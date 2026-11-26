package backend.midi;

typedef MidiSong =
{
	/** SMF format: 0 = 单轨, 1 = 多轨同步, 2 = 独立音序 */
	var format:Int;

	/** 原始轨道数（解析后事件已合并排序） */
	var tracks:Int;

	/** ticks per quarter note；SMPTE 时间码会被归一化成 480 */
	var division:Int;

	/** 按 tick + 事件优先级排好序的事件流 */
	var events:Array<MidiEvent>;

	/** 最后一个事件的 tick，用于估算时长 */
	var durationTicks:Int;
}
