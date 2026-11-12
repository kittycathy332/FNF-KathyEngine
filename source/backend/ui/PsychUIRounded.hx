package backend.ui;

import flixel.FlxSprite;
import flixel.graphics.FlxGraphic;
import openfl.display.BitmapData;
import openfl.display.Graphics;
import openfl.display.Shape;
import openfl.geom.Matrix;

/**
 * Kathy 编谱器专用的圆角皮肤工具。
 *
 * - `radius` 默认 0：其它编辑器完全不受影响，继续用原 png 帧 / 1x1 方角。
 *   ChartingState.create() 设 4，destroy() 还原 0。
 * - PsychUI* 的背景几乎都是「1x1 纯色 FlxSprite 拉伸」，`apply()` 把它换成
 *   按显示尺寸烘焙的白色圆角位图，控件自身的 `color` / `alpha` 着色仍然生效。
 * - 图片帧控件（勾选框 / 单选框 / 加减按钮 / 下拉箭头 / 上下箭头）在 radius>0 时
 *   改用自绘的多帧位图，帧尺寸与动画名保持和原 png 一致。
 * - 所有位图按 尺寸+半径 缓存复用，不会每次 resize 都新建纹理。
 */
class PsychUIRounded
{
	/** 0 = 不启用；Kathy 编谱器内为 4 */
	public static var radius:Float = 0;

	static var _cache:Map<String, FlxGraphic> = new Map<String, FlxGraphic>();

	static function cached(key:String, build:Void->BitmapData):FlxGraphic
	{
		var graph:FlxGraphic = _cache.get(key);
		if (graph != null && !graph.isDestroyed) return graph;
		graph = FlxGraphic.fromBitmapData(build(), false, key);
		_cache.set(key, graph);
		return graph;
	}

	/**
	 * OpenFL 的 Graphics.drawRoundRect 自带抗锯齿，圆角边缘是一圈半透明像素，
	 * 贴到屏幕上就是「糊」。这里把 alpha 二值化，得到干净的硬像素圆角。
	 * 只在烘焙期调用一次（结果按尺寸缓存），运行时零开销。
	 */
	public static function hardenAlpha(bd:BitmapData):Void
	{
		if (bd == null) return;
		var w:Int = bd.width;
		var h:Int = bd.height;
		bd.lock();
		for (y in 0...h)
		{
			for (x in 0...w)
			{
				var px:Int = bd.getPixel32(x, y);
				var a:Int = (px >>> 24) & 0xFF;
				if (a == 0 || a == 255) continue;
				bd.setPixel32(x, y, (a >= 128) ? ((0xFF << 24) | (px & 0x00FFFFFF)) : 0);
			}
		}
		bd.unlock();
	}

	/**
	 * 只二值化位图外圈几条像素（HaxeUI 组件用）。
	 * 它的表面可能有整体半透明底色，全图二值化会把底色也强制成不透明；
	 * 而 OpenFL 矢量 AA 只出现在绘制轮廓附近，处理外圈即可。
	 */
	public static function hardenEdges(bd:BitmapData, band:Int = 3):Void
	{
		if (bd == null) return;
		var w:Int = bd.width;
		var h:Int = bd.height;
		var b:Int = Std.int(Math.min(Math.min(w, h), Math.max(1, band)));
		bd.lock();
		var one = function(x:Int, y:Int):Void
		{
			var px:Int = bd.getPixel32(x, y);
			var a:Int = (px >>> 24) & 0xFF;
			if (a == 0 || a == 255) return;
			bd.setPixel32(x, y, (a >= 128) ? ((0xFF << 24) | (px & 0x00FFFFFF)) : 0);
		};
		for (y in 0...h)
		{
			for (x in 0...b) one(x, y);
			for (x in (w - b)...w) one(x, y);
		}
		for (x in 0...w)
		{
			for (y in 0...b) one(x, y);
			for (y in (h - b)...h) one(x, y);
		}
		bd.unlock();
	}

	/** 白色圆角纯色位图（外侧四角透明，靠 sprite.color 着色） */
	public static function rounded(width:Int, height:Int, ?r:Float):FlxGraphic
	{
		var rad:Float = (r == null) ? radius : r;
		var w:Int = Std.int(Math.max(1, width));
		var h:Int = Std.int(Math.max(1, height));
		return cached('PsychUIRounded:bg:${w}x${h}r${Std.int(rad * 2)}', function():BitmapData
		{
			var bd:BitmapData = new BitmapData(w, h, true, 0);
			var shape:Shape = new Shape();
			var g:Graphics = shape.graphics;
			var d:Float = Math.min(rad * 2, Math.min(w, h));
			g.beginFill(0xFFFFFF, 1);
			g.drawRoundRect(0, 0, w, h, d, d);
			g.endFill();
			bd.draw(shape);
			hardenAlpha(bd);
			return bd;
		});
	}

	/** 给 1x1 拉伸的纯色背景套圆角；width/height 省略时取当前显示尺寸 */
	public static function apply(sprite:FlxSprite, ?width:Float, ?height:Float, ?r:Float):Void
	{
		if (sprite == null) return;
		sprite.antialiasing = false;
		var rad:Float = (r == null) ? radius : r;
		if (rad <= 0) return;
		var w:Float = (width == null) ? sprite.width : width;
		var h:Float = (height == null) ? sprite.height : height;
		sprite.frames = rounded(Std.int(Math.max(1, w)), Std.int(Math.max(1, h)), rad).imageFrame;
		sprite.scale.set(1, 1);
		sprite.updateHitbox();
	}

	/**
	 * 把背景显示高度改成 h 且保持圆角，代替直接写 `scale.y`。
	 * radius=0 时原样走 1x1 缩放逻辑，其它编辑器行为不变。
	 */
	public static function resizeHeight(sprite:FlxSprite, h:Float, ?w:Float):Void
	{
		if (sprite == null) return;
		if (radius <= 0)
		{
			sprite.scale.y = h;
			sprite.updateHitbox();
			return;
		}
		apply(sprite, (w == null) ? sprite.width : w, h);
	}

	/** 多帧图标位图：painter(graphics, frameIndex, w, h) 在局部坐标画一帧 */
	static function sheet(key:String, w:Int, h:Int, frames:Int, painter:Graphics->Int->Int->Int->Void):FlxGraphic
	{
		return cached(key, function():BitmapData
		{
			var bd:BitmapData = new BitmapData(w * frames, h, true, 0);
			for (i in 0...frames)
			{
				var shape:Shape = new Shape();
				painter(shape.graphics, i, w, h);
				var m:Matrix = new Matrix();
				m.translate(i * w, 0);
				bd.draw(shape, m);
			}
			hardenAlpha(bd);
			return bd;
		});
	}

	/** 统一的黑底白描边圆角底座；circle=true 时画正圆（单选框） */
	static function base(g:Graphics, w:Int, h:Int, pressed:Bool, circle:Bool = false, r:Float = 4):Void
	{
		var fill:Int = pressed ? 0xFF3A3A3A : 0xFF111111;
		var d:Float = Math.min(r * 2, Math.min(w, h));
		g.lineStyle(2, 0xFFFFFF, 1, true);
		g.beginFill(fill, 1);
		if (circle) g.drawCircle(w / 2, h / 2, Math.min(w, h) / 2 - 1);
		else g.drawRoundRect(1, 1, w - 2, h - 2, d, d);
		g.endFill();
	}

	/** 复选框：2 帧 false / true，16x16 */
	public static function checkSheet():FlxGraphic
	{
		return sheet('PsychUIRounded:check', 16, 16, 2, function(g:Graphics, i:Int, w:Int, h:Int):Void
		{
			base(g, w, h, false);
			if (i == 1)
			{
				g.lineStyle(2.5, 0xFFFFFF, 1, true);
				g.moveTo(4, 8.5); g.lineTo(7, 11.5); g.lineTo(12.5, 5);
			}
		});
	}

	/** 单选框：2 帧 false / true，16x16 正圆 */
	public static function radioSheet():FlxGraphic
	{
		return sheet('PsychUIRounded:radio', 16, 16, 2, function(g:Graphics, i:Int, w:Int, h:Int):Void
		{
			base(g, w, h, false, true);
			if (i == 1)
			{
				g.lineStyle(0);
				g.beginFill(0xFFFFFF, 1);
				g.drawCircle(w / 2, h / 2, 3);
				g.endFill();
			}
		});
	}

	/** 数字框 +/- 按钮：2 帧 normal / pressed，16x16 */
	public static function stepperSheet(plus:Bool):FlxGraphic
	{
		var tag:String = plus ? 'plus' : 'minus';
		return sheet('PsychUIRounded:stepper:$tag', 16, 16, 2, function(g:Graphics, i:Int, w:Int, h:Int):Void
		{
			base(g, w, h, i == 1);
			g.lineStyle(2, 0xFFFFFF, 1, true);
			g.moveTo(4.5, 8); g.lineTo(11.5, 8);
			if (plus) { g.moveTo(8, 4.5); g.lineTo(8, 11.5); }
		});
	}

	/** 下拉箭头按钮：2 帧 normal / pressed，20x20 */
	public static function dropDownButtonSheet():FlxGraphic
	{
		return sheet('PsychUIRounded:ddbutton', 20, 20, 2, function(g:Graphics, i:Int, w:Int, h:Int):Void
		{
			base(g, w, h, i == 1);
			g.lineStyle(0);
			g.beginFill(0xFFFFFF, 1);
			g.moveTo(6, 8); g.lineTo(14, 8); g.lineTo(10, 13); g.lineTo(6, 8);
			g.endFill();
		});
	}

	/** 单选组上下箭头：2 帧 normal / press，24x18 */
	public static function arrowSheet(up:Bool):FlxGraphic
	{
		var tag:String = up ? 'up' : 'down';
		return sheet('PsychUIRounded:arrow:$tag', 24, 18, 2, function(g:Graphics, i:Int, w:Int, h:Int):Void
		{
			base(g, w, h, i == 1);
			g.lineStyle(0);
			g.beginFill(0xFFFFFF, 1);
			if (up) { g.moveTo(12, 4); g.lineTo(19, 13); g.lineTo(5, 13); }
			else { g.moveTo(5, 5); g.lineTo(19, 5); g.lineTo(12, 14); }
			g.endFill();
		});
	}
}
