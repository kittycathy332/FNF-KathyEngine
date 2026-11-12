package backend.ui;

import backend.Paths;
import backend.Language;
import backend.ui.PsychUIBox.UIStyleData;

class PsychUIDropDownMenu extends PsychUIInputText
{
	public static final CLICK_EVENT = "dropdown_click";

	public var list(default, set):Array<String> = [];
	public var button:FlxSprite;
	public var onSelect:Int->String->Void;

	public var selectedIndex(default, set):Int = -1;
	public var selectedLabel(default, set):String = null;

	var _curFilter:Array<String>;
	var _itemWidth:Float = 0;
	public var markedIndices:Array<Int> = [];
	public function new(x:Float, y:Float, list:Array<String>, callback:Int->String->Void, ?width:Float = 100)
	{
		super(x, y);
		if(list == null) list = [];

		_itemWidth = width - 2;
		setGraphicSize(width, 20);
		updateHitbox();
		// 让闭合框的选中标签文字宽度跟随下拉框实际宽度，避免文字超出后被裁剪（默认固定 ~98 与宽度脱钩）
		fieldWidth = Std.int(width - 5);
		textObj.y += 2;

		button = new FlxSprite(Math.max(0, width - 5), 0);
		if (PsychUIRounded.radius > 0) button.loadGraphic(PsychUIRounded.dropDownButtonSheet(), true, 20, 20);
		else button.loadGraphic(Paths.image('psych-ui/dropdown_button', 'embed'), true, 20, 20);
		button.antialiasing = false;
		button.animation.add('normal', [0], false);
		button.animation.add('pressed', [1], false);
		button.animation.play('normal', true);
		add(button);

		onSelect = callback;

		onChange = function(old:String, cur:String)
		{
			if(old != cur)
			{
				_curFilter = this.list.filter(function(str:String) return str.startsWith(cur));
				showDropDown(true, 0, _curFilter);
			}
		}
		unfocus = function()
		{
			showDropDownClickFix();
			showDropDown(false);
		}

		for (option in list)
			addOption(option);

		selectedIndex = 0;
		showDropDown(false);
	}

	function set_selectedIndex(v:Int)
	{
		selectedIndex = v;
		if(selectedIndex < 0 || selectedIndex >= list.length) selectedIndex = -1;

		@:bypassAccessor selectedLabel = list[selectedIndex];
		text = (selectedLabel != null) ? selectedLabel : '';
		return selectedIndex;
	}

	function set_selectedLabel(v:String)
	{
		var id:Int = list.indexOf(v);
		if(id >= 0)
		{
			@:bypassAccessor selectedIndex = id;
			selectedLabel = v;
			text = selectedLabel;
		}
		else
		{
			@:bypassAccessor selectedIndex = -1;
			selectedLabel = null;
			text = '';
		}
		return selectedLabel;
	}

	var _items:Array<PsychUIDropDownItem> = [];
	public var curScroll:Int = 0;
	override function update(elapsed:Float)
	{
		// 父类 PsychUIInputText.update() 里的闸门只能拦住父类函数体；本类覆写了
		// update()，其后的 header 点击 / showDropDown 仍会执行。这里再拦一次，
		// 避免「选项位置压着另一个下拉框」时下方那个也被拉下。展开中的下拉框
		// 在 currentProtected 里，shouldBlockInput() 会放行，不受影响。
		if (DropdownInputPriority.shouldBlockInput(this)) return;
		var lastFocus = PsychUIInputText.focusOn;
		super.update(elapsed);
		if(FlxG.mouse.justPressed)
		{
			if(FlxG.mouse.overlaps(button, camera))
			{
				button.animation.play('pressed', true);
				if(lastFocus != this)
					PsychUIInputText.focusOn = this;
				else if(PsychUIInputText.focusOn == this)
					PsychUIInputText.focusOn = null;
			}
		}
		else if(FlxG.mouse.released && button.animation.curAnim != null && button.animation.curAnim.name != 'normal') button.animation.play('normal', true);

		if(lastFocus != PsychUIInputText.focusOn)
		{
			showDropDown(PsychUIInputText.focusOn == this);
		}
		else if(PsychUIInputText.focusOn == this)
		{
			var wheel:Int = FlxG.mouse.wheel;
			if(FlxG.keys.justPressed.UP) wheel++;
			if(FlxG.keys.justPressed.DOWN) wheel--;
			/*#if FLX_TOUCH
			for (touch in FlxG.touches.list)
			{
				var moveY:Int = 0;
				var addition:Int = 0;
				var curY:Int = 0;
				var prevY:Int = 0;

				if (touch.pressed)
				{
					curY = touch.y;

					// these might need to be swaped idk i can't test
					if (curY > prevY)
						addition++;
					else
						addition--;

					// change the option every 10 pixels you move
					if (addition >= 10 || addition <= 10)
					{
						// these here might also need to be swapped
						if (addition >= 10)
							moveY++
						else
							moveY--;

						addition = 0;
					}

					prevY = curY;
				}

				wheel += moveY;

				if (touch.justReleased)
					moveY = addition = curY = prevY = 0;
			}
			#end*/
			if(wheel != 0) showDropDown(true, curScroll - wheel, _curFilter);
		}
	}

	private function showDropDownClickFix()
	{
		if(FlxG.mouse.justPressed)
		{
			for (item in _items) //extra update to fix a little bug where it wouldnt click on any option if another input text was behind the drop down
				if(item != null && item.active && item.visible)
					item.update(0);
		}
	}

	public function showDropDown(vis:Bool = true, scroll:Int = 0, onlyAllowed:Array<String> = null)
	{
		if(!vis)
		{
			text = selectedLabel;
			_curFilter = null;
		}

		curScroll = Std.int(Math.max(0, Math.min(onlyAllowed != null ? (onlyAllowed.length - 1) : (list.length - 1), scroll)));
		if(vis)
		{
			var n:Int = 0;
			for (item in _items)
			{
				if(onlyAllowed != null)
				{
					if(onlyAllowed.contains(item.label))
					{
						item.active = item.visible = (n >= curScroll);
						n++;
					}
					else item.active = item.visible = false;
				}
				else
				{
					item.active = item.visible = (n >= curScroll);
					n++;
				}
			}

			var txtY:Float = behindText.y + behindText.height + 1;
			for (num => item in _items)
			{
				if(!item.visible) continue;
				item.x = behindText.x;
				item.y = txtY;
				txtY += item.height;
				item.forceNextUpdate = true;
			}
			// 下拉展开时背景变高：圆角皮肤必须按新高度重烘焙，不能只写 scale.y
			PsychUIRounded.resizeHeight(bg, txtY - behindText.y + 2);
		}
		else
		{
			for (item in _items)
				item.active = item.visible = false;

			PsychUIRounded.resizeHeight(bg, 20);
		}
		DropdownInputPriority.setOpen(this, vis);
	}

	public var broadcastDropDownEvent:Bool = true;
	function clickedOn(num:Int, label:String)
	{
		selectedIndex = num;
		showDropDown(false);
		// 选中选项后必须主动失焦：下拉框本体是 PsychUIInputText，静态 focusOn
		// 若仍是 this，caret 会继续闪、IME 继续激活、还能继续打字过滤。
		// 这里不能只靠 PsychUIInputText.update() 的「点外部 -> focusOn = null」：
		// 收起当帧的 shouldBlockInput 闸门会提前 return，把那段逻辑跳过。
		if (PsychUIInputText.focusOn == this) PsychUIInputText.focusOn = null;
		if(onSelect != null) onSelect(num, label);
		if(broadcastDropDownEvent) PsychUIEventHandler.event(CLICK_EVENT, this);
	}

	function addOption(option:String)
	{
		@:bypassAccessor list.push(option);
		var curID:Int = list.length - 1;
		var item:PsychUIDropDownItem = cast recycle(PsychUIDropDownItem, () -> new PsychUIDropDownItem(1, 1, this._itemWidth), true);
		item.cameras = cameras;
		item.label = option;
		item.visible = item.active = false;
		item.onClick = function() clickedOn(curID, option);
		item.forceNextUpdate = true;
		_items.push(item);
		insert(1, item);
	}

	function set_list(v:Array<String>)
	{
		var selected:String = selectedLabel;
		showDropDown(false);

		for (item in _items)
			item.kill();

		_items = [];
		list = [];
		markedIndices = [];
		for (option in v)
			addOption(option);

		if(selectedLabel != null) selectedLabel = selected;
		return v;
	}

	public function markItem(index:Int)
	{
		if(!markedIndices.contains(index))
			markedIndices.push(index);
		if(index >= 0 && index < _items.length)
			_items[index].marked = true;
	}

	public function markItems(indices:Array<Int>)
	{
		for (i in indices) markItem(i);
	}
}

class PsychUIDropDownItem extends FlxSpriteGroup
{
	public var hoverStyle:UIStyleData = {
		bgColor: 0xFF0066FF,
		textColor: FlxColor.WHITE,
		bgAlpha: 1
	};
	public var normalStyle:UIStyleData = {
		bgColor: FlxColor.WHITE,
		textColor: FlxColor.BLACK,
		bgAlpha: 1
	};
	public var markedStyle:UIStyleData = {
		bgColor: 0xFFB3E5FC,
		textColor: FlxColor.BLACK,
		bgAlpha: 1
	};
	public var markedHoverStyle:UIStyleData = {
		bgColor: 0xFF0288D1,
		textColor: FlxColor.WHITE,
		bgAlpha: 1
	};

	public var marked:Bool = false;
	public var bg:FlxSprite;
	public var text:FlxText;
	public function new(x:Float = 0, y:Float = 0, width:Float = 100)
	{
		super(x, y);

		bg = new FlxSprite().makeGraphic(1, 1, FlxColor.WHITE);
		bg.setGraphicSize(width, 20);
		bg.updateHitbox();
		PsychUIRounded.apply(bg, width, 20);
		add(bg);

		text = new FlxText(0, 0, width, '', 10);
		text.font = Paths.font(Language.get('uitab_font_small'));
		text.color = FlxColor.BLACK;
		text.textField.wordWrap = false;
		text.textField.multiline = false;
		add(text);
	}

	public var onClick:Void->Void;
	public var forceNextUpdate:Bool = false;
	override function update(elapsed:Float)
	{
		super.update(elapsed);
		if(FlxG.mouse.justMoved || FlxG.mouse.justPressed || forceNextUpdate)
		{
			var overlapped:Bool = (FlxG.mouse.overlaps(bg, camera));

			var style;
			if(marked)
				style = overlapped ? markedHoverStyle : markedStyle;
			else
				style = overlapped ? hoverStyle : normalStyle;
			bg.color = style.bgColor;
			text.color = style.textColor;
			bg.alpha = style.bgAlpha;
			forceNextUpdate = false;

			if(overlapped && FlxG.mouse.justPressed)
				onClick();
		}
		
		text.x = bg.x;
		text.y = bg.y + bg.height/2 - text.height/2;
	}

	public var label(default, set):String;
	function set_label(v:String)
	{
		label = v;
		text.text = v;
		PsychUIRounded.resizeHeight(bg, text.height + 6);
		return v;
	}
}
