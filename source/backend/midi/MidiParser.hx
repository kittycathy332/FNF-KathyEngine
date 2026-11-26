package backend.midi;

import haxe.io.Bytes;

/**
 *  轻量 Standard MIDI File (SMF) 解析器。
 *  纯 Haxe，无 native 依赖，可在 cpp / js(html5) / neko / hl 上跑。
 */
class MidiParser
{
	public static function parse(bytes:Bytes):MidiSong
	{
		if (bytes == null || bytes.length < 14)
			throw "MIDI: 文件太短或为空";

		var r = new MidiByteReader(bytes);
		if (r.readString(4) != "MThd")
			throw "MIDI: 缺少 MThd 文件头（不是标准 MIDI 文件）";

		var headerLength = r.readUInt32();
		var format = r.readUInt16();
		var trackCount = r.readUInt16();
		var division = r.readUInt16();

		if (headerLength > 6)
			r.skip(headerLength - 6);

		// SMPTE 时间码（division 最高位为 1）统一归一化成 480 ticks/quarter。
		// 真正的 SMPTE 歌曲很少，播放器场景下不需要精确还原帧率。
		var ticksPerQuarter = (division & 0x8000) != 0 ? 480 : division;
		if (ticksPerQuarter <= 0)
			ticksPerQuarter = 480;

		var events:Array<MidiEvent> = [];
		for (i in 0...trackCount)
			parseTrack(r, events);

		// 同一 tick 上的事件顺序会影响听感：
		// tempo/timeSig 先生效，noteOff 早于 noteOn（避免同音重触发被立刻掐掉）。
		events.sort(function(a, b)
		{
			if (a.tick != b.tick)
				return a.tick - b.tick;
			return priority(a.message) - priority(b.message);
		});

		var maxTick = 0;
		for (e in events)
			if (e.tick > maxTick)
				maxTick = e.tick;

		return {
			format: format,
			tracks: trackCount,
			division: ticksPerQuarter,
			events: events,
			durationTicks: maxTick
		};
	}

	static function priority(msg:MidiMessage):Int
	{
		return switch (msg)
		{
			case Tempo(_) | TimeSignature(_, _): -2;
			case ProgramChange(_, _) | ControlChange(_, _, _) | PitchBend(_, _): -1;
			case NoteOff(_, _, _): 0;
			case NoteOn(_, _, _): 1;
			case EndOfTrack: 2;
		};
	}

	static function parseTrack(r:MidiByteReader, out:Array<MidiEvent>):Void
	{
		if (r.remaining() < 8)
			throw "MIDI: MTrk 轨道头不完整";

		var id = r.readString(4);
		if (id != "MTrk")
			throw 'MIDI: 期望 MTrk，实际拿到 "$id"';

		var length = r.readUInt32();
		var end = r.position + length;
		if (end > r.bytes.length)
			throw "MIDI: MTrk 声明长度超出文件范围";

		var tick = 0;
		var runningStatus = -1;

		while (r.position < end)
		{
			var delta = r.readVLQ();
			tick += delta;

			var first = r.bytes.get(r.position);
			var status:Int;
			if ((first & 0x80) != 0)
			{
				status = r.readByte();
				if (status < 0xF0)
					runningStatus = status;
			}
			else
			{
				// running status：沿用上一条 channel voice message
				if (runningStatus < 0)
					throw "MIDI: 遇到 running status 但没有前置状态字节";
				status = runningStatus;
			}

			var type = status & 0xF0;
			var channel = status & 0x0F;

			switch (type)
			{
				case 0x80: // note off
					var note = r.readByte();
					var velocity = r.readByte();
					out.push({tick: tick, message: NoteOff(channel, note, velocity)});

				case 0x90: // note on；velocity 0 等价于 note off
					var note = r.readByte();
					var velocity = r.readByte();
					out.push({
						tick: tick,
						message: velocity == 0 ? NoteOff(channel, note, 0) : NoteOn(channel, note, velocity)
					});

				case 0xA0: // poly aftertouch，播放器忽略
					r.readByte();
					r.readByte();

				case 0xB0: // control change
					var controller = r.readByte();
					var value = r.readByte();
					out.push({tick: tick, message: ControlChange(channel, controller, value)});

				case 0xC0: // program change
					out.push({tick: tick, message: ProgramChange(channel, r.readByte())});

				case 0xD0: // channel aftertouch，播放器忽略
					r.readByte();

				case 0xE0: // pitch bend
					var lo = r.readByte();
					var hi = r.readByte();
					out.push({tick: tick, message: PitchBend(channel, (hi << 7 | lo) - 8192)});

				case 0xF0:
					if (status == 0xFF)
					{
						var metaType = r.readByte();
						var len = r.readVLQ();
						var data = r.readBytes(len);
						switch (metaType)
						{
							case 0x51: // tempo: microseconds per quarter note
								if (len >= 3)
									out.push({
										tick: tick,
										message: Tempo((data.get(0) << 16) | (data.get(1) << 8) | data.get(2))
									});
							case 0x58:
								if (len >= 2)
									out.push({tick: tick, message: TimeSignature(data.get(0), data.get(1))});
							case 0x2F:
								out.push({tick: tick, message: EndOfTrack});
							default:
								// 其它 meta（文字、歌词、标记等）播放器用不到
						}
					}
					else
					{
						// sysex / escaped event：跳过其长度字段和数据
						r.skip(r.readVLQ());
					}

				default:
					// 非法状态，跳过一个数据字节防止死循环
					r.readByte();
			}
		}

		if (r.position != end)
			r.seek(end);
	}
}

/** SMF 使用 big-endian，这里不依赖 Bytes.getInt32 的端序行为。 */
class MidiByteReader
{
	public var bytes:Bytes;
	public var position:Int = 0;

	public function new(bytes:Bytes)
	{
		this.bytes = bytes;
	}

	public inline function remaining():Int
	{
		return bytes.length - position;
	}

	public inline function seek(pos:Int):Void
	{
		position = pos;
	}

	public inline function skip(count:Int):Void
	{
		position += count;
		if (position < 0 || position > bytes.length)
			throw "MIDI: 读取越界";
	}

	public function readByte():Int
	{
		if (position >= bytes.length)
			throw "MIDI: 文件意外结束";
		return bytes.get(position++);
	}

	public function readUInt16():Int
	{
		return (readByte() << 8) | readByte();
	}

	public function readUInt32():Int
	{
		return (readByte() << 24) | (readByte() << 16) | (readByte() << 8) | readByte();
	}

	public function readString(length:Int):String
	{
		var s = "";
		for (i in 0...length)
			s += String.fromCharCode(readByte());
		return s;
	}

	public function readBytes(length:Int):Bytes
	{
		if (length < 0 || position + length > bytes.length)
			throw "MIDI: 数据块长度越界";
		var result = bytes.sub(position, length);
		position += length;
		return result;
	}

	/** SMF variable-length quantity */
	public function readVLQ():Int
	{
		var value = 0;
		var count = 0;
		while (true)
		{
			var b = readByte();
			value = (value << 7) | (b & 0x7F);
			count++;
			if ((b & 0x80) == 0)
				break;
			if (count > 4)
				throw "MIDI: 非法的 variable-length quantity";
		}
		return value;
	}
}
