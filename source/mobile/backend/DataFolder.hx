package mobile.backend;

#if android
import lime.system.JNI;
#end

/**
 * 打开游戏数据目录。
 * Android 通过 DocumentsProvider 根 URI 跳转系统文件管理器；桌面直接打开工作目录。
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
		#else
		return false;
		#end
	}
}
