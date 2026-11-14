package options;

/**
 * 兼容性与脚本 —— 分类重组阶段 2 自动生成。
 * 选项来自：ExtraGameplaySettingSubState.hx, CompatibilitySettingsSubState.hx, SpamChartSettingsSubState.hx, VisualsSettingsSubState.hx
 * 共 13 项；辅助函数按需从源文件带入。
 */
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

class CompatibilityScriptsSubState extends BaseOptionsMenu
{

	function onChangeFakeOSMode()
	{
		MainMenuState.osEngineVersion = ClientPrefs.data.fakeOSVersion;
		#if (!mobile && !html5)
		Main.updateWindowTitle();
		#end
	}

	function onChangeFakePsychVersion()
	{
		MainMenuState.psychEngineVersion = ClientPrefs.data.fakePsychVersion;
	}

	public function new()
	{
		title = Language.get('compatibility_menu');
		rpcTitle = 'Compatibility & Scripts Menu';

		var option:Option;












		// Lua API 兼容版本

		option = new Option(Language.get('lua_compat_version'),
			Language.get("lua_compat_version_desc"),
			'luaCompatVersion',
			STRING,
			psychlua.LuaCompatRouter.VERSIONS.copy());
		addOption(option);



		// Leather Engine 脚本 API 兼容模式（所有模组的 scripts// .lua 加载器）
		option = new Option(Language.get('leather_script_compat'),
			Language.get("leather_script_compat_desc"),
			'leatherScriptCompat',
			STRING,
			psychlua.leather.LeatherScriptRouter.MODES.copy());
		addOption(option);



		// 制谱器版本
		option = new Option(Language.get('charting_version'),
			Language.get("charting_version_desc"),
			'chartingVersion',
			STRING,
			states.editors.ChartingRouter.VERSIONS.copy());
		addOption(option);



		// 旧版主菜单界面
		option = new Option(Language.get('legacy_main_menu_ui'),
			Language.get("legacy_main_menu_desc"),
			'legacyMainMenu',
			BOOL);
		addOption(option);



		// 旧版短类名兼容层
		option = new Option(Language.get('legacy_class_alias'),
			Language.get("legacy_class_alias_desc"),
			'enableLegacyClassAlias',
			BOOL);
		addOption(option);
		option = new Option(Language.get('legacy_hud'),
			Language.get("legacy_hud_desc"),
			'legacyHUD',
			BOOL);
		addOption(option);



		// 长按音符仅播放一次确认动画
		option = new Option(Language.get('lua_note_index_perf'),
			Language.get("lua_note_index_perf_desc"),
			'luaNoteIndexPerf',
			BOOL);
		addOption(option);
		option = new Option(Language.get('multi_key_layout'),
			Language.get("multi_key_layout_desc"),
			'multiKeyLayoutStyle',
			STRING,
			['PsychEK', 'Leather']);
		addOption(option);



		// 是否使用自定义（伪）窗口标题
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
		#if !mobile
		option = new Option(Language.get('mods_import'),
			Language.get("mods_import_desc"),
			'enableModsImport',
			BOOL);
		addOption(option);



		// 模组兼容性检测（扫描模组脚本，报告 Kathy / Psych 各版本的兼容性）
		#end
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

		super();
	}
}
