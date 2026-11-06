package mobile.objects;

import flixel.util.FlxSignal.FlxTypedSignal;

/**
 * Arrows 操作模式的触控层。
 *
 * 与 Hitbox 一样输出同一套 MobileInputID，但不渲染整屏轨道：
 * 每个音符列是一个透明的 TouchButton 矩形，由 PlayState 按底部箭头位置
 * （外扩 26px）调用 relayout() 摆放；额外功能键按 extraButtons 设置在屏幕顶部 1/4。
 */
class ArrowsPad extends MobileInputManager implements IMobileControls
{
	public static inline var TOUCH_PADDING:Float = 26;

	public var buttonLeft:TouchButton;
	public var buttonDown:TouchButton;
	public var buttonUp:TouchButton;
	public var buttonRight:TouchButton;
	public var buttonExtra:TouchButton;
	public var buttonExtra2:TouchButton;
	public var buttonExtra3:TouchButton;
	public var buttonExtra4:TouchButton;

	public var instance:MobileInputManager;

	public var onButtonDown:FlxTypedSignal<TouchButton->Void> = new FlxTypedSignal<TouchButton->Void>();
	public var onButtonUp:FlxTypedSignal<TouchButton->Void> = new FlxTypedSignal<TouchButton->Void>();

	var laneButtons:Array<TouchButton> = [];

	public function new(?extraMode:ExtraActions = ZERO)
	{
		super();

		instance = this;
		scrollFactor.set();

		createExtras(extraMode);
		ensureLaneCount(4);
	}

	/**
	 * 按音符列数重建/复用透明 lane 按钮。
	 */
	public function ensureLaneCount(count:Int):Void
	{
		if (count < 1) count = 4;
		if (count == laneButtons.length) return;

		while (laneButtons.length > count)
		{
			var btn:TouchButton = laneButtons.pop();
			remove(btn);
			btn.destroy();
		}

		while (laneButtons.length < count)
		{
			var index:Int = laneButtons.length;
			laneButtons.push(addLaneButton(index));
		}

		if (laneButtons.length >= 4)
		{
			buttonLeft = laneButtons[0];
			buttonDown = laneButtons[1];
			buttonUp = laneButtons[2];
			buttonRight = laneButtons[3];
		}

		updateTrackedButtons();
	}

	/**
	 * 用箭头按钮的屏幕矩形摆放触控区。
	 * rects 元素格式：[x, y, width, height]
	 */
	public function relayout(rects:Array<Array<Float>>):Void
	{
		if (rects == null || rects.length == 0) return;
		ensureLaneCount(rects.length);

		for (i in 0...laneButtons.length)
		{
			var rect:Array<Float> = rects[i];
			var btn:TouchButton = laneButtons[i];
			btn.setPosition(rect[0], rect[1]);
			btn.setGraphicSize(Std.int(Math.max(rect[2], 1)), Std.int(Math.max(rect[3], 1)));
			btn.updateHitbox();
		}

		updateTrackedButtons();
	}

	function addLaneButton(index:Int):TouchButton
	{
		var btn:TouchButton = new TouchButton(-1000, -1000, laneIDs(index));
		btn.makeGraphic(1, 1, 0x00000000); // 完全透明，仅用于触摸判定
		btn.statusAlphas = [1, 1, 1];
		btn.statusBrightness = [1, 1, 1];
		btn.canChangeLabelAlpha = false;
		btn.multiTouch = true;
		btn.immovable = true;
		btn.solid = false;
		btn.moves = false;
		btn.antialiasing = ClientPrefs.data.antialiasing;
		btn.onDown.callback = () -> onButtonDown.dispatch(btn);
		btn.onOut.callback = btn.onUp.callback = () -> onButtonUp.dispatch(btn);
		add(btn);
		return btn;
	}

	static function laneIDs(index:Int):Array<MobileInputID>
	{
		return switch (index)
		{
			case 0: [MobileInputID.HITBOX_LEFT, MobileInputID.NOTE_LEFT];
			case 1: [MobileInputID.HITBOX_DOWN, MobileInputID.NOTE_DOWN];
			case 2: [MobileInputID.HITBOX_UP, MobileInputID.NOTE_UP];
			case 3: [MobileInputID.HITBOX_RIGHT, MobileInputID.NOTE_RIGHT];
			default: [Hitbox.noteIDForIndex(index)];
		};
	}

	/**
	 * 额外功能键（A/B/C/D）：跟随 extraButtons 设置，放在屏幕顶部 1/4，避免与底部箭头行重叠。
	 */
	function createExtras(extraMode:ExtraActions):Void
	{
		var count:Int = switch (extraMode)
		{
			case ONE: 1;
			case TWO: 2;
			case THREE: 3;
			case FOUR: 4;
			default: 0;
		}
		if (count == 0) return;

		var colors:Array<Int> = [0xFF0066FF, 0xA6FF00, 0xFF00A6FF, 0xFFFFA600];
		var zoneW:Int = Std.int(FlxG.width / count);
		var zoneH:Int = Std.int(FlxG.height / 4);

		for (i in 0...count)
		{
			var btn:TouchButton = new TouchButton(i * zoneW, 0, [extraID(i)]);
			btn.makeGraphic(1, 1, colors[i]);
			btn.setGraphicSize(zoneW, zoneH);
			btn.updateHitbox();
			btn.statusAlphas = [1, 1, 0.6];
			btn.canChangeLabelAlpha = false;
			btn.multiTouch = true;
			btn.immovable = true;
			btn.solid = false;
			btn.moves = false;
			btn.antialiasing = ClientPrefs.data.antialiasing;
			btn.onDown.callback = () -> onButtonDown.dispatch(btn);
			btn.onOut.callback = btn.onUp.callback = () -> onButtonUp.dispatch(btn);
			add(btn);

			switch (i)
			{
				case 0: buttonExtra = btn;
				case 1: buttonExtra2 = btn;
				case 2: buttonExtra3 = btn;
				default: buttonExtra4 = btn;
			}
		}
	}

	static function extraID(index:Int):MobileInputID
	{
		return switch (index)
		{
			case 0: MobileInputID.EXTRA_1;
			case 1: MobileInputID.EXTRA_2;
			case 2: MobileInputID.EXTRA_3;
			default: MobileInputID.EXTRA_4;
		}
	}

	override public function destroy():Void
	{
		onButtonUp.destroy();
		onButtonDown.destroy();
		super.destroy();
	}
}
