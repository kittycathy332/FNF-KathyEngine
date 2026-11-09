package backend.ui;

import flixel.FlxCamera;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.graphics.FlxGraphic;
import flixel.math.FlxMath;
import flixel.math.FlxPoint;
import openfl.display.BitmapData;
import openfl.display.GradientType;
import openfl.display.Graphics;
import openfl.display.Shape;
import openfl.geom.Matrix;

/**
 * 完全自绘、可换肤的通用按钮，不依赖 FlxButton / flixel-ui，也不需要任何外部贴图资源。
 *
 * - 纹理由 openfl Shape 矢量绘制后烘焙进一张 3 帧位图（normal / hover / pressed），
 *   圆角、渐变、玻璃光泽、内阴影、描边、投影、图标全部由 StyledButtonStyle 参数控制。
 * - 输入自己处理：鼠标 + 多点触控，对外暴露 pressed / justPressed / justReleased，
 *   用法与 FlxButton 一致。命中判定走相机的 view 坐标，支持自定义相机、zoom、
 *   任意 scrollFactor（默认 scrollFactor=0 即 HUD 层）。
 * - 换肤：改 style 的任意字段后调用 rebuild()；自定义图标可设置 iconPainter 回调，
 *   或直接把 direction 设为 NONE 得到一块纯色按钮。
 * - 手感可选：style.animatePress=true 时按下缩放做平滑补间；false 时三态仍是即时
 *   硬切换（normal / hover / pressed 三张烘焙帧），按下与聚焦反馈完整保留但没有动画。
 *
 * 性能约定：
 * - 相同 style + direction 的按钮共享同一张烘焙纹理与同一份 FlxGraphic / FlxTileFrames，
 *   不会逐实例做矢量光栅化，也不会逐实例占一份 GPU 纹理。
 * - 三态切帧直接用 animation.frameIndex，不建三个单帧动画，避免每帧跑动画控制器。
 * - 自定义 iconPainter 无法从 style 推导缓存 key：默认走独占纹理，
 *   若多个按钮用的是同一个 painter，请给它们设置相同的 cacheTag 以重新启用共享。
 *
 * 位于 backend.ui 且被 import.hx 全局导入，全项目无需写 import 即可使用。
 *
 * 示例：
 *   var st = StyledButtonStyle.darkMetal();
 *   st.cornerRadius = 6;
 *   var btn = new StyledButton(x, y, StyledButton.LEFT, st);
 *   btn.onClick = function() trace('clicked');
 *   add(btn);
 *
 *   // 纯色按钮 + 自绘图标
 *   var btn2 = new StyledButton(x, y);
 *   btn2.cacheTag = 'circle';
 *   btn2.iconPainter = function(g, size, cx, cy, state) {
 *       g.lineStyle(3, 0xFFFFFF); g.drawCircle(cx, cy, size * 0.2);
 *   };
 *   btn2.rebuild();
 */
class StyledButton extends FlxSprite
{
	/** 不绘制内置箭头（配合 iconPainter 画任意图标） */
	public static inline var NONE:Int = 0;
	public static inline var LEFT:Int = -1;
	public static inline var RIGHT:Int = 1;
	public static inline var UP:Int = -2;
	public static inline var DOWN:Int = 2;

	static inline var FRAME_NORMAL:Int = 0;
	static inline var FRAME_HOVER:Int = 1;
	static inline var FRAME_PRESSED:Int = 2;

	/** 记录本控件创建过的共享 key，供 clearCache() 精确释放；纹理本体交给 flixel 的 BitmapFrontEnd 缓存 */
	static var sharedKeys:Array<String> = [];
	static var uniqueKeyCounter:Int = 0;

	/** 纯手感字段不影响烘焙出的像素，不参与缓存 key，让外观相同仅手感不同的皮肤共用同一张纹理 */
	static var BEHAVIOR_FIELDS:Array<String> = ['animatePress', 'smoothing'];

	public var style:StyledButtonStyle;
	/** 内置箭头方向；NONE 表示不画箭头 */
	public var direction:Int;
	public var enabled:Bool = true;
	/** 命中区向四周额外扩张的像素，移动端触屏可设 4~8 */
	public var hitPadding:Float = 0;
	/** 置 false 可强制每次 rebuild 都独立烘焙（调试或一次性皮肤） */
	public var useSharedCache:Bool = true;
	/** 自定义 iconPainter 的缓存标识：不同图标必须给不同值，相同图标给相同值即可共享 */
	public var cacheTag:String = '';

	public var pressed(default, null):Bool = false;
	public var justPressed(default, null):Bool = false;
	public var justReleased(default, null):Bool = false;
	public var hovered(default, null):Bool = false;

	/** 按下 / 松开瞬间触发；持续按住请读 pressed。onClick 在按下瞬间额外触发，用法对齐项目内其它按钮 */
	public var onPress:Void->Void;
	public var onRelease:Void->Void;
	public var onClick:Void->Void;

	/** 自绘图标。为空时用内置箭头。参数：(graphics, 边长, 中心X, 中心Y, 状态帧 0/1/2) */
	public var iconPainter:Graphics->Float->Float->Float->Int->Void;

	var curFrame:Int = FRAME_NORMAL;
	var lastPressed:Bool = false;
	var viewPoint:FlxPoint = FlxPoint.get();
	var btnPoint:FlxPoint = FlxPoint.get();
	var graphicKey:String = null;
	var ownsGraphic:Bool = false;

	public function new(X:Float = 0, Y:Float = 0, Direction:Int = NONE, ?Style:StyledButtonStyle)
	{
		super(X, Y);
		direction = (Direction == LEFT || Direction == RIGHT || Direction == UP || Direction == DOWN) ? Direction : NONE;
		style = (Style != null) ? Style : StyledButtonStyle.glassBlue();
		scrollFactor.set(); // 默认 HUD 层：固定在屏幕坐标，不随相机滚动
		antialiasing = true;
		rebuild();
	}

	/** 替换样式并立即重新烘焙纹理 */
	public function setStyle(?value:StyledButtonStyle):Void
	{
		if (value != null) style = value;
		rebuild();
	}

	/**
	 * 按当前 style 重新烘焙三态纹理。运行时换肤后调用即可（不要每帧调用）。
	 * 命中共享缓存时完全跳过矢量绘制，只做一次 loadGraphic + 切帧。
	 */
	public function rebuild():Void
	{
		if (style == null) style = StyledButtonStyle.glassBlue();
		var s:Int = style.size;

		// 自定义图标且未给 tag：无法推导 key，走独占纹理，避免不同图标复用同一张图
		var sharedKey:Null<String> = computeCacheKey();
		var shared:Bool = (sharedKey != null);
		var key:String = shared ? sharedKey : 'StyledButton:unique:' + (++uniqueKeyCounter);

		// 换肤前释放上一份独占纹理；共享纹理由缓存统一管理，不能在这里销毁
		if (ownsGraphic && graphicKey != null && graphicKey != key)
			releaseExclusive(graphicKey);

		// 共享命中时完全跳过矢量绘制：flixel 的 BitmapFrontEnd 本身就是按 key 的缓存，
		// 直接用它，避免维护第二份可能不同步的 Map。
		var graph:FlxGraphic = shared ? FlxG.bitmap.get(key) : null;
		if (graph != null && graph.isDestroyed) graph = null;

		if (graph == null)
		{
			var sheet:BitmapData = bakeSheet(s);
			// unique=false：flixel 5.9 的 unique=true 会 clone 整张 BitmapData，纯属浪费
			graph = FlxG.bitmap.add(sheet, false, key);
			if (shared && graph != null && sharedKeys.indexOf(key) < 0)
				sharedKeys.push(key);
		}

		// 传 FlxGraphic（而不是 BitmapData）可绕过 findKeyForBitmap 的全缓存遍历
		loadGraphic(graph, true, s, s, false, key);
		graphicKey = key;
		ownsGraphic = !shared;
		setFrame(curFrame, true); // set_frames 会清掉动画并重置到第 0 帧，这里恢复当前状态
		// 换肤时立刻归位缩放：从带补间的主题切到无动画主题，不能留着上一次 lerp 的中间值
		if (!style.animatePress)
			applyInstantScale(curFrame == FRAME_PRESSED);
	}

	/** 生成共享缓存 key。返回 null 表示该按钮必须使用独占纹理。 */
	function computeCacheKey():Null<String>
	{
		if (!useSharedCache) return null;
		if (iconPainter != null && cacheTag.length == 0) return null;

		var fields:Array<String> = Reflect.fields(style).copy();
		fields.sort(function(a:String, b:String):Int return a < b ? -1 : (a > b ? 1 : 0));
		var sb:StringBuf = new StringBuf();
		sb.add('StyledButton|d='); sb.add(direction);
		sb.add('|tag='); sb.add(cacheTag);
		for (f in fields)
		{
			if (BEHAVIOR_FIELDS.indexOf(f) >= 0) continue;
			sb.add('|'); sb.add(f); sb.add('=');
			sb.add(Std.string(Reflect.field(style, f)));
		}
		return sb.toString();
	}

	/**
	 * 清除共享缓存记录。disposeGraphics=true 会真正释放纹理，
	 * 仅在确认没有存活按钮引用它们时调用（例如切 State 之后）。
	 * 默认 false 只清记录，纹理仍在引擎缓存里，之后的按钮会继续复用。
	 */
	public static function clearCache(disposeGraphics:Bool = false):Void
	{
		if (disposeGraphics)
		{
			for (k in sharedKeys)
				FlxG.bitmap.removeByKey(k);
		}
		sharedKeys = [];
	}

	static function releaseExclusive(key:String):Void
	{
		var g:FlxGraphic = FlxG.bitmap.get(key);
		if (g != null) FlxG.bitmap.remove(g);
	}

	/** 把三态烘焙进一张 s*3 x s 位图；复用同一个 Shape 与 Matrix，避免 3 次对象分配。 */
	function bakeSheet(s:Int):BitmapData
	{
		var sheet:BitmapData = new BitmapData(s * 3, s, true, 0x00000000);
		var shape:Shape = new Shape();
		var m:Matrix = new Matrix();
		for (i in 0...3)
		{
			renderFrame(i, shape);
			m.identity();
			m.translate(i * s, 0);
			sheet.draw(shape, m);
		}
		return sheet;
	}

	/** 在传入的 Shape 上绘制某一态（局部坐标 0..size）。state: 0 普通 / 1 悬停 / 2 按下 */
	function renderFrame(state:Int, shape:Shape):Void
	{
		var st:StyledButtonStyle = style;
		var size:Float = st.size;
		var r:Float = st.cornerRadius;
		var b:Float = st.borderThickness;
		var inner:Float = size - b * 2;
		var innerR:Float = Math.max(1, r - b);

		// 三态色调。tintBorder=false 时外描边保持恒定色（Flixel 默认皮肤的黑框不随三态变化）
		var amount:Float = (state == 1) ? st.hoverBright : (state == 2) ? -st.pressDark : 0;
		var top:Int = tint(st.topColor, amount);
		var bottom:Int = tint(st.bottomColor, amount);
		var border:Int = st.tintBorder ? tint(st.borderColor, amount) : st.borderColor;

		// 主体四段渐变：顶部白光泽 -> 顶色 -> 底色 -> 底部内阴影
		var colors:Array<Int> = [
			mix(top, 0xFFFFFF, st.glossStrength),
			top,
			bottom,
			mix(bottom, 0x000000, st.shadeStrength)
		];
		var alphas:Array<Float> = [1, 1, 1, 1];
		var ratios:Array<Int> = (st.gradientRatios != null && st.gradientRatios.length == 4)
			? st.gradientRatios : [0, 55, 200, 255];

		var g:Graphics = shape.graphics;
		g.clear();

		// 投影（alpha 为 0 时跳过绘制，Flixel 默认皮肤无投影）
		if (st.shadowAlpha > 0)
		{
			g.beginFill(0x000000, st.shadowAlpha);
			g.drawRoundRect(1, st.shadowOffsetY + 1, size - 2, size - 2 - st.shadowOffsetY, r, r);
			g.endFill();
		}

		// 外描边
		g.beginFill(rgb(border));
		g.drawRoundRect(0, 0, size, size, r, r);
		g.endFill();

		// 主体
		var grad:Matrix = new Matrix();
		grad.createGradientBox(inner, inner, Math.PI * 0.5, b, b);
		g.beginGradientFill(GradientType.LINEAR, colors, alphas, ratios, grad);
		g.drawRoundRect(b, b, inner, inner, innerR, innerR);
		g.endFill();

		// 按下反馈增强：顶部一层向下淡出的黑色渐变，做出「按进去」的内凹阴影。
		// 只在烘焙期绘制一次，运行时零开销；直角叠层适合方角皮肤（圆角皮肤请保持 alpha=0）。
		if (state == 2 && st.pressInsetAlpha > 0)
		{
			var insetH:Float = Math.max(1, size * st.pressInsetSize);
			var insetGrad:Matrix = new Matrix();
			insetGrad.createGradientBox(inner, insetH, Math.PI * 0.5, b, b);
			g.beginGradientFill(GradientType.LINEAR,
				[0x000000, 0x000000], [st.pressInsetAlpha, 0], [0, 255], insetGrad);
			g.drawRect(b, b, inner, insetH);
			g.endFill();
		}

		// 顶部内侧高光线。pressedRimTint 为负时按下态会反转成暗线，模拟 Flixel 按钮的凹陷；
		// pressedRimThickness > 0 时可只把按下态这条线加粗，常态白高光不受影响。
		var rimTint:Float = (state == 2) ? st.pressedRimTint : 0;
		var rim:Int = tint(st.rimColor, rimTint);
		var rimWidth:Float = (state == 2 && st.pressedRimThickness > 0)
			? st.pressedRimThickness : st.rimThickness;
		g.lineStyle(rimWidth, rgb(rim), st.rimAlpha, true);
		g.moveTo(b + innerR * 0.6, b + 0.5);
		g.lineTo(size - b - innerR * 0.6, b + 0.5);
		g.lineStyle(0);

		// 图标（按下态整体下沉）
		var cx:Float = size * 0.5;
		var cy:Float = size * 0.5 + (state == 2 ? st.pressOffsetY : 0);
		if (iconPainter != null)
			iconPainter(g, size, cx, cy, state);
		else if (direction != NONE)
			drawArrow(g, size, cx, cy, state);
	}

	/** 内置 V 形箭头，支持四个方向；先画一层暗色偏移做立体感 */
	function drawArrow(g:Graphics, size:Float, cx:Float, cy:Float, state:Int):Void
	{
		var st:StyledButtonStyle = style;
		var half:Float = st.arrowSize;

		// 从两臂中点指向顶点的单位向量
		var dx:Float = (direction == LEFT) ? -1 : (direction == RIGHT) ? 1 : 0;
		var dy:Float = (direction == UP) ? -1 : (direction == DOWN) ? 1 : 0;
		var tipX:Float = cx + dx * half * 0.55;
		var tipY:Float = cy + dy * half * 0.55;
		var backX:Float = cx - dx * half * 0.55;
		var backY:Float = cy - dy * half * 0.55;
		// 与 (dx,dy) 垂直的开口方向
		var px:Float = -dy * half;
		var py:Float = dx * half;

		if (st.arrowShadowAlpha > 0)
			paintChevron(g, tipX, tipY + 1.2, backX, backY + 1.2, px, py,
				st.arrowThickness + 1.2, rgb(st.arrowShadowColor), st.arrowShadowAlpha);
		paintChevron(g, tipX, tipY, backX, backY, px, py,
			st.arrowThickness, rgb(st.arrowColor), 1);
	}

	function paintChevron(g:Graphics, tipX:Float, tipY:Float, backX:Float, backY:Float,
		px:Float, py:Float, thickness:Float, color:Int, alpha:Float):Void
	{
		g.lineStyle(thickness, color, alpha, true);
		g.moveTo(backX + px, backY + py);
		g.lineTo(tipX, tipY);
		g.lineTo(backX - px, backY - py);
		g.lineStyle(0);
	}

	override public function update(elapsed:Float):Void
	{
		super.update(elapsed);

		if (!visible || !exists || !active || !enabled)
		{
			setPressed(false);
			hovered = false;
			setFrame(FRAME_NORMAL);
			animateScale(false);
			return;
		}

		// 用按钮自己所属的相机做换算：getViewPosition 给出相机内的视口坐标（含 zoom），
		// getScreenPosition 给出 x - scroll * scrollFactor，两者是同一坐标系，
		// 因此自定义相机 / 缩放 / 任意 scrollFactor 都能正确命中。
		var cam:FlxCamera = (cameras != null && cameras.length > 0) ? cameras[0] : FlxG.camera;
		getScreenPosition(btnPoint, cam);
		var bx:Float = btnPoint.x;
		var by:Float = btnPoint.y;
		var down:Bool = false;
		var over:Bool = false;

		#if FLX_MOUSE
		if (FlxG.mouse != null)
		{
			var p:FlxPoint = FlxG.mouse.getViewPosition(cam, viewPoint);
			if (hitTest(p.x, p.y, bx, by))
			{
				over = true;
				if (FlxG.mouse.pressed) down = true;
			}
		}
		#end

		#if FLX_TOUCH
		for (touch in FlxG.touches.list)
		{
			if (touch == null) continue;
			var tp:FlxPoint = touch.getViewPosition(cam, viewPoint);
			if (hitTest(tp.x, tp.y, bx, by))
			{
				over = true;
				if (touch.pressed) down = true;
			}
		}
		#end

		setPressed(down);
		hovered = over && !down;
		setFrame(down ? FRAME_PRESSED : (over ? FRAME_HOVER : FRAME_NORMAL));
		animateScale(down);
	}

	inline function hitTest(px:Float, py:Float, bx:Float, by:Float):Bool
		return px >= bx - hitPadding && px <= bx + width + hitPadding
			&& py >= by - hitPadding && py <= by + height + hitPadding;

	function setPressed(value:Bool):Void
	{
		justPressed = value && !lastPressed;
		justReleased = !value && lastPressed;
		pressed = value;
		if (justPressed)
		{
			if (onPress != null) onPress();
			if (onClick != null) onClick();
		}
		if (justReleased && onRelease != null) onRelease();
		lastPressed = value;
	}

	/** 直接切帧，不创建 FlxAnimation：animation.update() 每帧会空转，省掉三个单帧动画的开销 */
	function setFrame(frame:Int, force:Bool = false):Void
	{
		if (!force && curFrame == frame) return;
		curFrame = frame;
		animation.frameIndex = frame;
	}

	function animateScale(isDown:Bool):Void
	{
		// 无动画模式：不做任何补间，缩放直接吸附到目标值。
		// 三态外观仍由 setFrame() 即时切帧（明暗、顶部高光反转、图标下沉都在烘焙好的帧里），
		// 按下 / 聚焦的视觉反馈完整保留，只是没有逐帧的缩放回弹。
		if (!style.animatePress)
		{
			applyInstantScale(isDown);
			return;
		}

		var target:Float = isDown ? style.pressScale : 1;
		// 已经到位就停止写 scale，避免静止时每帧做 lerp + 触发矩阵重算
		if (Math.abs(scale.x - target) < 0.002)
		{
			if (scale.x != target) scale.set(target, target);
			return;
		}
		var k:Float = FlxMath.bound(style.smoothing, 0, 1);
		if (k <= 0)
			scale.set(target, target);
		else
			scale.set(FlxMath.lerp(scale.x, target, k), FlxMath.lerp(scale.y, target, k));
	}

	/** 立即把缩放设到目标值且不产生过渡；已到位时不写 scale，避免触发矩阵重算 */
	function applyInstantScale(isDown:Bool):Void
	{
		var target:Float = isDown ? style.pressScale : 1;
		if (scale.x != target || scale.y != target)
			scale.set(target, target);
	}

	override public function destroy():Void
	{
		onPress = null;
		onRelease = null;
		onClick = null;
		iconPainter = null;
		style = null;
		viewPoint = null;
		btnPoint = null;
		if (ownsGraphic && graphicKey != null)
			releaseExclusive(graphicKey);
		graphicKey = null;
		super.destroy();
	}

	/** 剥掉 alpha 字节，Graphics 的颜色参数只吃 RGB */
	static inline function rgb(color:Int):Int
		return color & 0xFFFFFF;

	/** 提亮(amount>0) / 压暗(amount<0)，返回不透明 0xFFRRGGBB */
	static function tint(color:Int, amount:Float):Int
	{
		if (amount == 0) return color;
		return amount > 0 ? mix(color, 0xFFFFFF, amount) : mix(color, 0x000000, -amount);
	}

	static function mix(a:Int, b:Int, t:Float):Int
	{
		t = FlxMath.bound(t, 0, 1);
		var ar:Int = (a >> 16) & 0xFF;
		var ag:Int = (a >> 8) & 0xFF;
		var ab:Int = a & 0xFF;
		var br:Int = (b >> 16) & 0xFF;
		var bg:Int = (b >> 8) & 0xFF;
		var bb:Int = b & 0xFF;
		var r:Int = Std.int(ar + (br - ar) * t);
		var g:Int = Std.int(ag + (bg - ag) * t);
		var bl:Int = Std.int(ab + (bb - ab) * t);
		return 0xFF000000 | (r << 16) | (g << 8) | bl;
	}
}
