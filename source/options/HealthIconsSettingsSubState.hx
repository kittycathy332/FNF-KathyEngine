package options;

/**
 * 血条与图标 —— 分类重组阶段 2 自动生成。
 * 选项来自：ExtraGameplaySettingSubState.hx, VisualsSettingsSubState.hx
 * 共 9 项；辅助函数按需从源文件带入。
 */
import flixel.text.FlxText;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.util.FlxTimer;
import backend.CustomFadeTransition;
import objects.Note;
import objects.StrumNote;
import objects.NoteSplash;
import objects.Alphabet;

class HealthIconsSettingsSubState extends BaseOptionsMenu
{
	var ratingBounceOption:Option = null;
	var ratingBounceOptionIndex:Int = -1;
	var healthOverflowOption:Option = null;
	var healthOverflowOptionIndex:Int = -1;
	var healthOverflowDrainOption:Option = null;
	var healthOverflowDrainOptionIndex:Int = -1;
	var smoothHPSpeedOption:Option = null;
	var smoothHPSpeedOptionIndex:Int = -1;
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

	override public function onOptionsBuilt():Void
	{
		super.onOptionsBuilt();
		refreshHealthOverflowState();
	}


	public function new()
	{
		title = Language.get('health_icons_menu');
		rpcTitle = 'Health & Icons Menu';

		var healthOverflowDrainOption:Option = null;
		var healthOverflowDrainOptionIndex:Int = -1;
		var healthOverflowOption:Option = null;
		var healthOverflowOptionIndex:Int = -1;
		var option: Option;
		var ratingBounceOption:Option = null;
		var ratingBounceOptionIndex:Int = -1;
		var smoothHPOption: Option;
		var smoothHPSpeedOption:Option = null;
		var smoothHPSpeedOptionIndex:Int = -1;









		option = new Option(Language.get('healthbar_style'),
			Language.get("healthbar_style_desc"),
			'healthbarstyle',
			STRING,
			['Psych', 'OS', 'Kade', 'Leather']);
		addOption(option);
		option = new Option(Language.get('health_bar_opacity'),
			Language.get("healthbaropacity_desc"),
			'healthBarAlpha',
			PERCENT);
		option.scrollSpeed = 1.6;
		option.minValue = 0.0;
		option.maxValue = 1;
		option.changeValue = 0.1;
		option.decimals = 1;
		addOption(option);
		smoothHPOption = new Option(Language.get('smooth_hp_bar'),
			Language.get("smooth_hpbar_desc"),
			'smoothHP',
			BOOL);
		smoothHPOption.onChange = refreshHealthOverflowState;
		addOption(smoothHPOption);
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
		option = new Option(Language.get('load_leather_icons'),
			Language.get("load_leather_icons_desc"),
			'loadLeatherIcons',
			STRING,
			['default', 'leather', 'os']);
		addOption(option);
		option = new Option(Language.get('3_state_icons_normal_lose_win'),
			Language.get("three_icons_desc"),
			'threeIcons',
			BOOL);
		addOption(option);
		option = new Option(Language.get('dynamic_health_icons'),
			Language.get("dynamic_health_icons_desc"),
			'dynamicHealthIcons',
			BOOL);
		addOption(option);




		super();
	}
}
