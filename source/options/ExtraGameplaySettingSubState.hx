package options;

import flixel.text.FlxText;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.util.FlxTimer;
import backend.CustomFadeTransition;

class ExtraGameplaySettingSubState extends BaseOptionsMenu
{
	var errorText:FlxText = null;
	var errorBg:FlxSprite = null;
	var errorTimer:FlxTimer = null;
	
	var blueArchiveLanguageOption:Option = null;
	var blueArchiveLanguageOptionIndex:Int = -1;
	
	var ratingBounceOption:Option = null;
	var ratingBounceOptionIndex:Int = -1;
	var extraRatingBounceOption:Option = null;
	var extraRatingBounceOptionIndex:Int = -1;
	var ratingFallStyleOption:Option = null;
	var ratingFallStyleOptionIndex:Int = -1;
	var ratingFallStyleDescBase:String = '';
	var camelliaScaleOption:Option = null;
	var camelliaScaleOptionIndex:Int = -1;

	var healthOverflowOption:Option = null;
	var healthOverflowOptionIndex:Int = -1;

	var healthOverflowDrainOption:Option = null;
	var healthOverflowDrainOptionIndex:Int = -1;

	var smoothHPSpeedOption:Option = null;
	var smoothHPSpeedOptionIndex:Int = -1;

	var biggerInfoTextOption:Option = null;
	var biggerInfoTextOptionIndex:Int = -1;
	var timebarStyleOption:Option = null;
	var timebarStyleOptionIndex:Int = -1;

	var enableGameLogOption:Option = null;
	var enableConsoleLogOption:Option = null;

	public function new()
	{
		title = Language.get('extra_menu_title');
		rpcTitle = 'Extra Gameplay Settings Menu'; //for Discord Rich Presence

		// BOOL 类型设置

		// 开发者模式（放在最顶部）：启用后可进入编辑器菜单，legacy 主界面显示 toolbox 入口
		var option:Option = new Option(Language.get('developer_mode'),
			Language.get("developer_mode_desc"),
			'developer',
			BOOL);
		addOption(option);

		option = new Option(Language.get('show_extra_rating'),
			Language.get("show_exrating_desc"),
			'exratingDisplay',
			BOOL);
		addOption(option);

		option = new Option(Language.get('rating_bounce'),
			Language.get("rating_bounce_desc"),
			'ratbounce',
			BOOL);
		ratingBounceOption = addOption(option);
		ratingBounceOptionIndex = optionsArray.length - 1;

		option = new Option(Language.get('extra_rating_bounce'),
			Language.get("exrating_bounce_desc"),
			'exratbounce',
			BOOL);
		extraRatingBounceOption = addOption(option);
		extraRatingBounceOptionIndex = optionsArray.length - 1;

		option = new Option(Language.get('perfect_judgement_mode'),
			Language.get("rm_perfect_judge_desc"),
			'rmPerfect',
			STRING,
			['enable', 'remove', 'sickPlus']);
		addOption(option);

		option = new Option(Language.get('remove_the_ms_offset'),
			Language.get("rm_ms_offset_desc"),
			'rmmsTimeTxt',
			BOOL);
		addOption(option);

		option = new Option(Language.get('show_mode_label_in_ms_text'),
			Language.get("show_mode_label_ms_desc"),
			'showModeLabelInMsTxt',
			BOOL);
		addOption(option);

		option = new Option(Language.get('ms_timing_style'),
			Language.get("ms_timing_style_desc"),
			'msTimingStyle',
			STRING,
			['Kathy', 'Kade']);
		addOption(option);

		option = new Option(Language.get('ms_timing_offset_mode'),
			Language.get("ms_timing_offset_mode_desc"),
			'msTimingOffsetMode',
			STRING,
			['independent', 'numScore']);
		addOption(option);

		option = new Option(Language.get('show_nps'),
			Language.get("nps_desc"),
			'showNPS',
			BOOL);
		addOption(option);

		option = new Option(Language.get('keep_sing_animation'),
			Language.get("keep_sing_animation_desc"),
			'keepSingAnimation',
			BOOL);
		addOption(option);

		option = new Option(Language.get('ghost_effect_multi_press'),
			Language.get("ghost_effect_desc"),
			'ghostEffect',
			BOOL);
		addOption(option);

		option = new Option(Language.get('scoretxt_bounce'),
			Language.get("scoretxt_bounce_desc"),
			'scoretxtbounce',
			BOOL);
		addOption(option);

		option = new Option(Language.get('single_note_splash_anim'),
			Language.get("single_splashanim_desc"),
			'forceSingleSplashAnim',
			BOOL);
		addOption(option);

		var smoothHPOption:Option = new Option(Language.get('smooth_hp_bar'),
			Language.get("smooth_hpbar_desc"),
			'smoothHP',
			BOOL);
		smoothHPOption.onChange = refreshHealthOverflowState;
		addOption(smoothHPOption);

		option = new Option(Language.get('health_overflow_icons'),
			Language.get("health_overflow_desc"),
			'healthOverflow',
			BOOL);
		healthOverflowOption = addOption(option);
		healthOverflowOptionIndex = optionsArray.length - 1;
		healthOverflowOption.onChange = refreshHealthOverflowState;

		option = new Option(Language.get('overflow_return_speed'),
			Language.get("health_overflow_drain_desc"),
			'healthOverflowDrain',
			FLOAT);
		option.displayFormat = '%v';
		option.scrollSpeed = 2;
		option.minValue = 2;
		option.maxValue = 50;
		option.changeValue = 0.5;
		option.decimals = 1;
		healthOverflowDrainOption = addOption(option);
		healthOverflowDrainOptionIndex = optionsArray.length - 1;

		option = new Option(Language.get('smooth_hp_speed'),
			Language.get("smooth_hp_speed_desc"),
			'smoothHPSpeed',
			FLOAT);
		option.displayFormat = '%v';
		option.scrollSpeed = 2;
		option.minValue = 1;
		option.maxValue = 30;
		option.changeValue = 1;
		option.decimals = 1;
		smoothHPSpeedOption = addOption(option);
		smoothHPSpeedOptionIndex = optionsArray.length - 1;

		option = new Option(Language.get('cpu_strums'),
			Language.get("cpu_strums_desc"),
			'cpuStrums',
			BOOL);
		addOption(option);

		option = new Option(Language.get('score_incrase_when_botplay'),
			Language.get("bot_addscore_desc"),
			'botplayScore',
			BOOL);
		addOption(option);

		option = new Option(Language.get('botplay_perfect_timing'),
			Language.get("botplay_perfect_timing_desc"),
			'botplayPerfectTiming',
			BOOL);
		addOption(option);

		option = new Option(Language.get('show_combo_sprite'),
			Language.get("gameplay_combospr_desc"),
			'comboSprDisplay',
			BOOL);
		addOption(option);

		option = new Option(Language.get('combo_number_display'),
			Language.get("combo_num_display_desc"),
			'comboNumDisplay',
			STRING,
			['Psych', 'Default', 'OG Funkin']);
		addOption(option);

		option = new Option(Language.get('rating_fall_style'),
			Language.get("rating_fall_style_desc"),
			'ratingFallStyle',
			STRING,
			['Leather', 'Legacy', 'Kathy', 'Kathy(Legacy)', 'Camellia']);
		option.onChange = function() {
			updateBounceOptionsVisibility();
			updateCamelliaScaleVisibility();
		};
		ratingFallStyleOption = addOption(option);
		ratingFallStyleOptionIndex = optionsArray.length - 1;
		ratingFallStyleDescBase = ratingFallStyleOption.description;

		option = new Option(Language.get('camellia_scale_mode'),
			Language.get("camellia_scale_mode_desc"),
			'camelliaScaleMode',
			STRING,
			['Proportional', 'Original']);
		camelliaScaleOption = addOption(option);
		camelliaScaleOptionIndex = optionsArray.length - 1;

		option = new Option(Language.get('show_event_information'),
			Language.get("events_debug_desc"),
			'eventDebug',
			BOOL);
		addOption(option);

		option = new Option(Language.get('background_volume'),
			Language.get("bgvol_desc"),
			'backgroundVolume',
			BOOL);
		addOption(option);

		option = new Option(Language.get('fixed_timestep'),
			Language.get("fixed_timestep_desc"),
			'fixedTimestep',
			BOOL);
		addOption(option);
		option.onChange = function() {
			FlxG.fixedTimestep = ClientPrefs.data.fixedTimestep;
			trace("Fixed timestep changed to: " + FlxG.fixedTimestep);
		};

		// ===== 渲染质量（StageQuality） =====
		option = new Option(Language.get('stage_quality'),
			Language.get("stage_quality_desc"),
			'stageQuality',
			STRING,
			['LOW', 'MEDIUM', 'HIGH', 'BEST']);
		option.onChange = function() {
			FlxG.stage.quality = ClientPrefs.getStageQuality();
		};
		addOption(option);

		// ===== 低延迟 / 性能模式 =====
		option = new Option(Language.get('auto_song_resync'),
			Language.get("auto_song_resync_desc"),
			'autoResync',
			BOOL);
		addOption(option);

		option = new Option(Language.get('frame_adaptive_sync'),
			Language.get("frame_adaptive_sync_desc"),
			'useFrameAdaptiveSync',
			BOOL);
		addOption(option);

		option = new Option(Language.get('sync_speed_multiplier'),
			Language.get("sync_speed_multiplier_desc"),
			'syncSpeedMultiplier',
			FLOAT);
		option.displayFormat = '%v X';
		option.scrollSpeed = 2;
		option.minValue = 0.1;
		option.maxValue = 10;
		option.changeValue = 0.1;
		option.decimals = 1;
		addOption(option);

		option = new Option(Language.get('background_volume_level'),
			Language.get("bgvol_level_desc"),
			'backgroundVolumeLevel',
			PERCENT);
		option.scrollSpeed = 2;
		option.minValue = 0;
		option.maxValue = 1;
		option.changeValue = 0.02;
		option.decimals = 2;
		addOption(option);

		option = new Option(Language.get('rating_counter'),
			Language.get("ratcounter_desc"),
			'ratCounter',
			BOOL);
		addOption(option);

		option = new Option(Language.get('rating_counter_animation'),
			Language.get("ratcounter_anim_desc"),
			'ratCounterAnimation',
			BOOL);
		addOption(option);

		option = new Option(Language.get('show_watermark'),
			Language.get("watermark_desc"),
			'waterMarkPlay',
			BOOL);
		addOption(option);

		option = new Option(Language.get('watermark_type'),
			Language.get("watermark_type_desc"),
			'watermarkType',
			STRING,
			['Kathy', 'OS', 'Psych', 'Kade']);
		addOption(option);

		option = new Option(Language.get('enable_game_log_display'),
			Language.get("enable_game_log_desc"),
			'enableGameLog',
			BOOL);
		option.onChange = function() {
			if(Main.gameLogVar != null) {
				Main.gameLogVar.setEnabled(ClientPrefs.data.enableGameLog);
			}
		};
		enableGameLogOption = addOption(option);

		#if !mobile
		option = new Option(Language.get('enable_console_log_output'),
			Language.get("enable_console_log_desc"),
			'enableConsoleLog',
			BOOL);
		option.onChange = function() {
			refreshGameLogDisabledState();
		};
		enableConsoleLogOption = addOption(option);
		#end

		option = new Option(Language.get('garbage_collector_name'),
			Language.get("garbage_collector_desc"),
			'garbageCollectorEnabled',
			BOOL);
		option.onChange = function() {
			// 变更后立即生效
			Main.applyGarbageCollectorSetting();
		};
		addOption(option);

	// PERCENT 类型设置
		option = new Option(Language.get('ratings_opacity'),
			Language.get("rating_opac_desc"),
			'ratingsAlpha',
			PERCENT);
		option.scrollSpeed = 1.6;
		option.minValue = 0.0;
		option.maxValue = 1;
		option.changeValue = 0.1;
		option.decimals = 1;
		addOption(option);

		// STRING 类型设置
		option = new Option(Language.get('healthbar_style'),
			Language.get("healthbar_style_desc"),
			'healthbarstyle',
			STRING,
			['Psych', 'OS', 'Kade', 'Leather']);
		addOption(option);
		
		option = new Option(Language.get('time_bar_stripes'),
			Language.get("time_bar_stripes_desc"),
			'timeBarStripes',
			BOOL);
		addOption(option);

		option = new Option(Language.get('time_bar_gradient'),
			Language.get("time_bar_gradient_desc"),
			'timeBarGradient',
			BOOL);
		addOption(option);

		option = new Option(Language.get('iconbop_style'),
			Language.get("iconbop_style_desc"),
			'iconbopstyle',
			STRING,
			['Psych', 'Psych (Legacy)', 'OS', 'Kathy', 'Leather', 'SB', 'Vanilla', 'VSlice(New)', 'VSlice(Old)', 'Codename', 'Dave', 'Squash', 'GoldenApple', 'GoldenApple (Lerp)', 'NovaFlare', 'Forever', 'NONE']);
		addOption(option);

		option = new Option(Language.get('iconbop_normalize'),
			Language.get("iconbop_normalize_desc"),
			'iconbopNormalize',
			BOOL);
		addOption(option);

		option = new Option(Language.get('scoretxt_style'),
			Language.get("scoretxt_style_desc"),
			'scoretxtstyle',
			STRING,
			['Psych', 'Psych (Old)', 'OS', 'Kathy', 'Kade', 'V-Slice', 'Leather', 'Forever']);
		addOption(option);

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

		option = new Option(Language.get('timebar_style'),
			Language.get("timebar_style_desc"),
			'timebarStyle',
			STRING,
			['Psych', 'Kade', 'Leather', 'Leather (Legacy)']);
		option.onChange = function() {
			updateBiggerInfoTextVisibility();
		};
		timebarStyleOption = addOption(option);
		timebarStyleOptionIndex = optionsArray.length - 1;

		option = new Option(Language.get('bigger_info_text'), Language.get("bigger_info_text_desc"), 'biggerInfoText', BOOL);
		biggerInfoTextOption = addOption(option);
		biggerInfoTextOptionIndex = optionsArray.length - 1;

		option = new Option(Language.get('botplaytxt_style'),
			Language.get("botplaytxt_style_desc"),
			'botplayStyle',
			STRING,
			['Kade', 'Psych']);
		addOption(option);

		option = new Option(Language.get('showcase_style'),
			Language.get("showcase_style_desc"),
			'showcaseStyle',
			STRING,
			['Kade', 'Psych']);
		addOption(option);

		/*
		// 修复 FPS 字体选项
		option = new Option(Language.get('fps_counter_font'),
			Language.get("fpstxt_style_desc"),
			'fpsFont',
			STRING,
			['default', 'Kade']);
		option.onChange = function() {
			if (Main.fpsVar != null) {
				Main.fpsVar.updateFont(); // 调用字体更新方法
				Main.fpsVar.positionFPS(10, 3); // 重新定位确保布局正确
			}
		};
		addOption(option);*/

		option = new Option(Language.get('ratings_position'),
			Language.get("ratings_pos_desc"),
			'ratingsPos',
			STRING,
			['camHUD', 'camGame']);
		addOption(option);

		option = new Option(Language.get('hud_zoom_speed'),
			Language.get("hud_zoomstyle_desc"),
			'hudZoomStyle',
			STRING,
			['default', 'Fast', 'Slow', 'Kade']);
		addOption(option);

		option = new Option(Language.get('hud_zoom'),
			Language.get("camhud_zoom_desc"),
			'hudSize',
			FLOAT);
		option.displayFormat = '%v X';
		option.scrollSpeed = 1;
		option.minValue = 0.5;
		option.maxValue = 1.2;
		option.changeValue = 0.005;
		option.decimals = 3; //小数点后三位
		addOption(option);

		// 语言设置放在最后
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
					Language.get("note_colors"),
					Language.get("controls"),
					Language.get("adjust_delay_combo"),
					Language.get("adjust_rating_offset"),
					Language.get("graphics"),
					Language.get("visuals"), 
					Language.get("gameplay"),
					#if cpp
					#if windows
					#if !mobile
					Language.get("window_manager"),
					#end
					#end
					#end
					Language.get("extra_options")
					, Language.get("spam_chart")
					, Language.get("compatibility")
					#if mobile , Language.get("mobile_options") #end
					];
		
					parentState.optionDescriptions = [
					Language.get("note_colors_desc"),
					Language.get("controls_desc"),
					Language.get("adjust_delay_combo_desc"),
					Language.get("adjust_rating_offset_desc"),
					Language.get("graphics_desc"),
					Language.get("visuals_desc"),
					Language.get("gameplay_desc"),
					#if cpp
					#if windows
					#if !mobile
					Language.get("window_manager_desc"),
					#end
					#end
					#end
					Language.get("extra_options_desc")
					, Language.get("spam_chart_desc")
					, Language.get("compatibility_desc")
					#if mobile , Language.get("mobile_options_desc") #end
					];
			
					parentState.refreshTexts();
			}
		};
		addOption(option);

		#if !mobile
		option = new Option(Language.get('mods_import'),
			Language.get("mods_import_desc"),
			'enableModsImport',
			BOOL);
		addOption(option);
		#end

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

		super();
	}

	function showError(msg:String)
	{
		if (errorText == null) {
			errorText = new FlxText(0, 0, 400, "", 24);
			errorText.setFormat(Language.get("game_font"), 24, 0xFFFFFFFF, "center");
			errorText.scrollFactor.set();
			errorText.borderStyle = FlxTextBorderStyle.OUTLINE;
			errorText.borderColor = 0xFF000000;
			errorText.alpha = 1;
			errorText.cameras = [FlxG.cameras.list[FlxG.cameras.list.length-1]];
			errorBg = new FlxSprite().makeGraphic(420, 40, 0xFFFF4444);
			errorBg.alpha = 0.85;
			errorBg.scrollFactor.set();
			errorBg.cameras = errorText.cameras;
			add(errorBg);
			add(errorText);
		}
		errorText.text = Language.get("error_title") + ": " + msg;
		errorText.x = FlxG.width - errorText.width - 30;
		errorText.y = 30;
		errorBg.x = errorText.x - 10;
		errorBg.y = errorText.y - 5;
		errorBg.visible = errorText.visible = true;
		if (errorTimer != null) errorTimer.cancel();
		errorTimer = new FlxTimer().start(1.5, function(_) {
			if (errorText != null) errorText.visible = false;
			if (errorBg != null) errorBg.visible = false;
		});
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

	override function changeSelection(change:Int = 0, skipRefresh:Bool = false, skipDesc:Bool = false)
	{
		// 不再跳过禁用项：禁用项仍可选中（父类会阻止其被修改），
		// 选中后描述框会显示 "[需要: ...]" 前提条件，列表里也会行内标注。
		super.changeSelection(change, skipRefresh, skipDesc);
	}
	
	function onChangeAutoPause()
		FlxG.autoPause = ClientPrefs.data.autoPause;

	override function update(elapsed:Float)
	{
		super.update(elapsed);
		
		updateBounceOptionsVisibility();
		updateCamelliaScaleVisibility();
		updateBiggerInfoTextVisibility();
		updateRatingFallStyleNote();
		
		// 控制 Blue Archive Language 选项的可见性和禁用状态
		if (blueArchiveLanguageOptionIndex != -1) {
			var isBlueArchiveActive:Bool = ClientPrefs.data.customFadeStyle == 'Blue Archive';
			optionsArray[blueArchiveLanguageOptionIndex].disabled = !isBlueArchiveActive;
			optionsArray[blueArchiveLanguageOptionIndex].requirement = OptionsLanguage.get('ba_language_requirement', '使用 Blue Archive 淡入风格');
		}
	}
	
	function updateBounceOptionsVisibility()
	{
		var isKathyStyle:Bool = ClientPrefs.data.ratingFallStyle == 'Kathy' || ClientPrefs.data.ratingFallStyle == 'Kathy(Legacy)';

		if (ratingBounceOptionIndex != -1) {
			optionsArray[ratingBounceOptionIndex].disabled = !isKathyStyle;
			optionsArray[ratingBounceOptionIndex].requirement = OptionsLanguage.get('rating_bounce_requirement', '使用 Kathy 评价下落风格');
		}

		if (extraRatingBounceOptionIndex != -1) {
			// 额外评价回弹不仅要求 Kathy 风格，还要求已开启“显示额外评价”（见 PlayState.hx:5126）
			var exratingOn:Bool = ClientPrefs.data.exratingDisplay;
			optionsArray[extraRatingBounceOptionIndex].disabled = !isKathyStyle || !exratingOn;
			if (!isKathyStyle)
				optionsArray[extraRatingBounceOptionIndex].requirement = OptionsLanguage.get('rating_bounce_requirement', '使用 Kathy 评价下落风格');
			else
				optionsArray[extraRatingBounceOptionIndex].requirement = OptionsLanguage.get('exrating_bounce_requirement', '启用 显示额外评价');
		}
	}

	// Camellia Scale Mode 仅在 Camellia 风格下可用，其它风格变灰
	function updateCamelliaScaleVisibility()
	{
		if (camelliaScaleOptionIndex == -1) return;

		var isCamellia:Bool = ClientPrefs.data.ratingFallStyle == 'Camellia';
		optionsArray[camelliaScaleOptionIndex].disabled = !isCamellia;
		optionsArray[camelliaScaleOptionIndex].requirement = OptionsLanguage.get('camellia_scale_mode_requirement', '使用 Camellia 评价下落风格');
	}

	function updateBiggerInfoTextVisibility()
	{
		var isLeatherStyle:Bool = ClientPrefs.data.timebarStyle == 'Leather' || ClientPrefs.data.timebarStyle == 'Leather (Legacy)';

		if (biggerInfoTextOptionIndex != -1) {
			optionsArray[biggerInfoTextOptionIndex].disabled = !isLeatherStyle;
			optionsArray[biggerInfoTextOptionIndex].requirement = OptionsLanguage.get('bigger_info_text_requirement', '使用 Leather 时间轴风格');
		}
	}

	// Rating Fall Style 中 Leather/Legacy/Kathy 仅在「Combo Stacking」关闭时生效（Camellia 始终生效）。
	// 当 Combo Stacking 开启时，给描述追加提示，指明该隐藏前提。
	function updateRatingFallStyleNote()
	{
		if (ratingFallStyleOption == null) return;
		var note:String = OptionsLanguage.get('rating_fall_style_combostacking_note',
			'（仅 Leather 样式依赖禁用 Combo Stacking：开启时 Leather 会回退为默认上跳表现、失去下落特效；Legacy 表现不变，Camellia 始终生效）');
		ratingFallStyleOption.description = ClientPrefs.data.comboStacking
			? ratingFallStyleDescBase + '\n' + note
			: ratingFallStyleDescBase;
	}
}