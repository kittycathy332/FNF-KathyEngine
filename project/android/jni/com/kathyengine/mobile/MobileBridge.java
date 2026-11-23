package com.kathyengine.mobile;

import android.app.Activity;
import android.content.ContentResolver;
import android.content.Context;
import android.content.Intent;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.net.Uri;
import android.os.BatteryManager;
import android.os.Handler;
import android.os.Looper;
import android.view.WindowManager;
import android.widget.Toast;
import org.libsdl.app.SDLActivity;

import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;

/**
 * KathyEngine 原生能力桥接（无 Extension 依赖，直接挂在 app 模块）。
 * 与 Haxe 侧 mobile.backend.MobileUtil 一一对应。
 */
public class MobileBridge {
	private static Context ctx() {
		return SDLActivity.getContext();
	}

	private static Activity activity() {
		Context c = ctx();
		return (c instanceof Activity) ? (Activity) c : null;
	}

	/** 主线程 Toast */
	public static void toast(final String text, final boolean longDuration) {
		if (text == null) return;
		Context c = ctx();
		if (c == null) return;
		new Handler(Looper.getMainLooper()).post(new Runnable() {
			@Override
			public void run() {
				Toast.makeText(c.getApplicationContext(), text,
					longDuration ? Toast.LENGTH_LONG : Toast.LENGTH_SHORT).show();
			}
		});
	}

	/** 常亮屏幕 */
	public static void setKeepScreenOn(final boolean on) {
		Activity a = activity();
		if (a == null) return;
		a.runOnUiThread(new Runnable() {
			@Override
			public void run() {
				if (on) {
					a.getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
				} else {
					a.getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
				}
			}
		});
	}

	/** 电量百分比（0~100，读不到时返回 -1） */
	public static int getBatteryLevel() {
		Context c = ctx();
		if (c == null) return -1;
		try {
			Intent intent = c.registerReceiver(null, new android.content.IntentFilter(Intent.ACTION_BATTERY_CHANGED));
			if (intent == null) return -1;
			int level = intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1);
			int scale = intent.getIntExtra(BatteryManager.EXTRA_SCALE, -1);
			if (level < 0 || scale <= 0) return -1;
			return (int) (level * 100.0f / scale);
		} catch (Exception e) {
			return -1;
		}
	}

	/** 是否正在充电 */
	public static boolean isCharging() {
		Context c = ctx();
		if (c == null) return false;
		try {
			Intent intent = c.registerReceiver(null, new android.content.IntentFilter(Intent.ACTION_BATTERY_CHANGED));
			if (intent == null) return false;
			int status = intent.getIntExtra(BatteryManager.EXTRA_STATUS, -1);
			if (status == BatteryManager.BATTERY_STATUS_CHARGING || status == BatteryManager.BATTERY_STATUS_FULL) return true;
			return intent.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0) != 0;
		} catch (Exception e) {
			return false;
		}
	}

	/** 充电功率（瓦特）= |电流| × 电压；设备不支持时返回 -1 */
	public static float getChargingWatts() {
		Context c = ctx();
		if (c == null) return -1f;
		try {
			Intent sticky = c.registerReceiver(null, new android.content.IntentFilter(Intent.ACTION_BATTERY_CHANGED));
			if (sticky == null) return -1f;
			int voltageMv = sticky.getIntExtra(BatteryManager.EXTRA_VOLTAGE, -1);
			if (voltageMv <= 0) return -1f;

			BatteryManager bm = (BatteryManager) c.getSystemService(Context.BATTERY_SERVICE);
			if (bm == null) return -1f;
			long currentUa = bm.getLongProperty(BatteryManager.BATTERY_PROPERTY_CURRENT_NOW);
			if (currentUa == 0 || currentUa == Long.MIN_VALUE || currentUa == Integer.MIN_VALUE)
				return -1f;
			if (Math.abs(currentUa) > 10000000L) return -1f; // >10A 视为异常读数

			float volts = voltageMv / 1000f;
			float amps = Math.abs(currentUa) / 1000000f;
			return amps * volts;
		} catch (Throwable t) {
			return -1f;
		}
	}

	/** 打开系统图片选择器（SAF / Documents UI），结果通过 androidtools 回调返回 */
	public static void openImagePicker(int requestCode) {
		Activity a = activity();
		if (a == null) return;
		Intent intent = new Intent(Intent.ACTION_GET_CONTENT);
		intent.addCategory(Intent.CATEGORY_OPENABLE);
		intent.setType("image/*");
		try {
			a.startActivityForResult(intent, requestCode);
		} catch (Exception e) {
			e.printStackTrace();
		}
	}

	/**
	 * 打开系统文件选择器（SAF / Documents UI），可选择任意类型文件。
	 * 结果通过 androidtools CallBack.onActivityResult 返回，字段含 requestCode/resultCode/uri。
	 * @param requestCode 用于识别本次选择
	 * @param mimeType    MIME 过滤，如 application/json、image/* 或 * 斜杠 *（全部类型）
	 */
	public static void openFilePicker(int requestCode, String mimeType) {
		Activity a = activity();
		if (a == null) return;
		Intent intent = new Intent(Intent.ACTION_GET_CONTENT);
		intent.addCategory(Intent.CATEGORY_OPENABLE);
		intent.setType((mimeType == null || mimeType.length() == 0) ? "*/*" : mimeType);
		try {
			intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
			a.startActivityForResult(intent, requestCode);
		} catch (Exception e) {
			e.printStackTrace();
		}
	}

	/**
	 * 打开系统「另存为」对话框（ACTION_CREATE_DOCUMENT）。
	 * 用户选保存位置+文件名，返回 content:// URI，再用 writeUriText 写入。
	 * 结果通过 CallBack.onActivityResult 返回（字段 uri）。
	 * @param requestCode 用于识别本次请求
	 * @param fileName    建议文件名（如 song.json）
	 * @param mimeType    MIME 类型，如 application/json
	 */
	public static void createDocument(int requestCode, String fileName, String mimeType) {
		Activity a = activity();
		if (a == null) return;
		Intent intent = new Intent(Intent.ACTION_CREATE_DOCUMENT);
		intent.addCategory(Intent.CATEGORY_OPENABLE);
		intent.setType((mimeType == null || mimeType.length() == 0) ? "*/*" : mimeType);
		intent.putExtra(Intent.EXTRA_TITLE, fileName == null ? "chart.json" : fileName);
		try {
			intent.addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION);
			a.startActivityForResult(intent, requestCode);
		} catch (Exception e) {
			e.printStackTrace();
		}
	}

	/**
	 * 打开系统目录选择对话框（ACTION_OPEN_DOCUMENT_TREE）。
	 * 用于多文件保存（V-Slice 谱面+元数据等）。返回目录 content:// URI。
	 * 注意：SAF 目录 URI 不能直接用 java.io.File 写，需通过 ContentResolver 创建子文件。
	 */
	public static void openDocumentTree(int requestCode) {
		Activity a = activity();
		if (a == null) return;
		Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT_TREE);
		try {
			intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION
				| Intent.FLAG_GRANT_WRITE_URI_PERMISSION
				| Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION);
			a.startActivityForResult(intent, requestCode);
		} catch (Exception e) {
			e.printStackTrace();
		}
	}

	/**
	 * 写入文本到 SAF content:// URI（ACTION_CREATE_DOCUMENT 返回的 URI）。
	 * @return true 成功
	 */
	public static boolean writeUriText(String uriString, String text) {
		if (uriString == null || text == null) return false;
		Context c = ctx();
		if (c == null) return false;
		java.io.OutputStream out = null;
		try {
			ContentResolver cr = c.getContentResolver();
			out = cr.openOutputStream(Uri.parse(uriString), "w");
			if (out == null) return false;
			out.write(text.getBytes("UTF-8"));
			out.flush();
			return true;
		} catch (Exception e) {
			e.printStackTrace();
			return false;
		} finally {
			if (out != null) {
				try { out.close(); } catch (Exception ignored) {}
			}
		}
	}

	/**
	 * 在父文档下查找同名子项，存在则复用（覆盖写入），不存在才创建。
	 * DocumentsContract.createDocument 遇到同名会生成 "name (1)" 副本，
	 * 所以多文件保存必须先查再建，否则 chart/metadata 各建一遍目录产生多个副本。
	 */
	private static Uri findOrCreateDocument(ContentResolver cr, Uri treeUri, Uri parentUri, String name, String mimeType) {
		String parentId = android.provider.DocumentsContract.getDocumentId(parentUri);
		// 关键：buildChildDocumentsUriUsingTree / buildDocumentUriUsingTree 的第一参必须是
		// 原始 tree URI，不能是 document URI，否则 query 查不到子项、去重失效。
		Uri childrenUri = android.provider.DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, parentId);
		android.database.Cursor cursor = null;
		try {
			cursor = cr.query(childrenUri,
				new String[]{
					android.provider.DocumentsContract.Document.COLUMN_DOCUMENT_ID,
					android.provider.DocumentsContract.Document.COLUMN_DISPLAY_NAME
				}, null, null, null);
			if (cursor != null) {
				while (cursor.moveToNext()) {
					String displayName = cursor.getString(cursor.getColumnIndex(
						android.provider.DocumentsContract.Document.COLUMN_DISPLAY_NAME));
					if (name.equals(displayName)) {
						String docId = cursor.getString(cursor.getColumnIndex(
							android.provider.DocumentsContract.Document.COLUMN_DOCUMENT_ID));
						return android.provider.DocumentsContract.buildDocumentUriUsingTree(treeUri, docId);
					}
				}
			}
		} catch (Exception e) {
			e.printStackTrace();
		} finally {
			if (cursor != null) cursor.close();
		}
		try {
			return android.provider.DocumentsContract.createDocument(cr, parentUri, mimeType, name);
		} catch (java.io.FileNotFoundException e) {
			e.printStackTrace();
			return null;
		}
	}

	/**
	 * 在 SAF 目录 URI 下创建文件并写入文本（多文件保存用）。
	 * 同名目录/文件会复用，避免 dad-battle、dad-battle (1)... 副本泛滥。
	 * @param treeUri  目录 content:// URI
	 * @param fileName 文件名（可含子目录用 / 分隔）
	 * @param text     文件内容
	 * @return true 成功
	 */
	public static boolean writeToTree(String treeUri, String fileName, String text) {
		if (treeUri == null || fileName == null || text == null) return false;
		Context c = ctx();
		if (c == null) return false;
		ContentResolver cr = c.getContentResolver();
		try {
			Uri rootUri = Uri.parse(treeUri);
			Uri docUri = android.provider.DocumentsContract.buildDocumentUriUsingTree(
				rootUri, android.provider.DocumentsContract.getTreeDocumentId(rootUri));
			// 逐级查找/创建子目录
			String[] parts = fileName.split("/");
			for (int i = 0; i < parts.length - 1; i++) {
				Uri childUri = findOrCreateDocument(cr, rootUri, docUri, parts[i],
					android.provider.DocumentsContract.Document.MIME_TYPE_DIR);
				if (childUri == null) return false;
				docUri = childUri;
			}
			String lastName = parts[parts.length - 1];
			Uri fileUri = findOrCreateDocument(cr, rootUri, docUri, lastName, "application/json");
			if (fileUri == null) return false;
			return writeUriText(fileUri.toString(), text);
		} catch (Exception e) {
			e.printStackTrace();
			return false;
		}
	}

	/**
	 * 读取 SAF content:// URI 指向的文本内容（如 JSON）。
	 * content:// 不能直接用 File 读，必须走 ContentResolver。
	 * @param uriString SAF 返回的 URI 字符串
	 * @return 文本；失败返回 null
	 */
	public static String readUriText(String uriString) {
		if (uriString == null) return null;
		Context c = ctx();
		if (c == null) return null;
		InputStream in = null;
		try {
			ContentResolver cr = c.getContentResolver();
			Uri uri = Uri.parse(uriString);
			in = cr.openInputStream(uri);
			if (in == null) return null;
			java.io.ByteArrayOutputStream out = new java.io.ByteArrayOutputStream();
			byte[] buf = new byte[8192];
			int len;
			while ((len = in.read(buf)) > 0) out.write(buf, 0, len);
			return out.toString("UTF-8");
		} catch (Exception e) {
			e.printStackTrace();
			return null;
		} finally {
			if (in != null) {
				try { in.close(); } catch (Exception ignored) {}
			}
		}
	}

	/**
	 * 获取 SAF URI 的显示文件名（从 DisplayName column）。
	 */
	public static String getUriDisplayName(String uriString) {
		if (uriString == null) return null;
		Context c = ctx();
		if (c == null) return null;
		android.database.Cursor cursor = null;
		try {
			Uri uri = Uri.parse(uriString);
			String[] projection = { android.provider.OpenableColumns.DISPLAY_NAME };
			cursor = c.getContentResolver().query(uri, projection, null, null, null);
			if (cursor != null && cursor.moveToFirst()) {
				int idx = cursor.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME);
				if (idx >= 0) return cursor.getString(idx);
			}
		} catch (Exception e) {
			e.printStackTrace();
		} finally {
			if (cursor != null) cursor.close();
		}
		// 回退：从 URI 末段取
		int slash = uriString.lastIndexOf('/');
		return slash >= 0 ? uriString.substring(slash + 1) : uriString;
	}

	/**
	 * 将 SAF 返回的 content:// URI 解码并保存为 PNG。
	 * @param uriString  返回的 URI
	 * @param destPath   目标文件绝对路径
	 * @param maxSize    最长边上限（避免超大图占内存）
	 */
	public static boolean importImage(String uriString, String destPath, int maxSize) {
		if (uriString == null || destPath == null) return false;
		Context c = ctx();
		if (c == null) return false;
		InputStream first = null;
		InputStream second = null;
		try {
			ContentResolver cr = c.getContentResolver();
			Uri uri = Uri.parse(uriString);

			BitmapFactory.Options bounds = new BitmapFactory.Options();
			bounds.inJustDecodeBounds = true;
			first = cr.openInputStream(uri);
			BitmapFactory.decodeStream(first, null, bounds);
			first.close();
			first = null;
			if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return false;

			int sample = 1;
			if (maxSize > 0) {
				while ((bounds.outWidth / sample) > maxSize * 2 && (bounds.outHeight / sample) > maxSize * 2) sample *= 2;
			}

			BitmapFactory.Options opts = new BitmapFactory.Options();
			opts.inSampleSize = sample;
			second = cr.openInputStream(uri);
			Bitmap bitmap = BitmapFactory.decodeStream(second, null, opts);
			second.close();
			second = null;
			if (bitmap == null) return false;

			// 缩放到 maxSize 以内，保持宽高比
			if (maxSize > 0 && (bitmap.getWidth() > maxSize || bitmap.getHeight() > maxSize)) {
				float ratio = Math.min((float) maxSize / bitmap.getWidth(), (float) maxSize / bitmap.getHeight());
				int w = Math.max(1, Math.round(bitmap.getWidth() * ratio));
				int h = Math.max(1, Math.round(bitmap.getHeight() * ratio));
				Bitmap scaled = Bitmap.createScaledBitmap(bitmap, w, h, true);
				if (scaled != bitmap) bitmap.recycle();
				bitmap = scaled;
			}

			File dest = new File(destPath);
			File parent = dest.getParentFile();
			if (parent != null && !parent.exists()) parent.mkdirs();

			FileOutputStream out = new FileOutputStream(dest);
			boolean ok = bitmap.compress(Bitmap.CompressFormat.PNG, 100, out);
			out.flush();
			out.close();
			bitmap.recycle();
			return ok;
		} catch (Exception e) {
			e.printStackTrace();
			return false;
		} finally {
			try {
				if (first != null) first.close();
			} catch (Exception ignored) {}
			try {
				if (second != null) second.close();
			} catch (Exception ignored) {}
		}
	}

	/** 当前包名（用于把日志/路径显示给用户） */
	public static String getPackageName() {
		Context c = ctx();
		return (c == null) ? "" : c.getPackageName();
	}

	/**
	 * 重启应用：用 Launch Intent 清栈重新拉起主 Activity，再结束当前进程。
	 * 供游戏内崩溃弹层的「重启应用」按钮调用（Haxe 侧 mobile.backend.MobileUtil / CrashHandler）。
	 * 注意：这里必须在主线程 startActivity，且 NEW_TASK 不能省（ctx 可能是 Application Context）。
	 */
	public static void restartApp() {
		final Context c = ctx();
		if (c == null) return;
		try {
			Intent intent = c.getPackageManager().getLaunchIntentForPackage(c.getPackageName());
			if (intent == null) return;
			intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
			new Handler(Looper.getMainLooper()).post(new Runnable() {
				@Override
				public void run() {
					try {
						c.startActivity(intent);
					} catch (Throwable ignored) {}
					android.os.Process.killProcess(android.os.Process.myPid());
					System.exit(0);
				}
			});
		} catch (Throwable ignored) {}
	}

	/**
	 * 安装 Java 层崩溃上报：写 crash_native_*.txt 后继续抛给原处理器（不改变崩溃行为）。
	 */
	public static void installCrashHandler(final String logDir) {
		final Thread.UncaughtExceptionHandler previous = Thread.getDefaultUncaughtExceptionHandler();
		Thread.setDefaultUncaughtExceptionHandler(new Thread.UncaughtExceptionHandler() {
			@Override
			public void uncaughtException(Thread thread, Throwable throwable) {
				try {
					File dir = new File(logDir);
					if (!dir.exists()) dir.mkdirs();
					java.text.SimpleDateFormat fmt = new java.text.SimpleDateFormat("yyyy-MM-dd_HH-mm-ss", java.util.Locale.US);
					File file = new File(dir, "crash_native_" + fmt.format(new java.util.Date()) + ".txt");
					java.io.PrintWriter pw = new java.io.PrintWriter(new java.io.FileOutputStream(file));
					pw.println("Thread: " + thread.getName());
					throwable.printStackTrace(pw);
					pw.flush();
					pw.close();
				} catch (Throwable ignored) {
					// 日志失败绝不能掩盖原始崩溃
				}
				if (previous != null) previous.uncaughtException(thread, throwable);
			}
		});
	}
}
