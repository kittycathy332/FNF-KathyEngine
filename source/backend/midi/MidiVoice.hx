package backend.midi;

typedef MidiVoice =
{
	var active:Bool;
	var channel:Int;
	var note:Int;
	var program:Int;
	var freq:Float;
	var baseFreq:Float;
	var velocity:Float;
	var volume:Float;
	var start:Int;
	var releaseStart:Int;
	var phase:Float;
	var drum:Bool;
}
