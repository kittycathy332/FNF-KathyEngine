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
 * 统一时钟架构（所有时间都从 subFrame 派生，避免音画/倒计时漂移）：
 *  1. fixedTimestep = true；updateFramerate = fps×SUBSTEPS（判定/逻辑步长
 *     1000/(fps×SUBSTEPS)，如 120fps×8=960Hz → 1.04ms）；
 *     drawFramerate = stage.frameRate = fps（窗口绘制/截帧节奏）。
 *  2. _maxAccumulation 钉为 1000/fps，允许每 draw 跑满 SUBSTEPS 步；
 *     注意 set_drawFramerate() 会把 _maxAccumulation 改写成 2000/fps-1，
 *     所以每次设定帧率之后都必须重新钉一次。
 *  3. ClientPrefs.data.framerate 也同步改成 fps，让读它的模组 / 脚本保持一致。
 *  4. preUpdate 每个逻辑 step 都按 subFrame 写 Conductor.songPosition，
 *     并每累计 SUBSTEPS 个 step 置一次 _frameReady；postDraw 在 _frameReady 时截帧。
 *     这样截帧数 = subFrame/SUBSTEPS，而 songPosition、倒计时 FlxTimer、
 *     音频时长全部 = frame/fps —— 四者严格同步，窗口帧率抖动只影响渲染速度。
 *  5. 开场淡入转场（CustomFadeTransition）属于成片内容，正常录制；
 *     冻结仅限暂停菜单。preUpdate/postDraw 是全局信号，subState 期间照常派发。
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
	/** 已处理的输出帧序号（下一帧的文件名 / 画面帧） */
	public static var frame:Int = 0;
	/**
	 * 逻辑亚帧计数：每个 step() 递增一次。判定 / songPosition 用它推进，
	 * 精度 = 1000/(fps×SUB) 毫秒（90fps×8 = 1.39ms），远高于画面帧的 11.11ms。
	 */
	public static var subFrame:Int = 0;
	/** 每个输出帧细分的逻辑步数（真亚帧判定） */
	public static inline var SUBSTEPS:Int = 8;
	/** 起点待定：begin 早于 BPM 设置，首帧用正确 crochet 重算 _startSongPos */
	static var _originPending:Bool = false;
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
	/** 累计的 step 数对 SUBSTEPS 取模得到的欠帧：每个 draw 最多补截一帧 */
	static var _framesDue:Int = 0;
	static var _interrupted:String = '';
	static var _skippedSubFrames:Int = 0;
	/** 运行期时钟参数被外部改写并校正回来的次数（应为 0，非 0 说明还有别的干扰源） */
	static var _clockCorrections:Int = 0;
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

	// ===== 画布准备：逻辑坐标恒定，只有窗口/编码器尺寸按模式决定 =====
	/** 需要在首帧调整窗口并（可能）启动编码器 */
	static var _supersamplePending:Bool = false;
	/** 无损模式必须等 create() 完成后才知道真实逻辑尺寸，编码器延迟到首帧启动 */
	static var _encoderPending:Bool = false;
	/** 像素级无损：原逻辑分辨率截帧 + RGB 无损编码 */
	static var _lossless:Bool = true;
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
		trace('[RenderClock] cutscene mode: ' + d.renderCutscene);

		_fps = Std.int(Math.max(24, d.renderFPS));
		_width = Std.int(Math.max(320, d.renderWidth));
		_height = Std.int(Math.max(240, d.renderHeight));
		_songName = (PlayState.SONG != null) ? PlayState.SONG.song : 'song';
		_lossless = d.renderLossless;

		// begin() 在 PlayState.create() 中途调用，此刻 PlayStateScaleMode 还没应用，
		// 真正的逻辑尺寸要等首帧 preUpdate 才能确定。无损模式必须按真实逻辑尺寸
		// 开管道，所以窗口调整和编码器启动都推迟到 applySupersampling()。
		_savedWindowWidth = FlxG.stage.window.width;
		_savedWindowHeight = FlxG.stage.window.height;
		_savedLogicWidth = FlxG.width;
		_savedLogicHeight = FlxG.height;
		_savedScaleMode = FlxG.scaleMode;
		_supersamplePending = _lossless || (_savedWindowWidth != _width || _savedWindowHeight != _height);
		_encoderPending = _lossless && (d.renderOutput == 'MP4' || d.renderOutput == 'PNG+MP4');
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

		_firstError = '';
		_errorCount = 0;
		_frameReady = false;
		_interrupted = '';
		_skippedSubFrames = 0;
		_clockCorrections = 0;
		logLine('[begin] ' + _songName + ' / ' + _fps + 'fps / '
			+ (_lossless ? 'LOSSLESS (size locked to logical)' : _width + 'x' + _height));
		logLine('[output] ' + outputDir);
		logLine('[window] native=' + _savedWindowWidth + 'x' + _savedWindowHeight
			+ ' logic=' + _savedLogicWidth + 'x' + _savedLogicHeight
			+ ' -> prepare=' + _supersamplePending);

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
			+ ' lossless=' + _lossless + ' encoder=' + d.renderEncoder + ' crf=' + d.renderCRF);
		if (_usePipe && !_encoderPending)
		{
			if (!RenderEncoder.begin(outputDir, _width, _height, _fps, d.renderCRF,
				d.renderEncoder, false, logLine))
			{
				logLine('[fallback] pipe unavailable -> PNG sequence mode');
				_usePipe = false;
				_usePNG = true;
			}
		}
		else if (_encoderPending)
			logLine('[encoder] deferred to first frame (needs real logical size)');

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

		// ===== 渲染期：逻辑用亚帧高频步进，画面按输出帧率截屏 =====
		// 判定精度取决于 songPosition 的采样密度。旧版 update=draw=fps，
		// 每帧只 step 一次 → songPosition 只能落在 1000/fps 的整数倍上，
		// noteDiff 呈"整数台阶"（90fps 就是 11.11ms 一格）。
		// 现在 updateFramerate = fps×SUBSTEPS（如 90×8=720Hz），每输出帧跑 8 个逻辑步，
		// songPosition 每步推进 1000/720=1.39ms → 判定精确到 0.00x 毫秒；
		// drawFramerate 仍是 fps，画面照旧 90fps 截，不增加读回开销。
		//
		// 顺序很重要：set_drawFramerate() 会把 _maxAccumulation 改写成 2000/fps - 1，
		// set_updateFramerate() 又会重算 _stepMS/_stepSeconds。所以累加器最后钉。
		// _maxAccumulation = 1000/fps = SUB × stepMS，允许每 draw 恰好跑 SUB 步。
		var logicFps:Int = _fps * SUBSTEPS;
		FlxG.updateFramerate = logicFps; // 逻辑 / 判定步长 = 1000/logicFps
		FlxG.drawFramerate = _fps;       // 窗口 onEnterFrame 频率 = 画面帧率
		if (FlxG.stage != null) FlxG.stage.frameRate = _fps;
		d.framerate = _fps; // 玩家设定保持画面帧率，模组脚本读它不会被 ×8
		// 渲染期间禁止失焦自动暂停：FlxGame.onEnterFrame 在 _lostFocus && autoPause 时
		// 整帧 return，会让长时间渲染中途停住（且 step 与截帧配对全乱）。
		_savedAutoPause = FlxG.autoPause;
		FlxG.autoPause = false;
		@:privateAccess FlxG.game._maxAccumulation = 1000 / _fps;
		FlxG.random.initialSeed = d.renderSeed;
		logLine('[clock] SUBSTEP x' + SUBSTEPS + ': output=' + _fps + 'fps logic=' + logicFps
			+ 'Hz judgeStep=' + (1000 / logicFps) + 'ms'
			+ ' / update=' + FlxG.updateFramerate + ' draw=' + FlxG.drawFramerate
			+ ' stage=' + ((FlxG.stage != null) ? Std.string(FlxG.stage.frameRate) : 'n/a')
			+ ' maxAccum=' + (1000 / _fps)
			+ ' (was update=' + _savedUpdateFramerate + ' draw=' + _savedDrawFramerate + ')');

		// 倒计时段的起点与 PlayState.startCountdown() 的赋值保持一致。
		// 注意 begin() 在 create() 中途（PlayState 823 行）调用，此刻 BPM 尚未设好
		// （882 行才 Conductor.bpm = SONG.bpm），crochet 还是默认值。真正起点在首帧
		// onPreUpdate（create 已完成）用正确 crochet 重算，见 _originPending。
		_originPending = true;
		_startSongPos = (d.renderRange == 'SongOnly')
			? Conductor.offset
			: -Conductor.crochet * 5 + Conductor.offset;
		frame = 0;
		subFrame = 0;
		_framesDue = 0;
		_frameReady = false;
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
		trace('[RenderClock] begin: $_songName / $_fps fps / '
			+ (_lossless ? 'LOSSLESS(logical)' : '${_width}x$_height') + ' -> ' + outputDir);
		return true;
	}

	/** 只在 FlxGame 真正 step() 过的一帧里 dispatch */
	static function onPreUpdate():Void
	{
		if (!active) return;
		// create() 已完成，首帧把窗口 framebuffer 放大到目标分辨率
		if (!_supersampleApplied) applySupersampling();
		// 首帧用已设好的 BPM 重算倒计时起点（begin 时 crochet 还是默认值）
		if (_originPending)
		{
			_originPending = false;
			var dd = ClientPrefs.data;
			var correctStart:Float = (dd != null && dd.renderRange == 'SongOnly')
				? Conductor.offset
				: -Conductor.crochet * 5 + Conductor.offset;
			if (Math.abs(correctStart - _startSongPos) > 0.01)
				logLine('[origin] songPosition start corrected ' + Math.round(_startSongPos)
					+ 'ms -> ' + Math.round(correctStart) + 'ms (BPM now ' + Conductor.bpm + ')');
			_startSongPos = correctStart;
		}

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

		// ===== 统一时钟：一切从 subFrame（step 时钟）派生 =====
		// 上一版把 songPosition 绑在 frame（draw 时钟）上治好了音画漂移，
		// 却让倒计时 FlxTimer（走 step 时钟）掉队 → 曲目比倒计时快约 18%，
		// 表现为"倒计时还没结束曲目就开始了"。
		// 根治：让截帧也走 step 时钟 —— 每 SUBSTEPS 个 step 才截一帧（见下）。
		// 于是四者严格相等、且都由 subFrame 派生：
		//   截帧数 frame   ≈ subFrame / SUBSTEPS
		//   songPosition   = 起点 + subFrame × (1000/fps/SUBSTEPS) = 起点 + frame × 1000/fps
		//   倒计时 FlxTimer = subFrame / updateFramerate = subFrame/(fps×SUBSTEPS) = frame/fps
		//   音频时长        = frame / fps
		// 窗口帧率抖动只影响"多久截一帧"（实时速度），不影响任何时间戳与同步。
		var rate:Float = (PlayState.instance != null) ? PlayState.instance.playbackRate : 1;
		var logicStepMs:Float = (1000 / _fps) / SUBSTEPS;
		Conductor.songPosition = _startSongPos + subFrame * logicStepMs * rate;
		subFrame++;
		// 每 SUBSTEPS 个 step 欠一帧；postDraw 消费（每 draw 最多补一帧）。
		// 窗口跑满时每 draw 恰好 SUBSTEPS 步 → 截一帧；跑不满时欠帧顺延到后续 draw。
		_framesDue++;
		if (_framesDue >= SUBSTEPS)
		{
			_frameReady = true;
			_framesDue -= SUBSTEPS;
		}
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
	 * 首帧（create 已完成后）确定画布与编码器尺寸。
	 *
	 * 必须在 create() 之后做：begin() 在 PlayState.create() 中途调用，若那时
	 * 就 resizeGame，紧随其后的 PlayState 自适应缩放模式切换（约 842 行）会
	 * 把我们装好的 RenderScaleMode 覆盖掉。preUpdate 首帧时 create 已完成，
	 * 此刻拿到的 FlxG.width/height 才是真实逻辑尺寸。
	 *
	 * 无损模式下 _width/_height 会被改写成这个真实逻辑尺寸，窗口也缩到同一尺寸，
	 * 于是 readPixels() 得到的就是游戏原始像素，没有 GPU 插值、没有放大。
	 * 逻辑分辨率在任何模式下都不会被导出尺寸改写。
	 */
	static function applySupersampling():Void
	{
		if (_supersampleApplied) return;
		_supersampleApplied = true;
		#if desktop
		// create() 到这里已完成（含 PlayState 842 行的自适应 width 切换）。
		// 以"此刻"的 scaleMode / 逻辑尺寸为还原基准，而不是 begin() 时的旧值。
		_savedLogicWidth = FlxG.width;
		_savedLogicHeight = FlxG.height;
		_savedScaleMode = FlxG.scaleMode;
		var d = ClientPrefs.data;
		try
		{
			if (_lossless)
			{
				_width = _savedLogicWidth;
				_height = _savedLogicHeight;
			}

			if (_supersamplePending)
			{
				FlxG.scaleMode = new flixel.system.scaleModes.RenderScaleMode(_savedLogicWidth, _savedLogicHeight);
				FlxG.stage.window.resize(_width, _height);
				// resize 事件是异步的，主动 measure 一次让本帧就生效
				FlxG.resizeGame(_width, _height);
			}

			logLine('[canvas] ' + (_lossless ? 'LOSSLESS' : 'EXPORT') + ' render '
				+ _width + 'x' + _height
				+ ' / logic locked ' + FlxG.width + 'x' + FlxG.height
				+ ' (window ' + _savedWindowWidth + 'x' + _savedWindowHeight
				+ ' -> ' + _width + 'x' + _height + ')');

			if (_encoderPending)
			{
				_encoderPending = false;
				if (_usePipe)
				{
					if (!RenderEncoder.begin(outputDir, _width, _height, _fps, d.renderCRF,
						d.renderEncoder, _lossless, logLine))
					{
						logLine('[fallback] pipe unavailable -> PNG sequence mode');
						_usePipe = false;
						_usePNG = true;
					}
				}
			}
		}
		catch (e:Dynamic)
		{
			logLine('[canvas] FAILED: ' + Std.string(e) + ' -> PNG fallback');
			_usePipe = false;
			_usePNG = true;
			try { FlxG.scaleMode = _savedScaleMode; } catch (e2:Dynamic) {}
		}
		#else
		logLine('[canvas] skipped (not desktop target)');
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
	 * 亚帧方案下四个量必须同时正确：
	 *  - updateFramerate = fps×SUBSTEPS → 判定步长（决定 noteDiff 精度）
	 *  - drawFramerate / stage.frameRate = fps → 画面截帧频率
	 *  - ClientPrefs.data.framerate = fps → 模组脚本读它不会以为被 ×8
	 *  - _maxAccumulation = 1000/fps → 每 draw 允许跑满 SUBSTEPS 个逻辑步
	 *
	 * 注意 set_drawFramerate() 会把 _maxAccumulation 改写成 2000/fps - 1，
	 * 所以累加器的修正必须放在最后。
	 */
	static function enforceClock():Void
	{
		var logicFps:Int = _fps * SUBSTEPS;
		if (FlxG.updateFramerate != logicFps)
		{
			FlxG.updateFramerate = logicFps;
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
		// 放在最后：set_drawFramerate() 会覆盖它。
		// 目标 = 1000/fps = SUBSTEPS 个逻辑步，允许每 draw 跑满细分步数。
		var accMs:Float = 1000 / _fps;
		var cur:Float = @:privateAccess FlxG.game._maxAccumulation;
		if (Math.abs(cur - accMs) > 0.01)
		{
			@:privateAccess FlxG.game._maxAccumulation = accMs;
			_clockCorrections++;
		}
	}

	/** 每帧一次：截屏落盘，然后推进帧号 */
	static function onPostDraw():Void
	{
		if (!active) return;
		if (!_frameReady)
		{
			// 本 draw 周期内累计的 step 还不足 SUBSTEPS 个，不截帧，只做时钟纠错。
			// 截帧改由 step 时钟驱动（每 SUBSTEPS 步一次），因此帧号、songPosition、
			// 倒计时、音频时长四者严格同步，不受窗口帧率抖动影响。
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
			// 无损模式下目标就是原逻辑尺寸；若仍不一致（DPI 缩放），用最近邻取样
			// 而不是 img.resize() 的双线性插值，避免把原始像素混色。
			var nativeW:Int = img.width;
			var nativeH:Int = img.height;
			var frameBytes:haxe.io.Bytes = img.buffer.data.buffer;
			if (nativeW != _width || nativeH != _height)
			{
				if (nativeW < _width || nativeH < _height)
				{
					_cpuResizeCount++;
					if (_cpuResizeCount <= 2)
						logLine('[capture] readPixels ' + nativeW + 'x' + nativeH + ' < target '
							+ _width + 'x' + _height + ' -> UPSCALE (quality degraded)');
				}
				if (frame == 0)
					logLine('[capture] first frame native ' + nativeW + 'x' + nativeH
						+ ' -> target ' + _width + 'x' + _height
						+ (_lossless ? ' (nearest-neighbor, pixel-exact)' : ''));
				if (_lossless)
					frameBytes = resizeNearestRGBA(frameBytes, nativeW, nativeH, _width, _height);
				else
				{
					try { img.resize(_width, _height); }
					catch (e:Dynamic) logLine('[resize skipped] ' + Std.string(e) + ' -> native ' + nativeW + 'x' + nativeH);
					frameBytes = img.buffer.data.buffer;
				}
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
				// 无损模式下 frameBytes 已是原始像素（或最近邻取样结果），直接写 stdin
				RenderEncoder.writeFrame(frameBytes);
			}
			// 分阶段计时：每 600 帧汇总一次，定位瓶颈在读回 / 翻转还是管道写入
			_perfReadMs += tRead1 - tRead0;
			_perfWriteMs += Date.now().getTime() - tRead1;
			_perfFrames++;
			if (_perfFrames >= 600)
			{
				// frame 是 0-based 且在本函数末尾才 ++，这里 +1 才是"已处理的帧数"，
				// 否则日志会显示 599/1199/… 这种"整百减一"，读起来像丢了帧。
				logLine('[perf] ' + _perfFrames + ' frames: read+flip='
					+ Math.round(_perfReadMs / _perfFrames * 100) / 100 + 'ms'
					+ ' writePipe=' + Math.round(_perfWriteMs / _perfFrames * 100) / 100 + 'ms'
					+ ' videoMB=' + RenderEncoder.videoSizeMB()
					+ ' (at frame ' + (frame + 1) + ')');
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
				// 过场已在渲染时按虚拟时钟逐帧画进游戏画面，不再在片头 concat。
				cutscenes: [],
				songAudio: songAudio,
				soundEvents: soundEvents,
				sfx: sfxTimeline,
				leadMs: _leadMs,
				durationSec: frame / _fps
			}, logLine);
		}
		logLine('[finish] frames=' + frame + ' / subSteps=' + subFrame
			+ ' (x' + SUBSTEPS + ' judge grid) / captureErrors=' + _errorCount
			+ ' / skippedSubFrames=' + _skippedSubFrames
			+ ' / clockCorrections=' + _clockCorrections
			+ ' / cpuResizedFrames=' + _cpuResizeCount
			+ ' / sfxCaptured=' + _sfxSeen
			+ (_firstError != '' ? ' / firstError=' + _firstError : '')
			+ ' / video=' + videoPath);
		// 诊断用：subFrame 是实际 step 总数，窗口帧率抖动时会少于 frame×SUBSTEPS。
		// 自 frame 驱动时钟修复后，这个偏差【不再造成音画漂移】—— 时钟由 frame
		// 决定，少跑的 step 只是那一帧内少覆盖了几个判定采样点。仅在偏差极大时提示。
		var expectSub:Int = (frame - _skippedSubFrames) * SUBSTEPS;
		if (expectSub > 0 && subFrame < expectSub * 0.5)
			logLine('[timing] NOTE: step coverage ' + Math.round(subFrame * 100 / expectSub)
				+ '% (window fps unstable). Clock stays frame-driven, no A/V drift.');
		if (_cpuResizeCount > 0)
			logLine('[quality] WARNING: readPixels was SMALLER than target on ' + _cpuResizeCount
				+ ' frames (window resize blocked?). Output was CPU-upscaled and may look soft.');
		writeManifest(videoPath, '');

		var summary:String = Language.get('render_finish_popup') + '\n' + outputDir
			+ '\nframes: ' + frame
			+ (videoPath != '' ? '\nvideo: ' + videoPath : '')
			+ (_errorCount > 0 ? '\nERRORS: ' + _errorCount + '\n' + _firstError : '');
		logLine('[summary] ' + StringTools.replace(summary, '\n', ' | '));
		cleanupVideoCache();
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
		logLine('[abort] reason=' + reason + ' frames=' + frame + ' / subSteps=' + subFrame
			+ ' / skippedSubFrames=' + _skippedSubFrames
			+ ' / sfxCaptured=' + _sfxSeen
			+ ' / clockCorrections=' + _clockCorrections + ' / partial=' + partial);
		writeManifest(partial, reason);
		cleanupVideoCache();
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
	public static function videoMs():Float
		return frame * (1000 / _fps);

	/** 过场逐帧显示用的输出帧率 */
	public static function videoFps():Int
		return _fps;

	/** 给 RenderVideoFrames 写诊断日志用的回调 */
	public static function videoLog(s:String):Void
		logLine(s);

	/**
	 * 登记视频自带音轨：在 atMs 这个视频时间点播放，持续 durMs。
	 * 走已有的 sfxTimeline 通道，因此会和游戏音频一起混入成片。
	 */
	public static function registerVideoAudio(path:String, atMs:Float, durMs:Float, volume:Float):Void
	{
		if (!active || path == null || !FileSystem.exists(path)) return;
		sfxTimeline.push({
			path: path,
			atMs: Math.max(0, atMs),
			volume: volume <= 0 ? 1 : volume,
			looped: false,
			durMs: durMs
		});
		logLine('[video] audio registered at ' + Math.round(atMs) + 'ms dur='
			+ Math.round(durMs) + 'ms ' + path);
	}

	/** 渲染结束（混音完成）后删除预解码缓存（PNG 帧在子目录里，需递归） */
	public static function cleanupVideoCache():Void
	{
		if (outputDir == '') return;
		deleteTree(outputDir + 'video_cache/');
	}

	static function deleteTree(path:String):Void
	{
		try
		{
			if (!FileSystem.exists(path)) return;
			if (FileSystem.isDirectory(path))
			{
				for (f in FileSystem.readDirectory(path))
					deleteTree(path + f + (FileSystem.isDirectory(path + f) ? '/' : ''));
				FileSystem.deleteDirectory(path);
			}
			else
				FileSystem.deleteFile(path);
		}
		catch (e:Dynamic) { logLine('[video] cache cleanup failed: ' + path + ' ' + Std.string(e)); }
	}

	/**
	 * HUD 统计数据（NPS 等）专用的单调时间源，单位毫秒。
	 *
	 * 渲染时返回帧号驱动的虚拟时间：成片是 0.47 倍速这样的慢速回放，
	 * 若用真实墙钟，1 秒窗口会按真实秒滑走，NPS 就变成"真实每秒命中数"，
	 * 被放大数倍且随卡顿抖动，与画面里的曲目进度对不上。
	 * 正常游玩时返回真实墙钟，行为与原 haxe.Timer.stamp()*1000 完全一致。
	 */
	public static function hudTimeMs():Float
	{
		if (active) return frame * (1000 / _fps);
		return haxe.Timer.stamp() * 1000;
	}

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

	/**
	 * 兼容旧调用点：过场现在由 VideoSprite 在渲染时逐帧画进游戏画面，
	 * 不再需要片头 concat。保留空实现避免第三方脚本调用报错。
	 */
	public static function registerCutscene(path:String):Void
	{
		if (active && path != null) logLine('[cutscene] in-frame mode, ignored concat: ' + path);
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

	/**
	 * 写日志文件：release 构建会关掉 trace，这是唯一的可见诊断通道。
	 *
	 * 必须追加写，不能每次 saveContent(全文) —— 密集谱面每个音符都会打
	 * [audio] sfx start/end，日志涨到几千行后，全文重写变成 O(n²)，
	 * 表现为"越到渲染后期越卡"。这里改成 append，单次写入恒定。
	 */
	static function logLine(s:String):Void
	{
		var line:String = DateTools.format(Date.now(), '%H:%M:%S') + ' ' + s + '\n';
		try
		{
			var out = File.append(outputDir + 'render_log.txt', false);
			out.writeString(line);
			out.close();
		}
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

	/**
	 * 无损模式下的 DPI 尺寸修正：最近邻取样，不引入插值混色。
	 * 正常 100% 缩放下 readPixels 尺寸已等于逻辑尺寸，这个函数不会被调用。
	 */
	static function resizeNearestRGBA(src:haxe.io.Bytes, sw:Int, sh:Int, dw:Int, dh:Int):haxe.io.Bytes
	{
		var out:haxe.io.Bytes = haxe.io.Bytes.alloc(dw * dh * 4);
		for (y in 0...dh)
		{
			var sy:Int = Std.int(y * sh / dh);
			if (sy >= sh) sy = sh - 1;
			for (x in 0...dw)
			{
				var sx:Int = Std.int(x * sw / dw);
				if (sx >= sw) sx = sw - 1;
				var si:Int = (sy * sw + sx) * 4;
				var di:Int = (y * dw + x) * 4;
				out.set(di, src.get(si));
				out.set(di + 1, src.get(si + 1));
				out.set(di + 2, src.get(si + 2));
				out.set(di + 3, src.get(si + 3));
			}
		}
		return out;
	}
}
