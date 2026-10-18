package psychlua.compat;

import backend.Mods;
import backend.Paths;

/**
 * 模组 Lua/HScript 兼容性「静态扫描器」。
 *
 * 原理：读取模组目录里的 .lua / .hx 脚本文本 → 去掉注释与字符串 → 提取
 *   —— 全局函数的调用点（name( 形式，排除库调用 name.xxx( / obj:xxx( ）
 *   —— 脚本自身定义过的函数名（function name / local function name / name = function）
 *   —— 其中命中 CompatData.HOOK_MASK 的定义名即视为回调钩子
 * 再与 CompatData（由 tools/CompatDbGen.hx 离线生成）比对，得出「哪些名字在
 * Kathy / Psych 1.0.4 / Psych 0.7.3 / Psych 0.6.3 下可用」。
 *
 * 报告只列出「有问题」的条目（Kathy 独占、仅 Legacy 提供、疑似拼写错误），
 * 全版本通用的 API 不逐条列出，避免刷屏。
 *
 * 注意：这是静态分析，注释里写代码、字符串拼接调用、_G[...] 动态调用等
 * 无法识别；HScript(.hx) 仅做浅层检测（不做类成员级校验）。结果仅供参考。
 */
typedef CompatFinding = {
	var name:String;
	/** true=回调钩子，false=全局函数 */
	var isHook:Bool;
	/** 0=提示 1=警告 2=不兼容 */
	var severity:Int;
	/** 该名字可用的版本列表 */
	var versions:Array<String>;
	/** 出现的脚本相对路径（最多展示前若干条） */
	var files:Array<String>;
	/** 说明文案（中文，供 UI 直接显示） */
	var note:String;
}

typedef CompatReport = {
	var mod:String;
	var scannedFiles:Int;
	var luaFiles:Int;
	var hxFiles:Int;
	/** 识别到的引擎 API 名字总数（含正常的） */
	var knownNames:Int;
	/** 有问题的条目 */
	var findings:Array<CompatFinding>;
	/** 扫描过程中遇到的错误（如读盘失败） */
	var errors:Array<String>;
}

private typedef ScanResult = {
	var calls:Array<String>;
	var hooks:Array<String>;
}

class ModCompatScanner
{
	public static final SEV_INFO:Int = 0;
	public static final SEV_WARN:Int = 1;
	public static final SEV_ERROR:Int = 2;

	/** 遍历时跳过的重型资源目录（里面不会放脚本） */
	static var SKIP_DIRS:Array<String> = ['images', 'sounds', 'music', 'songs', 'fonts', 'videos', '.git'];

	/** Lua 关键字 */
	static var LUA_KEYWORDS:Array<String> = [
		'and', 'break', 'do', 'else', 'elseif', 'end', 'false', 'for', 'function', 'goto', 'if', 'in',
		'local', 'nil', 'not', 'or', 'repeat', 'return', 'then', 'true', 'until', 'while'
	];

	/** Lua 标准库 / 常用全局，避免误报为引擎 API */
	static var LUA_STDLIB:Array<String> = [
		'print', 'type', 'tostring', 'tonumber', 'pairs', 'ipairs', 'next', 'select', 'pcall', 'xpcall',
		'error', 'assert', 'setmetatable', 'getmetatable', 'rawget', 'rawset', 'rawequal', 'rawlen',
		'unpack', 'require', 'dofile', 'load', 'loadstring', 'collectgarbage', 'setfenv', 'getfenv',
		'string', 'table', 'math', 'os', 'io', 'coroutine', 'debug', 'utf8', 'arg', '_G', '_VERSION'
	];

	public static function listMods():Array<String>
	{
		#if sys
		return Mods.getModDirectories();
		#else
		return [];
		#end
	}

	// ---- Leather Engine 模组检测 ----
	public static final LE_NONE:Int = 0;      // 非 LE 模组（Psych 系）
	public static final LE_OFFICIAL:Int = 1;  // LE Official 系（0.4.x / 0.5.0，data/song data 等带空格目录）
	public static final LE_LTS:Int = 2;       // LE LTS 1.1.9（data/charts + {folder}-metadata）
	public static final LE_UNKNOWN:Int = 3;   // 有 LE 特征（_polymod_meta.json 且无 pack.json）但目录结构无法定版

	/** 检测模组是否为 Leather Engine 模组并分辨版本家族（复用 Song.isLeatherMod 的判定思路，独立实现避免依赖 backend） */
	public static function detectLeather(modName:String):Int
	{
		#if sys
		var root:String = Paths.mods(modName);
		if (!sys.FileSystem.exists(root)) return LE_NONE;

		var hasMeta:Bool = sys.FileSystem.exists(root + '/_polymod_meta.json');
		var hasPack:Bool = sys.FileSystem.exists(root + '/pack.json');
		var hasSongData:Bool = sys.FileSystem.exists(root + '/data/song data');
		var hasCharts:Bool = sys.FileSystem.exists(root + '/data/charts');
		var hasCharData:Bool = sys.FileSystem.exists(root + '/data/character data');
		var hasStageData:Bool = sys.FileSystem.exists(root + '/data/stage data');

		// LTS 1.1.9：data/charts + {folder}-metadata
		if (hasCharts) return LE_LTS;
		// Official 0.5.0 / 0.4.x：data/song data 等 LE 特有带空格目录
		if (hasSongData || hasCharData || hasStageData) return LE_OFFICIAL;
		// Polymod 元数据存在且无 Psych pack.json → LE 系（目录结构未知，无法进一步定版）
		if (hasMeta && !hasPack) return LE_UNKNOWN;
		#end
		return LE_NONE;
	}

	/** LE 类型显示名（中文，供 UI 徽章/报告直接显示） */
	public static function leatherTypeName(t:Int):String
	{
		return switch(t)
		{
			case LE_OFFICIAL: 'LE Official / 0.4.x';
			case LE_LTS: 'LE LTS 1.1.9';
			case LE_UNKNOWN: 'LE ?';
			default: '';
		}
	}

	/**
	 * 扫描一个模组。
	 * @param modName 模组文件夹名（相对 mods/）
	 * @param deep    true 时额外跑一次运行探针（沙箱执行脚本捕获动态访问的全局名）
	 */
	public static function scan(modName:String, ?deep:Bool = false):CompatReport
	{
		var report:CompatReport = {
			mod: modName,
			scannedFiles: 0,
			luaFiles: 0,
			hxFiles: 0,
			knownNames: 0,
			findings: [],
			errors: []
		};

		// 名字 -> 出现的文件（相对路径）；在 #if sys 内外都要可见
		var funcs:Map<String, Array<String>> = new Map();
		var hooks:Map<String, Array<String>> = new Map();

		#if sys
		var root:String = Paths.mods(modName);
		if (!sys.FileSystem.exists(root))
		{
			report.errors.push('模组目录不存在: ' + root);
			return report;
		}

		var files:Array<String> = [];
		collectScriptFiles(root, files, 0);

		// 每个脚本走哪个运行时（LE API / Psych API）：与 PlayState 的加载路由一致
		var fileRoute:Map<String, String> = new Map();
		for (abs in files)
		{
			var rel:String = abs.substr(root.length);
			if (rel.startsWith('/') || rel.startsWith('\\')) rel = rel.substr(1);
			fileRoute.set(rel, psychlua.leather.LeatherScriptRouter.detectScriptRuntime(abs, ''));

			var content:String = null;
			try
			{
				content = sys.io.File.getContent(abs);
			}
			catch (e:Dynamic)
			{
				report.errors.push('读取失败: ' + rel);
				continue;
			}
			if (content == null) continue;

			report.scannedFiles++;
			var isLua:Bool = abs.toLowerCase().endsWith('.lua');
			if (isLua) report.luaFiles++ else report.hxFiles++;

			var res:ScanResult = isLua ? scanLua(content) : scanHx(content);
			for (n in res.calls) addName(funcs, n, rel);
			for (n in res.hooks) addName(hooks, n, rel);
		}

		// 可选：运行探针（把脚本放进沙箱执行，捕获运行时访问到的全局名）
		// CompatProbe 仅在 LUA_ALLOWED（cpp）下存在，其他目标自动跳过深度检测。
		if (deep)
		{
			#if LUA_ALLOWED
			var probe:Map<String, Bool> = CompatProbe.run(files);
			if (probe != null)
			{
				for (n in probe.keys())
				{
					if (isLuaKeyword(n) || isLuaStdlib(n)) continue;
					if (!funcs.exists(n) && !hooks.exists(n)) addName(funcs, n, '(run-probe)');
				}
			}
			#end
		}

		#end

		// 组装 findings
		var findings:Array<CompatFinding> = [];
		var known:Int = 0;

		for (n in funcs.keys())
		{
			var f = classifyFunc(n, routeOf(n, funcs, fileRoute));
			if (f != null)
			{
				f.files = funcs.get(n);
				findings.push(f);
			}
			else if (CompatData.FUNC_MASK.exists(n)) known++;
		}
		for (n in hooks.keys())
		{
			var f = classifyHook(n);
			if (f != null)
			{
				f.files = hooks.get(n);
				findings.push(f);
			}
			else if (CompatData.HOOK_MASK.exists(n)) known++;
		}

		findings.sort(sortFindings);
		report.findings = findings;
		report.knownNames = known;
		return report;
	}

	// ---------------------------------------------------------------- 版本分类

	public static function classifyFunc(name:String, ?leRoute:String = null):CompatFinding
	{
		var versions:Array<String> = CompatData.versionsOfFunction(name);
		if (versions.length == 0)
		{
			// 未注册：只在「像拼写错误」时报（与某已知 API 名字很接近）
			var near:String = closestName(name, CompatData.FUNC_MASK);
			if (near != null)
				return mk(name, false, SEV_WARN, [], '未在任何版本注册，疑似拼写错误；可能是 "' + near + '"');
			return null;
		}

		var hasKathy:Bool = versions.indexOf('kathy') >= 0;
		var has104:Bool = versions.indexOf('1.0.4') >= 0;
		var hasLegacy:Bool = versions.indexOf('0.7.3') >= 0 || versions.indexOf('0.6.3') >= 0;
		var hasLe:Bool = versions.indexOf('le') >= 0;

		// LE 独占：Kathy 经 LE API 运行时提供，Psych 1.0/0.7/0.6 均无。
		// 脚本走（或部分走）LE 运行时即可用；仅走 Psych 运行时则不可用。
		if (hasKathy && hasLe && !has104 && !hasLegacy)
		{
			if (leRoute == null || leRoute == 'le' || leRoute == 'mixed')
				return null;
			return mk(name, false, SEV_WARN, versions, '该函数仅 LE API 运行时提供；当前脚本按 Psych API 运行时加载，会报「函数不存在」。可把 leatherScriptCompat 设为 official/lts，或改用 Psych 对应 API');
		}

		// Psych 独占：LE API 运行时无此函数。脚本会走 LE 运行时（或混合）时报告。
		if (hasKathy && !hasLe && (has104 || hasLegacy) && (leRoute == 'le' || leRoute == 'mixed'))
			return mk(name, false, (leRoute == 'le' ? SEV_ERROR : SEV_WARN), versions,
				'该 Psych 函数在 LE API 运行时下不可用；当前脚本会走 LE 运行时。可把 leatherScriptCompat 设为 off，或改用 LE 对应 API');

		if (!has104 && hasLegacy)
			return mk(name, false, SEV_WARN, versions, 'Psych 1.0 未提供（仅旧版 PE / Kathy 兼容层有）；Kathy 上需把 luaCompatVersion 设为 0.7.3/0.6.3');
		if (hasKathy && !has104)
			return mk(name, false, SEV_ERROR, versions, 'Kathy 独占：Psych 1.0 / Legacy 下不存在，换引擎会直接报「函数不存在」');
		if (!hasKathy && has104)
			return mk(name, false, SEV_ERROR, versions, '当前 Kathy 引擎未提供该函数（可能已移除或改名）');
		return null;
	}

	public static function classifyHook(name:String):CompatFinding
	{
		var versions:Array<String> = CompatData.versionsOfHook(name);
		if (versions.length == 0)
		{
			if (!looksLikeHook(name)) return null;
			var near:String = closestName(name, CompatData.HOOK_MASK);
			if (near != null)
				return mk(name, true, SEV_WARN, [], '该回调钩子在任何版本都不存在，疑似拼写错误；可能是 "' + near + '"');
			return null;
		}

		var hasKathy:Bool = versions.indexOf('kathy') >= 0;
		var has104:Bool = versions.indexOf('1.0.4') >= 0;
		var hasLegacy:Bool = versions.indexOf('0.7.3') >= 0 || versions.indexOf('0.6.3') >= 0;
		var hasLe:Bool = versions.indexOf('le') >= 0;

		// LE 钩子：Kathy 的 LE 运行时实际广播该事件（update/popUpScore/playerOneSing…）→ 通过
		if (hasLe)
			return null;

		if (!has104 && hasLegacy)
			return mk(name, true, SEV_WARN, versions, 'Psych 1.0 不会调用该回调（仅旧版 PE 有）');
		if (hasKathy && !has104)
			return mk(name, true, SEV_ERROR, versions, 'Kathy 独有回调：Psych 1.0 / Legacy 下永远不会被触发');
		if (!hasKathy && has104)
			return mk(name, true, SEV_ERROR, versions, '当前 Kathy 引擎不会调用该回调');
		return null;
	}

	/** 汇总某名字出现过的脚本的路由：'le' / 'psych' / 'mixed' / null(无记录) */
	static function routeOf(name:String, map:Map<String, Array<String>>, fileRoute:Map<String, String>):String
	{
		var files:Array<String> = map.get(name);
		if (files == null || files.length == 0) return null;
		var hasLe:Bool = false;
		var hasPsych:Bool = false;
		for (f in files)
		{
			var r:String = fileRoute.get(f);
			if (r == 'le') hasLe = true;
			else if (r == 'psych') hasPsych = true;
		}
		if (hasLe && hasPsych) return 'mixed';
		if (hasLe) return 'le';
		if (hasPsych) return 'psych';
		return null;
	}

	// ---------------------------------------------------------------- 扫描实现

	static function scanLua(src:String):ScanResult
	{
		var clean:String = stripLua(src);

		var defined:Map<String, Bool> = new Map();
		collectDefinitions(clean, defined);

		var hooks:Array<String> = [];
		for (n in defined.keys())
			if (CompatData.HOOK_MASK.exists(n) || looksLikeHook(n)) hooks.push(n);

		var callNames:Map<String, Bool> = new Map();
		collectCalls(clean, callNames);

		var calls:Array<String> = [];
		for (n in callNames.keys())
		{
			if (defined.exists(n)) continue;
			if (isLuaKeyword(n) || isLuaStdlib(n)) continue;
			calls.push(n);
		}
		return {calls: calls, hooks: hooks};
	}

	/** HScript 仅浅层：提取调用点（不做类成员级校验），钩子定义照常识别 */
	static function scanHx(src:String):ScanResult
	{
		var clean:String = stripHx(src);

		var defined:Map<String, Bool> = new Map();
		collectDefinitions(clean, defined);

		var hooks:Array<String> = [];
		for (n in defined.keys())
			if (CompatData.HOOK_MASK.exists(n) || looksLikeHook(n)) hooks.push(n);

		var callNames:Map<String, Bool> = new Map();
		collectCalls(clean, callNames);

		var calls:Array<String> = [];
		for (n in callNames.keys())
		{
			if (defined.exists(n)) continue;
			if (isLuaKeyword(n) || isLuaStdlib(n)) continue;
			calls.push(n);
		}
		return {calls: calls, hooks: hooks};
	}

	/** 收集定义过的函数名（function X / local function X / X = function） */
	static function collectDefinitions(clean:String, out:Map<String, Bool>):Void
	{
		var len:Int = clean.length;

		// function NAME
		var i:Int = 0;
		while ((i = clean.indexOf('function', i)) >= 0)
		{
			i += 'function'.length;
			var j:Int = i;
			while (j < len && isSpace(clean.charAt(j))) j++;
			var name:String = readIdent(clean, j);
			if (name != '') out.set(name, true);
		}

		// NAME = function
		var k:Int = 0;
		while ((k = clean.indexOf('= function', k)) >= 0)
		{
			var e:Int = k - 1;
			while (e >= 0 && isSpace(clean.charAt(e))) e--;
			var s:Int = e;
			while (s >= 0 && isWordChar(clean.charAt(s))) s--;
			if (e >= 0)
			{
				var nm:String = clean.substring(s + 1, e + 1);
				if (nm != '' && isIdentStart(nm.charAt(0))) out.set(nm, true);
			}
			k += '= function'.length;
		}
	}

	/** 收集「全局函数调用点」：name( ，排除 obj.name( 与 obj:name( */
	static function collectCalls(clean:String, out:Map<String, Bool>):Void
	{
		var len:Int = clean.length;
		var i:Int = 0;
		while (i < len)
		{
			var c:String = clean.charAt(i);
			if (!isIdentStart(c))
			{
				i++;
				continue;
			}

			var j:Int = i + 1;
			while (j < len && isWordChar(clean.charAt(j))) j++;
			var name:String = clean.substring(i, j);

			var k:Int = j;
			while (k < len && isSpace(clean.charAt(k))) k++;

			var prev:String = i > 0 ? clean.charAt(i - 1) : '';
			if (k < len && clean.charAt(k) == '(' && prev != '.' && prev != ':' && !isWordChar(prev))
				out.set(name, true);

			i = j;
		}
	}

	// ---------------------------------------------------------------- 去注释/字符串

	static function stripLua(src:String):String
	{
		var out:StringBuf = new StringBuf();
		var len:Int = src.length;
		var i:Int = 0;
		while (i < len)
		{
			var c:String = src.charAt(i);

			// 长字符串 [[ ... ]] / [=[ ... ]=]
			if (c == '[' && i + 1 < len && src.charAt(i + 1) == '[')
			{
				i = skipLongBracket(src, i);
				continue;
			}

			// 注释
			if (c == '-' && i + 1 < len && src.charAt(i + 1) == '-')
			{
				i += 2;
				if (i < len && src.charAt(i) == '[' && i + 1 < len && src.charAt(i + 1) == '[')
				{
					i = skipLongBracket(src, i);
				}
				else
				{
					while (i < len && src.charAt(i) != '\n') i++;
				}
				continue;
			}

			// 短字符串
			if (c == '"' || c == '\'')
				i = skipQuoted(src, i, c);
			else
			{
				out.add(c);
				i++;
			}
		}
		return out.toString();
	}

	static function stripHx(src:String):String
	{
		var out:StringBuf = new StringBuf();
		var len:Int = src.length;
		var i:Int = 0;
		while (i < len)
		{
			var c:String = src.charAt(i);

			if (c == '/' && i + 1 < len && src.charAt(i + 1) == '/')
			{
				i += 2;
				while (i < len && src.charAt(i) != '\n') i++;
				continue;
			}
			if (c == '/' && i + 1 < len && src.charAt(i + 1) == '*')
			{
				i += 2;
				while (i + 1 < len && !(src.charAt(i) == '*' && src.charAt(i + 1) == '/')) i++;
				i += 2;
				continue;
			}
			if (c == '"' || c == '\'')
				i = skipQuoted(src, i, c);
			else
			{
				out.add(c);
				i++;
			}
		}
		return out.toString();
	}

	static function skipQuoted(src:String, start:Int, quote:String):Int
	{
		var len:Int = src.length;
		var i:Int = start + 1;
		while (i < len)
		{
			var ch:String = src.charAt(i);
			if (ch == '\\')
			{
				i += 2;
				continue;
			}
			if (ch == quote) return i + 1;
			// Lua 短字符串不允许裸换行，遇到换行就中止，避免吞掉整段代码
			if (ch == '\n') return i;
			i++;
		}
		return len;
	}

	static function skipLongBracket(src:String, start:Int):Int
	{
		var len:Int = src.length;
		var i:Int = start + 2;
		while (i + 1 < len)
		{
			if (src.charAt(i) == ']' && src.charAt(i + 1) == ']') return i + 2;
			i++;
		}
		return len;
	}

	// ---------------------------------------------------------------- 工具

	static function addName(map:Map<String, Array<String>>, name:String, rel:String):Void
	{
		if (!map.exists(name)) map.set(name, []);
		var arr:Array<String> = map.get(name);
		if (arr.indexOf(rel) < 0) arr.push(rel);
	}

	static function mk(name:String, isHook:Bool, severity:Int, versions:Array<String>, note:String):CompatFinding
	{
		return {name: name, isHook: isHook, severity: severity, versions: versions, files: [], note: note};
	}

	static function sortFindings(a:CompatFinding, b:CompatFinding):Int
	{
		if (a.severity != b.severity) return b.severity - a.severity;
		return Reflect.compare(a.name, b.name);
	}

	static inline function looksLikeHook(name:String):Bool
	{
		if (name.length < 3 || name.substr(0, 2) != 'on') return false;
		var c:String = name.charAt(2);
		return c >= 'A' && c <= 'Z';
	}

	public static inline function isLuaKeyword(n:String):Bool
		return LUA_KEYWORDS.indexOf(n) >= 0;

	public static inline function isLuaStdlib(n:String):Bool
		return LUA_STDLIB.indexOf(n) >= 0;

	static inline function isSpace(c:String):Bool
		return c == ' ' || c == '\t' || c == '\r' || c == '\n';

	static inline function isIdentStart(c:String):Bool
	{
		var code:Int = c.charCodeAt(0);
		return (code >= 97 && code <= 122) || (code >= 65 && code <= 90) || code == 95;
	}

	static inline function isWordChar(c:String):Bool
	{
		var code:Int = c.charCodeAt(0);
		return (code >= 97 && code <= 122) || (code >= 65 && code <= 90) || (code >= 48 && code <= 57) || code == 95;
	}

	static function readIdent(s:String, from:Int):String
	{
		var len:Int = s.length;
		if (from >= len || !isIdentStart(s.charAt(from))) return '';
		var j:Int = from + 1;
		while (j < len && isWordChar(s.charAt(j))) j++;
		return s.substring(from, j);
	}

	/** 在已知名字表里找与 name 最接近的（编辑距离 <= 2），用于提示拼写错误 */
	static function closestName(name:String, table:Map<String, String>):String
	{
		var best:String = null;
		var bestDist:Int = 3;
		for (k in table.keys())
		{
			if (k == name) continue;
			if (k.length != name.length && Math.abs(k.length - name.length) >= bestDist) continue;
			var d:Int = levenshtein(name, k);
			if (d < bestDist)
			{
				bestDist = d;
				best = k;
				if (d == 1) break;
			}
		}
		return best;
	}

	static function levenshtein(a:String, b:String):Int
	{
		var la:Int = a.length;
		var lb:Int = b.length;
		if (la == 0) return lb;
		if (lb == 0) return la;

		var prev:Array<Int> = [for (i in 0...lb + 1) i];
		var cur:Array<Int> = [for (i in 0...lb + 1) 0];

		for (i in 1...la + 1)
		{
			cur[0] = i;
			var ca:Int = a.charCodeAt(i - 1);
			for (j in 1...lb + 1)
			{
				var cost:Int = ca == b.charCodeAt(j - 1) ? 0 : 1;
				var del:Int = prev[j] + 1;
				var ins:Int = cur[j - 1] + 1;
				var sub:Int = prev[j - 1] + cost;
				var m:Int = del < ins ? del : ins;
				if (sub < m) m = sub;
				cur[j] = m;
			}
			var tmp:Array<Int> = prev;
			prev = cur;
			cur = tmp;
		}
		return prev[lb];
	}

	#if sys
	/** 递归收集模组里的 .lua / .hx 文件 */
	static function collectScriptFiles(dir:String, out:Array<String>, depth:Int):Void
	{
		if (depth > 12) return;

		var entries:Array<String>;
		try
		{
			entries = sys.FileSystem.readDirectory(dir);
		}
		catch (e:Dynamic)
		{
			return;
		}

		for (e in entries)
		{
			var full:String = dir + '/' + e;
			var isDir:Bool = false;
			try
			{
				isDir = sys.FileSystem.isDirectory(full);
			}
			catch (ex:Dynamic)
			{
				continue;
			}

			if (isDir)
			{
				if (SKIP_DIRS.indexOf(e.toLowerCase()) >= 0) continue;
				collectScriptFiles(full, out, depth + 1);
			}
			else
			{
				var low:String = e.toLowerCase();
				if (low.endsWith('.lua') || low.endsWith('.hx')) out.push(full);
			}
		}
	}
	#end
}
