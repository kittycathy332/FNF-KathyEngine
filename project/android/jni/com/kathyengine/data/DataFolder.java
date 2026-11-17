package com.kathyengine.data;

import android.content.ActivityNotFoundException;
import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.os.Build;
import android.provider.DocumentsContract;
import android.widget.Toast;

import org.libsdl.app.SDLActivity;

import java.io.File;
import java.io.FileInputStream;

/**
 * 打开游戏数据目录（设置里选定的存储根：Data / Media / Obb / External）。
 * 数据根由 StorageUtil 写入的 .kathy_storage_root 标记决定，DataProvider 通过同一标记
 * 把该目录暴露为 DocumentsProvider 的 root，因此这里只需打开该 provider 的 root。
 *
 * 放在 app 模块（project/android/jni），可直接使用 SDLActivity 获取 Context。
 */
public class DataFolder
{
	private static final String ROOT_ID = "root";
	private static final String ROOT_FILE_NAME = ".kathy_storage_root";

	public static boolean open()
	{
		Context context = SDLActivity.getContext();
		if (context == null) return false;

		final String authority = context.getPackageName() + ".documents";
		final File baseDir = readBaseDir(context);

		// 方案 1（Android 8.0+）：buildExploreRootUri 让系统「文件」应用直接浏览该 provider 根。
		// 注意：该方法是系统 @hide API —— 运行时存在，但 SDK 的 android.jar 里没有声明，
		// 直接调用会在编译期报「找不到符号」。因此用反射调用，避免编译期依赖。
		// 反射失败（设备无此方法）时静默回退到下面的方案 2/3。
		if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
		{
			try
			{
				java.lang.reflect.Method m = DocumentsContract.class.getMethod(
					"buildExploreRootUri", String.class, String.class);
				Uri exploreUri = (Uri) m.invoke(null, authority, ROOT_ID);
				if (exploreUri != null)
				{
					Intent view = new Intent(Intent.ACTION_VIEW);
					view.setDataAndType(exploreUri, "vnd.android.document/root");
					addGrantFlags(view);
					if (startSafely(context, view)) return true;
				}
			}
			catch (Throwable ignored)
			{
			}
		}

		// 方案 2（SAF 文件夹选择器）：打开系统文件夹选择器并尽量定位到数据根目录。
		// 用户能直接看到目录内容；本功能只需「打开看到」，不依赖写权限。
		try
		{
			Intent tree = new Intent(Intent.ACTION_OPEN_DOCUMENT_TREE);
			if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && baseDir != null)
			{
				Uri initial = DocumentsContract.buildDocumentUri(authority, baseDir.getAbsolutePath());
				tree.putExtra(DocumentsContract.EXTRA_INITIAL_URI, initial);
			}
			addGrantFlags(tree);
			if (startSafely(context, tree)) return true;
		}
		catch (Throwable ignored)
		{
		}

		// 方案 3（旧兜底）：对 root URI 发 ACTION_VIEW，命中少数第三方文件管理器。
		try
		{
			Uri rootDoc = DocumentsContract.buildRootUri(authority, ROOT_ID);
			Intent legacy = new Intent(Intent.ACTION_VIEW);
			legacy.setDataAndType(rootDoc, "vnd.android.document/root");
			addGrantFlags(legacy);
			if (startSafely(context, legacy)) return true;
		}
		catch (Throwable ignored)
		{
		}

		try
		{
			Toast.makeText(context, "No file manager could open the data folder.", Toast.LENGTH_LONG).show();
		}
		catch (Throwable ignored)
		{
		}
		return false;
	}

	/** 读取 StorageUtil 写入的实际数据根；失败时回退到应用外部私有目录。 */
	private static File readBaseDir(Context context)
	{
		File fallback = context.getExternalFilesDir(null);
		if (fallback == null) fallback = context.getFilesDir();
		File marker = new File(fallback, ROOT_FILE_NAME);
		if (marker.isFile())
		{
			FileInputStream in = null;
			try
			{
				byte[] data = new byte[(int) marker.length()];
				in = new FileInputStream(marker);
				int read = in.read(data);
				String path = new String(data, 0, Math.max(read, 0), "UTF-8").trim();
				if (path.length() > 0)
				{
					File resolved = new File(path);
					if (resolved.isDirectory()) return resolved;
				}
			}
			catch (Throwable ignored)
			{
			}
			finally
			{
				if (in != null)
					try { in.close(); } catch (Throwable ignored) {}
			}
		}
		return fallback;
	}

	private static void addGrantFlags(Intent intent)
	{
		intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION
			| Intent.FLAG_GRANT_WRITE_URI_PERMISSION
			| Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
			| Intent.FLAG_GRANT_PREFIX_URI_PERMISSION);
	}

	private static boolean startSafely(Context context, Intent intent)
	{
		if (!(context instanceof android.app.Activity))
			intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
		try
		{
			context.startActivity(intent);
			return true;
		}
		catch (ActivityNotFoundException e)
		{
			return false;
		}
		catch (SecurityException e)
		{
			return false;
		}
		catch (Throwable t)
		{
			return false;
		}
	}
}
