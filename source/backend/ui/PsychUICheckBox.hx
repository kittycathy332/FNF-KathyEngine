package backend.ui;

import backend.Paths;

class PsychUICheckBox extends FlxSpriteGroup
{
	public static final CLICK_EVENT = 'checkbox_click';

	public var name:String;
	public var box:FlxSprite;
	public var text:FlxText;
	public var label(get, set):String;

	public var checked(default, set):Bool = false;
	public var onClick:Void->Void = null;

	public function new(x:Float, y:Float, label:String, ?textWid:Int = 100, ?callback:Void->Void)
	{
		super(x, y);

		box = new FlxSprite();
		boxGraphic();
		add(box);

		text = new FlxText(box.width + 6, 0, textWid, label, Std.parseInt(Language.get('checkbox_font_size')));
		text.font = Paths.font(Language.get('uitab_font'));
		text.y += box.height/2 - text.height/2;
		add(text);

		this.onClick = callback;
	}

	public function boxGraphic()
	{
		if (PsychUIRounded.radius > 0) box.loadGraphic(PsychUIRounded.checkSheet(), true, 16, 16);
		else box.loadGraphic(Paths.image('psych-ui/checkbox', 'embed'), true, 16, 16);
		box.antialiasing = false;
		box.animation.add('false', [0]);
		box.animation.add('true', [1]);
		box.animation.play('false');
	}

	public var broadcastCheckBoxEvent:Bool = true;
	override function update(elapsed:Float)
	{
		if (!active || !exists || camera == null || box == null || text == null) return;
		super.update(elapsed);
		if (backend.ui.DropdownInputPriority.shouldBlockInput(this)) return;

		if(FlxG.mouse.justPressed)
		{
			var screenPos:FlxPoint = getScreenPosition(null, camera);
			var mousePos:FlxPoint = FlxG.mouse.getPositionInCameraView(camera);
			if((mousePos.x >= screenPos.x && mousePos.x < screenPos.x + width) &&
				(mousePos.y >= screenPos.y && mousePos.y < screenPos.y + height))
			{
				checked = !checked;
				if(onClick != null) onClick();
				if(broadcastCheckBoxEvent) PsychUIEventHandler.event(CLICK_EVENT, this);
			}
		}
	}

	function set_checked(v:Any)
	{
		var v:Bool = (v != null && v != false);
		box.animation.play(Std.string(v));
		return (checked = v);
	}

	function get_label():String {
		return text.text;
	}
	function set_label(v:String):String {
		return (text.text = v);
	}
}