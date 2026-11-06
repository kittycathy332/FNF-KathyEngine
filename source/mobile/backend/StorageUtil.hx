/*
 * Copyright (C) 2025 Mobile Porting Team
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and associated documentation files (the "Software"),
 * to deal in the Software without restriction, including without limitation
 * the rights to use, copy, modify, merge, publish, distribute, sublicense,
 * and/or sell copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 * DEALINGS IN THE SOFTWARE.
 */

package mobile.backend;

import haxe.io.Path;

/**
 * A storage class for mobile.
 *
 * 四种存储类型（Data / Media / Obb / External）决定「用户数据」根目录：
 * mods、saves、logs、screenshots、exports、backups、crash 等全部跟随该根目录。
 * 只切换位置、不自动迁移已有数据。
 *
 * @author Karim Akra and Homura Akemi (HomuHomu833)
 */
class StorageUtil
{
	/**
	 * 可选存储类型。默认 External（用户可在设置页切换）。
	 */
	public static var STORAGE_TYPES:Array<String> = ['Data', 'Media', 'Obb', 'External'];
	public static var DEFAULT_STORAGE_TYPE:String = 'External';

	/** 存储类型标记文件（始终放在应用私有目录，避免受类型切换本身影响） */
	static inline var TYPE_FILE_NAME:String = '.kathy_storage_type';
	/** 实际可写根目录标记（供 Android DocumentsProvider 读取，保持 Java 与 Haxe 同源） */
	static inline var ROOT_FILE_NAME:String = '.kathy_storage_root';

	static var _storageType:Null<String> = null;
	static var _storageRoot:Null<String> = null;

	/**
	 * 应用私有目录（cwd / 内置资源复制目标），与存储类型无关。
	 */
	public static function getStorageDirectory():String
		return #if android Path.addTrailingSlash(AndroidContext.getExternalFilesDir()) #elseif ios
			Path.addTrailingSlash(lime.system.System.documentsDirectory) #else Sys.getCwd() #end;

	/**
	 * 用户可见的数据根目录（mods / saves / logs 等都放这里）。
	 */
	public static function getExternalStorageDirectory():String
	{
		if (_storageRoot == null)
			_storageRoot = getStorageRootPathForType(getStorageType());
		return _storageRoot;
	}

	/**
	 * 获取当前存储类型（读取标记文件；无效值回落到默认 External）。
	 */
	public static function getStorageType():String
	{
		if (_storageType != null)
			return _storageType;

		var storageType:String = DEFAULT_STORAGE_TYPE;
		#if android
		try
		{
			var file:String = getStorageDirectory() + TYPE_FILE_NAME;
			if (FileSystem.exists(file))
			{
				var saved:String = StringTools.trim(File.getContent(file));
				if (STORAGE_TYPES.contains(saved))
					storageType = saved;
			}
		}
		catch (e:Dynamic) {}
		#end
		return _storageType = storageType;
	}

	/**
	 * 设置存储类型（不迁移数据）。返回 false 表示目标目录无法创建/写入。
	 */
	public static function setStorageType(storageType:String):Bool
	{
		if (storageType == null || !STORAGE_TYPES.contains(storageType))
			storageType = DEFAULT_STORAGE_TYPE;

		_storageType = storageType;
		_storageRoot = getStorageRootPathForType(storageType);

		var ok:Bool = #if android ensureStorageRoot(storageType) #else true #end;

		#if android
		try
		{
			if (!FileSystem.exists(getStorageDirectory()))
				FileSystem.createDirectory(getStorageDirectory());
			File.saveContent(getStorageDirectory() + TYPE_FILE_NAME, storageType);
		}
		catch (e:Dynamic) {}
		#end

		return ok;
	}

	/**
	 * 获取指定存储类型的用户数据根目录（带结尾斜杠，保证路径可直接拼接）。
	 */
	public static function getStorageRootPathForType(storageType:String):String
	{
		#if android
		var dir:String = switch (storageType)
		{
			case 'Data':
				AndroidContext.getFilesDir();
			case 'Media':
				getAndroidMediaDir();
			case 'Obb':
				AndroidContext.getObbDir();
			case 'External':
				'/sdcard/.KathyEngine/';
			default:
				getStorageDirectory();
		};
		if (dir == null || dir.length == 0)
			dir = getStorageDirectory();
		dir = Path.addTrailingSlash(dir);
		// 未授予「所有文件访问」时 /sdcard 等目录不可写：回退到应用私有目录，避免启动崩溃
		if (!isWritableDir(dir))
		{
			trace('StorageUtil: "$dir" is not writable, falling back to app storage.');
			dir = getStorageDirectory();
		}
		writeRootMarker(dir);
		return dir;
		#else
		return getStorageDirectory();
		#end
	}

	#if android
	/**
	 * 把当前实际可写的根目录写入应用私有目录，供 DocumentsProvider 读取。
	 */
	static function writeRootMarker(root:String):Void
	{
		try
		{
			var privateDir:String = getStorageDirectory();
			if (!FileSystem.exists(privateDir))
				FileSystem.createDirectory(privateDir);
			File.saveContent(privateDir + ROOT_FILE_NAME, root);
		}
		catch (e:Dynamic) {}
	}
	#end

	#if android
	/**
	 * 目录是否可写（不存在时尝试创建一次）。
	 */
	static function isWritableDir(dir:String):Bool
	{
		try
		{
			if (!FileSystem.exists(dir))
				FileSystem.createDirectory(dir);
			return FileSystem.exists(dir);
		}
		catch (e:Dynamic)
			return false;
	}
	#end

	/**
	 * 确保当前（或指定）类型的根目录存在。
	 */
	public static function ensureStorageRoot(?storageType:String):Bool
	{
		var root:String = getStorageRootPathForType(storageType == null ? getStorageType() : storageType);
		try
		{
			if (!FileSystem.exists(root))
				FileSystem.createDirectory(root);
			for (folder in ['mods', 'saves', 'logs'])
			{
				var path:String = root + folder;
				if (!FileSystem.exists(path))
					FileSystem.createDirectory(path);
			}
			#if android
			writeRootMarker(root);
			#end
			return true;
		}
		catch (e:Dynamic)
		{
			trace('StorageUtil: failed to create storage root "$root" (${e.message})');
			return false;
		}
	}

	/**
	 * 判断某个存储类型当前是否可写（创建根目录并写入测试文件）。
	 */
	public static function isStorageTypeWritable(?storageType:String):Bool
	{
		return ensureStorageRoot(storageType);
	}

	#if android
	/**
	 * Android 10+ 的 Media 目录：/storage/emulated/0/Android/media/<package>/
	 * 由 getExternalFilesDir() 的路径推导，避免依赖 getExternalMediaDirs（Haxe 侧未导出）。
	 */
	static function getAndroidMediaDir():String
	{
		var base:String = AndroidContext.getExternalFilesDir();
		if (base == null)
			return getStorageDirectory();

		var parts:Array<String> = base.split('/');
		var dataIdx:Int = -1;
		for (i in 0...parts.length)
			if (parts[i] == 'data')
				dataIdx = i;

		// .../Android/data/<pkg>/files → .../Android/media/<pkg>
		if (dataIdx > 0 && dataIdx + 2 < parts.length && parts[dataIdx + 2] == 'files')
		{
			parts[dataIdx] = 'media';
			parts.splice(dataIdx + 2, 1);
			return parts.join('/');
		}
		return base;
	}
	#end

	public static function saveContent(fileName:String, fileData:String, ?alert:Bool = true):Void
	{
		final folder:String = getExternalStorageDirectory() + 'saves/';
		try
		{
			if (!FileSystem.exists(folder))
				FileSystem.createDirectory(folder);

			File.saveContent('$folder/$fileName', fileData);
			if (alert)
				CoolUtil.showPopUp(LanguageBasic.getPhrase('file_save_success', '{1} has been saved.', [fileName]), LanguageBasic.getPhrase('mobile_success', "Success!"));
		}
		catch (e:Dynamic)
			if (alert)
				CoolUtil.showPopUp(LanguageBasic.getPhrase('file_save_fail', '{1} couldn\'t be saved.\n({2})', [fileName, e.message]), LanguageBasic.getPhrase('mobile_error', "Error!"));
			else
				trace('$fileName couldn\'t be saved. (${e.message})');
	}

	#if android
	public static function requestPermissions():Void
	{
		if (AndroidVersion.SDK_INT >= AndroidVersionCode.TIRAMISU)
			AndroidPermissions.requestPermissions(['READ_MEDIA_IMAGES', 'READ_MEDIA_VIDEO', 'READ_MEDIA_AUDIO', 'READ_MEDIA_VISUAL_USER_SELECTED']);
		else
			AndroidPermissions.requestPermissions(['READ_EXTERNAL_STORAGE', 'WRITE_EXTERNAL_STORAGE']);

		// MANAGE_EXTERNAL_STORAGE 只在 API 30 (Android 11+) 存在
		// API 29 (Android 10) 没有这个权限，直接跳过避免 NoSuchMethodError 闪退
		if (AndroidVersion.SDK_INT >= AndroidVersionCode.R)
		{
			if (!AndroidEnvironment.isExternalStorageManager())
				AndroidSettings.requestSetting('MANAGE_APP_ALL_FILES_ACCESS_PERMISSION');
		}

		// 延迟检查权限，给用户时间授予权限
		// 使用 Sys.sleep 而不是 FlxTimer，因为此时 FlxG 可能还未初始化
		Sys.sleep(1.0);

		if ((AndroidVersion.SDK_INT >= AndroidVersionCode.TIRAMISU
			&& !AndroidPermissions.getGrantedPermissions().contains('android.permission.READ_MEDIA_IMAGES'))
			|| (AndroidVersion.SDK_INT < AndroidVersionCode.TIRAMISU
				&& !AndroidPermissions.getGrantedPermissions().contains('android.permission.READ_EXTERNAL_STORAGE')))
			CoolUtil.showPopUp(LanguageBasic.getPhrase('permissions_message', 'If you accepted the permissions you are all good!\nIf you didn\'t then expect a crash\nPress OK to see what happens'),
				LanguageBasic.getPhrase('mobile_notice', "Notice!"));

		try
		{
			if (!FileSystem.exists(StorageUtil.getStorageDirectory()))
				FileSystem.createDirectory(StorageUtil.getStorageDirectory());
		}
		catch (e:Dynamic)
		{
			CoolUtil.showPopUp(LanguageBasic.getPhrase('create_directory_error', 'Please create directory to\n{1}\nPress OK to close the game', [StorageUtil.getStorageDirectory()]), LanguageBasic.getPhrase('mobile_error', "Error!"));
			lime.system.System.exit(1);
		}

		try
		{
			if (!FileSystem.exists(StorageUtil.getExternalStorageDirectory() + 'mods'))
				FileSystem.createDirectory(StorageUtil.getExternalStorageDirectory() + 'mods');
		}
		catch (e:Dynamic)
		{
			CoolUtil.showPopUp(LanguageBasic.getPhrase('create_directory_error', 'Please create directory to\n{1}\nPress OK to close the game', [StorageUtil.getExternalStorageDirectory()]), LanguageBasic.getPhrase('mobile_error', "Error!"));
			lime.system.System.exit(1);
		}
	}
	#end
}
