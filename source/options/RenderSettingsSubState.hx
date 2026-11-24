package options;

/**
 * 渲染导出 —— 独立设置子界面。
 *
 * 入口在「工具与校准」(ToolsSettingsSubState) 的 _toolRenderSettings 按钮，
 * 不占用设置主菜单，因此不需要同步 OptionsState 的
 * options[] / optionDescriptions[] / substateMap 与语言切换硬编码数组。
 *
 * 这里只负责持久化配置到 ClientPrefs.data；
 * 真正的渲染后端（Offline / SlowMotion / Realtime）由 backend 下的模块读取这些字段。
 * 三种后端共用同一套输出规格、范围与过场配置。
 */
class RenderSettingsSubState extends BaseOptionsMenu
{
	public function new()
	{
		title = Language.get('render_menu');
		rpcTitle = 'Render & Export Menu';

		var option:Option;

		// 渲染后端目前只实现了 Offline（逐帧离线 + 虚拟时钟）。
		// SlowMotion / Realtime 两套后端尚未接入，renderBackend / renderSlowFactor
		// 字段与规划注释保留在 ClientPrefs 里，等实现后再放回设置页，
		// 现在不展示，避免用户选了却没反应。

		option = new Option(Language.get('render_input_source'),
			Language.get('render_input_source_desc'),
			'renderInputSource',
			STRING,
			['BotPlay', 'Replay']);
		option.valueLocalizations = [
			'BotPlay' => Language.get('render_input_botplay'),
			'Replay' => Language.get('render_input_replay')
		];
		addOption(option);

		// Replay 来源时，回放在 Freeplay 里自主选择；渲染会跟随那局回放，
		// 不需要在这里选文件（见 render_input_source_desc）。

		option = new Option(Language.get('render_fps'),
			Language.get('render_fps_desc'),
			'renderFPS',
			INT);
		option.minValue = 24;
		option.maxValue = 240;
		option.displayFormat = '%v FPS';
		addOption(option);

		option = new Option(Language.get('render_logic_substeps'),
			Language.get('render_logic_substeps_desc'),
			'renderLogicSubsteps',
			INT);
		option.minValue = 1;
		option.maxValue = 8;
		option.displayFormat = '%vx';
		addOption(option);

		option = new Option(Language.get('render_width'),
			Language.get('render_width_desc'),
			'renderWidth',
			INT);
		option.minValue = 640;
		option.maxValue = 3840;
		option.displayFormat = '%v px';
		addOption(option);

		option = new Option(Language.get('render_height'),
			Language.get('render_height_desc'),
			'renderHeight',
			INT);
		option.minValue = 360;
		option.maxValue = 2160;
		option.displayFormat = '%v px';
		addOption(option);

		option = new Option(Language.get('render_lossless'),
			Language.get('render_lossless_desc'),
			'renderLossless',
			BOOL);
		addOption(option);

		option = new Option(Language.get('render_output'),
			Language.get('render_output_desc'),
			'renderOutput',
			STRING,
			['MP4', 'PNG', 'PNG+MP4']);
		option.valueLocalizations = [
			'MP4' => Language.get('render_output_mp4'),
			'PNG' => Language.get('render_output_png'),
			'PNG+MP4' => Language.get('render_output_both')
		];
		addOption(option);

		option = new Option(Language.get('render_encoder'),
			Language.get('render_encoder_desc'),
			'renderEncoder',
			STRING,
			['libx264', 'h264_nvenc']);
		option.valueLocalizations = [
			'libx264' => Language.get('render_encoder_x264'),
			'h264_nvenc' => Language.get('render_encoder_nvenc')
		];
		addOption(option);

		// x264 编码预设：越靠后越慢但压缩率/画质越好。默认 faster 兼顾速度与画质。
		option = new Option(Language.get('render_preset'),
			Language.get('render_preset_desc'),
			'renderPreset',
			STRING,
			['ultrafast', 'veryfast', 'faster', 'fast', 'medium', 'slow']);
		addOption(option);

		// renderSlowFactor 仅服务于尚未实现的 SlowMotion 后端，暂不展示。

		option = new Option(Language.get('render_range'),
			Language.get('render_range_desc'),
			'renderRange',
			STRING,
			['Countdown', 'SongOnly']);
		option.valueLocalizations = [
			'Countdown' => Language.get('render_range_countdown'),
			'SongOnly' => Language.get('render_range_songonly')
		];
		addOption(option);

		option = new Option(Language.get('render_cutscene'),
			Language.get('render_cutscene_desc'),
			'renderCutscene',
			STRING,
			['FFmpeg', 'Freeze', 'Skip']);
		option.valueLocalizations = [
			'FFmpeg' => Language.get('render_cutscene_ffmpeg'),
			'Freeze' => Language.get('render_cutscene_freeze'),
			'Skip' => Language.get('render_cutscene_skip')
		];
		addOption(option);

		option = new Option(Language.get('render_audio'),
			Language.get('render_audio_desc'),
			'renderAudio',
			BOOL);
		addOption(option);

		option = new Option(Language.get('render_crf'),
			Language.get('render_crf_desc'),
			'renderCRF',
			INT);
		// ffmpeg/x264 与 NVENC 的 CQ 范围都是 0~51；0 为无损，51 最低质量。
		// 无损模式会忽略这个值（走 qp=0 RGB），这里放宽供有损模式做极端质量/体积取舍。
		option.minValue = 0;
		option.maxValue = 51;
		option.displayFormat = 'CRF %v';
		addOption(option);

		option = new Option(Language.get('render_seed'),
			Language.get('render_seed_desc'),
			'renderSeed',
			INT);
		option.minValue = 0;
		option.maxValue = 999999;
		option.displayFormat = '#%v';
		addOption(option);

		option = new Option(Language.get('render_hide_overlay'),
			Language.get('render_hide_overlay_desc'),
			'renderHideOverlay',
			BOOL);
		addOption(option);

		// 启动入口：置位 requested，下一次进入 PlayState 时由 RenderClock.begin() 接管
		option = new Option(Language.get('render_start_next'),
			Language.get('render_start_next_desc'),
			'_renderStartNext',
			BUTTON);
		addOption(option);
		option.onChange = function() {
			backend.RenderClock.requested = true;
			CoolUtil.showPopUp(Language.get('render_start_next_ok'), Language.get('render_menu'));
		};

		super();
	}
}
