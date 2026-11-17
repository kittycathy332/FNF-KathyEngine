package backend;

import openfl.utils.Assets;
import lime.utils.Assets as LimeAssets;
import flixel.addons.display.FlxGridOverlay;
import flixel.graphics.FlxGraphic;
import flixel.FlxG;
import flixel.util.FlxTimer;

#if cpp
@:cppFileCode('#include <thread>')
#end
class CoolUtil
{
	private static var cachedTips:String = null;
	private static var _tipsPending:Bool = false; // tips 请求进行中标志：预取与主界面请求重叠时复用同一请求，避免重复联网
	private static var _tipsQueue:Array<String->Void> = [];
	private static var _coolTextFileCache:Map<String, Array<String>> = null;
	private static var _gridCache:Map<String, FlxGraphic> = null;
	private static var _updateCheckDone:Bool = false;
	private static var _updateCheckPending:Bool = false;
	private static var _updateWatchdog:FlxTimer = null;
	private static var _updateRequestId:Int = 0; // 每次发起请求自增，用于丢弃看门狗超时后才迟到的过期响应

	// 更新检查结果（检查结束后有效）：标题界面后台发起，主界面进入时读取
	public static var updateLatestVersion:String = null;
	public static var updateIsOutdated:Bool = false;

	// 更新检查源：jsDelivr CDN 上的 gitVersion.txt（唯一版本源）
	//   release:1.x.x    <- 最新正式版（所有用户）
	//   dev:x.x.x-rc.1xx   <- 最新测试版（可选；"接收测试版构建"开启时优先读取）
	//   注意 jsDelivr 对 @main 分支有最长 12h 的 CDN 缓存，改完文件后可用 purge.jsdelivr.net 主动刷新
	static inline final UPDATE_SOURCE_URL:String = "https://cdn.jsdelivr.net/gh/kittycathy114/FNF-KathyEngine@main/gitVersion.txt";
	// 看门狗超时：连上但服务器一直不响应时按失败处理，及时结束本次检查
	static inline final UPDATE_TIMEOUT:Float = 4;

	/**
	 * 发起更新检查（每次启动仅一次，在标题界面后台调用）。
	 * 结果写入 updateLatestVersion / updateIsOutdated，由主界面在进入时读取并弹窗。
	 */
	public static function checkForUpdates():Void {
		if(!ClientPrefs.data.checkForUpdates) {
			_updateCheckDone = true;
			return;
		}
		if(_updateCheckDone || _updateCheckPending) return;
		// 全局联网禁用时直接短路，避免逐层触发 onError 回调
		if(Network.isNetworkingDisabled()) {
			trace('[UpdateCheck] networking disabled, skipping');
			_updateCheckDone = true;
			return;
		}
		_updateCheckPending = true;
		requestUpdateCheck();
	}

	/** 实际发起更新检查请求（不带会话去重门控） */
	static function requestUpdateCheck():Void {
		trace('checking for updates... ($UPDATE_SOURCE_URL)');

		final reqId:Int = ++_updateRequestId;

		// 4 秒看门狗：HTTPRequest 挂起（连上但不返回）永远不会触发 onError，
		// 必须主动超时结束；否则本次检查放弃
		if(_updateWatchdog != null) _updateWatchdog.cancel();
		_updateWatchdog = new FlxTimer().start(UPDATE_TIMEOUT, function(tmr:FlxTimer) {
			if(reqId != _updateRequestId) return; // 已被新请求取代
			_updateWatchdog = null;
			trace('update check timed out after ${Std.int(UPDATE_TIMEOUT)}s ($UPDATE_SOURCE_URL)');
			finishUpdateCheck(states.MainMenuState.kathyEngineVersion, false);
		});

		Network.httpGet(UPDATE_SOURCE_URL,
			function (data:String) {
				if(reqId != _updateRequestId) return; // 看门狗已超时放弃本请求，丢弃迟到响应
				stopUpdateWatchdog();
				var newVersion:String = parseUpdateResponse(data);
				if(newVersion == null) {
					// 响应不是合法版本号（如 CDN 缓存被污染），按失败处理
					trace('invalid response from update source');
					finishUpdateCheck(states.MainMenuState.kathyEngineVersion, false);
					return;
				}
				trace('version online: $newVersion, your version: ${states.MainMenuState.kathyEngineVersion}');
				finishUpdateCheck(newVersion, versionCompare(newVersion, states.MainMenuState.kathyEngineVersion) > 0);
			},
			function (error) {
				if(reqId != _updateRequestId) return;
				stopUpdateWatchdog();
				trace('failed to check ($UPDATE_SOURCE_URL): $error');
				finishUpdateCheck(states.MainMenuState.kathyEngineVersion, false);
			});
	}

	static function finishUpdateCheck(latestVersion:String, isOutdated:Bool):Void {
		_updateCheckDone = true;
		_updateCheckPending = false;
		updateLatestVersion = latestVersion;
		updateIsOutdated = isOutdated;
	}

	static function stopUpdateWatchdog():Void {
		if(_updateWatchdog != null) {
			_updateWatchdog.cancel();
			_updateWatchdog = null;
		}
	}

	/**
	 * 从 gitVersion.txt 内容中提取版本号，无法解析时返回 null。
	 * 文件格式（键名大小写不限；兼容旧式无键单行文件）：
	 *   release:1.1.0     <- 最新正式版（所有用户）
	 *   dev:1.1.1-rc.1    <- 最新测试版（可选；"接收测试版构建"开启时优先读取，缺失时退回 release）
	 */
	static function parseUpdateResponse(data:String):String {
		var stable:String = null, latest:String = null;
		for (line in data.split('\n')) {
			var key:String = null, ver:String = line;
			var colon:Int = line.indexOf(':');
			if(colon > 0) {
				key = line.substring(0, colon).trim().toLowerCase();
				ver = line.substring(colon + 1);
			}
			ver = parseVersionLine(ver);
			if(ver == null) continue;
			if(key == null || key == 'release' || key == 'stable') {
				if(stable == null) stable = ver;
			} else if(key == 'dev' || key == 'beta' || key == 'prerelease') {
				if(latest == null) latest = ver;
			}
		}
		if(stable == null) return null;
		if(!ClientPrefs.data.receiveBetaBuilds) {
			// 测试版开关关闭时，release 行必须是纯正式版或 Fix/Hotfix 修复版：
			// 普通预发布后缀（-rc.x/-beta 等）只应出现在 dev 行，避免误推给所有用户
			var pre:String = splitCorePre(stable).pre;
			if(pre != null && pre.length > 0 && !isFixSuffix(pre)) {
				trace('[UpdateCheck] release version "$stable" has a prerelease suffix, but receiveBetaBuilds is off; ignored');
				return null;
			}
			return stable;
		}
		if(latest == null) return stable;
		return latest;
	}

	/** 解析单行版本号：剥离 v/V 前缀后校验合法性 */
	static function parseVersionLine(line:String):String {
		line = line.trim();
		if(line.length > 1 && (line.charAt(0) == 'v' || line.charAt(0) == 'V'))
			line = line.substring(1);
		return isValidVersion(line) ? line : null;
	}

	/** 接受任意长度数字核心版本（1.2 / 1.2.3 / 1.2.3.4），可带预发布后缀（-beta、-rc.1 等）与 '+' 构建元数据 */
	static function isValidVersion(s:String):Bool {
		return s != null && ~/^\d+(\.\d+)*(-[0-9A-Za-z][0-9A-Za-z.-]*)?(\+[0-9A-Za-z.-]*)?$/.match(s);
	}

	/**
	 * 语义化版本比较（SemVer 2.0.0 宽松实现，含 Fix/Hotfix 扩展）。
	 *  - 核心段支持任意数量：1.2 / 1.2.3 / 1.2.3.4 均可，缺段按 0 补齐
	 *  - 预发布后缀：1.2.0-alpha < 1.2.0-beta.1 < 1.2.0-beta.10 < 1.2.0-rc < 1.2.0
	 *    （同核心版本下，无后缀比有后缀新；标识符数字比数值、字母比字典序、数字 < 字母）
	 *  - Fix/Hotfix 扩展：首个标识符以 fix/hotfix 开头的后缀（大小写不限，如 -fix.1、-HotFix-xxx）
	 *    视为"高于正式版"的紧急修复通道，但仍低于任何版本号更高的核心版本
	 *  - 忽略空格后缀（如 debug 构建的 " dev"）和 '+' 构建元数据
	 * @return >0 表示 a 比 b 新，<0 表示 a 比 b 旧，0 表示相等
	 */
	public static function versionCompare(a:String, b:String):Int
	{
		var va:String = a.split(' ')[0].trim();
		var vb:String = b.split(' ')[0].trim();
		var sa:{core:String, pre:String} = splitCorePre(va);
		var sb:{core:String, pre:String} = splitCorePre(vb);

		var pa:Array<String> = sa.core.split('.');
		var pb:Array<String> = sb.core.split('.');
		var len:Int = Std.int(Math.max(pa.length, pb.length));
		for (i in 0...len)
		{
			var na:Int = (i < pa.length) ? parseVersionSegment(pa[i]) : 0;
			var nb:Int = (i < pb.length) ? parseVersionSegment(pb[i]) : 0;
			if (na > nb) return 1;
			if (na < nb) return -1;
		}
		return comparePrerelease(sa.pre, sb.pre);
	}

	/** 拆出核心版本与预发布后缀；'+' 构建元数据不参与比较 */
	static function splitCorePre(v:String):{core:String, pre:String}
	{
		var plus:Int = v.indexOf('+');
		if(plus >= 0) v = v.substring(0, plus);
		var dash:Int = v.indexOf('-');
		if(dash < 0) return {core: v, pre: null};
		return {core: v.substring(0, dash), pre: v.substring(dash + 1)};
	}

	static function parseVersionSegment(s:String):Int
	{
		var n:Null<Int> = Std.parseInt(s);
		return (n == null) ? 0 : n; // 非法段按 0 处理，避免 null 参与比较
	}

	/**
	 * 预发布后缀比较。常规后缀：无后缀 > 有后缀；标识符数字比数值、字母比字典序、数字 < 字母。
	 * Fix/Hotfix 扩展：fix/hotfix 类后缀视为高于正式版与一切常规预发布（见 isFixSuffix）。
	 */
	static function comparePrerelease(a:String, b:String):Int
	{
		// Fix/Hotfix 通道：同核心版本下 正式版 < -fix.1 < -fix.2 < 下一版本号
		var aFix:Bool = isFixSuffix(a);
		var bFix:Bool = isFixSuffix(b);
		if(aFix != bFix)
			return aFix ? 1 : -1;

		if(a == null || a.length == 0) return (b == null || b.length == 0) ? 0 : 1;
		if(b == null || b.length == 0) return -1;
		var pa:Array<String> = a.split('.');
		var pb:Array<String> = b.split('.');
		var len:Int = Std.int(Math.max(pa.length, pb.length));
		for (i in 0...len)
		{
			if(i >= pa.length) return -1; // 前段全等时，标识符更少的一方更旧
			if(i >= pb.length) return 1;
			var sa:String = pa[i], sb:String = pb[i];
			var na:Null<Int> = Std.parseInt(sa);
			var nb:Null<Int> = Std.parseInt(sb);
			if(na != null && nb != null)
			{
				if(na > nb) return 1;
				if(na < nb) return -1;
			}
			else if(na != null) return -1; // 数字标识符 < 字母标识符
			else if(nb != null) return 1;
			else
			{
				// 字母标识符按小写化后的字典序比较，使 -Beta / -BETA / -beta 等大小写变体互相兼容
				var c:Int = Reflect.compare(sa.toLowerCase(), sb.toLowerCase());
				if(c != 0) return c;
			}
		}
		return 0;
	}

	/**
	 * 是否为 Fix/Hotfix 类后缀：首个标识符以 fix / hotfix 开头（大小写不限）。
	 * 如 -fix、-fix.1、-Fix-2、-hotfix-20260913。多个修复版建议用点号编号（-fix.1 / -fix.2）以获得正确的数值排序。
	 */
	static function isFixSuffix(pre:String):Bool
	{
		if(pre == null || pre.length == 0) return false;
		var first:String = pre.split('.')[0].toLowerCase();
		return first.indexOf('fix') == 0 || first.indexOf('hotfix') == 0;
	}

	public static function tipsShow(?onComplete:String->Void, url:String = null, forceReload:Bool = false):Void {
		if (!forceReload && cachedTips != null) {
			if (onComplete != null) onComplete(cachedTips);
			return;
		}

		if (url == null || url.length == 0)
			url = "https://raw.githubusercontent.com/kittycathy332/FNF-Kathy-Things/main/engine/menu/tips/" + ClientPrefs.data.language + ".txt";

		// 首个请求还在途中时，后续调用只排队等结果，不再重复发请求
		if (_tipsPending) {
			if (onComplete != null) _tipsQueue.push(onComplete);
			return;
		}
		_tipsPending = true;

		trace('searching for tips... ($url)');
		Network.httpGet(url,
			function (data:String)
			{
				_tipsPending = false;
				cachedTips = data.trim(); // 缓存结果
				flushTipsQueue(cachedTips);
				if (onComplete != null) onComplete(cachedTips);
			},
			function (error) {
				// 语言专属文件不存在时，回退到简体中文
				if (url.indexOf("zh_cn.txt") == -1) {
					trace('tip file for current language unavailable, fallback to zh_cn: $error');
					_tipsPending = false; // 递归重试会重新置位
					tipsShow(onComplete, "https://raw.githubusercontent.com/kittycathy332/FNF-Kathy-Things/main/engine/menu/tips/zh_cn.txt", forceReload);
				} else {
					_tipsPending = false;
					trace('error: $error');
					flushTipsQueue('');
					if (onComplete != null) onComplete('');
				}
			});
	}

	/** 把排队中的 tips 回调按序补发（含完全失败时的空结果） */
	static function flushTipsQueue(tips:String):Void {
		var queue:Array<String->Void> = _tipsQueue;
		_tipsQueue = [];
		for (cb in queue) cb(tips);
	}

	inline public static function quantize(f:Float, snap:Float){
		// changed so this actually works lol
		var m:Float = Math.fround(f * snap);
		//trace(snap);
		return (m / snap);
	}

	public static function coolLerp(base:Float, target:Float, ratio:Float):Float
		return base + cameraLerp(ratio) * (target - base);

	public static function cameraLerp(lerp:Float):Float
		return lerp * (FlxG.elapsed / (1 / 60));

	inline public static function capitalize(text:String)
		return text.charAt(0).toUpperCase() + text.substr(1).toLowerCase();

	inline public static function coolTextFile(path:String):Array<String>
	{
		if (_coolTextFileCache == null) _coolTextFileCache = [];
		if (_coolTextFileCache.exists(path)) return _coolTextFileCache.get(path);

		var daList:String = null;
		#if (sys && MODS_ALLOWED)
		if(FileSystem.exists(path)) daList = File.getContent(path);
		#else
		if(Assets.exists(path)) daList = Assets.getText(path);
		#end
		var result:Array<String> = daList != null ? listFromString(daList) : [];
		_coolTextFileCache.set(path, result);
		return result;
	}

	public static function invalidateCoolTextFileCache(?path:String):Void
	{
		if (_coolTextFileCache == null) return;
		if (path == null)
			_coolTextFileCache = [];
		else if (_coolTextFileCache.exists(path))
			_coolTextFileCache.remove(path);
	}

	public static function getCachedGrid(columns:Int, rows:Int, pWidth:Int, pHeight:Int, useRect:Bool, color1:Int, color2:Int):FlxGraphic
	{
		if (_gridCache == null) _gridCache = [];
		var key:String = '$columns,$rows,$pWidth,$pHeight,$useRect,$color1,$color2';
		if (_gridCache.exists(key))
		{
			var cached:FlxGraphic = _gridCache.get(key);
			if (cached.bitmap != null && cached.bitmap.width > 0)
				return cached;
			_gridCache.remove(key);
		}
		var bmp = FlxGridOverlay.createGrid(columns, rows, pWidth, pHeight, useRect, color1, color2);
		var graphic:FlxGraphic = FlxG.bitmap.add(bmp, true, 'cached_grid_$key');
		graphic.persist = true;
		graphic.destroyOnNoUse = false;
		_gridCache.set(key, graphic);
		return graphic;
	}

	inline public static function colorFromString(color:String):FlxColor
	{
		var hideChars = ~/[\t\n\r]/;
		var color:String = hideChars.split(color).join('').trim();
		if(color.startsWith('0x')) color = color.substring(color.length - 6);

		var colorNum:Null<FlxColor> = FlxColor.fromString(color);
		if(colorNum == null) colorNum = FlxColor.fromString('#$color');
		return colorNum != null ? colorNum : FlxColor.WHITE;
	}

	inline public static function listFromString(string:String):Array<String>
	{
		var daList:Array<String> = [];
		daList = string.trim().split('\n');

		for (i in 0...daList.length)
			daList[i] = daList[i].trim();

		return daList;
	}

	public static function floorDecimal(value:Float, decimals:Int):Float
	{
		if(decimals < 1)
			return Math.floor(value);

		return Math.floor(value * Math.pow(10, decimals)) / Math.pow(10, decimals);
	}

	#if linux
	public static function sortAlphabetically(list:Array<String>):Array<String> {
		if (list == null) return [];

		list.sort((a, b) -> {
			var upperA = a.toUpperCase();
			var upperB = b.toUpperCase();
			
			return upperA < upperB ? -1 : upperA > upperB ? 1 : 0;
		});
		return list;
	}
	#end

	inline public static function dominantColor(sprite:flixel.FlxSprite):Int
	{
		var countByColor:Map<Int, Int> = [];
		for(col in 0...sprite.frameWidth)
		{
			for(row in 0...sprite.frameHeight)
			{
				var colorOfThisPixel:FlxColor = sprite.pixels.getPixel32(col, row);
				if(colorOfThisPixel.alphaFloat > 0.05)
				{
					colorOfThisPixel = FlxColor.fromRGB(colorOfThisPixel.red, colorOfThisPixel.green, colorOfThisPixel.blue, 255);
					var count:Int = countByColor.exists(colorOfThisPixel) ? countByColor[colorOfThisPixel] : 0;
					countByColor[colorOfThisPixel] = count + 1;
				}
			}
		}

		var maxCount = 0;
		var maxKey:Int = 0; //after the loop this will store the max color
		countByColor[FlxColor.BLACK] = 0;
		for(key => count in countByColor)
		{
			if(count >= maxCount)
			{
				maxCount = count;
				maxKey = key;
			}
		}
		countByColor = [];
		return maxKey;
	}

	inline public static function numberArray(max:Int, ?min = 0):Array<Int>
	{
		var dumbArray:Array<Int> = [];
		for (i in min...max) dumbArray.push(i);

		return dumbArray;
	}

	inline public static function browserLoad(site:String) {
		Network.openURL(site);
	}

	inline public static function openFolder(folder:String, absolute:Bool = false) {
		#if sys
			if(!absolute) folder = Sys.getCwd() + '$folder';

			// 关键：去掉结尾的斜杠/反斜杠。Sys.getCwd() 在 Windows 上常以 '\' 结尾，
			// 若保留，Haxe 的 quoteWinArg 会把结尾 '\' 转义成 '\\'，导致 explorer 认为
			// 路径无效而打开空白「此电脑」窗口——这正是「打开的是纯 explorer」的根因。
			// 旧代码两处 bug：只判断 '/'（但上面已把 '/' 全换成 '\'）、substr 结果未赋值。
			while (folder.length > 1 && (folder.endsWith('/') || folder.endsWith('\\')))
				folder = folder.substr(0, folder.length - 1);

			#if windows
			// Windows：Sys.command 会用 quoteWinArg 自动给含空格路径加引号，
			// 因此这里传原始路径即可，绝不要手动加引号（会造成双重引号）。
			var command:String = 'explorer.exe';
			#elseif mac
			var command:String = '/usr/bin/open';
			#else
			var command:String = '/usr/bin/xdg-open';
			#end
			Sys.command(command, [folder]);
			trace('$command $folder');
		#else
			FlxG.error("Platform is not supported for CoolUtil.openFolder");
		#end
	}

	/**
		Helper Function to Fix Save Files for Flixel 5

		-- EDIT: [November 29, 2023] --

		this function is used to get the save path, period.
		since newer flixel versions are being enforced anyways.
		@crowplexus
	**/
	@:access(flixel.util.FlxSave.validate)
	inline public static function getSavePath():String {
		final company:String = FlxG.stage.application.meta.get('company');
		// #if (flixel < "5.0.0") return company; #else
		return '${company}/${flixel.util.FlxSave.validate(FlxG.stage.application.meta.get('file'))}';
		// #end
	}

	public static function setTextBorderFromString(text:FlxText, border:String)
	{
		switch(border.toLowerCase().trim())
		{
			case 'shadow':
				text.borderStyle = SHADOW;
			case 'outline':
				text.borderStyle = OUTLINE;
			case 'outline_fast', 'outlinefast':
				text.borderStyle = OUTLINE_FAST;
			default:
				text.borderStyle = NONE;
		}
	}

	public static function showPopUp(message:String, title:String, ?onOk:()->Void):Void
	{
		#if android
		AndroidTools.showAlertDialog(title, message, {name: "OK", func: onOk != null ? onOk : null}, null);
		#else
		FlxG.stage.window.alert(message, title);
		if (onOk != null) onOk();
		#end
	}

	#if mobile
	public static function showConfirmDialog(message:String, title:String, onConfirm:()->Void, ?onCancel:()->Void):Void
	{
		#if android
		AndroidTools.showAlertDialog(title, message,
			{name: Language.get("confirm_button"), func: onConfirm},
			{name: Language.get("cancel_button"), func: onCancel != null ? onCancel : function() {}}
		);
		#else
		FlxG.stage.window.alert(message, title);
		if (onCancel != null) onCancel();
		#end
	}
	#end

	#if cpp
    @:functionCode('
        return std::thread::hardware_concurrency();
    ')
	#end
    public static function getCPUThreadsCount():Int
    {
        return 1;
    }
}
