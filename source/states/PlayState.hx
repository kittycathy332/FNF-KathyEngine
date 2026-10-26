package states;

import Main;
import sys.thread.Thread;
import backend.Highscore;
import backend.StageData;
import backend.WeekData;
import backend.Song;
import backend.HitSoundPool;
import backend.Language.ScoreLanguage;
import backend.Rating;
import backend.ExtraKeysHandler;
import backend.InputFormatter;

#if MODS_ALLOWED
import sys.FileSystem;
#end

import flixel.FlxBasic;
import flixel.graphics.FlxGraphic;
import flixel.FlxObject;
import flixel.FlxSubState;
import flixel.util.FlxSort;
	import flixel.util.FlxStringUtil;
	import flixel.util.FlxSave;
	import flixel.text.FlxText;
	import flixel.util.FlxTimer;
	import flixel.sound.FlxSound;
	import psychlua.ModchartSprite;
	import flixel.input.keyboard.FlxKey;
import flixel.animation.FlxAnimationController;
import lime.utils.Assets;
import openfl.utils.AssetType;
import openfl.utils.Assets as OpenFlAssets;
import flash.media.Sound;
import openfl.events.KeyboardEvent;
import openfl.events.Event;
import haxe.Json;
import flixel.system.scaleModes.PlayStateScaleMode;
import flixel.system.scaleModes.BaseScaleMode;

import cutscenes.DialogueBoxPsych;

import states.StoryMenuState;
import states.FreeplayState;
import states.editors.ChartingState;
import states.editors.CharacterEditorState;

import substates.PauseSubState;
import substates.GameOverSubstate;
import substates.ResultsScreen;

#if !flash
import openfl.filters.ShaderFilter;
#end

import shaders.ErrorHandledShader;

import objects.VideoSprite;
import objects.Note.EventNote;
import objects.Note.PreloadedChartNote;
import objects.StrumNote.KeybindShowcase;
import objects.StrumNote.StrumBoundaries;
import objects.*;
import states.stages.*;
import states.stages.objects.*;

#if LUA_ALLOWED
import psychlua.*;
#else
import psychlua.LuaUtils;
import psychlua.HScript;
#end

#if HSCRIPT_ALLOWED
import psychlua.HScript.HScriptInfos;
import crowplexus.iris.Iris;
import crowplexus.hscript.Expr.Error as IrisError;
import crowplexus.hscript.Printer;
#end
import lime.app.Application;
import backend.Native;

import funkin.vis.dsp.SpectralAnalyzer;
import funkin.vis.audioclip.frontends.LimeAudioClip;
import objects.Bar as Bar;

/**
 * This is where all the Gameplay stuff happens and is managed
 *
 * here's some useful tips if you are making a mod in source:
 *
 * If you want to add your stage to the game, copy states/stages/Template.hx,
 * and put your stage code there, then, on PlayState, search for
 * "switch (curStage)", and add your stage to that list.
 *
 * If you want to code Events, you can either code it on a Stage file or on PlayState, if you're doing the latter, search for:
 *
 * "function eventPushed" - Only called *one time* when the game loads, use it for precaching events that use the same assets, no matter the values
 * "function eventPushedUnique" - Called one time per event, use it for precaching events that uses different assets based on its values
 * "function eventEarlyTrigger" - Used for making your event start a few MILLISECONDS earlier
 * "function triggerEvent" - Called when the song hits your event's timestamp, this is probably what you were looking for
**/

// 回放数据类型定义
typedef ReplayData = {
	time:Float,				// 按下时间（相对于歌曲开始）
	key:Int,				// 按下的键（0-3）
	noteTime:Null<Float>,	// 音符时间（如果是打击音符），null表示空按
	late:Null<Float>,		// 延迟（ms），正数表示晚，负数表示早
	judge:String,			// 判定结果（sick/good/bad/shit/miss/ghost/release）
	releaseTime:Null<Float>	// 按键抬起的绝对时间，null表示未抬起
}

class PlayState extends MusicBeatState
{
	/**
	 * PlayState宽屏自适应模式开关：进入PlayState时临时启用宽屏分辨率（高度锁定720，宽度960~1680自适应），
	 * 退出PlayState后自动还原。设为 false 可关闭该功能。
	 * 注意：此开关是全局总开关，即使 ClientPrefs.data.playStateAdaptiveWidth 为 true，
	 * 此开关关闭也不会生效（用于调试或强制禁用）。
	 */
	public static var ENABLE_ADAPTIVE_WIDTH:Bool = true;
	private static var _psAdaptiveScaleMode:BaseScaleMode = null;
	private static var _psAdaptiveActive:Bool = false;

	//杂七杂八的新特性
	// 存命中时间戳（haxe.Timer.stamp() 秒级浮点），替代原 Array<Date> + Date.now()，
	// 消除每帧 Date 分配 + 系统调用 + O(n) remove。仅用于计算 NPS。
	var notesHitArray:Array<Float> = [];
	var nps:Int = 0;
	var maxNPS:Int = 0;
	var npsCheck:Int = 0;
	var allNotesMs:Float = 0;
	var averageMs:Float = 0;
	var msTimeTxt:FlxText;
	var msTimeTxtTween1:FlxTween;
	var msTimeTxtTween2:FlxTween;
	// 标记 msTimeTxt 当前是否处于 Kade 风格（20px/1px描边），用于切换回 Kathy 时恢复原样式
	var msTimeTxtKadeStyle:Bool = false;
	// Kade 风格下 ms 文本是否处于淡出中（按 120Hz 固定步进，不再逐帧）
	var msTimingShownActive:Bool = false;
	// 淡出步进的时间累加器（秒）
	var msTimeTxtFadeAccum:Float = 0;
	var scoreTxtTweenAngle:FlxTween;

	// 存储打击数据供 HitGraph 使用 [diff, judge, time]
	public var hitHistory:Array<Array<Dynamic>> = [];

	// 每帧复用的按键状态数组，避免重复分配
	var _holdBuffer:Array<Bool> = [];
	var _pressBuffer:Array<Bool> = [];
	var _releaseBuffer:Array<Bool> = [];
	var _heldBuffer:Array<Bool> = [];
	var _countedBuffer:Array<Bool> = [];
	// 回放系统
	public var replayData:Array<ReplayData> = [];	// 回放数据
	public var isReplaying:Bool = false;			// 是否正在回放
	public var currentReplayIndex:Int = 0;			// 当前回放索引
	var replayHeldKeys:Array<Bool> = [false, false, false, false];	// 回放时按下的键状态（用于长按）
	var keyPressIndices:Array<Int> = [-1, -1, -1, -1];	// 记录每个按键最后一次按下对应的replayData索引
	var replayNoteDelays:Array<Array<{strumTime:Float, late:Float}>> = [[], [], [], []];	// 存储每个键对应的音符延迟
	var currentNoteDelayOverride:Null<Float> = null;	// 当前音符的延迟覆盖值（replay模式使用）
	// 非音符按键支持（将按键code + NON_NOTE_KEY_OFFSET 存入 replayData.key）
	public static inline var NON_NOTE_KEY_OFFSET:Int = 1000;
	var nonNoteKeyPressIndices:Map<Int, Int> = new Map<Int, Int>();
	var replayHeldNonNoteKeys:Map<Int, Bool> = new Map<Int, Bool>();
	
	// 静态变量用于传递回放数据
	public static var pendingReplayData:Array<ReplayData> = null;	// 待加载的回放数据
	public static var shouldStartReplay:Bool = false;			// 是否应该启动回放
	public static var retainReplayOnRestart:Bool = false;		// 重玩仍需保留回放（下次重建 PlayState 继续回放）
	public static var replayJudgmentSettings:Dynamic = null;	// 回放中的判定设置
	public static var replayGameplaySettings:Dynamic = null;	// 回放中的游戏设置
	
	// 存储原始设置以便恢复
	var originalJudgmentSettings:Dynamic = null;
	var originalGameplaySettings:Dynamic = null;
	
	var dancingLeft:Bool = false;
	var icondancingLeft:Bool = false;
	public var iconBopEnabled:Bool = true;
	var ratingexspr:String = '';
	var exratingexspr:String = '-extra';
	var numexspr:String = '';
	var ratingAlpha:Float = ClientPrefs.data.ratingsAlpha;
	var iconP1InitialY:Float;
	var iconP2InitialY:Float;
	var botCheck:Bool = false; // 默认血条范围是0-2
	var totalEvents:Int = 0; // 添加在类变量区
	var eventAlerts:Array<FlxText> = [];
	var debugTexts:FlxTypedGroup<FlxText>;
	var chartingInfo:FlxText;
	var fpsVarInitialX:Float = 10;
	
	//专为仿LE设计的时间条多颜色（大概吧）
	var timeBarLeftColor:FlxColor = FlxColor.BLACK;
	var timeBarRightColor:FlxColor = FlxColor.WHITE;
	var timeBarLeftColorTarget:FlxColor = FlxColor.BLACK;
	var timeBarRightColorTarget:FlxColor = FlxColor.WHITE;

	public var eventDebugGroup:FlxTypedGroup<FlxText>; // 存储事件文本的组

	// 事件处理器
	public var eventHandler:EventHandler;

	//可以被lua调用的杂项
    public var targetZoom:Float = ClientPrefs.data.hudSize;

	//MRE特有的小图标角度变化
	var iconP1TargetAngle:Float = 0;
	var iconP2TargetAngle:Float = 0;
	var iconP1AngleLerpSpeed:Float = 0.11;
	var iconP2AngleLerpSpeed:Float = 0.11;



	// 丝滑血条
	var displayedHealth:Float = 1; // 用于显示的血量
	var healthLerp:Float = 1; // 用于平滑过渡的血量
	var maxHealth:Float = 2; // 默认血条最大值
	//var iconsAnimations:Bool = true; // 控制图标动画的开关
	var cpuHits:Int = 0;

	public static var STRUM_X = 42;
	public static var STRUM_X_MIDDLESCROLL = -278;

	public static var ratingStuff:Array<Dynamic> = [
		['You Suck!', 0.2], //From 0% to 19%
		['Shit', 0.4], //From 20% to 39%
		['Bad', 0.5], //From 40% to 49%
		['Bruh', 0.6], //From 50% to 59%
		['Meh', 0.69], //From 60% to 68%
		['Nice', 0.7], //69%
		['Good', 0.8], //From 70% to 79%
		['Great', 0.9], //From 80% to 89%
		['Sick!', 1], //From 90% to 99%
		['Perfect!!', 1] //The value on this one isn't used actually, since Perfect is always "1"
	];
	public var ratingStuffKE:Array<Dynamic> = 
    [
		["D", 0.6], // accuracy < 60
		["C", 0.7], // accuracy >= 60
		["B", 0.80], // accuracy >= 70
		["A", 0.85], // accuracy >= 80
		["A.", 0.9], // accuracy >= 85
		["A:", 0.93], // accuracy >= 90
		["AA", 0.965], // accuracy >= 93
		["AA.", 0.99], // accuracy >= 96.50
		["AA:", 0.997], // accuracy >= 99
		["AAA", 0.998], // accuracy >= 99.70
		["AAA.", 0.999], // accuracy >= 99.80
		["AAA:", 0.99955], // accuracy >= 99.90
		["AAAA", 0.99970], // accuracy >= 99.955
		["AAAA.", 0.99980], // accuracy >= 99.970
		["AAAA:", 0.999935], // accuracy >= 99.980
		["AAAAA", 1], // accuracy >= 99.9935
		["AAAAA", 1], // accuracy >= 99.9935    
		];

	//event variables
	public var isCameraOnForcedPos:Bool = false;

	public var boyfriendMap:Map<String, Character> = new Map<String, Character>();
	public var dadMap:Map<String, Character> = new Map<String, Character>();
	public var gfMap:Map<String, Character> = new Map<String, Character>();

	#if HSCRIPT_ALLOWED
	public var hscriptArray:Array<HScript> = [];
	#end

	public var BF_X:Float = 770;
	public var BF_Y:Float = 100;
	public var DAD_X:Float = 100;
	public var DAD_Y:Float = 100;
	public var GF_X:Float = 400;
	public var GF_Y:Float = 130;

	public var songSpeedTween:FlxTween;
	public var songSpeed(default, set):Float = 1;
	public var songSpeedType:String = "multiplicative";
	public var noteKillOffset:Float = 350;

	// 低延迟 / 已错过音符剔除相关（已移除 lowLatency 聚合开关，各行为直接由对应设置决定）
	// 有效自动重同步：用户开启 autoResync 时为真
	private inline function effectiveAutoResync():Bool return ClientPrefs.data.autoResync;
	// 有效已错过音符剔除：用户开启 hideMissedNotes 时为真
	private inline function effectiveHideMissed():Bool return ClientPrefs.data.hideMissedNotes;
	// 有效过期即时结算：用户开启 instantResolveExpired 时为真
	private inline function effectiveInstantResolve():Bool return ClientPrefs.data.instantResolveExpired;
	// 有效关闭逐音符脚本：用户开启 disableNoteLua 时为真
	private inline function effectiveDisableNoteLua():Bool return ClientPrefs.data.disableNoteLua;
	// 本帧已新建的音符精灵计数（用于 maxNotesPerFrame 每帧生成预算），每帧生成前清零
	private var notesSpawnedThisFrame:Int = 0;

	public var playbackRate(default, set):Float = 1;

	public var eventsPushed(get, never):Array<String>;
	private function get_eventsPushed():Array<String> { return eventHandler != null ? eventHandler.eventsPushed : []; }

	public var boyfriendGroup:FlxSpriteGroup;
	public var dadGroup:FlxSpriteGroup;
	public var gfGroup:FlxSpriteGroup;
	public static var curStage:String = '';
	public static var stageUI(default, set):String = "normal";
	public static var uiPrefix:String = "";
	public static var uiPostfix:String = "";
	public static var isPixelStage(get, never):Bool;

	@:noCompletion
	static function set_stageUI(value:String):String
	{
		uiPrefix = uiPostfix = "";
		if (value != "normal")
		{
			uiPrefix = value.split("-pixel")[0].trim();
			if (value == "pixel" || value.endsWith("-pixel")) uiPostfix = "-pixel";
		}
		return stageUI = value;
	}

	@:noCompletion
	static function get_isPixelStage():Bool
		return stageUI == "pixel" || stageUI.endsWith("-pixel");

	public static var SONG:SwagSong = null;
	public static var isStoryMode:Bool = false;
	// 是否由命令行直启进入（用于禁用调试/退出主界面/选项，并改变结算界面行为）
	public static var isCommandLineMode:Bool = false;
	public static var storyWeek:Int = 0;
	public static var storyPlaylist:Array<String> = [];
	public static var storyDifficulty:Int = 1;

	public var spawnTime:Float = 2000;

	public var inst:FlxSound;
	public var vocals:FlxSound;
	public var opponentVocals:FlxSound;

	public var dad:Character = null;
	public var gf:Character = null;
	public var boyfriend:Character = null;

	public var notes:FlxTypedGroup<Note>; // 主组，包含所有音符（用于 modchart 兼容性）
	public var normalNotes:FlxTypedGroup<Note>; // 普通音符组
	public var holdNotes:FlxTypedGroup<Note>; // Hold notes 组
	public var unspawnNotes:Array<Note> = [];
	public var eventNotes:Array<EventNote> = [];
	// 优化音符加载模式变量
	public var unspawnNotesPreloaded:Array<PreloadedChartNote> = []; // 预加载音符数据
	public var spawnedNotes:Array<Note> = []; // 跟踪已生成的音符，按预加载索引
	public var notesAddedCount:Int = 0;

	// 对象池：按 "noteData:sustain" 分桶复用 Note 实例，消除高密度谱每秒数十~数百次
	// new/destroy 带来的 GC 停顿。仅在 noteOptimization 且脚本未激活时启用（脚本激活时
	// 由 effectiveDisableNoteLua() 控制退化为原始 new/destroy，保证回调语义不变）。
	private var notePool:Map<String, Array<Note>> = new Map<String, Array<Note>>();
	// 传统加载模式的音符生成序号。优化模式用 notesAddedCount，传统模式没有预解析数组可对齐，
	// 故用此自增序号作为 Lua/HScript 回调 index 参数的稳定标识（仅标识用，不代表 notes 数组位置，
	// 不随 notes.remove() 漂移，避免原 notes.members.indexOf() 的 O(n) 扫描）。
	private var noteSpawnSeq:Int = 0;
	// 打击音 FlxSound 对象池：复用实例播放 hitsound/missnote，避免高密度谱每击分配与 GC 卡顿
	var hitSoundPool:HitSoundPool;
	private var useOptimizedLoading:Bool = false; // 本次歌曲实际采用的加载方式

	// 分帧延迟初始化：将非关键操作分散到后续帧，避免 create() 中主线程长时间阻塞
	private var _deferredInitStep:Int = -1; // -1=未开始, 0+=进行中

	public var camFollow:FlxObject;
	private static var prevCamFollow:FlxObject;

	public var strumLineNotes:FlxTypedGroup<StrumNote> = new FlxTypedGroup<StrumNote>();
	public var opponentStrums:FlxTypedGroup<StrumNote> = new FlxTypedGroup<StrumNote>();
	public var playerStrums:FlxTypedGroup<StrumNote> = new FlxTypedGroup<StrumNote>();
	public var grpNoteSplashes:FlxTypedGroup<NoteSplash> = new FlxTypedGroup<NoteSplash>();
	public var grpHoldCovers:FlxTypedGroup<NoteHoldCover> = new FlxTypedGroup<NoteHoldCover>();
	public var playerHoldCovers:Array<NoteHoldCover> = [];
	public var opponentHoldCovers:Array<NoteHoldCover> = [];
	public var laneCovers:FlxTypedGroup<FlxSprite> = new FlxTypedGroup<FlxSprite>();
	private var opponentLaneCover:FlxSprite = null;
	private var playerLaneCover:FlxSprite = null;

	public var camZooming:Bool = false;
	public var camZoomingMult:Float = 1;
	public var camZoomingDecay:Float = 1;
	private var curSong:String = "";

	public var gfSpeed:Int = 1;
	public var health(default, set):Float = 1;
	public var combo:Int = 0;
	public var maxCombo:Int = 0; // 本局最大连击，用于回放 meta 展示
	public var comboJustBroke:Bool = false; // 断连(失手)后首次命中标记，供 OG Funkin 显示模式强制显示 000

	public var healthBar:Bar;
	public var timeBar:Bar;
	var songPercent:Float = 0;

	public var ratingsData:Array<Rating> = Rating.loadDefault();

	private var generatedMusic:Bool = false;
	public var endingSong:Bool = false;
	public var startingSong:Bool = false;
	private var updateTime:Bool = true;
	public static var changedDifficulty:Bool = false;
	public static var chartingMode:Bool = false;

	//Gameplay settings
	public var healthGain:Float = 1;
	public var healthLoss:Float = 1;

	public var guitarHeroSustains:Bool = false;
	public var sustainTailFixMode:String = 'off'; // 长按音符尾条判定优化方案: 'off'/'extend'/'earlyHit'/'both'
	public var holdReleaseInstantMiss:Bool = false; // 特性1: guitarHeroSustains下松手立刻miss
	public var holdTailJudge:Bool = false; // 特性2: 长条尾部算有效命中(加combo+评级,不加分)
	public var holdScoreBonus:Bool = false; // 特性3: 长条命中期间持续加分
	public var holdTailLeniency:Bool = false; // 特性2宽容: 是否放宽尾条判定窗口
	public var holdTailLeniencyMs:Float = 20.0; // 特性2宽容量(ms)
	var holdScoreRemainder:Float = 0; // 特性3: 分数小数累加器(songScore为Int,避免每帧取整丢失)
	public static inline var HOLD_SCORE_BONUS_PER_SECOND:Float = 250.0; // 特性3: 每秒加分(参考原版Funkin Constants.SCORE_HOLD_BONUS_PER_SECOND)
	public var instakillOnMiss:Bool = false;
	public var foreverMissPunish:Float = 0.0; // Forever 血量模型：连续 miss 递增惩罚累计器
	public var cpuControlled:Bool = false;
	public var practiceMode:Bool = false;
	public var pressMissDamage:Float = 0.05;

	// Ghost Tap 冷却（375ms，仅 whenSinging 模式启用，原版 Funkin 防连按）
	public static final GHOST_TAP_DELAY_MS:Float = 375.0; // 原版 Funkin: 3/8 秒
	public var ghostTapTimer:Array<Float> = [0, 0, 0, 0];

	public var botplaySine:Float = 0;
	public var botplayTxt:FlxText;
	public var replayTxt:FlxText;
	public var watermarkTxt:FlxText;
	public var ratingCounter:FlxText;
	public var ratingCounterModule:objects.RatingCounter;

	public var iconP1:HealthIcon;
	public var iconP2:HealthIcon;
	public var camHUD:FlxCamera;
	public var camGame:FlxCamera;
	public var camOther:FlxCamera;
	public var camArchived:FlxCamera;
	private var mobilePauseBtn:TouchButton;
	public var luaTpadCam:FlxCamera;
	public var cameraSpeed:Float = 1;

	public var songScore:Int = 0;
	public var songHits:Int = 0;
	public var songMisses:Int = 0;
	public var songSickPlus:Int = 0; // Sick+模式下命中perfect窗口的次数（纯统计用，不影响FC/准度）
	public var scoreTxt:FlxText;
	var timeTxt:FlxText;
	var scoreTxtTween:FlxTween;

	public static var campaignScore:Int = 0;
	public static var campaignMisses:Int = 0;
	public static var seenCutscene:Bool = false;
	public static var deathCounter:Int = 0;

	public var defaultCamZoom:Float = 1.05;

	// how big to stretch the pixel art assets
	public static var daPixelZoom:Float = 6;
	private var singAnimations:Array<String> = ['singLEFT', 'singDOWN', 'singUP', 'singRIGHT'];

	// 当前键数配置与每键缩放；原生 4 键下 curMania==3、strumScale==1（保持原布局）。
	public static var strumScale:Float = 1;
	public var curMania:Int = 3;
	private var startArrowSkin:String = null;
	private var startSplashSkin:String = null;

	// —— LE LTS 双侧轨道数（跟随 EK 配置化结构：每侧一个 EK 档位） ——
	// 玩家侧沿用 curMania/totalColumns/colArray/singAnimations/keysArray（applyMania 填充）；
	// 对手侧由下列镜像字段承载（applyOpponentMania 填充，与 applyMania 同构）。
	// isLeDualChart=true 时（谱面含 playerKeyCount 且 != keyCount）两侧轨道数独立，
	// 解析按 LE 规则（mustHit 段连续编号）、事件 "change keycount" 可实时切换；false 时对手侧恒等于玩家侧。
	public var isLeDualChart:Bool = false;
	public var oppMania:Int = 3;
	public var opponentColumns:Int = 4;
	public var opponentColArray:Array<String> = ['purple', 'blue', 'green', 'red'];
	public var opponentSingAnimations:Array<String> = ['singLEFT', 'singDOWN', 'singUP', 'singRIGHT'];

	// LE LTS 双侧：两侧 strum/滚动音符的独立缩放（computeMultiKeyStrumScale 按各自键数与中心计算）。
	// 非双侧两侧同值（= 原 strumScale 逻辑）；strumScale 主值保持玩家侧，兼容既有引用。
	public var playerStrumScale:Float = 1;
	public var opponentStrumScale:Float = 1;
	// 当前正在生成的音符属于哪一侧（供 Note 构造时缩放：构造阶段 mustPress 尚未赋值，
	// 由 generateSongLeDual 在 new Note() 前写入；非双侧/其他路径恒 true=主值，无影响）。
	public var currentSideMustPress:Bool = true;

	public var inCutscene:Bool = false;
	public var skipCountdown:Bool = false;
	var songLength:Float = 0;

	// 旧版 PE (0.6.3/0.7.3) 兼容字段：模组脚本 runHaxeCode 会直接访问 game.modchartTweens.set/remove
	// 1.0.4 官方已移除该字段，这里补回以保证旧脚本可运行（KathyEngine 自身 tween 走 variables，不使用此 map）
	public var modchartTweens:Map<String, FlxTween> = new Map<String, FlxTween>();
	// 旧版 PE (0.6.3/0.7.3) 兼容：1.0.4 官方移除了这些 modchart* 公开字段，
	// 补回以避免老脚本 runHaxeCode 直接反射 game.modchartXxx 时报 Invalid access to field。
	// 这些字段始终存在（编译期无法按 luaCompatVersion 动态开关），KathyEngine 自身不使用它们。
	public var modchartSprites:Map<String, ModchartSprite> = new Map<String, ModchartSprite>();
	public var modchartTexts:Map<String, FlxText> = new Map<String, FlxText>();
	public var modchartTimers:Map<String, FlxTimer> = new Map<String, FlxTimer>();
	public var modchartSounds:Map<String, FlxSound> = new Map<String, FlxSound>();
	public var modchartSaves:Map<String, FlxSave> = new Map<String, FlxSave>();

	public var boyfriendCameraOffset:Array<Float> = null;
	public var opponentCameraOffset:Array<Float> = null;
	public var girlfriendCameraOffset:Array<Float> = null;

	#if DISCORD_ALLOWED
	// Discord RPC variables
	var storyDifficultyText:String = "";
	var detailsText:String = "";
	var detailsPausedText:String = "";
	#end

	//Achievement shit
	var keysPressed:Array<Int> = [];
	var boyfriendIdleTime:Float = 0.0;
	var boyfriendIdled:Bool = false;

	// Lua shit
	public static var instance:PlayState;
	#if LUA_ALLOWED public var luaArray:Array<FunkinLua> = []; #end
	// Leather Engine 脚本层（对照 LE 原版 modding/scripts/languages/LuaScript.hx）
	// 仅当当前谱面 format=LEATHER/LEATHER LTS 且 ClientPrefs.leatherScriptCompat != off 时使用
	#if LUA_ALLOWED public var leatherLuaArray:Array<psychlua.leather.LeatherLuaScript> = []; #end

	#if (LUA_ALLOWED || HSCRIPT_ALLOWED)
	private var luaDebugGroup:FlxTypedGroup<psychlua.DebugLuaText>;
	#end
	public var introSoundsSuffix:String = '';

	// Less laggy controls
	public var keysArray:Array<String>;
	public var keyViewer:objects.KeyViewer; // 游戏内按键显示覆盖层
	public var songName:String;

	// Callbacks for stages
	public var startCallback:Void->Void = null;
	public var endCallback:Void->Void = null;

	private var shutdownThread:Bool = false;
	private var gameFroze:Bool = false;
	private var requiresSyncing:Bool = false;
	private var lastCorrectSongPos:Float = -1.0;

	public static var _lastLoadedModDirectory:String = '';
	// 歌曲音频所在模组的探测结果缓存（song -> audioModDir，''=内置）。
	// generateSong 每次进歌都要遍历全部 84 个模组探测音频是否存在，跨曲切换时是固定开销，会话内缓存可消除。
	public static var _songAudioModCache:Map<String, String> = null;
	public static var nextReloadAll:Bool = false;

	public var luaTouchPad:TouchPad;

	// 添加一个变量用于平滑血条
	private var smoothHealth:Float = 1;

	// 血条平滑/溢出回落系数（PlayState 公有变量，脚本与游玩中可直接修改本实例）
	public var smoothHPSpeed:Float = 10; // 正常血条追平速度，越大越跟手（可在设置里配默认值）
	public var healthOverflowDrain:Float = 20; // 超满血回落速度，越大回落越快（可在设置里配默认值）

	public var audioAnalyzer:SpectralAnalyzer;
	public var opponentAudioAnalyzer:SpectralAnalyzer;
	public var playerAudioAnalyzer:SpectralAnalyzer;

	public function initAnalyzer(barCount:Int, maxDelta:Float = 0.01, peakHold:Int = 30) {
		@:privateAccess
		if (FlxG.sound.music == null || FlxG.sound.music._channel == null || FlxG.sound.music._channel.__audioSource == null) return;

		@:privateAccess
		audioAnalyzer = new SpectralAnalyzer(FlxG.sound.music._channel.__audioSource, barCount, maxDelta, peakHold);

		#if desktop
		audioAnalyzer.fftN = 256;
		#end
	}

	public function getAudioLevels() {
		var levels = audioAnalyzer.getLevels();
		return [for (i in levels) i.value];
	}

	public function initOpponentAnalyzer(barCount:Int, maxDelta:Float = 0.01, peakHold:Int = 30) {
		@:privateAccess
		if (opponentVocals == null || opponentVocals._channel == null || opponentVocals._channel.__audioSource == null) return;

		@:privateAccess
		opponentAudioAnalyzer = new SpectralAnalyzer(opponentVocals._channel.__audioSource, barCount, maxDelta, peakHold);

		#if desktop
		opponentAudioAnalyzer.fftN = 256;
		#end
	}

	public function getOpponentAudioLevels() {
		if (opponentAudioAnalyzer == null) return null;
		var levels = opponentAudioAnalyzer.getLevels();
		return [for (i in levels) i.value];
	}

	public function initPlayerAnalyzer(barCount:Int, maxDelta:Float = 0.01, peakHold:Int = 30) {
		@:privateAccess
		if (vocals == null || vocals._channel == null || vocals._channel.__audioSource == null) return;

		@:privateAccess
		playerAudioAnalyzer = new SpectralAnalyzer(vocals._channel.__audioSource, barCount, maxDelta, peakHold);

		#if desktop
		playerAudioAnalyzer.fftN = 256;
		#end
	}

	public function getPlayerAudioLevels() {
		if (playerAudioAnalyzer == null) return null;
		var levels = playerAudioAnalyzer.getLevels();
		return [for (i in levels) i.value];
	}

	override public function create()
	{
		var __t0:Float = Sys.time();
		// 从设置读取血条平滑/溢出回落系数的默认值（游玩中脚本仍可直接覆盖本实例变量）
		smoothHPSpeed = ClientPrefs.data.smoothHPSpeed;
		healthOverflowDrain = ClientPrefs.data.healthOverflowDrain;

		//trace('Playback Rate: ' + playbackRate);
		_lastLoadedModDirectory = Mods.currentModDirectory;

		// 只有当不缓存资源或F5刷新时才清空资源
		if(!ClientPrefs.data.cacheResourcesOnReload || nextReloadAll)
		{
			Paths.clearStoredMemory();
			if(nextReloadAll)
			{
				Paths.clearUnusedMemory();
				LanguageBasic.reloadPhrases();
			}
		}
		nextReloadAll = false;

		// 检查是否有待加载的回放数据
		if(shouldStartReplay && pendingReplayData != null)
		{
			isReplaying = true;
			// 清空上一局残留的虚拟按键状态（旧回放数据 5/6 键 releaseTime 缺失时按下状态会残留跨局）
			Controls.instance.clearVirtualPressedStates();
			replayData = pendingReplayData;
			currentReplayIndex = 0;
			shouldStartReplay = false;
			pendingReplayData = null;
			retainReplayOnRestart = false;
			// 重置按键状态
			replayHeldKeys = [false, false, false, false];
			keyPressIndices = [-1, -1, -1, -1];
			// 初始化延迟存储数组
			replayNoteDelays = [[], [], [], []];
			// 初始化非音符回放状态
			replayHeldNonNoteKeys = new Map<Int, Bool>();
			nonNoteKeyPressIndices = new Map<Int, Int>();
			// 预填充延迟数据，以便在 popUpScore 中快速查找
			for(action in replayData)
			{
				if(action.noteTime != null && action.late != null && action.key >= 0 && action.key < 4)
				{
					// 存储延迟值 {strumTime:Float, late:Float}
					replayNoteDelays[action.key].push({strumTime: action.noteTime, late: action.late});
				}
			}
			
			// 应用回放中的判定设置
			if (replayJudgmentSettings != null) {
				// 保存原始判定设置
				originalJudgmentSettings = {
					rmPerfect: ClientPrefs.data.rmPerfect,
					perfectWindow: ClientPrefs.data.perfectWindow,
					sickWindow: ClientPrefs.data.sickWindow,
					goodWindow: ClientPrefs.data.goodWindow,
					badWindow: ClientPrefs.data.badWindow,
					safeFrames: ClientPrefs.data.safeFrames,
					ratingOffset: ClientPrefs.data.ratingOffset,
					hitsoundVolume: ClientPrefs.data.hitsoundVolume,
					noteOffset: ClientPrefs.data.noteOffset,
				};
				
				// 覆盖 ClientPrefs.data 中的判定相关字段
				if (Reflect.hasField(replayJudgmentSettings, 'rmPerfect')) ClientPrefs.data.rmPerfect = replayJudgmentSettings.rmPerfect;
				if (Reflect.hasField(replayJudgmentSettings, 'perfectWindow')) ClientPrefs.data.perfectWindow = replayJudgmentSettings.perfectWindow;
				if (Reflect.hasField(replayJudgmentSettings, 'sickWindow')) ClientPrefs.data.sickWindow = replayJudgmentSettings.sickWindow;
				if (Reflect.hasField(replayJudgmentSettings, 'goodWindow')) ClientPrefs.data.goodWindow = replayJudgmentSettings.goodWindow;
				if (Reflect.hasField(replayJudgmentSettings, 'badWindow')) ClientPrefs.data.badWindow = replayJudgmentSettings.badWindow;
				if (Reflect.hasField(replayJudgmentSettings, 'safeFrames')) ClientPrefs.data.safeFrames = replayJudgmentSettings.safeFrames;
				if (Reflect.hasField(replayJudgmentSettings, 'ratingOffset')) ClientPrefs.data.ratingOffset = replayJudgmentSettings.ratingOffset;
				if (Reflect.hasField(replayJudgmentSettings, 'hitsoundVolume')) ClientPrefs.data.hitsoundVolume = replayJudgmentSettings.hitsoundVolume;
				if (Reflect.hasField(replayJudgmentSettings, 'noteOffset')) ClientPrefs.data.noteOffset = replayJudgmentSettings.noteOffset;
				
				// 重新初始化 ratingsData 以确保与当前 rmPerfect 设置一致
				ratingsData = Rating.loadDefault();
				
				// 更新 ratingsData 中的 hitWindow
				for (rating in ratingsData) {
					var windowField:String = rating.name + 'Window';
					if (Reflect.hasField(replayJudgmentSettings, windowField)) {
						rating.hitWindow = Reflect.field(replayJudgmentSettings, windowField);
					}
				}
			}
		
		// 应用回放中的游戏设置
		if (replayGameplaySettings != null) {
			// 保存原始游戏设置
			originalGameplaySettings = {
				downScroll: ClientPrefs.data.downScroll,
				middleScroll: ClientPrefs.data.middleScroll,
				opponentStrums: ClientPrefs.data.opponentStrums,
				ghostTappingMode: ClientPrefs.data.ghostTappingMode,
				noReset: ClientPrefs.data.noReset,
				guitarHeroSustains: ClientPrefs.data.guitarHeroSustains,
				sustainTailFix: ClientPrefs.data.sustainTailFix,
				holdReleaseInstantMiss: ClientPrefs.data.holdReleaseInstantMiss,
				holdTailJudge: ClientPrefs.data.holdTailJudge,
				holdScoreBonus: ClientPrefs.data.holdScoreBonus,
				holdTailLeniency: ClientPrefs.data.holdTailLeniency,
				holdTailLeniencyMs: ClientPrefs.data.holdTailLeniencyMs,
				popUpRating: ClientPrefs.data.popUpRating
			};
			
			// 应用 basic gameplay preferences
			if (Reflect.hasField(replayGameplaySettings, 'downScroll')) ClientPrefs.data.downScroll = replayGameplaySettings.downScroll;
			if (Reflect.hasField(replayGameplaySettings, 'middleScroll')) ClientPrefs.data.middleScroll = replayGameplaySettings.middleScroll;
			if (Reflect.hasField(replayGameplaySettings, 'opponentStrums')) ClientPrefs.data.opponentStrums = replayGameplaySettings.opponentStrums;
			if (Reflect.hasField(replayGameplaySettings, 'ghostTappingMode')) ClientPrefs.data.ghostTappingMode = replayGameplaySettings.ghostTappingMode;
			if (Reflect.hasField(replayGameplaySettings, 'noReset')) ClientPrefs.data.noReset = replayGameplaySettings.noReset;
			if (Reflect.hasField(replayGameplaySettings, 'guitarHeroSustains')) ClientPrefs.data.guitarHeroSustains = replayGameplaySettings.guitarHeroSustains;
			if (Reflect.hasField(replayGameplaySettings, 'sustainTailFix')) ClientPrefs.data.sustainTailFix = replayGameplaySettings.sustainTailFix;
			if (Reflect.hasField(replayGameplaySettings, 'holdReleaseInstantMiss')) ClientPrefs.data.holdReleaseInstantMiss = replayGameplaySettings.holdReleaseInstantMiss;
			if (Reflect.hasField(replayGameplaySettings, 'holdTailJudge')) ClientPrefs.data.holdTailJudge = replayGameplaySettings.holdTailJudge;
			if (Reflect.hasField(replayGameplaySettings, 'holdScoreBonus')) ClientPrefs.data.holdScoreBonus = replayGameplaySettings.holdScoreBonus;
			if (Reflect.hasField(replayGameplaySettings, 'holdTailLeniency')) ClientPrefs.data.holdTailLeniency = replayGameplaySettings.holdTailLeniency;
			if (Reflect.hasField(replayGameplaySettings, 'holdTailLeniencyMs')) ClientPrefs.data.holdTailLeniencyMs = replayGameplaySettings.holdTailLeniencyMs;
			if (Reflect.hasField(replayGameplaySettings, 'popUpRating')) ClientPrefs.data.popUpRating = replayGameplaySettings.popUpRating;
			
			// 应用 GameplayChangersSubstate 设置
			if (Reflect.hasField(replayGameplaySettings, 'scrolltype')) ClientPrefs.data.gameplaySettings.set('scrolltype', replayGameplaySettings.scrolltype);
			if (Reflect.hasField(replayGameplaySettings, 'scrollspeed')) ClientPrefs.data.gameplaySettings.set('scrollspeed', replayGameplaySettings.scrollspeed);
			if (Reflect.hasField(replayGameplaySettings, 'songspeed')) ClientPrefs.data.gameplaySettings.set('songspeed', replayGameplaySettings.songspeed);
			if (Reflect.hasField(replayGameplaySettings, 'healthgain')) ClientPrefs.data.gameplaySettings.set('healthgain', replayGameplaySettings.healthgain);
			if (Reflect.hasField(replayGameplaySettings, 'healthloss')) ClientPrefs.data.gameplaySettings.set('healthloss', replayGameplaySettings.healthloss);
			if (Reflect.hasField(replayGameplaySettings, 'instakill')) ClientPrefs.data.gameplaySettings.set('instakill', replayGameplaySettings.instakill);
			if (Reflect.hasField(replayGameplaySettings, 'practice')) ClientPrefs.data.gameplaySettings.set('practice', replayGameplaySettings.practice);
			if (Reflect.hasField(replayGameplaySettings, 'botplay')) ClientPrefs.data.gameplaySettings.set('botplay', replayGameplaySettings.botplay);
			if (Reflect.hasField(replayGameplaySettings, 'playOpponent')) ClientPrefs.data.gameplaySettings.set('playOpponent', replayGameplaySettings.playOpponent);
			if (Reflect.hasField(replayGameplaySettings, 'healthmodel')) ClientPrefs.data.gameplaySettings.set('healthmodel', replayGameplaySettings.healthmodel);
			if (Reflect.hasField(replayGameplaySettings, 'antiMash')) ClientPrefs.data.gameplaySettings.set('antiMash', replayGameplaySettings.antiMash);
			if (Reflect.hasField(replayGameplaySettings, 'breakComboOnBad')) ClientPrefs.data.breakComboOnBad = replayGameplaySettings.breakComboOnBad;
			if (Reflect.hasField(replayGameplaySettings, 'breakComboOnShit')) ClientPrefs.data.breakComboOnShit = replayGameplaySettings.breakComboOnShit;
			if (Reflect.hasField(replayGameplaySettings, 'accuracyMode')) ClientPrefs.data.accuracyMode = replayGameplaySettings.accuracyMode;
			if (Reflect.hasField(replayGameplaySettings, 'sustainAccuracy')) ClientPrefs.data.sustainAccuracy = replayGameplaySettings.sustainAccuracy;
			if (Reflect.hasField(replayGameplaySettings, 'kadeScoring')) ClientPrefs.data.kadeScoring = replayGameplaySettings.kadeScoring;
			// 断连依赖校正：shit 断连关闭时，bad 断连一并关闭
			if (!ClientPrefs.data.breakComboOnShit) ClientPrefs.data.breakComboOnBad = false;
		}
	}
	else
	{
isReplaying = false;
		// 普通局：彻底清空虚拟按键状态，避免上一局回放的残留按下（尤其旧回放缺失 releaseTime 的多键）污染本局
		Controls.instance.clearVirtualPressedStates();
		replayData = [];
		currentReplayIndex = 0;
		replayHeldKeys = [false, false, false, false];
		keyPressIndices = [-1, -1, -1, -1];
		replayNoteDelays = [[], [], [], []];
		replayHeldNonNoteKeys = new Map<Int, Bool>();
		nonNoteKeyPressIndices = new Map<Int, Int>();
		// 重置回放判定设置
		replayJudgmentSettings = null;
		// 重置回放游戏设置
		replayGameplaySettings = null;
		}

		startCallback = startCountdown;
		endCallback = endSong;

		// for lua
		instance = this;

		PauseSubState.songName = null; //Reset to default
		playbackRate = ClientPrefs.getGameplaySetting('songspeed');

		keysArray = [
			'note_left',
			'note_down',
			'note_up',
			'note_right'
		];
		
		// Initialize virtual input states for replay mode
		if (isReplaying)
		{
			Controls.instance.clearVirtualJustStates();
		}

		if(FlxG.sound.music != null)
			FlxG.sound.music.stop();

		// Gameplay settings
		healthGain = ClientPrefs.getGameplaySetting('healthgain');
		healthLoss = ClientPrefs.getGameplaySetting('healthloss');
		instakillOnMiss = ClientPrefs.getGameplaySetting('instakill');
		practiceMode = ClientPrefs.getGameplaySetting('practice');
		cpuControlled = ClientPrefs.getGameplaySetting('botplay');
		guitarHeroSustains = ClientPrefs.data.guitarHeroSustains;
		sustainTailFixMode = ClientPrefs.data.sustainTailFix;
		holdReleaseInstantMiss = ClientPrefs.data.holdReleaseInstantMiss;
		holdTailJudge = ClientPrefs.data.holdTailJudge;
		holdScoreBonus = ClientPrefs.data.holdScoreBonus;
		holdTailLeniency = ClientPrefs.data.holdTailLeniency;
		holdTailLeniencyMs = ClientPrefs.data.holdTailLeniencyMs;

		// PlayState宽屏自适应模式：根据设置开关临时切换缩放模式，高度锁定720，宽度960~1680自适应
		// 必须在创建任何相机/UI之前调用
		if (ENABLE_ADAPTIVE_WIDTH && ClientPrefs.data.playStateAdaptiveWidth)
		{
			if (!_psAdaptiveActive)
			{
				_psAdaptiveScaleMode = FlxG.scaleMode;
				FlxG.scaleMode = new PlayStateScaleMode();
				FlxG.resizeGame(FlxG.stage.stageWidth, FlxG.stage.stageHeight);
				_psAdaptiveActive = true;
			}
		}

		// var gameCam:FlxCamera = FlxG.camera;
		camGame = initPsychCamera();
		camHUD = new FlxCamera();
		camOther = new FlxCamera();
		camArchived = new FlxCamera();
		luaTpadCam = new FlxCamera();
		camHUD.bgColor.alpha = 0;
		camOther.bgColor.alpha = 0;
		camArchived.bgColor.alpha = 0;
		luaTpadCam.bgColor.alpha = 0;
		if(ClientPrefs.data.hudSize != 1.0) {
    		camHUD.zoom = ClientPrefs.data.hudSize;
		}

		camGame.pixelPerfectRender = ClientPrefs.data.playStatePixelPerfect;
		camHUD.pixelPerfectRender = ClientPrefs.data.playStatePixelPerfect;
		camOther.pixelPerfectRender = ClientPrefs.data.playStatePixelPerfect;
		camArchived.pixelPerfectRender = ClientPrefs.data.playStatePixelPerfect;

		FlxG.cameras.add(camHUD, false);
		FlxG.cameras.add(camOther, false);
		FlxG.cameras.add(camArchived, false);
		FlxG.cameras.add(luaTpadCam, false);

		persistentUpdate = true;
		persistentDraw = true;

		Conductor.mapBPMChanges(SONG);
		Conductor.bpm = SONG.bpm;

		#if DISCORD_ALLOWED
		// String that contains the mode defined here so it isn't necessary to call changePresence for each mode
		storyDifficultyText = Difficulty.getString();

		if (isStoryMode)
			detailsText = "Story Mode: " + WeekData.getCurrentWeek().weekName;
		else
			detailsText = "Freeplay";

		// String for when the game is paused
		detailsPausedText = "Paused - " + detailsText;
		#end

		GameOverSubstate.resetVariables();
		songName = Paths.formatToSongPath(SONG.song);
		backend.NoteTypesConfig.currentSongName = songName;
		if(SONG.stage == null || SONG.stage.length < 1)
			SONG.stage = StageData.vanillaSongStage(Paths.formatToSongPath(Song.loadedSongName));

		curStage = SONG.stage;

		var stageData:StageFile = StageData.getStageFile(curStage);
		defaultCamZoom = stageData.defaultZoom;

		stageUI = "normal";
		if (stageData.stageUI != null && stageData.stageUI.trim().length > 0)
			stageUI = stageData.stageUI;
		else if (stageData.isPixelStage == true) //Backward compatibility
			stageUI = "pixel";

		BF_X = stageData.boyfriend[0];
		BF_Y = stageData.boyfriend[1];
		GF_X = stageData.girlfriend[0];
		GF_Y = stageData.girlfriend[1];
		DAD_X = stageData.opponent[0];
		DAD_Y = stageData.opponent[1];

		if(stageData.camera_speed != null)
			cameraSpeed = stageData.camera_speed;

		boyfriendCameraOffset = stageData.camera_boyfriend;
		if(boyfriendCameraOffset == null) //Fucks sake should have done it since the start :rolling_eyes:
			boyfriendCameraOffset = [0, 0];

		opponentCameraOffset = stageData.camera_opponent;
		if(opponentCameraOffset == null)
			opponentCameraOffset = [0, 0];

		girlfriendCameraOffset = stageData.camera_girlfriend;
		if(girlfriendCameraOffset == null)
			girlfriendCameraOffset = [0, 0];

		boyfriendGroup = new FlxSpriteGroup(BF_X, BF_Y);
		dadGroup = new FlxSpriteGroup(DAD_X, DAD_Y);
		gfGroup = new FlxSpriteGroup(GF_X, GF_Y);

		switch (curStage)
		{
			case 'stage': new StageWeek1(); 			//Week 1
			case 'spooky': new Spooky();				//Week 2
			case 'philly': new Philly();				//Week 3
			case 'limo': new Limo();					//Week 4
			case 'mall': new Mall();					//Week 5 - Cocoa, Eggnog
			case 'mallEvil': new MallEvil();			//Week 5 - Winter Horrorland
			case 'school': new School();				//Week 6 - Senpai, Roses
			case 'schoolEvil': new SchoolEvil();		//Week 6 - Thorns
			case 'tank': new Tank();					//Week 7 - Ugh, Guns, Stress
			case 'phillyStreets': new PhillyStreets(); 	//Weekend 1 - Darnell, Lit Up, 2Hot
			case 'phillyBlazin': new PhillyBlazin();	//Weekend 1 - Blazin
		}
		if(isPixelStage) introSoundsSuffix = '-pixel';

		#if (LUA_ALLOWED || HSCRIPT_ALLOWED)
		luaDebugGroup = new FlxTypedGroup<psychlua.DebugLuaText>();
		luaDebugGroup.cameras = [camArchived];
		add(luaDebugGroup);
		#end

		if (!stageData.hide_girlfriend)
		{
			trace('[PlayState.create] gf创建前: ${Math.round((Sys.time() - __t0) * 1000)}ms');
			if(SONG.gfVersion == null || SONG.gfVersion.length < 1) SONG.gfVersion = 'gf'; //Fix for the Chart Editor
			gf = new Character(0, 0, SONG.gfVersion);
			startCharacterPos(gf);
			gfGroup.scrollFactor.set(0.95, 0.95);
			gfGroup.add(gf);
		}

		playOpponent = ClientPrefs.getGameplaySetting('playOpponent', false);
		trace('[PlayState.create] dad创建前: ${Math.round((Sys.time() - __t0) * 1000)}ms');
		dad = new Character(0, 0, SONG.player2);
		startCharacterPos(dad, true);
		dadGroup.add(dad);

		trace('[PlayState.create] boyfriend创建前: ${Math.round((Sys.time() - __t0) * 1000)}ms');
		boyfriend = new Character(0, 0, SONG.player1, true);
		startCharacterPos(boyfriend);
		boyfriendGroup.add(boyfriend);

		// Leather 舞台角色摆位：LE 的 character_Positions 语义是 [x=中心, y=脚底]（对照 LE 原版
		// StageGroup.setCharOffsets：setPosition(x - width/2, y - height)），Psych 是左上角。
		// 若不换算，角色左上直接落在 (1446,1656) 大坐标，Psych 相机 follow 角色中点时会错过
		// 舞台对象（视野 y 超过背景底边 → camGame 黑屏）。换算后角色中点约在 LE 坐标，
		// 相机跟随即可让角色与舞台背景同时进入视野。
		if (isLeatherChartFormat() && stageData != null && stageData.objects != null && stageData.objects.length > 0)
		{
			if (gf != null) gf.setPosition(gf.x - gf.width / 2, gf.y - gf.height);
			dad.setPosition(dad.x - dad.width / 2, dad.y - dad.height);
			boyfriend.setPosition(boyfriend.x - boyfriend.width / 2, boyfriend.y - boyfriend.height);
		}

		if (playOpponent)
		{
			// 交换"唱歌动画自动回位"行为：受控角色(dad)按玩家规则回位（配合 playerDance），
			// 自动演奏侧(boyfriend)按 CPU 规则自动回位，避免卡在 sing 姿势。
			// isPlayer 的 flipX 在构造时已应用完毕，此处修改只影响回位逻辑。
			dad.isPlayer = true;
			boyfriend.isPlayer = false;
		}
		
		if(stageData.objects != null && stageData.objects.length > 0)
		{
			trace('[PlayState.create] stage对象创建前: ${Math.round((Sys.time() - __t0) * 1000)}ms');
			var list:Map<String, FlxSprite> = StageData.addObjectsToState(stageData.objects, !stageData.hide_girlfriend ? gfGroup : null, dadGroup, boyfriendGroup, this);
			for (key => spr in list)
				if(!StageData.reservedNames.contains(key))
					variables.set(key, spr);
		}
		else
		{
			add(gfGroup);
		trace('[PlayState.create] 角色+stage创建: ${Math.round((Sys.time() - __t0) * 1000)}ms');
		add(dadGroup);
			add(boyfriendGroup);
		}
		
		#if (LUA_ALLOWED || HSCRIPT_ALLOWED)
		// "SCRIPTS FOLDER" SCRIPTS
		// Leather Engine API 兼容：设置非 off 时启用 LE API 运行时，并支持与 Psych API 共存——
		// auto 模式下按脚本内容自动分流（LE API 脚本走 LeatherLuaScript，Psych API 脚本走 FunkinLua，
		// 同一模组可两种脚本并存）；official/lts 强制全部走 LE；off 则全部按 Psych API。
		var leatherScriptActive:Bool = psychlua.leather.LeatherScriptRouter.isActive(SONG.format);
		var leatherApiVer:String = psychlua.leather.LeatherScriptRouter.resolveVersion(SONG.format);
		for (folder in Mods.directoriesWithFile(Paths.getSharedPath(), 'scripts/'))
			#if linux
			for (file in CoolUtil.sortAlphabetically(Paths.readDirectory(folder)))
			#else
			for (file in Paths.readDirectory(folder))
			#end
			{
				#if LUA_ALLOWED
				if(file.toLowerCase().endsWith('.lua'))
				{
					if (leatherScriptActive)
					{
						// 脚本级自动分流：内容检测命中 Psych API → Psych 运行时，否则走 LE 运行时
						if (psychlua.leather.LeatherScriptRouter.detectScriptRuntime(folder + file, SONG.format) == 'psych')
							new FunkinLua(folder + file);
						else
							leatherLuaArray.push(new psychlua.leather.LeatherLuaScript(folder + file, leatherApiVer, Mods.currentModDirectory));
					}
					else
						new FunkinLua(folder + file);
				}
				#end

				#if HSCRIPT_ALLOWED
				if(file.toLowerCase().endsWith('.hx'))
					initHScript(folder + file);
				#end
			}

		// Leather modchart 脚本：data/modcharts/{modchartPath}.lua（对照 LE 原版 PlayState ~951-958：
		// executeModchart = modchartPath 非空，先找 modcharts/ 再回退 scripts/，用 ModchartUtilities 执行）。
		// 走 LeatherLuaScript（LE API 语义），加载后立即广播 start(0) 让脚本创建初始对象。
		#if LUA_ALLOWED
		if (leatherScriptActive && SONG.modchartPath != null && SONG.modchartPath.length > 0)
		{
			var modchartPath:String = findLeatherModchartPath(SONG.modchartPath);
			if (modchartPath != null)
			{
				var modchartScript:psychlua.leather.LeatherLuaScript =
					new psychlua.leather.LeatherLuaScript(modchartPath, leatherApiVer, Mods.currentModDirectory);
				leatherLuaArray.push(modchartScript);
				modchartScript.call('start', [0]);
				trace('[LE modchart] loaded: $modchartPath');
			}
			else
				trace('[LE modchart] not found: data/modcharts/${SONG.modchartPath}.lua');
		}
		#end
		#end
			
		eventDebugGroup = new FlxTypedGroup<FlxText>();
		eventDebugGroup.cameras = [camArchived];
		add(eventDebugGroup);

		// 初始化事件处理器
		eventHandler = new EventHandler(this);

		var camPos:FlxPoint = FlxPoint.get(girlfriendCameraOffset[0], girlfriendCameraOffset[1]);
		if(gf != null)
		{
			camPos.x += gf.getGraphicMidpoint().x + gf.cameraPosition[0];
			camPos.y += gf.getGraphicMidpoint().y + gf.cameraPosition[1];
		}

		if(dad.curCharacter.startsWith('gf')) {
			dad.setPosition(GF_X, GF_Y);
			if(gf != null)
				gf.visible = false;
		}
		
		#if (LUA_ALLOWED || HSCRIPT_ALLOWED)
		// STAGE SCRIPTS
		#if LUA_ALLOWED startLuasNamed('stages/' + curStage + '.lua'); #end
		#if HSCRIPT_ALLOWED startHScriptsNamed('stages/' + curStage + '.hx'); #end

		// CHARACTER SCRIPTS
		if(gf != null) startCharacterScripts(gf.curCharacter);
		startCharacterScripts(dad.curCharacter);
		startCharacterScripts(boyfriend.curCharacter);
		#end

		uiGroup = new FlxSpriteGroup();
		comboGroup = new FlxSpriteGroup();
		noteGroup = new FlxTypedGroup<FlxBasic>();
		add(laneCovers);
		// 旧版HUD模式(legacyHUD): 不将 comboGroup/uiGroup/noteGroup 加入 state,
		// 其元素改由 addToHUD/addToNoteLayer/addToComboLayer 直接 add 进 state, 以复刻 0.6.x 结构。
		if (!ClientPrefs.data.legacyHUD)
		{
			add(comboGroup);
			add(uiGroup);
			add(noteGroup);
		}

		Conductor.songPosition = -Conductor.crochet * 5 + Conductor.offset;
		var showTime:Bool = (ClientPrefs.data.timeBarType != 'Disabled');

		timeTxt = new FlxText(STRUM_X + (FlxG.width / 2) - 248, 19, 640, "", 32);
		// 设置时间条文本大小和边框大小
		var baseTextSize:Int = (ClientPrefs.data.timebarStyle == "Leather" || ClientPrefs.data.timebarStyle == "Leather (Legacy)") ? 16 : 32;
		var baseBorderSize:Float = (ClientPrefs.data.timebarStyle == "Leather" || ClientPrefs.data.timebarStyle == "Leather (Legacy)") ? 1 : 2;
		// 应用 biggerInfoText
		if (ClientPrefs.data.biggerInfoText && (ClientPrefs.data.timebarStyle == "Leather" || ClientPrefs.data.timebarStyle == "Leather (Legacy)")) {
			baseTextSize = 20;
			baseBorderSize = 1.5;
		} else if (ClientPrefs.data.biggerInfoText) {
			baseTextSize = 32;
			baseBorderSize = 2;
		}
		timeTxt.setFormat(Paths.font("vcr.ttf"), baseTextSize, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		timeTxt.scrollFactor.set();
		timeTxt.alpha = 0;
		timeTxt.borderSize = baseBorderSize;
		timeTxt.visible = updateTime = showTime;
		timeTxt.screenCenter(X);

		if (ClientPrefs.data.downScroll)
			timeTxt.y = FlxG.height - 44;

		if (ClientPrefs.data.timeBarType == 'Song Name' && ClientPrefs.data.timebarStyle != "Leather" && ClientPrefs.data.timebarStyle != "Leather (Legacy)")
		{
			timeTxt.text = (ClientPrefs.data.timebarStyle == "Kade") ? SONG.song.replace(" ", "-") : SONG.song;
		}
		else if (ClientPrefs.data.timebarStyle == "Kade" && ClientPrefs.data.timeBarType != 'Song Name')
		{
			timeTxt.text = SONG.song.replace(" ", "-");
		}

		// 确定条样式
		var barStyle:String = "timeBar";
		if (ClientPrefs.data.timebarStyle == "Kade")
		{
			barStyle = "barKEL";
		}
		else if (ClientPrefs.data.timebarStyle == "Leather" || ClientPrefs.data.timebarStyle == "Leather (Legacy)")
		{
			barStyle = "barLE";
		}

		timeBar = new Bar(0, timeTxt.y + (timeTxt.height / 4), barStyle, function() return songPercent, 0, 1);
		timeBar.scrollFactor.set();
		timeBar.screenCenter(X);
		timeBar.alpha = 0;
		timeBar.visible = showTime;
		if (ClientPrefs.data.timeBarStripes) {
			timeBar.showStripes = true;
			timeBar.createStripedOverlay();
		}

		// 特殊处理Leather样式
		if (ClientPrefs.data.timebarStyle == "Leather")
		{
			// Leather 样式：文本在条内部
			timeTxt.size = ClientPrefs.data.biggerInfoText ? 20 : 16;
			if (ClientPrefs.data.biggerInfoText) {
				timeTxt.borderSize = 1.5;
			}
			if (ClientPrefs.data.downScroll) {
				timeBar.y = FlxG.height - (timeBar.height + 1);
				timeTxt.y = timeBar.y;
			} else {
				timeBar.y = 1;
				timeTxt.y = timeBar.y;
			}
			timeTxt.text = SONG.song + " ~ " + Difficulty.getString().toUpperCase() + " (0:00)";
		}
		else if (ClientPrefs.data.timebarStyle == "Leather (Legacy)")
		{
			// Leather (Legacy) 样式：文本在条外部（原来的行为）
			timeTxt.size = ClientPrefs.data.biggerInfoText ? 20 : 16;
			if (ClientPrefs.data.biggerInfoText) {
				timeTxt.borderSize = 1.5;
			}
			if (ClientPrefs.data.downScroll) {
				// downScroll 时，条在底部，文本在条上方
				timeBar.y = FlxG.height - (timeBar.height + 1);
				timeTxt.y = timeBar.y - timeTxt.height;
			} else {
				// 普通模式，条在顶部，文本在条下方
				timeBar.y = 1;
				timeTxt.y = timeBar.y + timeBar.height;
			}
			timeTxt.text = SONG.song + " ~ " + Difficulty.getString().toUpperCase() + " (0:00)";
			// 对于 Leather (Legacy) 样式，设置为青色
			timeBar.setColors(FlxColor.CYAN, FlxColor.BLACK);
		}
		else
		{
			timeBar.y = timeTxt.y + (timeTxt.height / 4);
		}

		// 先添加条再添加文本，确保文本在上面
		addToHUD(timeBar);
		addToHUD(timeTxt);
		// 对于 Kade 样式：保留 barKEL.png 边框纹理
		// 填充为 LIME，空白为 GRAY（填充色从贴图透明中心透出）
		if (ClientPrefs.data.timebarStyle == "Kade") {
			timeBar.setColors(FlxColor.LIME, FlxColor.GRAY);
			// 沿用 songName 样式：字号16、白色、居中、黑色描边，描边粗细1
			timeTxt.setFormat(Paths.font("vcr.ttf"), 16, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			timeTxt.borderSize = 1;
			timeTxt.y = timeBar.y;
			timeTxt.y -= (ClientPrefs.data.downScroll == true) ? 3 : 0;
			timeTxt.x = timeBar.x;
		}

		// Psych 与 Leather (Legacy) 样式下的渐变时间条：对手色→玩家色
		if ((ClientPrefs.data.timebarStyle == "Psych" || ClientPrefs.data.timebarStyle == "Leather (Legacy)") && ClientPrefs.data.timeBarGradient && dad != null && boyfriend != null) {
			var dadColor:FlxColor = FlxColor.fromRGB(dad.healthColorArray[0], dad.healthColorArray[1], dad.healthColorArray[2]);
			var bfColor:FlxColor = FlxColor.fromRGB(boyfriend.healthColorArray[0], boyfriend.healthColorArray[1], boyfriend.healthColorArray[2]);
			timeBar.useGradient = true;
			timeBar.setGradientColors(dadColor, bfColor);
		}

		// 根据 holdNoteBehind 设置调整图层顺序
		if (ClientPrefs.data.holdNoteBehind) {
			// 如果 holdNoteBehind 是 true，先添加 hold notes（在最下面）
			// 然后添加 strumLineNotes
			// 最后添加 normal notes（在最上面）
		} else {
			// 如果 holdNoteBehind 是 false，保持原来的顺序
			addToNoteLayer(strumLineNotes);
		}

		// 处理Song Name类型的调整（排除Leather样式）
		if (ClientPrefs.data.timeBarType == 'Song Name' && ClientPrefs.data.timebarStyle != "Leather" && ClientPrefs.data.timebarStyle != "Leather (Legacy)" && ClientPrefs.data.timebarStyle != "Kade")
		{
			timeTxt.size = 24;
			timeTxt.y += 3;
		}

		// Extra Keys：多键收缩系数改由 applyMania 内统一计算（此处调用时 applyMania 尚未执行、
		// totalColumns 仍为默认 4，条件恒假；且 applyMania 每次都会重置 strumScale=1，必须在其重置后重算）
		generateSong();
		trace('[PlayState.create] generateSong: ${Math.round((Sys.time() - __t0) * 1000)}ms');

		// 根据 holdNoteBehind 设置调整图层顺序
		if (ClientPrefs.data.holdNoteBehind) {
			// 如果 holdNoteBehind 是 true，按以下顺序添加：
			// 1. hold notes（最下面）
			// 2. strumLineNotes（中间）
			// 3. normal notes（最上面）
			addToNoteLayer(holdNotes);
			addToNoteLayer(strumLineNotes);
			addToNoteLayer(normalNotes);
		} else {
			// 如果 holdNoteBehind 是 false，保持原来的顺序
			addToNoteLayer(notes);
		}

		addToNoteLayer(grpNoteSplashes);
		addToNoteLayer(grpHoldCovers);

		camFollow = new FlxObject();
		camFollow.setPosition(camPos.x, camPos.y);
		camPos.put();

		if (prevCamFollow != null)
		{
			camFollow = prevCamFollow;
			prevCamFollow = null;
		}
		add(camFollow);

		FlxG.camera.follow(camFollow, LOCKON, 0);
		FlxG.camera.zoom = defaultCamZoom;
		FlxG.camera.snapToTarget();

		FlxG.worldBounds.set(0, 0, FlxG.width, FlxG.height);
		moveCameraSection();

		// 计算血条 Y 位置
		var healthBarY:Float = 0;
		if (ClientPrefs.data.healthbarstyle == 'Leather') {
			// LeatherEngine 原版：0.9 (正常) / 60 (downscroll)
			healthBarY = !ClientPrefs.data.downScroll ? FlxG.height * 0.9 : 60;
		} else {
			healthBarY = FlxG.height * (!ClientPrefs.data.downScroll ? 0.89 : 0.11);
		}

		healthBar = new Bar(0, healthBarY, 'healthBar', function() return (ClientPrefs.data.smoothHP ? smoothHealth : health), 0, 2);
		healthBar.screenCenter(X);
		// 普通模式：leftToRight=false，玩家(bf 在右)命中使右侧颜色向左扩张，维持原本逻辑。
		// playOpponent：玩家改为控制左侧 dad，血条改为“由左到右、从低到高”填充（leftToRight=true），
		// 此时 dad 在左、bf 在右且位置不变，命中时左侧 dad 颜色向右扩张，方向符合“血量低→高 左→右”过渡。
		healthBar.leftToRight = playOpponent;
		healthBar.scrollFactor.set();
		healthBar.visible = !ClientPrefs.data.hideHud;
		healthBar.alpha = ClientPrefs.data.healthBarAlpha;
		if (ClientPrefs.data.healthbarstyle == 'OS') {
			healthBar.showStripes = true;
			healthBar.stripeWidth = 7;
			healthBar.stripeGap = 12;
			healthBar.stripeAngle = -45;
			healthBar.stripeColor = FlxColor.BLACK;
			healthBar.createStripedOverlay();
		}
		reloadHealthBarColors();
		addToHUD(healthBar);

		msTimeTxt = new FlxText(0, 0, 250, "", 32);
		msTimeTxt.setFormat(Paths.font('vcr.ttf'), 24, FlxColor.WHITE, RIGHT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		msTimeTxt.scrollFactor.set();
		msTimeTxt.alpha = 0;
		msTimeTxt.visible = true;
		msTimeTxt.borderSize = 1.3;
		/*mstimeTxt.y = comboSpr.y + 20;
		mstimeTxt.x += comboSpr.x + 100;*/
		// [6,7] 始终作为 msTimeTxt 二次偏移；'numScore' 时额外沿用 combo 数字槽位 [2,3] 作为基础锚点
		var msInitBaseX:Int = 0;
		var msInitBaseY:Int = 0;
		if (ClientPrefs.data.msTimingOffsetMode != 'independent') {
			msInitBaseX = ClientPrefs.data.comboOffset[2];
			msInitBaseY = ClientPrefs.data.comboOffset[3];
		} else {
			msInitBaseX = 150; // 独立偏移：默认在此基础上额外右移 150
		}
		msTimeTxt.x = FlxG.width * 0.35 + 100 + msInitBaseX + ClientPrefs.data.comboOffset[6] + 60 - 20 - 40;
		msTimeTxt.y = (FlxG.height * 0.5) + 80 - 40 - msInitBaseY - ClientPrefs.data.comboOffset[7];
		addToComboLayer(msTimeTxt);

		iconP1 = new HealthIcon(boyfriend.healthIcon, true);
		if (ClientPrefs.data.healthbarstyle == 'Leather') {
			// LeatherEngine 原版：图标在血条上居中
			iconP1.y = healthBar.y - (iconP1.height / 2) - iconP1.offset.y;
		} else {
			iconP1.y = healthBar.y - iconP1.frameHeight / 2;
		}
		iconP1.visible = !ClientPrefs.data.hideHud;
		iconP1.alpha = ClientPrefs.data.healthBarAlpha;
		iconP1.startSize = iconP1.scale.x;
		addToHUD(iconP1);

		iconP2 = new HealthIcon(dad.healthIcon, false);
		if (ClientPrefs.data.healthbarstyle == 'Leather') {
			// LeatherEngine 原版：图标在血条上居中
			iconP2.y = healthBar.y - (iconP2.height / 2) - iconP2.offset.y;
		} else {
			iconP2.y = healthBar.y - iconP2.frameHeight / 2;
		}
		iconP2.visible = !ClientPrefs.data.hideHud;
		iconP2.alpha = ClientPrefs.data.healthBarAlpha;
		iconP2.startSize = iconP2.scale.x;
		addToHUD(iconP2);

		if(ClientPrefs.data.scoretxtstyle == 'Kade') 
		{
		scoreTxt = new FlxText(0, healthBar.y + 50, FlxG.width, "", 20);
		scoreTxt.screenCenter(X);
		scoreTxt.scrollFactor.set();
		scoreTxt.setFormat(Paths.font("vcr.ttf"), 16, FlxColor.WHITE, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		}
		else if (ClientPrefs.data.scoretxtstyle == 'V-Slice')	
		{
			scoreTxt = new FlxText(FlxG.width / 2 - 235, healthBar.y + 50, 0, "", 20);
			scoreTxt.screenCenter(X);
			scoreTxt.x += 100;
			scoreTxt.scrollFactor.set();
			scoreTxt.setFormat(Paths.font("vcr.ttf"), 16, FlxColor.WHITE, FlxTextAlign.CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		}
		else if (ClientPrefs.data.scoretxtstyle == 'OS')	
		{
			scoreTxt = new FlxText(0, healthBar.y + 28, FlxG.width, "", 16);
			scoreTxt.setFormat(Paths.font("vcr.ttf"), 16, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			scoreTxt.scrollFactor.set();
			scoreTxt.borderSize = 1.2;
			scoreTxt.visible = !ClientPrefs.data.hideHud;
		}
		else if (ClientPrefs.data.scoretxtstyle == 'Leather')	
		{
			// LeatherEngine 原版：healthBarBG.y + 45
			// 字号：biggerInfoText ? 20 : 16
			scoreTxt = new FlxText(0, healthBar.y + 45, FlxG.width, "", 20);
			scoreTxt.screenCenter(X);
			scoreTxt.scrollFactor.set();
			scoreTxt.setFormat(Paths.font("vcr.ttf"), ClientPrefs.data.biggerInfoText ? 20 : 16, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			scoreTxt.borderSize = 1.25;
			scoreTxt.visible = !ClientPrefs.data.hideHud;
		}
		else if (ClientPrefs.data.scoretxtstyle == 'Psych (Old)')	
			{
				// PsychEngine 0.4.2 原版：y = healthBarBG.y + 36（healthBarBG.y = healthBar.y - 4）
				// 字号 20、边框 1.25、居中，位置 healthBar.y + 32
				scoreTxt = new FlxText(0, healthBar.y + 32, FlxG.width, "", 20);
				scoreTxt.screenCenter(X);
				scoreTxt.scrollFactor.set();
				scoreTxt.setFormat(Paths.font("vcr.ttf"), 20, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
				scoreTxt.borderSize = 1.25;
				scoreTxt.visible = !ClientPrefs.data.hideHud;
			}
			else if (ClientPrefs.data.scoretxtstyle == 'Forever')
			{
				// Forever Engine 原版：healthBar 下方居中，字号 18，边框 1.5
				scoreTxt = new FlxText(0, healthBar.y + 40, FlxG.width, "", 18);
				scoreTxt.screenCenter(X);
				scoreTxt.scrollFactor.set();
				scoreTxt.setFormat(Paths.font("vcr.ttf"), 18, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
				scoreTxt.borderSize = 1.5;
				scoreTxt.visible = !ClientPrefs.data.hideHud;
			}
		else 
		{
		scoreTxt = new FlxText(0, healthBar.y + 40, FlxG.width, "", 20);
		scoreTxt.setFormat(Paths.font("vcr.ttf"), 20, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		scoreTxt.scrollFactor.set();
		scoreTxt.borderSize = 1.25;
		scoreTxt.visible = !ClientPrefs.data.hideHud;
		}
		// 依据设置载入分数文字语言（auto 时跟随游戏语言）
		ScoreLanguage.load();
		scoreTxt.setFormat(Paths.font(ScoreLanguage.getScoreFont()), scoreTxt.size, FlxColor.WHITE, scoreTxt.alignment, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);

		addToHUD(scoreTxt);

		botplayTxt = new FlxText(400, ClientPrefs.data.botplayStyle == 'Kade' ? healthBar.y - 120 : healthBar.y - 90, FlxG.width - 800, "BOTPLAY", 32);
		//botplayTxt = new FlxText(400, healthBar.y - 90, FlxG.width - 800, LanguageBasic.getPhrase("Botplay").toUpperCase(), 32);
		botplayTxt.setFormat(Paths.font("vcr.ttf"), ClientPrefs.data.botplayStyle == 'Kade' ? 37 : 32, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		botplayTxt.scrollFactor.set();
		botplayTxt.borderSize = ClientPrefs.data.botplayStyle == 'Kade' ? 2 : 1.25;
		botplayTxt.visible = cpuControlled;
		addToHUD(botplayTxt);

		// 创建回放模式指示文本
		replayTxt = new FlxText(400, ClientPrefs.data.botplayStyle == 'Kade' ? healthBar.y - 120 : healthBar.y - 90, FlxG.width - 800, "REPLAY", 32);
		replayTxt.setFormat(Paths.font("vcr.ttf"), 37, 0xFF00FF00, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		replayTxt.scrollFactor.set();
		replayTxt.screenCenter();
		replayTxt.y -= 100;
		replayTxt.borderSize = 2;
		replayTxt.color = FlxColor.fromRGB(boyfriend.healthColorArray[0], boyfriend.healthColorArray[1], boyfriend.healthColorArray[2]);
		replayTxt.visible = isReplaying;
		addToHUD(replayTxt);

		if(ClientPrefs.data.downScroll)
			botplayTxt.y = ClientPrefs.data.botplayStyle == 'Kade' ? healthBar.y + 120 : healthBar.y + 70;

		var watermarkContent:String;
		switch (ClientPrefs.data.watermarkType)
		{
			case 'OS':
				watermarkContent = 'OS v${ClientPrefs.data.fakeOSVersion}';
			case 'Psych':
				watermarkContent = 'PE ${MainMenuState.psychEngineVersion}';
			case 'Kade':
				watermarkContent = 'KE v1.5.4';
			default: // Kathy
				watermarkContent = 'KYE v${MainMenuState.kathyEngineVersion}';
		}
		var isLeatherBar:Bool = ClientPrefs.data.timebarStyle == 'Leather' || ClientPrefs.data.timebarStyle == 'Leather (Legacy)';
		if (!isLeatherBar && (ClientPrefs.data.watermarkType == 'OS' || ClientPrefs.data.watermarkType == 'Kathy' || ClientPrefs.data.watermarkType == 'Psych' || ClientPrefs.data.watermarkType == 'Kade'))
			watermarkContent = '${SONG.song}-${Difficulty.getString().toUpperCase()} | ' + watermarkContent;
		
		watermarkTxt = new FlxText(20, FlxG.height - 20, 0, watermarkContent, 14);
		watermarkTxt.setFormat(Paths.font("vcr.ttf"), 16, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		watermarkTxt.scrollFactor.set();
		watermarkTxt.y = !ClientPrefs.data.downScroll ? (watermarkTxt.height * 0.5) : FlxG.height - (watermarkTxt.height * 1.5);
		watermarkTxt.visible = !ClientPrefs.data.hideHud;
		if (ClientPrefs.data.waterMarkPlay)	addToHUD(watermarkTxt);

		// 使用新的 RatingCounter 模块（仅当开启评分计数器时创建，避免禁用后左侧依旧显示文本）
		if (ClientPrefs.data.ratCounter)
		{
			ratingCounterModule = new objects.RatingCounter(6, 0, ratingsData);
			ratingCounterModule.updatePosition();
			ratingCounterModule.setVisible(!ClientPrefs.data.hideHud);
			if (ClientPrefs.data.legacyHUD)
			{
				// 旧版HUD模式: 将所有评分文本直接加入 state, 供旧模组脚本 getObjectOrder/setObjectOrder 定位
				for (rt in ratingCounterModule.ratingTexts)
				{
					add(rt.text);
					rt.text.cameras = [camHUD];
				}
				add(ratingCounterModule.maText);
				ratingCounterModule.maText.cameras = [camHUD];
				add(ratingCounterModule.paText);
				ratingCounterModule.paText.cameras = [camHUD];
				add(ratingCounterModule.sickPlusText);
				ratingCounterModule.sickPlusText.cameras = [camHUD];
			}
			else
				ratingCounterModule.addToGroup(uiGroup);
		}

		uiGroup.cameras = [camHUD];
		noteGroup.cameras = [camHUD];
		//comboGroup.cameras = [camHUD];
		comboGroup.cameras = [ClientPrefs.data.ratingsPos == 'camHUD' ? camHUD : camGame];

		// 箭头倒计时：两箭头间隔 ≥ 3秒 时显示圆形进度圈 + 整数秒
		if (ClientPrefs.data.noteTimerEnabled)
		{
			noteTimer = new ui.NoteTimer(this);
			// 根据 noteTimerLayer 设置决定图层：压在箭头之上 还是 在箭头之下
			var aboveNotes:Bool = (ClientPrefs.data.noteTimerLayer == 'Above Notes');
			if (ClientPrefs.data.legacyHUD)
			{
				if (aboveNotes)
					add(noteTimer); // 加入 members 末尾 → 最顶层
				else
					insert(members.indexOf(strumLineNotes), noteTimer); // 插入 strumLineNotes 之前 → 箭头之下
				noteTimer.cameras = [camHUD];
			}
			else
			{
				if (aboveNotes)
					add(noteTimer); // 直接加入 state，比 noteGroup 晚 add → 箭头之上
				else
					uiGroup.add(noteTimer); // uiGroup 在 noteGroup 之前 add → 箭头之下
				noteTimer.cameras = [camHUD];
			}
		}

		startingSong = true;

		// PER-SONG CUSTOM EVENTS & NOTETYPES (take priority over global)
		var perSongEventScripts:Array<String> = [];
		var perSongNoteTypeScripts:Array<String> = [];

		#if (LUA_ALLOWED || HSCRIPT_ALLOWED)
		#if MODS_ALLOWED
		for (folder in Mods.directoriesWithFile(Paths.getSharedPath(), 'data/$songName/'))
		{
			// custom_events subfolder
			var eventsFolder:String = folder + 'custom_events/';
			if(FileSystem.exists(eventsFolder))
			{
				for (file in Paths.readDirectory(eventsFolder))
				{
					var eventName:String = file;
					var ext:String = '';
					if(file.toLowerCase().endsWith('.lua')) { eventName = file.substr(0, file.length - 4); ext = '.lua'; }
					else if(file.toLowerCase().endsWith('.hx')) { eventName = file.substr(0, file.length - 3); ext = '.hx'; }

					if(!perSongEventScripts.contains(eventName))
						perSongEventScripts.push(eventName);

					#if LUA_ALLOWED
					if(ext == '.lua') new FunkinLua(eventsFolder + file);
					#end
					#if HSCRIPT_ALLOWED
					if(ext == '.hx') initHScript(eventsFolder + file);
					#end
				}
			}

			// custom_notetypes subfolder
			var typesFolder:String = folder + 'custom_notetypes/';
			if(FileSystem.exists(typesFolder))
			{
				for (file in Paths.readDirectory(typesFolder))
				{
					var typeName:String = file;
					var ext:String = '';
					if(file.toLowerCase().endsWith('.lua')) { typeName = file.substr(0, file.length - 4); ext = '.lua'; }
					else if(file.toLowerCase().endsWith('.hx')) { typeName = file.substr(0, file.length - 3); ext = '.hx'; }

					if(!perSongNoteTypeScripts.contains(typeName))
						perSongNoteTypeScripts.push(typeName);

					#if LUA_ALLOWED
					if(ext == '.lua') new FunkinLua(typesFolder + file);
					#end
					#if HSCRIPT_ALLOWED
					if(ext == '.hx') initHScript(typesFolder + file);
					#end
				}
			}
		}
		#end
		#end

		#if LUA_ALLOWED
		for (notetype in noteTypes)
		{
			if(!perSongNoteTypeScripts.contains(notetype))
				startLuasNamed('custom_notetypes/' + notetype + '.lua');
		}
		for (event in eventsPushed)
		{
			if(!perSongEventScripts.contains(event))
				startLuasNamed('custom_events/' + event + '.lua');
		}
		#end

		#if HSCRIPT_ALLOWED
		for (notetype in noteTypes)
		{
			if(!perSongNoteTypeScripts.contains(notetype))
				startHScriptsNamed('custom_notetypes/' + notetype + '.hx');
		}
		for (event in eventsPushed)
		{
			if(!perSongEventScripts.contains(event))
				startHScriptsNamed('custom_events/' + event + '.hx');
		}
		#end
		noteTypes = null;

		// SONG SPECIFIC SCRIPTS
		#if (LUA_ALLOWED || HSCRIPT_ALLOWED)
		for (folder in Mods.directoriesWithFile(Paths.getSharedPath(), 'data/$songName/'))
			#if linux
			for (file in CoolUtil.sortAlphabetically(Paths.readDirectory(folder)))
			#else
			for (file in Paths.readDirectory(folder))
			#end
			{
				#if LUA_ALLOWED
				if(file.toLowerCase().endsWith('.lua'))
					new FunkinLua(folder + file);
				#end

				#if HSCRIPT_ALLOWED
				if(file.toLowerCase().endsWith('.hx'))
					initHScript(folder + file);
				#end
			}
		#end
		
		// Extra Keys：非 4 键谱面强制使用 Hitbox 预设。
		// TouchPad 预设（RIGHT_FULL/LEFT_FULL/CUSTOM/DOUBLE）只绑定 NOTE_LEFT..NOTE_RIGHT 四列，
		// 多出来的轨道在触屏上无法按下；这里仅对本次进曲生效，不改动用户保存的设置。
		var prevForcedMode:Null<Int> = MobileData.forcedMode;
		if (mobileLaneCount() > 4)
			MobileData.forcedMode = 3;
		addMobileControls();
		MobileData.forcedMode = prevForcedMode;
		mobileControls.instance.visible = true;
		mobileControls.onButtonDown.add(onButtonPress);
		mobileControls.onButtonUp.add(onButtonRelease);

		createMobilePauseButton();

		if(eventNotes.length > 0)
		{
			for (event in eventNotes) event.strumTime -= eventHandler.eventEarlyTrigger(event);
			eventNotes.sort(sortByTime);
		}

		startCallback();
		trace('[PlayState.create] HUD+脚本初始化完成: ${Math.round((Sys.time() - __t0) * 1000)}ms');
		RecalculateRating(false, false);

		FlxG.stage.addEventListener(KeyboardEvent.KEY_DOWN, onKeyPress);
		FlxG.stage.addEventListener(KeyboardEvent.KEY_UP, onKeyRelease);

		//PRECACHING THINGS THAT GET USED FREQUENTLY TO AVOID LAGSPIKES
		// 以下资源已由 LoadingState.prepareToSong() 在后台线程预加载，此处仅为确保缓存命中（几乎无开销）
		if(ClientPrefs.data.hitsoundVolume > 0) Paths.sound('hitsound');
		if (ClientPrefs.data.hitsound != 'none' && ClientPrefs.data.hitsound != null && ClientPrefs.data.hitsound.length > 0)
			Paths.sound('hitsounds/' + ClientPrefs.data.hitsound);
		if(ClientPrefs.data.ghostTappingMode != 'always') for (i in 1...4) Paths.sound('missnote$i');
		Paths.image('alphabet');

		// 打击音对象池：预建 N 个 FlxSound 实例复用，避免高密度谱每击 new + GC 卡顿（可在设置中开关/调整大小）
		if (ClientPrefs.data.hitSoundPoolEnabled)
			hitSoundPool = new HitSoundPool(ClientPrefs.data.hitSoundPoolSize);

		if (PauseSubState.songName != null)
			Paths.music(PauseSubState.songName);
		else if(Paths.formatToSongPath(ClientPrefs.data.pauseMusic) != 'none')
			Paths.music(Paths.formatToSongPath(ClientPrefs.data.pauseMusic));

		resetRPC();

		stagesFunc(function(stage:BaseStage) stage.createPost());
		callOnScripts('onCreatePost');
		
		var splash:NoteSplash = new NoteSplash();
		grpNoteSplashes.add(splash);
		splash.alpha = 0.000001; //cant make it invisible or it won't allow precaching

		// 预缓存 Hold Cover 贴图，避免第一次长条命中时卡顿
		if(ClientPrefs.data.holdCovers)
		{
			if (NoteHoldCover.isRGBSkin())
				Paths.image(NoteHoldCover.getRGBAtlasPath());
			else
				for (c in NoteHoldCover.COVER_COLORS)
					Paths.image(NoteHoldCover.getColorAtlasPath(c));
		}

		#if !android
		addTouchPad('NONE', 'P');
		addTouchPadCamera();
		#end

		trace('[PlayState.create] create() 总耗时: ${Math.round((Sys.time() - __t0) * 1000)}ms');
		super.create();
		iconP1InitialY = iconP1.y;
   	 	iconP2InitialY = iconP2.y;

		// 倒计时资源已由 LoadingState 后台预加载，此处为缓存命中（几乎无开销）
		cacheCountdown();

		// 标记需要延迟执行的非关键初始化（在首帧 update 中分摊到后续帧，避免卡死）
		_deferredInitStep = 0;

		if(eventNotes.length < 1) eventHandler.checkEventNote();
	}

	function set_songSpeed(value:Float):Float
	{
		if(generatedMusic)
		{
			var ratio:Float = value / songSpeed; //funny word huh
			if(ratio != 1)
			{
				for (note in notes.members) note.resizeByRatio(ratio);
				for (note in unspawnNotes) note.resizeByRatio(ratio);
			}
		}
		songSpeed = value;
		noteKillOffset = Math.max(Conductor.stepCrochet, 350 / songSpeed * playbackRate);
		return value;
	}

	function set_playbackRate(value:Float):Float
	{
		#if FLX_PITCH
		if(generatedMusic)
		{
			vocals.pitch = value;
			opponentVocals.pitch = value;
			FlxG.sound.music.pitch = value;

			var ratio:Float = playbackRate / value; //funny word huh
			if(ratio != 1)
			{
				for (note in notes.members) note.resizeByRatio(ratio);
				for (note in unspawnNotes) note.resizeByRatio(ratio);
			}
		}
		playbackRate = value;
		FlxG.animationTimeScale = value;
		Conductor.offset = Reflect.hasField(PlayState.SONG, 'offset') ? (PlayState.SONG.offset / value) : 0;
		// safeZoneOffset: 启用shitWindow模式时使用固定值，否则沿用safeFrames计算
		if (ClientPrefs.data.useShitWindowAsSafeZone)
			Conductor.safeZoneOffset = ClientPrefs.data.shitWindow * value;
		else
			Conductor.safeZoneOffset = (ClientPrefs.data.safeFrames / 60) * 1000 * value;
		#if VIDEOS_ALLOWED
		if(videoCutscene != null && videoCutscene.videoSprite != null) videoCutscene.videoSprite.bitmap.rate = value;
		#end
		setOnScripts('playbackRate', playbackRate);
		#else
		playbackRate = 1.0; // ensuring -Crow
		#end
		return playbackRate;
	}

	#if (LUA_ALLOWED || HSCRIPT_ALLOWED)
	public function addTextToDebug(text:String, color:FlxColor) {
		var newText:psychlua.DebugLuaText = luaDebugGroup.recycle(psychlua.DebugLuaText);
		newText.text = text;
		newText.color = color;
		newText.disableTime = 6;
		newText.alpha = 1;
		newText.setPosition(10, 8 - newText.height);

		luaDebugGroup.forEachAlive(function(spr:psychlua.DebugLuaText) {
			spr.y += newText.height + 2;
		});
		luaDebugGroup.add(newText);

		Sys.println(text);
		
		// 同时输出到游戏日志显示
		if (Main.gameLogVar != null && Main.gameLogVar.isEnabled)
		{
			Main.gameLogVar.addLogWithColor(text, color);
		}
	}
	#end

	public function reloadHealthBarColors() {
		// 不改变左右颜色顺序：左侧始终是 dad、右侧始终是 bf（playOpponent 仅改填充方向，不动图标/颜色位置）。
		healthBar.setColors(FlxColor.fromRGB(dad.healthColorArray[0], dad.healthColorArray[1], dad.healthColorArray[2]),
			FlxColor.fromRGB(boyfriend.healthColorArray[0], boyfriend.healthColorArray[1], boyfriend.healthColorArray[2]));
	}

	public function addCharacterToList(newCharacter:String, type:Int) {
		switch(type) {
			case 0:
				if(!boyfriendMap.exists(newCharacter)) {
					var newBoyfriend:Character = new Character(0, 0, newCharacter, true);
					boyfriendMap.set(newCharacter, newBoyfriend);
					boyfriendGroup.add(newBoyfriend);
					startCharacterPos(newBoyfriend);
					newBoyfriend.alpha = 0.00001;
					startCharacterScripts(newBoyfriend.curCharacter);
				}

			case 1:
				if(!dadMap.exists(newCharacter)) {
					var newDad:Character = new Character(0, 0, newCharacter);
					dadMap.set(newCharacter, newDad);
					dadGroup.add(newDad);
					startCharacterPos(newDad, true);
					newDad.alpha = 0.00001;
					startCharacterScripts(newDad.curCharacter);
				}

			case 2:
				if(gf != null && !gfMap.exists(newCharacter)) {
					var newGf:Character = new Character(0, 0, newCharacter);
					newGf.scrollFactor.set(0.95, 0.95);
					gfMap.set(newCharacter, newGf);
					gfGroup.add(newGf);
					startCharacterPos(newGf);
					newGf.alpha = 0.00001;
					startCharacterScripts(newGf.curCharacter);
				}
		}
	}

	function startCharacterScripts(name:String)
	{
		// Lua
		#if LUA_ALLOWED
		var doPush:Bool = false;
		var luaFile:String = 'characters/$name.lua';
		#if MODS_ALLOWED
		var replacePath:String = Paths.modFolders(luaFile);
		if(FileSystem.exists(replacePath))
		{
			luaFile = replacePath;
			doPush = true;
		}
		else
		{
			luaFile = Paths.getSharedPath(luaFile);
			if(FileSystem.exists(luaFile))
				doPush = true;
		}
		#else
		luaFile = Paths.getSharedPath(luaFile);
		if(Assets.exists(luaFile)) doPush = true;
		#end

		if(doPush)
		{
			for (script in luaArray)
			{
				if(script.scriptName == luaFile)
				{
					doPush = false;
					break;
				}
			}
			if(doPush) new FunkinLua(luaFile);
		}
		#end

		// HScript
		#if HSCRIPT_ALLOWED
		var doPush:Bool = false;
		var scriptFile:String = 'characters/' + name + '.hx';
		#if MODS_ALLOWED
		var replacePath:String = Paths.modFolders(scriptFile);
		if(FileSystem.exists(replacePath))
		{
			scriptFile = replacePath;
			doPush = true;
		}
		else
		#end
		{
			scriptFile = Paths.getSharedPath(scriptFile);
			if(FileSystem.exists(scriptFile))
				doPush = true;
		}

		if(doPush)
		{
			if(Iris.instances.exists(scriptFile))
				doPush = false;

			if(doPush) initHScript(scriptFile);
		}
		#end
	}

	public function getLuaObject(tag:String):Dynamic
		return variables.get(tag);

	function startCharacterPos(char:Character, ?gfCheck:Bool = false) {
		if(gfCheck && char.curCharacter.startsWith('gf')) { //IF DAD IS GIRLFRIEND, HE GOES TO HER POSITION
			char.setPosition(GF_X, GF_Y);
			char.scrollFactor.set(0.95, 0.95);
			char.danceEveryNumBeats = 2;
		}
		char.x += char.positionArray[0];
		char.y += char.positionArray[1];
	}

	/** 当前谱面是否为 Leather 系（LEATHER / LEATHER LTS / 及 VSlice 转谱）。 */
	public function isLeatherChartFormat():Bool
	{
		return SONG.format != null && (SONG.format == 'LEATHER' || SONG.format == 'LEATHER LTS');
	}

	/** 在当前/所有模组的 data/modcharts/{path}.lua 下查找 LE modchart 脚本（先 modcharts/ 再 scripts/，对照 LE 原版）。 */
	function findLeatherModchartPath(path:String):String
	{
		#if MODS_ALLOWED
		var candidates:Array<String> = [
			'data/modcharts/' + path + '.lua',
			'scripts/' + path + '.lua'
		];
		for (c in candidates)
		{
			var p:String = Paths.modFolders(c);
			if (FileSystem.exists(p)) return p;
		}
		#end
		return null;
	}

	public var videoCutscene:VideoSprite = null;
	public function startVideo(name:String, forMidSong:Bool = false, canSkip:Bool = true, loop:Bool = false, playOnLoad:Bool = true)
	{
		#if VIDEOS_ALLOWED
		inCutscene = !forMidSong;
		canPause = forMidSong;

		var foundFile:Bool = false;
		var fileName:String = Paths.video(name);

		#if sys
		if (FileSystem.exists(fileName))
		#else
		if (OpenFlAssets.exists(fileName))
		#end
		foundFile = true;

		if (foundFile)
		{
			videoCutscene = new VideoSprite(fileName, forMidSong, canSkip, loop);
			if(forMidSong) videoCutscene.videoSprite.bitmap.rate = playbackRate;

			// Finish callback
			if (!forMidSong)
			{
				function onVideoEnd()
				{
					if (!isDead && generatedMusic && PlayState.SONG.notes[Std.int(curStep / 16)] != null && !endingSong && !isCameraOnForcedPos)
					{
						moveCameraSection();
						FlxG.camera.snapToTarget();
					}
					videoCutscene = null;
					canPause = true;
					inCutscene = false;
					startAndEnd();
				}
				videoCutscene.finishCallback = onVideoEnd;
				videoCutscene.onSkip = onVideoEnd;
			}
			if (GameOverSubstate.instance != null && isDead) GameOverSubstate.instance.add(videoCutscene);
			else add(videoCutscene);

			if (playOnLoad)
				videoCutscene.play();
			return videoCutscene;
		}
		#if (LUA_ALLOWED || HSCRIPT_ALLOWED)
		else addTextToDebug("Video not found: " + fileName, FlxColor.RED);
		#else
		else FlxG.log.error("Video not found: " + fileName);
		#end
		#else
		FlxG.log.warn('Platform not supported!');
		startAndEnd();
		#end
		return null;
	}

	function startAndEnd()
	{
		if(endingSong)
			endSong();
		else
			startCountdown();
	}

	var dialogueCount:Int = 0;
	public var psychDialogue:DialogueBoxPsych;
	//You don't have to add a song, just saying. You can just do "startDialogue(DialogueBoxPsych.parseDialogue(Paths.json(songName + '/dialogue')))" and it should load dialogue.json
	public function startDialogue(dialogueFile:DialogueFile, ?song:String = null):Void
	{
		// TO DO: Make this more flexible, maybe?
		if(psychDialogue != null) return;

		if(dialogueFile.dialogue.length > 0) {
			inCutscene = true;
			psychDialogue = new DialogueBoxPsych(dialogueFile, song);
			psychDialogue.scrollFactor.set();
			if(endingSong) {
				psychDialogue.finishThing = function() {
					psychDialogue = null;
					endSong();
				}
			} else {
				psychDialogue.finishThing = function() {
					psychDialogue = null;
					startCountdown();
				}
			}
			psychDialogue.nextDialogueThing = startNextDialogue;
			psychDialogue.skipDialogueThing = skipDialogue;
			psychDialogue.cameras = [camHUD];
			add(psychDialogue);
		} else {
			FlxG.log.warn('Your dialogue file is badly formatted!');
			startAndEnd();
		}
	}

	var startTimer:FlxTimer;
	var finishTimer:FlxTimer = null;

	// For being able to mess with the sprites on Lua
	public var countdownReady:FlxSprite;
	public var countdownSet:FlxSprite;
	public var countdownGo:FlxSprite;
	public static var startOnTime:Float = 0;

	function cacheCountdown()
	{
		var introAssets:Map<String, Array<String>> = new Map<String, Array<String>>();
		var introImagesArray:Array<String> = switch(stageUI) {
			case "pixel": ['pixelUI/ready-pixel', 'pixelUI/set-pixel', 'pixelUI/date-pixel'];
			case "normal": ["ready", "set" ,"go"];
			default: ['${uiPrefix}UI/ready${uiPostfix}', '${uiPrefix}UI/set${uiPostfix}', '${uiPrefix}UI/go${uiPostfix}'];
		}
		introAssets.set(stageUI, introImagesArray);
		var introAlts:Array<String> = introAssets.get(stageUI);
		for (asset in introAlts) Paths.image(asset);

		Paths.sound('intro3' + introSoundsSuffix);
		Paths.sound('intro2' + introSoundsSuffix);
		Paths.sound('intro1' + introSoundsSuffix);
		Paths.sound('introGo' + introSoundsSuffix);
	}

	public function startCountdown()
	{
		if(startedCountdown) {
			callOnScripts('onStartCountdown');
			return false;
		}

		seenCutscene = true;
		inCutscene = false;
		var ret:Dynamic = callOnScripts('onStartCountdown', null, true);
		if(ret != LuaUtils.Function_Stop) {
			if (skipCountdown || startOnTime > 0) skipArrowStartTween = true;

			canPause = true;
			applyMania((SONG != null && SONG.mania != null) ? SONG.mania : 3);
			generateStaticArrows(0);
			generateStaticArrows(1);
		createLaneCovers();
		createHoldCovers();

		// 开局键位预览（样式见 showKeyPreview：'ek' = EK KeybindShowcase / 'le' = LE extraKeyReminders）
		showKeyPreview();

		for (i in 0...playerStrums.length) {
				setOnScripts('defaultPlayerStrumX' + i, playerStrums.members[i].x);
				setOnScripts('defaultPlayerStrumY' + i, playerStrums.members[i].y);
			}
			for (i in 0...opponentStrums.length) {
				setOnScripts('defaultOpponentStrumX' + i, opponentStrums.members[i].x);
				setOnScripts('defaultOpponentStrumY' + i, opponentStrums.members[i].y);
				//if(ClientPrefs.data.middleScroll) opponentStrums.members[i].visible = false;
			}

			startedCountdown = true;
			Conductor.songPosition = -Conductor.crochet * 5 + Conductor.offset;
			setOnScripts('startedCountdown', true);
			callOnScripts('onCountdownStarted');

			// 创建游戏内按键显示覆盖层（复刻 JKPS 效果，跟随玩家键位）
			if (ClientPrefs.data.keyViewer && keyViewer == null)
			{
				keyViewer = new objects.KeyViewer();
				add(keyViewer);
			}

			var swagCounter:Int = 0;
			if (startOnTime > 0) {
				clearNotesBefore(startOnTime);
				setSongTime(startOnTime - 350);
				return true;
			}
			else if (skipCountdown)
			{
				setSongTime(0);
				return true;
			}
			moveCameraSection();

			startTimer = new FlxTimer().start(Conductor.crochet / 1000 / playbackRate, function(tmr:FlxTimer)
			{
				characterBopper(tmr.loopsLeft);

				var introAssets:Map<String, Array<String>> = new Map<String, Array<String>>();
				var introImagesArray:Array<String> = switch(stageUI) {
					case "pixel": ['pixelUI/ready-pixel', 'pixelUI/set-pixel', 'pixelUI/date-pixel'];
					case "normal": ["ready", "set" ,"go"];
					default: ['${uiPrefix}UI/ready${uiPostfix}', '${uiPrefix}UI/set${uiPostfix}', '${uiPrefix}UI/go${uiPostfix}'];
				}
				introAssets.set(stageUI, introImagesArray);

				var introAlts:Array<String> = introAssets.get(stageUI);
				var antialias:Bool = (ClientPrefs.data.antialiasing && !isPixelStage);
				var tick:Countdown = THREE;

				switch (swagCounter)
				{
					case 0:
						FlxG.sound.play(Paths.sound('intro3' + introSoundsSuffix), 0.6);
						tick = THREE;
					case 1:
						countdownReady = createCountdownSprite(introAlts[0], antialias);
						FlxG.sound.play(Paths.sound('intro2' + introSoundsSuffix), 0.6);
						tick = TWO;
					case 2:
						countdownSet = createCountdownSprite(introAlts[1], antialias);
						FlxG.sound.play(Paths.sound('intro1' + introSoundsSuffix), 0.6);
						tick = ONE;
					case 3:
						countdownGo = createCountdownSprite(introAlts[2], antialias);
						FlxG.sound.play(Paths.sound('introGo' + introSoundsSuffix), 0.6);
						tick = GO;
					case 4:
						tick = START;
				}

				if(!skipArrowStartTween)
				{
					notes.forEachAlive(function(note:Note) {
						if(ClientPrefs.data.opponentStrums || note.mustPress)
						{
							note.copyAlpha = false;
							note.alpha = note.multAlpha;
							if(ClientPrefs.data.middleScroll && !note.mustPress)
								note.alpha *= 0.35;
						}
					});
				}

				stagesFunc(function(stage:BaseStage) stage.countdownTick(tick, swagCounter));
				callOnLuas('onCountdownTick', [swagCounter]);
				callOnHScript('onCountdownTick', [tick, swagCounter]);

				swagCounter += 1;
			}, 5);
		}
		return true;
	}

	/**
	 * 将HUD元素加入场景。
	 * 普通模式: 加入 uiGroup (默认, 便于统一管理与缩放)。
	 * 旧版HUD模式 (ClientPrefs.data.legacyHUD): 直接加入 state 并指定 cameras = [camHUD],
	 * 以兼容依赖旧版Psych(0.6.x)结构的模组脚本 (getObjectOrder/setObjectOrder 需元素为 state 的直接成员)。
	 */
	inline private function addToHUD(obj:FlxSprite):FlxSprite
	{
		if (ClientPrefs.data.legacyHUD)
		{
			add(obj);
			obj.cameras = [camHUD];
		}
		else
			uiGroup.add(obj);
		return obj;
	}

	/**
	 * 将音符层元素(strumLineNotes/notes/grpNoteSplashes/grpHoldCovers)加入场景。
	 * 普通模式: 加入 noteGroup。
	 * 旧版HUD模式 (legacyHUD): 直接 add 进 state 并指定 cameras = [camHUD], 复刻 0.6.x 结构,
	 * 使 getObjectOrder('strumLineNotes') / getObjectOrder('notes') / members.indexOf(strumLineNotes) 可用。
	 */
	inline private function addToNoteLayer(obj:FlxBasic):FlxBasic
	{
		if (ClientPrefs.data.legacyHUD)
		{
			add(obj);
			obj.cameras = [camHUD];
		}
		else
			noteGroup.add(obj);
		return obj;
	}

	/**
	 * 将评级弹出元素(rating/comboSpr/numScore/EXrating)加入场景。
	 * 普通模式: 加入 comboGroup (逻辑回收 + 显示)。
	 * 旧版HUD模式 (legacyHUD): 不将 comboGroup 加入 state, 而是把每个元素直接 insert 进 state 的
	 * members.indexOf(strumLineNotes) 之前, 复刻 0.6.x 的 `insert(members.indexOf(strumLineNotes), rating)`,
	 * 并单独设置 cameras (由 ratingsPos 决定 camHUD/camGame)。comboGroup 仅保留为对象池回收索引。
	 */
	inline private function addToComboLayer(obj:FlxSprite):FlxSprite
	{
		if (ClientPrefs.data.legacyHUD)
		{
			// 仍登记进 comboGroup 作为逻辑索引(供 comboStacking / 对象池定位),
			// 但 comboGroup 不加入 state, 故不负责渲染。
			comboGroup.add(obj);
			obj.cameras = [ClientPrefs.data.ratingsPos == 'camHUD' ? camHUD : camGame];
			// 复刻 0.6.x: rating 直接成为 state 的成员, 插入到 strumLineNotes 之前。
			insert(members.indexOf(strumLineNotes), obj);
		}
		else
			comboGroup.add(obj);
		return obj;
	}

	/**
	 * 从显示/逻辑中移除一个评级弹出精灵。
	 * 非 legacy: 仅从 comboGroup 移除(comboGroup 在 state 中, 移除即停止渲染)。
	 * legacyHUD: comboGroup 不加入 state, 故需额外从 state.members 移除以停止渲染;
	 *            同时仍从 comboGroup 逻辑索引移除, 避免索引残留影响 comboStacking/对象池。
	 */
	inline private function removeComboSpr(spr:FlxSprite):Void
	{
		if (comboGroup != null && comboGroup.members.indexOf(spr) != -1)
			comboGroup.remove(spr, true);
		if (ClientPrefs.data.legacyHUD)
			members.remove(spr);
	}

	inline private function createCountdownSprite(image:String, antialias:Bool):FlxSprite
	{
		var spr:FlxSprite = new FlxSprite().loadGraphic(Paths.image(image));
		spr.cameras = [camHUD];
		spr.scrollFactor.set();
		spr.updateHitbox();

		if (PlayState.isPixelStage)
			spr.setGraphicSize(Std.int(spr.width * daPixelZoom));

		spr.screenCenter();
		spr.antialiasing = antialias;
		insert(ClientPrefs.data.legacyHUD ? members.indexOf(strumLineNotes) : members.indexOf(noteGroup), spr);
		FlxTween.tween(spr, {/*y: spr.y + 100,*/ alpha: 0}, Conductor.crochet / 1000, {
			ease: FlxEase.cubeInOut,
			onComplete: function(twn:FlxTween)
			{
				remove(spr);
				spr.destroy();
			}
		});
		return spr;
	}

	public function addBehindGF(obj:FlxBasic)
	{
		insert(members.indexOf(gfGroup), obj);
	}
	public function addBehindBF(obj:FlxBasic)
	{
		insert(members.indexOf(boyfriendGroup), obj);
	}
	public function addBehindDad(obj:FlxBasic)
	{
		insert(members.indexOf(dadGroup), obj);
	}

	public function clearNotesBefore(time:Float)
	{
		var i:Int = unspawnNotes.length - 1;
		while (i >= 0) {
			var daNote:Note = unspawnNotes[i];
			if(daNote.strumTime - 350 < time)
			{
				daNote.active = false;
				daNote.visible = false;
				daNote.ignoreNote = true;

				if(!ClientPrefs.data.lowQuality/* || !cpuControlled*/) daNote.kill();
				unspawnNotes.remove(daNote);
				daNote.destroy();
			}
			--i;
		}

		i = notes.length - 1;
		while (i >= 0) {
			var daNote:Note = notes.members[i];
			if(daNote != null && daNote.strumTime - 350 < time)
			{
				daNote.active = false;
				daNote.visible = false;
				daNote.ignoreNote = true;
				invalidateNote(daNote);
			}
			--i;
		}
	}

	// fun fact: Dynamic Functions can be overriden by just doing this
	// `updateScore = function(miss:Bool = false) { ... }
	// its like if it was a variable but its just a function!
	// cool right? -Crow
	public dynamic function updateScore(miss:Bool = false, scoreBop:Bool = true)
	{
		var ret:Dynamic = callOnScripts('preUpdateScore', [miss], true);
		if (ret == LuaUtils.Function_Stop)
			return;

		updateScoreText();
		if (!miss/* && !cpuControlled*/ && scoreBop)
			doScoreBop();

		callOnScripts('onUpdateScore', [miss]);
	}

	public dynamic function updateScoreText()
	{
		var lblScore:String = ScoreLanguage.get('score_label_score');
		var lblNPS:String = ScoreLanguage.get('score_label_nps');
		var lblMiss:String = ScoreLanguage.get('score_label_miss');
		var lblMisses:String = ScoreLanguage.get('score_label_misses');
		var lblAcc:String = ScoreLanguage.get('score_label_acc');
		var lblComboBreaks:String = ScoreLanguage.get('score_label_combobreaks');
		var lblAverage:String = ScoreLanguage.get('score_label_average');
		var lblAccuracy:String = ScoreLanguage.get('score_label_accuracy');
	var lblRating:String = ScoreLanguage.get('score_label_rating');

	// 预计算本地化的 ratingFC 文本（缺失时 ScoreLanguage 会回退到原始 token，保证兼容）
	var ratingFCText:String = ScoreLanguage.getRatingFC(ratingFC);
	// 评分名（ratingStuff）的展示用本地化文本；ratingName 本体仍保持英文 token，不影响判定/脚本
	var ratingNameDisp:String = ScoreLanguage.getRatingName(ratingName);

	var str:String = ratingNameDisp;
        var percent:Float = 0; // 提前声明并初始化
        if(totalPlayed != 0)
        {
            percent = CoolUtil.floorDecimal(ratingPercent * 100, 2);
            str += ' (${percent}%) - ' + ratingFCText;
        }

        var tempScore:String;
        if(!instakillOnMiss) {
            if (ClientPrefs.data.scoretxtstyle == 'Kathy')
			{
    			if (!cpuControlled || ClientPrefs.data.botplayScore)
    			{
        			tempScore = '| ';
        			if (ClientPrefs.data.showNPS)
tempScore += '${lblNPS}: ${nps} (${maxNPS}) | ';
tempScore += '${lblScore}: ${songScore}';
        			if (!instakillOnMiss)
tempScore += ' | ${lblMiss}: ${songMisses}';
tempScore += ' | ${lblAcc}: ${percent}% | ${ratingFCText} |';
    			}
    			else {
        			if (ClientPrefs.data.showNPS)
            			tempScore = '| ${lblNPS}: ${nps} (${maxNPS}) |';
        			else
            			tempScore = ''; // 不显示竖线
    			}
    			//if (cpuControlled) tempScore += ' AUTOPLAY |';
			}
            else if (ClientPrefs.data.scoretxtstyle == 'Kade')
            {
                if (!cpuControlled || ClientPrefs.data.botplayScore)
                {
                    tempScore = '';
                    if (ClientPrefs.data.showNPS)
tempScore += '${lblNPS}: ${nps} (Max: ${maxNPS}) | ';
tempScore += '${lblScore}: ${songScore}';
                    if (!instakillOnMiss)
                        tempScore += ' | ${lblComboBreaks}: ${songMisses}';
                    tempScore += ' | ${lblAccuracy}: ${percent}% | (${ratingFCText}) ${ratingNameKE}';
                } else {
                    tempScore = ClientPrefs.data.showNPS ? '${lblNPS}: ${nps} (Max: ${maxNPS})' : '';
                }
                //if (cpuControlled) tempScore += ' | BOTPLAY';
            }
			else if (ClientPrefs.data.scoretxtstyle == 'V-Slice')
            {
                    tempScore = '${lblScore}: ${songScore}';
            }
            else if (ClientPrefs.data.scoretxtstyle == 'OS')
            {
                if (!cpuControlled || ClientPrefs.data.botplayScore)
                {
                    if(ratingName == '?') {
                        tempScore = '${lblScore}: ${songScore} | ${lblComboBreaks}: ${songMisses} | ${lblAverage}: ? | ${lblAccuracy}: ${ratingNameDisp}';
                    } else {
                        var avgValue:Int = Std.int(Math.abs(Math.round(averageMs)));
                        tempScore = '${lblScore}: ${songScore} | ${lblComboBreaks}: ${songMisses} | ${lblAverage}: ${avgValue}ms | ${lblAccuracy}: ${percent}% | ${ratingNameDisp} [${ratingFCText}]';
                    }
                } else {
                    tempScore = '';
                }
            }
            else if (ClientPrefs.data.scoretxtstyle == 'Leather')
            {
                // LeatherEngine 原版格式：<  Score:${songScore} ~ Misses:${misses} ~ Accuracy:${accuracy}% ~ ${ratingStr}  >
                if (!cpuControlled || ClientPrefs.data.botplayScore)
                {
                    var leatherAcc:Float = totalPlayed != 0 ? CoolUtil.floorDecimal(ratingPercent * 100, 2) : 100.0;
                    var leatherRank:String = getLeatherRank(leatherAcc, songMisses);
                    if (!instakillOnMiss)
                        tempScore = '<  ${lblScore}: ${songScore} ~ ${lblMisses}: ${songMisses} ~ ${lblAccuracy}: ${leatherAcc}% ~ ${leatherRank}  >';
                    else
                        tempScore = '<  ${lblScore}: ${songScore} ~ ${lblAccuracy}: ${leatherAcc}% ~ ${leatherRank}  >';
                } else {
                    tempScore = '';
                }
            }
            else if (ClientPrefs.data.scoretxtstyle == 'Psych (Old)')
				{
					// PsychEngine 0.4.2 原版格式：Score: X | Misses: Y | Rating: R (P%)
					if (!cpuControlled || ClientPrefs.data.botplayScore)
					{
						if (ratingName == '?')
							tempScore = '${lblScore}: ${songScore} | ${lblMisses}: ${songMisses} | ${lblRating}: ${ratingNameDisp}';
						else
							tempScore = '${lblScore}: ${songScore} | ${lblMisses}: ${songMisses} | ${lblRating}: ${ratingNameDisp} (${Std.int(ratingPercent * 100)}%)';
					}
					else
						tempScore = '';
				}
				else if (ClientPrefs.data.scoretxtstyle == 'Forever')
				{
					// Forever Engine 格式：< Score: X • Accuracy: X% • Combo Breaks: X • Rank: X >
					if (!cpuControlled || ClientPrefs.data.botplayScore)
					{
						var foreverAcc:Float = totalPlayed != 0 ? CoolUtil.floorDecimal(ratingPercent * 100, 2) : 100.0;
						var foreverRank:String = getForeverRank(foreverAcc);
						if (!instakillOnMiss)
							tempScore = '<  ${lblScore}: ${songScore}  ${lblAccuracy}: ${foreverAcc}%  ${lblComboBreaks}: ${songMisses}  ${lblRating}: ${foreverRank}  >';
						else
							tempScore = '<  ${lblScore}: ${songScore}  ${lblAccuracy}: ${foreverAcc}%  ${lblRating}: ${foreverRank}  >';
					}
					else
						tempScore = '';
				}
			else
				tempScore = '${lblScore}: ${songScore} | ${lblMisses}: ${songMisses} | ${lblRating}: ${str}';
        }
        else {
            // instakill 模式：根据不同样式显示不同格式
            if (ClientPrefs.data.scoretxtstyle == 'Leather') {
                var leatherAcc:Float = totalPlayed != 0 ? CoolUtil.floorDecimal(ratingPercent * 100, 2) : 100.0;
                var leatherRank:String = getLeatherRank(leatherAcc);
                tempScore = '<  ${lblScore}: ${songScore} ~ ${leatherRank}  >';
            } else if (ClientPrefs.data.scoretxtstyle == 'Psych (Old)') {
                tempScore = ratingName == '?'
                    ? '${lblScore}: ${songScore} | ${lblRating}: ${ratingNameDisp}'
                    : '${lblScore}: ${songScore} | ${lblRating}: ${ratingNameDisp} (${Std.int(ratingPercent * 100)}%)';
			} else if (ClientPrefs.data.scoretxtstyle == 'Forever') {
				var foreverAcc:Float = totalPlayed != 0 ? CoolUtil.floorDecimal(ratingPercent * 100, 2) : 100.0;
				var foreverRank:String = getForeverRank(foreverAcc);
				tempScore = '<  ${lblScore}: ${songScore}  ${lblAccuracy}: ${foreverAcc}%  ${lblRating}: ${foreverRank}  >';
			} else {
				tempScore = '${lblScore}: ${songScore} | ${lblRating}: ${str}';
            }
        }
        scoreTxt.text = tempScore;
    }

	// 获取 Forever 排名（基于 accuracy 百分比）
	public function getForeverRank(accuracyPct:Float):String
	{
		if (accuracyPct >= 100) return 'S+';
		if (accuracyPct >= 95)  return 'S';
		if (accuracyPct >= 90)  return 'A';
		if (accuracyPct >= 85)  return 'B';
		if (accuracyPct >= 80)  return 'C';
		if (accuracyPct >= 75)  return 'D';
		if (accuracyPct >= 70)  return 'E';
		if (accuracyPct >= 65)  return 'F';
		return 'F';
	}

	public dynamic function fullComboFunction()
	{
		// 根据是否启用perfect来确定索引
		var perfects:Int = ClientPrefs.data.rmPerfect == 'enable' ? ratingsData[0].hits : 0;
		var sicks:Int = ClientPrefs.data.rmPerfect == 'enable' ? ratingsData[1].hits : ratingsData[0].hits;
		var goods:Int = ClientPrefs.data.rmPerfect == 'enable' ? ratingsData[2].hits : ratingsData[1].hits;
		var bads:Int = ClientPrefs.data.rmPerfect == 'enable' ? ratingsData[3].hits : ratingsData[2].hits;
		var shits:Int = ClientPrefs.data.rmPerfect == 'enable' ? ratingsData[4].hits : ratingsData[3].hits;

		//ratingFC = "";
		ratingFC = /*ClientPrefs.data.scoretxtstyle == 'Psych' ? "?" : */"?";
		if(ClientPrefs.data.scoretxtstyle == 'Kathy') ratingFC = "IDK";
			if(ClientPrefs.data.scoretxtstyle == 'Kade') ratingFC = "PFC";
			if(ClientPrefs.data.scoretxtstyle == 'OS') ratingFC = "PFC";
			if(ClientPrefs.data.scoretxtstyle == 'Forever') ratingFC = "S+";
		if(songMisses == 0)
		{
			if (bads > 0 || shits > 0) ratingFC = 'FC';
			else if (goods > 0) ratingFC = 'GFC';
			else if (sicks > 0) ratingFC = 'SFC';
			else if (perfects > 0) ratingFC = 'PFC';
		}
		else {
			if (songMisses < 10) ratingFC = 'SDCB';
			else ratingFC = 'Clear';
		}
	}

	public function getLeatherRank(accuracy:Float, ?misses:Int):String {
		var conditions:Array<Bool> = [
			accuracy == 100, // SSSS
			accuracy >= 98, // SSS
			accuracy >= 95, // SS
			accuracy >= 92, // S
			accuracy >= 89, // AA
			accuracy >= 85, // A
			accuracy >= 80, // B+
			accuracy >= 70, // B
			accuracy >= 65, // C
			accuracy >= 50, // D
			accuracy >= 10, // E
			accuracy >= 5, // F
			accuracy < 4, // G
		];
		var rankNames:Array<String> = ["SSSS", "SSS", "SS", "S", "AA", "A", "B+", "B", "C", "D", "E", "F", "G"];

		// 找到第一个满足条件的评级（原逻辑：首个为 true 即返回）
		var rankIndex:Int = rankNames.length - 1;
		for (i in 0...conditions.length) {
			if (conditions[i]) { rankIndex = i; break; }
		}

		// 计算 Leather 前缀原始 token（FC / SDB / GFC / SDG / PFC / SDP / MFC / SDCB / CLEAR）
		var prefixToken:String = '';
		if (misses != null) {
			if (misses == 0) {
				prefixToken = 'FC';

				// 根据是否启用perfect来确定索引
				var perfects:Int = ClientPrefs.data.rmPerfect == 'enable' ? ratingsData[0].hits : 0;
				var sicks:Int = ClientPrefs.data.rmPerfect == 'enable' ? ratingsData[1].hits : ratingsData[0].hits;
				var goods:Int = ClientPrefs.data.rmPerfect == 'enable' ? ratingsData[2].hits : ratingsData[1].hits;
				var bads:Int = ClientPrefs.data.rmPerfect == 'enable' ? ratingsData[3].hits : ratingsData[2].hits;
				var shits:Int = ClientPrefs.data.rmPerfect == 'enable' ? ratingsData[4].hits : ratingsData[3].hits;

				if (bads < 10 && shits == 0)
					prefixToken = 'SDB';
				if (bads == 0 && shits == 0)
					prefixToken = 'GFC';
				if (goods < 10 && bads == 0 && shits == 0)
					prefixToken = 'SDG';
				if (goods == 0 && bads == 0 && shits == 0)
					prefixToken = 'PFC';
				if (sicks < 10 && goods == 0 && bads == 0 && shits == 0)
					prefixToken = 'SDP';
				if (sicks == 0 && goods == 0 && bads == 0 && shits == 0)
					prefixToken = 'MFC';
			}
			if (misses > 0 && misses < 10)
				prefixToken = 'SDCB';
			if (misses >= 10)
				prefixToken = 'CLEAR';
		}

		// 本地化前缀与评级名（缺失时回退原始 token，保证兼容）
		var prefix:String = (prefixToken == '') ? '' : ScoreLanguage.getLeatherRankPrefix(prefixToken) + ' ~ ';
		return prefix + ScoreLanguage.getLeatherRankName(rankNames[rankIndex]);
	}

	public function doScoreBop():Void {
		if (!ClientPrefs.data.scoreZoom || ClientPrefs.data.scoretxtstyle == 'Kade' || ClientPrefs.data.scoretxtstyle == 'OS')
			return;

		if(scoreTxtTween != null)
			scoreTxtTween.cancel();
		if(scoreTxtTweenAngle != null)
			scoreTxtTweenAngle.cancel();

		scoreTxt.scale.x = 1.075;
		scoreTxt.scale.y = 1.075;
		scoreTxtTween = FlxTween.tween(scoreTxt.scale, {x: 1, y: 1}, 0.2, {
			onComplete: function(twn:FlxTween) {
				scoreTxtTween = null;
			}
		});

		if (ClientPrefs.data.scoretxtbounce) 
		{
			scoreTxt.angle = (Math.random() * 2.5) * (Math.random() > .5 ? 1 : -1);
			scoreTxtTweenAngle = FlxTween.tween(scoreTxt, {angle: 0}, ClientPrefs.data.scoretxtstyle == 'Kathy' ? 0.15 : 0.2, {
				onComplete: function (twn: FlxTween) {
					scoreTxtTweenAngle = null;
				}
			});
		}

	}

	public function setSongTime(time:Float)
	{
		FlxG.sound.music.pause();
		vocals.pause();
		opponentVocals.pause();

		FlxG.sound.music.time = time - Conductor.offset;
		#if FLX_PITCH FlxG.sound.music.pitch = playbackRate; #end
		FlxG.sound.music.play();

		if (Conductor.songPosition < vocals.length)
		{
			vocals.time = time - Conductor.offset;
			#if FLX_PITCH vocals.pitch = playbackRate; #end
			vocals.play();
		}
		else vocals.pause();

		if (Conductor.songPosition < opponentVocals.length)
		{
			opponentVocals.time = time - Conductor.offset;
			#if FLX_PITCH opponentVocals.pitch = playbackRate; #end
			opponentVocals.play();
		}
		else opponentVocals.pause();
		Conductor.songPosition = time;
	}

	public function startNextDialogue() {
		dialogueCount++;
		callOnScripts('onNextDialogue', [dialogueCount]);
	}

	public function skipDialogue() {
		callOnScripts('onSkipDialogue', [dialogueCount]);
	}

	function startSong():Void
	{
		startingSong = false;

		// A3: onEndCountdown — Ready-Set-Go 全部播完，正式开唱前
		callOnScripts('onEndCountdown');

		@:privateAccess
		FlxG.sound.playMusic(inst._sound, 1, false);
		#if FLX_PITCH FlxG.sound.music.pitch = playbackRate; #end
		FlxG.sound.music.onComplete = finishSong.bind();
		vocals.play();
		opponentVocals.play();

		setSongTime(Math.max(0, startOnTime - 500) + Conductor.offset);
		startOnTime = 0;

		if(paused) {
			//trace('Oopsie doopsie! Paused sound');
			FlxG.sound.music.pause();
			vocals.pause();
			opponentVocals.pause();
		}

		stagesFunc(function(stage:BaseStage) stage.startSong());

		// Song duration in a float, useful for the time left feature
		songLength = FlxG.sound.music.length;
		FlxTween.tween(timeBar, {alpha: 1}, 0.5, {ease: FlxEase.circOut});
		FlxTween.tween(timeTxt, {alpha: 1}, 0.5, {ease: FlxEase.circOut});

		#if DISCORD_ALLOWED
		// Updating Discord Rich Presence (with Time Left)
		if(autoUpdateRPC) DiscordClient.changePresence(detailsText, SONG.song + " (" + storyDifficultyText + ")", iconP2.getCharacter(), true, songLength);
		#end
		setOnScripts('songLength', songLength);
		callOnScripts('onSongStart');

		runSongSyncThread();
	}

	private var noteTypes:Array<String> = [];
	// LE LTS 双侧：玩家侧运行时键数（change keycount 改键后更新；StrumNote/Note 等按侧取档位需要公开访问）
	public var totalColumns: Int = 4;
	private var diagFrame:Int = 0; // 错位诊断计数

	private function generateSong():Void
	{
		// FlxG.log.add(ChartParser.parse());
		songSpeed = PlayState.SONG.speed;

		// Extra Keys：在解析谱面前先按歌曲 mania 档位配置好列数/颜色/键位，
		// 否则下面 generateSongLegacy/Optimized 里的 sectCols 会按 4 键硬解析多键谱面。
		// LE LTS 双侧模式（谱面含 playerKeyCount 且 != keyCount）：玩家侧/对手侧各按独立 EK 档位配置；
		// 非双侧模式对手侧恒等于玩家侧（isLeDualChart=false）。
		isLeDualChart = (SONG != null && SONG.playerKeyCount != null && SONG.keyCount != null && SONG.playerKeyCount != SONG.keyCount);
		if (isLeDualChart)
		{
			applyMania((SONG.playerKeyCount - 1));
			applyOpponentMania((SONG.keyCount - 1));
			// 双侧模式：两侧 strum/音符按各自键数与中心独立缩放（computeMultiKeyStrumScale 内按侧计算）
			if (totalColumns > 4 || opponentColumns > 4) computeMultiKeyStrumScale();
		}
		else
		{
			applyMania((SONG != null && SONG.mania != null) ? SONG.mania : 3);
		}

		songSpeedType = ClientPrefs.getGameplaySetting('scrolltype');
		switch(songSpeedType)
		{
			case "multiplicative":
				songSpeed = SONG.speed * ClientPrefs.getGameplaySetting('scrollspeed');
			case "constant":
				songSpeed = ClientPrefs.getGameplaySetting('scrollspeed');
		}

		var songData = SONG;
		Conductor.bpm = songData.bpm;

		curSong = songData.song;

		vocals = new FlxSound();
		opponentVocals = new FlxSound();
		// 让音频从真正包含该歌曲的模组目录解析，避免模组沿用 funkin 曲名时误加载 funkin 内置资源。
		// 部分模组没有 runsGlobally，只能经由 Mods.currentModDirectory 访问；若 .folder 登记有误或被
		// loadTopMod 重置，这里直接在所有“真实存在的模组目录”中搜索实际包含该歌曲音频的模组。
		var prevModDir:String = Mods.currentModDirectory;


		// 用 loadSongAudio（不回退 funkin）判定该模组是否真有这首曲子的音频，避免被原生同名资源误导。
		function modHasAudio(mod:String, song:String, fileBase:String):Bool
		{
			// mod 为空 => 内置 base_game，绝不被原生同名资源误导（loadSongAudio 空 modDir 即查 assets/songs）。
			return Paths.loadSongAudio(song, fileBase, mod) != null;
		}

		// 探测某 mod 是否含有该曲音频：含 SpecialInst/SpecialVocal 的带后缀文件也算（与 ChartingState/FreeplayState 一致）。
		function modHasSong(mod:String, song:String):Bool
		{
			var si:String = (songData.specialInst != null && songData.specialInst.length > 0) ? songData.specialInst : null;
			var sv:String = (songData.specialVocal != null && songData.specialVocal.length > 0) ? songData.specialVocal : null;
			if (modHasAudio(mod, song, 'Inst') || modHasAudio(mod, song, 'Voices')) return true;
			if (si != null && modHasAudio(mod, song, 'Inst-${si}')) return true;
			if (sv != null && modHasAudio(mod, song, 'Voices-${sv}')) return true;
			return false;
		}

		var audioModDir:String = PlayState._lastLoadedModDirectory;
		if (PlayState._songAudioModCache != null && PlayState._songAudioModCache.exists(songData.song))
		{
			audioModDir = PlayState._songAudioModCache.get(songData.song);
		}
		else
		{
			if (!modHasSong(audioModDir, songData.song))
			{
				audioModDir = '';
				#if MODS_ALLOWED
				for (mod in Mods.getModDirectories())
				{
					if (modHasSong(mod, songData.song))
					{
						audioModDir = mod;
						break;
					}
				}
				#end
			}
			if (audioModDir == null) audioModDir = '';
			if (PlayState._songAudioModCache == null) PlayState._songAudioModCache = new Map();
			PlayState._songAudioModCache.set(songData.song, audioModDir);
		}

		Mods.currentModDirectory = audioModDir;
		try
		{
			if (songData.needsVoices)
			{
				// Inst 与人声统一从 audioModDir 加载（loadSongAudio 不回退 funkin，缺失即 null）。
				// 优先：角色指定(postfix) > Voices-Player / Voices-Opponent > 无后缀合并 Voices
				function tryVoices(postfix:String):Sound
				{
					var fileBase:String = 'Voices';
					if (postfix != null) fileBase += '-' + postfix;
					// 追加 SpecialVocal 后缀，与 Inst 的 specialInst 对称：
					// 优先 Voices-{角色}-SpecialVocal > Voices-Player/Opponent-SpecialVocal > Voices-SpecialVocal，命中即止（任一存在即可）。
					if (songData.specialVocal != null && songData.specialVocal.length > 0)
						fileBase += '-' + songData.specialVocal;
					return Paths.loadSongAudio(songData.song, fileBase, audioModDir);
				}

				var playerVocalPostfix = (boyfriend.vocalsFile == null || boyfriend.vocalsFile.length < 1) ? boyfriend.curCharacter : boyfriend.vocalsFile;
				var playerVocals:Sound = tryVoices(playerVocalPostfix);
				if (playerVocals == null) playerVocals = tryVoices('Player');
				if (playerVocals == null) playerVocals = tryVoices(null);
				if (playerVocals != null && playerVocals.length > 0) vocals.loadEmbedded(playerVocals);

				var oppVocalPostfix = (dad.vocalsFile == null || dad.vocalsFile.length < 1) ? dad.curCharacter : dad.vocalsFile;
				var oppVocals:Sound = tryVoices(oppVocalPostfix);
				if (oppVocals == null) oppVocals = tryVoices('Opponent');
				if (oppVocals == null) oppVocals = tryVoices(null);
				if (oppVocals != null && oppVocals.length > 0) opponentVocals.loadEmbedded(oppVocals);
			}
		}
		catch (e:Dynamic) {}

		#if FLX_PITCH
		vocals.pitch = playbackRate;
		opponentVocals.pitch = playbackRate;
		#end
		FlxG.sound.list.add(vocals);
		FlxG.sound.list.add(opponentVocals);

		inst = new FlxSound();
		try
		{
			var instFileBase:String = (songData.specialInst != null && songData.specialInst.length > 0) ? 'Inst-${songData.specialInst}' : 'Inst';
			inst.loadEmbedded(Paths.loadSongAudio(songData.song, instFileBase, audioModDir));
		}
		catch (e:Dynamic) {}
		FlxG.sound.list.add(inst);

		Mods.currentModDirectory = prevModDir;

		notes = new FlxTypedGroup<Note>(); // 主组（用于 modchart 兼容性）
		normalNotes = new FlxTypedGroup<Note>(); // 普通音符组
		holdNotes = new FlxTypedGroup<Note>(); // Hold notes 组
		
		// 只有当 holdNoteBehind 为 false 时，才将主 notes 组添加到 noteGroup
		// 当 holdNoteBehind 为 true 时，我们单独添加 normalNotes 和 holdNotes
		if (!ClientPrefs.data.holdNoteBehind) {
			addToNoteLayer(notes);
		}

		// 重置优化音符加载的跟踪数组
		unspawnNotesPreloaded = [];
		spawnedNotes = [];
		notesAddedCount = 0;
		// 切歌时清空对象池：旧曲的 Note 实例帧已绑定旧皮肤，跨曲复用会导致皮肤错乱。
		notePool.clear();
		// 切歌时统一清空皮肤探测缓存（替代原每音符销毁时清空，避免高密度谱数十万次文件系统 stat）
		Note.resetNoteSkinCache();

		try
		{
			var eventsChart:SwagSong = null;
			
			// 如果设置了 specialEvents，只尝试加载对应的 events 文件（不回退到普通 events.json）
			if(songData.specialEvents != null && songData.specialEvents.length > 0)
			{
				try
				{
					eventsChart = Song.getChart('events-' + songData.specialEvents, songName);
				}
				catch(e:Dynamic) {}
			}
			else
			{
				// 如果 specialEvents 为空，尝试加载普通 events 文件
				try
				{
					eventsChart = Song.getChart('events', songName);
				}
				catch(e:Dynamic) {}
			}
			
			if(eventsChart != null && eventsChart.events != null)
				for (event in eventsChart.events) //Event Notes
					if (event != null && event[1] != null)
						for (i in 0...event[1].length)
							makeEvent(event, i);
		}
		catch(e:Dynamic) {}

		var oldNote:Note = null;
		var sectionsData:Array<SwagSection> = PlayState.SONG.notes;
		var ghostNotesCaught:Int = 0;
		var daBpm:Float = Conductor.bpm;

		// 根据设置选择加载方式：OFF / ON / AUTO
		useOptimizedLoading = false;
		var setting:String = ClientPrefs.data.useOptimizedNoteLoading;
		if (setting == null) setting = 'AUTO';
		if (setting.toUpperCase() == 'ON')
		{
			useOptimizedLoading = true;
			trace('[OptimizedNoteLoading] setting=ON → force OPTIMIZED (deferred note creation)');
		}
		else if (setting.toUpperCase() == 'AUTO')
		{
			useOptimizedLoading = shouldUseOptimizedLoading(sectionsData, songLength);
			trace('[OptimizedNoteLoading] setting=AUTO to ' + (useOptimizedLoading ? 'OPTIMIZED' : 'LEGACY'));
		}
		else
		{
			useOptimizedLoading = false;
			trace('[OptimizedNoteLoading] setting=OFF → LEGACY (eager note creation)');
		}

		if (isLeDualChart) {
			// LE LTS 双侧模式：独立 LE 解析路径（mustHit 段连续编号 + change keycount 事件时间点推进键数）
			generateSongLeDual(sectionsData, daBpm, oldNote, ghostNotesCaught);
		} else if (useOptimizedLoading) {
			// 优化模式：暂存音符对象，延迟添加到游戏世界
			generateSongOptimized(sectionsData, daBpm, oldNote, ghostNotesCaught);
		} else {
			// 传统模式：原来的逻辑
			generateSongLegacy(sectionsData, daBpm, oldNote, ghostNotesCaught);
		}
	
		if (songData.events != null) //Event Notes（防御：psych_v1 谱面可能无 events 字段，避免 Null Object Reference 崩溃）
			for (event in songData.events)
				if (event != null && event[1] != null)
					for (i in 0...event[1].length)
						makeEvent(event, i);

		if (useOptimizedLoading) {
			// 优化模式：保持原来的顺序，不排序
			generatedMusic = true;
		} else {
			unspawnNotes.sort(sortByTime);
			generatedMusic = true;
		}
	}

	/**
	 * 自动检测：统计有效箭头总数（玩家+对手），除以歌曲秒数计算 notesPerSecond，达到 100 及以上返回 true
	 * 如果 music.length 还没加载好，用最后一个箭头的 strumTime 作为估算时长
	 */
	private function shouldUseOptimizedLoading(sectionsData:Array<SwagSection>, msLen:Float):Bool
	{
		var totalNotes:Int = 0;
		var totalSections:Int = 0;
		var lastStrumTimeMs:Float = 0;

		if (sectionsData != null)
		{
			for (i in 0...sectionsData.length)
			{
				var section:Dynamic = sectionsData[i];
				if (section == null) continue;
				totalSections++;
				var notes:Array<Dynamic> = Reflect.field(section, 'sectionNotes');
				if (notes == null) continue;
				totalNotes += notes.length;
				for (j in 0...notes.length)
				{
					var noteArr:Array<Dynamic> = notes[j];
					if (noteArr == null || noteArr.length < 1) continue;
					var t:Float = Std.parseFloat(Std.string(noteArr[0]));
					if (!Math.isNaN(t) && t > lastStrumTimeMs)
						lastStrumTimeMs = t;
				}
			}
		}

		var seconds:Float = 0;
		var lenSource:String = 'music.length';
		if (msLen > 0)
			seconds = msLen / 1000.0;
		else if (lastStrumTimeMs > 0)
		{
			// 音乐还没加载好时，用最后一个箭头的 strumTime 估算，加 2 秒缓冲
			seconds = (lastStrumTimeMs + 2000.0) / 1000.0;
			lenSource = 'lastStrumTime(+2s pad)';
		}

		if (seconds <= 0)
		{
			trace('[OptimizedNoteLoading] sections=$totalSections totalNotes=$totalNotes no duration available → LEGACY');
			return false;
		}

		var notesPerSecond:Float = totalNotes / seconds;
		trace('[OptimizedNoteLoading] sections=$totalSections totalNotes=$totalNotes seconds=$seconds($lenSource) notesPerSecond=$notesPerSecond threshold(1w)=100 threshold(1w>)=50');
		return notesPerSecond >= 100 || (totalNotes > 10000 && notesPerSecond > 50);
	}

	/**
	 * 传统音符生成方式 - 与原来完全一致
	 */
	private function generateSongLegacy(sectionsData:Array<SwagSection>, daBpm:Float, oldNote:Note, ghostNotesCaught:Int):Void {
		// 使用 Map 做 O(1) 查找替代 O(n) 线性扫描检测 Ghost Note
		// 注意：存"音符引用"而非"数组下标"，否则 remove 后下标失效会越界崩溃
		var ghostNoteMap:Map<String, Note> = new Map();

		for (section in sectionsData)
		{
			if (section.changeBPM != null && section.changeBPM && section.bpm != null && daBpm != section.bpm)
				daBpm = section.bpm;

			// 小节列数（回退原生4键：固定4列，按4取模）
			var sectCols:Int = totalColumns;

			// 防御：个别 section 可能缺 sectionNotes 字段，避免 Null Object Reference 崩溃
			if (section.sectionNotes == null)
				continue;

			for (i in 0...section.sectionNotes.length)
			{
				final songNotes: Array<Dynamic> = section.sectionNotes[i];
				var spawnTime: Float = songNotes[0];
				var rawColumn:Int = Std.int(songNotes[1]);
				var noteColumn: Int = rawColumn % sectCols;
				var holdLength: Float = songNotes[2];
				// Leather 谱面音符：[time, data, length, 0, "type"]——第 4 位是数字占位，type 在第 5 位。
				// Psych 谱面：[time, data, length, "type"]——type 在第 4 位。按谱面 format 分流解析，
				// 否则 LE 的 Fireworks/XPbottle 等箭头类型会全被读成 ''（defaultNoteTypes[0]）。
				var isLeatherNoteType:Bool = isLeatherChartFormat();
				var noteType: String;
				if (isLeatherNoteType && songNotes.length > 4 && Std.isOfType(songNotes[4], String))
					noteType = songNotes[4];
				else
					noteType = !Std.isOfType(songNotes[3], String) ? Note.defaultNoteTypes[songNotes[3]] : songNotes[3];
				if (Math.isNaN(holdLength))
					holdLength = 0.0;

				var gottaHitNote:Bool = (rawColumn < sectCols);

				if (i != 0) {
					// CLEAR ANY POSSIBLE GHOST NOTES — O(1) Map查找替代 O(n) 线性扫描
					var ghostKey:String = '${noteColumn}_${gottaHitNote}_${noteType}_$spawnTime';
					if (ghostNoteMap.exists(ghostKey))
					{
						var evilNote:Note = ghostNoteMap.get(ghostKey);
						if (evilNote.tail.length > 0)
							for (tail in evilNote.tail)
							{
								tail.destroy();
								unspawnNotes.remove(tail);
							}
						evilNote.destroy();
						unspawnNotes.remove(evilNote);
						ghostNotesCaught++;
					}
				}

			var swagNote:Note = new Note(spawnTime, noteColumn, oldNote);
			// 存储原始谱面列号（4 键下等于 noteColumn），供需要时重映射 noteData。
			swagNote.noteColumnRaw = Std.int(songNotes[1]);
			swagNote.noteData = noteColumn;

			var isAlt: Bool = section.altAnim && !gottaHitNote;
			swagNote.gfNote = (section.gfSection && gottaHitNote == section.mustHitSection);
			swagNote.animSuffix = isAlt ? "-alt" : "";
			// playOpponent：只反转判定归属（谁来打），演出相关字段(gfNote/animSuffix/位置)仍按原谱面
			swagNote.mustPress = gottaHitNote;
			swagNote.sustainLength = holdLength;
			swagNote.noteType = noteType;
	
				swagNote.scrollFactor.set();
				unspawnNotes.push(swagNote);
				// 注册到 Ghost Note 查找 Map（用于后续检测重复音符），存引用避免下标失效
				ghostNoteMap.set('${noteColumn}_${gottaHitNote}_${noteType}_$spawnTime', swagNote);

				var curStepCrochet:Float = 60 / daBpm * 1000 / 4.0;
				final roundSus:Int = Math.round(swagNote.sustainLength / curStepCrochet);
				if(roundSus > 0)
				{
					for (susNote in 0...roundSus)
					{
						oldNote = unspawnNotes[Std.int(unspawnNotes.length - 1)];

					var sustainNote:Note = new Note(spawnTime + (curStepCrochet * susNote), noteColumn, oldNote, true);
					sustainNote.animSuffix = swagNote.animSuffix;
					sustainNote.mustPress = swagNote.mustPress;
					sustainNote.gfNote = swagNote.gfNote;
					sustainNote.noteType = swagNote.noteType;
					sustainNote.noteColumnRaw = swagNote.noteColumnRaw;
					sustainNote.noteData = swagNote.noteData;
						sustainNote.scrollFactor.set();
						sustainNote.parent = swagNote;
						unspawnNotes.push(sustainNote);
						swagNote.tail.push(sustainNote);

						sustainNote.correctionOffset = swagNote.height / 2;
						if(!PlayState.isPixelStage)
						{
							if(oldNote.isSustainNote)
							{
								oldNote.scale.y *= Note.SUSTAIN_SIZE / oldNote.frameHeight * Note.kadeHoldGapScale();
								oldNote.scale.y /= playbackRate;
								oldNote.resizeByRatio(curStepCrochet / Conductor.stepCrochet);
							}

							if(ClientPrefs.data.downScroll)
								sustainNote.correctionOffset = 0;
						}
						else if(oldNote.isSustainNote)
						{
							oldNote.scale.y /= playbackRate;
							oldNote.resizeByRatio(curStepCrochet / Conductor.stepCrochet);
						}

						// Extra Keys：多键下 sustain 与 strum 同布局（按布局风格取间距/组左缘）
						if (totalColumns > 4) {
							var susSpacing:Float = sideSpacing(totalColumns, strumScale);
							sustainNote.x = sideGroupLeftX(totalColumns, susSpacing, sustainNote.mustPress) + susSpacing * sustainNote.noteData;
						} else if (gottaHitNote) sustainNote.x += FlxG.width / 2; // general offset（按演出侧摆放）
						else if(ClientPrefs.data.middleScroll)
						{
							sustainNote.x += 310;
							if(noteColumn > 1) //Up and Right
								sustainNote.x += FlxG.width / 2 + 25;
						}
					}

					// 尾条判定优化：修正最后一个 tail 子音符的判定时机
					var lastTailNote:Note = swagNote.tail[swagNote.tail.length - 1];
					var useExtendFix:Bool = (sustainTailFixMode == 'extend' || sustainTailFixMode == 'both');
					var useEarlyHitFix:Bool = (sustainTailFixMode == 'earlyHit' || sustainTailFixMode == 'both');
					if(useExtendFix)
					{
						// 方案A：把最后一个 tail 的判定点延伸到"可见尾部"结束处（+noteOffset 与 Note 构造保持一致）
						lastTailNote.strumTime = spawnTime + swagNote.sustainLength + ClientPrefs.data.noteOffset;
					}
					if(useEarlyHitFix)
					{
						// 方案B：放宽最后一个 tail 的提前命中窗口
						lastTailNote.earlyHitMult = 1;
					}
				}

				// Extra Keys：多键下普通音符与 strum 同布局（按布局风格取间距/组左缘）
				if (totalColumns > 4) {
					var noteSpacing:Float = sideSpacing(totalColumns, strumScale);
					swagNote.x = sideGroupLeftX(totalColumns, noteSpacing, gottaHitNote) + noteSpacing * noteColumn;
				} else if (gottaHitNote)
				{
					swagNote.x += FlxG.width / 2; // general offset（按演出侧摆放）
				}
				else if(ClientPrefs.data.middleScroll)
				{
					swagNote.x += 310;
					if(noteColumn > 1) //Up and Right
					{
						swagNote.x += FlxG.width / 2 + 25;
					}
				}
				if(!noteTypes.contains(swagNote.noteType))
					noteTypes.push(swagNote.noteType);

				oldNote = swagNote;
			}
		}
		trace('["${SONG.song.toUpperCase()}" CHART INFO]: Ghost Notes Cleared: $ghostNotesCaught');
	}

	// —— LE LTS 双侧模式解析（跟随 EK 配置化结构：按侧独立键数；逻辑参考 LE：连续编号 noteData + change keycount 事件实时推进）——
	// 仅 isLeDualChart（谱面含 playerKeyCount 且 != keyCount）时由 generateSong 分流调用。
	// 谱面 noteData 为 LE 连续编号：mustHit 小节 0..plr-1 = 玩家、plr..plr+opp-1 = 对手；
	// 非 mustHit 小节 0..opp-1 = 对手、opp..opp+plr-1 = 玩家。
	// change keycount 事件（value1=玩家键数、value2=对手键数）按时间点实时切换两侧键数；
	// 音符按生成时刻固化"侧内列"（不随后续事件二次取模），直接生成 Note 对象（legacy 式，x 按侧居中）。
	private function generateSongLeDual(sectionsData:Array<SwagSection>, daBpm:Float, oldNote:Note, ghostNotesCaught:Int):Void
	{
		// 预扫描 change keycount 事件（SONG.events 由 Song.getChart 合并 events.json 而来，可能为空）
		var maniaChanges:Array<Array<Dynamic>> = [];
		if (SONG.events != null)
			for (event in SONG.events)
				if (event != null && event[1] != null)
					for (i in 0...event[1].length)
					{
						var ev:Array<Dynamic> = event[1][i];
						if (ev != null && ev.length >= 4 && Std.string(ev[1]).toLowerCase() == 'change keycount')
							maniaChanges.push([Std.parseFloat(Std.string(ev[0])), Std.parseInt(Std.string(ev[2])), Std.parseInt(Std.string(ev[3]))]);
					}
		maniaChanges.sort(function(a:Array<Dynamic>, b:Array<Dynamic>):Int { return (a[0] < b[0]) ? -1 : ((a[0] > b[0]) ? 1 : 0); });
		var mcIndex:Int = 0;

		// 去重查找表（与 generateSongLegacy 同构）
		var ghostNoteMap:Map<String, Note> = new Map();

		var curPlr:Int = (SONG.playerKeyCount != null) ? SONG.playerKeyCount : 4; // 玩家侧当前键数
		var curOpp:Int = (SONG.keyCount != null) ? SONG.keyCount : 4;             // 对手侧当前键数

		trace('["${SONG.song.toUpperCase()}" CHART INFO]: LE LTS dual-keycount loading (player=${SONG.playerKeyCount}K opponent=${SONG.keyCount}K)');

		for (section in sectionsData)
		{
			if (section.changeBPM != null && section.changeBPM && section.bpm != null && daBpm != section.bpm)
				daBpm = section.bpm;

			// 按本小节首个音符时间推进 change keycount 事件（LE：事件在时间轴上生效）；
			// 空小节无音符不推进（下一有音符小节会推进）
			var sectionStartTime:Float = (section.sectionNotes != null && section.sectionNotes.length > 0)
				? Std.parseFloat(Std.string(section.sectionNotes[0][0])) : 0.0;
			while (mcIndex < maniaChanges.length && maniaChanges[mcIndex][0] <= sectionStartTime)
			{
				curPlr = maniaChanges[mcIndex][1];
				curOpp = maniaChanges[mcIndex][2];
				trace('[LE DUAL] change keycount @${maniaChanges[mcIndex][0]}ms -> player=${curPlr}K opponent=${curOpp}K');
				mcIndex++;
			}

			if (section.sectionNotes == null) continue;

			var sectionMustHit:Bool = section.mustHitSection;

			for (i in 0...section.sectionNotes.length)
			{
				final songNotes:Array<Dynamic> = section.sectionNotes[i];
				var spawnTime:Float = songNotes[0];
				var rawColumn:Int = Std.int(songNotes[1]);
				var holdLength:Float = songNotes[2];
				// Leather 谱面音符：[time, data, length, 0, "type"]——type 在第 5 位；Psych 在第 4 位。
				var noteType:String;
				if (songNotes.length > 4 && Std.isOfType(songNotes[4], String))
					noteType = songNotes[4];
				else
					noteType = !Std.isOfType(songNotes[3], String) ? Note.defaultNoteTypes[songNotes[3]] : songNotes[3];
				if (Math.isNaN(holdLength)) holdLength = 0.0;

				// LE 连续编号 → mustPress + 侧内列（按小节归属 + 当前两侧键数；取模防御越界）
				var mustPress:Bool;
				var noteColumn:Int;
				if (sectionMustHit)
				{
					mustPress = rawColumn < curPlr;
					noteColumn = mustPress ? (rawColumn % curPlr) : ((rawColumn - curPlr) % curOpp);
				}
				else
				{
					mustPress = rawColumn >= curOpp;
					noteColumn = mustPress ? ((rawColumn - curOpp) % curPlr) : (rawColumn % curOpp);
				}

				if (i != 0) {
					// CLEAR ANY POSSIBLE GHOST NOTES（与 legacy 一致）
					var ghostKey:String = '${noteColumn}_${mustPress}_${noteType}_$spawnTime';
					if (ghostNoteMap.exists(ghostKey))
					{
						var evilNote:Note = ghostNoteMap.get(ghostKey);
						if (evilNote.tail.length > 0)
							for (tail in evilNote.tail)
							{
								tail.destroy();
								unspawnNotes.remove(tail);
							}
						evilNote.destroy();
						unspawnNotes.remove(evilNote);
						ghostNotesCaught++;
					}
				}

				// 修正构造时缩放所依据的生成侧：先写 currentSideMustPress 再 new Note
				// （构造阶段 mustPress 尚未赋值，Note 的 loadNoteAnims 依此按侧缩放）
				if (PlayState.instance.isLeDualChart)
					PlayState.instance.currentSideMustPress = mustPress;
				var swagNote:Note = new Note(spawnTime, noteColumn, oldNote);
				// 保留原始 LE 连续编号（供需要时重映射）
				swagNote.noteColumnRaw = rawColumn;
				swagNote.noteData = noteColumn;

				var isAlt:Bool = section.altAnim && !mustPress;
				swagNote.gfNote = (section.gfSection && mustPress == sectionMustHit);
				swagNote.animSuffix = isAlt ? "-alt" : "";
				swagNote.mustPress = mustPress;
				// LE LTS 双侧：两侧音符都绑定生成时刻的列配色/动画数组并立即刷新——
				// 对手侧=opponentColArray、玩家侧=Note.colArray（当时全局引用）；同时记录生成时档位，
				// 供 change keycount 改键折叠后更新。绑定的是数组引用：applyMania/applyOpponentMania
				// 会新建数组，改键时 remapNote 会换成新档，未改键前保持区间档（LE 语义）。
				if (PlayState.instance.isLeDualChart)
				{
					swagNote.noteColArray = mustPress ? Note.colArray : PlayState.instance.opponentColArray;
					swagNote.genMania = curPlr - 1;
					swagNote.genOppMania = curOpp - 1;
					swagNote.refreshNoteVisual();
				}
				swagNote.sustainLength = holdLength;
				swagNote.noteType = noteType;

				swagNote.scrollFactor.set();
				unspawnNotes.push(swagNote);
				ghostNoteMap.set('${noteColumn}_${mustPress}_${noteType}_$spawnTime', swagNote);

				// 双侧 x 布局：按 mustPress 侧 + 该侧当前键数排布，间距按布局风格与该侧 strumScale（LE LTS 双侧：两侧独立缩放）
				var sideCols:Int = mustPress ? curPlr : curOpp;
				var sideScale:Float = mustPress ? playerStrumScale : opponentStrumScale;
				var noteSpacing:Float = sideSpacing(sideCols, sideScale);
				var groupLeftX:Float = sideGroupLeftX(sideCols, noteSpacing, mustPress);
				if (sideCols == 4)
				{
					if (mustPress) swagNote.x += FlxG.width / 2;
					else if (ClientPrefs.data.middleScroll)
					{
						swagNote.x += 310;
						if (noteColumn > 1) swagNote.x += FlxG.width / 2 + 25;
					}
				}
				else swagNote.x = groupLeftX + noteSpacing * noteColumn;

				var curStepCrochet:Float = 60 / daBpm * 1000 / 4.0;
				final roundSus:Int = Math.round(swagNote.sustainLength / curStepCrochet);
				if (roundSus > 0)
				{
					for (susNote in 0...roundSus)
					{
						oldNote = unspawnNotes[Std.int(unspawnNotes.length - 1)];

						// 长条构造同样按当前侧缩放（构造阶段 mustPress 未赋值）
						if (PlayState.instance.isLeDualChart)
							PlayState.instance.currentSideMustPress = mustPress;
						var sustainNote:Note = new Note(spawnTime + (curStepCrochet * susNote), noteColumn, oldNote, true);
						sustainNote.animSuffix = swagNote.animSuffix;
						sustainNote.mustPress = swagNote.mustPress;
						sustainNote.gfNote = swagNote.gfNote;
						sustainNote.noteType = swagNote.noteType;
						sustainNote.noteColumnRaw = swagNote.noteColumnRaw;
						sustainNote.noteData = swagNote.noteData;
						// LE LTS 双侧：两侧长条都绑定生成时刻的列配色并刷新（玩家=Note.colArray、对手=opponentColArray，含前驱 head 的 hold 动画）
						if (PlayState.instance.isLeDualChart)
						{
							sustainNote.noteColArray = swagNote.mustPress ? Note.colArray : PlayState.instance.opponentColArray;
							sustainNote.genMania = swagNote.genMania;
							sustainNote.genOppMania = swagNote.genOppMania;
							sustainNote.refreshNoteVisual();
						}
						sustainNote.scrollFactor.set();
						sustainNote.parent = swagNote;
						unspawnNotes.push(sustainNote);
						swagNote.tail.push(sustainNote);

						sustainNote.correctionOffset = swagNote.height / 2;
						if (!PlayState.isPixelStage)
						{
							if (oldNote.isSustainNote)
							{
								oldNote.scale.y *= Note.SUSTAIN_SIZE / oldNote.frameHeight * Note.kadeHoldGapScale();
								oldNote.scale.y /= playbackRate;
								oldNote.resizeByRatio(curStepCrochet / Conductor.stepCrochet);
							}
							if (ClientPrefs.data.downScroll) sustainNote.correctionOffset = 0;
						}
						else if (oldNote.isSustainNote)
						{
							oldNote.scale.y /= playbackRate;
							oldNote.resizeByRatio(curStepCrochet / Conductor.stepCrochet);
						}

						if (sideCols == 4)
						{
							if (mustPress) sustainNote.x += FlxG.width / 2;
							else if (ClientPrefs.data.middleScroll)
							{
								sustainNote.x += 310;
								if (noteColumn > 1) sustainNote.x += FlxG.width / 2 + 25;
							}
						}
						else sustainNote.x = groupLeftX + noteSpacing * sustainNote.noteData;
					}

					// 尾条判定优化（同 legacy）
					var lastTailNote:Note = swagNote.tail[swagNote.tail.length - 1];
					if (sustainTailFixMode == 'extend' || sustainTailFixMode == 'both')
						lastTailNote.strumTime = spawnTime + swagNote.sustainLength + ClientPrefs.data.noteOffset;
					if (sustainTailFixMode == 'earlyHit' || sustainTailFixMode == 'both')
						lastTailNote.earlyHitMult = 1;
				}

				if (!noteTypes.contains(swagNote.noteType))
					noteTypes.push(swagNote.noteType);

				oldNote = swagNote;
			}
		}
		trace('["${SONG.song.toUpperCase()}" CHART INFO]: Ghost Notes Cleared: $ghostNotesCaught');
	}
	private function generateSongOptimized(sectionsData:Array<SwagSection>, daBpm:Float, oldNote:Note, ghostNotesCaught:Int):Void {
		unspawnNotesPreloaded = [];
		spawnedNotes = [];
		notesAddedCount = 0;
		trace('["${SONG.song.toUpperCase()}" CHART INFO]: Using Optimized Note Loading');
		
		var previousNoteIndex:Int = -1;
		
		for (section in sectionsData)
		{
			if (section.changeBPM != null && section.changeBPM && section.bpm != null && daBpm != section.bpm)
				daBpm = section.bpm;

			// 小节列数（回退原生4键：固定4列，按4取模）
			var sectCols:Int = totalColumns;

			// 防御：个别 section 可能缺 sectionNotes 字段，避免 Null Object Reference 崩溃
			if (section.sectionNotes == null)
				continue;

			for (i in 0...section.sectionNotes.length)
			{
				final songNotes: Array<Dynamic> = section.sectionNotes[i];
				var spawnTime: Float = songNotes[0];
				var rawColumn:Int = Std.int(songNotes[1]);
				var noteColumn: Int = rawColumn % sectCols;
				var holdLength: Float = songNotes[2];
				// Leather 谱面音符：[time, data, length, 0, "type"]——第 4 位是数字占位，type 在第 5 位。
				// Psych 谱面：[time, data, length, "type"]——type 在第 4 位。按谱面 format 分流解析，
				// 否则 LE 的 Fireworks/XPbottle 等箭头类型会全被读成 ''（defaultNoteTypes[0]）。
				var isLeatherNoteType:Bool = isLeatherChartFormat();
				var noteType: String;
				if (isLeatherNoteType && songNotes.length > 4 && Std.isOfType(songNotes[4], String))
					noteType = songNotes[4];
				else
					noteType = !Std.isOfType(songNotes[3], String) ? Note.defaultNoteTypes[songNotes[3]] : songNotes[3];
				if (Math.isNaN(holdLength))
					holdLength = 0.0;

				var gottaHitNote:Bool = (rawColumn < sectCols);

				// 处理主音符位置偏移
				var mainPosOffsetX:Float = 0;
				if (gottaHitNote)
					mainPosOffsetX += FlxG.width / 2;
				else if(ClientPrefs.data.middleScroll)
				{
					mainPosOffsetX += 310;
					if(noteColumn > 1)
						mainPosOffsetX += FlxG.width / 2 + 25;
				}

				// 创建主音符的预加载数据
				var mainNoteIndex:Int = unspawnNotesPreloaded.length;
				var isAlt: Bool = section.altAnim && !gottaHitNote;
				
			var mainNoteData:PreloadedChartNote = {
				strumTime: spawnTime,
				noteData: noteColumn,
				rawColumn: Std.int(songNotes[1]),
				mustPress: gottaHitNote,
					noteType: noteType,
					animSuffix: isAlt ? "-alt" : "",
					gfNote: (section.gfSection && gottaHitNote == section.mustHitSection),
				isSustainNote: false,
				sustainLength: holdLength,
				earlyHitMult: 1,
					parentIndex: -1,
					previousNoteIndex: previousNoteIndex,
					posOffsetX: mainPosOffsetX,
					posOffsetY: 0,
					correctionOffset: 0,
					curStepCrochet: 0,
					needsOldNoteScaleAdjust: false,
					isPixelStage: PlayState.isPixelStage,
					hasDownScrollCorrection: false
				};
				
				unspawnNotesPreloaded.push(mainNoteData);
				previousNoteIndex = mainNoteIndex;
				
				// 收集音符类型
				if(!noteTypes.contains(noteType))
					noteTypes.push(noteType);

				// 处理长音符
				var curStepCrochet:Float = 60 / daBpm * 1000 / 4.0;
				final roundSus:Int = Math.round(holdLength / curStepCrochet);
				if(roundSus > 0)
				{
					for (susNote in 0...roundSus)
					{
						var susSpawnTime:Float = spawnTime + (curStepCrochet * susNote);
						
						// 处理 sustain note 位置偏移
						var susPosOffsetX:Float = 0;
						if (gottaHitNote)
							susPosOffsetX += FlxG.width / 2;
						else if(ClientPrefs.data.middleScroll)
						{
							susPosOffsetX += 310;
							if(noteColumn > 1)
								susPosOffsetX += FlxG.width / 2 + 25;
						}
						
					var susNoteData:PreloadedChartNote = {
						strumTime: susSpawnTime,
						noteData: noteColumn,
						rawColumn: Std.int(songNotes[1]),
						mustPress: gottaHitNote,
							noteType: noteType,
							animSuffix: isAlt ? "-alt" : "",
							gfNote: (section.gfSection && gottaHitNote == section.mustHitSection),
							isSustainNote: true,
							sustainLength: 0,
							earlyHitMult: 0,
							parentIndex: mainNoteIndex,
							previousNoteIndex: previousNoteIndex,
							posOffsetX: susPosOffsetX,
							posOffsetY: 0,
							correctionOffset: 0, // 这个在运行时设置
							curStepCrochet: curStepCrochet,
							needsOldNoteScaleAdjust: true,
							isPixelStage: PlayState.isPixelStage,
							hasDownScrollCorrection: ClientPrefs.data.downScroll
						};
						
						unspawnNotesPreloaded.push(susNoteData);
						previousNoteIndex = unspawnNotesPreloaded.length - 1;
					}

					// 尾条判定优化：修正最后一个 tail 子音符的判定时机，避免"按住到可见尾部仍断连"
					var lastTailData:PreloadedChartNote = unspawnNotesPreloaded[unspawnNotesPreloaded.length - 1];
					var useExtendFix:Bool = (sustainTailFixMode == 'extend' || sustainTailFixMode == 'both');
					var useEarlyHitFix:Bool = (sustainTailFixMode == 'earlyHit' || sustainTailFixMode == 'both');
					if(useExtendFix)
					{
						// 方案A：把最后一个 tail 的判定点延伸到"可见尾部"结束处，使玩家按住到视觉尾部即可命中
						lastTailData.strumTime = spawnTime + holdLength;
					}
					if(useEarlyHitFix)
					{
						// 方案B：放宽最后一个 tail 的提前命中窗口，抵消其判定点比可见尾部早一个 step 的偏移
						lastTailData.earlyHitMult = 1;
					}
				}
			}
		}
	}

	public static function sortByTime(Obj1:Dynamic, Obj2:Dynamic):Int
		return FlxSort.byValues(FlxSort.ASCENDING, Obj1.strumTime, Obj2.strumTime);

	public function triggerEvent(eventName:String, value1:String, value2:String, value3:String, value4:String, strumTime:Float) {
		eventHandler.triggerEvent(eventName, value1, value2, value3, value4, strumTime);
	}

	override public function stagesFunc(func:BaseStage->Void) {
		for (stage in stages)
			if(stage != null && stage.exists && stage.active)
				func(stage);
	}

	function makeEvent(event:Array<Dynamic>, i:Int)
	{
		var subEvent:EventNote = {
			strumTime: event[0] + ClientPrefs.data.noteOffset,
			event: event[1][i][0],
			value1: event[1][i][1],
			value2: event[1][i][2],
			value3: event[1][i][3],
			value4: event[1][i][4]
		};
		eventNotes.push(subEvent);
		eventHandler.eventPushed(subEvent);
		callOnScripts('onEventPushed', [subEvent.event, subEvent.value1 != null ? subEvent.value1 : '', subEvent.value2 != null ? subEvent.value2 : '', subEvent.value3 != null ? subEvent.value3 : '', subEvent.value4 != null ? subEvent.value4 : '', subEvent.strumTime]);
	}

	public var skipArrowStartTween:Bool = false; //for lua
	// Play As Opponent（playOpponent）实现说明：
	// 不交换任何角色引用/箭头位置/血条图标，完整保留原有演出（镜头、事件、布局全部按原谱面走）。
	// 关键：note.mustPress 始终保持原版语义（true=bf 侧、false=dad 侧），绝不反转它，
	// 否则所有读取 mustPress 的脚本/模组/NoteType 都会判断错左右。
	// 只把"谁提供输入 / 谁自动演奏 / 谁会 miss"在判定层换边：isPlayerNote() 决定当前人类
	// 玩家控制的音符（playOpponent 时为 dad 侧）；CPU 自动演奏另一侧。
	// 表现层出口（渲染归组、亮灯、唱歌角色、人声）按 playOpponent 重定向到对应的一侧。
	// 改为 static：Note.update() 需要据此判断"当前 CPU 自动演奏侧"，以便把自动命中逻辑绑定到真正的控制侧。
	public static var playOpponent:Bool = false;

	// 玩家实际操作侧的键数（playOpponent 时操作对手侧，键数取 opponentColumns；否则 totalColumns）
	// replay 系统全程操作这个侧的键数，确保取模与 remapNote 用的 sideCols 一致。
	inline function sideCols():Int
		return playOpponent ? opponentColumns : totalColumns;

	/**
	 * Extra Keys：移动端触屏轨道的键数。
	 * touchLaneMode = '4k' 时固定 4 键；否则按谱面档位（与 Hitbox 构造时的列数计算保持一致）。
	 * 用于判断是否需要强制使用 Hitbox 预设（TouchPad 预设只支持 4 列）。
	 */
	public function mobileLaneCount():Int
	{
		if (ClientPrefs.data.touchLaneMode == '4k' || SONG == null)
			return 4;

		var mania:Null<Int> = SONG.mania;
		return ((mania != null) ? mania : 3) + 1;
	}

	// 玩家实际操作侧的箭头组（playOpponent 时为对手侧箭头）
	inline public function playerSideStrums():FlxTypedGroup<StrumNote>
		return playOpponent ? opponentStrums : playerStrums;
	// 对手/CPU 自动演奏侧的箭头组（playOpponent 时为玩家侧箭头），用于对手飞溅定位
	inline public function opponentSideStrums():FlxTypedGroup<StrumNote>
		return playOpponent ? playerStrums : opponentStrums;
	// 玩家实际操控的角色（playOpponent 时为 dad）
	inline public function playerSideChar():Character
		return playOpponent ? dad : boyfriend;
	// CPU 自动演奏侧的角色（playOpponent 时为 boyfriend）
	inline public function cpuSideChar():Character
		return playOpponent ? boyfriend : dad;
	// LE LTS 双侧：按角色取 sing 动画数组（dad=对手档 opponentSingAnimations、bf/gf=玩家档；
	// 非双侧恒玩家档）。解决双侧下对手侧超 4 列角色动画被钳制到 singRIGHT 的问题。
	inline function singAnimsFor(char:Character):Array<String>
	{
		if (isLeDualChart && char != null && char == dad)
			return opponentSingAnimations;
		return singAnimations;
	}
	// 当前由人类玩家控制的音符（playOpponent 时为对手/dad 侧，否则为玩家/bf 侧）。
	// 注意：note.mustPress 始终保持原版语义（true=bf 侧），不要反转它，否则脚本会读错。
	inline public function isPlayerNote(note:Note):Bool
		return (note.mustPress != playOpponent);

	/**
	 * 多键布局风格辅助（ClientPrefs.data.multiKeyLayoutStyle）：
	 * 'PsychEK' = 自适应收缩贴合屏幕（默认）；'Leather' = 照搬 LeatherEngine 表驱动
	 * （箭头尺寸 maniasize / 列距 maniagap / 居中补偿 maniaoffset，无自适应，按 1280x720 手调）。
	 * 表值与 LeatherEngine assets/data/ui skins/default/maniasize|maniagap|maniaoffset.txt 一致，
	 * 索引 = keyCount-1（1K 起），超出 21K 钳制到末位。
	 */
	static final LEATHER_MANIA_SIZE:Array<Float> = [0, 0, 0, 0, 0.06, 0.12, 0.15, 0.20, 0.22, 0.27, 0.31, 0.33, 0.35, 0.36, 0.37, 0.39, 0.41, 0.42, 0.43, 0.44, 0.45];
	static final LEATHER_MANIA_GAP:Array<Float> = [0, 0, 0, 0, -8, -11, -11, -12, -12, -12, -12, -12, -12, -12, -12, -12, -11, -11, -10, -10, -10];
	static final LEATHER_MANIA_OFFSET:Array<Float> = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 40, 40, 50, 50, 55, 70, 90, 105, 120, 135, 150];

	public static inline function isLeatherLayout():Bool
		return ClientPrefs.data.multiKeyLayoutStyle == 'Leather';

	static inline function leatherTableVal(table:Array<Float>, cols:Int):Float
	{
		var idx = cols - 1;
		if (idx < 0) idx = 0;
		if (idx >= table.length) idx = table.length - 1;
		return table[idx];
	}

	// Leather 箭头缩放系数（相对 0.7 基准）：(0.7 - maniasize) / 0.7。
	// LE 原始尺寸 = rawW * (0.7 - ms)，本项目基准 = rawW * 0.7，故比值即 scale。
	public static inline function leatherSizeScale(cols:Int):Float
		return (0.7 - leatherTableVal(LEATHER_MANIA_SIZE, cols)) / 0.7;

	// 该侧列间距：PsychEK = 等距（swagWidth × scale）；Leather = 箭头宽 + (2 + gap)
	// （负 gap = 相邻包围盒重叠，靠贴图透明边距不穿帮，LE 原样）。
	public static inline function sideSpacing(cols:Int, sideScale:Float):Float
	{
		if (!isLeatherLayout()) return Note.swagWidth * sideScale;
		return Note.swagWidth * sideScale + 2 + leatherTableVal(LEATHER_MANIA_GAP, cols);
	}

	// 该侧第 0 列 x（组左缘）。PsychEK = 按侧中心居中；Leather = LE 手调居中公式
	// x = (W/2)*侧 + 100 - (cols-4)*16 + (cols>=10 ? 30 : 0) + maniaoffset。
	// middleScroll 无对应 LE 布局，回退按 0.5W 居中排布（仍用 Leather 间距/尺寸）。
	public static function sideGroupLeftX(cols:Int, spacing:Float, mustPress:Bool):Float
	{
		var middleScroll:Bool = ClientPrefs.data.middleScroll;
		if (!isLeatherLayout() || middleScroll)
		{
			var cX:Float = middleScroll ? (FlxG.width * 0.5) : (mustPress ? (FlxG.width * 0.75) : (FlxG.width * 0.25));
			return cX - (cols - 1) * spacing / 2;
		}
		return (FlxG.width / 2) * (mustPress ? 1 : 0)
			+ (100 - (cols - 4) * 16) + (cols >= 10 ? 30 : 0)
			+ leatherTableVal(LEATHER_MANIA_OFFSET, cols);
	}

	/**
	 * Extra Keys：多键时计算 strum 收缩系数并写回 static strumScale。
	 * 必须在 generateSong() 之前调用（Note 构造时读取），generateStaticArrows() 直接复用结果。
	 *
	 * 约束（保证整组含列宽绝不越屏）：组中心到屏幕边缘的较小空间为 edge，
	 * 整组宽（cols*spacing）的一半 + 单列宽 spacing ≤ edge
	 *   → spacing*(cols/2) + spacing ≤ edge → spacing ≤ 2*edge/(cols+2)
	 * 代数一次求解（无需迭代）。4 键不调用（strumScale 保持 1）。
	 */
	public function computeMultiKeyStrumScale():Void
	{
		// LE LTS 双侧：两侧 strum/音符独立缩放（玩家侧中心 0.75W、对手侧 0.25W；middleScroll 均 0.5W）。
		// 非双侧两侧同值（= 原单侧逻辑）。strumScale 主值 = 玩家侧，兼容既有引用。
		playerStrumScale = calcSideStrumScale(totalColumns, ClientPrefs.data.middleScroll ? 0.5 : 0.75);
		opponentStrumScale = calcSideStrumScale(isLeDualChart ? opponentColumns : totalColumns, ClientPrefs.data.middleScroll ? 0.5 : 0.25);
		strumScale = playerStrumScale;
	}

	// 单侧 strum 缩放：按该侧列数与中心比例计算（边缘留 24px 观感留白）。4 键侧恒为 1（保留原布局）。
	// Leather 布局风格：直接查 LE maniasize 表（非自适应），4 键仍恒为 1。
	function calcSideStrumScale(cols:Int, centerFrac:Float):Float
	{
		if (cols <= 4) return 1;
		if (isLeatherLayout()) return leatherSizeScale(cols);
		var centerX:Float = FlxG.width * centerFrac;
		var edge:Float = Math.min(centerX, FlxG.width - centerX) - 24;
		var maxSpacing:Float = 2 * edge / (cols + 2);
		var scale:Float = 1;
		if (Note.swagWidth * scale > maxSpacing)
			scale = maxSpacing / Note.swagWidth;
		return scale;
	}

	// 滚动音符（Note.hx 构造/长条尾部）按侧取 strum 缩放；非双侧恒为主值 strumScale
	public static function getNoteSideScale(mustPress:Bool):Float
	{
		if (instance == null || !instance.isLeDualChart) return strumScale;
		return mustPress ? instance.playerStrumScale : instance.opponentStrumScale;
	}

	private function generateStaticArrows(player:Int, ?instant:Bool = false):Void
	{
		var strumLineX:Float = ClientPrefs.data.middleScroll ? STRUM_X_MIDDLESCROLL : STRUM_X;
		var strumLineY:Float = ClientPrefs.data.downScroll ? (FlxG.height - 150) : 50;

		// 应用传统音符位置偏移
		var legacyOffset:Float = ClientPrefs.data.legacynotepos ? 50 : 0;

		// LE LTS 双侧：strum 组按各自侧键数生成（玩家侧=totalColumns、对手侧=opponentColumns）；
		// 非双侧时 opponentColumns 不生效，恒用 totalColumns。
		var sideCols:Int = (player == 1) ? totalColumns : (isLeDualChart ? opponentColumns : totalColumns);

		// 标准 4 键：保留旧引擎原始布局，确保 100% 向后兼容。
		if (sideCols == 4)
		{
			strumScale = 1; // 重置多键收缩残留，避免上一首多键歌影响 4 键大小
			for (i in 0...4)
			{
				var targetAlpha:Float = 1;
				// "隐藏/淡化对手箭头" 的规则应作用于 CPU 自动演奏侧（playOpponent 时是右侧玩家箭头组）
				if ((player < 1) != playOpponent)
				{
					if(!ClientPrefs.data.opponentStrums) targetAlpha = 0;
					else if(ClientPrefs.data.middleScroll) targetAlpha = 0.35;
				}

				var babyArrow:StrumNote = new StrumNote(strumLineX, strumLineY, i, player);
				babyArrow.downScroll = ClientPrefs.data.downScroll;

				babyArrow.x -= legacyOffset;

				if (!instant && !isStoryMode && !skipArrowStartTween)
				{
					babyArrow.alpha = 0;
					FlxTween.tween(babyArrow, {alpha: targetAlpha}, 1, {ease: FlxEase.circOut, startDelay: 0.5 + (0.2 * i)});
				}
				else babyArrow.alpha = targetAlpha;

				if (player == 1)
					playerStrums.add(babyArrow);
				else
				{
					if(ClientPrefs.data.middleScroll)
					{
						babyArrow.x += 310;
						if(i > 1) {
							babyArrow.x += FlxG.width / 2 + 25;
						}
					}
					opponentStrums.add(babyArrow);
				}

				strumLineNotes.add(babyArrow);
				babyArrow.playerPosition();
			}
			return;
		}

		// 多键：按布局风格（PsychEK 居中 / Leather LE 公式）分布 + 按侧 strumScale 缩放（LE LTS 双侧：玩家/对手各自独立缩放，非双侧同值）
		var sideScale:Float = (player == 1) ? playerStrumScale : opponentStrumScale;
		var spacing:Float = sideSpacing(sideCols, sideScale);
		var groupLeft:Float = sideGroupLeftX(sideCols, spacing, player == 1) - legacyOffset;

		for (i in 0...sideCols)
		{
			var targetAlpha:Float = 1;
			// 同上：淡化规则作用于 CPU 自动演奏侧
			if ((player < 1) != playOpponent)
			{
				if(!ClientPrefs.data.opponentStrums) targetAlpha = 0;
				else if(ClientPrefs.data.middleScroll) targetAlpha = 0.35;
			}

			var babyArrow:StrumNote = new StrumNote(strumLineX, strumLineY, i, player);
			babyArrow.downScroll = ClientPrefs.data.downScroll;

			if (!instant && !isStoryMode && !skipArrowStartTween)
			{
				babyArrow.alpha = 0;
				FlxTween.tween(babyArrow, {alpha: targetAlpha}, 1, {ease: FlxEase.circOut, startDelay: 0.5 + (0.2 * i)});
			}
			else babyArrow.alpha = targetAlpha;

			if (!PlayState.isPixelStage && sideScale != 1)
			{
				babyArrow.scale.scale(sideScale);
				// 关键：缩放后必须同步 width/offset/origin，否则 strum 渲染中心
				// 仍按缩放前的 width 计算（offset=(frameWidth-width)/2），比滚动箭头偏右约半列宽。
				babyArrow.updateHitbox();
				babyArrow.centerOffsets();
				babyArrow.centerOrigin();
			}

			if (player == 1)
				playerStrums.add(babyArrow);
			else
				opponentStrums.add(babyArrow);

			strumLineNotes.add(babyArrow);
			babyArrow.x = groupLeft + spacing * i;
		}
		/*trace('[EK] strums side=' + player + ' cols=' + totalColumns + ' centerX=' + centerX + ' spacing=' + spacing
			+ ' groupW=' + groupWidth + ' firstX=' + ((centerX - groupWidth / 2) - legacyOffset)
			+ ' lastX=' + ((centerX - groupWidth / 2) - legacyOffset + spacing * (totalColumns - 1))
			+ ' lastEdge=' + ((centerX - groupWidth / 2) - legacyOffset + spacing * (totalColumns - 1) + Note.swagWidth * strumScale)
			+ ' screenW=' + FlxG.width);*/
	}

	/** 根据当前 strum 的实际位置，为每个 strum 组（对手/玩家）生成 Track 上的黑色半透明覆盖层（阴影）。 */
	/** 为两侧每列 strum 创建 Hold Cover（长条按住光效）。 */
	public function createHoldCovers():Void
	{
		playerHoldCovers = [];
		opponentHoldCovers = [];
		NoteHoldCover.configs.clear(); // 重新读取（皮肤 / JSON 可能已更改）
		for (cover in grpHoldCovers.members)
			if(cover != null) cover.destroy();
		grpHoldCovers.clear();
		if(!ClientPrefs.data.holdCovers) return;

		for (i in 0...playerSideStrums().members.length)
		{
			var strum:StrumNote = playerSideStrums().members[i];
			if(strum == null) continue;
			try
			{
				var cover:NoteHoldCover = new NoteHoldCover(strum, i);
				grpHoldCovers.add(cover);
				playerHoldCovers[i] = cover;
			}
			catch (e:Dynamic) { playerHoldCovers[i] = null; } // 自定义目录缺失时退化为不显示覆盖，避免崩溃
		}

		if(ClientPrefs.data.opponentHoldCovers)
		{
			for (i in 0...opponentSideStrums().members.length)
			{
				var strum:StrumNote = opponentSideStrums().members[i];
				if(strum == null) continue;
				try
				{
					var cover:NoteHoldCover = new NoteHoldCover(strum, i);
					grpHoldCovers.add(cover);
					opponentHoldCovers[i] = cover;
				}
				catch (e:Dynamic) { opponentHoldCovers[i] = null; }
			}
		}
	}

	/** 长条命中时驱动 Hold Cover：头 -> start，中段 -> 刷新循环，最后一节 -> end 爆发 */
	public function holdCoverHit(note:Note, playerSide:Bool):Void
	{
		if(!ClientPrefs.data.holdCovers || note == null || note.noteSplashData.disabled) return;
		if(!playerSide && (!ClientPrefs.data.opponentHoldCovers || !ClientPrefs.data.cpuStrums)) return;

		// Hold Cover 数量限制检查（与最大溅射数类似）：当前显示中的覆盖数达上限则跳过本次
		if (ClientPrefs.data.holdCoverLimitEnabled)
		{
			var aliveCount:Int = 0;
			for (covers in [playerHoldCovers, opponentHoldCovers])
				for (c in covers)
					if (c != null && c.visible) aliveCount++;
			if (aliveCount >= ClientPrefs.data.holdCoverLimit)
				return;
		}

		var covers:Array<NoteHoldCover> = playerSide ? playerHoldCovers : opponentHoldCovers;
		if(note.noteData < 0 || note.noteData >= covers.length) return;
		var cover:NoteHoldCover = covers[note.noteData];
		if(cover == null) return;

		cover.timeout = Conductor.stepCrochet * 2.5 / 1000 / playbackRate;
		if(!note.isSustainNote)
		{
			if(note.tail.length > 0) cover.startHold(); // 长条头
		}
		else if(note.parent != null && note.parent.tail.length > 0
			&& note.parent.tail[note.parent.tail.length - 1] == note)
		{
			// 对手飞溅禁用时不播放 end 爆发动画（holdcover 本身仍启用，start/hold 照常）
			if(playerSide || ClientPrefs.data.opponentSplashes)
				cover.playEnd(); // 长条最后一节
			else
				cover.hideCover(true);
		}
		else
			cover.keepHold(); // 长条中段
	}

	/** 隐藏某列 Hold Cover（松手 / miss）。force=false 时不打断正在播放的 end 动画 */
	public function hideHoldCover(playerSide:Bool, direction:Int, force:Bool = true):Void
	{
		var covers:Array<NoteHoldCover> = playerSide ? playerHoldCovers : opponentHoldCovers;
		if(direction < 0 || direction >= covers.length) return;
		var cover:NoteHoldCover = covers[direction];
		if(cover != null) cover.hideCover(force);
	}

	public function createLaneCovers():Void
	{
		opponentLaneCover = null;
		playerLaneCover = null;
		laneCovers.clear();
		if (ClientPrefs.data.laneCoverAlphaP1 <= 0 && ClientPrefs.data.laneCoverAlphaP2 <= 0) return;

		if (ClientPrefs.data.laneCoverAlphaP2 > 0)
			opponentLaneCover = createLaneCoverFor(opponentStrums, ClientPrefs.data.laneCoverAlphaP2);
		if (ClientPrefs.data.laneCoverAlphaP1 > 0)
			playerLaneCover = createLaneCoverFor(playerStrums, ClientPrefs.data.laneCoverAlphaP1);
	}

	/** 每帧更新覆盖层位置、尺寸、透明度，适应 modchart 对 strum 的移动与 alpha 变化。 */
	public function updateLaneCovers():Void
	{
		if (laneCovers.members.length == 0) return;

		function updateCover(c:FlxSprite, group:FlxTypedGroup<StrumNote>, baseAlpha:Float) {
			if (c == null || group.length == 0) return;
			var minX:Float = Math.POSITIVE_INFINITY;
			var maxX:Float = Math.NEGATIVE_INFINITY;
			for (s in group) {
				minX = Math.min(minX, s.x);
				maxX = Math.max(maxX, s.x + s.width);
			}
			c.x = minX;
			c.scale.x = maxX - minX;

			// 基于箭头 alpha 叠加：覆盖层最终透明度 = 基础设置值 × 该组首个 strum 的 alpha
			var finalAlpha:Float = baseAlpha;
			if (ClientPrefs.data.laneCoverByStrumAlpha)
				finalAlpha *= group.members[0].alpha;
			c.alpha = finalAlpha;
		}

		updateCover(opponentLaneCover, opponentStrums, ClientPrefs.data.laneCoverAlphaP2);
		updateCover(playerLaneCover, playerStrums, ClientPrefs.data.laneCoverAlphaP1);
	}

	private function createLaneCoverFor(group:FlxTypedGroup<StrumNote>, baseAlpha:Float):FlxSprite
	{
		if (group == null || group.length == 0) return null;

		var minX:Float = Math.POSITIVE_INFINITY;
		var maxX:Float = Math.NEGATIVE_INFINITY;
		for (s in group)
		{
			minX = Math.min(minX, s.x);
			maxX = Math.max(maxX, s.x + s.width);
		}
		if (minX == Math.POSITIVE_INFINITY) return null;

		var w:Int = Math.ceil(maxX - minX);
		var cover:FlxSprite = new FlxSprite(minX, 0);
		cover.makeGraphic(1, Std.int(FlxG.height), FlxColor.BLACK);
		cover.scale.x = w;
		cover.updateHitbox();
		cover.alpha = ClientPrefs.data.laneCoverByStrumAlpha && group.members[0] != null ? baseAlpha * group.members[0].alpha : baseAlpha;
		cover.scrollFactor.set();
		cover.cameras = [camHUD];
		laneCovers.add(cover);
		return cover;
	}

	/** 应用键位配置：键数、缩放、配色前缀、sing 动画、键位 action。
	 *  从 extrakeys.json 读取当前 mania 档位的列配置，动态填充 Note.colArray / singAnimations / keysArray。
	 *  mania=3（4键）时与旧硬编码行为完全一致，保证老谱面 100% 向后兼容。
	 */
	/** 按当前键数重建回放按键状态数组（多键适配：replayHeldKeys/keyPressIndices/replayNoteDelays
	 *  原为硬编码 4 元素，6k+ 谱面索引 4..17 越界 → 回放释放逻辑失效、箭头卡按下）。
	 *  laneCount 为列数；重建后若正在回放则按 replayData 重新预填延迟数据（幂等，可重复调用）。 */
	function rebuildReplayKeyArrays(laneCount:Int):Void
	{
		if (laneCount < 1) laneCount = 1;
		replayHeldKeys = [for (i in 0...laneCount) false];
		keyPressIndices = [for (i in 0...laneCount) -1];
		replayNoteDelays = [for (i in 0...laneCount) []];
		if (isReplaying && replayData != null)
			// 预填延迟时对 action.key 取模对齐 laneCount（remapNote 折叠规则相同），
			// 避免 changekeycount 后 noteData 被折叠但延迟数据仍落在旧索引槽导致读不到。
			for (action in replayData)
				if (action.noteTime != null && action.late != null && action.key >= 0 && action.key < NON_NOTE_KEY_OFFSET)
					replayNoteDelays[action.key % laneCount].push({strumTime: action.noteTime, late: action.late});
	}

	public function applyMania(mania:Int):Void
	{
		if (startArrowSkin == null)
		{
			startArrowSkin = PlayState.SONG.arrowSkin;
			startSplashSkin = PlayState.SONG.splashSkin;
		}

		// 确保 EK 配置已加载
		ExtraKeysHandler.ensure();
		var ek = ExtraKeysHandler.instance.data;

		curMania = mania;
		totalColumns = mania + 1;
		strumScale = 1;
		// Extra Keys：键数已知后立即计算收缩系数（generateSong 的 Note 构造与 generateStaticArrows 共用；
		// applyMania 会被 generateSong/ generateStaticArrows 各调一次，computeMultiKeyStrumScale 幂等）
		if (totalColumns > 4) computeMultiKeyStrumScale();

		// 兜底：extrakeys.json 缺失时退回 4 键
		if (ek == null || ek.keys == null || ek.keys.length <= mania) {
			Note.colArray = ['purple', 'blue', 'green', 'red'];
			singAnimations = ['singLEFT', 'singDOWN', 'singUP', 'singRIGHT'];
			keysArray = ['note_left', 'note_down', 'note_up', 'note_right'];
			rebuildReplayKeyArrays(4); // 回放状态数组按当前键数重建（多键适配）
			return;
		}

		// 按当前 mania 档位逐列填充：
		//   colArray[i]    = 该列贴图前缀（purple/blue/green/red/rombus/circle...）
		//   singAnimations[i] = 该列 sing 动画名（singLEFT/singDOWN/...）
		//   keysArray[i]   = 该列输入 action 名（"{mania}_key_{i}"，对应 ClientPrefs.keyBinds）
		var newColArray:Array<String> = [];
		var newSingAnims:Array<String> = [];
		var newKeysArray:Array<String> = [];
			var mode:EKManiaMode = ek.keys[mania];
			// 键数以预期键数为准（applyMania=totalColumns / applyOpponentMania=opponentColumns），
			// 而非 EK notes 数组长度。EK 只管贴图动画（缺失列 fallback），保证 keysArray 始终与 strums 数量对齐。
			var laneCount:Int = totalColumns;

			for (i in 0...laneCount)
			{
				var globalIdx:Int = (mode != null && mode.notes != null && i < mode.notes.length) ? mode.notes[i] : i;
			var anim:EKAnimation = (ek.animations != null && globalIdx >= 0 && globalIdx < ek.animations.length)
				? ek.animations[globalIdx] : null;

			newColArray.push(anim != null ? anim.note : 'purple');
			newSingAnims.push(anim != null ? ('sing' + anim.sing) : 'singLEFT');
			newKeysArray.push(Std.string(mania) + '_key_' + i);
		}

		Note.colArray = newColArray;
			singAnimations = newSingAnims;
			keysArray = newKeysArray;
			rebuildReplayKeyArrays(laneCount); // 回放状态数组按当前键数重建（多键适配）

			// Extra Keys：进游戏时兜底把 arrowRGB/arrowRGBPixel/arrowHSV 补齐到 18 色
		// （loadPrefs 启动早期 ExtraKeysHandler 可能加载失败导致多键列取色越界→染色失效）
		ClientPrefs.ensureEKArrowColors();
		/*trace('[EK] applyMania(' + mania + ') -> columns=' + laneCount
			+ ' colArray=[' + newColArray.join(',') + ']'
			+ ' arrowRGB.len=' + (ClientPrefs.data.arrowRGB != null ? ClientPrefs.data.arrowRGB.length : -1)
			+ ' arrowRGBPixel.len=' + (ClientPrefs.data.arrowRGBPixel != null ? ClientPrefs.data.arrowRGBPixel.length : -1));*/
	}

	// —— LE LTS 双侧轨道数：对手侧 EK 档位配置（与 applyMania 同构，填充 opponentColumns/opponentColArray/opponentSingAnimations）——
	// 仅双侧模式（isLeDualChart）调用；非双侧模式对手侧恒等于玩家侧（generateStaticArrows 等按 totalColumns 处理）。
	public function applyOpponentMania(mania:Int):Void
	{
		ExtraKeysHandler.ensure();
		var ek = ExtraKeysHandler.instance.data;
		oppMania = mania;
		opponentColumns = mania + 1;

		// 兜底：extrakeys.json 缺失时退回 4 键
		if (ek == null || ek.keys == null || ek.keys.length <= mania)
		{
			opponentColArray = ['purple', 'blue', 'green', 'red'];
			opponentSingAnimations = ['singLEFT', 'singDOWN', 'singUP', 'singRIGHT'];
			return;
		}

		// 按对手档位逐列填充（与 applyMania 相同的 EK 配置读取逻辑）
		var newColArray:Array<String> = [];
		var newSingAnims:Array<String> = [];
		var mode:EKManiaMode = ek.keys[mania];
			// 键数以预期键数为准（applyMania=totalColumns / applyOpponentMania=opponentColumns），
			// 而非 EK notes 数组长度。EK 只管贴图动画（缺失列 fallback），保证 keysArray 始终与 strums 数量对齐。
			var laneCount:Int = opponentColumns;

			for (i in 0...laneCount)
			{
				var globalIdx:Int = (mode != null && mode.notes != null && i < mode.notes.length) ? mode.notes[i] : i;
			var anim:EKAnimation = (ek.animations != null && globalIdx >= 0 && globalIdx < ek.animations.length)
				? ek.animations[globalIdx] : null;

			newColArray.push(anim != null ? anim.note : 'purple');
			newSingAnims.push(anim != null ? ('sing' + anim.sing) : 'singLEFT');
		}

		opponentColArray = newColArray;
		opponentSingAnimations = newSingAnims;
		/*trace('[EK] applyOpponentMania(' + mania + ') -> columns=' + laneCount
			+ ' colArray=[' + newColArray.join(',') + ']');*/
	}

	// —— LE LTS 双侧：change keycount 事件实时切换两侧轨道数 ——
	// 参考 LTS EventHandler 思路：写回 SONG 两侧键数 → applyMania/applyOpponentMania 更新两侧 EK 档配置
	// → 重建两侧 strums（instant 不播渐入）→ 重排已生成音符 x（按 mustPress 侧 + 新键数）→ 回放键数组随 applyMania 重建。
	// —— 开局 / change keycount 改键后的键位预览 ——
	// 样式由 ClientPrefs.data.keyPreviewStyle 决定：
	//  - 'ek'：EK KeybindShowcase（strum 下方背景块 + 双键位切换淡出）
	//  - 'le'：LE extraKeyReminders（strum 上方白字黑阴影，逐列延迟上浮淡出；仅非 4 键显示）
	// 记录当前在屏的预览对象：快速连续改键（change keycount 高频触发）时先清除旧的，避免叠字重叠
	public var keyPreviewObjs:Array<FlxBasic> = [];

	public function clearKeyPreview():Void
	{
		for (obj in keyPreviewObjs)
		{
			if (obj != null && members.indexOf(obj) != -1) remove(obj);
			if (obj != null) obj.kill();
		}
		keyPreviewObjs = [];
	}

	public function showKeyPreview():Void
	{
		clearKeyPreview();
		if (!ClientPrefs.data.showKeyPreview) return;
		// playOpponent 下用操作侧 strums（对手侧）显示键位预览，让玩家知道自己控制的箭头是哪些
		var sideStrums:FlxTypedGroup<StrumNote> = playerSideStrums();
		var previewKeys:Int = Std.int(Math.min(sideStrums.members.length, keysArray.length));
		if (ClientPrefs.data.keyPreviewStyle == 'le' && sideStrums.members.length != 4)
		{
			for (i in 0...previewKeys)
			{
				var st:StrumNote = sideStrums.members[i];
				var keyCodes:Array<FlxKey> = ClientPrefs.keyBinds.get(keysArray[i]);
				if (keyCodes == null || keyCodes.length < 1) continue;
				var coolWidth:Int = Math.ceil(st.width / 2.83684);
				if (coolWidth < 4) coolWidth = 4;
				var keyName:String = InputFormatter.getKeyName(keyCodes[0]);
				var keyShadow:FlxText = new FlxText((st.x + (st.width / 2)) - (coolWidth / 2), st.y - (coolWidth / 2), coolWidth, keyName, coolWidth);
				keyShadow.cameras = [camHUD];
				keyShadow.color = FlxColor.BLACK;
				keyShadow.scrollFactor.set();
				add(keyShadow);
				keyPreviewObjs.push(keyShadow);
				var keyThing:FlxText = new FlxText(keyShadow.x - 6, keyShadow.y - 6, coolWidth, keyName, coolWidth);
				keyThing.cameras = [camHUD];
				keyThing.scrollFactor.set();
				add(keyThing);
				keyPreviewObjs.push(keyThing);
				FlxTween.tween(keyShadow, {y: keyShadow.y + 10, alpha: 0}, 3, {
					ease: FlxEase.circOut,
					startDelay: 0.5 + (0.2 * i),
					onComplete: function(_) { remove(keyShadow); keyShadow.kill(); keyShadow.destroy(); }
				});
				FlxTween.tween(keyThing, {y: keyThing.y + 10, alpha: 0}, 3, {
					ease: FlxEase.circOut,
					startDelay: 0.5 + (0.2 * i),
					onComplete: function(_) { remove(keyThing); keyThing.kill(); keyThing.destroy(); }
				});
			}
		}
		else
		{
			for (i in 0...previewKeys)
			{
				var st:StrumNote = sideStrums.members[i];
				var keyCodes:Array<FlxKey> = ClientPrefs.keyBinds.get(keysArray[i]);
				if (keyCodes == null || keyCodes.length < 1) continue;
				var kc:KeybindShowcase = new KeybindShowcase(st.x,
					ClientPrefs.data.downScroll ? st.y - 30 : st.y + st.height + 5,
					keyCodes, camHUD, st.width / 2, (SONG != null && SONG.mania != null) ? SONG.mania : 3);
				kc.onComplete = function() remove(kc);
				add(kc);
				keyPreviewObjs.push(kc);
			}
		}
	}

	// showPreviewAfter：改键后是否重显键位预览（由 change keycount 事件 value3 控制，默认 true；false 则跳过且不影响已显示的预览）
	public function changeKeyCounts(playerKeyCount:Int, oppKeyCount:Int, showPreviewAfter:Bool = true):Void
	{
		if (playerKeyCount < 1 || playerKeyCount > 18) playerKeyCount = 4;
		if (oppKeyCount < 1 || oppKeyCount > 18) oppKeyCount = 4;

		// 无变化则跳过（防事件重复触发导致无谓重建）
		var curPlr:Int = totalColumns;
		var curOpp:Int = opponentColumns;
		if (curPlr == playerKeyCount && curOpp == oppKeyCount) return;

		isLeDualChart = true; // 事件显式进入双侧模式

		// 回放模式：changekeycount 期间 heldKeys 有三次风险：
		// 1) applyMania 内部 rebuildReplayKeyArrays 按玩家侧键数重建——playOpponent 下操作侧是对手侧，长度不对
		// 2) rebuildReplayKeyArrays 会全清 heldKeys，进行中长条 sustain 丢失
		// 3) 操作侧键数与玩家侧不同时，取模基数必须对齐
		// 解法：先快照 heldKeys → applyMania/opp 正常执行 → 用 sideCols() 覆盖重建操作侧的数组 → 按操作侧目标键数迁移快照
		var savedHeldBefore:Array<Bool> = null;
		if (isReplaying)
			savedHeldBefore = replayHeldKeys.copy();

		// 注意：不写 SONG.playerKeyCount/keyCount——SONG 保持谱面原始键数，
			// 供重玩（restartSong/重进）恢复初始配置；运行键数由 applyMania/applyOpponentMania 维护。
			applyMania(playerKeyCount - 1);
			applyOpponentMania(oppKeyCount - 1);

			// playOpponent 下，玩家键盘事件应全部映射到对手侧 mania 档位的 action 名（"{oppMania}_key_{i}"）。
			// applyMania 先把 keysArray 设成玩家侧档位（"{curMania}_key_{i}"），导致混档——
			// 前 N 列是玩家侧 action 名，pad 出来的才是对手侧。全部重建确保统一用操作侧档位。
			if (playOpponent)
			{
				var oppPadKeys:Array<String> = [];
				for (i in 0...opponentColumns)
					oppPadKeys.push(Std.string(oppMania) + '_key_' + i);
				keysArray = oppPadKeys;
			}

			// 回放模式：applyMania 内部 rebuildReplayKeyArrays 按玩家侧重建了 heldKeys，
		// playOpponent 下操作侧是对手侧，键数不对。这里用 sideCols() 覆盖重建，确保数组长度对齐。
		// 然后按同样的取模规则把快照中的按下状态迁移到新数组，保持进行中长条不因改键丢失持续按住状态。
		if (savedHeldBefore != null)
		{
			// 操作侧的目标键数（changeKeyCounts 还未返回，sideCols() 读到的还是旧值，显式计算）
			var targetCols:Int = playOpponent ? oppKeyCount : playerKeyCount;
			rebuildReplayKeyArrays(targetCols);
			for (oldIdx in 0...savedHeldBefore.length)
				if (savedHeldBefore[oldIdx])
					replayHeldKeys[oldIdx % targetCols] = true;
		}
		if (totalColumns > 4 || opponentColumns > 4) computeMultiKeyStrumScale();
		else { playerStrumScale = 1; opponentStrumScale = 1; strumScale = 1; }

		// 重建两侧 strums（不播渐入）
		playerStrums.clear();
		opponentStrums.clear();
		strumLineNotes.clear();
		generateStaticArrows(0, true);
		generateStaticArrows(1, true);

		// 新 strums 构造后无动画（resetAnim=0 → update 不会播 static → curAnim=null）：
		// 渲染会停在图集首帧（全组显示同一帧左箭头），且按键判定处读 curAnim.name 会取到 null。
		// 立即播 static 使每根 strum 有正确的本列静态帧与动画状态。
		for (s in playerStrums) if (s != null) s.playAnim('static');
		for (s in opponentStrums) if (s != null) s.playAnim('static');

		// 改键后：场上音符折叠到新键数（取模重映射 noteData + 重排 x + 换新档配色动画 + 按新 scale 重缩），
		// 与新建 strums 完全匹配；sustain 长条随 head 一起折叠（head 已重映射，tail 复制其新 noteData）。
		remapNotesToNewKeyCount();
		// hold cover 绑定的 strum 已被 clear 重建，需重新创建（绑定新 strums、按新档着色）
		createHoldCovers();
		// 改键后按当前样式重显键位预览（LE extraKeyReminders / EK KeybindShowcase），让玩家知道新键位；
		// 事件 value3 = 0/false 时跳过，且不会清掉当前已显示的预览（showKeyPreview 内部才做清理）
			if (showPreviewAfter) showKeyPreview();

			trace('[LE DUAL] changeKeyCounts -> player=${playerKeyCount}K opponent=${oppKeyCount}K | keysArray.len=' + keysArray.length
				+ ' total=' + totalColumns + ' opp=' + opponentColumns + ' oppMania=' + oppMania + ' playOpp=' + playOpponent);

			// 兜底：playOpponent 下如果 keysArray 长度 < 操作侧键数，补全缺失 action 名。
			// 常见原因：EK 配置里某档位的 notes 数组长度 < 档位预期键数，导致 applyMania 生成的 keysArray 比预期短。
			// 补全的 action 名按操作侧当前 mania 档位格式 "{mania}_key_{i}" 生成——若玩家未在该档位绑键，
			// 则需要在设置里补上；但至少保证 strums 重建、showKeyPreview、keyPressed 边界检查全对齐。
			var needKeys:Int = sideCols();
			if (keysArray.length < needKeys)
			{
				var padMania:Int = playOpponent ? oppMania : curMania;
				for (i in keysArray.length...needKeys)
					keysArray.push(Std.string(padMania) + '_key_' + i);
				trace('[LE DUAL] keysArray padded from ' + (needKeys - (needKeys - keysArray.length))
					+ ' to ' + keysArray.length + ' (padMania=' + padMania + ')');
			}

		// 移动端 Hitbox：按新操作侧键数重建触屏 lane 按钮（列数/列宽/配色/多键 NOTE 映射）。
		// 进曲时 Hitbox 只按 SONG.mania 生成一次，中途 changeKeyCounts 后不重建会停留在旧样式，
		// 且多出的轨道因 trackedButtons 缺映射而按不到。
		refreshMobileHitbox();
	}

	/**
	 * Extra Keys：changeKeyCounts 后刷新移动端 Hitbox 的 lane 按钮布局。
	 * touchLaneMode='4k' 时触屏固定 4 列（与进曲时 Hitbox 构造函数的列数判定一致）；
	 * 否则按玩家操作侧当前键数（playOpponent 时为对手侧）。
	 */
	private function refreshMobileHitbox():Void
	{
		if (mobileControls == null) return;
		var hb:Hitbox = cast mobileControls.instance;
		if (hb == null) return;

		var newCols:Int = sideCols();
		if (ClientPrefs.data.touchLaneMode == '4k') newCols = 4;
		if (newCols < 1) newCols = 4;
		hb.rebuildLanes(newCols, newCols - 1);
	}

	// —— 改键后音符折叠重映射（与新建 strums 匹配） ——
	public function remapNotesToNewKeyCount():Void
	{
		for (note in unspawnNotes)
			if (note != null) remapNote(note);
		for (note in notes)
			if (note != null) remapNote(note);
	}

	private function remapNote(n:Note):Void
	{
		// 已销毁的音符（FlxSprite.destroy 置 frames=null，如 hold 结束后被 removeNote）跳过，避免无效操作
		if (n.frames == null) return;
		var sideCols:Int = n.mustPress ? totalColumns : opponentColumns;
		// 1) noteData 折叠/展开（可逆）：改键变小取模折叠并记录原始列；键数恢复（能容纳原列）时展开回原列。
		//    长条段（tail）跟随 head 同步折叠/展开，避免 9k→6k→9k 后高列音符丢失。
		var newData:Int = n.noteData;
		if (n.origNoteData >= 0)
		{
			// 已折叠过：键数能容纳原列 → 展开恢复；否则按原列重新折叠
			newData = (n.origNoteData < sideCols) ? n.origNoteData : (n.origNoteData % sideCols);
		}
		else if (n.noteData >= sideCols)
		{
			n.origNoteData = n.noteData;
			newData = n.noteData % sideCols;
		}
		if (newData != n.noteData)
		{
			n.noteData = newData;
			n.ID = newData;
			if (n.tail != null) for (t in n.tail) if (t != null) { t.noteData = newData; t.ID = newData; t.origNoteData = n.origNoteData; }
		}
		// 2) 换新档配色/动画数组 + 档位记录，立即刷新动画与着色
		if (PlayState.instance.isLeDualChart)
		{
			n.noteColArray = n.mustPress ? Note.colArray : PlayState.instance.opponentColArray;
			n.genMania = totalColumns - 1;
			n.genOppMania = opponentColumns - 1;
			n.refreshNoteVisual();
		}
		// 3) x 按新键数 + 新侧 scale 重排（head 与 sustain tail 都要——tail 的 x 只在生成时设置过一次，
		//    不重排会停在旧键数布局导致长条位置偏移）
		relayoutNoteX(n);
		if (n.tail != null) for (t in n.tail) if (t != null) relayoutNoteX(t);
		// 4) 按新侧 scale 重缩（宽度；sustain 的 y 为长条长度逻辑，不动）
		rescaleNote(n);
		if (n.tail != null) for (t in n.tail) if (t != null) rescaleNote(t);
		// 5) 长条衔接偏移：tail.y = strumY + offsetY + correctionOffset + distance，correctionOffset 只在
		//    spawn 时按 head.height/2 设置一次；改键后 head 高度已随新 scale 变化，同步更新在场长条的
		//    correctionOffset，避免长条起点与箭头衔接处出现 y 偏移（downScroll 恒为 0 不变）。
		if (n.tail != null && !ClientPrefs.data.downScroll)
			for (t in n.tail) if (t != null) t.correctionOffset = n.height / 2;
	}

	private function rescaleNote(n:Note):Void
	{
		if (PlayState.isPixelStage || n.genStrumScale <= 0) return;
		var want:Float = PlayState.getNoteSideScale(n.mustPress);
		// baseScale 为 0.7 基准 × 生成时 scale（等比例）：每次改键都从原始基准重算，
		// 目标 = baseScale / 生成时scale × 新scale。与"当前 scale 是否已等于目标"比较，
		// 避免第二次改键时因 want == 生成时scale 提前 return（滚动箭头停在第一次缩放的大小）。
		var targetX:Float = n.baseScaleX / n.genStrumScale * want;
		if (Math.abs(n.scale.x - targetX) < 0.001) return;
		n.scale.x = targetX;
		// head 音符 x/y 等比（避免高键→低键时只改宽导致箭头变扁）；
		// sustain tail 的 scale.y 是长条长度（baseScale 后又经长条逻辑调整），只等比 x，不破坏长度。
		if (!n.isSustainNote) n.scale.y = n.baseScaleY / n.genStrumScale * want;
		n.updateHitbox();
		// 渲染锚点与重建后的 strum 保持一致（strum 构造时 centerOffsets/centerOrigin 按当前 scale 校准；
		// 音符只改 scale 会保留旧 scale 的 offset/origin，多键缩放下箭头/长条相对 strum 整体偏移）。
		n.centerOffsets();
		n.centerOrigin();
		// sustain 的 offsetX 在构造时按生成时 scale 一次性算出（正比于 scale.x），
		// followStrumNote 每帧用 x = strumX + offsetX 定位长条；改键改了 scale.x 却不重算 offsetX，
		// 会导致长条（含 holdend）整体横向偏移，而 holdcover/滚动箭头不依赖 offsetX 故正常。
		if (n.isSustainNote) n.offsetX = n.baseOffsetX / n.genStrumScale * want;
	}

	// 重排场上/待生成音符的 x 位置（change keycount 事件后调用）
	public function relayoutNotes():Void
	{
		for (note in unspawnNotes)
			if (note != null && note.animation != null)
				relayoutNoteX(note);
		for (note in notes)
			if (note != null && note.animation != null)
				relayoutNoteX(note);
	}

	private function relayoutNoteX(n:Note):Void
	{
		var cols:Int = n.mustPress ? totalColumns : opponentColumns;
		var sideScale:Float = n.mustPress ? playerStrumScale : opponentStrumScale;
		if (cols == 4)
		{
			if (n.mustPress) n.x = STRUM_X + 50 + Note.swagWidth * n.noteData + FlxG.width / 2;
			else if (ClientPrefs.data.middleScroll) n.x = STRUM_X + 50 + Note.swagWidth * n.noteData + 310 + (n.noteData > 1 ? FlxG.width / 2 + 25 : 0);
			else n.x = STRUM_X + 50 + Note.swagWidth * n.noteData;
		}
		else
		{
			var spacing:Float = sideSpacing(cols, sideScale);
			n.x = sideGroupLeftX(cols, spacing, n.mustPress) + spacing * n.noteData;
		}
	}

	override function openSubState(SubState:FlxSubState)
	{
		stagesFunc(function(stage:BaseStage) stage.openSubState(SubState));
		if (paused)
		{
			if (FlxG.sound.music != null)
			{
				FlxG.sound.music.pause();
				vocals.pause();
				opponentVocals.pause();
			}
			FlxTimer.globalManager.forEach(function(tmr:FlxTimer) if(!tmr.finished) tmr.active = false);
			FlxTween.globalManager.forEach(function(twn:FlxTween) if(!twn.finished) twn.active = false);
		}

		super.openSubState(SubState);
	}

	public var canResync:Bool = true;
	override function closeSubState()
	{
		super.closeSubState();
		
		stagesFunc(function(stage:BaseStage) stage.closeSubState());
		if (paused)
		{
			if (FlxG.sound.music != null && !startingSong && canResync)
			{
				resyncVocals();
			}
			FlxTimer.globalManager.forEach(function(tmr:FlxTimer) if(!tmr.finished) tmr.active = true);
			FlxTween.globalManager.forEach(function(twn:FlxTween) if(!twn.finished) twn.active = true);

			paused = false;
			callOnScripts('onResume');
			resetRPC(startTimer != null && startTimer.finished);
			runSongSyncThread();
		}
	}

	#if DISCORD_ALLOWED
	override public function onFocus():Void
	{
		super.onFocus();
		if (!paused && health > 0)
		{
			resetRPC(Conductor.songPosition > 0.0);
		}
		shutdownThread = false;
		runSongSyncThread();
	}

	override public function onFocusLost():Void
	{
		super.onFocusLost();
		if (!paused && health > 0 && autoUpdateRPC)
		{
			DiscordClient.changePresence(detailsPausedText, SONG.song + " (" + storyDifficultyText + ")", iconP2.getCharacter());
		}
		shutdownThread = true;
	}
	#end

	// Updating Discord Rich Presence.
	public var autoUpdateRPC:Bool = true; //performance setting for custom RPC things
	function resetRPC(?showTime:Bool = false)
	{
		#if DISCORD_ALLOWED
		if(!autoUpdateRPC) return;

		if (showTime)
			DiscordClient.changePresence(detailsText, SONG.song + " (" + storyDifficultyText + ")", iconP2.getCharacter(), true, songLength - Conductor.songPosition - ClientPrefs.data.noteOffset);
		else
			DiscordClient.changePresence(detailsText, SONG.song + " (" + storyDifficultyText + ")", iconP2.getCharacter());
		#end
	}

	function resyncVocals():Void
	{
		if(finishTimer != null) return;

		trace('resynced vocals at ' + Math.floor(Conductor.songPosition));

		FlxG.sound.music.play();
		#if FLX_PITCH FlxG.sound.music.pitch = playbackRate; #end
		Conductor.songPosition = FlxG.sound.music.time + Conductor.offset;

		var checkVocals = [vocals, opponentVocals];
		for (voc in checkVocals)
		{
			if (FlxG.sound.music.time < vocals.length)
			{
				voc.time = FlxG.sound.music.time;
				#if FLX_PITCH voc.pitch = playbackRate; #end
				voc.play();
			}
			else voc.pause();
		}
	}

	public var paused:Bool = false;
	public var canReset:Bool = true;
	var startedCountdown:Bool = false;
	var canPause:Bool = true;
	var freezeCamera:Bool = false;
	var allowDebugKeys:Bool = true;

	override public function update(elapsed:Float)
	{
		// 分帧延迟初始化：将非关键操作分散到后续帧，避免 create() 中长时间阻塞主线程
		if (_deferredInitStep >= 0)
		{
			switch (_deferredInitStep)
			{
				case 0:
					cachePopUpScore(); // 第1帧：缓存评分弹窗图片
				case 1:
					Paths.clearUnusedMemory(); // 第2帧：GC清理（画面已渲染后执行）
				default:
					_deferredInitStep = -2; // 完成
			}
			_deferredInitStep++;
		}

		// Kade 风格 ms 文本淡出：按 240Hz 步进衰减（1/240 秒一步，每步 -0.005，约 0.83 秒淡完），与帧率解耦
		if (msTimingShownActive)
		{
			msTimeTxtFadeAccum += elapsed;
			while (msTimingShownActive && msTimeTxtFadeAccum >= 1 / 240)
			{
				msTimeTxtFadeAccum -= 1 / 240;
				msTimeTxt.alpha -= 0.01;
				if (msTimeTxt.alpha <= 0)
				{
					msTimeTxt.alpha = 0;
					msTimingShownActive = false;
					// 归零运动，避免淡出结束后仍在屏幕外继续漂移
					msTimeTxt.velocity.set(0, 0);
					msTimeTxt.acceleration.set(0, 0);
				}
			}
			if (msTimeTxtFadeAccum > 0.1) msTimeTxtFadeAccum = 0; // 卡顿后不追帧
		}

		// 移动端右上角暂停按钮：跟随移动控制整体可见性（暂停/结算时会自动隐藏）
		if (mobilePauseBtn != null)
			mobilePauseBtn.visible = controls.mobileC && mobileControls.instance.visible;

		// Ghost Tap 冷却递减：whenSinging 模式启用（集成 Funkin 防连按），屏幕上无玩家音符时才开始递减
		if (ClientPrefs.data.ghostTappingMode == 'whenSinging' && !paused && !hasPlayerNotesOnScreen())
		{
			for (i in 0...4)
			{
				if (ghostTapTimer[i] > 0)
				{
					ghostTapTimer[i] -= elapsed * 1000;
					if (ghostTapTimer[i] < 0) ghostTapTimer[i] = 0;
				}
			}
		}

		// 回放模式下的自动按键逻辑
		if(isReplaying && startedCountdown && !paused && !endingSong)
		{
			// 清理虚拟输入的just状态，确保每帧只触发一次
			Controls.instance.clearVirtualJustStates();
			
			// 检查是否需要抬起按键（检查当前索引及之前的所有动作）
			for (i in 0...currentReplayIndex)
			{
				var action = replayData[i];
				// 检查是否有releaseTime且已到时间（ghost操作需要至少50ms的延迟）
				if(action.releaseTime != null && Conductor.songPosition >= action.releaseTime)
				{
					// 如果是音符按键
					if(action.key < NON_NOTE_KEY_OFFSET)
					{
						// replayData.key 存录制时的绝对值；当前谱面键数变化时动态取模（与 remapNote 规则一致）
						var rkeyR:Int = action.key % sideCols();
						replayHeldKeys[rkeyR] = false;

						// 特性1：回放中同样在松手时立刻判定 miss，保持与实时游玩一致
						if(guitarHeroSustains && holdReleaseInstantMiss)
							tryInstantSustainMiss(rkeyR);

						// 特性2：回放中同样在松手时判定长条尾部
						if(guitarHeroSustains && holdTailJudge)
							tryTailJudgeOnRelease(rkeyR);

						// 同步虚拟输入状态到Controls，让模组能够检测到按键释放
						var keyNameR = keysArray[rkeyR];
						Controls.instance.setVirtualKeyState(keyNameR, false);
						// 播放static动画
						var sprR:StrumNote = playerSideStrums().members[rkeyR];
						if(sprR != null)
						{
							sprR.playAnim('static');
							sprR.resetAnim = 0;
						}
					}
					else
					{
						// 非音符按键抬起：向舞台派发合成 KEY_UP 事件并标记为已处理
						var actualKey:Int = action.key - NON_NOTE_KEY_OFFSET;
						replayHeldNonNoteKeys.set(action.key, false);
						if(FlxG.stage != null)
						{
							var ev:KeyboardEvent = new KeyboardEvent(KeyboardEvent.KEY_UP, false, false, 0, actualKey);
							FlxG.stage.dispatchEvent(ev);
						}
					}
					action.releaseTime = null; // 标记为已处理
				}
			}
			
			// 检查长按音符，保持按键按下状态
			if(guitarHeroSustains)
			{
				// 复用缓冲数组，避免每帧分配
			_holdBuffer.splice(0, _holdBuffer.length);
			for (i in 0...keysArray.length)
				_holdBuffer.push(replayHeldKeys[i]);

				if(notes.length > 0) {
					for (n in notes) {
						if (n == null || !n.exists) continue; // 帧末批量模式下跳过本帧已销毁的“死音符”
						var canHit:Bool = (!strumsBlocked[n.noteData] && n.canBeHit
							&& isPlayerNote(n) && !n.tooLate && !n.wasGoodHit && !n.blockHit);

						if (canHit && n.isSustainNote) {
							var released:Bool = !replayHeldKeys[n.noteData];
							// 特性2：回放中同样跳过最后一个尾音的按住自动命中（改在松手时判定）
							var isLastTail:Bool = (holdTailJudge && guitarHeroSustains && !cpuControlled
								&& n.parent != null && n.parent.tail.length > 0
								&& n.parent.tail[n.parent.tail.length - 1] == n);
							if (!released && n.parent != null && n.parent.wasGoodHit && !isLastTail) {
								// 持续按下长按音符
								goodNoteHit(n);
							}
						}
					}
				}
			}
			
			while(currentReplayIndex < replayData.length)
			{
				var replayAction = replayData[currentReplayIndex];
				// 检查是否到了按下时间
				if(Conductor.songPosition >= replayAction.time)
				{
					// 根据回放数据执行相应的按键
					if(replayAction.key < NON_NOTE_KEY_OFFSET)
					{
						if(replayAction.judge == 'ghost')
						{
							var rkey:Int = replayAction.key % sideCols();
							// 标记按键为按下状态
							replayHeldKeys[rkey] = true;
							
							// 同步虚拟输入状态到Controls，让模组能够检测到按键
							var keyName = keysArray[rkey];
							Controls.instance.setVirtualKeyState(keyName, true);

							// 空按 - 播放pressed动画
							var spr:StrumNote = playerSideStrums().members[rkey];
							if(spr != null && strumsBlocked[rkey] != true && (spr.animation.curAnim == null || spr.animation.curAnim.name != 'confirm'))
							{
								spr.playAnim('pressed');
								spr.resetAnim = 0; // 不自动重置，由按键释放时重置
							}

							// 根据当前的ghostTapping设置决定是否调用noteMissPress和onGhostTap
							handleGhostTap(rkey);

							// 调用onKeyPress回调（与正常模式保持一致）
							callOnScripts('onKeyPress', [rkey]);
						}
						else if(replayAction.judge == 'miss')
						{
							// Miss，不需要按键
						}
							else
							{
								// 标记按键为按下状态
								var rkey:Int = replayAction.key % sideCols();
								replayHeldKeys[rkey] = true;
								
								// 同步虚拟输入状态到Controls，让模组能够检测到按键
								var keyName = keysArray[rkey];
								Controls.instance.setVirtualKeyState(keyName, true);
						
								// 播放pressed动画（会在goodNoteHit中被confirm覆盖）
							var spr:StrumNote = playerSideStrums().members[rkey];
							if(spr != null && strumsBlocked[rkey] != true)
							{
								spr.playAnim('pressed');
								spr.resetAnim = 0;
							}
						
							// 正常按键，找到对应的音符并打击
							var targetNotes:Array<Note> = notes.members.filter(function(n:Note):Bool {
								// 使用小容差（5ms）来匹配音符，避免浮点数精度问题
								return n != null && n.exists && isPlayerNote(n) && n.noteData == rkey && !n.wasGoodHit
								&& Math.abs(n.strumTime - replayAction.noteTime) < 5;
							});
							for(note in targetNotes)
							{
								// 设置延迟覆盖值，确保使用原始记录的延迟
								if(replayAction.late != null)
								{
									currentNoteDelayOverride = replayAction.late;
								}
								goodNoteHit(note);
							}
						}
					}
					else
					{
						// 非音符按键按下：向舞台派发合成 KEY_DOWN 事件
						var actualKey:Int = replayAction.key - NON_NOTE_KEY_OFFSET;
						replayHeldNonNoteKeys.set(replayAction.key, true);
						if(FlxG.stage != null)
						{
							var dev:KeyboardEvent = new KeyboardEvent(KeyboardEvent.KEY_DOWN, false, false, 0, actualKey);
							FlxG.stage.dispatchEvent(dev);
						}
						if(!keysPressed.contains(actualKey)) keysPressed.push(actualKey);
					}
					currentReplayIndex++;
				}
				else
				{
					// 还没到时间，跳出循环
					break;
				}
			}
		}
		
		if(!inCutscene && !paused && !freezeCamera) {
			FlxG.camera.followLerp = 0.04 * cameraSpeed * playbackRate;
			var idleAnim:Bool = (boyfriend.getAnimationName().startsWith('idle') || boyfriend.getAnimationName().startsWith('danceLeft') || boyfriend.getAnimationName().startsWith('danceRight'));
			if(!startingSong && !endingSong && idleAnim) {
				boyfriendIdleTime += elapsed;
				if(boyfriendIdleTime >= 0.15) { // Kind of a mercy thing for making the achievement easier to get as it's apparently frustrating to some playerss
					boyfriendIdled = true;
				}
			} else {
				boyfriendIdleTime = 0;
			}
		}
		else FlxG.camera.followLerp = 0;
		callOnScripts('onUpdate', [elapsed]);
		// Leather modchart 事件：update(elapsed)（LE 原版每帧调用，与 Psych onUpdate 并存）
		callOnLeatherScripts('update', [elapsed]);
		ExtraFunctions.frameCount++;
		super.update(elapsed);

		if (ClientPrefs.data.iconbopstyle == "Kathy") {
        iconP1.angle = FlxMath.lerp(iconP1.angle, iconP1TargetAngle, elapsed / iconP1AngleLerpSpeed);
        iconP2.angle = FlxMath.lerp(iconP2.angle, iconP2TargetAngle, elapsed / iconP2AngleLerpSpeed);
   	 	}

		setOnScripts('curDecStep', curDecStep);
		setOnScripts('curDecBeat', curDecBeat);

		if(botplayTxt != null && botplayTxt.visible && ClientPrefs.data.botplayStyle != 'Kade') {
			botplaySine += 180 * elapsed;
			botplayTxt.alpha = 1 - Math.sin((Math.PI * botplaySine) / 180);
		} else botplayTxt.alpha = 1;

		// 更新回放文本可见性
		if(replayTxt != null) {
			replayTxt.visible = isReplaying;
		}

		if (controls.PAUSE #if android || FlxG.android.justReleased.BACK #end && startedCountdown && canPause)
		{
			var ret:Dynamic = callOnScripts('onPause', null, true);
			if(ret != LuaUtils.Function_Stop) {
				openPauseMenu();
			}
		}

		if(!endingSong && !inCutscene && allowDebugKeys && !isCommandLineMode)
		{
			// 仅在开发者模式启用时，才允许从游戏中直接进入编辑器界面
			if (controls.justPressed('debug_1') && ClientPrefs.data.developer)
				openChartEditor();
			else if (controls.justPressed('debug_2') && ClientPrefs.data.developer)
				openCharacterEditor();
			else if (controls.justPressed('debug_3'))
				eventDebugGroup.visible = !eventDebugGroup.visible;
			else if (controls.justPressed('debug_4'))
			{
				cpuControlled = !cpuControlled;
				botplayTxt.visible = cpuControlled;
			}

		}

		var allowOverflow:Bool = ClientPrefs.data.smoothHP && ClientPrefs.data.healthOverflow;
		if (healthBar.bounds.max != null)
		{
			if (!allowOverflow && health > healthBar.bounds.max)
			{
				// 未开启超满血：压回原生上限 2
				health = healthBar.bounds.max;
			}
			else if (allowOverflow && health > healthBar.bounds.max)
			{
				// 超满血：用 lerp 平滑过渡回 2（缓出，越接近 2 越慢），最终落回干净的 2.00
				var k:Float = healthOverflowDrain; // 回落速度系数（PlayState 公有变量，可运行时修改）
				var t:Float = Math.min(1, elapsed * k);
				health = FlxMath.lerp(health, healthBar.bounds.max, t);
				if (health - healthBar.bounds.max <= 0.005)
					health = healthBar.bounds.max; // 接近 2 时直接锁定为 2.00
				else
					health = FlxMath.roundDecimal(health, 2);
			}
		}

		// 平滑血条逻辑
		if (ClientPrefs.data.smoothHP)
		{
			smoothHealth += (health - smoothHealth) * elapsed * smoothHPSpeed;
			if (Math.abs(smoothHealth - health) < 0.005)
				smoothHealth = health;
			healthBar.percent = FlxMath.remapToRange(smoothHealth, healthBar.bounds.min, healthBar.bounds.max, 0, 100);
		}
		else
		{
			healthBar.percent = FlxMath.remapToRange(health, healthBar.bounds.min, healthBar.bounds.max, 0, 100);
		}

		updateIconsScale(elapsed);
		updateIconsPosition();

		if (startedCountdown && !paused)
		{
			Conductor.songPosition += elapsed * 1000 * playbackRate;
			if (Conductor.songPosition >= Conductor.offset)
			{
				var _syncK:Float = ClientPrefs.data.useFrameAdaptiveSync
				? 5 * (ClientPrefs.data.framerate / 60) * ClientPrefs.data.syncSpeedMultiplier
				: 5;
			Conductor.songPosition = FlxMath.lerp(FlxG.sound.music.time + Conductor.offset, Conductor.songPosition, Math.exp(-elapsed * _syncK));
				var timeDiff:Float = Math.abs((FlxG.sound.music.time + Conductor.offset) - Conductor.songPosition);
				if (timeDiff > 1000 * playbackRate)
					Conductor.songPosition = Conductor.songPosition + 1000 * FlxMath.signOf(timeDiff);
			}

			// 线性 BPM 过渡：实时刷新全局 BPM / 节拍，供图标缩放、脚本等使用
			Conductor.bpm = Conductor.getBPMFromSeconds(Conductor.songPosition).bpm;
		}


		if (startingSong)
		{
			if (startedCountdown && Conductor.songPosition >= Conductor.offset)
				startSong();
			else if(!startedCountdown)
				Conductor.songPosition = -Conductor.crochet * 5 + Conductor.offset;
		}
		else if (!paused && updateTime)
		{
			var curTime:Float = Math.max(0, Conductor.songPosition - ClientPrefs.data.noteOffset);
			songPercent = (curTime / songLength);

			if (ClientPrefs.data.timebarStyle == "Leather" || ClientPrefs.data.timebarStyle == "Leather (Legacy)")
			{
				// 计算剩余时间
				var timeLeft:Float = Math.max(0, songLength - curTime);
				var secondsLeft:Int = Math.floor(timeLeft / 1000);
				if (secondsLeft < 0)
					secondsLeft = 0;

				// 构建显示文本
				var timeString:String = FlxStringUtil.formatTime(secondsLeft, false);
				var kadeSongName:String = (ClientPrefs.data.timebarStyle == "Kade") ? SONG.song.replace(" ", "-") : SONG.song;
				var displayText:String = kadeSongName + " ~ " + Difficulty.getString().toUpperCase() + " (" + timeString + ")";

				// 添加模式标识
				if (cpuControlled)
					displayText += " (BOT)";
				if (practiceMode)
					displayText += " (NO DEATH)";

				timeTxt.text = displayText;
			}
			else if (ClientPrefs.data.timeBarType != 'Song Name' && ClientPrefs.data.timebarStyle != "Kade")
			{
				var songCalc:Float = (songLength - curTime);
				if (ClientPrefs.data.timeBarType == 'Time Elapsed')
					songCalc = curTime;

				var secondsTotal:Int = Math.floor(songCalc / 1000);
				if (secondsTotal < 0)
					secondsTotal = 0;

				timeTxt.text = FlxStringUtil.formatTime(secondsTotal, false);
			}
		}

		//if (camZooming)
		//{
			//FlxG.camera.zoom = FlxMath.lerp(defaultCamZoom, FlxG.camera.zoom, Math.exp(-elapsed * 3.125 * camZoomingDecay * playbackRate));
    		/*if(ClientPrefs.data.hudSize != 1.0) 	targetZoom = ClientPrefs.data.hudSize;*/
    		//camHUD.zoom = FlxMath.lerp(targetZoom, camHUD.zoom, Math.exp(-elapsed * 3.125 * camZoomingDecay * playbackRate));
		//}
		if (camZooming)
		{
    		// 先定义一个映射表，或者用简单的switch/if
    		var styleNum:Float = switch (ClientPrefs.data.hudZoomStyle)
    		{
        		case "Kade": 8;
        		case "Fast": 12;
        		case "Slow": 1.5;
        		default: 3.125; // 默认
    		}
    		var zoomLerp = Math.exp(-elapsed * styleNum * camZoomingDecay * playbackRate);
    		var hudLerp = zoomLerp;
    		FlxG.camera.zoom = FlxMath.lerp(defaultCamZoom, FlxG.camera.zoom, zoomLerp);
    		camHUD.zoom = FlxMath.lerp(targetZoom, camHUD.zoom, hudLerp);
		}

		FlxG.watch.addQuick("secShit", curSection);
		FlxG.watch.addQuick("beatShit", curBeat);
		FlxG.watch.addQuick("stepShit", curStep);

		// RESET = Quick Game Over Screen
		if (!ClientPrefs.data.noReset && controls.RESET && canReset && !inCutscene && startedCountdown && !endingSong)
		{
			health = 0;
			trace("RESET = True");
		}
		doDeathCheck();

		// 每帧生成预算计数清零（maxNotesPerFrame）
		notesSpawnedThisFrame = 0;

		if (useOptimizedLoading)
		{
			// 优化模式
			if (notesAddedCount < unspawnNotesPreloaded.length)
			{
				while (notesAddedCount < unspawnNotesPreloaded.length)
				{
					var noteData:PreloadedChartNote = unspawnNotesPreloaded[notesAddedCount];
					
					// 计算 spawning time
					var time:Float = spawnTime * playbackRate;
					if(songSpeed < 1) time /= songSpeed;
					
					// 我们先假设 multSpeed 为 1！
					if (noteData.strumTime - Conductor.songPosition >= time) break;

					// #4 过期即时结算判定：非 sustain 且已越过 noteKillOffset 的音符稍后直接结算，不入渲染组。
					// 优化模式下仍需构建对象以维持 sustain 的 parent/tail 引用链，故保留构建、仅省去入组与逐帧开销。
					var instantExpire:Bool = effectiveInstantResolve() && !noteData.isSustainNote
						&& (Conductor.songPosition - noteData.strumTime > noteKillOffset);

				// #2 每帧生成预算：仅约束需要正常显示的音符；过期音符不受预算限制以便快速清空积压。
				// sustain 段落必须一次性构建完，避免预算打断同一长按、导致后续子段引用到已销毁的 head 而崩溃。
				if (!instantExpire && !noteData.isSustainNote && ClientPrefs.data.maxNotesPerFrame > 0
					&& notesSpawnedThisFrame >= ClientPrefs.data.maxNotesPerFrame)
					break;

				// 安全读取已生成音符：spawnedNotes 中的对象可能因命中/错过而被 invalidateNote 销毁
				// （destroy 后 animation 被置空）。若直接引用，后续音符在构造时访问已销毁的 prevNote 就会崩溃。
				// 故读取时校验其是否仍存活，已失效的（animation 为 null）当作 null 处理。
				var oldNote:Note = null;
				if(noteData.previousNoteIndex >= 0 && noteData.previousNoteIndex < notesAddedCount) {
					var p:Note = spawnedNotes[noteData.previousNoteIndex];
					if (p != null && p.animation != null) oldNote = p;
				}
				var parentNote:Note = null;
				if(noteData.parentIndex >= 0 && noteData.parentIndex < notesAddedCount) {
					var p:Note = spawnedNotes[noteData.parentIndex];
					if (p != null && p.animation != null) parentNote = p;
				}
					
					// 创建 Note 对象，完全按照传统模式！
					// noteData 按当前列数取模（原生 4 键下等价于原值）
					var remappedData:Int = noteData.rawColumn % totalColumns;
					var note:Note = spawnNote(noteData.strumTime, remappedData, oldNote, noteData.isSustainNote);
					
					// 设置基本属性
					note.animSuffix = noteData.animSuffix;
					note.mustPress = noteData.rawColumn < totalColumns;
					note.noteColumnRaw = noteData.rawColumn;
					note.gfNote = noteData.gfNote;
					note.sustainLength = noteData.sustainLength;
					note.noteType = noteData.noteType;
					note.scrollFactor.set();
					// 应用预加载数据中的提前命中窗口倍率（供尾条判定优化方案B使用）
					note.earlyHitMult = noteData.earlyHitMult;
					
				// 处理 parent 关系
				if (noteData.isSustainNote && parentNote != null) {
					note.parent = parentNote;
					note.parent.tail.push(note);
				}
				
				// 处理 correctionOffset
				if (noteData.isSustainNote) {
					if (parentNote != null) {
						note.correctionOffset = parentNote.height / 2;
					}
						
						// 处理 oldNote 的 scale 调整
						if (oldNote != null && oldNote.isSustainNote && noteData.needsOldNoteScaleAdjust) {
							if (!noteData.isPixelStage) {
								oldNote.scale.y *= Note.SUSTAIN_SIZE / oldNote.frameHeight * Note.kadeHoldGapScale();
								oldNote.scale.y /= playbackRate;
								oldNote.resizeByRatio(noteData.curStepCrochet / Conductor.stepCrochet);
							} else {
								oldNote.scale.y /= playbackRate;
								oldNote.resizeByRatio(noteData.curStepCrochet / Conductor.stepCrochet);
							}
						}
						
						// 处理 downScroll correction
						if(noteData.hasDownScrollCorrection && !noteData.isPixelStage) {
							note.correctionOffset = 0;
						}
					}
					
					// 应用位置偏移
					note.x += noteData.posOffsetX;
					note.y += noteData.posOffsetY;
					
					// 保存到跟踪数组
					spawnedNotes[notesAddedCount] = note;
					note.preloadIndex = notesAddedCount;

				// #4 过期即时结算：越过 noteKillOffset 的音符按 sick 结算（对手方直接跳过），
				// 不加入任何渲染组、不逐帧绘制，也不产生视觉开销（详见 instantResolveAsSick）
				if (instantExpire)
				{
					note.spawned = true;
					note.active = note.visible = false;
					if (note.mustPress && !note.ignoreNote && !endingSong)
						instantResolveAsSick(note);
					// [OOM FIX] 过期音符结算完毕后立即销毁并解除 spawnedNotes 强引用。
					// 否则对手方过期音符既不入渲染组、也永不被 invalidateNote 回收，会随整曲
					// 单向累积，最终撑爆 Java 堆（崩溃点 PlayState.update:3656 的 OutOfMemoryError）。
					// 后续循环通过 previousNoteIndex/parentIndex 引用它时已做 null + animation 校验，置空安全。
					note.destroy();
					spawnedNotes[notesAddedCount] = null;
					notesAddedCount++;
					continue;
				}
					
					// 生成音符，根据 holdNoteBehind 设置调整添加顺序
					if (ClientPrefs.data.holdNoteBehind) {
						if (note.isSustainNote) {
							// 如果是 hold note，添加到 holdNotes 组
						if (ClientPrefs.data.noteOptimization) holdNotes.add(note);
						else holdNotes.insert(0, note);
					} else {
						// 如果是普通 note，添加到 normalNotes 组
						if (ClientPrefs.data.noteOptimization) normalNotes.add(note);
						else normalNotes.insert(0, note);
					}
					// 同时也添加到主 notes 组，保持 modchart 兼容性
					if (ClientPrefs.data.noteOptimization) notes.add(note);
					else notes.insert(0, note);
				} else {
					// 保持原来的行为
					if (ClientPrefs.data.noteOptimization) notes.add(note);
					else notes.insert(0, note);
					}
					note.ensureCurrentSkin(); // 按当前皮肤懒加载一次
					note.spawned = true;
					
					// 调用回调（关闭逐音符脚本时跳过）
					if (!effectiveDisableNoteLua())
					{
						callOnLuas('onSpawnNote', [luaNoteIndex(note), note.noteData, note.noteType, note.isSustainNote, note.strumTime]);
						callOnHScript('onSpawnNote', [note]);
					}

					notesSpawnedThisFrame++;
					notesAddedCount++;
				}
			}
		}
		else
		{
			// 传统模式
			if (unspawnNotes[0] != null)
			{
				var time:Float = spawnTime * playbackRate;
				if(songSpeed < 1) time /= songSpeed;
				if(unspawnNotes[0].multSpeed < 1) time /= unspawnNotes[0].multSpeed;

				while (unspawnNotes.length > 0 && unspawnNotes[0].strumTime - Conductor.songPosition < time)
				{
					var dunceNote:Note = unspawnNotes[0];

					// #4 过期即时结算：非 sustain、无 sustain 子节点且已越过 noteKillOffset 的音符直接结算，不入渲染组
					if (effectiveInstantResolve() && !dunceNote.isSustainNote && dunceNote.tail.length == 0
						&& (Conductor.songPosition - dunceNote.strumTime > noteKillOffset))
					{
						if (dunceNote.mustPress && !dunceNote.ignoreNote && !endingSong)
							instantResolveAsSick(dunceNote);
						dunceNote.active = dunceNote.visible = false;
						dunceNote.kill();
						unspawnNotes.splice(0, 1);
						continue;
					}

					// #2 每帧生成预算：达到上限则本帧停止生成，剩余音符延后到下一帧（音符不会丢失）
					if (ClientPrefs.data.maxNotesPerFrame > 0
						&& notesSpawnedThisFrame >= ClientPrefs.data.maxNotesPerFrame)
						break;

					// 根据 holdNoteBehind 设置调整添加顺序
					if (ClientPrefs.data.holdNoteBehind) {
						if (dunceNote.isSustainNote) {
							// 如果是 hold note，添加到 holdNotes 组
							holdNotes.insert(0, dunceNote);
						} else {
							// 如果是普通 note，添加到 normalNotes 组
							normalNotes.insert(0, dunceNote);
						}
					// 同时也添加到主 notes 组，保持 modchart 兼容性
					notes.insert(0, dunceNote);
				} else {
					// 保持原来的行为
					notes.insert(0, dunceNote);
				}
				dunceNote.preloadIndex = noteSpawnSeq++;
				dunceNote.ensureCurrentSkin(); // 按当前皮肤懒加载一次
				dunceNote.spawned = true;



					// 调用回调（关闭逐音符脚本时跳过）
					if (!effectiveDisableNoteLua())
					{
						callOnLuas('onSpawnNote', [luaNoteIndex(dunceNote), dunceNote.noteData, dunceNote.noteType, dunceNote.isSustainNote, dunceNote.strumTime]);
						callOnHScript('onSpawnNote', [dunceNote]);
					}

					notesSpawnedThisFrame++;
					var index:Int = unspawnNotes.indexOf(dunceNote);
					unspawnNotes.splice(index, 1);
				}
			}
		}

		{
			// 原地过滤：只保留最近 1000ms 内的命中时间戳，避免 Array.remove() 的 O(n) 移动开销
			var now:Float = haxe.Timer.stamp() * 1000;
			var writeIdx:Int = 0;
			for (readIdx in 0...notesHitArray.length)
			{
				if (notesHitArray[readIdx] + 1000 >= now)
				{
					if (writeIdx != readIdx)
						notesHitArray[writeIdx] = notesHitArray[readIdx];
					writeIdx++;
				}
			}
			while (notesHitArray.length > writeIdx)
				notesHitArray.pop();
			nps = notesHitArray.length;
			if (nps > maxNPS)
				maxNPS = nps;
			if (ClientPrefs.data.showNPS && npsCheck != nps && ClientPrefs.data.scoretxtstyle == 'Kathy' || ClientPrefs.data.scoretxtstyle == 'Kade') {
				npsCheck = nps;
			    updateScoreText();
			}
			setOnLuas('nps', nps);
			setOnLuas('maxFPS', maxNPS);	

		}

		if (ClientPrefs.data.timebarStyle == 'Leather')
		{
			// 使用FlxColor.interpolate进行颜色插值
			timeBarLeftColor = FlxColor.interpolate(timeBarLeftColor, timeBarLeftColorTarget, elapsed * 5);
			timeBarRightColor = FlxColor.interpolate(timeBarRightColor, timeBarRightColorTarget, elapsed * 5);
			timeBar.setColors(timeBarRightColor, timeBarLeftColor); //不是，timebar的颜色是反着来的吗？
		}
		else if (ClientPrefs.data.timebarStyle == 'Leather (Legacy)')
		{
			// 默认始终为青色，不更新
			// 开启时间条渐变后，颜色交由渐变逻辑（applyGradient）处理，这里不再强制青色覆盖
			if (!ClientPrefs.data.timeBarGradient)
				timeBar.setColors(FlxColor.CYAN, FlxColor.BLACK);
		}

		if (generatedMusic)
		{
			if(!inCutscene)
			{
				if(!cpuControlled)
					keysCheck();
				else
					playerDance();

				// 特性3：长条命中期间持续加分（参考原版Funkin）
				if(holdScoreBonus) updateHoldScore(elapsed);

				if(notes.length > 0)
				{
					if(startedCountdown)
					{
						if (SONG != null)
						{
							var fakeCrochet:Float = (60 / SONG.bpm) * 1000;
							var i:Int = 0;
							while(i < notes.length)
							{
								var daNote:Note = notes.members[i];
								// 跳过 null 及帧末批量 compact 模式下一帧内已销毁但尚未剔除的“死音符”。
								if(daNote == null || !daNote.exists)
								{
									i++;
									continue;
								}

								// 渲染归组只按原版几何关系：bf 音符(mustPress)在右侧 playerStrums，dad 音符在左侧 opponentStrums。
								// 不随 playOpponent 改变——playOpponent 时你打的音符(dad 侧)天然就在左侧对手箭头上。
								var strumGroup:FlxTypedGroup<StrumNote> = playerStrums;
								if(!daNote.mustPress) strumGroup = opponentStrums;

								var strum:StrumNote = strumGroup.members[daNote.noteData];
								if (strum == null)
								{
									// 该轨已无对应箭头（异常谱面），隐藏音符避免报错。
									daNote.visible = false;
									i++;
									continue;
								}
								// 诊断：每 120 帧打印列0/列5 的 note 与 strum 渲染参数（x/offset/宽），定位视觉错位源
								diagFrame++;
								if (diagFrame % 120 == 0 && !daNote.isSustainNote)
								{
									var diagCol:Int = daNote.noteData;
									if (diagCol == 0 || diagCol == 5)
									{
										/*trace('[EK] diag col=' + diagCol + ' mustPress=' + daNote.mustPress
											+ ' noteX=' + daNote.x + ' noteOff=' + daNote.offset.x + ' noteW=' + daNote.width
											+ ' strumX=' + strum.x + ' strumOff=' + strum.offset.x + ' strumW=' + strum.width
											+ ' noteCenter=' + (daNote.x + daNote.offset.x) + ' strumCenter=' + (strum.x + strum.offset.x));*/
									}
								}
								daNote.followStrumNote(strum, fakeCrochet, songSpeed / playbackRate);

								if(isPlayerNote(daNote))
								{
									// 长条头部也必须在到达 strumTime 后才首次命中，避免提前窗口导致
									// 对手箭头飞溅/holdcover 在真实判定点之前就触发（尾段 earlyHitMult=0 不受影响）。
									if(cpuControlled && !daNote.blockHit && daNote.canBeHit && daNote.strumTime <= Conductor.songPosition)
										goodNoteHit(daNote);
								}
								else if (!daNote.hitByOpponent && !daNote.ignoreNote && daNote.canBeHit && daNote.strumTime <= Conductor.songPosition)
								{
									opponentNoteHit(daNote);
									if (!daNote.isSustainNote) daNote.wasGoodHit = true;
								}
								else if (daNote.wasGoodHit && !daNote.hitByOpponent && !daNote.ignoreNote)
									opponentNoteHit(daNote);

								if(daNote.isSustainNote && strum.sustainReduce) daNote.clipToStrumNote(strum);

								// Kill extremely late notes and cause misses
								if (Conductor.songPosition - daNote.strumTime > noteKillOffset)
								{
									if (isPlayerNote(daNote) /*&& !cpuControlled */&& !daNote.ignoreNote && !endingSong && (daNote.tooLate || !daNote.wasGoodHit))
										noteMiss(daNote);

									daNote.active = daNote.visible = false;
									invalidateNote(daNote);
								}
								// 提前剔除已错过音符的渲染（低延迟/性能模式）：
								// 已错过且离开屏幕（或逼近 kill 阈值）的音符提前隐藏，减少 SPAM 谱下大量"死音符"的绘制负担。
								// 注意仍保留其在 notes 组内，错过判定/漏击仍由上面的 kill 逻辑在 noteKillOffset 处统一处理。
								else if (effectiveHideMissed() && daNote.tooLate && !daNote.ignoreNote && (daNote.active || daNote.visible))
								{
									var offscreen:Bool = (
										daNote.y > FlxG.height || daNote.y + daNote.height < 0 ||
										daNote.x > FlxG.width || daNote.x + daNote.width < 0
									);
									var extremelyLate:Bool = (Conductor.songPosition - daNote.strumTime > noteKillOffset * 0.9);
									if (offscreen || extremelyLate)
										daNote.active = daNote.visible = false;
								}

								if (ClientPrefs.data.batchCompactNotes)
									i++; // 批量模式不改数组成员，稳定前进
								else if (daNote.exists) i++; // legacy 即时 splice：exists=false 时保持索引，补偿左移
							}
						}
					}
					else
					{
						notes.forEachAlive(function(daNote:Note)
						{
							daNote.canBeHit = false;
							daNote.wasGoodHit = false;
						});
					}
				}
			}
			eventHandler.checkEventNote();
		}

		// 帧末批量 compact：batchCompactNotes 开启时销毁被延迟到帧末才真正收缩数组。
		// 一次性单遍紧凑 notes/normalNotes/holdNotes，把 SPAM 高密度谱下每颗销毁 3 次 O(n)
		// 左移（乐/MS/holdNotes）降为一帧一次的 O(n)，是销毁路径的主要 CPU 优化。
		// 生成循环在本段之前运行 → 本帧被销毁的音符不会被本帧复用，故此处剔除安全、无重复入组。
		if (ClientPrefs.data.batchCompactNotes) {
			compactNoteArray(notes.members);
			compactNoteArray(normalNotes.members);
			compactNoteArray(holdNotes.members);
		}

		#if debug
		if(!endingSong && !startingSong) {
			if (FlxG.keys.justPressed.ONE) {
				KillNotes();
				FlxG.sound.music.onComplete();
			}
			if(FlxG.keys.justPressed.TWO) { //Go 10 seconds into the future :O
				setSongTime(Conductor.songPosition + 10000);
				clearNotesBefore(Conductor.songPosition);
			}
		}
		#end

		setOnScripts('botPlay', cpuControlled);
		callOnScripts('onUpdatePost', [elapsed]);
	}

	// ============ A1: onDraw / onDrawPost 回调 ============
	override function draw():Void
	{
		callOnScripts('onDraw');
		super.draw();
		callOnScripts('onDrawPost');
	}

	// Health icon updaters
	var iconSizeResetTime:Float = 0; // 压扁风格(Squash)的恢复计时器：beat 触发后从 ICON_SQUASH_TIME 递减到 0，期间平滑恢复为正常大小
	var ICON_SQUASH_TIME:Float = 2.0; // 压扁风格恢复时长（秒），数值越大回弹越慢越柔和
	var _cachedIconSpeedMult:Float = 9; // 缓存 speedMultiplier，仅在 iconbopstyle 改变时更新，避免每帧字符串比较
	var _lastIconBopStyle:String = null; // 记录上次检查的 iconbopstyle，用于检测变更

	// V-Slice(New) 复刻 funkin 跳动用的线性补间引用，用于在连续 beat 时取消旧的补间
	var vsliceBopTweenP1:FlxTween = null;
	var vsliceBopTweenP2:FlxTween = null;

	// 图标缩放回弹的插值因子：
	// - 归一化(iconbopNormalize=true)：1 - e^(-k·dt·playbackRate)，任意刷新率/倍速下表现一致（高刷屏不再偏快/偏慢）
	// - 关闭：沿用旧版逐帧线性公式 k·dt·playbackRate，保留旧手感（低帧下可能偏离）
	private function iconBopLerpFactor(perSec:Float, dt:Float):Float
	{
		if (ClientPrefs.data.iconbopNormalize)
			return 1 - Math.exp(-perSec * playbackRate * dt);
		return perSec * playbackRate * dt;
	}

	/**
	 * 复刻 funkin 的图标跳动：beat 时把图标整体放大到 1.2，
	 * 再用默认(linear)匀速补间在约一个 step 内缩回 1.0（时长上限 0.175s，与 funkin 原版一致）。
	 * 返回新创建的补间，调用方负责存到对应图标字段，以便下次 beat 时取消。
	 */
	function iconBopFunkin(icon:HealthIcon, before:FlxTween):FlxTween
	{
		before?.cancel();
		icon.scale.set(1.2, 1.2);
		icon.updateHitbox();
		return FlxTween.tween(icon.scale, {x: 1, y: 1}, Math.min(Conductor.stepCrochet * 0.002, 0.175), {
			ease: FlxEase.linear
		});
	}

	public dynamic function updateIconsScale(elapsed:Float)
{
    // 当 iconbopstyle 改变时同步缓存，避免每帧做字符串 switch
    var curStyle:String = ClientPrefs.data.iconbopstyle;
    if (curStyle != _lastIconBopStyle)
    {
        _lastIconBopStyle = curStyle;
        _cachedIconSpeedMult = switch (curStyle)
        {
            case "Codename": 20;
            case "Leather": 6;
            case "SB": 20;
            case "VSlice(New)": 14;
            case "NovaFlare": 22;
            default: 9;
        }
    }

    // 统一递减：仅 Squash 使用此计时器
    if (ClientPrefs.data.iconbopstyle == "Squash")
        iconSizeResetTime = Math.max(0, iconSizeResetTime - elapsed * playbackRate);

    // 压扁风格(Squash)：beat 上双方 icon 被压扁（一方变矮胖、一方变高瘦），
    // 并随血量/输赢状态表现不同，随后在 0.8 秒内平滑过渡回正常大小（参考 JSE 的 Dave and Bambi）。
    if (ClientPrefs.data.iconbopstyle == "Squash")
    {
        var t:Float = FlxMath.bound(iconSizeResetTime / ICON_SQUASH_TIME, 0, 1);
        var iconLerp:Float = t * t * t * t; // 等价于 FlxEase.quartIn：开头慢、结尾快地恢复
        iconP1.scale.x = FlxMath.lerp(1, iconP1.scale.x, iconLerp);
        iconP1.scale.y = FlxMath.lerp(1, iconP1.scale.y, iconLerp);
        iconP2.scale.x = FlxMath.lerp(1, iconP2.scale.x, iconLerp);
        iconP2.scale.y = FlxMath.lerp(1, iconP2.scale.y, iconLerp);
    }
    else if (ClientPrefs.data.iconbopstyle == "Dave")
    {
        // 直接传浮点：Std.int 截断会在压扁方向制造死区，浮点 lerp 自然收敛
        var daveFactor:Float = ClientPrefs.data.iconbopNormalize
            ? FlxMath.bound(Math.exp(-(-Math.log(0.88) * 60) * elapsed * playbackRate), 0, 1)
            : 0.88;
        iconP1.setGraphicSize(FlxMath.lerp(iconP1.frameWidth, iconP1.width, daveFactor),
                             FlxMath.lerp(iconP1.frameHeight, iconP1.height, daveFactor));
        iconP2.setGraphicSize(FlxMath.lerp(iconP2.frameWidth, iconP2.width, daveFactor),
                             FlxMath.lerp(iconP2.frameHeight, iconP2.height, daveFactor));
    }
    // Kathy 专属缩放逻辑
    else if (ClientPrefs.data.iconbopstyle == "Kathy") {
        var healthPercent:Float = healthBar.percent;
        var targetScale:Float = 1.0;

        // 根据血量动态调整缩放强度
        var scaleIntensity:Float = 1 - Math.abs(healthPercent - 50) / 50;
        targetScale += 0.1 * scaleIntensity;

        // 平滑缩放过渡（归一化：任意刷新率下回弹速度一致）
        var kathyFactor:Float = iconBopLerpFactor(12, elapsed);
        iconP1.scale.x = FlxMath.lerp(iconP1.scale.x, targetScale, kathyFactor);
        iconP1.scale.y = FlxMath.lerp(iconP1.scale.y, targetScale, kathyFactor);
        iconP2.scale.x = FlxMath.lerp(iconP2.scale.x, targetScale, kathyFactor);
        iconP2.scale.y = FlxMath.lerp(iconP2.scale.y, targetScale, kathyFactor);
    }
    else if (ClientPrefs.data.iconbopstyle == "VSlice(New)")
    {
        // funkin 复刻：回弹完全由 beat 时启动的 linear 补间驱动，这里不再做指数衰减
    }
    else if (ClientPrefs.data.iconbopstyle == "VSlice(Old)")
    {
        // 原版 Funkin 0.2.7.1 复刻：每帧按 lerp(150, width, 0.50) 向基础尺寸衰减，
        // 等效于 30/s 收敛速率，仅传宽度参数，高度自动等比缩放
        var factor:Float = FlxMath.bound(1 - elapsed * 30 * playbackRate, 0, 1);
        iconP1.setGraphicSize(Std.int(FlxMath.lerp(iconP1.frameWidth, iconP1.width, factor)));
        iconP2.setGraphicSize(Std.int(FlxMath.lerp(iconP2.frameWidth, iconP2.width, factor)));
    }
    else if (ClientPrefs.data.iconbopstyle == "Psych (Legacy)")
    {
        // PsychEngine 0.4.2 忠实复刻：每帧按 (1 - elapsed*30) 向基础尺寸衰减，
        // 用 setGraphicSize 重绘像素（非 scale），收敛速率为 30/s。不使用 iconbopNormalize（保持默认手感）。
        var factor:Float = FlxMath.bound(1 - elapsed * 30 * playbackRate, 0, 1);
        iconP1.setGraphicSize(Std.int(FlxMath.lerp(iconP1.frameWidth, iconP1.width, factor)),
                              Std.int(FlxMath.lerp(iconP1.frameHeight, iconP1.height, factor)));
        iconP2.setGraphicSize(Std.int(FlxMath.lerp(iconP2.frameWidth, iconP2.width, factor)),
                              Std.int(FlxMath.lerp(iconP2.frameHeight, iconP2.height, factor)));
    }
    else if (ClientPrefs.data.iconbopstyle == "Forever")
    {
        // Forever Engine 复刻：beat 时图标放大到 1.15x，用指数衰减 lerp 平滑缩回，
        // 衰减系数 5.0（与原版 Forever Engine 的 Math.exp(5.0 * elapsed) 一致），
        // 带 playbackRate 支持变速播放。
        var foreverFactor:Float = 1 - Math.exp(-5.0 * elapsed * playbackRate);
        iconP1.scale.x = FlxMath.lerp(iconP1.scale.x, 1.0, foreverFactor);
        iconP1.scale.y = FlxMath.lerp(iconP1.scale.y, 1.0, foreverFactor);
        iconP2.scale.x = FlxMath.lerp(iconP2.scale.x, 1.0, foreverFactor);
        iconP2.scale.y = FlxMath.lerp(iconP2.scale.y, 1.0, foreverFactor);
    }
    else
    {
			// 使用缓存的 speedMultiplier，仅在 style 变更时由同步逻辑更新
			var speedMultiplier:Float = _cachedIconSpeedMult;

			// 定义缩放上限
			final ICON_BOUND:Float = 1.2; // 1 + 0.2

			if (["VSlice(New)", "Codename", "Leather"].contains(ClientPrefs.data.iconbopstyle))
			{
				var rate:Float;
				var targetScale:Float;
				if (ClientPrefs.data.iconbopstyle == "Leather") {
					// Leather 原生逐帧 0.1 衰减（每 1/60 秒衰减 10%）→ 归一化后换算为每秒收敛速率 0.1*60
					rate = ClientPrefs.data.iconbopNormalize
						? 1 - Math.exp(-(0.1 * 60) * playbackRate * elapsed)
						: 0.1 / ((Main.game != null ? Main.game.framerate : 60) / 60) * playbackRate;
					targetScale = iconP1.startSize;
				} else {
					rate = iconBopLerpFactor(speedMultiplier, elapsed);
					targetScale = 1;
				}
				iconP1.scale.x = FlxMath.lerp(iconP1.scale.x, targetScale, rate);
				iconP1.scale.y = FlxMath.lerp(iconP1.scale.y, targetScale, rate);
				iconP2.scale.x = FlxMath.lerp(iconP2.scale.x, targetScale, rate);
				iconP2.scale.y = FlxMath.lerp(iconP2.scale.y, targetScale, rate);

				if (Math.abs(iconP1.scale.x - targetScale) < 0.001) iconP1.scale.set(targetScale, targetScale);
				if (Math.abs(iconP2.scale.x - targetScale) < 0.001) iconP2.scale.set(targetScale, targetScale);

				iconP1.scale.x = FlxMath.bound(iconP1.scale.x, Math.NEGATIVE_INFINITY, ICON_BOUND);
				iconP1.scale.y = FlxMath.bound(iconP1.scale.y, Math.NEGATIVE_INFINITY, ICON_BOUND);
				iconP2.scale.x = FlxMath.bound(iconP2.scale.x, Math.NEGATIVE_INFINITY, ICON_BOUND);
				iconP2.scale.y = FlxMath.bound(iconP2.scale.y, Math.NEGATIVE_INFINITY, ICON_BOUND);

			}
			else
			{
				var mult:Float = FlxMath.lerp(1, iconP1.scale.x, Math.exp(-elapsed * speedMultiplier * playbackRate));
				iconP1.scale.set(mult, mult);
				mult = FlxMath.lerp(1, iconP2.scale.x, Math.exp(-elapsed * speedMultiplier * playbackRate));
				iconP2.scale.set(mult, mult);

				if (Math.abs(iconP1.scale.x - 1) < 0.001) iconP1.scale.set(1, 1);
				if (Math.abs(iconP2.scale.x - 1) < 0.001) iconP2.scale.set(1, 1);

				iconP1.scale.x = FlxMath.bound(iconP1.scale.x, Math.NEGATIVE_INFINITY, ICON_BOUND);
				iconP1.scale.y = FlxMath.bound(iconP1.scale.y, Math.NEGATIVE_INFINITY, ICON_BOUND);
				iconP2.scale.x = FlxMath.bound(iconP2.scale.x, Math.NEGATIVE_INFINITY, ICON_BOUND);
				iconP2.scale.y = FlxMath.bound(iconP2.scale.y, Math.NEGATIVE_INFINITY, ICON_BOUND);

			}
    }
    
    // 统一更新碰撞框
    iconP1.updateHitbox();
    iconP2.updateHitbox();
}

	public dynamic function updateIconsPosition()
	{
		var iconOffset:Int = 26;

	// Kathy专属动效
	//不要了，不好看
	/*if(ClientPrefs.data.iconbopstyle == "Kathy") 		{
			iconP1.x = healthBar.barCenter + (iconP1.frameHeight * iconP1.scale.x - iconP1.frameHeight)/2 - iconOffset;
			iconP2.x = healthBar.barCenter - (iconP2.frameHeight * iconP2.scale.x)/2 - iconOffset*2;

			// 垂直浮动效果
			var wave = Math.sin(Conductor.songPosition / 400) * 1.5;
			iconP1.y = iconP1InitialY + wave;
			iconP2.y = iconP2InitialY - wave;
		} else */
		{

			iconP1.x = healthBar.barCenter + (iconP1.frameHeight * iconP1.scale.x - iconP1.frameHeight)/2 - iconOffset;
			iconP2.x = healthBar.barCenter - (iconP2.frameHeight * iconP2.scale.x)/2 - iconOffset*2;

			// 超满血溢出移动：血量超过满值时，让小图标向血条右端外溢出（需丝滑血条 + 超满设置）
			if (ClientPrefs.data.smoothHP && ClientPrefs.data.healthOverflow)
			{
				var overflow:Float = smoothHealth - healthBar.bounds.max;
				if (overflow > 0.001)
				{
					overflow = FlxMath.bound(overflow, 0, 1);
					var overshoot:Float = overflow * 40;
					iconP1.x += overshoot;
					iconP2.x += overshoot * 0.5;
				}
			}
			/*iconP1.y = iconP1InitialY;
			iconP2.y = iconP2InitialY;*/
			if (ClientPrefs.data.iconbopstyle == "Kade") {
	        		iconP1.y = iconP1InitialY + (iconP1.scale.y - 1) * 80;
	        		iconP2.y = iconP2InitialY + (iconP2.scale.y - 1) * 80;
	    		}
				else if (ClientPrefs.data.iconbopstyle == "VSlice(Old)") {
					// 左上角缩放原点 + 原版 Funkin 复刻
					iconP1.origin.set(0, 0);  iconP2.origin.set(0, 0);
					iconP1.offset.set(0, 0);  iconP2.offset.set(0, 0);
					iconP1.y = iconP1InitialY;
					iconP2.y = iconP2InitialY;
					iconP1.x = healthBar.barCenter - iconOffset;
					iconP2.x = healthBar.barCenter + (iconP2.frameHeight / 2) - iconOffset * 2 - iconP2.width;
				}
			else if (ClientPrefs.data.iconbopstyle == "Leather") {
				// 左上角缩放原点：与 Psych (Legacy) 同理，解除 flixel 居中缩放
				iconP1.origin.set(0, 0);  iconP2.origin.set(0, 0);
				iconP1.offset.set(0, 0);  iconP2.offset.set(0, 0);
				// y 钉初始位置（无跳动偏移）
				iconP1.y = iconP1InitialY;
				iconP2.y = iconP2InitialY;
				// x 只跟随血量，不随 scale 跳动（与 Psych Legacy / Dave 完全一致）
				iconP1.x = healthBar.barCenter - iconOffset;
				iconP2.x = healthBar.barCenter + (iconP2.frameHeight / 2) - iconOffset * 2 - iconP2.width;
			}
			else if (ClientPrefs.data.iconbopstyle == "Codename") {
        		if(ClientPrefs.data.downScroll){
				iconP1.y = iconP1InitialY - (iconP1.scale.y - 1) * 70;
        		iconP2.y = iconP2InitialY - (iconP2.scale.y - 1) * 70;
    			} else {
				iconP1.y = iconP1InitialY + (iconP1.scale.y - 1) * 70;
        		iconP2.y = iconP2InitialY + (iconP2.scale.y - 1) * 70;
				}
			}
			else if (ClientPrefs.data.iconbopstyle == "Dave") {
				// 左上角缩放原点：归零 origin/offset 解除 flixel 居中缩放，y 钉上边缘、x 钉外缘
				iconP1.origin.set(0, 0);  iconP2.origin.set(0, 0);
				iconP1.offset.set(0, 0);  iconP2.offset.set(0, 0);
				iconP1.y = iconP1InitialY;
				iconP2.y = iconP2InitialY;
				iconP1.x = healthBar.barCenter - iconOffset;
				iconP2.x = healthBar.barCenter + (iconP2.frameHeight / 2) - iconOffset * 2 - iconP2.width;
			}
			else if (ClientPrefs.data.iconbopstyle == "Psych (Legacy)") {
					// 0.4.2 左上角缩放原点：
					// flixel 的 scale 默认绕 origin(=中心)缩放，updateHitbox() 又会把 origin 重置回中心、
					// 并把 offset 设为居中补偿 → 所以默认就是"居中缩放"。
					// 因此这里必须显式把 origin(x2 offset) 归零，让缩放锚定到左上角；
					// 再钉住上边缘(y)与外缘(x)，放大只向外缘方向扩张，绝不居中。
					iconP1.origin.set(0, 0);  iconP2.origin.set(0, 0);
					iconP1.offset.set(0, 0);  iconP2.offset.set(0, 0);

					// 上边缘固定：y 钉在创建时的初始安装位置，放大只向下生长
					iconP1.y = iconP1InitialY;
					iconP2.y = iconP2InitialY;

					// 外缘固定（向外扩张，避免居中缩放）：
					// P1 锚左缘(左上角)向右长；P2 锚右缘向左长，静止时保持在血条各自原位置
					iconP1.x = healthBar.barCenter - iconOffset;
					iconP2.x = healthBar.barCenter + (iconP2.frameHeight / 2) - iconOffset * 2 - iconP2.width;
					}
				else if (ClientPrefs.data.iconbopstyle == "Forever") {
						// Forever Engine 复刻：左上角缩放原点，与 Psych (Legacy) 同理
						iconP1.origin.set(0, 0);  iconP2.origin.set(0, 0);
						iconP1.offset.set(0, 0);  iconP2.offset.set(0, 0);
						iconP1.y = iconP1InitialY;
						iconP2.y = iconP2InitialY;
						iconP1.x = healthBar.barCenter - iconOffset;
						iconP2.x = healthBar.barCenter + (iconP2.frameHeight / 2) - iconOffset * 2 - iconP2.width;
					}
			}

		updateLaneCovers();
	}

	var iconsAnimations:Bool = true;
	function set_health(value:Float):Float // You can alter how icon animations work here
	{
		value = FlxMath.roundDecimal(value, 5); //Fix Float imprecision
		if(!iconsAnimations || healthBar == null || !healthBar.enabled || healthBar.valueFunction == null)
		{
			health = value;
			return health;
		}

		// update health bar
		health = value;
		var newPercent:Null<Float> = FlxMath.remapToRange(FlxMath.bound(healthBar.valueFunction(), healthBar.bounds.min, healthBar.bounds.max), healthBar.bounds.min, healthBar.bounds.max, 0, 100);
		healthBar.percent = (newPercent != null ? newPercent : 0);

		applyIconStates();
		return health;
	}

	/**
	 * 根据当前血条百分比刷新双方图标的 输/赢/正常 三态。
	 * 除了在 health 赋值时调用外，也在 Change Character 换图标后调用，
	 * 防止 changeIcon 重置动画帧导致图标状态丢失（如高血量对手图标回到普通态）。
	 */
	public function applyIconStates():Void
	{
		if(!iconsAnimations || healthBar == null || !healthBar.enabled || healthBar.valueFunction == null) return;

		// 三态图标：0=正常 1=输 2=赢（win 仅在开启 threeIcons 时生效；自动兼容仅含 0/1 帧的经典图标）
		// 赢与输的判定区间正相反，且玩家(iconP1)/对手(iconP2)两侧都生效
		var p1State:String = (healthBar.percent < 20) ? 'lose' : ((ClientPrefs.data.threeIcons && healthBar.percent > 80) ? 'win' : 'normal');
		var p2State:String = (healthBar.percent > 80) ? 'lose' : ((ClientPrefs.data.threeIcons && healthBar.percent < 20) ? 'win' : 'normal');
		if(playOpponent)
		{
			// playOpponent：玩家是左侧 dad(iconP2)、对手是右侧 bf(iconP1)，
			// 把“玩家态(p1State)”给 iconP2、“对手态(p2State)”给 iconP1，修正输赢状态反置。
			// 三态(win/lose/normal)判定区间不变，threeIcons 兼容性保留。
			iconP1.setIconState(p2State);
			iconP2.setIconState(p1State);
		}
		else
		{
			iconP1.setIconState(p1State);
			iconP2.setIconState(p2State);
		}
	}

	function openPauseMenu()
	{
		FlxG.camera.followLerp = 0;
		persistentUpdate = false;
		persistentDraw = true;
		paused = true;

		if(FlxG.sound.music != null) {
			FlxG.sound.music.pause();
			vocals.pause();
			opponentVocals.pause();
		}
		if(!cpuControlled)
		{
			for (note in playerStrums)
				if(note.animation.curAnim != null && note.animation.curAnim.name != 'static')
				{
					note.playAnim('static');
					note.resetAnim = 0;
				}
		}
		openSubState(new PauseSubState());

		#if DISCORD_ALLOWED
		if(autoUpdateRPC) DiscordClient.changePresence(detailsPausedText, SONG.song + " (" + storyDifficultyText + ")", iconP2.getCharacter());
		#end
	}

	/**
	 * 移动端游玩时，在屏幕右上角额外添加一个暂停按钮。
	 * 底板颜色 rgba(20,40,80,0.4)，图标（字母 "P"）为浅蓝 #88ccff。
	 */
	private function createMobilePauseButton():Void
	{
		if (!controls.mobileC)
			return;

		mobilePauseBtn = new TouchButton(0, 0, null);
		mobilePauseBtn.label = new FlxSprite();
		mobilePauseBtn.loadGraphic(Paths.image('touchpad/bg', 'mobile'));
		mobilePauseBtn.label.loadGraphic(Paths.image('touchpad/P', 'mobile'));

		mobilePauseBtn.scale.set(0.22, 0.22);
		mobilePauseBtn.updateHitbox();
		mobilePauseBtn.refreshLabel();

		mobilePauseBtn.statusIndicatorType = ALPHA;
		mobilePauseBtn.independentLabelColor = true; // P 用独立浅蓝，不被底板色覆盖
		mobilePauseBtn.statusAlphas = [0.4, 0.5, 0.3];
		mobilePauseBtn.canChangeLabelAlpha = false; // 图标始终不透明，底板才有透明度
		mobilePauseBtn.label.alpha = 1.0;

		mobilePauseBtn.color = 0x88ccff;       // 底板用原来的字母浅蓝
		mobilePauseBtn.label.color = 0xb0c4de; // 图标 #B0C4DE

		mobilePauseBtn.antialiasing = ClientPrefs.data.antialiasing;
		mobilePauseBtn.tag = 'P';
		mobilePauseBtn.scrollFactor.set();

		mobilePauseBtn.x = FlxG.width - mobilePauseBtn.width - 15;
		mobilePauseBtn.y = 15;

		mobilePauseBtn.cameras = [mobileControlsCam];
		mobilePauseBtn.onDown.callback = () ->
		{
			if (startedCountdown && !paused && canPause)
			{
				var ret:Dynamic = callOnScripts('onPause', null, true);
				if(ret != LuaUtils.Function_Stop)
				{
					mobilePauseBtn.visible = false;
					openPauseMenu();
				}
			}
		};

		mobilePauseBtn.alpha = 0.4;
		mobileControls.instance.insert(0, mobilePauseBtn);
		mobilePauseBtn.visible = controls.mobileC;
	}

	public function openChartEditor()
	{
		canResync = false;
		FlxG.camera.followLerp = 0;
		persistentUpdate = false;
		chartingMode = true;
		paused = true;

		if(FlxG.sound.music != null)
			FlxG.sound.music.stop();
		if(vocals != null)
			vocals.pause();
		if(opponentVocals != null)
			opponentVocals.pause();

		#if DISCORD_ALLOWED
		DiscordClient.changePresence("Chart Editor", null, null, true);
		DiscordClient.resetClientID();
		#end

		// 跟随 chartingVersion 设置回到对应版本的制谱器（默认仍是 1.0.4-Kathy）
		MusicBeatState.switchState(states.editors.ChartingRouter.createChartingState());
	}

	function openCharacterEditor()
	{
		canResync = false;
		FlxG.camera.followLerp = 0;
		persistentUpdate = false;
		paused = true;

		if(FlxG.sound.music != null)
			FlxG.sound.music.stop();
		if(vocals != null)
			vocals.pause();
		if(opponentVocals != null)
			opponentVocals.pause();

		#if DISCORD_ALLOWED DiscordClient.resetClientID(); #end
		MusicBeatState.switchState(new CharacterEditorState(SONG.player2));
	}

	public var isDead:Bool = false; //Don't mess with this on Lua!!!
	public var gameOverTimer:FlxTimer;
	function doDeathCheck(?skipHealthCheck:Bool = false) {
		if (((skipHealthCheck && instakillOnMiss) || health <= 0) && !practiceMode && !isDead && gameOverTimer == null)
		{
			// A2: onDeath — 纯通知回调，脚本收到"血量归零"信号；
			// 不返回 Function_Stop，阻止死亡请用 onGameOver（原版已有）或 onCustomGameOver
			callOnScripts('onDeath', null, true);

			var ret:Dynamic = callOnScripts('onGameOver', null, true);
			if(ret != LuaUtils.Function_Stop)
			{
				FlxG.animationTimeScale = 1;
				playerSideChar().stunned = true;
				deathCounter++;

				paused = true;
				canResync = false;
				canPause = false;
				#if VIDEOS_ALLOWED
				if(videoCutscene != null)
				{
					videoCutscene.destroy();
					videoCutscene = null;
				}
				#end

				persistentUpdate = false;
				persistentDraw = false;
				FlxTimer.globalManager.clear();
				FlxTween.globalManager.clear();
				FlxG.camera.setFilters([]);

				// A4: onCustomGameOver — 默认死亡流程已开始，但还没弹 GameOverSubstate；
				// 返回 Function_Stop 阻止默认 GameOverSubstate，脚本可以自己做自定义结束
				var customRet:Dynamic = callOnScripts('onCustomGameOver', null, true);
				if (customRet != LuaUtils.Function_Stop)
				{
					if(GameOverSubstate.deathDelay > 0)
					{
						gameOverTimer = new FlxTimer().start(GameOverSubstate.deathDelay, function(_)
						{
							vocals.stop();
							opponentVocals.stop();
							FlxG.sound.music.stop();
							openSubState(new GameOverSubstate(boyfriend));
							gameOverTimer = null;
						});
					}
					else
					{
						vocals.stop();
						opponentVocals.stop();
						FlxG.sound.music.stop();
						openSubState(new GameOverSubstate(boyfriend));
					}
				}
				else
				{
					// 被脚本拦截：停止音乐但不弹默认结束界面
					vocals.stop();
					opponentVocals.stop();
					FlxG.sound.music.stop();
				}

				// MusicBeatState.switchState(new GameOverState(boyfriend.getScreenPosition().x, boyfriend.getScreenPosition().y));

				#if DISCORD_ALLOWED
				// Game Over doesn't get his its variable because it's only used here
				if(autoUpdateRPC) DiscordClient.changePresence("Game Over - " + detailsText, SONG.song + " (" + storyDifficultyText + ")", iconP2.getCharacter());
				#end
				isDead = true;
				return true;
			}
		}
		return false;
	}

	public function moveCameraSection(?sec:Null<Int>):Void {
		if(sec == null) sec = curSection;
		if(sec < 0) sec = 0;

		if(SONG.notes[sec] == null) return;

		if (gf != null && SONG.notes[sec].gfSection)
		{
			moveCameraToGirlfriend();
			callOnScripts('onMoveCamera', ['gf']);
			return;
		}

		var isDad:Bool = (SONG.notes[sec].mustHitSection != true);
		moveCamera(isDad);
		if (isDad)
			callOnScripts('onMoveCamera', ['dad']);
		else
			callOnScripts('onMoveCamera', ['boyfriend']);
	}
	
	public function moveCameraToGirlfriend()
	{
		camFollow.setPosition(gf.getMidpoint().x, gf.getMidpoint().y);
		camFollow.x += gf.cameraPosition[0] + girlfriendCameraOffset[0];
		camFollow.y += gf.cameraPosition[1] + girlfriendCameraOffset[1];
		tweenCamIn();
	}

	var cameraTwn:FlxTween;
	public function moveCamera(isDad:Bool)
	{
		if(isDad)
		{
			if(dad == null) return;
			camFollow.setPosition(dad.getMidpoint().x + 150, dad.getMidpoint().y - 100);
			camFollow.x += dad.cameraPosition[0] + opponentCameraOffset[0];
			camFollow.y += dad.cameraPosition[1] + opponentCameraOffset[1];
			tweenCamIn();
		}
		else
		{
			if(boyfriend == null) return;
			camFollow.setPosition(boyfriend.getMidpoint().x - 100, boyfriend.getMidpoint().y - 100);
			camFollow.x -= boyfriend.cameraPosition[0] - boyfriendCameraOffset[0];
			camFollow.y += boyfriend.cameraPosition[1] + boyfriendCameraOffset[1];

			if (songName == 'tutorial' && cameraTwn == null && FlxG.camera.zoom != 1)
			{
				cameraTwn = FlxTween.tween(FlxG.camera, {zoom: 1}, (Conductor.stepCrochet * 4 / 1000), {ease: FlxEase.elasticInOut, onComplete:
					function (twn:FlxTween)
					{
						cameraTwn = null;
					}
				});
			}
		}
	}

	public function tweenCamIn() {
		if (songName == 'tutorial' && cameraTwn == null && FlxG.camera.zoom != 1.3) {
			cameraTwn = FlxTween.tween(FlxG.camera, {zoom: 1.3}, (Conductor.stepCrochet * 4 / 1000), {ease: FlxEase.elasticInOut, onComplete:
				function (twn:FlxTween) {
					cameraTwn = null;
				}
			});
		}
	}

	public function finishSong(?ignoreNoteOffset:Bool = false):Void
	{
		updateTime = false;
		FlxG.sound.music.volume = 0;

		vocals.volume = 0;
		vocals.pause();
		opponentVocals.volume = 0;
		opponentVocals.pause();

		if(ClientPrefs.data.noteOffset <= 0 || ignoreNoteOffset) {
			endCallback();
		} else {
			finishTimer = new FlxTimer().start(ClientPrefs.data.noteOffset / 1000, function(tmr:FlxTimer) {
				endCallback();
			});
		}
	}


	public var transitioning = false;
	public function endSong()
	{
		// 重置回放按键状态
		replayHeldKeys = [false, false, false, false];
		
		mobileControls.instance.visible = #if !android touchPad.visible = #end false;
		//Should kill you if you tried to cheat
		if(!startingSong)
		{
			notes.forEachAlive(function(daNote:Note)
			{
				if(daNote.strumTime < songLength - Conductor.safeZoneOffset)
					health -= 0.05 * healthLoss;
			});
			for (daNote in unspawnNotes)
			{
				if(daNote != null && daNote.strumTime < songLength - Conductor.safeZoneOffset)
					health -= 0.05 * healthLoss;
			}

			if(doDeathCheck()) {
				return false;
			}
		}

		timeBar.visible = false;
		timeTxt.visible = false;
		canPause = false;
		endingSong = true;
		camZooming = false;
		inCutscene = false;
		updateTime = false;

		deathCounter = 0;
		seenCutscene = false;

		#if ACHIEVEMENTS_ALLOWED
		var weekNoMiss:String = WeekData.getWeekFileName() + '_nomiss';
		checkForAchievement([weekNoMiss, 'ur_bad', 'ur_good', 'hype', 'two_keys', 'toastie' #if BASE_GAME_FILES, 'debugger' #end]);
		#end

		var ret:Dynamic = callOnScripts('onEndSong', null, true);
		if(ret != LuaUtils.Function_Stop && !transitioning)
		{
			#if !switch
			if(cpuHits == 0)
			{
			var percent:Float = ratingPercent;
			if(Math.isNaN(percent)) percent = 0;
			Highscore.saveScore(Song.loadedSongName, songScore, storyDifficulty, percent);
			}
			#end
			playbackRate = 1;

			if (chartingMode)
			{
				openChartEditor();
				return false;
			}

			if (isStoryMode)
			{
				campaignScore += songScore;
				campaignMisses += songMisses;

				storyPlaylist.remove(storyPlaylist[0]);

				if (storyPlaylist.length <= 0)
				{
					Mods.loadTopMod();
					FlxG.sound.playMusic(Paths.menuMusicAudio());
					#if DISCORD_ALLOWED DiscordClient.resetClientID(); #end

					canResync = false;
					MusicBeatState.switchState(new StoryMenuState());

					// if ()
					if(!ClientPrefs.getGameplaySetting('practice') && !ClientPrefs.getGameplaySetting('botplay') && cpuHits != 0) {
						StoryMenuState.weekCompleted.set(WeekData.weeksList[storyWeek], true);
						Highscore.saveWeekScore(WeekData.getWeekFileName(), campaignScore, storyDifficulty);

						FlxG.save.data.weekCompleted = StoryMenuState.weekCompleted;
						FlxG.save.flush();
					}
					changedDifficulty = false;
				}
				else
				{
					var difficulty:String = Difficulty.getFilePath();

					trace('LOADING NEXT SONG');
					trace(Paths.formatToSongPath(PlayState.storyPlaylist[0]) + difficulty);

					FlxTransitionableState.skipNextTransIn = true;
					FlxTransitionableState.skipNextTransOut = true;
					prevCamFollow = camFollow;

					Song.loadFromJson(PlayState.storyPlaylist[0] + difficulty, PlayState.storyPlaylist[0]);
					FlxG.sound.music.stop();

					canResync = false;
					LoadingState.prepareToSong();
					LoadingState.loadAndSwitchState(new PlayState(), false, false);
				}
			}
			else
			{
				openSubState(new ResultsScreen());
				/*trace('WENT BACK TO FREEPLAY??');
				Mods.loadTopMod();
				#if DISCORD_ALLOWED DiscordClient.resetClientID(); #end

				canResync = false;
				MusicBeatState.switchState(new FreeplayState());
				FlxG.sound.playMusic(Paths.menuMusicAudio());
				changedDifficulty = false;*/
			}
			transitioning = true;
		}
		return true;
	}

	public function KillNotes() {
		// batchCompactNotes 下 invalidateNote 不再即时 splice，不能再依赖 while(notes.length>0) 收敛。
		// 改为先快照依次击杀（复进对象池/销毁），再显式清空三个数组。
		var snapshot:Array<Note> = notes.members.copy();
		for (daNote in snapshot)
		{
			if (daNote == null) continue;
			daNote.active = false;
			daNote.visible = false;
			invalidateNote(daNote);
		}
		// 批量模式下数组仍留死成员，直接清空；legacy 模式下已即时移除，clear 幂等无害。
		notes.clear();
		normalNotes.clear();
		holdNotes.clear();
		unspawnNotes = [];
		eventNotes = [];
	}

	public var totalPlayed:Int = 0;
	public var totalNotesHit:Float = 0.0;

	public var showCombo:Bool = ClientPrefs.data.comboSprDisplay;
	public var showComboNum:Bool = true;
	public var showRating:Bool = true;
	public var showEXRating:Bool = ClientPrefs.data.exratingDisplay;

	// Stores Ratings and Combo Sprites in a group
	public var comboGroup:FlxSpriteGroup;

	// 取一个全新的、干净的 rating/combo 精灵：直接 new，行为与旧引擎/模组完全一致。
	// （已移除 comboSpritePooling 对象池——之前池复用会残留视觉状态，改为每次 new 确保渲染符合预期。）
	function recycleComboSprite():FlxSprite
	{
		var spr:FlxSprite = new FlxSprite();
		FlxTween.cancelTweensOf(spr);
		// scale 是独立的 FlxPoint，cancelTweensOf(spr) 无法取消作用于它的补间，
		// 必须单独取消，否则残留的 scale 补间会在复用后继续篡改新精灵的大小。
		FlxTween.cancelTweensOf(spr.scale);
		spr.velocity.set(0, 0);
		spr.acceleration.set(0, 0);
		spr.angle = 0;
		spr.alpha = 1;
		spr.scale.set(1, 1);
		spr.offset.set(0, 0);
		spr.loadGraphic(null);
		return spr;
	}

	// 用完一个 rating/combo 精灵：先从 comboGroup 移除，再立即销毁释放。
	// （已移除对象池归属判断，全部 new 出来的对象直接 destroy。）
	function killComboSprite(spr:FlxSprite):Void
	{
		if (spr == null) return;
		FlxTween.cancelTweensOf(spr);
		FlxTween.cancelTweensOf(spr.scale);
		spr.scale.set(1, 1);
		removeComboSpr(spr);
		spr.destroy();
	}

	// ===== Camellia 跳动风格（复刻自 VSCam 2.75）=====
	// 原版参数：判定贴图 scale 0.45 → 0.4（0.2s cubeIn），停留 0.75s 后 0.35s 淡出
	static inline var CAMELLIA_HOLD:Float = 0.75; // 淡出前的停留时长
	static inline var CAMELLIA_FADE:Float = 0.35; // 淡出时长
	static inline var CAMELLIA_BOUNCE_TIME:Float = 0.2; // 缩放回弹时长
	static inline var CAMELLIA_SCALE_RATIO:Float = 1.125; // 0.45 / 0.4，按比例换算时的起始放大倍率（预留）
	static inline var CAMELLIA_SCALE_OFFSET:Float = 0.05; // 按比例换算时，判定贴图从“默认大小 + 0.05”回弹到默认大小
	static inline var CAMELLIA_SCALE_FROM:Float = 0.45; // 照搬原数值时的起始缩放
	static inline var CAMELLIA_SCALE_TO:Float = 0.4; // 照搬原数值时的目标缩放

	inline function isKathyFallStyle():Bool
		return ClientPrefs.data.ratingFallStyle == "Kathy" || ClientPrefs.data.ratingFallStyle == "Kathy(Legacy)";

	inline function isCamelliaFallStyle():Bool
		return ClientPrefs.data.ratingFallStyle == "Camellia";

	// 对判定贴图施加 Camellia 的缩放回弹：出现时放大，随后 cubeIn 缓动收缩回目标大小。
	// 必须在 updateHitbox() 之后调用，否则会因 scale 被放大而错算 offset。
	function camelliaScaleBounce(spr:FlxSprite):Void
	{
		if (spr == null) return;

		var toX:Float;
		var toY:Float;
		if (ClientPrefs.data.camelliaScaleMode == "Original")
		{
			// 照搬原版绝对数值；像素舞台下乘以 daPixelZoom 以免小到不可见
			var mult:Float = PlayState.isPixelStage ? daPixelZoom : 1;
			toX = toY = CAMELLIA_SCALE_TO * mult;
			spr.scale.set(CAMELLIA_SCALE_FROM * mult, CAMELLIA_SCALE_FROM * mult);
		}
		else
		{
			// 按比例换算：以 setGraphicSize() 得到的当前 scale 为默认大小，
			// 起始临时放大 0.05（即 0.7 → 0.75）后回弹，幅度不受贴图基准影响。
			toX = spr.scale.x;
			toY = spr.scale.y;
			spr.scale.set(toX + CAMELLIA_SCALE_OFFSET, toY + CAMELLIA_SCALE_OFFSET);
		}

		FlxTween.cancelTweensOf(spr.scale);
		FlxTween.tween(spr.scale, {x: toX, y: toY}, CAMELLIA_BOUNCE_TIME / playbackRate, {ease: FlxEase.cubeIn});
	}

	// Stores HUD Objects in a Group
	public var uiGroup:FlxSpriteGroup;
	// Stores Note Objects in a Group
	public var noteGroup:FlxTypedGroup<FlxBasic>;

	// 箭头倒计时：当两箭头间隔 ≥ 3秒 时显示圆形进度圈 + 整数秒数字
	var noteTimer:ui.NoteTimer = null;

	// checkModHasImage 缓存：避免每次note命中都执行文件系统查询
	var _modImageCache:Map<String, Bool> = null;

	// 评分弹窗贴图缓存：在 cachePopUpScore() 中一次性预存 FlxGraphic 引用，
	// 命中时直接 loadGraphic(缓存引用)，省掉每次命中 6 次 Paths.image() 的路径计算与 Map 查找。
	// 按 rating.name 索引（perfect/sick/good/bad/shit），值已是 fallback 规则（marvelous→perfect→sick）后的最终贴图。
	var _ratingGfxCache:Map<String, FlxGraphic> = null;
	var _exRatingGfxCache:Map<String, FlxGraphic> = null;
	var _numGfxCache:Array<FlxGraphic> = null;
	var _comboGfx:FlxGraphic = null;

	private function checkModHasImage(imagePath:String):Bool
	{
		if (_modImageCache == null) _modImageCache = [];
		if (_modImageCache.exists(imagePath)) return _modImageCache.get(imagePath);

		var imageKey:String = LanguageBasic.getFileTranslation('images/' + imagePath) + '.png';
		var result:Bool = false;
		#if MODS_ALLOWED
		var modKey:String = imageKey;
		if(imagePath.startsWith('songs/')) modKey = imagePath;

		for(mod in Mods.getGlobalMods())
			if (FileSystem.exists(Paths.mods(mod + '/' + modKey)))
			{ result = true; break; }
		if (!result && (FileSystem.exists(Paths.mods(Mods.currentModDirectory + '/' + modKey)) || FileSystem.exists(Paths.mods(modKey))))
			result = true;
		#end
		_modImageCache.set(imagePath, result);
		return result;
	}

	private function cachePopUpScore()
	{
		var uiFolder:String = "";
		if (stageUI != "normal")
			uiFolder = uiPrefix + "UI/";

		// 预存 FlxGraphic 引用：命中时直接 loadGraphic(缓存引用)，避免每次命中都调用 Paths.image()
		// 重新计算路径字符串、查 currentTrackedAssets Map。同时在此处预先应用 marvelous→perfect→sick
		// 的 fallback 规则，使 popUpScore 命中路径只做一次 Map 查表。
		_ratingGfxCache = [];
		_exRatingGfxCache = [];
		for (rating in ratingsData)
		{
			// 普通 rating：按 fallback 规则确定最终贴图名（与原 popUpScore 中的判断一致）
			var ratingImageToUse:String = rating.image;
			if (rating.name == 'perfect' && ClientPrefs.data.fallbackPerfectToSick)
			{
				var hasMarvelousImg:Bool = checkModHasImage(uiFolder + 'marvelous' + ratingexspr + uiPostfix);
				var hasPerfectImg:Bool = checkModHasImage(uiFolder + 'perfect' + ratingexspr + uiPostfix);
				if (hasMarvelousImg)
					ratingImageToUse = 'marvelous';
				else if (!hasPerfectImg)
					ratingImageToUse = 'sick';
			}
			_ratingGfxCache.set(rating.name, Paths.image(uiFolder + ratingImageToUse + ratingexspr + uiPostfix));

			// EX rating：同样应用 fallback 规则
			var exRatingImageToUse:String = rating.image;
			if (rating.name == 'perfect' && ClientPrefs.data.fallbackEXPerfectToSick)
			{
				var hasMarvelousEXImg:Bool = checkModHasImage(uiFolder + 'marvelous' + exratingexspr + uiPostfix);
				var hasPerfectEXImg:Bool = checkModHasImage(uiFolder + 'perfect' + exratingexspr + uiPostfix);
				if (hasMarvelousEXImg)
					exRatingImageToUse = 'marvelous';
				else if (!hasPerfectEXImg)
					exRatingImageToUse = 'sick';
			}
			_exRatingGfxCache.set(rating.name, Paths.image(uiFolder + exRatingImageToUse + exratingexspr + uiPostfix));
		}
		// Sick+ 模式：perfect 不在 ratingsData 中，但需要缓存 perfect 贴图供 Sick+ 显示使用
		// 仅当 fallbackPerfectToSick=false（即选择显示 Perfect 贴图）时才需要缓存
		if (ClientPrefs.data.rmPerfect == 'sickPlus' && !ClientPrefs.data.fallbackPerfectToSick)
		{
			_ratingGfxCache.set('perfect', Paths.image(uiFolder + 'perfect' + ratingexspr + uiPostfix));
		}
		if (ClientPrefs.data.rmPerfect == 'sickPlus' && !ClientPrefs.data.fallbackEXPerfectToSick)
		{
			_exRatingGfxCache.set('perfect', Paths.image(uiFolder + 'perfect' + exratingexspr + uiPostfix));
		}
		// 数字 0-9 贴图
		_numGfxCache = [];
		for (i in 0...10)
			_numGfxCache.push(Paths.image(uiFolder + 'num' + i + uiPostfix + numexspr));
		// combo 贴图（popUpScore 中每次命中都会加载）
		_comboGfx = Paths.image(uiFolder + 'combo' + uiPostfix);
	}

	private function popUpScore(note:Note = null, scoreGain:Bool = true, leniencyMs:Float = 0):Void
	{
		// scoreGain=false 时（特性2 长条尾部判定）：显示评级/计入准度，但不加 songScore、不写回放数据
		// 移除Math.abs()来允许显示负值
		// BotPlay 不是人类输入，不应套用 ratingOffset / 移动端补偿：这些校准值仅用于补偿玩家本人的手感，
		// 否则会让 bot 的"完美命中"被系统性地偏移 ratingOffset 毫秒，导致整体爆 good/bad。

		// Kade 样式 ShowCase：Botplay（cpuControlled，非回放）下只显示 numScore 数字，隐藏 rating/exRating 贴图。
		// 对齐 Kade Engine 原版行为：if(!PlayStateChangeables.botPlay || loadRep) add(rating);
		if (ClientPrefs.data.showcaseStyle == 'Kade' && cpuControlled && !isReplaying)
		{
			showRating = false;
			showEXRating = false;
		}
		else
		{
			showRating = true;
			showEXRating = ClientPrefs.data.exratingDisplay;
		}

		var noteDiff:Float = note.strumTime - Conductor.songPosition + (cpuControlled ? 0 : ClientPrefs.data.ratingOffset);

		// 移动端判定补偿：触屏输入倾向于出现额外正向(偏晚) 延迟，
		// 因此仅在 noteDiff < 0 时叠加偏移，避免把本来就偏早的按键推得更提前。
		// 同样不对 BotPlay 生效（见上方说明）。
		if (!cpuControlled && ClientPrefs.data.mobileJudgmentCompensation && noteDiff < 0)
			noteDiff += ClientPrefs.data.mobileJudgmentOffset;

		// 在回放模式下，优先使用延迟覆盖值（最高优先级）
		if(isReplaying && currentNoteDelayOverride != null)
		{
			noteDiff = currentNoteDelayOverride;
			currentNoteDelayOverride = null; // 使用后清空
		}
		// 备用方案：从预填充的延迟数组中查找对应音符的记录
		else if(isReplaying && note.noteData >= 0 && note.noteData < 4)
		{
			for(delayData in replayNoteDelays[note.noteData])
			{
				if(delayData.strumTime == note.strumTime)
				{
					// 找到匹配的记录，使用原始记录的延迟值
					noteDiff = delayData.late;
					break;
				}
			}
		}

		if(cpuControlled && ClientPrefs.data.botplayPerfectTiming)
		{
			noteDiff = 0;
		}

		// 特性2宽容：尾条判定时，把计时误差绝对值削减至多 leniencyMs，等效于把 perfect/sick/good 等
		// 评级窗口（以及命中窗口）各放宽 leniencyMs。例如 Psych(perfect23/sick45/good90) +20ms → 43/65/110。
		if(leniencyMs > 0 && noteDiff != 0)
			noteDiff -= (noteDiff > 0 ? 1 : -1) * Math.min(Math.abs(noteDiff), leniencyMs);

		allNotesMs += noteDiff;
		
		averageMs = allNotesMs/songHits;

		// 存储打击数据供 HitGraph 使用，同时一次性计算 daRating 给后续计分/动画/EX贴图 共用
		var daRating:Rating = Conductor.judgeNote(ratingsData, noteDiff / playbackRate);
		// Leather modchart 事件：popUpScore(rating, combo)（对照 LE 原版 PlayState ~2877）
		callOnLeatherScripts('popUpScore', [daRating.name, combo]);
		// Sick+ 模式：命中 perfect 窗口时，判定为 Sick 但给予 Perfect 分数(500)，且可选显示 Perfect 贴图
		// 不创建新的 ratingData，纯粹在 popUpScore 中处理分数和贴图显示
		var isSickPlus:Bool = false;
		if (ClientPrefs.data.rmPerfect == 'sickPlus' && daRating.name == 'sick')
		{
			var absJudgeDiff:Float = Math.abs(noteDiff / playbackRate);
			if (absJudgeDiff <= ClientPrefs.data.perfectWindow)
				isSickPlus = true;
		}
		// 触发评分计数器动画
		if (ratingCounterModule != null && !note.ratingDisabled)
		{
			ratingCounterModule.triggerHitAnimation(daRating.name);
		}
		if(!cpuControlled)
		{
			if(!note.ratingDisabled)
			{
				hitHistory.push([noteDiff, daRating.name, note.strumTime]);			
				// 记录回放数据（仅在非回放模式下；特性2 长条尾部判定不写回放，避免污染输入序列）
				if(!isReplaying && scoreGain)
				{
					replayData.push({
						time: Conductor.songPosition,
						key: note.noteData,
						noteTime: note.strumTime,
						late: noteDiff,
						judge: daRating.name,
						releaseTime: null
					});
				}
			}
		}

		vocals.volume = 1;

		if (!ClientPrefs.data.comboStacking && comboGroup.members.length > 0)
		{
			// 遍历成员副本，避免边遍历边移除导致跳过元素；kill 回收进对象池而非 destroy，供后续复用。
			for (spr in comboGroup.members.copy())
			{
				if(spr == null) continue;
				if (spr == msTimeTxt) continue; // 排除 msTimeTxt，避免 comboStacking 关闭时被销毁导致空引用
				killComboSprite(spr);
			}
		}

		if (!ClientPrefs.data.rmmsTimeTxt) {
			if (ClientPrefs.data.msTimingStyle == 'Kade') {
				// ===== Kade 风格：复用原 msTimeTxt，覆盖为 Kade 样式（20px/1px黑描边/居中）=====
				if (!msTimeTxtKadeStyle) {
					msTimeTxt.setFormat(null, 20, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
					msTimeTxt.borderSize = 1;
					msTimeTxt.width = 0; // 让文本自适应宽度（Kade 无固定宽度）
					msTimeTxtKadeStyle = true;
				}
				msTimeTxt.alpha = 1;
				msTimeTxt.visible = true;
				// Kade 原生：颜色随判定变化（bad/shit 红、good 绿、sick 青）；Perfect 引擎无原生配色，用浅粉高亮
				switch (daRating.name) {
					case 'perfect':
						msTimeTxt.color = 0xFFFFC0CB;
					case 'sick':
						msTimeTxt.color = FlxColor.CYAN;
					case 'good':
						msTimeTxt.color = FlxColor.GREEN;
					default:
						msTimeTxt.color = FlxColor.RED; // bad / shit
				}
				msTimeTxt.text = CoolUtil.floorDecimal(noteDiff, 2) + "ms";
				msTimeTxt.updateHitbox();
			// 统一使用 NoteOffsetState 预览位置（Kathy 基准），Kade 只保留颜色/淡出差异
			// [6,7] 始终作为 msTimeTxt 二次偏移；'numScore' 时沿用 combo 数字槽位 [2,3] 作为基础锚点
			var msBaseX:Int = 0;
			var msBaseY:Int = 0;
			if (ClientPrefs.data.msTimingOffsetMode != 'independent') {
			msBaseX = ClientPrefs.data.comboOffset[2];
			msBaseY = ClientPrefs.data.comboOffset[3];
		} else {
			msBaseX = 150; // 独立偏移：默认在此基础上额外右移 150
		}
		msTimeTxt.x = FlxG.width * 0.35 + 100 + msBaseX + ClientPrefs.data.comboOffset[6] + 60 - 20 - 40;
			msTimeTxt.y = (FlxG.height * 0.5) + 80 - 40 - msBaseY - ClientPrefs.data.comboOffset[7];
				msTimeTxt.acceleration.y = 600;
				msTimeTxt.velocity.y = -150;
				msTimeTxt.velocity.x = FlxG.random.float(0, 10);
				// 复用同一个文本：Kade 原版淡出——不建 tween，改为 update 中按固定 120Hz 步进衰减
				if (msTimeTxtTween1 != null) {
					msTimeTxtTween1.cancel();
					msTimeTxtTween1.destroy();
				}
				// 若刚从 Kathy 风格切换过来，可能有残留的 y 位移补间，一并取消
				if (msTimeTxtTween2 != null) {
					msTimeTxtTween2.cancel();
					msTimeTxtTween2.destroy();
				}
				// 标记开始 Kade 定时淡出；本次命中已把 alpha 重置为 1，同时清空步进累加器
				msTimingShownActive = true;
				msTimeTxtFadeAccum = 0;
			}
			else {
				// 从 Kade 风格切回 Kathy：恢复原样式并清零运动
				if (msTimeTxtKadeStyle) {
					msTimeTxt.setFormat(Paths.font('vcr.ttf'), 24, FlxColor.WHITE, RIGHT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
					msTimeTxt.borderSize = 1.3;
					msTimeTxt.borderColor = FlxColor.BLACK;
					msTimeTxt.width = 250;
					msTimeTxtKadeStyle = false;
				}
				msTimeTxt.velocity.set(0, 0);
				msTimeTxt.acceleration.set(0, 0);
				// 切回 Kathy 风格：关掉 Kade 定时淡出，避免与 Kathy 的 alpha Tween 打架
				msTimingShownActive = false;
				msTimeTxtFadeAccum = 0;
			if (isPixelStage) {
				msTimeTxt.font = Paths.font("pixel.otf");
				msTimeTxt.size = 16;

			}
			msTimeTxt.alpha = ratingAlpha;
		// [6,7] 始终作为 msTimeTxt 二次偏移；'numScore' 时额外沿用 combo 数字槽位 [2,3] 作为基础锚点
		var msLiveBaseX:Int = 0;
		var msLiveBaseY:Int = 0;
		if (ClientPrefs.data.msTimingOffsetMode != 'independent') {
			msLiveBaseX = ClientPrefs.data.comboOffset[2];
			msLiveBaseY = ClientPrefs.data.comboOffset[3];
		} else {
			msLiveBaseX = 150; // 独立偏移：默认在此基础上额外右移 150
		}
		msTimeTxt.x = FlxG.width * 0.35 + 100 + msLiveBaseX + ClientPrefs.data.comboOffset[6] + 60 - 20 - 40;
		msTimeTxt.y = (FlxG.height * 0.5) + 80 - 40 - msLiveBaseY - ClientPrefs.data.comboOffset[7];
			// 调整显示格式，保留两位小数
			var modeLabel:String = "";
			if (ClientPrefs.data.showModeLabelInMsTxt) {
				if (isReplaying) {
					modeLabel = "(REP)";
				} else if (cpuControlled) {
					modeLabel = "(BOT)";
				} else if (!scoreGain) {
					// 特性2：长条尾部判定（释放时机命中），对应标签
					modeLabel = "(TAIL)";
				}
			}
			
			if(cpuControlled && ClientPrefs.data.botplayPerfectTiming) msTimeTxt.text = "0ms" + modeLabel;
			else msTimeTxt.text = Std.string(CoolUtil.floorDecimal(noteDiff, 2)) + "ms" + modeLabel;
			msTimeTxt.color = noteDiff < 0 ? FlxColor.ORANGE : FlxColor.CYAN;

			if (msTimeTxtTween1 != null){
				msTimeTxtTween1.cancel(); msTimeTxtTween1.destroy(); // top 10 awesome code
			}
			msTimeTxtTween1 = FlxTween.tween(msTimeTxt, {alpha: 0}, 0.5, {
				onComplete: function(tw:FlxTween) {msTimeTxtTween1 = null;}, startDelay: (60 / Conductor.bpm) * 0.5
			});
			// Kathy 风格：命中时向下位移 10px（恢复历史行为；NoteOffsetState 预览为静态不位移，属预期差异）
			if (msTimeTxtTween2 != null) {
				msTimeTxtTween2.cancel(); msTimeTxtTween2.destroy();
			}
			msTimeTxtTween2 = FlxTween.tween(msTimeTxt, {y: msTimeTxt.y + 10}, 0.32, {ease: FlxEase.circOut});
			}
		}

		var placement:Float = FlxG.width * 0.35 + 100;
		var score:Int = 350;

		// 复用上方已计算的 daRating（避免重复调用 judgeNote）
		// 准确率模式：'accurate' 按评级固定加权(ratingMod)；'complex' 用 wife3 毫秒精度函数
		var accGain:Float = daRating.ratingMod;
		if(ClientPrefs.data.accuracyMode.toLowerCase() == 'complex')
		{
			// 长条(尾音)命中：无论开关都按 Kade 固定满分 +1，不套毫秒权重
			accGain = note.isSustainNote ? 1 : Math.max(0, wife3Accuracy(-noteDiff / playbackRate, playbackRate));
		}
		// 长条准确率开关：关闭时长条(尾音)命中不计入分子（仅分母 totalPlayed++，等效忽略长条对准确率的贡献）
		if(note.isSustainNote && !ClientPrefs.data.sustainAccuracy) accGain = 0;
		totalNotesHit += accGain;
		note.ratingMod = daRating.ratingMod;
		if(!note.ratingDisabled) daRating.hits++;
		note.rating = daRating.name;
		score = daRating.score;
		if (ClientPrefs.data.kadeScoring)
		{
			// Kade 计分：bad=0 / shit=-300 / good=200 / sick=350（Perfect 归入 sick 分，无额外加分）
			switch (daRating.name)
			{
				case 'shit': score = -300;
				case 'bad': score = 0;
				case 'good': score = 200;
				default: score = 350;
			}
		}
		// Sick+ 给予 Perfect 分数(500)
		else if (isSickPlus) score = 500;
		// Sick+ 计数（纯统计用，不影响FC/准度）
		if (isSickPlus && !note.ratingDisabled) songSickPlus++;

		if(daRating.noteSplash && !note.noteSplashData.disabled && ClientPrefs.data.cpuStrums)
			spawnNoteSplashOnNote(note);

		/*if(!cpuControlled) */
		if(!cpuControlled || ClientPrefs.data.botplayScore)
		{
    		if(scoreGain) songScore += score; // 特性2：长条尾部命中不加分
    		if(!note.ratingDisabled && !(note.isSustainNote && !ClientPrefs.data.sustainAccuracy))
    		{
        		songHits++;
        		totalPlayed++; 
        		RecalculateRating(false);
    		}
		}

		if(cpuControlled) cpuHits++;
		if (ClientPrefs.data.ratCounter)	updateRatingCounters();

		var uiFolder:String = "";
		var antialias:Bool = ClientPrefs.data.antialiasing;
		if (stageUI != "normal")
		{
			uiFolder = uiPrefix + "UI/";
			antialias = !isPixelStage;
		}

		// Sick+ 贴图显示：复用 fallbackPerfectToSick/fallbackEXPerfectToSick 设置
		// fallbackPerfectToSick=false → 显示 Perfect 贴图; =true → 显示 Sick 贴图(回落到sick)
		var displayRatingName:String = daRating.name;
		var displayExRatingName:String = daRating.name;
		if (isSickPlus)
		{
			if (!ClientPrefs.data.fallbackPerfectToSick)
				displayRatingName = 'perfect';
			if (!ClientPrefs.data.fallbackEXPerfectToSick)
				displayExRatingName = 'perfect';
		}

		if (ClientPrefs.data.popUpRating)
		{
			// 跳动风格只在此处求值一次，避免在下方多个分支里重复做字符串比较（热路径，一首歌可达数千次命中）
			var isKathyStyle:Bool = isKathyFallStyle();
			var isCamellia:Bool = isCamelliaFallStyle();
			// Camellia 使用固定的 0.35s 淡出时长，其它风格维持原有的 0.2s
			var fadeDuration:Float = isCamellia ? CAMELLIA_FADE : 0.2;

			var rating:FlxSprite = recycleComboSprite();
			var theEXrating:FlxSprite = recycleComboSprite();
			// 直接复用 cachePopUpScore() 预存的 FlxGraphic 引用（已按 fallback 规则确定最终贴图），
			// 跳过每次命中的 Paths.image() 路径计算与 Map 查找；缓存不可用时回退到原逻辑
			rating.loadGraphic(_ratingGfxCache != null ? _ratingGfxCache.get(displayRatingName) : Paths.image(uiFolder + displayRatingName + ratingexspr + uiPostfix));
			rating.screenCenter();
			rating.x = placement - 40;
			rating.y -= 60;
			rating.visible = (!ClientPrefs.data.hideHud && showRating);
			rating.x += ClientPrefs.data.comboOffset[0];
			rating.y -= ClientPrefs.data.comboOffset[1];
			rating.antialiasing = antialias;

			theEXrating.loadGraphic(_exRatingGfxCache != null ? _exRatingGfxCache.get(displayExRatingName) : Paths.image(uiFolder + displayExRatingName + exratingexspr + uiPostfix));
			theEXrating.screenCenter();
			theEXrating.x = placement - 40;
			theEXrating.y -= 60;
			theEXrating.visible = (!ClientPrefs.data.hideHud && showEXRating);
			theEXrating.x += ClientPrefs.data.comboOffset[4] - 140;
			theEXrating.y -= ClientPrefs.data.comboOffset[5]; // y 基础已在上方 -=60，与 rating 对齐
			theEXrating.antialiasing = antialias;
			theEXrating.angle = 0;

	
			// combo 数字纹理显示模式：Psych / Default / OG Funkin
		var showThisCombo:Bool = showCombo;
		var showThisComboNum:Bool = showComboNum;
		var separatedScore:String = Std.string(combo).lpad('0', 3); // 默认(Psych)：补0到3位
		switch (ClientPrefs.data.comboNumDisplay)
		{
			case 'OG Funkin':
				if (comboJustBroke)
				{
					separatedScore = '000'; // 断连后首次命中强制显示 000
					showThisComboNum = true;
				}
				else if (combo >= 10)
				{
					separatedScore = Std.string(combo).lpad('0', 3);
					showThisComboNum = true;
				}
				else
				{
					separatedScore = '';
					showThisCombo = false;
					showThisComboNum = false;
				}
			case 'Default':
				separatedScore = Std.string(combo); // 类似Psych但不补0
			default: // 'Psych'
				separatedScore = Std.string(combo).lpad('0', 3);
		}

		var comboSpr:FlxSprite = recycleComboSprite();
			comboSpr.loadGraphic(_comboGfx != null ? _comboGfx : Paths.image(uiFolder + 'combo' + uiPostfix));
			comboSpr.screenCenter();
			comboSpr.x = placement;
			//comboSpr.acceleration.y = FlxG.random.int(200, 300) * playbackRate * playbackRate;
			//comboSpr.velocity.y -= FlxG.random.int(140, 160) * playbackRate;
			//comboSpr.velocity.x += FlxG.random.int(1, 10) * playbackRate;
			comboSpr.visible = (!ClientPrefs.data.hideHud && showThisCombo);
			// comboSpr 不跟随 rating：改为跟在 combo 数字之后，沿用 numScore 的偏移槽位 [2,3]（不可独立调整），并上移 30px 修正靠下问题
			comboSpr.y -= ClientPrefs.data.comboOffset[3];
			comboSpr.y += 50;
			comboSpr.antialiasing = antialias;

			if (isCamellia)
			{
				// Camellia 风格：原地出现，不带任何下落速度或重力，动画完全交给下方的缩放回弹补间。
				// 放在 comboStacking 判断之前，保证开关无论开或关，观感都一致。
				rating.velocity.set(0, 0);
				rating.acceleration.set(0, 0);
				theEXrating.velocity.set(0, 0);
				theEXrating.acceleration.set(0, 0);
				comboSpr.velocity.set(0, 0);
				comboSpr.acceleration.set(0, 0);
			}
			else if (ClientPrefs.data.comboStacking)
			{
				// 原版向上跳跃逻辑
				rating.acceleration.y = 550 * playbackRate * playbackRate;
				rating.velocity.y -= FlxG.random.int(140, 175) * playbackRate;

				theEXrating.acceleration.y = 550 * playbackRate * playbackRate;
				theEXrating.velocity.y -= FlxG.random.int(140, 150) * playbackRate;

				comboSpr.acceleration.y = FlxG.random.int(200, 300) * playbackRate * playbackRate;
				comboSpr.velocity.y -= FlxG.random.int(140, 160) * playbackRate;
			}
			else
			{
				if (ClientPrefs.data.ratingFallStyle == "Leather")
				{
					// Leather 风格，直接向下移动，像 LeatherEngine 那样
					rating.velocity.y = FlxG.random.int(30, 60);
					rating.velocity.x = FlxG.random.int(-10, 10);
					
					theEXrating.velocity.y = FlxG.random.int(30, 60);
					theEXrating.velocity.x = FlxG.random.int(-10, 10);
					
					comboSpr.velocity.y = FlxG.random.int(30, 60);
					comboSpr.velocity.x = FlxG.random.int(-10, 10);
				}
				else if (ClientPrefs.data.ratingFallStyle == "Legacy")
				{
					rating.acceleration.y = 550 * playbackRate * playbackRate;
					rating.velocity.y -= FlxG.random.int(140, 175) * playbackRate;

					theEXrating.acceleration.y = 550 * playbackRate * playbackRate;
					theEXrating.velocity.y -= FlxG.random.int(140, 150) * playbackRate;

					comboSpr.acceleration.y = FlxG.random.int(200, 300) * playbackRate * playbackRate;
					comboSpr.velocity.y -= FlxG.random.int(140, 160) * playbackRate;
				}
				else if (isKathyStyle)
				{
					rating.velocity.y = 0;
					theEXrating.velocity.y = 0;
					comboSpr.velocity.y = 0;
				}
				else
				{
					rating.acceleration.y = 550 * playbackRate * playbackRate;
					rating.velocity.y -= FlxG.random.int(140, 175) * playbackRate;

					theEXrating.acceleration.y = 550 * playbackRate * playbackRate;
					theEXrating.velocity.y -= FlxG.random.int(140, 150) * playbackRate;

					comboSpr.acceleration.y = FlxG.random.int(200, 300) * playbackRate * playbackRate;
					comboSpr.velocity.y -= FlxG.random.int(140, 160) * playbackRate;
				}
			}

			if (!PlayState.isPixelStage)
			{
				rating.setGraphicSize(Std.int(rating.width * 0.7));
				theEXrating.setGraphicSize(Std.int(theEXrating.width * 0.7));
				comboSpr.setGraphicSize(Std.int(comboSpr.width * 0.65));
			}
			else
			{
				rating.setGraphicSize(Std.int(rating.width * daPixelZoom * 0.7));
				theEXrating.setGraphicSize(Std.int(theEXrating.width * daPixelZoom * 0.7));
				comboSpr.setGraphicSize(Std.int(comboSpr.width * daPixelZoom * 0.7));
			}


			if (ratingAlpha != 1)
			{
				rating.alpha = ratingAlpha;
				theEXrating.alpha = ratingAlpha;
				comboSpr.alpha = ratingAlpha;
			}

			if (ClientPrefs.data.exratingDisplay)	addToComboLayer(theEXrating);
			
			addToComboLayer(rating);	

			if (isCamellia)
			{
				// Camellia 风格拥有自己固定的动画方案，不读取 ratbounce / exratbounce。
				// 缩放回弹放在下方 updateHitbox() 之后统一处理，此处留空。
			}
			else if (ClientPrefs.data.comboStacking)
			{
				// 只有 Kathy/Kathy(Legacy) 风格才能用 bounce
				if (ClientPrefs.data.ratbounce == true && !PlayState.isPixelStage && isKathyStyle)
				{
					rating.scale.set(0.85, 0.8);
					FlxTween.tween(rating.scale, {x: 0.7, y: 0.7}, 0.35, {ease: FlxEase.quartOut});
				}

				if(ClientPrefs.data.exratbounce == true && ClientPrefs.data.exratingDisplay && isKathyStyle)
				{
					theEXrating.angle = (Math.random() * 10) * (Math.random() > .5 ? 1 : -1);
					theEXrating.scale.set(0.85, 0.85);
					FlxTween.tween(theEXrating, {angle: 0}, 0.4, {ease: FlxEase.backOut});
					FlxTween.tween(theEXrating.scale, {x: 0.7, y: 0.7}, 0.4, {ease: FlxEase.quartOut});
				}
			}
			else
			{
				// 只有 Kathy/Kathy(Legacy) 风格才能用 bounce
				if (ClientPrefs.data.ratbounce == true && !PlayState.isPixelStage && isKathyStyle)
				{
					rating.angle = (Math.random() * 7) * (Math.random() > .5 ? 1 : -1);
				}

				if(ClientPrefs.data.exratbounce == true && ClientPrefs.data.exratingDisplay && isKathyStyle)
				{
					theEXrating.angle = (Math.random() * 7) * (Math.random() > .5 ? 1 : -1);
				}

				if (isKathyStyle)
				{
					if (ClientPrefs.data.ratingFallStyle == "Kathy(Legacy)")
					{
						rating.angle = -8;
						rating.x -= 150;
						if (!PlayState.isPixelStage)
							rating.setGraphicSize(Std.int(rating.width * 0.65));
						else
						{
							rating.setGraphicSize(Std.int(rating.width * daPixelZoom * 0.65));
						}
						theEXrating.alpha = rating.alpha;
						theEXrating.x = rating.x + (rating.width / 2.1);
						theEXrating.y = rating.y - 75;
						theEXrating.angle = 2;
					}
					
					FlxTween.tween(rating, {y: rating.y + FlxG.random.int(12, 18)}, 0.2, {ease: FlxEase.quintOut});
					FlxTween.tween(theEXrating, {y: theEXrating.y + FlxG.random.int(15, 20)}, 0.2, {ease: FlxEase.quintOut});
					FlxTween.tween(comboSpr, {y: comboSpr.y + FlxG.random.int(12, 18)}, 0.2, {ease: FlxEase.quintOut});

				}

			}
	
			comboSpr.updateHitbox();
			rating.updateHitbox();
			theEXrating.updateHitbox();

			if (isCamellia)
			{
				// 缩放回弹必须放在 updateHitbox() 之后，否则 updateHitbox() 会依据被放大的 scale
				// 重算 width/height 与 offset，导致贴图位置偏移。
				camelliaScaleBounce(rating);
				if (ClientPrefs.data.exratingDisplay) camelliaScaleBounce(theEXrating);
				// "combo" 单词：与 numScore 同款入场（抬高 5px 后 cubeIn 落回原位）。
				// 此前这里只有缩放/淡出，没有下落，导致数字在下坠而单词静止。
				if (showThisCombo)
				{
					var comboWordTargetY:Float = comboSpr.y;
					comboSpr.y -= 5;
					FlxTween.tween(comboSpr, {y: comboWordTargetY}, 0.1 / playbackRate, {ease: FlxEase.cubeIn});
				}
			}

			var daLoop:Int = 0;
			var xThing:Float = 0;
			if (showThisCombo)
				addToComboLayer(comboSpr);

			for (i in 0...separatedScore.length)
			{
				var numScore:FlxSprite = recycleComboSprite();
				var numIdx:Int = Std.parseInt(separatedScore.charAt(i));
				numScore.loadGraphic((_numGfxCache != null && numIdx < _numGfxCache.length) ? _numGfxCache[numIdx] : Paths.image(uiFolder + 'num' + numIdx + uiPostfix));
				numScore.screenCenter();
				numScore.x = placement + (43 * daLoop) - 90 + ClientPrefs.data.comboOffset[2];
				numScore.y += 80 - ClientPrefs.data.comboOffset[3];
				numScore.alpha = ratingAlpha;

				if (!PlayState.isPixelStage)
					numScore.setGraphicSize(Std.int(numScore.width * 0.5));
				else
					numScore.setGraphicSize(Std.int(numScore.width * daPixelZoom));
				numScore.updateHitbox();

				if (isCamellia)
				{
					// Camellia 风格：数字原地出现，初始位置略高于最终位置，再落回原位。
					// 注意方向与 Kathy 风格的「向下弹出」相反。
					numScore.velocity.set(0, 0);
					numScore.acceleration.set(0, 0);
					var targetY:Float = numScore.y;
					numScore.y -= 5;
					FlxTween.tween(numScore, {y: targetY}, 0.1 / playbackRate, {ease: FlxEase.cubeIn});
				}
				else if (ClientPrefs.data.comboStacking)
				{
					// 原版向上跳跃逻辑
					numScore.acceleration.y = FlxG.random.int(200, 300) * playbackRate * playbackRate;
					numScore.velocity.y -= FlxG.random.int(140, 160) * playbackRate;
					numScore.velocity.x = FlxG.random.float(-5, 5) * playbackRate;
				}
				else
				{
					if (ClientPrefs.data.ratingFallStyle == "Leather")
					{
						// Leather 风格
						numScore.velocity.y = FlxG.random.int(30, 60);
						numScore.velocity.x = FlxG.random.float(-5, 5);
					}
					else if (ClientPrefs.data.ratingFallStyle == "Legacy")
					{
						// Legacy 风格，跟 rating 一样的加速度逻辑
						numScore.acceleration.y = FlxG.random.int(200, 300) * playbackRate * playbackRate;
						numScore.velocity.y -= FlxG.random.int(140, 160) * playbackRate;
						numScore.velocity.x = FlxG.random.float(-5, 5) * playbackRate;
					}
					else if (isKathyStyle)
					{
						numScore.velocity.y = 0;
						numScore.velocity.x = 0;
						FlxTween.tween(numScore, {y: numScore.y + FlxG.random.int(12, 18)}, 0.2, {ease: FlxEase.quintOut});
					}
					else 
					{
						numScore.velocity.y = FlxG.random.int(30, 60);
						numScore.velocity.x = FlxG.random.float(-5, 5);
					}
				}
				numScore.visible = !ClientPrefs.data.hideHud;
				numScore.antialiasing = antialias;

				// if (combo >= 10 || combo == 0)
				if (showThisComboNum)
					addToComboLayer(numScore);

				// 根据不同的跳动风格设置渐隐延迟
				var numScoreFadeDelay:Float = Conductor.crochet * 0.002 / playbackRate;
				if (isCamellia)
				{
					// Camellia 使用固定时序：停留 0.75s 后淡出，不随 BPM 变化
					numScoreFadeDelay = CAMELLIA_HOLD / playbackRate;
				}
				else if (!ClientPrefs.data.comboStacking && isKathyStyle)
				{
					// Kathy模式下，跳动完成后才开始渐隐
					numScoreFadeDelay += 0.2;
				}

				FlxTween.tween(numScore, {alpha: 0}, fadeDuration / playbackRate, {
					onComplete: function(tween:FlxTween)
					{
						killComboSprite(numScore);
					},
					startDelay: numScoreFadeDelay
				});

				daLoop++;
				if (numScore.x > xThing)
					xThing = numScore.x;
			}
			comboSpr.x = xThing + 50; // 跟随最大数字 xThing，偏移由 numScore 的 [2,3] 承载，不可独立调整
			// msTimeTxt 基于 numScore 对齐：启用 "combo" 单词(comboSprDisplay)时跟到单词之后，否则紧跟数字末位，
			// comboOffset[6] 作为二次微调（与 NoteOffsetState 预览保持一致）
			// 注意：必须用 showThisCombo（本次是否真的可见）而非 comboSprDisplay（模式开关），
			// 否则 OG Funkin 模式 combo≤10 时 comboSpr 隐藏但 xThing=0，会导致 msTimeTxt 被推到屏幕极左。
			if (ClientPrefs.data.msTimingOffsetMode == 'numScore') {
				if (showThisCombo)
					msTimeTxt.x = comboSpr.x + comboSpr.width + 5 - 20 - 40 + ClientPrefs.data.comboOffset[6];
				else {
					// 不显示 "combo" 单词时紧跟数字末位：以 3 位数为基准（与 NoteOffsetState 预览一致），
					// 再按 numScore 的 43px/位 间距补偿实际位数差，否则位数变化（如 Default 模式 1→4 位）时文本不跟随。
					// 数字整体不显示时（OG Funkin combo≤10）退回 3 位基准，避免 xThing=0 把文本推到屏幕极左。
					var numDigits:Int = showThisComboNum ? separatedScore.length : 3;
					msTimeTxt.x = FlxG.width * 0.35 + 100 + ClientPrefs.data.comboOffset[2] + ClientPrefs.data.comboOffset[6] + 60 - 20 - 40 + 43 * (numDigits - 3);
				}
			}
		comboJustBroke = false; // 本次命中已消费断连标记

			// 根据不同的跳动风格设置渐隐延迟
			var ratingFadeDelay:Float = Conductor.crochet * 0.001 / playbackRate;
			var exRatingFadeDelay:Float = Conductor.crochet * 0.0008 / playbackRate;
			var comboFadeDelay:Float = Conductor.crochet * 0.0015 / playbackRate;


			if (isCamellia)
			{
				// Camellia 使用固定时序：三者统一停留 0.75s 后淡出，不随 BPM 变化
				ratingFadeDelay = exRatingFadeDelay = comboFadeDelay = CAMELLIA_HOLD / playbackRate;
			}
			else if (!ClientPrefs.data.comboStacking && isKathyStyle)
			{
				// Kathy模式下，跳动完成后才开始渐隐
				ratingFadeDelay += 0.2;
				exRatingFadeDelay += 0.2;
				comboFadeDelay += 0.2;
			}

			FlxTween.tween(rating, {alpha: 0}, fadeDuration / playbackRate, {
				onComplete: function(tween:FlxTween)
				{
					killComboSprite(rating);
				},
				startDelay: ratingFadeDelay
			});
			FlxTween.tween(theEXrating, {alpha: 0}, fadeDuration / playbackRate, {
				onComplete: function(tween:FlxTween)
				{
					killComboSprite(theEXrating);
				},
				startDelay: exRatingFadeDelay
			});

			FlxTween.tween(comboSpr, {alpha: 0}, fadeDuration / playbackRate, {
				onComplete: function(tween:FlxTween)
				{
					killComboSprite(comboSpr);
				},
				startDelay: comboFadeDelay
			});
		}
	}

	function updateRatingCounters() {
	// 使用新的 RatingCounter 模块更新计数
	if (ratingCounterModule != null)
	{
		ratingCounterModule.updateCounters();
	}
}

	public var strumsBlocked:Array<Bool> = [];
	private function onKeyPress(event:KeyboardEvent):Void
	{

		var eventKey:FlxKey = event.keyCode;
		var key:Int = getKeyFromEvent(keysArray, eventKey);

		if (!controls.controllerMode)
		{
			#if debug
			//Prevents crash specifically on debug without needing to try catch shit
			@:privateAccess if (!FlxG.keys._keyListMap.exists(eventKey)) return;
			#end

			if(FlxG.keys.checkStatus(eventKey, JUST_PRESSED) || (Reflect.hasField(event, "replay") && Reflect.field(event, "replay") == true))
			{
				if(key != -1)
					keyPressed(key);
				else
				{
					// 非音符键：记录（如果未被列为忽略的主要功能键）
					if(shouldRecordKey(eventKey))
					{
						if(!isReplaying)
						{
							replayData.push({
								time: Conductor.songPosition,
								key: NON_NOTE_KEY_OFFSET + eventKey,
								noteTime: null,
								late: null,
								judge: 'raw',
								releaseTime: null
							});
							nonNoteKeyPressIndices.set(eventKey, replayData.length - 1);
							replayHeldNonNoteKeys.set(NON_NOTE_KEY_OFFSET + eventKey, true);
						}
						// 调用脚本回调（可选，脚本可监听）
						callOnScripts('onRawKeyPress', [eventKey]);
					}
				}
			}
		}
	}

	private function keyPressed(key:Int)
	{
		if(cpuControlled || paused || inCutscene || key < 0 || key >= playerSideStrums().length || !generatedMusic || endingSong || playerSideChar().stunned || isReplaying) return;

		var ret:Dynamic = callOnScripts('onKeyPressPre', [key]);
		if(ret == LuaUtils.Function_Stop) return;

		// 毫秒级精确判定（可在设置中开关 preciseHit）：
		// 开启时用按键瞬间的音频时钟同步 songPosition 并实时计算判定窗口，消除约1帧的滞后与边界误判；
		// 关闭时沿用原逻辑（依赖上一帧 update 缓存的 n.canBeHit 与 songPosition）。
		var preciseHit:Bool = ClientPrefs.data.preciseHit;
		var lastTime:Float = Conductor.songPosition;
		if (preciseHit && FlxG.sound.music != null && FlxG.sound.music.playing)
			Conductor.songPosition = FlxG.sound.music.time + Conductor.offset;

		var plrInputNotes:Array<Note> = notes.members.filter(function(n:Note):Bool {
			if (n == null || !n.exists || n.isSustainNote || n.noteData != key) return false;
			if (strumsBlocked[n.noteData] || !isPlayerNote(n) || n.tooLate || n.wasGoodHit || n.blockHit) return false;
			if (preciseHit)
			{
				var timeUntilHit:Float = n.strumTime - Conductor.songPosition;
				var earlyWindow:Float = Conductor.safeZoneOffset * n.earlyHitMult;
				var lateWindow:Float = Conductor.safeZoneOffset * n.lateHitMult;
				return (timeUntilHit > -lateWindow && timeUntilHit < earlyWindow);
			}
			return n.canBeHit;
		});

		// 根据输入系统设置选择排序方式
		var dontHit:Array<Note> = [];
		if (ClientPrefs.data.inputSystem == 'rhythm')
		{
			// Rhythm模式：按时间距离降序排列（离当前时间最远的/最过期的排在前面）
			plrInputNotes.sort(function(a:Note, b:Note):Int {
				if (a.lowPriority && !b.lowPriority) return 1;
				else if (!a.lowPriority && b.lowPriority) return -1;
				return FlxSort.byValues(FlxSort.DESCENDING, a.strumTime, b.strumTime);
			});

			// Rhythm模式的dontHit机制：只允许击中离判定线最近的shouldHit音符，其余标记为dontHit
			// shouldHit等效判定：非blockHit且非hitCausesMiss（即普通可击中音符）
			var coolNote:Note = null;
			for (note in plrInputNotes) {
				var isShouldHit:Bool = !note.blockHit && !note.hitCausesMiss;
				if (coolNote != null) {
					if (note.strumTime > coolNote.strumTime && isShouldHit)
						dontHit.push(note);
				} else if (isShouldHit) {
					coolNote = note;
				}
			}
		}
		else
		{
			// 默认模式：按strumTime升序排列（最近的音符在前）
			plrInputNotes.sort(sortHitNotes);
		}

		// 记录按键按下的索引（用于后续记录抬起动作）- 在判断是否有音符之后设置，以确保索引正确
		// key < keysArray.length 以兼容多键（原硬编码 < 4 导致 5/6 键 releaseTime 永不被记录 → 回放箭头卡按下）
		if(!isReplaying && key >= 0 && key < keysArray.length)
		{
			// 先记录索引
			keyPressIndices[key] = replayData.length;
		}

		if (plrInputNotes.length != 0) { // slightly faster than doing `> 0` lol
			var funnyNote:Note = plrInputNotes[0]; // front note

			if (plrInputNotes.length > 1) {
				var doubleNote:Note = plrInputNotes[1];

				if (doubleNote.noteData == funnyNote.noteData) {
					// if the note has a 0ms distance (is on top of the current note), kill it
					if (Math.abs(doubleNote.strumTime - funnyNote.strumTime) < 1.0)
						invalidateNote(doubleNote);
					// 仅在两者优先级相同时才按时间替换，避免用低优先级音符（如危险箭头 Hurt Note）
					// 顶替掉已由排序选出的普通箭头，从而导致普通箭头与危险箭头相邻时误命中危险箭头
					else if (doubleNote.strumTime < funnyNote.strumTime && doubleNote.lowPriority == funnyNote.lowPriority)
					{
						// replace the note if its ahead of time (or at least ensure "doubleNote" is ahead)
						funnyNote = doubleNote;
					}
				}
			}

			// Rhythm模式：如果击中的音符在dontHit列表中，触发miss而非goodNoteHit
			if (ClientPrefs.data.inputSystem == 'rhythm' && dontHit.contains(funnyNote))
			{
				noteMiss(funnyNote);
				invalidateNote(funnyNote);
			}
			else
			{
				goodNoteHit(funnyNote);
			}
		}
		else
		{
			// ghostTapping开启时，也需要记录回放数据
			if(!isReplaying)
			{
				replayData.push({
					time: Conductor.songPosition,
					key: key,
					noteTime: null,
					late: null,
					judge: 'ghost',
					releaseTime: null
				});
			}
			handleGhostTap(key);
		}

		// Needed for the  "Just the Two of Us" achievement.
		//									- Shadow Mario

	// [毫秒级精确判定] 开启时 songPosition 被临时改为精确值，这里还原为本帧原值，避免影响后续逻辑与音符视觉位置（防抖动）；下一帧 update 会重新从音频时钟同步。
	if (preciseHit) Conductor.songPosition = lastTime;

		var spr:StrumNote = playerSideStrums().members[key];
		if(strumsBlocked[key] != true && spr != null && (spr.animation.curAnim == null || spr.animation.curAnim.name != 'confirm'))
		{
			spr.playAnim('pressed');
			spr.resetAnim = 0; // 不自动重置，由按键释放时重置
		}
		callOnScripts('onKeyPress', [key]);
	}

	public static function sortHitNotes(a:Note, b:Note):Int
	{
		if (a.lowPriority && !b.lowPriority)
			return 1;
		else if (!a.lowPriority && b.lowPriority)
			return -1;

		return FlxSort.byValues(FlxSort.ASCENDING, a.strumTime, b.strumTime);
	}

	private function onKeyRelease(event:KeyboardEvent):Void
	{
		var eventKey:FlxKey = event.keyCode;
		var key:Int = getKeyFromEvent(keysArray, eventKey);
		if(!controls.controllerMode)
		{
			if(key > -1) keyReleased(key);
			else
			{
				// 非音符键抬起：更新回放数据并触发脚本回调
				if(shouldRecordKey(eventKey))
				{
					var idx:Int = nonNoteKeyPressIndices.exists(eventKey) ? nonNoteKeyPressIndices.get(eventKey) : -1;
					if(!isReplaying && idx >= 0 && idx < replayData.length)
					{
						replayData[idx].releaseTime = Conductor.songPosition;
						nonNoteKeyPressIndices.remove(eventKey);
					}
					callOnScripts('onRawKeyRelease', [eventKey]);
				}
			}
		}
	}

	private function keyReleased(key:Int)
	{
		if(cpuControlled || !startedCountdown || paused || key < 0 || key >= playerSideStrums().length || isReplaying) return;

		var ret:Dynamic = callOnScripts('onKeyReleasePre', [key]);
		if(ret == LuaUtils.Function_Stop) return;

		// 记录按键抬起动作（key < keysArray.length 以兼容多键；releaseTime 用于回放时释放箭头）
		if(!isReplaying && key >= 0 && key < keysArray.length && keyPressIndices[key] >= 0)
		{
			// 更新对应按下记录的抬起时间
			if(keyPressIndices[key] < replayData.length)
			{
				replayData[keyPressIndices[key]].releaseTime = Conductor.songPosition;
			}
			keyPressIndices[key] = -1;
		}

		// 特性1：guitarHeroSustains 下，长条命中期间松手立刻判定 miss
		if(guitarHeroSustains && holdReleaseInstantMiss)
			tryInstantSustainMiss(key);

		// 特性2：在松手时按其释放时机判定长条尾部（加combo+评级, 不加分）
		if(guitarHeroSustains && holdTailJudge)
			tryTailJudgeOnRelease(key);

		var spr:StrumNote = playerSideStrums().members[key];
		if(spr != null)
		{
			spr.playAnim('static');
			spr.resetAnim = 0;
			spr.holdConfirmActive = false;
		}
		// 松手隐藏该列 Hold Cover（不打断已完成长条的 end 动画）
		hideHoldCover(true, key, false);
		callOnScripts('onKeyRelease', [key]);
	}

	// 特性1：松手立刻判定 miss。找到该列一个"头部已命中、但尚未命中且未过期"的长条尾音，立刻触发 miss。
	// 若该列所有长条尾音都已命中（长条已完成），则不会误判 miss。
	private function tryInstantSustainMiss(key:Int):Void
	{
		if(!guitarHeroSustains || !holdReleaseInstantMiss) return;
		if(cpuControlled || endingSong || !startedCountdown || !generatedMusic) return;
		if(key < 0 || notes.length <= 0) return;

		var target:Note = null;
		for (n in notes)
		{
			if(n == null || !n.exists || !n.isSustainNote || !isPlayerNote(n)) continue;
			if(n.noteData != key) continue;
			if(n.wasGoodHit || n.tooLate || n.missed || n.ignoreNote || n.blockHit) continue;
			if(n.parent == null || !n.parent.wasGoodHit) continue; // 头部必须已命中(长条正在进行中)
			// 选取最早的一个未命中尾音
			if(target == null || n.strumTime < target.strumTime) target = n;
		}

		if(target != null)
			noteMiss(target); // noteMissCommon 会连带把同一长条的其余尾音标记为 missed 并断连
	}

	// 特性2：在松手(key release)时判定长条尾部。仅 guitarHeroSustains 模式生效。
	// 找到该列"头部已命中、尾部尚未命中且在可命中窗口内"的长条，按其释放时机给一次有效命中
	// （加 combo + 显示评级，但不加分）。若松手过晚（尾部已 tooLate）则不判定，由现有 miss 逻辑断连。
	private function tryTailJudgeOnRelease(key:Int):Void
	{
		if(!guitarHeroSustains || !holdTailJudge || cpuControlled) return;
		if(endingSong || !startedCountdown || !generatedMusic) return;
		if(key < 0 || notes.length <= 0) return;

		var lastTail:Note = null;
		for (n in notes)
		{
			if(n == null || !n.exists || !n.isSustainNote || !isPlayerNote(n)) continue;
			if(n.noteData != key) continue;
			if(n.parent == null || !n.parent.wasGoodHit || n.parent.missed) continue;
			// 取该列当前活跃长条的最后一个尾音
			if(lastTail == null || n.strumTime > lastTail.strumTime) lastTail = n;
		}

		// 仅在最后一个尾音尚未命中、且当前处于其判定窗口内时判定；
		// 判定窗口 = [strumTime - len, strumTime + lateWindow + len]，len 为特性2宽容量(ms)。
		// 超出则视为释放时机不当，交由 tooLate/kill 逻辑触发 miss（按久超时照样断连并加miss）。
		if(lastTail != null && !lastTail.wasGoodHit)
		{
			var lateWindow:Float = Conductor.safeZoneOffset * lastTail.lateHitMult;
			var len:Float = (holdTailLeniency) ? holdTailLeniencyMs : 0;
			var lowerBound:Float = lastTail.strumTime - len;                 // 放宽早松手
			var upperBound:Float = lastTail.strumTime + lateWindow + len;    // 放宽晚松手(含原 lateWindow)
			var songPos:Float = Conductor.songPosition;
			if(songPos >= lowerBound && songPos <= upperBound)
				goodNoteHit(lastTail); // 触发 goodNoteHit 中"尾部有效命中"分支(combo+评级, 不加分)
		}
	}



	// 特性3：长条命中期间持续加分（参考原版Funkin：songScore += SCORE_HOLD_BONUS_PER_SECOND * elapsed）
	// 对每一列，只要该列有"头部已命中、尚未过期"的长条尾音且该列按键被按住，就按时间比例累加分数。
	private function updateHoldScore(elapsed:Float):Void
	{
		if(!holdScoreBonus) return;
		if(cpuControlled && !ClientPrefs.data.botplayScore) return;
		if(!generatedMusic || !startedCountdown || inCutscene || endingSong) return;
		if(notes.length <= 0) return;

		// 每列是否按住（与 keysCheck 保持一致）
		_heldBuffer.splice(0, _heldBuffer.length);
		for (i in 0...keysArray.length)
		{
			if(cpuControlled) _heldBuffer.push(true);
			else if(isReplaying) _heldBuffer.push(replayHeldKeys[i]);
			else _heldBuffer.push(controls.pressed(keysArray[i]) || mobileHoldPressed(i));
		}

		// 统计当前正在被有效按住的长条列数（每列只计一次，避免同列多个尾音重复计分）
		_countedBuffer.splice(0, _countedBuffer.length);
		for (i in 0...keysArray.length)
			_countedBuffer.push(false);
		var activeCols:Int = 0;
		for (n in notes)
		{
			if(n == null || !n.exists || !n.isSustainNote || !isPlayerNote(n)) continue;
			if(n.tooLate || n.missed || n.ignoreNote) continue;
			if(n.parent == null || !n.parent.wasGoodHit) continue; // 头部已命中(长条进行中)
			if(n.noteData < 0 || n.noteData >= _countedBuffer.length || _countedBuffer[n.noteData]) continue;
			if(!_heldBuffer[n.noteData]) continue;
			_countedBuffer[n.noteData] = true;
			activeCols++;
		}

		if(activeCols > 0)
		{
			holdScoreRemainder += HOLD_SCORE_BONUS_PER_SECOND * elapsed * activeCols;
			if(holdScoreRemainder >= 1)
			{
				var add:Int = Std.int(holdScoreRemainder);
				songScore += add;
				holdScoreRemainder -= add;
				updateScoreText();
			}
		}
	}

	public static function getKeyFromEvent(arr:Array<String>, key:FlxKey):Int
	{
		if(key != NONE)
		{
			for (i in 0...arr.length)
			{
				var note:Array<FlxKey> = Controls.instance.keyboardBinds[arr[i]];
				for (noteKey in note)
					if(key == noteKey)
						return i;
			}
		}
		return -1;
	}

	// 判断是否应该记录该按键为回放（排除主要功能键）
	private function shouldRecordKey(eventKey:FlxKey):Bool
	{
		// 过滤掉 ESC 与 ENTER（用户要求）
		if(eventKey == FlxKey.ESCAPE || eventKey == FlxKey.ENTER) return false;
		// 只要不是 ESC/ENTER 并且不是映射到箭头（getKeyFromEvent 已处理），就记录
		return true;
	}

	private function onButtonPress(button:TouchButton):Void
	{
		if (button.IDs.filter(id -> id.toString().startsWith("EXTRA")).length > 0)
			return; // 非音符的 EXTRA 按钮（如暂停）不触发音符
		if (button.tag == 'P')
			return; // P 暂停按钮不触发音符

		var buttonCode:Int = (button.IDs[0].toString().startsWith('NOTE')) ? button.IDs[0] : button.IDs[1];
		buttonCode = noteCodeToIndex(buttonCode); // 多键 NOTE_4..NOTE_17 -> 音符索引 4..17
		callOnScripts('onButtonPressPre', [buttonCode]);
		if (button.justPressed) keyPressed(buttonCode);
		callOnScripts('onButtonPress', [buttonCode]);
	}

	private function onButtonRelease(button:TouchButton):Void
	{
		if (button.IDs.filter(id -> id.toString().startsWith("EXTRA")).length > 0)
			return;
		if (button.tag == 'P')
			return; // P 暂停按钮不触发音符

		var buttonCode:Int = (button.IDs[0].toString().startsWith('NOTE')) ? button.IDs[0] : button.IDs[1];
		buttonCode = noteCodeToIndex(buttonCode); // 多键 NOTE_4..NOTE_17 -> 音符索引 4..17
		callOnScripts('onButtonReleasePre', [buttonCode]);
		// 同一音符列可能绑定多个触屏按钮（双 Pad 模式左右两套方向键都绑定 NOTE_LEFT）：
		// 只有该列所有按钮都已松开时才触发释放，避免另一根手指仍按住时长条被误判断开
		if(buttonCode > -1 && !mobileHoldPressed(buttonCode)) keyReleased(buttonCode);
		callOnScripts('onButtonRelease', [buttonCode]);
	}

	/** 触屏按钮的 NOTE_* 枚举值 -> 音符列索引（NOTE_LEFT=0..NOTE_RIGHT=3，NOTE_4..NOTE_17=4..17） */
	private static function noteCodeToIndex(code:Int):Int
	{
		if (code >= 0 && code <= 3) return code; // NOTE_LEFT..NOTE_RIGHT
		if (code >= Std.int(MobileInputID.NOTE_9)) return 9 + (code - Std.int(MobileInputID.NOTE_9)); // 51..59 -> 9..17
		if (code >= Std.int(MobileInputID.NOTE_4)) return 4 + (code - Std.int(MobileInputID.NOTE_4)); // 44..48 -> 4..8
		return code;
	}

	/**
	 * 触屏按住判定：多键档位的 action 名（如 "4_key_4"）没有注册到 Controls.mobileBinds，
	 * 仅靠 controls.pressed() 轮询不到触屏按键，导致长条头段命中后无法续上。
	 * 这里按列索引直接查询当前触屏控件的 NOTE_* 按钮。
	 */
	private function mobileHoldPressed(lane:Int):Bool
	{
		if (mobileControls == null || mobileControls.instance == null)
			return false;

		return mobileControls.instance.buttonHeld(MobileInputID.noteForLane(lane));
	}

	// Hold notes
	private function keysCheck():Void
	{
		// HOLDING — 复用缓冲数组，避免每帧分配
		_holdBuffer.splice(0, _holdBuffer.length);
		_pressBuffer.splice(0, _pressBuffer.length);
		_releaseBuffer.splice(0, _releaseBuffer.length);
		for (i in 0...keysArray.length)
		{
			// 在回放模式下使用replayHeldKeys，否则使用controls.pressed
			if(isReplaying)
			{
				_holdBuffer.push(replayHeldKeys[i]);
				_pressBuffer.push(false); // 回放模式下不使用justPressed
				_releaseBuffer.push(false); // 回放模式下不使用justReleased
			}
			else
			{
				_holdBuffer.push(controls.pressed(keysArray[i]) || mobileHoldPressed(i));
				_pressBuffer.push(controls.justPressed(keysArray[i]));
				_releaseBuffer.push(controls.justReleased(keysArray[i]));
			}
		}

		// TO DO: Find a better way to handle controller inputs, this should work for now
		if(controls.controllerMode && _pressBuffer.contains(true))
			for (i in 0..._pressBuffer.length)
				if(_pressBuffer[i] && strumsBlocked[i] != true)
					keyPressed(i);

		if (startedCountdown && !inCutscene && !playerSideChar().stunned && generatedMusic)
		{

			if (notes.length > 0) {
				for (n in notes) { // I can't do a filter here, that's kinda awesome
					if (n == null || !n.exists) continue; // 帧末批量模式下跳过本帧已销毁的“死音符”
					var canHit:Bool = (!strumsBlocked[n.noteData] && n.canBeHit
						&& isPlayerNote(n) && !n.tooLate && !n.wasGoodHit && !n.blockHit);

					if (guitarHeroSustains)
						canHit = canHit && n.parent != null && n.parent.wasGoodHit;

					if (canHit && n.isSustainNote) {
						var released:Bool = !_holdBuffer[n.noteData];

						// 特性2：启用尾部判定时，最后一个尾音不在按住期间自动命中，
						// 改在松手(keyReleased)时按其释放时机判定；botplay 仍照常完成。
						if (!released && !(holdTailJudge && guitarHeroSustains && !cpuControlled
							&& n.parent != null && n.parent.tail.length > 0
							&& n.parent.tail[n.parent.tail.length - 1] == n))
							goodNoteHit(n);
					}
				}
			}

			if (!_holdBuffer.contains(true) || endingSong)
				playerDance();

			#if ACHIEVEMENTS_ALLOWED
			else checkForAchievement(['oversinging']);
			#end
		}

		// TO DO: Find a better way to handle controller inputs, this should work for now
		if((controls.controllerMode || strumsBlocked.contains(true)) && _releaseBuffer.contains(true))
			for (i in 0..._releaseBuffer.length)
				if(_releaseBuffer[i] || strumsBlocked[i] == true)
					keyReleased(i);
	}

	function noteMiss(daNote:Note):Void { //You didn't hit the key and let it go offscreen, also used by Hurt Notes
		// 记录回放数据（仅在非回放模式下）
		if(!isReplaying && isPlayerNote(daNote) && !daNote.isSustainNote)
		{
			replayData.push({
				time: Conductor.songPosition,
				key: daNote.noteData,
				noteTime: daNote.strumTime,
				late: null,
				judge: 'miss',
				releaseTime: null
			});
		}
		
		//Dupe note remove
		notes.forEachAlive(function(note:Note) {
			if (daNote != note && isPlayerNote(daNote) && daNote.noteData == note.noteData && daNote.isSustainNote == note.isSustainNote && Math.abs(daNote.strumTime - note.strumTime) < 1)
				invalidateNote(note);
		});

		noteMissCommon(daNote.noteData, daNote);
		stagesFunc(function(stage:BaseStage) stage.noteMiss(daNote));
		if (!effectiveDisableNoteLua())
		{
			var result:Dynamic = callOnLuas('noteMiss', [luaNoteIndex(daNote), daNote.noteData, daNote.noteType, daNote.isSustainNote]);
			if(result != LuaUtils.Function_Stop && result != LuaUtils.Function_StopHScript && result != LuaUtils.Function_StopAll) callOnHScript('noteMiss', [daNote]);
		}
		// Leather modchart 事件：playerOneMiss（对照 LE 原版 PlayState ~3510：
		// 参数 = [noteData, songPosition, arrowType, isHeld]）
		callOnLeatherScripts('playerOneMiss',
			[Math.abs(daNote.noteData), Conductor.songPosition, daNote.noteType, daNote.isSustainNote]);
	}

	function noteMissPress(direction:Int = 1):Void //You pressed a key when there was no notes to press for this key
	{
		noteMissCommon(direction);
		playShortHitSound(Paths.soundRandom('missnote', 1, 3), FlxG.random.float(0.1, 0.2));
		stagesFunc(function(stage:BaseStage) stage.noteMissPress(direction));
		callOnScripts('noteMissPress', [direction]);
	}

	// Ghost Miss 惩罚：扣血跟随健康模型 + healthLoss 倍率，分数 -10（与普通 miss 一致）
	function ghostNoteMiss(direction:Int):Void
	{
		// 扣血 —— 完全跟随 noteMissCommon 的逻辑，不复用函数以避免 hideHoldCover / guitarHeroSustains 等 ghost tap 无关副作用
		var subtract:Float = pressMissDamage;
		var healthModel:String = ClientPrefs.getGameplaySetting('healthmodel', 'default');
		if (healthModel == 'kade')
			health -= 0.04 * healthLoss;
		else if (healthModel == 'forever')
		{
			if (foreverMissPunish <= 0.01) foreverMissPunish = 1.0;
			health -= 0.035 * foreverMissPunish * healthLoss;
			foreverMissPunish += 0.075;
		}
		else
			health -= subtract * healthLoss;
		if (health < 0) health = 0;

		var lastCombo:Int = combo;
		combo = 0;
		if (lastCombo > 0) comboJustBroke = true;

		songScore -= 10;
		if (!endingSong) songMisses++;

		// 角色 miss 动画（LE LTS 双侧：受控角色为 dad 时用对手档 sing 动画）
		var char:Character = playerSideChar();
		if(char != null && char.hasMissAnimations)
		{
			var animToPlay:String = singAnimsFor(char)[Std.int(Math.abs(Math.min(singAnimsFor(char).length-1, direction)))] + 'miss';
			char.playAnim(animToPlay, true);

			if(char != gf && lastCombo > 5 && gf != null && gf.hasAnimation('sad'))
			{
				gf.playAnim('sad');
				gf.specialAnim = true;
			}
		}

		// 静音 vocals
		if (playOpponent && opponentVocals != null && opponentVocals.length > 0) opponentVocals.volume = 0;
		else if (vocals != null && vocals.exists) vocals.volume = 0;

		playShortHitSound(Paths.soundRandom('missnote', 1, 3), FlxG.random.float(0.1, 0.2));
		callOnScripts('ghostNoteMiss', [direction]);
	}

	// V-Slice Ghost Tap：检查该方向是否允许空按不惩罚
	function mayGhostTap(direction:Int):Bool
	{
		// 冷却中 → 不允许空按
		if (ghostTapTimer[direction] > 0) return false;
		// 玩家侧判定范围内有音符 → 不允许空按（原版 getNotesMayHit 语义）
		if (hasPlayerNotesInRange()) return false;
		return true;
	}

	// V-Slice Ghost Tap 辅助：玩家侧判定范围内是否有音符（原版 getNotesMayHit）
	function hasPlayerNotesInRange():Bool
	{
		for (n in notes.members)
		{
			if (n == null || !n.exists) continue;
			if (!isPlayerNote(n)) continue;
			if (n.wasGoodHit || n.tooLate || n.blockHit) continue;
			var timeUntilHit:Float = n.strumTime - Conductor.songPosition;
			var earlyWindow:Float = Conductor.safeZoneOffset * n.earlyHitMult;
			var lateWindow:Float = Conductor.safeZoneOffset * n.lateHitMult;
			if (timeUntilHit > -lateWindow && timeUntilHit < earlyWindow) return true;
		}
		return false;
	}

	// V-Slice Ghost Tap 辅助：屏幕上是否有玩家音符（包括还没到判定线的、刚过判定线还没消失的）
	// 原版 updateGhostTapTimer 用这个（getNotesOnScreen 语义）—— 屏幕上无音符时冷却才开始递减
	function hasPlayerNotesOnScreen():Bool
	{
		var earlyCutoff:Float = Conductor.songPosition - Conductor.safeZoneOffset;
		var lateCutoff:Float = Conductor.songPosition + Conductor.safeZoneOffset * 3;
		for (n in notes.members)
		{
			if (n == null || !n.exists) continue;
			if (!isPlayerNote(n)) continue;
			if (n.wasGoodHit || n.blockHit) continue;
			if (n.strumTime >= earlyCutoff && n.strumTime <= lateCutoff) return true;
		}
		return false;
	}

	// 空按箭头处理：根据 ghostTappingMode 走不同分支
	private function handleGhostTap(key:Int):Void
	{
		// Bool 兼容层同步 —— 模组运行时改 ghostTapping Bool 能生效
		var curMode:String = ClientPrefs.data.ghostTappingMode;
		var expectBool:Bool = curMode != 'off';
		if (ClientPrefs.data.ghostTapping != expectBool)
		{
			ClientPrefs.data.ghostTappingMode = ClientPrefs.data.ghostTapping ? 'always' : 'off';
		}
		switch (ClientPrefs.data.ghostTappingMode)
		{
			case 'always':
				// 始终允许 — 空按永不惩罚
				callOnScripts('onGhostTap', [key]);

			case 'whenSinging':
				// 唱歌时启用惩罚 — 有音符时惩罚（+ 375ms 冷却期），无音符时空按不惩罚
				// mayGhostTap 已同时包含冷却期检查 + 判定窗口音符检查
				if (mayGhostTap(key))
					callOnScripts('onGhostTap', [key]);
				else
					ghostNoteMiss(key);

			case 'whenNotSinging':
				// 唱歌时禁用惩罚（反向）— 判定窗口有音符时空按不惩罚，无音符时空按惩罚
				if (hasPlayerNotesInRange())
					callOnScripts('onGhostTap', [key]);
				else
					ghostNoteMiss(key);

			case _: // 'off' 及其他未知值
				// 完全禁用 — 空按总是触发完整 miss 惩罚
				noteMissPress(key);
		}
		addToKeysPressed(key);
	}

	// 去重追加到 keysPressed（用于 achievement 追踪）
	private function addToKeysPressed(key:Int):Void
	{
		if (!keysPressed.contains(key))
			keysPressed.push(key);
	}

	// 音符回调的 index 参数取值：默认沿用 notes.members.indexOf()（Psych 原版语义，完全兼容既有 modchart）；
	// 仅在 luaNoteIndexPerf 开启时改用稳定生成序号 preloadIndex，消除脚本激活时每次命中/生成的全数组 O(n) 扫描。
	inline function luaNoteIndex(n:Note):Int
		return ClientPrefs.data.luaNoteIndexPerf ? n.preloadIndex : notes.members.indexOf(n);

	function noteMissCommon(direction:Int, note:Note = null)
	{
		// miss 时立即隐藏该列 Hold Cover
		hideHoldCover(true, direction);

		// score and data
		var subtract:Float = pressMissDamage;
		if(note != null) subtract = note.missHealth;

		// GUITAR HERO SUSTAIN CHECK LOL!!!!
		if (note != null && guitarHeroSustains && note.parent == null) {
			if(note.tail.length > 0) {
				note.alpha = 0.35;
				for(childNote in note.tail) {
					childNote.alpha = note.alpha;
					childNote.missed = true;
					childNote.canBeHit = false;
					childNote.ignoreNote = true;
					childNote.tooLate = true;
				}
				note.missed = true;
				note.canBeHit = false;

				//subtract += 0.385; // you take more damage if playing with this gameplay changer enabled.
				// i mean its fair :p -Crow
				subtract *= note.tail.length + 1;
				// i think it would be fair if damage multiplied based on how long the sustain is -[REDACTED]
			}

			if (note.missed)
				return;
		}
		if (note != null && guitarHeroSustains && note.parent != null && note.isSustainNote) {
			if (note.missed)
				return;

			var parentNote:Note = note.parent;
			if (parentNote.wasGoodHit && parentNote.tail.length > 0) {
				for (child in parentNote.tail) if (child != note) {
					child.missed = true;
					child.canBeHit = false;
					child.ignoreNote = true;
					child.tooLate = true;
				}
			}
		}

		if(instakillOnMiss)
		{
			vocals.volume = 0;
			opponentVocals.volume = 0;
			doDeathCheck(true);
		}

		var lastCombo:Int = combo;
		combo = 0;
		if (lastCombo > 0) comboJustBroke = true; // 仅在真正断连(此前有combo)时置位

			// Kade 血量：miss 固定扣血 0.04 × healthLoss
			if (ClientPrefs.getGameplaySetting('healthmodel', 'default') == 'kade')
				health -= 0.04 * healthLoss;
			// Forever 血量：连续 miss 递增惩罚，从 0.035 开始每次 +0.075
			else if (ClientPrefs.getGameplaySetting('healthmodel', 'default') == 'forever')
			{
				if (foreverMissPunish <= 0.01) foreverMissPunish = 1.0;
				health -= 0.035 * foreverMissPunish * healthLoss;
				foreverMissPunish += 0.075;
			}
			else
				health -= subtract * healthLoss;
		// Kade 计分：长条(sustain) miss 额外再扣 0.075 × healthLoss（对齐 Kade tooLate 分支的额外惩罚）
		if (ClientPrefs.getGameplaySetting('healthmodel', 'default') == 'kade' && note != null && note.isSustainNote)
			health -= 0.075 * healthLoss;
		songScore -= 10;
		if(!endingSong) songMisses++;
		// Kade Complex 模式：miss 时准确率分子 -1（等效 miss_weight=-5.5 的归一化扣减）
		// 长条准确率开关关闭时，长条 miss 不影响分子（完全忽略长条对准确率的贡献）
		if(ClientPrefs.data.accuracyMode.toLowerCase() == 'complex' && (note == null || !note.isSustainNote || ClientPrefs.data.sustainAccuracy))
			totalNotesHit -= 1;
		// 长条准确率开关关闭时，长条 miss 也不计入分母（与命中侧一致，完全忽略长条对准确率的贡献）
		if(note == null || !note.isSustainNote || ClientPrefs.data.sustainAccuracy)
		{
			totalPlayed++;
			RecalculateRating(true);
		}
		else
			RecalculateRating(true);

		// play character anims（playOpponent 时受控角色是 dad；LE LTS 双侧：dad 用对手档 sing 动画）
		var char:Character = playerSideChar();
		if((note != null && note.gfNote) || (SONG.notes[curSection] != null && SONG.notes[curSection].gfSection)) char = gf;

		if(char != null && (note == null || !note.noMissAnimation) && char.hasMissAnimations)
		{
			var postfix:String = '';
			if(note != null) postfix = note.animSuffix;

			var animToPlay:String = singAnimsFor(char)[Std.int(Math.abs(Math.min(singAnimsFor(char).length-1, direction)))] + 'miss' + postfix;
			char.playAnim(animToPlay, true);

			if(char != gf && lastCombo > 5 && gf != null && gf.hasAnimation('sad'))
			{
				gf.playAnim('sad');
				gf.specialAnim = true;
			}
		}
		// playOpponent 时玩家唱的是对手人声轨
		if(playOpponent && opponentVocals.length > 0) opponentVocals.volume = 0;
		else vocals.volume = 0;
	}

	// Kade Complex 准确率模式的 wife3 权重函数（移植自 Etterna）
	// maxms: 偏移毫秒（正值=偏晚）；ts: 歌曲时间缩放（对应 playbackRate）
	inline function wife3Accuracy(maxms:Float, ts:Float):Float
	{
		var max_points:Float = 1.0;
		var miss_weight:Float = -5.5;
		var ridic:Float = 5 * ts;
		var max_boo_weight:Float = 180 * ts;
		var ts_pow:Float = 0.75;
		var zero:Float = 65 * Math.pow(ts, ts_pow);
		var power:Float = 2.5;
		var dev:Float = 22.7 * Math.pow(ts, ts_pow);
		var absMs:Float = Math.abs(maxms);

		if (absMs <= ridic) // 低于该阈值（按判定缩放）记满分
			return max_points;
		else if (absMs <= zero) // ma/pa 区间，指数
			return max_points * erf((zero - absMs) / dev);
		else if (absMs <= max_boo_weight) // cb 区间，线性
			return (absMs - zero) * miss_weight / (max_boo_weight - zero);
		else
			return miss_weight;
	}

	// erf 误差函数（A&S 7.1.26 近似）
	inline function erf(x:Float):Float
	{
		var sign:Int = 1;
		if (x < 0) sign = -1;
		x = Math.abs(x);
		var t:Float = 1.0 / (1.0 + 0.3275911 * x);
		var y:Float = 1.0 - (((((1.061405429 * t + -1.453152027) * t) + 1.421413741) * t + -0.284496736) * t + 0.254829592) * t * Math.exp(-x * x);
		return sign * y;
	}

	function opponentNoteHit(note:Note):Void
	{
		var result:Dynamic = LuaUtils.Function_Continue;
		if (!effectiveDisableNoteLua())
		{
			var preCbName:String = playOpponent ? 'goodNoteHitPre' : 'opponentNoteHitPre';
			result = callOnLuas(preCbName, [luaNoteIndex(note), Math.abs(note.noteData), note.noteType, note.isSustainNote]);
			if(result != LuaUtils.Function_Stop && result != LuaUtils.Function_StopHScript && result != LuaUtils.Function_StopAll) result = callOnHScript(preCbName, [note]);
		}

		if(result == LuaUtils.Function_Stop) return;

		if (songName != 'tutorial')
			camZooming = true;

		// playOpponent 时自动演奏侧是 boyfriend
		var autoChar:Character = cpuSideChar();
		if(note.noteType == 'Hey!' && autoChar.hasAnimation('hey'))
		{
			autoChar.playAnim('hey', true);
			autoChar.specialAnim = true;
			autoChar.heyTimer = 0.6;
		}
		else if(!note.noAnimation)
		{
			var char:Character = autoChar;
			// gf 音符先切到 gf，动画名按其所属角色取数组（LE LTS 双侧：仅 dad 用对手档）
			if(note.gfNote) char = gf;
			var animToPlay:String = singAnimsFor(char)[Std.int(Math.abs(Math.min(singAnimsFor(char).length-1, note.noteData)))] + note.animSuffix;

			if(char != null)
			{
				var canPlay:Bool = true;
				if(note.isSustainNote)
				{
					if(ClientPrefs.data.forceHoldAnimations)
					{
						// funk.in（“长按仅播放一次”）：长条段不重放/不切换角色动画，保持头段姿态
						canPlay = false;
					}
					else
					{
						// 原版 Psych：有 -hold 用 -hold（循环），无则每段重放 sing
						var holdAnim:String = animToPlay + '-hold';
						if(char.animation.exists(holdAnim)) animToPlay = holdAnim;
						if(char.getAnimationName() == holdAnim || char.getAnimationName() == holdAnim + '-loop') canPlay = false;
					}
				}

				if(canPlay)
				{
					// Ghost effect: detect multi-press (multiple notes hit at nearly the same time)
					if(ClientPrefs.data.ghostEffect && !note.isSustainNote && Math.abs(char.lastHitTime - note.strumTime) < 3)
						char.playGhostAnim(note.noteData, animToPlay, true);

					char.playAnim(animToPlay, true);
				}
				char.holdTimer = 0;

				// Update last hit time for multi-press detection
				if(!note.isSustainNote || note.prevNote != null && note.prevNote.isSustainNote)
					char.lastHitTime = note.strumTime;
			}
		}

		if(playOpponent || opponentVocals.length <= 0) vocals.volume = 1;
		strumPlayAnim(!playOpponent, Std.int(Math.abs(note.noteData)), Conductor.stepCrochet * 1.25 / 1000 / playbackRate, note.isSustainNote);
		note.hitByOpponent = true;

		// 对手侧 NoteSplash（兼容 playOpponent：此时对手侧箭头在 playerStrums 上）
		if (ClientPrefs.data.opponentSplashes && ClientPrefs.data.cpuStrums
			&& !note.noteSplashData.disabled && !note.isSustainNote) {
			var strum:StrumNote = opponentSideStrums().members[note.noteData];
			if (strum != null)
				spawnNoteSplash(strum.x, strum.y, note.noteData, note, strum);
		}

		// 对手侧 Hold Cover
		if(note.isSustainNote || note.tail.length > 0) holdCoverHit(note, false);

		stagesFunc(function(stage:BaseStage) {
			if (playOpponent) stage.goodNoteHit(note);
			else stage.opponentNoteHit(note);
		});
		if (!effectiveDisableNoteLua())
		{
			var cbName:String = playOpponent ? 'goodNoteHit' : 'opponentNoteHit';
			var result:Dynamic = callOnLuas(cbName, [luaNoteIndex(note), Math.abs(note.noteData), note.noteType, note.isSustainNote]);
			if(result != LuaUtils.Function_Stop && result != LuaUtils.Function_StopHScript && result != LuaUtils.Function_StopAll) callOnHScript(cbName, [note]);
		}

		if (!note.isSustainNote) invalidateNote(note);
	}

	// 通过打击音对象池播放短音效；未启用池时退回 FlxG.sound.play 原逻辑（保持原行为）
	inline function playShortHitSound(sound:Sound, volume:Float, ?pitch:Float):Void
	{
		if (hitSoundPool != null)
		{
			hitSoundPool.play(sound, volume, pitch);
			return;
		}
		var snd:FlxSound = FlxG.sound.play(sound, volume);
		#if FLX_PITCH
		if (snd != null && pitch != null) snd.pitch = pitch;
		#end
	}

	public function goodNoteHit(note:Note):Void
	{
		if(note.wasGoodHit) return;
		if(cpuControlled && note.ignoreNote) return;

		var isSus:Bool = note.isSustainNote; //GET OUT OF MY HEAD, GET OUT OF MY HEAD, GET OUT OF MY HEAD
		var leData:Int = Math.round(Math.abs(note.noteData));
		var leType:String = note.noteType;

		var result:Dynamic = LuaUtils.Function_Continue;
		if (!effectiveDisableNoteLua())
		{
			var preCbName:String = playOpponent ? 'opponentNoteHitPre' : 'goodNoteHitPre';
			result = callOnLuas(preCbName, [luaNoteIndex(note), leData, leType, isSus]);
			if(result != LuaUtils.Function_Stop && result != LuaUtils.Function_StopHScript && result != LuaUtils.Function_StopAll) result = callOnHScript(preCbName, [note]);
		}

		if(result == LuaUtils.Function_Stop) return;

		note.wasGoodHit = true;

		// Leather modchart 事件：playerOneSing / playerOneSingHeld（对照 LE 原版 PlayState ~2284-2297：
		// 参数 = [noteData, songPosition, arrowType, strumTime]，长条段走 playerOneSingHeld）
		callOnLeatherScripts(note.isSustainNote ? 'playerOneSingHeld' : 'playerOneSing',
			[leData, Conductor.songPosition, leType, note.strumTime]);

		// whenSinging 模式：处理/击中音符后重置该方向冷却（集成 Funkin 防连按）
		if (ClientPrefs.data.ghostTappingMode == 'whenSinging' && note.noteData >= 0 && note.noteData < 4)
			ghostTapTimer[note.noteData] = GHOST_TAP_DELAY_MS;

		if (note.hitsoundVolume > 0 && !note.hitsoundDisabled)
		{
			var useSound:String = note.hitsound;
			if (ClientPrefs.data.hitsound != 'none' && ClientPrefs.data.hitsound != null && ClientPrefs.data.hitsound.length > 0
				&& note.hitsound == 'hitsound')
				useSound = 'hitsounds/' + ClientPrefs.data.hitsound;

			#if FLX_PITCH
			if (ClientPrefs.data.hitsoundPitchOffset)
			{
				// 命中时机偏移（毫秒）：>0 偏早，<0 偏晚；按命中窗口归一化后映射到音高
				var noteDiff:Float = note.strumTime - Conductor.songPosition + (cpuControlled ? 0 : ClientPrefs.data.ratingOffset);
				var norm:Float = Math.max(-1.0, Math.min(1.0, noteDiff / Conductor.safeZoneOffset));
				var pitch:Float = 1.0 + norm * ClientPrefs.data.hitsoundPitchRange;
				playShortHitSound(Paths.sound(useSound), note.hitsoundVolume, pitch);
			}
			else
			#end
				playShortHitSound(Paths.sound(useSound), note.hitsoundVolume);
		}

		if(!note.hitCausesMiss) //Common notes
		{
			if(!note.noAnimation)
			{
				// LE LTS 双侧：受控角色为 dad（playOpponent）时用对手档 sing 动画；gf 音符先切到 gf 再取数组
				var char:Character = playerSideChar();
				var animCheck:String = 'hey';
				if(note.gfNote)
				{
					char = gf;
					animCheck = 'cheer';
				}
				var animToPlay:String = singAnimsFor(char)[Std.int(Math.abs(Math.min(singAnimsFor(char).length-1, note.noteData)))] + note.animSuffix;

				if(char != null)
				{
					var canPlay:Bool = true;
					if(note.isSustainNote)
						{
							if(ClientPrefs.data.forceHoldAnimations)
							{
								// funk.in（“长按仅播放一次”）：长条段不重放/不切换角色动画，保持头段姿态
								canPlay = false;
							}
							else
							{
								// 原版 Psych：有 -hold 用 -hold（循环），无则每段重放 sing
								var holdAnim:String = animToPlay + '-hold';
								if(char.animation.exists(holdAnim)) animToPlay = holdAnim;
								if(char.getAnimationName() == holdAnim || char.getAnimationName() == holdAnim + '-loop') canPlay = false;
							}
						}

				if(canPlay)
				{
					// Ghost effect: detect multi-press (multiple notes hit at nearly the same time)
					if(ClientPrefs.data.ghostEffect && !note.isSustainNote && Math.abs(char.lastHitTime - note.strumTime) < 3)
						char.playGhostAnim(note.noteData, animToPlay, true);

					char.playAnim(animToPlay, true);
				}
				char.holdTimer = 0;

				// Update last hit time for multi-press detection (only for non-sustain notes)
				if(!note.isSustainNote || note.prevNote != null && note.prevNote.isSustainNote)
					char.lastHitTime = note.strumTime;

				if(note.noteType == 'Hey!')
					{
						if(char.hasAnimation(animCheck))
						{
							char.playAnim(animCheck, true);
							char.specialAnim = true;
							char.heyTimer = 0.6;
						}
					}
				}
			}

			if(!cpuControlled)
			{
				var spr = playerSideStrums().members[note.noteData];
				if(spr != null) {
					// 玩家游玩时，重置 botplay 模式标志
					spr.isBotplayMode = false;
					var shouldPlay:Bool = true;
					if(ClientPrefs.data.singleHoldNoteAnimation && note.isSustainNote) {
						shouldPlay = !spr.holdConfirmActive;
					}
					if(shouldPlay) {
						spr.playAnim('confirm', true);
						var isHoldWithSingleAnim:Bool = ClientPrefs.data.singleHoldNoteAnimation && note.isSustainNote;
						if(ClientPrefs.data.autoResetStrumAnim) {
							if(!isHoldWithSingleAnim) {
								spr.resetAnim = Conductor.stepCrochet * 1.25 / 1000 / playbackRate;
								spr.holdConfirmActive = false;
							} else {
								spr.resetAnim = 0;
								spr.holdConfirmActive = true;
							}
						}
						// 即使禁用 autoResetStrumAnim，也要设置 holdConfirmActive 来控制 singleHoldNoteAnimation
						else if(isHoldWithSingleAnim) {
							spr.holdConfirmActive = true;
						}
					}
					
					if(ClientPrefs.data.singleHoldNoteAnimation && note.isSustainNote) {
						spr.lastHoldAnimTime = 0; // 每次处理 hold note 时都重置计时器
					}
					else if (spr.holdConfirmActive) {
						if(ClientPrefs.data.autoResetStrumAnim) {
							spr.holdConfirmActive = false;
							spr.resetAnim = Conductor.stepCrochet * 1.25 / 1000 / playbackRate;
						}
					}
				}
			}
			else strumPlayAnim(playOpponent, Std.int(Math.abs(note.noteData)), Conductor.stepCrochet * 1.25 / 1000 / playbackRate, note.isSustainNote);
			if(playOpponent && opponentVocals.length > 0) opponentVocals.volume = 1;
			else vocals.volume = 1;

			// Hold Cover：长条头/中段/末尾驱动光效
			if(note.isSustainNote || note.tail.length > 0) holdCoverHit(note, true);

			if (!note.isSustainNote)
			{
				combo++;
				if (combo > maxCombo) maxCombo = combo;
				//if(combo > 9999) combo = 9999;
				notesHitArray.unshift(haxe.Timer.stamp() * 1000);
				popUpScore(note);
			}
			// 特性2：长条最后一个尾音命中时，算作一个有效命中判定 —— 加 combo + 显示评级，但不加分
			else if (holdTailJudge && note.parent != null && note.parent.tail.length > 0
				&& note.parent.tail[note.parent.tail.length - 1] == note)
			{
				var tailLeniencyMs:Float = (holdTailLeniency) ? holdTailLeniencyMs : 0;
				combo++;
				if (combo > maxCombo) maxCombo = combo;
				notesHitArray.unshift(haxe.Timer.stamp() * 1000);
				popUpScore(note, false, tailLeniencyMs); // scoreGain=false：只显示评级/计入准度，不加 songScore
			}
			// 长条按住期间每个命中节段：开启长条准确率时计入准确率（分子/分母各 +1）
			else if (note.isSustainNote && ClientPrefs.data.sustainAccuracy && !note.ratingDisabled)
			{
				totalNotesHit += 1;
				totalPlayed++;
				RecalculateRating(false);
			}
			var gainHealth:Bool = true; // prevent health gain, *if* sustains are treated as a singular note
			if (guitarHeroSustains && note.isSustainNote) gainHealth = false;
			if (gainHealth) {
			var healthModel:String = ClientPrefs.getGameplaySetting('healthmodel', 'default');
			// Kade 血量模型：按固定加减血规则结算（sick/good 加血，bad/shit 扣血）
			if (healthModel == 'kade') {
				switch (note.rating) {
					case 'perfect' | 'sick': health += 0.1  * healthGain;
					case 'good':            health += 0.04 * healthGain;
					case 'bad':             health -= 0.06 * healthLoss;
					case 'shit':            health -= 0.2  * healthLoss;
					default:                health += note.hitHealth * healthGain; // 长条/未知评级保持原加血
				}
			}
			// Leather 血量模型：sick/perfect 加血，good/bad 小幅加血；shit 仅在 antiMash 开启时扣血（反连打）
			else if (healthModel == 'leather') {
				switch (note.rating) {
					case 'perfect' | 'sick': health += 0.035 * healthGain;
					case 'good':            health += 0.015 * healthGain;
					case 'bad':             health += 0.005 * healthGain;
					case 'shit':            if (ClientPrefs.getGameplaySetting('antiMash', false)) health -= 0.075 * healthLoss;
					default:                health += note.hitHealth * healthGain; // 长条/未知评级保持原加血
				}
			}
			// Forever 血量模型：任意命中固定加血 0.035，不区分评级；命中后重置连续 miss 惩罚
			else if (healthModel == 'forever') {
				health += 0.035 * healthGain;
				foreverMissPunish = 0.0;
			} else {
				health += note.hitHealth * healthGain;
			}
		}

			// 断连逻辑：命中 bad/shit 评级时，按设置强制中断连击
			if (note.rating == 'bad' && ClientPrefs.data.breakComboOnBad)
				combo = 0;
			else if (note.rating == 'shit' && ClientPrefs.data.breakComboOnShit)
				combo = 0;

			// Kade 计分：命中 Shit 强制断连并计入 Miss 数（相当于 Kade 的 case 'shit' 行为）
			if (ClientPrefs.data.kadeScoring && note.rating == 'shit')
			{
				combo = 0;
				songMisses++;
			}

		}
		else //Notes that count as a miss if you hit them (Hurt notes for example)
		{
			if(!note.noMissAnimation)
			{
				switch(note.noteType)
				{
					case 'Hurt Note':
						var hurtChar:Character = playerSideChar();
						if(hurtChar.hasAnimation('hurt'))
						{
							hurtChar.playAnim('hurt', true);
							hurtChar.specialAnim = true;
						}
				}
			}

			noteMiss(note);
			if(!note.noteSplashData.disabled && !note.isSustainNote && ClientPrefs.data.cpuStrums) spawnNoteSplashOnNote(note);
		}

		stagesFunc(function(stage:BaseStage) {
			if (playOpponent) stage.opponentNoteHit(note);
			else stage.goodNoteHit(note);
		});
		if (!effectiveDisableNoteLua())
		{
			var cbName:String = playOpponent ? 'opponentNoteHit' : 'goodNoteHit';
			var result:Dynamic = callOnLuas(cbName, [luaNoteIndex(note), leData, leType, isSus]);
			if(result != LuaUtils.Function_Stop && result != LuaUtils.Function_StopHScript && result != LuaUtils.Function_StopAll) callOnHScript(cbName, [note]);
		}
		if(!note.isSustainNote) invalidateNote(note);
	}

	public function invalidateNote(note:Note):Void {
		// 幂等防护：已杀(destroy 前 kill 置 exists=false)的音符直接返回，避免同一实例被重复进池/destroy。
		// （从对象池复用的实例 exists 会重新为 true，属正常存活对象，不受此短路影响。）
		if (!note.exists) return;
		// 始终调用 kill() 使 exists=false：帧末批量 compact 依此剔除；legacy 即时移除路径下，
		// 也依靠 exists=false 让主循环末尾不推进索引，避免 splice 左移后跳过下一颗音符。
		note.kill();
		if (ClientPrefs.data.batchCompactNotes)
		{
			// 帧末批量 compact 模式：销毁不 splice，仅标记 dead，在 update 末尾一次收缩三个数组。
			// 把原先每颗销毁就 3 次 O(n) indexOf+splice（乐/MS/holdNotes 各一次）降为一帧一次的单遍紧凑。
		}
		else
		{
			// legacy/兼容模式：维持原“销毁即 splice”行为，notes.length 对脚本实时生效。
			notes.remove(note, true);
			// 同时也从 normalNotes 和 holdNotes 中移除
			normalNotes.remove(note, true);
			holdNotes.remove(note, true);
		}
		// 解除 spawnedNotes 强引用（与 OOM FIX 逻辑一致）：正常路径此前未置空，整曲跑完会持有
		// 全部已 destroy 的 Note 对象（FlxPoint 等残骸），高密度谱下即数十~上百 MB 泄漏。
		// 读取侧（生成循环）已做 null + animation 双重校验，置空安全。
		if (note.preloadIndex >= 0 && note.preloadIndex < spawnedNotes.length)
			spawnedNotes[note.preloadIndex] = null;

		// 对象池回收：仅在 notePooling 开启、noteOptimization 开启、且为普通音符时复用实例。
		// （sustain 不入池：构造时会改前驱 scale.y，见 spawnNote 注释；notePooling 默认关闭，确保安全。）
		if (ClientPrefs.data.noteOptimization && ClientPrefs.data.notePooling && !note.isSustainNote)
		{
			var key:String = note.noteData + ':false';
			var bucket:Array<Note> = notePool.get(key);
			if (bucket == null) { bucket = []; notePool.set(key, bucket); }
			// 防止同一实例被重复还池（理论上不会发生）
			if (bucket.indexOf(note) == -1) bucket.push(note);
		}
		else
		{
			note.destroy();
		}
	}

	// 单遍就地紧凑：保留 null 之外的存活(!exists=false)成员到数组前段，一次收缩完成。
	// 就地写入、无新数组分配，也顺带填掉数组里的 null 空洞（如 OOM/过期即时结算路径留下的槽位）。
	function compactNoteArray(arr:Array<Note>):Void {
		var w:Int = 0;
		for (r in 0...arr.length) {
			var m:Note = arr[r];
			if (m != null && m.exists) { arr[w] = m; w++; }
		}
		if (w < arr.length) arr.splice(w, arr.length - w);
	}

	/**
	 * 音符工厂：统一替代 `new Note(...)`，支持对象池复用。
	 * - notePooling 开启（且 noteOptimization 开启）时：优先从 notePool 取同桶（noteData）普通音符
	 *   实例并 prepareForReuse，否则 new 一个（首次构建 frames/animation，落入池中后续复用）。
	 * - notePooling 关闭（默认）：始终 new，保持原始语义。此时 onSpawnNote 等脚本回调拿到的每个
	 *   Note 都是独立 new 的新对象，生命周期与脚本预期一致（不会读到被复用的脏对象）。
	 * ⚠ 注意：池化仅在玩家显式开启 notePooling 时生效，因为引擎无法自动判断脚本是否依赖音符对象的
	 *   持久引用（effectiveDisableNoteLua 语义为“是否禁用脚本”，与“是否激活”相反，不能作为退化依据）。
	 */
	public function spawnNote(strumTime:Float, noteData:Int, prevNote:Note, isSustain:Bool, ?inEditor:Bool = false):Note {
		// 仅池化普通音符：sustain 音符构造时会修改前驱普通音符的 scale.y（累积拉伸），
		// 池化复用会导致 scale.y 错乱，且 sustain 在高密度纯箭头谱中占比极小，收益不抵风险。
		if (ClientPrefs.data.noteOptimization && ClientPrefs.data.notePooling && !isSustain)
		{
			var key:String = noteData + ':false';
			var bucket:Array<Note> = notePool.get(key);
			if (bucket != null && bucket.length > 0)
			{
				var note:Note = bucket.pop();
				note.inEditor = inEditor;
				note.prepareForReuse(strumTime, noteData, prevNote, false);
				return note;
			}
		}
		return new Note(strumTime, noteData, prevNote, isSustain, inEditor);
	}

	// 过期即时结算的“判为 sick”版本：把已越过 noteKillOffset 的音符按最高评级 sick 结算，而非判 miss。
	// 即使 rmPerfect（禁用 perfect）开启也始终强制为 sick——因为 sick 在 ratingsData 中一定存在，而 perfect 不一定。
	// 这样在性能兜底时不会误扣血 / 断连击 / 掉准度。
	// 为不抵消本功能的性能收益，这里只做轻量计分（连击 / 分数 / 血量 / 准度计数），
	// 不生成任何视觉对象（评级贴图、连击数、角色动画、splash 等），也不写入回放（避免污染输入序列）。
	public function instantResolveAsSick(note:Note):Void
	{
		if (note.wasGoodHit || note.ignoreNote) return;
		note.wasGoodHit = true;

		// 找到 sick 评级（无论 rmPerfect 是否禁用 perfect，都强制取 sick）
		var sickRating:Rating = null;
		for (r in ratingsData) if (r.name == 'sick') { sickRating = r; break; }
		if (sickRating == null) sickRating = ratingsData[0];

		if (!note.isSustainNote)
		{
			combo++;
			if (combo > maxCombo) maxCombo = combo;
			notesHitArray.unshift(haxe.Timer.stamp() * 1000);
		}
		// 特性2：长条尾音命中同样计入一次有效命中（连击 + 准度），但不加分
		else if (holdTailJudge && note.parent != null && note.parent.tail.length > 0
			&& note.parent.tail[note.parent.tail.length - 1] == note)
		{
			combo++;
			if (combo > maxCombo) maxCombo = combo;
			notesHitArray.unshift(haxe.Timer.stamp() * 1000);
		}

		var gainHealth:Bool = true;
		if (guitarHeroSustains && note.isSustainNote) gainHealth = false;
		if (gainHealth) health += note.hitHealth * healthGain;

		// 复用 popUpScore 的计分核心（sick 评级），但不生成任何视觉对象、不写回放
		totalNotesHit += sickRating.ratingMod;
		note.ratingMod = sickRating.ratingMod;
		sickRating.hits++;
		note.rating = sickRating.name;
		songScore += sickRating.score;
		songHits++;
		totalPlayed++;
		RecalculateRating(false);
	}

	public function spawnNoteSplashOnNote(note:Note) {
		if(note != null) {
			var strum:StrumNote = playerSideStrums().members[note.noteData];
			if(strum != null)
				spawnNoteSplash(strum.x, strum.y, note.noteData, note, strum);
		}
	}

	public function spawnNoteSplash(x:Float = 0, y:Float = 0, ?data:Int = 0, ?note:Note, ?strum:StrumNote) {
		// 飞溅数量限制检查
		if (ClientPrefs.data.splashLimitEnabled) {
			var aliveCount:Int = 0;
			for (splash in grpNoteSplashes)
				if (splash.alive) aliveCount++;

			if (aliveCount >= ClientPrefs.data.splashLimit) {
				// 超限处理模式：仅当达到上限时才走这里
				if (ClientPrefs.data.splashLimitMode == 'replace') {
					// 'replace' 模式：销毁最早生成的那个存活飞溅，随后照常生成新飞溅
					for (splash in grpNoteSplashes)
						if (splash.alive) { splash.kill(); break; }
				} else {
					// 'skip' 模式（现状）：达到上限则忽略本次飞溅
					return;
				}
			}
		}

		var splash:NoteSplash = grpNoteSplashes.recycle(NoteSplash);
		splash.babyArrow = strum;
		splash.spawnSplashNote(x, y, data, note);
		grpNoteSplashes.add(splash);
	}

	override function destroy() {
		if (keyViewer != null)
		{
			keyViewer.destroy();
			keyViewer = null;
		}
		// 清理评分贴图缓存引用（FlxGraphic 本身由 Paths.currentTrackedAssets 统一管理，这里只释放本实例的引用）
		_ratingGfxCache = null;
		_exRatingGfxCache = null;
		_numGfxCache = null;
		_comboGfx = null;

		if (psychlua.CustomSubstate.instance != null)
		{
			closeSubState();
			resetSubState();
		}

		#if LUA_ALLOWED
		for (lua in luaArray)
		{
			lua.call('onDestroy', []);
			lua.stop();
		}
		luaArray = null;
		FunkinLua.customFunctions.clear();
		#end

		#if HSCRIPT_ALLOWED
		for (script in hscriptArray)
			if(script != null)
			{
				if(script.exists('onDestroy')) script.call('onDestroy');
				script.destroy();
			}

		hscriptArray = null;
		#end
		stagesFunc(function(stage:BaseStage) stage.destroy());

		#if VIDEOS_ALLOWED
		if(videoCutscene != null)
		{
			videoCutscene.destroy();
			videoCutscene = null;
		}
		#end

		FlxG.stage.removeEventListener(KeyboardEvent.KEY_DOWN, onKeyPress);
		FlxG.stage.removeEventListener(KeyboardEvent.KEY_UP, onKeyRelease);

		FlxG.camera.filters = [];

		#if FLX_PITCH FlxG.sound.music.pitch = 1; #end
		FlxG.animationTimeScale = 1;

		// 清理旧版 PE 兼容字段中的 tween/timer 对象，防止 FlxTimer.globalManager 持有已销毁 state
		for (tween in modchartTweens) { if (tween != null) tween.destroy(); }
		modchartTweens = null;
		for (timer in modchartTimers) { if (timer != null) timer.destroy(); }
		modchartTimers = null;
		modchartSprites = null;
		modchartTexts = null;
		modchartSounds = null;

		Note.globalRgbShaders = [];
		backend.NoteTypesConfig.clearNoteTypesData();

		NoteSplash.configs.clear();
		instance = null;
		shutdownThread = true;
		FlxG.signals.preUpdate.remove(checkForResync);
		
		// 恢复原始判定设置
		if (originalJudgmentSettings != null) {
			if (Reflect.hasField(originalJudgmentSettings, 'rmPerfect')) ClientPrefs.data.rmPerfect = originalJudgmentSettings.rmPerfect;
			if (Reflect.hasField(originalJudgmentSettings, 'perfectWindow')) ClientPrefs.data.perfectWindow = originalJudgmentSettings.perfectWindow;
			if (Reflect.hasField(originalJudgmentSettings, 'sickWindow')) ClientPrefs.data.sickWindow = originalJudgmentSettings.sickWindow;
			if (Reflect.hasField(originalJudgmentSettings, 'goodWindow')) ClientPrefs.data.goodWindow = originalJudgmentSettings.goodWindow;
			if (Reflect.hasField(originalJudgmentSettings, 'badWindow')) ClientPrefs.data.badWindow = originalJudgmentSettings.badWindow;
			if (Reflect.hasField(originalJudgmentSettings, 'safeFrames')) ClientPrefs.data.safeFrames = originalJudgmentSettings.safeFrames;
			if (Reflect.hasField(originalJudgmentSettings, 'ratingOffset')) ClientPrefs.data.ratingOffset = originalJudgmentSettings.ratingOffset;
			if (Reflect.hasField(originalJudgmentSettings, 'hitsoundVolume')) ClientPrefs.data.hitsoundVolume = originalJudgmentSettings.hitsoundVolume;
			if (Reflect.hasField(originalJudgmentSettings, 'noteOffset')) ClientPrefs.data.noteOffset = originalJudgmentSettings.noteOffset;
			
			// 重新初始化 ratingsData 以确保与恢复后的 rmPerfect 设置一致
			ratingsData = Rating.loadDefault();
			
			// 更新 ratingsData 中的 hitWindow（虽然实例即将销毁，但为了完整性）
			for (rating in ratingsData) {
				var windowField:String = rating.name + 'Window';
				if (Reflect.hasField(originalJudgmentSettings, windowField)) {
					rating.hitWindow = Reflect.field(originalJudgmentSettings, windowField);
				}
			}
		}
		
		// 恢复原始游戏设置
		if (originalGameplaySettings != null) {
			if (Reflect.hasField(originalGameplaySettings, 'downScroll')) ClientPrefs.data.downScroll = originalGameplaySettings.downScroll;
			if (Reflect.hasField(originalGameplaySettings, 'middleScroll')) ClientPrefs.data.middleScroll = originalGameplaySettings.middleScroll;
			if (Reflect.hasField(originalGameplaySettings, 'opponentStrums')) ClientPrefs.data.opponentStrums = originalGameplaySettings.opponentStrums;
			if (Reflect.hasField(originalGameplaySettings, 'ghostTappingMode'))
			{
				var m:String = originalGameplaySettings.ghostTappingMode;
				if (m == 'psych') m = 'always';
				else if (m == 'vslice' || m == 'cooldown') m = 'whenSinging';
				else if (m == 'disabled') m = 'off';
				ClientPrefs.data.ghostTappingMode = m;
			}
			else if (Reflect.hasField(originalGameplaySettings, 'ghostTapping')) // 旧 Bool 存档兼容
				ClientPrefs.data.ghostTappingMode = (originalGameplaySettings.ghostTapping == true) ? 'always' : 'off';
			if (Reflect.hasField(originalGameplaySettings, 'noReset')) ClientPrefs.data.noReset = originalGameplaySettings.noReset;
			if (Reflect.hasField(originalGameplaySettings, 'guitarHeroSustains')) ClientPrefs.data.guitarHeroSustains = originalGameplaySettings.guitarHeroSustains;
			if (Reflect.hasField(originalGameplaySettings, 'sustainTailFix')) ClientPrefs.data.sustainTailFix = originalGameplaySettings.sustainTailFix;
			if (Reflect.hasField(originalGameplaySettings, 'holdReleaseInstantMiss')) ClientPrefs.data.holdReleaseInstantMiss = originalGameplaySettings.holdReleaseInstantMiss;
			if (Reflect.hasField(originalGameplaySettings, 'holdTailJudge')) ClientPrefs.data.holdTailJudge = originalGameplaySettings.holdTailJudge;
			if (Reflect.hasField(originalGameplaySettings, 'holdScoreBonus')) ClientPrefs.data.holdScoreBonus = originalGameplaySettings.holdScoreBonus;
			if (Reflect.hasField(originalGameplaySettings, 'holdTailLeniency')) ClientPrefs.data.holdTailLeniency = originalGameplaySettings.holdTailLeniency;
			if (Reflect.hasField(originalGameplaySettings, 'holdTailLeniencyMs')) ClientPrefs.data.holdTailLeniencyMs = originalGameplaySettings.holdTailLeniencyMs;
			if (Reflect.hasField(originalGameplaySettings, 'popUpRating')) ClientPrefs.data.popUpRating = originalGameplaySettings.popUpRating;
		}
		
		// 重置回放设置静态变量。
		// 若是"重玩"（队列新 PlayState 继续回放），则保留静态回放数据供下次消费；
		// 否则为真正退出 PlayState，销毁回放数据避免污染后续流程。
		if (retainReplayOnRestart)
		{
			retainReplayOnRestart = false; // 保留 pendingReplayData/shouldStartReplay 等，供新 PlayState 消费
		}
		else
		{
			shouldStartReplay = false;
			pendingReplayData = null;
			replayJudgmentSettings = null;
			replayGameplaySettings = null;
		}

		// 退出PlayState时还原为原来的缩放模式（destroy在下一状态create之前执行，确保后续界面恢复原始分辨率）
		if (_psAdaptiveActive)
		{
			FlxG.scaleMode = _psAdaptiveScaleMode;
			FlxG.resizeGame(FlxG.stage.stageWidth, FlxG.stage.stageHeight);
			_psAdaptiveActive = false;
			_psAdaptiveScaleMode = null;
		}

		// 释放打击音对象池（stop + destroy 并从 FlxG.sound.list 移除）
		if (hitSoundPool != null)
		{
			hitSoundPool.destroy();
			hitSoundPool = null;
		}
		
		super.destroy();
	}

	var lastStepHit:Int = -1;
	override function stepHit()
	{
		if (ClientPrefs.data.timebarStyle == 'Leather')
		{
			var section = SONG.notes[curSection];
			if (section != null)
			{
				if (section.mustHitSection)
				{
					timeBarRightColorTarget = FlxColor.fromRGB(boyfriend.healthColorArray[0], boyfriend.healthColorArray[1], boyfriend.healthColorArray[2]);
				}
				else
				{
					timeBarRightColorTarget = FlxColor.fromRGB(dad.healthColorArray[0], dad.healthColorArray[1], dad.healthColorArray[2]);
				}
			}
		}

		if ((ClientPrefs.data.timebarStyle == 'Psych' || ClientPrefs.data.timebarStyle == 'Leather (Legacy)') && ClientPrefs.data.timeBarGradient && timeBar != null && dad != null && boyfriend != null) {
			var dadColor:FlxColor = FlxColor.fromRGB(dad.healthColorArray[0], dad.healthColorArray[1], dad.healthColorArray[2]);
			var bfColor:FlxColor = FlxColor.fromRGB(boyfriend.healthColorArray[0], boyfriend.healthColorArray[1], boyfriend.healthColorArray[2]);
			timeBar.useGradient = true;
			timeBar.setGradientColors(dadColor, bfColor);
		}

		super.stepHit();

		if(curStep == lastStepHit) {
			return;
		}

		lastStepHit = curStep;
		setOnScripts('curStep', curStep);
		callOnScripts('onStepHit');
	}

	var lastBeatHit:Int = -1;

	override function beatHit()
	{
		if(lastBeatHit >= curBeat) {
			//trace('BEAT HIT: ' + curBeat + ', LAST HIT: ' + lastBeatHit);
			return;
		}

		if (generatedMusic)
		{
			// 优化模式下音符以 push 追加，天然按生成时间（≈Y 序）排列，无需每拍重排。
			if (!ClientPrefs.data.noteOptimization)
				notes.sort(FlxSort.byY, ClientPrefs.data.downScroll ? FlxSort.ASCENDING : FlxSort.DESCENDING);
		}

		if (iconBopEnabled)
		{
			if (ClientPrefs.data.iconbopstyle != "NONE")
			{
				switch (ClientPrefs.data.iconbopstyle)
				{
					case "Kade":
						iconP1.scale.set(1.4, 1.4);
						iconP2.scale.set(1.4, 1.4);

					case "Leather":
						// Leather 风格使用 add 方法，与原版一致
						iconP1.scale.add(0.2 * iconP1.startSize, 0.2 * iconP1.startSize);
						iconP2.scale.add(0.2 * iconP2.startSize, 0.2 * iconP2.startSize);

            	case "VSlice(New)":
						// funkin 复刻：整体放大到 1.2，linear 匀速缩回
						vsliceBopTweenP1 = iconBopFunkin(iconP1, vsliceBopTweenP1);
						vsliceBopTweenP2 = iconBopFunkin(iconP2, vsliceBopTweenP2);

            	case "Codename" | "NovaFlare" | "Kathy":
							iconP1.scale.set(1.3, 1.3);
							iconP2.scale.set(1.3, 1.3);

						case "VSlice(Old)":
							// 原版 Funkin 0.2.7.1 复刻：beat 时宽度+30px，高度自动等比缩放
							iconP1.setGraphicSize(Std.int(iconP1.width + 30));
							iconP2.setGraphicSize(Std.int(iconP2.width + 30));

					case "Vanilla":
							iconP1.scale.set(1.1, 1.1);
							iconP2.scale.set(1.1, 1.1);

						case "Forever":
							// Forever Engine 复刻：beat 时图标放大到 1.15x，指数衰减缩回
							iconP1.scale.set(1.15, 1.15);
							iconP2.scale.set(1.15, 1.15);

						case "Psych (Legacy)":
						// PsychEngine 0.4.2 忠实复刻：beat 时把图标整体放大 30px（仅给宽，高度按原比例自动缩放）
						iconP1.setGraphicSize(Std.int(iconP1.width + 30));
						iconP2.setGraphicSize(Std.int(iconP2.width + 30));

                case "Dave":
                    // 原版 Dave Engine 复刻：每拍在现有尺寸上相乘累积压扁/拉长
                    // （宽度 +50·(funny+0.1)，高度 -25·funny），随血量方向互补，回缩在 updateIconsScale 按帧进行
                    var daveFunny:Float = FlxMath.bound(healthBar.percent / 50, 0.1, 1.9);
                    if (playOpponent)
                    {
                        iconP2.setGraphicSize(Std.int(iconP2.width + (50 * (daveFunny + 0.1))), Std.int(iconP2.height - (25 * daveFunny)));
                        iconP1.setGraphicSize(Std.int(iconP1.width + (50 * ((2 - daveFunny) + 0.1))), Std.int(iconP1.height - (25 * ((2 - daveFunny) + 0.1))));
                    }
                    else
                    {
                        iconP1.setGraphicSize(Std.int(iconP1.width + (50 * (daveFunny + 0.1))), Std.int(iconP1.height - (25 * daveFunny)));
                        iconP2.setGraphicSize(Std.int(iconP2.width + (50 * ((2 - daveFunny) + 0.1))), Std.int(iconP2.height - (25 * ((2 - daveFunny) + 0.1))));
                    }
                case "Squash":
                    // 压扁风格：beat 上双方 icon 被压扁，随血量/输赢状态表现不同，恢复在 updateIconsScale 中处理
                    var pct:Float = healthBar.percent;
                    var playerWin:Bool = (ClientPrefs.data.threeIcons && pct > 80);
                    var playerLose:Bool = (pct < 20);
                    var playerIcon:HealthIcon = playOpponent ? iconP2 : iconP1;
                    var oppIcon:HealthIcon = playOpponent ? iconP1 : iconP2;
                    if (playerWin)
                    {
                        playerIcon.scale.set(0.85, 1.25); // 领先方被拉长（高瘦）
                        oppIcon.scale.set(1.25, 0.8);   // 落后方被压扁（矮胖）
                    }
                    else if (playerLose)
                    {
                        playerIcon.scale.set(1.25, 0.8);
                        oppIcon.scale.set(0.85, 1.25);
                    }
                    else
                    {
                        var off:Float = (pct - 50) / 50; // -1 ~ 1
                        playerIcon.scale.set(1.15 + 0.1 * off, 0.85 - 0.1 * off);
                        oppIcon.scale.set(1.15 - 0.1 * off, 0.85 + 0.1 * off);
                    }
                    iconSizeResetTime = ICON_SQUASH_TIME;
                default:
						iconP1.scale.set(1.2, 1.2);
						iconP2.scale.set(1.2, 1.2);
				}
			}
			dancingLeft = !dancingLeft;

			if (ClientPrefs.data.iconbopstyle == "OS")
			{
				if (dancingLeft)
				{
					iconP1.angle = 8;
					iconP2.angle = 8; // maybe i should do it with tweens, but i'm lazy // i'll make it in -1.0.0, i promise //这是OS引擎的作者写的，然而OS已经停更了（悲）
				}
				else
				{
					iconP1.angle = -8;
					iconP2.angle = -8;
				}
			}
			else if (ClientPrefs.data.iconbopstyle == "SB")
			{
				if (dancingLeft)
				{
					iconP1.angle = -15;
					iconP2.angle = 15;
				}
				else
				{
					iconP1.angle = 15;
					iconP2.angle = -15;
				}
			}
			else if (ClientPrefs.data.iconbopstyle == "Kathy")
			{
				var healthPercent:Float = healthBar.percent;
				if (healthPercent < 20)
				{
					if (curBeat % 2 == 0)
					{
						iconP2.angle += icondancingLeft ? -17 : 17;
						icondancingLeft = !icondancingLeft;
					}
				}
				else if (healthPercent > 80)
				{
					if (curBeat % 2 == 0)
					{
						iconP1.angle += icondancingLeft ? -17 : 17;
						icondancingLeft = !icondancingLeft;
					}
				}
			}
		}

		iconP1.updateHitbox();
		iconP2.updateHitbox();

		characterBopper(curBeat);

		super.beatHit();
		lastBeatHit = curBeat;

		setOnScripts('curBeat', curBeat);
		callOnScripts('onBeatHit');
	}

	public function iconBopNow():Void
	{
		if (ClientPrefs.data.iconbopstyle != "NONE")
    	{
        	switch(ClientPrefs.data.iconbopstyle) {
            	case "Kade":
                	iconP1.scale.set(1.4, 1.4);
                	iconP2.scale.set(1.4, 1.4);

				case "Leather":
					// Leather 风格使用 add 方法，与原版一致
					iconP1.scale.add(0.2 * iconP1.startSize, 0.2 * iconP1.startSize);
					iconP2.scale.add(0.2 * iconP2.startSize, 0.2 * iconP2.startSize);

            	case "VSlice(New)" | "Codename" | "NovaFlare" | "Kathy":
	                	iconP1.scale.set(1.3, 1.3);
	                	iconP2.scale.set(1.3, 1.3);

					case "VSlice(Old)":
						iconP1.setGraphicSize(Std.int(iconP1.width + 30));
						iconP2.setGraphicSize(Std.int(iconP2.width + 30));
                
            	case "Vanilla":
	                	iconP1.scale.set(1.1, 1.1);
	                	iconP2.scale.set(1.1, 1.1);

	            	case "Forever":
	                	iconP1.scale.set(1.15, 1.15);
	                	iconP2.scale.set(1.15, 1.15);
	                
	            	case "Dave":
                    // 原版 Dave Engine 复刻：每拍在现有尺寸上相乘累积压扁/拉长，回缩在 updateIconsScale 按帧进行
                    var daveFunny:Float = FlxMath.bound(healthBar.percent / 50, 0.1, 1.9);
                    if (playOpponent)
                    {
                        iconP2.setGraphicSize(Std.int(iconP2.width + (50 * (daveFunny + 0.1))), Std.int(iconP2.height - (25 * daveFunny)));
                        iconP1.setGraphicSize(Std.int(iconP1.width + (50 * ((2 - daveFunny) + 0.1))), Std.int(iconP1.height - (25 * ((2 - daveFunny) + 0.1))));
                    }
                    else
                    {
                        iconP1.setGraphicSize(Std.int(iconP1.width + (50 * (daveFunny + 0.1))), Std.int(iconP1.height - (25 * daveFunny)));
                        iconP2.setGraphicSize(Std.int(iconP2.width + (50 * ((2 - daveFunny) + 0.1))), Std.int(iconP2.height - (25 * ((2 - daveFunny) + 0.1))));
                    }
            	case "Squash":
                    var pct:Float = healthBar.percent;
                    var playerWin:Bool = (ClientPrefs.data.threeIcons && pct > 80);
                    var playerLose:Bool = (pct < 20);
                    var playerIcon:HealthIcon = playOpponent ? iconP2 : iconP1;
                    var oppIcon:HealthIcon = playOpponent ? iconP1 : iconP2;
                    if (playerWin)
                    {
                        playerIcon.scale.set(0.85, 1.25);
                        oppIcon.scale.set(1.25, 0.8);
                    }
                    else if (playerLose)
                    {
                        playerIcon.scale.set(1.25, 0.8);
                        oppIcon.scale.set(0.85, 1.25);
                    }
                    else
                    {
                        var off:Float = (pct - 50) / 50;
                        playerIcon.scale.set(1.15 + 0.1 * off, 0.85 - 0.1 * off);
                        oppIcon.scale.set(1.15 - 0.1 * off, 0.85 + 0.1 * off);
                    }
                    iconSizeResetTime = ICON_SQUASH_TIME;
            	default:
                	iconP1.scale.set(1.2, 1.2);
                	iconP2.scale.set(1.2, 1.2);
        	}
    	}
    	dancingLeft = !dancingLeft;

    	if (ClientPrefs.data.iconbopstyle == "OS") {
    		if (dancingLeft){
    			iconP1.angle = 8; iconP2.angle = 8;
    		} else { 
    			iconP1.angle = -8; iconP2.angle = -8;
    		}
    	} 	
    	else if (ClientPrefs.data.iconbopstyle == "SB") {
    		if (dancingLeft){
    			iconP1.angle = -15; iconP2.angle = 15;
    		} else { 
    			iconP1.angle = 15; iconP2.angle = -15;
    		}
    	}
    	else if (ClientPrefs.data.iconbopstyle == "Kathy")
    	{
    		var healthPercent:Float = healthBar.percent;
    		if (healthPercent < 20)
    		{
    			iconP2.angle += icondancingLeft ? -17 : 17;
    			icondancingLeft = !icondancingLeft;
    		}
    		else if (healthPercent > 80)
    		{
    			iconP1.angle += icondancingLeft ? -17 : 17;
    			icondancingLeft = !icondancingLeft;
    		}
    	}
    	iconP1.updateHitbox();
    	iconP2.updateHitbox();
	}

	public function characterBopper(beat:Int):Void
	{
		if (gf != null && beat % Math.round(gfSpeed * gf.danceEveryNumBeats) == 0 && !gf.getAnimationName().startsWith('sing') && !gf.stunned)
			gf.dance();
		if (boyfriend != null && beat % boyfriend.danceEveryNumBeats == 0 && !boyfriend.getAnimationName().startsWith('sing') && !boyfriend.stunned)
			boyfriend.dance();
		if (dad != null && beat % dad.danceEveryNumBeats == 0 && !dad.getAnimationName().startsWith('sing') && !dad.stunned)
			dad.dance();
	}

	public function playerDance():Void
	{
		var char:Character = playerSideChar();
		if(char == null) return;
		var anim:String = char.getAnimationName();
		if(char.holdTimer > Conductor.stepCrochet * (0.0011 #if FLX_PITCH / FlxG.sound.music.pitch #end) * char.singDuration && anim.startsWith('sing') && !anim.endsWith('miss'))
			char.dance();
	}

	override function sectionHit()
{
    if (SONG.notes[curSection] != null)
    {
        if (generatedMusic && !endingSong && !isCameraOnForcedPos)
            moveCameraSection();

        if (camZooming /*&& FlxG.camera.zoom < 1.35 */&& ClientPrefs.data.camZooms)
        {
            FlxG.camera.zoom += 0.015 * camZoomingMult;
            camHUD.zoom += 0.03 * camZoomingMult;
        }

        if (ClientPrefs.data.iconbopstyle == "Kathy" && iconBopEnabled)
			{
				var healthPercent:Float = healthBar.percent;
				if (healthPercent < 20)
				{
					iconP1.angle += 30;
				}
				else if (healthPercent > 80)
				{
					iconP2.angle -= 30;
				}
				else
				{
					iconP1.angle -= 25;
					iconP2.angle += 25;
				}
			}

        if (SONG.notes[curSection].changeBPM)
        {
            // 线性 BPM 过渡：用当前实时瞬时 BPM，而不是把全局 BPM 硬设为目标值。
            // 否则在 ramp 段（尤其是单曲内多个连续 ramp 段）进入瞬间会突跳到 endTime，
            // 破坏与 update() 中实时插值的平滑一致性（仅当帧/脚本 curBpm 会跳变）。
            Conductor.bpm = Conductor.getBPMFromSeconds(Conductor.songPosition).bpm;
            setOnScripts('curBpm', Conductor.bpm);
            setOnScripts('crochet', Conductor.crochet);
            setOnScripts('stepCrochet', Conductor.stepCrochet);
        }

        setOnScripts('mustHitSection', SONG.notes[curSection].mustHitSection);
        setOnScripts('altAnim', SONG.notes[curSection].altAnim);
        setOnScripts('gfSection', SONG.notes[curSection].gfSection);
    }
    super.sectionHit();

    setOnScripts('curSection', curSection);
    callOnScripts('onSectionHit');
}

	#if LUA_ALLOWED
	public function startLuasNamed(luaFile:String)
	{
		#if MODS_ALLOWED
		var luaToLoad:String = Paths.modFolders(luaFile);
		if(!FileSystem.exists(luaToLoad))
			luaToLoad = Paths.getSharedPath(luaFile);

		if(FileSystem.exists(luaToLoad))
		#elseif sys
		var luaToLoad:String = Paths.getSharedPath(luaFile);
		if(OpenFlAssets.exists(luaToLoad))
		#end
		{
			for (script in luaArray)
				if(script.scriptName == luaToLoad) return false;

			new FunkinLua(luaToLoad);
			return true;
		}
		return false;
	}
	#end

	#if HSCRIPT_ALLOWED
	public function startHScriptsNamed(scriptFile:String)
	{
		#if MODS_ALLOWED
		var scriptToLoad:String = Paths.modFolders(scriptFile);
		if(!FileSystem.exists(scriptToLoad))
			scriptToLoad = Paths.getSharedPath(scriptFile);
		#else
		var scriptToLoad:String = Paths.getSharedPath(scriptFile);
		#end

		if(FileSystem.exists(scriptToLoad))
		{
			if (Iris.instances.exists(scriptToLoad)) return false;

			initHScript(scriptToLoad);
			return true;
		}
		return false;
	}

	public function initHScript(file:String)
	{
		var newScript:HScript = null;
		try
		{
			newScript = new HScript(null, file);
			if (newScript.exists('onCreate')) newScript.call('onCreate');
			trace('initialized hscript interp successfully: $file');
			hscriptArray.push(newScript);
		}
		catch(e:IrisError)
		{
			var pos:HScriptInfos = cast {fileName: file, showLine: false};
			Iris.error(Printer.errorToString(e, false), pos);
			var newScript:HScript = cast (Iris.instances.get(file), HScript);
			if(newScript != null)
				newScript.destroy();
		}
	}
	#end

	public function callOnScripts(funcToCall:String, args:Array<Dynamic> = null, ignoreStops = false, exclusions:Array<String> = null, excludeValues:Array<Dynamic> = null):Dynamic {
		var returnVal:Dynamic = LuaUtils.Function_Continue;
		if(args == null) args = [];
		if(exclusions == null) exclusions = [];
		if(excludeValues == null) excludeValues = [LuaUtils.Function_Continue];

		var result:Dynamic = callOnLuas(funcToCall, args, ignoreStops, exclusions, excludeValues);
		if(result == null || excludeValues.contains(result)) result = callOnHScript(funcToCall, args, ignoreStops, exclusions, excludeValues);

		// Leather Engine 脚本事件广播（对照 LE 原版 PlayState.instance.scripts 的事件分发）
		// LE 脚本独立于 Psych 脚本：只接收事件，不参与返回值链
		#if LUA_ALLOWED
		if (leatherLuaArray != null)
		{
			for (script in leatherLuaArray)
			{
				if (script == null || script.closed) continue;
				try {
					if (script.exists(funcToCall)) script.call(funcToCall, args);
				} catch(e:Dynamic) {}
			}
		}
		#end

		return result;
	}

	/**
	 * Leather 专属事件广播：只把事件分发给 leatherLuaArray（LE 事件名，如 update/playerOneSing/playerOneMiss/popUpScore）。
	 * 与 callOnScripts 里的 Psych 事件名广播互补——LE modchart 脚本定义的是 LE 事件名，
	 * 由 Psych 事件点（goodNoteHit/noteMiss/popUpScore/update）显式桥接过来。
	 */
	public function callOnLeatherScripts(funcToCall:String, args:Array<Dynamic> = null):Void
	{
		#if LUA_ALLOWED
		if(args == null) args = [];
		if (leatherLuaArray != null)
		{
			for (script in leatherLuaArray)
			{
				if (script == null || script.closed) continue;
				try {
					if (script.exists(funcToCall)) script.call(funcToCall, args);
				} catch(e:Dynamic) {
					trace('[LE event] $funcToCall threw: ' + Std.string(e));
				}
			}
		}
		#end
	}

	public function callOnLuas(funcToCall:String, args:Array<Dynamic> = null, ignoreStops = false, exclusions:Array<String> = null, excludeValues:Array<Dynamic> = null):Dynamic {
		var returnVal:Dynamic = LuaUtils.Function_Continue;
		#if LUA_ALLOWED
		if(args == null) args = [];
		if(exclusions == null) exclusions = [];
		if(excludeValues == null) excludeValues = [LuaUtils.Function_Continue];

		var arr:Array<FunkinLua> = [];
		for (script in luaArray)
		{
			if(script.closed)
			{
				arr.push(script);
				continue;
			}

			if(exclusions.contains(script.scriptName))
				continue;

			// 性能优化：广播前先查探测缓存，未实现该事件的脚本直接跳过
			// （ FunkinLua.call 内部也会短路，这里是双保险，避免进 try 块）
			if(!script.probeFunc(funcToCall))
				continue;

			var myValue:Dynamic = script.call(funcToCall, args);
			if((myValue == LuaUtils.Function_StopLua || myValue == LuaUtils.Function_StopAll) && !excludeValues.contains(myValue) && !ignoreStops)
			{
				returnVal = myValue;
				break;
			}

			if(myValue != null && !excludeValues.contains(myValue))
				returnVal = myValue;

			if(script.closed) arr.push(script);
		}

		if(arr.length > 0)
			for (script in arr)
				luaArray.remove(script);
		#end
		return returnVal;
	}

	public function callOnHScript(funcToCall:String, args:Array<Dynamic> = null, ?ignoreStops:Bool = false, exclusions:Array<String> = null, excludeValues:Array<Dynamic> = null):Dynamic {
		var returnVal:Dynamic = LuaUtils.Function_Continue;

		#if HSCRIPT_ALLOWED
		if(exclusions == null) exclusions = new Array();
		if(excludeValues == null) excludeValues = new Array();
		excludeValues.push(LuaUtils.Function_Continue);

		var len:Int = hscriptArray.length;
		if (len < 1)
			return returnVal;

		for(script in hscriptArray)
		{
			@:privateAccess
			if(script == null || !script.exists(funcToCall) || exclusions.contains(script.origin))
				continue;

			var callValue = script.call(funcToCall, args);
			if(callValue != null)
			{
				var myValue:Dynamic = callValue.returnValue;

				if((myValue == LuaUtils.Function_StopHScript || myValue == LuaUtils.Function_StopAll) && !excludeValues.contains(myValue) && !ignoreStops)
				{
					returnVal = myValue;
					break;
				}

				if(myValue != null && !excludeValues.contains(myValue))
					returnVal = myValue;
			}
		}
		#end

		return returnVal;
	}

	public function setOnScripts(variable:String, arg:Dynamic, exclusions:Array<String> = null) {
		if(exclusions == null) exclusions = [];
		setOnLuas(variable, arg, exclusions);
		setOnHScript(variable, arg, exclusions);
	}

	public function setOnLuas(variable:String, arg:Dynamic, exclusions:Array<String> = null) {
		#if LUA_ALLOWED
		if(exclusions == null) exclusions = [];
		for (script in luaArray) {
			if(exclusions.contains(script.scriptName))
				continue;

			script.set(variable, arg);
		}
		#end
	}

	public function setOnHScript(variable:String, arg:Dynamic, exclusions:Array<String> = null) {
		#if HSCRIPT_ALLOWED
		if(exclusions == null) exclusions = [];
		for (script in hscriptArray) {
			if(exclusions.contains(script.origin))
				continue;

			script.set(variable, arg);
		}
		#end
	}

	function strumPlayAnim(isDad:Bool, id:Int, time:Float, isHoldNote:Bool = false) {
		var spr:StrumNote = null;
		if(isDad) {
			spr = opponentStrums.members[id];
		} else {
			spr = playerStrums.members[id];
		}

		if(spr != null && ClientPrefs.data.cpuStrums) {
			var shouldPlay:Bool = true;
			if(ClientPrefs.data.singleHoldNoteAnimation && isHoldNote) {
				shouldPlay = !spr.holdConfirmActive;
			}
			if(shouldPlay) {
				spr.playAnim('confirm', true);
				var isHoldWithSingleAnim:Bool = ClientPrefs.data.singleHoldNoteAnimation && isHoldNote;
				// 对手箭头和 botplay 模式下玩家箭头都要始终自动恢复
				if(!isHoldWithSingleAnim) {
					spr.resetAnim = time;
					spr.holdConfirmActive = false;
				} else {
					spr.resetAnim = 0;
					spr.holdConfirmActive = true;
				}
				// botplay 模式下，标记箭头为 botplay 模式
				spr.isBotplayMode = true;
			}
			
			if(ClientPrefs.data.singleHoldNoteAnimation && isHoldNote) {
				spr.lastHoldAnimTime = 0; // 每次处理 hold note 时都重置计时器
			}
			else if (spr.holdConfirmActive) {
				// 对手箭头和 botplay 模式下玩家箭头都要始终自动恢复
				spr.holdConfirmActive = false;
				spr.resetAnim = time;
			}
		}
	}

	public var ratingName:String = '?';
	public var ratingNameKE:String = 'AAAAA';
	public var ratingPercent:Float;
	public var ratingFC:String;
	public function RecalculateRating(badHit:Bool = false, scoreBop:Bool = true) {
		setOnScripts('score', songScore);
		setOnScripts('misses', songMisses);
		setOnScripts('hits', songHits);
		setOnScripts('combo', combo);

		var ret:Dynamic = callOnScripts('onRecalculateRating', null, true);
		if(ret != LuaUtils.Function_Stop)
		{
			ratingName = '?';
			if(totalPlayed != 0) //Prevent divide by 0
			{
				// Rating Percent
				ratingPercent = Math.max(0, totalNotesHit / totalPlayed);
				//trace((totalNotesHit / totalPlayed) + ', Total: ' + totalPlayed + ', notes hit: ' + totalNotesHit);

				// Rating Name
				ratingName = ratingStuff[ratingStuff.length-1][0]; //Uses last string
				if(ratingPercent < 1)
					for (i in 0...ratingStuff.length-1)
						if(ratingPercent < ratingStuff[i][1])
						{
							ratingName = ratingStuff[i][0];
							break;
						}
				ratingNameKE = ratingStuffKE[ratingStuffKE.length-1][0]; //Uses last string
					if(ratingPercent < 1)
						for (i in 0...ratingStuffKE.length-1)
						if(ratingPercent < ratingStuffKE[i][1])
						{
							ratingNameKE = ratingStuffKE[i][0];
							break;
						}
			}
			fullComboFunction();
		}
		setOnScripts('rating', ratingPercent);
		setOnScripts('ratingName', ratingName);
		setOnScripts('ratingFC', ratingFC);
		setOnScripts('totalPlayed', totalPlayed);
		setOnScripts('totalNotesHit', totalNotesHit);
		updateScore(badHit, scoreBop); // score will only update after rating is calculated, if it's a badHit, it shouldn't bounce
	}

	#if ACHIEVEMENTS_ALLOWED
	private function checkForAchievement(achievesToCheck:Array<String> = null)
	{
		if(chartingMode) return;

		var usedPractice:Bool = (ClientPrefs.getGameplaySetting('practice') || ClientPrefs.getGameplaySetting('botplay'));
		if(cpuControlled) return;

		for (name in achievesToCheck) {
			if(!Achievements.exists(name)) continue;

			var unlock:Bool = false;
			if (name != WeekData.getWeekFileName() + '_nomiss') // common achievements
			{
				switch(name)
				{
					case 'ur_bad':
						unlock = (ratingPercent < 0.2 && !practiceMode);

					case 'ur_good':
						unlock = (ratingPercent >= 1 && !usedPractice);

					case 'oversinging':
						unlock = (boyfriend.holdTimer >= 10 && !usedPractice);

					case 'hype':
						unlock = (!boyfriendIdled && !usedPractice);

					case 'two_keys':
						unlock = (!usedPractice && keysPressed.length <= 2);

					case 'toastie':
						unlock = (!ClientPrefs.data.cacheOnGPU && !ClientPrefs.data.shaders && ClientPrefs.data.lowQuality && !ClientPrefs.data.antialiasing);

					#if BASE_GAME_FILES
					case 'debugger':
						unlock = (songName == 'test' && !usedPractice);
					#end
				}
			}
			else // any FC achievements, name should be "weekFileName_nomiss", e.g: "week3_nomiss";
			{
				if(isStoryMode && campaignMisses + songMisses < 1 && Difficulty.getString().toUpperCase() == 'HARD'
					&& storyPlaylist.length <= 1 && !changedDifficulty && !usedPractice)
					unlock = true;
			}

			if(unlock) Achievements.unlock(name);
		}
	}
	#end

	#if (!flash && sys)
	public var runtimeShaders:Map<String, Array<String>> = new Map<String, Array<String>>();
	#end
	public function createRuntimeShader(shaderName:String):ErrorHandledRuntimeShader
	{
		#if (!flash && sys)
		if(!ClientPrefs.data.shaders) return new ErrorHandledRuntimeShader(shaderName);

		if(!runtimeShaders.exists(shaderName) && !initLuaShader(shaderName))
		{
			FlxG.log.warn('Shader $shaderName is missing!');
			return new ErrorHandledRuntimeShader(shaderName);
		}

		var arr:Array<String> = runtimeShaders.get(shaderName);
		return new ErrorHandledRuntimeShader(shaderName, arr[0], arr[1]);
		#else
		FlxG.log.warn("Platform unsupported for Runtime Shaders!");
		return null;
		#end
	}

	public function initLuaShader(name:String, ?glslVersion:Int = 120)
	{
		if(!ClientPrefs.data.shaders) return false;

		#if (!flash && sys)
		if(runtimeShaders.exists(name))
		{
			FlxG.log.warn('Shader $name was already initialized!');
			return true;
		}

		for (folder in Mods.directoriesWithFile(Paths.getSharedPath(), 'shaders/'))
		{
			var frag:String = folder + name + '.frag';
			var vert:String = folder + name + '.vert';
			var found:Bool = false;
			if(FileSystem.exists(frag))
			{
				frag = File.getContent(frag);
				found = true;
			}
			else frag = null;

			if(FileSystem.exists(vert))
			{
				vert = File.getContent(vert);
				found = true;
			}
			else vert = null;

			if(found)
			{
				runtimeShaders.set(name, [frag, vert]);
				//trace('Found shader $name!');
				return true;
			}
		}
			#if (LUA_ALLOWED || HSCRIPT_ALLOWED)
			addTextToDebug('Missing shader $name .frag AND .vert files!', FlxColor.RED);
			#else
			FlxG.log.warn('Missing shader $name .frag AND .vert files!');
			#end
		#else
		FlxG.log.warn('This platform doesn\'t support Runtime Shaders!');
		#end
		return false;
	}

	public function makeLuaTouchPad(DPadMode:String, ActionMode:String) {
		if(members.contains(luaTouchPad)) return;

		if(!variables.exists("luaTouchPad"))
			variables.set("luaTouchPad", luaTouchPad);

		luaTouchPad = new TouchPad(DPadMode, ActionMode, ZERO);
		luaTouchPad.alpha = ClientPrefs.data.controlsAlpha;
	}
	
	public function addLuaTouchPad() {
		if(luaTouchPad == null || members.contains(luaTouchPad)) return;

		var target = LuaUtils.getTargetInstance();
		target.insert(target.members.length + 1, luaTouchPad);
	}

	public function addLuaTouchPadCamera() {
		if(luaTouchPad != null)
			luaTouchPad.cameras = [luaTpadCam];
	}

	public function removeLuaTouchPad() {
		if (luaTouchPad != null) {
			luaTouchPad.kill();
			luaTouchPad.destroy();
			remove(luaTouchPad);
			luaTouchPad = null;
		}
	}

	public function luaTouchPadPressed(button:Dynamic):Bool {
		if(luaTouchPad != null) {
			if(Std.isOfType(button, String))
				return luaTouchPad.buttonPressed(MobileInputID.fromString(button));
			else if(Std.isOfType(button, Array)){
				var FUCK:Array<String> = button; // haxe said "You Can't Iterate On A Dyanmic Value Please Specificy Iterator or Iterable *insert nerd emoji*" so that's the only i foud to fix
				var idArray:Array<MobileInputID> = [];
				for(strId in FUCK)
					idArray.push(MobileInputID.fromString(strId));
				return luaTouchPad.anyPressed(idArray);
			} else
				return false;
		}
		return false;
	}

	public function luaTouchPadJustPressed(button:Dynamic):Bool {
		if(luaTouchPad != null) {
			if(Std.isOfType(button, String))
				return luaTouchPad.buttonJustPressed(MobileInputID.fromString(button));
			else if(Std.isOfType(button, Array)){
				var FUCK:Array<String> = button;
				var idArray:Array<MobileInputID> = [];
				for(strId in FUCK)
					idArray.push(MobileInputID.fromString(strId));
				return luaTouchPad.anyJustPressed(idArray);
			} else
				return false;
		}
		return false;
	}
	
	public function luaTouchPadJustReleased(button:Dynamic):Bool {
		if(luaTouchPad != null) {
			if(Std.isOfType(button, String))
				return luaTouchPad.buttonJustReleased(MobileInputID.fromString(button));
			else if(Std.isOfType(button, Array)){
				var FUCK:Array<String> = button;
				var idArray:Array<MobileInputID> = [];
				for(strId in FUCK)
					idArray.push(MobileInputID.fromString(strId));
				return luaTouchPad.anyJustReleased(idArray);
			} else
				return false;
		}
		return false;
	}

	public function luaTouchPadReleased(button:Dynamic):Bool {
		if(luaTouchPad != null) {
			if(Std.isOfType(button, String))
				return luaTouchPad.buttonJustReleased(MobileInputID.fromString(button));
			else if(Std.isOfType(button, Array)){
				var FUCK:Array<String> = button;
				var idArray:Array<MobileInputID> = [];
				for(strId in FUCK)
					idArray.push(MobileInputID.fromString(strId));
				return luaTouchPad.anyReleased(idArray);
			} else
				return false;
		}
		return false;
	}

	function checkForResync()
	{
		if (endingSong || paused || shutdownThread)
			return;

		if (requiresSyncing && effectiveAutoResync())
		{
			requiresSyncing = false;
			setSongTime(lastCorrectSongPos);
		}

		gameFroze = false;
	}

	public function runSongSyncThread()
	{
		Thread.create(function()
		{
			while (!endingSong && !paused && !shutdownThread)
			{
				if (requiresSyncing)
					continue;

					if (gameFroze)
					{
						// 仅当有效自动重同步开启时才标记需要跳回，否则看门狗仅做空轮询（低延迟模式/autoResync 关闭时不“倒带”）
						if (effectiveAutoResync())
						{
							lastCorrectSongPos = Conductor.songPosition;
							requiresSyncing = true;
						}
						continue;
					}
				gameFroze = true;

				Sys.sleep(0.25);
			}
		});

		if (!FlxG.signals.preUpdate.has(checkForResync))
			FlxG.signals.preUpdate.add(checkForResync);
	}
}
