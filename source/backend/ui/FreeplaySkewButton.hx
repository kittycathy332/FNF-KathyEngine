package backend.ui;

import flixel.FlxSprite;
import flixel.FlxState;
import flixel.text.FlxText;
import openfl.display.BitmapData;
import openfl.display.GradientType;
import openfl.display.Graphics;
import openfl.display.Shape;
import openfl.geom.Matrix;

/**
 * Freeplay 顶栏末尾的斜切小按钮（目前用于「分区编辑」入口）。
 *
 * 视觉与 FreeplayTabBar 的分区卡片是同一套：投影 + 深色竖向渐变 + 顶部高光 + 像素字体；
 * 唯一区别是斜角方向相反——分区卡片是顶边左缩（"/"），本按钮是顶边右缩（"\"），
 * 这样它和分区卡片挨在同一行时一眼能区分开。
 *
 * 文字固定使用主色 #87CEEB（悬停变亮、按下变暗），悬停时整块叠加一层很淡的白色高光，
 * 与分区卡片的悬停反馈一致。
 */
class FreeplaySkewButton
{
	public static inline var HEIGHT:Float = FreeplayTabBar.HEIGHT;

	static inline var SKEW:Float = FreeplayTabBar.SKEW;
	static inline var PAD:Float = 12;
	static inline var LABEL_SIZE:Int = 16;
	static inline var MIN_WIDTH:Float = 88;
	static inline var ACCENT:Int = 0xFF87CEEB;
	static inline var ACCENT_HOVER:Int = 0xFFA5DCF2;
	static inline var ACCENT_DOWN:Int = 0xFF6FB9D6;

	/** 点击（按下后在同一按钮内松开）时触发。 */
	public var onClick:Void->Void;

	public var width(default, null):Float = MIN_WIDTH;
	public var height(default, null):Float = HEIGHT;

	var x:Float = 0;
	var y:Float = 0;
	var shown:Bool = true;
	var hovered:Bool = false;
	var pressing:Bool = false;

	var state:FlxState = null;
	var card:FlxSprite = null;
	var hoverLayer:FlxSprite = null;
	var label:FlxText = null;

	public function new(font:String, text:String)
	{
		label = new FlxText(0, 0, 0, text, LABEL_SIZE);
		label.setFormat(font, LABEL_SIZE, ACCENT, LEFT);
		label.scrollFactor.set(0, 0);
		label.antialiasing = false; // 与 Tab 栏一致，保持像素质感
		// FlxText 首次绘制前 width 只是占位值，需要手动重建一次才能拿到真实文字宽度
		@:privateAccess label.regenGraphic();

		width = Math.max(MIN_WIDTH, SKEW + PAD * 2 + label.width);

		card = makeCard(width, height);
		hoverLayer = makeHover(width, height);
		label.color = ACCENT;
	}

	/** 把按钮挂到指定 state（必须调用一次才会显示）。 */
	public function addTo(state:FlxState):Void
	{
		this.state = state;
		state.add(card);
		state.add(hoverLayer);
		state.add(label);
		applyPositions();
		applyState();
	}

	/** 摆放位置（左上角）。 */
	public function layout(x:Float, y:Float):Void
	{
		this.x = x;
		this.y = y;
		applyPositions();
	}

	public function setVisible(value:Bool):Void
	{
		if (shown == value)
			return;
		shown = value;
		if (!shown)
		{
			hovered = false;
			pressing = false;
			applyState();
		}
		applyPositions();
	}

	/** 每帧调用：悬停反馈 + 点击判定。 */
	public function update(elapsed:Float):Void
	{
		if (!shown || state == null)
			return;

		var over:Bool = contains(FlxG.mouse.x, FlxG.mouse.y);
		if (over != hovered)
		{
			hovered = over;
			applyState();
		}

		if (over && FlxG.mouse.justPressed)
			pressing = true;

		if (pressing && !FlxG.mouse.pressed)
		{
			pressing = false;
			applyState();
			if (over && onClick != null)
				onClick();
		}
	}

	public function contains(mx:Float, my:Float):Bool
	{
		return mx >= x && mx <= x + width && my >= y && my <= y + height;
	}

	public function destroy():Void
	{
		if (state != null)
		{
			state.remove(card);
			state.remove(hoverLayer);
			state.remove(label);
		}
		if (card != null)
		{
			card.destroy();
			card = null;
		}
		if (hoverLayer != null)
		{
			hoverLayer.destroy();
			hoverLayer = null;
		}
		if (label != null)
		{
			label.destroy();
			label = null;
		}
		onClick = null;
		state = null;
	}

	// ==================== 内部实现 ====================

	function applyState():Void
	{
		hoverLayer.visible = shown && hovered;
		label.color = pressing && hovered ? ACCENT_DOWN : (hovered ? ACCENT_HOVER : ACCENT);
	}

	function applyPositions():Void
	{
		card.x = x;
		card.y = y;
		card.visible = shown;

		hoverLayer.x = x;
		hoverLayer.y = y;
		hoverLayer.visible = shown && hovered;

		// 文字落在整数像素上，避免字形发虚
		label.x = Math.round(x + (width - label.width) * 0.5);
		label.y = Math.round(y + (height - label.height) * 0.5);
		label.visible = shown;
	}

	/** 与分区卡片同款：投影 + 深色渐变主体 + 顶部高光，仅斜角方向相反。 */
	function makeCard(w:Float, h:Float):FlxSprite
	{
		var pw:Int = Std.int(Math.ceil(w + 4));
		var ph:Int = Std.int(Math.ceil(h + 3));
		var bmd:BitmapData = new BitmapData(pw, ph, true, 0x00000000);
		var shape:Shape = new Shape();

		// 投影
		shape.graphics.beginFill(0x000000, 0.45);
		traceQuad(shape.graphics, w, h, 2, 3);
		shape.graphics.endFill();

		// 卡片主体（上浅下深的竖向渐变）
		var matrix:Matrix = new Matrix();
		matrix.createGradientBox(w, h, Math.PI * 0.5, 0, 0);
		var colors:Array<Int> = [0xFF34343F, 0xFF0E0E12];
		var alphas:Array<Float> = [0.94, 0.94];
		var ratios:Array<Int> = [0, 255];
		shape.graphics.beginGradientFill(GradientType.LINEAR, colors, alphas, ratios, matrix);
		traceQuad(shape.graphics, w, h, 0, 0);
		shape.graphics.endFill();

		// 顶部高光（镜像后顶边从 0 到 w - SKEW）
		shape.graphics.lineStyle(1, 0xFFFFFF, 0.16);
		shape.graphics.moveTo(0.5, 0.5);
		shape.graphics.lineTo(w - SKEW, 0.5);

		bmd.draw(shape);

		var sprite:FlxSprite = new FlxSprite(0, 0);
		sprite.loadGraphic(bmd, false, pw, ph, true);
		sprite.scrollFactor.set(0, 0);
		sprite.antialiasing = false; // 与 Tab 栏一致，保持像素质感
		return sprite;
	}

	/** 悬停高光层：与分区卡片使用同一档白色透明度。 */
	function makeHover(w:Float, h:Float):FlxSprite
	{
		var pw:Int = Std.int(Math.ceil(w + 4));
		var ph:Int = Std.int(Math.ceil(h + 3));
		var bmd:BitmapData = new BitmapData(pw, ph, true, 0x00000000);
		var shape:Shape = new Shape();

		var matrix:Matrix = new Matrix();
		matrix.createGradientBox(w, h, Math.PI * 0.5, 0, 0);
		var colors:Array<Int> = [0xFFFFFFFF, 0xFFFFFFFF];
		var alphas:Array<Float> = [0.14, 0.04];
		var ratios:Array<Int> = [0, 255];
		shape.graphics.beginGradientFill(GradientType.LINEAR, colors, alphas, ratios, matrix);
		traceQuad(shape.graphics, w, h, 0, 0);
		shape.graphics.endFill();

		bmd.draw(shape);

		var sprite:FlxSprite = new FlxSprite(0, 0);
		sprite.loadGraphic(bmd, false, pw, ph, true);
		sprite.scrollFactor.set(0, 0);
		sprite.antialiasing = false;
		sprite.visible = false;
		return sprite;
	}

	/** 以 (ox, oy) 为左上角画一个顶边右缩的平行四边形（分区卡片的镜像）。 */
	inline function traceQuad(g:Graphics, w:Float, h:Float, ox:Float, oy:Float):Void
	{
		g.moveTo(ox, oy);
		g.lineTo(ox + w - SKEW, oy);
		g.lineTo(ox + w, oy + h);
		g.lineTo(ox + SKEW, oy + h);
		g.lineTo(ox, oy);
	}
}
