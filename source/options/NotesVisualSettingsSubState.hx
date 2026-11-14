package options;

/**
 * 音符与轨道视觉 —— 分类重组阶段 2 自动生成。
 * 选项来自：GameplaySettingsSubState.hx, ExtraGameplaySettingSubState.hx, CompatibilitySettingsSubState.hx, SpamChartSettingsSubState.hx, VisualsSettingsSubState.hx
 * 共 28 项；辅助函数按需从源文件带入。
 */
import states.PlayState;
import objects.KeyViewer;
import backend.MusicBeatState;
import flixel.text.FlxText;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.util.FlxTimer;
import backend.CustomFadeTransition;
import backend.ClientPrefs;
import states.MainMenuState;
import objects.Note;
import objects.StrumNote;
import objects.NoteSplash;
import objects.Alphabet;

class NotesVisualSettingsSubState extends BaseOptionsMenu
{
	// 音符 / 溅射预览组（切皮肤与颜色模式时实时预览）
	var noteOptionID:Int = -1;
	var notes:FlxTypedGroup<StrumNote>;
	var splashes:FlxTypedGroup<NoteSplash>;
	var noteY:Float = 90;
	var notesShown:Bool = false;
	var noteSkinList:Array<String> = [];
	var splashSkinList:Array<String> = [];
	function changeNoteSkin(note:StrumNote)
	{
		var baseSkin:String = Note.defaultNoteSkin;
		var postfix:String = Note.getNoteSkinPostfix();
		var customBase:String = baseSkin + postfix;

		var customExists:Bool = false;
		if(ClientPrefs.data.arrowColorMode == 'HSV')
		{
			var parts:Array<String> = customBase.split('/');
			var filename:String = parts.pop();
			var folder:String = parts.join('/');
			customExists = Paths.fileExists('images/$folder/hsv/$filename.png', IMAGE) || Paths.fileExists('images/$customBase.png', IMAGE);
		}
		else
		{
			customExists = Paths.fileExists('images/$customBase.png', IMAGE);
		}

		var skin:String = customExists ? Note.getNoteSkinPath(customBase) : Note.getNoteSkinPath(baseSkin);

		note.texture = skin;
		note.reloadNote();
		note.playAnim('static');
	}

	private function onChangeLaneCover()
	{
		if (PlayState.instance != null) PlayState.instance.createLaneCovers();
	}

	function onChangeNoteSkin()
	{
		ensurePreview();
		notes.forEachAlive(function(note:StrumNote) {
			changeNoteSkin(note);
			note.centerOffsets();
			note.centerOrigin();
		});
	}

	function onChangeSplashSkin()
	{
		var skin:String = NoteSplash.defaultNoteSplash + NoteSplash.getSplashSkinPostfix();
		ensurePreview();
		for (splash in splashes)
			splash.loadSplash(skin);

		playNoteSplashes();
	}

	function playNoteSplashes()
	{
		if (splashes == null || splashes.members.length == 0) return;
		try playNoteSplashesUnsafe() catch (e:Dynamic) {}
	}

	function playNoteSplashesUnsafe()
	{

		var rand:Int = 0;
		if (splashes.members[0] != null && splashes.members[0].maxAnims > 1)
			rand = FlxG.random.int(0, splashes.members[0].maxAnims - 1); // For playing the same random animation on all 4 splashes

		for (splash in splashes)
		{
			splash.revive();

			splash.spawnSplashNote(0, 0, splash.ID, null, false);
			if (splash.maxAnims > 1)
				splash.noteData = splash.noteData % Note.colArray.length + (rand * Note.colArray.length);

			var anim:String = splash.playDefaultAnim();
			var conf = splash.config.animations.get(anim);
			var offsets:Array<Float> = [0, 0];

			var minFps:Int = 22;
			var maxFps:Int = 26;
			if (conf != null)
			{
				offsets = conf.offsets;

				minFps = conf.fps[0];
				if (minFps < 0) minFps = 0;

				maxFps = conf.fps[1];
				if (maxFps < 0) maxFps = 0;
			}

			splash.offset.set(10, 10);
			if (offsets != null)
			{
				splash.offset.x += offsets[0];
				splash.offset.y += offsets[1];
			}

			if (splash.animation.curAnim != null)
				splash.animation.curAnim.frameRate = FlxG.random.int(minFps, maxFps);
		}
	}

	var previewBuilt:Bool = false;
	function ensurePreview():Void
	{
		if (previewBuilt) return;
		previewBuilt = true;
		for (i in 0...Note.colArray.length)
		{
			try
			{
				var note:StrumNote = new StrumNote(370 + (560 / Note.colArray.length) * i, -200, i, 0);
				changeNoteSkin(note);
				notes.add(note);

				try
				{
					var splash:NoteSplash = new NoteSplash(0, 0, NoteSplash.defaultNoteSplash + NoteSplash.getSplashSkinPostfix());
					splash.inEditor = true;
					splash.babyArrow = note;
					splash.ID = i;
					splash.kill();
					splashes.add(splash);
				}
				catch (e:Dynamic) {}
			}
			catch (e:Dynamic) {}
		}
	}

override function changeSelection(change:Int = 0, skipRefresh:Bool = false, skipDesc:Bool = false)
	{
		super.changeSelection(change, skipRefresh, skipDesc);

		// 预览组可能尚未建立（父类构造期间就会调用一次），直接跳过动画
		if (curOption == null || notes == null || notes.members.length == 0) return;

		// 预览只是装饰：任何资源异常都不该让整个设置页进不去
		try
		{
		switch(curOption.variable)
		{
			case 'noteSkin', 'splashSkin', 'splashAlpha':
				ensurePreview();
				if (notes.members.length == 0) return;
				if(!notesShown)
				{
					for (note in notes.members)
					{
						if (note == null) continue;
						FlxTween.cancelTweensOf(note);
						FlxTween.tween(note, {y: noteY}, Math.abs(note.y / (200 + noteY)) / 3, {ease: FlxEase.quadInOut});
					}
				}
				notesShown = true;
				if(curOption.variable.startsWith('splash') && notes.members[0] != null && Math.abs(notes.members[0].y - noteY) < 25) playNoteSplashes();

			default:
				if(notesShown)
				{
					for (note in notes.members)
					{
						if (note == null) continue;
						FlxTween.cancelTweensOf(note);
						FlxTween.tween(note, {y: -200}, Math.abs(note.y / (200 + noteY)) / 3, {ease: FlxEase.quadInOut});
					}
				}
				notesShown = false;
		}
		}
		catch (e:Dynamic)
		{
			notesShown = false;
		}
	}

	override function destroy()
		{
			Note.globalRgbShaders = [];
			Note.globalColorSwapShaders = [];
			super.destroy();
		}

	function onChangeArrowColorMode()
	{
		Note.globalRgbShaders = [];
		Note.globalColorSwapShaders = [];
		if (notes == null || splashes == null) return;

		notes.forEachAlive(function(n) n.destroy());
		notes.clear();
		splashes.forEachAlive(function(s) s.destroy());
		splashes.clear();
		previewBuilt = false;
		ensurePreview();
	}

	override public function onOptionsBuilt():Void
	{
		super.onOptionsBuilt();
		// 预览位置由 BaseOptionsMenu 的初始 changeSelection 处理，这里不做二次触发
	}


	public function new()
	{
		title = Language.get('notes_visual_menu');
		rpcTitle = 'Notes & Strums Menu';


		// 音符 / 溅射预览：原 VisualsSettingsSubState 在构造函数开头创建，分类重组时遗漏
		notes = new FlxTypedGroup<StrumNote>();
		splashes = new FlxTypedGroup<NoteSplash>();
		// 进入页面即建好音符箭头预览（每个对象单独 try/catch，缺资源只跳过该项）。
		// 之前「进不去」的真正原因是 optionsArray 未初始化，与预览无关，故恢复即时创建。
		ensurePreview();

		var option: Option;








		// 皮肤列表：准备逻辑不包 if，保证 var 声明与对应 Option 永远在同一块里；
		// list 为空时 insert 默认皮肤后至少有一项，选项始终有效。
		var noteSkins:Array<String> = Mods.mergeAllTextsNamed('images/noteSkins/list.txt');
		if(!noteSkins.contains(ClientPrefs.data.noteSkin))
			ClientPrefs.data.noteSkin = ClientPrefs.defaultData.noteSkin;
		noteSkins.insert(0, ClientPrefs.defaultData.noteSkin);
		noteSkinList = noteSkins;


		option = new Option(Language.get('arrow_color_mode'),
			Language.get('arrow_colormode_desc'),
			'arrowColorMode',
			STRING,
			['RGB', 'HSV']);
		addOption(option);
		option.onChange = onChangeArrowColorMode;
		option = new Option(Language.get('note_skins'),
			Language.get("noteskin_desc"),
			'noteSkin',
			STRING,
			noteSkins);
		option.onChange = onChangeNoteSkin;
		addOption(option);
		noteOptionID = (optionsArray != null) ? optionsArray.length - 1 : -1;
		var noteSplashes:Array<String> = Mods.mergeAllTextsNamed('images/noteSplashes/list.txt');
		if(!noteSplashes.contains(ClientPrefs.data.splashSkin))
			ClientPrefs.data.splashSkin = ClientPrefs.defaultData.splashSkin;
		noteSplashes.insert(0, ClientPrefs.defaultData.splashSkin);
		splashSkinList = noteSplashes;
		option = new Option(Language.get('note_splashes'),
			Language.get("notesplash_desc"),
			'splashSkin',
			STRING,
			noteSplashes);
		option.onChange = onChangeSplashSkin;
		addOption(option);
		option = new Option(Language.get('downscroll'),
			Language.get("downscroll_desc"),
			'downScroll',
			BOOL);
		addOption(option);
		option = new Option(Language.get('middlescroll'),
			Language.get("middlescroll_desc"),
			'middleScroll',
			BOOL);
		addOption(option);
		option = new Option(Language.get('cpu_strums'),
			Language.get("cpu_strums_desc"),
			'cpuStrums',
			BOOL);
		addOption(option);
		option = new Option(Language.get('opponent_notes'),
			Language.get("opponentnotes_desc"),
			'opponentStrums',
			BOOL);
		addOption(option);
		option = new Option(Language.get('opponent_splashes'),
			Language.get("opponent_splashes_desc"),
			'opponentSplashes',
			BOOL);
		addOption(option);
		option = new Option(Language.get('note_splash_opacity'),
			Language.get("notesplashopacity_desc"),
			'splashAlpha',
			PERCENT);
		option.scrollSpeed = 1.6;
		option.minValue = 0.0;
		option.maxValue = 1;
		option.changeValue = 0.1;
		option.decimals = 1;
		addOption(option);


		option.onChange = playNoteSplashes;
		option = new Option(Language.get('single_note_splash_anim'),
			Language.get("single_splashanim_desc"),
			'forceSingleSplashAnim',
			BOOL);
		addOption(option);
		var holdCoverSkins:Array<String> = Mods.mergeAllTextsNamed('images/holdCover/list.txt');
		if(!holdCoverSkins.contains(ClientPrefs.data.holdCoverSkin))
			ClientPrefs.data.holdCoverSkin = ClientPrefs.defaultData.holdCoverSkin;
		holdCoverSkins.insert(0, ClientPrefs.defaultData.holdCoverSkin);
		option = new Option(Language.get('hold_cover_skin'),
			Language.get("hold_cover_skin_desc"),
			'holdCoverSkin',
			STRING,
			holdCoverSkins);
		addOption(option);
		option = new Option(Language.get('hold_covers'),
			Language.get("hold_covers_desc"),
			'holdCovers',
			BOOL);
		addOption(option);
		option = new Option(Language.get('opponent_hold_covers'),
			Language.get("opponent_hold_covers_desc"),
			'opponentHoldCovers',
			BOOL);
		addOption(option);
		option = new Option(Language.get('lane_cover_player'),
			Language.get("lane_cover_p1_desc"),
			'laneCoverAlphaP1',
			FLOAT);
		option.scrollSpeed = 2;
		option.minValue = 0;
		option.maxValue = 1;
		option.changeValue = 0.05;
		option.decimals = 2;
		option.onChange = onChangeLaneCover;
		addOption(option);
		option = new Option(Language.get('lane_cover_opponent'),
			Language.get("lane_cover_p2_desc"),
			'laneCoverAlphaP2',
			FLOAT);
		option.scrollSpeed = 2;
		option.minValue = 0;
		option.maxValue = 1;
		option.changeValue = 0.05;
		option.decimals = 2;
		option.onChange = onChangeLaneCover;
		addOption(option);
		option = new Option(Language.get('lane_cover_strum_alpha'),
			Language.get("lane_cover_strum_alpha_desc"),
			'laneCoverByStrumAlpha',
			BOOL);
		option.onChange = onChangeLaneCover;
		addOption(option);
	option = new Option(Language.get('hold_note_behind'),
		Language.get("hold_note_behind_desc"),
		'holdNoteBehind',
		BOOL);
	addOption(option);



		// ===== 动态窗口标题 (Dynamic Window Title) =====
		option = new Option(Language.get('force_hold_animations'),
			Language.get("force_hold_animations_desc"),
			'forceHoldAnimations',
			BOOL);
		addOption(option);
		option = new Option(Language.get('single_hold_animation'),
			Language.get("single_hold_note_animation_desc"),
			'singleHoldNoteAnimation',
			BOOL);
		addOption(option);



		// 自动重置箭头动画
		option = new Option(Language.get('keep_sing_animation'),
			Language.get("keep_sing_animation_desc"),
			'keepSingAnimation',
			BOOL);
		addOption(option);
		option = new Option(Language.get('auto_reset_strum_animation'),
			Language.get("auto_reset_strum_anim_desc"),
			'autoResetStrumAnim',
			BOOL);
		addOption(option);



		// Perfect 评级精灵回退至 Sick
		option = new Option(Language.get('ghost_effect_multi_press'),
			Language.get("ghost_effect_desc"),
			'ghostEffect',
			BOOL);
		addOption(option);
		option = new Option(Language.get('botplay_perfect_timing'),
			Language.get("botplay_perfect_timing_desc"),
			'botplayPerfectTiming',
			BOOL);
		addOption(option);
		option = new Option(Language.get('score_incrase_when_botplay'),
			Language.get("bot_addscore_desc"),
			'botplayScore',
			BOOL);
		addOption(option);





		super();

		add(notes);
		add(splashes);

	}
}
