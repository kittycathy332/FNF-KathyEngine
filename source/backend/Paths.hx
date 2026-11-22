package backend;

import flixel.graphics.frames.FlxFrame.FlxFrameAngle;
import flixel.graphics.frames.FlxAtlasFrames;
import flixel.graphics.FlxGraphic;
import flixel.math.FlxRect;
import flixel.system.FlxAssets;

import openfl.display.BitmapData;
import openfl.display3D.textures.RectangleTexture;
import openfl.utils.AssetType;
import openfl.utils.Assets as OpenFlAssets;
import openfl.system.System;
import openfl.geom.Rectangle;

import lime.utils.Assets;
import flash.media.Sound;

import haxe.Json;


#if MODS_ALLOWED
import backend.Mods;
#end

// 主菜单音乐样式：key=唯一标识(音频文件后缀)，display=设置里显示的选项名，audio=实际播放的文件(不含扩展)，bpm=对应 BPM(<=0 表示未指定)
typedef MenuMusicStyle = { key:String, display:String, audio:String, bpm:Float }

@:access(openfl.display.BitmapData)
class Paths
{
	inline public static var SOUND_EXT = #if web "mp3" #else "ogg" #end;
	inline public static var VIDEO_EXT = "mp4";

	// 按上下文标签分组的资源保护。调用者在登记时带上 tag（如 'freeplay'、'loading'），
	// 退出该上下文时用 clearExcludedByTag() 批量移除保护条目，随后 clearStoredMemory/
	// clearUnusedMemory 就能真正回收这些资源，避免全局永久泄漏。
	// 不传 tag 的调用走 legacy 路径，条目仍在 dumpExclusions 里（兼容现有未迁移的调用方）。
	public static var _excludedByTag:Map<String, Array<String>> = new Map();

	public static function excludeAsset(key:String, ?tag:String = null) {
		if (!dumpExclusions.contains(key))
			dumpExclusions.push(key);
		if (tag != null)
		{
			if (!_excludedByTag.exists(tag))
				_excludedByTag.set(tag, []);
			var bucket:Array<String> = _excludedByTag.get(tag);
			if (!bucket.contains(key))
				bucket.push(key);
		}
	}

	/// 按 tag 批量移除保护条目。移除后这些 key 不再出现在 dumpExclusions 里，
	/// 随后 clearStoredMemory/clearUnusedMemory 就能回收它们。
	public static function clearExcludedByTag(tag:String):Void
	{
		if (!_excludedByTag.exists(tag)) return;
		var bucket:Array<String> = _excludedByTag.get(tag);
		for (key in bucket)
		{
			var idx:Int = dumpExclusions.indexOf(key);
			if (idx >= 0) dumpExclusions.splice(idx, 1);
		}
		_excludedByTag.remove(tag);
	}

	public static var dumpExclusions:Array<String> = ['assets/shared/music/freakyMenu.$SOUND_EXT', 'assets/shared/mobile/touchpad/bg.png'];
	// haya I love you for the base cache dump I took to the max
	public static function clearUnusedMemory()
	{
		// clear non local assets in the tracked assets list
		for (key in currentTrackedAssets.keys())
		{
			// if it is not currently contained within the used local assets
			if (!localTrackedAssets.contains(key) && !dumpExclusions.contains(key))
			{
				destroyGraphic(currentTrackedAssets.get(key)); // get rid of the graphic
				currentTrackedAssets.remove(key); // and remove the key from local cache map
			}
		}

		// 仅在原生 GC 开启时强制回收。
		// 注意：Gc.run()/System.gc() 不受 Gc.enable(false) 约束（hxcpp 的
		// InternalCollect 不检查 sgInternalEnable），所以必须在这里显式判断，
		// 否则关掉 GC 设置后游玩期间仍会被这里强制停顿一次。
		// 关闭 GC 时只做资源解引用，贴图/音频仍按上面的逻辑正常释放。
		if (ClientPrefs.data == null || ClientPrefs.data.garbageCollectorEnabled)
		{
			#if debug
			var st = flixel.FlxG.state;
			var stateName = st != null ? Type.getClassName(Type.getClass(st)) : "null";
			var assetCount = 0;
			for (_ in currentTrackedAssets.keys()) assetCount++;
			var soundCount = 0;
			for (_ in currentTrackedSounds.keys()) soundCount++;
			trace('[GC] 主动完整回收 @ ${Math.round(haxe.Timer.stamp() * 1000)}ms state=$stateName trackedAssets=$assetCount trackedSounds=$soundCount');
			#end
			System.gc();
			#if cpp
			cpp.NativeGc.run(true);
			#end
		}
	}

	// define the locally tracked assets
	public static var localTrackedAssets:Array<String> = [];

	// 去重登记"本状态仍在使用"的资源 key。
	// 原实现是每次 image()/returnSound()（哪怕命中缓存）都 push，导致 localTrackedAssets
	// 在浏览期间无限堆积重复条目，且让 clearStoredMemory/clearUnusedMemory 的 contains 恒真，
	// 永远释放不了任何资源。改为仅在首次出现时登记。
	public static function trackLocalAsset(key:String):Void
	{
		if (key == null || key.length == 0) return;
		if (!localTrackedAssets.contains(key))
			localTrackedAssets.push(key);
	}

	// 仅判断歌曲音频文件是否存在，绝不加载/解码。
	// 用于 FreeplayState 的 modHasAudio 存在性探测：原实现直接 loadSongAudio，
	// 会把整段 Inst/Voices 解码进 currentTrackedSounds 且不登记释放，浏览期间只增不减。
	public static function songAudioExists(song:String, fileBase:String, ?modDir:String = ''):Bool
	{
		var path:String = getSongAudioPath(song, fileBase, modDir);
		#if sys
		return FileSystem.exists(path);
		#else
		return OpenFlAssets.exists(path, SOUND);
		#end
	}

	@:access(flixel.system.frontEnds.BitmapFrontEnd._cache)
	public static function clearStoredMemory()
	{
		// clear anything not in the tracked assets list
		for (key in FlxG.bitmap._cache.keys())
		{
			if (!currentTrackedAssets.exists(key))
				destroyGraphic(FlxG.bitmap.get(key));
		}

		// clear all sounds that are cached
		for (key => asset in currentTrackedSounds)
		{
			if (!localTrackedAssets.contains(key) && !dumpExclusions.contains(key) && asset != null)
			{
				Assets.cache.clear(key);
				currentTrackedSounds.remove(key);
				var lruIdx:Int = _soundLru.indexOf(key);
				if (lruIdx >= 0) _soundLru.splice(lruIdx, 1);
			}
		}
		// flags everything to be cleared out next unused memory clear
		localTrackedAssets = [];
		// Sparrow/Packer atlas 缓存也一并释放（下次 getSparrowAtlas 会重建，代价只是再 parse XML）
		_atlasCache = new Map();
		#if !html5 openfl.Assets.cache.clear("songs"); #end
	}

	/**
	 * 核弹选项（Shift+F9）：解除所有资源保护并销毁全部缓存资源，包括 freakyMenu 等默认保护项。
	 * 与 clearStoredMemory 的区别：那个保留 dumpExclusions/localTrackedAssets 里的资源，
	 * 这个连保护项一起清。调用方随后必须重载 state 重建所需资源，否则画面/音乐会缺资源。
	 * 不在这里调 GC，由调用方统一在解引用后跑一次完整回收。
	 */
	@:access(flixel.system.frontEnds.BitmapFrontEnd._cache)
	public static function clearAllMemory(?protect:Array<flixel.graphics.FlxGraphic>)
	{
		// 兼容旧的单个 graphic 传参
		if (protect == null) protect = [];

		// 解除所有保护：默认项 + 按 tag 登记的项 + 本地在用标记
		dumpExclusions = [];
		_excludedByTag = new Map();
		localTrackedAssets = [];

		function isProtected(g:FlxGraphic):Bool
		{
			if (g == null) return false;
			for (p in protect) if (p == g) return true;
			return false;
		}

		// 销毁所有被跟踪的贴图（跳过需要保护的，例如正在显示的转场图/遮罩）
		for (key in currentTrackedAssets.keys())
		{
			var g = currentTrackedAssets.get(key);
			if (!isProtected(g)) destroyGraphic(g);
		}
		// 保护图仍保留在当前追踪表里（否则下次 image() 命中已 remove 的条目会异常），其余清空
		var keep:Map<String, FlxGraphic> = [];
		for (key in currentTrackedAssets.keys())
		{
			var g = currentTrackedAssets.get(key);
			if (isProtected(g)) keep.set(key, g);
		}
		currentTrackedAssets = keep;

		// 清掉所有被跟踪的音频
		for (key in currentTrackedSounds.keys())
		{
			if (currentTrackedSounds.get(key) != null)
				Assets.cache.clear(key);
		}
		currentTrackedSounds = [];
		_soundLru = [];

		// FlxG.bitmap 里的其它图形、atlas 缓存、资源缓存全清（同样跳过保护图）
		for (key in FlxG.bitmap._cache.keys())
		{
			var g = FlxG.bitmap.get(key);
			if (!isProtected(g)) destroyGraphic(g);
		}
		_atlasCache = new Map();
		#if !html5 openfl.Assets.cache.clear("songs"); #end
	}

	public static function freeGraphicsFromMemory()
	{
		var protectedGfx:Array<FlxGraphic> = [];
		function checkForGraphics(spr:Dynamic)
		{
			try
			{
				var grp:Array<Dynamic> = Reflect.getProperty(spr, 'members');
				if(grp != null)
				{
					//trace('is actually a group');
					for (member in grp)
					{
						checkForGraphics(member);
					}
					return;
				}
			}

			//trace('check...');
			try
			{
				var gfx:FlxGraphic = Reflect.getProperty(spr, 'graphic');
				if(gfx != null)
				{
					protectedGfx.push(gfx);
					//trace('gfx added to the list successfully!');
				}
			}
			//catch(haxe.Exception) {}
		}

		for (member in FlxG.state.members)
			checkForGraphics(member);

		if(FlxG.state.subState != null)
			for (member in FlxG.state.subState.members)
				checkForGraphics(member);

		for (key in currentTrackedAssets.keys())
		{
			// if it is not currently contained within the used local assets
			if (!dumpExclusions.contains(key))
			{
				var graphic:FlxGraphic = currentTrackedAssets.get(key);
				if(!protectedGfx.contains(graphic))
				{
					destroyGraphic(graphic); // get rid of the graphic
					currentTrackedAssets.remove(key); // and remove the key from local cache map
					//trace('deleted $key');
				}
			}
		}
	}

	inline static function destroyGraphic(graphic:FlxGraphic)
	{
		// free some gpu memory
		if (graphic != null && graphic.bitmap != null && graphic.bitmap.__texture != null)
			graphic.bitmap.__texture.dispose();
		FlxG.bitmap.remove(graphic);
	}



	static public var currentLevel:String;
	static public function setCurrentLevel(name:String)
		currentLevel = name.toLowerCase();

	// getPath 解析结果缓存（进入编谱器卡住 96s 的修复）：
	// 553 个事件各构造一次 FlxText → Paths.font() → getPath() → modFolders()+FileSystem.exists()
	// 同步磁盘查询，即使资源早已加载过。解析结果只依赖入参 + 当前 mod 目录 + 当前关卡 +
	// 语言（已翻译进 file），命中后直接返回，彻底消除热路径的重复磁盘 I/O。
	// 切模组时 clearModPathCache() 会清空；编辑器里新建文件后若需立即生效，也走该清理。
	static var _pathResolveCache:Map<String, String> = new Map();

	public static function getPath(file:String, ?type:AssetType = TEXT, ?parentfolder:String, ?modsAllowed:Bool = true):String
	{
		var resolveKey:String = file + '|' + type + '|' + parentfolder + '|' + modsAllowed + '|'
			+ Mods.currentModDirectory + '|' + currentLevel;
		var cachedPath:String = _pathResolveCache.get(resolveKey);
		if (cachedPath != null) return cachedPath;

		var result:String = getPathUncached(file, type, parentfolder, modsAllowed);
		_pathResolveCache.set(resolveKey, result);
		return result;
	}

	static function getPathUncached(file:String, ?type:AssetType = TEXT, ?parentfolder:String, ?modsAllowed:Bool = true):String
	{
		#if MODS_ALLOWED
		if(modsAllowed)
		{
			var customFile:String = file;
			if (parentfolder != null) customFile = '$parentfolder/$file';

			var modded:String = modFolders(customFile);
			if(FileSystem.exists(modded)) return modded;
		}
		#end
		if(parentfolder == "mobile")
			return getSharedPath('mobile/$file');

		if (parentfolder != null)
			return getFolderPath(file, parentfolder);

		if (currentLevel != null && currentLevel != 'shared')
		{
			var levelPath = getFolderPath(file, currentLevel);
			if (OpenFlAssets.exists(levelPath, type))
				return levelPath;
		}
		return getSharedPath(file);
	}

	inline static public function getFolderPath(file:String, folder = "shared")
		return 'assets/$folder/$file';

inline public static function getSharedPath(file:String = '')
	return 'assets/shared/$file';

	static function extractModFromPath(path:String):String
	{
		#if MODS_ALLOWED
		if (path.startsWith(mods())) {
			var modsPrefix = mods();
			var relativePath = path.substring(modsPrefix.length);
			var slashIndex = relativePath.indexOf('/');
			if (slashIndex > 0) {
				return relativePath.substring(0, slashIndex);
			}
		}
		#end
		return 'shared';
	}

	static function generateCacheKey(path:String):String
	{
		var mod = extractModFromPath(path);
		var relativePath = path;
		#if MODS_ALLOWED
		if (mod != 'shared') {
			var modsPrefix = mods();
			relativePath = path.substring(modsPrefix.length + mod.length + 1);
		} else if (path.startsWith('assets/')) {
			relativePath = path.substring(7);
		}
		#end
		return '$mod:$relativePath';
	}

	inline static public function txt(key:String, ?folder:String)
		return getPath('data/$key.txt', TEXT, folder, true);

	inline static public function xml(key:String, ?folder:String)
		return getPath('data/$key.xml', TEXT, folder, true);

	inline static public function json(key:String, ?folder:String)
		return getPath('data/$key.json', TEXT, folder, true);

	inline static public function shaderFragment(key:String, ?folder:String)
		return getPath('shaders/$key.frag', TEXT, folder, true);

	inline static public function shaderVertex(key:String, ?folder:String)
		return getPath('shaders/$key.vert', TEXT, folder, true);

	inline static public function lua(key:String, ?folder:String)
		return getPath('$key.lua', TEXT, folder, true);

	static public function video(key:String)
	{
		#if MODS_ALLOWED
		var file:String = modsVideo(key);
		if(FileSystem.exists(file)) return file;
		#end
		return 'assets/videos/$key.$VIDEO_EXT';
	}

	inline static public function sound(key:String, ?modsAllowed:Bool = true):Sound
		return returnSound('sounds/$key', modsAllowed);

	inline static public function music(key:String, ?modsAllowed:Bool = true):Sound
		return returnSound('music/$key', modsAllowed);

	// ===== 主菜单音乐「样式」系统 =====
	// 每个样式含三要素：display(设置里显示的选项名)、audio(实际播放的文件, 不含扩展)、bpm(对应 BPM, <=0 表示未指定走默认)。
	// 数据来源：assets 与各 mod 的 music 目录下 freakyMenu-* 音频自动发现 + freakyMenu-BPM.json 覆盖 display/audio/bpm。
	// 设置里保存 daMenuMusic = display 名；'Default'/'None' 使用标准 freakyMenu，保证原生 Psych 行为一致。

	inline static public function menuMusicName():String
		return resolveMenuMusicStyle(ClientPrefs.data.daMenuMusic).audio;

	// 设置里显示的菜单音乐选项名列表（'Default' 在最前）
	static public function availableMenuMusicNames():Array<String>
	{
		loadMenuMusicStyles();
		final out:Array<String> = ['Default'];
		for (style in cachedMenuMusicStyles)
			if (!out.contains(style.display))
				out.push(style.display);
		return out;
	}

	// 返回实际要播放的主菜单音乐：目标曲目存在则播，否则回退默认 freakyMenu
	static public function menuMusicAudio():Sound
	{
		var name:String = menuMusicName();
		#if sys
		if (FileSystem.exists(getPath('music/$name', SOUND) + '.$SOUND_EXT'))
			return returnSound('music/$name');
		#else
		if (OpenFlAssets.exists('music/$name.$SOUND_EXT', SOUND))
			return returnSound('music/$name');
		#end
		return returnSound('music/freakyMenu'); // 找不到则退回默认
	}

	// 返回当前所选菜单音乐样式的 BPM；未指定(<=0)时返回默认 BPM（调用方传入 gfDanceTitle 等兜底）
	static public function menuMusicBPM(?defaultBPM:Float = 102):Float
	{
		final bpm:Float = resolveMenuMusicStyle(ClientPrefs.data.daMenuMusic).bpm;
		return (bpm > 0) ? bpm : defaultBPM;
	}

	// ---------- 内部实现 ----------

	static var cachedMenuMusicNames:Array<String> = null;
	static var cachedMenuMusicStyles:Array<MenuMusicStyle> = null;
	static var cachedStyleByDisplay:Map<String, MenuMusicStyle> = null;
	static var cachedStyleByKey:Map<String, MenuMusicStyle> = null;

	static function defaultMenuMusicStyle():MenuMusicStyle
		return {key: 'Default', display: 'Default', audio: 'freakyMenu', bpm: -1};

	inline static public function isDefaultMenuMusic():Bool
	{
		final v:String = ClientPrefs.data.daMenuMusic;
		return v == null || v == '' || v == 'Default' || v == 'None';
	}

	static function resolveMenuMusicStyle(value:String):MenuMusicStyle
	{
		loadMenuMusicStyles();
		if (value == null || value == '' || value == 'Default' || value == 'None')
			return defaultMenuMusicStyle();
		var style:MenuMusicStyle = null;
		if (cachedStyleByDisplay != null && cachedStyleByDisplay.exists(value))
			style = cachedStyleByDisplay.get(value);
		if (style == null && cachedStyleByKey != null && cachedStyleByKey.exists(value))
			style = cachedStyleByKey.get(value);
		if (style == null) // 兼容旧存档：直接存了音频文件后缀（如 'Dave'）
			for (s in cachedMenuMusicStyles)
				if (s.key == value || s.audio == 'freakyMenu-' + value)
					return s;
		if (style == null) style = defaultMenuMusicStyle();
		return style;
	}

	static function addMenuMusicStyle(style:MenuMusicStyle)
	{
		cachedMenuMusicStyles.push(style);
		cachedStyleByKey.set(style.key, style);
		cachedStyleByDisplay.set(style.display, style);
	}

	static function loadMenuMusicStyles()
	{
		if (cachedMenuMusicStyles != null) return;
		cachedMenuMusicStyles = [];
		cachedStyleByKey = new Map();
		cachedStyleByDisplay = new Map();
		#if sys
		// 1. json 覆盖表（按 audio 文件后缀索引，mods 后到者覆盖）
		final overrides:Array<MenuMusicStyle> = [];
		collectMenuMusicBPMFiles(overrides);
		final byAudio:Map<String, MenuMusicStyle> = new Map();
		for (o in overrides)
			byAudio.set(o.audio, o);

		// 2. 自动发现音频文件，套用覆盖（无覆盖则按文件后缀生成默认样式）
		cachedMenuMusicNames = [];
		scanMenuMusicFolders();
		for (handle in cachedMenuMusicNames)
		{
			var ov:MenuMusicStyle = byAudio.get('freakyMenu-' + handle);
			if (ov == null) ov = byAudio.get(handle);
			registerMenuMusicStyle(handle, ov);
		}
		#end
	}

	#if sys
	static function registerMenuMusicStyle(handle:String, ovr:MenuMusicStyle)
	{
		final style:MenuMusicStyle = {
			key: handle,
			display: (ovr != null && ovr.display.length > 0) ? ovr.display : handle,
			audio: (ovr != null && ovr.audio.length > 0) ? ovr.audio : 'freakyMenu-' + handle,
			bpm: (ovr != null && ovr.bpm > 0) ? ovr.bpm : -1
		};
		addMenuMusicStyle(style);
	}

	// 读取 assets 与各 mod 的 freakyMenu-BPM.json，合并成有序覆盖列表
	static function collectMenuMusicBPMFiles(out:Array<MenuMusicStyle>)
	{
		parseMenuMusicBPMJson(menuMusicAssetsBase() + 'assets/shared/music/freakyMenu-BPM.json', out);
		#if MODS_ALLOWED
		parseMenuMusicBPMJson(menuMusicModsBase() + 'mods/music/freakyMenu-BPM.json', out);
		var modsDir:String = menuMusicModsBase() + 'mods';
		if (FileSystem.exists(modsDir) && FileSystem.isDirectory(modsDir))
			for (modFolder in FileSystem.readDirectory(modsDir))
				parseMenuMusicBPMJson(modsDir + '/' + modFolder + '/music/freakyMenu-BPM.json', out);
		#end
	}

	// JSON 格式：{ "key": { "display":?, "audio":?, "bpm":? } } 或简写 { "key": bpm }；# 开头的键视为注释
	static function parseMenuMusicBPMJson(path:String, out:Array<MenuMusicStyle>)
	{
		if (!FileSystem.exists(path)) return;
		try
		{
			final data:Dynamic = haxe.Json.parse(sys.io.File.getContent(path));
			for (key in Reflect.fields(data))
			{
				if (key.charAt(0) == '#') continue;
				final v:Dynamic = Reflect.field(data, key);
				var style:MenuMusicStyle = {key: key, display: key, audio: 'freakyMenu-' + key, bpm: -1};
				if (Std.isOfType(v, Float) || Std.isOfType(v, Int)) // 简写 { "key": bpm }
					style.bpm = v;
				else if (Std.isOfType(v, String))
					style.bpm = Std.parseFloat(Std.string(v));
				else if (v != null) // 对象形式 { display?, audio?, bpm? }
				{
					if (Reflect.hasField(v, 'display')) style.display = Std.string(Reflect.field(v, 'display'));
					if (Reflect.hasField(v, 'audio')) style.audio = Std.string(Reflect.field(v, 'audio'));
					if (Reflect.hasField(v, 'bpm')) style.bpm = Std.parseFloat(Std.string(Reflect.field(v, 'bpm')));
				}
				if (style.display.length == 0) style.display = key;
				if (style.audio.length == 0) style.audio = 'freakyMenu-' + key;
				out.push(style); // 后加载的（mods）会覆盖同名 audio
			}
		}
		catch(e:haxe.Exception) {}
	}

	// assets/shared 的实际根：与 getFolderPath 相对路径基准一致。
	// Android 上包内 assets 被 CopyState 用相对路径复制到应用私有目录(cwd)，故此处统一用 Sys.getCwd()。
	inline static function menuMusicAssetsBase():String
		return Sys.getCwd();

	// mods 根：Android 上 mods 被复制到外部存储，桌面则在工作目录。
	inline static function menuMusicModsBase():String
		return #if android StorageUtil.getExternalStorageDirectory() #else Sys.getCwd() #end;

	// 谱面编辑器备份目录：跟随存储位置（Android）/ 工作目录（桌面）。
	public static inline function backupsPath():String
		return #if android StorageUtil.getExternalStorageDirectory() #else Sys.getCwd() #end + 'backups/';

	static function scanMenuMusicFolders()
	{
		final dirs:Array<String> = [menuMusicAssetsBase() + 'assets/shared/music', menuMusicModsBase() + 'mods/music'];
		#if MODS_ALLOWED
		var modsDir:String = menuMusicModsBase() + 'mods';
		if (FileSystem.exists(modsDir) && FileSystem.isDirectory(modsDir))
			for (modFolder in FileSystem.readDirectory(modsDir))
				dirs.push(modsDir + '/' + modFolder + '/music');
		#end

		for (dir in dirs)
		{
			if (!FileSystem.exists(dir) || !FileSystem.isDirectory(dir)) continue;
			for (entry in FileSystem.readDirectory(dir))
			{
				if (entry.indexOf('freakyMenu-') != 0) continue;
				if (!isMenuMusicAudioEntry(entry)) continue; // 只识别音频，忽略 BPM.json 等
				final handle:String = menuMusicFileBaseName(entry);
				if (handle.length > 0 && !cachedMenuMusicNames.contains(handle))
					cachedMenuMusicNames.push(handle);
			}
		}
		cachedMenuMusicNames.sort(Reflect.compare);
	}

	// 是否为有效的菜单音乐音频（排除 .json/.txt/.ini 等）
	static inline function isMenuMusicAudioEntry(entry:String):Bool
	{
		final lower:String = entry.toLowerCase();
		return StringTools.endsWith(lower, '.ogg') || StringTools.endsWith(lower, '.mp3') || StringTools.endsWith(lower, '.wav');
	}

	// "freakyMenu-<名字>.ogg" -> "<名字>"
	static inline function menuMusicFileBaseName(entry:String):String
	{
		var name:String = entry.substr('freakyMenu-'.length);
		final dot:Int = name.lastIndexOf('.');
		if (dot > 0) name = name.substr(0, dot);
		return name;
	}
	#end

inline static public function inst(song:String, ?specialInst:String = null, ?modsAllowed:Bool = true):Sound
{
    var instKey:String = '${formatToSongPath(song)}/Inst';
    if(specialInst != null && specialInst.length > 0) instKey += '-' + specialInst;
    return returnSound(instKey, 'songs', modsAllowed);
}

	inline static public function voices(song:String, postfix:String = null, ?specialVocal:String = null, ?modsAllowed:Bool = true):Sound
	{
		var songKey:String = '${formatToSongPath(song)}/Voices';
		if(postfix != null) songKey += '-' + postfix;
		if(specialVocal != null && specialVocal.length > 0) songKey += '-' + specialVocal;
		trace('voices() - songKey: $songKey, postfix: $postfix, specialVocal: $specialVocal');
		return returnSound(songKey, 'songs', modsAllowed, false);
	}

	// 从单一明确目录加载歌曲音频（Inst / Voices-*），缺失即返回 null，绝不回退到 funkin 原生 assets/songs。
	// 用于统一 Inst 与人声解析路径：二者共用同一个 modDir，从机制上消除"Inst 正常、人声串味 funkin 原声"的不对称。
	//   modDir 非空 -> 仅查 mods/<modDir>/songs/<song>/<fileBase>.<SOUND_EXT>；
	//   modDir 为空   -> 仅查 assets/songs/<song>/<fileBase>.<SOUND_EXT>（即 base_game，与原 getPath 回退结果一致）。
	// 缓存 key 与 returnSound 经 getPath 解析出的绝对路径完全一致，故 currentTrackedSounds / killAudio / precache 不受影响。
	static public function loadSongAudio(song:String, fileBase:String, ?modDir:String = ''):Sound
	{
		return loadSoundAtPath(getSongAudioPath(song, fileBase, modDir));
	}

	// 与 loadSongAudio 完全一致的绝对路径解析，供外部按路径释放音频缓存时复用，
	// 确保"释放"与"缓存"使用同一 key，避免路径不一致导致缓存永远清不掉。
	// 模组路径先经 resolveModPath 还原磁盘真实文件名（大小写 / 空格 / % / 标点差异），
	// 结果按原始路径缓存，保证探测、加载、trackPreviewSound、releaseSoundCache 拿到同一个 key。
	public static function getSongAudioPath(song:String, fileBase:String, ?modDir:String = ''):String
	{
		var key:String = '${formatToSongPath(song)}/$fileBase.${SOUND_EXT}';
		var raw:String = (modDir != null && modDir.length > 0)
			? mods('$modDir/songs/$key')
			: getFolderPath(key, 'songs');
		#if sys
		if (ClientPrefs.data.modPathCompat && modDir != null && modDir.length > 0)
		{
			var hit:String = _audioPathCache.get(raw);
			if (hit != null) return hit;
			var resolved:String = resolveModPath(raw);
			if (resolved == null) resolved = raw;
			_audioPathCache.set(raw, resolved);
			return resolved;
		}
		#end
		return raw;
	}

	// 主动释放单张图片纹理（供 Freeplay 图标这类"浏览数量无上限"的小图使用）。
	// 与 clearStoredMemory 的全量清理不同，这里只针对指定 key：
	// 解除 localTrackedAssets / dumpExclusions / _excludedByTag 的引用保护，
	// 清掉引用该纹理的 Sparrow 图集缓存（否则下次 getSparrowAtlas 会拿到已销毁的 graphic），
	// 再销毁 GPU 纹理与 FlxGraphic，使内存不随"浏览过多少首曲子"单调增长。
	// 调用方必须保证该 key 已无存活的 Sprite 在使用。
	public static function releaseGraphic(key:String):Void
	{
		if (key == null || key.length == 0) return;

		var idx:Int = dumpExclusions.indexOf(key);
		if (idx >= 0) dumpExclusions.splice(idx, 1);
		for (bucket in _excludedByTag)
		{
			var i:Int = bucket.indexOf(key);
			if (i >= 0) bucket.splice(i, 1);
		}

		var localIdx:Int = localTrackedAssets.indexOf(key);
		if (localIdx >= 0) localTrackedAssets.splice(localIdx, 1);

		// 图集缓存持有 parent FlxGraphic 引用，必须一起清掉
		var staleAtlas:Array<String> = [];
		for (cacheKey in _atlasCache.keys())
		{
			var frames:FlxAtlasFrames = _atlasCache.get(cacheKey);
			if (frames != null && frames.parent != null && frames.parent.key == key)
				staleAtlas.push(cacheKey);
		}
		for (cacheKey in staleAtlas)
			_atlasCache.remove(cacheKey);

		var graph:FlxGraphic = currentTrackedAssets.get(key);
		currentTrackedAssets.remove(key);
		if (graph == null) graph = FlxG.bitmap.get(key);
		if (graph != null) destroyGraphic(graph);
	}

	// 从 currentTrackedSounds 中移除指定音频缓存，并尽力释放其底层 asset 与解码数据，
	// 让该 Sound 变为孤儿后能被 GC 回收。仅在确认不再播放该音频时调用。
	public static function releaseSoundCache(file:String):Void
	{
		if (file == null || file.length == 0 || !currentTrackedSounds.exists(file))
			return;
		currentTrackedSounds.remove(file);
		var lruIdx:Int = _soundLru.indexOf(file);
		if (lruIdx >= 0) _soundLru.splice(lruIdx, 1);
		#if !html5
		try { Assets.cache.clear(file); } catch (e:Dynamic) {}
		#end
	}

	// 与 returnSound 相同的加载/缓存逻辑，但仅按给定绝对路径判定，不触发模组与原生之间的回退链。
	static function loadSoundAtPath(file:String):Sound
	{
		var isNewLoad:Bool = !currentTrackedSounds.exists(file);
		if (isNewLoad)
		{
			#if sys
			if (FileSystem.exists(file))
			{
				try
				{
					currentTrackedSounds.set(file, Sound.fromFile(file));
				}
				catch (e:Dynamic)
				{
					trace('Failed to load sound at $file: $e');
					currentTrackedSounds.set(file, null);
				}
			}
			#else if (OpenFlAssets.exists(file, SOUND))
				currentTrackedSounds.set(file, OpenFlAssets.getSound(file));
			#end
			else
				currentTrackedSounds.set(file, null);
		}
		touchSoundLru(file);
		var loaded:Sound = currentTrackedSounds.get(file);
		// 仅「真正解码出一个有效 Sound」后才检查淘汰；探测到不存在的音频（null）不新增
		// 缓存占用，跳过可避免 loadMusic 里多次 Voices fallback 探测反复遍历缓存表。
		if (isNewLoad && loaded != null) trimSoundCache();
		return loaded;
	}

	inline static public function soundRandom(key:String, min:Int, max:Int, ?modsAllowed:Bool = true)
		return sound(key + FlxG.random.int(min, max), modsAllowed);

	public static var currentTrackedAssets:Map<String, FlxGraphic> = [];
	static public function image(key:String, ?parentFolder:String = null, ?allowGPU:Bool = true):FlxGraphic
	{
		key = LanguageBasic.getFileTranslation('images/$key') + '.png';
		var filePath:String = getPath(key, IMAGE, parentFolder, true);
		var cacheKey:String = generateCacheKey(filePath);
		var bitmap:BitmapData = null;
		if (currentTrackedAssets.exists(cacheKey))
		{
			// 校验缓存条目是否仍然有效：FlxG.resetGame() → FlxG.bitmap.reset() 会销毁所有
			// FlxGraphic（bitmap=null, key=null），但 Paths.currentTrackedAssets 这个独立 Map
			// 不会自动清除，导致之后 Paths.image() 拿到已销毁的图形并直接返回，图标渲染为空白。
			// 与 Note.hx:getCachedSparrowAtlas 的失效校验逻辑保持一致。
			var cached:FlxGraphic = currentTrackedAssets.get(cacheKey);
			if (cached != null && cached.bitmap != null
				&& FlxG.bitmap.get(cached.key) == cached)
			{
				trackLocalAsset(cacheKey);
				return cached;
			}
			currentTrackedAssets.remove(cacheKey); // 失效则丢弃，后续走 cacheBitmap 重新加载
		}
		return cacheBitmap(key, parentFolder, bitmap, allowGPU, cacheKey);
	}

	public static function cacheBitmap(key:String, ?parentFolder:String = null, ?bitmap:BitmapData, ?allowGPU:Bool = true, ?cacheKey:String = null):FlxGraphic
	{
		var actualCacheKey:String = cacheKey;
		if (actualCacheKey == null) actualCacheKey = key;
		
		if (bitmap == null)
		{
			var file:String = getPath(key, IMAGE, parentFolder, true);
			#if MODS_ALLOWED
			if (FileSystem.exists(file))
				bitmap = BitmapData.fromFile(file);
			else #end if (OpenFlAssets.exists(file, IMAGE))
				bitmap = OpenFlAssets.getBitmapData(file);

			if (bitmap == null)
			{
				trace('Bitmap not found: $file | key: $key');
				// 开启“资源加载失败提示”时，就地返回一张占位贴图，让缺失资源在原本的位置可见。
				// 传原始请求 key（如 images/xxx）而非回退解析到的 shared 路径，路径行才能显示成简洁的 mod 风格；
				// 关闭（默认）时仍返回 null，保持原逻辑不变。
				var placeholder:FlxGraphic = AssetErrorOverlay.makePlaceholder(key);
				if (placeholder != null)
					return placeholder;
				return null;
			}
			if (cacheKey == null) actualCacheKey = generateCacheKey(file);
		}

		if (allowGPU && ClientPrefs.data.cacheOnGPU && bitmap.image != null)
		{
			bitmap.lock();
			if (bitmap.__texture == null)
			{
				bitmap.image.premultiplied = true;
				bitmap.getTexture(FlxG.stage.context3D);
			}
			bitmap.getSurface();
			bitmap.disposeImage();
			bitmap.image.data = null;
			bitmap.image = null;
			bitmap.readable = true;
		}

		var graph:FlxGraphic = FlxGraphic.fromBitmapData(bitmap, false, actualCacheKey);
		graph.persist = true;
		graph.destroyOnNoUse = false;

		currentTrackedAssets.set(actualCacheKey, graph);
		trackLocalAsset(actualCacheKey);
		return graph;
	}

	inline static public function getTextFromFile(key:String, ?ignoreMods:Bool = false):String
	{
		var path:String = getPath(key, TEXT, !ignoreMods);
		#if sys
		return (FileSystem.exists(path)) ? File.getContent(path) : null;
		#else
		return (OpenFlAssets.exists(path, TEXT)) ? Assets.getText(path) : null;
		#end
	}

	static var _fontPathCache:Map<String, String> = new Map();

	static public function font(key:String):String
	{
		var folderKey:String = LanguageBasic.getFileTranslation('fonts/$key');
		// 缓存解析结果：编谱器里每个事件构造 FlxText 都会调 font()，
		// 原实现每次 modFolders()+FileSystem.exists() 同步磁盘查询，553 事件时累计接近 100 秒。
		var cacheKey:String = folderKey + '|' + Mods.currentModDirectory;
		var cached:String = _fontPathCache.get(cacheKey);
		if (cached != null) return cached;
		var result:String = 'assets/$folderKey';
		#if MODS_ALLOWED
		var file:String = modFolders(folderKey);
		if(FileSystem.exists(file)) result = file;
		#end
		_fontPathCache.set(cacheKey, result);
		return result;
	}

	public static function fileExists(key:String, type:AssetType, ?ignoreMods:Bool = false, ?parentFolder:String = null)
	{
		#if MODS_ALLOWED
		if(!ignoreMods)
		{
			var modKey:String = key;
			if(parentFolder == 'songs') modKey = 'songs/$key';

			// globalMods + mods 根：走 Mods.globalModsHas 缓存，避免重复 N 次 FileSystem.exists
			if (Mods.globalModsHas(modKey))
				return true;

			// currentModDirectory：只一个目录，不走缓存（缓存 key 会因 currentModDirectory 切换失效）
			if (Mods.currentModDirectory != null && Mods.currentModDirectory.length > 0)
			{
				if (FileSystem.exists(mods(Mods.currentModDirectory + '/' + modKey)))
					return true;
			}

			#if linux
			if (FileSystem.exists(findFile(modKey)))
				return true;
			#end
		}
		#end
		return (OpenFlAssets.exists(getPath(key, type, parentFolder, false)));
	}

	static public function getAtlas(key:String, ?parentFolder:String = null, ?allowGPU:Bool = true):FlxAtlasFrames
	{
		var useMod = false;
		var imageLoaded:FlxGraphic = image(key, parentFolder, allowGPU);

		var myXml:Dynamic = getPath('images/$key.xml', TEXT, parentFolder, true);
		if(OpenFlAssets.exists(myXml) #if MODS_ALLOWED || (FileSystem.exists(myXml) && (useMod = true)) #end )
		{
			#if MODS_ALLOWED
			return FlxAtlasFrames.fromSparrow(imageLoaded, (useMod ? File.getContent(myXml) : myXml));
			#else
			return FlxAtlasFrames.fromSparrow(imageLoaded, myXml);
			#end
		}
		else
		{
			var myJson:Dynamic = getPath('images/$key.json', TEXT, parentFolder, true);
			if(OpenFlAssets.exists(myJson) #if MODS_ALLOWED || (FileSystem.exists(myJson) && (useMod = true)) #end )
			{
				#if MODS_ALLOWED
				return FlxAtlasFrames.fromTexturePackerJson(imageLoaded, (useMod ? File.getContent(myJson) : myJson));
				#else
				return FlxAtlasFrames.fromTexturePackerJson(imageLoaded, myJson);
				#end
			}
		}
		return getPackerAtlas(key, parentFolder);
	}
	
	static public function getMultiAtlas(keys:Array<String>, ?parentFolder:String = null, ?allowGPU:Bool = true):FlxAtlasFrames
	{
		
		var parentFrames:FlxAtlasFrames = Paths.getAtlas(keys[0].trim());
		if(keys.length > 1)
		{
			var original:FlxAtlasFrames = parentFrames;
			parentFrames = new FlxAtlasFrames(parentFrames.parent);
			parentFrames.addAtlas(original, true);
			for (i in 1...keys.length)
			{
				var extraFrames:FlxAtlasFrames = Paths.getAtlas(keys[i].trim(), parentFolder, allowGPU);
				if(extraFrames != null)
					parentFrames.addAtlas(extraFrames, true);
			}
		}
		return parentFrames;
	}

	static public function getSparrowAtlas(key:String, ?parentFolder:String = null, ?allowGPU:Bool = true):FlxAtlasFrames
	{
		var __cacheKey:String = 'Sparrow|' + key;
		if (_atlasCache.exists(__cacheKey)) return _atlasCache.get(__cacheKey);

		if(key.contains('psychic')) trace(key, parentFolder, allowGPU);
		// 读取 Sparrow XML 内容（经 OpenFlAssets 读取打包资源，兼容 Android），
		// 不再把 getPath 的路径字符串丢给 fromSparrow 当内联 XML 解析，避免设备上解析为 null。
		// 同时借用 getTextFromFile 的 mod 搜索逻辑，与原先 FileSystem.exists(modsXml(key)) 等价。
		var xml:String = null;
		#if MODS_ALLOWED
		try
		{
			var xmlFile:String = modsXml(key);
			if(FileSystem.exists(xmlFile)) xml = File.getContent(xmlFile);
		}
		catch (e:Dynamic) { xml = null; }
		#end
		if (xml == null)
			xml = getTextFromFile(LanguageBasic.getFileTranslation('images/$key') + '.xml');
		// XML 缺失/为空/不可解析时返回 null，交由调用方（如 NoteSplash.loadSplash）走默认回退，
		// 避免 fromSparrow 对空根节点解引用抛 "Null Object Reference"。
		if (xml == null || StringTools.trim(xml).length < 1)
		{
			_atlasCache.set(__cacheKey, null);
			return null;
		}
		var imageLoaded:FlxGraphic = image(key, parentFolder, allowGPU);
		var __frames:FlxAtlasFrames = FlxAtlasFrames.fromSparrow(imageLoaded, xml);
		_atlasCache.set(__cacheKey, __frames);
		return __frames;
	}

	// 判定该图片 key 是否配套 Sparrow XML（角色/Note 等图集），供 LoadingState 预构建 FlxAtlasFrames 使用。
	// 与 getSparrowAtlas 内部一致：优先 mods 目录，再回退 assets 共享路径。
	static public function sparrowXmlExists(key:String):Bool
	{
		#if MODS_ALLOWED
		try { if (FileSystem.exists(modsXml(key))) return true; } catch (e:Dynamic) {}
		#end
		try { return FileSystem.exists(getPath('images/$key.xml', TEXT, null, true)); } catch (e:Dynamic) {}
		return false;
	}

	inline static public function getPackerAtlas(key:String, ?parentFolder:String = null, ?allowGPU:Bool = true):FlxAtlasFrames
	{
		var imageLoaded:FlxGraphic = image(key, parentFolder, allowGPU);
		#if MODS_ALLOWED
		var txtExists:Bool = false;
		
		var txt:String = modsTxt(key);
		if(FileSystem.exists(txt)) txtExists = true;

		return FlxAtlasFrames.fromSpriteSheetPacker(imageLoaded, (txtExists ? File.getContent(txt) : getPath(LanguageBasic.getFileTranslation('images/$key') + '.txt', TEXT, parentFolder)));
		#else
		return FlxAtlasFrames.fromSpriteSheetPacker(imageLoaded, getPath(LanguageBasic.getFileTranslation('images/$key') + '.txt', TEXT, parentFolder));
		#end
	}

	inline static public function getAsepriteAtlas(key:String, ?parentFolder:String = null, ?allowGPU:Bool = true):FlxAtlasFrames
	{
		var imageLoaded:FlxGraphic = image(key, parentFolder, allowGPU);
		#if MODS_ALLOWED
		var jsonExists:Bool = false;

		var json:String = modsImagesJson(key);
		if(FileSystem.exists(json)) jsonExists = true;

		return FlxAtlasFrames.fromTexturePackerJson(imageLoaded, (jsonExists ? File.getContent(json) : getPath(LanguageBasic.getFileTranslation('images/$key') + '.json', TEXT, parentFolder)));
		#else
		return FlxAtlasFrames.fromTexturePackerJson(imageLoaded, getPath(LanguageBasic.getFileTranslation('images/$key') + '.json', TEXT, parentFolder));
		#end
	}

	inline static public function formatToSongPath(path:String) {
		final invalidChars = ~/[~&;:<>#\s]/g;
		final hideChars = ~/[.,'"%?!]/g;

		return hideChars.replace(invalidChars.replace(path, '-'), '').trim().toLowerCase();
	}

	public static var currentTrackedSounds:Map<String, Sound> = [];

	// 音频解码 LRU（2026-11-20）：Sound.fromFile 会把整首 OGG 解码成 PCM 常驻，
	// 一首 3min 立体声约 30MB。旧实现只增不减，长时间游玩/浏览后音频缓存单调膨胀，
	// 表现为"播个音频涨一大截运存且不回落"。这里记录访问顺序，超限淘汰最久未用、
	// 且【当前无任何 FlxSound 引用】的条目——只动缓存表，不碰调用方已持有的 Sound 引用，
	// 因此对模组兼容性零影响（模组若仍持有引用，Sound 对象继续存活，只是不再被缓存命中）。
	// 阈值保守取 24：足以覆盖同时播放的 Inst/Voices + 常用 UI/打击音效，正常游玩几乎不触发。
	static var _soundLru:Array<String> = [];
	static inline var SOUND_CACHE_LIMIT:Int = 24;

	// returnSound 的 key→file 解析缓存（滚动卡顿修复）：
	// Paths.sound('scrollMenu') 在滚动时每格调用，即便 Sound 已在 currentTrackedSounds 命中，
	// getPath() 仍每次执行 modFolders()+FileSystem.exists() 的同步磁盘 I/O。
	// 缓存命中后只做一次 Map 查找。mod 目录/语言/关卡会影响解析结果，已编入缓存 key；
	// 切模组时 clearModPathCache() 也会一并清空。
	static var _soundPathCache:Map<String, String> = new Map();

	// 标记一次音频访问（命中或新加载）：把 key 提到 LRU 末尾。
	static function touchSoundLru(file:String):Void
	{
		if (file == null || file.length == 0) return;
		var idx:Int = _soundLru.indexOf(file);
		if (idx >= 0) _soundLru.splice(idx, 1);
		_soundLru.push(file);
	}

	// 判断某音频是否仍被任何存活 FlxSound 引用（含 music 与 list 中的实例）。
	// 有引用就绝不淘汰，从根本上杜绝"正在播放/暂停待恢复的音乐被释放"导致中断或崩溃。
	static function soundInUse(snd:Sound):Bool
	{
		if (snd == null) return false;
		@:privateAccess
		{
			if (FlxG.sound.music != null && FlxG.sound.music._sound == snd) return true;
			for (fs in FlxG.sound.list)
				if (fs != null && fs._sound == snd) return true;
		}
		return false;
	}

	// 缓存条目超限时，单趟扫描 LRU，从最久未用的一端淘汰最多 over 个可安全释放的音频。
	// 保护项（dumpExclusions）与仍被引用的音频跳过；不在缓存表的孤儿 key 顺手清掉。
	static function trimSoundCache():Void
	{
		var total:Int = 0;
		for (_ in currentTrackedSounds.keys()) total++;
		var over:Int = total - SOUND_CACHE_LIMIT;
		if (over <= 0) return;

		var removed:Int = 0;
		var i:Int = 0;
		while (i < _soundLru.length && removed < over)
		{
			var file:String = _soundLru[i];
			if (!currentTrackedSounds.exists(file))
			{
				_soundLru.splice(i, 1); // 孤儿，索引不前进
				continue;
			}
			var snd:Sound = currentTrackedSounds.get(file);
			if (snd != null && (dumpExclusions.contains(file) || soundInUse(snd)))
			{
				i++; // 受保护/在用，跳过
				continue;
			}
			_soundLru.splice(i, 1);
			releaseSoundCache(file);
			removed++;
		}
	}

	/// Atlas 缓存：getSparrowAtlas / getPackerAtlas / getAsepriteAtlas 结果缓存，
	/// 避免每次都 File.getContent + XML 解析 + FlxAtlasFrames.fromSparrow 重建 Frames 对象。
	/// mod 列表变化时需手动调 clearAtlasCache()（Mods.invalidateDirectoriesCache 后会被调）。
	static var _atlasCache:Map<String, FlxAtlasFrames> = new Map();
	public static function clearAtlasCache():Void _atlasCache = new Map();

	public static function returnSound(key:String, ?path:String, ?modsAllowed:Bool = true, ?beepOnNull:Bool = true)
	{
		// 路径解析缓存：mod 目录/当前关卡/当前语言都编入 key，任一变化自动失效。
		// 这样滚动播放 UI 音效时不再反复触发 FileSystem.exists()/目录扫描。
		var translated:String = LanguageBasic.getFileTranslation(key);
		var cacheKey:String = translated + '|' + path + '|' + modsAllowed + '|'
			+ Mods.currentModDirectory + '|' + currentLevel;
		var file:String = _soundPathCache.get(cacheKey);
		if (file == null)
		{
			file = getPath(translated + '.$SOUND_EXT', SOUND, path, modsAllowed);
			_soundPathCache.set(cacheKey, file);
		}

		//trace('precaching sound: $file');
		var isNewLoad:Bool = !currentTrackedSounds.exists(file);
		if(isNewLoad)
		{
			#if sys
			if(FileSystem.exists(file))
			{
				try
				{
					currentTrackedSounds.set(file, Sound.fromFile(file));
				}
				catch (e:Dynamic)
				{
					trace('Failed to load sound at $file: $e');
					currentTrackedSounds.set(file, null);
				}
			}
			#else
			if(OpenFlAssets.exists(file, SOUND))
				currentTrackedSounds.set(file, OpenFlAssets.getSound(file));
			#end
			else if(beepOnNull)
			{
				trace('SOUND NOT FOUND: $key, PATH: $path');
				FlxG.log.error('SOUND NOT FOUND: $key, PATH: $path');
				return FlxAssets.getSound('flixel/sounds/beep');
			}
		}
		trackLocalAsset(file);
		touchSoundLru(file);
		// 只在真正新解码出一个有效音频后才检查淘汰；缓存命中（如快速滚动反复播放
		// scrollMenu）或探测到不存在的音频（null）都不新增占用，跳过全表枚举。
		var loaded:Sound = currentTrackedSounds.get(file);
		if (isNewLoad && loaded != null) trimSoundCache();
		return loaded;
	}

	#if MODS_ALLOWED
	inline static public function mods(key:String = '')
		return #if android StorageUtil.getExternalStorageDirectory() + #else Sys.getCwd() + #end 'mods/' + key;

	#if sys
	// mod 路径解析用的目录列举缓存（Android 上 readDirectory 是固定开销，故仅移动端常驻缓存）
	static var _dirCache:Map<String, Array<String>> = new Map();
	static var _dirMutex:sys.thread.Mutex = new sys.thread.Mutex();
	// 歌曲音频「规范化路径 -> 磁盘真实路径」映射；切模组时随 clearModPathCache 一起清
	static var _audioPathCache:Map<String, String> = new Map();

	public static function clearModPathCache():Void
	{
		_dirMutex.acquire();
		_dirCache.clear();
		_audioPathCache.clear();
		_soundPathCache.clear(); // 音效路径解析结果依赖 mod 目录，切模组时必须一并失效
		_pathResolveCache.clear(); // getPath 通用解析缓存同理
		_fontPathCache.clear();    // font 路径解析缓存同理
		_dirMutex.release();
	}

	static function listDirectory(dir:String):Array<String>
	{
		#if mobile
		_dirMutex.acquire();
		var entries:Array<String> = _dirCache.get(dir);
		_dirMutex.release();
		if (entries != null) return entries;
		#else
		var entries:Array<String> = null;
		#end

		try
		{
			if (!FileSystem.exists(dir) || !FileSystem.isDirectory(dir)) return null;
			entries = FileSystem.readDirectory(dir);
		}
		catch (e:Dynamic)
		{
			return null;
		}

		#if mobile
		_dirMutex.acquire();
		_dirCache.set(dir, entries);
		_dirMutex.release();
		#end
		return entries;
	}
	#end

	/**
	 * 路径段匹配等级：3=精确、2=仅大小写不同、1=规范化后等价、0=不匹配。
	 * 带扩展名的段先分离扩展名再比较，避免 formatToSongPath 删除 '.' 导致误匹配。
	 * 例：请求 space-breaker-4k-godly.json，磁盘 Space-Breaker-4k Godly.json → 等级 1 命中。
	 */
	static function pathPartRank(entry:String, part:String):Int
	{
		if (entry == part) return 3;
		if (entry.toLowerCase() == part.toLowerCase()) return 2;

		var eDot:Int = entry.lastIndexOf('.');
		var pDot:Int = part.lastIndexOf('.');
		if (eDot > 0 && pDot > 0)
		{
			if (entry.substr(eDot).toLowerCase() != part.substr(pDot).toLowerCase()) return 0;
			return formatToSongPath(entry.substr(0, eDot)) == formatToSongPath(part.substr(0, pDot)) ? 1 : 0;
		}
		return formatToSongPath(entry) == formatToSongPath(part) ? 1 : 0;
	}

	/**
	 * 修复前的旧解析行为：仅移动端逐层做大小写不敏感匹配，其它平台直接放弃。
	 * modPathCompat 关闭时用它，保证设置能真正回退到旧行为。
	 */
	static function resolveModPathCaseOnly(path:String):String
	{
		#if mobile
		if (FileSystem.exists(path)) return path;
		var root:String = mods();
		if (!path.startsWith(root)) return null;

		var current:String = root.substr(0, root.length - 1);
		for (part in path.substr(root.length).split('/'))
		{
			if (part.length == 0) continue;
			var entries:Array<String> = listDirectory(current);
			if (entries == null) return null;

			var lower:String = part.toLowerCase();
			var match:String = null;
			for (entry in entries)
			{
				if (entry.toLowerCase() == lower) { match = entry; break; }
			}
			if (match == null) return null;
			current += '/' + match;
		}
		return path.endsWith('/') ? current + '/' : current;
		#else
		return null;
		#end
	}

	/**
	 * 模组路径解析：精确路径不存在时逐层按目录项匹配，覆盖大小写差异（Android/Linux）
	 * 与 formatToSongPath 规范化差异（空格、%、标点）。全 sys 平台生效 ——
	 * Windows 大小写不敏感，但空格 / % 仍匹配不上，同样需要这一层。
	 * modPathCompat 关闭时走 resolveModPathCaseOnly（完全回到修复前）。
	 * 返回 null 表示确实找不到；调用方回退到原路径。
	 */
	public static function resolveModPath(path:String):String
	{
		if (path == null) return null;
		#if sys
		if (!ClientPrefs.data.modPathCompat) return resolveModPathCaseOnly(path);
		if (FileSystem.exists(path)) return path;
		var root:String = mods();
		if (!path.startsWith(root)) return null;

		var current:String = root.substr(0, root.length - 1);
		for (part in path.substr(root.length).split('/'))
		{
			if (part.length == 0) continue;
			var entries:Array<String> = listDirectory(current);
			if (entries == null) return null;

			var bestRank:Int = 0;
			var match:String = null;
			for (entry in entries)
			{
				var rank:Int = pathPartRank(entry, part);
				if (rank > bestRank)
				{
					bestRank = rank;
					match = entry;
					if (rank == 3) break;
				}
			}
			if (match == null) return null;
			current += '/' + match;
		}
		return path.endsWith('/') ? current + '/' : current;
		#else
		return null;
		#end
	}

	inline static public function modsJson(key:String)
		return modFolders('data/' + key + '.json');

	inline static public function modsVideo(key:String)
		return modFolders('videos/' + key + '.' + VIDEO_EXT);

	inline static public function modsSounds(path:String, key:String)
		return modFolders(path + '/' + key + '.' + SOUND_EXT);

	inline static public function modsImages(key:String)
		return modFolders('images/' + key + '.png');

	inline static public function modsXml(key:String)
		return modFolders('images/' + key + '.xml');

	inline static public function modsTxt(key:String)
		return modFolders('images/' + key + '.txt');

	inline static public function modsImagesJson(key:String)
		return modFolders('images/' + key + '.json');

	static public function modFolders(key:String)
	{
		if(Mods.currentModDirectory != null && Mods.currentModDirectory.length > 0)
		{
			// 先按原路径精确命中，再逐层做大小写不敏感解析（Android 上 mod 目录大小写经常写错）
			var fileToCheck:String = resolveModPath(mods(Mods.currentModDirectory + '/' + key));
			if(fileToCheck != null)
				return fileToCheck;
			#if linux
			else
			{
				var newPath:String = findFile(key);
				if (newPath != null)
					return newPath;
			}
			#end
		}

		// globalMods + mods 根：走 Mods.findInGlobalMods 缓存
		var found:Null<String> = Mods.findInGlobalMods(key);
		if (found != null)
		{
			var resolved:String = resolveModPath(found);
			return resolved != null ? resolved : found;
		}
		#if linux
		var fileToFind:String = findFile(key);
		if (fileToFind != null)
			return fileToFind;
		#end
		return (#if android StorageUtil.getExternalStorageDirectory() + #else Sys.getCwd() + #end 'mods/' + key);
	}

	#if linux
	static function findFile(key:String):String {
		var targetParts:Array<String> = key.replace('\\', '/').split('/');
		if (targetParts.length == 0) return null;

		var baseDir:String = targetParts.shift();
		var searchDirs:Array<String> = [
			mods(Mods.currentModDirectory + '/' + baseDir),
			mods(baseDir)
		];

		for (part in targetParts) {
			if (part == '') continue;

			var nextDir:String = findNodeInDirs(searchDirs, part);
			if (nextDir == null) {
				return null;
			}

			searchDirs = [nextDir];
		}

		return searchDirs[0];
	}

	static function findNodeInDirs(dirs:Array<String>, key:String):String {
		for (dir in dirs) {
			var node:String = findNode(dir, key);
			if (node != null) {
				return dir + '/' + node;
			}
		}
		return null;
	}

	static function findNode(dir:String, key:String):String {
		try {
			var allFiles:Array<String> = Paths.readDirectory(dir);
			var fileMap:Map<String, String> = new Map();

			for (file in allFiles) {
				fileMap.set(file.toLowerCase(), file);
			}

			return fileMap.get(key.toLowerCase());
		} catch (e:Dynamic) {
			return null;
		}
	}
	#end
	#end

	#if flxanimate
	public static function loadAnimateAtlas(spr:FlxAnimate, folderOrImg:Dynamic, spriteJson:Dynamic = null, animationJson:Dynamic = null)
	{
		var changedAnimJson = false;
		var changedAtlasJson = false;
		var changedImage = false;
		
		if(spriteJson != null)
		{
			changedAtlasJson = true;
			spriteJson = File.getContent(spriteJson);
		}

		if(animationJson != null) 
		{
			changedAnimJson = true;
			animationJson = File.getContent(animationJson);
		}

		// is folder or image path
		if(Std.isOfType(folderOrImg, String))
		{
			var originalPath:String = folderOrImg;
			for (i in 0...10)
			{
				var st:String = '$i';
				if(i == 0) st = '';

				if(!changedAtlasJson)
				{
					spriteJson = getTextFromFile('images/$originalPath/spritemap$st.json');
					if(spriteJson != null)
					{
						//trace('found Sprite Json');
						changedImage = true;
						changedAtlasJson = true;
						folderOrImg = image('$originalPath/spritemap$st');
						break;
					}
				}
				else if(fileExists('images/$originalPath/spritemap$st.png', IMAGE))
				{
					//trace('found Sprite PNG');
					changedImage = true;
					folderOrImg = image('$originalPath/spritemap$st');
					break;
				}
			}

			if(!changedImage)
			{
				//trace('Changing folderOrImg to FlxGraphic');
				changedImage = true;
				folderOrImg = image(originalPath);
			}

			if(!changedAnimJson)
			{
				//trace('found Animation Json');
				changedAnimJson = true;
				animationJson = getTextFromFile('images/$originalPath/Animation.json');
			}
		}

		//trace(folderOrImg);
		//trace(spriteJson);
		//trace(animationJson);
		spr.loadAtlasEx(folderOrImg, spriteJson, animationJson);
	}
	#end

	public static function readDirectory(directory:String):Array<String>
	{
		#if MODS_ALLOWED
		return FileSystem.readDirectory(directory);
		#else
		var dirs:Array<String> = [];
		var seen:haxe.ds.StringSet = new haxe.ds.StringSet();
		var matchingDirs = Assets.list().filter(folder -> folder.startsWith(directory));
		@:privateAccess
		var libraries = lime.utils.Assets.libraries.keys();
		for(dir in matchingDirs)
		{
			var added:Bool = false;
			for(library in libraries)
			{
				if(library != 'default')
				{
					var libKey:String = '$library:$dir';
					if(!seen.exists(libKey) && Assets.exists(libKey))
					{
						seen.add(libKey);
						dirs.push(libKey);
						added = true;
					}
				}
			}
			if(!added && !seen.exists(dir) && Assets.exists(dir))
			{
				seen.add(dir);
				dirs.push(dir);
			}
		}
		return dirs.map(dir -> dir.substr(dir.lastIndexOf("/") + 1));
		#end
	}
}
