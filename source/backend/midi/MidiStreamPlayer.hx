package backend.midi;

import haxe.io.Bytes;

#if lime_openal
import lime.media.openal.AL;
import lime.media.openal.ALBuffer;
import lime.media.openal.ALC;
import lime.media.openal.ALContext;
import lime.media.openal.ALSource;
import lime.utils.UInt8Array;
import sys.thread.Mutex;
import sys.thread.Thread;
#end

#if (js && html5)
import js.html.audio.AudioBufferSourceNode;
import js.html.audio.AudioContext;
#end

#if !(lime_openal || (js && html5))
import lime.media.AudioBuffer;
import openfl.media.Sound;
import openfl.media.SoundChannel;
#end

/**
 *  实时流式 MIDI 播放器。
 *
 *  不再一次性渲染整首曲子，而是用 MidiStream 按小块产出 PCM：
 *  - 桌面 / Android：OpenAL 缓冲队列 + 独立音频线程持续补充 buffer，主线程卡顿不影响发声
 *  - HTML5：Web Audio 提前调度 2 秒 chunk，浏览器音频线程负责播放
 *  - 其它目标：降级为一次性渲染（仍能播放，但不是实时）
 */
class MidiStreamPlayer
{
	static inline var CHUNK_SAMPLES = 2048;   // ~93ms @22050Hz
	static inline var BUFFER_COUNT = 6;       // 约 0.55s 缓冲深度

	public var stream:MidiStream;
	public var playing:Bool = false;
	public var sampleRate:Int;
	public var fileName:String = "untitled.mid";

	public var progress(get, never):Float;
	public var position(get, never):Float;
	public var duration(get, never):Float;
	public var finished(get, never):Bool;
	public var activeVoices(get, never):Int;
	public var voiceLimit(get, never):Int;
	public var unlimitedVoices(get, set):Bool;
	public var workerCount(get, never):Int;

	var song:MidiSong;

	#if lime_openal
	var source:ALSource = null;
	var buffers:Array<ALBuffer> = null;
	var alContext:ALContext = null;
	var audioThread:Thread = null;
	var controlLock = new Mutex();
	var stopRequested:Bool = false;
	#end

	#if (js && html5)
	var audioCtx:AudioContext = null;
	var nextTime:Float = 0;
	var scheduled:Array<{node:AudioBufferSourceNode, end:Float}> = [];
	#end

	#if !(lime_openal || (js && html5))
	var channel:SoundChannel = null;
	var fallbackSound:Sound = null;
	var fallbackStartMs:Float = 0;
	#end

	public function new(song:MidiSong, ?sampleRate:Int = 22050)
	{
		this.song = song;
		this.sampleRate = sampleRate < 8000 ? 8000 : sampleRate;
		stream = new MidiStream(song, this.sampleRate);

	}

	public static function fromBytes(bytes:Bytes, ?sampleRate:Int = 22050, ?name:String):MidiStreamPlayer
	{
		var player = new MidiStreamPlayer(MidiParser.parse(bytes), sampleRate);
		if (name != null && name.length > 0)
			player.fileName = name;
		return player;
	}

	inline function get_progress():Float
	{
		return stream.durationSamples > 0
			? Math.min(1.0, stream.position / stream.durationSamples)
			: 0;
	}

	inline function get_position():Float
	{
		return stream.position / sampleRate;
	}

	inline function get_duration():Float
	{
		return stream.durationSamples / sampleRate;
	}

	inline function get_finished():Bool
	{
		return stream.finished;
	}

	inline function get_activeVoices():Int
	{
		return stream.activeVoices;
	}

	inline function get_voiceLimit():Int
	{
		return stream.voiceLimit;
	}

	inline function get_unlimitedVoices():Bool
	{
		return !stream.adaptiveVoices;
	}

	inline function set_unlimitedVoices(value:Bool):Bool
	{
		stream.adaptiveVoices = !value;
		if (value)
			stream.voiceLimit = MidiSynth.MAX_VOICES;
		return value;
	}

	inline function get_workerCount():Int
	{
		#if cpp
		return stream.workerCount;
		#else
		return 1;
		#end
	}

	public function play():Void
	{
		if (playing)
			return;
		#if lime_openal
		playOpenAL();
		#elseif (js && html5)
		playWebAudio();
		#else
		if (fallbackSound == null)
		{
			var wav = MidiSynth.render(song, sampleRate);
			fallbackSound = Sound.fromAudioBuffer(AudioBuffer.fromBytes(wav));
		}
		channel = fallbackSound.play(fallbackStartMs);
		playing = true;
		#end
	}

	/** 跳转到指定秒数；正在播放时会停下并从新位置重启音频。 */
	public function seek(time:Float):Void
	{
		var wasPlaying = playing;
		stop();
		stream.seek(Std.int(Math.max(0, time) * sampleRate));
		#if !(lime_openal || (js && html5))
		fallbackStartMs = Math.max(0, time) * 1000;
		#end
		if (wasPlaying)
			play();
	}

	public function dispose():Void
	{
		stop();
		#if cpp
		stream.dispose();
		#end
	}

	public function update():Void
	{
		if (!playing)
			return;
		// OpenAL 分支不需要主线程 pump：音频线程自己补 buffer
		#if (js && html5)
		pumpWebAudio();
		#end
	}

	public function stop():Void
	{
		#if lime_openal
		if (audioThread != null)
		{
			controlLock.acquire();
			stopRequested = true;
			controlLock.release();
			// 等音频线程退出（它每 10ms 检查一次标志），再回收 AL 对象
			Sys.sleep(0.03);
			audioThread = null;
		}
		// 只操作 source/buffer，绝不销毁 context 或 device
		var mainContext:ALContext = ALC.getCurrentContext();
		if (alContext != null)
			ALC.makeContextCurrent(alContext);

		if (source != null)
		{
			AL.sourceStop(source);
			AL.deleteSources([source]);
			source = null;
		}
		if (buffers != null)
		{
			AL.deleteBuffers(buffers);
			buffers = null;
		}

		// 恢复主线程原本的 context（不置 null，避免全局音频失去上下文）
		if (mainContext != null)
			ALC.makeContextCurrent(mainContext);
		alContext = null;
		#elseif (js && html5)
		for (item in scheduled)
		{
			try { item.node.stop(); } catch (e:Dynamic) {}
		}
		scheduled = [];
		#else
		if (channel != null)
		{
			channel.stop();
			channel = null;
		}
		#end
		playing = false;
	}

	#if lime_openal
	function playOpenAL():Void
	{
		// 复用 Lime/FlxG.sound 的全局 context，绝不创建或销毁 device
		alContext = ALC.getCurrentContext();
		if (alContext == null)
			throw "MIDI: OpenAL context 不可用";
		ALC.makeContextCurrent(alContext);

		var sources = AL.genSources(1);
		if (sources == null || sources.length == 0 || sources[0] == null)
			throw "MIDI: 无法创建 OpenAL source";
		source = sources[0];

		buffers = AL.genBuffers(BUFFER_COUNT);
		if (buffers == null || buffers.length == 0)
			throw "MIDI: 无法创建 OpenAL buffer";
		var filled = 0;
		for (buffer in buffers)
		{
			if (!fillBuffer(buffer))
				break;
			filled++;
		}
		if (filled == 0)
		{
			stop();
			return;
		}

		AL.sourceQueueBuffers(source, filled, buffers.slice(0, filled));
		AL.sourcePlay(source);
		playing = true;

		// 音频上下文是线程局部的，把全局 context 交给音频线程绑定
		controlLock.acquire();
		stopRequested = false;
		controlLock.release();
		audioThread = Thread.create(function() audioThreadLoop(alContext));
	}

	function audioThreadLoop(ctx:ALContext):Void
	{
		if (ctx != null)
			ALC.makeContextCurrent(ctx);

		while (true)
		{
			controlLock.acquire();
			var shouldStop = stopRequested;
			controlLock.release();
			if (shouldStop)
				break;

			pumpOpenAL();
			Sys.sleep(0.01);
		}

		if (ctx != null)
			ALC.makeContextCurrent(null);
	}

	function fillBuffer(buffer:ALBuffer):Bool
	{
		var bytes = stream.renderChunk(CHUNK_SAMPLES);
		if (bytes.length == 0)
			return false;

		var view = new UInt8Array(bytes.length);
		for (i in 0...bytes.length)
			view[i] = bytes.get(i);
		AL.bufferData(buffer, AL.FORMAT_MONO16, view, view.length, sampleRate);
		return true;
	}

	function pumpOpenAL():Void
	{
		if (source == null)
			return;
		var processed:Int = cast AL.getSourcei(source, AL.BUFFERS_PROCESSED);
		while (processed > 0)
		{
			var freed = AL.sourceUnqueueBuffers(source, 1);
			if (freed.length == 0)
				break;
			if (!fillBuffer(freed[0]))
			{
				processed = 0;
				break;
			}
			AL.sourceQueueBuffers(source, 1, [freed[0]]);
			processed--;
		}

		var state:Int = cast AL.getSourcei(source, AL.SOURCE_STATE);
		if (state == AL.STOPPED)
		{
			if (stream.finished)
				stop();
			else
				AL.sourcePlay(source);
		}
	}
	#end

	#if (js && html5)
	function playWebAudio():Void
	{
		if (audioCtx == null)
			audioCtx = new AudioContext();
		nextTime = audioCtx.currentTime + 0.08;
		playing = true;
		pumpWebAudio();
	}

	function pumpWebAudio():Void
	{
		if (audioCtx == null)
			return;

		// 清掉已经播完的节点引用，避免数组无限增长
		while (scheduled.length > 0 && scheduled[0].end < audioCtx.currentTime)
			scheduled.shift();

		while (playing && !stream.finished && nextTime < audioCtx.currentTime + 2.0)
		{
			var bytes = stream.renderChunk(CHUNK_SAMPLES);
			if (bytes.length == 0)
				break;

			var buffer = audioCtx.createBuffer(1, CHUNK_SAMPLES, sampleRate);
			var channel = buffer.getChannelData(0);
			for (i in 0...CHUNK_SAMPLES)
			{
				var value = bytes.get(i * 2) | (bytes.get(i * 2 + 1) << 8);
				if (value >= 32768)
					value -= 65536;
				channel[i] = value / 32768.0;
			}

			var node = audioCtx.createBufferSource();
			node.buffer = buffer;
			node.connect(audioCtx.destination);
			node.start(nextTime);
			var chunkEnd = nextTime + CHUNK_SAMPLES / sampleRate;
			scheduled.push({node: node, end: chunkEnd});
			nextTime = chunkEnd;
		}
	}
	#end
}
