package states.editors.old;

import flash.geom.Rectangle;
import haxe.Json;
import mobile.backend.StorageUtil;
import backend.CoolUtil;
import haxe.format.JsonParser;
import haxe.io.Bytes;

import flixel.FlxObject;
import flixel.addons.display.FlxGridOverlay;
import flixel.addons.ui.FlxUI;
import flixel.addons.ui.FlxUICheckBox;
import flixel.addons.ui.FlxUIInputText;

import flixel.addons.ui.FlxUINumericStepper;
import flixel.addons.ui.FlxUITabMenu;
import flixel.group.FlxGroup;
import flixel.ui.FlxButton;

import flixel.util.FlxSort;
import lime.media.AudioBuffer;
import lime.utils.Assets;
import openfl.events.Event;
import openfl.events.IOErrorEvent;
import openfl.media.Sound;
import openfl.net.FileReference;
import openfl.utils.Assets as OpenFlAssets;
import android.FlxVirtualPad;
import android.FlxVirtualPad.FlxDPadMode;
import android.FlxVirtualPad.FlxActionMode;

import backend.Song;
import backend.StageData;
import backend.ExtraKeysHandler;
import states.PlayState;
import states.editors.content.EditorPlayState;
import states.editors.old.content.AttachedFlxText;
import states.editors.old.content.FlxUIDropDownMenuCustom;
import states.editors.old.content.LegacyChartFormat;
import states.editors.old.content.OldEditorState;
import backend.ui.StyledButton;
import backend.ui.StyledButtonStyle;
import states.editors.old.content.OldSlider;
import states.editors.old.content.Prompt;
import states.LoadingState;

import objects.Note;
import objects.StrumNote;
import objects.NoteSplash;
import objects.HealthIcon;
import objects.AttachedSprite;
import objects.Character;
import objects.Character.CharacterFile;


#if sys
import flash.media.Sound;
#end

@:access(flixel.sound.FlxSound)
@:access(openfl.media.Sound)
class OldChartingState073 extends OldEditorState
{
	public static var noteTypeList:Array<String> = //Used for backwards compatibility with 0.1 - 0.3.2 charts, though, you should add your hardcoded custom note types here too.
	[
		'',
		'Alt Animation',
		'Hey!',
		'Hurt Note',
		'GF Sing',
		'No Animation'
	];
	public var ignoreWarnings = false;
	var curNoteTypes:Array<String> = [];
	var undos = [];
	var redos = [];
	var eventStuff:Array<Dynamic> =
	[
		['', "Nothing. Yep, that's right."],
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
		['Alt Idle Animation', "Sets a specified suffix after the idle animation name.\nYou can use this to trigger 'idle-alt' if you set\nValue 2 to -alt\n\nValue 1: Character to set (Dad, BF or GF)\nValue 2: New suffix (Leave it blank to disable)"],
		['Screen Shake', "Value 1: Camera shake\nValue 2: HUD shake\n\nEvery value works as the following example: \"1, 0.05\".\nThe first number (1) is the duration.\nThe second number (0.05) is the intensity."],
		['Change Character', "Value 1: Character to change (Dad, BF, GF)\nValue 2: New character's name"],
		['Change Scroll Speed', "Value 1: Scroll Speed Multiplier (1 is default)\nValue 2: Time it takes to change fully in seconds."],
		['Set Property', "Value 1: Variable name\nValue 2: New value"],
		['Play Sound', "Value 1: Sound file name\nValue 2: Volume (Default: 1), ranges from 0 to 1"]
	];

	var _file:FileReference;
	var _virtualpad:FlxVirtualPad;

	var UI_box:FlxUITabMenu;

	public static var goToPlayState:Bool = false;
	/**
	 * Array of notes showing when each section STARTS in STEPS
	 * Usually rounded up??
	 */
	public static var curSec:Int = 0;
	public static var lastSection:Int = 0;
	private static var lastSong:String = '';

	var bpmTxt:FlxText;
	/** 只给 bpmTxt 末尾「! N note(s) out of XK」这一行上橙色的格式，缓存一份复用 */
	var stashWarnFormat:FlxTextFormat = null;
	/** 上一次套到 bpmTxt 上的格式范围；start = -1 表示当前没在应用 */
	var stashWarnStart:Int = -1;
	var stashWarnEnd:Int = -1;
	var clear_events:FlxButton;
	var clear_notes:FlxButton;

	var camPos:FlxObject;
	var strumLine:FlxSprite;
	var quant:AttachedSprite;
	var strumLineNotes:FlxTypedGroup<StrumNote>;
	var curSong:String = 'Test';
	var amountSteps:Int = 0;
	var bullshitUI:FlxGroup;

	var highlight:FlxSprite;

	public static var GRID_SIZE:Int = 40;
	var CAM_OFFSET:Int = 360;

	// 固定字体：直接写 assets 目录路径，绕过 Paths.font() 的语言翻译层与 mods 覆盖，
	// 保证任何语言 / 模组下这两处文本都用同一套字形。
	static inline var SONG_INFO_FONT:String = 'assets/fonts/arturito-slab.ttf';
	static inline var TIP_INFO_FONT:String = 'assets/fonts/Quantico-Bold.ttf';
	/**
	 * 暂存（超范围）音符的警示配色：照搬正常箭头预设的 [主体, 白高光, 深色描边] 三通道层次，
	 *   r = 纯橙（主体）、g = 白（高光）、b = 深橙（描边）。
	 * 三通道全刷成橙会让箭头失去立体感、发平，所以只让主体是橙，其余保持正常的明暗结构。
	 */
	static inline var STASHED_NOTE_ORANGE:Int = 0xFFFFA500;
	static inline var STASHED_NOTE_HIGHLIGHT:Int = 0xFFFFFFFF;
	static inline var STASHED_NOTE_ORANGE_DARK:Int = 0xFF8C3A00;
	/** 信息文本里暂存警示行的橙色。FlxTextFormat 需要 0xRRGGBB（不带 alpha 通道），
	 *  取箭头主体色 STASHED_NOTE_ORANGE 的低 24 位，保证两处橙色一致。 */
	static inline var STASHED_INFO_ORANGE:Int = 0xFFA500;

	/**
	 * 超范围（!）音符的持久化字段名：挂到 _song（= PlayState.SONG）上，随
	 * saveLevel() / autosaveSong() 的 Json.stringify 一起落盘，重开时由 create() 读回。
	 * 暂存为空时该字段会被删除，正常谱面文件与 073 原版完全一致、零污染。
	 */
	static inline var STASH_FIELD:String = 'editorStashedNotes';

	/** 会话级兜底：PlayState / Reload JSON / 换歌可能重建 SONG 对象导致挂载字段丢失。
	 *  按歌曲名分别保存，避免切到别的歌再回来时把这份暂存冲掉（只活在本进程内）。 */
	static var sessionStashBySong:Map<String, Array<Dynamic>> = new Map<String, Array<Dynamic>>();

	// 轨道水平手动偏移量（多键时可手动左右滑动）
	var trackScrollX:Float = GRID_SIZE;     // 默认右移一格，让 grid 整体左移，不挡右侧信息栏/帮助文本
	var trackScrollTargetX:Float = GRID_SIZE; // 目标值（与默认偏移一致）
	var trackScrollMax:Float = 0;        // 最大可左移量（轨道总宽 - 屏幕宽）
	var btnTrackLeft:StyledButton;   // 自绘轨道左滑按钮
	var btnTrackRight:StyledButton;  // 自绘轨道右滑按钮

	// 触屏左右按钮按住时的轨道滚动速度（像素/秒，按 elapsed 推进，不受屏幕刷新率影响）。
	// 演变：最初每帧 GRID_SIZE*0.5 → 减半成每帧 GRID_SIZE*0.25（60fps 下 600px/s）；
	// 但「每帧固定步长」在 90/120Hz 高刷屏上会成比例变快，所以改成时间基准并再放慢。
	// 240px/s ≈ 60fps 下每帧 4px ≈ 每秒 6 格（GRID_SIZE=40）。想再快/慢只改这一个数。
	// 键鼠的 Alt+滚轮仍是 wheelDelta * GRID_SIZE、共用 lerp 系数 0.25，两者都不改动。
	var trackButtonScrollSpeed:Float = 240;

	var dummyArrow:FlxSprite;

	var curRenderedSustains:FlxTypedGroup<FlxSprite>;
	var curRenderedNotes:FlxTypedGroup<Note>;
	var curRenderedNoteType:FlxTypedGroup<FlxText>;

	var nextRenderedSustains:FlxTypedGroup<FlxSprite>;
	var nextRenderedNotes:FlxTypedGroup<Note>;

	var gridBG:FlxSprite;
	var nextGridBG:FlxSprite;

	var daquantspot = 0;
	var curEventSelected:Int = 0;
	var curUndoIndex = 0;
	var curRedoIndex = 0;

	// 保存谱面时写入的出处标记
	static var GENERATED_BY(get, never):String;
	static function get_GENERATED_BY():String
		return 'KathyEngine - Chart Editor Legacy v0.7.3';

	var _song:SwagSong;
	/*
	 * WILL BE THE CURRENT / LAST PLACED NOTE
	**/
	var curSelectedNote:Array<Dynamic> = null;

	var playbackSpeed:Float = 1;

	var vocals:FlxSound = null;
	var opponentVocals:FlxSound = null;

	var leftIcon:HealthIcon;
	var rightIcon:HealthIcon;

	var value1InputText:FlxUIInputText;
	var value2InputText:FlxUIInputText;
	var currentSongName:String;

	var zoomTxt:FlxText;

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
	var curZoom:Int = 2;

	private var blockPressWhileTypingOn:Array<FlxUIInputText> = [];
	private var blockPressWhileTypingOnStepper:Array<FlxUINumericStepper> = [];
	private var blockPressWhileScrolling:Array<FlxUIDropDownMenuCustom> = [];

	var waveformSprite:FlxSprite;
	var gridLayer:FlxTypedGroup<FlxSprite>;

	public static var quantization:Int = 16;
	public static var curQuant = 3;

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

	var text:String = "";
	public static var vortex:Bool = false;
	public var mouseQuant:Bool = false;
	override function create()
	{
		if (PlayState.SONG != null)
		{
			_song = PlayState.SONG;
			// Charts always reach us as psych_v1 (Song.parseJSON upgrades on load), but this editor
			// reads/writes lanes relative to mustHitSection like 0.7.3 did.
			LegacyChartFormat.toLegacy(_song, LegacyChartFormat.FORMAT_073);
		}
		else
		{
			Difficulty.resetList();
			_song = {
				song: 'Test',
				notes: [],
				events: [],
				bpm: 150.0,
				needsVoices: true,
				player1: 'bf',
				player2: 'dad',
				gfVersion: 'gf',
				speed: 1,
				stage: 'stage',
				offset: 0,
				mania: 3,
				format: '0.7.3'
			};
			addSection();
			PlayState.SONG = _song;
		}

		// Extra Keys：把键数档位同步到全部全局态（PlayState.SONG / Note.colArray / EK 色表 / 编辑侧档）。
		// 必须在任何 Note 构造之前完成，否则谱面音符的帧前缀会沿用上一次 State 残留的 4 键档。
		if (_song.mania == null) _song.mania = 3;
		// 读回随谱面 JSON / autosave 落盘的暂存音符（或本会话的兜底副本），必须在首次 updateGrid() 之前
		restoreStashedNotes();
		captureNoteTypeMirror(); // 刚加载的数据最干净，作为改档镜像的基准
		syncChartManiaGlobals();

		// Paths.clearMemory();

		#if DISCORD_ALLOWED
		// Updating Discord Rich Presence
		DiscordClient.changePresence("Chart Editor", StringTools.replace(_song.song, '-', ' '));
		#end

		vortex = FlxG.save.data.chart_vortex;
		ignoreWarnings = FlxG.save.data.ignoreWarnings;
		var bg:FlxSprite = new FlxSprite().loadGraphic(Paths.image('menuDesat'));
		bg.antialiasing = ClientPrefs.data.antialiasing;
		bg.scrollFactor.set();
		bg.color = 0xFF222222;
		add(bg);

		gridLayer = new FlxTypedGroup<FlxSprite>();
		add(gridLayer);

		waveformSprite = new FlxSprite(GRID_SIZE, 0).makeGraphic(1, 1, 0x00FFFFFF);
		add(waveformSprite);

		var eventIcon:FlxSprite = new FlxSprite(-GRID_SIZE - 5, -90).loadGraphic(Paths.image('editors/eventIcon'));
		eventIcon.antialiasing = ClientPrefs.data.antialiasing;
		leftIcon = new HealthIcon('bf');
		rightIcon = new HealthIcon('dad');
		eventIcon.scrollFactor.set(1, 1);
		leftIcon.scrollFactor.set(1, 1);
		rightIcon.scrollFactor.set(1, 1);

		eventIcon.setGraphicSize(30, 30);
		leftIcon.setGraphicSize(0, 45);
		rightIcon.setGraphicSize(0, 45);

		add(eventIcon);
		add(leftIcon);
		add(rightIcon);

		// Extra Keys：左右图标贴到对应轨区（4键 = 原位置）
		var gridLaneMidPoint:Float = (GRID_SIZE * (_song.mania + 1)) / 2;
		leftIcon.setPosition((GRID_SIZE + gridLaneMidPoint) - (leftIcon.width / 2), -100);
		rightIcon.setPosition(leftIcon.x + (GRID_SIZE * (_song.mania + 1)), -100);

		curRenderedSustains = new FlxTypedGroup<FlxSprite>();
		curRenderedNotes = new FlxTypedGroup<Note>();
		curRenderedNoteType = new FlxTypedGroup<FlxText>();
		stashedRenderedNotes = new FlxTypedGroup<Note>();

		nextRenderedSustains = new FlxTypedGroup<FlxSprite>();
		nextRenderedNotes = new FlxTypedGroup<Note>();

		FlxG.mouse.visible = true;
		//FlxG.save.bind('funkin', CoolUtil.getSavePath());

		//addSection();

		// sections = _song.notes;

		updateJsonData();
		currentSongName = Paths.formatToSongPath(_song.song);
		loadSong();

		bpmTxt = new FlxText(1000, 50, 0, "", 16);
		// 歌曲信息（时间 / Section / Beat / Step / Snap / Zoom 多行实时刷新）固定用 arturito-slab
		bpmTxt.setFormat(SONG_INFO_FONT, 16, FlxColor.WHITE, LEFT);
		bpmTxt.scrollFactor.set();
		add(bpmTxt);

		strumLine = new FlxSprite(0, 50).makeGraphic(Std.int(GRID_SIZE * ((_song.mania * 2) + 3)), 4);
		add(strumLine);

		quant = new AttachedSprite('chart_quant','chart_quant');
		quant.animation.addByPrefix('q','chart_quant',0,false);
		quant.animation.play('q', true, false, 0);
		quant.sprTracker = strumLine;
		quant.xAdd = -32;
		quant.yAdd = 8;
		add(quant);

		// 先建好箭头组，再让 reloadGridLayer() 统一走 rebuildStrumLineNotes()。
		// 旧写法在 reloadGridLayer() 之后才创建箭头组（首次重建被 null 判断跳过），
		// 于是「创建」和「改 mania 时重建」是两份重复代码，档位同步只加在了后者。
		strumLineNotes = new FlxTypedGroup<StrumNote>();
		add(strumLineNotes);

		reloadGridLayer();
		Conductor.bpm = _song.bpm;
		Conductor.mapBPMChanges(_song);
		if(curSec >= _song.notes.length) curSec = _song.notes.length - 1;
		dbgTypeLog('CREATE 进入编辑器', 'mania=' + _song.mania + ' format=' + _song.format);

		camPos = new FlxObject(0, 0, 1, 1);
		camPos.setPosition(strumLine.x + CAM_OFFSET, strumLine.y);

		dummyArrow = new FlxSprite().makeGraphic(GRID_SIZE, GRID_SIZE);
		dummyArrow.antialiasing = ClientPrefs.data.antialiasing;
		add(dummyArrow);

		var tabs = [
			{name: "Song", label: 'Song'},
			{name: "Section", label: 'Section'},
			{name: "Note", label: 'Note'},
			{name: "Events", label: 'Events'},
			{name: "Charting", label: 'Charting'},
			{name: "Data", label: 'Data'},
		];

		UI_box = new FlxUITabMenu(null, tabs, true);

		// 对齐 Minty 新版：相对定位贴右边缘，避免移动端与轨道重叠
		UI_box.resize(300, 400);
		UI_box.x = FlxG.width - UI_box.width - 30;
		UI_box.y = 25;
		UI_box.scrollFactor.set();

		// 进度信息（时间/section/beat/step）放到 box 左侧，避免被 box 遮挡
		bpmTxt.x = UI_box.x - 210;
		bpmTxt.y = 50;

		text =
		"W/S or Mouse Wheel - Change Conductor's strum time
		A/D - Go to the previous/next section
		Left/Right - Change Snap
		Up/Down - Change Conductor's Strum Time with Snapping
		" +
		#if FLX_PITCH
		"Left Bracket / Right Bracket - Change Song Playback Rate (SHIFT to go Faster)
		ALT + Left Bracket / Right Bracket - Reset Song Playback Rate
		" +
		#end
		"Hold Shift to move 4x faster
		Hold Control and click on an arrow to select it
		Z/X - Zoom in/out
		\nEsc - Playtest inside Chart Editor
		Backspace - Go back to Editor Menu
		Enter - Play your chart
		Q/E - Decrease/Increase Note Sustain Length
		Space - Stop/Resume song
		Alt + Wheel / < > - Scroll tracks left/right" + (controls.mobileC ? "\nTouch Pad: use on-screen buttons (B button exits to Editor Menu)" : "");

		var tipTextArray:Array<String> = text.split('\n');
		for (i in 0...tipTextArray.length) {
			var tipText:FlxText = new FlxText(UI_box.x - 210, UI_box.y + UI_box.height + 8, 0, tipTextArray[i], 16);
			tipText.y += i * 16;
			// 下方操作提示固定用 Quantico-Bold
			tipText.setFormat(TIP_INFO_FONT, 14, FlxColor.WHITE, LEFT/*, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK*/);
			//tipText.borderSize = 2;
			tipText.scrollFactor.set();
			add(tipText);
		}
		add(UI_box);

		// 轨道左右滑动按钮在 create() 末尾统一创建（保证绘制层级在轨道内容之上）

		addSongUI();
		addSectionUI();
		addNoteUI();
		addEventsUI();
		addChartingUI();
		addDataUI();
		updateHeads();
		updateWaveform();
		//UI_box.selected_tab = 4;

		add(curRenderedSustains);
		add(curRenderedNotes);
		add(stashedRenderedNotes);
		add(curRenderedNoteType);
		add(nextRenderedSustains);
		add(nextRenderedNotes);

		// === 轨道左右滑动按钮 ===
		// 用的是 backend.ui.StyledButton（全项目通用的自绘按钮，非制谱器专属，也不依赖 FlxButton）。
		// 默认 flixelClassic()：复刻 FlxButton 自带皮肤的灰阶方角观感，和本屏 Save / Reload 等
		// FlxButton 是同一套视觉语言。蓝色玻璃 glassBlue() 仍保留，运行时调
		// setTrackButtonTheme(false) 即可整组切回；两套都是纯矢量自绘，无贴图依赖。
		// 放在所有轨道内容之后 add：避免被网格 / 音符盖住。
		var btnLeftX:Float = UI_box.x - 46;
		var btnLeftY:Float = UI_box.y + UI_box.height - 88;
		var btnRightX:Float = UI_box.x - 46;
		var btnRightY:Float = UI_box.y + UI_box.height - 44;

		var trackBtnStyle:StyledButtonStyle = StyledButtonStyle.flixelClassic();
		trackBtnStyle.size = 44;

		btnTrackLeft = new StyledButton(btnLeftX, btnLeftY, StyledButton.LEFT, trackBtnStyle);
		btnTrackLeft.hitPadding = 4; // 触屏扩大命中区，与下方 suppressMouse 的 ±4 判定保持一致
		add(btnTrackLeft);
		btnTrackRight = new StyledButton(btnRightX, btnRightY, StyledButton.RIGHT, trackBtnStyle);
		btnTrackRight.hitPadding = 4;
		add(btnTrackRight);

		updateTrackButtonsVisibility();

		if(lastSong != currentSongName) {
			changeSection();
		}
		lastSong = currentSongName;

		updateGrid();
		super.create();
	}

	var check_mute_inst:FlxUICheckBox = null;
	var check_mute_vocals:FlxUICheckBox = null;
	var check_mute_vocals_opponent:FlxUICheckBox = null;
	var check_vortex:FlxUICheckBox = null;
	var check_warnings:FlxUICheckBox = null;
	var playSoundBf:FlxUICheckBox = null;
	var playSoundDad:FlxUICheckBox = null;
	var UI_songTitle:FlxUIInputText;
	var stageDropDown:FlxUIDropDownMenuCustom;
	#if FLX_PITCH
	var sliderRate:OldSlider;
	#end
	function addSongUI():Void
	{
		UI_songTitle = new FlxUIInputText(10, 10, 70, _song.song, 8);
		blockPressWhileTypingOn.push(UI_songTitle);

		var check_voices = new FlxUICheckBox(10, 25, null, null, "Has voice track", 100);
		check_voices.checked = _song.needsVoices;
		// _song.needsVoices = check_voices.checked;
		check_voices.callback = function()
		{
			_song.needsVoices = check_voices.checked;
			//trace('CHECKED!');
		};

		var saveButton:FlxButton = new FlxButton(110, 8, "Save", function()
		{
			// 降档期间有暂存音符时先确认：数据会随谱面 / autosave 一起保存，只是当前档位装不下
			confirmChartMania(saveLevel);
		});

		var reloadSong:FlxButton = new FlxButton(saveButton.x + 90, saveButton.y, "Reload Audio", function()
		{
			currentSongName = Paths.formatToSongPath(UI_songTitle.text);
			updateJsonData();
			loadSong();
			updateWaveform();
		});

		var reloadSongJson:FlxButton = new FlxButton(reloadSong.x, saveButton.y + 30, "Reload JSON", function()
		{
			openSubState(new Prompt('This action will clear current progress.\n\nProceed?', 0, function() {
				loadJson(_song.song.toLowerCase());
			},
			null, ignoreWarnings));
		});

		var loadAutosaveBtn:FlxButton = new FlxButton(reloadSongJson.x, reloadSongJson.y + 30, 'Load Autosave', function()
		{
			PlayState.SONG = Song.parseJSON(FlxG.save.data.autosave);
			MusicBeatState.resetState();
		});

		var loadEventJson:FlxButton = new FlxButton(loadAutosaveBtn.x, loadAutosaveBtn.y + 30, 'Load Events', function()
		{

			var songName:String = Paths.formatToSongPath(_song.song);
			var file:String = Paths.json(songName + '/events');
			#if sys
			if (#if MODS_ALLOWED FileSystem.exists(Paths.modsJson(songName + '/events')) || #end FileSystem.exists(file))
			#else
			if (OpenFlAssets.exists(file))
			#end
			{
				clearEvents();
				var events:SwagSong = Song.loadFromJson('events', songName);
				_song.events = events.events;
				changeSection(curSec);
			}
		});

		var saveEvents:FlxButton = new FlxButton(110, reloadSongJson.y, 'Save Events', function ()
		{
			saveEvents();
		});

		clear_events = new FlxButton(10, 310, 'Clear events', function()
			{
				openSubState(new Prompt('This action will clear current progress.\n\nProceed?', 0, clearEvents, null,ignoreWarnings));
			});
		clear_events.color = FlxColor.RED;
		clear_events.label.color = FlxColor.WHITE;

		clear_notes = new FlxButton(10, clear_events.y + 30, 'Clear notes', function()
			{
				openSubState(new Prompt('This action will clear current progress.\n\nProceed?', 0, function(){for (sec in 0..._song.notes.length) {
					_song.notes[sec].sectionNotes = [];
				}
				clearStashedNotes(); // 清空音符时一并清暂存（含落盘字段），避免改档后幽灵音符复活
				updateGrid();
			}, null,ignoreWarnings));

			});
		clear_notes.color = FlxColor.RED;
		clear_notes.label.color = FlxColor.WHITE;

		var stepperBPM:FlxUINumericStepper = new FlxUINumericStepper(10, 75, 1, 1, 1, 400, 3);
		stepperBPM.value = Conductor.bpm;
		stepperBPM.name = 'song_bpm';
		blockPressWhileTypingOnStepper.push(stepperBPM);

		// Song Offset（毫秒）：谱面时间对齐偏移，写入 _song.offset 并同步到 Conductor.offset
		// 参数顺序：(x, y, stepSize, defaultValue, min, max, decimals)。
		// 旧写法传成 (10, -1000, 1000, 0, 100)，min=1000 / max=0 / decimals=100，
		// value setter 会把任何值 clamp 成 0 —— 等于这个 stepper 无效，还会把 offset 悄悄写成 0。
		var stepperOffset:FlxUINumericStepper = new FlxUINumericStepper(stepperBPM.x + 100, 75, 10, 0, -1000, 1000, 0);
		// offset 在 SwagSong 里是 Float，静态平台不能直接与 null 比；先用 Dynamic 接住再兜底，兼容旧谱面缺该字段
		var chartOffset:Dynamic = _song.offset;
		stepperOffset.value = (chartOffset == null) ? 0 : chartOffset;
		stepperOffset.name = 'song_offset';
		blockPressWhileTypingOnStepper.push(stepperOffset);
		Conductor.offset = stepperOffset.value;

		var stepperSpeed:FlxUINumericStepper = new FlxUINumericStepper(10, stepperBPM.y + 35, 0.1, 1, 0.1, 10, 2);
		stepperSpeed.value = _song.speed;
		stepperSpeed.name = 'song_speed';
		blockPressWhileTypingOnStepper.push(stepperSpeed);

		// Extra Keys：键数档位（mania，4 键 = 3；范围取自 extrakeys.json）
		// 与上方 Song Offset 同一列、下一行：x/y 都跟随 stepperOffset，UI 两列严格对齐
		ExtraKeysHandler.ensure();
		maniaStepper = new FlxUINumericStepper(stepperOffset.x, stepperOffset.y + 35, 1, 3, ExtraKeysHandler.instance.data.minKeys, ExtraKeysHandler.instance.data.maxKeys, 1);
		maniaStepper.value = _song.mania;
		maniaStepper.name = 'song_mania';
		blockPressWhileTypingOnStepper.push(maniaStepper);
		#if MODS_ALLOWED
		var directories:Array<String> = [Paths.mods('characters/'), Paths.mods(Mods.currentModDirectory + '/characters/'), Paths.getSharedPath('characters/')];
		for(mod in Mods.getGlobalMods())
			directories.push(Paths.mods(mod + '/characters/'));
		#else
		var directories:Array<String> = [Paths.getSharedPath('characters/')];
		#end

		var tempArray:Array<String> = [];
		var characters:Array<String> = Mods.mergeAllTextsNamed('data/characterList.txt', Paths.getSharedPath());
		for (character in characters)
		{
			if(character.trim().length > 0)
				tempArray.push(character);
		}

		#if MODS_ALLOWED
		for (i in 0...directories.length) {
			var directory:String = directories[i];
			if(FileSystem.exists(directory)) {
				for (file in FileSystem.readDirectory(directory)) {
					var path = haxe.io.Path.join([directory, file]);
					if (!FileSystem.isDirectory(path) && file.endsWith('.json')) {
						var charToCheck:String = file.substr(0, file.length - 5);
						if(charToCheck.trim().length > 0 && !charToCheck.endsWith('-dead') && !tempArray.contains(charToCheck)) {
							tempArray.push(charToCheck);
							characters.push(charToCheck);
						}
					}
				}
			}
		}
		#end
		tempArray = [];

		var player1DropDown = new FlxUIDropDownMenuCustom(10, stepperSpeed.y + 45, FlxUIDropDownMenuCustom.makeStrIdLabelArray(characters, true), function(character:String)
		{
			_song.player1 = characters[Std.parseInt(character)];
			updateJsonData();
			updateHeads();
		});
		player1DropDown.selectedLabel = _song.player1;
		blockPressWhileScrolling.push(player1DropDown);

		var gfVersionDropDown = new FlxUIDropDownMenuCustom(player1DropDown.x, player1DropDown.y + 40, FlxUIDropDownMenuCustom.makeStrIdLabelArray(characters, true), function(character:String)
		{
			_song.gfVersion = characters[Std.parseInt(character)];
			updateJsonData();
			updateHeads();
		});
		gfVersionDropDown.selectedLabel = _song.gfVersion;
		blockPressWhileScrolling.push(gfVersionDropDown);

		var player2DropDown = new FlxUIDropDownMenuCustom(player1DropDown.x, gfVersionDropDown.y + 40, FlxUIDropDownMenuCustom.makeStrIdLabelArray(characters, true), function(character:String)
		{
			_song.player2 = characters[Std.parseInt(character)];
			updateJsonData();
			updateHeads();
		});
		player2DropDown.selectedLabel = _song.player2;
		blockPressWhileScrolling.push(player2DropDown);

		#if MODS_ALLOWED
		var directories:Array<String> = [Paths.mods('stages/'), Paths.mods(Mods.currentModDirectory + '/stages/'), Paths.getSharedPath('stages/')];
		for(mod in Mods.getGlobalMods())
			directories.push(Paths.mods(mod + '/stages/'));
		#else
		var directories:Array<String> = [Paths.getSharedPath('stages/')];
		#end

		var stageFile:Array<String> = Mods.mergeAllTextsNamed('data/stageList.txt', Paths.getSharedPath());
		var stages:Array<String> = [];
		for (stage in stageFile) {
			if(stage.trim().length > 0) {
				stages.push(stage);
			}
			tempArray.push(stage);
		}
		#if MODS_ALLOWED
		for (i in 0...directories.length) {
			var directory:String = directories[i];
			if(FileSystem.exists(directory)) {
				for (file in FileSystem.readDirectory(directory)) {
					var path = haxe.io.Path.join([directory, file]);
					if (!FileSystem.isDirectory(path) && file.endsWith('.json')) {
						var stageToCheck:String = file.substr(0, file.length - 5);
						if(stageToCheck.trim().length > 0 && !tempArray.contains(stageToCheck)) {
							tempArray.push(stageToCheck);
							stages.push(stageToCheck);
						}
					}
				}
			}
		}
		#end

		if(stages.length < 1) stages.push('stage');

		stageDropDown = new FlxUIDropDownMenuCustom(player1DropDown.x + 140, player1DropDown.y, FlxUIDropDownMenuCustom.makeStrIdLabelArray(stages, true), function(character:String)
		{
			_song.stage = stages[Std.parseInt(character)];
		});
		stageDropDown.selectedLabel = _song.stage;
		blockPressWhileScrolling.push(stageDropDown);

		var tab_group_song = new FlxUI(null, UI_box);
		tab_group_song.name = "Song";
		tab_group_song.add(UI_songTitle);

		tab_group_song.add(check_voices);
		tab_group_song.add(clear_events);
		tab_group_song.add(clear_notes);
		tab_group_song.add(saveButton);
		tab_group_song.add(saveEvents);
		tab_group_song.add(reloadSong);
		tab_group_song.add(reloadSongJson);
		tab_group_song.add(loadAutosaveBtn);
		tab_group_song.add(loadEventJson);
		tab_group_song.add(stepperBPM);
		tab_group_song.add(stepperSpeed);
		tab_group_song.add(stepperOffset);
		tab_group_song.add(new FlxText(stepperBPM.x, stepperBPM.y - 15, 0, 'Song BPM:'));
		tab_group_song.add(new FlxText(stepperOffset.x, stepperOffset.y - 15, 0, 'Song Offset:'));
		tab_group_song.add(new FlxText(stepperSpeed.x, stepperSpeed.y - 15, 0, 'Song Speed:'));
		// 动态标签：stepper 值是 0-based 档位索引，这里换算成实际每侧键数（5 -> 6K）
		maniaKeysLabel = new FlxText(maniaStepper.x, maniaStepper.y - 15, 0, '');
		refreshManiaKeysLabel();
		tab_group_song.add(maniaKeysLabel);
		tab_group_song.add(maniaStepper);
		tab_group_song.add(new FlxText(player2DropDown.x, player2DropDown.y - 15, 0, 'Opponent:'));
		tab_group_song.add(new FlxText(gfVersionDropDown.x, gfVersionDropDown.y - 15, 0, 'Girlfriend:'));
		tab_group_song.add(new FlxText(player1DropDown.x, player1DropDown.y - 15, 0, 'Boyfriend:'));
		tab_group_song.add(new FlxText(stageDropDown.x, stageDropDown.y - 15, 0, 'Stage:'));
		tab_group_song.add(player2DropDown);
		tab_group_song.add(gfVersionDropDown);
		tab_group_song.add(player1DropDown);
		tab_group_song.add(stageDropDown);

		UI_box.addGroup(tab_group_song);

		initPsychCamera().follow(camPos, LOCKON, 999);
	}

	var stepperBeats:FlxUINumericStepper;
	var check_mustHitSection:FlxUICheckBox;
	var check_gfSection:FlxUICheckBox;
	var check_changeBPM:FlxUICheckBox;
	var stepperSectionBPM:FlxUINumericStepper;
	var check_altAnim:FlxUICheckBox;

	var sectionToCopy:Int = 0;
	var notesCopied:Array<Dynamic>;

	function addSectionUI():Void
	{
		var tab_group_section = new FlxUI(null, UI_box);
		tab_group_section.name = 'Section';

		check_mustHitSection = new FlxUICheckBox(10, 15, null, null, "Must hit section", 100);
		check_mustHitSection.name = 'check_mustHit';
		check_mustHitSection.checked = _song.notes[curSec].mustHitSection;

		check_gfSection = new FlxUICheckBox(10, check_mustHitSection.y + 22, null, null, "GF section", 100);
		check_gfSection.name = 'check_gf';
		check_gfSection.checked = _song.notes[curSec].gfSection;
		// _song.needsVoices = check_mustHit.checked;

		check_altAnim = new FlxUICheckBox(check_gfSection.x + 120, check_gfSection.y, null, null, "Alt Animation", 100);
		check_altAnim.checked = _song.notes[curSec].altAnim;

		stepperBeats = new FlxUINumericStepper(10, 100, 1, 4, 1, 7, 2);
		stepperBeats.value = getSectionBeats();
		stepperBeats.name = 'section_beats';
		blockPressWhileTypingOnStepper.push(stepperBeats);
		check_altAnim.name = 'check_altAnim';

		check_changeBPM = new FlxUICheckBox(10, stepperBeats.y + 30, null, null, 'Change BPM', 100);
		check_changeBPM.checked = _song.notes[curSec].changeBPM;
		check_changeBPM.name = 'check_changeBPM';

		stepperSectionBPM = new FlxUINumericStepper(10, check_changeBPM.y + 20, 1, Conductor.bpm, 0, 999, 1);
		if(check_changeBPM.checked) {
			stepperSectionBPM.value = _song.notes[curSec].bpm;
		} else {
			stepperSectionBPM.value = Conductor.bpm;
		}
		stepperSectionBPM.name = 'section_bpm';
		blockPressWhileTypingOnStepper.push(stepperSectionBPM);

		var check_eventsSec:FlxUICheckBox = null;
		var check_notesSec:FlxUICheckBox = null;
		var copyButton:FlxButton = new FlxButton(10, 190, "Copy Section", function()
		{
			notesCopied = [];
			sectionToCopy = curSec;
			for (i in 0..._song.notes[curSec].sectionNotes.length)
			{
				var note:Array<Dynamic> = _song.notes[curSec].sectionNotes[i];
				notesCopied.push(note);
			}

			var startThing:Float = sectionStartTime();
			var endThing:Float = sectionStartTime(1);
			for (event in _song.events)
			{
				var strumTime:Float = event[0];
				if(endThing > event[0] && event[0] >= startThing)
				{
					var copiedEventArray:Array<Dynamic> = [];
					for (i in 0...event[1].length)
					{
						var eventToPush:Array<Dynamic> = event[1][i];
						copiedEventArray.push([eventToPush[0], eventToPush[1], eventToPush[2]]);
					}
					notesCopied.push([strumTime, -1, copiedEventArray]);
				}
			}
		});

		var pasteButton:FlxButton = new FlxButton(copyButton.x + 100, copyButton.y, "Paste Section", function()
		{
			if(notesCopied == null || notesCopied.length < 1)
			{
				return;
			}

			var addToTime:Float = Conductor.stepCrochet * (getSectionBeats() * 4 * (curSec - sectionToCopy));
			//trace('Time to add: ' + addToTime);

			for (note in notesCopied)
			{
				var copiedNote:Array<Dynamic> = [];
				var newStrumTime:Float = note[0] + addToTime;
				if(note[1] < 0)
				{
					if(check_eventsSec.checked)
					{
						var copiedEventArray:Array<Dynamic> = [];
						for (i in 0...note[2].length)
						{
							var eventToPush:Array<Dynamic> = note[2][i];
							copiedEventArray.push([eventToPush[0], eventToPush[1], eventToPush[2]]);
						}
						_song.events.push([newStrumTime, copiedEventArray]);
					}
				}
				else
				{
					if(check_notesSec.checked)
					{
						if(note[4] != null)
							copiedNote = [newStrumTime, note[1], note[2], note[3], note[4]];
						else
							copiedNote = [newStrumTime, note[1], note[2], note[3]];

						_song.notes[curSec].sectionNotes.push(copiedNote);
					}
				}
			}
			updateGrid();
		});

		var clearSectionButton:FlxButton = new FlxButton(pasteButton.x + 100, pasteButton.y, "Clear", function()
		{
			if(check_notesSec.checked)
			{
				_song.notes[curSec].sectionNotes = [];
				// 只清掉属于本小节的暂存音符，其它小节的不受影响
				stashedNotes = stashedNotes.filter(function(s) return s.sec != curSec);
				syncStashedNotes();
			}

			if(check_eventsSec.checked)
			{
				var i:Int = _song.events.length - 1;
				var startThing:Float = sectionStartTime();
				var endThing:Float = sectionStartTime(1);
				while(i > -1) {
					var event:Array<Dynamic> = _song.events[i];
					if(event != null && endThing > event[0] && event[0] >= startThing)
					{
						_song.events.remove(event);
					}
					--i;
				}
			}
			updateGrid();
			updateNoteUI();
		});
		clearSectionButton.color = FlxColor.RED;
		clearSectionButton.label.color = FlxColor.WHITE;
		
		check_notesSec = new FlxUICheckBox(10, clearSectionButton.y + 25, null, null, "Notes", 100);
		check_notesSec.checked = true;
		check_eventsSec = new FlxUICheckBox(check_notesSec.x + 100, check_notesSec.y, null, null, "Events", 100);
		check_eventsSec.checked = true;

		var swapSection:FlxButton = new FlxButton(10, check_notesSec.y + 40, "Swap section", function()
		{
			for (i in 0..._song.notes[curSec].sectionNotes.length)
			{
				var note:Array<Dynamic> = _song.notes[curSec].sectionNotes[i];
				// Extra Keys：镜像翻转（0.7.3 relative lane 语义）
				note[1] = (note[1] + (_song.mania + 1)) % ((_song.mania + 1) * 2);
				_song.notes[curSec].sectionNotes[i] = note;
			}
			updateGrid();
		});

		var stepperCopy:FlxUINumericStepper = null;
		var copyLastButton:FlxButton = new FlxButton(10, swapSection.y + 30, "Copy last section", function()
		{
			var value:Int = Std.int(stepperCopy.value);
			if(value == 0) return;

			var daSec = FlxMath.maxInt(curSec, value);

			for (note in _song.notes[daSec - value].sectionNotes)
			{
				var strum = note[0] + Conductor.stepCrochet * (getSectionBeats(daSec) * 4 * value);

				var copiedNote:Array<Dynamic> = [strum, note[1], note[2], note[3]];
				_song.notes[daSec].sectionNotes.push(copiedNote);
			}

			var startThing:Float = sectionStartTime(-value);
			var endThing:Float = sectionStartTime(-value + 1);
			for (event in _song.events)
			{
				var strumTime:Float = event[0];
				if(endThing > event[0] && event[0] >= startThing)
				{
					strumTime += Conductor.stepCrochet * (getSectionBeats(daSec) * 4 * value);
					var copiedEventArray:Array<Dynamic> = [];
					for (i in 0...event[1].length)
					{
						var eventToPush:Array<Dynamic> = event[1][i];
						copiedEventArray.push([eventToPush[0], eventToPush[1], eventToPush[2]]);
					}
					_song.events.push([strumTime, copiedEventArray]);
				}
			}
			updateGrid();
		});
		copyLastButton.setGraphicSize(80, 30);
		copyLastButton.updateHitbox();
		
		stepperCopy = new FlxUINumericStepper(copyLastButton.x + 100, copyLastButton.y, 1, 1, -999, 999, 0);
		blockPressWhileTypingOnStepper.push(stepperCopy);

		var duetButton:FlxButton = new FlxButton(10, copyLastButton.y + 45, "Duet Notes", function()
		{
			var duetNotes:Array<Array<Dynamic>> = [];
			for (note in _song.notes[curSec].sectionNotes)
			{
				var boob = note[1];
				if (boob > _song.mania){
					boob -= (_song.mania + 1);
				}else{
					boob += (_song.mania + 1);
				}

				var copiedNote:Array<Dynamic> = [note[0], boob, note[2], note[3]];
				duetNotes.push(copiedNote);
			}

			for (i in duetNotes){
			_song.notes[curSec].sectionNotes.push(i);

			}

			updateGrid();
		});
		var mirrorButton:FlxButton = new FlxButton(duetButton.x + 100, duetButton.y, "Mirror Notes", function()
		{
			var duetNotes:Array<Array<Dynamic>> = [];
			for (note in _song.notes[curSec].sectionNotes)
			{
				// Extra Keys：镜像 = 每侧内翻转（mania - boob），再跨侧偏移
				var boob = note[1] % (_song.mania + 1);
				boob = _song.mania - boob;
				if (note[1] > _song.mania) boob += (_song.mania + 1);

				note[1] = boob;
				var copiedNote:Array<Dynamic> = [note[0], boob, note[2], note[3]];
				//duetNotes.push(copiedNote);
			}

			for (i in duetNotes){
			//_song.notes[curSec].sectionNotes.push(i);

			}

			updateGrid();
		});

		tab_group_section.add(new FlxText(stepperBeats.x, stepperBeats.y - 15, 0, 'Beats per Section:'));
		tab_group_section.add(stepperBeats);
		tab_group_section.add(stepperSectionBPM);
		tab_group_section.add(check_mustHitSection);
		tab_group_section.add(check_gfSection);
		tab_group_section.add(check_altAnim);
		tab_group_section.add(check_changeBPM);
		tab_group_section.add(copyButton);
		tab_group_section.add(pasteButton);
		tab_group_section.add(clearSectionButton);
		tab_group_section.add(check_notesSec);
		tab_group_section.add(check_eventsSec);
		tab_group_section.add(swapSection);
		tab_group_section.add(stepperCopy);
		tab_group_section.add(copyLastButton);
		tab_group_section.add(duetButton);
		tab_group_section.add(mirrorButton);

		UI_box.addGroup(tab_group_section);
	}

	var stepperSusLength:FlxUINumericStepper;
	var strumTimeInputText:FlxUIInputText; //I wanted to use a stepper but we can't scale these as far as i know :(
	var noteTypeDropDown:FlxUIDropDownMenuCustom;
	var currentType:Int = 0;

	function addNoteUI():Void
	{
		var tab_group_note = new FlxUI(null, UI_box);
		tab_group_note.name = 'Note';

		stepperSusLength = new FlxUINumericStepper(10, 25, Conductor.stepCrochet / 2, 0, 0, Conductor.stepCrochet * 64);
		stepperSusLength.value = 0;
		stepperSusLength.name = 'note_susLength';
		blockPressWhileTypingOnStepper.push(stepperSusLength);

		strumTimeInputText = new FlxUIInputText(10, 65, 180, "0");
		tab_group_note.add(strumTimeInputText);
		blockPressWhileTypingOn.push(strumTimeInputText);

		var key:Int = 0;
		while (key < noteTypeList.length) {
			curNoteTypes.push(noteTypeList[key]);
			key++;
		}

		#if sys
		var foldersToCheck:Array<String> = Mods.directoriesWithFile(Paths.getSharedPath(), 'custom_notetypes/');
		for (folder in foldersToCheck)
			for (file in FileSystem.readDirectory(folder))
			{
				var fileName:String = file.toLowerCase().trim();
				var wordLen:Int = 4; //length of word ".lua" and ".txt";
				if((#if LUA_ALLOWED fileName.endsWith('.lua') || #end
					#if HSCRIPT_ALLOWED (fileName.endsWith('.hx') && (wordLen = 3) == 3) || #end
					fileName.endsWith('.txt')) && fileName != 'readme.txt')
				{
					var fileToCheck:String = file.substr(0, file.length - wordLen);
					if(!curNoteTypes.contains(fileToCheck))
					{
						curNoteTypes.push(fileToCheck);
						key++;
					}
				}
			}
		#end

		// Also scan per-song data folder for custom_notetypes
		var perSongNoteTypeNames:Array<String> = [];
		if(currentSongName != null && currentSongName.length > 0)
		{
			#if MODS_ALLOWED
			var folders:Array<String> = Mods.directoriesWithFile(Paths.getSharedPath(), 'data/' + currentSongName + '/');
			for (folder in folders)
			{
				var perSongTypesPath:String = folder + 'custom_notetypes/';
				if(FileSystem.exists(perSongTypesPath))
				{
					for (file in FileSystem.readDirectory(perSongTypesPath))
					{
						var pFileName:String = file.toLowerCase().trim();
						var pWordLen:Int = 4;
						if((#if LUA_ALLOWED pFileName.endsWith('.lua') || #end
							#if HSCRIPT_ALLOWED (pFileName.endsWith('.hx') && (pWordLen = 3) == 3) || #end
							pFileName.endsWith('.txt')) && pFileName != 'readme.txt')
						{
							var pFileToCheck:String = file.substr(0, file.length - pWordLen);
							if(!curNoteTypes.contains(pFileToCheck))
							{
								curNoteTypes.push(pFileToCheck);
								perSongNoteTypeNames.push(pFileToCheck);
							}
						}
					}
				}
			}
			#end
		}

		var displayNameList:Array<String> = curNoteTypes.copy();
		for (i in 1...displayNameList.length) {
			displayNameList[i] = i + '. ' + displayNameList[i];
		}

		noteTypeDropDown = new FlxUIDropDownMenuCustom(10, 105, FlxUIDropDownMenuCustom.makeStrIdLabelArray(displayNameList, true), function(character:String)
		{
			currentType = Std.parseInt(character);
			if(curSelectedNote != null && curSelectedNote[1] > -1) {
				curSelectedNote[3] = curNoteTypes[currentType];
				mirrorSetNoteType(curSelectedNote, curNoteTypes[currentType]);
				updateGrid();
			}
		});
		blockPressWhileScrolling.push(noteTypeDropDown);

		// Mark per-song note types
		for (idx in 0...curNoteTypes.length)
		{
			if(perSongNoteTypeNames.contains(curNoteTypes[idx]))
				noteTypeDropDown.markItem(idx);
		}

		tab_group_note.add(new FlxText(10, 10, 0, 'Sustain length:'));
		tab_group_note.add(new FlxText(10, 50, 0, 'Strum time (in miliseconds):'));
		tab_group_note.add(new FlxText(10, 90, 0, 'Note type:'));
		tab_group_note.add(stepperSusLength);
		tab_group_note.add(strumTimeInputText);
		tab_group_note.add(noteTypeDropDown);

		UI_box.addGroup(tab_group_note);
	}

	var eventDropDown:FlxUIDropDownMenuCustom;
	var descText:FlxText;
	var selectedEventText:FlxText;
	function addEventsUI():Void
	{
		var tab_group_event = new FlxUI(null, UI_box);
		tab_group_event.name = 'Events';

		#if LUA_ALLOWED
		var eventPushedMap:Map<String, Bool> = new Map<String, Bool>();
		var directories:Array<String> = [];

		#if MODS_ALLOWED
		directories.push(Paths.mods('custom_events/'));
		directories.push(Paths.mods(Mods.currentModDirectory + '/custom_events/'));
		for(mod in Mods.getGlobalMods())
			directories.push(Paths.mods(mod + '/custom_events/'));
		#end

		for (i in 0...directories.length) {
			var directory:String =  directories[i];
			if(FileSystem.exists(directory)) {
				for (file in FileSystem.readDirectory(directory)) {
					var path = haxe.io.Path.join([directory, file]);
					if (!FileSystem.isDirectory(path) && file != 'readme.txt' && file.endsWith('.txt')) {
						var fileToCheck:String = file.substr(0, file.length - 4);
						if(!eventPushedMap.exists(fileToCheck)) {
							eventPushedMap.set(fileToCheck, true);
							eventStuff.push([fileToCheck, File.getContent(path)]);
						}
					}
				}
			}
		}
		eventPushedMap.clear();
		eventPushedMap = null;
		#end

		// Also scan per-song data folder for custom_events
		var perSongEventNames:Array<String> = [];
		if(currentSongName != null && currentSongName.length > 0)
		{
			#if MODS_ALLOWED
			var eventFolders:Array<String> = Mods.directoriesWithFile(Paths.getSharedPath(), 'data/' + currentSongName + '/');
			for (folder in eventFolders)
			{
				var perSongEventsPath:String = folder + 'custom_events/';
				if(FileSystem.exists(perSongEventsPath))
				{
					for (file in FileSystem.readDirectory(perSongEventsPath))
					{
						var path = haxe.io.Path.join([perSongEventsPath, file]);
						if (!FileSystem.isDirectory(path) && file != 'readme.txt' && file.endsWith('.txt')) {
							var fileToCheck:String = file.substr(0, file.length - 4);
							var alreadyInList:Bool = false;
							for (ev in eventStuff)
							{
								if(ev[0] == fileToCheck) { alreadyInList = true; break; }
							}
							if(!alreadyInList)
							{
								eventStuff.push([fileToCheck, File.getContent(path)]);
								perSongEventNames.push(fileToCheck);
							}
						}
					}
				}
			}
			#end
		}

		descText = new FlxText(20, 200, 0, eventStuff[0][0]);

		var leEvents:Array<String> = [];
		var perSongEventIndices:Array<Int> = [];
		for (i in 0...eventStuff.length) {
			leEvents.push(eventStuff[i][0]);
			if(perSongEventNames.contains(eventStuff[i][0]))
				perSongEventIndices.push(i);
		}

		var text:FlxText = new FlxText(20, 30, 0, "Event:");
		tab_group_event.add(text);
		eventDropDown = new FlxUIDropDownMenuCustom(20, 50, FlxUIDropDownMenuCustom.makeStrIdLabelArray(leEvents, true), function(pressed:String) {
			var selectedEvent:Int = Std.parseInt(pressed);
			descText.text = eventStuff[selectedEvent][1];
				if (curSelectedNote != null &&  eventStuff != null) {
				if (curSelectedNote != null && curSelectedNote[2] == null){
				curSelectedNote[1][curEventSelected][0] = eventStuff[selectedEvent][0];

				}
				updateGrid();
			}
		});
		blockPressWhileScrolling.push(eventDropDown);

		// Mark per-song events
		for (idx in perSongEventIndices)
			eventDropDown.markItem(idx);

		var text:FlxText = new FlxText(20, 90, 0, "Value 1:");
		tab_group_event.add(text);
		value1InputText = new FlxUIInputText(20, 110, 100, "");
		blockPressWhileTypingOn.push(value1InputText);

		var text:FlxText = new FlxText(20, 130, 0, "Value 2:");
		tab_group_event.add(text);
		value2InputText = new FlxUIInputText(20, 150, 100, "");
		blockPressWhileTypingOn.push(value2InputText);

		// New event buttons
		var removeButton:FlxButton = new FlxButton(eventDropDown.x + eventDropDown.width + 10, eventDropDown.y, '-', function()
		{
			if(curSelectedNote != null && curSelectedNote[2] == null) //Is event note
			{
				if(curSelectedNote[1].length < 2)
				{
					_song.events.remove(curSelectedNote);
					curSelectedNote = null;
				}
				else
				{
					curSelectedNote[1].remove(curSelectedNote[1][curEventSelected]);
				}

				var eventsGroup:Array<Dynamic>;
				--curEventSelected;
				if(curEventSelected < 0) curEventSelected = 0;
				else if(curSelectedNote != null && curEventSelected >= (eventsGroup = curSelectedNote[1]).length) curEventSelected = eventsGroup.length - 1;

				changeEventSelected();
				updateGrid();
			}
		});
		removeButton.setGraphicSize(Std.int(removeButton.height), Std.int(removeButton.height));
		removeButton.updateHitbox();
		removeButton.color = FlxColor.RED;
		removeButton.label.color = FlxColor.WHITE;
		removeButton.label.size = 12;
		setAllLabelsOffset(removeButton, -30, 0);
		tab_group_event.add(removeButton);

		var addButton:FlxButton = new FlxButton(removeButton.x + removeButton.width + 10, removeButton.y, '+', function()
		{
			if(curSelectedNote != null && curSelectedNote[2] == null) //Is event note
			{
				var eventsGroup:Array<Dynamic> = curSelectedNote[1];
				eventsGroup.push(['', '', '']);

				changeEventSelected(1);
				updateGrid();
			}
		});
		addButton.setGraphicSize(Std.int(removeButton.width), Std.int(removeButton.height));
		addButton.updateHitbox();
		addButton.color = FlxColor.GREEN;
		addButton.label.color = FlxColor.WHITE;
		addButton.label.size = 12;
		setAllLabelsOffset(addButton, -30, 0);
		tab_group_event.add(addButton);

		var moveLeftButton:FlxButton = new FlxButton(addButton.x + addButton.width + 20, addButton.y, '<', function()
		{
			changeEventSelected(-1);
		});
		moveLeftButton.setGraphicSize(Std.int(addButton.width), Std.int(addButton.height));
		moveLeftButton.updateHitbox();
		moveLeftButton.label.size = 12;
		setAllLabelsOffset(moveLeftButton, -30, 0);
		tab_group_event.add(moveLeftButton);

		var moveRightButton:FlxButton = new FlxButton(moveLeftButton.x + moveLeftButton.width + 10, moveLeftButton.y, '>', function()
		{
			changeEventSelected(1);
		});
		moveRightButton.setGraphicSize(Std.int(moveLeftButton.width), Std.int(moveLeftButton.height));
		moveRightButton.updateHitbox();
		moveRightButton.label.size = 12;
		setAllLabelsOffset(moveRightButton, -30, 0);
		tab_group_event.add(moveRightButton);

		selectedEventText = new FlxText(addButton.x - 100, addButton.y + addButton.height + 6, (moveRightButton.x - addButton.x) + 186, 'Selected Event: None');
		selectedEventText.alignment = CENTER;
		tab_group_event.add(selectedEventText);

		tab_group_event.add(descText);
		tab_group_event.add(value1InputText);
		tab_group_event.add(value2InputText);
		tab_group_event.add(eventDropDown);

		UI_box.addGroup(tab_group_event);
	}

	function changeEventSelected(change:Int = 0)
	{
		if(curSelectedNote != null && curSelectedNote[2] == null) //Is event note
		{
			curEventSelected += change;
			if(curEventSelected < 0) curEventSelected = Std.int(curSelectedNote[1].length) - 1;
			else if(curEventSelected >= curSelectedNote[1].length) curEventSelected = 0;
			selectedEventText.text = 'Selected Event: ' + (curEventSelected + 1) + ' / ' + curSelectedNote[1].length;
		}
		else
		{
			curEventSelected = 0;
			selectedEventText.text = 'Selected Event: None';
		}
		updateNoteUI();
	}

	// 虚拟方向键、提示层等后加入 state 时，把轨道按钮重新排到最上层
	function bringTrackButtonsToFront():Void
	{
		if (btnTrackLeft != null) { remove(btnTrackLeft); add(btnTrackLeft); }
		if (btnTrackRight != null) { remove(btnTrackRight); add(btnTrackRight); }
	}

	// 只有 4 键以上才需要横向滚动轨道
	function updateTrackButtonsVisibility():Void
	{
		var show:Bool = (_song.mania >= 3);
		if (btnTrackLeft != null) btnTrackLeft.visible = show;
		if (btnTrackRight != null) btnTrackRight.visible = show;
	}

	/**
	 * 运行时切换轨道按钮主题（不加可见 UI，供脚本 / 调试 / 以后重写 UI 时调用）。
	 *   setTrackButtonTheme(true)  -> flixelClassic()：灰阶方角，与屏内 FlxButton 一致（默认）
	 *   setTrackButtonTheme(false) -> glassBlue()：蓝色圆角玻璃
	 * 也可以直接传自定义 style：setTrackButtonTheme(true, myStyle)。
	 * 两个按钮共用一份 style，共享纹理缓存按字段生成 key，切换只重烘焙一次。
	 */
	public function setTrackButtonTheme(useFlixel:Bool, ?customStyle:StyledButtonStyle):Void
	{
		if (btnTrackLeft == null || btnTrackRight == null) return;
		if (customStyle != null)
		{
			btnTrackLeft.setStyle(customStyle);
			btnTrackRight.setStyle(customStyle);
			return;
		}
		var st:StyledButtonStyle = useFlixel ? StyledButtonStyle.flixelClassic() : StyledButtonStyle.glassBlue();
		st.size = 44;
		btnTrackLeft.setStyle(st);
		btnTrackRight.setStyle(st);
	}

	function setAllLabelsOffset(button:FlxButton, x:Float, y:Float)
	{
		for (point in button.labelOffsets)
		{
			point.set(x, y);
		}
	}

	var metronome:FlxUICheckBox;
	var mouseScrollingQuant:FlxUICheckBox;
	var metronomeStepper:FlxUINumericStepper;
	var metronomeOffsetStepper:FlxUINumericStepper;
	var disableAutoScrolling:FlxUICheckBox;
	var instVolume:FlxUINumericStepper;
	var voicesVolume:FlxUINumericStepper;
	var voicesOppVolume:FlxUINumericStepper;
	function addChartingUI() {
		var tab_group_chart = new FlxUI(null, UI_box);
		tab_group_chart.name = 'Charting';

		#if desktop
		if (FlxG.save.data.chart_waveformInst == null) FlxG.save.data.chart_waveformInst = false;
		if (FlxG.save.data.chart_waveformVoices == null) FlxG.save.data.chart_waveformVoices = false;
		if (FlxG.save.data.chart_waveformOppVoices == null) FlxG.save.data.chart_waveformOppVoices = false;

		var waveformUseInstrumental:FlxUICheckBox = null;
		var waveformUseVoices:FlxUICheckBox = null;
		var waveformUseOppVoices:FlxUICheckBox = null;

		waveformUseInstrumental = new FlxUICheckBox(10, 90, null, null, "Waveform\n(Instrumental)", 85);
		waveformUseInstrumental.checked = FlxG.save.data.chart_waveformInst;
		waveformUseInstrumental.callback = function()
		{
			waveformUseVoices.checked = false;
			waveformUseOppVoices.checked = false;
			FlxG.save.data.chart_waveformVoices = false;
			FlxG.save.data.chart_waveformOppVoices = false;
			FlxG.save.data.chart_waveformInst = waveformUseInstrumental.checked;
			updateWaveform();
		};

		waveformUseVoices = new FlxUICheckBox(waveformUseInstrumental.x + 100, waveformUseInstrumental.y, null, null, "Waveform\n(Main Vocals)", 85);
		waveformUseVoices.checked = FlxG.save.data.chart_waveformVoices && !waveformUseInstrumental.checked;
		waveformUseVoices.callback = function()
		{
			waveformUseInstrumental.checked = false;
			waveformUseOppVoices.checked = false;
			FlxG.save.data.chart_waveformInst = false;
			FlxG.save.data.chart_waveformOppVoices = false;
			FlxG.save.data.chart_waveformVoices = waveformUseVoices.checked;
			updateWaveform();
		};

		waveformUseOppVoices = new FlxUICheckBox(waveformUseInstrumental.x + 200, waveformUseInstrumental.y, null, null, "Waveform\n(Opp. Vocals)", 85);
		waveformUseOppVoices.checked = FlxG.save.data.chart_waveformOppVoices && !waveformUseVoices.checked;
		waveformUseOppVoices.callback = function()
		{
			waveformUseInstrumental.checked = false;
			waveformUseVoices.checked = false;
			FlxG.save.data.chart_waveformInst = false;
			FlxG.save.data.chart_waveformVoices = false;
			FlxG.save.data.chart_waveformOppVoices = waveformUseOppVoices.checked;
			updateWaveform();
		};
		#end

		check_mute_inst = new FlxUICheckBox(10, 280, null, null, "Mute Instrumental (in editor)", 100);
		check_mute_inst.checked = false;
		check_mute_inst.callback = function()
		{
			var vol:Float = instVolume.value;
			if (check_mute_inst.checked)
				vol = 0;

			FlxG.sound.music.volume = vol;
		};
		mouseScrollingQuant = new FlxUICheckBox(10, 190, null, null, "Mouse Scrolling Quantization", 100);
		if (FlxG.save.data.mouseScrollingQuant == null) FlxG.save.data.mouseScrollingQuant = false;
		mouseScrollingQuant.checked = FlxG.save.data.mouseScrollingQuant;

		mouseScrollingQuant.callback = function()
		{
			FlxG.save.data.mouseScrollingQuant = mouseScrollingQuant.checked;
			mouseQuant = FlxG.save.data.mouseScrollingQuant;
		};

		check_vortex = new FlxUICheckBox(10, 160, null, null, "Vortex Editor (BETA)", 100);
		if (FlxG.save.data.chart_vortex == null) FlxG.save.data.chart_vortex = false;
		check_vortex.checked = FlxG.save.data.chart_vortex;

		check_vortex.callback = function()
		{
			FlxG.save.data.chart_vortex = check_vortex.checked;
			vortex = FlxG.save.data.chart_vortex;
			reloadGridLayer();
		};

		check_warnings = new FlxUICheckBox(10, 120, null, null, "Ignore Progress Warnings", 100);
		if (FlxG.save.data.ignoreWarnings == null) FlxG.save.data.ignoreWarnings = false;
		check_warnings.checked = FlxG.save.data.ignoreWarnings;

		check_warnings.callback = function()
		{
			FlxG.save.data.ignoreWarnings = check_warnings.checked;
			ignoreWarnings = FlxG.save.data.ignoreWarnings;
		};

		check_mute_vocals = new FlxUICheckBox(check_mute_inst.x, check_mute_inst.y + 30, null, null, "Mute Main Vocals (in editor)", 100);
		check_mute_vocals.checked = false;
		check_mute_vocals.callback = function()
		{
			var vol:Float = voicesVolume.value;
			if (check_mute_vocals.checked)
				vol = 0;

			if(vocals != null) vocals.volume = vol;
		};
		check_mute_vocals_opponent = new FlxUICheckBox(check_mute_vocals.x + 120, check_mute_vocals.y, null, null, "Mute Opp. Vocals (in editor)", 100);
		check_mute_vocals_opponent.checked = false;
		check_mute_vocals_opponent.callback = function()
		{
			var vol:Float = voicesOppVolume.value;
			if (check_mute_vocals_opponent.checked)
				vol = 0;

			if(opponentVocals != null) opponentVocals.volume = vol;
		};

		playSoundBf = new FlxUICheckBox(check_mute_inst.x, check_mute_vocals.y + 30, null, null, 'Play Sound (Boyfriend notes)', 100,
			function() {
				FlxG.save.data.chart_playSoundBf = playSoundBf.checked;
			}
		);
		if (FlxG.save.data.chart_playSoundBf == null) FlxG.save.data.chart_playSoundBf = false;
		playSoundBf.checked = FlxG.save.data.chart_playSoundBf;

		playSoundDad = new FlxUICheckBox(check_mute_inst.x + 120, playSoundBf.y, null, null, 'Play Sound (Opponent notes)', 100,
			function() {
				FlxG.save.data.chart_playSoundDad = playSoundDad.checked;
			}
		);
		if (FlxG.save.data.chart_playSoundDad == null) FlxG.save.data.chart_playSoundDad = false;
		playSoundDad.checked = FlxG.save.data.chart_playSoundDad;

		metronome = new FlxUICheckBox(10, 15, null, null, "Metronome Enabled", 100,
			function() {
				FlxG.save.data.chart_metronome = metronome.checked;
			}
		);
		if (FlxG.save.data.chart_metronome == null) FlxG.save.data.chart_metronome = false;
		metronome.checked = FlxG.save.data.chart_metronome;

		metronomeStepper = new FlxUINumericStepper(15, 55, 5, _song.bpm, 1, 1500, 1);
		metronomeOffsetStepper = new FlxUINumericStepper(metronomeStepper.x + 100, metronomeStepper.y, 25, 0, 0, 1000, 1);
		blockPressWhileTypingOnStepper.push(metronomeStepper);
		blockPressWhileTypingOnStepper.push(metronomeOffsetStepper);

		disableAutoScrolling = new FlxUICheckBox(metronome.x + 120, metronome.y, null, null, "Disable Autoscroll (Not Recommended)", 120,
			function() {
				FlxG.save.data.chart_noAutoScroll = disableAutoScrolling.checked;
			}
		);
		if (FlxG.save.data.chart_noAutoScroll == null) FlxG.save.data.chart_noAutoScroll = false;
		disableAutoScrolling.checked = FlxG.save.data.chart_noAutoScroll;

		instVolume = new FlxUINumericStepper(metronomeStepper.x, 250, 0.1, 1, 0, 1, 1);
		instVolume.value = FlxG.sound.music.volume;
		instVolume.name = 'inst_volume';
		blockPressWhileTypingOnStepper.push(instVolume);

		voicesVolume = new FlxUINumericStepper(instVolume.x + 100, instVolume.y, 0.1, 1, 0, 1, 1);
		voicesVolume.value = vocals.volume;
		voicesVolume.name = 'voices_volume';
		blockPressWhileTypingOnStepper.push(voicesVolume);

		voicesOppVolume = new FlxUINumericStepper(instVolume.x + 200, instVolume.y, 0.1, 1, 0, 1, 1);
		voicesOppVolume.value = vocals.volume;
		voicesOppVolume.name = 'voices_opp_volume';
		blockPressWhileTypingOnStepper.push(voicesOppVolume);
		
		#if FLX_PITCH
		sliderRate = new OldSlider(this, 'playbackSpeed', 120, 120, 0.5, 3, 150, 15, 5, FlxColor.WHITE, FlxColor.BLACK);
		sliderRate.nameLabel.text = 'Playback Rate';
		tab_group_chart.add(sliderRate);
		#end

		tab_group_chart.add(new FlxText(metronomeStepper.x, metronomeStepper.y - 15, 0, 'BPM:'));
		tab_group_chart.add(new FlxText(metronomeOffsetStepper.x, metronomeOffsetStepper.y - 15, 0, 'Offset (ms):'));
		tab_group_chart.add(new FlxText(instVolume.x, instVolume.y - 15, 0, 'Inst Volume'));
		tab_group_chart.add(new FlxText(voicesVolume.x, voicesVolume.y - 15, 0, 'Main Vocals'));
		tab_group_chart.add(new FlxText(voicesOppVolume.x, voicesOppVolume.y - 15, 0, 'Opp. Vocals'));
		tab_group_chart.add(metronome);
		tab_group_chart.add(disableAutoScrolling);
		tab_group_chart.add(metronomeStepper);
		tab_group_chart.add(metronomeOffsetStepper);
		#if desktop
		tab_group_chart.add(waveformUseInstrumental);
		tab_group_chart.add(waveformUseVoices);
		tab_group_chart.add(waveformUseOppVoices);
		#end
		tab_group_chart.add(instVolume);
		tab_group_chart.add(voicesVolume);
		tab_group_chart.add(voicesOppVolume);
		tab_group_chart.add(check_mute_inst);
		tab_group_chart.add(check_mute_vocals);
		tab_group_chart.add(check_mute_vocals_opponent);
		tab_group_chart.add(check_vortex);
		tab_group_chart.add(mouseScrollingQuant);
		tab_group_chart.add(check_warnings);
		tab_group_chart.add(playSoundBf);
		tab_group_chart.add(playSoundDad);
		UI_box.addGroup(tab_group_chart);
	}

	var gameOverCharacterInputText:FlxUIInputText;
	var gameOverSoundInputText:FlxUIInputText;
	var gameOverLoopInputText:FlxUIInputText;
	var gameOverEndInputText:FlxUIInputText;
	var noteSkinInputText:FlxUIInputText;
	var noteSplashesInputText:FlxUIInputText;
	function addDataUI()
	{
		var tab_group_data = new FlxUI(null, UI_box);
		tab_group_data.name = 'Data';

		//
		gameOverCharacterInputText = new FlxUIInputText(10, 25, 150, _song.gameOverChar != null ? _song.gameOverChar : '', 8);
		blockPressWhileTypingOn.push(gameOverCharacterInputText);
		
		gameOverSoundInputText = new FlxUIInputText(10, gameOverCharacterInputText.y + 35, 150, _song.gameOverSound != null ? _song.gameOverSound : '', 8);
		blockPressWhileTypingOn.push(gameOverSoundInputText);
		
		gameOverLoopInputText = new FlxUIInputText(10, gameOverSoundInputText.y + 35, 150, _song.gameOverLoop != null ? _song.gameOverLoop : '', 8);
		blockPressWhileTypingOn.push(gameOverLoopInputText);
		
		gameOverEndInputText = new FlxUIInputText(10, gameOverLoopInputText.y + 35, 150, _song.gameOverEnd != null ? _song.gameOverEnd : '', 8);
		blockPressWhileTypingOn.push(gameOverEndInputText);
		//

		var check_disableNoteRGB:FlxUICheckBox = new FlxUICheckBox(10, 170, null, null, "Disable Note RGB", 100);
		check_disableNoteRGB.checked = (_song.disableNoteRGB == true);
		check_disableNoteRGB.callback = function()
		{
			_song.disableNoteRGB = check_disableNoteRGB.checked;
			updateGrid();
			//trace('CHECKED!');
		};

		//
		noteSkinInputText = new FlxUIInputText(10, 280, 150, _song.arrowSkin != null ? _song.arrowSkin : '', 8);
		blockPressWhileTypingOn.push(noteSkinInputText);

		noteSplashesInputText = new FlxUIInputText(noteSkinInputText.x, noteSkinInputText.y + 35, 150, _song.splashSkin != null ? _song.splashSkin : '', 8);
		blockPressWhileTypingOn.push(noteSplashesInputText);

		var reloadNotesButton:FlxButton = new FlxButton(noteSplashesInputText.x + 5, noteSplashesInputText.y + 20, 'Change Notes', function() {
			_song.arrowSkin = noteSkinInputText.text;
			updateGrid();
		});
		//
		
		tab_group_data.add(gameOverCharacterInputText);
		tab_group_data.add(gameOverSoundInputText);
		tab_group_data.add(gameOverLoopInputText);
		tab_group_data.add(gameOverEndInputText);

		tab_group_data.add(check_disableNoteRGB);
		
		tab_group_data.add(reloadNotesButton);
		tab_group_data.add(noteSkinInputText);
		tab_group_data.add(noteSplashesInputText);

		tab_group_data.add(new FlxText(gameOverCharacterInputText.x, gameOverCharacterInputText.y - 15, 0, 'Game Over Character Name:'));
		tab_group_data.add(new FlxText(gameOverSoundInputText.x, gameOverSoundInputText.y - 15, 0, 'Game Over Death Sound (sounds/):'));
		tab_group_data.add(new FlxText(gameOverLoopInputText.x, gameOverLoopInputText.y - 15, 0, 'Game Over Loop Music (music/):'));
		tab_group_data.add(new FlxText(gameOverEndInputText.x, gameOverEndInputText.y - 15, 0, 'Game Over Retry Music (music/):'));

		tab_group_data.add(new FlxText(noteSkinInputText.x, noteSkinInputText.y - 15, 0, 'Note Texture:'));
		tab_group_data.add(new FlxText(noteSplashesInputText.x, noteSplashesInputText.y - 15, 0, 'Note Splashes Texture:'));
		UI_box.addGroup(tab_group_data);
	}

	function loadSong():Void
	{
		if(FlxG.sound.music != null)
			FlxG.sound.music.stop();

		if(vocals != null)
		{
			vocals.stop();
			vocals.destroy();
		}
		if(opponentVocals != null)
		{
			opponentVocals.stop();
			opponentVocals.destroy();
		}

		// reloadaudio fix (real refresh): drop any cached audio for this song so the
		// subsequent Paths.voices/playMusic re-reads the file from disk instead of
		// returning the previously loaded (now stale) Sound object.
		for (key => snd in Paths.currentTrackedSounds)
		{
			if (key.contains('/songs/' + currentSongName + '/') && snd != null)
			{
				snd.close();
				OpenFlAssets.cache.clear(key);
				Paths.currentTrackedSounds.remove(key);
				Paths.localTrackedAssets.remove(key);
			}
		}

		vocals = new FlxSound();
		opponentVocals = new FlxSound();
		try
		{
			var playerPostfix:String = (characterData.vocalsP1 == null || characterData.vocalsP1.length < 1) ? 'Player' : characterData.vocalsP1;
			var playerVocals = Paths.voices(currentSongName, playerPostfix, specialVocalSuffix());
			if (playerVocals == null) playerVocals = Paths.voices(currentSongName, playerPostfix);
			vocals.loadEmbedded(playerVocals != null ? playerVocals : Paths.voices(currentSongName));
		}
		vocals.autoDestroy = false;
		FlxG.sound.list.add(vocals);

		opponentVocals = new FlxSound();
		try
		{
			var oppPostfix:String = (characterData.vocalsP2 == null || characterData.vocalsP2.length < 1) ? 'Opponent' : characterData.vocalsP2;
			var oppVocals = Paths.voices(currentSongName, oppPostfix, specialVocalSuffix());
			if (oppVocals == null) oppVocals = Paths.voices(currentSongName, oppPostfix);
			if(oppVocals != null) opponentVocals.loadEmbedded(oppVocals);
		}
		opponentVocals.autoDestroy = false;
		FlxG.sound.list.add(opponentVocals);

		generateSong();
		FlxG.sound.music.pause();
		Conductor.songPosition = sectionStartTime();
		FlxG.sound.music.time = Conductor.songPosition;

		var curTime:Float = 0;
		//trace(_song.notes.length);
		if(_song.notes.length <= 1) //First load ever
		{
			trace('first load ever!!');
			while(curTime < FlxG.sound.music.length)
			{
				addSection();
				curTime += (60 / _song.bpm) * 4000;
			}
		}
	}

	var playtesting:Bool = false;
	var playtestingTime:Float = 0;
	var playtestingOnComplete:Void->Void = null;
	override function closeSubState()
	{
		if(playtesting)
		{
			FlxG.sound.music.pause();
			FlxG.sound.music.time = playtestingTime;
			FlxG.sound.music.onComplete = playtestingOnComplete;
			if (instVolume != null) FlxG.sound.music.volume = instVolume.value;
			if (check_mute_inst != null && check_mute_inst.checked) FlxG.sound.music.volume = 0;

			if(vocals != null)
			{
				vocals.pause();
				vocals.time = playtestingTime;
				if (voicesVolume != null) vocals.volume = voicesVolume.value;
				if (check_mute_vocals != null && check_mute_vocals.checked) vocals.volume = 0;
			}

			if(opponentVocals != null)
			{
				opponentVocals.pause();
				opponentVocals.time = playtestingTime;
				if (voicesOppVolume != null) opponentVocals.volume = voicesOppVolume.value;
				if (check_mute_vocals_opponent != null && check_mute_vocals_opponent.checked) opponentVocals.volume = 0;
			}

			#if DISCORD_ALLOWED
			// Updating Discord Rich Presence
			DiscordClient.changePresence("Chart Editor", StringTools.replace(_song.song, '-', ' '));
			#end
		}
		super.closeSubState();
	}

	// This engine lets a chart point at suffixed audio files (Inst-X / Voices-X) through
	// specialInst / specialVocal; 0.7.3 knew nothing about them and would load the wrong track.
	inline function specialInstSuffix():String
		return (_song != null && _song.specialInst != null && _song.specialInst.length > 0) ? _song.specialInst : null;

	inline function specialVocalSuffix():String
		return (_song != null && _song.specialVocal != null && _song.specialVocal.length > 0) ? _song.specialVocal : null;

	function generateSong() {
		FlxG.sound.playMusic(Paths.inst(currentSongName, specialInstSuffix()), 0.6/*, false*/);
		FlxG.sound.music.autoDestroy = false;
		if (instVolume != null) FlxG.sound.music.volume = instVolume.value;
		if (check_mute_inst != null && check_mute_inst.checked) FlxG.sound.music.volume = 0;

		FlxG.sound.music.onComplete = function()
		{
			FlxG.sound.music.pause();
			Conductor.songPosition = 0;
			if(vocals != null) {
				vocals.pause();
				vocals.time = 0;
			}
			if(opponentVocals != null) {
				opponentVocals.pause();
				opponentVocals.time = 0;
			}
			changeSection();
			curSec = 0;
			updateGrid();
			updateSectionUI();
			if(vocals != null) vocals.play();
			if(opponentVocals != null) opponentVocals.play();
		};
	}

	function generateUI():Void
	{
		while (bullshitUI.members.length > 0)
		{
			bullshitUI.remove(bullshitUI.members[0], true);
		}

		// general shit
		var title:FlxText = new FlxText(UI_box.x + 20, UI_box.y + 20, 0);
		bullshitUI.add(title);
	}

	override function getEvent(id:String, sender:Dynamic, data:Dynamic, ?params:Array<Dynamic>)
	{
		if (id == FlxUICheckBox.CLICK_EVENT)
		{
			var check:FlxUICheckBox = cast sender;
			var label = check.getLabel().text;
			pushUndo();
			switch (label)
			{
				case 'Must hit section':
					_song.notes[curSec].mustHitSection = check.checked;

					updateGrid();
					updateHeads();

				case 'GF section':
					_song.notes[curSec].gfSection = check.checked;

					updateGrid();
					updateHeads();

				case 'Change BPM':
					_song.notes[curSec].changeBPM = check.checked;
					FlxG.log.add('changed bpm shit');
				case "Alt Animation":
					_song.notes[curSec].altAnim = check.checked;
			}
		}
		else if (id == FlxUINumericStepper.CHANGE_EVENT && (sender is FlxUINumericStepper))
		{
			var nums:FlxUINumericStepper = cast sender;
			var wname = nums.name;
			// 音量/速度类不改谱面数据，不进 undo 栈；undo 同步 stepper 显示值时也不该压栈
			if (!suppressManiaEvent && (wname == 'section_beats' || wname == 'song_bpm' || wname == 'song_mania'
				|| wname == 'section_bpm' || wname == 'note_susLength'))
				pushUndo();
			//FlxG.log.add(wname);
			switch(wname)
			{
				case 'section_beats':
					_song.notes[curSec].sectionBeats = nums.value;
					reloadGridLayer();

				case 'song_speed':
					_song.speed = nums.value;

				case 'song_offset':
					_song.offset = nums.value;
					Conductor.offset = nums.value;

				case 'song_mania':
					refreshManiaKeysLabel(); // 无论是否 undo 同步，显示值都跟着 stepper 变
					// 改档是「非破坏性」的：降档只把超范围音符暂存，改回/升档自动原位还原，
					// 因此 6K→5K→6K 不会丢任何箭头。undo 同步 stepper 显示值时置
					// suppressManiaEvent，避免把一次 UI 同步误当成新的改档再重映射一遍。
					if (!suppressManiaEvent)
					{
						var newMania:Int = Std.int(nums.value);
						var oldMania:Int = _song.mania;
						if (oldMania != newMania)
						{
							dbgTypeLog('MANIA 改档前', (oldMania + 1) + 'K -> ' + (newMania + 1) + 'K');
							remapChartNotesForMania(oldMania, newMania);
							dbgTypeLog('MANIA 改档后', (oldMania + 1) + 'K -> ' + (newMania + 1) + 'K');
						}
						_song.mania = newMania;
						// 同步 keyCount 字段：Song.convert 优先读 keyCount-1 而不是 mania，
						// 不同步会导致从 6k 谱面改成 9k 后，toPsychV1 仍用 6 列折叠 lane，音符飞轨。
						if (Reflect.hasField(_song, 'keyCount'))
							Reflect.setField(_song, 'keyCount', newMania + 1);
						PlayState.SONG.mania = _song.mania;
						// 重置轨道水平偏移 + 同步按钮与背景层的可见性（仅 4k+ 显示）
						trackScrollX = GRID_SIZE;
						trackScrollTargetX = GRID_SIZE;
						updateTrackButtonsVisibility();
						// reloadGridLayer() -> rebuildStrumLineNotes()：箭头数量、位置与
						// 多键贴图档位一起按新 mania 重建（只改 _song.mania 不会换贴图）
						reloadGridLayer();
					}

				case 'song_bpm':
					_song.bpm = nums.value;
					Conductor.mapBPMChanges(_song);
					Conductor.bpm = nums.value;
					stepperSusLength.stepSize = Math.ceil(Conductor.stepCrochet / 2);
					updateGrid();

				case 'note_susLength':
					if(curSelectedNote != null && curSelectedNote[2] != null) {
						curSelectedNote[2] = nums.value;
						updateGrid();
					}

				case 'section_bpm':
					_song.notes[curSec].bpm = nums.value;
					updateGrid();

				case 'inst_volume':
					FlxG.sound.music.volume = nums.value;
					if(check_mute_inst.checked) FlxG.sound.music.volume = 0;

				case 'voices_volume':
					vocals.volume = nums.value;
					if(check_mute_vocals.checked) vocals.volume = 0;

				case 'voices_opp_volume':
					opponentVocals.volume = nums.value;
					if(check_mute_vocals_opponent.checked) opponentVocals.volume = 0;
			}
		}
		else if(id == FlxUIInputText.CHANGE_EVENT && (sender is FlxUIInputText)) {
			if(sender == noteSplashesInputText) {
				_song.splashSkin = noteSplashesInputText.text;
			}
			else if(sender == noteSkinInputText) {
				_song.arrowSkin = noteSkinInputText.text;
			}
			else if(sender == gameOverCharacterInputText) {
				_song.gameOverChar = gameOverCharacterInputText.text;
			}
			else if(sender == gameOverSoundInputText) {
				_song.gameOverSound = gameOverSoundInputText.text;
			}
			else if(sender == gameOverLoopInputText) {
				_song.gameOverLoop = gameOverLoopInputText.text;
			}
			else if(sender == gameOverEndInputText) {
				_song.gameOverEnd = gameOverEndInputText.text;
			}
			else if(curSelectedNote != null)
			{
				if(sender == value1InputText) {
					if(curSelectedNote[1][curEventSelected] != null)
					{
						curSelectedNote[1][curEventSelected][1] = value1InputText.text;
						updateGrid();
					}
				}
				else if(sender == value2InputText) {
					if(curSelectedNote[1][curEventSelected] != null)
					{
						curSelectedNote[1][curEventSelected][2] = value2InputText.text;
						updateGrid();
					}
				}
				else if(sender == strumTimeInputText) {
					var value:Float = Std.parseFloat(strumTimeInputText.text);
					if(Math.isNaN(value)) value = 0;
					curSelectedNote[0] = value;
					updateGrid();
				}
			}
		}
		// NOTE: 0.7.3 handled the playback rate slider here through FlxUISlider.CHANGE_EVENT, but it
		// compared the sender object against a String so the branch never ran. OldSlider writes
		// `playbackSpeed` directly instead, which is what that code meant to do.

		// FlxG.log.add(id + " WEED " + sender + " WEED " + data + " WEED " + params);

		if(controls.mobileC)
		{
			if(_virtualpad == null)
			{
				_virtualpad = new FlxVirtualPad(FlxDPadMode.CHART_EDITOR, FlxActionMode.CHART_EDITOR);
				add(_virtualpad);
				// 虚拟方向键是运行时后加入的，重新把轨道按钮置顶，避免触控层盖住背景
				bringTrackButtonsToFront();
			}
		}
	}

	var updatedSection:Bool = false;

	function sectionStartTime(add:Int = 0):Float
	{
		var daBPM:Float = _song.bpm;
		var daPos:Float = 0;
		for (i in 0...curSec + add)
		{
			if(_song.notes[i] != null)
			{
				if (_song.notes[i].changeBPM)
				{
					daBPM = _song.notes[i].bpm;
				}
				daPos += getSectionBeats(i) * (1000 * 60 / daBPM);
			}
		}
		return daPos;
	}

	var lastConductorPos:Float;
	var colorSine:Float = 0;
	override function update(elapsed:Float)
	{
		curStep = recalculateSteps();

		var shiftHeld:Bool = FlxG.keys.pressed.SHIFT || (_virtualpad != null && _virtualpad.buttonY.pressed);
		var altHeld:Bool = FlxG.keys.pressed.ALT;
		var ctrlHeld:Bool = FlxG.keys.pressed.CONTROL || (_virtualpad != null && _virtualpad.buttonZ.pressed);

		if(FlxG.sound.music.time < 0) {
			FlxG.sound.music.pause();
			FlxG.sound.music.time = 0;
		}
		else if(FlxG.sound.music.time > FlxG.sound.music.length) {
			FlxG.sound.music.pause();
			FlxG.sound.music.time = 0;
			changeSection();
		}
		Conductor.songPosition = FlxG.sound.music.time + Conductor.offset;
		_song.song = UI_songTitle.text;

		strumLineUpdateY();
		// 按实际成员遍历：改 mania 时若箭头数量尚未跟上，按 (_song.mania+1)*2 取下标会越界
		if (strumLineNotes != null)
		{
			for (arrow in strumLineNotes)
				if (arrow != null) arrow.y = strumLine.y;
		}

		FlxG.mouse.visible = true;//cause reasons. trust me

		// === 轨道水平相机（自动跟随 mania + 手动偏移 + 平滑过渡）===
		// 手动滚动：Alt/Shift + 鼠标滚轮 → 无限制，直接推进目标值
		var wheelDelta:Float = FlxG.mouse.wheel;
		var wheelConsumedForHorizontal:Bool = false;
		if (wheelDelta != 0 && altHeld) {
			trackScrollTargetX -= wheelDelta * GRID_SIZE;
			wheelConsumedForHorizontal = true;
		}

		// 按钮按住 → 持续推进目标值（无限制）。按时间推进而非按帧，高刷屏不会变快；
		// elapsed 上限 1/30 秒，避免卡顿恢复后单帧跳太远。
		// 上方 Alt+滚轮分支与下方共用 lerp 系数保持不变，键鼠滚动速度不受影响。
		var btnStep:Float = trackButtonScrollSpeed * Math.min(elapsed, 1 / 30);
		if (btnTrackLeft != null && btnTrackLeft.pressed) {
			trackScrollTargetX += btnStep;
		}
		if (btnTrackRight != null && btnTrackRight.pressed) {
			trackScrollTargetX -= btnStep;
		}

		// 平滑过渡：lerp 当前值 → 目标值（系数 0.25 中等速度，键鼠与按钮共用，不改动）
		trackScrollX = FlxMath.lerp(trackScrollX, trackScrollTargetX, 0.25);

		// 相机中心 = Minty 新版自动跟随公式 + 平滑后的手动偏移
		camPos.x = -80 + (GRID_SIZE * ((_song.mania + 1) * 2)) + trackScrollX;
		camPos.y = strumLine.y;

		if(!disableAutoScrolling.checked) {
			// 直接用播放时间 vs section 起始时间判断跨段，不依赖 strumLine.y 与 gridBG.height 的
			// 像素/格数比较（取模 + zoom 缩放后两者单位不一致，容易永远到不了阈值）。
			var songPos:Float = Conductor.songPosition;
			if (songPos >= sectionStartTime(1))
			{
				if (_song.notes[curSec + 1] == null)
				{
					addSection();
				}

				changeSection(curSec + 1, false);
			} else if (songPos < sectionStartTime()) {
				if (curSec > 0) changeSection(curSec - 1, false);
			}
		}
		FlxG.watch.addQuick('daBeat', curBeat);
		FlxG.watch.addQuick('daStep', curStep);

		// 提前计算 blockInput，让它同时保护鼠标事件（防止 UI box 穿透到轨道）
		var blockInput:Bool = false;
		for (inputText in blockPressWhileTypingOn) {
			if(inputText.hasFocus) {
				ClientPrefs.toggleVolumeKeys(false);
				blockInput = true;
				break;
			}
		}

		if(!blockInput) {
			for (stepper in blockPressWhileTypingOnStepper) {
				@:privateAccess
				var leText:FlxUIInputText = cast (stepper.text_field, FlxUIInputText);
				if(leText.hasFocus) {
					ClientPrefs.toggleVolumeKeys(false);
					blockInput = true;
					break;
				}
			}
		}

		if(!blockInput) {
			ClientPrefs.toggleVolumeKeys(true);
			for (dropDownMenu in blockPressWhileScrolling) {
				if(dropDownMenu.dropPanel.visible) {
					blockInput = true;
					break;
				}
			}
		}

		// blockInput=true 时（UI 输入/下拉在交互中），阻止轨道穿透：不显示 dummyArrow、不响应点击
		var mouseInGrid:Bool = FlxG.mouse.x > gridBG.x
			&& FlxG.mouse.x < gridBG.x + gridBG.width
			&& FlxG.mouse.y > gridBG.y
			&& FlxG.mouse.y < gridBG.y + (GRID_SIZE * getSectionBeats() * 4) * zoomList[curZoom];

		// 额外防护：鼠标是否在 UI box 矩形内。
		// UI_box.scrollFactor=(0,0)，它的 x/y/width/height 是屏幕坐标；
		// FlxG.mouse.x/y 是世界坐标。Flixel 里：屏幕坐标 = 世界坐标 - camera.scroll。
		// trackScrollX 改变 camera.scroll.x 后，必须反算屏幕坐标再和 UI_box 矩形比较，
		// 否则轨道滑到 box 下方时点 box 内容会穿透到 grid。
		var mouseInUIBox:Bool = false;
		var smx:Float = FlxG.mouse.x - FlxG.camera.scroll.x;
		var smy:Float = FlxG.mouse.y - FlxG.camera.scroll.y;
		if (UI_box != null) {
			mouseInUIBox = smx >= UI_box.x - 5
				&& smx <= UI_box.x + UI_box.width + 5
				&& smy >= UI_box.y - 5
				&& smy <= UI_box.y + UI_box.height + 5;
		}
		var suppressMouse = blockInput || mouseInUIBox || backend.ui.DropdownInputPriority.pointerInsideOpenList();

		// 轨道左右滑动按钮也在屏幕上（scrollFactor=0），点按钮时不能穿透到 grid
		if (!suppressMouse && btnTrackLeft != null && btnTrackLeft.visible) {
			if (smx >= btnTrackLeft.x - 4 && smx <= btnTrackLeft.x + btnTrackLeft.width + 4
				&& smy >= btnTrackLeft.y - 4 && smy <= btnTrackLeft.y + btnTrackLeft.height + 4)
				suppressMouse = true;
		}
		if (!suppressMouse && btnTrackRight != null && btnTrackRight.visible) {
			if (smx >= btnTrackRight.x - 4 && smx <= btnTrackRight.x + btnTrackRight.width + 4
				&& smy >= btnTrackRight.y - 4 && smy <= btnTrackRight.y + btnTrackRight.height + 4)
				suppressMouse = true;
		}

		if (!suppressMouse && mouseInGrid)
		{
			dummyArrow.visible = true;
			dummyArrow.x = Math.floor(FlxG.mouse.x / GRID_SIZE) * GRID_SIZE;
			if (shiftHeld)
				dummyArrow.y = FlxG.mouse.y;
			else
			{
				var gridmult = GRID_SIZE / (quantization / 16);
				dummyArrow.y = Math.floor(FlxG.mouse.y / gridmult) * gridmult;
			}
		} else {
			dummyArrow.visible = false;
		}

		if (FlxG.mouse.justPressed && !suppressMouse)
		{
			if (FlxG.mouse.overlaps(curRenderedNotes))
			{
				curRenderedNotes.forEachAlive(function(note:Note)
				{
					if (FlxG.mouse.overlaps(note))
					{
						if (ctrlHeld)
						{
							selectNote(note);
						}
						else if (altHeld)
						{
							selectNote(note);
							curSelectedNote[3] = curNoteTypes[currentType];
							mirrorSetNoteType(curSelectedNote, curNoteTypes[currentType]);
							updateGrid();
						}
						else
						{
							//trace('tryin to delete note...');
							deleteNote(note);
						}
					}
				});
			}
			else if (mouseInGrid)
			{
				FlxG.log.add('added note');
				addNote();
			}
		}

		if (!blockInput)
		{
	

		if (FlxG.keys.justPressed.ESCAPE || (_virtualpad != null && _virtualpad.buttonC.justPressed))
			{
				confirmChartMania(openEditorPlayState);
			}
			else if (FlxG.keys.justPressed.ENTER || (_virtualpad != null && _virtualpad.buttonA.justPressed))
			{
				confirmChartMania(goPlayState);
			}

			if(curSelectedNote != null && curSelectedNote[1] > -1) {
				if (FlxG.keys.justPressed.E || (_virtualpad != null && _virtualpad.buttonCEDown.justPressed))
				{
					changeNoteSustain(Conductor.stepCrochet);
				}
				if (FlxG.keys.justPressed.Q || (_virtualpad != null && _virtualpad.buttonCEUp.justPressed))
				{
					changeNoteSustain(-Conductor.stepCrochet);
				}
			}


			if (FlxG.keys.justPressed.BACKSPACE || (_virtualpad != null && _virtualpad.buttonB.justPressed)) {
				// Protect against lost data when quickly leaving the chart editor.
				autosaveSong();
				PlayState.chartingMode = false;
				MusicBeatState.switchState(new states.editors.MasterEditorMenu());
				FlxG.sound.playMusic(Paths.menuMusicAudio());
				FlxG.mouse.visible = false;
				return;
			}

			if(FlxG.keys.justPressed.Z && ctrlHeld) {
				undo();
			}

			if((FlxG.keys.justPressed.Y && ctrlHeld) || (FlxG.keys.justPressed.Z && ctrlHeld && shiftHeld)) {
				redo();
			}

			if((FlxG.keys.justPressed.Z || (_virtualpad != null && _virtualpad.buttonV.justPressed)) && curZoom > 0 && !ctrlHeld) {
				--curZoom;
				updateZoom();
			}
			if((FlxG.keys.justPressed.X || (_virtualpad != null && _virtualpad.buttonD.justPressed)) && curZoom < zoomList.length-1) {
				curZoom++;
				updateZoom();
			}

			if (FlxG.keys.justPressed.TAB)
			{
				if (shiftHeld)
				{
					UI_box.selected_tab -= 1;
					if (UI_box.selected_tab < 0)
						UI_box.selected_tab = 2;
				}
				else
				{
					UI_box.selected_tab += 1;
					if (UI_box.selected_tab >= 3)
						UI_box.selected_tab = 0;
				}
			}

			if (FlxG.keys.justPressed.SPACE || (_virtualpad != null && _virtualpad.buttonX.justPressed))
			{
				if(vocals != null) vocals.play();
				if(opponentVocals != null) opponentVocals.play();
				pauseAndSetVocalsTime();
				if (!FlxG.sound.music.playing)
				{
					FlxG.sound.music.play();
					if(vocals != null) vocals.play();
					if(opponentVocals != null) opponentVocals.play();
				}
				else FlxG.sound.music.pause();
			}

			if (!altHeld && FlxG.keys.justPressed.R)
			{
				if (shiftHeld)
					resetSection(true);
				else
					resetSection();
			}

			if (FlxG.mouse.wheel != 0 && !wheelConsumedForHorizontal)
			{
				FlxG.sound.music.pause();
				if (!mouseQuant)
					FlxG.sound.music.time -= (FlxG.mouse.wheel * Conductor.stepCrochet*0.8);
				else
				{
					var time:Float = FlxG.sound.music.time;
					var beat:Float = curDecBeat;
					var snap:Float = quantization / 4;
					var increase:Float = 1 / snap;
					if (FlxG.mouse.wheel > 0)
					{
						var fuck:Float = CoolUtil.quantize(beat, snap) - increase;
						FlxG.sound.music.time = Conductor.beatToSeconds(fuck);
					} else {
						var fuck:Float = CoolUtil.quantize(beat, snap) + increase;
						FlxG.sound.music.time = Conductor.beatToSeconds(fuck);
					}
				}
				pauseAndSetVocalsTime();
			}

			//ARROW VORTEX SHIT NO DEADASS

			if (FlxG.keys.pressed.W || FlxG.keys.pressed.S || (_virtualpad != null && (_virtualpad.buttonUp.pressed || _virtualpad.buttonDown.pressed)))
			{
				FlxG.sound.music.pause();

				var holdingShift:Float = 1;
				if (ctrlHeld) holdingShift = 0.25;
				else if (shiftHeld) holdingShift = 4;

				var daTime:Float = 700 * FlxG.elapsed * holdingShift;

				FlxG.sound.music.time += daTime * ((FlxG.keys.pressed.W || (_virtualpad != null && _virtualpad.buttonUp.pressed)) ? -1 : 1);

				pauseAndSetVocalsTime();
			}

			if(!vortex){
				if (FlxG.keys.justPressed.UP || FlxG.keys.justPressed.DOWN)
				{
					FlxG.sound.music.pause();
					updateCurStep();
					var time:Float = FlxG.sound.music.time;
					var beat:Float = curDecBeat;
					var snap:Float = quantization / 4;
					var increase:Float = 1 / snap;
					if (FlxG.keys.pressed.UP)
					{
						var fuck:Float = CoolUtil.quantize(beat, snap) - increase; //(Math.floor((beat+snap) / snap) * snap);
						FlxG.sound.music.time = Conductor.beatToSeconds(fuck);
					}else{
						var fuck:Float = CoolUtil.quantize(beat, snap) + increase; //(Math.floor((beat+snap) / snap) * snap);
						FlxG.sound.music.time = Conductor.beatToSeconds(fuck);
					}
				}
			}

			var style = currentType;

			if (shiftHeld){
				style = 3;
			}

			var conductorTime = Conductor.songPosition; //+ sectionStartTime();Conductor.songPosition / Conductor.stepCrochet;

			//AWW YOU MADE IT SEXY <3333 THX SHADMAR

			if(!blockInput){
				if(FlxG.keys.justPressed.RIGHT){
					curQuant++;
					if(curQuant>quantizations.length-1)
						curQuant = 0;

					quantization = quantizations[curQuant];
				}

				if(FlxG.keys.justPressed.LEFT){
					curQuant--;
					if(curQuant<0)
						curQuant = quantizations.length-1;

					quantization = quantizations[curQuant];
				}
				quant.animation.play('q', true, false, curQuant);
			}
			if(vortex && !blockInput){
				var controlArray:Array<Bool> = [FlxG.keys.justPressed.ONE, FlxG.keys.justPressed.TWO, FlxG.keys.justPressed.THREE, FlxG.keys.justPressed.FOUR,
											   FlxG.keys.justPressed.FIVE, FlxG.keys.justPressed.SIX, FlxG.keys.justPressed.SEVEN, FlxG.keys.justPressed.EIGHT];

				if(controlArray.contains(true))
				{
					for (i in 0...controlArray.length)
					{
						if(controlArray[i])
							doANoteThing(conductorTime, i, style);
					}
				}

				var feces:Float;
				if (FlxG.keys.justPressed.UP || FlxG.keys.justPressed.DOWN)
				{
					FlxG.sound.music.pause();


					updateCurStep();
					//FlxG.sound.music.time = (Math.round(curStep/quants[curQuant])*quants[curQuant]) * Conductor.stepCrochet;

						//(Math.floor((curStep+quants[curQuant]*1.5/(quants[curQuant]/2))/quants[curQuant])*quants[curQuant]) * Conductor.stepCrochet;//snap into quantization
					var time:Float = FlxG.sound.music.time;
					var beat:Float = curDecBeat;
					var snap:Float = quantization / 4;
					var increase:Float = 1 / snap;
					if (FlxG.keys.pressed.UP)
					{
						var fuck:Float = CoolUtil.quantize(beat, snap) - increase;
						feces = Conductor.beatToSeconds(fuck);
					}else{
						var fuck:Float = CoolUtil.quantize(beat, snap) + increase; //(Math.floor((beat+snap) / snap) * snap);
						feces = Conductor.beatToSeconds(fuck);
					}
					FlxTween.tween(FlxG.sound.music, {time:feces}, 0.1, {ease:FlxEase.circOut});
					pauseAndSetVocalsTime();

					var dastrum = 0;

					if (curSelectedNote != null){
						dastrum = curSelectedNote[0];
					}

					var secStart:Float = sectionStartTime();
					var datime = (feces - secStart) - (dastrum - secStart); //idk math find out why it doesn't work on any other section other than 0
					if (curSelectedNote != null)
					{
						var controlArray:Array<Bool> = [FlxG.keys.pressed.ONE, FlxG.keys.pressed.TWO, FlxG.keys.pressed.THREE, FlxG.keys.pressed.FOUR,
													   FlxG.keys.pressed.FIVE, FlxG.keys.pressed.SIX, FlxG.keys.pressed.SEVEN, FlxG.keys.pressed.EIGHT];

						if(controlArray.contains(true))
						{

							for (i in 0...controlArray.length)
							{
								if(controlArray[i])
									if(curSelectedNote[1] == i) curSelectedNote[2] += datime - curSelectedNote[2] - Conductor.stepCrochet;
							}
							updateGrid();
							updateNoteUI();
						}
					}
				}
			}
			var shiftThing:Int = 1;
			if (shiftHeld)
				shiftThing = 4;

			if (FlxG.keys.justPressed.D || (_virtualpad != null && _virtualpad.buttonRight.justPressed))
				changeSection(curSec + shiftThing);
			if (FlxG.keys.justPressed.A || (_virtualpad != null && _virtualpad.buttonLeft.justPressed)) {
				if(curSec <= 0) {
					changeSection(_song.notes.length-1);
				} else {
					changeSection(curSec - shiftThing);
				}
			}
		} else if (FlxG.keys.justPressed.ENTER) {
			for (i in 0...blockPressWhileTypingOn.length) {
				if(blockPressWhileTypingOn[i].hasFocus) {
					blockPressWhileTypingOn[i].hasFocus = false;
				}
			}
		}

		strumLineNotes.visible = quant.visible = vortex;

		if(FlxG.sound.music.time < 0) {
			FlxG.sound.music.pause();
			FlxG.sound.music.time = 0;
		}
		else if(FlxG.sound.music.time > FlxG.sound.music.length) {
			FlxG.sound.music.pause();
			FlxG.sound.music.time = 0;
			changeSection();
		}
		Conductor.songPosition = FlxG.sound.music.time + Conductor.offset;
		strumLineUpdateY();
		// 播放时也应用相机水平跟随
		camPos.x = -80 + (GRID_SIZE * ((_song.mania + 1) * 2)) + trackScrollX;
		camPos.y = strumLine.y;
		if (strumLineNotes != null)
		{
			for (arrow in strumLineNotes)
			{
				if (arrow == null) continue;
				arrow.y = strumLine.y;
				arrow.alpha = FlxG.sound.music.playing ? 1 : 0.35;
			}
		}

		#if FLX_PITCH
		// PLAYBACK SPEED CONTROLS //
		var holdingShift = shiftHeld;
		var holdingLB = FlxG.keys.pressed.LBRACKET;
		var holdingRB = FlxG.keys.pressed.RBRACKET;
		var pressedLB = FlxG.keys.justPressed.LBRACKET;
		var pressedRB = FlxG.keys.justPressed.RBRACKET;

		if (!holdingShift && pressedLB || holdingShift && holdingLB)
			playbackSpeed -= 0.01;
		if (!holdingShift && pressedRB || holdingShift && holdingRB)
			playbackSpeed += 0.01;
		if (altHeld && (pressedLB || pressedRB || holdingLB || holdingRB))
			playbackSpeed = 1;
		//

		if (playbackSpeed <= 0.5)
			playbackSpeed = 0.5;
		if (playbackSpeed >= 3)
			playbackSpeed = 3;

		FlxG.sound.music.pitch = playbackSpeed;
		if (vocals != null) vocals.pitch = playbackSpeed;
		if (opponentVocals != null) opponentVocals.pitch = playbackSpeed;
		#end

		var songInfo:String =
		Std.string(FlxMath.roundDecimal(Conductor.songPosition / 1000, 2)) + " / " + Std.string(FlxMath.roundDecimal(FlxG.sound.music.length / 1000, 2)) +
		"\nSection: " + curSec +
		"\n\nBeat: " + Std.string(curDecBeat).substring(0,4) +
		"\nStep: " + curStep +
		"\n\nBeat Snap: " + quantization + "th" +
		"\nZoom: " + (zoomList[curZoom] >= 1 ? '1 / ' + zoomList[curZoom] : Math.round(1/zoomList[curZoom]) + ' / 1');
		// 降档期间常驻提示：这些音符会随谱面文件 / autosave 一起保存，升档即可原位还原
		var stashWarn:String = (stashedNotes.length > 0)
			? "\n\n! " + stashedNotes.length + " note(s) out of " + (_song.mania + 1) + "K"
			: "";
		bpmTxt.text = songInfo + stashWarn;
		// +2 跳过分隔用的两个换行；没有警示行时传 -1 表示撤掉格式
		updateStashWarnFormat(stashWarn.length > 0 ? songInfo.length + 2 : -1);

		var playedSound:Array<Bool> = []; //Prevents ouchy GF sex sounds（多键下按列数动态扩展）
		for (i in 0...(_song.mania + 1)) playedSound.push(false);
		curRenderedNotes.forEachAlive(function(note:Note) {
			note.alpha = 1;
			if(curSelectedNote != null) {
				var noteDataToCheck:Int = note.noteData;
				if(noteDataToCheck > -1 && note.mustPress != _song.notes[curSec].mustHitSection) noteDataToCheck += (_song.mania + 1);

				if (curSelectedNote[0] == note.strumTime && ((curSelectedNote[2] == null && noteDataToCheck < 0) || (curSelectedNote[2] != null && curSelectedNote[1] == noteDataToCheck)))
				{
					colorSine += elapsed;
					var colorVal:Float = 0.7 + Math.sin(Math.PI * colorSine) * 0.3;
					note.color = FlxColor.fromRGBFloat(colorVal, colorVal, colorVal, 0.999); //Alpha can't be 100% or the color won't be updated for some reason, guess i will die
				}
			}

			if(note.strumTime <= Conductor.songPosition) {
				note.alpha = 0.4;
				if(note.strumTime > lastConductorPos && FlxG.sound.music.playing && note.noteData > -1) {
					var data:Int = note.noteData % (_song.mania + 1);
					var noteDataToCheck:Int = note.noteData;
					if(noteDataToCheck > -1 && note.mustPress != _song.notes[curSec].mustHitSection) noteDataToCheck += (_song.mania + 1);
						strumLineNotes.members[noteDataToCheck].playAnim('confirm', true);
						strumLineNotes.members[noteDataToCheck].resetAnim = ((note.sustainLength / 1000) + 0.15) / playbackSpeed;
					if(!playedSound[data]) {
						if(note.hitsoundChartEditor && ((playSoundBf.checked && note.mustPress) || (playSoundDad.checked && !note.mustPress)))
						{
							var soundToPlay = note.hitsound;
							if(_song.player1 == 'gf') //Easter egg
								soundToPlay = 'GF_' + Std.string(data + 1);

							FlxG.sound.play(Paths.sound(soundToPlay)).pan = note.noteData < (_song.mania + 1)? -0.3 : 0.3; //would be coolio
							playedSound[data] = true;
						}

						data = note.noteData;
						if(note.mustPress != _song.notes[curSec].mustHitSection)
						{
							data += (_song.mania + 1);
						}
					}
				}
			}
		});

		if(metronome.checked && lastConductorPos != Conductor.songPosition) {
			var metroInterval:Float = 60 / metronomeStepper.value;
			var metroStep:Int = Math.floor(((Conductor.songPosition + metronomeOffsetStepper.value) / metroInterval) / 1000);
			var lastMetroStep:Int = Math.floor(((lastConductorPos + metronomeOffsetStepper.value) / metroInterval) / 1000);
			if(metroStep != lastMetroStep) {
				FlxG.sound.play(Paths.sound('Metronome_Tick'));
				//trace('Ticked');
			}
		}
		lastConductorPos = Conductor.songPosition;
		super.update(elapsed);
	}

	function pauseAndSetVocalsTime()
	{
		if(vocals != null)
		{
			vocals.pause();
			vocals.time = FlxG.sound.music.time;
		}
		
		if(opponentVocals != null)
		{
			opponentVocals.pause();
			opponentVocals.time = FlxG.sound.music.time;
		}
	}

	function updateZoom() {
		reloadGridLayer();
	}

	override function destroy()
	{
		Note.globalRgbShaders = [];
		backend.NoteTypesConfig.clearNoteTypesData();
		super.destroy();
	}

	var lastSecBeats:Float = 0;
	var lastSecBeatsNext:Float = 0;
	// Extra Keys：网格列数 = 双方轨道 + 事件列（4键 = 3*2+3 = 9，与原生一致）
	var columns:Int = 9;

	/**
	 * 降档时「暂时移出」谱面的音符 —— 绝不删除。
	 * 每项：{sec:Int, lane:Int(原始完整 lane), side:Bool(false=本节拍方侧), key:Int(侧内列), data:Array<Dynamic>}
	 * 侧内列与档位无关，因此只要目标档位装得下这个 key，就能按目标档位重算 lane 原位还原；
	 * 多级降档（6K→4K→6K）也能逐级还原。
	 *
	 * 持久化：本数组是工作副本，另有一份同步到 _song.editorStashedNotes（随谱面 JSON /
	 * autosave 落盘）和一份会话级静态副本（防 PlayState / Reload JSON 重建 SONG 后字段丢失）。
	 * 暂存项不进 sectionNotes、不参与 lane 编码、不进入试玩，只做警示渲染，
	 * 因此 _song.notes 的 lane 与 _song.mania 始终自洽。
	 */
	var stashedNotes:Array<Dynamic> = [];
	/** 暂存音符的警示渲染层（独立于 curRenderedNotes，避免干扰选中/删除命中） */
	var stashedRenderedNotes:FlxTypedGroup<Note>;

	/** 从谱面对象 / 会话兜底恢复暂存音符。谱面字段优先（跨重启、跨文件），会话副本兜底（切 state）。 */
	function restoreStashedNotes():Void
	{
		var songKey:String = (_song != null) ? Std.string(_song.song) : '';
		var fromSong:Array<Dynamic> = null;
		if (_song != null)
		{
			var raw:Dynamic = Reflect.field(_song, STASH_FIELD);
			if (raw != null) fromSong = sanitizeStashedNotes(raw);
		}
		if (fromSong != null && fromSong.length > 0)
			stashedNotes = fromSong;
		else
		{
			var cached:Array<Dynamic> = sessionStashBySong.get(songKey);
			stashedNotes = (cached != null && cached.length > 0)
				? sanitizeStashedNotes(haxe.Json.parse(haxe.Json.stringify(cached))) : [];
		}
		// 恢复后立刻回写，保证后续 Save / autosave 拿到的是同一份
		syncStashedNotes(songKey);
	}

	/**
	 * 把音符的 noteType 值规范化成引擎能稳定识别的字符串。
	 *
	 * 073 / 旧谱面里 [3] 可能是字符串类型名、旧式数字索引、null 或空串。
	 * 旧式数字索引必须在这里就转成名字：PlayState 与 Song.convert() 都是直接
	 * `Note.defaultNoteTypes[songNotes[3]]` 索引，遇到 null / 浮点索引会读不到值，
	 * 结果整支音符退化成默认类型（编辑器不显示编号、游戏里没有特殊效果）。
	 * 未知字符串原样保留（noteTypeLabel() 会画 '?'），越界数字保留原值文本。
	 */
	static function normalizeNoteType(v:Dynamic):String
	{
		if (v == null) return '';
		if (Std.isOfType(v, String)) return cast(v, String);
		var idx:Int = Std.int(v);
		if (idx >= 0 && idx < objects.Note.defaultNoteTypes.length)
			return objects.Note.defaultNoteTypes[idx];
		return Std.string(v);
	}

	/** 取暂存项里最可信的 noteType：显式 type 优先，data[3] 兜底，空串视为缺失。 */
	static function stashedNoteType(s:Dynamic):String
	{
		var t:String = Reflect.hasField(s, 'type') ? normalizeNoteType(Reflect.field(s, 'type')) : '';
		if (t.length > 0) return t;
		var data:Array<Dynamic> = Reflect.hasField(s, 'data') ? Reflect.field(s, 'data') : null;
		return (data != null && data.length > 3) ? normalizeNoteType(data[3]) : '';
	}

	/**
	 * 让暂存项的 type 与 data[3] 完全对齐，并保证 data 至少 4 项。
	 * 每次落盘 / 读回 / 渲染前都跑一遍：无论中间哪一步把第 4 项抹成 null、'' 或删掉，
	 * 都能从另一份冗余里救回来，升档还原时音符类型不会凭空消失。
	 */
	static function normalizeStashedNote(s:Dynamic):Void
	{
		if (s == null) return;
		var data:Array<Dynamic> = Reflect.hasField(s, 'data') ? Reflect.field(s, 'data') : null;
		if (data == null || !Std.isOfType(data, Array)) return;
		while (data.length < 3) data.push(null);
		var t:String = stashedNoteType(s);
		if (data.length < 4) data.push(t);
		else data[3] = t;
		Reflect.setField(s, 'type', t);
	}

	/** 校验外部读回的暂存数据：坏项直接跳过，避免 renderStashedNotes() 里空引用崩溃。
	 *  读回时立刻做一次 noteType 双向兜底，保证升档还原后音符类型不会消失。 */
	static function sanitizeStashedNotes(raw:Dynamic):Array<Dynamic>
	{
		var out:Array<Dynamic> = [];
		if (raw == null || !Std.isOfType(raw, Array)) return out;
		for (s in (cast raw:Array<Dynamic>))
		{
			if (s == null || s.sec == null || s.lane == null || s.key == null
				|| s.side == null || s.data == null || !Std.isOfType(s.data, Array))
				continue;
			normalizeStashedNote(s);
			out.push(s);
		}
		return out;
	}

	/**
	 * 把工作副本同步到谱面对象与会话兜底。所有改动 stashedNotes 的地方都要调一次。
	 * 深拷贝是为了让落盘副本与工作副本互不引用：undo 快照替换数组时不会误改 _song。
	 * 暂存为空时直接删掉字段 —— 正常谱面文件与 073 原版逐字节一致，零污染。
	 */
	function syncStashedNotes(?songKey:String):Void
	{
		if (_song == null) return;
		// 落盘前统一对齐 type / data[3]，保证写进 JSON 与 autosave 的每一支暂存音符
		// 都带着可识别的 noteType，不依赖第 4 项在中间环节是否还活着。
		for (s in stashedNotes) normalizeStashedNote(s);
		var key:String = (songKey != null) ? songKey : Std.string(_song.song);
		var copy:Array<Dynamic> = haxe.Json.parse(haxe.Json.stringify(stashedNotes));
		if (copy.length == 0)
			Reflect.deleteField(_song, STASH_FIELD);
		else
			Reflect.setField(_song, STASH_FIELD, copy);
		sessionStashBySong.set(key, copy);
	}

	/** 清空暂存（Clear notes / Clear song），同时抹掉落盘字段与会话兜底，避免幽灵音符复活。 */
	function clearStashedNotes():Void
	{
		stashedNotes = [];
		syncStashedNotes();
	}
	/** Song 页签的 Mania stepper，供 undo 同步显示值 */
	var maniaStepper:FlxUINumericStepper;
	/** undo 同步 stepper.value 时屏蔽其 CHANGE_EVENT，避免触发一次多余的重映射/压栈 */
	var suppressManiaEvent:Bool = false;
	/** mania stepper 存 0-based 索引；这个标签换算成实际每侧键数（5 -> "Mania (6K):"） */
	var maniaKeysLabel:FlxText;

	/** 刷新 mania 标签：实际键数 = stepper.value + 1。 */
	function refreshManiaKeysLabel():Void
	{
		if (maniaKeysLabel == null || maniaStepper == null) return;
		maniaKeysLabel.text = 'Mania (' + (Std.int(maniaStepper.value) + 1) + 'K):';
	}


	/**
	 * 改档真值镜像：key 是「音符数组对象本身」（引用），value 是改档前的
	 * strumTime 原值 + 规范化类型名。
	 *
	 * 用引用做 key 是零歧义的（remap 只改 note[1]、不重建留在谱面里的数组）；
	 * 旧方案用「小节 + strumTime」会和弦串位，日志实测误补 169 支 No Animation。
	 *
	 * 19:39:04 日志的决定性证据：升档「还原循环」里整谱 [3] 被写成 Int 0，同时
	 * [0] 的浮点 strumTime 被截断成 Int；更关键的是 heal 报告 healed=198，census 的
	 * Int:1240 却纹丝不动 —— 说明往这些数组里写 String 被静默吞成了 0（运行时
	 * 被当成整数数组）。所以 heal 不再原地赋值，而是一律新建一支显式
	 * Array<Dynamic> 替换引用，用改档前真值重建，彻底绕开隐式类型转换。
	 */
	var noteTypeMirror:haxe.ds.ObjectMap<Dynamic, {t0:Dynamic, type:String}> = new haxe.ds.ObjectMap();

	/** 抓全谱真值 —— 累积式，绝不覆盖已有的真值（升档时数据可能已被污染）。 */
	function captureNoteTypeMirror():Void
	{
		if (noteTypeMirror == null) noteTypeMirror = new haxe.ds.ObjectMap();
		if (_song == null || _song.notes == null) return;
		for (sec in _song.notes)
		{
			if (sec == null || sec.sectionNotes == null) continue;
			for (note in sec.sectionNotes)
			{
				if (note == null || note.length < 4 || note[1] == null || note[1] < 0) continue;
				if (noteTypeMirror.exists(note)) continue; // 已有真值，不动
				var t:String = normalizeNoteType(note[3]);
				if (t == '0') t = ''; // 旧式数字索引 / 污染占位，不是类型名
				// 空类型音符也登记：它们的 strumTime 同样会被截断，需要能重建
				noteTypeMirror.set(note, {t0: note[0], type: t});
			}
		}
	}

	/**
	 * 用镜像真值把被污染的音符整支重建为显式 Array<Dynamic>。返回重建数量。
	 * 绝不原地写 note[3] —— 日志已证实那条写入会被吞掉。
	 */
	function healNoteTypeMirror():Int
	{
		if (noteTypeMirror == null || _song == null || _song.notes == null) return 0;
		var fixed:Int = 0;
		for (sec in _song.notes)
		{
			if (sec == null || sec.sectionNotes == null) continue;
			var list:Array<Dynamic> = sec.sectionNotes;
			var freshList:Array<Dynamic> = [];
			var changed:Bool = false;
			for (note in list)
			{
				if (note == null || !noteTypeMirror.exists(note))
				{
					freshList.push(note);
					continue;
				}
				var truth = noteTypeMirror.get(note);
				if (truth == null) { freshList.push(note); continue; }
				var want:String = truth.type;
				var cur:String = (note.length > 3) ? normalizeNoteType(note[3]) : '';
				if (cur == '0') cur = '';
				// strumTime 从 Float 被截成 Int，是同一条污染路径留下的指纹
				var t0Damaged:Bool = (note.length > 0 && Std.isOfType(note[0], Int)
					&& truth.t0 != null && !Std.isOfType(truth.t0, Int));
				// 整数 0 或字符串 "0" 都是污染占位；字符串 "0" 尤其危险 ——
				// Song.convert() 对 String 直接放行，会一直残留到谱面文件里。
				var raw3:Dynamic = (note.length > 3) ? note[3] : null;
				var t3Polluted:Bool = (raw3 != null && Std.string(raw3) == '0');
				if (cur == want && !t0Damaged && !t3Polluted)
				{
					freshList.push(note);
					continue;
				}

				// 新建显式 Array<Dynamic>：保留当前值（lane 已被改档重编码，不能回退），
				// 只把被污染的两个字段换成真值。
				var fresh:Array<Dynamic> = [];
				for (k in 0...note.length) fresh.push(note[k]);
				while (fresh.length < 3) fresh.push(null);
				if (t0Damaged) fresh[0] = truth.t0;
				if (fresh.length < 4) fresh.push(want) else fresh[3] = want;
				freshList.push(fresh);
				if (curSelectedNote == note) curSelectedNote = fresh;
				// 引用换了，镜像 key 必须跟着换，否则下次 heal 找不到这支音符
				noteTypeMirror.remove(note);
				noteTypeMirror.set(fresh, {t0: fresh[0], type: want});
				changed = true;
				fixed++;
			}
			// 连容器一起换成显式 Array<Dynamic>：若 sectionNotes 自身是强类型容器，
			// 只替换元素仍可能被吞掉，整支换掉才彻底。
			if (changed) sec.sectionNotes = freshList;
		}
		return fixed;
	}

	/** 用户主动改类型 / 新建音符时同步镜像，避免下一次 heal 覆盖回旧值。 */
	function mirrorSetNoteType(note:Array<Dynamic>, v:Dynamic):Void
	{
		if (noteTypeMirror == null || note == null) return;
		var t:String = normalizeNoteType(v);
		if (t == '0') t = '';
		var t0:Dynamic = (note.length > 0) ? note[0] : 0;
		if (noteTypeMirror.exists(note))
		{
			var old = noteTypeMirror.get(note);
			if (old != null) t0 = old.t0; // 保留改档前的浮点 strumTime
		}
		noteTypeMirror.set(note, {t0: t0, type: t});
	}


	/** 诊断日志：只在 Windows 桌面上写文件，方便定位「类型在哪一步消失」。 */
	function dbgTypeLog(tag:String, extra:String = ''):Void
	{
		#if windows
		try
		{
			// 写到 exe 同目录，方便直接找到（工作目录不一定等于 exe 目录）
			var dir:String = '';
			try dir = haxe.io.Path.directory(Sys.programPath()) catch (e:Dynamic) {}
			var path:String = (dir.length > 0) ? (dir + '/notetype_debug.log') : 'notetype_debug.log';
			var head:String = '[' + Date.now().toString() + '] ' + tag + ' | ' + extra;
			var body:String = '';
			if (_song != null && _song.notes != null)
			{
				var total:Int = 0;
				var typed:Int = 0;
				var dist:Map<String, Int> = new Map();
				var kinds:Map<String, Int> = new Map();
				var samples:Array<String> = [];
				for (sec in _song.notes)
				{
					if (sec == null || sec.sectionNotes == null) continue;
					for (n in sec.sectionNotes)
					{
						total++;
						var v:Dynamic = (n.length > 3) ? n[3] : null;
						var sv:String = (v == null) ? '<null>' : Std.string(v);
						if (sv.length > 0 && sv != '<null>') typed++;
						dist.set(sv, (dist.exists(sv) ? dist.get(sv) : 0) + 1);
						var kind:String = (v == null) ? 'null'
							: Std.isOfType(v, String) ? 'String'
							: Std.isOfType(v, Int) ? 'Int'
							: Std.isOfType(v, Float) ? 'Float'
							: Std.isOfType(v, Bool) ? 'Bool' : 'Other';
						kinds.set(kind, (kinds.exists(kind) ? kinds.get(kind) : 0) + 1);
						if (samples.length < 3)
							samples.push('[t=' + Std.string(n[0]) + ',lane=' + Std.string(n[1]) + ',sus=' + Std.string(n[2]) + ',3=' + sv + '(' + kind + '),len=' + n.length + ']');
					}
				}
				var parts:Array<String> = [];
				for (k in dist.keys()) parts.push('"' + k + '"x' + dist.get(k));
				var kparts:Array<String> = [];
				for (k in kinds.keys()) kparts.push(k + ':' + kinds.get(k));
				body = '  notes=' + total + ' typed=' + typed + ' kinds={' + kparts.join(',') + '} | ' + parts.join(' ')
					+ '\n  samples: ' + samples.join(' ');
			}
			var prev:String = sys.FileSystem.exists(path) ? sys.io.File.getContent(path) : '';
			sys.io.File.saveContent(path, prev + head + '\n' + body + '\n');
		}
		catch (e:Dynamic) {}
		#end
	}

	/**
	 * 切换键数档位时对谱面音符做「可逆重编码」，绝不删除任何音符。
	 *
	 * 073 的 lane 是相对当前键数编码的（0..cols-1 = 本节拍方侧，cols..2cols-1 = 对方侧），
	 * 所以改档必须重编码。旧实现把 keyIdx > newMania 的音符直接 drop，导致 6K→5K→6K 后
	 * 玩家侧第 6 列与对方侧第 6 列永久丢失（保存后重开仍缺）。这里改为：
	 *   1) 先把谱面里现有的音符按 oldCols -> newCols 重映射，保持「侧 + 侧内列」语义；
	 *      目标档位装不下的，连同原始 lane / 小节 / 侧 / 侧内列暂存到 stashedNotes。
	 *   2) 再把 stashedNotes 里目标档位能容纳的音符按目标档位重算 lane，放回原小节。
	 * 顺序必须是「先重映射、后还原」，否则刚放回的音符会被二次重映射算错侧。
	 * 暂存记录的是「侧 + 侧内列」而不是 lane，因此多级降档（6K→4K→6K）能逐级还原；
	 * 降档期间新放的音符按当前档位编码进 _song.notes，也不会与旧音符混编码。
	 */
	function remapChartNotesForMania(oldMania:Int, newMania:Int):Void
	{
		var oldCols:Int = oldMania + 1;
		var newCols:Int = newMania + 1;

		// 降档前先在独立副本里记一份全谱类型：后续任何一步（重映射 / 试玩转换 / 重载）
		// 把 [3] 洗成空串，升档回来都能按小节+时间点补回。
		captureNoteTypeMirror();
		dbgTypeLog('  [remap] 进入/抓取镜像', 'old=' + oldMania + ' new=' + newMania);

		// 1) 重映射现有音符；超范围的暂存而不是丢弃
		for (secIdx in 0..._song.notes.length)
		{
			var section = _song.notes[secIdx];
			if (section == null || section.sectionNotes == null) continue;
			var kept:Array<Dynamic> = [];
			for (note in section.sectionNotes)
			{
				var lane:Int = note[1];
				if (lane < 0) { kept.push(note); continue; } // 事件列 / inline event
				var isPlr:Bool = lane < oldCols;
				var keyIdx:Int = isPlr ? lane : (lane - oldCols);
				if (keyIdx > newMania)
				{
					// 完全自包含的快照：data 用副本（不再与 sectionNotes 共享引用），
					// type 是规范化后的 noteType 字符串。两者互为冗余，任一被抹掉都能互相恢复。
					stashedNotes.push({sec: secIdx, lane: lane, side: isPlr, key: keyIdx,
						type: (note.length > 3 ? normalizeNoteType(note[3]) : ''), data: note.copy()});
					continue;
				}
				note[1] = isPlr ? keyIdx : (newCols + keyIdx);
				kept.push(note);
			}
			section.sectionNotes = kept;
		}

		// 2) 还原目标档位能容纳的暂存音符
		dbgTypeLog('  [remap] 重映射循环后', 'kept + stash done');
		if (stashedNotes.length == 0)
		{
			var n1:Int = healNoteTypeMirror();
			dbgTypeLog('  [remap] 无暂存/heal后', 'healed=' + n1);
			return;
		}
		var stillStashed:Array<Dynamic> = [];
		var touched:Map<Int, Bool> = new Map();
		for (s in stashedNotes)
		{
			if (s.key > newMania) { stillStashed.push(s); continue; }
			var secIdx:Int = s.sec;
			if (secIdx < 0 || secIdx >= _song.notes.length || _song.notes[secIdx] == null
				|| _song.notes[secIdx].sectionNotes == null)
			{
				// 小节已被删掉：继续暂存，绝不丢数据
				stillStashed.push(s);
				continue;
			}
			var src:Array<Dynamic> = s.data;
			while (src.length < 3) src.push(null);
			// 显式重建音符数组：第 4 项一定来自规范化后的 noteType 冗余，不再隐式依赖
			// src[3] 在暂存期间是否幸存。旧写法直接 push 原数组引用，只要 [3] 被任何
			// 路径写成 null / ''，升档后箭头编号与游戏内的特殊效果就会一起消失。
			// 第 5 项起的扩展字段（Leather 谱面的 [4] 类型等）原样保留。
			var rebuilt:Array<Dynamic> = [src[0], s.side ? s.key : (newCols + s.key),
				src[2], stashedNoteType(s)];
			for (k in 4...src.length) rebuilt.push(src[k]);
			_song.notes[secIdx].sectionNotes.push(rebuilt);
			// 立刻按引用登记真值：日志证实「还原循环」随后会把这批新数组的 [3]
			// 也写成 Int 0，等循环结束后再补登记就只能记到污染值了。
			noteTypeMirror.set(rebuilt, {t0: src[0], type: stashedNoteType(s)});
			// 数组是新建的：若用户降档前正选中这支音符，把选中引用一起指过去，
			// 否则之后改 sustain / strum time 会写到一个已不在谱面里的旧数组上。
			if (curSelectedNote == src) curSelectedNote = rebuilt;
			touched.set(secIdx, true);
		}
		stashedNotes = stillStashed;
		for (idx in touched.keys())
			_song.notes[idx].sectionNotes.sort(function(a, b) return (a[0] < b[0]) ? -1 : ((a[0] > b[0]) ? 1 : 0));
		dbgTypeLog('  [remap] 还原循环后', 'stashed=' + stashedNotes.length);
		syncStashedNotes();
		dbgTypeLog('  [remap] syncStashedNotes 后', '');
		// 还原出来的 rebuilt 是新数组，镜像里没有它：立刻登记，防止之后被外部路径写成 0。
		for (sec in _song.notes)
		{
			if (sec == null || sec.sectionNotes == null) continue;
			for (note in sec.sectionNotes)
				if (note != null && note.length > 3 && !noteTypeMirror.exists(note))
					mirrorSetNoteType(note, note[3]);
		}
		var n2:Int = healNoteTypeMirror();
		dbgTypeLog('  [remap] heal后', 'healed=' + n2);
	}

	/**
	 * 把「当前谱面键数」同步到 Note / Extra Keys 的全局静态档位。
	 *
	 * 073 的 updateGrid() 每次都 new Note(...)，而 Note 构造时：
	 *   - 动画帧前缀取 colAt(noteData) -> 全局静态 Note.colArray
	 *   - RGB / HSV 取色取 styleIndex(noteData) -> Note.uiManiaOverride / PlayState.SONG.mania
	 * 073 原先只同步了 PlayState.SONG.mania，从未同步 Note.colArray。这个全局表由
	 * PlayState.applyMania() 或新版 ChartingState.applySectionColumns() 设置，直接打开 073
	 * 时它往往仍是上一次 State 的档位（常见是 4 键 ['purple','blue','green','red']）。
	 * 于是改 mania 后音符的数量/位置按新键数变了，帧前缀却仍按 %4 循环成四方向箭头；
	 * 且 arrowRGB / arrowHSV 未补齐到 18 色时，高列 initializeGlobalRGBShader() 读不到
	 * 颜色会退回默认洋红/绿/蓝 —— 这就是「新放的、实际可玩的箭头显示不正常」。
	 * 进 PlayState 会调 applyMania() 重设全局表并补齐色表，所以试玩回来（或再重进制谱器）
	 * 就恢复正常；重开进程又可能变回去。
	 *
	 * 做法：按 PlayState.applyMania() / 新版 applySectionColumns() 的同一规则生成 colArray，
	 * 补齐 18 色，钉住编辑侧档；在任何 new Note() / new StrumNote() 之前调用即可。
	 */
	function syncChartManiaGlobals():Void
	{
		var mania:Int = (_song.mania != null) ? _song.mania : 3;
		var laneCount:Int = mania + 1;

		ExtraKeysHandler.ensure();
		// 幂等：补齐 arrowRGB / arrowRGBPixel / arrowHSV 到 18 色，缺色时多键音符会显示成默认三原色
		ClientPrefs.ensureEKArrowColors();

		if (PlayState.SONG != null) PlayState.SONG.mania = mania;
		Note.uiManiaOverride = -1;
		Note.editorDualMode = false;
		Note.editorPlrKeys = laneCount;
		Note.editorOppKeys = laneCount;

		var cols:Array<String> = [];
		var ek = (ExtraKeysHandler.instance != null) ? ExtraKeysHandler.instance.data : null;
		if (ek != null && ek.keys != null && ek.keys.length > mania)
		{
			var mode = ek.keys[mania];
			for (i in 0...laneCount)
			{
				var g:Int = (mode != null && mode.notes != null && i < mode.notes.length) ? mode.notes[i] : i;
				var anim = (ek.animations != null && g >= 0 && g < ek.animations.length) ? ek.animations[g] : null;
				cols.push((anim != null && anim.note != null) ? anim.note : 'purple');
			}
		}
		else cols = ['purple', 'blue', 'green', 'red'];

		Note.colArray = cols;
	}

	/**
	 * 重建 Vortex 判定线的静态箭头：数量、位置，以及最容易被漏掉的「多键贴图档位」。
	 *
	 * StrumNote.reloadNote() 的帧前缀（LEFT/DOWN/UP/RIGHT/ROMBUS/CIRCLE…）不是按本类的
	 * _song.mania 取，而是按 Note.uiManiaOverride -> PlayState.SONG.mania ->
	 * 编辑器侧档(Note.editorPlrKeys / editorOppKeys) 取档。073 从未初始化这几个全局态，
	 * 新版制谱器 / 颜色菜单退出后可能残留旧档（常见是 4 键档），于是改 mania 时
	 * 箭头数量按 _song.mania 变了，贴图却仍停在 4K 方向。
	 *
	 * 做法：重建期间把编辑器侧档钉在当前键数（该分支优先级最高，同时修正取色与
	 * shader 绑定），重建完把全局态归位到 073 应有的干净值，避免污染其它 State。
	 */
	function rebuildStrumLineNotes():Void
	{
		if (strumLineNotes == null) return;

		// 旧箭头必须真正销毁：clear() 只摘除引用，残留对象仍持有共享 shader / 动画
		for (arrow in strumLineNotes)
			if (arrow != null) arrow.destroy();
		strumLineNotes.clear();

		// SONG.mania 是流动音符的取档来源，保持为新键数（不要恢复成旧值）
		if (PlayState.SONG != null) PlayState.SONG.mania = _song.mania;

		Note.uiManiaOverride = -1;
		Note.editorDualMode = true;
		Note.editorPlrKeys = _song.mania + 1;
		Note.editorOppKeys = _song.mania + 1;

		for (i in 0...((_song.mania + 1) * 2))
		{
			var arrow:StrumNote = new StrumNote(GRID_SIZE * (i + 1), strumLine.y, i % (_song.mania + 1), 0);
			arrow.setGraphicSize(GRID_SIZE, GRID_SIZE);
			arrow.updateHitbox();
			arrow.playAnim('static', true);
			arrow.scrollFactor.set(1, 1);
			strumLineNotes.add(arrow);
		}

		// 归位到 073 的干净默认：非双侧、无 UI 档位覆盖，侧档数值与当前键数一致。
		// 原本残留的脏全局态就此清掉；新版制谱器进入时会自行重设这几个字段。
		Note.uiManiaOverride = -1;
		Note.editorDualMode = false;
		Note.editorPlrKeys = _song.mania + 1;
		Note.editorOppKeys = _song.mania + 1;

		strumLineNotes.visible = strumLineNotes.active = vortex;
		// reloadGridLayer() 每次 add(strumLine) 会把判定线放到最上层，箭头组要重新置顶
		remove(strumLineNotes);
		add(strumLineNotes);
	}

	function reloadGridLayer() {
		// 对齐 Minty 新版：mania 改变时同步到 PlayState.SONG（确保运行态按键映射正确）
		if (PlayState.SONG == null) {
			PlayState.SONG = {
				song: 'DUMMY',
				notes: [],
				events: [],
				bpm: 1,
				offset: 0,
				mania: _song.mania,
				needsVoices: true,
				player1: 'bf',
				player2: 'bf',
				gfVersion: 'bf',
				speed: 1,
				stage: 'stage',
				format: 'mrek_v0.0.1',
			};
		} else {
			PlayState.SONG.mania = _song.mania;
		}
		// 改键数 / 缩放 / section beats 变化时先重同步全局档位，再重建任何 Note / StrumNote
		syncChartManiaGlobals();

		// 对齐 Minty 新版：mania 改变时重建左右 icon 位置
		var gridLaneMidPoint:Float = (GRID_SIZE * (_song.mania + 1)) / 2;
		var leftIconX:Float = (GRID_SIZE + gridLaneMidPoint) - (leftIcon.width / 2);
		var rightIconX:Float = leftIconX + (GRID_SIZE * (_song.mania + 1));
		leftIcon.setPosition(leftIconX, -100);
		rightIcon.setPosition(rightIconX, -100);

		columns = (_song.mania * 2) + 3;
		gridLayer.clear();
		gridBG = FlxGridOverlay.create(1, 1, columns, Std.int(getSectionBeats() * 4 * zoomList[curZoom]));
		gridBG.antialiasing = false;
		gridBG.scale.set(GRID_SIZE, GRID_SIZE);
		gridBG.updateHitbox();

		#if desktop
		if(FlxG.save.data.chart_waveformInst || FlxG.save.data.chart_waveformVoices || FlxG.save.data.chart_waveformOppVoices) {
			updateWaveform();
		}
		#end

		var leHeight:Int = Std.int(gridBG.height);
		var foundNextSec:Bool = false;
		if(sectionStartTime(1) <= FlxG.sound.music.length)
		{
			nextGridBG = FlxGridOverlay.create(1, 1, columns, Std.int(getSectionBeats(curSec + 1) * 4 * zoomList[curZoom]));
			nextGridBG.antialiasing = false;
			nextGridBG.scale.set(GRID_SIZE, GRID_SIZE);
			nextGridBG.updateHitbox();
			leHeight = Std.int(gridBG.height + nextGridBG.height);
			foundNextSec = true;
		}
		else nextGridBG = new FlxSprite().makeGraphic(1, 1, FlxColor.TRANSPARENT);
		nextGridBG.y = gridBG.height;
		
		gridLayer.add(nextGridBG);
		gridLayer.add(gridBG);

		if(foundNextSec)
		{
			var gridBlack:FlxSprite = new FlxSprite(0, gridBG.height).makeGraphic(1, 1, FlxColor.BLACK);
			gridBlack.setGraphicSize(Std.int(GRID_SIZE * columns), Std.int(nextGridBG.height));
			gridBlack.updateHitbox();
			gridBlack.antialiasing = false;
			gridBlack.alpha = 0.4;
			gridLayer.add(gridBlack);
		}

		var gridBlackLine:FlxSprite = new FlxSprite(gridBG.x + gridBG.width - (GRID_SIZE * (_song.mania + 1))).makeGraphic(1, 1, FlxColor.BLACK);
		gridBlackLine.setGraphicSize(2, leHeight);
		gridBlackLine.updateHitbox();
		gridBlackLine.antialiasing = false;
		gridLayer.add(gridBlackLine);

		for (i in 1...Std.int(getSectionBeats())) {
			var beatsep:FlxSprite = new FlxSprite(gridBG.x, (GRID_SIZE * (4 * zoomList[curZoom])) * i).makeGraphic(1, 1, 0x44FF0000);
			beatsep.scale.x = gridBG.width;
			beatsep.updateHitbox();
			if(vortex) gridLayer.add(beatsep);
		}

		// 对齐 Minty 新版：先重建 strumLine 与 quant 跟踪，再画左侧分隔线
		remove(strumLine);
		strumLine = new FlxSprite(0, 50).makeGraphic(Std.int(GRID_SIZE * columns), 4);
		add(strumLine);
		quant.sprTracker = strumLine;

		// 数量、位置与多键贴图档位统一由 rebuildStrumLineNotes() 重建
		rebuildStrumLineNotes();

		var gridBlackLineLeft:FlxSprite = new FlxSprite(gridBG.x + GRID_SIZE).makeGraphic(1, 1, FlxColor.BLACK);
		gridBlackLineLeft.setGraphicSize(2, leHeight);
		gridBlackLineLeft.updateHitbox();
		gridBlackLineLeft.antialiasing = false;
		gridLayer.add(gridBlackLineLeft);

		updateGrid();

		lastSecBeats = getSectionBeats();
		if(sectionStartTime(1) > FlxG.sound.music.length) lastSecBeatsNext = 0;
		else getSectionBeats(curSec + 1);
	}

	function strumLineUpdateY()
	{
		var raw:Float = (Conductor.songPosition - sectionStartTime()) / zoomList[curZoom];
		var mod:Float = Conductor.stepCrochet * 16;
		// 刚切 section 时 songPosition 可能 < sectionStartTime()，原生 % 会返回负值，
		// 导致 strumLine 跳到错误位置。用数学取模把它折回 [0, mod)。
		var pos:Float = ((raw % mod) + mod) % mod;
		strumLine.y = getYfromStrum(pos) / (getSectionBeats() / 4);
	}

	var waveformPrinted:Bool = true;
	var wavData:Array<Array<Array<Float>>> = [[[0], [0]], [[0], [0]]];

	function updateWaveform() {
		#if desktop
		var width:Int = Std.int(GRID_SIZE * ((_song.mania + 1) * 2));
		var height:Int = Std.int(gridBG.height);

		/**
		 * 位图尺寸每次都要核对，且不能只按 height 缓存。
		 * width 随 mania（列数）变化，但 gridBG.height 只由 sectionBeats / zoom 决定；
		 * 073 原版仅在 lastWaveformHeight != height 时重建，改档时位图仍是旧宽度，
		 * 而清屏 fillRect 与波形绘制都按新的 gSize 算，超出旧位图右边界的部分被裁掉
		 * —— 看起来像隔了一层空气墙。重进编辑器时缓存归零才重建，所以「重进就好了」。
		 * 这里直接以位图自身尺寸为准，且不受 waveformPrinted（上次是否画过）影响，
		 * 顺带修掉「关着波形改档、之后再开启波形」时依旧裁切的情况。
		 */
		if (waveformSprite != null)
		{
			var pixels = waveformSprite.pixels;
			if (pixels == null || pixels.width != width || pixels.height != height)
			{
				if (pixels != null)
				{
					pixels.dispose();
					pixels.disposeImage();
				}
				waveformSprite.makeGraphic(width, height, 0x00FFFFFF);
			}
		}

		if(waveformPrinted) {
			waveformSprite.pixels.fillRect(new Rectangle(0, 0, width, height), 0x00FFFFFF);
		}
		waveformPrinted = false;

		if(!FlxG.save.data.chart_waveformInst && !FlxG.save.data.chart_waveformVoices && !FlxG.save.data.chart_waveformOppVoices) {
			//trace('Epic fail on the waveform lol');
			return;
		}

		wavData[0][0] = [];
		wavData[0][1] = [];
		wavData[1][0] = [];
		wavData[1][1] = [];

		var steps:Int = Math.round(getSectionBeats() * 4);
		var st:Float = sectionStartTime();
		var et:Float = st + (Conductor.stepCrochet * steps);

		var sound:FlxSound = FlxG.sound.music;
		if(FlxG.save.data.chart_waveformVoices)
			sound = vocals;
		else if(FlxG.save.data.chart_waveformOppVoices)
			sound = opponentVocals;
		
		if (sound != null && sound._sound != null && sound._sound.__buffer != null) {
			var bytes:Bytes = sound._sound.__buffer.data.toBytes();

			wavData = waveformData(
				sound._sound.__buffer,
				bytes,
				st,
				et,
				1,
				wavData,
				Std.int(gridBG.height)
			);
		}

		// Draws
		var gSize:Int = width; // 与位图宽度同源：中心点 hSize 不会和位图右边界错位
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

			waveformSprite.pixels.fillRect(new Rectangle(hSize - (lmin + rmin), index * size, (lmin + rmin) + (lmax + rmax), size), FlxColor.BLUE);
		}

		waveformPrinted = true;
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

	function changeNoteSustain(value:Float):Void
	{
		if (curSelectedNote != null)
		{
			pushUndo();
			if (curSelectedNote[2] != null)
			{
				curSelectedNote[2] += Math.ceil(value);
				curSelectedNote[2] = Math.max(curSelectedNote[2], 0);
			}
		}

		updateNoteUI();
		updateGrid();
	}

	function recalculateSteps(add:Float = 0):Int
	{
		var lastChange:BPMChangeEvent = {
			stepTime: 0,
			songTime: 0,
			bpm: 0
		}
		for (i in 0...Conductor.bpmChangeMap.length)
		{
			if (FlxG.sound.music.time > Conductor.bpmChangeMap[i].songTime)
				lastChange = Conductor.bpmChangeMap[i];
		}

		curStep = lastChange.stepTime + Math.floor((FlxG.sound.music.time - lastChange.songTime + add) / Conductor.stepCrochet);
		updateBeat();

		return curStep;
	}

	function resetSection(songBeginning:Bool = false):Void
	{
		updateGrid();

		FlxG.sound.music.pause();
		// Basically old shit from changeSection???
		FlxG.sound.music.time = sectionStartTime();

		if (songBeginning)
		{
			FlxG.sound.music.time = 0;
			curSec = 0;
		}

		pauseAndSetVocalsTime();
		updateCurStep();

		updateGrid();
		updateSectionUI();
		updateWaveform();
	}

	function changeSection(sec:Int = 0, ?updateMusic:Bool = true):Void
	{
		var waveformChanged:Bool = false;
		if (_song.notes[sec] != null)
		{
			curSec = sec;
			if (updateMusic)
			{
				FlxG.sound.music.pause();

				FlxG.sound.music.time = sectionStartTime();
				pauseAndSetVocalsTime();
				updateCurStep();
			}

			var blah1:Float = getSectionBeats();
			var blah2:Float = getSectionBeats(curSec + 1);
			if(sectionStartTime(1) > FlxG.sound.music.length) blah2 = 0;
	
			if(blah1 != lastSecBeats || blah2 != lastSecBeatsNext)
			{
				reloadGridLayer();
				waveformChanged = true;
			}
			else
			{
				updateGrid();
			}
			updateSectionUI();
		}
		else
		{
			changeSection();
		}
		Conductor.songPosition = FlxG.sound.music.time + Conductor.offset;
		if(!waveformChanged) updateWaveform();
	}

	function updateSectionUI():Void
	{
		var sec = _song.notes[curSec];

		stepperBeats.value = getSectionBeats();
		check_mustHitSection.checked = sec.mustHitSection;
		check_gfSection.checked = sec.gfSection;
		check_altAnim.checked = sec.altAnim;
		check_changeBPM.checked = sec.changeBPM;
		stepperSectionBPM.value = sec.bpm;

		updateHeads();
	}

	var characterData:Dynamic = {
		iconP1: null,
		iconP2: null,
		vocalsP1: null,
		vocalsP2: null
	};

	function updateJsonData():Void
	{
		for (i in 1...3)
		{
			var data:CharacterFile = loadCharacterFile(Reflect.field(_song, 'player$i'));
			Reflect.setField(characterData, 'iconP$i', !characterFailed ? data.healthicon : 'face');
			Reflect.setField(characterData, 'vocalsP$i', data.vocals_file != null ? data.vocals_file : '');
		}
	}

	function updateHeads():Void
	{
		if (_song.notes[curSec].mustHitSection)
		{
			leftIcon.changeIcon(characterData.iconP1);
			rightIcon.changeIcon(characterData.iconP2);
			if (_song.notes[curSec].gfSection) leftIcon.changeIcon('gf');
		}
		else
		{
			leftIcon.changeIcon(characterData.iconP2);
			rightIcon.changeIcon(characterData.iconP1);
			if (_song.notes[curSec].gfSection) leftIcon.changeIcon('gf');
		}
	}

	var characterFailed:Bool = false;
	function loadCharacterFile(char:String):CharacterFile {
		characterFailed = false;
		var characterPath:String = 'characters/' + char + '.json';
		#if MODS_ALLOWED
		var path:String = Paths.modFolders(characterPath);
		if (!FileSystem.exists(path)) {
			path = Paths.getSharedPath(characterPath);
		}

		if (!FileSystem.exists(path))
		#else
		var path:String = Paths.getSharedPath(characterPath);
		if (!OpenFlAssets.exists(path))
		#end
		{
			path = Paths.getSharedPath('characters/' + Character.DEFAULT_CHARACTER + '.json'); //If a character couldn't be found, change him to BF just to prevent a crash
			characterFailed = true;
		}

		#if MODS_ALLOWED
		var rawJson = File.getContent(path);
		#else
		var rawJson = OpenFlAssets.getText(path);
		#end
		return cast Json.parse(rawJson);
	}

	function updateNoteUI():Void
	{
		if (curSelectedNote != null) {
			if(curSelectedNote[2] != null) {
				stepperSusLength.value = curSelectedNote[2];
				// 统一走只读解析：旧式数字索引与字符串都能映射到下拉列表，
				// 避免「箭头上有编号、选中后 Note type 却显示为空」的假丢失。
				// 也不再依赖 curSelectedNote[3] != null，选中无类型音符时会清掉上一次的残留显示。
				var typeName:String = resolveNoteTypeName(curSelectedNote);
				currentType = curNoteTypes.indexOf(typeName);
				if (currentType > 0)
					noteTypeDropDown.selectedLabel = currentType + '. ' + typeName;
				else
					noteTypeDropDown.selectedLabel = '';
			} else {
				eventDropDown.selectedLabel = curSelectedNote[1][curEventSelected][0];
				var selected:Int = Std.parseInt(eventDropDown.selectedId);
				if(selected > 0 && selected < eventStuff.length) {
					descText.text = eventStuff[selected][1];
				}
				value1InputText.text = curSelectedNote[1][curEventSelected][1];
				value2InputText.text = curSelectedNote[1][curEventSelected][2];
			}
			strumTimeInputText.text = '' + curSelectedNote[0];
		}
	}

	function updateGrid():Void
	{
		// 073 里谱面音符只在这里创建。全局静态可能被 PlayState / 新版制谱器 / 颜色菜单改写，
		// 所以每次重建前都核对一次档位，保证 new Note() 读到当前 mania 的帧前缀与色表。
		syncChartManiaGlobals();

		// 重建前按引用镜像恢复被外部路径写成 0 / 空串的 noteType。
		// 放在 setupNoteData() 之前，保证本帧的编号标签与下拉框读到的都是正确值。
		healNoteTypeMirror();

		curRenderedNotes.forEachAlive(function(spr:Note) spr.destroy());
		curRenderedNotes.clear();
		curRenderedSustains.forEachAlive(function(spr:FlxSprite) spr.destroy());
		curRenderedSustains.clear();
		curRenderedNoteType.forEachAlive(function(spr:FlxText) spr.destroy());
		curRenderedNoteType.clear();
		nextRenderedNotes.forEachAlive(function(spr:Note) spr.destroy());
		nextRenderedNotes.clear();
		nextRenderedSustains.forEachAlive(function(spr:FlxSprite) spr.destroy());
		nextRenderedSustains.clear();

		if (_song.notes[curSec].changeBPM && _song.notes[curSec].bpm > 0)
		{
			Conductor.bpm = _song.notes[curSec].bpm;
			//trace('BPM of this section:');
		}
		else
		{
			// get last bpm
			var daBPM:Float = _song.bpm;
			for (i in 0...curSec)
				if (_song.notes[i].changeBPM)
					daBPM = _song.notes[i].bpm;
			Conductor.bpm = daBPM;
		}

		// CURRENT SECTION
		var beats:Float = getSectionBeats();
		for (i in _song.notes[curSec].sectionNotes)
		{
			var note:Note = setupNoteData(i, false);
			curRenderedNotes.add(note);
			if (note.sustainLength > 0)
			{
				curRenderedSustains.add(setupSusNote(note, beats));
			}

			// noteType 标签：已知类型显示编号，预设不存在/越界索引显示 '?'，默认空类型不画。
			// noteTypeLabel() 只读解析，绝不改写 i[3]，保存时谱面数据保持原样。
			var typeLabel:String = noteTypeLabel(i);
			if (typeLabel.length > 0)
				curRenderedNoteType.add(makeNoteLabel(typeLabel, note));
			note.mustPress = _song.notes[curSec].mustHitSection;
			if(i[1] > _song.mania) note.mustPress = !note.mustPress;
		}

		// CURRENT EVENTS
		var startThing:Float = sectionStartTime();
		var endThing:Float = sectionStartTime(1);
		for (i in _song.events)
		{
			if(endThing > i[0] && i[0] >= startThing)
			{
				var note:Note = setupNoteData(i, false);
				curRenderedNotes.add(note);

				var text:String = 'Event: ' + note.eventName + ' (' + Math.floor(note.strumTime) + ' ms)' + '\nValue 1: ' + note.eventVal1 + '\nValue 2: ' + note.eventVal2;
				if(note.eventLength > 1) text = note.eventLength + ' Events:\n' + note.eventName;

				var daText:AttachedFlxText = new AttachedFlxText(0, 0, 400, text, 12);
				daText.setFormat(Paths.font("vcr.ttf"), 12, FlxColor.WHITE, RIGHT, FlxTextBorderStyle.OUTLINE_FAST, FlxColor.BLACK);
				daText.xAdd = -410;
				daText.borderSize = 1;
				if(note.eventLength > 1) daText.yAdd += 8;
				curRenderedNoteType.add(daText);
				daText.sprTracker = note;
				//trace('test: ' + i[0], 'startThing: ' + startThing, 'endThing: ' + endThing);
			}
		}

		// NEXT SECTION
		var beats:Float = getSectionBeats(1);
		if(curSec < _song.notes.length-1) {
			for (i in _song.notes[curSec+1].sectionNotes)
			{
				var note:Note = setupNoteData(i, true);
				note.alpha = 0.6;
				nextRenderedNotes.add(note);
				if (note.sustainLength > 0)
				{
					nextRenderedSustains.add(setupSusNote(note, beats));
				}
			}
		}

		// NEXT EVENTS
		var startThing:Float = sectionStartTime(1);
		var endThing:Float = sectionStartTime(2);
		for (i in _song.events)
		{
			if(endThing > i[0] && i[0] >= startThing)
			{
				var note:Note = setupNoteData(i, true);
				note.alpha = 0.6;
				nextRenderedNotes.add(note);
			}
		}

		// 超范围音符照常按原始 lane 画出来并加警示（独立于 curRenderedNotes）
		renderStashedNotes();
	}

	/**
	 * 只读解析音符的 noteType 名字（交给 new Note 用），绝不改写原始数组。
	 *
	 * 073 原版 setupNoteData() 会把旧式数字索引就地转成字符串写回 i[3]，空值还会
	 * i.remove(i[3]) 把第 4 项整个删掉 —— 每次重绘网格都在悄悄改写谱面数据，
	 * 保存时异常 noteType / 旧格式的 [3] 就无法保持原样。这里统一改为只读解析。
	 */
	function resolveNoteTypeName(raw:Array<Dynamic>):String
	{
		if (raw == null || raw.length < 4) return '';
		var v:Dynamic = raw[3];
		if (v == null) return '';
		if (!Std.isOfType(v, String))
		{
			var idx:Int = Std.int(v);
			return (idx >= 0 && idx < curNoteTypes.length) ? curNoteTypes[idx] : '';
		}
		return cast(v, String);
	}

	/**
	 * 音符的 noteType 标签文本：
	 *   ''  = 默认/空类型，不画标签
	 *   '?' = 类型异常（预设不存在、越界数字索引、未知字符串）
	 *   '3' = 已知类型在下拉列表中的编号
	 * 数字索引先按 curNoteTypes 解析，解析得出来就按正常类型处理、解析不出来才算异常，
	 * 这样改档重绘不会平白让每个音符都扣一个 '?'。全程只读，不回写谱面数据。
	 */
	function noteTypeLabel(raw:Array<Dynamic>):String
	{
		// 类型列表还没建好时不要急着判定「异常」，否则会把每个音符都误标成 '?'
		if (curNoteTypes.length == 0) return '';
		if (raw == null || raw.length < 4) return '';
		var v:Dynamic = raw[3];
		if (v == null) return '';

		var name:String = '';
		if (Std.isOfType(v, String))
			name = cast(v, String);
		else
		{
			var idx:Int = Std.int(v);
			if (idx < 0 || idx >= curNoteTypes.length) return '?';
			name = curNoteTypes[idx];
		}
		if (name.length < 1) return '';
		var typeInt:Int = curNoteTypes.indexOf(name);
		if (typeInt < 0) return '?'; // 预设不存在：真正的 noteType 异常
		return (typeInt > 0) ? '' + typeInt : '';
	}

	/** 统一的 noteType / 警示标签：24px vcr 白字 + 1px 黑描边，居中贴在音符上 */
	function makeNoteLabel(text:String, note:Note):AttachedFlxText
	{
		var t:AttachedFlxText = new AttachedFlxText(0, 0, 100, text, 24);
		t.setFormat(Paths.font("vcr.ttf"), 24, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE_FAST, FlxColor.BLACK);
		t.xAdd = (GRID_SIZE - 100) / 2; // 100 宽 CENTER -> 文本中心正好落在箭头中心
		t.yAdd = 6;
		t.borderSize = 1;
		t.sprTracker = note;
		return t;
	}

	/**
	 * 把暂存的超范围音符按「原始 lane 位置」照常渲染，并加警示染色 + '!' 叠加标签。
	 *
	 * 染色必须走 Note 自己的着色通道：RGB 模式按 [橙主体, 白高光, 深橙描边] 三通道
	 * 着色（与普通箭头预设的层次一致）；HSV 模式（ColorSwap 只能做色相/亮度偏移，
	 * 凑不出纯橙）改用本地 ColorSwap 压成纯黑剪影。直接设 FlxSprite.color 是乘色，
	 * 会被箭头 shader 吃掉，结果仍是各方向原色。
	 *
	 * 警示 '!' 不再单独画在右上角，而是与 noteType 标签拼成一个居中文本：
	 *   异常 noteType -> '?!'，已知类型 -> '3!'，默认空类型 -> '!'
	 *
	 * 用独立的 stashedRenderedNotes 组、不进 curRenderedNotes：这样不会干扰既有
	 * 的选中/删除命中（update() 按 curSelectedNote 匹配 curRenderedNotes），也不会
	 * 被误当作当前谱面里可编辑的音符。它们只是「数据还在，但当前档位装不下」的提示。
	 * 警示标签复用 curRenderedNoteType，updateGrid() 开头会统一销毁重建。
	 */
	function renderStashedNotes():Void
	{
		if (stashedRenderedNotes == null) return;
		stashedRenderedNotes.forEachAlive(function(spr:Note) spr.destroy());
		stashedRenderedNotes.clear();
		if (stashedNotes.length == 0) return;

		for (s in stashedNotes)
		{
			var secIdx:Int = s.sec;
			// 与 curRenderedNotes / nextRenderedNotes 的可见范围保持一致
			if (secIdx != curSec && secIdx != curSec + 1) continue;

			var raw:Array<Dynamic> = s.data;
			// 完整复制原始音符数组（含第 4 项 noteType 与之后的扩展字段），只替换 lane。
			// setupNoteData() 只读，不会回写 raw。
			var copy:Array<Dynamic> = raw.copy();
			while (copy.length < 3) copy.push(null);
			copy[1] = s.lane;
			while (copy.length < 4) copy.push('');
			// 标签与 Note.noteType 都从规范化冗余取，避免 raw[3] 被污染时「3!」退化成「!」
			copy[3] = stashedNoteType(s);
			var note:Note = setupNoteData(copy, false);
			applyStashedWarningColor(note);
			stashedRenderedNotes.add(note);
			// 长条也照常画出来（同样染成警示色），否则会只剩一个孤零零的箭头
			if (note.sustainLength > 0)
			{
				var sus:FlxSprite = setupSusNote(note, getSectionBeats());
				sus.color = stashedSusColor();
				curRenderedSustains.add(sus);
			}

			// 警示 '!' 与 noteType 标签合成一个居中文本，样式与普通音符的 '?' 标签完全一致：
			//   异常 noteType -> '?!'，已知类型 -> '3!'，默认空类型 -> '!'
			curRenderedNoteType.add(makeNoteLabel(noteTypeLabel(copy) + '!', note));
		}
	}

	/** 当前箭头是否走 HSV（ColorSwap）着色，而不是 RGB 调色板 */
	function usingHSVNoteColors():Bool
		return ClientPrefs.data.arrowColorMode == 'HSV';

	/** 警示长条跟随箭头：RGB 模式纯橙，HSV 模式纯黑 */
	function stashedSusColor():FlxColor
		return usingHSVNoteColors() ? FlxColor.BLACK : STASHED_NOTE_ORANGE;

	/**
	 * 暂存警示箭头染色 —— 按当前着色模式分支，绝不污染全局共享 shader。
	 *
	 * RGB 模式：Note 的箭头贴图由 RGBPalette 接管（红/绿/蓝通道分别映射成 r/g/b 三色）。
	 *   照搬正常箭头预设 [主体色, 白高光, 深色描边] 的结构，只把主体换成橙：
	 *   r = 纯橙、g = 白、b = 深橙。三通道全橙会让箭头发平、失去立体感。
	 *   直接新建一份本地 RGBPalette 并重建 rgbShader 引用，完全不碰全局共享实例，
	 *   同 style 的正常音符颜色不会被带歪。
	 * HSV 模式：ColorSwap 是「色相/饱和度/亮度」偏移，无论如何都凑不出纯橙；
	 *   改挂一个本地 ColorSwap，brightness = -1 使 V *= (1 + brightness) = 0，得到纯黑剪影。
	 *   必须新建本地实例 —— 构造时挂的是全局共享 ColorSwap，直接改它会影响所有音符。
	 * 两条分支都把 FlxSprite.color 复位为白色，避免旧的橙红乘色再叠一层导致发暗。
	 */
	function applyStashedWarningColor(note:Note):Void
	{
		if (note == null) return;
		if (usingHSVNoteColors())
		{
			var swap:shaders.ColorSwap = new shaders.ColorSwap();
			swap.hue = 0;
			swap.saturation = 0;
			swap.brightness = -1.0;
			note.colorSwap = swap;
			note.shader = swap.shader;
			note.color = FlxColor.WHITE;
		}
		else
		{
			// RGB：给这支警示箭头挂一份**完全本地**的 RGBPalette，按正常箭头的三通道
			// 层次上色（橙主体 / 白高光 / 深橙描边）。
			// 不直接写 note.rgbShader.r=... 的原因：RGBShaderReference 只在「新值 != 原色」
			// 时才 cloneOriginal()，万一某列主色恰好也是这个橙，就会直接写进全局共享
			// palette，把同 style 的正常音符一起染橙。本地 palette 彻底隔离、零污染。
			var pal:shaders.RGBPalette = new shaders.RGBPalette();
			pal.r = STASHED_NOTE_ORANGE;
			pal.g = STASHED_NOTE_HIGHLIGHT;
			pal.b = STASHED_NOTE_ORANGE_DARK;
			var ref:shaders.RGBPalette.RGBShaderReference = new shaders.RGBPalette.RGBShaderReference(note, pal);
			ref.allowNew = false; // parent 已是本地调色板，后续 setter 不必再 clone
			note.rgbShader = ref; // defaultRGB()/set_enabled() 也只会操作这份本地 palette
			note.shader = pal.shader;
			note.color = FlxColor.WHITE;
		}
	}

	function setupNoteData(i:Array<Dynamic>, isNextSection:Bool):Note
	{
		var daNoteInfo = i[1];
		var daStrumTime = i[0];
		var daSus:Dynamic = i[2];

		var note:Note = new Note(daStrumTime, daNoteInfo % (_song.mania + 1), null, null, true);
		if(daSus != null) { //Common note
			// 只读解析 noteType：073 原版会把旧式数字索引就地转成字符串写回 i[3]，
			// 空值还会 i.remove(i[3]) 删掉第 4 项。那样每次重绘网格都在改写谱面数据，
			// 保存时异常 noteType / 旧格式的 [3] 就保持不了原样。这里绝不回写 i。
			note.sustainLength = daSus;
			note.noteType = resolveNoteTypeName(i);
		} else { //Event note
			note.loadGraphic(Paths.image('editors/eventIcon'));
			note.rgbShader.enabled = false;
			note.eventName = getEventName(i[1]);
			note.eventLength = i[1].length;
			if(i[1].length < 2)
			{
				note.eventVal1 = i[1][0][1];
				note.eventVal2 = i[1][0][2];
			}
			note.noteData = -1;
			daNoteInfo = -1;
		}

		note.setGraphicSize(GRID_SIZE, GRID_SIZE);
		note.updateHitbox();
		note.x = Math.floor(daNoteInfo * GRID_SIZE) + GRID_SIZE;
		if(isNextSection && _song.notes[curSec].mustHitSection != _song.notes[curSec+1].mustHitSection) {
			if(daNoteInfo > _song.mania) {
				note.x -= GRID_SIZE * (_song.mania + 1);
			} else if(daSus != null) {
				note.x += GRID_SIZE * (_song.mania + 1);
			}
		}

		var beats:Float = getSectionBeats(isNextSection ? 1 : 0);
		note.y = getYfromStrumNotes(daStrumTime - sectionStartTime(), beats);
		//if(isNextSection) note.y += gridBG.height;
		if(note.y < -150) note.y = -150;
		return note;
	}

	function getEventName(names:Array<Dynamic>):String
	{
		var retStr:String = '';
		var addedOne:Bool = false;
		for (i in 0...names.length)
		{
			if(addedOne) retStr += ', ';
			retStr += names[i][0];
			addedOne = true;
		}
		return retStr;
	}

	function setupSusNote(note:Note, beats:Float):FlxSprite {
		var height:Int = Math.floor(FlxMath.remapToRange(note.sustainLength, 0, Conductor.stepCrochet * 16, 0, GRID_SIZE * 16 * zoomList[curZoom]) + (GRID_SIZE * zoomList[curZoom]) - GRID_SIZE / 2);
		var minHeight:Int = Std.int((GRID_SIZE * zoomList[curZoom] / 2) + GRID_SIZE / 2);
		if(height < minHeight) height = minHeight;
		if(height < 1) height = 1; //Prevents error of invalid height

		var spr:FlxSprite = new FlxSprite(note.x + (GRID_SIZE * 0.5) - 4, note.y + GRID_SIZE / 2).makeGraphic(8, height);
		return spr;
	}

	private function addSection(sectionBeats:Float = 4):Void
	{
		var sec:SwagSection = {
			sectionBeats: sectionBeats,
			bpm: _song.bpm,
			changeBPM: false,
			mustHitSection: true,
			gfSection: false,
			sectionNotes: [],
			altAnim: false
		};

		_song.notes.push(sec);
	}

	function selectNote(note:Note):Void
	{
		var noteDataToCheck:Int = note.noteData;

		if(noteDataToCheck > -1)
		{
			if(note.mustPress != _song.notes[curSec].mustHitSection) noteDataToCheck += (_song.mania + 1);
			for (i in _song.notes[curSec].sectionNotes)
			{
				if (i != curSelectedNote && i.length > 2 && i[0] == note.strumTime && i[1] == noteDataToCheck)
				{
					curSelectedNote = i;
					break;
				}
			}
		}
		else
		{
			for (i in _song.events)
			{
				if(i != curSelectedNote && i[0] == note.strumTime)
				{
					curSelectedNote = i;
					curEventSelected = Std.int(curSelectedNote[1].length) - 1;
					break;
				}
			}
		}
		changeEventSelected();

		updateGrid();
		updateNoteUI();
	}

	function deleteNote(note:Note):Void
	{
		pushUndo();

		var noteDataToCheck:Int = note.noteData;
		if(noteDataToCheck > -1 && note.mustPress != _song.notes[curSec].mustHitSection) noteDataToCheck += (_song.mania + 1);

		if(note.noteData > -1) //Normal Notes
		{
			for (i in _song.notes[curSec].sectionNotes)
			{
				if (i[0] == note.strumTime && i[1] == noteDataToCheck)
				{
					if(i == curSelectedNote) curSelectedNote = null;
					//FlxG.log.add('FOUND EVIL NOTE');
					_song.notes[curSec].sectionNotes.remove(i);
					break;
				}
			}
		}
		else //Events
		{
			for (i in _song.events)
			{
				if(i[0] == note.strumTime)
				{
					if(i == curSelectedNote)
					{
						curSelectedNote = null;
						changeEventSelected();
					}
					//FlxG.log.add('FOUND EVIL EVENT');
					_song.events.remove(i);
					break;
				}
			}
		}

		updateGrid();
	}

	public function doANoteThing(cs, d, style){
		var delnote = false;
		if(strumLineNotes.members[d].overlaps(curRenderedNotes))
		{
			curRenderedNotes.forEachAlive(function(note:Note)
			{
				if (note.overlapsPoint(new FlxPoint(strumLineNotes.members[d].x + 1,strumLine.y+1)) && note.noteData == d%(_song.mania + 1))
				{
						//trace('tryin to delete note...');
						if(!delnote) deleteNote(note);
						delnote = true;
				}
			});
		}

		if (!delnote){
			addNote(cs, d, style);
		}
	}
	function clearSong():Void
	{
		pushUndo();
		for (daSection in 0..._song.notes.length)
		{
			_song.notes[daSection].sectionNotes = [];
		}
		// 清空音符时暂存也要一起清，否则改档后幽灵音符会重新冒出来
		clearStashedNotes();

		updateGrid();
	}

	private function addNote(strum:Null<Float> = null, data:Null<Int> = null, type:Null<Int> = null):Void
	{
		pushUndo();

		//curUndoIndex++;
		//var newsong = _song.notes;
		//	undos.push(newsong);
		var noteStrum = getStrumTime(dummyArrow.y * (getSectionBeats() / 4), false) + sectionStartTime();
		var noteData:Int = Math.floor((FlxG.mouse.x - GRID_SIZE) / GRID_SIZE);
		var noteSus = 0;
		var daAlt = false;
		var daType = currentType;

		if (strum != null) noteStrum = strum;
		if (data != null) noteData = data;
		if (type != null) daType = type;

		// 边界钳制：合法轨道 0..(mania+1)*2-1，事件列 -1。
		// 鼠标在 grid 右边缘外 / vortex 小键盘按到不存在的高键时不再写入越轨 lane。
		var maxLane:Int = (_song.mania + 1) * 2 - 1;
		if (noteData > maxLane) noteData = maxLane;
		if (noteData < -1) noteData = -1;

		if(noteData > -1)
		{
			_song.notes[curSec].sectionNotes.push([noteStrum, noteData, noteSus, curNoteTypes[daType]]);
			curSelectedNote = _song.notes[curSec].sectionNotes[_song.notes[curSec].sectionNotes.length - 1];
		}
		else
		{
			var event = eventStuff[Std.parseInt(eventDropDown.selectedId)][0];
			var text1 = value1InputText.text;
			var text2 = value2InputText.text;
			_song.events.push([noteStrum, [[event, text1, text2]]]);
			curSelectedNote = _song.events[_song.events.length - 1];
			curEventSelected = 0;
		}
		changeEventSelected();

		if (FlxG.keys.pressed.CONTROL && noteData > -1)
		{
			_song.notes[curSec].sectionNotes.push([noteStrum, (noteData + (_song.mania + 1)) % ((_song.mania + 1) * 2), noteSus, curNoteTypes[daType]]);
		}

		//trace(noteData + ', ' + noteStrum + ', ' + curSec);
		strumTimeInputText.text = '' + curSelectedNote[0];

		updateGrid();
		updateNoteUI();
	}

	// === Undo / Redo（快照式：深拷贝 notes + events）===
	// 旧版这里是空壳（注释掉了），现在补齐。所有会改谱面的操作前先 pushUndo()。
	var undoHistory:Array<Dynamic> = [];
	var redoHistory:Array<Dynamic> = [];
	var UNDO_MAX:Int = 100;

	/** 快照必须连 mania 与暂存音符一起存：否则 undo 后谱面 lane 编码与档位会错开，
	 *  暂存音符也可能重复（既在 notes 里又留在 stashed 里）。 */
	function makeSnapshot():Dynamic
	{
		return {
			notes: haxe.Json.parse(haxe.Json.stringify(_song.notes)),
			events: haxe.Json.parse(haxe.Json.stringify(_song.events)),
			mania: _song.mania,
			stashed: haxe.Json.parse(haxe.Json.stringify(stashedNotes))
		};
	}

	function pushUndo():Void
	{
		redoHistory = [];
		undoHistory.push(makeSnapshot());
		if (undoHistory.length > UNDO_MAX) undoHistory.shift();
	}

	function applySnapshot(snap:Dynamic):Void
	{
		_song.notes = snap.notes;
		_song.events = snap.events;
		// undo / redo 是深拷贝替换 _song.notes，谱面里每支音符都是新数组对象，
		// 之前按引用建立的镜像 key 全部失效。快照是改档前 pushUndo() 抓的、数据干净，
		// 立刻重新登记一次（累积式，不会覆盖已有真值），否则 undo 之后再改档就无从恢复。
		captureNoteTypeMirror();
		stashedNotes = (snap.stashed != null) ? sanitizeStashedNotes(snap.stashed) : [];
		syncStashedNotes();
		if (snap.mania != null)
		{
			_song.mania = snap.mania;
			if (Reflect.hasField(_song, 'keyCount'))
				Reflect.setField(_song, 'keyCount', snap.mania + 1);
			// stepper.value 的 setter 会派发 CHANGE_EVENT，用标志挡掉，避免把一次
			// 「同步 UI 显示值」误当成用户改档而再跑一次重映射 / 压栈
			if (maniaStepper != null)
			{
				suppressManiaEvent = true;
				maniaStepper.value = snap.mania;
				suppressManiaEvent = false;
			}
			refreshManiaKeysLabel(); // undo 同步 UI 后标签也要跟着变
		}
		Conductor.mapBPMChanges(_song);
		// 兜底：undo 到空谱面时至少保留一个空 section，避免 updateGrid 空引用
		if (_song.notes == null || _song.notes.length == 0)
		{
			_song.notes = [];
			addSection();
		}
		if (curSec < 0) curSec = 0;
		if (curSec >= _song.notes.length) curSec = _song.notes.length - 1;
		curSelectedNote = null;
		reloadGridLayer();
		updateSectionUI();
		updateNoteUI();
	}

	function redo():Void
	{
		if (redoHistory.length == 0) return;
		var snap:Dynamic = redoHistory.pop();
		undoHistory.push(makeSnapshot());
		if (undoHistory.length > UNDO_MAX) undoHistory.shift();
		applySnapshot(snap);
	}

	function undo():Void
	{
		if (undoHistory.length == 0) return;
		var snap:Dynamic = undoHistory.pop();
		redoHistory.push(makeSnapshot());
		if (redoHistory.length > UNDO_MAX) redoHistory.shift();
		applySnapshot(snap);
	}

	function getStrumTime(yPos:Float, doZoomCalc:Bool = true):Float
	{
		var leZoom:Float = zoomList[curZoom];
		if(!doZoomCalc) leZoom = 1;
		return FlxMath.remapToRange(yPos, gridBG.y, gridBG.y + gridBG.height * leZoom, 0, 16 * Conductor.stepCrochet);
	}

	function getYfromStrum(strumTime:Float, doZoomCalc:Bool = true):Float
	{
		var leZoom:Float = zoomList[curZoom];
		if(!doZoomCalc) leZoom = 1;
		return FlxMath.remapToRange(strumTime, 0, 16 * Conductor.stepCrochet, gridBG.y, gridBG.y + gridBG.height * leZoom);
	}
	
	function getYfromStrumNotes(strumTime:Float, beats:Float):Float
	{
		var value:Float = strumTime / (beats * 4 * Conductor.stepCrochet);
		return GRID_SIZE * beats * 4 * zoomList[curZoom] * value + gridBG.y;
	}

	function getNotes():Array<Dynamic>
	{
		var noteData:Array<Dynamic> = [];

		for (i in _song.notes)
		{
			noteData.push(i.sectionNotes);
		}

		return noteData;
	}

	var missingText:FlxText;
	var missingTextTimer:FlxTimer;
	function loadJson(song:String):Void
	{
		//shitty null fix, i fucking hate it when this happens
		//make it look sexier if possible
		try {
			if (Difficulty.getString() != Difficulty.getDefault()) {
				if(Difficulty.getString() == null){
					PlayState.SONG = Song.loadFromJson(song.toLowerCase(), song.toLowerCase());
				}else{
					PlayState.SONG = Song.loadFromJson(song.toLowerCase() + "-" + Difficulty.getString(), song.toLowerCase());
				}
			}
			else PlayState.SONG = Song.loadFromJson(song.toLowerCase(), song.toLowerCase());
			MusicBeatState.resetState();
		}
		catch(e)
		{
			trace('ERROR! $e');

			var errorStr:String = e.toString();
			if(errorStr.startsWith('[file_contents,assets/data/')) errorStr = 'Missing file: ' + errorStr.substring(27, errorStr.length-1); //Missing chart
			
			if(missingText == null)
			{
				missingText = new FlxText(50, 0, FlxG.width - 100, '', 24);
				missingText.setFormat(Paths.font("vcr.ttf"), 24, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
				missingText.scrollFactor.set();
				add(missingText);
			}
			else missingTextTimer.cancel();

			missingText.text = 'ERROR WHILE LOADING CHART:\n$errorStr';
			missingText.screenCenter(Y);

			missingTextTimer = new FlxTimer().start(5, function(tmr:FlxTimer) {
				remove(missingText);
				missingText.destroy();
			});
			FlxG.sound.play(Paths.sound('cancelMenu'));
		}
	}

	/** Enter 键：切到 PlayState 试玩（从按键分支抽出，供确认框回调使用） */
	function goPlayState():Void
	{
		autosaveSong();
		FlxG.mouse.visible = false;
		PlayState.SONG = prepareSongForPlayState();
		FlxG.sound.music.stop();
		if(vocals != null) vocals.stop();
		if(opponentVocals != null) opponentVocals.stop();
		StageData.loadDirectory(_song);
		LoadingState.loadAndSwitchState(new PlayState());
	}

	/**
	 * 只把 bpmTxt 末尾「! N note(s) out of XK」这一行染成橙色，其余行保持白色。
	 *
	 * bpmTxt.text 每帧都会重写，但 FlxText 的 set_text 不会清 _formatRanges ——
	 * 若每帧直接 addFormat() 会让格式范围数组无限增长。所以缓存一份 FlxTextFormat，
	 * 只在「范围确实变了」时才 clearFormats() + addFormat() 重设一次；没有警示行时
	 * 只清一次。FlxTextFormat 的 font / size 为 null，OpenFL 的 TextFormat.__merge()
	 * 只在非 null 时覆盖，因此 arturito-slab 字体、16px、LEFT 对齐都不受影响。
	 *
	 * @param start 警示行首字符在 bpmTxt.text 中的索引；-1 = 当前没有警示行
	 */
	function updateStashWarnFormat(start:Int):Void
	{
		if (start < 0)
		{
			if (stashWarnStart >= 0)
			{
				bpmTxt.clearFormats();
				stashWarnStart = -1;
				stashWarnEnd = -1;
			}
			return;
		}

		var end:Int = bpmTxt.text.length;
		if (start == stashWarnStart && end == stashWarnEnd) return;

		bpmTxt.clearFormats();
		if (stashWarnFormat == null) stashWarnFormat = new FlxTextFormat(STASHED_INFO_ORANGE);
		bpmTxt.addFormat(stashWarnFormat, start, end);
		stashWarnStart = start;
		stashWarnEnd = end;
	}

	/**
	 * 保存 / 试玩前的确认：提醒当前档位装不下这些音符，但它们不会丢 ——
	 * 会随谱面 JSON / autosave 一起保存，刷新 state 或重开后仍在，升档即可原位还原；
	 * 只有试玩不带入（超范围 lane 在 PlayState 会越界）。
	 * 无暂存、或勾选「Ignore Progress Warnings」时直接执行，零弹窗 —— 与 073 原版的
	 * Reload JSON / Clear notes 等进度警告共用同一个 ignoreWarnings 开关。
	 */
	function confirmChartMania(action:Void->Void):Void
	{
		if (stashedNotes.length == 0 || ignoreWarnings)
		{
			action();
			return;
		}
		var secs:Map<Int, Bool> = new Map();
		for (s in stashedNotes)
		{
			var secIdx:Int = s.sec;
			secs.set(secIdx, true);
		}
		var secCount:Int = 0;
		for (k in secs.keys()) secCount++;

		openSubState(new Prompt(
			stashedNotes.length + ' note(s) are outside the current ' + (_song.mania + 1) + 'K layout'
			+ '\n(spread over ' + secCount + ' section(s)).\n\n'
			+ 'They are kept: saved into the chart JSON and autosave,\n'
			+ 'restored after a state reload, and put back in place\n'
			+ 'when you raise Mania again.\n'
			+ 'Only playtest will skip them.\n\nProceed anyway?',
			0, action, null, false, 'PROCEED', 'CANCEL'));
	}

	function autosaveSong():Void
	{
		// 保证 autosave 里带上最新的暂存音符：没点 Save 就退出 / 重启也能通过 Load Autosave 找回
		syncStashedNotes();
		var hs:Int = healNoteTypeMirror();
		dbgTypeLog('AUTOSAVE 写盘前', 'stash=' + stashedNotes.length + ' healed=' + hs);
		FlxG.save.data.autosave = haxe.Json.stringify({
			"song": _song
		});
		FlxG.save.flush();
	}

	/**
	 * The editor keeps the chart in the 0.7.3 layout, but `PlayState` only understands psych_v1.
	 * Upgrade it right before leaving; coming back re-runs `create()`, which downgrades it again.
	 */
	function prepareSongForPlayState():SwagSong
	{
		// LegacyChartFormat.toPsychV1() -> Song.convert() 会**原地**改写 lane 与 [3]。
		// 旧写法直接传 _song，等于把试玩用的转换结果留在编辑器正在编辑的数据上：
		// 回来后音符类型可能被写成空串，编号与游戏内特殊效果一起消失。
		// 改成深拷贝（与 openEditorPlayState 一致），编辑器数据零污染；副本仍带
		// editorStashedNotes，回到编辑器时 create() 能正常读回暂存。
		healNoteTypeMirror();
		var song:SwagSong = cast haxe.Json.parse(haxe.Json.stringify(_song));
		LegacyChartFormat.toPsychV1(song);
		return song;
	}

	/**
	 * 1.0 风格的「在编辑器网格内试听」：打开 `EditorPlayState` 子状态而不是切到 `PlayState`。
	 * 用一份 psych_v1 克隆，绝不改动编辑器里正在编辑的 `_song`。
	 */
	function openEditorPlayState():Void
	{
		if (FlxG.sound.music == null)
		{
			trace('No music loaded, cannot playtest.');
			return;
		}

		healNoteTypeMirror();
		var song:SwagSong = cast haxe.Json.parse(haxe.Json.stringify(_song));
		Song.convert(song);
		song.format = 'psych_v1_convert';

		PlayState.SONG = song;
		PlayState.stageUI = 'normal';
		PlayState.uiPrefix = '';
		PlayState.uiPostfix = '';

		var noteList:Array<Note> = [];
		for (section in song.notes)
		{
			if (section == null || section.sectionNotes == null) continue;
			for (raw in section.sectionNotes)
			{
				var strumTime:Float = raw[0];
				var data:Int = raw[1];
				if (data < 0) continue; // inline event
				var sustain:Float = raw[2];
				var noteType:String = (raw[3] != null) ? raw[3] : '';
				var col:Int = data % (_song.mania + 1);
				var mustPress:Bool = (data < (_song.mania + 1));
				var n:Note = new Note(strumTime, col, null, false, true);
				n.mustPress = mustPress;
				n.sustainLength = sustain;
				n.noteType = noteType;
				noteList.push(n);
			}
		}

		if (FlxG.sound.music != null) FlxG.sound.music.pause();
		Conductor.songPosition = 0;
		openSubState(new EditorPlayState(noteList, [vocals, opponentVocals]));
	}

	function clearEvents() {
		pushUndo();
		_song.events = [];
		updateGrid();
	}

	private function saveLevel()
	{
		// 让 _song.editorStashedNotes 与当前工作副本一致；暂存为空时字段已被删掉，导出文件保持原样
		syncStashedNotes();
		var hs2:Int = healNoteTypeMirror();
		dbgTypeLog('SAVE 保存前', 'mania=' + _song.mania + ' stash=' + stashedNotes.length + ' healed=' + hs2);
		if(_song.events != null && _song.events.length > 1) _song.events.sort(sortByTime);
		// 标记谱面出处（仅元信息，不参与玩法逻辑）
		_song.generatedBy = GENERATED_BY;
		// 旧版制谱器（0.7.3）输出不含引擎扩展字段：format（版本标记）
		Reflect.deleteField(_song, "format");
		var json = {
			"song": _song
		};

		var data:String = haxe.Json.stringify(json, "\t");

		if ((data != null) && (data.length > 0))
		{
			#if mobile
			// 移动端：静默写入外部存储，并提示保存路径
			var saveName:String = Paths.formatToSongPath(_song.song) + "_073.json";
			StorageUtil.saveContent(saveName, data.trim(), false);
			CoolUtil.showPopUp('File saved successfully to: ' + StorageUtil.getExternalStorageDirectory() + 'saves/' + saveName, 'Success!');
			#else
			// 桌面/网页：文件选择框，保存后不弹信息（仅日志记录）
			_file = new FileReference();
			_file.addEventListener(#if desktop Event.SELECT #else Event.COMPLETE #end, onSaveComplete);
			_file.addEventListener(Event.CANCEL, onSaveCancel);
			_file.addEventListener(IOErrorEvent.IO_ERROR, onSaveError);
			_file.save(data.trim(), Paths.formatToSongPath(_song.song) + "_073.json");
			#end
		}
	}

	function sortByTime(Obj1:Array<Dynamic>, Obj2:Array<Dynamic>):Int
	{
		return FlxSort.byValues(FlxSort.ASCENDING, Obj1[0], Obj2[0]);
	}

	private function saveEvents()
	{
		if(_song.events != null && _song.events.length > 1) _song.events.sort(sortByTime);
		var eventsSong:Dynamic = {
			events: _song.events
		};
		var json = {
			"song": eventsSong
		}

		var data:String = haxe.Json.stringify(json, "\t");

		if ((data != null) && (data.length > 0))
		{
			#if mobile
			var saveName:String = "events_073.json";
			StorageUtil.saveContent(saveName, data.trim(), false);
			CoolUtil.showPopUp('File saved successfully to: ' + StorageUtil.getExternalStorageDirectory() + 'saves/' + saveName, 'Success!');
			#else
			_file = new FileReference();
			_file.addEventListener(#if desktop Event.SELECT #else Event.COMPLETE #end, onSaveComplete);
			_file.addEventListener(Event.CANCEL, onSaveCancel);
			_file.addEventListener(IOErrorEvent.IO_ERROR, onSaveError);
			_file.save(data.trim(), "events_073.json");
			#end
		}
	}

	function onSaveComplete(_):Void
	{
		_file.removeEventListener(Event.COMPLETE, onSaveComplete);
		_file.removeEventListener(Event.CANCEL, onSaveCancel);
		_file.removeEventListener(IOErrorEvent.IO_ERROR, onSaveError);
		_file = null;
		FlxG.log.notice("Successfully saved LEVEL DATA.");
	}

	/**
	 * Called when the save file dialog is cancelled.
	 */
	function onSaveCancel(_):Void
	{
		_file.removeEventListener(Event.COMPLETE, onSaveComplete);
		_file.removeEventListener(Event.CANCEL, onSaveCancel);
		_file.removeEventListener(IOErrorEvent.IO_ERROR, onSaveError);
		_file = null;
	}

	/**
	 * Called if there is an error while saving the gameplay recording.
	 */
	function onSaveError(_):Void
	{
		_file.removeEventListener(Event.COMPLETE, onSaveComplete);
		_file.removeEventListener(Event.CANCEL, onSaveCancel);
		_file.removeEventListener(IOErrorEvent.IO_ERROR, onSaveError);
		_file = null;
		FlxG.log.error("Problem saving Level data");
	}

	function getSectionBeats(?section:Null<Int> = null)
	{
		if (section == null) section = curSec;
		var val:Null<Float> = null;
		
		if(_song.notes[section] != null) val = _song.notes[section].sectionBeats;
		return val != null ? val : 4;
	}
}
