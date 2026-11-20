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

	// 统一键数（1-based，4 键 = 4），语义与 mania 等价：理想情况 keyCount = mania + 1。
	// 作为 mania 缺失时的兜底读取，兼容 Matt/MattV3 等写 keyCount 的引擎。
	// 双侧谱面（两侧键数不同）不参与键数解析，由 playerKeyCount/opponentKeyCount 决定。
	@:optional var keyCount:Int;

	// LE LTS 双侧轨道数（1-based）：玩家侧 / 对手侧键数。
	// 仅当两者同时存在且不相等时进入"双侧模式"。优先级分工：
	//  - 原生 playerKeyCount + opponentKeyCount（新双侧格式）：双侧判定优先，mania 让位；
	//  - 旧 LE 格式 playerKeyCount + keyCount（keyCount 表示对手侧）：仅当没有有效 mania
	//    时才转成 opponentKeyCount；有有效 mania 时按 mania 单侧处理，不转谱。
	//    典型例子：JS Engine 谱面 mania:13 + keyCount:4 + playerKeyCount:14 实为 14K 单侧，
	//    keyCount/playerKeyCount 是残留死字段，不能因为它们在就误判成双侧。
	@:optional var playerKeyCount:Int;
	@:optional var opponentKeyCount:Int;

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

	// 073 旧版制谱器私有：降档时「当前档位装不下」的超范围音符（网格上带 ! 警示）。
	// 不放在 sectionNotes 里，因此不参与 lane 编码、也不进入试玩；其它引擎/工具忽略即可。
	// 随谱面 JSON / autosave 一起保存，重开制谱器时原位恢复。
	@:optional var editorStashedNotes:Array<Dynamic>;

	// 键数字段审计快照：normalizeKeyFields() 就地规范化时会捕获原始声明，
	// 供 Freeplay 谱面信息面板显示"声明值 vs 实际音符列数"的不一致警告。
	// 仅元信息，不参与任何玩法逻辑。
	@:optional var keyAudit:KeyAuditSnapshot;
}

/**
 * 键数字段审计快照（纯元信息）。
 * 记录规范化前的原始声明、规范化后的最终键数，以及原始声明与实际音符列范围是否自洽。
 */
typedef KeyAuditSnapshot =
{
	var hasManiaField:Bool;          // 原谱是否显式写了 mania 字段
	var rawMania:Null<Int>;          // 原始 mania 值（可能无效，如 0）
	var rawKeyCount:Null<Int>;       // 原始 keyCount
	var rawPlayerKeys:Null<Int>;     // 原始 playerKeyCount
	var rawOpponentKeys:Null<Int>;   // 原始 opponentKeyCount / 旧格式转谱来的对手侧
	var rawLegacyKeyCount:Null<Int>; // 旧格式 playerKeyCount+keyCount 里被转谱前的 keyCount
	var finalPlayerKeys:Int;         // 最终玩家侧键数（1-based）
	var finalOpponentKeys:Int;       // 最终对手侧键数（1-based）
	var isDual:Bool;                 // 是否双侧谱面
	var noteMaxCol:Int;              // 玩家段实际最大 noteData（-1=无音符）
	var inferredKeys:Int;            // 音符推断出的键数（-1=未推断）
	var declaredMismatch:Bool;       // 原始 mania 声明与音符列范围不一致
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
	// 规范化后的对手侧键数（1-based）。非双侧谱面 == 玩家侧键数；仅元信息，
	// 运行时玩法判定请统一走 Song.getOpponentKeys()/Song.isDualChart()。
	public var opponentKeyCount:Null<Int>;
	// 键数字段审计快照（规范化时生成，仅用于 UI 诊断显示，不参与玩法）
	public var keyAudit:Null<KeyAuditSnapshot>;
	public var player1:String = 'bf';
	public var player2:String = 'dad';
	public var gfVersion:String = 'gf';
	public var format:String = 'psych_v1';
	public var generatedBy:String;
	public var specialInst:String;
	public var specialVocal:String;
	public var specialEvents:String;

	// ————————————————————————————————————————————————————————————
	// 键数字段统一解析（mania / keyCount / playerKeyCount / opponentKeyCount）
	// 规则（用户定案）：
	//  1) 双侧判定优先：playerKeyCount 与 opponentKeyCount 同时存在且不相等 → 双侧模式，
	//     mania 不参与键数决定（只被规范化成玩家侧档位）。
	//  2) 单侧键数优先级：有效mania > keyCount > opponentKeyCount > playerKeyCount > 默认 4。
	//     理想关系 keyCount = mania + 1（1-based vs 0-based）。
	//     谱面显式写了 mania 但值无效（如 mania:0 死字段）→ 判 4K，不做音符推断。
	//  3) 转谱：仅当"没有有效 mania"且原谱同时有 playerKeyCount + keyCount（无 opponentKeyCount）时，
	//     才把 keyCount 当作对手侧键数写入 opponentKeyCount（旧 LE 谱面兼容）。
	//     有有效 mania 时按优先级 mania 优先，跳过转谱——JS Engine 等改版谱面会同时写
	//     mania:13 + keyCount:4 + playerKeyCount:14 这类噪声字段，其实只是单侧 14K。
	//  4) 所有字段都做 1..18 范围钳制，越界/null 一律回落到合法值，杜绝 0/1 键误判。
	// ————————————————————————————————————————————————————————————

	/** 键数钳制到 1..18；非法（null / NaN / 越界）回落到 fallback。 */
	inline public static function clampKeyCount(v:Dynamic, fallback:Int = 4):Int
	{
		if (v == null) return fallback;
		var f:Float = Std.parseFloat(Std.string(v));
		if (Math.isNaN(f)) return fallback;
		var n:Int = Std.int(f);
		if (n < 1 || n > 18) return fallback;
		return n;
	}

	/**
	 * mania 字段是否有效（0-based 档位，1..17 合法 → 2..18 键）。
	 * mania<=0 视为"未填"：原版 Psych 0.6.3/0.7.3/1.0.4 的 SwagSong 根本没有 mania 字段，
	 * 旧模组谱里的 mania:0 只是被制谱工具写进来的死字段，作者本意是标准 4K；
	 * 只有 EK 补丁把它当 0-based 档位，mania:0 才会被读成 1 键（单箭头）。
	 * 真正的 1K 谱面几乎不存在，故统一把 <=0 当作未填，让位给 keyCount / 默认 4K。
	 */
	inline public static function isValidMania(v:Dynamic):Bool
	{
		if (v == null) return false;
		var f:Float = Std.parseFloat(Std.string(v));
		return !Math.isNaN(f) && f >= 1 && f <= 17;
	}

	/**
	 * 用谱面实际音符列分布推断真实键数。仅在"完全没有可信键数字段"时作为兜底调用
	 * （典型：旧 Psych 谱的 mania:0 死字段）。有明确 keyCount/mania 时绝不用它——
	 * psych_v1 的 noteData 是 0..2K-1 绝对双列编码，用它会把 4K 双侧谱误判成 8K。
	 *
	 * 返回"密集列"的最大列号 + 1；找不到有效音符则返回 -1。
	 * 关键点：
	 *  1) 只统计玩家段（mustHitSection=true）——老式相对编码谱里对手侧音符的 noteData
	 *     也是 0..K-1（相对列号），算进来会把列边界虚增一倍。
	 *  2) 忽略稀疏的孤立脏音符——例如某些旧谱在 4K 布局里混入单个 noteData=4，
	 *     不能因它就判成 5K。判定标准：该列音符数 >= max(2, 玩家段音符总数 * 1%)。
	 */
	public static function inferKeysFromNotes(song:Dynamic):Int
	{
		if (song == null || song.notes == null) return -1;
		var sections:Array<Dynamic> = cast song.notes;
		var counts:Map<Int, Int> = new Map();
		var total:Int = 0;
		for (section in sections)
		{
			if (section == null || section.sectionNotes == null) continue;
			if (section.mustHitSection == false) continue; // 对手段用相对列号，跳过
			var notes:Array<Dynamic> = cast section.sectionNotes;
			for (note in notes)
			{
				if (note == null || note.length < 2) continue;
				var d:Int = Std.int(note[1]);
				if (d < 0) continue; // 事件音符
				counts.set(d, (counts.get(d) != null ? counts.get(d) : 0) + 1);
				total++;
			}
		}
		if (total == 0) return -1;
		var threshold:Float = Math.max(2, total * 0.01);
		var maxCol:Int = -1;
		for (col => cnt in counts)
			if (cnt >= threshold && col > maxCol) maxCol = col;
		return maxCol >= 0 ? (maxCol + 1) : -1;
	}

	/** 是否双侧谱面（两侧字段同时存在且不相等）。全项目唯一判定口径。 */
	public static function isDualChart(song:Dynamic):Bool
	{
		if (song == null) return false;
		if (song.playerKeyCount == null || song.opponentKeyCount == null) return false;
		return Std.int(song.playerKeyCount) != Std.int(song.opponentKeyCount);
	}

	/** 玩家侧键数（1-based）。 */
	public static function getPlayerKeys(song:Dynamic):Int
	{
		if (song == null) return 4;
		if (isDualChart(song)) return clampKeyCount(song.playerKeyCount, 4);
		// 单侧：mania（仅有效档位）> keyCount > opponentKeyCount > playerKeyCount > 4
		if (isValidMania(song.mania)) return Std.int(song.mania) + 1;
		if (song.keyCount != null) return clampKeyCount(song.keyCount, 4);
		if (song.opponentKeyCount != null) return clampKeyCount(song.opponentKeyCount, 4);
		if (song.playerKeyCount != null) return clampKeyCount(song.playerKeyCount, 4);
		return 4;
	}

	/** 对手侧键数（1-based）。非双侧恒等于玩家侧。 */
	public static function getOpponentKeys(song:Dynamic):Int
	{
		if (song == null) return 4;
		if (isDualChart(song)) return clampKeyCount(song.opponentKeyCount, 4);
		return getPlayerKeys(song);
	}

	/**
	 * 就地规范化谱面键数字段，保证下游读到的 SONG 字段自洽：
	 *  - 转谱：playerKeyCount + keyCount（无 opponentKeyCount）→ opponentKeyCount = keyCount；
	 *  - 双侧：保留两侧真值，mania = 玩家侧档位，keyCount = 玩家侧键数（= mania+1）；
	 *  - 单侧：按优先级定出键数 K，写入 mania=K-1、keyCount=K，并清掉残留的两侧字段
	 *    （避免脏字段在运行时被误判成双侧）。
	 */
	/** 取原始整数值（不做键数钳制，保留 0/-1 这类无效值供审计显示）。 */
	inline static function rawInt(v:Dynamic):Null<Int>
	{
		if (v == null) return null;
		var f:Float = Std.parseFloat(Std.string(v));
		if (Math.isNaN(f)) return null;
		return Std.int(f);
	}

	/** 扫描整谱所有音符（含对手段）的最大 noteData，用于审计"声明 vs 音符列范围"。 */
	static function scanMaxNoteColumn(song:Dynamic):Int
	{
		if (song == null || song.notes == null) return -1;
		var sections:Array<Dynamic> = cast song.notes;
		var maxCol:Int = -1;
		for (section in sections)
		{
			if (section == null || section.sectionNotes == null) continue;
			var notes:Array<Dynamic> = cast section.sectionNotes;
			for (note in notes)
			{
				if (note == null || note.length < 2) continue;
				var d:Int = Std.int(note[1]);
				if (d >= 0 && d > maxCol) maxCol = d;
			}
		}
		return maxCol;
	}

	public static function normalizeKeyFields(song:Dynamic):Void
	{
		if (song == null) return;

		// —— 审计：在任何修改前捕获原始声明 ——
		var hasManiaField:Bool = Reflect.hasField(song, 'mania') && song.mania != null;
		var rawMania:Null<Int> = hasManiaField ? rawInt(song.mania) : null;
		var rawKeyCount:Null<Int> = song.keyCount != null ? rawInt(song.keyCount) : null;
		var rawPlr:Null<Int> = song.playerKeyCount != null ? rawInt(song.playerKeyCount) : null;
		var rawOpp:Null<Int> = song.opponentKeyCount != null ? rawInt(song.opponentKeyCount) : null;
		var rawLegacyKeyCount:Null<Int> = null; // 旧格式 playerKeyCount+keyCount 里被转谱前的 keyCount
		var needsTranscribe:Bool = !isValidMania(song.mania) && song.playerKeyCount != null
			&& song.keyCount != null && song.opponentKeyCount == null;
		if (needsTranscribe) rawLegacyKeyCount = rawKeyCount;

		var noteMaxCol:Int = scanMaxNoteColumn(song);
		// 声明的 mania 与音符列范围是否不一致：
		// 绝对双列编码下 K 键最多用到 2K-1 列；超出说明声明的键数明显偏小。
		// 例：mania:0 → 声明 1K，最多容纳 0..1 列；音符却到 3/7 → 不一致（That-Girl / childs-play）。
		// mania:13 → 14K，最多 0..27；音符到 13 → 一致（fuck-14k）。
		var declaredMismatch:Bool = false;
		if (rawMania != null && noteMaxCol >= 0)
		{
			var declaredKeys:Int = rawMania + 1;
			if (declaredKeys >= 1 && noteMaxCol > 2 * declaredKeys - 1)
				declaredMismatch = true;
		}

		// 写入审计快照的局部函数（dual / 单侧两条路径都调用）
		function commitAudit(plr:Int, opp:Int, dual:Bool, inferred:Int):Void
		{
			song.keyAudit = {
				hasManiaField: hasManiaField,
				rawMania: rawMania,
				rawKeyCount: rawKeyCount,
				rawPlayerKeys: rawPlr,
				rawOpponentKeys: rawOpp,
				rawLegacyKeyCount: rawLegacyKeyCount,
				finalPlayerKeys: plr,
				finalOpponentKeys: opp,
				isDual: dual,
				noteMaxCol: noteMaxCol,
				inferredKeys: inferred,
				declaredMismatch: declaredMismatch
			};
		}

		// 转谱：旧 LE 谱面 keyCount 语义是对手侧键数。
		// 前提：没有有效 mania——否则 mania 优先，直接按单侧处理，绝不转谱。
		// （JS Engine 等改版谱面会残留 mania:13 + keyCount:4 + playerKeyCount:14，
		//   实际是单侧 14K；无条件转谱会把它误判成 14K vs 4K 双侧。）
		if (needsTranscribe)
			song.opponentKeyCount = clampKeyCount(song.keyCount, 4);

		if (isDualChart(song))
		{
			var plr:Int = clampKeyCount(song.playerKeyCount, 4);
			var opp:Int = clampKeyCount(song.opponentKeyCount, 4);
			song.playerKeyCount = plr;
			song.opponentKeyCount = opp;
			song.mania = plr - 1;
			song.keyCount = plr;
			commitAudit(plr, opp, true, -1);
			return;
		}

		// 单侧：优先级 有效mania > keyCount > opponentKeyCount > playerKeyCount > 4
		var keys:Int = 4;
		var hasExplicitField:Bool = false; // 是否有一个可信的显式键数字段
		if (isValidMania(song.mania)) { keys = Std.int(song.mania) + 1; hasExplicitField = true; }
		else if (song.keyCount != null) { keys = clampKeyCount(song.keyCount, 4); hasExplicitField = true; }
		else if (song.opponentKeyCount != null) { keys = clampKeyCount(song.opponentKeyCount, 4); hasExplicitField = true; }
		else if (song.playerKeyCount != null) { keys = clampKeyCount(song.playerKeyCount, 4); hasExplicitField = true; }
		else if (hasManiaField)
		{
			// 谱面显式写了 mania 但值无效（典型 mania:0 死字段）——来自老 Psych/EK 系工具，
			// 作者本意是标准 4K。此时绝不能用音符推断：这些谱的 noteData 是 0..2K-1
			// 绝对双列编码或混了多键残留，max(noteData)+1 会把 childs-play 这类 4K 谱误判成 8K。
			// 直接按 4K 处理，并标记"已有意图"，跳过下面的音符兜底。
			keys = 4;
			hasExplicitField = true;
		}

		// 无键数字段 → 原版 4K，不做音符推断。
		// 原因：原版 Psych/psych_v1 的 noteData 是 0..2K-1 绝对双列编码（玩家 0..K-1 / 对手 K..2K-1），
		// 标准 4K 谱的音符会到 0..7。若按 max(noteData)+1 推断，2hot 会被读成 8K、bopeebo 读成 7K，
		// 导致原生 4K 曲被当多键游玩。真正多键谱必然带 mania/keyCount 字段，已在上面读到，
		// 所以"无字段"本身就等价于"标准 4K"，无需（也不能）靠音符猜。
		// inferKeysFromNotes() 保留为诊断工具（审计快照用），但绝不参与键数决策。

		song.mania = keys - 1;
		song.keyCount = keys;
		// 两侧相等或只填了一个：清掉，保持非双侧语义，杜绝残留字段再次误判
		if (Reflect.hasField(song, 'playerKeyCount')) Reflect.deleteField(song, 'playerKeyCount');
		if (Reflect.hasField(song, 'opponentKeyCount')) Reflect.deleteField(song, 'opponentKeyCount');
		commitAudit(keys, keys, false, -1);
	}

	/**
	 * 旧式数字索引 -> 类型名。原版 `Note.defaultNoteTypes[note[3]]` 是无防护索引，
	 * 遇到 null / 越界 / 浮点索引会读到 undefined 并把它写回 [3]，导致编辑器不显示
	 * 类型编号、PlayState 里特殊音符效果失效。这里加边界检查，读不到就退回空类型。
	 */
	public static function safeDefaultNoteType(v:Dynamic):String
	{
		if (Std.isOfType(v, String)) return cast(v, String);
		if (v == null) return '';
		var idx:Int = Std.int(v);
		return (idx >= 0 && idx < Note.defaultNoteTypes.length) ? Note.defaultNoteTypes[idx] : '';
	}

	public static function convert(songJson:Dynamic) // Convert old charts to psych_v1 format
	{
		if(songJson.gfVersion == null)
		{
			songJson.gfVersion = songJson.player3;
			if(Reflect.hasField(songJson, 'player3')) Reflect.deleteField(songJson, 'player3');
		}

		// Extra Keys：列数统一取规范化后的玩家侧键数（parseJSON 已在 convert 之前调用 normalizeKeyFields）。
		// legacy 谱面无键数字段 → 兜底 4 列；多键谱面（keyCount:6 / mania:5）→ 6 列。
		// LE LTS 双侧模式：列重排整体跳过，保留原始连续 noteData 交给运行时解析。
		var dualMode:Bool = isDualChart(songJson);
		var sectCols:Int = getPlayerKeys(songJson);

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
				// LE LTS 双侧模式：保留谱面原始连续 noteData（mustHit 段 0..playerKeyCount-1 = 玩家、
				// playerKeyCount.. = 对手；非 mustHit 段反之），运行时按事件时间点映射。不做列折叠。
			if (dualMode)
			{
				if(!Std.isOfType(note[3], String))
					note[3] = safeDefaultNoteType(note[3]);
				continue;
			}
				// 列数从硬编码 4 改成按 mania 档位动态计算。
				// legacy 相对车道：0..sectCols-1 = 当前小节归属方，sectCols..2*sectCols-1 = 另一方。
				// psych_v1 绝对车道：0..sectCols-1 永远是玩家，sectCols..2*sectCols-1 永远是对手。
				var gottaHitNote:Bool = (note[1] < sectCols) ? section.mustHitSection : !section.mustHitSection;
				note[1] = (note[1] % sectCols) + (gottaHitNote ? 0 : sectCols);

				if(!Std.isOfType(note[3], String))
					note[3] = safeDefaultNoteType(note[3]);
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
				var rawDir:String = Paths.mods(Mods.currentModDirectory + '/data/' + formattedFolder);
				var dir:String = ClientPrefs.data.modPathCompat ? Paths.resolveModPath(rawDir) : rawDir;
				if(dir != null && FileSystem.exists(dir) && FileSystem.isDirectory(dir))
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

		// 键数字段统一规范化（含旧 LE 谱面 keyCount→opponentKeyCount 转谱），
		// 必须在 convert() 之前完成：convert 的列折叠依赖规范化后的键数。
		normalizeKeyFields(songJson);

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

		// 键数字段已在 convert() 之前由 normalizeKeyFields() 统一规范化：
		//  - 双侧：mania = 玩家侧档位；keyCount = 玩家侧键数；两侧真值保留；
		//  - 单侧：mania/keyCount 按优先级定档并自洽，残留两侧字段已清除。
		// 事件 "change keycount" 的运行时改键由 PlayState.changeKeyCounts 处理，不写回 SONG。

		return songJson;
	}
}
