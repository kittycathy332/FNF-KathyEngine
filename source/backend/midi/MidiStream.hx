package backend.midi;

import haxe.io.Bytes;
#if cpp
import sys.thread.Deque;
import sys.thread.Semaphore;
import sys.thread.Thread;
#end

/**
 *  流式（实时）MIDI 合成核心。
 *
 *  与 MidiSynth.render() 的区别：这里不一次性生成整首曲子，而是每次只产出
 *  一小段 PCM，由调用方喂给音频后端。播放端可以边播边算，启动延迟低，
 *  内存占用恒定，也不再需要几十 MB 的完整 WAV。
 *
 *  音色/包络与 MidiSynth 完全一致（共用 MidiSynth 的 voice 计算）。
 */
class MidiStream
{
	public static inline var SCOPE_SIZE:Int = 512;

	/** 已经产出的采样点数量 */
	public var position:Int = 0;

	/** 当前活跃声部数（UI 状态显示用） */
	public var activeVoices(get, never):Int;

	/** 最近 SCOPE_SIZE 个采样点的环形缓冲， oldest -> newest */
	public var scopeLength:Int = 0;

	var scope:Array<Float>;
	var scopeCursor:Int = 0;

	/** 全部事件结束（含尾音衰减）后的采样点数量 */
	public var durationSamples:Int = 0;

	public var finished:Bool = false;
	public var sampleRate:Int;

	/** 根据实测渲染耗时动态调整；关闭后保留全部声部（可能卡顿） */
	public var adaptiveVoices:Bool = true;

	/** 当前声部上限；无上限模式下为 MAX_VOICES */
	public var voiceLimit:Int = MidiSynth.MAX_VOICES;

	var scheduled:Array<MidiScheduledEvent>;
	var eventIndex:Int = 0;
	var lastEventSample:Int = 0;

	var voices:Array<MidiVoice> = [];
	var programs:Array<Int> = [];
	var volumes:Array<Float> = [];
	var bends:Array<Float> = [];
	var noiseSeed:Int = 0x1F123BB5;

	#if cpp
	/** 实际创建的 worker 数，按设备核心数决定（上限 16，读不到则 4） */
	public var workerCount:Int = 4;
	var jobs:Deque<MidiRenderJob>;
	var workers:Array<Thread>;
	var doneSem:Semaphore;

	/** 声部少于这个数时走顺序路径，避免线程派发开销让普通 MIDI 变卡顿 */
	public var parallelMinVoices:Int = 64;
	#end

	public function new(song:MidiSong, ?sampleRate:Int = 22050)
	{
		if (song == null || song.events == null)
			throw "MIDI: 没有可播放的事件";

		this.sampleRate = sampleRate < 8000 ? 8000 : sampleRate;
		MidiSynth.ensureSineTable();

		scope = new Array<Float>();
		for (i in 0...SCOPE_SIZE)
			scope.push(0.0);

		var tempo = 500000;
		var lastTick = 0;
		var timeSec = 0.0;
		scheduled = [];

		for (e in song.events)
		{
			if (e.tick > lastTick)
			{
				timeSec += (e.tick - lastTick) * (tempo / 1000000.0) / song.division;
				lastTick = e.tick;
			}
			var sample = Std.int(timeSec * this.sampleRate);
			scheduled.push({sample: sample, message: e.message});
			if (sample > lastEventSample)
				lastEventSample = sample;

			switch (e.message)
			{
				case Tempo(t):
					tempo = t > 0 ? t : 500000;
				default:
			}
		}

		durationSamples = lastEventSample + MidiSynth.RELEASE_SAMPLES;

		for (i in 0...16)
		{
			programs.push(0);
			volumes.push(1.0);
			bends.push(1.0);
		}

		#if cpp
		jobs = new Deque<MidiRenderJob>();
		doneSem = new Semaphore(0);
		workers = [];
		workerCount = detectCoreCount();
		for (i in 0...workerCount)
			workers.push(Thread.create(workerLoop));
		#end
	}

	#if cpp
	static function detectCoreCount():Int
	{
		var count = -1;

		#if windows
		var env = Sys.getEnv("NUMBER_OF_PROCESSORS");
		if (env != null && env.length > 0)
			count = Std.parseInt(env);
		#else
		try
		{
			var info = sys.io.File.getContent("/proc/cpuinfo");
			count = 0;
			for (line in info.split("\n"))
				if (line.indexOf("processor") == 0)
					count++;
		}
		catch (e:Dynamic)
		{
			count = -1;
		}
		if (count <= 0)
		{
			var env = Sys.getEnv("NPROCESSORS_ONLN");
			if (env != null && env.length > 0)
				count = Std.parseInt(env);
		}
		#end

		if (count <= 0)
			return 4;
		// 防止在 128 核机器上开过多线程反而拖慢
		return Std.int(Math.max(1, Math.min(16, count)));
	}

	function workerLoop():Void
	{
		while (true)
		{
			var job = jobs.pop(true);
			if (job == null) // dispose() 发的哨兵
				break;
			renderRange(job);
			doneSem.release();
		}
	}

	function renderRange(job:MidiRenderJob):Void
	{
		renderRangeInto(job.start, job.end, job.out, job.base);
	}
	#end

	function renderRangeInto(from:Int, to:Int, buffer:Array<Float>, base:Int):Void
	{
		var list = voices;
		for (sample in from...to)
		{
			var sum = 0.0;
			for (v in list)
			{
				if (!v.active)
					continue;
				sum += MidiSynth.voiceSample(v, sample, sampleRate, noiseSeed);
			}
			buffer[sample - base] = sum;
		}
	}

	#if cpp
	public function dispose():Void
	{
		if (workers == null)
			return;
		for (i in 0...workers.length)
			jobs.add(null);
		workers = null;
	}
	#end

	inline function get_activeVoices():Int
	{
		return voices.length;
	}

	/** 跳转到指定采样点（用于进度条拖动/时间调整）。 */
	public function seek(sample:Int):Void
	{
		if (sample < 0)
			sample = 0;
		if (durationSamples > 0 && sample > durationSamples)
			sample = durationSamples;

		position = sample;
		voices = [];

		for (i in 0...16)
		{
			programs[i] = 0;
			volumes[i] = 1.0;
			bends[i] = 1.0;
		}

		// 重建跳转点之前的非音符状态（program / volume / bend）；
		// 跨越跳转点的音符不恢复，下一条 NoteOn 才重新发声。
		eventIndex = 0;
		// 用 < 而不是 <=：正好落在跳转点的事件要留给第一次 renderChunk 处理
		while (eventIndex < scheduled.length && scheduled[eventIndex].sample < sample)
		{
			switch (scheduled[eventIndex].message)
			{
				case ProgramChange(channel, program):
					programs[channel] = program;
				case ControlChange(channel, controller, value):
					if (controller == 7 || controller == 11)
						volumes[channel] = value / 127.0;
				case PitchBend(channel, value):
					bends[channel] = Math.pow(2, (value / 8192.0) * 2.0 / 12.0);
				default:
			}
			eventIndex++;
		}

		for (i in 0...SCOPE_SIZE)
			scope[i] = 0.0;
		scopeCursor = 0;
		scopeLength = 0;
		noiseSeed = 0x1F123BB5;
		finished = sample >= durationSamples && eventIndex >= scheduled.length;
	}

	/** i=0 最旧，i=scopeLength-1 最新 */
	public inline function getScope(i:Int):Float
	{
		if (scope == null || i < 0 || i >= scopeLength)
			return 0;
		var index = scopeCursor - scopeLength + i;
		while (index < 0)
			index += SCOPE_SIZE;
		return scope[index % SCOPE_SIZE];
	}

	/**
	 * 产出下一批 PCM（16bit 单声道 little-endian，无 WAV 头）。
	 * @param sampleCount 想要产出的采样点数；实际返回值长度 = sampleCount * 2
	 */
	public function renderChunk(sampleCount:Int):Bytes
	{
		if (finished || sampleCount <= 0)
			return Bytes.alloc(0);

		var out = Bytes.alloc(sampleCount * 2);
		var start = position;
		var end = start + sampleCount;
		var renderStart = haxe.Timer.stamp();

		// 先把本块所有事件按真实采样点应用；纯函数式 voiceSample 会正确处理未来 start/release
		while (eventIndex < scheduled.length && scheduled[eventIndex].sample < end)
		{
			var ev = scheduled[eventIndex];
			MidiSynth.applyMessage(ev.message, ev.sample, voices, programs, volumes, bends);
			eventIndex++;
		}
		if (voices.length > voiceLimit)
			voices.splice(0, voices.length - voiceLimit);

		var mix = new Array<Float>();
		for (i in 0...sampleCount)
			mix.push(0.0);

		#if cpp
		if (workers != null && voices.length >= parallelMinVoices)
		{
			var perChunk = Std.int(Math.ceil(sampleCount / workerCount));
			var from = start;
			var expected = 0;
			while (from < end && expected < workerCount)
			{
				var to = Std.int(Math.min(end, from + perChunk));
				jobs.add(new MidiRenderJob(from, to, start, mix));
				from = to;
				expected++;
			}
			// Semaphore 阻塞等待，避免轮询 sleep 带来的抖动
			for (i in 0...expected)
				doneSem.acquire();
		}
		else
			renderRangeInto(start, end, mix, start);
		#else
		renderRangeInto(start, end, mix, start);
		#end

		// 尾音结束的声部统一回收，每个 chunk 只压缩一次数组
		for (v in voices)
			if (v.releaseStart >= 0 && end - v.releaseStart >= MidiSynth.RELEASE_SAMPLES)
				v.active = false;
		var write = 0;
		for (v in voices)
		{
			if (!v.active)
				continue;
			voices[write] = v;
			write++;
		}
		if (write < voices.length)
			voices.splice(write, voices.length - write);

		var gain = 0.32 / (1 + voices.length * 0.02);
		for (i in 0...sampleCount)
		{
			var limited = mix[i] * gain;
			if (limited > 1.0)
				limited = 1.0;
			else if (limited < -1.0)
				limited = -1.0;

			scope[scopeCursor] = limited;
			scopeCursor = (scopeCursor + 1) % SCOPE_SIZE;
			if (scopeLength < SCOPE_SIZE)
				scopeLength++;

			var pcm = Std.int(limited * 32767);
			if (pcm < 0)
				pcm += 65536;
			var offset = i * 2;
			out.set(offset, pcm & 0xFF);
			out.set(offset + 1, (pcm >> 8) & 0xFF);
		}

		if (adaptiveVoices)
		{
			var budget = sampleCount / sampleRate;
			var cost = haxe.Timer.stamp() - renderStart;
			if (cost > budget * 0.8)
				voiceLimit = Std.int(Math.max(96, voiceLimit * 0.75));
			else if (cost < budget * 0.4)
				voiceLimit = Std.int(Math.min(MidiSynth.MAX_VOICES, voiceLimit * 1.25 + 16));
		}

		position = end;
		if (eventIndex >= scheduled.length && voices.length == 0 && position >= durationSamples)
			finished = true;

		return out;
	}
}

class MidiRenderJob
{
	public var start:Int;
	public var end:Int;
	public var base:Int;
	public var out:Array<Float>;

	public function new(start:Int, end:Int, base:Int, out:Array<Float>)
	{
		this.start = start;
		this.end = end;
		this.base = base;
		this.out = out;
	}
}
