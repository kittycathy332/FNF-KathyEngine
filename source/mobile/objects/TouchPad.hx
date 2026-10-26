/*
 * Copyright (C) 2025 Mobile Porting Team
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and associated documentation files (the "Software"),
 * to deal in the Software without restriction, including without limitation
 * the rights to use, copy, modify, merge, publish, distribute, sublicense,
 * and/or sell copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 * DEALINGS IN THE SOFTWARE.
 */

package mobile.objects;

import flixel.util.FlxSignal.FlxTypedSignal;

/**
 * ...
 * @author: Karim Akra and Homura Akemi (HomuHomu833)
 */
@:access(mobile.objects.TouchButton)
class TouchPad extends MobileInputManager implements IMobileControls
{
	public var buttonLeft:TouchButton = new TouchButton(0, 0, [MobileInputID.LEFT, MobileInputID.NOTE_LEFT]);
	public var buttonUp:TouchButton = new TouchButton(0, 0, [MobileInputID.UP, MobileInputID.NOTE_UP]);
	public var buttonRight:TouchButton = new TouchButton(0, 0, [MobileInputID.RIGHT, MobileInputID.NOTE_RIGHT]);
	public var buttonDown:TouchButton = new TouchButton(0, 0, [MobileInputID.DOWN, MobileInputID.NOTE_DOWN]);
	public var buttonLeft2:TouchButton = new TouchButton(0, 0, [MobileInputID.LEFT2, MobileInputID.NOTE_LEFT]);
	public var buttonUp2:TouchButton = new TouchButton(0, 0, [MobileInputID.UP2, MobileInputID.NOTE_UP]);
	public var buttonRight2:TouchButton = new TouchButton(0, 0, [MobileInputID.RIGHT2, MobileInputID.NOTE_RIGHT]);
	public var buttonDown2:TouchButton = new TouchButton(0, 0, [MobileInputID.DOWN2, MobileInputID.NOTE_DOWN]);
	public var buttonA:TouchButton = new TouchButton(0, 0, [MobileInputID.A]);
	public var buttonB:TouchButton = new TouchButton(0, 0, [MobileInputID.B]);
	public var buttonC:TouchButton = new TouchButton(0, 0, [MobileInputID.C]);
	public var buttonD:TouchButton = new TouchButton(0, 0, [MobileInputID.D]);
	public var buttonE:TouchButton = new TouchButton(0, 0, [MobileInputID.E]);
	public var buttonF:TouchButton = new TouchButton(0, 0, [MobileInputID.F]);
	public var buttonG:TouchButton = new TouchButton(0, 0, [MobileInputID.G]);
	public var buttonH:TouchButton = new TouchButton(0, 0, [MobileInputID.H]);
	public var buttonI:TouchButton = new TouchButton(0, 0, [MobileInputID.I]);
	public var buttonJ:TouchButton = new TouchButton(0, 0, [MobileInputID.J]);
	public var buttonK:TouchButton = new TouchButton(0, 0, [MobileInputID.K]);
	public var buttonL:TouchButton = new TouchButton(0, 0, [MobileInputID.L]);
	public var buttonM:TouchButton = new TouchButton(0, 0, [MobileInputID.M]);
	public var buttonN:TouchButton = new TouchButton(0, 0, [MobileInputID.N]);
	public var buttonO:TouchButton = new TouchButton(0, 0, [MobileInputID.O]);
	public var buttonP:TouchButton = new TouchButton(0, 0, [MobileInputID.P]);
	public var buttonQ:TouchButton = new TouchButton(0, 0, [MobileInputID.Q]);
	public var buttonR:TouchButton = new TouchButton(0, 0, [MobileInputID.R]);
	public var buttonS:TouchButton = new TouchButton(0, 0, [MobileInputID.S]);
	public var buttonT:TouchButton = new TouchButton(0, 0, [MobileInputID.T]);
	public var buttonU:TouchButton = new TouchButton(0, 0, [MobileInputID.U]);
	public var buttonV:TouchButton = new TouchButton(0, 0, [MobileInputID.V]);
	public var buttonW:TouchButton = new TouchButton(0, 0, [MobileInputID.W]);
	public var buttonX:TouchButton = new TouchButton(0, 0, [MobileInputID.X]);
	public var buttonY:TouchButton = new TouchButton(0, 0, [MobileInputID.Y]);
	public var buttonZ:TouchButton = new TouchButton(0, 0, [MobileInputID.Z]);
	public var buttonExtra:TouchButton = new TouchButton(0, 0, [MobileInputID.EXTRA_1]);
	public var buttonExtra2:TouchButton = new TouchButton(0, 0, [MobileInputID.EXTRA_2]);
	public var buttonExtra3:TouchButton = new TouchButton(0, 0, [MobileInputID.EXTRA_3]);
	public var buttonExtra4:TouchButton = new TouchButton(0, 0, [MobileInputID.EXTRA_4]);

	public var instance:MobileInputManager;
	public var onButtonDown:FlxTypedSignal<TouchButton->Void> = new FlxTypedSignal<TouchButton->Void>();
	public var onButtonUp:FlxTypedSignal<TouchButton->Void> = new FlxTypedSignal<TouchButton->Void>();

	// 性能优化：缓存按钮引用，减少 Reflect 使用
	var _buttonCache:Map<String, TouchButton> = new Map<String, TouchButton>();

	/**
	 * Create a gamepad.
	 *
	 * @param   DPadMode     The D-Pad mode. `LEFT_FULL` for example.
	 * @param   ActionMode   The action buttons mode. `A_B_C` for example.
	 */
	public function new(DPad:String, Action:String, ?Extra:ExtraActions = ZERO)
	{
		super();

		// 性能优化：初始化按钮缓存
		initButtonCache();

		if (DPad != "NONE")
		{
			if (!MobileData.dpadModes.exists(DPad))
				throw LanguageBasic.getPhrase('touchpad_dpadmode_missing', 'The touchPad dpadMode "{1}" doesn\'t exist.', [DPad]);

			for (buttonData in MobileData.dpadModes.get(DPad).buttons)
			{
				var buttonName = buttonData.button;
				var existingButton = _buttonCache.get(buttonName);
				var ids = existingButton != null ? existingButton.IDs : [];
				var newButton = createButton(buttonData.x, buttonData.y, buttonData.graphic, CoolUtil.colorFromString(buttonData.color), ids);
				setButtonByCache(buttonName, newButton);
				add(newButton);
			}
		}

		if (Action != "NONE")
		{
			if (!MobileData.actionModes.exists(Action))
				throw LanguageBasic.getPhrase('touchpad_actionmode_missing', 'The touchPad actionMode "{1}" doesn\'t exist.', [DPad]);

			for (buttonData in MobileData.actionModes.get(Action).buttons)
			{
				var buttonName = buttonData.button;
				var existingButton = _buttonCache.get(buttonName);
				var ids = existingButton != null ? existingButton.IDs : [];
				var newButton = createButton(buttonData.x, buttonData.y, buttonData.graphic, CoolUtil.colorFromString(buttonData.color), ids);
				setButtonByCache(buttonName, newButton);
				add(newButton);
			}
		}

		var count:Int = 0;
		switch (Extra)
		{
			case ONE: count = 1;
			case TWO: count = 2;
			case THREE: count = 3;
			case FOUR: count = 4;
			default: count = 0;
		}

		if (count > 0)
		{
			// 额外键自左向右均匀排布在底部，图形依次为 S/G/T/P
			var extraNames:Array<String> = ['buttonExtra', 'buttonExtra2', 'buttonExtra3', 'buttonExtra4'];
			var extraGraphics:Array<String> = ['s', 'g', 't', 'p'];
			var extraColors:Array<Int> = [0xFF0066FF, 0xA6FF00, 0xFF00A6FF, 0xFFFFA600];
			var slotW:Float = 132;
			var totalW:Float = count * slotW;
			var startX:Float = (FlxG.width - totalW) / 2;
			for (i in 0...count)
			{
				var btn:TouchButton = createButton(startX + i * slotW, FlxG.height - 137, extraGraphics[i], extraColors[i]);
				switch (i)
				{
					case 0: buttonExtra = btn;
					case 1: buttonExtra2 = btn;
					case 2: buttonExtra3 = btn;
					default: buttonExtra4 = btn;
				}
				add(btn);
				_buttonCache.set(extraNames[i], btn);
			}
			setExtrasPos();
		}

		alpha = ClientPrefs.data.controlsAlpha;
		scrollFactor.set();
		updateTrackedButtons();

		instance = this;
	}

	override public function destroy()
	{
		super.destroy();
		onButtonUp.destroy();
		onButtonDown.destroy();

		// 性能优化：清理缓存
		_buttonCache.clear();

		for (fieldName in Reflect.fields(this))
		{
			var field = Reflect.field(this, fieldName);
			if (Std.isOfType(field, TouchButton))
				Reflect.setField(this, fieldName, FlxDestroyUtil.destroy(field));
		}
	}

	/**
	 * 性能优化：初始化按钮缓存，避免重复使用 Reflect
	 */
	private function initButtonCache():Void
	{
		// 缓存主要按钮引用
		_buttonCache.set('buttonLeft', buttonLeft);
		_buttonCache.set('buttonUp', buttonUp);
		_buttonCache.set('buttonRight', buttonRight);
		_buttonCache.set('buttonDown', buttonDown);
		_buttonCache.set('buttonLeft2', buttonLeft2);
		_buttonCache.set('buttonUp2', buttonUp2);
		_buttonCache.set('buttonRight2', buttonRight2);
		_buttonCache.set('buttonDown2', buttonDown2);
		_buttonCache.set('buttonA', buttonA);
		_buttonCache.set('buttonB', buttonB);
		_buttonCache.set('buttonC', buttonC);
		_buttonCache.set('buttonD', buttonD);
		_buttonCache.set('buttonE', buttonE);
		_buttonCache.set('buttonF', buttonF);
		_buttonCache.set('buttonG', buttonG);
		_buttonCache.set('buttonH', buttonH);
		_buttonCache.set('buttonI', buttonI);
		_buttonCache.set('buttonJ', buttonJ);
		_buttonCache.set('buttonK', buttonK);
		_buttonCache.set('buttonL', buttonL);
		_buttonCache.set('buttonM', buttonM);
		_buttonCache.set('buttonN', buttonN);
		_buttonCache.set('buttonO', buttonO);
		_buttonCache.set('buttonP', buttonP);
		_buttonCache.set('buttonQ', buttonQ);
		_buttonCache.set('buttonR', buttonR);
		_buttonCache.set('buttonS', buttonS);
		_buttonCache.set('buttonT', buttonT);
		_buttonCache.set('buttonU', buttonU);
		_buttonCache.set('buttonV', buttonV);
		_buttonCache.set('buttonW', buttonW);
		_buttonCache.set('buttonX', buttonX);
		_buttonCache.set('buttonY', buttonY);
		_buttonCache.set('buttonZ', buttonZ);
		_buttonCache.set('buttonExtra', buttonExtra);
		_buttonCache.set('buttonExtra2', buttonExtra2);
		_buttonCache.set('buttonExtra3', buttonExtra3);
		_buttonCache.set('buttonExtra4', buttonExtra4);
	}

	/**
	 * 性能优化：通过缓存设置按钮，减少 Reflect 使用
	 */
	private function setButtonByCache(buttonName:String, button:TouchButton):Void
	{
		Reflect.setField(this, buttonName, button);
		_buttonCache.set(buttonName, button);
	}

	public function setExtrasDefaultPos()
	{
		var extraButtons:Array<TouchButton> = [
			buttonExtra,
			buttonExtra2,
			buttonExtra3,
			buttonExtra4
		];

		if (MobileData.save.data.extraData == null)
			MobileData.save.data.extraData = new Array();

		for (i in 0...extraButtons.length)
		{
			var button = extraButtons[i];
			if (button != null)
			{
				MobileData.save.data.extraData[i] = FlxPoint.get(button.x, button.y);
			}
		}
		MobileData.save.flush();
	}

	public function setExtrasPos()
	{
		var extraButtons:Array<TouchButton> = [
			buttonExtra,
			buttonExtra2,
			buttonExtra3,
			buttonExtra4
		];

		if (MobileData.save.data.extraData == null)
			setExtrasDefaultPos();

		for (i in 0...extraButtons.length)
		{
			var button = extraButtons[i];
			if (button != null)
			{
				if (MobileData.save.data.extraData.length <= i)
					setExtrasDefaultPos();
				var point = MobileData.save.data.extraData[i];
				// 无效/越界/原点位置视为历史脏数据：保留 createButton 生成的默认（底部）位置，
				// 避免额外键被历史错误值钉在左上角
				if (point != null && (point.x != 0 || point.y != 0)
					&& point.x >= 0 && point.x < FlxG.width
					&& point.y >= 0 && point.y < FlxG.height)
				{
					button.x = point.x;
					button.y = point.y;
				}
			}
		}
	}

	public function createButton(X:Float, Y:Float, Graphic:String, ?Color:FlxColor = 0xFFFFFF, ?IDs:Array<MobileInputID>):TouchButton
	{
		var button = new TouchButton(X, Y, IDs);
		button.label = new FlxSprite();
		button.loadGraphic(Paths.image('touchpad/bg', "mobile"));
		button.label.loadGraphic(Paths.image('touchpad/${Graphic.toUpperCase()}', "mobile"));

		button.scale.set(0.243, 0.243);
		button.updateHitbox();
		button.updateLabelPosition();

		button.statusBrightness = [1, 0.8, 0.4];
		button.statusIndicatorType = BRIGHTNESS;
		button.indicateStatus();

		button.bounds.makeGraphic(Std.int(button.width - 50), Std.int(button.height - 50), FlxColor.TRANSPARENT);
		button.centerBounds();

		button.immovable = true;
		button.solid = button.moves = false;
		button.label.antialiasing = button.antialiasing = ClientPrefs.data.antialiasing;
		button.tag = Graphic.toUpperCase();
		button.color = Color;
		button.parentAlpha = button.alpha;

		button.onDown.callback = () -> onButtonDown.dispatch(button);
		button.onOut.callback = button.onUp.callback = () -> onButtonUp.dispatch(button);
		return button;
	}

	override function set_alpha(Value):Float
	{
		forEachAlive((button:TouchButton) -> button.parentAlpha = Value);
		return super.set_alpha(Value);
	}
}
