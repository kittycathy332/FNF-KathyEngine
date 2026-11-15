package backend;

import flixel.FlxG;
import lime.graphics.Image;
import sys.io.File;
import sys.FileSystem;
import haxe.Json;

/**
 * 离线渲染驱动（"视频软件式"渲染，不是录屏）。
 *
 * 重要：不接管主循环。早期版本用 FlxG.vcr.paused + 手动 step()/draw()，
 * 与 FlxGame.onEnterFrame 在同一帧重入，导致 resetSubState() 交错调用、
 * CustomFadeTransition.create() 在 Paths 缓存不一致时崩溃（hxSehException）。
 *
 * 现在的做法只约束 FlxGame 自己的累加器：
 *  1. fixedTimestep = true + updateFramerate = fps
 *     → _stepMS = 1000/fps，updateElapsed() 恒算出 FlxG.elapsed = 1/fps
 *       （elapsed 是 (default,null) 只读属性，不需要写）。
 *  2. 把 _maxAccumulation 钉死为 1000/fps（== _stepMS）→ while 循环
 *     每帧最多执行一次 step()：慢帧不补跑、快帧攒够才跑，都不丢帧。
 *  3. drawFramerate 与 ClientPrefs.data.framerate 同步设为 fps，
 *     避免 FPSCounter 每帧把窗口帧率改回用户设定值。
 *  4. preUpdate 按帧号写 Conductor.songPosition 并置 _frameReady；
 *     postDraw 仅在 _frameReady 时截帧 —— 因为 draw() 每事件都会跑，
 *     而 step() 可能隔一次才跑，不这样做会截出重复帧。
 *  5. 截帧走 lime 官方 FlxG.stage.window.readPixels()（内部 glReadPixels +
 *     自动垂直翻转）。绝不能用 BitmapData.draw(FlxG.game)：硬件/tile 渲染下
 *     Cairo 递归渲染 Tilemap/shader 会触发 hxSehException（访问违规）。
 *
 * 所有异常都写进输出目录的 render_log.txt（release 构建看不到 trace）。
 * 设置来自 ClientPrefs.data 的 render* 字段；入口由 PlayState.create() 检测 requested 触发。
 */
class RenderClock
{
	/** 是否正在离线渲染 */
	public static var active:Bool = false;
	/** 设置页按钮置位，下一首进入 PlayState 时开始渲染 */
	public static var requested:Bool = false;
	/** 已处理的帧序号（下一帧的文件名） */
	public static var frame:Int = 0;
	public static var totalFrames:Int = 0;
	public static var outputDir:String = '';
	public static var lastError:String = '';

	static var _savedFixedTimestep:Bool = true;
	static var _savedTimeScale:Float = 1;
	static var _savedUpdateFramerate:Int = 60;
	static var _savedDrawFramerate:Int = 60;
	static var _savedFrameratePref:Int = 60;
	static var _savedMaxAccumulation:Float = 0;
	static var _savedMusicVolume:Float = 1;
	static var _savedVocalsVolume:Float = 1;
	static var _savedOppVolume:Float = 1;
	static var _savedFPSVisible:Bool = true;
	static var _savedLogVisible:Bool = true;
	static var _startSongPos:Float = 0;
	static var _fps:Int = 60;
	static var _width:Int = 1280;
	static var _height:Int = 720;
	static var _songName:String = '';
	static var _frameReady:Bool = false;
	static var _interrupted:String = '';
	static var _skippedSubFrames:Int = 0;
	/** 运行期时钟参数被外部改写并校正回来的次数（应为 0，非 0 说明还有别的干扰源） */
	static var _clockCorrections:Int = 0;
	static var _usePipe:Bool = false;
	static var _usePNG:Bool = true;
	static var _cutscenes:Array<String> = [];
	/** 游戏实际加载的伴奏 / 人声文件路径（由 PlayState 加载处登记，去重） */
	public static var songAudio:Array<String> = [];
	/** 渲染期间播放的即时音效：key=资源名，atMs=相对视频起点，volume=音量 */
	public static var soundEvents:Array<{key:String, atMs:Float, volume:Float}> = [];
	/** 倒计时段长度，换算成视频时间轴上的毫秒 */
	static var _leadMs:Float = 0;
	static var _firstError:String = '';
	static var _errorCount:Int = 0;
	static var _logLines:Array<String> = [];

	// ===== 超采样：把窗口 framebuffer 放大到目标分辨率，逻辑坐标保持不变 =====
	/** 目标分辨率与当前窗口不同，需要在首帧 resize 窗口 */
	static var _supersamplePending:Bool = false;
	/** applySupersampling 只执行一次（含失败情形） */
	static var _supersampleApplied:Bool = false;
	/** 渲染前的窗口物理尺寸，收尾时还原 */
	static var _savedWindowWidth:Int = 0;
	static var _savedWindowHeight:Int = 0;
	/** 渲染前的 scaleMode，收尾时还原 */
	static var _savedScaleMode:flixel.system.scaleModes.BaseScaleMode = null;
	/** 渲染前的逻辑尺寸（锁给 RenderScaleMode，保证 HUD 坐标不变） */
	static var _savedLogicWidth:Int = 0;
	static var _savedLogicHeight:Int = 0;
	/** readPixels 尺寸与目标不符、走了 CPU resize 的次数（超采样未生效的信号） */
	static var _cpuResizeCount:Int = 0;

	/** 由 PlayState.create() 调用；成功返回 true */
	public static function begin():Bool
	{
		if (active) return true;
		#if !desktop
		lastError = 'Offline render is only available on desktop targets.';
		trace('[RenderClock] ' + lastError);
		return false;
		#end
		var d = ClientPrefs.data;
		if (d == null)
		{
			lastError = 'ClientPrefs.data is null.';
			return false;
		}

		// 明确告知哪些配置尚未接入，避免"选了却没反应"
		if (d.renderBackend != 'Offline')
			trace('[RenderClock] backend "' + d.renderBackend + '" not implemented yet, using Offline.');
		if (d.renderInputSource == 'Replay')
			trace('[RenderClock] Replay input not wired yet, using BotPlay.');
		if (d.renderCutscene != 'Skip')
			trace('[RenderClock] cutscene join/freeze not implemented yet; cutscenes will play in realtime.');

		_fps = Std.int(Math.max(24, d.renderFPS));
		_width = Std.int(Math.max(320, d.renderWidth));
		_height = Std.int(Math.max(240, d.renderHeight));
		_songName = (PlayState.SONG != null) ? PlayState.SONG.song : 'song';

		// 超采样准备：目标分辨率与当前窗口 framebuffer 不一致时，首帧 resize 窗口
		// 并锁定逻辑坐标。begin() 在 create() 中途调用，此刻窗口尺寸稳定、可读。
		_savedWindowWidth = FlxG.stage.window.width;
		_savedWindowHeight = FlxG.stage.window.height;
		_savedLogicWidth = FlxG.width;
		_savedLogicHeight = FlxG.height;
		_savedScaleMode = FlxG.scaleMode;
		_supersamplePending = (_savedWindowWidth != _width || _savedWindowHeight != _height);
		_supersampleApplied = false;
		_cpuResizeCount = 0;

		var root:String = Sys.getCwd() + 'renders/';
		outputDir = root + sanitize(_songName) + '-' + DateTools.format(Date.now(), '%Y%m%d_%H%M%S') + '/';
		try
		{
			mkdir(root);
			mkdir(outputDir);
			mkdir(outputDir + 'frames/');
		}
		catch (e:Dynamic)
		{
			lastError = 'Cannot create output folder: ' + Std.string(e);
			trace('[RenderClock] ' + lastError);
			requested = false;
			return false;
		}

		_logLines = [];
		_firstError = '';
		_errorCount = 0;
		_frameReady = false;
		_interrupted = '';
		_skippedSubFrames = 0;
		_clockCorrections = 0;
		logLine('[begin] ' + _songName + ' / ' + _fps + 'fps / ' + _width + 'x' + _height);
		logLine('[output] ' + outputDir);
		logLine('[window] native=' + _savedWindowWidth + 'x' + _savedWindowHeight
			+ ' logic=' + _savedLogicWidth + 'x' + _savedLogicHeight
			+ ' -> supersample=' + _supersamplePending);

		// 交付形式分流：MP4 = rawvideo 直连 ffmpeg（最快）；PNG = 只落帧序列；
		// PNG+MP4 = 两者都做（保留逐帧素材，但仍有压缩与写盘开销）。
		_usePipe = (d.renderOutput == 'MP4' || d.renderOutput == 'PNG+MP4');
		_usePNG = (d.renderOutput == 'PNG' || d.renderOutput == 'PNG+MP4');
		_cutscenes = [];
		songAudio = [];
		soundEvents = [];
		_leadMs = 0;
		logLine('[mode] output=' + d.renderOutput + ' pipe=' + _usePipe + ' png=' + _usePNG
			+ ' encoder=' + d.renderEncoder + ' crf=' + d.renderCRF);
		if (_usePipe)
		{
			if (!RenderEncoder.begin(outputDir, _width, _height, _fps, d.renderCRF, d.renderEncoder, logLine))
			{
				logLine('[fallback] pipe unavailable -> PNG sequence mode');
				_usePipe = false;
				_usePNG = true;
			}
		}

		_savedFixedTimestep = FlxG.fixedTimestep;
		_savedTimeScale = FlxG.timeScale;
		_savedUpdateFramerate = FlxG.updateFramerate;
		_savedDrawFramerate = FlxG.drawFramerate;
		_savedFrameratePref = d.framerate;
		_savedMaxAccumulation = @:privateAccess FlxG.game._maxAccumulation;

		// 只约束累加器，不改 vcr.paused、不手动 step/draw —— 避免与引擎主循环重入
		FlxG.fixedTimestep = true;
		FlxG.timeScale = 1;
		FlxG.updateFramerate = _fps; // 决定 _stepMS 与 FlxG.elapsed
		// 刻意不动 drawFramerate / ClientPrefs.data.framerate：
		// 窗口仍按玩家设定的帧率跑，虚拟时间轴只由 stepMS + 累加器上限决定，
		// 两者彻底解耦，也避免与 FPS 计数器的自动调速互相打架。
		// set_updateFramerate() 可能触碰 _maxAccumulation，钉死放在最后
		@:privateAccess FlxG.game._maxAccumulation = 1000 / _fps;
		FlxG.random.initialSeed = d.renderSeed;
		logLine('[clock] stepMS=' + (1000 / _fps) + 'ms pinned; drawFramerate left at '
			+ _savedDrawFramerate + ' (user pref ' + _savedFrameratePref + ')');

		// 倒计时段的起点与 PlayState.startCountdown() 的赋值保持一致
		_startSongPos = (d.renderRange == 'SongOnly')
			? Conductor.offset
			: -Conductor.crochet * 5 + Conductor.offset;
		frame = 0;
		totalFrames = 0;
		lastError = '';

		if (d.renderHideOverlay)
		{
			if (Main.fpsLayer != null) { _savedFPSVisible = Main.fpsLayer.visible; Main.fpsLayer.visible = false; }
			if (Main.gameLogVar != null) { _savedLogVisible = Main.gameLogVar.visible; Main.gameLogVar.visible = false; }
		}

		// preUpdate 只在真正 step() 过的帧 dispatch；postDraw 每次 draw() 都会 dispatch
		if (FlxG.signals.preUpdate.has(onPreUpdate)) FlxG.signals.preUpdate.remove(onPreUpdate);
		if (FlxG.signals.postDraw.has(onPostDraw)) FlxG.signals.postDraw.remove(onPostDraw);
		FlxG.signals.preUpdate.add(onPreUpdate);
		FlxG.signals.postDraw.add(onPostDraw);
		// 渲染期间任何 state 切换 / 游戏 reset 都视为中断，必须安全收尾：
		// 否则全局监听会继续录菜单、全局帧率设置不恢复、ffmpeg 管道不关闭导致 MP4 损坏。
		if (FlxG.signals.preStateSwitch.has(onStateLeaving)) FlxG.signals.preStateSwitch.remove(onStateLeaving);
		if (FlxG.signals.preGameReset.has(onStateLeaving)) FlxG.signals.preGameReset.remove(onStateLeaving);
		FlxG.signals.preStateSwitch.add(onStateLeaving);
		FlxG.signals.preGameReset.add(onStateLeaving);

		active = true;
		requested = false;
		trace('[RenderClock] begin: $_songName / $_fps fps / ${_width}x$_height -> ' + outputDir);
		return true;
	}

	/** 只在 FlxGame 真正 step() 过的一帧里 dispatch */
	static function onPreUpdate():Void
	{
		if (!active) return;
		// create() 已完成，首帧把窗口 framebuffer 放大到目标分辨率
		if (!_supersampleApplied) applySupersampling();
		// 暂停菜单 / 淡入转场等 subState 打开时冻结渲染时钟：不推进帧号、不截帧。
		// 否则暂停界面会被录进成片，且虚拟时间轴会继续往前跑。
		if (FlxG.state != null && FlxG.state.subState != null)
		{
			_frameReady = false;
			_skippedSubFrames++;
			return;
		}
		_frameReady = true;
		var rate:Float = (PlayState.instance != null) ? PlayState.instance.playbackRate : 1;
		Conductor.songPosition = _startSongPos + frame * (1000 / _fps) * rate;
	}

	/** state 切换 / resetGame：中断渲染 */
	static function onStateLeaving():Void
	{
		if (active) abort('state switch / game reset');
	}

	/**
	 * 首帧（create 已完成后）把窗口 framebuffer 放大到目标分辨率。
	 *
	 * 必须在 create() 之后做：begin() 在 PlayState.create() 中途调用，若那时
	 * 就 resizeGame，紧随其后的 PlayState 自适应缩放模式切换（约 842 行）会
	 * 把我们装好的 RenderScaleMode 覆盖掉。preUpdate 首帧时 create 已完成，
	 * 此刻切换最稳。
	 *
	 * 逻辑坐标锁在 _savedLogicWidth x _savedLogicHeight，因此所有 1280x720
	 * 硬编码的 HUD / 相机坐标都不受影响；readPixels 读回的是放大后的原生
	 * framebuffer，不再需要 CPU 插值拉伸 —— 这才是真正的超采样。
	 */
	static function applySupersampling():Void
	{
		if (_supersampleApplied) return;
		_supersampleApplied = true;
		if (!_supersamplePending)
		{
			logLine('[supersample] native window matches target, no resize needed');
			return;
		}
		#if desktop
		// create() 到这里已完成（含 PlayState 842 行的自适应 width 切换）。
		// 以"此刻"的 scaleMode / 逻辑尺寸为还原基准，而不是 begin() 时的旧值，
		// 这样收尾能精确还原到渲染开始前的真实现场。
		_savedLogicWidth = FlxG.width;
		_savedLogicHeight = FlxG.height;
		_savedScaleMode = FlxG.scaleMode;
		try
		{
			// 用锁定逻辑尺寸的 scaleMode 接管 measure，再改窗口物理尺寸
			FlxG.scaleMode = new flixel.system.scaleModes.RenderScaleMode(_savedLogicWidth, _savedLogicHeight);
			FlxG.stage.window.resize(_width, _height);
			// resize 事件是异步的，主动 measure 一次让本帧就生效
			FlxG.resizeGame(_width, _height);
			logLine('[supersample] window ' + _savedWindowWidth + 'x' + _savedWindowHeight
				+ ' -> ' + _width + 'x' + _height + ' / logic locked '
				+ FlxG.width + 'x' + FlxG.height
				+ ' / scale ' + FlxG.scaleMode.scale.x + ',' + FlxG.scaleMode.scale.y);
		}
		catch (e:Dynamic)
		{
			// resize 失败就退回旧行为：CPU resize readPixels 结果（至少不会崩）
			logLine('[supersample] FAILED: ' + Std.string(e) + ' -> CPU resize fallback');
			try { FlxG.scaleMode = _savedScaleMode; } catch (e2:Dynamic) {}
		}
		#else
		logLine('[supersample] skipped (not desktop target)');
		#end
	}

	/** cleanup 时把窗口分辨率 / scaleMode 还原到渲染前 */
	static function restoreWindow():Void
	{
		if (!_supersamplePending || !_supersampleApplied) return;
		#if desktop
		try
		{
			FlxG.stage.window.resize(_savedWindowWidth, _savedWindowHeight);
			FlxG.scaleMode = _savedScaleMode;
			FlxG.resizeGame(_savedWindowWidth, _savedWindowHeight);
			logLine('[supersample] restored window ' + _savedWindowWidth + 'x' + _savedWindowHeight);
		}
		catch (e:Dynamic)
		{
			logLine('[supersample] restore FAILED: ' + Std.string(e));
		}
		#end
		_supersampleApplied = false;
	}

	/**
	 * 帧末把时钟参数钉回去。
	 * updateFramerate 决定 _stepMS → FlxG.elapsed（FlxTimer / 倒计时的步长）；
	 * _maxAccumulation 决定一帧最多 step 几次（超过一帧就丢画面）。
	 * 任何外部改写都会让虚拟时间轴与画面脱节，这里统一兜底。
	 */
	static function enforceClock():Void
	{
		if (FlxG.updateFramerate != _fps) { FlxG.updateFramerate = _fps; _clockCorrections++; }
		if (FlxG.timeScale != 1) { FlxG.timeScale = 1; _clockCorrections++; }
		var stepMs:Float = 1000 / _fps;
		var cur:Float = @:privateAccess FlxG.game._maxAccumulation;
		if (cur > stepMs)
		{
			@:privateAccess FlxG.game._maxAccumulation = stepMs;
			_clockCorrections++;
		}
	}

	/** 每帧一次：截屏落盘，然后推进帧号 */
	static function onPostDraw():Void
	{
		if (!active || !_frameReady) return;
		_frameReady = false;
		var path:String = outputDir + 'frames/frame_' + StringTools.lpad(Std.string(frame), '0', 6) + '.png';
		try
		{
			// lime 官方的窗口 framebuffer 读回（内部 glReadPixels + 自动垂直翻转）。
			// 不能用 BitmapData.draw(FlxG.game)：硬件/tile 渲染下 Cairo 会递归渲染
			// Tilemap / shader 节点并触发 hxSehException（访问违规）。
			var img:Image = FlxG.stage.window.readPixels(null);
			if (img == null) throw 'Window.readPixels returned null';
			// readPixels 尺寸 = 窗口逻辑尺寸 × 系统 DPI scale（见 NativeWindow.hx:350）。
			//  - 等于目标：超采样完美命中；
			//  - 大于目标：DPI>1 的额外超采样，缩到目标是高质量降采样（更好）；
			//  - 小于目标：窗口 resize 没生效 → 放大糊，记入日志以便排查。
			// 无论哪种，都 resize 到目标，保证写进 ffmpeg 的字节数精确匹配 rawvideo 声明。
			var nativeW:Int = img.width;
			var nativeH:Int = img.height;
			if (nativeW < _width || nativeH < _height)
			{
				_cpuResizeCount++;
				if (_cpuResizeCount <= 2)
					logLine('[capture] readPixels ' + nativeW + 'x' + nativeH + ' < target '
						+ _width + 'x' + _height + ' -> UPSCALE (supersample INEFFECTIVE, blurry)');
			}
			if (nativeW != _width || nativeH != _height)
			{
				if (frame == 0)
					logLine('[capture] first frame native ' + nativeW + 'x' + nativeH
						+ ' -> target ' + _width + 'x' + _height
						+ (nativeW > _width ? ' (DPI downscale)' : ''));
				try { img.resize(_width, _height); }
				catch (e:Dynamic) logLine('[resize skipped] ' + Std.string(e) + ' -> native ' + nativeW + 'x' + nativeH);
			}
			var pngLen:Int = 0;
			if (_usePNG)
			{
				var bytes:haxe.io.Bytes = img.encode(); // 默认 PNG
				if (bytes == null) throw 'Image.encode returned null';
				pngLen = bytes.length;
				File.saveBytes(path, bytes);
			}
			if (_usePipe)
			{
				// img.buffer.data.buffer 就是 readPixels 得到的 RGBA Bytes，零拷贝写 stdin
				RenderEncoder.writeFrame(img.buffer.data.buffer);
			}
			if (frame == 0)
			{
				var px = img.buffer.data;
				var mid:Int = (((img.height >> 1) * img.width) + (img.width >> 1)) * 4;
				logLine('[first frame] ok size=' + img.width + 'x' + img.height
					+ ' format=' + Std.string(img.buffer.format)
					+ ' pngBytes=' + pngLen
					+ ' px0=' + px[0] + ',' + px[1] + ',' + px[2] + ',' + px[3]
					+ ' center=' + px[mid] + ',' + px[mid + 1] + ',' + px[mid + 2]);
			}
		}
		catch (e:Dynamic)
		{
			_errorCount++;
			lastError = Std.string(e);
			if (_firstError == '')
			{
				_firstError = 'frame ' + frame + ': ' + lastError;
				logLine('[first capture error] ' + _firstError);
			}
			if (_errorCount <= 3) trace('[RenderClock] frame $frame: ' + lastError);
		}

		frame++;
		// 帧末把时钟参数钉回去：若 FPS 计数器或模组脚本在本帧改过，
		// 下一帧的 updateElapsed() 就会用错 _stepSeconds / 累加器上限。
		enforceClock();
		// 连续失败就别空转整首歌了，直接收尾并把错误交给弹窗 / 日志
		if (_errorCount >= 10 && frame < 20)
		{
			logLine('[abort] capture failed on first frames');
			finish();
			return;
		}
		if (totalFrames > 0 && frame >= totalFrames) finish();
	}

	/** startSong() 里调用：冻结音频并取得总帧数 */
	public static function onSongStart(songLengthMs:Float):Void
	{
		if (!active) return;
		var d = ClientPrefs.data;
		var rate:Float = (PlayState.instance != null) ? PlayState.instance.playbackRate : 1;
		if (rate <= 0) rate = 1;
		var leadMs:Float = (d != null && d.renderRange == 'SongOnly') ? 0 : Conductor.crochet * 5;
		// songPosition 每帧推进 (1000/fps)*rate，故总帧数要除以 rate；
		// 音轨在视频时间轴上的起点是 leadMs/rate（倒计时段）。
		_leadMs = leadMs / rate;
		totalFrames = Math.ceil((leadMs + songLengthMs) / (1000 / _fps) / rate);
		freezeAudio();
		logLine('[song] length=' + songLengthMs + 'ms leadMs=' + _leadMs
			+ ' rate=' + rate + ' totalFrames=' + totalFrames);
		trace('[RenderClock] totalFrames = ' + totalFrames);
	}

	/**
	 * 渲染期间不播放任何声音：音轨由原始 Inst / Voices 在合成阶段离线混入。
	 * 保留 FlxSound 对象，因为 songLength / vocals.length 等仍被大量读取。
	 */
	public static function freezeAudio():Void
	{
		if (!active) return;
		try
		{
			var music = FlxG.sound.music;
			if (music != null)
			{
				_savedMusicVolume = music.volume;
				music.onComplete = null; // 否则音频先放完会提前触发 finishSong
				music.pause();
				music.volume = 0;
			}
			var ps = PlayState.instance;
			if (ps != null)
			{
				if (ps.vocals != null) { _savedVocalsVolume = ps.vocals.volume; ps.vocals.pause(); ps.vocals.volume = 0; }
				if (ps.opponentVocals != null) { _savedOppVolume = ps.opponentVocals.volume; ps.opponentVocals.pause(); ps.opponentVocals.volume = 0; }
			}
		}
		catch (e:Dynamic) logLine('[freezeAudio error] ' + Std.string(e));
	}

	/** 公共清理：移除全部全局钩子、恢复全局状态。不写日志、不弹窗、不碰编码器 */
	static function cleanup():Void
	{
		if (!active) return;
		active = false;
		_frameReady = false;
		requested = false; // 中断后不要在下一次进 PlayState 时又自动开渲
		FlxG.signals.preUpdate.remove(onPreUpdate);
		FlxG.signals.postDraw.remove(onPostDraw);
		FlxG.signals.preStateSwitch.remove(onStateLeaving);
		FlxG.signals.preGameReset.remove(onStateLeaving);
		var d = ClientPrefs.data;
		if (d != null) d.framerate = _savedFrameratePref;
		FlxG.drawFramerate = _savedDrawFramerate;
		FlxG.updateFramerate = _savedUpdateFramerate;
		FlxG.fixedTimestep = _savedFixedTimestep;
		FlxG.timeScale = _savedTimeScale;
		// 恢复累加器上限要放在最后：set_drawFramerate() 会重写它
		@:privateAccess FlxG.game._maxAccumulation = _savedMaxAccumulation;
		try
		{
			var music = FlxG.sound.music;
			if (music != null) music.volume = _savedMusicVolume;
			var ps = PlayState.instance;
			if (ps != null)
			{
				if (ps.vocals != null) ps.vocals.volume = _savedVocalsVolume;
				if (ps.opponentVocals != null) ps.opponentVocals.volume = _savedOppVolume;
			}
		}
		catch (e:Dynamic) {}
		if (Main.fpsLayer != null) Main.fpsLayer.visible = _savedFPSVisible;
		if (Main.gameLogVar != null) Main.gameLogVar.visible = _savedLogVisible;
		// 窗口物理分辨率与 scaleMode 最后还原（会触发 resizeGame）
		restoreWindow();
	}

	/** 正常收尾：完整合成（混音 + 过场拼接） */
	public static function finish():Void
	{
		if (!active) return;
		cleanup();
		var d = ClientPrefs.data;
		var videoPath:String = '';
		if (_usePipe)
		{
			var rate:Float = (PlayState.instance != null) ? PlayState.instance.playbackRate : 1;
			if (rate <= 0) rate = 1;
			videoPath = RenderEncoder.finish({
				song: _songName,
				rate: rate,
				offsetMs: Conductor.offset,
				mixAudio: (d != null && d.renderAudio),
				cutscenes: _cutscenes,
				songAudio: songAudio,
				soundEvents: soundEvents,
				leadMs: _leadMs,
				durationSec: frame / _fps
			}, logLine);
		}
		logLine('[finish] frames=' + frame + ' / captureErrors=' + _errorCount
			+ ' / skippedSubFrames=' + _skippedSubFrames
			+ ' / clockCorrections=' + _clockCorrections
			+ ' / cpuResizedFrames=' + _cpuResizeCount
			+ (_firstError != '' ? ' / firstError=' + _firstError : '')
			+ ' / video=' + videoPath);
		if (_cpuResizeCount > 0)
			logLine('[quality] WARNING: readPixels was SMALLER than target on ' + _cpuResizeCount
				+ ' frames (window resize blocked?). Output was CPU-upscaled and may look soft.');
		writeManifest(videoPath, '');

		var summary:String = Language.get('render_finish_popup') + '\n' + outputDir
			+ '\nframes: ' + frame
			+ (videoPath != '' ? '\nvideo: ' + videoPath : '')
			+ (_errorCount > 0 ? '\nERRORS: ' + _errorCount + '\n' + _firstError : '');
		logLine('[summary] ' + StringTools.replace(summary, '\n', ' | '));
		trace('[RenderClock] done: ' + frame + ' frames -> ' + outputDir);
		showSummary(summary);
	}

	/**
	 * 中断收尾：退出 PlayState / 切到别的 state / 关闭游戏时调用。
	 * 只关管道拿到可播放的 partial.mp4，跳过耗时的混音与过场拼接。
	 */
	public static function abort(reason:String, silent:Bool = false):Void
	{
		if (!active) return;
		_interrupted = reason;
		cleanup();
		var partial:String = _usePipe ? RenderEncoder.abort(logLine) : '';
		logLine('[abort] reason=' + reason + ' frames=' + frame
			+ ' / skippedSubFrames=' + _skippedSubFrames
			+ ' / clockCorrections=' + _clockCorrections + ' / partial=' + partial);
		writeManifest(partial, reason);
		if (!silent)
		{
			var summary:String = Language.get('render_abort_popup') + '\n' + reason
				+ '\n' + outputDir + '\nframes: ' + frame
				+ (partial != '' ? '\npartial: ' + partial : '');
			logLine('[summary] ' + StringTools.replace(summary, '\n', ' | '));
			showSummary(summary);
		}
	}

	/** 只弹提示，不自动切状态：避免在转场创建过程中再引入一次状态切换 */
	static function showSummary(summary:String):Void
	{
		haxe.Timer.delay(function()
		{
			try { backend.CoolUtil.showPopUp(summary, Language.get('render_menu')); }
			catch (e:Dynamic) logLine('[popup error] ' + Std.string(e));
		}, 200);
	}

	/** 由 PlayState 音频加载处调用：登记游戏实际加载的伴奏 / 人声文件（去重） */
	public static function registerSongAudio(path:String):Void
	{
		if (!active || path == null || !FileSystem.exists(path)) return;
		if (songAudio.indexOf(path) < 0)
		{
			songAudio.push(path);
			logLine('[audio] song track: ' + path);
		}
	}

	/** 由 PlayState 播放即时音效处调用：把虚拟时间换算成视频时间轴上的毫秒 */
	public static function registerSound(key:String, volume:Float):Void
	{
		if (!active || key == null) return;
		var rate:Float = (PlayState.instance != null) ? PlayState.instance.playbackRate : 1;
		if (rate <= 0) rate = 1;
		var atMs:Float = (Conductor.songPosition - _startSongPos) / rate;
		soundEvents.push({key: key, atMs: atMs, volume: volume});
		logLine('[audio] sfx: ' + key + ' at ' + Math.round(atMs) + 'ms vol=' + volume);
	}

	/** 由 PlayState.startVideo() 调用：记录过场文件路径，合成阶段用 concat 拼接 */
	public static function registerCutscene(path:String):Void
	{
		if (active && path != null && _cutscenes.indexOf(path) < 0)
		{
			_cutscenes.push(path);
			logLine('[cutscene] registered ' + path);
		}
	}

	static function writeManifest(videoPath:String, interrupted:String):Void
	{
		try
		{
			var d = ClientPrefs.data;
			var obj:Dynamic = {
				song: _songName,
				fps: _fps,
				width: _width,
				height: _height,
				frames: frame,
				videoPath: videoPath,
				interrupted: interrupted,
				skippedSubFrames: _skippedSubFrames,
				clockCorrections: _clockCorrections,
				captureErrors: _errorCount,
				firstError: _firstError,
				encoder: d.renderEncoder,
				outputMode: d.renderOutput,
				cutscenes: _cutscenes,
				backend: d.renderBackend,
				inputSource: d.renderInputSource,
				output: d.renderOutput,
				range: d.renderRange,
				cutscene: d.renderCutscene,
				mixAudio: d.renderAudio,
				crf: d.renderCRF,
				seed: d.renderSeed,
				playbackRate: (PlayState.instance != null ? PlayState.instance.playbackRate : 1),
				offset: Conductor.offset,
				noteOffset: d.noteOffset,
				framesDir: 'frames/'
			};
			File.saveContent(outputDir + 'manifest.json', Json.stringify(obj));
		}
		catch (e:Dynamic) logLine('[writeManifest error] ' + Std.string(e));
	}

	/** 写日志文件：release 构建会关掉 trace，这是唯一的可见诊断通道 */
	static function logLine(s:String):Void
	{
		_logLines.push(DateTools.format(Date.now(), '%H:%M:%S') + ' ' + s);
		try { File.saveContent(outputDir + 'render_log.txt', _logLines.join('\n')); }
		catch (e:Dynamic) {}
	}

	static function mkdir(path:String):Void
	{
		if (!FileSystem.exists(path)) FileSystem.createDirectory(path);
	}

	static function sanitize(s:String):String
	{
		return ~/[^A-Za-z0-9_\-]/g.replace(s, '_');
	}
}
