package objects;

import haxe.Json;
import backend.ExtraKeysHandler;
import openfl.utils.AssetType;
import shaders.RGBPalette.RGBShaderReference;

/**
 * 原版 FNF (V-Slice) 风格的 Hold Cover：
 * 长条按住期间在对应 strum 箭头居中位置循环播放光效，
 * 长条完整按完时在末尾播放 end 爆发动画。
 *
 * 配置兼容 NoteSplash 的方式：
 *  - 默认素材：assets/shared/images/holdCover/hsv/holdCover{Color}.png/.xml
 *    （Color = Purple|Blue|Green|Red），动画前缀 holdCoverStart{Color} / holdCover{Color} / holdCoverEnd{Color}
 *  - 皮肤：ClientPrefs.data.holdCoverSkin（后缀，如 -Custom），经 Note.resolveSkinPath 解析
 *    "HSV" / "Default" → hsv/ 子目录；自定义皮肤 → holdCover/ 根目录
 *  - RGB 皮肤：holdCover/sustain_cover.png + RGB shader 按列染色
 *  - 每色可带 JSON 配置：默认 hsv/ 子目录下，自定义皮肤在 holdCover/ 根目录
 *    格式 { "start": "...", "hold": "...", "end": "...", "fps": 24, "offsets": [0,0], "scale": 1 }
 *  - 可用 states/editors/HoldCoverEditorState 编辑并保存 JSON
 */
typedef HoldCoverAnim = {
	@:optional var start:String;
	@:optional var hold:String;
	@:optional var end:String;
	@:optional var fps:Int;
	@:optional var offsets:Array<Float>;
	/** 三段动画各自的偏移（可选，优先于 offsets），在现有居中的基础上叠加 */
	@:optional var startOffset:Array<Float>;
	@:optional var holdOffset:Array<Float>;
	@:optional var endOffset:Array<Float>;
	@:optional var scale:Float;
};

typedef HoldCoverConfig = {
	scale:Float,
	anims:Map<String, HoldCoverAnim>,
	/** 禁用 RGB 染色（true 时显示灰白素体原图），由 JSON disableRGB 读取 */
	?disableRGB:Bool
};

class NoteHoldCover extends FlxSprite
{
	public static final COVER_COLORS:Array<String> = ['Purple', 'Blue', 'Green', 'Red'];
	public static final defaultHoldCover:String = 'holdCover/holdCover';

	/** RGB 皮肤：单张素体图（仿 Matt V3 sustain_cover），按列用 RGB shader 染色 */
	public static final rgbSkinName:String = 'RGB';
	public static final rgbHoldCover:String = 'holdCover/sustain_cover';

	/** RGB 染色 shader（仅 RGB 皮肤启用） */
	public var rgbShader:RGBShaderReference = null;

	/** 已加载配置缓存：key = color + postfix */
	public static var configs:Map<String, HoldCoverConfig> = new Map<String, HoldCoverConfig>();

	/** 跟随的目标 strum（每帧同步位置 / 透明度，兼容 modchart 移动） */
	public var targetStrum:StrumNote = null;
	/** 正在播放 end 动画 */
	public var isEnding:Bool = false;
	/** 距上次被长条命中刷新的时间；超过 timeout 自动隐藏（断连兜底） */
	public var holdTimer:Float = 0;
	/** 超时时间（秒），由 PlayState 在每次命中时按 stepCrochet 更新 */
	public var timeout:Float = 0.35;
	/** 编辑器预览时置 true，禁止自动隐藏 */
	public var freezeHold:Bool = false;

	public var coverColor:String;
	public var config:HoldCoverConfig;

	/** 附加偏移（来自 JSON 配置 / 编辑器），在 update 定位时叠加 */
	public var animOffset:Array<Float> = [0, 0];

	public function new(strum:StrumNote, data:Int, ?config:HoldCoverConfig, ?forceRGB:Null<Bool>, ?atlasPath:String = null)
	{
		super(strum.x, strum.y);
		targetStrum = strum;
		coverColor = getColorForData(data);
		var useRGB:Bool = (forceRGB != null) ? forceRGB : isRGBSkin();

		if (useRGB)
		{
			if (config == null) config = getRGBConfig();
			this.config = config;
			frames = Paths.getSparrowAtlas(getRGBAtlasPath());
			reloadAnims(getRGBAnim());
			applyRGB(data);
		}
		else
		{
			if (config == null) config = getConfigForColor(coverColor);
			this.config = config;
			// atlasPath：编辑器强制指定基础 HSV 图集（忽略全局皮肤后缀），默认按当前皮肤解析
			frames = Paths.getSparrowAtlas((atlasPath != null) ? atlasPath : getColorAtlasPath(coverColor));
			reloadAnims(getAnim(coverColor));
		}

		antialiasing = ClientPrefs.data.antialiasing;
		refreshScale();
		visible = false;
	}

	// ---- 配置 / 皮肤解析（兼容 NoteSplash 方式）----

	/** 是否为 RGB 皮肤（单张素体 + 按列 RGB 染色） */
	public static function isRGBSkin():Bool
	{
		var skin:String = ClientPrefs.data.holdCoverSkin.trim();
		return skin.length > 0 && skin.toLowerCase() == rgbSkinName.toLowerCase();
	}

	/** RGB 皮肤的三段动画默认前缀（对应 sustain_cover 图集帧名） */
	public static function rgbDefaultAnim():HoldCoverAnim
	{
		return {
			start: 'sustain cover pre',
			hold: 'sustain cover0',
			end: 'sustain cover end',
			fps: 24,
			offsets: [0, 0],
			scale: 1
		};
	}

	/** 从 holdCover/sustain_cover.json 读取 RGB 皮肤的完整配置（可调 scale/offsets/动画前缀） */
	public static function getRGBConfig():HoldCoverConfig
	{
		if (configs.exists('RGB' + getSongOverride())) return configs.get('RGB' + getSongOverride());

		var cfg:HoldCoverConfig = {scale: 1, anims: new Map<String, HoldCoverAnim>()};
		var anim:HoldCoverAnim = rgbDefaultAnim();

		var jsonPath:String = getRGBConfigJsonPath();
		if (Paths.fileExists('images/$jsonPath.json', AssetType.TEXT))
		{
			try
			{
				var raw:Dynamic = Json.parse(Paths.getTextFromFile('images/$jsonPath.json'));
				var parsed:HoldCoverAnim = parseAnim(raw);
				if (parsed.start != null) anim.start = parsed.start;
				if (parsed.hold != null) anim.hold = parsed.hold;
				if (parsed.end != null) anim.end = parsed.end;
				if (parsed.fps != null) anim.fps = parsed.fps;
				if (parsed.offsets != null) anim.offsets = parsed.offsets;
				if (parsed.startOffset != null) anim.startOffset = parsed.startOffset;
				if (parsed.holdOffset != null) anim.holdOffset = parsed.holdOffset;
				if (parsed.endOffset != null) anim.endOffset = parsed.endOffset;
				if (raw.scale != null) cfg.scale = raw.scale;
				if (raw.disableRGB != null) cfg.disableRGB = (raw.disableRGB == true);
			}
			catch (e:Dynamic) {}
		}
		cfg.anims.set('RGB', anim);
		configs.set('RGB' + getSongOverride(), cfg);
		return cfg;
	}

	/** RGB 皮肤实际使用的动画（读 JSON，含 offsets 偏移） */
	public static function getRGBAnim():HoldCoverAnim
	{
		var cfg:HoldCoverConfig = getRGBConfig();
		var anim:HoldCoverAnim = cfg.anims.get('RGB');
		return (anim != null) ? anim : rgbDefaultAnim();
	}

	/** 根据列 RGB 颜色配置 shader（仅 RGB 皮肤调用） */
	public function applyRGB(data:Int):Void
	{
		var idx:Int = getCoverStyleIndex(data);
		rgbShader = new RGBShaderReference(this, Note.initializeGlobalRGBShader(idx));
		var arr:Array<FlxColor> = (idx > -1 && idx < ClientPrefs.data.arrowRGB.length) ? ClientPrefs.data.arrowRGB[idx] : null;
		if (PlayState.isPixelStage && idx > -1 && idx < ClientPrefs.data.arrowRGBPixel.length) arr = ClientPrefs.data.arrowRGBPixel[idx];
		// Extra Keys：arrowRGB 未补齐（越界/缺失）时从 extrakeys.json 全局色表兜底，避免染色失效
		if (arr == null && ExtraKeysHandler.instance != null && ExtraKeysHandler.instance.data != null
			&& ExtraKeysHandler.instance.data.colors != null && idx > -1 && idx < ExtraKeysHandler.instance.data.colors.length)
		{
			var ekC = ExtraKeysHandler.instance.data.colors[idx];
			if (ekC != null) arr = [FlxColor.fromString('#' + ekC.inner), FlxColor.fromString('#' + ekC.border), FlxColor.fromString('#' + ekC.outline)];
		}
		if (arr != null && arr.length >= 3)
		{
			@:bypassAccessor
			{
				rgbShader.r = arr[0];
				rgbShader.g = arr[1];
				rgbShader.b = arr[2];
			}
		}
		rgbShader.enabled = true;
		if (PlayState.SONG != null && PlayState.SONG.disableNoteRGB) rgbShader.enabled = false;
		// JSON 配置的 disableRGB 优先于全局（用户可强制关闭某素材的染色）
		if (this.config != null && this.config.disableRGB) rgbShader.enabled = false;
	}

	// LE LTS 双侧：本 hold cover 生效的样式索引。
	// 双侧下两侧都按运行时档位取色——对手侧用 oppMania、玩家侧用 totalColumns-1；
	// 不能用静态 Note.styleIndex——双侧谱面无 mania 字段时它回退 4 键档，
	// 玩家多键列（data ≥ 4）会错色（change keycount 改键后同样生效）。
	function getCoverStyleIndex(data:Int):Int
	{
		if (targetStrum != null && PlayState.instance != null && PlayState.instance.isLeDualChart)
		{
			var mania:Int = targetStrum.isPlayerSide() ? (PlayState.instance.totalColumns - 1) : PlayState.instance.oppMania;
			if (ExtraKeysHandler.instance != null) return ExtraKeysHandler.instance.globalIndex(mania, data);
			return data % 4;
		}
		return Note.styleIndex(data);
	}

	public function getColorForData(data:Int):String
	{
		// Extra Keys：多键按 EK 样式方向映射素材色（与箭头/飞溅配色一致），
		// 使 HSV 素材（仅 4 色）尽量贴近列色（如 6k 列4 青→Blue、列5 蓝→Blue）；映射不到回退 4 色周期
		try {
			var style:Int = getCoverStyleIndex(data);
			if (ExtraKeysHandler.instance != null && ExtraKeysHandler.instance.data != null
				&& ExtraKeysHandler.instance.data.animations != null
				&& style > -1 && style < ExtraKeysHandler.instance.data.animations.length)
			{
				var ekNote:String = ExtraKeysHandler.instance.data.animations[style].note;
				if (ekNote == 'purple') return 'Purple';
				else if (ekNote == 'blue') return 'Blue';
				else if (ekNote == 'green') return 'Green';
				else if (ekNote == 'red') return 'Red';
			}
		} catch (e:Dynamic) {}
		var i:Int = data % COVER_COLORS.length;
		if (i < 0) i += COVER_COLORS.length;
		return COVER_COLORS[i];
	}

	/** 单曲自定义 holdCover 子目录（SONG.holdCoverSkin，基于 images/ 解析），空则用全局皮肤 */
	public static function getSongOverride():String
	{
		if (PlayState.SONG != null && PlayState.SONG.holdCoverSkin != null)
		{
			var s:String = PlayState.SONG.holdCoverSkin.trim();
			if (s.length > 0) return s;
		}
		return '';
	}

	public static function getHoldCoverPostfix():String
	{
		var skinName:String = ClientPrefs.data.holdCoverSkin.trim();
		// HSV / Default 皮肤均无后缀，素材位于 holdCover/hsv/ 子目录
		if (skinName.length == 0 || skinName.toLowerCase() == 'hsv' || skinName == ClientPrefs.defaultData.holdCoverSkin)
			return '';
		return '-' + skinName.toLowerCase().replace(' ', '-');
	}

	public static function getColorAtlasPath(color:String):String
	{
		var ov:String = getSongOverride();
		if (ov.length > 0) // 单曲自定义目录：images/holdCover/{目录}/holdCover{Color}
			return 'holdCover/$ov/holdCover' + color;
		var postfix:String = getHoldCoverPostfix();
		if (postfix.length == 0)
			return 'holdCover/hsv/holdCover' + color;
		return 'holdCover/holdCover' + color + postfix;
	}

	/** RGB 素体图路径：单曲自定义目录则用 images/holdCover/{目录}/sustain_cover */
	public static function getRGBAtlasPath():String
	{
		var ov:String = getSongOverride();
		if (ov.length > 0) return 'holdCover/$ov/sustain_cover';
		return rgbHoldCover;
	}

	/** 获取 JSON 配置文件的路径（不含 images/ 前缀），默认皮肤指向 hsv/ 子目录 */
	public static function getConfigJsonPath(color:String):String
	{
		var ov:String = getSongOverride();
		if (ov.length > 0)
			return 'holdCover/$ov/holdCover' + color;
		var postfix:String = getHoldCoverPostfix();
		if (postfix.length == 0)
			return 'holdCover/hsv/holdCover' + color;
		return 'holdCover/holdCover' + color + postfix;
	}

	/** RGB 皮肤的 JSON 配置路径 */
	public static function getRGBConfigJsonPath():String
	{
		var ov:String = getSongOverride();
		if (ov.length > 0) return 'holdCover/$ov/sustain_cover';
		return 'holdCover/sustain_cover';
	}

	public static function getConfigForColor(color:String):HoldCoverConfig
	{
		var key:String = color + getHoldCoverPostfix() + getSongOverride();
		if (configs.exists(key)) return configs.get(key);

		var cfg:HoldCoverConfig = createDefaultConfig(color);
		var jsonPath:String = getConfigJsonPath(color);
		if (Paths.fileExists('images/$jsonPath.json', AssetType.TEXT))
		{
			try
			{
				var raw:Dynamic = Json.parse(Paths.getTextFromFile('images/$jsonPath.json'));
				var anim:HoldCoverAnim = parseAnim(raw);
				cfg.anims.set(color, anim);
				if (raw.scale != null) cfg.scale = raw.scale;
				if (raw.disableRGB != null) cfg.disableRGB = (raw.disableRGB == true);
			}
			catch (e:Dynamic) {}
		}
		configs.set(key, cfg);
		return cfg;
	}

	public static function createDefaultConfig(color:String):HoldCoverConfig
	{
		var cfg:HoldCoverConfig = {scale: 1, anims: new Map<String, HoldCoverAnim>()};
		cfg.anims.set(color, {
			start: 'holdCoverStart' + color,
			hold: 'holdCover' + color,
			end: 'holdCoverEnd' + color,
			fps: 24,
			offsets: [0, 0],
			scale: 1
		});
		return cfg;
	}

	public static function parseAnim(raw:Dynamic):HoldCoverAnim
	{
		var a:HoldCoverAnim = {start: null, hold: null, end: null, fps: 24, offsets: [0, 0], scale: 1};
		if (raw.start != null) a.start = raw.start;
		if (raw.hold != null) a.hold = raw.hold;
		if (raw.end != null) a.end = raw.end;
		if (raw.fps != null) a.fps = raw.fps;
		if (raw.offsets != null && raw.offsets.length >= 2) a.offsets = [raw.offsets[0], raw.offsets[1]];
		if (raw.startOffset != null && raw.startOffset.length >= 2) a.startOffset = [raw.startOffset[0], raw.startOffset[1]];
		if (raw.holdOffset != null && raw.holdOffset.length >= 2) a.holdOffset = [raw.holdOffset[0], raw.holdOffset[1]];
		if (raw.endOffset != null && raw.endOffset.length >= 2) a.endOffset = [raw.endOffset[0], raw.endOffset[1]];
		if (raw.scale != null) a.scale = raw.scale;
		return a;
	}

	function getAnim(color:String):HoldCoverAnim
	{
		if (config != null && config.anims.exists(color)) return config.anims.get(color);
		return {start: 'holdCoverStart' + color, hold: 'holdCover' + color, end: 'holdCoverEnd' + color, fps: 24, offsets: [0, 0], scale: 1};
	}

	/** 三段动画各自的偏移（在居中基础上叠加），优先于 animOffset */
	public var startOffset:Array<Float> = [0, 0];
	public var holdOffset:Array<Float> = [0, 0];
	public var endOffset:Array<Float> = [0, 0];

	// ---- 动画（供编辑器热更新）----

	public function reloadAnims(?anim:HoldCoverAnim):Void
	{
		if (anim == null) anim = getAnim(coverColor);

		var fps:Int = (anim.fps != null) ? anim.fps : 24;
		startOffset = (anim.startOffset != null && anim.startOffset.length >= 2) ? [anim.startOffset[0], anim.startOffset[1]] : [0.0, 0.0];
		holdOffset  = (anim.holdOffset  != null && anim.holdOffset.length  >= 2) ? [anim.holdOffset[0],  anim.holdOffset[1]]  : [0.0, 0.0];
		endOffset   = (anim.endOffset   != null && anim.endOffset.length   >= 2) ? [anim.endOffset[0],   anim.endOffset[1]]   : [0.0, 0.0];
		animOffset = (anim.offsets != null && anim.offsets.length >= 2) ? [anim.offsets[0], anim.offsets[1]] : [0.0, 0.0]; // 全局偏移，叠加于各段偏移之上
		addSafe('start', (anim.start != null) ? anim.start : ('holdCoverStart' + coverColor), fps, false);
		addSafe('hold', (anim.hold != null) ? anim.hold : ('holdCover' + coverColor), fps, true);
		addSafe('end', (anim.end != null) ? anim.end : ('holdCoverEnd' + coverColor), fps, false);
		animation.finishCallback = onAnimFinished;
	}

	public function reloadAtlas(path:String):Void
	{
		try
		{
			frames = Paths.getSparrowAtlas(path);
		}
		catch (e:Dynamic) {}
		reloadAnims();
	}

	function addSafe(name:String, prefix:String, fps:Int, loop:Bool):Void
	{
		animation.remove(name); // 覆盖旧动画（clearAnimations 在本 flixel 版本为私有）
		animation.addByPrefix(name, prefix, fps, loop);
	}

	/** 当前图集中是否存在以指定前缀开头的帧 */
	public function prefixExists(prefix:String):Bool
	{
		if (frames == null) return false;
		for (f in frames.frames)
			if (f.name.startsWith(prefix))
				return true;
		return false;
	}

	/** 直接设置统一附加偏移（start/hold/end 共用），下一帧 update 生效（编辑器用） */
	public function setOffsets(off:Array<Float>):Void
	{
		if (off != null && off.length >= 2)
		{
			startOffset = [off[0], off[1]];
			holdOffset = [off[0], off[1]];
			endOffset = [off[0], off[1]];
			animOffset = [off[0], off[1]];
		}
	}

	/** 获取当前播放动画段应叠加的偏移（start/hold/end 各自独立） */
	function getCurrentOffset():Array<Float>
	{
		if (animation != null && animation.curAnim != null)
		{
			switch (animation.curAnim.name)
			{
				case 'start': return startOffset;
				case 'hold':  return holdOffset;
				case 'end':   return endOffset;
			}
		}
		return [0.0, 0.0];
	}

	// ---- 缩放 / 居中 / 回调 ----

	function refreshScale():Void
	{
		var s:Float = 0.7;
		var cfgScale:Float = (config != null) ? config.scale : 1;
		if (targetStrum != null && targetStrum.width > 0)
		{
			// RGB 皮肤使用 Matt suatain_cover：以 300x400 盒为基准改为套用素体宽度，
			// 使其覆盖范围贴近箭头（源宽 ~161），并保留 config.scale 缩放。
			if (isRGBSkin())
				s = targetStrum.width / 161 * cfgScale;
			else
				s = targetStrum.width * 1.91 / 300 * cfgScale;
		}
		if (Math.abs(s - scale.x) > 0.001)
		{
			scale.set(s, s);
			updateHitbox();
		}
	}

	function onAnimFinished(name:String):Void
	{
		switch (name)
		{
			case 'start':
				animation.play('hold', true);
			case 'end':
				visible = false;
				isEnding = false;
		}
	}

	/** 长条头命中：播放 start -> hold 循环 */
	public function startHold():Void
	{
		isEnding = false;
		holdTimer = 0;
		visible = true;
		animation.play('start', true);
	}

	/** 长条中段持续命中：刷新存活计时，必要时恢复显示 */
	public function keepHold():Void
	{
		holdTimer = 0;
		if (isEnding) return;
		if (!visible || animation.curAnim == null
			|| (animation.curAnim.name != 'hold' && animation.curAnim.name != 'start'))
			startHold();
	}

	/** 长条末尾命中：播放 end 爆发动画，播完自动隐藏 */
	public function playEnd():Void
	{
		holdTimer = 0;
		visible = true;
		isEnding = true;
		animation.play('end', true);
	}

	/** 隐藏（松手 / miss）。force=false 时不打断正在播放的 end 动画 */
	public function hideCover(force:Bool = true):Void
	{
		if (isEnding && !force) return;
		isEnding = false;
		holdTimer = 0;
		visible = false;
	}

	override function update(elapsed:Float)
	{
		super.update(elapsed);

		if (targetStrum != null)
		{
			refreshScale();

			// 位置由 JSON 偏移决定（以 strum 左上角为锚点）：全局 offsets + 各段自身偏移，不做自动居中
			// LE LTS 双侧：按所属 strum 侧取缩放（玩家=playerStrumScale、对手=opponentStrumScale；非双侧=全局）
			var k:Float = PlayState.getNoteSideScale(targetStrum.isPlayerSide());
			var curOff:Array<Float> = getCurrentOffset();
			x = targetStrum.x + (curOff[0] + animOffset[0]) * k;
			y = targetStrum.y + (curOff[1] + animOffset[1]) * k;
			alpha = targetStrum.alpha;
		}

		// 断连兜底：一段时间没有被长条命中刷新就自动隐藏
		if (!freezeHold && visible && !isEnding)
		{
			holdTimer += elapsed;
			if (holdTimer > timeout)
			{
				holdTimer = 0;
				visible = false;
			}
		}
	}

	override function destroy()
	{
		targetStrum = null;
		super.destroy();
	}
}
