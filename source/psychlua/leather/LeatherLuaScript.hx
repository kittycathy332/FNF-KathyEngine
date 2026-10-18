#if LUA_ALLOWED
package psychlua.leather;

/**
 * Leather Engine 脚本运行时（Kathy 移植版）。
 *
 * 职责：
 *   - 持有独立的 llua State
 *   - 按 LE 原版语义注册全局变量（songLower / difficulty / bpm / keyCount / scrollspeed / curStep ...）
 *   - dofile 执行 LE mod 的 scripts/*.lua
 *   - 注册 LE API 函数集（分阶段补全，见 #25）
 *   - 提供 call()/set() 供 PlayState 事件广播（onCreate/onBeatHit/onUpdate 等）
 *
 * LE 原版对照：
 *   LTS 1.1.9: modding/scripts/languages/LuaScript.hx（~3800 行，121KB）
 *   Official 0.5.0: modding/ModchartUtilities.hx（~2000 行，73KB）
 *
 * 版本差异说明：
 *   - Official 系：API 以 ModchartUtilities 为主，全局变量集较小
 *   - LTS 系：在 Official 基础上扩展了大量函数（shader/trail/perlin/多角色组合等）
 *   本类先以 LTS 全局变量集为基础（LTS 是 Official 的超集），函数集按 resolveVersion 分支。
 */

import flixel.FlxG;
import haxe.Json;
import flixel.util.FlxStringUtil;

import llua.State;
import llua.Lua;
import llua.LuaL;
import llua.Convert;
import llua.Lua.Lua_helper;

import states.PlayState;
import backend.Conductor;
import backend.Song;
import backend.ClientPrefs;
import flixel.util.FlxColor;
import flixel.sound.FlxSound;
import flixel.FlxCamera;
import flixel.FlxG;
import flixel.FlxSprite;
import Reflect;
import openfl.display.BlendMode;

import flixel.tweens.FlxTween;
import flixel.tweens.FlxEase;
import flixel.math.FlxMath;
import flixel.text.FlxText;
import flixel.addons.effects.FlxTrail;
import objects.Note;
import objects.Character;
import objects.StrumNote;
import sys.FileSystem;
import flixel.FlxBasic;

class LeatherLuaScript
{
	/** llua 状态机 */
	public var lua:State = null;
	/** 脚本文件路径（dofile 用） */
	public var scriptPath:String;
	/** 脚本名（不含路径） */
	public var scriptName:String;
	/** 所属 mod 目录名（如 "REC"） */
	public var modFolder:String = null;
	/** 生效的 API 版本：'official' | 'lts' */
	public var apiVersion:String;
	/** 脚本是否已关闭（停止事件接收） */
	public var closed:Bool = false;

	// ===== LE 对象注册表（对照 LTS LuaScript.hx 静态 Map）=====
	// lua_Sprites / lua_Characters / lua_Sounds / lua_Cameras / lua_Tweens / lua_Jsons
	// 这些表在 getActorByName(id) 解析 lua 里的对象 id 时使用。
	// 当前阶段先建表结构，内容在 setup() 里按 PlayState 实际对象填充。
	public var luaSprites:Map<String, Dynamic> = new Map<String, Dynamic>();
	public var luaCharacters:Map<String, Dynamic> = new Map<String, Dynamic>();
	public var luaSounds:Map<String, FlxSound> = new Map<String, FlxSound>();
	public var luaTweens:Map<String, Dynamic> = new Map<String, Dynamic>();
	/** 脚本创建的残影（对照 LTS trails:Map<String, FlxTrail>） */
	public var trails:Map<String, Dynamic> = new Map<String, Dynamic>();
	/** tween 注册 key 计数器（flixel 5.x 的 FlxTween 无 id 字段，用自增序号作 key） */
	var tweenCount:Int = 0;

	/**
	 * @param path       lua 脚本绝对路径
	 * @param apiVersion 'official' | 'lts'
	 * @param modFolder  所属 mod 目录名
	 */
	public function new(path:String, apiVersion:String, modFolder:String = null)
	{
		this.scriptPath = path;
		this.apiVersion = apiVersion;
		this.modFolder = modFolder;
		// 取脚本文件名（不含扩展名），兼容 / 和 \ 分隔符
		var normalized:String = path.replace('\\', '/');
		var segs:Array<String> = normalized.split('/');
		var lastSeg:String = segs[segs.length - 1];
		this.scriptName = haxe.io.Path.withoutExtension(lastSeg);

		lua = LuaL.newstate();
		LuaL.openlibs(lua);

		setupGlobals();

		// 执行脚本本体（对照 LTS: LuaL.dofile(lua, path)）
		var result:Int = LuaL.dofile(lua, path);
		if (result != Lua.LUA_OK)
		{
			var err:Dynamic = Lua.tostring(lua, -1);
			trace('[LeatherLuaScript] Lua ERROR in ' + path + ': ' + Std.string(err));
		}
	}

	/**
	 * 注册 LE 全局变量（对照 LTS LuaScript.hx 构造函数 ~227-290 行）。
	 * 注意：变量名大小写严格按 LE 原版（scrollspeed 全小写、songLower、crochet 等）。
	 */
	function setupGlobals():Void
	{
		var ps:PlayState = PlayState.instance;
		if (ps == null) return;

		set('songLower', PlayState.SONG.song.toLowerCase());
		set('difficulty', PlayState.storyDifficulty);
		set('bpm', Conductor.bpm);
		set('songBpm', PlayState.SONG.bpm);
		set('keyCount', PlayState.SONG.keyCount);
		// LE 的玩家侧键数概念：Kathy 双侧谱面有 playerKeyCount（!= keyCount 时两侧独立），缺失时回落 keyCount
		set('playerKeyCount', (PlayState.SONG.playerKeyCount != null) ? PlayState.SONG.playerKeyCount : PlayState.SONG.keyCount);
		set('scrollspeed', PlayState.SONG.speed);   // LE 原版全小写
		set('scrollSpeed', PlayState.SONG.speed);    // 兼容写法
		set('stepCrochet', Conductor.stepCrochet);
		set('crochetUnscaled', Conductor.stepCrochet);
		set('crochet', Conductor.crochet);
		set('curStep', 0);
		set('curBeat', 0);

		set('player1', ps.boyfriend != null ? ps.boyfriend.curCharacter : PlayState.SONG.player1);
		set('player2', ps.dad != null ? ps.dad.curCharacter : PlayState.SONG.player2);

		set('windowWidth', FlxG.width);
		set('windowHeight', FlxG.height);
		set('mustHit', false);
		set('inReplay', false);
		// 对照 LTS:238-239：downscroll 是 0/1 数字（LE 脚本常写 downscroll == 0），另有 downscrollBool。
		set('downscroll', ClientPrefs.data.downScroll == true ? 1 : 0);
		set('downscrollBool', ClientPrefs.data.downScroll);

		// ===== LTS setup() 预注册的全局引用（对照 LTS LuaScript.hx:3618-3688）=====
		// 角色引用（Kathy PlayState 字段：boyfriend/gf/dad）
		luaSprites.set('boyfriend', ps.boyfriend);
		luaSprites.set('girlfriend', ps.gf);
		luaSprites.set('dad', ps.dad);
		luaCharacters.set('boyfriend', ps.boyfriend);
		luaCharacters.set('girlfriend', ps.gf);
		luaCharacters.set('dad', ps.dad);
		// 音频：Inst / Voices0..n（Kathy vocals 为单个 FlxSound，仍按 LTS 命名注册）
		luaSounds.set('Inst', FlxG.sound.music);
		if (ps.vocals != null)
		{
			luaSounds.set('Voices', ps.vocals);
			luaSounds.set('Voices0', ps.vocals);
		}
		// 判定线 strum：defaultStrum0..n / playerStrum / opponentStrum（Kathy 无 enemyStrums，用 opponentStrums 语义）
		if (ps.strumLineNotes != null)
		{
			for (i in 0...ps.strumLineNotes.length)
			{
				var s:StrumNote = ps.strumLineNotes.members[i];
				luaSprites.set('defaultStrum' + i, s);
			}
		}
		if (ps.playerStrums != null)
			for (i in 0...ps.playerStrums.length) luaSprites.set('playerStrum' + i, ps.playerStrums.members[i]);
		if (ps.opponentStrums != null)
			for (i in 0...ps.opponentStrums.length) luaSprites.set('opponentStrum' + i, ps.opponentStrums.members[i]);
		// 血条图标
		luaSprites.set('iconP1', ps.iconP1);
		luaSprites.set('iconP2', ps.iconP2);

		// ===== API 函数注册入口（#25 分阶段补全）=====
		registerCoreApi();
	}

	// ============================================================
	// 工具函数（对照 LTS LuaScript.hx getActorByName / cameraFromString）
	// ============================================================

	/**
	 * 按 id 解析脚本中的对象引用。
	 * 对照 LTS LuaScript.hx:77-117 getActorByName(id)。
	 * 顺序：luaSprites → luaSounds → luaTweens → PlayState 实例属性 → PlayState 静态属性 → 点号递归
	 */
	function getActorByName(id:String):Dynamic
	{
		if (luaSprites.exists(id)) return luaSprites.get(id);
		if (luaSounds.exists(id)) return luaSounds.get(id);
		if (luaTweens.exists(id)) return luaTweens.get(id);

		var ps:PlayState = PlayState.instance;
		if (ps == null) return null;

		// 实例属性
		var v:Dynamic = Reflect.getProperty(ps, id);
		if (v != null) return v;
		// 静态属性
		v = Reflect.getProperty(PlayState, id);
		if (v != null) return v;

		// 点号分割递归（如 "dad.x"、"boyfriend.health"）
		var segs:Array<String> = id.split('.');
		if (segs.length > 1)
		{
			var cur:Dynamic = getActorByName(segs[0]);
			for (i in 1...segs.length)
			{
				if (cur == null) break;
				cur = Reflect.getProperty(cur, segs[i]);
			}
			return cur;
		}
		return null;
	}

	/**
	 * 把相机名字符串解析为 FlxCamera。
	 * 对照 LTS: cameraFromString(camera)。
	 * 支持：'game'/'camgame'/''（默认game）、'hud'/'camhud'、'other'/'camother'。
	 */
	function cameraFromString(camStr:String):FlxCamera
	{
		var ps:PlayState = PlayState.instance;
		if (ps == null) return null;
		if (camStr == null || camStr == '') return ps.camGame;
		return switch (camStr.toLowerCase())
		{
			case 'hud', 'camhud': ps.camHUD;
			case 'other', 'camother': ps.camOther;
			default: ps.camGame; // 'game'/'camgame'/未知 回落 game
		};
	}

	// ============================================================
	// 第一批核心 API（对照 LTS LuaScript.hx setFunction 注册）
	// ============================================================
	function registerCoreApi():Void
	{
		// --- 调试输出 ---
		setFunction('trace', function(str:Dynamic) { trace('[LE lua:' + scriptName + '] ' + Std.string(str)); });
		setFunction('print', function(str:Dynamic) { trace('[LE lua:' + scriptName + '] ' + Std.string(str)); });

		// --- 屏幕闪烁/淡入淡出 ---
		setFunction('flashCamera', function(camStr:String = '', color:String = '#FFFFFF', time:Float = 1, ?force:Bool) {
			var cam:FlxCamera = cameraFromString(camStr);
			if (cam != null) cam.flash(FlxColor.fromString(color), time);
		});
		setFunction('fadeCamera', function(camStr:String = '', color:String = '#FFFFFF', time:Float = 1, fadeIn:Bool = false, ?force:Bool) {
			var cam:FlxCamera = cameraFromString(camStr);
			if (cam != null) cam.fade(FlxColor.fromString(color), time, fadeIn);
		});
		setFunction('stopFlash', function(?camStr:String, ?color:String, ?time:Float, ?force:Bool) {
			// FlxCamera 无直接 stopFlash，留空占位
		});

		// --- 相机控制 ---
		setFunction('setCamZoom', function(zoom:Float) {
			var ps:PlayState = PlayState.instance;
			if (ps != null && ps.camGame != null) ps.camGame.zoom = zoom;
		});
		setFunction('setHudZoom', function(zoom:Float) {
			var ps:PlayState = PlayState.instance;
			if (ps != null && ps.camHUD != null) ps.camHUD.zoom = zoom;
		});
		setFunction('getCamZoom', function():Float {
			var ps:PlayState = PlayState.instance;
			return (ps != null && ps.camGame != null) ? ps.camGame.zoom : 1;
		});
		setFunction('setCamPosition', function(x:Int, y:Int) {
			var ps:PlayState = PlayState.instance;
			if (ps != null && ps.camGame != null) { ps.camGame.x = x; ps.camGame.y = y; }
		});

		// --- 相机归属 ---
		setFunction('setObjectCamera', function(id:String, camStr:String = '') {
			var actor:Dynamic = getActorByName(id);
			var cam:FlxCamera = cameraFromString(camStr);
			if (actor != null && cam != null) actor.cameras = [cam];
		});
		setFunction('setCamera', function(id:String, camStr:String = '') {
			var actor:Dynamic = getActorByName(id);
			var cam:FlxCamera = cameraFromString(camStr);
			if (actor != null && cam != null) actor.cameras = [cam];
		});

		// --- 键盘输入 ---
		setFunction('justPressed', function(key:String = 'SPACE'):Bool {
			return Reflect.getProperty(FlxG.keys.justPressed, key) == true;
		});
		setFunction('pressed', function(key:String = 'SPACE'):Bool {
			return Reflect.getProperty(FlxG.keys.pressed, key) == true;
		});
		setFunction('justReleased', function(key:String = 'SPACE'):Bool {
			return Reflect.getProperty(FlxG.keys.justReleased, key) == true;
		});

		// --- 精灵属性 ---
		setFunction('setGraphicSize', function(id:String, w:Float = 0, h:Float = 0) {
			var actor:Dynamic = getActorByName(id);
			if (actor != null) actor.setGraphicSize(w, h);
		});
		setFunction('updateHitbox', function(id:String) {
			var actor:Dynamic = getActorByName(id);
			if (actor != null) actor.updateHitbox();
		});
		setFunction('setBlendMode', function(id:String, blend:String = '') {
			var actor:Dynamic = getActorByName(id);
			if (actor == null || blend == '') return;
			actor.blend = switch (blend.toLowerCase())
			{
				case 'add': BlendMode.ADD;
				case 'multiply': BlendMode.MULTIPLY;
				case 'screen': BlendMode.SCREEN;
				case 'alpha': BlendMode.ALPHA;
				default: BlendMode.NORMAL;
			};
		});

		// --- 颜色工具 ---
		setFunction('color', function(r:Int, g:Int, b:Int, a:Int = 255):Int {
			return FlxColor.fromRGB(r, g, b, a);
		});
		setFunction('colorString', function(c:String):Int {
			return FlxColor.fromString(c);
		});
		setFunction('colorRGB', function(r:Int, g:Int, b:Int):Int {
			return FlxColor.fromRGB(r, g, b);
		});
		setFunction('colorRGBA', function(r:Int, g:Int, b:Int, a:Int):Int {
			return FlxColor.fromRGB(r, g, b, a);
		});

		// --- 纯色块精灵 ---
		setFunction('makeGraphic', function(id:String, w:Int, h:Int, color:String) {
			var actor:Dynamic = getActorByName(id);
			if (actor != null) actor.makeGraphic(w, h, FlxColor.fromString(color));
		});
		setFunction('makeGraphicRGB', function(id:String, w:Int, h:Int, color:String) {
			var actor:Dynamic = getActorByName(id);
			if (actor == null) return;
			var parts:Array<String> = color.split(',');
			if (parts.length >= 3)
				actor.makeGraphic(w, h, FlxColor.fromRGB(Std.parseInt(parts[0]), Std.parseInt(parts[1]), Std.parseInt(parts[2])));
		});

		// --- 居中 ---
		setFunction('screenCenter', function(id:String, dir:String = 'xy') {
			var actor:Dynamic = getActorByName(id);
			if (actor == null) return;
			if (dir == 'x' || dir == 'xy') actor.x = (FlxG.width - actor.width) / 2;
			if (dir == 'y' || dir == 'xy') actor.y = (FlxG.height - actor.height) / 2;
		});
		setFunction('center', function(id:String, dir:String = 'xy') {
			var actor:Dynamic = getActorByName(id);
			if (actor == null) return;
			if (dir == 'x' || dir == 'xy') actor.x = (FlxG.width - actor.width) / 2;
			if (dir == 'y' || dir == 'xy') actor.y = (FlxG.height - actor.height) / 2;
		});

		// --- 血量 ---
		setFunction('setHealth', function(heal:Float) {
			var ps:PlayState = PlayState.instance;
			if (ps != null) ps.health = heal;
		});
		setFunction('getHealth', function():Float {
			var ps:PlayState = PlayState.instance;
			return (ps != null) ? ps.health : 1;
		});

		// --- 场景管理 ---
		setFunction('add', function(id:String) {
			var actor:Dynamic = getActorByName(id);
			var ps:PlayState = PlayState.instance;
			if (actor != null && ps != null) ps.add(actor);
		});
		setFunction('remove', function(id:String, ?splice:Bool) {
			var actor:Dynamic = getActorByName(id);
			var ps:PlayState = PlayState.instance;
			if (actor != null && ps != null) ps.remove(actor);
		});
		setFunction('kill', function(id:String) {
			var actor:Dynamic = getActorByName(id);
			if (actor != null) actor.kill();
		});
		setFunction('destroy', function(id:String) {
			var actor:Dynamic = getActorByName(id);
			if (actor != null) actor.destroy();
		});

		// --- 精灵变换（LE 签名：(value, id)，id 在最后）---
		// 对照 LTS LuaScript.hx:1525-1870
		setFunction('setActorX', function(x:Float, id:String) {
			var actor:Dynamic = getActorByName(id);
			if (actor != null) actor.x = x;
		});
		setFunction('setActorY', function(y:Float, id:String) {
			var actor:Dynamic = getActorByName(id);
			if (actor != null) actor.y = y;
		});
		setFunction('setActorPos', function(x:Float, y:Float, id:String) {
			var actor:Dynamic = getActorByName(id);
			if (actor != null) { actor.x = x; actor.y = y; }
		});
		setFunction('setActorAngle', function(angle:Float, id:String) {
			var actor:Dynamic = getActorByName(id);
			if (actor != null) actor.angle = angle;
		});
		setFunction('setActorScale', function(scale:Float, id:String) {
			var actor:Dynamic = getActorByName(id);
			if (actor != null) actor.scale.set(scale, scale);
		});
		setFunction('setActorScaleXY', function(sx:Float, sy:Float, id:String) {
			var actor:Dynamic = getActorByName(id);
			if (actor != null) actor.scale.set(sx, sy);
		});
		setFunction('setActorAlpha', function(alpha:Float, id:String) {
			var actor:Dynamic = getActorByName(id);
			if (actor != null) actor.alpha = alpha;
		});
		setFunction('setActorVisible', function(visible:Bool, id:String) {
			var actor:Dynamic = getActorByName(id);
			if (actor != null) actor.visible = visible;
		});
		setFunction('setActorScroll', function(sx:Float, sy:Float, id:String) {
			var actor:Dynamic = getActorByName(id);
			if (actor != null) actor.scrollFactor.set(sx, sy);
		});
		setFunction('setActorOriginX', function(x:Float, id:String) {
			var actor:Dynamic = getActorByName(id);
			if (actor != null) actor.origin.x = x;
		});
		setFunction('setActorOriginY', function(y:Float, id:String) {
			var actor:Dynamic = getActorByName(id);
			if (actor != null) actor.origin.y = y;
		});
		setFunction('setActorVelocityX', function(v:Float, id:String) {
			var actor:Dynamic = getActorByName(id);
			if (actor != null) actor.velocity.x = v;
		});
		setFunction('setActorVelocityY', function(v:Float, id:String) {
			var actor:Dynamic = getActorByName(id);
			if (actor != null) actor.velocity.y = v;
		});
		setFunction('setActorAccelerationX', function(v:Float, id:String) {
			var actor:Dynamic = getActorByName(id);
			if (actor != null) actor.acceleration.x = v;
		});
		setFunction('setActorAccelerationY', function(v:Float, id:String) {
			var actor:Dynamic = getActorByName(id);
			if (actor != null) actor.acceleration.y = v;
		});
		setFunction('setActorColor', function(id:String, r:Int, g:Int, b:Int, a:Int = 255) {
			var actor:Dynamic = getActorByName(id);
			if (actor != null) actor.color = FlxColor.fromRGB(r, g, b, a);
		});
		setFunction('setActorColorRGB', function(id:String, color:String) {
			var actor:Dynamic = getActorByName(id);
			if (actor != null) actor.color = FlxColor.fromString(color);
		});

		// --- 创建精灵（对照 LTS:842-916）---
		// makeSprite：从单张图片创建静态精灵
		setFunction('makeSprite', function(id:String, filename:String, x:Float, y:Float, size:Float = 1, ?sizeY:Float) {
			if (luaSprites.exists(id)) return;
			var spr:FlxSprite = new FlxSprite(x, y);
			if (filename != null && filename.length > 0)
				spr.loadGraphic(backend.Paths.image(filename));
			spr.scale.set(size, sizeY == null ? size : sizeY);
			spr.updateHitbox();
			luaSprites.set(id, spr);
			var ps:PlayState = PlayState.instance;
			if (ps != null) ps.add(spr);
		});

		// makeAnimatedSprite：从 sparrow atlas 创建动画精灵
		setFunction('makeAnimatedSprite', function(id:String, filename:String, x:Float, y:Float, size:Float = 1, ?sizeY:Float) {
			if (luaSprites.exists(id)) return;
			var spr:FlxSprite = new FlxSprite(x, y);
			if (filename != null && filename.length > 0)
				spr.frames = backend.Paths.getSparrowAtlas(filename);
			spr.scale.set(size, sizeY == null ? size : sizeY);
			spr.updateHitbox();
			luaSprites.set(id, spr);
			var ps:PlayState = PlayState.instance;
			if (ps != null) ps.add(spr);
		});

		// makeSpriteCopy：复制已有精灵
		setFunction('makeSpriteCopy', function(id:String, targetID:String) {
			if (luaSprites.exists(id)) return;
			var actor:Dynamic = getActorByName(targetID);
			if (actor == null) return;
			var spr:FlxSprite = new FlxSprite(actor.x, actor.y);
			spr.loadGraphicFromSprite(actor);
			spr.alpha = actor.alpha;
			spr.angle = actor.angle;
			spr.scale.x = actor.scale.x;
			spr.scale.y = actor.scale.y;
			spr.flipX = actor.flipX;
			spr.flipY = actor.flipY;
			spr.color = actor.color;
			luaSprites.set(id, spr);
			var ps:PlayState = PlayState.instance;
			if (ps != null) ps.add(spr);
		});

		// --- 动画播放（对照 LTS:1625-1660）---
		setFunction('playCharAnim', function(id:String, anim:String, force:Bool = false, reverse:Bool = false, frame:Int = 0) {
			var actor:Dynamic = getActorByName(id);
			if (actor != null && actor.animation != null)
				actor.animation.play(anim, force, reverse, frame);
		});
		setFunction('addActorAnimation', function(id:String, prefix:String, anim:String, fps:Int = 30, looped:Bool = true) {
			var actor:Dynamic = getActorByName(id);
			if (actor != null && actor.animation != null)
				actor.animation.addByPrefix(prefix, anim, fps, looped);
		});

		// playActorAnimation（对照 LTS:1665）：播放 lua 精灵/角色动画，force/reverse/frame 透传
		setFunction('playActorAnimation', function(id:String, anim:String, force:Bool = false, reverse:Bool = false, frame:Int = 0) {
			var actor:Dynamic = getActorByName(id);
			if (actor != null && actor.animation != null)
				actor.animation.play(anim, force, reverse, frame);
		});

		// --- 声音（对照 LTS:2202-2245）---
		// createSound(id, file_Path, ?library='shared', ?looped=false)：预加载到 luaSounds
		// 注：Psych 的 Paths.sound 第二参是 modsAllowed(Bool) 而非 library；library 参数仅作 LE 兼容占位。
		setFunction('createSound', function(id:String, file_Path:String, ?library:String = 'shared', ?looped:Bool = false) {
			if (luaSounds.exists(id)) return;
			var snd:FlxSound = FlxG.sound.load(backend.Paths.sound(file_Path), 1, looped);
			luaSounds.set(id, snd);
		});

		// playSound(id, ?forceRestart=false)：播放已创建的声音
		setFunction('playSound', function(id:String, ?forceRestart:Bool = false) {
			var snd:FlxSound = luaSounds.get(id);
			if (snd != null) snd.play(forceRestart);
		});

		// stopSound(id)：停止播放
		setFunction('stopSound', function(id:String) {
			var snd:FlxSound = luaSounds.get(id);
			if (snd != null) snd.stop();
		});

		// ============================================================
		// 批次 2-A：相机 / 屏幕 getter、文本、场景、actor 补充、角色
		// ============================================================

		// --- 相机 getter / HUD 控制（对照 LTS:1052-1075, 1107-1150）---
		setFunction('getCameraX', function():Float {
			var cam:FlxCamera = cameraFromString('game');
			return (cam != null) ? cam.x : 0;
		});
		setFunction('getCameraY', function():Float {
			var cam:FlxCamera = cameraFromString('game');
			return (cam != null) ? cam.y : 0;
		});
		setFunction('getCameraScrollX', function(camStr:String):Float {
			var cam:FlxCamera = cameraFromString(camStr);
			return (cam != null) ? cam.scroll.x : 0;
		});
		setFunction('getCameraScrollY', function(camStr:String):Float {
			var cam:FlxCamera = cameraFromString(camStr);
			return (cam != null) ? cam.scroll.y : 0;
		});
		setFunction('getHudX', function():Float {
			var ps:PlayState = PlayState.instance;
			return (ps != null && ps.camHUD != null) ? ps.camHUD.x : 0;
		});
		setFunction('getHudY', function():Float {
			var ps:PlayState = PlayState.instance;
			return (ps != null && ps.camHUD != null) ? ps.camHUD.y : 0;
		});
		setFunction('getHudZoom', function():Float {
			var ps:PlayState = PlayState.instance;
			return (ps != null && ps.camHUD != null) ? ps.camHUD.zoom : 1;
		});
		setFunction('setHudAngle', function(angle:Float) {
			var ps:PlayState = PlayState.instance;
			if (ps != null && ps.camHUD != null) ps.camHUD.angle = angle;
		});
		setFunction('setHudPosition', function(x:Int, y:Int) {
			var ps:PlayState = PlayState.instance;
			if (ps != null && ps.camHUD != null) { ps.camHUD.x = x; ps.camHUD.y = y; }
		});
		// setNoteCameras：把谱面音符（含 strums）整体挂到某相机
		setFunction('setNoteCameras', function(camStr:String) {
			var ps:PlayState = PlayState.instance;
			var cam:FlxCamera = cameraFromString(camStr);
			if (ps == null || cam == null) return;
			if (ps.notes != null) ps.notes.cameras = [cam];
			if (ps.strumLineNotes != null) ps.strumLineNotes.cameras = [cam];
		});
		// setObjectCameras：把某个 lua 对象挂到某相机（同 setObjectCamera 的批量别名）
		setFunction('setObjectCameras', function(id:String, camStr:String) {
			var actor:Dynamic = getActorByName(id);
			var cam:FlxCamera = cameraFromString(camStr);
			if (actor != null && cam != null) actor.cameras = [cam];
		});
		// setStrumlineX/Y：移动判定线（对照 LTS:1156-1176；Psych 无独立 strumLine 对象，直接整体移动成员）
		setFunction('setStrumlineX', function(x:Float, ?dontMove:Bool = false) {
			var ps:PlayState = PlayState.instance;
			if (ps == null || ps.strumLineNotes == null) return;
			if (!dontMove)
				for (s in ps.strumLineNotes) s.x = x;
		});
		setFunction('setStrumlineY', function(y:Float, ?dontMove:Bool = false) {
			var ps:PlayState = PlayState.instance;
			if (ps == null || ps.strumLineNotes == null) return;
			if (!dontMove)
				for (s in ps.strumLineNotes) s.y = y;
		});

		// --- 文本对象（对照 LTS:691-750, 731-753）---
		function makeTextInternal(id:String, text:String, x:Float, y:Float, size:Int = 32, font:String = 'vcr.ttf', fieldWidth:Float = 0, autoAdd:Bool = true):Void
		{
			if (luaSprites.exists(id)) return;
			var txt:FlxText = new FlxText(x, y, fieldWidth, text, size);
			if (font != null && font.length > 0) txt.font = backend.Paths.font(font);
			luaSprites.set(id, txt);
			if (autoAdd)
			{
				var ps:PlayState = PlayState.instance;
				if (ps != null) ps.add(txt);
			}
		}
		setFunction('makeText', function(id:String, text:String, x:Float, y:Float, size:Int = 32, font:String = 'vcr.ttf', fieldWidth:Float = 0) {
			makeTextInternal(id, text, x, y, size, font, fieldWidth, true);
		});
		setFunction('newText', function(id:String, text:String, x:Float, y:Float, size:Int = 32, font:String = 'vcr.ttf', fieldWidth:Float = 0) {
			makeTextInternal(id, text, x, y, size, font, fieldWidth, false);
		});
		setFunction('setActorText', function(id:String, text:String) {
			var actor:Dynamic = getActorByName(id);
			if (actor != null && Std.isOfType(actor, FlxText)) actor.text = text;
		});
		setFunction('setActorFont', function(id:String, font:String) {
			var actor:Dynamic = getActorByName(id);
			if (actor != null && Std.isOfType(actor, FlxText)) actor.font = backend.Paths.font(font);
		});
		setFunction('setActorAlignment', function(id:String, align:String) {
			var actor:Dynamic = getActorByName(id);
			if (actor != null && Std.isOfType(actor, FlxText))
				actor.alignment = switch (align.toLowerCase())
				{
					case 'left': flixel.text.FlxTextAlign.LEFT;
					case 'center': flixel.text.FlxTextAlign.CENTER;
					case 'right': flixel.text.FlxTextAlign.RIGHT;
					default: flixel.text.FlxTextAlign.LEFT;
				};
		});
		setFunction('setActorTextColor', function(id:String, color:String) {
			var actor:Dynamic = getActorByName(id);
			if (actor != null) actor.color = FlxColor.fromString(color);
		});
		setFunction('setActorOutlineColor', function(id:String, color:String) {
			var actor:Dynamic = getActorByName(id);
			if (actor != null && Std.isOfType(actor, FlxText)) actor.borderColor = FlxColor.fromString(color);
		});
		setFunction('setTextBorderStyle', function(id:String, text:String) {
			var actor:Dynamic = getActorByName(id);
			if (actor != null && Std.isOfType(actor, FlxText))
				actor.borderStyle = switch (text.toLowerCase())
				{
					case 'shadow': flixel.text.FlxTextBorderStyle.SHADOW;
					case 'outline': flixel.text.FlxTextBorderStyle.OUTLINE;
					case 'outline_fast': flixel.text.FlxTextBorderStyle.OUTLINE_FAST;
					case 'none': flixel.text.FlxTextBorderStyle.NONE;
					default: flixel.text.FlxTextBorderStyle.NONE;
				};
		});

		// --- 场景管理补充（对照 LTS:673-689）---
		setFunction('insert', function(id:String, position:Int) {
			var actor:Dynamic = getActorByName(id);
			var ps:PlayState = PlayState.instance;
			if (actor != null && ps != null) ps.insert(position, actor);
		});
		setFunction('addStage', function(id:String) {
			var actor:Dynamic = getActorByName(id);
			var ps:PlayState = PlayState.instance;
			if (actor != null && ps != null) ps.add(actor);
		});
		setFunction('removeStage', function(id:String, ?splice:Bool) {
			var actor:Dynamic = getActorByName(id);
			var ps:PlayState = PlayState.instance;
			if (actor != null && ps != null) ps.remove(actor);
		});
		setFunction('insertStage', function(id:String, position:Int) {
			var actor:Dynamic = getActorByName(id);
			var ps:PlayState = PlayState.instance;
			if (actor != null && ps != null) ps.insert(position, actor);
		});

		// --- actor 属性补充（对照 LTS:1577-2040）---
		setFunction('setActorModAngle', function(angle:Float, id:String) {
			var actor:Dynamic = getActorByName(id);
			if (actor != null) actor.angle = actor.angle + angle;
		});
		setFunction('setActorAntialiasing', function(antialiasing:Bool, id:String) {
			var actor:Dynamic = getActorByName(id);
			if (actor != null) actor.antialiasing = antialiasing;
		});
		setFunction('setActorDragX', function(v:Float, id:String) {
			var actor:Dynamic = getActorByName(id);
			if (actor != null) actor.drag.x = v;
		});
		setFunction('setActorDragY', function(v:Float, id:String) {
			var actor:Dynamic = getActorByName(id);
			if (actor != null) actor.drag.y = v;
		});
		setFunction('setActorFlipX', function(flip:Bool, id:String) {
			var actor:Dynamic = getActorByName(id);
			if (actor != null) actor.flipX = flip;
		});
		setFunction('setActorFlipY', function(flip:Bool, id:String) {
			var actor:Dynamic = getActorByName(id);
			if (actor != null) actor.flipY = flip;
		});
		setFunction('getActorFlipX', function(id:String):Bool {
			var actor:Dynamic = getActorByName(id);
			return (actor != null) ? actor.flipX : false;
		});
		// LTS 原版签名 bug：getActorFlipY(flip, id)——返回 id 对象的 flipY
		setFunction('getActorFlipY', function(flip:Dynamic, id:String):Bool {
			var actor:Dynamic = getActorByName(id);
			return (actor != null) ? actor.flipY : false;
		});
		setFunction('getActorX', function(id:String):Float {
			var actor:Dynamic = getActorByName(id);
			return (actor != null) ? actor.x : 0;
		});
		setFunction('getActorY', function(id:String):Float {
			var actor:Dynamic = getActorByName(id);
			return (actor != null) ? actor.y : 0;
		});
		setFunction('getActorAlpha', function(id:String):Float {
			var actor:Dynamic = getActorByName(id);
			return (actor != null) ? actor.alpha : 1;
		});
		setFunction('getActorAngle', function(id:String):Float {
			var actor:Dynamic = getActorByName(id);
			return (actor != null) ? actor.angle : 0;
		});
		setFunction('getActorWidth', function(id:String):Float {
			var actor:Dynamic = getActorByName(id);
			return (actor != null) ? actor.width : 0;
		});
		setFunction('getActorHeight', function(id:String):Float {
			var actor:Dynamic = getActorByName(id);
			return (actor != null) ? actor.height : 0;
		});
		setFunction('getActorLayer', function(id:String):Int {
			var actor:Dynamic = getActorByName(id);
			var ps:PlayState = PlayState.instance;
			if (actor == null || ps == null) return -1;
			return ps.members.indexOf(actor);
		});
		setFunction('setActorLayer', function(id:String, layer:Int) {
			var actor:Dynamic = getActorByName(id);
			var ps:PlayState = PlayState.instance;
			if (actor == null || ps == null) return;
			ps.remove(actor, true);
			ps.insert(layer, actor);
		});
		setFunction('getIsColliding', function(sprite1Name:String, sprite2Name:String):Bool {
			var a:Dynamic = getActorByName(sprite1Name);
			var b:Dynamic = getActorByName(sprite2Name);
			if (a == null || b == null || a.overlaps == null) return false;
			return a.overlaps(b);
		});
		// setActorProperty：反射设置任意属性（对照 LTS:2766）
		setFunction('setActorProperty', function(id:String, prop:String, value:Dynamic) {
			var actor:Dynamic = getActorByName(id);
			if (actor == null) return;
			// 点号深层属性
			var segs:Array<String> = prop.split('.');
			var cur:Dynamic = actor;
			for (i in 0...segs.length - 1)
			{
				if (cur == null) return;
				cur = Reflect.getProperty(cur, segs[i]);
			}
			if (cur != null) Reflect.setProperty(cur, segs[segs.length - 1], value);
		});
		// tweenActorProperty：tween 任意数值属性（对照 LTS:2746）
		setFunction('tweenActorProperty', function(id:String, prop:String, value:Dynamic, time:Float, easeStr:String = 'linear') {
			var actor:Dynamic = getActorByName(id);
			if (actor == null) return;
			var props:Dynamic = {};
			Reflect.setField(props, prop, value);
			doTween(actor, props, time, '', easeStr);
		});

		// --- 角色控制（对照 LTS:1690-1730, 1790-2045）---
		setFunction('playAnimation', function(id:String, anim:String, force:Bool = false, reverse:Bool = false, frame:Int = 0) {
			var actor:Dynamic = getActorByName(id);
			if (actor != null && actor.animation != null) actor.animation.play(anim, force, reverse, frame);
		});
		setFunction('dance', function(id:String, ?altAnim:String = '') {
			var actor:Dynamic = getActorByName(id);
			// Psych Character.dance() 无参（内部按 danceIdle 决定 idle/danceLeft/Right）；LE 的 altAnim 字符串在此无对应概念
			if (actor != null && actor.dance != null) actor.dance();
		});
		setFunction('playActorDance', function(id:String, ?altAnim:String = '') {
			var actor:Dynamic = getActorByName(id);
			if (actor != null && actor.dance != null) actor.dance();
		});
		setFunction('playCharacterAnimation', function(id:String, anim:String, force:Bool = false, reverse:Bool = false, frame:Int = 0) {
			var actor:Dynamic = getActorByName(id);
			if (actor != null && actor.animation != null) actor.animation.play(anim, force, reverse, frame);
		});
		setFunction('playCharacterDance', function(id:String, ?altAnim:String) {
			var actor:Dynamic = getActorByName(id);
			if (actor != null && actor.dance != null) actor.dance();
		});
		// LE Character 扩展字段（danceEnabled/playFullAnim/singPrefix/preventDanceForAnim）在 Psych Character 上不存在，
		// 用 Reflect 反射写入：字段存在时生效，不存在时静默跳过（避免编译/运行错误）。
		setFunction('setCharacterShouldDance', function(id:String, shouldDance:Bool = true) {
			var actor:Dynamic = getActorByName(id);
			if (actor != null) Reflect.setProperty(actor, 'danceEnabled', shouldDance);
		});
		setFunction('setCharacterPlayFullAnim', function(id:String, playFullAnim:Bool = true) {
			var actor:Dynamic = getActorByName(id);
			if (actor != null) Reflect.setProperty(actor, 'playFullAnim', playFullAnim);
		});
		setFunction('setCharacterSingPrefix', function(id:String, prefix:String) {
			var actor:Dynamic = getActorByName(id);
			if (actor != null) Reflect.setProperty(actor, 'singPrefix', prefix);
		});
		setFunction('setCharacterPreventDanceForAnim', function(id:String, preventDanceForAnim:Bool = true) {
			var actor:Dynamic = getActorByName(id);
			if (actor != null) Reflect.setProperty(actor, 'preventDanceForAnim', preventDanceForAnim);
		});
		setFunction('getPlayingActorAnimation', function(id:String):String {
			var actor:Dynamic = getActorByName(id);
			return (actor != null && actor.animation != null && actor.animation.curAnim != null) ? actor.animation.curAnim.name : '';
		});
		setFunction('getPlayingActorAnimationFrame', function(id:String):Int {
			var actor:Dynamic = getActorByName(id);
			return (actor != null && actor.animation != null) ? actor.animation.frameIndex : 0;
		});
		setFunction('getSingDirectionID', function(id:Int):Int {
			return id % 4;
		});
		setFunction('getSingDirectionAnim', function(id:Int, keyCount:Int = 4):String {
			return Note.colArray[id % keyCount];
		});
		// getOriginalCharX/Y：返回谱面定义的原始坐标（对照 LTS:1988-1998）
		// Kathy 的 SwagSong 无 player1X/dadX 等坐标字段（角色坐标由 Character 文件决定），返回 0。
		setFunction('getOriginalCharX', function(character:Int):Float {
			return 0;
		});
		setFunction('getOriginalCharY', function(character:Int):Float {
			return 0;
		});
		// 滚动速度（对照 LTS:2196-2220）
		setFunction('getBaseScrollSpeed', function():Float {
			return (PlayState.SONG != null) ? PlayState.SONG.speed : 1;
		});
		setFunction('getScrollSpeed', function():Float {
			var ps:PlayState = PlayState.instance;
			return (ps != null) ? ps.songSpeed : 1;
		});
		setFunction('setScrollSpeed', function(speed:Float) {
			var ps:PlayState = PlayState.instance;
			if (ps != null) ps.songSpeed = speed;
		});

		// ============================================================
		// 批次 2-B1：音符控制（rendered/unspawned）+ tween + 反射 + 歌曲 + 声音
		// ============================================================

		// --- 音符 getter/setter（对照 LTS:1178-1505）---
		setFunction('getNoteProperty', function(note:Note, property:String):Dynamic {
			if (note == null) return null;
			return Reflect.getProperty(note, property);
		});
		setFunction('getRenderedNotes', function():Int {
			var ps:PlayState = PlayState.instance;
			return (ps != null && ps.notes != null) ? ps.notes.length : 0;
		});
		setFunction('getUnspawnNotes', function():Int {
			var ps:PlayState = PlayState.instance;
			return (ps != null && ps.unspawnNotes != null) ? ps.unspawnNotes.length : 0;
		});
		setFunction('anyNotes', function():Bool {
			var ps:PlayState = PlayState.instance;
			return (ps != null && ps.notes != null && ps.notes.length > 0);
		});
		// makeNoteCopy：克隆某个渲染中音符为 lua 精灵（对照 LTS:1182）
		setFunction('makeNoteCopy', function(id:String, noteIdx:Int) {
			if (luaSprites.exists(id)) return;
			var src:Note = getRenderedNoteAt(noteIdx);
			if (src == null) return;
			var spr:FlxSprite = new FlxSprite(src.x, src.y);
			if (src.frames != null) spr.frames = src.frames; else if (src.graphic != null) spr.loadGraphicFromSprite(src);
			spr.animation.copyFrom(src.animation);
			spr.scale.set(src.scale.x, src.scale.y);
			spr.updateHitbox();
			luaSprites.set(id, spr);
			var ps:PlayState = PlayState.instance;
			if (ps != null) ps.add(spr);
		});

		// rendered 系列 getter
		setFunction('getRenderedNoteX', function(id:Int):Float {
			var n:Note = getRenderedNoteAt(id); return (n != null) ? n.x : 0;
		});
		setFunction('getRenderedNoteY', function(id:Int):Float {
			var n:Note = getRenderedNoteAt(id); return (n != null) ? n.y : 0;
		});
		setFunction('getRenderedNoteType', function(id:Int):String {
			var n:Note = getRenderedNoteAt(id); return (n != null) ? n.noteType : '';
		});
		setFunction('getRenderedNoteData', function(id:Int):Int {
			var n:Note = getRenderedNoteAt(id); return (n != null) ? n.noteData : 0;
		});
		setFunction('getRenderedNoteArrowType', function(id:Int):String {
			var n:Note = getRenderedNoteAt(id); return (n != null) ? n.noteType : '';
		});
		setFunction('getRenderedNoteParentX', function(id:Int):Float {
			var n:Note = getRenderedNoteAt(id);
			if (n == null) return 0;
			return (n.parent != null) ? n.parent.x : n.x;
		});
		setFunction('getRenderedNoteParentY', function(id:Int):Float {
			var n:Note = getRenderedNoteAt(id);
			if (n == null) return 0;
			return (n.parent != null) ? n.parent.y : n.y;
		});
		setFunction('getRenderedNoteHit', function(id:Int):Bool {
			var n:Note = getRenderedNoteAt(id);
			return (n != null) ? (n.wasGoodHit || n.missed || n.tooLate) : false;
		});
		setFunction('getRenderedNoteCalcX', function(id:Int):Float {
			var n:Note = getRenderedNoteAt(id); return (n != null) ? n.x : 0;
		});
		setFunction('getRenderedNoteStrumtime', function(id:Int):Float {
			var n:Note = getRenderedNoteAt(id); return (n != null) ? n.strumTime : 0;
		});
		setFunction('getRenderedNoteScaleX', function(id:Int):Float {
			var n:Note = getRenderedNoteAt(id); return (n != null) ? n.scale.x : 1;
		});
		setFunction('getRenderedNoteScaleY', function(id:Int):Float {
			var n:Note = getRenderedNoteAt(id); return (n != null) ? n.scale.y : 1;
		});
		setFunction('getRenderedNoteWidth', function(id:Int):Float {
			var n:Note = getRenderedNoteAt(id); return (n != null) ? n.width : 0;
		});
		setFunction('getRenderedNoteHeight', function(id:Int):Float {
			var n:Note = getRenderedNoteAt(id); return (n != null) ? n.height : 0;
		});
		setFunction('getRenderedNoteSustainScaleY', function(id:Int):Float {
			var n:Note = getRenderedNoteAt(id); return (n != null) ? n.scale.y : 1;
		});
		setFunction('getRenderedNoteOffsetX', function(id:Int):Float {
			var n:Note = getRenderedNoteAt(id); return (n != null) ? n.offsetX : 0;
		});
		setFunction('getRenderedNoteOffsetY', function(id:Int):Float {
			var n:Note = getRenderedNoteAt(id); return (n != null) ? n.offsetY : 0;
		});
		setFunction('getRenderedNotePrevNoteStrumtime', function(id:Int):Float {
			var n:Note = getRenderedNoteAt(id);
			if (n == null) return 0;
			return (n.prevNote != null) ? n.prevNote.strumTime : n.strumTime;
		});
		setFunction('getRenderedNoteSkewX', function(id:Int):Float {
			var n:Note = getRenderedNoteAt(id);
			return (n != null) ? (Reflect.field(n, 'skewX') != null ? Reflect.field(n, 'skewX') : 0) : 0;
		});
		setFunction('getRenderedNoteSkewY', function(id:Int):Float {
			var n:Note = getRenderedNoteAt(id);
			return (n != null) ? (Reflect.field(n, 'skewY') != null ? Reflect.field(n, 'skewY') : 0) : 0;
		});
		setFunction('isSustain', function(id:Int):Bool {
			var n:Note = getRenderedNoteAt(id); return (n != null) ? n.isSustainNote : false;
		});
		setFunction('isParentSustain', function(id:Int):Bool {
			var n:Note = getRenderedNoteAt(id);
			return (n != null && n.parent != null) ? n.parent.isSustainNote : false;
		});
		setFunction('isRenderedNoteSustainEnd', function(id:Int):Bool {
			var n:Note = getRenderedNoteAt(id);
			return (n != null && n.isSustainNote) ? (n.nextNote == null || !n.nextNote.isSustainNote) : false;
		});
		setFunction('getRenderedNoteColor', function(id:Int):Dynamic {
			var n:Note = getRenderedNoteAt(id); return (n != null) ? n.color : 0xFFFFFFFF;
		});
		setFunction('getRenderedNoteAffectedByColor', function(id:Int):Bool {
			var n:Note = getRenderedNoteAt(id); return (n != null) ? !n.noAnimation : true;
		});

		// rendered 系列 setter（LTS 签名：值在前，id 在后）
		setFunction('setRenderedNotePos', function(x:Float, y:Float, id:Int) {
			var n:Note = getRenderedNoteAt(id);
			if (n != null) { n.x = x; n.y = y; }
		});
		setFunction('setRenderedNoteAlpha', function(alpha:Float, id:Int) {
			var n:Note = getRenderedNoteAt(id);
			if (n != null) n.alpha = alpha;
		});
		setFunction('setRenderedNoteScale', function(scale:Float, id:Int) {
			var n:Note = getRenderedNoteAt(id);
			if (n != null) n.scale.set(scale, scale);
		});
		setFunction('setRenderedNoteScaleX', function(scale:Float, id:Int) {
			var n:Note = getRenderedNoteAt(id);
			if (n != null) n.scale.x = scale;
		});
		setFunction('setRenderedNoteScaleY', function(scale:Float, id:Int) {
			var n:Note = getRenderedNoteAt(id);
			if (n != null) n.scale.y = scale;
		});
		setFunction('setRenderedNoteScaleXY', function(scaleX:Float, scaleY:Float, id:Int) {
			var n:Note = getRenderedNoteAt(id);
			if (n != null) n.scale.set(scaleX, scaleY);
		});
		setFunction('setRenderedNoteAngle', function(angle:Float, id:Int) {
			var n:Note = getRenderedNoteAt(id);
			if (n != null) n.angle = angle;
		});
		setFunction('setRenderedNoteSkewX', function(skew:Float, id:Int) {
			var n:Note = getRenderedNoteAt(id);
			if (n != null && Reflect.hasField(n, 'skewX')) Reflect.setProperty(n, 'skewX', skew);
		});
		setFunction('setRenderedNoteSkewY', function(skew:Float, id:Int) {
			var n:Note = getRenderedNoteAt(id);
			if (n != null && Reflect.hasField(n, 'skewY')) Reflect.setProperty(n, 'skewY', skew);
		});
		setFunction('setRenderedNoteColor', function(r:Float, g:Float, b:Float, id:Int) {
			var n:Note = getRenderedNoteAt(id);
			if (n != null) n.color = FlxColor.fromRGB(Std.int(r), Std.int(g), Std.int(b));
		});
		setFunction('setRenderedNoteColorForce', function(r:Float, g:Float, b:Float, id:Int) {
			var n:Note = getRenderedNoteAt(id);
			if (n != null) n.color = FlxColor.fromRGB(Std.int(r), Std.int(g), Std.int(b));
		});
		setFunction('setRenderedNoteSpeed', function(speed:Float, id:Int) {
			var n:Note = getRenderedNoteAt(id);
			var ps:PlayState = PlayState.instance;
			if (n != null && ps != null) n.multSpeed = speed / ((ps.songSpeed == 0) ? 1 : ps.songSpeed);
		});

		// unspawned 系列 getter
		setFunction('getUnspawnedNoteType', function(id:Int):String {
			var n:Note = getUnspawnedNoteAt(id); return (n != null) ? n.noteType : '';
		});
		setFunction('getUnspawnedNoteNoteType', function(id:Int):String {
			var n:Note = getUnspawnedNoteAt(id); return (n != null) ? n.noteType : '';
		});
		setFunction('getUnspawnedNoteArrowType', function(id:Int):String {
			var n:Note = getUnspawnedNoteAt(id); return (n != null) ? n.noteType : '';
		});
		setFunction('getUnspawnedNoteStrumtime', function(id:Int):Float {
			var n:Note = getUnspawnedNoteAt(id); return (n != null) ? n.strumTime : 0;
		});
		setFunction('getUnspawnedNoteMustPress', function(id:Int):Bool {
			var n:Note = getUnspawnedNoteAt(id); return (n != null) ? n.mustPress : false;
		});
		setFunction('getUnspawnedNoteSustainNote', function(id:Int):Bool {
			var n:Note = getUnspawnedNoteAt(id); return (n != null) ? n.isSustainNote : false;
		});
		setFunction('getUnspawnedNoteNoteData', function(id:Int):Int {
			var n:Note = getUnspawnedNoteAt(id); return (n != null) ? n.noteData : 0;
		});
		setFunction('getUnspawnedNoteData', function(id:Int):Int {
			var n:Note = getUnspawnedNoteAt(id); return (n != null) ? n.noteData : 0;
		});
		setFunction('getUnspawnedNoteScaleX', function(id:Int):Float {
			var n:Note = getUnspawnedNoteAt(id); return (n != null) ? n.scale.x : 1;
		});
		setFunction('getUnspawnedNoteScaleY', function(id:Int):Float {
			var n:Note = getUnspawnedNoteAt(id); return (n != null) ? n.scale.y : 1;
		});
		setFunction('getUnspawnedNoteSingAnimPrefix', function(id:Int):String {
			var n:Note = getUnspawnedNoteAt(id);
			return (n != null) ? Note.colArray[n.noteData % (Note.colArray.length > 0 ? Note.colArray.length : 4)] : '';
		});
		setFunction('getUnspawnedNoteSingAnimSuffix', function(id:Int):String {
			var n:Note = getUnspawnedNoteAt(id); return (n != null) ? n.animSuffix : '';
		});
		setFunction('getUnspawnedNoteColor', function(id:Int):Dynamic {
			var n:Note = getUnspawnedNoteAt(id); return (n != null) ? n.color : 0xFFFFFFFF;
		});
		setFunction('getUnspawnedNoteAffectedByColor', function(id:Int):Bool {
			var n:Note = getUnspawnedNoteAt(id); return (n != null) ? !n.noAnimation : true;
		});

		// unspawned 系列 setter
		setFunction('setUnspawnedNoteSingAnimPrefix', function(id:Int, prefix:String) {
			var n:Note = getUnspawnedNoteAt(id);
			if (n != null) Reflect.setProperty(n, 'singAnimPrefix', prefix);
		});
		setFunction('setUnspawnedNoteSingAnimSuffix', function(id:Int, suffix:String) {
			var n:Note = getUnspawnedNoteAt(id);
			if (n != null) n.animSuffix = suffix;
		});
		setFunction('setUnspawnedNoteXOffset', function(id:Int, offset:Float) {
			var n:Note = getUnspawnedNoteAt(id);
			if (n != null) n.offsetX = offset;
		});
		setFunction('setUnspawnedNoteYOffset', function(id:Int, offset:Float) {
			var n:Note = getUnspawnedNoteAt(id);
			if (n != null) n.offsetY = offset;
		});
		setFunction('setUnspawnedNoteAngle', function(id:Int, offset:Float) {
			var n:Note = getUnspawnedNoteAt(id);
			if (n != null) n.angle = offset;
		});
		setFunction('setUnspawnedNoteColor', function(r:Float, g:Float, b:Float, id:Int) {
			var n:Note = getUnspawnedNoteAt(id);
			if (n != null) n.color = FlxColor.fromRGB(Std.int(r), Std.int(g), Std.int(b));
		});
		setFunction('setUnspawnedNoteColorForce', function(r:Float, g:Float, b:Float, id:Int) {
			var n:Note = getUnspawnedNoteAt(id);
			if (n != null) n.color = FlxColor.fromRGB(Std.int(r), Std.int(g), Std.int(b));
		});

		// --- tween 系统（对照 LTS:2257-2773）---
		setFunction('tween', function(obj:String, properties:Dynamic, duration:Float, ease:String, ?startDelay:Float = 0.0, ?onComplete:Dynamic) {
			var actor:Dynamic = getActorByName(obj);
			if (actor == null) return;
			doTween(actor, properties, duration, (onComplete != null) ? Std.string(onComplete) : '', ease, startDelay);
		});
		setFunction('tweenCancel', function(tween:String) {
			var t:FlxTween = luaTweens.get(tween);
			if (t != null) t.cancel();
		});
		setFunction('tweenPause', function(tween:String) {
			var t:FlxTween = luaTweens.get(tween);
			if (t != null) t.active = false;
		});
		setFunction('tweenResume', function(tween:String) {
			var t:FlxTween = luaTweens.get(tween);
			if (t != null) t.active = true;
		});
		setFunction('cancelTweensOf', function(id:String) {
			var actor:Dynamic = getActorByName(id);
			if (actor != null) FlxTween.cancelTweensOf(actor);
		});
		// pauseTweensOf/resumeTweensOf（对照 LTS:1108-1114）
		// flixel 5.x 的 FlxTween 无 object 字段，无法按 actor 过滤，暂停/恢复本脚本注册的全部 tween。
		setFunction('pauseTweensOf', function(id:String) {
			for (k in luaTweens.keys())
			{
				var t:FlxTween = luaTweens.get(k);
				if (t != null) t.active = false;
			}
		});
		setFunction('resumeTweensOf', function(id:String) {
			for (k in luaTweens.keys())
			{
				var t:FlxTween = luaTweens.get(k);
				if (t != null) t.active = true;
			}
		});

		// 相机/HUD tween 三件套（Pos/Angle/Zoom）+ Out/In 变体（对照 LTS:2330-2660）
		function tweenCameraLike(target:String, props:Dynamic, time:Float, onComplete:String):Void
		{
			var cam:FlxCamera = cameraFromString(target == 'hud' ? 'hud' : 'game');
			if (cam == null) return;
			doTween(cam, props, time, onComplete);
		}
		setFunction('tweenCameraPos', function(toX:Int, toY:Int, time:Float, onComplete:String = '') {
			tweenCameraLike('game', {x: toX, y: toY}, time, onComplete);
		});
		setFunction('tweenCameraAngle', function(toAngle:Float, time:Float, onComplete:String = '') {
			tweenCameraLike('game', {angle: toAngle}, time, onComplete);
		});
		setFunction('tweenCameraZoom', function(toZoom:Float, time:Float, onComplete:String = '') {
			tweenCameraLike('game', {zoom: toZoom}, time, onComplete);
		});
		setFunction('tweenHudPos', function(toX:Int, toY:Int, time:Float, onComplete:String = '') {
			tweenCameraLike('hud', {x: toX, y: toY}, time, onComplete);
		});
		setFunction('tweenHudAngle', function(toAngle:Float, time:Float, onComplete:String = '') {
			tweenCameraLike('hud', {angle: toAngle}, time, onComplete);
		});
		setFunction('tweenHudZoom', function(toZoom:Float, time:Float, onComplete:String = '') {
			tweenCameraLike('hud', {zoom: toZoom}, time, onComplete);
		});
		setFunction('tweenCameraPosOut', function(toX:Int, toY:Int, time:Float, onComplete:String = '') {
			tweenCameraLike('game', {x: toX, y: toY}, time, onComplete);
		});
		setFunction('tweenCameraAngleOut', function(toAngle:Float, time:Float, onComplete:String = '') {
			tweenCameraLike('game', {angle: toAngle}, time, onComplete);
		});
		setFunction('tweenCameraZoomOut', function(toZoom:Float, time:Float, onComplete:String = '') {
			tweenCameraLike('game', {zoom: toZoom}, time, onComplete);
		});
		setFunction('tweenHudPosOut', function(toX:Int, toY:Int, time:Float, onComplete:String = '') {
			tweenCameraLike('hud', {x: toX, y: toY}, time, onComplete);
		});
		setFunction('tweenHudAngleOut', function(toAngle:Float, time:Float, onComplete:String = '') {
			tweenCameraLike('hud', {angle: toAngle}, time, onComplete);
		});
		setFunction('tweenHudZoomOut', function(toZoom:Float, time:Float, onComplete:String = '') {
			tweenCameraLike('hud', {zoom: toZoom}, time, onComplete);
		});
		setFunction('tweenCameraPosIn', function(toX:Int, toY:Int, time:Float, onComplete:String = '') {
			tweenCameraLike('game', {x: toX, y: toY}, time, onComplete);
		});
		setFunction('tweenCameraAngleIn', function(toAngle:Float, time:Float, onComplete:String = '') {
			tweenCameraLike('game', {angle: toAngle}, time, onComplete);
		});
		setFunction('tweenCameraZoomIn', function(toZoom:Float, time:Float, onComplete:String = '') {
			tweenCameraLike('game', {zoom: toZoom}, time, onComplete);
		});
		setFunction('tweenHudPosIn', function(toX:Int, toY:Int, time:Float, onComplete:String = '') {
			tweenCameraLike('hud', {x: toX, y: toY}, time, onComplete);
		});
		setFunction('tweenHudAngleIn', function(toAngle:Float, time:Float, onComplete:String = '') {
			tweenCameraLike('hud', {angle: toAngle}, time, onComplete);
		});
		setFunction('tweenHudZoomIn', function(toZoom:Float, time:Float, onComplete:String = '') {
			tweenCameraLike('hud', {zoom: toZoom}, time, onComplete);
		});

		// 对象 tween（Pos/Angle/XAngle/YAngle/Fade/Color/ScaleX/ScaleY + Out/In 变体）
		function tweenActorLike(id:String, props:Dynamic, time:Float, onComplete:String, ?ease:String = 'linear'):Void
		{
			var actor:Dynamic = getActorByName(id);
			if (actor == null) return;
			doTween(actor, props, time, onComplete, ease);
		}
		setFunction('tweenPos', function(id:String, toX:Int, toY:Int, time:Float, ?onComplete:String = '') {
			tweenActorLike(id, {x: toX, y: toY}, time, onComplete);
		});
		setFunction('tweenPosXAngle', function(id:String, toX:Int, toAngle:Float, time:Float, onComplete:String = '') {
			tweenActorLike(id, {x: toX, angle: toAngle}, time, onComplete);
		});
		setFunction('tweenPosYAngle', function(id:String, toY:Int, toAngle:Float, time:Float, onComplete:String = '') {
			tweenActorLike(id, {y: toY, angle: toAngle}, time, onComplete);
		});
		setFunction('tweenAngle', function(id:String, toAngle:Int, time:Float, onComplete:String = '') {
			tweenActorLike(id, {angle: toAngle}, time, onComplete);
		});
		setFunction('tweenPosOut', function(id:String, toX:Int, toY:Int, time:Float, onComplete:String = '') {
			tweenActorLike(id, {x: toX, y: toY}, time, onComplete);
		});
		setFunction('tweenPosXAngleOut', function(id:String, toX:Int, toAngle:Float, time:Float, onComplete:String = '') {
			tweenActorLike(id, {x: toX, angle: toAngle}, time, onComplete);
		});
		setFunction('tweenPosYAngleOut', function(id:String, toY:Int, toAngle:Float, time:Float, onComplete:String = '') {
			tweenActorLike(id, {y: toY, angle: toAngle}, time, onComplete);
		});
		setFunction('tweenAngleOut', function(id:String, toAngle:Int, time:Float, onComplete:String = '') {
			tweenActorLike(id, {angle: toAngle}, time, onComplete);
		});
		setFunction('tweenPosIn', function(id:String, toX:Int, toY:Int, time:Float, onComplete:String = '') {
			tweenActorLike(id, {x: toX, y: toY}, time, onComplete);
		});
		setFunction('tweenPosXAngleIn', function(id:String, toX:Int, toAngle:Float, time:Float, onComplete:String = '') {
			tweenActorLike(id, {x: toX, angle: toAngle}, time, onComplete);
		});
		setFunction('tweenPosYAngleIn', function(id:String, toY:Int, toAngle:Float, time:Float, onComplete:String = '') {
			tweenActorLike(id, {y: toY, angle: toAngle}, time, onComplete);
		});
		setFunction('tweenAngleIn', function(id:String, toAngle:Int, time:Float, onComplete:String = '') {
			tweenActorLike(id, {angle: toAngle}, time, onComplete);
		});
		setFunction('tweenFadeIn', function(id:String, toAlpha:Float, time:Float, onComplete:String = '') {
			tweenActorLike(id, {alpha: toAlpha}, time, onComplete);
		});
		setFunction('tweenFadeOut', function(id:String, toAlpha:Float, time:Float, onComplete:String = '') {
			tweenActorLike(id, {alpha: toAlpha}, time, onComplete);
		});
		setFunction('tweenFadeCubeInOut', function(id:String, toAlpha:Float, time:Float, onComplete:String = '') {
			tweenActorLike(id, {alpha: toAlpha}, time, onComplete, 'cubeinout');
		});
		// tweenActorColor：从 rgb1 渐变到 rgb2（对照 LTS:2708/2773 双注册）
		function tweenActorColorImpl(id:String, r1:Int, g1:Int, b1:Int, r2:Int, g2:Int, b2:Int, time:Float, onComplete:String = ''):Void
		{
			var actor:Dynamic = getActorByName(id);
			if (actor == null) return;
			var key:String = 'leTween' + (tweenCount++);
			var tween:FlxTween = FlxTween.color(actor, time, FlxColor.fromRGB(r1, g1, b1), FlxColor.fromRGB(r2, g2, b2), {
				onComplete: function(t:FlxTween)
				{
					luaTweens.remove(key);
					if (onComplete != null && onComplete != '') call(onComplete, [t]);
				}
			});
			luaTweens.set(key, tween);
		}
		setFunction('tweenActorColor', function(id:String, r1:Int, g1:Int, b1:Int, r2:Int, g2:Int, b2:Int, time:Float, onComplete:String = '') {
			tweenActorColorImpl(id, r1, g1, b1, r2, g2, b2, time, onComplete);
		});
		setFunction('tweenScaleX', function(id:String, toScale:Float, time:Float, easeStr:String = '', onComplete:String = '') {
			tweenActorLike(id, {scale: {x: toScale}}, time, onComplete, easeStr);
		});
		setFunction('tweenScaleY', function(id:String, toScale:Float, time:Float, easeStr:String = '', onComplete:String = '') {
			tweenActorLike(id, {scale: {y: toScale}}, time, onComplete, easeStr);
		});

		// --- 全局属性反射（对照 LTS:2700-2940，Psych 风格 set/get）---
		setFunction('set', function(property:Dynamic, value:Dynamic):Void {
			var segs:Array<String> = Std.string(property).split('.');
			if (segs.length == 1)
			{
				set(Std.string(property), value);
				return;
			}
			var cur:Dynamic = getActorByName(segs[0]);
			for (i in 1...segs.length - 1)
			{
				if (cur == null) return;
				cur = Reflect.getProperty(cur, segs[i]);
			}
			if (cur != null) Reflect.setProperty(cur, segs[segs.length - 1], value);
		});
		setFunction('get', function(property:Dynamic):Dynamic {
			return getActorByName(Std.string(property));
		});
		setFunction('setClass', function(class_name:String, property:Dynamic, value:Dynamic):Void {
			var target:Class<Dynamic> = Type.resolveClass(class_name);
			if (target != null) Reflect.setProperty(target, Std.string(property), value);
		});
		setFunction('getClass', function(class_name:String, property:Dynamic):Dynamic {
			var target:Class<Dynamic> = Type.resolveClass(class_name);
			return (target != null) ? Reflect.getProperty(target, Std.string(property)) : null;
		});
		setFunction('setProperty', function(object:String, property:String, value:Dynamic) {
			var segs:Array<String> = property.split('.');
			var cur:Dynamic = getActorByName(object);
			for (i in 0...segs.length - 1)
			{
				if (cur == null) return;
				cur = Reflect.getProperty(cur, segs[i]);
			}
			if (cur != null) Reflect.setProperty(cur, segs[segs.length - 1], value);
		});
		setFunction('getProperty', function(object:String, property:String):Dynamic {
			var segs:Array<String> = property.split('.');
			var cur:Dynamic = getActorByName(object);
			for (i in 0...segs.length)
			{
				if (cur == null) return null;
				cur = Reflect.getProperty(cur, segs[i]);
			}
			return cur;
		});
		setFunction('getPropertyFromClass', function(className:String, variable:String):Dynamic {
			var target:Class<Dynamic> = Type.resolveClass(className);
			return (target != null) ? Reflect.getProperty(target, variable) : null;
		});
		setFunction('setPropertyFromClass', function(className:String, variable:String, value:Dynamic) {
			var target:Class<Dynamic> = Type.resolveClass(className);
			if (target != null) Reflect.setProperty(target, variable, value);
		});

		// --- 歌曲控制（对照 LTS:2940-2988）---
		setFunction('setSongPosition', function(position:Float) {
			var ps:PlayState = PlayState.instance;
			if (ps != null) Conductor.songPosition = position;
		});
		setFunction('stopSong', function() {
			var ps:PlayState = PlayState.instance;
			if (ps != null && FlxG.sound.music != null) FlxG.sound.music.stop();
		});
		setFunction('endSong', function() {
			var ps:PlayState = PlayState.instance;
			if (ps != null) ps.endSong();
		});

		// --- 声音控制补充（对照 LTS:2202-2245）---
		setFunction('removeSound', function(id:String) {
			var snd:FlxSound = luaSounds.get(id);
			if (snd != null)
			{
				snd.stop();
				snd.destroy();
				luaSounds.remove(id);
			}
		});
		setFunction('pauseSound', function(id:String) {
			var snd:FlxSound = luaSounds.get(id);
			if (snd != null) snd.pause();
		});
		setFunction('resumeSound', function(id:String) {
			var snd:FlxSound = luaSounds.get(id);
			if (snd != null) snd.resume();
		});
		setFunction('setSoundVolume', function(id:String, volume:Float) {
			var snd:FlxSound = luaSounds.get(id);
			if (snd != null) snd.volume = volume;
		});
		setFunction('getSoundTime', function(id:String):Float {
			var snd:FlxSound = luaSounds.get(id);
			return (snd != null) ? snd.time : 0;
		});
		setFunction('loopSound', function(id:String, loop:Bool) {
			var snd:FlxSound = luaSounds.get(id);
			if (snd != null) snd.looped = loop;
		});

		// ============================================================
		// 批次 2-B2：stage sprite、new 系、事件、工具、math、窗口、杂项
		// ============================================================

		// --- stage sprite（挂到舞台组，对照 LTS:519-575）---
		function makeStageSpriteInternal(id:String, filename:String, x:Float, y:Float, size:Float = 1, ?sizeY:Float, animated:Bool, dancing:Bool):Void
		{
			if (luaSprites.exists(id)) return;
			var ps:PlayState = PlayState.instance;
			if (ps == null) return;
			var spr:FlxSprite = new FlxSprite(x, y);
			if (filename != null && filename.length > 0)
			{
				if (animated) spr.frames = backend.Paths.getSparrowAtlas(filename);
				else spr.loadGraphic(backend.Paths.image(filename));
			}
			spr.scale.set(size, sizeY == null ? size : sizeY);
			spr.updateHitbox();
			luaSprites.set(id, spr);
			ps.add(spr);
		}
		setFunction('makeStageSprite', function(id:String, filename:String, x:Float, y:Float, size:Float = 1, ?sizeY:Float) {
			makeStageSpriteInternal(id, filename, x, y, size, sizeY, false, false);
		});
		setFunction('makeStageAnimatedSprite', function(id:String, filename:String, x:Float, y:Float, size:Float = 1, ?sizeY:Float) {
			makeStageSpriteInternal(id, filename, x, y, size, sizeY, true, false);
		});
		// dancing sprite：Psych 无 FlxDancingSprite，按 animated sprite 处理（dance 语义见 playActorDance）
		setFunction('makeStageDancingSprite', function(id:String, filename:String, x:Float, y:Float, size:Float = 1, ?sizeY:Float, ?animSuffix:String) {
			makeStageSpriteInternal(id, filename, x, y, size, sizeY, true, true);
		});

		// --- new 系：创建但不自动 add（对照 LTS:755-841）---
		setFunction('newSprite', function(id:String, filename:String, x:Float, y:Float, size:Float = 1, ?sizeY:Float) {
			if (luaSprites.exists(id)) return;
			var spr:FlxSprite = new FlxSprite(x, y);
			if (filename != null && filename.length > 0) spr.loadGraphic(backend.Paths.image(filename));
			spr.scale.set(size, sizeY == null ? size : sizeY);
			spr.updateHitbox();
			luaSprites.set(id, spr);
		});
		setFunction('newSpriteCopy', function(id:String, targetID:String) {
			if (luaSprites.exists(id)) return;
			var actor:Dynamic = getActorByName(targetID);
			if (actor == null) return;
			var spr:FlxSprite = new FlxSprite(actor.x, actor.y);
			spr.loadGraphicFromSprite(actor);
			spr.alpha = actor.alpha;
			spr.angle = actor.angle;
			spr.scale.x = actor.scale.x;
			spr.scale.y = actor.scale.y;
			spr.flipX = actor.flipX;
			spr.flipY = actor.flipY;
			spr.color = actor.color;
			luaSprites.set(id, spr);
		});
		setFunction('newAnimatedSprite', function(id:String, filename:String, x:Float, y:Float, size:Float = 1, ?sizeY:Float) {
			if (luaSprites.exists(id)) return;
			var spr:FlxSprite = new FlxSprite(x, y);
			if (filename != null && filename.length > 0) spr.frames = backend.Paths.getSparrowAtlas(filename);
			spr.scale.set(size, sizeY == null ? size : sizeY);
			spr.updateHitbox();
			luaSprites.set(id, spr);
		});
		setFunction('makeDancingSprite', function(id:String, filename:String, x:Float, y:Float, size:Float = 1, ?sizeY:Float, ?animSuffix:String) {
			if (luaSprites.exists(id)) return;
			var spr:FlxSprite = new FlxSprite(x, y);
			if (filename != null && filename.length > 0) spr.frames = backend.Paths.getSparrowAtlas(filename);
			spr.scale.set(size, sizeY == null ? size : sizeY);
			spr.updateHitbox();
			luaSprites.set(id, spr);
			var ps:PlayState = PlayState.instance;
			if (ps != null) ps.add(spr);
		});
		setFunction('newDancingSprite', function(id:String, filename:String, x:Float, y:Float, size:Float = 1, ?sizeY:Float, ?animSuffix:String) {
			if (luaSprites.exists(id)) return;
			var spr:FlxSprite = new FlxSprite(x, y);
			if (filename != null && filename.length > 0) spr.frames = backend.Paths.getSparrowAtlas(filename);
			spr.scale.set(size, sizeY == null ? size : sizeY);
			spr.updateHitbox();
			luaSprites.set(id, spr);
		});
		setFunction('destroySprite', function(id:String) {
			var spr:FlxSprite = luaSprites.get(id);
			if (spr != null)
			{
				spr.destroy();
				luaSprites.remove(id);
			}
		});
		// addActorAnimationIndices：按帧索引注册动画（对照 LTS:1631）
		setFunction('addActorAnimationIndices', function(id:String, prefix:String, indiceString:String, anim:String, fps:Int = 30, looped:Bool = true) {
			var actor:Dynamic = getActorByName(id);
			if (actor == null || actor.animation == null) return;
			var indices:Array<Int> = [];
			for (s in indiceString.split(','))
			{
				var v:Int = Std.parseInt(s.trim());
				if (!Math.isNaN(v)) indices.push(v);
			}
			actor.animation.addByIndices(prefix, anim, indices, fps, looped);
		});

		// --- 颜色工具补充（对照 LTS:614-642）---
		setFunction('rgbToHsv', function(r:Int, g:Int, b:Int):Array<Int> {
			var c:FlxColor = FlxColor.fromRGB(r, g, b);
			return [Std.int(c.hue), Std.int(c.saturation * 100), Std.int(c.brightness * 100)];
		});
		setFunction('dominantColor', function(id:String):Int {
			var actor:Dynamic = getActorByName(id);
			return (actor != null) ? actor.color : 0xFFFFFFFF;
		});
		setFunction('dominantColorFrame', function(id:String):Int {
			var actor:Dynamic = getActorByName(id);
			return (actor != null) ? actor.color : 0xFFFFFFFF;
		});
		setFunction('actorScreenCenter', function(id:String) {
			var actor:Dynamic = getActorByName(id);
			if (actor == null) return;
			actor.x = (FlxG.width - actor.width) / 2;
			actor.y = (FlxG.height - actor.height) / 2;
		});

		// makeCamera：注册自定义相机名映射（对照 LTS:1069）
		setFunction('makeCamera', function(camStr:String) {
			// Psych 相机由 PlayState 管理；仅记录名字到 luaSprites 兼容表（等价映射见 cameraFromString）
			luaSprites.set(camStr, PlayState.instance.camGame);
		});

		// --- 角色切换（对照 LTS:2089-2195）---
		// changeDadCharacter/changeBoyfriendCharacter：换角色（对照 LTS:1968-1985）。
		// Kathy 的 SwagSong 无 dadX/player1X 坐标字段，坐标保持角色默认（不重置）。
		setFunction('changeDadCharacter', function(character:String) {
			var ps:PlayState = PlayState.instance;
			if (ps == null || ps.dad == null) return;
			ps.dad.changeCharacter(character);
		});
		setFunction('changeBoyfriendCharacter', function(character:String) {
			var ps:PlayState = PlayState.instance;
			if (ps == null || ps.boyfriend == null) return;
			ps.boyfriend.changeCharacter(character);
		});

		// --- 事件（对照 LTS:407, 2989-3012）---
		setFunction('triggerEvent', function(event_name:String, argument_1:Dynamic, argument_2:Dynamic) {
			var ps:PlayState = PlayState.instance;
			if (ps != null) ps.triggerEvent(event_name, Std.string(argument_1), Std.string(argument_2), '', '', Conductor.songPosition);
		});
		setFunction('justPressedDodgeKey', function():Bool {
			return false; // Psych 无 dodge 键
		});
		setFunction('getCharFromEvent', function(eventId:String):Dynamic {
			return null; // LE 事件角色系统未移植（Psych 事件为 triggerEvent 字符串参数）
		});
		setFunction('charFromEvent', function(id:String):Dynamic {
			return null;
		});
		setFunction('updateRating', function() {
			var ps:PlayState = PlayState.instance;
			if (ps != null) Reflect.callMethod(ps, Reflect.field(ps, 'updateRatingCounters'), []);
		});
		// stage colorswap / strum 换算：Psych 无对应系统，占位（对照 LTS:3015-3065）
		setFunction('tweenStageColorSwap', function(prop:String, value:Dynamic, time:Float, easeStr:String = 'linear') {
			trace('[LE lua:' + scriptName + '] tweenStageColorSwap: 未移植（Psych 无 stage colorswap）');
		});
		setFunction('setStageColorSwap', function(prop:String, value:Dynamic) {
			trace('[LE lua:' + scriptName + '] setStageColorSwap: 未移植（Psych 无 stage colorswap）');
		});
		setFunction('getStrumTimeFromStep', function(step:Float):Float {
			return step * (Conductor.crochet / 4);
		});
		// shader 占位（Psych 侧 shader 系统为 setShaderXxx，名字不同；LTS 的 CustomShader 体系未移植）
		setFunction('setActor3DShader', function(id:String, ?speed:Float = 3, ?frequency:Float = 10, ?amplitude:Float = 0.25) {
			trace('[LE lua:' + scriptName + '] setActor3DShader: 未移植');
		});
		setFunction('setActorNoShader', function(id:String) {
			var actor:Dynamic = getActorByName(id);
			if (actor != null) actor.shader = null;
		});
		setFunction('setActorCustomShader', function(id:String, actor:String) {
			trace('[LE lua:' + scriptName + '] setActorCustomShader: 未移植（Psych shader 体系名不同）');
		});
		setFunction('setActorNoCustomShader', function(actor:String) {
			var a:Dynamic = getActorByName(actor);
			if (a != null) a.shader = null;
		});
		setFunction('setCameraCustomShader', function(id:String, camera:String) {
			trace('[LE lua:' + scriptName + '] setCameraCustomShader: 未移植');
		});
		setFunction('pushShaderToCamera', function(id:String, camera:String) {
			trace('[LE lua:' + scriptName + '] pushShaderToCamera: 未移植');
		});
		setFunction('setCameraNoCustomShader', function(camera:String) {
			var cam:FlxCamera = cameraFromString(camera);
			if (cam != null) cam.filters = null;
		});
		setFunction('getCustomShaderBool', function(id:String, property:String):Bool { return false; });
		setFunction('getCustomShaderInt', function(id:String, property:String):Int { return 0; });
		setFunction('getCustomShaderFloat', function(id:String, property:String):Float { return 0; });
		setFunction('setCustomShaderBool', function(id:String, property:String, value:Bool) {});
		setFunction('setCustomShaderInt', function(id:String, property:String, value:Int) {});
		setFunction('setCustomShaderFloat', function(id:String, property:String, value:Float) {});
		setFunction('tweenShader', function(id:String, property:String, value:Float, duration:Float, ease:String = 'linear', startDelay:Float = 0.0, ?onComplete:Dynamic) {});
		setFunction('initShader', function(id:String, frag:String, ?vert:String) {
			trace('[LE lua:' + scriptName + '] initShader: 未移植');
		});
		setFunction('setActorShader', function(actorStr:String, shaderName:String) {
			trace('[LE lua:' + scriptName + '] setActorShader: 未移植');
		});
		setFunction('setCameraShader', function(camera:String, id:String) {
			trace('[LE lua:' + scriptName + '] setCameraShader: 未移植');
		});
		setFunction('removeCameraShader', function(camStr:String, shaderName:String) {
			var cam:FlxCamera = cameraFromString(camStr);
			if (cam != null) cam.filters = null;
		});
		setFunction('setShaderProperty', function(id:String, property:String, value:Dynamic) {});
		setFunction('tweenShaderProperty', function(id:String, property:String, value:Float, duration:Float, ease:String = 'linear', startDelay:Float = 0.0, ?onComplete:Dynamic) {});

		// --- 工具函数（对照 LTS:3305-3390）---
		setFunction('arrayToCSV', function(data:Array<Int>, width:Int, invert:Bool):String {
			return FlxStringUtil.arrayToCSV(data, width, invert);
		});
		setFunction('filterDigits', function(input:String):String {
			return FlxStringUtil.filterDigits(input);
		});
		setFunction('formatArray', function(anyArray:Array<Dynamic>):String {
			return FlxStringUtil.formatArray(anyArray);
		});
		setFunction('formatBytes', function(bytes:Float, precision:Int = 2):String {
			return FlxStringUtil.formatBytes(bytes, precision);
		});
		setFunction('formatTime', function(seconds:Float, showMS:Bool = false):String {
			return FlxStringUtil.formatTime(seconds, showMS);
		});
		setFunction('getClassName', function(object:Dynamic, simple:Bool = false):String {
			return FlxStringUtil.getClassName(object, simple);
		});
		setFunction('printIP', function():Void {
			trace('${FlxG.random.int(100, 999)}.${FlxG.random.int(1, 99)}.${FlxG.random.int(1, 99)}.${FlxG.random.int(1, 99)}');
		});
		setFunction('getIP', function():String {
			return '${FlxG.random.int(100, 999)}.${FlxG.random.int(1, 99)}.${FlxG.random.int(1, 99)}.${FlxG.random.int(1, 99)}';
		});
		setFunction('getOption', function(saveStr:String):Dynamic {
			return Reflect.getProperty(ClientPrefs.data, saveStr);
		});
		setFunction('setOption', function(saveStr:String, value:Dynamic) {
			Reflect.setProperty(ClientPrefs.data, saveStr, value);
			ClientPrefs.saveSettings();
		});
		setFunction('getCurrentMod', function():String {
			return (modFolder != null) ? modFolder : '';
		});
		setFunction('assetExists', function(path:String):Bool {
			return lime.utils.Assets.exists(path);
		});
		setFunction('fileSystemExists', function(path:String):Bool {
			return FileSystem.exists(path);
		});
		setFunction('existsInMod', function(path:String, mod:String):Bool {
			return backend.Paths.fileExists(path, openfl.utils.AssetType.TEXT);
		});
		setFunction('getText', function(path:String):String {
			return backend.Paths.getTextFromFile(path);
		});
		setFunction('getContent', function(path:String):String {
			return sys.io.File.getContent(path);
		});
		setFunction('parseJson', function(tag:String, content:String) {
			luaSprites.set(tag, haxe.Json.parse(content));
		});
		setFunction('loadScript', function(script:String) {
			trace('[LE lua:' + scriptName + '] loadScript(' + script + '): 由 PlayState 的 callOnLeatherScripts 统一管理，跳过');
		});

		// --- math 全套（对照 LTS:3393-3563）---
		setFunction('bound', function(value:Float, ?Min:Float, ?Max:Float):Float {
			return FlxMath.bound(value, Min, Max);
		});
		setFunction('boundTo', function(value:Float, Min:Float, Max:Float):Float {
			return FlxMath.bound(value, Min, Max);
		});
		setFunction('distanceBetween', function(SpriteA:String, SpriteB:String):Float {
			var a:Dynamic = getActorByName(SpriteA);
			var b:Dynamic = getActorByName(SpriteB);
			return (a != null && b != null) ? FlxMath.distanceBetween(a, b) : 0;
		});
		setFunction('distanceToMouse', function(sprite:String):Float {
			var a:Dynamic = getActorByName(sprite);
			return (a != null) ? FlxMath.distanceToMouse(a) : 0;
		});
		setFunction('distanceToPoint', function(sprite:String, x:Float, y:Float):Float {
			var a:Dynamic = getActorByName(sprite);
			return (a != null) ? FlxMath.distanceToPoint(a, new flixel.math.FlxPoint(x, y)) : 0;
		});
		setFunction('dotProduct', function(ax:Float, ay:Float, bx:Float, by:Float):Float {
			return FlxMath.dotProduct(ax, ay, bx, by);
		});
		setFunction('equal', function(aValueA:Float, aValueB:Float, aDiff:Float = FlxMath.EPSILON):Bool {
			return FlxMath.equal(aValueA, aValueB, aDiff);
		});
		setFunction('fceil', function(n:Float):Int {
			return Math.ceil(n);
		});
		setFunction('ffloor', function(n:Float):Int {
			return Math.floor(n);
		});
		setFunction('fround', function(n:Float):Int {
			return Math.round(n);
		});
		setFunction('isFinite', function(n:Float):Bool {
			return Math.isFinite(n);
		});
		setFunction('isNaN', function(n:Float):Bool {
			return Math.isNaN(n);
		});
		setFunction('getDecimals', function(n:Float):Float {
			return FlxMath.getDecimals(n);
		});
		setFunction('inBounds', function(value:Float, min:Float, max:Float):Bool {
			return FlxMath.inBounds(value, min, max);
		});
		setFunction('isDistanceToMouseWithin', function(sprite:String, distance:Float, includeEqual:Bool = false):Bool {
			var a:Dynamic = getActorByName(sprite);
			return (a != null) ? FlxMath.isDistanceToMouseWithin(a, distance, includeEqual) : false;
		});
		setFunction('isDistanceToPointWithin', function(sprite:String, x:Float, y:Float, distance:Float, includeEqual:Bool = false):Bool {
			var a:Dynamic = getActorByName(sprite);
			return (a != null) ? FlxMath.isDistanceToPointWithin(a, new flixel.math.FlxPoint(x, y), distance, includeEqual) : false;
		});
		setFunction('isDistanceWithin', function(SpriteA:String, SpriteB:String, distance:Float, includeEqual:Bool = false):Bool {
			var a:Dynamic = getActorByName(SpriteA);
			var b:Dynamic = getActorByName(SpriteB);
			return (a != null && b != null) ? FlxMath.isDistanceWithin(a, b, distance, includeEqual) : false;
		});
		setFunction('isEven', function(n:Float):Bool {
			return FlxMath.isEven(n);
		});
		setFunction('isOdd', function(n:Float):Bool {
			return FlxMath.isOdd(n);
		});
		setFunction('lerp', function(a:Float, b:Float, ratio:Float):Float {
			return FlxMath.lerp(a, b, ratio);
		});
		setFunction('maxAdd', function(value:Int, amount:Int, max:Int, min:Int = 1):Int {
			return FlxMath.maxAdd(value, amount, max, min);
		});
		setFunction('maxInt', function(a:Int, b:Int):Int {
			return FlxMath.maxInt(a, b);
		});
		setFunction('minInt', function(a:Int, b:Int):Int {
			return FlxMath.minInt(a, b);
		});
		setFunction('numericComparison', function(a:Float, b:Float):Float {
			return FlxMath.numericComparison(a, b);
		});
		setFunction('perlin', function(x:Float, y:Float, z:Float):Float {
			return 0; // Psych 无 perlin 库，占位
		});
		setFunction('pointInCoordinates', function(pointX:Float, pointY:Float, rectX:Float, rectY:Float, rectWidth:Float, rectHeight:Float):Bool {
			return FlxMath.pointInCoordinates(pointX, pointY, rectX, rectY, rectWidth, rectHeight);
		});
		setFunction('random', function():Float {
			return Math.random();
		});
		setFunction('randomBool', function(chance:Float):Bool {
			return FlxG.random.bool(chance);
		});
		setFunction('randomFloat', function(min:Float, max:Float):Float {
			return FlxG.random.float(min, max);
		});
		setFunction('randomInt', function(min:Int, max:Int):Int {
			return FlxG.random.int(min, max);
		});
		setFunction('remapToRange', function(value:Float, start1:Float, stop1:Float, start2:Float, stop2:Float):Float {
			return FlxMath.remapToRange(value, start1, stop1, start2, stop2);
		});
		setFunction('round', function(v:Float):Float {
			return Math.round(v);
		});
		setFunction('roundDecimal', function(value:Float, precision:Int):Float {
			return FlxMath.roundDecimal(value, precision);
		});
		setFunction('sameSign', function(a:Float, b:Float):Bool {
			return FlxMath.sameSign(a, b);
		});
		setFunction('signOf', function(n:Float):Int {
			return FlxMath.signOf(n);
		});
		setFunction('sinh', function(n:Float):Float {
			return FlxMath.sinh(n);
		});
		setFunction('vectorLength', function(dx:Float, dy:Float):Float {
			return FlxMath.vectorLength(dx, dy);
		});
		setFunction('wrap', function(value:Int, min:Int, max:Int):Int {
			return FlxMath.wrap(value, min, max);
		});

		// --- 窗口控制（对照 LTS:2045-2090）---
		setFunction('setWindowPos', function(x:Int, y:Int) {
			if (FlxG.stage != null && FlxG.stage.window != null) FlxG.stage.window.x = x;
			if (FlxG.stage != null && FlxG.stage.window != null) FlxG.stage.window.y = y;
		});
		setFunction('getWindowX', function():Int {
			return (FlxG.stage != null && FlxG.stage.window != null) ? FlxG.stage.window.x : 0;
		});
		setFunction('getWindowY', function():Int {
			return (FlxG.stage != null && FlxG.stage.window != null) ? FlxG.stage.window.y : 0;
		});
		setFunction('getCenteredWindowX', function():Int {
			return (FlxG.stage != null && FlxG.stage.window != null) ? Std.int((FlxG.stage.window.display.currentMode.width - FlxG.stage.window.width) / 2) : 0;
		});
		setFunction('getCenteredWindowY', function():Int {
			return (FlxG.stage != null && FlxG.stage.window != null) ? Std.int((FlxG.stage.window.display.currentMode.height - FlxG.stage.window.height) / 2) : 0;
		});
		setFunction('resizeWindow', function(Width:Int, Height:Int) {
			if (FlxG.stage != null && FlxG.stage.window != null) FlxG.stage.window.resize(Width, Height);
		});
		setFunction('getScreenWidth', function():Int {
			return (FlxG.stage != null && FlxG.stage.window != null) ? FlxG.stage.window.display.currentMode.width : FlxG.width;
		});
		setFunction('getScreenHeight', function():Int {
			return (FlxG.stage != null && FlxG.stage.window != null) ? FlxG.stage.window.display.currentMode.height : FlxG.height;
		});
		setFunction('getWindowWidth', function():Int {
			return (FlxG.stage != null && FlxG.stage.window != null) ? FlxG.stage.window.width : FlxG.width;
		});
		setFunction('getWindowHeight', function():Int {
			return (FlxG.stage != null && FlxG.stage.window != null) ? FlxG.stage.window.height : FlxG.height;
		});
		setFunction('setCanFullscreen', function(can_Fullscreen:Bool) {
			if (FlxG.stage != null && FlxG.stage.window != null) FlxG.stage.window.fullscreen = can_Fullscreen;
		});

		// ===== 批次 3：trail / reflection / health / note speed / song position / shader 补充（对照 LTS LuaScript.hx）=====

		// addActorTrail/removeActorTrail（LTS:965-986，用 flixel-addons FlxTrail 挂在 actor 下一层）
		setFunction('addActorTrail', function(id:String, length:Int = 10, delay:Int = 3, alpha:Float = 0.4, diff:Float = 0.05) {
			var ps:PlayState = PlayState.instance;
			var actor:Dynamic = getActorByName(id);
			if (ps == null || actor == null || trails.exists(id)) return;
			var trail:FlxTrail = new FlxTrail(actor, null, length, delay, alpha, diff);
			ps.insert(ps.members.indexOf(actor) - 1, trail);
			trails.set(id, trail);
		});
		setFunction('removeActorTrail', function(id:String) {
			var ps:PlayState = PlayState.instance;
			if (ps == null || !trails.exists(id)) return;
			ps.remove(trails.get(id));
			trails.get(id).destroy();
			trails.remove(id);
		});
		// setActorTrailVisible/getActorTrailVisible（LTS:1897-1925，作用于角色 coolTrail；Kathy Character 无 coolTrail 字段，用 Reflect 兜底）
		setFunction('setActorTrailVisible', function(id:String, visibleVal:Bool):Bool {
			var actor:Dynamic = getActorByName(id);
			if (actor != null && Reflect.hasField(actor, 'coolTrail') && Reflect.field(actor, 'coolTrail') != null)
			{
				Reflect.field(actor, 'coolTrail').visible = visibleVal;
				return true;
			}
			return false;
		});
		setFunction('getActorTrailVisible', function(id:String):Bool {
			var actor:Dynamic = getActorByName(id);
			if (actor != null && Reflect.hasField(actor, 'coolTrail') && Reflect.field(actor, 'coolTrail') != null)
				return Reflect.field(actor, 'coolTrail').visible;
			return false;
		});
		// addCharacterToMap（LTS:424-445，LE 的 dadMap/gfMap/bfMap 多角色表；Kathy 无此系统，注册进 luaCharacters 供 getActorByName 使用）
		setFunction('addCharacterToMap', function(m:String, character:String) {
			var ps:PlayState = PlayState.instance;
			if (ps == null) return;
			var ch:Character = new Character(100, 100, character);
			ch.alpha = 0.00001;
			ps.add(ch);
			luaCharacters.set(character, ch);
		});
		// createCustomShader（LTS:3090-3095；Kathy 无 Psych 的 backend.CustomShader 体系，占位）
		setFunction('createCustomShader', function(id:String, frag:String, ?vert:String) {
			trace('[LE lua:' + scriptName + '] createCustomShader: 未移植（Kathy 无 CustomShader 体系）');
		});
		// exists（LTS:591-598）
		setFunction('exists', function(id:String):Bool {
			var actor:Dynamic = getActorByName(id);
			return actor != null && Reflect.getProperty(actor, 'exists') == true;
		});
		// getMinHealth/getMaxHealth（LTS:1033-1040；Kathy PlayState.maxHealth 为私有且无 minHealth → Reflect 兜底）
		setFunction('getMinHealth', function():Float {
			var ps:PlayState = PlayState.instance;
			return ps != null && Reflect.hasField(ps, 'minHealth') ? Reflect.field(ps, 'minHealth') : 0;
		});
		setFunction('getMaxHealth', function():Float {
			var ps:PlayState = PlayState.instance;
			return ps != null && Reflect.hasField(ps, 'maxHealth') ? Reflect.field(ps, 'maxHealth') : 2;
		});
		// getRenderedNoteSpeed / setUnspawnNoteSpeed / getUnspawnNoteSpeed（LTS:1509-1521；Kathy Note 的速度字段为 multSpeed）
		setFunction('getRenderedNoteSpeed', function(id:Int):Float {
			var n:Note = getRenderedNoteAt(id);
			return n != null ? n.multSpeed : 0;
		});
		setFunction('setUnspawnNoteSpeed', function(speed:Float, id:Int) {
			var n:Note = getUnspawnedNoteAt(id);
			if (n != null) n.multSpeed = speed;
		});
		setFunction('getUnspawnNoteSpeed', function(id:Int):Float {
			var n:Note = getUnspawnedNoteAt(id);
			return n != null ? n.multSpeed : 0;
		});
		// getSongPosition（LTS:2945-2948）
		setFunction('getSongPosition', function():Float {
			return Conductor.songPosition;
		});
		// setActorReflection 系（LTS:2000-2044；flixel 5.9 的 FlxSprite 无 reflection 字段，仅当字段存在时写入）
		function setActorReflectionProp(id:String, prop:String, value:Dynamic):Void {
			var actor:Dynamic = getActorByName(id);
			if (actor == null) return;
			if (Reflect.hasField(actor, prop)) Reflect.setProperty(actor, prop, value);
		}
		setFunction('setActorReflection', function(id:String, r:Bool) {
			setActorReflectionProp(id, 'drawReflection', r);
		});
		setFunction('setActorReflectionYOffset', function(id:String, y:Float) {
			setActorReflectionProp(id, 'reflectionYOffset', y);
		});
		setFunction('setActorReflectionAlpha', function(id:String, a:Float) {
			setActorReflectionProp(id, 'reflectionAlpha', a);
		});
		setFunction('setActorReflectionColor', function(id:String, color:String) {
			setActorReflectionProp(id, 'reflectionColor', FlxColor.fromString(color));
		});

		// ===== MODCHARTING_TOOLS 专属块（LTS:3565-3609，依赖 ModchartFuncs/playfieldRenderer，Kathy 无此系统，占位防 nil 调用）=====
		function modchartToolsStub(name:String):Void {
			trace('[LE lua:' + scriptName + '] ' + name + ': 未移植（Kathy 无 MODCHARTING_TOOLS 系统）');
		}
		setFunction('startMod', function(name:String, modClass:String, type:String = '', pf:Int = -1) { modchartToolsStub('startMod'); });
		setFunction('setMod', function(name:String, value:Float) { modchartToolsStub('setMod'); });
		setFunction('setSubMod', function(name:String, subValName:String, value:Float) { modchartToolsStub('setSubMod'); });
		setFunction('setModTargetLane', function(name:String, value:Int) { modchartToolsStub('setModTargetLane'); });
		setFunction('setModPlayfield', function(name:String, value:Int) { modchartToolsStub('setModPlayfield'); });
		setFunction('addPlayfield', function(?x:Float = 0, ?y:Float = 0, ?z:Float = 0) { modchartToolsStub('addPlayfield'); });
		setFunction('removePlayfield', function(idx:Int) { modchartToolsStub('removePlayfield'); });
		setFunction('tweenModifier', function(modifier:String, val:Float, time:Float, ease:String) { modchartToolsStub('tweenModifier'); });
		setFunction('tweenModifierSubValue', function(modifier:String, subValue:String, val:Float, time:Float, ease:String) { modchartToolsStub('tweenModifierSubValue'); });
		setFunction('setModEaseFunc', function(name:String, ease:String) { modchartToolsStub('setModEaseFunc'); });
		setFunction('setModifier', function(beat:Float, argsAsString:String) { modchartToolsStub('setModifier'); });
		setFunction('easeModifier', function(beat:Float, time:Float, easeStr:String, argsAsString:String) { modchartToolsStub('easeModifier'); });
		setFunction('ease', function(beat:Float, time:Float, easeStr:String, argsAsString:String) { modchartToolsStub('ease'); });

		// ===== 版本分支：official 模式下注销 LTS 独有函数 =====
		// 数据来源（本文件 API 全集 = LTS 1.1.9 LuaScript.hx 370 个 setFunction + MODCHARTING_TOOLS 占位）：
		//   Official 0.5.0 ModchartUtilities.hx 212 个 setLuaFunction；
		//   公共函数 199 个；LTS 独有 171 个（下方清单）。
		// 语义：leatherScriptCompat = official → 只保留 Official 0.5.0 的函数（公共 199 + MODCHARTING_TOOLS 占位 13），
		//       LTS 独有函数在 Lua 层置 nil（脚本调用时报 "attempt to call a nil value"，与原版行为一致）；
		//       lts / auto(LEATHER LTS) → 保留全集。auto(LEATHER) 由 resolveVersion 归为 official，同样走本分支。
		if (apiVersion == 'official')
		{
			var ltsOnly:Array<String> = [
			'actorScreenCenter', 'addCharacterToMap', 'arrayToCSV', 'assetExists', 'bound', 'boundTo', 'cancelTweensOf', 'createCustomShader',
			'distanceBetween', 'distanceToMouse', 'distanceToPoint', 'dominantColor', 'dominantColorFrame', 'dotProduct', 'equal', 'existsInMod',
			'fadeCamera', 'fceil', 'ffloor', 'fileSystemExists', 'filterDigits', 'formatArray', 'formatBytes', 'formatTime',
			'fround', 'getActorFlipX', 'getActorFlipY', 'getCameraScrollX', 'getCameraScrollY', 'getClassName', 'getContent', 'getCurrentMod',
			'getCustomShaderBool', 'getCustomShaderFloat', 'getCustomShaderInt', 'getDecimals', 'getNoteProperty', 'getOption', 'getRenderedNoteAffectedByColor', 'getRenderedNoteArrowType',
			'getRenderedNoteColor', 'getRenderedNoteData', 'getRenderedNoteOffsetX', 'getRenderedNoteOffsetY', 'getRenderedNotePrevNoteStrumtime', 'getRenderedNoteScaleY', 'getRenderedNoteSkewX', 'getRenderedNoteSkewY',
			'getRenderedNoteSpeed', 'getRenderedNoteSustainScaleY', 'getSingDirectionAnim', 'getSingDirectionID', 'getSongPosition', 'getStrumTimeFromStep', 'getText', 'getUnspawnNoteSpeed',
			'getUnspawnNotes', 'getUnspawnedNoteAffectedByColor', 'getUnspawnedNoteArrowType', 'getUnspawnedNoteColor', 'getUnspawnedNoteData', 'getUnspawnedNoteMustPress', 'getUnspawnedNoteNoteData', 'getUnspawnedNoteNoteType',
			'getUnspawnedNoteScaleX', 'getUnspawnedNoteScaleY', 'getUnspawnedNoteSingAnimPrefix', 'getUnspawnedNoteSingAnimSuffix', 'getUnspawnedNoteStrumtime', 'getUnspawnedNoteSustainNote', 'getUnspawnedNoteType', 'inBounds',
			'initShader', 'isDistanceToMouseWithin', 'isDistanceToPointWithin', 'isDistanceWithin', 'isEven', 'isFinite', 'isNaN', 'isOdd',
			'isRenderedNoteSustainEnd', 'justPressed', 'justPressedDodgeKey', 'justReleased', 'lerp', 'makeCamera', 'makeGraphicRGB', 'makeNoteCopy',
			'makeSpriteCopy', 'maxAdd', 'maxInt', 'minInt', 'newSpriteCopy', 'numericComparison', 'parseJson', 'pauseSound',
			'pauseTweensOf', 'perlin', 'pointInCoordinates', 'pressed', 'print', 'pushShaderToCamera', 'random', 'remapToRange',
			'removeCameraShader', 'resumeSound', 'resumeTweensOf', 'rgbToHsv', 'round', 'roundDecimal', 'sameSign', 'setActorColorRGB',
			'setActorCustomShader', 'setActorFont', 'setActorNoCustomShader', 'setActorOriginX', 'setActorOriginY', 'setActorOutlineColor', 'setActorProperty', 'setActorReflection',
			'setActorReflectionAlpha', 'setActorReflectionColor', 'setActorReflectionYOffset', 'setActorShader', 'setCameraCustomShader', 'setCameraNoCustomShader', 'setCameraShader', 'setCharacterPlayFullAnim',
			'setCharacterPreventDanceForAnim', 'setCharacterSingPrefix', 'setCustomShaderBool', 'setCustomShaderFloat', 'setCustomShaderInt', 'setNoteCameras', 'setObjectCameras', 'setOption',
			'setRenderedNoteColor', 'setRenderedNoteColorForce', 'setRenderedNoteScaleX', 'setRenderedNoteScaleY', 'setRenderedNoteSkewX', 'setRenderedNoteSkewY', 'setRenderedNoteSpeed', 'setShaderProperty',
			'setStageColorSwap', 'setStrumlineX', 'setTextBorderStyle', 'setUnspawnNoteSpeed', 'setUnspawnedNoteAngle', 'setUnspawnedNoteColor', 'setUnspawnedNoteColorForce', 'setUnspawnedNoteSingAnimPrefix',
			'setUnspawnedNoteSingAnimSuffix', 'setUnspawnedNoteXOffset', 'setUnspawnedNoteYOffset', 'signOf', 'sinh', 'stopFlash', 'trace', 'tweenActorProperty',
			'tweenCancel', 'tweenFadeCubeInOut', 'tweenPause', 'tweenResume', 'tweenScaleX', 'tweenScaleY', 'tweenShader', 'tweenShaderProperty',
			'tweenStageColorSwap', 'vectorLength', 'wrap'
			];
			for (n in ltsOnly)
			{
				Lua.pushnil(lua);
				Lua.setglobal(lua, n);
			}
			trace('[LE lua:' + scriptName + '] API 版本=official，已注销 ' + ltsOnly.length + ' 个 LTS 独有函数');
		}
		else
			trace('[LE lua:' + scriptName + '] API 版本=lts，注册全集 ' + 384 + ' 个函数');
	}

	/**
	 * 注册一个 lua 全局（变量或回调函数）。
	 * 对照 LTS: set(name, value) -> Convert.toLua + Lua.setglobal
	 */
	public function set(name:String, value:Dynamic):Void
	{
		if (lua == null) return;
		Convert.toLua(lua, value);
		Lua.setglobal(lua, name);
	}

	/**
	 * 注册一个 lua 回调函数。
	 * 对照 LTS: Lua_helper.add_callback(lua, name, func)
	 */
	public function setFunction(name:String, func:Dynamic):Void
	{
		if (lua == null) return;
		Lua_helper.add_callback(lua, name, func);
	}

	/**
	 * 调用脚本里的某个函数（事件广播入口）。
	 * 对照 LTS: call(func, arguments)；实现参考 Psych FunkinLua.call：
	 * getglobal → 类型校验 → Convert.toLua 压参 → pcall → 取返回值。
	 * @return 脚本返回值（无返回时为 null；Lua 层抛错返回 null 并 trace 错误）
	 */
	public function call(func:String, ?arguments:Array<Dynamic>):Dynamic
	{
		if (lua == null || closed) return null;
		if (arguments == null) arguments = [];

		try
		{
			Lua.getglobal(lua, func);
			var ftype:Int = Lua.type(lua, -1);
			if (ftype != Lua.LUA_TFUNCTION)
			{
				Lua.pop(lua, 1);
				return null;
			}

			for (arg in arguments)
				Convert.toLua(lua, arg);
			var status:Int = Lua.pcall(lua, arguments.length, 1, 0);

			if (status != Lua.LUA_OK)
			{
				var err:Dynamic = Lua.tostring(lua, -1);
				trace('[LE lua:${scriptName}] ERROR ($func): ' + Std.string(err));
				Lua.pop(lua, 1);
				return null;
			}

			var result:Dynamic = cast Convert.fromLua(lua, -1);
			Lua.pop(lua, 1);
			return result;
		}
		catch (e:Dynamic)
		{
			trace('[LE lua:${scriptName}] call($func) threw: ' + Std.string(e));
			return null;
		}
	}

	/** 判断脚本是否实现了某函数（事件广播前置探测，对照 FunkinLua.probeFunc）。 */
	public function exists(func:String):Bool
	{
		if (lua == null) return false;
		Lua.getglobal(lua, func);
		var ok:Bool = (Lua.type(lua, -1) == Lua.LUA_TFUNCTION);
		Lua.pop(lua, 1);
		return ok;
	}

	// ============================================================
	// 批次 2 辅助方法（tween / 音符索引 / ease）
	// ============================================================

	/** ease 字符串解析（对照 LTS CoolUtil.easeFromString；Psych 侧同名函数已存在）。 */
	function easeFromString(ease:String):Dynamic
	{
		if (ease == null || ease == '') return FlxEase.linear;
		return switch (ease.toLowerCase().replace(' ', ''))
		{
			case 'linear': FlxEase.linear;
			case 'cubein' | 'cubicin': FlxEase.cubeIn;
			case 'cubeout' | 'cubicout': FlxEase.cubeOut;
			case 'cubeinout' | 'cubicinout': FlxEase.cubeInOut;
			case 'sinein': FlxEase.sineIn;
			case 'sineout': FlxEase.sineOut;
			case 'sineinout': FlxEase.sineInOut;
			case 'quadin': FlxEase.quadIn;
			case 'quadout': FlxEase.quadOut;
			case 'quadinout': FlxEase.quadInOut;
			case 'quartin': FlxEase.quartIn;
			case 'quartout': FlxEase.quartOut;
			case 'quartinout': FlxEase.quartInOut;
			case 'quintin': FlxEase.quintIn;
			case 'quintout': FlxEase.quintOut;
			case 'quintinout': FlxEase.quintInOut;
			case 'expoin': FlxEase.expoIn;
			case 'expoout': FlxEase.expoOut;
			case 'expoinout': FlxEase.expoInOut;
			case 'backin': FlxEase.backIn;
			case 'backout': FlxEase.backOut;
			case 'backinout': FlxEase.backInOut;
			case 'bouncein': FlxEase.bounceIn;
			case 'bounceout': FlxEase.bounceOut;
			case 'bounceinout': FlxEase.bounceInOut;
			case 'circin': FlxEase.circIn;
			case 'circout': FlxEase.circOut;
			case 'circinout': FlxEase.circInOut;
			case 'elasticin': FlxEase.elasticIn;
			case 'elasticout': FlxEase.elasticOut;
			case 'elasticinout': FlxEase.elasticInOut;
			default: FlxEase.linear;
		};
	}

	/** 通用 tween（对照 LTS tween() 内部实现）。onComplete 为脚本函数名，完成后 call 之。 */
	function doTween(obj:Dynamic, props:Dynamic, time:Float, ?onComplete:String = '', ?ease:String = 'linear', ?startDelay:Float = 0):FlxTween
	{
		if (obj == null) return null;
		var key:String = 'leTween' + (tweenCount++);
		var tween:FlxTween = FlxTween.tween(obj, props, time, {
			ease: easeFromString(ease),
			startDelay: startDelay,
			onComplete: function(t:FlxTween)
			{
				luaTweens.remove(key);
				if (onComplete != null && onComplete != '') call(onComplete, [t]);
			}
		});
		luaTweens.set(key, tween);
		return tween;
	}

	/** 取渲染中的音符（对照 LTS getRenderedNotes：PlayState.notes.members）。 */
	function getRenderedNoteAt(idx:Int):Note
	{
		var ps:PlayState = PlayState.instance;
		if (ps == null || ps.notes == null || idx < 0 || idx >= ps.notes.length) return null;
		return ps.notes.members[idx];
	}

	/** 取未生成的音符（对照 LTS getUnspawnNotes：PlayState.unspawnNotes）。 */
	function getUnspawnedNoteAt(idx:Int):Note
	{
		var ps:PlayState = PlayState.instance;
		if (ps == null || ps.unspawnNotes == null || idx < 0 || idx >= ps.unspawnNotes.length) return null;
		return ps.unspawnNotes[idx];
	}

	/** 销毁（对照 LTS: destroy()，清理注册表）。 */
	public function destroy():Void
	{
		closed = true;
		luaCharacters.clear();
		luaSprites.clear();
		luaSounds.clear();
		luaTweens.clear();
		trails.clear();
		lua = null;
	}
}
#end
