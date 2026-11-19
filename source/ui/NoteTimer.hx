package ui;

import flixel.FlxSprite;
import flixel.math.FlxMath;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import flixel.group.FlxSpriteGroup;
import states.PlayState;
import backend.Conductor;

/**
 * 圆形倒计时 Shader —— 按 percent (0~1) 裁剪 circleThing 贴图为扇形进度环。
 * 逐字节移植自 Leather Engine：仅 fragment + #pragma header，无自定义 vertex。
 * vertex 交给 flixel 默认 FlxShader，它负责正确传递 alpha/colorTransform 等 attribute。
 */
class CircleShader extends flixel.system.FlxAssets.FlxShader
{
	@:glFragmentSource('
		#pragma header

		float PI = 3.14159265358;
		uniform float percent;

		vec2 rotate(vec2 v, float a) {
			float s = sin(a);
			float c = cos(a);
			mat2 m = mat2(c, -s, s, c);
			return m * v;
		}

		void main()
		{
			vec2 uv = openfl_TextureCoordv;
			vec4 spritecolor = flixel_texture2D(bitmap, openfl_TextureCoordv);

			uv -= vec2(0.5, 0.5);
			uv = rotate(uv, PI * 0.5);
			uv += vec2(0.5, 0.5);

			float percentAngle = (percent * 360.0) / (180.0 / PI);

			vec2 center = vec2(0.5, 0.5);
			float radius = 0.5;
			float angle = atan(uv.y - center.y, uv.x - center.x);
			float distance = length(uv - center);

			if ((angle + (PI)) > percentAngle)
			{
				spritecolor = vec4(0.0, 0.0, 0.0, 0.0);
			}

			gl_FragColor = spritecolor;
		}')

	public function new()
	{
		super();
		this.percent.value = [0.0];
	}
}

/**
 * 箭头倒计时：当两箭头间隔 ≥ 3秒 时，在屏幕中央偏上/偏下显示圆形进度圈 + 整数秒数字。
 *
 * 玩家过滤：只对"人类玩家控制侧"的箭头做倒计时。
 *   普通模式   → bf 侧（mustPress=true）
 *   playOpponent → dad 侧（mustPress=false）
 * 完全兼容 KathyEngine 的对手游玩特性，由 PlayState.isPlayerNote() 提供侧别判定。
 *
 * 逐行逻辑对齐 Leather Engine 原版 NoteTimer.hx，仅替换包名与玩家过滤函数。
 */
class NoteTimer extends FlxSpriteGroup
{
	private var instance:PlayState;
	private var timerText:FlxText;
	private var timerCircle:FlxSprite;
	private var circleShader:CircleShader = new CircleShader();

	public function new(instance:PlayState)
	{
		super();
		this.instance = instance;

		timerCircle = new FlxSprite().loadGraphic(backend.Paths.image("circleThing"));
		if (timerCircle != null && timerCircle.graphic != null)
		{
			timerCircle.antialiasing = true;
			timerCircle.shader = circleShader;
			timerCircle.scale *= 0.75;
			timerCircle.updateHitbox();
			add(timerCircle);
		}

		timerText = new FlxText(0, 0, 0, "");
		timerText.setFormat(backend.Paths.font("vcr.ttf"), 24, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		add(timerText);

		timerCircle.screenCenter();
		timerText.screenCenter();

		circleShader.percent.value = [0.0];
	}

	private var lastStartTime:Float = 1e10;
	private var prevShownNum:Int = -1; // 上一次显示的数字，用于检测变化触发跳动
	private var textScale:Float = 1.0; // 数字文本的实时缩放
	private var initialUnits:Float = 0; // 进入倒计时时的初始 beat/秒 数（跳剪模式用作 percent 分母）

	override public function update(elapsed:Float):Void
	{
		super.update(elapsed);

		var timeTillNextNote:Float = 1e10;

		if (instance != null)
		{
			var show:Bool = false;
			if (Conductor.songPosition > 0)
			{
				for (daNote in instance.notes)
					if (daNote.exists && instance.isPlayerNote(daNote))
					{
						var timeDiff:Float = daNote.strumTime - Conductor.songPosition;
						if (timeDiff < timeTillNextNote)
							timeTillNextNote = timeDiff;
					}

				if (timeTillNextNote == 1e10)
					for (daNote in instance.unspawnNotes)
						if (instance.isPlayerNote(daNote))
						{
							var timeDiff:Float = daNote.strumTime - Conductor.songPosition;
							if (timeDiff < timeTillNextNote)
							{
								timeTillNextNote = timeDiff;
								break;
							}
						}

				show = timeTillNextNote != 1e10;
			}

			var targetAlpha:Float = 0.0;
			if (show)
			{
				if (lastStartTime == 1e10 && timeTillNextNote > 3000)
				{
					lastStartTime = timeTillNextNote;
					// 记录进入倒计时时的初始单位数（跳剪模式下 percent 用这个做分母）
					var mode:String = backend.ClientPrefs.data.noteTimerDisplay;
					if (mode == 'Beats' && backend.Conductor.crochet > 0)
						initialUnits = Math.ceil(timeTillNextNote / backend.Conductor.crochet);
					else
						initialUnits = Math.ceil(timeTillNextNote * 0.001);
				}

				if (lastStartTime != 1e10)
				{
					var numLeft:Float;
					var mode:String = backend.ClientPrefs.data.noteTimerDisplay;
					var useBeats:Bool = (mode == 'Beats' && backend.Conductor.crochet > 0);
					if (useBeats)
						numLeft = Math.ceil(timeTillNextNote / backend.Conductor.crochet);
					else
						numLeft = Math.ceil(timeTillNextNote * 0.001);

					// 圆环裁剪：丝滑连续 vs 按 beat/秒 跳变
					var percent:Float;
					if (backend.ClientPrefs.data.noteTimerStepped && initialUnits > 0)
						percent = numLeft / initialUnits; // 跳变：percent 只在整数跳时变
					else
						percent = timeTillNextNote / lastStartTime; // 丝滑：每帧都在变

					if (percent <= 0.0)
					{
						lastStartTime = 1e10;
						initialUnits = 0;
						prevShownNum = -1;
						timerText.text = "";
						circleShader.percent.value = [0.0];
					}
					else
					{
						circleShader.percent.value = [percent];
						var curNum:Int = Std.int(numLeft);
						timerText.text = curNum + "";
						// 数字变化时触发放大跳动（仅在「跳剪」动效启用时；Beats 模式每拍都变 → 很密集）
						if (curNum != prevShownNum)
						{
							prevShownNum = curNum;
							if (backend.ClientPrefs.data.noteTimerStepped)
								textScale = 1.55; // 瞬时放大
						}
					}
					updatePosition();
				}

				if (timeTillNextNote > 1000)
					targetAlpha = 1.0;
			}

			// 放大效果每帧 lerp 回 1.0，形成弹性衰减；关闭「跳剪」时直接锁定默认大小
			if (backend.ClientPrefs.data.noteTimerStepped)
				textScale = FlxMath.lerp(textScale, 1.0, elapsed * 10);
			else
				textScale = 1.0;
			timerText.scale.set(textScale, textScale);

			timerText.alpha = FlxMath.lerp(timerText.alpha, targetAlpha, elapsed * 5);
			timerCircle.alpha = timerText.alpha;
		}
	}

	private function updatePosition():Void
	{
		timerCircle.screenCenter();
		timerText.screenCenter();
		if (backend.ClientPrefs.data.downScroll)
		{
			timerCircle.y += 260;
			timerText.y += 260;
		}
		else
		{
			timerCircle.y -= 260;
			timerText.y -= 260;
		}
	}
}
