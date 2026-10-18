package objects;

import backend.animation.PsychAnimationController;
import backend.NoteTypesConfig;
import backend.ClientPrefs;
import backend.ExtraKeysHandler;

import shaders.RGBPalette;
import shaders.RGBPalette.RGBShaderReference;
import shaders.ColorSwap;

import objects.StrumNote;

import flixel.math.FlxRect;
import flixel.graphics.frames.FlxAtlasFrames;

using StringTools;

typedef EventNote = {
	strumTime:Float,
	event:String,
	value1:String,
	value2:String,
	value3:String,
	value4:String
}

/**
 * 预加载音符数据 - 完整保存音符初始化所需的所有信息
 * 注：原为 typedef 匿名结构体（HXCPP 上编译为 hx::Anon 动态对象，字段访问走哈希查找且每字段装箱）。
 * 高密度纯箭头谱（数万音符）下会占用 10~15MB 且 GC 需扫描每对象 19 个 Dynamic 槽。
 * 改为 @:structInit final class 后：构造语法 `{...}` 完全兼容、调用侧零改动，字段变原生值类型，
 * 内存降至约 1/3~1/4、字段访问快一个数量级、GC 扫描开销大减。
 */
@:structInit final class PreloadedChartNote {
	public var strumTime:Float;
	public var noteData:Int;
	public var rawColumn:Int; // 原始谱面列号，未取模，供重映射时使用
	public var mustPress:Bool;
	public var noteType:String;
	public var animSuffix:String;
	public var gfNote:Bool;
	public var isSustainNote:Bool;
	public var sustainLength:Float;
	public var earlyHitMult:Float; // 提前命中窗口倍率（供尾条判定优化方案B使用）
	public var parentIndex:Int; // 父音符在预加载数组中的索引
	public var previousNoteIndex:Int; // 前一个音符在预加载数组中的索引
	public var posOffsetX:Float;
	public var posOffsetY:Float;
	public var correctionOffset:Float;
	public var curStepCrochet:Float;
	public var needsOldNoteScaleAdjust:Bool; // 是否需要调整前一个音符的 scale
	public var isPixelStage:Bool;
	public var hasDownScrollCorrection:Bool;
}

typedef NoteSplashData = {
	disabled:Bool,
	texture:String,
	useGlobalShader:Bool, //breaks r/g/b but makes it copy default colors for your custom note
	useRGBShader:Bool,
	antialiasing:Bool,
	r:FlxColor,
	g:FlxColor,
	b:FlxColor,
	a:Float
}

/**
 * The note object used as a data structure to spawn and manage notes during gameplay.
 * 
 * If you want to make a custom note type, you should search for: "function set_noteType"
**/
class Note extends FlxSprite
{
	//This is needed for the hardcoded note types to appear on the Chart Editor,
	//It's also used for backwards compatibility with 0.1 - 0.3.2 charts.
	public static final defaultNoteTypes:Array<String> = [
		'', //Always leave this one empty pls
		'Alt Animation',
		'Hey!',
		'Hurt Note',
		'GF Sing',
		'No Animation'
	];

	public var extraData:Map<String, Dynamic> = new Map<String, Dynamic>();

	public var strumTime:Float = 0;
	public var noteData:Int = 0;
	/** 原始谱面列号（未经 % 取模），用于重映射 noteData。4 键下等于 noteData。 */
	public var noteColumnRaw:Int = 0;
	// 记录 construct/reloadNote 后普通音符的基准 scale，供对象池 prepareForReuse 复位
	// （避免被前驱 sustain 改过的 scale.y 在复用普通音符时累积错乱）。
	public var baseScaleX:Float = 1;
	public var baseScaleY:Float = 1;

	public var mustPress:Bool = false;
	public var canBeHit:Bool = false;
	public var tooLate:Bool = false;

	public var wasGoodHit:Bool = false;
	public var missed:Bool = false;

	public var ignoreNote:Bool = false;
	public var hitByOpponent:Bool = false;
	public var noteWasHit:Bool = false;
	public var prevNote:Note;
	public var nextNote:Note;

	public var spawned:Bool = false;
	// 在预加载跟踪数组 spawnedNotes 中的索引；用于 invalidateNote 时解除强引用。
	// -1 表示未通过优化路径生成（传统/编辑器路径），此时 invalidateNote 不会触碰 spawnedNotes。
	public var preloadIndex:Int = -1;

	public var tail:Array<Note> = []; // for sustains
	public var parent:Note;
	
	public var blockHit:Bool = false; // only works for player

	public var sustainLength:Float = 0;
	public var isSustainNote:Bool = false;
	public var noteType(default, set):String = null;

	public var eventName:String = '';
	public var eventLength:Int = 0;
	public var eventVal1:String = '';
	public var eventVal2:String = '';

	public var rgbShader:RGBShaderReference;
	public static var globalRgbShaders:Array<RGBPalette> = [];
	/** UI 态 mania 覆盖（仅 NotesColorSubState 等菜单界面使用）：>=0 时 styleIndex/StrumNote 按它取样式映射，游戏内恒为 -1 不受影响 */
	public static var uiManiaOverride:Int = -1;
	public var colorSwap:ColorSwap;
	public static var globalColorSwapShaders:Array<ColorSwap> = [];
	// HSV 模式下本音符 colorSwap 绑定的样式索引（LE LTS 双侧：对手侧构造时按玩家档绑定，defaultHSV 按侧重绑）
	public var colorSwapIndex:Int = -1;

	/**
	 * 皮肤版本号：每次切换当前皮肤（如切到不同 note skin）时自增。
	 * 音符通过 lastSkinVersion 记录自己加载时的版本，仅在版本不匹配时（即皮肤已变）
	 * 才重新加载帧，从而避免对“尚未出现的音符”做无谓的 reloadNote 卡死整局。
	 */
	public static var noteSkinVersion:Int = 0;
	public var lastSkinVersion:Int = -1;
	public var inEditor:Bool = false;

	public var animSuffix:String = '';
	public var gfNote:Bool = false;
	public var earlyHitMult:Float = 1;
	public var lateHitMult:Float = 1;
	public var lowPriority:Bool = false;

	public static var SUSTAIN_SIZE:Int = 44;

	/** kadeHoldVisual 开启时，长条段之间留出的间隙系数（<1 使每段比一个 step 略矮，露出断续块缝） */
	public static function kadeHoldGapScale():Float {
		return ClientPrefs.data.kadeHoldVisual ? 0.9 : 1.0;
	}

	/**
	 * Kade 长条视觉：判定区“提前吞噬”量（毫秒）。
	 * 已命中的长条（prevNote.wasGoodHit）在其 strumTime 到来前提前 killPre 毫秒隐藏，
	 * 让长条前端贴住判定线逐段被吃掉。当前提前 1 个 step；想更激进可改 1.5 或 2。
	 */
	public static function kadeHoldKillPre():Float {
		return Conductor.stepCrochet * 1.0;
	}
	public static var swagWidth:Float = 160 * 0.7;
	// 当前 mania 档位下每列的动画前缀（purple/blue/green/red/rombus/circle...）。
	// 由 PlayState.applyMania() 按 extrakeys.json 动态填充；4 键默认值保持向后兼容。
	public static var colArray:Array<String> = ['purple', 'blue', 'green', 'red'];

	// LE LTS 双侧：本音符实际使用的列配色/动画前缀数组。
	// null = 用全局 colArray（玩家侧/Psych/EK 路径）；对手侧音符由 PlayState 设为 opponentColArray。
	public var noteColArray:Array<String> = null;

	// LE LTS 双侧：本音符生成时刻的 EK 档位（玩家/对手）。change keycount 改键后 PlayState 会
	// 折叠重映射音符并把这三者更新为新档，使动画名（noteColArray）与着色（getStyleIndex）始终匹配。
	public var genMania:Int = -1;      // 生成时玩家侧档位（-1=用全局 SONG.mania）
	public var genOppMania:Int = -1;   // 生成时对手侧档位（-1=用运行时 oppMania）
	public var genStrumScale:Float = 1; // 生成时 strum 缩放（loadNoteAnims 记录，供改键后按新 scale 重缩）

	// LE LTS 双侧：取本音符生效的列配色数组中的第 data 项（取模防御越界）。
	// noteColArray 未设置时回退全局 colArray，保证 Psych/EK 路径零影响。
	inline function colAt(data:Int):String
	{
		var arr:Array<String> = noteColArray;
		if (arr == null || arr.length == 0) arr = colArray;
		return arr[data % arr.length];
	}

	// LE LTS 双侧：PlayState 设置 noteColArray 后刷新本音符（及前驱长条）的动画帧与着色，使对手侧音符立即使用正确配色。
	// 注意：loadNoteAnims 只注册了构造时 colAt 色名的动画帧；切换 noteColArray 后新色名的 Scroll/hold 帧可能从未注册，
	// 直接 play 会落空（动画不生效），故播放前先按当前 colAt 色名补齐动画。
	public function refreshNoteVisual():Void
	{
		if (noteData < 0) return;
		ensureAnimForColor();
		if (!isSustainNote) animation.play(colAt(noteData) + 'Scroll');
		else if (prevNote != null)
		{
			prevNote.ensureAnimForColor();
			animation.play(colAt(noteData) + 'holdend');
			prevNote.animation.play(prevNote.colAt(prevNote.noteData) + 'hold');
		}
		// 着色按当前生效的侧（对手档）重刷；RGB/HSV 两模式都覆盖（HSV 下 defaultHSV 须用 getStyleIndex）
		if (ClientPrefs.data.arrowColorMode == 'HSV') defaultHSV();
		else defaultRGB();
	}

	// 确保当前 colAt 色名的 Scroll/hold 动画帧已注册（切换 noteColArray 后补注册，与 loadNoteAnims 的帧规则一致）
	function ensureAnimForColor():Void
	{
		if (frames == null) return;
		var name:String = colAt(noteData);
		if (name == null) return;
		var framePrefix:String = hasNoteFrame(name) ? name : 'green';
		if (isSustainNote)
		{
			if (animation.getByName(name + 'holdend') == null)
				attemptToAddAnimationByPrefix(name + 'holdend', framePrefix + ' hold end', 24, true);
			if (animation.getByName(name + 'hold') == null)
				attemptToAddAnimationByPrefix(name + 'hold', framePrefix + ' hold piece', 24, true);
		}
		else if (animation.getByName(name + 'Scroll') == null)
			attemptToAddAnimationByPrefix(name + 'Scroll', framePrefix + '0', 24, true);
	}

	/**
	 * 把 noteData 映射到全局样式索引（用于 RGB shader 颜色表）。
	 * 标准4键下 style == noteData % 4；多键时查 extrakeys.json 的 keys[mania].notes 映射。
	 */
	public static function styleIndex(noteData:Int):Int
	{
		var mania = 3;
		if (Note.uiManiaOverride >= 0) mania = Note.uiManiaOverride;
		else if (PlayState.SONG != null && PlayState.SONG.mania != null) mania = PlayState.SONG.mania;
		if (ExtraKeysHandler.instance == null) return noteData % 4;
		return ExtraKeysHandler.instance.globalIndex(mania, noteData);
	}

	// LE LTS 双侧：本音符生效的样式索引（双侧下对手侧音符按对手键数档位查色表，非双侧=styleIndex）。
	// 优先用生成时刻记录的 genMania/genOppMania（change keycount 改键折叠后已更新为新档），
	// 保证与 noteColArray（动画名）一致；缺失时回退运行时档位。
	public function getStyleIndex():Int
	{
		var mania:Int = Note.uiManiaOverride >= 0 ? Note.uiManiaOverride : ((PlayState.SONG != null && PlayState.SONG.mania != null) ? PlayState.SONG.mania : 3);
		if (PlayState.instance != null && PlayState.instance.isLeDualChart)
		{
			if (!mustPress) mania = (genOppMania >= 0) ? genOppMania : PlayState.instance.oppMania;
			else if (genMania >= 0) mania = genMania;
		}
		if (ExtraKeysHandler.instance == null) return noteData % 4;
		return ExtraKeysHandler.instance.globalIndex(mania, noteData);
	}
	public static var defaultNoteSkin(default, never):String = 'noteSkins/NOTE_assets';

	public var noteSplashData:NoteSplashData = {
		disabled: false,
		texture: null,
		antialiasing: !PlayState.isPixelStage,
		useGlobalShader: false,
		useRGBShader: (PlayState.SONG != null) ? !(PlayState.SONG.disableNoteRGB == true) : true,
		r: -1,
		g: -1,
		b: -1,
		a: ClientPrefs.data.splashAlpha
	};

	// Legacy HSV splash colors (mirror old Psych 0.6.3). Carried to NoteSplash in HSV mode.
	public var noteSplashHue:Float = 0;
	public var noteSplashSat:Float = 0;
	public var noteSplashBrt:Float = 0;

	public var offsetX:Float = 0;
	public var offsetY:Float = 0;
	public var offsetAngle:Float = 0;
	public var multAlpha:Float = 1;
	public var multSpeed(default, set):Float = 1;

	public var copyX:Bool = true;
	public var copyY:Bool = true;
	public var copyAngle:Bool = true;
	public var copyAlpha:Bool = true;

	public var hitHealth:Float = 0.02;
	public var missHealth:Float = 0.1;
	public var rating:String = 'unknown';
	public var ratingMod:Float = 0; //9 = unknown, 0.25 = shit, 0.5 = bad, 0.75 = good, 1 = sick
	public var ratingDisabled:Bool = false;

	public var texture(default, set):String = null;

	public var noAnimation:Bool = false;
	public var noMissAnimation:Bool = false;
	public var hitCausesMiss:Bool = false;
	public var distance:Float = 2000; //plan on doing scroll directions soon -bb

	public var hitsoundDisabled:Bool = false;
	public var hitsoundChartEditor:Bool = true;
	/**
	 * Forces the hitsound to be played even if the user's hitsound volume is set to 0
	**/
	public var hitsoundForce:Bool = false;
	public var hitsoundVolume(get, default):Float = 1.0;
	function get_hitsoundVolume():Float {
		if(ClientPrefs.data.hitsoundVolume > 0)
			return ClientPrefs.data.hitsoundVolume;
		return hitsoundForce ? hitsoundVolume : 0.0;
	}
	public var hitsound:String = 'hitsound';

	private function set_multSpeed(value:Float):Float {
		resizeByRatio(value / multSpeed);
		multSpeed = value;
		//trace('fuck cock');
		return value;
	}

	public function resizeByRatio(ratio:Float) //haha funny twitter shit
	{
		if(isSustainNote && animation.curAnim != null && !animation.curAnim.name.endsWith('end'))
		{
			scale.y *= ratio;
			updateHitbox();
		}
	}

	private function set_texture(value:String):String {
		if(texture != value) reloadNote(value);

		texture = value;
		return value;
	}

	public function defaultRGB()
	{
		var style:Int = getStyleIndex();
		var arr:Array<FlxColor> = (style > -1 && style < ClientPrefs.data.arrowRGB.length) ? ClientPrefs.data.arrowRGB[style] : null;
		if(PlayState.isPixelStage && style > -1 && style < ClientPrefs.data.arrowRGBPixel.length) arr = ClientPrefs.data.arrowRGBPixel[style];

		// Extra Keys：arrowRGB 未补齐（越界）时从 extrakeys.json 全局色表直接取色兜底，避免染色失效
		if (arr == null && ExtraKeysHandler.instance != null && ExtraKeysHandler.instance.data != null
			&& ExtraKeysHandler.instance.data.colors != null && style > -1 && style < ExtraKeysHandler.instance.data.colors.length)
		{
			var c = ExtraKeysHandler.instance.data.colors[style];
			if (c != null) arr = [FlxColor.fromString('#' + c.inner), FlxColor.fromString('#' + c.border), FlxColor.fromString('#' + c.outline)];
		}

		// 判断用 style 而非 noteData：4 键下二者相等；多键下 style 才是 arrowRGB 索引（Psych 原版
		// noteData <= arr.length 在多键列（noteData 4/5，arr 3 项）恒为 false，导致染色失效）。
		if (arr != null && noteData > -1)
		{
			rgbShader.r = arr[0];
			rgbShader.g = arr[1];
			rgbShader.b = arr[2];
		}
		else
		{
			rgbShader.r = 0xFFFF0000;
			rgbShader.g = 0xFF00FF00;
			rgbShader.b = 0xFF0000FF;
		}
	}

	/**
	 * Legacy HSV path: applies the arrow's hue/saturation/brightness shift from
	 * ClientPrefs.data.arrowHSV, and mirrors the values onto noteSplashHue/Sat/Brt
	 * so NoteSplash can pick them up in HSV mode. (Mirror of old Psych 0.6.3.)
	**/
	public function defaultHSV()
	{
		if (colorSwap == null) return;
		// LE LTS 双侧：按侧取样式索引（对手侧用对手键数档位），避免 HSV 模式下对手多键色相错用玩家档
		var style:Int = getStyleIndex();
		// 构造时 colorSwap 按当时（玩家档）索引绑定共享 shader；双侧下对手音符索引不符时重绑到当前侧档位
		if (colorSwapIndex != style)
		{
			colorSwap = Note.initializeGlobalColorSwapShader(style);
			shader = (PlayState.SONG != null && PlayState.SONG.disableNoteRGB) ? null : colorSwap.shader;
			colorSwapIndex = style;
		}
		if (style > -1 && style < ClientPrefs.data.arrowHSV.length)
		{
			var arr:Array<Int> = ClientPrefs.data.arrowHSV[style];
			colorSwap.hue = arr[0] / 360;
			colorSwap.saturation = arr[1] / 100;
			colorSwap.brightness = arr[2] / 100;
		}
		else
		{
			colorSwap.hue = 0;
			colorSwap.saturation = 0;
			colorSwap.brightness = 0;
		}
		noteSplashHue = colorSwap.hue;
		noteSplashSat = colorSwap.saturation;
		noteSplashBrt = colorSwap.brightness;
	}

	private function set_noteType(value:String):String {
		noteSplashData.texture = PlayState.SONG != null ? PlayState.SONG.splashSkin : 'noteSplashes/noteSplashes';
		if(ClientPrefs.data.arrowColorMode == 'HSV') defaultHSV();
		else defaultRGB();

		if(noteData > -1 && noteType != value) {
			switch(value) {
			case 'Hurt Note':
				ignoreNote = mustPress;

				if(ClientPrefs.data.arrowColorMode == 'HSV') {
					// Legacy HSV: override this note with a LOCAL ColorSwap (hue/sat/brt = 0)
					// so it renders UNSHIFTED (the danger texture's own warning colors),
					// without polluting the shared global shader.
					colorSwap = new ColorSwap();
					colorSwap.hue = 0;
					colorSwap.saturation = 0;
					colorSwap.brightness = 0;
					shader = colorSwap.shader;
					noteSplashHue = 0;
					noteSplashSat = 0;
					noteSplashBrt = 0;

					// 恢复专属危险箭头外观（仅非像素舞台，像素舞台没有对应的 pixelUI 危险贴图）：
					// 重新加载 noteSkins/hsv/HURTNOTE_assets（模组覆盖优先于原版，resolveSkinPath 已处理）。
					// 着色器仍是上面的本地 ColorSwap，去色后原样显示该危险贴图自带的警示配色。
					// 若某模组经 custom_notetypes 给 Hurt Note 指定了其它 texture，下方 applyNoteTypeData 会再次覆盖。
					if (!PlayState.isPixelStage)
						reloadNote('noteSkins/HURTNOTE_assets');
				} else {
						// note colors
						rgbShader.r = 0xFF101010;
						rgbShader.g = 0xFFFF0000;
						rgbShader.b = 0xFF990022;

						// splash data and colors
						noteSplashData.r = 0xFFFF0000;
						noteSplashData.g = 0xFF101010;
					}
					noteSplashData.texture = 'noteSplashes/noteSplashes-electric';

					// gameplay data
					lowPriority = true;
					missHealth = isSustainNote ? 0.25 : 0.1;
					hitCausesMiss = true;
					hitsound = 'cancelMenu';
					hitsoundChartEditor = false;
				case 'Alt Animation':
					animSuffix = '-alt';
				case 'No Animation':
					noAnimation = true;
					noMissAnimation = true;
				case 'GF Sing':
					gfNote = true;
			}
			if (value != null && value.length > 1) NoteTypesConfig.applyNoteTypeData(this, value);
			if (hitsound != 'hitsound' && hitsoundVolume > 0) Paths.sound(hitsound); //precache new sound for being idiot-proof
			noteType = value;
		}
		return value;
	}

	public function new(strumTime:Float, noteData:Int, ?prevNote:Note, ?sustainNote:Bool = false, ?inEditor:Bool = false, ?createdFrom:Dynamic = null)
	{
		super();

		animation = new PsychAnimationController(this);

		antialiasing = ClientPrefs.data.antialiasing;
		if(createdFrom == null) createdFrom = PlayState.instance;

		if (prevNote == null)
			prevNote = this;

		this.prevNote = prevNote;
		isSustainNote = sustainNote;
		this.inEditor = inEditor;
		this.moves = false;

		x += (ClientPrefs.data.middleScroll ? PlayState.STRUM_X_MIDDLESCROLL : PlayState.STRUM_X) + 50;
		// MAKE SURE ITS DEFINITELY OFF SCREEN?
		y -= 2000;
		this.strumTime = strumTime;
		if(!inEditor) this.strumTime += ClientPrefs.data.noteOffset;

		this.noteData = noteData;

		if(noteData > -1)
		{
			// RGB shader is always initialized (shared globals are referenced by NoteSplash /
			// VisualsSettings previews even in HSV mode). Only the sprite's active shader differs.
			rgbShader = new RGBShaderReference(this, initializeGlobalRGBShader(styleIndex(noteData)));
			var rgbDisabled:Bool = (PlayState.SONG != null && PlayState.SONG.disableNoteRGB);
			if(rgbDisabled) rgbShader.enabled = false;
			texture = '';

			// Legacy HSV path: override the sprite's shader with the shared ColorSwap shader.
			if(ClientPrefs.data.arrowColorMode == 'HSV') {
				colorSwap = Note.initializeGlobalColorSwapShader(styleIndex(noteData));
				colorSwapIndex = styleIndex(noteData);
				shader = rgbDisabled ? null : colorSwap.shader;
			}

			x += swagWidth * (noteData);
			if(!isSustainNote && noteData < colArray.length) { //Doing this 'if' check to fix the warnings on Senpai songs
				var animToPlay:String = '';
				animToPlay = colAt(noteData);
				animation.play(animToPlay + 'Scroll');
			}
		}

		// trace(prevNote);

		if(prevNote != null)
			prevNote.nextNote = this;

		if (isSustainNote && prevNote != null)
		{
			// Kade 长条视觉开启时长条完全不透明；关闭时保持原默认半透明
			if(ClientPrefs.data.kadeHoldVisual)
			{
				alpha = 1.0;
				multAlpha = 1.0;
			}
			else
			{
				alpha = 0.6;
				multAlpha = 0.6;
			}
			hitsoundDisabled = true;
			if(ClientPrefs.data.downScroll) flipY = true;

			offsetX += width / 2;
			copyAngle = false;

			animation.play(colAt(noteData) + 'holdend');

			updateHitbox();

			offsetX -= width / 2;

			if (PlayState.isPixelStage)
				offsetX += 30;

			if (prevNote.isSustainNote)
			{
				prevNote.animation.play(prevNote.colAt(prevNote.noteData) + 'hold');

				prevNote.scale.y *= Conductor.stepCrochet / 100 * 1.05;
				if(createdFrom != null && createdFrom.songSpeed != null) prevNote.scale.y *= createdFrom.songSpeed;

				if(PlayState.isPixelStage) {
					prevNote.scale.y *= 1.19;
					prevNote.scale.y *= (6 / height); //Auto adjust note size
				}
				prevNote.updateHitbox();
				// prevNote.setGraphicSize();
			}

			if(PlayState.isPixelStage)
			{
				scale.y *= PlayState.daPixelZoom;
				updateHitbox();
			}
			earlyHitMult = 0;
		}
		else if(!isSustainNote)
		{
			centerOffsets();
			centerOrigin();
		}
		x += offsetX;

		// 记录加载时的皮肤版本，供皮肤变更后懒加载判定
		lastSkinVersion = noteSkinVersion;
	}

	public static function initializeGlobalRGBShader(index:Int)
	{
		if(globalRgbShaders[index] == null)
		{
			var newRGB:RGBPalette = new RGBPalette();
			var arr:Array<FlxColor> = (!PlayState.isPixelStage) ? ClientPrefs.data.arrowRGB[index] : ClientPrefs.data.arrowRGBPixel[index];
			
			if (arr != null && arr.length >= 3)
			{
				newRGB.r = arr[0];
				newRGB.g = arr[1];
				newRGB.b = arr[2];
			}
			else
			{
				newRGB.r = 0xFFFF0000;
				newRGB.g = 0xFF00FF00;
				newRGB.b = 0xFF0000FF;
			}
			
			globalRgbShaders[index] = newRGB;
		}
		return globalRgbShaders[index];
	}

	/**
	 * Legacy HSV path: creates/caches a shared ColorSwap shader per note direction,
	 * seeded from ClientPrefs.data.arrowHSV. Mirrors initializeGlobalRGBShader so
	 * the legacy NotesColorSubState can edit these globals and see live updates.
	**/
	public static function initializeGlobalColorSwapShader(index:Int):ColorSwap
	{
		if(index < 0 || index >= ClientPrefs.data.arrowHSV.length) return new ColorSwap();
		if(globalColorSwapShaders[index] == null)
		{
			var cs:ColorSwap = new ColorSwap();
			if (index > -1 && index < ClientPrefs.data.arrowHSV.length)
			{
				var arr:Array<Int> = ClientPrefs.data.arrowHSV[index];
				cs.hue = arr[0] / 360;
				cs.saturation = arr[1] / 100;
				cs.brightness = arr[2] / 100;
			}
			globalColorSwapShaders[index] = cs;
		}
		return globalColorSwapShaders[index];
	}

	var _lastNoteOffX:Float = 0;
	static var _lastValidChecked:String; //optimization
	static var _skinPathCache:Map<String, String> = new Map();
	// 按皮肤 key 缓存 Sparrow atlas 帧数据：重映射时会对大量音符调用
	// reloadNote，若不缓存则每颗音符都重新解析 XML，大谱面会卡死。缓存后同一皮肤
	// 仅解析一次，重映射只重建每颗音符的动画帧（廉价）。
	static var _atlasCache:Map<String, FlxAtlasFrames> = new Map();
	static function getCachedSparrowAtlas(key:String):FlxAtlasFrames
	{
		if (_atlasCache.exists(key))
		{
			var cached:FlxAtlasFrames = _atlasCache.get(key);
			// 校验缓存是否仍然有效：切歌 / 清理内存时（clearStoredMemory、clearUnusedMemory）
			// 底层 FlxGraphic 会被销毁——bitmap 置空并从 FlxG.bitmap 缓存中移除。此时旧的
			// FlxAtlasFrames 仍指向这张已销毁的贴图，继续复用会让音符渲染成空白（“看不到滚动箭头纹理”）。
			// 一旦发现失效就丢弃并重新解析，从根本上避免这个问题，同时保留正常情况下的缓存收益。
			if (cached != null && cached.parent != null && cached.parent.bitmap != null
				&& FlxG.bitmap.get(cached.parent.key) == cached.parent)
				return cached;
			_atlasCache.remove(key);
		}
		var atlas:FlxAtlasFrames = Paths.getSparrowAtlas(key);
		if (atlas != null) _atlasCache.set(key, atlas);
		return atlas;
	}
	public var originalHeight:Float = 6;
	public var correctionOffset:Float = 0; //dont mess with this
	public function reloadNote(texture:String = '', postfix:String = '') {
		if(texture == null) texture = '';
		if(postfix == null) postfix = '';

		var skin:String = texture + postfix;
		if(texture.length < 1)
		{
			skin = PlayState.SONG != null ? PlayState.SONG.arrowSkin : null;
			if(skin == null || skin.length < 1)
				skin = defaultNoteSkin + postfix;
		}
		else rgbShader.enabled = false;

		var animName:String = null;
		if(animation.curAnim != null) {
			animName = animation.curAnim.name;
		}

		var skinPixel:String = skin;
		var lastScaleY:Float = scale.y;
		var skinPostfix:String = getNoteSkinPostfix();
		var customSkin:String = skin + skinPostfix;
		var path:String = PlayState.isPixelStage ? 'pixelUI/' : '';

		var customExists:Bool = false;
		if(PlayState.isPixelStage)
		{
			customExists = customSkin == _lastValidChecked || Paths.fileExists('images/' + path + customSkin + '.png', IMAGE);
		}
		else
		{
			if(customSkin == _lastValidChecked)
				customExists = true;
			else if(ClientPrefs.data.arrowColorMode == 'HSV')
			{
				var parts:Array<String> = customSkin.split('/');
				var filename:String = parts.pop();
				var folder:String = parts.join('/');
				customExists = Paths.fileExists('images/$folder/hsv/$filename.png', IMAGE) || Paths.fileExists('images/$customSkin.png', IMAGE);
			}
			else
			{
				customExists = Paths.fileExists('images/$customSkin.png', IMAGE);
			}
		}

		if(customExists)
		{
			skin = customSkin;
			_lastValidChecked = customSkin;
		}
		else skinPostfix = '';

		if(PlayState.isPixelStage) {
			// HSV 模式：优先加载 pixelUI/<folder>/hsv/<file> 的白色像素箭头（供 ColorSwap
			// 着色），保持 <base>ENDS<postfix> 的像素文件名格式；不存在则回退彩色像素贴图。
			var pixelSkin:String = skinPixel;
			if(ClientPrefs.data.arrowColorMode == 'HSV') {
				var parts:Array<String> = skinPixel.split('/');
				var filename:String = parts.pop();
				var folder:String = parts.join('/');
				var hsvSkin:String = (folder.length > 0 ? folder + '/' : '') + 'hsv/' + filename;
				var testPath:String = 'images/pixelUI/' + hsvSkin + (isSustainNote ? 'ENDS' : '') + skinPostfix + '.png';
				if(Paths.fileExists(testPath, IMAGE)) pixelSkin = hsvSkin;
			}
			if(isSustainNote) {
				var graphic = Paths.image('pixelUI/' + pixelSkin + 'ENDS' + skinPostfix);
				loadGraphic(graphic, true, Math.floor(graphic.width / 4), Math.floor(graphic.height / 2));
				originalHeight = graphic.height / 2;
			} else {
				var graphic = Paths.image('pixelUI/' + pixelSkin + skinPostfix);
				loadGraphic(graphic, true, Math.floor(graphic.width / 4), Math.floor(graphic.height / 5));
			}
			setGraphicSize(Std.int(width * PlayState.daPixelZoom));
			loadPixelNoteAnims();
			antialiasing = false;

			if(isSustainNote) {
				offsetX += _lastNoteOffX;
				_lastNoteOffX = (width - 7) * (PlayState.daPixelZoom / 2);
				offsetX -= _lastNoteOffX;
			}
		} else {
			frames = getCachedSparrowAtlas(getNoteSkinPath(skin));
			// 防护：若解析出的皮肤贴图加载失败（文件缺失/损坏），getSparrowAtlas 会返回 null，
			// 导致后续 addByPrefix / findByPrefix 崩溃。回退到默认皮肤并告警，避免整局崩溃。
			if (frames == null)
			{
				FlxG.log.warn('Note skin failed to load: "' + getNoteSkinPath(skin) + '", falling back to default "' + defaultNoteSkin + '"');
				frames = getCachedSparrowAtlas(defaultNoteSkin);
			}
			loadNoteAnims();
			if(!isSustainNote)
			{
				centerOffsets();
				centerOrigin();
			}
		}

		if(isSustainNote) {
			scale.y = lastScaleY;
		}
		updateHitbox();

		if(animName != null)
			animation.play(animName, true);
	}

	/**
	 * 对象池复用：在已有 frames/animation（construct 阶段已按当前皮肤加载好）的基础上，
	 * 仅复位"每次 spawn 会变化"的字段，并重跑与 `new` 一致的偏移/sustain 副作用逻辑，
	 * **不调用 reloadNote**（避免昂贵的皮肤探测 + 帧重新解析 + addByPrefix 字符串扫描）。
	 *
	 * 安全前提：仅当 `noteOptimization && notePooling`（玩家显式开启对象池）时由 PlayState 池化工厂调用。
	 * 默认（notePooling=false）下走原始 new/destroy，每个音符都是独立新对象，脚本语义不变。
	 * 皮肤变更时帧仍可通过 ensureCurrentSkin/updateManiaStyle 显式重载，不受此处跳过 reloadNote 影响。
	 *
	 * @param strumTime   音符命中时间
	 * @param noteData    重映射后的列号
	 * @param prevNote    前一个音符（用于 sustain 连接链；为 null 时自引用）
	 * @param isSustain   是否为长条音符
	 */
	public function prepareForReuse(strumTime:Float, noteData:Int, prevNote:Note, isSustain:Bool):Void
	{
		// —— 复位每次 spawn 会变化的状态字段 ——
		// 注意：以下字段若遗漏，池化复用时会产生判定错乱（脏值被复用）。
		// canBeHit 必须复位（否则残留 true 会在 Note.update 前被主循环误判命中）；
		// earlyHitMult/lateHitMult 影响判定窗口；hitsoundDisabled 影响命中被听。
		tooLate = false;
		wasGoodHit = false;
		missed = false;
		ignoreNote = false;
		hitByOpponent = false;
		noteWasHit = false;
		blockHit = false;
		canBeHit = false;
		earlyHitMult = 1;
		lateHitMult = 1;
		hitsoundDisabled = false;
		// LE LTS 双侧：复位按侧配色（池化复用默认回退全局玩家档）
		noteColArray = null;
		// 复位裁剪框（被裁剪过的音符复用会残留 clipRect 导致绘制异常）
		clipRect = null;
		flipY = false;
		spawned = false;
		preloadIndex = -1;
		lowPriority = false;
		noAnimation = false;
		noMissAnimation = false;
		hitCausesMiss = false;
		hitsoundForce = false;
		ratingDisabled = false;
		rating = 'unknown';
		ratingMod = 0;
		eventName = '';
		eventLength = 0;
		eventVal1 = '';
		eventVal2 = '';
		tail = [];
		parent = null;
		nextNote = null;
		this.prevNote = (prevNote == null) ? this : prevNote;
		this.noteData = noteData;
		this.isSustainNote = isSustain;
		this.strumTime = strumTime + (inEditor ? 0 : ClientPrefs.data.noteOffset);
		this.noteColumnRaw = noteData;
		this.noteType = null;
		this.animSuffix = '';
		this.gfNote = false;
		this.sustainLength = 0;
		this.mustPress = false;
		this.distance = 2000;
		this.visible = true;
		this.active = true;
		this.exists = true;
		this.offsetAngle = 0;
		this.noteSplashHue = 0;
		this.noteSplashSat = 0;
		this.noteSplashBrt = 0;
		// 命中/失判配置回到默认值（noteType setter 会按需覆盖）
		hitHealth = 0.02;
		missHealth = 0.1;
		hitsound = 'hitsound';
		// 记录当前皮肤版本：construct 时的帧即当前皮肤，避免 ensureCurrentSkin 立即重载
		lastSkinVersion = noteSkinVersion;

		// —— 重跑与 new 一致的初始偏移逻辑（不重建帧）——
		x = (ClientPrefs.data.middleScroll ? PlayState.STRUM_X_MIDDLESCROLL : PlayState.STRUM_X) + 50;
		y = -2000;
		moves = false;
		copyX = copyY = copyAngle = copyAlpha = true;
		multSpeed = 1;

		if (noteData > -1 && rgbShader != null)
		{
			var rgbDisabled:Bool = (PlayState.SONG != null && PlayState.SONG.disableNoteRGB);
			rgbShader.enabled = !rgbDisabled;
			if (ClientPrefs.data.arrowColorMode != 'HSV' && rgbDisabled)
				shader = null;

			x += swagWidth * noteData;
			if (!isSustainNote)
				animation.play(colAt(noteData) + 'Scroll');
		}

		// 前驱连接（与 new 一致：写前驱 nextNote）
		if (this.prevNote != this)
			this.prevNote.nextNote = this;

		if (isSustainNote && this.prevNote != this)
		{
			// Kade 长条视觉开启时长条完全不透明；关闭时保持原默认半透明
			if(ClientPrefs.data.kadeHoldVisual)
			{
				alpha = 1.0;
				multAlpha = 1.0;
			}
			else
			{
				alpha = 0.6;
				multAlpha = 0.6;
			}
			hitsoundDisabled = true;
			if (ClientPrefs.data.downScroll) flipY = true;
			copyAngle = false;
			animation.play(colAt(noteData) + 'holdend');

			offsetX += width / 2;
			if (ClientPrefs.data.downScroll) offsetX -= width / 2; // 保持与 construct 偏移一致
			// 注：construct 中此处为 `offsetX += width/2` 后 `offsetX -= width/2`（净 0），
			// 但这里为了与 construct 视觉结果严格一致，仍保留该对称操作。
			offsetX -= width / 2;

			if (PlayState.isPixelStage)
				offsetX += 30;

			if (this.prevNote.isSustainNote)
			{
				this.prevNote.animation.play(this.prevNote.colAt(this.prevNote.noteData) + 'hold');
				this.prevNote.scale.y *= Conductor.stepCrochet / 100 * 1.05;
			if (PlayState.instance != null)
				this.prevNote.scale.y *= PlayState.instance.songSpeed;
				if (PlayState.isPixelStage)
				{
					this.prevNote.scale.y *= 1.19;
					this.prevNote.scale.y *= (6 / this.prevNote.height);
				}
				this.prevNote.updateHitbox();
			}

			if (PlayState.isPixelStage)
			{
				scale.y *= PlayState.daPixelZoom;
				updateHitbox();
			}
			earlyHitMult = 0;
		}
		else if (!isSustainNote)
		{
			// 复位基准 scale（construct 时 setGraphicSize(0.7)*strumScale 的结果），
			// 消除上一轮被前驱 sustain 修改 scale.y 的累积影响。
			scale.set(baseScaleX, baseScaleY);
			centerOffsets();
			centerOrigin();
		}

		x += offsetX;
	}

	/**
	 * 皮肤变更后刷新音符：重新从当前皮肤加载帧（atlas 已按皮肤缓存，不会
	 * 重复解析），并按当前 styleIndex 刷新配色。必须重加载帧，否则音符仍使用旧皮肤的
	 * atlas，而新颜色前缀（rombus/circle 等）在旧 atlas 中不存在，会导致长条/音符显示异常。
	 */
	public function updateManiaStyle():Void
	{
		if (noteData <= -1) return;
		var animName:String = (animation.curAnim != null) ? animation.curAnim.name : null;
		reloadNote(); // 从当前皮肤重新加载帧（保留当前动画名），atlas 已缓存故廉价
		// 配色随当前 styleIndex 刷新（reloadNote 不会更新 rgbShader 着色）
		var idx:Int = styleIndex(noteData);
		rgbShader = new RGBShaderReference(this, initializeGlobalRGBShader(idx));
		var rgbDisabled:Bool = (PlayState.SONG != null && PlayState.SONG.disableNoteRGB);
		if (rgbDisabled) rgbShader.enabled = false;
		if (ClientPrefs.data.arrowColorMode == 'HSV')
		{
			colorSwap = Note.initializeGlobalColorSwapShader(idx);
			shader = rgbDisabled ? null : colorSwap.shader;
		}
		if (animName != null) animation.play(animName, true);
	}

	/**
	 * 按需要在“当前皮肤版本”下重载音符帧：
	 * 仅当皮肤版本已变化（lastSkinVersion != noteSkinVersion）时才真正 reloadNote，
	 * 否则直接跳过。这样未出现的音符不会在切换瞬间被批量 reload（那是卡死的根源），
	 * 而是在它们真正 spawn 时各加载一次，开销被均摊到逐帧生成预算中。
	 */
	public function ensureCurrentSkin():Void
	{
		if (lastSkinVersion != noteSkinVersion)
		{
			updateManiaStyle();
			lastSkinVersion = noteSkinVersion;
		}
	}

	public static function getNoteSkinPostfix()
	{
		var skin:String = '';
		var skinName:String = ClientPrefs.data.noteSkin.trim();
		if(skinName != ClientPrefs.defaultData.noteSkin)
			skin = '-' + skinName.toLowerCase().replace(' ', '_');
		return skin;
	}

	/**
	 * 统一解析皮肤路径，沿用「模组优先于原版、HSV 目录优先于默认目录」的优先级：
	 *   1) 模组 hsv 目录  mods/(currentMod)/images/<folder>/hsv/<file>
	 *   2) 模组默认目录  mods/(currentMod)/images/<folder>/<file>
	 *   3) 原版 hsv 目录  images/<folder>/hsv/<file>
	 *   4) 原版默认目录  images/<folder>/<file>
	 * 非 HSV 模式直接返回 basePath，真正加载时 Paths.getSparrowAtlas 自身已优先模组再回退原版。
	 * 这样可保证 StrumNote / 流动音符 / 飞溅在游玩（含模组）时使用完全一致的一套资源，
	 * 且不会在模组只提供白底默认箭头时错误回退到原版的 hsv 箭头。
	**/
	public static function resolveSkinPath(basePath:String, ?isSplash:Bool = false):String
	{
		if (basePath == null || basePath.length < 1) basePath = defaultNoteSkin;

		// 飞溅贴图是共享资源（不分像素/非像素，像素感由 PixelSplashShader 运行时做出），
		// 其 hsv 白色变体始终位于 images/<folder>/hsv/，绝不在 pixelUI/ 下，故飞溅
		// 在像素舞台也不应套用 pixelUI/ 前缀。
		var pixelPrefixEnabled:Bool = !isSplash && PlayState.isPixelStage;

		// cache key 必须包含 arrowColorMode 与是否像素舞台：否则 RGB/HSV 或
		// 像素/非像素缓存的基底路径会相互命中，导致永远解析不到正确的 hsv/ 纹理。
		var cacheKey:String = (Mods.currentModDirectory != null ? Mods.currentModDirectory : '')
			+ ':' + ClientPrefs.data.arrowColorMode + ':'
			+ (pixelPrefixEnabled ? 'pixel:' : '') + basePath;
		if (_skinPathCache.exists(cacheKey)) return _skinPathCache.get(cacheKey);

		var result:String = basePath;
		if (ClientPrefs.data.arrowColorMode == 'HSV')
		{
			var parts:Array<String> = basePath.split('/');
			var filename:String = parts.pop();
			var folder:String = parts.join('/');
			// 像素舞台的箭头资源位于 pixelUI/ 目录下，故 hsv 白色变体也要在那里查找；
			// 非像素舞台（或飞溅）则维持原 images/<folder>/hsv/<file> 逻辑。返回的
			// path 不含 pixelUI/ 前缀，由 StrumNote/Note 的像素分支自行拼接 pixelUI/。
			var pixelPrefix:String = pixelPrefixEnabled ? 'pixelUI/' : '';
			var hsvRel:String = 'images/$pixelPrefix$folder/hsv/$filename.png';
			var baseRel:String = 'images/$pixelPrefix$basePath.png';

			if (skinFileExists(hsvRel, true))       result = '$folder/hsv/$filename'; // 1) 模组 hsv
			else if (skinFileExists(baseRel, true)) result = basePath;                // 2) 模组默认
			else if (skinFileExists(hsvRel, false)) result = '$folder/hsv/$filename'; // 3) 原版 hsv
		}
		_skinPathCache.set(cacheKey, result);
		return result;
	}

	// modsOnly=true：仅检测当前模组 + 全局模组；false：还会回退检测原版（忽略模组）
	static function skinFileExists(relPath:String, modsOnly:Bool):Bool
	{
		#if MODS_ALLOWED
		if (Mods.currentModDirectory != null && Mods.currentModDirectory.length > 0
			&& FileSystem.exists(Paths.mods(Mods.currentModDirectory + '/' + relPath))) return true;
		for (mod in Mods.getGlobalMods())
			if (FileSystem.exists(Paths.mods(mod + '/' + relPath))) return true;
		#end
		if (modsOnly) return false;
		return Paths.fileExists(relPath, IMAGE, true); // ignoreMods=true → 仅原版
	}

	public static function getNoteSkinPath(basePath:String):String
	{
		return resolveSkinPath(basePath);
	}

	function loadNoteAnims() {
		if (colAt(noteData) == null)
			return;

		var name:String = colAt(noteData);
		// 若皮肤缺少该颜色帧（如多键 rombus/circle 在非 ek 皮肤中不存在），回退到 green（上音符）帧；
		// 动画名仍用原 name，保证构造函数 / MetaNote 的 play 能命中（普通长条/上动画）。
		var framePrefix:String = hasNoteFrame(name) ? name : 'green';

		if (isSustainNote)
		{
			attemptToAddAnimationByPrefix('purpleholdend', 'pruple end hold', 24, true); // this fixes some retarded typo from the original note .FLA
			animation.addByPrefix(name + 'holdend', framePrefix + ' hold end', 24, true);
			animation.addByPrefix(name + 'hold', framePrefix + ' hold piece', 24, true);
		}
		else animation.addByPrefix(name + 'Scroll', framePrefix + '0');

		setGraphicSize(Std.int(width * 0.7));
		// LE LTS 双侧：滚动音符按侧缩放（构造时 mustPress 尚未赋值，用 PlayState.currentSideMustPress 判断生成侧；
		// 非双侧=全局 strumScale）；记录生成时 scale 供 change keycount 改键后按新 scale 重缩
		var genSide:Bool = (PlayState.instance != null) ? PlayState.instance.currentSideMustPress : true;
		var noteSideScale:Float = PlayState.getNoteSideScale(genSide);
		genStrumScale = noteSideScale;
		if (!PlayState.isPixelStage && noteSideScale != 1) scale.scale(noteSideScale);
		updateHitbox();
		// 记录基准 scale（供对象池 prepareForReuse 复位，消除 sustain 改前驱累积）
		baseScaleX = scale.x;
		baseScaleY = scale.y;
	}

	// 判断当前皮肤图集中是否存在名为 `name + '0000'` 的帧（用于缺失动画的回退判断）
	function hasNoteFrame(name:String):Bool
	{
		return frames != null && frames.getByName(name + '0000') != null;
	}

	function loadPixelNoteAnims() {
		if (colAt(noteData) == null)
			return;

		if(isSustainNote)
		{
			animation.add(colAt(noteData) + 'holdend', [noteData + 4], 24, true);
			animation.add(colAt(noteData) + 'hold', [noteData], 24, true);
		} else animation.add(colAt(noteData) + 'Scroll', [noteData + 4], 24, true);
	}

	function attemptToAddAnimationByPrefix(name:String, prefix:String, framerate:Float = 24, doLoop:Bool = true)
	{
		// 防护：与 flixel 的 addByPrefix 一致，frames 未加载（为 null）时直接跳过，
		// 否则 findByPrefix 会访问 null.frames 触发 Null Object Reference 崩溃。
		if (frames == null) return;

		var animFrames = [];
		@:privateAccess
		animation.findByPrefix(animFrames, prefix); // adds valid frames to animFrames
		if(animFrames.length < 1) return;

		animation.addByPrefix(name, prefix, framerate, doLoop);
	}

	override function update(elapsed:Float) 
	{
		super.update(elapsed);

		var earlyWindow:Float = Conductor.safeZoneOffset * earlyHitMult;
		var lateWindow:Float = Conductor.safeZoneOffset * lateHitMult;
		var timeUntilHit:Float = (strumTime - Conductor.songPosition);

		// playOpponent：自动命中逻辑绑定到真正的 CPU 控制侧，而非死板的 !mustPress
		if (mustPress == PlayState.playOpponent)
		{
			canBeHit = (timeUntilHit > -lateWindow && timeUntilHit < earlyWindow);

			if (!wasGoodHit && strumTime <= Conductor.songPosition)
			{
				if(!isSustainNote || (prevNote.wasGoodHit && !ignoreNote))
					wasGoodHit = true;
			}

			if (strumTime < Conductor.songPosition - lateWindow && !wasGoodHit)
				tooLate = true;
		}
		else
		{
			canBeHit = (timeUntilHit > -lateWindow && timeUntilHit < earlyWindow);

			if (strumTime < Conductor.songPosition - lateWindow && !wasGoodHit)
				tooLate = true;
		}

		// Kade 长条视觉：段只在这些情况隐藏——
		// 1) 本段已“被消费”（wasGoodHit 命中/按住）
		// 2) 本段“断连”（missed，松开或漏接）
		// 3) 所属长条已命中到前一段（prevNote.wasGoodHit，hold 正在吞噬途中），
		//    且本段进入提前吞噬窗口（strumTime 前 kadeHoldKillPre() 毫秒）——让玩家/对手位
		//    长条前端都贴住判定线逐段提前消失，未命中的整条长条绝不提前消失。
		if (ClientPrefs.data.kadeHoldVisual && isSustainNote)
		{
			if (wasGoodHit || missed)
				visible = false;
			else if (prevNote != null && prevNote.wasGoodHit
				&& timeUntilHit <= kadeHoldKillPre())
				visible = false;
		}

		if (!ClientPrefs.data.kadeHoldVisual && tooLate && !inEditor)
		{
			if (alpha > 0.3)
				alpha = 0.3;
		}
	}

	override public function destroy()
	{
		super.destroy();
		// 注意：此处不再清空 _lastValidChecked。该 static 缓存用于避免对相同皮肤重复
		// 做 Paths.fileExists（多次 FileSystem.exists 系统调用）。原本在每实例 destroy 时清空，
		// 会导致高密度纯箭头谱（每秒数十~数百次 spawn/destroy 交错）下命中率≈0，每次构造都
		// 真跑文件系统 stat（安卓上单次数十微秒）。改为仅在切歌 / PlayState.destroy /
		// 皮肤变更时统一清空一次，由 resetNoteSkinCache() 负责。
	}

	/**
	 * 清空皮肤探测缓存。仅在切歌、PlayState 销毁或皮肤变更时调用一次，
	 * 不应在单个 Note 销毁时调用（见 destroy() 注释）。
	 */
	public static function resetNoteSkinCache():Void {
		_lastValidChecked = '';
		_skinPathCache.clear();
	}

	public function followStrumNote(myStrum:StrumNote, fakeCrochet:Float, songSpeed:Float = 1)
	{
		var strumX:Float = myStrum.x;
		var strumY:Float = myStrum.y;
		var strumAngle:Float = myStrum.angle;
		var strumAlpha:Float = myStrum.alpha;
		var strumDirection:Float = myStrum.direction;

		distance = (0.45 * (Conductor.songPosition - strumTime) * songSpeed * multSpeed);
		if (!myStrum.downScroll) distance *= -1;

		// 使用 StrumNote 缓存的 cos/sin（默认 90° 时 dirCos=0, dirSin=1），避免每音符每帧各算一次
		// Math.cos/sin（HXCPP 上走 C 库调用，高密度谱下数千次/帧）。注意 angleDir 仅用于 copyAngle 的
		// 角度计算（仍需原始角度值），而 x/y 平移改用缓存的 cos/sin。
		var angleDir = strumDirection * Math.PI / 180;
		var cosDir:Float = myStrum.dirCos;
		var sinDir:Float = myStrum.dirSin;
		if (copyAngle)
			angle = strumDirection - 90 + strumAngle + offsetAngle;

		if(copyAlpha)
			alpha = strumAlpha * multAlpha;

		if(copyX)
			x = strumX + offsetX + cosDir * distance;

		if(copyY)
		{
			y = strumY + offsetY + correctionOffset + sinDir * distance;
			if(myStrum.downScroll && isSustainNote)
			{
				if(PlayState.isPixelStage)
				{
					y -= PlayState.daPixelZoom * 9.5;
				}
				y -= (frameHeight * scale.y) - (Note.swagWidth / 2);
			}
		}
	}

	public function clipToStrumNote(myStrum:StrumNote)
	{
		// Kade 长条视觉：开启时不裁剪，改为靠 update 里按段时间淡出到 0.3（保持整条恒显示）
		if (ClientPrefs.data.kadeHoldVisual)
			return;

		var center:Float = myStrum.y + offsetY + Note.swagWidth / 2 * PlayState.getNoteSideScale(mustPress);
		if((mustPress || !ignoreNote) && (wasGoodHit || (prevNote.wasGoodHit && !canBeHit)))
		{
			var swagRect:FlxRect = clipRect;
			if(swagRect == null) swagRect = new FlxRect(0, 0, frameWidth, frameHeight);

			if (myStrum.downScroll)
			{
				if(y - offset.y * scale.y + height >= center)
				{
					swagRect.width = frameWidth;
					swagRect.height = (center - y) / scale.y;
					swagRect.y = frameHeight - swagRect.height;
				}
			}
			else if (y + offset.y * scale.y <= center)
			{
				swagRect.y = (center - y) / scale.y;
				swagRect.width = width / scale.x;
				swagRect.height = (height / scale.y) - swagRect.y;
			}
			clipRect = swagRect;
		}
	}

	@:noCompletion
	override function set_clipRect(rect:FlxRect):FlxRect {
		clipRect = rect;

		if (frames != null)
			frame = frames.frames[animation.frameIndex];

		return rect;
	}
}
