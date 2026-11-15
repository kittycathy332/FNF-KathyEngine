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

		// 渲染后端：决定了时间轴由谁驱动，是整套方案里唯一影响架构的选项
		option = new Option(Language.get('render_backend'),
			Language.get('render_backend_desc'),
			'renderBackend',
			STRING,
			['Offline', 'SlowMotion', 'Realtime']);
		option.valueLocalizations = [
			'Offline' => Language.get('render_backend_offline'),
			'SlowMotion' => Language.get('render_backend_slowmotion'),
			'Realtime' => Language.get('render_backend_realtime')
		];
		addOption(option);

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

		option = new Option(Language.get('render_fps'),
			Language.get('render_fps_desc'),
			'renderFPS',
			INT);
		option.minValue = 24;
		option.maxValue = 240;
		option.displayFormat = '%v FPS';
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

		option = new Option(Language.get('render_slow_factor'),
			Language.get('render_slow_factor_desc'),
			'renderSlowFactor',
			FLOAT);
		option.minValue = 0.1;
		option.maxValue = 1.0;
		option.changeValue = 0.05;
		option.decimals = 2;
		option.displayFormat = '%vx';
		addOption(option);

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
		option.minValue = 16;
		option.maxValue = 30;
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
