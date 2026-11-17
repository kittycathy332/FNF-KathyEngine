package backend;

import sys.io.Process;
import sys.io.File;
import sys.FileSystem;
import haxe.io.Bytes;
import openfl.display.BitmapData;
import openfl.utils.ByteArray;
import DateTools;

/**
 * 把一个过场视频预解码成「PNG 帧序列 + 独立音轨 WAV」。
 *
 * 为什么必须预解码：hxvlc 的 FlxVideoSprite 按真实墙钟播放，并且把 bitmap
 * 直接 addChild 到 FlxG.game（OpenFL 最顶层），既跟不上虚拟时钟，也没有图层概念。
 * 这里改成 ffmpeg 一次性解码成图片序列，渲染时由 VideoSprite 按 RenderClock 的
 * 虚拟帧号取帧、用普通 FlxSprite 显示 —— 调用方 add 到哪一层，视频就在哪一层。
 *
 * 为什么用 PNG 而不是裸 RGBA：1280x720 一帧裸 RGBA 就有 3.5MB，60fps 一分钟
 * 视频高达 12GB。PNG 无损压缩后通常 100~400KB/帧，体积降低一个数量级，
 * 画质无损。帧文件只放在本次 renders 目录，渲染结束由 RenderClock 统一删除。
 */
class RenderVideoFrames
{
	public var videoPath:String;
	public var width:Int;
	public var height:Int;
	public var fps:Int;
	public var totalFrames:Int = 0;
	public var durationMs:Float = 0;
	public var audioPath:String = '';
	public var ready:Bool = false;
	public var error:String = '';
	/** 'FFmpeg' 全帧序列 | 'Freeze' 只取首帧定格 | 'Skip' 完全不解码 */
	public var mode:String = 'FFmpeg';

	var frameDir:String;
	var audioPathInner:String;
	var log:String->Void;
	var cache:Map<Int, BitmapData> = new Map();
	var cacheOrder:Array<Int> = [];
	static inline var CACHE_MAX:Int = 12;

	public function new(videoPath:String, fps:Int, width:Int, height:Int,
		cacheDir:String, log:String->Void, ?mode:String)
	{
		this.videoPath = videoPath;
		this.fps = fps;
		this.width = width;
		this.height = height;
		this.log = log;
		this.mode = (mode == null || mode == '') ? 'FFmpeg' : mode;

		// Skip：完全不碰视频文件，也不建目录；由调用方立刻走完回调。
		if (this.mode == 'Skip')
		{
			log('[video] SKIP by renderCutscene setting: ' + videoPath);
			return;
		}

		try { if (!FileSystem.exists(cacheDir)) FileSystem.createDirectory(cacheDir); }
		catch (e:Dynamic) { error = 'cache dir failed: ' + Std.string(e); return; }

		var stamp:String = DateTools.format(Date.now(), '%H%M%S') + '_' + Std.string(Math.floor(Math.random() * 100000));
		frameDir = cacheDir + 'vid_' + stamp + '/';
		audioPathInner = cacheDir + 'vid_' + stamp + '.wav';
		try { FileSystem.createDirectory(frameDir); }
		catch (e:Dynamic) { error = 'frame dir failed: ' + Std.string(e); return; }

		var ffmpeg:String = RenderEncoder.locate(log);
		if (ffmpeg == '')
		{
			error = 'ffmpeg not found';
			log('[video] decode skipped: ffmpeg not found');
			return;
		}

		// 保持原比例、居中、黑边填充，与原本 setGraphicSize + screenCenter 行为一致。
		// PNG 无损压缩，肉眼零损失，体积比裸 RGBA 小一个数量级。
		var vf:String = 'fps=' + fps
			+ ',scale=' + width + ':' + height + ':force_original_aspect_ratio=decrease'
			+ ',pad=' + width + ':' + height + ':(ow-iw)/2:(oh-ih)/2:color=black';
		var pattern:String = frameDir + 'f_%06d.png';
		var args:Array<String> = [
			'-y', '-hide_banner', '-loglevel', 'error', '-i', videoPath,
			'-vf', vf, '-an', '-c:v', 'png'
		];
		if (mode == 'Freeze') args = args.concat(['-frames:v', '1']);
		args.push(pattern);
		if (!run(ffmpeg, args, 'decode'))
		{
			error = 'decode failed';
			return;
		}

		try
		{
			var files:Array<String> = FileSystem.readDirectory(frameDir);
			for (f in files) if (StringTools.endsWith(f, '.png')) totalFrames++;
			durationMs = totalFrames * (1000 / fps);
		}
		catch (e:Dynamic)
		{
			error = 'count frames failed: ' + Std.string(e);
			return;
		}
		if (totalFrames <= 0)
		{
			error = 'no frames decoded';
			return;
		}

		// Freeze 只解了 1 帧，真实时长靠 ffprobe 探测；取不到就退回 1 帧时长。
		if (mode == 'Freeze')
		{
			var probed:Float = probeDurationMs(ffmpeg, videoPath);
			if (probed > 0)
			{
				durationMs = probed;
				totalFrames = Std.int(Math.max(1, Math.ceil(probed / (1000 / fps))));
			}
			log('[video] FREEZE first frame only, display ' + Math.round(durationMs) + 'ms');
		}

		// 音轨单独抽出：VideoSprite 会在视频起点登记这条 WAV 到 sfxTimeline。
		var aok:Bool = run(ffmpeg, [
			'-y', '-hide_banner', '-loglevel', 'error', '-i', videoPath,
			'-vn', '-ac', '2', '-ar', '48000', '-c:a', 'pcm_s16le', audioPathInner
		], 'audio');
		audioPath = aok ? audioPathInner : '';

		ready = true;
		log('[video] decoded ' + videoPath + ' -> ' + totalFrames + ' PNG frames '
			+ width + 'x' + height + ' @' + fps + 'fps'
			+ ' audio=' + (audioPath != ''));
	}

	/**
	 * 取第 index 帧并解码成 BitmapData（0-based，越界钳到末帧）。
	 * 带 12 帧 LRU 缓存，避免顺序播放时反复解码同一批文件。
	 */
	public function getFrame(index:Int):BitmapData
	{
		if (!ready) return null;
		if (index < 0) index = 0;
		if (index >= totalFrames) index = totalFrames - 1;
		// Freeze 只有一张图，任何时间点都取首帧
		if (mode == 'Freeze') index = 0;

		var hit:BitmapData = cache.get(index);
		if (hit != null) return hit;

		var path:String = framePath(index);
		try
		{
			if (!FileSystem.exists(path)) return null;
			var bytes:Bytes = File.getBytes(path);
			var bd:BitmapData = BitmapData.fromBytes(ByteArray.fromBytes(bytes));
			if (bd == null) return null;
			cache.set(index, bd);
			cacheOrder.push(index);
			while (cacheOrder.length > CACHE_MAX)
			{
				var old:Int = cacheOrder.shift();
				cache.remove(old);
			}
			return bd;
		}
		catch (e:Dynamic)
		{
			log('[video] decode frame ' + index + ' failed: ' + Std.string(e));
			return null;
		}
	}

	function framePath(index:Int):String
	{
		return frameDir + 'f_' + StringTools.lpad(Std.string(index + 1), '0', 6) + '.png';
	}

	/** 释放解码缓存。PNG 帧文件保留到本次渲染目录清理时统一删。 */
	public function dispose():Void
	{
		for (bd in cache) { try { bd.dispose(); } catch (e:Dynamic) {} }
		cache = new Map();
		cacheOrder = [];
		ready = false;
	}

	/** 探测视频真实时长（毫秒）；失败返回 0。ffprobe 与 ffmpeg 通常同目录。 */
	function probeDurationMs(ffmpeg:String, path:String):Float
	{
		var ffprobe:String = '';
		try
		{
			var probeCandidates:Array<String> = [];
			if (ffmpeg.toLowerCase().endsWith('ffmpeg.exe'))
				probeCandidates.push(ffmpeg.substring(0, ffmpeg.length - 9) + 'ffprobe.exe');
			probeCandidates.push('ffprobe');
			for (c in probeCandidates)
			{
				var p:Process = new Process(c, [
					'-v', 'error', '-show_entries', 'format=duration',
					'-of', 'default=noprint_wrappers=1:nokey=1', path
				]);
				var out:String = p.stdout.readAll().toString().trim();
				p.close();
				var sec:Float = Std.parseFloat(out);
				if (!Math.isNaN(sec) && sec > 0) return sec * 1000;
			}
		}
		catch (e:Dynamic) {}
		return 0;
	}

	function run(ffmpeg:String, args:Array<String>, tag:String):Bool
	{
		try
		{
			var p:Process = new Process(ffmpeg, args);
			var err:String = '';
			try { err = p.stderr.readAll().toString(); } catch (e:Dynamic) {}
			var code:Int = p.exitCode();
			p.close();
			if (code != 0) log('[video] ' + tag + ' failed (' + code + '): ' + err);
			return code == 0;
		}
		catch (e:Dynamic)
		{
			log('[video] ' + tag + ' exception: ' + Std.string(e));
			return false;
		}
	}
}
