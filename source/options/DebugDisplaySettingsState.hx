package options;

import flixel.addons.display.FlxBackdrop;
import flixel.addons.display.shapes.FlxShapeCircle;
import flixel.math.FlxMath;
import flixel.math.FlxPoint;
import flixel.input.keyboard.FlxKey;
import flixel.input.touch.FlxTouch;
import flixel.util.FlxGradient;
import Std;
import Main;
import backend.CoolUtil;
import backend.Language;
import backend.Paths;
import backend.MusicBeatState;
import backend.ClientPrefs;
import debug.FunkinDebugDisplay;
import flixel.FlxSprite;
import flixel.FlxSubState;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import objects.Alphabet;

/**
 * 原版 FunkinDebugDisplay 风格的专属设置页。
 * 复用 KathyFPSCounterSettingsState 的列表 + 色轮/渐变/HEX 拾色交互，
 * 右侧用真实的 FunkinDebugDisplay 做实时预览。
 */
class DebugDisplaySettingsState extends MusicBeatState
{
	var curSelected:Int = 0;
	var scrollOffset:Int = 0;
	var scrollPx:Float = 0;
	var listStartY:Float = 150;
	var rowGap:Float = 4;
	var maxVisibleRows:Int = 10;
	var listViewHeight:Float = 0;
	var rowTops:Array<Float> = [];
	var rowHeights:Array<Float> = [];
	var scrollIndicatorUp:FlxSprite;
	var scrollIndicatorDown:FlxSprite;
	var onColorPicker:Bool = false;
	var currentColorType:String = "text";

	// 快速滚动/鼠标滚轮/触屏拖拽（仿 BaseOptionsMenu）
	var touchScrollActive:Bool = false; // 触屏拖拽进行中（拖拽/释放期间跳过阻尼滚动，避免抢位）
	var _lastScrollSndT:Float = 0; // 滚动音效限频
	#if mobile
	var touchScrollTouchID:Int = -1;
	var touchScrollStartY:Float = 0;
	var touchScrollStartCurSel:Float = 0; // 拖拽起点选中位（浮点）
	#end

	var hexTypeLine:FlxSprite;
	var hexTypeNum:Int = -1;
	var hexTypeVisibleTimer:Float = 0;
	var colorGradient:FlxSprite;
	var colorGradientSelector:FlxSprite;
	var colorWheel:FlxSprite;
	var colorWheelSelect:FlxShapeCircle;
	var colorPalette:FlxSprite;
	var alphabetR:Alphabet;
	var alphabetG:Alphabet;
	var alphabetB:Alphabet;
	var alphabetHex:Alphabet;
	var _storedColor:FlxColor;
	var holdingOnObj:FlxSprite;
	var bgSprite:FlxSprite;
	var darkOverlay:FlxSprite;
	var allowedTypeKeys:Map<FlxKey, String> = [
		ZERO => '0', ONE => '1', TWO => '2', THREE => '3', FOUR => '4', FIVE => '5', SIX => '6', SEVEN => '7', EIGHT => '8', NINE => '9',
		NUMPADZERO => '0', NUMPADONE => '1', NUMPADTWO => '2', NUMPADTHREE => '3', NUMPADFOUR => '4', NUMPADFIVE => '5', NUMPADSIX => '6',
		NUMPADSEVEN => '7', NUMPADEIGHT => '8', NUMPADNINE => '9', A => 'A', B => 'B', C => 'C', D => 'D', E => 'E', F => 'F'
	];

	var titleText:FlxText;
	var optionTexts:Array<FlxText>;
	var optionValues:Array<FlxText>;
	var tipTxt:FlxText;

	// 实时预览（直接挂到 stage 的 OpenFL Sprite）
	var previewDisplay:FunkinDebugDisplay;
	// 预览是否已过淡入转场允许显示（转场未结束前隐藏，避免盖住转场）
	var _previewRevealed:Bool = false;
	// 进场转场（CustomFadeTransition 子状态）关闭时的回调引用，用于转场结束后再显示预览
	var _onSubStateClosed:(FlxSubState)->Void = null;

	var options:Array<{name:String, desc:String, type:String}>;

	override function create()
	{
		super.create();

		options = [
			{name: Language.get("debug_mode_name"), desc: Language.get("debug_mode_desc"), type: "string"},
			{name: Language.get("debug_text_color_name"), desc: Language.get("debug_text_color_desc"), type: "color"},
			{name: Language.get("debug_bg_outer_name"), desc: Language.get("debug_bg_outer_desc"), type: "color"},
			{name: Language.get("debug_bg_inner_name"), desc: Language.get("debug_bg_inner_desc"), type: "color"},
			{name: Language.get("debug_bg_opacity_name"), desc: Language.get("debug_bg_opacity_desc"), type: "percent"},
			{name: Language.get("debug_font_size_name"), desc: Language.get("debug_font_size_desc"), type: "int"},
			{name: Language.get("debug_panel_width_name"), desc: Language.get("debug_panel_width_desc"), type: "int"},
			{name: Language.get("debug_update_delay_name"), desc: Language.get("debug_update_delay_desc"), type: "int"},
			{name: Language.get("debug_history_len_name"), desc: Language.get("debug_history_len_desc"), type: "int"},
			{name: Language.get("debug_graph_height_name"), desc: Language.get("debug_graph_height_desc"), type: "int"},
			{name: Language.get("debug_graph_text_gap_name"), desc: Language.get("debug_graph_text_gap_desc"), type: "int"},
			{name: Language.get("debug_line_thickness_name"), desc: Language.get("debug_line_thickness_desc"), type: "float"},
			{name: Language.get("debug_axis_color_name"), desc: Language.get("debug_axis_color_desc"), type: "color"},
			{name: Language.get("debug_axis_alpha_name"), desc: Language.get("debug_axis_alpha_desc"), type: "percent"},
			{name: Language.get("debug_show_bg_name"), desc: Language.get("debug_show_bg_desc"), type: "bool"},
			{name: Language.get("debug_show_fps_graph_name"), desc: Language.get("debug_show_fps_graph_desc"), type: "bool"},
			{name: Language.get("debug_show_avg_name"), desc: Language.get("debug_show_avg_desc"), type: "bool"},
			{name: Language.get("debug_show_low_name"), desc: Language.get("debug_show_low_desc"), type: "bool"},
			{name: Language.get("debug_show_gc_name"), desc: Language.get("debug_show_gc_desc"), type: "bool"},
			{name: Language.get("debug_show_task_name"), desc: Language.get("debug_show_task_desc"), type: "bool"},
			{name: Language.get("debug_graph_smooth_name"), desc: Language.get("debug_graph_smooth_desc"), type: "bool"},
			{name: Language.get("debug_font_name"), desc: Language.get("debug_font_desc"), type: "string"},
			{name: Language.get("debug_reset_defaults_name"), desc: Language.get("debug_reset_defaults_desc"), type: "button"}
		];

		bgSprite = new FlxSprite().loadGraphic(Paths.image('menuDesat'));
		bgSprite.color = 0xFF0077AA;
		bgSprite.screenCenter();
		bgSprite.antialiasing = ClientPrefs.data.antialiasing;
		add(bgSprite);

		darkOverlay = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, FlxColor.BLACK);
		darkOverlay.alpha = 0;
		add(darkOverlay);

		var grid:FlxBackdrop = new FlxBackdrop(CoolUtil.getCachedGrid(80, 80, 160, 160, true, 0x33FFFFFF, 0x0));
		grid.velocity.set(40, 40);
		grid.alpha = 0;
		FlxTween.tween(grid, {alpha: 1}, 0.5, {ease: FlxEase.quadOut});
		add(grid);

		var fontFile = Language.getGameFont();
		if (fontFile == null) fontFile = "vcr.ttf";
		var fontPath = Paths.font(fontFile);

		titleText = new FlxText(75, 45, 400, "Debug Display\nSettings", 32);
		titleText.setFormat(fontPath, 32, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		add(titleText);

		optionTexts = [];
		optionValues = [];
		rowTops = [];
		rowHeights = [];

		listStartY = 150;
		rowGap = 4;
		listViewHeight = (FlxG.height - listBottomMargin()) - listStartY;
		if (listViewHeight < 1) listViewHeight = 1;

		var cursorY:Float = listStartY;

		for (i in 0...options.length)
		{
			var text:FlxText = new FlxText(50, cursorY, 300, options[i].name, 22);
			text.setFormat(fontPath, 22, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			text.alpha = (i == 0) ? 1 : 0.6;
			add(text);
			optionTexts.push(text);

			var value:FlxText = new FlxText(360, cursorY, 260, getCurrentValue(i), 18);
			value.setFormat(fontPath, 18, valueColorFor(i), LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			value.alpha = (i == 0) ? 1 : 0.6;
			add(value);
			optionValues.push(value);

			// 行高基于该行各自的实际高度，而不是固定间距，避免更换字体后行与行重叠
			var rowHeight:Float = Math.max(text.height, value.height);
			rowTops.push(cursorY);
			rowHeights.push(rowHeight);
			cursorY += rowHeight + rowGap;
		}

		// 计算一屏内能放多少行（按各自行高累加）
		var acc:Float = 0;
		maxVisibleRows = 0;
		for (i in 0...rowHeights.length)
		{
			if (acc + rowHeights[i] + rowGap > listViewHeight) break;
			acc += rowHeights[i] + rowGap;
			maxVisibleRows++;
		}
		if (maxVisibleRows < 1) maxVisibleRows = 1;

		// 上下越界提醒指示箭头
		scrollIndicatorUp = makeScrollArrow(true);
		scrollIndicatorDown = makeScrollArrow(false);
		scrollIndicatorUp.x = 14;
		scrollIndicatorUp.y = listStartY;
		scrollIndicatorDown.x = 14;
		scrollIndicatorDown.y = listStartY + listViewHeight - scrollIndicatorDown.height;
		scrollIndicatorUp.visible = false;
		scrollIndicatorDown.visible = false;
		add(scrollIndicatorUp);
		add(scrollIndicatorDown);

		updateScrollPositions();

		tipTxt = new FlxText(20, FlxG.height - 82, 0, "", 16);
		tipTxt.setFormat(fontPath, 16, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		add(tipTxt);

		// 右侧预览区底板
		var rightBg:FlxSprite = new FlxSprite(700).makeGraphic(FlxG.width - 700, FlxG.height, 0xFF000000);
		rightBg.alpha = 0.4;
		add(rightBg);

		// 真实面板预览：直接挂到 stage（OpenFL Sprite，非 Flixel 对象）。
		// 位置/尺寸每帧用 Flixel 的 scaleMode 变换换算回 UI 坐标，避免随窗口大小漂移。
		previewDisplay = new FunkinDebugDisplay(0, 0);
		previewDisplay.x = 715;
		previewDisplay.y = 55;
		FlxG.stage.addChild(previewDisplay);
		pinPreview();

		// 预览挂在 stage 上层，会盖住 Flixel 的转场。进场时先隐藏预览，
		// 等进场转场（作为子状态）关闭后（任意转场样式都走到这一步）再显示。
		_previewRevealed = false;
		_onSubStateClosed = function(subState:FlxSubState):Void {
			if (!_previewRevealed) {
				_previewRevealed = true;
				refreshPreview();
			}
		}
		subStateClosed.add(_onSubStateClosed);

		// 本页临时隐藏全局 FPS 计数器（含 V-Slice 面板），退出时恢复。
		// 用全局 forceHideFPS 开关而非直接改 fpsVar.visible，因为窗口缩放会调用
		// updateFPSLayer()/updateFPSCounterVisibility() 强制重设可见性，直接隐藏会被覆盖。
		Main.forceHideFPS = true;
		if (Main.fpsVar != null) Main.fpsVar.visible = false;

		initColorPicker();
		refreshPreview();
		updateSelection();

		FlxG.mouse.visible = true;
		addTouchPad('LEFT_FULL', 'A_B_C');
		addTouchPadCamera();
	}

	override function destroy()
	{
		// 移除进场转场回调，避免在销毁后仍被触发
		if (_onSubStateClosed != null)
		{
			try { subStateClosed.remove(_onSubStateClosed); } catch (e:Dynamic) {}
			_onSubStateClosed = null;
		}
		// 恢复 FPS 计数器可见性（按 showFPS 设置重新计算）
		Main.forceHideFPS = false;
		Main.updateFPSCounterVisibility();
		if (previewDisplay != null)
		{
			try { FlxG.stage.removeChild(previewDisplay); } catch (e:Dynamic) {}
			previewDisplay = null;
		}
		super.destroy();
	}

	function refreshPreview():Void
	{
		if (previewDisplay == null) return;
		// 原实现无条件 mode= (setter 重建一次) + applySettings() (再重建一次)，每次切换整块重建两遍。
		// 现在：mode 变了由 setter 重建；没变则只在需要时 applySettings 一次。
		if (previewDisplay.mode != ClientPrefs.data.fpsDebugMode)
			previewDisplay.mode = ClientPrefs.data.fpsDebugMode;
		else
			previewDisplay.applySettings();
		// 取色器打开时临时隐藏预览，避免遮挡取色 UI
		previewDisplay.visible = _previewRevealed && !onColorPicker && ClientPrefs.data.fpsStyle == "V-Slice" && ClientPrefs.data.fpsDebugMode != "Off";
	}

	/**
	 * 把预览的 stage 位置/尺寸换算回 Flixel 虚拟坐标，这样窗口缩放后预览仍钉在 UI 的
	 * (715,55) 处。Flixel 渲染经 scaleMode 缩放 + FlxG.game 平移，故预览要套同样的变换。
	 */
	function pinPreview():Void
	{
		if (previewDisplay == null) return;
		if (FlxG.scaleMode == null || FlxG.scaleMode.scale == null) return;
		var s:flixel.math.FlxPoint = FlxG.scaleMode.scale;
		if (s == null || s.x <= 0 || s.y <= 0) return;
		var g = FlxG.game;
		if (g == null) return;
		// 预览自身作为 stage 子对象只做整体放大，保持横纵一致（取较小轴避免拉伸）
		var uni:Float = (s.x < s.y) ? s.x : s.y;
		previewDisplay.scaleX = previewDisplay.scaleY = 1.4 * uni;
		previewDisplay.x = g.x + 715 * s.x;
		previewDisplay.y = g.y + 55 * s.y;
	}

	private function initColorPicker():Void
	{
		colorGradient = FlxGradient.createGradientFlxSprite(60, 360, [FlxColor.WHITE, FlxColor.BLACK]);
		colorGradient.setPosition(780, 200);
		colorGradient.visible = false;
		add(colorGradient);

		colorGradientSelector = new FlxSprite(770, 200).makeGraphic(80, 10, FlxColor.WHITE);
		colorGradientSelector.offset.y = 5;
		colorGradientSelector.visible = false;
		add(colorGradientSelector);

		colorWheel = new FlxSprite(860, 200).loadGraphic(Paths.image('noteColorMenu/colorWheel'));
		colorWheel.antialiasing = true;
		colorWheel.visible = false;
		add(colorWheel);

		colorWheelSelect = new FlxShapeCircle(0, 0, 8, {thickness: 0}, FlxColor.WHITE);
		colorWheelSelect.offset.set(8, 8);
		colorWheelSelect.alpha = 0.6;
		colorWheelSelect.visible = false;
		add(colorWheelSelect);

		colorPalette = new FlxSprite(820, 580).loadGraphic(Paths.image('noteColorMenu/palette', false));
		colorPalette.scale.set(20, 20);
		colorPalette.updateHitbox();
		colorPalette.antialiasing = false;
		colorPalette.visible = false;
		add(colorPalette);

		alphabetR = makeColorAlphabet(910, 90);
		alphabetR.visible = false;
		add(alphabetR);

		alphabetG = makeColorAlphabet(1010, 90);
		alphabetG.visible = false;
		add(alphabetG);

		alphabetB = makeColorAlphabet(1110, 90);
		alphabetB.visible = false;
		add(alphabetB);

		alphabetHex = makeColorAlphabet(1010, 35);
		alphabetHex.visible = false;
		add(alphabetHex);

		hexTypeLine = new FlxSprite(44, 60).makeGraphic(5, 62, FlxColor.WHITE);
		hexTypeLine.visible = false;
		add(hexTypeLine);
	}

	private function makeColorAlphabet(x:Float = 0, y:Float = 0):Alphabet
	{
		var text:Alphabet = new Alphabet(x, y, '', true);
		text.alignment = CENTERED;
		text.setScale(0.5);
		return text;
	}

	function getColor():FlxColor
	{
		return switch(currentColorType)
		{
			case "bgOuter": ClientPrefs.data.fpsDebugBgOuter;
			case "bgInner": ClientPrefs.data.fpsDebugBgInner;
			case "axis": ClientPrefs.data.fpsDebugAxisColor;
			default: ClientPrefs.data.fpsDebugTextColor;
		}
	}

	function setColor(c:FlxColor):Void
	{
		switch(currentColorType)
		{
			case "bgOuter": ClientPrefs.data.fpsDebugBgOuter = c;
			case "bgInner": ClientPrefs.data.fpsDebugBgInner = c;
			case "axis": ClientPrefs.data.fpsDebugAxisColor = c;
			default: ClientPrefs.data.fpsDebugTextColor = c;
		}
	}

	private function getCurrentValue(index:Int):String
	{
		switch(index)
		{
			case 0: return ClientPrefs.data.fpsDebugMode;
			case 1: return "#" + StringTools.hex(ClientPrefs.data.fpsDebugTextColor, 6);
			case 2: return "#" + StringTools.hex(ClientPrefs.data.fpsDebugBgOuter, 6);
			case 3: return "#" + StringTools.hex(ClientPrefs.data.fpsDebugBgInner, 6);
			case 4: return Std.int(ClientPrefs.data.fpsDebugBgOpacity * 100) + "%";
			case 5: return Std.string(ClientPrefs.data.fpsDebugFontSize);
			case 6: return Std.string(ClientPrefs.data.fpsDebugPanelWidth);
			case 7: return Std.string(ClientPrefs.data.fpsDebugUpdateDelay) + "ms";
			case 8: return Std.string(ClientPrefs.data.fpsDebugHistoryMax);
			case 9: return Std.string(ClientPrefs.data.fpsDebugGraphHeight);
			case 10: return Std.string(ClientPrefs.data.fpsDebugGraphTextGap);
			case 11: return Std.string(ClientPrefs.data.fpsDebugLineThickness);
			case 12: return "#" + StringTools.hex(ClientPrefs.data.fpsDebugAxisColor, 6);
			case 13: return Std.int(ClientPrefs.data.fpsDebugAxisAlpha * 100) + "%";
			case 14: return ClientPrefs.data.fpsDebugBgEnabled ? Language.get('enabled') : Language.get('disabled');
			case 15: return ClientPrefs.data.fpsDebugShowFPSGraph ? Language.get('enabled') : Language.get('disabled');
			case 16: return ClientPrefs.data.fpsDebugShowAvg ? Language.get('enabled') : Language.get('disabled');
			case 17: return ClientPrefs.data.fpsDebugShowLow ? Language.get('enabled') : Language.get('disabled');
			case 18: return ClientPrefs.data.fpsDebugShowGCMem ? Language.get('enabled') : Language.get('disabled');
			case 19: return ClientPrefs.data.fpsDebugShowTaskMem ? Language.get('enabled') : Language.get('disabled');
			case 20: return ClientPrefs.data.fpsDebugGraphSmooth ? Language.get('enabled') : Language.get('disabled');
			case 21: return ClientPrefs.data.fpsDebugFont;
			case 22: return Language.get('debug_reset_defaults_action');
		}
		return "";
	}

	private function valueColorFor(idx:Int):FlxColor
	{
		switch(idx)
		{
			case 1: return ClientPrefs.data.fpsDebugTextColor;
			case 2: return ClientPrefs.data.fpsDebugBgOuter;
			case 3: return ClientPrefs.data.fpsDebugBgInner;
			case 12: return ClientPrefs.data.fpsDebugAxisColor;
			case 14: return ClientPrefs.data.fpsDebugBgEnabled ? OptionsConfig.OPTION_ON_COLOR : OptionsConfig.OPTION_OFF_COLOR;
			case 15: return ClientPrefs.data.fpsDebugShowFPSGraph ? OptionsConfig.OPTION_ON_COLOR : OptionsConfig.OPTION_OFF_COLOR;
			case 16: return ClientPrefs.data.fpsDebugShowAvg ? OptionsConfig.OPTION_ON_COLOR : OptionsConfig.OPTION_OFF_COLOR;
			case 17: return ClientPrefs.data.fpsDebugShowLow ? OptionsConfig.OPTION_ON_COLOR : OptionsConfig.OPTION_OFF_COLOR;
			case 18: return ClientPrefs.data.fpsDebugShowGCMem ? OptionsConfig.OPTION_ON_COLOR : OptionsConfig.OPTION_OFF_COLOR;
			case 19: return ClientPrefs.data.fpsDebugShowTaskMem ? OptionsConfig.OPTION_ON_COLOR : OptionsConfig.OPTION_OFF_COLOR;
			case 20: return ClientPrefs.data.fpsDebugGraphSmooth ? OptionsConfig.OPTION_ON_COLOR : OptionsConfig.OPTION_OFF_COLOR;
		}
		return FlxColor.WHITE;
	}

	function updateColorPickerUI():Void
	{
		var color:FlxColor = getColor();

		alphabetR.text = Std.string(color.red);
		alphabetG.text = Std.string(color.green);
		alphabetB.text = Std.string(color.blue);
		alphabetHex.text = color.toHexString(false, false);
		for (letter in alphabetHex.letters)
			letter.color = color;

		colorWheel.color = FlxColor.fromHSB(0, 0, color.brightness);
		colorWheelSelect.setPosition(colorWheel.x + colorWheel.width / 2, colorWheel.y + colorWheel.height / 2);
		if (color.brightness != 0)
		{
			var hueWrap:Float = color.hue * Math.PI / 180;
			colorWheelSelect.x += Math.sin(hueWrap) * colorWheel.width / 2 * color.saturation;
			colorWheelSelect.y -= Math.cos(hueWrap) * colorWheel.height / 2 * color.saturation;
		}
		colorGradientSelector.y = colorGradient.y + colorGradient.height * (1 - color.brightness);
	}

	function setColorPickerVisible(visible:Bool):Void
	{
		onColorPicker = visible;

		colorGradient.visible = visible;
		colorGradientSelector.visible = visible;
		colorWheel.visible = visible;
		colorWheelSelect.visible = visible;
		colorPalette.visible = visible;
		alphabetR.visible = visible;
		alphabetG.visible = visible;
		alphabetB.visible = visible;
		alphabetHex.visible = visible;
		hexTypeLine.visible = false;
		hexTypeNum = -1;

		if (visible)
		{
			_storedColor = getColor();
			updateColorPickerUI();
		}
		for (i in 0...optionTexts.length)
		{
			if (visible)
			{
				optionTexts[i].alpha = (i == curSelected) ? 1 : 0.25;
				optionValues[i].alpha = (i == curSelected) ? 1 : 0.25;
			}
			else
			{
				optionTexts[i].alpha = (i == curSelected) ? 1 : 0.6;
				optionValues[i].alpha = (i == curSelected) ? 1 : 0.6;
			}
		}
		tipTxt.text = visible
			? "Click the wheel / gradient / palette, type HEX digits.\nENTER to confirm, C to reset the color."
			: options[curSelected].desc;
		refreshPreview();
	}

	function updateSelection():Void
	{
		for (i in 0...optionTexts.length)
		{
			optionTexts[i].alpha = (i == curSelected) ? 1 : 0.6;
			optionValues[i].alpha = (i == curSelected) ? 1 : 0.6;
		}
		tipTxt.text = options[curSelected].desc;
	}

	/** 根据 scrollPx 脚各行的实际行高平滑重排 Y 坐标，并隐藏超出可视区的行 */
	function updateScrollPositions():Void
	{
		for (i in 0...optionTexts.length)
		{
			var y:Float = rowTops[i] - scrollPx;
			optionTexts[i].y = y;
			optionValues[i].y = y;
			var visible:Bool = (y + rowHeights[i]) > listStartY && y < (listStartY + listViewHeight);
			optionTexts[i].visible = visible;
			optionValues[i].visible = visible;
		}
		scrollIndicatorUp.visible = scrollOffset > 0;
		scrollIndicatorDown.visible = (scrollOffset + maxVisibleRows) < options.length;
	}

	/** 底部为虚拟按键预留的空间（移动端更大） */
	private inline function listBottomMargin():Float
	{
		return #if mobile 235 #else 100 #end;
	}

	/** 绘制一个实心三角指示箭头 */
	private function makeScrollArrow(pointsUp:Bool):FlxSprite
	{
		var w:Int = 14, h:Int = 9;
		var s:FlxSprite = new FlxSprite().makeGraphic(w, h, FlxColor.TRANSPARENT, true);
		var px:openfl.display.BitmapData = s.pixels;
		var maxHalf:Int = Math.floor((w - 1) / 2);
		for (row in 0...h)
		{
			var t:Int = pointsUp ? row : (h - 1 - row);
			var half:Int = Math.floor(t * maxHalf / (h - 1));
			if (half > maxHalf) half = maxHalf;
			var cx:Int = Math.floor((w - 1) / 2);
			for (dx in (-half)...(half + 1))
			{
				var x:Int = cx + dx;
				if (x >= 0 && x < w) px.setPixel32(x, row, 0xFFFFFFFF);
			}
		}
		s.alpha = 0.9;
		return s;
	}

	/** 导航后滚动窗口，保证当前选中行始终可见 */
	function keepRowVisible():Void
	{
		if (curSelected < scrollOffset) scrollOffset = curSelected;
		else if (curSelected >= scrollOffset + maxVisibleRows) scrollOffset = curSelected - maxVisibleRows + 1;
		if (scrollOffset < 0) scrollOffset = 0;
		var maxScroll:Int = options.length - maxVisibleRows;
		if (maxScroll < 0) maxScroll = 0;
		if (scrollOffset > maxScroll) scrollOffset = maxScroll;
	}

	override function update(elapsed:Float)
	{
		super.update(elapsed);

		// 列表滚动过渡：向目标偏移做阻尼逼近，实现丝滑滑动
		var targetPx:Float = rowTops[scrollOffset] - listStartY;
		if (!touchScrollActive && scrollPx != targetPx)
		{
			scrollPx += (targetPx - scrollPx) * FlxMath.bound(elapsed * 14, 0, 1);
			if (Math.abs(targetPx - scrollPx) < 0.5) scrollPx = targetPx;
			updateScrollPositions();
		}

		// 窗口可能任意时刻缩放，每帧把预览钉回 UI 坐标
		pinPreview();

		if (touchPad == null)
		{
			addTouchPad('LEFT_FULL', 'A_B_C');
			addTouchPadCamera();
		}
		if (touchPad != null) touchPad.buttonA.visible = !onColorPicker;

		// 触摸板 C 键 或 键盘 R 键：重置当前选项 / 拾色器中重置当前颜色
		if ((touchPad != null && touchPad.buttonC != null && touchPad.buttonC.justPressed) || FlxG.keys.justPressed.R)
		{
			if (onColorPicker) resetCurrentColorToDefault();
			else resetOptionToDefault(curSelected);
			FlxG.sound.play(Paths.sound('scrollMenu'));
		}

		if (onColorPicker) updateColorPicker(elapsed);
		else
		{
	#if !mobile
			// 鼠标滚轮滚动（按住 Shift 快速滚动 ×4）
			if (FlxG.mouse.wheel != 0)
			{
				var mult:Int = FlxG.keys.pressed.SHIFT ? 4 : 1;
				navigateSelection((FlxG.mouse.wheel > 0 ? -1 : 1) * mult);
			}
			else if (FlxG.mouse.justPressed)
			{
				handleMouseSelect();
			}
	#end
	#if mobile
			handleTouchScroll();
	#end
			updateSettingsList();
		}

		if (controls.BACK)
		{
			if (onColorPicker)
			{
				setColorPickerVisible(false);
				FlxG.sound.play(Paths.sound('cancelMenu'));
			}
			else
			{
				// 离场前先隐藏预览并解绑进场回调，避免盖住离场转场（转场是 Flixel 子层，
				// 预览挂在 stage 上层）。否则离场转场结束后回调还会把预览重新显示出来。
				_previewRevealed = false;
				if (previewDisplay != null) previewDisplay.visible = false;
				if (_onSubStateClosed != null)
				{
					try { subStateClosed.remove(_onSubStateClosed); } catch (e:Dynamic) {}
					_onSubStateClosed = null;
				}
				FlxG.mouse.visible = false;
				ClientPrefs.saveSettings();
				if (Main.fpsVar != null) Main.fpsVar.applySettings();
				MusicBeatState.switchState(new OptionsState());
			}
		}
	}

	function updateSettingsList():Void
	{
		// Shift 快速滚动（每次跳 4 项），与 BaseOptionsMenu/LanguageSubState 一致
		var mult:Int = FlxG.keys.pressed.SHIFT ? 4 : 1;

		if (controls.UI_UP_P)
		{
			navigateSelection(-1 * mult);
		}
		else if (controls.UI_DOWN_P)
		{
			navigateSelection(1 * mult);
		}

		if (controls.UI_LEFT_P || controls.UI_RIGHT_P)
		{
			adjustOption(controls.UI_LEFT_P ? -1 : 1);
			optionValues[curSelected].text = getCurrentValue(curSelected);
			optionValues[curSelected].color = valueColorFor(curSelected);
			refreshPreview();
			FlxG.sound.play(Paths.sound('scrollMenu'));
		}

		if (controls.ACCEPT)
		{
			var t = options[curSelected].type;
			if (t == "color")
			{
				currentColorType = switch(curSelected)
				{
					case 2: "bgOuter";
					case 3: "bgInner";
					case 12: "axis";
					default: "text";
				}
				setColorPickerVisible(true);
				FlxG.sound.play(Paths.sound('scrollMenu'));
			}
			else if (t == "bool")
			{
				toggleBoolOption(curSelected);
				optionValues[curSelected].text = getCurrentValue(curSelected);
				optionValues[curSelected].color = valueColorFor(curSelected);
				refreshPreview();
				FlxG.sound.play(Paths.sound('scrollMenu'));
			}
			else if (t == "string")
			{
				if (curSelected == 0)
				{
					var modes:Array<String> = ["Off", "Simple", "Advanced"];
					var i:Int = modes.indexOf(ClientPrefs.data.fpsDebugMode);
					ClientPrefs.data.fpsDebugMode = modes[(i + 1) % modes.length];
				}
				else
				{
					ClientPrefs.data.fpsDebugFont = ClientPrefs.data.fpsDebugFont == "VCR" ? "Quantico" : "VCR";
				}
				optionValues[curSelected].text = getCurrentValue(curSelected);
				optionValues[curSelected].color = valueColorFor(curSelected);
				refreshPreview();
				FlxG.sound.play(Paths.sound('scrollMenu'));
			}
			else if (t == "float")
			{
				ClientPrefs.data.fpsDebugLineThickness = (ClientPrefs.data.fpsDebugLineThickness >= 5) ? 1 : ClientPrefs.data.fpsDebugLineThickness + 1;
				optionValues[curSelected].text = getCurrentValue(curSelected);
				optionValues[curSelected].color = valueColorFor(curSelected);
				refreshPreview();
				FlxG.sound.play(Paths.sound('scrollMenu'));
			}
			else if (t == "button")
			{
				resetDebugSettings();
				FlxG.sound.play(Paths.sound('confirmMenu'));
			}
		}
	}

	/** 按 delta 改变选中项（回环），并保证选中行在可视区内；仿 BaseOptionsMenu.changeSelection */
	private function navigateSelection(delta:Int):Void
	{
		curSelected = FlxMath.wrap(curSelected + delta, 0, options.length - 1);
		updateSelection();
		keepRowVisible();
		var now:Float = FlxG.game.ticks / 1000.0;
		if (now - _lastScrollSndT >= 0.04)
		{
			FlxG.sound.play(Paths.sound('scrollMenu'));
			_lastScrollSndT = now;
		}
	}

	/** 桌面端：鼠标点击选项行，选中对应行 */
	private function handleMouseSelect():Void
	{
		for (i in 0...options.length)
		{
			var y:Float = rowTops[i] - scrollPx;
			if (y + rowHeights[i] <= listStartY || y >= listStartY + listViewHeight) continue; // 只处理可见行
			if (FlxG.mouse.x >= 40 && FlxG.mouse.x <= 700 &&
				FlxG.mouse.y >= y && FlxG.mouse.y <= y + rowHeights[i])
			{
				if (curSelected != i)
				{
					curSelected = i;
					updateSelection();
					keepRowVisible();
					FlxG.sound.play(Paths.sound('scrollMenu'));
				}
				break;
			}
		}
	}

#if mobile
	/** 移动端：在选项显示范围内拖拽滚动，手指带动选中项，松手后由 keepRowVisible 收尾 */
	private function handleTouchScroll():Void
	{
		if (!touchScrollActive)
		{
			for (t in FlxG.touches.list)
			{
				if (!t.justPressed) continue;
				// 避开虚拟按键触摸板，避免冲突
				if (touchPad != null && touchPadCam != null && t.overlaps(touchPad, touchPadCam)) continue;
				// 仅在选项显示区域内（overlap 检测）触摸才启动滚动
				if (t.x < 30 || t.x > 700 || t.y < listStartY || t.y > listStartY + listViewHeight) continue;
				touchScrollActive = true;
			touchScrollTouchID = t.touchPointID;
				touchScrollStartY = t.y;
				touchScrollStartCurSel = curSelected;
				break;
			}
			if (!touchScrollActive) return;
		}

		var active:FlxTouch = null;
		for (t in FlxG.touches.list) if (t.touchPointID == touchScrollTouchID) { active = t; break; }

		if (active == null || active.justReleased || active.released)
		{
			// 松手：结束拖拽，停止抢占阻尼滚动
			touchScrollActive = false;
			touchScrollTouchID = -1;
			return;
		}

		// 手指上滑（y 减小）→ 选中项增大（列表内容上移），以平均行距 1:1 映射
		var dragPx:Float = touchScrollStartY - active.y;
		var totalH:Float = (rowTops[rowTops.length - 1] + rowHeights[rowHeights.length - 1]) - rowTops[0];
		var pitch:Float = Math.max(1, totalH / options.length);
		var targetSel:Float = touchScrollStartCurSel + dragPx / pitch;
		if (targetSel < 0) targetSel = 0;
		else if (targetSel > options.length - 1) targetSel = options.length - 1;
		var newSel:Int = Math.round(targetSel);
		if (newSel < 0) newSel = 0;
		else if (newSel >= options.length) newSel = options.length - 1;

		if (newSel != curSelected)
		{
			curSelected = newSel;
			updateSelection();
			keepRowVisible();
			updateScrollPositions();
			var now:Float = FlxG.game.ticks / 1000.0;
			if (now - _lastScrollSndT >= 0.04)
			{
				FlxG.sound.play(Paths.sound('scrollMenu'));
				_lastScrollSndT = now;
			}
		}
	}
#end

	/** 把所有 fpsDebug* 设置恢复到默认值，并立即保存、刷新界面与预览 */
	function resetDebugSettings():Void
	{
		var defaults = ClientPrefs.defaultData;
		var changed = false;
		for (field in Reflect.fields(defaults))
		{
			if (StringTools.startsWith(field, "fpsDebug"))
			{
				Reflect.setField(ClientPrefs.data, field, Reflect.field(defaults, field));
				changed = true;
			}
		}
		if (!changed) return;
		if (Main.fpsVar != null) Main.fpsVar.applySettings();
		for (i in 0...optionValues.length)
			optionValues[i].text = getCurrentValue(i);
		for (i in 0...optionValues.length)
			optionValues[i].color = valueColorFor(i);
		refreshPreview();
		ClientPrefs.saveSettings();
	}

	/** 把当前选中的单个选项重置为默认值 */
	private function resetOptionToDefault(index:Int):Void
	{
		switch(index)
		{
			case 0: ClientPrefs.data.fpsDebugMode = "Simple";
			case 1: ClientPrefs.data.fpsDebugTextColor = 0xFFFFFFFF;
			case 2: ClientPrefs.data.fpsDebugBgOuter = 0xFF3D3F41;
			case 3: ClientPrefs.data.fpsDebugBgInner = 0xFF2C2F30;
			case 4: ClientPrefs.data.fpsDebugBgOpacity = 0.5;
			case 5: ClientPrefs.data.fpsDebugFontSize = 12;
			case 6: ClientPrefs.data.fpsDebugPanelWidth = 234;
			case 7: ClientPrefs.data.fpsDebugUpdateDelay = 100;
			case 8: ClientPrefs.data.fpsDebugHistoryMax = 100;
			case 9: ClientPrefs.data.fpsDebugGraphHeight = 25;
			case 10: ClientPrefs.data.fpsDebugGraphTextGap = 8;
			case 11: ClientPrefs.data.fpsDebugLineThickness = 1;
			case 12: ClientPrefs.data.fpsDebugAxisColor = 0xFFFFFFFF;
			case 13: ClientPrefs.data.fpsDebugAxisAlpha = 0.5;
			case 14: ClientPrefs.data.fpsDebugBgEnabled = true;
			case 15: ClientPrefs.data.fpsDebugShowFPSGraph = true;
			case 16: ClientPrefs.data.fpsDebugShowAvg = true;
			case 17: ClientPrefs.data.fpsDebugShowLow = true;
			case 18: ClientPrefs.data.fpsDebugShowGCMem = true;
			case 19: ClientPrefs.data.fpsDebugShowTaskMem = true;
			case 20: ClientPrefs.data.fpsDebugGraphSmooth = true;
			case 21: ClientPrefs.data.fpsDebugFont = "VCR";
		}
		optionValues[index].text = getCurrentValue(index);
		optionValues[index].color = valueColorFor(index);
		refreshPreview();
	}

	/** 把正在编辑的颜色重置为默认值 */
	private function resetCurrentColorToDefault():Void
	{
		switch(currentColorType)
		{
			case "bgOuter": ClientPrefs.data.fpsDebugBgOuter = 0xFF3D3F41;
			case "bgInner": ClientPrefs.data.fpsDebugBgInner = 0xFF2C2F30;
			case "axis": ClientPrefs.data.fpsDebugAxisColor = 0xFFFFFFFF;
			default: ClientPrefs.data.fpsDebugTextColor = 0xFFFFFFFF;
		}
		_storedColor = getColor();
		var idx:Int = switch(currentColorType)
		{
			case "bgOuter": 2;
			case "bgInner": 3;
			case "axis": 12;
			default: 1;
		}
		optionValues[idx].text = getCurrentValue(idx);
		optionValues[idx].color = valueColorFor(idx);
		updateColorPickerUI();
		refreshPreview();
	}

	function adjustOption(change:Int):Void
	{
		switch(curSelected)
		{
			case 4: ClientPrefs.data.fpsDebugBgOpacity = FlxMath.bound(ClientPrefs.data.fpsDebugBgOpacity + change * 0.05, 0, 1);
			case 5: ClientPrefs.data.fpsDebugFontSize = Std.int(FlxMath.bound(ClientPrefs.data.fpsDebugFontSize + change, 6, 48));
			case 6: ClientPrefs.data.fpsDebugPanelWidth = Std.int(FlxMath.bound(ClientPrefs.data.fpsDebugPanelWidth + change * 5, 100, 600));
			case 7: ClientPrefs.data.fpsDebugUpdateDelay = Std.int(FlxMath.bound(ClientPrefs.data.fpsDebugUpdateDelay + change * 10, 16, 1000));
			case 8: ClientPrefs.data.fpsDebugHistoryMax = Std.int(FlxMath.bound(ClientPrefs.data.fpsDebugHistoryMax + change * 10, 10, 500));
			case 9: ClientPrefs.data.fpsDebugGraphHeight = Std.int(FlxMath.bound(ClientPrefs.data.fpsDebugGraphHeight + change, 10, 80));
			case 10: ClientPrefs.data.fpsDebugGraphTextGap = Std.int(FlxMath.bound(ClientPrefs.data.fpsDebugGraphTextGap + change, 0, 40));
			case 11: ClientPrefs.data.fpsDebugLineThickness = FlxMath.bound(ClientPrefs.data.fpsDebugLineThickness + change * 0.5, 0.5, 8);
			case 13: ClientPrefs.data.fpsDebugAxisAlpha = FlxMath.bound(ClientPrefs.data.fpsDebugAxisAlpha + change * 0.05, 0, 1);
			case 21: ClientPrefs.data.fpsDebugFont = ClientPrefs.data.fpsDebugFont == "VCR" ? "Quantico" : "VCR";
		}
	}

	function toggleBoolOption(index:Int):Void
	{
		switch(index)
		{
			case 14: ClientPrefs.data.fpsDebugBgEnabled = !ClientPrefs.data.fpsDebugBgEnabled;
			case 15: ClientPrefs.data.fpsDebugShowFPSGraph = !ClientPrefs.data.fpsDebugShowFPSGraph;
			case 16: ClientPrefs.data.fpsDebugShowAvg = !ClientPrefs.data.fpsDebugShowAvg;
			case 17: ClientPrefs.data.fpsDebugShowLow = !ClientPrefs.data.fpsDebugShowLow;
			case 18: ClientPrefs.data.fpsDebugShowGCMem = !ClientPrefs.data.fpsDebugShowGCMem;
			case 19: ClientPrefs.data.fpsDebugShowTaskMem = !ClientPrefs.data.fpsDebugShowTaskMem;
			case 20: ClientPrefs.data.fpsDebugGraphSmooth = !ClientPrefs.data.fpsDebugGraphSmooth;
		}
	}

	// ============ 颜色拾取 ============

	function updateColorPicker(elapsed:Float):Void
	{
		if (hexTypeNum > -1)
		{
			var keyPressed:FlxKey = cast(FlxG.keys.firstJustPressed(), FlxKey);
			hexTypeVisibleTimer += elapsed;
			var changed:Bool = false;

			if (changed = FlxG.keys.justPressed.LEFT) hexTypeNum--;
			else if (changed = FlxG.keys.justPressed.RIGHT) hexTypeNum++;
			else if (allowedTypeKeys.exists(keyPressed))
			{
				var curColor:String = alphabetHex.text;
				var newColor:String = curColor.substring(0, hexTypeNum) + allowedTypeKeys.get(keyPressed) + curColor.substring(hexTypeNum + 1);
				var color:Null<FlxColor> = FlxColor.fromString('#' + newColor);
				if (color != null)
				{
					setColor(color);
					_storedColor = color;
					updateColorPickerUI();
					refreshPreview();
					updateOptionValues();
				}
				hexTypeNum++;
				changed = true;
			}
			else if (FlxG.keys.justPressed.ENTER) hexTypeNum = -1;

			if (changed)
			{
				if (hexTypeNum > 5) hexTypeNum = -1;
				else if (hexTypeNum < 0) hexTypeNum = 0;
				hexTypeLine.visible = hexTypeNum > -1;
				centerHexTypeLine();
				FlxG.sound.play(Paths.sound('scrollMenu'));
			}
			if (hexTypeNum != -1)
				hexTypeLine.visible = Math.floor(hexTypeVisibleTimer * 2) % 2 == 0;
		}
		else
		{
			var moved:Bool = FlxG.mouse.justMoved;
			var pressed:Bool = FlxG.mouse.justPressed;

			if (pressed)
			{
				if (FlxG.mouse.overlaps(colorWheel)) { _storedColor = getColor(); holdingOnObj = colorWheel; }
				else if (FlxG.mouse.overlaps(colorGradient)) { _storedColor = getColor(); holdingOnObj = colorGradient; }
				else if (FlxG.mouse.overlaps(colorPalette))
				{
					// 从调色板点选预设颜色
					var px = Std.int((FlxG.mouse.x - colorPalette.x) / colorPalette.scale.x);
					var py = Std.int((FlxG.mouse.y - colorPalette.y) / colorPalette.scale.y);
					var newColorInt = colorPalette.pixels.getPixel32(px, py);
					var newColor = FlxColor.fromRGB((newColorInt >> 16) & 0xFF, (newColorInt >> 8) & 0xFF, newColorInt & 0xFF);
					setColor(newColor);
					_storedColor = newColor;
					updateColorPickerUI();
					refreshPreview();
					updateOptionValues();
				}
				else if (pointerOnHex()) { hexTypeNum = 0; hexTypeLine.visible = true; }
				else holdingOnObj = null;
			}

			if (holdingOnObj != null)
			{
				if (FlxG.mouse.justReleased)
				{
					holdingOnObj = null;
					_storedColor = getColor();
					updateOptionValues();
				}
				else if (moved || pressed)
				{
					if (holdingOnObj == colorGradient)
					{
						var b:Float = 1 - FlxMath.bound((FlxG.mouse.y - colorGradient.y) / colorGradient.height, 0, 1);
						setColor(_storedColor.brightness == 0 ? FlxColor.fromRGBFloat(b, b, b) : FlxColor.fromHSB(_storedColor.hue, _storedColor.saturation, b));
					}
					else if (holdingOnObj == colorWheel)
					{
						var center:FlxPoint = new FlxPoint(colorWheel.x + colorWheel.width / 2, colorWheel.y + colorWheel.height / 2);
						var mouse:FlxPoint = FlxG.mouse.getScreenPosition();
						var hue:Float = FlxMath.wrap(FlxMath.wrap(Std.int(mouse.degreesTo(center)), 0, 360) - 90, 0, 360);
						var sat:Float = FlxMath.bound(mouse.dist(center) / colorWheel.width * 2, 0, 1);
						setColor(sat == 0 ? FlxColor.fromRGBFloat(_storedColor.brightness, _storedColor.brightness, _storedColor.brightness) : FlxColor.fromHSB(hue, sat, _storedColor.brightness));
					}
					updateColorPickerUI();
					refreshPreview();
					updateOptionValues();
				}
			}
		}
	}

	function pointerOnHex():Bool
	{
		if (alphabetHex.letters.length == 0) return false;
		var p:FlxPoint = FlxG.mouse.getScreenPosition();
		return p.y >= alphabetHex.y - 30 && p.y < alphabetHex.y + 50;
	}

	function centerHexTypeLine():Void
	{
		if (hexTypeNum > 0) hexTypeNum = Std.int(Math.max(0, Math.min(hexTypeNum, alphabetHex.letters.length - 1)));
		if (alphabetHex.letters.length == 0) return;
		var letter = alphabetHex.letters[Std.int(Math.max(0, Math.min(hexTypeNum, alphabetHex.letters.length - 1)))];
		hexTypeLine.x = letter.x - letter.offset.x + letter.width + 5;
	}

	private function updateOptionValues():Void
	{
		for (i in 0...optionValues.length)
		{
			optionValues[i].text = getCurrentValue(i);
			optionValues[i].color = valueColorFor(i);
		}
	}
}