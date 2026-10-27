package options;

import objects.Note;
import objects.StrumNote;
import objects.NoteSplash;
import objects.Alphabet;

class VisualsSettingsSubState extends BaseOptionsMenu
{
	var noteOptionID:Int = -1;
	var notes:FlxTypedGroup<StrumNote>;
	var splashes:FlxTypedGroup<NoteSplash>;
	var noteY:Float = 90;

	// 可选样式面板（聚焦 noteSkins / noteSplashes 时从右侧飞入）
	var noteSkinList:Array<String> = [];
	var splashSkinList:Array<String> = [];
	var skinPanelBG:FlxSprite;
	var skinPanelLines:Array<FlxText> = [];
	var panelMode:String = null; // 'noteSkin' / 'splashSkin' / null
	var panelHiddenX:Float = 0;
	var panelLineH:Float = 28;
	var panelPadX:Float = 14;
	var panelPadY:Float = 12;
	var panelMargin:Float = 16;
	public function new()
	{
		title = Language.get('visuals_menu');
		rpcTitle = 'Visuals Settings Menu'; //for Discord Rich Presence

		// for note skins and splash skins
		notes = new FlxTypedGroup<StrumNote>();
		splashes = new FlxTypedGroup<NoteSplash>();
		for (i in 0...Note.colArray.length)
		{
			var note:StrumNote = new StrumNote(370 + (560 / Note.colArray.length) * i, -200, i, 0);
			changeNoteSkin(note);
			notes.add(note);
			
			var splash:NoteSplash = new NoteSplash(0, 0, NoteSplash.defaultNoteSplash + NoteSplash.getSplashSkinPostfix());
			splash.inEditor = true;
			splash.babyArrow = note;
			splash.ID = i;
			splash.kill();
			splashes.add(splash);
		}

		// options
		var option:Option = new Option(Language.get('arrow_color_mode'),
			Language.get('arrow_colormode_desc'),
			'arrowColorMode',
			STRING,
			['RGB', 'HSV']);
		addOption(option);
		option.onChange = onChangeArrowColorMode;

		var noteSkins:Array<String> = Mods.mergeAllTextsNamed('images/noteSkins/list.txt');
		if(noteSkins.length > 0)
		{
			if(!noteSkins.contains(ClientPrefs.data.noteSkin))
				ClientPrefs.data.noteSkin = ClientPrefs.defaultData.noteSkin;

			noteSkins.insert(0, ClientPrefs.defaultData.noteSkin);
			noteSkinList = noteSkins;
			var option:Option = new Option(Language.get('note_skins'),
				Language.get("noteskin_desc"),
				'noteSkin',
				STRING,
				noteSkins);
			addOption(option);
			option.onChange = onChangeNoteSkin;
			noteOptionID = optionsArray.length - 1;
		}
		
		var noteSplashes:Array<String> = Mods.mergeAllTextsNamed('images/noteSplashes/list.txt');
		if(noteSplashes.length > 0)
		{
			if(!noteSplashes.contains(ClientPrefs.data.splashSkin))
				ClientPrefs.data.splashSkin = ClientPrefs.defaultData.splashSkin;

			noteSplashes.insert(0, ClientPrefs.defaultData.splashSkin);
			splashSkinList = noteSplashes;
			var option:Option = new Option(Language.get('note_splashes'),
				Language.get("notesplash_desc"),
				'splashSkin',
				STRING,
				noteSplashes);
			addOption(option);
			option.onChange = onChangeSplashSkin;
		}

		var holdCoverSkins:Array<String> = Mods.mergeAllTextsNamed('images/holdCover/list.txt');
		if(holdCoverSkins.length > 0)
		{
			if(!holdCoverSkins.contains(ClientPrefs.data.holdCoverSkin))
				ClientPrefs.data.holdCoverSkin = ClientPrefs.defaultData.holdCoverSkin;

			holdCoverSkins.insert(0, ClientPrefs.defaultData.holdCoverSkin);
			var option:Option = new Option(Language.get('hold_cover_skin'),
				Language.get("hold_cover_skin_desc"),
				'holdCoverSkin',
				STRING,
				holdCoverSkins);
			addOption(option);
		}

		var option:Option = new Option(Language.get('multi_key_layout'),
			Language.get("multi_key_layout_desc"),
			'multiKeyLayoutStyle',
			STRING,
			['PsychEK', 'Leather']);
		addOption(option);

		var option:Option = new Option(Language.get('note_splash_opacity'),
			Language.get("notesplashopacity_desc"),
			'splashAlpha',
			PERCENT);
		option.scrollSpeed = 1.6;
		option.minValue = 0.0;
		option.maxValue = 1;
		option.changeValue = 0.1;
		option.decimals = 1;
		addOption(option);
		option.onChange = playNoteSplashes;

		var option:Option = new Option(Language.get('hide_hud'),
			Language.get("hidehud_desc"),
			'hideHud',
			BOOL);
		addOption(option);

		var option:Option = new Option(Language.get('3_state_icons_normal_lose_win'),
			Language.get("three_icons_desc"),
			'threeIcons',
			BOOL);
		addOption(option);

		var option:Option = new Option(Language.get('load_leather_icons'),
			Language.get("load_leather_icons_desc"),
			'loadLeatherIcons',
			STRING,
			['default', 'leather', 'os']);
		addOption(option);

		var option:Option = new Option(Language.get('dynamic_health_icons'),
			Language.get("dynamic_health_icons_desc"),
			'dynamicHealthIcons',
			BOOL);
		addOption(option);

		var option:Option = new Option(Language.get('opponent_splashes'),
			Language.get("opponent_splashes_desc"),
			'opponentSplashes',
			BOOL);
		addOption(option);

		var option:Option = new Option(Language.get('hold_covers'),
			Language.get("hold_covers_desc"),
			'holdCovers',
			BOOL);
		addOption(option);

		var option:Option = new Option(Language.get('opponent_hold_covers'),
			Language.get("opponent_hold_covers_desc"),
			'opponentHoldCovers',
			BOOL);
		addOption(option);

		var option:Option = new Option(Language.get('note_timer'),
			Language.get("note_timer_desc"),
			'noteTimerEnabled',
			BOOL);
		addOption(option);

		var option:Option = new Option(Language.get('note_timer_layer'),
			Language.get("note_timer_layer_desc"),
			'noteTimerLayer',
			STRING,
			['Above Notes', 'Below Notes']);
		option.valueLocalizations = [
			'Above Notes' => Language.get('note_timer_layer_above'),
			'Below Notes' => Language.get('note_timer_layer_below')
		];
		addOption(option);

		var option:Option = new Option(Language.get('note_timer_display'),
			Language.get("note_timer_display_desc"),
			'noteTimerDisplay',
			STRING,
			['Seconds', 'Beats']);
		option.valueLocalizations = [
			'Seconds' => Language.get('note_timer_display_seconds'),
			'Beats'   => Language.get('note_timer_display_beats')
		];
		addOption(option);

		var option:Option = new Option(Language.get('note_timer_stepped'),
			Language.get("note_timer_stepped_desc"),
			'noteTimerStepped',
			BOOL);
		addOption(option);
		
		var option:Option = new Option(Language.get('time_bar'),
			Language.get("timebar_desc"),
			'timeBarType',
			STRING,
			['Time Left', 'Time Elapsed', 'Song Name', 'Disabled']);
		addOption(option);

		var option:Option = new Option(Language.get('flashing_lights'),
			Language.get("flashinglights_desc"),
			'flashing',
			BOOL);
		addOption(option);

		// 画面每拍缩放特效（标题界面 3%，主界面 1.5%）
		var option:Option = new Option(Language.get('beat_scale'),
			Language.get("beat_scale_desc"),
			'beatScale',
			BOOL);
		addOption(option);

		var option:Option = new Option(Language.get('camera_zooms'),
			Language.get("camerazooms_desc"),
			'camZooms',
			BOOL);
		addOption(option);

		var option:Option = new Option(Language.get('score_text_grow_on_hit'),
			Language.get("scoretextgrow_desc"),
			'scoreZoom',
			BOOL);
		addOption(option);

		var option:Option = new Option(Language.get('scoretext_language'),
			Language.get("scoretextlanguage_desc"),
			'scoreLanguage',
			STRING,
			['auto', 'en_us', 'zh_cn', 'zh_tw', 'ja', 'ko', 'kc_cn']);
		addOption(option);

		var option:Option = new Option(Language.get('health_bar_opacity'),
			Language.get("healthbaropacity_desc"),
			'healthBarAlpha',
			PERCENT);
		option.scrollSpeed = 1.6;
		option.minValue = 0.0;
		option.maxValue = 1;
		option.changeValue = 0.1;
		option.decimals = 1;
		addOption(option);
		
		var option:Option = new Option(Language.get('fps_counter'),
			Language.get("showfps_desc"),
			'showFPS',
			BOOL);
		addOption(option);
		option.onChange = onChangeFPSCounter;

		var option:Option = new Option(Language.get('fps_counter_style'),
			Language.get("fps_counter_style_desc"),
			'fpsStyle',
			STRING,
			['Psych', 'Kathy', 'Simple', 'V-Slice']);
		addOption(option);
		option.onChange = onChangeFPSStyle;

		var option:Option = new Option(Language.get('fps_counter_layer'),
			Language.get("fps_counter_layer_desc"),
			'fpsLayer',
			STRING,
			['Stage', 'Game']);
		addOption(option);
		option.onChange = onChangeFPSLayer;
		
		var option:Option = new Option(Language.get('show_game_version_name'),
			Language.get("show_game_version_desc"),
			'exgameversion',
			BOOL);
		fpsExgameversionOption = addOption(option);
		option.onChange = function() {
			if (Main.fpsVar != null) Main.fpsVar.applySettings();
		};

		fpsSettingsButton = new Option(
			Language.get('psych_fps_settings'),
			Language.get("fps_settings_button_desc"),
			'_fpsSettings',
			BUTTON);
		addOption(fpsSettingsButton);
		fpsSettingsButton.onChange = function() {
			switch(ClientPrefs.data.fpsStyle)
			{
				case 'Simple': MusicBeatState.switchState(new SimpleInfoDisplaySettingsState());
				case 'V-Slice': MusicBeatState.switchState(new DebugDisplaySettingsState());
				default: MusicBeatState.switchState(new KathyFPSCounterSettingsState());
			}
		};

		//新版lime跟git库的不同，故临时禁用此项，之后也许会改
		/*#if native
		var option:Option = new Option(Language.get('vsync'),
			Language.get("vsync_desc"),
			'vsync',
			BOOL);
		option.onChange = onChangeVSync;
		addOption(option);
		#end*/
		
		var option:Option = new Option(Language.get('pause_music'),
			Language.get("pausemusic_desc"),
			'pauseMusic',
			STRING,
			['None', 'Tea Time', 'Breakfast', 'Breakfast (Pico)', "Romantic Smile"]);
		addOption(option);
		option.onChange = onChangePauseMusic;

		// 主菜单音乐：'Default' 用标准 freakyMenu；其余由 freakyMenu-BPM.json 定义的三要素（显示名/音频文件/BPM）加自动扫描组成
		var menuMusicOptions:Array<String> = Paths.availableMenuMusicNames();
		var option:Option = new Option(Language.get('menu_music'),
			Language.get("menumusic_desc"),
			'daMenuMusic',
			STRING,
			menuMusicOptions);
		addOption(option);
		option.onChange = onChangeMenuMusic;

		// 画面每拍缩放特效（标题界面 3%，主界面 1.5%）
		var option:Option = new Option(Language.get('beat_scale'),
			Language.get("beat_scale_desc"),
			'beatScale',
			BOOL);
		addOption(option);
		
		#if CHECK_FOR_UPDATES
		var option:Option = new Option(Language.get('check_for_updates'),
			Language.get("checkforupdates_desc"),
			'checkForUpdates',
			BOOL);
		addOption(option);

		var option:Option = new Option(Language.get('receive_beta_builds'),
			Language.get("receivebetabuilds_desc"),
			'receiveBetaBuilds',
			BOOL);
		addOption(option);
		#end

	#if DISCORD_ALLOWED
	var option:Option = new Option(Language.get('discord_rich_presence'),
		Language.get("discordrpc_desc"),
		'discordRPC',
		BOOL);
	addOption(option);
	#end

	var option:Option = new Option(Language.get('disable_networking'),
		Language.get("disable_networking_desc"),
		'disableNetworking',
		BOOL);
	addOption(option);


		var option:Option = new Option(Language.get('combo_stacking'),
		Language.get("combostacking_desc"),
		'comboStacking',
		BOOL);
	addOption(option);

	var soundTrayOptions:Array<String> = ['Flixel', 'Funkin', 'Kathy', 'Dave'];
	var option:Option = new Option(Language.get('sound_tray_style'),
		Language.get("sound_tray_style_desc"),
		'soundTrayStyle',
		STRING,
		soundTrayOptions);
	addOption(option);
	
	var option:Option = new Option(Language.get('hold_note_behind'),
		Language.get("hold_note_behind_desc"),
		'holdNoteBehind',
		BOOL);
	addOption(option);

		// ===== 动态窗口标题 (Dynamic Window Title) =====
		#if !mobile
		var option:Option = new Option(Language.get('dynamic_window_title'),
			Language.get('wintitle_dynamic'),
			'dynamicWindowTitle',
			BOOL);
		option.onChange = function() { Main.updateWindowTitle(); };
		addOption(option);

		var option:Option = new Option(Language.get('show_current_screen'),
			Language.get('wintitle_state'),
			'windowTitleShowState',
			BOOL);
		option.onChange = function() { Main.updateWindowTitle(); };
		addOption(option);

		var option:Option = new Option(Language.get('show_current_mod'),
			Language.get('wintitle_mod'),
			'windowTitleShowMod',
			BOOL);
		option.onChange = function() { Main.updateWindowTitle(); };
		addOption(option);

		var option:Option = new Option(Language.get('show_current_song'),
			Language.get('wintitle_song'),
			'windowTitleShowSong',
			BOOL);
		option.onChange = function() { Main.updateWindowTitle(); };
		addOption(option);

		var option:Option = new Option(Language.get('show_song_difficulty'),
			Language.get('wintitle_difficulty'),
			'windowTitleShowDifficulty',
			BOOL);
		option.onChange = function() { Main.updateWindowTitle(); };
		addOption(option);
		#end

		super();
		refreshFPSStyleDependentOptions();
		add(notes);
		add(splashes);

		// 样式选择面板（半透明黑底 + 右侧飞入）
		skinPanelBG = new FlxSprite();
		skinPanelBG.makeGraphic(1, 1, FlxColor.BLACK);
		skinPanelBG.alpha = 0.5;
		skinPanelBG.scrollFactor.set();
		panelHiddenX = FlxG.width + 80;
		skinPanelBG.x = panelHiddenX;
		skinPanelBG.y = (FlxG.height - skinPanelBG.height) / 2;
		add(skinPanelBG); // 加在文本之下
	}

	var notesShown:Bool = false;
	var fpsSettingsButton:Option;
	var fpsExgameversionOption:Option;

	// 选项列表分帧构建完成后再同步一次依赖 fpsStyle 的状态，确保初始进入即显示禁用后缀
	override function onOptionsBuilt():Void
	{
		super.onOptionsBuilt();
		refreshFPSStyleDependentOptions();
	}

	override function changeSelection(change:Int = 0, skipRefresh:Bool = false, skipDesc:Bool = false)
	{
		super.changeSelection(change, skipRefresh, skipDesc);
		
		// 样式面板已统一到 BaseOptionsMenu 的通用 STRING 候选面板，这里不再单独显示
		var isSkinMode:Bool = false;

		switch(curOption.variable)
		{
			case 'noteSkin', 'splashSkin', 'splashAlpha':
				if(!notesShown)
				{
					for (note in notes.members)
					{
						FlxTween.cancelTweensOf(note);
						FlxTween.tween(note, {y: noteY}, Math.abs(note.y / (200 + noteY)) / 3, {ease: FlxEase.quadInOut});
					}
				}
				notesShown = true;
				if(curOption.variable.startsWith('splash') && Math.abs(notes.members[0].y - noteY) < 25) playNoteSplashes();

			default:
				if(notesShown) 
				{
					for (note in notes.members)
					{
						FlxTween.cancelTweensOf(note);
						FlxTween.tween(note, {y: -200}, Math.abs(note.y / (200 + noteY)) / 3, {ease: FlxEase.quadInOut});
					}
				}
				notesShown = false;
		}

		// 样式选择面板：仅在聚焦 noteSkin / splashSkin 时显示
		if (isSkinMode)
		{
			var mode:String = curOption.variable;
			if (panelMode != mode)
			{
				var wasShown:Bool = (panelMode != null);
				panelMode = mode;
				rebuildSkinPanel(mode, !wasShown);
			}
			showSkinPanel();
		}
		else if (panelMode != null)
		{
			hideSkinPanel();
			panelMode = null;
		}
	}

	// ---------- 可选样式面板（HSV 标记 + 右侧飞入）----------

	function getNoteSkinFile(skin:String):String
	{
		var base:String = 'noteSkins/NOTE_assets';
		if (skin != ClientPrefs.defaultData.noteSkin)
			base += '-' + skin.toLowerCase().replace(' ', '_');
		return base;
	}

	function getSplashSkinFile(skin:String):String
	{
		var base:String = 'noteSplashes/noteSplashes';
		if (skin != ClientPrefs.defaultData.splashSkin)
			base += '-' + skin.toLowerCase().replace(' ', '-');
		return base;
	}

	// 检测 hsv 目录是否存在与 rgb 样式同名的文件
	function hasHSVVersion(path:String):Bool
	{
		var parts:Array<String> = path.split('/');
		var filename:String = parts.pop();
		var folder:String = parts.join('/');
		return Paths.fileExists('images/$folder/hsv/$filename.png', IMAGE);
	}

	function getStyleLabel(skin:String, file:String):String
	{
		// 当前为 HSV 渲染且存在 hsv 同名文件时，左侧加入 (HSV) 前缀
		if (ClientPrefs.data.arrowColorMode == 'HSV' && hasHSVVersion(file))
			return '(HSV) ' + skin;
		return skin;
	}

	// 根据当前模式重建面板内容。flyIn=true 时内容先放到屏幕外以便飞入
	function rebuildSkinPanel(mode:String, flyIn:Bool)
	{
		for (line in skinPanelLines)
		{
			remove(line);
			line.destroy();
		}
		skinPanelLines = [];

		var list:Array<String> = (mode == 'noteSkin') ? noteSkinList : splashSkinList;
		var current:String = (mode == 'noteSkin') ? ClientPrefs.data.noteSkin : ClientPrefs.data.splashSkin;

		var maxW:Float = 0;
		for (skin in list)
		{
			var file:String = (mode == 'noteSkin') ? getNoteSkinFile(skin) : getSplashSkinFile(skin);
			var label:String = getStyleLabel(skin, file);
			var txt:FlxText = new FlxText(0, 0, 0, label, 22);
			txt.setFormat(Paths.font("vcr.ttf"), 22, (skin == current) ? FlxColor.YELLOW : FlxColor.WHITE,
				RIGHT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			txt.borderSize = 1.5;
			txt.scrollFactor.set();
			skinPanelLines.push(txt);
			add(txt); // 加在背景之上
			if (txt.width > maxW) maxW = txt.width;
		}

		var bgW:Float = maxW + panelPadX * 2;
		var bgH:Float = list.length * panelLineH + panelPadY * 2;
		skinPanelBG.makeGraphic(Math.ceil(bgW), Math.ceil(bgH), FlxColor.BLACK);
		skinPanelBG.alpha = 0.5;

		var targetBGX:Float = FlxG.width - panelMargin - bgW;
		var targetBGY:Float = (FlxG.height - bgH) / 2;
		var startX:Float = flyIn ? panelHiddenX : targetBGX;

		skinPanelBG.x = startX;
		skinPanelBG.y = targetBGY;

		for (i => line in skinPanelLines)
		{
			line.x = startX + panelPadX;
			line.y = targetBGY + panelPadY + i * panelLineH + (panelLineH - line.height) / 2;
			line.fieldWidth = maxW;
		}
	}

	function tweenSkinPanelTo(targetBGX:Float)
	{
		FlxTween.cancelTweensOf(skinPanelBG);
		FlxTween.tween(skinPanelBG, {x: targetBGX}, 0.3, {ease: FlxEase.quartOut});
		for (line in skinPanelLines)
		{
			FlxTween.cancelTweensOf(line);
			FlxTween.tween(line, {x: targetBGX + panelPadX}, 0.3, {ease: FlxEase.quartOut});
		}
	}

	function showSkinPanel()
	{
		if (skinPanelLines.length == 0) return;
		var targetBGX:Float = FlxG.width - panelMargin - skinPanelBG.width;
		tweenSkinPanelTo(targetBGX);
	}

	function hideSkinPanel()
	{
		tweenSkinPanelTo(panelHiddenX);
	}

	function refreshSkinPanelHighlight()
	{
		if (panelMode == null) return;
		var current:String = (panelMode == 'noteSkin') ? ClientPrefs.data.noteSkin : ClientPrefs.data.splashSkin;
		var list:Array<String> = (panelMode == 'noteSkin') ? noteSkinList : splashSkinList;
		for (i => line in skinPanelLines)
		{
			if (i < list.length)
				line.color = (list[i] == current) ? FlxColor.YELLOW : FlxColor.WHITE;
		}
	}

	var changedMusic:Bool = false;
	function onChangePauseMusic()
	{
		if(ClientPrefs.data.pauseMusic == 'None')
			FlxG.sound.music.volume = 0;
		else
			FlxG.sound.playMusic(Paths.music(Paths.formatToSongPath(ClientPrefs.data.pauseMusic)));

		changedMusic = true;
	}

	// 切换主菜单音乐：立即重播所选曲目以试听（无音轨文件时静默保留静音/原曲）
	function onChangeMenuMusic()
	{
		if (FlxG.sound.music != null)
			FlxG.sound.playMusic(Paths.menuMusicAudio());
		changedMusic = true;
	}

	function onChangeArrowColorMode()
	{
		Note.globalRgbShaders = [];
		Note.globalColorSwapShaders = [];

		notes.forEachAlive(function(n) n.destroy());
		notes.clear();
		splashes.forEachAlive(function(s) s.destroy());
		splashes.clear();

		for (i in 0...Note.colArray.length)
		{
			var note:StrumNote = new StrumNote(370 + (560 / Note.colArray.length) * i, -200, i, 0);
			changeNoteSkin(note);
			notes.add(note);

			var splash:NoteSplash = new NoteSplash(0, 0, NoteSplash.defaultNoteSplash + NoteSplash.getSplashSkinPostfix());
			splash.inEditor = true;
			splash.babyArrow = note;
			splash.ID = i;
			splash.kill();
			splashes.add(splash);
		}
	}

	function onChangeNoteSkin()
	{
		notes.forEachAlive(function(note:StrumNote) {
			changeNoteSkin(note);
			note.centerOffsets();
			note.centerOrigin();
		});
		refreshSkinPanelHighlight();
	}

	function changeNoteSkin(note:StrumNote)
	{
		var baseSkin:String = Note.defaultNoteSkin;
		var postfix:String = Note.getNoteSkinPostfix();
		var customBase:String = baseSkin + postfix;

		var customExists:Bool = false;
		if(ClientPrefs.data.arrowColorMode == 'HSV')
		{
			var parts:Array<String> = customBase.split('/');
			var filename:String = parts.pop();
			var folder:String = parts.join('/');
			customExists = Paths.fileExists('images/$folder/hsv/$filename.png', IMAGE) || Paths.fileExists('images/$customBase.png', IMAGE);
		}
		else
		{
			customExists = Paths.fileExists('images/$customBase.png', IMAGE);
		}

		var skin:String = customExists ? Note.getNoteSkinPath(customBase) : Note.getNoteSkinPath(baseSkin);

		note.texture = skin;
		note.reloadNote();
		note.playAnim('static');
	}

	function onChangeSplashSkin()
	{
		var skin:String = NoteSplash.defaultNoteSplash + NoteSplash.getSplashSkinPostfix();
		for (splash in splashes)
			splash.loadSplash(skin);

		playNoteSplashes();
		refreshSkinPanelHighlight();
	}

	function playNoteSplashes()
	{
		var rand:Int = 0;
		if (splashes.members[0] != null && splashes.members[0].maxAnims > 1)
			rand = FlxG.random.int(0, splashes.members[0].maxAnims - 1); // For playing the same random animation on all 4 splashes

		for (splash in splashes)
		{
			splash.revive();

			splash.spawnSplashNote(0, 0, splash.ID, null, false);
			if (splash.maxAnims > 1)
				splash.noteData = splash.noteData % Note.colArray.length + (rand * Note.colArray.length);

			var anim:String = splash.playDefaultAnim();
			var conf = splash.config.animations.get(anim);
			var offsets:Array<Float> = [0, 0];

			var minFps:Int = 22;
			var maxFps:Int = 26;
			if (conf != null)
			{
				offsets = conf.offsets;

				minFps = conf.fps[0];
				if (minFps < 0) minFps = 0;

				maxFps = conf.fps[1];
				if (maxFps < 0) maxFps = 0;
			}

			splash.offset.set(10, 10);
			if (offsets != null)
			{
				splash.offset.x += offsets[0];
				splash.offset.y += offsets[1];
			}

			if (splash.animation.curAnim != null)
				splash.animation.curAnim.frameRate = FlxG.random.int(minFps, maxFps);
		}
	}

	override function destroy()
	{
		if(changedMusic && !OptionsState.onPlayState) FlxG.sound.playMusic(Paths.menuMusicAudio(), 1, true);
		Note.globalRgbShaders = [];
		Note.globalColorSwapShaders = [];
		super.destroy();
	}

	function onChangeFPSCounter()
	{
		Main.updateFPSCounterVisibility();
	}

	function onChangeFPSStyle()
	{
		if (Main.fpsVar != null) Main.fpsVar.applySettings();
		Main.updateFPSLayer();
		refreshFPSStyleDependentOptions();
	}

	function onChangeFPSLayer()
	{
		Main.updateFPSLayer();
	}

	// 按当前 fpsStyle 返回跳转按钮的语言键
	private function getFPSStyleButtonLabelKey():String
	{
		return switch(ClientPrefs.data.fpsStyle)
		{
			case 'Simple': 'simple_fps_settings';
			case 'V-Slice': 'debug_fps_settings';
			case 'Kathy': 'kathy_fps_settings';
			default: 'psych_fps_settings';
		};
	}

	// 同步依赖 fpsStyle 的选项状态：按钮文案、exgameversion 可用性
	private function refreshFPSStyleDependentOptions():Void
	{
		var isPsych:Bool = (ClientPrefs.data.fpsStyle == 'Psych');
		var labelKey:String = getFPSStyleButtonLabelKey();
		if (fpsExgameversionOption != null)
		{
			fpsExgameversionOption.disabled = !isPsych;
			if (isPsych)
			{
				fpsExgameversionOption.altText = null;
				fpsExgameversionOption.disabledReason = null;
			}
			else
			{
				var reason:String = Language.get('requires_psych_style');
				fpsExgameversionOption.altText = Language.get('show_game_version_name') + ' (' + reason + ')';
				fpsExgameversionOption.disabledReason = reason;
			}
		}
		if (fpsSettingsButton != null)
		{
			fpsSettingsButton.name = Language.get(labelKey);
			fpsSettingsButton.disabled = isPsych;
			if (isPsych)
			{
				var reason:String = Language.get('fps_settings_not_configurable');
				fpsSettingsButton.altText = Language.get(labelKey) + ' (' + reason + ')';
				fpsSettingsButton.disabledReason = reason;
			}
			else
			{
				fpsSettingsButton.altText = null;
				fpsSettingsButton.disabledReason = null;
			}
		}
		refreshAllTexts();
	}

	/*#if native
	function onChangeVSync()
		lime.app.Application.current.window.vsync = ClientPrefs.data.vsync;
	#end*/
}
