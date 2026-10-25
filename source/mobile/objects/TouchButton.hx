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

import flixel.input.FlxInput;
import flixel.input.FlxPointer;
import flixel.input.IFlxInput;
import flixel.util.FlxDestroyUtil.IFlxDestroyable;
#if mac
import flixel.input.mouse.FlxMouseButton;
#end

/**
 * A simple button class that calls a function when clicked by the touch.
 * @author: Karim Akra and Homura Akemi (HomuHomu833)
 */
class TouchButton extends TypedTouchButton<FlxSprite>
{
	/**
	 * Used with public variable status, means not highlighted or pressed.
	 */
	public static inline var NORMAL:Int = 0;

	/**
	 * Used with public variable status, means highlighted (usually from touch over).
	 */
	public static inline var HIGHLIGHT:Int = 1;

	/**
	 * Used with public variable status, means pressed (usually from touch click).
	 */
	public static inline var PRESSED:Int = 2;

	/**
	 * A simple tag that returns the button's graphic name in upper case.
	**/
	public var tag:String;

	/**
	 * The `MobileInputID` that are assigned to this button.
	**/
	public var IDs:Array<MobileInputID> = [];

	/**
	 * A Small invisible bounds used for colision
	**/
	public var bounds:FlxSprite = new FlxSprite();

	/**
	 * Creates a new `TouchButton` object
	 * and a callback function on the UI thread.
	 *
	 * @param   X         The x position of the button.
	 * @param   Y         The y position of the button.
	 * @param   IDs        The button's IDs(used for input handling so be careful).
	 */
	public function new(X:Float = 0, Y:Float = 0, ?IDs:Array<MobileInputID> = null):Void
	{
		super(X, Y);

		this.IDs = IDs == null ? [] : IDs;
	}

	public inline function centerInBounds()
	{
		setPosition(bounds.x + ((bounds.width - frameWidth) / 2), bounds.y + ((bounds.height - frameHeight) / 2));
	}

	public inline function centerBounds()
	{
		bounds.setPosition(x + ((frameWidth - bounds.width) / 2), y + ((frameHeight - bounds.height) / 2));
	}
}

/**
 * A simple button class that calls a function when clicked by the touch.
 */
#if !display
@:generic
#end
class TypedTouchButton<T:FlxSprite> extends FlxSprite implements IFlxInput
{
	/**
	 * The label that appears on the button. Can be any `FlxSprite`.
	 */
	public var label(default, set):T;

	/**
	 * Whether you can press the button simply by releasing the touch button over it (default).
	 * If false, the input has to be pressed while hovering over the button.
	 */
	public var allowSwiping:Bool = true;

	/**
	 * Whether the button can use multiple fingers on it.
	 */
	public var multiTouch:Bool = false;

	/**
	 * Maximum distance a pointer can move to still trigger event handlers.
	 * If it moves beyond this limit, onOut is triggered.
	 * Defaults to `Math.POSITIVE_INFINITY` (i.e. no limit).
	 */
	public var maxInputMovement:Float = Math.POSITIVE_INFINITY;

	/**
	 * The properties of this button's `onUp` event (callback function, sound).
	 */
	public var onUp(default, null):TouchButtonEvent;

	/**
	 * The properties of this button's `onDown` event (callback function, sound).
	 */
	public var onDown(default, null):TouchButtonEvent;

	/**
	 * The properties of this button's `onOver` event (callback function, sound).
	 */
	public var onOver(default, null):TouchButtonEvent;

	/**
	 * The properties of this button's `onOut` event (callback function, sound).
	 */
	public var onOut(default, null):TouchButtonEvent;

	/**
	 * Shows the current state of the button, either `TouchButton.NORMAL`,
	 * `TouchButton.HIGHLIGHT` or `TouchButton.PRESSED`.
	 */
	public var status(default, set):Int;

	/**
	 * The alpha's the button should use depednging on the status.
	**/
	public var statusAlphas:Array<Float> = [1.0, 1.0, 0.6];

	/**
	 * The brightness the button should use depednging on the status.
	**/
	public var statusBrightness:Array<Float> = [1.0, 0.95, 0.7];

	/**
	 * How much to add/substract from the current indicator value for the label.
	**/
	public var labelStatusDiff:Float = 0.05;

	/**
	 * IF YOU'RE USING SPRITE GROUPS YOU MUST SET THIS TO THE GROUP'S ALPHA LIKE IN TouchPad.
	**/
	public var parentAlpha(default, set):Float = 1;

	public var statusIndicatorType(default, set):StatusIndicators = ALPHA;

	public var brightShader:ButtonBrightnessShader = new ButtonBrightnessShader();

	public var justReleased(get, never):Bool;
	public var released(get, never):Bool;
	public var pressed(get, never):Bool;
	public var justPressed(get, never):Bool;

	/**
	 * We cast label to a `FlxSprite` for internal operations to avoid Dynamic casts in C++
	 */
	var _spriteLabel:FlxSprite;

	/**
	 * We don't need an ID here, so let's just use `Int` as the type.
	 */
	var input:FlxInput<Int>;

	/**
	 * The input currently pressing this button, if none, it's `null`. Needed to check for its release.
	 */
	var currentInput:IFlxInput;

	/**
	 * 本帧检测到的、仍按在按钮上的任意触摸（用于多指场景下判断是否可以真正松开）。
	 */
	var _pressedOverlapInput:IFlxInput = null;

	public var canChangeLabelAlpha:Bool = true;

	/**
	 * 为 true 时，图标/字母保持自身颜色（不与底板同色）。
	 * 默认 false：字母颜色跟随底板，并在 BRIGHTNESS 模式下一起被亮度 shader 提亮，
	 * 以保持「字母与底板同色或偏亮」的传统观感（如默认 dpad/hitbox/extra）。
	 * 仅需要独立配色的按钮（如暂停键的浅蓝 P）才置为 true。
	 */
	public var independentLabelColor:Bool = false;

	/**
	 * Creates a new `FlxTypedButton` object with a gray background.
	 *
	 * @param   X         The x position of the button.
	 * @param   Y         The y position of the button.
	 */
	public function new(X:Float = 0, Y:Float = 0):Void
	{
		super(X, Y);

		if (statusIndicatorType == BRIGHTNESS)
			shader = brightShader;

		onUp = new TouchButtonEvent();
		onDown = new TouchButtonEvent();
		onOver = new TouchButtonEvent();
		onOut = new TouchButtonEvent();

		status = multiTouch ? TouchButton.NORMAL : TouchButton.HIGHLIGHT;

		// Since this is a UI element, the default scrollFactor is (0, 0)
		scrollFactor.set();

		input = new FlxInput(0);
	}

	/**
	 * Called by the game state when state is changed (if this object belongs to the state)
	 */
	override public function destroy():Void
	{
		label = FlxDestroyUtil.destroy(label);
		_spriteLabel = null;

		onUp = FlxDestroyUtil.destroy(onUp);
		onDown = FlxDestroyUtil.destroy(onDown);
		onOver = FlxDestroyUtil.destroy(onOver);
		onOut = FlxDestroyUtil.destroy(onOut);

		currentInput = null;
		input = null;

		super.destroy();
	}

	/**
	 * Called by the game loop automatically, handles touch over and click detection.
	 */
	override public function update(elapsed:Float):Void
	{
		super.update(elapsed);

		// 性能优化：只在可见且存在活动触摸时检测
		if (visible && FlxG.touches.list.length > 0)
		{
			// Update the button, but only if at least either touches are enabled
			#if FLX_POINTER_INPUT
			updateButton();
			#end
		}

		input.update();
	}

	/**
	 * Just draws the button graphic and text label to the screen.
	 */
	override public function draw():Void
	{
		super.draw();

		if (_spriteLabel != null && _spriteLabel.graphic != null && _spriteLabel.pixels != null && _spriteLabel.visible)
		{
			if (_spriteLabel.cameras != cameras)
				_spriteLabel.cameras = cameras;
			_spriteLabel.draw();
		}
	}

	#if FLX_DEBUG
	/**
	 * Helper function to draw the debug graphic for the label as well.
	 */
	override public function drawDebug():Void
	{
		super.drawDebug();

		if (_spriteLabel != null)
			_spriteLabel.drawDebug();
	}
	#end

	/**
	 * Basic button update logic - searches for overlaps with touches and
	 * the touch and calls `updateStatus()`.
	 */
	function updateButton():Void
	{
		var overlapFound = checkTouchOverlap();
		var tempCurrentInput = currentInput; // 保存临时保存临时currentInput

		if (tempCurrentInput != null && tempCurrentInput.justReleased)
		{
			// 同一按钮上还有其它手指保持按住时，把当前输入切换到那根手指，
			// 避免误判松手（多指操作时会导致长条断连）
			if (_pressedOverlapInput != null && _pressedOverlapInput != tempCurrentInput)
			{
				currentInput = _pressedOverlapInput;
			}
			else if (overlapFound)
			{
				onUpHandler();
			}
			else
			{
				onOutHandler();
			}
		}
		else if (status == TouchButton.PRESSED)
		{
			if (!overlapFound)
			{
				// 正在触摸但已离开 hitbox 范围
				onOutHandler();
			}
		}
		else if (status == TouchButton.HIGHLIGHT && !overlapFound)
		{
			// 仅高亮（从未按下）时离开按钮：静默恢复，不触发 onOut/onUp。
			// 否则触摸出现的第一帧会向 PlayState 误发 keyReleased。
			status = TouchButton.NORMAL;
		}
	}

	/**
	 * 性能优化：缓存触摸点位置以减少重复计算
	 */
	function checkTouchOverlap():Bool
	{
		var overlap = false;
		_pressedOverlapInput = null;

		// cameras 在对象尚未加入任何状态、或状态正在销毁时可能为 null
		if (cameras == null)
			return false;

		// 性能优化：优先使用第一个摄像头（大多数情况下只有一个）
		for (camera in cameras)
		{
			// 防御性检查：摄像头可能为 null 或已被销毁（切换状态时残留），
			// 直接传给 FlxPointer.getWorldPosition 会触发空引用崩溃
			if (camera == null || camera.flashSprite == null)
				continue;

			#if mac
			var button = FlxMouseButton.getByID(FlxMouseButtonID.LEFT);
			if (checkInput(FlxG.mouse, button, button.justPressedPosition, camera))
			{
				overlap = true;
			}
			#else
			// 性能优化：提前检查是否有触摸点
			var touches = FlxG.touches.list;
			if (touches.length == 0)
				break;

			for (touch in touches)
			{
				if (checkInput(touch, touch, touch.justPressedPosition, camera))
				{
					overlap = true;
				}
			}
			#end

			// 性能优化：找到重叠后立即返回
			if (overlap)
				break;
		}

		return overlap;
	}

	function checkInput(pointer:FlxPointer, input:IFlxInput, justPressedPosition:FlxPoint, camera:FlxCamera):Bool
	{
		if (pointer == null || camera == null)
			return false;

		var overlaps = overlapsPoint(pointer.getWorldPosition(camera, _point), true, camera);

		if (maxInputMovement != Math.POSITIVE_INFINITY
			&& justPressedPosition != null
			&& justPressedPosition.distanceTo(pointer.getScreenPosition(FlxPoint.weak())) > maxInputMovement
			&& input == currentInput)
		{
			currentInput = null;
		}
		else if (overlaps)
		{
			// 记录仍按住的触摸，供 updateButton 在多指场景下做按住归属切换
			if (input.pressed)
				_pressedOverlapInput = input;

			updateStatus(input);
			
			// 如果是首次按下或者允许滑动，并且没有 currentInput，设置 currentInput
			if (currentInput == null && input.pressed)
			{
				currentInput = input;
			}
			return true;
		}

		return false;
	}

	/**
	 * Updates the button status by calling the respective event handler function.
	 */
	function updateStatus(input:IFlxInput):Void
	{
		if (input.justPressed)
		{
			// 已经按下时不重复触发 onDown：同一按钮上的第二根手指会导致重复 keyPressed
			if (status == TouchButton.PRESSED)
				return;

			currentInput = input;
			onDownHandler();
		}
		else if (status == TouchButton.NORMAL)
		{
			// Allow 'swiping' to press a button (dragging it over the button while pressed)
			if (allowSwiping && input.pressed)
			{
				// 滑动进入时设置 currentInput
				if (currentInput == null)
				{
					currentInput = input;
				}
				onDownHandler();
			}
			else
			{
				onOverHandler();
			}
		}
	}

	function updateLabelPosition()
	{
		if (_spriteLabel != null)
		{
			_spriteLabel.x = ((width - _spriteLabel.width) / 2) + (pixelPerfectPosition ? Math.floor(x) : x);
			_spriteLabel.y = ((height - _spriteLabel.height) / 2) + (pixelPerfectPosition ? Math.floor(y) : y);
		}
	}

	function updateLabelScale()
	{
		if (_spriteLabel != null)
			_spriteLabel.scale.set(scale.x, scale.y);
	}

	/**
	 * 重新缩放并居中标签（供外部在改完 scale 后手动调用）。
	 */
	public function refreshLabel():Void
	{
		updateLabelScale();
		updateLabelPosition();
	}

	function indicateStatus()
	{
		switch (statusIndicatorType)
		{
			case ALPHA:
				alpha = statusAlphas[status];
			case BRIGHTNESS:
				brightShader.brightness.value = [statusBrightness[status]];
			case NONE: // no balls
		}
	}

	/**
	 * Internal function that handles the onUp event.
	 */
	function onUpHandler():Void
	{
		status = TouchButton.NORMAL;
		input.release();
		currentInput = null;
		onUp.fire(); // Order matters here, because onUp.fire() could cause a state change and destroy this object.
	}

	/**
	 * Internal function that handles the onDown event.
	 */
	function onDownHandler():Void
	{
		status = TouchButton.PRESSED;
		input.press();
		onDown.fire(); // Order matters here, because onDown.fire() could cause a state change and destroy this object.
	}

	/**
	 * Internal function that handles the onOver event.
	 */
	function onOverHandler():Void
	{
		status = TouchButton.HIGHLIGHT;
		onOver.fire(); // Order matters here, because onOver.fire() could cause a state change and destroy this object.
	}

	/**
	 * Internal function that handles the onOut event.
	 */
	function onOutHandler():Void
	{
		status = TouchButton.NORMAL;
		input.release();
		currentInput = null;
		onOut.fire(); // Order matters here, because onOut.fire() could cause a state change and destroy this object.
	}

	function set_label(Value:T):T
	{
		if (Value != null)
		{
			// use the same FlxPoint object for both
			Value.scrollFactor.put();
			Value.scrollFactor = scrollFactor;
		}

		label = Value;
		_spriteLabel = label;

		updateLabelPosition();

		// 非独立配色时，字母应与底板同色/偏亮（传统观感）。
		if (!independentLabelColor && statusIndicatorType == BRIGHTNESS && _spriteLabel != null)
			_spriteLabel.shader = brightShader;

		return Value;
	}

	function set_status(Value:Int):Int
	{
		status = Value;
		indicateStatus();
		return status;
	}

	override function set_alpha(Value:Float):Float
	{
		super.set_alpha(Value);
		if (_spriteLabel != null && canChangeLabelAlpha)
			_spriteLabel.alpha = alpha == 0 ? 0 : alpha + labelStatusDiff;
		return Value;
	}

	override function set_visible(Value:Bool):Bool
	{
		super.set_visible(Value);
		if (_spriteLabel != null)
			_spriteLabel.visible = Value;
		return Value;
	}

	override function set_x(Value:Float):Float
	{
		super.set_x(Value);
		updateLabelPosition();
		return x;
	}

	override function set_y(Value:Float):Float
	{
		super.set_y(Value);
		updateLabelPosition();
		return y;
	}

	override function set_color(Value:FlxColor):Int
	{
		// 非独立配色时，字母颜色跟随底板，保持「与底板同色/偏亮」的传统观感。
		if (!independentLabelColor && _spriteLabel != null)
			_spriteLabel.color = Value;
		brightShader.color = Value;
		super.set_color(Value);
		return Value;
	}

	override private function set_width(Value:Float)
	{
		super.set_width(Value);
		updateLabelScale();
		return Value;
	}

	override private function set_height(Value:Float)
	{
		super.set_height(Value);
		updateLabelScale();
		return Value;
	}

	override public function updateHitbox()
	{
		super.updateHitbox();
		if (_spriteLabel != null)
			_spriteLabel.updateHitbox();
	}

	function set_parentAlpha(Value:Float):Float
	{
		statusAlphas = [
			Value,
			Value - 0.05,
			(parentAlpha - 0.45 == 0 && parentAlpha > 0)
			? 0.25 : parentAlpha - 0.45
		];
		indicateStatus();
		return parentAlpha = Value;
	}

	function set_statusIndicatorType(Value:StatusIndicators)
	{
		if (Value == BRIGHTNESS)
		{
			shader = brightShader;
			// 非独立配色时字母也套亮度 shader，与底板一起被提亮（传统观感）。
			if (_spriteLabel != null)
				_spriteLabel.shader = independentLabelColor ? null : brightShader;
		}
		else
		{
			shader = null;
			if (_spriteLabel != null)
				_spriteLabel.shader = null;
		}
		statusIndicatorType = Value;
		return Value;
	}

	inline function get_justReleased():Bool
		return input.justReleased;

	inline function get_released():Bool
		return input.released;

	inline function get_pressed():Bool
		return input.pressed;

	inline function get_justPressed():Bool
		return input.justPressed;
}

/** 
 * Helper function for `TouchButton` which handles its events.
 */
private class TouchButtonEvent implements IFlxDestroyable
{
	/**
	 * The callback function to call when this even fires.
	 */
	public var callback:Void->Void;

	#if FLX_SOUND_SYSTEM
	/**
	 * The sound to play when this event fires.
	 */
	public var sound:FlxSound;
	#end

	/**
	 * @param   Callback   The callback function to call when this even fires.
	 * @param   sound      The sound to play when this event fires.
	 */
	public function new(?Callback:Void->Void, ?sound:FlxSound):Void
	{
		callback = Callback;

		#if FLX_SOUND_SYSTEM
		this.sound = sound;
		#end
	}

	/**
	 * Cleans up memory.
	 */
	public inline function destroy():Void
	{
		callback = null;

		#if FLX_SOUND_SYSTEM
		sound = FlxDestroyUtil.destroy(sound);
		#end
	}

	/**
	 * Fires this event (calls the callback and plays the sound)
	 */
	public inline function fire():Void
	{
		if (callback != null)
			callback();

		#if FLX_SOUND_SYSTEM
		if (sound != null)
			sound.play(true);
		#end
	}
}

class ButtonBrightnessShader extends FlxShader
{
	public var color(default, set):Null<FlxColor> = FlxColor.WHITE;

	@:glFragmentSource('
		#pragma header

		uniform float brightness;

		void main()
		{
			vec4 col = flixel_texture2D(bitmap, openfl_TextureCoordv);
			col.rgb *= brightness;

			gl_FragColor = col;
		}
	')
	public function new()
	{
		super();
	}

	private function set_color(?laColor:FlxColor)
	{
		if (laColor == null)
		{
			colorMultiplier.value = [1, 1, 1, 1];
			hasColorTransform.value = hasTransform.value = [false];
			return color = laColor;
		}
		hasColorTransform.value = hasTransform.value = [true];
		colorMultiplier.value = [laColor.redFloat, laColor.blueFloat, laColor.greenFloat, laColor.alphaFloat];
		return color = laColor;
	}
}

enum StatusIndicators
{
	// isn't very good looking
	ALPHA;
	// best one in my opinion
	BRIGHTNESS;
	// used when u make ur own status indicator like in hitbox
	NONE;
}
