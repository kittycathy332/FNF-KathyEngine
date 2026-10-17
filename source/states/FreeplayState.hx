package states;

import backend.WeekData;
import backend.Highscore;
import backend.Song;
import backend.SongMetadata;
import backend.Conductor;
import objects.HealthIcon;
import objects.MusicPlayer;
import options.GameplayChangersSubstate;
import substates.ResetScoreSubState;
import flixel.math.FlxMath;
import flixel.util.FlxColor;
import flixel.util.FlxDestroyUtil;
import flixel.tweens.FlxTween;
import openfl.utils.AssetType;
import openfl.utils.Assets;
import flash.media.Sound;
import haxe.Json;
import backend.ui.PsychUIInputText;
import backend.ui.PsychUIRadioGroup;
import backend.ui.PsychUIButton;
import states.editors.content.Prompt;
import flixel.ui.FlxButton;
import flixel.graphics.frames.FlxTileFrames;
import flixel.math.FlxPoint;
#if FEATURE_FILESYSTEM
import sys.FileSystem;
import sys.io.File;
import backend.Mods;
import android.FlxVirtualPad;
#end

class FreeplayState extends MusicBeatState
{
	public static var isFreeplayPlayingMusic:Bool = false;

	// 谱面数据缓存：避免试听和进入游戏时重复加载同一谱面
	private static var _songDataCache:Map<String, SwagSong> = new Map();
	private static var _songPathCache:Map<String, String> = new Map();
	// LRU 访问顺序：最近一次访问的 key 在队尾，超限时淘汰队首，限制单次会话内谱面缓存常驻量
	private static var _songCacheLRU:Array<String> = [];
	private static inline var SONG_CACHE_MAX:Int = 60;
	// 音频 mod 目录缓存：避免每次按空格时重复扫描所有 mod 目录
	private static var _audioModCache:Map<String, String> = new Map();
	// 当前试听加载过的音频绝对路径：停止试听/切换曲目时据此释放缓存，
	// 避免"换着听 N 首歌"时 Inst/Vocals 永久累积在 currentTrackedSounds。
	private static var _previewSoundFiles:Array<String> = [];
	// 上次执行低频主动 GC 的时间点，避免每帧跑 NativeGc 造成卡顿
	private static var _lastGcTime:Float = 0;
	private static inline var GC_INTERVAL:Float = 5.0;

	// 记录某 key 最近被访问/写入，并淘汰超出上限的最久未用项
	private static function touchSongCache(key:String):Void
	{
		var idx:Int = _songCacheLRU.indexOf(key);
		if (idx >= 0) _songCacheLRU.splice(idx, 1);
		_songCacheLRU.push(key);
		while (_songCacheLRU.length > SONG_CACHE_MAX)
		{
			var evict:String = _songCacheLRU.shift();
			_songDataCache.remove(evict);
			_songPathCache.remove(evict);
		}
	}

	// 后台预解析：在玩家还在浏览列表时就把选中曲目的谱面 JSON 解析好，
	// 这样按下确认键时不需要在主线程做 File.getContent + Json.parse，避免掉帧卡顿。
	// 采用“单个常驻工作线程 + 任务队列”取代原来“每首歌新建一个线程”的方式，
	// 避免频繁创建/销毁 OS 线程带来的开销与 GC（原来每首歌都会 spawn 一个短命线程，
	// 在歌曲较多时会造成不定时卡顿）。
	#if (sys && FEATURE_FILESYSTEM)
	private static var _prefetchMutex:sys.thread.Mutex = new sys.thread.Mutex();
	private static var _prefetchDone:Map<String, SwagSong> = new Map(); // 仅在持锁时访问
	private static var _prefetchBusy:Map<String, Bool> = new Map(); // 仅主线程访问
	private static var _prefetchFailed:Map<String, Bool> = new Map(); // 解析失败标记：避免每帧反复重试同一首

	// 任务队列：主线程投递，工作线程消费（用独立锁保护，避免与 _prefetchMutex 互相阻塞）
	private static var _prefetchQueueMutex:sys.thread.Mutex = new sys.thread.Mutex();
	private static var _prefetchQueue:Array<{key:String, path:String, poop:String}> = new Array();
	private static var _prefetchWorker:sys.thread.Thread = null;
	private static var _prefetchWorkerRunning:Bool = false;
	#end

	// 把后台线程解析好的谱面并入主缓存（只在主线程调用）
	private static function drainPrefetched():Void
	{
		#if (sys && FEATURE_FILESYSTEM)
		_prefetchMutex.acquire();
		for (key => data in _prefetchDone)
		{
			_prefetchBusy.remove(key);
			if (data != null && !_songDataCache.exists(key))
			{
				_songDataCache.set(key, data);
				touchSongCache(key);
			}
			else if (data == null)
				_prefetchFailed.set(key, true); // 解析失败：标记后不再反复重试
		}
		_prefetchDone.clear();
		_prefetchMutex.release();
		#end
	}

	// 懒启动一个常驻后台线程，循环消费 _prefetchQueue。
	// 空闲时短暂 sleep 让出 CPU，避免忙等占满核心；销毁时由 destroy() 置
	// _prefetchWorkerRunning=false 让线程在下一轮循环退出。
	private static function startPrefetchWorker():Void
	{
		#if (sys && FEATURE_FILESYSTEM)
		if (_prefetchWorker != null)
			return;

		_prefetchWorkerRunning = true;
		_prefetchWorker = sys.thread.Thread.create(() ->
		{
			while (_prefetchWorkerRunning)
			{
				var job:{key:String, path:String, poop:String} = null;
				_prefetchQueueMutex.acquire();
				if (_prefetchQueue.length > 0)
					job = _prefetchQueue.shift();
				_prefetchQueueMutex.release();

				if (job != null)
				{
					var parsed:SwagSong = null;
					try
					{
						parsed = Song.parseJSON(File.getContent(job.path), job.poop);
					}
					catch (e:Dynamic)
					{
						parsed = null;
					}

					_prefetchMutex.acquire();
					_prefetchDone.set(job.key, parsed);
					_prefetchMutex.release();

					Sys.sleep(0.003);
				}
				else
				{
					Sys.sleep(0.05); // 空闲时让出 CPU，避免忙等
				}
			}
		});
		#end
	}

	// 获取缓存的谱面数据，若不存在则加载并缓存
	private static function getCachedSongData(folder:String, poop:String, songLowercase:String):SwagSong
	{
		drainPrefetched();

		var cacheKey:String = folder + '_' + poop;
		var songData:SwagSong = _songDataCache.get(cacheKey);
		if (songData != null)
			touchSongCache(cacheKey);
		if (songData == null)
		{
			// Song.loadFromJson 内部已内置 Normal 难度兼容：
			// 无后缀谱面缺失时，回退尝试 -normal / 忽略大小写 / 已知拼写错误（如 -nuormal）变体。
			songData = Song.loadFromJson(poop, songLowercase);
			if (songData != null)
			{
				_songDataCache.set(cacheKey, songData);
				_songPathCache.set(cacheKey, Song.chartPath);
				touchSongCache(cacheKey);
			}
			return songData;
		}

		// 命中缓存时同样要重新应用全局状态，否则 PlayState.SONG 还停留在上一次加载的谱面
		return Song.applyChart(songData, songLowercase, _songPathCache.get(cacheKey));
	}

	// 谱面加载失败时的两行错误文案：第一行主错误，第二行列出实际尝试过的文件名
	static function getChartMissingMessage(poop:String):String
	{
		var tried:Array<String> = [];
		for (p in Song.lastTriedChartPaths)
		{
			var idx:Int = p.lastIndexOf('/');
			var idx2:Int = p.lastIndexOf('\\');
			if (idx2 > idx) idx = idx2;
			tried.push(idx >= 0 ? p.substr(idx + 1) : p);
		}
		if (tried.length == 0) tried.push(poop);
		return 'ERROR: Could not load chart file: $poop\n(Tried: ${tried.join(', ')})';
	}

	// 当前想要预解析的曲目 key，以及停留多久后才真正开始预解析（避免快速滚动列表时狂开线程）
	var prefetchKey:String = null;
	var prefetchDelay:Float = 0;
	private static inline var PREFETCH_DELAY:Float = 1.0;
	// 每帧预热图标数量上限：把“滚动时才加载纹理”的开销摊到空闲帧，
	// 同时让可见窗口在被滚到后能较快填充满，减少图标缺帧。
	private static inline var ICON_WARM_PER_FRAME:Int = 2;
	// 选中曲目上下各显示/预热多少个小图标（共 ±ICON_RADIUS）
	private static inline var ICON_RADIUS:Int = 8;

	function updateChartPrefetch(elapsed:Float):Void
	{
		#if (sys && FEATURE_FILESYSTEM)
		drainPrefetched();

		if (player.playingMusic || songs.length == 0 || curDifficulty < 0 || curSelected < 0 || curSelected >= songs.length)
			return;

		var meta:SongMetadata = songs[curSelected];
		var songLowercase:String = Paths.formatToSongPath(meta.songName);
		var poop:String = Highscore.formatSong(songLowercase, curDifficulty);
		var cacheKey:String = meta.folder + '_' + poop;

		if (cacheKey != prefetchKey)
		{
			prefetchKey = cacheKey;
			prefetchDelay = PREFETCH_DELAY;
			return;
		}

		if (prefetchDelay <= 0)
			return;

		prefetchDelay -= elapsed;
		if (prefetchDelay > 0)
			return;
		prefetchDelay = 0;

		if (_songDataCache.exists(cacheKey) || _prefetchBusy.exists(cacheKey) || _prefetchFailed.exists(cacheKey))
			return;

		// 路径解析必须留在主线程（依赖 Mods.currentModDirectory 等全局状态）。
		// getChartPath 内部已包含 Normal 难度（-normal / 忽略大小写 / 拼写错误）的兼容回退。
		var path:String = Song.getChartPath(poop, songLowercase);
		if (path == null || !FileSystem.exists(path))
			return; // 无文件（含打包进 assets 的谱面），跳过预取，走同步加载分支

		_prefetchBusy.set(cacheKey, true);
		_songPathCache.set(cacheKey, path);

		// 把任务投到队列，交给常驻工作线程处理（不在主线程新建线程）
		_prefetchQueueMutex.acquire();
		_prefetchQueue.push({key: cacheKey, path: path, poop: poop});
		_prefetchQueueMutex.release();
		startPrefetchWorker();
		#end
	}

	var songs:Array<SongMetadata> = [];
	var songsFull:Array<SongMetadata> = []; // 全部曲目（筛选前的完整列表）
	var searchTxt:PsychUIInputText;
	var searchLabel:FlxText;
	var searchContainer:FlxSpriteGroup; // 搜索框容器（默认常驻显示）
	private static final SEARCH_BOX_W:Int = 400;
	private static final SEARCH_Y_SHOWN:Float = 0;
	private static final SEARCH_Y_HIDDEN:Float = -60;

	var selector:FlxText;

	private static var curSelected:Int = 0;

	var lerpSelected:Float = 0;
	var curDifficulty:Int = -1;
	// 用于检测选择变化，仅在变化时触发图标预热，避免每帧空转造成 GC
	var lastWarmupSelected:Int = -999;

	private static var lastDifficultyName:String = Difficulty.getDefault();

	var scoreBG:FlxSprite;
	var scoreText:FlxText;
	var diffText:FlxText;
	var modText:FlxText; // 当前选中模组名称（显示在最高分数下方、选中难度上方）
	var lerpScore:Int = 0;
	var lerpRating:Float = 0;
	var intendedScore:Int = 0;
	var intendedRating:Float = 0;

	private var grpSongs:FlxTypedGroup<Alphabet>;
	private var grpIcons:FlxTypedGroup<HealthIcon>;
	private var curPlaying:Bool = false;

	private var iconArray:Array<HealthIcon> = null;
	private var iconLoadStatus:Array<Bool> = []; // 记录每个图标是否已加载
	// songTextArray[i] = songs[i] 的菜单条目：与 grpSongs.members 顺序解耦，支持分帧乱序构建
	private var songTextArray:Array<Alphabet> = [];
	private var _listBuildPriority:Array<Int> = null; // 分帧构建顺序：可见窗口优先，其余按序号
	private var _listBuildIndex:Int = -1; // 分帧构建游标；-1 表示已构建完毕
	// 进入 Freeplay 时只同步构建可见窗口，其余条目每空闲帧最多补建这么多条，
	// 把“几百首歌一次全建”的卡顿摊到进入后的前几帧。
	private static inline var LIST_BUILD_PER_FRAME:Int = 24;

	// 图标分帧构建：与文本列表同理，进入时只同步建 curSelected ± ICON_RADIUS 的可见图标，
	// 其余图标在 update() 空闲帧按 ICON_BUILD_PER_FRAME 逐帧补建，
	// 避免进入时一次性同步创建全部图标精灵（含文件系统探测）造成的卡顿。
	private var _iconBuildPriority:Array<Int> = null; // 图标分帧构建顺序：可见窗口优先，其余按序号
	private var _iconBuildIndex:Int = -1; // 图标分帧游标；-1 表示已构建完毕
	private static inline var ICON_BUILD_PER_FRAME:Int = 16;

	var bg:FlxSprite;
	var intendedColor:Int;
	private var bgScaleLerp:Float = 0; // Lerp插值进度 (0-1)
	private var bgBeatDuration:Float = 0; // 节拍动画总时长
	private var bgBeatElapsed:Float = 0; // 节拍动画已过去时间

	var missingTextBG:FlxSprite;
	var missingText:FlxText;

	var bottomString:String;
	var bottomText:FlxText;
	var bottomBG:FlxSprite;

	// 分帧加载指示：进入 Freeplay 后列表/图标仍在空闲帧补建时，在右下角显示加载字样
	private var loadingText:FlxText;

	var player:MusicPlayer;

	// BPM变化提示相关
	private var bpmText:FlxText;
	private var bpmTextBG:FlxSprite;
	private var _scorePrefix:String = null; // 缓存评分前缀文本，避免每帧 Language.get 分配字符串
	private var lastBPM:Float = -1;
	private var bpmDisplayTime:Float = 0;

	// 回放缓存相关
	private var cachedReplayText:String = "";
	private var cachedReplayIndex:Map<String, Array<String>> = new Map(); // 缓存回放文件索引：歌曲名 -> 难度列表
	#if FEATURE_FILESYSTEM
	private var replayButton:FlxButton = null; // 右上角 E 键回放按钮
	#end

	// 谱面信息面板（按 SPACE 预览时显示在右侧）
	private var chartInfoBG:FlxSprite;
	private var chartInfoTitle:FlxText;
	private var chartInfoText:FlxText;
	private var _chartInfoBuilt:Bool = false;
	private var _chartInfoVisible:Bool = true;

	override function create()
	{
		var __t0:Float = haxe.Timer.stamp();
		persistentUpdate = true;
		PlayState.isStoryMode = false;

		// 本状态内所有 HealthIcon 创建都带上 'freeplay' tag，退出时可一次性释放
		HealthIcon._excludeContext = 'freeplay';

		WeekData.reloadWeekFiles(false);
		var __t1:Float = haxe.Timer.stamp();
		trace('[FREEPLAY] reloadWeekFiles: ' + Math.round((__t1 - __t0) * 1000) + 'ms');

		#if DISCORD_ALLOWED
		// Updating Discord Rich Presence
		DiscordClient.changePresence("In the Menus", null);
		#end

		final accept:String = (controls.mobileC) ? "A" : "ACCEPT";
		final reject:String = (controls.mobileC) ? "B" : "BACK";

		if (WeekData.weeksList.length < 1)
		{
			FlxTransitionableState.skipNextTransIn = true;
			persistentUpdate = false;
			MusicBeatState.switchState(new states.ErrorState("NO WEEKS ADDED FOR FREEPLAY\n\nPress " + accept + " to go to the Week Editor Menu.\nPress "
				+ reject + " to return to Main Menu.",
				function() MusicBeatState.switchState(new states.editors.WeekEditorState()),
				function() MusicBeatState.switchState(new states.MainMenuState())));
			return;
		}

		var __addSongCount:Int = 0;
		var __t2:Float = haxe.Timer.stamp();
		for (i in 0...WeekData.weeksList.length)
		{
			if (weekIsLocked(WeekData.weeksList[i]))
				continue;

			var leWeek:WeekData = WeekData.weeksLoaded.get(WeekData.weeksList[i]);
			var leSongs:Array<String> = [];
			var leChars:Array<String> = [];

			for (j in 0...leWeek.songs.length)
			{
				leSongs.push(leWeek.songs[j][0]);
				leChars.push(leWeek.songs[j][1]);
			}

			WeekData.setDirectoryFromWeek(leWeek);
			for (song in leWeek.songs)
			{
				var colors:Array<Int> = song[2];
				if (colors == null || colors.length < 3)
				{
					colors = [146, 113, 253];
				}
				if (song.length > 3 && song[3] != null && Std.isOfType(song[3], String))
				{
					Mods.currentModDirectory = song[3];
				}
				else
				{
					WeekData.setDirectoryFromWeek(leWeek);
				}
				addSong(song[0], i, song[1], FlxColor.fromRGB(colors[0], colors[1], colors[2]));
				__addSongCount++;
			}
		}
		var __t3:Float = haxe.Timer.stamp();
		trace('[FREEPLAY] addSong ×' + __addSongCount + ': ' + Math.round((__t3 - __t2) * 1000) + 'ms');

		var __tModsLoad:Float = haxe.Timer.stamp();
		Mods.loadTopMod();
		trace('[FREEPLAY] Mods.loadTopMod: ' + Math.round((haxe.Timer.stamp() - __tModsLoad) * 1000) + 'ms');

		var __tBg:Float = haxe.Timer.stamp();
		bg = new FlxSprite().loadGraphic(Paths.image('menuDesat'));
		bg.antialiasing = ClientPrefs.data.antialiasing;
		add(bg);
		bg.screenCenter();
		bg.scale.set(1.0, 1.0);
		trace('[FREEPLAY] bg+menuDesat: ' + Math.round((haxe.Timer.stamp() - __tBg) * 1000) + 'ms');

		grpSongs = new FlxTypedGroup<Alphabet>();
		add(grpSongs);

		grpIcons = new FlxTypedGroup<HealthIcon>();
		add(grpIcons);

		// 初始化图标数组和加载状态数组
		iconArray = new Array<HealthIcon>();
		iconLoadStatus = new Array<Bool>();

		songs = songsFull;
		var __t4:Float = haxe.Timer.stamp();
		reloadSongList();
		var __t5:Float = haxe.Timer.stamp();
		trace('[FREEPLAY] reloadSongList: ' + Math.round((__t5 - __t4) * 1000) + 'ms');
		var __t7:Float = haxe.Timer.stamp();
		preloadAllIcons();
		var __t6:Float = haxe.Timer.stamp();
		trace('[FREEPLAY] preloadAllIcons: ' + Math.round((__t6 - __t7) * 1000) + 'ms');
		WeekData.setDirectoryFromWeek();

		if (curSelected >= songs.length)
			curSelected = 0;
		bg.color = songs[curSelected].color;
		intendedColor = bg.color;
		lerpSelected = curSelected;

		curDifficulty = Math.round(Math.max(0, Difficulty.defaultList.indexOf(lastDifficultyName)));

		scoreText = new FlxText(FlxG.width * 0.7, 5, 0, "", 32);
		scoreText.setFormat(Paths.font(Language.get('game_font2')), 32, FlxColor.WHITE, RIGHT);

		diffText = new FlxText(scoreText.x, scoreText.y + scoreText.height, 0, "", 24);
		diffText.font = scoreText.font;

		modText = new FlxText(scoreText.x, 0, 0, '', 16);
		modText.font = Paths.font("unifont-18.0.01.otf"); // 使用 unifont 以兼容多语言模组名与装饰符号
		var modDir:String = backend.Mods.currentModDirectory;
		var modName:String = (modDir != null && modDir.length > 0) ? modDir : 'Friday Night Funkin\'';
		modText.text = '◆ ' + modName + ' ◆';

		var height:Float = scoreText.y + scoreText.height + 2 + modText.height + 2 + diffText.height + 4;
		scoreBG = new FlxSprite(scoreText.x - 6, 0).makeGraphic(1, Std.int(height), 0xFF000000);
		scoreBG.alpha = 0.6;

		missingTextBG = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, FlxColor.BLACK);
		missingTextBG.alpha = 0.6;
		missingTextBG.visible = false;

		missingText = new FlxText(50, 0, FlxG.width - 100, '', 24);
		missingText.setFormat(Paths.font(Language.get('uitab_font')), 24, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		missingText.scrollFactor.set();
		missingText.visible = false;

		bottomBG = new FlxSprite(0, FlxG.height - 26).makeGraphic(FlxG.width, 26, 0xFF000000);
		bottomBG.alpha = 0.6;

		final space:String = (controls.mobileC) ? "X" : "SPACE";
		final control:String = (controls.mobileC) ? "C" : "CTRL";
		final reset:String = (controls.mobileC) ? "Y" : "RESET";

		var leText:String = LanguageBasic.getPhrase("freeplay_tip",
			"Press {1} to listen to the Song / Press {2} to open the Gameplay Changers Menu / Press {3} to Reset your Score and Accuracy.",
			[space, control, reset]);
		bottomString = leText;
		var size:Int = 16;
		bottomText = new FlxText(bottomBG.x, bottomBG.y + 4, FlxG.width, leText, size);
		bottomText.setFormat(Paths.font("vcr.ttf"), size, FlxColor.WHITE, CENTER);
		bottomText.scrollFactor.set();

		// 分帧加载提示：位于偏右下角（底部提示条上方），仅分帧构建进行中可见
		// 使用 uitab_font（按语言映射的像素字体，中文为 zh_hans）以正确渲染「加载中…」
		loadingText = new FlxText(0, 0, 0, '', 12);
		loadingText.setFormat(Paths.font(Language.get('uitab_font')), 12, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		loadingText.scrollFactor.set();
		loadingText.visible = false;
		add(loadingText);

		player = new MusicPlayer(this);

		// 创建BPM变化提示背景（先创建，渲染在底层）
		bpmTextBG = new FlxSprite(0, 0); // 初始位置为0,0
		// 预建一张小尺寸纯色底图，之后只通过缩放调整尺寸，
		// 避免每 250ms 用 FlxGraphic.fromRectangle 新建 BitmapData 造成 GC 尖刺。
		bpmTextBG.makeGraphic(8, 8, 0xFF000000);
		bpmTextBG.alpha = 0;
		bpmTextBG.scrollFactor.set(); // 固定位置

		// 创建BPM变化提示文本（后创建，渲染在顶层）
		bpmText = new FlxText(0, 20, 0, "", 32);
		bpmText.setFormat(Paths.font("vcr.ttf"), 32, FlxColor.WHITE, RIGHT);
		bpmText.alpha = 0;
		bpmText.scrollFactor.set(); // 固定位置

		// 缓存评分前缀文本，避免每帧 Language.get 分配字符串
		_scorePrefix = Language.get('score_best_desc');

		// 现在添加所有UI元素到正确的层级（在歌曲和图标之上）
		add(scoreBG);
		add(diffText);
		add(scoreText);
		add(modText);
		add(missingTextBG);
		add(missingText);
		add(bottomBG);
		add(bottomText);
		add(player);
		add(bpmTextBG);
		add(bpmText);

		// 谱面信息面板（右侧居中，预览时显示）
		var infoPanelW:Float = 280;
		var infoPanelH:Float = 200;
		var infoPanelX:Float = FlxG.width - infoPanelW - 12;
		var infoPanelY:Float = (FlxG.height - infoPanelH) / 2;

		chartInfoBG = new FlxSprite(infoPanelX, infoPanelY).makeGraphic(Std.int(infoPanelW), Std.int(infoPanelH), 0xFF000000);
		chartInfoBG.alpha = 0.3;
		chartInfoBG.visible = false;

		chartInfoTitle = new FlxText(infoPanelX + 8, infoPanelY + 6, infoPanelW - 16, 'CHART INFO', 18);
		chartInfoTitle.setFormat(Paths.font("vcr.ttf"), 18, FlxColor.YELLOW, LEFT);
		chartInfoTitle.visible = false;

		chartInfoText = new FlxText(infoPanelX + 8, infoPanelY + 28, infoPanelW - 16, '', 14);
		chartInfoText.setFormat(Paths.font("vcr.ttf"), 14, FlxColor.WHITE, LEFT);
		chartInfoText.visible = false;

		add(chartInfoBG);
		add(chartInfoTitle);
		add(chartInfoText);

		// 搜索 / 筛选（顶部居中，默认常驻显示）
		searchContainer = new FlxSpriteGroup();
		searchContainer.y = SEARCH_Y_SHOWN;

		// "SONGFILTER" 字样：放在文本框左侧、全大写、使用 unifont
		searchLabel = new FlxText(0, 0, 0, 'SONGFILTER', 16);
		searchLabel.setFormat(Paths.font("unifont-18.0.01.otf"), 24, FlxColor.WHITE);
		// 重新赋值文本以按新字体重算宽度（setFormat 不会自动更新 width）
		searchLabel.text = 'SONGFILTER: ';

		// 根据标签实测宽度自动偏移输入框，兼容不同文本长度
		var labelGap:Int = 8;
		var boxX:Float = searchLabel.width + labelGap;

		searchTxt = new PsychUIInputText(boxX, 0, SEARCH_BOX_W, '', 24, Paths.font("unifont-18.0.01.otf"), true);
		searchTxt.name = 'freeplay_search';
		searchTxt.maxLength = 32;
		// 标签在垂直方向上与输入框居中对齐
		searchLabel.y = (searchTxt.height - searchLabel.height) / 2;
		searchTxt.onChange = function(oldTxt:String, newTxt:String)
		{
			// 去除可能由 TAB 误输入的制表符，避免筛选异常
			if (newTxt.indexOf("\t") >= 0)
			{
				searchTxt.text = newTxt.split("\t").join("");
				return;
			}
			applyFilter(newTxt);
		};

		// 整个容器靠右上角，右边缘无外边距（标签 + 间距 + 输入框）
		searchContainer.x = FlxG.width - (boxX + SEARCH_BOX_W);

		searchContainer.add(searchLabel);
		searchContainer.add(searchTxt);
		add(searchContainer);

		changeSelection();
		updateTexts();

		// 预加载回放文件索引（异步，不阻塞主线程）
		preloadReplayIndex();

		addTouchPad('LEFT_FULL', 'A_B_C_X_Y_Z');

		#if FEATURE_FILESYSTEM
		#if !desktop
		// 右上角 E 键回放按钮（仅移动端显示）
		replayButton = new FlxButton(0, 0);
		replayButton.frames = FlxTileFrames.fromFrame(FlxVirtualPad.getFrames().getByName("e"), FlxPoint.get(44 * 3, 127));
		replayButton.resetSizeFromFrame();
		replayButton.solid = false;
		replayButton.immovable = true;
		replayButton.scrollFactor.set();
		replayButton.alpha = 0.8;
		replayButton.color = 0xFF7D00;
		replayButton.antialiasing = true;
		replayButton.scale.set(1.0, 1.0);
		replayButton.setPosition(FlxG.width - replayButton.frameWidth - 60, 60);
		replayButton.onDown.callback = function() loadReplay();
		replayButton.visible = false;
		add(replayButton);
		#end
		#end

		// 桌面端：进入 Freeplay 时显示鼠标（方便点击搜索框等），手柄模式下隐藏
		#if desktop
		FlxG.mouse.visible = !controls.controllerMode;
		#end

		super.create();
	}

	override function closeSubState()
	{
		changeSelection(0, false);
		persistentUpdate = true;
		lastLerpSelected = -9999; // 重置，确保下次更新时重新计算可见范围
		super.closeSubState();
		removeTouchPad();
		addTouchPad('LEFT_FULL', 'A_B_C_X_Y_Z');
	}

	public function addSong(songName:String, weekNum:Int, songCharacter:String, color:Int)
	{
		songsFull.push(new SongMetadata(songName, weekNum, songCharacter, color));
	}

	function weekIsLocked(name:String):Bool
	{
		var leWeek:WeekData = WeekData.weeksLoaded.get(name);
		return (!leWeek.startUnlocked
			&& leWeek.weekBefore.length > 0
			&& (!StoryMenuState.weekCompleted.exists(leWeek.weekBefore) || !StoryMenuState.weekCompleted.get(leWeek.weekBefore)));
	}

	/**
	 * 重建歌曲显示列表（grpSongs / grpIcons / 图标状态数组）。
	 * 在初始创建以及筛选条件变化时调用。
	 *
	 * 分帧构建：先同步建好"可见窗口"（±_drawDistance 文本行 + ±ICON_RADIUS 图标区），
	 * 其余条目在 update() 的空闲帧里按 LIST_BUILD_PER_FRAME 逐帧补建，避免几百首歌一次性全建卡顿。
	 */
	private function reloadSongList():Void
	{
		grpSongs.clear();
		grpIcons.clear();
		iconArray = new Array<HealthIcon>();
		iconLoadStatus = new Array<Bool>();
		songTextArray = new Array<Alphabet>();
		_lastIconVisibles = []; // 列表重建后清空图标可见缓存
		_lastVisibles = [];

		// 预填占位：分帧构建期间 updateVisibleItems 对未就绪条目做 null 跳过
		for (i in 0...songs.length)
		{
			songTextArray.push(null);
			iconArray.push(null);
			iconLoadStatus.push(false);
		}

		// 构建优先级：可见窗口排最前（同步建），其余按序号在空闲帧补建
		var center:Int = Math.round(Math.max(0, Math.min(songs.length - 1, curSelected)));
		_listBuildPriority = [];
		function addPriority(i:Int):Void
		{
			if (i >= 0 && i < songs.length && _listBuildPriority.indexOf(i) == -1)
				_listBuildPriority.push(i);
		}
		for (offset in (-_drawDistance)...(_drawDistance + 1))
			addPriority(center + offset);
		for (offset in (-ICON_RADIUS)...(ICON_RADIUS + 1))
			addPriority(center + offset);
		for (i in 0...songs.length)
			addPriority(i);

		// 同步先建可见窗口（Alphabet ±drawDistance + 图标 ±ICON_RADIUS），其余走空闲帧补建
		_listBuildIndex = 0;
		var windowBudget:Int = (_drawDistance * 2 + 1) + (ICON_RADIUS * 2 + 1);
		buildListBatch(windowBudget);
	}

	/**
	 * 按预算构建列表条目（Alphabet）。构建完成的条目由 updateVisibleItems 统一管理可见性。
	 * @param budget 本批最多新建条数；windowBudget 用于同步补建可见窗口，LIST_BUILD_PER_FRAME 用于空闲帧补建。
	 */
	private function buildListBatch(budget:Int):Void
	{
		if (_listBuildIndex < 0 || _listBuildPriority == null)
			return;

		var built:Int = 0;
		while (_listBuildIndex < _listBuildPriority.length && built < budget)
		{
			var i:Int = _listBuildPriority[_listBuildIndex++];
			if (i < 0 || i >= songs.length || songTextArray[i] != null)
				continue;

			var songText:Alphabet = new Alphabet(90, 320, songs[i].songName, true);
			songText.targetY = i;
			grpSongs.add(songText);

			songText.scaleX = Math.min(1, 980 / songText.width);
			songText.snapToPosition();

			// too laggy with a lot of songs, so i had to recode the logic for it
			songText.visible = songText.active = songText.isMenuItem = false;
			songTextArray[i] = songText;
			built++;
		}

		if (_listBuildIndex >= _listBuildPriority.length)
		{
			_listBuildIndex = -1;
			_listBuildPriority = null;
		}
	}

	/**
	 * 分帧加载进行中时，在右下角显示加载提示（含剩余待构建数量）；构建完成后自动隐藏。
	 * 仅在启用「Freeplay 分帧加载」且仍有条目/图标在空闲帧补建时显示。
	 */
	private function updateLoadingIndicator():Void
	{
		if (loadingText == null)
			return;

		var building:Bool = (_listBuildIndex >= 0 || _iconBuildIndex >= 0);
		loadingText.visible = building;
		if (!building)
			return;

		var remaining:Int = 0;
		if (_listBuildIndex >= 0 && _listBuildPriority != null)
			remaining += (_listBuildPriority.length - _listBuildIndex);
		if (_iconBuildIndex >= 0 && _iconBuildPriority != null)
			remaining += (_iconBuildPriority.length - _iconBuildIndex);

		loadingText.text = OptionsLanguage.get('freeplay_loading_text', 'Loading...') + (remaining > 0 ? ' (' + remaining + ')' : '');
		// 偏右下角：距右缘 24px，位于底部提示条（高度 26）上方
		loadingText.x = FlxG.width - loadingText.width - 24;
		loadingText.y = FlxG.height - 55;
	}

	/**
	 * 根据搜索框内容筛选曲目。
	 * @param filterStr 搜索关键字（大小写不敏感，支持空格）
	 */
	private function applyFilter(filterStr:String):Void
	{
		// 按空格分词，每个非空词都需出现在曲名中（多词 AND 搜索）。
		// 这样单独输入空格（或首尾空格）不会让列表变空，也自然支持带空格的曲名。
		var f:String = filterStr.toLowerCase().trim();
		var tokens:Array<String> = f.split(" ");

		if (tokens.length == 1 && tokens[0].length == 0)
		{
			songs = songsFull;
		}
		else
		{
			songs = songsFull.filter(function(s:SongMetadata):Bool
			{
				var name:String = s.songName.toLowerCase();
				for (token in tokens)
				{
					if (token.length > 0 && name.indexOf(token) == -1)
						return false;
				}
				return true;
			});
		}

		// 先钳位选中项再重建列表，让分帧构建的"可见窗口"围绕正确位置同步补建
		if (curSelected >= songs.length)
			curSelected = 0;
		lerpSelected = curSelected;

		reloadSongList();
		// 筛选后列表已重建，图标全部置为未加载；这里一次性全部预加载，
		// 避免退化为 warmupIcons 每帧 2 个的懒加载，导致滚动时图标逐个冒出的现象。
		preloadAllIcons();

		if (songs.length > 0)
		{
			changeSelection();
		}
		else
		{
			intendedScore = 0;
			intendedRating = 0;
			scoreText.text = '';
			diffText.text = '';
		}
	}

	var instPlaying:Int = -1;

	public static var vocals:FlxSound = null;
	public static var opponentVocals:FlxSound = null;

	var holdTime:Float = 0;

	var stopMusicPlay:Bool = false;
	var lastTypingTick:Int = -99999; // 上次处于搜索输入状态的帧时间

	override function update(elapsed:Float)
	{
		if (WeekData.weeksList.length < 1)
			return;

		// 空闲帧补建列表条目：可见窗口已在 reloadSongList 同步建好，
		// 其余按 LIST_BUILD_PER_FRAME 逐帧补齐，避免一次性全建卡顿
		if (_listBuildIndex >= 0)
			buildListBatch(LIST_BUILD_PER_FRAME);

		// 空闲帧补建图标：可见窗口已在 preloadAllIcons 同步建好，
		// 其余按 ICON_BUILD_PER_FRAME 逐帧补齐，避免进入时同步创建全部图标精灵
		if (_iconBuildIndex >= 0)
			buildIconsBatch(ICON_BUILD_PER_FRAME);

		// 分帧加载进行中时于右下角显示加载提示，构建完成后自动隐藏
		updateLoadingIndicator();

		// 是否正在搜索框中输入（避免空格/方向键等被 freeplay 逻辑拦截）
		var typingSearch:Bool = (searchTxt != null && PsychUIInputText.focusOn == searchTxt);
		if (typingSearch)
			lastTypingTick = FlxG.game.ticks;

		// 桌面端：未在播放预览音乐时恢复鼠标显示（播放时由 SPACE 分支隐藏）
		#if desktop
		if (!player.playingMusic && !controls.controllerMode && !FlxG.mouse.visible)
			FlxG.mouse.visible = true;
		#end

		// 未在播放预览时恢复搜索框与模组名文本显示（播放预览时由 SPACE 分支隐藏）
		if (!player.playingMusic && !searchContainer.visible)
			searchContainer.visible = true;
		if (!player.playingMusic && !modText.visible)
			modText.visible = true;

		// 谱面信息面板：仅在预览播放时显示，可通过 TAB 手动切换
		if (_chartInfoBuilt)
		{
			var showInfo:Bool = player.playingMusic && _chartInfoVisible;
			chartInfoBG.visible = showInfo;
			chartInfoTitle.visible = showInfo;
			chartInfoText.visible = showInfo;
		}

		if (FlxG.keys.justPressed.TAB)
		{
			_chartInfoVisible = !_chartInfoVisible;
		}

		// 后台预解析当前选中曲目的谱面，让按下确认键时直接命中缓存
		updateChartPrefetch(elapsed);

		// 仅在曲目切换时预热图标，避免每帧空转造成 GC 尖刺
		if (!player.playingMusic && curSelected != lastWarmupSelected)
		{
			lastWarmupSelected = curSelected;
			warmupIcons();
		}

		// 低频主动 GC：每 GC_INTERVAL 秒在空闲时跑一次 NativeGc，
		// 及时回收被 clearPreviewSounds / LRU 淘汰后沦为孤儿的 SwagSong、AudioBuffer 与废弃图标纹理，
		// 把"反反复复爆浆"的锯齿内存曲线压平成稳定的低位平台。
		_lastGcTime += elapsed;
		if (_lastGcTime >= GC_INTERVAL)
		{
			_lastGcTime = 0;
			#if cpp
			cpp.NativeGc.run(true);
			#end
		}

		if (FlxG.sound.music.volume < 0.7)
			FlxG.sound.music.volume += 0.5 * elapsed;

		// 更新Conductor.songPosition以触发beatHit
		if (player.playingMusic && FlxG.sound.music != null)
		{
			Conductor.songPosition = FlxG.sound.music.time + ClientPrefs.data.noteOffset;

			// 检测BPM变化并显示提示 - 使用getBPMFromSeconds获取当前时间点的实际BPM
			// 限制BPM检测频率，避免每帧都检测
			if (Conductor.songPosition % 250 < 16) // 每250ms检测一次
			{
				var currentBPM = Conductor.getBPMFromSeconds(Conductor.songPosition).bpm;
				if (currentBPM != lastBPM)
				{
					bpmText.text = 'BPM: ${Math.round(currentBPM)}';
					bpmText.x = FlxG.width - bpmText.width - 6;
					bpmText.y = diffText.y + diffText.height + 4;

					// 复用底图仅缩放，避免每 250ms 新建 BitmapData 造成 GC 尖刺
					refreshBpmBackground();

					bpmDisplayTime = 0;
				}
				lastBPM = currentBPM;
			}
		}

		// 更新BPM提示显示/隐藏
		if (bpmDisplayTime >= 0)
		{
			bpmDisplayTime += elapsed;
			if (bpmDisplayTime < 1.0) // 显示1秒
			{
				bpmText.alpha = 1;
				bpmTextBG.alpha = 0.6;
			}
			else if (bpmDisplayTime < 1.5) // 0.5秒淡出
			{
				var fade = (bpmDisplayTime - 1.0) / 0.5;
				bpmText.alpha = 1 - fade;
				bpmTextBG.alpha = 0.6 * (1 - fade);
			}
			else
			{
				bpmText.alpha = 0;
				bpmTextBG.alpha = 0;
			}
		}

		// 背景缩放Lerp动画（从1.05过渡回1）
		if (bg != null && bg.scale.x > 1.0)
		{
			bgBeatElapsed += elapsed;

			// 计算插值进度 (0-1)
			bgScaleLerp = Math.min(bgBeatElapsed / bgBeatDuration, 1.0);

			// 使用立方缓出函数使过渡更自然
			var easedProgress = 1 - Math.pow(1 - bgScaleLerp, 3);
			var scale = FlxMath.lerp(1.05, 1.0, easedProgress);
			bg.scale.set(scale, scale);
		}

		// 图标缩放Lerp动画（从1.1过渡回1）
		if (iconArray != null && iconArray[curSelected] != null && iconArray[curSelected].scale.x > 1.0)
		{
			iconBeatElapsed += elapsed;

			// 计算插值进度 (0-1)
			iconScaleLerp = Math.min(iconBeatElapsed / iconBeatDuration, 1.0);

			// 使用立方缓出函数使过渡更自然
			var easedProgress = 1 - Math.pow(1 - iconScaleLerp, 3);
			var scale = FlxMath.lerp(1.1, 1.0, easedProgress);
			iconArray[curSelected].scale.set(scale, scale);
		}

		lerpScore = Math.floor(FlxMath.lerp(intendedScore, lerpScore, Math.exp(-elapsed * 24)));
		lerpRating = FlxMath.lerp(intendedRating, lerpRating, Math.exp(-elapsed * 12));

		if (Math.abs(lerpScore - intendedScore) <= 10)
			lerpScore = intendedScore;
		if (Math.abs(lerpRating - intendedRating) <= 0.01)
			lerpRating = intendedRating;

		// 用无临时数组的方式格式化评分百分比，减少每帧 GC 压力
		var ratingStr:String = buildRatingString(lerpRating);

		var shiftMult:Int = 1;
		if ((FlxG.keys.pressed.SHIFT || touchPad.buttonZ.pressed) && !player.playingMusic)
			shiftMult = 3;

		if (!player.playingMusic && !typingSearch && songs.length > 0)
		{
			// scoreText.text = LanguageBasic.getPhrase('personal_best', 'PERSONAL BEST: {1} ({2}%)', [lerpScore, ratingSplit.join('.')]);
			// 值未变化时不要重设 text，避免每帧重建 FlxText 位图（主要 GC / 重绘来源）
			var scoreStr:String = _scorePrefix + ' ' + lerpScore + ' (' + ratingStr + '%)';
			if (scoreText.text != scoreStr)
				scoreText.text = scoreStr;
			positionHighscore();

			if (songs.length > 1)
			{
				if (FlxG.keys.justPressed.HOME)
				{
					curSelected = 0;
					changeSelection();
					holdTime = 0;
				}
				else if (FlxG.keys.justPressed.END)
				{
					curSelected = songs.length - 1;
					changeSelection();
					holdTime = 0;
				}
				if (controls.UI_UP_P)
				{
					changeSelection(-shiftMult);
					holdTime = 0;
				}
				if (controls.UI_DOWN_P)
				{
					changeSelection(shiftMult);
					holdTime = 0;
				}

				if (controls.UI_DOWN || controls.UI_UP)
				{
					var checkLastHold:Int = Math.floor((holdTime - 0.5) * 10);
					holdTime += elapsed;
					var checkNewHold:Int = Math.floor((holdTime - 0.5) * 10);

					if (holdTime > 0.5 && checkNewHold - checkLastHold > 0)
						changeSelection((checkNewHold - checkLastHold) * (controls.UI_UP ? -shiftMult : shiftMult));
				}

				if (FlxG.mouse.wheel != 0)
				{
					FlxG.sound.play(Paths.sound('scrollMenu'), 0.2);
					changeSelection(-shiftMult * FlxG.mouse.wheel, false);
				}
			}

			if (controls.UI_LEFT_P && !typingSearch)
			{
				changeDiff(-1);
				_updateSongLastDifficulty();
			}
			else if (controls.UI_RIGHT_P && !typingSearch)
			{
				changeDiff(1);
				_updateSongLastDifficulty();
			}
		}

		if (controls.BACK)
		{
			var wasTyping:Bool = typingSearch || (FlxG.game.ticks - lastTypingTick) < 250;
			if (wasTyping)
			{
				// 搜索框聚焦时：仅 ESC 取消焦点；BACKSPACE 交给输入框删除字符，二者均不返回主菜单
				if (FlxG.keys.justPressed.ESCAPE && PsychUIInputText.focusOn != null)
					PsychUIInputText.focusOn = null;
			}
			else if (player.playingMusic)
			{
				FlxG.sound.music.stop();
				// 停止试听时释放全部试听音频缓存，让内存回落到试听前的基线
				clearPreviewSounds();
				destroyFreeplayVocals();
				FlxG.sound.music.volume = 0;
				instPlaying = -1;

				player.playingMusic = false;
				player.switchPlayMusic();

				// 重置Conductor状态
				Conductor.songPosition = 0;
				lastBeatHit = -1;

				// 隐藏BPM提示
				bpmText.alpha = 0;
				bpmTextBG.alpha = 0;
				bpmDisplayTime = -1;
				lastBPM = -1;

				FlxG.sound.playMusic(Paths.menuMusicAudio(), 0);
				FlxTween.tween(FlxG.sound.music, {volume: 1}, 1);
			}
			else
			{
				persistentUpdate = false;
				FlxG.sound.play(Paths.sound('cancelMenu'));
				MusicBeatState.switchState(new MainMenuState());
			}
		}

		if ((FlxG.keys.justPressed.CONTROL || touchPad.buttonC.justPressed) && !player.playingMusic)
		{
			persistentUpdate = false;
			openSubState(new GameplayChangersSubstate());
			removeTouchPad();
		}
		else if ((FlxG.keys.justPressed.SPACE || touchPad.buttonX.justPressed) && !typingSearch && songs.length > 0)
		{
			if (instPlaying != curSelected && !player.playingMusic)
			{
				// 切换试听新歌前，释放上一次试听累积的音频缓存，避免多首歌音频永久驻留
				clearPreviewSounds();
				destroyFreeplayVocals();
				FlxG.sound.music.volume = 0;

				Mods.currentModDirectory = songs[curSelected].folder;
				var songLowercase:String = songs[curSelected].songName.toLowerCase();
				var poop:String = Highscore.formatSong(songLowercase, curDifficulty);
				var songData:SwagSong = null;
				try
				{
					songData = getCachedSongData(songs[curSelected].folder, poop, songLowercase);
				}
				catch (e:haxe.Exception)
				{
					// 谱面解析异常（如 JSON 损坏）时的错误处理
					var errorStr:String = e.message;
					if (errorStr.contains('There is no TEXT asset with an ID of'))
						errorStr = 'Missing file: ' + errorStr.substring(errorStr.indexOf(songLowercase), errorStr.length - 1);
					else
						errorStr += '\n\n' + e.stack;

					missingText.text = 'ERROR WHILE LOADING CHART:\n$errorStr';
					missingText.screenCenter(Y);
					missingText.visible = true;
					missingTextBG.visible = true;
					FlxG.sound.play(Paths.sound('cancelMenu'));
					chartInfoBG.visible = false;
					chartInfoTitle.visible = false;
					chartInfoText.visible = false;
					_chartInfoBuilt = false;

					// 必须调用 super.update 推进虚拟按键的 input.update()（JUST_PRESSED→PRESSED），
					// 否则 buttonX.justPressed 会一直为 true，错误分支每帧重复执行导致卡死 + 反复 cancelMenu
					updateTexts(elapsed);
					super.update(elapsed);
					return;
				}

				if (songData == null) {
					// 显示错误信息（两行：主错误 + 实际尝试过的文件名）
					missingText.text = getChartMissingMessage(poop);
					missingText.screenCenter(Y);
					missingText.visible = true;
					missingTextBG.visible = true;
					FlxG.sound.play(Paths.sound('cancelMenu'));
					chartInfoBG.visible = false;
					chartInfoTitle.visible = false;
					chartInfoText.visible = false;
					_chartInfoBuilt = false;

					// 必须调用 super.update 推进虚拟按键的 input.update()（JUST_PRESSED→PRESSED），
					// 否则 buttonX.justPressed 会一直为 true，错误分支每帧重复执行导致卡死 + 反复 cancelMenu
					updateTexts(elapsed);
					super.update(elapsed);
					return;
				}

						buildChartInfo(songData);

						// 设置Conductor的BPM信息以支持beat检测
						Conductor.bpm = PlayState.SONG.bpm;
						Conductor.mapBPMChanges(PlayState.SONG);

				// 显示初始BPM
				bpmText.text = 'BPM: ${Math.round(Conductor.bpm)}';
				bpmText.x = FlxG.width - bpmText.width - 6;
				bpmText.y = diffText.y + diffText.height + 4;

				// 复用底图仅缩放，避免新建 BitmapData 造成 GC 尖刺
				refreshBpmBackground();

				bpmDisplayTime = 0;
				lastBeatHit = -1; // 重置beat检测

			// 先确定这首歌所属音频目录：优先用当前歌曲登记的 folder，缺失再用 findModWithSong 兜底，
			// 与 PlayState 一致；Inst 与人声统一从 audioModDir 用 loadSongAudio 加载（不回退 funkin）。
			// 存在性探测只查文件系统，绝不 loadSongAudio —— 原实现会把整段 Inst/Voices 解码进
			// currentTrackedSounds 且不登记释放，浏览期间音频缓存只增不减。
			function modHasAudio(mod:String, song:String, fileBase:String):Bool
			{
				return Paths.songAudioExists(song, fileBase, mod);
			}

			// 探测某 mod 是否含有该曲音频：含 SpecialInst/SpecialVocal 的带后缀文件也算。
			function modHasSong(mod:String, song:String):Bool
			{
				if (modHasAudio(mod, song, 'Inst') || modHasAudio(mod, song, 'Voices')) return true;
				var si:String = (PlayState.SONG.specialInst != null && PlayState.SONG.specialInst.length > 0) ? PlayState.SONG.specialInst : null;
				var sv:String = (PlayState.SONG.specialVocal != null && PlayState.SONG.specialVocal.length > 0) ? PlayState.SONG.specialVocal : null;
				if (si != null && modHasAudio(mod, song, 'Inst-$si')) return true;
				if (sv != null && modHasAudio(mod, song, 'Voices-$sv')) return true;
				return false;
			}

			function findModWithSong(song:String):String
			{
				if (_audioModCache.exists(song))
					return _audioModCache.get(song);
				var found:String = '';
				#if MODS_ALLOWED
				for (mod in Mods.getModDirectories())
				{
					if (modHasSong(mod, song))
					{
						found = mod;
						break;
					}
				}
				#end
				_audioModCache.set(song, found);
				return found;
			}

			var audioModDir:String = songs[curSelected].folder;
			if (!modHasSong(audioModDir, PlayState.SONG.song))
				audioModDir = findModWithSong(PlayState.SONG.song);
			if (audioModDir == null) audioModDir = '';

			if (PlayState.SONG.needsVoices)
			{

				// 优先：角色指定(postfix) > Voices-Player / Voices-Opponent > 无后缀合并 Voices
				function tryVoices(postfix:String):Sound
				{
					var fileBase:String = 'Voices';
					if (postfix != null) fileBase += '-' + postfix;
					// 追加 SpecialVocal 后缀，与 Inst 的 specialInst 对称：
					// 优先 Voices-{角色}-SpecialVocal > Voices-Player/Opponent-SpecialVocal > Voices-SpecialVocal，命中即止（任一存在即可）。
					if (PlayState.SONG.specialVocal != null && PlayState.SONG.specialVocal.length > 0)
						fileBase += '-' + PlayState.SONG.specialVocal;
					var fp:String = Paths.getSongAudioPath(PlayState.SONG.song, fileBase, audioModDir);
					trackPreviewSound(fp);
					return Paths.loadSongAudio(PlayState.SONG.song, fileBase, audioModDir);
				}

				vocals = new FlxSound();
				try
				{
					var playerVocalPostfix = getVocalFromCharacter(PlayState.SONG.player1);
					// 使用character名称作为vocal postfix，而不是固定的'Player'
					if (playerVocalPostfix == null || playerVocalPostfix.length < 1)
						playerVocalPostfix = PlayState.SONG.player1;

					var loadedVocals:Sound = tryVoices(playerVocalPostfix);
					if (loadedVocals == null) loadedVocals = tryVoices('Player');
					if (loadedVocals == null) loadedVocals = tryVoices(null);

					if (loadedVocals != null && loadedVocals.length > 0)
					{
						vocals.loadEmbedded(loadedVocals);
						FlxG.sound.list.add(vocals);
						vocals.persist = vocals.looped = true;
						vocals.volume = 0.8;
						vocals.play();
						vocals.pause();
					}
					else
						vocals = FlxDestroyUtil.destroy(vocals);
				}
				catch (e:Dynamic)
				{
					vocals = FlxDestroyUtil.destroy(vocals);
				}

				opponentVocals = new FlxSound();
					try
					{
						var oppVocalPostfix = getVocalFromCharacter(PlayState.SONG.player2);
						// 使用character名称作为vocal postfix，而不是固定的'Opponent'
						if (oppVocalPostfix == null || oppVocalPostfix.length < 1)
							oppVocalPostfix = PlayState.SONG.player2;

						var loadedVocals:Sound = tryVoices(oppVocalPostfix);
						if (loadedVocals == null) loadedVocals = tryVoices('Opponent');
						if (loadedVocals == null) loadedVocals = tryVoices(null);

							if (loadedVocals != null && loadedVocals.length > 0)
							{
								opponentVocals.loadEmbedded(loadedVocals);
								FlxG.sound.list.add(opponentVocals);
								opponentVocals.persist = opponentVocals.looped = true;
								opponentVocals.volume = 0.8;
								opponentVocals.play();
								opponentVocals.pause();
							}
							else
								opponentVocals = FlxDestroyUtil.destroy(opponentVocals);
						}
						catch (e:Dynamic)
						{
							opponentVocals = FlxDestroyUtil.destroy(opponentVocals);
						}
				}

				var instFileBase:String = (PlayState.SONG.specialInst != null && PlayState.SONG.specialInst.length > 0) ? 'Inst-${PlayState.SONG.specialInst}' : 'Inst';
				trackPreviewSound(Paths.getSongAudioPath(PlayState.SONG.song, instFileBase, audioModDir));
				FlxG.sound.playMusic(Paths.loadSongAudio(PlayState.SONG.song, instFileBase, audioModDir), 0.8);
				FlxG.sound.music.pause();
				instPlaying = curSelected;

			player.playingMusic = true;
			player.curTime = 0;
			player.switchPlayMusic();
			player.pauseOrResume(true);

			// 桌面端：空格播放预览时隐藏鼠标
			#if desktop
			FlxG.mouse.visible = false;
			#end

			// 播放预览时一并隐藏搜索框（标签 + 输入框）与模组名文本
			searchContainer.visible = false;
			modText.visible = false;

				// 重置BPM检测，并显示初始BPM
				lastBPM = -1;
				bpmDisplayTime = -1;

				// 设置音乐循环回调，循环时重置beat检测
				FlxG.sound.music.onComplete = function()
				{
					lastBeatHit = -1;
				};
			}
			else if (instPlaying == curSelected && player.playingMusic)
			{
				player.pauseOrResume(!player.playing);
			}
		}
		else if (controls.ACCEPT && !player.playingMusic && !typingSearch && songs.length > 0)
		{
			persistentUpdate = false;
			
			// 显式设置当前mod目录，确保谱面文件路径正确
			Mods.currentModDirectory = songs[curSelected].folder;
			
			var songLowercase:String = Paths.formatToSongPath(songs[curSelected].songName);
			var poop:String = Highscore.formatSong(songLowercase, curDifficulty);

			try
			{
				var songData:SwagSong = getCachedSongData(songs[curSelected].folder, poop, songLowercase);

				if (songData == null) {
								// 显示错误信息（两行：主错误 + 实际尝试过的文件名）
								missingText.text = getChartMissingMessage(poop);
								missingText.screenCenter(Y);
								missingText.visible = true;
								missingTextBG.visible = true;
								FlxG.sound.play(Paths.sound('cancelMenu'));

								updateTexts(elapsed);
								super.update(elapsed);
								return;
							}
							
							PlayState.isStoryMode = false;
							PlayState.storyDifficulty = curDifficulty;

							trace('CURRENT WEEK: ' + WeekData.getWeekFileName());
						}
						catch (e:haxe.Exception)
						{
							// Error handling

							var errorStr:String = e.message;
							if (errorStr.contains('There is no TEXT asset with an ID of'))
								errorStr = 'Missing file: ' + errorStr.substring(errorStr.indexOf(songLowercase), errorStr.length - 1); // Missing chart
							else
								errorStr += '\n\n' + e.stack;

							missingText.text = 'ERROR WHILE LOADING CHART:\n$errorStr';
							missingText.screenCenter(Y);
							missingText.visible = true;
							missingTextBG.visible = true;
							FlxG.sound.play(Paths.sound('cancelMenu'));

							updateTexts(elapsed);
							super.update(elapsed);
							return;
						}
			@:privateAccess
			if (PlayState._lastLoadedModDirectory != Mods.currentModDirectory)
			{
				Paths.freeGraphicsFromMemory();
			}
			// 桌面端：开始游玩时隐藏鼠标
			#if desktop
			FlxG.mouse.visible = false;
			#end
			LoadingState.prepareToSong();
			LoadingState.loadAndSwitchState(new PlayState());
			if (!ClientPrefs.data.loadingScreen) FlxG.sound.music.stop();
			stopMusicPlay = true;

			destroyFreeplayVocals();
			#if (MODS_ALLOWED && DISCORD_ALLOWED)
			DiscordClient.loadModRPC();
			#end
		}
		else if ((controls.RESET || touchPad.buttonY.justPressed) && !player.playingMusic && !typingSearch && songs.length > 0)
		{
			persistentUpdate = false;
			openSubState(new ResetScoreSubState(songs[curSelected].songName, curDifficulty, songs[curSelected].songCharacter));
			removeTouchPad();
			FlxG.sound.play(Paths.sound('scrollMenu'));
		}

		// Replay loading entry point: F7 loads latest saved replay (if exists)
		#if FEATURE_FILESYSTEM
		// 只在按下F7时扫描回放文件，而不是每帧都扫描
		if (FlxG.keys.justPressed.F7 && !player.playingMusic && songs.length > 0)
			loadReplay();
		#end

		updateModText();
		updateTexts(elapsed);
		super.update(elapsed);
	}

	/**
	 * 加载当前选中曲目与难度的最新回放（等价于桌面端 F7 的触发逻辑）
	 * 供 F7 与右上角 E 键按钮共用
	 */
	#if FEATURE_FILESYSTEM
	private function loadReplay():Void
	{
		if (songs.length == 0)
			return;
		var moddirLoad:String = (Mods.currentModDirectory != null && Mods.currentModDirectory.length > 0) ? Mods.currentModDirectory : 'global';
			var replayFolderLoad:String = Paths.mods(moddirLoad + '/replay');
			if (FileSystem.exists(replayFolderLoad))
			{
				var filesLoad:Array<String> = FileSystem.readDirectory(replayFolderLoad);
				if (filesLoad != null && filesLoad.length > 0)
				{
					// Get currently selected song name (formatted)
					var currentSongName:String = Paths.formatToSongPath(songs[curSelected].songName);

					// Get currently selected difficulty name
					var currentDifficultyName:String = Difficulty.getString(curDifficulty, false);

					// 收集所有匹配当前曲目+难度的回放（按修改时间降序排序）
					var matchedList:Array<Dynamic> = [];
					var latest:String = null;
					var latestM:Float = -1;
					var savedSongName:String = null;
					for (f in filesLoad)
					{
						if (!f.endsWith('.replay.json'))
							continue;

						var p = replayFolderLoad + '/' + f;
						try
						{
							var content:String = File.getContent(p);
							var obj:Dynamic = Json.parse(content);
							var meta:Dynamic = Reflect.field(obj, 'meta');
							if (meta != null && Reflect.hasField(meta, 'song'))
							{
								var replaySongName:String = Reflect.field(meta, 'song');
								var chartPath:Dynamic = (meta != null && Reflect.hasField(meta, 'chartPath')) ? Reflect.field(meta, 'chartPath') : null;
								var replayDifficulty:String = getDifficultyFromChartPath(chartPath, meta);

								// Check if replay matches current song and difficulty
								if (Paths.formatToSongPath(replaySongName) == currentSongName && replayDifficulty == currentDifficultyName)
								{
									var s = FileSystem.stat(p);
									var m:Float = 0;
									if (s != null && Reflect.hasField(s, 'mtime'))
									{
										var mt = Reflect.field(s, 'mtime');
										if (Std.isOfType(mt, Date))
											m = mt.getTime();
										else
											m = Std.parseFloat(Std.string(mt));
									}
									matchedList.push({path: p, mtime: m, name: f});
									if (m > latestM)
									{
										latestM = m;
										latest = p;
										savedSongName = replaySongName;
									}
								}
							}
						}
						catch (e:Dynamic)
						{
							trace('Failed to read replay file ${f}: ' + e);
						}
					}
					matchedList.sort((a:Dynamic, b:Dynamic) -> (Reflect.field(b, 'mtime') > Reflect.field(a, 'mtime') ? 1 : (Reflect.field(b, 'mtime') < Reflect.field(a, 'mtime') ? -1 : 0)));

					if (latest != null)
					{
						// 多个匹配回放时，弹出选择框让玩家挑选
						if (matchedList.length > 1)
						{
							openReplayPicker(matchedList);
							return;
						}
						// Load and play the replay（单条与回放列表选择共用）
						playReplay(latest);
					}
					else
					{
						// Show prompt: current song and difficulty have no replay
						missingText.text = Language.get('freeplay_replay_none', [songs[curSelected].songName, currentDifficultyName]);
						missingText.screenCenter(Y);
						missingText.visible = true;
						missingTextBG.visible = true;
					}
				}
			}
		}
		#end

	/**
	 * 播放指定的回放文件（单条回放与回放列表选择共用）
	 */
	#if FEATURE_FILESYSTEM
	private function playReplay(replayPath:String):Void
	{
		try
		{
			var content:String = File.getContent(replayPath);
			var obj:Dynamic = Json.parse(content);
			var replayArr = Reflect.field(obj, 'replay');
			var meta:Dynamic = Reflect.field(obj, 'meta');
			var chartPath:Dynamic = (meta != null && Reflect.hasField(meta, 'chartPath')) ? Reflect.field(meta, 'chartPath') : null;
			var savedM:Dynamic = (meta != null && Reflect.hasField(meta, 'chartMTime')) ? Reflect.field(meta, 'chartMTime') : null;
			var warn:Bool = false;
			if (chartPath != null && FileSystem.exists(chartPath))
			{
				var s2 = FileSystem.stat(chartPath);
				var curM = (s2 != null && Reflect.hasField(s2, 'mtime')) ? Reflect.field(s2, 'mtime') : null;
				if (savedM != null && curM != null && Std.string(savedM) != Std.string(curM))
					warn = true;
			}
			else
				warn = true;
			// 谱面匹配时直接进入游玩，不弹"是否开始回放"确认框；
			// 仅在谱面自保存后已变更（可能不同步）时才弹出警告确认，避免误收看信息一闪而过。
			if (warn)
				openReplayConfirm(replayPath, warn, replayArr, meta);
			else
				doPlayReplay(replayArr, meta);
			}
			catch (e:Dynamic)
			{
				trace('Failed to load replay: ' + e);
			}
	}

	/**
	 * 播放已解析的回放数据（单条回放与回放列表选择共用）。
	 * 加载谱面并切换到游玩状态，不弹二次确认。
	 */
	#if FEATURE_FILESYSTEM
	private function doPlayReplay(replayArr:Dynamic, meta:Dynamic):Void
	{
		// Set pending replay data and load song
		PlayState.pendingReplayData = replayArr;
		PlayState.shouldStartReplay = true;
		// 提取并保存判定设置
		if (meta != null && Reflect.hasField(meta, 'judgmentSettings'))
			PlayState.replayJudgmentSettings = Reflect.field(meta, 'judgmentSettings');
		else
			PlayState.replayJudgmentSettings = null;
		// 提取并保存游戏设置
		if (meta != null && Reflect.hasField(meta, 'gameplaySettings'))
			PlayState.replayGameplaySettings = Reflect.field(meta, 'gameplaySettings');
		else
			PlayState.replayGameplaySettings = null;

		// 显式设置当前mod目录，确保谱面文件路径正确
		Mods.currentModDirectory = songs[curSelected].folder;

		var songLowercase:String = Paths.formatToSongPath(songs[curSelected].songName);
		var poop:String = Highscore.formatSong(songLowercase, curDifficulty);
		var songData:SwagSong = getCachedSongData(songs[curSelected].folder, poop, songLowercase);

		if (songData == null) {
			// 显示错误信息
			missingText.text = Language.get('freeplay_error_chart_replay', [poop]);
			missingText.screenCenter(Y);
			missingText.visible = true;
			missingTextBG.visible = true;
			FlxG.sound.play(Paths.sound('cancelMenu'));
			return;
		}

		PlayState.isStoryMode = false;
		PlayState.storyDifficulty = curDifficulty;
		// 桌面端：开始游玩（回放）时隐藏鼠标
		#if desktop
		FlxG.mouse.visible = false;
		#end
		LoadingState.prepareToSong();
		LoadingState.loadAndSwitchState(new PlayState());
	}
	#end

	/**
	 * 播放回放前的二次确认框：每次通过 E 键或选择界面 Play 按钮播放回放时统一调用。
	 * 在真正进入游玩前展示回放名称，若谱面自保存后已变更（可能不同步）则叠加警告，
	 * 让玩家决定是继续播放还是取消，避免信息一闪而过直接跳转游玩。
	 */
	#if FEATURE_FILESYSTEM
	private function openReplayConfirm(replayPath:String, warn:Bool, replayArr:Dynamic, meta:Dynamic):Void
	{
		// 从路径中提取回放文件名，去掉 .replay.json 后缀，仅保留 <song>-<timestamp> 部分
		var fname:String = replayPath;
		var sIdx:Int = fname.lastIndexOf('/');
		if (sIdx >= 0)
			fname = fname.substr(sIdx + 1);
		if (StringTools.endsWith(fname, '.replay.json'))
			fname = fname.substr(0, fname.length - '.replay.json'.length);

		var msg:String = Language.get('freeplay_replay_confirm_msg', [fname]);
		msg += '\n' + Language.get('freeplay_replay_play_question');
		if (warn)
			msg += '\n\n' + Language.get('freeplay_replay_warn_msg');

		var titleKey:String = warn ? 'freeplay_replay_warn_title' : 'freeplay_replay_confirm_title';
		var sizeY:Float = warn ? 240 : 190;
		openSubState(new BasePrompt(500, sizeY, Language.get(titleKey),
			function(state:BasePrompt) {
				var msgText:FlxText = new FlxText(0, state.bg.y + 60, 460, msg, 14);
				msgText.font = Paths.font(Language.get('uitab_font'));
				msgText.alignment = CENTER;
				msgText.color = warn ? FlxColor.ORANGE : FlxColor.WHITE;
				msgText.screenCenter(X);
				msgText.cameras = state.cameras;
				state.add(msgText);

				var yesBtn:PsychUIButton = new PsychUIButton(0, state.bg.y + state.bg.height - 60, Language.get('freeplay_replay_play'), function()
				{
					state.close();
					doPlayReplay(replayArr, meta);
				}, 200, 40);
				yesBtn.cameras = state.cameras;
				yesBtn.screenCenter(X);
				yesBtn.x -= 110;
				state.add(yesBtn);

				var noBtn:PsychUIButton = new PsychUIButton(0, state.bg.y + state.bg.height - 60, Language.get('freeplay_replay_cancel'), function()
				{
					state.close();
				}, 200, 40);
				noBtn.normalStyle.bgColor = FlxColor.RED;
				noBtn.normalStyle.textColor = FlxColor.WHITE;
				noBtn.cameras = state.cameras;
				noBtn.screenCenter(X);
				noBtn.x += 110;
				state.add(noBtn);
			}
		));
	}
	#end

	/**
	 * 当一首曲目存在多个回放时，弹出选择框让玩家挑选要播放的回放
	 */
	private function openReplayPicker(matchedList:Array<Dynamic>):Void
	{
		if (matchedList == null || matchedList.length == 0)
			return;

		var juncDisplay:Array<String> = [];
		for (it in matchedList)
		{
			var name:String = Std.string(Reflect.field(it, 'name'));
			// 去掉 .replay.json 后缀，只保留 <song>-<timestamp> 部分
			// 命名格式: <song>-<timestamp>.replay.json
			juncDisplay.push(name);
		}

		var maxItems:Int = Std.int(Math.min(5, juncDisplay.length));
		var radioGrp:PsychUIRadioGroup = new PsychUIRadioGroup(0, 0, juncDisplay, 25, maxItems, false, 300);
		radioGrp.checked = 0;

		var hei:Float = radioGrp.height + 170;
		openSubState(new BasePrompt(480, hei, Language.get('freeplay_replay_picker_title'),
			function(state:BasePrompt) {
				radioGrp.screenCenter(X);
				radioGrp.y = state.bg.y + 80;
				radioGrp.cameras = state.cameras;
				state.add(radioGrp);

				var btn:PsychUIButton = new PsychUIButton(0, radioGrp.y + radioGrp.height + 20, Language.get('freeplay_replay_play'), function()
				{
					var selected = matchedList[radioGrp.checked];
					var path:String = Std.string(Reflect.field(selected, 'path'));
					state.close();
					// 交由 playReplay 统一处理（含谱面变更的二次确认）
					playReplay(path);
				}, 200, 40);
				btn.cameras = state.cameras;
				btn.screenCenter(X);
				btn.x -= 110;
				state.add(btn);

				// 取消按钮：移动端无 ESC 键盘，必须有可点的退出途径，否则界面关不掉
				var cancelBtn:PsychUIButton = new PsychUIButton(0, radioGrp.y + radioGrp.height + 20, Language.get('freeplay_replay_cancel'), function()
				{
					state.close();
				}, 200, 40);
				cancelBtn.normalStyle.bgColor = FlxColor.RED;
				cancelBtn.normalStyle.textColor = FlxColor.WHITE;
				cancelBtn.cameras = state.cameras;
				cancelBtn.screenCenter(X);
				cancelBtn.x += 110;
				state.add(cancelBtn);
			}
		));
	}
	#end

	function getVocalFromCharacter(char:String)
	{
		try
		{
			var path:String = Paths.getPath('characters/$char.json', TEXT);
			#if MODS_ALLOWED
			var character:Dynamic = Json.parse(File.getContent(path));
			#else
			var character:Dynamic = Json.parse(Assets.getText(path));
			#end
			return character.vocals_file;
		}
		catch (e:Dynamic)
		{
		}
		return null;
	}

	public static function destroyFreeplayVocals()
	{
		if (vocals != null)
			vocals.stop();
		vocals = FlxDestroyUtil.destroy(vocals);

		if (opponentVocals != null)
			opponentVocals.stop();
		opponentVocals = FlxDestroyUtil.destroy(opponentVocals);
	}

	// 记录当前试听加载过的音频绝对路径，供后续释放缓存
	public static function trackPreviewSound(file:String):Void
	{
		if (file != null && file.length > 0 && !_previewSoundFiles.contains(file))
			_previewSoundFiles.push(file);
	}

	// 释放当前试听累积的所有音频缓存并清空记录（保留正在播放的引用交由 GC 处理）
	public static function clearPreviewSounds():Void
	{
		for (f in _previewSoundFiles)
			Paths.releaseSoundCache(f);
		_previewSoundFiles = [];
	}

	function changeDiff(change:Int = 0)
	{
		if (player.playingMusic)
			return;
		if (songs.length == 0)
			return;

		curDifficulty = FlxMath.wrap(curDifficulty + change, 0, Difficulty.list.length - 1);
		#if !switch
		var ratingSongName:String = Paths.formatToSongPath(songs[curSelected].songName);
		intendedScore = Highscore.getScore(ratingSongName, curDifficulty);
		intendedRating = Highscore.getRating(ratingSongName, curDifficulty);
		#end

		lastDifficultyName = Difficulty.getString(curDifficulty, false);
		var displayDiff:String = Difficulty.getString(curDifficulty);
		if (Difficulty.list.length > 1)
			diffText.text = '< ' + displayDiff.toUpperCase() + ' >';
		else
			diffText.text = displayDiff.toUpperCase();

		positionHighscore();
		missingText.visible = false;
		missingTextBG.visible = false;
		
		// 更新底部回放文本（因为难度可能变化，回放的可用性也会变化）
		updateReplayBottomText(true); // 强制更新，确保切换难度时立即刷新
	}

	function changeSelection(change:Int = 0, playSound:Bool = true)
	{
		if (player.playingMusic)
			return;
		if (songs.length == 0)
			return;

		curSelected = FlxMath.wrap(curSelected + change, 0, songs.length - 1);
		_updateSongLastDifficulty();
		if (playSound)
			FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);

		var newColor:Int = songs[curSelected].color;
		if (newColor != intendedColor)
		{
			intendedColor = newColor;
			FlxTween.cancelTweensOf(bg);
			FlxTween.color(bg, 1, bg.color, intendedColor);
		}

		// 只在切换歌曲时更新可见对象，而不是每帧更新
		updateVisibleItems();

		Mods.currentModDirectory = songs[curSelected].folder;
		PlayState.storyWeek = songs[curSelected].week;
		Difficulty.loadFromWeek();

		#if FEATURE_FILESYSTEM
		// 切到新曲目（可能属于不同模组）后重建该模组目录下的回放索引，
		// 否则 E 键/底部提示会一直用进入 Freeplay 时旧模组的索引，导致不显示。
		preloadReplayIndex();
		#end

		var savedDiff:String = songs[curSelected].lastDifficulty;
		var lastDiff:Int = Difficulty.list.indexOf(lastDifficultyName);
		if (savedDiff != null && !Difficulty.list.contains(savedDiff) && Difficulty.list.contains(savedDiff))
			curDifficulty = Math.round(Math.max(0, Difficulty.list.indexOf(savedDiff)));
		else if (lastDiff > -1)
			curDifficulty = lastDiff;
		else if (Difficulty.list.contains(Difficulty.getDefault()))
			curDifficulty = Math.round(Math.max(0, Difficulty.defaultList.indexOf(Difficulty.getDefault())));
		else
			curDifficulty = 0;

		changeDiff();
		_updateSongLastDifficulty();
		updateReplayBottomText(true); // 强制更新，确保切换时立即刷新回放文本
		lastLerpSelected = -9999; // 重置，确保切换歌曲时立即更新可见范围
	}

	inline private function _updateSongLastDifficulty()
		songs[curSelected].lastDifficulty = Difficulty.getString(curDifficulty, false);

	/**
	 * Get difficulty name from chart file path or meta data
	 * @param chartPath Chart file path, e.g. ".../song-hard.json"
	 * @param meta Replay meta data containing difficulty information
	 * @return Difficulty name (e.g. Easy/Normal/Hard) or default difficulty
	 */
	private function getDifficultyFromChartPath(chartPath:String, ?meta:Dynamic):Null<String>
	{
		if (meta != null && Reflect.hasField(meta, 'difficulty'))
			return Reflect.field(meta, 'difficulty');
		if (chartPath == null)
			return Difficulty.getDefault();
		// Find the last path separator
		var lastSep = chartPath.lastIndexOf('/');
		if (lastSep == -1)
			lastSep = chartPath.lastIndexOf('\\');
		var fileName:String = (lastSep >= 0) ? chartPath.substr(lastSep + 1) : chartPath;
		// Remove .json extension
		if (fileName.endsWith('.json'))
			fileName = fileName.substr(0, fileName.length - 5);
		// Find the last dash separator like "song-hard.json"
		var lastDash = fileName.lastIndexOf('-');
		if (lastDash == -1)
		{
			// No dash found, file might be "song.json" without difficulty
			return Difficulty.getDefault();
		}
		var potentialDiff:String = fileName.substr(lastDash + 1);
		// Check if the extracted part matches any difficulty name
		for (diff in Difficulty.list)
		{
			if (Paths.formatToSongPath(diff) == Paths.formatToSongPath(potentialDiff))
				return diff;
		}
		// No matching difficulty found, return default
		return Difficulty.getDefault();
	}

	#if FEATURE_FILESYSTEM
	/**
	 * 预加载回放文件索引到内存缓存中
	 * 只扫描一次文件列表，避免重复的文件I/O操作
	 */
	private function preloadReplayIndex():Void
	{
		// 清空之前的缓存
		cachedReplayIndex = new Map();
		
		var moddirCheck:String = (Mods.currentModDirectory != null && Mods.currentModDirectory.length > 0) ? Mods.currentModDirectory : 'global';
		var replayFolderCheck:String = Paths.mods(moddirCheck + '/replay');
		
		if (!FileSystem.exists(replayFolderCheck))
		{
			// 回放文件夹不存在，直接返回
			return;
		}
		
		var files:Array<String> = FileSystem.readDirectory(replayFolderCheck);
		if (files == null || files.length == 0)
		{
			// 没有回放文件
			return;
		}
		
		// 遍历所有回放文件，建立索引
		for (f in files)
		{
			if (!f.endsWith('.replay.json'))
				continue;
			
			var p = replayFolderCheck + '/' + f;
			try
			{
				var content:String = File.getContent(p);
				var obj:Dynamic = Json.parse(content);
				var meta:Dynamic = Reflect.field(obj, 'meta');
				
				if (meta != null && Reflect.hasField(meta, 'song'))
				{
					var replaySongName:String = Reflect.field(meta, 'song');
					var formattedSongName:String = Paths.formatToSongPath(replaySongName);
					var chartPath:Dynamic = (meta != null && Reflect.hasField(meta, 'chartPath')) ? Reflect.field(meta, 'chartPath') : null;
					var replayDifficulty:String = getDifficultyFromChartPath(chartPath, meta);
					
					// 将难度添加到对应歌曲的列表中
					if (!cachedReplayIndex.exists(formattedSongName))
					{
						cachedReplayIndex.set(formattedSongName, []);
					}
					
					var difficultyList:Array<String> = cachedReplayIndex.get(formattedSongName);
					if (difficultyList.indexOf(replayDifficulty) == -1)
					{
						difficultyList.push(replayDifficulty);
					}
				}
			}
			catch (e:Dynamic)
			{
				trace('Failed to preload replay file ${f}: ' + e);
			}
		}
	}
	#end

	private function updateReplayBottomText(?forceUpdate:Bool = false):Void
	{
		if (songs.length == 0)
			return;
	#if FEATURE_FILESYSTEM
	// 仅在切换曲目/难度（forceUpdate）或进入时刷新提示文本；不再每帧/每0.5秒轮询文件系统。
	// FileSystem.exists/stat 在 Android 上会引入周期性微卡顿，而回放索引已在 create() 时预加载，
	// 后续只要基于内存中的缓存索引生成文本即可。
	if (!forceUpdate)
		return;

	// 使用预加载的索引，不再扫描文件系统
		var currentSongName:String = Paths.formatToSongPath(songs[curSelected].songName);
		var currentDifficultyName:String = Difficulty.getString(curDifficulty, false);
		
		var difficultyList:Array<String> = cachedReplayIndex.exists(currentSongName) ? cachedReplayIndex.get(currentSongName) : null;
		var songReplayCount:Int = (difficultyList != null) ? difficultyList.length : 0;
		var matchedReplayCount:Int = (difficultyList != null && difficultyList.indexOf(currentDifficultyName) != -1) ? 1 : 0;

		// 右上角 E 键回放按钮：当前曲目+难度有回放文件时显示
		if (replayButton != null)
			replayButton.visible = matchedReplayCount > 0;
		
		// Generate hint text based on index data
		if (songReplayCount > 0)
		{
			if (matchedReplayCount > 0)
			{
				// Current difficulty has matching replays
				#if !desktop
				cachedReplayText = bottomString + '\nThis song has ${songReplayCount} replay(s) - Tap the E button (top-right) to watch';
				#else
				cachedReplayText = bottomString + '\nThis song has ${songReplayCount} replay(s) - Press F7 to watch';
				#end
			}
			else
			{
				// Song has replays but current difficulty doesn't
				cachedReplayText = bottomString + '\nThis song has ${songReplayCount} replay(s) (but no replay for ${currentDifficultyName} difficulty)';
			}
		}
		else
		{
			// Current song has no replay files
			cachedReplayText = bottomString;
		}
		
		bottomText.text = cachedReplayText;
		
		// Adjust position based on text height to prevent overflow
		bottomText.y = FlxG.height - bottomText.height - 2;
		bottomBG.y = bottomText.y - 4;
		bottomBG.makeGraphic(FlxG.width, Std.int(bottomText.height) + 8, 0x99000000);
		#end
	}

	

	private function positionHighscore()
	{
		// 高分面板放置在右上角筛选器下方；
		// searchTxt 可能在 MusicPlayer 初始化时尚未创建，此时退化为顶部定位
		var topY:Float = (searchTxt != null) ? (SEARCH_Y_SHOWN + searchTxt.height + 6) : 10;
		scoreText.y = topY;
		modText.y = scoreText.y + scoreText.height + 2;
		diffText.y = modText.y + modText.height + 2;

		scoreText.x = FlxG.width - scoreText.width - 6;
		scoreBG.scale.x = FlxG.width - scoreText.x + 6;
		scoreBG.x = FlxG.width - (scoreBG.scale.x / 2);
		scoreBG.y = scoreText.y - 6;
		diffText.x = Std.int(scoreBG.x + (scoreBG.width / 2));
		diffText.x -= diffText.width / 2;
		modText.x = Std.int(scoreBG.x + (scoreBG.width / 2));
		modText.x -= modText.width / 2;
	}

	private function updateModText():Void
	{
		// 直接读当前选中曲目在歌单里记录的 folder，避免被全局 Mods.currentModDirectory
		// 的临时切换污染（图标预热等会临时改全局目录）。若为 '' 则视为原版。
		var modDir:String = (curSelected >= 0 && curSelected < songs.length) ? songs[curSelected].folder : '';
		var newName:String = (modDir != null && modDir.length > 0) ? modDir : 'Friday Night Funkin\'';
		var display:String = '◆ ' + newName + ' ◆';
		if (modText.text != display)
		{
			modText.text = display;
			// 文本变化导致宽度变化，重新按背景框居中
			modText.x = Std.int(scoreBG.x + (scoreBG.width / 2)) - Std.int(modText.width / 2);
		}
	}

	var _drawDistance:Int = 4;
	var _lastVisibles:Array<Int> = [];
	var _lastIconVisibles:Array<Int> = []; // 上一帧显示过的小图标索引，用于隐藏
	private var lastLerpSelected:Float = -9999; // 用于检测lerpSelected是否变化

	public function updateTexts(elapsed:Float = 0.0)
	{
		// 每帧更新lerp位置
		lerpSelected = FlxMath.lerp(curSelected, lerpSelected, Math.exp(-elapsed * 9.6));
		
		// updateVisibleItems 每帧都会刷新可见窗口（含对象位置），
		// 因此无需再用 lerpChanged 区分“重建”与“仅更新位置”两条分支。
		updateVisibleItems();
	}

	private function updateVisibleItems():Void
	{
		// 隐藏上一帧可见的文本对象（未构建的条目在 songTextArray 中为 null，跳过）
		for (i in _lastVisibles)
		{
			if (songTextArray[i] != null)
				songTextArray[i].visible = songTextArray[i].active = false;
		}
		_lastVisibles = [];

		// 计算当前可见文本范围（基于lerpSelected而不是curSelected，使过渡更平滑）
		var min:Int = Math.round(Math.max(0, Math.min(songs.length, lerpSelected - _drawDistance)));
		var max:Int = Math.round(Math.max(0, Math.min(songs.length, lerpSelected + _drawDistance)));

		// 只显示可见范围内的文本对象（分帧构建未就绪的条目先跳过）
		for (i in min...max)
		{
			var item:Alphabet = songTextArray[i];
			if (item == null)
				continue;
			item.visible = item.active = true;
			item.x = ((item.targetY - lerpSelected) * item.distancePerItem.x) + item.startPosition.x;
			item.y = ((item.targetY - lerpSelected) * 1.3 * item.distancePerItem.y) + item.startPosition.y;
			item.alpha = (i == curSelected) ? 1.0 : 0.6; // 设置选中项的透明度（选中不透明，未选中半透明）
			_lastVisibles.push(i);
		}

		// 小图标显示：独立于文本可视窗口，显示 curSelected 附近 ±ICON_RADIUS 的图标。
		// 位置用与文本相同的投影公式手动计算（不再依赖 sprTracker），
		// 这样即使文本行未渲染，附近小图标也能正确显示，避免“只有选中项才显示图标”的问题。
		hideLastIcons();
		var iconMin:Int = Math.round(Math.max(0, Math.min(songs.length, lerpSelected - ICON_RADIUS)));
		var iconMax:Int = Math.round(Math.max(0, Math.min(songs.length, lerpSelected + ICON_RADIUS)));
		for (i in iconMin...iconMax)
		{
			var songItem:Alphabet = songTextArray[i];
			if (songItem == null)
				continue; // 文本行尚未构建，图标位置依赖其尺寸，先跳过

			// 选中项若尚未预热，做一次同步创建（最多 1 次解码，保证焦点图标始终可见）
			if (iconArray[i] == null && i == curSelected && !iconLoadStatus[i])
			{
				var __savedDir:String = Mods.currentModDirectory; // 保存当前目录，避免全局目录被污染
				Mods.currentModDirectory = songs[i].folder;
				var selIcon:HealthIcon = null;
				try {
					selIcon = new HealthIcon(songs[i].songCharacter);
				} catch (e:Dynamic) {
					trace('Failed to create selected icon for ${songs[i].songName}: ' + e);
				}
				Mods.currentModDirectory = __savedDir; // 无论成败都恢复选中曲目的目录
				if (selIcon != null) {
					selIcon.sprTracker = null; // 位置在下方用投影公式手动设置
					iconArray[i] = selIcon;
					iconLoadStatus[i] = true;
					grpIcons.add(selIcon);
				}
			}

			var icon:HealthIcon = iconArray[i];
			if (icon == null)
				continue;

			// 与 HealthIcon.update 中跟随 sprTracker 的偏移一致：(sprTracker.x + width + 12, sprTracker.y - 30)
			var sx:Float = ((songItem.targetY - lerpSelected) * songItem.distancePerItem.x) + songItem.startPosition.x;
			var sy:Float = ((songItem.targetY - lerpSelected) * 1.3 * songItem.distancePerItem.y) + songItem.startPosition.y;
			icon.setPosition(sx + songItem.width + 12, sy - 30);
			icon.visible = icon.active = true;
			icon.alpha = (i == curSelected) ? 1.0 : 0.6; // 设置选中项的透明度
			_lastIconVisibles.push(i);
		}
	}

	// 隐藏上一帧显示过的小图标（含超出文本可视窗口的邻近图标）
	private function hideLastIcons():Void
	{
		for (i in _lastIconVisibles)
		{
			if (iconArray[i] != null)
				iconArray[i].visible = iconArray[i].active = false;
		}
		_lastIconVisibles = [];
	}

	/** 一次性把列表里所有小图标建好并常驻，与 PsychEngine 原版一致：
	 *  浏览/滚动过程不再有任何新建或解码，内存进入 Freeplay 时即一次性到顶、之后保持稳定。
	 *  分帧构建：curSelected ± ICON_RADIUS 的可见图标同步建好，其余在 update() 空闲帧按
	 *  ICON_BUILD_PER_FRAME 逐帧补建，避免进入时同步创建全部图标精灵导致卡顿。
	 */
	private function preloadAllIcons():Void
	{
		if (songs.length == 0 || iconArray == null)
			return;

		// 构建优先级：可见窗口（curSelected ± ICON_RADIUS）排最前（同步建），其余按序号空闲帧补建
		var center:Int = Math.round(Math.max(0, Math.min(songs.length - 1, curSelected)));
		_iconBuildPriority = [];
		function addPriority(i:Int):Void
		{
			if (i >= 0 && i < songs.length && _iconBuildPriority.indexOf(i) == -1)
				_iconBuildPriority.push(i);
		}
		for (offset in (-ICON_RADIUS)...(ICON_RADIUS + 1))
			addPriority(center + offset);
		for (i in 0...songs.length)
			addPriority(i);

		// 同步只建可见窗口内的 HealthIcon（±ICON_RADIUS = 17 个），其余由 update() 空闲帧逐帧补建。
		// 与 Alphabet 列表的 windowBudget 策略保持一致：在 create() 只做"必须立即可见"的内容，
		// 把剩余的 400+ HealthIcon 创建分摊到 20 帧（~333ms），避免一次性 ~900ms 同步阻塞。
		_iconBuildIndex = 0;
		var __visibleBudget:Int = Std.int(Math.min(ICON_RADIUS * 2 + 1, songs.length));
		buildIconsBatch(__visibleBudget);
	}

	/**
	 * 按预算批量创建图标精灵。与 buildListBatch 同理：同步调用用于补建可见窗口，
	 * 空闲帧调用用于逐帧补齐其余图标，把 PNG 解码/文件系统探测/精灵创建摊到多帧。
	 */
	private function buildIconsBatch(budget:Int):Void
	{
		if (_iconBuildIndex < 0 || _iconBuildPriority == null)
			return;

		var built:Int = 0;
		while (_iconBuildIndex < _iconBuildPriority.length && built < budget)
		{
			var i:Int = _iconBuildPriority[_iconBuildIndex++];
			if (i < 0 || i >= songs.length || iconLoadStatus[i])
				continue;

			// 标记已尝试（创建失败也标记，避免每帧重试）；updateVisibleItems 的选中项兜底
			// 依赖该标记，创建成功前若被选中会走其同步兜底逻辑。
			iconLoadStatus[i] = true;
			var __savedDir:String = Mods.currentModDirectory;
			Mods.currentModDirectory = songs[i].folder;
			var ic:HealthIcon = null;
			try {
				ic = new HealthIcon(songs[i].songCharacter);
			} catch (e:Dynamic) {
				trace('Failed to preload icon for ${songs[i].songName}: ' + e);
			}
			Mods.currentModDirectory = __savedDir;
			if (ic == null)
				continue;
			// 位置由 updateVisibleItems 用投影公式统一设置，不绑定 sprTracker
			ic.sprTracker = null;
			ic.visible = ic.active = false;
			iconArray[i] = ic;
			grpIcons.add(ic);
			built++;
		}

		if (_iconBuildIndex >= _iconBuildPriority.length)
		{
			_iconBuildIndex = -1;
			_iconBuildPriority = null;
		}
	}

	/**
	 * 空闲时预加载“选中项附近 ±ICON_RADIUS”的小图标：每帧最多创建 ICON_WARM_PER_FRAME 个，
	 * 把 PNG 解码/纹理上传开销摊到空闲帧，避免滚动过程中的间歇性卡顿。
	 * 跟随 curSelected 形成一个滑动预热窗口（而非一次性预热整张列表），
	 * 因此滚动或跳转后，新进入附近的图标会在后续帧被补建，始终及时显示。
	 */
	private function warmupIcons():Void
	{
		if (songs.length == 0 || iconArray == null || iconLoadStatus.length != songs.length)
			return;

		var warmedThisFrame:Int = 0;
		// 仅扫描 curSelected ± ICON_RADIUS 的滑动窗口，开销极小；
		// 已加载的会被跳过，未加载的按预算补建。
		for (step in 0...(ICON_RADIUS * 2 + 1))
		{
			var offset:Int = (step % 2 == 0) ? (step >> 1) : -((step + 1) >> 1);
			var i:Int = curSelected + offset;
			if (i < 0 || i >= songs.length)
				continue;

			if (!iconLoadStatus[i])
			{
				var __savedDir:String = Mods.currentModDirectory; // 保存当前目录，避免全局目录被污染
				Mods.currentModDirectory = songs[i].folder;
				var ic:HealthIcon = null;
				try {
					ic = new HealthIcon(songs[i].songCharacter);
				} catch (e:Dynamic) {
					trace('Failed to create icon for ${songs[i].songName}: ' + e);
				}
				Mods.currentModDirectory = __savedDir; // 无论成败都恢复选中曲目的目录
				if (ic == null) { // 创建失败，标记已尝试，避免每帧重试
					iconLoadStatus[i] = true;
					continue;
				}
				// 不绑定 sprTracker：位置由 updateVisibleItems 用投影公式统一设置，
				// 使图标能独立于文本可视窗口、在选中项附近 ±ICON_RADIUS 显示。
				ic.sprTracker = null;
				ic.visible = false;
				ic.active = false;
				iconArray[i] = ic;
				iconLoadStatus[i] = true;
				grpIcons.add(ic);
				warmedThisFrame++;
				if (warmedThisFrame >= ICON_WARM_PER_FRAME)
					return; // 本帧达到预算上限，余下留到后续空闲帧
			}
		}
	}

	/**
	 * 复用同一张底图仅做缩放来适配 BPM 文本尺寸，避免在 BPM 变化时反复
	 * 新建 BitmapData（FlxGraphic.fromRectangle）造成不定时 GC 尖刺。
	 */
	private function refreshBpmBackground():Void
	{
		bpmTextBG.setGraphicSize(Std.int(bpmText.width + 20), Std.int(bpmText.height + 10));
		bpmTextBG.updateHitbox();
		bpmTextBG.x = bpmText.x - 10;
		bpmTextBG.y = bpmText.y - 5;
	}

	/**
	 * 把评分百分比格式化为固定 2 位小数的字符串，避免每帧使用
	 * split('.') + while 循环拼接产生的临时字符串数组（GC 来源）。
	 *
	 * 输入兼容两种格式：
	 *   - 0~1   (ratingPercent 原生格式，如 0.955 = 95.5%)
	 *   - 0~100 (旧 saveScore 中 ratingPercent * 100 的格式)
	 * 自动检测：r > 1.0 视为 0~100，反之为 0~1。
	 */
	private function buildRatingString(r:Float):String
	{
		if (r > 1.0) r = r / 100;

		var v:Int = Std.int(Math.round(r * 10000));
		var dec:Int = v % 100;
		if (dec < 0) dec = -dec;
		var intPart:Int = Std.int(v / 100);
		return intPart + '.' + (dec < 10 ? '0' + dec : '' + dec);
	}

	private var lastSectionHit:Int = -1;

	override function stepHit():Void
	{
		super.stepHit();

		// 每section（章节）触发背景缩放动画（不再是每4步）
		if (lastSectionHit != curSection && player.playingMusic)
		{
			lastSectionHit = curSection;
			sectionHit();
		}
	}

	private var lastBeatHit:Int = -1;
	private var iconScaleLerp:Float = 0; // 图标缩放Lerp进度 (0-1)
	private var iconBeatElapsed:Float = 0; // 图标节拍动画已过去时间
	private var iconBeatDuration:Float = 0; // 图标节拍动画总时长

	override function beatHit():Void
	{
		// trace('beatHit called, curBeat: ' + curBeat + ', lastBeatHit: ' + lastBeatHit + ', playingMusic: ' + player.playingMusic);
		if (lastBeatHit >= curBeat || !player.playingMusic)
		{
			// trace('beatHit blocked: lastBeatHit >= curBeat = ' + (lastBeatHit >= curBeat) + ', !playingMusic = ' + (!player.playingMusic));
			return;
		}

		lastBeatHit = curBeat;

		// 选中图标立刻缩放到1.1，然后开始lerp回1
		if (iconArray != null && iconArray[curSelected] != null)
		{
			var icon:HealthIcon = iconArray[curSelected];
			icon.scale.set(1.1, 1.1);
			iconBeatElapsed = 0;
			iconBeatDuration = Conductor.crochet / 1000;
		}
	}

	override function sectionHit():Void
	{
		// 背景每section缩放一次（每section触发一次）
		// 不再调用super.sectionHit()，避免父类中的额外缩放
		// 只有当缩放接近完成时才重新触发，避免在lerp动画中重复设置
		if (bg != null && player.playingMusic && bg.scale.x <= 1.01)
		{
			bg.scale.set(1.05, 1.05);
			bgBeatElapsed = 0;
			bgBeatDuration = Conductor.crochet / 1000;
		}
	}

	private function buildChartInfo(songData:SwagSong):Void
	{
		if (songData == null)
			return;

		var songName:String = songData.song;
		var bpm:Float = songData.bpm;
		var speed:Float = songData.speed;
		var fmt:String = songData.format;
		var p1:String = songData.player1;
		var p2:String = songData.player2;
		var sections:Array<SwagSection> = songData.notes;
		var secCount:Int = (sections != null) ? sections.length : 0;

		var totalNotes:Int = 0;
		var totalEvents:Int = (songData.events != null) ? songData.events.length : 0;
		if (sections != null)
		{
			for (sec in sections)
			{
				if (sec.sectionNotes != null)
					totalNotes += sec.sectionNotes.length;
			}
		}

		var lastTime:Float = 0;
		if (sections != null && sections.length > 0)
		{
			var lastSec:SwagSection = sections[sections.length - 1];
			var secBeats:Float = 4;
			var lastBeats:Null<Float> = cast lastSec.sectionBeats;
			if (lastBeats != null && !Math.isNaN(lastBeats))
				secBeats = lastBeats;

			var baseTime:Float = 0;
			for (i in 0...sections.length - 1)
			{
				var sb:Float = 4;
				var rawBeats:Null<Float> = cast sections[i].sectionBeats;
				if (rawBeats != null && !Math.isNaN(rawBeats))
					sb = rawBeats;
				baseTime += (sb * 60000) / bpm;
			}
			lastTime = baseTime + (secBeats * 60000) / bpm;
			var lastNoteTime:Float = 0;
			if (lastSec.sectionNotes != null)
			{
				for (note in lastSec.sectionNotes)
				{
					var nt:Float = note[0];
					if (nt > lastNoteTime)
						lastNoteTime = nt;
				}
				if (lastNoteTime > 0)
					lastTime = lastNoteTime + (secBeats * 60000) / bpm;
			}
		}

		var durationStr:String = '';
		if (lastTime > 0)
		{
			var totalSec:Float = lastTime / 1000;
			var mins:Int = Std.int(totalSec / 60);
			var secs:Int = Std.int(totalSec % 60);
			var ms:Int = Std.int(lastTime % 1000);
			durationStr = '$mins:${StringTools.lpad(Std.string(secs), '0', 2)}.${StringTools.lpad(Std.string(ms), '0', 3)}';
		}
		else
		{
			durationStr = 'N/A';
		}

		var lines:Array<String> = [];
		lines.push('Song: $songName');
		lines.push('BPM: ${Math.round(bpm)}');
		lines.push('Speed: ${Std.string(speed)}x');
		lines.push('Format: $fmt');
		lines.push('Sections: $secCount');
		lines.push('Notes: $totalNotes');
		lines.push('Events: $totalEvents');
		lines.push('Duration: $durationStr');
		lines.push('Players: $p1 vs $p2');
		if (songData.stage != null && songData.stage.length > 0)
			lines.push('Stage: ${songData.stage}');
		if (songData.generatedBy != null && songData.generatedBy.length > 0)
			lines.push('By: ${songData.generatedBy}');

		chartInfoText.text = lines.join('\n');

		var textH:Float = chartInfoText.height;
		var newH:Float = Std.int(textH + 44);
		var infoPanelX:Float = FlxG.width - 280 - 12;
		var infoPanelY:Float = (FlxG.height - newH) / 2;

		chartInfoBG.setGraphicSize(280, newH);
		chartInfoBG.updateHitbox();
		chartInfoBG.x = infoPanelX;
		chartInfoBG.y = infoPanelY;
		chartInfoTitle.x = infoPanelX + 8;
		chartInfoTitle.y = infoPanelY + 6;
		chartInfoText.x = infoPanelX + 8;
		chartInfoText.y = infoPanelY + 28;

		_chartInfoBuilt = true;
	}

	override function destroy():Void
	{
		// 清理背景缩放状态
		bgScaleLerp = 0;
		bgBeatElapsed = 0;
		bgBeatDuration = 0;

		// 重置Freeplay播放标志
		isFreeplayPlayingMusic = false;
		lastWarmupSelected = -999;

		// 清理谱面缓存，释放内存
		_songDataCache.clear();
		_songPathCache.clear();
		_audioModCache.clear();
		_songCacheLRU = [];
		#if (sys && FEATURE_FILESYSTEM)
		// 停止后台预解析工作线程并清空队列，避免线程泄漏
		_prefetchWorkerRunning = false;
		_prefetchWorker = null;
		_prefetchQueueMutex.acquire();
		_prefetchQueue = new Array();
		_prefetchQueueMutex.release();
		_prefetchMutex.acquire();
		_prefetchDone.clear();
		_prefetchMutex.release();
		_prefetchBusy.clear();
		_prefetchFailed.clear();
		#end

		// 离开 Freeplay 时释放残余的试听音频缓存（防止之前未来得及释放的累积）
		clearPreviewSounds();

		// --- 资源彻底释放 ---
		// 1. 清除 'freeplay' tag 保护（HealthIcon 图标才能被 clearStoredMemory 回收）
		HealthIcon._excludeContext = null;
		Paths.clearExcludedByTag('freeplay');
		// 2. 再释放本状态不再需要的静态缓存（下次进 Freeplay 会重新构建）
		#if MODS_ALLOWED
		WeekData._invalidateReloadCache();
		#end
		Mods.invalidateDirectoriesCache(); // 顺带清 globalModsExistsCache + Paths._atlasCache
		// 3. 现在 clearStoredMemory / clearUnusedMemory 才能真正回收所有 freeplay 资源
		super.destroy();
		Paths.clearStoredMemory();
		Paths.clearUnusedMemory();

		FlxG.autoPause = ClientPrefs.data.autoPause;
		if (!FlxG.sound.music.playing && !stopMusicPlay)
			FlxG.sound.playMusic(Paths.menuMusicAudio());

		// 清理BPM提示
		bpmText = null;
		bpmTextBG = null;

		// 清理谱面信息面板
		chartInfoBG = null;
		chartInfoTitle = null;
		chartInfoText = null;
		_chartInfoBuilt = false;
		_chartInfoVisible = true;
	}
}
