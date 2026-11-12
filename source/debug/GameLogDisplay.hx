package debug;

import openfl.display.Sprite;
import openfl.display.Shape;
import openfl.display.DisplayObject;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.GridFitType;
import openfl.text.AntiAliasType;
import openfl.events.Event;
import openfl.events.MouseEvent;
import openfl.events.TouchEvent;
import openfl.Lib;
import lime.system.System;
import haxe.Timer;
import haxe.PosInfos;
import StringBuf;
import flixel.util.FlxColor;
import backend.Paths;
import backend.Language;

/**
 * Game Log Display (重写版) — 显示在 OpenFL 层（stage 之上）的浮动日志窗口。
 *
 * 设计目标（来自需求）：
 *  - 一个常驻的“启动按钮”，桌面/手机都能轻松找到并调出日志；按钮可通过鼠标/触摸长按拖动。
 *  - 点开后是带 Windows 风格控件（最小化 / 最大化 / 关闭）的窗口，可拖动，始终在画面中可见。
 *  - 最小化后窗口收起、变回那个按钮的样子。
 *  - 窗口有固定默认尺寸，尽量不遮挡游戏；最大化时放大到约 70% 屏（留边距、半透明，仍可见游戏）。
 *  - 窗口内的 log 内容支持鼠标滚轮 / 触摸上下左右滑动，并带有垂直/水平滚动条。
 *  - 主题：半透明、圆角，且窗口内的操作不能穿透影响游戏内 UI（通过对日志层事件 stopPropagation 实现）。
 *  - 当窗口尺寸变化（含跟随最大窗口）时，按钮/窗口会自动夹紧到可视范围内并带移动动效。
 *
 * 公共 API 与旧版保持一致（Main.hx / ClientPrefs / PlayState 等无需改动）：
 *  setEnabled / toggleVisibility / updatePositionOnResize / addLog / addLogWithColor / static onLogAdded
 */
class GameLogDisplay extends Sprite
{
	// ---- 日志数据 ----
	private var logs:Array<LogEntry>;
	private var maxLogs:Int = 250;

	// ---- 文本 ----
	private var _logText:TextField;
	private var fontName:String;
	private var fontSize:Int = 16;

	// ---- 启用 / 可见 状态 ----
	public var isEnabled:Bool = false;     // 由设置（enableGameLog）控制是否启用
	private var _windowOpen:Bool = false;  // 日志窗口是否展开（false = 仅显示启动按钮）
	private var _isMaximized:Bool = false;  // 是否处于最大化状态
	private var _maxAnim:Float = 0;        // 最大化/还原 动画进度 0..1
	private var showDebug:Bool = false;     // 是否显示 debug 级别日志
	private var _logDirty:Bool = false;     // 日志内容变更标记：批量重绘，避免低端设备每帧重建 TextField
	private var _moved:Bool = false;        // 启动按钮是否被拖动过（区分轻点与拖动）

	// ---- 原始 trace ----
	private var originalTrace:Dynamic->?haxe.PosInfos->Void;
	public static var onLogAdded:Dynamic = null;

	// ---- 启动按钮（FAB）----
	private var _launcher:Sprite;
	private var _launchBg:Shape;
	private var _launchIcon:Shape;
	private var _launchX:Float = 0; private var _launchY:Float = 0;
	private var _launchTX:Float = 0; private var _launchTY:Float = 0;
	private var _launchAnim:Float = 0; private var _launchAnimTarget:Float = 0;
	private var _launchW:Float = 0; private var _launchH:Float = 0;

	// ---- 窗口 ----
	private var _window:Sprite;
	private var _winBg:Sprite;
	private var _titleBar:Sprite;
	private var _titleTF:TextField;
	private var _btnMin:Sprite; private var _btnMax:Sprite; private var _btnClose:Sprite;
	private var _winW:Float = 0; private var _winH:Float = 0;
	private var _titleH:Float = 0;
	private var _winX:Float = 0; private var _winY:Float = 0;
	private var _winTX:Float = 0; private var _winTY:Float = 0;
	private var _winAnim:Float = 0; private var _winAnimTarget:Float = 0;
	private var _hoverBtn:Int = -1;
	private var _maxAnimating:Bool = false;  // 最大化/还原 动画进行中（基于右上角锚点）
	private var _anchorX:Float = 0; private var _anchorY:Float = 0; // 动画锚点：窗口右上角（固定不动）

	// ---- 工具栏（debug 开关 / 清空 / 导出）----
	private var _toolbar:Sprite;
	private var _btnDebug:Sprite; private var _btnClear:Sprite; private var _btnExport:Sprite;
	private var _toolHover:Map<Sprite, Bool> = new Map(); // 工具栏按钮的悬停/按下态（焦点反馈）
	private var _toolLabels:Map<Sprite, Array<String>> = new Map(); // 工具栏按钮的 [语言 key, 兜底文案]
	private var _statusTF:TextField;
	private var _toolH:Float = 0;
	private var _statusTimer:haxe.Timer = null;

	// ---- 滚动内容 ----
	private var _contentScroll:Sprite;
	private var _contentHit:Sprite;
	private var _contentMask:Shape;
	private var _contentX:Float = 0; private var _contentY:Float = 0;
	private var _vpW:Float = 0; private var _vpH:Float = 0;
	private var _contentW:Float = 0; private var _contentH:Float = 0;
	private var _scrollX:Float = 0; private var _scrollY:Float = 0;
	private var _maxScrollX:Float = 0; private var _maxScrollY:Float = 0;
	private var _vScrollVisible:Bool = false; private var _hScrollVisible:Bool = false;

	// ---- 滚动条 ----
	private var _vTrack:Shape; private var _vThumb:Sprite;
	private var _hTrack:Shape; private var _hThumb:Sprite;
	private var _vTrackY:Float = 0; private var _vTrackH:Float = 0; private var _vThumbH:Float = 0; private var _vThumbY:Float = 0;
	private var _hTrackX:Float = 0; private var _hTrackW:Float = 0; private var _hThumbW:Float = 0; private var _hThumbX:Float = 0;

	// ---- 交互 / 拖动状态 ----
	private static inline var DRAG_NONE:Int = 0;
	private static inline var DRAG_LAUNCHER:Int = 1;
	private static inline var DRAG_WINDOW:Int = 2;
	private static inline var DRAG_CONTENT:Int = 3;
	private static inline var DRAG_VSCROLL:Int = 4;
	private static inline var DRAG_HSCROLL:Int = 5;

	// 日志级别
	private static inline var LV_INFO:Int = 0;
	private static inline var LV_WARN:Int = 1;
	private static inline var LV_ERROR:Int = 2;
	private static inline var LV_DEBUG:Int = 3;

	// 工具栏按钮宽度系数（乘以 _winS）
	private static inline var TB_DEBUG_W:Float = 72;
	private static inline var TB_CLEAR_W:Float = 56;
	private static inline var TB_EXPORT_W:Float = 56;

	private var _dragMode:Int = DRAG_NONE;
	private var _dragging:Bool = false;
	private var _pressActive:Bool = false;
	private var _launcherArmed:Bool = false;
	private var _longPressTimer:haxe.Timer = null;
	private var _pressStageX:Float = 0; private var _pressStageY:Float = 0;
	private var _grabX:Float = 0; private var _grabY:Float = 0;
	private var _startScrollX:Float = 0; private var _startScrollY:Float = 0;
	private var _vDragOffset:Float = 0; private var _hDragOffset:Float = 0;
	private var _pointerX:Float = 0; private var _pointerY:Float = 0;

	// ---- 缩放 ----
	private var _mobile:Bool = false;
	private var _uiScale:Float = 1;
	private var _winS:Float = 1;
	private var _touchS:Float = 1;

	// ---- 计时 ----
	private var _lastT:Float = 0;

	public function new()
	{
		super();

		_mobile = #if mobile true #else false #end;
		fontName = Paths.font('unifont-18.0.01.otf');

		logs = [];
		mouseEnabled = true;
		mouseChildren = true;
		visible = true;
		x = 0; y = 0;

		buildLauncher();
		buildWindow();
		buildScrollContent();
		buildScrollbars();
		buildToolbar();

		addEventListener(Event.ADDED_TO_STAGE, onAddedToStage);
		addEventListener(Event.ENTER_FRAME, onFrame);

		hookTrace();
		recomputeScale();
	}

	// ------------------------------------------------------------------
	// 构建：启动按钮
	// ------------------------------------------------------------------
	private function buildLauncher():Void
	{
		_launcher = new Sprite();
		_launcher.mouseEnabled = true;
		_launcher.mouseChildren = false;
		_launcher.visible = false;

		_launchBg = new Shape();
		_launchBg.cacheAsBitmap = true;
		_launcher.addChild(_launchBg);

		_launchIcon = new Shape();
		_launchIcon.cacheAsBitmap = true;
		_launcher.addChild(_launchIcon);

		_launcher.addEventListener(MouseEvent.MOUSE_DOWN, onLauncherDownMouse);
		_launcher.addEventListener(TouchEvent.TOUCH_BEGIN, onLauncherDownTouch);

		addChild(_launcher);
	}

	// ------------------------------------------------------------------
	// 构建：窗口骨架
	// ------------------------------------------------------------------
	private function buildWindow():Void
	{
		_window = new Sprite();
		_window.mouseEnabled = true;
		_window.mouseChildren = true;
		_window.visible = false;

		_winBg = new Sprite();
		_winBg.cacheAsBitmap = true;
		_winBg.mouseEnabled = true;
		_winBg.mouseChildren = false;
		// 拦截窗口背景上的按下事件，避免穿透到游戏
		_winBg.addEventListener(MouseEvent.MOUSE_DOWN, function(e:MouseEvent){ e.stopPropagation(); e.stopImmediatePropagation(); });
		_winBg.addEventListener(TouchEvent.TOUCH_BEGIN, function(e:TouchEvent){ e.stopPropagation(); e.stopImmediatePropagation(); });
		_window.addChild(_winBg);

		_titleBar = new Sprite();
		_titleBar.cacheAsBitmap = true;
		_titleBar.mouseEnabled = true;
		_titleBar.mouseChildren = false;
		_titleBar.addEventListener(MouseEvent.MOUSE_DOWN, onTitleDownMouse);
		_titleBar.addEventListener(TouchEvent.TOUCH_BEGIN, onTitleDownTouch);
		_window.addChild(_titleBar);

		_titleTF = new TextField();
		_titleTF.selectable = false;
		_titleTF.mouseEnabled = false;
		_titleTF.autoSize = openfl.text.TextFieldAutoSize.LEFT;
		_titleTF.multiline = false;
		_titleTF.wordWrap = false;
		_titleTF.antiAliasType = AntiAliasType.ADVANCED;
		_titleTF.gridFitType = GridFitType.PIXEL;
		setTitleText();
		_window.addChild(_titleTF);

		_btnMin = makeWinButton(0);
		_btnMax = makeWinButton(1);
		_btnClose = makeWinButton(2);
		_window.addChild(_btnMin);
		_window.addChild(_btnMax);
		_window.addChild(_btnClose);

		// 滚轮监听（在窗口范围内）
		_window.addEventListener(MouseEvent.MOUSE_WHEEL, onWheel);

		addChild(_window);
	}

	private function makeWinButton(kind:Int):Sprite
	{
		var b = new Sprite();
		b.mouseEnabled = true;
		b.mouseChildren = false;
		b.addEventListener(MouseEvent.MOUSE_DOWN, function(e:MouseEvent){ e.stopPropagation(); e.stopImmediatePropagation(); });
		b.addEventListener(TouchEvent.TOUCH_BEGIN, function(e:TouchEvent){ e.stopPropagation(); e.stopImmediatePropagation(); });
		b.addEventListener(MouseEvent.MOUSE_OVER, function(e:MouseEvent){ _hoverBtn = kind; redrawButtons(); });
		b.addEventListener(MouseEvent.MOUSE_OUT, function(e:MouseEvent){ if (_hoverBtn == kind) _hoverBtn = -1; redrawButtons(); });
		b.addEventListener(MouseEvent.CLICK, function(e:MouseEvent){ e.stopPropagation(); e.stopImmediatePropagation(); onWinButton(kind); });
		return b;
	}

	// ------------------------------------------------------------------
	// 构建：滚动内容区
	// ------------------------------------------------------------------
	private function buildScrollContent():Void
	{
		_contentMask = new Shape();
		_window.addChild(_contentMask);

		_contentScroll = new Sprite();
		_contentScroll.mouseEnabled = false;
		_contentScroll.mouseChildren = false;
		_contentScroll.mask = _contentMask;

		_logText = new TextField();
		_logText.selectable = false;
		_logText.mouseEnabled = false;
		_logText.defaultTextFormat = new TextFormat(fontName, fontSize, 0xFFFFFF);
		_logText.autoSize = openfl.text.TextFieldAutoSize.NONE;
		_logText.multiline = true;
		_logText.wordWrap = false; // 关闭自动换行 -> 支持水平滚动
		_logText.antiAliasType = AntiAliasType.ADVANCED;        // 配合 PIXEL 网格对齐，去除模糊
		_logText.gridFitType = openfl.text.GridFitType.PIXEL;  // 像素对齐，文字更清晰
		_logText.width = 8000;     // 给足宽度，保证水平方向测量准确
		_logText.height = 6000;
		_contentScroll.addChild(_logText);
		_window.addChild(_contentScroll);

		_contentHit = new Sprite();
		_contentHit.mouseEnabled = true;
		_contentHit.mouseChildren = false;
		_contentHit.addEventListener(MouseEvent.MOUSE_DOWN, onContentDownMouse);
		_contentHit.addEventListener(TouchEvent.TOUCH_BEGIN, onContentDownTouch);
		_window.addChild(_contentHit);
	}

	private function buildScrollbars():Void
	{
		_vTrack = new Shape();
		_vThumb = new Sprite(); _vThumb.mouseEnabled = true; _vThumb.mouseChildren = false;
		_vThumb.addEventListener(MouseEvent.MOUSE_DOWN, onVThumbDownMouse);
		_vThumb.addEventListener(TouchEvent.TOUCH_BEGIN, onVThumbDownTouch);
		_hTrack = new Shape();
		_hThumb = new Sprite(); _hThumb.mouseEnabled = true; _hThumb.mouseChildren = false;
		_hThumb.addEventListener(MouseEvent.MOUSE_DOWN, onHThumbDownMouse);
		_hThumb.addEventListener(TouchEvent.TOUCH_BEGIN, onHThumbDownTouch);

		_window.addChild(_vTrack); _window.addChild(_vThumb);
		_window.addChild(_hTrack); _window.addChild(_hThumb);
	}

	// ------------------------------------------------------------------
	// 构建：工具栏（debug 开关 / 清空 / 导出）
	// ------------------------------------------------------------------
	private function buildToolbar():Void
	{
		_toolbar = new Sprite();
		_toolbar.mouseEnabled = true;
		_toolbar.mouseChildren = true;
		_window.addChild(_toolbar);

		_btnDebug = makeToolButton('game_log_btn_debug', 'DEBUG', toggleDebug);
		_btnClear = makeToolButton('game_log_btn_clear', '清空', clearLogs);
		_btnExport = makeToolButton('game_log_btn_export', '导出', exportLogs);
		_window.addChild(_btnDebug);
		_window.addChild(_btnClear);
		_window.addChild(_btnExport);

		_statusTF = new TextField();
		_statusTF.selectable = false;
		_statusTF.mouseEnabled = false;
		_statusTF.autoSize = openfl.text.TextFieldAutoSize.LEFT;
		_statusTF.multiline = false;
		_statusTF.wordWrap = false;
		_statusTF.antiAliasType = AntiAliasType.ADVANCED;
		_statusTF.gridFitType = GridFitType.PIXEL;
		_statusTF.visible = false;
		_statusTF.htmlText = '<font face="' + fontName + '" size="16" color="#9FE09F"> </font>';
		_window.addChild(_statusTF);
	}

	private function makeToolButton(key:String, fallback:String, onClick:Void->Void):Sprite
	{
		var s = new Sprite();
		s.mouseEnabled = true;
		s.mouseChildren = false;
		_toolLabels.set(s, [key, fallback]);
		var tf = new TextField();
		tf.selectable = false;
		tf.mouseEnabled = false;
		tf.autoSize = openfl.text.TextFieldAutoSize.NONE;
		tf.antiAliasType = AntiAliasType.ADVANCED;
		tf.gridFitType = GridFitType.SUBPIXEL;
		tf.htmlText = toolButtonHtml(s);
		s.addChild(tf);
		s.addEventListener(MouseEvent.MOUSE_DOWN, function(e:MouseEvent){ e.stopPropagation(); e.stopImmediatePropagation(); });
		s.addEventListener(MouseEvent.CLICK, function(e:MouseEvent){ e.stopPropagation(); e.stopImmediatePropagation(); onClick(); });
		// 焦点反馈：桌面 hover / 移动端按下态
		s.addEventListener(MouseEvent.MOUSE_OVER, function(e:MouseEvent){ _toolHover.set(s, true); redrawToolbar(); });
		s.addEventListener(MouseEvent.MOUSE_OUT, function(e:MouseEvent){ _toolHover.set(s, false); redrawToolbar(); });
		s.addEventListener(TouchEvent.TOUCH_BEGIN, function(e:TouchEvent){ e.stopPropagation(); e.stopImmediatePropagation(); _toolHover.set(s, true); redrawToolbar(); });
		s.addEventListener(TouchEvent.TOUCH_END, function(e:TouchEvent){ e.stopPropagation(); e.stopImmediatePropagation(); _toolHover.set(s, false); redrawToolbar(); });
		return s;
	}

	/** 窗口标题：构造 / 重排 / 语言切换时都会重新取词。 */
	private function setTitleText():Void
	{
		if (_titleTF == null) return;
		_titleTF.htmlText = '<font face="' + fontName + '" size="16" color="#F2F2F6"><b>'
			+ escapeHtml(tr('game_log_title', '游戏日志')) + '</b></font>';
	}

	/** 工具栏按钮文本：每次取词，保证语言切换 / 重排后都是当前语言。 */
	private function toolButtonHtml(btn:Sprite):String
	{
		var labels = _toolLabels.get(btn);
		if (labels == null) return "";
		return '<p align="center"><font face="' + fontName + '" size="16" color="#E6E6EA">'
			+ escapeHtml(tr(labels[0], labels[1])) + '</font></p>';
	}

	/** 语言切换时刷新所有静态文案（按钮只换 htmlText，不重排布局）。 */
	private function refreshLocalizedTexts():Void
	{
		setTitleText();
		for (btn in [_btnDebug, _btnClear, _btnExport])
		{
			if (btn == null) continue;
			var tf:TextField = cast btn.getChildAt(0);
			tf.htmlText = toolButtonHtml(btn);
		}
	}

	private function redrawToolbar():Void
	{
		if (_toolbar == null) return;
		var pad = 6 * _winS;
		var gap = 4 * _winS;
		var h = _toolH - 8 * _winS;
		var y = _titleH + (_toolH - h) * 0.5;
		var x0 = pad;
		x0 = drawToolBtn(_btnDebug, x0, y, TB_DEBUG_W * _winS, h, showDebug, _toolHover.get(_btnDebug) == true); x0 += gap;
		x0 = drawToolBtn(_btnClear, x0, y, TB_CLEAR_W * _winS, h, false, _toolHover.get(_btnClear) == true); x0 += gap;
		x0 = drawToolBtn(_btnExport, x0, y, TB_EXPORT_W * _winS, h, false, _toolHover.get(_btnExport) == true);

		if (_statusTF != null)
		{
			_statusTF.x = x0 + 8 * _winS;
			_statusTF.y = _titleH + (_toolH - _statusTF.textHeight) * 0.5;
			_statusTF.width = Math.max(10, _winW - _statusTF.x - 6 * _winS);
		}
	}

	private function drawToolBtn(btn:Sprite, x:Float, y:Float, w:Float, h:Float, active:Bool, hover:Bool = false):Float
	{
		var g = btn.graphics; g.clear();
		var bg = active ? (hover ? 0x3F86D0 : 0x2F6DB0) : (hover ? 0x3A3A46 : 0x2A2A34);
		var bgA = active ? 0.95 : (hover ? 0.95 : 0.85);
		var border = active ? 0x6FB0FF : (hover ? 0x8A8A96 : 0x55555F);
		g.beginFill(bg, bgA);
		g.lineStyle(1 * _winS, border, 0.6);
		g.drawRoundRect(0, 0, w, h, h * 0.3);
		g.endFill();
		btn.x = x; btn.y = y;
		var tf:TextField = cast btn.getChildAt(0);
		tf.width = w; tf.height = h;
		tf.htmlText = toolButtonHtml(btn); // 重排时重新取词（语言切换后自动生效）
		tf.y = (h - tf.textHeight) * 0.5;
		return x + w;
	}

	private static function classifyLevel(msg:String):Int
	{
		var m = msg.toLowerCase();
		if (m.indexOf("error") != -1 || m.indexOf("错误") != -1) return LV_ERROR;
		if (m.indexOf("warn") != -1 || m.indexOf("warning") != -1) return LV_WARN;
		if (m.indexOf("debug") != -1) return LV_DEBUG;
		return LV_INFO;
	}

	/** 崩溃记录入口（由 backend.CrashHandler 调用）：ERROR 级别、红色，带 [CRASH] 标记。 */
	public function addLogError(message:String, ?stack:String):Void
	{
		var timestamp = Timer.stamp();
		var full = "[CRASH] " + message;
		if (stack != null && stack.length > 0) full += "\n" + stack;
		var entry:LogEntry = { timestamp: timestamp, message: full, location: "", source: "crash", level: LV_ERROR, color: null, cls: "", method: "" };
		logs.push(entry);
		if (logs.length > maxLogs) logs.shift();
		markDirty();
	}

	public function addLogDebug(message:String):Void
	{
		var timestamp = Timer.stamp();
		var entry:LogEntry = { timestamp: timestamp, message: message, location: "", source: "debug", level: LV_DEBUG, color: null, cls: "", method: "" };
		logs.push(entry);
		if (logs.length > maxLogs) logs.shift();
		markDirty();
	}

	public function clearLogs():Void
	{
		logs = [];
		markDirty();
		showStatus(tr('game_log_status_cleared', '已清空日志'));
	}

	public function toggleDebug():Void
	{
		showDebug = !showDebug;
		redrawToolbar();
		markDirty();
		showStatus(showDebug
			? tr('game_log_status_debug_on', '已显示 DEBUG 日志')
			: tr('game_log_status_debug_off', '已隐藏 DEBUG 日志'));
	}

	public function exportLogs():Void
	{
		var sb = new StringBuf();
		for (e in logs)
		{
			var lvl = "INFO";
			if (e.level == LV_WARN) lvl = "WARN";
			else if (e.level == LV_ERROR) lvl = "ERROR";
			else if (e.level == LV_DEBUG) lvl = "DEBUG";
			sb.add("[" + lvl + "] " + e.message + (e.location != "" ? "  (" + e.location + ")" : "") + "\n");
		}
		var text = sb.toString();
		#if sys
		try
		{
			// 每次导出都重新取根目录：用户在设置页切换存储位置后应立即生效，不能缓存
			var root = getLogRoot();
			var logsDir = root + "/logs";
			if (!sys.FileSystem.exists(logsDir)) sys.FileSystem.createDirectory(logsDir);
			var outDir = logsDir + "/output";
			if (!sys.FileSystem.exists(outDir)) sys.FileSystem.createDirectory(outDir);
			var ts = Date.now().toString();
			ts = StringTools.replace(StringTools.replace(ts, ":", "-"), " ", "_");
			var path = outDir + "/FNF_log_" + ts + ".txt";
			sys.io.File.saveContent(path, text);
			showStatus(tr('game_log_status_exported', '已导出至 {0}', [path]));
		}
		catch (e:Dynamic)
		{
			showStatus(tr('game_log_status_export_failed', '导出失败：{0}', [Std.string(e)]));
		}
		#else
		showStatus(tr('game_log_status_export_unsupported', '导出仅支持桌面/手机编译版本'));
		#end
	}

	// 日志导出的「用户数据根目录」：与 backend.CrashHandler / backend.Paths / backend.Mods 同一套。
	//  - Android：StorageUtil.getExternalStorageDirectory() 会按设置页的存储位置
	//    （Data / Media / Obb / External）动态返回根目录，切换后立即生效（setStorageType 会刷新缓存），
	//    并且内部已处理「无所有文件访问权限」时回退到应用私有目录。
	//  - iOS：沙盒内可写的 Documents 目录（与 StorageUtil.getStorageDirectory 一致）。
	//  - 桌面：工作目录（与崩溃日志一致，避免再出现两个目录）。
	// 最终写入 <root>/logs/output/，与崩溃日志共用 logs 文件夹。
	private function getLogRoot():String
	{
		var base:String = "";
		#if android
			base = StorageUtil.getExternalStorageDirectory();
		#elseif ios
			base = System.documentsDirectory;
		#elseif sys
			base = Sys.getCwd();
		#else
			base = "";
		#end
		if (base == null || base.length == 0) return "";
		// 统一去掉结尾斜杠，拼接时用 / 分隔（Windows 下 openfl/lime 同样接受正斜杠）
		var last = base.charAt(base.length - 1);
		if (last == "/" || last == "\\") base = base.substr(0, base.length - 1);
		return base;
	}

	private function showStatus(msg:String):Void
	{
		if (_statusTF == null) return;
		_statusTF.htmlText = '<font face="' + fontName + '" size="16" color="#9FE09F">' + escapeHtml(msg) + '</font>';
		_statusTF.visible = true;
		if (_statusTimer != null) { _statusTimer.stop(); _statusTimer = null; }
		_statusTimer = new haxe.Timer(2600);
		_statusTimer.run = function()
		{
			if (_statusTF != null) _statusTF.visible = false;
			if (_statusTimer != null) { _statusTimer.stop(); _statusTimer = null; }
		};
	}

	// ------------------------------------------------------------------
	// 事件接线（stage 级）
	// ------------------------------------------------------------------
	private function onAddedToStage(e:Event):Void
	{
		removeEventListener(Event.ADDED_TO_STAGE, onAddedToStage);
		var stage = Lib.current.stage;
		if (stage == null) return;

		stage.addEventListener(MouseEvent.MOUSE_MOVE, onStageMoveMouse);
		stage.addEventListener(MouseEvent.MOUSE_UP, onStageUpMouse);
		stage.addEventListener(TouchEvent.TOUCH_MOVE, onStageMoveTouch);
		stage.addEventListener(TouchEvent.TOUCH_END, onStageUpTouch);

		// Language.load() 会通知所有回调；此时（或运行中切换语言）立即刷新静态文案
		try { Language.addCallback(refreshLocalizedTexts); } catch (e:Dynamic) {}
	}

	// ------------------------------------------------------------------
	// 缩放计算
	// ------------------------------------------------------------------
	private function recomputeScale():Void
	{
		_uiScale = uiScaleVal();
		_winS = _mobile ? Math.max(_uiScale, 1.25) : _uiScale;
		_touchS = _mobile ? Math.max(_uiScale, 1.5) : _uiScale;
		fontSize = 16; // unifont 在 16px 时最清晰，故所有文本固定 16 不缩放
	}

	private function uiScaleVal():Float
	{
		#if mac
		return 1;
		#else
		var w = Lib.application.window;
		if (w == null) return 1;
		var s = w.scale;
		if (s > 1.01) return 1;
		var dpi = 96.0;
		if (w.display != null && w.display.dpi > 0) dpi = w.display.dpi;
		return Math.min(3.0, Math.max(1.0, dpi / 96.0));
		#end
	}

	// ------------------------------------------------------------------
	// trace 劫持
	// ------------------------------------------------------------------
	private function hookTrace():Void
	{
		originalTrace = haxe.Log.trace;
		haxe.Log.trace = function(v:Dynamic, ?pos:haxe.PosInfos):Void
		{
			if (originalTrace != null) originalTrace(v, pos);
			addLog(v, pos);
		};
	}

	public function addLog(message:Dynamic, ?pos:haxe.PosInfos):Void
	{
		var timestamp = Timer.stamp();
		var timeStr = StringTools.lpad(Std.string(Math.floor(timestamp % 3600)), "0", 2) + ":" +
		             StringTools.lpad(Std.string(Math.floor((timestamp % 60) * 60)), "0", 2);

		var location = "";
		if (pos != null) location = pos.fileName + ":" + pos.lineNumber;

		var entry:LogEntry = { timestamp: timestamp, message: Std.string(message), location: location, source: "trace", level: classifyLevel(Std.string(message)), color: null, cls: (pos != null ? pos.className : ""), method: (pos != null ? pos.methodName : "") };
		logs.push(entry);
		if (logs.length > maxLogs) logs.shift();
		markDirty();

		if (onLogAdded != null)
		{
			try { onLogAdded(message); } catch (e:Dynamic) {}
		}
	}

	public function addLogWithColor(message:String, color:flixel.util.FlxColor):Void
	{
		var timestamp = Timer.stamp();
		var entry:LogEntry = { timestamp: timestamp, message: message, location: "", source: "lua", level: classifyLevel(message), color: color, cls: "", method: "" };
		logs.push(entry);
		if (logs.length > maxLogs) logs.shift();
		markDirty();
	}

	// ------------------------------------------------------------------
	// 显示内容刷新
	// ------------------------------------------------------------------
	private function markDirty():Void
	{
		// 仅标记“有改动”，真正的 TextField 重建推迟到下一帧 onFrame 中统一执行，
		// 这样一帧内多次 addLog 只会触发一次 updateDisplay，显著降低低端设备重绘开销。
		_logDirty = true;
	}

	private function updateDisplay():Void
	{
		if (!isEnabled || _logText == null) return;

		var sb = new StringBuf();
		sb.add('<font face="' + fontName + '" size="' + fontSize + '">');
		for (i in 0...logs.length)
		{
			var entry = logs[i];
			if (!showDebug && entry.level == LV_DEBUG) continue;
			var timeStr = StringTools.lpad(Std.string(Math.floor((entry.timestamp % 60) * 60)), "0", 2) + ":" +
			             StringTools.lpad(Std.string(Math.floor((entry.timestamp * 1000) % 1000)), "0", 3);

			var colorHex = "#FFFFFF";
			if (entry.color != null)
				colorHex = '#' + StringTools.hex(entry.color, 6);
			else
			{
				var msg = entry.message.toLowerCase();
				if (msg.indexOf("error") != -1 || msg.indexOf("错误") != -1) colorHex = "#FF5555";
				else if (msg.indexOf("warn") != -1 || msg.indexOf("warning") != -1) colorHex = "#FFB454";
				else if (msg.indexOf("debug") != -1) colorHex = "#AAAAAA";
			}

			var prefix = "[LOG]";
			if (entry.source == "lua") prefix = "[LUA]";
			else if (entry.source == "crash") prefix = "[CRASH]";

			// 来源标签：普通模式显示 文件:行号；DEBUG 模式额外显示 类名.方法（真 debug 编译风格）
			var srcTag = "";
			if (entry.location != null && entry.location != "")
			{
				srcTag = entry.location;
				if (showDebug && entry.cls != null && entry.cls != "")
				{
					var cm = entry.cls + (entry.method != null && entry.method != "" ? "." + entry.method : "");
					srcTag = cm + " (" + srcTag + ")";
				}
				srcTag = ' <font color="#8A8A99">' + escapeHtml(srcTag) + '</font>';
			}

			sb.add('<font color="' + colorHex + '">[' + timeStr + '] ' + prefix + srcTag + ' ' + escapeHtml(entry.message) + '</font>\n');
		}
		sb.add('</font>');
		_logText.htmlText = sb.toString();

		// 记录是否在底部（用于新日志时自动贴底）
		var wasAtBottom = (_maxScrollY <= 0) || (_scrollY >= _maxScrollY - 2);
		relayoutScroll();
		if (wasAtBottom) _scrollY = _maxScrollY;
		clampScroll();
		updateScrollbars();
	}

	private static function escapeHtml(s:String):String
	{
		return StringTools.replace(StringTools.replace(StringTools.replace(s, "&", "&amp;"), "<", "&lt;"), ">", "&gt;");
	}

	/**
	 * 取本地化文案：模组 .lang > 当前语言 JSON > 内置中文兜底。
	 * Language.load() 可能尚未执行或加载失败（此时 get() 会返回裸 key），故整段 try/catch，
	 * 兜底文案自己也要替换 {0} / {$0} 占位符。
	 */
	private static function tr(key:String, fallback:String, ?params:Array<Dynamic>):String
	{
		try
		{
			var v:String = Language.getWithFallback(key, fallback, params);
			if (v != null && v.length > 0) return v;
		}
		catch (e:Dynamic) {}
		return applyParams(fallback, params);
	}

	private static function applyParams(s:String, ?params:Array<Dynamic>):String
	{
		if (s == null) return "";
		if (params == null) return s;
		for (i in 0...params.length)
		{
			s = StringTools.replace(s, '{$' + i + '}', Std.string(params[i]));
			s = StringTools.replace(s, '{' + i + '}', Std.string(params[i]));
		}
		return s;
	}

	// ------------------------------------------------------------------
	// 布局：启动按钮
	// ------------------------------------------------------------------
	private function layoutLauncher():Void
	{
		var r = 22 * _winS;
		_launchW = r * 2; _launchH = r * 2;
		var g = _launchBg.graphics;
		g.clear();
		g.beginFill(0x23232B, 0.82);
		g.lineStyle(1.5 * _touchS, 0x6E6E82, 0.55);
		g.drawCircle(r, r, r);
		g.endFill();

		// 简易“日志”图标：三条横线
		var ig = _launchIcon.graphics;
		ig.clear();
		ig.beginFill(0xF2F2F6, 0.95);
		var lw = r * 1.05, lh = 3 * _touchS, gap = 7 * _touchS;
		for (i in 0...3)
		{
			var yy = r - gap + i * gap;
			ig.drawRoundRect(r - lw / 2, yy - lh / 2, lw, lh, lh / 2);
		}
		ig.endFill();
	}

	// ------------------------------------------------------------------
	// 布局：窗口
	// ------------------------------------------------------------------
	private function layoutWindow():Void
	{
		recomputeScale();

		var stage = Lib.current.stage;
		var sw = stage != null ? stage.stageWidth : 1280;
		var sh = stage != null ? stage.stageHeight : 720;

		var baseW = 460 * _winS;   // 默认小窗：加宽
		var baseH = 300 * _winS;
		var maxW = sw * 0.70;
		var maxH = sh * 0.70;

		// 用动画进度在“默认尺寸”与“最大化”之间插值（_maxAnim 由 onFrame 缓动）
		_winW = lerp(baseW, maxW, _maxAnim);
		_winH = lerp(baseH, maxH, _maxAnim);

		_titleH = 32 * _winS;           // 标题栏压扁一些（原 44*_winS）
		_toolH = 30 * _winS; // 容纳固定 16px 工具栏字体，避免裁切
		_contentX = 8 * _winS;
		_contentY = _titleH + _toolH + 4 * _winS;

		// 背景
		var g = _winBg.graphics;
		g.clear();
		g.beginFill(0x1A1A22, 0.82);
		g.lineStyle(1.2 * _winS, 0x6A6A7A, 0.5);
		g.drawRoundRect(0, 0, _winW, _winH, 12 * _winS);
		g.endFill();
		// 顶部高光
		g.beginFill(0x3A3A46, 0.45);
		g.drawRoundRect(1, 1, _winW - 2, 3 * _winS, 2 * _winS);
		g.endFill();

		// 标题栏
		var tg = _titleBar.graphics;
		tg.clear();
		tg.beginFill(0x262630, 0.92);
		// 与窗口控制按钮使用相同的小圆角，避免黑块顶部大圆角造成的“比按钮高”错觉
		tg.drawRoundRect(0, 0, _winW, _titleH, 3 * _winS);
		tg.drawRect(0, _titleH - 3 * _winS, _winW, 3 * _winS); // 补齐标题栏下沿方角
		tg.endFill();
		_titleBar.y = 0;
		setTitleText();
		_titleTF.x = 12 * _winS;
		_titleTF.y = (_titleH - _titleTF.textHeight) * 0.5;

		// 按钮
		var bw = 32 * _winS;           // 窗口控制按钮压扁一些
		_btnClose.x = _winW - bw; _btnClose.y = 0;
		_btnMax.x = _winW - bw * 2; _btnMax.y = 0;
		_btnMin.x = _winW - bw * 3; _btnMin.y = 0;
		redrawButtons();

		// 工具栏背景
		var tg2 = _toolbar.graphics; tg2.clear();
		tg2.beginFill(0x20202A, 0.92);
		tg2.drawRect(0, _titleH, _winW, _toolH);
		tg2.endFill();
		redrawToolbar();

		relayoutScroll();
	}

	private function redrawButtons():Void
	{
		drawWinButton(_btnMin, 0, _hoverBtn == 0);
		drawWinButton(_btnMax, 1, _hoverBtn == 1);
		drawWinButton(_btnClose, 2, _hoverBtn == 2);
	}

	private function drawWinButton(btn:Sprite, kind:Int, hover:Bool):Void
	{
		var bw = 32 * _winS;
		var bh = _titleH;
		var g = btn.graphics;
		g.clear();
		var bg = (kind == 2) ? (hover ? 0xE81123 : 0x4A2024) : (hover ? 0x3A3A46 : 0x2D2D38);
		g.beginFill(bg, hover ? 1 : 0.55);
		// 按钮背景 = 满高、近乎直角的矩形，与标题栏黑块严格等高（圆角过大曾被看成矮一截）
		g.drawRoundRect(0, 0, bw, bh, 3 * _winS);
		g.endFill();

		var cx = bw * 0.5;
		var cy = bh * 0.5;
		var col = (hover && kind == 2) ? 0xFFFFFF : 0xE6E6EA;
		g.lineStyle(1.4 * _winS, col, 1);

		switch (kind)
		{
			case 0: // 最小化
				g.moveTo(cx - 6 * _winS, cy + 4 * _winS);
				g.lineTo(cx + 6 * _winS, cy + 4 * _winS);
			case 1: // 最大化 / 还原
				if (_isMaximized)
				{
					g.drawRect(cx - 7 * _winS, cy - 3 * _winS, 10 * _winS, 10 * _winS);
					g.moveTo(cx - 3 * _winS, cy - 7 * _winS);
					g.lineTo(cx + 7 * _winS, cy - 7 * _winS);
					g.lineTo(cx + 7 * _winS, cy + 3 * _winS);
				}
				else
				{
					g.drawRect(cx - 6 * _winS, cy - 6 * _winS, 12 * _winS, 12 * _winS);
				}
			case 2: // 关闭
				g.moveTo(cx - 5 * _winS, cy - 5 * _winS);
				g.lineTo(cx + 5 * _winS, cy + 5 * _winS);
				g.moveTo(cx + 5 * _winS, cy - 5 * _winS);
				g.lineTo(cx - 5 * _winS, cy + 5 * _winS);
		}
	}

	private function onWinButton(kind:Int):Void
	{
		switch (kind)
		{
			case 0: minimize();          // 最小化 -> 收起为按钮
			case 1: toggleMaximize();    // 最大化 / 还原
			case 2: minimize();          // 关闭 -> 同样收起为按钮（启动按钮是常驻入口）
		}
	}

	// ------------------------------------------------------------------
	// 布局：滚动区
	// ------------------------------------------------------------------
	private function relayoutScroll():Void
	{
		if (_logText == null) return;
		var inner = 6 * _winS;
		_contentW = _logText.textWidth + inner * 2;
		_contentH = _logText.textHeight + inner * 2;

		var pad = 8 * _winS;
		var sbSize = 10 * _touchS;

		// 先按“可能两条滚动条都出现”预估视口
		var provW = _winW - pad * 2 - sbSize;
		var provH = _winH - _contentY - pad - sbSize;
		_vScrollVisible = _contentH > provH + 1;
		_hScrollVisible = _contentW > provW + 1;

		_vpW = _winW - pad * 2 - (_vScrollVisible ? sbSize : 0);
		_vpH = _winH - _contentY - pad - (_hScrollVisible ? sbSize : 0);

		_maxScrollX = Math.max(0, _contentW - _vpW);
		_maxScrollY = Math.max(0, _contentH - _vpH);

		// 面具（裁剪）
		var mg = _contentMask.graphics;
		mg.clear();
		mg.beginFill(0x000000, 1);
		mg.drawRoundRect(_contentX, _contentY, _vpW, _vpH, 6 * _winS);
		mg.endFill();

		// 内容偏移
		_contentScroll.x = _contentX - _scrollX;
		_contentScroll.y = _contentY - _scrollY;
		// 文本内边距
		_logText.x = inner; _logText.y = inner;

		// 命中区
		var hg = _contentHit.graphics;
		hg.clear();
		hg.beginFill(0xFFFFFF, 0.001);
		hg.drawRect(_contentX, _contentY, _vpW, _vpH);
		hg.endFill();

		updateScrollbars();
	}

	private function clampScroll():Void
	{
		if (_scrollX < 0) _scrollX = 0;
		if (_scrollX > _maxScrollX) _scrollX = _maxScrollX;
		if (_scrollY < 0) _scrollY = 0;
		if (_scrollY > _maxScrollY) _scrollY = _maxScrollY;
	}

	private function updateScrollbars():Void
	{
		var sbSize = 10 * _touchS;
		var pad = 8 * _winS;
		var trackX = _winW - pad - sbSize;
		var trackY = _contentY;
		var trackH = _vpH;
		var trackW = _vpW;
		var trackX2 = _contentX;
		var trackY2 = _winH - pad - sbSize;

		// 垂直
		var vg = _vTrack.graphics; vg.clear();
		var vtg = _vThumb.graphics; vtg.clear();
		if (_vScrollVisible)
		{
			vg.beginFill(0x000000, 0.35);
			vg.drawRoundRect(trackX, trackY, sbSize, trackH, sbSize * 0.5);
			vg.endFill();
			_vTrackY = trackY; _vTrackH = trackH;
			_vThumbH = Math.max(24 * _touchS, (_vpH / _contentH) * trackH);
			_vThumbH = Math.min(_vThumbH, trackH);
			var ratio = _maxScrollY > 0 ? _scrollY / _maxScrollY : 0;
			_vThumbY = trackY + ratio * (trackH - _vThumbH);
			vtg.beginFill(0x8A8A9A, 0.85);
			vtg.lineStyle(1 * _touchS, 0xB8B8C4, 0.6);
			vtg.drawRoundRect(trackX, _vThumbY, sbSize, _vThumbH, sbSize * 0.5);
			vtg.endFill();
			_vThumb.visible = true; _vTrack.visible = true;
		}
		else
		{
			_vThumb.visible = false; _vTrack.visible = false;
		}

		// 水平
		var hg = _hTrack.graphics; hg.clear();
		var htg = _hThumb.graphics; htg.clear();
		if (_hScrollVisible)
		{
			hg.beginFill(0x000000, 0.35);
			hg.drawRoundRect(trackX2, trackY2, trackW, sbSize, sbSize * 0.5);
			hg.endFill();
			_hTrackX = trackX2; _hTrackW = trackW;
			_hThumbW = Math.max(24 * _touchS, (_vpW / _contentW) * trackW);
			_hThumbW = Math.min(_hThumbW, trackW);
			var ratio = _maxScrollX > 0 ? _scrollX / _maxScrollX : 0;
			_hThumbX = trackX2 + ratio * (trackW - _hThumbW);
			htg.beginFill(0x8A8A9A, 0.85);
			htg.lineStyle(1 * _touchS, 0xB8B8C4, 0.6);
			htg.drawRoundRect(_hThumbX, trackY2, _hThumbW, sbSize, sbSize * 0.5);
			htg.endFill();
			_hThumb.visible = true; _hTrack.visible = true;
		}
		else
		{
			_hThumb.visible = false; _hTrack.visible = false;
		}
	}

	// ------------------------------------------------------------------
	// 启用 / 展开 / 收起
	// ------------------------------------------------------------------
	public function setEnabled(enabled:Bool):Void
	{
		isEnabled = enabled;
		if (!enabled)
		{
			_windowOpen = false;
			_isMaximized = false;
			_maxAnim = 0;
			_maxAnimating = false;
		}
		else
		{
			// 启用后默认显示启动按钮（窗口收起），方便随时调出
			recomputeScale();
			layoutLauncher();
			layoutWindow(); // 预先算好窗口几何，保证日志在窗口未展开时也能正确测量
			if (!_windowOpen)
			{
				var stage = Lib.current.stage;
				if (stage != null)
				{
					_launchTX = stage.stageWidth - _launchW - 16 * _touchS;
					_launchTY = stage.stageHeight - _launchH - 16 * _touchS;
					if (_launchX == 0 && _launchY == 0) { _launchX = _launchTX; _launchY = _launchTY; }
				}
			}
		}
		refreshAnimTargets();
	}

	public function toggleVisibility():Void
	{
		if (!isEnabled) return;
		setWindowOpen(!_windowOpen);
	}

	private function setWindowOpen(open:Bool):Void
	{
		if (!isEnabled) return;
		if (open && !_windowOpen)
		{
			openWindow();
		}
		else if (!open && _windowOpen)
		{
			minimize();
		}
	}

	public function minimize():Void
	{
		if (!_windowOpen) return;
		_windowOpen = false;
		_maxAnimating = false;
		_dragMode = DRAG_NONE; _dragging = false; _pressActive = false;
		layoutLauncher();
		refreshAnimTargets();
	}

	private function openWindow():Void
	{
		_windowOpen = true;
		_isMaximized = false;
		_maxAnim = 0;
		_maxAnimating = false;
		var stage = Lib.current.stage;
		if (stage != null)
		{
			layoutWindow();
			// 默认出现在屏幕中央（窗口允许滑到游戏窗口之外，故不强制夹紧）
			_winTX = (stage.stageWidth - _winW) * 0.5;
			_winTY = (stage.stageHeight - _winH) * 0.5;
			if (_winX == 0 && _winY == 0) { _winX = _winTX; _winY = _winTY; }
		}
		updateDisplay();   // 打开时立刻重建一次（关闭期间跳过的重绘在此补上）
		_logDirty = false;
		refreshAnimTargets();
	}

	private function toggleMaximize():Void
	{
		if (!_windowOpen) { openWindow(); return; }
		// 记录当前右上角作为动画锚点，使最大化/还原从该角展开
		_anchorX = _winX + _winW;
		_anchorY = _winY;
		_isMaximized = !_isMaximized;
		_maxAnimating = true;
		redrawButtons();   // 图标立即切换；尺寸由 onFrame 缓动动画过渡（基于右上角锚点）
	}

	private function refreshAnimTargets():Void
	{
		_launchAnimTarget = (isEnabled && !_windowOpen) ? 1 : 0;
		_winAnimTarget = (isEnabled && _windowOpen) ? 1 : 0;
	}

	// ------------------------------------------------------------------
	// 每帧更新（动画 + 重定位 + 拖拽跟随）
	// ------------------------------------------------------------------
	private function onFrame(e:Event):Void
	{
		var now = Timer.stamp();
		var dt = _lastT > 0 ? Math.min(0.1, now - _lastT) : 0.016;
		_lastT = now;

		// 启动按钮动画 / 位置
		if (_launchAnim != _launchAnimTarget)
		{
			_launchAnim += (_launchAnimTarget - _launchAnim) * Math.min(1, dt * 18);
			if (Math.abs(_launchAnim - _launchAnimTarget) < 0.01) _launchAnim = _launchAnimTarget;
		}
		_launcher.visible = _launchAnim > 0.02;
		_launcher.alpha = _launchAnim;
		_launcher.scaleX = _launcher.scaleY = 0.9 + 0.1 * _launchAnim;

		// 窗口动画
		if (_winAnim != _winAnimTarget)
		{
			_winAnim += (_winAnimTarget - _winAnim) * Math.min(1, dt * 18);
			if (Math.abs(_winAnim - _winAnimTarget) < 0.01) _winAnim = _winAnimTarget;
		}
		_window.visible = _winAnim > 0.02;
		_window.alpha = _winAnim;
		_window.scaleX = _window.scaleY = 0.94 + 0.06 * _winAnim;

		// 最大化 / 还原 尺寸动画：基于右上角锚点缓动（窗口可滑到游戏窗口之外）
		var maxTarget = _isMaximized ? 1 : 0;
		if (_maxAnim != maxTarget)
		{
			_maxAnim += (maxTarget - _maxAnim) * Math.min(1, dt * 14);
			if (Math.abs(_maxAnim - maxTarget) < 0.01) _maxAnim = maxTarget;
			if (_windowOpen) { layoutWindow(); }
			if (_maxAnimating)
			{
				// 保持右上角固定，窗口向“左下”方向放大 / 还原
				_winY = _anchorY;
				_winX = _anchorX - _winW;
				_winTX = _winX; _winTY = _winY; // 同步目标，动画结束后续拖拽以此为准
			}
		}
		if (_maxAnim == maxTarget && _maxAnimating) _maxAnimating = false;

		// 批量刷新日志文本：仅在窗口打开且内容确有变动时重建一次 TextField
		if (_logDirty)
		{
			_logDirty = false;
			if (_windowOpen) updateDisplay();
		}

		// 位置缓动（拖动时更跟手，缩放重定位时更柔和）
		var follow = (_dragMode == DRAG_LAUNCHER || _dragMode == DRAG_WINDOW) ? 0.5 : 0.22;
		_launchX += (_launchTX - _launchX) * Math.min(1, dt * 60 * follow);
		_launchY += (_launchTY - _launchY) * Math.min(1, dt * 60 * follow);
		_launcher.x = _launchX; _launcher.y = _launchY;

		_winX += (_winTX - _winX) * Math.min(1, dt * 60 * follow);
		_winY += (_winTY - _winY) * Math.min(1, dt * 60 * follow);
		_window.x = _winX; _window.y = _winY;
	}

	// ------------------------------------------------------------------
	// 指针交互
	// ------------------------------------------------------------------
	private function onLauncherDownMouse(e:MouseEvent):Void { e.stopPropagation(); e.stopImmediatePropagation(); beginLauncherPress(e.stageX, e.stageY); }
	private function onLauncherDownTouch(e:TouchEvent):Void { e.stopPropagation(); e.stopImmediatePropagation(); beginLauncherPress(e.stageX, e.stageY); }

	private function beginLauncherPress(sx:Float, sy:Float):Void
	{
		_pressActive = true;
		_dragMode = DRAG_LAUNCHER;
		_dragging = true;     // 按下即进入拖动（去掉长按延迟）
		_moved = false;
		_pressStageX = sx; _pressStageY = sy;
		_grabX = _launchX - sx;
		_grabY = _launchY - sy;
	}

	private function onTitleDownMouse(e:MouseEvent):Void { e.stopPropagation(); e.stopImmediatePropagation(); beginWindowDrag(e.stageX, e.stageY); }
	private function onTitleDownTouch(e:TouchEvent):Void { e.stopPropagation(); e.stopImmediatePropagation(); beginWindowDrag(e.stageX, e.stageY); }

	private function beginWindowDrag(sx:Float, sy:Float):Void
	{
		_pressActive = true;
		_dragMode = DRAG_WINDOW;
		_dragging = true;
		_grabX = _winX - sx; _grabY = _winY - sy;
	}

	private function onContentDownMouse(e:MouseEvent):Void { e.stopPropagation(); e.stopImmediatePropagation(); beginContentDrag(e.stageX, e.stageY); }
	private function onContentDownTouch(e:TouchEvent):Void { e.stopPropagation(); e.stopImmediatePropagation(); beginContentDrag(e.stageX, e.stageY); }

	private function beginContentDrag(sx:Float, sy:Float):Void
	{
		_pressActive = true;
		_dragMode = DRAG_CONTENT;
		_dragging = true;
		_startScrollX = _scrollX; _startScrollY = _scrollY;
		_pressStageX = sx; _pressStageY = sy;
	}

	private function onVThumbDownMouse(e:MouseEvent):Void { e.stopPropagation(); e.stopImmediatePropagation(); beginVScroll(e.stageX, e.stageY); }
	private function onVThumbDownTouch(e:TouchEvent):Void { e.stopPropagation(); e.stopImmediatePropagation(); beginVScroll(e.stageX, e.stageY); }

	private function beginVScroll(sx:Float, sy:Float):Void
	{
		_pressActive = true;
		_dragMode = DRAG_VSCROLL;
		_dragging = true;
		var localY = sy - _winY;
		_vDragOffset = localY - _vThumbY;
	}

	private function onHThumbDownMouse(e:MouseEvent):Void { e.stopPropagation(); e.stopImmediatePropagation(); beginHScroll(e.stageX, e.stageY); }
	private function onHThumbDownTouch(e:TouchEvent):Void { e.stopPropagation(); e.stopImmediatePropagation(); beginHScroll(e.stageX, e.stageY); }

	private function beginHScroll(sx:Float, sy:Float):Void
	{
		_pressActive = true;
		_dragMode = DRAG_HSCROLL;
		_dragging = true;
		var localX = sx - _winX;
		_hDragOffset = localX - _hThumbX;
	}

	private function onWheel(e:MouseEvent):Void
	{
		e.stopPropagation(); e.stopImmediatePropagation();
		var step = 30 * _winS;
		if (e.shiftKey)
			_scrollX -= e.delta * step;
		else
			_scrollY -= e.delta * step;
		clampScroll();
		_contentScroll.x = _contentX - _scrollX;
		_contentScroll.y = _contentY - _scrollY;
		updateScrollbars();
	}

	private function onStageMoveMouse(e:MouseEvent):Void { handleMove(e.stageX, e.stageY); }
	private function onStageMoveTouch(e:TouchEvent):Void { handleMove(e.stageX, e.stageY); }

	private function handleMove(sx:Float, sy:Float):Void
	{
		_pointerX = sx; _pointerY = sy;
		if (!_pressActive) return;

		switch (_dragMode)
		{
			case DRAG_LAUNCHER:
			if (!_moved && (Math.abs(sx - _pressStageX) > 6 * _touchS || Math.abs(sy - _pressStageY) > 6 * _touchS))
			{
				_moved = true;
			}
				_launchTX = sx + _grabX;
				_launchTY = sy + _grabY;
				clampTarget(false);

			case DRAG_WINDOW:
				_winTX = sx + _grabX;
				_winTY = sy + _grabY;
				clampTarget(true);

			case DRAG_CONTENT:
				_scrollX = _startScrollX - (sx - _pressStageX);
				_scrollY = _startScrollY - (sy - _pressStageY);
				clampScroll();
				_contentScroll.x = _contentX - _scrollX;
				_contentScroll.y = _contentY - _scrollY;
				updateScrollbars();

			case DRAG_VSCROLL:
				var localY = sy - _winY;
				var ty = localY - _vDragOffset;
				ty = clamp(ty, _vTrackY, _vTrackY + _vTrackH - _vThumbH);
				_scrollY = (_vTrackH - _vThumbH) <= 0 ? 0 : (ty - _vTrackY) / (_vTrackH - _vThumbH) * _maxScrollY;
				clampScroll();
				_contentScroll.y = _contentY - _scrollY;
				updateScrollbars();

			case DRAG_HSCROLL:
				var localX = sx - _winX;
				var tx = localX - _hDragOffset;
				tx = clamp(tx, _hTrackX, _hTrackX + _hTrackW - _hThumbW);
				_scrollX = (_hTrackW - _hThumbW) <= 0 ? 0 : (tx - _hTrackX) / (_hTrackW - _hThumbW) * _maxScrollX;
				clampScroll();
				_contentScroll.x = _contentX - _scrollX;
				updateScrollbars();
		}
	}

	private function onStageUpMouse(e:MouseEvent):Void { handleUp(); }
	private function onStageUpTouch(e:TouchEvent):Void { handleUp(); }

	private function handleUp():Void
	{
		if (!_pressActive) return;
		if (_dragMode == DRAG_LAUNCHER && !_moved)
		{
			// 未移动 = 轻点 -> 展开窗口
			openWindow();
		}
		_pressActive = false;
		_dragMode = DRAG_NONE;
		_dragging = false;
		_moved = false;
	}

	private function clearLongPress():Void
	{
		if (_longPressTimer != null) { _longPressTimer.stop(); _longPressTimer = null; }
	}

	private static function clamp(v:Float, a:Float, b:Float):Float
	{
		return v < a ? a : (v > b ? b : v);
	}

	private static function lerp(a:Float, b:Float, t:Float):Float
	{
		return a + (b - a) * t;
	}

	// ------------------------------------------------------------------
	// 重定位：把目标夹紧到可视范围（窗口缩放时调用）
	// ------------------------------------------------------------------
	private function clampTarget(isWindow:Bool):Void
	{
		if (isWindow) return; // 日志窗口允许滑到游戏窗口之外，不夹紧
		var stage = Lib.current.stage;
		if (stage == null) return;
		var sw = stage.stageWidth, sh = stage.stageHeight;
		// 启动按钮必须始终完整留在游戏窗口内
		_launchTX = clamp(_launchTX, 0, Math.max(0, sw - _launchW));
		_launchTY = clamp(_launchTY, 0, Math.max(0, sh - _launchH));
	}

	public function updatePositionOnResize():Void
	{
		var stage = Lib.current.stage;
		if (stage == null) return;

		// 重新计算缩放并刷新布局
		recomputeScale();
		layoutLauncher();
		if (_windowOpen) layoutWindow();

		// 夹紧到新可视范围（带缓动）
		clampTarget(true);
		clampTarget(false);
	}

}

// ------------------------------------------------------------------
// 日志条目结构（模块级 typedef，Haxe 不允许在 class 体内定义）
// ------------------------------------------------------------------
typedef LogEntry = {
	timestamp:Float,
	message:String,
	location:String,  // 文件:行号（来自 haxe.PosInfos）
	source:String,
	level:Int,
	cls:String,       // 类名（DEBUG 模式显示，真 debug 编译风格）
	method:String,    // 方法名（DEBUG 模式显示）
	?color:flixel.util.FlxColor
}
