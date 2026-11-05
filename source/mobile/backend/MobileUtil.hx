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
	public static function toast(text:String):Void
	{
		if (text == null)
			return;
		#if android
		JNICache.createStaticMethod('com/kathyengine/mobile/MobileBridge', 'toast', '(Ljava/lang/String;)V')(text);
		#else
		trace('[Toast] $text');
		#end
	}

	/** 电量百分比（0~100；读不到时 -1；桌面固定 100） */
	public static function getBatteryLevel():Int
	{
		#if android
		return JNICache.createStaticMethod('com/kathyengine/mobile/MobileBridge', 'getBatteryLevel', '()I')();
		#else
		return 100;
		#end
	}

	/** 是否正在充电（桌面固定 false） */
	public static function isCharging():Bool
	{
		#if android
		return JNICache.createStaticMethod('com/kathyengine/mobile/MobileBridge', 'isCharging', '()Z')();
		#else
		return false;
		#end
	}

	/** 保持屏幕常亮 */
	public static function setKeepScreenOn(on:Bool):Void
	{
		if (_keepScreenOn == on)
			return;
		_keepScreenOn = on;
		#if android
		JNICache.createStaticMethod('com/kathyengine/mobile/MobileBridge', 'setKeepScreenOn', '(Z)V')(on);
		#end
	}

	public static function getKeepScreenOn():Bool
		return _keepScreenOn;

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
}
