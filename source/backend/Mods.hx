package backend;

import openfl.utils.Assets;

import haxe.Json;
import states.PlayState;

typedef ModsList = {
	enabled:Array<String>,
	disabled:Array<String>,
	all:Array<String>
};

class Mods
{
	static public var currentModDirectory:String = '';
	public static final ignoreModFolders:Array<String> = [
		'characters',
		'custom_events',
		'custom_notetypes',
		'data',
		'songs',
		'music',
		'sounds',
		'shaders',
		'videos',
		'images',
		'stages',
		'weeks',
		'fonts',
		'scripts',
		'achievements'
	];

	private static var globalMods:Array<String> = [];

	// directoriesWithFile 结果缓存，避免重复的 FileSystem.exists 调用
	static var _directoriesCache:Map<String, Array<String>> = null;

	// getModDirectories 结果缓存：模组列表运行中几乎不变，
	// 避免每次进歌/Freeplay 都 readDirectory 整个 mods 文件夹 + 逐目录 isDirectory（84 个模组时是固定开销）。
	static var _modDirectoriesCache:Null<Array<String>> = null;

	/// globalMods + mods 根 FileSystem.exists 结果缓存。
	/// key = 路径（不含 currentModDirectory 前缀），value = 是否存在。
	/// 独立于 currentModDirectory，所以 Freeplay 循环里切 currentModDirectory 也能持续命中。
	static var _globalExistsCache:Map<String, Bool> = new Map();

	public static function invalidateDirectoriesCache()
	{
		_directoriesCache = null;
		_modDirectoriesCache = null;
		_globalExistsCache = new Map();
		PlayState._songAudioModCache = null;
		Paths.clearAtlasCache();
		#if mobile
		Paths.clearModPathCache();
		#end
		ScriptPreload.invalidate();
	}

	/// 查 globalMods + mods 根里有没有这个路径，带缓存。
	/// 不考虑 currentModDirectory（那部分每次查一个目录，成本可忽略，由调用方单独处理）。
	public static function globalModsHas(modKey:String):Bool
	{
		return findInGlobalMods(modKey) != null;
	}

	/// 带缓存版的 modFolders globalMods 链遍历。
	/// 返回找到的完整路径（含 modsRoot + mod + '/' + modKey），没找到返回 null。
	/// 缓存命中时直接返回之前找到的结果，避免 N 次 FileSystem.exists。
	public static function findInGlobalMods(modKey:String):Null<String>
	{
		var modsRoot:String = #if android StorageUtil.getExternalStorageDirectory() + #else Sys.getCwd() + #end 'mods/';
		for(mod in globalMods)
		{
			var pth:String = modsRoot + mod + '/' + modKey;
			var exists:Bool;
			if (_globalExistsCache.exists(pth))
				exists = _globalExistsCache.get(pth);
			else
			{
				exists = FileSystem.exists(pth);
				_globalExistsCache.set(pth, exists);
			}
			if (exists) return pth;
		}
		// 也查 mods 根
		var rootPth:String = modsRoot + modKey;
		if (_globalExistsCache.exists(rootPth))
		{
			return _globalExistsCache.get(rootPth) ? rootPth : null;
		}
		var re:Bool = FileSystem.exists(rootPth);
		_globalExistsCache.set(rootPth, re);
		return re ? rootPth : null;
	}

	inline public static function getGlobalMods()
		return globalMods;

	inline public static function pushGlobalMods() // prob a better way to do this but idc
	{
		globalMods = [];
		invalidateDirectoriesCache();
		for(mod in parseList().enabled)
		{
			var pack:Dynamic = getPack(mod);
			if(pack != null && pack.runsGlobally) globalMods.push(mod);
		}
		return globalMods;
	}

	public static function getModDirectories():Array<String>
	{
		if (_modDirectoriesCache != null) return _modDirectoriesCache;
		var list:Array<String> = [];
		#if MODS_ALLOWED
		var modsFolder:String = Paths.mods();
		if(FileSystem.exists(modsFolder)) {
			for (folder in Paths.readDirectory(modsFolder))
			{
				var path = haxe.io.Path.join([modsFolder, folder]);
				if (FileSystem.isDirectory(path) && !ignoreModFolders.contains(folder.toLowerCase()) && !list.contains(folder))
					list.push(folder);
			}
		}
		#end
		_modDirectoriesCache = list;
		return list;
	}
	
	inline public static function mergeAllTextsNamed(path:String, ?defaultDirectory:String = null, allowDuplicates:Bool = false)
	{
		if(defaultDirectory == null) defaultDirectory = Paths.getSharedPath();
		defaultDirectory = defaultDirectory.trim();
		if(!defaultDirectory.endsWith('/')) defaultDirectory += '/';
		if(!defaultDirectory.startsWith('assets/')) defaultDirectory = 'assets/$defaultDirectory';

		var mergedList:Array<String> = [];
		var paths:Array<String> = directoriesWithFile(defaultDirectory, path);

		var defaultPath:String = defaultDirectory + path;
		if(paths.contains(defaultPath))
		{
			paths.remove(defaultPath);
			paths.insert(0, defaultPath);
		}

		for (file in paths)
		{
			var list:Array<String> = CoolUtil.coolTextFile(file);
			for (value in list)
				if((allowDuplicates || !mergedList.contains(value)) && value.length > 0)
					mergedList.push(value);
		}
		return mergedList;
	}

	inline public static function directoriesWithFile(path:String, fileToFind:String, mods:Bool = true)
	{
		if (_directoriesCache == null) _directoriesCache = [];
		var cacheKey:String = '$path|$fileToFind|$mods|${Paths.currentLevel}|$currentModDirectory|' + getGlobalMods().join(',');
		if (_directoriesCache.exists(cacheKey)) return _directoriesCache.get(cacheKey);

		var foldersToCheck:Array<String> = [];
		//Main folder
		if(FileSystem.exists(path + fileToFind))
			foldersToCheck.push(path + fileToFind);

		// Week folder
		if(Paths.currentLevel != null && Paths.currentLevel != path)
		{
			var pth:String = Paths.getFolderPath(fileToFind, Paths.currentLevel);
			if(!foldersToCheck.contains(pth) && FileSystem.exists(pth))
				foldersToCheck.push(pth);
		}

		#if MODS_ALLOWED
		if(mods)
		{
			// Global mods first
			for(mod in Mods.getGlobalMods())
			{
				var folder:String = Paths.mods(mod + '/' + fileToFind);
				if(FileSystem.exists(folder) && !foldersToCheck.contains(folder)) foldersToCheck.push(folder);
			}

			// Then "PsychEngine/mods/" main folder
			var folder:String = Paths.mods(fileToFind);
			if(FileSystem.exists(folder) && !foldersToCheck.contains(folder)) foldersToCheck.push(Paths.mods(fileToFind));

			// And lastly, the loaded mod's folder
			if(Mods.currentModDirectory != null && Mods.currentModDirectory.length > 0)
			{
				var folder:String = Paths.mods(Mods.currentModDirectory + '/' + fileToFind);
				if(FileSystem.exists(folder) && !foldersToCheck.contains(folder)) foldersToCheck.push(folder);
			}
		}
		#end
		_directoriesCache.set(cacheKey, foldersToCheck);
		return foldersToCheck;
	}

	public static function getPack(?folder:String = null):Dynamic
	{
		#if MODS_ALLOWED
		if(folder == null) folder = Mods.currentModDirectory;

		var path = Paths.mods(folder + '/pack.json');
		if(FileSystem.exists(path)) {
			try {
				#if sys
				var rawJson:String = File.getContent(path);
				#else
				var rawJson:String = Assets.getText(path);
				#end
				if(rawJson != null && rawJson.length > 0) return tjson.TJSON.parse(rawJson);
			} catch(e:Dynamic) {
				trace(e);
			}
		}
		#end
		return null;
	}

	public static var updatedOnState:Bool = false;
	inline public static function parseList():ModsList {
		if(!updatedOnState) updateModList();
		var list:ModsList = {enabled: [], disabled: [], all: []};

		#if MODS_ALLOWED
		try {
			for (mod in CoolUtil.coolTextFile(#if android StorageUtil.getExternalStorageDirectory() + #else Sys.getCwd() + #end 'modsList.txt'))
			{
				//trace('Mod: $mod');
				if(mod.trim().length < 1) continue;

				var dat = mod.split("|");
				list.all.push(dat[0]);
				if (dat[1] == "1")
					list.enabled.push(dat[0]);
				else
					list.disabled.push(dat[0]);
			}
		} catch(e) {
			trace(e);
		}
		#end
		return list;
	}
	
	private static function updateModList()
	{
		#if MODS_ALLOWED
		invalidateDirectoriesCache();
		// Find all that are already ordered
		var list:Array<Array<Dynamic>> = [];
		var added:Array<String> = [];
		try {
			for (mod in CoolUtil.coolTextFile(#if android StorageUtil.getExternalStorageDirectory() + #else Sys.getCwd() + #end 'modsList.txt'))
			{
				var dat:Array<String> = mod.split("|");
				var folder:String = dat[0];
				if(folder.trim().length > 0 && FileSystem.exists(Paths.mods(folder)) && FileSystem.isDirectory(Paths.mods(folder)) && !added.contains(folder))
				{
					added.push(folder);
					list.push([folder, (dat[1] == "1")]);
				}
			}
		} catch(e) {
			trace(e);
		}
		
		// Scan for folders that aren't on modsList.txt yet
		for (folder in getModDirectories())
		{
			if(folder.trim().length > 0 && FileSystem.exists(Paths.mods(folder)) && FileSystem.isDirectory(Paths.mods(folder)) &&
			!ignoreModFolders.contains(folder.toLowerCase()) && !added.contains(folder))
			{
				added.push(folder);
				list.push([folder, true]); //i like it false by default. -bb //Well, i like it True! -Shadow Mario (2022)
				//Shadow Mario (2023): What the fuck was bb thinking
			}
		}

		// Now save file
		var fileStr:String = '';
		for (values in list)
		{
			if(fileStr.length > 0) fileStr += '\n';
			fileStr += values[0] + '|' + (values[1] ? '1' : '0');
		}

	File.saveContent(#if android StorageUtil.getExternalStorageDirectory() + #else Sys.getCwd() + #end 'modsList.txt', fileStr);
	CoolUtil.invalidateCoolTextFileCache(#if android StorageUtil.getExternalStorageDirectory() + #else Sys.getCwd() + #end 'modsList.txt');
	updatedOnState = true;
		//trace('Saved modsList.txt');
		#end
	}

	public static function loadTopMod()
	{
		Mods.currentModDirectory = '';
		
		#if MODS_ALLOWED
		var list:Array<String> = Mods.parseList().enabled;
		if(list != null && list[0] != null)
			Mods.currentModDirectory = list[0];
		#end
	}
}
