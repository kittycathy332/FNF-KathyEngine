package options;

/**
 * 调试与信息面板 —— 分类重组阶段 2 自动生成。
 * 选项来自：ExtraGameplaySettingSubState.hx
 * 共 3 项；辅助函数按需从源文件带入。
 */
import flixel.text.FlxText;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.util.FlxTimer;
import backend.CustomFadeTransition;

class DebugPanelsSettingsSubState extends BaseOptionsMenu
{
	var enableGameLogOption:Option = null;
	var enableConsoleLogOption:Option = null;
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

	override public function onOptionsBuilt():Void
	{
		super.onOptionsBuilt();
		refreshGameLogDisabledState();
	}


	public function new()
	{
		title = Language.get('debug_display_menu');
		rpcTitle = 'Debug & Info Panels Menu';

		var enableConsoleLogOption:Option = null;
		var enableGameLogOption:Option = null;
		var option: Option;









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
		option = new Option(Language.get('show_event_information'),
			Language.get("events_debug_desc"),
			'eventDebug',
			BOOL);
		addOption(option);

		super();
	}
}
