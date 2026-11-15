package backend;

import sys.io.Process;
import sys.io.File;
import sys.FileSystem;
import sys.thread.Thread;
import haxe.io.Bytes;

/** 合成所需的音频信息，全部来自渲染期 PlayState 的真实记录 */
typedef RenderAudioInfo = {
	var song:String;
	var rate:Float;
	var offsetMs:Float;
	var mixAudio:Bool;
	var cutscenes:Array<String>;
	var songAudio:Array<String>;
	var soundEvents:Array<{key:String, atMs:Float, volume:Float}>;
	var leadMs:Float;
	var durationSec:Float;
}

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
			args = args.concat(['-c:v', 'h264_nvenc', '-preset', 'p5', '-rc', 'vbr', '-cq', Std.string(crf), '-pix_fmt', 'yuv420p']);
		else
			// 离线渲染不赶时间：medium + tune animation 在同 crf 下明显优于 veryfast，
			// 尤其保住 UI 文字 / 高对比边缘。tune animation 针对卡通风格优化。
			args = args.concat([
				'-c:v', 'libx264', '-preset', 'medium', '-tune', 'animation',
				'-crf', Std.string(crf), '-pix_fmt', 'yuv420p'
			]);
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
	public static function finish(info:RenderAudioInfo, log:String->Void):String
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
		var audioMixed:Bool = false;
		if (info.mixAudio)
		{
			var wav:String = _outputDir + 'audio_track.wav';
			if (buildAudioTrack(wav, info, log))
			{
				var args:Array<String> = [
					'-y', '-hide_banner', '-loglevel', 'error',
					'-i', _videoOnly, '-i', wav,
					'-map', '0:v', '-map', '1:a',
					'-c:v', 'copy', '-c:a', 'aac', '-b:a', '192k',
					'-t', fmtTime(info.durationSec), finalPath
				];
				audioMixed = run(args, log, 'mux');
			}
			if (!audioMixed) log('[encoder] audio build/mux failed, falling back to video-only');
		}
		if (!audioMixed)
		{
			try { File.copy(_videoOnly, finalPath); }
			catch (e:Dynamic) { log('[encoder] copy failed: ' + Std.string(e)); return ''; }
			log('[encoder] video only (mixAudio=false or no usable audio)');
		}

		if (info.cutscenes != null && info.cutscenes.length > 0 && FileSystem.exists(finalPath))
		{
			var joined:String = _outputDir + 'with_cutscenes.mp4';
			if (joinCutscenes(finalPath, joined, info.cutscenes, audioMixed, log))
			{
				log('[encoder] cutscenes joined -> ' + joined);
				return joined;
			}
			log('[encoder] cutscene join failed, delivering main video only');
		}
		return finalPath;
	}

	static function fmtTime(sec:Float):String
		return Std.string(Math.round(sec * 1000) / 1000);

	/**
	 * 重建音轨：主音轨整体延后 leadMs+offsetMs（倒计时段），
	 * 倒计时等即时音效按各自记录的视频时间点叠加，最后裁剪到视频时长。
	 * 分两步产出 wav 再与视频封装，避免 -shortest 把视频尾部裁掉。
	 */
	static function buildAudioTrack(out:String, info:RenderAudioInfo, log:String->Void):Bool
	{
		var tracks:Array<String> = [];
		if (info.songAudio != null)
			for (p in info.songAudio)
				if (p != null && FileSystem.exists(p) && tracks.indexOf(p) < 0) tracks.push(p);
		if (tracks.length == 0)
		{
			log('[encoder] no recorded song tracks, using filename fallback');
			tracks = collectAudioFallback(info.song, log);
		}
		if (tracks.length == 0 && (info.soundEvents == null || info.soundEvents.length == 0)) return false;

		var mainCount:Int = tracks.length;
		var sfxFiles:Array<String> = [];
		var delays:Array<Float> = [];
		var volumes:Array<Float> = [];
		// 视频 t 时 songPosition = (-lead + offset) + t*rate，而 music.time = songPosition - offset，
		// 所以音频起点正好是 t = lead/rate —— offset 在两端抵消，不需要额外叠加。
		var songDelay:Float = info.leadMs;
		if (info.soundEvents != null)
		{
			for (e in info.soundEvents)
			{
				var f:String = resolveSound(e.key, log);
				if (f == null) continue;
				sfxFiles.push(f);
				// e.atMs 已经是相对视频起点的绝对位置，不能再加 songDelay
				delays.push(e.atMs);
				volumes.push(e.volume);
			}
		}
		log('[encoder] audio plan: songTracks=' + tracks.length + ' sfx=' + sfxFiles.length
			+ ' songDelay=' + Math.round(songDelay) + 'ms duration=' + fmtTime(info.durationSec) + 's');

		var all:Array<String> = tracks.concat(sfxFiles);
		var args:Array<String> = ['-y', '-hide_banner', '-loglevel', 'error'];
		for (f in all) args = args.concat(['-i', f]);

		var fc:String = '';
		var labels:Array<String> = [];
		for (i in 0...mainCount)
		{
			fc += '[' + i + ':a]aresample=48000,aformat=sample_fmts=fltp:channel_layouts=stereo';
			if (info.rate != 1 && info.rate > 0.5 && info.rate < 2.0) fc += ',atempo=' + info.rate;
			if (songDelay > 0) fc += ',adelay=' + Std.int(songDelay) + ':all=1';
			fc += '[a' + i + '];';
			labels.push('[a' + i + ']');
		}
		for (j in 0...sfxFiles.length)
		{
			var i:Int = mainCount + j;
			fc += '[' + i + ':a]aresample=48000,aformat=sample_fmts=fltp:channel_layouts=stereo'
				+ ',volume=' + volumes[j]
				+ ',adelay=' + Std.int(delays[j]) + ':all=1[a' + i + '];';
			labels.push('[a' + i + ']');
		}
		fc += labels.join('') + 'amix=inputs=' + all.length
			+ ':duration=longest:normalize=0,apad,atrim=0:' + fmtTime(info.durationSec) + '[a]';

		args = args.concat([
			'-filter_complex', fc, '-map', '[a]',
			'-c:a', 'pcm_s16le', '-t', fmtTime(info.durationSec), out
		]);
		log('[encoder] audio args: ' + args.join(' '));
		return run(args, log, 'audio track');
	}

	/** 兜底：没有渲染期记录时，只选一条 Inst，绝不把多个 Inst 变体叠加 */
	static function collectAudioFallback(song:String, log:String->Void):Array<String>
	{
		var out:Array<String> = [];
		var modDir:String = Mods.currentModDirectory;
		var s = PlayState.SONG;
		var instBase:String = (s != null && s.specialInst != null && s.specialInst.length > 0)
			? 'Inst-' + s.specialInst : 'Inst';
		var ip:String = Paths.getSongAudioPath(song, instBase, modDir);
		if (!FileSystem.exists(ip)) ip = Paths.getSongAudioPath(song, 'Inst', modDir);
		if (FileSystem.exists(ip)) out.push(ip);
		var vocalSuffix:String = (s != null && s.specialVocal != null && s.specialVocal.length > 0)
			? '-' + s.specialVocal : '';
		for (b in ['Voices-Player', 'Voices-Opponent', 'Voices'])
		{
			var p:String = Paths.getSongAudioPath(song, b + vocalSuffix, modDir);
			if (FileSystem.exists(p) && out.indexOf(p) < 0) out.push(p);
		}
		log('[encoder] fallback audio files (' + out.length + '): ' + out.join(' | '));
		return out;
	}

	/** 倒计时音效：先查当前模组覆盖，再回退 assets/shared/sounds */
	static function resolveSound(key:String, log:String->Void):String
	{
		var ext:String = Paths.SOUND_EXT;
		var modDir:String = Mods.currentModDirectory;
		var candidates:Array<String> = [];
		if (modDir != null && modDir.length > 0)
		{
			candidates.push('mods/' + modDir + '/sounds/' + key + '.' + ext);
			candidates.push('mods/' + modDir + '/shared/sounds/' + key + '.' + ext);
		}
		candidates.push('assets/shared/sounds/' + key + '.' + ext);
		for (c in candidates) if (FileSystem.exists(c)) return c;
		log('[encoder] sfx not found: ' + key);
		return null;
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
				'-c:v', 'libx264', '-preset', 'medium', '-tune', 'animation', '-crf', Std.string(_crf),
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
				'-c:v', 'libx264', '-preset', 'medium', '-tune', 'animation', '-crf', Std.string(_crf), out
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
