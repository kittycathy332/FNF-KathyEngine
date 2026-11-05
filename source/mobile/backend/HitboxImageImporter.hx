package mobile.backend;

import mobile.objects.Hitbox;

/**
 * Hitbox 自定义图片导入：
 * - Android：系统 SAF 图片选择器（ACTION_GET_CONTENT），解码缩放后写入 mobile/hitbox_image.png
 * - 桌面：lime.ui.FileDialog 选择文件后直接复制
 */
class HitboxImageImporter
{
	static inline var REQUEST_CODE:Int = 0x4842; // "HB"

	static var _onDone:Null<Bool->Void> = null;

	#if android
	static var _initialized:Bool = false;

	static function ensureInit():Void
	{
		if (_initialized)
			return;
		_initialized = true;
		android.callback.CallBack.init();
		android.callback.CallBack.onActivityResult.add(onActivityResult);
	}

	static function onActivityResult(data:Dynamic):Void
	{
		if (data == null || data.requestCode != REQUEST_CODE)
			return;

		var ok:Bool = false;
		if (data.resultCode == -1 && data.uri != null)
			ok = MobileUtil.importImage(cast data.uri, Hitbox.imagePath(), 2048);

		if (ok)
			Hitbox.reloadImage();

		var cb = _onDone;
		_onDone = null;
		if (cb != null)
			cb(ok);
	}
	#end

	public static function pick(onDone:Bool->Void):Void
	{
		_onDone = onDone;
		#if android
		ensureInit();
		MobileUtil.openImagePicker(REQUEST_CODE);
		#elseif desktop
		var dialog:lime.ui.FileDialog = new lime.ui.FileDialog();
		dialog.onOpen.add(function(data) {
			if (saveBytes(data))
			{
				Hitbox.reloadImage();
				finish(true);
			}
			else
				finish(false);
		});
		dialog.onCancel.add(function() {
			finish(false);
		});
		if (!dialog.open('*.png,*.jpg,*.jpeg,*.webp', null, 'Select Hitbox Image'))
			finish(false);
		#else
		finish(false);
		#end
	}

	public static function remove():Void
	{
		Hitbox.removeImage();
	}

	static function saveBytes(data:haxe.io.Bytes):Bool
	{
		if (data == null)
			return false;
		try
		{
			var path:String = Hitbox.imagePath();
			var dir:String = haxe.io.Path.directory(path);
			if (dir != null && dir.length > 0 && !FileSystem.exists(dir))
				FileSystem.createDirectory(dir);
			File.saveBytes(path, data);
			return true;
		}
		catch (e:Dynamic)
		{
			trace('HitboxImageImporter: save failed (${e.message})');
			return false;
		}
	}

	static function finish(ok:Bool):Void
	{
		var cb = _onDone;
		_onDone = null;
		if (cb != null)
			cb(ok);
	}
}
