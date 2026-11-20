package states;

import lime.app.Future;
import sys.thread.FixedThreadPool;
import haxe.Json;
import lime.utils.Assets;
import openfl.display.BitmapData;
import openfl.utils.AssetType;
import openfl.utils.Assets as OpenFlAssets;
import flixel.graphics.FlxGraphic;
import flixel.system.FlxAssets;
import flixel.FlxState;
import flash.media.Sound;
import backend.Song;
import backend.StageData;
import objects.Character;
import sys.thread.Thread;
import sys.thread.Mutex;
import objects.Note;
import objects.NoteSplash;
import objects.NoteHoldCover;
import substates.PauseSubState;
#if HSCRIPT_ALLOWED
import psychlua.HScript;
import crowplexus.iris.Iris;
import crowplexus.hscript.Expr.Error as IrisError;
import crowplexus.hscript.Printer;
#end

class LoadingState extends MusicBeatState
{
	public static var loaded:Int = 0;
	public static var loadMax:Int = 0;

	static var originalBitmapKeys:Map<String, String> = [];
	static var requestedBitmaps:Map<String, BitmapData> = [];
	static var mutex:Mutex;
	static var threadPool:FixedThreadPool = null;

	function new(target:FlxState, stopMusic:Bool)
	{
		this.target = target;
		this.stopMusic = stopMusic;

		super();
	}

	inline static public function loadAndSwitchState(target:FlxState, stopMusic = false, intrusive:Bool = true)
		MusicBeatState.switchState(getNextState(target, stopMusic, intrusive));

	var target:FlxState = null;
	var stopMusic:Bool = false;
	var dontUpdate:Bool = false;

	var barGroup:FlxSpriteGroup;
	var bar:FlxSprite;
	var barWidth:Int = 0;
	var intendedPercent:Float = 0;
	var curPercent:Float = 0;
	var stateChangeDelay:Float = 0;

	#if PSYCH_WATERMARKS
	var logo:FlxSprite;
	var pessy:FlxSprite;
	var loadingText:FlxText;

	var timePassed:Float;
	var shakeFl:Float;
	var shakeMult:Float = 0;

	var isSpinning:Bool = false;
	var spawnedPessy:Bool = false;
	var pressedTimes:Int = 0;
	#else
	var funkay:FlxSprite;
	#end

	#if HSCRIPT_ALLOWED
	var hscript:HScript;
	#end

	override function create()
	{
		persistentUpdate = true;
		barGroup = new FlxSpriteGroup();
		add(barGroup);

		var barBack:FlxSprite = new FlxSprite(0, 660).makeGraphic(1, 1, FlxColor.BLACK);
		barBack.scale.set(FlxG.width - 300, 25);
		barBack.updateHitbox();
		barBack.screenCenter(X);
		barGroup.add(barBack);

		bar = new FlxSprite(barBack.x + 5, barBack.y + 5).makeGraphic(1, 1, FlxColor.WHITE);
		bar.scale.set(0, 15);
		bar.updateHitbox();
		barGroup.add(bar);
		barWidth = Std.int(barBack.width - 10);

		#if HSCRIPT_ALLOWED
		if (Mods.currentModDirectory != null && Mods.currentModDirectory.trim().length > 0)
		{
			var scriptPath:String = 'mods/${Mods.currentModDirectory}/data/LoadingScreen.hx'; // mods/My-Mod/data/LoadingScreen.hx
			if (FileSystem.exists(scriptPath))
			{
				try
				{
					hscript = new HScript(null, scriptPath);
					hscript.set('getLoaded', function() return loaded);
					hscript.set('getLoadMax', function() return loadMax);
					hscript.set('barBack', barBack);
					hscript.set('bar', bar);

					if (hscript.exists('onCreate'))
					{
						hscript.call('onCreate');
						trace('initialized hscript interp successfully: $scriptPath');
						return super.create();
					}
					else
					{
						trace('"$scriptPath" contains no \"onCreate" function, stopping script.');
					}
				}
				catch (e:IrisError)
				{
					var pos:HScriptInfos = cast {fileName: scriptPath, showLine: false};
					Iris.error(Printer.errorToString(e, false), pos);
					var hscript:HScript = cast(Iris.instances.get(scriptPath), HScript);
				}
				if (hscript != null)
					hscript.destroy();
				hscript = null;
			}
		}
		#end

		#if PSYCH_WATERMARKS // PSYCH LOADING SCREEN
		var bg = new FlxSprite().loadGraphic(Paths.image('menuDesat'));
		bg.antialiasing = ClientPrefs.data.antialiasing;
		bg.setGraphicSize(Std.int(FlxG.width));
		bg.color = 0xFFD16FFF;
		bg.updateHitbox();
		addBehindBar(bg);

		loadingText = new FlxText(520, 600, 400, LanguageBasic.getPhrase('now_loading', 'Now Loading', ['...']), 32);
		loadingText.setFormat(Paths.font("vcr.ttf"), 32, FlxColor.WHITE, LEFT, OUTLINE_FAST, FlxColor.BLACK);
		loadingText.borderSize = 2;
		addBehindBar(loadingText);

		logo = new FlxSprite(0, 0).loadGraphic(Paths.image('loading_screen/icon'));
		logo.antialiasing = ClientPrefs.data.antialiasing;
		logo.scale.set(0.75, 0.75);
		logo.updateHitbox();
		logo.screenCenter();
		logo.x -= 50;
		logo.y -= 40;
		addBehindBar(logo);
		#else // BASE GAME LOADING SCREEN
		var bg = new FlxSprite().makeGraphic(1, 1, 0xFFCAFF4D);
		bg.scale.set(FlxG.width, FlxG.height);
		bg.updateHitbox();
		bg.screenCenter();
		addBehindBar(bg);

		funkay = new FlxSprite(0, 0).loadGraphic(Paths.image('funkay'));
		funkay.antialiasing = ClientPrefs.data.antialiasing;
		funkay.setGraphicSize(0, FlxG.height);
		funkay.updateHitbox();
		addBehindBar(funkay);
		#end
		super.create();

		if (stateChangeDelay <= 0 && checkLoaded())
		{
			dontUpdate = true;
			onLoad();
		}
	}

	function addBehindBar(obj:flixel.FlxBasic)
	{
		insert(members.indexOf(barGroup), obj);
	}

	var transitioning:Bool = false;

	override function update(elapsed:Float)
	{
		super.update(elapsed);
		if (dontUpdate)
			return;

		if (!transitioning)
		{
			if (!finishedLoading && checkLoaded())
			{
				if (stateChangeDelay <= 0)
				{
					transitioning = true;
					onLoad();
					return;
				}
				else
					stateChangeDelay = Math.max(0, stateChangeDelay - elapsed);
			}
			intendedPercent = loaded / loadMax;
		}

		if (curPercent != intendedPercent)
		{
			if (Math.abs(curPercent - intendedPercent) < 0.001)
				curPercent = intendedPercent;
			else
				curPercent = FlxMath.lerp(intendedPercent, curPercent, Math.exp(-elapsed * 15));

			bar.scale.x = barWidth * curPercent;
			bar.updateHitbox();
		}

		#if HSCRIPT_ALLOWED
		if (hscript != null)
		{
			if (hscript.exists('onUpdate'))
				hscript.call('onUpdate', [elapsed]);
			return;
		}
		#end

		#if PSYCH_WATERMARKS // PSYCH LOADING SCREEN
		timePassed += elapsed;
		shakeFl += elapsed * 3000;
		var dots:String = '';
		switch (Math.floor(timePassed % 1 * 3))
		{
			case 0:
				dots = '.';
			case 1:
				dots = '..';
			case 2:
				dots = '...';
		}
		loadingText.text = LanguageBasic.getPhrase('now_loading', 'Now Loading{1}', [dots]);

		if (!spawnedPessy)
		{
			if (!transitioning && (controls.ACCEPT || FlxG.touches.getFirst() != null && FlxG.touches.getFirst().justPressed))
			{
				shakeMult = 1;
				FlxG.sound.play(Paths.sound('cancelMenu'));
				pressedTimes++;
			}
			shakeMult = Math.max(0, shakeMult - elapsed * 5);
			logo.offset.x = Math.sin(shakeFl * Math.PI / 180) * shakeMult * 100;

			if (pressedTimes >= 5)
			{
				FlxG.camera.fade(0xAAFFFFFF, 0.5, true);
				logo.visible = false;
				spawnedPessy = true;
				stateChangeDelay = 5;
				FlxG.sound.play(Paths.sound('secret'));

				pessy = new FlxSprite(700, 140);
				pessy.frames = Paths.getSparrowAtlas('loading_screen/pessy');
				pessy.animation.addByPrefix('run', 'run', 24, true);
				pessy.animation.addByPrefix('spin', 'spin', 24, true);
				pessy.antialiasing = ClientPrefs.data.antialiasing;
				pessy.flipX = (logo.offset.x > 0);
				pessy.visible = false;

				new FlxTimer().start(0.01, function(tmr:FlxTimer)
				{
					pessy.x = FlxG.width + 200;
					pessy.velocity.x = -1100;
					if (pessy.flipX)
					{
						pessy.x = -pessy.width - 200;
						pessy.velocity.x *= -1;
					}

					pessy.visible = true;
					pessy.animation.play('run', true);
					#if ACHIEVEMENTS_ALLOWED Achievements.unlock('pessy_easter_egg'); #end

					insert(members.indexOf(loadingText), pessy);
				});
			}
		}
		else if (!isSpinning && (pessy.flipX && pessy.x > FlxG.width) || (!pessy.flipX && pessy.x < -pessy.width))
		{
			isSpinning = true;
			pessy.animation.play('spin', true);
			pessy.flipX = false;
			pessy.x = 500;
			pessy.y = FlxG.height + 500;
			pessy.velocity.x = 0;
			FlxTween.tween(pessy, {y: 10}, 0.65, {ease: FlxEase.quadOut});
		}
		#end
	}

	#if HSCRIPT_ALLOWED
	override function destroy()
	{
		if (hscript != null)
		{
			if (hscript.exists('onDestroy'))
				hscript.call('onDestroy');
			hscript.destroy();
		}
		hscript = null;
		super.destroy();
	}
	#end

	var finishedLoading:Bool = false;

	function onLoad()
	{
		_loaded();

		if (stopMusic && FlxG.sound.music != null)
			FlxG.sound.music.stop();

		FlxG.camera.visible = false;
		MusicBeatState.switchState(target);
		transitioning = true;
		finishedLoading = true;
	}

	static function _loaded()
	{
		loaded = 0;
		loadMax = 0;
		initialThreadCompleted = true;
		isIntrusive = false;

		FlxTransitionableState.skipNextTransIn = true;
		if (threadPool != null)
			threadPool.shutdown(); // kill all workers safely
		threadPool = null;
		mutex = null;
	}

	public static function checkLoaded():Bool
	{
		// 分帧缓存后台预解码的 Bitmap（每帧至多 4 张），避免最后一条线程完成时大量 bitmap 同帧 cacheBitmap 造成进度条卡住
		var drained:Map<String, BitmapData> = requestedBitmaps;
		requestedBitmaps = [];
		var origDrained:Map<String, String> = originalBitmapKeys;
		originalBitmapKeys = [];
		if (drained != null)
		{
			var drainBudget:Int = 4;
			for (key => bitmap in drained)
			{
				if (drainBudget <= 0)
				{
					// 未处理完的还回去，留给下一帧
					if (bitmap != null) requestedBitmaps.set(key, bitmap);
					originalBitmapKeys.set(key, origDrained.get(key));
					break;
				}
				if (bitmap != null && Paths.cacheBitmap(origDrained.get(key), bitmap) != null)
				{
					// trace('finished preloading image $key');
				}
				else
					trace('failed to cache image $key');
				drainBudget--;
			}
		}
		// 未排完的 requestedBitmaps 留到下一帧继续

		// 预加载线程全部完成后（此时 FlxGraphic 都已注册），从预加载列表中筛出 sparrow 图集
		if (!_atlasQueueBuilt && loaded >= loadMax && initialThreadCompleted && !requestedBitmaps.keys().hasNext())
		{
			_atlasQueueBuilt = true;
			for (img in imagesToPrepare)
				if (img != null && img.length > 0 && Paths.sparrowXmlExists(img))
					atlasQueue.push(img);
		}

		// 每帧至多构建一个 FlxAtlasFrames（XML 解析 + 帧切分），分摊到加载条期间，避免 create() 首帧卡顿
		if (atlasQueueIdx < atlasQueue.length)
		{
			var key:String = atlasQueue[atlasQueueIdx++];
			try
			{
				// FlxGraphic 已由上方 cacheBitmap 注册，image() 命中缓存，不会重复解码
				Paths.getSparrowAtlas(key);
			}
			catch (e:Dynamic) {}
		}

		// trace('we checked if loaded');
		return (loaded >= loadMax && initialThreadCompleted && atlasQueueIdx >= atlasQueue.length && !requestedBitmaps.keys().hasNext());
	}

	public static function loadNextDirectory()
	{
		var directory:String = 'shared';
		var weekDir:String = StageData.forceNextDirectory;
		StageData.forceNextDirectory = null;

		if (weekDir != null && weekDir.length > 0 && weekDir != '')
			directory = weekDir;

		Paths.setCurrentLevel(directory);
		trace('Setting asset folder to ' + directory);
	}

	static var isIntrusive:Bool = false;

	static function getNextState(target:FlxState, stopMusic = false, intrusive:Bool = true):FlxState
	{
		if (!ClientPrefs.data.loadingScreen)
			intrusive = false;

		LoadingState.isIntrusive = intrusive;
		_startPool();
		loadNextDirectory();

		if (intrusive)
			return new LoadingState(target, stopMusic);

		if (stopMusic && FlxG.sound.music != null)
			FlxG.sound.music.stop();

		while (true)
		{
			if (checkLoaded())
			{
				_loaded();
				break;
			}
			else
				Sys.sleep(0.001);
		}
		return target;
	}

	static var imagesToPrepare:Array<String> = [];
	static var soundsToPrepare:Array<String> = [];
	static var musicToPrepare:Array<String> = [];
	static var songsToPrepare:Array<String> = [];

	// 待预构建的 sparrow 图集队列：把 FlxAtlasFrames 构建（XML 解析 + 帧切分）
	// 从 PlayState.create() 前移到 LoadingState 主线程分帧完成，首次进歌也能命中 _atlasCache。
	static var atlasQueue:Array<String> = [];
	static var atlasQueueIdx:Int = 0;
	static var _atlasQueueBuilt:Bool = false;

	public static function prepare(images:Array<String> = null, sounds:Array<String> = null, music:Array<String> = null)
	{
		if (images != null)
			imagesToPrepare = imagesToPrepare.concat(images);
		if (sounds != null)
			soundsToPrepare = soundsToPrepare.concat(sounds);
		if (music != null)
			musicToPrepare = musicToPrepare.concat(music);
	}

	static var initialThreadCompleted:Bool = true;
	static var dontPreloadDefaultVoices:Bool = false;

	// Haxe 标准库没有 Sys.cpuCount()，这里按平台探测逻辑核心数：
	// Windows 读 NUMBER_OF_PROCESSORS 环境变量；Linux/Android 数 /proc/cpuinfo 的 processor 行；其他保守返回 1。
	static function _getCpuCount():Int
	{
		var count:Int = 1;
		#if windows
		var env:String = Sys.getEnv('NUMBER_OF_PROCESSORS');
		if (env != null)
		{
			var c:Int = Std.parseInt(env);
			if (c > 0) count = c;
		}
		#elseif (linux || android)
		try
		{
			var cpuinfo:String = sys.io.File.getContent('/proc/cpuinfo');
			count = 0;
			for (line in cpuinfo.split('\n'))
				if (StringTools.startsWith(line, 'processor')) count++;
			if (count < 1) count = 1;
		}
		catch (e:Dynamic) {}
		#end
		return count;
	}

	static function _startPool()
	{
		// _startPool() 会被 prepareToSong() / getNextState() / _threadFunc() 各调用一次，
		// 以前每次都 new 一个新池并丢掉旧引用（旧池的线程永远不会被 shutdown），
		// 导致每进一次歌就泄漏两个线程池，玩得越久卡顿越明显。
		// 这里改成复用：池只在 _loaded() 里被 shutdown 并置 null。
		if (threadPool != null)
			return;

		// 使用「Loading Threads」设置（默认 2），限制在 [1, 16] 之间。
		// 老设备/低核 CPU：线程数超过物理核心数反而会饿死主线程（渲染/进度条），
		// 且并行解码会推高内存峰值。这里封顶到 CPU 核数，至少 1 个线程。
		var pref:Int = ClientPrefs.data.loadingThreadCount;
		var threadCount:Int = Std.int(Math.max(1, Math.min(pref < 1 ? 1 : pref, 16)));
		#if sys
		var cpuCount:Int = _getCpuCount();
		if (threadCount > cpuCount)
			threadCount = cpuCount;
		#end
		threadPool = new FixedThreadPool(threadCount);
	}

	public static function prepareToSong()
	{
		if (PlayState.SONG == null)
		{
			imagesToPrepare = [];
			soundsToPrepare = [];
			musicToPrepare = [];
			songsToPrepare = [];
			loaded = 0;
			loadMax = 0;
			initialThreadCompleted = true;
			isIntrusive = false;
			return;
		}

		_startPool();
		imagesToPrepare = [];
		soundsToPrepare = [];
		musicToPrepare = [];
		songsToPrepare = [];
		atlasQueue = [];
		atlasQueueIdx = 0;
		_atlasQueueBuilt = false;

		// 清空上一次遗留的角色 JSON 缓存，避免新谱面用了旧角色数据
		Character.clearPreloadedJsonCache();

		initialThreadCompleted = false;
		var threadsCompleted:Int = 0;
		var threadsMax:Int = 0;
		function completedThread()
		{
			threadsCompleted++;
			if (threadsCompleted == threadsMax)
			{
				clearInvalids();
				startThreads();
				initialThreadCompleted = true;
			}
		}

		var song:SwagSong = PlayState.SONG;
		var folder:String = Paths.formatToSongPath(Song.loadedSongName);

		// 并行化：note skin + note splash + preload.json（任务1）
		threadsMax++;
		threadPool.run(() ->
		{
			try
			{
				// LOAD NOTE IMAGE
				var noteSkin:String = Note.defaultNoteSkin;
				if (PlayState.SONG.arrowSkin != null && PlayState.SONG.arrowSkin.length > 1)
					noteSkin = PlayState.SONG.arrowSkin;

				var customSkin:String = noteSkin + Note.getNoteSkinPostfix();
				if (Paths.fileExists('images/$customSkin.png', IMAGE))
					noteSkin = customSkin;
				imagesToPrepare.push(noteSkin);
				//

				// LOAD NOTE SPLASH IMAGE
				var noteSplash:String = NoteSplash.defaultNoteSplash;
				if (PlayState.SONG.splashSkin != null && PlayState.SONG.splashSkin.length > 0)
					noteSplash = PlayState.SONG.splashSkin;
				else
					noteSplash += NoteSplash.getSplashSkinPostfix();
				imagesToPrepare.push(noteSplash);

				// 加载preload.json
				var preloadPath:String = Paths.json('$folder/preload');
				var json:Dynamic = null;

				#if MODS_ALLOWED
				var moddyFile:String = Paths.modsJson('$folder/preload');
				if (FileSystem.exists(moddyFile))
					json = Json.parse(File.getContent(moddyFile));
				else
					json = Json.parse(File.getContent(preloadPath));
				#else
				json = Json.parse(Assets.getText(preloadPath));
				#end

				if (json != null)
				{
					var imgs:Array<String> = [];
					var snds:Array<String> = [];
					var mscs:Array<String> = [];
					for (asset in Reflect.fields(json))
					{
						var filters:Int = Reflect.field(json, asset);
						var asset:String = asset.trim();

						if (filters < 0 || StageData.validateVisibility(filters))
						{
							if (asset.startsWith('images/'))
								imgs.push(asset.substr('images/'.length));
							else if (asset.startsWith('sounds/'))
								snds.push(asset.substr('sounds/'.length));
							else if (asset.startsWith('music/'))
								mscs.push(asset.substr('music/'.length));
						}
					}
					prepare(imgs, snds, mscs);
				}
			}
			catch (e:Dynamic)
			{
			}
			completedThread();
		});

		// 并行化：stage数据（任务2）
		threadsMax++;
		threadPool.run(() ->
		{
			try
			{
				var stageName:String = song.stage;
				if (stageName == null || stageName.length < 1)
					stageName = StageData.vanillaSongStage(folder);

				var stageData:StageFile = StageData.getStageFile(stageName);
				if (stageData != null)
				{
					var imgs:Array<String> = [];
					var snds:Array<String> = [];
					var mscs:Array<String> = [];
					if (stageData.preload != null)
					{
						for (asset in Reflect.fields(stageData.preload))
						{
							var filters:Int = Reflect.field(stageData.preload, asset);
							var asset:String = asset.trim();

							if (filters < 0 || StageData.validateVisibility(filters))
							{
								if (asset.startsWith('images/'))
									imgs.push(asset.substr('images/'.length));
								else if (asset.startsWith('sounds/'))
									snds.push(asset.substr('sounds/'.length));
								else if (asset.startsWith('music/'))
									mscs.push(asset.substr('music/'.length));
							}
						}
					}

					if (stageData.objects != null)
					{
						for (sprite in stageData.objects)
						{
							if (sprite.type == 'sprite' || sprite.type == 'animatedSprite')
								if ((sprite.filters < 0 || StageData.validateVisibility(sprite.filters)) && !imgs.contains(sprite.image))
									imgs.push(sprite.image);
						}
					}
					prepare(imgs, snds, mscs);
				}
			}
			catch (e:Dynamic)
			{
			}
			completedThread();
		});

		// 并行化：player1 + vocals（任务3）
		threadsMax++;
		threadPool.run(() ->
		{
			try
			{
				var player1:String = song.player1;
				var player2:String = song.player2;
				var gfVersion:String = song.gfVersion;
				var prefixVocals:String = song.needsVoices ? '$folder/Voices' : null;
				if (gfVersion == null)
					gfVersion = 'gf';

				preloadCharacter(player1, prefixVocals);

				dontPreloadDefaultVoices = false;
				if (!dontPreloadDefaultVoices && prefixVocals != null)
				{
					if (Paths.fileExists('$prefixVocals-Player.${Paths.SOUND_EXT}', SOUND, false, 'songs')
						&& Paths.fileExists('$prefixVocals-Opponent.${Paths.SOUND_EXT}', SOUND, false, 'songs'))
					{
						songsToPrepare.push('$prefixVocals-Player');
						songsToPrepare.push('$prefixVocals-Opponent');
					}
					else if (Paths.fileExists('$prefixVocals.${Paths.SOUND_EXT}', SOUND, false, 'songs'))
						songsToPrepare.push(prefixVocals);
				}

				songsToPrepare.push('$folder/Inst');

				// 并行化：player2（任务4）
				if (player2 != player1)
				{
					threadsMax++;
					threadPool.run(() ->
					{
						try
						{
							preloadCharacter(player2, prefixVocals);
						}
						catch (e:Dynamic)
						{
						}
						completedThread();
					});
				}

				// 并行化：gf（任务5）
				if (gfVersion != player2 && gfVersion != player1)
				{
					var stageData:StageFile = StageData.getStageFile(song.stage == null || song.stage.length < 1 ? StageData.vanillaSongStage(folder) : song.stage);
					if (stageData == null || !stageData.hide_girlfriend)
					{
						threadsMax++;
						threadPool.run(() ->
						{
							try
							{
								preloadCharacter(gfVersion);
							}
							catch (e:Dynamic)
							{
							}
							completedThread();
						});
					}
				}
			}
			catch (e:Dynamic)
			{
			}
			completedThread();
		});

		// 并行化：歌曲音频所在模组探测。
		// 首次进歌 generateSong 会对全部模组逐次 exists 探测音频（冷缓存下可达数秒），
		// 前移到后台线程并写入 PlayState._songAudioModCache，create() 直接命中。
		threadsMax++;
		threadPool.run(() ->
		{
			try
			{
				var song:SwagSong = PlayState.SONG;
				if (PlayState._songAudioModCache == null) PlayState._songAudioModCache = new Map();
				if (!PlayState._songAudioModCache.exists(song.song))
				{
					var si:String = (song.specialInst != null && song.specialInst.length > 0) ? song.specialInst : null;
					var sv:String = (song.specialVocal != null && song.specialVocal.length > 0) ? song.specialVocal : null;
					// 只判文件存在性，不触发 Sound 缓存，后台线程安全（与 PlayState.modHasSong 判定一致）
					function modHasAudio(mod:String, fileBase:String):Bool
						return FileSystem.exists(Paths.getSongAudioPath(song.song, fileBase, mod));
					function modHasSong(mod:String):Bool
					{
						if (modHasAudio(mod, 'Inst') || modHasAudio(mod, 'Voices')) return true;
						if (si != null && modHasAudio(mod, 'Inst-$si')) return true;
						if (sv != null && modHasAudio(mod, 'Voices-$sv')) return true;
						return false;
					}
					var found:String = '';
					for (mod in Mods.getModDirectories())
						if (modHasSong(mod)) { found = mod; break; }
					PlayState._songAudioModCache.set(song.song, found);
				}
			}
			catch (e:Dynamic) {}
			completedThread();
		});

		// 并行化：预读 PlayState.create() 用到的 Lua/HScript 脚本文件内容（纯 I/O 预读，后台线程安全）。
		// create() 的「HUD+脚本」段会在主线程对每个脚本 new FunkinLua / initHScript 同步读盘 + 编译执行。
		// 后台把文件内容读进 ScriptPreload 缓存后，create() 命中缓存跳过同步读盘（低端机冷 I/O 是大头）。
		threadsMax++;
		threadPool.run(() ->
		{
			try
			{
				var songName:String = song.song;
				// 预读 scripts/ 全局目录（create() 早期会遍历）
				#if MODS_ALLOWED
				for (luaFolder in Mods.directoriesWithFile(Paths.getSharedPath(), 'scripts/'))
				{
					for (file in Paths.readDirectory(luaFolder))
					{
						var f:String = luaFolder + file;
						#if LUA_ALLOWED
						if (file.toLowerCase().endsWith('.lua')) backend.ScriptPreload.preloadLua(f);
						#end
						#if HSCRIPT_ALLOWED
						if (file.toLowerCase().endsWith('.hx')) backend.ScriptPreload.preloadHScript(f);
						#end
					}
				}
				#end

			// 预读 data/$songName/ 下的 per-song 脚本（custom_events + custom_notetypes + 根目录脚本）
				#if MODS_ALLOWED
				for (dataFolder in Mods.directoriesWithFile(Paths.getSharedPath(), 'data/$songName/'))
				{
					// custom_events 子目录
					var eventsFolder:String = dataFolder + 'custom_events/';
					if (FileSystem.exists(eventsFolder))
						for (file in Paths.readDirectory(eventsFolder))
						{
							var f:String = eventsFolder + file;
							#if LUA_ALLOWED
							if (file.toLowerCase().endsWith('.lua')) backend.ScriptPreload.preloadLua(f);
							#end
							#if HSCRIPT_ALLOWED
							if (file.toLowerCase().endsWith('.hx')) backend.ScriptPreload.preloadHScript(f);
							#end
						}
					// custom_notetypes 子目录
					var typesFolder:String = dataFolder + 'custom_notetypes/';
					if (FileSystem.exists(typesFolder))
						for (file in Paths.readDirectory(typesFolder))
						{
							var f:String = typesFolder + file;
							#if LUA_ALLOWED
							if (file.toLowerCase().endsWith('.lua')) backend.ScriptPreload.preloadLua(f);
							#end
							#if HSCRIPT_ALLOWED
							if (file.toLowerCase().endsWith('.hx')) backend.ScriptPreload.preloadHScript(f);
							#end
						}
					// data/$songName/ 根目录脚本
					for (file in Paths.readDirectory(dataFolder))
					{
						var f:String = dataFolder + file;
						#if LUA_ALLOWED
						if (file.toLowerCase().endsWith('.lua')) backend.ScriptPreload.preloadLua(f);
						#end
						#if HSCRIPT_ALLOWED
						if (file.toLowerCase().endsWith('.hx')) backend.ScriptPreload.preloadHScript(f);
						#end
					}
				}
				#end

				// 预读 stage 脚本（stages/$stage.lua / .hx），解析方式与 startLuasNamed/startHScriptsNamed 一致
				var stageName:String = song.stage;
				if (stageName == null || stageName.length < 1)
					stageName = StageData.vanillaSongStage(folder);
				#if MODS_ALLOWED
				var stageLua:String = Paths.modFolders('stages/$stageName.lua');
				if (!FileSystem.exists(stageLua)) stageLua = Paths.getSharedPath('stages/$stageName.lua');
				if (FileSystem.exists(stageLua)) backend.ScriptPreload.preloadLua(stageLua);
				var stageHx:String = Paths.modFolders('stages/$stageName.hx');
				if (!FileSystem.exists(stageHx)) stageHx = Paths.getSharedPath('stages/$stageName.hx');
				if (FileSystem.exists(stageHx)) backend.ScriptPreload.preloadHScript(stageHx);
				#end
			}
			catch (e:Dynamic) {}
			completedThread();
		});

		// 额外任务：预加载 PlayState.create() 中常用的游戏资源（避免主线程同步阻塞）
		threadsMax++;
		threadPool.run(() ->
		{
			try
			{
				// 游戏音效（原在 PlayState.create() 中同步加载）
				soundsToPrepare.push('hitsound');
				if (ClientPrefs.data.hitsound != 'none' && ClientPrefs.data.hitsound != null && ClientPrefs.data.hitsound.length > 0)
					soundsToPrepare.push('hitsounds/' + ClientPrefs.data.hitsound);
				if (ClientPrefs.data.ghostTappingMode != 'always')
				{
					soundsToPrepare.push('missnote1');
					soundsToPrepare.push('missnote2');
					soundsToPrepare.push('missnote3');
				}

				// 常用图片
				imagesToPrepare.push('alphabet');

				// 倒计时图片（根据 stageUI 选择正确的变体，stage 数据此时已加载完毕）
				var stageData:StageFile = null;
				try { stageData = StageData.getStageFile(song.stage); } catch(_) {}
				var isPixel:Bool = stageData != null && stageData.isPixelStage == true;
				// 与 PlayState.cacheCountdown 保持一致：stageUI 存在时用自定义变体（uiPrefix/uiPostfix）
				var psStageUI:String = "normal";
				if (stageData != null && stageData.stageUI != null && stageData.stageUI.trim().length > 0)
					psStageUI = stageData.stageUI;
				else if (isPixel)
					psStageUI = "pixel";
				var psUiPrefix:String = "";
				var psUiPostfix:String = "";
				if (psStageUI != "normal")
				{
					psUiPrefix = psStageUI.split("-pixel")[0].trim();
					if (psStageUI == "pixel" || psStageUI.endsWith("-pixel")) psUiPostfix = "-pixel";
				}
				var introImagesArray:Array<String> = switch(psStageUI) {
					case "pixel": ['pixelUI/ready-pixel', 'pixelUI/set-pixel', 'pixelUI/date-pixel'];
					case "normal": ["ready", "set", "go"];
					default: ['${psUiPrefix}UI/ready${psUiPostfix}', '${psUiPrefix}UI/set${psUiPostfix}', '${psUiPrefix}UI/go${psUiPostfix}'];
				}
				var introSoundsSuffix:String = isPixel ? '-pixel' : '';
				for (introImg in introImagesArray)
					imagesToPrepare.push(introImg);
				soundsToPrepare.push('intro3' + introSoundsSuffix);
				soundsToPrepare.push('intro2' + introSoundsSuffix);
				soundsToPrepare.push('intro1' + introSoundsSuffix);
				soundsToPrepare.push('introGo' + introSoundsSuffix);

				// Hold Cover 贴图（原在 PlayState.create() 中同步加载，长条首次命中时会卡一下）
				if (ClientPrefs.data.holdCovers)
				{
					if (NoteHoldCover.isRGBSkin())
						imagesToPrepare.push(NoteHoldCover.getRGBAtlasPath());
					else
						for (c in NoteHoldCover.COVER_COLORS)
							imagesToPrepare.push(NoteHoldCover.getColorAtlasPath(c));
				}

				// Pause 音乐（原在 PlayState.create() 中同步加载，暂停首次打开时会卡）
				var pauseMusicName:String = null;
				if (PauseSubState.songName != null && PauseSubState.songName.length > 0)
					pauseMusicName = PauseSubState.songName;
				else
				{
					var fmt:String = Paths.formatToSongPath(ClientPrefs.data.pauseMusic);
					if (fmt != 'none') pauseMusicName = fmt;
				}
				if (pauseMusicName != null)
					musicToPrepare.push(pauseMusicName);
			}
			catch (e:Dynamic)
			{
			}
			completedThread();
		});
	}

	public static function clearInvalids()
	{
		clearInvalidFrom(imagesToPrepare, 'images', '.png', IMAGE);
		clearInvalidFrom(soundsToPrepare, 'sounds', '.${Paths.SOUND_EXT}', SOUND);
		clearInvalidFrom(musicToPrepare, 'music', ' .${Paths.SOUND_EXT}', SOUND);
		clearInvalidFrom(songsToPrepare, 'songs', '.${Paths.SOUND_EXT}', SOUND, 'songs');

		for (arr in [imagesToPrepare, soundsToPrepare, musicToPrepare, songsToPrepare])
			while (arr.contains(null))
				arr.remove(null);
	}

	static function clearInvalidFrom(arr:Array<String>, prefix:String, ext:String, type:AssetType, ?parentFolder:String = null)
	{
		for (folder in arr.copy())
		{
			var nam:String = folder.trim();
			if (nam.endsWith('/'))
			{
				for (subfolder in Mods.directoriesWithFile(Paths.getSharedPath(), '$prefix/$nam'))
				{
					for (file in Paths.readDirectory(subfolder))
					{
						if (file.endsWith(ext))
						{
							var toAdd:String = nam + haxe.io.Path.withoutExtension(file);
							if (!arr.contains(toAdd))
								arr.push(toAdd);
						}
					}
				}

				// trace('Folder detected! ' + folder);
			}
		}

		var i:Int = 0;
		while (i < arr.length)
		{
			var member:String = arr[i];
			var myKey = '$prefix/$member$ext';
			if (parentFolder == 'songs')
				myKey = '$member$ext';

			// trace('attempting on $prefix: $myKey');
			var doTrace:Bool = false;
			if (member.endsWith('/') || (!Paths.fileExists(myKey, type, false, parentFolder) && (doTrace = true)))
			{
				arr.remove(member);
				if (doTrace)
					trace('Removed invalid $prefix: $member');
			}
			else
				i++;
		}
	}

	public static function startThreads()
	{
		mutex = new Mutex();
		loadMax = imagesToPrepare.length + soundsToPrepare.length + musicToPrepare.length + songsToPrepare.length;
		loaded = 0;

		// then start threads
		_threadFunc();
	}

	static function _threadFunc()
	{
		_startPool();
		for (sound in soundsToPrepare)
			initThread(() -> preloadSound('sounds/$sound'), 'sound $sound');
		for (music in musicToPrepare)
			initThread(() -> preloadSound('music/$music'), 'music $music');
		for (song in songsToPrepare)
			initThread(() -> preloadSound(song, 'songs', true, false), 'song $song');

		// for images, they get to have their own thread
		for (image in imagesToPrepare)
			initThread(() -> preloadGraphic(image), 'image $image');
	}

	static function initThread(func:Void->Dynamic, traceData:String)
	{
		// trace('scheduled $func in threadPool');
		#if debug
		var threadSchedule = Sys.time();
		#end
		threadPool.run(() ->
		{
			#if debug
			var threadStart = Sys.time();
			trace('$traceData took ${threadStart - threadSchedule}s to start preloading');
			#end

			try
			{
				if (func() != null)
				{
					#if debug
					var diff = Sys.time() - threadStart;
					trace('finished preloading $traceData in ${diff}s');
					#end
				}
				else
					trace('ERROR! fail on preloading $traceData ');
			}
			catch (e:Dynamic)
			{
				trace('ERROR! fail on preloading $traceData: $e');
			}
			// 2026-11-20 修复：loaded 由线程池多 worker 并发 ++（read-modify-write，非原子）。
			// 之前锁被注释掉，丢失更新会让 loaded 永远追不上 loadMax，sparrow 图集队列
			// 永不构建，进游戏后相关贴图缺失。与 preloadSound 等共用同一把 mutex。
			mutex.acquire();
			loaded++;
			mutex.release();
		});
	}

	inline private static function preloadCharacter(char:String, ?prefixVocals:String)
	{
		try
		{
			var path:String = Paths.getPath('characters/$char.json', TEXT);
			#if MODS_ALLOWED
			var character:Dynamic = Json.parse(File.getContent(path));
			#else
			var character:Dynamic = Json.parse(Assets.getText(path));
			#end

			// 把已解析的角色 JSON 缓存起来，让 Character.changeCharacter() 在主线程直接命中，
			// 省掉重复的 File.getContent + Json.parse 同步开销
			if (character != null)
				Character._preloadedJsonCache.set(char, character);

			var isAnimateAtlas:Bool = false;
			var img:String = character.image;
			img = img.trim();
			#if flxanimate
			var animToFind:String = Paths.getPath('images/$img/Animation.json', TEXT);
			if (#if MODS_ALLOWED FileSystem.exists(animToFind) || #end Assets.exists(animToFind))
				isAnimateAtlas = true;
			#end

			if (!isAnimateAtlas)
			{
				var split:Array<String> = img.split(',');
				for (file in split)
				{
					var trimmed:String = file.trim();
					if (!imagesToPrepare.contains(trimmed))
						imagesToPrepare.push(trimmed);
				}
			}
			#if flxanimate
			else
			{
				for (i in 0...10)
				{
					var st:String = '$i';
					if (i == 0)
						st = '';

					if (Paths.fileExists('images/$img/spritemap$st.png', IMAGE))
					{
						// trace('found Sprite PNG');
						imagesToPrepare.push('$img/spritemap$st');
						break;
					}
				}
			}
			#end

			if (prefixVocals != null && character.vocals_file != null && character.vocals_file.length > 0)
			{
				songsToPrepare.push(prefixVocals + "-" + character.vocals_file);
				if (char == PlayState.SONG.player1)
					dontPreloadDefaultVoices = true;
			}
		}
		catch (e:haxe.Exception)
		{
			trace(e.details());
		}
	}

	// thread safe sound loader
	static function preloadSound(key:String, ?path:String, ?modsAllowed:Bool = true, ?beepOnNull:Bool = true):Null<Sound>
	{
		var file:String = Paths.getPath(LanguageBasic.getFileTranslation(key) + '.${Paths.SOUND_EXT}', SOUND, path, modsAllowed);

		// trace('precaching sound: $file');
		if (!Paths.currentTrackedSounds.exists(file))
		{
			if (#if sys FileSystem.exists(file) || #end OpenFlAssets.exists(file, SOUND))
			{
				var sound:Sound = #if sys Sound.fromFile(file) #else OpenFlAssets.getSound(file, false) #end;
				mutex.acquire();
				Paths.currentTrackedSounds.set(file, sound);
				mutex.release();
			}
			else if (beepOnNull)
			{
				trace('SOUND NOT FOUND: $key, PATH: $path');
				FlxG.log.error('SOUND NOT FOUND: $key, PATH: $path');
				return FlxAssets.getSound('flixel/sounds/beep');
			}
		}
		mutex.acquire();
		Paths.localTrackedAssets.push(file);
		mutex.release();

		return Paths.currentTrackedSounds.get(file);
	}

	@:access(flixel.system.frontEnds.BitmapFrontEnd._cache)
	static function preloadGraphic(key:String):Null<BitmapData>
	{
		try
		{
			var requestKey:String = 'images/$key';
			#if TRANSLATIONS_ALLOWED requestKey = LanguageBasic.getFileTranslation(requestKey); #end
			if (requestKey.lastIndexOf('.') < 0)
				requestKey += '.png';

			// 双重缓存检查：
			// 1. Paths.currentTrackedAssets — 常规资源缓存（被 clearStoredMemory 清空）
			// 2. FlxG.bitmap._cache — 底层 flixel bitmap 缓存（可能仍然保留，即使 currentTrackedAssets 已清）
			// vanilla 角色图集等资源在主菜单加载过，FlxG.bitmap._cache 里还留着，
			// 跳过它们的 BitmapData.fromFile 能省掉大量重复解码时间。
			if (Paths.currentTrackedAssets.exists(requestKey))
				return Paths.currentTrackedAssets.get(requestKey).bitmap;

			if (FlxG.bitmap._cache.exists(requestKey))
			{
				// 已经在 FlxG.bitmap._cache 里，跳过解码。把 FlxGraphic 登记到 currentTrackedAssets
				// 以便后续 checkLoaded 和 PlayState 直接命中，避免重复缓存校验。
				var cachedGraphic:FlxGraphic = FlxG.bitmap._cache.get(requestKey);
				if (cachedGraphic != null)
				{
					Paths.currentTrackedAssets.set(requestKey, cachedGraphic);
					Paths.trackLocalAsset(requestKey);
					return cachedGraphic.bitmap;
				}
			}

			var file:String = Paths.getPath(requestKey, IMAGE);
			if (#if sys FileSystem.exists(file) || #end OpenFlAssets.exists(file, IMAGE))
			{
				#if sys
				var bitmap:BitmapData = BitmapData.fromFile(file);
				#else
				var bitmap:BitmapData = OpenFlAssets.getBitmapData(file, false);
				#end

				mutex.acquire();
				requestedBitmaps.set(file, bitmap);
				originalBitmapKeys.set(file, requestKey);
				mutex.release();
				return bitmap;
			}
			else
				trace('no such image $key exists');
		}
		catch (e:haxe.Exception)
		{
			trace('ERROR! fail on preloading image $key');
		}

		return null;
	}
}
