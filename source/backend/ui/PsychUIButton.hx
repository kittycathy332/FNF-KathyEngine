package backend.ui;

import backend.Paths;
import backend.ui.PsychUIBox.UIStyleData;

class PsychUIButton extends FlxSpriteGroup
{
	public static final CLICK_EVENT = 'button_click';

	public var name:String;
	public var label(default, set):String;
	public var bg:FlxSprite;
	public var text:FlxText;

	public var onChangeState:String->Void;
	public var onClick:Void->Void;
	
	public var clickStyle:UIStyleData = {
		bgColor: FlxColor.BLACK,
		textColor: FlxColor.WHITE,
		bgAlpha: 1
	};
	public var hoverStyle:UIStyleData = {
		bgColor: FlxColor.WHITE,
		textColor: FlxColor.BLACK,
		bgAlpha: 1
	};
	public var normalStyle:UIStyleData = {
		bgColor: 0xFFAAAAAA,
		textColor: FlxColor.BLACK,
		bgAlpha: 1
	};

	public function new(x:Float = 0, y:Float = 0, label:String = '', ?onClick:Void->Void = null, ?wid:Int = 80, ?hei:Int = 20)
	{
		super(x, y);
		bg = new FlxSprite().makeGraphic(1, 1, FlxColor.WHITE);
		add(bg);
		bg.color = 0xFFAAAAAA;
		bg.alpha = 0.6;

		text = new FlxText(0, 0, 1, '');
		text.size = Std.parseInt(Language.get('button_text_size'));
		text.font = Paths.font(Language.get('uitab_font'));
		text.alignment = CENTER;
		add(text);
		resize(wid, hei);
		this.label = label;
		
		this.onClick = onClick;
		forceCheckNext = true;
	}

	public var isClicked:Bool = false;
	public var forceCheckNext:Bool = false;
	public var broadcastButtonEvent:Bool = true;
	var _firstFrame:Bool = true;

	/** 移动端：根据触摸状态计算"是否刚按下/是否抬起/是否悬停"*/
	function checkTouch():{pressed:Bool, released:Bool, overlaps:Bool}
	{
		#if FLX_TOUCH
		if (camera == null) return {pressed: false, released: false, overlaps: false};

		var touches = FlxG.touches.list;
		var anyOverlapped:Bool = false;
		var pressed:Bool = false;
		var released:Bool = false;

		for (touch in touches)
		{
			if (touch == null) continue;

			var worldPos = touch.getWorldPosition(camera);
			var overlapped:Bool = worldPos.x > bg.x && worldPos.x < bg.x + bg.width
				&& worldPos.y > bg.y && worldPos.y < bg.y + bg.height;
			if (overlapped)
			{
				anyOverlapped = true;
				if (touch.justPressed) pressed = true;
			}

			// 任意触摸点刚抬起即视为 released
			if (touch.justReleased) released = true;
		}
		return {pressed: pressed, released: released, overlaps: anyOverlapped};
		#else
		return {pressed: false, released: false, overlaps: false};
		#end
	}

	/** 移动端：按下/抬起通知钩子，供外部（如子状态）统一监听触摸，避免依赖 FlxG.mouse */
	public var onTouchJustPressed:Void->Void = null;
	public var onTouchJustReleased:Void->Void = null;

	override function update(elapsed:Float)
	{
		if (!active || !exists || camera == null) return;
		super.update(elapsed);
		if (backend.ui.DropdownInputPriority.shouldBlockInput(this)) return;

		if(_firstFrame)
		{
			bg.color = normalStyle.bgColor;
			bg.alpha = normalStyle.bgAlpha;
			text.color = normalStyle.textColor;
			_firstFrame = false;
		}

		#if FLX_TOUCH
		var touch = checkTouch();
		if (isClicked && (FlxG.mouse.released || touch.released))
		{
			forceCheckNext = true;
			isClicked = false;
			if (onTouchJustReleased != null) onTouchJustReleased();
		}

		if (touch.pressed)
		{
			isClicked = true;
			bg.color = clickStyle.bgColor;
			bg.alpha = clickStyle.bgAlpha;
			text.color = clickStyle.textColor;
			if (onClick != null) onClick();
			if (broadcastButtonEvent) PsychUIEventHandler.event(CLICK_EVENT, this);
			if (onTouchJustPressed != null) onTouchJustPressed();
		}
		else if(!isClicked)
		{
			// 鼠标路径负责非触摸时的状态；触摸路径只在确实重合时才接管，避免每帧用 normalStyle 覆盖鼠标高亮导致闪烁
			if(touch.overlaps)
			{
				bg.color = hoverStyle.bgColor;
				bg.alpha = hoverStyle.bgAlpha;
				text.color = hoverStyle.textColor;
			}
		}
		#end

		if(forceCheckNext || FlxG.mouse.justMoved || FlxG.mouse.justPressed)
		{
			var overlapped:Bool = (FlxG.mouse.overlaps(bg, camera));

			forceCheckNext = false;

			if(!isClicked)
			{
				var style:UIStyleData = (overlapped) ? hoverStyle : normalStyle;
				bg.color = style.bgColor;
				bg.alpha = style.bgAlpha;
				text.color = style.textColor;
			}

			if(overlapped && FlxG.mouse.justPressed)
			{
				isClicked = true;
				bg.color = clickStyle.bgColor;
				bg.alpha = clickStyle.bgAlpha;
				text.color = clickStyle.textColor;
				if(onClick != null) onClick();
				if(broadcastButtonEvent) PsychUIEventHandler.event(CLICK_EVENT, this);
			}
		}
	}

	public function resize(width:Int, height:Int)
	{
		bg.setGraphicSize(width, height);
		bg.updateHitbox();
		text.fieldWidth = width;
		text.x = bg.x;
		text.y = bg.y + height/2 - text.height/2;
	}

	function set_label(v:String)
	{
		if(text != null && text.exists) text.text = v;
		return (label = v);
	}
}