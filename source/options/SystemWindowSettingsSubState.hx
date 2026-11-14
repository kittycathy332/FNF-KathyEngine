package options;

/**
 * 系统与窗口 —— 分类重组阶段 2 自动生成。
 * 选项来自：GameplaySettingsSubState.hx, ExtraGameplaySettingSubState.hx, CompatibilitySettingsSubState.hx, VisualsSettingsSubState.hx, MobileOptionsSubState.hx, GraphicsSettingsSubState.hx
 * 共 25 项；辅助函数按需从源文件带入。
 */
import states.PlayState;
import objects.KeyViewer;
import backend.MusicBeatState;
import flixel.text.FlxText;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.util.FlxTimer;
import backend.CustomFadeTransition;
import backend.ClientPrefs;
import states.MainMenuState;
import objects.Note;
import objects.StrumNote;
import objects.NoteSplash;
import objects.Alphabet;
import mobile.backend.MobileScaleMode;
import mobile.backend.HitboxImageImporter;
import mobile.objects.Hitbox;
import flixel.input.keyboard.FlxKey;
import options.BaseOptionsMenu;
import options.Option;
import backend.AssetErrorOverlay;
import backend.GifAssets;
import com.yagp.Gif;
import flixel.util.FlxColor;
import flixel.math.FlxPoint;

class SystemWindowSettingsSubState extends BaseOptionsMenu
{
	static final soundTrayOptions:Array<String> = ['Flixel', 'Funkin', 'Kathy', 'Dave'];
	// FPS 计数器联动（随选项从 HUD 页整体迁入）
	var fpsExgameversionOption:Option;
	var fpsSettingsButton:Option;
	var blueArchiveLanguageOption:Option = null;
	var blueArchiveLanguageOptionIndex:Int = -1;

	var healthOverflowOption:Option = null;
	var healthOverflowDrainOption:Option = null;
	var smoothHPSpeedOption:Option = null;
	var enableGameLogOption:Option = null;
	function onChangeAutoPause()
		FlxG.autoPause = ClientPrefs.data.autoPause;

	function onChangeVibration()
	{
		if(ClientPrefs.data.gameOverVibration)
			lime.ui.Haptic.vibrate(0, 500);
	}

	function onChangeWindowTitle()
	{
		ClientPrefs.data.windowTitle = ClientPrefs.data.windowTitlePreset;
		#if (!mobile && !html5)
		Main.updateWindowTitle();
		#end
	}

	function refreshGameLogDisabledState()
	{
		if (enableGameLogOption != null)
		{
			#if mobile
			enableGameLogOption.disabled = false;
			#else
			var shouldDisable:Bool = !ClientPrefs.data.enableConsoleLog;
			enableGameLogOption.disabled = shouldDisable;
			enableGameLogOption.requirement = OptionsLanguage.get('enable_game_log_requirement', '启用 控制台日志');
			if (shouldDisable && ClientPrefs.data.enableGameLog)
			{
				ClientPrefs.data.enableGameLog = false;
				if (Main.gameLogVar != null)
					Main.gameLogVar.setEnabled(false);
			}
			#end
		}
	}

	function refreshHealthOverflowState()
	{
	var smoothHPActive:Bool = ClientPrefs.data.smoothHP;
	var overflowActive:Bool = smoothHPActive && ClientPrefs.data.healthOverflow;
	if (healthOverflowOption != null)
	{
		healthOverflowOption.disabled = !smoothHPActive;
		healthOverflowOption.requirement = OptionsLanguage.get('health_overflow_requirement', '启用 丝滑血条');
		if (!smoothHPActive && ClientPrefs.data.healthOverflow)
			{
				// 丝滑血条关闭时强制关闭超满血，回到原生血量上限
				ClientPrefs.data.healthOverflow = false;
			}
		}
		if (healthOverflowDrainOption != null) {
			healthOverflowDrainOption.disabled = !overflowActive;
			healthOverflowDrainOption.requirement = OptionsLanguage.get('health_overflow_drain_requirement', '启用 丝滑血条 且 超满血');
		}
		if (smoothHPSpeedOption != null) {
			smoothHPSpeedOption.disabled = !ClientPrefs.data.smoothHP;
			smoothHPSpeedOption.requirement = OptionsLanguage.get('smooth_hp_speed_requirement', '启用 丝滑血条');
		}
	}

	override function update(elapsed:Float)
	{
		super.update(elapsed);
		if (blueArchiveLanguageOptionIndex != -1) {
			var isBlueArchiveActive:Bool = ClientPrefs.data.customFadeStyle == 'Blue Archive';
			optionsArray[blueArchiveLanguageOptionIndex].disabled = !isBlueArchiveActive;
			optionsArray[blueArchiveLanguageOptionIndex].requirement = OptionsLanguage.get('ba_language_requirement', '使用 Blue Archive 淡入风格');
		}
	}

	override public function onOptionsBuilt():Void
	{
		super.onOptionsBuilt();
		refreshFPSStyleDependentOptions();
		refreshGameLogDisabledState();
		refreshHealthOverflowState();
	}


	public function new()
	{
		title = Language.get('system_menu');
		rpcTitle = 'System & Window Menu';

		var option: Option;









		option = new Option(Language.get('developer_mode'),
			Language.get("developer_mode_desc"),
			'developer',
			BOOL);
		addOption(option);
		option = new Option(Language.get('engine_language'),
			Language.get("change_language_desc"),
			'language',
			STRING,
			["en_us", "zh_cn", "zh_tw"]);
		option.onChange = function() {
			ClientPrefs.saveSettings();
			Language.load();
			refreshAllTexts();
			
			// 由于父状态在运行,直接获取并刷新
			var parentState = cast(FlxG.state, OptionsState);
			if(parentState != null) {
				parentState.options = [
					Language.get("judgment"),
					Language.get("notes_visual"),
					Language.get("hud"),
					Language.get("audio"),
					Language.get("health_icons"),
					Language.get("graphics"),
					Language.get("mobile_options"),
					Language.get("system"),
					Language.get("compatibility"),
					Language.get("debug_display"),
					Language.get("tools")
				];
		
					parentState.optionDescriptions = [
					Language.get("judgment_desc"),
					Language.get("notes_visual_desc"),
					Language.get("hud_desc"),
					Language.get("audio_desc"),
					Language.get("health_icons_desc"),
					Language.get("graphics_desc"),
					Language.get("mobile_options_desc"),
					Language.get("system_desc"),
					Language.get("compatibility_desc"),
					Language.get("debug_display_desc"),
					Language.get("tools_desc")
				];
			
					parentState.refreshTexts();
			}
		};
		addOption(option);
		#if !mobile
		option = new Option(Language.get('use_system_cursor'),
			Language.get("use_system_cursor_desc"),
			'systemCursor',
			BOOL);
		option.onChange = function() {
			FlxG.mouse.useSystemCursor = ClientPrefs.data.systemCursor;
			ClientPrefs.saveSettings();
		};
		addOption(option);
		#end
		option = new Option(Language.get('startup_splash'),
			Language.get("startup_splash_desc"),
			'splashMode',
			STRING,
			['Kathy', 'Flixel', 'Flixel+', 'None']);
		addOption(option);



		refreshGameLogDisabledState();
		refreshHealthOverflowState();
		option = new Option(Language.get('loading_style'),
			Language.get("loading_style_desc"),
			'customFadeStyle',
			STRING,
			['None', 'V-Slice', 'NovaFlare Move', 'NovaFlare Alpha', 'Blue Archive', 'BA_Schale_Glow']);
		var loadingStyleOption = addOption(option);
		option = new Option(Language.get('blue_archive_language'),
			Language.get("ba_language_desc"),
			'blueArchiveLanguage',
			STRING,
			['CN', 'JP', 'KR', 'EN']);
		option.onChange = function() {
			// 当语言改变时，清空图片列表，下次加载时会重新从新语言的文件夹读取
			CustomFadeTransition.resetBlueArchiveImages();
		};
		blueArchiveLanguageOption = addOption(option);
		blueArchiveLanguageOptionIndex = optionsArray.length - 1;
		option = new Option(Language.get('sound_tray_style'),
			Language.get("sound_tray_style_desc"),
			'soundTrayStyle',
			STRING,
			soundTrayOptions);
		addOption(option);
		option = new Option(Language.get('auto_pause'),
			Language.get("autopause_desc"),
			'autoPause',
			BOOL);
		addOption(option);



		// Fake OS 版本
		#if CHECK_FOR_UPDATES
		option = new Option(Language.get('check_for_updates'),
			Language.get("checkforupdates_desc"),
			'checkForUpdates',
			BOOL);
		addOption(option);
		#end
		#if CHECK_FOR_UPDATES
		option = new Option(Language.get('receive_beta_builds'),
			Language.get("receivebetabuilds_desc"),
			'receiveBetaBuilds',
			BOOL);
		addOption(option);
		#end
		#if DISCORD_ALLOWED
	option = new Option(Language.get('discord_rich_presence'),
		Language.get("discordrpc_desc"),
		'discordRPC',
		BOOL);
	addOption(option);
		#end
	option = new Option(Language.get('disable_networking'),
		Language.get("disable_networking_desc"),
		'disableNetworking',
		BOOL);
	addOption(option);
		#if desktop
			option = new Option(Language.get('borderless_name'),
				Language.get('borderless_desc'),
				'borderless',
				BOOL);
			option.onChange = function()
			{
				backend.PseudoTitleBar.applySettings();
			};
			addOption(option);



			// 图形设置选项
		#end
		option = new Option(Language.get('use_custom_window_title'),
			Language.get("use_custom_window_title_desc"),
			'useCustomWindowTitle',
			BOOL);
		option.onChange = function()
		{
			Main.updateWindowTitle(true);
		};
		addOption(option);


		option.onChange = onChangeAutoPause;
		option = new Option(Language.get('fake_window_title'),
			Language.get("fake_window_title_desc"),
			'windowTitlePreset',
			STRING,
			["Kathy Engine", "Psych Engine: MintRhythm Extended", "Friday Night Funkin': Psych Engine", "Friday Night Funkin': OS Engine", "Friday Night Funkin'", "FNF", "WTF in FNF", "Rhythm Game", "Not FNF", "Just a Game"]);
		option.onChange = onChangeWindowTitle;
		addOption(option);
		#if !mobile
		option = new Option(Language.get('dynamic_window_title'),
			Language.get('wintitle_dynamic'),
			'dynamicWindowTitle',
			BOOL);
		option.onChange = function() { Main.updateWindowTitle(); };
		addOption(option);
		#end
		#if !mobile
		option = new Option(Language.get('show_current_screen'),
			Language.get('wintitle_state'),
			'windowTitleShowState',
			BOOL);
		option.onChange = function() { Main.updateWindowTitle(); };
		addOption(option);
		#end
		#if !mobile
		option = new Option(Language.get('show_current_mod'),
			Language.get('wintitle_mod'),
			'windowTitleShowMod',
			BOOL);
		option.onChange = function() { Main.updateWindowTitle(); };
		addOption(option);
		#end
		#if !mobile
		option = new Option(Language.get('show_current_song'),
			Language.get('wintitle_song'),
			'windowTitleShowSong',
			BOOL);
		option.onChange = function() { Main.updateWindowTitle(); };
		addOption(option);
		#end
		#if !mobile
		option = new Option(Language.get('show_song_difficulty'),
			Language.get('wintitle_difficulty'),
			'windowTitleShowDifficulty',
			BOOL);
		option.onChange = function() { Main.updateWindowTitle(); };
		addOption(option);




		// 伪窗口标题预设
		#end
			option = new Option(Language.get('chart_editor_theme'),
				Language.get("chart_editor_theme_desc"),
				'chartEditorTheme',
				STRING,
				['Default', 'Light', 'Dark']);
			addOption(option);



			// 飞溅数量限制设置

		// 分类重组搬迁时遗漏、从备份补回的选项
			option = new Option(Language.get('asset_error_overlay'),
				Language.get("asset_error_overlay_desc"),
				'assetErrorOverlay',
				BOOL);
			option.onChange = function()
			{
				// 即时生效：清掉占位图缓存，后续对缺失资源的请求按新开关立即重建。
				AssetErrorOverlay.clearCache();
			}
			addOption(option);
		option = new Option(Language.get('fps_counter'),
			Language.get("showfps_desc"),
			'showFPS',
			BOOL);
		addOption(option);


		option.onChange = onChangeFPSCounter;
		option = new Option(Language.get('fps_counter_style'),
			Language.get("fps_counter_style_desc"),
			'fpsStyle',
			STRING,
			['Psych', 'Kathy', 'Simple', 'V-Slice']);
		addOption(option);


		option.onChange = onChangeFPSStyle;
		option = new Option(Language.get('fps_counter_layer'),
			Language.get("fps_counter_layer_desc"),
			'fpsLayer',
			STRING,
			['Stage', 'Game']);
		addOption(option);


		option.onChange = onChangeFPSLayer;
		option = new Option(Language.get('fps_counter_font'),
			Language.get("fpstxt_style_desc"),
			'fpsFont',
			STRING,
			['default', 'Kade']);
		option.onChange = function() {
			if (Main.fpsVar != null) Main.fpsVar.applySettings();
		};
		addOption(option);
		option = new Option(Language.get('show_game_version_name'),
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

		// 分类重组搬迁时遗漏、从备份补回的选项











		super();
	}

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

	function onChangeFPSCounter()
	{
		Main.updateFPSCounterVisibility();
	}

	function onChangeFPSLayer()
	{
		Main.updateFPSLayer();
	}

	function onChangeFPSStyle()
	{
		if (Main.fpsVar != null) Main.fpsVar.applySettings();
		Main.updateFPSLayer();
		refreshFPSStyleDependentOptions();
	}

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
}
