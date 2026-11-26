package backend.midi;

import haxe.io.Bytes;
import lime.media.AudioBuffer;
import openfl.media.Sound;
import openfl.media.SoundChannel;
import openfl.media.SoundTransform;
import openfl.utils.Assets;

/**
 *  全平台 MIDI 播放器（纯 Haxe）。
 *
 *  用法：
 *    var player = new MidiPlayer(Assets.getBytes("assets/music/test.mid"));
 *    var channel = player.play(0, 0); // 第 2 个参数是循环次数
 *
 *  注意：渲染是一次性同步操作。短曲（1~3 分钟 / 22050Hz 单声道）没问题；
 *  很长的 MIDI 会占用几十 MB 内存并在渲染瞬间卡帧。
 */
class MidiPlayer
{
	public var song:MidiSong;
	public var sound:Sound;
	public var sampleRate:Int;
	public var duration:Float = 0;
	public var wavBytes:Bytes;

	public function new(bytes:Bytes, ?sampleRate:Int = 22050)
	{
		if (bytes == null)
			throw "MIDI: 传入的字节数据为空";

		this.sampleRate = sampleRate < 8000 ? 8000 : sampleRate;
		song = MidiParser.parse(bytes);
		render();
	}

	/** 从 OpenFL 资源路径加载（需先把 .mid 加进 Project.xml 的 assets） */
	public static function fromAsset(path:String, ?sampleRate:Int = 22050):MidiPlayer
	{
		return new MidiPlayer(Assets.getBytes(path), sampleRate);
	}

	public function render():Sound
	{
		wavBytes = MidiSynth.render(song, sampleRate);
		duration = (wavBytes.length - 44) / 2.0 / sampleRate;

		var buffer = AudioBuffer.fromBytes(wavBytes);
		if (buffer == null)
			throw "MIDI: 生成的 WAV 无法被 AudioBuffer 解码";

		sound = Sound.fromAudioBuffer(buffer);
		return sound;
	}

	public function play(?startTime:Float = 0, ?loops:Int = 0, ?volume:Float = 1.0):SoundChannel
	{
		if (sound == null)
			render();
		if (sound == null)
			throw "MIDI: 没有可播放的 Sound";

		var channel = sound.play(startTime, loops);
		if (channel != null && volume != 1.0)
			channel.soundTransform = new SoundTransform(volume);
		return channel;
	}
}
