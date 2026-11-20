package options;

import flixel.addons.display.FlxBackdrop;
import flixel.addons.display.FlxGridOverlay;
import backend.CoolUtil;
import flixel.addons.display.shapes.FlxShapeCircle;
import flixel.input.keyboard.FlxKey;
import flixel.input.gamepad.FlxGamepadInputID;
import flixel.input.touch.FlxTouch;
import lime.system.Clipboard;
import flixel.util.FlxGradient;
import Std;
import Main;
import backend.Language;
import backend.Paths;
import backend.MusicBeatState;

class KathyFPSCounterSettingsState extends MusicBeatState
{
	var curSelected:Int = 0;
	var scrollOffset:Int = 0;
	var scrollPx:Float = 0;
	var rowGap:Float = 4;
	var rowTops:Array<Float> = [];
	var rowHeights:Array<Float> = [];
	var listStartY:Float = 140;
	var maxVisibleRows:Int = 10;
	var listViewHeight:Float = 0;
	var scrollIndicatorUp:FlxSprite;
	var scrollIndicatorDown:FlxSprite;
	var onColorPicker:Bool = false;
	var currentColorType:String = "text";

	var hexTypeLine:FlxSprite;
	var hexTypeNum:Int = -1;
	var hexTypeVisibleTimer:Float = 0;
	var copyButton:FlxSprite;
	var pasteButton:FlxSprite;
	var colorGradient:FlxSprite;
	var colorGradientSelector:FlxSprite;
	var colorPalette:FlxSprite;
	var colorWheel:FlxSprite;
	var colorWheelSelector:FlxSprite;
	var alphabetR:Alphabet;
	var alphabetG:Alphabet;
	var alphabetB:Alphabet;
	var alphabetHex:Alphabet;
	var _storedColor:FlxColor;
	var holdingOnObj:FlxSprite;
	var allowedTypeKeys:Map<FlxKey, String> = [
		ZERO => '0', ONE => '1', TWO => '2', THREE => '3', FOUR => '4', FIVE => '5', SIX => '6', SEVEN => '7', EIGHT => '8', NINE => '9',
		NUMPADZERO => '0', NUMPADONE => '1', NUMPADTWO => '2', NUMPADTHREE => '3', NUMPADFOUR => '4', NUMPADFIVE => '5', NUMPADSIX => '6',
		NUMPADSEVEN => '7', NUMPADEIGHT => '8', NUMPADNINE => '9', A => 'A', B => 'B', C => 'C', D => 'D', E => 'E', F => 'F'
	];

	var titleText:FlxText;
	var optionTexts:Array<FlxText>;
	var optionValues:Array<FlxText>;
	var bgSprite:FlxSprite;
	var darkOverlay:FlxSprite;
	var tipTxt:FlxText;
	var previewText:FlxText;
	var previewBg:FlxSprite;
	var leftPanelElements:Array<Dynamic>;

	var _activeTweens:Array<FlxTween> = [];

	var controllerPointer:FlxSprite;
	var _lastControllerMode:Bool = false;

	// 快速滚动/鼠标滚轮/触屏拖拽（仿 BaseOptionsMenu）
	var touchScrollActive:Bool = false; // 触屏拖拽进行中（拖拽/释放期间跳过阻尼滚动，避免抢位）
	var _lastScrollSndT:Float = 0; // 滚动音效限频
	#if mobile
	var touchScrollTouchID:Int = -1;
	var touchScrollStartY:Float = 0;
	var touchScrollStartCurSel:Float = 0; // 拖拽起点选中位（浮点）
#end

	var options:Array<{name:String, desc:String, type:String, min:Null<Dynamic>, max:Null<Dynamic>, change:Null<Dynamic>}>;

	override function create()
	{
		super.create();

		#if DISCORD_ALLOWED
		DiscordClient.changePresence("Kathy FPS Counter Settings Menu", null);
		#end

		options = [
			{name: Language.get("fps_text_color_name"), desc: Language.get("fps_text_color_desc"), type: "color", min: null, max: null, change: null},
			{name: Language.get("fps_bg_color_name"), desc: Language.get("fps_bg_color_desc"), type: "color", min: null, max: null, change: null},
			{name: Language.get("fps_text_opacity_name"), desc: Language.get("fps_text_opacity_desc"), type: "percent", min: 0.0, max: 1.0, change: 0.05},
			{name: Language.get("fps_bg_opacity_name"), desc: Language.get("fps_bg_opacity_desc"), type: "percent", min: 0.0, max: 1.0, change: 0.05},
			{name: Language.get("fps_font_size_name"), desc: Language.get("fps_font_size_desc"), type: "int", min: 8, max: 48, change: 1},
			{name: Language.get("fps_bg_padding_name"), desc: Language.get("fps_bg_padding_desc"), type: "int", min: 0, max: 30, change: 1},
			{name: Language.get("fps_show_fps_name"), desc: Language.get("fps_show_fps_desc"), type: "bool", min: null, max: null, change: null},
			{name: Language.get("fps_show_delay_name"), desc: Language.get("fps_show_delay_desc"), type: "bool", min: null, max: null, change: null},
			{name: Language.get("fps_show_ram_name"), desc: Language.get("fps_show_ram_desc"), type: "bool", min: null, max: null, change: null},
			{name: Language.get("fps_show_mempeak_name"), desc: Language.get("fps_show_mempeak_desc"), type: "bool", min: null, max: null, change: null},
			{name: Language.get("fps_show_objects_name"), desc: Language.get("fps_show_objects_desc"), type: "bool", min: null, max: null, change: null},
			{name: Language.get("fps_force_mb_name"), desc: Language.get("fps_force_mb_desc"), type: "bool", min: null, max: null, change: null},
			{name: Language.get("fps_bg_enabled_name"), desc: Language.get("fps_bg_enabled_desc"), type: "bool", min: null, max: null, change: null},
			{name: Language.get("fps_position_name"), desc: Language.get("fps_position_desc"), type: "fps_position", min: null, max: null, change: null},
			{name: Language.get("fps_spacing_name"), desc: Language.get("fps_spacing_desc"), type: "int", min: 0, max: 200, change: 5},
			{name: Language.get("show_game_version_name"), desc: Language.get("show_version_desc"), type: "bool", min: null, max: null, change: null},
			{name: Language.get("show_haxelibs_name"), desc: Language.get("show_haxelibs_desc"), type: "bool", min: null, max: null, change: null},
			{name: Language.get("show_running_os_name"), desc: Language.get("show_running_os_desc"), type: "bool", min: null, max: null, change: null},
			{name: Language.get("fps_show_platform_name"), desc: Language.get("fps_show_platform_desc"), type: "bool", min: null, max: null, change: null},
			{name: Language.get("fps_show_os_version_name"), desc: Language.get("fps_show_os_version_desc"), type: "bool", min: null, max: null, change: null},
			{name: Language.get("fps_show_resolution_name"), desc: Language.get("fps_show_resolution_desc"), type: "bool", min: null, max: null, change: null},
			{name: Language.get("fps_show_refresh_rate_name"), desc: Language.get("fps_show_refresh_rate_desc"), type: "bool", min: null, max: null, change: null},
			{name: "FPS Counter Layer", desc: "Switch between Stage (screen-space) or Game (1280x720)", type: "fps_layer", min: null, max: null, change: null}
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

		titleText = new FlxText(75, 45, 400, "Kathy FPS Counter\nSettings", 32);
		titleText.setFormat(fontPath, 32, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		titleText.alpha = 1;
		add(titleText);

		optionTexts = [];
		optionValues = [];
		leftPanelElements = [];
		rowTops = [];
		rowHeights = [];

		listStartY = 140;
		listViewHeight = (FlxG.height - listBottomMargin()) - listStartY;
		if (listViewHeight < 1) listViewHeight = 1;

		var cursorY:Float = listStartY;
		for (i in 0...options.length)
		{
			var opt = options[i];

			var text:FlxText = new FlxText(50, cursorY, 300, opt.name, 22);
			text.setFormat(fontPath, 22, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			text.alpha = (i == 0) ? 1 : 0.6;
			add(text);
			optionTexts.push(text);
			leftPanelElements.push(text);

			var value:FlxText = new FlxText(350, cursorY, 300, getCurrentValue(i), 18);
			value.setFormat(fontPath, 18, valueColorFor(i), LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			value.alpha = (i == 0) ? 1 : 0.6;
			add(value);
			optionValues.push(value);
			leftPanelElements.push(value);

			// 行高基于该行各自的实际高度，避免更换字体后行与行重叠
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

		tipTxt = new FlxText(20, FlxG.height - 70, 0, "Press UP/DOWN to navigate, LEFT/RIGHT to adjust values, ENTER to edit color", 16);
		tipTxt.setFormat(fontPath, 16, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		add(tipTxt);
		leftPanelElements.push(tipTxt);
		leftPanelElements.push(titleText);

		var rightBg1:FlxSprite = new FlxSprite(720).makeGraphic(FlxG.width - 720, FlxG.height, FlxColor.BLACK);
		rightBg1.alpha = 0.4;
		rightBg1.visible = true;
		add(rightBg1);

		var rightBg2:FlxSprite = new FlxSprite(750, 160).makeGraphic(FlxG.width - 780, 540, FlxColor.BLACK);
		rightBg2.alpha = 0.4;
		rightBg2.visible = true;
		add(rightBg2);

		// 用固定 key 的 1x1 白图：之后靠 setGraphicSize 缩放 + color 染色实现任意底色。
		// 原实现每次预览刷新都 makeGraphic(动态宽, 动态高, 动态色)，而 FlxGraphic.fromRectangle
		// 以 "宽x高:颜色" 为缓存 key，每个新组合都永久驻留 FlxG.bitmap 缓存（GC 回收不了），
		// 切字号/拖拾色器时涨几 MB 不回落。
		previewBg = new FlxSprite(0, 0).makeGraphic(1, 1, FlxColor.WHITE, false, 'fpsPreviewBg');
		previewBg.color = ClientPrefs.data.fpsBgColor;
		previewBg.alpha = ClientPrefs.data.fpsBgOpacity;
		add(previewBg);

		previewText = new FlxText(0, 0, 0, "", 20);
		previewText.setFormat(Paths.font("vcr.ttf"), 20, ClientPrefs.data.fpsColor);
		add(previewText);
		updatePreview();

		initColorPicker();

		controllerPointer = new FlxShapeCircle(0, 0, 20, {thickness: 0}, FlxColor.WHITE);
		controllerPointer.offset.set(20, 20);
		controllerPointer.screenCenter();
		controllerPointer.alpha = 0.6;
		controllerPointer.visible = false;
		add(controllerPointer);

		FlxG.mouse.visible = !controls.controllerMode;
		_lastControllerMode = controls.controllerMode;

		addTouchPad('LEFT_FULL', 'A_B_C');
		addTouchPadCamera();
	}

	private function initColorPicker():Void
	{
		copyButton = new FlxSprite(760, 50).loadGraphic(Paths.image('noteColorMenu/copy'));
		copyButton.alpha = 0.6;
		copyButton.visible = false;
		copyButton.x = FlxG.width + 100;
		add(copyButton);

		pasteButton = new FlxSprite(1180, 50).loadGraphic(Paths.image('noteColorMenu/paste'));
		pasteButton.alpha = 0.6;
		pasteButton.visible = false;
		pasteButton.x = FlxG.width + 100;
		add(pasteButton);

		colorGradient = FlxGradient.createGradientFlxSprite(60, 360, [FlxColor.WHITE, FlxColor.BLACK]);
		colorGradient.setPosition(780, 200);
		colorGradient.visible = false;
		colorGradient.x = FlxG.width + 100;
		add(colorGradient);

		colorGradientSelector = new FlxSprite(770, 200).makeGraphic(80, 10, FlxColor.WHITE);
		colorGradientSelector.offset.y = 5;
		colorGradientSelector.visible = false;
		colorGradientSelector.x = FlxG.width + 100;
		add(colorGradientSelector);

		colorPalette = new FlxSprite(820, 580).loadGraphic(Paths.image('noteColorMenu/palette', false));
		colorPalette.scale.set(20, 20);
		colorPalette.updateHitbox();
		colorPalette.antialiasing = false;
		colorPalette.visible = false;
		colorPalette.x = FlxG.width + 100;
		add(colorPalette);

		colorWheel = new FlxSprite(860, 200).loadGraphic(Paths.image('noteColorMenu/colorWheel'));
		colorWheel.setGraphicSize(360, 360);
		colorWheel.updateHitbox();
		colorWheel.visible = false;
		colorWheel.x = FlxG.width + 100;
		add(colorWheel);

		colorWheelSelector = new FlxShapeCircle(0, 0, 8, {thickness: 0}, FlxColor.WHITE);
		colorWheelSelector.offset.set(8, 8);
		colorWheelSelector.alpha = 0.6;
		colorWheelSelector.visible = false;
		colorWheelSelector.x = FlxG.width + 100;
		add(colorWheelSelector);

		var txtX = 980;
		var txtY = 90;
		alphabetR = makeColorAlphabet(txtX - 100, txtY);
		alphabetR.visible = false;
		alphabetR.x = FlxG.width + 100;
		add(alphabetR);

		alphabetG = makeColorAlphabet(txtX, txtY);
		alphabetG.visible = false;
		alphabetG.x = FlxG.width + 100;
		add(alphabetG);

		alphabetB = makeColorAlphabet(txtX + 100, txtY);
		alphabetB.visible = false;
		alphabetB.x = FlxG.width + 100;
		add(alphabetB);

		alphabetHex = makeColorAlphabet(txtX, txtY - 55);
		alphabetHex.visible = false;
		alphabetHex.x = FlxG.width + 100;
		add(alphabetHex);

		hexTypeLine = new FlxSprite(0, 20).makeGraphic(5, 62, FlxColor.WHITE);
		hexTypeLine.visible = false;
		hexTypeLine.x = FlxG.width + 100;
		add(hexTypeLine);
	}

	private function makeColorAlphabet(x:Float = 0, y:Float = 0):Alphabet
	{
		var text:Alphabet = new Alphabet(x, y, '', true);
		text.alignment = CENTERED;
		text.setScale(0.5);
		return text;
	}

	private function getCurrentValue(index:Int):String
	{
		switch(index)
		{
			case 0: return "#" + StringTools.hex(ClientPrefs.data.fpsColor, 6);
			case 1: return "#" + StringTools.hex(ClientPrefs.data.fpsBgColor, 6);
			case 2: return Std.int(ClientPrefs.data.fpsOpacity * 100) + "%";
			case 3: return Std.int(ClientPrefs.data.fpsBgOpacity * 100) + "%";
			case 4: return Std.string(ClientPrefs.data.fpsFontSize);
			case 5: return Std.string(ClientPrefs.data.fpsBgPadding);
			case 6: return ClientPrefs.data.fpsShowFPS ? Language.get('enabled') : Language.get('disabled');
			case 7: return ClientPrefs.data.fpsShowDelay ? Language.get('enabled') : Language.get('disabled');
			case 8: return ClientPrefs.data.fpsShowRAM ? Language.get('enabled') : Language.get('disabled');
			case 9: return ClientPrefs.data.fpsShowMemPeak ? Language.get('enabled') : Language.get('disabled');
			case 10: return ClientPrefs.data.fpsShowObjects ? Language.get('enabled') : Language.get('disabled');
			case 11: return ClientPrefs.data.fpsForceMB ? Language.get('enabled') : Language.get('disabled');
			case 12: return ClientPrefs.data.fpsBgEnabled ? Language.get('enabled') : Language.get('disabled');
			case 13: return ClientPrefs.data.fpsPosition;
			case 14: return Std.string(ClientPrefs.data.fpsSpacing);
			case 15: return ClientPrefs.data.exgameversion ? Language.get('enabled') : Language.get('disabled');
			case 16: return ClientPrefs.data.showHaxelibs ? Language.get('enabled') : Language.get('disabled');
			case 17: return ClientPrefs.data.showRunningOS ? Language.get('enabled') : Language.get('disabled');
			case 18: return ClientPrefs.data.fpsShowPlatform ? Language.get('enabled') : Language.get('disabled');
			case 19: return ClientPrefs.data.fpsShowOSVersion ? Language.get('enabled') : Language.get('disabled');
			case 20: return ClientPrefs.data.fpsShowResolution ? Language.get('enabled') : Language.get('disabled');
			case 21: return ClientPrefs.data.fpsShowRefreshRate ? Language.get('enabled') : Language.get('disabled');
			case 22: return ClientPrefs.data.fpsLayer;
		}
		return "";
	}

	private function valueColorFor(idx:Int):FlxColor
	{
		switch(idx)
		{
			case 0: return ClientPrefs.data.fpsColor;
			case 1: return ClientPrefs.data.fpsBgColor;
			case 6: return ClientPrefs.data.fpsShowFPS ? OptionsConfig.OPTION_ON_COLOR : OptionsConfig.OPTION_OFF_COLOR;
			case 7: return ClientPrefs.data.fpsShowDelay ? OptionsConfig.OPTION_ON_COLOR : OptionsConfig.OPTION_OFF_COLOR;
			case 8: return ClientPrefs.data.fpsShowRAM ? OptionsConfig.OPTION_ON_COLOR : OptionsConfig.OPTION_OFF_COLOR;
			case 9: return ClientPrefs.data.fpsShowMemPeak ? OptionsConfig.OPTION_ON_COLOR : OptionsConfig.OPTION_OFF_COLOR;
			case 10: return ClientPrefs.data.fpsShowObjects ? OptionsConfig.OPTION_ON_COLOR : OptionsConfig.OPTION_OFF_COLOR;
			case 11: return ClientPrefs.data.fpsForceMB ? OptionsConfig.OPTION_ON_COLOR : OptionsConfig.OPTION_OFF_COLOR;
			case 12: return ClientPrefs.data.fpsBgEnabled ? OptionsConfig.OPTION_ON_COLOR : OptionsConfig.OPTION_OFF_COLOR;
			case 15: return ClientPrefs.data.exgameversion ? OptionsConfig.OPTION_ON_COLOR : OptionsConfig.OPTION_OFF_COLOR;
			case 16: return ClientPrefs.data.showHaxelibs ? OptionsConfig.OPTION_ON_COLOR : OptionsConfig.OPTION_OFF_COLOR;
			case 17: return ClientPrefs.data.showRunningOS ? OptionsConfig.OPTION_ON_COLOR : OptionsConfig.OPTION_OFF_COLOR;
			case 18: return ClientPrefs.data.fpsShowPlatform ? OptionsConfig.OPTION_ON_COLOR : OptionsConfig.OPTION_OFF_COLOR;
			case 19: return ClientPrefs.data.fpsShowOSVersion ? OptionsConfig.OPTION_ON_COLOR : OptionsConfig.OPTION_OFF_COLOR;
			case 20: return ClientPrefs.data.fpsShowResolution ? OptionsConfig.OPTION_ON_COLOR : OptionsConfig.OPTION_OFF_COLOR;
			case 21: return ClientPrefs.data.fpsShowRefreshRate ? OptionsConfig.OPTION_ON_COLOR : OptionsConfig.OPTION_OFF_COLOR;
		}
		return FlxColor.WHITE;
	}

	private function applyOptionValue(idx:Int):Void
	{
		optionValues[idx].text = getCurrentValue(idx);
		optionValues[idx].color = valueColorFor(idx);
	}

	private function updatePreview():Void
	{
		var textLines:Array<String> = [];
		if(ClientPrefs.data.fpsShowFPS) textLines.push("FPS: 60");
		if(ClientPrefs.data.fpsShowDelay) textLines.push("Delay: 0.0ms");
		if(ClientPrefs.data.fpsShowRAM) {
			if(ClientPrefs.data.fpsForceMB) textLines.push("RAM: 2048MB");
			else textLines.push("RAM: 2GB");
		}
		if(ClientPrefs.data.fpsShowMemPeak) {
			if(ClientPrefs.data.fpsForceMB) textLines.push("Mem Peak: 3072MB");
			else textLines.push("Mem Peak: 3GB");
		}
		if(ClientPrefs.data.fpsShowObjects) textLines.push("Objects: 42");

		var text = textLines.join("\n");

		previewText.text = text;
		previewText.color = ClientPrefs.data.fpsColor;
		// FlxText.size 的 setter 无相等守卫，赋值即强制重绘；加守卫避免每次刷新重建位图
		if (previewText.size != ClientPrefs.data.fpsFontSize)
			previewText.size = ClientPrefs.data.fpsFontSize;
		previewText.alpha = ClientPrefs.data.fpsOpacity;

		var padding = ClientPrefs.data.fpsBgPadding;
		// 缩放固定白图 + 染色，替代 makeGraphic(动态尺寸,动态颜色)——后者每次新组合都进全局位图缓存常驻
		previewBg.setGraphicSize(Std.int(previewText.width + padding * 2), Std.int(previewText.height + padding * 2));
		previewBg.updateHitbox();
		previewBg.color = ClientPrefs.data.fpsBgColor;
		previewBg.alpha = ClientPrefs.data.fpsBgEnabled ? ClientPrefs.data.fpsBgOpacity : 0.2;
		previewBg.setPosition(800 - padding, 200 - padding);
		previewText.setPosition(800, 200);
	}

	private function updateColorPickerUI():Void
	{
		var color:FlxColor = currentColorType == "text" ? ClientPrefs.data.fpsColor : ClientPrefs.data.fpsBgColor;

		alphabetR.text = Std.string(color.red);
		alphabetG.text = Std.string(color.green);
		alphabetB.text = Std.string(color.blue);
		alphabetHex.text = color.toHexString(false, false);

		for(letter in alphabetHex.letters)
			letter.color = color;

		colorWheel.color = FlxColor.fromHSB(0, 0, color.brightness);
		colorWheelSelector.setPosition(colorWheel.x + colorWheel.width / 2, colorWheel.y + colorWheel.height / 2);

		if(color.brightness != 0)
		{
			var hueWrap:Float = color.hue * Math.PI / 180;
			colorWheelSelector.x += Math.sin(hueWrap) * colorWheel.width / 2 * color.saturation;
			colorWheelSelector.y -= Math.cos(hueWrap) * colorWheel.height / 2 * color.saturation;
		}

		colorGradientSelector.y = colorGradient.y + colorGradient.height * (1 - color.brightness);
	}

	private function setColorPickerVisible(visible:Bool):Void
	{
		for (tween in _activeTweens)
		{
			if (tween != null && tween.active)
			{
				tween.cancel();
			}
		}
		_activeTweens = [];

		onColorPicker = visible;

		for (elem in leftPanelElements)
		{
			if (visible)
			{
				var tween = FlxTween.tween(elem, {alpha: elem.alpha * 0.3}, 0.3, {ease: FlxEase.quadOut});
				_activeTweens.push(tween);
			}
			else
			{
				if (elem == titleText || elem == tipTxt)
				{
					var tween = FlxTween.tween(elem, {alpha: 1}, 0.3, {ease: FlxEase.quadOut});
					_activeTweens.push(tween);
				}
				else
				{
					var tween = FlxTween.tween(elem, {alpha: (optionTexts.indexOf(elem) == curSelected || optionValues.indexOf(elem) == curSelected) ? 1 : 0.6}, 0.3, {ease: FlxEase.quadOut});
					_activeTweens.push(tween);
				}
			}
		}

		if (visible)
		{
			var tween = FlxTween.tween(darkOverlay, {alpha: 0.5}, 0.3, {ease: FlxEase.quadOut});
			_activeTweens.push(tween);
		}
		else
		{
			var tween = FlxTween.tween(darkOverlay, {alpha: 0}, 0.3, {ease: FlxEase.quadOut});
			_activeTweens.push(tween);
		}

		var colorPickerElements = [
			{elem: copyButton, targetX: 760},
			{elem: pasteButton, targetX: 1180},
			{elem: colorGradient, targetX: 780},
			{elem: colorGradientSelector, targetX: 770},
			{elem: colorPalette, targetX: 820},
			{elem: colorWheel, targetX: 860}
		];

		for (item in colorPickerElements)
		{
			item.elem.visible = visible;
			if (visible)
			{
				var tween = FlxTween.tween(item.elem, {x: item.targetX}, 0.4, {ease: FlxEase.quadOut});
				_activeTweens.push(tween);
			}
			else
			{
				var tween = FlxTween.tween(item.elem, {x: FlxG.width + 100}, 0.4, {ease: FlxEase.quadOut});
				_activeTweens.push(tween);
			}
		}

		if (visible)
		{
			alphabetR.visible = true;
			alphabetG.visible = true;
			alphabetB.visible = true;
			alphabetHex.visible = true;
			colorWheelSelector.visible = true;

			var tweenR = FlxTween.tween(alphabetR, {x: 880}, 0.4, {ease: FlxEase.quadOut});
			var tweenG = FlxTween.tween(alphabetG, {x: 980}, 0.4, {ease: FlxEase.quadOut});
			var tweenB = FlxTween.tween(alphabetB, {x: 1080}, 0.4, {ease: FlxEase.quadOut});
			var tweenHex = FlxTween.tween(alphabetHex, {x: 980}, 0.4, {ease: FlxEase.quadOut});
			_activeTweens.push(tweenR);
			_activeTweens.push(tweenG);
			_activeTweens.push(tweenB);
			_activeTweens.push(tweenHex);

			new FlxTimer().start(0.4, function(_) {
				updateColorPickerUI();
			});
		}
		else
		{
			var tweenR = FlxTween.tween(alphabetR, {x: FlxG.width + 100}, 0.4, {ease: FlxEase.quadOut});
			var tweenG = FlxTween.tween(alphabetG, {x: FlxG.width + 100}, 0.4, {ease: FlxEase.quadOut});
			var tweenB = FlxTween.tween(alphabetB, {x: FlxG.width + 100}, 0.4, {ease: FlxEase.quadOut});
			var tweenHex = FlxTween.tween(alphabetHex, {x: FlxG.width + 100}, 0.4, {ease: FlxEase.quadOut});
			_activeTweens.push(tweenR);
			_activeTweens.push(tweenG);
			_activeTweens.push(tweenB);
			_activeTweens.push(tweenHex);

			new FlxTimer().start(0.4, function(_) {
				alphabetR.visible = false;
				alphabetG.visible = false;
				alphabetB.visible = false;
				alphabetHex.visible = false;
				colorWheelSelector.visible = false;
			});
		}

		hexTypeLine.visible = false;
		hexTypeNum = -1;

		previewBg.visible = !visible;
		previewText.visible = !visible;

		if(visible)
		{
			_storedColor = currentColorType == "text" ? ClientPrefs.data.fpsColor : ClientPrefs.data.fpsBgColor;
			updateColorPickerUI();
		}
	}

	private function updateSettingsList(elapsed:Float):Void
	{
		// Shift 快速滚动（每次跳 4 项），与 BaseOptionsMenu/LanguageSubState 一致
		var mult:Int = FlxG.keys.pressed.SHIFT ? 4 : 1;

		if(controls.UI_UP_P)
		{
			navigateSelection(-1 * mult);
		}
		else if(controls.UI_DOWN_P)
		{
			navigateSelection(1 * mult);
		}

		if(controls.UI_LEFT_P || controls.UI_RIGHT_P)
		{
			var change = controls.UI_LEFT_P ? -1 : 1;
			var opt = options[curSelected];

			switch(opt.type)
			{
				case "percent":
					if(curSelected == 2)
					{
						ClientPrefs.data.fpsOpacity = FlxMath.bound(ClientPrefs.data.fpsOpacity + change * 0.05, 0, 1);
					}
					else if(curSelected == 3)
					{
						ClientPrefs.data.fpsBgOpacity = FlxMath.bound(ClientPrefs.data.fpsBgOpacity + change * 0.05, 0, 1);
					}
				case "int":
					if (curSelected == 4)
					{
						ClientPrefs.data.fpsFontSize = Std.int(FlxMath.bound(ClientPrefs.data.fpsFontSize + change, 8, 48));
					}
					else if (curSelected == 5)
					{
						ClientPrefs.data.fpsBgPadding = Std.int(FlxMath.bound(ClientPrefs.data.fpsBgPadding + change, 0, 30));
					}
					else if (curSelected == 14)
					{
						ClientPrefs.data.fpsSpacing = Std.int(FlxMath.bound(ClientPrefs.data.fpsSpacing + change * 5, 0, 200));
					}
			}

			optionValues[curSelected].text = getCurrentValue(curSelected);
		optionValues[curSelected].color = valueColorFor(curSelected);
			updatePreview();
			updateFPSCounter();
			FlxG.sound.play(Paths.sound('scrollMenu'));
		}

		if (controls.ACCEPT)
		{
			if (curSelected == 0 || curSelected == 1)
			{
				currentColorType = curSelected == 0 ? "text" : "bg";
				setColorPickerVisible(true);
				FlxG.sound.play(Paths.sound('scrollMenu'));
			}
			else if (options[curSelected].type == "bool")
			{
				toggleBoolOption(curSelected);
				optionValues[curSelected].text = getCurrentValue(curSelected);
		optionValues[curSelected].color = valueColorFor(curSelected);
				updatePreview();
				updateFPSCounter();
				FlxG.sound.play(Paths.sound('scrollMenu'));
			}
			else if (curSelected == 13)
			{
				cycleFPSPosition();
				optionValues[curSelected].text = getCurrentValue(curSelected);
		optionValues[curSelected].color = valueColorFor(curSelected);
				updateFPSCounter();
				FlxG.sound.play(Paths.sound('scrollMenu'));
			}
			else if (options[curSelected].type == "fps_layer")
			{
				cycleFPSLayer();
				optionValues[curSelected].text = getCurrentValue(curSelected);
		optionValues[curSelected].color = valueColorFor(curSelected);
				FlxG.sound.play(Paths.sound('scrollMenu'));
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
			// 松手：结束拖拽，停止抢占阻尼滚动，并回放一次滚动音效
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

	private function cycleFPSPosition():Void
	{
		var positions = ["TOP_LEFT", "TOP_RIGHT", "BOTTOM_LEFT", "BOTTOM_RIGHT"];
		var currentIndex = positions.indexOf(ClientPrefs.data.fpsPosition);
		var newIndex = (currentIndex + 1) % positions.length;
		ClientPrefs.data.fpsPosition = positions[newIndex];
	}

	private function cycleFPSLayer():Void
	{
		var layers = ["Stage", "Game"];
		var currentIndex = layers.indexOf(ClientPrefs.data.fpsLayer);
		var newIndex = (currentIndex + 1) % layers.length;
		ClientPrefs.data.fpsLayer = layers[newIndex];
		Main.updateFPSLayer();
	}

	private function toggleBoolOption(index:Int):Void
	{
		switch(index)
		{
			case 6: ClientPrefs.data.fpsShowFPS = !ClientPrefs.data.fpsShowFPS;
			case 7: ClientPrefs.data.fpsShowDelay = !ClientPrefs.data.fpsShowDelay;
			case 8: ClientPrefs.data.fpsShowRAM = !ClientPrefs.data.fpsShowRAM;
			case 9: ClientPrefs.data.fpsShowMemPeak = !ClientPrefs.data.fpsShowMemPeak;
			case 10: ClientPrefs.data.fpsShowObjects = !ClientPrefs.data.fpsShowObjects;
			case 11: ClientPrefs.data.fpsForceMB = !ClientPrefs.data.fpsForceMB;
			case 12: ClientPrefs.data.fpsBgEnabled = !ClientPrefs.data.fpsBgEnabled;
			case 15: ClientPrefs.data.exgameversion = !ClientPrefs.data.exgameversion;
			case 16: ClientPrefs.data.showHaxelibs = !ClientPrefs.data.showHaxelibs;
			case 17: ClientPrefs.data.showRunningOS = !ClientPrefs.data.showRunningOS;
			case 18: ClientPrefs.data.fpsShowPlatform = !ClientPrefs.data.fpsShowPlatform;
			case 19: ClientPrefs.data.fpsShowOSVersion = !ClientPrefs.data.fpsShowOSVersion;
			case 20: ClientPrefs.data.fpsShowResolution = !ClientPrefs.data.fpsShowResolution;
			case 21: ClientPrefs.data.fpsShowRefreshRate = !ClientPrefs.data.fpsShowRefreshRate;
		}
	}

	private function updateFPSCounter():Void
	{
		if(Main.fpsVar != null)
		{
			Main.updateFPSLayer();
		}
	}

	private function resetOptionToDefault(index:Int):Void
	{
		switch(index)
		{
			case 0: ClientPrefs.data.fpsColor = 0xFFE6CAFF;
			case 1: ClientPrefs.data.fpsBgColor = 0xFF000000;
			case 2: ClientPrefs.data.fpsOpacity = 1.0;
			case 3: ClientPrefs.data.fpsBgOpacity = 0.5;
			case 4: ClientPrefs.data.fpsFontSize = 14;
			case 5: ClientPrefs.data.fpsBgPadding = 5;
			case 6: ClientPrefs.data.fpsShowFPS = true;
			case 7: ClientPrefs.data.fpsShowDelay = true;
			case 8: ClientPrefs.data.fpsShowRAM = true;
			case 9: ClientPrefs.data.fpsShowMemPeak = true;
			case 10: ClientPrefs.data.fpsShowObjects = true;
			case 11: ClientPrefs.data.fpsForceMB = false;
			case 12: ClientPrefs.data.fpsBgEnabled = false;
			case 13: ClientPrefs.data.fpsPosition = "TOP_LEFT";
			case 14: ClientPrefs.data.fpsSpacing = 10;
			case 15: ClientPrefs.data.exgameversion = false;
			case 16: ClientPrefs.data.showHaxelibs = false;
			case 17: ClientPrefs.data.showRunningOS = false;
			case 18: ClientPrefs.data.fpsShowPlatform = false;
			case 19: ClientPrefs.data.fpsShowOSVersion = false;
			case 20: ClientPrefs.data.fpsShowResolution = false;
			case 21: ClientPrefs.data.fpsShowRefreshRate = false;
			case 22: ClientPrefs.data.fpsLayer = "Stage";
		}

		optionValues[index].text = getCurrentValue(index);
		optionValues[index].color = valueColorFor(index);
		updatePreview();
		updateFPSCounter();
	}

	private function updateSelection():Void
	{
		for(i in 0...optionTexts.length)
		{
			optionTexts[i].alpha = (i == curSelected) ? 1 : 0.6;
			optionValues[i].alpha = (i == curSelected) ? 1 : 0.6;
		}

		tipTxt.text = options[curSelected].desc;
	}

	/** 根据 scrollPx 按各行的实际行高平滑重排 Y 坐标，并隐藏超出可视区的行 */
	private function updateScrollPositions():Void
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
	private function keepRowVisible():Void
	{
		if (curSelected < scrollOffset) scrollOffset = curSelected;
		else if (curSelected >= scrollOffset + maxVisibleRows) scrollOffset = curSelected - maxVisibleRows + 1;
		if (scrollOffset < 0) scrollOffset = 0;
		var maxScroll:Int = options.length - maxVisibleRows;
		if (maxScroll < 0) maxScroll = 0;
		if (scrollOffset > maxScroll) scrollOffset = maxScroll;
	}

	private function pointerOverlaps(obj:Dynamic):Bool
	{
		if(!controls.controllerMode) return FlxG.mouse.overlaps(obj);
		return FlxG.overlap(controllerPointer, obj);
	}

	private function pointerX():Float
	{
		if(!controls.controllerMode) return FlxG.mouse.x;
		return controllerPointer.x;
	}

	private function pointerY():Float
	{
		if(!controls.controllerMode) return FlxG.mouse.y;
		return controllerPointer.y;
	}

	private function pointerFlxPoint():FlxPoint
	{
		if(!controls.controllerMode) return FlxG.mouse.getScreenPosition();
		return new FlxPoint(controllerPointer.x, controllerPointer.y);
	}

	private function centerHexTypeLine():Void
	{
		if(hexTypeNum > 0)
		{
			var letter = alphabetHex.letters[hexTypeNum-1];
			hexTypeLine.x = letter.x - letter.offset.x + letter.width;
		}
		else
		{
			var letter = alphabetHex.letters[0];
			hexTypeLine.x = letter.x - letter.offset.x;
		}

		hexTypeLine.x += hexTypeLine.width;
		hexTypeVisibleTimer = 0;
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

		if(touchPad == null)
		{
			addTouchPad('LEFT_FULL', 'A_B_C');
			addTouchPadCamera();
		}

		if(touchPad != null)
		{
			touchPad.buttonA.visible = !onColorPicker;
		}

		// 触摸板 C 键 或 键盘 R 键：重置当前选项 / 拾色器中重置当前颜色
		if((touchPad != null && touchPad.buttonC != null && touchPad.buttonC.justPressed) || FlxG.keys.justPressed.R)
		{
			if(onColorPicker)
			{
				if(currentColorType == "text")
				{
					ClientPrefs.data.fpsColor = 0xFFE6CAFF;
				}
				else
				{
					ClientPrefs.data.fpsBgColor = 0xFF000000;
				}
				updateColorPickerUI();
				updatePreview();
				updateFPSCounter();
				updateOptionValues();
				FlxG.sound.play(Paths.sound('scrollMenu'));
			}
			else
			{
				resetOptionToDefault(curSelected);
				FlxG.sound.play(Paths.sound('scrollMenu'));
			}
		}

		if(controls.BACK)
		{
			if(onColorPicker)
			{
				setColorPickerVisible(false);
				FlxG.sound.play(Paths.sound('cancelMenu'));
			}
			else
			{
				FlxG.mouse.visible = false;
				FlxG.sound.play(Paths.sound('cancelMenu'));
				ClientPrefs.saveSettings();
				MusicBeatState.switchState(new OptionsState());
				return;
			}
		}

		if(FlxG.gamepads.anyJustPressed(ANY)) controls.controllerMode = true;
		else if(FlxG.mouse.justPressed || FlxG.mouse.deltaScreenX != 0 || FlxG.mouse.deltaScreenY != 0) controls.controllerMode = false;

		if(controls.controllerMode != _lastControllerMode)
		{
			FlxG.mouse.visible = !controls.controllerMode;
			controllerPointer.visible = controls.controllerMode;

			if(controls.controllerMode)
			{
				controllerPointer.x = FlxG.mouse.x;
				controllerPointer.y = FlxG.mouse.y;
			}

			_lastControllerMode = controls.controllerMode;
		}

		if(controls.controllerMode)
		{
			for(gamepad in FlxG.gamepads.getActiveGamepads())
			{
				var analogX:Float = gamepad.getXAxis(LEFT_ANALOG_STICK);
				var analogY:Float = gamepad.getYAxis(LEFT_ANALOG_STICK);

				if(analogX != 0 || analogY != 0)
				{
					controllerPointer.x = Math.max(0, Math.min(FlxG.width, controllerPointer.x + analogX * 1000 * elapsed));
					controllerPointer.y = Math.max(0, Math.min(FlxG.height, controllerPointer.y + analogY * 1000 * elapsed));
					break;
				}
			}
		}

		if(onColorPicker)
		{
			updateColorPicker(elapsed);
		}
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
			updateSettingsList(elapsed);
		}
	}

	private function updateColorPicker(elapsed:Float):Void
	{
		if(hexTypeNum > -1)
		{
			var keyPressed:FlxKey = cast(FlxG.keys.firstJustPressed(), FlxKey);
			hexTypeVisibleTimer += elapsed;
			var changed:Bool = false;

			if(changed = FlxG.keys.justPressed.LEFT) hexTypeNum--;
			else if(changed = FlxG.keys.justPressed.RIGHT) hexTypeNum++;
			else if(allowedTypeKeys.exists(keyPressed))
			{
				var curColor:String = alphabetHex.text;
				var newColor:String = curColor.substring(0, hexTypeNum) + allowedTypeKeys.get(keyPressed) + curColor.substring(hexTypeNum + 1);

				var color:Null<FlxColor> = FlxColor.fromString('#' + newColor);
				if(color != null)
				{
					if(currentColorType == "text") ClientPrefs.data.fpsColor = color;
					else ClientPrefs.data.fpsBgColor = color;

					_storedColor = color;
					updateColorPickerUI();
					updatePreview();
					updateFPSCounter();
					updateOptionValues();
				}

				hexTypeNum++;
				changed = true;
			}
			else if(FlxG.keys.justPressed.ENTER) hexTypeNum = -1;

			if(changed)
			{
				if (hexTypeNum > 5)
				{
					hexTypeNum = -1;
					hexTypeLine.visible = false;
				}
				else
				{
					if(hexTypeNum < 0) hexTypeNum = 0;
					else if(hexTypeNum > 5) hexTypeNum = 5;
					centerHexTypeLine();
					hexTypeLine.visible = true;
				}

				FlxG.sound.play(Paths.sound('scrollMenu'));
			}

			if(hexTypeNum != -1)
				hexTypeLine.visible = Math.floor(hexTypeVisibleTimer * 2) % 2 == 0;
		}
		else
		{
			var generalMoved:Bool = FlxG.mouse.justMoved || (controls.controllerMode && FlxG.gamepads.anyInput());
			var generalPressed:Bool = FlxG.mouse.justPressed || (controls.controllerMode && controls.ACCEPT);

			if(generalMoved)
			{
				copyButton.alpha = 0.6;
				pasteButton.alpha = 0.6;
			}

			if(pointerOverlaps(copyButton))
			{
				copyButton.alpha = 1;
				if(generalPressed)
				{
					var color = currentColorType == "text" ? ClientPrefs.data.fpsColor : ClientPrefs.data.fpsBgColor;
					Clipboard.text = color.toHexString(false, false);
					FlxG.sound.play(Paths.sound('scrollMenu'));
				}
				hexTypeNum = -1;
			}
			else if(pointerOverlaps(pasteButton))
			{
				pasteButton.alpha = 1;
				if(generalPressed)
				{
					var formattedText = Clipboard.text.trim().toUpperCase().replace('#', '').replace('0x', '');
					var newColor:Null<FlxColor> = FlxColor.fromString('#' + formattedText);

					if(newColor != null && formattedText.length == 6)
					{
						if(currentColorType == "text") ClientPrefs.data.fpsColor = newColor;
						else ClientPrefs.data.fpsBgColor = newColor;

						_storedColor = newColor;
						updateColorPickerUI();
						updatePreview();
						updateFPSCounter();
						updateOptionValues();
						FlxG.sound.play(Paths.sound('scrollMenu'));
					}
					else
					{
						FlxG.sound.play(Paths.sound('cancelMenu'));
					}
				}
				hexTypeNum = -1;
			}
			else if(generalPressed)
			{
				hexTypeNum = -1;
				if(pointerOverlaps(colorWheel))
				{
					_storedColor = currentColorType == "text" ? ClientPrefs.data.fpsColor : ClientPrefs.data.fpsBgColor;
					holdingOnObj = colorWheel;
				}
				else if(pointerOverlaps(colorGradient))
				{
					_storedColor = currentColorType == "text" ? ClientPrefs.data.fpsColor : ClientPrefs.data.fpsBgColor;
					holdingOnObj = colorGradient;
				}
				else if(pointerOverlaps(colorPalette))
				{
					var px = Std.int((pointerX() - colorPalette.x) / colorPalette.scale.x);
					var py = Std.int((pointerY() - colorPalette.y) / colorPalette.scale.y);
					var newColorInt = colorPalette.pixels.getPixel32(px, py);
					var newColor = FlxColor.fromRGB((newColorInt >> 16) & 0xFF, (newColorInt >> 8) & 0xFF, newColorInt & 0xFF);
					newColor.alpha = (newColorInt >> 24) & 0xFF;

					if(currentColorType == "text") ClientPrefs.data.fpsColor = newColor;
					else ClientPrefs.data.fpsBgColor = newColor;

					_storedColor = newColor;
					updateColorPickerUI();
					updatePreview();
					updateFPSCounter();
					updateOptionValues();
					FlxG.sound.play(Paths.sound('scrollMenu'));
				}
				else if(pointerY() >= alphabetHex.y && pointerY() < alphabetHex.y + alphabetHex.height &&
						Math.abs(pointerX() - 980) <= 84)
				{
					hexTypeNum = 0;
					for(letter in alphabetHex.letters)
					{
						if(letter.x - letter.offset.x + letter.width <= pointerX()) hexTypeNum++;
						else break;
					}
					if(hexTypeNum > 5) hexTypeNum = 5;
					hexTypeLine.visible = true;
					centerHexTypeLine();
				}
				else holdingOnObj = null;
			}

			if(holdingOnObj != null)
			{
				if (FlxG.mouse.justReleased || (controls.controllerMode && !controls.ACCEPT))
				{
					holdingOnObj = null;
					_storedColor = currentColorType == "text" ? ClientPrefs.data.fpsColor : ClientPrefs.data.fpsBgColor;
					updateColorPickerUI();
					updatePreview();
					updateFPSCounter();
					updateOptionValues();
					FlxG.sound.play(Paths.sound('scrollMenu'));
				}
				else if (generalMoved || generalPressed)
				{
					if (holdingOnObj == colorGradient)
					{
						var newBrightness = 1 - FlxMath.bound((pointerY() - colorGradient.y) / colorGradient.height, 0, 1);
						_storedColor.alpha = 1;
						if(_storedColor.brightness == 0)
						{
							var color = FlxColor.fromRGBFloat(newBrightness, newBrightness, newBrightness);
							if(currentColorType == "text") ClientPrefs.data.fpsColor = color;
							else ClientPrefs.data.fpsBgColor = color;
						}
						else
						{
							var color = FlxColor.fromHSB(_storedColor.hue, _storedColor.saturation, newBrightness);
							if(currentColorType == "text") ClientPrefs.data.fpsColor = color;
							else ClientPrefs.data.fpsBgColor = color;
						}

						updateColorPickerUI();
						updatePreview();
						updateFPSCounter();
						updateOptionValues();
					}
					else if (holdingOnObj == colorWheel)
					{
						var center:FlxPoint = new FlxPoint(colorWheel.x + colorWheel.width / 2, colorWheel.y + colorWheel.height / 2);
						var mouse:FlxPoint = pointerFlxPoint();
						var hue:Float = FlxMath.wrap(FlxMath.wrap(Std.int(mouse.degreesTo(center)), 0, 360) - 90, 0, 360);
						var sat:Float = FlxMath.bound(mouse.dist(center) / colorWheel.width * 2, 0, 1);

						if(sat != 0)
						{
							var color = FlxColor.fromHSB(hue, sat, _storedColor.brightness);
							if(currentColorType == "text") ClientPrefs.data.fpsColor = color;
							else ClientPrefs.data.fpsBgColor = color;
						}
						else
						{
							var color = FlxColor.fromRGBFloat(_storedColor.brightness, _storedColor.brightness, _storedColor.brightness);
							if(currentColorType == "text") ClientPrefs.data.fpsColor = color;
							else ClientPrefs.data.fpsBgColor = color;
						}

						updateColorPickerUI();
						updatePreview();
						updateFPSCounter();
						updateOptionValues();
					}
				}
			}
		}
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
