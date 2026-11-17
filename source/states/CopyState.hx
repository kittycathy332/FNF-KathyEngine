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

package states;

#if COPYSTATE_ALLOWED
import states.TitleState;
import states.CommandLineLaunchState;
import states.EnhancedFlixelState;
import Main;
import lime.utils.Assets as LimeAssets;
import openfl.utils.Assets as OpenFLAssets;
import openfl.utils.ByteArray;
import haxe.io.Path;
import flixel.ui.FlxBar;
import flixel.ui.FlxBar.FlxBarFillDirection;
import lime.system.ThreadPool;

/**
 * ...
 * @author: Karim Akra
 */
class CopyState extends MusicBeatState
{
	private static final textFilesExtensions:Array<String> = ['ini', 'txt', 'xml', 'hxs', 'hx', 'lua', 'json', 'frag', 'vert'];
	public static final IGNORE_FOLDER_FILE_NAME:String = "CopyState-Ignore.txt";
	private static var directoriesToIgnore:Array<String> = [];
	public static var locatedFiles:Array<String> = [];
	public static var maxLoopTimes:Int = 0;

	public var loadingImage:FlxSprite;
	public var loadingBar:FlxBar;
	public var loadedText:FlxText;
	public var thread:ThreadPool;

	var failedFilesStack:Array<String> = [];
	var failedFiles:Array<String> = [];
	var shouldCopy:Bool = false;
	var canUpdate:Bool = true;
	var loopTimes:Int = 0;

	override function create()
	{
		locatedFiles = [];
		maxLoopTimes = 0;
		checkExistingFiles();
		if (maxLoopTimes <= 0)
		{
			gotoNextState();
			return;
		}

		CoolUtil.showPopUp("Seems like you have some missing files that are necessary to run the game\nPress OK to begin the copy process",
			LanguageBasic.getPhrase('mobile_notice', 'Notice!'));

		shouldCopy = true;

		add(new FlxSprite(0, 0).makeGraphic(FlxG.width, FlxG.height, 0xffcaff4d));

		loadingImage = new FlxSprite(0, 0, Paths.image('funkay'));
		loadingImage.setGraphicSize(0, FlxG.height);
		loadingImage.updateHitbox();
		loadingImage.screenCenter();
		add(loadingImage);

		loadingBar = new FlxBar(0, FlxG.height - 26, FlxBarFillDirection.LEFT_TO_RIGHT, FlxG.width, 26);
		loadingBar.setRange(0, maxLoopTimes);
		add(loadingBar);

		loadedText = new FlxText(loadingBar.x, loadingBar.y + 4, FlxG.width, '', 16);
		loadedText.setFormat(Paths.font("vcr.ttf"), 16, FlxColor.WHITE, CENTER);
		add(loadedText);

		thread = new ThreadPool(0, CoolUtil.getCPUThreadsCount());
		thread.doWork.add(function(poop)
		{
			for (file in locatedFiles)
			{
				loopTimes++;
				copyAsset(file);
			}
		});
		new FlxTimer().start(0.5, (tmr) ->
		{
			thread.queue({});
		});

		super.create();
	}

	override function update(elapsed:Float)
	{
		if (shouldCopy)
		{
			if (loopTimes >= maxLoopTimes && canUpdate)
			{
				if (failedFiles.length > 0)
				{
					CoolUtil.showPopUp(failedFiles.join('\n'), 'Failed To Copy ${failedFiles.length} File.');
					final folder:String = #if android StorageUtil.getExternalStorageDirectory() + #else Sys.getCwd() + #end
					'logs/';
					if (!FileSystem.exists(folder))
						FileSystem.createDirectory(folder);
					File.saveContent(folder + Date.now().toString().replace(' ', '-').replace(':', "'") + '-CopyState' + '.txt', failedFilesStack.join('\n'));
				}

				FlxG.sound.play(Paths.sound('confirmMenu')).onComplete = () ->
				{
					gotoNextState();
				};

				canUpdate = false;
			}

			if (loopTimes >= maxLoopTimes)
				loadedText.text = "Completed!";
			else
				loadedText.text = '$loopTimes/$maxLoopTimes';

			loadingBar.percent = Math.min((loopTimes / maxLoopTimes) * 100, 100);
		}
		super.update(elapsed);
	}

	public function copyAsset(file:String)
	{
		var path:String = file;
		#if android
		if (file.startsWith('mods/'))
			path = StorageUtil.getExternalStorageDirectory() + file;
		#end

		if (!FileSystem.exists(path))
		{
			var directory = Path.directory(path);
			if (!FileSystem.exists(directory))
				FileSystem.createDirectory(directory);
			try
			{
				if (OpenFLAssets.exists(getFile(file)))
				{
					if (textFilesExtensions.contains(Path.extension(file)))
					createContentFromInternal(file);
				else
				{
					File.saveBytes(path, getFileBytes(getFile(file)));
				}
				}
				else
				{
					failedFiles.push(getFile(file) + " (File Dosen't Exist)");
					failedFilesStack.push('Asset ${getFile(file)} does not exist.');
				}
			}
			catch (e:haxe.Exception)
			{
				failedFiles.push('${getFile(file)} (${e.message})');
				failedFilesStack.push('${getFile(file)} (${e.stack})');
			}
		}
	}

	public function createContentFromInternal(file:String)
	{
		var fileName = Path.withoutDirectory(file);
		var directory = Path.directory(file);
		#if android
		if (file.startsWith('mods/'))
			directory = StorageUtil.getExternalStorageDirectory() + directory;
		#end
		try
		{
			var fileData:String = OpenFLAssets.getText(getFile(file));
			if (fileData == null)
				fileData = '';
			if (!FileSystem.exists(directory))
				FileSystem.createDirectory(directory);
			File.saveContent(Path.join([directory, fileName]), fileData);
		}
		catch (e:haxe.Exception)
		{
			failedFiles.push('${getFile(file)} (${e.message})');
			failedFilesStack.push('${getFile(file)} (${e.stack})');
		}
	}

	public function getFileBytes(file:String):ByteArray
	{
		switch (Path.extension(file).toLowerCase())
		{
			case 'otf' | 'ttf':
				return ByteArray.fromFile(file);
			default:
				// OpenFLAssets.getBytes() 只按 BINARY 类型取值，而 png/ogg/jpg 等
				// 在资源清单里注册为 IMAGE/SOUND，取不到时会返回 null —— 这正是
				// 「Failed To Copy ... (Null Object Reference)」的来源。
				// 先用 getPath() 拿到真实路径直接读；读不到再退回 getBytes()。
				// 注意 getFile() 可能返回 "library:assets/..." 形式，getPath 对前缀
				// 解析失败时，去掉前缀用裸路径再试一次。
				var realPath:String = null;
				try
				{
					realPath = OpenFLAssets.getPath(file);
				}
				catch (e:Dynamic) {}

				if ((realPath == null || realPath.length == 0) && file.indexOf(':') >= 0)
				{
					var barePath:String = file.substr(file.indexOf(':') + 1);
					try
					{
						realPath = OpenFLAssets.getPath(barePath);
					}
					catch (e:Dynamic) {}
				}

				if (realPath != null && realPath.length > 0)
				{
					try
					{
						if (FileSystem.exists(realPath))
							return ByteArray.fromBytes(File.getBytes(realPath));
					}
					catch (e:Dynamic) {}
				}

				// 最后才尝试 getBytes()，带前缀失败则用裸 id 再试，并显式判空，
				// 避免把 null 交给 File.saveBytes
				var bytes:ByteArray = null;
				try
				{
					bytes = OpenFLAssets.getBytes(file);
				}
				catch (e:Dynamic) {}

				if (bytes == null && file.indexOf(':') >= 0)
				{
					try
					{
						bytes = OpenFLAssets.getBytes(file.substr(file.indexOf(':') + 1));
					}
					catch (e:Dynamic) {}
				}

				if (bytes == null)
					throw 'No bytes available for "$file" (path: $realPath)';

				return bytes;
		}
	}

	public static function getFile(file:String):String
	{
		if (OpenFLAssets.exists(file))
			return file;

		@:privateAccess
		for (library in LimeAssets.libraries.keys())
		{
			if (OpenFLAssets.exists('$library:$file') && library != 'default')
				return '$library:$file';
		}

		return file;
	}

	private function gotoNextState():Void
	{
		// 移动端此处是初始状态，且早于 postGameStart，故需先（同步）加载一次完整设置，
		// 否则 ClientPrefs.data.splashMode 仍是默认值 'Kathy'，导致设置里的启动画面失效。
		// 此处作为 FlxState 的回调运行，FlxG.sound / Controls.instance 均已就绪，loadPrefs 安全。
		ClientPrefs.loadPrefs();

		#if MODS_ALLOWED
		if (Main.commandLineLaunch != null)
		{
			CommandLineLaunchState.launchData = Main.commandLineLaunch;
		}
		#end

		// 开屏画面跟随设置中的 splashMode（上面已 loadPrefs 加载最新值）。
		// 命令行直启时，由对应的开屏结束态(LogoState / TitleState / EnhancedFlixelState)负责跳转进歌。
		var splashMode:String = ClientPrefs.data.splashMode;
		switch (splashMode)
		{
			case 'Flixel', 'None':
				// 拷贝流程无法再显示 Flixel 自带 splash，直接进入标题（标题会按命令行参数重定向）
				#if MODS_ALLOWED
				if (Main.commandLineLaunch != null)
				{
					MusicBeatState.switchState(new CommandLineLaunchState());
					return;
				}
				#end
				MusicBeatState.switchState(new TitleState());
			case 'Flixel+':
				MusicBeatState.switchState(new EnhancedFlixelState());
			default: // 'Kathy'
				MusicBeatState.switchState(new LogoState());
		}
	}

	public static function checkExistingFiles():Bool
	{
		locatedFiles = OpenFLAssets.list();

		// removes unwanted assets
		var assets = locatedFiles.filter(folder -> folder.startsWith('assets/'));
		var mods = locatedFiles.filter(folder -> folder.startsWith('mods/'));
		locatedFiles = assets.concat(mods);

		// Check file existence with correct paths per platform
		locatedFiles = locatedFiles.filter(function(file) {
			var checkPath:String = file;
			#if android
			if (file.startsWith('mods/'))
				checkPath = StorageUtil.getExternalStorageDirectory() + file;
			#end
			return !FileSystem.exists(checkPath);
		});

		var filesToRemove:Array<String> = [];

		for (file in locatedFiles)
		{
			if (filesToRemove.contains(file))
				continue;

			if (file.endsWith(IGNORE_FOLDER_FILE_NAME) && !directoriesToIgnore.contains(Path.directory(file)))
				directoriesToIgnore.push(Path.directory(file));

			if (directoriesToIgnore.length > 0)
			{
				for (directory in directoriesToIgnore)
				{
					if (file.startsWith(directory))
						filesToRemove.push(file);
				}
			}
		}

		locatedFiles = locatedFiles.filter(file -> !filesToRemove.contains(file));

		maxLoopTimes = locatedFiles.length;

		return (maxLoopTimes <= 0);
	}

	public static function clearCopiedFiles():{deleted:Int, failed:Int}
	{
		var allFiles = OpenFLAssets.list();
		var assets = allFiles.filter(folder -> folder.startsWith('assets/'));
		var mods = allFiles.filter(folder -> folder.startsWith('mods/'));
		var files = assets.concat(mods);

		var filesToRemove:Array<String> = [];

		// Apply the same ignore logic as checkExistingFiles
		var dirsToIgnore:Array<String> = [];
		for (file in files)
		{
			if (file.endsWith(IGNORE_FOLDER_FILE_NAME) && !dirsToIgnore.contains(Path.directory(file)))
				dirsToIgnore.push(Path.directory(file));
		}
		for (file in files)
		{
			for (directory in dirsToIgnore)
			{
				if (file.startsWith(directory))
					filesToRemove.push(file);
			}
		}
		files = files.filter(file -> !filesToRemove.contains(file));

		var deletedCount:Int = 0;
		var failedCount:Int = 0;
		var directoriesToCheck:Array<String> = [];
		var modDirectoriesToCheck:Array<String> = [];

		for (file in files)
		{
			var path:String = file;
			var isModFile:Bool = file.startsWith('mods/');
			#if android
			if (isModFile)
				path = StorageUtil.getExternalStorageDirectory() + file;
			#end

			if (FileSystem.exists(path))
			{
				try
				{
					FileSystem.deleteFile(path);
					deletedCount++;

					var dir = haxe.io.Path.directory(path);
					if (dir != null && dir.length > 0)
					{
						if (isModFile)
						{
							// 模组目录下只清理叶子目录（如 mods/engine/），避免误删用户的 mods/ 根目录
							if (!modDirectoriesToCheck.contains(dir))
								modDirectoriesToCheck.push(dir);
						}
						else
						{
							if (!directoriesToCheck.contains(dir))
								directoriesToCheck.push(dir);
						}
					}
				}
				catch (e:haxe.Exception)
				{
					failedCount++;
				}
			}
		}

		// Clean up empty directories for assets files (internal storage, safe to clean)
		directoriesToCheck.sort((a, b) -> b.length - a.length);
		for (dir in directoriesToCheck)
		{
			try
			{
				if (FileSystem.exists(dir))
				{
					var entries = FileSystem.readDirectory(dir);
					if (entries.length == 0)
						FileSystem.deleteDirectory(dir);
				}
			}
			catch (e:haxe.Exception)
			{
				// Ignore directory cleanup failures
			}
		}

		// Clean up empty directories for mod files, but never touch the mods/ root directory
		modDirectoriesToCheck.sort((a, b) -> b.length - a.length);
		for (dir in modDirectoriesToCheck)
		{
			try
			{
				// Never delete the mods/ root directory itself
				if (dir.endsWith('mods') || dir.endsWith('mods/'))
					continue;

				if (FileSystem.exists(dir))
				{
					var entries = FileSystem.readDirectory(dir);
					if (entries.length == 0)
						FileSystem.deleteDirectory(dir);
				}
			}
			catch (e:haxe.Exception)
			{
				// Ignore directory cleanup failures
			}
		}

		return {deleted: deletedCount, failed: failedCount};
	}
}
#end
