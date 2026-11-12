package mobile.backend;

#if android
import lime._internal.backend.android.JNICache;
#end

/**
 * 原生能力封装（Toast / 电量 / 充电状态 / 常亮屏幕）。
 *
 * Android 走 project/android/jni 下的 MobileBridge.java；
 * 桌面等其它平台全部降级为无副作用的中性实现，保证同一套 Lua/HScript 脚本可跨平台运行。
 */
class MobileUtil
{
	static var _keepScreenOn:Bool = false;

	// 电量/充电缓存：避免每次 UI 刷新都走 JNI
	static var _batteryLevel:Int = -2;
	static var _charging:Bool = false;
	static var _chargingWatts:Float = -1;
	static var _batteryStamp:Float = -1000;
	static inline var BATTERY_CACHE_SECONDS:Float = 5;

	public static inline function isMobile():Bool
		return FlxG.onMobile;

	public static inline function getPlatform():String
		#if android
		return 'android';
		#elseif ios
		return 'ios';
		#elseif desktop
		return 'desktop';
		#else
		return 'unknown';
		#end

	/** 轻提示 */
	public static function toast(text:String, longDuration:Bool = false):Void
	{
		if (text == null)
			return;
		#if android
		JNICache.createStaticMethod('com/kathyengine/mobile/MobileBridge', 'toast', '(Ljava/lang/String;Z)V')(text, longDuration);
		#else
		trace('[Toast] $text');
		#end
	}

	// 5 秒缓存：UI 每帧/每秒调用都不会频繁触发 JNI
	static function refreshBatteryCache():Void
	{
		var now:Float = haxe.Timer.stamp();
		if (now - _batteryStamp < BATTERY_CACHE_SECONDS)
			return;
		_batteryStamp = now;
		_batteryLevel = getBatteryLevelRaw();
		_charging = isChargingRaw();
		_chargingWatts = getChargingWattsRaw();
	}

	/** 电量百分比（0~100；读不到时 -1；桌面固定 100） */
	public static function getBatteryLevel():Int
	{
		refreshBatteryCache();
		return _batteryLevel;
	}

	/** 是否正在充电（桌面固定 false） */
	public static function isCharging():Bool
	{
		refreshBatteryCache();
		return _charging;
	}

	static function getBatteryLevelRaw():Int
	{
		#if android
		return JNICache.createStaticMethod('com/kathyengine/mobile/MobileBridge', 'getBatteryLevel', '()I')();
		#else
		return 100;
		#end
	}

	static function isChargingRaw():Bool
	{
		#if android
		return JNICache.createStaticMethod('com/kathyengine/mobile/MobileBridge', 'isCharging', '()Z')();
		#else
		return false;
		#end
	}

	/** 充电功率（瓦特；设备不支持时返回 -1） */
	public static function getChargingWatts():Float
	{
		refreshBatteryCache();
		return _chargingWatts;
	}

	static function getChargingWattsRaw():Float
	{
		#if android
		return JNICache.createStaticMethod('com/kathyengine/mobile/MobileBridge', 'getChargingWatts', '()F')();
		#else
		return -1;
		#end
	}

	/** 瓦数格式化：保留 1 位小数（12.3W）；无效值返回空串 */
	public static function formatWatts(watts:Float):String
	{
		if (watts <= 0)
			return '';
		var value:Float = Math.round(watts * 10) / 10;
		var text:String = Std.string(value);
		if (text.indexOf('.') < 0)
			text += '.0';
		return text + 'W';
	}

	/**
	 * 电量颜色：0% 红 → 100% 蓝，按 HSV 色相平滑过渡（中间经过绿/青），降低饱和度让文字更柔和。
	 */
	public static function getBatteryColor(level:Int):FlxColor
	{
		var ratio:Float = FlxMath.bound(level / 100.0, 0, 1);
		return FlxColor.fromHSB(ratio * 210.0, 0.65, 0.95);
	}

	/** 电量信息文本（仅移动端且能读到电量时返回，否则空串）。固定英文，避免默认 vcr 字体缺中文字形 */
	public static function getBatteryText():String
	{
		if (!FlxG.onMobile)
			return '';
		var level:Int = getBatteryLevel();
		if (level < 0)
			return '';
		#if android
		var text:String = 'Battery $level%';
		if (isCharging())
		{
			var wattsText:String = formatWatts(getChargingWatts());
			text += (wattsText.length > 0) ? ' (Charging $wattsText)' : ' (Charging)';
		}
		return text;
		#else
		return '';
		#end
	}

	/** 保持屏幕常亮（全局生效：同时控制系统休眠超时与窗口 flag） */
	public static function setKeepScreenOn(on:Bool):Void
	{
		// allowScreenTimeout 是 Haxe/Lime 侧的超时控制，每次都要同步
		lime.system.System.allowScreenTimeout = !on;
		if (_keepScreenOn == on)
			return;
		_keepScreenOn = on;
		#if android
		JNICache.createStaticMethod('com/kathyengine/mobile/MobileBridge', 'setKeepScreenOn', '(Z)V')(on);
		#end
	}

	public static function getKeepScreenOn():Bool
		return _keepScreenOn;

	/** 打开游戏数据目录（Android 走 DocumentsProvider；桌面打开工作目录） */
	public static function openDataFolder():Bool
		return DataFolder.open();

	/** 打开系统图片选择器（仅 Android；桌面返回 false） */
	public static function openImagePicker(requestCode:Int):Bool
	{
		#if android
		JNICache.createStaticMethod('com/kathyengine/mobile/MobileBridge', 'openImagePicker', '(I)V')(requestCode);
		return true;
		#else
		return false;
		#end
	}

	/** 把 content:// URI 写入为 PNG 文件（仅 Android） */
	public static function importImage(uri:String, destPath:String, maxSize:Int = 2048):Bool
	{
		#if android
		return JNICache.createStaticMethod('com/kathyengine/mobile/MobileBridge', 'importImage', '(Ljava/lang/String;Ljava/lang/String;I)Z')(uri, destPath,
			maxSize);
		#else
		return false;
		#end
	}

	public static function getPackageName():String
	{
		#if android
		return JNICache.createStaticMethod('com/kathyengine/mobile/MobileBridge', 'getPackageName', '()Ljava/lang/String;')();
		#else
		return '';
		#end
	}

	/** 安装 Java 层未捕获异常上报（写入 logDir/crash_native_*.txt） */
	public static function installCrashHandler(logDir:String):Void
	{
		#if android
		JNICache.createStaticMethod('com/kathyengine/mobile/MobileBridge', 'installCrashHandler', '(Ljava/lang/String;)V')(logDir);
		#end
	}

	/**
	 * 重启应用（Android 走 MobileBridge.restartApp() 的 Launch Intent + 结束进程）。
	 * 桌面 / iOS 等平台不做任何事，由调用方 CrashHandler 负责降级处理。
	 * 返回是否成功发起重启，便于调用方决定是否需要降级。
	 */
	public static function restartApp():Bool
	{
		#if android
		try
		{
			JNICache.createStaticMethod('com/kathyengine/mobile/MobileBridge', 'restartApp', '()V')();
			return true;
		}
		catch (e:Dynamic)
		{
			trace('[MobileUtil] restartApp failed: ' + Std.string(e));
			return false;
		}
		#else
		return false;
		#end
	}
}
