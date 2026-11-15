package backend;

import sys.io.Process;
import sys.io.File;
import sys.FileSystem;
import sys.thread.Thread;
import haxe.io.Bytes;

/**
 * rawvideo 直连 ffmpeg 的编码与合成。
 *
 * 取代「每帧 PNG 压缩 + 写盘 + 合成时二次解码」：
 *   - 渲染期起一个 ffmpeg 子进程，stdin 收 RGBA 原始帧，直接编码成无声 video_only.mp4
 *   - 收尾时再调一次 ffmpeg 混入原始 Inst/Voices 音轨
 *   - 有视频过场时再调一次做片头拼接
 *
 * 所有日志通过 log 回调写到 RenderClock 的 render_log.txt。
 */
class RenderEncoder
{
	static var _proc:Process = null;
	static var _ffmpeg:String = '';
	static var _encoder:String = 'libx264';
	static var _videoOnly:String = '';
	static var _outputDir:String = '';
	static var _width:Int = 1280;
	static var _height:Int = 720;
	static var _fps:Int = 60;
	static var _crf:Int = 20;
	static var _frames:Int = 0;
	static var _running:Bool = false;

	public static function locate(log:String->Void):String
	{
		if (probe('ffmpeg')) { log('[encoder] ffmpeg found on PATH'); return 'ffmpeg'; }
		var local:String = Sys.getCwd() + 'tools/ffmpeg/bin/ffmpeg.exe';
		if (FileSystem.exists(local) && probe(local)) { log('[encoder] ffmpeg found: ' + local); return local; }
		log('[encoder] ffmpeg NOT found (PATH, then tools/ffmpeg/bin/ffmpeg.exe)');
		return '';
	}

	static function probe(path:String):Bool
	{
		try
		{
			var p = new Process(path, ['-hide_banner', '-version']);
			var ok:Bool = p.exitCode() == 0;
			p.close();
			return ok;
		}
		catch (e:Dynamic) return false;
	}

	public static function hasEncoder(ffmpeg:String, name:String):Bool
	{
		try
		{
			var p = new Process(ffmpeg, ['-hide_banner', '-encoders']);
			var out:String = p.stdout.readAll().toString();
			p.close();
			return out.indexOf(name) >= 0;
		}
		catch (e:Dynamic) return false;
	}

	/** 起 pipe 进程；失败返回 false，由 RenderClock 回退到 PNG 模式 */
	public static function begin(outputDir:String, width:Int, height:Int, fps:Int, crf:Int,
		requestedEncoder:String, log:String->Void):Bool
	{
		_outputDir = outputDir;
		_width = width;
		_height = height;
		_fps = fps;
		_crf = crf;
		_frames = 0;
		_videoOnly = outputDir + 'video_only.mp4';

		_ffmpeg = locate(log);
		if (_ffmpeg == '') return false;

		_encoder = requestedEncoder;
		if (_encoder == 'h264_nvenc' && !hasEncoder(_ffmpeg, 'h264_nvenc'))
		{
			_encoder = 'libx264';
			log('[encoder] h264_nvenc unavailable, falling back to libx264');
		}

		var args:Array<String> = [
			'-y', '-hide_banner', '-loglevel', 'error', '-nostats',
			'-f', 'rawvideo', '-pix_fmt', 'rgba',
			'-s', width + 'x' + height, '-r', Std.string(fps), '-i', 'pipe:0',
			'-an'
		];
		if (_encoder == 'h264_nvenc')
			args = args.concat(['-c:v', 'h264_nvenc', '-preset', 'p4', '-cq', Std.string(crf), '-pix_fmt', 'yuv420p']);
		else
			args = args.concat(['-c:v', 'libx264', '-preset', 'veryfast', '-crf', Std.string(crf), '-pix_fmt', 'yuv420p']);
		args.push(_videoOnly);

		try
		{
			_proc = new Process(_ffmpeg, args);
			var p:Process = _proc;
			// ffmpeg 的 stderr 缓冲写满会反过来阻塞 stdin；后台线程持续排空。
			// -loglevel error -nostats 已把输出压到极小，这里只是兜底。
			Thread.create(function()
			{
				try { while (true) p.stderr.readByte(); }
				catch (e:Dynamic) {}
			});
			_running = true;
			log('[encoder] pipe started: ' + _ffmpeg + ' / ' + _encoder
				+ ' / ' + width + 'x' + height + '@' + fps + ' / crf=' + crf);
			return true;
		}
		catch (e:Dynamic)
		{
			log('[encoder] pipe start FAILED: ' + Std.string(e));
			_proc = null;
			return false;
		}
	}

	/** 写一帧 RGBA 原始像素（零拷贝，直接写 stdin） */
	public static function writeFrame(bytes:Bytes):Void
	{
		if (!_running || _proc == null) return;
		_proc.stdin.writeBytes(bytes, 0, bytes.length);
		_frames++;
	}

	public static function isRunning():Bool return _running && _proc != null;

	/**
	 * 中断收尾：只关 stdin 让 ffmpeg 正常 finalize，跳过混音 / 拼接等耗时后期。
	 * 这一步绝不能省——不关 stdin 的话 MP4 没有 moov atom，文件直接报废。
	 * 返回可播放的 partial.mp4 路径（失败返回 ''）。
	 */
	public static function abort(log:String->Void):String
	{
		if (!_running || _proc == null) return '';
		_running = false;
		try { _proc.stdin.close(); } catch (e:Dynamic) {}
		var code:Int = -1;
		try { code = _proc.exitCode(); } catch (e:Dynamic) {}
		try { _proc.close(); } catch (e:Dynamic) {}
		_proc = null;
		log('[encoder] ABORT pipe closed exit=' + code + ' frames=' + _frames);
		if (code == 0 && FileSystem.exists(_videoOnly))
		{
			var partial:String = _outputDir + 'partial.mp4';
			try
			{
				File.copy(_videoOnly, partial);
				log('[encoder] partial video saved: ' + partial);
				return partial;
			}
			catch (e:Dynamic) log('[encoder] partial copy failed: ' + Std.string(e));
		}
		return '';
	}

	/**
	 * 收尾：关闭 stdin → 等待编码结束 → 混入音轨 → 拼接过场。
	 * 返回最终 MP4 路径（失败返回 ''）。
	 */
	public static function finish(song:String, playbackRate:Float, offsetMs:Float,
		mixAudio:Bool, cutscenes:Array<String>, log:String->Void):String
	{
		if (!_running || _proc == null) return '';
		_running = false;
		try { _proc.stdin.close(); } catch (e:Dynamic) {}
		var code:Int = -1;
		try { code = _proc.exitCode(); } catch (e:Dynamic) {}
		try { _proc.close(); } catch (e:Dynamic) {}
		_proc = null;
		log('[encoder] pipe closed exit=' + code + ' frames=' + _frames
			+ ' size=' + (FileSystem.exists(_videoOnly) ? FileSystem.stat(_videoOnly).size : 0));

		if (code != 0 || !FileSystem.exists(_videoOnly)) return '';

		var finalPath:String = _outputDir + 'output.mp4';
		var audio:Array<String> = mixAudio ? collectAudio(song, log) : [];

		if (audio.length == 0)
		{
			try { File.copy(_videoOnly, finalPath); }
			catch (e:Dynamic) { log('[encoder] copy failed: ' + Std.string(e)); return ''; }
			log('[encoder] no audio mixed (mixAudio=false or no audio files found)');
		}
		else if (!muxAudio(_videoOnly, finalPath, audio, playbackRate, offsetMs, log))
		{
			log('[encoder] audio mux failed, falling back to video-only copy');
			try { File.copy(_videoOnly, finalPath); } catch (e:Dynamic) { return ''; }
		}

		if (cutscenes != null && cutscenes.length > 0 && FileSystem.exists(finalPath))
		{
			var joined:String = _outputDir + 'with_cutscenes.mp4';
			if (joinCutscenes(finalPath, joined, cutscenes, audio.length > 0, log))
			{
				log('[encoder] cutscenes joined -> ' + joined);
				return joined;
			}
			log('[encoder] cutscene join failed, delivering main video only');
		}
		return finalPath;
	}

	/** 按引擎的加载顺序探测当前曲目的伴奏 / 人声文件 */
	static function collectAudio(song:String, log:String->Void):Array<String>
	{
		var out:Array<String> = [];
		var modDir:String = Mods.currentModDirectory;
		var bases:Array<String> = [];
		var s = PlayState.SONG;
		if (s != null && s.specialInst != null && s.specialInst.length > 0)
			bases.push('Inst-' + s.specialInst);
		bases.push('Inst');
		if (s != null && s.specialVocal != null && s.specialVocal.length > 0)
		{
			bases.push('Voices-' + s.specialVocal);
			bases.push('Voices-Player-' + s.specialVocal);
			bases.push('Voices-Opponent-' + s.specialVocal);
		}
		bases = bases.concat(['Voices', 'Voices-Player', 'Voices-Opponent']);
		for (b in bases)
		{
			var p:String = Paths.getSongAudioPath(song, b, modDir);
			if (p != null && FileSystem.exists(p) && out.indexOf(p) < 0) out.push(p);
		}
		log('[encoder] audio files (' + out.length + '): ' + out.join(' | '));
		return out;
	}

	static function muxAudio(video:String, out:String, audio:Array<String>,
		rate:Float, offsetMs:Float, log:String->Void):Bool
	{
		var args:Array<String> = ['-y', '-hide_banner', '-loglevel', 'error', '-i', video];
		for (a in audio) args = args.concat(['-i', a]);

		var n:Int = audio.length;
		var fc:String = '';
		var labels:Array<String> = [];
		for (i in 0...n)
		{
			var src:String = '[' + (i + 1) + ':a]';
			if (rate != 1 && rate > 0.5 && rate < 2.0)
			{
				fc += src + 'atempo=' + rate + '[a' + i + '];';
				labels.push('[a' + i + ']');
			}
			else labels.push(src);
		}
		fc += labels.join('') + 'amix=inputs=' + n + ':duration=first:normalize=0';
		if (offsetMs > 0) fc += ',adelay=' + Std.int(offsetMs) + '|' + Std.int(offsetMs);
		fc += '[a]';

		args = args.concat([
			'-filter_complex', fc,
			'-map', '0:v', '-map', '[a]',
			'-c:v', 'copy', '-c:a', 'aac', '-b:a', '192k', '-shortest', out
		]);
		log('[encoder] mux args: ' + args.join(' '));
		return run(args, log, 'mux');
	}

	/** 片头拼接过场：统一缩放/帧率后用 concat filter，失败不影响主视频 */
	static function joinCutscenes(main:String, out:String, cuts:Array<String>, hasAudio:Bool, log:String->Void):Bool
	{
		var args:Array<String> = ['-y', '-hide_banner', '-loglevel', 'error', '-i', main];
		var idx:Int = 1;
		for (c in cuts) if (c != null && FileSystem.exists(c)) { args = args.concat(['-i', c]); idx++; }
		if (idx < 2) return false;

		var fc:String = '';
		var cvLabels:Array<String> = [];
		var caLabels:Array<String> = [];
		for (i in 1...idx)
		{
			// filter 名是 setpts，不是 setspts
			fc += '[' + i + ':v]scale=' + _width + ':' + _height + ',setsar=1,fps=' + _fps
				+ ',format=yuv420p,setpts=PTS-STARTPTS[cv' + i + '];';
			cvLabels.push('[cv' + i + ']');
			if (hasAudio)
			{
				fc += '[' + i + ':a]aresample=async=1[ca' + i + '];';
				caLabels.push('[ca' + i + ']');
			}
		}

		if (hasAudio)
		{
			// concat 要求每个片段的 v/a 交错：[v0][a0][v1][a1]...
			var all:Array<String> = [];
			for (i in 0...cvLabels.length) { all.push(cvLabels[i]); all.push(caLabels[i]); }
			all.push('[0:v]'); all.push('[0:a]');
			fc += all.join('') + 'concat=n=' + idx + ':v=1:a=1[v][a]';
			args = args.concat([
				'-filter_complex', fc, '-map', '[v]', '-map', '[a]',
				'-c:v', 'libx264', '-preset', 'veryfast', '-crf', Std.string(_crf),
				'-c:a', 'aac', '-b:a', '192k', out
			]);
		}
		else
		{
			// 主视频无音轨（关闭混音或未找到音频）时只拼画面
			var vs:Array<String> = cvLabels.copy();
			vs.push('[0:v]');
			fc += vs.join('') + 'concat=n=' + idx + ':v=1:a=0[v]';
			args = args.concat([
				'-filter_complex', fc, '-map', '[v]', '-an',
				'-c:v', 'libx264', '-preset', 'veryfast', '-crf', Std.string(_crf), out
			]);
		}
		log('[encoder] cutscene args: ' + args.join(' '));
		return run(args, log, 'cutscene');
	}

	static function run(args:Array<String>, log:String->Void, tag:String):Bool
	{
		try
		{
			var p = new Process(_ffmpeg, args);
			var err:String = '';
			try { err = p.stderr.readAll().toString(); } catch (e:Dynamic) {}
			var code:Int = p.exitCode();
			p.close();
			if (code != 0) log('[encoder] ' + tag + ' failed (' + code + '): ' + err);
			return code == 0;
		}
		catch (e:Dynamic)
		{
			log('[encoder] ' + tag + ' exception: ' + Std.string(e));
			return false;
		}
	}
}
