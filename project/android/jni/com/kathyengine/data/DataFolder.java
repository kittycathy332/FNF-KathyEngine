package com.kathyengine.data;

import android.content.ActivityNotFoundException;
import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.provider.DocumentsContract;
import android.widget.Toast;

import org.libsdl.app.SDLActivity;

/**
 * 通过 DocumentsContract 根 URI 打开系统文件管理器中的数据目录。
 * 放在 app 模块（project/android/jni），因此可以直接使用 SDLActivity 获取 Context。
 */
public class DataFolder
{
	private static final String ROOT_ID = "root";
	private static final String ROOT_MIME = "vnd.android.document/root";

	private static final String[] FILE_MANAGERS = new String[] {
		"com.google.android.documentsui",
		"com.android.documentsui",
		null
	};

	public static boolean open()
	{
		Context context = SDLActivity.getContext();
		if (context == null) return false;

		Uri rootUri;
		try
		{
			String authority = context.getPackageName() + ".documents";
			rootUri = DocumentsContract.buildRootUri(authority, ROOT_ID);
		}
		catch (Throwable t)
		{
			return false;
		}

		for (String manager : FILE_MANAGERS)
			if (tryOpen(context, rootUri, manager)) return true;

		try
		{
			Toast.makeText(context, "No file manager could open the data folder.", Toast.LENGTH_LONG).show();
		}
		catch (Throwable ignored)
		{
		}
		return false;
	}

	private static boolean tryOpen(Context context, Uri uri, String manager)
	{
		Intent intent = new Intent(Intent.ACTION_VIEW);
		intent.setDataAndType(uri, ROOT_MIME);
		intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION
			| Intent.FLAG_GRANT_WRITE_URI_PERMISSION
			| Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
			| Intent.FLAG_GRANT_PREFIX_URI_PERMISSION);
		if (manager != null) intent.setPackage(manager);
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
	}
}
