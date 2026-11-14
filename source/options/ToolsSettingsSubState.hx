package options;

/**
 * 工具与校准 —— 分类重组「阶段 1」新增的二级入口。
 *
 * 把原先直接挂在设置主菜单的 5 个专用页收拢到这里，
 * 让主菜单只保留按语义划分的分类入口，避免双栏布局被撑爆。
 * 另含一个「垃圾谱面」临时入口：阶段 2 完成选项搬迁后会移除。
 */
class ToolsSettingsSubState extends BaseOptionsMenu
{
	public function new()
	{
		title = Language.get('tools_menu');
		rpcTitle = 'Tools & Calibration Menu';









		var option:Option = new Option(Language.get('note_colors'),
			Language.get('note_colors_desc'),
			'_toolNoteColors',
			BUTTON);
		addOption(option);


		option.onChange = function() {
			openSubState(ClientPrefs.data.arrowColorMode == 'HSV'
				? new options.NotesColorSubStateLegacy()
				: new options.NotesColorSubState());
		};
		var option:Option = new Option(Language.get('controls'),
			Language.get('controls_desc'),
			'_toolControls',
			BUTTON);
		addOption(option);


		option.onChange = function() {
			openSubState(new options.ControlsSubState());
		};
		var option:Option = new Option(Language.get('adjust_delay_combo'),
			Language.get('adjust_delay_combo_desc'),
			'_toolDelayCombo',
			BUTTON);
		addOption(option);


		option.onChange = function() {
			MusicBeatState.switchState(new options.NoteOffsetState());
		};
		var option:Option = new Option(Language.get('adjust_rating_offset'),
			Language.get('adjust_rating_offset_desc'),
			'_toolRatingOffset',
			BUTTON);
		addOption(option);


		option.onChange = function() {
			MusicBeatState.switchState(new options.RatingOffsetState());
		};
		var option:Option = new Option(Language.get('window_manager'),
			Language.get('window_manager_desc'),
			'_toolWindowManager',
			BUTTON);
		addOption(option);


		option.onChange = function() {
			MusicBeatState.switchState(new states.WindowManagerState());
		};

		// 打开数据目录（原 MobileOptionsSubState 的 BUTTON 动作项，归「其他 / 待定」，收进工具页）
		var option:Option = new Option(Language.getWithFallback('open_data_folder', 'Open Data Folder'),
			Language.getWithFallback('open_data_folder_desc', 'Open the game data folder in a file manager.'),
			'_openDataFolder',
			BUTTON);
		addOption(option);
		option.onChange = function() {
			if (!MobileUtil.openDataFolder())
				CoolUtil.showPopUp(Language.getWithFallback('open_data_folder_failed', 'Could not open the data folder.'), 'Data Folder');
		};

		super();
	}
}
