package objects;

import backend.Conductor;
import backend.animation.PsychAnimationController;
import backend.ExtraKeysHandler;
import backend.InputFormatter;
import backend.Paths;

import flixel.FlxSprite;
import flixel.FlxBasic;
import flixel.FlxCamera;
import flixel.math.FlxPoint;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.text.FlxText;
import flixel.util.FlxTimer;
import flixel.util.FlxColor;
import flixel.tweens.FlxTween;

import shaders.RGBPalette;
import shaders.RGBPalette.RGBShaderReference;
import shaders.ColorSwap;

class StrumNote extends FlxSprite
{
	public var rgbShader:RGBShaderReference;
	public var colorSwap:ColorSwap;
	public var resetAnim:Float = 0;
	public var holdConfirmActive:Bool = false;
	private var noteData:Int = 0;
	// direction 为角度（默认 90，即向上）。缓存 cos/sin 避免每个流动音符每帧各算一次 Math.cos/sin
	// （安卓 HXCPP 上走 C 库调用，高密度谱下数千次/帧）。
	public var direction(default, set):Float = 90;
	public var dirCos:Float = 0; // cos(90°)=0，缓存供流动音符快速路径读取
	public var dirSin:Float = 1; // sin(90°)=1，缓存供流动音符快速路径读取
	public var downScroll:Bool = false;
	public var sustainReduce:Bool = true;
	private var player:Int;

	// 所属侧（LE LTS 双侧：供 NoteHoldCover 等按侧取 strum 缩放；1=玩家、0=对手）
	public function isPlayerSide():Bool
	{
		return player == 1;
	}

	private function set_direction(value:Float):Float {
		if (direction != value) {
			direction = value;
			var rad:Float = value * Math.PI / 180.0;
			dirCos = Math.cos(rad);
			dirSin = Math.sin(rad);
		}
		return value;
	}
	
	public var texture(default, set):String = null;
	private function set_texture(value:String):String {
		if(texture != value) {
			texture = value;
			reloadNote();
		}
		return value;
	}

	public var useRGBShader:Bool = true;
	public function new(x:Float, y:Float, leData:Int, player:Int) {
		animation = new PsychAnimationController(this);

		rgbShader = new RGBShaderReference(this, Note.initializeGlobalRGBShader(Note.styleIndex(leData)));
		rgbShader.enabled = false;
		if(PlayState.SONG != null && PlayState.SONG.disableNoteRGB) useRGBShader = false;
		
		var arr:Array<FlxColor> = ClientPrefs.data.arrowRGB[Note.styleIndex(leData)];
		if(PlayState.isPixelStage) arr = ClientPrefs.data.arrowRGBPixel[Note.styleIndex(leData)];
		
		if(arr != null && arr.length >= 3)
		{
			@:bypassAccessor
			{
				rgbShader.r = arr[0];
				rgbShader.g = arr[1];
				rgbShader.b = arr[2];
			}
		}

		// Legacy HSV path: share the per-direction ColorSwap shader. The sprite
		// starts disabled (null shader = static); playAnim toggles it on/off.
		if(ClientPrefs.data.arrowColorMode == 'HSV') {
			colorSwap = Note.initializeGlobalColorSwapShader(Note.styleIndex(leData));
		}

		noteData = leData;
		this.player = player;
		this.noteData = leData;
		this.ID = noteData;
		super(x, y);

		var skin:String = null;
		if(PlayState.SONG != null && PlayState.SONG.arrowSkin != null && PlayState.SONG.arrowSkin.length > 1) skin = PlayState.SONG.arrowSkin;
		else skin = Note.defaultNoteSkin;

		// 与 Note.reloadNote 一致的皮肤解析：HSV 时优先走 hsv 目录，
		// 保证 StrumNote 与流动音符使用同一套箭头（而非默认/RGB 纹理）。
		// 像素舞台的箭头资源在 pixelUI/ 下，这里的自定义皮肤解析查的是非 pixelUI 路径，
		// 无意义；且 HSV 目录查找统一交给 resolveSkinPath（已支持 pixelUI/<folder>/hsv），
		// 故像素场景跳过此处，避免把含 hsv 的路径再次传入 resolveSkinPath 造成双重查找。
		var customSkin:String = skin + Note.getNoteSkinPostfix();
		var customExists:Bool = false;
		if (!PlayState.isPixelStage)
		{
			if(ClientPrefs.data.arrowColorMode == 'HSV')
			{
				var parts:Array<String> = customSkin.split('/');
				var filename:String = parts.pop();
				var folder:String = parts.join('/');
				customExists = Paths.fileExists('images/$folder/hsv/$filename.png', IMAGE) || Paths.fileExists('images/$customSkin.png', IMAGE);
			}
			else
				customExists = Paths.fileExists('images/$customSkin.png', IMAGE);

			if(!customExists) customSkin = skin;
		}
		skin = Note.getNoteSkinPath(customSkin);

		texture = skin; //Load texture and anims
		scrollFactor.set();

		// LE LTS 双侧：两侧 strum 颜色都按各自运行时档位重算（玩家=totalColumns-1、对手=oppMania），
		// 覆盖 super 前按玩家档的默认值。档位用运行时值（change keycount 改键后重建即用新档），
		// 而非 SONG.keyCount/SONG.mania（保持谱面原始值）。
		if (PlayState.instance != null && PlayState.instance.isLeDualChart)
		{
			var sideManiaC:Int = (player == 1) ? (PlayState.instance.totalColumns - 1) : PlayState.instance.oppMania;
			var styleC:Int = (ExtraKeysHandler.instance != null) ? ExtraKeysHandler.instance.globalIndex(sideManiaC, noteData) : (noteData % 4);
			var arrC:Array<FlxColor> = (styleC > -1 && styleC < ClientPrefs.data.arrowRGB.length) ? ClientPrefs.data.arrowRGB[styleC] : null;
			if(PlayState.isPixelStage && styleC > -1 && styleC < ClientPrefs.data.arrowRGBPixel.length) arrC = ClientPrefs.data.arrowRGBPixel[styleC];
			if(arrC != null && arrC.length >= 3)
			{
				@:bypassAccessor
				{
					rgbShader.r = arrC[0];
					rgbShader.g = arrC[1];
					rgbShader.b = arrC[2];
				}
			}
		}
		playAnim('static');

		// 初始化方向三角函数缓存（与 direction setter 逻辑一致）
		var rad:Float = direction * Math.PI / 180.0;
		dirCos = Math.cos(rad);
		dirSin = Math.sin(rad);
	}

	public function reloadNote()
	{
		var lastAnim:String = null;
		if(animation.curAnim != null) lastAnim = animation.curAnim.name;

		if(PlayState.isPixelStage)
		{
			loadGraphic(Paths.image('pixelUI/' + texture));
			width = width / 4;
			height = height / 5;
			loadGraphic(Paths.image('pixelUI/' + texture), true, Math.floor(width), Math.floor(height));

			antialiasing = false;
			setGraphicSize(Std.int(width * PlayState.daPixelZoom));

			animation.add('green', [6]);
			animation.add('red', [7]);
			animation.add('blue', [5]);
			animation.add('purple', [4]);
			switch (Math.abs(noteData) % 4)
			{
				case 0:
					animation.add('static', [0]);
					animation.add('pressed', [4, 8], 12, false);
					animation.add('confirm', [12, 16], 24, false);
				case 1:
					animation.add('static', [1]);
					animation.add('pressed', [5, 9], 12, false);
					animation.add('confirm', [13, 17], 24, false);
				case 2:
					animation.add('static', [2]);
					animation.add('pressed', [6, 10], 12, false);
					animation.add('confirm', [14, 18], 12, false);
				case 3:
					animation.add('static', [3]);
					animation.add('pressed', [7, 11], 12, false);
					animation.add('confirm', [15, 19], 24, false);
			}
		}
		else
		{
			frames = Paths.getSparrowAtlas(texture);
			animation.addByPrefix('green', 'arrowUP');
			animation.addByPrefix('blue', 'arrowDOWN');
			animation.addByPrefix('purple', 'arrowLEFT');
			animation.addByPrefix('red', 'arrowRIGHT');

			antialiasing = ClientPrefs.data.antialiasing;
			setGraphicSize(Std.int(width * 0.7));

			// 多键：按当前 mania 档位查 extrakeys.json 取 strum 前缀（LEFT/DOWN/UP/RIGHT/ROMBUS/CIRCLE）。
			// UI 态（颜色菜单等）由 Note.uiManiaOverride 接管，游戏内仍用 PlayState.SONG.mania。
			// LE LTS 双侧：两侧 strum 都按各自运行时档位取前缀（玩家=totalColumns-1、对手=oppMania），与玩家侧独立。
			var mania:Int = Note.uiManiaOverride >= 0 ? Note.uiManiaOverride : ((PlayState.SONG != null && PlayState.SONG.mania != null) ? PlayState.SONG.mania : 3);
			if (PlayState.instance != null && PlayState.instance.isLeDualChart)
				mania = (player == 1) ? (PlayState.instance.totalColumns - 1) : PlayState.instance.oppMania;
			var strumName:String = ExtraKeysHandler.instance.strumName(mania, noteData);
			if (!hasFrame('arrow' + strumName)) strumName = 'UP';

			var pressName:String = strumName.toLowerCase() + ' press';
			if (!hasFrame(pressName)) pressName = 'up press';
			var confirmName:String = strumName.toLowerCase() + ' confirm';
			if (!hasFrame(confirmName)) confirmName = 'up confirm';

			animation.addByPrefix('static', 'arrow' + strumName, 24, false);
			animation.addByPrefix('pressed', pressName, 24, false);
			animation.addByPrefix('confirm', confirmName, 24, false);
		}
		updateHitbox();

		if(lastAnim != null)
		{
			playAnim(lastAnim, true);
		}
	}

	// 判断皮肤图集中是否存在名为 `name + '0000'` 的帧（用于缺失动画的回退判断）
	function hasFrame(name:String):Bool
	{
		return frames != null && frames.getByName(name + '0000') != null;
	}

	public function playerPosition()
	{
		x += Note.swagWidth * noteData;
		x += 50;
		x += ((FlxG.width / 2) * player);
	}

	public var lastHoldAnimTime:Float = 0;
	public var isBotplayMode:Bool = false;
	
	override function update(elapsed:Float) {
		// player = 0 是对手箭头，始终能自动恢复
		// player = 1 且 isBotplayMode 是 true，也始终能自动恢复
		// 其他情况受 autoResetStrumAnim 控制
		if(ClientPrefs.data.autoResetStrumAnim || player == 0 || isBotplayMode) {
			if(holdConfirmActive && resetAnim <= 0) {
				// 检查是否很久没有处理 hold note 了
				lastHoldAnimTime += elapsed;
				// 动态获取当前时间的 BPM 信息，计算 2 个 16 分音符的时间（毫秒转秒）
				var currentBPMInfo = Conductor.getBPMFromSeconds(Conductor.songPosition);
				var timeoutSeconds = (currentBPMInfo.stepCrochet * 2) / 1000;
				if(lastHoldAnimTime >= timeoutSeconds) {
					// 超时了，自动重置到 static
					playAnim('static');
					holdConfirmActive = false;
				}
			}
			
			if(resetAnim > 0) {
				resetAnim -= elapsed;
				if(resetAnim <= 0) {
					playAnim('static');
					resetAnim = 0;
					holdConfirmActive = false;
				}
			}
		}
		super.update(elapsed);
	}

	public function playAnim(anim:String, ?force:Bool = false) {
		animation.play(anim, force);
		if(animation.curAnim != null)
		{
			centerOffsets();
			centerOrigin();
		}
		// HSV mode: 始终挂载 ColorSwap 着色器（hue=0 时为恒等变换，仍显示箭头本色），
		// 与流动音符保持一致；修改 arrowHSV 后静态箭头也会同步变色。
		if(ClientPrefs.data.arrowColorMode == 'HSV' && colorSwap != null) {
			shader = colorSwap.shader;
		} else if(useRGBShader) {
			rgbShader.enabled = (animation.curAnim != null && animation.curAnim.name != 'static');
		}
	}
}

/**
 * 开局键位预览（复刻 Psych EK 的 KeybindShowcase）：
 * 在每个玩家 strum 下方短暂显示该轨道绑定的键名，依次展示主/副绑定后自动销毁。
 */
class KeybindShowcase extends FlxTypedGroup<FlxBasic>
{
	public var background:FlxSprite;
	public var keyText:FlxText;
	public var keyCodes:Array<Int>;
	public dynamic function onComplete():Void {}

	public function new(x:Float, y:Float, keyCodes:Array<Int>, camera:FlxCamera, strumHalved:Float, mania:Int)
	{
		super();

		this.keyCodes = keyCodes;

		var xOffset:Float = x + strumHalved;
		var size:Int = 20 - (mania - 3);
		if (size < 10) size = 10;

		keyText = new FlxText(xOffset + 4, y + 4, 0, InputFormatter.getKeyName(keyCodes[0]));
		keyText.setFormat(Paths.font("vcr.ttf"), size, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		keyText.x -= keyText.width / 2;
		xOffset = keyText.x;

		background = new FlxSprite(xOffset - 4, y);
		background.makeGraphic(Std.int(keyText.width + 8), Std.int(keyText.height + 8), 0xFF000000);
		background.alpha = 0.5;

		add(background);
		add(keyText);

		background.cameras = [camera];
		keyText.cameras = [camera];

		new FlxTimer().start(2, function(tmr:FlxTimer)
		{
			FlxTween.tween(keyText, {alpha: 0}, 0.5, {ease: FlxEase.linear, onComplete: function(t)
			{
				if (keyCodes.length > 1) keyText.text = InputFormatter.getKeyName(keyCodes[1]);
				else keyText.text = '---';

				FlxTween.tween(keyText, {alpha: 1}, 0.5);

				keyText.x = x + strumHalved + 4;
				keyText.x -= keyText.width / 2;
				xOffset = keyText.x;
				background.x = xOffset - 4;
				background.makeGraphic(Std.int(keyText.width + 8), Std.int(keyText.height + 8), 0xFF000000);
				new FlxTimer().start(2.5, function(tmr2:FlxTimer)
				{
					FlxTween.tween(keyText, {alpha: 0}, 0.5, {ease: FlxEase.linear, onComplete: function(t)
					{
						onComplete();
					}});
				});
			}});
		});
	}
}

/**
 * Extra Keys：判定线边界（复刻 Psych EK 的 StrumBoundaries）。
 * 多键谱的 strumline 若超出边界宽度，会被 adaptStrumline / generateStaticArrows 收缩。
 */
class StrumBoundaries
{
	public static var minBoundaryOpponent:FlxPoint = new FlxPoint(30, 50);
	public static var maxBoundaryOpponent:FlxPoint = new FlxPoint(630, 160);

	public static function getMiddlePoint():FlxPoint
	{
		return new FlxPoint(Std.int(getBoundaryWidth().x / 2), Std.int(getBoundaryWidth().y / 2));
	}

	public static function getBoundaryWidth():FlxPoint
	{
		return new FlxPoint(Std.int((maxBoundaryOpponent.x - minBoundaryOpponent.x)), Std.int((maxBoundaryOpponent.y - minBoundaryOpponent.y)));
	}
}
