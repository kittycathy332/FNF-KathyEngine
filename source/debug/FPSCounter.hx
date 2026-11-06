package debug;

import flixel.FlxG;
import openfl.Lib;
import haxe.Timer;
import openfl.text.TextField;
import openfl.text.TextFormat;
import lime.system.System as LimeSystem;
import states.MainMenuState;
import debug.GameVersion;
import debug.HaxelibInfo;
import openfl.display.Sprite;
import flixel.FlxState;
import openfl.utils.Assets;
import openfl.utils.AssetCache;
import openfl.utils.AssetType;
import backend.ClientPrefs;
import backend.Paths;
import StringTools;
import lime.app.Application;
import debug.PsychFPSCounter;
#if cpp
#if windows
@:cppFileCode('#include <windows.h>')
#elseif (ios || mac)
@:cppFileCode('#include <mach-o/arch.h>')
#else
@:headerInclude('sys/utsname.h')
#end
#end
class FPSCounter extends Sprite
{
	public var currentFPS(default, null):Int = 0;

	public var memoryMegas(get, never):Float;
	public var memoryPeakMegas(default, null):Float = 0;

	// ---- 环形 FPS 缓冲区（替代 Array.push/shift） ----
	private static final RING_SIZE:Int = 10000;
	@:noCompletion private var ringTimes:Array<Float>;
	@:noCompletion private var ringWrite:Int = 0;
	@:noCompletion private var ringCount:Int = 0;

	@:noCompletion private var lastFramerateUpdateTime:Float;
	@:noCompletion private var updateTime:Int;
	@:noCompletion private var framesCount:Int;
	@:noCompletion private var prevTime:Int;
	@:noCompletion private var currentTime:Float;
	@:noCompletion private var cacheCount:Int;

	public var objectCount(default, null):Int = 0;

	@:noCompletion private var lastObjectCountUpdate:Float = 0;
	@:noCompletion private var lastDelayUpdateTime:Float = 0;
	@:noCompletion private var currentDelay:Float = 0;

	public var os:String = '';

	// 文本字段
	private var allInfoText:TextField;
	
	// 背景
	private var bgSprite:Sprite;

	// 原版 FunkinDebugDisplay 风格（"Debug" fpsStyle）独立面板
	public var debugDisplay:FunkinDebugDisplay;

	// 原版 Psych 风格实例（fpsStyle == "Psych" 时显示）
	private var psychInstance:PsychFPSCounter;

	// 布局参数
	private var lineHeight:Float = 18;

	// 性能优化变量
	private var lastFpsUpdateTime:Float = 0;

	public var fontName:String = Paths.font("vcr.ttf");

	// ---- 缓存变量 ----
	private var _cachedMemMegas:Float = 0;
	private var _lastMemQueryTime:Float = 0;
	private var _lastHtmlText:String = null;      // 上次写入 allInfoText.htmlText 的值
	private var _lastSimpleText:String = null;   // Simple 模式上次写入 text 的值
	private var _lastTextFormatHash:Int = -1;    // TextFormat 变化标识
	private var _lastBgWidth:Float = -1;         // 上次背景宽度
	private var _lastBgHeight:Float = -1;        // 上次背景高度
	private var _lastVersionStr:String = null;   // 缓存 Application.version
	private var _cachedAssetText:String = null;  // 缓存资源统计文本
	private var _lastAssetQueryTime:Float = 0;   // 上次资源查询时间戳

	public function new(x:Float = 10, y:Float = 10, color:flixel.util.FlxColor = 0xFF000000)
	{
		super();

		// 创建背景
		bgSprite = new Sprite();
		addChild(bgSprite);

		// 创建单个文本字段，显示所有信息
		allInfoText = createTextField(ClientPrefs.data.fpsFontSize, ClientPrefs.data.fpsColor);
		addChild(allInfoText);

		// 创建原版 Debug 面板（默认隐藏，fpsStyle == "Debug" 时显示）
		debugDisplay = new FunkinDebugDisplay(10, 10);
		debugDisplay.visible = false;
		addChild(debugDisplay);

		// 创建原版 Psych 风格实例（初始隐藏，fpsStyle == "Psych" 时显示）
		psychInstance = new PsychFPSCounter(x, y, 0xFFFFFF);
		psychInstance.visible = (ClientPrefs.data.fpsStyle == "Psych");
		addChild(psychInstance);

		#if !officialBuild
		if (LimeSystem.platformName == LimeSystem.platformVersion || LimeSystem.platformVersion == null)
			os = 'OS: ${LimeSystem.platformName}' #if cpp + ' ${getArch() != 'Unknown' ? getArch() : ''}' #end;
		else
			os = 'OS: ${LimeSystem.platformName}' #if cpp + ' ${getArch() != 'Unknown' ? getArch() : ''}' #end + ' - ${LimeSystem.platformVersion}';
		#end

		positionFPS(x, y);

		// 初始化环形 FPS 缓冲区
		ringTimes = [];
		for (i in 0...RING_SIZE) ringTimes.push(0);
		ringWrite = 0;
		ringCount = 0;

		lastFramerateUpdateTime = Timer.stamp();
		prevTime = Lib.getTimer();
		updateTime = prevTime + 500;
		framesCount = 0;
		currentTime = 0;
		cacheCount = 0;

		// 初始化时间戳
		lastFpsUpdateTime = Timer.stamp();
		_lastMemQueryTime = Timer.stamp();
	}

	private function createTextField(size:Int, color:flixel.util.FlxColor, bold:Bool = false):TextField
	{
		var tf = new TextField();
		tf.selectable = false;
		tf.mouseEnabled = false;
		tf.defaultTextFormat = new TextFormat(fontName, size, (color.red << 16) | (color.green << 8) | color.blue, bold);
		tf.autoSize = LEFT;
		return tf;
	}

	public dynamic function updateText():Void
	{
		// Psych 原版风格：委托给 PsychFPSCounter（自己有节流）
		if (ClientPrefs.data.fpsStyle == "Psych")
		{
			psychInstance.visible = true;
			allInfoText.visible = false;
			bgSprite.visible = false;
			if (debugDisplay != null) debugDisplay.visible = false;
			return;
		}
		else if (psychInstance != null)
		{
			psychInstance.visible = false;
		}

		// 原版 FunkinDebugDisplay 风格：完全交给独立面板渲染
		if (ClientPrefs.data.fpsStyle == "V-Slice")
		{
			bgSprite.visible = false;
			allInfoText.visible = false;
			debugDisplay.visible = true;
			return;
		}
		else if (debugDisplay != null)
		{
			debugDisplay.visible = false;
		}

		// 切回 Kathy / Simple 时，需把文本与背景重新显示（之前切到 V-Slice 时被隐藏）
		allInfoText.visible = true;
		bgSprite.visible = true;

		// Simple/Leather 模式：使用 _sans 字体，简洁格式（与 SimpleInfoDisplay 一致）
		if (ClientPrefs.data.fpsStyle == "Simple")
		{
			var memory:Float = getMemoryCached();
			if (memory > memoryPeakMegas) memoryPeakMegas = memory;

			var textLines:Array<String> = [];

			if (ClientPrefs.data.simpleInfoShowFPS) textLines.push(currentFPS + " fps" + gcStateLabel());
			if (ClientPrefs.data.simpleInfoShowMem) textLines.push(formatSimpleMemory(memory) + " / " + formatSimpleMemory(memoryPeakMegas));
			var batteryInfo:String = MobileUtil.getBatteryText();
			if (batteryInfo.length > 0) textLines.push(batteryInfo);
			if (ClientPrefs.data.simpleInfoShowVersion)
			{
				var version:String = getCachedVersion();
				textLines.push("v" + version);
			}

			var allText = textLines.join('\n');

			// ---- 内容没变化就跳过 ----
			if (allText == _lastSimpleText && !simpleFormatChanged())
			{
				bgSprite.visible = false;
				return;
			}
			_lastSimpleText = allText;

			// 颜色（Simple 模式使用自己的颜色设置）
			var simpleColorInt = (ClientPrefs.data.simpleInfoColor.red << 16) | (ClientPrefs.data.simpleInfoColor.green << 8) | ClientPrefs.data.simpleInfoColor.blue;
			var colorHex = StringTools.hex(simpleColorInt, 6);
			allInfoText.htmlText = '<font color="#$colorHex">$allText</font>';

			// _sans 字体和字号（Simple 模式使用系统 _sans 字体，而非 vcr.ttf）
			applyTextFormatIfChanged("_sans", ClientPrefs.data.simpleInfoFontSize, simpleColorInt, false);

			// 隐藏背景（Simple 模式没有背景）
			bgSprite.visible = false;
			this.alpha = 1;

			return;
		}

		// Kathy 风格：详细信息
		var memory:Float = getMemoryCached();

		// 更新内存峰值
		if (memory > memoryPeakMegas)
		{
			memoryPeakMegas = memory;
		}

		// 构建所有信息的文本 - 使用数组避免多余空行
		var textLines:Array<String> = [];

		// FPS信息 - 根据设置显示（附带原生GC开关状态标记）
		if (ClientPrefs.data.fpsShowFPS) textLines.push('FPS: $currentFPS ${gcStateLabel()}');
		if (ClientPrefs.data.fpsShowDelay) textLines.push('Delay: ${currentDelay}ms');
		if (ClientPrefs.data.fpsShowRAM) textLines.push('RAM: ${formatMemory(memory)}');
		if (ClientPrefs.data.fpsShowMemPeak) textLines.push('MEM Peak: ${formatMemory(memoryPeakMegas)}');
		if (ClientPrefs.data.fpsShowObjects) textLines.push('Objects: $objectCount');
		var batteryInfo:String = MobileUtil.getBatteryText();
		if (batteryInfo.length > 0) textLines.push(batteryInfo);

		#if debug
		// 资源缓存 / 内嵌统计（仅 Kathy 详细模式 + debug 构建显示）
		try
		{
			var assetInfo = getAssetDebugText();
			for (line in assetInfo.split('\n')) textLines.push(line);
		}
		catch (e:Dynamic) {}
		#end
		
		// 版本信息
		if (ClientPrefs.data.exgameversion)
		{
			textLines.push('');
			textLines.push('Psych ${MainMenuState.psychEngineVersion}');
			textLines.push('Kathy ${MainMenuState.kathyEngineVersion}');
			textLines.push('Commit: ${GameVersion.getGitCommitCount()} (${GameVersion.getGitCommitHash()})');
			textLines.push('Build: ${GameVersion.getBuildTime()}');
		}
		
		// 显示haxelib信息 - 独立于版本信息
		if (ClientPrefs.data.showHaxelibs)
		{
			textLines.push('');
			textLines.push('Libs:');
			textLines.push(HaxelibInfo.getHaxelibInfo());
		}

		// 显示操作系统信息
		if (ClientPrefs.data.showRunningOS)
		{
			textLines.push('');
			textLines.push(os);
		}

		// 系统信息 - 只有当显示版本信息或者显示haxelib或者显示操作系统信息时才添加
		if (ClientPrefs.data.exgameversion || ClientPrefs.data.showHaxelibs || ClientPrefs.data.showRunningOS)
		{
			var hasSystemInfo = false;
			var lastWasBlank:Bool = textLines.length > 0 && textLines[textLines.length - 1] == '';

			// 平台信息
			if (ClientPrefs.data.fpsShowPlatform)
			{
				if (!hasSystemInfo && !lastWasBlank)
				{
					textLines.push('');
					lastWasBlank = true;
					hasSystemInfo = true;
				}
				else
				{
					hasSystemInfo = true;
				}
				#if cpp
				var arch = getArch() != 'Unknown' ? ' (${getArch()})' : '';
				#else
				var arch = '';
				#end
				textLines.push('Platform: ${LimeSystem.platformName}$arch');
				lastWasBlank = false;
			}

			// 平台版本
			if (ClientPrefs.data.fpsShowOSVersion)
			{
				if (LimeSystem.platformVersion != null && LimeSystem.platformVersion != LimeSystem.platformName)
				{
					if (!hasSystemInfo && !lastWasBlank)
					{
						textLines.push('');
						lastWasBlank = true;
						hasSystemInfo = true;
					}
					else
					{
						hasSystemInfo = true;
					}
					textLines.push('OS Ver.: ${LimeSystem.platformVersion}');
					lastWasBlank = false;
				}
			}

			// 显示器信息
			try
			{
				var display = LimeSystem.getDisplay(0);
				if (display != null)
				{
					if (ClientPrefs.data.fpsShowResolution)
					{
						if (!hasSystemInfo && !lastWasBlank)
						{
							textLines.push('');
							lastWasBlank = true;
							hasSystemInfo = true;
						}
						else
						{
							hasSystemInfo = true;
						}
						textLines.push('Resolution: ${display.currentMode.width}x${display.currentMode.height}');
						lastWasBlank = false;
					}

					if (ClientPrefs.data.fpsShowRefreshRate)
					{
						if (!hasSystemInfo && !lastWasBlank)
						{
							textLines.push('');
							lastWasBlank = true;
							hasSystemInfo = true;
						}
						else
						{
							hasSystemInfo = true;
						}
						textLines.push('Refresh: ${display.currentMode.refreshRate}Hz');
						lastWasBlank = false;
					}
				}
			}
			catch (e:Dynamic)
			{
			}
		}

		// 移除末尾的空行
		while (textLines.length > 0 && textLines[textLines.length - 1] == '')
		{
			textLines.pop();
		}

		var allText = textLines.join('\n');

		// 转换颜色为十六进制字符串
		var colorHex = StringTools.hex((ClientPrefs.data.fpsColor.red << 16) | (ClientPrefs.data.fpsColor.green << 8) | ClientPrefs.data.fpsColor.blue, 6);
		var htmlText = '<font color="#$colorHex">$allText</font>';

		// ---- 内容没变化就跳过 TextField 更新 + TextFormat + Background ----
		if (htmlText == _lastHtmlText && !kathyFormatChanged())
		{
			this.alpha = ClientPrefs.data.fpsOpacity;
			return;
		}
		_lastHtmlText = htmlText;
		allInfoText.htmlText = htmlText;
		
		applyTextFormatIfChanged(fontName, ClientPrefs.data.fpsFontSize, (ClientPrefs.data.fpsColor.red << 16) | (ClientPrefs.data.fpsColor.green << 8) | ClientPrefs.data.fpsColor.blue, false);
		
		// 更新透明度
		this.alpha = ClientPrefs.data.fpsOpacity;
		
		// 更新背景（尺寸变化时才重绘）
		updateBackground();
	}

	/** 生成 TextFormat 的 hash，用来检测设置是否变了 */
	inline private function computeFormatHash(name:String, size:Int, color:Int, bold:Bool):Int
	{
		var h:Int = (name == null ? 0 : name.length * 17 + Std.int(name.charCodeAt(0)));
		h = h ^ size ^ color;
		if (bold) h = h ^ 1;
		return h;
	}

	private function applyTextFormatIfChanged(name:String, size:Int, color:Int, bold:Bool):Void
	{
		var h = computeFormatHash(name, size, color, bold);
		if (h == _lastTextFormatHash) return;
		_lastTextFormatHash = h;
		allInfoText.defaultTextFormat = new TextFormat(name, size, color, bold);
	}

	private function simpleFormatChanged():Bool
	{
		var desiredColor = (ClientPrefs.data.simpleInfoColor.red << 16) | (ClientPrefs.data.simpleInfoColor.green << 8) | ClientPrefs.data.simpleInfoColor.blue;
		var h = computeFormatHash("_sans", ClientPrefs.data.simpleInfoFontSize, desiredColor, false);
		return h != _lastTextFormatHash;
	}

	private function kathyFormatChanged():Bool
	{
		var desiredColor = (ClientPrefs.data.fpsColor.red << 16) | (ClientPrefs.data.fpsColor.green << 8) | ClientPrefs.data.fpsColor.blue;
		var h = computeFormatHash(fontName, ClientPrefs.data.fpsFontSize, desiredColor, false);
		return h != _lastTextFormatHash;
	}
	
	private function updateBackground():Void
	{
		// Psych 模式下重新显示背景
		bgSprite.visible = true;

		// 计算目标尺寸，如果没变就跳过重绘
		var padding = ClientPrefs.data.fpsBgPadding;
		var w = allInfoText.width + padding * 2;
		var h = allInfoText.height + padding * 2;

		if (ClientPrefs.data.fpsBgEnabled && w == _lastBgWidth && h == _lastBgHeight)
		{
			return; // 尺寸没变，没必要重绘 Graphics
		}
		_lastBgWidth = w;
		_lastBgHeight = h;

		bgSprite.graphics.clear();
		
		if (ClientPrefs.data.fpsBgEnabled)
		{
			var bgColorInt = (ClientPrefs.data.fpsBgColor.red << 16) | (ClientPrefs.data.fpsBgColor.green << 8) | ClientPrefs.data.fpsBgColor.blue;
			bgSprite.graphics.beginFill(bgColorInt, ClientPrefs.data.fpsBgOpacity);
			bgSprite.graphics.drawRect(-padding, -padding, w, h);
			bgSprite.graphics.endFill();
		}
	}

	// 重新应用所有设置
	public function applySettings():Void
	{
		// ---- 重置缓存，让下一次 updateText 一定刷新 ----
		_lastHtmlText = null;
		_lastSimpleText = null;
		_lastTextFormatHash = -1;
		_lastBgWidth = -1;
		_lastBgHeight = -1;
		_lastVersionStr = null;
		_lastMemQueryTime = 0;
		_cachedAssetText = null;
		_lastAssetQueryTime = 0;

		// 若切换到 Psych 模式，重建 psychInstance 以应用新位置
		if (ClientPrefs.data.fpsStyle == "Psych" && psychInstance != null)
		{
			removeChild(psychInstance);
			psychInstance = new PsychFPSCounter(10, 3, 0xFFFFFF);
			addChild(psychInstance);
		}

		updateText();
		positionFPS(x, y);

		// Debug 风格需要重建面板以吸收新增设定
		if (ClientPrefs.data.fpsStyle == "V-Slice" && debugDisplay != null)
		{
			debugDisplay.mode = ClientPrefs.data.fpsDebugMode;
			debugDisplay.applySettings();
			updateDebugPosition();
		}
	}

	// ============ 原版 FunkinDebugDisplay 风格 ============

	/**
	 * 独立开关+热键：在 Off / Simple / Advanced 之间循环当前 Debug 面板模式。
	 * 仅当 fpsStyle 为 "V-Slice" 时生效。
	 */
	public function cycleDebugMode():Void
	{
		if (ClientPrefs.data.fpsStyle != "V-Slice") return;

		var modes:Array<String> = ["Off", "Simple", "Advanced"];
		var i:Int = modes.indexOf(ClientPrefs.data.fpsDebugMode);
		if (i < 0) i = 0;
		ClientPrefs.data.fpsDebugMode = modes[(i + 1) % modes.length];
		ClientPrefs.saveSettings();
		applySettings();
	}

	/**
	 * 手动设置 Debug 面板模式（供设置界面使用）。
	 */
	public function setDebugMode(mode:String):Void
	{
		if (ClientPrefs.data.fpsDebugMode != mode)
		{
			ClientPrefs.data.fpsDebugMode = mode;
			ClientPrefs.saveSettings();
			applySettings();
		}
	}

	function updateDebugPosition():Void
	{
		if (debugDisplay != null)
		{
			var scale:Float = 1;
			debugDisplay.setScaleFactor(scale);
			debugDisplay.reposition(ClientPrefs.data.fpsPosition, ClientPrefs.data.fpsSpacing);
		}
	}

	private override function __enterFrame(deltaTime:Float):Void
	{
		if (!visible)
			return;

		// Psych 原版风格：显式驱动 psychInstance（引擎不自动向子节点传递 __enterFrame）
		if (ClientPrefs.data.fpsStyle == "Psych")
		{
			if (psychInstance != null) psychInstance.__enterFrame(deltaTime);
			return;
		}

		// 原版 Debug(V-Slice) 风格：本类覆写了 __enterFrame 且不调用 super，
		// OpenFL 不会把帧回调链式传到子面板，故这里显式驱动 debugDisplay 刷新。
		if (ClientPrefs.data.fpsStyle == "V-Slice")
		{
			if (debugDisplay != null) debugDisplay.step(deltaTime);
			return;
		}

		// 限制 Delay 更新频率为每 0.2 秒
		if (Timer.stamp() - lastDelayUpdateTime > 0.2)
		{
			// 更新延迟时间（以毫秒为单位）
			currentDelay = Math.round(deltaTime * 1000) / 1000;
			lastDelayUpdateTime = Timer.stamp();
		}

		// ---- 环形 FPS 计数：O(1) 写入，消除 shift ----
		currentTime += deltaTime;
		ringTimes[ringWrite] = currentTime;
		ringWrite = (ringWrite + 1) % RING_SIZE;
		if (ringCount < RING_SIZE) ringCount++;

		// 只在显示更新时更新 FPS 值，避免数值跳动
		// Simple 模式 0.1s，其他 0.5s
		var updateInterval:Float = (ClientPrefs.data.fpsStyle == "Simple") ? 0.1 : 0.5;
		if (Timer.stamp() - lastFpsUpdateTime > updateInterval)
		{
			// 从环形缓冲里数最近 1 秒内有多少帧
			var cutoff = currentTime - 1000;
			var count:Int = 0;
			for (i in 0...ringCount)
			{
				var idx = (ringWrite - 1 - i + RING_SIZE) % RING_SIZE;
				if (ringTimes[idx] >= cutoff) count++;
				else break;
			}
			currentFPS = Math.round((count + cacheCount) / 2);
			cacheCount = count;
			lastFpsUpdateTime = Timer.stamp();
			updateText();
		}

		// ---- 只在玩家开了 Objects 显示时才遍历 ----
		if (ClientPrefs.data.fpsShowObjects && Timer.stamp() - lastObjectCountUpdate > 2.0)
		{
			objectCount = countObjects(FlxG.state);
			lastObjectCountUpdate = Timer.stamp();
		}

		if (ClientPrefs.data.fpsRework)
		{
			if (FlxG.stage.window.frameRate != ClientPrefs.data.framerate && FlxG.stage.window.frameRate != FlxG.game.focusLostFramerate)
				FlxG.stage.window.frameRate = ClientPrefs.data.framerate;

			var nowTime = openfl.Lib.getTimer();
			framesCount++;

			if (nowTime >= updateTime)
			{
				framesCount = 0;
				prevTime = nowTime;
				updateTime = nowTime + 500;
			}
		}
	}

	private function countObjects(state:FlxState, depth:Int = 0):Int
	{
		if (depth > 10)
			return 0;

		var count:Int = 0;

		if (state == null)
			return 0;

		count += countGroupMembers(state.members, depth + 1);

		if (state.subState != null)
		{
			count += countGroupMembers(state.subState.members, depth + 1);
		}

		return count;
	}

	private function countGroupMembers(members:Array<flixel.FlxBasic>, depth:Int = 0):Int
	{
		if (depth > 10)
			return 0;

		var count:Int = 0;

		if (members == null)
			return 0;

		for (member in members)
		{
			if (member != null && member.exists)
			{
				count++;

				if (Std.isOfType(member, flixel.group.FlxGroup.FlxTypedGroup))
				{
					var group:flixel.group.FlxGroup.FlxTypedGroup<flixel.FlxBasic> = cast member;
					count += countGroupMembers(group.members, depth + 1);
				}
			}
		}

		return count;
	}

	// ---- 节流的资源统计（每 2 秒刷新一次，内嵌资源量基本不变，缓存量随游戏过程变化） ----

	// Haxe Map 没有 .length，用迭代器遍历取长度
	inline private function mapLen<K, V>(m:Map<K, V>):Int
	{
		var n:Int = 0;
		if (m != null) for (_ in m) n++;
		return n;
	}

	private function getAssetDebugText():String
	{
		var now = Timer.stamp();
		if (now - _lastAssetQueryTime < 2.0 && _cachedAssetText != null)
			return _cachedAssetText;
		_lastAssetQueryTime = now;

		var oflBmp:Int = 0, oflFont:Int = 0, oflSnd:Int = 0;
		var flxCache:Int = 0;
		var limeImg:Int = 0, limeAudio:Int = 0, limeFont:Int = 0;
		var embImg:Int = 0, embSnd:Int = 0, embFont:Int = 0, embBin:Int = 0, embMClip:Int = 0;

		// OpenFL 运行时缓存（AssetCache 有公开的 Map 字段，IAssetCache 接口则没有 length）
		try
		{
			var c:AssetCache = cast Assets.cache;
			if (c != null)
			{
				oflBmp  = mapLen(c.bitmapData);
				oflFont = mapLen(c.font);
				oflSnd  = mapLen(c.sound);
			}
		}
		catch (e:Dynamic) {}

		// Flixel FlxGraphic 缓存（_cache 是 BitmapFrontEnd 的私有字段，需 privateAccess）
		try
		{
			@:privateAccess
			var flxC:Int = mapLen(flixel.FlxG.bitmap._cache);
			flxCache = flxC;
		}
		catch (e:Dynamic) {}

		#if lime
		// Lime 底层缓存（image/audio/font Map）
		try
		{
			limeImg   = mapLen(lime.utils.Assets.cache.image);
			limeAudio = mapLen(lime.utils.Assets.cache.audio);
			limeFont  = mapLen(lime.utils.Assets.cache.font);
		}
		catch (e:Dynamic) {}
		#end

		// 内嵌资源总量（编译时打包进可执行文件的，运行时基本不变）
		try { embImg   = Assets.list(AssetType.IMAGE).length;      } catch (e:Dynamic) {}
		try { embSnd   = Assets.list(AssetType.SOUND).length;      } catch (e:Dynamic) {}
		try { embFont  = Assets.list(AssetType.FONT).length;       } catch (e:Dynamic) {}
		try { embBin   = Assets.list(AssetType.BINARY).length;     } catch (e:Dynamic) {}
		try { embMClip = Assets.list(AssetType.MOVIE_CLIP).length; } catch (e:Dynamic) {}

		var embTotal:Int = embImg + embSnd + embFont + embBin + embMClip;

		// 组装两行文本：缓存一行 + 内嵌一行
		var cacheParts:Array<String> = [];
		cacheParts.push('OFL ${oflBmp}/${oflFont}/${oflSnd}');
		cacheParts.push('Flx ${flxCache}');
		#if lime
		cacheParts.push('Lime ${limeImg}/${limeAudio}/${limeFont}');
		#end
		var cacheLine = 'Cache: ' + cacheParts.join(' | ');

		var embParts:Array<String> = [];
		embParts.push('IMG ${embImg}');
		embParts.push('SND ${embSnd}');
		if (embFont > 0)  embParts.push('FNT ${embFont}');
		if (embBin > 0)   embParts.push('BIN ${embBin}');
		if (embMClip > 0) embParts.push('MCLIP ${embMClip}');
		var embLine = 'Embedded: ' + embParts.join(' ') + '  (${embTotal})';

		_cachedAssetText = cacheLine + '\n' + embLine;
		return _cachedAssetText;
	}

	// ---- 节流的内存查询 ----
	private function getMemoryCached():Float
	{
		var now = Timer.stamp();
		if (now - _lastMemQueryTime < 0.5) // 0.5 秒更新一次
		{
			// 即使在 Simple 模式也返回缓存值（Simple 用 Simple 格式）
			return _cachedMemMegas;
		}
		_lastMemQueryTime = now;

		#if cpp
		try
		{
			var memValue:Dynamic = cpp.vm.Gc.memInfo64(cpp.vm.Gc.MEM_INFO_USAGE);
			if (Std.is(memValue, Float) || Std.is(memValue, Int))
			{
				var mem:Float = cast memValue;
				if (Math.isFinite(mem) && mem >= 0)
				{
					_cachedMemMegas = mem;
					return mem;
				}
			}
		}
		catch (e:Dynamic) {}

		try
		{
			var memValue:Dynamic = cpp.vm.Gc.memInfo(cpp.vm.Gc.MEM_INFO_USAGE);
			if (Std.is(memValue, Float) || Std.is(memValue, Int))
			{
				var mem:Float = cast memValue;
				if (Math.isFinite(mem) && mem >= 0)
				{
					_cachedMemMegas = mem;
					return mem;
				}
			}
		}
		catch (e:Dynamic) {}
		#end

		_cachedMemMegas = 0;
		return 0;
	}

	function get_memoryMegas():Float
	{
		return _cachedMemMegas;
	}

	/** 缓存版本字符串（统一读 MainMenuState.kathyEngineVersion，带 rc/beta 后缀） */
	inline private function getCachedVersion():String
	{
		if (_lastVersionStr != null) return _lastVersionStr;
		var v:String = MainMenuState.kathyEngineVersion;
		if (v == null) v = "0.0.0";
		_lastVersionStr = v;
		return v;
	}

	// 原生GC开关状态标记：仅当关闭时在 FPS 行显示 "NO GC" 提示
	inline function gcStateLabel():String
	{
		return (ClientPrefs.data != null && !ClientPrefs.data.garbageCollectorEnabled) ? "(No GC)" : "";
	}

	public inline function positionFPS(X:Float, Y:Float, ?scale:Float = 1)
	{
		scaleX = scaleY = #if android (scale > 1 ? scale : 1) #else (scale < 1 ? scale : 1) #end;

		var spacing = ClientPrefs.data.fpsSpacing;

		// 原版 Debug 风格：面板按自身尺寸贴边
		if (ClientPrefs.data.fpsStyle == "V-Slice")
		{
			updateDebugPosition();
			return;
		}

		var isRight = ClientPrefs.data.fpsPosition.indexOf("RIGHT") != -1;
		var isBottom = ClientPrefs.data.fpsPosition.indexOf("BOTTOM") != -1;

		// 使用 OpenFL stage 坐标系而非 FlxG.game
		var stage = Lib.current.stage;
		if (stage != null)
		{
			if (isRight)
			{
				x = stage.stageWidth - 200 - spacing;
			}
			else
			{
				x = spacing;
			}

			if (isBottom)
			{
				var textHeight = allInfoText.height;
				y = stage.stageHeight - textHeight - spacing;
			}
			else
			{
				y = spacing;
			}
		}
	}

	#if cpp
	#if windows
	private function getArch():String
	{
		@:functionCode('
        SYSTEM_INFO osInfo;
        GetSystemInfo(&osInfo);
        switch(osInfo.wProcessorArchitecture)
        {
            case 9: return ::String("x86_64");
            case 5: return ::String("ARM");
            case 12: return ::String("ARM64");
            case 6: return ::String("IA-64");
            case 0: return ::String("x86");
            default: return ::String("Unknown");
        }
    ')
		return "Unknown";
	}
	#elseif (ios || mac)
	private function getArch():String
	{
		@:functionCode('
        const NXArchInfo *archInfo = NXGetLocalArchInfo();
        return ::String(archInfo == NULL ? "Unknown" : archInfo->name);
    ')
		return "Unknown";
	}
	#else
	private function getArch():String
	{
		@:functionCode('
        struct utsname osInfo{};
        uname(&osInfo);
        return ::String(osInfo.machine);
    ')
		return "Unknown";
	}
	#end
	#else
	private function getArch():String
	{
		var platform = LimeSystem.platformName;
		if (platform != null && (platform.indexOf("x86_64") >= 0 || platform.indexOf("arm64") >= 0 || platform.indexOf("ARM64") >= 0))
			return platform;
		return "Unknown";
	}
	#end

	/**
	 * 格式化内存显示，根据设置决定是否强制显示MB
	 */
	private function formatMemory(memoryInBytes:Float):String
	{
		if (memoryInBytes < 0 || memoryInBytes != memoryInBytes)
		{
			memoryInBytes = 0;
		}

		if (ClientPrefs.data.fpsForceMB)
		{
			var memoryInMB = memoryInBytes / (1024 * 1024);
			return Std.string(Math.round(memoryInMB)) + "MB";
		}

		try
		{
			return flixel.util.FlxStringUtil.formatBytes(memoryInBytes);
		}
		catch (e:Dynamic)
		{
			var memoryInMB = memoryInBytes / (1024 * 1024);
			return Std.string(Math.round(memoryInMB)) + "MB";
		}
	}

	/**
	 * Simple/Leather 模式的内存格式化：MB/GB 自动切换，保留两位小数
	 */
	private function formatSimpleMemory(memoryInBytes:Float):String
	{
		if (memoryInBytes < 0 || memoryInBytes != memoryInBytes) memoryInBytes = 0;

		var memoryInMB:Float = memoryInBytes / (1024 * 1024);

		if (memoryInMB < 1024)
			return Math.round(memoryInMB * 100) / 100 + "MB";
		else
			return Math.round((memoryInMB / 1024) * 100) / 100 + "GB";
	}
}
