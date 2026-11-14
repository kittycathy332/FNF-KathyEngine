package options;

import states.MainMenuState;
import backend.StageData;
import com.yagp.Gif;
import objects.GifSprite;
import backend.GifAssets;
import flixel.FlxG;
import flixel.math.FlxMath;
import flixel.tweens.FlxTween;
import flixel.tweens.FlxEase;
import flixel.input.mouse.FlxMouse;
import flixel.ui.FlxButton;
import backend.CoolUtil;
import lime.system.System;
import haxe.ui.Toolkit;
import haxe.ui.components.Button;
import haxe.ui.core.Screen;
import haxe.ui.events.MouseEvent;

class OptionsState extends MusicBeatState
{
	// ===== 分类重组后的一级入口（10 个语义分类 + 1 个工具与校准）=====
	// 原先的 5 个专用页（箭头颜色 / 键位 / 两个偏移校准 / 窗口管理）已收进 ToolsSettingsSubState。
	// 注意：options 与 optionDescriptions 必须严格一一对应。
	public var options:Array<String> = [
		Language.get("system"),
		Language.get("graphics"),
		Language.get("compatibility"),
		Language.get("hud"),
		Language.get("health_icons"),
		Language.get("judgment"),
		Language.get("notes_visual"),
		Language.get("audio"),
		Language.get("debug_display"),
		Language.get("mobile_options"),
		Language.get("tools")
	];

	public var optionDescriptions:Array<String> = [
		Language.get("system_desc"),
		Language.get("graphics_desc"),
		Language.get("compatibility_desc"),
		Language.get("hud_desc"),
		Language.get("health_icons_desc"),
		Language.get("judgment_desc"),
		Language.get("notes_visual_desc"),
		Language.get("audio_desc"),
		Language.get("debug_display_desc"),
		Language.get("mobile_options_desc"),
		Language.get("tools_desc")
	];
	
	private var grpOptions:FlxTypedGroup<FlxText>;
	private static var curSelected:Int = 0;
	private static var lastOptionsSelection:Int = 0; // 记住主设置菜单上次选中的项（仅本次会话）
	public static var menuBG:FlxSprite;
	public static var onPlayState:Bool = false;

	var selectorLeft:FlxText;
	var selectorRight:FlxText;
	var descriptionText:FlxText;
	var sideGif:GifSprite = null;
	var titleText:FlxText;

	private var _sideGifOutTween:FlxTween = null;
	private var _sideGifHomeY:Float = 0; // sideGif 静止时的 y
	private var _titleHomeX:Float = 0;   // titleText 静止时的 x

	// HaxeUI 右上角按钮（取代原来的 adminButton / clearFilesButton）
	private var haxeUITopRightButton:Button = null;
	// HaxeUI 导入导出按钮（在原按钮下方）
	private var haxeUIIOButton:Button = null;

	// ===== 性能诊断（卡顿已优化完毕，逻辑暂时注释禁用；需要时可取消注释恢复）=====
	private var _diagStart:Float = 0;
	private var _diagLast:Float = 0;
	inline function diagTick(tag:String):Void
	{
		// 性能诊断已禁用：不再计时、不再输出到控制台与 diag_options.txt
		/*
		var now:Float = Sys.cpuTime();
		var msg:String = '[OptionsDiag] $tag: +${Math.round((now - _diagLast) * 1000)}ms (total ${Math.round((now - _diagStart) * 1000)}ms)';
		trace(msg);
		#if sys
		try {
			var f = sys.io.File.append(Sys.getCwd() + 'diag_options.txt');
			f.writeString(msg + '\n');
			f.close();
		} catch (e:Dynamic) {}
		#end
		_diagLast = now;
		*/
	}
	// ===== 性能诊断结束 =====

	// speaki 语音列表（assets/shared/sounds/speaki 下的全部 .ogg）
	private var speakiSounds:Array<String> = [
		'speaki/ahh', 'speaki/ahhww', 'speaki/baseo_full', 'speaki/baseo',
		'speaki/choayo_1', 'speaki/choayo_2', 'speaki/choayo_23', 'speaki/choayo_excited',
		'speaki/speaki_will_tryhard', 'speaki/speaki', 'speaki/spq_baseo',
		'speaki/wwaah_full', 'speaki/wwaahh'
	];
	private var pokeCooldown:Bool = false; // 戳戳冷却中（音频未播完）
	private var pokeTween:FlxTween = null;
	private var sideGifBaseScale:Float = 1; // sideGif 静止时的缩放（setGraphicSize 设定，非 1.0）

	private var _inSubState:Bool = false;

	private var itemSpacing:Int = 72; // 减小垂直间距
	private var startY:Float = 0;
	private var gridCols:Int = 2; // 双栏布局列数
	private var gridRows:Int = 0; // 每列行数（运行时计算）

	private var hideSelectors:Bool = false; // 是否隐藏选择器

	private var selectorLeftTargetX:Float = 0;
	private var selectorLeftTargetY:Float = 0;
	private var selectorRightTargetX:Float = 0;
	private var selectorRightTargetY:Float = 0;

	private var allowInput:Bool = true;
	private var descriptionTween:FlxTween;

	private var lastClickTime:Float = 0;
	private var lastClickIndex:Int = -1;

	#if (cpp && windows && !mobile)
	private function onAdminButtonClick():Void {
		// 请求管理员权限
		var success = backend.Native.requestAdminPrivilege();

		// 如果返回 false，说明用户拒绝了 UAC 提示
		// 此时游戏不会退出，继续运行
		if (!success) {
			// 可选：显示提示信息
			FlxG.log.add("UAC prompt was declined by user");
		}
	}
	#end

	#if mobile
	private function onClearFilesClick():Void {
		// 第一次确认
		CoolUtil.showConfirmDialog(
			Language.get("clear_copied_files_confirm"),
			LanguageBasic.getPhrase('mobile_notice', 'Notice!'),
			function() {
				// 第二次确认（最终警告）
				CoolUtil.showConfirmDialog(
					Language.get("clear_copied_files_warning"),
					LanguageBasic.getPhrase('mobile_warning', 'Warning!'),
					function() {
						// 执行清理
						var result: {deleted:Int, failed:Int} = {deleted: 0, failed: 0};
						#if COPYSTATE_ALLOWED
						result = states.CopyState.clearCopiedFiles();
						#end

						// 构建结果信息
						var deletedText = Language.get("clear_copied_files_deleted", [Std.string(result.deleted)]);
						var failedText = Language.get("clear_copied_files_failed_count", [Std.string(result.failed)]);

						var resultMessage:String = '';
						var resultTitle:String = '';

						if (result.failed > 0) {
							resultMessage = Language.get("clear_copied_files_failed") +
								"\n\n" + deletedText + "\n" + failedText + "\n\n" +
								Language.get("clear_copied_files_restart");
							resultTitle = LanguageBasic.getPhrase('mobile_error', 'Error!');
						} else if (result.deleted > 0) {
							resultMessage = Language.get("clear_copied_files_done") +
								"\n\n" + deletedText + "\n\n" +
								Language.get("clear_copied_files_restart");
							resultTitle = LanguageBasic.getPhrase('mobile_success', 'Success!');
						} else {
							resultMessage = Language.get("clear_copied_files_nothing") +
								"\n\n" +
								Language.get("clear_copied_files_restart");
							resultTitle = LanguageBasic.getPhrase('mobile_notice', 'Notice!');
						}

						// 显示结果弹窗，用户点击 OK 后游戏自动退出
						CoolUtil.showPopUp(resultMessage, resultTitle, function() {
							System.exit(0);
						});
					}
				);
			}
		);
	}
	#end

	function openSelectedSubstate(label:String) {
		_inSubState = true; // 标记进入子状态，阻止主界面UI操作

		// 始终保持父界面 update 运行（persistentUpdate = true），
		// 这样背景网格、sideGif 等装饰元素持续刷新，进出子界面更连贯
		persistentUpdate = true;
		removeTouchPad();

		// 子界面打开时禁用主界面输入
		allowInput = false;

		// 隐藏当前选中的选项文本（不隐藏 grpOptions 整体，这样退出时直接恢复即可）
		if (grpOptions != null && curSelected >= 0 && curSelected < grpOptions.length)
		{
			grpOptions.members[curSelected].visible = false;
		}

		// 打开 Graphics 子界面时 sideGif 向上飞出 + 标题滑正中（进子界面后才触发，高亮不触发）
		triggerSideGifOut(label == Language.get("graphics"));

		// ===== 分类重组完成 =====
		// 10 个语义分类 + 1 个工具与校准，全部指向新建的 SubState。
		// 旧 7 个子界面文件已删除；独立设置页仍由 HUD 分类里的 _fpsSettings 按钮进入。
		var substateMap:Map<String, () -> Void> = [
			Language.get("judgment") => () -> openSubState(new options.JudgmentSettingsSubState()),
			Language.get("tools") => () -> openSubState(new options.ToolsSettingsSubState()),
			Language.get("notes_visual") => () -> openSubState(new options.NotesVisualSettingsSubState()),
			Language.get("hud") => () -> openSubState(new options.HudSettingsSubState()),
			Language.get("audio") => () -> openSubState(new options.AudioSettingsSubState()),
			Language.get("health_icons") => () -> openSubState(new options.HealthIconsSettingsSubState()),
			Language.get("graphics") => () -> openSubState(new options.GraphicsPerformanceSettingsSubState()),
			Language.get("mobile_options") => () -> openSubState(new options.MobileTouchSettingsSubState()),
			Language.get("system") => () -> openSubState(new options.SystemWindowSettingsSubState()),
			Language.get("compatibility") => () -> openSubState(new options.CompatibilityScriptsSubState()),
			Language.get("debug_display") => () -> openSubState(new options.DebugPanelsSettingsSubState())
		];

		if (substateMap.exists(label)) {
			substateMap.get(label)();
		}
	}

	override function create()
	{
		#if DISCORD_ALLOWED
		DiscordClient.changePresence("Options Menu", null);
		#end

		// 性能诊断起点（已禁用）
		//_diagStart = Sys.cpuTime();
		//_diagLast = _diagStart;

		var bg:FlxSprite = new FlxSprite().loadGraphic(Paths.image('menuDesat'));
		bg.antialiasing = ClientPrefs.data.antialiasing;
		bg.color = 0xFF00BFFF;
		bg.updateHitbox();

		bg.screenCenter();
		add(bg);
		diagTick('bg(menuDesat)');

		// 顶部居中大标题（跟随语言），使用自动尺寸以便精确测量文本宽度来定位 GIF
		titleText = new FlxText(0, 40, 0, Language.get('options_title'), 48);
		titleText.setFormat(Paths.font(Language.get('game_font')), 48, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		titleText.borderSize = 2;
		titleText.scrollFactor.set();
		titleText.antialiasing = ClientPrefs.data.antialiasing;
		titleText.x = (FlxG.width - titleText.width) / 2;
		add(titleText);
		diagTick('titleText+font');

		// 标题左侧固定 GIF（minispeaki）：异步后台解码，避免低端机进入设置界面时同步解码
		// 73 帧 GIF（约 500 万像素）导致卡顿数秒；解码结果由 GifAssets 全局缓存，再次进入秒开
		sideGif = new GifSprite(0, 0);
		sideGif.disposeGifOnDestroy = false; // 解码数据由 GifAssets 缓存共享，离开本界面不销毁
		sideGif.antialiasing = ClientPrefs.data.antialiasing;
		sideGif.scrollFactor.set();
		sideGif.visible = false; // 解码完成后再显示
		add(sideGif);

		GifAssets.load('assets/shared/images/gifs/minispeaki.gif', function(gif:Gif) {
			diagTick('GIF解码完成->attachGif');
			// 解码期间可能已切走 state（sideGif 字段非 null 但已销毁）：exists 为 false 则直接放弃挂载
			if (sideGif == null || !sideGif.exists) return;
			sideGif.attachGif(gif);
			sideGif.setGraphicSize(96);
			sideGif.updateHitbox();
			sideGifBaseScale = sideGif.scale.x; // 记录静止缩放（setGraphicSize(96) 后通常 < 1）
			// 用默认左上角原点定位（origin 保持 0,0），与"添加动效前"完全一致：位于"设置"文本左侧，留 12px 间隙，垂直居中
			sideGif.x = titleText.x - sideGif.width - 12;
			sideGif.y = titleText.y + (titleText.height - sideGif.height) / 2;
			// 记录静止基准位置，供飞出/飞回动画使用
			_sideGifHomeY = sideGif.y;
			// titleText 基准 x：sideGif 在左侧时，让 titleText 故意偏右 30px，飞出后滑回真正正中
			_titleHomeX = (FlxG.width - titleText.width) / 2 + 30;
			titleText.x = _titleHomeX;
			// 加载完成后渐显，避免瞬间弹出
			sideGif.alpha = 0;
			sideGif.visible = true;
			FlxTween.tween(sideGif, {alpha: 1}, 0.5, {ease: FlxEase.quadOut});
			diagTick('GIF attach 定位完成');
		}, function() {
			// 解码失败：保持隐藏，不影响其余界面
			if (sideGif != null) sideGif.visible = false;
		});
		diagTick('GifAssets.load 发起');

		// 不在此同步预加载全部 speaki 语音：Paths.sound() 底层是 Sound.fromFile 主线程同步解码，
		// 13 个 OGG 在低端机上会让进入设置界面卡顿数秒。改为 pokeGif() 中按需加载（首次小卡顿，之后走缓存）
		pokeCooldown = false;

		if (controls.mobileC)
		{
			var keyLabel:String = FlxG.onMobile ? 'C' : 'CTRL or C';
			var tipText:FlxText = new FlxText(150, FlxG.height - 24, 0, Language.get('mobile_controls_menu_tip', [keyLabel]), 16);
			tipText.setFormat(Paths.font(Language.get('game_font')), 17, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			tipText.borderSize = 1.25;
			tipText.scrollFactor.set();
			tipText.antialiasing = ClientPrefs.data.antialiasing;
			add(tipText);
		}

		grpOptions = new FlxTypedGroup<FlxText>();
		add(grpOptions);

		itemSpacing = OptionsConfig.ITEM_SPACING;
		// 双栏布局：窄屏（如手机）退化为单栏
		gridCols = (FlxG.width < 900) ? 1 : 2;
		gridRows = Std.int(Math.ceil(options.length / gridCols));
		var totalHeight = itemSpacing * gridRows;
		startY = (FlxG.height - totalHeight) / 2 + itemSpacing / 2;

		// 启用虚拟方向键（移动端或桌面开启移动控制）时，左侧 LEFT_FULL 方向键会覆盖约 x∈[0,330] 区域，
		// 将选项列整体右移到方向键之外，并适当缩小字号以适配窄屏，避免选项被虚拟键盖住。
		var leftColX = OptionsConfig.LEFT_MARGIN;
		var itemFontSize:Int = 48;
		if (controls.mobileC)
		{
			leftColX = 340;
			itemFontSize = 40;
		}
		var rightColX = (gridCols > 1) ? (Math.floor(FlxG.width * 0.5) + 40) : leftColX;

		for (num => option in options)
		{
			var col:Int = Std.int(num / gridRows);
			var row:Int = num % gridRows;
			var itemX = (col == 0) ? leftColX : rightColX;

			var optionText:FlxText = new FlxText(itemX, 0, 0, LanguageBasic.getPhrase('options_$option', option), itemFontSize);
			optionText.setFormat(Paths.font(Language.get('game_font')), itemFontSize, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			optionText.borderSize = 2;
			optionText.antialiasing = ClientPrefs.data.antialiasing;
			optionText.x = itemX;
			optionText.y = startY + row * itemSpacing;
			grpOptions.add(optionText);
		}

		selectorLeft = new FlxText(0, 0, 0, ">", itemFontSize);
		selectorLeft.setFormat(Paths.font(Language.get('game_font')), itemFontSize, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		selectorLeft.borderSize = 2;
		selectorLeft.antialiasing = ClientPrefs.data.antialiasing;
		add(selectorLeft);

		selectorRight = new FlxText(0, 0, 0, "<", itemFontSize);
		selectorRight.setFormat(Paths.font(Language.get('game_font')), itemFontSize, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		selectorRight.borderSize = 2;
		selectorRight.antialiasing = ClientPrefs.data.antialiasing;
		add(selectorRight);

		// 添加描述文本（水平居中、垂直偏下）
		descriptionText = new FlxText(100, FlxG.height - 120, FlxG.width - 200, optionDescriptions[curSelected], 24);
		descriptionText.setFormat(Paths.font(Language.get('game_font')), 24, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		descriptionText.borderSize = 1;
		descriptionText.antialiasing = ClientPrefs.data.antialiasing;
		descriptionText.scrollFactor.set();
		add(descriptionText);
		diagTick('grpOptions+selectors+desc');

		// 右上角按钮（Windows 为管理员权限，移动端为清空复制文件），改用 HaxeUI 实现
		addHaxeUITopRightButton();
		addHaxeUIIOButton();
		diagTick('HaxeUI按钮');

		// 初始化选择器目标位置
		changeSelection();
		diagTick('changeSelection(0)');

		// 直接设置选择器初始位置
		selectorLeft.x = selectorLeftTargetX;
		selectorLeft.y = selectorLeftTargetY;
		selectorRight.x = selectorRightTargetX;
		selectorRight.y = selectorRightTargetY;

		ClientPrefs.saveSettings();
		diagTick('saveSettings');

		addTouchPad('LEFT_FULL', 'A_B_C');
		diagTick('addTouchPad');

		super.create();
		FlxG.mouse.visible = true;
		diagTick('super.create');

		// 记住上次选中的项（仅本次游戏会话内有效，超出范围则回退到中间项）
		curSelected = Std.int(Math.max(0, Math.min(options.length - 1, lastOptionsSelection)));
		changeSelection(0); // 刷新高亮和描述
		diagTick('changeSelection(0) 结束');
	}

	// 在设置主界面右上角添加 HaxeUI 按钮（取代原来的 Flixel 按钮）
	private function addHaxeUITopRightButton():Void {
		if (haxeUITopRightButton != null) return;

		#if mobile
		var btnText:String = Language.get("clear_copied_files");
		var clickFn:Void->Void = onClearFilesClick;
		var showBtn:Bool = true;
		#elseif (cpp && windows)
		var btnText:String = Language.get("request_admin_button");
		var clickFn:Void->Void = onAdminButtonClick;
		var showBtn:Bool = !backend.Native.isAdmin();
		#else
		var btnText:String = "";
		var clickFn:Void->Void = null;
		var showBtn:Bool = false;
		#end

		if (!showBtn) return;

		// 首次使用时初始化 HaxeUI Toolkit（幂等）；
		// 禁用 DPI 自动缩放，保证 HaxeUI 坐标与 Flixel 屏幕坐标一致
		if (!Toolkit.initialized) {
			Toolkit.autoScale = false;
			Toolkit.init();
		}

		haxeUITopRightButton = new Button();
		haxeUITopRightButton.text = btnText;
		haxeUITopRightButton.x = FlxG.width - 220;
		haxeUITopRightButton.y = 20;
		haxeUITopRightButton.width = 200;
		haxeUITopRightButton.height = 40;
		// 禁止键盘焦点：否则回车/确认键会被 HaxeUI 动作系统路由到该按钮并触发点击（如桌面弹 UAC）
		haxeUITopRightButton.allowFocus = false;
		haxeUITopRightButton.styleString = "font-name: " + Paths.font("unifont-18.0.01.otf") + "; font-size: 16px;";
		haxeUITopRightButton.registerEvent(MouseEvent.CLICK, function(_) clickFn());
		// 加入 HaxeUI Screen，会自动挂到当前 FlixelState 之上渲染
		Screen.instance.addComponent(haxeUITopRightButton);
	}

	// 在 HaxeUI 按钮下方添加「设置导入/导出」按钮
	private function addHaxeUIIOButton():Void {
		if (haxeUIIOButton != null) return;

		// 首次使用时初始化 HaxeUI Toolkit（幂等）
		if (!Toolkit.initialized) {
			Toolkit.autoScale = false;
			Toolkit.init();
		}

		var btnY:Int = 20;
		// 如果右上角已有按钮，在它下方
		if (haxeUITopRightButton != null)
			btnY = Std.int(haxeUITopRightButton.y + haxeUITopRightButton.height + 6);

		haxeUIIOButton = new Button();
		haxeUIIOButton.text = Language.get("settings_io_button");
		haxeUIIOButton.x = FlxG.width - 220;
		haxeUIIOButton.y = btnY;
		haxeUIIOButton.width = 200;
		haxeUIIOButton.height = 40;
		haxeUIIOButton.allowFocus = false;
		haxeUIIOButton.styleString = "font-name: " + Paths.font("unifont-18.0.01.otf") + "; font-size: 16px;";
		haxeUIIOButton.registerEvent(MouseEvent.CLICK, function(_) { ClientPrefs.saveSettings(); FlxG.switchState(new options.OptionsIOState()); });
		Screen.instance.addComponent(haxeUIIOButton);
	}

	override function closeSubState()
	{
		super.closeSubState();
		ClientPrefs.saveSettings();
		#if DISCORD_ALLOWED
		DiscordClient.changePresence("Options Menu", null);
		#end
		controls.isInSubstate = false;
		removeTouchPad();
		addTouchPad('LEFT_FULL', 'A_B_C');
		persistentUpdate = true;
		allowInput = true;
		_inSubState = false; // 退出子状态

		// 恢复被隐藏的选中项可见性
		if (grpOptions != null && curSelected >= 0 && curSelected < grpOptions.length)
		{
			grpOptions.members[curSelected].visible = true;
		}

		// 退出子界面后 sideGif 飞回原位 + 标题回位
		triggerSideGifOut(false);
	}

	var exiting = false;
	override function update(elapsed:Float) {
		super.update(elapsed);

		// 按住 Shift 时快速滚动（每次跳 4 项，与 LanguageSubState 一致）
		var mult:Int = (FlxG.keys.pressed.SHIFT) ? 4 : 1;

		// 在子状态中，淡出选择器，但保持位置更新
		if (_inSubState) {
			// 更新选择器位置到当前选中项
			var selectedOption = grpOptions.members[curSelected];
			if (selectedOption != null)
			{
				selectorLeftTargetX = selectedOption.x - 63;
				selectorLeftTargetY = selectedOption.y;
				selectorRightTargetX = selectedOption.x + selectedOption.width + 15;
				selectorRightTargetY = selectedOption.y;

				// 平滑移动到目标位置
				selectorLeft.x = FlxMath.lerp(selectorLeftTargetX, selectorLeft.x, Math.exp(-elapsed * OptionsConfig.SELECTOR_LERP_SPEED));
				selectorLeft.y = FlxMath.lerp(selectorLeftTargetY, selectorLeft.y, Math.exp(-elapsed * OptionsConfig.SELECTOR_LERP_SPEED));
				selectorRight.x = FlxMath.lerp(selectorRightTargetX, selectorRight.x, Math.exp(-elapsed * OptionsConfig.SELECTOR_LERP_SPEED));
				selectorRight.y = FlxMath.lerp(selectorRightTargetY, selectorRight.y, Math.exp(-elapsed * OptionsConfig.SELECTOR_LERP_SPEED));
			}

			// 淡出选择器
			selectorLeft.alpha = FlxMath.lerp(0, selectorLeft.alpha, Math.exp(-elapsed * 10));
			selectorRight.alpha = FlxMath.lerp(0, selectorRight.alpha, Math.exp(-elapsed * 10));
			return;
		}

		// 根据hideSelectors标志控制选择器显示/隐藏
		var targetAlpha:Float = hideSelectors ? 0 : 1;
		selectorLeft.alpha = FlxMath.lerp(targetAlpha, selectorLeft.alpha, Math.exp(-elapsed * 10));
		selectorRight.alpha = FlxMath.lerp(targetAlpha, selectorRight.alpha, Math.exp(-elapsed * 10));

		// 始终显示鼠标指针
		FlxG.mouse.visible = true;

		// 仅在允许输入时处理按键
		if (allowInput) {
			if (!exiting) {
				if (controls.UI_UP_P) {
					changeSelection(0, -1 * mult);
					hideSelectors = false; // 键盘输入恢复显示
				}
				if (controls.UI_DOWN_P) {
					changeSelection(0, 1 * mult);
					hideSelectors = false; // 键盘输入恢复显示
				}
				if (controls.UI_LEFT_P || (touchPad != null && touchPad.buttonLeft.justPressed)) {
					changeSelection(-1 * mult, 0);
					hideSelectors = false;
				}
				if (controls.UI_RIGHT_P || (touchPad != null && touchPad.buttonRight.justPressed)) {
					changeSelection(1 * mult, 0);
					hideSelectors = false;
				}

				if (touchPad.buttonC.justPressed || FlxG.keys.justPressed.CONTROL && controls.mobileC)
				{
					persistentUpdate = false;
					openSubState(new mobile.substates.MobileControlSelectSubState());
				}

				if (controls.BACK)
				{
					exiting = true;
					FlxG.sound.play(Paths.sound('cancelMenu'));
					if (onPlayState)
					{
						StageData.loadDirectory(PlayState.SONG);
						LoadingState.loadAndSwitchState(new PlayState());
						FlxG.sound.music.volume = 0;
					}
					else MusicBeatState.switchState(new MainMenuState());
				}
				else if (controls.ACCEPT) {
					openSelectedSubstate(options[curSelected]);
					hideSelectors = false; // 键盘输入恢复显示
				}
			}
		}

		// --- 移动端虚拟按键检测 ---
		#if mobile
		// 检查虚拟按键是否被按下（除了C按钮，它有单独的功能）
		if (touchPad != null) {
			var anyButtonPressed = touchPad.buttonUp.pressed || touchPad.buttonDown.pressed ||
			                       touchPad.buttonLeft.pressed || touchPad.buttonRight.pressed ||
			                       touchPad.buttonA.pressed || touchPad.buttonB.pressed;
			if (anyButtonPressed) {
				hideSelectors = true; // 虚拟按键按下时隐藏选择器
			} else if (touchPad.buttonC.justReleased) {
				// C按钮松开时不隐藏选择器（它有单独的功能）
			}
		}
		#end

		// --- 鼠标拖动与点击选项 ---
		var mouse:FlxMouse = FlxG.mouse;
		var mouseOverOption:Int = -1;
		for (i in 0...grpOptions.length) {
			var opt = grpOptions.members[i];
			if (mouse.x >= opt.x && mouse.x <= opt.x + opt.width && mouse.y >= opt.y && mouse.y <= opt.y + opt.height) {
				mouseOverOption = i;
				break;
			}
		}

		// 移动端：本次触摸若落在虚拟按键上，则不应被当作对选项的点击，避免误触选中
		var touchPadJustPressed:Bool = false;
		#if mobile
		if (touchPad != null) {
			touchPadJustPressed = touchPad.buttonUp.justPressed || touchPad.buttonDown.justPressed ||
				touchPad.buttonLeft.justPressed || touchPad.buttonRight.justPressed ||
				touchPad.buttonA.justPressed || touchPad.buttonB.justPressed || touchPad.buttonC.justPressed;
		}
		#end

		// 鼠标单击选项自动更改选中项（虚拟按键按下时跳过）
		if (mouseOverOption != -1 && mouse.justPressed && !touchPadJustPressed) {
			if (curSelected != mouseOverOption) {
				var targetCol:Int = Std.int(mouseOverOption / gridRows);
				var targetRow:Int = mouseOverOption % gridRows;
				var curCol:Int = Std.int(curSelected / gridRows);
				var curRow:Int = curSelected % gridRows;
				changeSelection(targetCol - curCol, targetRow - curRow);
			}
			hideSelectors = true; // 点击选项时隐藏选择器
			// 双击检测
			var now = FlxG.game.ticks / 1000.0;
			if (lastClickIndex == mouseOverOption && (now - lastClickTime) < OptionsConfig.DOUBLE_CLICK_THRESHOLD) {
				openSelectedSubstate(options[mouseOverOption]);
		}
		lastClickTime = now;
		lastClickIndex = mouseOverOption;
	}

		// 鼠标右键双击也可进入
		if (mouseOverOption != -1 && mouse.justPressedRight) {
			openSelectedSubstate(options[mouseOverOption]);
		}

		// 点击 sideGif：q弹戳戳 + 随机语音（有 cd，需等音频播完）
		if (mouse.justPressed && allowInput && !_inSubState && sideGif != null && sideGif.visible)
		{
			// origin 为默认左上角，故精灵中心 = (x + width/2, y + height/2)，命中判定须以真实中心为准
			var cx:Float = sideGif.x + sideGif.width / 2;
			var cy:Float = sideGif.y + sideGif.height / 2;
			var hw:Float = sideGif.width / 2;
			var hh:Float = sideGif.height / 2;
			if (Math.abs(mouse.x - cx) <= hw && Math.abs(mouse.y - cy) <= hh)
			{
				pokeGif();
			}
		}

		// 选中项动效
		for (i in 0...grpOptions.length)
		{
			var item = grpOptions.members[i];
			if (i == curSelected)
			{
				item.scale.x = FlxMath.lerp(OptionsConfig.SELECTED_SCALE, item.scale.x, Math.exp(-elapsed * OptionsConfig.SCALE_LERP_SPEED));
				item.scale.y = FlxMath.lerp(OptionsConfig.SELECTED_SCALE, item.scale.y, Math.exp(-elapsed * OptionsConfig.SCALE_LERP_SPEED));
			}
			else
			{
				item.scale.x = FlxMath.lerp(OptionsConfig.NORMAL_SCALE, item.scale.x, Math.exp(-elapsed * OptionsConfig.SCALE_LERP_SPEED));
				item.scale.y = FlxMath.lerp(OptionsConfig.NORMAL_SCALE, item.scale.y, Math.exp(-elapsed * OptionsConfig.SCALE_LERP_SPEED));
			}
		}

		// 更新选择器位置，使其跟随当前选中选项
		var selectedOption = grpOptions.members[curSelected];
		if (selectedOption != null)
		{
			selectorLeftTargetX = selectedOption.x - 63;
			selectorLeftTargetY = selectedOption.y;
			selectorRightTargetX = selectedOption.x + selectedOption.width + 15;
			selectorRightTargetY = selectedOption.y;
		}

		// < 和 > 选择器平滑动画
		selectorLeft.x = FlxMath.lerp(selectorLeftTargetX, selectorLeft.x, Math.exp(-elapsed * OptionsConfig.SELECTOR_LERP_SPEED));
		selectorLeft.y = FlxMath.lerp(selectorLeftTargetY, selectorLeft.y, Math.exp(-elapsed * OptionsConfig.SELECTOR_LERP_SPEED));
		selectorRight.x = FlxMath.lerp(selectorRightTargetX, selectorRight.x, Math.exp(-elapsed * OptionsConfig.SELECTOR_LERP_SPEED));
		selectorRight.y = FlxMath.lerp(selectorRightTargetY, selectorRight.y, Math.exp(-elapsed * OptionsConfig.SELECTOR_LERP_SPEED));
	}

	private function pokeGif():Void
	{
		if (pokeCooldown || sideGif == null || !sideGif.visible)
			return;
		pokeCooldown = true;

		// 取消上一次补间，从当前状态重新弹动
		if (pokeTween != null)
			pokeTween.cancel();

		// 戳一下先变小（被“戳扁”），再用 lerp 平滑过渡回原本的小图大小，营造“q弹/戳戳”手感
		// 注意：回归目标是 sideGifBaseScale（setGraphicSize 设定的静止缩放），而非 1.0，否则会放大到原始尺寸
		// origin 为默认左上角，缩放会绕左上角进行，故在补间中持续补偿 x/y 使显示中心保持不动
		var s:Float = sideGifBaseScale;
		var cx:Float = sideGif.x + sideGif.width / 2;
		var cy:Float = sideGif.y + sideGif.height / 2;
		sideGif.scale.set(s * 0.6, s * 0.6);
		sideGif.x = cx - (sideGif.frameWidth * sideGif.scale.x) / 2;
		sideGif.y = cy - (sideGif.frameHeight * sideGif.scale.y) / 2;
		pokeTween = FlxTween.tween(sideGif.scale, { x: s, y: s }, 0.45,
			{ ease: FlxEase.quadOut,
			  onUpdate: function(twn:FlxTween) {
				  sideGif.x = cx - (sideGif.frameWidth * sideGif.scale.x) / 2;
				  sideGif.y = cy - (sideGif.frameHeight * sideGif.scale.y) / 2;
			  },
			  onComplete: function(twn:FlxTween) {
				  sideGif.x = cx - (sideGif.frameWidth * sideGif.scale.x) / 2;
				  sideGif.y = cy - (sideGif.frameHeight * sideGif.scale.y) / 2;
				  pokeTween = null;
			  } });

		// 随机播放 speaki 语音
		var key:String = speakiSounds[FlxG.random.int(0, speakiSounds.length - 1)];
		var snd = FlxG.sound.play(Paths.sound(key));
		if (snd != null)
			snd.onComplete = function() { pokeCooldown = false; };
	}

	function changeSelection(dx:Int = 0, dy:Int = 0)
	{
		var col:Int = Std.int(curSelected / gridRows);
		var row:Int = curSelected % gridRows;

		// 左右切换列：在列之间环绕（左栏按左键跳到最右栏，右栏按右键跳到最左栏，与上下一致）
		col = Std.int(FlxMath.wrap(col + dx, 0, gridCols - 1));
		// 切列后把 row 钳制到目标列有效行内（最后一列可能不满整列）
		if (dx != 0)
		{
			var rowsInTargetCol:Int = (col < gridCols - 1) ? gridRows : (options.length - (gridCols - 1) * gridRows);
			if (rowsInTargetCol < 1) rowsInTargetCol = 1;
			row = Std.int(FlxMath.bound(row, 0, rowsInTargetCol - 1));
		}

		// 上下：在当前列内环绕（到顶/底可继续绕回）
		if (dy != 0)
		{
			var rowsInCol:Int = (col < gridCols - 1) ? gridRows : (options.length - (gridCols - 1) * gridRows);
			if (rowsInCol < 1) rowsInCol = 1;
			row = FlxMath.wrap(row + dy, 0, rowsInCol - 1);
		}

		var target = col * gridRows + row;
		// 目标位置在最后一列可能不存在（该项不足整列），夹到列表末项
		if (target >= options.length)
		{
			target = options.length - 1;
		}
		curSelected = target;

		// 记住当前选中项，下次进入主设置界面时恢复（仅本次会话，重启游戏后重置）
		if (dx != 0 || dy != 0)
		{
			lastOptionsSelection = curSelected;
		}

		// 与 create 保持一致：启用虚拟方向键时选项列右移，避免被 LEFT_FULL 盖住
		var leftColX = OptionsConfig.LEFT_MARGIN;
		if (controls.mobileC)
		{
			leftColX = 340;
		}
		var rightColX = (gridCols > 1) ? (Math.floor(FlxG.width * 0.5) + 40) : leftColX;

		for (i in 0...grpOptions.length)
		{
			var icol:Int = Std.int(i / gridRows);
			var irow:Int = i % gridRows;
			var item = grpOptions.members[i];
			item.x = (icol == 0) ? leftColX : rightColX;
			item.y = startY + irow * itemSpacing;
			item.alpha = (i == curSelected) ? 1 : 0.6;
		}

		updateDescriptionText();
		FlxG.sound.play(Paths.sound('scrollMenu'));
	}

	// sideGif 飞出/回位动画
	private function triggerSideGifOut(doOut:Bool):Void
	{
		if (sideGif == null || !sideGif.exists || titleText == null) return;

		// 如果 gif 还没初始化完成（_sideGifHomeY 为 0 且 sideGif.visible 还为 false），跳过
		if (sideGif.visible == false && _sideGifHomeY == 0) return;

		if (_sideGifOutTween != null)
		{
			_sideGifOutTween.cancel();
			_sideGifOutTween.destroy();
			_sideGifOutTween = null;
		}

		var targetY:Float = doOut ? -sideGif.height - 20 : _sideGifHomeY;
		var targetX:Float = doOut ? (FlxG.width - titleText.width) / 2 : _titleHomeX;
		var dur:Float = 0.35;

		_sideGifOutTween = FlxTween.tween(sideGif, { y: targetY, alpha: doOut ? 0 : 1 }, dur,
			{ ease: FlxEase.quadInOut,
			  onComplete: function(_) { _sideGifOutTween = null; } });
		FlxTween.tween(titleText, { x: targetX }, dur, { ease: FlxEase.quadInOut });
	}

	// 更新描述文本
	private function updateDescriptionText():Void
	{
		descriptionText.text = optionDescriptions[curSelected];
		
		// 取消之前的tween
		if (descriptionTween != null) {
			descriptionTween.cancel();
			//descriptionTween.destroy();
		}
		
		// 重置位置并创建新的tween
		descriptionText.y = FlxG.height + OptionsConfig.DESC_Y_START;
		descriptionTween = FlxTween.tween(descriptionText,
			{y: FlxG.height + OptionsConfig.DESC_Y_END},
			OptionsConfig.TWEEN_DURATION,
			{
				ease: FlxEase.quadOut,
				onComplete: function(twn:FlxTween) {
					if (descriptionTween == twn)
						descriptionTween = null;
				}
			}
		);
	}

	public function refreshTexts()
	{
		// 更新选项文本
		for (i in 0...options.length)
		{
			var optionText = grpOptions.members[i];
			optionText.text = LanguageBasic.getPhrase('options_${options[i]}', options[i]);
		}

		// 更新描述文本
		if(curSelected >= 0 && curSelected < optionDescriptions.length) {
			descriptionText.text = optionDescriptions[curSelected];
		}

		// 重新计算选择器位置
		var selectedOption = grpOptions.members[curSelected];
		if (selectedOption != null)
		{
			selectorLeftTargetX = selectedOption.x - 63;
			selectorLeftTargetY = selectedOption.y;
			selectorRightTargetX = selectedOption.x + selectedOption.width + 15;
			selectorRightTargetY = selectedOption.y;
		}
	}

	override function draw()
	{
		// 在子状态打开时，强制选择器为完全透明（防止persistentUpdate=false时选择器可见）
		if (_inSubState && FlxG.state.subState != null)
		{
			// 更新选择器位置到当前选中项
			var selectedOption = grpOptions.members[curSelected];
			if (selectedOption != null)
			{
				selectorLeft.x = selectedOption.x - 63;
				selectorLeft.y = selectedOption.y;
				selectorRight.x = selectedOption.x + selectedOption.width + 15;
				selectorRight.y = selectedOption.y;
			}

			// 强制选择器为完全透明
			selectorLeft.alpha = 0;
			selectorRight.alpha = 0;
		}

		super.draw();
	}

	override function destroy()
	{
		if (descriptionTween != null)
		{
			descriptionTween.cancel();
			descriptionTween.destroy();
		}
		if (sideGif != null)
		{
			sideGif.destroy();
			sideGif = null;
		}
		ClientPrefs.loadPrefs();
		super.destroy();
	}
}