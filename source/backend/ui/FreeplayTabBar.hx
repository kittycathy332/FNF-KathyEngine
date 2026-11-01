package backend.ui;

import flixel.FlxSprite;
import flixel.FlxState;
import flixel.math.FlxMath;
import flixel.math.FlxRect;
import flixel.text.FlxText;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.util.FlxColor;
import openfl.display.BitmapData;
import openfl.display.GradientType;
import openfl.display.Graphics;
import openfl.display.Shape;
import openfl.geom.Matrix;

/**
 * Freeplay 顶部分区 Tab 栏（单行、FNF 斜切卡片风格、纯 Flixel 自绘）。
 *
 * 视觉：
 *  - 卡片为投影 + 深色渐变平行四边形，顶部一条浅色高光
 *  - 选中：主题色文字 + 沿卡片底边的同色指示条（外加细边框），主题色可按分区配置，默认亮黄
 *  - 曲目数以像素字体角标显示在卡片右下角（字体跟随多语言设置）
 *  - 悬停时文字变白
 *  - 所有元素关闭抗锯齿，保持像素质感
 *
 * 交互：
 *  - 点击卡片切换分区（onSelect 回调）
 *  - 鼠标/触摸按住可横向拖动，滚轮可横向滚动
 *  - 选中项会自动滚动到可见区域（Q/E 等键盘切换同样适用）
 */
class FreeplayTabBar
{
	public static inline var HEIGHT:Float = 34;
	public static inline var GAP:Float = 6;
	public static inline var MARGIN:Float = 12;
	public static inline var SKEW:Float = 9;

	static inline var PAD_LEFT:Float = 12;
	static inline var PAD_RIGHT:Float = 12;
	static inline var LABEL_GAP:Float = 12;
	static inline var MIN_WIDTH:Float = 88;
	static inline var LABEL_SIZE:Int = 16;
	static inline var BADGE_SIZE:Int = 12;
	/** 角标距卡片右下斜边的水平内边距、距底边的垂直内边距 */
	static inline var BADGE_MARGIN:Float = 7;
	static inline var BADGE_BOTTOM:Float = 4;
	static inline var ACCENT:Int = 0xFFFFD800;
	static inline var TEXT_NORMAL:Int = 0xFFB9B9C3;
	static inline var TEXT_HOVER:Int = 0xFFFFFFFF;
	static inline var BADGE_NORMAL:Int = 0xFF7E7E8A;
	static inline var BADGE_HOVER:Int = 0xFFC8C8D0;
	static inline var DRAG_THRESHOLD:Float = 8;
	/** 松手速度 × 该系数 = 惯性追加的滑行距离（秒） */
	static inline var FLING_COAST:Float = 0.3;
	/** 惯性滑行阶段的平滑速率（越小滑得越久） */
	static inline var FLING_RATE:Float = 8;
	static inline var SCROLL_RATE:Float = 16;
	/** 低于该松手速度不做惯性（px/s），以及速度上限 */
	static inline var FLING_MIN_SPEED:Float = 260;
	static inline var FLING_MAX_SPEED:Float = 3200;

	/** 选中某个分区（用户点击卡片时触发）。 */
	public var onSelect:Int->Void;

	/** Tab 行顶部 y 坐标（由 FreeplayState 指定）。 */
	public var rowY:Float = 6;

	var font:String;
	var badgeFont:String;
	var state:FlxState;

	var cards:Array<FlxSprite> = [];
	var hovers:Array<FlxSprite> = [];
	var overlays:Array<FlxSprite> = [];
	var labels:Array<FlxText> = [];
	var badges:Array<FlxText> = [];
	var widths:Array<Float> = [];
	var offsets:Array<Float> = [];
	/** 每个分区的主题色（选中态文字与底部亮条都用它） */
	var accents:Array<Int> = [];

	var selected:Int = 0;
	var hovered:Int = -1;
	var shown:Bool = false;
	var dirty:Bool = true;

	var rowX:Float = MARGIN;
	var rowW:Float = 0;
	var contentW:Float = 0;

	var scroll:Float = 0;
	var scrollTarget:Float = 0;
	/** 平滑滚动的速率（惯性滑行时用小值，滑得更"长"） */
	var scrollRate:Float = 16;

	var dragging:Bool = false;
	var dragMoved:Bool = false;
	var dragStartX:Float = 0;
	var dragStartScroll:Float = 0;
	var dragPrevX:Float = 0;
	/** 拖动时的瞬时速度（px/s），松手后用来做惯性 */
	var dragVel:Float = 0;
	var pressedIndex:Int = -1;

	public function new(font:String, badgeFont:String)
	{
		this.font = font;
		// 曲目数角标用按语言映射的像素字体；未指定时退回标题字体
		this.badgeFont = (badgeFont != null && badgeFont.length > 0) ? badgeFont : font;
	}

	/** 按分区名与曲目数构建（重建时会清掉旧卡片）。
	 *  @param accents 每个分区的主题色（0xAARRGGBB）；元素为 -1 或缺失时用默认亮黄 */
	public function build(titles:Array<String>, counts:Array<Int>, selectedIndex:Int, ?accents:Array<Int>):Void
	{
		clearTabs();

		selected = (selectedIndex >= 0 && selectedIndex < titles.length) ? selectedIndex : -1;
		hovered = -1;

		rowW = FlxG.width - MARGIN * 2;

		var total:Float = 0;
		for (i in 0...titles.length)
		{
			var label:FlxText = makeText(titles[i], LABEL_SIZE, font);
			var badge:FlxText = makeText('${counts[i]}', BADGE_SIZE, badgeFont);
			var w:Float = Math.max(MIN_WIDTH, SKEW + PAD_LEFT + label.width + LABEL_GAP + badge.width + PAD_RIGHT);

			var accent:Int = ACCENT;
			if (accents != null && i < accents.length && accents[i] != 0)
				accent = accents[i];

			widths.push(w);
			offsets.push(total);
			total += w + GAP;

			cards.push(makeCard(w, HEIGHT));
			hovers.push(makeHover(w, HEIGHT));
			overlays.push(makeOverlay(w, HEIGHT, accent));
			this.accents.push(accent);
			labels.push(label);
			badges.push(badge);
		}
		if (widths.length > 0)
			contentW = total - GAP;

		// 初始直接定位到选中项，不要从 0 滚动过去
		scroll = 0;
		scrollTarget = 0;
		ensureVisible(selected);
		scroll = scrollTarget;
		dirty = true;
	}

	/** 把卡片挂到指定 state（必须在 build 之后调用一次）。 */
	public function addTo(state:FlxState):Void
	{
		this.state = state;
		for (i in 0...cards.length)
		{
			state.add(cards[i]);
			state.add(hovers[i]);
			state.add(overlays[i]);
			state.add(labels[i]);
			state.add(badges[i]);
		}
		applyState();
		applyPositions();
	}

	/** 直接指定可见窗口的左边与宽度（固定分区行、以及避让高分面板的自定义行都用它）。 */
	public function layout(x:Float, visibleWidth:Float):Void
	{
		rowX = x;
		rowW = Math.max(0, visibleWidth);
		scrollTarget = clampScroll(scrollTarget);
		scroll = clampScroll(scroll);
		ensureVisible(selected);
		dirty = true;
		if (state != null)
			applyPositions();
	}

	/** 所有卡片的自然总宽度。 */
	public function getContentWidth():Float
	{
		return contentW;
	}

	/** 显示/隐藏整条 Tab 栏（试听预览或没有自定义分区时隐藏）。 */
	public function setVisible(value:Bool):Void
	{
		if (shown == value)
			return;
		shown = value;
		dirty = true;
		if (state != null)
			applyPositions();
	}

	/** 程序设置选中项（Q/E、肩键切区后同步）。 */
	public function setSelected(index:Int):Void
	{
		if (index < 0 || index >= labels.length || index == selected)
			return;
		selected = index;
		applyState();
		ensureVisible(index);
	}

	/** 取消选中（当前分区属于另一行时使用）。 */
	public function clearSelection():Void
	{
		if (selected == -1)
			return;
		selected = -1;
		applyState();
	}

	/** 鼠标/触摸是否落在 Tab 行上（用于屏蔽歌单的滚轮）。 */
	public function isOverBar():Bool
	{
		if (!shown)
			return false;
		var mx:Float = FlxG.mouse.x;
		var my:Float = FlxG.mouse.y;
		return my >= rowY && my <= rowY + HEIGHT && mx >= rowX && mx <= rowX + rowW;
	}

	/** 每帧调用：处理悬停、点击、拖动、滚轮与平滑滚动。 */
	public function update(elapsed:Float):Void
	{
		if (!shown || state == null || cards.length == 0)
			return;

		if (scroll != scrollTarget)
		{
			scroll = FlxMath.lerp(scroll, scrollTarget, Math.min(1, elapsed * scrollRate));
			if (Math.abs(scrollTarget - scroll) < 0.4)
			{
				scroll = scrollTarget;
				scrollRate = SCROLL_RATE;
			}
			dirty = true;
		}

		var mx:Float = FlxG.mouse.x;
		var my:Float = FlxG.mouse.y;
		var overRow:Bool = my >= rowY && my <= rowY + HEIGHT && mx >= rowX && mx <= rowX + rowW;

		if (dragging)
		{
			var dx:Float = mx - dragStartX;
			if (!dragMoved && Math.abs(dx) > DRAG_THRESHOLD)
				dragMoved = true;
			if (dragMoved)
			{
				// 内容跟随手指/鼠标：往右拖，卡片跟着往右走
				scrollTarget = clampScroll(dragStartScroll + dx);
				scroll = scrollTarget;

				// 记录拖动速度（px/s）：快速甩动后松手才有惯性
				var instantVel:Float = (mx - dragPrevX) / (elapsed > 0 ? elapsed : 0.016);
				dragVel = (dragVel + instantVel) * 0.5;
				dirty = true;
			}
			dragPrevX = mx;

			if (!FlxG.mouse.pressed)
			{
				dragging = false;
				if (!dragMoved && pressedIndex >= 0 && hitTest(mx, my) == pressedIndex)
				{
					select(pressedIndex);
				}
				else if (dragMoved && Math.abs(dragVel) >= FLING_MIN_SPEED)
				{
					// 松手惯性：按松手瞬间的速度再滑一段，用更慢的速率缓出
					var flingDistance:Float = FlxMath.bound(dragVel, -FLING_MAX_SPEED, FLING_MAX_SPEED) * FLING_COAST;
					scrollTarget = clampScroll(scroll + flingDistance);
					scrollRate = FLING_RATE;
					dirty = true;
				}
				dragVel = 0;
				pressedIndex = -1;
			}
		}
		else if (overRow)
		{
			// 滚轮横向滚动（FlxG.mouse.wheel 向上为正：向上滚回到前面的分区，向下滚往后翻）
			if (FlxG.mouse.wheel != 0)
			{
				scrollTarget = clampScroll(scrollTarget + FlxG.mouse.wheel * 70);
				scrollRate = SCROLL_RATE;
				dirty = true;
			}

			if (FlxG.mouse.justPressed)
			{
				// 按下即接管当前的滚动位置：正在惯性滑行时会被立刻停住
				scrollTarget = scroll;
				dragging = true;
				dragMoved = false;
				dragStartX = mx;
				dragStartScroll = scroll;
				dragPrevX = mx;
				dragVel = 0;
				scrollRate = SCROLL_RATE;
				pressedIndex = hitTest(mx, my);
			}

			var hover:Int = hitTest(mx, my);
			if (hover != hovered)
			{
				hovered = hover;
				applyState();
			}
		}
		else if (hovered != -1)
		{
			hovered = -1;
			applyState();
		}

		if (dirty)
			applyPositions();
	}

	/** 释放所有卡片精灵（离开 Freeplay 时调用）。 */
	public function destroy():Void
	{
		clearTabs();
		onSelect = null;
		state = null;
	}

	// ==================== 内部实现 ====================

	function select(index:Int):Void
	{
		if (index < 0 || index >= labels.length)
			return;
		if (index != selected)
		{
			selected = index;
			applyState();
		}
		ensureVisible(index);
		if (onSelect != null)
			onSelect(index);
	}

	/** 让指定卡片完整落在可见区域内（只在必要时调整滚动目标）。 */
	function ensureVisible(index:Int):Void
	{
		if (index < 0 || index >= widths.length)
			return;
		scrollRate = SCROLL_RATE;
		var left:Float = offsets[index];
		var w:Float = widths[index];
		if (left + scrollTarget < 4)
			scrollTarget = 4 - left;
		else if (left + w + scrollTarget > rowW - 4)
			scrollTarget = rowW - 4 - w - left;
		scrollTarget = clampScroll(scrollTarget);
		dirty = true;
	}

	function clampScroll(value:Float):Float
	{
		var minScroll:Float = Math.min(0, rowW - contentW);
		return Math.max(minScroll, Math.min(0, value));
	}

	/** 命中测试：返回鼠标下的卡片索引（不在任何卡片上时返回 -1）。 */
	function hitTest(mx:Float, my:Float):Int
	{
		if (my < rowY || my > rowY + HEIGHT)
			return -1;
		for (i in 0...widths.length)
		{
			var x:Float = rowX + offsets[i] + scroll;
			// 完全滚出可见区域外的卡片不参与命中，避免点到看不见的分区
			if (x + widths[i] <= rowX || x >= rowX + rowW)
				continue;
			if (mx >= x && mx <= x + widths[i])
				return i;
		}
		return -1;
	}

	/** 选中态 / 悬停态的文字与指示条同步。 */
	function applyState():Void
	{
		for (i in 0...labels.length)
		{
			var isSel:Bool = i == selected;
			var isHover:Bool = i == hovered;
			var accent:Int = (i < accents.length) ? accents[i] : ACCENT;
			labels[i].color = isSel ? accent : (isHover ? TEXT_HOVER : TEXT_NORMAL);
			badges[i].color = isSel ? accent : (isHover ? BADGE_HOVER : BADGE_NORMAL);

			var overlay:FlxSprite = overlays[i];
			if (isSel)
			{
				// 只在第一次被选中时做淡入；hover 变化会反复调用这里，不应重启动画
				if (overlay.alpha <= 0)
				{
					FlxTween.cancelTweensOf(overlay);
					overlay.alpha = 0;
					FlxTween.tween(overlay, {alpha: 1}, 0.14, {ease: FlxEase.quadOut});
				}
			}
			else if (overlay.alpha != 0)
			{
				FlxTween.cancelTweensOf(overlay);
				overlay.alpha = 0;
			}
		}
		dirty = true;
	}

	/** 按当前滚动值摆放所有精灵；超出可见窗口的部分直接裁掉（卡片保持不透明，不做整体淡出）。 */
	function applyPositions():Void
	{
		if (state == null)
			return;

		var visL:Float = rowX;
		var visR:Float = rowX + rowW;

		for (i in 0...cards.length)
		{
			var x:Float = rowX + offsets[i] + scroll;
			var w:Float = widths[i];
			var vis:Bool = shown && x + w > visL && x < visR;

			// 悬停高光：选中项用 overlay 的暖色光晕，这里只处理未选中的卡片
			var hover:FlxSprite = hovers[i];
			hover.x = x;
			hover.y = rowY;
			hover.visible = vis && hovered == i && selected != i;

			var overlay:FlxSprite = overlays[i];
			overlay.x = x;
			overlay.y = rowY;
			overlay.visible = vis;

			var card:FlxSprite = cards[i];
			card.x = x;
			card.y = rowY;
			card.visible = vis;
			card.alpha = 1;
			if (vis)
			{
				clipToRow(card, x, visL, visR);
				clipToRow(hover, x, visL, visR);
				clipToRow(overlay, x, visL, visR);
			}

			// 文字落在整数像素上，避免滚动时字形发虚
			var label:FlxText = labels[i];
			label.x = Math.round(x + SKEW + PAD_LEFT);
			label.y = rowY + Math.round((HEIGHT - label.height) * 0.5);
			label.visible = vis;
			label.alpha = 1;
			if (vis)
				clipToRow(label, label.x, visL, visR);

			var badge:FlxText = badges[i];
			badge.x = Math.round(x + w - SKEW - BADGE_MARGIN - badge.width);
			badge.y = rowY + Math.round(HEIGHT - badge.height - BADGE_BOTTOM);
			badge.visible = vis;
			badge.alpha = 1;
			if (vis)
				clipToRow(badge, badge.x, visL, visR);
		}
		dirty = false;
	}

	/**
	 * 把精灵硬裁到可见窗口 `[visL, visR]`（世界坐标）。
	 * FlxSprite 的 clipRect 只改绘制区域，不改变精灵位置与尺寸，因此被裁的部分直接消失、剩余部分位置不变。
	 */
	function clipToRow(sprite:FlxSprite, x:Float, visL:Float, visR:Float):Void
	{
		var frameW:Float = sprite.frameWidth;
		// 向内取整：宁可多裁一个像素，也不要让内容溢出到窗口外
		var localL:Float = Math.ceil(Math.max(0, visL - x));
		var localR:Float = Math.min(frameW, Math.floor(visR - x));

		if (localL <= 0 && localR >= frameW)
		{
			if (sprite.clipRect != null)
				sprite.clipRect = null;
			return;
		}

		if (localR <= localL)
		{
			sprite.visible = false;
			return;
		}

		var clip:FlxRect = sprite.clipRect;
		if (clip != null && clip.x == localL && clip.width == localR - localL)
			return; // 数值未变就不要重设，避免每帧重建帧数据

		sprite.clipRect = new FlxRect(localL, 0, localR - localL, sprite.frameHeight);
	}


	function clearTabs():Void
	{
		for (s in cards)
			removeSprite(s);
		for (s in hovers)
			removeSprite(s);
		for (s in overlays)
			removeSprite(s);
		for (s in labels)
			removeSprite(s);
		for (s in badges)
			removeSprite(s);

		cards = [];
		hovers = [];
		overlays = [];
		labels = [];
		badges = [];
		widths = [];
		offsets = [];
		accents = [];
		contentW = 0;
	}

	function removeSprite(s:FlxSprite):Void
	{
		if (state != null)
			state.remove(s);
		if (s != null)
			s.destroy();
	}

	function makeText(text:String, size:Int, fontName:String):FlxText
	{
		var t:FlxText = new FlxText(0, 0, 0, text, size);
		t.setFormat(fontName, size, FlxColor.WHITE, LEFT);
		t.scrollFactor.set(0, 0);
		t.antialiasing = false; // Tab 栏文字一律关闭抗锯齿
		// FlxText 首次绘制前 width 只是占位值，需要手动重建一次才能拿到真实文字宽度
		@:privateAccess t.regenGraphic();
		return t;
	}

	/** 未选中卡片：投影 + 深色渐变 + 顶部高光。 */
	function makeCard(w:Float, h:Float):FlxSprite
	{
		var pw:Int = Std.int(Math.ceil(w + 4));
		var ph:Int = Std.int(Math.ceil(h + 3));
		var bmd:BitmapData = new BitmapData(pw, ph, true, 0x00000000);
		var shape:Shape = new Shape();

		// 投影
		shape.graphics.beginFill(0x000000, 0.45);
		traceQuad(shape.graphics, w, h, 2, 3, SKEW);
		shape.graphics.endFill();

		// 卡片主体（上浅下深的竖向渐变）
		var matrix:Matrix = new Matrix();
		matrix.createGradientBox(w, h, Math.PI * 0.5, 0, 0);
		var colors:Array<Int> = [0xFF34343F, 0xFF0E0E12];
		var alphas:Array<Float> = [0.94, 0.94];
		var ratios:Array<Int> = [0, 255];
		shape.graphics.beginGradientFill(GradientType.LINEAR, colors, alphas, ratios, matrix);
		traceQuad(shape.graphics, w, h, 0, 0, SKEW);
		shape.graphics.endFill();

		// 顶部高光
		shape.graphics.lineStyle(1, 0xFFFFFF, 0.16);
		shape.graphics.moveTo(SKEW, 0.5);
		shape.graphics.lineTo(w, 0.5);

		bmd.draw(shape);

		var sprite:FlxSprite = new FlxSprite(0, 0);
		sprite.loadGraphic(bmd, false, pw, ph, true);
		sprite.scrollFactor.set(0, 0);
		sprite.antialiasing = false; // Tab 栏一律关闭抗锯齿（像素风硬边）
		return sprite;
	}

	/** 悬停高光层：一层很淡的白色，让未选中的卡片也有可点击的反馈。 */
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
		traceQuad(shape.graphics, w, h, 0, 0, SKEW);
		shape.graphics.endFill();

		bmd.draw(shape);

		var sprite:FlxSprite = new FlxSprite(0, 0);
		sprite.loadGraphic(bmd, false, pw, ph, true);
		sprite.scrollFactor.set(0, 0);
		sprite.antialiasing = false; // Tab 栏一律关闭抗锯齿（像素风硬边）
		sprite.visible = false;
		return sprite;
	}

	/** 选中指示层：主题色光晕 + 细边框 + 底部 3px 亮条。 */
	function makeOverlay(w:Float, h:Float, accent:Int):FlxSprite
	{
		var pw:Int = Std.int(Math.ceil(w + 4));
		var ph:Int = Std.int(Math.ceil(h + 3));
		var bmd:BitmapData = new BitmapData(pw, ph, true, 0x00000000);
		var shape:Shape = new Shape();

		// 被选中卡片整体淡淡透出的主题色（随 overlay 一起淡入）
		var matrix:Matrix = new Matrix();
		matrix.createGradientBox(w, h, Math.PI * 0.5, 0, 0);
		var colors:Array<Int> = [accent, accent];
		var alphas:Array<Float> = [0.18, 0.05];
		var ratios:Array<Int> = [0, 255];
		shape.graphics.beginGradientFill(GradientType.LINEAR, colors, alphas, ratios, matrix);
		traceQuad(shape.graphics, w, h, 0, 0, SKEW);
		shape.graphics.endFill();

		// 描边
		shape.graphics.lineStyle(1.5, accent, 0.9);
		traceQuad(shape.graphics, w - 2, h - 2, 1, 1, SKEW);

		// 底部亮条：严格贴合卡片底边的斜边，不能超出卡片轮廓
		var barH:Float = 3;
		var barTopL:Float = SKEW * barH / h;
		var barTopR:Float = w - SKEW + SKEW * barH / h;
		shape.graphics.beginFill(accent, 1);
		shape.graphics.moveTo(barTopL, h - barH);
		shape.graphics.lineTo(barTopR, h - barH);
		shape.graphics.lineTo(w - SKEW, h);
		shape.graphics.lineTo(0, h);
		shape.graphics.lineTo(barTopL, h - barH);
		shape.graphics.endFill();

		bmd.draw(shape);

		var sprite:FlxSprite = new FlxSprite(0, 0);
		sprite.loadGraphic(bmd, false, pw, ph, true);
		sprite.scrollFactor.set(0, 0);
		sprite.antialiasing = false; // Tab 栏一律关闭抗锯齿（像素风硬边）
		// 初始为透明，由 applyState 做淡入
		sprite.alpha = 0;
		return sprite;
	}

	/** 以 (ox, oy) 为左上角画一个向右倾斜的平行四边形。 */
	inline function traceQuad(g:Graphics, w:Float, h:Float, ox:Float, oy:Float, skew:Float):Void
	{
		g.moveTo(ox + skew, oy);
		g.lineTo(ox + w, oy);
		g.lineTo(ox + w - skew, oy + h);
		g.lineTo(ox, oy + h);
		g.lineTo(ox + skew, oy);
	}
}
