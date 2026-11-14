package options;

/**
 * HUD 与界面 —— 分类重组阶段 2 自动生成。
 * 选项来自：GameplaySettingsSubState.hx, ExtraGameplaySettingSubState.hx, CompatibilitySettingsSubState.hx, VisualsSettingsSubState.hx, GraphicsSettingsSubState.hx
 * 共 55 项；辅助函数按需从源文件带入。
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
import backend.AssetErrorOverlay;
import backend.GifAssets;
import com.yagp.Gif;
import flixel.util.FlxColor;
import flixel.math.FlxPoint;

class HudSettingsSubState extends BaseOptionsMenu
{
	var ratingBounceOption:Option = null;
	var ratingBounceOptionIndex:Int = -1;
	var extraRatingBounceOption:Option = null;
	var extraRatingBounceOptionIndex:Int = -1;
	var ratingFallStyleOption:Option = null;
	var ratingFallStyleOptionIndex:Int = -1;
	var ratingFallStyleDescBase:String = '';
	var camelliaScaleOption:Option = null;
	var camelliaScaleOptionIndex:Int = -1;
	var biggerInfoTextOption:Option = null;
	var biggerInfoTextOptionIndex:Int = -1;
	var timebarStyleOption:Option = null;
	var timebarStyleOptionIndex:Int = -1;
	var notes:FlxTypedGroup<StrumNote>;
	var splashes:FlxTypedGroup<NoteSplash>;
	var noteSkinList:Array<String> = [];
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

	function onChangeArrowColorMode()
	{
		Note.globalRgbShaders = [];
		Note.globalColorSwapShaders = [];
		if (notes == null || splashes == null) return;

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

	function updateBiggerInfoTextVisibility()
	{
		var isLeatherStyle:Bool = ClientPrefs.data.timebarStyle == 'Leather' || ClientPrefs.data.timebarStyle == 'Leather (Legacy)';

		if (biggerInfoTextOptionIndex != -1) {
			optionsArray[biggerInfoTextOptionIndex].disabled = !isLeatherStyle;
			optionsArray[biggerInfoTextOptionIndex].requirement = OptionsLanguage.get('bigger_info_text_requirement', '使用 Leather 时间轴风格');
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

	function updateCamelliaScaleVisibility()
	{
		if (camelliaScaleOptionIndex == -1) return;

		var isCamellia:Bool = ClientPrefs.data.ratingFallStyle == 'Camellia';
		optionsArray[camelliaScaleOptionIndex].disabled = !isCamellia;
		optionsArray[camelliaScaleOptionIndex].requirement = OptionsLanguage.get('camellia_scale_mode_requirement', '使用 Camellia 评价下落风格');
	}

		function updateRatingFallStyleNote()
		{
			if (ratingFallStyleOption == null) return;
			var note:String = OptionsLanguage.get('rating_fall_style_combostacking_note',
				'（仅 Leather 样式依赖禁用 Combo Stacking：开启时 Leather 会回退为默认上跳表现、失去下落特效；Legacy 表现不变，Camellia 始终生效）');
			ratingFallStyleOption.description = ClientPrefs.data.comboStacking
				? ratingFallStyleDescBase + '\n' + note
				: ratingFallStyleDescBase;
		}

	override public function onOptionsBuilt():Void
	{
		super.onOptionsBuilt();
		updateBounceOptionsVisibility();
		updateCamelliaScaleVisibility();
		updateBiggerInfoTextVisibility();
		updateRatingFallStyleNote();
	}

	override function update(elapsed:Float)
	{
		super.update(elapsed);
		updateBounceOptionsVisibility();
		updateCamelliaScaleVisibility();
		updateBiggerInfoTextVisibility();
		updateRatingFallStyleNote();
	}


	public function new()
	{
		title = Language.get('hud_menu');
		rpcTitle = 'HUD & Interface Menu';

		var biggerInfoTextOption:Option = null;
		var biggerInfoTextOptionIndex:Int = -1;
		var camelliaScaleOption:Option = null;
		var camelliaScaleOptionIndex:Int = -1;
		var extraRatingBounceOption:Option = null;
		var extraRatingBounceOptionIndex:Int = -1;
		var kadeHoldVisualOption: Option;
		var noteSkinList:Array<String> = [];
		var option: Option;
		var ratingFallStyleDescBase:String = '';
		var ratingFallStyleOption:Option = null;
		var ratingFallStyleOptionIndex:Int = -1;
		var timebarStyleOption:Option = null;
		var timebarStyleOptionIndex:Int = -1;









		option = new Option(Language.get('pop_up_score'),
			Language.get("popupscore_desc"),
			'popUpRating',
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
			option = new Option(Language.get('combo_stacking'),
			Language.get("combostacking_desc"),
			'comboStacking',
			BOOL);
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
		option = new Option(Language.get('fallback_ex_perfect_to_sick'),
			Language.get("fallback_experfect_to_sick_desc"),
			'fallbackEXPerfectToSick',
			BOOL);
		addOption(option);
		option = new Option(Language.get('fallback_perfect_to_sick'),
			Language.get("fallback_perfect_to_sick_desc"),
			'fallbackPerfectToSick',
			BOOL);
		addOption(option);



		// 额外 Perfect 评级精灵回退至 Sick
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
		option = new Option(Language.get('ratings_position'),
			Language.get("ratings_pos_desc"),
			'ratingsPos',
			STRING,
			['camHUD', 'camGame']);
		addOption(option);
		option = new Option(Language.get('key_viewer'),
			Language.get("keyviewer_desc"),
			'keyViewer',
			BOOL);
		addOption(option);
		option = new Option(Language.get('key_viewer_profile'),
			Language.get("keyviewer_profile_desc"),
			'keyViewerProfile',
			BOOL);
		addOption(option);
		option = new Option(Language.get('key_viewer_position'),
			Language.get("keyviewer_pos_desc"),
			'_keyViewerPos',
			BUTTON);
		addOption(option);


		option.onChange = function() {
			MusicBeatState.switchState(new KeyViewerPosState());
		};
		option = new Option(Language.get('reset_key_viewer_total'),
			Language.get("keyviewer_reset_total_desc"),
			'_keyViewerResetTotal',
			BUTTON);
		addOption(option);


		option.onChange = function() {
			KeyViewer.keyViewerTotal = 0;
			KeyViewer.saveKeyViewerTotal();
		};
		option = new Option(Language.get('key_viewer_trail'),
			Language.get("keyviewer_trail_desc"),
			'keyViewerTrail',
			STRING,
			['off', 'auto', 'up', 'down']);
		addOption(option);
		option = new Option(Language.get('key_viewer_trail_speed'),
			Language.get("keyviewer_trail_speed_desc"),
			'keyViewerTrailSpeed',
			FLOAT);
		option.scrollSpeed = 10;
		option.minValue = 100;
		option.maxValue = 1000;
		option.changeValue = 10;
		option.decimals = 0;
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
		option = new Option(Language.get('show_key_preview'),
			Language.get("show_key_preview_desc"),
			'showKeyPreview',
			BOOL);
		addOption(option);



		// 键位预览样式（EK KeybindShowcase / LE extraKeyReminders）
		option = new Option(Language.get('key_preview_style'),
			Language.get("key_preview_style_desc"),
			'keyPreviewStyle',
			STRING, ['ek', 'le']);
		option.valueLocalizations = ['ek' => Language.get('key_preview_style_ek'), 'le' => Language.get('key_preview_style_le')];
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
		option = new Option(Language.get('scoretxt_style'),
			Language.get("scoretxt_style_desc"),
			'scoretxtstyle',
			STRING,
			['Psych', 'Psych (Old)', 'OS', 'Kathy', 'Kade', 'V-Slice', 'Leather', 'Forever']);
		addOption(option);

		// noteSkins 准备逻辑与 noteSkin 选项已随分类重组迁到「音符与轨道视觉」，此处不再保留
		option = new Option(Language.get('hide_hud'),
			Language.get("hidehud_desc"),
			'hideHud',
			BOOL);
		addOption(option);
		option = new Option(Language.get('note_timer'),
			Language.get("note_timer_desc"),
			'noteTimerEnabled',
			BOOL);
		addOption(option);
		option = new Option(Language.get('note_timer_layer'),
			Language.get("note_timer_layer_desc"),
			'noteTimerLayer',
			STRING,
			['Above Notes', 'Below Notes']);
		option.valueLocalizations = [
			'Above Notes' => Language.get('note_timer_layer_above'),
			'Below Notes' => Language.get('note_timer_layer_below')
		];
		addOption(option);
		option = new Option(Language.get('note_timer_display'),
			Language.get("note_timer_display_desc"),
			'noteTimerDisplay',
			STRING,
			['Seconds', 'Beats']);
		option.valueLocalizations = [
			'Seconds' => Language.get('note_timer_display_seconds'),
			'Beats'   => Language.get('note_timer_display_beats')
		];
		addOption(option);
		option = new Option(Language.get('note_timer_stepped'),
			Language.get("note_timer_stepped_desc"),
			'noteTimerStepped',
			BOOL);
		addOption(option);
		option = new Option(Language.get('time_bar'),
			Language.get("timebar_desc"),
			'timeBarType',
			STRING,
			['Time Left', 'Time Elapsed', 'Song Name', 'Disabled']);
		addOption(option);
		option = new Option(Language.get('score_text_grow_on_hit'),
			Language.get("scoretextgrow_desc"),
			'scoreZoom',
			BOOL);
		addOption(option);
		option = new Option(Language.get('scoretext_language'),
			Language.get("scoretextlanguage_desc"),
			'scoreLanguage',
			STRING,
			['auto', 'en_us', 'zh_cn', 'zh_tw', 'ja', 'ko', 'kc_cn']);
		addOption(option);
		option = new Option(Language.get('show_nps'),
			Language.get("nps_desc"),
			'showNPS',
			BOOL);
		addOption(option);
		option = new Option(Language.get('scoretxt_bounce'),
			Language.get("scoretxt_bounce_desc"),
			'scoretxtbounce',
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
		option = new Option(Language.get('beat_scale'),
			Language.get("beat_scale_desc"),
			'beatScale',
			BOOL);
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
		option = new Option(Language.get('legacy_note_position'),
			Language.get("legacy_notepos_desc"),
			'legacynotepos',
			BOOL);
		addOption(option);
		var kadeHoldVisualOption:Option = new Option(Language.get('kade_hold_visual'),
			Language.get("kade_hold_visual_desc", ["启用 Kade 长条视觉：长条显示为分段，判定区间已走过的段淡出到 0.3（纯视觉，不改判定与回放）"]),
			'kadeHoldVisual',
			BOOL);
		addOption(kadeHoldVisualOption);







		super();

		// 音符 / 溅射预览组：原 VisualsSettingsSubState 在 super() 之后初始化，
		// 分类重组时随 onChangeArrowColorMode 一起搬过来，需补上初始化避免空指针。
		notes = new FlxTypedGroup<StrumNote>();
		splashes = new FlxTypedGroup<NoteSplash>();
		add(notes);
		add(splashes);
	}
}
