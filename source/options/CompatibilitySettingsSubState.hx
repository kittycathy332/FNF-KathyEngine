package options;

import flixel.FlxG;
import backend.ClientPrefs;
import states.MainMenuState;

class CompatibilitySettingsSubState extends BaseOptionsMenu
{
	public function new()
	{
		title = Language.get("compatibility");
		rpcTitle = 'Compatibility Settings Menu';

		// OG Funkin 音符位置
		var option:Option = new Option(Language.get('legacy_note_position'),
			Language.get("legacy_notepos_desc"),
			'legacynotepos',
			BOOL);
		addOption(option);

		// 旧版 HUD 布局
		option = new Option(Language.get('legacy_hud'),
			Language.get("legacy_hud_desc"),
			'legacyHUD',
			BOOL);
		addOption(option);

		// 旧版主菜单界面
		option = new Option(Language.get('legacy_main_menu_ui'),
			Language.get("legacy_main_menu_desc"),
			'legacyMainMenu',
			BOOL);
		addOption(option);

		// 制谱器版本
		option = new Option(Language.get('charting_version'),
			Language.get("charting_version_desc"),
			'chartingVersion',
			STRING,
			states.editors.ChartingRouter.VERSIONS.copy());
		addOption(option);

		// Lua API 兼容版本
		option = new Option(Language.get('lua_compat_version'),
			Language.get("lua_compat_version_desc"),
			'luaCompatVersion',
			STRING,
			psychlua.LuaCompatRouter.VERSIONS.copy());
		addOption(option);

		// Leather Engine 脚本 API 兼容模式（所有模组的 scripts/*.lua 加载器）
		option = new Option(Language.get('leather_script_compat'),
			Language.get("leather_script_compat_desc"),
			'leatherScriptCompat',
			STRING,
			psychlua.leather.LeatherScriptRouter.MODES.copy());
		addOption(option);

		// 模组兼容性检测（扫描模组脚本，报告 Kathy / Psych 各版本的兼容性）
		option = new Option(Language.get('mod_compat_checker'),
			Language.get("mod_compat_checker_desc"),
			'modCompatChecker',
			BUTTON);
		option.onChange = function()
		{
			persistentUpdate = false;
			openSubState(new ModCompatCheckerSubState());
		};
		addOption(option);

		#if !mobile
		// 窗口标题
		option = new Option(Language.get('fake_window_title'),
			Language.get("fake_window_title_desc"),
			'windowTitlePreset',
			STRING,
			["Kathy Engine", "Psych Engine: MintRhythm Extended", "Friday Night Funkin': Psych Engine", "Friday Night Funkin': OS Engine", "Friday Night Funkin'", "FNF", "WTF in FNF", "Rhythm Game", "Not FNF", "Just a Game"]);
		option.onChange = onChangeWindowTitle;
		addOption(option);
		#end

		// Fake OS 版本
		option = new Option(Language.get('fake_os_version'),
			Language.get("fake_os_version_desc"),
			'fakeOSVersion',
			STRING,
			["1.5.1", "1.5.0", "1.4.1", "1.4.0", "1.3.1", "1.3.0", "1.2.0", "1.1.0", "1.0.1", "1.0.0"]);
		option.onChange = onChangeFakeOSMode;
		addOption(option);

		// Fake Psych 版本
		option = new Option(Language.get('fake_psych_version'),
			Language.get("fake_psych_version_desc"),
			'fakePsychVersion',
			STRING,
			["1.0.4", "1.0.3", "1.0.2h", "1.0.1", "1.0-prerelease", "1.0", "0.7.3", "0.7.2h", "0.7.2", "0.7.1h", "0.7", "0.6.3", "0.6.2", "0.6.1", "0.6", "0.5.2h", "0.5.2", "0.5.1", "0.5"]);
		option.onChange = onChangeFakePsychVersion;
		addOption(option);

		// 旧版短类名兼容层
		option = new Option(Language.get('legacy_class_alias'),
			Language.get("legacy_class_alias_desc"),
			'enableLegacyClassAlias',
			BOOL);
		addOption(option);

		// 长按音符仅播放一次确认动画
		option = new Option(Language.get('single_hold_animation'),
			Language.get("single_hold_note_animation_desc"),
			'singleHoldNoteAnimation',
			BOOL);
		addOption(option);

		// 自动重置箭头动画
		option = new Option(Language.get('auto_reset_strum_animation'),
			Language.get("auto_reset_strum_anim_desc"),
			'autoResetStrumAnim',
			BOOL);
		addOption(option);

		// Perfect 评级精灵回退至 Sick
		option = new Option(Language.get('fallback_perfect_to_sick'),
			Language.get("fallback_perfect_to_sick_desc"),
			'fallbackPerfectToSick',
			BOOL);
		addOption(option);

		// 额外 Perfect 评级精灵回退至 Sick
		option = new Option(Language.get('fallback_ex_perfect_to_sick'),
			Language.get("fallback_experfect_to_sick_desc"),
			'fallbackEXPerfectToSick',
			BOOL);
		addOption(option);

		super();
	}

	function onChangeFakeOSMode()
	{
		MainMenuState.osEngineVersion = ClientPrefs.data.fakeOSVersion;
		#if (!mobile && !html5)
		Main.updateWindowTitle();
		#end
	}

	function onChangeWindowTitle()
	{
		ClientPrefs.data.windowTitle = ClientPrefs.data.windowTitlePreset;
		#if (!mobile && !html5)
		Main.updateWindowTitle();
		#end
	}

	function onChangeFakePsychVersion()
	{
		MainMenuState.psychEngineVersion = ClientPrefs.data.fakePsychVersion;
	}

	function onChangeFakeOSVersion()
	{
		MainMenuState.osEngineVersion = ClientPrefs.data.fakeOSVersion;
	}
}
