package states;

import backend.WeekData;
import backend.Highscore;
import backend.Song;
import backend.SongMetadata;
import backend.FreeplayCategory;
import backend.Conductor;
import objects.HealthIcon;
import objects.MusicPlayer;
import options.GameplayChangersSubstate;
import substates.ResetScoreSubState;
import flixel.math.FlxMath;
import flixel.util.FlxColor;
import flixel.util.FlxDestroyUtil;
import flixel.tweens.FlxTween;
import flixel.input.gamepad.FlxGamepadInputID;
import openfl.utils.AssetType;
import openfl.utils.Assets;
import flash.media.Sound;
import haxe.Json;
import haxe.ui.Toolkit;
import haxe.ui.core.Screen;
import haxe.ui.components.Label;
import haxe.ui.components.TextField;
import haxe.ui.containers.HBox;
import haxe.ui.events.UIEvent;
import backend.ui.FreeplaySkewButton;
import backend.ui.PsychUIRadioGroup;
import backend.ui.PsychUIButton;
import backend.ui.FreeplayTabBar;
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
	// 上一次计算 prefetchKey 时的选中项/难度/列表版本：三者没变就不必每帧重新拼接字符串（减少 GC）
	private var _prefetchSel:Int = -9999;
	private var _prefetchDiff:Int = -9999;
	private var _prefetchVer:Int = -1;
	// 与 prefetchKey 对应的谱面名，避免每帧重新计算
	private var _prefetchPoop:String = null;
	private var _prefetchSongPath:String = null;
	// 列表内容版本号：筛选/切区重建列表时自增，用于让预解析缓存失效
	private var _listVersion:Int = 0;
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

		var cacheKey:String = prefetchKey;
		if (curSelected != _prefetchSel || curDifficulty != _prefetchDiff || _prefetchVer != _listVersion)
		{
			_prefetchSel = curSelected;
			_prefetchDiff = curDifficulty;
			_prefetchVer = _listVersion;

			var meta:SongMetadata = songs[curSelected];
			var songLowercase:String = Paths.formatToSongPath(meta.songName);
			var poop:String = Highscore.formatSong(songLowercase, curDifficulty);
			cacheKey = meta.folder + '_' + poop;

			_prefetchPoop = poop;
			_prefetchSongPath = songLowercase;
			prefetchKey = cacheKey;
			prefetchDelay = PREFETCH_DELAY;
			return;
		}

		if (cacheKey == null || prefetchDelay <= 0)
			return;

		prefetchDelay -= elapsed;
		if (prefetchDelay > 0)
			return;
		prefetchDelay = 0;

		if (_songDataCache.exists(cacheKey) || _prefetchBusy.exists(cacheKey) || _prefetchFailed.exists(cacheKey))
			return;

		// 路径解析必须留在主线程（依赖 Mods.currentModDirectory 等全局状态）。
		// getChartPath 内部已包含 Normal 难度（-normal / 忽略大小写 / 拼写错误）的兼容回退。
		var path:String = Song.getChartPath(_prefetchPoop, _prefetchSongPath);
		if (path == null || !FileSystem.exists(path))
			return; // 无文件（含打包进 assets 的谱面），跳过预取，走同步加载分支

		_prefetchBusy.set(cacheKey, true);
		_songPathCache.set(cacheKey, path);

		// 把任务投到队列，交给常驻工作线程处理（不在主线程新建线程）
		_prefetchQueueMutex.acquire();
		_prefetchQueue.push({key: cacheKey, path: path, poop: _prefetchPoop});
		_prefetchQueueMutex.release();
		startPrefetchWorker();
		#end
	}

	var songs:Array<SongMetadata> = [];
	var songsFull:Array<SongMetadata> = []; // 全部曲目（筛选前的完整列表）

	// ===== Freeplay 分区（按 JSON 配置把歌曲分到不同 Tab）=====
	private static final CATEGORY_ALL_ID:String = '__freeplay_all__';
	private static final CATEGORY_UNCAT_ID:String = '__freeplay_uncategorized__';
	private var categoryList:Array<FreeplayCategory> = []; // 与 categorySongs 一一对应，索引 0 恒为“全部”
	private var categorySongs:Array<Array<SongMetadata>> = [];
	private var curCategory:Int = 0;
	private var categoryPrefsDirty:Bool = false; // 分区变动后延迟到离开 Freeplay 时再写存档
	private var listFade:Float = 1; // 切区淡入（0→1），乘到列表与图标的透明度上

	// 顶部：第一行固定分区（全部/未分类）+ 曲目筛选框，第二行自定义分区；高分面板占右上角
	private static final TOP_BAR_X:Int = 12;
	/**
	 * 顶部整条 Tab 栏的纵向偏移。
	 * 移动端屏幕最上沿容易被状态栏/圆角/刘海占掉，手指在贴边位置也更容易点偏，
	 * 所以移动端把第一行（含搜索框、分区编辑按钮与高分面板）整体下移一点。
	 */
	#if mobile
	private static final TOP_BAR_OFFSET_Y:Int = 16;
	#else
	private static final TOP_BAR_OFFSET_Y:Int = 0;
	#end
	private static final TAB_ROW_Y:Int = 6 + TOP_BAR_OFFSET_Y;
	private static final TAB_ROW_H:Int = 34;
	private static final TOP_ROW_GAP:Int = 6;
	private static final CUSTOM_ROW_Y:Int = TAB_ROW_Y + TAB_ROW_H + TOP_ROW_GAP;
	private static final SEARCH_ROW_Y:Int = TAB_ROW_Y + 3; // 与第一行卡片垂直居中
	private static final SEARCH_BOX_H:Int = 28;
	/** 搜索框右侧的分区编辑按钮宽度（触屏没有 TAB 键时用） */
	private static final EDIT_BTN_W:Int = 96;
	private static final SEARCH_GAP:Int = 10;
	private static final PANEL_GAP:Int = 8;
	private static final TOP_FONT_SIZE:Int = 16; // 顶部 Tab 栏与搜索框字号
	private var fixedTabBar:FreeplayTabBar = null; // 第一行：全部 / 未分类
	private var customTabBar:FreeplayTabBar = null; // 第二行：自定义分区
	private var haxeSearchBox:HBox = null;
	private var haxeSearchField:TextField = null;
	private var categoryEditButton:FreeplaySkewButton = null; // 第一行末尾的分区编辑入口（触屏可用，斜切卡片样式）
	private var categoryEditor:FreeplayCategoryEditor = null; // 分区编辑器（非 null 表示正打开）
	private var _suppressSearchChange:Bool = false; // 重建顶栏时回填搜索文字，避免重复触发筛选
	private var topBarWidth:Float = 0; // 上次布局宽度，窗口尺寸变化后重新摆放
	private var highscoreLeft:Float = -1000; // 高分面板左边界，自定义分区行按它避让
	private var lastLayoutPanelLeft:Float = -1000;

	// 移动端 Tab 栏横向拖动由 FreeplayTabBar 内部实现

	var selector:FlxText;

	private static var curSelected:Int = 0;

	var lerpSelected:Float = 0;
	var curDifficulty:Int = -1;

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
	private var iconLoadStatus:Array<Bool> = []; // 记录每个图标是否已加载（创建失败也标记，避免每帧重试）
	// songTextArray[i] = songs[i] 的菜单条目：按需创建，未创建的为 null。
	// 进入 Freeplay 时不再一次性把整张列表（1000+ 首）建出来。
	private var songTextArray:Array<Alphabet> = [];
	// 单帧最多创建的文本行数：滚动/跳转时按需创建，把开销摊到多帧，避免整页跳转一次性卡顿
	private static inline var TEXT_CREATE_PER_FRAME:Int = 8;
	// 远距离回收：离选中项超过该行数的条目会被移除并置空，内存不随浏览时长/曲库规模增长
	private static inline var RECYCLE_DISTANCE:Int = 40;
	private static inline var RECYCLE_PER_FRAME:Int = 24;
	private var _recycleCursor:Int = 0;

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
	private var _replayIndexMod:String = null; // 上次建立索引所用的模组目录，相同则跳过重扫
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

		// 进入 Freeplay 时临时隐藏 FPS 计数器，避免其遮挡顶部 Tab 栏等 UI；
		// 用全局 forceHideFPS 开关（而不是直接改 fpsVar.visible），
		// 因为窗口缩放等操作会调用 updateFPSCounterVisibility 重新设置可见性。
		Main.forceHideFPS = true;
		Main.updateFPSCounterVisibility();

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

		// 先按 JSON 配置分组，再只构建当前分区（以及“全部”）的列表
		songs = songsFull;
		buildCategoryList();
		applySavedCategory();
		songs = categorySongs[curCategory];
		var __t4:Float = haxe.Timer.stamp();
		reloadSongList();
		var __t5:Float = haxe.Timer.stamp();
		trace('[FREEPLAY] reloadSongList: ' + Math.round((__t5 - __t4) * 1000) + 'ms');
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

		var leText:String = Language.getWithFallback("freeplay_tip",
			"Press {0} to listen to the Song / Press {1} to open the Gameplay Changers Menu / Press {2} to Reset your Score and Accuracy.",
			[space, control, reset]);
		bottomString = leText;
		var size:Int = 16;
		bottomText = new FlxText(bottomBG.x, bottomBG.y + 4, FlxG.width, leText, size);
		// 用按语言映射的像素字体，中文提示才不会显示成空白方块
		bottomText.setFormat(Paths.font(Language.get('uitab_font')), size, FlxColor.WHITE, CENTER);
		bottomText.scrollFactor.set();

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

		chartInfoTitle = new FlxText(infoPanelX + 8, infoPanelY + 6, infoPanelW - 16, Language.get('chartinfo_title'), 18);
		chartInfoTitle.setFormat(Paths.font(Language.get('uitab_font')), 18, FlxColor.YELLOW, LEFT);
		chartInfoTitle.visible = false;

		chartInfoText = new FlxText(infoPanelX + 8, infoPanelY + 28, infoPanelW - 16, '', 14);
		chartInfoText.setFormat(Paths.font(Language.get('uitab_font')), 14, FlxColor.WHITE, LEFT);
		chartInfoText.visible = false;

		add(chartInfoBG);
		add(chartInfoTitle);
		add(chartInfoText);

		// 顶部分区 Tab 栏 + 搜索框（两者都在这里创建）
		buildHaxeUITopBar();

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
	 * 不再一次性构建整张列表：只有滚动到可见范围的条目才会被创建（见 updateVisibleItems），
	 * 因此进入耗时与内存占用都不随曲库规模（1000+ 首）增长。
	 */
	private function reloadSongList():Void
	{
		grpSongs.clear();
		grpIcons.clear();
		iconArray = new Array<HealthIcon>();
		iconLoadStatus = new Array<Bool>();
		songTextArray = new Array<Alphabet>();
		_lastIconVisibles.resize(0); // 列表重建后清空图标可见缓存
		_lastVisibles.resize(0);
		_recycleCursor = 0;
		_listVersion++;

		// 只预填占位：真正的文本/图标在进入可见窗口时按需创建
		for (i in 0...songs.length)
		{
			songTextArray.push(null);
			iconArray.push(null);
			iconLoadStatus.push(false);
		}
	}

	/**
	 * 创建单条菜单文本（Alphabet）。已存在则直接返回。
	 * 创建失败（字体/图集异常）时返回 null，调用方跳过该行。
	 */
	private function ensureSongText(i:Int):Alphabet
	{
		if (i < 0 || i >= songs.length)
			return null;
		var item:Alphabet = songTextArray[i];
		if (item != null)
			return item;

		try
		{
			item = new Alphabet(90, 320, songs[i].songName, true);
		}
		catch (e:Dynamic)
		{
			trace('Failed to create song text for ${songs[i].songName}: ' + e);
			return null;
		}

		item.targetY = i;
		grpSongs.add(item);
		item.scaleX = Math.min(1, 980 / item.width);
		item.snapToPosition();

		// too laggy with a lot of songs, so i had to recode the logic for it
		item.visible = item.active = item.isMenuItem = false;
		songTextArray[i] = item;
		return item;
	}

	/**
	 * 创建单个小图标（HealthIcon）。已存在、或已尝试过（含失败）时返回 null。
	 * 位置由 updateVisibleItems 用投影公式统一设置。
	 */
	private function ensureIcon(i:Int):HealthIcon
	{
		if (i < 0 || i >= songs.length)
			return null;
		if (iconLoadStatus[i])
			return iconArray[i];

		// 先标记已尝试：创建失败也不重试，避免每帧反复探测文件系统
		iconLoadStatus[i] = true;
		var savedDir:String = Mods.currentModDirectory; // 保存当前目录，避免全局目录被污染
		Mods.currentModDirectory = songs[i].folder;
		var ic:HealthIcon = null;
		try
		{
			ic = new HealthIcon(songs[i].songCharacter);
		}
		catch (e:Dynamic)
		{
			trace('Failed to create icon for ${songs[i].songName}: ' + e);
		}
		Mods.currentModDirectory = savedDir; // 无论成败都恢复选中曲目的目录
		if (ic == null)
			return null;

		ic.sprTracker = null; // 位置在 updateVisibleItems 里用投影公式手动设置
		ic.visible = ic.active = false;
		iconArray[i] = ic;
		grpIcons.add(ic);
		return ic;
	}

	/**
	 * 远距离回收：把离选中项太远的条目从组里移除并置空，交给 GC 释放。
	 * 每帧只处理少量索引，完整扫描一圈的开销可以忽略；内存因此不随浏览时长增长。
	 */
	private function recycleDistantItems():Void
	{
		var n:Int = songs.length;
		if (n == 0)
			return;

		for (_ in 0...Std.int(Math.min(RECYCLE_PER_FRAME, n)))
		{
			if (_recycleCursor >= n)
				_recycleCursor = 0;
			var i:Int = _recycleCursor++;
			if (Math.abs(i - curSelected) <= RECYCLE_DISTANCE)
				continue;

			var item:Alphabet = songTextArray[i];
			if (item != null && !item.visible)
			{
				grpSongs.remove(item, true);
				songTextArray[i] = null;
			}

			var icon:HealthIcon = iconArray[i];
			if (icon != null && !icon.visible)
			{
				grpIcons.remove(icon, true);
				iconArray[i] = null;
				iconLoadStatus[i] = false; // 滚回来时允许重新创建
			}
		}
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

		// 始终在当前分区内筛选（"全部"分区对应的列表本身就是完整曲库），
		// 避免选中自定义分区后一输入关键字就变成跨分区（全部）的结果。
		var hasQuery:Bool = !(tokens.length == 1 && tokens[0].length == 0);
		var baseList:Array<SongMetadata> = (curCategory >= 0 && curCategory < categorySongs.length) ? categorySongs[curCategory] : songsFull;

		if (!hasQuery)
		{
			songs = baseList;
		}
		else
		{
			songs = baseList.filter(function(s:SongMetadata):Bool
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

	// ==================== 分区与 Tab 栏 ====================

	/**
	 * 读取 freeplay_categories.json（模组自带 + 全局），把歌曲分进各个分区。
	 * 顺序：索引 0 恒为“全部”，之后紧跟“未分类”（若有），
	 * 最后是 JSON 中定义的、且至少有一首歌的自定义分区。
	 * （固定分区放 UI 第一行，自定义分区放第二行）
	 * 同一首歌可以出现在多个分区（各分区列表独立去重）。
	 */
	private function buildCategoryList():Void
	{
		categoryList = [];
		categorySongs = [];

		var allCat:FreeplayCategory = new FreeplayCategory();
		allCat.id = CATEGORY_ALL_ID;
		allCat.name = OptionsLanguage.get('freeplay_category_all', 'ALL');
		categoryList.push(allCat);
		categorySongs.push(songsFull);

		// 每首歌的曲名路径 / 归一化文件夹 / 周目名只算一次：
		// 1000+ 首 × 多个分区时不再重复分配字符串，也不再对数组反复 indexOf（原来整体是 O(n²)）
		var n:Int = songsFull.length;
		var songPaths:Array<String> = [];
		var songFolders:Array<String> = [];
		var songWeekFiles:Array<String> = [];
		var songWeekNames:Array<String> = [];
		for (i in 0...n)
		{
			var meta:SongMetadata = songsFull[i];
			songPaths.push(Paths.formatToSongPath(meta.songName));
			songFolders.push(FreeplayCategory.normalizeFolderName(meta.folder));
			songWeekFiles.push(getWeekFileName(meta));
			songWeekNames.push(getWeekDisplayName(meta));
		}

		// 先解析自定义分区（不直接入列表，等“未分类”插队到前面后再合并）
		var customCats:Array<FreeplayCategory> = [];
		var customSongs:Array<Array<SongMetadata>> = [];
		var configured:Array<FreeplayCategory> = FreeplayCategory.loadAll();
		var anyMatched:Array<Bool> = [];
		for (i in 0...n)
			anyMatched.push(false);

		for (cat in configured)
		{
			var list:Array<SongMetadata> = [];
			var member:Array<Bool> = [];
			for (i in 0...n)
				member.push(false);

			// 先按 JSON 里 songs 的书写顺序放入：逐条按 [曲名, 文件夹] 精确匹配，
			// 这样分区内的曲目顺序与配置一致，而不是沿用全局列表顺序。
			// exclude 优先：被显式排除的曲目即便写在 songs 里也不放入（编辑器用它来移出规则命中的歌）。
			for (s in cat.songs)
			{
				var songPath:String = s[0];
				var folderFilter:String = (s[1] == null) ? '' : s[1];
				var folderNorm:String = (folderFilter.length == 0) ? '' : FreeplayCategory.normalizeFolderName(folderFilter);
				for (i in 0...n)
				{
					if (member[i])
						continue;
					if (songPaths[i] != songPath)
						continue;
					if (folderFilter.length > 0 && folderNorm != songFolders[i])
						continue;
					if (cat.isExcludedPrepared(songPath, songFolders[i]))
						continue;
					member[i] = true;
					anyMatched[i] = true;
					list.push(songsFull[i]);
					break; // 一条配置只取第一个匹配（同名曲目可能存在于多个模组）
				}
			}

			// 再按 folders / weeks 补齐 songs 里没写到的曲目（没有这些规则时不会有多余项）
			for (i in 0...n)
			{
				if (member[i])
					continue;
				if (cat.matchesRulesPrepared(songFolders[i], songWeekFiles[i], songWeekNames[i]))
				{
					member[i] = true;
					anyMatched[i] = true;
					list.push(songsFull[i]);
				}
			}

			if (list.length == 0)
				continue; // 空分区不显示，避免点了却看不到歌
			customCats.push(cat);
			customSongs.push(list);
		}

		// 未分类：没被任何自定义分区匹配到的歌（紧跟“全部”，固定在第一行）
		var uncategorized:Array<SongMetadata> = [];
		for (i in 0...n)
		{
			if (!anyMatched[i])
				uncategorized.push(songsFull[i]);
		}
		if (uncategorized.length > 0)
		{
			var unc:FreeplayCategory = new FreeplayCategory();
			unc.id = CATEGORY_UNCAT_ID;
			unc.name = OptionsLanguage.get('freeplay_category_uncategorized', '未分类');
			categoryList.push(unc);
			categorySongs.push(uncategorized);
		}

		for (i in 0...customCats.length)
		{
			categoryList.push(customCats[i]);
			categorySongs.push(customSongs[i]);
		}

		if (curCategory >= categoryList.length)
			curCategory = 0;
	}

	/** 曲目所属周目的文件名（WeekData.weeksList 里的值）。 */
	private function getWeekFileName(meta:SongMetadata):String
	{
		if (meta.week >= 0 && meta.week < WeekData.weeksList.length)
			return WeekData.weeksList[meta.week];
		return '';
	}

	/** 曲目所属周目的显示名（week JSON 的 weekName）。 */
	private function getWeekDisplayName(meta:SongMetadata):String
	{
		var key:String = getWeekFileName(meta);
		if (key.length == 0)
			return '';
		var week:WeekData = WeekData.weeksLoaded.get(key);
		return (week != null && week.weekName != null) ? week.weekName : '';
	}

	/** 恢复上次停留的分区（ClientPrefs.data.freeplayCategory）。 */
	private function applySavedCategory():Void
	{
		curCategory = 0;
		var saved:String = ClientPrefs.data.freeplayCategory;
		if (saved == null || saved.length == 0)
			return;
		for (i in 0...categoryList.length)
		{
			if (categoryList[i].id == saved)
			{
				curCategory = i;
				return;
			}
		}
	}

	/**
	 * 切换分区并重建列表。
	 * @param delta 相对位移（±1 用于 Q/E、肩键）
	 * @param index 直接指定分区索引（点击 Tab 时）
	 */
	private function switchCategory(delta:Int = 0, index:Int = -1, playSound:Bool = true):Void
	{
		if (categoryList.length <= 1 || songsFull.length == 0)
			return;
		if (player != null && player.playingMusic)
			return; // 试听中不切区，避免音频与列表状态不同步

		var target:Int = (index >= 0) ? index : FlxMath.wrap(curCategory + delta, 0, categoryList.length - 1);
		if (target < 0 || target >= categoryList.length || target == curCategory)
			return;

		curCategory = target;
		ClientPrefs.data.freeplayCategory = categoryList[curCategory].id;
		// 延迟写档：切区时只改内存，真正落盘放到离开 Freeplay 时，避免连续按 Q/E 反复写存档
		categoryPrefsDirty = true;

		curSelected = 0;
		lerpSelected = 0;
		lastLerpSelected = -9999;
		listFade = 0; // 列表淡入

		if (playSound)
			FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);

		applyFilter(getSearchText());
		syncTabSelection();
	}

	/** 固定分区数量：索引 0 恒为“全部”，若有“未分类”则再占一位。 */
	private function fixedTabCount():Int
	{
		return (categoryList.length >= 2 && categoryList[1].id == CATEGORY_UNCAT_ID) ? 2 : 1;
	}

	/** 把选中态同步到两行 Tab（两行互斥，当前分区不在某行时该行取消选中）。 */
	private function syncTabSelection():Void
	{
		var fixedCount:Int = fixedTabCount();
		if (fixedTabBar != null)
		{
			if (curCategory < fixedCount)
				fixedTabBar.setSelected(curCategory);
			else
				fixedTabBar.clearSelection();
		}
		if (customTabBar != null)
		{
			if (curCategory >= fixedCount)
				customTabBar.setSelected(curCategory - fixedCount);
			else
				customTabBar.clearSelection();
		}
	}

	// ==================== HaxeUI 焦点清理（防退出崩溃 / 防自动聚焦） ====================

	private static var _focusCleanupHooked:Bool = false;

	/** 在游戏启动时调用一次（必须早于 HaxeUI Toolkit 首次初始化注册，见 clearHaxeUIFocus）。 */
	public static function initHaxeUIFocusCleanup():Void
	{
		if (_focusCleanupHooked)
			return;
		_focusCleanupHooked = true;
		FlxG.signals.preStateSwitch.add(clearHaxeUIFocus);
	}

	/**
	 * 切换 state 前清空 HaxeUI 焦点记录：
	 * FocusManager.removeView 在移除根组件时会按 _lastFocuses 重新聚焦（可能聚焦搜索框），
	 * 触发 FlxInputText.startFocus → getScreenBounds 在 state 销毁阶段访问失效对象而崩溃。
	 * 这里抢在 HaxeUI ScreenImpl 的 preStateSwitch 监听之前失焦并清空记录，绕开该路径。
	 */
	private static function clearHaxeUIFocus():Void
	{
		if (!Toolkit.initialized)
			return;
		var fm:haxe.ui.focus.FocusManager = haxe.ui.focus.FocusManager.instance;
		@:privateAccess
		{
			// focus=false 会触发 FocusManager.set_focus（内部读写 _lastFocuses），
			// 先复制到数组再遍历，避免边遍历边修改 Map
			var items:Array<haxe.ui.focus.IFocusable> = [];
			for (item in fm._lastFocuses)
				items.push(item);
			for (item in items)
			{
				if (item != null)
					item.focus = false;
			}
			fm._lastFocuses.clear();
		}
	}

	/** 创建顶部分区 Tab 栏（Flixel 自绘）与搜索框（HaxeUI），只在进入 Freeplay 时调用一次。 */
	private function buildHaxeUITopBar():Void
	{
		// 首次使用时初始化 HaxeUI Toolkit（幂等）；禁用 DPI 自动缩放，保证坐标与 Flixel 屏幕坐标一致
		if (!Toolkit.initialized)
		{
			Toolkit.autoScale = false;
			Toolkit.init();
		}
		// FocusManager 默认会在组件加入屏幕时自动聚焦第一个可聚焦组件，
		// 导致进入 Freeplay 后搜索框意外持有焦点、方向键/滚轮被输入判定吞掉；全局关闭。
		haxe.ui.focus.FocusManager.instance.autoFocus = false;
		applyHaxeThemeOverrides();

		var font:String = Paths.font('unifont-18.0.01.otf');
		// 曲目数角标用 fusion-pixel 像素字体（uitab_font 按语言映射到 zh_hans / zh_hant / latin）
		var badgeFont:String = Paths.font(Language.get('uitab_font'));

		var fixedCount:Int = fixedTabCount();

		// ---- 第一行：固定分区（全部 / 未分类）----
		fixedTabBar = new FreeplayTabBar(font, badgeFont);
		fixedTabBar.rowY = TAB_ROW_Y;
		var fixedTitles:Array<String> = [];
		var fixedCounts:Array<Int> = [];
		var fixedColors:Array<Int> = [];
		for (i in 0...fixedCount)
		{
			fixedTitles.push(categoryList[i].getDisplayName());
			fixedCounts.push(categorySongs[i].length);
			fixedColors.push(categoryList[i].color);
		}
		fixedTabBar.build(fixedTitles, fixedCounts, curCategory, fixedColors);
		fixedTabBar.onSelect = function(idx:Int)
		{
			if (haxeSearchField != null)
				haxeSearchField.focus = false;
			switchCategory(0, idx);
		};
		fixedTabBar.addTo(this);
		fixedTabBar.setVisible(true);

		// ---- 第二行：自定义分区（索引从 fixedCount 开始）----
		customTabBar = new FreeplayTabBar(font, badgeFont);
		customTabBar.rowY = CUSTOM_ROW_Y;
		var customTitles:Array<String> = [];
		var customCounts:Array<Int> = [];
		var customColors:Array<Int> = [];
		for (i in fixedCount...categoryList.length)
		{
			customTitles.push(categoryList[i].getDisplayName());
			customCounts.push(categorySongs[i].length);
			customColors.push(categoryList[i].color);
		}
		customTabBar.build(customTitles, customCounts, curCategory - fixedCount, customColors);
		customTabBar.onSelect = function(idx:Int)
		{
			if (haxeSearchField != null)
				haxeSearchField.focus = false;
			switchCategory(0, fixedCount + idx);
		};
		customTabBar.addTo(this);
		customTabBar.setVisible(customTitles.length > 0);

		// ---- 曲目筛选框（第一行，紧跟未分类右侧；位置在 layoutTopBar 里算）----
		haxeSearchBox = new HBox();
		haxeSearchBox.height = SEARCH_BOX_H;
		haxeSearchBox.styleString = 'padding: 0; horizontal-spacing: 8px; vertical-align: center;';

		var searchLabel:Label = new Label();
		searchLabel.text = OptionsLanguage.get('freeplay_songfilter', 'SONGFILTER:');
		searchLabel.styleString = 'font-name: $font; font-size: ${TOP_FONT_SIZE}px; color: #FFFFFF;';
		haxeSearchBox.addComponent(searchLabel);

		haxeSearchField = new TextField();
		haxeSearchField.text = '';
		haxeSearchField.maxChars = 32;
		haxeSearchField.percentWidth = 100;
		haxeSearchField.height = 24;
		// 背景/边框由 applyHaxeThemeOverrides 的 .textfield 规则统一处理，这里只设字体与内边距
		haxeSearchField.styleString = 'font-name: $font; font-size: ${TOP_FONT_SIZE}px; padding: 3px 6px;';
		haxeSearchField.registerEvent(UIEvent.CHANGE, function(_) {
			if (_suppressSearchChange)
				return;
			var txt:String = getSearchText();
			// 去除可能由 TAB 误输入的制表符，避免筛选异常
			if (txt.indexOf('\t') >= 0)
			{
				haxeSearchField.text = txt.split('\t').join('');
				return;
			}
			applyFilter(txt);
		});
		// 回车提交后取消聚焦，避免继续拦截选歌/方向键
		haxeSearchField.registerEvent(UIEvent.SUBMIT, function(_) haxeSearchField.focus = false);
		haxeSearchBox.addComponent(haxeSearchField);

		// ---- 分区编辑入口（触屏没有 Tab 键，放一个按钮在第一行末尾）----
		// 用 Flixel 自绘的斜切卡片按钮：和分区 Tab 卡片同一套视觉，斜角方向相反，
		// 文字固定 #87CEEB。HaxeUI 的 Button 套不出这种卡片风格。
		// 不要放进 haxeSearchBox（TextField 用 percentWidth=100，会把它挤出可视区），
		// 直接挂到 state 上，位置由 layoutTopBar 计算。
		categoryEditButton = new FreeplaySkewButton(font, OptionsLanguage.get('freeplay_cat_editor_entry', 'EDIT'));
		categoryEditButton.onClick = function() {
			if (haxeSearchField != null)
				haxeSearchField.focus = false;
			openCategoryEditor();
		};
		categoryEditButton.addTo(this);

		Screen.instance.addComponent(haxeSearchBox);

		syncTabSelection();
		// 强制做一次布局（此时高分文本还没生成，先按满宽摆放，changeDiff 后会被精确重排）
		layoutTopBar();
	}

	/**
	 * 顶部三块的摆放：第一行固定分区 + 曲目筛选框，第二行自定义分区。
	 * 两行都避让右上角的高分面板，第二行的宽度完全跟着面板左边界走。
	 */
	private function layoutTopBar():Void
	{
		if (fixedTabBar == null || haxeSearchBox == null)
			return;

		var panelLeft:Float = (highscoreLeft > 0) ? highscoreLeft : FlxG.width;
		if (topBarWidth == FlxG.width && Math.abs(panelLeft - lastLayoutPanelLeft) < 1)
			return;
		topBarWidth = FlxG.width;
		lastLayoutPanelLeft = panelLeft;

		// 第一行固定分区按内容自然宽度摆放，筛选框紧接其右侧
		var fixedW:Float = Math.min(fixedTabBar.getContentWidth(), Math.max(180, FlxG.width * 0.45));
		fixedTabBar.layout(TOP_BAR_X, fixedW);

		// 分区编辑按钮占最右侧（宽度按文字长度算，与卡片同高），筛选框宽度要把它扣掉，避免被挤出面板
		var editW:Float = (categoryEditButton != null) ? categoryEditButton.width : EDIT_BTN_W;
		var searchX:Float = TOP_BAR_X + fixedW + SEARCH_GAP;
		var searchW:Float = panelLeft - PANEL_GAP - searchX - editW - SEARCH_GAP;
		if (searchW < 100)
			searchW = 100;
		haxeSearchBox.x = searchX;
		haxeSearchBox.y = SEARCH_ROW_Y;
		haxeSearchBox.width = searchW;
		haxeSearchBox.height = SEARCH_BOX_H;

		if (categoryEditButton != null)
			// 与第一行分区卡片同高同基线，斜角方向相反
			categoryEditButton.layout(searchX + searchW + SEARCH_GAP, TAB_ROW_Y);

		// 第二行：显示范围跟着高分面板的长度收缩
		customTabBar.layout(TOP_BAR_X, Math.max(160, panelLeft - PANEL_GAP - TOP_BAR_X));
	}

	/**
	 * 覆盖 HaxeUI 默认主题里 TextField 的浅色网页风样式
	 * （圆角、渐变、hover 变浅、按下内阴影、底部边框线）。
	 * 通过 Toolkit.styleSheet 注入全局规则：主题规则先加载，注入规则后 merge，同选择器属性覆盖生效。
	 * parse 内部按内容 hash 去重，多次进入 Freeplay 不会重复注入。
	 * 字体不走这里：带空格/反斜杠的字体路径在 CSS 值解析里有风险，改由组件 styleString 单独设置。
	 */
	private function applyHaxeThemeOverrides():Void
	{
		Toolkit.styleSheet.parse('
			.textfield {
				border-radius: 0px;
				filter: none;
				background-color: #000000;
				background-color-end: #000000;
				background-opacity: 0.5;
				border-size: 1px;
				border-color: #666666;
				color: #FFFFFF;
			}
			.textfield:active {
				border-size: 1px;
				border-color: #FFD800;
				filter: none;
			}
		');
	}

	/** 搜索框当前内容。 */
	private function getSearchText():String
	{
		if (haxeSearchField == null)
			return '';
		var txt:String = haxeSearchField.text;
		return (txt == null) ? '' : txt;
	}

	/** 是否正在搜索框内输入（避免空格/方向键等被 freeplay 逻辑拦截）。 */
	private function isTypingSearch():Bool
	{
		return haxeSearchField != null && haxeSearchField.focus;
	}

	/** 显示/隐藏顶部两行 Tab 栏与筛选框（试听预览时整条隐藏）。 */
	private function setHaxeTopBarVisible(visible:Bool):Void
	{
		if (haxeSearchBox != null)
			haxeSearchBox.hidden = !visible;
		if (fixedTabBar != null)
			fixedTabBar.setVisible(visible);
		if (customTabBar != null)
			customTabBar.setVisible(visible && categoryList.length > fixedTabCount());
		if (!visible && haxeSearchField != null)
			haxeSearchField.focus = false;
		if (categoryEditButton != null)
			categoryEditButton.setVisible(visible);
	}

	// ==================== 分区编辑器 ====================

	/** 打开分区编辑器（非试听播放时）。 */
	private function openCategoryEditor():Void
	{
		if (categoryEditor != null || player == null || player.playingMusic)
			return;
		if (Controls.instance.isInSubstate)
			return;

		if (haxeSearchField != null)
			haxeSearchField.focus = false;
		setHaxeTopBarVisible(false);
		// 编辑器是整屏覆盖层：先隐藏虚拟按键，避免底部触控按钮盖住列表抢走触摸。
		// 这里只隐藏不销毁——openCategoryEditor 可能在 update() 中途被 TAB 键触发，
		// 销毁会让同一帧后续代码访问 touchPad 时崩溃（Null Object Reference）。
		if (touchPad != null)
		{
			touchPad.visible = false;
			touchPad.active = false;
		}

		#if desktop
		FlxG.mouse.visible = true;
		#end

		// 新建的分区 id 依赖 songsFull 里的曲目信息，编辑器内部自行读取并保存
		categoryEditor = new FreeplayCategoryEditor(songsFull);
		categoryEditor.onClose = closeCategoryEditor;
		categoryEditor.onSaved = onCategoryEditorSaved;
		categoryEditor.build();
		FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);
	}

	/** 关闭编辑器（不写盘），并恢复顶部 Tab 栏。 */
	private function closeCategoryEditor():Void
	{
		if (categoryEditor == null)
			return;
		categoryEditor.destroy();
		categoryEditor = null;
		// 恢复被隐藏的虚拟按键
		if (touchPad != null)
		{
			touchPad.visible = true;
			touchPad.active = true;
		}
		if (!player.playingMusic)
			setHaxeTopBarVisible(true);
	}

	/** 编辑器保存成功：先关掉界面，再按新配置重建分区与 Tab 栏。 */
	private function onCategoryEditorSaved():Void
	{
		closeCategoryEditor();
		rebuildAfterCategoryEdit();
		FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);
	}

	/**
	 * 分区配置变更后重建：分区列表、顶部两行 Tab、搜索框与左侧曲目列表。
	 * 尽量保持当前停留的分区（按 id 找回，找不到则回到“全部”）。
	 */
	private function rebuildAfterCategoryEdit():Void
	{
		var searchText:String = getSearchText();
		var curId:String = (curCategory >= 0 && curCategory < categoryList.length) ? categoryList[curCategory].id : '';

		buildCategoryList();
		curCategory = 0;
		for (i in 0...categoryList.length)
		{
			if (categoryList[i].id == curId)
			{
				curCategory = i;
				break;
			}
		}

		destroyHaxeUITopBar();
		buildHaxeUITopBar();

		if (haxeSearchField != null)
		{
			_suppressSearchChange = true;
			haxeSearchField.text = searchText;
			_suppressSearchChange = false;
		}
		applyFilter(searchText);
	}

	/** 释放顶部两行 Tab 栏与搜索框（重建前调用；HaxeUI 组件需要显式移除）。 */
	private function destroyHaxeUITopBar():Void
	{
		if (fixedTabBar != null)
		{
			fixedTabBar.destroy();
			fixedTabBar = null;
		}
		if (customTabBar != null)
		{
			customTabBar.destroy();
			customTabBar = null;
		}
		if (haxeSearchBox != null)
		{
			if (haxeSearchField != null)
				haxeSearchField.focus = false;
			Screen.instance.removeComponent(haxeSearchBox);
			haxeSearchBox = null;
			haxeSearchField = null;
		}
		if (categoryEditButton != null)
		{
			categoryEditButton.destroy();
			categoryEditButton = null;
		}
		// 强制下次 layoutTopBar 重新摆放
		topBarWidth = 0;
		lastLayoutPanelLeft = -1000;
	}

	/** 每帧维护：窗口尺寸变化后重新摆放（高分面板宽度变化由 positionHighscore 触发）。 */
	private function updateHaxeTopBar():Void
	{
		if (haxeSearchBox == null)
			return;
		if (topBarWidth == FlxG.width)
			return;
		layoutTopBar();
	}

	/** 鼠标是否悬停在任意一行 Tab 栏上（用于屏蔽歌曲列表的滚轮）。 */
	private function isMouseOverTabBar():Bool
	{
		return (fixedTabBar != null && fixedTabBar.isOverBar()) || (customTabBar != null && customTabBar.isOverBar());
	}

	/** 鼠标/触摸点是否落在顶部区域（搜索框或 Tab 栏）。 */
	private function isMouseOverTopBar():Bool
	{
		if (haxeSearchBox != null && !haxeSearchBox.hidden)
		{
			var mx:Float = FlxG.mouse.x;
			var my:Float = FlxG.mouse.y;
			if (mx >= haxeSearchBox.x && mx <= haxeSearchBox.x + haxeSearchBox.width && my >= haxeSearchBox.y
				&& my <= haxeSearchBox.y + haxeSearchBox.height)
				return true;
		}
		return isMouseOverTabBar();
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

		// 分区编辑器打开时接管全部输入：只处理退出键，其余交给 HaxeUI 组件
		if (categoryEditor != null)
		{
			if (controls.BACK)
			{
				// 保存目标弹窗 / 系统软键盘展开时，BACK 只关最上层，不关整个编辑器
				if (categoryEditor.cancelTargetPicker() || categoryEditor.cancelSoftKeyboard())
				{
					FlxG.sound.play(Paths.sound('cancelMenu'));
					super.update(elapsed);
					return;
				}
				closeCategoryEditor();
				FlxG.sound.play(Paths.sound('cancelMenu'));
				super.update(elapsed);
				return;
			}
			// 每帧驱动虚拟列表：同步勾选状态 + 按滚动位置重绑可见行
			categoryEditor.update();
			super.update(elapsed);
			return;
		}

		// 是否正在搜索框中输入（避免空格/方向键等被 freeplay 逻辑拦截）
		var typingSearch:Bool = isTypingSearch();
		if (typingSearch)
		{
			lastTypingTick = FlxG.game.ticks;
			// 点击/触摸顶栏以外的区域立刻取消搜索框焦点，避免焦点被困住、只能靠 ESC 脱身
			if (FlxG.mouse.justPressed && !isMouseOverTopBar())
			{
				haxeSearchField.focus = false;
				typingSearch = false;
			}
		}

		// 窗口尺寸变化后重新摆放搜索框与 Tab 栏
		updateHaxeTopBar();
		// 分区 Tab：悬停/点击/横向拖动/滚轮全部由 FreeplayTabBar 内部处理（两行各自独立）
		if (!Controls.instance.isInSubstate)
		{
			if (fixedTabBar != null)
				fixedTabBar.update(elapsed);
			if (customTabBar != null)
				customTabBar.update(elapsed);
			if (categoryEditButton != null)
				categoryEditButton.update(elapsed);
		}
		if (listFade < 1)
			listFade = Math.min(1, listFade + elapsed * 5);

		// 键盘 Q/E 与手柄肩键切分区（左右方向键仍保留给选歌）
		if (!typingSearch && !player.playingMusic && !Controls.instance.isInSubstate && songsFull.length > 0 && categoryList.length > 1)
		{
			if (FlxG.keys.justPressed.Q)
				switchCategory(-1);
			else if (FlxG.keys.justPressed.E)
				switchCategory(1);

			if (FlxG.gamepads.anyJustPressed(FlxGamepadInputID.LEFT_SHOULDER))
				switchCategory(-1);
			else if (FlxG.gamepads.anyJustPressed(FlxGamepadInputID.RIGHT_SHOULDER))
				switchCategory(1);
		}

		// 桌面端：非手柄模式时保持鼠标可见（含试听播放期间，播放器有可点击按钮）
		#if desktop
		if (!controls.controllerMode && !FlxG.mouse.visible)
			FlxG.mouse.visible = true;
		#end

		// 未在播放预览时恢复搜索框与模组名文本显示（播放预览时由 SPACE 分支隐藏）
		if (!player.playingMusic && haxeSearchBox != null && haxeSearchBox.hidden)
			setHaxeTopBarVisible(true);
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

		// TAB：试听播放时切换谱面信息面板，非播放时打开分区编辑器
		if (FlxG.keys.justPressed.TAB && !typingSearch && !Controls.instance.isInSubstate)
		{
			if (player.playingMusic)
				_chartInfoVisible = !_chartInfoVisible;
			else
				openCategoryEditor();
		}

		// 后台预解析当前选中曲目的谱面，让按下确认键时直接命中缓存
		updateChartPrefetch(elapsed);

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

		if (!player.playingMusic && !typingSearch && songs.length > 0 && !Controls.instance.isInSubstate)
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

				if (FlxG.mouse.wheel != 0 && !isMouseOverTabBar())
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

		// 搜索框聚焦时按确认键：仅取消焦点（本次按键不参与选歌，避免误触），恢复列表操作
		if (typingSearch && controls.ACCEPT && haxeSearchField != null)
			haxeSearchField.focus = false;

		if (controls.BACK && !Controls.instance.isInSubstate)
		{
			var wasTyping:Bool = typingSearch || (FlxG.game.ticks - lastTypingTick) < 250;
			if (wasTyping)
			{
				// 搜索框聚焦时：仅 ESC 取消焦点；BACKSPACE 交给输入框删除字符，二者均不返回主菜单
				if (FlxG.keys.justPressed.ESCAPE && haxeSearchField != null && haxeSearchField.focus)
					haxeSearchField.focus = false;
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

			// 播放预览时不隐藏鼠标：播放器里有可点击的按钮，桌面端需要能看到光标
			// 播放预览时一并隐藏顶部 Tab 栏 / 搜索框与模组名文本
			setHaxeTopBarVisible(false);
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
		else if (controls.ACCEPT && !player.playingMusic && !typingSearch && songs.length > 0 && !Controls.instance.isInSubstate)
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
		else if ((controls.RESET || touchPad.buttonY.justPressed) && !player.playingMusic && !typingSearch && songs.length > 0 && !Controls.instance.isInSubstate)
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
									matchedList.push({path: p, mtime: m, name: f, meta: meta,
										replayVersion: (obj != null && Reflect.hasField(obj, 'replayVersion')) ? Reflect.field(obj, 'replayVersion') : null,
										kathyVersion: (obj != null && Reflect.hasField(obj, 'kathyVersion')) ? Reflect.field(obj, 'kathyVersion') : null});
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
	 * 当一首曲目存在多个回放时，弹出选择框让玩家挑选要播放的回放。
	 * 实际 UI 在 substates/ReplayPickerSubState.hx。
	 */
	private function openReplayPicker(matchedList:Array<Dynamic>):Void
	{
		if (matchedList == null || matchedList.length == 0)
			return;
		openSubState(new substates.ReplayPickerSubState(matchedList, function(path:String) {
			playReplay(path);
		}));
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
		var moddirCheck:String = (Mods.currentModDirectory != null && Mods.currentModDirectory.length > 0) ? Mods.currentModDirectory : 'global';
		// 同一模组目录下的回放列表不会变化：滚动选歌时直接复用已有索引，
		// 避免每换一首歌就重新 readDirectory + 解析全部回放 JSON（大量临时字符串 → GC 抖动）。
		if (_replayIndexMod == moddirCheck)
			return;
		_replayIndexMod = moddirCheck;

		// 清空之前的缓存
		cachedReplayIndex = new Map();

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
				cachedReplayText = bottomString + '\n' + Language.get('freeplay_replay_hint_mobile', [Std.string(songReplayCount)]);
				#else
				cachedReplayText = bottomString + '\n' + Language.get('freeplay_replay_hint_desktop', [Std.string(songReplayCount)]);
				#end
			}
			else
			{
				// Song has replays but current difficulty doesn't
				cachedReplayText = bottomString + '\n'
					+ Language.get('freeplay_replay_hint_nodiff', [Std.string(songReplayCount), currentDifficultyName]);
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
		// 高分面板固定在右上角，与第一行 Tab 顶部对齐
		var topY:Float = TAB_ROW_Y;
		scoreText.y = topY;
		modText.y = scoreText.y + scoreText.height + 2;
		diffText.y = modText.y + modText.height + 2;

		scoreText.x = FlxG.width - scoreText.width - 6;
		// 面板左边界即背景底色左边缘，Tab 行按它避让
		highscoreLeft = scoreText.x - 6;

		// 背景按三行文本的实际尺寸重新缩放；updateHitbox 后 x/y 即左上角，直接对齐面板左边界
		var bgTop:Float = scoreText.y - 6;
		var bgH:Float = diffText.y + diffText.height + 4 - bgTop;
		scoreBG.scale.set((FlxG.width - highscoreLeft) / scoreBG.frameWidth, bgH / scoreBG.frameHeight);
		scoreBG.updateHitbox();
		scoreBG.x = highscoreLeft;
		scoreBG.y = bgTop;
		diffText.x = Std.int(scoreBG.x + (scoreBG.width / 2));
		diffText.x -= diffText.width / 2;
		modText.x = Std.int(scoreBG.x + (scoreBG.width / 2));
		modText.x -= modText.width / 2;

		layoutTopBar();
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
		_lastVisibles.resize(0);

		// 计算当前可见文本范围（基于lerpSelected而不是curSelected，使过渡更平滑）
		var min:Int = Math.round(Math.max(0, Math.min(songs.length, lerpSelected - _drawDistance)));
		var max:Int = Math.round(Math.max(0, Math.min(songs.length, lerpSelected + _drawDistance)));

		// 选中行优先按需创建：整页跳转时保证焦点那一行一定是完整的
		var created:Int = 0;
		if (curSelected >= min && curSelected < max && songTextArray[curSelected] == null && ensureSongText(curSelected) != null)
			created++;

		// 只显示可见范围内的文本对象；未创建的按需创建（每帧有上限，避免整页跳转时一次性建太多行卡顿）
		for (i in min...max)
		{
			var item:Alphabet = songTextArray[i];
			if (item == null)
			{
				if (created >= TEXT_CREATE_PER_FRAME)
					continue;
				item = ensureSongText(i);
				created++;
				if (item == null)
					continue;
			}
			item.visible = item.active = true;
			item.x = ((item.targetY - lerpSelected) * item.distancePerItem.x) + item.startPosition.x;
			item.y = ((item.targetY - lerpSelected) * 1.3 * item.distancePerItem.y) + item.startPosition.y;
			item.alpha = ((i == curSelected) ? 1.0 : 0.6) * listFade; // 选中项不透明，未选中半透明；listFade 处理切区淡入
			_lastVisibles.push(i);
		}

		// 小图标显示：独立于文本可视窗口，显示 curSelected 附近 ±ICON_RADIUS 的图标。
		// 位置用与文本相同的投影公式手动计算（不再依赖 sprTracker），
		// 这样即使文本行未渲染，附近小图标也能正确显示，避免“只有选中项才显示图标”的问题。
		hideLastIcons();
		var iconMin:Int = Math.round(Math.max(0, Math.min(songs.length, lerpSelected - ICON_RADIUS)));
		var iconMax:Int = Math.round(Math.max(0, Math.min(songs.length, lerpSelected + ICON_RADIUS)));
		var iconCreated:Int = 0;
		for (i in iconMin...iconMax)
		{
			var songItem:Alphabet = songTextArray[i];
			if (songItem == null)
				continue; // 文本行尚未创建，图标位置依赖其尺寸，下一帧会随文本补建

			var icon:HealthIcon = iconArray[i];
			if (icon == null)
			{
				// 按需创建（每帧有上限，把 PNG 解码/文件系统探测摊到多帧）
				if (iconLoadStatus[i] || iconCreated >= ICON_WARM_PER_FRAME)
					continue;
				icon = ensureIcon(i);
				iconCreated++;
				if (icon == null)
					continue;
			}

			// 与 HealthIcon.update 中跟随 sprTracker 的偏移一致：(sprTracker.x + width + 12, sprTracker.y - 30)
			var sx:Float = ((songItem.targetY - lerpSelected) * songItem.distancePerItem.x) + songItem.startPosition.x;
			var sy:Float = ((songItem.targetY - lerpSelected) * 1.3 * songItem.distancePerItem.y) + songItem.startPosition.y;
			icon.setPosition(sx + songItem.width + 12, sy - 30);
			icon.visible = icon.active = true;
			icon.alpha = ((i == curSelected) ? 1.0 : 0.6) * listFade; // 设置选中项的透明度；listFade 处理切区淡入
			_lastIconVisibles.push(i);
		}

		// 远距离回收，让内存不随浏览时长/曲库规模无限增长
		recycleDistantItems();
	}

	// 隐藏上一帧显示过的小图标（含超出文本可视窗口的邻近图标）
	private function hideLastIcons():Void
	{
		for (i in _lastIconVisibles)
		{
			if (iconArray[i] != null)
				iconArray[i].visible = iconArray[i].active = false;
		}
		_lastIconVisibles.resize(0);
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
		lines.push(Language.get('chartinfo_song', [songName]));
		lines.push(Language.get('chartinfo_bpm', [Std.string(Math.round(bpm))]));
		lines.push(Language.get('chartinfo_speed', [Std.string(speed)]));
		lines.push(Language.get('chartinfo_format', [fmt]));
		lines.push(Language.get('chartinfo_sections', [Std.string(secCount)]));
		lines.push(Language.get('chartinfo_notes', [Std.string(totalNotes)]));
		lines.push(Language.get('chartinfo_events', [Std.string(totalEvents)]));
		lines.push(Language.get('chartinfo_duration', [durationStr]));
		lines.push(Language.get('chartinfo_players', [p1, p2]));
		if (songData.stage != null && songData.stage.length > 0)
			lines.push(Language.get('chartinfo_stage', [songData.stage]));
		if (songData.generatedBy != null && songData.generatedBy.length > 0)
			lines.push(Language.get('chartinfo_by', [songData.generatedBy]));

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

		// 分区变动落盘（切区时只改了内存）
		if (categoryPrefsDirty)
		{
			categoryPrefsDirty = false;
			ClientPrefs.saveSettings();
		}

		// 离开 Freeplay 时恢复 FPS 计数器（是否显示仍由 showFPS 设置决定）
		Main.forceHideFPS = false;
		Main.updateFPSCounterVisibility();

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

		// 释放两行分区 Tab 栏的卡片精灵
		if (categoryEditor != null)
		{
			categoryEditor.destroy();
			categoryEditor = null;
		}
		if (fixedTabBar != null)
		{
			fixedTabBar.destroy();
			fixedTabBar = null;
		}
		if (customTabBar != null)
		{
			customTabBar.destroy();
			customTabBar = null;
		}
		if (categoryEditButton != null)
		{
			categoryEditButton.destroy();
			categoryEditButton = null;
		}

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
