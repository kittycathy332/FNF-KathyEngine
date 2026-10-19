package options;

import states.PlayState;
import objects.KeyViewer;
import backend.MusicBeatState;

class GameplaySettingsSubState extends BaseOptionsMenu
{
	public function new()
	{
		title = Language.get('gameplay_menu');
		rpcTitle = 'Gameplay Settings Menu'; //for Discord Rich Presence

		//I'd suggest using "Downscroll" as an example for making your own option since it is the simplest here
		var option:Option = new Option(Language.get('downscroll'),
			Language.get("downscroll_desc"),
			'downScroll',
			BOOL);
		addOption(option);

		var option:Option = new Option(Language.get('key_viewer'),
			Language.get("keyviewer_desc"),
			'keyViewer',
			BOOL);
		addOption(option);

		var option:Option = new Option(Language.get('key_viewer_profile'),
			Language.get("keyviewer_profile_desc"),
			'keyViewerProfile',
			BOOL);
		addOption(option);

		var option:Option = new Option(Language.get('reset_key_viewer_total'),
			Language.get("keyviewer_reset_total_desc"),
			'_keyViewerResetTotal',
			BUTTON);
		addOption(option);
		option.onChange = function() {
			KeyViewer.keyViewerTotal = 0;
			KeyViewer.saveKeyViewerTotal();
		};

		var option:Option = new Option(Language.get('key_viewer_trail'),
			Language.get("keyviewer_trail_desc"),
			'keyViewerTrail',
			STRING,
			['off', 'auto', 'up', 'down']);
		addOption(option);

		var option:Option = new Option(Language.get('key_viewer_position'),
			Language.get("keyviewer_pos_desc"),
			'_keyViewerPos',
			BUTTON);
		addOption(option);
		option.onChange = function() {
			MusicBeatState.switchState(new KeyViewerPosState());
		};

		var option:Option = new Option(Language.get('key_viewer_trail_speed'),
			Language.get("keyviewer_trail_speed_desc"),
			'keyViewerTrailSpeed',
			FLOAT);
		option.scrollSpeed = 10;
		option.minValue = 100;
		option.maxValue = 1000;
		option.changeValue = 10;
		option.decimals = 0;
		addOption(option);

		var option:Option = new Option(Language.get('middlescroll'),
			Language.get("middlescroll_desc"),
			'middleScroll',
			BOOL);
		addOption(option);

		var option:Option = new Option(Language.get('lane_cover_player'),
			Language.get("lane_cover_p1_desc"),
			'laneCoverAlphaP1',
			FLOAT);
		option.scrollSpeed = 2;
		option.minValue = 0;
		option.maxValue = 1;
		option.changeValue = 0.05;
		option.decimals = 2;
		option.onChange = onChangeLaneCover;
		addOption(option);

		var option:Option = new Option(Language.get('lane_cover_opponent'),
			Language.get("lane_cover_p2_desc"),
			'laneCoverAlphaP2',
			FLOAT);
		option.scrollSpeed = 2;
		option.minValue = 0;
		option.maxValue = 1;
		option.changeValue = 0.05;
		option.decimals = 2;
		option.onChange = onChangeLaneCover;
		addOption(option);

		var option:Option = new Option(Language.get('lane_cover_strum_alpha'),
			Language.get("lane_cover_strum_alpha_desc"),
			'laneCoverByStrumAlpha',
			BOOL);
		option.onChange = onChangeLaneCover;
		addOption(option);

		var option:Option = new Option(Language.get('opponent_notes'),
			Language.get("opponentnotes_desc"),
			'opponentStrums',
			BOOL);
		addOption(option);

		var option:Option = new Option(Language.get('ghost_tapping'),
			Language.get("ghosttapping_desc"),
			'ghostTappingMode',
			STRING,
			['off', 'whenNotSinging', 'whenSinging', 'always']);
		addOption(option);

		var option:Option = new Option(Language.get('precise_hit_timing'),
			Language.get("precise_hit_desc"),
			'preciseHit',
			BOOL);
		addOption(option);

		var option:Option = new Option(Language.get('input_system'),
			Language.get("input_system_desc"),
			'inputSystem',
			STRING,
			['default', 'rhythm']);
		addOption(option);

		var option:Option = new Option(Language.get('auto_pause'),
			Language.get("autopause_desc"),
			'autoPause',
			BOOL);
		addOption(option);
		option.onChange = onChangeAutoPause;

		var option:Option = new Option(Language.get('gc_on_resume'),
			Language.get("gc_on_resume_desc"),
			'gcOnResume',
			BOOL);
		addOption(option);

		var option:Option = new Option(Language.get('pop_up_score'),
			Language.get("popupscore_desc"),
			'popUpRating',
			BOOL);
		addOption(option);

		var option:Option = new Option(Language.get('disable_reset_button'),
			Language.get("disablereset_desc"),
			'noReset',
			BOOL);
		addOption(option);

		var option:Option = new Option(Language.get('force_hold_animations'),
			Language.get("force_hold_animations_desc"),
			'forceHoldAnimations',
			BOOL);
		addOption(option);

		#if mobile
		var option:Option = new Option(Language.get('game_over_vibration'),
			Language.get("gameovervibration_desc"),
			'gameOverVibration',
			BOOL);
		addOption(option);
		option.onChange = onChangeVibration;

		var mobileCompOption:Option = new Option(Language.get('mobile_judgment_compensation'),
			Language.get("mobilejudgmentcomp_desc", ["自动为触屏输入叠加判定偏移以补偿触屏延迟"]),
			'mobileJudgmentCompensation',
			BOOL);
		addOption(mobileCompOption);

		var mobileOffsetOption:Option = new Option(Language.get('mobile_judgment_offset'),
			Language.get("mobilejudgmentoffset_desc", ["移动端判定补偿量（毫秒）"]),
			'mobileJudgmentOffset',
			FLOAT);
		mobileOffsetOption.displayFormat = '%vms';
		mobileOffsetOption.scrollSpeed = 5;
		mobileOffsetOption.minValue = 0.0;
		mobileOffsetOption.maxValue = 30.0;
		mobileOffsetOption.changeValue = 1.0;
		addOption(mobileOffsetOption);
		#end

		var option:Option = new Option(Language.get('sustains_as_one_note'),
			Language.get("sustainsasone_desc"),
			'guitarHeroSustains',
			BOOL);
		addOption(option);

		var option:Option = new Option(Language.get('hold_note_tail_fix'),
			Language.get("hold_note_tail_fix_desc"),
			'sustainTailFix',
			STRING,
			['off', 'extend', 'earlyHit', 'both']);
		addOption(option);

		var option:Option = new Option(Language.get('hold_release_instant_miss'),
			Language.get("hold_release_instant_miss_desc"),
			'holdReleaseInstantMiss',
			BOOL);
		addOption(option);

		var option:Option = new Option(Language.get('hold_tail_judgement'),
			Language.get("hold_tail_judge_desc"),
			'holdTailJudge',
			BOOL);
		addOption(option);

		var option:Option = new Option(Language.get('hold_score_bonus'),
			"长条命中期间持续加分，直到长条结束（参考原版 Funkin，约每秒 250 分）。",
			'holdScoreBonus',
			BOOL);
		addOption(option);

		var option:Option = new Option(Language.get('hold_tail_leniency'),
			Language.get("hold_tail_leniency_desc"),
			'holdTailLeniency',
			BOOL);
		addOption(option);

		var option:Option = new Option(Language.get('hold_tail_leniency_ms'),
			Language.get("hold_tail_leniency_ms_desc"),
			'holdTailLeniencyMs',
			FLOAT);
		option.scrollSpeed = 2;
		option.minValue = 0;
		option.maxValue = 50;
		option.changeValue = 1;
		option.decimals = 0;
		addOption(option);

		// Extra Keys：开局键位预览（EK KeybindShowcase）
		var option:Option = new Option(Language.get('show_key_preview'),
			Language.get("show_key_preview_desc"),
			'showKeyPreview',
			BOOL);
		addOption(option);

		// 键位预览样式（EK KeybindShowcase / LE extraKeyReminders）
		var option:Option = new Option(Language.get('key_preview_style'),
			Language.get("key_preview_style_desc"),
			'keyPreviewStyle',
			STRING, ['ek', 'le']);
		option.valueLocalizations = ['ek' => Language.get('key_preview_style_ek'), 'le' => Language.get('key_preview_style_le')];
		addOption(option);

		var option:Option = new Option(Language.get('hitsound_volume'),
			Language.get("hitsoundvolume_desc"),
			'hitsoundVolume',
			PERCENT);
		addOption(option);
		option.scrollSpeed = 1.6;
		option.minValue = 0.0;
		option.maxValue = 1;
		option.changeValue = 0.1;
		option.decimals = 1;
		option.onChange = onChangeHitsoundVolume;

		var option:Option = new Option(Language.get('hitsound'),
			Language.get("hitsound_desc"),
			'hitsound',
			STRING,
			CoolUtil.coolTextFile(Paths.txt('hitsoundList')));
		addOption(option);
		option.onChange = onChangeHitsound;

		var option:Option = new Option(Language.get('hitsound_pitch_offset'),
			Language.get('hitsound_pitch_offset_desc'),
			'hitsoundPitchOffset',
			BOOL);
		addOption(option);

		var option:Option = new Option(Language.get('hitsound_pitch_range'),
			Language.get('hitsound_pitch_range_desc'),
			'hitsoundPitchRange',
			FLOAT);
		option.scrollSpeed = 20;
		option.minValue = 0.05;
		option.maxValue = 0.6;
		option.changeValue = 0.05;
		option.decimals = 2;
		addOption(option);

		var option:Option = new Option(Language.get('hitsound_pool_enabled'),
			Language.get('hitsound_pool_enabled_desc'),
			'hitSoundPoolEnabled',
			BOOL);
		addOption(option);

		var option:Option = new Option(Language.get('hitsound_pool_size'),
			Language.get('hitsound_pool_size_desc'),
			'hitSoundPoolSize',
			INT);
		option.scrollSpeed = 20;
		option.minValue = 10;
		option.maxValue = 500;
		option.changeValue = 5;
		addOption(option);

		var option:Option = new Option(Language.get('rating_offset'),
			Language.get("ratingoffset_desc"),
			'ratingOffset',
			INT);
		option.displayFormat = '%vms';
		option.scrollSpeed = 20;
		option.minValue = -180;
		option.maxValue = 180;
		addOption(option);

		var option:Option = new Option(Language.get('safe_frames'),
			Language.get("safeframes_desc"),
			'safeFrames',
			FLOAT);
		option.scrollSpeed = 5;
		option.minValue = 2;
		option.maxValue = 15;
		option.changeValue = 0.1;
		addOption(option);

		var hitWindowPresetOption:Option = new Option(Language.get('hit_window_preset'),
			Language.get("hitwindowpreset_desc"),
			'hitWindowPreset',
			STRING,
			['Leather', 'Psych / Kade', 'Funkin\'', 'Forever', 'Custom']);
		hitWindowPresetOption.onChange = onChangeHitWindowPreset;
		addOption(hitWindowPresetOption);

		var perfectWindowOption:Option = new Option(Language.get('perfect_hit_window'),
			Language.get("perfectwindow_desc"),
			'perfectWindow',
			FLOAT);
		perfectWindowOption.displayFormat = '%vms';
		perfectWindowOption.scrollSpeed = 15;
		perfectWindowOption.minValue = 5;
		perfectWindowOption.maxValue = 45.0;
		perfectWindowOption.changeValue = 0.1;
		perfectWindowOption.onChange = function() { adjustHitWindow('perfectWindow', ClientPrefs.data.perfectWindow); markPresetCustom(); };
		addOption(perfectWindowOption);

		var sickWindowOption:Option = new Option(Language.get('sick_hit_window'),
			Language.get("sickwindow_desc"),
			'sickWindow',
			FLOAT);
		sickWindowOption.displayFormat = '%vms';
		sickWindowOption.scrollSpeed = 15;
		sickWindowOption.minValue = 15.0;
		sickWindowOption.maxValue = 75.0;
		sickWindowOption.changeValue = 0.1;
		sickWindowOption.onChange = function() { adjustHitWindow('sickWindow', ClientPrefs.data.sickWindow); markPresetCustom(); };
		addOption(sickWindowOption);

		var goodWindowOption:Option = new Option(Language.get('good_hit_window'),
			Language.get("goodwindow_desc"),
			'goodWindow',
			FLOAT);
		goodWindowOption.displayFormat = '%vms';
		goodWindowOption.scrollSpeed = 30;
		goodWindowOption.minValue = 15.0;
		goodWindowOption.maxValue = 130.0;
		goodWindowOption.changeValue = 0.1;
		goodWindowOption.onChange = function() { adjustHitWindow('goodWindow', ClientPrefs.data.goodWindow); markPresetCustom(); };
		addOption(goodWindowOption);

		var badWindowOption:Option = new Option(Language.get('bad_hit_window'),
			Language.get("badwindow_desc"),
			'badWindow',
			FLOAT);
		badWindowOption.displayFormat = '%vms';
		badWindowOption.scrollSpeed = 60;
		badWindowOption.minValue = 15.0;
		badWindowOption.maxValue = 200.0;
		badWindowOption.changeValue = 0.1;
		badWindowOption.onChange = function() { adjustHitWindow('badWindow', ClientPrefs.data.badWindow); markPresetCustom(); };
		addOption(badWindowOption);

		var shitWindowOption:Option = new Option(Language.get('shit_hit_window'),
			Language.get("shitwindow_desc", ["判定兜底窗口，同时作为 safeZoneOffset 的固定值上限"]),
			'shitWindow',
			FLOAT);
		shitWindowOption.displayFormat = '%vms';
		shitWindowOption.scrollSpeed = 60;
		shitWindowOption.minValue = 135.0;
		shitWindowOption.maxValue = 300.0;
		shitWindowOption.changeValue = 1.0;
		shitWindowOption.onChange = function() { adjustHitWindow('shitWindow', ClientPrefs.data.shitWindow); markPresetCustom(); };
		addOption(shitWindowOption);

		var useShitWindowOption:Option = new Option(Language.get('use_shit_window_as_safezone'),
			Language.get("useshitwindow_desc", ["启用后 safeZoneOffset 使用 Shit Window 固定值，而非通过 Safe Frames 计算"]),
			'useShitWindowAsSafeZone',
			BOOL);
		addOption(useShitWindowOption);

		var softEdgeOption:Option = new Option(Language.get('soft_judgment_edge'),
			Language.get("softedge_desc", ["在判定窗口的最外 20% 边缘启用软插值，避免卡边界时出现判定跳变"]),
			'softJudgmentEdge',
			BOOL);
		addOption(softEdgeOption);

		breakComboShitOption = new Option(Language.get('break_combo_shit'),
			Language.get("break_combo_shit_desc", ["启用后，命中 Shit 评级会中断连击；关闭它会同时禁用「命中 Bad 时断连」"]),
			'breakComboOnShit',
			BOOL);
		breakComboShitOption.onChange = onChangeBreakComboShit;
		addOption(breakComboShitOption);

		breakComboBadOption = new Option(Language.get('break_combo_bad'),
			Language.get("break_combo_bad_desc", ["启用后，命中 Bad 评级会中断连击；需先启用「命中 Shit 时断连」才能开启"]),
			'breakComboOnBad',
			BOOL);
		breakComboBadOption.onChange = onChangeBreakComboBad;
		addOption(breakComboBadOption);

		var accuracyModeOption:Option = new Option(Language.get('accuracy_mode'),
			Language.get("accuracy_mode_desc", ["选择准确率的计算方式：Accurate 按评级固定加权，Complex 使用 Kade/wife3 毫秒精度"]),
			'accuracyMode',
			STRING,
			['Accurate', 'Complex']);
		addOption(accuracyModeOption);

		var sustainAccuracyOption:Option = new Option(Language.get('sustain_accuracy'),
			Language.get("sustain_accuracy_desc", ["启用后长条(尾音)命中会计入准确率；关闭后完全忽略长条对准确率的贡献"]),
			'sustainAccuracy',
			BOOL);
		addOption(sustainAccuracyOption);

		var kadeScoringOption:Option = new Option(Language.get('kade_scoring'),
			Language.get("kade_scoring_desc", ["启用后采用 Kade 计分制：bad=0 / shit=-300 / good=200 / sick=350，命中 Shit 会断连并计入 Miss，并套用 Kade 的命中/miss 加减血规则"]),
			'kadeScoring',
			BOOL);
		addOption(kadeScoringOption);

		var kadeHoldVisualOption:Option = new Option(Language.get('kade_hold_visual'),
			Language.get("kade_hold_visual_desc", ["启用 Kade 长条视觉：长条显示为分段，判定区间已走过的段淡出到 0.3（纯视觉，不改判定与回放）"]),
			'kadeHoldVisual',
			BOOL);
		addOption(kadeHoldVisualOption);

		presetDependentOptions = [perfectWindowOption, sickWindowOption, goodWindowOption, badWindowOption, shitWindowOption];

		super();
	}

	override public function onOptionsBuilt():Void
	{
		super.onOptionsBuilt();
		// 初始化完成后，根据当前预设刷新禁用状态
		refreshPresetDisabledState();
		// 同步断连选项的初始化可用性（加载到不一致状态时强制校正）
		refreshBreakComboDependency();
	}

	var presetDependentOptions:Array<Option> = null;
	var breakComboBadOption:Option = null;  // 命中 Bad 断连
	var breakComboShitOption:Option = null; // 命中 Shit 断连

	// 依赖规则：Shit 断连不启用时，Bad 断连无法启用；
	// 反之若 Bad 断连被关闭，则两者必须同时禁用。
	function onChangeBreakComboShit()
	{
		// 关闭 Shit 断连时，同步关闭并禁用 Bad 断连
		if (!ClientPrefs.data.breakComboOnShit)
			ClientPrefs.data.breakComboOnBad = false;
		refreshBreakComboDependency();
	}

	function onChangeBreakComboBad()
	{
		// 关闭 Bad 断连时，Shit 断连也必须一并关闭（两者同时禁用）
		if (!ClientPrefs.data.breakComboOnBad)
			ClientPrefs.data.breakComboOnShit = false;
		refreshBreakComboDependency();
	}

	// 一致性校正 + 刷新禁用状态/文本：
	// Bad 断连仅在 Shit 断连启用时才可操作。
	function refreshBreakComboDependency()
	{
		if (breakComboBadOption != null)
			breakComboBadOption.disabled = !ClientPrefs.data.breakComboOnShit;

		reloadCheckboxes();
		changeSelection(0);
	}

	function onChangeHitsoundVolume()
	{
		var useSound:String = 'hitsound';
		if (ClientPrefs.data.hitsound != 'none' && ClientPrefs.data.hitsound != null && ClientPrefs.data.hitsound.length > 0)
			useSound = 'hitsounds/' + ClientPrefs.data.hitsound;
		FlxG.sound.play(Paths.sound(useSound), ClientPrefs.data.hitsoundVolume);
	}

	function onChangeHitsound()
	{
		var soundName:String = ClientPrefs.data.hitsound;
		if (soundName != null && soundName != 'none')
			FlxG.sound.play(Paths.sound('hitsounds/' + soundName), 1.0);
	}

	function onChangeAutoPause()
		FlxG.autoPause = ClientPrefs.data.autoPause;

	function onChangeVibration()
	{
		if(ClientPrefs.data.gameOverVibration)
			lime.ui.Haptic.vibrate(0, 500);
	}

	// 添加联动逻辑：保持窗口严格升序 (perfect < sick < good < bad < shit)
	// 被联动的窗口只会跟随当前值，不会无限自增/自减。
	function adjustHitWindow(optionKey:String, newValue:Float) {
		switch(optionKey) {
			case 'perfectWindow':
				ClientPrefs.data.perfectWindow = newValue;
				if (newValue >= ClientPrefs.data.sickWindow) {
					ClientPrefs.data.sickWindow = newValue;
				}
			case 'sickWindow':
				ClientPrefs.data.sickWindow = newValue;
				if (newValue <= ClientPrefs.data.perfectWindow) {
					ClientPrefs.data.perfectWindow = newValue;
				} else if (newValue >= ClientPrefs.data.goodWindow) {
					ClientPrefs.data.goodWindow = newValue;
				}
			case 'goodWindow':
				ClientPrefs.data.goodWindow = newValue;
				if (newValue <= ClientPrefs.data.sickWindow) {
					ClientPrefs.data.sickWindow = newValue;
				} else if (newValue >= ClientPrefs.data.badWindow) {
					ClientPrefs.data.badWindow = newValue;
				}
			case 'badWindow':
				ClientPrefs.data.badWindow = newValue;
				if (newValue <= ClientPrefs.data.goodWindow) {
					ClientPrefs.data.goodWindow = newValue;
				} else if (newValue >= ClientPrefs.data.shitWindow) {
					ClientPrefs.data.shitWindow = newValue; // 与其它窗口保持一致的跟随策略
				}
			case 'shitWindow':
				ClientPrefs.data.shitWindow = newValue;
				if (newValue <= ClientPrefs.data.badWindow) {
					ClientPrefs.data.badWindow = newValue; // badWindow 跟随 shitWindow，不会无限减小
				}
			default:
		}
		// 所有窗口夹到合理范围，避免滑块溢出或顺序错乱
		function clamp(v:Float, lo:Float, hi:Float):Float { return Math.max(lo, Math.min(hi, v)); }
		ClientPrefs.data.perfectWindow = clamp(ClientPrefs.data.perfectWindow, 5,   250);
		ClientPrefs.data.sickWindow    = clamp(ClientPrefs.data.sickWindow,    15,  250);
		ClientPrefs.data.goodWindow    = clamp(ClientPrefs.data.goodWindow,    15,  250);
		ClientPrefs.data.badWindow     = clamp(ClientPrefs.data.badWindow,     15,  300);
		ClientPrefs.data.shitWindow    = clamp(ClientPrefs.data.shitWindow,    135, 300);
	}

	// 预设配置表 - 参考 Leather Engine timingPresets.txt
	// 名称, perfect, sick, good, bad, shit (单位: ms)
	static var hitWindowPresets:Map<String, { perfectWindow:Float, sickWindow:Float, goodWindow:Float, badWindow:Float, shitWindow:Float }> = [
		'Leather'      => { perfectWindow: 25.00, sickWindow: 50.00, goodWindow: 70.00,  badWindow: 100.00, shitWindow: 130.00 },
		'Psych / Kade' => { perfectWindow: 23.00, sickWindow: 45.00, goodWindow: 90.00,  badWindow: 135.00, shitWindow: 180.00 },
		'Funkin\''        => { perfectWindow: 16.00, sickWindow: 33.00, goodWindow: 124.00, badWindow: 149.00, shitWindow: 180.00 },
		'Forever'        => { perfectWindow: 14.78,  sickWindow: 33.33, goodWindow: 91.67,  badWindow: 133.33, shitWindow: 166.67 }
	];

	function onChangeHitWindowPreset()
	{
		var presetName:String = ClientPrefs.data.hitWindowPreset;

		if (hitWindowPresets.exists(presetName))
		{
			var preset = hitWindowPresets.get(presetName);
			ClientPrefs.data.perfectWindow = preset.perfectWindow;
			ClientPrefs.data.sickWindow = preset.sickWindow;
			ClientPrefs.data.goodWindow = preset.goodWindow;
			ClientPrefs.data.badWindow = preset.badWindow;
			ClientPrefs.data.shitWindow = preset.shitWindow;

			// 立刻刷新下方 4 个窗口选项的显示文本（复制 BaseOptionsMenu.updateTextFrom 的逻辑）
			for (opt in presetDependentOptions)
			{
				var val:Dynamic = opt.getValue();
				opt.text = opt.displayFormat.replace('%v', Std.string(val)).replace('%d', Std.string(opt.defaultValue));
			}
		}

		refreshPresetDisabledState();
	}

	// 根据预设切换: 非 Custom 状态下窗口滑块不可修改，Custom 状态下才解锁
	function refreshPresetDisabledState()
	{
		var isCustom:Bool = ClientPrefs.data.hitWindowPreset == 'Custom';
		for (opt in presetDependentOptions)
		{
			opt.disabled = !isCustom;
		}

		// 刷新视觉效果（改变 changeSelection 中的淡化逻辑依赖 curSelected）
		changeSelection(0);
	}

	function markPresetCustom()
	{
		// 当用户手动调整单个窗口时，自动切换到 Custom
		if (ClientPrefs.data.hitWindowPreset != 'Custom')
		{
			ClientPrefs.data.hitWindowPreset = 'Custom';
			refreshPresetDisabledState();
		}
	}

	private function onChangeLaneCover()
	{
		if (PlayState.instance != null) PlayState.instance.createLaneCovers();
	}
}
