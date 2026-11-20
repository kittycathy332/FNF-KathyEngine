package backend;

import backend.Mods;

class Highscore
{
	public static var weekScores:Map<String, Int> = new Map();
	public static var songScores:Map<String, Int> = new Map<String, Int>();
	public static var songRating:Map<String, Float> = new Map<String, Float>();

	public static function resetSong(song:String, diff:Int = 0, ?folder:String):Void
	{
		var daSong:String = namespacedKey(song, diff, folder);
		setScore(daSong, 0);
		setRating(daSong, 0);
	}

	public static function resetWeek(week:String, diff:Int = 0, ?folder:String):Void
	{
		var daWeek:String = namespacedKey(week, diff, folder);
		setWeekScore(daWeek, 0);
	}

	public static function saveScore(song:String, score:Int = 0, ?diff:Int = 0, ?rating:Float = -1, ?folder:String):Void
	{
		if(song == null) return;
		var daSong:String = namespacedKey(song, diff, folder);

		if (songScores.exists(daSong))
		{
			if (songScores.get(daSong) < score)
			{
				setScore(daSong, score);
				if(rating >= 0) setRating(daSong, rating);
			}
		}
		else
		{
			setScore(daSong, score);
			if(rating >= 0) setRating(daSong, rating);
		}
	}

	public static function saveWeekScore(week:String, score:Int = 0, ?diff:Int = 0, ?folder:String):Void
	{
		var daWeek:String = namespacedKey(week, diff, folder);

		if (weekScores.exists(daWeek))
		{
			if (weekScores.get(daWeek) < score)
				setWeekScore(daWeek, score);
		}
		else setWeekScore(daWeek, score);
	}

	/**
	 * YOU SHOULD FORMAT SONG WITH formatSong() BEFORE TOSSING IN SONG VARIABLE
	 */
	// doFlush=false 用于"读时补零"：只更新内存中的存档 Map，不同步写盘。
	// 2026-11-20：getScore/getRating/getWeekScore 在 key 缺失时会补 0，
	// 原实现走 setScore→flush() 同步写整个存档文件。Freeplay 快速滚动经过未打过的歌时
	// 每首触发 2 次 flush，是"时不时卡一下"的主因。补零条目本来就在 songScores 这个
	// 与 FlxG.save.data 共享引用的 Map 里，退出时 OpenFL 会自动 flush，不会丢。
	static function setScore(song:String, score:Int, ?doFlush:Bool = true):Void
	{
		songScores.set(song, score);
		FlxG.save.data.songScores = songScores;
		if (doFlush) FlxG.save.flush();
	}
	static function setWeekScore(week:String, score:Int, ?doFlush:Bool = true):Void
	{
		weekScores.set(week, score);
		FlxG.save.data.weekScores = weekScores;
		if (doFlush) FlxG.save.flush();
	}

	static function setRating(song:String, rating:Float, ?doFlush:Bool = true):Void
	{
		songRating.set(song, rating);
		FlxG.save.data.songRating = songRating;
		if (doFlush) FlxG.save.flush();
	}

	public static function formatSong(song:String, diff:Int):String
	{
		return Paths.formatToSongPath(song) + Difficulty.getFilePath(diff);
	}

	// 在分数键中加入模组命名空间，实现跨模组隔离；
	// 基础游戏（folder 为空）保持原键以兼容旧存档
	static function namespacedKey(song:String, diff:Int, ?folder:String):String
	{
		var base:String = formatSong(song, diff);
		var mod:String = (folder != null && folder.length > 0) ? folder : Mods.currentModDirectory;
		return (mod != null && mod.length > 0) ? (mod + ':' + base) : base;
	}

	public static function getScore(song:String, diff:Int, ?folder:String):Int
	{
		var daSong:String = namespacedKey(song, diff, folder);
		if (!songScores.exists(daSong))
			setScore(daSong, 0, false); // 补零不写盘，避免快速滚动卡顿

		return songScores.get(daSong);
	}

	public static function getRating(song:String, diff:Int, ?folder:String):Float
	{
		var daSong:String = namespacedKey(song, diff, folder);
		if (!songRating.exists(daSong))
			setRating(daSong, 0, false); // 补零不写盘

		return songRating.get(daSong);
	}

	public static function getWeekScore(week:String, diff:Int, ?folder:String):Int
	{
		var daWeek:String = namespacedKey(week, diff, folder);
		if (!weekScores.exists(daWeek))
			setWeekScore(daWeek, 0, false); // 补零不写盘

		return weekScores.get(daWeek);
	}

	public static function load():Void
	{
		if (FlxG.save == null || FlxG.save.data == null)
			return;

		if (FlxG.save.data.weekScores != null)
			weekScores = FlxG.save.data.weekScores;

		if (FlxG.save.data.songScores != null)
			songScores = FlxG.save.data.songScores;

		if (FlxG.save.data.songRating != null)
			songRating = FlxG.save.data.songRating;
	}
}