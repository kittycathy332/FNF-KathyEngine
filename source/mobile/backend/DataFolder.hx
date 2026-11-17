package mobile.backend;

#if android
import lime.system.JNI;
#end

/**
 * 打开游戏数据目录。
 * - Android: 通过 DocumentsProvider / SAF 跳转系统文件管理器，定位到设置选定的存储根。
 * - 桌面 (Windows/macOS/Linux): 打开工作目录（exe 所在目录，mods/saves 所在）。
 * - iOS: 用系统 openURL 打开应用 Documents 目录（受 iOS 沙盒限制，能否直接定位取决于系统）。
 */
class DataFolder
{
	#if android
	static var openJNI:Dynamic = null;
	#end

	/**
	 * @return 是否成功发起打开请求
	 */
	public static function open():Bool
	{
		#if android
		if (openJNI == null)
			openJNI = JNI.createStaticMethod('com/kathyengine/data/DataFolder', 'open', '()Z');
		if (openJNI == null)
			return false;
		return openJNI() == true;
		#elseif desktop
		try
		{
			backend.CoolUtil.openFolder(Sys.getCwd(), true);
			return true;
		}
		catch (e:Dynamic)
			return false;
		#elseif ios
		// iOS 没有 shell；lime 的 openFile 在 iOS 上走原生 openURL。
		// 数据目录在 iOS 即应用 Documents 目录（见 StorageUtil.getStorageDirectory）。
		// 注意：iOS 不允许第三方 App 直接「跳转」到 Files 里的任意文件夹，
		// 这里是最接近的尽力实现——成功后会尝试用系统方式打开该路径。
		try
		{
			lime.system.System.openFile(lime.system.System.documentsDirectory);
			return true;
		}
		catch (e:Dynamic)
			return false;
		#else
		return false;
		#end
	}
}
