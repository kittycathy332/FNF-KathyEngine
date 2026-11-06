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
