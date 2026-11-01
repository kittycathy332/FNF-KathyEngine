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
 *   1. 每个模组自带的 mods/<模组文件夹>/freeplay_categories.json
 *   2. 全局 mods/freeplay_categories.json
 * 相同 id 的分区会被合并：名称以后读到的（全局）为准，匹配规则取并集。
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
 *       "color": "#FF7A00"
 *     }
 *   ]
 * }
 * folders / weeks / songs 都是可选项，命中任意一条即归入该分区；
 * songs 也可以直接写成字符串（此时不限制文件夹）。
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
	 * Tab 栏选中时的主题色（0xAARRGGBB）；0 表示未配置，用默认亮黄。
	 * 用 0 而不是 -1 作哨兵：不透明色（alpha=0xFF）在 32 位 Int 里是负数，
	 * 用 -1 / >= 0 判断会把它们误认成"未配置"。
	 */
	public var color:Int = 0;

	public function new() {}

	/** 读取所有分区配置（模组自带 + 全局），按 id 合并。 */
	public static function loadAll():Array<FreeplayCategory>
	{
		var result:Array<FreeplayCategory> = [];
		#if (FEATURE_FILESYSTEM && MODS_ALLOWED)
		var byId:Map<String, FreeplayCategory> = new Map();
		for (mod in Mods.getModDirectories())
			readInto(Paths.mods(mod + '/freeplay_categories.json'), byId, result);
		readInto(Paths.mods('freeplay_categories.json'), byId, result);
		#end
		return result;
	}

	/**
	 * 该曲目是否属于此分区。
	 * @param weekFileName 曲目所属周目文件名（WeekData.weeksList 里的值）
	 * @param weekName 曲目所属周目的显示名（weekName 字段）
	 */
	public function matches(meta:SongMetadata, weekFileName:String, weekName:String):Bool
	{
		var folder:String = normalizeFolderName(meta.folder);
		for (f in folders)
			if (normalizeFolderName(f) == folder)
				return true;

		var wf:String = (weekFileName == null) ? '' : weekFileName.trim().toLowerCase();
		var wn:String = (weekName == null) ? '' : weekName.trim().toLowerCase();
		for (w in weeks)
		{
			var wl:String = w.trim().toLowerCase();
			if (wl.length > 0 && (wl == wf || (wn.length > 0 && wl == wn)))
				return true;
		}

		if (songs.length > 0)
		{
			var songPath:String = Paths.formatToSongPath(meta.songName);
			for (s in songs)
			{
				if (s[0] != songPath)
					continue;
				var f:String = (s[1] == null) ? '' : s[1];
				if (f.length == 0 || normalizeFolderName(f) == folder)
					return true;
			}
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
		if (other.name != null && other.name.length > 0)
			name = other.name;
		if (other.color != 0)
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
			if (byId.exists(c.id))
				byId.get(c.id).mergeFrom(c);
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

		var songs:Array<Dynamic> = Reflect.field(entry, 'songs');
		if (Std.isOfType(songs, Array))
		{
			for (s in songs)
			{
				if (Std.isOfType(s, String))
				{
					var v:String = Std.string(s).trim();
					if (v.length > 0)
						c.songs.push([Paths.formatToSongPath(v), '']);
				}
				else
				{
					var sn:String = getString(s, 'song').trim();
					if (sn.length > 0)
						c.songs.push([Paths.formatToSongPath(sn), getString(s, 'folder').trim()]);
				}
			}
		}

		return c;
	}

	private static function getString(obj:Dynamic, field:String):String
	{
		if (obj == null)
			return '';
		var v:Dynamic = Reflect.field(obj, field);
		return (v == null) ? '' : Std.string(v);
	}

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
