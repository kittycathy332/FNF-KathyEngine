package substates;

import backend.WeekData;
import backend.Highscore;
import backend.Song;

import flixel.util.FlxStringUtil;

import states.StoryMenuState;
import states.FreeplayState;
import options.OptionsState;
import StringTools;

class PauseSubState extends MusicBeatSubstate
{
	var grpMenuShit:FlxTypedGroup<Alphabet>;

	var menuItems:Array<String> = [];
	var menuItemsOG:Array<String> = ['Resume', 'Restart Song'#if mobile , 'Chart Editor' #end, 'Change Difficulty', 'Options', 'Exit to menu'];
	var difficultyChoices = [];
	var curSelected:Int = 0;

	var pauseMusic:FlxSound;
	var practiceText:FlxText;
	var skipTimeText:FlxText;
	var skipTimeTracker:Alphabet;
	var curTime:Float = Math.max(0, Conductor.songPosition);

	var missingTextBG:FlxSprite;
	var missingText:FlxText;
	var batteryText:FlxText;
	var batteryRefresh:Float = 0;

	public static var songName:String = null;

	override function create()
	{
		var format1 = new FlxTextFormat(0xFFFFFF, false, false);
		var format2 = new FlxTextFormat(0xFF4000, false, false);

		if(Difficulty.list.length < 2) menuItemsOG.remove('Change Difficulty'); //No need to change difficulty if there is only one!
		#if mobile
		if(!ClientPrefs.data.developer) menuItemsOG.remove('Chart Editor'); // 开发者模式关闭时，移动端暂停界面隐藏制谱器入口
		#end
		if(PlayState.isCommandLineMode)
		{
			// 命令行直启：禁用「选项」「退出主界面」与「难度修改」入口
			menuItemsOG.remove('Options');
			menuItemsOG.remove('Exit to menu');
			menuItemsOG.remove('Change Difficulty');
		}
		if(PlayState.chartingMode)
		{
			menuItemsOG.insert(2, 'Leave Charting Mode');
			var num:Int = 0;
			if(!PlayState.instance.startingSong)
			{
				num = 1;
				menuItemsOG.insert(3, 'Skip Time');
			}
			menuItemsOG.insert(3 + num, 'End Song');
			menuItemsOG.insert(4 + num, 'Toggle Practice Mode');
			menuItemsOG.insert(5 + num, 'Toggle Botplay');
		} else if(PlayState.instance.practiceMode && !PlayState.instance.startingSong)
			menuItemsOG.insert(3, 'Skip Time');
		menuItems = menuItemsOG;

		for (i in 0...Difficulty.list.length) {
			var diff:String = Difficulty.getString(i);
			difficultyChoices.push(diff);
		}
		difficultyChoices.push('BACK');

		pauseMusic = new FlxSound();
		try
		{
			var pauseSong:String = getPauseSong();
			if(pauseSong != null) pauseMusic.loadEmbedded(Paths.music(pauseSong), true, true);
		}
		catch(e:Dynamic) {}
		pauseMusic.volume = 0;
		pauseMusic.play(false, FlxG.random.int(0, Std.int(pauseMusic.length / 2)));

		FlxG.sound.list.add(pauseMusic);

		var bg:FlxSprite = new FlxSprite().makeGraphic(1, 1, FlxColor.BLACK);
		bg.scale.set(FlxG.width, FlxG.height);
		bg.updateHitbox();
		bg.alpha = 0;
		bg.scrollFactor.set();
		add(bg);

		// 移动端：游戏内暂停按钮按下后瞬间隐藏并打开本界面。
		// 这里用纯视觉副本（不接收触摸）继续播放完整的"按下"动画，绘制在半透明黑底之上、
		// 信息文本之下，让按钮看起来仍在 PlayState 画面上，只是被暂停界面压暗；
		// 按下动画播放的同时直接淡出（1.5s ± 0.3s，easeIn），淡出过程不会被触摸状态打断。
		if (FlxG.onMobile && PlayState.pauseBtnPressed)
		{
			PlayState.pauseBtnPressed = false;

			var pauseGhost:FlxSprite = new FlxSprite();
			pauseGhost.frames = Paths.getSparrowAtlas('mobile/pauseButton');
			pauseGhost.animation.addByPrefix('press', 'pause', 24, false);
			pauseGhost.animation.play('press');
			pauseGhost.setGraphicSize(Std.int(pauseGhost.width * 0.8));
			pauseGhost.updateHitbox();
			pauseGhost.scrollFactor.set();
			pauseGhost.antialiasing = ClientPrefs.data.antialiasing;
			pauseGhost.alpha = 0.4;
			pauseGhost.x = FlxG.width - pauseGhost.width - 15;
			pauseGhost.y = 15;
			add(pauseGhost); // 位于黑底之上、下方信息文本之前

			var fadeTime:Float = FlxG.random.float(1.2, 1.8);
			FlxTween.tween(pauseGhost, {alpha: 0}, fadeTime, {
				ease: FlxEase.quadIn,
				onComplete: _ -> pauseGhost.visible = false
			});
		}

		var levelInfo:FlxText = new FlxText(20, 15, 0, 'SONG: ${PlayState.SONG.song}', 32);
		levelInfo.scrollFactor.set();
		levelInfo.setFormat(Paths.font("vcr.ttf"), 32);
		levelInfo.updateHitbox();
		add(levelInfo);

		var levelDifficulty:FlxText = new FlxText(20, 15 + 32, 0, 'DIFFICULTY: ${Difficulty.getString().toUpperCase()}', 32);
		levelDifficulty.scrollFactor.set();
		levelDifficulty.setFormat(Paths.font('vcr.ttf'), 32);
		levelDifficulty.updateHitbox();
		add(levelDifficulty);

		var bpmText:FlxText = null;
		var speedText:FlxText = null;
		var formatText:FlxText = null;
		if (!PlayState.isCommandLineMode)
		{
			bpmText = new FlxText(20, 15 + 64, 0, 'cur.BPM: ${Conductor.bpm}', 32);
			bpmText.scrollFactor.set();
			bpmText.setFormat(Paths.font('vcr.ttf'), 32);
			bpmText.updateHitbox();
			add(bpmText);
		}

		if (!PlayState.isCommandLineMode)
		{
			speedText = new FlxText(20, 15 + 96, 0, '', 32);
			speedText.scrollFactor.set();
			speedText.setFormat(Paths.font('vcr.ttf'), 32);
			speedText.updateHitbox();
			if (ClientPrefs.getGameplaySetting('scrolltype', 'multiplicative') == 'constant') {
				speedText.applyMarkup('<y>NOTE SPEED: <y>!${PlayState.instance.songSpeed}x!${PlayState.SONG.speed != PlayState.instance.songSpeed ? '<y> (${PlayState.SONG.speed}x)<y>' : ''}', [
				new FlxTextFormatMarkerPair(format1, "<y>"),
				new FlxTextFormatMarkerPair(format2, "!"),
			]);
			} else speedText.text = 'NOTE SPEED: ${PlayState.instance.songSpeed}x${PlayState.SONG.speed != PlayState.instance.songSpeed ? ' (${PlayState.SONG.speed}x)' : ''}';
			add(speedText);
		}
		if (!PlayState.isCommandLineMode)
		{
			formatText = new FlxText(20, 15 + 128, 0, 'CHART FORMAT: ${PlayState.SONG.format}', 32);
			formatText.scrollFactor.set();
			formatText.setFormat(Paths.font('vcr.ttf'), 32);
			formatText.updateHitbox();
			add(formatText);
		}

		var generatedByText:FlxText = null;
		if (!PlayState.isCommandLineMode && PlayState.SONG.generatedBy != null && PlayState.SONG.generatedBy.trim().length > 0)
		{
			generatedByText = new FlxText(20, 15 + 160, 0, 'GENERATED BY: ${PlayState.SONG.generatedBy}', 32);
			generatedByText.scrollFactor.set();
			generatedByText.setFormat(Paths.font('vcr.ttf'), 32);
			generatedByText.updateHitbox();
			// 出处字符串通常较长，超出屏宽时自动缩小字号
			var maxWidth:Float = FlxG.width - 40;
			if (generatedByText.width > maxWidth)
			{
				var shrunk:Int = Std.int(Math.max(12, 32 * maxWidth / generatedByText.width));
				generatedByText.setFormat(Paths.font('vcr.ttf'), shrunk);
				generatedByText.updateHitbox();
			}
			add(generatedByText);
		}

		//var blueballedTxt:FlxText = new FlxText(20, 15 + 160, 0, LanguageBasic.getPhrase("blueballed", "Blueballed: {1}", [PlayState.deathCounter]), 32);
		var blueballedTxt:FlxText = new FlxText(20, 15 + 160, 0, 'BLUEBALLLED: ${PlayState.deathCounter}', 32);
		blueballedTxt.scrollFactor.set();
		blueballedTxt.setFormat(Paths.font('vcr.ttf'), 32);
		if (generatedByText != null) blueballedTxt.y += 32;
		if (!PlayState.isCommandLineMode && PlayState.SONG.specialInst != null && PlayState.SONG.specialInst.trim().length > 0) blueballedTxt.y += 32;
		if (!PlayState.isCommandLineMode && PlayState.SONG.specialVocal != null && PlayState.SONG.specialVocal.trim().length > 0) blueballedTxt.y += 32;
		blueballedTxt.updateHitbox();
		add(blueballedTxt);

		// 命令行直启：仅保留 SONG / DIFFICULTY / BLUEBALLLED 三行，曲名与难度的值显示为红色
		if (PlayState.isCommandLineMode)
		{
			levelInfo.text = 'SONG: §${PlayState.SONG.song}§';
			levelInfo.applyMarkup(levelInfo.text, [new FlxTextFormatMarkerPair(new FlxTextFormat(0xFFFF3030), '§')]);
			levelDifficulty.text = 'DIFFICULTY: §${Difficulty.getString().toUpperCase()}§';
			levelDifficulty.applyMarkup(levelDifficulty.text, [new FlxTextFormatMarkerPair(new FlxTextFormat(0xFFFF3030), '§')]);
			// 紧跟在 DIFFICULTY(15+32) 之下，避免与上方信息行之间留空
			blueballedTxt.y = 15 + 64;
		}

		// 移动端：信息列末行显示电量与充电状态（右对齐，风格与 SONG 等行一致）
		if (FlxG.onMobile)
		{
			batteryText = new FlxText(20, blueballedTxt.y + 32, 0, '', 32);
			batteryText.scrollFactor.set();
			batteryText.setFormat(Paths.font('vcr.ttf'), 32);
			batteryText.updateHitbox();
			batteryText.x = FlxG.width - (batteryText.width + 20);
			batteryText.alpha = 0;
			add(batteryText);
			refreshBatteryText();
			batteryRefresh = 5;
		}

		var sprcialInstText:FlxText = null;
		var specialVocalText:FlxText = null;
		
		if (!PlayState.isCommandLineMode && PlayState.SONG.specialInst != null && PlayState.SONG.specialInst.trim().length > 0) {
			sprcialInstText = new FlxText(20, 15 + 160, 0, 'Special Inst: ${PlayState.SONG.specialInst}', 32);
			sprcialInstText.scrollFactor.set();
			sprcialInstText.setFormat(Paths.font('vcr.ttf'), 32);
			if (generatedByText != null) sprcialInstText.y += 32;
			sprcialInstText.updateHitbox();
			add(sprcialInstText);
		}
		
		if (!PlayState.isCommandLineMode && PlayState.SONG.specialVocal != null && PlayState.SONG.specialVocal.trim().length > 0) {
			specialVocalText = new FlxText(20, 15 + 160, 0, 'Special Vocal: ${PlayState.SONG.specialVocal}', 32);
			specialVocalText.scrollFactor.set();
			specialVocalText.setFormat(Paths.font('vcr.ttf'), 32);
			specialVocalText.updateHitbox();
			if (generatedByText != null) specialVocalText.y += 32;
			if (sprcialInstText != null) specialVocalText.y += 32;
			add(specialVocalText);
		}

		practiceText = new FlxText(20, 15 + 197, 0, LanguageBasic.getPhrase("Practice Mode").toUpperCase(), 32);
		practiceText.scrollFactor.set();
		practiceText.setFormat(Paths.font('vcr.ttf'), 32);
		practiceText.x = FlxG.width - (practiceText.width + 20);
		practiceText.y = FlxG.height - (practiceText.height + 55);
		practiceText.updateHitbox();
		practiceText.visible = PlayState.instance.practiceMode;
		add(practiceText);

		var chartingText:FlxText = new FlxText(20, 15 + 197, 0, LanguageBasic.getPhrase("Charting Mode").toUpperCase(), 32);
		chartingText.scrollFactor.set();
		chartingText.setFormat(Paths.font('vcr.ttf'), 32);
		chartingText.x = FlxG.width - (chartingText.width + 20);
		chartingText.y = FlxG.height - (chartingText.height + 20);
		chartingText.updateHitbox();
		chartingText.visible = PlayState.chartingMode;
		add(chartingText);

		blueballedTxt.alpha = 0;
		levelDifficulty.alpha = 0;
		levelInfo.alpha = 0;
		if (bpmText != null) bpmText.alpha = 0;
		if (speedText != null) speedText.alpha = 0;
		if (formatText != null) formatText.alpha = 0;
		if (generatedByText != null) generatedByText.alpha = 0;
		if (sprcialInstText != null) sprcialInstText.alpha = 0;
		if (specialVocalText != null) specialVocalText.alpha = 0;

		levelInfo.x = FlxG.width - (levelInfo.width + 20);
		levelDifficulty.x = FlxG.width - (levelDifficulty.width + 20);
		if (bpmText != null) bpmText.x = FlxG.width - (bpmText.width + 20);
		if (speedText != null) speedText.x = FlxG.width - (speedText.width + 20);
		if (formatText != null) formatText.x = FlxG.width - (formatText.width + 20);
		if (generatedByText != null) generatedByText.x = FlxG.width - (generatedByText.width + 20);
		blueballedTxt.x = FlxG.width - (blueballedTxt.width + 20);
		if (specialVocalText != null) specialVocalText.x = FlxG.width - (specialVocalText.width + 20);
		if (sprcialInstText != null) sprcialInstText.x = FlxG.width - (sprcialInstText.width + 20);
		if (batteryText != null) batteryText.x = FlxG.width - (batteryText.width + 20);

		FlxTween.tween(bg, {alpha: 0.6}, 0.3, {ease: FlxEase.quartInOut});

		// 按实际显示的行顺序依次淡入：避免因某行缺失（数据为空/命令行模式）而沿用固定延迟，出现明显空档
		var fadeRows:Array<FlxText> = [levelInfo, levelDifficulty];
		if (bpmText != null) fadeRows.push(bpmText);
		if (speedText != null) fadeRows.push(speedText);
		if (formatText != null) fadeRows.push(formatText);
		if (generatedByText != null) fadeRows.push(generatedByText);
		if (sprcialInstText != null) fadeRows.push(sprcialInstText);
		if (specialVocalText != null) fadeRows.push(specialVocalText);
		fadeRows.push(blueballedTxt);
		if (batteryText != null) fadeRows.push(batteryText);

		for (i in 0...fadeRows.length)
		{
			var row:FlxText = fadeRows[i];
			FlxTween.tween(row, {alpha: 1, y: row.y + 5}, 0.3, {ease: FlxEase.quartInOut, startDelay: 0.1 + i * 0.1});
		}

		grpMenuShit = new FlxTypedGroup<Alphabet>();
		add(grpMenuShit);

		missingTextBG = new FlxSprite().makeGraphic(1, 1, FlxColor.BLACK);
		missingTextBG.scale.set(FlxG.width, FlxG.height);
		missingTextBG.updateHitbox();
		missingTextBG.alpha = 0.6;
		missingTextBG.visible = false;
		add(missingTextBG);
		
		missingText = new FlxText(50, 0, FlxG.width - 100, '', 24);
		missingText.setFormat(Paths.font("vcr.ttf"), 24, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		missingText.scrollFactor.set();
		missingText.visible = false;
		add(missingText);

		regenMenu();
		cameras = [FlxG.cameras.list[FlxG.cameras.list.length - 1]];

		// 动画返回按钮（暂时注释：系统返回键已能关闭暂停菜单，如需恢复取消下面注释即可）
		/*
		if (FlxG.onMobile)
		{
			var backBtn:MobileButton = MobileButton.back(() -> close(), cameras[0], true);
			add(backBtn);
		}
		*/

		addTouchPad(menuItems.contains('Skip Time') ? 'LEFT_FULL' : 'UP_DOWN', 'A');
		addTouchPadCamera();

		super.create();
	}
	
	/**
	 * 暂停菜单电量行：与 SONG / DIFFICULTY 等行同风格（固定英文，vcr 字体不支持中文）。
	 * 仅数字百分比按电量染色（0% 红 → 100% 蓝），其余文字保持默认白色。
	 */
	function refreshBatteryText():Void
	{
		if (batteryText == null)
			return;

		if (!FlxG.onMobile)
		{
			batteryText.visible = false;
			return;
		}

		var level:Int = MobileUtil.getBatteryLevel();
		if (level < 0)
		{
			batteryText.visible = false;
			return;
		}

		var suffix:String = '';
		// 非充电状态不显示后缀；充电时显示功率（设备读不到功率则只显示 CHARGING）
		if (MobileUtil.isCharging())
		{
			var wattsText:String = MobileUtil.formatWatts(MobileUtil.getChargingWatts());
			suffix = (wattsText.length > 0) ? ' (CHARGING $wattsText)' : ' (CHARGING)';
		}

		var line:String = 'BATTERY: §$level%§$suffix';
		batteryText.applyMarkup(line, [new FlxTextFormatMarkerPair(new FlxTextFormat(MobileUtil.getBatteryColor(level)), '§')]);
		batteryText.visible = true;
		batteryText.updateHitbox();
		// 文案长度变化后保持右对齐
		batteryText.x = FlxG.width - (batteryText.width + 20);
	}

	function getPauseSong()
	{
		var formattedSongName:String = (songName != null ? Paths.formatToSongPath(songName) : '');
		var formattedPauseMusic:String = Paths.formatToSongPath(ClientPrefs.data.pauseMusic);
		if(formattedSongName == 'none' || (formattedSongName != 'none' && formattedPauseMusic == 'none')) return null;

		return (formattedSongName != '') ? formattedSongName : formattedPauseMusic;
	}

	var holdTime:Float = 0;
	var cantUnpause:Float = 0.1;
	override function update(elapsed:Float)
	{
		cantUnpause -= elapsed;
		if (pauseMusic.volume < 0.5)
			pauseMusic.volume += 0.01 * elapsed;

		// 电量信息每 5 秒刷新（MobileUtil 内部也有 5 秒缓存，不会频繁走 JNI）
		if (batteryText != null)
		{
			batteryRefresh -= elapsed;
			if (batteryRefresh <= 0)
			{
				batteryRefresh = 5;
				refreshBatteryText();
			}
		}

		super.update(elapsed);

		if(controls.BACK)
		{
			close();
			return;
		}

		if(FlxG.keys.justPressed.F5)
		{
			FlxTransitionableState.skipNextTransIn = true;
			FlxTransitionableState.skipNextTransOut = true;
			PlayState.nextReloadAll = true;
			MusicBeatState.resetState();
		}

		updateSkipTextStuff();
		if (controls.UI_UP_P)
		{
			changeSelection(-1);
		}
		if (controls.UI_DOWN_P)
		{
			changeSelection(1);
		}

		var daSelected:String = menuItems[curSelected];
		switch (daSelected)
		{
			case 'Skip Time':
				if (controls.UI_LEFT_P)
				{
					FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);
					curTime -= 1000;
					holdTime = 0;
				}
				if (controls.UI_RIGHT_P)
				{
					FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);
					curTime += 1000;
					holdTime = 0;
				}

				if(controls.UI_LEFT || controls.UI_RIGHT)
				{
					holdTime += elapsed;
					if(holdTime > 0.5)
					{
						curTime += 45000 * elapsed * (controls.UI_LEFT ? -1 : 1);
					}

					if(curTime >= FlxG.sound.music.length) curTime -= FlxG.sound.music.length;
					else if(curTime < 0) curTime += FlxG.sound.music.length;
					updateSkipTimeText();
				}
		}

		if (controls.ACCEPT && (cantUnpause <= 0 || !controls.controllerMode))
		{
			if (menuItems == difficultyChoices)
			{
				if (PlayState.SONG == null)
				{
					menuItems = menuItemsOG;
					regenMenu();
					super.update(elapsed);
					return;
				}
				var songLowercase:String = Paths.formatToSongPath(PlayState.SONG.song);
				var poop:String = Highscore.formatSong(songLowercase, curSelected);
				try
				{
					if(menuItems.length - 1 != curSelected && difficultyChoices.contains(daSelected))
					{
						var loadedSong = Song.loadFromJson(poop, songLowercase);
						if(loadedSong == null)
						{
							missingText.text = 'ERROR WHILE LOADING CHART:\nMissing chart file for difficulty: ${poop}';
							missingText.screenCenter(Y);
							missingText.visible = true;
							missingTextBG.visible = true;
							FlxG.sound.play(Paths.sound('cancelMenu'));
							super.update(elapsed);
							return;
						}
						PlayState.storyDifficulty = curSelected;
						MusicBeatState.resetState();
						FlxG.sound.music.volume = 0;
						PlayState.changedDifficulty = true;
						PlayState.chartingMode = false;
						return;
					}
				}
				catch(e:haxe.Exception)
				{
					trace('ERROR! ${e.message}');

					var errorStr:String = e.message;
					if(errorStr.startsWith('[lime.utils.Assets] ERROR:')) errorStr = 'Missing file: ' + errorStr.substring(errorStr.indexOf(songLowercase), errorStr.length-1); //Missing chart
					else errorStr += '\n\n' + e.stack;

					missingText.text = 'ERROR WHILE LOADING CHART:\n$errorStr';
					missingText.screenCenter(Y);
					missingText.visible = true;
					missingTextBG.visible = true;
					FlxG.sound.play(Paths.sound('cancelMenu'));

					super.update(elapsed);
					return;
				}


				menuItems = menuItemsOG;
				regenMenu();
			}

			switch (daSelected)
			{
				case "Resume":
					if (ClientPrefs.data.gcOnResume)
						Paths.clearUnusedMemory();
					close();
				case 'Change Difficulty':
					menuItems = difficultyChoices;
					deleteSkipTimeText();
					regenMenu();
				case 'Toggle Practice Mode':
					PlayState.instance.practiceMode = !PlayState.instance.practiceMode;
					PlayState.changedDifficulty = true;
					practiceText.visible = PlayState.instance.practiceMode;
				case "Restart Song":
					restartSong();
			case 'Chart Editor':
				if (ClientPrefs.data.developer)
					PlayState.instance.openChartEditor();
				case "Leave Charting Mode":
					restartSong();
					PlayState.chartingMode = false;
				case 'Skip Time':
					if(curTime < Conductor.songPosition)
					{
						PlayState.startOnTime = curTime;
						restartSong(true);
					}
					else
					{
						if (curTime != Conductor.songPosition)
						{
							PlayState.instance.clearNotesBefore(curTime);
							PlayState.instance.setSongTime(curTime);
						}
						close();
					}
				case 'End Song':
					close();
					PlayState.instance.notes.clear();
					PlayState.instance.normalNotes.clear();
					PlayState.instance.holdNotes.clear();
					PlayState.instance.unspawnNotes = [];
					PlayState.instance.finishSong(true);
				case 'Toggle Botplay':
					PlayState.instance.cpuControlled = !PlayState.instance.cpuControlled;
					PlayState.changedDifficulty = true;
					PlayState.instance.botplayTxt.visible = PlayState.instance.cpuControlled;
					PlayState.instance.botplayTxt.alpha = 1;
					PlayState.instance.botplaySine = 0;
				case 'Options':
					PlayState.instance.paused = true; // For lua
					PlayState.instance.vocals.volume = 0;
					PlayState.instance.canResync = false;
					MusicBeatState.switchState(new OptionsState());
					if(ClientPrefs.data.pauseMusic != 'None')
					{
						FlxG.sound.playMusic(Paths.music(Paths.formatToSongPath(ClientPrefs.data.pauseMusic)), pauseMusic.volume);
						FlxTween.tween(FlxG.sound.music, {volume: 1}, 0.8);
						FlxG.sound.music.time = pauseMusic.time;
					}
					OptionsState.onPlayState = true;
				case "Exit to menu":
					#if DISCORD_ALLOWED DiscordClient.resetClientID(); #end
					PlayState.deathCounter = 0;
					PlayState.seenCutscene = false;

					PlayState.instance.canResync = false;
					Mods.loadTopMod();
					if(PlayState.isStoryMode)
						MusicBeatState.switchState(new StoryMenuState());
					else 
						MusicBeatState.switchState(new FreeplayState());

					FlxG.sound.playMusic(Paths.menuMusicAudio());
					PlayState.changedDifficulty = false;
					PlayState.chartingMode = false;
					FlxG.camera.followLerp = 0;
			}
		}

		if (touchPad == null) //sometimes it dosent add the tpad, hopefully this fixes it
		{
			addTouchPad(PlayState.chartingMode ? 'LEFT_FULL' : 'UP_DOWN', 'A');
			addTouchPadCamera();
		}
	}

	function deleteSkipTimeText()
	{
		if(skipTimeText != null)
		{
			skipTimeText.kill();
			remove(skipTimeText);
			skipTimeText.destroy();
		}
		skipTimeText = null;
		skipTimeTracker = null;
	}

	public static function restartSong(noTrans:Bool = false)
	{
		PlayState.instance.paused = true; // For lua

		// 若当前正在回放，重玩时保留回放数据，使重建的 PlayState 继续回放同一段
		if (PlayState.instance.isReplaying && PlayState.instance.replayData != null && PlayState.instance.replayData.length > 0)
		{
			PlayState.pendingReplayData = PlayState.instance.replayData.copy();
			PlayState.shouldStartReplay = true;
			PlayState.retainReplayOnRestart = true;
		}

		FlxG.sound.music.volume = 0;
		PlayState.instance.vocals.volume = 0;

		if(noTrans)
		{
			FlxTransitionableState.skipNextTransIn = true;
			FlxTransitionableState.skipNextTransOut = true;
		}
		MusicBeatState.resetState();
	}

	override function destroy()
	{
		pauseMusic.destroy();
		super.destroy();
	}

	function changeSelection(change:Int = 0):Void
	{
		curSelected = FlxMath.wrap(curSelected + change, 0, menuItems.length - 1);
		for (num => item in grpMenuShit.members)
		{
			item.targetY = num - curSelected;
			item.alpha = 0.6;
			if (item.targetY == 0)
			{
				item.alpha = 1;
				if(item == skipTimeTracker)
				{
					curTime = Math.max(0, Conductor.songPosition);
					updateSkipTimeText();
				}
			}
		}
		missingText.visible = false;
		missingTextBG.visible = false;
		FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);
	}

	function regenMenu():Void {
		for (i in 0...grpMenuShit.members.length)
		{
			var obj:Alphabet = grpMenuShit.members[0];
			obj.kill();
			grpMenuShit.remove(obj, true);
			obj.destroy();
		}

		for (num => str in menuItems) {
			var item = new Alphabet(90, 320, LanguageBasic.getPhrase('pause_$str', str), true);
			item.isMenuItem = true;
			item.targetY = num;
			grpMenuShit.add(item);

			if(str == 'Skip Time')
			{
				skipTimeText = new FlxText(0, 0, 0, '', 64);
				skipTimeText.setFormat(Paths.font("vcr.ttf"), 64, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
				skipTimeText.scrollFactor.set();
				skipTimeText.borderSize = 2;
				skipTimeTracker = item;
				add(skipTimeText);

				updateSkipTextStuff();
				updateSkipTimeText();
			}
		}
		curSelected = 0;
		changeSelection();
	}
	
	function updateSkipTextStuff()
	{
		if(skipTimeText == null || skipTimeTracker == null) return;

		skipTimeText.x = skipTimeTracker.x + skipTimeTracker.width + 60;
		skipTimeText.y = skipTimeTracker.y;
		skipTimeText.visible = (skipTimeTracker.alpha >= 1);
	}

	function updateSkipTimeText()
		skipTimeText.text = FlxStringUtil.formatTime(Math.max(0, Math.floor(curTime / 1000)), false) + ' / ' + FlxStringUtil.formatTime(Math.max(0, Math.floor(FlxG.sound.music.length / 1000)), false);
}
