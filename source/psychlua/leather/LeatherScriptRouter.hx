#if LUA_ALLOWED
package psychlua.leather;

import backend.ClientPrefs;

/**
 * Leather Engine 脚本 API 兼容路由。
 *
 * 背景：
 *   LE（Leather Engine）的 mod 脚本是 lua 文件（mods/{mod}/scripts/*.lua），
 *   调用的是 LE 自己的一套 API（见 LE 源码 ModchartUtilities.hx / LuaScript.hx），
 *   与 Psych 的 FunkinLua API 函数名/全局变量名不同。
 *
 * 本路由负责：
 *   1. 读 ClientPrefs.leatherScriptCompat 设置（off/auto/official/lts）
 *   2. 结合当前谱面 format（LEATHER / LEATHER LTS），决定是否加载 LE 脚本层、
 *      以及用 Official 系还是 LTS 系 API。
 *
 * LE 原版参考：
 *   Official 0.5.0 : D:\VibeCode\LeatherEngine-Official\source\modding\ModchartUtilities.hx
 *   LTS  1.1.9    : D:\VibeCode\LeatherEngine-LTS\LeatherEngine-main\source\modding\scripts\languages\LuaScript.hx
 */
class LeatherScriptRouter
{
	public static final MODE_OFF:String = 'off';
	public static final MODE_AUTO:String = 'auto';
	public static final MODE_OFFICIAL:String = 'official';
	public static final MODE_LTS:String = 'lts';

	public static final MODES:Array<String> = [MODE_OFF, MODE_AUTO, MODE_OFFICIAL, MODE_LTS];

	/** 谱面 format：Official 系 */
	public static final FMT_LEATHER:String = 'LEATHER';
	/** 谱面 format：LTS 系 */
	public static final FMT_LEATHER_LTS:String = 'LEATHER LTS';

	/** 设置原始值（非法时回落 auto）。 */
	public static function rawMode():String
	{
		var v:String = ClientPrefs.data.leatherScriptCompat;
		if (v == null || MODES.indexOf(v) < 0)
			return MODE_AUTO;
		return v;
	}

	/** 脚本内容检测：LE 特有 API 签名（Psych 无同名，高区分度）。 */
	static final LE_SIGNATURES:Array<String> = [
		'makeSprite(', 'makeAnimatedSprite(', 'makeSpriteCopy(', 'setActor', 'getActor',
		'playCharAnim(', 'setStrumline', 'addActorAnimation', 'addActorTrail(',
		'createCustomShader(', 'setCamZoom(', 'getCamZoom(', 'setHudZoom(', 'getHudZoom(',
		'addPlayfield(', 'addStage(', 'changeBoyfriendCharacter(', 'changeDadCharacter(',
		'setNoteCameras(', 'setObjectCameras(', 'setHudPosition(', 'setHudAngle(',
		'makeText(', 'setActorText(', 'setActorFont(', 'anyNotes(', 'charFromEvent(',
		'getCharFromEvent(', 'getBaseScrollSpeed(', 'easeModifier(', 'actorScreenCenter(',
	];

	/** 脚本内容检测：Psych 特有 API 签名（LE 无同名，高区分度；避开两套同名函数）。 */
	static final PSYCH_SIGNATURES:Array<String> = [
		'makeLuaSprite(', 'makeAnimatedLuaSprite(', 'addLuaSprite(', 'setProperty(', 'getProperty(',
		'runHaxeCode(', 'doTweenX(', 'doTweenY(', 'doTweenAlpha(', 'doTweenAngle(', 'doTweenColor(',
		'doTweenZoom(', 'noteTweenX(', 'noteTweenY(', 'noteTweenAlpha(', 'noteTweenAngle(',
		'noteTweenDirection(', 'noteTweenColor(', 'noteTweenZoom(', 'addAnimationByPrefix(',
		'addAnimationByIndices(', 'addAnimation(', 'addHScript(', 'addLuaScript(', 'loadSong(',
		'cameraFlash(', 'cameraFade(', 'cameraShake(', 'cameraSetTarget(', 'characterDance(',
		'getVar(', 'setVar(', 'getLuaCompatVersion(', 'initAnalyzer(', 'mouseClicked(', 'mousePressed(',
		'mouseReleased(', 'addCameraFollowPoint(', 'addCharacterToList(', 'addScore(', 'getScore(',
		'addMisses(', 'getMisses(', 'addHits(', 'getHits(', 'getObjectOrder(', 'setObjectOrder(',
		'luaSpriteExists(', 'luaSoundExists(', 'luaTextExists(', 'getRunningScripts(', 'callScript(',
		'isRunning(', 'getAudioLevels(', 'getPixelColor(', 'loadGraphic(', 'loadFrames(',
		'loadMultipleFrames(', 'getMidpointX(', 'getMidpointY(', 'getGraphicMidpointX(',
		'getGraphicMidpointY(', 'getScreenPositionX(', 'getScreenPositionY(', 'getMouseX(', 'getMouseY(',
		'getCameraFollowX(', 'getCameraFollowY(', 'cancelTween(', 'cancelTimer(', 'startTween(',
		'getSoundPitch(', 'setSoundPitch(', 'getColorFromHex(', 'getColorFromName(', 'getColorFromString(',
		'exitSong(', 'isPlayerNote(', 'addOffset(', 'getCharacterX(', 'getCharacterY(', 'debugPrint(',
		'getLuaObject(', 'setVarFromClass(', 'getVarFromClass(',
	];

	/**
	 * 脚本级自动分流：按脚本文件内容检测它写的是哪套 API。
	 * @return 'leather' | 'psych'。均未命中时按谱面 format 回退（LE 谱面→leather，否则→psych）。
	 */
	public static function detectScriptRuntime(path:String, chartFormat:String):String
	{
		var content:String = null;
		#if sys
		try { content = sys.io.File.getContent(path); } catch (e:Dynamic) { content = null; }
		#end
		if (content == null || content.length == 0)
			return isLeatherChart(chartFormat) ? MODE_OFFICIAL : 'psych';

		for (sig in LE_SIGNATURES)
			if (content.indexOf(sig) != -1) return 'leather';
		for (sig in PSYCH_SIGNATURES)
			if (content.indexOf(sig) != -1) return 'psych';

		return isLeatherChart(chartFormat) ? 'leather' : 'psych';
	}

	/**
	 * 当前是否应启用 LE 脚本层。
	 * 不区分谱面来源：只要设置不是 off，任何模组（LE / Psych / 其他）的 scripts/*.lua
	 * 都走 LeatherLuaScript（LE API；auto=按谱面定版本，official/lts=强制指定版本）。
	 * @param chartFormat  当前谱面的 format 字段（Song.format，可能为 null/Psych 空串，仅 auto 定版本时参考）
	 */
	public static function isActive(chartFormat:String):Bool
	{
		var m:String = rawMode();
		if (m == MODE_OFF)
			return false;
		// auto / official / lts：全部启用（auto=按谱面定版本；official/lts=强制指定版本）
		return true;
	}

	/** 谱面 format 是否为 LE 系（Official 或 LTS）。 */
	public static function isLeatherChart(chartFormat:String):Bool
	{
		if (chartFormat == null)
			return false;
		return chartFormat == FMT_LEATHER || chartFormat == FMT_LEATHER_LTS;
	}

	/**
	 * 解析实际生效的 API 版本：official / lts。
	 * auto 模式按谱面 format 判定；强制模式按设置。
	 */
	public static function resolveVersion(chartFormat:String):String
	{
		var m:String = rawMode();
		if (m == MODE_OFFICIAL)
			return MODE_OFFICIAL;
		if (m == MODE_LTS)
			return MODE_LTS;
		// auto：按谱面
		if (chartFormat == FMT_LEATHER_LTS)
			return MODE_LTS;
		// 默认（含 FMT_LEATHER 与未知）走 Official 系（REC 0.4.x 属此系）
		return MODE_OFFICIAL;
	}
}
#end
