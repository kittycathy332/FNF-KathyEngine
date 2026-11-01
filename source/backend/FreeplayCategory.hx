package backend;

import haxe.Json;
#if (FEATURE_FILESYSTEM && MODS_ALLOWED)
import sys.FileSystem;
import sys.io.File;
#end

/**
 * Freeplay 分区（歌曲分类）数据。
 *
 * 配置文件读取顺序：
 *   1. 全局 mods/freeplay_categories.json（Tab 栏里排在最前面）
 *   2. 各模组自带的 mods/<模组文件夹>/freeplay_categories.json，按模组列表（modsList.txt）顺序排在全局之后
 * 相同 id 的分区会被合并：名称/颜色以先读到的（全局）为准，匹配规则取并集；
 * 保存时以模组为准——模组里出现过的分区写回模组文件（全局里的同 id 条目会被移除），
 * 这样编辑模组分类不会污染全局配置，模组目录可以直接打包分享。
 *
 * 格式：
 * {
 *   "categories": [
 *     {
 *       "id": "kathy",
 *       "name": "Kathy MOD",
 *       "folders": ["kathy-mod"],
 *       "weeks": ["week-kathy"],
 *       "songs": [{"song": "Bopeebo", "folder": "kathy-mod"}],
 *       "exclude": [{"song": "Ugh", "folder": "kathy-mod"}],
 *       "color": "#FF7A00"
 *     }
 *   ]
 * }
 * folders / weeks / songs 都是可选项，命中任意一条即归入该分区；
 * songs 也可以直接写成字符串（此时不限制文件夹）。
 * exclude 与 songs 格式相同：命中的曲目即便符合 folders / weeks / songs 规则也不会归入该分区，
 * 用于把规则命中的歌曲单独移出（Freeplay 分区编辑器取消勾选时会自动写入）。
 * color 可选：Tab 选中时的主题色，支持 "#RRGGBB"、[r, g, b] 或整数；不写则用默认亮黄。
 */
class FreeplayCategory
{
	public var id:String = '';
	public var name:String = '';
	public var folders:Array<String> = [];
	public var weeks:Array<String> = [];
	// 每项为 [格式化后的曲名, 文件夹（空字符串表示不限）]
	public var songs:Array<Array<String>> = [];
	/**
	 * 显式排除的曲目（格式与 songs 相同）。
	 * 用于把 folders / weeks 规则命中的歌从分区里拿掉：
	 * 命中 exclude 的歌即便符合 folders / weeks / songs 规则也不会归入本分区。
	 */
	public var exclude:Array<Array<String>> = [];
	/**
	 * Tab 栏选中时的主题色（0xAARRGGBB）；0 表示未配置，用默认亮黄。
	 * 用 0 而不是 -1 作哨兵：不透明色（alpha=0xFF）在 32 位 Int 里是负数，
	 * 用 -1 / >= 0 判断会把它们误认成"未配置"。
	 */
	public var color:Int = 0;
	/**
	 * 该分区第一次被读到的配置文件路径（空字符串表示本次会话新建、还没落盘）。
	 * 保存时按它"原地写回"，避免已存在的分区被挪到文件末尾打乱 Freeplay 的显示顺序。
	 * 只是运行时状态，不会写进 JSON。
	 */
	public var sourceFile:String = '';
	/**
	 * 定义该分区的**模组**配置文件路径（全局文件定义的分区为空字符串）。
	 *
	 * 当一个 id 同时出现在全局和某个模组里时，内存里合并成一条、sourceFile 记的是先读到的全局；
	 * 保存时以模组为准，写回 modSourceFile，这样编辑模组分类不会把内容搬进全局文件，
	 * 整个模组目录可以直接打包分享。也只是运行时状态。
	 */
	public var modSourceFile:String = '';

	public function new() {}

	/** 读取所有分区配置（全局 + 模组自带），按 id 合并。 */
	public static function loadAll():Array<FreeplayCategory>
	{
		var result:Array<FreeplayCategory> = [];
		#if (FEATURE_FILESYSTEM && MODS_ALLOWED)
		var byId:Map<String, FreeplayCategory> = new Map();
		// 全局配置先读：这些分区在 Tab 栏里排在最前（同一 id 时名称/颜色以全局为准）
		readInto(Paths.mods('freeplay_categories.json'), byId, result);
		// 各模组随后：按模组列表（modsList.txt）里的顺序追加
		for (mod in orderedModDirectories())
			readInto(Paths.mods(mod + '/freeplay_categories.json'), byId, result);
		#end
		return result;
	}

	/**
	 * 模组顺序：以 modsList.txt（模组菜单里看到的顺序）为准，
	 * 还没写进列表的模组目录按扫描顺序补在末尾。
	 *
	 * loadAll / saveAll 都用它，保证 Freeplay 里「全局 → 模组1 → 模组2 …」的排列与模组列表一致。
	 */
	public static function orderedModDirectories():Array<String>
	{
		var out:Array<String> = [];
		#if (FEATURE_FILESYSTEM && MODS_ALLOWED)
		var scanned:Array<String> = Mods.getModDirectories();
		for (mod in Mods.parseList().all)
			if (mod != null && mod.length > 0 && !out.contains(mod) && scanned.contains(mod))
				out.push(mod);
		for (mod in scanned)
			if (!out.contains(mod))
				out.push(mod);
		#end
		return out;
	}

	/**
	 * 该曲目是否属于此分区。
	 * @param weekFileName 曲目所属周目文件名（WeekData.weeksList 里的值）
	 * @param weekName 曲目所属周目的显示名（weekName 字段）
	 */
	public function matches(meta:SongMetadata, weekFileName:String, weekName:String):Bool
	{
		return matchesPrepared(Paths.formatToSongPath(meta.songName), normalizeFolderName(meta.folder), weekFileName, weekName);
	}

	/**
	 * 快速匹配：曲名路径与文件夹名由调用方预计算（每首歌只算一次），
	 * 1000+ 首 × 多个分区时不再重复分配字符串，避免 GC 抖动。
	 */
	public function matchesPrepared(songPath:String, folderNorm:String, weekFileName:String, weekName:String):Bool
	{
		if (isExcludedPrepared(songPath, folderNorm))
			return false;
		if (matchesSongsPrepared(songPath, folderNorm))
			return true;
		return matchesRulesPrepared(folderNorm, weekFileName, weekName);
	}

	/** songs 列表是否显式包含该曲目（不看 exclude）。 */
	public function matchesSongs(meta:SongMetadata):Bool
	{
		return matchesSongsPrepared(Paths.formatToSongPath(meta.songName), normalizeFolderName(meta.folder));
	}

	public function matchesSongsPrepared(songPath:String, folderNorm:String):Bool
	{
		if (songs.length == 0)
			return false;
		for (s in songs)
		{
			if (s[0] != songPath)
				continue;
			var f:String = (s[1] == null) ? '' : s[1];
			if (f.length == 0 || normalizeFolderName(f) == folderNorm)
				return true;
		}
		return false;
	}

	/** folders / weeks 规则是否命中该曲目（不含 songs 与 exclude）。 */
	public function matchesRules(meta:SongMetadata, weekFileName:String, weekName:String):Bool
	{
		return matchesRulesPrepared(normalizeFolderName(meta.folder), weekFileName, weekName);
	}

	public function matchesRulesPrepared(folderNorm:String, weekFileName:String, weekName:String):Bool
	{
		for (f in folders)
			if (normalizeFolderName(f) == folderNorm)
				return true;

		// 绝大多数分区只配 folders：提前返回，避免每首歌都做两次 trim/toLowerCase 的字符串分配
		if (weeks.length == 0)
			return false;

		var wf:String = (weekFileName == null) ? '' : weekFileName.trim().toLowerCase();
		var wn:String = (weekName == null) ? '' : weekName.trim().toLowerCase();
		for (w in weeks)
		{
			var wl:String = w.trim().toLowerCase();
			if (wl.length > 0 && (wl == wf || (wn.length > 0 && wl == wn)))
				return true;
		}
		return false;
	}

	/** 是否被 exclude 显式排除。 */
	public function isExcluded(meta:SongMetadata, weekFileName:String, weekName:String):Bool
	{
		return isExcludedPrepared(Paths.formatToSongPath(meta.songName), normalizeFolderName(meta.folder));
	}

	public function isExcludedPrepared(songPath:String, folderNorm:String):Bool
	{
		if (exclude.length == 0)
			return false;
		for (s in exclude)
		{
			if (s[0] != songPath)
				continue;
			var f:String = (s[1] == null) ? '' : s[1];
			if (f.length == 0 || normalizeFolderName(f) == folderNorm)
				return true;
		}
		return false;
	}

	/** 显示名：JSON 的 name → 第一个文件夹的 pack.json name → 文件夹名 → id。 */
	public function getDisplayName():String
	{
		if (name != null && name.trim().length > 0)
			return name.trim();
		#if (FEATURE_FILESYSTEM && MODS_ALLOWED)
		for (f in folders)
		{
			var folder:String = normalizeFolderName(f);
			if (folder.length == 0)
				continue; // 本体没有 pack.json，退回 id
			var pack:Dynamic = Mods.getPack(folder);
			if (pack != null)
			{
				var packName:Dynamic = Reflect.field(pack, 'name');
				if (packName != null && Std.string(packName).trim().length > 0)
					return Std.string(packName).trim();
			}
			return f.trim();
		}
		#end
		return id;
	}

	/** 文件夹比较用：空目录、base、vanilla 都视为游戏本体。 */
	public static function normalizeFolderName(folder:String):String
	{
		if (folder == null)
			return '';
		var v:String = folder.trim().toLowerCase();
		if (v == 'base' || v == 'vanilla' || v == "friday night funkin'")
			return '';
		return v;
	}

	private function mergeFrom(other:FreeplayCategory):Void
	{
		// 名称/颜色：先读到的（全局）优先，后读到的模组配置只补空缺
		if (name == null || name.length == 0)
			name = other.name;
		if (color == 0)
			color = other.color;
		for (f in other.folders)
			if (!folders.contains(f))
				folders.push(f);
		for (w in other.weeks)
			if (!weeks.contains(w))
				weeks.push(w);
		for (s in other.songs)
		{
			var exists:Bool = false;
			for (existing in songs)
			{
				if (existing[0] == s[0] && existing[1] == s[1])
				{
					exists = true;
					break;
				}
			}
			if (!exists)
				songs.push(s);
		}
		for (s in other.exclude)
		{
			var exists:Bool = false;
			for (existing in exclude)
			{
				if (existing[0] == s[0] && existing[1] == s[1])
				{
					exists = true;
					break;
				}
			}
			if (!exists)
				exclude.push(s);
		}
	}

	#if (FEATURE_FILESYSTEM && MODS_ALLOWED)
	private static function readInto(path:String, byId:Map<String, FreeplayCategory>, result:Array<FreeplayCategory>):Void
	{
		if (!FileSystem.exists(path))
			return;

		var entries:Array<Dynamic> = [];
		try
		{
			var parsed:Dynamic = Json.parse(File.getContent(path));
			if (Std.isOfType(parsed, Array))
				entries = cast parsed;
			else if (parsed != null)
			{
				var cats:Dynamic = Reflect.field(parsed, 'categories');
				if (Std.isOfType(cats, Array))
					entries = cast cats;
				else if (isCategoryObject(cats))
					entries.push(cats); // "categories" 写成单个对象
				else if (isCategoryObject(parsed))
					entries.push(parsed); // 顶层直接写单个分区
			}
		}
		catch (e:Dynamic)
		{
			trace('[FREEPLAY] 分区配置解析失败: ' + path + ' (' + e + ')');
			return;
		}

		for (entry in entries)
		{
			var c:FreeplayCategory = fromJson(entry);
			if (c == null)
				continue;
			c.sourceFile = path;
			// 模组文件单独记一份：同一 id 在全局与模组里都出现时，保存要写回模组
			var isModFile:Bool = (path != Paths.mods('freeplay_categories.json'));
			if (isModFile)
				c.modSourceFile = path;
			if (byId.exists(c.id))
			{
				var existing:FreeplayCategory = byId.get(c.id);
				existing.mergeFrom(c);
				if (isModFile && existing.modSourceFile.length == 0)
					existing.modSourceFile = path;
			}
			else
			{
				byId.set(c.id, c);
				result.push(c);
			}
		}
	}

	private static function isCategoryObject(obj:Dynamic):Bool
	{
		return Reflect.isObject(obj) && (Reflect.hasField(obj, 'id') || Reflect.hasField(obj, 'name'));
	}

	private static function fromJson(entry:Dynamic):FreeplayCategory
	{
		if (entry == null)
			return null;

		var c:FreeplayCategory = new FreeplayCategory();
		c.id = getString(entry, 'id').trim();
		if (c.id.length == 0)
			c.id = getString(entry, 'name').trim();
		if (c.id.length == 0)
			return null; // 没有 id 和 name 无法合并/识别，跳过
		c.name = getString(entry, 'name').trim();
		c.color = parseColor(Reflect.field(entry, 'color'));

		var folders:Array<Dynamic> = Reflect.field(entry, 'folders');
		if (Std.isOfType(folders, Array))
		{
			for (f in folders)
			{
				var v:String = Std.string(f).trim();
				if (v.length > 0)
					c.folders.push(v);
			}
		}

		var weeks:Array<Dynamic> = Reflect.field(entry, 'weeks');
		if (Std.isOfType(weeks, Array))
		{
			for (w in weeks)
			{
				var v:String = Std.string(w).trim();
				if (v.length > 0)
					c.weeks.push(v);
			}
		}

		c.songs = parseSongList(Reflect.field(entry, 'songs'));
		c.exclude = parseSongList(Reflect.field(entry, 'exclude'));

		return c;
	}

	/** 解析 songs / exclude：支持字符串或 {song, folder} 两种写法。 */
	private static function parseSongList(value:Dynamic):Array<Array<String>>
	{
		var list:Array<Array<String>> = [];
		if (!Std.isOfType(value, Array))
			return list;

		var entries:Array<Dynamic> = cast value;
		for (s in entries)
		{
			if (Std.isOfType(s, String))
			{
				var v:String = Std.string(s).trim();
				if (v.length > 0)
					list.push([Paths.formatToSongPath(v), '']);
			}
			else
			{
				var sn:String = getString(s, 'song').trim();
				if (sn.length > 0)
					list.push([Paths.formatToSongPath(sn), getString(s, 'folder').trim()]);
			}
		}
		return list;
	}

	private static function getString(obj:Dynamic, field:String):String
	{
		if (obj == null)
			return '';
		var v:Dynamic = Reflect.field(obj, field);
		return (v == null) ? '' : Std.string(v);
	}

	// ==================== 写盘（分区编辑器） ====================

	/**
	 * 编辑器里对分区分组/排序所依据的"归属文件"。
	 *
	 * 用第一次读到它的配置文件（sourceFile）：Freeplay 的 Tab 顺序正是按这个文件里的条目顺序排的，
	 * 所以同一组内的排序写回该文件后，Tab 顺序会跟着变。
	 * 本次会话新建、还没落盘的分区返回空字符串（单独成组，保存时按选择的目标文件写入）。
	 */
	public static function groupFileOf(c:FreeplayCategory):String
	{
		if (c == null)
			return '';
		return (c.sourceFile == null) ? '' : c.sourceFile;
	}

	/**
	 * 把分区编辑器的结果写回配置文件。
	 * @param edited 被修改或新建的分区（未修改的不用传，保持原文件原样）
	 * @param removedIds 被删除的分区 id
	 * @param newCatTarget 新建分区的目标文件（编辑器保存时弹窗选择；null/空则用全局配置）
	 * @param order 编辑器里分区的新顺序（仅排序有改动时传入）。每个文件里属于同一归属文件的分区
	 *              会按这个顺序重排，从而让 Freeplay 的 Tab 顺序跟着变
	 *
	 * 原则是**原地更新、不打乱顺序**：
	 *  - 已存在的分区写回它原本所在的那个文件；若它同时存在于某个模组配置里，以模组为准写回
	 *    模组文件（方便整个模组打包分享），全局文件里的同 id 条目被移除；
	 *  - 新建的分区写到 newCatTarget（默认全局 mods/freeplay_categories.json）；
	 *  - 被删除的分区从所有配置文件里移除。
	 * 其余文件里同 id 的条目会被清掉，避免同一个分区在两处合并出旧规则。
	 */
	public static function saveAll(edited:Array<FreeplayCategory>, removedIds:Array<String>, ?newCatTarget:String, ?order:Array<FreeplayCategory>):Void
	{
#if (FEATURE_FILESYSTEM && MODS_ALLOWED)
		var changed:Array<String> = [];
		for (id in removedIds)
			if (id != null && id.length > 0 && !changed.contains(id))
				changed.push(id);
		for (c in edited)
			if (c != null && c.id != null && c.id.length > 0 && !changed.contains(c.id))
				changed.push(c.id);
		// 只调整了顺序（内容没改）时也要写盘
		if (changed.length == 0 && order == null)
			return;

		var globalPath:String = Paths.mods('freeplay_categories.json');
		var targetForNew:String = (newCatTarget != null && newCatTarget.length > 0) ? newCatTarget : globalPath;
		var files:Array<String> = [globalPath];
		for (mod in orderedModDirectories())
		{
			var path:String = Paths.mods(mod + '/freeplay_categories.json');
			if (!files.contains(path))
				files.push(path);
		}
		if (!files.contains(targetForNew))
			files.push(targetForNew);

		// 先把所有目标文件读进来；全局文件解析失败就整次放弃，模组文件解析失败则跳过（保持原样）
		var parsedByFile:Map<String, Dynamic> = new Map();
		var entriesByFile:Map<String, Array<Dynamic>> = new Map();
		for (path in files)
		{
			if (!FileSystem.exists(path))
				continue;
			var parsed:Dynamic = null;
			try parsed = Json.parse(File.getContent(path))
			catch (e:Dynamic)
			{
				if (path == globalPath)
				{
					trace('[FREEPLAY] 分区配置解析失败，已取消写入: ' + globalPath + ' (' + e + ')');
					return;
				}
				trace('[FREEPLAY] 模组分区配置解析失败，已跳过: ' + path + ' (' + e + ')');
				parsedByFile.set(path, null);
				continue;
			}
			parsedByFile.set(path, parsed);
			entriesByFile.set(path, extractEntries(parsed));
		}

		// 每个被改动的分区决定写到哪个文件：模组里的分类写回模组文件，新建的写到用户选的目标文件
		var targetByCat:Map<String, String> = new Map();
		for (c in edited)
		{
			var target:String;
			if (c.sourceFile == null || c.sourceFile.length == 0)
				target = targetForNew; // 本次新建：写到保存时选择的位置
			else if (c.modSourceFile != null && c.modSourceFile.length > 0 && FileSystem.exists(c.modSourceFile))
				target = c.modSourceFile; // 全局与模组都有：以模组为准
			else if (FileSystem.exists(c.sourceFile))
				target = c.sourceFile;
			else
				target = globalPath; // 原文件已被删掉，退回全局
			targetByCat.set(c.id, target);
		}

		for (path in files)
		{
			var parsed:Dynamic = parsedByFile.get(path);
			var oldEntries:Array<Dynamic> = (entriesByFile.exists(path) && entriesByFile.get(path) != null) ? entriesByFile.get(path) : [];

			var newEntries:Array<Dynamic> = [];
			var fileChanged:Bool = false;

			// 原条目：命中的 id 原位置替换（或删除），其余保持原顺序
			for (e in oldEntries)
			{
				var id:String = entryId(e);
				if (id.length > 0 && changed.contains(id))
				{
					fileChanged = true;
					var editedCat:FreeplayCategory = findEdited(edited, id);
					if (editedCat != null && targetByCat.get(id) == path)
						newEntries.push(toJson(editedCat));
					continue;
				}
				newEntries.push(e);
			}

			// 目标文件里原本没有这个 id（新建分区、或原本在别的文件）→ 追加到末尾
			for (c in edited)
			{
				if (targetByCat.get(c.id) != path)
					continue;
				var present:Bool = false;
				for (e in oldEntries)
				{
					if (entryId(e) == c.id)
					{
						present = true;
						break;
					}
				}
				if (present)
					continue;
				newEntries.push(toJson(c));
				fileChanged = true;
			}

			// 按编辑器里的新顺序重排本文件里"归属本文件"的条目（只动了顺序时也要写盘）
			if (order != null)
			{
				var orderedIds:Array<String> = [];
				for (c in order)
				{
					if (c == null || c.id == null || c.id.length == 0 || orderedIds.contains(c.id))
						continue;
					if (groupFileOf(c) == path)
						orderedIds.push(c.id);
				}
				if (orderedIds.length > 1)
				{
					var reordered:Null<Array<Dynamic>> = applyOrder(newEntries, orderedIds);
					if (reordered != null)
					{
						newEntries = reordered;
						fileChanged = true;
					}
				}
			}

			if (!fileChanged)
				continue;

			try
			{
				var folder:String = Paths.mods();
				if (!FileSystem.exists(folder))
					FileSystem.createDirectory(folder);
				// 新建分区选到某个模组时，确保该模组目录存在（正常情况下面已经存在）
				if (path != globalPath)
				{
					var slash:Int = path.lastIndexOf('/');
					if (slash > 0)
					{
						var dir:String = path.substr(0, slash);
						if (!FileSystem.exists(dir))
							FileSystem.createDirectory(dir);
					}
				}
				File.saveContent(path, Json.stringify(buildRoot(parsed, newEntries), '\t'));
			}
			catch (e:Dynamic)
				trace('[FREEPLAY] 分区配置写入失败: ' + path + ' (' + e + ')');
		}
#end
	}

#if (FEATURE_FILESYSTEM && MODS_ALLOWED)
	private static function findEdited(edited:Array<FreeplayCategory>, id:String):FreeplayCategory
	{
		for (c in edited)
			if (c != null && c.id == id)
				return c;
		return null;
	}

	private static function findEntryById(entries:Array<Dynamic>, id:String):Dynamic
	{
		for (e in entries)
			if (entryId(e) == id)
				return e;
		return null;
	}

	/**
	 * 按编辑器里的顺序重排文件条目。
	 * 只重排 orderedIds 里出现过的条目，其它（无关的）条目留在原来的位置上。
	 * 返回 null 表示顺序本来就一致，不需要写盘。
	 */
	private static function applyOrder(entries:Array<Dynamic>, orderedIds:Array<String>):Null<Array<Dynamic>>
	{
		var present:Array<String> = [];
		for (id in orderedIds)
			if (!present.contains(id) && findEntryById(entries, id) != null)
				present.push(id);
		if (present.length < 2)
			return null;

		var inOrder:Array<Dynamic> = [];
		for (id in present)
			inOrder.push(findEntryById(entries, id));

		var out:Array<Dynamic> = [];
		var cursor:Int = 0;
		var changed:Bool = false;
		for (e in entries)
		{
			var id:String = entryId(e);
			if (present.contains(id))
			{
				var next:Dynamic = inOrder[cursor];
				cursor++;
				if (entryId(next) != id)
					changed = true;
				out.push(next);
			}
			else
				out.push(e);
		}
		return changed ? out : null;
	}

	private static function extractEntries(parsed:Dynamic):Array<Dynamic>
	{
		if (parsed == null)
			return [];
		if (Std.isOfType(parsed, Array))
			return cast parsed;

		var cats:Dynamic = Reflect.field(parsed, 'categories');
		if (Std.isOfType(cats, Array))
			return cast cats;
		if (isCategoryObject(cats))
			return [cats];
		if (isCategoryObject(parsed))
			return [parsed];
		return [];
	}

	/** 复用原文件的其余字段（如 _comment），只替换 categories。 */
	private static function buildRoot(parsed:Dynamic, entries:Array<Dynamic>):Dynamic
	{
		if (parsed != null && !Std.isOfType(parsed, Array) && Reflect.isObject(parsed) && Reflect.hasField(parsed, 'categories'))
		{
			Reflect.setField(parsed, 'categories', entries);
			return parsed;
		}
		var root:Dynamic = {};
		Reflect.setField(root, 'categories', entries);
		return root;
	}

	private static function entryId(entry:Dynamic):String
	{
		var id:String = getString(entry, 'id').trim();
		if (id.length == 0)
			id = getString(entry, 'name').trim();
		return id;
	}

	private static function toJson(cat:FreeplayCategory):Dynamic
	{
		var obj:Dynamic = {};
		Reflect.setField(obj, 'id', cat.id);
		if (cat.name != null && cat.name.trim().length > 0)
			Reflect.setField(obj, 'name', cat.name.trim());
		if (cat.folders.length > 0)
			Reflect.setField(obj, 'folders', cat.folders.copy());
		if (cat.weeks.length > 0)
			Reflect.setField(obj, 'weeks', cat.weeks.copy());
		if (cat.songs.length > 0)
			Reflect.setField(obj, 'songs', songListToJson(cat.songs));
		if (cat.exclude.length > 0)
			Reflect.setField(obj, 'exclude', songListToJson(cat.exclude));
		if (cat.color != 0)
			Reflect.setField(obj, 'color', colorToHex(cat.color));
		return obj;
	}

	private static function songListToJson(list:Array<Array<String>>):Array<Dynamic>
	{
		var out:Array<Dynamic> = [];
		for (s in list)
		{
			var folder:String = (s[1] == null) ? '' : s[1];
			if (folder.length == 0)
				out.push(s[0]);
			else
			{
				var item:Dynamic = {};
				Reflect.setField(item, 'song', s[0]);
				Reflect.setField(item, 'folder', folder);
				out.push(item);
			}
		}
		return out;
	}

	/** 0xAARRGGBB → "#RRGGBB"（全不透明）或 "#AARRGGBB"。 */
	public static function colorToHex(color:Int):String
	{
		var a:Int = (color >>> 24) & 0xFF;
		var r:Int = (color >> 16) & 0xFF;
		var g:Int = (color >> 8) & 0xFF;
		var b:Int = color & 0xFF;
		return '#' + ((a == 0xFF) ? '' : hex2(a)) + hex2(r) + hex2(g) + hex2(b);
	}

	private static inline function hex2(v:Int):String
	{
		return StringTools.hex(v, 2).toUpperCase();
	}
#end

	/**
	 * 解析分区的 color 字段，支持三种写法：
	 *  - "#RRGGBB" / "#AARRGGBB" / 不带 # 的十六进制字符串
	 *  - [r, g, b]（或 [r, g, b, a]，取值 0~255）
	 *  - 整数（0xRRGGBB 或 0xAARRGGBB）
	 * 解析失败或不合法时返回 -1（使用默认颜色）。
	 */
	private static function parseColor(value:Dynamic):Int
	{
		if (value == null)
			return 0;

		if (Std.isOfType(value, Array))
		{
			var arr:Array<Dynamic> = cast value;
			if (arr.length < 3)
				return 0;
			var alpha:Int = (arr.length > 3) ? clampByte(arr[3]) : 255;
			return (alpha << 24) | (clampByte(arr[0]) << 16) | (clampByte(arr[1]) << 8) | clampByte(arr[2]);
		}

		if (Std.isOfType(value, String))
		{
			var text:String = Std.string(value).trim();
			if (text.length == 0)
				return 0;
			if (text.charAt(0) == '#')
				text = text.substr(1);

			// 逐 2 位解析，避免 0xAARRGGBB 超出 Int32 范围
			var digits:String = '';
			if (text.length == 6)
				digits = 'FF' + text; // 只写了 RGB，补满不透明
			else if (text.length == 8)
				digits = text;

			if (digits.length != 8)
				return 0;

			var a:Null<Int> = Std.parseInt('0x' + digits.substr(0, 2));
			var r:Null<Int> = Std.parseInt('0x' + digits.substr(2, 2));
			var g:Null<Int> = Std.parseInt('0x' + digits.substr(4, 2));
			var b:Null<Int> = Std.parseInt('0x' + digits.substr(6, 2));
			if (a == null || r == null || g == null || b == null)
				return 0;

			return (a << 24) | (r << 16) | (g << 8) | b;
		}

		// JSON 里直接写数字（如 16711680 表示 #FF0000）
		var num:Int = Std.int(cast value);
		if (num < 0)
			return 0;
		return (num <= 0xFFFFFF) ? (num | 0xFF000000) : num;
	}

	private static function clampByte(v:Dynamic):Int
	{
		return Std.int(Math.max(0, Math.min(255, Std.parseFloat(Std.string(v)))));
	}
	#end
}
