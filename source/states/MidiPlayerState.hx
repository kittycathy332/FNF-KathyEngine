package states;

import backend.MusicBeatState;
import backend.Paths;
import backend.midi.MidiFilePicker;
import backend.midi.MidiStream;
import backend.midi.MidiStreamPlayer;
import flixel.FlxSprite;
import flixel.text.FlxText;
import flixel.math.FlxMath;
import flixel.util.FlxColor;
import mobile.backend.TouchUtil;
import openfl.display.BitmapData;

/**
 *  独立的 MIDI 播放器界面（非 SubState）。
 *  聚焦播放：文件选择、播放状态、进度、实时波形。
 */
class MidiPlayerState extends MusicBeatState
{
	static inline var WAVE_W:Int = 600;
	static inline var WAVE_H:Int = 140;
	static inline var BAR_W:Int = 600;

	var player:MidiStreamPlayer = null;
	var status:String = "Ready - no file loaded";
	var lastFinished:Bool = false;
	var unlimitedVoices:Bool = false;

	var titleText:FlxText;
	var statusText:FlxText;
	var fileText:FlxText;
	var timeText:FlxText;
	var infoText:FlxText;
	var hintText:FlxText;

	var progressBg:FlxSprite;
	var progressFill:FlxSprite;
	var progressHead:FlxSprite;
	var displayProgress:Float = 0;
	var uiTick:Int = 0;

	var waveSprite:FlxSprite;
	var waveBitmap:BitmapData;
	var waveTick:Int = 0;

	var openBtnBg:FlxSprite;
	var openBtnText:FlxText;
	var stopBtnBg:FlxSprite;
	var stopBtnText:FlxText;
	var backBtnBg:FlxSprite;
	var backBtnText:FlxText;
	var voiceModeBtnBg:FlxSprite;
	var voiceModeBtnText:FlxText;

	override function create():Void
	{
		super.create();

		// 主菜单音乐会跨 State 持续播放，进播放器后只停止，不销毁
		// destroy 会让 FlxG.sound 全局系统失效，返回主菜单后其它音效也播不出来
		if (FlxG.sound.music != null)
			FlxG.sound.music.stop();

		var bg = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, 0xFF101018);
		bg.scrollFactor.set();
		add(bg);

		titleText = new FlxText(0, 28, 0, "MIDI PLAYER", 32);
		titleText.setFormat(Paths.font('vcr.ttf'), 32, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		titleText.screenCenter(X);
		titleText.scrollFactor.set();
		add(titleText);

		statusText = new FlxText(0, 78, 0, "", 18);
		statusText.setFormat(Paths.font('vcr.ttf'), 18, 0xFF57F287, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		statusText.screenCenter(X);
		statusText.scrollFactor.set();
		add(statusText);

		fileText = new FlxText(0, 106, 0, "", 16);
		fileText.setFormat(Paths.font('vcr.ttf'), 16, 0xFFBBBBBB, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		fileText.screenCenter(X);
		fileText.scrollFactor.set();
		add(fileText);

		progressBg = new FlxSprite(0, 142).makeGraphic(BAR_W, 18, 0xFF222233);
		progressBg.scrollFactor.set();
		progressBg.screenCenter(X);
		add(progressBg);

		progressFill = new FlxSprite(progressBg.x, progressBg.y).makeGraphic(BAR_W, 18, 0xFF57F287);
		progressFill.origin.x = 0;
		progressFill.scale.x = 0;
		progressFill.scrollFactor.set();
		add(progressFill);

		progressHead = new FlxSprite(progressBg.x, progressBg.y).makeGraphic(6, 18, 0xFFFFFFFF);
		progressHead.scrollFactor.set();
		add(progressHead);

		timeText = new FlxText(0, 168, 0, "", 16);
		timeText.setFormat(Paths.font('vcr.ttf'), 16, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		timeText.screenCenter(X);
		timeText.scrollFactor.set();
		add(timeText);

		waveBitmap = new BitmapData(WAVE_W, WAVE_H, true, 0x00000000);
		waveSprite = new FlxSprite(0, 204);
		waveSprite.pixels = waveBitmap;
		waveSprite.screenCenter(X);
		waveSprite.scrollFactor.set();
		add(waveSprite);

		infoText = new FlxText(0, 358, 0, "", 14);
		infoText.setFormat(Paths.font('vcr.ttf'), 14, 0xFF888888, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		infoText.screenCenter(X);
		infoText.scrollFactor.set();
		add(infoText);

		var buttonY:Float = 410;
		openBtnBg = makeButton(FlxG.width * 0.5 - 260, buttonY, 160, "OPEN MIDI");
		stopBtnBg = makeButton(FlxG.width * 0.5 - 80, buttonY, 160, "STOP");
		backBtnBg = makeButton(FlxG.width * 0.5 + 100, buttonY, 160, "BACK");
		openBtnText = makeButtonLabel(openBtnBg, "OPEN MIDI");
		stopBtnText = makeButtonLabel(stopBtnBg, "STOP");
		backBtnText = makeButtonLabel(backBtnBg, "BACK");

		voiceModeBtnBg = makeButton(FlxG.width * 0.5 - 110, 375, 220, "VOICES: AUTO");
		voiceModeBtnText = makeButtonLabel(voiceModeBtnBg, "VOICES: AUTO");

		hintText = new FlxText(0, FlxG.height - 48, 0, "Enter: Open   Space: Stop   Esc: Back   Left-Right: Seek   V: Voice mode", 14);
		hintText.setFormat(Paths.font('vcr.ttf'), 14, 0xFF666666, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		hintText.screenCenter(X);
		hintText.scrollFactor.set();
		add(hintText);

		updateTextUI();
		drawWave();
	}

	function makeButton(x:Float, y:Float, width:Int, label:String):FlxSprite
	{
		var bg = new FlxSprite(x, y).makeGraphic(width, 42, 0xFF333344);
		bg.scrollFactor.set();
		add(bg);
		return bg;
	}

	function makeButtonLabel(bg:FlxSprite, label:String):FlxText
	{
		var text = new FlxText(bg.x, bg.y + 11, Std.int(bg.width), label, 16);
		text.setFormat(Paths.font('vcr.ttf'), 16, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		text.scrollFactor.set();
		add(text);
		return text;
	}

	override function update(elapsed:Float):Void
	{
		super.update(elapsed);

		// 进度条每帧插值，文本 10Hz 左右刷新即可，避免无谓的排版开销
		updateProgressVisual(elapsed);
		if (++uiTick % 6 == 0)
			updateTextUI();

		if (player != null)
		{
			player.update();
			if (player.finished && !lastFinished)
			{
				status = "Finished";
				lastFinished = true;
			}
			if (++waveTick % 2 == 0)
				drawWave();
		}

		if (player != null)
		{
			#if desktop
			if (FlxG.mouse.justPressed && FlxG.mouse.overlaps(progressBg, FlxG.camera))
				seekFromPointer(FlxG.mouse.x);
			if (controls.UI_LEFT_P)
				seekBy(-5);
			if (controls.UI_RIGHT_P)
				seekBy(5);
			#else
			if (TouchUtil.justPressed && TouchUtil.overlaps(progressBg, FlxG.camera))
				seekFromPointer(TouchUtil.touch.x);
			#end
		}

		if (controls.BACK)
		{
			goBack();
			return;
		}

		if (controls.ACCEPT || buttonHit(openBtnBg))
		{
			openFile();
			return;
		}

		#if desktop
		if (FlxG.keys.justPressed.SPACE || buttonHit(stopBtnBg))
		#else
		if (buttonHit(stopBtnBg))
		#end
		{
			stopPlayback();
		}

		#if desktop
		if (FlxG.keys.justPressed.V || buttonHit(voiceModeBtnBg))
		#else
		if (buttonHit(voiceModeBtnBg))
		#end
		{
			toggleVoiceMode();
		}

		if (buttonHit(backBtnBg))
			goBack();
	}

	function toggleVoiceMode():Void
	{
		unlimitedVoices = !unlimitedVoices;
		if (player != null)
			player.unlimitedVoices = unlimitedVoices;
		voiceModeBtnText.text = unlimitedVoices ? "VOICES: UNLIMITED" : "VOICES: AUTO";
		updateTextUI();
	}

	function buttonHit(bg:FlxSprite):Bool
	{
		if (bg == null)
			return false;
		#if desktop
		return FlxG.mouse.justPressed && FlxG.mouse.overlaps(bg, FlxG.camera);
		#else
		return TouchUtil.justPressed && TouchUtil.overlaps(bg, FlxG.camera);
		#end
	}

	function seekFromPointer(x:Float):Void
	{
		if (player == null)
			return;
		var ratio = (x - progressBg.x) / BAR_W;
		ratio = FlxMath.bound(ratio, 0, 1);
		try
		{
			player.seek(ratio * player.duration);
			displayProgress = player.progress;
			lastFinished = false;
			status = "Playing";
		}
		catch (e:Dynamic)
		{
			status = "Seek failed";
			trace('MIDI seek failed: $e');
		}
		updateTextUI();
		drawWave();
	}

	function seekBy(seconds:Float):Void
	{
		if (player == null)
			return;
		try
		{
			player.seek(player.position + seconds);
			displayProgress = player.progress;
			lastFinished = false;
			status = "Playing";
		}
		catch (e:Dynamic)
		{
			status = "Seek failed";
			trace('MIDI seek failed: $e');
		}
		updateTextUI();
		drawWave();
	}

	function openFile():Void
	{
		if (player != null)
		{
			player.stop();
			player = null;
		}
		status = "Choosing file...";
		lastFinished = false;
		updateTextUI();

		MidiFilePicker.pick(
			function(bytes:haxe.io.Bytes, name:String)
			{
				try
				{
					player = MidiStreamPlayer.fromBytes(bytes, 22050, name);
					player.unlimitedVoices = unlimitedVoices;
					player.play();
					displayProgress = 0;
					status = "Playing";
					lastFinished = false;
				}
				catch (e:Dynamic)
				{
					var msg = Std.string(e);
					if (msg.length > 64)
						msg = msg.substr(0, 64);
					status = "Load failed: " + msg;
					trace('MIDI load failed: $e');
				}
				updateTextUI();
			},
			function()
			{
				status = "Cancelled";
				updateTextUI();
			},
			function()
			{
				status = "Read failed";
				updateTextUI();
			}
		);
	}

	function stopPlayback():Void
	{
		if (player == null)
			return;
		player.stop();
		player = null;
		status = "Stopped";
		updateTextUI();
		drawWave();
	}

	function goBack():Void
	{
		if (player != null)
		{
			player.stop();
			player = null;
		}
		// 恢复进播放器前停掉的主菜单音乐
		if (FlxG.sound.music != null && !FlxG.sound.music.playing)
			FlxG.sound.music.play();
		FlxG.switchState(new MainMenuState());
	}

	function updateTextUI():Void
	{
		statusText.text = 'Status: $status';
		statusText.screenCenter(X);
		fileText.text = player != null ? 'File: ' + player.fileName : 'File: -';
		fileText.screenCenter(X);

		if (player != null)
		{
			var percent = Std.int(player.progress * 100);
			timeText.text = '${formatTime(player.position)} / ${formatTime(player.duration)}  ($percent%)';
			var limitLabel = unlimitedVoices ? 'UNLIMITED' : Std.string(player.voiceLimit);
			infoText.text = 'Rate: ${player.sampleRate} Hz   Voices: ${player.activeVoices}/$limitLabel   Workers: ${player.workerCount}   Scope: ${MidiStream.SCOPE_SIZE}';
		}
		else
		{
			timeText.text = '00:00 / 00:00  (0%)';
			infoText.text = 'Rate: 22050 Hz   Voices: 0';
		}
		timeText.screenCenter(X);
		infoText.screenCenter(X);
	}

	function updateProgressVisual(elapsed:Float):Void
	{
		var target = player != null ? player.progress : 0;
		if (target < 0) target = 0;
		if (target > 1) target = 1;

		// 指数平滑，帧率无关
		var k = 1 - Math.exp(-elapsed * 14);
		displayProgress += (target - displayProgress) * k;
		if (Math.abs(target - displayProgress) < 0.0005)
			displayProgress = target;

		progressFill.scale.x = displayProgress;
		progressHead.x = progressBg.x + displayProgress * BAR_W - 3;
	}

	function drawWave():Void
	{
		if (waveBitmap == null)
			return;

		waveBitmap.fillRect(waveBitmap.rect, 0x00000000);
		var mid:Int = Std.int(WAVE_H * 0.5);
		for (x in 0...WAVE_W)
			waveBitmap.setPixel32(x, mid, 0xFF333344);

		if (player == null)
		{
			waveSprite.dirty = true;
			return;
		}

		var stream = player.stream;
		var n = stream.scopeLength;
		if (n <= 0)
		{
			waveSprite.dirty = true;
			return;
		}

		// 按像素列反向取样，保证每个 x 都有数据，避免 512→600 映射跳列形成梳齿
		for (x in 0...WAVE_W)
		{
			var index = Std.int(x * n / WAVE_W);
			if (index >= n)
				index = n - 1;
			var value = stream.getScope(index);
			var y = Std.int(mid - value * mid * 0.9);
			y = Std.int(FlxMath.bound(y, 0, WAVE_H - 1));
			var from = Std.int(Math.min(y, mid));
			var to = Std.int(Math.max(y, mid));
			for (yy in from...to + 1)
				waveBitmap.setPixel32(x, yy, 0xFF57F287);
		}
		waveSprite.dirty = true;
	}

	static function formatTime(seconds:Float):String
	{
		var total = Std.int(Math.max(0, seconds));
		var mins = Std.int(total / 60);
		var secs = total % 60;
		return mins + ':' + (secs < 10 ? '0' : '') + secs;
	}

	override function destroy():Void
	{
		if (player != null)
		{
			player.dispose();
			player = null;
		}
		super.destroy();
	}
}
