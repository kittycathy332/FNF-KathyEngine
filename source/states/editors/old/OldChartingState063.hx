package states.editors.old;

// #if desktop
// import backend.Discord.DiscordClient;
// #end
import flash.geom.Rectangle;
import haxe.Json;
import mobile.backend.StorageUtil;
import haxe.format.JsonParser;
import haxe.io.Bytes;
import backend.Conductor.BPMChangeEvent;
import backend.Song;
import backend.StageData;
import backend.Mods;
import backend.CoolUtil;
import backend.ExtraKeysHandler;
import backend.ui.StyledButton;
import backend.ui.StyledButtonStyle;
import objects.Character;
import objects.Character.CharacterFile;
import objects.HealthIcon;
import objects.Note;
import objects.StrumNote;
import objects.AttachedSprite;
import states.PlayState;
import states.LoadingState;
import states.editors.MasterEditorMenu;
import states.editors.content.EditorPlayState;
import states.editors.old.content.AttachedFlxText;
import states.editors.old.content.FlxUIDropDownMenuCustom;
import states.editors.old.content.LegacyChartFormat;
import states.editors.old.content.OldEditorState;
import states.editors.old.content.OldSlider;
import states.editors.old.content.Prompt;
import android.FlxVirtualPad;
import android.FlxVirtualPad.FlxDPadMode;
import android.FlxVirtualPad.FlxActionMode;
import flixel.FlxG;
import flixel.FlxObject;
import flixel.FlxSprite;
import flixel.addons.display.FlxGridOverlay;
import flixel.addons.transition.FlxTransitionableState;
import flixel.addons.ui.FlxInputText;
import flixel.addons.ui.FlxUI9SliceSprite;
import flixel.addons.ui.FlxUI;
import flixel.addons.ui.FlxUICheckBox;
import flixel.addons.ui.FlxUIInputText;
import flixel.addons.ui.FlxUINumericStepper;
import flixel.addons.ui.FlxUITabMenu;
import flixel.addons.ui.FlxUITooltip.FlxUITooltipStyle;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.group.FlxGroup;
import flixel.group.FlxSpriteGroup;
import flixel.input.keyboard.FlxKey;
import flixel.math.FlxMath;
import flixel.math.FlxPoint;
import flixel.system.FlxSound;
import flixel.text.FlxText;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.ui.FlxButton;
import flixel.ui.FlxSpriteButton;
import flixel.util.FlxColor;
import flixel.util.FlxSort;
import lime.media.AudioBuffer;
import lime.utils.Assets;
import openfl.events.Event;
import openfl.events.IOErrorEvent;
import openfl.media.Sound;
import openfl.net.FileReference;
import openfl.utils.Assets as OpenFlAssets;
import openfl.utils.ByteArray;

using StringTools;
#if sys
import flash.media.Sound;
import sys.FileSystem;
import sys.io.File;
#end


@:access(flixel.sound.FlxSound)
@:access(openfl.media.Sound)
class OldChartingState063 extends OldEditorState
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
	private var noteTypeIntMap:Map<Int, String> = new Map<Int, String>();
	private var noteTypeMap:Map<String, Null<Int>> = new Map<String, Null<Int>>();
	public var ignoreWarnings = false;
	var _virtualpad:FlxVirtualPad;

	// === Extra Keys: multi-key support ===
	/** lanes per side = mania + 1 */
	function laneCount():Int return ((_song != null && _song.mania != null) ? _song.mania : 3) + 1;
	/** grid columns = 1 event column + both sides */
	function getColumns():Int return 1 + laneCount() * 2;
	var columns:Int = 9;
	var maniaStepper:FlxUINumericStepper;
	var suppressManiaEvent:Bool = false;

	// === horizontal track scrolling (mirrors 0.7.3 editor) ===
	var trackScrollX:Float = GRID_SIZE;
	var trackScrollTargetX:Float = GRID_SIZE;
	var trackButtonScrollSpeed:Float = 240;
	var btnTrackLeft:StyledButton;
	var btnTrackRight:StyledButton;

	// === stashed notes (reversible down-shift, mirrors 0.7.3) ===
	static inline var STASH_FIELD:String = 'editorStashedNotes';
	static inline var STASHED_NOTE_ORANGE:Int = 0xFFFFA500;
	static inline var STASHED_NOTE_ORANGE_DARK:Int = 0xFF8C3A00;
	static inline var STASHED_NOTE_HIGHLIGHT:Int = 0xFFFFFFFF;
	static var sessionStashBySong:Map<String, Array<Dynamic>> = new Map<String, Array<Dynamic>>();
	var stashedNotes:Array<Dynamic> = [];
	var stashedRenderedNotes:FlxTypedGroup<Note>;
	/** Raw note type names, index-aligned with the Note type dropdown (0.7.3 style). */
	var curNoteTypes:Array<String> = [];

	// === undo / redo snapshots ===
	var undoHistory:Array<Dynamic> = [];
	var redoHistory:Array<Dynamic> = [];
	var UNDO_MAX:Int = 100;
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
		['Change Mania', "Runtime key-count change (Psych EK 0.3 style).\nValue 1: new mania (0 = 1K ... 17 = 18K)\nValue 2: 'true' skips the key preview"]
	];

	var _file:FileReference;

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
	/** Cached format that paints only the stashed-note warning line orange. */
	var stashWarnFormat:FlxTextFormat = null;
	/** Last applied format range; start = -1 means no warning line is active. */
	var stashWarnStart:Int = -1;
	var stashWarnEnd:Int = -1;

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
	// 0.7.3 layout fonts
	static inline var SONG_INFO_FONT:String = 'assets/fonts/arturito-slab.ttf';
	static inline var TIP_INFO_FONT:String = 'assets/fonts/Quantico-Bold.ttf';
	/** FlxTextFormat needs 0xRRGGBB (no alpha); low 24 bits of STASHED_NOTE_ORANGE. */
	static inline var STASHED_INFO_ORANGE:Int = 0xFFA500;
	static function get_GENERATED_BY():String
		return 'KathyEngine - Chart Editor Legacy v0.6.3';

	var _song:SwagSong;
	/*
	 * WILL BE THE CURRENT / LAST PLACED NOTE
	**/
	var curSelectedNote:Array<Dynamic> = null;

	var tempBpm:Float = 0;
	var playbackSpeed:Float = 1;

	var vocals:FlxSound = null;

	var leftIcon:HealthIcon;
	var rightIcon:HealthIcon;

	var value1InputText:FlxUIInputText;
	var value2InputText:FlxUIInputText;
	var currentSongName:String;


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
		// Extra Keys: this editor now handles 1K-18K charts directly, no fallback needed.
		if (PlayState.SONG != null)
		{
			_song = PlayState.SONG;
			if (_song.mania == null) _song.mania = 3;
			// Charts always reach us as psych_v1 (Song.parseJSON upgrades on load), but this editor
			// reads/writes lanes relative to mustHitSection like 0.6.3 did.
			LegacyChartFormat.toLegacy(_song, LegacyChartFormat.FORMAT_063);
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
				arrowSkin: '',
				splashSkin: 'noteSplashes',//idk it would crash if i didn't
				player1: 'bf',
				player2: 'dad',
				gfVersion: 'gf',
				speed: 1,
				stage: 'stage',
				offset: 0,
				format: '0.6.3',
				mania: 3
			};
			addSection();
			PlayState.SONG = _song;
		}

		ExtraKeysHandler.ensure();
		syncChartManiaGlobals();
		restoreStashedNotes();

		// Paths.clearMemory();

		// #if desktop
		// // Updating Discord Rich Presence
		// DiscordClient.changePresence("Chart Editor", StringTools.replace(_song.song, '-', ' '));
		// #end

		vortex = FlxG.save.data.chart_vortex;
		ignoreWarnings = FlxG.save.data.ignoreWarnings;
		var bg:FlxSprite = new FlxSprite().loadGraphic(Paths.image('menuDesat'));
		bg.scrollFactor.set();
		bg.color = 0xFF222222;
		add(bg);

		gridLayer = new FlxTypedGroup<FlxSprite>();
		add(gridLayer);

		waveformSprite = new FlxSprite(GRID_SIZE, 0).makeGraphic(FlxG.width, FlxG.height, 0x00FFFFFF);
		add(waveformSprite);

		var eventIcon:FlxSprite = new FlxSprite(-GRID_SIZE - 5, -90).loadGraphic(Paths.image('editors/eventIcon'));
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

		updateIconPositions();

		curRenderedSustains = new FlxTypedGroup<FlxSprite>();
		curRenderedNotes = new FlxTypedGroup<Note>();
		curRenderedNoteType = new FlxTypedGroup<FlxText>();

		nextRenderedSustains = new FlxTypedGroup<FlxSprite>();
		nextRenderedNotes = new FlxTypedGroup<Note>();

		if(curSec >= _song.notes.length) curSec = _song.notes.length - 1;

		FlxG.mouse.visible = true;
		//FlxG.save.bind('funkin', 'ninjamuffin99');

		tempBpm = _song.bpm;

		addSection();

		// sections = _song.notes;

		currentSongName = Paths.formatToSongPath(_song.song);
		loadSong();

		// Song info (time / section / beat / step / snap / zoom) uses arturito-slab,
		// same as the 0.7.3 editor. Its position is set once UI_box exists.
		bpmTxt = new FlxText(1000, 50, 0, "", 16);
		bpmTxt.setFormat(SONG_INFO_FONT, 16, FlxColor.WHITE, LEFT);
		bpmTxt.scrollFactor.set();
		add(bpmTxt);

		strumLine = new FlxSprite(0, 50).makeGraphic(Std.int(GRID_SIZE * getColumns()), 4);
		add(strumLine);

		quant = new AttachedSprite('chart_quant','chart_quant');
		quant.animation.addByPrefix('q','chart_quant',0,false);
		quant.animation.play('q', true, false, 0);
		quant.sprTracker = strumLine;
		quant.xAdd = -32;
		quant.yAdd = 8;
		add(quant);

		reloadGridLayer();
		Conductor.bpm = _song.bpm;
		Conductor.mapBPMChanges(_song);

		strumLineNotes = new FlxTypedGroup<StrumNote>();
		add(strumLineNotes);
		rebuildStrumLineNotes();

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
		];

		UI_box = new FlxUITabMenu(null, tabs, true);

		// Align to the right edge like 0.7.3 so the box never overlaps the tracks on mobile.
		UI_box.resize(300, 400);
		UI_box.x = FlxG.width - UI_box.width - 30;
		UI_box.y = 25;
		UI_box.scrollFactor.set();

		// Keep the song info to the left of the box (0.7.3 layout).
		bpmTxt.x = UI_box.x - 210;
		bpmTxt.y = 50;

		text =
		"W/S or Mouse Wheel - Change Conductor's strum time
		A/D - Go to the previous/next section
		Left/Right - Change Snap
		Up/Down - Change Conductor's Strum Time with Snapping
		Left Bracket / Right Bracket - Change Song Playback Rate (SHIFT to go Faster)
		ALT + Left Bracket / Right Bracket - Reset Song Playback Rate
		Hold Shift to move 4x faster
		Hold Control and click on an arrow to select it
		Z/X - Zoom in/out
		\nEsc - Playtest inside Chart Editor
		Backspace - Go back to Editor Menu
		Enter - Play your chart
		Q/E - Decrease/Increase Note Sustain Length
		Alt + Wheel / < > - Scroll tracks left/right
		Space - Stop/Resume song" + (controls.mobileC ? "\nTouch Pad: use on-screen buttons (B button exits to Editor Menu)" : "");

		var tipTextArray:Array<String> = text.split('\n');
		for (i in 0...tipTextArray.length) {
			var tipText:FlxText = new FlxText(UI_box.x - 210, UI_box.y + UI_box.height + 8, 0, tipTextArray[i], 16);
			tipText.y += i * 16;
			// 0.7.3 uses Quantico-Bold for the help text.
			tipText.setFormat(TIP_INFO_FONT, 14, FlxColor.WHITE, LEFT/*, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK*/);
			//tipText.borderSize = 2;
			tipText.scrollFactor.set();
			add(tipText);
		}
		add(UI_box);

		addSongUI();
		addSectionUI();
		addNoteUI();
		addEventsUI();
		addChartingUI();
		updateHeads();
		updateWaveform();
		//UI_box.selected_tab = 4;

		stashedRenderedNotes = new FlxTypedGroup<Note>();
		add(curRenderedSustains);
		add(curRenderedNotes);
		add(stashedRenderedNotes);
		add(curRenderedNoteType);
		add(nextRenderedSustains);
		add(nextRenderedNotes);

		// === horizontal track scroll buttons (mirrors 0.7.3) ===
		var trackBtnStyle:StyledButtonStyle = StyledButtonStyle.flixelClassic();
		trackBtnStyle.size = 44;
		btnTrackLeft = new StyledButton(UI_box.x - 46, UI_box.y + UI_box.height - 88, StyledButton.LEFT, trackBtnStyle);
		btnTrackLeft.hitPadding = 4;
		add(btnTrackLeft);
		btnTrackRight = new StyledButton(UI_box.x - 46, UI_box.y + UI_box.height - 44, StyledButton.RIGHT, trackBtnStyle);
		btnTrackRight.hitPadding = 4;
		add(btnTrackRight);
		bringTrackButtonsToFront();
		updateTrackButtonsVisibility();

		if(lastSong != currentSongName) {
			changeSection();
		}
		lastSong = currentSongName;

		updateGrid();
		super.create();
	}

	var check_mute_inst:FlxUICheckBox = null;
	var check_vortex:FlxUICheckBox = null;
	var check_warnings:FlxUICheckBox = null;
	var playSoundBf:FlxUICheckBox = null;
	var playSoundDad:FlxUICheckBox = null;
	var UI_songTitle:FlxUIInputText;
	var noteSkinInputText:FlxUIInputText;
	var noteSplashesInputText:FlxUIInputText;
	var stageDropDown:FlxUIDropDownMenuCustom;
	var sliderRate:OldSlider;
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
			confirmChartMania(saveLevel);
		});

		var reloadSong:FlxButton = new FlxButton(saveButton.x + 90, saveButton.y, "Reload Audio", function()
		{
			currentSongName = Paths.formatToSongPath(UI_songTitle.text);
			loadSong();
			updateWaveform();
		});

		var reloadSongJson:FlxButton = new FlxButton(reloadSong.x, saveButton.y + 30, "Reload JSON", function()
		{
			openSubState(new Prompt('This action will clear current progress.\n\nProceed?', 0, function(){loadJson(_song.song.toLowerCase()); }, null,ignoreWarnings));
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

		var clear_events:FlxButton = new FlxButton(320, 310, 'Clear events', function()
			{
				openSubState(new Prompt('This action will clear current progress.\n\nProceed?', 0, clearEvents, null,ignoreWarnings));
			});
		clear_events.color = FlxColor.RED;
		clear_events.label.color = FlxColor.WHITE;

		var clear_notes:FlxButton = new FlxButton(320, clear_events.y + 30, 'Clear notes', function()
			{
				openSubState(new Prompt('This action will clear current progress.\n\nProceed?', 0, function(){for (sec in 0..._song.notes.length) {
					_song.notes[sec].sectionNotes = [];
				}
				updateGrid();
			}, null,ignoreWarnings));

			});
		clear_notes.color = FlxColor.RED;
		clear_notes.label.color = FlxColor.WHITE;

		var stepperBPM:FlxUINumericStepper = new FlxUINumericStepper(10, 70, 1, 1, 1, 400, 3);
		stepperBPM.value = Conductor.bpm;
		stepperBPM.name = 'song_bpm';
		blockPressWhileTypingOnStepper.push(stepperBPM);

		var stepperSpeed:FlxUINumericStepper = new FlxUINumericStepper(10, stepperBPM.y + 35, 0.1, 1, 0.1, 10, 1);
		stepperSpeed.value = _song.speed;
		stepperSpeed.name = 'song_speed';
		blockPressWhileTypingOnStepper.push(stepperSpeed);
		#if MODS_ALLOWED
		var directories:Array<String> = [Paths.mods('characters/'), Paths.mods(Mods.currentModDirectory + '/characters/'), Paths.getSharedPath('characters/')];
		for(mod in Mods.getGlobalMods())
			directories.push(Paths.mods(mod + '/characters/'));
		#else
		var directories:Array<String> = [Paths.getSharedPath('characters/')];
		#end

		var tempMap:Map<String, Bool> = new Map<String, Bool>();
		var characters:Array<String> = CoolUtil.coolTextFile(Paths.txt('characterList'));
		for (i in 0...characters.length) {
			tempMap.set(characters[i], true);
		}

		#if MODS_ALLOWED
		for (i in 0...directories.length) {
			var directory:String = directories[i];
			if(FileSystem.exists(directory)) {
				for (file in FileSystem.readDirectory(directory)) {
					var path = haxe.io.Path.join([directory, file]);
					if (!FileSystem.isDirectory(path) && file.endsWith('.json')) {
						var charToCheck:String = file.substr(0, file.length - 5);
						if(!charToCheck.endsWith('-dead') && !tempMap.exists(charToCheck)) {
							tempMap.set(charToCheck, true);
							characters.push(charToCheck);
						}
					}
				}
			}
		}
		#end

		var player1DropDown = new FlxUIDropDownMenuCustom(10, stepperSpeed.y + 45, FlxUIDropDownMenuCustom.makeStrIdLabelArray(characters, true), function(character:String)
		{
			_song.player1 = characters[Std.parseInt(character)];
			updateHeads();
		});
		player1DropDown.selectedLabel = _song.player1;
		blockPressWhileScrolling.push(player1DropDown);

		var gfVersionDropDown = new FlxUIDropDownMenuCustom(player1DropDown.x, player1DropDown.y + 40, FlxUIDropDownMenuCustom.makeStrIdLabelArray(characters, true), function(character:String)
		{
			_song.gfVersion = characters[Std.parseInt(character)];
			updateHeads();
		});
		gfVersionDropDown.selectedLabel = _song.gfVersion;
		blockPressWhileScrolling.push(gfVersionDropDown);

		var player2DropDown = new FlxUIDropDownMenuCustom(player1DropDown.x, gfVersionDropDown.y + 40, FlxUIDropDownMenuCustom.makeStrIdLabelArray(characters, true), function(character:String)
		{
			_song.player2 = characters[Std.parseInt(character)];
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

		tempMap.clear();
		var stageFile:Array<String> = CoolUtil.coolTextFile(Paths.txt('stageList'));
		var stages:Array<String> = [];
		for (i in 0...stageFile.length) { //Prevent duplicates
			var stageToCheck:String = stageFile[i];
			if(!tempMap.exists(stageToCheck)) {
				stages.push(stageToCheck);
			}
			tempMap.set(stageToCheck, true);
		}
		#if MODS_ALLOWED
		for (i in 0...directories.length) {
			var directory:String = directories[i];
			if(FileSystem.exists(directory)) {
				for (file in FileSystem.readDirectory(directory)) {
					var path = haxe.io.Path.join([directory, file]);
					if (!FileSystem.isDirectory(path) && file.endsWith('.json')) {
						var stageToCheck:String = file.substr(0, file.length - 5);
						if(!tempMap.exists(stageToCheck)) {
							tempMap.set(stageToCheck, true);
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

		var skin = PlayState.SONG.arrowSkin;
		if(skin == null) skin = '';
		noteSkinInputText = new FlxUIInputText(player2DropDown.x, player2DropDown.y + 50, 150, skin, 8);
		blockPressWhileTypingOn.push(noteSkinInputText);

		noteSplashesInputText = new FlxUIInputText(noteSkinInputText.x, noteSkinInputText.y + 35, 150, _song.splashSkin, 8);
		blockPressWhileTypingOn.push(noteSplashesInputText);

		var reloadNotesButton:FlxButton = new FlxButton(noteSplashesInputText.x + 5, noteSplashesInputText.y + 20, 'Change Notes', function() {
			_song.arrowSkin = noteSkinInputText.text;
			updateGrid();
		});

		ExtraKeysHandler.ensure();
		maniaStepper = new FlxUINumericStepper(stepperSpeed.x + 110, stepperSpeed.y, 1, 3,
			ExtraKeysHandler.instance.data.minKeys, ExtraKeysHandler.instance.data.maxKeys, 1);
		maniaStepper.value = (_song.mania != null) ? _song.mania : 3;
		maniaStepper.name = 'song_mania';
		blockPressWhileTypingOnStepper.push(maniaStepper);

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
		tab_group_song.add(maniaStepper);
		tab_group_song.add(reloadNotesButton);
		tab_group_song.add(noteSkinInputText);
		tab_group_song.add(noteSplashesInputText);
		tab_group_song.add(new FlxText(stepperBPM.x, stepperBPM.y - 15, 0, 'Song BPM:'));
		tab_group_song.add(new FlxText(stepperBPM.x + 100, stepperBPM.y - 15, 0, 'Song Offset:'));
		tab_group_song.add(new FlxText(stepperSpeed.x, stepperSpeed.y - 15, 0, 'Song Speed:'));
		tab_group_song.add(new FlxText(maniaStepper.x, maniaStepper.y - 15, 0, 'Mania (Keys):'));
		tab_group_song.add(new FlxText(player2DropDown.x, player2DropDown.y - 15, 0, 'Opponent:'));
		tab_group_song.add(new FlxText(gfVersionDropDown.x, gfVersionDropDown.y - 15, 0, 'Girlfriend:'));
		tab_group_song.add(new FlxText(player1DropDown.x, player1DropDown.y - 15, 0, 'Boyfriend:'));
		tab_group_song.add(new FlxText(stageDropDown.x, stageDropDown.y - 15, 0, 'Stage:'));
		tab_group_song.add(new FlxText(noteSkinInputText.x, noteSkinInputText.y - 15, 0, 'Note Texture:'));
		tab_group_song.add(new FlxText(noteSplashesInputText.x, noteSplashesInputText.y - 15, 0, 'Note Splashes Texture:'));
		tab_group_song.add(player2DropDown);
		tab_group_song.add(gfVersionDropDown);
		tab_group_song.add(player1DropDown);
		tab_group_song.add(stageDropDown);

		UI_box.addGroup(tab_group_song);

		// MusicBeatState.create() resets the camera list, so grab the PsychCamera now instead of
		// following FlxG.camera (which would be destroyed by the time super.create() runs).
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

		stepperBeats = new FlxUINumericStepper(10, 100, 1, 4, 1, 6, 2);
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
						if(note[4] != null) {
							copiedNote = [newStrumTime, note[1], note[2], note[3], note[4]];
						} else {
							copiedNote = [newStrumTime, note[1], note[2], note[3]];
						}
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
			pushUndo();
			for (i in 0..._song.notes[curSec].sectionNotes.length)
			{
				var note:Array<Dynamic> = _song.notes[curSec].sectionNotes[i];
				note[1] = (note[1] + laneCount()) % (laneCount() * 2);
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
				if (note.length > 4) copiedNote.push(note[4]);
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
					boob -= laneCount();
				}else{
					boob += laneCount();
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
				var boob = note[1] % laneCount();
				boob = _song.mania - boob;
				if (note[1] > _song.mania) boob += laneCount();

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
		var displayNameList:Array<String> = [];
		while (key < noteTypeList.length) {
			displayNameList.push(noteTypeList[key]);
			curNoteTypes.push(noteTypeList[key]);
			noteTypeMap.set(noteTypeList[key], key);
			noteTypeIntMap.set(key, noteTypeList[key]);
			key++;
		}

		// 0.6.3 only scanned for `.lua` note types; this engine declares them with `.txt`
		// (see NoteTypesConfig), so accept both instead of showing an empty list.
		#if sys
		for (folder in Mods.directoriesWithFile(Paths.getSharedPath(), 'custom_notetypes/'))
		{
			for (file in FileSystem.readDirectory(folder))
			{
				var fileName:String = file.toLowerCase().trim();
				var wordLen:Int = 4; // ".lua" / ".txt"
				if ((#if LUA_ALLOWED fileName.endsWith('.lua') || #end
					#if HSCRIPT_ALLOWED (fileName.endsWith('.hx') && (wordLen = 3) == 3) || #end
					fileName.endsWith('.txt')) && fileName != 'readme.txt')
				{
					var fileToCheck:String = file.substr(0, file.length - wordLen);
					if (!noteTypeMap.exists(fileToCheck))
					{
						displayNameList.push(fileToCheck);
						curNoteTypes.push(fileToCheck);
						noteTypeMap.set(fileToCheck, key);
						noteTypeIntMap.set(key, fileToCheck);
						key++;
					}
				}
			}
		}
		#end

		// Also scan per-song data folder for custom_notetypes
		var perSongNoteTypeNames:Array<String> = [];
		if(currentSongName != null && currentSongName.length > 0)
		{
			#if MODS_ALLOWED
			var pFolders:Array<String> = Mods.directoriesWithFile(Paths.getSharedPath(), 'data/' + currentSongName + '/');
			for (folder in pFolders)
			{
				var pTypesPath:String = folder + 'custom_notetypes/';
				if(FileSystem.exists(pTypesPath))
				{
					for (file in FileSystem.readDirectory(pTypesPath))
					{
						var pFileName:String = file.toLowerCase().trim();
						var pWordLen:Int = 4;
						if ((#if LUA_ALLOWED pFileName.endsWith('.lua') || #end
							#if HSCRIPT_ALLOWED (pFileName.endsWith('.hx') && (pWordLen = 3) == 3) || #end
							pFileName.endsWith('.txt')) && pFileName != 'readme.txt')
						{
							var pFileToCheck:String = file.substr(0, file.length - pWordLen);
							if (!noteTypeMap.exists(pFileToCheck))
							{
								displayNameList.push(pFileToCheck);
								curNoteTypes.push(pFileToCheck);
								noteTypeMap.set(pFileToCheck, key);
								noteTypeIntMap.set(key, pFileToCheck);
								perSongNoteTypeNames.push(pFileToCheck);
								key++;
							}
						}
					}
				}
			}
			#end
		}

		for (i in 1...displayNameList.length) {
			displayNameList[i] = i + '. ' + displayNameList[i];
		}

		noteTypeDropDown = new FlxUIDropDownMenuCustom(10, 105, FlxUIDropDownMenuCustom.makeStrIdLabelArray(displayNameList, true), function(character:String)
		{
			currentType = Std.parseInt(character);
			if(curSelectedNote != null && curSelectedNote[1] > -1) {
				curSelectedNote[3] = noteTypeIntMap.get(currentType);
				updateGrid();
			}
		});
		blockPressWhileScrolling.push(noteTypeDropDown);

		// Mark per-song note types
		for (idx in 0...displayNameList.length)
		{
			var rawName:String = noteTypeIntMap.get(idx);
			if(perSongNoteTypeNames.contains(rawName))
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
	#if desktop
	var waveformUseInstrumental:FlxUICheckBox;
	var waveformUseVoices:FlxUICheckBox;
	#end
	var instVolume:FlxUINumericStepper;
	var voicesVolume:FlxUINumericStepper;
	function addChartingUI() {
		var tab_group_chart = new FlxUI(null, UI_box);
		tab_group_chart.name = 'Charting';

		#if desktop
		if (FlxG.save.data.chart_waveformInst == null) FlxG.save.data.chart_waveformInst = false;
		if (FlxG.save.data.chart_waveformVoices == null) FlxG.save.data.chart_waveformVoices = false;

		waveformUseInstrumental = new FlxUICheckBox(10, 90, null, null, "Waveform for Instrumental", 100);
		waveformUseInstrumental.checked = FlxG.save.data.chart_waveformInst;
		waveformUseInstrumental.callback = function()
		{
			waveformUseVoices.checked = false;
			FlxG.save.data.chart_waveformVoices = false;
			FlxG.save.data.chart_waveformInst = waveformUseInstrumental.checked;
			updateWaveform();
		};

		waveformUseVoices = new FlxUICheckBox(waveformUseInstrumental.x + 120, waveformUseInstrumental.y, null, null, "Waveform for Voices", 100);
		waveformUseVoices.checked = FlxG.save.data.chart_waveformVoices;
		waveformUseVoices.callback = function()
		{
			waveformUseInstrumental.checked = false;
			FlxG.save.data.chart_waveformInst = false;
			FlxG.save.data.chart_waveformVoices = waveformUseVoices.checked;
			updateWaveform();
		};
		#end

		check_mute_inst = new FlxUICheckBox(10, 310, null, null, "Mute Instrumental (in editor)", 100);
		check_mute_inst.checked = false;
		check_mute_inst.callback = function()
		{
			var vol:Float = 1;

			if (check_mute_inst.checked)
				vol = 0;

			FlxG.sound.music.volume = vol;
		};
		mouseScrollingQuant = new FlxUICheckBox(10, 200, null, null, "Mouse Scrolling Quantization", 100);
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

		var check_mute_vocals = new FlxUICheckBox(check_mute_inst.x + 120, check_mute_inst.y, null, null, "Mute Vocals (in editor)", 100);
		check_mute_vocals.checked = false;
		check_mute_vocals.callback = function()
		{
			if(vocals != null) {
				var vol:Float = 1;

				if (check_mute_vocals.checked)
					vol = 0;

				vocals.volume = vol;
			}
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

		instVolume = new FlxUINumericStepper(metronomeStepper.x, 270, 0.1, 1, 0, 1, 1);
		instVolume.value = FlxG.sound.music.volume;
		instVolume.name = 'inst_volume';
		blockPressWhileTypingOnStepper.push(instVolume);

		voicesVolume = new FlxUINumericStepper(instVolume.x + 100, instVolume.y, 0.1, 1, 0, 1, 1);
		voicesVolume.value = vocals.volume;
		voicesVolume.name = 'voices_volume';
		blockPressWhileTypingOnStepper.push(voicesVolume);
		
		#if !html5
		sliderRate = new OldSlider(this, 'playbackSpeed', 120, 120, 0.5, 3, 150, 15, 5, FlxColor.WHITE, FlxColor.BLACK);
		sliderRate.nameLabel.text = 'Playback Rate';
		tab_group_chart.add(sliderRate);
		#end

		tab_group_chart.add(new FlxText(metronomeStepper.x, metronomeStepper.y - 15, 0, 'BPM:'));
		tab_group_chart.add(new FlxText(metronomeOffsetStepper.x, metronomeOffsetStepper.y - 15, 0, 'Offset (ms):'));
		tab_group_chart.add(new FlxText(instVolume.x, instVolume.y - 15, 0, 'Inst Volume'));
		tab_group_chart.add(new FlxText(voicesVolume.x, voicesVolume.y - 15, 0, 'Voices Volume'));
		tab_group_chart.add(metronome);
		tab_group_chart.add(disableAutoScrolling);
		tab_group_chart.add(metronomeStepper);
		tab_group_chart.add(metronomeOffsetStepper);
		#if desktop
		tab_group_chart.add(waveformUseInstrumental);
		tab_group_chart.add(waveformUseVoices);
		#end
		tab_group_chart.add(instVolume);
		tab_group_chart.add(voicesVolume);
		tab_group_chart.add(check_mute_inst);
		tab_group_chart.add(check_mute_vocals);
		tab_group_chart.add(check_vortex);
		tab_group_chart.add(mouseScrollingQuant);
		tab_group_chart.add(check_warnings);
		tab_group_chart.add(playSoundBf);
		tab_group_chart.add(playSoundDad);
		UI_box.addGroup(tab_group_chart);
	}

	function loadSong():Void
	{
		if (FlxG.sound.music != null)
		{
			FlxG.sound.music.stop();
			// vocals.stop();
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

		var file:Dynamic = Paths.voices(currentSongName, null, specialVocalSuffix());
		if (file == null) file = Paths.voices(currentSongName);
		vocals = new FlxSound();
		if (Std.isOfType(file, Sound) || OpenFlAssets.exists(file)) {
			vocals.loadEmbedded(file);
			FlxG.sound.list.add(vocals);
		}
		generateSong();
		FlxG.sound.music.pause();
		Conductor.songPosition = sectionStartTime();
		FlxG.sound.music.time = Conductor.songPosition;
	}

	// This engine lets a chart point at suffixed audio files (Inst-X / Voices-X) through
	// specialInst / specialVocal; 0.6.3 knew nothing about them and would load the wrong track.
	inline function specialInstSuffix():String
		return (_song != null && _song.specialInst != null && _song.specialInst.length > 0) ? _song.specialInst : null;

	inline function specialVocalSuffix():String
		return (_song != null && _song.specialVocal != null && _song.specialVocal.length > 0) ? _song.specialVocal : null;

	function generateSong() {
		FlxG.sound.playMusic(Paths.inst(currentSongName, specialInstSuffix()), 0.6/*, false*/);
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
			changeSection();
			curSec = 0;
			updateGrid();
			updateSectionUI();
			vocals.play();
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
			FlxG.log.add(wname);
			if (wname == 'section_beats')
			{
				_song.notes[curSec].sectionBeats = nums.value;
				reloadGridLayer();
			}
			else if (wname == 'song_speed')
			{
				_song.speed = nums.value;
			}
			else if (wname == 'song_mania')
			{
				if (!suppressManiaEvent)
				{
					pushUndo();
					var newMania:Int = Std.int(nums.value);
					var oldMania:Int = (_song.mania != null) ? _song.mania : 3;
					if (oldMania != newMania) remapChartNotesForMania(oldMania, newMania);
					_song.mania = newMania;
					Reflect.setField(_song, 'keyCount', newMania + 1);
					if (PlayState.SONG != null) PlayState.SONG.mania = newMania;
					trackScrollX = GRID_SIZE;
					trackScrollTargetX = GRID_SIZE;
					updateTrackButtonsVisibility();
					reloadGridLayer();
				}
			}
			else if (wname == 'song_bpm')
			{
				tempBpm = nums.value;
				Conductor.mapBPMChanges(_song);
				Conductor.bpm = nums.value;
			}
			else if (wname == 'note_susLength')
			{
				if(curSelectedNote != null && curSelectedNote[2] != null) {
					curSelectedNote[2] = nums.value;
					updateGrid();
				}
			}
			else if (wname == 'section_bpm')
			{
				_song.notes[curSec].bpm = nums.value;
				updateGrid();
			}
			else if (wname == 'inst_volume')
			{
				FlxG.sound.music.volume = nums.value;
			}
			else if (wname == 'voices_volume')
			{
				vocals.volume = nums.value;
			}
		}
		else if(id == FlxUIInputText.CHANGE_EVENT && (sender is FlxUIInputText)) {
			if(sender == noteSplashesInputText) {
				_song.splashSkin = noteSplashesInputText.text;
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
		// NOTE: 0.6.3 handled the playback rate slider here through FlxUISlider.CHANGE_EVENT, but it
		// compared the sender object against a String so the branch never ran. OldSlider writes
		// `playbackSpeed` directly instead, which is what that code meant to do.

		// FlxG.log.add(id + " WEED " + sender + " WEED " + data + " WEED " + params);

		if(controls.mobileC)
		{
			if(_virtualpad == null)
			{
				_virtualpad = new FlxVirtualPad(FlxDPadMode.CHART_EDITOR, FlxActionMode.CHART_EDITOR);
				add(_virtualpad);
				// The virtual pad is added lazily; keep the track scroll buttons above it.
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
		Conductor.songPosition = FlxG.sound.music.time;
		_song.song = UI_songTitle.text;

		strumLineUpdateY();
		for (arrow in strumLineNotes)
			if (arrow != null) arrow.y = strumLine.y;

		// === horizontal track camera (mirrors 0.7.3) ===
		var wheelConsumedForHorizontal:Bool = false;
		var wheelDelta:Float = FlxG.mouse.wheel;
		if (wheelDelta != 0 && altHeld)
		{
			trackScrollTargetX -= wheelDelta * GRID_SIZE;
			wheelConsumedForHorizontal = true;
		}
		var btnStep:Float = trackButtonScrollSpeed * Math.min(elapsed, 1 / 30);
		if (btnTrackLeft != null && btnTrackLeft.pressed) trackScrollTargetX += btnStep;
		if (btnTrackRight != null && btnTrackRight.pressed) trackScrollTargetX -= btnStep;
		trackScrollX = FlxMath.lerp(trackScrollX, trackScrollTargetX, 0.25);
		camPos.x = -80 + (GRID_SIZE * (laneCount() * 2)) + trackScrollX;

		FlxG.mouse.visible = true;//cause reasons. trust me
		camPos.y = strumLine.y;
		if(!disableAutoScrolling.checked) {
			if (Math.ceil(strumLine.y) >= gridBG.height)
			{
				if (_song.notes[curSec + 1] == null)
				{
					addSection();
				}

				changeSection(curSec + 1, false);
			} else if(strumLine.y < -10) {
				changeSection(curSec - 1, false);
			}
		}
		FlxG.watch.addQuick('daBeat', curBeat);
		FlxG.watch.addQuick('daStep', curStep);


		// Screen-space guard: after horizontal scrolling, world mouse coords no longer match
		// the fixed UI_box / button rects. Mirrors 0.7.3's anti-click-through logic.
		var smx:Float = FlxG.mouse.x - FlxG.camera.scroll.x;
		var smy:Float = FlxG.mouse.y - FlxG.camera.scroll.y;
		var suppressMouse:Bool = false;
		if (UI_box != null)
			suppressMouse = smx >= UI_box.x - 5 && smx <= UI_box.x + UI_box.width + 5
				&& smy >= UI_box.y - 5 && smy <= UI_box.y + UI_box.height + 5;
		if (!suppressMouse && btnTrackLeft != null && btnTrackLeft.visible
			&& smx >= btnTrackLeft.x - 4 && smx <= btnTrackLeft.x + btnTrackLeft.width + 4
			&& smy >= btnTrackLeft.y - 4 && smy <= btnTrackLeft.y + btnTrackLeft.height + 4)
			suppressMouse = true;
		if (!suppressMouse && btnTrackRight != null && btnTrackRight.visible
			&& smx >= btnTrackRight.x - 4 && smx <= btnTrackRight.x + btnTrackRight.width + 4
			&& smy >= btnTrackRight.y - 4 && smy <= btnTrackRight.y + btnTrackRight.height + 4)
			suppressMouse = true;

		if (!suppressMouse && FlxG.mouse.x > gridBG.x
			&& FlxG.mouse.x < gridBG.x + gridBG.width
			&& FlxG.mouse.y > gridBG.y
			&& FlxG.mouse.y < gridBG.y + (GRID_SIZE * getSectionBeats() * 4) * zoomList[curZoom])
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
							curSelectedNote[3] = noteTypeIntMap.get(currentType);
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
			else
			{
				if (!suppressMouse && FlxG.mouse.x > gridBG.x
					&& FlxG.mouse.x < gridBG.x + gridBG.width
					&& FlxG.mouse.y > gridBG.y
					&& FlxG.mouse.y < gridBG.y + (GRID_SIZE * getSectionBeats() * 4) * zoomList[curZoom])
				{
					FlxG.log.add('added note');
					addNote();
				}
			}
		}

		var blockInput:Bool = false;
		for (inputText in blockPressWhileTypingOn) {
			if(inputText.hasFocus) {
				FlxG.sound.muteKeys = [];
				FlxG.sound.volumeDownKeys = [];
				FlxG.sound.volumeUpKeys = [];
				blockInput = true;
				break;
			}
		}

		if(!blockInput) {
			for (stepper in blockPressWhileTypingOnStepper) {
				@:privateAccess
				var leText:Dynamic = stepper.text_field;
				var leText:FlxUIInputText = leText;
				if(leText.hasFocus) {
					FlxG.sound.muteKeys = [];
					FlxG.sound.volumeDownKeys = [];
					FlxG.sound.volumeUpKeys = [];
					blockInput = true;
					break;
				}
			}
		}

		if(!blockInput) {
			FlxG.sound.muteKeys = TitleState.muteKeys;
			FlxG.sound.volumeDownKeys = TitleState.volumeDownKeys;
			FlxG.sound.volumeUpKeys = TitleState.volumeUpKeys;
			for (dropDownMenu in blockPressWhileScrolling) {
				if(dropDownMenu.dropPanel.visible) {
					blockInput = true;
					break;
				}
			}
		}

		if (!blockInput)
		{


			if (FlxG.keys.justPressed.ESCAPE || (_virtualpad != null && _virtualpad.buttonC.justPressed))
			{
				confirmChartMania(openEditorPlayState);
			}
			if (FlxG.keys.justPressed.ENTER || (_virtualpad != null && _virtualpad.buttonA.justPressed))
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
				PlayState.chartingMode = false;
				MusicBeatState.switchState(new MasterEditorMenu());
				FlxG.sound.playMusic(Paths.menuMusicAudio());
				FlxG.mouse.visible = false;
				return;
			}

			if(FlxG.keys.justPressed.Z && ctrlHeld) {
				undo();
			}
			if(FlxG.keys.justPressed.Y && ctrlHeld) {
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
						UI_box.selected_tab = 4;
				}
				else
				{
					UI_box.selected_tab += 1;
					if (UI_box.selected_tab >= 5)
						UI_box.selected_tab = 0;
				}
			}

			if (FlxG.keys.justPressed.SPACE || (_virtualpad != null && _virtualpad.buttonX.justPressed))
			{
				if (FlxG.sound.music.playing)
				{
					FlxG.sound.music.pause();
					if(vocals != null) vocals.pause();
				}
				else
				{
					if(vocals != null) {
						vocals.play();
						vocals.pause();
						vocals.time = FlxG.sound.music.time;
						vocals.play();
					}
					FlxG.sound.music.play();
				}
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
						}else{
							var fuck:Float = CoolUtil.quantize(beat, snap) + increase;
							FlxG.sound.music.time = Conductor.beatToSeconds(fuck);
						}
					}
				if(vocals != null) {
					vocals.pause();
					vocals.time = FlxG.sound.music.time;
				}
			}

			//ARROW VORTEX SHIT NO DEADASS



			if (FlxG.keys.pressed.W || FlxG.keys.pressed.S || (_virtualpad != null && (_virtualpad.buttonUp.pressed || _virtualpad.buttonDown.pressed)))
			{
				FlxG.sound.music.pause();

				var holdingShift:Float = 1;
				if (ctrlHeld) holdingShift = 0.25;
				else if (shiftHeld) holdingShift = 4;

				var daTime:Float = 700 * FlxG.elapsed * holdingShift;

				if (FlxG.keys.pressed.W || (_virtualpad != null && _virtualpad.buttonUp.pressed))
				{
					FlxG.sound.music.time -= daTime;
				}
				else
					FlxG.sound.music.time += daTime;

				if(vocals != null) {
					vocals.pause();
					vocals.time = FlxG.sound.music.time;
				}
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
					if(vocals != null) {
						vocals.pause();
						vocals.time = FlxG.sound.music.time;
					}

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
		} else if (FlxG.keys.justPressed.ENTER || (_virtualpad != null && _virtualpad.buttonA.justPressed)) {
			for (i in 0...blockPressWhileTypingOn.length) {
				if(blockPressWhileTypingOn[i].hasFocus) {
					blockPressWhileTypingOn[i].hasFocus = false;
				}
			}
		}

		_song.bpm = tempBpm;

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
		Conductor.songPosition = FlxG.sound.music.time;
		strumLineUpdateY();
		camPos.y = strumLine.y;
		for (arrow in strumLineNotes)
		{
			if (arrow == null) continue;
			arrow.y = strumLine.y;
			arrow.alpha = FlxG.sound.music.playing ? 1 : 0.35;
		}

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
		vocals.pitch = playbackSpeed;

		// 0.7.3 layout: compact single line breaks and Zoom on the last line.
		var songInfo:String =
		Std.string(FlxMath.roundDecimal(Conductor.songPosition / 1000, 2)) + " / " + Std.string(FlxMath.roundDecimal(FlxG.sound.music.length / 1000, 2)) +
		"\nSection: " + curSec +
		"\n\nBeat: " + Std.string(curDecBeat).substring(0,4) +
		"\nStep: " + curStep +
		"\n\nBeat Snap: " + quantization + "th" +
		"\nZoom: " + (zoomList[curZoom] >= 1 ? '1 / ' + zoomList[curZoom] : Math.round(1 / zoomList[curZoom]) + ' / 1');
		// Persistent warning while notes are parked outside the current layout.
		var stashWarn:String = (stashedNotes.length > 0)
			? "\n\n! " + stashedNotes.length + " note(s) out of " + laneCount() + "K"
			: "";
		bpmTxt.text = songInfo + stashWarn;
		// +2 skips the two separating newlines; -1 removes the format.
		updateStashWarnFormat(stashWarn.length > 0 ? songInfo.length + 2 : -1);

		var playedSound:Array<Bool> = [];
		for (i in 0...laneCount()) playedSound.push(false);
		curRenderedNotes.forEachAlive(function(note:Note) {
			note.alpha = 1;
			if(curSelectedNote != null) {
				var noteDataToCheck:Int = note.noteData;
				if(noteDataToCheck > -1 && note.mustPress != _song.notes[curSec].mustHitSection) noteDataToCheck += laneCount();

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
					var data:Int = note.noteData % laneCount();
					var noteDataToCheck:Int = note.noteData;
					if(noteDataToCheck > -1 && note.mustPress != _song.notes[curSec].mustHitSection) noteDataToCheck += laneCount();
						if (noteDataToCheck >= 0 && noteDataToCheck < strumLineNotes.members.length)
						{
							strumLineNotes.members[noteDataToCheck].playAnim('confirm', true);
							strumLineNotes.members[noteDataToCheck].resetAnim = (note.sustainLength / 1000) + 0.15;
						}
					if(!playedSound[data]) {
						if((playSoundBf.checked && note.mustPress) || (playSoundDad.checked && !note.mustPress)){
							var soundToPlay = 'hitsound';
							if(_song.player1 == 'gf') { //Easter egg
								soundToPlay = 'GF_' + Std.string(data + 1);
							}

							FlxG.sound.play(Paths.sound(soundToPlay)).pan = note.noteData < laneCount()? -0.3 : 0.3;
							playedSound[data] = true;
						}

						data = note.noteData;
						if(note.mustPress != _song.notes[curSec].mustHitSection)
						{
							data += laneCount();
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

	/**
	 * Paint only bpmTxt's trailing "! N note(s) out of XK" line orange.
	 *
	 * FlxText.set_text does NOT clear _formatRanges, so calling addFormat() every
	 * frame would grow that array without bound. Cache one FlxTextFormat and only
	 * re-apply when the range actually changes; clear once when the warning is gone.
	 * font / size stay null in FlxTextFormat, so OpenFL's TextFormat.__merge()
	 * leaves arturito-slab / 16px / LEFT untouched.
	 *
	 * @param start index of the warning line's first char; -1 = no warning line
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
	 * Clear global note / shader state when leaving the editor (mirrors 0.7.3).
	 * Without this the next state can inherit this chart's multi-key colArray,
	 * cached RGB shaders and note-type data -> wrong colors / stale note types.
	 */
	override function destroy()
	{
		Note.globalRgbShaders = [];
		backend.NoteTypesConfig.clearNoteTypesData();
		Note.uiManiaOverride = -1;
		Note.editorDualMode = false;
		Note.editorPlrKeys = 4;
		Note.editorOppKeys = 4;
		Note.colArray = ['purple', 'blue', 'green', 'red'];
		super.destroy();
	}

	function updateZoom() {
		// Zoom is the last line of bpmTxt (refreshed every frame), so only rebuild the grid.
		// Matches 0.7.3.
		reloadGridLayer();
	}

	/*
	function loadAudioBuffer() {
		if(audioBuffers[0] != null) {
			audioBuffers[0].dispose();
		}
		audioBuffers[0] = null;
		#if MODS_ALLOWED
		if(FileSystem.exists(Paths.modFolders('songs/' + currentSongName + '/Inst.ogg'))) {
			audioBuffers[0] = AudioBuffer.fromFile(Paths.modFolders('songs/' + currentSongName + '/Inst.ogg'));
			//trace('Custom vocals found');
		}
		else { #end
			var leVocals:String = Paths.getPath(currentSongName + '/Inst.' + Paths.SOUND_EXT, SOUND, 'songs');
			if (OpenFlAssets.exists(leVocals)) { //Vanilla inst
				audioBuffers[0] = AudioBuffer.fromFile('./' + leVocals.substr(6));
				//trace('Inst found');
			}
		#if MODS_ALLOWED
		}
		#end

		if(audioBuffers[1] != null) {
			audioBuffers[1].dispose();
		}
		audioBuffers[1] = null;
		#if MODS_ALLOWED
		if(FileSystem.exists(Paths.modFolders('songs/' + currentSongName + '/Voices.ogg'))) {
			audioBuffers[1] = AudioBuffer.fromFile(Paths.modFolders('songs/' + currentSongName + '/Voices.ogg'));
			//trace('Custom vocals found');
		} else { #end
			var leVocals:String = Paths.getPath(currentSongName + '/Voices.' + Paths.SOUND_EXT, SOUND, 'songs');
			if (OpenFlAssets.exists(leVocals)) { //Vanilla voices
				audioBuffers[1] = AudioBuffer.fromFile('./' + leVocals.substr(6));
				//trace('Voices found, LETS FUCKING GOOOO');
			}
		#if MODS_ALLOWED
		}
		#end
	}
	*/

	var lastSecBeats:Float = 0;
	var lastSecBeatsNext:Float = 0;
	function reloadGridLayer() {
		columns = getColumns();
		syncChartManiaGlobals();
		updateIconPositions();
		// Re-size the judgement line in place (keeps quant.sprTracker valid).
		if (strumLine != null) strumLine.makeGraphic(Std.int(GRID_SIZE * columns), 4);
		gridLayer.clear();
		gridBG = FlxGridOverlay.create(GRID_SIZE, GRID_SIZE, GRID_SIZE * columns, Std.int(GRID_SIZE * getSectionBeats() * 4 * zoomList[curZoom]));

		#if desktop
		if(FlxG.save.data.chart_waveformInst || FlxG.save.data.chart_waveformVoices) {
			updateWaveform();
		}
		#end

		var leHeight:Int = Std.int(gridBG.height);
		var foundNextSec:Bool = false;
		if(sectionStartTime(1) <= FlxG.sound.music.length)
		{
			nextGridBG = FlxGridOverlay.create(GRID_SIZE, GRID_SIZE, GRID_SIZE * columns, Std.int(GRID_SIZE * getSectionBeats(curSec + 1) * 4 * zoomList[curZoom]));
			leHeight = Std.int(gridBG.height + nextGridBG.height);
			foundNextSec = true;
		}
		else nextGridBG = new FlxSprite().makeGraphic(1, 1, FlxColor.TRANSPARENT);
		nextGridBG.y = gridBG.height;
		
		gridLayer.add(nextGridBG);
		gridLayer.add(gridBG);

		if(foundNextSec)
		{
			var gridBlack:FlxSprite = new FlxSprite(0, gridBG.height).makeGraphic(Std.int(GRID_SIZE * columns), Std.int(nextGridBG.height), FlxColor.BLACK);
			gridBlack.alpha = 0.4;
			gridLayer.add(gridBlack);
		}

		var gridBlackLine:FlxSprite = new FlxSprite(gridBG.x + gridBG.width - (GRID_SIZE * laneCount())).makeGraphic(2, leHeight, FlxColor.BLACK);
		gridLayer.add(gridBlackLine);

		for (i in 1...4) {
			var beatsep1:FlxSprite = new FlxSprite(gridBG.x, (GRID_SIZE * (4 * curZoom)) * i).makeGraphic(Std.int(gridBG.width), 1, 0x44FF0000);
			if(vortex)
			{
				gridLayer.add(beatsep1);
			}
		}

		var gridBlackLine:FlxSprite = new FlxSprite(gridBG.x + GRID_SIZE).makeGraphic(2, leHeight, FlxColor.BLACK);
		gridLayer.add(gridBlackLine);
		rebuildStrumLineNotes();
		updateTrackButtonsVisibility();
		updateGrid();

		lastSecBeats = getSectionBeats();
		if(sectionStartTime(1) > FlxG.sound.music.length) lastSecBeatsNext = 0;
		else getSectionBeats(curSec + 1);
	}

	function strumLineUpdateY()
	{
		strumLine.y = getYfromStrum((Conductor.songPosition - sectionStartTime()) / zoomList[curZoom] % (Conductor.stepCrochet * 16)) / (getSectionBeats() / 4);
	}

	var waveformPrinted:Bool = true;
	var wavData:Array<Array<Array<Float>>> = [[[0], [0]], [[0], [0]]];
	function updateWaveform() {
		#if desktop
		if(waveformPrinted) {
			waveformSprite.makeGraphic(Std.int(GRID_SIZE * (laneCount() * 2)), Std.int(gridBG.height), 0x00FFFFFF);
			waveformSprite.pixels.fillRect(new Rectangle(0, 0, gridBG.width, gridBG.height), 0x00FFFFFF);
		}
		waveformPrinted = false;

		if(!FlxG.save.data.chart_waveformInst && !FlxG.save.data.chart_waveformVoices) {
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

		if (FlxG.save.data.chart_waveformInst) {
			var sound:FlxSound = FlxG.sound.music;
			if (sound._sound != null && sound._sound.__buffer != null) {
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
		}

		if (FlxG.save.data.chart_waveformVoices) {
			var sound:FlxSound = vocals;
			if (sound._sound != null && sound._sound.__buffer != null) {
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
		}

		// Draws
		var gSize:Int = Std.int(GRID_SIZE * (laneCount() * 2));
		var hSize:Int = Std.int(gSize / 2);

		var lmin:Float = 0;
		var lmax:Float = 0;

		var rmin:Float = 0;
		var rmax:Float = 0;

		var size:Float = 1;

		var leftLength:Int = (
			wavData[0][0].length > wavData[0][1].length ? wavData[0][0].length : wavData[0][1].length
		);

		var rightLength:Int = (
			wavData[1][0].length > wavData[1][1].length ? wavData[1][0].length : wavData[1][1].length
		);

		var length:Int = leftLength > rightLength ? leftLength : rightLength;

		var index:Int;
		for (i in 0...length) {
			index = i;

			lmin = FlxMath.bound(((index < wavData[0][0].length && index >= 0) ? wavData[0][0][index] : 0) * (gSize / 1.12), -hSize, hSize) / 2;
			lmax = FlxMath.bound(((index < wavData[0][1].length && index >= 0) ? wavData[0][1][index] : 0) * (gSize / 1.12), -hSize, hSize) / 2;

			rmin = FlxMath.bound(((index < wavData[1][0].length && index >= 0) ? wavData[1][0][index] : 0) * (gSize / 1.12), -hSize, hSize) / 2;
			rmax = FlxMath.bound(((index < wavData[1][1].length && index >= 0) ? wavData[1][1][index] : 0) * (gSize / 1.12), -hSize, hSize) / 2;

			waveformSprite.pixels.fillRect(new Rectangle(hSize - (lmin + rmin), i * size, (lmin + rmin) + (lmax + rmax), size), FlxColor.BLUE);
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

				if (sample > 0) {
					if (sample > lmax) lmax = sample;
				} else if (sample < 0) {
					if (sample < lmin) lmin = sample;
				}

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

				if (channels >= 2) {
					if (gotIndex > array[1][0].length) array[1][0].push(rRMin);
						else array[1][0][gotIndex - 1] = array[1][0][gotIndex - 1] + rRMin;

					if (gotIndex > array[1][1].length) array[1][1].push(rRMax);
						else array[1][1][gotIndex - 1] = array[1][1][gotIndex - 1] + rRMax;
				}
				else {
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
			if (curSelectedNote[2] != null)
			{
				curSelectedNote[2] += value;
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

		if(vocals != null) {
			vocals.pause();
			vocals.time = FlxG.sound.music.time;
		}
		updateCurStep();

		updateGrid();
		updateSectionUI();
		updateWaveform();
	}

	function changeSection(sec:Int = 0, ?updateMusic:Bool = true):Void
	{
		if (_song.notes[sec] != null)
		{
			curSec = sec;
			if (updateMusic)
			{
				FlxG.sound.music.pause();

				FlxG.sound.music.time = sectionStartTime();
				if(vocals != null) {
					vocals.pause();
					vocals.time = FlxG.sound.music.time;
				}
				updateCurStep();
			}

			var blah1:Float = getSectionBeats();
			var blah2:Float = getSectionBeats(curSec + 1);
			if(sectionStartTime(1) > FlxG.sound.music.length) blah2 = 0;
	
			if(blah1 != lastSecBeats || blah2 != lastSecBeatsNext)
			{
				reloadGridLayer();
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
		Conductor.songPosition = FlxG.sound.music.time;
		updateWaveform();
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

	function updateHeads():Void
	{
		var healthIconP1:String = loadHealthIconFromCharacter(_song.player1);
		var healthIconP2:String = loadHealthIconFromCharacter(_song.player2);

		if (_song.notes[curSec].mustHitSection)
		{
			leftIcon.changeIcon(healthIconP1);
			rightIcon.changeIcon(healthIconP2);
			if (_song.notes[curSec].gfSection) leftIcon.changeIcon('gf');
		}
		else
		{
			leftIcon.changeIcon(healthIconP2);
			rightIcon.changeIcon(healthIconP1);
			if (_song.notes[curSec].gfSection) leftIcon.changeIcon('gf');
		}
	}

	function loadHealthIconFromCharacter(char:String) {
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
		}

		#if MODS_ALLOWED
		var rawJson = File.getContent(path);
		#else
		var rawJson = OpenFlAssets.getText(path);
		#end

		var json:CharacterFile = cast Json.parse(rawJson);
		return json.healthicon;
	}

	function updateNoteUI():Void
	{
		if (curSelectedNote != null) {
			if(curSelectedNote[2] != null) {
				stepperSusLength.value = curSelectedNote[2];
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
		curRenderedNotes.clear();
		curRenderedSustains.clear();
		curRenderedNoteType.clear();
		nextRenderedNotes.clear();
		nextRenderedSustains.clear();
		if (stashedRenderedNotes != null)
		{
			stashedRenderedNotes.forEachAlive(function(spr:Note) spr.destroy());
			stashedRenderedNotes.clear();
		}

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

			// noteType label: index / '?' / nothing. Read-only, never rewrites i[3].
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

		renderStashedNotes();
	}

	function setupNoteData(i:Array<Dynamic>, isNextSection:Bool):Note
	{
		var daNoteInfo = i[1];
		var daStrumTime = i[0];
		var daSus:Dynamic = i[2];

		var note:Note = new Note(daStrumTime, daNoteInfo % laneCount(), null, null, true);
		if(daSus != null) { //Common note
			// Read-only resolution: the old code converted numeric indices in place
			// and removed i[3] when empty, silently rewriting chart data on redraw.
			note.sustainLength = daSus;
			note.noteType = resolveNoteTypeName(i);
		} else { //Event note
			note.loadGraphic(Paths.image('editors/eventIcon'));
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
				note.x -= GRID_SIZE * laneCount();
			} else if(daSus != null) {
				note.x += GRID_SIZE * laneCount();
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
			if(note.mustPress != _song.notes[curSec].mustHitSection) noteDataToCheck += laneCount();
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
		if(noteDataToCheck > -1 && note.mustPress != _song.notes[curSec].mustHitSection) noteDataToCheck += laneCount();

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
		if (d < 0 || d >= strumLineNotes.members.length) return;
		var delnote = false;
		if(strumLineNotes.members[d].overlaps(curRenderedNotes))
		{
			curRenderedNotes.forEachAlive(function(note:Note)
			{
				if (note.overlapsPoint(new FlxPoint(strumLineNotes.members[d].x + 1,strumLine.y+1)) && note.noteData == d%laneCount())
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

	// =====================================================================
	// Extra Keys support (ported from the 0.7.3 editor + Psych EK 0.3 ideas)
	// =====================================================================

	/** Place the two health icons above the middle of each side's lanes. */
	function updateIconPositions():Void
	{
		if (leftIcon == null || rightIcon == null) return;
		var half:Float = GRID_SIZE * laneCount();
		leftIcon.setPosition((half / 2) - (leftIcon.width / 2), -100);
		rightIcon.setPosition(((half * 2) - (half / 2)) - (rightIcon.width / 2), -100);
	}

	/**
	 * Keep the global Note / ExtraKeys static state in sync with _song.mania.
	 * Note picks its frame prefix and colors from these globals, NOT from this
	 * class, so without this a 9K chart would still draw 4-direction arrows.
	 */
	function syncChartManiaGlobals():Void
	{
		var m:Int = (_song != null && _song.mania != null) ? _song.mania : 3;
		var cols:Int = m + 1;
		ExtraKeysHandler.ensure();
		ClientPrefs.ensureEKArrowColors();

		if (PlayState.SONG != null) PlayState.SONG.mania = m;
		Note.uiManiaOverride = -1;
		Note.editorDualMode = false;
		Note.editorPlrKeys = cols;
		Note.editorOppKeys = cols;

		var names:Array<String> = [];
		var ek = (ExtraKeysHandler.instance != null) ? ExtraKeysHandler.instance.data : null;
		if (ek != null && ek.keys != null && ek.keys.length > m)
		{
			var mode = ek.keys[m];
			for (i in 0...cols)
			{
				var g:Int = (mode != null && mode.notes != null && i < mode.notes.length) ? mode.notes[i] : i;
				var anim = (ek.animations != null && g >= 0 && g < ek.animations.length) ? ek.animations[g] : null;
				names.push((anim != null && anim.note != null) ? anim.note : 'purple');
			}
		}
		else names = ['purple', 'blue', 'green', 'red'];
		Note.colArray = names;
	}

	/** Rebuild the vortex strum arrows for the current mania (count + texture tier). */
	function rebuildStrumLineNotes():Void
	{
		if (strumLineNotes == null) return;
		for (arrow in strumLineNotes)
			if (arrow != null) arrow.destroy();
		strumLineNotes.clear();

		if (PlayState.SONG != null) PlayState.SONG.mania = (_song.mania != null) ? _song.mania : 3;
		Note.uiManiaOverride = -1;
		Note.editorDualMode = true;
		Note.editorPlrKeys = laneCount();
		Note.editorOppKeys = laneCount();

		for (i in 0...(laneCount() * 2))
		{
			var arrow:StrumNote = new StrumNote(GRID_SIZE * (i + 1), strumLine.y, i % laneCount(), 0);
			arrow.setGraphicSize(GRID_SIZE, GRID_SIZE);
			arrow.updateHitbox();
			arrow.playAnim('static', true);
			arrow.scrollFactor.set(1, 1);
			strumLineNotes.add(arrow);
		}

		Note.uiManiaOverride = -1;
		Note.editorDualMode = false;
		Note.editorPlrKeys = laneCount();
		Note.editorOppKeys = laneCount();
		strumLineNotes.visible = strumLineNotes.active = vortex;
		remove(strumLineNotes);
		add(strumLineNotes);
	}

	// --- horizontal track buttons -----------------------------------------
	function bringTrackButtonsToFront():Void
	{
		if (btnTrackLeft != null) { remove(btnTrackLeft); add(btnTrackLeft); }
		if (btnTrackRight != null) { remove(btnTrackRight); add(btnTrackRight); }
	}

	function updateTrackButtonsVisibility():Void
	{
		var show:Bool = ((_song.mania != null) ? _song.mania : 3) >= 3;
		if (btnTrackLeft != null) btnTrackLeft.visible = show;
		if (btnTrackRight != null) btnTrackRight.visible = show;
	}

	public function setTrackButtonTheme(useFlixel:Bool, ?customStyle:StyledButtonStyle):Void
	{
		if (btnTrackLeft == null || btnTrackRight == null) return;
		var st:StyledButtonStyle = (customStyle != null) ? customStyle
			: (useFlixel ? StyledButtonStyle.flixelClassic() : StyledButtonStyle.glassBlue());
		st.size = 44;
		btnTrackLeft.setStyle(st);
		btnTrackRight.setStyle(st);
	}

	// --- stashed notes: reversible mania changes --------------------------
	/** Restore stashed notes from the chart object, falling back to a session copy. */
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
				? haxe.Json.parse(haxe.Json.stringify(cached)) : [];
		}
		syncStashedNotes(songKey);
	}

	static function sanitizeStashedNotes(raw:Dynamic):Array<Dynamic>
	{
		var out:Array<Dynamic> = [];
		if (raw == null || !Std.isOfType(raw, Array)) return out;
		for (s in (cast raw:Array<Dynamic>))
		{
			if (s == null || s.sec == null || s.lane == null || s.key == null
				|| s.side == null || s.data == null || !Std.isOfType(s.data, Array))
				continue;
			// Keep noteType in both directions so legacy stash records still restore.
			if (s.type == null && s.data.length > 3) s.type = s.data[3];
			if (s.type != null && (s.data.length < 4 || s.data[3] == null)) s.data[3] = s.type;
			out.push(s);
		}
		return out;
	}

	/** Mirror the working copy into the chart object + session cache. */
	function syncStashedNotes(?songKey:String):Void
	{
		if (_song == null) return;
		var key:String = (songKey != null) ? songKey : Std.string(_song.song);
		var copy:Array<Dynamic> = haxe.Json.parse(haxe.Json.stringify(stashedNotes));
		if (copy.length == 0)
			Reflect.deleteField(_song, STASH_FIELD);
		else
			Reflect.setField(_song, STASH_FIELD, copy);
		sessionStashBySong.set(key, copy);
	}

	/**
	 * Re-encode every existing note when the mania changes. Notes that no longer
	 * fit are stashed (never deleted) and put back when the mania is raised again.
	 * Stash records "side + lane within side", so 6K -> 4K -> 6K is lossless.
	 */
	function remapChartNotesForMania(oldMania:Int, newMania:Int):Void
	{
		var oldCols:Int = oldMania + 1;
		var newCols:Int = newMania + 1;

		for (secIdx in 0..._song.notes.length)
		{
			var section = _song.notes[secIdx];
			if (section == null || section.sectionNotes == null) continue;
			var kept:Array<Dynamic> = [];
			for (note in section.sectionNotes)
			{
				var lane:Int = note[1];
				if (lane < 0) { kept.push(note); continue; }
				var isPlr:Bool = lane < oldCols;
				var keyIdx:Int = isPlr ? lane : (lane - oldCols);
				if (keyIdx > newMania)
				{
					stashedNotes.push({sec: secIdx, lane: lane, side: isPlr, key: keyIdx, data: note,
						type: (note.length > 3) ? note[3] : null});
					continue;
				}
				note[1] = isPlr ? keyIdx : (newCols + keyIdx);
				kept.push(note);
			}
			section.sectionNotes = kept;
		}

		if (stashedNotes.length == 0) return;
		var stillStashed:Array<Dynamic> = [];
		var touched:Map<Int, Bool> = new Map();
		for (s in stashedNotes)
		{
			if (s.key > newMania) { stillStashed.push(s); continue; }
			var secIdx:Int = s.sec;
			if (secIdx < 0 || secIdx >= _song.notes.length || _song.notes[secIdx] == null
				|| _song.notes[secIdx].sectionNotes == null)
			{
				stillStashed.push(s);
				continue;
			}
			s.data[1] = s.side ? s.key : (newCols + s.key);
			if (s.data.length > 3 && s.data[3] == null && s.type != null) s.data[3] = s.type;
			_song.notes[secIdx].sectionNotes.push(s.data);
			touched.set(secIdx, true);
		}
		stashedNotes = stillStashed;
		for (idx in touched.keys())
			_song.notes[idx].sectionNotes.sort(function(a, b) return (a[0] < b[0]) ? -1 : ((a[0] > b[0]) ? 1 : 0));
		syncStashedNotes();
	}


	/**
	 * Read-only noteType name resolution. The original 0.6.3 editor converted numeric
	 * indices in place on every redraw (and removed i[3] when empty), silently mutating
	 * chart data. This never writes back.
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

	/** '' = default, '?' = broken/unknown type, otherwise the dropdown index. */
	function noteTypeLabel(raw:Array<Dynamic>):String
	{
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
		if (typeInt < 0) return '?';
		return (typeInt > 0) ? '' + typeInt : '';
	}

	/** Shared label style for noteType badges and stash warnings. */
	function makeNoteLabel(text:String, note:Note):AttachedFlxText
	{
		var t:AttachedFlxText = new AttachedFlxText(0, 0, 100, text, 24);
		t.setFormat(Paths.font("vcr.ttf"), 24, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE_FAST, FlxColor.BLACK);
		t.xAdd = (GRID_SIZE - 100) / 2;
		t.yAdd = 6;
		t.borderSize = 1;
		t.sprTracker = note;
		return t;
	}

	function usingHSVNoteColors():Bool
		return ClientPrefs.data.arrowColorMode == 'HSV';

	function stashedSusColor():FlxColor
		return usingHSVNoteColors() ? FlxColor.BLACK : STASHED_NOTE_ORANGE;

	/**
	 * Tint a stashed warning arrow through a LOCAL shader instance. Setting
	 * FlxSprite.color directly is a multiply that the note shader eats, and
	 * touching the shared RGB palette / ColorSwap would tint every normal note
	 * of the same style.
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
			var pal:shaders.RGBPalette = new shaders.RGBPalette();
			pal.r = STASHED_NOTE_ORANGE;
			pal.g = STASHED_NOTE_HIGHLIGHT;
			pal.b = STASHED_NOTE_ORANGE_DARK;
			var ref:shaders.RGBPalette.RGBShaderReference = new shaders.RGBPalette.RGBShaderReference(note, pal);
			ref.allowNew = false;
			note.rgbShader = ref;
			note.shader = pal.shader;
			note.color = FlxColor.WHITE;
		}
	}

	/** Ghost-render stashed notes so the user can see data is still there. */
	function renderStashedNotes():Void
	{
		if (stashedRenderedNotes == null || stashedNotes.length == 0) return;
		for (s in stashedNotes)
		{
			var secIdx:Int = s.sec;
			if (secIdx != curSec && secIdx != curSec + 1) continue;
			var raw:Array<Dynamic> = s.data;
			var copy:Array<Dynamic> = raw.copy();
			copy[1] = s.lane;
			if (s.type != null && (copy.length < 4 || copy[3] == null)) copy[3] = s.type;
			var note:Note = setupNoteData(copy, false);
			applyStashedWarningColor(note);
			stashedRenderedNotes.add(note);
			if (note.sustainLength > 0)
			{
				var sus:FlxSprite = setupSusNote(note, getSectionBeats());
				sus.color = stashedSusColor();
				curRenderedSustains.add(sus);
			}
			// '?!' broken type / '3!' known type / '!' default.
			curRenderedNoteType.add(makeNoteLabel(noteTypeLabel(copy) + '!', note));
		}
	}

	/** Warn before exporting / leaving when notes are parked outside the layout. */
	function confirmChartMania(action:Void->Void):Void
	{
		if (stashedNotes.length == 0 || ignoreWarnings)
		{
			action();
			return;
		}
		var secs:Map<Int, Bool> = new Map();
		for (s in stashedNotes) secs.set(s.sec, true);
		var secCount:Int = 0;
		for (k in secs.keys()) secCount++;
		openSubState(new Prompt(
			stashedNotes.length + ' note(s) are outside the current ' + laneCount() + 'K layout'
			+ '\n(spread over ' + secCount + ' section(s)).\n\n'
			+ 'They are kept in the chart JSON and put back\n'
			+ 'when you raise Mania again.\n\nProceed anyway?',
			0, action, null, false, 'PROCEED', 'CANCEL'));
	}

	// --- undo / redo snapshots --------------------------------------------
	function makeSnapshot():Dynamic
	{
		return {
			notes: haxe.Json.parse(haxe.Json.stringify(_song.notes)),
			events: haxe.Json.parse(haxe.Json.stringify(_song.events)),
			mania: (_song.mania != null) ? _song.mania : 3,
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
		stashedNotes = (snap.stashed != null) ? snap.stashed : [];
		syncStashedNotes();
		if (snap.mania != null)
		{
			_song.mania = snap.mania;
			Reflect.setField(_song, 'keyCount', snap.mania + 1);
			if (maniaStepper != null)
			{
				suppressManiaEvent = true;
				maniaStepper.value = snap.mania;
				suppressManiaEvent = false;
			}
		}
		Conductor.mapBPMChanges(_song);
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

	/** Enter -> PlayState (extracted so confirmChartMania can wrap it). */
	function goPlayState():Void
	{
		autosaveSong();
		FlxG.mouse.visible = false;
		PlayState.SONG = prepareSongForPlayState();
		FlxG.sound.music.stop();
		if(vocals != null) vocals.stop();
		StageData.loadDirectory(_song);
		LoadingState.loadAndSwitchState(new PlayState());
	}

	function clearSong():Void
	{
		for (daSection in 0..._song.notes.length)
		{
			_song.notes[daSection].sectionNotes = [];
		}

		updateGrid();
	}

	private function addNote(strum:Null<Float> = null, data:Null<Int> = null, type:Null<Int> = null):Void
	{
		//curUndoIndex++;
		//var newsong = _song.notes;
		//	undos.push(newsong);
		var noteStrum = getStrumTime(dummyArrow.y * (getSectionBeats() / 4), false) + sectionStartTime();
		var noteData = Math.floor((FlxG.mouse.x - GRID_SIZE) / GRID_SIZE);
		var noteSus = 0;
		var daAlt = false;
		var daType = currentType;

		if (strum != null) noteStrum = strum;
		if (data != null) noteData = data;
		if (type != null) daType = type;

		var maxLane:Int = laneCount() * 2 - 1;
		if (noteData > maxLane) noteData = maxLane;
		pushUndo();
		if(noteData > -1)
		{
			_song.notes[curSec].sectionNotes.push([noteStrum, noteData % (laneCount() * 2), noteSus, noteTypeIntMap.get(daType)]);
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
			_song.notes[curSec].sectionNotes.push([noteStrum, (noteData + laneCount()) % (laneCount() * 2), noteSus, noteTypeIntMap.get(daType)]);
		}

		//trace(noteData + ', ' + noteStrum + ', ' + curSec);
		strumTimeInputText.text = '' + curSelectedNote[0];

		updateGrid();
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

	function loadJson(song:String):Void
	{
		//shitty null fix, i fucking hate it when this happens
		//make it look sexier if possible
		// 0.6.3 read the difficulty list off CoolUtil; this engine keeps it in backend.Difficulty.
		var diff:String = Difficulty.getString();
		if (diff != null && diff != Difficulty.getDefault())
			PlayState.SONG = Song.loadFromJson(song.toLowerCase() + '-' + diff, song.toLowerCase());
		else
			PlayState.SONG = Song.loadFromJson(song.toLowerCase(), song.toLowerCase());
		MusicBeatState.resetState();
	}

	function autosaveSong():Void
	{
		FlxG.save.data.autosave = Json.stringify({
			"song": _song
		});
		FlxG.save.flush();
	}

	/**
	 * The editor keeps the chart in the 0.6.3 layout, but `PlayState` only understands psych_v1.
	 * Upgrade it right before leaving; coming back re-runs `create()`, which downgrades it again.
	 */
	function prepareSongForPlayState():SwagSong
	{
		var m:Int = (_song.mania != null) ? _song.mania : 3;
		Reflect.setField(_song, 'mania', m);
		Reflect.setField(_song, 'keyCount', m + 1);
		LegacyChartFormat.toPsychV1(_song);
		return _song;
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
				var col:Int = data % laneCount();
				var mustPress:Bool = (data < laneCount());
				var n:Note = new Note(strumTime, col, null, false, true);
				n.mustPress = mustPress;
				n.sustainLength = sustain;
				n.noteType = noteType;
				noteList.push(n);
			}
		}

		if (FlxG.sound.music != null) FlxG.sound.music.pause();
		Conductor.songPosition = 0;
		// 0.6.3 没有对手音轨概念，用空 FlxSound 占位（play() 在 _sound==null 时安全早退）
		openSubState(new EditorPlayState(noteList, [vocals, new FlxSound()]));
	}

	function clearEvents() {
		pushUndo();
		_song.events = [];
		updateGrid();
	}

	private function saveLevel()
	{
		if(_song.events != null && _song.events.length > 1) _song.events.sort(sortByTime);
		syncStashedNotes();

		// Export from a clone: the in-memory chart keeps mania/keyCount for editing,
		// but a 4K chart must contain NO engine-specific fields so that a real
		// Psych 0.6.3 build can still read it. Multi-key charts need mania+keyCount
		// so Song.convert() picks the right column count on reload.
		var out:Dynamic = haxe.Json.parse(haxe.Json.stringify(_song));
		out.generatedBy = GENERATED_BY;
		Reflect.deleteField(out, "format");
		Reflect.deleteField(out, "mania");
		Reflect.deleteField(out, "keyCount");
		Reflect.deleteField(out, "playerKeyCount");
		Reflect.deleteField(out, STASH_FIELD);
		var m:Int = (_song.mania != null) ? _song.mania : 3;
		if (m != 3)
		{
			Reflect.setField(out, "mania", m);
			Reflect.setField(out, "keyCount", m + 1);
		}
		if (stashedNotes.length > 0)
			Reflect.setField(out, STASH_FIELD, haxe.Json.parse(haxe.Json.stringify(stashedNotes)));

		var json = {
			"song": out
		};

		var data:String = Json.stringify(json, "\t");

		if ((data != null) && (data.length > 0))
		{
			#if mobile
			// 移动端：静默写入外部存储，并提示保存路径
			var saveName:String = Paths.formatToSongPath(_song.song) + "_063.json";
			StorageUtil.saveContent(saveName, data.trim(), false);
			CoolUtil.showPopUp('File saved successfully to: ' + StorageUtil.getExternalStorageDirectory() + 'saves/' + saveName, 'Success!');
			#else
			// 桌面/网页：文件选择框，保存后不弹信息（仅日志记录）
			_file = new FileReference();
			_file.addEventListener(Event.COMPLETE, onSaveComplete);
			_file.addEventListener(Event.CANCEL, onSaveCancel);
			_file.addEventListener(IOErrorEvent.IO_ERROR, onSaveError);
			_file.save(data.trim(), Paths.formatToSongPath(_song.song) + "_063.json");
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

		var data:String = Json.stringify(json, "\t");

		if ((data != null) && (data.length > 0))
		{
			#if mobile
			var saveName:String = "events_063.json";
			StorageUtil.saveContent(saveName, data.trim(), false);
			CoolUtil.showPopUp('File saved successfully to: ' + StorageUtil.getExternalStorageDirectory() + 'saves/' + saveName, 'Success!');
			#else
			_file = new FileReference();
			_file.addEventListener(Event.COMPLETE, onSaveComplete);
			_file.addEventListener(Event.CANCEL, onSaveCancel);
			_file.addEventListener(IOErrorEvent.IO_ERROR, onSaveError);
			_file.save(data.trim(), "events_063.json");
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
