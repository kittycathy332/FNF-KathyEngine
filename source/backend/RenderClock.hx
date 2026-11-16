package backend;

import flixel.FlxG;
import lime.graphics.Image;
import sys.io.File;
import sys.FileSystem;
import haxe.Json;

/**
 * 一条自动捕获的即时音效。
 * atMs 是视频时间轴上的起点，durMs <= 0 表示"一直播到视频结束"。
 */
typedef SfxTrack = {
	var path:String;
	var atMs:Float;
	var volume:Float;
	var looped:Bool;
	var durMs:Float;
}

/**
 * 离线渲染驱动（"视频软件式"渲染，不是录屏）。
 *
 * 重要：不接管主循环。早期版本用 FlxG.vcr.paused + 手动 step()/draw()，
 * 与 FlxGame.onEnterFrame 在同一帧重入，导致 resetSubState() 交错调用、
 * CustomFadeTransition.create() 在 Paths 缓存不一致时崩溃（hxSehException）。
 *
 * 现在的做法只约束 FlxGame 自己的累加器：
 *  1. fixedTimestep = true + updateFramerate = drawFramerate = stage.frameRate = fps
 *     → _stepMS = 1000/fps，updateElapsed() 恒算出 FlxG.elapsed = 1/fps
 *       （elapsed 是 (default,null) 只读属性，不需要写）。
 *  2. 把 _maxAccumulation 钉死为 1000/fps（== _stepMS）→ while 循环
 *     每帧最多执行一次 step()：慢帧不补跑、快帧攒够才跑，都不丢帧。
 *     注意 set_drawFramerate() 会把 _maxAccumulation 改写成 2000/fps - 1（≈两步），
 *     所以每次设定帧率之后都必须重新钉一次，否则会"跑两步、只截一帧"。
 *  3. ClientPrefs.data.framerate 也同步改成 fps，让读它的模组 / 脚本保持一致。
 *  4. preUpdate 按帧号写 Conductor.songPosition 并置 _frameReady；
 *     postDraw 仅在 _frameReady 时截帧 —— 因为 draw() 每事件都会跑，
 *     而 step() 可能隔一次才跑，不这样做会截出重复帧。
 *  5. 开场淡入转场（CustomFadeTransition）在渲染时被 MusicBeatState 跳过：
 *     它是 subState，若照旧打开会让 PlayState.update 停摆而 FlxTimer 继续走，
 *     造成倒计时被压快 + 开场丢 0.5s（45 帧 @90fps）。
 *  6. 截帧走 lime 官方 FlxG.stage.window.readPixels()（内部 glReadPixels +
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
	static var _savedStageFrameRate:Float = 60;
	static var _savedFrameratePref:Int = 60;
	static var _savedAutoPause:Bool = true;
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
	/** 真正执行过的 step() 次数。与 frame 数对比即可判断是否"跑了逻辑却没截帧" */
	static var _stepCount:Int = 0;
	/** 有 step 但没有对应截帧的次数（>0 说明画面上真丢了一帧的内容） */
	static var _lostSteps:Int = 0;
	/** 分阶段耗时统计（毫秒累计）：定位渲染瓶颈在读回还是管道写入 */
	static var _perfReadMs:Float = 0;
	static var _perfWriteMs:Float = 0;
	static var _perfFrames:Int = 0;
	static var _usePipe:Bool = false;
	static var _usePNG:Bool = true;
	static var _cutscenes:Array<String> = [];
	/** 游戏实际加载的伴奏 / 人声文件路径（由 PlayState 加载处登记，去重） */
	public static var songAudio:Array<String> = [];
	/** 渲染期间播放的即时音效：key=资源名，atMs=相对视频起点，volume=音量 */
	public static var soundEvents:Array<{key:String, atMs:Float, volume:Float}> = [];
	/**
	 * 渲染期间自动捕获的即时音效。
	 * 与 soundEvents 的区别：soundEvents 靠调用点手工登记（倒计时），
	 * 这里由每帧扫描 Flixel 声音池自动得到 —— 事件、脚本、stage、FlxG.sound.play()
	 * 播放的音频都能覆盖，不需要改任何调用点。
	 */
	public static var sfxTimeline:Array<SfxTrack> = [];
	/** 正在播放中的音效（FlxSound 对象 → 轨道），停止后移入 sfxTimeline */
	static var _activeSfx:Map<flixel.sound.FlxSound, SfxTrack> = new Map();
	/** Sound 资源对象 → 磁盘文件路径 的反查缓存（来源 Paths.currentTrackedSounds） */
	static var _soundPathCache:Map<openfl.media.Sound, String> = new Map();
	/** 本次渲染捕获到的音效总数（写日志 / manifest 用） */
	static var _sfxSeen:Int = 0;
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
		_stepCount = 0;
		_lostSteps = 0;
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
		sfxTimeline = [];
		_activeSfx = new Map();
		_soundPathCache = new Map();
		_sfxSeen = 0;
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
		_savedStageFrameRate = (FlxG.stage != null) ? FlxG.stage.frameRate : _savedDrawFramerate;
		_savedFrameratePref = d.framerate;
		_savedMaxAccumulation = @:privateAccess FlxG.game._maxAccumulation;

		// 只约束累加器，不改 vcr.paused、不手动 step/draw —— 避免与引擎主循环重入
		FlxG.fixedTimestep = true;
		FlxG.timeScale = 1;

		// ===== 渲染期：把所有 FPS / 更新相关设定强行改为输出帧率 =====
		// 顺序很重要：set_drawFramerate() 内部会把 _maxAccumulation 改写成
		// 2000/fps - 1（≈ 两步），set_updateFramerate() 又会重算 _stepMS/_stepSeconds。
		// 所以必须在两者之后再把累加器钉成恰好一步，否则单帧可能跑两次 step()
		// 却只截一张图 —— 帧数对得上，画面内容却跳过一帧（= 肉眼丢帧）。
		FlxG.updateFramerate = _fps; // 决定 _stepMS / _stepSeconds / FlxG.elapsed
		FlxG.drawFramerate = _fps; // 决定 stage.frameRate（窗口发起 onEnterFrame 的频率）
		if (FlxG.stage != null) FlxG.stage.frameRate = _fps;
		d.framerate = _fps; // 让读 ClientPrefs.data.framerate 的模组 / 脚本也保持一致
		// 渲染期间禁止失焦自动暂停：FlxGame.onEnterFrame 在 _lostFocus && autoPause 时
		// 整帧 return，会让长时间渲染中途停住（且 step 与截帧配对全乱）。
		_savedAutoPause = FlxG.autoPause;
		FlxG.autoPause = false;
		@:privateAccess FlxG.game._maxAccumulation = 1000 / _fps;
		FlxG.random.initialSeed = d.renderSeed;
		logLine('[clock] ALL fps pinned to ' + _fps + ': update=' + FlxG.updateFramerate
			+ ' draw=' + FlxG.drawFramerate
			+ ' stage=' + ((FlxG.stage != null) ? Std.string(FlxG.stage.frameRate) : 'n/a')
			+ ' pref=' + d.framerate
			+ ' stepMS=' + (1000 / _fps) + ' maxAccum=' + (1000 / _fps)
			+ ' (was update=' + _savedUpdateFramerate + ' draw=' + _savedDrawFramerate
			+ ' stage=' + _savedStageFrameRate + ' pref=' + _savedFrameratePref + ')');

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

		// 只有暂停菜单才冻结时钟：暂停界面不属于成片，且此时游戏逻辑停摆，
		// 继续推进虚拟时间会在恢复后造成跳变。
		//
		// 开场淡入转场（CustomFadeTransition）、对话等 subState 是成片的一部分，
		// 必须照常推进帧号并截帧 —— preUpdate/postDraw 是全局信号，subState 打开时
		// 依然每帧派发，所以这里不 return 就能把转场动画完整录进开头。
		//
		// 关键：旧版"见到任何 subState 就冻结"本身才是丢帧元凶 —— 转场期间
		// PlayState.update 停摆、FlxTimer（倒计时）照走，虚拟时钟却不动，
		// 于是倒计时空转 45 步（0.5s × 90fps）而画面一帧没录。现在虚拟时钟
		// 与 FlxTimer 同步推进，倒计时恢复原速，转场画面也进成片。
		if (isPauseOpen())
		{
			_frameReady = false;
			_skippedSubFrames++;
			return;
		}

		// 上一个 step 还没等到 draw() 就又 step 了一次 → 中间那帧画面永远丢了
		if (_frameReady) _lostSteps++;
		_stepCount++;

		_frameReady = true;
		var rate:Float = (PlayState.instance != null) ? PlayState.instance.playbackRate : 1;
		Conductor.songPosition = _startSongPos + frame * (1000 / _fps) * rate;
	}

	/**
	 * 暂停菜单是否打开。以 PlayState.paused 为主判据（最可靠、不依赖类名反射），
	 * 类名只作兜底。用 inString 匹配避免 cpp 目标下 DCE 剥掉类元数据后反射失败。
	 */
	static function isPauseOpen():Bool
	{
		var ps = PlayState.instance;
		if (ps != null && ps.paused) return true;
		if (FlxG.state == null || FlxG.state.subState == null) return false;
		var name:String = Type.getClassName(Type.getClass(FlxG.state.subState));
		return name != null && name.indexOf('PauseSubState') >= 0;
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
	 * 帧末把全部帧率参数钉回去。
	 *
	 * 四个量必须同时正确，缺一个都会让"逻辑步"和"截帧"错位：
	 *  - updateFramerate → _stepMS / _stepSeconds → FlxG.elapsed（FlxTimer、补间的步长）
	 *  - drawFramerate   → stage.frameRate（窗口多久调一次 onEnterFrame）
	 *  - ClientPrefs.data.framerate → 模组 / 脚本读它做自适应同步
	 *  - _maxAccumulation → 单帧最多跑几次 step()，必须 == 一步，否则会"跑两步截一帧"
	 *
	 * 注意 set_drawFramerate() 会把 _maxAccumulation 改写成 2000/fps - 1，
	 * 所以累加器的修正必须放在最后。
	 */
	static function enforceClock():Void
	{
		if (FlxG.updateFramerate != _fps)
		{
			FlxG.updateFramerate = _fps;
			_clockCorrections++;
		}
		if (FlxG.drawFramerate != _fps)
		{
			FlxG.drawFramerate = _fps;
			_clockCorrections++;
		}
		if (FlxG.stage != null && FlxG.stage.frameRate != _fps)
		{
			FlxG.stage.frameRate = _fps;
			_clockCorrections++;
		}
		var d = ClientPrefs.data;
		if (d != null && d.framerate != _fps)
		{
			d.framerate = _fps;
			_clockCorrections++;
		}
		if (FlxG.timeScale != 1)
		{
			FlxG.timeScale = 1;
			_clockCorrections++;
		}
		// 放在最后：set_drawFramerate() 会覆盖它
		var stepMs:Float = 1000 / _fps;
		var cur:Float = @:privateAccess FlxG.game._maxAccumulation;
		if (Math.abs(cur - stepMs) > 0.01)
		{
			@:privateAccess FlxG.game._maxAccumulation = stepMs;
			_clockCorrections++;
		}
	}

	/** 每帧一次：截屏落盘，然后推进帧号 */
	static function onPostDraw():Void
	{
		if (!active) return;
		if (!_frameReady)
		{
			// 这一帧没跑 step()（窗口帧率高于输出帧率时会出现），不截帧，只做时钟纠错。
			// 截帧与 step 严格 1:1，才能保证成片每个渲染帧恰好是一步逻辑。
			enforceClock();
			return;
		}
		_frameReady = false;
		// 先扫描这一帧的声音池：本帧新起播的音效起点就是当前帧号，
		// 放在截帧之前才能把"这一帧刚开始的声音"算在正确的时间点上。
		scanSounds();
		var path:String = outputDir + 'frames/frame_' + StringTools.lpad(Std.string(frame), '0', 6) + '.png';
		var tRead0:Float = Date.now().getTime();
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
			var tRead1:Float = Date.now().getTime();
			if (_usePipe)
			{
				// img.buffer.data.buffer 就是 readPixels 得到的 RGBA Bytes，零拷贝写 stdin
				RenderEncoder.writeFrame(img.buffer.data.buffer);
			}
			// 分阶段计时：每 600 帧汇总一次，定位瓶颈在读回 / 翻转还是管道写入
			_perfReadMs += tRead1 - tRead0;
			_perfWriteMs += Date.now().getTime() - tRead1;
			_perfFrames++;
			if (_perfFrames >= 600)
			{
				logLine('[perf] ' + _perfFrames + ' frames: read+flip='
					+ Math.round(_perfReadMs / _perfFrames * 100) / 100 + 'ms'
					+ ' writePipe=' + Math.round(_perfWriteMs / _perfFrames * 100) / 100 + 'ms'
					+ ' (at frame ' + frame + ')');
				_perfReadMs = 0;
				_perfWriteMs = 0;
				_perfFrames = 0;
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
		_activeSfx = new Map(); // 释放对 FlxSound / Sound 的强引用，避免跨曲目残留
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
		FlxG.autoPause = _savedAutoPause;
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
		flushSounds(); // 仍在播放的音效按"播到视频结束"归档，必须早于 cleanup
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
				sfx: sfxTimeline,
				leadMs: _leadMs,
				durationSec: frame / _fps
			}, logLine);
		}
		logLine('[finish] frames=' + frame + ' / steps=' + _stepCount
			+ ' / lostSteps=' + _lostSteps
			+ ' / captureErrors=' + _errorCount
			+ ' / skippedSubFrames=' + _skippedSubFrames
			+ ' / clockCorrections=' + _clockCorrections
			+ ' / cpuResizedFrames=' + _cpuResizeCount
			+ ' / sfxCaptured=' + _sfxSeen
			+ (_firstError != '' ? ' / firstError=' + _firstError : '')
			+ ' / video=' + videoPath);
		if (_lostSteps > 0)
			logLine('[timing] WARNING: ' + _lostSteps + ' logic steps had no captured frame '
				+ '(accelerator allowed >1 step per draw). Content skipped.');
		if (frame != _stepCount + _skippedSubFrames)
			logLine('[timing] note: frames(' + frame + ') != steps(' + _stepCount
				+ ') + skipped(' + _skippedSubFrames + ')');
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
		flushSounds();
		cleanup();
		var partial:String = _usePipe ? RenderEncoder.abort(logLine) : '';
		logLine('[abort] reason=' + reason + ' frames=' + frame + ' / steps=' + _stepCount
			+ ' / lostSteps=' + _lostSteps
			+ ' / skippedSubFrames=' + _skippedSubFrames
			+ ' / sfxCaptured=' + _sfxSeen
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

	/** 当前虚拟时间在视频时间轴上的毫秒（帧号 × 帧间隔，不受 timeScale 影响） */
	static function videoMs():Float
		return frame * (1000 / _fps);

	/**
	 * 每帧扫描 Flixel 的声音池，自动捕获"曲目中途播放的音频"。
	 *
	 * 为什么扫描而不是改调用点：模组播放音频的路径太多 —— PlayState 事件、
	 * HScript / Stage 脚本、FlxG.sound.play()、playMusic()、直接往
	 * defaultSoundGroup 里塞……它们最终都会落在 FlxG.sound.list 或某个
	 * FlxSoundGroup 里，扫描是唯一能全覆盖、又不必改每个调用点的做法。
	 *
	 * 主音轨（Inst / Voices）由 songAudio 通道整体混入，这里必须排除，
	 * 否则会与延后 leadMs 的主音轨叠成双份。
	 */
	static function scanSounds():Void
	{
		if (FlxG.sound == null) return;
		var now:Float = videoMs();

		// 1) 收集当前所有音效对象：list 覆盖 play()，两个默认组再兜一层 playMusic()
		var pool:Array<flixel.sound.FlxSound> = [];
		try
		{
			var list = FlxG.sound.list;
			if (list != null && list.members != null)
				for (s in list.members) if (s != null) pool.push(s);
		}
		catch (e:Dynamic) {}
		try
		{
			var groups:Array<flixel.sound.FlxSoundGroup> = [FlxG.sound.defaultSoundGroup, FlxG.sound.defaultMusicGroup];
			for (g in groups)
			{
				if (g == null || g.sounds == null) continue;
				for (s in g.sounds) if (s != null && pool.indexOf(s) < 0) pool.push(s);
			}
		}
		catch (e:Dynamic) {}

		// 2) 新开始播放的
		for (s in pool)
		{
			if (_activeSfx.exists(s)) continue;
			var playing:Bool = false;
			try { playing = s.playing; } catch (e:Dynamic) {}
			if (!playing) continue;

			var snd:Dynamic = null;
			try { @:privateAccess snd = s._sound; } catch (e:Dynamic) {}
			var path:String = soundFilePath(snd);
			if (path == null) continue;
			if (isSongTrack(path)) continue;      // Inst / Voices 已由 songAudio 处理
			if (isCountdownSfx(path)) continue;   // 倒计时已由 registerSound 登记，避免重复混音

			var vol:Float = 1;
			try { vol = s.volume; } catch (e:Dynamic) {}
			if (vol <= 0.001) continue;           // 静音音效没有任何贡献，白占一条输入
			var looped:Bool = false;
			try { looped = s.looped; } catch (e:Dynamic) {}

			_activeSfx.set(s, {path: path, atMs: now, volume: vol, looped: looped, durMs: -1});
			logLine('[audio] sfx start: ' + path + ' at ' + Math.round(now) + 'ms vol=' + vol
				+ (looped ? ' loop' : ''));
		}

		// 3) 已经停下的（自然播完 / 被 stop / autoDestroy）→ 定长度入列
		var done:Array<flixel.sound.FlxSound> = [];
		for (s in _activeSfx.keys())
		{
			var still:Bool = false;
			try { still = (s != null && s.playing); } catch (e:Dynamic) {}
			if (!still) done.push(s);
		}
		for (s in done)
		{
			var t:SfxTrack = _activeSfx.get(s);
			_activeSfx.remove(s);
			if (t == null) continue;
			t.durMs = Math.max(0, now - t.atMs);
			sfxTimeline.push(t);
			_sfxSeen++;
			logLine('[audio] sfx end: ' + t.path + ' dur=' + Math.round(t.durMs) + 'ms');
		}
	}

	/** 收尾时把仍在播放的音效归档为"播到视频结束" */
	static function flushSounds():Void
	{
		for (s in _activeSfx.keys())
		{
			var t:SfxTrack = _activeSfx.get(s);
			if (t == null) continue;
			t.durMs = -1;
			sfxTimeline.push(t);
			_sfxSeen++;
			logLine('[audio] sfx still playing at end: ' + t.path + ' from ' + Math.round(t.atMs) + 'ms');
		}
		_activeSfx = new Map();
	}

	/**
	 * 从 Sound 资源对象反查它对应的磁盘文件。
	 * Paths.returnSound() 把「路径 → Sound」存进了 currentTrackedSounds，
	 * 反过来查即可 —— 不需要覆盖 Flixel 或拦截加载。
	 */
	static function soundFilePath(snd:Dynamic):String
	{
		if (snd == null) return null;
		var key:openfl.media.Sound = cast snd;
		var hit:String = _soundPathCache.get(key);
		if (hit != null) return (hit == '') ? null : hit;

		var found:String = null;
		try
		{
			for (file => s in backend.Paths.currentTrackedSounds)
			{
				if (s != null && s == snd) { found = file; break; }
			}
		}
		catch (e:Dynamic) {}
		// 兜底：脚本直接塞字符串路径（不经过 Paths.returnSound）时，
		// 资源只登记在 OpenFL 的 Assets 缓存里。key 是 asset id，可能不含 assets/ 前缀。
		if (found == null)
		{
			try
			{
				// Assets.cache 静态类型是 IAssetCache 接口，实际实现是 AssetCache
				var ac:openfl.utils.AssetCache = cast openfl.utils.Assets.cache;
				for (id => s in ac.sound)
				{
					if (s == null || s != snd) continue;
					found = id;
					if (found != null && !FileSystem.exists(found) && FileSystem.exists('assets/' + found))
						found = 'assets/' + found;
					break;
				}
			}
			catch (e:Dynamic) {}
		}
		_soundPathCache.set(key, found == null ? '' : found);
		return found;
	}

	/** 取路径的文件名主干（小写、去目录、去扩展名） */
	static function baseName(path:String):String
	{
		var p:String = path.toLowerCase();
		var slash:Int = p.lastIndexOf('/');
		if (slash < 0) slash = p.lastIndexOf('\\');
		var n:String = (slash >= 0) ? p.substr(slash + 1) : p;
		var dot:Int = n.lastIndexOf('.');
		return (dot > 0) ? n.substr(0, dot) : n;
	}

	/** Inst / Voices 变体（Inst, Inst-erect, Voices-Player ...）走 songAudio 通道 */
	static function isSongTrack(path:String):Bool
	{
		var n:String = baseName(path);
		return StringTools.startsWith(n, 'inst') || StringTools.startsWith(n, 'voices');
	}

	/** 已由 PlayState.registerSound 手工登记的倒计时音效，按资源名去重 */
	static function isCountdownSfx(path:String):Bool
	{
		if (soundEvents.length == 0) return false;
		var n:String = baseName(path);
		for (e in soundEvents)
		{
			if (e.key == null) continue;
			var k:String = e.key.toLowerCase();
			// 手工登记的 key 可能带变体后缀（intro3 / intro3-pixel），用前缀兼容
			if (n == k || StringTools.startsWith(n, k)) return true;
		}
		return false;
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
				sfxCaptured: _sfxSeen,
				sfx: sfxTimeline,
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
