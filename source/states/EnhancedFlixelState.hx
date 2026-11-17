package states;

import Main;
import flixel.FlxState;
import flixel.FlxSprite;
import flixel.effects.particles.FlxEmitter;
import flixel.effects.particles.FlxParticle;
import flixel.math.FlxPoint;
import backend.Paths;
import flixel.text.FlxText;
import flixel.tweens.FlxTween;
import flixel.tweens.FlxEase;
import flixel.util.FlxColor;
import flixel.util.FlxTimer;
import flixel.FlxG;
import openfl.display.Shape;
import openfl.display.BitmapData;
import openfl.geom.Matrix;

// 增强版 Flixel 四色风车开屏：
// 时间轴对齐原版（绿0.04s→黄0.18s→红0.33s→蓝0.50s→浅蓝0.64s）：
// 四瓣立刻以完整形态出现并快速砸向绿色中心块，撞击瞬间迸发粒子 + 绿块脉冲 + 接触闪光
// 文字图层位于图像之下，从 logo 右侧被「遮挡条」裁出后向右飞出显示
class EnhancedFlixelState extends FlxState
{
	static final PETAL_SIZE:Int = 120; // 单瓣位图尺寸（风车中心位于其中心）
	static final COLORS:Array<Int> = [0x00b922, 0xffc132, 0xf5274e, 0x3641ff, 0x04cdfb];
	// 各瓣多边形（相对风车中心 0,0，与 Flixel 官方 splash 一致）
	static final PETALS:Array<Array<Float>> = [
		[0, -37, 1, -37, 37, 0, 37, 1, 1, 37, 0, 37, -37, 1, -37, 0], // 绿（中心菱形）
		[-50, -50, -25, -50, 0, -37, -37, 0, -50, -25], // 黄（左上）
		[50, -50, 25, -50, 1, -37, 37, 0, 50, -25], // 红（右上）
		[-50, 50, -25, 50, 0, 37, -37, 1, -50, 25], // 蓝（左下）
		[50, 50, 25, 50, 1, 37, 37, 1, 50, 25] // 浅蓝（右下）
	];
	// 四瓣外侧方向的相对分量（左上/右上/左下/右下），用于「砸向绿块」入场
	static final OUT_DIRS:Array<Array<Float>> = [
		[-1, -1], [1, -1], [-1, 1], [1, 1]
	];
	// 对齐原版的出现时间点（黄/红/蓝/浅蓝）
	static final HIT_TIMES:Array<Float> = [0.184, 0.334, 0.495, 0.636];

	var petals:Array<FlxSprite> = [];
	var greenBlock:FlxSprite;
	var label:FlxText;
	var whiteFmt:flixel.text.FlxText.FlxTextFormat; // "Powered by" 纯白格式（不变色）
	var colorFmt:flixel.text.FlxText.FlxTextFormat; // "HaxeFlixel" 可变色格式
	var maskBar:FlxSprite; // 同背景色的遮挡条：让文字像从 logo 后飞出
	var emitter:FlxEmitter;
	var center:FlxPoint;

	var _cachedBgColor:FlxColor;
	var formed:Bool = false;
	var skipping:Bool = false;
	var bouncing:Bool = false; // 整组回弹进行中，暂停 update 的脉冲
	var textRevealed:Bool = false;
	var _colorIdx:Int = 0;

	// 预创建的五色格式实例，循环变色时只做 remove/add，不再每次 new 一个 FlxTextFormat
	var colorFormats:Array<flixel.text.FlxText.FlxTextFormat> = [];
	// 本 state 创建的所有 timer：切走时统一 cancel，避免无限循环变色 timer 等问题残留后台
	var timers:Array<FlxTimer> = [];

	function trackTimer(timer:FlxTimer):FlxTimer
	{
		timers.push(timer);
		return timer;
	}

	override public function create():Void
	{
		_cachedBgColor = FlxG.camera.bgColor;
		FlxG.camera.bgColor = FlxColor.BLACK;

		center = FlxPoint.get(FlxG.width / 2, FlxG.height / 2);

		// 启动音效（Flixel 自带 jingle）
		FlxG.sound.play(Paths.sound('flixel'));

		// —— 文字（图层在图像之下：先 add，logo 后 add 覆盖其上）——
		// 两行：上一行 "Powered by"（纯白），下一行 "HaxeFlixel"（循环变色）
		label = new FlxText(0, 0, 460, "Powered by\nHaxeFlixel", 28);
		label.setFormat(null, 28, FlxColor.WHITE, LEFT);
		label.alpha = 1;
		label.y = center.y - 26; // 两行块 ~52px，垂直居中
		label.x = startLabelX();
		// 用 FlxTextFormat 给不同字符区间套不同格式（参考官方 addFormat 用法）
		whiteFmt = new flixel.text.FlxText.FlxTextFormat(FlxColor.WHITE); // 上一行：纯白
		for (c in COLORS) colorFormats.push(new flixel.text.FlxText.FlxTextFormat(c));
		colorFmt = colorFormats[0]; // 下一行：可变色
		label.addFormat(whiteFmt, 0, 10);   // "Powered by"（10 字符）
		label.addFormat(colorFmt, 11, 21);  // "HaxeFlixel"（其后含换行，11..21）
		add(label);

		// —— 同色遮挡条：覆盖 logo 左侧区域，文字飞出到其右边缘后才会显形 ——
		maskBar = new FlxSprite(0, center.y - 50);
		maskBar.makeGraphic(Math.floor(revealLine()), 100, FlxColor.BLACK);
		maskBar.alpha = 1;
		add(maskBar);

		// —— 绿色中心块先出现（原版 0.04s，作为被撞击的「靶」）——
		greenBlock = drawPetal(PETALS[0], COLORS[0]);
		greenBlock.origin.set(PETAL_SIZE / 2, PETAL_SIZE / 2);
		greenBlock.setPosition(center.x - PETAL_SIZE / 2, center.y - PETAL_SIZE / 2);
		greenBlock.scale.set(0.5, 0.5);
		greenBlock.alpha = 1;
		petals.push(greenBlock);
		add(greenBlock);
		// 绿块轻微弹出（立即显示，非渐隐）
		FlxTween.tween(greenBlock, {'scale.x': 1, 'scale.y': 1}, 0.15, {ease: FlxEase.backOut});

		// —— 四瓣按原版时间点立刻出现并砸向绿块 ——
		for (i in 0...4)
		{
			trackTimer(new FlxTimer()).start(HIT_TIMES[i], (_) -> spawnOuter(i));
		}

		// 粒子发射器（成型时中心再补一发）
		emitter = new FlxEmitter(center.x, center.y);
		emitter.makeParticles(8, 8, FlxColor.WHITE, 60);
		emitter.color.set(COLORS[0], COLORS[4]); // 在五色之间取色
		emitter.launchMode = FlxEmitterMode.CIRCLE;
		emitter.speed.set(120, 360);
		emitter.scale.set(0.6, 1.2, 0, 0);
		emitter.alpha.set(1, 0, 0, 0);
		emitter.lifespan.set(0.6, 1.1);
		add(emitter);

		// 安全兜底：最长 4.5 秒后强制收尾
		trackTimer(new FlxTimer()).start(4.5, (_) -> outro());
	}

	// 四瓣立刻以完整形态出现，并快速砸向绿色中心块
	function spawnOuter(i:Int):Void
	{
		var idx:Int = i + 1; // 对应黄/红/蓝/浅蓝
		var p = drawPetal(PETALS[idx], COLORS[idx]);
		p.origin.set(PETAL_SIZE / 2, PETAL_SIZE / 2);

		var dir = OUT_DIRS[i];
		var fx:Float = center.x - PETAL_SIZE / 2;
		var fy:Float = center.y - PETAL_SIZE / 2;
		// 起点：从外侧更远处（沿 dir 远离中心），完整形态、立即显示
		p.setPosition(fx + dir[0] * 260, fy + dir[1] * 260);
		p.scale.set(1, 1);
		p.alpha = 1;
		petals.push(p);
		add(p);

		// 快速砸入（加速曲线，撞上绿块），随后迸发粒子
		FlxTween.tween(p, {x: fx, y: fy}, 0.18, {
			ease: FlxEase.quadIn,
			onComplete: (_) ->
			{
				hitGreen(dir, COLORS[idx]);
				if (idx == PETALS.length - 1 && !formed)
					onFormed();
			}
		});
	}

	// 撞击绿块：绿块轻微脉冲 + 接触点白色闪光 + 该色粒子迸发
	function hitGreen(dir:Array<Float>, color:Int):Void
	{
		// 每瓣落定的即时反馈（轻微），整体回弹由 bounceAll 统一表现。
		// 先取消上一次脉冲，避免 4 次撞击的 scale tween 叠加、互相拉扯导致绿块抖动。
		FlxTween.cancelTweensOf(greenBlock);
		FlxTween.tween(greenBlock, {'scale.x': 1.12, 'scale.y': 1.12}, 0.06, {
			ease: FlxEase.quadOut,
			onComplete: (_) -> FlxTween.tween(greenBlock, {'scale.x': 1, 'scale.y': 1}, 0.14, {ease: FlxEase.quadOut})
		});

		var cx:Float = center.x + dir[0] * 26;
		var cy:Float = center.y + dir[1] * 26;

		// 接触点白色闪光
		var spark = new FlxSprite(cx - 12, cy - 12);
		spark.makeGraphic(24, 24, FlxColor.WHITE);
		spark.alpha = 0.95;
		add(spark);
		FlxTween.tween(spark, {'scale.x': 2.4, 'scale.y': 2.4, alpha: 0}, 0.3, {
			ease: FlxEase.quadOut,
			onComplete: (_) -> spark.destroy()
		});

		// 撞击粒子（一次性迸发该瓣颜色）
		var burst = new FlxEmitter(cx, cy);
		burst.makeParticles(7, 7, color, 18);
		burst.color.set(color, color);
		burst.launchMode = FlxEmitterMode.CIRCLE;
		burst.speed.set(90, 240);
		burst.scale.set(0.5, 1.3, 0, 0);
		burst.alpha.set(1, 0, 0, 0);
		burst.lifespan.set(0.3, 0.6);
		add(burst);
		burst.start(true, 0, 18);
		trackTimer(new FlxTimer()).start(0.8, (_) -> burst.destroy());
	}

	// 整组（含绿色方块）轻微回弹：先压扁再弹性回正
	function bounceAll():Void
	{
		bouncing = true;
		var last = petals[petals.length - 1];
		for (p in petals)
		{
			FlxTween.tween(p, {'scale.x': 0.88, 'scale.y': 0.88}, 0.07, {
				ease: FlxEase.quadOut,
				onComplete: (_) -> FlxTween.tween(p, {'scale.x': 1, 'scale.y': 1}, 0.35, {
					ease: FlxEase.elasticOut,
					onComplete: (_) -> { if (p == last) bouncing = false; }
				})
			});
		}
	}

	function onFormed():Void
	{
		formed = true;
		emitter.start(true, 0, 50);

		// 整体（含绿色方块）轻微回弹：先压扁再弹性回正
		bounceAll();

		// 文字从 logo 后向右飞出
		textRevealed = true;
		FlxTween.tween(label, {x: endLabelX()}, 0.9, {ease: FlxEase.quadOut});

		// 仅 "HaxeFlixel" 颜色循环；"Powered by" 为纯白，不受影响
		trackTimer(new FlxTimer()).start(0.4, (_) ->
		{
			// FlxTextFormat 无 color 字段，需移除旧实例再套用新实例触发重绘。
			// 格式实例在 create 时已预建，这里只做切换，避免每次新建对象产生 GC 压力。
			label.removeFormat(colorFmt);
			_colorIdx = (_colorIdx + 1) % colorFormats.length;
			colorFmt = colorFormats[_colorIdx];
			label.addFormat(colorFmt, 11, 21); // 重新套用触发重绘
		}, 0); // loops = 0 => 无限循环

		// 对齐原版节奏：成型后停留约 2.0 秒再淡出
		trackTimer(new FlxTimer()).start(2.0, (_) -> outro());
	}

	// 文字起点（LEFT 对齐，左缘在此；需足够靠左才能整体藏到 logo 后方）/ 终点（向右飞出，贴近 logo 右侧）
	function startLabelX():Float
	{
		return center.x - 280;
	}

	function endLabelX():Float
	{
		return center.x + 200;
	}

	// 遮挡条的右边缘 = logo 正中心：文字从图形内部钻出，向右飞过右侧花瓣
	function revealLine():Float
	{
		return center.x;
	}

	function drawPetal(points:Array<Float>, color:Int):FlxSprite
	{
		var shape = new Shape();
		shape.graphics.beginFill(color);
		shape.graphics.moveTo(points[0], points[1]);
		var i = 2;
		while (i < points.length)
		{
			shape.graphics.lineTo(points[i], points[i + 1]);
			i += 2;
		}
		shape.graphics.endFill();

		var bmp = new BitmapData(PETAL_SIZE, PETAL_SIZE, true, 0);
		var m = new Matrix(1, 0, 0, 1, PETAL_SIZE / 2, PETAL_SIZE / 2); // 中心对齐到位图中心
		bmp.draw(shape, m);

		var s = new FlxSprite();
		s.loadGraphic(bmp);
		return s;
	}

	function outro():Void
	{
		if (skipping)
			return;
		skipping = true;

		// 整体放大、旋转并淡出，然后进入标题（每瓣绕自身中心旋转，保持居中）
		for (p in petals)
		{
			FlxTween.tween(p, {alpha: 0, angle: p.angle + 90, 'scale.x': 1.8, 'scale.y': 1.8}, 0.7, {ease: FlxEase.quadIn});
		}
		FlxTween.tween(label, {alpha: 0}, 0.7, {ease: FlxEase.quadIn, onComplete: (_) -> switchState()});
	}

	// 跳过（用户输入触发）：用相机级淡黑让画面整体变暗。
	// 相机特效绘制在所有精灵之上（含后续迸发的火花/粒子），且完全不触碰任何底层 tween，
	// 因此既保证「整体变暗且置于游戏最顶层」，又不会出现「动效被打乱」的情况。
	function skipToDark():Void
	{
		if (skipping)
			return;
		skipping = true;

		// 注意：完成时【不要】在此 stopFX() 清掉黑屏——onComplete 在 cameras.update() 内触发，
		// 而当前步的绘制仍由旧开屏状态负责；若此刻清黑，旧画面会在无黑遮罩下被画一帧（即「闪一下」）。
		// 保持黑屏，仅请求切换状态；flixel 在切状态时会对相机 reset()（销毁旧相机、新建干净相机），
		// 黑屏特效随之清除，不会带入下一个状态，也不会有闪屏。
		FlxG.camera.fade(FlxColor.BLACK, 0.45, false, () -> switchState());
	}

	function switchState():Void
	{
		FlxG.camera.bgColor = _cachedBgColor;
		#if MODS_ALLOWED
		if (Main.commandLineLaunch != null)
		{
			states.CommandLineLaunchState.launchData = Main.commandLineLaunch;
			FlxG.switchState(new states.CommandLineLaunchState());
			return;
		}
		#end
		FlxG.switchState(new states.TitleState());
	}

	override function update(elapsed:Float):Void
	{
		super.update(elapsed);

		// 成型后风车持续缓慢自转 + 轻微脉冲缩放
		if (formed && !skipping && !bouncing)
		{
			for (p in petals)
			{
				p.angle += 24 * elapsed;
				var s = 1 + 0.04 * Math.sin(FlxG.game.ticks / 220);
				p.scale.set(s, s);
			}
		}

		// 任意按键 / 鼠标 / 触屏 可跳过
		// 注意：不再直接调用 outro()（那会操底层花瓣 tween，导致其与原「砸入」/回弹 tween 打架、动效被打乱），
		// 而是用相机级淡黑让画面整体变暗，底层 tween 照常运行，达到「跳过」效果。
		// 移动端补上 touches 检测：部分 ROM 上触摸不会映射成 FlxG.mouse.justPressed。
		var touchSkip:Bool = false;
		if (FlxG.touches != null)
		{
			for (touch in FlxG.touches.list)
			{
				if (touch.justPressed)
				{
					touchSkip = true;
					break;
				}
			}
		}
		if (!skipping && (FlxG.keys.firstJustPressed() != -1 || FlxG.mouse.justPressed || touchSkip))
			skipToDark();
	}

	override public function onResize(Width:Int, Height:Int):Void
	{
		super.onResize(Width, Height);
		// 注意：Width/Height 是实际舞台像素尺寸，花瓣使用 1280x720 逻辑坐标系，
		// 必须按 FlxG.width/FlxG.height 重新居中，不能用传入的舞台像素。
		center.set(FlxG.width / 2, FlxG.height / 2);
		// 仅在成型/收尾后重定位：避免开场飞入途中被 resize 强行弹回中心
		if (formed || skipping)
		{
			for (p in petals)
				p.setPosition(center.x - PETAL_SIZE / 2, center.y - PETAL_SIZE / 2);
		}
		if (greenBlock != null)
		{
			greenBlock.setPosition(center.x - PETAL_SIZE / 2, center.y - PETAL_SIZE / 2);
		}
		if (label != null)
		{
			label.y = center.y - 26; // 两行块垂直居中
			label.x = textRevealed ? endLabelX() : startLabelX();
		}
		if (maskBar != null)
		{
			maskBar.setPosition(0, center.y - 50);
			var barW:Int = Math.floor(revealLine());
			// makeGraphic 会重建底层 BitmapData，尺寸没变时跳过，避免 resize 抖动时反复分配贴图
			if (maskBar.width != barW || maskBar.height != 100)
				maskBar.makeGraphic(barW, 100, FlxColor.BLACK);
		}
		if (emitter != null)
			emitter.setPosition(center.x, center.y);
	}

	override function destroy():Void
	{
		// 统一取消本 state 创建的 timer：尤其那个无限循环的文字变色 timer，
		// 不取消会随切状态继续在后台跑，反复触发已销毁 label 的 remove/addFormat。
		for (timer in timers)
			timer.cancel();
		timers.resize(0);
		FlxG.camera.bgColor = _cachedBgColor;
		super.destroy();
	}
}
