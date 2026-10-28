package;

import debug.FPSCounter;
import debug.GameLogDisplay;
import flixel.FlxGame;
import openfl.Lib;
import openfl.display.Sprite;
import openfl.events.Event;
import openfl.display.StageScaleMode;
import openfl.display.StageQuality;
import lime.app.Application;
import states.TitleState;
import states.LogoState;
import states.EnhancedFlixelState;
import states.FreeplayState;
import states.CommandLineLaunchState;
#if HSCRIPT_ALLOWED
import crowplexus.iris.Iris;
import psychlua.HScript.HScriptInfos;
#end
import mobile.backend.MobileScaleMode;
import openfl.events.KeyboardEvent;
import lime.system.System as LimeSystem;
import Sys;
import backend.Paths;
#if (linux || mac)
import lime.graphics.Image;
#end
#if COPYSTATE_ALLOWED
import states.CopyState;
#end
import backend.Highscore;
import flixel.tweens.FlxTween;
import flixel.tweens.FlxEase;
import backend.ClientPrefs;
#if desktop
import backend.PseudoTitleBar;
#end
import openfl.ui.Keyboard;

// NATIVE API STUFF, YOU CAN IGNORE THIS AND SCROLL //
#if (linux && !debug)
@:cppInclude('./external/gamemode_client.h')
@:cppFileCode('#define GAMEMODE_AUTO')
#end
// // // // // // // // //
class Main extends Sprite
{
	public static final game = {
		width: 1280, // WINDOW width
		height: 720, // WINDOW height
		initialState: LogoState, // initial game state (实际在 new FlxGame 时按 splashMode 决定)
		framerate: 60, // default framerate
		skipSplash: true, // if the default flixel splash screen should be skipped (实际按 splashMode 决定)
		startFullscreen: false // if the game should start at fullscreen mode
	};

	public static var fpsLayer:Sprite;
	public static var fpsVar:FPSCounter;
	public static var gameLogVar:GameLogDisplay;
	#if desktop
	public static var titleBar:PseudoTitleBar;
	#end

	/** 强制隐藏 FPS 计数器（如进入制谱器时临时隐藏，不受 showFPS 设置与窗口缩放影响）。
	 * 设为 false 或调用 updateFPSCounterVisibility 可恢复。 */
	public static var forceHideFPS:Bool = false;

	/** 命令行直启参数（由 parseCommandLineArgs 填充）；为 null 时走正常启动流程 */
	public static var commandLineLaunch:CommandLineLaunch = null;

	public static final platform:String = #if mobile "Phones" #else "PCs" #end;

	#if (cpp && windows && !mobile)
	private static var isAdminCached:Bool = false;
	#end

	// Background volume control variables
	private var backgroundVolumeTween:FlxTween;
	private var originalVolume:Float = 1.0;
	private var isInBackground:Bool = false;

	// You can pretty much ignore everything from here on - your code should go in your states.

	public static function main():Void
	{
		Lib.current.addChild(new Main());
		applyGarbageCollectorSetting();
	}

	// 根据设置决定是否启用原生GC（cpp.NativeGc / hl.Gc）。
	// 关闭原生GC可减少周期性GC停顿导致的掉帧；启动时与设置变更时调用，立即生效。
	public static function applyGarbageCollectorSetting():Void
	{
		var enabled:Bool = (ClientPrefs.data != null) && ClientPrefs.data.garbageCollectorEnabled;
		#if cpp
		cpp.NativeGc.enable(enabled);
		#elseif hl
		hl.Gc.enable(enabled);
		#end
	}

	public static var originalHaxeTrace:Dynamic->?haxe.PosInfos->Void = null;

	public static function shouldLogToConsole():Bool
	{
		#if debug
		return true;
		#else
		return ClientPrefs.data != null && ClientPrefs.data.enableConsoleLog;
		#end
	}

	public static function hookConsoleLog():Void
	{
		if (originalHaxeTrace != null) return;
		originalHaxeTrace = haxe.Log.trace;
		haxe.Log.trace = function(v:Dynamic, ?pos:haxe.PosInfos):Void
		{
			if (shouldLogToConsole() && originalHaxeTrace != null)
			{
				originalHaxeTrace(v, pos);
			}
		};
	}

	public function new()
	{
		super();
		// 尽早劫持日志输出，避免 debug 编译以外时污染终端
		hookConsoleLog();

		// 解析命令行直启参数（--mod / --week / --song / --diff 或位置参数）
		parseCommandLineArgs();

		#if mobile
		#if android
		StorageUtil.requestPermissions();
		#end
		Sys.setCwd(StorageUtil.getStorageDirectory());
		#end
		backend.CrashHandler.init();

		#if (cpp && windows)
		backend.Native.fixScaling();
		#end

		#if VIDEOS_ALLOWED
		hxvlc.util.Handle.init(#if (hxvlc >= "1.8.0") ['--no-lua'] #end);
		#end

		#if LUA_ALLOWED
		Mods.pushGlobalMods();
		#end
		Mods.loadTopMod();

		FlxG.save.bind('funkin', CoolUtil.getSavePath());

		#if desktop
		// Apply the borderless flag before the FlxGame is created, so the
		// native title bar does not flash during startup.
		if (FlxG.save.data != null && Reflect.field(FlxG.save.data, 'borderless') == true)
			PseudoTitleBar.applyStartupBorderless(true);
		#end

		#if HSCRIPT_ALLOWED
		Iris.warn = function(x, ?pos:haxe.PosInfos)
		{
			Iris.logLevel(WARN, x, pos);
			var newPos:HScriptInfos = cast pos;
			if (newPos.showLine == null)
				newPos.showLine = true;
			var msgInfo:String = (newPos.funcName != null ? '(${newPos.funcName}) - ' : '') + '${newPos.fileName}:';
			#if LUA_ALLOWED
			if (newPos.isLua == true)
			{
				msgInfo += 'HScript:';
				newPos.showLine = false;
			}
			#end
			if (newPos.showLine == true)
			{
				msgInfo += '${newPos.lineNumber}:';
			}
			msgInfo += ' $x';
			if (PlayState.instance != null)
				PlayState.instance.addTextToDebug('WARNING: $msgInfo', FlxColor.YELLOW);
		}
		Iris.error = function(x, ?pos:haxe.PosInfos)
		{
			Iris.logLevel(ERROR, x, pos);
			var newPos:HScriptInfos = cast pos;
			if (newPos.showLine == null)
				newPos.showLine = true;
			var msgInfo:String = (newPos.funcName != null ? '(${newPos.funcName}) - ' : '') + '${newPos.fileName}:';
			#if LUA_ALLOWED
			if (newPos.isLua == true)
			{
				msgInfo += 'HScript:';
				newPos.showLine = false;
			}
			#end
			if (newPos.showLine == true)
			{
				msgInfo += '${newPos.lineNumber}:';
			}
			msgInfo += ' $x';
			if (PlayState.instance != null)
				PlayState.instance.addTextToDebug('ERROR: $msgInfo', FlxColor.RED);
		}
		Iris.fatal = function(x, ?pos:haxe.PosInfos)
		{
			Iris.logLevel(FATAL, x, pos);
			var newPos:HScriptInfos = cast pos;
			if (newPos.showLine == null)
				newPos.showLine = true;
			var msgInfo:String = (newPos.funcName != null ? '(${newPos.funcName}) - ' : '') + '${newPos.fileName}:';
			#if LUA_ALLOWED
			if (newPos.isLua == true)
			{
				msgInfo += 'HScript:';
				newPos.showLine = false;
			}
			#end
			if (newPos.showLine == true)
			{
				msgInfo += '${newPos.lineNumber}:';
			}
			msgInfo += ' $x';
			if (PlayState.instance != null)
				PlayState.instance.addTextToDebug('FATAL: $msgInfo', 0xFFBB0000);
		}
		#end

		#if LUA_ALLOWED Lua.set_callbacks_function(cpp.Callable.fromStaticFunction(psychlua.CallbackHandler.call)); #end
		Controls.instance = new Controls();
		ClientPrefs.loadDefaultKeys();
		
		// 1. 先绑定 FlxG.save，读取 soundTrayStyle 等需要提前知道的设置
		FlxG.save.bind('funkin', CoolUtil.getSavePath());
		if (Reflect.hasField(FlxG.save.data, 'soundTrayStyle')) {
			ClientPrefs.data.soundTrayStyle = FlxG.save.data.soundTrayStyle;
		}
		
		#if ACHIEVEMENTS_ALLOWED Achievements.load(); #end
		#if mobile
		FlxG.signals.postGameStart.addOnce(() ->
		{
			FlxG.scaleMode = new MobileScaleMode();
		});
		#end
		
		// 2. 游戏启动后再加载完整设置（此时 FlxG 已完全初始化，loadPrefs 内的
		//    FlxG.sound / Controls.instance 均可用）。注意：不能在 Main.new() 内同步调用
		//    loadPrefs()，否则此刻 FlxG.sound 等为 null 会崩溃。
		FlxG.signals.postGameStart.addOnce(() ->
		{
			ClientPrefs.loadPrefs();
			#if desktop
			PseudoTitleBar.applySettings();
			#end
			// 加载完设置后再按保存值启用/关闭原生GC
			applyGarbageCollectorSetting();
		});

		// 启动开屏模式: 'Kathy' = 自定义 Logo 开屏, 'Flixel' = Flixel 自带 splash, 'None' = 直接进游戏
		// 此时尚未 loadPrefs，直接读取已 bind 的 FlxG.save.data（桌面走此分支，移动端走 CopyState 分支）
		var splashMode:String = Reflect.field(FlxG.save.data, 'splashMode');
		if (splashMode == null) splashMode = 'Kathy';

		var skipSplash:Bool = true;
		var initialGameState:Class<flixel.FlxState> = LogoState;
		switch (splashMode)
		{
			case 'Flixel':
				skipSplash = false; // 显示 Flixel 自带 splash，随后进入标题
				initialGameState = TitleState;
			case 'None':
				skipSplash = true; // 不显示任何开屏，直接进入游戏
				initialGameState = TitleState;
			case 'Flixel+':
				skipSplash = true; // 不显示官方 splash，使用增强版风车开屏
				initialGameState = EnhancedFlixelState;
			default: // 'Kathy'
				skipSplash = true;
				initialGameState = LogoState; // 自定义 Logo 开屏，结束后进入 TitleState
		}

		// 命令行直启：开屏画面仍由上面的 splashMode 决定，这里只预填参数。
		// 开屏结束后的跳转目标由各个「开屏结束态」(LogoState / TitleState / EnhancedFlixelState) 按 commandLineLaunch 决定。
		#if MODS_ALLOWED
		if (commandLineLaunch != null)
		{
			CommandLineLaunchState.launchData = commandLineLaunch;
		}
		#end

		// addChild(new FlxGame(game.width, game.height, #if COPYSTATE_ALLOWED !CopyState.checkExistingFiles() ? CopyState : #end initialGameState, game.framerate, game.framerate, skipSplash, game.startFullscreen));

		var game:FlxGame = new FlxGame(game.width, game.height, #if COPYSTATE_ALLOWED !CopyState.checkExistingFiles() ? CopyState : #end initialGameState,
			#if (flixel < "5.0.0") game.zoom, #end game.framerate, game.framerate, skipSplash, game.startFullscreen);
		if (ClientPrefs.data.soundTrayStyle == 'Funkin') {
			@:privateAccess
			game._customSoundTray = backend.FunkinSoundTray;
		}
		else if (ClientPrefs.data.soundTrayStyle == 'Kathy') {
			@:privateAccess
			game._customSoundTray = backend.KathySoundTray;
		}
		else if (ClientPrefs.data.soundTrayStyle == 'Dave') {
			@:privateAccess
			game._customSoundTray = backend.DaveEngineSoundTray;
		}
		addChild(game);

		// 创建 fpsLayer 作为 FPS 计数器的统一容器
		fpsLayer = new Sprite();
		fpsLayer.x = 0;
		fpsLayer.y = 0;
		Lib.current.stage.addChild(fpsLayer);

		// fpsVar 现在内部支持 Psych 和 Simple 两种渲染模式
		fpsVar = new FPSCounter(10, 3, 0xFFFFFF);
		fpsLayer.addChild(fpsVar);
		
		// 根据设置更新 fpsLayer 的位置和缩放
		updateFPSLayer();
		Lib.current.stage.align = "tl";
		Lib.current.stage.scaleMode = StageScaleMode.SHOW_ALL;
		Lib.current.stage.quality = ClientPrefs.getStageQuality();

		// 创建游戏日志显示
		gameLogVar = new GameLogDisplay();
		gameLogVar.setEnabled(ClientPrefs.data.enableGameLog);
		Lib.current.stage.addChild(gameLogVar);

		#if desktop
		// 无边框模式下替代系统标题栏的游戏内伪标题栏
		titleBar = new PseudoTitleBar();
		titleBar.onExit = function() {
			requestExit();
		};
		titleBar.onFrameChanged = function() {
			updateFPSLayer();
		};
		Lib.current.stage.addChild(titleBar);
		// postGameStart may already have fired before this overlay existed.
		// Mirror the saved flag so the immediate apply below does not undo the
		// startup borderless state when ClientPrefs has not finished loading.
		if (FlxG.save.data != null)
		{
			var savedBorderless:Dynamic = Reflect.field(FlxG.save.data, 'borderless');
			if (savedBorderless != null) ClientPrefs.data.borderless = (savedBorderless == true);
		}
		PseudoTitleBar.applySettings();
		#end

		Language.load();

	#if (linux || mac) // fix the app icon not showing up on the Linux Panel / Mac Dock
	var icon = Image.fromFile("icon.png");
	Lib.current.stage.window.setIcon(icon);
	#end

	#if (cpp && windows && !mobile)
	// 检测管理员权限并更新窗口标题
	checkAndUpdateAdminTitle();
	#end

		#if html5
		FlxG.autoPause = false;
		FlxG.mouse.visible = false;
		#end

		FlxG.fixedTimestep = ClientPrefs.data.fixedTimestep;
		FlxG.game.focusLostFramerate = #if mobile 30 #else 60 #end;
		#if web
		FlxG.keys.preventDefaultKeys.push(TAB);
		#else
		FlxG.keys.preventDefaultKeys = [TAB];
		#end

		#if DISCORD_ALLOWED
		DiscordClient.prepare();
		#end

		#if desktop FlxG.stage.addEventListener(KeyboardEvent.KEY_UP, onKeyPress); #end

		#if mobile
		#if android FlxG.android.preventDefaultKeys = [BACK]; #end
		LimeSystem.allowScreenTimeout = ClientPrefs.data.screensaver;
		#end

		// Application.current.window.vsync = ClientPrefs.data.vsync;

		// shader coords fix
		FlxG.signals.gameResized.add(function(w, h)
		{
			// 更新 fpsLayer / fpsVar 的缩放和偏移（随窗口大小变化）
			// 注意：统一交给 updateFPSLayer() 管理，不要再单独给 fpsVar 传 ratio 缩放，
			// 否则 Game 模式下 fpsLayer 已缩放，再加 fpsVar 自身缩放会叠加放大（甚至超出屏幕）。
			updateFPSLayer();
			
			if (FlxG.cameras != null)
			{
				for (cam in FlxG.cameras.list)
				{
					if (cam != null && cam.filters != null)
						resetSpriteCache(cam.flashSprite);
				}
			}

			if (FlxG.game != null)
				resetSpriteCache(FlxG.game);
		});

		// 监听 stage 窗口大小变化，更新 FPS 计数器位置
		Lib.current.stage.addEventListener(Event.RESIZE, function(e:Event):Void
		{
			// 先更新 fpsLayer 的缩放和偏移
			updateFPSLayer();
			
			if (fpsVar != null)
			{
				fpsVar.positionFPS(10, 3, 1);
			}
			if (gameLogVar != null)
			{
				gameLogVar.updatePositionOnResize();
			}
		});

		#if (desktop && !mobile)
		setCustomCursor();
		#end

		// 添加应用激活/停用事件监听
		Lib.current.stage.addEventListener(Event.DEACTIVATE, onAppDeactivate);
		Lib.current.stage.addEventListener(Event.ACTIVATE, onAppActivate);

		// 动态窗口标题：每帧检测当前状态是否切换，切换时刷新标题
		Lib.current.stage.addEventListener(Event.ENTER_FRAME, onWindowTitleFrame);

		#if (cpp && windows && !mobile)
		// 延迟初始化窗口关闭回调，确保窗口完全创建后再设置
		haxe.Timer.delay(function()
		{
			backend.Native.setCloseCallback();
			// 启动关闭检查定时器
			startCloseCheckTimer();
		}, 100); // 延迟 100ms，更快启用关闭拦截
		#end
	}

	/**
	 * 渐隐关闭应用（仅Windows桌面端）
	 */
	#if (cpp && windows && !mobile)
	private static var isExiting:Bool = false;
	private static var closeCheckTimer:haxe.Timer = null;

	private static function checkCloseRequest():Void
	{
		if (backend.Native.isClosingRequested())
		{
			// 重置标志
			backend.Native.resetClosingRequested();

			// 停止定时器
			if (closeCheckTimer != null)
			{
				closeCheckTimer.stop();
				closeCheckTimer = null;
			}

			// 执行关闭流程
			startFadeOutAndExit();

			return; // 停止检查
		}
	}

	// 启动关闭请求检查（使用较慢的定时器减少性能影响）
	private static function startCloseCheckTimer():Void
	{
		if (closeCheckTimer != null)
			return; // 已经在运行

		closeCheckTimer = new haxe.Timer(100); // 每 100ms 检查一次（每秒 10 次）
		closeCheckTimer.run = checkCloseRequest;
	}

	// 停止关闭请求检查
	private static function stopCloseCheckTimer():Void
	{
		if (closeCheckTimer != null)
		{
			closeCheckTimer.stop();
			closeCheckTimer = null;
		}
	}

	private static function startFadeOutAndExit():Void
	{
		// 防止重复执行
		if (isExiting)
			return;
		isExiting = true;

		// 停止关闭检查定时器（性能优化）
		stopCloseCheckTimer();

		// 立即静音音乐（无延迟）
		if (FlxG.sound.music != null)
		{
			FlxG.sound.music.volume = 0;
		}

		// 立即播放关闭音效（无延迟）
		FlxG.sound.play(Paths.sound('BA/UI_BattleComplete'), 0.75, false);

		// 短暂延迟后开始渐隐（让音效开始播放）
		haxe.Timer.delay(function()
		{
			// 执行渐隐动画，持续500ms
			backend.Native.fadeOutWindow(500);

			// 延迟退出
			haxe.Timer.delay(function()
			{
				// 关闭 Discord（如果已初始化）
				#if DISCORD_ALLOWED
				if (DiscordClient.isInitialized)
					DiscordClient.shutdown();
				#end

				// 退出应用
				LimeSystem.exit(0);
			}, 550); // 550ms = 500ms 渐隐 + 50ms 缓冲
		}, 20); // 20ms 延迟，极快响应
	}
	#end

	/** Shared quit path for the in-game title bar and other UI entry points. */
	public static var isExitRequested:Bool = false;

	public static function requestExit():Void
	{
		if (isExitRequested) return;
		isExitRequested = true;

		try
		{
			ClientPrefs.saveSettings();
		}
		catch (e:Dynamic)
		{
			trace('Failed to save settings before exit: $e');
		}

		#if (cpp && windows && !mobile)
		startFadeOutAndExit();
		#else
		#if DISCORD_ALLOWED
		try
		{
			if (DiscordClient.isInitialized) DiscordClient.shutdown();
		}
		catch (e:Dynamic) {}
		#end
		LimeSystem.exit(0);
		#end
	}

	// 应用进入后台时调用
	private function onAppDeactivate(e:Event):Void
	{
		if (isInBackground || !ClientPrefs.data.backgroundVolume || FreeplayState.isFreeplayPlayingMusic)
			return;
		isInBackground = true;

		// 取消正在进行的恢复动画（如果存在）
		if (backgroundVolumeTween != null)
		{
			backgroundVolumeTween.cancel();
			backgroundVolumeTween = null;
		}

		// 保存当前音量
		originalVolume = FlxG.sound.volume;

		// 创建降低音量的动画
		backgroundVolumeTween = FlxTween.tween(FlxG.sound, {volume: ClientPrefs.data.backgroundVolumeLevel}, 1, {
			ease: FlxEase.quadOut,
			onComplete: function(twn:FlxTween)
			{
				backgroundVolumeTween = null;
			}
		});
	}

	// 应用回到前台时调用
	private function onAppActivate(e:Event):Void
	{
		if (!isInBackground)
			return;
		isInBackground = false;

		// 切回前台后窗口尺寸/缩放可能变化（状态栏、导航栏、DPI 等），重新同步 FPS 计数器布局。
		// 延迟一帧，等待 stage 尺寸稳定后再计算，避免用旧尺寸得到错误缩放。
		haxe.Timer.delay(function()
		{
			updateFPSLayer();
		}, 30);

		// 未开启后台音量功能时，仅重同步 FPS 布局即可，不恢复音量
		if (!ClientPrefs.data.backgroundVolume)
			return;

		// 取消正在进行的降低动画（如果存在）
		if (backgroundVolumeTween != null)
		{
			backgroundVolumeTween.cancel();
			backgroundVolumeTween = null;
		}

		// 创建恢复音量的动画
		backgroundVolumeTween = FlxTween.tween(FlxG.sound, {volume: originalVolume}, 0.5, {
			ease: FlxEase.quadOut,
			onComplete: function(twn:FlxTween)
			{
				backgroundVolumeTween = null;
			}
		});
	}

	#if (cpp && windows && !mobile)
	/**
	 * 检测管理员权限并更新窗口标题
	 */
	private static function checkAndUpdateAdminTitle():Void
	{
		// 检测是否具有管理员权限
		isAdminCached = backend.Native.isAdmin();

		// 更新窗口标题
		updateWindowTitle();
	}
	#end

	/**
	 * 更新窗口标题。
	 *
	 * useCustomWindowTitle=true  ：使用“伪窗口标题”设置，并接管动态标题。
	 * useCustomWindowTitle=false ：完全不修改窗口标题，保留游戏/模组原始标题。
	 */
	public static function updateWindowTitle(force:Bool = true):Void
	{
		if (Lib.current.stage != null && Lib.current.stage.window != null)
		{
			var window = Lib.current.stage.window;

			if (!ClientPrefs.data.useCustomWindowTitle)
			{
				// 关闭自定义标题时，如果当前标题仍是引擎上一次写入的伪标题，
				// 恢复成应用原始标题；如果已被模组改成别的值，则不要覆盖它。
				if (force && _lastAppliedWindowTitle != null && window.title == _lastAppliedWindowTitle)
				{
					var originalTitle:String = Application.current.meta.get('title');
					if (originalTitle == null) originalTitle = "Kathy Engine";
					window.title = originalTitle;
				}

				_lastAppliedWindowTitle = null;
				return;
			}

			var baseTitle:String = ClientPrefs.data.windowTitle != null ? ClientPrefs.data.windowTitle : Application.current.meta.get('title');
			if (baseTitle == null) baseTitle = "Kathy Engine";

			var adminSuffix:String = "";
			#if (cpp && windows && !mobile)
			if (isAdminCached) adminSuffix = " (Administrator)";
			#end

			// 未启用动态窗口标题时，仅显示基础标题
			if (!ClientPrefs.data.dynamicWindowTitle)
			{
				var title:String = baseTitle + adminSuffix;
				window.title = title;
				_lastAppliedWindowTitle = title;
				return;
			}

			var parts:Array<String> = [baseTitle + adminSuffix];

			// 当前模组名称
			if (ClientPrefs.data.windowTitleShowMod)
			{
				var modName:String = Mods.currentModDirectory;
				if (modName != null && modName.length > 0)
					parts.push("Mod: " + modName);
			}

			// 游玩中：显示当前曲目（实时信息）
			if (Std.isOfType(FlxG.state, PlayState) && PlayState.SONG != null)
			{
				if (ClientPrefs.data.windowTitleShowSong)
				{
					var songStr:String = PlayState.SONG.song;
					if (ClientPrefs.data.windowTitleShowDifficulty)
						songStr += " (" + Difficulty.getString() + ")";
					parts.push("Playing: " + songStr);
				}
			}
			else if (ClientPrefs.data.windowTitleShowState)
			{
				// 非游玩状态：显示当前界面/状态名称
				var stateName:String = (FlxG.state == null) ? "Unknown" : Type.getClassName(Type.getClass(FlxG.state)).split('.').pop();
				parts.push("Screen: " + stateName);
			}

			var title:String = parts.join(" | ");
			window.title = title;
			_lastAppliedWindowTitle = title;
		}
	}


	// 每帧检测状态切换（仅在状态实例变化时刷新窗口标题，避免重复设置）
	private static var _lastWindowTitleState:Dynamic = null;
	private static var _lastAppliedWindowTitle:String = null;
	private static function onWindowTitleFrame(_):Void
	{
		var cur = FlxG.state;
		if (cur != _lastWindowTitleState)
		{
			_lastWindowTitleState = cur;
			updateWindowTitle(false);
		}
	}

	/**
	 * 根据 fpsLayer 设置调整 FPS 计数器图层的缩放和位置
	 * "Stage" - 屏幕像素坐标系，不受游戏缩放影响
	 * "Game"  - 1280x720 游戏坐标系，随游戏一起缩放并居中
	 * 
	 * 注意：此函数统一管理 fpsLayer 的缩放/偏移和计数器在 fpsLayer 内的位置，
	 *       避免 positionFPS/positionSimpleInfo 的双重缩放问题
	 */
	public static function updateFPSLayer():Void
	{
		if(fpsLayer == null) return;

		// 始终保持在 Lib.current.stage 上，避免渲染兼容性问题
		if(fpsLayer.parent != Lib.current.stage) {
			if(fpsLayer.parent != null) {
				fpsLayer.parent.removeChild(fpsLayer);
			}
			Lib.current.stage.addChild(fpsLayer);
			#if desktop
			if (titleBar != null) titleBar.bringFrameAbove(fpsLayer);
			#end
		}

		var screenWidth:Float = Lib.current.stage.stageWidth;
		var screenHeight:Float = Lib.current.stage.stageHeight;

		#if desktop
		var frameBorder = PseudoTitleBar.getFrameBorder();
		var content = PseudoTitleBar.getGameContentRect();
		#else
		var frameBorder = 0.0;
		var content = {x: 0.0, y: 0.0, width: screenWidth, height: screenHeight};
		#end

		if (content.width <= 0 || content.height <= 0)
			content = {x: 0.0, y: 0.0, width: screenWidth, height: screenHeight};

		// 先更新可见性（applySettings 会被调用，可能覆盖位置）
		updateFPSCounterVisibility();

		if(ClientPrefs.data.fpsLayer == "Game") {
			// Game 模式：与游戏画面对齐 —— 等比缩放 + 居中偏移
			var gameWidth:Float = 1280;
			var gameHeight:Float = 720;
			var scale:Float = Math.min(content.width / gameWidth, content.height / gameHeight);

			fpsLayer.scaleX = scale;
			fpsLayer.scaleY = scale;
			fpsLayer.x = content.x + (content.width - gameWidth * scale) / 2;
			fpsLayer.y = content.y + (content.height - gameHeight * scale) / 2;

			// fpsVar 在 fpsLayer 内部，使用 1280x720 坐标（无额外缩放）
			if(fpsVar != null) {
				fpsVar.scaleX = 1;
				fpsVar.scaleY = 1;

				var spacing:Float = ClientPrefs.data.fpsSpacing;
				var isRight:Bool = ClientPrefs.data.fpsPosition.indexOf("RIGHT") != -1;
				var isBottom:Bool = ClientPrefs.data.fpsPosition.indexOf("BOTTOM") != -1;
				fpsVar.x = isRight ? (gameWidth - 220 - spacing) : spacing;
				fpsVar.y = isBottom ? (gameHeight - 40 - spacing) : spacing;
			}
		} else {
			// Stage 模式：不缩放 fpsLayer，使用屏幕像素坐标。
			// 伪边框开启时，把整个 stage 坐标空间等比缩进到游戏区域内部，
			// 这样所有 FPS 样式都会自动避开边框。
			if (frameBorder > 0) {
				var scale:Float = Math.min(content.width / screenWidth, content.height / screenHeight);
				fpsLayer.scaleX = scale;
				fpsLayer.scaleY = scale;
				fpsLayer.x = content.x + (content.width - screenWidth * scale) / 2;
				fpsLayer.y = content.y + (content.height - screenHeight * scale) / 2;
			} else {
				fpsLayer.scaleX = 1;
				fpsLayer.scaleY = 1;
				fpsLayer.x = 0;
				fpsLayer.y = 0;
			}

			// Stage 模式下，positionFPS 使用 stage 坐标逻辑
			if(fpsVar != null) {
				fpsVar.positionFPS(10, 3, 1);
			}
		}
	}

	/**
	 * 根据 fpsStyle 和 showFPS 设置更新 FPS 计数器的可见性
	 * fpsVar 内部已支持 Psych 和 Simple 两种渲染模式
	 */
	public static function updateFPSCounterVisibility():Void
	{
		if(fpsVar != null) {
			fpsVar.visible = ClientPrefs.data.showFPS && !forceHideFPS;
			fpsVar.applySettings();
		}
	}

	static function resetSpriteCache(sprite:Sprite):Void
	{
		@:privateAccess {
			sprite.__cacheBitmap = null;
			sprite.__cacheBitmapData = null;
		}
	}

	function onKeyPress(event:KeyboardEvent)
	{
		if (Controls.instance.justReleased('fullscreen'))
		{
			FlxG.fullscreen = !FlxG.fullscreen;
			// 切换全屏后修复分辨率
			#if (cpp && windows)
			haxe.Timer.delay(function()
			{
				backend.Native.fixFullscreenResolution();
			}, 50);
			#end
		}

		// F3键切换日志显示
		if (event.keyCode == Keyboard.F3 && gameLogVar != null)
		{
			gameLogVar.toggleVisibility();
		}

		// 原版 Debug 显示面板的独立开关+模式循环热键（Off/Simple/Advanced）
		if (event.keyCode == ClientPrefs.data.fpsDebugHotkey && fpsVar != null)
		{
			fpsVar.cycleDebugMode();
		}

		/*#if (cpp && windows && !mobile)
			// 拦截 ESC 键，执行渐隐关闭
			if (event.keyCode == Keyboard.ESCAPE)
			{
				// 阻止默认的 ESC 行为
				event.preventDefault();
				event.stopPropagation();
				event.stopImmediatePropagation();

				// 执行渐隐关闭
				startFadeOutAndExit();
			}
			#end */

		// F5键刷新当前state（使用CustomFadeTransition无缝切换）
		if (event.keyCode == Keyboard.F5 && FlxG.state != null)
		{
			// 获取当前state的类型
			var currentStateType:Class<flixel.FlxState> = Type.getClass(FlxG.state);

			// 创建新的state实例
			if (currentStateType != null)
			{
				var newState:flixel.FlxState = Type.createInstance(currentStateType, []);

				// 标记为刷新操作（CustomFadeTransition构造函数中会立即读取并重置）
				backend.CustomFadeTransition.isReloading = true;
				backend.CustomFadeTransition.reloadingStateType = currentStateType; // 保存要 reload 的 state 类型

				// 检查是否是MusicBeatState，使用自定义转场
				#if !macro
				// 尝试使用MusicBeatState的startTransition方法
				if (Std.isOfType(FlxG.state, backend.MusicBeatState))
				{
					backend.MusicBeatState.startTransition(newState);
				}
				else
				{
					// 非MusicBeatState，直接切换
					FlxG.switchState(newState);
				}
				#else
				FlxG.switchState(newState);
				#end
			}
		}
	}

	function setCustomCursor():Void
	{
		FlxG.mouse.load('assets/shared/images/cursor.png');
	}

	/**
	 * 解析命令行参数，填充 commandLineLaunch。
	 * 支持的参数：
	 *   --mod <模组名>   --week <周名>   --song <曲目名>   --diff <难度>
	 *   --play "模组|周|曲目|难度"   或位置参数：模组 周 曲目 [难度]
	 *   --help / -h   打印帮助
	 */
	function parseCommandLineArgs():Void
	{
		var args:Array<String> = Sys.args();
		if (args == null || args.length == 0)
			return;

		var mod:String = null;
		var week:String = null;
		var song:String = null;
		var diff:String = null;

		var i:Int = 0;
		while (i < args.length)
		{
			var a:String = args[i];
			function nextArg():String
			{
				if (i + 1 < args.length)
					return args[++i];
				return null;
			}
			switch (a.toLowerCase())
			{
				case '-mod', '--mod', '/mod':
					mod = nextArg();
				case '-week', '--week', '/week':
					week = nextArg();
				case '-song', '--song', '/song':
					song = nextArg();
				case '-diff', '--diff', '-difficulty', '--difficulty', '/diff':
					diff = nextArg();
				case '-play', '--play', '-launch', '--launch':
					var parts:Array<String> = nextArg().split('|');
					if (mod == null && parts.length > 0) mod = parts[0];
					if (week == null && parts.length > 1) week = parts[1];
					if (song == null && parts.length > 2) song = parts[2];
					if (diff == null && parts.length > 3) diff = parts[3];
				case '-h', '--help', '/help', '-?', '/?':
					printLaunchHelp();
					return;
				default:
					// 位置参数：mod week song [diff]
					if (mod == null) mod = a;
					else if (week == null) week = a;
					else if (song == null) song = a;
					else if (diff == null) diff = a;
			}
			i++;
		}

		if (song != null && song.trim().length > 0)
		{
			commandLineLaunch = {mod: mod, week: week, song: song, difficulty: diff};
			trace('Command-line launch requested: mod=$mod, week=$week, song=$song, diff=$diff');
		}
	}

	function printLaunchHelp():Void
	{
		Sys.println('');
		Sys.println('Kathy Engine - 命令行直启用法:');
		Sys.println('  KathyEngine.exe --mod "模组名" --week "周名" --song "曲目名" [--diff "难度"]');
		Sys.println('  KathyEngine.exe --play "模组名|周名|曲目名|难度"');
		Sys.println('  KathyEngine.exe "模组名" "周名" "曲目名" ["难度"]   (位置参数)');
		Sys.println('  说明: 未找到目标时会提示并返回 Freeplay。');
		Sys.println('');
	}
}
