package backend;

import lime.utils.Assets;
import openfl.utils.Assets as OpenFlAssets;
import haxe.Json;

typedef WeekFile =
{
	// JSON variables
	var songs:Array<Dynamic>;
	var weekCharacters:Array<String>;
	var weekBackground:String;
	var weekBefore:String;
	var storyName:String;
	var weekName:String;
	var startUnlocked:Bool;
	var hiddenUntilUnlocked:Bool;
	var hideStoryMode:Bool;
	var hideFreeplay:Bool;
	var difficulties:String;
}

class WeekData {
	public static var weeksLoaded:Map<String, WeekData> = new Map<String, WeekData>();
	public static var weeksList:Array<String> = [];
	private static var loadedFiles:Map<String, Bool> = new Map();
	#if MODS_ALLOWED
	public static var fileCache:Map<String, {data:WeekFile, mtime:Float}> = new Map();

	// reloadWeekFiles 跨会话缓存：enabled mod 列表没变且 isStoryMode 没变时，
	// 直接返回上次扫描结果，跳过 O(N) 次目录遍历 + JSON 解析。
	private static var _lastReloadKey:String = null;

	/// 失效 reloadWeekFiles 缓存。退出 Freeplay 时调，下次进入会重新全量扫描。
	public static function _invalidateReloadCache():Void
	{
		_lastReloadKey = null;
		weeksList = [];
		weeksLoaded.clear();
		loadedFiles = new Map();
	}
	#end
	public var folder:String = '';

	// JSON variables
	public var songs:Array<Dynamic>;
	public var weekCharacters:Array<String>;
	public var weekBackground:String;
	public var weekBefore:String;
	public var storyName:String;
	public var weekName:String;
	public var startUnlocked:Bool;
	public var hiddenUntilUnlocked:Bool;
	public var hideStoryMode:Bool;
	public var hideFreeplay:Bool;
	public var difficulties:String;

	public var fileName:String;

	public static function createWeekFile():WeekFile {
		var weekFile:WeekFile = {
			songs: [["Bopeebo", "face", [146, 113, 253]], ["Fresh", "face", [146, 113, 253]], ["Dad Battle", "face", [146, 113, 253]]],
			#if BASE_GAME_FILES
			weekCharacters: ['dad', 'bf', 'gf'],
			#else
			weekCharacters: ['bf', 'bf', 'gf'],
			#end
			weekBackground: 'stage',
			weekBefore: 'tutorial',
			storyName: 'Your New Week',
			weekName: 'Custom Week',
			startUnlocked: true,
			hiddenUntilUnlocked: false,
			hideStoryMode: false,
			hideFreeplay: false,
			difficulties: ''
		};
		return weekFile;
	}

	// HELP: Is there any way to convert a WeekFile to WeekData without having to put all variables there manually? I'm kind of a noob in haxe lmao
	public function new(weekFile:WeekFile, fileName:String) {
		// here ya go - MiguelItsOut
		for (field in Reflect.fields(weekFile))
			if(Reflect.fields(this).contains(field)) // Reflect.hasField() won't fucking work :/
				Reflect.setProperty(this, field, Reflect.getProperty(weekFile, field));

		this.fileName = fileName;
	}

	public static function reloadWeekFiles(isStoryMode:Null<Bool> = false)
	{
		#if MODS_ALLOWED
		// 跨会话缓存：enabled mod 列表 + isStoryMode 没变 → 跳过全量扫描
		var cacheKey:String = _buildReloadCacheKey(isStoryMode);
		if (_lastReloadKey != null && cacheKey == _lastReloadKey && weeksList.length > 0)
		{
			trace('[WEEKDATA] reloadWeekFiles: CACHE HIT (weeks=' + weeksList.length + ')');
			return;
		}
		trace('[WEEKDATA] reloadWeekFiles: CACHE MISS (full scan, modCount=' + Mods.getGlobalMods().length + ')');
		#end

		weeksList = [];
		weeksLoaded.clear();
		loadedFiles = new Map();
		#if MODS_ALLOWED
		var directories:Array<String> = [Paths.mods(), Paths.getSharedPath()];
		var originalLength:Int = directories.length;

		for (mod in Mods.parseList().enabled)
			directories.push(Paths.mods(mod + '/'));
		#else
		var directories:Array<String> = [Paths.getSharedPath()];
		var originalLength:Int = directories.length;
		#end

		var sexList:Array<String> = CoolUtil.coolTextFile(Paths.getSharedPath('weeks/weekList.txt'));
		for (i in 0...sexList.length) {
			for (j in 0...directories.length) {
				var fileToCheck:String = directories[j] + 'weeks/' + sexList[i] + '.json';
				if(loadedFiles.exists(fileToCheck)) continue;
				var week:WeekFile = getWeekFile(fileToCheck);
				if(week != null) {
					var newFolder:String = '';
					#if MODS_ALLOWED
					if(j >= originalLength) {
						newFolder = directories[j].substring(Paths.mods().length, directories[j].length-1);
					}
					#end

					var shouldAdd:Bool = (isStoryMode == null || (isStoryMode && !week.hideStoryMode) || (!isStoryMode && !week.hideFreeplay));
					if(!shouldAdd) continue;

					if(weeksLoaded.exists(sexList[i])) {
						mergeWeekSongs(weeksLoaded.get(sexList[i]), week, newFolder);
					} else {
						var weekFile:WeekData = new WeekData(week, sexList[i]);
						#if MODS_ALLOWED
						if(j >= originalLength) {
							weekFile.folder = newFolder;
						}
						#end
						weeksLoaded.set(sexList[i], weekFile);
						weeksList.push(sexList[i]);
					}
					loadedFiles.set(fileToCheck, true);
				}
			}
		}

		#if MODS_ALLOWED
		for (i in 0...directories.length) {
			var directory:String = directories[i] + 'weeks/';
			if(FileSystem.exists(directory)) {
				var listOfWeeks:Array<String> = CoolUtil.coolTextFile(directory + 'weekList.txt');
				for (daWeek in listOfWeeks)
				{
					var path:String = directory + daWeek + '.json';
					if(FileSystem.exists(path))
					{
						addWeek(daWeek, path, directories[i], i, originalLength);
					}
				}

				for (file in Paths.readDirectory(directory))
				{
					var path = haxe.io.Path.join([directory, file]);
					if (!FileSystem.isDirectory(path) && file.endsWith('.json'))
					{
						addWeek(file.substr(0, file.length - 5), path, directories[i], i, originalLength);
					}
				}
			}
		}
		#end

		#if MODS_ALLOWED
		_lastReloadKey = cacheKey;
		#end
	}

	#if MODS_ALLOWED
	/// 构建 reloadWeekFiles 的缓存 key：enabled mod 列表（Mods.globalMods） + isStoryMode。
	/// mod 启用状态没变 + 筛选模式没变 → 直接复用上次结果，跳过全量目录扫描 + JSON 解析。
	private static function _buildReloadCacheKey(isStoryMode:Null<Bool> = false):String
	{
		// 直接用 Mods.globalMods —— 已经是 parseList() 解析好的 enabled mod 列表，零 IO 开销
		var mods:Array<String> = Mods.getGlobalMods();
		var flag:String = (isStoryMode == null) ? 'null' : (isStoryMode ? 'story' : 'free');
		return mods.join(',') + '|' + flag;
	}
	#end

	private static function addWeek(weekToCheck:String, path:String, directory:String, i:Int, originalLength:Int)
	{
		if(loadedFiles.exists(path)) return;
		var week:WeekFile = getWeekFile(path);
		if(week != null)
		{
			var newFolder:String = '';
			if(i >= originalLength)
			{
				#if MODS_ALLOWED
				newFolder = directory.substring(Paths.mods().length, directory.length-1);
				#end
			}

			var shouldAdd:Bool = (PlayState.isStoryMode && !week.hideStoryMode) || (!PlayState.isStoryMode && !week.hideFreeplay);
			if(!shouldAdd) return;

			if(weeksLoaded.exists(weekToCheck)) {
				mergeWeekSongs(weeksLoaded.get(weekToCheck), week, newFolder);
			} else {
				var weekFile:WeekData = new WeekData(week, weekToCheck);
				if(i >= originalLength)
				{
					#if MODS_ALLOWED
					weekFile.folder = newFolder;
					#end
				}
				weeksLoaded.set(weekToCheck, weekFile);
				weeksList.push(weekToCheck);
			}
			loadedFiles.set(path, true);
		}
	}

	private static function mergeWeekSongs(existingWeek:WeekData, newWeekFile:WeekFile, newFolder:String):Void
	{
		for (song in newWeekFile.songs)
		{
			var songName:String = song[0];
			var alreadyExists:Bool = false;
			for (existingSong in existingWeek.songs)
			{
				if (existingSong[0] == songName)
				{
					alreadyExists = true;
					break;
				}
			}
			if (!alreadyExists)
			{
				var newSong:Array<Dynamic> = song.copy();
				if(newFolder != null && newFolder.length > 0)
				{
					newSong.push(newFolder);
				}
				existingWeek.songs.push(newSong);
			}
		}
	}

private static function getWeekFile(path:String):WeekFile {
		var rawJson:String = null;
		var currentMTime:Float = 0;
		
#if MODS_ALLOWED
		if(FileSystem.exists(path)) {
			// 检查文件修改时间，判断是否需要重新加载
			var stat = FileSystem.stat(path);
			if (stat != null && Reflect.hasField(stat, 'mtime')) {
				var mtime = Reflect.field(stat, 'mtime');
				currentMTime = Std.isOfType(mtime, Date) ? mtime.getTime() : Std.parseFloat(Std.string(mtime));
			}
			
			// 如果缓存存在且文件未修改，直接使用缓存
			if (fileCache.exists(path)) {
				var cached = fileCache.get(path);
				if (cached != null && cached.mtime == currentMTime) {
					return cached.data;
				}
			}
			
			rawJson = File.getContent(path);
		}
		#else
		if(OpenFlAssets.exists(path)) {
			rawJson = Assets.getText(path);
		}
		#end

		if(rawJson != null && rawJson.length > 0) {
			var parsedData = cast tjson.TJSON.parse(rawJson);
		#if MODS_ALLOWED
			// 缓存解析后的数据
			fileCache.set(path, {data: parsedData, mtime: currentMTime});
		#end
			return parsedData;
		}
		return null;
	}

	//   FUNCTIONS YOU WILL PROBABLY NEVER NEED TO USE

	//To use on PlayState.hx or Highscore stuff
	public static function getWeekFileName():String {
		return weeksList[PlayState.storyWeek];
	}

	//Used on LoadingState, nothing really too relevant
	public static function getCurrentWeek():WeekData {
		return weeksLoaded.get(weeksList[PlayState.storyWeek]);
	}

	public static function setDirectoryFromWeek(?data:WeekData = null) {
		Mods.currentModDirectory = '';
		if(data != null && data.folder != null && data.folder.length > 0) {
			Mods.currentModDirectory = data.folder;
		}
	}
}
