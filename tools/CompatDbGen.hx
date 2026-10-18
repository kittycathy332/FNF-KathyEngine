/**
 * Kathy Engine —— Lua API 兼容性数据库生成器（开发期工具，不参与游戏编译）
 *
 * 作用：扫描 4 个引擎源码树，提取「Lua 全局函数」与「回调钩子」分别在哪些版本中存在，
 *      生成一个烘焙进引擎的静态数据文件（source/psychlua/compat/CompatData.hx）。
 *
 * 为什么要离线生成：游戏在 Android 上读不到开发机的参考源码目录，
 *      所以版本对比只能在开发机构建期做一次，产物随游戏一起编译。
 *
 * 用法（在项目根目录执行）：
 *   haxe -cp tools --run CompatDbGen <kathySrc> <pe104Src> <pe073Src> <pe063Src> <outFile>
 *
 * 例：
 *   haxe -cp tools --run CompatDbGen ^
 *     "e:/EXTRA/FNF/For Android/KathyEngine/source" ^
 *     "e:/EXTRA/FNF/ENGINE/PE/FNF-PsychEngine-1.0.4/source" ^
 *     "e:/EXTRA/FNF/ENGINE/PE/FNF-PsychEngine-0.7.3/source" ^
 *     "e:/EXTRA/FNF/ENGINE/PE/FNF-PsychEngine-0.6.3/source" ^
 *     "source/psychlua/compat/CompatData.hx"
 *
 * 参考源码更新后（如换引擎版本），重跑一次即可。
 */
import sys.FileSystem;
import sys.io.File;
using StringTools;

class CompatDbGen
{
	// 版本下标顺序固定为: 0=kathy, 1=1.0.4, 2=0.7.3, 3=0.6.3, 4=le（LE API 运行时）
	// （与 CompatData.VERSIONS 一致；le = LeatherLuaScript 提供的 LE API，官方/LTS 合并）
	static inline var V_COUNT:Int = 5;
	// 需要独立目录扫描的版本数（LE 数据从 kathy 源码的 LeatherLuaScript.hx / PlayState.hx 提取，见 extract()）
	static inline var SCAN_DIRS:Int = 4;

	// 各版本的函数 / 钩子集合
	static var funcFound:Array<Map<String, Bool>>;
	static var hookFound:Array<Map<String, Bool>>;
	static var fileCount:Int = 0;

	// 提取「Lua 全局函数」与「回调钩子」的辅助正则：
	//   先用 finder 定位调用点，再在调用点后的片段里取第一个引号名字。
	// 说明：刻意避开懒量词（*?），因为 Haxe eval 的 EReg 在大文件上会严重退化。
	static inline var RE_IDENT_QUOTED:String = '["\']([A-Za-z_][A-Za-z0-9_]*)["\']';

	// 调用点后最多观察多少个字符（足够覆盖常规的注册/分发调用）
	static inline var CALL_LOOKAHEAD:Int = 300;

	// 不以 on 开头的合法钩子（其余钩子都形如 onXxx）
	static var HOOK_EXTRA:Array<String> = [
		'eventEarlyTrigger', 'ghostNoteMiss', 'goodNoteHit', 'goodNoteHitPre',
		'noteMiss', 'noteMissPress', 'opponentNoteHit', 'opponentNoteHitPre', 'preUpdateScore'
	];

	public static function main()
	{
		var args:Array<String> = Sys.args();
		if (args.length < 5)
		{
			Sys.println('用法: haxe -cp tools --run CompatDbGen <kathySrc> <pe104Src> <pe073Src> <pe063Src> <outFile>');
			Sys.exit(1);
		}

		var dirs:Array<String> = [args[0], args[1], args[2], args[3]];
		var outFile:String = args[4];

		funcFound = [for (_ in 0...V_COUNT) new Map<String, Bool>()];
		hookFound = [for (_ in 0...V_COUNT) new Map<String, Bool>()];

		for (i in 0...SCAN_DIRS)
		{
			if (!FileSystem.exists(dirs[i]))
			{
				Sys.println('警告: 目录不存在，跳过 -> ${dirs[i]}');
				continue;
			}
			Sys.println('扫描中 [版本 $i]: ${dirs[i]}');
			scanDir(dirs[i], i);
			Sys.println('  -> 累计扫描 .hx 文件: $fileCount');
		}

		File.saveContent(outFile, build(outFile));
		Sys.println('已生成: $outFile');
		Sys.println('函数条目: ${union(funcFound).length}  钩子条目: ${union(hookFound).length}');
	}

	/** 递归扫描目录下所有 .hx 文件 */
	static function scanDir(dir:String, version:Int):Void
	{
		var entries:Array<String> = FileSystem.readDirectory(dir);
		for (e in entries)
		{
			var full:String = dir + '/' + e;
			if (FileSystem.isDirectory(full))
			{
				scanDir(full, version);
			}
			else if (e.endsWith('.hx'))
			{
				fileCount++;
				extract(File.getContent(full), version, full);
			}
		}
	}

	/** 从单个文件内容里提取函数名与钩子名 */
	static function extract(src:String, version:Int, path:String = ''):Void
	{
		// Lua_helper.add_callback(lua, "name", ...) —— 名字是第 2 个参数（前面有逗号）
		collectFromCalls(src, 'add_callback', true, funcFound[version]);
		// addLocalCallback("name", ...) —— 名字是第 1 个参数（前面无逗号）
		collectFromCalls(src, 'addLocalCallback', false, funcFound[version]);
		// callOnScripts / callOnLuas / callOnHScript('hookName', ...) —— 名字是第 1 个参数
		collectFromCalls(src, 'callOnScripts', false, hookFound[version], isHookName);
		collectFromCalls(src, 'callOnLuas', false, hookFound[version], isHookName);
		collectFromCalls(src, 'callOnHScript', false, hookFound[version], isHookName);
		// FunkinLua/HScript 直接派发：call('onCreate', ...) / hscript.call('onDestroy')
		collectFromCalls(src, 'call', false, hookFound[version], isHookName);
		// 变量派发：xxx ? 'goodNoteHit' : 'opponentNoteHit'
		collectTernaries(src, hookFound[version], isHookName);

		// ---- LE API 运行时（下标 4）：Kathy 移植版的两个关键文件 ----
		if (version == 0)
		{
			// LeatherLuaScript.hx 的 setFunction('name', ...) 注册 → LE 全局函数。
			// Kathy 自带 LE 运行时，故同时写 kathy 位（下标 0）与 le 位（下标 4）。
			if (path.indexOf('psychlua/leather/LeatherLuaScript.hx') >= 0)
			{
				collectFromCalls(src, 'setFunction', false, funcFound[4]);
				collectFromCalls(src, 'setFunction', false, funcFound[0]);
			}
			// PlayState.hx 的 callOnLeatherScripts('name', ...) 广播 → LE 回调钩子
			// （LE 钩子名不全是 onXxx（update/popUpScore/playerOneSing…），不过滤）
			if (path.indexOf('states/PlayState.hx') >= 0)
			{
				collectFromCalls(src, 'callOnLeatherScripts', false, hookFound[4]);
				collectFromCalls(src, 'callOnLeatherScripts', false, hookFound[0]);
			}
		}
	}

	/** 合法钩子名的判定：on + 大写字母开头，或在 HOOK_EXTRA 白名单内 */
	static function isHookName(name:String):Bool
	{
		if (name.length > 2 && name.substr(0, 2) == 'on')
		{
			var c = name.charAt(2);
			if (c >= 'A' && c <= 'Z') return true;
		}
		return HOOK_EXTRA.indexOf(name) >= 0;
	}

	/** 收集 `cond ? 'a' : 'b'` 形式里的两个字符串名（用于变量派发的钩子） */
	static function collectTernaries(src:String, target:Map<String, Bool>, filter:String->Bool):Void
	{
		var re = new EReg('\\?\\s*["\']([A-Za-z_][A-Za-z0-9_]*)["\']\\s*:\\s*["\']([A-Za-z_][A-Za-z0-9_]*)["\']', '');
		var from:Int = 0;
		while (true)
		{
			var idx:Int = src.indexOf('?', from);
			if (idx < 0) break;
			from = idx + 1;
			if (re.match(src.substr(idx, CALL_LOOKAHEAD)))
			{
				var a = re.matched(1);
				var b = re.matched(2);
				if (filter(a)) target.set(a, true);
				if (filter(b)) target.set(b, true);
			}
		}
	}

	/**
	 * 定位所有 `callName(...)` 调用点，取调用点后第一个「引号包裹的标识符」作为名字。
	 * 用 indexOf 手动推进（不依赖 EReg 的 g 标志——eval 目标上 g 不会推进，会死循环）。
	 * @param nameIsSecondArg true = 名字前应有逗号（add_callback 形态）；false = 名字应是第一个参数
	 */
	static function collectFromCalls(src:String, callName:String, nameIsSecondArg:Bool, target:Map<String, Bool>,
		?filter:String->Bool = null):Void
	{
		var quoted = new EReg(RE_IDENT_QUOTED, '');
		var from:Int = 0;
		while (true)
		{
			var idx:Int = src.indexOf(callName, from);
			if (idx < 0) break;
			from = idx + callName.length;

			// 左侧词边界：避免匹配到 xxxadd_callback
			if (idx > 0 && isWordChar(src.charAt(idx - 1))) continue;

			// 右侧需为可选空白 + '('
			var j:Int = idx + callName.length;
			while (j < src.length && isSpaceChar(src.charAt(j))) j++;
			if (j >= src.length || src.charAt(j) != '(') continue;

			var rest:String = src.substr(j + 1, CALL_LOOKAHEAD);
			if (!quoted.match(rest)) continue;

			var qPos:Int = quoted.matchedPos().pos;
			var comma:Int = rest.indexOf(',');
			var ok:Bool = nameIsSecondArg ? (comma >= 0 && qPos > comma) : (comma < 0 || qPos < comma);
			if (!ok) continue;

			var name = quoted.matched(1);
			if (filter == null || filter(name)) target.set(name, true);
		}
	}

	static inline function isSpaceChar(c:String):Bool
		return c == ' ' || c == '\t' || c == '\r' || c == '\n';

	static inline function isWordChar(c:String):Bool
	{
		var code = c.charCodeAt(0);
		return (code >= 97 && code <= 122) || (code >= 65 && code <= 90) || (code >= 48 && code <= 57) || code == 95;
	}

	/** 所有版本出现过的名字并集，已排序 */
	static function union(sets:Array<Map<String, Bool>>):Array<String>
	{
		var seen:Map<String, Bool> = new Map<String, Bool>();
		for (s in sets)
			for (k in s.keys())
				seen.set(k, true);
		var out:Array<String> = [for (k in seen.keys()) k];
		out.sort(Reflect.compare);
		return out;
	}

	/** 生成某名字在 4 个版本下的可用性掩码，如 "1011" */
	static function maskOf(sets:Array<Map<String, Bool>>, name:String):String
	{
		var sb:StringBuf = new StringBuf();
		for (i in 0...V_COUNT)
			sb.add(sets[i].exists(name) ? '1' : '0');
		return sb.toString();
	}

	static function emitMask(sb:StringBuf, comment:String, sets:Array<Map<String, Bool>>, fieldName:String):Void
	{
		sb.add('\t// $comment\n');
		sb.add('\tpublic static final $fieldName:Map<String, String> = [\n');
		for (n in union(sets))
			sb.add('\t\t\'$n\' => \'${maskOf(sets, n)}\',\n');
		sb.add('\t];\n\n');
	}

	static function build(outFile:String):String
	{
		var sb:StringBuf = new StringBuf();
		sb.add('/**\n');
		sb.add(' * 自动生成，请勿手动编辑。\n');
		sb.add(' * 生成器: tools/CompatDbGen.hx\n');
		sb.add(' * 生成命令: haxe -cp tools --run CompatDbGen <kathySrc> <pe104Src> <pe073Src> <pe063Src> <outFile>\n');
		sb.add(' *\n');
		sb.add(' * 掩码顺序: kathy, 1.0.4, 0.7.3, 0.6.3, le （\'1\'=该版本提供，\'0\'=不提供；le=LE API 运行时）\n');
		sb.add(' */\n');
		sb.add('package psychlua.compat;\n\n');
		sb.add('class CompatData\n{\n');
		sb.add('\tpublic static final VERSIONS:Array<String> = [\'kathy\', \'1.0.4\', \'0.7.3\', \'0.6.3\', \'le\'];\n\n');

		emitMask(sb, 'Lua 全局函数名 => 提供该函数的版本掩码', funcFound, 'FUNC_MASK');
		emitMask(sb, '回调钩子名 => 会分发该钩子的版本掩码', hookFound, 'HOOK_MASK');

		// 查询辅助（生成器固定输出，保持稳定）
		sb.add('\t/** 掩码中某下标位是否为 1 */\n');
		sb.add('\tpublic static inline function maskHas(mask:String, index:Int):Bool\n');
		sb.add('\t\treturn mask != null && index >= 0 && index < mask.length && mask.charAt(index) == "1";\n\n');

		sb.add('\t/** 某函数可用版本的名称列表；未知函数返回空数组 */\n');
		sb.add('\tpublic static function versionsOfFunction(name:String):Array<String>\n');
		sb.add('\t{\n');
		sb.add('\t\tvar out:Array<String> = [];\n');
		sb.add('\t\tvar m:String = FUNC_MASK.get(name);\n');
		sb.add('\t\tif (m == null) return out;\n');
		sb.add('\t\tfor (i in 0...VERSIONS.length) if (maskHas(m, i)) out.push(VERSIONS[i]);\n');
		sb.add('\t\treturn out;\n');
		sb.add('\t}\n\n');

		sb.add('\t/** 某钩子会生效的版本名称列表；未知钩子返回空数组 */\n');
		sb.add('\tpublic static function versionsOfHook(name:String):Array<String>\n');
		sb.add('\t{\n');
		sb.add('\t\tvar out:Array<String> = [];\n');
		sb.add('\t\tvar m:String = HOOK_MASK.get(name);\n');
		sb.add('\t\tif (m == null) return out;\n');
		sb.add('\t\tfor (i in 0...VERSIONS.length) if (maskHas(m, i)) out.push(VERSIONS[i]);\n');
		sb.add('\t\treturn out;\n');
		sb.add('\t}\n');
		sb.add('}\n');
		return sb.toString();
	}
}
