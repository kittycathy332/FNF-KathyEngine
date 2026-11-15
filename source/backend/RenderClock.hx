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
	static var _usePipe:Bool = false;
	static var _usePNG:Bool = true;
	static var _cutscenes:Array<String> = [];
	static var _firstError:String = '';
	static var _errorCount:Int = 0;
	static var _logLines:Array<String> = [];

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
		logLine('[begin] ' + _songName + ' / ' + _fps + 'fps / ' + _width + 'x' + _height);
		logLine('[output] ' + outputDir);

		// 交付形式分流：MP4 = rawvideo 直连 ffmpeg（最快）；PNG = 只落帧序列；
		// PNG+MP4 = 两者都做（保留逐帧素材，但仍有压缩与写盘开销）。
		_usePipe = (d.renderOutput == 'MP4' || d.renderOutput == 'PNG+MP4');
		_usePNG = (d.renderOutput == 'PNG' || d.renderOutput == 'PNG+MP4');
		_cutscenes = [];
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
		FlxG.updateFramerate = _fps;
		FlxG.drawFramerate = _fps;
		d.framerate = _fps;
		// set_drawFramerate() 会重写 _maxAccumulation，必须放在最后
		@:privateAccess FlxG.game._maxAccumulation = 1000 / _fps;
		FlxG.random.initialSeed = d.renderSeed;
		logLine('[clock] stepMS=' + (1000 / _fps) + 'ms, maxAccumulation pinned to one step'
			+ ' (was update/draw/pref ' + _savedUpdateFramerate + '/' + _savedDrawFramerate + '/' + _savedFrameratePref + ')');

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

		active = true;
		requested = false;
		trace('[RenderClock] begin: $_songName / $_fps fps / ${_width}x$_height -> ' + outputDir);
		return true;
	}

	/** 只在 FlxGame 真正 step() 过的一帧里 dispatch */
	static function onPreUpdate():Void
	{
		if (!active) return;
		_frameReady = true;
		var rate:Float = (PlayState.instance != null) ? PlayState.instance.playbackRate : 1;
		Conductor.songPosition = _startSongPos + frame * (1000 / _fps) * rate;
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
			if (img.width != _width || img.height != _height)
			{
				try { img.resize(_width, _height); }
				catch (e:Dynamic) logLine('[resize skipped] ' + Std.string(e) + ' -> native ' + img.width + 'x' + img.height);
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
		var leadMs:Float = (d != null && d.renderRange == 'SongOnly') ? 0 : Conductor.crochet * 5;
		totalFrames = Math.ceil((leadMs + songLengthMs) / (1000 / _fps));
		freezeAudio();
		logLine('[song] length=' + songLengthMs + 'ms totalFrames=' + totalFrames);
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

	public static function finish():Void
	{
		if (!active) return;
		active = false;
		_frameReady = false;
		FlxG.signals.preUpdate.remove(onPreUpdate);
		FlxG.signals.postDraw.remove(onPostDraw);
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

		var videoPath:String = '';
		if (_usePipe)
			videoPath = RenderEncoder.finish(_songName,
				(PlayState.instance != null ? PlayState.instance.playbackRate : 1),
				Conductor.offset, (d != null && d.renderAudio), _cutscenes, logLine);
		logLine('[finish] frames=' + frame + ' / captureErrors=' + _errorCount
			+ (_firstError != '' ? ' / firstError=' + _firstError : '')
			+ ' / video=' + videoPath);
		writeManifest(videoPath);

		var summary:String = Language.get('render_finish_popup') + '\n' + outputDir
			+ '\nframes: ' + frame
			+ (videoPath != '' ? '\nvideo: ' + videoPath : '')
			+ (_errorCount > 0 ? '\nERRORS: ' + _errorCount + '\n' + _firstError : '');
		logLine('[summary] ' + StringTools.replace(summary, '\n', ' | '));
		trace('[RenderClock] done: ' + frame + ' frames -> ' + outputDir);

		// 只弹提示，不自动切状态：避免在转场创建过程中再引入一次状态切换
		haxe.Timer.delay(function()
		{
			try { backend.CoolUtil.showPopUp(summary, Language.get('render_menu')); }
			catch (e:Dynamic) logLine('[popup error] ' + Std.string(e));
		}, 200);
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

	static function writeManifest(videoPath:String):Void
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
