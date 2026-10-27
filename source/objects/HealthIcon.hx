package objects;

import flixel.graphics.FlxGraphic;
import flixel.graphics.frames.FlxAtlasFrames;

class HealthIcon extends FlxSprite
{
	public var sprTracker:FlxSprite;
	private var isPlayer:Bool = false;
	private var char:String = '';
	public var startSize:Float = 1;
	public var framesCount:Int = 1; // 当前图标实际包含的状态帧数量
	public var isAnimated:Bool = false; // 是否为 png+xml（Sparrow Atlas）动态图标

	// 资源保护的上下文标签。由 FreeplayState 在构建图标批量创建前设为 'freeplay'，
	// 构建完清回 null。其他状态（PlayState、编辑器等）默认 null，
	// HealthIcon 不会自动调 excludeAsset，图标纹理随该状态 destroy 时一起被清。
	public static var _excludeContext:Null<String> = null;


	public function new(char:String = 'face', isPlayer:Bool = false, ?allowGPU:Bool = true)
	{
		super();
		this.isPlayer = isPlayer;
		changeIcon(char, allowGPU);
		scrollFactor.set();
	}

	override function update(elapsed:Float)
	{
		super.update(elapsed);

		if (sprTracker != null)
			setPosition(sprTracker.x + sprTracker.width + 12, sprTracker.y - 30);
	}

	private var iconOffsets:Array<Float> = [0, 0];
	// Atlas 模式下每个状态的独立居中偏移（0=default，1=losing，2=win），
	// 静态图标仍只使用 iconOffsets，互不影响。
	private var perAnimIconOffsets:Array<Array<Float>> = [[0, 0], [0, 0], [0, 0]];
	private var curStateFrame:Int = 0;
	// 可选 JSON 配置中的 antialiasing 覆盖值；null 表示沿用原逻辑（-pixel 或 ClientPrefs）。
	private var _configAntialiasing:Null<Bool> = null;

	public function changeIcon(char:String, ?allowGPU:Bool = true) {
		if(this.char != char) {
			var name:String = 'icons/' + char;

			// Leather 图标模式：当 loadLeatherIcons='leather' 时优先查找 leather/<角色名>-icons 格式，
			// Paths.fileExists / Paths.image 会自动按 Mods → currentLevel → shared 顺序解析，
			// 因此 Mods 中的 Leather 图标会被自动优先使用。
			if (ClientPrefs.data.loadLeatherIcons == 'leather') {
				var leatherName:String = 'icons/leather/' + char + '-icons';
				if (Paths.fileExists('images/' + leatherName + '.png', IMAGE))
					name = leatherName;
			}
			// OS 图标模式：当 loadLeatherIcons='os' 时使用 OS 风格图标（icons/os/icon-<角色名>.png）
			else if (ClientPrefs.data.loadLeatherIcons == 'os') {
				var osName:String = 'icons/os/icon-' + char;
				if (Paths.fileExists('images/' + osName + '.png', IMAGE))
					name = osName;
			}

			if(!Paths.fileExists('images/' + name + '.png', IMAGE)) name = 'icons/icon-' + char; //Older versions of psych engine's support
			if(!Paths.fileExists('images/' + name + '.png', IMAGE)) name = 'icons/icon-face'; //Prevents crash from missing icon

			// 可选：png + xml（Sparrow Atlas）动态图标（Matt V3 风格），由设置项 dynamicHealthIcons 控制。
			// 关闭或 xml 不存在 / 不含可用帧前缀时，完全走原有的单张 PNG 切分逻辑，
			// 保证旧图标（含 Leather/OS 模式、2/3 帧条带）行为不变。
			// 若存在同名 JSON（images/icons/<name>.json），则读取动画前缀/帧率/循环/缩放/偏移等配置。
			var atlas:FlxAtlasFrames = null;
			var iconConfig:Dynamic = null;
			if (ClientPrefs.data.dynamicHealthIcons && Paths.sparrowXmlExists(name)) {
				try {
					iconConfig = loadIconConfig(name);
					var normalPrefix:String = getAnimPrefix(iconConfig, 'normal', 'default');
					var candidate:FlxAtlasFrames = Paths.getSparrowAtlas(name, null, allowGPU);
					if (candidate != null) {
						if (!hasFramePrefix(candidate, normalPrefix)) normalPrefix = 'default';
						if (hasFramePrefix(candidate, normalPrefix)) atlas = candidate;
					}
				} catch (e:Dynamic) {
					// XML/JSON 损坏时静默回退到静态 PNG，避免旧资源导致崩溃
					atlas = null;
				}
			}

			var graphic:FlxGraphic = (atlas != null) ? atlas.parent : Paths.image(name, allowGPU);

			// 资源保护由调用方通过 HealthIcon._excludeContext 设置上下文标签。
			// FreeplayState 在构建批量图标前会设为 'freeplay'，退出时调
			// Paths.clearExcludedByTag('freeplay') → clearStoredMemory → 真正释放纹理。
			// PlayState / 编辑器等其他状态的 _excludeContext 默认 null，
			// 图标纹理不被保护，随该状态 destroy 时一起被清，无累积泄漏。
			if (graphic != null && graphic.key != null && graphic.key.length > 0)
				Paths.excludeAsset(graphic.key, _excludeContext);

			if (atlas != null)
				loadAnimatedIcon(atlas, iconConfig);
			else
				loadStaticIcon(graphic, char);

			this.char = char;

			// JSON 的 antialiasing 优先级最高；否则沿用原来的 -pixel / 全局设置逻辑。
			if (_configAntialiasing != null)
				antialiasing = _configAntialiasing;
			else if(char.endsWith('-pixel'))
				antialiasing = false;
			else
				antialiasing = ClientPrefs.data.antialiasing;
		}
	}

	// 原有静态图标逻辑：按 宽/高 自适应切分单张 PNG 条带（2/3/... 帧均可）。
	private function loadStaticIcon(graphic:FlxGraphic, iconName:String) {
		isAnimated = false;
		curStateFrame = 0;
		_configAntialiasing = null;
		iconOffsets[0] = iconOffsets[1] = 0;

		// 自适应切分：按 宽/高 推算图标数量，每个图标视为正方形。
		// 这样 2:1（双态）、3:1（三态）等任意数量的图标条都能正确切分，避免把 2:1 误切成三份。
		var iSize:Int = Math.round(graphic.width / graphic.height);
		var frameW:Int = Math.floor(graphic.width / iSize);
		var frameH:Int = Math.floor(graphic.height);

		loadGraphic(graphic, true, frameW, frameH);
		// 在 150x150 参考框内居中，兼容宽矩形与方形图标
		iconOffsets[0] = (width - 150) / 2;
		iconOffsets[1] = (height - 150) / 2;
		startSize = scale.x;
		updateHitbox();

		animation.add(iconName, [for(i in 0...frames.frames.length) i], 0, false, isPlayer);
		animation.play(iconName);
		framesCount = frames.frames.length;
	}

	// Atlas 动态图标：normal（正常）/ lose（输）/ win（赢，可选）循环播放。
	// 默认前缀兼容 Matt V3 的 default/losing 命名，并额外识别 lose 与 win；
	// 若存在同名 JSON，则前缀、帧率、循环、缩放、偏移与抗锯齿均可配置。
	private function loadAnimatedIcon(atlas:FlxAtlasFrames, config:Dynamic) {
		isAnimated = true;
		curStateFrame = 0;
		for (offset in perAnimIconOffsets) {
			offset[0] = 0;
			offset[1] = 0;
		}

		frames = atlas;
		// 从静态图标切换过来时，避免沿用旧的静态居中偏移（atlas 模式只使用 perAnimIconOffsets）。
		iconOffsets[0] = iconOffsets[1] = 0;
		_configAntialiasing = getConfigAntialiasing(config);

		var normalPrefix:String = getAnimPrefix(config, 'normal', 'default');
		if (!hasFramePrefix(atlas, normalPrefix)) normalPrefix = 'default';
		animation.addByPrefix('default', normalPrefix, getAnimFrameRate(config, 'normal'), getAnimLoop(config, 'normal'));

		var states:Array<String> = ['default'];
		var stateKeys:Array<String> = ['normal'];

		var losePrefix:String = getAnimPrefix(config, 'lose', '');
		if (losePrefix == '' || !hasFramePrefix(atlas, losePrefix))
			losePrefix = hasFramePrefix(atlas, 'losing') ? 'losing' : (hasFramePrefix(atlas, 'lose') ? 'lose' : null);
		if (losePrefix != null) {
			animation.addByPrefix('losing', losePrefix, getAnimFrameRate(config, 'lose'), getAnimLoop(config, 'lose'));
			states.push('losing');
			stateKeys.push('lose');
		}

		var winPrefix:String = getAnimPrefix(config, 'win', '');
		if (winPrefix == '' || !hasFramePrefix(atlas, winPrefix))
			winPrefix = hasFramePrefix(atlas, 'win') ? 'win' : null;
		if (winPrefix != null) {
			animation.addByPrefix('win', winPrefix, getAnimFrameRate(config, 'win'), getAnimLoop(config, 'win'));
			states.push('win');
			stateKeys.push('win');
		}

		// 可选的整体缩放（在 150x150 参考框之外额外缩放）
		var iconScale:Float = getConfigScale(config);
		animation.play('default');
		if (iconScale != 1)
			setGraphicSize(Std.int(frameWidth * iconScale), Std.int(frameHeight * iconScale));

		// 逐状态记录 150x150 参考框内的居中偏移（各状态帧尺寸可能不同），并叠加 JSON 自定义偏移。
		for (i in 0...states.length) {
			curStateFrame = i;
			animation.play(states[i]);
			updateHitbox();
			perAnimIconOffsets[i][0] = (width - 150) / 2;
			perAnimIconOffsets[i][1] = (height - 150) / 2;
			applyConfigOffset(config, stateKeys[i], perAnimIconOffsets[i]);
		}

		curStateFrame = 0;
		animation.play('default');
		updateHitbox();
		startSize = scale.x;
		framesCount = states.length;
	}

	private static function hasFramePrefix(atlas:FlxAtlasFrames, prefix:String):Bool {
		if (atlas == null || atlas.frames == null) return false;
		for (frame in atlas.frames) {
			if (frame.name != null && frame.name.startsWith(prefix))
				return true;
		}
		return false;
	}

	// ===== 可选 JSON 配置（images/icons/<name>.json）=====
	// 所有字段都是可选的；缺失、类型错误或 JSON 损坏时静默回退到内置默认值。
	// 示例：
	// {
	//   "antialiasing": true,
	//   "scale": 1.0,
	//   "animations": {
	//     "normal": { "prefix": "default", "frameRate": 24, "loop": true },
	//     "lose":   { "prefix": "losing",  "frameRate": 24, "loop": true },
	//     "win":    { "prefix": "win",     "frameRate": 24, "loop": true }
	//   },
	//   "offsets": { "normal": [0, 0], "lose": [0, 0], "win": [0, 0] }
	// }

	private static function loadIconConfig(name:String):Dynamic {
		var jsonPath:String = 'images/' + name + '.json';
		if (!Paths.fileExists(jsonPath, TEXT)) return null;
		try {
			return haxe.Json.parse(Paths.getTextFromFile(jsonPath));
		} catch (e:Dynamic) {
			return null;
		}
	}

	private static function getAnimEntry(config:Dynamic, key:String):Dynamic {
		if (config == null) return null;
		var animations:Dynamic = Reflect.field(config, 'animations');
		if (animations == null) return null;
		return Reflect.field(animations, key);
	}

	private static function getAnimPrefix(config:Dynamic, key:String, fallback:String):String {
		var entry:Dynamic = getAnimEntry(config, key);
		if (entry != null) {
			var v:Dynamic = Reflect.field(entry, 'prefix');
			if (Std.isOfType(v, String) && v.length > 0) return v;
		}
		return fallback;
	}

	private static function getAnimFrameRate(config:Dynamic, key:String):Float {
		var entry:Dynamic = getAnimEntry(config, key);
		if (entry != null) {
			var v:Dynamic = Reflect.field(entry, 'frameRate');
			if ((Std.isOfType(v, Int) || Std.isOfType(v, Float)) && v > 0) return v;
		}
		return 24;
	}

	private static function getAnimLoop(config:Dynamic, key:String):Bool {
		var entry:Dynamic = getAnimEntry(config, key);
		if (entry != null) {
			var v:Dynamic = Reflect.field(entry, 'loop');
			if (Std.isOfType(v, Bool)) return v;
		}
		return true;
	}

	private static function getConfigScale(config:Dynamic):Float {
		if (config != null) {
			var v:Dynamic = Reflect.field(config, 'scale');
			if ((Std.isOfType(v, Int) || Std.isOfType(v, Float)) && v > 0) return v;
		}
		return 1;
	}

	private static function getConfigAntialiasing(config:Dynamic):Null<Bool> {
		if (config != null) {
			var v:Dynamic = Reflect.field(config, 'antialiasing');
			if (Std.isOfType(v, Bool)) return v;
		}
		return null;
	}

	// JSON offsets 是叠加在自动居中偏移之上的微调值，单位与像素一致。
	private static function applyConfigOffset(config:Dynamic, key:String, target:Array<Float>):Void {
		if (config == null) return;
		var offsets:Dynamic = Reflect.field(config, 'offsets');
		if (offsets == null) return;
		var arr:Dynamic = Reflect.field(offsets, key);
		if (arr == null || !Std.isOfType(arr, Array) || arr.length < 2) return;

		var ox:Dynamic = arr[0];
		var oy:Dynamic = arr[1];
		if (Std.isOfType(ox, Int) || Std.isOfType(ox, Float)) {
			var fx:Float = ox;
			target[0] += fx;
		}
		if (Std.isOfType(oy, Int) || Std.isOfType(oy, Float)) {
			var fy:Float = oy;
			target[1] += fy;
		}
	}

	/**
	 * 设置图标状态：'normal'（正常）、'lose'（输）、'win'（赢）
	 * 帧索引：0 = 正常，1 = 输，2 = 赢（仅当图标实际包含对应帧时生效，否则自动回退，保证兼容）
	 */
	public function setIconState(state:String)
	{
		if (animation.curAnim == null || framesCount <= 0) return;

		if (isAnimated)
		{
			var anim:String = 'default';
			if (state == 'lose' && animation.exists('losing'))
				anim = 'losing';
			else if (state == 'win' && animation.exists('win'))
				anim = 'win';

			// 只在状态变化时切换，避免每次血量刷新都重播动画导致动画卡在第一帧。
			if (animation.curAnim.name != anim)
			{
				curStateFrame = (anim == 'losing') ? 1 : ((anim == 'win') ? 2 : 0);
				animation.play(anim, true);
				updateHitbox();
			}
			return;
		}

		var f:Int = 0;
		switch (state)
		{
			case 'lose': f = (framesCount > 1) ? 1 : 0;
			case 'win':  f = (framesCount > 2) ? 2 : 0; // 无独立赢帧时回退到正常帧(0)，而不是输帧(1)
			default:     f = 0;
		}
		if (f > framesCount - 1) f = framesCount - 1;
		if (f < 0) f = 0;
		animation.curAnim.curFrame = f;
	}


	public var autoAdjustOffset:Bool = true;
	override function updateHitbox()
	{
		super.updateHitbox();
		if(autoAdjustOffset)
		{
			var stateOffset:Array<Float> = isAnimated ? perAnimIconOffsets[curStateFrame % perAnimIconOffsets.length] : null;
			offset.x = iconOffsets[0] + (stateOffset != null ? stateOffset[0] : 0);
			offset.y = iconOffsets[1] + (stateOffset != null ? stateOffset[1] : 0);
		}
	}

	public function getCharacter():String {
		return char;
	}
}
