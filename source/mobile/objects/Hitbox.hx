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

import openfl.display.BitmapData;
import openfl.display.Shape;
import flixel.graphics.FlxGraphic;
import flixel.util.FlxSignal.FlxTypedSignal;
import openfl.geom.Matrix;
import states.PlayState;
import backend.ExtraKeysHandler;

/**
 * A zone with 4 hint's (A hitbox).
 * It's really easy to customize the layout.
 *
 * @author: Karim Akra and Homura Akemi (HomuHomu833)
 */
class Hitbox extends MobileInputManager implements IMobileControls
{
	final offsetFir:Int = (ClientPrefs.data.hitboxPos ? Std.int(FlxG.height / 4) * 3 : 0);
	final offsetSec:Int = (ClientPrefs.data.hitboxPos ? 0 : Std.int(FlxG.height / 4));

	public var buttonLeft:TouchButton = new TouchButton(0, 0, [MobileInputID.HITBOX_LEFT, MobileInputID.NOTE_LEFT]);
	public var buttonDown:TouchButton = new TouchButton(0, 0, [MobileInputID.HITBOX_DOWN, MobileInputID.NOTE_DOWN]);
	public var buttonUp:TouchButton = new TouchButton(0, 0, [MobileInputID.HITBOX_UP, MobileInputID.NOTE_UP]);
	public var buttonRight:TouchButton = new TouchButton(0, 0, [MobileInputID.HITBOX_RIGHT, MobileInputID.NOTE_RIGHT]);
	public var buttonExtra:TouchButton = new TouchButton(0, 0, [MobileInputID.EXTRA_1]);
	public var buttonExtra2:TouchButton = new TouchButton(0, 0, [MobileInputID.EXTRA_2]);
	public var buttonExtra3:TouchButton = new TouchButton(0, 0, [MobileInputID.EXTRA_3]);
	public var buttonExtra4:TouchButton = new TouchButton(0, 0, [MobileInputID.EXTRA_4]);

	// Extra Keys：多键谱面动态生成的第 5 列及以后音符按钮（不入字段，需手动管理生命周期）
	public var dynamicNoteButtons:Array<TouchButton> = [];

	public var instance:MobileInputManager;
	public var onButtonDown:FlxTypedSignal<TouchButton->Void> = new FlxTypedSignal<TouchButton->Void>();
	public var onButtonUp:FlxTypedSignal<TouchButton->Void> = new FlxTypedSignal<TouchButton->Void>();

	var storedButtonsIDs:Map<String, Array<MobileInputID>> = new Map<String, Array<MobileInputID>>();

	// 性能优化：动画状态缓存
	var _animatingButtons:Map<TouchButton, Bool> = new Map<TouchButton, Bool>();
	var _targetAlphas:Map<TouchButton, Float> = new Map<TouchButton, Float>();
	var _targetLabelAlphas:Map<TouchButton, Float> = new Map<TouchButton, Float>();
	var _animationSpeed:Float = 0.1; // lerp 速度

	/**
	 * Create the zone.
	 */
	public function new(?extraMode:ExtraActions = ZERO)
	{
		super();

		for (button in Reflect.fields(this))
		{
			var field = Reflect.field(this, button);
			if (Std.isOfType(field, TouchButton))
				storedButtonsIDs.set(button, Reflect.getProperty(field, 'IDs'));
		}

		var count:Int = 0;
		switch (extraMode)
		{
			case ONE: count = 1;
			case TWO: count = 2;
			case THREE: count = 3;
			case FOUR: count = 4;
			default: count = 0;
		}

		// Extra Keys：当前谱面档位/键数（touchLaneMode='4k' 时强制 4 键；谱面未加载时 4 键）
		var mania:Null<Int> = (PlayState.SONG != null) ? PlayState.SONG.mania : null;
		var totalCols:Int = 4;
		if (ClientPrefs.data.touchLaneMode != '4k' && PlayState.SONG != null)
			totalCols = ((mania != null) ? mania : 3) + 1;
		var maniaIdx:Int = (mania != null) ? mania : 3;

		// 标准 4 键且无额外键：轨道占满全屏高度；其余情况（含额外键 / 多键谱面）占上方 3/4
		if (count == 0 && totalCols <= 4)
			createLaneHints(4, maniaIdx, 0, FlxG.height);
		else
			createLaneHints(totalCols, maniaIdx, offsetSec, Std.int(FlxG.height / 4) * 3);

		if (count > 0)
		{
			// 顶部 1/4 区域等分为 count 个额外键
			var extraColors:Array<Int> = [0xFF0066FF, 0xA6FF00, 0xFF00A6FF, 0xFFFFA600];
			for (i in 0...count)
			{
				var zoneW:Int = Std.int(FlxG.width / count);
				var btn:TouchButton = createHint(i * zoneW, offsetFir, zoneW, Std.int(FlxG.height / 4), extraColors[i]);
				switch (i)
				{
					case 0: buttonExtra = btn;
					case 1: buttonExtra2 = btn;
					case 2: buttonExtra3 = btn;
					default: buttonExtra4 = btn;
				}
				add(btn);
			}
		}

		for (button in Reflect.fields(this))
		{
			if (Std.isOfType(Reflect.field(this, button), TouchButton))
				Reflect.setProperty(Reflect.getProperty(this, button), 'IDs', storedButtonsIDs.get(button));
		}

		storedButtonsIDs.clear();
		scrollFactor.set();
		updateTrackedButtons();

		instance = this;
	}

	/**
	 * Extra Keys：生成音符轨道按钮。
	 * 4 键等分四列；多键谱面按键数等分，每列映射 NOTE_X 枚举并记录动态按钮。
	 * 颜色统一取自 getLaneColor，跟随游戏内箭头 RGB。
	 */
	function createLaneHints(totalCols:Int, maniaIdx:Int, y:Float, h:Int):Void
	{
		if (totalCols <= 4)
		{
			var zoneW:Int = Std.int(FlxG.width / 4);
			add(buttonLeft = createHint(0, y, zoneW, h, getLaneColor(0, maniaIdx)));
			add(buttonDown = createHint(zoneW, y, zoneW, h, getLaneColor(1, maniaIdx)));
			add(buttonUp = createHint(zoneW * 2, y, zoneW, h, getLaneColor(2, maniaIdx)));
			add(buttonRight = createHint(zoneW * 3, y, zoneW, h, getLaneColor(3, maniaIdx)));
			return;
		}

		var zoneW:Int = Std.int(FlxG.width / totalCols);
		for (i in 0...totalCols)
		{
			var btn:TouchButton = createHint(i * zoneW, y, zoneW, h, getLaneColor(i, maniaIdx));
			btn.IDs = [noteIDForIndex(i)];
			if (i < 4)
			{
				// 前 4 列复用标准字段（兼容原有 hitbox 字段引用）
				switch (i)
				{
					case 0: buttonLeft = btn;
					case 1: buttonDown = btn;
					case 2: buttonUp = btn;
					default: buttonRight = btn;
				}
			}
			else
			{
				dynamicNoteButtons.push(btn);
			}
			add(btn);
		}
	}

	/**
	 * Extra Keys：按列取箭头配色，使 Hitbox 各列颜色与游戏内箭头一致。
	 * 索引与 Note/StrumNote 同源：arrowRGB[globalIndex(mania, column)][0]（多键下列索引 != 样式索引）。
	 * 像素舞台优先 arrowRGBPixel；dynamicColors 关闭时用出厂色表；越界回退 EK 全局色表。
	 * HSV 模式：箭头实际显示为「贴图原色 + H/S/B 偏移」，这里用 arrowRGB 底色套用同一套偏移近似。
	 */
	static function getLaneColor(column:Int, mania:Int):Int
	{
		var cfg = ClientPrefs.data.dynamicColors ? ClientPrefs.data : ClientPrefs.defaultData;
		var style:Int = column;
		if (ExtraKeysHandler.instance != null && ExtraKeysHandler.instance.data != null)
			style = ExtraKeysHandler.instance.globalIndex(mania, column);

		var arr:Array<FlxColor> = null;
		if (cfg != null && cfg.arrowRGB != null && style > -1 && style < cfg.arrowRGB.length)
			arr = cfg.arrowRGB[style];
		if (PlayState.isPixelStage && cfg != null && cfg.arrowRGBPixel != null && style > -1 && style < cfg.arrowRGBPixel.length)
			arr = cfg.arrowRGBPixel[style];

		var base:Int = 0xFF999999;
		if (arr != null && arr.length > 0)
			base = arr[0];
		else
		{
			var ek = (ExtraKeysHandler.instance != null) ? ExtraKeysHandler.instance.data : null;
			if (ek != null && ek.colors != null && style > -1 && style < ek.colors.length)
			{
				var c = ek.colors[style];
				if (c != null && c.inner != null)
					base = FlxColor.fromString('#' + c.inner);
			}
		}

		if (ClientPrefs.data.arrowColorMode == 'HSV')
			base = applyArrowHSV(base, style);
		return base;
	}

	/**
	 * 与 ColorSwap 着色器同样的 HSV 偏移：色相相加、饱和度相加后 clamp、亮度相乘。
	 * 偏移值取自 arrowHSV[style]（H 为度数，S/B 为 -100..100 的百分比）。
	 */
	static function applyArrowHSV(color:Int, style:Int):Int
	{
		var arr:Array<Int> = null;
		if (ClientPrefs.data.arrowHSV != null && style > -1 && style < ClientPrefs.data.arrowHSV.length)
			arr = ClientPrefs.data.arrowHSV[style];
		if (arr == null || (arr[0] == 0 && arr[1] == 0 && arr[2] == 0))
			return color;

		var c = new FlxColor(color);
		var hue:Float = (c.hue + arr[0]) % 360;
		if (hue < 0)
			hue += 360;
		var sat:Float = FlxMath.bound(c.saturation + arr[1] / 100, 0, 1);
		var bri:Float = FlxMath.bound(c.brightness * (1 + arr[2] / 100), 0, 1);
		return FlxColor.fromHSB(hue, sat, bri);
	}

	/** 音符列索引 -> 触屏 NOTE 枚举值（0..3 -> NOTE_LEFT..NOTE_RIGHT，4..17 -> NOTE_4..NOTE_17） */
	static function noteIDForIndex(index:Int):MobileInputID
	{
		return switch (index)
		{
			case 0: MobileInputID.NOTE_LEFT;
			case 1: MobileInputID.NOTE_DOWN;
			case 2: MobileInputID.NOTE_UP;
			case 3: MobileInputID.NOTE_RIGHT;
			case 4: MobileInputID.NOTE_4;
			case 5: MobileInputID.NOTE_5;
			case 6: MobileInputID.NOTE_6;
			case 7: MobileInputID.NOTE_7;
			case 8: MobileInputID.NOTE_8;
			case 9: MobileInputID.NOTE_9;
			case 10: MobileInputID.NOTE_10;
			case 11: MobileInputID.NOTE_11;
			case 12: MobileInputID.NOTE_12;
			case 13: MobileInputID.NOTE_13;
			case 14: MobileInputID.NOTE_14;
			case 15: MobileInputID.NOTE_15;
			case 16: MobileInputID.NOTE_16;
			default: MobileInputID.NOTE_17;
		}
	}

	/**
	 * Clean up memory.
	 */
	override function destroy()
	{
		super.destroy();
		onButtonUp.destroy();
		onButtonDown.destroy();

		_animatingButtons.clear();
		_targetAlphas.clear();
		_targetLabelAlphas.clear();

		// Extra Keys：动态多键按钮不在字段里，手动销毁
		for (btn in dynamicNoteButtons)
		{
			if (btn != null && btn.exists)
				FlxDestroyUtil.destroy(btn);
		}
		dynamicNoteButtons = [];

		for (fieldName in Reflect.fields(this))
		{
			var field = Reflect.field(this, fieldName);
			if (Std.isOfType(field, TouchButton))
				Reflect.setField(this, fieldName, FlxDestroyUtil.destroy(field));
		}
	}

	/**
	 * 性能优化：每帧更新动画，替代 FlxTween
	 */
	override public function update(elapsed:Float):Void
	{
		super.update(elapsed);

		// 只在动画启用时才运行动画逻辑
		if (ClientPrefs.data.hitboxAnimation)
		{
			// 使用简单的 lerp 更新动画
			for (button in _animatingButtons.keys())
			{
				if (!button.active || !button.exists)
					continue;

				if (_animatingButtons.get(button))
				{
					var targetAlpha = _targetAlphas.get(button);
					var targetLabelAlpha = _targetLabelAlphas.get(button);

					// 使用 lerp 平滑过渡
					var lerpSpeed = _animationSpeed;
					button.alpha = button.alpha + (targetAlpha - button.alpha) * lerpSpeed;

					if (button.label != null)
						button.label.alpha = button.label.alpha + (targetLabelAlpha - button.label.alpha) * lerpSpeed;

					// 检查是否接近目标值，如果是则停止动画
					if (Math.abs(button.alpha - targetAlpha) < 0.001)
					{
						button.alpha = targetAlpha;
						if (button.label != null)
							button.label.alpha = targetLabelAlpha;
						_animatingButtons.set(button, false);
					}
				}
			}
		}
	}

	private function createHint(X:Float, Y:Float, Width:Int, Height:Int, Color:Int = 0xFFFFFF):TouchButton
	{
		var hint = new TouchButton(X, Y);
		hint.statusAlphas = [];
		hint.statusIndicatorType = NONE;
		hint.loadGraphic(createHintGraphic(Width, Height));

		hint.label = new FlxSprite();
		hint.labelStatusDiff = (ClientPrefs.data.hitboxType != "Hidden") ? ClientPrefs.data.controlsAlpha : 0.00001;
		hint.label.loadGraphic(createHintGraphic(Width, Math.floor(Height * 0.035), true));
		if (ClientPrefs.data.hitboxPos)
			hint.label.offset.y -= (hint.height - hint.label.height) / 2;
		else
			hint.label.offset.y += (hint.height - hint.label.height) / 2;

		if (ClientPrefs.data.hitboxType != "Hidden")
		{
			if (ClientPrefs.data.hitboxAnimation)
			{
				// 性能优化：初始化动画状态
				_animatingButtons.set(hint, false);
				_targetAlphas.set(hint, ClientPrefs.data.hitboxHideIdle ? 0 : 0.00001);
				_targetLabelAlphas.set(hint, ClientPrefs.data.hitboxHideIdle ? 0 : ClientPrefs.data.controlsAlpha);

				hint.onDown.callback = function()
				{
					onButtonDown.dispatch(hint);
					// 性能优化：设置目标 alpha 值，由 update 循环中的 lerp 处理
					_targetAlphas.set(hint, ClientPrefs.data.controlsAlpha);
					_targetLabelAlphas.set(hint, 0.00001);
					_animatingButtons.set(hint, true);
				}

				hint.onOut.callback = hint.onUp.callback = function()
				{
					onButtonUp.dispatch(hint);
					// 性能优化：设置目标 alpha 值，由 update 循环中的 lerp 处理
					_targetAlphas.set(hint, ClientPrefs.data.hitboxHideIdle ? 0 : 0.00001);
					_targetLabelAlphas.set(hint, ClientPrefs.data.hitboxHideIdle ? 0 : ClientPrefs.data.controlsAlpha);
					_animatingButtons.set(hint, true);
				}
			}
			else
			{
				// 禁用动画模式：直接设置 alpha
				hint.alpha = ClientPrefs.data.hitboxHideIdle ? 0 : 0.00001;
				hint.label.alpha = ClientPrefs.data.hitboxHideIdle ? 0 : ClientPrefs.data.controlsAlpha;

				hint.onDown.callback = function()
				{
					onButtonDown.dispatch(hint);
					// 直接设置，无动画
					hint.alpha = ClientPrefs.data.controlsAlpha;
					hint.label.alpha = 0.00001;
				}

				hint.onOut.callback = hint.onUp.callback = function()
				{
					onButtonUp.dispatch(hint);
					// 直接设置，无动画
					hint.alpha = ClientPrefs.data.hitboxHideIdle ? 0 : 0.00001;
					hint.label.alpha = ClientPrefs.data.hitboxHideIdle ? 0 : ClientPrefs.data.controlsAlpha;
				}
			}
		}
		else
		{
			hint.onDown.callback = () -> onButtonDown.dispatch(hint);
			hint.onOut.callback = hint.onUp.callback = () -> onButtonUp.dispatch(hint);
		}

		hint.immovable = hint.multiTouch = true;
		hint.solid = hint.moves = false;
		hint.alpha = ClientPrefs.data.hitboxHideIdle ? 0 : 0.00001;
		hint.label.alpha = (ClientPrefs.data.hitboxType != "Hidden" && !ClientPrefs.data.hitboxHideIdle) ? ClientPrefs.data.controlsAlpha : 0.00001;
		hint.canChangeLabelAlpha = false;
		hint.label.antialiasing = hint.antialiasing = ClientPrefs.data.antialiasing;
		hint.color = Color;
		#if FLX_DEBUG
		hint.ignoreDrawDebug = true;
		#end
		return hint;
	}

	/**
	 * 设置界面专用：进入时按钮立即以 controlsAlpha 可见，0.6s 后渐隐回 idle 状态。
	 * 期间触摸仍可正常触发 onDown/onUp 打断渐隐循环（每次打断会重新计时）。
	 * hitboxHideIdle 为 true 时（游戏内禁用），直接进入 idle 而不显示。
	 */
	public function startFadeOut()
	{
		if (!ClientPrefs.data.hitboxAnimation)
			return;
		// hitboxHideIdle=true 时游戏内完全禁用，设置界面也应保持隐藏
		if (ClientPrefs.data.hitboxHideIdle)
		{
			forEachAllButtons(function(btn:TouchButton)
			{
				btn.alpha = 0;
				if (btn.label != null)
					btn.label.alpha = 0;
				_animatingButtons.set(btn, false);
			});
			return;
		}
		var hideAlpha:Float = 0.00001;
		forEachAllButtons(function(btn:TouchButton)
		{
			// 立即以 controlsAlpha 可见，再开始计时
			btn.alpha = ClientPrefs.data.controlsAlpha;
			if (btn.label != null)
				btn.label.alpha = ClientPrefs.data.controlsAlpha;
			_animatingButtons.set(btn, true);
			_targetAlphas.set(btn, hideAlpha);
			_targetLabelAlphas.set(btn, ClientPrefs.data.controlsAlpha);
		});
		// 0.6s 后真正开始渐隐（用 tween 延迟，不阻塞调用栈）
		FlxTween.tween(this, {}, 0.6, {
			ease: FlxEase.linear,
			onComplete: (twn:FlxTween) ->
			{
				forEachAllButtons(function(btn:TouchButton)
				{
					if (_animatingButtons.exists(btn) && _animatingButtons.get(btn))
					{
						_animatingButtons.set(btn, true);
						_targetAlphas.set(btn, hideAlpha);
						_targetLabelAlphas.set(btn, hideAlpha);
					}
				});
			}
		});
	}

	/** 遍历全部触屏按钮：字段按钮 + Extra Keys 动态多键按钮 */
	function forEachAllButtons(callback:TouchButton->Void):Void
	{
		for (fieldName in Reflect.fields(this))
		{
			var button = Reflect.field(this, fieldName);
			if (Std.isOfType(button, TouchButton))
				callback(cast button);
		}
		for (btn in dynamicNoteButtons)
		{
			if (btn != null)
				callback(btn);
		}
	}

	function createHintGraphic(Width:Int, Height:Int, ?isLane:Bool = false):FlxGraphic
	{
		var shape:Shape = new Shape();
		shape.graphics.beginFill(0xFFFFFF);

		if (ClientPrefs.data.hitboxType == "No Gradient")
		{
			var matrix:Matrix = new Matrix();
			matrix.createGradientBox(Width, Height, 0, 0, 0);

			if (isLane)
				shape.graphics.beginFill(0xFFFFFF);
			else
				shape.graphics.beginGradientFill(RADIAL, [0xFFFFFF, 0xFFFFFF], [0, 1], [60, 255], matrix, PAD, RGB, 0);
			shape.graphics.drawRect(0, 0, Width, Height);
			shape.graphics.endFill();
		}
		else if (ClientPrefs.data.hitboxType == "No Gradient (Old)")
		{
			shape.graphics.lineStyle(10, 0xFFFFFF, 1);
			shape.graphics.drawRect(0, 0, Width, Height);
			shape.graphics.endFill();
		}
		else // if (ClientPrefs.data.hitboxType == 'Gradient')
		{
			shape.graphics.lineStyle(3, 0xFFFFFF, 1);
			shape.graphics.drawRect(0, 0, Width, Height);
			shape.graphics.lineStyle(0, 0, 0);
			shape.graphics.drawRect(3, 3, Width - 6, Height - 6);
			shape.graphics.endFill();
			if (isLane)
				shape.graphics.beginFill(0xFFFFFF);
			else
				shape.graphics.beginGradientFill(RADIAL, [0xFFFFFF, FlxColor.TRANSPARENT], [1, 0], [0, 255], null, null, null, 0.5);
			shape.graphics.drawRect(3, 3, Width - 6, Height - 6);
			shape.graphics.endFill();
		}

		var bitmap:BitmapData = new BitmapData(Width, Height, true, 0);
		bitmap.draw(shape);

		return FlxG.bitmap.add(bitmap);
	}
}
