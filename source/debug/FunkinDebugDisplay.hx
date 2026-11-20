package debug;

import flixel.util.FlxColor;
import flixel.util.FlxStringUtil;
import openfl.display.Shape;
import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.AntiAliasType;
import openfl.Lib;
import backend.ClientPrefs;

/**
 * 原版 FNF FunkinDebugDisplay 的完整复刻 + 高度自定义版。
 *
 * 沿用原版的三种模式：
 *  - "Off"      不显示
 *  - "Simple"   纯文本：FPS + GC MEM + TASK MEM
 *  - "Advanced" 在上方加上迷你折线图（FPS 实时/平均/1%low、GC MEM、TASK MEM）
 *
 * 所有颜色/尺寸/显示项/更新频率均从 ClientPrefs.data.fpsDebug* 读取，
 * 调用 `applySettings()` 即可整体重建生效。
 */
class FunkinDebugDisplay extends Sprite
{
	/** 内区边框内缩（INNER_RECT_DIFF） */
	public static inline var DEFAULT_PADDING:Int = 3;
	/** 面板基础内区尺寸 */
	public static inline var DEFAULT_PANEL_WIDTH:Int = 234;
	public static inline var DEFAULT_PANEL_HEIGHT:Int = 201;
	/** 元素到边缘的间距 */
	public static inline var OTHERS_OFFSET:Int = 8;
	/** 底部和右侧的内边框间距（比 OTHERS_OFFSET 更大） */
	public static inline var MARGIN_BR:Int = 14;

	/** 当前模式（"Off" / "Simple" / "Advanced"） */
	public var mode(default, set):String = "Simple";

	var deltaTimeout:Float;
	var times:Array<Float>;
	var fps:Int;
	var fpsPeak:Int;
	var gcMem:Float;
	var gcMemPeak:Float;
	var taskMem:Float;
	var taskMemPeak:Float;

	var background:Shape;
	var fpsGraph:FunkinStatsGraph;
	var gcMemGraph:FunkinStatsGraph;
	var taskMemGraph:FunkinStatsGraph;
	var infoDisplay:TextField;

	public function new(x:Float = 10, y:Float = 10):Void
	{
		super();

		this.x = x;
		this.y = y;

		this.deltaTimeout = 0;
		this.times = [];
		this.fps = 0;
		this.fpsPeak = 0;
		this.gcMem = 0;
		this.gcMemPeak = 0;
		this.taskMem = 0;
		this.taskMemPeak = 0;

		this.mode = ClientPrefs.data.fpsDebugMode;
		applySettings();
	}

	function fontNameForOpenFL():String
	{
		return ClientPrefs.data.fpsDebugFont == "Quantico"
			? backend.Paths.font("Quantico-Regular.ttf")
			: backend.Paths.font("vcr.ttf");
	}

	function set_mode(value:String):String
	{
		if (mode == value) return value; // 值没变不重建（原先每次赋值都整块重建 DisplayObject）
		mode = value;
		buildDebugDisplay();
		return value;
	}

	/**
	 * 整体（重新）构建面板：背景 + 当前模式的元素。
	 */
	public function applySettings():Void
	{
		if (mode == "Off")
		{
			buildBackground();
			return;
		}
		buildDebugDisplay();
	}

	function buildDebugDisplay():Void
	{
		removeChildren(0, numChildren);

		buildBackground();

		if (mode == "Simple")
		{
			createSimpleElements();
			updateDisplay();
		}
		else if (mode == "Advanced")
		{
			createAdvancedElements();
			resizeAdvancedBackground();
			updateDisplay();
		}
	}

	// ============ 背景面板 ============

	function buildBackground():Void
	{
		if (background != null)
		{
			removeChild(background);
			background = null;
		}

		background = new Shape();

		var w:Float = 0;
		var h:Float = 0;
		if (mode != "Off")
		{
			var pad:Int = ClientPrefs.data.fpsDebugPadding;
			if (mode == "Simple")
			{
				// 尺寸跟文本实时匹配（更贴合 Psych 现有风格）
				w = ClientPrefs.data.fpsDebugPanelWidth + pad * 2;
				h = 1 + pad * 2;
			}
			else // Advanced
			{
				var graphCount:Int = 1;
				if (supportsGCMem() && ClientPrefs.data.fpsDebugShowGCMem) graphCount++;
				if (supportsTaskMem() && ClientPrefs.data.fpsDebugShowTaskMem) graphCount++;
				w = ClientPrefs.data.fpsDebugPanelWidth + pad * 2;
				h = (graphCount * (ClientPrefs.data.fpsDebugGraphHeight + 34)) + 8 + pad;
			}
		}

		if (ClientPrefs.data.fpsDebugBgEnabled && w > 0 && h > 0)
		{
			var outer:Int = (ClientPrefs.data.fpsDebugBgOuter:Int);
			var inner:Int = (ClientPrefs.data.fpsDebugBgInner:Int);
			var pad:Int = ClientPrefs.data.fpsDebugPadding;

			background.graphics.beginFill(outer, 1);
			background.graphics.drawRect(0, 0, w, h);
			background.graphics.endFill();
			background.graphics.beginFill(inner, 1);
			background.graphics.drawRect(pad, pad, w - pad * 2, h - pad * 2);
			background.graphics.endFill();
			background.alpha = ClientPrefs.data.fpsDebugBgOpacity;
		}
		addChild(background);
	}

	// ============ Simple ============

	function createSimpleElements():Void
	{
		if (infoDisplay != null)
		{
			removeChild(infoDisplay);
			infoDisplay = null;
		}

		infoDisplay = new TextField();
		infoDisplay.x = OTHERS_OFFSET;
		infoDisplay.y = OTHERS_OFFSET;
		infoDisplay.width = 500;
		infoDisplay.selectable = false;
		infoDisplay.mouseEnabled = false;
		infoDisplay.defaultTextFormat = new TextFormat(fontNameForOpenFL(), ClientPrefs.data.fpsDebugFontSize,
			(ClientPrefs.data.fpsDebugTextColor:Int), false);
		infoDisplay.antiAliasType = AntiAliasType.NORMAL;
		infoDisplay.multiline = true;
		addChild(infoDisplay);
	}

	// ============ Advanced ============

	function createAdvancedElements():Void
	{
		var graphsWidth:Int = ClientPrefs.data.fpsDebugPanelWidth - (OTHERS_OFFSET * 3);
		var graphsHeight:Int = ClientPrefs.data.fpsDebugGraphHeight;
		var graphColor:FlxColor = ClientPrefs.data.fpsDebugTextColor;

		fpsGraph = null;
		gcMemGraph = null;
		taskMemGraph = null;

		if (ClientPrefs.data.fpsDebugShowFPSGraph)
		{
			fpsGraph = new FunkinStatsGraph(OTHERS_OFFSET, 0, graphsWidth, graphsHeight, graphColor, fontNameForOpenFL(),
				ClientPrefs.data.fpsDebugFontSize);
			fpsGraph.minValue = 0;
			applyGraphConfig(fpsGraph);
			addChild(fpsGraph);
			// 先行填充文本，让下方布局能读到实际文本高度
			var fpsLines:Array<String> = ['FPS: 0'];
			if (ClientPrefs.data.fpsDebugShowAvg) fpsLines.push('AVG FPS: 0');
			if (ClientPrefs.data.fpsDebugShowLow) fpsLines.push('1% LOW FPS: 0');
			fpsGraph.textLines = fpsLines;
			fpsGraph.updateText();
		}

		if (supportsGCMem() && ClientPrefs.data.fpsDebugShowGCMem)
		{
			gcMemGraph = new FunkinStatsGraph(OTHERS_OFFSET, 0, graphsWidth, graphsHeight, graphColor, fontNameForOpenFL(),
				ClientPrefs.data.fpsDebugFontSize);
			gcMemGraph.minValue = 0;
			applyGraphConfig(gcMemGraph);
			addChild(gcMemGraph);
			gcMemGraph.textLines = ['GC MEM: 0'];
			gcMemGraph.updateText();
		}

		if (supportsTaskMem() && ClientPrefs.data.fpsDebugShowTaskMem)
		{
			taskMemGraph = new FunkinStatsGraph(OTHERS_OFFSET, 0, graphsWidth, graphsHeight, graphColor, fontNameForOpenFL(),
				ClientPrefs.data.fpsDebugFontSize);
			taskMemGraph.minValue = 0;
			applyGraphConfig(taskMemGraph);
			addChild(taskMemGraph);
			taskMemGraph.textLines = ['TASK MEM: 0'];
			taskMemGraph.updateText();
		}

		layoutAdvancedGraphs();
	}

	/**
	 * 按每一行的实际文本高度横向堆叠折线图（图上方标签底边贴图顶部），
	 * 避免文本与图形、图形与图形之间重叠。
	 */
	function layoutAdvancedGraphs():Void
	{
		var graphs:Array<FunkinStatsGraph> = [fpsGraph, gcMemGraph, taskMemGraph];
		var cursorY:Float = OTHERS_OFFSET;
		var columnGap:Float = 10;

		for (g in graphs)
		{
			if (g == null) continue;
			var textH:Float = (g.textDisplay != null) ? g.textDisplay.textHeight : 0;
			// 文本顶部对齐游标；y 需多让出「文本高度 + 文本与图的间距」，文本才不会顶出面板
			g.y = Math.floor(cursorY + textH + g.textGap);
			cursorY = g.y + g.axisHeight + columnGap;
		}
	}

	function applyGraphConfig(graph:FunkinStatsGraph):Void
	{
		graph.textGap = ClientPrefs.data.fpsDebugGraphTextGap;
		graph.applyConfig(ClientPrefs.data.fpsDebugHistoryMax, ClientPrefs.data.fpsDebugLineThickness,
			ClientPrefs.data.fpsDebugAxisColor, ClientPrefs.data.fpsDebugAxisAlpha, ClientPrefs.data.fpsDebugAxisInset, true,
			ClientPrefs.data.fpsDebugGraphSmooth);
	}

	// ============ 更新 ============

	override function __enterFrame(deltaTime:Float):Void
	{
		step(deltaTime);
	}

	/**
	 * 刷新的统一入口。直接挂到 stage 的面板（如设置界面预览）由 OpenFL 通过
	 * `__enterFrame` 驱动；游戏内嵌在 FPSCounter 里的面板因 FPSCounter 覆写了
	 * `__enterFrame` 且未调用 super，链式传播会中断，故由 FPSCounter 每帧显式调用本方法。
	 */
	public function step(deltaTime:Float):Void
	{
		if (mode == "Off" || !visible)
		{
			return;
		}

		var currentTime:Float = Lib.getTimer();
		times.push(currentTime);

		while (times[0] < currentTime - 1000)
		{
			times.shift();
		}

		if (deltaTimeout < ClientPrefs.data.fpsDebugUpdateDelay)
		{
			deltaTimeout += deltaTime;
			return;
		}

		fps = times.length;
		if (fps > fpsPeak) fpsPeak = fps;

		if (supportsGCMem())
		{
			gcMem = getGCMemory();
			if (gcMem > gcMemPeak) gcMemPeak = gcMem;
		}

		if (supportsTaskMem())
		{
			taskMem = getTaskMemory();
			if (taskMem > taskMemPeak) taskMemPeak = taskMem;
		}

		updateDisplay();
		deltaTimeout = 0;
	}

	function updateDisplay():Void
	{
		if (mode == "Advanced")
		{
			updateAdvancedDisplay();
			resizeAdvancedBackground();
		}
		else if (mode == "Simple")
		{
			updateSimpleDisplay();
			resizeBackgroundToFit();
		}
	}

	function updateSimpleDisplay():Void
	{
		if (infoDisplay == null) return;

		var info:Array<String> = [];

		var fpsLine:String = 'FPS: $fps';
		if (ClientPrefs.data.fpsDebugShowPlatform) fpsLine += '  ${platformLabel()}';
		info.push(fpsLine);

		if (supportsGCMem())
		{
			info.push('GC MEM: ${formatBytes(gcMem)} / ${formatBytes(gcMemPeak)}');
		}
		if (supportsTaskMem())
		{
			info.push('TASK MEM: ${formatBytes(taskMem)} / ${formatBytes(taskMemPeak)}');
		}

		infoDisplay.text = info.join('\n');
	}

	function updateAdvancedDisplay():Void
	{
		if (fpsGraph != null)
		{
			fpsGraph.maxValue = fpsPeak;
			fpsGraph.update(fps);

			var info:Array<String> = ['FPS: $fps'];
			if (ClientPrefs.data.fpsDebugShowAvg) info.push('AVG FPS: ${Math.floor(fpsGraph.average())}');
			if (ClientPrefs.data.fpsDebugShowLow) info.push('1% LOW FPS: ${Math.floor(fpsGraph.lowest())}');
			fpsGraph.textLines = info;
			fpsGraph.updateText();
		}

		if (gcMemGraph != null)
		{
			gcMemGraph.maxValue = gcMemPeak;
			gcMemGraph.update(gcMem);
			gcMemGraph.textLines = ['GC MEM: ${formatBytes(gcMem)} / ${formatBytes(gcMemPeak)}'];
			gcMemGraph.updateText();
		}

		if (taskMemGraph != null)
		{
			taskMemGraph.maxValue = taskMemPeak;
			taskMemGraph.update(taskMem);
			taskMemGraph.textLines = ['TASK MEM: ${formatBytes(taskMem)} / ${formatBytes(taskMemPeak)}'];
			taskMemGraph.updateText();
		}
	}

	/**
	 * 让背景高度/宽度跟随文本实际尺寸（Simple 模式），保证贴边定位准确且文字不超框。
	 */
	function resizeBackgroundToFit():Void
	{
		if (mode != "Simple" || background == null) return;

		var pad:Int = ClientPrefs.data.fpsDebugPadding;
		var contentW:Float = infoDisplay != null ? infoDisplay.textWidth : 1;
		var contentH:Float = infoDisplay != null ? infoDisplay.textHeight : 1;
		// 宽度跟随文字实际宽度自适应（保留配置的最小面板宽度下限），避免长文本（如带平台信息的 FPS 行）画出面板框
		var w:Float = Math.max(ClientPrefs.data.fpsDebugPanelWidth + pad * 2, OTHERS_OFFSET + contentW + MARGIN_BR);
		var h:Float = OTHERS_OFFSET + contentH + MARGIN_BR;

		var outer:Int = (ClientPrefs.data.fpsDebugBgOuter:Int);
		var inner:Int = (ClientPrefs.data.fpsDebugBgInner:Int);
		background.graphics.clear();
		if (ClientPrefs.data.fpsDebugBgEnabled)
		{
			background.graphics.beginFill(outer, 1);
			background.graphics.drawRect(0, 0, w, h);
			background.graphics.endFill();
			background.graphics.beginFill(inner, 1);
			background.graphics.drawRect(pad, pad, w - pad * 2, h - pad * 2);
			background.graphics.endFill();
			background.alpha = ClientPrefs.data.fpsDebugBgOpacity;
		}
	}

	/**
	 * Advanced 模式按折线图的实际纵向位置把背景撑到能包住最后一张图的坐标轴，
	 * 避免坐标轴超出背景框。buildBackground 里的粗略公式仅作初值。
	 */
	function resizeAdvancedBackground():Void
	{
		if (mode != "Advanced" || background == null) return;

		var pad:Int = ClientPrefs.data.fpsDebugPadding;
		var h:Float = pad * 2 + 1;

		var graphs:Array<FunkinStatsGraph> = [fpsGraph, gcMemGraph, taskMemGraph];
		var maxTextRight:Float = 0;
		for (g in graphs)
		{
			if (g == null) continue;
			if (g.axisHeight > 0) h = Math.max(h, g.y + g.axisHeight + MARGIN_BR);
			// 宽度跟随各张图最宽的文本自然右边界，背景至少包住已显示文本（面板宽度配置作为最小宽度下限）
			if (g.textDisplay != null && g.textDisplay.textWidth > 0)
			{
				maxTextRight = Math.max(maxTextRight, g.x + g.textDisplay.x + g.textDisplay.textWidth);
			}
		}

		var w:Float = Math.max(ClientPrefs.data.fpsDebugPanelWidth + pad * 2, maxTextRight + MARGIN_BR);

		var outer:Int = (ClientPrefs.data.fpsDebugBgOuter:Int);
		var inner:Int = (ClientPrefs.data.fpsDebugBgInner:Int);
		background.graphics.clear();
		if (ClientPrefs.data.fpsDebugBgEnabled)
		{
			background.graphics.beginFill(outer, 1);
			background.graphics.drawRect(0, 0, w, h);
			background.graphics.endFill();
			background.graphics.beginFill(inner, 1);
			background.graphics.drawRect(pad, pad, w - pad * 2, h - pad * 2);
			background.graphics.endFill();
			background.alpha = ClientPrefs.data.fpsDebugBgOpacity;
		}
	}

	// ============ 定位 / 缩放 ============

	/**
	 * 根据 fpsPosition 的四个角落 + 间距放置到 stage 边缘。
	 */
	public function reposition(position:String, spacing:Int):Void
	{
		var isRight:Bool = position != null && position.indexOf("RIGHT") != -1;
		var isBottom:Bool = position != null && position.indexOf("BOTTOM") != -1;
		var w:Float = width <= 0 ? ClientPrefs.data.fpsDebugPanelWidth : width;
		var h:Float = height <= 0 ? 80 : height;

		var stageW:Float = openfl.Lib.current.stage != null ? openfl.Lib.current.stage.stageWidth : 1280;
		var stageH:Float = openfl.Lib.current.stage != null ? openfl.Lib.current.stage.stageHeight : 720;

		x = isRight ? (stageW - w - spacing) : spacing;
		y = isBottom ? (stageH - h - spacing) : spacing;
	}

	public function setScaleFactor(f:Float):Void
	{
		scaleX = scaleY = (f <= 0 ? 1 : f);
	}

	// ============ 工具 ============

	function formatBytes(v:Float):String
	{
		if (v < 0 || v != v) v = 0;
		try
		{
			return FlxStringUtil.formatBytes(v).toLowerCase();
		}
		catch (e:Dynamic)
		{
			return '${Math.round(v / (1024 * 1024))}mb';
		}
	}

	function platformLabel():String
	{
		#if cpp
		try
		{
			return lime.system.System.platformName;
		}
		catch (e:Dynamic) {}
		#end
		return "";
	}

	function supportsGCMem():Bool
	{
		#if cpp
		return true;
		#else
		return false;
		#end
	}

	function getGCMemory():Float
	{
		#if cpp
		try
		{
			var v:Dynamic = cpp.vm.Gc.memInfo64(cpp.vm.Gc.MEM_INFO_USAGE);
			if (Std.is(v, Float) || Std.is(v, Int)) return cast v;
		}
		catch (e:Dynamic) {}
		try
		{
			var v:Dynamic = cpp.vm.Gc.memInfo(cpp.vm.Gc.MEM_INFO_USAGE);
			if (Std.is(v, Float) || Std.is(v, Int)) return cast v;
		}
		catch (e:Dynamic) {}
		#end
		return 0;
	}

	function supportsTaskMem():Bool
	{
		// 进程级内存：使用 openfl.system.System.totalMemory（各平台可用）
		return true;
	}

	function getTaskMemory():Float
	{
		// 注意：openfl.System.totalMemory 在 cpp 下其实等于 Gc.MEM_INFO_USAGE，
		// 直接用它会和 getGCMemory() 返回同一个值。这里改用进程/堆预留总量
		// (MEM_INFO_RESERVED >= USAGE)，让 GC（实际使用量）与 TASK（预留总量）能区分开来。
		#if cpp
		try
		{
			var v:Dynamic = cpp.vm.Gc.memInfo64(cpp.vm.Gc.MEM_INFO_RESERVED);
			if (Std.is(v, Float) || Std.is(v, Int)) return cast v;
		}
		catch (e:Dynamic) {}
		#end
		try
		{
			return openfl.system.System.totalMemory;
		}
		catch (e:Dynamic)
		{
			return 0;
		}
	}
}