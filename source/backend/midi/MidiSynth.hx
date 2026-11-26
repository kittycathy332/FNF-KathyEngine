package backend.midi;

import haxe.io.Bytes;
import backend.midi.MidiMessage;

/**
 *  纯 Haxe 简易软合成器。
 *
 *  路线：解析事件 -> 按 tempo map 换算成采样点 -> 逐样本叠加波形 -> 输出 16bit PCM WAV。
 *  没有 SoundFont、没有滤波器，音色是按 GM program 分族的简化波形；
 *  目标是“能播放 MIDI、全平台一致、零 native 依赖”，不是追求采样器音质。
 */
class MidiSynth
{
	static inline var ATTACK_SAMPLES = 220;   // ~10ms @22050
	static inline var DECAY_SAMPLES = 1764;   // ~80ms
	public static inline var RELEASE_SAMPLES = 2205; // ~100ms（流式播放判断尾音用）
	public static inline var MAX_VOICES = 0x7FFFFFFF; // 默认不设上限；自适应降载可在 MidiStream 里开启
	static inline var SINE_TABLE_SIZE = 2048;

	static var sineTable:Array<Float>;
	static var waveTables:Array<Array<Float>>;

	public static function ensureSineTable():Void
	{
		if (sineTable != null)
			return;

		sineTable = new Array<Float>();
		for (i in 0...SINE_TABLE_SIZE)
			sineTable.push(Math.sin(i * 2 * Math.PI / SINE_TABLE_SIZE));

		// 16 个 GM 音色族 × 一个周期波形，运行时只做查表 + 线性插值
		waveTables = new Array<Array<Float>>();
		for (family in 0...16)
		{
			var table = new Array<Float>();
			for (i in 0...SINE_TABLE_SIZE)
				table.push(rawInstrumentWave(family, i / SINE_TABLE_SIZE));
			waveTables.push(table);
		}
	}

	/** 默认 22050Hz 单声道：3 分钟 MIDI 的 PCM 约 8MB，HTML5 也能承受。 */
	public static function render(song:MidiSong, sampleRate:Int = 22050):Bytes
	{
		if (song == null || song.events == null)
			throw "MIDI: 没有可渲染的事件";
		if (sampleRate < 8000)
			sampleRate = 8000;

		ensureSineTable();

		// ---- 事件时间 -> 采样点 ----
		var tempo = 500000; // 默认 120 BPM
		var lastTick = 0;
		var timeSec = 0.0;
		var scheduled:Array<MidiScheduledEvent> = [];

		for (e in song.events)
		{
			if (e.tick > lastTick)
			{
				timeSec += (e.tick - lastTick) * (tempo / 1000000.0) / song.division;
				lastTick = e.tick;
			}
			scheduled.push({
				sample: Std.int(timeSec * sampleRate),
				message: e.message
			});
			switch (e.message)
			{
				case Tempo(t):
					tempo = t > 0 ? t : 500000;
				default:
			}
		}

		// 末尾多留 1.2 秒让 release 衰减完，再算上 tempo map 剩余部分。
		var totalSeconds = timeSec + 1.2;
		if (song.durationTicks > lastTick)
			totalSeconds += (song.durationTicks - lastTick) * (tempo / 1000000.0) / song.division;
		var totalSamples = Std.int(Math.ceil(totalSeconds * sampleRate));
		if (totalSamples < 1)
			totalSamples = 1;

		var pcmLength = totalSamples * 2;
		var out = Bytes.alloc(44 + pcmLength);
		writeWavHeader(out, sampleRate, pcmLength);

		var voices:Array<MidiVoice> = [];
		var programs = new Array<Int>();
		var volumes = new Array<Float>();
		var bends = new Array<Float>();
		for (i in 0...16)
		{
			programs.push(0);
			volumes.push(1.0);
			bends.push(1.0);
		}

		var eventIndex = 0;
		var noiseSeed = 0x1F123BB5;
		var masterVolume = 1.0;

		for (sample in 0...totalSamples)
		{
			while (eventIndex < scheduled.length && scheduled[eventIndex].sample <= sample)
			{
				applyMessage(scheduled[eventIndex].message, sample, voices, programs, volumes, bends);
				eventIndex++;
			}
			if (voices.length > MAX_VOICES)
				voices.splice(0, voices.length - MAX_VOICES);

			var mixed = 0.0;
			for (v in voices)
			{
				if (!v.active)
					continue;

				var value = voiceSample(v, sample, sampleRate, noiseSeed);
				if (v.releaseStart >= 0 && sample - v.releaseStart >= RELEASE_SAMPLES)
				{
					v.active = false;
					value = 0.0;
				}
				mixed += value;
			}

			// 声部越多，单声部增益越低，避免黑乐谱叠加爆音
			var gain = 0.32 / (1 + voices.length * 0.02);
			var limited = mixed * gain * masterVolume;
			if (limited > 1.0)
				limited = 1.0;
			else if (limited < -1.0)
				limited = -1.0;

			var pcm = Std.int(limited * 32767);
			var offset = 44 + sample * 2;
			if (pcm < 0)
				pcm += 65536;
			out.set(offset, pcm & 0xFF);
			out.set(offset + 1, (pcm >> 8) & 0xFF);
		}

		return out;
	}

	public static function applyMessage(msg:MidiMessage, sample:Int, voices:Array<MidiVoice>, programs:Array<Int>, volumes:Array<Float>, bends:Array<Float>):Void
	{
		switch (msg)
		{
			case NoteOn(channel, note, velocity):
				if (velocity <= 0)
					return;

				// 同通道同音先放掉旧 voice，防止 sustain 叠音
				for (v in voices)
					if (v.active && v.channel == channel && v.note == note && v.releaseStart < 0)
						v.releaseStart = sample;

				var program = channel == 9 ? 0 : programs[channel];
				var freq = 440.0 * Math.pow(2, (note - 69) / 12.0) * bends[channel];
				voices.push({
					active: true,
					channel: channel,
					note: note,
					program: program,
					freq: freq,
					baseFreq: freq,
					// MIDI velocity 听感近似指数，1.6 次幂让弱音真正更轻
					velocity: Math.pow(velocity / 127.0, 1.6),
					volume: volumes[channel],
					start: sample,
					releaseStart: -1,
					phase: 0.0,
					drum: channel == 9
				});

			case NoteOff(channel, note, _):
				for (v in voices)
					if (v.active && v.channel == channel && v.note == note && v.releaseStart < 0)
						v.releaseStart = sample;

			case ProgramChange(channel, program):
				programs[channel] = program;

			case ControlChange(channel, controller, value):
				if (controller == 7 || controller == 11)
					volumes[channel] = value / 127.0;

			case PitchBend(channel, value):
				// ±2 半音
				bends[channel] = Math.pow(2, (value / 8192.0) * 2.0 / 12.0);
				for (v in voices)
					if (v.active && v.channel == channel)
						v.freq = v.baseFreq * bends[channel];

			case Tempo(_) | TimeSignature(_, _) | EndOfTrack:
				// 时间信息已在预处理阶段处理
		}
	}

	/**
	 * 纯函数式采样：不修改 voice 状态，可由多个 worker 并行调用。
	 * 事件可以提前应用，start/releaseStart 在未来的音符会自动静音或保持正常包络。
	 */
	public static function voiceSample(v:MidiVoice, sample:Int, sampleRate:Int, noiseSeed:Int):Float
	{
		var age = sample - v.start;
		if (age < 0)
			return 0;

		var envelope:Float;
		if (v.releaseStart < 0 || sample < v.releaseStart)
		{
			if (age < ATTACK_SAMPLES)
				envelope = age / ATTACK_SAMPLES;
			else if (age < ATTACK_SAMPLES + DECAY_SAMPLES)
				envelope = 1.0 - 0.4 * ((age - ATTACK_SAMPLES) / DECAY_SAMPLES);
			else
				envelope = 0.6;
		}
		else
		{
			var releaseAge = sample - v.releaseStart;
			envelope = 0.6 * (1.0 - releaseAge / RELEASE_SAMPLES);
			if (envelope < 0)
				envelope = 0;
		}

		if (v.drum)
			return drumSample(v.note, age, sampleRate, noiseSeed) * envelope * v.velocity * v.volume;

		var phase = v.phase + age * v.freq / sampleRate;
		phase -= Math.floor(phase);
		return instrumentWave(v.program, phase) * envelope * v.velocity * v.volume;
	}

	static inline function instrumentWave(program:Int, phase:Float):Float
	{
		var table = waveTables[(program & 0x7F) >> 3];
		var p = phase - Math.floor(phase);
		var pos = p * SINE_TABLE_SIZE;
		var i0 = Std.int(pos) & (SINE_TABLE_SIZE - 1);
		var frac = pos - Math.floor(pos);
		var i1 = (i0 + 1) & (SINE_TABLE_SIZE - 1);
		return table[i0] * (1.0 - frac) + table[i1] * frac;
	}

	static function rawInstrumentWave(family:Int, phase:Float):Float
	{
		var s = sineAt(phase);
		if (family < 1)
			return s + 0.35 * sineAt(phase * 2) + 0.15 * sineAt(phase * 3);
		if (family == 1 || family == 15)
			return 0.6 * s + 0.4 * squareAt(phase);
		if (family < 3)
			return 0.55 * s + 0.3 * sineAt(phase * 2) + 0.15 * sineAt(phase * 4);
		if (family == 3)
			return sawAt(phase);
		if (family == 4)
			return triangleAt(phase) + 0.15 * s;
		if (family < 7)
			return 0.5 * (sawAt(phase) + sawAt(phase + 0.003));
		if (family < 9)
			return squareAt(phase) * 0.7 + s * 0.3;
		if (family < 11)
			return squareAt(phase);
		if (family < 13)
			return triangleAt(phase) + 0.3 * sineAt(phase * 3);
		return s + 0.25 * squareAt(phase);
	}

	static inline function sineAt(phase:Float):Float
	{
		var p = phase - Math.floor(phase);
		var index = Std.int(p * SINE_TABLE_SIZE) & (SINE_TABLE_SIZE - 1);
		return sineTable[index];
	}

	static inline function squareAt(phase:Float):Float
	{
		var p = phase - Math.floor(phase);
		return p < 0.5 ? 1.0 : -1.0;
	}

	static inline function sawAt(phase:Float):Float
	{
		var p = phase - Math.floor(phase);
		return 2.0 * p - 1.0;
	}

	static inline function triangleAt(phase:Float):Float
	{
		var p = phase - Math.floor(phase);
		return 1.0 - 4.0 * Math.abs(p - 0.5);
	}

	static function drumSample(note:Int, age:Int, sampleRate:Int, seed:Int):Float
	{
		var t = age / sampleRate;
		var noise = nextNoise(Std.int(seed + age * 2654435761));

		if (note == 35 || note == 36)
		{
			// Kick: 频率快速下扫的正弦
			var freq = 150.0 * Math.exp(-t * 30.0) + 48.0;
			var env = Math.exp(-t * 12.0);
			return Math.sin(2 * Math.PI * freq * t) * env;
		}
		if (note == 38 || note == 40 || note == 37)
		{
			// Snare: 噪声 + 音调
			return (noise * 0.7 + Math.sin(2 * Math.PI * 180 * t) * 0.3) * Math.exp(-t * 22.0);
		}
		if (note == 42 || note == 44 || note == 46 || note == 49 || note == 51)
		{
			// Hi-hat / cymbal: 高通近似（相邻噪声差分）
			var hp = noise - nextNoise(Std.int(seed + age * 2654435761 + 1));
			return hp * Math.exp(-t * 40.0) * 0.6;
		}
		// Tom / 其它打击乐
		return Math.sin(2 * Math.PI * (220.0 - note) * t) * Math.exp(-t * 18.0);
	}

	static function nextNoise(seed:Int):Float
	{
		// 确定性 xorshift，保证同一 MIDI 每次渲染结果一致
		var x = seed;
		x ^= x << 13;
		x ^= x >>> 17;
		x ^= x << 5;
		return ((x & 0x7FFFFFFF) / 1073741824.0) - 1.0;
	}

	static function writeWavHeader(bytes:Bytes, sampleRate:Int, dataLength:Int):Void
	{
		writeAscii(bytes, 0, "RIFF");
		writeUInt32LE(bytes, 4, 36 + dataLength);
		writeAscii(bytes, 8, "WAVEfmt ");
		writeUInt32LE(bytes, 16, 16);
		writeUInt16LE(bytes, 20, 1); // PCM
		writeUInt16LE(bytes, 22, 1); // mono
		writeUInt32LE(bytes, 24, sampleRate);
		writeUInt32LE(bytes, 28, sampleRate * 2); // byte rate
		writeUInt16LE(bytes, 32, 2); // block align
		writeUInt16LE(bytes, 34, 16); // bits per sample
		writeAscii(bytes, 36, "data");
		writeUInt32LE(bytes, 40, dataLength);
	}

	static inline function writeAscii(bytes:Bytes, offset:Int, text:String):Void
	{
		for (i in 0...text.length)
			bytes.set(offset + i, text.charCodeAt(i) & 0xFF);
	}

	static inline function writeUInt16LE(bytes:Bytes, offset:Int, value:Int):Void
	{
		bytes.set(offset, value & 0xFF);
		bytes.set(offset + 1, (value >> 8) & 0xFF);
	}

	static inline function writeUInt32LE(bytes:Bytes, offset:Int, value:Int):Void
	{
		bytes.set(offset, value & 0xFF);
		bytes.set(offset + 1, (value >>> 8) & 0xFF);
		bytes.set(offset + 2, (value >>> 16) & 0xFF);
		bytes.set(offset + 3, (value >>> 24) & 0xFF);
	}
}
