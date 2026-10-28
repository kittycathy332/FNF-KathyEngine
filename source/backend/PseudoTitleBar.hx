package backend;

import openfl.display.Bitmap;
import openfl.display.BitmapData;
import openfl.display.DisplayObject;
import openfl.display.PixelSnapping;
import openfl.display.Shape;
import openfl.display.Sprite;
import openfl.events.Event;
import openfl.events.MouseEvent;
import openfl.text.TextField;
import openfl.text.TextFieldAutoSize;
import openfl.text.TextFormat;
import openfl.Lib;
import flixel.FlxG;
import lime.ui.MouseCursor;
import lime.ui.Window;
import lime.system.System as LimeSystem;

/**
 * In-game replacement for the native window title bar.
 *
 * The bar is only active while the main window is borderless. It slides in
 * when the pointer moves upward into the top trigger zone and provides the
 * usual window controls (minimize / maximize / close) plus drag-to-move.
 */
class PseudoTitleBar extends Sprite
{
	public static var instance:PseudoTitleBar = null;

	private static var BAR_HEIGHT:Float = 36;
	private static var BUTTON_WIDTH:Float = 46;
	private static var SHOW_ZONE:Float = 72;
	private static var HIDE_DELAY:Float = 0.9;
	private static var RESIZE_MARGIN:Float = 12;
	private static var RESIZE_CORNER:Float = 24;
	private static var FRAME_WIDTH:Float = 8;
	private static var MIN_WIDTH:Float = 640;
	private static var MIN_HEIGHT:Float = 360;

	private var _window:Window;
	private var _bg:Shape;
	private var _frame:Shape = null;
	private var _frameApplied:Bool = false;
	private var _lastContentX:Float = -9999;
	private var _lastContentY:Float = -9999;
	private var _lastContentW:Float = -9999;
	private var _lastContentH:Float = -9999;
	private var _appliedBorder:Float = -1;
	private var _windowBorderApplied:Float = 0;
	private var _icon:Bitmap = null;
	private var _lastIconHandle:Float = 0;
	private var _iconPollTimer:Float = 0;
	private var _dragArea:Sprite;
	private var _title:TextField;
	private var _titleFormat:TextFormat;
	private var _buttons:Array<Sprite> = [];
	private var _buttonKinds:Array<Int> = [];
	private var _hoverButton:Sprite = null;

	private var _uiScale:Float = 1;
	private var _barHeight:Float = 36;
	private var _buttonWidth:Float = 46;
	private var _showZone:Float = 28;
	private var _titleMaxWidth:Float = 0;

	private var _enabled:Bool = false;
	private var _shown:Bool = false;
	private var _active:Bool = true;
	private var _mouseInside:Bool = true;
	private var _lastMouseY:Float = -1;
	private var _dragging:Bool = false;
	private var _dragGrabX:Float = 0;
	private var _dragGrabY:Float = 0;
	private var _resizing:Bool = false;
	private var _resizeEdges:Int = 0;
	private var _resizeStartX:Int = 0;
	private var _resizeStartY:Int = 0;
	private var _resizeStartW:Int = 0;
	private var _resizeStartH:Int = 0;
	private var _resizeGrabLeft:Float = 0;
	private var _resizeGrabTop:Float = 0;
	private var _resizeHoverEdges:Int = 0;
	private var _resizeForcedCursor:Bool = false;
	private var _resizePrevMouseVisible:Bool = true;
	private var _hideTimer:Float = 0;
	private var _showDwell:Float = 0;
	private var _lastFrame:Float = 0;
	private var _isMaximized:Bool = false;
	private var _hasRestore:Bool = false;
	private var _restoreX:Int = 0;
	private var _restoreY:Int = 0;
	private var _restoreW:Int = 0;
	private var _restoreH:Int = 0;

	private var _lastTitle:String = null;
	private var _lastStageWidth:Int = 0;
	private var _savedMouseVisible:Bool = true;
	private var _hasSavedMouseVisible:Bool = false;

	/** Called by the close button. Main wires this to its own quit routine. */
	public var onExit:Void->Void = null;

	/** Called when the frame inset/visibility changes (used to re-layout the FPS layer). */
	public var onFrameChanged:Void->Void = null;

	/** Keeps the frame above a display object (for example the FPS layer). */
	public function bringFrameAbove(obj:DisplayObject):Void
	{
		if (_frame == null || stage == null || obj == null || obj.parent != stage) return;

		var objIndex = stage.getChildIndex(obj);
		if (stage.getChildIndex(_frame) < objIndex)
			stage.setChildIndex(_frame, objIndex);
	}

	public function new()
	{
		super();

		instance = this;
		_window = Lib.application.window;

		mouseEnabled = false;
		mouseChildren = false;
		visible = false;
		y = -BAR_HEIGHT;

		_bg = new Shape();
		addChild(_bg);

		_icon = createWindowIcon();
		if (_icon != null) addChild(_icon);
		_lastIconHandle = Native.getWindowIconHandle();

		_dragArea = new Sprite();
		_dragArea.mouseEnabled = true;
		_dragArea.mouseChildren = false;
		_dragArea.addEventListener(MouseEvent.MOUSE_DOWN, onDragStart);
		_dragArea.addEventListener(MouseEvent.MOUSE_UP, onBarMouseUp);
		addChild(_dragArea);

		_title = new TextField();
		_title.selectable = false;
		_title.mouseEnabled = false;
		_title.autoSize = TextFieldAutoSize.LEFT;
		_title.multiline = false;
		_title.wordWrap = false;
		var titleFormat = new TextFormat("_sans", 13, 0xF1F1F5, true);
		titleFormat.letterSpacing = 0.2;
		_titleFormat = titleFormat;
		_title.defaultTextFormat = _titleFormat;
		addChild(_title);

		for (i in 0...3)
		{
			var button = makeButton(i);
			_buttons.push(button);
			_buttonKinds.push(i);
			addChild(button);
		}

		addEventListener(Event.ADDED_TO_STAGE, onAddedToStage);
		addEventListener(Event.ENTER_FRAME, onFrame);

		if (_window != null)
		{
			_window.onResize.add(onWindowResize);
			_window.onMove.add(onWindowMove);
			_window.onMouseUp.add(onWindowMouseUp);
			_window.onFullscreen.add(onFullscreen);
			_window.onActivate.add(onActivate);
			_window.onDeactivate.add(onDeactivate);
			_window.onMaximize.add(onMaximize);
			_window.onRestore.add(onRestore);
			_window.onMinimize.add(onMinimize);
			_isMaximized = _window.maximized;
		}

		layout();
	}

	// ---------------------------------------------------------------------
	// Public API
	// ---------------------------------------------------------------------

	/** Re-applies ClientPrefs.borderless to the real window and this overlay. */
	public function syncSettings():Void
	{
		if (_window == null) _window = Lib.application.window;
		if (_window == null) return;

		_enabled = (ClientPrefs.data != null && ClientPrefs.data.borderless);

		stopResize();

		if (isFullscreen())
		{
			_showDwell = 0;
			if (_enabled) layout();
			else hideImmediate();
			return;
		}

		if (_isMaximized) restoreMaximized();
		if (_window.maximized) _window.maximized = false;
		_isMaximized = false;
		_hasRestore = false;

		if (_enabled)
		{
			if (!_window.borderless) _window.borderless = true;
			layout();
		}
		else
		{
			if (_window.borderless) _window.borderless = false;
			hideImmediate();
		}
	}

	public static function applySettings():Void
	{
		if (instance != null) instance.syncSettings();
	}

	/**
	 * Applies the saved borderless flag before the FlxGame is created, so the
	 * window does not visibly flash its native title bar during startup.
	 */
	public static function applyStartupBorderless(enabled:Bool):Void
	{
		if (!enabled) return;

		var window = Lib.application.window;
		if (window == null || window.fullscreen) return;

		if (!window.borderless) window.borderless = true;
		centerWindow(window);
	}

	// ---------------------------------------------------------------------
	// Event wiring
	// ---------------------------------------------------------------------

	private function onAddedToStage(event:Event):Void
	{
		removeEventListener(Event.ADDED_TO_STAGE, onAddedToStage);
		if (stage == null) return;

		stage.addEventListener(MouseEvent.MOUSE_MOVE, onStageMouseMove, true);
		stage.addEventListener(MouseEvent.MOUSE_DOWN, onStageMouseDown, true);
		stage.addEventListener(MouseEvent.MOUSE_UP, onStageMouseUp, true);
		stage.addEventListener(Event.MOUSE_LEAVE, onMouseLeave, false, 0, true);

		if (_frame == null) _frame = new Shape();
		if (_frame.parent != stage)
		{
			// Above the game and the FPS/log layers, but below the title bar.
			var index = stage.getChildIndex(this);
			if (index > stage.numChildren) index = stage.numChildren;
			stage.addChildAt(_frame, index);
		}

		layout();
	}

	private function onFrame(event:Event):Void
	{
		if (_window == null) _window = Lib.application.window;
		if (_window == null || stage == null) return;

		var now = haxe.Timer.stamp();
		var dt = _lastFrame > 0 ? Math.min(0.1, now - _lastFrame) : 0.016;
		_lastFrame = now;

		_iconPollTimer += dt;
		if (_iconPollTimer >= 0.5)
		{
			_iconPollTimer = 0;
			syncWindowIcon();
		}

		if (_shown && parent == stage && stage.numChildren > 0)
		{
			var topIndex = stage.numChildren - 1;
			if (stage.getChildIndex(this) != topIndex) stage.setChildIndex(this, topIndex);
		}

		// Some states hide the system cursor every frame; keep it visible while
		// the user is interacting with the title bar.
		if (_shown && FlxG.mouse != null) FlxG.mouse.visible = true;

		// Re-apply the window style if something (fullscreen toggle, external
		// window manager) reset it while the setting is still enabled.
		if (_enabled && !isFullscreen() && !_window.borderless)
		{
			if (_window.maximized) _window.maximized = false;
			_window.borderless = true;
		}

		// Keep the game root inset even if Flixel/OpenFL applied a resize after
		// our layout pass.
		applyGameFrame();

		// Scale modes can change (PlayState adaptive width / chart editor follow
		// window) without changing the stage size. Re-draw the frame whenever the
		// actual game content rectangle changes, otherwise the frame may still
		// use the old, larger gameplay rect and cover the game.
		if (_frame != null && _enabled && !isFullscreen())
		{
			var content = getGameContentRect();
			if (Math.abs(content.x - _lastContentX) > 0.5
				|| Math.abs(content.y - _lastContentY) > 0.5
				|| Math.abs(content.width - _lastContentW) > 0.5
				|| Math.abs(content.height - _lastContentH) > 0.5)
			{
				drawFrame();
			}
		}

		if (_frame != null) _frame.visible = _enabled && !isFullscreen() && _frameApplied;

		if (!_enabled)
		{
			_showDwell = 0;
			clearResizeCursor();
			if (_shown) hide();
		}
		else if (!_shown)
		{
			// Dwell fallback: if the bar is hidden while the pointer is already
			// at the top (after maximize/fullscreen), show it after a short
			// moment instead of requiring a perfect upward gesture.
			if (!_resizing && _mouseInside && stage.mouseY >= 0 && stage.mouseY <= _showZone)
			{
				_showDwell += dt;
				if (_showDwell >= 0.12) show();
			}
			else
			{
				_showDwell = 0;
			}
		}
		else
		{
			var overBar = _mouseInside && stage.mouseY >= -2 && stage.mouseY <= y + _showZone + 8 * _uiScale;
			if (_dragging)
			{
				_hideTimer = 0;
			}
			else if (!overBar)
			{
				_hideTimer += dt;
				if (_hideTimer >= HIDE_DELAY) hide();
			}
			else
			{
				_hideTimer = 0;
			}
		}

		if (_resizing) updateResize();
		else if (_dragging) updateDrag();

		updateResizeCursor();

		var targetY = _shown ? 0 : -_barHeight;
		if (Math.abs(y - targetY) < 0.5) y = targetY;
		else y += (targetY - y) * Math.min(1, dt * 24);

		var targetAlpha = _shown ? 1.0 : 0.0;
		if (Math.abs(alpha - targetAlpha) < 0.01) alpha = targetAlpha;
		else alpha += (targetAlpha - alpha) * Math.min(1, dt * 24);

		if (!_shown && y <= -_barHeight + 0.5)
		{
			y = -_barHeight;
			alpha = 0;
			visible = false;
			mouseChildren = false;
		}

		updateTitle();
		updateLayoutIfNeeded();
	}

	private function onStageMouseMove(event:MouseEvent):Void
	{
		var wasInside = _mouseInside;
		_mouseInside = true;

		var mouseY = event.stageY;

		// The first move after entering the window is only used as a baseline.
		if (!wasInside)
		{
			_lastMouseY = mouseY;
			return;
		}

		var movedUp = _lastMouseY >= 0 && mouseY < _lastMouseY - 1.0;

		if (_enabled && !_shown && !_resizing
			&& mouseY >= 0 && mouseY <= _showZone
			&& (movedUp || mouseY <= _barHeight + 8 * _uiScale))
		{
			show();
		}

		_lastMouseY = mouseY;
	}

	private function onMouseLeave(event:Event):Void
	{
		_mouseInside = false;
		_lastMouseY = -1;
		_showDwell = 0;
		if (_shown) _hideTimer = 0;
		if (!_resizing) clearResizeCursor();
		// Do not hide immediately. Leaving the window for a moment (especially
		// when the cursor clips the top edge) used to make the bar vanish; let
		// onFrame's hide delay handle it and allow the pointer to come back.
	}

	private function onStageMouseDown(event:MouseEvent):Void
	{
		if (!_enabled || _window == null || _resizing || stage == null) return;
		if (_window.fullscreen || _isMaximized || _window.maximized) return;
		if (_shown && stage.mouseY <= _barHeight + 4) return;

		var edges = getResizeEdges(stage.mouseX, stage.mouseY);
		if (edges == 0) return;

		event.stopPropagation();
		event.stopImmediatePropagation();
		startResize(edges);
	}

	private function getResizeEdges(x:Float, y:Float):Int
	{
		if (stage == null || _window == null || _window.fullscreen) return 0;

		var margin = RESIZE_MARGIN * _uiScale;

		// The top edge belongs to the pseudo title bar. Resize from the
		// left/right/bottom edges and the two bottom corners.
		if (y <= margin) return 0;

		var corner = RESIZE_CORNER * _uiScale;
		if (y >= stage.stageHeight - corner)
		{
			if (x >= stage.stageWidth - corner) return 2 | 8;
			if (x <= corner) return 1 | 8;
		}

		var edges = 0;
		if (x <= margin) edges |= 1;
		else if (x >= stage.stageWidth - margin) edges |= 2;
		if (y >= stage.stageHeight - margin) edges |= 8;
		return edges;
	}

	private function startResize(edges:Int):Void
	{
		_resizing = true;
		_resizeEdges = edges;
		_resizeStartX = _window.x;
		_resizeStartY = _window.y;
		_resizeStartW = _window.width;
		_resizeStartH = _window.height;

		var gx:Float = 0;
		var gy:Float = 0;

		#if (cpp && windows)
		Native.setMouseCapture(true);
		var screenScale = _window.scale;
		if (screenScale <= 0) screenScale = 1;
		gx = Native.getCursorScreenX() / screenScale;
		gy = Native.getCursorScreenY() / screenScale;
		#else
		var sx = (stage.stageWidth > 0 && _window.width > 0) ? _window.width / stage.stageWidth : 1;
		var sy = (stage.stageHeight > 0 && _window.height > 0) ? _window.height / stage.stageHeight : 1;
		gx = _window.x + stage.mouseX * sx;
		gy = _window.y + stage.mouseY * sy;
		#end

		_resizeGrabLeft = gx - _window.x;
		_resizeGrabTop = gy - _window.y;
		_dragging = false;
		_hideTimer = 0;
	}

	private function updateResize():Void
	{
		if (_window == null || stage == null) return;

		var gx:Float = 0;
		var gy:Float = 0;

		#if (cpp && windows)
		var screenScale = _window.scale;
		if (screenScale <= 0) screenScale = 1;
		gx = Native.getCursorScreenX() / screenScale;
		gy = Native.getCursorScreenY() / screenScale;
		#else
		var sx = (stage.stageWidth > 0 && _window.width > 0) ? _window.width / stage.stageWidth : 1;
		var sy = (stage.stageHeight > 0 && _window.height > 0) ? _window.height / stage.stageHeight : 1;
		gx = _window.x + stage.mouseX * sx;
		gy = _window.y + stage.mouseY * sy;
		#end

		var newX = _resizeStartX;
		var newY = _resizeStartY;
		var newW = _resizeStartW;
		var newH = _resizeStartH;
		var minW = Math.round(MIN_WIDTH * _uiScale);
		var minH = Math.round(MIN_HEIGHT * _uiScale);
		var right = _resizeStartX + _resizeStartW;

		if ((_resizeEdges & 1) != 0)
		{
			newX = Math.round(gx - _resizeGrabLeft);
			newW = right - newX;
			if (newW < minW)
			{
				newW = minW;
				newX = right - minW;
			}
		}
		else if ((_resizeEdges & 2) != 0)
		{
			newW = Math.round(gx - _resizeStartX);
			if (newW < minW) newW = minW;
		}

		if ((_resizeEdges & 8) != 0)
		{
			newH = Math.round(gy - _resizeStartY);
			if (newH < minH) newH = minH;
		}

		if (newX != _window.x || newY != _window.y) _window.move(newX, newY);
		if (newW != _window.width || newH != _window.height) _window.resize(newW, newH);
	}

	private function updateResizeCursor():Void
	{
		if (_window == null || stage == null) return;

		if (!_enabled || _window.fullscreen || _isMaximized || _window.maximized
			|| (_shown && stage.mouseY <= _barHeight + 4))
		{
			clearResizeCursor();
			return;
		}

		var edges = _resizing ? _resizeEdges : getResizeEdges(stage.mouseX, stage.mouseY);

		if (edges != 0 && FlxG.mouse != null)
		{
			if (!_resizeForcedCursor)
			{
				_resizePrevMouseVisible = FlxG.mouse.visible;
				_resizeForcedCursor = true;
			}
			FlxG.mouse.visible = true;
		}

		if (edges == _resizeHoverEdges) return;
		_resizeHoverEdges = edges;

		if (edges == 0)
		{
			clearResizeCursor();
			return;
		}

		var left = (edges & 1) != 0;
		var rightEdge = (edges & 2) != 0;
		var bottom = (edges & 8) != 0;

		var cursor:MouseCursor = null;
		if (left && bottom) cursor = MouseCursor.RESIZE_NESW;
		else if (rightEdge && bottom) cursor = MouseCursor.RESIZE_NWSE;
		else if (left || rightEdge) cursor = MouseCursor.RESIZE_WE;
		else if (bottom) cursor = MouseCursor.RESIZE_NS;

		_window.cursor = cursor;
	}

	private function clearResizeCursor():Void
	{
		if (_resizeForcedCursor && FlxG.mouse != null)
		{
			FlxG.mouse.visible = _resizePrevMouseVisible;
			_resizeForcedCursor = false;
		}

		if (_resizeHoverEdges != 0)
		{
			_resizeHoverEdges = 0;
			if (_window != null) _window.cursor = null;
		}
	}

	private function stopResize():Void
	{
		if (_resizing) Native.setMouseCapture(false);

		_resizing = false;
		_resizeEdges = 0;
		clearResizeCursor();
	}

	private function onStageMouseUp(event:MouseEvent):Void
	{
		var wasResizing = _resizing;
		var wasDragging = _dragging;
		stopResize();
		_dragging = false;
		if (wasResizing || wasDragging) event.stopPropagation();
		clearResizeCursor();
	}

	private function onWindowResize(_width:Int, _height:Int):Void
	{
		layout();
	}

	private function onWindowMove(_x:Float, _y:Float):Void
	{
		if (Math.abs(computeUIScale() - _uiScale) > 0.01) layout();
	}

	private function onWindowMouseUp(_x:Float, _y:Float, _button:Int):Void
	{
		if (_resizing) stopResize();
	}

	private function onFullscreen():Void
	{
		if (_window == null) return;
		_lastMouseY = -1;
		_mouseInside = true;
		_showDwell = 0;
		stopResize();

		if (_window.fullscreen)
		{
			_isMaximized = false;
			_hasRestore = false;
			_showDwell = 0;
			layout();
		}
		else
		{
			#if (cpp && windows)
			Native.resetWindowHandle();
			#end
			// Fullscreen style changes finish a few milliseconds after the event.
			haxe.Timer.delay(function()
			{
				if (_window != null && !_window.fullscreen) syncSettings();
			}, 60);
		}
	}

	private function onActivate():Void
	{
		_active = true;
	}

	private function onDeactivate():Void
	{
		_active = false;
		stopResize();
		hideImmediate();
	}

	private function onMaximize():Void
	{
		_isMaximized = true;
		_mouseInside = true;
		redrawButtons();
	}

	private function onRestore():Void
	{
		// A custom (work-area) maximize does not use the OS maximized flag.
		if (!_hasRestore) _isMaximized = false;
		_mouseInside = true;
		redrawButtons();
	}

	private function onMinimize():Void
	{
		stopResize();
		hideImmediate();
	}

	// ---------------------------------------------------------------------
	// Show / hide
	// ---------------------------------------------------------------------

	private function show():Void
	{
		if (_shown) return;

		_shown = true;
		visible = true;
		mouseChildren = true;
		_hideTimer = 0;
		_showDwell = 0;
		if (alpha < 0.15) alpha = 0.15;
		_lastMouseY = stage != null ? stage.mouseY : -1;

		if (FlxG.mouse != null)
		{
			_savedMouseVisible = FlxG.mouse.visible;
			_hasSavedMouseVisible = true;
			FlxG.mouse.visible = true;
		}

		layout();
	}

	private function hide():Void
	{
		if (!_shown) return;

		_shown = false;
		mouseChildren = false;
		_hideTimer = 0;
		_showDwell = 0;
		restoreMouseVisible();
	}

	private function hideImmediate():Void
	{
		_shown = false;
		visible = false;
		mouseChildren = false;
		y = -_barHeight;
		alpha = 0;
		_hideTimer = 0;
		_showDwell = 0;
		_dragging = false;
		stopResize();
		_lastMouseY = -1;
		restoreMouseVisible();
	}

	private function restoreMouseVisible():Void
	{
		if (_hasSavedMouseVisible && FlxG.mouse != null)
		{
			FlxG.mouse.visible = _savedMouseVisible;
		}
		_hasSavedMouseVisible = false;
	}

	// ---------------------------------------------------------------------
	// Window controls / drag
	// ---------------------------------------------------------------------

	private function onDragStart(event:MouseEvent):Void
	{
		if (!_enabled || _window == null) return;

		event.stopPropagation();
		event.stopImmediatePropagation();

		// Dragging a fullscreen window is not meaningful; leave fullscreen
		// first, then the next drag works normally.
		if (_window.fullscreen)
		{
			_window.fullscreen = false;
			return;
		}

		// Dragging a maximized window restores it first, like a native title bar.
		if (_isMaximized) restoreMaximized();
		if (_window.maximized)
		{
			_window.maximized = false;
			_isMaximized = false;
		}

		// On Windows this starts the native non-client drag loop. It blocks
		// until the user releases the mouse, which gives smooth native motion.
		if (Native.startWindowDrag())
		{
			_dragging = false;
			_hideTimer = 0;
			return;
		}

		_dragging = true;
		_dragGrabX = stage.mouseX;
		_dragGrabY = stage.mouseY;
		_hideTimer = 0;
	}

	private function onBarMouseUp(event:MouseEvent):Void
	{
		event.stopPropagation();
	}

	private function updateDrag():Void
	{
		if (_window == null || stage == null) return;

		var sx = (stage.stageWidth > 0 && _window.width > 0) ? _window.width / stage.stageWidth : 1;
		var sy = (stage.stageHeight > 0 && _window.height > 0) ? _window.height / stage.stageHeight : 1;

		var nx = _window.x + Math.round((stage.mouseX - _dragGrabX) * sx);
		var ny = _window.y + Math.round((stage.mouseY - _dragGrabY) * sy);

		if (nx != _window.x || ny != _window.y) _window.move(nx, ny);
	}

	private function onButtonClick(kind:Int):Void
	{
		switch (kind)
		{
			case 0:
				minimizeWindow();
			case 1:
				toggleMaximize();
			case 2:
				closeWindow();
		}
	}

	private function minimizeWindow():Void
	{
		if (_window == null) return;

		if (_window.fullscreen)
		{
			_window.fullscreen = false;
			haxe.Timer.delay(function()
			{
				if (_window != null) _window.minimized = true;
			}, 100);
		}
		else
		{
			_window.minimized = true;
		}

		hideImmediate();
	}

	private function toggleMaximize():Void
	{
		if (_window == null) return;

		if (_window.fullscreen)
		{
			_window.fullscreen = false;
			haxe.Timer.delay(function()
			{
				if (_window != null && !_window.fullscreen)
				{
					syncSettings();
					maximizeWindow();
				}
			}, 100);
			return;
		}

		if (_isMaximized) restoreMaximized();
		else maximizeWindow();
	}

	private function maximizeWindow():Void
	{
		if (_window == null) return;

		_mouseInside = true;
		if (_window.maximized) _window.maximized = false;

		_restoreX = _window.x;
		_restoreY = _window.y;
		_restoreW = _window.width;
		_restoreH = _window.height;
		_hasRestore = true;
		_isMaximized = true;

		#if (cpp && windows)
		var wx = Native.getWorkAreaX();
		var wy = Native.getWorkAreaY();
		var ww = Native.getWorkAreaWidth();
		var wh = Native.getWorkAreaHeight();

		if (ww > 0 && wh > 0)
		{
			// Borderless WS_POPUP windows maximize over the taskbar when using
			// SDL/Win32's default maximize. Resize to the work area instead.
			// Work-area APIs return physical pixels; window coordinates are
			// logical when the window reports a high-DPI scale.
			var screenScale = _window.scale;
			if (screenScale <= 0) screenScale = 1;

			_window.move(Math.round(wx / screenScale), Math.round(wy / screenScale));
			_window.resize(Math.round(ww / screenScale), Math.round(wh / screenScale));
			redrawButtons();
			return;
		}
		#end

		_hasRestore = false;
		_window.maximized = true;
		redrawButtons();
	}

	private function restoreMaximized():Void
	{
		if (_window == null) return;

		_mouseInside = true;
		if (_hasRestore)
		{
			_window.move(_restoreX, _restoreY);
			_window.resize(_restoreW, _restoreH);
			_hasRestore = false;
		}
		else if (_window.maximized)
		{
			_window.maximized = false;
		}

		_isMaximized = false;
		redrawButtons();
	}

	private function closeWindow():Void
	{
		if (onExit != null) onExit();
		else LimeSystem.exit(0);
	}

	// ---------------------------------------------------------------------
	// Layout / painting
	// ---------------------------------------------------------------------

	private function makeButton(kind:Int):Sprite
	{
		var button = new Sprite();
		button.mouseEnabled = true;
		button.mouseChildren = false;

		button.addEventListener(MouseEvent.MOUSE_OVER, function(event:MouseEvent) {
			_hoverButton = button;
			redrawButtons();
		});
		button.addEventListener(MouseEvent.MOUSE_OUT, function(event:MouseEvent) {
			button.alpha = 1;
			if (_hoverButton == button) _hoverButton = null;
			redrawButtons();
		});
		button.addEventListener(MouseEvent.MOUSE_DOWN, function(event:MouseEvent) {
			button.alpha = 0.72;
			event.stopPropagation();
			event.stopImmediatePropagation();
		});
		button.addEventListener(MouseEvent.MOUSE_UP, function(event:MouseEvent) {
			button.alpha = 1;
			event.stopPropagation();
		});
		button.addEventListener(MouseEvent.CLICK, function(event:MouseEvent) {
			event.stopPropagation();
			event.stopImmediatePropagation();
			onButtonClick(kind);
		});

		return button;
	}

	private function createWindowIcon():Bitmap
	{
		try
		{
			var data = IconLoader.loadGameIcon();
			if (data != null)
			{
				var icon = new Bitmap(data, PixelSnapping.AUTO, true);
				icon.smoothing = true;
				return icon;
			}
		}
		catch (e:Dynamic) {}

		return null;
	}

	/**
	 * Mods often change the native window icon at runtime, e.g.
	 * `Application.current.window.setIcon(...)`. Poll the Win32 icon handle and
	 * mirror the new bitmap into the pseudo title bar.
	 */
	private function syncWindowIcon():Void
	{
		#if (cpp && windows)
		var handle = Native.getWindowIconHandle();
		if (handle == 0) return;

		// First successful read is the baseline (usually the app icon). Do not
		// replace the high-resolution icon.ico image with the small HICON.
		if (_lastIconHandle == 0)
		{
			_lastIconHandle = handle;
			if (_icon != null) return;
		}

		if (handle == _lastIconHandle && _icon != null) return;

		var pixels:Array<Int> = [];
		if (!Native.readWindowIcon(pixels) || pixels.length < 3) return;

		var w = pixels[0];
		var h = pixels[1];
		if (w <= 0 || h <= 0 || pixels.length < 2 + w * h) return;

		var bitmap = new BitmapData(w, h, true, 0);
		var index = 2;
		for (y in 0...h)
		{
			for (x in 0...w)
			{
				bitmap.setPixel32(x, y, pixels[index++]);
			}
		}

		_lastIconHandle = handle;

		if (_icon == null)
		{
			_icon = new Bitmap(bitmap, PixelSnapping.AUTO, true);
			_icon.smoothing = true;
			addChildAt(_icon, 1);
			layout();
		}
		else
		{
			_icon.bitmapData = bitmap;
			_icon.smoothing = true;
			var iconSize = 18 * _uiScale;
			_icon.width = iconSize;
			_icon.height = iconSize;
		}
		#end
	}

	private function layout():Void
	{
		var width:Float = 1280;
		if (stage != null && stage.stageWidth > 0) width = stage.stageWidth;
		else if (_window != null && _window.width > 0) width = _window.width;

		_uiScale = computeUIScale();
		_barHeight = BAR_HEIGHT * _uiScale;
		_buttonWidth = BUTTON_WIDTH * _uiScale;
		_showZone = SHOW_ZONE * _uiScale;

		_titleFormat.size = Math.round(13 * _uiScale);
		_titleFormat.letterSpacing = 0.2 * _uiScale;
		_title.defaultTextFormat = _titleFormat;

		if (width < 240 * _uiScale) width = 240 * _uiScale;

		applyGameFrame();
		drawBackground(width);
		drawFrame();

		var dragWidth = width - _buttonWidth * 3;
		if (dragWidth < 1) dragWidth = 1;

		_dragArea.graphics.clear();
		_dragArea.graphics.beginFill(0xFFFFFF, 0.001);
		_dragArea.graphics.drawRect(0, 0, dragWidth, _barHeight);
		_dragArea.graphics.endFill();

		var buttonsX = width - _buttonWidth * 3;
		for (i in 0..._buttons.length)
		{
			var button = _buttons[i];
			button.x = buttonsX + i * _buttonWidth;
			button.y = 0;
		}

		var iconSize = 18 * _uiScale;
		var titleX = 20 * _uiScale;
		if (_icon != null)
		{
			_icon.width = iconSize;
			_icon.height = iconSize;
			_icon.x = 10 * _uiScale;
			_icon.y = (_barHeight - iconSize) * 0.5;
			_icon.visible = true;
			titleX = 34 * _uiScale;
		}

		_titleMaxWidth = Math.max(0, dragWidth - titleX - 12 * _uiScale);
		_title.x = titleX;
		_title.y = 9 * _uiScale;
		_title.visible = _titleMaxWidth > 20 * _uiScale;

		_lastTitle = null;
		_lastStageWidth = stage != null ? stage.stageWidth : 0;

		redrawButtons();
		updateTitle();

		if (!_shown)
		{
			y = -_barHeight;
			alpha = 0;
		}
	}

	private function drawBackground(width:Float):Void
	{
		var h = _barHeight;
		var s = _uiScale;
		var steps = 12;
		var topColor = 0x202028;
		var bottomColor = 0x101014;

		_bg.graphics.clear();

		// Soft vertical gradient instead of a flat block.
		for (i in 0...steps)
		{
			var t = i / (steps - 1);
			_bg.graphics.beginFill(lerpColor(topColor, bottomColor, t), 0.97);
			_bg.graphics.drawRect(0, h * i / steps, width, h / steps);
			_bg.graphics.endFill();
		}

		// Top highlight.
		_bg.graphics.beginFill(0x3A3A46, 0.55);
		_bg.graphics.drawRect(0, 0, width, Math.max(1, s));
		_bg.graphics.endFill();

		// Small accent mark at the left, used when no app icon is available.
		if (_icon == null)
		{
			_bg.graphics.beginFill(0x4D9BFF, 0.95);
			_bg.graphics.drawRoundRect(10 * s, (h - 16 * s) * 0.5, 3 * s, 16 * s, 1.5 * s);
			_bg.graphics.endFill();
		}

		// Separator before the window buttons.
		var buttonsX = width - _buttonWidth * 3;
		_bg.graphics.beginFill(0x3A3A46, 0.45);
		_bg.graphics.drawRect(buttonsX - s, 9 * s, Math.max(1, s), h - 18 * s);
		_bg.graphics.endFill();

		// Inner shadow at the bottom edge.
		var shadowHeight:Int = Std.int(Math.max(1, Math.round(4 * s)));
		for (i in 0...shadowHeight)
		{
			_bg.graphics.beginFill(0x000000, 0.05 + i * (0.16 / shadowHeight));
			_bg.graphics.drawRect(0, h - shadowHeight + i, width, 1);
			_bg.graphics.endFill();
		}

		_bg.graphics.beginFill(0x30303A, 0.95);
		_bg.graphics.drawRect(0, h - Math.max(1, s), width, Math.max(1, s));
		_bg.graphics.endFill();
	}

	private function syncWindowBorder(border:Float):Void
	{
		if (_window == null) return;
		if (isFullscreen() || _isMaximized || _window.maximized || _window.minimized) return;
		if (Math.abs(border - _windowBorderApplied) < 0.01) return;

		var delta = border - _windowBorderApplied;
		var newWidth = Math.round(_window.width + delta * 2);
		var newHeight = Math.round(_window.height + delta * 2);

		if (newWidth <= 0 || newHeight <= 0) return;

		// Do not push the window past the monitor bounds. If there is no room
		// for a real outer frame, drawFrame() fills the leftover margin with
		// the frame color instead.
		if (delta > 0 && _window.display != null)
		{
			var bounds = _window.display.bounds;
			if (bounds != null && (newWidth > bounds.width || newHeight > bounds.height))
				return;
		}

		// Grow/shrink around the window center, like a real non-client frame.
		_windowBorderApplied = border;
		_window.move(Math.round(_window.x - delta), Math.round(_window.y - delta));
		_window.resize(newWidth, newHeight);
	}

	private function applyGameFrame():Void
	{
		if (stage == null || FlxG.game == null)
		{
			_frameApplied = false;
			return;
		}

		var border = getFrameBorder();
		var oldBorder = _appliedBorder;
		var wasApplied = _frameApplied;

		// A real window frame sits outside the client area. Grow the outer
		// window by 2 * border so the game client area can stay 16:9 without
		// stretching and without black strips.
		syncWindowBorder(border);

		if (border <= 0)
		{
			if (wasApplied)
			{
				FlxG.game.scaleX = 1;
				FlxG.game.scaleY = 1;
				FlxG.resizeGame(stage.stageWidth, stage.stageHeight);
			}

			_frameApplied = false;
		}
		else
		{
			// FlxG.game contains the whole rendered game. Scale and center that
			// display object instead of FlxG.scaleMode, so PlayState/ChartingState
			// can keep switching their own scale modes without fighting us.
			var baseScaleX = FlxG.scaleMode != null ? FlxG.scaleMode.scale.x : 1;
			var baseScaleY = FlxG.scaleMode != null ? FlxG.scaleMode.scale.y : 1;
			var baseWidth = FlxG.width * baseScaleX;
			var baseHeight = FlxG.height * baseScaleY;

			if (baseWidth <= 0) baseWidth = stage.stageWidth;
			if (baseHeight <= 0) baseHeight = stage.stageHeight;

			// Uniform scale: the window itself was grown by the frame size,
			// so the remaining client area can keep the original aspect ratio.
			var factor = Math.min((stage.stageWidth - border * 2) / baseWidth,
								  (stage.stageHeight - border * 2) / baseHeight);

			if (factor <= 0) factor = 0.01;
			else if (factor > 1) factor = 1;

			var contentWidth = baseWidth * factor;
			var contentHeight = baseHeight * factor;

			FlxG.game.scaleX = factor;
			FlxG.game.scaleY = factor;
			FlxG.game.x = (stage.stageWidth - contentWidth) * 0.5;
			FlxG.game.y = (stage.stageHeight - contentHeight) * 0.5;

			_frameApplied = true;
		}

		_appliedBorder = border;

		if (onFrameChanged != null && (oldBorder != border || wasApplied != _frameApplied))
			onFrameChanged();
	}

	public static function getFrameBorder():Float
	{
		if (instance == null) return 0;
		if (!instance._enabled || instance.isFullscreen()) return 0;
		return Math.max(1, Math.round(FRAME_WIDTH * instance._uiScale));
	}

	/**
	 * Rectangle (in stage coordinates) occupied by the actual game viewport,
	 * excluding the pseudo frame margin.
	 */
	public static function getGameContentRect():{x:Float, y:Float, width:Float, height:Float}
	{
		var stage = Lib.current.stage;
		if (stage == null) return {x: 0.0, y: 0.0, width: 0.0, height: 0.0};

		var screenWidth = stage.stageWidth;
		var screenHeight = stage.stageHeight;
		var border = getFrameBorder();

		var baseScaleX = (FlxG.scaleMode != null && FlxG.scaleMode.scale != null) ? FlxG.scaleMode.scale.x : 1;
		var baseScaleY = (FlxG.scaleMode != null && FlxG.scaleMode.scale != null) ? FlxG.scaleMode.scale.y : 1;
		var baseWidth = FlxG.width * baseScaleX;
		var baseHeight = FlxG.height * baseScaleY;

		if (baseWidth <= 0) baseWidth = screenWidth;
		if (baseHeight <= 0) baseHeight = screenHeight;

		if (border > 0)
		{
			var factor = Math.min((screenWidth - border * 2) / baseWidth,
								  (screenHeight - border * 2) / baseHeight);

			if (factor <= 0) factor = 0.01;
			else if (factor > 1) factor = 1;

			var contentWidth = baseWidth * factor;
			var contentHeight = baseHeight * factor;

			return {
				x: (screenWidth - contentWidth) * 0.5,
				y: (screenHeight - contentHeight) * 0.5,
				width: contentWidth,
				height: contentHeight
			};
		}

		return {
			x: FlxG.game != null ? FlxG.game.x : 0,
			y: FlxG.game != null ? FlxG.game.y : 0,
			width: baseWidth,
			height: baseHeight
		};
	}

	private function drawFrame():Void
	{
		if (_frame == null || stage == null) return;

		var w = stage.stageWidth;
		var h = stage.stageHeight;

		_frame.graphics.clear();

		if (_enabled && !isFullscreen() && w > 0 && h > 0)
		{
			var content = getGameContentRect();
			var cx = content.x;
			var cy = content.y;
			var cw = content.width;
			var ch = content.height;

			if (cw > 0 && ch > 0)
			{
				// Fill everything outside the actual game viewport with the
				// frame color. If the window could not grow by the frame size
				// (for example at 150% DPI on a 1080p screen), this also hides
				// the letterbox strips instead of leaving visible side gaps.
				_frame.graphics.beginFill(0x202028, 1);
				_frame.graphics.drawRect(0, 0, w, cy); // top
				_frame.graphics.drawRect(0, cy + ch, w, h - (cy + ch)); // bottom
				_frame.graphics.drawRect(0, cy, cx, ch); // left
				_frame.graphics.drawRect(cx + cw, cy, w - (cx + cw), ch); // right
				_frame.graphics.endFill();

				// Inner shadow just outside the game, never on the game itself.
				_frame.graphics.beginFill(0x08080A, 0.7);
				_frame.graphics.drawRect(cx - 1, cy - 1, cw + 2, 1);
				_frame.graphics.drawRect(cx - 1, cy + ch, cw + 2, 1);
				_frame.graphics.drawRect(cx - 1, cy, 1, ch);
				_frame.graphics.drawRect(cx + cw, cy, 1, ch);
				_frame.graphics.endFill();

				// Outer highlight.
				_frame.graphics.lineStyle(1, 0x4A4A55, 0.9);
				_frame.graphics.drawRoundRect(0.5, 0.5, w - 1, h - 1, 13 * _uiScale);
			}

			_lastContentX = cx;
			_lastContentY = cy;
			_lastContentW = cw;
			_lastContentH = ch;
		}
		else
		{
			_lastContentX = -9999;
			_lastContentY = -9999;
			_lastContentW = -9999;
			_lastContentH = -9999;
		}

		_frame.visible = _enabled && !isFullscreen() && _frameApplied;
	}

	private function updateLayoutIfNeeded():Void
	{
		if (stage == null) return;
		var width = stage.stageWidth;
		if (width > 0 && width != _lastStageWidth) layout();
	}

	private function redrawButtons():Void
	{
		var s = _uiScale;

		for (i in 0..._buttons.length)
		{
			var button = _buttons[i];
			var kind = _buttonKinds[i];
			var hover = (_hoverButton == button);
			var bgColor = hover ? (kind == 2 ? 0xE81123 : 0x2C2C36) : 0xFFFFFF;
			var inset = 3.0 * s;

			button.graphics.clear();
			button.graphics.beginFill(bgColor, hover ? 1 : 0.001);
			button.graphics.drawRoundRect(inset, inset, _buttonWidth - inset * 2, _barHeight - inset * 2, 6 * s);
			button.graphics.endFill();

			var cx = _buttonWidth * 0.5;
			var cy = _barHeight * 0.5;
			var color = (hover && kind == 2) ? 0xFFFFFF : 0xE6E6EA;

			button.graphics.lineStyle(1.3 * s, color, 1);

			switch (kind)
			{
				case 0: // minimize
					button.graphics.moveTo(cx - 5 * s, cy + 4 * s);
					button.graphics.lineTo(cx + 5 * s, cy + 4 * s);
				case 1: // maximize / restore
					if (_isMaximized)
					{
						button.graphics.drawRect(cx - 6 * s, cy - 3 * s, 9 * s, 9 * s);
						button.graphics.moveTo(cx - 3 * s, cy - 6 * s);
						button.graphics.lineTo(cx + 6 * s, cy - 6 * s);
						button.graphics.lineTo(cx + 6 * s, cy + 3 * s);
					}
					else
					{
						button.graphics.drawRect(cx - 5 * s, cy - 5 * s, 10 * s, 10 * s);
					}
				case 2: // close
					button.graphics.moveTo(cx - 4 * s, cy - 4 * s);
					button.graphics.lineTo(cx + 4 * s, cy + 4 * s);
					button.graphics.moveTo(cx + 4 * s, cy - 4 * s);
					button.graphics.lineTo(cx - 4 * s, cy + 4 * s);
			}
		}
	}

	private function updateTitle():Void
	{
		if (_window == null) return;

		var title = _window.title;
		if (title == null || title == "") title = "Kathy Engine";
		if (title == _lastTitle) return;
		_lastTitle = title;

		_title.text = title;

		if (_titleMaxWidth <= 20 * _uiScale)
		{
			_title.visible = false;
			return;
		}

		_title.visible = true;
		var truncated = title;
		var guard = 0;
		while (_title.textWidth > _titleMaxWidth && truncated.length > 1 && guard < 200)
		{
			truncated = truncated.substr(0, truncated.length - 2) + "…";
			_title.text = truncated;
			guard++;
		}

		var textHeight = _title.textHeight;
		if (textHeight <= 0) textHeight = 16;
		_title.y = Math.round((_barHeight - textHeight) * 0.5);
	}

	// ---------------------------------------------------------------------
	// Helpers
	// ---------------------------------------------------------------------

	/**
	 * OpenFL may already scale the stage on high-DPI platforms. In that case
	 * the logical-stage units are already scaled, so only add a DPI factor
	 * when the window reports no scale (common on Windows/Linux).
	 */
	private function computeUIScale():Float
	{
		if (_window == null) return 1;

		#if mac
		return 1;
		#else
		var windowScale = _window.scale;
		if (windowScale > 1.01) return 1;

		var dpi = 96.0;
		var display = _window.display;
		if (display != null && display.dpi > 0) dpi = display.dpi;

		return Math.min(3.0, Math.max(1.0, dpi / 96.0));
		#end
	}

	private static function lerpColor(a:Int, b:Int, t:Float):Int
	{
		var ar = (a >> 16) & 0xFF;
		var ag = (a >> 8) & 0xFF;
		var ab = a & 0xFF;
		var br = (b >> 16) & 0xFF;
		var bg = (b >> 8) & 0xFF;
		var bb = b & 0xFF;

		var r = Std.int(ar + (br - ar) * t);
		var g = Std.int(ag + (bg - ag) * t);
		var bl = Std.int(ab + (bb - ab) * t);
		return (r << 16) | (g << 8) | bl;
	}

	private function isFullscreen():Bool
	{
		// Window.fullscreen mirrors the setter synchronously; Stage.displayState
		// can lag for a frame during an F11 transition.
		return _window != null && _window.fullscreen;
	}

	private static function centerWindow(window:Window):Void
	{
		if (window == null) return;

		var display = window.display;
		if (display == null || display.bounds == null) return;

		var bounds = display.bounds;
		if (bounds.width <= 0 || bounds.height <= 0) return;
		if (window.width <= 0 || window.height <= 0) return;

		window.x = Std.int(bounds.x + (bounds.width - window.width) * 0.5);
		window.y = Std.int(bounds.y + (bounds.height - window.height) * 0.5);
	}
}
