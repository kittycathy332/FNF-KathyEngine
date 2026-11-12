package backend.ui;

import backend.Paths;
import backend.Language;
import flixel.FlxObject;
import flixel.input.keyboard.FlxKey;
import flixel.math.FlxPoint;
import flixel.util.FlxDestroyUtil;
import flash.events.KeyboardEvent;
import lime.math.Rectangle;
import lime.system.Clipboard;

enum abstract AccentCode(Int) from Int from UInt to Int to UInt
{
	var NONE = -1;
	var GRAVE = 0;
	var ACUTE = 1;
	var CIRCUMFLEX = 2;
	var TILDE = 3;
}

enum abstract FilterMode(Int) from Int from UInt to Int to UInt
{
	var NO_FILTER:Int = 0;
	var ONLY_ALPHA:Int = 1;
	var ONLY_NUMERIC:Int = 2;
	var ONLY_ALPHANUMERIC:Int = 3;
	var ONLY_HEXADECIMAL:Int = 4;
	var CUSTOM_FILTER:Int = 5;
}

enum abstract CaseMode(Int) from Int from UInt to Int to UInt
{
	var ALL_CASES:Int = 0;
	var UPPER_CASE:Int = 1;
	var LOWER_CASE:Int = 2;
}

class PsychUIInputText extends FlxSpriteGroup
{
	public static final CHANGE_EVENT = "inputtext_change";

	static final KEY_TILDE = 126;
	static final KEY_ACUTE = 180;

	public static var focusOn(default, set):PsychUIInputText = null;

	/**
	 * 正在销毁的标记。destroy() 里 focusOn = null 会走静态 setter，
	 * 旧实现会回调旧焦点的 unfocus()；下拉框的 unfocus 又反过来
	 * showDropDown(false) -> text = selectedLabel -> set_text() 访问刚被
	 * destroy() 置空的 _boundaries，于是 F5 刷新（switchState -> destroy）
	 * 时抛 Null Object Reference。用这个标记跳过析构期的重入回调，
	 * 同时保留输入法关闭等正常清理。
	 */
	var _destroying:Bool = false;

	public static var defaultFont:String = null;

	public var name:String;
	public var bg:FlxSprite;
	public var behindText:FlxSprite;
	public var selection:FlxSprite;
	public var textObj:FlxText;
	public var caret:FlxSprite;
	public var onChange:String->String->Void;

	public var fieldWidth(default, set):Int = 0;
	public var maxLength(default, set):Int = 0;
	public var passwordMask(default, set):Bool = false;
	public var text(default, set):String = null;
	
	public var forceCase(default, set):CaseMode = ALL_CASES;
	public var filterMode(default, set):FilterMode = NO_FILTER;
	public var customFilterPattern(default, set):EReg;

	public var selectedFormat:FlxTextFormat = new FlxTextFormat(FlxColor.WHITE);

	public function new(x:Float = 0, y:Float = 0, wid:Int = 100, ?text:String = '', size:Int = 10, ?font:String, ?darkStyle:Bool = false)
	{
		super(x, y);
		// 深色样式：内底深色 + 浅色文字；浅色样式：内底白色 + 深色文字
		var behindColor:Int = darkStyle ? 0xFF202024 : 0xFFFFFFFF;
		var textColor:Int = darkStyle ? 0xFFFFFFFF : 0xFF1E1E28;

		this.bg = new FlxSprite().makeGraphic(1, 1, FlxColor.BLACK);
		this.bg.color = 0xFF000000;
		this.bg.alpha = 1;
		this.behindText = new FlxSprite(1, 1).makeGraphic(1, 1, FlxColor.WHITE);
		this.behindText.color = behindColor;
		this.behindText.alpha = 0.7;
		this.selection = new FlxSprite().makeGraphic(1, 1, FlxColor.WHITE);
		this.textObj = new FlxText(1, 1, Math.max(1, wid - 2), '', size);
		this.caret = new FlxSprite().makeGraphic(1, 1, FlxColor.WHITE);
		add(this.bg);
		add(this.behindText);
		add(this.selection);
		add(this.textObj);
		add(this.caret);

		// 浅色背景下改用深色文字，选区保留主题蓝
		this.textObj.color = textColor;
		this.textObj.textField.selectable = false;
		this.textObj.textField.wordWrap = false;
		this.textObj.textField.multiline = false;
		this.selection.color = 0xFF3B82F6;

		// 自动根据字号选择对应字体（未指定时）
		if (font == null || font.length == 0)
			font = (size <= 10) ? Paths.font(Language.get('uitab_font_small')) : Paths.font(Language.get('uitab_font'));
		this.textObj.setFormat(font, size, textColor);

		@:bypassAccessor fieldWidth = wid;
		setGraphicSize(wid + 2, this.textObj.height + 2);
		updateHitbox();
		this.text = text;

		FlxG.stage.addEventListener(KeyboardEvent.KEY_DOWN, onKeyDown);
	}
	
	public var selectIndex:Int = -1;
	public var caretIndex(default, set):Int = -1;
	var _caretTime:Float = 0;

	var _nextAccent:AccentCode = NONE;
	public var inInsertMode:Bool = false;

	// IME / SDL text input 通道 —— 处理中文等需要输入法组合的文本
	var _textInputListening:Bool = false;

	// textInputRect 位置缓存，避免每帧无意义调用
	var _lastTextInputRectX:Float = -1;
	var _lastTextInputRectY:Float = -1;
	function onKeyDown(e:KeyboardEvent)
	{
		if(focusOn != this) return;

		var keyCode:Int = e.keyCode;
		var charCode:Int = e.charCode;
		var flxKey:FlxKey = cast keyCode;

		// 当 SDL onTextInput 通道正在监听时，所有字符输入由它处理，
		// KEY_DOWN 不再调用 _typeLetter，否则同一个按键会触发两次插入。
		// 这是解决"英文直输重复"和"中文IME无法输出"问题的关键。
		var skipTypeLetter:Bool = _textInputListening;

		// Fix missing cedilla
		switch(keyCode)
		{
			case 231: //ç and Ç
				charCode = e.shiftKey ? 0xC7 : 0xE7;
		}

		// Control key actions
		if(e.controlKey)
		{
			switch(flxKey)
			{
				case A: //select all text
					selectIndex = Std.int(Math.min(0, text.length - 1));
					caretIndex = text.length;

				case X, C: //cut/copy selected text to clipboard
					if(caretIndex >= 0 && selectIndex != 0 && caretIndex != selectIndex)
					{
						Clipboard.text = text.substring(caretIndex, selectIndex);
						if(flxKey == X)
							deleteSelection();
					}

				case V: //paste from clipboard
					if(Clipboard.text == null) return;

					if(selectIndex > -1 && selectIndex != caretIndex)
						deleteSelection();

					var lastText = text;
					text = text.substring(0, caretIndex) + Clipboard.text + text.substring(caretIndex);
					caretIndex += Clipboard.text.length;
					if(onChange != null) onChange(lastText, text);
					if(broadcastInputTextEvent) PsychUIEventHandler.event(CHANGE_EVENT, this);

				case BACKSPACE:
					if(selectIndex < 0 || selectIndex == caretIndex)
					{
						var lastText = text;
						var deletedText:String = text.substr(0, Std.int(Math.max(0, caretIndex-1)));
						var space:Int = deletedText.lastIndexOf(' ');
						if(space > -1 && space != caretIndex-1)
						{
							var start:String = deletedText.substring(0, space+1);
							var end:String = text.substring(caretIndex);
							caretIndex -= Std.int(Math.max(0, text.length - (start.length + end.length)));
							text = start + end;
						}
						else
						{
							text = text.substring(caretIndex);
							caretIndex = 0;
						}
						selectIndex = -1;
						if(onChange != null) onChange(lastText, text);
						if(broadcastInputTextEvent) PsychUIEventHandler.event(CHANGE_EVENT, this);
					}
					else deleteSelection();

				case DELETE:
					if(selectIndex < 0 || selectIndex == caretIndex)
					{
						// This is| a test
						// This is test
						var deletedText:String = text.substring(caretIndex);
						var spc:Int = 0;
						var space:Int = deletedText.indexOf(' ');
						while(deletedText.substr(spc, 1) == ' ')
						{
							spc++;
							space = deletedText.substr(spc).indexOf(' ');
						}

						var lastText = text;
						if(space > -1)
						{
							text = text.substr(0, caretIndex) + text.substring(caretIndex + space + spc);
						}
						else text = text.substr(0, caretIndex);
						if(onChange != null) onChange(lastText, text);
						if(broadcastInputTextEvent) PsychUIEventHandler.event(CHANGE_EVENT, this);
					}
					else deleteSelection();

				case LEFT:
					if(caretIndex > 0)
					{
						do
						{
							caretIndex--;
							var a:String = text.substr(caretIndex-1, 1);
							var b:String = text.substr(caretIndex, 1);
							//trace(a, b);
							if(a == ' ' && b != ' ') break;
						}
						while(caretIndex > 0);
					}

				case RIGHT:
					if(caretIndex < text.length)
					{
						do
						{
							caretIndex++;
							var a:String = text.substr(caretIndex-1, 1);
							var b:String = text.substr(caretIndex, 1);
							//trace(a, b);
							if(a != ' ' && b == ' ') break;
						}
						while(caretIndex < text.length);
					}

				default:
			}
			updateCaret();
			return;
		}

		static final ignored:Array<FlxKey> = [SHIFT, CONTROL, ESCAPE];
		if(ignored.contains(flxKey)) return;

		var lastAccent = _nextAccent;
		switch(keyCode)
		{
			case KEY_TILDE:
				_nextAccent = !e.shiftKey ? TILDE : CIRCUMFLEX;
				if(lastAccent == NONE) return;
			case KEY_ACUTE:
				_nextAccent = !e.shiftKey ? ACUTE : GRAVE;
				if(lastAccent == NONE) return;
			default:
				lastAccent = NONE;
		}

		//trace(keyCode, charCode, flxKey);
		switch(flxKey)
		{
			case LEFT: //move caret to left
				if(!FlxG.keys.pressed.SHIFT) selectIndex = -1;
				else if(selectIndex == -1) selectIndex = caretIndex;
				caretIndex = Std.int(Math.max(0, caretIndex - 1));

			case RIGHT: //move caret to right
				if(!FlxG.keys.pressed.SHIFT) selectIndex = -1;
				else if(selectIndex == -1) selectIndex = caretIndex;
				caretIndex = Std.int(Math.min(text.length, caretIndex + 1));

			case HOME: //move caret to the begin
				if(!FlxG.keys.pressed.SHIFT) selectIndex = -1;
				else if(selectIndex == -1) selectIndex = caretIndex;
				caretIndex = 0;

			case END: //move caret to the end
				if(!FlxG.keys.pressed.SHIFT) selectIndex = -1;
				else if(selectIndex == -1) selectIndex = caretIndex;
				caretIndex = text.length;

			case INSERT: //change to insert mode
				inInsertMode = !inInsertMode;

			case BACKSPACE: //Delete letter to the left of caret
				if(caretIndex <= 0) return;

				if(selectIndex > -1 && selectIndex != caretIndex)
					deleteSelection();
				else
				{
					var lastText = text;
					// 先左移光标、再改文本。
					// set_text 末尾会用新文本长度 clamp 光标：如果先改文本再 caretIndex--，
					// 旧光标值会先被压到新长度、之后又被减一次，于是光标多左移一格，
					// 连续退格时文本最右侧的字永远删不掉。
					caretIndex--;
					text = text.substring(0, caretIndex) + text.substring(caretIndex + 1);
					if(onChange != null) onChange(lastText, text);
					if(broadcastInputTextEvent) PsychUIEventHandler.event(CHANGE_EVENT, this);
				}
				_nextAccent = NONE;

			case DELETE: //Delete letter to the right of caret
				if(selectIndex > -1 && selectIndex != caretIndex)
				{
					deleteSelection();
					updateCaret();
					return;
				}

				if(caretIndex >= text.length) return;

				var lastText = text;
				if(caretIndex < 1)
					text = text.substr(1);
				else
					text = text.substring(0, caretIndex) + text.substring(caretIndex+1);

				if(caretIndex >= text.length) caretIndex = text.length;
				
				if(onChange != null) onChange(lastText, text);
				if(broadcastInputTextEvent) PsychUIEventHandler.event(CHANGE_EVENT, this);
			
			case SPACE: //space or last accent pressed
				if (!skipTypeLetter)
				{
					if(_nextAccent != NONE) _typeLetter(getAccentCharCode(_nextAccent));
					else _typeLetter(charCode);
				}
				_nextAccent = NONE;

			case A, O: //these support all accents
				var grave:Int = 0x0;
				var capital:Int = 0x0;
				switch(flxKey)
				{
					case A:
						grave = 0xC0;
						capital = 0x41;
					case O:
						grave = 0xD2;
						capital = 0x4f;
					default:
				}
				if(_nextAccent != NONE)
					charCode += grave - capital + _nextAccent;

				if (!skipTypeLetter) _typeLetter(charCode);
				_nextAccent = NONE;

			case E, I, U: //these support grave, acute and circumflex
				var grave:Int = 0x0;
				var capital:Int = 0x0;
				switch(flxKey)
				{
					case E:
						grave = 0xC8;
						capital = 0x45;
					case I:
						grave = 0xCC;
						capital = 0x49;
					case U:
						grave = 0xD9;
						capital = 0x55;
					default:
				}
				if(_nextAccent == GRAVE || _nextAccent == ACUTE || _nextAccent == CIRCUMFLEX) //Supported accents
					charCode += grave - capital + _nextAccent;
				else if(_nextAccent == TILDE) //Unsupported accent
				{
					if (!skipTypeLetter) _typeLetter(getAccentCharCode(_nextAccent));
				}

				if (!skipTypeLetter) _typeLetter(charCode);
				_nextAccent = NONE;

			case N: //it only supports tilde
				if(_nextAccent == TILDE)
					charCode += 0xD1 - 0x4E;
				else if (!skipTypeLetter)
					_typeLetter(getAccentCharCode(_nextAccent));

				if (!skipTypeLetter) _typeLetter(charCode);
				_nextAccent = NONE;

			case ESCAPE:
				focusOn = null;

			case ENTER:
				onPressEnter(e);

			default:
				if(charCode < 1)
					if((charCode = getAccentCharCode(_nextAccent)) < 1)
						return;

				if (!skipTypeLetter)
				{
					if(lastAccent != NONE) _typeLetter(getAccentCharCode(lastAccent));
					else if(_nextAccent != NONE) _typeLetter(getAccentCharCode(_nextAccent));
					_typeLetter(charCode);
				}
				_nextAccent = NONE;
		}
		updateCaret();
	}

	public dynamic function onPressEnter(e:KeyboardEvent)
	{
		FlxG.stage.window.textInputEnabled = false;
		focusOn = null;
	}

	/**
	 * lime SDL onTextInput 回调 —— 处理 IME（如中文拼音）组合后的完整文本。
	 * SDL_TEXTINPUT 事件在字符最终确认后触发，value 可能包含多字节 Unicode 字符。
	 * 这个通道是处理中文/日文/韩文等需要输入法组合的语言的唯一正确方式，
	 * 因为 KeyboardEvent.charCode 在 IME 激活期间不可靠（openfl 文档明确说明）。
	 */
	function _onWindowTextInput(value:String):Void
	{
		if (focusOn != this || value == null || value.length == 0) return;

		var lastText = text;

		// 如果有选区，先删除
		if (selectIndex > -1 && selectIndex != caretIndex)
			deleteSelection();

		// 插入 IME 提交的完整 Unicode 字符串
		var inserted:String = filter(value);
		if (inserted.length > 0 && (maxLength == 0 || (Std.int(text.length) + Std.int(inserted.length)) <= maxLength))
		{
			var insLen:Int = Std.int(inserted.length);
			if (inInsertMode)
			{
				var restStart:Int = Std.int(Math.min(caretIndex + insLen, Std.int(text.length)));
				text = text.substring(0, caretIndex) + inserted + text.substring(restStart);
			}
			else
			{
				text = text.substring(0, caretIndex) + inserted + text.substring(caretIndex);
			}

			caretIndex += insLen;
			if (onChange != null) onChange(lastText, text);
			if (broadcastInputTextEvent) PsychUIEventHandler.event(CHANGE_EVENT, this);
		}
		_caretTime = 0;
		updateCaret();
	}

	public var unfocus:Void->Void;
	public static function set_focusOn(v:PsychUIInputText)
	{
		// 旧焦点正在销毁时不再回调 unfocus / resetCaret：它会回头写 text，
		// 而此刻渲染对象与 _boundaries 已被释放（F5 刷新崩溃的根因）。
		if(focusOn != null && focusOn != v && focusOn.exists && !focusOn._destroying)
		{
			if(focusOn.unfocus != null) focusOn.unfocus();
			focusOn.resetCaret();
			focusOn.clearFocusVisual();
			// 旧实例失焦时，移除其 onTextInput 监听
			if (focusOn._textInputListening)
			{
				FlxG.stage.window.onTextInput.remove(focusOn._onWindowTextInput);
				focusOn._textInputListening = false;
			}
		}
		// 失焦到空白时必须关闭输入法，否则 textInputEnabled 会一直为 true，
		// 导致 Windows 上 IME 持续激活，非英文输入法态下键盘 UI 输入被吞掉。
		if (v == null && FlxG.stage.window.textInputEnabled)
			FlxG.stage.window.textInputEnabled = false;
		else if (v != null && !v._textInputListening)
		{
			// 新实例获得焦点时，注册 onTextInput 以接收 IME 组合后的完整文本
			FlxG.stage.window.onTextInput.add(v._onWindowTextInput);
			v._textInputListening = true;
		}
		return (focusOn = v);
	}

	override function update(elapsed:Float)
	{
		super.update(elapsed);
		if (backend.ui.DropdownInputPriority.shouldBlockInput(this)) return;

		if(FlxG.mouse.justPressed)
		{
			if(FlxG.mouse.overlaps(behindText, camera))
			{
				if(!FlxG.keys.pressed.SHIFT) selectIndex = -1;
				else if(selectIndex == -1) selectIndex = caretIndex;
				focusOn = this;
				FlxG.stage.window.textInputEnabled = true;
				caretIndex = 0;
				var lastBound:Float = 0;
				var textObjX:Float = textObj.getScreenPosition(camera).x;
				var mousePosX:Float = FlxG.mouse.getScreenPosition(camera).x;
				var txtX:Float = textObjX - textObj.textField.scrollH;

				for (i => bound in _boundaries)
				{
					if(mousePosX >= txtX + (bound - lastBound)/2)
					{
						caretIndex = i+1;
						txtX += bound - lastBound;
						lastBound = bound;
					}
					else break;
				}
				updateCaret();
			}
			else if(focusOn == this)
				focusOn = null;

			//trace('changed focus to: ' + this);
		}

		if(focusOn == this)
		{
			_caretTime = (_caretTime + elapsed) % 1;
			if(textObj != null && textObj.exists)
			{
				var drewSelection:Bool = false;
				if(selection != null && selection.exists)
				{
					if(selectIndex != -1 && selectIndex != caretIndex)
					{
						selection.visible = true;
						drewSelection = true;
					}
					else selection.visible = false;
				}
	
				if(caret != null && caret.exists)
				{
					if(!drewSelection && _caretTime < 0.5 && caret.x >= textObj.x)
					{
						caret.visible = true;
						caret.color = textObj.color;
					}
					else caret.visible = false;
				}
			}

			// 更新 IME 候选框定位
			updateTextInputRect();
		}
		else
		{
			_caretTime = 0;
			inInsertMode = false;
			if(selection != null && selection.exists) selection.visible = false;
			if(caret != null && caret.exists) caret.visible = false;
		}
	}

	public function resetCaret()
	{
		selectIndex = -1;
		caretIndex = 0;
		updateCaret();
	}

	/**
	 * 失焦时强制清掉聚焦视觉，等价于 update() 里 `focusOn != this` 的 else 分支。
	 * 下拉框选中选项的那一帧，shouldBlockInput() 闸门会提前 return，让那个 else
	 * 没机会执行 —— 于是 caret / selection 残留、inInsertMode 还开着，看起来
	 * 就像文本框仍在聚焦。所有失焦路径统一在这里收尾，不依赖 update 是否跑完。
	 */
	public function clearFocusVisual():Void
	{
		_caretTime = 0;
		inInsertMode = false;
		if (selection != null && selection.exists) selection.visible = false;
		if (caret != null && caret.exists) caret.visible = false;
	}

	/**
	 * 计算 caret 的窗口屏幕坐标，设置 SDL textInputRect。
	 * 这让 Windows/macOS 上 IME 候选框定位到 caret 附近，而不是飘在屏幕某个角落。
	 * 坐标转换：FlxSprite 本地坐标 → 屏幕坐标（camera 校正） → 窗口 client 坐标（lime SDL 原生）。
	 * 只在位置变化时才调用 SDL API，避免无意义开销。
	 */
	function updateTextInputRect():Void
	{
		if (!exists || caret == null || !caret.exists) return;

		var pos:FlxPoint = caret.getScreenPosition(camera);
		// caret.y 已经是 textObj.y + 2 这样的偏移，但 getScreenPosition 会自动加 camera
		var x:Float = pos.x;
		var y:Float = pos.y;

		// 加一个最小尺寸让 SDL 有参考
		var h:Float = textObj != null && textObj.exists ? textObj.height : 20;

		if (Math.abs(x - _lastTextInputRectX) < 1 && Math.abs(y - _lastTextInputRectY) < 1) return;

		_lastTextInputRectX = x;
		_lastTextInputRectY = y;

		var rect:Rectangle = new Rectangle(x, y, 2, h);
		FlxG.stage.window.setTextInputRect(rect);
	}

	public function updateCaret()
	{
		if(textObj == null || !textObj.exists) return;

		var textField = textObj.textField;
		// 防御性 clamp，任何路径进来都要保证不越界
		var len:Int = textField.text != null ? textField.text.length : 0;
		if(caretIndex > len) caretIndex = len;
		if(caretIndex < 0) caretIndex = 0;
		if(selectIndex > len) selectIndex = len;
		if(selectIndex < -1) selectIndex = -1;
		textField.setSelection(caretIndex, caretIndex);
		_caretTime = 0;
		if(caret != null && caret.exists)
		{
			caret.y = textObj.y + 2;
			caret.x = textObj.x + 1 - textObj.textField.scrollH;
			if(caretIndex > 0)
				caret.x += _boundaries[Std.int(Math.max(0, Math.min(_boundaries.length-1, caretIndex-1)))];
		}
		
		if(selection != null && selection.exists)
		{
			selection.y = textObj.y + 2;
			selection.x = textObj.x + 1 - textObj.textField.scrollH;
			if(selectIndex > 0)
				selection.x += _boundaries[Std.int(Math.max(0, Math.min(_boundaries.length-1, selectIndex-1)))];

			selection.scale.y = textField.textHeight;
			selection.scale.x = caret.x - selection.x;
			if(selection.scale.x < 0)
			{
				selection.scale.x = Math.abs(selection.scale.x);
				selection.x -= selection.scale.x;
			}

			if(selection.x < textObj.x)
			{
				var diff:Float = textObj.x - selection.x;
				selection.x += diff;
				selection.scale.x -= diff;
			}
			if(selection.x + selection.scale.x > textObj.x + textObj.width)
				selection.scale.x += (textObj.x + textObj.width - selection.x - selection.scale.x);

			selection.updateHitbox();

			if(text.length > 0)
			{
				textObj.removeFormat(selectedFormat);
				if(selectIndex != -1 && selectIndex != caretIndex)
				{
					textObj.addFormat(selectedFormat, caretIndex < selectIndex ? caretIndex : selectIndex, caretIndex < selectIndex ? selectIndex : caretIndex);
				}
			}
		}
		else if(text.length > 0) textObj.removeFormat(selectedFormat);
	}

	function deleteSelection()
	{
		var lastText:String = text;
		if(selectIndex > caretIndex)
		{
			text = text.substring(0, caretIndex) + text.substring(selectIndex);
		}
		else
		{
			text = text.substring(0, selectIndex) + text.substring(caretIndex);
			caretIndex = selectIndex;
		}
		selectIndex = -1;
		if(onChange != null) onChange(lastText, text);
		if(broadcastInputTextEvent) PsychUIEventHandler.event(CHANGE_EVENT, this);
	}

	override public function destroy()
	{
		// 必须先标记：下面的 focusOn = null 会走 set_focusOn，析构期禁止再回调 unfocus
		_destroying = true;
		_boundaries = null;
		if (focusOn == this)
		{
			// 先移除 onTextInput 监听，再置空 focusOn
			if (_textInputListening)
			{
				FlxG.stage.window.onTextInput.remove(_onWindowTextInput);
				_textInputListening = false;
			}
			focusOn = null;
		}
		else if (_textInputListening)
		{
			// 虽然不是当前焦点，但保险起见也清理掉
			FlxG.stage.window.onTextInput.remove(_onWindowTextInput);
			_textInputListening = false;
		}
		FlxG.stage.removeEventListener(KeyboardEvent.KEY_DOWN, onKeyDown);
		super.destroy();
	}

	function set_caretIndex(v:Int)
	{
		caretIndex = v;
		updateCaret();
		return v;
	}

	override public function setGraphicSize(width:Float = 0, height:Float = 0)
	{
		super.setGraphicSize(width, height);
		bg.setGraphicSize(width, height);
		behindText.setGraphicSize(width - 2, height - 2);
		PsychUIRounded.apply(bg, width, height);
		PsychUIRounded.apply(behindText, width - 2, height - 2);
		if(textObj != null && textObj.exists)
		{
			textObj.scale.x = 1;
			textObj.scale.y = 1;
			if(caret != null && caret.exists) caret.setGraphicSize(1, textObj.height - 4);
		}
	}
	
	override public function updateHitbox()
	{
		super.updateHitbox();
		bg.updateHitbox();
		behindText.updateHitbox();
		if(textObj != null && textObj.exists)
		{
			textObj.updateHitbox();
			if(caret != null && caret.exists) caret.updateHitbox();
		}
	}

	function set_fieldWidth(v:Int)
	{
		textObj.fieldWidth = Math.max(1, v - 2);
		textObj.textField.selectable = false;
		textObj.textField.wordWrap = false;
		textObj.textField.multiline = false;
		return (fieldWidth = v);
	}

	function set_maxLength(v:Int)
	{
		var lastText = text;
		v = Std.int(Math.max(0, v));
		if(v > 0 && text.length > v) text = text.substr(0, v);
		if(onChange != null) onChange(lastText, text);
		if(broadcastInputTextEvent) PsychUIEventHandler.event(CHANGE_EVENT, this);
		return (maxLength = v);
	}

	function set_passwordMask(v:Bool)
	{
		passwordMask = v;
		text = text;
		return passwordMask;
	}

	var _boundaries:Array<Float> = [];
	function set_text(v:String)
	{
		// 析构期 / 异常重入：只保留字段值，绝不触碰已释放的 _boundaries / textObj
		if (_destroying)
		{
			text = v;
			return v;
		}
		if (_boundaries == null) _boundaries = [];
		for (i in 0..._boundaries.length) _boundaries.pop();
		v = filter(v);

		textObj.text = '';
		if(v != null && v.length > 0)
		{
			if(v.length > 1)
			{
				for (i in 0...v.length)
				{
					var toPrint:String = v.substr(i, 1);
					if(toPrint == '\n') toPrint = ' ';
					textObj.textField.appendText(!passwordMask ? toPrint : '*');
					_boundaries.push(textObj.textField.textWidth);
				}
			}
			else
			{
				textObj.text = !passwordMask ? v : '*';
				_boundaries.push(textObj.textField.textWidth);
			}
		}
		text = v;
		// 防止 caretIndex / selectIndex 在文本变短后越界（openfl TextField.setSelection 内部 getLineOffset 会数组越界崩溃）
		if(caretIndex > v.length) caretIndex = v.length;
		if(caretIndex < 0) caretIndex = 0;
		if(selectIndex > v.length) selectIndex = v.length;
		if(selectIndex < -1) selectIndex = -1;
		updateCaret();
		return v;
	}

	public static function getAccentCharCode(accent:AccentCode)
	{
		switch(accent)
		{
			case TILDE:
				return 0x7E;
			case CIRCUMFLEX:
				return 0x5E;
			case ACUTE:
				return 0xB4;
			case GRAVE:
				return 0x60;
			default:
				return 0x0;
		}
	}

	public var broadcastInputTextEvent:Bool = true;
	function _typeLetter(charCode:Int)
	{
		if(charCode < 1) return;
		
		if(selectIndex > -1 && selectIndex != caretIndex)
			deleteSelection();

		var letter:String = String.fromCharCode(charCode);
		letter = filter(letter);
		if(letter.length > 0 && (maxLength == 0 || (text.length + letter.length) <= maxLength))
		{
			var lastText = text;
			//trace('Drawing character: $letter');
			if(!inInsertMode)
				text = text.substring(0, caretIndex) + letter + text.substring(caretIndex);
			else
				text = text.substring(0, caretIndex) + letter + text.substring(caretIndex+1);

			caretIndex += letter.length;
			if(onChange != null) onChange(lastText, text);
			if(broadcastInputTextEvent) PsychUIEventHandler.event(CHANGE_EVENT, this);
		}
		_caretTime = 0;
	}

	// from FlxInputText
	function set_forceCase(v:CaseMode)
	{
		forceCase = v;
		text = filter(text);
		return forceCase;
	}

	function set_filterMode(v:FilterMode)
	{
		filterMode = v;
		text = filter(text);
		return filterMode;
	}

	function set_customFilterPattern(cfp:EReg)
	{
		customFilterPattern = cfp;
		filterMode = CUSTOM_FILTER;
		return customFilterPattern;
	}
	
	private function filter(text:String):String
	{
		switch(forceCase)
		{
			case UPPER_CASE:
				text = text.toUpperCase();
			case LOWER_CASE:
				text = text.toLowerCase();
			default:
		}
		if (forceCase == UPPER_CASE)
			text = text.toUpperCase();
		else if (forceCase == LOWER_CASE)
			text = text.toLowerCase();

		if (filterMode != NO_FILTER)
		{
			var pattern:EReg;
			switch (filterMode)
			{
				case ONLY_ALPHA:
					pattern = ~/[^a-zA-Z]*/g;
				case ONLY_NUMERIC:
					pattern = ~/[^0-9]*/g;
				case ONLY_ALPHANUMERIC:
					pattern = ~/[^a-zA-Z0-9]*/g;
				case ONLY_HEXADECIMAL:
					pattern = ~/[^a-fA-F0-9]*/g;
				case CUSTOM_FILTER:
					pattern = customFilterPattern;
				default:
					throw new flash.errors.Error("FlxInputText: Unknown filterMode (" + filterMode + ")");
			}
			text = pattern.replace(text, "");
		}
		return text;
	}
}
