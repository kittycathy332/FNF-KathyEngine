package objects;

import backend.ExtraKeysHandler;
import backend.animation.PsychAnimationController;
import shaders.RGBPalette;
import shaders.ColorSwap;
import flixel.system.FlxAssets.FlxShader;

typedef RGB = {
	r:Null<Int>,
	g:Null<Int>,
	b:Null<Int>
}

typedef NoteSplashAnim = {
	name:String,
	noteData:Int,
	prefix:String,
	indices:Array<Int>,
	offsets:Array<Float>,
	fps:Array<Int>
}

typedef NoteSplashConfig = {
	animations:Map<String, NoteSplashAnim>,
	scale:Float,
	allowRGB:Bool,
	allowPixel:Bool,
	rgb:Array<Null<RGB>>
}

class NoteSplash extends FlxSprite
{
	public var rgbShader:PixelSplashShaderRef;
	public var colorSwap:ColorSwap;
	public var texture:String;
	public var config(default, set):NoteSplashConfig;
	public var babyArrow:StrumNote;
	public var noteData:Int = 0;

	public var copyX:Bool = true;
	public var copyY:Bool = true;
	public var inEditor:Bool = false;

	var spawned:Bool = false;
	var noteDataMap:Map<Int, String> = new Map();
	// Extra Keys：随机动画组（0..maxAnims-1）。noteData 保持列号不被改写，
	// 供取色（styleIndex）与方向映射使用，避免多键下产生配置外动画索引导致飞溅卡死。
	var animNum:Int = 0;

	public static var defaultNoteSplash(default, never):String = "noteSplashes/noteSplashes";
	public static var configs:Map<String, NoteSplashConfig> = new Map();

	public function new(?x:Float = 0, ?y:Float = 0, ?splash:String)
	{
		super(x, y);

		animation = new PsychAnimationController(this);

		rgbShader = new PixelSplashShaderRef();
		shader = rgbShader.shader;
		// Legacy HSV shader (local per-splash, like old Psych 0.6.3). Only assigned
		// to the sprite when arrowColorMode == 'HSV' in spawnSplashNote.
		colorSwap = new ColorSwap();

		loadSplash(splash);
	}

	public var maxAnims(default, set):Int = 0;
	public function loadSplash(?splash:String)
	{
		// 先解析目标皮肤的最终路径（此时不要清空 config，早退时需要保留已加载的动画）。
		// 空串（如 SONG.splashSkin = ""）与 null 等价，一律回退到默认飞溅，
		// 否则会被 resolveSkinPath("") 误解析成普通箭头皮肤（defaultNoteSkin）。
		if(splash == null || splash.length < 1)
		{
			splash = getSplashSkinPath(defaultNoteSplash + getSplashSkinPostfix());
			if (PlayState.SONG != null && PlayState.SONG.splashSkin != null && PlayState.SONG.splashSkin.length > 0) splash = getSplashSkinPath(PlayState.SONG.splashSkin);
		}
		else
		{
			splash = getSplashSkinPath(splash);
		}

		// 单曲内同一皮肤只需检测/构建一次：目标路径与当前已加载一致且已有有效 config，
		// 直接跳过后续的 getSparrowAtlas / checkForAnim 探测 / clearAnimations+addByPrefix 重建。
		// spawnSplashNote 每次命中都会调用本方法（因 texture 存的是解析后路径、传入的是原始名，
		// 二者常不相等），这里的早退可消除每次命中飞溅时的重复解析与动画重建开销。
		if (!inEditor && config != null && texture == splash)
			return;

		config = null;
		maxAnims = 0;

		texture = splash;
		frames = Paths.getSparrowAtlas(texture);
		if (frames == null)
		{
			texture = getSplashSkinPath(defaultNoteSplash + getSplashSkinPostfix());
			frames = Paths.getSparrowAtlas(texture);
			if (frames == null)
			{
				texture = getSplashSkinPath(defaultNoteSplash);
				frames = Paths.getSparrowAtlas(texture);
			}
		}
		// 连默认飞溅贴图都解析不出时（资源损坏/缺失），不再继续解析动画配置，
		// 直接退出避免对空 frames 解引用崩溃。该飞溅会因 animation.curAnim 为空
		// 而被 update() 里的 buggedKillTime 自动清理，不影响游戏运行。
		if (frames == null)
			return;

		var path:String = 'images/$texture';
		if (configs.exists(path))
		{
			this.config = configs.get(path);
			for (anim in this.config.animations)
			{
				if (anim.noteData % 4 == 0)
					maxAnims++;
			}
			return;
		}
		else if (Paths.fileExists('$path.json', TEXT))
		{
			var config:Dynamic = haxe.Json.parse(Paths.getTextFromFile('$path.json'));
			if (config != null)
			{
				var tempConfig:NoteSplashConfig = {
					animations: new Map(),
					scale: config.scale,
					allowRGB: config.allowRGB,
					allowPixel: config.allowPixel,
					rgb: config.rgb
				}

				for (i in Reflect.fields(config.animations))
				{
					var anim:NoteSplashAnim = Reflect.field(config.animations, i);
					tempConfig.animations.set(i, anim);
					if (anim.noteData % 4 == 0)
						maxAnims++;
				}

				this.config = tempConfig;
				configs.set(path, this.config);
				return;
			}
		}

		// Splashes with no json
		var tempConfig:NoteSplashConfig = createConfig();
		var anim:String = 'note splash';
		var fps:Array<Null<Int>> = [22, 26];
		var offsets:Array<Array<Float>> = [[0, 0]];
		if (Paths.fileExists('$path.txt', TEXT)) // Backwards compatibility with 0.7 splash txts
		{
			var configFile:Array<String> = CoolUtil.listFromString(Paths.getTextFromFile('$path.txt'));
			if (configFile.length > 0)
			{
				anim = configFile[0];
				if (configFile.length > 1)
				{
					var framerates:Array<String> = configFile[1].split(' ');
					fps = [Std.parseInt(framerates[0]), Std.parseInt(framerates[1])];
					if (fps[0] == null) fps[0] = 22;
					if (fps[1] == null) fps[1] = 26;

					if (configFile.length > 2)
					{
						offsets = [];
						for (i in 2...configFile.length)
						{
							if (configFile[i].trim() != '')
							{
								var animOffs:Array<String> = configFile[i].split(' ');
								var x:Float = Std.parseFloat(animOffs[0]);
								var y:Float = Std.parseFloat(animOffs[1]);
								if (Math.isNaN(x)) x = 0;
								if (Math.isNaN(y)) y = 0;
								offsets.push([x, y]);
							}
						}
					}
				}
			}
		}

		var failedToFind:Bool = false;
		while (true)
		{
			for (v in Note.colArray)
			{
				if (!checkForAnim('$anim $v ${maxAnims+1}'))
				{
					failedToFind = true;
					break;
				}
			}
			if (failedToFind) break;
			maxAnims++;
		}

		var failedToFind:Bool = false;
		var forceSingle = ClientPrefs.data.forceSingleSplashAnim;
		if (!forceSingle) { // 只有不强制单动画时才检查多个动画
			while (true) {
				for (v in Note.colArray) {
					if (!checkForAnim('$anim $v ${maxAnims+1}')) {
						failedToFind = true;
						break;
					}
				}
				if (failedToFind) break;
				maxAnims++;
			}
		} else {
			maxAnims = 1; // 强制设置为单动画
		}
	
		// 生成动画配置时添加强制单动画处理
		for (animNum in 0...maxAnims) {
			for (i => col in Note.colArray) {
				var data:Int = i % Note.colArray.length + (animNum * Note.colArray.length);
				// 强制单动画时使用统一名称
				var name:String = forceSingle ? col : (animNum > 0 ? '$col${animNum+1}' : col);
				var prefix:String = forceSingle ? '$anim $col 1' : '$anim $col ${animNum + 1}';
				
				// 检查动画是否存在，如果强制单动画但动画不存在时使用备用方案
				if (forceSingle && !checkForAnim(prefix)) {
					prefix = '$anim $col'; // 尝试不带数字的后缀
					if (!checkForAnim(prefix)) continue; // 如果仍不存在则跳过
				}
				
				var offset:Array<Float> = offsets[FlxMath.wrap(data, 0, Std.int(offsets.length-1))];
				addAnimationToConfig(tempConfig, 1, name, prefix, fps, offset, [], data);
			}
		}

		this.config = tempConfig;
		configs.set(path, this.config);
	}

	public function spawnSplashNote(?x:Float = 0, ?y:Float = 0, ?noteData:Int = 0, ?note:Note, ?randomize:Bool = true)
	{
		if (note != null && note.noteSplashData.disabled)
			return;

		aliveTime = 0;

		if (!inEditor)
		{
			var loadedTexture:String = defaultNoteSplash + getSplashSkinPostfix();
			// 空串视为未指定，回退到默认/SONG.splashSkin；否则 "" 会被当成有效纹理传入 loadSplash
			if (note != null && note.noteSplashData.texture != null && note.noteSplashData.texture.length > 0) loadedTexture = note.noteSplashData.texture;
			else if (PlayState.SONG != null && PlayState.SONG.splashSkin != null && PlayState.SONG.splashSkin.length > 0) loadedTexture = PlayState.SONG.splashSkin;

			if (texture != loadedTexture) loadSplash(loadedTexture);
		}

		setPosition(x, y);

		// 多键：飞溅 scale/offset 随 strumScale 缩放（4k=1 原样）。
		// 定位基准保持 Psych 原版固定值（不乘 strumScale）：渲染中心 = x_pos - offset + origin，
		// origin 是贴图原始半宽（固定不随缩放变），若定位也缩放会把贴图中心推向一侧造成错位。
		// LE LTS 双侧：按命中音符所属侧取缩放（玩家=playerStrumScale、对手=opponentStrumScale；非双侧=全局）
		var splashScale:Float = (note != null) ? PlayState.getNoteSideScale(note.mustPress) : PlayState.strumScale;
		if (babyArrow != null)
			setPosition(babyArrow.x - Note.swagWidth * 0.95, babyArrow.y - Note.swagWidth); // To prevent it from being misplaced for one game tick

		if (note != null)
			noteData = note.noteData;

		if (randomize && maxAnims > 1)
			animNum = FlxG.random.int(0, maxAnims - 1);

		this.noteData = noteData;
		var anim:String = playDefaultAnim();

		// Legacy HSV path: apply the note's HSV splash shift via ColorSwap and skip the RGB setup.
		if(ClientPrefs.data.arrowColorMode == 'HSV') {
			// LE LTS 双侧：按命中音符所属侧取样式索引（对手侧用对手键数档位）
			var nd:Int = (note != null) ? note.getStyleIndex() : Note.styleIndex(noteData); // 多键：按全局样式索引取 arrowHSV
			var hue:Float = 0;
			var sat:Float = 0;
			var brt:Float = 0;
			if (nd > -1 && nd < ClientPrefs.data.arrowHSV.length) {
				var hsvArr:Array<Int> = ClientPrefs.data.arrowHSV[nd];
				hue = hsvArr[0] / 360;
				sat = hsvArr[1] / 100;
				brt = hsvArr[2] / 100;
			}
			// Note-specific overrides (e.g. Hurt Note zeroes the shift), mirroring old Psych 0.6.3.
			if (note != null) {
				hue = note.noteSplashHue;
				sat = note.noteSplashSat;
				brt = note.noteSplashBrt;
			}
			colorSwap.hue = hue;
			colorSwap.saturation = sat;
			colorSwap.brightness = brt;
			this.shader = colorSwap.shader;
		} else {
			var tempShader:RGBPalette = null;
			// LE LTS 双侧：按命中音符所属侧取样式索引（对手侧用对手键数档位）
			var splashStyle:Int = (note != null) ? note.getStyleIndex() : Note.styleIndex(noteData); // 多键：列号→全局样式索引（取色用）
			if (config.allowRGB)
			{
				Note.initializeGlobalRGBShader(splashStyle);
				if (inEditor || (note == null || note.noteSplashData.useRGBShader) && (PlayState.SONG == null || !PlayState.SONG.disableNoteRGB))
				{
					tempShader = new RGBPalette();
					// If Note RGB is enabled:
					if ((note == null || !note.noteSplashData.useGlobalShader) || inEditor)
					{
						var colors = config.rgb;
						if (colors != null)
						{
							for (i in 0...colors.length)
							{
								if (i > 2) break;

							var arr:Array<FlxColor> = (splashStyle > -1 && splashStyle < ClientPrefs.data.arrowRGB.length) ? ClientPrefs.data.arrowRGB[splashStyle] : null;
							if (PlayState.isPixelStage && splashStyle > -1 && splashStyle < ClientPrefs.data.arrowRGBPixel.length) arr = ClientPrefs.data.arrowRGBPixel[splashStyle];
							// Extra Keys：arrowRGB 缺失时从 extrakeys.json 全局色表兜底（与 Note.defaultRGB 一致）
							if (arr == null && ExtraKeysHandler.instance != null && ExtraKeysHandler.instance.data != null
								&& ExtraKeysHandler.instance.data.colors != null && splashStyle > -1 && splashStyle < ExtraKeysHandler.instance.data.colors.length)
							{
								var ekC = ExtraKeysHandler.instance.data.colors[splashStyle];
								if (ekC != null) arr = [FlxColor.fromString('#' + ekC.inner), FlxColor.fromString('#' + ekC.border), FlxColor.fromString('#' + ekC.outline)];
							}

								var rgb = colors[i];
								if (rgb == null)
								{
									if (i == 0) tempShader.r = arr[0];
									else if (i == 1) tempShader.g = arr[1];
									else if (i == 2) tempShader.b = arr[2];
									continue;
								}

								var r:Null<Int> = rgb.r; 
								var g:Null<Int> = rgb.g;
								var b:Null<Int> = rgb.b;

								if (r == null || Math.isNaN(r) || r < 0) r = arr[0];
								if (g == null || Math.isNaN(g) || g < 0) g = arr[1];
								if (b == null || Math.isNaN(b) || b < 0) b = arr[2];

								var color:FlxColor = FlxColor.fromRGB(r, g, b);
								if (i == 0) tempShader.r = color;
								else if (i == 1) tempShader.g = color;
								else if (i == 2) tempShader.b = color;
							}
						}
						else tempShader.copyValues(Note.globalRgbShaders[splashStyle]);

						if (note != null)
						{
							if (note.noteSplashData.r != -1) tempShader.r = note.noteSplashData.r;
							if (note.noteSplashData.g != -1) tempShader.g = note.noteSplashData.g;
							if (note.noteSplashData.b != -1) tempShader.b = note.noteSplashData.b;
						}
					}
					else tempShader.copyValues(Note.globalRgbShaders[splashStyle]);
				}
			}
			rgbShader.copyValues(tempShader);
			if (!config.allowPixel) rgbShader.pixelAmount = 1;
			else if (PlayState.isPixelStage) rgbShader.pixelAmount = 6;
		}

		scale.set(config.scale * splashScale, config.scale * splashScale);
		offset.set(10 * splashScale, 10 * splashScale);
		var conf:NoteSplashAnim = config.animations.get(anim);
		var offsets:Array<Float> = [0, 0];
		if (conf != null) offsets = conf.offsets;
		if (offsets != null)
		{
			offset.x += offsets[0] * splashScale;
			offset.y += offsets[1] * splashScale;
		}

		animation.finishCallback = function(name:String) {
			kill();
			spawned = false;
		}

		alpha = ClientPrefs.data.splashAlpha;
		if (note != null) alpha = note.noteSplashData.a;

		antialiasing = ClientPrefs.data.antialiasing;
		if (note != null) antialiasing = note.noteSplashData.antialiasing;
		if (PlayState.isPixelStage && config.allowPixel) antialiasing = false;

		var minFps:Int = 22;
		var maxFps:Int = 26;
		if (conf != null)
		{
			minFps = conf.fps[0];
			if (minFps < 0) minFps = 0;

			maxFps = conf.fps[1];
			if (maxFps < 0) maxFps = 0;
		}

		if (animation.curAnim != null)
			animation.curAnim.frameRate = FlxG.random.int(minFps, maxFps);

		spawned = true;
	}
	
	public function playDefaultAnim()
	{
		// 方向周期：配置飞溅动画按 4 方向组织（noteData 0-3 = 组1，4-7 = 组2……）。
		// 多键下按列对应的 EK 样式名映射到 4 方向（purple/blue/green/red），
		// 保证飞溅配色与列色一致；映射不到时回退 noteData%4。
		var dir:Int = noteData % 4;
		try {
			var style:Int = Note.styleIndex(noteData);
			if (ExtraKeysHandler.instance != null && ExtraKeysHandler.instance.data != null
				&& ExtraKeysHandler.instance.data.animations != null
				&& style > -1 && style < ExtraKeysHandler.instance.data.animations.length)
			{
				var ekNote:String = ExtraKeysHandler.instance.data.animations[style].note;
				if (ekNote == 'purple') dir = 0;
				else if (ekNote == 'blue') dir = 1;
				else if (ekNote == 'green') dir = 2;
				else if (ekNote == 'red') dir = 3;
			}
		} catch (e:Dynamic) {}

		// 先取随机组动画（animNum），缺失时回退组1；仍缺失则本帧不播放（由 buggedKillTime 兜底清理）
		var anim:String = noteDataMap.get(dir + animNum * 4);
		if (anim == null || !animation.exists(anim))
			anim = noteDataMap.get(dir);
		if (anim != null && animation.exists(anim))
			animation.play(anim, true);

		return anim;
	}

	function checkForAnim(anim:String)
	{
		var animFrames = [];
		@:privateAccess
		animation.findByPrefix(animFrames, anim); // adds valid frames to animFrames

		return animFrames.length > 0;
	}

	var aliveTime:Float = 0;
	static var buggedKillTime:Float = 0.5; //automatically kills note splashes if they break to prevent it from flooding your HUD
	override function update(elapsed:Float)
	{
		if (spawned)
		{
			aliveTime += elapsed;
			if (animation.curAnim == null && aliveTime >= buggedKillTime)
			{
				kill();
				spawned = false;
			}
		}

		if (babyArrow != null)
		{
			if (copyX)
				x = babyArrow.x - Note.swagWidth * 0.95;

			if (copyY)
				y = babyArrow.y - Note.swagWidth;
		}
		super.update(elapsed);
	}

	public static function getSplashSkinPostfix()
	{
		var skin:String = '';
		var skinName:String = ClientPrefs.data.splashSkin.trim();
		if (skinName != ClientPrefs.defaultData.splashSkin)
			skin = '-' + skinName.toLowerCase().replace(' ', '-');
		return skin;
	}

	public static function getSplashSkinPath(basePath:String):String
	{
		// 飞溅贴图共享、不分像素/非像素，故传入 isSplash=true，避免像素舞台被套上
		// 不存在的 pixelUI/ 前缀而回退到默认（非 hsv）飞溅贴图。
		return Note.resolveSkinPath(basePath, true);
	}

	public static function createConfig():NoteSplashConfig
	{
		return {
			animations: new Map(),
			scale: 1,
			allowRGB: true,
			allowPixel: true,
			rgb: null
		}
	}

	public static function addAnimationToConfig(config:NoteSplashConfig, scale:Float, name:String, prefix:String, fps:Array<Int>, offsets:Array<Float>, indices:Array<Int>, noteData:Int):NoteSplashConfig
	{
		if (config == null) config = createConfig();

		config.animations.set(name, {name: name, noteData: noteData, prefix: prefix, indices: indices, offsets: offsets, fps: fps});
		config.scale = scale;
		return config;
	}

	function set_config(value:NoteSplashConfig):NoteSplashConfig 
	{
		if (value == null) value = createConfig();

		@:privateAccess
		animation.clearAnimations();
		noteDataMap.clear();

		for (i in value.animations)
		{
			var key:String = i.name;
			if (i.prefix.length > 0 && key != null && key.length > 0)
			{
				if (i.indices != null && i.indices.length > 0)
					animation.addByIndices(key, i.prefix, i.indices, "", i.fps[1], false);
				else
					animation.addByPrefix(key, i.prefix, i.fps[1], false);

				noteDataMap.set(i.noteData, key);
			}
		}

		scale.set(value.scale, value.scale);
		return config = value;
	}

	function set_maxAnims(value:Int)
		{
			// Extra Keys：不再改写 noteData（Psych 原版依赖 noteData 索引动画，
			// 多键下 wrap 到 colArray*maxAnims-1 会产生配置外索引导致飞溅卡死/取色错位；
			// 动画选择已改为 playDefaultAnim 的 dir+animNum 方案）。
			return maxAnims = value;
		}
}

class PixelSplashShaderRef 
{
	public var shader:PixelSplashShader = new PixelSplashShader();
	public var enabled(default, set):Bool = true;
	public var pixelAmount(default, set):Float = 1;

	public function copyValues(tempShader:RGBPalette)
	{
		if (tempShader != null)
		{
			for (i in 0...3)
			{
				shader.r.value[i] = tempShader.shader.r.value[i];
				shader.g.value[i] = tempShader.shader.g.value[i];
				shader.b.value[i] = tempShader.shader.b.value[i];
			}
			shader.mult.value[0] = tempShader.shader.mult.value[0];
		}
		else enabled = false;
	}

	public function set_enabled(value:Bool)
	{
		enabled = value;
		shader.mult.value = [value ? 1 : 0];
		return value;
	}

	public function set_pixelAmount(value:Float)
	{
		pixelAmount = value;
		shader.uBlocksize.value = [value, value];
		return value;
	}

	public function reset()
	{
		shader.r.value = [0, 0, 0];
		shader.g.value = [0, 0, 0];
		shader.b.value = [0, 0, 0];
	}

	public function new()
	{
		reset();
		enabled = true;

		if (!PlayState.isPixelStage) pixelAmount = 1;
		else pixelAmount = PlayState.daPixelZoom;
		//trace('Created shader ' + Conductor.songPosition);
	}
}

class PixelSplashShader extends FlxShader
{
	@:glFragmentHeader('
		#pragma header

		uniform vec3 r;
		uniform vec3 g;
		uniform vec3 b;
		uniform float mult;
		uniform vec2 uBlocksize;

		vec4 flixel_texture2DCustom(sampler2D bitmap, vec2 coord) {
			vec2 blocks = openfl_TextureSize / uBlocksize;
			vec4 color = flixel_texture2D(bitmap, floor(coord * blocks) / blocks);
			if (!hasTransform) {
				return color;
			}

			if (color.a == 0.0 || mult == 0.0) {
				return color * openfl_Alphav;
			}

			vec4 newColor = color;
			newColor.rgb = min(color.r * r + color.g * g + color.b * b, vec3(1.0));
			newColor.a = color.a;

			color = mix(color, newColor, mult);

			if (color.a > 0.0) {
				return vec4(color.rgb, color.a);
			}
			return vec4(0.0, 0.0, 0.0, 0.0);
		}')

	@:glFragmentSource('
		#pragma header

		void main() {
			gl_FragColor = flixel_texture2DCustom(bitmap, openfl_TextureCoordv);
		}')

	public function new()
	{
		super();
	}
}
