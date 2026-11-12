package backend;

import openfl.events.UncaughtErrorEvent;
import openfl.events.ErrorEvent;
import openfl.events.Event;
import openfl.errors.Error;
import debug.CrashOverlay;
#if sys
import sys.FileSystem;
import sys.io.File;
#end

using StringTools;

/**
 * Crash Handler（可恢复版 / 防卡死）。
 *
 * 原版行为：捕获未捕获异常 -> 写 logs/ 文件 -> 弹**系统原生**对话框 -> System.exit(1) 直接退出。
 * 现改为：捕获异常 -> 写 logs/ 文件 -> 推入游戏日志窗口 -> 在**游戏内（OpenFL 层）**显示错误弹层，
 *         绝不主动退出；由用户在弹层里选择「继续并恢复 / 返回主菜单 / 重启应用」。
 *
 * ★ 防卡死的关键设计（曾出现「游戏未响应」）：
 *  - **未捕获异常回调里只做最少的事**：preventDefault + 记录 message/stack 到静态字段。
 *    绝不在此处操作显示列表、写文件、改 flixel 状态机 —— 异常栈中任一步再抛错都会
 *    递归重入异常处理器，导致主线程卡死（Windows 显示「未响应」+ 窗口泛白）。
 *  - 所有重活（节流、写文件、推日志、暂停、显示弹层）延迟到**正常帧**执行：
 *    stage 的 ENTER_FRAME 监听 + haxe.Timer 双保险，并用 _processing 做重入保护。
 *  - 处理过程若再次异常，catch 里强制 resumeGameImpl()，绝不让游戏停在暂停态。
 *  - 暂停使用 `FlxG.vcr.paused`（由 Main.hx 注入），不用 `FlxG.state.active=false`：
 *    后者会让 FlxGame.update() 首行直接 return，连带把其后的 switchState() 永久挂起。
 *    vcr.paused 在 _nextState != null 时仍允许执行状态切换。
 *
 * 其他设计：
 *  - `e.preventDefault()` 阻止 Lime 默认的崩溃/退出行为，保留；不再 stopImmediatePropagation，
 *    避免干扰 Lime 内部的异常派发/清理链。
 *  - 节流去重：同一错误（签名 = 消息 + 堆栈前 200 字）在 2.5s 窗口内合并计数。
 *  - 崩溃文件写入 logs/，与日志导出的 logs/output/ 同属一个 logs 文件夹。
 *  - 重启应用：Android 走 MobileBridge.restartApp() JNI；桌面拉起新进程；其余降级回主菜单。
 *
 * @author YoshiCrafter29, Ne_Eo, MAJigsaw77 and Homura Akemi (HomuHomu833)
 */
class CrashHandler
{
	// ---- 待处理队列：异常回调只写这里，重活一律延迟到正常帧 ----
	private static var _pending:Bool = false;
	private static var _pendingMsg:String = "";
	private static var _pendingStack:String = "";
	private static var _queuedCount:Int = 0;
	private static var _processing:Bool = false;
	private static var _pumpAttached:Bool = false;

	// ---- 节流去重 ----
	private static var _lastSig:String = "";
	private static var _lastTime:Float = 0;
	private static var _repeatCount:Int = 0;
	private static inline var THROTTLE_SEC:Float = 2.5;
	private static var _logFileWritten:Bool = false;
	private static var _pauseDisabled:Bool = false;      // 安全阀：暂停无效时自动降级
	private static var _errorsWhilePaused:Int = 0;
	private static inline var MAX_ERRORS_WHILE_PAUSED:Int = 12;

	// 用户点过弹层按钮后的静默期：切状态 / 恢复音乐时常见的连锁异常只记录、不再弹层，
	// 否则会出现「点一次关掉、下一帧又被拉回来，要再点一下」的观感。
	private static var _dismissUntil:Float = 0;
	// 0.2s ≈ 60fps 下 12 帧：足够吃掉切状态 / 恢复音乐那一两帧的连锁异常，
	// 又不会把真正的新错误压太久
	private static inline var DISMISS_COOLDOWN_SEC:Float = 0.2;

	/** 由 Main.hx 注入（CrashHandler 不直接依赖 flixel / states，便于独立编译验证）。 */
	public static var gotoTitleImpl:()->Void = null;
	public static var pauseGameImpl:()->Void = null;
	public static var resumeGameImpl:()->Void = null;
	/** 由 Main.hx 注入：终止所有在播放的音频（回主菜单 / 重启应用前调用）。 */
	public static var stopAllAudioImpl:()->Void = null;
	/** 由 Main.hx 注入：弹层期间切到系统光标 / 关闭后恢复游戏原本的光标设置。 */
	public static var showCursorImpl:()->Void = null;
	public static var restoreCursorImpl:()->Void = null;

	public static function init():Void
	{
		openfl.Lib.current.loaderInfo.uncaughtErrorEvents.addEventListener(UncaughtErrorEvent.UNCAUGHT_ERROR, onUncaughtError);
		#if cpp
		untyped __global__.__hxcpp_set_critical_error_handler(onError);
		#elseif hl
		hl.Api.setErrorHandler(onError);
		#end

		// 独立于 flixel 的帧泵：保证错误在「正常帧」里被处理，而非异常栈中
		attachFramePump();

		CrashOverlay.onContinue = function()
		{
			// 「继续游戏」= 恢复更新，回到游戏（异常可能再次出现，由弹层再次提示）
			callResume();
		};
		CrashOverlay.onDismiss = dismiss;
		CrashOverlay.onGotoTitle = gotoTitle;
		CrashOverlay.onRestartApp = restartApp;
	}

	// ------------------------------------------------------------------
	// 帧泵（正常帧处理）
	// ------------------------------------------------------------------
	private static function attachFramePump():Void
	{
		if (_pumpAttached) return;
		try
		{
			var stage = openfl.Lib.current.stage;
			if (stage != null)
				stage.addEventListener(Event.ENTER_FRAME, onFramePump);
			else
				// Lib.current 始终在显示列表上，同样会收到 ENTER_FRAME，且都在主线程
				openfl.Lib.current.addEventListener(Event.ENTER_FRAME, onFramePump);
			_pumpAttached = true;
		}
		catch (e:Dynamic)
		{
			trace('[CrashHandler] 帧泵注册失败: ' + Std.string(e));
		}
	}

	private static function onFramePump(_:Event):Void
	{
		// 帧泵没注册成功时，在任意一次 ENTER_FRAME 里补注册（仍在主线程，不用 Timer）
		if (!_pumpAttached) attachFramePump();
		runPending();
	}

	/** 统一的延迟处理器：重入保护 + 异常兜底强制恢复。 */
	private static function runPending():Void
	{
		if (!_pending || _processing) return;
		_processing = true;
		try
		{
			processError(_pendingMsg, _pendingStack, _queuedCount);
		}
		catch (e:Dynamic)
		{
			// 处理过程本身又抛错：强制恢复更新，绝不让游戏停在暂停态造成「卡死」
			trace('[CrashHandler] 处理错误时再次异常: ' + Std.string(e));
			callResume();
		}
		_pending = false;
		_queuedCount = 0;
		_processing = false;
	}

	// ------------------------------------------------------------------
	// 异常回调：极简，只记录
	// ------------------------------------------------------------------
	private static function queueError(message:String, stack:String):Void
	{
		if (_pending)
		{
			_queuedCount++; // 合并同一帧内的多次异常，不重复排队
			return;
		}
		_pendingMsg = message != null ? message : "Unknown error";
		_pendingStack = stack != null ? stack : "";
		_queuedCount = 1;
		_pending = true;
		// 由 stage/Lib.current 的 ENTER_FRAME 帧泵在下一正常帧处理（主线程，绝不用 Timer）
	}

	private static function onUncaughtError(e:UncaughtErrorEvent):Void
	{
		// 保留与原版一致的三连，阻止 Lime 默认退出与其它 listener 干扰
		try
		{
			e.preventDefault();
			e.stopPropagation();
			e.stopImmediatePropagation();
		}
		catch (x:Dynamic) {}

		var m:String = "Unknown error";
		var stack:String = "";
		try
		{
			var raw:Dynamic = e.error;
			if (Std.isOfType(raw, Error)) m = cast(raw, Error).message;
			else if (Std.isOfType(raw, ErrorEvent)) m = cast(raw, ErrorEvent).text;
			else if (raw != null) m = Std.string(raw);
		}
		catch (x:Dynamic) {}
		// exceptionStack 必须在异常栈里取（正常帧里取不到），但用 try/catch 全包，失败就留空
		try { stack = formatStack(haxe.CallStack.exceptionStack()); } catch (x:Dynamic) {}

		queueError(m, stack);
	}

	#if (cpp || hl)
	private static function onError(message:Dynamic):Void
	{
		var m:String = "Critical Error";
		var stack:String = "";
		try { if (message != null) m = Std.string(message); } catch (x:Dynamic) {}
		try { stack = haxe.CallStack.toString(haxe.CallStack.exceptionStack(true)); } catch (x:Dynamic) {}
		queueError(m, stack);
	}
	#end

	/** 正常帧里执行：节流 -> 写文件 -> 推日志 -> 暂停 -> 显示弹层。 */
	private static function processError(message:String, stack:String, queued:Int):Void
	{
		var now:Float = haxe.Timer.stamp();
		var sig:String = message + "|" + stack.substr(0, 200);
		var repeated:Bool = (sig == _lastSig) && ((now - _lastTime) < THROTTLE_SEC);
		var inc = queued > 0 ? queued : 1;
		if (repeated) _repeatCount += inc;
		else { _repeatCount = inc; _logFileWritten = false; }
		_lastSig = sig;
		_lastTime = now;

		#if sys
		if (!_logFileWritten)
		{
			saveErrorMessage('$message\n$stack');
			_logFileWritten = true;
		}
		#end

		if (!repeated)
		{
			try { if (Main.gameLogVar != null) Main.gameLogVar.addLogError(message, stack); }
			catch (e:Dynamic) {}
		}

		// 用户刚在弹层上做过选择：静默期内的连锁异常已经写文件 / 进日志窗口，
		// 但既不暂停也不再弹层，保证「点一次就能走」。静默期结束后恢复常规处理。
		if (haxe.Timer.stamp() < _dismissUntil) return;

		// 暂停游戏更新（在**正常帧**、而非异常栈里执行，避免重入卡死）
		// 安全阀：若暂停后同一错误仍持续复抛（说明暂停在该环境无效，例如异常来自
		// OpenFL 层而非 flixel update），则自动恢复更新并永久停用暂停，绝不把游戏冻死。
		if (repeated && !_pauseDisabled)
		{
			_errorsWhilePaused++;
			if (_errorsWhilePaused >= MAX_ERRORS_WHILE_PAUSED)
			{
				_pauseDisabled = true;
				callResume();
				trace('[CrashHandler] 暂停未能阻止异常，已自动恢复更新并停用暂停');
			}
		}
		if (!_pauseDisabled && pauseGameImpl != null && !repeated)
		{
			try { pauseGameImpl(); }
			catch (e:Dynamic) { trace('[CrashHandler] 暂停更新失败: ' + Std.string(e)); }
		}

		// 弹层是全屏 OpenFL 覆盖层，会盖住 flixel 的自定义光标；先切到系统光标
		if (showCursorImpl != null)
		{
			try { showCursorImpl(); } catch (e:Dynamic) {}
		}
		try { CrashOverlay.show(message, stack, _repeatCount); }
		catch (e:Dynamic)
		{
			trace('[CrashHandler] 无法显示游戏内错误弹层: ' + Std.string(e));
			trace('$message\n$stack');
			callResume();
			if (restoreCursorImpl != null) { try { restoreCursorImpl(); } catch (x:Dynamic) {} }
		}
	}

	// ------------------------------------------------------------------
	// 动作
	// ------------------------------------------------------------------
	private static function callResume():Void
	{
		if (resumeGameImpl == null) return;
		try { resumeGameImpl(); } catch (e:Dynamic) { trace('[CrashHandler] 恢复更新失败: ' + Std.string(e)); }
	}

	/** 终止所有在播放的音频；注入实现缺失或抛错都不影响后续流程。 */
	private static function callStopAllAudio():Void
	{
		if (stopAllAudioImpl == null) return;
		try { stopAllAudioImpl(); }
		catch (e:Dynamic) { trace('[CrashHandler] 停止音频失败: ' + Std.string(e)); }
	}

	/** 用户在弹层上作出选择（三个按钮都会先 hide()，由此触发）。
	 *  清掉积压异常 + 进入短暂静默期 + 恢复更新与鼠标，避免切状态的连锁异常把弹层拉回来。 */
	public static function dismiss():Void
	{
		_pending = false;
		_queuedCount = 0;
		_dismissUntil = haxe.Timer.stamp() + DISMISS_COOLDOWN_SEC;
		_lastSig = "";
		_repeatCount = 0;
		_errorsWhilePaused = 0;
		_logFileWritten = false;
		callResume();
		if (restoreCursorImpl != null)
		{
			try { restoreCursorImpl(); } catch (e:Dynamic) {}
		}
	}

	/** 回主菜单（软重启）：跨平台通用，进程不退出。实现由 Main.hx 注入。 */
	public static function gotoTitle():Void
	{
		callResume(); // 先恢复，确保任何待切换状态都能被处理
		// 必须在切换 state 之前主动停音频：FlxG.sound.music 是 persist=true，
		// FlxGame.switchState() 里的 FlxG.sound.destroy() 不会动它；且 vcr 暂停
		// 只停 Haxe 层 update，底层音频线程仍在播放。
		callStopAllAudio();
		if (gotoTitleImpl == null)
		{
			trace('[CrashHandler] 未注入 gotoTitleImpl，无法回主菜单');
			return;
		}
		try { gotoTitleImpl(); }
		catch (e:Dynamic) { trace('[CrashHandler] 回主菜单失败: ' + Std.string(e)); }
	}

	/** 重启应用：Android 走 MobileUtil 的 JNI；桌面拉起新进程；其余平台降级为回主菜单。 */
	public static function restartApp():Void
	{
		callResume();
		callStopAllAudio(); // 重启（或降级回主菜单）前立刻静音，避免残留音轨
		try
		{
			if (mobile.backend.MobileUtil.restartApp()) return;
		}
		catch (e:Dynamic)
		{
			trace('[CrashHandler] Android 重启调用失败: ' + Std.string(e));
		}

		#if (sys && !mobile)
		try
		{
			var exe:String = Sys.programPath();
			var args:Array<String> = Sys.args();
			new sys.io.Process(exe, args);
			lime.system.System.exit(0);
			return;
		}
		catch (e:Dynamic)
		{
			trace('[CrashHandler] 桌面重启失败，降级为回主菜单: ' + Std.string(e));
		}
		#end

		gotoTitle();
	}

	// ------------------------------------------------------------------
	// 工具
	// ------------------------------------------------------------------
	private static function formatStack(stack:Array<haxe.CallStack.StackItem>):String
	{
		var arr:Array<String> = [];
		for (item in stack)
		{
			switch (item)
			{
				case CFunction:
					arr.push("Non-Haxe (C) Function");
				case Module(c):
					arr.push('Module ${c}');
				case FilePos(parent, file, line, col):
					switch (parent)
					{
						case Method(cla, func):
							arr.push('${file.replace('.hx', '')}.$func() [line $line]');
						case _:
							arr.push('${file.replace('.hx', '')} [line $line]');
					}
				case LocalFunction(v):
					arr.push('Local Function ${v}');
				case Method(cl, m):
					arr.push('${cl} - ${m}');
			}
		}
		return arr.join('\n');
	}

	#if sys
	private static function saveErrorMessage(message:String):Void
	{
		final folder:String = #if android StorageUtil.getExternalStorageDirectory() + #else Sys.getCwd() + #end 'logs/';
		try
		{
			if (!FileSystem.exists(folder)) FileSystem.createDirectory(folder);
			File.saveContent(folder + 'crash_' + Date.now().toString().replace(' ', '-').replace(':', "'") + '.txt', message);
		}
		catch (e:haxe.Exception)
			trace('Couldn\'t save error message. (${e.message})');
	}
	#end
}
