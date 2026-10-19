package states.editors;

import flixel.FlxSubState;
import flixel.util.FlxSave;
import flixel.util.FlxSort;
import flixel.util.FlxSpriteUtil;
import flixel.util.FlxStringUtil;
import flixel.util.FlxDestroyUtil;
import flixel.input.keyboard.FlxKey;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.util.FlxTimer;
import flixel.system.scaleModes.ChartingScaleMode;
import flixel.system.scaleModes.BaseScaleMode;
import flixel.addons.display.waveform.FlxWaveform;
import flixel.addons.display.waveform.FlxWaveform.WaveformDrawMode;
import flixel.addons.display.waveform.FlxWaveform.WaveformOrientation;
import flixel.addons.display.waveform.FlxWaveform.WaveformAlignment;

import openfl.events.Event;
import openfl.utils.Assets as OpenFlAssets;

import lime.utils.Assets;
import lime.media.AudioBuffer;

import flash.media.Sound;
import flash.geom.Rectangle;

import haxe.Json;
import haxe.Exception;
import haxe.io.Bytes;

import states.editors.content.MetaNote;
import states.editors.content.VSlice;
import states.editors.content.Prompt;
import states.editors.content.*;

import haxe.ui.Toolkit;
import haxe.ui.core.Component;
import haxe.ui.core.Screen;
import haxe.ui.components.Button;
import haxe.ui.components.Label;
import haxe.ui.events.MouseEvent;
import haxe.ui.events.MenuEvent;
import haxe.ui.events.UIEvent as HaxeUIEvent;
import haxe.ui.containers.menus.MenuBar;
import haxe.ui.containers.menus.Menu;
import haxe.ui.containers.menus.MenuItem;
import haxe.ui.backend.flixel.MouseHelper;

import states.MainMenuState;

import backend.Song;
import backend.StageData;
import backend.Highscore;
import backend.Difficulty;
import backend.ExtraKeysHandler;

import objects.Character;
import objects.HealthIcon;
import objects.Note;
import objects.StrumNote;

using DateTools;

typedef UndoStruct = {
	var action:UndoAction;
	var data:Dynamic;
}

enum abstract UndoAction(String)
{
	var ADD_NOTE = 'Add Note';
	var DELETE_NOTE = 'Delete Note';
	var MOVE_NOTE = 'Move Note';
	var SELECT_NOTE = 'Select Note';
	var MODIFY_NOTE = 'Modify Note';
}

enum abstract ChartingTheme(String)
{
	var LIGHT = 'light';
	var DARK = 'dark';
	var DEFAULT = 'default';
	var VSLICE = 'vslice';
	var CUSTOM = 'custom';
}

enum abstract WaveformTarget(String)
{
	var INST = 'inst';
	var PLAYER = 'voc';
	var OPPONENT = 'opp';
}

// 频谱波形渲染方式：旧版自研逐字节实现，或 flixel-waveform 库实现
enum abstract WaveformStyle(String)
{
	var LEGACY = 'legacy';
	var LIBRARY = 'library';
}

class ChartingState extends MusicBeatState implements PsychUIEventHandler.PsychUIEvent
{
	public static final defaultEvents:Array<Array<String>> =
	[
		['', "Nothing. Yep, that's right."], //Always leave this one empty pls
		['Dadbattle Spotlight', "Used in Dad Battle,\nValue 1: 0/1 = ON/OFF,\n2 = Target Dad\n3 = Target BF"],
		['Hey!', "Plays the \"Hey!\" animation from Bopeebo,\nValue 1: BF = Only Boyfriend, GF = Only Girlfriend,\nSomething else = Both.\nValue 2: Custom animation duration,\nleave it blank for 0.6s"],
		['Set GF Speed', "Sets GF head bopping speed,\nValue 1: 1 = Normal speed,\n2 = 1/2 speed, 4 = 1/4 speed etc.\nUsed on Fresh during the beatbox parts.\n\nWarning: Value must be integer!"],
		['Philly Glow', "Exclusive to Week 3\nValue 1: 0/1/2 = OFF/ON/Reset Gradient\n \nNo, i won't add it to other weeks."],
		['Kill Henchmen', "For Mom's songs, don't use this please, i love them :("],
		['Add Camera Zoom', "Used on MILF on that one \"hard\" part\nValue 1: Camera zoom add (Default: 0.015)\nValue 2: UI zoom add (Default: 0.03)\nLeave the values blank if you want to use Default."],
		['BG Freaks Expression', "Should be used only in \"school\" Stage!"],
		['Trigger BG Ghouls', "Should be used only in \"schoolEvil\" Stage!"],
		['Play Animation', "Plays an animation on a Character,\nonce the animation is completed,\nthe animation changes to Idle\n\nValue 1: Animation to play.\nValue 2: Character (Dad, BF, GF)"],
		['Camera Follow Pos', "Value 1: X\nValue 2: Y\n\nThe camera won't change the follow point\nafter using this, for getting it back\nto normal, leave both values blank."],
		['Alt Idle Animation', "Sets a specified postfix after the idle animation name.\nYou can use this to trigger 'idle-alt' if you set\nValue 2 to -alt\n\nValue 1: Character to set (Dad, BF or GF)\nValue 2: New postfix (Leave it blank to disable)"],
		['Screen Shake', "Value 1: Camera shake\nValue 2: HUD shake\n\nEvery value works as the following example: \"1, 0.05\".\nThe first number (1) is the duration.\nThe second number (0.05) is the intensity."],
		['Change Character', "Value 1: Character to change (Dad, BF, GF)\nValue 2: New character's name"],
		['Change Scroll Speed', "Value 1: Scroll Speed Multiplier (1 is default)\nValue 2: Time it takes to change fully in seconds (empty is instantly achieved)\nValue 3: Easing type (linear is default)"],
		['Set Property', "Value 1: Variable name\nValue 2: New value"],
		['Play Sound', "Value 1: Sound file name\nValue 2: Volume (Default: 1), ranges from 0 to 1"],
		//未完成
		['Change Window Title', "Value 1: Window title name"],
		['Change Opponent Scroll Speed', "same as Change Scroll Speed, but only for Opponent"],
		['Change Player Scroll Speed', "same as Change Scroll Speed, but only for Player"],
		['Toggle IconBop', "Enable or disable icon bopping.\nValue 1: on/off/true/false/0/1 (default: on)"],
		['Add IconBop', "Make the health icons bop once immediately."],
		// LE LTS 双侧轨道数：谱面播放到该事件时间点时实时切换两侧箭头轨道数（首字母大写；EventHandler 同时兼容小写老谱面）
		['Change KeyCount', "LE LTS dual keycount: switches lane count mid-song.\nValue 1: Player key count (e.g. 4, 6, 8)\nValue 2: Opponent key count (e.g. 6, 8)\nValue 3: Whether to re-show the key preview after the change (1/true/0/false; default 1 = show)"]
		];
	
	/** 根据事件名获取本地化描述，找不到翻译则返回原文 */
	public static function getEventDesc(eventName:String, originalDesc:String):String
	{
		var keySuffix = eventName.toLowerCase().replace(' ', '_').replace('!', '').replace("'", '');
		var key = 'charting_event_desc_' + (keySuffix == '' ? 'nothing' : keySuffix);
		var translated = Language.get(key);
		return (translated == key) ? originalDesc : translated;
	}
	
	public static var keysArray:Array<FlxKey> = [ONE, TWO, THREE, FOUR, FIVE, SIX, SEVEN, EIGHT]; //Used for Vortex Editor
	public static var SHOW_EVENT_COLUMN = true;
	public static var EVENT_TRACK_COUNT = 4; // Event轨道数量，用于分散同一时间点的多个event
	public static var GRID_COLUMNS_PER_PLAYER = 4;
	public static var GRID_PLAYERS = 2;
	public static var GRID_SIZE = 40;
	public static var TRACK_SPACING = 0; // 轨道间距（0=取消对手/事件/玩家三组之间的间距，使12条轨道连续排布）
	final BACKUP_EXT = '.bkp';

	// —— LE LTS 双侧轨道数（制谱器 LE 式分侧编辑） ——
	// editorSide：当前编辑侧（0=玩家、1=对手）。双侧模式下网格列数 = 该侧键数（各侧独立列数与网格），
	// 音符 noteData 按 LE 规则映射（mustHit 段 0..plr-1 玩家 / plr.. 对手；非 mustHit 段反之），
	// 对侧音符若超出当前编辑侧网格宽度则不显示（切换编辑侧后可编辑）。非双侧谱面恒为玩家侧语义。
	public static var editorSide:Int = 0;

	// LE LTS 双侧：谱面是否双侧模式（playerKeyCount 存在且 != keyCount）
	public static function isDualChart():Bool
	{
		return (PlayState.SONG != null && PlayState.SONG.playerKeyCount != null
			&& PlayState.SONG.keyCount != null && PlayState.SONG.playerKeyCount != PlayState.SONG.keyCount);
	}

	// 玩家侧键数（双侧模式；非双侧 = keyCount/mania+1）
	public static function dualPlayerKeyCount():Int
	{
		if (PlayState.SONG == null) return 4;
		if (PlayState.SONG.playerKeyCount != null) return Std.int(PlayState.SONG.playerKeyCount);
		if (PlayState.SONG.keyCount != null) return Std.int(PlayState.SONG.keyCount);
		return 4;
	}

	// 对手侧键数（双侧模式；非双侧 = keyCount/mania+1）
	public static function dualOpponentKeyCount():Int
	{
		if (PlayState.SONG == null) return 4;
		if (PlayState.SONG.keyCount != null) return Std.int(PlayState.SONG.keyCount);
		if (PlayState.SONG.playerKeyCount != null) return Std.int(PlayState.SONG.playerKeyCount);
		return 4;
	}

	// —— LE LTS 双侧：不对称网格列数 ——
	// 双侧模式下玩家/对手网格各自独立列数（网格布局/轨道色块/静态箭头/鼠标映射全部按各自列数渲染）；
	// 非双侧 = 实时读 SONG.mania+1（不能用静态 GRID_COLUMNS_PER_PLAYER——那是上次重建的缓存值，
	// 键数修改后若不重读 mania 会导致 applySectionColumns 的重建条件恒 false，轨道无变化）。
	public static function playerGridCols():Int
	{
		if (isDualChart()) return dualPlayerKeyCount();
		if (PlayState.SONG != null && PlayState.SONG.mania != null) return Std.int(PlayState.SONG.mania) + 1;
		return GRID_COLUMNS_PER_PLAYER;
	}
	public static function opponentGridCols():Int
	{
		if (isDualChart()) return dualOpponentKeyCount();
		if (PlayState.SONG != null && PlayState.SONG.mania != null) return Std.int(PlayState.SONG.mania) + 1;
		return GRID_COLUMNS_PER_PLAYER;
	}

	// 上次网格重建时的两侧列数（用于检测键数变化触发重建；双侧下编辑侧切换不触发）
	var _lastGridPlayerCols:Int = -1;
	var _lastGridOpponentCols:Int = -1;

	/**
	 * 制谱器高清模式开关：进入制谱器时临时将内部渲染分辨率提升到 1080P（仅桌面端生效），
	 * 退出制谱器后自动还原。设为 false 可关闭该功能。
	 */
	public static var ENABLE_HD:Bool = true;
	private static var _hdPrevScaleMode:BaseScaleMode = null;
	private static var _hdActive:Bool = false;

	/** 进入制谱器时的窗口尺寸，用于判断窗口缩放幅度 */
	private var _initialStageW:Int = 0;
	private var _initialStageH:Int = 0;

	/** 窗口缩放提示相关 UI（仅在桌面端、高清模式生效时启用） */
	private var _resizeBg:FlxSprite = null;
	private var _resizeText:FlxText = null;
	private var _resizeButton:PsychUIButton = null;
	private var _resizeDismissTimer:FlxTimer = null;
	private var _resizePromptActive:Bool = false;
	private var _resizePromptPersistent:Bool = false;

	/** 窗口尺寸变化多少算“明显变化”：宽高差绝对值之和超过该阈值时显示“重载界面”按钮。
	 * 阈值偏小（如 200）时轻微拖拽也会提示重载；调大（如 400）则只在大改窗口时提示。 */
	public static var RESIZE_PROMPT_THRESHOLD:Int = 300;


	public var quantizations:Array<Int> = [
		4,
		8,
		12,
		16,
		20,
		24,
		32,
		48,
		64,
		96,
		192
	];
	public var quantColors:Array<FlxColor> = [
		0xFFDF0000,
		0xFF4040CF,
		0xFFAF00AF,
		0xFFFFAF00,
		0xFFFFFFFF,
		0xFFFFA0FF,
		0xFFFF6030,
		0xFF00CFCF,
		0xFF00CF00,
		0xFF9F9F9F,
		0xFF3F3F3F,
	];
	var curQuant(default, set):Int = 16;
	function set_curQuant(v:Int)
	{
		curQuant = v;
		updateVortexColor();
		return curQuant;
	}
	function updateVortexColor()
		vortexIndicator.color = quantColors[Std.int(FlxMath.bound(quantizations.indexOf(curQuant), 0, quantColors.length - 1))];

	var sectionFirstNoteID:Int = 0;
	var sectionFirstEventID:Int = 0;
	var curSec:Int = 0;
	
	// 不受noteOffset影响的纯粹播放信息（用于右下角显示）
	var curSecPure:Int = 0;
	var curBeatPure:Int = 0;
	var curStepPure:Int = 0;
	
	// 优化音符加载：预保存数据，延迟创建 MetaNote
	var preloadedNoteData:Array<Dynamic> = [];
	var preloadedSecNum:Array<Int> = [];
	var preloadedMetaNotes:Array<MetaNote> = [];
	private var useOptimizedLoading:Bool = false; // 本次编辑实际采用的加载方式

	private function resolveOptimizedLoading():Bool
	{
		var setting:String = ClientPrefs.data.useOptimizedNoteLoading;
		if (setting == null) setting = 'AUTO';
		setting = setting.toUpperCase();
		if (setting == 'ON') return true;
		if (setting == 'OFF') return false;
		// AUTO：按谱面 notesPerSecond 自动判断
		var totalNotes:Int = 0;
		var totalSections:Int = 0;
		var lastStrumTimeMs:Float = 0;
		if (PlayState.SONG != null && PlayState.SONG.notes != null)
		{
			var secs:Array<Dynamic> = cast PlayState.SONG.notes;
			for (i in 0...secs.length)
			{
				var section:Dynamic = secs[i];
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
		var msLen:Float = (FlxG.sound.music != null) ? FlxG.sound.music.length : 0;
		var seconds:Float = 0;
		var lenSource:String = 'music.length';
		if (msLen > 0)
			seconds = msLen / 1000.0;
		else if (lastStrumTimeMs > 0)
		{
			seconds = (lastStrumTimeMs + 2000.0) / 1000.0;
			lenSource = 'lastStrumTime(+2s pad)';
		}
		if (seconds <= 0)
		{
			trace('[ChartingState.OptimizedNoteLoading] sections=$totalSections totalNotes=$totalNotes no duration → LEGACY');
			return false;
		}
		var notesPerSecond:Float = totalNotes / seconds;
		trace('[ChartingState.OptimizedNoteLoading] sections=$totalSections totalNotes=$totalNotes seconds=$seconds($lenSource) notesPerSecond=$notesPerSecond threshold(1w)=100 threshold(1w>)=50');
		return notesPerSecond >= 100 || (totalNotes > 10000 && notesPerSecond > 50);
	}

	var chartEditorSave:FlxSave;
	var mainBox:PsychUIBox;
	var mainBoxPosition:FlxPoint = FlxPoint.get(920, 40);
	var infoBox:PsychUIBox;
	var infoBoxPosition:FlxPoint = FlxPoint.get(1000, 360);
	var upperBox:PsychUIBox;
	var searchBox:PsychUIBox;
	var camUI:FlxCamera;
	var camChart:FlxCamera;

	// 角色对象
	public var dad:Character;
	public var boyfriend:Character;
	public var charactersLoaded:Bool = false;

	// idle动画重新播放标记（初始为true，让角色开始播放idle动画）
	private var boyfriendNeedIdleReplay:Bool = true;
	private var dadNeedIdleReplay:Bool = true;

	// sing Duration完成时的beat记录（用于在下一拍播放idle）
	private var boyfriendSingFinishedBeat:Null<Int> = null;
	private var dadSingFinishedBeat:Null<Int> = null;

	// 角色拖动相关
	private var isDraggingCharacter:Bool = false;
	private var draggedCharacter:Character = null;
	private var dragOffsetX:Float = 0;
	private var dragOffsetY:Float = 0;

	

	private var lastBeat:Int = 0;

	// Sing动画相关
	private var singAnimations:Array<String> = ['singLEFT', 'singDOWN', 'singUP', 'singRIGHT'];

	// LE LTS 双侧：玩家侧 / 对手侧各自独立的列配色数组（按各自键数档位从 extrakeys.json 填充）。
	// 双侧谱面音符为 LE 连续编号跨两侧渲染，单份 Note.colArray（编辑侧档）无法同时满足两侧取色，
	// 音符构造时按自身侧（editorSideNote）选用对应数组。
	private var playerColArrayCache:Array<String> = null;
	private var opponentColArrayCache:Array<String> = null;

	var prevOpponentGridBg:ChartingGridSprite;
	var prevEventGridBg:ChartingGridSprite;
	var prevPlayerGridBg:ChartingGridSprite;
	var opponentGridBg:ChartingGridSprite;
	var eventGridBg:ChartingGridSprite;
	var playerGridBg:ChartingGridSprite;
	var nextOpponentGridBg:ChartingGridSprite;
	var nextEventGridBg:ChartingGridSprite;
	var nextPlayerGridBg:ChartingGridSprite;
	var scrollY:Float = 0;
	
	// Grid轨道颜色覆盖层
	var playerTrackOverlay:FlxSprite; // 玩家轨道（蓝色）
	var opponentTrackOverlay:FlxSprite; // 对手轨道（红色）
	var _rebuildingGrids:Bool = false; // 防止 createGrids 递归调用 loadSection 的守护标志
	var eventTrackOverlay:FlxSprite; // Event轨道（黄色）

	var iconbopTween:FlxTween;

	var zoomList:Array<Float> = [
		0.25,
		0.5,
		1,
		2,
		3,
		4,
		6,
		8,
		12,
		16,
		24
	];
	var curZoom:Float = 1;

	var mustHitIndicator:FlxSprite;
	var eventIcon:FlxSprite;
	var icons:Array<HealthIcon> = [];

	var events:Array<EventMetaNote> = [];
	var notes:Array<MetaNote> = [];

	var behindRenderedNotes:FlxTypedGroup<MetaNote> = new FlxTypedGroup<MetaNote>();
	var curRenderedNotes:FlxTypedGroup<MetaNote> = new FlxTypedGroup<MetaNote>();
	var movingNotes:FlxTypedGroup<MetaNote> = new FlxTypedGroup<MetaNote>();
	var eventLockOverlay:FlxSprite;
	var vortexIndicator:FlxSprite;

	// Lil' Buddies 制谱器迷你角色预览
	var lilStage:FlxSprite;
	var lilBf:FlxSprite;
	var lilOpp:FlxSprite;
	var lilBfSingFinishedBeat:Int = -1;  // 上次 playLilSing 发生在哪一拍（-1 表示 idle 中）
    var lilOppSingFinishedBeat:Int = -1;
    var lilBfInSustain:Bool = false;
    var lilOppInSustain:Bool = false;
    var lilLastStrumCheckTime:Float = 0;  // 独立的时间窗口起点，自己维护不依赖外部 lastTime

	var strumLineNotes:FlxTypedGroup<StrumNote> = new FlxTypedGroup<StrumNote>();
	var dummyArrow:FlxSprite;
	var dragPreview:FlxSprite;
	var isDraggingNote:Bool = false;
	var dragNote:MetaNote = null;
	var dragExistingNote:Bool = false; // 当前拖动是否为“延伸已有箭头”而非新建
	var dragExtendOriginalSustain:Float = 0; // 延伸前记录的原始长条长度（用于撤销）
	var dragPendingNote:MetaNote = null; // 左键按住已有箭头后的待命状态，移动超过阈值才真正开始延伸拖动
	var dragPendingStartY:Float = 0; // 进入待命拖动时的鼠标Y（用于判断拖动阈值）
	var dragStartStrumTime:Float = 0;
	var dragStartNoteData:Int = 0;
	var dragStartTrackType:String = 'normal';
	var dragStartEventTrackIndex:Null<Int> = null;
	var dragStartX:Float = 0;
	var dragStartChartY:Float = 0;
	var dragStartMouseY:Float = 0; // 按下左键时的原始鼠标Y，用于区分“单击”与“向下拖动”
	var rightClickDeleteNote:Bool = false;
	var dragCreateHoldNote:Bool = true;
	var isMovingNotes:Bool = false;
	var movingNotesLastData:Int = 0;
	var movingNotesLastY:Float = 0;
	// 叠加标记：同 strumTime（同一网格行）+ 同列的箭头/事件数量 > 1 时，在格子右下角显示 "xN"（位于箭头图层之上）
	var overlapMarkers:FlxTypedGroup<FlxText>;
	// 去重按钮（当前小节 / 整个谱面；无重复时自动隐藏且不可按下）
	var dedupe1Button:PsychUIButton = null;
	var clearDupButton:PsychUIButton = null;
	// 《音符/事件》复选框（去重按钮与"清空"按钮共用；勾选决定去重处理哪些类型）
	var affectNotes:PsychUICheckBox = null;
	var affectEvents:PsychUICheckBox = null;
	
	var vocals:FlxSound = new FlxSound();
	var opponentVocals:FlxSound = new FlxSound();
	
	// 击打声音效池 - 用于高密度音符播放
	var hitSoundPool:Array<FlxSound> = [];
	var hitSoundPoolSize:Int = 16; // 池大小
	var hitSoundPoolIndex:Int = 0; // 轮询索引

	// 轨道颜色标识控制
	var trackColorsCheckBox:PsychUICheckBox; // 主题设置中的复选框

	// 视觉效果控制变量
	var iconBopEnabled:Bool = true;        // 小图标跳动开关
	var mustHitTweenEnabled:Bool = true;  // mustHitIndicator的倒三角tween

	var timeLine:FlxSprite;
	var infoText:FlxText;

	var autoSaveIcon:FlxSprite;
	var outputTxt:FlxText;

	var selectionStart:FlxPoint = FlxPoint.get();
	var selectionBox:FlxSprite;

	var _shouldReset:Bool = true;
	var _blockParentUpdate:Bool = false;
	public function new(?shouldReset:Bool = true)
	{
		this._shouldReset = shouldReset;
		super();
	}

	var bg:FlxSprite;
	var theme:ChartingTheme = DEFAULT;

	var copiedNotes:Array<Dynamic> = [];
	var copiedEvents:Array<Dynamic> = [];
	
	var _keysPressedBuffer:Array<Bool> = [];

	var tipBg:FlxSprite;
	var fullTipText:FlxText;
	
	var vortexEnabled:Bool = false;
	var waveformEnabled:Bool = false;
	var waveformTargets:Array<WaveformTarget> = [INST]; // 库版：可多选
	var waveformTargetLegacy:WaveformTarget = INST;     // 旧版：单选
	var waveformStyle:WaveformStyle = LIBRARY;
	// flixel-waveform 库实现的频谱精灵，与旧版 waveformSprite 并存，供用户切换样式
	var waveformSprites:Array<FlxSprite> = [];
	// 库版频谱为双缓冲（前台显示 + 后台预渲染下一 section），消除 section 切换时的闪烁
	var waveformLibSprites:Array<FlxWaveform> = [];      // 前台：当前显示的波形
	var waveformLibBackSprites:Array<FlxWaveform> = [];  // 后台：预渲染下一 section 的备用波形
	var waveformLibCacheSection:Array<Int> = [-1, -1, -1]; // 前台各目标当前缓存的 section
	var waveformLibBackSection:Array<Int> = [-1, -1, -1];  // 后台各目标已预渲染的 section
	var waveformLibPreRenderCursor:Int = 0;                 // 后台预渲染轮询游标
	var waveformLibLoadedBuffers:Array<AudioBuffer> = [null, null, null];      // 前台各目标已加载的音频缓冲
	var waveformLibBackLoadedBuffers:Array<AudioBuffer> = [null, null, null];  // 后台各目标已加载的音频缓冲（与前台独立，避免后台上台互跳过 loadData）
	// flixel-waveform 库版的独立样式参数（与旧版各存一套，互不影响）
	var waveformLibColor:String = '0F4C81';
	var waveformLibDrawMode:String = 'COMBINED';
	var waveformLibRMS:Bool = false;
	var waveformLibRMSColor:String = '98B4D4';
	var waveformLibBaseline:Bool = false;
	var waveformLibBarSize:Int = 1;
	var waveformLibBarPadding:Int = 0;
	var waveformLibGain:Float = 1;

	// 定义全局字体变量
	public static var defaultFont:String = Paths.font(Language.get('uitab_font'));

	override function create()
	{
		// 进入制谱器时临时隐藏 FPS 计数器（不受 showFPS 设置与窗口缩放影响），退出时还原
		Main.forceHideFPS = true;
		if (Main.fpsVar != null) Main.fpsVar.visible = false;

		// 制谱器高清模式：进入时临时把内部渲染分辨率提升到 720P~1080P（移动端允许更宽），
		// 退出时还原。必须在创建任何相机/UI 之前调用，这样相机与布局都会基于新分辨率生成
		// 是否启用由设置项 chartEditorFollowWindow 控制：开启则跟随窗口，关闭则使用游戏默认1280x720
		if (ENABLE_HD && ClientPrefs.data.chartEditorFollowWindow)
		{
			if (!_hdActive)
			{
				_hdPrevScaleMode = FlxG.scaleMode;
				FlxG.scaleMode = new ChartingScaleMode();
				FlxG.resizeGame(FlxG.stage.stageWidth, FlxG.stage.stageHeight);
				_hdActive = true;
			}
			// 记录进入时的窗口尺寸，并监听窗口缩放（移动端为旋转触发的 RESIZE）
			_initialStageW = FlxG.stage.stageWidth;
			_initialStageH = FlxG.stage.stageHeight;
			FlxG.stage.addEventListener(Event.RESIZE, onWindowResized);
		}



		if(Difficulty.list.length < 1) Difficulty.resetList();
		_keysPressedBuffer.resize(keysArray.length);

if(_shouldReset) Conductor.songPosition = 0;
	persistentUpdate = true; // 保持持续更新：确保淡入转场期间顶部条信息也能实时刷新
	FlxG.mouse.visible = true;
	FlxG.sound.list.add(vocals);
	FlxG.sound.list.add(opponentVocals);
	
	// 初始化击打声音效池
	for (i in 0...hitSoundPoolSize)
	{
		hitSoundPool[i] = new FlxSound();
		FlxG.sound.list.add(hitSoundPool[i]);
	}

		vocals.autoDestroy = false;
		vocals.looped = true;
		opponentVocals.autoDestroy = false;
		opponentVocals.looped = true;

	initPsychCamera();
	camUI = new FlxCamera();
	camUI.bgColor.alpha = 0;
	FlxG.cameras.add(camUI, false);

	camChart = new FlxCamera();
	camChart.bgColor.alpha = 0;
	FlxG.cameras.add(camChart, false);

		chartEditorSave = new FlxSave();
		chartEditorSave.bind('chart_editor_data', CoolUtil.getSavePath());

		bg = new FlxSprite().loadGraphic(Paths.image('menuDesat'));
		bg.antialiasing = ClientPrefs.data.antialiasing;
		bg.scrollFactor.set();
		add(bg);
		resizeBg();

		if(chartEditorSave.data.autoSave != null) autoSaveCap = chartEditorSave.data.autoSave;
		if(chartEditorSave.data.backupLimit != null) backupLimit = chartEditorSave.data.backupLimit;
		if(chartEditorSave.data.vortex != null) vortexEnabled = chartEditorSave.data.vortex;

		// 加载视觉效果设置
		if(chartEditorSave.data.iconBopEnabled != null) iconBopEnabled = chartEditorSave.data.iconBopEnabled;
		if(chartEditorSave.data.mustHitTweenEnabled != null) mustHitTweenEnabled = chartEditorSave.data.mustHitTweenEnabled;
		if(chartEditorSave.data.showCharacters == null) chartEditorSave.data.showCharacters = false;
		if(chartEditorSave.data.allowDragCharacters == null) chartEditorSave.data.allowDragCharacters = false;
		if(chartEditorSave.data.mouseScrollSnap == null) chartEditorSave.data.mouseScrollSnap = false;
		if(chartEditorSave.data.ignoreProgressWarns == null) chartEditorSave.data.ignoreProgressWarns = false;
		if(chartEditorSave.data.rightClickDeleteNote == null) chartEditorSave.data.rightClickDeleteNote = true;
		if(chartEditorSave.data.dragCreateHoldNote == null) chartEditorSave.data.dragCreateHoldNote = true;
		rightClickDeleteNote = chartEditorSave.data.rightClickDeleteNote;
		dragCreateHoldNote = chartEditorSave.data.dragCreateHoldNote;

		// Lil' Buddies 迷你角色预览设置
		if(chartEditorSave.data.showLilBuddies == null) chartEditorSave.data.showLilBuddies = true;
		if (controls.mobileC)
		{
			// 移动端自动禁用右键移除箭头 / 拖动生成长条，避免影响触控游玩体验
			rightClickDeleteNote = false;
			dragCreateHoldNote = false;
		}

		// 音频相关设置（charting 选项卡需保存的项，播放速度除外）
		if(chartEditorSave.data.hitsoundPlayerVol == null) chartEditorSave.data.hitsoundPlayerVol = 0;
		if(chartEditorSave.data.hitsoundOpponentVol == null) chartEditorSave.data.hitsoundOpponentVol = 0;
		if(chartEditorSave.data.metronomeVol == null) chartEditorSave.data.metronomeVol = 0;
		if(chartEditorSave.data.instVolume == null) chartEditorSave.data.instVolume = 0.6;
		if(chartEditorSave.data.playerVolume == null) chartEditorSave.data.playerVolume = 1;
		if(chartEditorSave.data.opponentVolume == null) chartEditorSave.data.opponentVolume = 1;
		if(chartEditorSave.data.instMuted == null) chartEditorSave.data.instMuted = false;
		if(chartEditorSave.data.playerMuted == null) chartEditorSave.data.playerMuted = false;
		if(chartEditorSave.data.opponentMuted == null) chartEditorSave.data.opponentMuted = false;

		if(chartEditorSave.data.customBgColor == null) chartEditorSave.data.customBgColor = '303030';
		if(chartEditorSave.data.customGridColors == null || chartEditorSave.data.customGridColors.length < 2)
			chartEditorSave.data.customGridColors = ['DFDFDF', 'BFBFBF'];
		if(chartEditorSave.data.customNextGridColors == null || chartEditorSave.data.customNextGridColors.length < 2)
			chartEditorSave.data.customNextGridColors = ['5F5F5F', '4A4A4A'];
		
		changeTheme(chartEditorSave.data.theme != null ? chartEditorSave.data.theme : DEFAULT, false);

		createGrids();

		var gridLayout = getGridLayout();
		// 每个目标（伴奏/主唱/对唱）各建一份频谱精灵，支持同时显示多个
		for (t in [INST, PLAYER, OPPONENT])
		{
			var ws = new FlxSprite(gridLayout.startX, 0).makeGraphic(1, 1, 0x00FFFFFF);
			ws.scrollFactor.x = 0;
			ws.visible = false;
			add(ws);
			waveformSprites.push(ws);

			// flixel-waveform 库实现的频谱（默认隐藏，由 updateWaveform 按样式启用）
		// 每目标双缓冲：前台显示当前 section，后台预渲染下一 section
		var wl = new ChartingWaveform(gridLayout.startX, 0, 1, 1, FlxColor.WHITE, 0x00FFFFFF, COMBINED);
		wl.scrollFactor.x = 0;
		wl.waveformDrawBaseline = false;
		wl.waveformBarSize = 1;
		wl.waveformBarPadding = 0;
		wl.visible = false;
		// 后台缓冲关闭自动重绘，改由预渲染逻辑手动 generateWaveformBitmap()
		wl.autoUpdateBitmap = false;
		add(wl);
		waveformLibSprites.push(wl);

		var wlB = new ChartingWaveform(gridLayout.startX, 0, 1, 1, FlxColor.WHITE, 0x00FFFFFF, COMBINED);
		wlB.scrollFactor.x = 0;
		wlB.waveformDrawBaseline = false;
		wlB.waveformBarSize = 1;
		wlB.waveformBarPadding = 0;
		wlB.visible = false;
		wlB.autoUpdateBitmap = false;
		add(wlB);
		waveformLibBackSprites.push(wlB);
	}

		dummyArrow = new FlxSprite().makeGraphic(1, 1, FlxColor.WHITE);
		dummyArrow.setGraphicSize(GRID_SIZE, GRID_SIZE);
		dummyArrow.updateHitbox();
		dummyArrow.scrollFactor.x = 0;
		add(dummyArrow);

		dragPreview = new FlxSprite().makeGraphic(1, 1, 0x4DD2FF);
		dragPreview.setGraphicSize(GRID_SIZE, 1);
		dragPreview.updateHitbox();
		dragPreview.scrollFactor.x = 0;
		dragPreview.alpha = 0.4;
		dragPreview.visible = false;
		add(dragPreview);

		vortexIndicator = new FlxSprite(gridLayout.startX - GRID_SIZE, FlxG.height/2).loadGraphic(Paths.image('editors/vortex_indicator'));
		vortexIndicator.setGraphicSize(GRID_SIZE);
		vortexIndicator.updateHitbox();
		vortexIndicator.scrollFactor.set();
		vortexIndicator.active = false;
		updateVortexColor();
		add(vortexIndicator);

		// ===== Lil' Buddies 制谱器迷你角色预览 =====
		// 固定在屏幕左下角，不随谱面滚动（scrollFactor=0）
		// layout: lilStage 在最底层背景 → lilBf(左) + lilOpp(右) 角色精灵
		var lilVisible:Bool = chartEditorSave.data.showLilBuddies;

		// 舞台背景 256×256，左下角，底部离屏幕 32px
            var lilBaseY:Float = FlxG.height - 256 - 32;
            lilStage = new FlxSprite(32, lilBaseY).loadGraphic(Paths.image('editors/lilStage'));
            lilStage.scrollFactor.set();
            lilStage.visible = lilVisible;
            add(lilStage);

            // 迷你 BF 300×256 每帧，和舞台底部对齐
            lilBf = new FlxSprite(32, lilBaseY).loadGraphic(Paths.image('editors/lilBf'), true, 300, 256);
		lilBf.animation.add('idle', [0, 1], 12, true);
		lilBf.animation.add('0', [3, 4, 5], 12, false);
		lilBf.animation.add('1', [6, 7, 8], 12, false);
		lilBf.animation.add('2', [9, 10, 11], 12, false);
		lilBf.animation.add('3', [12, 13, 14], 12, false);
		lilBf.animation.add('yeah', [17, 20, 23], 12, false);
		lilBf.animation.play('idle');
		lilBf.animation.onFinish.add(function(name:String){
			if(lilBf != null && name != 'idle')
				lilBf.animation.play(name, true, false, lilBf.animation.getByName(name).numFrames - 2);
		});
		lilBf.scrollFactor.set();
		lilBf.visible = lilVisible;
		add(lilBf);

		// 迷你对手 300×256 每帧，放在 lilBf 右边
		lilOpp = new FlxSprite(32, lilBaseY).loadGraphic(Paths.image('editors/lilOpp'), true, 300, 256);
		lilOpp.animation.add('idle', [0, 1], 12, true);
		lilOpp.animation.add('0', [3, 4, 5], 12, false);
		lilOpp.animation.add('1', [6, 7, 8], 12, false);
		lilOpp.animation.add('2', [9, 10, 11], 12, false);
		lilOpp.animation.add('3', [12, 13, 14], 12, false);
		lilOpp.animation.play('idle');
		lilOpp.animation.onFinish.add(function(name:String){
			if(lilOpp != null && name != 'idle')
				lilOpp.animation.play(name, true, false, lilOpp.animation.getByName(name).numFrames - 2);
		});
		lilOpp.scrollFactor.set();
		lilOpp.visible = lilVisible;
		add(lilOpp);

		// 创建轨道颜色覆盖层 - 只在gridBg显示的区域，放在strumLineNotes之前
		var gridHeight:Float = opponentGridBg.height; // 只覆盖grid显示的高度

		// 初始化轨道颜色显示设置
		if(chartEditorSave.data.showTrackColors == null) chartEditorSave.data.showTrackColors = true;
		// 初始化轨道分隔线显示设置
		if(chartEditorSave.data.showTrackSeparators == null) chartEditorSave.data.showTrackSeparators = true;

		// 新轨道布局：对手(0-3) → Event(4-7) → 玩家(8-11)
		var gridY:Float = 0; // 从屏幕顶部开始，覆盖整个屏幕
		var extraHeight:Int = 500; // 增加500像素缓冲确保覆盖整个网格区域
		var gridLayout = getGridLayout();

		// 对手轨道覆盖层（最左侧，UI列0至对手键数-1；LE LTS 双侧：按对手侧键数）
		opponentTrackOverlay = new FlxSprite(gridLayout.opponentX, gridY).makeGraphic(GRID_SIZE * opponentGridCols(), Std.int(gridHeight) + extraHeight, 0xFFCC88FF); // 浅紫色
		opponentTrackOverlay.alpha = 0.15;
		opponentTrackOverlay.scrollFactor.set(0, 0); // X和Y方向都固定，不随网格滚动
		opponentTrackOverlay.visible = chartEditorSave.data.showTrackColors;
		add(opponentTrackOverlay);

		// Event轨道覆盖层（中间，UI列4-7）- 4列宽度
		if(SHOW_EVENT_COLUMN)
		{
			eventTrackOverlay = new FlxSprite(gridLayout.eventX, gridY).makeGraphic(GRID_SIZE * EVENT_TRACK_COUNT, Std.int(gridHeight) + extraHeight, 0xFFFFFF44); // 黄色
			eventTrackOverlay.alpha = 0.15;
			eventTrackOverlay.scrollFactor.set(0, 0); // X和Y方向都固定，不随网格滚动
			eventTrackOverlay.visible = chartEditorSave.data.showTrackColors;
			add(eventTrackOverlay);
		}

		// 玩家轨道覆盖层（最右侧；LE LTS 双侧：按玩家侧键数）
		playerTrackOverlay = new FlxSprite(gridLayout.playerX, gridY).makeGraphic(GRID_SIZE * playerGridCols(), Std.int(gridHeight) + extraHeight, 0xFF88CCFF); // 浅蓝色
		playerTrackOverlay.alpha = 0.15;
		playerTrackOverlay.scrollFactor.set(0, 0); // X和Y方向都固定，不随网格滚动
		playerTrackOverlay.visible = chartEditorSave.data.showTrackColors;
		add(playerTrackOverlay);

		add(strumLineNotes);

		add(behindRenderedNotes);
		add(curRenderedNotes);
		add(movingNotes);

		// 叠加标记层（最后 add → 渲染在最上层，覆盖箭头/长条）
		overlapMarkers = new FlxTypedGroup<FlxText>();
		add(overlapMarkers);

		eventLockOverlay = new FlxSprite(SHOW_EVENT_COLUMN ? gridLayout.eventX : gridLayout.opponentX, 0).makeGraphic(1, 1, FlxColor.BLACK);
		eventLockOverlay.alpha = 0.6;
		eventLockOverlay.visible = false;
		eventLockOverlay.scrollFactor.x = 0;
		eventLockOverlay.scale.x = GRID_SIZE * EVENT_TRACK_COUNT;
		eventLockOverlay.updateHitbox();
		add(eventLockOverlay);

		timeLine = new FlxSprite(gridLayout.startX, 0).makeGraphic(1, 1, FlxColor.WHITE);
		timeLine.setGraphicSize(Std.int(gridLayout.totalWidth), 4);
		timeLine.updateHitbox();
		timeLine.screenCenter(Y);
		timeLine.scrollFactor.set();
		add(timeLine);


		var startX:Float = gridLayout.startX;
		var startY:Float = FlxG.height/2;
		vortexIndicator.visible = strumLineNotes.visible = strumLineNotes.active = vortexEnabled;

		// 漩涡编辑器静态箭头：固定 4 列
		// LE LTS 双侧：提前同步编辑器静态档位——strums 在 applySectionColumns/reloadNotes 之前创建，
		// 双侧下必须让 StrumNote 构造即按两侧键数取档（PlayState.instance 为 null）。
		Note.editorDualMode = isDualChart();
		if (isDualChart()) { Note.editorPlrKeys = dualPlayerKeyCount(); Note.editorOppKeys = dualOpponentKeyCount(); }
		rebuildStrumLineNotes();


		// 为Grid格子添加颜色滤镜（新布局：对手 → Event → 玩家）
		applyGridStripeColors();



		var gridStripes:Array<Int> = [];
		var iconY:Float = 50;

		mustHitIndicator = FlxSpriteUtil.drawTriangle(new FlxSprite(0, iconY - 20).makeGraphic(16, 16, FlxColor.TRANSPARENT), 0, 0, 16);
		mustHitIndicator.scrollFactor.set();
		mustHitIndicator.flipY = true;
		mustHitIndicator.offset.x += mustHitIndicator.width/2;
		add(mustHitIndicator);

		// Event图标（新布局：在Event轨道中心，UI列5.5）
		if(SHOW_EVENT_COLUMN)
		{
			eventIcon = new FlxSprite(0, iconY).loadGraphic(Paths.image('editors/eventIcon'));
			eventIcon.antialiasing = ClientPrefs.data.antialiasing;
			eventIcon.alpha = 0.6;
			eventIcon.setGraphicSize(30, 30);
			eventIcon.updateHitbox();
			eventIcon.scrollFactor.set();

			add(eventIcon);
			// Event轨道的起始偏移：GRID_COLUMNS_PER_PLAYER（对手4列），中心点再偏移2列
			eventIcon.x = gridLayout.eventX + GRID_SIZE * 2 - eventIcon.width/2;
		}

		// 为对手和玩家添加图标（修复后：交换位置）
		for (i in 0...GRID_PLAYERS)
		{
			// icons[0]是对手，icons[1]是玩家（顺序不变，仅交换位置）
			var icon:HealthIcon = new HealthIcon();
			icon.autoAdjustOffset = false;
			icon.y = iconY;
			icon.alpha = 0.6;
			icon.scrollFactor.set();
			icon.scale.set(0.3, 0.3);
			icon.updateHitbox();
			icon.ID = i + 1;
			add(icon);
			icons.push(icon);
			// 修复逻辑：i=0（对手）用玩家偏移，i=1（玩家）用对手偏移（LE LTS 双侧：按各自键数列数）
			var pColsI:Int = playerGridCols();
			var oColsI:Int = opponentGridCols();
			var iconStartOffset:Int = (i == 0) ? (oColsI + EVENT_TRACK_COUNT) : 0;
			icon.x = gridLayout.startX + GRID_SIZE * iconStartOffset + (iconStartOffset > 0 ? TRACK_SPACING * 2 : 0) + GRID_SIZE * ((i == 0) ? pColsI : oColsI) / 2 - icon.width / 2;
		}
		// 直接进入制谱器时可能还没有加载任何歌曲，先确保 SONG 已初始化，避免空引用崩溃
		if(PlayState.SONG == null)
		{
			openNewChart();
		}

		// 设置 mustHitIndicator 的初始位置
		var initialMustHit:Bool = (PlayState.SONG.notes.length > 0 && PlayState.SONG.notes[0] != null && PlayState.SONG.notes[0].mustHitSection);
		var initialTargetX:Float = initialMustHit ? (icons[0].x + icons[0].width / 2) : (icons[1].x + icons[1].width / 2);
		mustHitIndicator.x = initialTargetX;
		opponentGridBg.stripes = prevOpponentGridBg.stripes = nextOpponentGridBg.stripes = gridStripes;
		if(SHOW_EVENT_COLUMN) eventGridBg.stripes = prevEventGridBg.stripes = nextEventGridBg.stripes = gridStripes;
		playerGridBg.stripes = prevPlayerGridBg.stripes = nextPlayerGridBg.stripes = gridStripes;



		selectionBox = new FlxSprite().makeGraphic(1, 1, FlxColor.CYAN);
		selectionBox.alpha = 0.4;
		selectionBox.blend = ADD;
		selectionBox.scrollFactor.set();
		selectionBox.visible = false;
		add(selectionBox);

		infoBox = new PsychUIBox(infoBoxPosition.x #if mobile - 900 #end, infoBoxPosition.y #if mobile - 250 #end, 220, 220, [Language.get('charting_infotab_text')]);
		infoBox.scrollFactor.set();
		infoBox.cameras = [camUI];
		infoText = new FlxText(15, 15, 230, '', 16);
		infoText.scrollFactor.set();
		infoBox.getTab(Language.get('charting_infotab_text')).menu.add(infoText);
		add(infoBox);

		mainBox = new PsychUIBox(mainBoxPosition.x, mainBoxPosition.y, 350, 360, [Language.get('charting_charting_text'), Language.get('charting_data_text'), Language.get('charting_events_text'), Language.get('charting_notes_text'), Language.get('charting_section_text'), Language.get('charting_song_text')]);
		mainBox.selectedName = Language.get('charting_song_text');
		mainBox.scrollFactor.set();
		mainBox.cameras = [camUI];
		add(mainBox);

		autoSaveIcon = new FlxSprite(50).loadGraphic(Paths.image('editors/autosave'));
		autoSaveIcon.screenCenter(Y);
		autoSaveIcon.scale.set(0.6, 0.6);
		autoSaveIcon.antialiasing = ClientPrefs.data.antialiasing;
		autoSaveIcon.scrollFactor.set();
		autoSaveIcon.alpha = 0;
		add(autoSaveIcon);

		// save data positions for the UI boxes
		if(chartEditorSave.data.mainBoxPosition != null && chartEditorSave.data.mainBoxPosition.length > 1)
			mainBox.setPosition(chartEditorSave.data.mainBoxPosition[0], chartEditorSave.data.mainBoxPosition[1]);
		if(chartEditorSave.data.infoBoxPosition != null && chartEditorSave.data.infoBoxPosition.length > 1)
			infoBox.setPosition(chartEditorSave.data.infoBoxPosition[0], chartEditorSave.data.infoBoxPosition[1]);

		upperBox = new PsychUIBox(40, 40, 330, 300, [Language.get('charting_file_text'), Language.get('charting_edit_text'), Language.get('charting_view_text')]);
		upperBox.scrollFactor.set();
		upperBox.isMinimized = true;
		upperBox.minimizeOnFocusLost = true;
		upperBox.canMove = false;
		upperBox.cameras = [camUI];
		upperBox.bg.visible = false;
		upperBox.bgFollowsSelectedTab = true; // 让背景板实时跟随下拉菜单选中的 tab
		add(upperBox);

		outputTxt = new FlxText(25, FlxG.height - 50, FlxG.width - 50, '', 20);
		outputTxt.setFormat(Paths.font(Language.get('uitab_font')), 20);
		outputTxt.borderSize = 2;
		outputTxt.borderStyle = OUTLINE_FAST;
		outputTxt.scrollFactor.set();
		outputTxt.cameras = [camUI];
		outputTxt.alpha = 0;
		add(outputTxt);

		updateJsonData();
		
		// TABS
		////// for main box
		addChartingTab();
		addDataTab();
		addEventsTab();
		addNoteTab();
		addSectionTab();
		addSongTab();

		createSearchBox();
		
		////// for upper box
		addFileTab();
		addEditTab();
		addViewTab();
		//

		// HaxeUI 顶部菜单栏替换原左上角下拉菜单（文件/编辑/视图）
		createHaxeUIMenuBar();
		upperBox.visible = false;
		upperBox.active = false;

		// 顶部条信息（FPS+内存峰值居中、版本右上角）+ 深浅色主题套用
		createTopBarInfo();
		applyTopBarTheme();

		loadMusic();
		reloadNotesDropdowns();
		if(!_shouldReset)
		{
			vocals.time = opponentVocals.time = FlxG.sound.music.time = Conductor.songPosition - Conductor.offset;
			if(FlxG.sound.music.time >= vocals.length)
				vocals.pause();
			if(FlxG.sound.music.time >= opponentVocals.length)
				opponentVocals.pause();
		}

		reloadNotes();
		updateGridVisibility();

		// CHARACTERS FOR THE DROP DOWNS
		var gameOverCharacters:Array<String> = loadFileList('characters/', 'data/characterList.txt');
		var characterList:Array<String> = gameOverCharacters.filter((name:String) -> (!name.endsWith('-dead') && !name.endsWith('-death')));
		playerDropDown.list = characterList;
		opponentDropDown.list = characterList;
		girlfriendDropDown.list = characterList;

		gameOverCharacters.insert(0, '');
		gameOverCharacters.sort(function(a:String, b:String)
		{
			if((a == '' || a.endsWith('-dead') || a.endsWith('-death')) && !(b == '' || b.endsWith('-dead') || b.endsWith('-death'))) return -1; //Prioritize "-dead" or "-death" characters
			return 0;
		});
		gameOverCharDropDown.list = gameOverCharacters;

		stageDropDown.list = loadFileList('stages/', 'data/stageList.txt');
		onChartLoaded();

		var tipText:FlxText = new FlxText(FlxG.width - 210, FlxG.height - 30, 200, (controls.mobileC ? Language.get('charting_forhelptextm') : Language.get('charting_forhelptextpc')), 20);
		tipText.cameras = [camUI];
		tipText.setFormat(Paths.font("unifont-18.0.01.otf"), 18, FlxColor.WHITE, RIGHT);
		tipText.borderColor = FlxColor.BLACK;
		tipText.scrollFactor.set();
		tipText.borderSize = 1;
		tipText.active = false;
		tipText.x = FlxG.width - tipText.width - 20;

		add(tipText);

		tipBg = new FlxSprite().makeGraphic(1, 1, FlxColor.BLACK);
		tipBg.cameras = [camUI];
		tipBg.scale.set(FlxG.width, FlxG.height);
		tipBg.updateHitbox();
		tipBg.scrollFactor.set();
		tipBg.visible = tipBg.active = false;
		tipBg.alpha = 0.6;
		add(tipBg);
		
		fullTipText = new FlxText(0, 0, FlxG.width - 200);
		fullTipText.setFormat(Paths.font("unifont-18.0.01.otf"), 24, FlxColor.WHITE, CENTER);
		fullTipText.cameras = [camUI];
		fullTipText.scrollFactor.set();
		fullTipText.visible = fullTipText.active = false;
		/*fullTipText.text = (controls.mobileC) ? [
			"Up/Down - Move Conductor's Time",
			"Left/Right - Change Sections",
			"Up/Down (On The Right) - Decrease/Increase Note Sustain Length",
			"Hold Y to Increase/Decrease move by 4x",
			"",
			"C - Preview Chart",
			"A - Playtest Chart",
			"X - Stop/Resume Song",
			"",
			"Hold H and touch to Select Note(s)",
			"Z - Hide Action TouchPad Buttons",
			"V/D - Zoom in/out",
			""
			#if FLX_PITCH
			,"G - Reset Song Playback Rate"
			#end
		].join('\n') : [
			"W/S/Mouse Wheel - Move Conductor's Time",
			"A/D - Change Sections",
			"Q/E - Decrease/Increase Note Sustain Length",
			"Hold Shift/Alt to Increase/Decrease move by 4x",
			"",
			"F12 - Preview Chart",
			"Enter - Playtest Chart",
			"Space - Stop/Resume song",
			"",
			"Alt + Click - Select Note(s)",
			"Shift + Click - Select/Unselect Note(s)",
			"Right Click - Selection Box",
			"",
			"R - Reset Section",
			"Shift + R - Go Back to the Start of the Song",
			"Z/X - Zoom in/out",
			"Left/Right - Change Snap",
			#if FLX_PITCH
			"Left Bracket / Right Bracket - Change Song Playback Rate", "ALT + Left Bracket / Right Bracket - Reset Song Playback Rate",
			#end
			"",
			"Ctrl + Z - Undo",
			"Ctrl + Y - Redo",
			"Ctrl + X - Cut Selected Notes",
			"Ctrl + C - Copy Selected Notes",
			"Ctrl + V - Paste Copied Notes",
			"Ctrl + A - Select all in current Section",
			"Ctrl + S - Quicksave",
		].join('\n');*/
		fullTipText.text = (controls.mobileC) 
    		? Language.get("charting_mobile_tips").split('\n').join('\n') 
    		: Language.get("charting_desktop_tips").split('\n').join('\n');
		fullTipText.screenCenter();
		add(fullTipText);
	// update() 中无条件引用 touchPad.*，所以桌面端也必须创建，仅隐藏即可。
	// 触控板必须拥有独立摄像头，否则按钮会跟随制谱器网格摄像头滚动/错位，
	// 并且触摸检测时会读取到其它状态残留的摄像头导致崩溃。
	addTouchPad('LEFT_FULL', 'CHART_EDITOR');
	addTouchPadCamera();
	touchPad.visible = controls.mobileC;

	super.create();

	// 初始化角色显示
	if(chartEditorSave.data.showCharacters == null) chartEditorSave.data.showCharacters = false;
	if(chartEditorSave.data.showCharacters) initCharacters();

		// 构建窗口缩放提示 UI（默认隐藏，仅在窗口明显缩放或需要重载时显示）
		buildResizePromptUI();
	}

	function initCharacters()
	{
		var stageData = StageData.dummy();

		// 创建对手角色（左侧）
		if(dad != null) remove(dad);
		dad = new Character(stageData.opponent[0], stageData.opponent[1], PlayState.SONG.player2);
		dad.cameras = [camChart];
		dad.updateHitbox();
		dad.visible = chartEditorSave.data.showCharacters;
		
		// 自定义对手角色位置（覆盖StageData，不影响全局）
		dad.x = -700;
		dad.y = 200;

		add(dad);

		// 创建玩家角色（右侧）
		if(boyfriend != null) remove(boyfriend);
		boyfriend = new Character(stageData.boyfriend[0], stageData.boyfriend[1], PlayState.SONG.player1, true);
		boyfriend.cameras = [camChart];
		boyfriend.updateHitbox();
		boyfriend.visible = chartEditorSave.data.showCharacters;
		
		// 自定义玩家角色位置（覆盖StageData，不影响全局）
		boyfriend.x = 1200;
		boyfriend.y = 200;

		add(boyfriend);

		charactersLoaded = true;
		
		// 设置相机缩放以获得更好的视觉效果
		camChart.zoom = 0.4;
		
		// 初始化角色透明度
		updateHeads(true);
	}

	function updateCharacters()
	{
		if(!charactersLoaded) return;

		var stageData = StageData.dummy();

		// 更新对手角色
		if(dad != null && dad.curCharacter != PlayState.SONG.player2)
		{
			remove(dad);
			dad = new Character(stageData.opponent[0], stageData.opponent[1], PlayState.SONG.player2);
			dad.cameras = [camChart];
			dad.updateHitbox();
			dad.visible = chartEditorSave.data.showCharacters;
			
			// 自定义对手角色位置（覆盖StageData，不影响全局）
			dad.x = -850;
			dad.y = 100;

			add(dad);
		}

		// 更新玩家角色
		if(boyfriend != null && boyfriend.curCharacter != PlayState.SONG.player1)
		{
			remove(boyfriend);
			boyfriend = new Character(stageData.boyfriend[0], stageData.boyfriend[1], PlayState.SONG.player1, true);
			boyfriend.cameras = [camChart];
			boyfriend.updateHitbox();
			boyfriend.visible = chartEditorSave.data.showCharacters;
			
			// 自定义玩家角色位置（覆盖StageData，不影响全局）
			boyfriend.x = 1500;
			boyfriend.y = 100;

			add(boyfriend);
		}
		
		// 更新角色透明度
		updateHeads(true);
	}

	// 播放角色的sing动画
	// LE LTS 双侧：isBf 决定取哪侧档位的 sing 方向映射（玩家=playerKeyCount-1、对手=keyCount-1）——
	// 全局 singAnimations 是"当前编辑侧"档位，跨两侧播放时对侧角色会用错档方向（"播放的不是箭头对应动画"）。
	public function playCharacterSing(char:Character, noteData:Int, ?isBf:Bool = true, ?forcePlay:Bool = false):Void
	{
		if(char == null || !char.visible) return;

		var dir:Int = Std.int(Math.abs(noteData));
		var animToPlay:String = singAnimations[Std.int(Math.abs(Math.min(singAnimations.length-1, dir)))];
		// 多键/双侧：按该侧档位从 extrakeys 映射方向动画（列 4+ 不再截断到 singRIGHT；4 键档结果与原生一致）
		var mania:Int = (isDualChart()) ? ((isBf ? dualPlayerKeyCount() : dualOpponentKeyCount()) - 1) : getSectionMania(-1);
		if (mania < 0) mania = 3;
		ExtraKeysHandler.ensure();
		if (ExtraKeysHandler.instance != null && ExtraKeysHandler.instance.data != null)
		{
			switch (ExtraKeysHandler.instance.singAnim(mania, dir))
			{
				case 'singLEFT': animToPlay = 'singLEFT';
				case 'singDOWN': animToPlay = 'singDOWN';
				case 'singUP': animToPlay = 'singUP';
				case 'singRIGHT': animToPlay = 'singRIGHT';
			}
		}
		if(char.animation.exists(animToPlay) || (char.isAnimateAtlas && char.atlas.anim.getByName(animToPlay) != null))
		{
			char.playAnim(animToPlay, true);
			char.holdTimer = 0;
		}
	}

	// Lil' Buddies 迷你角色唱歌动画
	// isBf: true=BF唱歌(lilBf), false=对手唱歌(lilOpp)
	// direction: 列索引（多键时 0..keyCount-1）。Lil 素材仅 4 方向动画，
	// 多键列按 extrakeys 的 sing 方向（singLEFT/DOWN/UP/RIGHT）映射回 0..3，
	// 修复 5K+ 时多出轨道（动画名 '4'..'8' 不存在）不触发播放的问题。
	private function playLilSing(isBf:Bool, direction:Int):Void
	{
		if(chartEditorSave == null || !chartEditorSave.data.showLilBuddies) return;
		var target:FlxSprite = isBf ? lilBf : lilOpp;
		if(target == null || !target.visible) return;
		var dir:Int = Std.int(Math.abs(direction)) % 4;
		ExtraKeysHandler.ensure();
		// 该侧档位（双侧：玩家/对手各自档；非双侧：SONG.mania 档）——sing 方向与着色共用
		var mania:Int = (isDualChart()) ? ((isBf ? dualPlayerKeyCount() : dualOpponentKeyCount()) - 1) : getSectionMania(-1);
		if (mania < 0) mania = 3;
		if (ExtraKeysHandler.instance != null && ExtraKeysHandler.instance.data != null)
		{
			switch (ExtraKeysHandler.instance.singAnim(mania, direction))
			{
				case 'singLEFT': dir = 0;
				case 'singDOWN': dir = 1;
				case 'singUP': dir = 2;
				case 'singRIGHT': dir = 3;
			}
		}
		var animName:String = "" + dir;
		target.animation.play(animName, true);
		// 按该侧档位染上箭头主色（Lil 主体黑白，染色后显示对应键的颜色）。
		// 不能用全局 Note.styleIndex——双侧谱面无 mania 字段时它会回退 4 键档，对手多键列（侧内列 ≥ 4）错色。
		var style:Int = (ExtraKeysHandler.instance != null) ? ExtraKeysHandler.instance.globalIndex(mania, direction) : (direction % 4);
		var arr:Array<FlxColor> = ClientPrefs.data.arrowRGB[style];
		if (arr != null && arr.length > 0) target.color = arr[0];
		else target.color = 0xFFFFFFFF;
		// 记录当前拍号，下一拍自动回 idle（与主角色逻辑对齐）
		var curBeatNow:Int = Math.floor(Conductor.getStep(Conductor.songPosition) / 4);
		if(isBf) lilBfSingFinishedBeat = curBeatNow;
		else lilOppSingFinishedBeat = curBeatNow;
	}

	// 处理idle动画的播放
	// 每拍都检查，使用holdTimer和singDuration来决定何时从sing回到idle
	// 必须在sing Duration完成后的下一拍才播放idle
	// 返回类型：Null<Int> - 返回sing完成的beat，或null表示idle已播放
	private function handleIdleAnimationLoop(char:Character, currentBeat:Int, needIdleReplay:Bool, ?singFinishedBeat:Null<Int>):Null<Int>
	{
		if(char == null || !char.visible) return singFinishedBeat;

		var animName:String = char.getAnimationName();

		// 检查是否在播放sing动画
		if(animName.startsWith('sing'))
		{
			// 制谱器模式下：总是允许角色回到idle动画
			// keepSingAnimation只在实际游戏中针对按键持续按下使用
			var timeThreshold:Float = Conductor.stepCrochet * (0.0011 #if FLX_PITCH / FlxG.sound.music.pitch #end) * char.singDuration;
			if(char.holdTimer > timeThreshold)
			{
				// holdTimer超过阈值，记录当前beat为sing完成的beat
				return currentBeat; // 返回当前beat，标记sing在此beat完成
			}
			// 还在保持sing动画，不播放idle
			return singFinishedBeat; // 保持之前的sing完成记录
		}

		// 当前不在sing动画中，检查是否需要在下一拍播放idle
		if(singFinishedBeat != null && currentBeat > singFinishedBeat)
		{
			// sing已完成，且是下一拍，播放idle/dance动画
			char.dance();
			return null; // idle已播放，清除sing完成标记
		}

		// 每拍都尝试播放idle动画（正常idle循环）
		if(currentBeat != lastBeat)
		{
			// 播放idle/dance动画
			char.dance();
			return singFinishedBeat; // 保持sing完成记录（如果存在）
		}

		return singFinishedBeat;
	}

	// 更新角色的holdTimer和动画状态（用于EditorPlayState中手动更新角色）
	public function updateCharacter(elapsed:Float):Void
	{
		// 临时保存原来的keepSingAnimation值
		var originalKeepSingAnimation:Bool = ClientPrefs.data.keepSingAnimation;
		// 在制谱器中临时禁用keepSingAnimation，让角色正常回到idle
		ClientPrefs.data.keepSingAnimation = false;
		
		if(dad != null && dad.visible) dad.update(elapsed);
		if(boyfriend != null && boyfriend.visible) boyfriend.update(elapsed);
		
		// 恢复原来的keepSingAnimation值
		ClientPrefs.data.keepSingAnimation = originalKeepSingAnimation;
	}

	// 获取角色的动画偏移（用于显示和调试）
	public function getCharacterOffset(char:Character, animName:String):{x:Float, y:Float}
	{
		if(char == null || !char.animOffsets.exists(animName)) return {x: 0, y: 0};
		var offset:Array<Dynamic> = char.animOffsets.get(animName);
		return {x: offset[0], y: offset[1]};
	}

	var gridColors:Array<FlxColor>;
	var gridColorsOther:Array<FlxColor>;
	function changeTheme(changeTo:ChartingTheme, ?doSave:Bool = true)
	{
		var oldTheme:ChartingTheme = theme;
		theme = changeTo;
		chartEditorSave.data.theme = changeTo;
		if(doSave) chartEditorSave.flush();

		switch(theme)
		{
			case LIGHT:
				bg.color = 0xFFA0A0A0;
				gridColors = [0xFFDFDFDF, 0xFFBFBFBF];
				gridColorsOther = [0xFF5F5F5F, 0xFF4A4A4A];
			case DARK:
				bg.color = 0xFF222222;
				gridColors = [0xFF3F3F3F, 0xFF2F2F2F];
				gridColorsOther = [0xFF1F1F1F, 0xFF111111];
			case VSLICE:
				bg.color = 0xFF673AB7;
				gridColors = [0xFFD0D0D0, 0xFFAFAFAF];
				gridColorsOther = [0xFF595959, 0xFF464646];
			case CUSTOM:
				bg.color = CoolUtil.colorFromString(chartEditorSave.data.customBgColor);
				gridColors = [CoolUtil.colorFromString(chartEditorSave.data.customGridColors[0]), CoolUtil.colorFromString(chartEditorSave.data.customGridColors[1])];
				gridColorsOther = [CoolUtil.colorFromString(chartEditorSave.data.customNextGridColors[0]), CoolUtil.colorFromString(chartEditorSave.data.customNextGridColors[1])];
			default:
				bg.color = 0xFF303030;
				gridColors = [0xFFDFDFDF, 0xFFBFBFBF];
				gridColorsOther = [0xFF5F5F5F, 0xFF4A4A4A];
		}

		if(theme != oldTheme || theme == CUSTOM)
		{
			if(opponentGridBg != null)
			{
				opponentGridBg.loadGrid(gridColors[0], gridColors[1]);
				opponentGridBg.vortexLineEnabled = vortexEnabled;
				opponentGridBg.vortexLineSpace = GRID_SIZE * 4 * curZoom;
				prevOpponentGridBg.loadGrid(gridColorsOther[0], gridColorsOther[1]);
				prevOpponentGridBg.vortexLineEnabled = vortexEnabled;
				prevOpponentGridBg.vortexLineSpace = GRID_SIZE * 4 * curZoom;
				nextOpponentGridBg.loadGrid(gridColorsOther[0], gridColorsOther[1]);
				nextOpponentGridBg.vortexLineEnabled = vortexEnabled;
				nextOpponentGridBg.vortexLineSpace = GRID_SIZE * 4 * curZoom;
			}
			if(SHOW_EVENT_COLUMN && eventGridBg != null)
			{
				eventGridBg.loadGrid(gridColors[0], gridColors[1]);
				eventGridBg.vortexLineEnabled = vortexEnabled;
				eventGridBg.vortexLineSpace = GRID_SIZE * 4 * curZoom;
				prevEventGridBg.loadGrid(gridColorsOther[0], gridColorsOther[1]);
				prevEventGridBg.vortexLineEnabled = vortexEnabled;
				prevEventGridBg.vortexLineSpace = GRID_SIZE * 4 * curZoom;
				nextEventGridBg.loadGrid(gridColorsOther[0], gridColorsOther[1]);
				nextEventGridBg.vortexLineEnabled = vortexEnabled;
				nextEventGridBg.vortexLineSpace = GRID_SIZE * 4 * curZoom;
			}
			if(playerGridBg != null)
			{
				playerGridBg.loadGrid(gridColors[0], gridColors[1]);
				playerGridBg.vortexLineEnabled = vortexEnabled;
				playerGridBg.vortexLineSpace = GRID_SIZE * 4 * curZoom;
				prevPlayerGridBg.loadGrid(gridColorsOther[0], gridColorsOther[1]);
				prevPlayerGridBg.vortexLineEnabled = vortexEnabled;
				prevPlayerGridBg.vortexLineSpace = GRID_SIZE * 4 * curZoom;
				nextPlayerGridBg.loadGrid(gridColorsOther[0], gridColorsOther[1]);
				nextPlayerGridBg.vortexLineEnabled = vortexEnabled;
				nextPlayerGridBg.vortexLineSpace = GRID_SIZE * 4 * curZoom;
			}
		}

		// 制谱器内切换主题时，若顶部条设置为"默认（跟随制谱器主题）"，则同步菜单条深浅色
		applyTopBarTheme();
	}

	function openNewChart()
	{
		var song:SwagSong = {
			song: 'Test',
			notes: [],
			events: [],
			bpm: 150,
			needsVoices: true,
			speed: 1,
			offset: 0,

			player1: 'bf',
			player2: 'dad',
			gfVersion: 'gf',
			stage: 'stage',
			specialInst: "", // 添加默认值
			specialVocal: "", // 添加默认值
			specialEvents: "", // 添加默认值
			format: 'psych_v1'
		};
		Song.chartPath = null;
		loadChart(song);
	}

	function prepareReload()
	{
		updateJsonData();
		loadMusic();
		reloadNotes();
		onChartLoaded();
		updateHeads(true);
		
		autoSaveTime = 0;
		Conductor.songPosition = 0;
		if(FlxG.sound.music != null) FlxG.sound.music.time = 0;
		curSec = 0;
		loadSection();
		forceDataUpdate = true;
	}

	function onChartLoaded()
	{
		if(PlayState.SONG == null) return;

		// SONG TAB
		songNameInputText.text = PlayState.SONG.song;
		allowVocalsCheckBox.checked = (PlayState.SONG.needsVoices != false); //If the song for some reason does not have this value, it will be set to true

		bpmStepper.value = PlayState.SONG.bpm;
		scrollSpeedStepper.value = PlayState.SONG.speed;
		audioOffsetStepper.value = Reflect.hasField(PlayState.SONG, 'offset') ? PlayState.SONG.offset : 0;
		Conductor.offset = audioOffsetStepper.value;

		if (maniaStepper != null)
			maniaStepper.value = (PlayState.SONG.playerKeyCount != null) ? Std.int(PlayState.SONG.playerKeyCount)
				: ((PlayState.SONG.mania != null) ? Std.int(PlayState.SONG.mania) + 1 : 4);
		if (opponentKeyStepper != null)
			opponentKeyStepper.value = (PlayState.SONG.keyCount != null && PlayState.SONG.keyCount >= 1) ? Std.int(PlayState.SONG.keyCount) : 4;
		// 两个键数设置项始终显示（Psych/EK 谱面两侧默认同值）；双侧模式显示编辑侧切换按钮
		if (editPlayerBtn != null && editOpponentBtn != null)
		{
			editPlayerBtn.visible = isDualChart();
			editOpponentBtn.visible = isDualChart();
			if (opponentKeyStepperText != null) opponentKeyStepperText.visible = true;
			if (opponentKeyStepper != null) opponentKeyStepper.visible = true;
			if (!isDualChart()) ChartingState.editorSide = 0;
			refreshEditSideButtons();
		}

		specialInstInputText.text = PlayState.SONG.specialInst != null ? PlayState.SONG.specialInst : '';
		specialVocalInputText.text = PlayState.SONG.specialVocal != null ? PlayState.SONG.specialVocal : '';
		specialEventsInputText.text = PlayState.SONG.specialEvents != null ? PlayState.SONG.specialEvents : '';

		playerDropDown.selectedLabel = PlayState.SONG.player1;
		opponentDropDown.selectedLabel = PlayState.SONG.player2;
		girlfriendDropDown.selectedLabel = PlayState.SONG.gfVersion;
		stageDropDown.selectedLabel = PlayState.SONG.stage;
		StageData.loadDirectory(PlayState.SONG);

		// DATA TAB
		gameOverCharDropDown.selectedLabel = PlayState.SONG.gameOverChar;
		gameOverSndInputText.text = PlayState.SONG.gameOverSound;
		gameOverLoopInputText.text = PlayState.SONG.gameOverLoop;
		gameOverRetryInputText.text = PlayState.SONG.gameOverEnd;

		noRGBCheckBox.checked = (PlayState.SONG.disableNoteRGB == true);

		noteTextureInputText.text = PlayState.SONG.arrowSkin;
		noteSplashesInputText.text = PlayState.SONG.splashSkin;
		holdCoverTextureInputText.text = PlayState.SONG.holdCoverSkin;
	}
	
	var noteSelectionSine:Float = 0;
	var selectedNotes:Array<MetaNote> = [];
	var ignoreClickForThisFrame:Bool = false;
	var outputAlpha:Float = 0;
	var songFinished:Bool = false;

	// HaxeUI 顶部菜单栏（文件/编辑/视图）相关
	var haxeMenuBar:MenuBar;
	var haxeMenuOpen:Bool = false;
	var haxeMenuIgnoreFrames:Int = 0;
	var haxeMenuBarHeight:Float = 30;
	// HaxeUI 菜单项 ↔ 原 PsychUIButton 映射，用于同步动态文本（如视图菜单的前三项、便捷制谱器开关）
	var haxeMenuItemMappings:Array<{item:MenuItem, btn:PsychUIButton}> = [];
	// 顶部菜单条按钮 ↔ 菜单映射（顺序一致），用于切换菜单时精确控制按钮高亮
	var haxeMenuBarMenus:Array<Menu> = [];
	var haxeMenuBarButtons:Array<Button> = [];
	var haxeMenuOpenMenu:Menu = null; // 当前打开的下拉菜单（用于按钮高亮判断，比 selected 更可靠）

	// 顶部条信息：FPS+内存峰值（水平居中一行）与版本（右上角）
	// 用 FlxText 叠加在 HaxeUI 菜单条之上渲染：不用 HaxeUI Label 是因为全宽 Label 会拦截菜单按钮的点击事件
	var topBarFpsMemText:FlxText;
	var topBarVersionText:FlxText;
	var haxeMenuStyleLight:Bool = true; // 当前 HaxeUI 菜单条是否为浅色（下拉菜单打开时套用对应配色）
	// 制谱器独立 FPS 计数（不依赖 Main.fpsVar，后者在 visible=false 时停止刷新）
	var _topBarFrameCount:Int = 0;
	var _topBarFrameTime:Float = 0;
	var _topBarFPS:Float = 0;
	var _topBarPeakMem:Float = 0; // 峰值内存（字节），自行跟踪
	var _topBarLastMemQueryTime:Float = 0; // 上次查询系统内存的时间戳（用于节流）
	var _topBarLastMemBytes:Float = 0; // 最近一次成功查询到的内存（字节）

	var fileDialog:FileDialogHandler = new FileDialogHandler();
	var lastFocus:PsychUIInputText;

	var autoSaveTime:Float = 0;
	var autoSaveCap:Int = 2; //in minutes
	var backupLimit:Int = 10;
	var chartDataDirty:Bool = false;

	var lastBeatHit:Int = 0;
	var songBeatNoOffset:Int = 0; // 不受noteOffset影响的纯粹歌曲节拍
	override function update(elapsed:Float)
	{
		if(!fileDialog.completed)
		{
			lastFocus = PsychUIInputText.focusOn;
			return;
		}

		// HaxeUI 菜单栏点击穿透保护：点击菜单栏区域、菜单打开或刚关闭时忽略制谱器的鼠标操作。
		// 必须用 HaxeUI 自己的坐标（MouseHelper.currentWorldY），它与菜单栏的命中测试一致；
		// 不能用 screenY（屏幕像素坐标，窗口缩放后会漏）或 FlxG.mouse.y（制谱器默认相机纵向滚动，会偏移）。
		if(FlxG.mouse.justPressed && (haxeMenuOpen || haxeMenuIgnoreFrames > 0 || MouseHelper.currentWorldY <= haxeMenuBarHeight))
			ignoreClickForThisFrame = true;
		if(haxeMenuIgnoreFrames > 0) haxeMenuIgnoreFrames--;

		// 同步 HaxeUI 菜单项文本与底层动态按钮文本（如视图菜单前三项、便捷制谱器开关）
		syncHaxeMenuTexts();

		// 顶部条 FPS + 内存峰值实时刷新
		updateTopBarInfo(elapsed);

		// 库版频谱后台预渲染：空闲帧里把已显示目标的"下一 section"提前画到后台缓冲
		// 这样 section 切换时前台可直接换显后台缓冲，避免切换瞬间先看到旧图的闪烁
		if(waveformStyle == LIBRARY)
		{
			var targetOrder:Array<WaveformTarget> = [INST, PLAYER, OPPONENT];
			// 每帧最多预渲染一个目标，分摊开销
			for(c in 0...targetOrder.length)
			{
				var i:Int = (waveformLibPreRenderCursor + c) % targetOrder.length;
				if(waveformTargets.indexOf(targetOrder[i]) == -1) continue;
				var src:Int = waveformLibCacheSection[i];
				if(src < 0 || src >= cachedSectionTimes.length - 1) continue;
				var nxt:Int = src + 1;
				if(waveformLibBackSection[i] == nxt && waveformLibBackSprites[i] != null) continue;
				waveformLibBackSprites[i].autoUpdateBitmap = false; // 后台缓冲手动重绘，避免 setter 标记 dirty 拖到换显时重复重绘
				if(paintLibWaveform(waveformLibBackSprites[i], targetOrder[i], nxt, waveformLibBackLoadedBuffers))
				{
					waveformLibBackSprites[i].generateWaveformBitmap();
					waveformLibBackSprites[i].dirty = true;
					waveformLibBackSection[i] = nxt;
				}
				waveformLibPreRenderCursor = (i + 1) % targetOrder.length;
				break;
			}
		}

		for (num => key in keysArray)
			_keysPressedBuffer[num] = FlxG.keys.checkStatus(key, JUST_PRESSED);

		if(autoSaveCap > 0)
		{
			autoSaveTime += elapsed / 60.0;
			//trace(autoSaveTime);
			//#if debug if(FlxG.keys.justPressed.J) autoSaveTime += 20/60.0; #end
			if(autoSaveTime >= autoSaveCap #if debug || FlxG.keys.justPressed.NUMPADMULTIPLY #end)
			{
				autoSaveTime = 0;
				if(!chartDataDirty)
				{
					#if debug trace('[AutoSave] Skipped: no changes since last save.'); #end
				}
				else
				{
					FlxTween.cancelTweensOf(autoSaveIcon);
					autoSaveIcon.alpha = 0;
					updateChartData();
					var chartName:String = 'unknown';
					if(Song.chartPath != null)
					{
						chartName = Song.chartPath.replace('\\', '/');
						chartName = chartName.substring(chartName.lastIndexOf('/')+1, chartName.lastIndexOf('.'));
					}
					chartName += DateTools.format(Date.now(), '_%Y-%m-%d_%H-%M-%S');
					var songCopy:SwagSong = Reflect.copy(PlayState.SONG);
					Reflect.setField(songCopy, '__original_path', Song.chartPath);
					var dataToSave:String = haxe.Json.stringify(songCopy);
					//trace(chartName, dataToSave);
					if(!FileSystem.isDirectory('backups')) FileSystem.createDirectory('backups');
					File.saveContent('backups/$chartName.$BACKUP_EXT', dataToSave);

					if(backupLimit > 0)
					{
						var files:Array<String> = Paths.readDirectory('backups/').filter((file:String) -> file.endsWith('.$BACKUP_EXT'));
						if(files.length > backupLimit)
						{
							var incorrect:Array<String> = [];
							var map:Map<String, Float> = [];
							for(file in files)
							{
								var split:Array<String> = file.split('_');
								if(split.length > 2) //is properly formatted
								{
									try
									{
										var timeStr:String = split[split.length-1].replace('-', ':');
										timeStr = timeStr.substr(0, timeStr.indexOf('.'));

										var fileJoin:String = split[split.length-2] + ' ' + timeStr;
										var date:Date = Date.fromString(fileJoin);
										//trace(fileJoin, date.getTime());
										map.set(file, date.getTime());
									}
									catch(e:Exception)
									{
										incorrect.push(file);
									}
								}
								else incorrect.push(file);
							}

							if(incorrect.length > 0) files = files.filter((file:String) -> !incorrect.contains(file));
							files.sort(function(a:String, b:String) return map.get(a) > map.get(b) ? 1 : -1);

							while(files.length > backupLimit)
							{
								var file = files.shift();
								//trace('removed $file');
								try
								{
									FileSystem.deleteFile('backups/$file');
								}
								catch(e:Exception) {}
							}
						}
					}

					chartDataDirty = false;
					FlxTween.tween(autoSaveIcon, {alpha: 1}, 0.5, {onComplete: function(_)
						FlxTween.tween(autoSaveIcon, {alpha: 0}, 0.5, {startDelay: 2})
					});
				}
			}
		}

		ClientPrefs.toggleVolumeKeys(PsychUIInputText.focusOn == null);

		var lastTime:Float = Conductor.songPosition;
		outputAlpha = Math.max(0, outputAlpha - elapsed);
		var holdingAlt:Bool = touchPad.buttonG.justPressed || FlxG.keys.pressed.ALT;
		if(FlxG.sound.music != null)
		{
			if(PsychUIInputText.focusOn == null) //If not typing anything
			{
				if(touchPad.buttonC.justPressed || FlxG.keys.justPressed.F12)
				{
					// 临时禁用 keepSingAnimation，使角色在制谱器中正常回到 idle
					var originalKeepSingAnimation:Bool = ClientPrefs.data.keepSingAnimation;
					ClientPrefs.data.keepSingAnimation = false;
					
					super.update(elapsed);
					
					// 恢复原值
					ClientPrefs.data.keepSingAnimation = originalKeepSingAnimation;
					
					openEditorPlayState();
					lastFocus = PsychUIInputText.focusOn;
					return;
				}
				else if(touchPad.buttonF.justPressed || FlxG.keys.justPressed.F1)
				{
					if (controls.mobileC)
					{
						touchPad.forEachAlive(function(button:TouchButton){
							if(button.tag != 'F')
								button.visible = !button.visible;
						});
					}
					var vis:Bool = !fullTipText.visible;
					tipBg.visible = tipBg.active = fullTipText.visible = fullTipText.active = vis;
				}

				if (touchPad.buttonZ.justPressed)
				{
					if (controls.mobileC)
					{
						touchPad.forEachAlive(function(button:TouchButton){
							if(button.tag != 'Z' && button.tag != 'LEFT' && button.tag != 'RIGHT' && button.tag != 'UP' && button.tag != 'DOWN')
								touchPad.buttonUp2.visible = touchPad.buttonDown2.visible = button.visible = !button.visible;
						});
					}
				}

				if (touchPad.buttonG.justPressed)
				{
					if(playbackRate != 1)
					{
						playbackRate = 1;
						setPitch();
					}
					playbackSlider.value = playbackRate;
				}

				var goingBack:Bool = false;
				if(FlxG.keys.pressed.RBRACKET || (FlxG.keys.pressed.LBRACKET && (goingBack = true)))
				{
					if(holdingAlt)
					{
						if(playbackRate != 1)
						{
							playbackRate = 1;
							setPitch();
						}
					}
					else
					{
						playbackRate = FlxMath.bound(playbackRate + elapsed * (!goingBack ? 1 : -1), playbackSlider.min, playbackSlider.max);
						setPitch();
					}
					playbackSlider.value = playbackRate;
				}

				if(vortexEnabled && _keysPressedBuffer.contains(true))
				{
					var typeSelected:String = noteTypes[noteTypeDropDown.selectedIndex];
					if(typeSelected != null)
					{
						typeSelected = typeSelected.trim();
						if(typeSelected.length < 1) typeSelected = null;
					}

					// 在“步空间”量化播放头，再转回 ramp 感知的毫秒（与网格一致）
					var quantSteps:Float = 16 / curQuant;
					var curStepF:Float = Conductor.getStep(Conductor.songPosition);
					curStepF = Math.floor(curStepF / quantSteps) * quantSteps;
					var strumTime:Float = Conductor.getTimeFromStep(curStepF);

					trace('Vortex editor press at time: $strumTime');
					var deletedNotes:Array<MetaNote> = [];
					var addedNotes:Array<MetaNote> = [];
					for (num => press in _keysPressedBuffer)
					{
						if(!press) continue;

						// Try to find a note to delete first
						var didDelete:Bool = false;
						for (note in curRenderedNotes)
						{
							if(note == null || note.isEvent) continue;

							if(note.songData[1] == num && Math.abs(strumTime - note.strumTime) < 1)
							{
								deletedNotes.push(note);
								didDelete = true;
								break;
							}
						}

						if(didDelete) continue;

						// If no notes were found, add a new in its place
						var didAdd:Bool = false;
						var noteSetupData:Array<Dynamic> = [strumTime, num, 0];
						if(typeSelected != null) noteSetupData.push(typeSelected);
	
						var noteAdded:MetaNote = createNote(noteSetupData);
						for (num in sectionFirstNoteID...notes.length)
						{
							var note = notes[num];
							if(note.strumTime >= strumTime)
							{
								notes.insert(num, noteAdded);
								didAdd = true;
								break;
							}
						}
						if(!didAdd) notes.push(noteAdded);
						addedNotes.push(noteAdded);
					}

					if(deletedNotes.length > 0)
					{
						var wasSelected:Bool = false;
						for (note in deletedNotes)
						{
							if(selectedNotes.contains(note))
							{
								selectedNotes.remove(note);
								wasSelected = true;
							}
							notes.remove(note);
						}
						if(wasSelected) onSelectNote();
						addUndoAction(DELETE_NOTE, {notes: deletedNotes});
					}
					if(addedNotes.length > 0)
						addUndoAction(ADD_NOTE, {notes: addedNotes});

					softReloadNotes(true);
				}
				else if(touchPad.buttonLeft.justPressed || FlxG.keys.justPressed.A != touchPad.buttonRight.justPressed || FlxG.keys.justPressed.D && !holdingAlt)
				{
					if(FlxG.sound.music.playing)
						setSongPlaying(false);

					var shiftAdd:Int = (touchPad.buttonY.pressed || FlxG.keys.pressed.SHIFT ? 4 : 1);

					if(touchPad.buttonLeft.justPressed || FlxG.keys.justPressed.A)
					{
						if(curSec - shiftAdd < 0) shiftAdd = curSec;

						if(shiftAdd > 0)
						{
							loadSection(curSec - shiftAdd);
							Conductor.songPosition = FlxG.sound.music.time = cachedSectionTimes[curSec] - Conductor.offset + 0.000001;
						}
					}
					else if(touchPad.buttonRight.justPressed || FlxG.keys.justPressed.D)
					{
						if(curSec + shiftAdd >= PlayState.SONG.notes.length) shiftAdd = PlayState.SONG.notes.length - curSec - 1;
						
						if(shiftAdd > 0)
						{
							loadSection(curSec + shiftAdd);
							Conductor.songPosition = FlxG.sound.music.time = cachedSectionTimes[curSec] - Conductor.offset + 0.000001;
						}
					}
				}
				else if(FlxG.keys.justPressed.HOME)
				{
					setSongPlaying(false);
					Conductor.songPosition = FlxG.sound.music.time = 0;
					loadSection(0);
				}
				else if(FlxG.keys.justPressed.END)
				{
					setSongPlaying(false);
					Conductor.songPosition = FlxG.sound.music.time = FlxG.sound.music.length - 1;
					loadSection(PlayState.SONG.notes.length - 1);
				}
				else if(FlxG.keys.justPressed.R)
				{
					var timeToGoBack:Float = 0;
					if(!FlxG.keys.pressed.SHIFT) timeToGoBack = cachedSectionTimes[curSec] + (curSec > 0 ? 0.000001 : 0);
					else loadSection(0);
					Conductor.songPosition = FlxG.sound.music.time = vocals.time = opponentVocals.time = timeToGoBack;
				}
				else if(touchPad.buttonUp.pressed || FlxG.keys.pressed.W != touchPad.buttonDown.pressed || FlxG.keys.pressed.S || FlxG.mouse.wheel != 0)
				{
					if(FlxG.sound.music.playing)
						setSongPlaying(false);

					if(mouseSnapCheckBox.checked && FlxG.mouse.wheel != 0)
					{
						var snap:Float = Conductor.stepCrochet / (curQuant/16) / curZoom;
						var timeAdd:Float = (touchPad.buttonY.pressed || FlxG.keys.pressed.SHIFT ? 4 : 1) / (holdingAlt ? 4 : 1) * -FlxG.mouse.wheel * snap;
						var time:Float = Math.round((FlxG.sound.music.time + timeAdd) / snap) * snap;
						if(time > 0) time += 0.000001; //goes at the start of a section more properly
						FlxG.sound.music.time = time;
					}
					else
					{
						var speedMult:Float = (touchPad.buttonY.pressed || FlxG.keys.pressed.SHIFT ? 4 : 1) * (FlxG.mouse.wheel != 0 ? 4 : 1) / (holdingAlt ? 4 : 1);
						if(touchPad.buttonUp.pressed || FlxG.keys.pressed.W || FlxG.mouse.wheel > 0)
							FlxG.sound.music.time -= Conductor.crochet * speedMult * 1.5 * elapsed / curZoom;
						else if(touchPad.buttonDown.pressed || FlxG.keys.pressed.S || FlxG.mouse.wheel < 0)
							FlxG.sound.music.time += Conductor.crochet * speedMult * 1.5 * elapsed / curZoom;
					}

					FlxG.sound.music.time = FlxMath.bound(FlxG.sound.music.time, 0, FlxG.sound.music.length - 1);
					if(FlxG.sound.music.playing) setSongPlaying(!FlxG.sound.music.playing);
				}
				else if(touchPad.buttonX.justPressed || FlxG.keys.justPressed.SPACE)
				{
					setSongPlaying(!FlxG.sound.music.playing);
				}
			}

			if(!songFinished) Conductor.songPosition = FlxMath.bound(FlxG.sound.music.time + Conductor.offset, 0, FlxG.sound.music.length - 1);
			Conductor.bpm = Conductor.getBPMFromSeconds(Conductor.songPosition).bpm;
			updateScrollY();
		}

		// 角色拖动逻辑
		// 兼容 FlxAnimate 图集角色：其本体 Character 没有帧尺寸，点击检测需针对内部的 atlas 子精灵
		var charOverlapsMouse = function(char:Character):Bool
		{
			if(char == null || !char.visible) return false;
			#if flxanimate
			if(char.isAnimateAtlas && char.atlas != null) return FlxG.mouse.overlaps(char.atlas, camChart);
			#end
			return FlxG.mouse.overlaps(char, camChart);
		};

		if(chartEditorSave.data.allowDragCharacters && PsychUIInputText.focusOn == null && !ignoreClickForThisFrame)
		{
			// 检测鼠标左键按下
			if(FlxG.mouse.justPressed)
			{
				// 检查是否点击到角色
				if(charOverlapsMouse(dad))
				{
					isDraggingCharacter = true;
					draggedCharacter = dad;
					dragOffsetX = FlxG.mouse.getWorldPosition(camChart).x - dad.x;
					dragOffsetY = FlxG.mouse.getWorldPosition(camChart).y - dad.y;
				}
				else if(charOverlapsMouse(boyfriend))
				{
					isDraggingCharacter = true;
					draggedCharacter = boyfriend;
					dragOffsetX = FlxG.mouse.getWorldPosition(camChart).x - boyfriend.x;
					dragOffsetY = FlxG.mouse.getWorldPosition(camChart).y - boyfriend.y;
				}
			}

			// 拖动角色
			if(isDraggingCharacter && draggedCharacter != null)
			{
				var mousePos = FlxG.mouse.getWorldPosition(camChart);
				var newX = mousePos.x - dragOffsetX;
				var newY = mousePos.y - dragOffsetY;

				// 移除范围限制，允许自由拖拽角色
				draggedCharacter.x = newX;
				draggedCharacter.y = newY;
			}

			// 检测鼠标释放
			if(FlxG.mouse.justReleased)
			{
				isDraggingCharacter = false;
				draggedCharacter = null;
			}
		}

		// 临时禁用 keepSingAnimation，使角色在制谱器中正常回到 idle
		var originalKeepSingAnimation:Bool = ClientPrefs.data.keepSingAnimation;
		ClientPrefs.data.keepSingAnimation = false;
		
		super.update(elapsed);
		
		// 恢复原值
		ClientPrefs.data.keepSingAnimation = originalKeepSingAnimation;

		if(songFinished)
		{
			onSongComplete();
			lastTime = FlxG.sound.music.time;
			songFinished = false;
		}
		else if(FlxG.sound.music != null)
		{
			if(FlxG.sound.music.time >= vocals.length)
				vocals.pause();
			if(FlxG.sound.music.time >= opponentVocals.length)
				opponentVocals.pause();

			while(curSec > 0 && Conductor.songPosition < cachedSectionTimes[curSec])
				loadSection(curSec - 1);
			while(curSec < cachedSectionTimes.length - 1 && Conductor.songPosition >= cachedSectionTimes[curSec + 1])
				loadSection(curSec + 1);
		}

		if(PsychUIInputText.focusOn == null && lastFocus == null)
		{
			var doCut:Bool = false;
			var canContinue:Bool = true;
			if(touchPad.buttonA.justPressed || FlxG.keys.justPressed.ENTER)
			{
				goToPlayState();
				return;
			}
			else if(FlxG.keys.pressed.CONTROL && !isMovingNotes && (FlxG.keys.justPressed.Z || FlxG.keys.justPressed.Y || FlxG.keys.justPressed.X ||
				FlxG.keys.justPressed.C || FlxG.keys.justPressed.V || FlxG.keys.justPressed.A || FlxG.keys.justPressed.S))
			{
				canContinue = false;
				if(FlxG.keys.justPressed.Z)
					undo();
				else if(FlxG.keys.justPressed.Y)
					redo();
				else if((doCut = FlxG.keys.justPressed.X) || FlxG.keys.justPressed.C) // Cut (Ctrl + X) and Copy (Ctrl + C)
				{
					if(selectedNotes.length > 0)
					{
						copiedNotes = [];
						copiedEvents = [];
						var pushedNotes:Array<Array<Dynamic>> = [];

						for (note in selectedNotes)
						{
							if(note == null) continue;

							var copied:Array<Dynamic> = makeNoteDataCopy(note.songData, note.isEvent);
							pushedNotes.push(copied);
							if(note.isEvent) copiedEvents.push(copied);
							else copiedNotes.push(copied);
						}
						pushedNotes.sort((a:Array<Dynamic>, b:Array<Dynamic>) -> FlxSort.byValues(FlxSort.ASCENDING, a[0], b[0]));
						
						var minTime:Float = pushedNotes[0][0];
						for (note in pushedNotes)
							note[0] -= minTime;
					}
				}
				else if(FlxG.keys.justPressed.V) // Paste (Ctrl + V)
				{
					if(copiedNotes.length > 0 || copiedEvents.length > 0)
					{
						selectionBox.visible = false;
						stopMovingNotes();
						resetSelectedNotes();
						selectedNotes = pasteCopiedNotesToSection();
						selectedNotes.sort(PlayState.sortByTime);

						var didFind:Bool = false;
						var minNoteData:Float = Math.POSITIVE_INFINITY;
						for (note in selectedNotes)
						{
							if(note == null || note.isEvent) continue;

							if(minNoteData > note.songData[1]) minNoteData = note.songData[1];
							didFind = true;
						}
						if(!didFind) minNoteData = 0;
						
						var pushedNotes:Array<MetaNote> = [];
						var pushedEvents:Array<EventMetaNote> = [];
						for (note in selectedNotes)
						{
							if(note == null) continue;

							if(!note.isEvent)
							{
								note.changeNoteData(Std.int(note.songData[1] - minNoteData));
								pushedNotes.push(note);
							}
							else pushedEvents.push(cast (note, EventMetaNote));
						}
						addUndoAction(ADD_NOTE, {notes: pushedNotes, events: pushedEvents});
						moveSelectedNotes(Std.int(minNoteData), selectedNotes[0].y);
					}
				}
				else if(FlxG.keys.justPressed.A) // Select All (Ctrl + A)
				{
					var sel = selectedNotes;
					selectedNotes = curRenderedNotes.members.copy();
					addUndoAction(SELECT_NOTE, {old: sel, current: selectedNotes.copy()});
					onSelectNote();
					trace('Notes selected: ' + selectedNotes.length);
				}
				else if(FlxG.keys.justPressed.S) // Save (Ctrl + S)
					saveChart();
			}
			if(FlxG.keys.pressed.CONTROL && FlxG.keys.justPressed.F) // Ctrl + F: Toggle search box（需同时按 Ctrl，避免误触）
			{
				searchBox.visible = !searchBox.visible;
			}

			if(doCut || FlxG.keys.justPressed.DELETE || FlxG.keys.justPressed.BACKSPACE || (isMovingNotes && (FlxG.mouse.justPressedRight || FlxG.keys.justPressed.ESCAPE))) // Delete button
			{
				if(selectedNotes.length > 0)
				{
					var removedNotes:Array<MetaNote> = [];
					var removedEvents:Array<EventMetaNote> = [];
					while(selectedNotes.length > 0)
					{
						var note:MetaNote = selectedNotes[0];
						selectedNotes.shift();
						if(note == null) continue;
		
						var kind:String = !note.isEvent ? 'note' : 'event';
						trace('Removed $kind at time: ${note.strumTime}');
						if(!note.isEvent)
						{
							notes.remove(note);
							removedNotes.push(note);
						}
						else
						{
							var ev:EventMetaNote = cast (note, EventMetaNote);
							events.remove(ev);
							removedEvents.push(ev);
						}
					}
					movingNotes.clear();
					isMovingNotes = false;
					selectedNotes = [];
					onSelectNote();
					softReloadNotes();
					addUndoAction(DELETE_NOTE, {notes: removedNotes, events: removedEvents});
				}
			}
			else if(canContinue)
			{
				if(FlxG.keys.justPressed.LEFT != FlxG.keys.justPressed.RIGHT) //Lower/Higher quant
				{
					if(FlxG.keys.justPressed.LEFT)
						curQuant = quantizations[Std.int(Math.max(quantizations.indexOf(curQuant) - 1, 0))];
					else
						curQuant = quantizations[Std.int(Math.min(quantizations.indexOf(curQuant) + 1, quantizations.length - 1))];
					forceDataUpdate = true;
				}
				else if(touchPad.buttonV.justPressed || FlxG.keys.justPressed.Z != touchPad.buttonD.justPressed || FlxG.keys.justPressed.X) //Decrease/Increase Zoom
				{
					if(touchPad.buttonV.justPressed || FlxG.keys.justPressed.Z)
						curZoom = zoomList[Std.int(Math.max(zoomList.indexOf(curZoom) - 1, 0))];
					else
						curZoom = zoomList[Std.int(Math.min(zoomList.indexOf(curZoom) + 1, zoomList.length - 1))];
	
					notes.sort(PlayState.sortByTime);
					var noteSec:Int = 0;
					var nextSectionTime:Float = cachedSectionTimes[noteSec + 1];
					var curSectionTime:Float = cachedSectionTimes[noteSec];
					for (num => note in notes)
					{
						if(note == null) continue;
			
						while(cachedSectionTimes[noteSec + 1] <= note.strumTime)
						{
							noteSec++;
							nextSectionTime = cachedSectionTimes[noteSec + 1];
							curSectionTime = cachedSectionTimes[noteSec];
						}
						positionNoteYOnTime(note, noteSec);
						note.updateSustainToZoom(cachedSectionCrochets[noteSec] / 4, curZoom);
					}
	
					for (event in events)
					{
						var secNum:Int = 0;
						for (time in cachedSectionTimes)
						{
							if(time > event.strumTime) break;
							secNum++;
						}
						positionNoteYOnTime(event, secNum);
					}
					loadSection();
					showOutput(Language.get('charting_msg_zoom', [Std.string(Math.round(curZoom * 100))]));
					updateScrollY();
				}
			}
		}

		if(selectionBox.visible)
		{
			if(FlxG.mouse.releasedRight)
			{
				var sel = selectedNotes.copy();
				updateSelectionBox();
				if(!FlxG.keys.pressed.SHIFT && !holdingAlt)
					resetSelectedNotes();

				var selectionBounds = selectionBox.getScreenBounds(null, camUI);
				for (note in curRenderedNotes)
				{
					if(note == null) continue;

					if(!selectedNotes.contains(note) || holdingAlt /*&& FlxG.overlap(selectionBox, note)*/) //overlap doesnt work here
					{
						var noteBounds = note.getScreenBounds(null, camUI);
						noteBounds.top -= scrollY;
						noteBounds.bottom -= scrollY;

						if(selectionBounds.overlaps(noteBounds))
						{
							if(holdingAlt && selectedNotes.contains(note))
							{
								selectedNotes.remove(note);
								note.colorTransform.redMultiplier = note.colorTransform.greenMultiplier = note.colorTransform.blueMultiplier = 1;
								if(note.animation.curAnim != null) note.animation.curAnim.curFrame = 0;
							}
							else selectedNotes.push(note);
							onSelectNote();
						}
					}
				}
				selectionBox.visible = false;
				addUndoAction(SELECT_NOTE, {old: sel, current: selectedNotes.copy()});
			}
			else if(FlxG.mouse.justMoved)
				updateSelectionBox();
		}
		else if(FlxG.mouse.pressedRight && (FlxG.mouse.deltaScreenX != 0 || FlxG.mouse.deltaScreenY != 0))
		{
			selectionBox.setPosition(FlxG.mouse.screenX, FlxG.mouse.screenY);
			selectionStart.set(FlxG.mouse.screenX, FlxG.mouse.screenY);
			selectionBox.visible = true;
			updateSelectionBox();
		}




		var gridLayout = getGridLayout();
		var minX:Float = gridLayout.startX;
		// 新布局：Event在中间（UI列4-7），不改变minX逻辑
		if(SHOW_EVENT_COLUMN && lockedEvents) minX = gridLayout.startX;

		if (controls.mobileC)
		{
			for (touch in FlxG.touches.list)
			{
				if(touch.justPressed && (touch.overlaps(mainBox.bg) || touch.overlaps(infoBox.bg)))
					ignoreClickForThisFrame = true;

				if(isMovingNotes && touch.justReleased)
					stopMovingNotes();

			var trackInfo = getTrackAtPosition(touch.x, touch.y);
			if(trackInfo != null)
			{
					var diffX:Float = touch.x - trackInfo.trackX;
					var diffY:Float = touch.y - trackInfo.grid.y;
					if(!touchPad.buttonY.pressed)
						diffY -= diffY % (GRID_SIZE / (curQuant/16));

					if(trackInfo.nextGrid.visible) diffY = Math.min(diffY, trackInfo.grid.height + trackInfo.nextGrid.height);
					else diffY = Math.min(diffY, trackInfo.grid.height);

					if(trackInfo.prevGrid.visible) diffY = Math.max(diffY, -trackInfo.prevGrid.height);
					else diffY = Math.max(diffY, 0);

					// 根据UI列计算noteData（新布局：对手(0-3) → Event(4-7) → 玩家(8-11)）
					var uiColumn:Int = Math.floor(diffX / GRID_SIZE);

					// 根据轨道类型调整UI列偏移
					if(trackInfo.trackType == 'event') uiColumn += opponentGridCols();
					else if(trackInfo.trackType == 'player') uiColumn += opponentGridCols() + EVENT_TRACK_COUNT;

			var noteData:Int = uiColumnToNoteData(uiColumn);
			dummyArrow.visible = !selectionBox.visible;
			if(isDraggingNote)
			{
				dummyArrow.visible = false;
				updateDragPreview();
			}
			if(isDraggingNote)
			{
				dummyArrow.visible = false;
				updateDragPreview();
			}

					// 计算最终的UI列并应用间距偏移
					var finalUIColumn:Int = noteDataToUIColumn(noteData);
					var spacingOffset:Float = 0;
					if (finalUIColumn >= opponentGridCols())
					{
						spacingOffset += TRACK_SPACING; // Event轨道后的间距
					}
					if (finalUIColumn >= opponentGridCols() + EVENT_TRACK_COUNT)
					{
						spacingOffset += TRACK_SPACING; // 玩家轨道前的间距
					}
					
					// 如果是Event轨道，根据用户实际点击的具体Event轨道位置调整dummyArrow
					if (trackInfo.trackType == 'event')
					{
						var eventTrackOffset:Int = Math.floor(diffX / GRID_SIZE);
						dummyArrow.x = gridLayout.eventX + eventTrackOffset * GRID_SIZE;
					}
					else
					{
						dummyArrow.x = gridLayout.startX + finalUIColumn * GRID_SIZE + spacingOffset;
					}

					if(touchPad.buttonY.pressed || touch.y >= trackInfo.grid.y || !trackInfo.prevGrid.visible)
						dummyArrow.y = trackInfo.grid.y + diffY;
					else
					{
						var t:Float = (diffY - (GRID_SIZE / (curQuant/16)));
						if(touch.y >= trackInfo.grid.y) t *= curZoom;
						dummyArrow.y = trackInfo.grid.y + t;
					}

					if(isMovingNotes)
					{
						// Move note data
						var nData:Int = Std.int(Math.max(0, noteData));
						if(movingNotesLastData != nData)
						{
							var isFirst:Bool = true;
							var movingNotesMinData:Int = 0;
							var movingNotesMaxData:Int = 0;
							for (note in selectedNotes) //Find boundaries first
							{
								if(note == null || note.isEvent) continue;
			
								var data:Int = note.songData[1];
								if(isFirst || data < movingNotesMinData) movingNotesMinData = data;
								if(data > movingNotesMaxData) movingNotesMaxData = data;
								isFirst = false;
							}
		
							var diff:Int = nData - movingNotesLastData;
							var maxn:Int = (playerGridCols() + opponentGridCols()) - 1;
							movingNotesMinData += diff;
							movingNotesMaxData += diff;
							if(movingNotesMinData < 0)
								diff -= movingNotesMinData;
							else if(movingNotesMaxData > maxn)
								diff -= movingNotesMaxData - maxn;
		
							for (note in movingNotes)
							{
								if(note == null || note.isEvent) continue; //Events shouldn't change note data as they don't have one
		
								note.changeNoteData(note.songData[1] + diff);
								positionNoteXByData(note);
							}
						}
						movingNotesLastData = nData;
		
						// Move note strum time
						if(dummyArrow.y != movingNotesLastY)
						{
							var diff:Float = dummyArrow.y - movingNotesLastY;
							var curSecRow:Int = 0;
							for (note in movingNotes) //Try to figure out new strum time for the notes, DEFINITELY INACCURATE WITH BPM CHANGING, ALTHOUGH UNTESTED
							{
								if(note == null) continue;
		
							note.chartY += diff;
							var row:Float = (note.chartY / GRID_SIZE) * curZoom;
							while(curSecRow + 1 < cachedSectionRow.length && cachedSectionRow[curSecRow] <= row)
							{
								curSecRow++;
							}

							// ramp 感知：chartY 对应均匀步位置，直接转回毫秒（避免用起点 crochet 在过渡段产生误差）
							note.setStrumTime(Math.max(-5000, Conductor.getTimeFromStep(row)));
							positionNoteYOnTime(note, curSecRow);
								if(note.isEvent) cast (note, EventMetaNote).updateEventText();
							}
							movingNotesLastY = dummyArrow.y;
						}
					}
					else if(touch.justPressed && !ignoreClickForThisFrame)
					{
						if(FlxG.keys.pressed.CONTROL && touch.justPressed)
						{
							if(selectedNotes.length > 0)
								moveSelectedNotes(noteData, dummyArrow.y);
							else
								showOutput(Language.get('charting_msg_selectnotes'), true);
						}
						else if(touch.x >= gridLayout.startX && touch.x < gridLayout.startX + gridLayout.totalWidth)
						{
							var closeNotes:Array<MetaNote> = curRenderedNotes.members.filter(function(note:MetaNote)
							{
								var chartY:Float = touch.y - note.chartY;
								if(note.isEvent && noteData < 0)
								{
									var eventDiffX:Float = touch.x - trackInfo.trackX;
									var clickTrackIndex:Int = Std.int(Math.floor(eventDiffX / GRID_SIZE));
									clickTrackIndex = Std.int(Math.max(0, Math.min(clickTrackIndex, EVENT_TRACK_COUNT - 1)));
									var eventNote:EventMetaNote = cast note;
									return eventNote.eventTrackIndex == clickTrackIndex && chartY >= 0 && chartY < GRID_SIZE;
								}
								return (!note.isEvent && note.songData[1] == noteData) && chartY >= 0 && chartY < GRID_SIZE;
							});
							closeNotes.sort(function(a:MetaNote, b:MetaNote) return Math.abs(a.strumTime - touch.y) < Math.abs(b.strumTime - touch.y) ? 1 : -1);

							var closest = closeNotes[0];
							if(closest != null && (!closest.isEvent || !lockedEvents))
							{
								if(touchPad.buttonH.pressed || holdingAlt) // Select Note/Event
								{
									var sel = selectedNotes.copy();
									if(!selectedNotes.contains(closest))
									{
										selectedNotes.push(closest);
										addUndoAction(SELECT_NOTE, {old: sel, current: selectedNotes.copy()});
									}
									else if(!touchPad.buttonH.pressed || !holdingAlt)
									{
										resetSelectedNotes();
										selectedNotes.remove(closest);
										addUndoAction(SELECT_NOTE, {old: sel, current: selectedNotes.copy()});
									}
		
									trace('Notes selected: ' + selectedNotes.length);
								}
						else if(!FlxG.keys.pressed.CONTROL && !rightClickDeleteNote) // Remove Note/Event
						{
							deleteNoteUnderCursor(closest);
						}
						else if(!FlxG.keys.pressed.CONTROL && rightClickDeleteNote) // 启用“右键移除箭头”时，左键改为选中已有箭头，并在启用“拖动生成箭头长条”时进入待命拖动（可拖动延伸其长条）
						{
							resetSelectedNotes();
							selectedNotes.push(closest);
							if(dragCreateHoldNote && !closest.isEvent)
							{
								dragPendingNote = closest;
								dragPendingStartY = FlxG.mouse.y;
							}
						}
						if(selectedNotes.length == 1) onSelectNote();
								forceDataUpdate = true;
							}
							else if(!holdingAlt && touch.y >= trackInfo.grid.y && touch.y < trackInfo.grid.y + trackInfo.grid.height + (trackInfo.nextGrid.visible ? trackInfo.nextGrid.height : 0)) // Add note（与预览一致，放行到下一小节区域）
							{
								// 触摸 Y（均匀像素）→ 步 → ramp 感知毫秒，放置与显示一致
								var stepAtMouse:Float = (diffY / (GRID_SIZE * curZoom)) + cachedSectionRow[curSec];
								var strumTime:Float = Conductor.getTimeFromStep(stepAtMouse);
								if(noteData >= 0)
								{
									trace('Added note at time: $strumTime');
									var didAdd:Bool = false;
		
									var noteSetupData:Array<Dynamic> = [strumTime, noteData, 0];
									var typeSelected:String = noteTypes[noteTypeDropDown.selectedIndex].trim();
									if(typeSelected != null && typeSelected.length > 0)
										noteSetupData.push(typeSelected);
		
									var noteAdded:MetaNote = createNote(noteSetupData);
									for (num in sectionFirstNoteID...notes.length)
									{
										var note = notes[num];
										if(note.strumTime >= strumTime)
										{
											notes.insert(num, noteAdded);
											didAdd = true;
											break;
										}
									}
									if(!didAdd) notes.push(noteAdded);
		
									if(!holdingAlt)
										resetSelectedNotes();
		
								selectedNotes.push(noteAdded);
								addUndoAction(ADD_NOTE, {notes: [noteAdded]});

								// 播放角色对应箭头动画（LE LTS 双侧：noteData 连续编号，按侧+小节 mustHit 划分）
								var charSide:Array<Dynamic> = resolveCharAnimSide(noteData, getCurrentSectionMustHit());
								var targetChar:Character = charSide[0] ? boyfriend : dad;
								var direction:Int = charSide[1];
								if(targetChar != null && targetChar.visible)
									playCharacterSing(targetChar, direction, charSide[0]);
							}
								else if(!lockedEvents)
								{
									trace('Added event at time: $strumTime');
									var didAdd:Bool = false;
									
									// 计算点击在Event轨道的具体索引（0-3）
									var preferredTrackIndex:Null<Int> = null;
									if(trackInfo.trackType == 'event')
									{
										var eventDiffX:Float = touch.x - trackInfo.trackX;
										preferredTrackIndex = Std.int(Math.floor(eventDiffX / GRID_SIZE));
										if(preferredTrackIndex < 0 || preferredTrackIndex >= EVENT_TRACK_COUNT) preferredTrackIndex = null;
									}
		
									var eventAdded:EventMetaNote = createEvent([strumTime, [[eventsList[Std.int(Math.max(eventDropDown.selectedIndex, 0))][0], value1InputText.text, value2InputText.text, value3InputText.text, value4InputText.text]]], preferredTrackIndex);
									for (num in sectionFirstEventID...events.length)
									{
										var event = events[num];
										if(event.strumTime >= strumTime)
										{
											events.insert(num, eventAdded);
											didAdd = true;
											break;
										}
									}
									if(!didAdd) events.push(eventAdded);
		
									if(!holdingAlt)
										resetSelectedNotes();
		
									selectedNotes.push(eventAdded);
									addUndoAction(ADD_NOTE, {events: [eventAdded]});
								}
								onSelectNote();
								softReloadNotes();
							}
						}
					}
				}
				else if(!ignoreClickForThisFrame)
				{
					if(touch.justPressed && !touchPad.buttonH.pressed)
						resetSelectedNotes();
		
					dummyArrow.visible = false;
				}
			}
		} else {
			if(FlxG.mouse.justPressed && (FlxG.mouse.overlaps(mainBox.bg) || FlxG.mouse.overlaps(infoBox.bg)))
				ignoreClickForThisFrame = true;

			if(isMovingNotes && FlxG.mouse.justReleased)
				stopMovingNotes();

			var mouseTrackInfo = getTrackAtPosition(FlxG.mouse.x, FlxG.mouse.y);
			if(mouseTrackInfo != null)
			{
				var diffX:Float = FlxG.mouse.x - mouseTrackInfo.trackX;
				var diffY:Float = FlxG.mouse.y - mouseTrackInfo.grid.y;
				if(!FlxG.keys.pressed.SHIFT)
					diffY -= diffY % (GRID_SIZE / (curQuant/16));

				if(mouseTrackInfo.nextGrid.visible) diffY = Math.min(diffY, mouseTrackInfo.grid.height + mouseTrackInfo.nextGrid.height);
				else diffY = Math.min(diffY, mouseTrackInfo.grid.height);

				if(mouseTrackInfo.prevGrid.visible) diffY = Math.max(diffY, -mouseTrackInfo.prevGrid.height);
				else diffY = Math.max(diffY, 0);

				// 根据UI列计算noteData（新布局：对手(0-3) → Event(4-7) → 玩家(8-11)）
				var uiColumn:Int = Math.floor(diffX / GRID_SIZE);

				// 根据轨道类型调整UI列偏移
				if(mouseTrackInfo.trackType == 'event') uiColumn += opponentGridCols();
				else if(mouseTrackInfo.trackType == 'player') uiColumn += opponentGridCols() + EVENT_TRACK_COUNT;

				var noteData:Int = uiColumnToNoteData(uiColumn);
			dummyArrow.visible = !selectionBox.visible;

			// 待命拖动：左键按住已有箭头并移动超过阈值后，才真正开始延伸拖动（避免单纯点击选中误触）
			if(dragPendingNote != null)
			{
				if(Math.abs(FlxG.mouse.y - dragPendingStartY) > GRID_SIZE * curZoom / 3)
					startDragExtend(dragPendingNote);
				else if(FlxG.mouse.justReleased)
					dragPendingNote = null;
			}

			if(isDraggingNote)
			{
				dummyArrow.visible = false;
				updateDragPreview();
			}
			
			// 计算最终的UI列并应用间距偏移
				var finalUIColumn:Int = noteDataToUIColumn(noteData);
				var spacingOffset:Float = 0;
				if (finalUIColumn >= opponentGridCols())
				{
					spacingOffset += TRACK_SPACING; // Event轨道后的间距
				}
				if (finalUIColumn >= opponentGridCols() + EVENT_TRACK_COUNT)
				{
					spacingOffset += TRACK_SPACING; // 玩家轨道前的间距
				}
				
				// 如果是Event轨道，根据用户实际点击的具体Event轨道位置调整dummyArrow
				if (mouseTrackInfo.trackType == 'event')
				{
					var eventTrackOffset:Int = Math.floor(diffX / GRID_SIZE);
					dummyArrow.x = gridLayout.eventX + eventTrackOffset * GRID_SIZE;
				}
				else
				{
					dummyArrow.x = gridLayout.startX + finalUIColumn * GRID_SIZE + spacingOffset;
				}

				if(FlxG.keys.pressed.SHIFT || FlxG.mouse.y >= mouseTrackInfo.grid.y || !mouseTrackInfo.prevGrid.visible)
					dummyArrow.y = mouseTrackInfo.grid.y + diffY;
				else
				{
					var t:Float = (diffY - (GRID_SIZE / (curQuant/16)));
					if(FlxG.mouse.y >= mouseTrackInfo.grid.y) t *= curZoom;
					dummyArrow.y = mouseTrackInfo.grid.y + t;
				}

				if(isMovingNotes)
				{
					// Move note data
					var nData:Int = Std.int(Math.max(0, noteData));
					if(movingNotesLastData != nData)
					{
						var isFirst:Bool = true;
						var movingNotesMinData:Int = 0;
						var movingNotesMaxData:Int = 0;
						for (note in selectedNotes) //Find boundaries first
						{
							if(note == null || note.isEvent) continue;

							var data:Int = note.songData[1];
							if(isFirst || data < movingNotesMinData) movingNotesMinData = data;
							if(data > movingNotesMaxData) movingNotesMaxData = data;
							isFirst = false;
						}

						var diff:Int = nData - movingNotesLastData;
						var maxn:Int = (playerGridCols() + opponentGridCols()) - 1;
						movingNotesMinData += diff;
						movingNotesMaxData += diff;
						if(movingNotesMinData < 0)
							diff -= movingNotesMinData;
						else if(movingNotesMaxData > maxn)
							diff -= movingNotesMaxData - maxn;
	
						for (note in movingNotes)
						{
							if(note == null || note.isEvent) continue; //Events shouldn't change note data as they don't have one
	
							note.changeNoteData(note.songData[1] + diff);
							positionNoteXByData(note);
						}
					}
					movingNotesLastData = nData;
	
					// Move note strum time
					if(dummyArrow.y != movingNotesLastY)
					{
						var diff:Float = dummyArrow.y - movingNotesLastY;
						var curSecRow:Int = 0;
						for (note in movingNotes) //Try to figure out new strum time for the notes, DEFINITELY INACCURATE WITH BPM CHANGING, ALTHOUGH UNTESTED
						{
							if(note == null) continue;
	
							note.chartY += diff;
							var row:Float = (note.chartY / GRID_SIZE) * curZoom;
							while(curSecRow + 1 < cachedSectionRow.length && cachedSectionRow[curSecRow] <= row)
							{
								curSecRow++;
							}
	
							note.setStrumTime(Math.max(-5000, note.strumTime + (diff * cachedSectionCrochets[curSecRow] / 4) / GRID_SIZE * curZoom));
							positionNoteYOnTime(note, curSecRow);
							if(note.isEvent) cast (note, EventMetaNote).updateEventText();
						}
						movingNotesLastY = dummyArrow.y;
					}
				}
				else if(FlxG.mouse.justPressed && !ignoreClickForThisFrame)
				{
					if(FlxG.keys.pressed.CONTROL && FlxG.mouse.justPressed)
					{
						if(selectedNotes.length > 0)
							moveSelectedNotes(noteData, dummyArrow.y);
						else
							showOutput(Language.get('charting_msg_selectnotes'), true);
					}
					else if(FlxG.mouse.x >= gridLayout.startX && FlxG.mouse.x < gridLayout.startX + gridLayout.totalWidth)
					{
						var closest = getClosestNoteUnderMouse();
						if(closest != null && (!closest.isEvent || !lockedEvents))
						{
							if(FlxG.keys.pressed.SHIFT || holdingAlt) // Select Note/Event
							{
								var sel = selectedNotes.copy();
								if(!selectedNotes.contains(closest))
								{
									selectedNotes.push(closest);
									addUndoAction(SELECT_NOTE, {old: sel, current: selectedNotes.copy()});
								}
								else if(!holdingAlt)
								{
									resetSelectedNotes();
									selectedNotes.remove(closest);
									addUndoAction(SELECT_NOTE, {old: sel, current: selectedNotes.copy()});
								}
	
								trace('Notes selected: ' + selectedNotes.length);
							}
						else if(!FlxG.keys.pressed.CONTROL && !rightClickDeleteNote) // Remove Note/Event
						{
							deleteNoteUnderCursor(closest);
						}
						else if(!FlxG.keys.pressed.CONTROL && rightClickDeleteNote) // 启用“右键移除箭头”时，左键改为选中已有箭头，并在启用“拖动生成箭头长条”时进入待命拖动（可拖动延伸其长条）
						{
							resetSelectedNotes();
							selectedNotes.push(closest);
							if(dragCreateHoldNote && !closest.isEvent)
							{
								dragPendingNote = closest;
								dragPendingStartY = FlxG.mouse.y;
							}
						}
						if(selectedNotes.length == 1) onSelectNote();
						forceDataUpdate = true;
						}
						else if(!holdingAlt && FlxG.mouse.y >= mouseTrackInfo.grid.y && FlxG.mouse.y < mouseTrackInfo.grid.y + mouseTrackInfo.grid.height + (mouseTrackInfo.nextGrid.visible ? mouseTrackInfo.nextGrid.height : 0)) // Add note（与预览一致，放行到下一小节区域）
						{
							if(dragCreateHoldNote)
							{
								startDragCreate();
							}
							else
							{
							// 鼠标 Y（均匀像素）→ 步 → ramp 感知毫秒，放置与显示一致
							var stepAtMouse:Float = (diffY / (GRID_SIZE * curZoom)) + cachedSectionRow[curSec];
							var strumTime:Float = Conductor.getTimeFromStep(stepAtMouse);
							if(noteData >= 0)
							{
								trace('Added note at time: $strumTime');
								var didAdd:Bool = false;

								var noteSetupData:Array<Dynamic> = [strumTime, noteData, 0];
								var typeSelected:String = noteTypes[noteTypeDropDown.selectedIndex].trim();
								if(typeSelected != null && typeSelected.length > 0)
									noteSetupData.push(typeSelected);
	
								var noteAdded:MetaNote = createNote(noteSetupData);
								for (num in sectionFirstNoteID...notes.length)
								{
									var note = notes[num];
									if(note.strumTime >= strumTime)
									{
										notes.insert(num, noteAdded);
										didAdd = true;
										break;
									}
								}
								if(!didAdd) notes.push(noteAdded);
	
								if(!holdingAlt)
									resetSelectedNotes();
	
								selectedNotes.push(noteAdded);
								addUndoAction(ADD_NOTE, {notes: [noteAdded]});

								// 播放角色对应箭头动画（LE LTS 双侧：noteData 连续编号，按侧+小节 mustHit 划分）
								var charSide:Array<Dynamic> = resolveCharAnimSide(noteData, getCurrentSectionMustHit());
								var targetChar:Character = charSide[0] ? boyfriend : dad;
								var direction:Int = charSide[1];
								if(targetChar != null && targetChar.visible)
									playCharacterSing(targetChar, direction, charSide[0]);
							}
							else if(!lockedEvents)
							{
								trace('Added event at time: $strumTime');
								var didAdd:Bool = false;
								
								// 计算点击在Event轨道的具体索引（0-3）
								var preferredTrackIndex:Null<Int> = null;
								if(mouseTrackInfo.trackType == 'event')
								{
									var eventDiffX:Float = FlxG.mouse.x - mouseTrackInfo.trackX;
									preferredTrackIndex = Std.int(Math.floor(eventDiffX / GRID_SIZE));
									if(preferredTrackIndex < 0 || preferredTrackIndex >= EVENT_TRACK_COUNT) preferredTrackIndex = null;
								}
	
								var eventAdded:EventMetaNote = createEvent([strumTime, [[eventsList[Std.int(Math.max(eventDropDown.selectedIndex, 0))][0], value1InputText.text, value2InputText.text, value3InputText.text, value4InputText.text]]], preferredTrackIndex);
								for (num in sectionFirstEventID...events.length)
								{
									var event = events[num];
									if(event.strumTime >= strumTime)
									{
										events.insert(num, eventAdded);
										didAdd = true;
										break;
									}
								}
								if(!didAdd) events.push(eventAdded);
	
								if(!holdingAlt)
									resetSelectedNotes();
	
								selectedNotes.push(eventAdded);
								addUndoAction(ADD_NOTE, {events: [eventAdded]});
							}
							onSelectNote();
							softReloadNotes();
							}
						}
					}
				}
			else if(rightClickDeleteNote && FlxG.mouse.justPressedRight && !ignoreClickForThisFrame)
			{
				var closestDel = getClosestNoteUnderMouse();
				if(closestDel != null && (!closestDel.isEvent || !lockedEvents))
				{
					deleteNoteUnderCursor(closestDel);
					if(selectedNotes.length == 1) onSelectNote();
					forceDataUpdate = true;
				}
			}
			}
			else if(!ignoreClickForThisFrame)
			{
				if(FlxG.mouse.justPressed)
					resetSelectedNotes();
	
				dummyArrow.visible = false;
			}
		}
		if(isDraggingNote && FlxG.mouse.justReleased)
			finishDragCreate();
		else if(dragPendingNote != null && FlxG.mouse.justReleased)
			dragPendingNote = null; // 按下后未移动即释放：仅选中，取消待命拖动

		ignoreClickForThisFrame = false;

	// 基于Conductor.songPosition自动播放角色sing动画
	if(charactersLoaded)
	{
		// 检测音符是否刚刚到达判定点（类似打击音的时机）
		var currentStrumTime:Float = Conductor.songPosition;
		var lastStrumTime:Float = lastTime;

		for(note in notes)
		{
			if(note == null || note.isEvent) continue;

			var noteStrumTime:Float = note.strumTime;
			var noteData:Int = Std.int(note.noteData);

			// 检查音符是否在上一帧和当前帧之间到达（类似打击音的触发时机）
			if(noteStrumTime > lastStrumTime && noteStrumTime <= currentStrumTime)
			{
				// LE LTS 双侧：按音符所属小节 mustHit 解析侧与侧内列（LE 连续编号：mustHit 0..plr-1=玩家/plr..=对手；
				// 非 mustHit 0..opp-1=对手/opp..=玩家）。不能用 % 侧键数——非 mustHit 玩家音符（LE=opp+col）会算错列。
				// 必须传原始 songData[1]（非双侧 0-3=玩家编码/4-7=对手编码），不能传 note.noteData（已 %cols 折叠成侧内列，
				// 会把 4-7 折叠成 0-3 误判为玩家，导致对手侧箭头命中播玩家动画）。
				var noteSec:Int = (note.editorSection >= 0) ? note.editorSection : curSec;
				var secMustHit:Bool = (PlayState.SONG.notes[noteSec] != null) ? (PlayState.SONG.notes[noteSec].mustHitSection == true) : getCurrentSectionMustHit();
				var charSide:Array<Dynamic> = resolveCharAnimSide(Std.int(note.songData[1]), secMustHit);
				var targetChar:Character = charSide[0] ? boyfriend : dad;
				var direction:Int = charSide[1];
				if(targetChar != null && targetChar.visible)
					playCharacterSing(targetChar, direction, charSide[0]);
			}
		}

		// 处理长条持续的期间：防止角色回到idle动画
		// 检查当前是否处于长条持续时间内
		var boyfriendInSustain:Bool = false;
		var dadInSustain:Bool = false;

		for(note in notes)
		{
			if(note == null || note.isEvent) continue;

			// 检查音符是否在当前时间范围内（包括长条持续时间）
			var noteStartTime:Float = note.strumTime;
			var noteEndTime:Float = note.strumTime + (note.sustainLength > 0 ? note.sustainLength : 0);

			// 如果当前时间在音符的持续时间内
			if(currentStrumTime >= noteStartTime && currentStrumTime <= noteEndTime)
			{
				if(note.mustPress && boyfriend != null && boyfriend.visible)
				{
					boyfriendInSustain = true;
				}
				else if(!note.mustPress && dad != null && dad.visible)
				{
					dadInSustain = true;
				}
			}
		}

		// 如果角色当前在长条中，重置holdTimer以防止回到idle
		if(boyfriendInSustain && boyfriend.getAnimationName().startsWith('sing'))
			boyfriend.holdTimer = 0;

		if(dadInSustain && dad.getAnimationName().startsWith('sing'))
			dad.holdTimer = 0;

		// 处理idle动画的播放：每拍尝试播放idle动画
		// sing Duration完成后在下一拍才播放idle
		boyfriendSingFinishedBeat = handleIdleAnimationLoop(boyfriend, curBeatPure, boyfriendNeedIdleReplay, boyfriendSingFinishedBeat);
		dadSingFinishedBeat = handleIdleAnimationLoop(dad, curBeatPure, dadNeedIdleReplay, dadSingFinishedBeat);

		// 更新上一拍的记录
		lastBeat = curBeatPure;
	}

		// 更新不受noteOffset影响的纯粹歌曲节拍（用于图标缩放）
		var curDecStepPure:Float = Conductor.getStep(Conductor.songPosition);
		curStepPure = Math.floor(curDecStepPure);
		curBeatPure = Math.floor(curStepPure / 4);

	// ===== Lil' Buddies 迷你角色动画 =====

	// [块A] 独立音符驱动 + sustain 检测（music.playing 时）
	if(chartEditorSave != null && chartEditorSave.data.showLilBuddies && FlxG.sound.music != null && FlxG.sound.music.playing)
	{
		var lilNow:Float = Conductor.songPosition;
		// 独立时间窗口，不依赖外部 lastTime
		for(note in notes)
		{
			if(note == null || note.isEvent) continue;
			var noteStrumTime:Float = note.strumTime;
			if(noteStrumTime > lilLastStrumCheckTime && noteStrumTime <= lilNow)
			{
				// 双侧：按所属小节 mustHit 解析侧与侧内列（同主角色逻辑），避免非 mustHit 玩家音符 % 玩家键数算错列；
				// 同样传原始 songData[1]，不能传 note.noteData（%cols 折叠会误判侧）
				var noteSec:Int = (note.editorSection >= 0) ? note.editorSection : curSec;
				var secMustHit:Bool = (PlayState.SONG.notes[noteSec] != null) ? (PlayState.SONG.notes[noteSec].mustHitSection == true) : getCurrentSectionMustHit();
				var charSide:Array<Dynamic> = resolveCharAnimSide(Std.int(note.songData[1]), secMustHit);
				playLilSing(charSide[0], charSide[1]);
			}
		}
		lilLastStrumCheckTime = lilNow;

		// 长条持续 → sing 不回 idle
		lilBfInSustain = false;
		lilOppInSustain = false;
		for(note in notes)
		{
			if(note == null || note.isEvent) continue;
			var noteEndTime:Float = note.strumTime + (note.sustainLength > 0 ? note.sustainLength : 0);
			if(lilNow >= note.strumTime && lilNow <= noteEndTime)
			{
				if(note.mustPress) lilBfInSustain = true;
				else lilOppInSustain = true;
			}
		}
	}

	// [块B] idle 恢复（每帧执行，用 curBeatPure 拍数判断）
	if(chartEditorSave != null && chartEditorSave.data.showLilBuddies)
	{
		// 只在 curAnim != 'idle' 时才 play，避免每帧 forceRestart 打断 idle 循环
		if(lilBf != null && lilBf.visible)
		{
			var bfAnim:String = lilBf.animation.curAnim != null ? lilBf.animation.curAnim.name : '';
			if(bfAnim != 'idle' && !lilBfInSustain && lilBfSingFinishedBeat != -1 && curBeatPure > lilBfSingFinishedBeat)
			{
				lilBf.animation.play('idle', false, false);  // forceRestart=false，不打断循环
				lilBf.color = 0xFFFFFFFF; // 回 idle 恢复黑白
				lilBfSingFinishedBeat = -1;
			}
		}
		if(lilOpp != null && lilOpp.visible)
		{
			var oppAnim:String = lilOpp.animation.curAnim != null ? lilOpp.animation.curAnim.name : '';
			if(oppAnim != 'idle' && !lilOppInSustain && lilOppSingFinishedBeat != -1 && curBeatPure > lilOppSingFinishedBeat)
			{
				lilOpp.animation.play('idle', false, false);
				lilOpp.color = 0xFFFFFFFF; // 回 idle 恢复黑白
				lilOppSingFinishedBeat = -1;
			}
		}
	}

	// [块C] 音乐未播放：重置时间窗口 + 点击 lilBf → yeah 动画
	if(chartEditorSave != null && chartEditorSave.data.showLilBuddies && FlxG.sound.music != null && !FlxG.sound.music.playing)
	{
		lilLastStrumCheckTime = Conductor.songPosition;

		if(lilBf != null && lilBf.visible && FlxG.mouse.justPressed && !ignoreClickForThisFrame)
		{
			var mx:Float = FlxG.mouse.screenX;
			var my:Float = FlxG.mouse.screenY;
			if(mx >= lilBf.x && mx <= lilBf.x + lilBf.width && my >= lilBf.y && my <= lilBf.y + lilBf.height)
			{
				lilBf.animation.play('yeah', true);
				lilBfSingFinishedBeat = curBeatPure;
			}
		}
	}
		
		// 计算纯粹的section（不受noteOffset影响）
		curSecPure = curSec; // 默认使用当前curSec
		if (cachedSectionTimes != null && cachedSectionTimes.length > 0)
		{
			// 使用纯粹的songPosition（不受noteOffset影响）来计算section
			var songPosPure = Conductor.songPosition;
			while (curSecPure > 0 && songPosPure < cachedSectionTimes[curSecPure])
				curSecPure--;
			while (curSecPure < cachedSectionTimes.length - 1 && songPosPure >= cachedSectionTimes[curSecPure + 1])
				curSecPure++;
		}
		
		songBeatNoOffset = curBeatPure;
		
		// Add icon bounce effect on every beat（使用不受offset影响的节拍）
		if (iconBopEnabled && songBeatNoOffset != lastBeatHit) {
			var mustHitSection:Bool = (PlayState.SONG.notes[curSec] != null && PlayState.SONG.notes[curSec].mustHitSection);
			if(iconbopTween != null)
				iconbopTween.cancel();
			for (icon in icons) {
				if ((mustHitSection && icon.ID == 1) || (!mustHitSection && icon.ID == 2)) {
					icon.scale.set(0.4, 0.4); // Slightly increase the size for the bounce effect
					//FlxTween.tween(icon.scale, {x: 0.3, y: 0.3}, 0.17, {ease: FlxEase.linear}); // Smoothly return to original size
					iconbopTween = FlxTween.tween(icon.scale, {x: 0.3, y: 0.3}, 0.15, {
						onComplete: function(twn:FlxTween) {
							iconbopTween = null;
						}});
			}
			}
		}

		if(Conductor.songPosition != lastTime || forceDataUpdate)
		{
			var curTime:String = FlxStringUtil.formatTime(Conductor.songPosition / 1000, true);
			var songLength:String = (FlxG.sound.music != null) ? FlxStringUtil.formatTime(FlxG.sound.music.length / 1000, true) : '???';
			var curSecData:SwagSection = PlayState.SONG.notes[curSecPure];
			var oppCount:Int = 0;
			var playCount:Int = 0;
			for(secIdx in 0...curSecPure)
			{
				var secData = PlayState.SONG.notes[secIdx];
				if(secData == null) continue;
				for(note in secData.sectionNotes)
				{
					if(note == null) continue;
					var secMustHit:Bool = secData.mustHitSection;
					if(isPlayerNoteByData(Std.int(note[1]), secMustHit)) playCount++; else oppCount++;
				}
			}
			if(curSecData != null)
			{
				for(note in curSecData.sectionNotes)
				{
					if(note == null) continue;
					if(note[0] > Conductor.songPosition) continue;
					var secMustHitCur:Bool = curSecData.mustHitSection;
					if(isPlayerNoteByData(Std.int(note[1]), secMustHitCur)) playCount++; else oppCount++;
				}
			}
			var str:String =  '$curTime / $songLength' +
							  '\n\nSection: $curSecPure' +
							  '\nNote: $oppCount / $playCount' +
							  '\nBeat: $curBeatPure' +
							  '\nStep: $curStepPure' +
							  '\n\nBeat Snap: ${curQuant} / 16' +
							  '\nSelected: ${selectedNotes.length}';

			if(str != infoText.text)
			{
				infoText.text = str;
				if(infoText.autoSize) infoText.autoSize = false;
			}

var vortexPlaying:Bool = (vortexEnabled && FlxG.sound.music != null && FlxG.sound.music.playing);
		var canPlayHitSound:Bool = (FlxG.sound.music != null && FlxG.sound.music.playing && lastTime < Conductor.songPosition);
		
		for (note in curRenderedNotes)
		{
			if(note == null || note.isEvent) continue;

			note.alpha = (note.strumTime >= Conductor.songPosition) ? 1 : 0.6;
			if(Conductor.songPosition > note.strumTime && lastTime <= note.strumTime)
			{
				if(canPlayHitSound)
				{
					// 使用音效池轮询播放，确保每个音符都能发声
					if(note.mustPress && hitsoundPlayerStepper.value > 0)
					{
						var sound:FlxSound = hitSoundPool[hitSoundPoolIndex];
						sound.loadEmbedded(Paths.sound('hitsounds/quaver'));
						sound.volume = hitsoundPlayerStepper.value;
						sound.play();
						hitSoundPoolIndex = (hitSoundPoolIndex + 1) % hitSoundPoolSize;
					}
					else if(!note.mustPress && hitsoundOpponentStepper.value > 0)
					{
						var sound:FlxSound = hitSoundPool[hitSoundPoolIndex];
						sound.loadEmbedded(Paths.sound('hitsounds/stepmania'));
						sound.volume = hitsoundOpponentStepper.value;
						// sound.pan = 1; // 对手音符：纯右声道
						sound.play();
						hitSoundPoolIndex = (hitSoundPoolIndex + 1) % hitSoundPoolSize;
					}
				}

					if(vortexPlaying)
					{
						// LE LTS 双侧/调换后：strums 按"对手左 / 玩家右"排列（members 索引 ≠ Psych 编码 noteData）。
						// 必须通过 noteDataToUIColumn 映射到 UI 列，再换算成 strums 实际 members 索引，
						// 否则玩家音符会触发对手 strum、对手音符触发玩家 strum（原 Psych 按 noteData 直索引的残留）。
						var uiColV:Int = noteDataToUIColumn(Std.int(note.songData[1]));
						var strumIndexV:Int = -1;
						if (uiColV >= 0)
						{
							var oColsV:Int = opponentGridCols();
							if (uiColV < oColsV) strumIndexV = uiColV;                       // 对手区
							else if (uiColV >= oColsV + EVENT_TRACK_COUNT) strumIndexV = uiColV - EVENT_TRACK_COUNT; // 玩家区（成员索引比 UI 列少 EVENT 轨道数）
						}
						if (strumIndexV >= 0 && strumIndexV < strumLineNotes.length)
						{
							var strumNote:StrumNote = strumLineNotes.members[strumIndexV];
							if(strumNote != null)
							{
								strumNote.playAnim('confirm', true);
								strumNote.resetAnim = Math.max(Conductor.stepCrochet * 1.25, note.sustainLength) / 1000 / playbackRate;
							}
						}
					}
				}
			}
			forceDataUpdate = false;
			
			// moved from beatHit()
			if(metronomeStepper.value > 0 && lastBeatHit != songBeatNoOffset)
				FlxG.sound.play(Paths.sound('Metronome_Tick'), metronomeStepper.value);

			lastBeatHit = songBeatNoOffset;
		}

		if(selectedNotes.length > 0)
		{
			noteSelectionSine += elapsed;
			var sineValue:Float = 0.75 + Math.cos(Math.PI * noteSelectionSine * (isMovingNotes ? 8 : 2)) / 4;
			//trace(sineValue);

			var qPress = (touchPad.buttonUp2.justPressed || FlxG.keys.justPressed.Q);
			var ePress = (touchPad.buttonDown2.justPressed || FlxG.keys.justPressed.E);
			var addSus = (touchPad.buttonY.pressed || FlxG.keys.pressed.SHIFT ? 4 : 1) * (Conductor.stepCrochet / 2);
			if(qPress) addSus *= -1;

			if(qPress != ePress && selectedNotes.length != 1)
				susLengthStepper.value += addSus;

			var noteSec:Int = 0;
			for (note in selectedNotes)
			{
				if(note == null || !note.exists) continue;

				if(!note.isEvent)
				{
					if(qPress != ePress)
					{
						while(cachedSectionTimes.length > noteSec + 1 && cachedSectionTimes[noteSec + 1] <= note.strumTime)
							noteSec++;

						note.setSustainLength(note.sustainLength + addSus, cachedSectionCrochets[noteSec] / 4, curZoom);
						if(selectedNotes.length == 1)
							susLengthStepper.value = note.sustainLength;
					}
					note.animation.update(elapsed); //let selected notes be animated for better visibility
				}
				note.colorTransform.redMultiplier = note.colorTransform.greenMultiplier = note.colorTransform.blueMultiplier = sineValue;
			}
		}
		else noteSelectionSine = 0;

		outputTxt.alpha = outputAlpha;
		outputTxt.visible = (outputAlpha > 0);
		FlxG.camera.scroll.y = scrollY;
		lastFocus = PsychUIInputText.focusOn;
	}

	function moveSelectedNotes(noteData:Int = 0, lastY:Float) //This turns selected notes into moving notes
	{
		var originalNotes:Array<MetaNote> = [];
		var originalEvents:Array<EventMetaNote> = [];
		var movedNotes:Array<MetaNote> = [];
		var movedEvents:Array<EventMetaNote> = [];
		for (note in selectedNotes)
		{
			if(note == null) continue;

			if(!note.isEvent)
			{
				notes.remove(note);
				var secNum:Int = 0;
				for (time in cachedSectionTimes)
				{
					if(time > note.strumTime) break;
					secNum++;
				}
				originalNotes.push(note);
				var mov:MetaNote = createNote(note.songData, secNum);
				movingNotes.add(mov);
				movedNotes.push(mov);
			}
			else
			{
				events.remove(cast (note, EventMetaNote));
				originalEvents.push(cast (note, EventMetaNote));
				var mov:EventMetaNote = createEvent(note.songData);
				movingNotes.add(mov);
				movedEvents.push(mov);
			}
		}
		selectedNotes = movingNotes.members.copy();
		isMovingNotes = true;
		movingNotesLastY = lastY;
		movingNotesLastData = noteData;
		movingNotes.sort(cast PlayState.sortByTime);
		addUndoAction(MOVE_NOTE, {originalNotes: originalNotes, originalEvents: originalEvents, movedNotes: movedNotes, movedEvents: movedEvents});
		softReloadNotes();
	}

	function stopMovingNotes() //This turns moving notes into saved notes
	{
		var pushedNotes:Array<MetaNote> = [];
		var pushedEvents:Array<EventMetaNote> = [];
		movingNotes.forEachAlive(function(note:MetaNote)
		{
			if(!note.isEvent)
			{
				notes.push(note);
				pushedNotes.push(note);
			}
			else
			{
				events.push(cast (note, EventMetaNote));
				pushedEvents.push(cast (note, EventMetaNote));
			}
		});
		notes.sort(PlayState.sortByTime);
		events.sort(PlayState.sortByTime);
		movingNotes.clear();
		isMovingNotes = false;
		softReloadNotes();
	}

	function makeNoteDataCopy(originalData:Array<Dynamic>, isEvent:Bool)
	{
		var dataCopy:Array<Dynamic> = originalData.copy();
		if(isEvent)
		{
			var eventGrp:Array<Array<Dynamic>> = cast dataCopy[1].copy();
			for (num => subEvent in eventGrp)
				eventGrp[num] = subEvent.copy();

			dataCopy[1] = eventGrp;
		}
		return dataCopy;
	}

	function updateScrollY()
	{
		var secStartTime:Null<Float> = cast cachedSectionTimes[curSec];
		var secCrochet:Null<Float> = cast cachedSectionCrochets[curSec];
		var secRows:Null<Float> = cast cachedSectionRow[curSec];
		if(secStartTime == null || secCrochet == null || secRows == null) return;

		scrollY = (((Conductor.songPosition - secStartTime) / secCrochet * GRID_SIZE * 4) + (secRows * GRID_SIZE)) * curZoom - FlxG.height/2;
		
		// 轨道颜色覆盖层的位置是固定的，不需要在scroll时更新（已在create时设置）
		// 只确保覆盖层存在即可
	}

	function updateSelectionBox()
	{
		var diffX:Float = FlxG.mouse.screenX - selectionStart.x;
		var diffY:Float = FlxG.mouse.screenY - selectionStart.y;
		selectionBox.setPosition(selectionStart.x, selectionStart.y);

		if(diffX < 0) //Fixes negative X scale
		{
			diffX = Math.abs(diffX);
			selectionBox.x -= diffX;
		}
		if(diffY < 0) //Fixes negative Y scale
		{
			diffY = Math.abs(diffY);
			selectionBox.y -= diffY;
		}
		selectionBox.scale.set(diffX, diffY);
		selectionBox.updateHitbox();
	}

	function showOutput(message:String, isError:Bool = false)
	{
		trace(message);
		outputTxt.text = message;
		outputTxt.y = FlxG.height - outputTxt.height - 30;
		outputAlpha = 4;
		if(isError)
		{
			FlxG.sound.play(Paths.sound('cancelMenu'), 0.6);
			outputTxt.color = FlxColor.RED;
		}
		else
		{
			FlxG.sound.play(Paths.sound('scrollMenu'), 0.6);
			outputTxt.color = FlxColor.WHITE;
		}
	}

	function resetSelectedNotes()
	{
		for (note in selectedNotes)
		{
			if(note == null || !note.exists) continue;

			note.colorTransform.redMultiplier = note.colorTransform.greenMultiplier = note.colorTransform.blueMultiplier = 1;
			if(note.animation.curAnim != null) note.animation.curAnim.curFrame = 0;
		}
		selectedNotes = [];
		onSelectNote();
		forceDataUpdate = true;
	}

	function onSelectNote()
	{
		if(selectedNotes.length == 1) //Only one note selected
		{
			var note:MetaNote = selectedNotes[0];
			strumTimeStepper.value = note.strumTime;
			if(!note.isEvent) //Normal note
			{
				if(!note.isEvent)
				{
					susLengthLastVal = susLengthStepper.value = note.sustainLength;
					noteTypeDropDown.selectedIndex = Std.int(Math.max(0, noteTypes.indexOf(note.noteType)));
				}
				else
				{
					susLengthLastVal = susLengthStepper.value = 0;
					noteTypeDropDown.selectedLabel = '';
				}
			}
			else //Event note
			{
				var eventNote:EventMetaNote = cast (selectedNotes[0], EventMetaNote);
				updateSelectedEventText();
			}
		}
		else if(selectedNotes.length > 1)
		{
			susLengthStepper.min = -susLengthStepper.max;
			susLengthLastVal = susLengthStepper.value = 0;
			strumTimeStepper.value = selectedNotes[0].strumTime;
			noteTypeDropDown.selectedLabel = '';
			eventDropDown.selectedLabel = '';
			value1InputText.text = '';
			value2InputText.text = '';
			value3InputText.text = '';
			value4InputText.text = '';
		}
		forceDataUpdate = true;
	}

	function updateSelectedEventText()
	{
		if(selectedNotes.length == 1 && selectedNotes[0].isEvent)
		{
			var eventNote:EventMetaNote = cast (selectedNotes[0], EventMetaNote);
			curEventSelected = Std.int(FlxMath.bound(curEventSelected, 0, eventNote.events.length - 1));
			selectedEventText.text = Language.get('charting_selected_event', ['${curEventSelected + 1}', '${eventNote.events.length}']);
			selectedEventText.visible = true;
			
			var myEvent:Array<String> = eventNote.events[curEventSelected];
			if(myEvent != null)
			{
				var eventName:String = (myEvent[0] != null) ? myEvent[0] : '';
				for (num => event in eventsList)
				{
					if(event[0] == eventName)
					{
						eventDropDown.selectedIndex = num;
						break;
					}
				}
				value1InputText.text = (myEvent[1] != null) ? myEvent[1] : '';
				value2InputText.text = (myEvent[2] != null) ? myEvent[2] : '';
				value3InputText.text = (myEvent[3] != null) ? myEvent[3] : '';
				value4InputText.text = (myEvent[4] != null) ? myEvent[4] : '';
			}
		}
		else selectedEventText.visible = false;
	}

	function searchEvents(searchStr:String)
	{
		_lastSearchStr = searchStr;
		if(searchStr.length == 0)
		{
			_eventSearchResults = [];
			eventSearchResultLine1.text = '';
			eventSearchResultLine1.visible = false;
			eventSearchResultLine2.text = '';
			eventSearchResultLine2.visible = false;
			eventSearchResultLine3.text = '';
			eventSearchResultLine3.visible = false;
			return;
		}
		var terms:Array<String> = [];
		var useRegex:Bool = false;
		var lowerSearch:String = searchStr.toLowerCase().trim();

		// 若含通配符则转 regex，否则按空格分词（全部匹配）
		if(lowerSearch.contains('*') || lowerSearch.contains('?') || lowerSearch.contains('['))
		{
			useRegex = true;
			var esc = '';
			var chars = lowerSearch.split('');
			var ci = 0;
			while(ci < chars.length)
			{
				var c = chars[ci];
				switch(c)
				{
					case '[':
						// 收集 [] 内的内容直到闭合
						var clsEnd = lowerSearch.indexOf(']', ci);
						if(clsEnd == -1) { esc += '\\['; ci++; continue; }
						var clsContent = lowerSearch.substring(ci + 1, clsEnd);
						// [!...] 转为 [^...]
						if(clsContent.length > 0 && clsContent.charCodeAt(0) == 33)
							clsContent = '^' + clsContent.substr(1);
						esc += '[' + clsContent + ']';
						ci = clsEnd + 1;
					case '*': esc += '.*'; ci++;
					case '?': esc += '.'; ci++;
					case '.': esc += '\\.'; ci++;
					case '^': esc += '\\^'; ci++;
					case '$': esc += '\\$'; ci++;
					case '+': esc += '\\+'; ci++;
					case '|': esc += '\\|'; ci++;
					case '{': esc += '\\{'; ci++;
					case '}': esc += '\\}'; ci++;
					case '(': esc += '\\('; ci++;
					case ')': esc += '\\)'; ci++;
					case '\\': esc += '\\\\'; ci++;
					default: esc += c; ci++;
				}
			}
			terms.push(esc);
		}
		else
		{
			var parts = lowerSearch.split(' ');
			for(p in parts) if(p.length > 0) terms.push(p);
		}

		function matchesText(txt:String):Bool
		{
			var t = txt.toLowerCase();
			for(term in terms)
			{
				if(useRegex)
				{
					var re = new EReg(term, '');
					if(!re.match(t)) return false;
				}
				else if(!t.contains(term)) return false;
			}
			return true;
		}

		_eventSearchResults = [];
		for (eventNote in events)
		{
			for (i in 0...eventNote.events.length)
			{
				var ev:Array<Dynamic> = eventNote.events[i];
				if(ev == null) continue;
				var match:Bool = false;
				// 检查事件名
				var evName:String = (ev[0] != null) ? Std.string(ev[0]) : '';
				if(matchesText(evName)) match = true;
				// 检查各 value 字段
				if(!match)
					for (v in 1...Std.int(Math.min(ev.length, 5)))
					{
						if(ev[v] != null && matchesText(Std.string(ev[v])))
						{
							match = true;
							break;
						}
					}
				if(match) _eventSearchResults.push({note: eventNote, index: i});
			}
		}
		// 自动检测事件名（所有匹配事件名相同）
		var allNamesSame:Bool = true;
		var commonName:String = '';
		if(_eventSearchResults.length > 0)
		{
			commonName = _eventSearchResults[0].note.events[_eventSearchResults[0].index][0];
			for (r in _eventSearchResults)
			{
				var n:String = r.note.events[r.index][0];
				if(n != commonName) { allNamesSame = false; break; }
			}
		}
		_jumpToSearchResult(0, allNamesSame, commonName);
	}

	function _jumpToSearchResult(resultIdx:Int, allNamesSame:Bool, commonName:String)
	{
		if(_eventSearchResults.length == 0)
		{
			eventSearchResultLine1.text = Language.get('charting_event_search_notfound');
			eventSearchResultLine1.visible = true;
			eventSearchResultLine2.text = '';
			eventSearchResultLine2.visible = false;
			eventSearchResultLine3.text = '';
			eventSearchResultLine3.visible = false;
			return;
		}
		_currentSearchResultIdx = Std.int(FlxMath.bound(resultIdx, 0, _eventSearchResults.length - 1));
		var result = _eventSearchResults[_currentSearchResultIdx];
		resetSelectedNotes();
		selectedNotes.push(result.note);
		curEventSelected = result.index;
		setSongPlaying(false);
		Conductor.songPosition = result.note.strumTime;
		FlxG.sound.music.time = result.note.strumTime - Conductor.offset;
		updateSelectedEventText();
		eventSearchResultLine1.text = Language.get('charting_event_search_found', [Std.string(_currentSearchResultIdx + 1), Std.string(_eventSearchResults.length)]);
		eventSearchResultLine1.visible = true;
		if(result.note.events.length > 1)
		{
			eventSearchResultLine2.text = '(' + Language.get('charting_event_note_count', [Std.string(result.note.events.length)]) + ')';
			eventSearchResultLine2.visible = true;
		}
		else
		{
			eventSearchResultLine2.text = '';
			eventSearchResultLine2.visible = false;
		}
		var curEventName:String = result.note.events[result.index][0];
		if(curEventName.length > 0)
		{
			eventSearchResultLine3.text = curEventName;
			eventSearchResultLine3.visible = true;
		}
		else
		{
			eventSearchResultLine3.text = '';
			eventSearchResultLine3.visible = false;
		}
	}

	function createGrids()
	{
		var destroyed:Bool = false;
		var stripes:Array<Int> = null;
		if(opponentGridBg != null)
		{
			stripes = opponentGridBg.stripes;
			remove(prevOpponentGridBg);
			remove(prevEventGridBg);
			remove(prevPlayerGridBg);
			remove(opponentGridBg);
			remove(eventGridBg);
			remove(playerGridBg);
			remove(nextOpponentGridBg);
			remove(nextEventGridBg);
			remove(nextPlayerGridBg);
			prevOpponentGridBg = FlxDestroyUtil.destroy(prevOpponentGridBg);
			prevEventGridBg = FlxDestroyUtil.destroy(prevEventGridBg);
			prevPlayerGridBg = FlxDestroyUtil.destroy(prevPlayerGridBg);
			opponentGridBg = FlxDestroyUtil.destroy(opponentGridBg);
			eventGridBg = FlxDestroyUtil.destroy(eventGridBg);
			playerGridBg = FlxDestroyUtil.destroy(playerGridBg);
			nextOpponentGridBg = FlxDestroyUtil.destroy(nextOpponentGridBg);
			nextEventGridBg = FlxDestroyUtil.destroy(nextEventGridBg);
			nextPlayerGridBg = FlxDestroyUtil.destroy(nextPlayerGridBg);
			destroyed = true;
		}

		// 创建三个独立的轨道网格（LE LTS 双侧：对手/玩家各按各自键数渲染）
		var startX:Float = FlxG.width / 2;
		var pCols:Int = playerGridCols();
		var oCols:Int = opponentGridCols();
		
		// 计算总宽度并居中
		var opponentWidth:Float = GRID_SIZE * oCols;
		var eventWidth:Float = SHOW_EVENT_COLUMN ? GRID_SIZE * EVENT_TRACK_COUNT : 0;
		var playerWidth:Float = GRID_SIZE * pCols;
		var spacingWidth:Float = TRACK_SPACING * (SHOW_EVENT_COLUMN ? 2 : 1);
		var totalWidth:Float = opponentWidth + eventWidth + playerWidth + spacingWidth;
		
		startX = (FlxG.width - totalWidth) / 2;

		// 对手轨道网格
		opponentGridBg = new ChartingGridSprite(oCols, gridColors[0], gridColors[1]);
		opponentGridBg.x = startX;
		opponentGridBg.y = FlxG.height / 2;
		
		// Event轨道网格
		if(SHOW_EVENT_COLUMN)
		{
			eventGridBg = new ChartingGridSprite(EVENT_TRACK_COUNT, gridColors[0], gridColors[1]);
			eventGridBg.x = startX + opponentWidth + TRACK_SPACING;
			eventGridBg.y = opponentGridBg.y;
		}
		
		// 玩家轨道网格
		playerGridBg = new ChartingGridSprite(pCols, gridColors[0], gridColors[1]);
		playerGridBg.x = startX + opponentWidth + eventWidth + TRACK_SPACING * (SHOW_EVENT_COLUMN ? 2 : 1);
		playerGridBg.y = opponentGridBg.y;

		// 创建前一节和下一节的网格
		prevOpponentGridBg = new ChartingGridSprite(oCols, gridColorsOther[0], gridColorsOther[1]);
		prevOpponentGridBg.x = opponentGridBg.x;
		prevOpponentGridBg.y = opponentGridBg.y;
		prevOpponentGridBg.stripes = opponentGridBg.stripes = stripes;
		
		nextOpponentGridBg = new ChartingGridSprite(oCols, gridColorsOther[0], gridColorsOther[1]);
		nextOpponentGridBg.x = opponentGridBg.x;
		nextOpponentGridBg.y = opponentGridBg.y;
		nextOpponentGridBg.stripes = opponentGridBg.stripes;
		
		if(SHOW_EVENT_COLUMN)
		{
			prevEventGridBg = new ChartingGridSprite(EVENT_TRACK_COUNT, gridColorsOther[0], gridColorsOther[1]);
			prevEventGridBg.x = eventGridBg.x;
			prevEventGridBg.y = eventGridBg.y;
			prevEventGridBg.stripes = eventGridBg.stripes = stripes;
			
			nextEventGridBg = new ChartingGridSprite(EVENT_TRACK_COUNT, gridColorsOther[0], gridColorsOther[1]);
			nextEventGridBg.x = eventGridBg.x;
			nextEventGridBg.y = eventGridBg.y;
			nextEventGridBg.stripes = eventGridBg.stripes;
		}
		
		prevPlayerGridBg = new ChartingGridSprite(pCols, gridColorsOther[0], gridColorsOther[1]);
		prevPlayerGridBg.x = playerGridBg.x;
		prevPlayerGridBg.y = playerGridBg.y;
		prevPlayerGridBg.stripes = playerGridBg.stripes = stripes;
		
		nextPlayerGridBg = new ChartingGridSprite(pCols, gridColorsOther[0], gridColorsOther[1]);
		nextPlayerGridBg.x = playerGridBg.x;
		nextPlayerGridBg.y = playerGridBg.y;
		nextPlayerGridBg.stripes = playerGridBg.stripes;
		
		if(destroyed)
		{
			insert(getFirstNull(), prevOpponentGridBg);
			insert(getFirstNull(), nextOpponentGridBg);
			insert(getFirstNull(), opponentGridBg);
			if(SHOW_EVENT_COLUMN)
			{
				insert(getFirstNull(), prevEventGridBg);
				insert(getFirstNull(), nextEventGridBg);
				insert(getFirstNull(), eventGridBg);
			}
		insert(getFirstNull(), prevPlayerGridBg);
		insert(getFirstNull(), nextPlayerGridBg);
		insert(getFirstNull(), playerGridBg);
		// 网格重建期间（applySectionColumns 调用）不递归触发 loadSection，避免死循环
		if(!_rebuildingGrids) loadSection();
	}
	else
	{
		add(prevOpponentGridBg);
		add(nextOpponentGridBg);
		add(opponentGridBg);
		if(SHOW_EVENT_COLUMN)
		{
			add(prevEventGridBg);
			add(nextEventGridBg);
			add(eventGridBg);
		}
		add(prevPlayerGridBg);
		add(nextPlayerGridBg);
		add(playerGridBg);
	}
	// 新创建/重建后统一着色条纹（原 create() 内的内联着色逻辑已迁移至此）
	applyGridStripeColors();
}

	// 根据UI列获取对应的网格（LE LTS 双侧：对手区按对手键数列数）
	function getGridByUIColumn(uiColumn:Int):ChartingGridSprite
	{
		var oCols:Int = opponentGridCols();
		if(uiColumn < oCols)
		{
			return opponentGridBg;
		}
		else if(SHOW_EVENT_COLUMN && uiColumn < oCols + EVENT_TRACK_COUNT)
		{
			return eventGridBg;
		}
		else
		{
			return playerGridBg;
		}
	}

	// 获取所有轨道的总宽度和起始位置
	function getGridLayout():{startX:Float, opponentX:Float, eventX:Float, playerX:Float, totalWidth:Float}
	{
		// LE LTS 双侧：对手/玩家网格按各自键数渲染（不对称布局）；非双侧 = 两侧同值
		var opponentWidth:Float = GRID_SIZE * opponentGridCols();
		var eventWidth:Float = SHOW_EVENT_COLUMN ? GRID_SIZE * EVENT_TRACK_COUNT : 0;
		var playerWidth:Float = GRID_SIZE * playerGridCols();
		var spacingWidth:Float = TRACK_SPACING * (SHOW_EVENT_COLUMN ? 2 : 1);
		var totalWidth:Float = opponentWidth + eventWidth + playerWidth + spacingWidth;
		var startX:Float = (FlxG.width - totalWidth) / 2;
		
		return {
			startX: startX,
			opponentX: startX,
			eventX: startX + opponentWidth + TRACK_SPACING,
			playerX: startX + opponentWidth + eventWidth + TRACK_SPACING * (SHOW_EVENT_COLUMN ? 2 : 1),
			totalWidth: totalWidth
		};
	}

	// 小节键数（Extra Keys：从谱面 SONG.mania 读取，3 = 标准 4 键）
	public static function getSectionMania(secNum:Int):Int
	{
		if (PlayState.SONG != null && PlayState.SONG.mania != null)
			return PlayState.SONG.mania;
		return 3;
	}

	// 某小节的轨道列数（Extra Keys：mania + 1；4 键 = 4 列，6 键 = 6 列...）
	// LE LTS 双侧（LE 式分侧编辑）：网格列数 = 当前编辑侧键数（玩家侧=playerKeyCount、对手侧=keyCount），各侧独立网格。
	public static function getSectionColumns(secNum:Int):Int
	{
		if (isDualChart())
			return (editorSide == 0) ? dualPlayerKeyCount() : dualOpponentKeyCount();
		return getSectionMania(secNum) + 1;
	}

	// 根据小节（按谱面 mania）同步：Note.colArray（颜色前缀）、singAnimations、网格列数、网格与箭头、轨道色块。
	// 按指定 mania 档位生成一组的列配色数组（仅取色，不含 sing 动画名；双侧档位缓存用）。
	// 逻辑与 applySectionColumns 的填充一致，4 键兜底 purple/blue/green/red。
	function buildColArrayForMania(mania:Int, laneCountFallback:Int):Array<String>
	{
		ExtraKeysHandler.ensure();
		var out:Array<String> = [];
		var ek = ExtraKeysHandler.instance.data;
		if (ek != null && ek.keys != null && ek.keys.length > mania) {
			var mode = ek.keys[mania];
			var laneCount:Int = (mode != null && mode.notes != null) ? mode.notes.length : laneCountFallback;
			for (i in 0...laneCount) {
				var g:Int = (mode.notes != null && i < mode.notes.length) ? mode.notes[i] : i;
				var anim = (ek.animations != null && g >= 0 && g < ek.animations.length) ? ek.animations[g] : null;
				out.push(anim != null ? anim.note : 'purple');
			}
		} else {
			out = ['purple', 'blue', 'green', 'red'];
		}
		return out;
	}

	// LE LTS 双侧：改键数后按"新键数"重编码全部音符的 LE 连续编号，保持音符的"侧 + 侧内列"不变。
	// 双侧谱面音符编号按谱面当前键数编码（mustHit 小节 0..plr-1=玩家/plr..=对手；非 mustHit 小节 0..opp-1=对手/opp..=玩家）。
	// 若只改 SONG.keyCount/playerKeyCount 而不重编码，改对手键数后对手边界（opp）变化，
	// 原玩家音符（如非 mustHit 下 LE 4..9）会被新边界重新判成对手——侧判定翻转、按对手档取动画/着色，
	// 即"改对手键数后玩家箭头动画受影响"（改玩家键数不动 opp 边界，所以对手不受影响，现象不对称）。
	// oldDual=false（改前是 Psych/EK 编码）：侧判定固定为 noteData < oldPlr（不随小节），转新 LE 编码。
	function reencodeChartNotes(oldPlr:Int, oldOpp:Int, oldDual:Bool):Void
	{
		var newPlr:Int = dualPlayerKeyCount();
		var newOpp:Int = dualOpponentKeyCount();
		for (sec in PlayState.SONG.notes)
		{
			var secMustHit:Bool = sec.mustHitSection;
			for (note in sec.sectionNotes)
			{
				if (note == null || note.length < 2) continue;
				var d:Int = Std.int(note[1]);
				var isPlr:Bool;
				var col:Int;
				if (oldDual)
				{
					if (secMustHit) { isPlr = (d < oldPlr); col = isPlr ? d : (d - oldPlr); }
					else { isPlr = (d >= oldOpp); col = isPlr ? (d - oldOpp) : d; }
				}
				else
				{
					// Psych/EK 编码：0..oldPlr-1=玩家（固定，不随小节）、oldPlr..=对手
					isPlr = (d < oldPlr);
					col = d % oldPlr;
				}
				note[1] = isPlr ? (secMustHit ? col : newOpp + col) : (secMustHit ? newPlr + col : col);
			}
		}
	}

	function applySectionColumns(secNum:Int):Void
	{
		var cols = getSectionColumns(secNum);
		var mania = getSectionMania(secNum);
		// LE LTS 双侧：双侧下 colArray 按"当前编辑侧"的键数档位取（玩家侧=playerKeyCount-1、对手侧=keyCount-1），
		// 而非全局 SONG.mania（双侧谱面通常无 mania 字段，回退 4 键档会导致分侧编辑时轨道颜色错误）。
		if (isDualChart())
			mania = (editorSide == 0) ? (dualPlayerKeyCount() - 1) : (dualOpponentKeyCount() - 1);

		// Extra Keys：按 mania 档位从 extrakeys.json 填充每列的颜色前缀与 sing 动画名。
		// 4 键档位结果与原生硬编码完全一致（purple/blue/green/red + singLEFT/DOWN/UP/RIGHT）。
		ExtraKeysHandler.ensure();
		var newColArray:Array<String> = [];
		var newSingAnims:Array<String> = [];
		var ek = ExtraKeysHandler.instance.data;
		if (ek != null && ek.keys != null && ek.keys.length > mania) {
			var mode = ek.keys[mania];
			var laneCount:Int = (mode != null && mode.notes != null) ? mode.notes.length : cols;
			for (i in 0...laneCount) {
				var g:Int = (mode.notes != null && i < mode.notes.length) ? mode.notes[i] : i;
				var anim = (ek.animations != null && g >= 0 && g < ek.animations.length) ? ek.animations[g] : null;
				newColArray.push(anim != null ? anim.note : 'purple');
				newSingAnims.push(anim != null ? ('sing' + anim.sing) : 'singLEFT');
			}
		} else {
			// 兜底 4 键
			newColArray = ['purple', 'blue', 'green', 'red'];
			newSingAnims = ['singLEFT', 'singDOWN', 'singUP', 'singRIGHT'];
		}
		Note.colArray = newColArray;
		singAnimations = newSingAnims;

		// LE LTS 双侧：同步编辑器静态档位（供 Note/StrumNote 按侧取色与动画），
		// 并缓存玩家/对手两侧独立列配色（音符构造时按自身侧选用，避免跨侧取色错乱）。
		Note.editorDualMode = isDualChart();
		if (isDualChart())
		{
			Note.editorPlrKeys = dualPlayerKeyCount();
			Note.editorOppKeys = dualOpponentKeyCount();
			playerColArrayCache = buildColArrayForMania(dualPlayerKeyCount() - 1, dualPlayerKeyCount());
			opponentColArrayCache = buildColArrayForMania(dualOpponentKeyCount() - 1, dualOpponentKeyCount());
		}

		// LE LTS 双侧：GRID_COLUMNS_PER_PLAYER 主值 = 玩家侧列数（非双侧 = mania+1）；
		// 重建条件 = 两侧列数任一变化（编辑侧切换不再误触发重建，网格始终按两侧真实键数渲染）
		var pCols:Int = playerGridCols();
		var oCols:Int = opponentGridCols();
		if (pCols != _lastGridPlayerCols || oCols != _lastGridOpponentCols)
		{
			_lastGridPlayerCols = pCols;
			_lastGridOpponentCols = oCols;
			GRID_COLUMNS_PER_PLAYER = pCols;
			_rebuildingGrids = true;
			createGrids(); // 内部因 _rebuildingGrids 守护而不会递归调用 loadSection
			rebuildStrumLineNotes();
			resizeTrackOverlays();
			applyGridStripeColors();
			_rebuildingGrids = false;
		}
	}

	// 重建漩涡编辑器的静态箭头（LE LTS 双侧：玩家/对手按各自键数，不对称布局）
	function rebuildStrumLineNotes():Void
	{
		for (note in strumLineNotes) note.destroy();
		strumLineNotes.clear();
		var gridLayout = getGridLayout();

		var pCols:Int = playerGridCols();
		var oCols:Int = opponentGridCols();
		var total:Int = pCols + oCols;
		var startY:Float = FlxG.height / 2;
		for (i in 0...total)
		{
			var isPlayer:Bool = (i >= oCols); // 前 oCols 个为对手，后 pCols 个为玩家
			var noteData:Int = isPlayer ? (i - oCols) : i;
			var uiColumn:Int = isPlayer ? (noteData + oCols + EVENT_TRACK_COUNT) : noteData;

			var spacingOffset:Float = 0;
			if (uiColumn >= oCols) spacingOffset += TRACK_SPACING;
			if (uiColumn >= oCols + EVENT_TRACK_COUNT) spacingOffset += TRACK_SPACING;

			// player 参数必须按真实侧传（1=玩家、0=对手）：StrumNote.isPlayerSide()/按侧取档依赖它。
			// 原 Psych 残留全传 0 会把玩家 strums 也当对手，导致双侧下玩家 strums 用对手档着色与动画。
			var note:StrumNote = new StrumNote(gridLayout.startX + (GRID_SIZE * uiColumn) + spacingOffset, startY, noteData, isPlayer ? 1 : 0);
			// 制谱器 strums 只是可视化指示器（无真实输入）：isBotplayMode=true 让玩家位（player=1）的
			// confirm 动画也能像对手位一样计时自动恢复 static——否则受 autoResetStrumAnim 控制，
			// 默认关闭时玩家 strum 会一直停留在命中动画（Vortex 播放时可见）。
			note.isBotplayMode = true;
			note.scrollFactor.set();
			note.playAnim('static');
			note.alpha = 0.4;

			note.updateHitbox();
			if(note.width > note.height)
				note.setGraphicSize(GRID_SIZE);
			else
				note.setGraphicSize(0, GRID_SIZE);

			note.updateHitbox();
			note.x += GRID_SIZE/2 - note.width/2;
			note.y += GRID_SIZE/2 - note.height/2;
			strumLineNotes.add(note);
		}
	}

	// 网格列数变化时，按新的列数重新生成轨道底色块的宽度
	function resizeTrackOverlays():Void
	{
		if (playerTrackOverlay == null || opponentGridBg == null) return;
		var gridHeight:Float = opponentGridBg.height;
		var extraHeight:Int = 500;
		// LE LTS 双侧：对手/玩家色块按各自键数宽度
		opponentTrackOverlay.makeGraphic(GRID_SIZE * opponentGridCols(), Std.int(gridHeight) + extraHeight, 0xFFCC88FF);
		opponentTrackOverlay.alpha = 0.15;
		playerTrackOverlay.makeGraphic(GRID_SIZE * playerGridCols(), Std.int(gridHeight) + extraHeight, 0xFF88CCFF);
		playerTrackOverlay.alpha = 0.15;
	}

	// 为三块网格（对手 / Event / 玩家）重新着色条纹（LE LTS 双侧：条纹范围按各自键数）
	function applyGridStripeColors():Void
	{
		if (opponentGridBg == null) return;
		var oCols:Int = opponentGridCols();
		var pCols:Int = playerGridCols();
		for (i in 0...oCols)
			opponentGridBg.stripe.color = 0xFFFF4488; // 对手：红色
		if (SHOW_EVENT_COLUMN)
		{
			for (i in oCols...(oCols + EVENT_TRACK_COUNT))
				eventGridBg.stripe.color = 0xFFFFFF44; // Event：黄色
		}
		for (i in (oCols + EVENT_TRACK_COUNT)...(oCols + EVENT_TRACK_COUNT + pCols))
			playerGridBg.stripe.color = 0xFF4488FF; // 玩家：蓝色
	}

	// 获取指定位置的轨道信息和网格
	function getTrackAtPosition(x:Float, y:Float):{grid:ChartingGridSprite, prevGrid:ChartingGridSprite, nextGrid:ChartingGridSprite, trackX:Float, trackType:String}
	{
		var gridLayout = getGridLayout();
		var opponentWidth:Float = GRID_SIZE * opponentGridCols();
		var eventWidth:Float = SHOW_EVENT_COLUMN ? GRID_SIZE * EVENT_TRACK_COUNT : 0;
		var playerWidth:Float = GRID_SIZE * playerGridCols();

		if(x >= gridLayout.opponentX && x < gridLayout.opponentX + opponentWidth)
		{
			return {
				grid: opponentGridBg,
				prevGrid: prevOpponentGridBg,
				nextGrid: nextOpponentGridBg,
				trackX: gridLayout.opponentX,
				trackType: 'opponent'
			};
		}
		else if(SHOW_EVENT_COLUMN && x >= gridLayout.eventX && x < gridLayout.eventX + eventWidth)
		{
			return {
				grid: eventGridBg,
				prevGrid: prevEventGridBg,
				nextGrid: nextEventGridBg,
				trackX: gridLayout.eventX,
				trackType: 'event'
			};
		}
		else if(x >= gridLayout.playerX && x < gridLayout.playerX + playerWidth)
		{
			return {
				grid: playerGridBg,
				prevGrid: prevPlayerGridBg,
				nextGrid: nextPlayerGridBg,
				trackX: gridLayout.playerX,
				trackType: 'player'
			};
		}

		return null;
	}

	var cachedSectionRow:Array<Int>;
	var cachedSectionTimes:Array<Float>;
	var cachedSectionCrochets:Array<Float>;
	var cachedSectionBPMs:Array<Float>;
	function loadChart(song:SwagSong)
	{
		PlayState.SONG = song;
		StageData.loadDirectory(PlayState.SONG);
		Conductor.bpm = PlayState.SONG.bpm;
		Conductor.mapBPMChanges(PlayState.SONG);
	}

	function loadMusic(?killAudio:Bool = false)
	{
		setSongPlaying(false);
		var time:Float = Conductor.songPosition;

		// 让音频从真正包含该歌曲的模组目录解析，避免模组沿用 funkin 曲名时误加载 funkin 内置资源。
		// 逻辑与 PlayState 一致：优先用当前模组目录，缺失再扫描所有模组；用 loadSongAudio（不回退 funkin）判定。
		var prevModDir:String = Mods.currentModDirectory;
		var songModDir:String = Mods.currentModDirectory;
		function modHasAudio(mod:String, song:String, fileBase:String):Bool
		{
			return Paths.loadSongAudio(song, fileBase, mod) != null;
		}
		// 探测某 mod 是否含有该曲音频：含 SpecialInst/SpecialVocal 的带后缀文件也算（与 FreeplayState 一致）。
		function modHasSong(mod:String, song:String):Bool
		{
			var si:String = (PlayState.SONG.specialInst != null && PlayState.SONG.specialInst.length > 0) ? PlayState.SONG.specialInst : null;
			var sv:String = (PlayState.SONG.specialVocal != null && PlayState.SONG.specialVocal.length > 0) ? PlayState.SONG.specialVocal : null;
			if (modHasAudio(mod, song, 'Inst') || modHasAudio(mod, song, 'Voices')) return true;
			if (si != null && modHasAudio(mod, song, 'Inst-$si')) return true;
			if (sv != null && modHasAudio(mod, song, 'Voices-$sv')) return true;
			return false;
		}
		#if MODS_ALLOWED
		// 优先当前模组目录（与 PlayState 的 _lastLoadedModDirectory 语义一致），缺失再扫描所有模组以兜底同名曲冲突。
		if (!modHasSong(songModDir, PlayState.SONG.song))
		{
			songModDir = '';
			for (mod in Mods.getModDirectories())
			{
				if (modHasSong(mod, PlayState.SONG.song))
				{
					songModDir = mod;
					break;
				}
			}
		}
		#end
		Mods.currentModDirectory = songModDir;

		if(killAudio)
		{
			var sndsToKill:Array<String> = [];
			for (key => snd in Paths.currentTrackedSounds)
			{
				//trace(key, snd);
				if(key.contains('/songs/${Paths.formatToSongPath(PlayState.SONG.song)}/') && snd != null)
				{
					sndsToKill.push(key);
					snd.close();
				}
			}

			for (key in sndsToKill)
			{
				Assets.cache.clear(key);
				OpenFlAssets.cache.clear(key);
				Paths.currentTrackedSounds.remove(key);
				Paths.localTrackedAssets.remove(key);
			}
		}

		try
		{
			var instFileBase:String = (PlayState.SONG.specialInst != null && PlayState.SONG.specialInst.length > 0) ? 'Inst-${PlayState.SONG.specialInst}' : 'Inst';
				FlxG.sound.playMusic(Paths.loadSongAudio(PlayState.SONG.song, instFileBase, songModDir), 0);
			FlxG.sound.music.pause();
			FlxG.sound.music.time = time;
			FlxG.sound.music.onComplete = (function() songFinished = true);
		}
		catch(e:Exception)
		{
			FlxG.log.error('Error loading song: $e');
			Mods.currentModDirectory = prevModDir;
			return;
		}

		@:privateAccess vocals.cleanup(true);
		@:privateAccess opponentVocals.cleanup(true);
		if (PlayState.SONG.needsVoices)
		{
			try
			{
				// Inst 与人声统一从 songModDir 用 loadSongAudio 加载（不回退 funkin，缺失即 null）；
				// 优先：角色指定(postfix) > Voices-Player / Voices-Opponent > 无后缀合并 Voices
				function tryVoices(postfix:String):Sound
				{
					var fileBase:String = 'Voices';
					if (postfix != null) fileBase += '-' + postfix;
					// 追加 SpecialVocal 后缀，与 Inst 的 specialInst 对称：
					// 优先 Voices-{角色}-SpecialVocal > Voices-Player/Opponent-SpecialVocal > Voices-SpecialVocal，命中即止（任一存在即可）。
					if (PlayState.SONG.specialVocal != null && PlayState.SONG.specialVocal.length > 0)
						fileBase += '-' + PlayState.SONG.specialVocal;
					return Paths.loadSongAudio(PlayState.SONG.song, fileBase, songModDir);
				}

				// 加载玩家vocal
				var playerVocalName:String = characterData.vocalsP1;
				trace('Loading player vocal: name=$playerVocalName, specialVocal=${PlayState.SONG.specialVocal}');
				var playerVocals:Sound = tryVoices(playerVocalName);
				trace('Player vocal result: ${playerVocals != null ? "found" : "not found"}');
				
				// 如果指定的vocal不存在，尝试使用Player
				if (playerVocals == null) {
					trace('Trying Player fallback...');
					playerVocals = tryVoices('Player');
					trace('Player fallback result: ${playerVocals != null ? "found" : "not found"}');
				}
				
				// 如果Player也不存在，使用默认voices
				if (playerVocals != null) {
					vocals.loadEmbedded(playerVocals);
				} else {
					trace('Using default voices...');
					vocals.loadEmbedded(tryVoices(null));
				}
				vocals.volume = 0;
				vocals.play();
				vocals.pause();
				vocals.time = time;
				
				// 加载对手vocal
				var oppVocalName:String = characterData.vocalsP2;
				trace('Loading opponent vocal: name=$oppVocalName, specialVocal=${PlayState.SONG.specialVocal}');
				var oppVocals:Sound = tryVoices(oppVocalName);
				trace('Opponent vocal result: ${oppVocals != null ? "found" : "not found"}');
				
				// 如果指定的vocal不存在，尝试使用Opponent
				if (oppVocals == null) {
					trace('Trying Opponent fallback...');
					oppVocals = tryVoices('Opponent');
					trace('Opponent fallback result: ${oppVocals != null ? "found" : "not found"}');
				}
				
				// 如果找到vocal文件，加载它
				if(oppVocals != null)
				{
					opponentVocals.loadEmbedded(oppVocals);
					opponentVocals.volume = 0;
					opponentVocals.play();
					opponentVocals.pause();
					opponentVocals.time = time;
				}
			}
			catch (e:Dynamic) {}
		}
		Mods.currentModDirectory = prevModDir;

		#if DISCORD_ALLOWED
		DiscordClient.changePresence('Chart Editor', 'Song: ' + PlayState.SONG.song);
		#end

		updateAudioVolume();
		setPitch();
		_cacheSections();
		updateWaveform();
	}

	function onSongComplete()
	{
		trace('song completed');
		setSongPlaying(false);
		Conductor.songPosition = FlxG.sound.music.time = vocals.time = opponentVocals.time = FlxG.sound.music.length - 1;
		curSec = PlayState.SONG.notes.length - 1;
		forceDataUpdate = true;
	}

	function updateAudioVolume()
	{
		FlxG.sound.music.volume = instVolumeStepper.value;
		vocals.volume = playerVolumeStepper.value;
		opponentVocals.volume = opponentVolumeStepper.value;
		if(instMuteCheckBox.checked) FlxG.sound.music.volume = 0;
		if(playerMuteCheckBox.checked) vocals.volume = 0;
		if(opponentMuteCheckBox.checked) opponentVocals.volume = 0;
	}

	var playbackRate:Float = 1;
	function setPitch(?value:Null<Float>)
	{
		#if FLX_PITCH
		if(value == null) value = playbackRate;
		FlxG.sound.music.pitch = value;
		vocals.pitch = value;
		opponentVocals.pitch = value;
		#end
	}

	function setSongPlaying(doPlay:Bool)
	{
		if(FlxG.sound.music == null) return;

		vocals.time = FlxG.sound.music.time;
		opponentVocals.time = FlxG.sound.music.time;

		if(doPlay)
		{
			FlxG.sound.music.play();
			if(FlxG.sound.music.time < vocals.length) vocals.play(true, FlxG.sound.music.time);
			if(FlxG.sound.music.time < opponentVocals.length) opponentVocals.play(true, FlxG.sound.music.time);
			updateAudioVolume();
		}
		else
		{
			FlxG.sound.music.pause();
			vocals.pause();
			opponentVocals.pause();
		}

		for (note in strumLineNotes)
		{
			note.alpha = doPlay ? 1 : 0.4;
			if(!doPlay)
			{
				note.playAnim('static');
				note.resetAnim = 0;
			}
		}
	}

	function reloadNotes()
	{
		// 在创建音符前先同步颜色前缀与网格列数（固定 4 键）。
		applySectionColumns(curSec);
		selectedNotes = [];
		for (note in notes) if(note != null) note.destroy();
		for (event in events) if(event != null) event.destroy();
		notes = [];
		events = [];
		undoActions = [];
		
		preloadedNoteData = [];
		preloadedSecNum = [];
		preloadedMetaNotes = [];

		useOptimizedLoading = resolveOptimizedLoading();
		trace('[OptimizedNoteLoading] ChartingState → ' + (useOptimizedLoading ? 'OPTIMIZED' : 'LEGACY'));

		if (useOptimizedLoading)
		{
			// 优化模式：只预保存数据
			for (secNum => section in PlayState.SONG.notes)
				for (note in section.sectionNotes)
					if(note != null)
					{
						preloadedNoteData.push(note);
						preloadedSecNum.push(secNum);
						preloadedMetaNotes.push(null); // 预留位置，后面才创建 MetaNote
					}

			trace('Optimized mode: preloaded ${preloadedNoteData.length} notes, no MetaNotes created yet');
		}
		else
		{
			// 传统模式：立即创建所有 MetaNote
			for (secNum => section in PlayState.SONG.notes)
				for (note in section.sectionNotes)
					if(note != null)
						notes.push(createNote(note, secNum));
		}

		for (eventNum => event in PlayState.SONG.events)
			if(event != null && (cachedSectionTimes.length < 1 || event[0] < cachedSectionTimes[cachedSectionTimes.length-1])) //dont spawn events over the time limit
				events.push(createEvent(event));

		notes.sort(PlayState.sortByTime);
		events.sort(PlayState.sortByTime);

		trace('Note count: ${notes.length}');
		trace('Events count: ${events.length}');
		loadSection();
	}

	function createNote(note:Dynamic, ?secNum:Null<Int> = null)
	{
		if(secNum == null) secNum = curSec;
		var section = PlayState.SONG.notes[secNum];

		// 用音符所属小节的列数解码 note[1]，避免按当前显示小节的列数误判归属。
		var cols:Int = getSectionColumns(secNum);
		var daStrumTime:Float = note[0];
		// LE LTS 双侧：note[1] 是 LE 连续编号（mustHit 小节 0..plr-1=玩家/plr..=对手；非 mustHit 小节 0..opp-1=对手/opp..=玩家），
		// 不能按编辑侧键数取模——否则非 mustHit 小节玩家音符（opp..opp+plr-1）与对手音符会被错误折叠进玩家列区。
		// 非双侧：Psych 编码（0..cols-1=玩家/cols..=对手），取模得到侧内列。
		var daNoteData:Int = isDualChart() ? Std.int(note[1]) : Std.int(note[1] % cols);
		// LE LTS 双侧（分侧编辑）：mustPress 按音符真实侧判定（LE 连续编号 + 所属小节 mustHit），
		// 而非编辑侧统一标记——否则非 mustHit 小节/对手区音符会被误标为玩家，
		// 播放预览时对手音符命中却触发玩家角色 sing、打击音错侧。
		// 非双侧：Psych 编码（note[1] < cols 即玩家）。
		var gottaHitNote:Bool = isDualChart() ? isPlayerNoteByData(Std.int(note[1]), section.mustHitSection) : (note[1] < cols);

		var swagNote:MetaNote = new MetaNote(daStrumTime, daNoteData, note);
		swagNote.editorSection = secNum; // 记录所属小节（自动播放角色动画按小节 mustHit 解析双侧 LE 编号）
		swagNote.mustPress = gottaHitNote;
		swagNote.setSustainLength(note[2], cachedSectionCrochets[secNum] / 4, curZoom);
		swagNote.gfNote = (section.gfSection && gottaHitNote == section.mustHitSection);
		swagNote.noteType = note[3];
		swagNote.scrollFactor.x = 0;
		var txt:FlxText = swagNote.findNoteTypeText(swagNote.noteType != null ? noteTypes.indexOf(swagNote.noteType) : 0);
		if(txt != null) txt.visible = showNoteTypeLabels;

		swagNote.updateHitbox();
		if(swagNote.width > swagNote.height)
			swagNote.setGraphicSize(GRID_SIZE);
		else
			swagNote.setGraphicSize(0, GRID_SIZE);

		swagNote.updateHitbox();
		swagNote.active = false;

		// LE LTS 双侧：按音符真实侧（LE 编号 + 所属小节 mustHit）设置列配色数组与生成档位，
		// 使动画帧（noteColArray）与着色（getStyleIndex → genMania/genOppMania）一致。
		// 否则双侧谱面跨两侧渲染时，取色/动画全按"当前编辑侧"档（PlayState.instance 为 null），
		// 出现"玩家箭头一个动画不同着色、对手多键错色错帧"类问题。
		if (isDualChart())
		{
			var secMustHit:Bool = section.mustHitSection;
			var isPlrNote:Bool = isPlayerNoteByData(daNoteData, secMustHit);
			swagNote.editorSideNote = isPlrNote ? 0 : 1;
			swagNote.noteColArray = isPlrNote ? playerColArrayCache : opponentColArrayCache;
			swagNote.genMania = dualPlayerKeyCount() - 1;
			swagNote.genOppMania = dualOpponentKeyCount() - 1;
			// 侧内列：LE 连续编号按小节 mustHit 换算（玩家 mustHit=编号 / 非 mustHit=编号-对手键数；对手对称）。
			// colAt/getStyleIndex 用此侧内列取色/查表，避免非 mustHit 小节玩家音符（LE=opp+col）取模错位。
			var plrSide:Int = dualPlayerKeyCount();
			var oppSide:Int = dualOpponentKeyCount();
			swagNote.sideNoteData = isPlrNote ? (secMustHit ? daNoteData : (daNoteData - oppSide)) : (secMustHit ? (daNoteData - plrSide) : daNoteData);
			if (swagNote.sideNoteData < 0) swagNote.sideNoteData = 0;
			// 构造时已按 SONG.mania 档取色/播帧，双侧需按真实侧刷新（补注册动画帧 + 重绑 shader + 重着色）
			swagNote.refreshNoteVisual();
		}

		positionNoteXByData(swagNote, null, cols);
		positionNoteYOnTime(swagNote, secNum);
		return swagNote;
	}

	function createEvent(event:Dynamic, ?preferredTrackIndex:Null<Int> = null)
	{
		var daStrumTime:Float = event[0];

		var trackIndex:Int = 0;
		if (preferredTrackIndex != null && preferredTrackIndex >= 0 && preferredTrackIndex < EVENT_TRACK_COUNT)
		{
			// 如果指定了首选轨道索引，检查该轨道在该时间点是否已有事件
			var isPreferredTrackAvailable:Bool = true;
			for (existingEvent in events)
			{
				if (Math.abs(existingEvent.strumTime - daStrumTime) < 0.0001 && existingEvent.eventTrackIndex == preferredTrackIndex)
				{
					isPreferredTrackAvailable = false;
					break;
				}
			}
			
			if (isPreferredTrackAvailable)
			{
				trackIndex = preferredTrackIndex;
			}
			else
			{
				// 首选轨道已被占用，分配到其他可用轨道
				var eventsAtTime:Int = 0;
				for (existingEvent in events)
				{
					if (Math.abs(existingEvent.strumTime - daStrumTime) < 0.0001)
					{
						eventsAtTime++;
					}
				}
				trackIndex = eventsAtTime % EVENT_TRACK_COUNT;
			}
		}
		else
		{
			// 没有指定首选轨道，按原有逻辑分配
			var eventsAtTime:Int = 0;
			for (existingEvent in events)
			{
				if (Math.abs(existingEvent.strumTime - daStrumTime) < 0.0001)
				{
					eventsAtTime++;
				}
			}
			trackIndex = eventsAtTime % EVENT_TRACK_COUNT;
		}

		var swagEvent:EventMetaNote = new EventMetaNote(daStrumTime, event, trackIndex);
		swagEvent.scrollFactor.x = 0;
		swagEvent.active = false;

		var secNum:Int = 0;
		for (i in 1...cachedSectionTimes.length)
		{
			if(cachedSectionTimes[i] > daStrumTime) break;
			secNum++;
		}
		positionNoteYOnTime(swagEvent, secNum);
		positionEventOnTrack(swagEvent, trackIndex);
		return swagEvent;
	}

	function positionEventOnTrack(event:EventMetaNote, trackIndex:Int)
	{
		// 轨道布局：对手(0-3) → Event(4-7) → 玩家(8-11)
		// Event轨道的起始偏移（LE LTS 双侧：对手区列数 = 对手侧键数）
		var eventTrackOffset:Int = opponentGridCols();
		var gridLayout = getGridLayout();

		var eventX:Float = gridLayout.startX + (GRID_SIZE - event.width) / 2;
		eventX += GRID_SIZE * eventTrackOffset;
		eventX += TRACK_SPACING; // Event轨道的间距偏移
		eventX += GRID_SIZE * trackIndex;
		event.x = eventX;
		event.eventText.x = event.x - event.eventText.width - 10;
	}

	function _cacheSections()
	{
		cachedSectionRow = [];
		cachedSectionTimes = [];
		cachedSectionCrochets = [];
		cachedSectionBPMs = [];

		if(PlayState.SONG == null)
		{
			cachedSectionRow.push(0);
			cachedSectionTimes.push(0);
			cachedSectionCrochets.push(0);
			cachedSectionBPMs.push(0);
			return;
		}

		// 修正每段的 sectionBeats（与 mapBPMChanges 保持一致）
		for (section in PlayState.SONG.notes)
		{
			var secs:Null<Float> = cast section.sectionBeats;
			if(secs == null || Math.isNaN(secs) || secs <= 0) section.sectionBeats = 4;
		}

		// 先构建支持线性 BPM 过渡的 BPM 映射（与 BPM 无关，只依赖 sectionBeats）
		Conductor.mapBPMChanges(PlayState.SONG);
		// 确保全局基础 BPM 复位为歌曲基准（mapBPMChanges 已处理，这里再保险一次，
		// 避免从 PlayState 返回时遗留的瞬时 BPM 污染 makeDefault 计算的段位置）
		Conductor.bpm = PlayState.SONG.bpm;

		var bpm:Float = PlayState.SONG.bpm;
		var reachedLimit:Bool = false;
		var row:Int = 0;
		for (secNum => section in PlayState.SONG.notes)
		{
			// 进入本段时的 BPM（= 本段起点 BPM），作为该段“编辑用 BPM”，
			// 这样网格显示、音符放置、Conductor.bpm 三者一致；ramp 段也用起点 BPM，
			// 跳回前面小节时 Conductor.bpm 能正确回退到之前的 BPM。
			var startBpm:Float = bpm;
			if(section.changeBPM && section.bpm != null) bpm = section.bpm;

			cachedSectionRow.push(row);
			var startTime:Float = Conductor.getTimeFromStep(row);
			cachedSectionTimes.push(startTime);

			// 用“段起点”的 crochet / BPM，使网格与放置一致（ramp 段起点 BPM 即 startBpm）
			var seg = Conductor.getBPMFromStep(row);
			cachedSectionCrochets.push(seg.stepCrochet * 4);
			cachedSectionBPMs.push(startBpm);

			var rowRound:Int = Math.round(4 * section.sectionBeats);
			var endTime:Float = Conductor.getTimeFromStep(row + rowRound);
			row += rowRound;

			for (note in section.sectionNotes)
			{
				if(secNum > 0 && note[0] < startTime) note[0] = startTime;
				else if(secNum < PlayState.SONG.notes.length && note[0] >= endTime - 0.000001) note[0] = endTime - 0.000001;
			}

			if(FlxG.sound.music != null && endTime >= FlxG.sound.music.length)
			{
				var lastSectionNum:Int = PlayState.SONG.notes.length - 1;
				if(secNum < lastSectionNum) //Delete extra sections
				{
					while(PlayState.SONG.notes.length - 1 > secNum)
					{
						PlayState.SONG.notes.pop();
					}
	
					trace('breaking at section $secNum');
					reachedLimit = true;
					break;
				}
				else if(secNum == lastSectionNum)
				{
					trace('reached limit at section $secNum');
					reachedLimit = true;
				}
			}
		}

		if(FlxG.sound.music != null && !reachedLimit) //Created sections to fill blank space
		{
			var lastSection = PlayState.SONG.notes[PlayState.SONG.notes.length-1];
			var sectionBeats:Float = lastSection != null ? lastSection.sectionBeats : 4;
			var rowRound:Int = Math.round(4 * sectionBeats);
			var mustHitSec:Bool = lastSection != null ? lastSection.mustHitSection : true;
			var changeBpmSec:Bool = lastSection != null ? lastSection.changeBPM : false;
			var bpmVal:Float = (lastSection != null && lastSection.bpm != null) ? lastSection.bpm : bpm;
			var altAnimSec:Bool = lastSection != null ? lastSection.altAnim : false;
			var gfSec:Bool = lastSection != null ? lastSection.gfSection : false;

			while(!reachedLimit)
			{
				PlayState.SONG.notes.push({
					sectionNotes: [],
					sectionBeats: sectionBeats,
					mustHitSection: mustHitSec,
					bpm: bpmVal,
					changeBPM: changeBpmSec,
					altAnim: altAnimSec,
					gfSection: gfSec
				});

			cachedSectionRow.push(row);
			cachedSectionTimes.push(Conductor.getTimeFromStep(row));
			var seg2 = Conductor.getBPMFromStep(row);
			cachedSectionCrochets.push(seg2.stepCrochet * 4);
			cachedSectionBPMs.push(bpm); // 用当前运行 BPM（= 进入本段起点 BPM）保持一致

				var endTime:Float = Conductor.getTimeFromStep(row + rowRound);
				row += rowRound;

				if(endTime >= FlxG.sound.music.length)
				{
					trace('created sections until ${PlayState.SONG.notes.length-1}');
					reachedLimit = true;
				}
			}
		}
		cachedSectionRow.push(row);
		cachedSectionTimes.push(Conductor.getTimeFromStep(row));
	}

	var showPreviousSection:Bool = true;
	var showNextSection:Bool = true;
	var showNoteTypeLabels:Bool = true;
	var forceDataUpdate:Bool = true;
	function loadSection(?sec:Null<Int> = null)
	{
		if(sec != null) curSec = sec;
		curSec = Std.int(FlxMath.bound(curSec, 0, PlayState.SONG.notes.length-1));
		// 同步当前小节的列数 / 颜色前缀 / 网格（固定 4 键）
		applySectionColumns(curSec);
		Conductor.bpm = cachedSectionBPMs[curSec];

		var hei:Float = 0;

		// 更新对手轨道网格
		if(curSec > 0)
		{
			prevOpponentGridBg.y = cachedSectionRow[curSec-1] * GRID_SIZE * curZoom;
			prevOpponentGridBg.rows = 4 * PlayState.SONG.notes[curSec-1].sectionBeats * curZoom;
			prevOpponentGridBg.visible = showPreviousSection;
			hei += prevOpponentGridBg.height;
			eventLockOverlay.y = prevOpponentGridBg.y;
		}
		else prevOpponentGridBg.visible = false;

		if(curSec < PlayState.SONG.notes.length - 1)
		{
			nextOpponentGridBg.y = cachedSectionRow[curSec+1] * GRID_SIZE * curZoom;
			nextOpponentGridBg.rows = 4 * PlayState.SONG.notes[curSec+1].sectionBeats * curZoom;
			nextOpponentGridBg.visible = showNextSection;
			hei += nextOpponentGridBg.height;
		}
		else nextOpponentGridBg.visible = false;

		opponentGridBg.y = cachedSectionRow[curSec] * GRID_SIZE * curZoom;
		opponentGridBg.rows = 4 * PlayState.SONG.notes[curSec].sectionBeats * curZoom;
		hei += opponentGridBg.height;

		// 更新Event轨道网格
		if(SHOW_EVENT_COLUMN)
		{
			if(curSec > 0)
			{
				prevEventGridBg.y = cachedSectionRow[curSec-1] * GRID_SIZE * curZoom;
				prevEventGridBg.rows = 4 * PlayState.SONG.notes[curSec-1].sectionBeats * curZoom;
				prevEventGridBg.visible = showPreviousSection;
			}
			else prevEventGridBg.visible = false;

			if(curSec < PlayState.SONG.notes.length - 1)
			{
				nextEventGridBg.y = cachedSectionRow[curSec+1] * GRID_SIZE * curZoom;
				nextEventGridBg.rows = 4 * PlayState.SONG.notes[curSec+1].sectionBeats * curZoom;
				nextEventGridBg.visible = showNextSection;
			}
			else nextEventGridBg.visible = false;

			eventGridBg.y = cachedSectionRow[curSec] * GRID_SIZE * curZoom;
			eventGridBg.rows = 4 * PlayState.SONG.notes[curSec].sectionBeats * curZoom;
		}

		// 更新玩家轨道网格
		if(curSec > 0)
		{
			prevPlayerGridBg.y = cachedSectionRow[curSec-1] * GRID_SIZE * curZoom;
			prevPlayerGridBg.rows = 4 * PlayState.SONG.notes[curSec-1].sectionBeats * curZoom;
			prevPlayerGridBg.visible = showPreviousSection;
		}
		else prevPlayerGridBg.visible = false;

		if(curSec < PlayState.SONG.notes.length - 1)
		{
			nextPlayerGridBg.y = cachedSectionRow[curSec+1] * GRID_SIZE * curZoom;
			nextPlayerGridBg.rows = 4 * PlayState.SONG.notes[curSec+1].sectionBeats * curZoom;
			nextPlayerGridBg.visible = showNextSection;
		}
		else nextPlayerGridBg.visible = false;

		playerGridBg.y = cachedSectionRow[curSec] * GRID_SIZE * curZoom;
		playerGridBg.rows = 4 * PlayState.SONG.notes[curSec].sectionBeats * curZoom;

		// 更新轨道颜色覆盖层的位置和高度
		var gridLayout = getGridLayout();
		var gridY:Float = 0;
		var extraHeight:Int = 500;
		
		if(playerTrackOverlay != null && opponentTrackOverlay != null)
		{
			opponentTrackOverlay.x = gridLayout.opponentX;
			opponentTrackOverlay.y = gridY;
			opponentTrackOverlay.height = Std.int(opponentGridBg.height) + extraHeight;
			
			playerTrackOverlay.x = gridLayout.playerX;
			playerTrackOverlay.y = gridY;
			playerTrackOverlay.height = Std.int(opponentGridBg.height) + extraHeight;
			
			if(eventTrackOverlay != null)
			{
				eventTrackOverlay.x = gridLayout.eventX;
				eventTrackOverlay.y = gridY;
				eventTrackOverlay.height = Std.int(opponentGridBg.height) + extraHeight;
			}
		}

		if(!prevOpponentGridBg.visible) eventLockOverlay.y = opponentGridBg.y;
		eventLockOverlay.scale.y = hei;
		// 更新事件锁定覆盖层的X位置，确保它始终在Event轨道上
		eventLockOverlay.x = SHOW_EVENT_COLUMN ? gridLayout.eventX : gridLayout.opponentX;
		eventLockOverlay.updateHitbox();

		softReloadNotes();
		updateHeads();

		var sec = getCurChartSection();
		if(sec != null)
		{
			mustHitCheckBox.checked = sec.mustHitSection;
			gfSectionCheckBox.checked = sec.gfSection;
			altAnimSectionCheckBox.checked = sec.altAnim;
		changeBpmCheckBox.checked = sec.changeBPM;
		// changeBPM 段显示“目标 BPM”（编辑用）；其它段显示当前段编辑用 BPM（已随起点 BPM 正确回退）
		changeBpmStepper.value = (sec.changeBPM && sec.bpm != null) ? sec.bpm : Conductor.bpm;
		bpmRampStepper.value = (sec.bpmRamp != null) ? sec.bpmRamp : 0;
		beatsPerSecStepper.value = sec.sectionBeats;

			strumTimeStepper.step = Conductor.stepCrochet;
			susLengthStepper.step = cachedSectionCrochets[curSec] / 4 / 2;
			susLengthStepper.max = susLengthStepper.step * 128;
			if(selectedNotes.length > 1) susLengthStepper.min = -susLengthStepper.max;
			else susLengthStepper.min = 0;
		}
		opponentGridBg.vortexLineEnabled = playerGridBg.vortexLineEnabled = vortexEnabled;
		prevOpponentGridBg.vortexLineEnabled = prevPlayerGridBg.vortexLineEnabled = vortexEnabled;
		nextOpponentGridBg.vortexLineEnabled = nextPlayerGridBg.vortexLineEnabled = vortexEnabled;
		opponentGridBg.vortexLineSpace = playerGridBg.vortexLineSpace = GRID_SIZE * 4 * curZoom;
		prevOpponentGridBg.vortexLineSpace = prevPlayerGridBg.vortexLineSpace = GRID_SIZE * 4 * curZoom;
		nextOpponentGridBg.vortexLineSpace = nextPlayerGridBg.vortexLineSpace = GRID_SIZE * 4 * curZoom;

		if(SHOW_EVENT_COLUMN)
		{
			eventGridBg.vortexLineEnabled = vortexEnabled;
			prevEventGridBg.vortexLineEnabled = vortexEnabled;
			nextEventGridBg.vortexLineEnabled = vortexEnabled;
			eventGridBg.vortexLineSpace = GRID_SIZE * 4 * curZoom;
			prevEventGridBg.vortexLineSpace = GRID_SIZE * 4 * curZoom;
			nextEventGridBg.vortexLineSpace = GRID_SIZE * 4 * curZoom;
		}

		updateWaveform();
	}

	function softReloadNotes(onlyCurrent:Bool = false)
	{
		if(!onlyCurrent) behindRenderedNotes.clear();
		curRenderedNotes.clear();

		var minTime:Float = getMinNoteTime(curSec);
		var maxTime:Float = getMaxNoteTime(curSec);
		function curSecFilter(note:MetaNote)
		{
			return (note.strumTime >= minTime && note.strumTime < maxTime);
		}

		// 优化模式：先创建需要的 MetaNote
		if (useOptimizedLoading)
		{
			var secToCheck = [curSec];
			if (!onlyCurrent && (showPreviousSection || showNextSection))
			{
				if (showPreviousSection && curSec > 0) secToCheck.push(curSec - 1);
				if (showNextSection && curSec < PlayState.SONG.notes.length - 1) secToCheck.push(curSec + 1);
			}

			for (i in 0...preloadedNoteData.length)
			{
				var secForNote = preloadedSecNum[i];
				var shouldCreate = false;
				for (s in secToCheck)
				{
					if (secForNote == s)
					{
						shouldCreate = true;
						break;
					}
				}

				if (shouldCreate && preloadedMetaNotes[i] == null)
				{
					// 创建 MetaNote
					var newNote = createNote(preloadedNoteData[i], secForNote);
					preloadedMetaNotes[i] = newNote;
					notes.push(newNote);
				}
			}
			
			notes.sort(PlayState.sortByTime);
		}

		var firstNote:Bool = false;
		var firstEvent:Bool = false;
		sectionFirstNoteID = 0;
		sectionFirstEventID = 0;
		for (num => note in notes)
		{
			if(note != null && curSecFilter(note))
			{
				if(!firstNote) sectionFirstNoteID = num;
				// 当前小节的音符按当前网格重新定位 X，保证导航后列号正确对齐。
				positionNoteXByData(note);
				curRenderedNotes.add(note);
				note.alpha = (note.strumTime >= Conductor.songPosition) ? 1 : 0.6;
				if(note.hasSustain) note.updateSustainToZoom(cachedSectionCrochets[curSec] / 4, curZoom);
			}
		}

		if(SHOW_EVENT_COLUMN)
		{
			for (num => event in events)
			{
				if(event != null && curSecFilter(event))
				{
					if(!firstEvent) sectionFirstEventID = num;
					curRenderedNotes.add(event);
					event.alpha = (event.strumTime >= Conductor.songPosition) ? 1 : 0.6;
					event.eventText.visible = true;
				}
			}
		}

		if(!onlyCurrent)
		{
			if(showPreviousSection || showNextSection)
			{
				var prevMinTime:Float = getMinNoteTime(curSec-1);
				var prevMaxTime:Float = getMaxNoteTime(curSec-1);
				var nextMinTime:Float = getMinNoteTime(curSec+1);
				var nextMaxTime:Float = getMaxNoteTime(curSec+1);
				function otherSecFilter(note:MetaNote)
				{
					return (prevOpponentGridBg.visible && (note.strumTime >= prevMinTime && note.strumTime < prevMaxTime)) ||
						(nextOpponentGridBg.visible && (note.strumTime >= nextMinTime && note.strumTime < nextMaxTime));
				}
	
				for(note in notes.filter(otherSecFilter))
				{
					behindRenderedNotes.add(note);
					note.alpha = 0.4;
					if(note.hasSustain) note.updateSustainToZoom(cachedSectionCrochets[curSec] / 4, curZoom);
				}

				if(SHOW_EVENT_COLUMN)
				{
					for(event in events.filter(otherSecFilter))
					{
						behindRenderedNotes.add(event);
						event.alpha = 0.4;
						event.eventText.visible = false;
					}
				}
			}
		}
		// 叠加标记：按当前小节渲染的音符/事件统计同格数量，>1 时在格子右下角显示 xN
		updateOverlapMarkers();
		// 去重按钮：无重复时自动隐藏
		refreshDedupeButtons();
	}

	// 叠加标记：统计当前小节渲染音符/事件中"同一网格行（步）+ 同一 UI 列/事件轨"的数量，
	// 数量 > 1 时在该格子右下角显示 "xN"（文本右缘/底缘贴格线）；标记层 add 在箭头之上。
	// 允许重叠（复制粘贴等产生的同格多音符），仅作视觉提示，不阻止、不清理。
	function updateOverlapMarkers():Void
	{
		if (overlapMarkers == null) return;
		overlapMarkers.clear();

		var gl = getGridLayout();
		var counts:Map<String, Int> = [];
		var samples:Map<String, MetaNote> = [];
		for (note in curRenderedNotes)
		{
			if (note == null || !note.exists) continue;
			var row:Int = Math.round(note.chartY / (GRID_SIZE * curZoom));
			var key:String;
			if (!note.isEvent)
			{
				var uiCol:Int = noteDataToUIColumn(note.songData[1]);
				if (uiCol < 0) continue; // 事件列占位等无效列
				key = row + '|' + uiCol;
			}
			else
			{
				var ev:EventMetaNote = cast note;
				key = row + '|ev' + ev.eventTrackIndex;
			}
			if (counts.exists(key)) counts.set(key, counts.get(key) + 1);
			else counts.set(key, 1);
			if (samples.get(key) == null) samples.set(key, note);
		}

		for (key in counts.keys())
		{
			var cnt:Int = counts.get(key);
			if (cnt <= 1) continue;
			var sample:MetaNote = samples.get(key);
			if (sample == null) continue;
			var x:Float = 0;
			if (!sample.isEvent)
			{
				var uiCol:Int = noteDataToUIColumn(sample.songData[1]);
				var spacingOffset:Float = 0;
				if (uiCol >= opponentGridCols()) spacingOffset += TRACK_SPACING;
				if (uiCol >= opponentGridCols() + EVENT_TRACK_COUNT) spacingOffset += TRACK_SPACING;
				x = gl.startX + uiCol * GRID_SIZE + spacingOffset + GRID_SIZE;
			}
			else
			{
				var ev:EventMetaNote = cast sample;
				x = gl.eventX + ev.eventTrackIndex * GRID_SIZE + GRID_SIZE;
			}
			var y:Float = sample.chartY + GRID_SIZE - 24; // 文本底缘贴格子底边
			var txt:FlxText = new FlxText(x - 48, y, 48, 'x$cnt', 24);
			// arturito-slab 24px + 1px 黑色描边
			txt.setFormat(Paths.font('arturito-slab.ttf'), 24, 0xFFFFFFFF, RIGHT, OUTLINE_FAST, 0xFF000000);
			txt.borderSize = 1;
			// X 固定（网格不随摄像机横向滚动）；Y 跟随摄像机纵向滚动（与音符一致，滚动时标记随网格移动）
			txt.scrollFactor.set(0, 1);
			overlapMarkers.add(txt);
		}
	}

	// 去除当前作用域内的重复箭头与事件
	// 箭头重复：同 strumTime + 同数据列（songData[1]）；事件重复：strumTime + 事件名 + 全部 value 值相同（不要求轨道索引）
	// wholeSong=false（"-1 重复"）：仅当前小节；wholeSong=true（"清除重复"）：整个谱面
	// minusOne=true（"-1 重复"）：每个重复组仅删除 1 个（N→N-1，可多次点击逐步减）；
	// minusOne=false（"清除重复"）：每组保留 1 个、删除其余 N-1 个
	// 受《音符/事件》复选框（affectNotes/affectEvents）控制：只处理勾选类型
	function dedupeSection(wholeSong:Bool, minusOne:Bool = false):Void
	{
		var removedNotes:Int = 0;
		var removedEvents:Int = 0;
		var minTime:Float = wholeSong ? Math.NEGATIVE_INFINITY : getMinNoteTime(curSec);
		var maxTime:Float = wholeSong ? Math.POSITIVE_INFINITY : getMaxNoteTime(curSec);

		if (affectNotes.checked)
		{
			var counts:Map<String, Int> = [];
			if (minusOne)
			{
				for (note in notes)
				{
					if (note == null || note.isEvent) continue;
					if (note.strumTime < minTime || note.strumTime >= maxTime) continue;
					var k:String = note.strumTime + '|' + note.songData[1];
					if (counts.exists(k)) counts.set(k, counts.get(k) + 1);
					else counts.set(k, 1);
				}
			}
			var keptNotes:Map<String, Bool> = [];
			var deletedKeys:Map<String, Bool> = [];
			for (note in notes.copy())
			{
				if (note == null || note.isEvent) continue;
				if (note.strumTime < minTime || note.strumTime >= maxTime) continue;
				var key:String = note.strumTime + '|' + note.songData[1];
				if (minusOne)
				{
					// 每个重复组只删 1 个
					if (counts.get(key) != null && counts.get(key) > 1 && !deletedKeys.exists(key))
					{
						notes.remove(note);
						selectedNotes.remove(note);
						removedNotes++;
						deletedKeys.set(key, true);
					}
				}
				else
				{
					if (keptNotes.exists(key))
					{
						notes.remove(note);
						selectedNotes.remove(note);
						removedNotes++;
					}
					else keptNotes.set(key, true);
				}
			}
		}

		if (affectEvents.checked)
		{
			var eventCounts:Map<String, Int> = [];
			if (minusOne)
			{
				for (ev in events)
				{
					if (ev == null) continue;
					if (ev.strumTime < minTime || ev.strumTime >= maxTime) continue;
					var entries:Array<Array<String>> = ev.events;
					if (entries == null || entries.length == 0) continue;
					for (entry in entries)
					{
						if (entry == null) continue;
						var k:String = ev.strumTime + '|' + entry.join('|');
						if (eventCounts.exists(k)) eventCounts.set(k, eventCounts.get(k) + 1);
						else eventCounts.set(k, 1);
					}
				}
			}
			var keptEvents:Map<String, Bool> = [];
			var deletedEventKeys:Map<String, Bool> = [];
			for (ev in events.copy())
			{
				if (ev == null) continue;
				if (ev.strumTime < minTime || ev.strumTime >= maxTime) continue;
				var entries:Array<Array<String>> = ev.events;
				if (entries == null || entries.length == 0) continue;
				for (entry in entries)
				{
					if (entry == null) continue;
					var key:String = ev.strumTime + '|' + entry.join('|');
					if (minusOne)
					{
						// 每个重复组只删 1 个（该组首个重复图标）
						if (eventCounts.get(key) != null && eventCounts.get(key) > 1 && !deletedEventKeys.exists(key))
						{
							events.remove(ev);
							selectedNotes.remove(ev);
							removedEvents++;
							deletedEventKeys.set(key, true);
							break;
						}
					}
					else
					{
						if (keptEvents.exists(key))
						{
							events.remove(ev);
							selectedNotes.remove(ev);
							removedEvents++;
							break; // 该图标已判定为重复，不再处理其后续条目
						}
						keptEvents.set(key, true);
					}
				}
			}
		}

		if (removedNotes + removedEvents > 0)
		{
			softReloadNotes(wholeSong ? false : true);
			chartDataDirty = true;
			showOutput(Language.get('charting_dedupesec_result', [Std.string(removedNotes), Std.string(removedEvents)]), true);
		}
		else showOutput(Language.get('charting_msg_nothingdedupe'), true);
	}

	// 检测 [minTime, maxTime) 范围内是否存在重复（箭头或事件，可分别开关）
	function hasDuplicatesInRange(minTime:Float, maxTime:Float, checkNotes:Bool = true, checkEvents:Bool = true):Bool
	{
		if (checkNotes)
		{
			var seenNotes:Map<String, Bool> = [];
			for (note in notes)
			{
				if (note == null || note.isEvent) continue;
				if (note.strumTime < minTime || note.strumTime >= maxTime) continue;
				var key:String = note.strumTime + '|' + note.songData[1];
				if (seenNotes.exists(key)) return true;
				seenNotes.set(key, true);
			}
		}
		if (checkEvents)
		{
			var seenEvents:Map<String, Bool> = [];
			for (ev in events)
			{
				if (ev == null) continue;
				if (ev.strumTime < minTime || ev.strumTime >= maxTime) continue;
				var entries:Array<Array<String>> = ev.events;
				if (entries == null || entries.length == 0) continue;
				for (entry in entries)
				{
					if (entry == null) continue;
					var key:String = ev.strumTime + '|' + entry.join('|');
					if (seenEvents.exists(key)) return true;
					seenEvents.set(key, true);
				}
			}
		}
		return false;
	}

	// 去重按钮：始终可见；按《音符/事件》复选框检测各自作用域是否存在重复——
	// 有重复时正常亮度，无重复时半透明（点击仍会给出"未发现重复项"提示）；仅清除重复部分、每组保留 1 个
	function refreshDedupeButtons():Void
	{
		if (dedupe1Button == null || clearDupButton == null) return;
		if (cachedSectionTimes == null) return; // create 早期 _cacheSections() 尚未执行，跳过本次刷新
		dedupe1Button.alpha = hasDuplicatesInRange(getMinNoteTime(curSec), getMaxNoteTime(curSec), affectNotes.checked, affectEvents.checked) ? 1 : 0.5;
		clearDupButton.alpha = hasDuplicatesInRange(Math.NEGATIVE_INFINITY, Math.POSITIVE_INFINITY, affectNotes.checked, affectEvents.checked) ? 1 : 0.5;
	}

	function getMinNoteTime(sec:Int)
	{
		var minTime:Float = Math.NEGATIVE_INFINITY;
		if(sec > 0 && cachedSectionTimes != null)
			minTime = cachedSectionTimes[sec];
		return minTime;
	}

	function getMaxNoteTime(sec:Int)
	{
		var maxTime:Float = Math.POSITIVE_INFINITY;
		if(cachedSectionTimes != null && sec + 1 < cachedSectionTimes.length)
			maxTime = cachedSectionTimes[sec + 1];
		return maxTime;
	}

	function uiColumnToNoteData(uiColumn:Int):Int
	{
		// LE LTS 双侧（分侧编辑）：noteData 为 LE 连续编号——
		// mustHit 小节 0..plr-1 玩家 / plr..plr+opp-1 对手；非 mustHit 小节 0..opp-1 对手 / opp..opp+plr-1 玩家。
		// 不对称网格：对手列区（0..opp-1）放对手音符、玩家列区（opp+EVENT..）放玩家音符，两区均可直接编辑。
		if (isDualChart())
		{
			var plr:Int = dualPlayerKeyCount();
			var opp:Int = dualOpponentKeyCount();
			var secMustHit:Bool = getCurrentSectionMustHit();
			var oCols:Int = opponentGridCols();
			if (uiColumn < oCols)
			{
				// 对手列区（放置对手音符）
				return secMustHit ? (plr + uiColumn) : uiColumn;
			}
			else if (uiColumn < oCols + EVENT_TRACK_COUNT && SHOW_EVENT_COLUMN)
			{
				return -1; // Event轨道（noteData -1，通过eventTrackIndex区分）
			}
			else
			{
				// 玩家列区（放置玩家音符）
				var col:Int = uiColumn - (oCols + EVENT_TRACK_COUNT);
				return secMustHit ? col : (opp + col);
			}
		}
		// 动态列数布局：对手(0..cols-1) → Event(cols..cols+EVENT-1) → 玩家(cols+EVENT..2cols+EVENT-1)
		if (uiColumn < GRID_COLUMNS_PER_PLAYER)
		{
			return uiColumn + GRID_COLUMNS_PER_PLAYER; // 对手轨道（noteData cols..2cols-1）
		}
		else if (uiColumn < GRID_COLUMNS_PER_PLAYER + EVENT_TRACK_COUNT && SHOW_EVENT_COLUMN)
		{
			return -1; // Event轨道（noteData -1，通过eventTrackIndex区分）
		}
		else
		{
			return uiColumn - (GRID_COLUMNS_PER_PLAYER + EVENT_TRACK_COUNT); // 玩家轨道（noteData 0..cols-1）
		}
	}

	// 当前小节是否 mustHit（LE 双侧映射依据）
	function getCurrentSectionMustHit():Bool
	{
		if (PlayState.SONG != null && PlayState.SONG.notes != null
			&& curSec >= 0 && curSec < PlayState.SONG.notes.length)
			return PlayState.SONG.notes[curSec].mustHitSection;
		return true;
	}

	// noteData 是否属于玩家侧（LE LTS 双侧：按小节 mustHit 与 LE 连续编号判断；非双侧 = noteData < 玩家侧键数）
	public static function isPlayerNoteByData(noteData:Int, secMustHit:Bool):Bool
	{
		if (!isDualChart()) return (noteData < playerGridCols());
		var plr:Int = dualPlayerKeyCount();
		var opp:Int = dualOpponentKeyCount();
		return secMustHit ? (noteData < plr) : (noteData >= opp);
	}

	// LE LTS 双侧：把"音符 noteData + 所属小节 mustHit"解析为 [isPlayer, 侧内方向列]，供角色 sing 动画使用。
	// 双侧下 noteData 为 LE 连续编号（mustHit 小节 0..plr-1=玩家 / plr..=对手；非 mustHit 小节 0..opp-1=对手 / opp..=玩家），
	// 非双侧下为 Psych 编码（0..cols-1=玩家 / cols..=对手）。
	function resolveCharAnimSide(noteData:Int, secMustHit:Bool):Array<Dynamic>
	{
		var pCols:Int = playerGridCols();
		var oCols:Int = opponentGridCols();
		var isPlr:Bool;
		var direction:Int;
		if (isDualChart())
		{
			isPlr = isPlayerNoteByData(noteData, secMustHit);
			direction = isPlr ? (secMustHit ? noteData : (noteData - oCols)) : (secMustHit ? (noteData - pCols) : noteData);
		}
		else
		{
			isPlr = (noteData < pCols);
			direction = noteData % (isPlr ? pCols : oCols);
		}
		if (direction < 0) direction = 0;
		return [isPlr, direction];
	}

	// LE LTS 双侧：刷新编辑侧切换按钮高亮（当前编辑侧高亮）
	function refreshEditSideButtons():Void
	{
		if (editPlayerBtn == null || editOpponentBtn == null) return;
		editPlayerBtn.color = (ChartingState.editorSide == 0) ? 0xFF60A0FF : 0xFFFFFFFF;
		editOpponentBtn.color = (ChartingState.editorSide == 1) ? 0xFF60A0FF : 0xFFFFFFFF;
	}

	function noteDataToUIColumn(noteData:Int):Int
	{
		// LE LTS 双侧（分侧编辑）：按 LE 规则把 noteData 映射回 UI 列。
		// 不对称网格下两侧各自渲染（对手区 0..opp-1、玩家区 opp+EVENT..），对侧音符显示在对侧网格，不再裁剪隐藏。
		if (isDualChart())
		{
			var plr:Int = dualPlayerKeyCount();
			var opp:Int = dualOpponentKeyCount();
			var secMustHit:Bool = getCurrentSectionMustHit();
			var oCols:Int = opponentGridCols();
			var pCols:Int = playerGridCols();

			if (noteData < 0 && SHOW_EVENT_COLUMN)
				return oCols; // Event轨道（返回起始位置，具体位置由eventTrackIndex决定）

			if (isPlayerNoteByData(noteData, secMustHit))
			{
				var col:Int = secMustHit ? noteData : (noteData - opp);
				if (col < 0 || col >= pCols) return -2;
				return col + oCols + EVENT_TRACK_COUNT;
			}
			else
			{
				var col:Int = secMustHit ? (noteData - plr) : noteData;
				if (col < 0 || col >= oCols) return -2;
				return col;
			}
		}
		// 动态列数布局：对手(0..cols-1) → Event → 玩家(0..cols-1)
		if (noteData >= GRID_COLUMNS_PER_PLAYER)
		{
			return noteData - GRID_COLUMNS_PER_PLAYER; // 对手轨道（UI列0..cols-1）
		}
		else if (noteData < 0 && SHOW_EVENT_COLUMN)
		{
			return GRID_COLUMNS_PER_PLAYER; // Event轨道（返回起始位置，具体位置由eventTrackIndex决定）
		}
		else
		{
			return noteData + GRID_COLUMNS_PER_PLAYER + EVENT_TRACK_COUNT; // 玩家轨道
		}
	}

	// 获取鼠标当前位置下最接近的箭头（音符/事件），供左键选择与右键删除共用
	function getClosestNoteUnderMouse():MetaNote
	{
		var trackInfo = getTrackAtPosition(FlxG.mouse.x, FlxG.mouse.y);
		if(trackInfo == null) return null;

		var diffX:Float = FlxG.mouse.x - trackInfo.trackX;
		var uiColumn:Int = Math.floor(diffX / GRID_SIZE);
		if(trackInfo.trackType == 'event') uiColumn += opponentGridCols();
		else if(trackInfo.trackType == 'player') uiColumn += opponentGridCols() + EVENT_TRACK_COUNT;

		var noteData:Int = uiColumnToNoteData(uiColumn);
		if(trackInfo.trackType == 'event') noteData = -1;

		var closeNotes:Array<MetaNote> = curRenderedNotes.members.filter(function(note:MetaNote)
		{
			var chartY:Float = FlxG.mouse.y - note.chartY;
			if(note.isEvent && noteData < 0)
			{
				var eventDiffX:Float = FlxG.mouse.x - trackInfo.trackX;
				var clickTrackIndex:Int = Std.int(Math.floor(eventDiffX / GRID_SIZE));
				clickTrackIndex = Std.int(Math.max(0, Math.min(clickTrackIndex, EVENT_TRACK_COUNT - 1)));
				var eventNote:EventMetaNote = cast note;
				return eventNote.eventTrackIndex == clickTrackIndex && chartY >= 0 && chartY < GRID_SIZE;
			}
			return (!note.isEvent && note.songData[1] == noteData) && chartY >= 0 && chartY < GRID_SIZE;
		});
		closeNotes.sort(function(a:MetaNote, b:MetaNote) return Math.abs(a.strumTime - FlxG.mouse.y) < Math.abs(b.strumTime - FlxG.mouse.y) ? 1 : -1);
		return closeNotes[0];
	}

	// 删除指定箭头（音符或事件），并记录撤销操作
	function deleteNoteUnderCursor(note:MetaNote):Void
	{
		var kind:String = !note.isEvent ? 'note' : 'event';
		trace('Removed $kind at time: ${note.strumTime}');
		if(!note.isEvent)
			notes.remove(note);
		else
			events.remove(cast (note, EventMetaNote));

		selectedNotes.remove(note);
		curRenderedNotes.remove(note, true);
		addUndoAction(DELETE_NOTE, !note.isEvent ? {notes: [note]} : {events: [note]});
		// 手动删减（鼠标/触屏/右键）后刷新叠加标记与去重按钮状态（此路径不走 softReloadNotes）
		updateOverlapMarkers();
		refreshDedupeButtons();
	}

	// 在空白处按下左键时立即创建箭头，并进入“拖拽创建长条”状态（拖动时实时预览长度）
	function startDragCreate():Void
	{
		var trackInfo = getTrackAtPosition(FlxG.mouse.x, FlxG.mouse.y);
		if(trackInfo == null) return;

		var diffX:Float = FlxG.mouse.x - trackInfo.trackX;
		var uiColumn:Int = Math.floor(diffX / GRID_SIZE);
		if(trackInfo.trackType == 'event') uiColumn += opponentGridCols();
		else if(trackInfo.trackType == 'player') uiColumn += opponentGridCols() + EVENT_TRACK_COUNT;

		var noteData:Int = uiColumnToNoteData(uiColumn);
		if(trackInfo.trackType == 'event') noteData = -1;

		isDraggingNote = true;
		dragStartNoteData = noteData;
		dragStartTrackType = trackInfo.trackType;
		dragStartEventTrackIndex = null;
		if(trackInfo.trackType == 'event')
		{
			var eventDiffX:Float = FlxG.mouse.x - trackInfo.trackX;
			var idx:Int = Std.int(Math.floor(eventDiffX / GRID_SIZE));
			if(idx >= 0 && idx < EVENT_TRACK_COUNT) dragStartEventTrackIndex = idx;
		}

		var diffY:Float = FlxG.mouse.y - trackInfo.grid.y;
		if(!FlxG.keys.pressed.SHIFT)
			diffY -= diffY % (GRID_SIZE * curZoom / (curQuant/16)); // 乘 curZoom 以适配不同缩放
		if(trackInfo.nextGrid.visible) diffY = Math.min(diffY, trackInfo.grid.height + trackInfo.nextGrid.height);
		else diffY = Math.min(diffY, trackInfo.grid.height);
		if(trackInfo.prevGrid.visible) diffY = Math.max(diffY, -trackInfo.prevGrid.height);
		else diffY = Math.max(diffY, 0);

		var stepAtMouse:Float = (diffY / (GRID_SIZE * curZoom)) + cachedSectionRow[curSec];
		dragStartStrumTime = Conductor.getTimeFromStep(stepAtMouse);
		dragStartChartY = trackInfo.grid.y + diffY;
		dragStartMouseY = FlxG.mouse.y; // 记录按下点，用于判断是否真正向下拖动

		// 记录起始轨道的屏幕 X 坐标（拖拽过程中长条始终停留在该轨道）
		dragStartX = dummyArrow.x;

		// 立即创建真实箭头，拖动过程中实时更新长条长度
		if(dragStartNoteData >= 0)
		{
			var noteSetupData:Array<Dynamic> = [dragStartStrumTime, dragStartNoteData, 0];
			var typeSelected:String = noteTypes[noteTypeDropDown.selectedIndex].trim();
			if(typeSelected != null && typeSelected.length > 0)
				noteSetupData.push(typeSelected);

			var noteAdded:MetaNote = createNote(noteSetupData);
			var didAdd:Bool = false;
			for (num in sectionFirstNoteID...notes.length)
			{
				var note = notes[num];
				if(note.strumTime >= dragStartStrumTime)
				{
					notes.insert(num, noteAdded);
					didAdd = true;
					break;
				}
			}
			if(!didAdd) notes.push(noteAdded);

			dragNote = noteAdded;
			resetSelectedNotes();
			selectedNotes.push(noteAdded);

			var charSide:Array<Dynamic> = resolveCharAnimSide(dragStartNoteData, getCurrentSectionMustHit());
			var targetChar:Character = charSide[0] ? boyfriend : dad;
			var direction:Int = charSide[1];
			if(targetChar != null && targetChar.visible)
				playCharacterSing(targetChar, direction, charSide[0]);
		}
		else if(!lockedEvents && dragStartTrackType == 'event')
		{
			var eventAdded:EventMetaNote = createEvent([dragStartStrumTime, [[eventsList[Std.int(Math.max(eventDropDown.selectedIndex, 0))][0], value1InputText.text, value2InputText.text, value3InputText.text, value4InputText.text]]], dragStartEventTrackIndex);
			var didAdd:Bool = false;
			for (num in sectionFirstEventID...events.length)
			{
				var event = events[num];
				if(event.strumTime >= dragStartStrumTime)
				{
					events.insert(num, eventAdded);
					didAdd = true;
					break;
				}
			}
			if(!didAdd) events.push(eventAdded);

			dragNote = eventAdded;
			resetSelectedNotes();
			selectedNotes.push(eventAdded);
		}

		softReloadNotes();
		dragPreview.visible = true;
		updateDragPreview();
	}

	// 对已有箭头进行拖动延伸：复用“拖动生成长条”逻辑，直接修改该箭头的长度（需启用“拖动生成箭头长条”）
	function startDragExtend(note:MetaNote):Void
	{
		isDraggingNote = true;
		dragExistingNote = true;
		dragNote = note;
		dragExtendOriginalSustain = note.sustainLength; // 记录原始长条长度，供撤销使用

		dragStartStrumTime = note.strumTime;
		dragStartNoteData = note.noteData;
		dragStartTrackType = note.isEvent ? 'event' : (isDualChart()
			? (isPlayerNoteByData(note.noteData, getCurrentSectionMustHit()) ? 'player' : 'normal')
			: ((note.noteData >= GRID_COLUMNS_PER_PLAYER) ? 'player' : 'normal'));
		dragStartX = note.x;     // 延伸时箭头始终停留在该轨道
		dragStartChartY = note.y; // 以箭头头部为起点计算位移

		dragPendingNote = null; // 已进入真正拖动，取消待命标记

		resetSelectedNotes();
		selectedNotes.push(note);

		dragPreview.visible = true;
		updateDragPreview();
	}

	// 拖动过程中实时更新长条预览：直接修改真实箭头的长度，并显示半透明参考框
	function updateDragPreview():Void
	{
		// 已有箭头延伸：按相对起始点（箭头头部）的位移直接计算新长条长度，与轨道无关，避免跨轨误差
		if(dragExistingNote && dragNote != null)
		{
			var emy:Float = FlxG.mouse.y;
			var deltaY:Float = emy - dragStartChartY;
			if(!FlxG.keys.pressed.SHIFT)
			{
				// 默认按半格吸附，使长条长度可按半格增量修改
				var snap:Float = GRID_SIZE * curZoom / (curQuant/16) / 2; // 乘 curZoom 适配缩放
				deltaY -= deltaY % snap;
			}
			var steps:Float = deltaY / (GRID_SIZE * curZoom);
			var sustain:Float = steps * Conductor.stepCrochet;
			if(sustain < 0) sustain = 0; // 向上拖拽视为缩短（到头部则为普通箭头）

			if(!dragNote.isEvent)
				dragNote.setSustainLength(sustain, Conductor.stepCrochet, curZoom);

			var topY:Float = Math.min(dragStartChartY, emy);
			var h:Float = Math.max(4, Math.abs(emy - dragStartChartY));
			dragPreview.setPosition(dragStartX, topY);
			dragPreview.setGraphicSize(GRID_SIZE, h);
			dragPreview.updateHitbox();
			return;
		}

		var my:Float = FlxG.mouse.y;
		var myTrack = getTrackAtPosition(FlxG.mouse.x, my);
		if(myTrack == null || dragNote == null) return;

		// 只有鼠标从按下点向下移动才视为“拖拽生成长条”；单纯点击（即使按在格线下半部）
		// 也是普通箭头，长条为 0。这样可避免头部向下取整吸附导致点击下半格也生成半个长条。
		var deltaY:Float = 0;
		if(my > dragStartMouseY)
		{
			// 相对头部（dragStartChartY，当前格线）计算长条，头部不跳到下一格
			deltaY = my - dragStartChartY;
			if(!FlxG.keys.pressed.SHIFT)
			{
				var snap:Float = GRID_SIZE * curZoom / (curQuant/16) / 2; // 乘 curZoom 适配缩放
				deltaY = Math.ceil(deltaY / snap) * snap; // 向下拖动向上取整到下一吸附点

				// 最小长度为“一整格”（一 grid），杜绝亚格超短长条
				var oneGrid:Float = GRID_SIZE * curZoom;
				if(deltaY > 0 && deltaY < oneGrid) deltaY = oneGrid;
			}
		}

		// 限制在谱面小节可见范围内（相对头部计算边界）
		var headOffset:Float = dragStartChartY - myTrack.grid.y;
		var maxDelta:Float = (myTrack.nextGrid.visible ? myTrack.grid.height + myTrack.nextGrid.height : myTrack.grid.height) - headOffset;
		var minDelta:Float = (myTrack.prevGrid.visible ? -myTrack.prevGrid.height : 0) - headOffset;
		deltaY = Math.max(minDelta, Math.min(maxDelta, deltaY));

		var steps:Float = deltaY / (GRID_SIZE * curZoom);
		var sustain:Float = steps * Conductor.stepCrochet;
		if(sustain < 0) sustain = 0;

		// setSustainLength 内部已自动吸附到半格（stepCrochet/2）
		if(!dragNote.isEvent)
			dragNote.setSustainLength(sustain, Conductor.stepCrochet, curZoom);

		// 预览框与真实长条一致：从头部向下延伸 deltaY（避免视觉长度与长条长度不符）
		var headY:Float = dragStartChartY;
		var topY:Float = Math.min(headY, headY + deltaY);
		var h:Float = Math.max(4, Math.abs(deltaY));
		dragPreview.setPosition(dragStartX, topY);
		dragPreview.setGraphicSize(GRID_SIZE, h);
		dragPreview.updateHitbox();
	}

	// 左键释放时确认长条（箭头已在拖拽开始时创建），仅记录撤销操作
	function finishDragCreate():Void
	{
		if(!isDraggingNote) return;
		isDraggingNote = false;
		dragPreview.visible = false;

		if(dragNote != null)
		{
			if(dragExistingNote)
			{
				// 仅在实际改变长条长度时记录撤销，避免单纯点击选中产生冗余历史
				if(dragExtendOriginalSustain != dragNote.sustainLength)
				{
					addUndoAction(MODIFY_NOTE, {
						note: dragNote,
						isEvent: dragNote.isEvent,
						originalSustain: dragExtendOriginalSustain,
						modifiedSustain: dragNote.sustainLength
					});
				}
			}
			else
			{
				addUndoAction(ADD_NOTE, !dragNote.isEvent ? {notes: [dragNote]} : {events: [dragNote]});
			}
			onSelectNote();
		}
		dragNote = null;
		dragExistingNote = false;
	}

	function positionNoteXByData(note:MetaNote, ?data:Null<Int> = null, ?cols:Null<Int> = null)
	{
		if(data == null) data = note.songData[1];
		// cols：音符所属小节的列数。默认回落到全局（当前小节）列数，保持既有调用行为。
		if(cols == null) cols = GRID_COLUMNS_PER_PLAYER;
		var gridLayout = getGridLayout();

		var noteX:Float = gridLayout.startX + (GRID_SIZE - note.width) / 2;

		// 区分event和普通note，使用不同的轨道布局
		if (note.isEvent)
		{
			// Event使用专用方法，根据eventTrackIndex定位
			var eventNote:EventMetaNote = cast note;
			positionEventOnTrack(eventNote, eventNote.eventTrackIndex);
			return;
		}

		// LE LTS 双侧（分侧编辑）：按 LE 规则映射 UI 列；音符渲染在各自侧网格（不对称布局）
		if (isDualChart())
		{
			var uiCol:Int = noteDataToUIColumn(data);
			if (uiCol < 0)
			{
				note.visible = false;
				return;
			}
			note.visible = true;
			var oColsP:Int = opponentGridCols();
			var spacingOffset:Float = 0;
			if (uiCol >= oColsP) spacingOffset += TRACK_SPACING;
			if (uiCol >= oColsP + EVENT_TRACK_COUNT) spacingOffset += TRACK_SPACING;
			note.x = gridLayout.startX + uiCol * GRID_SIZE + spacingOffset + (GRID_SIZE - note.width) / 2;
			return;
		}

		// 普通note的轨道布局：对手(0..cols-1) → Event → 玩家(0..cols-1)
		var uiColumn:Int = 0;
		if (data >= cols)
		{
			// 对手轨道（noteData cols..2cols-1）
			uiColumn = data - cols;
		}
		else
		{
			// 玩家轨道（noteData 0..cols-1）
			uiColumn = data + cols + EVENT_TRACK_COUNT;
		}

		// 根据逻辑列号计算额外的间距偏移
		var spacingOffset:Float = 0;
		if (uiColumn >= cols)
		{
			spacingOffset += TRACK_SPACING; // Event轨道后的间距
		}
		if (uiColumn >= cols + EVENT_TRACK_COUNT)
		{
			spacingOffset += TRACK_SPACING; // 玩家轨道前的间距
		}

		noteX += GRID_SIZE * uiColumn + spacingOffset;
		note.x = noteX;
		//trace(gridLayout.startX, noteX);
	}

	function positionNoteYOnTime(note:MetaNote, section:Int)
	{
		// 用 ramp 感知的 getStep 把音符放到其“步位置”对应的均匀网格线上：
		// 即使某段 BPM 线性过渡，音符依然落在网格上且毫秒正确（不挤到段顶）。
		var noteY:Float = Conductor.getStep(note.strumTime) * GRID_SIZE * curZoom;
		noteY = Math.max(noteY, -150);
		note.y = noteY + (GRID_SIZE/2 - note.height/2);
		note.chartY = noteY;
		//trace(gridBg.y, noteY);
	}

	var characterData:Dynamic = {};
	function updateJsonData():Void
	{
		for (i in 1...GRID_PLAYERS+1)
		{
			//trace('adding iconP$i');
			var charName:String = Reflect.field(PlayState.SONG, 'player$i');
			trace('updateJsonData - player$i: charName=$charName');
			var data:CharacterFile = loadCharacterFile(charName);
			trace('updateJsonData - player$i: data=${data != null ? "loaded" : "null"}, vocals_file=${data != null ? data.vocals_file : "N/A"}');
			Reflect.setField(characterData, 'iconP$i', data != null && data.healthicon != null ? data.healthicon : 'face');
			var vocalName:String = data != null && data.vocals_file != null && data.vocals_file.length > 0 ? data.vocals_file : charName;
			trace('updateJsonData - player$i: vocalName=$vocalName');
			Reflect.setField(characterData, 'vocalsP$i', vocalName);
		}
	}
	
	var _lastSec:Int = -1;
	var _lastGfSection:Null<Bool> = null;
	var _lastMustHitSection:Null<Bool> = null; // 记录上一次的mustHitSection状态
	function updateHeads(ignoreCheck:Bool = false):Void
	{
		var curSecData:SwagSection = PlayState.SONG.notes[curSec];
		var isGfSection:Bool = (curSecData != null && curSecData.gfSection == true);
		var mustHitSection:Bool = (curSecData != null && curSecData.mustHitSection == true);
		
		// 提前更新mustHitSection状态，确保动画逻辑能正确判断
		var mustHitChanged:Bool = (_lastMustHitSection != mustHitSection);
		_lastMustHitSection = mustHitSection;
		
		if(_lastGfSection == isGfSection && _lastSec == curSec && !ignoreCheck) return; //optimization

for (i in 0...GRID_PLAYERS)
	{
		var icon:HealthIcon = icons[i];
		//trace('changing iconP${icon.ID}');
		var iconName:String = Reflect.field(characterData, 'iconP${icon.ID}');
		
		// GF Section特殊处理：根据mustHitSection决定哪个图标显示GF
		if (isGfSection)
		{
			var gfChar:String = (PlayState.SONG.gfVersion != null && PlayState.SONG.gfVersion.length > 0) ? PlayState.SONG.gfVersion : 'gf';
			var gfData:CharacterFile = loadCharacterFile(gfChar);
			var gfIcon:String = (gfData != null && gfData.healthicon != null && gfData.healthicon.length > 0) ? gfData.healthicon : 'face';
			if (mustHitSection && i == 0) // 玩家位且GF在玩家位
			{
				icon.changeIcon(gfIcon);
			}
			else if (!mustHitSection && i == 1) // 对手位且GF在对手位
			{
				icon.changeIcon(gfIcon);
			}
			else
			{
				icon.changeIcon(iconName); // 恢复角色图标
			}
		}
		else
		{
			icon.changeIcon(iconName); // 非GF Section，正常显示角色图标
		}
	}

	if(icons.length > 1)
	{
		var iconP1:HealthIcon = icons[0]; // 对手图标
		var iconP2:HealthIcon = icons[1]; // 玩家图标
		var mustHitSection:Bool = (curSecData != null && curSecData.mustHitSection == true);

		// GF Section时的颜色调整（新布局：对手和玩家轨道）
		if (isGfSection)
		{
			if (mustHitSection)
			{
				// 同时启用：mustHitSec + gfSection，GF在玩家位
				// 玩家轨道改为浅红色，对手保持浅紫色
				if(playerTrackOverlay != null) playerTrackOverlay.color = 0xFFFF8888; // 浅红色
				// 对手保持浅紫色（不更改）
			}
			else
			{
				// 仅启用gfSection（mustHitSec禁用），GF在对手位
				// 对手轨道改为浅红色，玩家保持浅紫色
				if(opponentTrackOverlay != null) opponentTrackOverlay.color = 0xFFFF8888; // 浅红色
				// 玩家保持浅紫色（不更改）
			}
		}
		else
		{
			// 非GF Section，恢复默认颜色：对手浅红，玩家浅蓝
			if(playerTrackOverlay != null) playerTrackOverlay.color = 0xFF88CCFF; // 浅蓝色
			if(opponentTrackOverlay != null) opponentTrackOverlay.color = 0xFFCC88FF; // 浅紫色
		}
			// 只在mustHitSection状态改变时执行Tween动画（使用之前记录的mustHitChanged）
			// 修复后：交换iconP1和iconP2的目标，匹配图标显示位置
			if (mustHitChanged)
			{
				var targetX:Float = mustHitSection ? (iconP1.x + iconP1.width / 2) : (iconP2.x + iconP2.width / 2);
				
				if (mustHitTweenEnabled)
				{
					// 指示器移动到对应图标（使用quartout）
					FlxTween.cancelTweensOf(mustHitIndicator);
					FlxTween.tween(mustHitIndicator, {x: targetX}, 0.3, {ease: FlxEase.quartOut});
				}
				else
				{
					// 禁用tween时直接设置位置
					FlxTween.cancelTweensOf(mustHitIndicator);
					mustHitIndicator.x = targetX;
				}
			}
		}
			// 根据mustHitSection调整角色颜色已移除（ShowCharacters复选框已删除）

		_lastGfSection = isGfSection;
		_lastSec = curSec;
	}

	var playbackSlider:PsychUISlider;

	var mouseSnapCheckBox:PsychUICheckBox;
	var ignoreProgressCheckBox:PsychUICheckBox;
	var rightClickDeleteCheckBox:PsychUICheckBox;
	var dragHoldCheckBox:PsychUICheckBox;
	var hitsoundPlayerStepper:PsychUINumericStepper;
	var hitsoundOpponentStepper:PsychUINumericStepper;
	var metronomeStepper:PsychUINumericStepper;

	var instVolumeStepper:PsychUINumericStepper;
	var instMuteCheckBox:PsychUICheckBox;
	var playerVolumeStepper:PsychUINumericStepper;
	var playerMuteCheckBox:PsychUICheckBox;
	var opponentVolumeStepper:PsychUINumericStepper;
	var opponentMuteCheckBox:PsychUICheckBox;

	function addChartingTab()
	{
		var tab_group = mainBox.getTab(Language.get('charting_charting_text')).menu;
		var objX = 10;
		var objY = 10;

		var txt = new FlxText(objX, objY, 320, Language.get('charting_charting_tip'), Std.parseInt(Language.get('charting_font_size')));
		txt.font = Paths.font(Language.get('uitab_font'));
		txt.alignment = CENTER;
		tab_group.add(txt);

		objY += 25;
		playbackSlider = new PsychUISlider(50, objY, function(v:Float) setPitch(playbackRate = v), 1, 0.1, 5.0, 250);
		playbackSlider.label = Language.get('charting_playback_text');
		
		objY += 60;
		mouseSnapCheckBox = new PsychUICheckBox(objX, objY, Language.get('charting_mousescrsnap_text'), 160, function() 
		{
			chartEditorSave.data.mouseScrollSnap = mouseSnapCheckBox.checked;
			chartEditorSave.flush();
		});
		if(chartEditorSave.data.mouseScrollSnap == null) chartEditorSave.data.mouseScrollSnap = false;
		mouseSnapCheckBox.checked = chartEditorSave.data.mouseScrollSnap;

		ignoreProgressCheckBox = new PsychUICheckBox(objX + 170, objY, Language.get('charting_ignwarning_text'), 160, function()
		{
			chartEditorSave.data.ignoreProgressWarns = ignoreProgressCheckBox.checked;
			chartEditorSave.flush();
		});
		if(chartEditorSave.data.ignoreProgressWarns == null) chartEditorSave.data.ignoreProgressWarns = false;
		ignoreProgressCheckBox.checked = chartEditorSave.data.ignoreProgressWarns;

		if(!controls.mobileC)
		{
			objY += 25;
			rightClickDeleteCheckBox = new PsychUICheckBox(objX, objY, Language.get('charting_rightclickdel_text'), 160, function()
			{
				rightClickDeleteNote = rightClickDeleteCheckBox.checked;
				chartEditorSave.data.rightClickDeleteNote = rightClickDeleteNote;
				chartEditorSave.flush();
			});
			if(chartEditorSave.data.rightClickDeleteNote == null) chartEditorSave.data.rightClickDeleteNote = false;
			rightClickDeleteCheckBox.checked = chartEditorSave.data.rightClickDeleteNote;

			// dragHoldCheckBox 移到 ignoreProgressCheckBox 下方（与 rightClickDeleteCheckBox 同行但右对齐）
			dragHoldCheckBox = new PsychUICheckBox(objX + 170, objY, Language.get('charting_dragcreatesustain_text'), 160, function()
			{
				dragCreateHoldNote = dragHoldCheckBox.checked;
				chartEditorSave.data.dragCreateHoldNote = dragCreateHoldNote;
				chartEditorSave.flush();
			});
			if(chartEditorSave.data.dragCreateHoldNote == null) chartEditorSave.data.dragCreateHoldNote = true;
			dragHoldCheckBox.checked = chartEditorSave.data.dragCreateHoldNote;
		}

		objY += 50;
		hitsoundPlayerStepper = new PsychUINumericStepper(objX, objY, 0.2, chartEditorSave.data.hitsoundPlayerVol, 0, 1, 1, 80);
		hitsoundPlayerStepper.onValueChange = function()
		{
			chartEditorSave.data.hitsoundPlayerVol = hitsoundPlayerStepper.value;
			chartEditorSave.flush();
		};
		hitsoundOpponentStepper = new PsychUINumericStepper(objX + 110, objY, 0.2, chartEditorSave.data.hitsoundOpponentVol, 0, 1, 1, 80);
		hitsoundOpponentStepper.onValueChange = function()
		{
			chartEditorSave.data.hitsoundOpponentVol = hitsoundOpponentStepper.value;
			chartEditorSave.flush();
		};
		metronomeStepper = new PsychUINumericStepper(objX + 220, objY, 0.2, chartEditorSave.data.metronomeVol, 0, 1, 1, 80);
		metronomeStepper.onValueChange = function()
		{
			chartEditorSave.data.metronomeVol = metronomeStepper.value;
			chartEditorSave.flush();
		};

		objY += 50;
		instVolumeStepper = new PsychUINumericStepper(objX, objY, 0.1, chartEditorSave.data.instVolume, 0, 1, 1, 80);
		instVolumeStepper.onValueChange = function()
		{
			chartEditorSave.data.instVolume = instVolumeStepper.value;
			chartEditorSave.flush();
			updateAudioVolume();
		};
		playerVolumeStepper = new PsychUINumericStepper(objX + 110, objY, 0.1, chartEditorSave.data.playerVolume, 0, 1, 1, 80);
		playerVolumeStepper.onValueChange = function()
		{
			chartEditorSave.data.playerVolume = playerVolumeStepper.value;
			chartEditorSave.flush();
			updateAudioVolume();
		};
		opponentVolumeStepper = new PsychUINumericStepper(objX + 220, objY, 0.1, chartEditorSave.data.opponentVolume, 0, 1, 1, 80);
		opponentVolumeStepper.onValueChange = function()
		{
			chartEditorSave.data.opponentVolume = opponentVolumeStepper.value;
			chartEditorSave.flush();
			updateAudioVolume();
		};

		objY += 25;
		instMuteCheckBox = new PsychUICheckBox(objX, objY, Language.get('charting_mute_text'), 60, function()
		{
			chartEditorSave.data.instMuted = instMuteCheckBox.checked;
			chartEditorSave.flush();
			updateAudioVolume();
		});
		instMuteCheckBox.checked = chartEditorSave.data.instMuted;
		playerMuteCheckBox = new PsychUICheckBox(objX + 100, objY, Language.get('charting_mute_text'), 60, function()
		{
			chartEditorSave.data.playerMuted = playerMuteCheckBox.checked;
			chartEditorSave.flush();
			updateAudioVolume();
		});
		playerMuteCheckBox.checked = chartEditorSave.data.playerMuted;
		opponentMuteCheckBox = new PsychUICheckBox(objX + 200, objY, Language.get('charting_mute_text'), 60, function()
		{
			chartEditorSave.data.opponentMuted = opponentMuteCheckBox.checked;
			chartEditorSave.flush();
			updateAudioVolume();
		});
		opponentMuteCheckBox.checked = chartEditorSave.data.opponentMuted;

		objY += 50;

		tab_group.add(playbackSlider);
		tab_group.add(mouseSnapCheckBox);
		tab_group.add(ignoreProgressCheckBox);
		// 移动端不会创建这两个复选框，直接 add(null) 会在 FlxSpriteGroup.preAdd 中崩溃
		if(rightClickDeleteCheckBox != null) tab_group.add(rightClickDeleteCheckBox);
		if(dragHoldCheckBox != null) tab_group.add(dragHoldCheckBox);

		tab_group.add(new FlxText(hitsoundPlayerStepper.x, hitsoundPlayerStepper.y - 15, 120, Language.get('charting_playersoundhit_text')).setFormat(Paths.font(Language.get('uitab_font')), 12));
		tab_group.add(new FlxText(hitsoundOpponentStepper.x, hitsoundOpponentStepper.y - 15, 120, Language.get('charting_opposoundhit_text')).setFormat(Paths.font(Language.get('uitab_font')), 12));
		tab_group.add(new FlxText(metronomeStepper.x, metronomeStepper.y - 15, 100, Language.get('charting_metronome_text')).setFormat(Paths.font(Language.get('uitab_font')), 12));
		tab_group.add(hitsoundPlayerStepper);
		tab_group.add(hitsoundOpponentStepper);
		tab_group.add(metronomeStepper);
		
		tab_group.add(new FlxText(instVolumeStepper.x, instVolumeStepper.y - 15, 100, Language.get('charting_instvol_text')).setFormat(Paths.font(Language.get('uitab_font')), 12));
		tab_group.add(new FlxText(playerVolumeStepper.x, playerVolumeStepper.y - 15, 100, Language.get('charting_playervol_text')).setFormat(Paths.font(Language.get('uitab_font')), 12));
		tab_group.add(new FlxText(opponentVolumeStepper.x, opponentVolumeStepper.y - 15, 100, Language.get('charting_oppovol_text')).setFormat(Paths.font(Language.get('uitab_font')), 12));
		tab_group.add(instVolumeStepper);
		tab_group.add(instMuteCheckBox);
		tab_group.add(playerVolumeStepper);
		tab_group.add(playerMuteCheckBox);
		tab_group.add(opponentVolumeStepper);
		tab_group.add(opponentMuteCheckBox);
	}

	var gameOverCharDropDown:PsychUIDropDownMenu;
	var gameOverSndInputText:PsychUIInputText;
	var gameOverLoopInputText:PsychUIInputText;
	var gameOverRetryInputText:PsychUIInputText;
	var noRGBCheckBox:PsychUICheckBox;
	var noteTextureInputText:PsychUIInputText;
	var noteSplashesInputText:PsychUIInputText;
	var holdCoverTextureInputText:PsychUIInputText;
	function addDataTab()
	{
		var tab_group = mainBox.getTab(Language.get('charting_data_text')).menu;
		var objX = 10;
		var objY = 25;
		gameOverCharDropDown = new PsychUIDropDownMenu(objX, objY, [''], function(id:Int, character:String)
		{
			PlayState.SONG.gameOverChar = character;
			if(character.length < 1) Reflect.deleteField(PlayState.SONG, 'gameOverChar');
			trace('selected $character');
		});

		objY += 40;
		gameOverSndInputText = new PsychUIInputText(objX, objY, 150, '', 12);
		gameOverSndInputText.onChange = function(old:String, cur:String)
		{
			PlayState.SONG.gameOverSound = cur;
			if(cur.trim().length < 1) Reflect.deleteField(PlayState.SONG, 'gameOverSound');
		}
		objY += 40;
		gameOverLoopInputText = new PsychUIInputText(objX, objY, 150, '', 12);
		gameOverLoopInputText.onChange = function(old:String, cur:String)
		{
			PlayState.SONG.gameOverLoop = cur;
			if(cur.trim().length < 1) Reflect.deleteField(PlayState.SONG, 'gameOverLoop');
		}
		objY += 40;
		gameOverRetryInputText = new PsychUIInputText(objX, objY, 150, '', 12);
		gameOverRetryInputText.onChange = function(old:String, cur:String)
		{
			PlayState.SONG.gameOverEnd = cur;
			if(cur.trim().length < 1) Reflect.deleteField(PlayState.SONG, 'gameOverEnd');
		}

		objY += 35;
		var rgbTextKey:String = ClientPrefs.data.arrowColorMode == 'HSV' ? 'charting_disRGB_text_hsv' : 'charting_disRGB_text';
		noRGBCheckBox = new PsychUICheckBox(objX, objY, Language.get(rgbTextKey), 200, updateNotesRGB);
		if(ClientPrefs.data.arrowColorMode == 'HSV') noRGBCheckBox.alpha = 0.5;
		
		objY += 40;
		noteTextureInputText = new PsychUIInputText(objX, objY, 150, '', 12);
		noteTextureInputText.unfocus = function()
		{
			var changed:Bool = false;
			if(PlayState.SONG.arrowSkin != noteTextureInputText.text) changed = true;
			PlayState.SONG.arrowSkin = noteTextureInputText.text.trim();
			if(PlayState.SONG.arrowSkin.trim().length < 1) PlayState.SONG.arrowSkin = null;

			if(changed)
			{
				var textureLoad:String = 'images/${noteTextureInputText.text}.png';
				if(Paths.fileExists(textureLoad, IMAGE) || noteTextureInputText.text.trim() == '')
				{
					for (note in notes)
					{
						if(note == null) continue;
						note.reloadNote(note.texture);
		
						if(note.width > note.height)
							note.setGraphicSize(GRID_SIZE);
						else
							note.setGraphicSize(0, GRID_SIZE);
		
						note.updateHitbox();
					}
					if(noteTextureInputText.text.trim().length > 0) 					showOutput(Language.get('charting_msg_reload_notes', [textureLoad]));
					else showOutput(Language.get('charting_msg_reload_notes_def'));
					
				}
				else showOutput(Language.get('charting_msg_texture_notfound', [textureLoad]), true);
			}
		};

		noteSplashesInputText = new PsychUIInputText(objX + 160, objY, 140, '', 12);
		noteSplashesInputText.onChange = function(old:String, cur:String)
		{
			PlayState.SONG.splashSkin = cur;
			if(cur.trim().length < 1) PlayState.SONG.splashSkin = null;
		}

		objY += 40;
		holdCoverTextureInputText = new PsychUIInputText(objX, objY, 150, '', 12);
		holdCoverTextureInputText.unfocus = function()
		{
			var changed:Bool = false;
			if(PlayState.SONG.holdCoverSkin != holdCoverTextureInputText.text) changed = true;
			PlayState.SONG.holdCoverSkin = holdCoverTextureInputText.text.trim();
			if(PlayState.SONG.holdCoverSkin.trim().length < 1) PlayState.SONG.holdCoverSkin = null;

			if(changed)
			{
				var dir:String = (PlayState.SONG.holdCoverSkin != null) ? PlayState.SONG.holdCoverSkin : '';
				if(dir.length > 0)
				{
					// 单曲自定义纹理目录：images/holdCover/{目录}/holdCover{Purple..}.png 或 sustain_cover.png
					var found:Bool = Paths.fileExists('images/holdCover/$dir/holdCoverPurple.png', IMAGE)
						|| Paths.fileExists('images/holdCover/$dir/sustain_cover.png', IMAGE);
					if(!found)
						showOutput(Language.get('charting_msg_texture_notfound', ['images/holdCover/$dir/']), true);
					else
						showOutput(Language.get('charting_msg_reload_holdcover_ok', ['holdCover/$dir']));
				}
				else
					showOutput(Language.get('charting_msg_reload_notes_def'));
			}
		};

		tab_group.add(new FlxText(gameOverCharDropDown.x, gameOverCharDropDown.y - 15, 120, Language.get('charting_gameover_char')).setFormat(Paths.font(Language.get('uitab_font')), 12));
		tab_group.add(new FlxText(gameOverSndInputText.x, gameOverSndInputText.y - 15, 180, Language.get('charting_gameover_snd')).setFormat(Paths.font(Language.get('uitab_font')), 12));
		tab_group.add(new FlxText(gameOverLoopInputText.x, gameOverLoopInputText.y - 15, 180, Language.get('charting_gameover_loop')).setFormat(Paths.font(Language.get('uitab_font')), 12));
		tab_group.add(new FlxText(gameOverRetryInputText.x, gameOverRetryInputText.y - 15, 180, Language.get('charting_gameover_retry')).setFormat(Paths.font(Language.get('uitab_font')), 12));
		tab_group.add(gameOverSndInputText);
		tab_group.add(gameOverLoopInputText);
		tab_group.add(gameOverRetryInputText);
		tab_group.add(noRGBCheckBox);

		tab_group.add(new FlxText(noteTextureInputText.x, noteTextureInputText.y - 15, 100, Language.get('charting_note_texture')).setFormat(Paths.font(Language.get('uitab_font')), 12));
		tab_group.add(new FlxText(noteSplashesInputText.x, noteSplashesInputText.y - 15, 120, Language.get('charting_note_splashes')).setFormat(Paths.font(Language.get('uitab_font')), 12));
		tab_group.add(new FlxText(holdCoverTextureInputText.x, holdCoverTextureInputText.y - 15, 150, Language.get('charting_hold_cover_texture')).setFormat(Paths.font(Language.get('uitab_font')), 12));
		tab_group.add(noteTextureInputText);
		tab_group.add(noteSplashesInputText);
		tab_group.add(holdCoverTextureInputText);

		tab_group.add(gameOverCharDropDown); //lowest priority to display properly
	}

	var eventDropDown:PsychUIDropDownMenu;
	var value1InputText:PsychUIInputText;
	var value2InputText:PsychUIInputText;
	var value3InputText:PsychUIInputText;
	var value4InputText:PsychUIInputText;
	var selectedEventText:FlxText;
	var eventDescriptionText:FlxText;

	var eventsList:Array<Array<String>>;
	var curEventSelected:Int = 0;
	var eventSearchInputText:PsychUIInputText;
	var eventSearchResultLine1:FlxText;
	var eventSearchResultLine2:FlxText;
	var eventSearchResultLine3:FlxText;
	var eventSearchButton:PsychUIButton;
	var eventSearchClearButton:PsychUIButton;
	var eventSearchPrevButton:PsychUIButton;
	var eventSearchNextButton:PsychUIButton;
	var _eventSearchResults:Array<{note:EventMetaNote, index:Int}> = [];
	var _lastSearchStr:String = '';
	var _currentSearchResultIdx:Int = 0;
	function addEventsTab()
	{
		var tab_group = mainBox.getTab(Language.get('charting_events_text')).menu;
		var objX = 10;
		var objY = 25;
		var boxW:Float = mainBox.bg.width;
		var rightEdge:Int = Std.int(boxW) - objX; // usable right margin within the mainBox

		// Dropdown row layout:
		//   [  eventDropDown  ] (arrow protrudes 15px to the right of the box edge)  (10px) [ - ] (15px) [ + ] ... [ < ] (15px) [ > ] (15px from right edge)
		var eventDropDownWidth = 150;      // total width of the dropdown (excl. the protruding arrow)
		var arrowProtrude:Int = 15;         // how far the dropdown arrow sticks out past the box right edge
		var innerBtnGap:Int = 15;          // gap between consecutive buttons in a group (red-green, left-right)
		var removeBtnX:Int = objX + eventDropDownWidth + arrowProtrude + 10; // red button: 10px right of the arrow's right edge
		var addBtnX:Int = removeBtnX + 20 + innerBtnGap;
		var rightMargin:Int = 15;          // distance from the box right edge for the trailing '>' button
		var rightBtnX:Int = rightEdge - rightMargin - 20; // top-right '>' button
		var leftBtnX:Int = rightBtnX - innerBtnGap - 20;   // '<' button (to the left of '>')

		eventDropDown = new PsychUIDropDownMenu(objX, objY, [], function(id:Int, character:String)
		{
			var eventSelected:Array<String> = eventsList[id];
			var eventName:String = eventSelected[0];
			var description:String = eventSelected[1];
			eventDescriptionText.text = getEventDesc(eventName, description);
			if(selectedNotes.length > 1)
			{
				for (note in selectedNotes)
				{
					if(note == null || !note.isEvent) continue;

					var event:EventMetaNote = cast (note, EventMetaNote);
					event.events[event.events.length - 1][0] = eventName;
					event.updateEventText();
				}
			}
			else if(selectedNotes.length == 1 && selectedNotes[0].isEvent)
			{
				var event:EventMetaNote = cast (selectedNotes[0], EventMetaNote);
				event.events[Std.int(FlxMath.bound(curEventSelected, 0, event.events.length - 1))][0] = eventName;
				event.updateEventText();
			}
			chartDataDirty = true;
		}, eventDropDownWidth);

		function genericEventButton(func:EventMetaNote->Void)
		{
			if(selectedNotes.length == 1)
			{
				if(selectedNotes[0].isEvent)
				{
					var event:EventMetaNote = cast (selectedNotes[0], EventMetaNote);
					func(event);
					updateSelectedEventText();
				}
				else showOutput(Language.get('charting_msg_note_must_event'), true);
			}
			else showOutput(Language.get('charting_msg_single_event'), true);
		}

		var removeButton:PsychUIButton = new PsychUIButton(removeBtnX, objY, '-', function()
		{
			genericEventButton(function(event:EventMetaNote)
			{
				if(event.events.length > 1)
				{
					var selectedEvent = event.events[curEventSelected];
					if(selectedEvent != null)
					{
						event.events.remove(selectedEvent);
						event.updateEventText();
						curEventSelected--;
						chartDataDirty = true;
					}
					else showOutput(Language.get('charting_msg_event_del_weird'), true);
				}
				else
				{
					selectedNotes.remove(event);
					events.remove(event);
					curRenderedNotes.remove(event, true);
					addUndoAction(DELETE_NOTE, {events: [event]});
				}
			});
		}, 20);
		var addButton:PsychUIButton = new PsychUIButton(addBtnX, objY, '+', function()
		{
			genericEventButton(function(event:EventMetaNote)
			{
				event.events.push([eventsList[Std.int(Math.max(eventDropDown.selectedIndex, 0))][0], value1InputText.text, value2InputText.text, value3InputText.text, value4InputText.text]);
				event.updateEventText();
				curEventSelected++;
				chartDataDirty = true;
			});
		}, 20);
		var leftButton:PsychUIButton = new PsychUIButton(leftBtnX, objY, '<', function()
		{
			genericEventButton(function(event:EventMetaNote) curEventSelected = FlxMath.wrap(curEventSelected - 1, 0, event.events.length - 1));
		}, 20);
		var rightButton:PsychUIButton = new PsychUIButton(rightBtnX, objY, '>', function()
		{
			genericEventButton(function(event:EventMetaNote) curEventSelected = FlxMath.wrap(curEventSelected + 1, 0, event.events.length - 1));
		}, 20);
		removeButton.normalStyle.bgColor = FlxColor.RED;
		removeButton.normalStyle.textColor = FlxColor.WHITE;
		addButton.normalStyle.bgColor = FlxColor.GREEN;
		addButton.normalStyle.textColor = FlxColor.WHITE;

		selectedEventText = new FlxText(objX, objY + 30, rightEdge - objX, '');
		selectedEventText.font = Paths.font(Language.get('uitab_font'));
		selectedEventText.size = 12;
		selectedEventText.visible = false;

		function changeEventsValue(str:String, n:Int)
		{
			if(selectedNotes.length > 1)
			{
				for (note in selectedNotes)
				{
					if(note == null || !note.isEvent) continue;

					var event:EventMetaNote = cast (note, EventMetaNote);
					event.events[event.events.length - 1][n] = str;
					event.updateEventText();
				}
			}
			else if(selectedNotes.length == 1 && selectedNotes[0].isEvent)
			{
				var event:EventMetaNote = cast (selectedNotes[0], EventMetaNote);
				event.events[Std.int(FlxMath.bound(curEventSelected, 0, event.events.length - 1))][n] = str;
				event.updateEventText();
			}
			chartDataDirty = true;
		}

		// Value rows: stretch inputs to use the full inner width of the box.
		var valueColGap:Int = 12;
		var valueInputWidth:Int = Std.int((rightEdge - objX - valueColGap) / 2);
		var valueInputCol2X:Int = objX + valueInputWidth + valueColGap;

		objY += 70;
		value1InputText = new PsychUIInputText(objX, objY, valueInputWidth, '', 12);
		value1InputText.onChange = function(old:String, cur:String) changeEventsValue(cur, 1);
		value2InputText = new PsychUIInputText(valueInputCol2X, objY, valueInputWidth, '', 12);
		value2InputText.onChange = function(old:String, cur:String) changeEventsValue(cur, 2);

		objY += 40;
		value3InputText = new PsychUIInputText(objX, objY, valueInputWidth, '', 12);
		value3InputText.onChange = function(old:String, cur:String) changeEventsValue(cur, 3);
		value4InputText = new PsychUIInputText(valueInputCol2X, objY, valueInputWidth, '', 12);
		value4InputText.onChange = function(old:String, cur:String) changeEventsValue(cur, 4);

		objY += 40;
		eventDescriptionText = new FlxText(objX, objY, rightEdge - objX, getEventDesc(defaultEvents[0][0], defaultEvents[0][1]));
		eventDescriptionText.font = Paths.font(Language.get('uitab_font'));
		eventDescriptionText.size = 12;

		tab_group.add(new FlxText(eventDropDown.x, eventDropDown.y - 15, 80, Language.get('charting_event_drop')).setFormat(Paths.font(Language.get('uitab_font')), 12));
		tab_group.add(new FlxText(value1InputText.x, value1InputText.y - 15, 80, Language.get('charting_value1')).setFormat(Paths.font(Language.get('uitab_font')), 12));
		tab_group.add(new FlxText(value2InputText.x, value2InputText.y - 15, 80, Language.get('charting_value2')).setFormat(Paths.font(Language.get('uitab_font')), 12));
		tab_group.add(new FlxText(value3InputText.x, value3InputText.y - 15, 80, Language.get('charting_value3')).setFormat(Paths.font(Language.get('uitab_font')), 12));
		tab_group.add(new FlxText(value4InputText.x, value4InputText.y - 15, 80, Language.get('charting_value4')).setFormat(Paths.font(Language.get('uitab_font')), 12));

		tab_group.add(removeButton);
		tab_group.add(addButton);
		tab_group.add(leftButton);
		tab_group.add(rightButton);
		tab_group.add(selectedEventText);

		tab_group.add(value1InputText);
		tab_group.add(value2InputText);
		tab_group.add(value3InputText);
		tab_group.add(value4InputText);
		tab_group.add(eventDescriptionText);
		
		tab_group.add(eventDropDown); //lowest priority to display properly
	}

	function createSearchBox()
	{
		var searchBoxTabs = [Language.get('charting_search_box_title')];
		searchBox = new PsychUIBox(mainBox.x - 290, mainBox.y + 310, 280, 200, searchBoxTabs);
		searchBox.cameras = [camUI];
		searchBox.scrollFactor.set();
		searchBox.visible = false;
		add(searchBox);

		var tab = searchBox.getTab(searchBoxTabs[0]);
		var tab_group = tab.menu;
		var objX = 10;
		var objY = 25;

		eventSearchInputText = new PsychUIInputText(objX, objY, 200, '', 12);
		tab_group.add(new FlxText(objX, objY - 15, 80, Language.get('charting_event_search_label')).setFormat(Paths.font(Language.get('uitab_font')), 12));
		tab_group.add(eventSearchInputText);

		objY += 42;
		eventSearchButton = new PsychUIButton(objX, objY, Language.get('charting_event_search_btn'), function()
		{
			searchEvents(eventSearchInputText.text.trim());
		}, 55);
		eventSearchPrevButton = new PsychUIButton(objX + 60, objY, '<', function()
		{
			if(_eventSearchResults.length > 0) _jumpToSearchResult(_currentSearchResultIdx - 1, false, '');
		}, 20);
		eventSearchNextButton = new PsychUIButton(objX + 85, objY, '>', function()
		{
			if(_eventSearchResults.length > 0) _jumpToSearchResult(_currentSearchResultIdx + 1, false, '');
		}, 20);
		eventSearchClearButton = new PsychUIButton(objX + 110, objY, Language.get('charting_event_search_clear_btn'), function()
		{
			eventSearchInputText.text = '';
			_eventSearchResults = [];
			_lastSearchStr = '';
			_currentSearchResultIdx = 0;
			eventSearchResultLine1.text = '';
			eventSearchResultLine1.visible = false;
			eventSearchResultLine2.text = '';
			eventSearchResultLine2.visible = false;
			eventSearchResultLine3.text = '';
			eventSearchResultLine3.visible = false;
		}, 50);
		tab_group.add(eventSearchButton);
		tab_group.add(eventSearchPrevButton);
		tab_group.add(eventSearchNextButton);
		tab_group.add(eventSearchClearButton);

		var font = Paths.font(Language.get('uitab_font'));
		eventSearchResultLine1 = new FlxText(objX, objY + 42, 260, '', 13).setFormat(font, 13);
		eventSearchResultLine2 = new FlxText(objX, objY + 60, 260, '', 13).setFormat(font, 13);
		eventSearchResultLine3 = new FlxText(objX, objY + 78, 260, '', 13).setFormat(font, 13);
		eventSearchResultLine3.visible = false;
		tab_group.add(eventSearchResultLine1);
		tab_group.add(eventSearchResultLine2);
		tab_group.add(eventSearchResultLine3);
	}

	var susLengthLastVal:Float = 0; //used for multiple notes selected
	var susLengthStepper:PsychUINumericStepper;
	var strumTimeStepper:PsychUINumericStepper;
	var noteTypeDropDown:PsychUIDropDownMenu;
	var noteTypes:Array<String>;
	function addNoteTab()
	{
		var tab_group = mainBox.getTab(Language.get('charting_notes_text')).menu;
		var objX = 10;
		var objY = 25;

		susLengthStepper = new PsychUINumericStepper(objX, objY, Conductor.stepCrochet / 2, 0, 0, Conductor.stepCrochet * 128, 1, 80);
		susLengthStepper.onValueChange = function()
		{
			var halfStep:Float = (Conductor.stepCrochet / 2);
			trace(halfStep, susLengthStepper.value);
			var val:Float = Math.round(susLengthStepper.value / halfStep) * halfStep;
			susLengthStepper.value = val;
			if(susLengthLastVal != susLengthStepper.value)
			{
				if(selectedNotes.length > 1)
				{
					for (note in selectedNotes)
					{
						if(note == null && !note.isEvent) continue;
						note.setSustainLength(note.sustainLength + (susLengthStepper.value - susLengthLastVal), Conductor.stepCrochet, curZoom);
					}
				}
				else if(selectedNotes.length == 1) selectedNotes[0].setSustainLength(susLengthStepper.value, Conductor.stepCrochet, curZoom);
				susLengthLastVal = susLengthStepper.value;
				chartDataDirty = true;
			}
		};

		objY += 40;
		strumTimeStepper = new PsychUINumericStepper(objX, objY, Conductor.stepCrochet, 0, -5000, Math.POSITIVE_INFINITY, 3, 120);
		strumTimeStepper.onValueChange = function()
		{
			if(selectedNotes.length < 1) return;

			var firstTime:Float = selectedNotes[0].strumTime;
			for (note in selectedNotes)
			{
				if(note == null) continue;

				note.setStrumTime(Math.max(-5000, strumTimeStepper.value + (note.strumTime - firstTime)));
				positionNoteYOnTime(note, curSec);

				if(note.isEvent)
				{
					cast (note, EventMetaNote).updateEventText();
				}
			}
			softReloadNotes();
			chartDataDirty = true;
		};
		
		objY += 40;
		noteTypeDropDown = new PsychUIDropDownMenu(objX, objY, [], function(id:Int, changeToType:String)
		{
			var newSelected:Array<MetaNote> = [];
			var typeSelected:String = noteTypes[id].trim();
			for (note in selectedNotes)
			{
				if(note == null || note.isEvent) continue;

				if(typeSelected != null && typeSelected.length > 0)
					note.songData[3] = typeSelected;
				else
					note.songData.remove(note.songData[3]);

				var id:Int = notes.indexOf(note);
				if(id > -1)
				{
					notes[id] = createNote(note.songData, curSec);
					actionReplaceNotes(note, notes[id]);
					newSelected.push(notes[id]);
					note.destroy();
				}
			}
			selectedNotes = newSelected;
			softReloadNotes();
			chartDataDirty = true;
		}, 150);
		
		tab_group.add(new FlxText(susLengthStepper.x, susLengthStepper.y - 15, 80, Language.get('charting_sustainlength_text')).setFormat(Paths.font(Language.get('uitab_font')), 12));
		tab_group.add(new FlxText(strumTimeStepper.x, strumTimeStepper.y - 15, 140, Language.get('charting_notetime_text')).setFormat(Paths.font(Language.get('uitab_font')), 12));
		tab_group.add(new FlxText(noteTypeDropDown.x, noteTypeDropDown.y - 15, 80, Language.get('charting_notetype_text')).setFormat(Paths.font(Language.get('uitab_font')), 12));
		tab_group.add(susLengthStepper);
		tab_group.add(strumTimeStepper);
		tab_group.add(noteTypeDropDown);
	}

	var mustHitCheckBox:PsychUICheckBox;
	var gfSectionCheckBox:PsychUICheckBox;
	var altAnimSectionCheckBox:PsychUICheckBox;

	var changeBpmCheckBox:PsychUICheckBox;
	var changeBpmStepper:PsychUINumericStepper;
	var bpmRampStepper:PsychUINumericStepper;
	var beatsPerSecStepper:PsychUINumericStepper;

	function addSectionTab()
	{
		var copyLastSecStepper:PsychUINumericStepper = null;
		var tab_group = mainBox.getTab(Language.get('charting_section_text')).menu;
		var objX = 10;
		var objY = 10;
		function copyNotesOnSection(?secOff:Int = 0, ?showMessage:Bool = true) //Used on "Copy Section" and "Copy Last Section" buttons
		{
			var curSectionTime:Null<Float> = cachedSectionTimes[curSec - secOff];
			if(curSectionTime == null)
			{
				//showOutput('ERROR: Unknown section??', true);
				return;
			}

			var nextSectionTime:Null<Float> = cachedSectionTimes[curSec - secOff + 1];
			if(nextSectionTime == null) Math.POSITIVE_INFINITY;

			var notesCopyNum:Int = 0;
			if(affectNotes.checked)
			{
				copiedNotes = [];
				for (note in notes)
				{
					if(note.strumTime >= curSectionTime && note.strumTime < nextSectionTime)
					{
						var dataCopy:Array<Dynamic> = makeNoteDataCopy(note.songData, false);
						dataCopy[0] = note.strumTime - curSectionTime;
						copiedNotes.push(dataCopy);
						notesCopyNum++;
					}
				}
			}

			var eventsCopyNum:Int = 0;
			if(affectEvents.checked)
			{
				copiedEvents = [];
				for (event in events)
				{
					if(event.strumTime >= curSectionTime && event.strumTime < nextSectionTime)
					{
						var dataCopy:Array<Dynamic> = makeNoteDataCopy(event.songData, true);
						dataCopy[0] = event.strumTime - curSectionTime;
						copiedEvents.push(dataCopy);
						eventsCopyNum++;
					}
				}
			}

			if(showMessage)
			{
				if(notesCopyNum == 0 && eventsCopyNum == 0)
				{
					showOutput(Language.get('charting_msg_nothingcopy'), true);
					return;
				}

				var str:String = '';
				if(notesCopyNum > 0) str += 'Notes Copied: $notesCopyNum';
				if(eventsCopyNum > 0)
				{
					if(str.length > 0) str += '\n';
					str += 'Events Copied: $eventsCopyNum';
				}
	
				if(str.length > 0) showOutput(str);
			}
		}

		mustHitCheckBox = new PsychUICheckBox(objX, objY, Language.get('charting_musthitsec_text'), 100, function()
		{
			var sec = getCurChartSection();
			if(sec != null) sec.mustHitSection = mustHitCheckBox.checked;
			updateHeads(true);
			chartDataDirty = true;
		});
		gfSectionCheckBox = new PsychUICheckBox(objX + 110, objY, Language.get('charting_gfsec_text'), 100, function()
		{
			var sec = getCurChartSection();
			if(sec != null) sec.gfSection = gfSectionCheckBox.checked;
			updateHeads(true);
			chartDataDirty = true;
		});
		altAnimSectionCheckBox = new PsychUICheckBox(objX + 220, objY, Language.get('charting_altanim_text'), 100, function()
		{
			var sec = getCurChartSection();
			if(sec != null) sec.altAnim = altAnimSectionCheckBox.checked;
			chartDataDirty = true;
		});

		objY += 40;
		changeBpmCheckBox = new PsychUICheckBox(objX, objY, Language.get('charting_changebpm_text'), 100, function()
		{
			var sec = getCurChartSection();
			if(sec != null)
			{
				var oldTimes:Array<Float> = cachedSectionTimes.copy();
				sec.changeBPM = changeBpmCheckBox.checked;
				if(!Reflect.hasField(sec, 'bpm')) sec.bpm = changeBpmStepper.value;
			adaptNotesToNewTimes(oldTimes);
			chartDataDirty = true;
		}
	});

	objY += 25;
	changeBpmStepper = new PsychUINumericStepper(objX, objY, 1, 0, 1, 10000, 3, 100);
	changeBpmStepper.onValueChange = function()
	{
		var sec = getCurChartSection();
		if(sec != null)
		{
			var oldTimes:Array<Float> = cachedSectionTimes.copy();
			sec.bpm = changeBpmStepper.value;
			sec.changeBPM = true;
			changeBpmCheckBox.checked = true;
			adaptNotesToNewTimes(oldTimes);
			chartDataDirty = true;
		}
	};

		objY += 35;
	var bpmRampLabel = new FlxText(changeBpmStepper.x, objY - 15, 100, Language.get('charting_bpm_ramp'));
		bpmRampLabel.setFormat(Paths.font(Language.get('uitab_font')), 12);
		tab_group.add(bpmRampLabel);
		bpmRampStepper = new PsychUINumericStepper(changeBpmStepper.x, objY, 1, 0, 0, 9999, 0, 100);
		bpmRampStepper.onValueChange = function()
		{
			var sec = getCurChartSection();
			if(sec != null)
			{
				var oldTimes:Array<Float> = cachedSectionTimes.copy();
				sec.bpmRamp = bpmRampStepper.value;
				if(bpmRampStepper.value > 0)
				{
					sec.changeBPM = true;
					if(sec.bpm == null) sec.bpm = changeBpmStepper.value;
				}
				adaptNotesToNewTimes(oldTimes);
				softReloadNotes();
				chartDataDirty = true;
			}
		};

		var beatsLabel = new FlxText(objX + 150, objY - 15, 110, Language.get('charting_beatspersec_text'));
		beatsLabel.setFormat(Paths.font(Language.get('uitab_font')), 12);
		tab_group.add(beatsLabel);
		beatsPerSecStepper = new PsychUINumericStepper(objX + 150, objY, 1, 4, 1, 16, 2, 100);
		beatsPerSecStepper.onValueChange = function()
		{
			beatsPerSecStepper.value = Math.round(beatsPerSecStepper.value * 4) / 4;
			var sec = getCurChartSection();
			if(sec != null)
			{
				var oldTimes:Array<Float> = cachedSectionTimes.copy();
				sec.sectionBeats = beatsPerSecStepper.value;
				adaptNotesToNewTimes(oldTimes);
				chartDataDirty = true;
			}
		};

		objY += 40;
		var copyButton:PsychUIButton = new PsychUIButton(objX, objY, Language.get('charting_copysec_button'), copyNotesOnSection.bind());
		var pasteButton:PsychUIButton = new PsychUIButton(objX + 100, objY, Language.get('charting_pastesec_button'), function()
		{
			pasteCopiedNotesToSection(affectNotes.checked, affectEvents.checked);
		});
		var clearButton:PsychUIButton = new PsychUIButton(objX + 200, objY, Language.get('charting_clearsec_button'), function()
		{
			for (note in curRenderedNotes)
			{
				if(note == null) continue;

				if(!note.isEvent && affectNotes.checked)
					notes.remove(note);
				if(note.isEvent && affectEvents.checked)
					events.remove(cast (note, EventMetaNote));

				selectedNotes.remove(note);
			}
			softReloadNotes(true);
			chartDataDirty = true;
		});
		clearButton.normalStyle.bgColor = FlxColor.RED;
		clearButton.normalStyle.textColor = FlxColor.WHITE;

		objY += 25;
		affectNotes = new PsychUICheckBox(objX, objY, Language.get('charting_notes_text'), 60, function()
		{
			refreshDedupeButtons();
		});
		affectNotes.checked = true;
		affectEvents = new PsychUICheckBox(objX + 100, objY, Language.get('charting_events_text'), 60, function()
		{
			refreshDedupeButtons();
		});

		// 两套去重按钮：
		// "-1 重复"：仅当前小节，每个重复组仅删除 1 个（N→N-1，可多次点击逐步减）
		// "清除重复"：整个谱面，每组保留 1 个、删除其余 N-1 个
		objY += 25;
		dedupe1Button = new PsychUIButton(objX, objY, Language.get('charting_dedupesec_button'), function()
		{
			dedupeSection(false, true);
		});
		clearDupButton = new PsychUIButton(objX + 100, objY, Language.get('charting_cleardup_button'), function()
		{
			dedupeSection(true, false);
		});
		refreshDedupeButtons();

		objY += 32;
		var copyLastSecButton:PsychUIButton = new PsychUIButton(objX, objY, Language.get('charting_copylastsec_button'), function()
		{
			var lastCopiedNotes = copiedNotes;
			var lastCopiedEvents = copiedEvents;
			copyNotesOnSection(Std.int(copyLastSecStepper.value), false);
			pasteCopiedNotesToSection(affectNotes.checked, affectEvents.checked);
			copiedNotes = lastCopiedNotes;
			copiedEvents = lastCopiedEvents;
		});
		copyLastSecButton.resize(80, 26);
		copyLastSecStepper = new PsychUINumericStepper(objX + 110, objY + 2, 1, 1, -999, 999, 0);
		
		objY += 40;
		var swapSectionButton:PsychUIButton = new PsychUIButton(objX, objY, Language.get('charting_swapsec_button'), function()
		{
			var maxData:Int = GRID_COLUMNS_PER_PLAYER * GRID_PLAYERS;
			for (note in curRenderedNotes)
			{
				if(note != null && !note.isEvent)
				{
					var data:Int = note.songData[1] + GRID_COLUMNS_PER_PLAYER;
					if(data >= maxData) data -= maxData;
					note.changeNoteData(data);
					positionNoteXByData(note);
				}
			}
			softReloadNotes(true);
			chartDataDirty = true;
		});
		var duetSectionButton:PsychUIButton = new PsychUIButton(objX + 100, objY, Language.get('charting_duetsec_button'), function()
		{
			var side:Int = -1;
			for (note in curRenderedNotes.members)
			{
				if(note == null || note.isEvent) continue;

				//First figure out if there are notes on more than one player's sides to cancel operation early
				if(side > -1)
				{
					if(Math.floor(note.songData[1] / GRID_COLUMNS_PER_PLAYER) != side)
					{
						showOutput(Language.get('charting_msg_morethanoneside'));
						return;
					}
				}
				else side = Math.floor(note.songData[1] / GRID_COLUMNS_PER_PLAYER);
			}

			var pushedNotes:Array<MetaNote> = [];
			for (note in curRenderedNotes.members)
			{
				if(note == null || note.isEvent) continue;

				for (i in 0...GRID_PLAYERS)
				{
					if(i == side) continue;

					var songDataCopy:Array<Dynamic> = note.songData.copy();
					songDataCopy[1] = note.noteData + i * GRID_COLUMNS_PER_PLAYER;
					var newNote = createNote(songDataCopy);
					notes.push(newNote);
					pushedNotes.push(newNote);
				}
			}
			notes.sort(PlayState.sortByTime);
			softReloadNotes(true);
			
			addUndoAction(ADD_NOTE, {notes: pushedNotes});
		});
		var mirrorNotesButton:PsychUIButton = new PsychUIButton(objX + 200, objY, Language.get('charting_mirrornote_button'), function()
		{
			var maxData:Int = GRID_COLUMNS_PER_PLAYER * GRID_PLAYERS;
			for (note in curRenderedNotes)
			{
				if(note == null || note.isEvent) continue;

				var data:Int = Std.int(note.songData[1]);
				note.changeNoteData((Math.floor(data / GRID_COLUMNS_PER_PLAYER) * GRID_COLUMNS_PER_PLAYER) + GRID_COLUMNS_PER_PLAYER - note.noteData - 1);
				positionNoteXByData(note);
			}
			softReloadNotes(true);
			chartDataDirty = true;
		});

		tab_group.add(mustHitCheckBox);
		tab_group.add(gfSectionCheckBox);
		tab_group.add(altAnimSectionCheckBox);

		tab_group.add(new FlxText(beatsPerSecStepper.x, beatsPerSecStepper.y - 15, 100, Language.get('charting_beatspersec_text')).setFormat(Paths.font(Language.get('uitab_font')), 12));
		tab_group.add(changeBpmCheckBox);
		tab_group.add(changeBpmStepper);
		tab_group.add(bpmRampStepper);
		tab_group.add(beatsPerSecStepper);
		
		tab_group.add(copyButton);
		tab_group.add(pasteButton);
		tab_group.add(clearButton);
		tab_group.add(affectNotes);
		tab_group.add(affectEvents);
		tab_group.add(dedupe1Button);
		tab_group.add(clearDupButton);

		tab_group.add(copyLastSecButton);
		tab_group.add(copyLastSecStepper);

		tab_group.add(swapSectionButton);
		tab_group.add(duetSectionButton);
		tab_group.add(mirrorNotesButton);
	}

	function reloadNotesDropdowns()
	{
		// Event drop down
		if(eventDropDown != null)
		{
			eventsList = [];
			var eventFiles:Array<String> = loadFileList('custom_events/', ['.txt']);

			// Also scan per-song data folder for custom_events
			var songFolder:String = _getSongDataFolder();
			var perSongEventNames:Array<String> = [];
			if(songFolder != null)
			{
				var perSongEventsPath:String = songFolder + 'custom_events/';
				#if MODS_ALLOWED
				if(FileSystem.exists(perSongEventsPath))
				{
					for (file in Paths.readDirectory(perSongEventsPath))
					{
						var fileName:String = file;
						if(fileName.toLowerCase().endsWith('.txt'))
						{
							fileName = fileName.substr(0, fileName.length - 4);
							if(!eventFiles.contains(fileName))
							{
								eventFiles.push(fileName);
								perSongEventNames.push(fileName);
							}
						}
					}
				}
				#end
			}

			for (file in eventFiles)
			{
				var desc:String = null;
				// Try per-song first, then global
				if(songFolder != null)
				{
					var perSongDescPath:String = songFolder + 'custom_events/' + file + '.txt';
					#if MODS_ALLOWED
					if(FileSystem.exists(perSongDescPath))
						desc = File.getContent(perSongDescPath);
					#end
				}
				if(desc == null)
					desc = Paths.getTextFromFile('custom_events/$file.txt');
				eventsList.push([file, desc]);
			}

			for (id => event in defaultEvents)
				if(!eventsList.contains(event))
					eventsList.insert(id, event);
			
			var displayEventsList:Array<String> = [];
			var perSongEventIndices:Array<Int> = [];
			for (id => data in eventsList)
			{
				var evName:String = data[0];
				if(perSongEventNames.contains(evName))
					perSongEventIndices.push(id);
				if(id > 0)
					displayEventsList[id] = data[0];
				else
					displayEventsList.push('');
			}

			var lastSelected:String = eventDropDown.selectedLabel;
			eventDropDown.list = displayEventsList;
			eventDropDown.selectedLabel = lastSelected;
			for (idx in perSongEventIndices)
				eventDropDown.markItem(idx);
		}

		// Note type drop down
		if(noteTypeDropDown != null)
		{
			var exts:Array<String> = ['.txt'];
			#if LUA_ALLOWED exts.push('.lua'); #end
			#if HSCRIPT_ALLOWED exts.push('.hx'); #end
			noteTypes = loadFileList('custom_notetypes/', exts);

			// Also scan per-song data folder for custom_notetypes
			var songFolder2:String = _getSongDataFolder();
			var perSongNoteTypeNames:Array<String> = [];
			if(songFolder2 != null)
			{
				var perSongTypesPath:String = songFolder2 + 'custom_notetypes/';
				#if MODS_ALLOWED
				if(FileSystem.exists(perSongTypesPath))
				{
					for (file in Paths.readDirectory(perSongTypesPath))
					{
						var tn:String = file;
						var tnExt:String = '';
						if(tn.toLowerCase().endsWith('.txt')) { tn = tn.substr(0, tn.length - 4); tnExt = '.txt'; }
						else if(tn.toLowerCase().endsWith('.lua')) { tn = tn.substr(0, tn.length - 4); tnExt = '.lua'; }
						else if(tn.toLowerCase().endsWith('.hx')) { tn = tn.substr(0, tn.length - 3); tnExt = '.hx'; }
						if(tnExt.length > 0 && !noteTypes.contains(tn))
						{
							noteTypes.push(tn);
							perSongNoteTypeNames.push(tn);
						}
					}
				}
				#end
			}

			for (id => noteType in Note.defaultNoteTypes)
				if(!noteTypes.contains(noteType))
					noteTypes.insert(id, noteType);

			if(Song.chartPath != null && Song.chartPath.length > 0)
			{
				var parentFolder:String = Song.chartPath.replace('\\', '/');
				parentFolder = parentFolder.substr(0, Song.chartPath.lastIndexOf('/')+1);
				var notetypeFile:Array<String> = CoolUtil.coolTextFile(parentFolder + 'notetypes.txt');
				if(notetypeFile.length > 0)
				{
					for (ntTyp in notetypeFile)
					{
						var name:String = ntTyp.trim();
						if(!noteTypes.contains(name))
							noteTypes.push(name);
					}
				}
			}
			
			var displayNoteTypes:Array<String> = noteTypes.copy();
			var perSongNoteTypeIndices:Array<Int> = [];
			for (id => key in displayNoteTypes)
			{
				if(perSongNoteTypeNames.contains(noteTypes[id]))
					perSongNoteTypeIndices.push(id);
				if(id == 0) continue;
				displayNoteTypes[id] = '$id. $key';
			}
			
			var lastSelected:String = noteTypeDropDown.selectedLabel;
			noteTypeDropDown.list = displayNoteTypes;
			noteTypeDropDown.selectedLabel = lastSelected;
			for (idx in perSongNoteTypeIndices)
				noteTypeDropDown.markItem(idx);
		}
	}

	function _getSongDataFolder():String
	{
		if(Song.chartPath == null || Song.chartPath.length < 1) return null;

		var normalizedPath:String = Song.chartPath.replace('\\', '/');
		var lastSlash:Int = normalizedPath.lastIndexOf('/');
		if(lastSlash < 0) return null;

		var chartFileName:String = normalizedPath.substr(lastSlash + 1);
		var songName:String = chartFileName;
		// Remove common extensions
		if(songName.endsWith('.json')) songName = songName.substr(0, songName.length - 5);
		if(songName.endsWith('.txt')) songName = songName.substr(0, songName.length - 4);

		var basePath:String = normalizedPath.substr(0, lastSlash + 1);

		// Check if we're already in a data/<song>/ folder
		var dataIdx:Int = basePath.indexOf('data/');
		if(dataIdx >= 0)
		{
			var afterData:String = basePath.substr(dataIdx + 5);
			var songFolderEnd:Int = afterData.indexOf('/');
			if(songFolderEnd > 0)
			{
				var extractedSong:String = afterData.substr(0, songFolderEnd);
				if(extractedSong.length > 0)
					return basePath.substr(0, dataIdx + 5) + extractedSong + '/';
			}
		}

		// Fallback: use song name from chart file name
		#if MODS_ALLOWED
		var songDataPath:String = Paths.getSharedPath('data/' + songName + '/');
		if(FileSystem.exists(songDataPath)) return songDataPath;
		#end

		return null;
	}

	function pasteCopiedNotesToSection(?canCopyNotes:Bool = true, ?canCopyEvents:Bool = true, ?showMessage:Bool = true) //Used on "Paste Section" and "Copy Last Section" buttons
	{
		var curSectionTime:Null<Float> = cachedSectionTimes[curSec];
		if(curSectionTime == null)
		{
			showOutput(Language.get('charting_msg_unknown_sec'), true);
			return [];
		}

		var pushedNotes:Array<MetaNote> = [];
		var nts:Array<MetaNote> = [];
		var evs:Array<EventMetaNote> = [];
		if(canCopyNotes && copiedNotes.length > 0)
		{
			for (note in copiedNotes)
			{
				if(note == null) continue;
				var dataCopy:Array<Dynamic> = makeNoteDataCopy(note, false);
				dataCopy[0] += curSectionTime;

				var createdNote = createNote(dataCopy, curSec);
				notes.push(createdNote);
				pushedNotes.push(createdNote);
				nts.push(createdNote);
			}
			notes.sort(PlayState.sortByTime);
		}

		if(canCopyEvents && copiedEvents.length > 0)
		{
			for (event in copiedEvents)
			{
				if(event == null) continue;
				var dataCopy:Array<Dynamic> = makeNoteDataCopy(event, true);
				dataCopy[0] += curSectionTime;

				var createdEvent = createEvent(dataCopy);
				events.push(createdEvent);
				pushedNotes.push(createdEvent);
				evs.push(createdEvent);
			}
			events.sort(PlayState.sortByTime);
		}
		loadSection();
		
		if(showMessage)
		{
			if(nts.length == 0 && evs.length == 0)
			{
				showOutput(Language.get('charting_msg_nothingpaste'), true);
				return [];
			}

			var str:String = '';
			if(nts.length > 0) str += 'Notes Added: ${nts.length}';
			if(evs.length > 0)
			{
				if(str.length > 0) str += '\n';
				str += 'Events Added: ${evs.length}';
			}

			if(str.length > 0) showOutput(str);
		}
		addUndoAction(ADD_NOTE, {notes: nts, events: evs});
		return pushedNotes;
	}

	var songNameInputText:PsychUIInputText;
	var allowVocalsCheckBox:PsychUICheckBox;

	var bpmStepper:PsychUINumericStepper;
	var scrollSpeedStepper:PsychUINumericStepper;
	var audioOffsetStepper:PsychUINumericStepper;
	var maniaStepper:PsychUINumericStepper; // Extra Keys：键数档位 stepper
	var opponentKeyStepper:PsychUINumericStepper; // LE LTS 双侧：对手侧键数（keyCount）
	var opponentKeyStepperText:FlxText; // 对手侧键数标签
	var editPlayerBtn:PsychUIButton; // LE LTS 双侧：编辑侧切换（玩家）
	var editOpponentBtn:PsychUIButton; // LE LTS 双侧：编辑侧切换（对手）
 	var specialInstInputText:PsychUIInputText;
	var specialVocalInputText:PsychUIInputText;
	var specialEventsInputText:PsychUIInputText;

	var stageDropDown:PsychUIDropDownMenu;
	var playerDropDown:PsychUIDropDownMenu;
	var opponentDropDown:PsychUIDropDownMenu;
	var girlfriendDropDown:PsychUIDropDownMenu;
	
	function addSongTab()
	{
		var tab_group = mainBox.getTab(Language.get('charting_song_text')).menu;
		var objX = 10;
		var objY = 25;

		songNameInputText = new PsychUIInputText(objX, objY, 100, 'None', 12);
		songNameInputText.onChange = function(old:String, cur:String) PlayState.SONG.song = cur;

		allowVocalsCheckBox = new PsychUICheckBox(objX, objY + 20, Language.get('charting_allvoc_text'), 80, function()
		{
			PlayState.SONG.needsVoices = allowVocalsCheckBox.checked;
			loadMusic();
		});
		var reloadAudioButton:PsychUIButton = new PsychUIButton(objX + 120, objY, Language.get('charting_reaudio_button'), function() loadMusic(true), 80);

		#if (mac || mobile)
		var reloadJsonButton:PsychUIButton = new PsychUIButton(objX + 205, objY, Language.get('charting_rejsonm_button'), function()
		{
			var cur = Paths.formatToSongPath(songNameInputText.text);
			var curdiff = Highscore.formatSong(cur, PlayState.storyDifficulty);
			var diff = false;
			var loadedChart:SwagSong = try {
				diff = true;
				Song.getChart(curdiff, cur);
			} catch (e) {
				diff = false;
				Song.getChart(cur, cur);
			}
			if(loadedChart == null || !Reflect.hasField(loadedChart, 'song')) //Check if chart is ACTUALLY a chart and valid
			{
				showOutput(Language.get('charting_msg_notchart'), true);
				return;
			}

			var func:Void->Void = function()
			{
				loadChart(loadedChart);
				Song.chartPath = diff ? curdiff : cur;
				reloadNotesDropdowns();
				prepareReload();
				showOutput(Language.get('charting_msg_chart_opened', [diff ? curdiff : cur]));
			}
					
			if(!ignoreProgressCheckBox.checked) openSubState(new Prompt(Language.get('prompt_unsaved'), func));
			else func();
		}, 80);
		#end

		objY += 65;
		//(x:Float = 0, y:Float = 0, step:Float = 1, defValue:Float = 0, min:Float = -999, max:Float = 999, decimals:Int = 0, ?wid:Int = 60, ?isPercent:Bool = false)
		bpmStepper = new PsychUINumericStepper(objX, objY, 1, 1, 1, 10000, 3, 80);
		bpmStepper.onValueChange = function()
		{
			var oldTimes:Array<Float> = cachedSectionTimes.copy();
			PlayState.SONG.bpm = bpmStepper.value;
			adaptNotesToNewTimes(oldTimes);
		};

		scrollSpeedStepper = new PsychUINumericStepper(objX + 110, objY, 0.1, 1, 0.1, 10000, 2, 80);
		scrollSpeedStepper.onValueChange = function() PlayState.SONG.speed = scrollSpeedStepper.value;

		audioOffsetStepper = new PsychUINumericStepper(objX + 220, objY, 1, 0, -500, 500, 0, 100);
		audioOffsetStepper.onValueChange = function()
		{
			PlayState.SONG.offset = audioOffsetStepper.value;
			Conductor.offset = audioOffsetStepper.value;
			updateWaveform();
		};

		// LE LTS 双侧：键数变化后刷新编辑侧按钮可见性与当前编辑侧有效性（两侧同值时无分侧编辑概念）
		function refreshDualUI():Void
		{
			var dual:Bool = isDualChart();
			if (editPlayerBtn != null) editPlayerBtn.visible = dual;
			if (editOpponentBtn != null) editOpponentBtn.visible = dual;
			if (!dual) ChartingState.editorSide = 0; // 非双侧恒为玩家侧语义
			refreshEditSideButtons();
		}

		// Extra Keys：键数档位（0=1键 ... 17=18键；4 键 = 3）。改键数会重建网格列数与轨道色块。
		// 位置：BPM 所在行的下一行（objY+40）第一列（objX）；对手键数在第二列（objX+110）。
		// LE LTS 双侧（分侧编辑，两个独立设置项）：此 stepper = 玩家侧键数（playerKeyCount，1..18），始终显示；
		// 对手侧键数（keyCount）由 opponentKeyStepper 独立控制。两者相等时保存为 EK/Psych 格式（mania），不等时保存为 LE 格式。
		// 注意：此处 value 为"键数"（1..18），与对手 stepper 同单位；内部换算档位 = 键数-1。
		// 两个 stepper 完全独立：改玩家只改玩家侧（playerKeyCount + mania），改对手只改对手侧（keyCount），
		// 互不同步——相等/不等由实际值决定，保存时自动切换 EK mania / LE keyCount+playerKeyCount 格式。
		maniaStepper = new PsychUINumericStepper(objX, objY + 40, 1, 4, 1, 18, 0, 80);
		maniaStepper.onValueChange = function()
		{
			var newKeys:Int = Std.int(maniaStepper.value);
			// 记录改键前边界（供重编码保持音符侧不变）。Psych/EK 谱面（非双侧）用 mania+1 作为玩家侧键数。
			var oldDualM:Bool = isDualChart();
			var oldPlrM:Int = oldDualM ? dualPlayerKeyCount() : ((PlayState.SONG.mania != null) ? Std.int(PlayState.SONG.mania) + 1 : 4);
			var oldOppM:Int = oldDualM ? dualOpponentKeyCount() : oldPlrM;
			// Psych/EK 谱面 keyCount 为 null：进入双侧语义前补齐对手侧 = 原 mania+1（原始 4 键）。
			// 否则 isDualChart() 恒 false，对手侧网格会跟着玩家侧 mania 一起变（初次调整"双方同时变化"）。
			if (PlayState.SONG.keyCount == null)
				PlayState.SONG.keyCount = ((PlayState.SONG.mania != null) ? Std.int(PlayState.SONG.mania) : 3) + 1;
			PlayState.SONG.mania = newKeys - 1;
			PlayState.SONG.playerKeyCount = newKeys;
			if (isDualChart() && oldPlrM != newKeys)
				reencodeChartNotes(oldPlrM, oldOppM, oldDualM); // 保持侧+侧内列不变，按新键数重编码 LE 编号
			refreshDualUI();
			applySectionColumns(curSec);
			reloadNotes(); // 改键后重建音符：已放置箭头的列/位置需按新网格重新映射
			updateJsonData();
		};

		// LE LTS 双侧：对手侧键数（keyCount，1..18），BPM 下一行第二列（objX+110），始终显示（Psych/EK 谱面默认为玩家侧同值）。
		opponentKeyStepper = new PsychUINumericStepper(objX + 110, objY + 40, 1, 4, 1, 18, 0, 80);
		opponentKeyStepper.onValueChange = function()
		{
			var newKeys:Int = Std.int(opponentKeyStepper.value);
			// 记录改键前边界：非双侧（Psych/EK）时两侧 = mania+1
			var oldDualO:Bool = isDualChart();
			var oldPlrO:Int = oldDualO ? dualPlayerKeyCount() : ((PlayState.SONG.mania != null) ? Std.int(PlayState.SONG.mania) + 1 : 4);
			var oldOppO:Int = oldDualO ? dualOpponentKeyCount() : oldPlrO;
			// 对称补齐：Psych/EK 谱面 playerKeyCount 为 null 时，先按原 mania+1 补齐玩家侧，再进入双侧语义
			if (PlayState.SONG.playerKeyCount == null)
				PlayState.SONG.playerKeyCount = ((PlayState.SONG.mania != null) ? Std.int(PlayState.SONG.mania) : 3) + 1;
			PlayState.SONG.keyCount = newKeys;
			if (isDualChart() && oldOppO != newKeys)
				reencodeChartNotes(oldPlrO, oldOppO, oldDualO); // 保持侧+侧内列不变，按新键数重编码 LE 编号
			refreshDualUI();
			applySectionColumns(curSec);
			reloadNotes(); // 改键后重建音符：已放置箭头的列/位置需按新网格重新映射
			updateJsonData();
		};
		opponentKeyStepper.visible = true;

		// LE LTS 双侧：编辑侧切换（玩家/对手），BPM 下一行第三列起（objX+220/objX+300）。双侧模式下网格列数 = 编辑侧键数（LE 式分侧编辑）。
		editPlayerBtn = new PsychUIButton(objX + 220, objY + 40, Language.get('charting_editside_player'), function()
		{
			if (ChartingState.editorSide != 0)
			{
				ChartingState.editorSide = 0;
				refreshEditSideButtons();
				applySectionColumns(curSec);
				updateJsonData();
			}
		});
		editOpponentBtn = new PsychUIButton(objX + 300, objY + 40, Language.get('charting_editside_opponent'), function()
		{
			if (ChartingState.editorSide != 1)
			{
				ChartingState.editorSide = 1;
				refreshEditSideButtons();
				applySectionColumns(curSec);
				updateJsonData();
			}
		});
		editPlayerBtn.visible = isDualChart();
		editOpponentBtn.visible = isDualChart();
		refreshEditSideButtons();


		tab_group.add(new FlxText(songNameInputText.x, songNameInputText.y - 15, 80, Language.get('charting_songname')).setFormat(Paths.font(Language.get('uitab_font')), 12));
		tab_group.add(songNameInputText);
		tab_group.add(allowVocalsCheckBox);
		tab_group.add(reloadAudioButton);
	#if (mac || mobile)
		tab_group.add(reloadJsonButton);
	#end
		tab_group.add(new FlxText(maniaStepper.x, maniaStepper.y - 15, 100, Language.get('charting_playerkeycount')).setFormat(Paths.font(Language.get('uitab_font')), 12));
		tab_group.add(maniaStepper);
		opponentKeyStepperText = new FlxText(opponentKeyStepper.x, opponentKeyStepper.y - 15, 120, Language.get('charting_oppkeycount')).setFormat(Paths.font(Language.get('uitab_font')), 12);
		opponentKeyStepperText.visible = true;
		tab_group.add(opponentKeyStepperText);
		tab_group.add(opponentKeyStepper);
		tab_group.add(editPlayerBtn);
		tab_group.add(editOpponentBtn);

	// Find characters
	var characters:Array<String> = [];
	//
		
		// LE LTS 双侧：对手侧键数 stepper/编辑侧按钮占用了 objY+40 一行，字符区整体下移 40px
		objY += 80;
		playerDropDown = new PsychUIDropDownMenu(objX, objY, [''], function(id:Int, character:String)
		{
			PlayState.SONG.player1 = character;
			updateJsonData();
			updateHeads(true);
			loadMusic();
			updateCharacters();
			trace('selected $character');
		}, 110);
		stageDropDown = new PsychUIDropDownMenu(objX + 130, objY, [''], function(id:Int, stage:String)
		{
			PlayState.SONG.stage = stage;
			StageData.loadDirectory(PlayState.SONG);
			trace('selected $stage');
		}, 110);
		
		opponentDropDown = new PsychUIDropDownMenu(objX, objY + 40, [''], function(id:Int, character:String)
		{
			PlayState.SONG.player2 = character;
			updateJsonData();
			updateHeads(true);
			loadMusic();
			updateCharacters();
			trace('selected $character');
		}, 110);
		
		girlfriendDropDown = new PsychUIDropDownMenu(objX, objY + 80, [''], function(id:Int, character:String)
		{
			PlayState.SONG.gfVersion = character;
			trace('selected $character');
		}, 110);

		// Special inputs on right column, aligned with opponent/girlfriend
		var rightX = objX + 150;
		specialInstInputText = new PsychUIInputText(rightX, objY + 40, 110, '', 12);
		specialInstInputText.onChange = function(old:String, cur:String)
		{
			PlayState.SONG.specialInst = specialInstInputText.text;
			//updateWaveform();
		};

		specialVocalInputText = new PsychUIInputText(rightX, objY + 80, 110, '', 12);
		specialVocalInputText.onChange = function(old:String, cur:String)
		{
			PlayState.SONG.specialVocal = specialVocalInputText.text;
			//updateWaveform();
		};

		specialEventsInputText = new PsychUIInputText(rightX, objY + 120, 110, '', 12);
		specialEventsInputText.onChange = function(old:String, cur:String)
		{
			PlayState.SONG.specialEvents = specialEventsInputText.text;
			//updateWaveform();
		};

		tab_group.add(new FlxText(bpmStepper.x, bpmStepper.y - 15, 80, Language.get('charting_bpm')).setFormat(Paths.font(Language.get('uitab_font')), 12));
		tab_group.add(new FlxText(scrollSpeedStepper.x, scrollSpeedStepper.y - 15, 80, Language.get('charting_scrollspeed')).setFormat(Paths.font(Language.get('uitab_font')), 12));
		tab_group.add(new FlxText(audioOffsetStepper.x, audioOffsetStepper.y - 15, 160, Language.get('charting_audiooffset')).setFormat(Paths.font(Language.get('uitab_font')), 12));
		tab_group.add(bpmStepper);
		tab_group.add(scrollSpeedStepper);
		tab_group.add(audioOffsetStepper);

		//dropdowns
		tab_group.add(new FlxText(stageDropDown.x, stageDropDown.y - 15, 80, Language.get('charting_stage')).setFormat(Paths.font(Language.get('uitab_font')), 12));
		tab_group.add(new FlxText(playerDropDown.x, playerDropDown.y - 15, 80, Language.get('charting_player')).setFormat(Paths.font(Language.get('uitab_font')), 12));
		tab_group.add(new FlxText(opponentDropDown.x, opponentDropDown.y - 15, 80, Language.get('charting_opponent')).setFormat(Paths.font(Language.get('uitab_font')), 12));
		tab_group.add(new FlxText(girlfriendDropDown.x, girlfriendDropDown.y - 15, 80, Language.get('charting_girlfriend')).setFormat(Paths.font(Language.get('uitab_font')), 12));
		tab_group.add(stageDropDown);
		tab_group.add(girlfriendDropDown);
		tab_group.add(opponentDropDown);
		tab_group.add(playerDropDown);

		// Special inputs labels and controls (right column)
		tab_group.add(new FlxText(specialInstInputText.x, specialInstInputText.y - 15, 120, Language.get('charting_special_inst')).setFormat(Paths.font(Language.get('uitab_font')), 12));
		tab_group.add(specialInstInputText);
		tab_group.add(new FlxText(specialVocalInputText.x, specialVocalInputText.y - 15, 120, Language.get('charting_special_vocal')).setFormat(Paths.font(Language.get('uitab_font')), 12));
		tab_group.add(specialVocalInputText);
		tab_group.add(new FlxText(specialEventsInputText.x, specialEventsInputText.y - 15, 120, Language.get('charting_special_events')).setFormat(Paths.font(Language.get('uitab_font')), 12));
		tab_group.add(specialEventsInputText);
	}

	function createHaxeUIMenuBar()
	{
		// 首次使用时初始化 HaxeUI Toolkit（幂等）；禁用 DPI 自动缩放，保证坐标与 Flixel 屏幕坐标一致
		if (!Toolkit.initialized)
		{
			Toolkit.autoScale = false;
			Toolkit.init();
		}

		haxeMenuBar = new MenuBar();
		haxeMenuBar.x = 0;
		haxeMenuBar.y = 0;
		haxeMenuBar.width = FlxG.width;
		haxeMenuBar.height = haxeMenuBarHeight;
		haxeMenuBar.percentWidth = 100; // 窗口缩放时菜单条自动跟随宽度
		haxeMenuBar.styleString = 'font-name: ${Paths.font(Language.get('uitab_font'))}; font-size: 12px;';

		var menuFont:String = Paths.font(Language.get('uitab_font'));
		var tabNames:Array<String> = [Language.get('charting_file_text'), Language.get('charting_edit_text'), Language.get('charting_view_text')];
		var menus:Array<Menu> = [];
		for (tabName in tabNames)
		{
			var tab:PsychUITab = upperBox.getTab(tabName);
			if (tab == null || tab.menu == null) continue;

			var menu:Menu = new Menu();
			menu.text = tabName;
			menu.styleString = 'font-name: $menuFont; font-size: 12px;';

			for (member in tab.menu.members)
			{
				if (!(member is PsychUIButton)) continue;
				var pb:PsychUIButton = cast member;
				if (pb.onClick == null) continue;

				var item:MenuItem = new MenuItem();
				item.text = (pb.label != null && pb.label.length > 0) ? pb.label : pb.text.text;
				item.styleString = 'font-name: $menuFont; font-size: 12px;';

				var onClick:Void->Void = pb.onClick;
				var thisMenu:Menu = menu; // 捕获当前菜单，供点击后立即收起下拉使用
				item.registerEvent(MouseEvent.CLICK, function(_)
				{
					ignoreClickForThisFrame = true;
					if (onClick != null) onClick();
					// 点击后立即收起下拉框：HaxeUI 默认延迟 100ms 收起，会被 openSubState 等打断，
					// 通过派发 UIEvent.CLOSE 触发 MenuBar 内部的 hideCurrentMenu 立即收起。
					thisMenu.dispatch(new HaxeUIEvent(HaxeUIEvent.CLOSE));
				});
				menu.addComponent(item);

				// 记录菜单项与底层按钮的映射，用于后续同步动态文本
				haxeMenuItemMappings.push({item: item, btn: pb});
				// 注册悬停浅蓝高亮
				registerMenuItemHover(item);
			}

			menus.push(menu);
			haxeMenuBarMenus.push(menu);
			haxeMenuBar.addComponent(menu);
		}

		// MenuBar.Builder 为每个 Menu 内部创建的按钮不继承容器的 styleString，默认主题字体不含中文字形，
		// 必须把游戏字体显式应用到菜单按钮、菜单项及其内部 label 上，否则中文显示为空白。
		applyMenuFont(haxeMenuBar, menuFont);
		for (menu in menus) applyMenuFont(menu, menuFont);

		// 加宽菜单条顶部按钮（文件/编辑/视图），保证文本有足够的显示长度
		for (child in haxeMenuBar.childComponents)
		{
			if (child is Button)
			{
				child.styleString = 'font-name: $menuFont; font-size: 12px; min-width: 100px;';
				registerTopBarButtonHover(cast child);
				haxeMenuBarButtons.push(cast child);
			}
		}

		haxeMenuBar.registerEvent(MenuEvent.MENU_OPENED, function(e:MenuEvent)
		{
			haxeMenuOpen = true;
			haxeMenuOpenMenu = e.menu;
			haxeMenuIgnoreFrames = 2;
			styleMenuComponent(e.menu); // 深浅色模式下套用下拉菜单配色
			setMenuButtonHighlight(e.menu, true); // 打开菜单的按钮高亮
		});
		haxeMenuBar.registerEvent(MenuEvent.MENU_CLOSED, function(_)
		{
			haxeMenuOpen = false;
			if (haxeMenuOpenMenu != null)
			{
				setMenuButtonHighlight(haxeMenuOpenMenu, false); // 关闭时恢复该按钮底色
				haxeMenuOpenMenu = null;
			}
			haxeMenuIgnoreFrames = 2;
		});

		Screen.instance.addComponent(haxeMenuBar);
	}

	/** 创建顶部条信息：FPS+内存峰值（水平居中一行）与版本（右上角），以 FlxText 叠加在菜单条之上渲染 */
	function createTopBarInfo()
	{
		var font:String = Paths.font(Language.get('uitab_font'));
		var fgColor:Int = isChartEditorLightTheme() ? 0xFF444444 : 0xFFFFFFFF;

		// FPS+内存峰值：全宽字段 + 水平居中，文本垂直居中对齐
		topBarFpsMemText = new FlxText(0, 0, FlxG.width, '', 12);
		topBarFpsMemText.setFormat(font, 12, fgColor, CENTER);
		topBarFpsMemText.scrollFactor.set();
		topBarFpsMemText.antialiasing = ClientPrefs.data.antialiasing;
		topBarFpsMemText.text = 'FPS: --    内存峰值: --MB';
		topBarFpsMemText.y = (haxeMenuBarHeight - topBarFpsMemText.height) / 2;
		add(topBarFpsMemText);

		// 版本号：右上角，右对齐
		topBarVersionText = new FlxText(0, 0, 200, 'v' + MainMenuState.psychEngineVersion, 12);
		topBarVersionText.setFormat(font, 12, fgColor, RIGHT);
		topBarVersionText.scrollFactor.set();
		topBarVersionText.antialiasing = ClientPrefs.data.antialiasing;
		topBarVersionText.x = FlxG.width - topBarVersionText.width - 8;
		topBarVersionText.y = (haxeMenuBarHeight - topBarVersionText.height) / 2;
		add(topBarVersionText);
	}

	/** 判断顶部 HaxeUI 菜单条当前应为浅色还是深色：优先取设置，设置默认时跟随制谱器内保存的主题 */
	function isChartEditorLightTheme():Bool
	{
		var pref:String = ClientPrefs.data.chartEditorTheme;
		if (pref == 'Light') return true;
		if (pref == 'Dark') return false;
		// 默认：跟随制谱器内保存的主题（LIGHT→浅色，其余→深色）
		return (theme == LIGHT);
	}

	/** 将深浅色配色套用到顶部菜单条、其按钮以及顶部条信息文字上 */
	function applyTopBarTheme()
	{
		var light:Bool = isChartEditorLightTheme();
		haxeMenuStyleLight = light;
		var bgColor:String = light ? '#f6f6f6' : '#3d3f41';
		var fgColor:String = light ? '#444444' : '#ffffff';
		var fgColorInt:Int = light ? 0xFF444444 : 0xFFFFFFFF;
		var borderColor:String = light ? '#d2d2d2' : '#555555';
		var font:String = Paths.font(Language.get('uitab_font'));

		if (haxeMenuBar != null)
		{
			haxeMenuBar.styleString = 'font-name: $font; font-size: 12px; background-color: $bgColor; color: $fgColor; border-bottom-color: $borderColor;';
			for (child in haxeMenuBar.childComponents)
			{
				if (child is Button)
					child.styleString = 'font-name: $font; font-size: 12px; min-width: 100px; background-color: $bgColor; color: $fgColor;';
			}
			haxeMenuBar.syncComponentValidation(false);
			// 主题切换重设了按钮 styleString，若此时有菜单打开，重新套用其按钮高亮
			if (haxeMenuOpenMenu != null)
				setMenuButtonHighlight(haxeMenuOpenMenu, true);
		}
		if (topBarFpsMemText != null)
			topBarFpsMemText.color = fgColorInt;
		if (topBarVersionText != null)
			topBarVersionText.color = fgColorInt;
	}

	/** 下拉菜单打开时，按当前深浅色配色递归套用到菜单及菜单项 */
	function styleMenuComponent(menu:Menu)
	{
		if (menu == null) return;
		var light:Bool = haxeMenuStyleLight;
		var menuBg:String = light ? '#ffffff' : '#2d2f31';
		var menuFg:String = light ? '#444444' : '#ffffff';
		var selBg:String = light ? '#b4cbe4' : '#4a6a8a';
		var border:String = light ? '#d2d2d2' : '#555555';
		var font:String = Paths.font(Language.get('uitab_font'));

		menu.styleString = 'background-color: $menuBg; border-color: $border;';
		styleMenuComponentRecursive(menu, menuBg, menuFg, selBg, font);
		menu.invalidateComponentStyle(true);
		menu.invalidateComponent();
	}

	/** 递归为菜单组件及其内部 label 套用深浅色配色 */
	function styleMenuComponentRecursive(comp:Component, menuBg:String, menuFg:String, selBg:String, font:String)
	{
		if (comp is MenuItem)
		{
			comp.styleString = 'font-name: $font; font-size: 12px; background-color: $menuBg; color: $menuFg;';
		}
		else if (comp is Label)
		{
			comp.styleString = 'font-name: $font; font-size: 12px; color: $menuFg;';
		}
		else if (comp is Menu)
		{
			comp.styleString = 'background-color: $menuBg; border-color: ${(menuBg == '#ffffff') ? '#d2d2d2' : '#555555'};';
		}
		for (child in comp.childComponents)
			styleMenuComponentRecursive(child, menuBg, menuFg, selBg, font);
	}

	/** 顶部条 FPS+内存实时刷新（独立计数，不依赖 Main.fpsVar；内存显示为 当前/峰值 MB） */
	function updateTopBarInfo(elapsed:Float)
	{
		if (topBarFpsMemText == null) return;
		// 独立 FPS 计数（基于帧数和时间，不受 Main.fpsVar.visible 影响）
		_topBarFrameCount++;
		_topBarFrameTime += elapsed;
		if (_topBarFrameTime >= 1.0)
		{
			_topBarFPS = _topBarFrameCount / _topBarFrameTime;
			_topBarFrameCount = 0;
			_topBarFrameTime = 0;
		}
		// 内存：独立节流查询系统内存（Main.fpsVar.visible=false 时其缓存不再刷新，不能依赖它）
		var now = haxe.Timer.stamp();
		if (now - _topBarLastMemQueryTime >= 0.5)
		{
			_topBarLastMemQueryTime = now;
			var mem:Float = 0;
			#if cpp
			try
			{
				var memValue:Dynamic = cpp.vm.Gc.memInfo64(cpp.vm.Gc.MEM_INFO_USAGE);
				if (Std.is(memValue, Float) || Std.is(memValue, Int))
				{
					var m:Float = cast memValue;
					if (Math.isFinite(m) && m >= 0)
						mem = m;
				}
			}
			catch (e:Dynamic) {}
			if (mem == 0)
			{
				try
				{
					var memValue2:Dynamic = cpp.vm.Gc.memInfo(cpp.vm.Gc.MEM_INFO_USAGE);
					if (Std.is(memValue2, Float) || Std.is(memValue2, Int))
					{
						var m2:Float = cast memValue2;
						if (Math.isFinite(m2) && m2 >= 0)
							mem = m2;
					}
				}
				catch (e2:Dynamic) {}
			}
			#end
			_topBarLastMemBytes = mem;
		}
		if (_topBarLastMemBytes > _topBarPeakMem)
			_topBarPeakMem = _topBarLastMemBytes;
		var curMB:Int = Std.int(_topBarLastMemBytes / (1024 * 1024));
		var peakMB:Int = Std.int(_topBarPeakMem / (1024 * 1024));
		var newText:String = 'FPS: ' + Std.int(_topBarFPS) + '    内存: ' + curMB + '/' + peakMB + 'MB';
		if (topBarFpsMemText.text != newText) topBarFpsMemText.text = newText;
	}

	/** 递归将游戏字体应用到菜单按钮/菜单项及其内部 label，确保中文正常显示 */
	function applyMenuFont(comp:Component, font:String)
	{
		if (comp is Button || comp is MenuItem || comp is Label)
		{
			comp.styleString = 'font-name: $font; font-size: 12px;';
		}
		for (child in comp.childComponents)
			applyMenuFont(child, font);
	}

	/** 返回菜单对应的顶部按钮（菜单与按钮按加入顺序一一对应） */
	function getMenuBarButton(menu:Menu):Button
	{
		var idx = haxeMenuBarMenus.indexOf(menu);
		if (idx < 0 || idx >= haxeMenuBarButtons.length) return null;
		return haxeMenuBarButtons[idx];
	}

	/** 高亮/恢复菜单对应按钮：打开菜单时浅蓝，关闭时恢复底色 */
	function setMenuButtonHighlight(menu:Menu, active:Bool)
	{
		var btn = getMenuBarButton(menu);
		if (btn == null) return;
		btn.backgroundColor = active
			? (haxeMenuStyleLight ? 0xFFB4CBE4 : 0xFF4A6A8A)
			: (haxeMenuStyleLight ? 0xFFF6F6F6 : 0xFF3D3F41);
	}

	/** 顶部菜单条按钮：注册鼠标悬停浅蓝高亮。styleString 无法携带 :hover 伪类，
		只能用 MOUSE_OVER/MOUSE_OUT 事件动态改背景色（主题的 hover 已被内联 background-color 覆盖） */
	function registerTopBarButtonHover(btn:Button)
	{
		if (btn == null) return;
		btn.registerEvent(MouseEvent.MOUSE_OVER, function(_)
		{
			btn.backgroundColor = (haxeMenuStyleLight ? 0xFFB4CBE4 : 0xFF4A6A8A);
		});
		btn.registerEvent(MouseEvent.MOUSE_OUT, function(_)
		{
			// 仅当该按钮对应的下拉菜单正处于打开状态时才保持高亮，否则恢复底色。
			// 用 haxeMenuOpenMenu 判断而非 selected：切换菜单时 MOUSE_OUT 会先于 MenuBar
			// 更新 selected 触发，若按 selected 判断会误留高亮，导致多个按钮同时变蓝。
			btn.backgroundColor = (haxeMenuOpenMenu != null && getMenuBarButton(haxeMenuOpenMenu) == btn)
				? (haxeMenuStyleLight ? 0xFFB4CBE4 : 0xFF4A6A8A)
				: (haxeMenuStyleLight ? 0xFFF6F6F6 : 0xFF3D3F41);
		});
	}

	/** 下拉菜单项：注册鼠标悬停浅蓝高亮（颜色同下拉选中色 selBg），悬停离开恢复底色 */
	function registerMenuItemHover(item:MenuItem)
	{
		if (item == null) return;
		item.registerEvent(MouseEvent.MOUSE_OVER, function(_)
		{
			item.backgroundColor = (haxeMenuStyleLight ? 0xFFB4CBE4 : 0xFF4A6A8A);
		});
		item.registerEvent(MouseEvent.MOUSE_OUT, function(_)
		{
			item.backgroundColor = (haxeMenuStyleLight ? 0xFFFFFFFF : 0xFF2D2F31);
		});
	}

	/** 同步 HaxeUI 菜单项文本与底层 PsychUIButton 的动态文本（如视图菜单前三项、便捷制谱器开关） */
	function syncHaxeMenuTexts()
	{
		if (haxeMenuItemMappings == null || haxeMenuItemMappings.length == 0) return;
		for (pair in haxeMenuItemMappings)
		{
			if (pair == null || pair.item == null || pair.btn == null || pair.btn.text == null) continue;
			var t:String = pair.btn.text.text;
			if (t != null && t != pair.item.text)
				pair.item.text = t;
		}
	}

	function addFileTab()
	{
		var tab = upperBox.getTab(Language.get("charting_file_text"));
		var tab_group = tab.menu;
		var btnX = tab.x - upperBox.x;
		var btnY = 1;
		var btnWid = 180; // 下拉选项条宽度，加宽以容纳较长文本单行显示

		#if !mobile
		var btn:PsychUIButton = new PsychUIButton(btnX, btnY, Language.get('charting_new_tab1'), function()
		{
			var func:Void->Void = function()
			{
				openNewChart();
				reloadNotesDropdowns();
				prepareReload();
			}

			if(!ignoreProgressCheckBox.checked) openSubState(new Prompt(Language.get('prompt_startover'), func));
			else func();
		}, btnWid);
		btn.text.alignment = LEFT;
		tab_group.add(btn);

		btnY++;
		btnY += 20;
		var btn:PsychUIButton = new PsychUIButton(btnX, btnY, Language.get('charting_opchart_tab1'), function()
		{
			if(!fileDialog.completed) return;
			upperBox.isMinimized = true;
			upperBox.bg.visible = false;

			fileDialog.open(function()
			{
				try
				{
					var filePath:String = fileDialog.path.replace('\\', '/');
					var loadedChart:SwagSong = Song.parseJSON(fileDialog.data, filePath.substr(filePath.lastIndexOf('/')));
					if(loadedChart == null || !Reflect.hasField(loadedChart, 'song')) //Check if chart is ACTUALLY a chart and valid
					{
						showOutput(Language.get('charting_msg_notchart'), true);
						return;
					}

					var func:Void->Void = function()
					{
						loadChart(loadedChart);
						Song.chartPath = fileDialog.path;
						reloadNotesDropdowns();
						prepareReload();
						showOutput(Language.get('charting_msg_chart_opened', [Song.chartPath]));
					}
					
					if(!ignoreProgressCheckBox.checked) openSubState(new Prompt(Language.get('prompt_unsaved'), func));
					else func();
				}
				catch(e:Exception)
				{
					showOutput(Language.get('charting_msg_genericerr', [e.message]), true);
					trace(e.stack);
				}
			});
		}, btnWid);
		btn.text.alignment = LEFT;
		tab_group.add(btn);

		btnY += 20;
		#end
		var btn:PsychUIButton = new PsychUIButton(btnX, btnY, Language.get('charting_opautosave_tab1'), function()
		{
			if(!fileDialog.completed) return;
			upperBox.isMinimized = true;
			upperBox.bg.visible = false;

			if(!FileSystem.exists('backups/'))
			{
				showOutput(Language.get('charting_msg_autosave_nobackup'), true);
				return;
			}
			
			var fileList:Array<String> = Paths.readDirectory('backups/').filter((file:String) -> file.endsWith('.$BACKUP_EXT'));
			if(fileList.length < 1)
			{
				showOutput(Language.get('charting_msg_autosave_none'), true);
				return;
			}

			fileList.sort((a:String, b:String) -> (a.toUpperCase() < b.toUpperCase()) ? 1 : -1); //Sort alphabetically descending
			var maxItems:Int = Std.int(Math.min(5, fileList.length));
			var radioGrp:PsychUIRadioGroup = new PsychUIRadioGroup(0, 0, fileList, 25, maxItems, false, 240);
			radioGrp.checked = 0;

			var hei:Float = radioGrp.height + 160;
			openSubState(new BasePrompt(420, hei, 'Choose an Autosave',
				function(state:BasePrompt) {
					upperBox.isMinimized = true;
					upperBox.bg.visible = false;

					var btn:PsychUIButton = new PsychUIButton(state.bg.x + state.bg.width - 40, state.bg.y, 'X', state.close, 40);
					btn.cameras = state.cameras;
					state.add(btn);

					radioGrp.screenCenter(X);
					radioGrp.y = state.bg.y + 80;
					radioGrp.cameras = state.cameras;
					state.add(radioGrp);

					var btn:PsychUIButton = new PsychUIButton(0, radioGrp.y + radioGrp.height + 20, 'Load', function()
					{
						var autosaveName:String = fileList[radioGrp.checked];
						var path:String = 'backups/$autosaveName';
						state.close();

						if(FileSystem.exists(path))
						{
							try
							{
								var loadedChart:SwagSong = Song.parseJSON(File.getContent(path), autosaveName, null);
								if(loadedChart == null || !Reflect.hasField(loadedChart, '__original_path'))
								{
									showOutput(Language.get('charting_msg_autosave_invalid'), true);
									return;
	
								}
	
								var originalPath:String = Reflect.field(loadedChart, '__original_path');
								Reflect.deleteField(loadedChart, '__original_path');
	
								var func:Void->Void = function()
								{
									Song.chartPath = FileSystem.exists(originalPath) ? originalPath : null;
									loadChart(loadedChart);
									reloadNotesDropdowns();
									prepareReload();
	
									showOutput(Language.get('charting_msg_autosave_opened', [autosaveName]));
								}
								
								if(!ignoreProgressCheckBox.checked) openSubState(new Prompt(Language.get('prompt_unsaved'), func));
								else func();
							}
							catch(e:Exception)
							{
								showOutput(Language.get('charting_msg_autosave_loaderr', [e.message]), true);
							}
						}
						else showOutput(Language.get('charting_msg_autosave_notfound'), true);
					});
					btn.cameras = state.cameras;
					btn.screenCenter(X);
					state.add(btn);
				}
			));
		}, btnWid);
		btn.text.alignment = LEFT;
		tab_group.add(btn);

		#if !mobile
		if(SHOW_EVENT_COLUMN)
		{
			btnY += 20;
			var btn:PsychUIButton = new PsychUIButton(btnX, btnY, Language.get('charting_opevent_tab1'), function()
			{
				if(!fileDialog.completed) return;
				upperBox.isMinimized = true;
				upperBox.bg.visible = false;
	
				fileDialog.open(function()
				{
					try
					{
						var filePath:String = fileDialog.path.replace('\\', '/');
						var eventsFile:SwagSong = Song.parseJSON(fileDialog.data, filePath.substr(filePath.lastIndexOf('/')));
						if(eventsFile == null || Reflect.hasField(eventsFile, 'scrollSpeed') || eventsFile.events == null)
						{
							showOutput(Language.get('charting_msg_noteventfile'), true);
							return;
						}
	
						var loadedEvents:Array<Dynamic> = eventsFile.events;
						if(loadedEvents.length < 1)
						{
							showOutput(Language.get('charting_msg_events_empty'), true);
							return;
						}
	
						openSubState(new BasePrompt('Events Found! Choose an action.',
							function(state:BasePrompt)
							{
								var btnY = 390;
								var btn:PsychUIButton = new PsychUIButton(0, btnY, 'Replace All', function()
								{
									for (event in events)
									{
										if(event != null)
										{
											event.destroy();
											selectedNotes.remove(event);
										}
									}
									undoActions = [];
									events = [];
	
									for (event in loadedEvents)
										events.push(createEvent(event));
	
									softReloadNotes();
									state.close();
									showOutput(Language.get('charting_msg_events_loaded'));
								});
								btn.normalStyle.bgColor = FlxColor.RED;
								btn.normalStyle.textColor = FlxColor.WHITE;
								btn.screenCenter(X);
								btn.x -= 125;
								btn.cameras = state.cameras;
								state.add(btn);
								
								var btn:PsychUIButton = new PsychUIButton(0, btnY, Language.get('charting_add_btn'), function()
								{
									for (event in loadedEvents)
										events.push(createEvent(event));
	
									softReloadNotes();
									state.close();
									showOutput(Language.get('charting_msg_events_added'));
								});
								btn.screenCenter(X);
								btn.cameras = state.cameras;
								state.add(btn);
						
								var btn:PsychUIButton = new PsychUIButton(0, btnY, Language.get('charting_cancel_btn'), state.close);
								btn.screenCenter(X);
								btn.x += 125;
								btn.cameras = state.cameras;
								state.add(btn);
							}
						));
					}
					catch(e:Exception)
					{
						showOutput(Language.get('charting_msg_genericerr', [e.message]), true);
						trace(e.stack);
					}
				});
			}, btnWid);
			btn.text.alignment = LEFT;
			tab_group.add(btn);
		}
		#end

		btnY++;
		btnY += 20;
		var btn:PsychUIButton = new PsychUIButton(btnX, btnY, Language.get('charting_save1_tab1'), function()
		{
			if(!fileDialog.completed) return;
			upperBox.isMinimized = true;
			upperBox.bg.visible = false;

			saveChart();
		}, btnWid);
		btn.text.alignment = LEFT;
		tab_group.add(btn);

		#if !mobile
		btnY += 20;
		var btn:PsychUIButton = new PsychUIButton(btnX, btnY, Language.get('charting_save2_tab1'), function()
		{
			if(!fileDialog.completed) return;
			upperBox.isMinimized = true;
			upperBox.bg.visible = false;

			saveChart(false);
		},btnWid);
		btn.text.alignment = LEFT;
		tab_group.add(btn);
		#end

		if(SHOW_EVENT_COLUMN)
		{
			btnY += 20;
			var btn:PsychUIButton = new PsychUIButton(btnX, btnY, Language.get('charting_save3_tab1'), function()
			{
				if(!fileDialog.completed) return;
				upperBox.isMinimized = true;
	
				updateChartData();
				
				// 保存 events 数据
				var eventsData:String = PsychJsonPrinter.print({events: PlayState.SONG.events, format: 'mr_psych_v1'}, ['events']);
				
				// 获取格式化后的曲名前缀
				var formattedSongName:String = Paths.formatToSongPath(PlayState.SONG.song);
				
				// 保存普通 events 文件（带曲名前缀）
				#if mobile
				var eventsFileName:String = formattedSongName + '-events.json';
				StorageUtil.saveContent(eventsFileName, eventsData);
				#else
				// 使用变量存储回调
				var hasSavedSpecialEvents:Bool = false;
				
				// 普通 events 文件名（带曲名前缀）
				var regularEventsFileName:String = formattedSongName + '-events.json';
				
				var saveEventsCallback:Void->Void = function()
				{
					// 如果设置了 specialEvents，并且还没有保存 special events 文件，尝试保存
					if(PlayState.SONG.specialEvents != null && PlayState.SONG.specialEvents.length > 0 && !hasSavedSpecialEvents)
					{
						hasSavedSpecialEvents = true;
						var specialEventsName:String = formattedSongName + '-events-' + PlayState.SONG.specialEvents + '.json';
						fileDialog.save(specialEventsName, eventsData,
							function() 
							{
								showOutput(Language.get('charting_msg_events_saved', [regularEventsFileName + ' and ' + specialEventsName]));
							}, 
							null,
							function() 
							{
								showOutput(Language.get('charting_msg_events_saved', [regularEventsFileName + ' (failed to save ' + specialEventsName + ')']));
							}
						);
					}
					else if(!hasSavedSpecialEvents)
					{
						showOutput(Language.get('charting_msg_events_saved', [regularEventsFileName]));
					}
				};
				
				var saveEventsErrorCallback:Void->Void = function()
				{
					showOutput(Language.get('charting_msg_events_saveerr'), true);
				};
				
				fileDialog.save(regularEventsFileName, eventsData, saveEventsCallback, null, saveEventsErrorCallback);
				#end
			}, btnWid);
			btn.text.alignment = LEFT;
			tab_group.add(btn);
		}

		#if !mobile
		btnY += 20;
		var btn:PsychUIButton = new PsychUIButton(btnX, btnY, Language.get('charting_savelegacy_tab1'), function()
		{
			if(!fileDialog.completed) return;
			upperBox.isMinimized = true;
			upperBox.bg.visible = false;

			saveChartLegacy();
		}, btnWid);
		btn.text.alignment = LEFT;
		tab_group.add(btn);
		#end

		btnY++;
		btnY += 20;
		var btn:PsychUIButton = new PsychUIButton(btnX, btnY, Language.get('charting_reloadchart_tab1'), function()
		{
			var func:Void->Void = function()
			{
				if(Song.chartPath == null)
				{
					showOutput(Language.get('charting_msg_reload_noneed'), true);
					return;
				}
	
				if(FileSystem.exists(Song.chartPath))
				{
					try
					{
						var reloadedChart:SwagSong = Song.parseJSON(File.getContent(Song.chartPath));
						loadChart(reloadedChart);
						reloadNotesDropdowns();
						prepareReload();
						showOutput(Language.get('charting_msg_reload_ok'));
					}
					catch(e:Exception)
					{
						showOutput(Language.get('charting_msg_genericerr', [e.message]), true);
						trace(e.stack);
					}
				}
				else showOutput(Language.get('charting_msg_reload_noneed'), true);
			}

			if(!ignoreProgressCheckBox.checked) openSubState(new Prompt(Language.get('prompt_unsaved'), func));
			else func();
		}, btnWid);
		btn.text.alignment = LEFT;
		tab_group.add(btn);
		#if !mobile
		btnY++;
		btnY += 20;
		var btn:PsychUIButton = new PsychUIButton(btnX, btnY, Language.get('charting_save4V_tab1'), function()
		{
			if(!fileDialog.completed) return;
			upperBox.isMinimized = true;
			upperBox.bg.visible = false;

			fileDialog.openDirectory('Save V-Slice Chart/Metadata JSONs', function()
			{
				try
				{
				var path:String = fileDialog.path.replace('\\', '/');

				// 在选中的保存路径下创建以歌曲名命名的子文件夹，避免文件直接散落在根目录
				var songFolder:String = Paths.formatToSongPath(PlayState.SONG.song);
				if (songFolder.length < 1) songFolder = 'song';
				path = '$path/$songFolder';
				if (!FileSystem.exists(path)) FileSystem.createDirectory(path);

				var chartName:String = songFolder;

				var chartFile:String = '$path/$chartName-chart.json';
				var metadataFile:String = '$path/$chartName-metadata.json';

					updateChartData();
					var pack:VSlicePackage = VSlice.export(PlayState.SONG);

					ClientPrefs.toggleVolumeKeys(false);
					openSubState(new BasePrompt('Metadata',
						function(state:BasePrompt)
						{
							var btnX = 640;
							var btnY = 400;
							var btn:PsychUIButton = new PsychUIButton(btnX, btnY, 'Save', function()
							{
								overwriteSavedSomething = false;
								overwriteCheck(chartFile, '$chartName-chart.json', PsychJsonPrinter.print(pack.chart, ['events', 'notes', 'scrollSpeed']), function()
								{
									overwriteCheck(metadataFile, '$chartName-metadata.json', PsychJsonPrinter.print(pack.metadata, ['characters', 'difficulties', 'timeChanges']), function()
									{
										if(overwriteSavedSomething)
											showOutput(Language.get('charting_msg_files_saved', [path]));
									});
								});
								state.close();
							});
							btn.normalStyle.bgColor = FlxColor.GREEN;
							btn.normalStyle.textColor = FlxColor.WHITE;
							btn.cameras = state.cameras;
							state.add(btn);
							
							var btn:PsychUIButton = new PsychUIButton(btnX + 100, btnY, Language.get('charting_cancel_btn'), state.close);
							btn.cameras = state.cameras;
							state.add(btn);
							
							var textX = FlxG.width/2 - 155;
							var textY = 360;
							var artistInput:PsychUIInputText = new PsychUIInputText(textX, textY, 120, pack.metadata.artist, 12);
							artistInput.cameras = state.cameras;
							artistInput.onChange = function(old:String, cur:String) pack.metadata.artist = cur;

							var charterInput:PsychUIInputText = new PsychUIInputText(textX + 190, textY, 120, pack.metadata.charter, 12);
							charterInput.cameras = state.cameras;
							charterInput.onChange = function(old:String, cur:String) pack.metadata.charter = cur;
							
							var artistTxt:FlxText = new FlxText(artistInput.x, artistInput.y - 15, 100, Language.get('charting_artist')).setFormat(Paths.font(Language.get('uitab_font')), 12);
							artistTxt.cameras = state.cameras;
							var charterTxt:FlxText = new FlxText(charterInput.x, charterInput.y - 15, 100, Language.get('charting_charter')).setFormat(Paths.font(Language.get('uitab_font')), 12);
							charterTxt.cameras = state.cameras;
							state.add(artistTxt);
							state.add(charterTxt);
							state.add(artistInput);
							state.add(charterInput);
						}
					));

					//trace(pack.chart);
					//trace(pack.metadata);
					//trace(chartName, chartFile, metadataFile);
				}
				catch(e:Exception)
				{
					showOutput(Language.get('charting_msg_genericerr', [e.message]), true);
					trace(e.stack);
				}
			});
		},btnWid);
		btn.text.alignment = LEFT;
		tab_group.add(btn);

		btnY += 20;
		var btn:PsychUIButton = new PsychUIButton(btnX, btnY, Language.get('charting_saveP2V_tab1'), function()
		{
			if(!fileDialog.completed) return;
			upperBox.isMinimized = true;
			upperBox.bg.visible = false;

			fileDialog.open('song.json', 'Open a Psych Engine Chart JSON', function()
			{
				var filePath:String = fileDialog.path.replace('\\', '/');
				var loadedChart:SwagSong = Song.parseJSON(fileDialog.data, filePath.substr(filePath.lastIndexOf('/')));
				if(loadedChart == null || !Reflect.hasField(loadedChart, 'song')) //Check if chart is ACTUALLY a chart and valid
				{
					showOutput(Language.get('charting_msg_notchart'), true);
					return;
				}

				var pack:VSlicePackage = VSlice.export(loadedChart);
				if(pack.chart == null || pack.metadata == null)
				{
					showOutput(Language.get('charting_msg_chart_invalid'), true);
					return;
				}

				ClientPrefs.toggleVolumeKeys(false);
				openSubState(new BasePrompt('Metadata',
					function(state:BasePrompt)
					{
						var songName:String = Paths.formatToSongPath(pack.metadata.songName);
						var parentFolder:String = filePath.substring(0, filePath.lastIndexOf('/')+1);
						var artistInput, charterInput, difficultiesInput:PsychUIInputText = null;

						var btnX = 640;
						var btnY = 400;
						var btn:PsychUIButton = new PsychUIButton(btnX, btnY, 'Save', function()
						{
							try
							{
								var diffs:Array<String> = pack.metadata.playData.difficulties;
								if(diffs != null && diffs.length > 0)
								{
									var diffsFound:Array<String> = [];
									var defaultDiff:String = Paths.formatToSongPath(Difficulty.getDefault());
									for (diff in diffs)
									{
										var diffPostfix:String = (diff != defaultDiff) ? '-$diff' : '';
										var chartToFind:String = parentFolder + songName + diffPostfix + '.json';
										if(FileSystem.exists(chartToFind))
										{
											var diffChart:SwagSong = Song.parseJSON(File.getContent(chartToFind), songName + diffPostfix);
											if(diffChart != null)
											{
												var subpack:VSlicePackage = VSlice.export(diffChart);
												var	diffSpeed:Null<Float> = subpack.chart.scrollSpeed.get(diff);
												var diffNotes:Array<VSliceNote> = subpack.chart.notes.get(diff);
												if(diffSpeed != null && diffNotes != null)
												{
													pack.chart.scrollSpeed.set(diff, diffSpeed);
													pack.chart.notes.set(diff, diffNotes);
												}
												//trace(diff, diffSpeed, diffNotes.length);
											}
										}
										else trace('File not found: $chartToFind');
									}
									
									var chartToFind:String = parentFolder + 'events.json';
									if(FileSystem.exists(chartToFind))
									{
										var eventsChart:SwagSong = Song.parseJSON(File.getContent(chartToFind), 'events');
										if(eventsChart != null)
										{
											var subpack:VSlicePackage = VSlice.export(eventsChart);
											if(subpack.chart.events != null && subpack.chart.events.length > 0)
											{
												for (event in subpack.chart.events)
												{
													if(event == null) continue;
													pack.chart.events.push(event);
												}
											}
										@:privateAccess pack.chart.events.sort(VSlice.sortByTime);
										}
									}

									fileDialog.openDirectory('Save V-Slice Chart/Metadata JSONs', function()
									{
									overwriteSavedSomething = false;
									var path:String = fileDialog.path.replace('\\', '/');
									if(path.endsWith('/')) path = path.substr(0, path.length-1);
									// 在选中的保存路径下创建以歌曲名命名的子文件夹
									var songFolder:String = songName;
									if (songFolder.length < 1) songFolder = 'song';
									path = '$path/$songFolder';
									if (!FileSystem.exists(path)) FileSystem.createDirectory(path);
										overwriteCheck('$path/$songName-chart.json', '$songName-chart.json', PsychJsonPrinter.print(pack.chart, ['events', 'notes', 'scrollSpeed']), function()
										{
											overwriteCheck('$path/$songName-metadata.json', '$songName-metadata.json', PsychJsonPrinter.print(pack.metadata, ['characters', 'difficulties', 'timeChanges']), function()
											{
												if(overwriteSavedSomething)
													showOutput(Language.get('charting_msg_files_saved', [path]));
											});
										});
									});
								}
								else showOutput(Language.get('charting_msg_vslice_nodiff'), true);
							}
							catch(e:Exception)
							{
								showOutput(Language.get('charting_msg_genericerr', [e.message]), true);
								trace(e.stack);
							}
							state.close();
						});
						btn.normalStyle.bgColor = FlxColor.GREEN;
						btn.normalStyle.textColor = FlxColor.WHITE;
						btn.cameras = state.cameras;
						state.add(btn);
						
						var btn:PsychUIButton = new PsychUIButton(btnX + 100, btnY, Language.get('charting_cancel_btn'), state.close);
						btn.cameras = state.cameras;
						state.add(btn);
						
						var textX = FlxG.width/2 - 180;
						var textY = 360;
						artistInput = new PsychUIInputText(textX, textY, 120, pack.metadata.artist, 12);
						artistInput.cameras = state.cameras;
						artistInput.onChange = function(old:String, cur:String) pack.metadata.artist = cur;
	
						charterInput = new PsychUIInputText(textX + 150, textY, 120, pack.metadata.charter, 12);
						charterInput.cameras = state.cameras;
						charterInput.onChange = function(old:String, cur:String) pack.metadata.charter = cur;

						var diffs:Array<String> = pack.metadata.playData.difficulties;
						if(diffs == null || diffs.length < 0) pack.metadata.playData.difficulties = diffs = ['easy', 'normal', 'hard'];
						difficultiesInput = new PsychUIInputText(textX, textY + 42, 160, diffs.join(', '), 12);
						difficultiesInput.cameras = state.cameras;
						difficultiesInput.forceCase = LOWER_CASE;
						difficultiesInput.onChange = function(old:String, cur:String)
						{
							pack.metadata.playData.difficulties = cur.split(',');

							var diffs:Array<String> = pack.metadata.playData.difficulties;
							for (num => diff in diffs)
								diffs[num] = Paths.formatToSongPath(diff);

							while(diffs.contains('')) //Clear invalids cuz people might be stupid
								diffs.remove('');
						}
						
						var artistTxt:FlxText = new FlxText(artistInput.x, artistInput.y - 15, 100, Language.get('charting_artist')).setFormat(Paths.font(Language.get('uitab_font')), 12);
						artistTxt.cameras = state.cameras;
						var charterTxt:FlxText = new FlxText(charterInput.x, charterInput.y - 15, 100, Language.get('charting_charter')).setFormat(Paths.font(Language.get('uitab_font')), 12);
						charterTxt.cameras = state.cameras;
						var difficultiesTxt:FlxText = new FlxText(difficultiesInput.x, difficultiesInput.y - 15, 100, Language.get('charting_difficulties')).setFormat(Paths.font(Language.get('uitab_font')), 12);
						difficultiesTxt.cameras = state.cameras;
						state.add(artistTxt);
						state.add(charterTxt);
						state.add(difficultiesTxt);
						state.add(artistInput);
						state.add(charterInput);
						state.add(difficultiesInput);
					}
				));
			});
		},btnWid);
		btn.text.alignment = LEFT;
		tab_group.add(btn);

		btnY += 20;
		var btn:PsychUIButton = new PsychUIButton(btnX, btnY, Language.get('charting_saveV2P_tab1'), function()
		{
			if(!fileDialog.completed) return;
			upperBox.isMinimized = true;
			upperBox.bg.visible = false;

			fileDialog.open('chart.json', 'Open a V-Slice Chart file', function()
			{
				var chart:VSliceChart = cast Json.parse(fileDialog.data);
				if(chart == null || chart.version == null || chart.notes == null || chart.scrollSpeed == null)
				{
					showOutput(Language.get('charting_msg_vslice_notchart'), true);
					return;
				}

				fileDialog.open('metadata.json', 'Open a V-Slice Metadata file', function()
				{
					var metadata:VSliceMetadata = cast Json.parse(fileDialog.data);
					if(metadata == null || metadata.version == null || metadata.playData == null || metadata.songName == null ||
						metadata.playData.difficulties == null || metadata.timeChanges == null || metadata.timeChanges.length < 1)
					{
						showOutput(Language.get('charting_msg_vslice_notmeta'), true);
						return;
					}

					try
					{
						var pack:PsychPackage = VSlice.convertToPsych(chart, metadata);
						if(pack.difficulties != null)
						{
							fileDialog.openDirectory('Save Converted Psych JSONs', function()
							{
								var path:String = fileDialog.path.replace('\\', '/');
								if(!path.endsWith('/')) path += '/';
								// 在选中的保存路径下创建以歌曲名命名的子文件夹
								var songFolder:String = Paths.formatToSongPath(metadata.songName);
								if (songFolder.length < 1) songFolder = 'song';
								path += '$songFolder/';
								if (!FileSystem.exists(path)) FileSystem.createDirectory(path);

								var diffs:Array<String> = metadata.playData.difficulties.copy();
								var defaultDiff:String = Paths.formatToSongPath(Difficulty.getDefault());
								function nextChart()
								{
									while(diffs.length > 0)
									{
										var diffName:String = diffs[0];
										diffs.remove(diffName);
										if(!pack.difficulties.exists(diffName)) continue;
		
										var diffPostfix:String = (diffName != defaultDiff) ? '-$diffName' : '';
										var chartData:SwagSong = pack.difficulties.get(diffName);
										var chartName:String = Paths.formatToSongPath(chartData.song) + diffPostfix + '.json';
										overwriteCheck(path + chartName, chartName, PsychJsonPrinter.print(chartData, ['sectionNotes', 'events']), nextChart, true);
										return;
									}
	
									if(pack.events != null)
									{
										overwriteCheck(path + 'events.json', 'events.json', PsychJsonPrinter.print(pack.events, ['events']), function()
										{
											if(overwriteSavedSomething)
												showOutput(Language.get('charting_msg_files_saved', [path]));
										}, true);
									}
									else if(overwriteSavedSomething)
										showOutput(Language.get('charting_msg_files_saved', [path]));
								}
								
								overwriteSavedSomething = false;
								nextChart();
							});
						}
						else showOutput(Language.get('charting_msg_vslice_nodiff2'));
					}
					catch(e:Exception)
					{
						showOutput(Language.get('charting_msg_genericerr', [e.message]), true);
						trace(e.stack);
					}
				});
			});
		},btnWid);
		btn.text.alignment = LEFT;
		tab_group.add(btn);
		
		btnY += 20;
		var btn:PsychUIButton = new PsychUIButton(btnX, btnY, Language.get('charting_conv2legacy_tab1'), function()
		{
			if(!fileDialog.completed) return;
			upperBox.isMinimized = true;
			upperBox.bg.visible = false;

			// 选源文件（新版 Psych 谱面），转成 0.6.x 后另存到用户指定位置
			fileDialog.open('song.json', 'Open a Psych Engine Chart JSON', function()
			{
				try
				{
					var filePath:String = fileDialog.path.replace('\\', '/');
					var loadedChart:SwagSong = Song.parseJSON(fileDialog.data, filePath.substr(filePath.lastIndexOf('/')));
					if(loadedChart == null || !Reflect.hasField(loadedChart, 'song'))
					{
						showOutput(Language.get('charting_legacy_notchart'), true);
						return;
					}

					var chartData:String = convertSongToLegacy(loadedChart);
					if(chartData == null) return; // 错误信息已在转换函数内提示

					var chartName:String = Paths.formatToSongPath(loadedChart.song) + '.json';
					#if mobile
					StorageUtil.saveContent(chartName, chartData);
					showOutput(Language.get('charting_legacy_saved_mobile', [chartName]));
					#else
					fileDialog.save(chartName, chartData,
						function()
						{
							showOutput(Language.get('charting_legacy_saved', [fileDialog.path]));
						}, null, function() showOutput(Language.get('charting_legacy_savefail'), true));
					#end
				}
				catch(e:Dynamic)
				{
					showOutput(Language.get('charting_legacy_convertfail', [Std.string(e)]), true);
				}
			});
		},btnWid);
		btn.text.alignment = LEFT;
		tab_group.add(btn);

		btnY += 20;
		var btn:PsychUIButton = new PsychUIButton(btnX, btnY, Language.get('charting_upPold_tab1'), function()
		{
			if(!fileDialog.completed) return;
			upperBox.isMinimized = true;
			upperBox.bg.visible = false;

			fileDialog.open(function()
			{
				var oldSong = PlayState.SONG;
				try
				{
					var filePath:String = fileDialog.path.replace('\\', '/');
					filePath = filePath.substring(filePath.lastIndexOf('/')+1, filePath.lastIndexOf('.'));

					var loadedChart:SwagSong = Song.parseJSON(fileDialog.data, filePath, '');
					if(loadedChart == null || !Reflect.hasField(loadedChart, 'song')) //Check if chart is ACTUALLY a chart and valid
					{
						showOutput(Language.get('charting_msg_notchart'), true);
						return;
					}

					var fmt:String = loadedChart.format;
					if(fmt == null || fmt.length < 1)
						fmt = loadedChart.format = 'unknown';

					if(!fmt.startsWith('psych_v1'))
					{
						loadedChart.format = 'psych_v1_convert';
						Song.convert(loadedChart);
						File.saveContent(fileDialog.path, PsychJsonPrinter.print(loadedChart, ['sectionNotes', 'events']));
						showOutput(Language.get('charting_msg_updated', [filePath, fmt]));
					}
					else showOutput(Language.get('charting_msg_uptodate', [fmt]), true);
				}
				catch(e:Exception)
				{
					showOutput(Language.get('charting_msg_genericerr', [e.message]), true);
					trace(e.stack);
				}
			});
		}, btnWid);
		btn.text.alignment = LEFT;
		tab_group.add(btn);
		#end

		btnY++;
		btnY += 20;
		var btn:PsychUIButton = new PsychUIButton(btnX, btnY, '${Language.get('charting_preview_tab1')} (${(controls.mobileC) ? 'C' : 'F12'})', openEditorPlayState, btnWid);
		btn.text.alignment = LEFT;
		tab_group.add(btn);
		
		btnY += 20;
		var btn:PsychUIButton = new PsychUIButton(btnX, btnY, '${Language.get('charting_playtest_tab1')} (${(controls.mobileC) ? 'A' : 'ENTER'})', goToPlayState, btnWid);
		btn.text.alignment = LEFT;
		tab_group.add(btn);

		btnY++;
		btnY += 20;
		var btn:PsychUIButton = new PsychUIButton(btnX, btnY, Language.get('charting_exit_tab1'), function()
		{
			PlayState.chartingMode = false;
			MusicBeatState.switchState(new states.editors.MasterEditorMenu());
			FlxG.sound.playMusic(Paths.menuMusicAudio());
			FlxG.mouse.visible = false;
		}, btnWid);
		btn.text.alignment = LEFT;
		tab_group.add(btn);
	}

	var lockedEvents:Bool = false;
	function addEditTab()
	{
		var tab = upperBox.getTab(Language.get("charting_edit_text"));
		var tab_group = tab.menu;
		var btnX = tab.x - upperBox.x;
		var btnY = 1;
		var btnWid = 180; // 下拉选项条宽度，加宽以容纳较长文本单行显示

		var btn:PsychUIButton = new PsychUIButton(btnX, btnY, Language.get('charting_undo_tab2'), undo, btnWid);
		btn.text.alignment = LEFT;
		tab_group.add(btn);

		btnY += 20;
		var btn:PsychUIButton = new PsychUIButton(btnX, btnY, Language.get('charting_redo_tab2'), redo, btnWid);
		btn.text.alignment = LEFT;
		tab_group.add(btn);

		btnY++;
		btnY += 20;
		var btn:PsychUIButton = new PsychUIButton(btnX, btnY, Language.get('charting_selectall_tab2'), function()
		{
			var sel = selectedNotes;
			selectedNotes = curRenderedNotes.members.copy();
			addUndoAction(SELECT_NOTE, {old: sel, current: selectedNotes.copy()});
			onSelectNote();
			trace('Notes selected: ' + selectedNotes.length);
		}, btnWid);
		btn.text.alignment = LEFT;
		tab_group.add(btn);

		btnY++;
		btnY += 20;
		var btn:PsychUIButton = new PsychUIButton(btnX, btnY, Language.get('charting_find_event_tab2'), function()
		{
			searchBox.visible = !searchBox.visible;
		}, btnWid);
		btn.text.alignment = LEFT;
		tab_group.add(btn);

		if(SHOW_EVENT_COLUMN)
		{
			btnY++;
			btnY += 20;
			var btn:PsychUIButton = new PsychUIButton(btnX, btnY, Language.get('charting_lockeve_tab2'), btnWid);
			btn.onClick = function()
			{
				lockedEvents = !lockedEvents;
				if(lockedEvents) btn.text.text = Language.get('charting_unlockeve_tab2');
				else btn.text.text = Language.get('charting_lockeve_tab2');
				eventLockOverlay.visible = lockedEvents;
	
				if(selectedNotes.length >= 1)
				{
					var sel = selectedNotes;
					var onlyNotes = selectedNotes.filter((note:MetaNote) -> !note.isEvent);
					resetSelectedNotes();
					selectedNotes = onlyNotes;
					addUndoAction(SELECT_NOTE, {old: sel, current: selectedNotes.copy()});
					if(selectedNotes.length == 1) onSelectNote();
				}
				softReloadNotes();
			};
			btn.text.alignment = LEFT;
			tab_group.add(btn);
		}
		
		btnY++;
		btnY += 20;
		var btn:PsychUIButton = new PsychUIButton(btnX, btnY, Language.get('charting_autosaveopt_tab2'), btnWid);
		btn.onClick = function()
		{
			upperBox.isMinimized = true;
			upperBox.bg.visible = false;
			openSubState(new BasePrompt(400, 160, Language.get('prompt_autosave_tab'),
				function(state:BasePrompt)
				{
					var btn:PsychUIButton = new PsychUIButton(state.bg.x + state.bg.width - 40, state.bg.y, 'X', state.close, 40);
					btn.cameras = state.cameras;
					state.add(btn);

					var checkbox:PsychUICheckBox = null;
					var timeStepper:PsychUINumericStepper = null;

					timeStepper = new PsychUINumericStepper(state.bg.x + 50, state.bg.y + 90, 1, autoSaveCap, 1, 30, 0);
					timeStepper.onValueChange = function() {
						autoSaveTime = 0;
						checkbox.checked = true;
						autoSaveCap = chartEditorSave.data.autoSave = Std.int(timeStepper.value);
					};
					timeStepper.cameras = state.cameras;

					checkbox = new PsychUICheckBox(timeStepper.x + 80, timeStepper.y, Language.get('enabled_text'), 60, function() {
						autoSaveTime = 0;
						autoSaveCap = chartEditorSave.data.autoSave = checkbox.checked ? Std.int(timeStepper.value) : 0;
					});
					checkbox.checked = (autoSaveCap > 0);
					checkbox.cameras = state.cameras;
					
					var maxFileStepper:PsychUINumericStepper = new PsychUINumericStepper(checkbox.x + 140, checkbox.y, 1, backupLimit, 0, 50, 0);
					maxFileStepper.onValueChange = function() {
						autoSaveTime = 0;
						checkbox.checked = true;
						chartEditorSave.data.backupLimit = backupLimit = Std.int(maxFileStepper.value);
					};
					maxFileStepper.cameras = state.cameras;

					var txt1:FlxText = new FlxText(timeStepper.x, timeStepper.y - 15, 200, Language.get('autosave_time'));
					txt1.font = Paths.font(Language.get('uitab_font'));
					txt1.size = 12;
					txt1.cameras = state.cameras;
					var txt2:FlxText = new FlxText(maxFileStepper.x, maxFileStepper.y - 15, 160, Language.get('autosave_filelimit'));
					txt2.font = Paths.font(Language.get('uitab_font'));
					txt2.size = 12;
					txt2.cameras = state.cameras;

					state.add(txt1);
					state.add(txt2);
					state.add(checkbox);
					state.add(timeStepper);
					state.add(maxFileStepper);
				}
			));

		};
		btn.text.alignment = LEFT;
		tab_group.add(btn);

		btnY++;
		btnY += 20;
		var btn:PsychUIButton = new PsychUIButton(btnX, btnY, Language.get('charting_clearalln_tab2'), function()
		{
			var func:Void->Void = function()
			{
				resetSelectedNotes();
				addUndoAction(DELETE_NOTE, {notes: notes.copy()});
				notes = [];
				loadSection();
			}

			if(!ignoreProgressCheckBox.checked) openSubState(new Prompt(Language.get('prompt_deleteallnote'), func));
			else func();
		}, btnWid);
		btn.normalStyle.bgColor = FlxColor.RED;
		btn.normalStyle.textColor = FlxColor.WHITE;
		btn.text.alignment = LEFT;
		tab_group.add(btn);

		if(SHOW_EVENT_COLUMN)
		{
			btnY += 20;
			var btn:PsychUIButton = new PsychUIButton(btnX, btnY, Language.get('charting_clearalle_tab2'), function()
			{
				var func:Void->Void = function()
				{
					resetSelectedNotes();
					addUndoAction(DELETE_NOTE, {events: events.copy()});
					events = [];
					loadSection();
				}
	
				if(!ignoreProgressCheckBox.checked) openSubState(new Prompt(Language.get('prompt_deleteallevent'), func));
				else func();
			}, btnWid);
			btn.normalStyle.bgColor = FlxColor.RED;
			btn.normalStyle.textColor = FlxColor.WHITE;
			btn.text.alignment = LEFT;
			tab_group.add(btn);
		}
	}

	var showLastGridButton:PsychUIButton;
	var showNextGridButton:PsychUIButton;
	var noteTypeLabelsButton:PsychUIButton;
	var vortexEditorButton:PsychUIButton;
	function addViewTab()
	{
		var tab = upperBox.getTab(Language.get("charting_view_text"));
		var tab_group = tab.menu;
		var btnX = tab.x - upperBox.x;
		var btnY = 1;
		var btnWid = 180; // 下拉选项条宽度，加宽以容纳较长文本单行显示

		if(chartEditorSave.data.waveformEnabled != null)
			waveformEnabled = chartEditorSave.data.waveformEnabled;
		if(chartEditorSave.data.waveformTargets != null)
		{
			waveformTargets = [];
			var savedTargets:Array<String> = cast chartEditorSave.data.waveformTargets;
			for (s in savedTargets)
				waveformTargets.push(cast s);
			if(waveformTargets.length == 0) waveformTargets = [INST];
		}
		if(chartEditorSave.data.waveformTargetLegacy != null)
			waveformTargetLegacy = cast chartEditorSave.data.waveformTargetLegacy;
		if(chartEditorSave.data.waveformColor != null)
			for (ws in waveformSprites)
				ws.color = CoolUtil.colorFromString(chartEditorSave.data.waveformColor);
		if(chartEditorSave.data.waveformStyle != null)
			waveformStyle = chartEditorSave.data.waveformStyle;
		if(chartEditorSave.data.waveformLibColor != null)
			waveformLibColor = chartEditorSave.data.waveformLibColor;
		if(chartEditorSave.data.waveformLibDrawMode != null)
			waveformLibDrawMode = chartEditorSave.data.waveformLibDrawMode;
		if(chartEditorSave.data.waveformLibRMS != null)
			waveformLibRMS = chartEditorSave.data.waveformLibRMS;
		if(chartEditorSave.data.waveformLibRMSColor != null)
			waveformLibRMSColor = chartEditorSave.data.waveformLibRMSColor;
		if(chartEditorSave.data.waveformLibBaseline != null)
			waveformLibBaseline = chartEditorSave.data.waveformLibBaseline;
		if(chartEditorSave.data.waveformLibBarSize != null)
			waveformLibBarSize = chartEditorSave.data.waveformLibBarSize;
		if(chartEditorSave.data.waveformLibBarPadding != null)
			waveformLibBarPadding = chartEditorSave.data.waveformLibBarPadding;
		if(chartEditorSave.data.waveformLibGain != null)
			waveformLibGain = chartEditorSave.data.waveformLibGain;

		showLastGridButton = new PsychUIButton(btnX, btnY, '', function()
		{
			showPreviousSection = !showPreviousSection;
			updateGridVisibility();
		}, btnWid);
		showLastGridButton.text.alignment = LEFT;
		tab_group.add(showLastGridButton);

		btnY += 20;
		showNextGridButton = new PsychUIButton(btnX, btnY, '', function()
		{
			showNextSection = !showNextSection;
			updateGridVisibility();
		}, btnWid);
		showNextGridButton.text.alignment = LEFT;
		tab_group.add(showNextGridButton);

		btnY++;
		btnY += 20;
		noteTypeLabelsButton = new PsychUIButton(btnX, btnY, '', function()
		{
			showNoteTypeLabels = !showNoteTypeLabels;
			updateGridVisibility();
		}, btnWid);
		noteTypeLabelsButton.text.alignment = LEFT;
		tab_group.add(noteTypeLabelsButton);

		btnY++;
		btnY += 20;
		vortexEditorButton = new PsychUIButton(btnX, btnY, vortexEnabled ? Language.get('charting_vortexeditoron_tab3') : Language.get('charting_vortexeditoroff_tab3'), function()
		{
			vortexEnabled = !vortexEnabled;
			chartEditorSave.data.vortex = vortexEnabled;
			vortexIndicator.visible = strumLineNotes.visible = strumLineNotes.active = vortexEnabled;
			vortexEditorButton.text.text = vortexEnabled ? Language.get('charting_vortexeditoron_tab3') : Language.get('charting_vortexeditoroff_tab3');

			for (note in strumLineNotes)
			{
				note.playAnim('static');
				note.resetAnim = 0;
			}
			opponentGridBg.vortexLineEnabled = playerGridBg.vortexLineEnabled = vortexEnabled;
			prevOpponentGridBg.vortexLineEnabled = prevPlayerGridBg.vortexLineEnabled = vortexEnabled;
			nextOpponentGridBg.vortexLineEnabled = nextPlayerGridBg.vortexLineEnabled = vortexEnabled;
			if(SHOW_EVENT_COLUMN)
			{
				eventGridBg.vortexLineEnabled = vortexEnabled;
				prevEventGridBg.vortexLineEnabled = vortexEnabled;
				nextEventGridBg.vortexLineEnabled = vortexEnabled;
			}
		}, btnWid);
		vortexEditorButton.text.alignment = LEFT;
		tab_group.add(vortexEditorButton);

		btnY++;

		btnY += 20;
		var btn:PsychUIButton = new PsychUIButton(btnX, btnY, Language.get('charting_waveform_tab3'), function()
		{
			ClientPrefs.toggleVolumeKeys(false);
			openSubState(new BasePrompt(620, 560, Language.get('prompt_waveform_tab'),
				function(state:BasePrompt) {
					upperBox.isMinimized = true;
					upperBox.bg.visible = false;

					var btn:PsychUIButton = new PsychUIButton(state.bg.x + state.bg.width - 40, state.bg.y, 'X', state.close, 40);
					btn.cameras = state.cameras;
					state.add(btn);

					// ===== 通用：启用 / 目标 / 渲染样式 =====
					var check:PsychUICheckBox = new PsychUICheckBox(state.bg.x + 40, state.bg.y + 70, Language.get('enabled_text'), 60);
					check.onClick = function()
					{
						chartEditorSave.data.waveformEnabled = waveformEnabled = check.checked;
						updateWaveform();
					};
					check.cameras = state.cameras;
					check.checked = waveformEnabled;
					state.add(check);

					var targetOptions:Array<WaveformTarget> = [INST, PLAYER, OPPONENT];
					var targetLabels:Array<String> = [Language.get('waveform_inst'), Language.get('waveform_mainvoice'), Language.get('waveform_dadvoice')];
					var targetCheckX = check.x + 250;
					var libraryTargetChecks:Array<PsychUICheckBox> = []; // 库版：复选（可多选）
					var legacyTargetChecks:Array<PsychUICheckBox> = [];   // 旧版：单选（互斥）
					for (i in 0...targetOptions.length)
					{
						var opt:WaveformTarget = targetOptions[i];

						// 库版：复选，可多选
						var tc:PsychUICheckBox = new PsychUICheckBox(targetCheckX, check.y + i * 20, targetLabels[i], 130);
						tc.checked = waveformTargets.indexOf(opt) != -1;
						tc.onClick = function()
						{
							if(tc.checked)
							{
								if(waveformTargets.indexOf(opt) == -1)
									waveformTargets.push(opt);
							}
							else
							{
								waveformTargets = waveformTargets.filter(function(x) return x != opt);
							}
							if(waveformTargets.length == 0) waveformTargets.push(opt);
							var savedTargets:Array<String> = [];
							for (w in waveformTargets) savedTargets.push(cast w);
							chartEditorSave.data.waveformTargets = savedTargets;
							updateWaveform();
						};
						tc.cameras = state.cameras;
						state.add(tc);
						libraryTargetChecks.push(tc);

						// 旧版：单选（互斥），勾选时取消勾选其余
						var leg:PsychUICheckBox = new PsychUICheckBox(targetCheckX, check.y + i * 20, targetLabels[i], 130);
						leg.checked = (waveformTargetLegacy == opt);
						leg.onClick = function()
						{
							if(leg.checked)
							{
								waveformTargetLegacy = opt;
								for (j in 0...legacyTargetChecks.length)
									legacyTargetChecks[j].checked = (targetOptions[j] == opt);
								chartEditorSave.data.waveformTargetLegacy = cast opt;
								updateWaveform();
							}
							else
								leg.checked = true; // 单选不允许全部取消，点击已选中的项视为保持选中
						};
						leg.cameras = state.cameras;
						state.add(leg);
						legacyTargetChecks.push(leg);
					}
					function refreshTargetControls()
					{
						for (c in libraryTargetChecks) c.visible = (waveformStyle == LIBRARY);
						for (c in legacyTargetChecks) c.visible = (waveformStyle == LEGACY);
					}
					refreshTargetControls();

					// 渲染样式切换（旧版逐字节 / flixel-waveform 库版）
					var styleOptions:Array<WaveformStyle> = [LEGACY, LIBRARY];
					var styleLabels:Array<String> = [Language.get('waveform_style_legacy') + Language.get('deprecated_suffix'), Language.get('waveform_style_library')];
					var styleDrop:PsychUIDropDownMenu = new PsychUIDropDownMenu(check.x, check.y + 50, styleLabels, function(id:Int, val:String)
					{
						waveformStyle = chartEditorSave.data.waveformStyle = styleOptions[id];
						refreshTargetControls();
						updateWaveform();
					}, 240);
					styleDrop.selectedLabel = styleLabels[styleOptions.indexOf(waveformStyle)];
					styleDrop.cameras = state.cameras;
					state.add(styleDrop);

					var txtStyle:FlxText = new FlxText(styleDrop.x, styleDrop.y - 15, 240, Language.get('waveform_style'));
					txtStyle.font = Paths.font(Language.get('uitab_font'));
					txtStyle.size = 12;
					txtStyle.cameras = state.cameras;
					state.add(txtStyle);

					// ===== 旧版样式：独立颜色 =====
					var txtLeg:FlxText = new FlxText(check.x, styleDrop.y + 48, 300, Language.get('waveform_style_legacy'));
					txtLeg.font = Paths.font(Language.get('uitab_font'));
					txtLeg.size = 12;
					txtLeg.cameras = state.cameras;
					state.add(txtLeg);

					var waveformC:String = '0000FF';
					if(chartEditorSave.data.waveformColor != null)
						waveformC = chartEditorSave.data.waveformColor;

					var legColorInput:PsychUIInputText = new PsychUIInputText(check.x, txtLeg.y + 25, 60, waveformC, 10);
					legColorInput.onChange = function(old:String, cur:String)
					{
						chartEditorSave.data.waveformColor = cur;
						for (ws in waveformSprites)
							ws.color = CoolUtil.colorFromString(cur);
					}
					legColorInput.maxLength = 6;
					legColorInput.filterMode = ONLY_HEXADECIMAL;
					legColorInput.cameras = state.cameras;
					legColorInput.forceCase = UPPER_CASE;
					var txtLegColor:FlxText = new FlxText(legColorInput.x, legColorInput.y - 15, 140, Language.get('waveform_color'));
					txtLegColor.font = Paths.font(Language.get('uitab_font'));
					txtLegColor.size = 12;
					txtLegColor.cameras = state.cameras;
					state.add(txtLegColor);
					state.add(legColorInput);

					// ===== 库版样式：独立参数 =====
					var colAX:Float = check.x;
					var colBX:Float = check.x + 240;
					var secY:Float = txtLeg.y + 60;
					var rowY:Float = secY + 25;

					var txtLib:FlxText = new FlxText(check.x, secY, 300, Language.get('waveform_style_library'));
					txtLib.font = Paths.font(Language.get('uitab_font'));
					txtLib.size = 12;
					txtLib.cameras = state.cameras;
					state.add(txtLib);

					// 行1：颜色（方向固定为竖向 VERTICAL，随制谱器网格方向）
					var libColorInput:PsychUIInputText = new PsychUIInputText(colAX, rowY, 60, waveformLibColor, 10);
					libColorInput.onChange = function(old:String, cur:String)
					{
						waveformLibColor = chartEditorSave.data.waveformLibColor = cur;
						updateWaveform();
					}
					libColorInput.maxLength = 6;
					libColorInput.filterMode = ONLY_HEXADECIMAL;
					libColorInput.cameras = state.cameras;
					libColorInput.forceCase = UPPER_CASE;
					var txtLibColor:FlxText = new FlxText(libColorInput.x, libColorInput.y - 15, 140, Language.get('waveform_lib_color'));
					txtLibColor.font = Paths.font(Language.get('uitab_font'));
					txtLibColor.size = 12;
					txtLibColor.cameras = state.cameras;
					state.add(txtLibColor);
					state.add(libColorInput);

					// 行2：绘制模式 | 基线
					rowY += 50;
					var drawOptions:Array<String> = ['COMBINED', 'SPLIT_CHANNELS'];
					var drawLabels:Array<String> = [Language.get('waveform_drawmode_combined'), Language.get('waveform_drawmode_split')];
					var drawDrop:PsychUIDropDownMenu = new PsychUIDropDownMenu(colAX, rowY, drawLabels, function(id:Int, val:String)
					{
						waveformLibDrawMode = chartEditorSave.data.waveformLibDrawMode = drawOptions[id];
						updateWaveform();
					}, 180);
					drawDrop.selectedLabel = drawLabels[drawOptions.indexOf(waveformLibDrawMode)];
					drawDrop.cameras = state.cameras;
					state.add(drawDrop);
					var txtDraw:FlxText = new FlxText(drawDrop.x, drawDrop.y - 15, 200, Language.get('waveform_drawmode'));
					txtDraw.font = Paths.font(Language.get('uitab_font'));
					txtDraw.size = 12;
					txtDraw.cameras = state.cameras;
					state.add(txtDraw);

					var baseCheck:PsychUICheckBox = new PsychUICheckBox(colBX, rowY, Language.get('waveform_baseline'), 140);
					baseCheck.checked = waveformLibBaseline;
					baseCheck.onClick = function()
					{
						waveformLibBaseline = chartEditorSave.data.waveformLibBaseline = baseCheck.checked;
						updateWaveform();
					};
					baseCheck.cameras = state.cameras;
					state.add(baseCheck);

					// 行3：响度(RMS) | 响度颜色
					rowY += 50;
					var rmsCheck:PsychUICheckBox = new PsychUICheckBox(colAX, rowY, Language.get('waveform_rms'), 150);
					rmsCheck.checked = waveformLibRMS;
					rmsCheck.onClick = function()
					{
						waveformLibRMS = chartEditorSave.data.waveformLibRMS = rmsCheck.checked;
						updateWaveform();
					};
					rmsCheck.cameras = state.cameras;
					state.add(rmsCheck);

					var rmsColorInput:PsychUIInputText = new PsychUIInputText(colBX, rowY, 60, waveformLibRMSColor, 10);
					rmsColorInput.onChange = function(old:String, cur:String)
					{
						waveformLibRMSColor = chartEditorSave.data.waveformLibRMSColor = cur;
						updateWaveform();
					}
					rmsColorInput.maxLength = 6;
					rmsColorInput.filterMode = ONLY_HEXADECIMAL;
					rmsColorInput.cameras = state.cameras;
					rmsColorInput.forceCase = UPPER_CASE;
					var txtRmsColor:FlxText = new FlxText(rmsColorInput.x, rmsColorInput.y - 15, 140, Language.get('waveform_rms_color'));
					txtRmsColor.font = Paths.font(Language.get('uitab_font'));
					txtRmsColor.size = 12;
					txtRmsColor.cameras = state.cameras;
					state.add(txtRmsColor);
					state.add(rmsColorInput);

					// 行4：柱宽 | 柱间距
					rowY += 50;
					var sizeInput:PsychUIInputText = new PsychUIInputText(colAX, rowY, 60, Std.string(waveformLibBarSize), 10);
					sizeInput.onChange = function(old:String, cur:String)
					{
						var parsedSize:Null<Int> = Std.parseInt(cur);
						var v:Int = (parsedSize == null || parsedSize < 1) ? 1 : parsedSize;
						waveformLibBarSize = chartEditorSave.data.waveformLibBarSize = v;
						updateWaveform();
					}
					sizeInput.maxLength = 3;
					sizeInput.filterMode = ONLY_NUMERIC;
					sizeInput.cameras = state.cameras;
					var txtSize:FlxText = new FlxText(sizeInput.x, sizeInput.y - 15, 140, Language.get('waveform_barsize'));
					txtSize.font = Paths.font(Language.get('uitab_font'));
					txtSize.size = 12;
					txtSize.cameras = state.cameras;
					state.add(txtSize);
					state.add(sizeInput);

					var padInput:PsychUIInputText = new PsychUIInputText(colBX, rowY, 60, Std.string(waveformLibBarPadding), 10);
					padInput.onChange = function(old:String, cur:String)
					{
						var parsedPad:Null<Int> = Std.parseInt(cur);
						var v:Int = (parsedPad == null || parsedPad < 0) ? 0 : parsedPad;
						waveformLibBarPadding = chartEditorSave.data.waveformLibBarPadding = v;
						updateWaveform();
					}
					padInput.maxLength = 3;
					padInput.filterMode = ONLY_NUMERIC;
					padInput.cameras = state.cameras;
					var txtPad:FlxText = new FlxText(padInput.x, padInput.y - 15, 140, Language.get('waveform_barpadding'));
					txtPad.font = Paths.font(Language.get('uitab_font'));
					txtPad.size = 12;
					txtPad.cameras = state.cameras;
					state.add(txtPad);
					state.add(padInput);

					// 行5：增益
					rowY += 50;
					var gainInput:PsychUIInputText = new PsychUIInputText(colAX, rowY, 60, Std.string(waveformLibGain), 10);
					gainInput.onChange = function(old:String, cur:String)
					{
						var v:Float = Std.parseFloat(cur);
						if(Math.isNaN(v) || v < 0) v = 1;
						waveformLibGain = chartEditorSave.data.waveformLibGain = v;
						updateWaveform();
					}
					gainInput.cameras = state.cameras;
					var txtGain:FlxText = new FlxText(gainInput.x, gainInput.y - 15, 140, Language.get('waveform_gain'));
					txtGain.font = Paths.font(Language.get('uitab_font'));
					txtGain.size = 12;
					txtGain.cameras = state.cameras;
					state.add(txtGain);
					state.add(gainInput);
				}
			));
		}, btnWid);
		btn.text.alignment = LEFT;
		tab_group.add(btn);

		btnY += 20;
		var btn:PsychUIButton = new PsychUIButton(btnX, btnY, Language.get('charting_go2time_tab3'), function()
		{
			upperBox.isMinimized = true;
			upperBox.bg.visible = false;
			openSubState(new BasePrompt(420, 200, Language.get('prompt_go2time_tab'),
				function(state:BasePrompt)
				{
					var curTime:Float = Conductor.songPosition;
					var currentSec:Int = curSec;

					var timeStepper:PsychUINumericStepper = new PsychUINumericStepper(state.bg.x + 100, state.bg.y + 90, 1, Math.floor(curTime)/1000, 0, FlxG.sound.music.length/1000 - 0.01, 2, 80);
					timeStepper.cameras = state.cameras;
					var sectionStepper:PsychUINumericStepper = new PsychUINumericStepper(timeStepper.x + 160, timeStepper.y, 1, currentSec, 0, PlayState.SONG.notes.length - 1, 0);
					sectionStepper.cameras = state.cameras;

					var txt1:FlxText = new FlxText(timeStepper.x, timeStepper.y - 15, 160, Language.get('go2time_time'));
					txt1.font = Paths.font(Language.get('uitab_font'));
					txt1.size = 12;
					var txt2:FlxText = new FlxText(sectionStepper.x, sectionStepper.y - 15, 100, Language.get('go2time_section'));
					txt2.font = Paths.font(Language.get('uitab_font'));
					txt2.size = 12;
					txt1.cameras = state.cameras;
					txt2.cameras = state.cameras;
					state.add(txt1);
					state.add(txt2);
					state.add(timeStepper);
					state.add(sectionStepper);

					var timeTxt:FlxText = new FlxText(15, state.bg.y + state.bg.height - 75, 230, '', 16);
					timeTxt.alignment = CENTER;
					timeTxt.screenCenter(X);
					timeTxt.cameras = state.cameras;
					state.add(timeTxt);
					function updateTime()
					{
						var tm:String = FlxStringUtil.formatTime(curTime / 1000, true);
						var ln:String = FlxStringUtil.formatTime(FlxG.sound.music.length / 1000, true);
						timeTxt.text = '$tm / $ln';
					}
					updateTime();

					timeStepper.onValueChange = function()
					{
						curTime = timeStepper.value * 1000;
						for (i => time in cachedSectionTimes)
						{
							if(time <= curTime)
								currentSec = i;
							else break;
						}
						updateTime();
					};
					sectionStepper.onValueChange = function()
					{
						currentSec = Std.int(sectionStepper.value);
						curTime = cachedSectionTimes[currentSec] + 0.000001;
						updateTime();
					};

					var btn:PsychUIButton = new PsychUIButton(0, timeTxt.y + 30, Language.get('charting_goto_btn'), function()
					{
						curSec = currentSec;
						FlxG.sound.music.time = FlxMath.bound(curTime, 0, FlxG.sound.music.length - 1);
						loadSection();
						state.close();
					});
					btn.cameras = state.cameras;
					btn.screenCenter(X);
					btn.x -= 60;
					state.add(btn);

					var btn:PsychUIButton = new PsychUIButton(0, btn.y, Language.get('charting_cancel_btn'), state.close);
					btn.cameras = state.cameras;
					btn.screenCenter(X);
					btn.x += 60;
					state.add(btn);
				}
			));
		}, btnWid);
		btn.text.alignment = LEFT;
		tab_group.add(btn);

		btnY++;
		btnY += 20;
		var btn:PsychUIButton = new PsychUIButton(btnX, btnY, Language.get('charting_theme_tab3'), function()
		{
			if(!fileDialog.completed) return;
			upperBox.isMinimized = true;
			upperBox.bg.visible = false;

			openSubState(new BasePrompt(500, 260, Language.get('prompt_theme_tab'),
				function(state:BasePrompt)
				{
					var btn:PsychUIButton = new PsychUIButton(state.bg.x + state.bg.width - 40, state.bg.y, 'X', state.close, 40);
					btn.cameras = state.cameras;
					state.add(btn);

					var btnY = 320;
					var btn:PsychUIButton = new PsychUIButton(0, btnY, Language.get('theme_light'), changeTheme.bind(LIGHT));
					btn.screenCenter(X);
					btn.x -= 180;
					btn.cameras = state.cameras;
					state.add(btn);
			
					var btn:PsychUIButton = new PsychUIButton(0, btnY, Language.get('theme_dark'), changeTheme.bind(DARK));
					btn.screenCenter(X);
					btn.x -= 60;
					btn.cameras = state.cameras;
					state.add(btn);
					
					var btn:PsychUIButton = new PsychUIButton(0, btnY, Language.get('theme_default'), changeTheme.bind(DEFAULT));
					btn.screenCenter(X);
					btn.cameras = state.cameras;
					btn.x += 60;
					state.add(btn);
			
					var btn:PsychUIButton = new PsychUIButton(0, btnY, Language.get('theme_vslice'), changeTheme.bind(VSLICE));
					btn.screenCenter(X);
					btn.x += 180;
					btn.cameras = state.cameras;
					state.add(btn);

					btnY += 60;
					var btn:PsychUIButton = new PsychUIButton(0, btnY, Language.get('theme_custom'), changeTheme.bind(CUSTOM));
					btn.screenCenter(X);
					btn.x -= 180;
					btn.cameras = state.cameras;
					state.add(btn);

					var customBgC:String = '303030';
					if(chartEditorSave.data.customBgColor != null)
						customBgC = chartEditorSave.data.customBgColor;

					var input:PsychUIInputText = new PsychUIInputText(0, btnY, 80, customBgC, 10);
					input.maxLength = 6;
					input.filterMode = ONLY_HEXADECIMAL;
					input.forceCase = UPPER_CASE;
					input.screenCenter(X);
					input.x -= 60;
					input.cameras = state.cameras;
					input.onChange = function(old:String, cur:String)
					{
						chartEditorSave.data.customBgColor = cur;
						changeTheme(CUSTOM);
					}

					var txt:FlxText = new FlxText(input.x, input.y - 15, 120, Language.get('theme_bgcolor'));
					txt.font = Paths.font(Language.get('uitab_font'));
					txt.size = 12;
					txt.cameras = state.cameras;
					state.add(txt);
					state.add(input);

					var customGridC:Array<String> = ['DFDFDF', 'BFBFBF'];
					if(chartEditorSave.data.customGridColors != null && chartEditorSave.data.customGridColors.length > 1)
						customGridC = chartEditorSave.data.customGridColors;

					var input:PsychUIInputText = new PsychUIInputText(0, btnY, 80, customGridC[0], 10);
					input.maxLength = 6;
					input.filterMode = ONLY_HEXADECIMAL;
					input.forceCase = UPPER_CASE;
					input.screenCenter(X);
					input.x += 60;
					input.cameras = state.cameras;
					input.onChange = function(old:String, cur:String)
					{
						chartEditorSave.data.customGridColors[0] = cur;
						changeTheme(CUSTOM);
					}

					var txt:FlxText = new FlxText(input.x, input.y - 15, 120, Language.get('theme_gridcolor'));
					txt.font = Paths.font(Language.get('uitab_font'));
					txt.size = 12;
					txt.cameras = state.cameras;
					state.add(txt);
					state.add(input);

					var input:PsychUIInputText = new PsychUIInputText(0, btnY + 30, 80, customGridC[1], 10);
					input.maxLength = 6;
					input.filterMode = ONLY_HEXADECIMAL;
					input.forceCase = UPPER_CASE;
					input.screenCenter(X);
					input.x += 60;
					input.cameras = state.cameras;
					input.onChange = function(old:String, cur:String)
					{
						chartEditorSave.data.customGridColors[1] = cur;
						changeTheme(CUSTOM);
					}
					state.add(input);

					var customGridOtherC:Array<String> = ['5F5F5F', '4A4A4A'];
					if(chartEditorSave.data.customNextGridColors != null && chartEditorSave.data.customNextGridColors.length > 1)
						customGridOtherC = chartEditorSave.data.customNextGridColors;

					var input:PsychUIInputText = new PsychUIInputText(0, btnY, 80, customGridOtherC[0], 10);
					input.maxLength = 6;
					input.filterMode = ONLY_HEXADECIMAL;
					input.forceCase = UPPER_CASE;
					input.screenCenter(X);
					input.x += 180;
					input.cameras = state.cameras;
					input.onChange = function(old:String, cur:String)
					{
						chartEditorSave.data.customNextGridColors[0] = cur;
						changeTheme(CUSTOM);
					}

					var txt:FlxText = new FlxText(input.x, input.y - 15, 120, Language.get('theme_ngridcolor'));
					txt.font = Paths.font(Language.get('uitab_font'));
					txt.size = 12;
					txt.cameras = state.cameras;
					state.add(txt);
					state.add(input);

					var input:PsychUIInputText = new PsychUIInputText(0, btnY + 30, 80, customGridOtherC[1], 10);
					input.maxLength = 6;
					input.filterMode = ONLY_HEXADECIMAL;
					input.forceCase = UPPER_CASE;
					input.screenCenter(X);
					input.x += 180;
					input.cameras = state.cameras;
					input.onChange = function(old:String, cur:String)
					{
						chartEditorSave.data.customNextGridColors[1] = cur;
						changeTheme(CUSTOM);
					}
					state.add(input);

				}
			));
		}, btnWid);
		btn.text.alignment = LEFT;
		tab_group.add(btn);

		btnY++;
		btnY += 20;
		var btn:PsychUIButton = new PsychUIButton(btnX, btnY, Language.get('charting_visualeffects_tab3'), function()
		{
			if(!fileDialog.completed) return;
			upperBox.isMinimized = true;
			upperBox.bg.visible = false;

			openSubState(new BasePrompt(450, 400, Language.get('prompt_visualeffects_tab'),
				function(state:BasePrompt)
				{
					var btn:PsychUIButton = new PsychUIButton(state.bg.x + state.bg.width - 40, state.bg.y, 'X', state.close, 40);
					btn.cameras = state.cameras;
					state.add(btn);

					// 初始化变量（从保存数据中读取）
					if(chartEditorSave.data.iconBopEnabled != null)
						iconBopEnabled = chartEditorSave.data.iconBopEnabled;
					if(chartEditorSave.data.mustHitTweenEnabled != null)
						mustHitTweenEnabled = chartEditorSave.data.mustHitTweenEnabled;
					if(chartEditorSave.data.showTrackColors == null)
						chartEditorSave.data.showTrackColors = true;


					var checkY = state.bg.y + 60;

					// 小图标跳动
					var iconBopCheckBox:PsychUICheckBox = new PsychUICheckBox(state.bg.x + 40, checkY, Language.get('visualeffect_iconbop'), 200);
					iconBopCheckBox.checked = iconBopEnabled;
					iconBopCheckBox.onClick = function()
					{
						iconBopEnabled = chartEditorSave.data.iconBopEnabled = iconBopCheckBox.checked;
						chartEditorSave.flush();
					};
					iconBopCheckBox.cameras = state.cameras;
					state.add(iconBopCheckBox);
					checkY += 30;

					// 倒三角tween
					var mustHitTweenCheckBox:PsychUICheckBox = new PsychUICheckBox(state.bg.x + 40, checkY, Language.get('visualeffect_musthittween'), 200);
					mustHitTweenCheckBox.checked = mustHitTweenEnabled;
					mustHitTweenCheckBox.onClick = function()
					{
						mustHitTweenEnabled = chartEditorSave.data.mustHitTweenEnabled = mustHitTweenCheckBox.checked;
						chartEditorSave.flush();
						if(!mustHitTweenEnabled)
							FlxTween.cancelTweensOf(mustHitIndicator);
					};
					mustHitTweenCheckBox.cameras = state.cameras;
					state.add(mustHitTweenCheckBox);
					checkY += 30;

					// 轨道颜色
					var trackColorsCheckBox2:PsychUICheckBox = new PsychUICheckBox(state.bg.x + 40, checkY, Language.get('visualeffect_trackcolors'), 200);
					trackColorsCheckBox2.checked = chartEditorSave.data.showTrackColors;
					trackColorsCheckBox2.onClick = function()
					{
						chartEditorSave.data.showTrackColors = trackColorsCheckBox2.checked;
						chartEditorSave.flush();
						// 立即应用设置
						if(playerTrackOverlay != null) playerTrackOverlay.visible = trackColorsCheckBox2.checked;
						if(opponentTrackOverlay != null) opponentTrackOverlay.visible = trackColorsCheckBox2.checked;
						if(eventTrackOverlay != null) eventTrackOverlay.visible = trackColorsCheckBox2.checked;
					};
					trackColorsCheckBox2.cameras = state.cameras;
					state.add(trackColorsCheckBox2);
					checkY += 30;

					// 显示角色
					var showCharacterCheckBox:PsychUICheckBox = new PsychUICheckBox(state.bg.x + 40, checkY, Language.get('visualeffect_showcharacter'), 200);
					showCharacterCheckBox.checked = chartEditorSave.data.showCharacters;
					showCharacterCheckBox.onClick = function()
					{
						chartEditorSave.data.showCharacters = showCharacterCheckBox.checked;
						chartEditorSave.flush();
						if(!charactersLoaded && showCharacterCheckBox.checked)
						{
							initCharacters();
						}
						else
						{
							if(dad != null) dad.visible = showCharacterCheckBox.checked;
							if(boyfriend != null) boyfriend.visible = showCharacterCheckBox.checked;
						}
					};
					showCharacterCheckBox.cameras = state.cameras;
					state.add(showCharacterCheckBox);
					checkY += 30;

					// 可拖动角色
					var dragCharacterCheckBox2:PsychUICheckBox = new PsychUICheckBox(state.bg.x + 40, checkY, Language.get('visualeffect_dragcharacter'), 200);
					dragCharacterCheckBox2.checked = chartEditorSave.data.allowDragCharacters;
					dragCharacterCheckBox2.onClick = function()
					{
						chartEditorSave.data.allowDragCharacters = dragCharacterCheckBox2.checked;
						chartEditorSave.flush();
					};
					dragCharacterCheckBox2.cameras = state.cameras;
					state.add(dragCharacterCheckBox2);
					checkY += 30;

					// Lil' Buddies 迷你角色预览
					var lilBuddiesCheckBox:PsychUICheckBox = new PsychUICheckBox(state.bg.x + 40, checkY, Language.get('visualeffect_lilbuddies'), 200);
					lilBuddiesCheckBox.checked = chartEditorSave.data.showLilBuddies;
					lilBuddiesCheckBox.onClick = function()
					{
						chartEditorSave.data.showLilBuddies = lilBuddiesCheckBox.checked;
						chartEditorSave.flush();
						if(lilStage != null) lilStage.visible = lilBuddiesCheckBox.checked;
						if(lilBf != null) lilBf.visible = lilBuddiesCheckBox.checked;
						if(lilOpp != null) lilOpp.visible = lilBuddiesCheckBox.checked;
						if(lilBuddiesCheckBox.checked)
					{
						if(lilBf != null) { lilBf.animation.play('idle', false, false); lilBf.color = 0xFFFFFFFF; lilBfSingFinishedBeat = -1; lilBfInSustain = false; }
						if(lilOpp != null) { lilOpp.animation.play('idle', false, false); lilOpp.color = 0xFFFFFFFF; lilOppSingFinishedBeat = -1; lilOppInSustain = false; }
					}
					};
					lilBuddiesCheckBox.cameras = state.cameras;
					state.add(lilBuddiesCheckBox);

					var btnY = state.bg.y + 240;
					var btn:PsychUIButton = new PsychUIButton(0, btnY, Language.get('charting_ok_btn'), state.close);
					btn.screenCenter(X);
					btn.cameras = state.cameras;
					state.add(btn);
				}
			));
		}, btnWid);
		btn.text.alignment = LEFT;
		tab_group.add(btn);

		btnY += 20;
		var btn:PsychUIButton = new PsychUIButton(btnX, btnY, Language.get('charting_resetuibox_tab3'), function()
		{
			mainBox.setPosition(mainBoxPosition.x, mainBoxPosition.y);
			infoBox.setPosition(infoBoxPosition.x, infoBoxPosition.y);
			UIEvent(PsychUIBox.DROP_EVENT, btn); //to force a save
		}, btnWid);
		btn.text.alignment = LEFT;
		tab_group.add(btn);
	}

	function updateChartData()
	{
		for (secNum => section in PlayState.SONG.notes)
			PlayState.SONG.notes[secNum].sectionNotes = [];

		notes.sort(PlayState.sortByTime);
		var noteSec:Int = 0;
		var nextSectionTime:Float = cachedSectionTimes[noteSec + 1];
		var curSectionTime:Float = cachedSectionTimes[noteSec];

		for (num => note in notes)
		{
			if(note == null) continue;

			while(cachedSectionTimes[noteSec + 1] <= note.strumTime)
			{
				noteSec++;
				nextSectionTime = cachedSectionTimes[noteSec + 1];
				curSectionTime = cachedSectionTimes[noteSec];
			}

			var arr:Array<Dynamic> = PlayState.SONG.notes[noteSec].sectionNotes;
			//trace('Added note with time ${note.songData[0]} at section $noteSec');
			arr.push(note.songData);
		}

		// 排序：先按时间，再按轨道索引（最左侧轨道优先）
		events.sort(function(a:EventMetaNote, b:EventMetaNote):Int {
			var timeDiff = a.strumTime - b.strumTime;
			if(Math.abs(timeDiff) > 0.0001) {
				return timeDiff > 0 ? 1 : -1;
			}
			// 同一时间点，按轨道索引排序，最左侧轨道(0)优先
			return a.eventTrackIndex - b.eventTrackIndex;
		});
		PlayState.SONG.events = [];
		for (event in events)
			PlayState.SONG.events.push(event.songData);
	}

	function saveChart(canQuickSave:Bool = true)
	{
		updateChartData();
		chartDataDirty = false;
		// LE LTS 双侧：保存格式按两侧键数相等性切换（仅作用于深拷贝，不影响内存 SONG）——
		// 相等（或未设置 playerKeyCount）→ EK/Psych 格式：输出 mania = keyCount-1、不输出 playerKeyCount；
		// 不等 → LE 格式：输出 keyCount + playerKeyCount、不输出 mania（LE 引擎读取）。
		var saveSong:Dynamic = haxe.Json.parse(haxe.Json.stringify(PlayState.SONG));
		if (saveSong.playerKeyCount == null || saveSong.playerKeyCount == saveSong.keyCount)
		{
			Reflect.deleteField(saveSong, 'playerKeyCount');
			if (saveSong.keyCount != null) saveSong.mania = Std.int(saveSong.keyCount) - 1;
			else if (saveSong.mania == null) saveSong.mania = 3;
		}
		else Reflect.deleteField(saveSong, 'mania');
		var chartData:String = PsychJsonPrinter.print(saveSong, ['sectionNotes', 'events']);
		if(canQuickSave && Song.chartPath != null)
		{
			#if mobile
			var chartName:String = Paths.formatToSongPath(PlayState.SONG.song) + '.json';
			StorageUtil.saveContent(chartName, chartData);
			#else
			File.saveContent(Song.chartPath, chartData);
			showOutput(Language.get('charting_msg_chart_saved', [Song.chartPath]));
			#end
		}
		else
		{
			var chartName:String = Paths.formatToSongPath(PlayState.SONG.song) + '.json';
			if(Song.chartPath != null) chartName = Song.chartPath.substr(Song.chartPath.lastIndexOf('/')).trim();
			#if mobile
			StorageUtil.saveContent(chartName, chartData);
			#else
			fileDialog.save(chartName, chartData,
				function()
				{
					var newPath:String = fileDialog.path;
					Song.chartPath = newPath.replace('\\', '/');
					reloadNotesDropdowns();
					showOutput(Language.get('charting_msg_chart_saved', [newPath]));

				}, null, function() showOutput(Language.get('charting_msg_chart_saveerr'), true));
			#end
		}
	}
	
	/**
	 * 反向转谱核心：把当前 psych_v1 的 song 对象转成 Psych Engine 0.6.x 的 JSON 字符串。
	 * 仅支持 4 键谱面；失败时返回 null（错误信息已通过 showOutput 提示）。
	 * 规则：剥离自定义字段、noteType 转 Int 索引、事件截断为 [name,v1,v2]、强制 mustHitSection=true、补默认箭头皮肤、包裹为 {"song":{}}。
	 */
	function convertSongToLegacy(song:Dynamic):String
	{
		if(song == null) return null;

		// 引擎已回退为原生 4 键，所有谱面均为 4 键，无需多键校验。

		try
		{
			// 深拷贝，避免污染传入对象
			var raw:Dynamic = haxe.Json.parse(haxe.Json.stringify(song));

			// 清理 song 级自定义字段
			Reflect.deleteField(raw, 'format');
			Reflect.deleteField(raw, 'specialInst');
			Reflect.deleteField(raw, 'specialVocal');
			Reflect.deleteField(raw, 'specialEvents');
			Reflect.deleteField(raw, '__original_path');

			// 必填兜底（旧版 0.6.3 中 arrowSkin/splashSkin 为必填字符串）
			if(raw.arrowSkin == null || raw.arrowSkin.length == 0) raw.arrowSkin = 'NOTE_assets';
			if(raw.splashSkin == null || raw.splashSkin.length == 0) raw.splashSkin = 'noteSplashes';

			// noteType：String -> Int 索引；mustHitSection 强制 true（配合归一化 noteData）
			if(raw.notes != null)
			{
				var notes:Array<Dynamic> = raw.notes;
				// 当前键数：多键谱保留 absolute lane + 原 mustHitSection（0.6.3 无多键概念，
				// 强制翻转会损坏数据；写入 mania 字段供支持多键的 0.7.3 EK 类引擎识别）。
				var mania:Int = (raw.mania != null) ? Std.int(raw.mania) : 3;
				var isMultiKey:Bool = (mania != 3);

				for (sec in notes)
				{
					if(sec == null) continue;
					if (!isMultiKey)
					{
						// 4 键：新版 noteData 已归一化（0-3=玩家 / 4-7=对手），与 mustHitSection 无关；
						// 旧版 0.6.3 靠 mustHitSection 翻转归属，故强制 true 使其解读与归一化数据一致（音符归属 100% 正确）。
						// 代价：旧版镜头会一直聚焦 BF，原谱对手镜头段丢失（纯视觉差异）。
						sec.mustHitSection = true;
					}
					Reflect.deleteField(sec, 'bpmRamp');

					if(sec.sectionNotes != null)
					{
						var sectionNotes:Array<Dynamic> = sec.sectionNotes;
						for (note in sectionNotes)
						{
							if(note == null || note.length < 4) continue;
							var nt:String = (note[3] != null) ? Std.string(note[3]) : '';
							var idx:Int = noteTypes.indexOf(nt);
							note[3] = (idx < 0) ? 0 : idx;
						}
					}
				}
			}

			// events：截断为 [name, value1, value2]，丢弃 value3/value4；内联进谱面
			if(raw.events != null)
			{
				var convertedEvents:Array<Dynamic> = [];
				var events:Array<Dynamic> = raw.events;
				for (ev in events)
				{
					if(ev == null || ev.length < 2) continue;
					var evTime:Dynamic = ev[0];
					var evList:Array<Dynamic> = [];
					if(ev[1] != null)
					{
						var eList:Array<Dynamic> = ev[1];
						for (e in eList)
						{
							if(e == null || e.length < 1) continue;
							var trimmed:Array<Dynamic> = [e[0]];
							trimmed.push((e.length > 1 && e[1] != null) ? e[1] : '');
							trimmed.push((e.length > 2 && e[2] != null) ? e[2] : '');
							evList.push(trimmed);
						}
					}
					convertedEvents.push([evTime, evList]);
				}
				raw.events = convertedEvents;
			}

			var output:Dynamic = {song: raw};
			return haxe.Json.stringify(output, "\t");
		}
		catch(e:Dynamic)
		{
			showOutput(Language.get('charting_legacy_convertfail', [Std.string(e)]), true);
			return null;
		}
	}

	function saveChartLegacy()
	{
		updateChartData();

		// 反向转谱：当前编辑中的谱面 -> Psych Engine 0.6.x 格式并保存
		var chartData:String = convertSongToLegacy(PlayState.SONG);
		if(chartData == null) return;

		var chartName:String = Paths.formatToSongPath(PlayState.SONG.song) + '.json';
		#if mobile
		StorageUtil.saveContent(chartName, chartData);
		showOutput(Language.get('charting_legacy_saved_mobile', [chartName]));
		#else
		fileDialog.save(chartName, chartData,
			function()
			{
				showOutput(Language.get('charting_legacy_saved', [fileDialog.path]));
			}, null, function() showOutput(Language.get('charting_legacy_savefail'), true));
		#end
	}

	inline function getCurChartSection()
	{
		return PlayState.SONG.notes != null ? PlayState.SONG.notes[curSec] : null;
	}

	function updateNotesRGB()
	{
		PlayState.SONG.disableNoteRGB = noRGBCheckBox.checked;
		if(ClientPrefs.data.arrowColorMode == 'HSV') return;

		for (note in notes)
		{
			if(note == null) continue;

			note.rgbShader.enabled = !noRGBCheckBox.checked;
			if(note.rgbShader.enabled)
			{
				var data = backend.NoteTypesConfig.loadNoteTypeData(note.noteType);
				if(data == null || data.length < 1) continue;

				for (line in data)
				{
					var prop:String = line.property.join('.');
					if(prop == 'rgbShader.enabled')
						note.rgbShader.enabled = line.value;
				}
			}
		}

		for (note in strumLineNotes)
			note.rgbShader.enabled = !noRGBCheckBox.checked;
	}

	function updateGridVisibility()
	{
		showLastGridButton.text.text = showPreviousSection	? Language.get('charting_hidelastsec_tab3') :  Language.get('charting_showlastsec_tab3');
		showNextGridButton.text.text = showNextSection		? Language.get('charting_hidenextsec_tab3') :  Language.get('charting_shownextsec_tab3');

		prevOpponentGridBg.visible = (curSec > 0 && showPreviousSection);
		nextOpponentGridBg.visible = (curSec < PlayState.SONG.notes.length - 1 && showNextSection);
		if(SHOW_EVENT_COLUMN)
		{
			prevEventGridBg.visible = (curSec > 0 && showPreviousSection);
			nextEventGridBg.visible = (curSec < PlayState.SONG.notes.length - 1 && showNextSection);
		}
		prevPlayerGridBg.visible = (curSec > 0 && showPreviousSection);
		nextPlayerGridBg.visible = (curSec < PlayState.SONG.notes.length - 1 && showNextSection);

		noteTypeLabelsButton.text.text = showNoteTypeLabels ? Language.get('charting_hidenlab_tab3') : Language.get('charting_shownlab_tab3');
		for (num => text in MetaNote.noteTypeTexts)
			text.visible = showNoteTypeLabels;
		softReloadNotes();
	}

function adaptNotesToNewTimes(oldTimes:Array<Float>)
{
	undoActions = [];
	setSongPlaying(false);
	var gridLerp:Float = FlxMath.bound((scrollY + FlxG.height/2 - opponentGridBg.y) / opponentGridBg.height, 0.000001, 0.999999);
	notes.sort(PlayState.sortByTime);

	// 捕获"旧"的 BPM 映射（来自上一次 _cacheSections），用于把音符按其网格步位置重新定位，
	// 这样在线性 BPM 过渡(ramp)下调整 ramp 时，音符的步位置保持不变，不会被线性缩放挤歪/重叠。
	var oldMap = Conductor.bpmChangeMap.copy();

	_cacheSections(); // 用新的 ramp 配置重建 Conductor 映射与 section 时间

	// 用旧映射求出每个音符的步位置；之后恢复新映射，用积分公式换算到新的毫秒时间
	var newMap = Conductor.bpmChangeMap;
	Conductor.bpmChangeMap = oldMap;
	var oldSteps:Array<Float> = [];
	for (note in notes)
		oldSteps.push((note == null || note.strumTime <= 0) ? Math.NaN : Conductor.getStep(note.strumTime));
	Conductor.bpmChangeMap = newMap;

	var noteSec:Int = 0;
	var oldNextSectionTime:Float = oldTimes[noteSec + 1];
	var oldCurSectionTime:Float = oldTimes[noteSec];
	var nextSectionTime:Float = cachedSectionTimes[noteSec + 1];
	var curSectionTime:Float = cachedSectionTimes[noteSec];

	for (num => note in notes)
	{
		if(note == null || note.strumTime <= 0) continue;

		while(noteSec + 2 < oldTimes.length && oldTimes[noteSec + 1] <= note.strumTime)
		{
			noteSec++;
			oldNextSectionTime = oldTimes[noteSec + 1];
			oldCurSectionTime = oldTimes[noteSec];
			nextSectionTime = cachedSectionTimes[noteSec + 1];
			curSectionTime = cachedSectionTimes[noteSec];

			if(noteSec + 1 >= cachedSectionTimes.length)
			{
				trace('failsafe, cancel early and delete notes after this');
				var changedSelected:Bool = false;
				for(i in num...notes.length)
				{
					var n = notes[num];
					if(n != null)
					{
						if(selectedNotes.contains(n))
						{
							selectedNotes.remove(n);
							changedSelected = true;
						}
						notes.remove(n);
						note.destroy();
					}
				}
				if(changedSelected) onSelectNote();
				loadSection();
				return;
			}
			//trace('changed section: $noteSec, $oldNextSectionTime, $oldCurSectionTime, $nextSectionTime, $curSectionTime');
		}

		// 按步位置保持：用旧映射求该音符的步，再用新映射换算新毫秒时间（兼容 ramp）
		var oldStep:Float = oldSteps[num];
		if(!Math.isNaN(oldStep))
		{
			var newMs:Float = Conductor.getTimeFromStep(oldStep);
			// 仅做轻微夹取，防止浮点误差越界；正常应已落在本段内
			note.setStrumTime(FlxMath.bound(newMs, curSectionTime, nextSectionTime));
		}

		positionNoteYOnTime(note, noteSec);
		note.updateSustainToStepCrochet(cachedSectionCrochets[noteSec] / 4);
	}

	for (event in events)
	{
		var secNum:Int = 0;
		for (time in cachedSectionTimes)
		{
			if(time > event.strumTime) break;
			secNum++;
		}
		positionNoteYOnTime(event, secNum);
	}
	
		var time:Float = FlxMath.remapToRange(gridLerp, 0, 1, cachedSectionTimes[curSec], cachedSectionTimes[curSec + 1]);
		if(Math.isNaN(time))
		{
			time = 0;
			curSec = 0;
		}
		
		if(FlxG.sound.music != null && time >= FlxG.sound.music.length)
		{
			time = FlxG.sound.music.length - 1;
			curSec = PlayState.SONG.notes.length - 1;
		}
		FlxG.sound.music.time = time;
		Conductor.songPosition = time;
		forceDataUpdate = true;
		loadSection();
	}

	public function UIEvent(id:String, sender:Dynamic)
	{
		//trace(id, sender);
		switch(id)
		{
			case PsychUIButton.CLICK_EVENT, PsychUIDropDownMenu.CLICK_EVENT:
				ignoreClickForThisFrame = true;

			case PsychUIBox.CLICK_EVENT:
				ignoreClickForThisFrame = true;

			case PsychUIBox.MINIMIZE_EVENT:
				if(sender == upperBox)
				{
					upperBox.bg.visible = !upperBox.isMinimized;
					// 背景板位置与尺寸由 PsychUIBox.bgFollowsSelectedTab 实时同步，无需手动更新
				}

			case PsychUIBox.DROP_EVENT:
				chartEditorSave.data.mainBoxPosition = [mainBox.x, mainBox.y];
				chartEditorSave.data.infoBoxPosition = [infoBox.x, infoBox.y];
		}
	}

	function openEditorPlayState()
	{
		if(FlxG.sound.music == null)
		{
			showOutput(Language.get('charting_msg_loadvalid_preview'), true);
			return;
		}
		setSongPlaying(false);
		chartEditorSave.flush(); //just in case a random crash happens before loading

		// 预览游玩期间暂停制谱器主逻辑：
		// 1) 避免父状态每帧用已暂停的 FlxG.sound.music.time 覆盖 Conductor.songPosition（否则预览卡在同一时机不动）；
		// 2) persistentUpdate=false 使打开子状态时触发 FlxG.inputs.onStateSwitch() 清空 justPressed，
		//    防止 F12 在同一帧被子状态的退出判断捕获导致预览瞬间关闭（vanilla104 即为 persistentUpdate=false）。
		persistentUpdate = false;
		openSubState(new EditorPlayState(cast notes, [vocals, opponentVocals]));
		upperBox.isMinimized = true;
		mainBox.visible = infoBox.visible = false;
	}

	function goToPlayState()
	{
		persistentUpdate = false;
		FlxG.mouse.visible = false;
		chartEditorSave.flush();

		setSongPlaying(false);
		updateChartData();
		StageData.loadDirectory(PlayState.SONG);
		LoadingState.loadAndSwitchState(new PlayState());
		ClientPrefs.toggleVolumeKeys(true);
	}
	
	override function openSubState(SubState:FlxSubState)
	{
		setSongPlaying(false);
		if (Std.is(SubState, BasePrompt))
		{
			_blockParentUpdate = true;
			persistentUpdate = false;
		}
		super.openSubState(SubState);
		// 顶部 HaxeUI 菜单栏始终可见，不随子状态隐藏（用户要求顶栏不自动隐藏）
		// if(haxeMenuBar != null) haxeMenuBar.visible = false;
	}

	override function closeSubState()
	{
		if (_blockParentUpdate)
		{
			_blockParentUpdate = false;
			persistentUpdate = true;
		}
		ClientPrefs.toggleVolumeKeys(true);
		super.closeSubState();
		upperBox.isMinimized = true;
		mainBox.visible = infoBox.visible = true;
		upperBox.bg.visible = false;
		updateAudioVolume();
		// 顶部 HaxeUI 菜单栏始终可见，不随子状态隐藏
		// if(haxeMenuBar != null) haxeMenuBar.visible = true;
	}

	override function destroy()
	{
		// 退出制谱器时清除编辑器双侧静态档位，避免残留影响 PlayState 等后续状态
		Note.editorDualMode = false;

		// 退出制谱器时停止窗口缩放监听
		FlxG.stage.removeEventListener(Event.RESIZE, onWindowResized);

		// 顶部条信息（FPS/内存/版本）为 FlxText，随状态销毁自动清理

		// 还原 FPS 计数器的可见性（恢复为 showFPS 设置）
		Main.forceHideFPS = false;
		Main.updateFPSCounterVisibility();

		// 退出制谱器时还原为原来的缩放模式（destroy 在下一状态 create 之前执行，确保其它界面恢复 1280x720）
		if (_hdActive)
		{
			FlxG.scaleMode = _hdPrevScaleMode;
			FlxG.resizeGame(FlxG.stage.stageWidth, FlxG.stage.stageHeight);
			_hdActive = false;
			_hdPrevScaleMode = null;
		}



		Note.globalRgbShaders = [];
		backend.NoteTypesConfig.clearNoteTypesData();

		for (num => text in MetaNote.noteTypeTexts)
			text.destroy();

		MetaNote.noteTypeTexts = [];
		fileDialog.destroy();
		super.destroy();
	}

	//============================================================
	// 窗口缩放提示：窗口尺寸变化后，提示用户是否需要重载界面布局
	//============================================================

	/** 构建窗口缩放提示的 UI（背景、文字、重载按钮），默认全部隐藏 */
	function buildResizePromptUI()
	{
		if (_resizeBg != null) return;

		_resizeBg = new FlxSprite();
		_resizeBg.makeGraphic(10, 10, 0xFF16162A);
		_resizeBg.alpha = 0.88;
		_resizeBg.scrollFactor.set();
		_resizeBg.cameras = [camUI];
		add(_resizeBg);

		_resizeText = new FlxText(0, 0, 0, '', 18);
		_resizeText.setFormat(Paths.font(Language.get('uitab_font')), 18, FlxColor.WHITE, CENTER);
		_resizeText.scrollFactor.set();
		_resizeText.cameras = [camUI];
		add(_resizeText);

		_resizeButton = new PsychUIButton(0, 0, '重载界面', reloadInterface, 140);
		_resizeButton.cameras = [camUI];
		add(_resizeButton);

		hideResizePrompt(true);
	}

	/** 窗口缩放事件回调：根据与进入时窗口尺寸的差距决定提示形式 */
	/** 让背景铺满整个渲染缓冲区（FlxG.width × FlxG.height）并居中，避免窗口比背景图大时出现黑边 */
	function resizeBg():Void
	{
		if (bg == null) return;

		// 以铺满（cover）方式缩放：取宽高方向上更大的缩放比，保证完全覆盖且不变形
		var scale:Float = Math.max(FlxG.width / bg.frameWidth, FlxG.height / bg.frameHeight);
		bg.scale.set(scale, scale);
		bg.updateHitbox();
		bg.screenCenter();
	}

	function onWindowResized(e:Event):Void
	{
		// 窗口/内部缓冲尺寸变化时，重新让背景铺满整个渲染缓冲区，避免黑边
		resizeBg();

		if (!ENABLE_HD || !_hdActive) return;



		var newW:Int = FlxG.stage.stageWidth;
		var newH:Int = FlxG.stage.stageHeight;
		var delta:Float = Math.abs(newW - _initialStageW) + Math.abs(newH - _initialStageH);

		// 已经处在“明显变化”提示时，不因后续小幅缩放而降级为仅提示
		var persistent:Bool = delta > RESIZE_PROMPT_THRESHOLD;
		if (_resizePromptActive && _resizePromptPersistent) persistent = true;

		showResizePrompt(persistent);
	}


	/** 显示窗口缩放提示。persistent=true 显示“重载界面”按钮并常驻；否则仅短暂提示后飞出 */
	function showResizePrompt(persistent:Bool):Void
	{
		buildResizePromptUI();
		_resizePromptPersistent = persistent;

		var newW:Int = FlxG.stage.stageWidth;
		var newH:Int = FlxG.stage.stageHeight;

		var msg:String = persistent
			? '窗口大小已明显改变（${_initialStageW}x${_initialStageH} → ${newW}x${newH}）\n界面布局可能需要重载才能完全适配。'
			: '窗口已缩放，画面已自动适配。';

		if (_resizeDismissTimer != null) { _resizeDismissTimer.cancel(); _resizeDismissTimer = null; }

		_resizeBg.visible = _resizeText.visible = _resizeButton.visible = true;
		_resizeBg.alpha = 0.88;
		_resizeText.alpha = 1;
		_resizeButton.alpha = 1;

		_resizeText.text = msg;
		_resizeText.alignment = CENTER;
		_resizeText.fieldWidth = 0; // 自动宽度

		var textW:Float = _resizeText.width;
		var textH:Float = _resizeText.height;
		var btnW:Float = _resizeButton.width;
		var btnH:Float = _resizeButton.height;
		var pad:Float = 18;
		var bgW:Float = Math.max(textW, persistent ? btnW : 0) + pad * 2;
		var bgH:Float = textH + pad * 2 + (persistent ? (btnH + 10) : 0);

		_resizeBg.makeGraphic(Math.ceil(bgW), Math.ceil(bgH), 0xFF16162A);
		_resizeBg.alpha = 0.88;
		_resizeBg.x = (FlxG.width - bgW) / 2;
		_resizeBg.y = FlxG.height * 0.10;

		_resizeText.x = _resizeBg.x + (bgW - textW) / 2;
		_resizeText.y = _resizeBg.y + pad;

		_resizeButton.visible = persistent;
		_resizeButton.active = persistent; // 仅常驻（显示“重载界面”按钮）时可点击，隐藏时禁用防止误触重载
		_resizeButton.x = (FlxG.width - btnW) / 2;
		_resizeButton.y = _resizeBg.y + bgH - btnH - pad / 2;

		_resizePromptActive = true;

		if (!persistent)
		{
			// 几秒后自动飞出
			_resizeDismissTimer = new FlxTimer().start(3.0, function(t:FlxTimer) {
				flyOutResizePrompt();
			});
		}
	}

	/** 让提示向上飞出并淡出，结束后隐藏 */
	function flyOutResizePrompt():Void
	{
		if (!_resizePromptActive) return;
		_resizePromptActive = false;
		_resizePromptPersistent = false;
		if (_resizeDismissTimer != null) { _resizeDismissTimer.cancel(); _resizeDismissTimer = null; }

		var dur:Float = 0.4;
		FlxTween.tween(_resizeBg, {y: _resizeBg.y - 60, alpha: 0}, dur, {ease: FlxEase.cubeIn});
		FlxTween.tween(_resizeText, {y: _resizeText.y - 60, alpha: 0}, dur, {ease: FlxEase.cubeIn});
		FlxTween.tween(_resizeButton, {y: _resizeButton.y - 60, alpha: 0}, dur, {ease: FlxEase.cubeIn, onComplete: function(t:FlxTween) {
			hideResizePrompt(true);
		}});
	}

	/** 隐藏窗口缩放提示。immediate=true 立即隐藏，否则保留当前状态 */
	function hideResizePrompt(immediate:Bool):Void
	{
		_resizePromptActive = false;
		_resizePromptPersistent = false;
		if (_resizeDismissTimer != null) { _resizeDismissTimer.cancel(); _resizeDismissTimer = null; }
		if (_resizeButton != null) _resizeButton.active = false; // 隐藏时禁用点击，防止不可见按钮（默认位于左上角）被误触而重载界面
		if (_resizeBg == null) return;

		if (immediate)
		{
			_resizeBg.visible = false;
			_resizeText.visible = false;
			_resizeButton.visible = false;
			_resizeBg.alpha = _resizeText.alpha = _resizeButton.alpha = 1;
		}
	}

	/** 点击“重载界面”按钮：重建制谱器以按新窗口尺寸重新布局 */
	function reloadInterface():Void
	{
		hideResizePrompt(true);
		MusicBeatState.switchState(new ChartingState());
	}

	function loadFileList(mainFolder:String, ?optionalList:String = null, ?fileTypes:Array<String> = null)
	{
		if(fileTypes == null) fileTypes = ['.json'];

		var fileList:Array<String> = [];
		if(optionalList != null)
		{
			for (file in Mods.mergeAllTextsNamed(optionalList))
			{
				file = file.trim();
				if(file.length > 0 && !fileList.contains(file))
					fileList.push(file);
			}
		}

		for (directory in Mods.directoriesWithFile(Paths.getSharedPath(), mainFolder))
		{
			for (file in Paths.readDirectory(directory))
			{
				var path = haxe.io.Path.join([directory, file.trim()]);
				if (!FileSystem.isDirectory(path) && !file.startsWith('readme.'))
				{
					for (fileType in fileTypes)
					{
						var fileToCheck:String = file.substr(0, file.length - fileType.length);
						if(fileToCheck.length > 0 && path.endsWith(fileType) && !fileList.contains(fileToCheck))
						{
							fileList.push(fileToCheck);
							break;
						}
					}
				}
			}
		}
		return fileList;
	}
	
	function loadCharacterFile(char:String):CharacterFile
	{
		if(char != null)
		{
			try
			{
				var path:String = Paths.getPath('characters/' + char + '.json', TEXT);
				#if MODS_ALLOWED
				var unparsedJson = File.getContent(path);
				#else
				var unparsedJson = Assets.getText(path);
				#end
				return cast Json.parse(unparsedJson);
			}
			catch (e:Dynamic) {}
		}
		return null;
	}
	
	var overwriteSavedSomething:Bool = false;
	function overwriteCheck(savePath:String, overwriteName:String, saveData:String, continueFunc:Void->Void = null, ?continueOnCancel:Bool = false)
	{
		if(FileSystem.exists(savePath))
		{
			openSubState(new Prompt('Overwrite: "$overwriteName"?', function()
			{
				overwriteSavedSomething = true;
				File.saveContent(savePath, saveData);
				if(continueFunc != null) continueFunc();
			},
			continueOnCancel ? (function() if(continueFunc != null) continueFunc()) : null));
		}
		else
		{
			overwriteSavedSomething = true;
			File.saveContent(savePath, saveData);
			if(continueFunc != null) continueFunc();
		}
	}

	// Undo/Redo stuff
	var undoActions:Array<UndoStruct> = [];
	var currentUndo:Int = 0;
	function addUndoAction(action:UndoAction, data:Dynamic)
	{
		function destroyFromArr(arr:Array<MetaNote>)
		{
			if(arr == null || arr.length < 1) return;

			for (note in arr)
				if(note != null)
					note.destroy();
		}

		//trace('pushed action: $action');
		if(currentUndo > 0) undoActions = undoActions.slice(currentUndo);
		currentUndo = 0;
		undoActions.insert(0, {action: action, data: data});
		if(action != SELECT_NOTE) chartDataDirty = true;
		while(undoActions.length > 15)
		{
			var lastAction:UndoStruct = undoActions.pop();
			if(lastAction != null)
			{
				switch(lastAction.action)
				{
					case DELETE_NOTE:
						destroyFromArr(lastAction.data.notes);
						destroyFromArr(lastAction.data.events);
					case MOVE_NOTE:
						destroyFromArr(lastAction.data.originalNotes);
						destroyFromArr(lastAction.data.originalEvents);
					default:
				}
			}
		}
	}

	function undo()
	{
		if(isMovingNotes || currentUndo >= undoActions.length)
		{
			FlxG.sound.play(Paths.sound('cancelMenu'), 0.4);
			return;
		}

		var action:UndoStruct = undoActions[currentUndo];
		switch(action.action)
		{
			case ADD_NOTE:
				actionRemoveNotes(action.data.notes, action.data.events);

			case DELETE_NOTE:
				actionPushNotes(action.data.notes, action.data.events);

			case MOVE_NOTE:
				actionRemoveNotes(action.data.movedNotes, action.data.movedEvents);
				actionPushNotes(action.data.originalNotes, action.data.originalEvents);
				onSelectNote();

			case SELECT_NOTE:
				resetSelectedNotes();
				selectedNotes = action.data.old;
				if(lockedEvents) selectedNotes = selectedNotes.filter((note:MetaNote) -> !note.isEvent);
				onSelectNote();

			case MODIFY_NOTE:
				var n:MetaNote = action.data.note;
				n.setSustainLength(action.data.originalSustain, Conductor.stepCrochet, curZoom);
				softReloadNotes();
				onSelectNote();
		}
		showOutput('Undo #${currentUndo+1}: ${action.action}');
		if(action.action != SELECT_NOTE) chartDataDirty = true;
		FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);
		currentUndo++;
	}
	function redo()
	{
		if(isMovingNotes || currentUndo < 1)
		{
			FlxG.sound.play(Paths.sound('cancelMenu'), 0.4);
			return;
		}

		currentUndo--;
		var action:UndoStruct = undoActions[currentUndo];
		switch(action.action)
		{
			case ADD_NOTE:
				actionPushNotes(action.data.notes, action.data.events);

			case DELETE_NOTE:
				actionRemoveNotes(action.data.notes, action.data.events);

			case MOVE_NOTE:
				actionRemoveNotes(action.data.originalNotes, action.data.originalEvents);
				actionPushNotes(action.data.movedNotes, action.data.movedEvents);
				onSelectNote();

			case SELECT_NOTE:
				resetSelectedNotes();
				selectedNotes = action.data.current;
				if(lockedEvents) selectedNotes = selectedNotes.filter((note:MetaNote) -> !note.isEvent);
				onSelectNote();

			case MODIFY_NOTE:
				var n:MetaNote = action.data.note;
				n.setSustainLength(action.data.modifiedSustain, Conductor.stepCrochet, curZoom);
				softReloadNotes();
				onSelectNote();
		}
		showOutput('Redo #${currentUndo+1}: ${action.action}');
		if(action.action != SELECT_NOTE) chartDataDirty = true;
		FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);
	}

	function actionPushNotes(dataNotes:Array<MetaNote>, dataEvents:Array<EventMetaNote>)
	{
		resetSelectedNotes();
		if(dataNotes != null && dataNotes.length > 0)
		{
			for (note in dataNotes)
			{
				if(note != null)
				{
					notes.push(note);
					selectedNotes.push(note);
					note.songData[0] = note.strumTime;
					note.songData[1] = note.chartNoteData;
				}
			}
			notes.sort(PlayState.sortByTime);
		}
		if(dataEvents != null && dataEvents.length > 0)
		{
			for (event in dataEvents)
			{
				if(event != null)
				{
					events.push(event);
					selectedNotes.push(event);
					event.songData[0] = event.strumTime;
				}
			}
			events.sort(PlayState.sortByTime);
		}
		softReloadNotes();
	}

	function actionRemoveNotes(dataNotes:Array<MetaNote>, dataEvents:Array<EventMetaNote>)
	{
		if(dataNotes != null && dataNotes.length > 0)
		{
			for (note in dataNotes)
			{
				if(note != null)
				{
					notes.remove(note);
					selectedNotes.remove(note);

					if(note.exists)
					{
						note.colorTransform.redMultiplier = note.colorTransform.greenMultiplier = note.colorTransform.blueMultiplier = 1;
						if(note.animation.curAnim != null) note.animation.curAnim.curFrame = 0;
					}
				}

			}
		}
		if(dataEvents != null && dataEvents.length > 0)
		{
			for (event in dataEvents)
			{
				if(event != null)
				{
					trace(events.remove(event));
					selectedNotes.remove(event);

					if(event.exists)
					{
						event.colorTransform.redMultiplier = event.colorTransform.greenMultiplier = event.colorTransform.blueMultiplier = 1;
						if(event.animation.curAnim != null) event.animation.curAnim.curFrame = 0;
					}
				}
			}
		}
		softReloadNotes();
	}

	function actionReplaceNotes(oldNote:MetaNote, newNote:MetaNote)
	{
		for (act in undoActions)
		{
			for (field in Reflect.fields(act.data))
			{
				var fld:Array<MetaNote> = cast Reflect.field(act.data, field);
				if(fld != null && fld.length > 0)
					for (num => actNote in fld)
						if(actNote == oldNote)
							fld[num] = newNote;
			}
		}
	}

	// Ported from the old chart editor
	var wavData:Array<Array<Array<Float>>> = [[[0], [0]], [[0], [0]]];
	function updateWaveform() {
		#if (lime_cffi && !macro)
		if(curSec < 0 || curSec >= cachedSectionTimes.length || !waveformEnabled)
		{
			for (ws in waveformSprites) ws.visible = false;
			for (wl in waveformLibSprites) wl.visible = false;
			return;
		}

		var targetOrder:Array<WaveformTarget> = [INST, PLAYER, OPPONENT];

		// flixel-waveform 库版分支
		if(waveformStyle == LIBRARY)
		{
			for (ws in waveformSprites) ws.visible = false;
			updateLibraryWaveform();
			return;
		}
		for (wl in waveformLibSprites) wl.visible = false;

		// 旧版逐字节绘制：旧版为单选，只绘制选中的那个目标
		var gridLayout = getGridLayout();
		var height:Int = Std.int(opponentGridBg.height);
		for (t in [waveformTargetLegacy])
		{
			var waveformX:Float;
			var width:Int;
			switch(t)
			{
				case INST:
					waveformX = gridLayout.eventX;
					width = Std.int(GRID_SIZE * EVENT_TRACK_COUNT);
				case PLAYER:
					waveformX = gridLayout.playerX;
					width = Std.int(GRID_SIZE * GRID_COLUMNS_PER_PLAYER);
				case OPPONENT:
					waveformX = gridLayout.opponentX;
					width = Std.int(GRID_SIZE * GRID_COLUMNS_PER_PLAYER);
			}

			var ws:FlxSprite = waveformSprites[targetOrder.indexOf(t)];
			ws.visible = true;
			ws.y = opponentGridBg.y;
			ws.x = waveformX;
			if(Std.int(ws.height) != height && ws.pixels != null)
			{
				ws.pixels.dispose();
				ws.pixels.disposeImage();
				ws.makeGraphic(width, height, 0x00FFFFFF);
			}
			ws.pixels.fillRect(new Rectangle(0, 0, width, height), 0x00FFFFFF);

			wavData[0][0].resize(0);
			wavData[0][1].resize(0);
			wavData[1][0].resize(0);
			wavData[1][1].resize(0);

			var sound:FlxSound = switch(t)
			{
				case INST: FlxG.sound.music;
				case PLAYER: vocals;
				case OPPONENT: opponentVocals;
				default: null;
			}

			@:privateAccess
			if (sound != null && sound._sound != null && sound._sound.__buffer != null)
			{
				var bytes:Bytes = sound._sound.__buffer.data.toBytes();
				wavData = waveformData(sound._sound.__buffer, bytes, cachedSectionTimes[curSec] - Conductor.offset, cachedSectionTimes[curSec+1] - Conductor.offset, 1, wavData, height);
			}

			// Draws
			var gSize:Int = width;
			var hSize:Int = Std.int(gSize / 2);
			var size:Float = 1;

			var leftLength:Int = (wavData[0][0].length > wavData[0][1].length ? wavData[0][0].length : wavData[0][1].length);
			var rightLength:Int = (wavData[1][0].length > wavData[1][1].length ? wavData[1][0].length : wavData[1][1].length);
			var length:Int = leftLength > rightLength ? leftLength : rightLength;

			for (index in 0...length)
			{
				var lmin:Float = FlxMath.bound(((index < wavData[0][0].length && index >= 0) ? wavData[0][0][index] : 0) * (gSize / 1.12), -hSize, hSize) / 2;
				var lmax:Float = FlxMath.bound(((index < wavData[0][1].length && index >= 0) ? wavData[0][1][index] : 0) * (gSize / 1.12), -hSize, hSize) / 2;
				var rmin:Float = FlxMath.bound(((index < wavData[1][0].length && index >= 0) ? wavData[1][0][index] : 0) * (gSize / 1.12), -hSize, hSize) / 2;
				var rmax:Float = FlxMath.bound(((index < wavData[1][1].length && index >= 0) ? wavData[1][1][index] : 0) * (gSize / 1.12), -hSize, hSize) / 2;
				ws.pixels.fillRect(new Rectangle(hSize - (lmin + rmin), index * size, (lmin + rmin) + (lmax + rmax), size), FlxColor.WHITE);
			}
		}
		#else
		for (ws in waveformSprites) ws.visible = false;
		for (wl in waveformLibSprites) wl.visible = false;
		#end
	}

	// flixel-waveform 库实现：双缓冲显示当前 section（命中后台预渲染则直接换显，零闪烁；未命中则就地重绘）
	function updateLibraryWaveform()
	{
		#if (lime_cffi && !macro)
		var targetOrder:Array<WaveformTarget> = [INST, PLAYER, OPPONENT];

		for (l in waveformLibSprites) l.visible = false;
		for (l in waveformLibBackSprites) l.visible = false;

		for (t in waveformTargets)
		{
			var i:Int = targetOrder.indexOf(t);

			// 1) 后台已预渲染好本 section → 交换前后台缓冲，前台可直接显示，无需重绘
			if(waveformLibBackSection[i] == curSec)
			{
				var tmp:FlxWaveform = waveformLibSprites[i];
				waveformLibSprites[i] = waveformLibBackSprites[i];
				waveformLibBackSprites[i] = tmp;
				var tmpS:Int = waveformLibCacheSection[i];
				waveformLibCacheSection[i] = waveformLibBackSection[i];
				waveformLibBackSection[i] = tmpS;
			}

			var wl:FlxWaveform = waveformLibSprites[i];
			wl.autoUpdateBitmap = true; // 前台交给 FlxWaveform 在 draw 时重绘（未变更时不会触发）
			var ok:Bool = paintLibWaveform(wl, t, curSec);
			if(ok) waveformLibCacheSection[i] = curSec;

			wl.visible = ok;
			waveformLibBackSprites[i].visible = false;
		}
		#else
		for (l in waveformLibSprites) l.visible = false;
		for (l in waveformLibBackSprites) l.visible = false;
		#end
	}

	// 把目标 t 的波形按给定 section 配置到位（几何、音轨、样式、时间窗口）。
	// 返回是否有可用音频缓冲；前台由 autoUpdateBitmap 触发重绘，后台由调用方手动 generateWaveformBitmap()
	// loadedBuffers：记录该精灵已加载的音频缓冲（前台/后台各自独立，避免后台上台互跳过 loadData）
	function paintLibWaveform(wl:FlxWaveform, t:WaveformTarget, section:Int, ?loadedBuffers:Array<AudioBuffer>):Bool
	{
		#if (lime_cffi && !macro)
		if(loadedBuffers == null) loadedBuffers = waveformLibLoadedBuffers;
		var gridLayout = getGridLayout();
		var height:Int = Std.int(opponentGridBg.height);
		var waveformX:Float;
		var width:Int;
		switch(t)
		{
			case INST:
				waveformX = gridLayout.eventX;
				width = Std.int(GRID_SIZE * EVENT_TRACK_COUNT);
			case PLAYER:
				waveformX = gridLayout.playerX;
				width = Std.int(GRID_SIZE * GRID_COLUMNS_PER_PLAYER);
			case OPPONENT:
				waveformX = gridLayout.opponentX;
				width = Std.int(GRID_SIZE * GRID_COLUMNS_PER_PLAYER);
		}
		var i:Int = [INST, PLAYER, OPPONENT].indexOf(t);

		wl.x = waveformX;
		wl.y = opponentGridBg.y;
		if(wl.waveformWidth != width || wl.waveformHeight != height)
			wl.resize(width, height);

		var sound:FlxSound = switch(t)
		{
			case INST: FlxG.sound.music;
			case PLAYER: vocals;
			case OPPONENT: opponentVocals;
		}
		@:privateAccess
		var buffer:AudioBuffer = (sound != null && sound._sound != null) ? sound._sound.__buffer : null;
		if(buffer == null || buffer.data == null)
		{
			wl.visible = false;
			return false;
		}

		if(buffer != loadedBuffers[i])
		{
			loadedBuffers[i] = buffer;
			wl.loadDataFromAudioBuffer(buffer);
		}

		// 应用库版独立样式参数（各 setter 仅在该值变化时重绘）
		wl.waveformDrawMode = switch(waveformLibDrawMode)
		{
			case 'SPLIT_CHANNELS': SPLIT_CHANNELS;
			case 'SINGLE_CHANNEL': SINGLE_CHANNEL(0);
			default: COMBINED;
		};
		wl.waveformOrientation = VERTICAL; // 制谱器网格为竖向滚动，方向固定为竖向
		wl.waveformAlignment = CENTER(false);
		wl.waveformDrawRMS = waveformLibRMS;
		wl.waveformDrawBaseline = waveformLibBaseline;
		wl.waveformBarSize = waveformLibBarSize;
		wl.waveformBarPadding = waveformLibBarPadding;
		wl.waveformGainMultiplier = waveformLibGain;
		wl.waveformColor = CoolUtil.colorFromString(waveformLibColor);
		wl.waveformRMSColor = CoolUtil.colorFromString(waveformLibRMSColor);

		wl.waveformTime = cachedSectionTimes[section] - Conductor.offset;
		// 末段没有下一段起点缓存，用歌曲总时长作结束点；避免 duration=0 导致窗口为空/除零 → 波形空白
		var endTime:Float = (section + 1 < cachedSectionTimes.length)
			? cachedSectionTimes[section + 1]
			: FlxG.sound.music.length;
		var duration:Float = endTime - cachedSectionTimes[section];
		if(duration <= 0) duration = 1;
		wl.waveformDuration = duration;
		return true;
		#else
		return false;
		#end
	}

	function waveformData(buffer:AudioBuffer, bytes:Bytes, time:Float, endTime:Float, multiply:Float = 1, ?array:Array<Array<Array<Float>>>, ?steps:Float):Array<Array<Array<Float>>>
	{
		#if (lime_cffi && !macro)
		if (buffer == null || buffer.data == null) return [[[0], [0]], [[0], [0]]];

		var khz:Float = (buffer.sampleRate / 1000);
		var channels:Int = buffer.channels;

		var index:Int = Std.int(time * khz);

		var samples:Float = ((endTime - time) * khz);

		if (steps == null) steps = 1280;

		var samplesPerRow:Float = samples / steps;
		var samplesPerRowI:Int = Std.int(samplesPerRow);

		var gotIndex:Int = 0;

		var lmin:Float = 0;
		var lmax:Float = 0;

		var rmin:Float = 0;
		var rmax:Float = 0;

		var rows:Float = 0;

		var simpleSample:Bool = true;//samples > 17200;
		var v1:Bool = false;

		if (array == null) array = [[[0], [0]], [[0], [0]]];

		while (index < (bytes.length - 1)) {
			if (index >= 0) {
				var byte:Int = bytes.getUInt16(index * channels * 2);

				if (byte > 65535 / 2) byte -= 65535;

				var sample:Float = (byte / 65535);

				if (sample > 0)
					if (sample > lmax) lmax = sample;
				else if (sample < 0)
					if (sample < lmin) lmin = sample;

				if (channels >= 2) {
					byte = bytes.getUInt16((index * channels * 2) + 2);

					if (byte > 65535 / 2) byte -= 65535;

					sample = (byte / 65535);

					if (sample > 0) {
						if (sample > rmax) rmax = sample;
					} else if (sample < 0) {
						if (sample < rmin) rmin = sample;
					}
				}
			}

			v1 = samplesPerRowI > 0 ? (index % samplesPerRowI == 0) : false;
			while (simpleSample ? v1 : rows >= samplesPerRow) {
				v1 = false;
				rows -= samplesPerRow;

				gotIndex++;

				var lRMin:Float = Math.abs(lmin) * multiply;
				var lRMax:Float = lmax * multiply;

				var rRMin:Float = Math.abs(rmin) * multiply;
				var rRMax:Float = rmax * multiply;

				if (gotIndex > array[0][0].length) array[0][0].push(lRMin);
					else array[0][0][gotIndex - 1] = array[0][0][gotIndex - 1] + lRMin;

				if (gotIndex > array[0][1].length) array[0][1].push(lRMax);
					else array[0][1][gotIndex - 1] = array[0][1][gotIndex - 1] + lRMax;

				if (channels >= 2)
				{
					if (gotIndex > array[1][0].length) array[1][0].push(rRMin);
						else array[1][0][gotIndex - 1] = array[1][0][gotIndex - 1] + rRMin;

					if (gotIndex > array[1][1].length) array[1][1].push(rRMax);
						else array[1][1][gotIndex - 1] = array[1][1][gotIndex - 1] + rRMax;
				}
				else
				{
					if (gotIndex > array[1][0].length) array[1][0].push(lRMin);
						else array[1][0][gotIndex - 1] = array[1][0][gotIndex - 1] + lRMin;

					if (gotIndex > array[1][1].length) array[1][1].push(lRMax);
						else array[1][1][gotIndex - 1] = array[1][1][gotIndex - 1] + lRMax;
				}

				lmin = 0;
				lmax = 0;

				rmin = 0;
				rmax = 0;
			}

			index++;
			rows++;
			if(gotIndex > steps) break;
		}

		return array;
		#else
		return [[[0], [0]], [[0], [0]]];
		#end
	}
}
