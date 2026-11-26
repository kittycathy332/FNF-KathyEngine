package mobile.backend;

#if android

/**
 * Android 原生文件选择器（SAF / Documents UI）。
 *
 * 走系统 Intent，用户可从「文件」「下载」「Drive」等任意位置操作：
 * - pick：ACTION_GET_CONTENT 选文件（读）
 * - saveFile：ACTION_CREATE_DOCUMENT 选位置+写文件（单文件另存为）
 * - saveToDir：ACTION_OPEN_DOCUMENT_TREE 选目录（多文件保存，如 V-Slice）
 *
 * 结果经 extension-androidtools 的 CallBack.onActivityResult 回传 content:// URI。
 * 与 HitboxImageImporter 共用回调机制，用随机 requestCode 区分，避免撞码。
 */
class AndroidFilePicker
{
	static var _nextRequestCode:Int = 0x4A53; // "JS"
	static var _pending:Map<Int, Dynamic> = new Map();
	static var _initialized:Bool = false;

	/** 读文件回调：(text, name)，text==null 表示取消/失败。 */
	public static var onDone:String->String->Void = null;
	/** 读二进制文件回调：(bytes, name)，bytes==null 表示取消/失败。 */
	public static var onDoneBytes:haxe.io.Bytes->String->Void = null;
	/** 保存文件回调：(success, uri)，success==false 表示取消/失败。 */
	public static var onSaved:Bool->String->Void = null;

	static function ensureInit():Void
	{
		if (_initialized) return;
		_initialized = true;
		android.callback.CallBack.init();
		android.callback.CallBack.onActivityResult.add(onActivityResult);
	}

	static function onActivityResult(data:Dynamic):Void
	{
		if (data == null) return;
		var req:Int = data.requestCode;
		var cb:Dynamic = _pending.get(req);
		if (cb == null) return; // 不是我们的请求（图片选择器等）
		_pending.remove(req);

		var uri:String = null;
		if (data.resultCode == -1 && data.uri != null) // Activity.RESULT_OK
			uri = cast data.uri;
		cb(uri); // 统一把 uri 交给各自的包装闭包处理
	}

	static function nextCode():Int
	{
		var req:Int = _nextRequestCode++;
		if (_nextRequestCode > 0xFFFF) _nextRequestCode = 0x4A53;
		return req;
	}

	/** 选择文件读取。mimeType 如 application/json、image/*；null=全部。 */
	public static function pick(?mimeType:String, ?onDone:String->String->Void):Bool
	{
		ensureInit();
		if (onDone != null) AndroidFilePicker.onDone = onDone;
		var req:Int = nextCode();
		_pending.set(req, function(uri:String)
		{
			var text:String = null;
			var name:String = null;
			if (uri != null)
			{
				text = MobileUtil.readUriText(uri);
				name = MobileUtil.getUriDisplayName(uri);
			}
			var cb = AndroidFilePicker.onDone;
			AndroidFilePicker.onDone = null;
			if (cb != null) cb(text, name);
		});
		if (!MobileUtil.openFilePicker(req, mimeType))
		{
			_pending.remove(req);
			var cb = AndroidFilePicker.onDone;
			AndroidFilePicker.onDone = null;
			if (cb != null) cb(null, null);
			return false;
		}
		return true;
	}

	/** 选择二进制文件读取。mimeType 如 audio/midi；null=全部。 */
	public static function pickBytes(?mimeType:String, ?onDone:haxe.io.Bytes->String->Void):Bool
	{
		ensureInit();
		if (onDone != null) AndroidFilePicker.onDoneBytes = onDone;
		var req:Int = nextCode();
		_pending.set(req, function(uri:String)
		{
			var bytes:haxe.io.Bytes = null;
			var name:String = null;
			if (uri != null)
			{
				bytes = MobileUtil.readUriBytes(uri);
				name = MobileUtil.getUriDisplayName(uri);
			}
			var cb = AndroidFilePicker.onDoneBytes;
			AndroidFilePicker.onDoneBytes = null;
			if (cb != null) cb(bytes, name);
		});
		if (!MobileUtil.openFilePicker(req, mimeType))
		{
			_pending.remove(req);
			var cb = AndroidFilePicker.onDoneBytes;
			AndroidFilePicker.onDoneBytes = null;
			if (cb != null) cb(null, null);
			return false;
		}
		return true;
	}

	/**
	 * 另存为单文件：系统文件管理器选位置+文件名，回调里把 text 写入。
	 * @param fileName 建议文件名
	 * @param mimeType MIME
	 * @param text     要写入的内容
	 * @param onSaved  (success, uri)
	 */
	public static function saveFile(fileName:String, mimeType:String, text:String, ?onSaved:Bool->String->Void):Bool
	{
		ensureInit();
		if (onSaved != null) AndroidFilePicker.onSaved = onSaved;
		var req:Int = nextCode();
		_pending.set(req, function(uri:String)
		{
			var ok:Bool = false;
			if (uri != null)
				ok = MobileUtil.writeUriText(uri, text);
			var cb = AndroidFilePicker.onSaved;
			AndroidFilePicker.onSaved = null;
			if (cb != null) cb(ok, uri);
		});
		if (!MobileUtil.createDocument(req, fileName, mimeType))
		{
			_pending.remove(req);
			var cb = AndroidFilePicker.onSaved;
			AndroidFilePicker.onSaved = null;
			if (cb != null) cb(false, null);
			return false;
		}
		return true;
	}

	/**
	 * 选目录（多文件保存）：系统目录选择器，回调拿到目录 URI。
	 * 文件写入由调用方用 MobileUtil.writeToTree(uri, name, text) 完成。
	 * @param onPicked (uri)，uri==null 表示取消
	 */
	public static function pickDirectory(?onPicked:String->Void):Bool
	{
		ensureInit();
		var req:Int = nextCode();
		_pending.set(req, function(uri:String)
		{
			if (onPicked != null) onPicked(uri);
		});
		if (!MobileUtil.openDocumentTree(req))
		{
			_pending.remove(req);
			if (onPicked != null) onPicked(null);
			return false;
		}
		return true;
	}
}

#end
