package debug;

import openfl.display.Sprite;
import openfl.display.Shape;
import openfl.text.TextField;
import openfl.text.TextFieldAutoSize;
import openfl.text.AntiAliasType;
import openfl.text.GridFitType;
import openfl.events.Event;
import openfl.events.MouseEvent;
import openfl.events.TouchEvent;
import openfl.Lib;
import backend.Paths;
import backend.Language;

/**
 * CrashOverlay — 游戏内（OpenFL 层）的未捕获异常提示层。
 *
 * 目标：异常被 preventDefault 吞掉后，游戏不再退出，而是覆盖一层半透明遮罩，
 * 显示完整错误信息 + 调用堆栈，并提供「继续游戏 / 回到主菜单 / 重启游戏」三个选项。
 *
 * 设计约束：
 *  - 纯 OpenFL（不依赖 flixel / states / Main），动作通过静态回调注入，便于独立编译验证。
 *  - 文案走 backend.Language（模组 .lang > assets/languages/{lang}.json > 内置中文兜底），
 *    崩溃时语言系统可能尚未加载，所以每个文案都带内置兜底且整体 try/catch。
 *  - 半透明圆角主题，与 GameLogDisplay 一致；标题 32px、其余 16px（16 的整数倍），ADVANCED + PIXEL 保证清晰。
 *  - 内容支持鼠标滚轮 / 触摸拖动上下滚动，带可拖拽的垂直滚动条。
 *  - 所有交互事件 stopPropagation + stopImmediatePropagation，绝不穿透到游戏内 UI。
 *  - 跟随窗口大小变化重排，始终置顶且覆盖整个画面。
 *
 * 用法（由 backend.CrashHandler 调用）：
 *  CrashOverlay.onContinue = ...; CrashOverlay.onGotoTitle = ...; CrashOverlay.onRestartApp = ...;
 *  CrashOverlay.show(message, stack);
 */
class CrashOverlay extends Sprite
{
	// ---- 注入的动作回调 ----
	public static var onContinue:()->Void = null;
	public static var onGotoTitle:()->Void = null;
	public static var onRestartApp:()->Void = null;
	/** 弹层被用户关闭时通知外部（用于清理待处理异常、进入短暂静默期、恢复鼠标）。 */
	public static var onDismiss:()->Void = null;

	private static var _instance:CrashOverlay = null;

	// unifont 在 16px 最锐利；标题取 16 的整数倍放大，既是点阵整数倍、又能做出层次
	private static inline var TITLE_SIZE:Int = 32;
	private static inline var BODY_SIZE:Int = 16;

	public static function isShowing():Bool
	{
		return _instance != null && _instance.visible;
	}

	/** 显示（或更新）错误层。重复调用只刷新内容，不会叠加多个层。 */
	public static function show(message:String, stack:String, ?count:Int = 1):Void
	{
		var stage = Lib.current.stage;
		if (stage == null) return;

		if (_instance == null)
		{
			_instance = new CrashOverlay();
			stage.addChild(_instance);
		}

		// 同一错误重复上报且已显示：只刷新计数文本，跳过 setChildIndex 与整个 layout()。
		// layout() 会重设 3 个 htmlText、重绘全部 graphics、读取 textHeight，若异常每帧
		// 复抛，逐帧执行会拖死主线程（表现为游戏「未响应」）。
		var sig = (message != null ? message : "") + "\u0001" + (stack != null ? stack : "");
		if (_instance.visible && _instance._lastContent == sig)
		{
			_instance.setCountOnly(count);
			return;
		}

		_instance.setText(message, stack, count);
		_instance.visible = true;
		// 置顶，确保不被游戏内其它 OpenFL 层盖住
		if (stage.getChildIndex(_instance) != stage.numChildren - 1)
			stage.setChildIndex(_instance, stage.numChildren - 1);
		_instance.layout();
	}

	private function setCountOnly(count:Int):Void
	{
		// 必须写回 _countTF；只调用 countText() 会丢掉结果，重复报错时次数永远不刷新
		setHtml(_countTF, countText(count), 0xFFB454, false);
	}

	private function countText(count:Int):String
	{
		return count > 1
			? tr('crash_overlay_count_repeat', '同类情况累计 {0} 次', [count])
			: tr('crash_overlay_count_saved', '已记入 logs 文件夹');
	}

	public static function hide():Void
	{
		if (_instance != null)
		{
			_instance.visible = false;
			_instance._lastContent = ""; // 下次显示（即使同错误）重新排版并回到顶部
		}
		// 先通知外部进入静默期，避免切状态时的连锁异常立刻把弹层重新拉起来
		if (onDismiss != null) { try { onDismiss(); } catch (e:Dynamic) {} }
	}

	// ------------------------------------------------------------------
	// 实例成员
	// ------------------------------------------------------------------
	private var fontName:String;

	private var _dim:Sprite;             // 全屏遮罩（必须可交互，否则点击空白会穿透到游戏）
	private var _panel:Sprite;           // 圆角面板
	private var _panelBg:Sprite;
	private var _titleTF:TextField;
	private var _hintTF:TextField;
	private var _countTF:TextField;

	private var _contentMask:Shape;
	private var _contentHit:Sprite;      // 内容命中区（滚轮/触摸）
	private var _text:TextField;         // 错误详情 + 堆栈
	private var _vTrack:Shape;
	private var _vThumb:Sprite;

	private var _btnContinue:Sprite;
	private var _btnTitle:Sprite;
	private var _btnRestart:Sprite;
	private var _hover:Map<Sprite, Bool> = new Map();

	private var _lastContent:String = "";   // 内容缓存：同错误重复上报时只刷新次数，不重建文本/重置滚动
	private var _btnW:Float = 0;             // 按钮尺寸（独立于文本尺寸，避免 autoSize 把背景画成一小条）
	private var _btnH:Float = 0;
	private var _scrollY:Float = 0;
	private var _maxScrollY:Float = 0;
	private var _vpW:Float = 0;
	private var _vpH:Float = 0;
	private var _contentX:Float = 0;
	private var _contentY:Float = 0;

	private var _touchActive:Bool = false;
	private var _touchID:Int = -1;
	private var _touchLastY:Float = 0;
	private var _dragThumb:Bool = false;
	private var _dragGrabY:Float = 0;

	private function new()
	{
		super();
		fontName = Paths.font('unifont-18.0.01.otf');

		// 全屏遮罩：拦截所有输入，避免穿透
		// 必须是 Sprite（Shape 不是 InteractiveObject，收不到事件，点击空白会漏到游戏）
		_dim = new Sprite();
		_dim.mouseEnabled = true;
		_dim.mouseChildren = false;
		addBlock(_dim);
		addChild(_dim);

		_panel = new Sprite();
		_panel.mouseEnabled = true;
		_panel.mouseChildren = true;
		addChild(_panel);

		_panelBg = new Sprite();
		_panelBg.mouseEnabled = true;
		_panelBg.mouseChildren = false;
		_panel.addChild(_panelBg);

		_titleTF = makeText(TITLE_SIZE, 0xFF6B6B, true);
		_hintTF = makeText(BODY_SIZE, 0xB9B9C4, false);
		_countTF = makeText(BODY_SIZE, 0xFFB454, false);
		// 标题区文本固定尺寸 + 自动换行，避免长文案在窄屏溢出面板
		for (t in [_titleTF, _hintTF, _countTF])
		{
			t.autoSize = TextFieldAutoSize.NONE;
			t.wordWrap = true;
			t.multiline = true;
		}
		_panel.addChild(_titleTF);
		_panel.addChild(_hintTF);
		_panel.addChild(_countTF);

		_contentMask = new Shape();
		_panel.addChild(_contentMask);

		_text = new TextField();
		_text.selectable = false;
		_text.mouseEnabled = false;
		_text.wordWrap = true;
		_text.multiline = true;
		_text.autoSize = TextFieldAutoSize.NONE;
		_text.antiAliasType = AntiAliasType.ADVANCED;
		_text.gridFitType = GridFitType.PIXEL;
		_text.defaultTextFormat = new openfl.text.TextFormat(fontName, BODY_SIZE, 0xE6E6EA);
		_panel.addChild(_text);
		_text.mask = _contentMask;

		// 内容命中区：接收滚轮与触摸，且拦截冒泡
		_contentHit = new Sprite();
		_contentHit.mouseEnabled = true;
		_contentHit.mouseChildren = false;
		_contentHit.addEventListener(MouseEvent.MOUSE_WHEEL, onWheel);
		_contentHit.addEventListener(MouseEvent.MOUSE_DOWN, blockMouse);
		_contentHit.addEventListener(TouchEvent.TOUCH_BEGIN, onContentTouchBegin);
		_contentHit.addEventListener(TouchEvent.TOUCH_MOVE, onContentTouchMove);
		_contentHit.addEventListener(TouchEvent.TOUCH_END, onContentTouchEnd);
		_panel.addChild(_contentHit);

		_vTrack = new Shape();
		_panel.addChild(_vTrack);
		_vThumb = new Sprite();
		_vThumb.mouseEnabled = true;
		_vThumb.mouseChildren = false;
		_vThumb.addEventListener(MouseEvent.MOUSE_DOWN, onThumbDown);
		addBlock(_vThumb);
		_panel.addChild(_vThumb);

		_btnContinue = makeButton(btnActionContinue);
		_btnTitle = makeButton(btnActionTitle);
		_btnRestart = makeButton(btnActionRestart);
		_panel.addChild(_btnContinue);
		_panel.addChild(_btnTitle);
		_panel.addChild(_btnRestart);

		// 顶层统一拦截：所有输入（含移动/滚轮）都不冒泡到 stage 上的 flixel 监听。
		// 拖拽滚动条的逻辑也放在这里处理，避免依赖 stage 监听导致无法拦截 MOUSE_MOVE。
		addEventListener(MouseEvent.MOUSE_DOWN, blockMouse);
		addEventListener(MouseEvent.MOUSE_UP, onRootMouseUp);
		addEventListener(MouseEvent.MOUSE_MOVE, onRootMouseMove);
		addEventListener(MouseEvent.MOUSE_WHEEL, blockMouse);
		// 不拦截 MOUSE_OVER / MOUSE_OUT：OpenFL 内部靠它们维护 hover 状态，
		// 全局 stopImmediatePropagation 可能干扰输入状态机；按钮自身已处理 hover。
		addEventListener(TouchEvent.TOUCH_BEGIN, blockTouch);
		addEventListener(TouchEvent.TOUCH_MOVE, onRootTouchMove);
		addEventListener(TouchEvent.TOUCH_END, onRootTouchEnd);

		addEventListener(Event.ADDED_TO_STAGE, onAdded);
		visible = false;
	}

	private function onAdded(e:Event):Void
	{
		removeEventListener(Event.ADDED_TO_STAGE, onAdded);
		var stage = Lib.current.stage;
		if (stage == null) return;
		stage.addEventListener(Event.RESIZE, function(_:Event) { if (visible) layout(); });
	}

	private function onRootMouseMove(e:MouseEvent):Void
	{
		e.stopPropagation(); e.stopImmediatePropagation();
		if (_dragThumb) updateThumbDrag(e.stageY);
	}

	private function onRootMouseUp(e:MouseEvent):Void
	{
		e.stopPropagation(); e.stopImmediatePropagation();
		_dragThumb = false;
	}

	private function onRootTouchMove(e:TouchEvent):Void
	{
		e.stopPropagation(); e.stopImmediatePropagation();
		// 内容区自身的 TOUCH_MOVE 已在 target 阶段处理滚动，这里只补滚动条拖拽
		if (_dragThumb) updateThumbDrag(e.stageY);
	}

	private function onRootTouchEnd(e:TouchEvent):Void
	{
		e.stopPropagation(); e.stopImmediatePropagation();
		_dragThumb = false;
		if (e.touchPointID == _touchID) { _touchActive = false; _touchID = -1; }
	}

	// ------------------------------------------------------------------
	// 文本与按钮
	// ------------------------------------------------------------------
	private function makeText(size:Int, color:Int, bold:Bool):TextField
	{
		var tf = new TextField();
		tf.selectable = false;
		tf.mouseEnabled = false;
		tf.autoSize = TextFieldAutoSize.LEFT;
		tf.multiline = false;
		tf.wordWrap = false;
		tf.antiAliasType = AntiAliasType.ADVANCED;
		tf.gridFitType = GridFitType.PIXEL;
		tf.defaultTextFormat = new openfl.text.TextFormat(fontName, size, color, bold);
		return tf;
	}

	private function setHtml(tf:TextField, str:String, color:Int, bold:Bool, size:Int = BODY_SIZE):Void
	{
		// 翻译文案可能含 & / <，先转义再拼进 htmlText
		var safe = escapeHtml(str);
		var b = bold ? "<b>" + safe + "</b>" : safe;
		tf.htmlText = '<font face="' + fontName + '" size="' + size + '" color="#' + StringTools.hex(color, 6) + '">' + b + '</font>';
	}

	private function makeButton(action:()->Void):Sprite
	{
		var s = new Sprite();
		s.mouseEnabled = true;
		s.mouseChildren = false;
		// 关键：按钮文本必须用 autoSize=NONE，否则 width/height 设不进去，
		// redrawButtons 会读回文本自身尺寸，把按钮背景画成一小条、文字跑到色块外。
		var tf = makeText(BODY_SIZE, 0xE6E6EA, false);
		tf.autoSize = TextFieldAutoSize.NONE;
		tf.multiline = true;
		tf.wordWrap = false;
		tf.mouseEnabled = false;
		s.addChild(tf);
		addBlock(s);
		s.addEventListener(MouseEvent.MOUSE_OVER, function(e:MouseEvent){ _hover.set(s, true); redrawButtons(); });
		s.addEventListener(MouseEvent.MOUSE_OUT, function(e:MouseEvent){ _hover.set(s, false); redrawButtons(); });
		s.addEventListener(TouchEvent.TOUCH_BEGIN, function(e:TouchEvent){ _hover.set(s, true); redrawButtons(); });
		s.addEventListener(TouchEvent.TOUCH_END, function(e:TouchEvent){ _hover.set(s, false); redrawButtons(); });
		s.addEventListener(MouseEvent.CLICK, function(e:MouseEvent){
			e.stopPropagation(); e.stopImmediatePropagation(); action();
		});
		return s;
	}

	private function addBlock(s:Sprite):Void
	{
		s.addEventListener(MouseEvent.MOUSE_DOWN, blockMouse);
		s.addEventListener(TouchEvent.TOUCH_BEGIN, blockTouch);
	}

	private function blockMouse(e:MouseEvent):Void
	{
		e.stopPropagation(); e.stopImmediatePropagation();
	}

	private function blockTouch(e:TouchEvent):Void
	{
		e.stopPropagation(); e.stopImmediatePropagation();
	}

	// ------------------------------------------------------------------
	// 内容
	// ------------------------------------------------------------------
	private function setText(message:String, stack:String, count:Int):Void
	{
		setHtml(_titleTF, tr('crash_overlay_title', '刚刚记录到一个小状况'), 0xFF6B6B, true, TITLE_SIZE);
		setHtml(_hintTF, tr('crash_overlay_hint', '游戏仍在正常运行，这个问题已被拦截并记入日志。为避免它反复出现，更新暂时停了一下。选一个方式继续就好。'), 0xB9B9C4, false);
		setHtml(_countTF, countText(count), 0xFFB454, false);

		// 同一错误重复上报：只更新次数，保留用户当前的滚动位置，避免每帧重建 TextField
		var sig = message + "\u0001" + stack;
		if (sig == _lastContent) return;
		_lastContent = sig;

		var sb = new StringBuf();
		sb.add('<font face="' + fontName + '" size="' + BODY_SIZE + '" color="#FF8080"><b>' + escapeHtml(message) + '</b></font>');
		if (stack != null && stack.length > 0)
		{
			sb.add('<font face="' + fontName + '" size="' + BODY_SIZE + '" color="#9FA0AD">\n\n'
				+ escapeHtml(tr('crash_overlay_tech_details', '—— 技术详情 ——')) + '\n</font>');
			sb.add('<font face="' + fontName + '" size="' + BODY_SIZE + '" color="#D2D2DA">' + escapeHtml(stack) + '</font>');
		}
		_text.htmlText = sb.toString();
		_scrollY = 0;
	}

	private static function escapeHtml(s:String):String
	{
		if (s == null) return "";
		s = StringTools.replace(s, "&", "&amp;");
		s = StringTools.replace(s, "<", "&lt;");
		s = StringTools.replace(s, ">", "&gt;");
		return s;
	}

	/**
	 * 取本地化文案：模组 .lang > 当前语言 JSON > 内置中文兜底。
	 * 崩溃可能发生在 Language.load() 之前、或语言包加载失败（此时 Language.get 会返回裸 key），
	 * 因此整段必须 try/catch，且兜底文案自己也要替换 {0} / {$0} 占位符。
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
	// 布局
	// ------------------------------------------------------------------
	private function layout():Void
	{
		var stage = Lib.current.stage;
		if (stage == null) return;
		var sw = stage.stageWidth;
		var sh = stage.stageHeight;

		var s = uiScale();
		var pw = Math.min(sw * 0.86, 900 * s);
		var ph = Math.min(sh * 0.80, 620 * s);
		if (pw < 320) pw = sw - 20;
		if (ph < 240) ph = sh - 20;
		var px = (sw - pw) * 0.5;
		var py = (sh - ph) * 0.5;

		// 遮罩
		var dg = _dim.graphics; dg.clear();
		dg.beginFill(0x05050A, 0.62);
		dg.drawRect(0, 0, sw, sh);
		dg.endFill();

		_panel.x = px; _panel.y = py;
		var pg = _panelBg.graphics; pg.clear();
		pg.beginFill(0x1A1A22, 0.94);
		pg.lineStyle(1.4 * s, 0x7A4A50, 0.7);
		pg.drawRoundRect(0, 0, pw, ph, 14 * s);
		pg.endFill();

		var pad = 18 * s;
		var tw = pw - pad * 2;
		// 标题 32px / 说明 16px：先按屏宽给基础高度，再按实际渲染高度测量一次。
		// 多语言后文案长度差异很大（英文说明通常明显长于中文），固定行高容易被裁。
		var titleH:Float = (pw < 700 * s) ? 84 * s : 46 * s;
		var hintH:Float = (pw < 560 * s) ? 66 * s : 44 * s;
		_titleTF.width = tw; _titleTF.height = titleH;
		_hintTF.width = tw;  _hintTF.height = hintH;
		var titleMeasured = _titleTF.textHeight + 6 * s;
		if (titleMeasured > titleH) titleH = Math.min(titleMeasured, 100 * s);
		var hintMeasured = _hintTF.textHeight + 6 * s;
		if (hintMeasured > hintH) hintH = Math.min(hintMeasured, 130 * s);
		_titleTF.x = pad; _titleTF.y = pad;                  _titleTF.height = titleH;
		_hintTF.x = pad;  _hintTF.y = pad + titleH + 6 * s; _hintTF.height = hintH;
		_countTF.x = pad; _countTF.y = _hintTF.y + hintH + 4 * s; _countTF.width = tw; _countTF.height = 22 * s;

		// 底部按钮区（加大：保证 16px 文字在按钮内有充足留白、居中显示）
		var btnH = 52 * s;
		var btnY = ph - pad - btnH;
		var gap = 10 * s;
		var bw = Math.min(200 * s, (pw - pad * 2 - gap * 2) / 3);
		var bx = pad;
		bx = placeButton(_btnContinue, bx, btnY, bw, btnH, s); bx += gap;
		bx = placeButton(_btnTitle, bx, btnY, bw, btnH, s); bx += gap;
		placeButton(_btnRestart, bx, btnY, bw, btnH, s);
		redrawButtons();

		// 内容区
		_contentX = pad;
		_contentY = _countTF.y + 26 * s;
		var sbSize = 10 * s;
		_vpW = pw - pad * 2 - sbSize - 6 * s;
		_vpH = btnY - _contentY - 10 * s;
		if (_vpH < 40 * s) _vpH = 40 * s;

		var bg2 = _contentMask.graphics; bg2.clear();
		bg2.beginFill(0xFFFFFF, 1);
		bg2.drawRoundRect(_contentX, _contentY, _vpW, _vpH, 6 * s);
		bg2.endFill();
		_contentMask.visible = true;

		var hg = _contentHit.graphics; hg.clear();
		hg.beginFill(0xFFFFFF, 0.001);
		hg.drawRoundRect(_contentX, _contentY, _vpW, _vpH, 6 * s);
		hg.endFill();

		_text.x = _contentX + 4 * s;
		_text.y = _contentY;
		_text.width = _vpW - 8 * s;

		var trackX = _contentX + _vpW + 4 * s;
		var vg = _vTrack.graphics; vg.clear();
		vg.beginFill(0x2A2A34, 0.9);
		vg.drawRoundRect(trackX, _contentY, sbSize, _vpH, sbSize * 0.5);
		vg.endFill();

		_maxScrollY = Math.max(0, _text.textHeight - _vpH + 12 * s);
		clampScroll();
		updateScrollbar(trackX, sbSize);
	}

	private function uiScale():Float
	{
		var s:Float = 1;
		try
		{
			var w = Lib.application.window;
			if (w != null)
			{
				#if (mobile)
				s = Math.max(1.25, (w.width / 1280));
				#else
				s = Math.max(1, (w.width / 1280));
				#end
			}
		}
		catch (e:Dynamic) {}
		if (s < 1) s = 1;
		if (s > 2.2) s = 2.2;
		return s;
	}

	private function placeButton(b:Sprite, x:Float, y:Float, w:Float, h:Float, s:Float):Float
	{
		b.x = x; b.y = y;
		var tf:TextField = cast b.getChildAt(0);
		tf.width = w; tf.height = h;
		tf.x = 0;
		tf.htmlText = '<p align="center"><font face="' + fontName + '" size="' + BODY_SIZE + '" color="#E6E6EA">' + escapeHtml(buttonLabel(b)) + '</font></p>';
		// autoSize=NONE 后 tf.height 固定为 h，textHeight 是真实文本高度，位移即可垂直居中
		tf.y = (h - tf.textHeight) * 0.5;
		_btnW = w; _btnH = h;
		return x + w;
	}

	private function buttonLabel(b:Sprite):String
	{
		if (b == _btnContinue) return tr('crash_overlay_btn_continue', '继续游戏');
		if (b == _btnTitle) return tr('crash_overlay_btn_title', '回到主菜单');
		return tr('crash_overlay_btn_restart', '重启游戏');
	}

	private function redrawButtons():Void
	{
		var s = uiScale();
		for (b in [_btnContinue, _btnTitle, _btnRestart])
		{
			if (b == null) continue;
			// 用布局时记录的按钮尺寸，而不是 TextField 的尺寸（避免 autoSize 造成背景过小）
			var w = _btnW;
			var h = _btnH;
			var hv = _hover.get(b) == true;
			var g = b.graphics; g.clear();
			var base = (b == _btnRestart) ? 0x5A2A2E : (b == _btnTitle ? 0x2F4A70 : 0x2A2A34);
			var hi   = (b == _btnRestart) ? 0xB03A42 : (b == _btnTitle ? 0x3F6DB0 : 0x3A3A46);
			g.beginFill(hv ? hi : base, hv ? 0.98 : 0.88);
			g.lineStyle(1 * s, hv ? 0xA0A0B0 : 0x55555F, 0.7);
			g.drawRoundRect(0, 0, w, h, 8 * s);
			g.endFill();
		}
	}

	// ------------------------------------------------------------------
	// 滚动
	// ------------------------------------------------------------------
	private function clampScroll():Void
	{
		if (_scrollY < 0) _scrollY = 0;
		if (_scrollY > _maxScrollY) _scrollY = _maxScrollY;
		_text.y = _contentY - _scrollY;
	}

	private function updateScrollbar(trackX:Float, sbSize:Float):Void
	{
		var vg = _vThumb.graphics; vg.clear();
		if (_maxScrollY <= 0) { _vThumb.visible = false; return; }
		_vThumb.visible = true;
		var th = thumbHeight();
		var ty = _contentY + Math.max(1, _vpH - th) * (_scrollY / _maxScrollY);
		vg.beginFill(0x8A8A9A, 0.9);
		vg.drawRoundRect(trackX, ty, sbSize, th, sbSize * 0.5);
		vg.endFill();
		_vThumb.x = 0; _vThumb.y = 0; // 图形已用绝对坐标绘制
	}

	private function onWheel(e:MouseEvent):Void
	{
		e.stopPropagation(); e.stopImmediatePropagation();
		_scrollY -= e.delta * 32;
		clampScroll();
		var s = uiScale();
		updateScrollbar(_contentX + _vpW + 4 * s, 10 * s);
	}

	private function onContentTouchBegin(e:TouchEvent):Void
	{
		e.stopPropagation(); e.stopImmediatePropagation();
		_touchActive = true;
		_touchID = e.touchPointID;
		_touchLastY = e.stageY;
	}

	private function onContentTouchMove(e:TouchEvent):Void
	{
		e.stopPropagation(); e.stopImmediatePropagation();
		if (!_touchActive || e.touchPointID != _touchID) return;
		_scrollY -= (e.stageY - _touchLastY);
		_touchLastY = e.stageY;
		clampScroll();
		var s = uiScale();
		updateScrollbar(_contentX + _vpW + 4 * s, 10 * s);
	}

	private function onContentTouchEnd(e:TouchEvent):Void
	{
		e.stopPropagation(); e.stopImmediatePropagation();
		if (e.touchPointID == _touchID) { _touchActive = false; _touchID = -1; }
	}

	private function thumbHeight():Float
	{
		return Math.max(24, _vpH * (_vpH / Math.max(1, _vpH + _maxScrollY)));
	}

	private function onThumbDown(e:MouseEvent):Void
	{
		e.stopPropagation(); e.stopImmediatePropagation();
		if (_maxScrollY <= 0) return;
		_dragThumb = true;
		var localY = e.stageY - _panel.y;
		var usable = Math.max(1, _vpH - thumbHeight());
		var thumbTop = _contentY + usable * (_scrollY / _maxScrollY);
		_dragGrabY = localY - thumbTop; // 鼠标在滑块内的偏移
	}

	private function updateThumbDrag(stageY:Float):Void
	{
		var s = uiScale();
		var trackX = _contentX + _vpW + 4 * s;
		var localY = stageY - _panel.y;
		var usable = Math.max(1, _vpH - thumbHeight());
		var thumbTop = localY - _dragGrabY;
		_scrollY = ((thumbTop - _contentY) / usable) * _maxScrollY;
		clampScroll();
		updateScrollbar(trackX, 10 * s);
	}

	// ------------------------------------------------------------------
	// 按钮动作（转发到注入的回调；未注入时至少关闭弹层保证可继续）
	// ------------------------------------------------------------------
	private function btnActionContinue():Void
	{
		hide();
		if (onContinue != null) { try { onContinue(); } catch (e:Dynamic) {} }
	}

	private function btnActionTitle():Void
	{
		hide();
		if (onGotoTitle != null) { try { onGotoTitle(); } catch (e:Dynamic) {} }
	}

	private function btnActionRestart():Void
	{
		hide();
		if (onRestartApp != null) { try { onRestartApp(); } catch (e:Dynamic) {} }
	}
}
