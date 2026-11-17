package states;

import Main;
import states.CommandLineLaunchState;
import states.TitleState;
import backend.Language;
import openfl.Assets;
import openfl.display.BitmapData;
import openfl.display.GradientType;
import openfl.display.Shape;
import openfl.geom.Matrix;

/**
 * 开屏 Logo 画面（Kathy 默认开屏）
 *
 * 构图（除 logo 外全部程序生成）：
 *   1. 深紫渐变舞台背景（持续向上流动）+ 开场向上冲的速度线
 *   2. logo（渐显清晰）与其下方图层的柔和配色 flixel 风车
 *   3. 中间光晕（第三音调后渐显）
 *   4. 底部文本按 Ka → Kathy → Kathy Engine 逐段出现，各段不同颜色，再画装饰线
 *   5. 顶部“按键/触屏跳过”提示（跟随语言包）
 *
 * 音效 bells-logo 三个音调：0.162s / 0.436s / 0.702s。
 * 画面先动、音频随后播，音调节点以音频播放时刻为基准对齐。
 * 收尾整体下潜（含装饰线与提示）；全平台可点击/触摸/按键跳过；timer 统一取消。
 */
class LogoState extends MusicBeatState
{
	static final BELL_TIMES:Array<Float> = [0.162, 0.436, 0.702];
	static final BELL_TEXTS:Array<String> = ["Ka", "Kathy", "Kathy Engine"];
	static final BELL_COLORS:Array<Int> = [0xA8D8F5, 0x8FE08F, 0xFFC9D4];
	static final TEXT_ORANGE:Int = 0xFFB27A;
	static final FLIXEL_COLORS:Array<Int> = [0x5FC98A, 0xF2C968, 0xEE7A94, 0x8794EA, 0x7FD8E8];
	static final PETALS:Array<Array<Float>> = [
		[0, -37, 1, -37, 37, 0, 37, 1, 1, 37, 0, 37, -37, 1, -37, 0],
		[-50, -50, -25, -50, 0, -37, -37, 0, -50, -25],
		[50, -50, 25, -50, 1, -37, 37, 0, 50, -25],
		[-50, 50, -25, 50, 0, 37, -37, 1, -50, 25],
		[50, 50, 25, 50, 1, 37, 37, 1, 50, 25]
	];

	static var bgGradient:BitmapData;
	static var glowBitmap:BitmapData;
	static var flixelBitmap:BitmapData;
	static var streakBitmap:BitmapData;

	var bg:FlxSprite;
	var streaks:Array<FlxSprite> = [];
	var streakSpeeds:Array<Float> = [];
	var halo:FlxSprite;
	var particles:Array<FlxSprite> = [];
	var particleSpeeds:Array<Float> = [];
	var particlePhases:Array<Float> = [];
	var particleBaseAlpha:Array<Float> = [];
	var flixelIcon:FlxSprite;
	var logo:FlxSprite;
	var titleText:FlxText;
	var titleLine:FlxSprite;
	var skipBg:FlxSprite;
	var skipText:FlxText;

	var finalScale:Float = 1;
	var haloScale:Float = 1;
	var logoCX:Float = 0;
	var logoCY:Float = 0;
	var logoLeftCX:Float = 0;
	var flixelCX:Float = 0;
	var flixelCY:Float = 0;
	var flixelTargetCX:Float = 0;
	var haloCX:Float = 0;
	var haloCY:Float = 0;
	var titleBaseY:Float = 0;
	var lineBaseY:Float = 0;
	var cachedBgColor:FlxColor;

	var textStage:Int = -1;
	var streaksActive:Bool = true;
	var bgScroll:Bool = false;
	var bgY:Float = 0;

	var timers:Array<FlxTimer> = [];
	var finished:Bool = false;
	var skipped:Bool = false;
	var holding:Bool = false;
	var diving:Bool = false;

	function trackTimer(timer:FlxTimer):FlxTimer
	{
		timers.push(timer);
		return timer;
	}

	function centerSprite(spr:FlxSprite, cx:Float, cy:Float):Void
	{
		spr.x = cx - spr.origin.x;
		spr.y = cy - spr.origin.y;
	}

	override function create():Void
	{
		super.create();

		cachedBgColor = FlxG.camera.bgColor;
		FlxG.camera.bgColor = FlxColor.BLACK;
		FlxG.mouse.visible = false;

		var cx:Float = FlxG.width / 2;
		var cy:Float = FlxG.height / 2;

		// —— 1. 渐变舞台背景（画成 2 屏高，滚动 1 屏高度可无缝循环）——
		bg = new FlxSprite().loadGraphic(getBgGradient());
		bg.setGraphicSize(FlxG.width, FlxG.height * 2);
		bg.updateHitbox();
		bg.origin.set(0, 0);
		bg.x = 0;
		bg.y = 0;
		bgY = 0;
		bg.scrollFactor.set();
		add(bg);

		// —— 2. 开场速度线 ——
		for (i in 0...22)
		{
			var s = new FlxSprite().loadGraphic(getStreakBitmap());
			s.alpha = 0;
			var sc:Float = 0.5 + Math.random() * 1.9;
			s.scale.set(sc, sc);
			s.x = Math.random() * FlxG.width;
			s.y = Math.random() * FlxG.height;
			s.scrollFactor.set();
			add(s);
			streaks.push(s);
			streakSpeeds.push(260 + Math.random() * 620);
			FlxTween.tween(s, {alpha: 0.18 + Math.random() * 0.32}, 0.25 + Math.random() * 0.2, {ease: FlxEase.sineOut});
		}

		// —— 3. 中间光晕（第三音调后渐显）——
		halo = new FlxSprite().loadGraphic(getGlowBitmap());
		halo.origin.set(halo.width / 2, halo.height / 2);
		haloCX = cx;
		haloCY = cy - 26;
		centerSprite(halo, haloCX, haloCY);
		haloScale = (FlxG.height * 0.78) / halo.width;
		halo.scale.set(haloScale, haloScale);
		halo.color = 0xFF9FD8;
		halo.alpha = 0;
		halo.scrollFactor.set();
		add(halo);

		// —— 4. 漂浮光点（向上）——
		var lightColors:Array<Int> = [0xFFD9EC, 0xFFFFFF, 0xE8DCFF, 0xFFE8F0];
		for (i in 0...26)
		{
			var p = new FlxSprite().loadGraphic(getGlowBitmap());
			var s = 0.09 + Math.random() * 0.16;
			p.scale.set(s, s);
			p.color = lightColors[i % lightColors.length];
			p.alpha = 0;
			p.x = Math.random() * FlxG.width;
			p.y = Math.random() * FlxG.height;
			p.scrollFactor.set();
			add(p);

			particles.push(p);
			particleSpeeds.push(9 + Math.random() * 20);
			// 预存归一化相位（原 phase/1400），避免 update 里每帧做除法
			particlePhases.push(Math.random() * 1000 / 1400);
			particleBaseAlpha.push(0.14 + Math.random() * 0.22);
		}

		// —— 5a. flixel 风车（先加入 → 位于 logo 图层下方，初始藏在 logo 中心）——
		flixelIcon = new FlxSprite().loadGraphic(getFlixelBitmap());
		flixelIcon.antialiasing = ClientPrefs.data.antialiasing;
		flixelIcon.origin.set(flixelIcon.width / 2, flixelIcon.height / 2);
		flixelCX = cx - 62;
		flixelCY = cy - 30;
		flixelTargetCX = cx + (Math.min(FlxG.height * 0.60, FlxG.width * 0.66)) / 2 + 26;
		centerSprite(flixelIcon, flixelCX, flixelCY);
		flixelIcon.alpha = 0;
		flixelIcon.scale.set(0.3, 0.3);
		flixelIcon.angle = -45;
		flixelIcon.scrollFactor.set();
		add(flixelIcon);

		// —— 5b. logo（后加入 → 位于风车上方，渐显清晰）——
		logo = new FlxSprite().loadGraphic(Paths.image('logo'));
		logo.antialiasing = ClientPrefs.data.antialiasing;
		finalScale = Math.min(FlxG.height * 0.60, FlxG.width * 0.66) / logo.frameHeight;
		logo.scale.set(finalScale, finalScale);
		logo.origin.set(logo.frameWidth / 2, logo.frameHeight / 2);
		logoCX = cx - 62;
		logoCY = cy - 30;
		logoLeftCX = cx - 84;
		centerSprite(logo, logoCX, logoCY);
		logo.alpha = 0;
		logo.scale.set(finalScale * 1.05, finalScale * 1.05); // 从略放大收敛到清晰
		add(logo);

		// —— 5c. 底部文字与装饰线（线先 add → 图层在文字下方）——
		var fontName:String = Assets.getFont("assets/fonts/BlackSugarPlumCandy-Bold.ttf").fontName;
		titleBaseY = FlxG.height - 104;
		lineBaseY = titleBaseY + 64;

		// 装饰线（加粗）——先加入，位于文字下方
		titleLine = new FlxSprite();
		titleLine.makeGraphic(300, 4, 0xBBFFD0EA);
		titleLine.origin.set(titleLine.width / 2, titleLine.height / 2);
		centerSprite(titleLine, cx, lineBaseY);
		titleLine.scale.x = 0;
		titleLine.alpha = 0;
		titleLine.scrollFactor.set();
		add(titleLine);

		// 标题文字（Ka → Kathy → Kathy Engine）——后加入，位于线上方
		titleText = new FlxText(0, 0, FlxG.width, "");
		titleText.setFormat(fontName, 52, 0xFFF3F8, CENTER,
			flixel.text.FlxText.FlxTextBorderStyle.OUTLINE, 0x6B2F5E);
		titleText.y = titleBaseY;
		titleText.scrollFactor.set();
		add(titleText);

		// —— 6. 顶部跳过提示（黑块背景 + 语言包文案）——
		#if mobile
		var hint:String = Language.get('logo_skip_hint_touch');
		#else
		var hint:String = Language.get('logo_skip_hint_key');
		#end
		// 不先 makeGraphic(1,1)：layoutHint() 紧接着会按实际宽度建一次，
		// 提前建一张再丢弃是无谓的纹理分配。
		skipBg = new FlxSprite();
		skipBg.scrollFactor.set();
		add(skipBg);
		skipText = new FlxText(0, 0, FlxG.width, hint);
		skipText.setFormat(fontName, 20, 0xFFEFE6, CENTER,
			flixel.text.FlxText.FlxTextBorderStyle.OUTLINE, 0x000000);
		skipText.scrollFactor.set();
		add(skipText);
		layoutHint();

		// —— 时间轴 ——
		// 背景先动；logo 与 flixel 严格等音频第一个音调节点之后才出场
		trackTimer(new FlxTimer()).start(0.14, (_) -> bgScroll = true);

		// 音频随后播，音调节点以播放时刻为基准
		trackTimer(new FlxTimer()).start(0.5, (_) ->
		{
			FlxG.sound.play(Paths.sound('KYE/bells-logo'), 1);
			for (i in 0...BELL_TIMES.length)
				trackTimer(new FlxTimer()).start(BELL_TIMES[i], (_) -> {
					showText(i);
					if (i == 0) revealLogo(); // 第一个音调节点后 logo 才开始渐显，flixel 随后跟进
				});

			trackTimer(new FlxTimer()).start(BELL_TIMES[2] + 0.16, (_) ->
			{
				FlxTween.tween(halo, {alpha: 0.7}, 0.6, {ease: FlxEase.sineOut});
				trackTimer(new FlxTimer()).start(0.28, (_) ->
				{
					FlxTween.tween(titleLine, {'scale.x': 1, alpha: 1}, 0.5, {ease: FlxEase.quadOut});
				});
			});

			// 收尾下潜（比上一版更晚，总时长更长）
			trackTimer(new FlxTimer()).start(2.55, (_) -> beginDive());
		});

		trackTimer(new FlxTimer()).start(1.0, (_) ->
		{
			for (s in streaks)
				FlxTween.tween(s, {alpha: 0}, 0.5, {
					ease: FlxEase.quadIn,
					onComplete: (_) -> {
						s.visible = false;
						streaksActive = false;
					}
				});
		});

		#if mobile
		// 开屏靠全屏触摸（update 里的 touchSkip）跳过，不需要虚拟键；
		// 这里只确保 MobileData 已初始化，供后续 TitleState 复用。
		if (MobileData.actionModes == null || !MobileData.actionModes.exists('A'))
			MobileData.init();
		#end
	}

	function layoutHint():Void
	{
		if (skipText == null || skipBg == null)
			return;
		skipText.fieldWidth = FlxG.width;
		skipText.x = 0;
		skipText.y = 26;
		var w:Float = Math.min(FlxG.width - 40, skipText.text.length * 15 + 44);
		skipBg.makeGraphic(Std.int(w), 38, 0x99000000);
		skipBg.x = (FlxG.width - w) / 2;
		skipBg.y = 22;
	}

	function revealLogo():Void
	{
		if (skipped || finished)
			return;
		FlxTween.cancelTweensOf(logo);
		FlxTween.tween(logo, {
			alpha: 1,
			'scale.x': finalScale, 'scale.y': finalScale
		}, 0.8, {
			ease: FlxEase.sineInOut,
			onComplete: (_) ->
			{
				if (skipped || finished)
					return;
				holding = true;
				var fx:Float = flixelTargetCX;
				FlxTween.tween(flixelIcon, {
					x: fx - flixelIcon.origin.x, alpha: 1, angle: 0,
					'scale.x': 1, 'scale.y': 1
				}, 0.6, {ease: FlxEase.backOut});
				FlxTween.tween(logo, {x: logoLeftCX - logo.origin.x}, 0.6, {ease: FlxEase.quadOut});
			}
		});
	}

	function showText(stage:Int):Void
	{
		if (skipped || finished || stage <= textStage)
			return;
		textStage = stage;
		titleText.text = BELL_TEXTS[stage];
		titleText.alpha = 0;
		titleText.y = titleBaseY + 16;
		titleText.color = BELL_COLORS[stage];
		FlxTween.cancelTweensOf(titleText);
		FlxTween.tween(titleText, {alpha: 1, y: titleBaseY}, 0.3, {ease: FlxEase.backOut});

		if (stage == 2)
		{
			var mix = {v: 0.0};
			var lastStep:Int = -1;
			FlxTween.tween(mix, {v: 1}, 0.9, {
				ease: FlxEase.sineInOut,
				onUpdate: (_) ->
				{
					if (skipped || finished)
						return;
					// FlxText 每次改 color 都会 updateDefaultFormat() -> _regen=true，
					// 下一帧 draw() 要把带 OUTLINE 的整段文字重新光栅化进 BitmapData。
					// 0.9s 渐变量化成 16 档：约 16 次重绘而非 54 次，肉眼无差。
					var step:Int = Std.int(mix.v * 16);
					if (step != lastStep)
					{
						lastStep = step;
						titleText.color = FlxColor.interpolate(BELL_COLORS[2], TEXT_ORANGE, step / 16);
					}
				}
			});
		}
	}

	override function update(elapsed:Float):Void
	{
		super.update(elapsed);

		if (!skipped && !diving)
		{
			if (bgScroll)
			{
				bgY -= 34 * elapsed;
				if (bgY <= -FlxG.height)
					bgY += FlxG.height;
				bg.y = bgY;
			}
			// 循环外预读与常量化：避免 26 次属性读 + 除法
			var tickPhase:Float = FlxG.game.ticks * 0.000714285714; // 1/1400
			var edge:Float = 60;
			var invEdge:Float = 1 / edge;
			var bottom:Float = FlxG.height - edge;
			for (i in 0...particles.length)
			{
				var p = particles[i];
				p.y -= particleSpeeds[i] * elapsed;
				p.x += Math.sin(tickPhase + particlePhases[i]) * 0.28;
				if (p.y < -40)
				{
					p.y = FlxG.height + 40;
					p.x = Math.random() * FlxG.width;
				}
				var fade:Float = 1;
				if (p.y > bottom)
					fade = (bottom - p.y) * invEdge + 1;
				else if (p.y < edge)
					fade = (p.y + 40) * 0.01; // /(edge+40)
				var a:Float = particleBaseAlpha[i] * Math.max(0, Math.min(1, fade));
				// alpha 极小时直接置 0，让 FlxSprite.draw() 首行 return 跳过整块渲染
				p.alpha = a < 0.01 ? 0 : a;
			}
			if (streaksActive)
			{
				for (i in 0...streaks.length)
				{
					var s = streaks[i];
					s.y -= streakSpeeds[i] * elapsed;
					if (s.y < -80)
					{
						s.y = FlxG.height + 80;
						s.x = Math.random() * FlxG.width;
					}
				}
			}
		}

		if (holding && !skipped)
		{
			var t:Float = FlxG.game.ticks / 1000;
			logo.y = logoCY - logo.origin.y + 2.5 * Math.sin(t * 1.7);
			var breathe:Float = 1 + 0.01 * Math.sin(t * 2.2);
			logo.scale.set(finalScale * breathe, finalScale * breathe);
		}

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
		if (!skipped && (controls.ACCEPT || controls.BACK || touchSkip #if desktop || FlxG.keys.justPressed.ANY #end))
			skipLogo();
	}

	function beginDive():Void
	{
		if (skipped || finished)
			return;
		holding = false;
		diving = true;
		streaksActive = false;
		bgScroll = false;

		FlxTween.tween(logo, {
			alpha: 0, y: logoCY - logo.origin.y + 54,
			'scale.x': finalScale * 1.05, 'scale.y': finalScale * 1.05, angle: 4
		}, 0.7, {ease: FlxEase.quadIn});
		FlxTween.tween(flixelIcon, {
			alpha: 0, y: flixelCY - flixelIcon.origin.y + 64, 'scale.x': 1.2, 'scale.y': 1.2
		}, 0.7, {ease: FlxEase.quadIn});
		FlxTween.tween(titleText, {alpha: 0, y: titleBaseY + 44}, 0.7, {ease: FlxEase.quadIn});
		FlxTween.tween(titleLine, {alpha: 0, y: lineBaseY + 44}, 0.7, {ease: FlxEase.quadIn});
		FlxTween.tween(halo, {alpha: 0, y: haloCY - halo.origin.y + 60}, 0.7, {ease: FlxEase.quadIn});
		FlxTween.tween(skipBg, {alpha: 0, y: skipBg.y + 40}, 0.7, {ease: FlxEase.quadIn});
		FlxTween.tween(skipText, {alpha: 0, y: skipText.y + 40}, 0.7, {ease: FlxEase.quadIn});
		for (p in particles)
			FlxTween.tween(p, {alpha: 0, y: p.y + 50}, 0.7, {ease: FlxEase.quadIn});

		trackTimer(new FlxTimer()).start(0.72, (_) -> finishLogo());
	}

	function skipLogo():Void
	{
		if (skipped)
			return;
		skipped = true;

		for (timer in timers) timer.cancel();
		timers.resize(0);
		FlxTween.cancelTweensOf(logo);
		FlxTween.cancelTweensOf(flixelIcon);
		FlxTween.cancelTweensOf(halo);
		FlxTween.cancelTweensOf(titleText);
		FlxTween.cancelTweensOf(titleLine);
		FlxTween.cancelTweensOf(skipBg);
		FlxTween.cancelTweensOf(skipText);
		for (p in particles)
			FlxTween.cancelTweensOf(p);
		for (s in streaks)
			FlxTween.cancelTweensOf(s);
		finishLogo();
	}

	function finishLogo():Void
	{
		if (finished)
			return;
		finished = true;

		#if MODS_ALLOWED
		if (Main.commandLineLaunch != null)
		{
			CommandLineLaunchState.launchData = Main.commandLineLaunch;
			MusicBeatState.switchState(new CommandLineLaunchState());
			return;
		}
		#end

		MusicBeatState.switchState(new TitleState());
	}

	override public function onResize(Width:Int, Height:Int):Void
	{
		super.onResize(Width, Height);
		if (bg == null) return;

		bg.setGraphicSize(FlxG.width, FlxG.height * 2);
		bg.updateHitbox();
		var cx:Float = FlxG.width / 2;
		var cy:Float = FlxG.height / 2;

		if (logo != null)
		{
			finalScale = Math.min(FlxG.height * 0.60, FlxG.width * 0.66) / logo.frameHeight;
			logoCX = cx - 62;
			logoLeftCX = cx - 84;
			logoCY = cy - 30;
			centerSprite(logo, holding ? logoLeftCX : logoCX, logoCY);
			logo.scale.set(finalScale, finalScale);
		}
		if (flixelIcon != null)
		{
			flixelCX = cx - 62;
			flixelCY = cy - 30;
			flixelTargetCX = cx + Math.min(FlxG.height * 0.60, FlxG.width * 0.66) / 2 + 26;
			flixelIcon.y = flixelCY - flixelIcon.origin.y;
		}
		if (halo != null)
		{
			haloCX = cx;
			haloCY = cy - 26;
			centerSprite(halo, haloCX, haloCY);
			haloScale = (FlxG.height * 0.78) / halo.width;
			halo.scale.set(haloScale, haloScale);
		}
		if (titleText != null)
		{
			titleText.fieldWidth = FlxG.width;
			titleBaseY = FlxG.height - 104;
			titleText.x = 0;
			titleText.y = titleBaseY;
		}
		if (titleLine != null)
		{
			lineBaseY = titleBaseY + 64;
			centerSprite(titleLine, cx, lineBaseY);
		}
		layoutHint();
	}

	override function destroy():Void
	{
		for (timer in timers) timer.cancel();
		timers.resize(0);
		FlxG.camera.bgColor = cachedBgColor;
		super.destroy();
	}

	static function getBgGradient():BitmapData
	{
		if (bgGradient == null)
		{
			// 每个 256px 周期必须首尾同色，否则周期交界处会出现一条横贯全屏的硬色带，
			// 随背景以 34px/s 上滚时看起来像"从底部飞入的粉色块"。
			// 用余弦波让 0→1→0 平滑往返，t=0 与 t=1 都为暗色，循环无缝。
			bgGradient = new BitmapData(1, 512, false);
			for (y in 0...512)
			{
				var t:Float = (y % 256) / 255;
				var wave:Float = 0.5 - 0.5 * Math.cos(t * Math.PI * 2);
				var r:Int = Std.int(12 + 30 * wave);
				var g:Int = Std.int(8 + 18 * wave);
				var b:Int = Std.int(20 + 40 * wave);
				bgGradient.setPixel(0, y, (r << 16) | (g << 8) | b);
			}
		}
		return bgGradient;
	}

	static function getGlowBitmap():BitmapData
	{
		if (glowBitmap == null)
		{
			var size:Int = 128;
			var shape = new Shape();
			var m = new Matrix();
			m.createGradientBox(size, size, 0, 0, 0);
			shape.graphics.beginGradientFill(GradientType.RADIAL,
				[0xFFFFFF, 0xFFFFFF], [0.9, 0], [0, 255], m);
			shape.graphics.drawCircle(size / 2, size / 2, size / 2);
			shape.graphics.endFill();

			glowBitmap = new BitmapData(size, size, true, 0);
			glowBitmap.draw(shape);
		}
		return glowBitmap;
	}

	static function getStreakBitmap():BitmapData
	{
		if (streakBitmap == null)
		{
			var w:Int = 3;
			var h:Int = 96;
			streakBitmap = new BitmapData(w, h, true, 0);
			for (y in 0...h)
			{
				var t:Float = 1 - y / (h - 1);
				var a:Int = Std.int(150 * t * t);
				for (x in 0...w)
					streakBitmap.setPixel32(x, y, (a << 24) | 0xFFD0EA);
			}
		}
		return streakBitmap;
	}

	static function getFlixelBitmap():BitmapData
	{
		if (flixelBitmap == null)
		{
			var size:Int = 128;
			var shape = new Shape();
			for (i in 0...PETALS.length)
			{
				var pts = PETALS[i];
				shape.graphics.beginFill(FLIXEL_COLORS[i]);
				shape.graphics.moveTo(pts[0], pts[1]);
				var j = 2;
				while (j < pts.length)
				{
					shape.graphics.lineTo(pts[j], pts[j + 1]);
					j += 2;
				}
				shape.graphics.endFill();
			}

			flixelBitmap = new BitmapData(size, size, true, 0);
			var m = new Matrix(1, 0, 0, 1, size / 2, size / 2);
			flixelBitmap.draw(shape, m);
		}
		return flixelBitmap;
	}
}
