package backend.midi;

/**
 *  MIDI 文件解析后保留的消息类型。
 *  其它 meta / sysex 事件在解析阶段丢弃。
 */
enum MidiMessage
{
	NoteOn(channel:Int, note:Int, velocity:Int);
	NoteOff(channel:Int, note:Int, velocity:Int);
	ProgramChange(channel:Int, program:Int);
	ControlChange(channel:Int, controller:Int, value:Int);
	PitchBend(channel:Int, value:Int);
	Tempo(microsPerBeat:Int);
	TimeSignature(numerator:Int, denominator:Int);
	EndOfTrack;
}
