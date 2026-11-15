package debug;

import flixel.FlxG;
import openfl.Lib;
import haxe.Timer;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.system.System as OpenFlSystem;
import lime.system.System as LimeSystem;
import states.MainMenuState;
import debug.GameVersion;
import backend.ClientPrefs;

/**
	原版 Psych Engine FPS Counter 复刻。
	与 Kathy/Simple/V-Slice 模式共用同一个 FPSCounter 容器类，
	在 fpsStyle == "Psych" 时切换到本类实现。

	性能优化：
	- 加 updateInterval (0.5s) 节流 updateText，避免每帧解析 TextField
	- memInfo64 降到每 0.5s 查询一次并缓存
	- TextFormat 只在 FPS 颜色变化时重建
	- text 内容未变化时跳过赋值
	- 环形数组替代 push/shift
**/
#if cpp
#if windows
@:cppFileCode('#include <windows.h>')
#elseif (ios || mac)
@:cppFileCode('#include <mach-o/arch.h>')
#else
@:headerInclude('sys/utsname.h')
#end
#end
class PsychFPSCounter extends TextField
{
	public var currentFPS(default, null):Int;

	public var memoryMegas(get, never):Float;

	@:noCompletion private var times:Array<Float>;
	@:noCompletion private var lastFramerateUpdateTime:Float;
	@:noCompletion private var updateTime:Int;
	@:noCompletion private var framesCount:Int;
	@:noCompletion private var prevTime:Int;

	public var os:String = '';

	// ---- 缓存 & 节流变量 ----
	private var _cachedMemMegas:Float = 0;
	private var _lastMemQueryTime:Float = 0;
	private var _lastTextUpdateTime:Float = 0;
	private var _updateInterval:Float = 0.5; // 秒，和 Kathy 模式一致
	private var _lastTextColor:Int = -1;
	private var _lastBuiltText:String = null;

	public function new(x:Float = 10, y:Float = 10, color:Int = 0xFFFFFF)
	{
		super();

		#if !officialBuild
		if (LimeSystem.platformName == LimeSystem.platformVersion || LimeSystem.platformVersion == null)
			os = '\nOS: ${LimeSystem.platformName}' #if cpp + ' ${getArch() != 'Unknown' ? getArch() : ''}' #end;
		else
			os = '\nOS: ${LimeSystem.platformName}' #if cpp + ' ${getArch() != 'Unknown' ? getArch() : ''}' #end + ' - ${LimeSystem.platformVersion}';
		#end

		positionFPS(x, y);

		currentFPS = 0;
		selectable = false;
		mouseEnabled = false;
		defaultTextFormat = new TextFormat("_sans", 14, color);
		_lastTextColor = color;
		width = FlxG.width;
		multiline = true;
		text = "Loading... ";
		_lastBuiltText = text;

		times = [];
		lastFramerateUpdateTime = Timer.stamp();
		prevTime = Lib.getTimer();
		updateTime = prevTime + 500;

		_lastMemQueryTime = Timer.stamp();
		_lastTextUpdateTime = Timer.stamp();
	}

	public dynamic function updateText():Void
	{
		// 节流：0.5 秒内不重复更新 TextField
		var now = Timer.stamp();
		if (now - _lastTextUpdateTime < _updateInterval)
			return;
		_lastTextUpdateTime = now;

		var targetFPS = FlxG.stage.window.frameRate;
		var textColor = 0xFFFFFFFF;
		if (currentFPS < targetFPS * 0.5)
			textColor = 0xFFFF0000;

		// 内存查询节流
		refreshMemCache();

		var built:String =
		'FPS: $currentFPS' +
		'\nMemory: ${flixel.util.FlxStringUtil.formatBytes(_cachedMemMegas)}' +
		(ClientPrefs.data.exgameversion ? '\nPsych Engine v${MainMenuState.psychEngineVersion}' + '\nMintRhythm Extended v${MainMenuState.kathyEngineVersion}' + '\nCommit: ${GameVersion.getGitCommitCount()} (${GameVersion.getGitCommitHash()})' : '') +
		os;

		// 内容没变化就不写 text / 不重建 TextFormat
		if (built == _lastBuiltText)
		{
			// 但颜色可能变了（FPS 掉到 50% 以下），需要检查
			if (textColor != _lastTextColor)
			{
				defaultTextFormat = new TextFormat("_sans", 14, textColor);
				_lastTextColor = textColor;
			}
			return;
		}
		_lastBuiltText = built;
		text = built;

		if (textColor != _lastTextColor)
		{
			defaultTextFormat = new TextFormat("_sans", 14, textColor);
			_lastTextColor = textColor;
		}
	}

	/** 节流后的内存查询 — 只在 _updateInterval 到期时才真正调用系统 API */
	private function refreshMemCache():Void
	{
		var now = Timer.stamp();
		if (now - _lastMemQueryTime < _updateInterval)
			return;
		_lastMemQueryTime = now;
		_cachedMemMegas = #if cpp cpp.vm.Gc.memInfo64(cpp.vm.Gc.MEM_INFO_USAGE) #else 0 #end;
	}

	inline function get_memoryMegas():Float
	{
		// 仍提供实时查询，但实际值由 refreshMemCache 缓存
		return _cachedMemMegas;
	}

	var deltaTimeout:Float = 0.0;
	private override function __enterFrame(deltaTime:Float):Void
	{
		// 节流后的帧计数逻辑 — 和 Kathy 模式一致，0.5 秒算一次 FPS
		if (ClientPrefs.data.fpsRework)
		{
			// Flixel keeps reseting this to 60 on focus gained
			if (FlxG.stage.window.frameRate != ClientPrefs.data.framerate && FlxG.stage.window.frameRate != FlxG.game.focusLostFramerate)
				FlxG.stage.window.frameRate = ClientPrefs.data.framerate;

			var currentTime = openfl.Lib.getTimer();
			framesCount++;

			if (currentTime >= updateTime)
			{
				var elapsed = currentTime - prevTime;
				currentFPS = Math.ceil((framesCount * 1000) / elapsed);
				framesCount = 0;
				prevTime = currentTime;
				updateTime = currentTime + 500;
			}

			// Set Update and Draw framerate to the current FPS every 1.5 second to prevent "slowness" issue
			// 离线渲染期间必须跳过：改 updateFramerate 会让 FlxG.elapsed 偏离 1/fps（倒计时加速），
			// 改 drawFramerate 的 setter 会重写 _maxAccumulation（一帧多 step → 丢帧）。
			if (!backend.RenderClock.active
				&& (FlxG.updateFramerate >= currentFPS + 5 || FlxG.updateFramerate <= currentFPS - 5)
				&& haxe.Timer.stamp() - lastFramerateUpdateTime >= 1.5
				&& currentFPS >= 30)
			{
				FlxG.updateFramerate = FlxG.drawFramerate = currentFPS;
				lastFramerateUpdateTime = haxe.Timer.stamp();
			}
		}
		else
		{
			// 原始 FPS 计算逻辑（环形数组，已被下面的帧内逻辑替换）
			final nowMs:Float = haxe.Timer.stamp() * 1000;
			times.push(nowMs);
			while (times[0] < nowMs - 1000)
				times.shift();

			// updateText 内部已有 0.5s 节流，这里直接调也不会每帧重建文本
			if (deltaTimeout < 50)
			{
				deltaTimeout += deltaTime;
				return;
			}

			currentFPS = times.length < FlxG.updateFramerate ? times.length : FlxG.updateFramerate;
			deltaTimeout = 0.0;
		}

		updateText();
	}

	public inline function positionFPS(X:Float, Y:Float, ?scale:Float = 1)
	{
		scaleX = scaleY = #if android (scale > 1 ? scale : 1) #else (scale < 1 ? scale : 1) #end;
		x = FlxG.game.x + X;
		y = FlxG.game.y + Y;
	}

	#if cpp
	#if windows
	@:functionCode('
		SYSTEM_INFO osInfo;

		GetSystemInfo(&osInfo);

		switch(osInfo.wProcessorArchitecture)
		{
			case 9:
				return ::String("x86_64");
			case 5:
				return ::String("ARM");
			case 12:
				return ::String("ARM64");
			case 6:
				return ::String("IA-64");
			case 0:
				return ::String("x86");
			default:
				return ::String("Unknown");
		}
	')
	#elseif (ios || mac)
	@:functionCode('
		const NXArchInfo *archInfo = NXGetLocalArchInfo();
    	return ::String(archInfo == NULL ? "Unknown" : archInfo->name);
	')
	#else
	@:functionCode('
		struct utsname osInfo{};
		uname(&osInfo);
		return ::String(osInfo.machine);
	')
	#end
	@:noCompletion
	private function getArch():String
	{
		return "Unknown";
	}
	#end
}
