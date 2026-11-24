package backend;

import sys.io.Process;
import sys.io.File;
import sys.FileSystem;
import sys.thread.Thread;
import haxe.io.Bytes;
import hx.concurrent.collection.Queue;
import sys.thread.Mutex;
import sys.thread.Semaphore;

/** 合成所需的音频信息，全部来自渲染期 PlayState 的真实记录 */
typedef RenderAudioInfo = {
	var song:String;
	var rate:Float;
	var offsetMs:Float;
	var mixAudio:Bool;
	var cutscenes:Array<String>;
	var songAudio:Array<String>;
	var soundEvents:Array<{key:String, atMs:Float, volume:Float}>;
	/** 渲染期自动捕获的中途音效（事件 / 脚本 / stage 播放的音频） */
	var sfx:Array<{path:String, atMs:Float, volume:Float, looped:Bool, durMs:Float, ?pitch:Float}>;
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
	static var _preset:String = 'faster'; // x264 速度/压缩率权衡（ultrafast~slow）
	static var _videoOnly:String = '';
	static var _outputDir:String = '';
	static var _width:Int = 1280;
	static var _height:Int = 720;
	static var _fps:Int = 60;
	static var _crf:Int = 20;
	/** 像素级无损：libx264rgb + qp=0 + rgb24，RGB 值逐像素保真 */
	static var _lossless:Bool = false;
	static var _frames:Int = 0;
	static var _running:Bool = false;

	// ===== 异步写入流水线：GPU 读回(主线程) 与 ffmpeg 编码(后台线程) 重叠 =====
	/** 待写入 ffmpeg 的帧队列；Bytes 在主线程生成，writer 线程只管写管道 */
	static var _writeQueue:Queue<Bytes> = null;
	/** 剩余槽位信号量：上限 8 帧（8×8.3MB≈66MB），防止内存无限堆积 */
	static var _slots:Semaphore = null;
	/** writer 线程是否已退出（队列排空且收到结束信号） */
	static var _writerDone:Bool = false;
	/** writer 停止标志：drain 时置位，避免用 null 哨兵（Queue 对 null 处理不可靠） */
	static var _stopWriter:Bool = false;
	/** writer 线程已成功写入的帧数（用于收尾对账，避免依赖槽位计数造成死锁） */
	static var _writtenFrames:Int = 0;
	/** 保存 log 回调，供无参的 drainAndClose 使用 */
	static var _log:String->Void = null;
	static inline var QUEUE_CAP:Int = 8;

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
		requestedEncoder:String, lossless:Bool, log:String->Void, preset:String = 'faster'):Bool
	{
		_outputDir = outputDir;
		_width = width;
		_height = height;
		_fps = fps;
		_crf = crf;
		_lossless = lossless;
		_log = log;
		_frames = 0;
		_videoOnly = outputDir + 'video_only.mp4';

		_ffmpeg = locate(log);
		if (_ffmpeg == '') return false;

		_encoder = requestedEncoder;
		// 校验 preset 合法性（防存档里是旧值/非法值），非法则回退默认
		var validPresets:Array<String> = ['ultrafast', 'veryfast', 'faster', 'fast', 'medium', 'slow'];
		_preset = validPresets.contains(preset) ? preset : 'faster';
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
		if (_lossless)
		{
			// 真无损：RGB 像素直接进 libx264rgb，qp=0 不做有损量化。
			// ultrafast 只影响压缩率，不影响无损性；成片会很大，但每个像素可复现。
			if (hasEncoder(_ffmpeg, 'libx264rgb'))
			{
				_encoder = 'libx264rgb';
				args = args.concat([
					'-c:v', 'libx264rgb', '-preset', 'ultrafast',
					'-qp', '0', '-pix_fmt', 'rgb24'
				]);
				log('[encoder] LOSSLESS RGB: libx264rgb qp=0 rgb24 (pixel-exact)');
				log('[encoder] WARNING: lossless files are very large (often GBs); '
					+ 'keep the output drive fast and mostly empty, and use MP4-only output');
			}
			else
			{
				_encoder = 'libx264';
				args = args.concat([
					'-c:v', 'libx264', '-preset', 'ultrafast',
					'-qp', '0', '-pix_fmt', 'yuv444p'
				]);
				log('[encoder] libx264rgb unavailable -> yuv444p qp=0 (RGB->YUV may round)');
			}
		}
		else if (_encoder == 'h264_nvenc')
			args = args.concat(['-c:v', 'h264_nvenc', '-preset', 'p5', '-rc', 'vbr', '-cq', Std.string(crf), '-pix_fmt', 'yuv420p']);
		else
			// preset 可配置（默认 faster）：ultrafast 最快但文件大，slow 最省体积但慢。
			// tune animation 保留：针对卡通/像素风格与 UI 文字边缘优化。
			args = args.concat([
				'-c:v', 'libx264', '-preset', _preset, '-tune', 'animation',
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

			// 异步写入线程：主线程负责 GPU 读回并入队，这里并行把队列内容写进管道。
			// 这样 readPixels 的 GPU 等待与 ffmpeg 编码不再串行，充分利用多核。
			_writeQueue = new Queue<Bytes>();
			_slots = new Semaphore(QUEUE_CAP);
			_writerDone = false;
			_stopWriter = false;
			_writtenFrames = 0;
			Thread.create(function()
			{
				while (!_stopWriter)
				{
					// 短超时轮询：既避免忙等，又能及时响应 stopWriter 标志
					var b:Bytes = _writeQueue.pop(100);
					if (b == null) continue;
					try { p.stdin.writeBytes(b, 0, b.length); _writtenFrames++; }
					catch (e:Dynamic)
					{
						log('[encoder] writer error: ' + Std.string(e));
						break;
					}
					_slots.release(); // 归还槽位，唤醒被背压的主线程
				}
				_writerDone = true;
			});

			_running = true;
			log('[encoder] pipe started (async writer x' + QUEUE_CAP + '): ' + _ffmpeg + ' / ' + _encoder
				+ ' / ' + width + 'x' + height + '@' + fps
				+ (_lossless ? ' / qp=0 LOSSLESS' : ' / crf=' + crf));
			return true;
		}
		catch (e:Dynamic)
		{
			log('[encoder] pipe start FAILED: ' + Std.string(e));
			_proc = null;
		_log = null;
			return false;
		}
	}

	/**
	 * 提交一帧 RGBA 原始像素到异步写入队列。
	 * 队列满时会在此短暂背压（等 writer 归还槽位），但不直接等 ffmpeg 编码完成。
	 */
	public static function writeFrame(bytes:Bytes):Void
	{
		if (!_running || _proc == null) return;
		if (_slots != null) _slots.acquire(); // 有空槽才入队，控制内存上限
		if (_writeQueue != null) _writeQueue.push(bytes);
		_frames++;
	}

	/**
	 * 排空队列并关闭 stdin 前的同步点：等 writer 写完所有已入队的帧，
	 * 再置停止标志让它退出。必须在 stdin.close() 之前调用，否则会丢尾帧。
	 */
	static function drainAndClose():Void
	{
		if (_writeQueue != null)
		{
			var target:Int = _frames;
			// 等 writer 把所有已入队的帧写完（按实际写入帧数对账，writer 异常退出也不会死等）
			var waited:Int = 0;
			while (_writtenFrames < target && !_writerDone && waited < 30000)
			{
				Sys.sleep(0.002);
				waited += 2;
			}
			if (_writtenFrames != target && _log != null)
				_log('[encoder] drain mismatch: written=' + _writtenFrames + ' queued=' + target);
			_stopWriter = true; // 通知 writer 线程退出
			waited = 0;
			while (!_writerDone && waited < 2000)
			{
				Sys.sleep(0.005);
				waited += 5;
			}
		}
		_writeQueue = null;
		_slots = null;
	}

	public static function isRunning():Bool return _running && _proc != null;

	/** 当前 video_only 文件大小（MB），用于诊断无损模式随文件增长变慢的问题 */
	public static function videoSizeMB():Float
		return Math.round(safeFileSize(_videoOnly) / 1024 / 1024 * 10) / 10;

	/**
	 * 中断收尾：只关 stdin 让 ffmpeg 正常 finalize，跳过混音 / 拼接等耗时后期。
	 * 这一步绝不能省——不关 stdin 的话 MP4 没有 moov atom，文件直接报废。
	 * 返回可播放的 partial.mp4 路径（失败返回 ''）。
	 */
	public static function abort(log:String->Void):String
	{
		if (!_running || _proc == null) return '';
		_running = false;
		drainAndClose(); // 先把队列里已提交的帧写完，再关 stdin
		try { _proc.stdin.close(); } catch (e:Dynamic) {}
		var code:Int = -1;
		try { code = _proc.exitCode(); } catch (e:Dynamic) {}
		try { _proc.close(); } catch (e:Dynamic) {}
		_proc = null;
		_log = null;
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
		drainAndClose(); // 等队列排空再关 stdin，保证尾帧不丢
		try { _proc.stdin.close(); } catch (e:Dynamic) {}
		var code:Int = -1;
		try { code = _proc.exitCode(); } catch (e:Dynamic) {}
		try { _proc.close(); } catch (e:Dynamic) {}
		_proc = null;
		_log = null;
		// 日志文件大小只是诊断信息：ffmpeg 刚写完 2GB+ 文件时，Windows 上
		// 文件可能被杀软/索引短暂锁定，FileSystem.stat 偶发抛 "Could not stat"。
		// 绝不能让这种非关键统计把整个 finish() 流程打断（否则音频合成与 mux 都不执行）。
		log('[encoder] pipe closed exit=' + code + ' frames=' + _frames
			+ ' size=' + safeFileSize(_videoOnly));

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

	/** 安全读取文件大小：stat 偶发失败（文件被占用/刚写完未刷新）时返回 0，绝不抛异常。 */
	static function safeFileSize(path:String):Float
	{
		if (path == null) return 0;
		try
		{
			if (!FileSystem.exists(path)) return 0;
			return FileSystem.stat(path).size;
		}
		catch (e:Dynamic) { return 0; }
	}

	/**
	 * 把所有即时音效（倒计时 + 自动捕获）预混成一条独立的音效床 WAV。
	 *
	 * 为什么需要：旧实现把每条音效都作为独立 `-i` 输入喂给 ffmpeg，
	 * 而 Windows 命令行上限 ~32767 字符，约 500 条就撑爆 → ffmpeg 启动失败 → 成片无声。
	 * spamchart（NPS 上千 + 打击音）轻易数千条，必然触发。
	 *
	 * 新实现：按文件路径分组（同一音效文件只开一个输入），每路径用 asplit 复制多路、
	 * 各自 adelay 到发生时刻再 amix；filter 写进脚本文件（无长度限制）。
	 * 每组超过 SFX_BATCH 条时分批混入中间 WAV，再递归合并，保证 O(N) 可扩展。
	 *
	 * @return 音效床 WAV 路径；无有效音效返回 null（调用方跳过音效床）
	 */
	static function buildSfxBed(out:String, sfxFiles:Array<String>, delays:Array<Float>,
		volumes:Array<Float>, durs:Array<Float>, loops:Array<Bool>, pitches:Array<Float>,
		durationSec:Float, log:String->Void):String
	{
		if (sfxFiles.length == 0) return null;

		// 按路径分组：key=文件路径，value=该文件的所有事件索引
		var groups:Map<String, Array<Int>> = new Map();
		var groupCount:Int = 0;
		for (i in 0...sfxFiles.length)
		{
			var g = groups.get(sfxFiles[i]);
			if (g == null) { g = []; groups.set(sfxFiles[i], g); groupCount++; }
			g.push(i);
		}
		log('[encoder] sfx bed: ' + sfxFiles.length + ' events / ' + groupCount
			+ ' unique files');

		var tmpDir:String = out + '_sfxparts/';
		try { if (!FileSystem.exists(tmpDir)) FileSystem.createDirectory(tmpDir); }
		catch (e:Dynamic) { log('[encoder] sfx tmp dir failed: ' + Std.string(e)); return null; }

		var partFiles:Array<String> = [];
		var groupIdx:Int = 0;
		for (path => idxs in groups)
		{
			// 每组按 SFX_BATCH 分批，避免单批 asplit/amix 路数过大
			var batch:Int = 0;
			while (batch < idxs.length)
			{
				var end:Int = Std.int(Math.min(batch + SFX_BATCH, idxs.length));
				var partPath:String = tmpDir + 'g' + groupIdx + '_b' + batch + '.wav';
				if (mixSfxBatch(path, idxs, batch, end, sfxFiles, delays, volumes, durs,
					loops, pitches, durationSec, partPath, log))
					partFiles.push(partPath);
				batch = end;
			}
			groupIdx++;
		}
		if (partFiles.length == 0) return null;

		// 各分组批次混成一条音效床；批次少时一次 amix，多时递归分批
		var bedPath:String = out;
		if (partFiles.length <= SFX_BATCH)
		{
			var args:Array<String> = ['-y', '-hide_banner', '-loglevel', 'error'];
			// 用 amix 合并（partFiles 数量已被分组压到很小）
			var fc:String = '';
			for (i in 0...partFiles.length) fc += '[' + i + ':a]';
			fc += 'amix=inputs=' + partFiles.length + ':duration=longest:normalize=0[a]';
			for (f in partFiles) args = args.concat(['-i', f]);
			args = args.concat(['-filter_complex', fc, '-map', '[a]',
				'-c:a', 'pcm_s16le', '-t', fmtTime(durationSec), bedPath]);
			if (!run(args, log, 'sfx bed merge')) return null;
		}
		else
		{
			// 极端情况：批次仍多，递归两两合并
			var cur:Array<String> = partFiles;
			var round:Int = 0;
			while (cur.length > 1)
			{
				var next:Array<String> = [];
				var i:Int = 0;
				while (i < cur.length)
				{
					var chunk:Array<String> = cur.slice(i, Std.int(Math.min(i + SFX_BATCH, cur.length)));
					var merged:String = tmpDir + 'merge' + round + '_' + i + '.wav';
					var args:Array<String> = ['-y', '-hide_banner', '-loglevel', 'error'];
					var fc:String = '';
					for (k in 0...chunk.length) fc += '[' + k + ':a]';
					fc += 'amix=inputs=' + chunk.length + ':duration=longest:normalize=0[a]';
					for (f in chunk) args = args.concat(['-i', f]);
					args = args.concat(['-filter_complex', fc, '-map', '[a]',
						'-c:a', 'pcm_s16le', '-t', fmtTime(durationSec), merged]);
					if (run(args, log, 'sfx merge r' + round)) next.push(merged);
					i += SFX_BATCH;
				}
				cur = next;
				round++;
			}
			if (cur.length == 0) return null;
			if (cur[0] != bedPath)
			{
				try { File.copy(cur[0], bedPath); } catch (e:Dynamic) { return null; }
			}
		}
		// 清理中间文件
		try { for (f in FileSystem.readDirectory(tmpDir)) FileSystem.deleteFile(tmpDir + f); FileSystem.deleteDirectory(tmpDir); }
		catch (e:Dynamic) {}
		log('[encoder] sfx bed ready: ' + bedPath);
		return bedPath;
	}

	/** 单文件单批次：一个 -i + asplit 多路 adelay + amix，filter 写脚本文件 */
	static function mixSfxBatch(path:String, idxs:Array<Int>, from:Int, to:Int,
		sfxFiles:Array<String>, delays:Array<Float>, volumes:Array<Float>, durs:Array<Float>,
		loops:Array<Bool>, pitches:Array<Float>, durationSec:Float, outPath:String, log:String->Void):Bool
	{
		var n:Int = to - from;
		if (n <= 0) return false;
		var scriptPath:String = outPath + '.filter.txt';
		var sb:StringBuf = new StringBuf();
		sb.add('[0:a]aresample=48000,aformat=sample_fmts=fltp:channel_layouts=stereo,asplit=' + n);
		for (i in 0...n) sb.add('[s' + i + ']');
		sb.add(';\n');
		for (i in 0...n)
		{
			var src:Int = idxs[from + i];
			var pitch:Float = (pitches != null && src < pitches.length && pitches[src] > 0.01) ? pitches[src] : 1;
			var dur:Float = durs[src];
			if (dur <= 0) dur = Math.max(0, durationSec - delays[src] / 1000);
			// label 必须紧跟第一个 filter 名，不能单独输出 [s0] 后再接逗号——
			// 那会生成 "[s0],atrim=..." 这种空 filter，ffmpeg 报 "No such filter: ''" 并使整条音效床失败。
			sb.add('[s' + i + ']');
			// 变调处理：asetrate 改采样率实现升/降调，aresample 恢复到 48k。
			// 这与 FNF 的 FlxSound.pitch 语义一致（改播放速率 → 音高与时长同时变化），
			// archiveSfx 已按 length/pitch 换算过输出时长。
			if (Math.abs(pitch - 1) > 0.01)
				sb.add('asetrate=48000*' + Std.string(pitch) + ',aresample=48000,');
			// dur 已经是 pitch 变速后的输出时长（archiveSfx 里按 length/pitch 算的），
			// atrim 作用在 asetrate 之后的输出时间轴上，直接用 dur 即可。
			sb.add('atrim=0:' + fmtTime(dur / 1000) + ',asetpts=PTS-STARTPTS');
			if (volumes[src] != 1) sb.add(',volume=' + volumes[src]);
			if (delays[src] > 0) sb.add(',adelay=' + Std.int(delays[src]) + ':all=1');
			sb.add('[b' + i + '];\n');
		}
		for (i in 0...n) sb.add('[b' + i + ']');
		sb.add('amix=inputs=' + n + ':duration=longest:normalize=0,alimiter=limit=0.89:level=false[a]');
		try { File.saveContent(scriptPath, sb.toString()); }
		catch (e:Dynamic) { log('[encoder] sfx filter write failed: ' + Std.string(e)); return false; }

		var args:Array<String> = ['-y', '-hide_banner', '-loglevel', 'error'];
		if (loops[idxs[from]]) args = args.concat(['-stream_loop', '-1']);
		args = args.concat(['-i', path, '-filter_complex_script', scriptPath, '-map', '[a]',
			'-c:a', 'pcm_s16le', '-t', fmtTime(durationSec), outPath]);
		var ok:Bool = run(args, log, 'sfx batch n=' + n);
		try { FileSystem.deleteFile(scriptPath); } catch (e:Dynamic) {}
		return ok;
	}

	/** 单批 asplit 路数上限：超过则分批，兼顾性能与可扩展 */
	static inline var SFX_BATCH:Int = 400;

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
		if (tracks.length == 0 && (info.soundEvents == null || info.soundEvents.length == 0)
			&& (info.sfx == null || info.sfx.length == 0)) return false;

		var mainCount:Int = tracks.length;
		var sfxFiles:Array<String> = [];
		var delays:Array<Float> = [];
		var volumes:Array<Float> = [];
		var durs:Array<Float> = [];
		var loops:Array<Bool> = [];
		var pitches:Array<Float> = [];
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
				durs.push(-1);
				loops.push(false);
				pitches.push(1);
			}
		}
		// 渲染期自动捕获的中途音效（事件 / 脚本 / stage 播放的音频），路径已在游戏内解析好
		var autoCount:Int = 0;
		if (info.sfx != null)
		{
			for (e in info.sfx)
			{
				if (e == null || e.path == null || e.volume <= 0.001) continue;
				if (!FileSystem.exists(e.path))
				{
					log('[encoder] sfx missing on disk: ' + e.path);
					continue;
				}
				sfxFiles.push(e.path);
				delays.push(Math.max(0, e.atMs));
				volumes.push(e.volume);
				durs.push(e.durMs);
				loops.push(e.looped);
				pitches.push(e.pitch != null && e.pitch > 0.01 ? e.pitch : 1);
				autoCount++;
			}
		}
		log('[encoder] audio plan: songTracks=' + tracks.length + ' sfx=' + sfxFiles.length
			+ ' (auto=' + autoCount + ') songDelay=' + Math.round(songDelay)
			+ 'ms duration=' + fmtTime(info.durationSec) + 's');

		// 先把所有即时音效预混成一条音效床 WAV —— 避免每条音效一个 -i 撑爆命令行。
		// 音效床失败（极端情况）时静默降级为只有主音轨，绝不让整条音频合成失败。
		var sfxBed:String = null;
		if (sfxFiles.length > 0)
		{
			sfxBed = buildSfxBed(out + '.sfxbed.wav', sfxFiles, delays, volumes, durs,
				loops, pitches, info.durationSec, log);
			if (sfxBed == null) log('[encoder] sfx bed failed, mixing song tracks only');
		}

		// 主输入 = 主音轨（Inst / Voices）+ 可选的一条音效床。输入数恒定很小。
		var all:Array<String> = tracks.copy();
		if (sfxBed != null) all.push(sfxBed);
		var args:Array<String> = ['-y', '-hide_banner', '-loglevel', 'error'];
		for (f in all) args = args.concat(['-i', f]);

		var fc:String = '';
		var labels:Array<String> = [];
		for (i in 0...tracks.length)
		{
			fc += '[' + i + ':a]aresample=48000,aformat=sample_fmts=fltp:channel_layouts=stereo';
			if (info.rate != 1 && info.rate > 0.5 && info.rate < 2.0) fc += ',atempo=' + info.rate;
			if (songDelay > 0) fc += ',adelay=' + Std.int(songDelay) + ':all=1';
			fc += '[a' + i + '];';
			labels.push('[a' + i + ']');
		}
		if (sfxBed != null)
		{
			var bi:Int = tracks.length;
			fc += '[' + bi + ':a]aresample=48000,aformat=sample_fmts=fltp:channel_layouts=stereo[a' + bi + '];';
			labels.push('[a' + bi + ']');
		}
		// 限幅防爆音：模组素材本身常是 0dB 满幅（无 headroom），
		// amix normalize=0 把多条满幅音轨原样相加后必然超过 0dB，
		// 写 16-bit PCM 时硬截断 → 削波爆音。
		// alimiter 做真峰值限制：limit=0.89 ≈ -1dB，留 1dB headroom；
		// level=false 关键——否则 limiter 会把信号重新放大回 limit，等于没限幅。
		fc += labels.join('') + 'amix=inputs=' + all.length
			+ ':duration=longest:normalize=0,alimiter=limit=0.89:level=false'
			+ ',apad,atrim=0:' + fmtTime(info.durationSec) + '[a]';

		args = args.concat([
			'-filter_complex', fc, '-map', '[a]',
			'-c:a', 'pcm_s16le', '-t', fmtTime(info.durationSec), out
		]);
		log('[encoder] audio args: ' + args.join(' '));
		var ok:Bool = run(args, log, 'audio track');
		// 清理音效床临时文件
		if (sfxBed != null) try { FileSystem.deleteFile(sfxBed); } catch (e:Dynamic) {}
		return ok;
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
