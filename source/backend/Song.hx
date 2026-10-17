package backend;

import haxe.Json;
import lime.utils.Assets;

import objects.Note;

typedef SwagSong =
{
	var song:String;
	var notes:Array<SwagSection>;
	var events:Array<Dynamic>;
	var bpm:Float;
	var needsVoices:Bool;
	var speed:Float;
	var offset:Float;

	var player1:String;
	var player2:String;
	var gfVersion:String;
	var stage:String;
	var format:String;

	// 谱面由哪个编辑器/引擎生成，仅作元信息展示，不参与任何玩法逻辑
	@:optional var generatedBy:String;

	// Extra Keys：键数档位（0=1键 ... 17=18键）。缺省 = 3（标准 4 键）。
	// 对应 extrakeys.json 里 keys 数组的下标。
	@:optional var mania:Int;

	// 兼容其他多键引擎的字段名（如 Matt/MattV3 的 "keyCount": 6 表示 6 键）。
	// onLoadJson 里会把 keyCount 映射成 mania = keyCount - 1。
	@:optional var keyCount:Int;

	@:optional var gameOverChar:String;
	@:optional var gameOverSound:String;
	@:optional var gameOverLoop:String;
	@:optional var gameOverEnd:String;
	
	@:optional var disableNoteRGB:Bool;

	@:optional var arrowSkin:String;
	@:optional var splashSkin:String;
	@:optional var holdCoverSkin:String;
	@:optional var specialInst:String;
    @:optional var specialVocal:String;
    @:optional var specialEvents:String;

	// Leather Engine 字段：modchart 脚本路径（data/modcharts/{modchartPath}.lua）、UI 皮肤名
	@:optional var modchartPath:String;
	@:optional var ui_Skin:String;
}

typedef SwagSection =
{
	var sectionNotes:Array<Dynamic>;
	var sectionBeats:Float;
	var mustHitSection:Bool;
	@:optional var altAnim:Bool;
	@:optional var gfSection:Bool;
	@:optional var bpm:Float;
	@:optional var changeBPM:Bool;
	@:optional var bpmRamp:Float; // 线性 BPM 过渡持续的步数（0/缺省 = 瞬时跳变，保持旧行为）
}

class Song
{
	public var song:String;
	public var notes:Array<SwagSection>;
	public var events:Array<Dynamic>;
	public var bpm:Float;
	public var needsVoices:Bool = true;
	public var arrowSkin:String;
	public var splashSkin:String;
	public var holdCoverSkin:String;
	public var gameOverChar:String;
	public var gameOverSound:String;
	public var gameOverLoop:String;
	public var gameOverEnd:String;
	public var disableNoteRGB:Bool = false;
	public var speed:Float = 1;
	public var stage:String;
	public var player1:String = 'bf';
	public var player2:String = 'dad';
	public var gfVersion:String = 'gf';
	public var format:String = 'psych_v1';
	public var generatedBy:String;
	public var specialInst:String;
	public var specialVocal:String;
	public var specialEvents:String;

	public static function convert(songJson:Dynamic) // Convert old charts to psych_v1 format
	{
		if(songJson.gfVersion == null)
		{
			songJson.gfVersion = songJson.player3;
			if(Reflect.hasField(songJson, 'player3')) Reflect.deleteField(songJson, 'player3');
		}

		// Extra Keys：在按列折叠之前先确定列数。
		// legacy 谱面无 mania 字段 → 兜底 3（4 键），行为与原版一致；
		// 多键谱面（keyCount:6 或 mania:5）→ sectCols=6，轨道号 0-5 玩家 / 6-11 敌人。
		var mania:Int = 3;
		if (songJson.keyCount != null) mania = Std.int(songJson.keyCount) - 1;
		else if (songJson.mania != null) mania = Std.int(songJson.mania);
		var sectCols:Int = mania + 1;

		if(songJson.events == null)
		{
			songJson.events = [];
			for (secNum in 0...songJson.notes.length)
			{
				var sec:SwagSection = songJson.notes[secNum];
				var notes:Array<Dynamic> = sec.sectionNotes;
				var newNotes:Array<Dynamic> = [];
				if(notes != null)
				{
					for(note in notes)
					{
						if(note[1] < 0)
						{
							songJson.events.push([note[0], [[note[2], note[3], note[4]]]]);
						}
						else
						{
							newNotes.push(note);
						}
					}
				}
				sec.sectionNotes = newNotes;
			}
		}

		var sectionsData:Array<SwagSection> = songJson.notes;
		if(sectionsData == null) return;

		for (section in sectionsData)
		{
			if (section.sectionNotes == null)
				section.sectionNotes = [];

			var beats:Null<Float> = cast section.sectionBeats;
			if (beats == null || Math.isNaN(beats))
			{
				section.sectionBeats = 4;
				if(Reflect.hasField(section, 'lengthInSteps')) Reflect.deleteField(section, 'lengthInSteps');
			}

			for (note in section.sectionNotes)
			{
				// 列数从硬编码 4 改成按 mania 档位动态计算。
				// legacy 相对车道：0..sectCols-1 = 当前小节归属方，sectCols..2*sectCols-1 = 另一方。
				// psych_v1 绝对车道：0..sectCols-1 永远是玩家，sectCols..2*sectCols-1 永远是对手。
				var gottaHitNote:Bool = (note[1] < sectCols) ? section.mustHitSection : !section.mustHitSection;
				note[1] = (note[1] % sectCols) + (gottaHitNote ? 0 : sectCols);

				if(!Std.isOfType(note[3], String))
					note[3] = Note.defaultNoteTypes[note[3]];
			}
		}
	}

	public static var chartPath:String;
	public static var loadedSongName:String;
	// 最近一次谱面加载失败时实际尝试过的路径（用于错误提示）
	public static var lastTriedChartPaths:Array<String> = [];
	public static function loadFromJson(jsonInput:String, ?folder:String):SwagSong
	{
		if(folder == null) folder = jsonInput;
		var newSong:SwagSong = getChart(jsonInput, folder);
		if(newSong == null)
		{
			trace('Failed to load chart: $jsonInput (tried: ${lastTriedChartPaths.join(', ')})');
			return null;
		}
		PlayState.SONG = newSong;
		
		loadedSongName = folder;
		chartPath = _lastPath;
		#if windows
		// prevent any saving errors by fixing the path on Windows (being the only OS to ever use backslashes instead of forward slashes for paths)
		chartPath = chartPath.replace('/', '\\');
		#end
		StageData.loadDirectory(PlayState.SONG);
		return PlayState.SONG;
	}

	/**
	 * 计算谱面 JSON 的路径，不读文件。开销极小，可以在主线程调用后把路径丢给后台线程去读。
	 * 内置 Normal 难度兼容：无后缀谱面缺失时，回退尝试 -normal / 忽略大小写 / 已知拼写错误变体。
	 */
	public static function getChartPath(jsonInput:String, ?folder:String):String
	{
		if(folder == null) folder = jsonInput;

		var formattedFolder:String = Paths.formatToSongPath(folder);
		var formattedSong:String = Paths.formatToSongPath(jsonInput);
		var basePath:String = Paths.json('${formattedFolder}/${formattedSong}');
		lastTriedChartPaths = [basePath];

		// Compat：Normal（无后缀）谱面缺失时，尝试 -normal 后缀 / 难度名（忽略大小写）及已知拼写错误变体
		if(isDefaultDifficultyChart(formattedSong) && !chartFileExists(basePath))
		{
			var fallbackPath:String = findNormalFallbackChart(formattedFolder, formattedSong);
			if(fallbackPath != null) return fallbackPath;
		}
		return basePath;
	}

	/**
	 * 判断是否为"无后缀"（即 Normal / 默认难度）谱面名。
	 * 只要不以当前难度列表里的某个非默认难度名结尾，就按无后缀谱面处理。
	 */
	static function isDefaultDifficultyChart(formattedSong:String):Bool
	{
		var defaultDiff:String = Paths.formatToSongPath(Difficulty.getDefault()); // 'normal'
		for(diff in Difficulty.list)
		{
			var lower:String = Paths.formatToSongPath(diff);
			if(lower.length == 0 || lower == defaultDiff) continue;
			if(formattedSong.endsWith('-' + lower)) return false;
		}
		return true;
	}

	/**
	 * 尝试寻找 Normal 难度兼容谱面文件：
	 * 1) -normal 后缀精确路径（Windows/macOS 等大小写不敏感文件系统可一步命中）
	 * 2) 谱面目录内忽略大小写的文件名匹配（覆盖大小写敏感文件系统）
	 * 返回实际存在的路径；找不到返回 null。
	 */
	static function findNormalFallbackChart(formattedFolder:String, formattedSong:String):String
	{
		// 候选难度后缀（小写）。'nuormal' 是部分旧模组常见的拼写错误，可继续追加
		var suffixes:Array<String> = ['normal', 'nuormal'];
		var want:Array<String> = [];
		for(s in suffixes)
			want.push(formattedSong + '-' + s);

		// 1) 精确路径尝试（mods 解析 + 打包资源）
		for(w in want)
		{
			var p:String = Paths.json('$formattedFolder/$w');
			lastTriedChartPaths.push(p);
			if(chartFileExists(p)) return p;
		}

		// 2) 大小写敏感文件系统：扫描当前 mod 的谱面目录，忽略大小写匹配
		#if (MODS_ALLOWED && sys)
		try
		{
			if(Mods.currentModDirectory != null && Mods.currentModDirectory.length > 0)
			{
				var dir:String = Paths.mods(Mods.currentModDirectory + '/data/' + formattedFolder);
				if(FileSystem.exists(dir) && FileSystem.isDirectory(dir))
				{
					for(f in FileSystem.readDirectory(dir))
					{
						var lower:String = f.toLowerCase();
						for(w in want)
						{
							if(lower == w + '.json')
							{
								var fp:String = dir + '/' + f;
								lastTriedChartPaths.push(fp);
								return fp;
							}
						}
					}
				}
			}
		}
		catch(e:Dynamic) { /* 目录不可读时忽略，按未找到处理 */ }
		#end
		return null;
	}

	static function chartFileExists(path:String):Bool
	{
		#if sys
		if(FileSystem.exists(path)) return true;
		#end
		return Assets.exists(path, lime.utils.AssetType.TEXT);
	}

	/**
	 * 把一份**已经解析好**的谱面应用成当前谱面。
	 * 用于缓存命中 / 后台线程预解析的结果，避免重复 Json.parse。
	 */
	public static function applyChart(songJson:SwagSong, folder:String, ?path:String):SwagSong
	{
		if(songJson == null) return null;

		PlayState.SONG = songJson;
		loadedSongName = folder;
		chartPath = (path != null ? path : _lastPath);
		#if windows
		if(chartPath != null) chartPath = chartPath.replace('/', '\\');
		#end
		StageData.loadDirectory(songJson);
		return songJson;
	}

	static var _lastPath:String;
	public static function getChart(jsonInput:String, ?folder:String):SwagSong
	{
		if(folder == null) folder = jsonInput;
		var rawData:String = null;

		// 路径解析（含 Normal 难度兼容回退）
		_lastPath = getChartPath(jsonInput, folder);

		try
		{
			#if MODS_ALLOWED
			if(FileSystem.exists(_lastPath))
				rawData = File.getContent(_lastPath);
			else
			#end
				rawData = Assets.getText(_lastPath);
		}
		catch(e:Dynamic)
		{
			trace('Error loading chart file: $e');
			return null;
		}

		return rawData != null ? parseJSON(rawData, jsonInput) : null;
	}

	public static function parseJSON(rawData:String, ?nameForError:String = null, ?convertTo:String = 'psych_v1'):SwagSong
	{
		var songJson:SwagSong = cast Json.parse(rawData);
		if(Reflect.hasField(songJson, 'song'))
		{
			var subSong:SwagSong = Reflect.field(songJson, 'song');
			if(subSong != null && Type.typeof(subSong) == TObject)
				songJson = subSong;
		}

		if(convertTo != null && convertTo.length > 0)
		{
			var fmt:String = songJson.format;
			if(fmt == null) fmt = songJson.format = 'unknown';

			switch(convertTo)
			{
				case 'psych_v1':
					if(!fmt.startsWith('psych_v1')) //Convert to Psych 1.0 format
					{
						trace('converting chart $nameForError with format $fmt to psych_v1 format...');
						songJson.format = 'psych_v1_convert';
						convert(songJson);
					}
			}
		}

		// 防御：谱面可能完全没有 events 字段（常见于已是 psych_v1 的自定义/旧谱），
		// 不补默认空数组会导致 PlayState 遍历 songData.events 时 Null Object Reference 崩溃。
		if (songJson.events == null)
			songJson.events = [];

		// 防御：谱面可能完全没有 notes 字段，避免 PlayState 遍历 SONG.notes 时 Null Object Reference 崩溃。
		if (songJson.notes == null)
			songJson.notes = [];

		// Extra Keys：mania 字段兜底为 3（标准 4 键），与 Psych EK 行为一致。
		// 兼容 "keyCount" 字段（其他多键引擎风格）：keyCount=6 → mania=5。
		if (songJson.keyCount != null && songJson.mania == null)
			songJson.mania = Std.int(songJson.keyCount) - 1;
		if (songJson.mania == null)
			songJson.mania = 3;

		return songJson;
	}
}
