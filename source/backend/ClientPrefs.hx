package backend;

import flixel.util.FlxSave;
import flixel.input.keyboard.FlxKey;
import flixel.input.gamepad.FlxGamepadInputID;

import states.TitleState;
import states.MainMenuState;
import openfl.display.StageQuality;

import haxe.Json;
import haxe.io.Bytes;
import haxe.io.BytesOutput;
import haxe.io.BytesInput;

// Add a variable here and it will get automatically saved
@:structInit class SaveVariables {
	// Mobile and Mobile Controls Releated
	public var extraButtons:String = "0"; // mobile extra button option (count: 0-4)
	public var extraKeyReturn1:String = 'SPACE'; // 额外键1绑定到的虚拟控制键名
	public var extraKeyReturn2:String = 'SPACE'; // 额外键2绑定到的虚拟控制键名
	public var extraKeyReturn3:String = 'SHIFT'; // 额外键3绑定到的虚拟控制键名
	public var extraKeyReturn4:String = 'SHIFT'; // 额外键4绑定到的虚拟控制键名
	public var hitboxPos:Bool = true; // hitbox extra button position option
	public var dynamicColors:Bool = true; // yes cause its cool -Karim
	public var controlsAlpha:Float = FlxG.onMobile ? 0.6 : 0;
	public var screensaver:Bool = false;
	public var wideScreen:Bool = false;
	public var hitboxType:String = "Gradient";
	public var hitboxAnimation:Bool = true; // whether hitbox button animations are enabled
	public var hitboxHideIdle:Bool = true; // hide the colored hitbox blocks while not being touched
	public var popUpRating:Bool = true;
	//public var vsync:Bool = false;
	public var gameOverVibration:Bool = false;
	public var mobileJudgmentCompensation:Bool = FlxG.onMobile; // 移动端判定补偿（触屏自动加偏移）
	public var mobileJudgmentOffset:Float = 10.0; // 移动端补偿量（ms）
	public var fpsRework:Bool = false;
	
	public var downScroll:Bool = false;
	public var middleScroll:Bool = false;
	public var opponentStrums:Bool = true;
	public var laneCoverAlphaP1:Float = 0.0; // 玩家轨道阴影覆盖层透明度（0=关闭，1=最暗）
	public var laneCoverAlphaP2:Float = 0.0; // 对手轨道阴影覆盖层透明度（0=关闭，1=最暗）
	public var laneCoverByStrumAlpha:Bool = false; // 覆盖层透明度是否基于箭头当前 alpha 叠加（乘算）
	public var showFPS:Bool = true;
	// 图片资源加载失败时，在屏幕角落显示「红色警告三角 + flixel默认图标 + 失败资源路径」的提示卡
	public var assetErrorOverlay:Bool = true;
	public var flashing:Bool = true;
	public var autoPause:Bool = false;
	public var gcOnResume:Bool = true;
	public var antialiasing:Bool = true;
	public var threeIcons:Bool = false; // 三态图标（正常 / 输 / 赢）：开启后图标图片按宽矩形横向均分为 3 个状态
	public var noteSkin:String = 'Default';
	public var splashSkin:String = 'Psych';
	public var holdCoverSkin:String = 'Default'; // Hold Cover 皮肤（后缀，如 -Psych），Default 表示使用默认 holdCover{Color} 素材
	public var splashAlpha:Float = 0.6;
	public var splashLimitEnabled:Bool = true; // 是否启用飞溅数量限制
	public var splashLimit:Int = 16; // 飞溅最大同时存在数量（默认16）
	public var splashLimitMode:String = 'skip'; // 飞溅超限处理模式：'skip' = 达到上限则忽略本次（现状）；'replace' = 达到上限则销毁最早生成的那个飞溅再生成新飞溅
	public var holdCoverLimitEnabled:Bool = true; // 是否启用 Hold Cover 数量限制
	public var holdCoverLimit:Int = 10; // Hold Cover 最大同时显示数量（默认10）
	public var lowQuality:Bool = false;
	public var shaders:Bool = true;
	public var cacheOnGPU:Bool = #if !switch false #else true #end; // GPU Caching made by Raltyro
	public var playStatePixelPerfect:Bool = true; // 游戏内所有相机是否启用 pixelPerfectRender（关闭可显著改善全屏/高分辨率滚动性能）
	public var framerate:Int = 60;
	public var camZooms:Bool = true;
	public var stageQuality:String = 'MEDIUM'; // 矢量/文本渲染质量(StageQuality)：LOW/MEDIUM/HIGH/BEST，移动端建议 MEDIUM 及以下
	public var loadingThreadCount:Int = 2; // 进入歌曲时资源加载的线程数（1=单线程，越大并行越高但更耗内存/可能触发OOM）
	public var hideHud:Bool = false;
	public var noteOffset:Int = 0;
	public var arrowRGB:Array<Array<FlxColor>> = [
		[0xFFC24B99, 0xFFFFFFFF, 0xFF3C1F56],
		[0xFF00FFFF, 0xFFFFFFFF, 0xFF1542B7],
		[0xFF12FA05, 0xFFFFFFFF, 0xFF0A4447],
		[0xFFF9393F, 0xFFFFFFFF, 0xFF651038]];
	public var arrowRGBPixel:Array<Array<FlxColor>> = [
		[0xFFE276FF, 0xFFFFF9FF, 0xFF60008D],
		[0xFF3DCAFF, 0xFFF4FFFF, 0xFF003060],
		[0xFF71E300, 0xFFF6FFE6, 0xFF003100],
		[0xFFFF884E, 0xFFFFFAF5, 0xFF6C0000]];

	// Arrow color rendering mode: 'RGB' (new palette) or 'HSV' (legacy Psych v0.6.3 hue/sat/brightness shift)
	public var arrowColorMode:String = 'RGB';
	// Legacy HSV arrow colors (one [hue, saturation, brightness] per direction, integers).
	// Range: hue -180..180, saturation/brightness -100..100. All 0 = no shift (texture renders as-is).
	public var arrowHSV:Array<Array<Int>> = [[0, 0, 0], [0, 0, 0], [0, 0, 0], [0, 0, 0]];

	// Ghost Tapping 模式 —— 控制"空按箭头"惩罚的触发时机：
	//   'always'       — 始终允许：空按永不惩罚
	//   'whenSinging'  — 唱歌时启用惩罚（FPS Plus + Funkin 原版）：玩家判定窗口有音符时空按惩罚，无音符时空按不惩罚，集成 375ms 冷却期防连按
	//   'whenNotSinging' — 唱歌时禁用惩罚（反向）：玩家判定窗口无音符时空按惩罚，有音符时空按不惩罚
	//   'off'          — 完全禁用：空按总是触发完整 miss 惩罚（noteMissPress）
	public var ghostTappingMode:String = 'always';

	// Bool 兼容层（真实字段，FlxSave 可反射）—— 供旧模组/脚本调用：
	//   读取：ghostTappingMode != 'off'
	//   写入 true  → ghostTappingMode='always'
	//   写入 false → ghostTappingMode='off'
	// 注意：主逻辑一律读 ghostTappingMode，此 Bool 仅为模组兼容
	public var ghostTapping:Bool = true;
	public var preciseHit:Bool = true; // 毫秒级精确判定：按键瞬间用音频时钟同步 songPosition，并实时计算判定窗口（替代上一帧缓存的 canBeHit）

	// ===== 低延迟 / 性能模式 =====
	// 自动重同步：弱机卡顿时，引擎会检测音频与逻辑不同步并跳回正确位置。关闭后不会“倒带”，改由玩家手动校准。
	public var autoResync:Bool = true;
	// 帧自适应同步：根据目标帧率动态调整 songPosition 向音频时钟的收敛速度，低帧时更平滑、高帧时更跟手。
	public var useFrameAdaptiveSync:Bool = false;
	// 同步速度倍率（仅 useFrameAdaptiveSync 启用时生效），范围 0.1 ~ 10，默认 1.0。
	public var syncSpeedMultiplier:Float = 1.0;
	// 提前剔除已错过音符的渲染：已错过且离开屏幕（或到达极晚阈值）的音符不再参与绘制，降低 SPAM 谱渲染负担。
	public var hideMissedNotes:Bool = true;

	// ===== 高密度谱面（SPAM）性能优化 =====
	// 每帧生成预算：单帧内最多新建多少个音符精灵，0 = 不限制（保持原行为）。
	// 卡顿恢复后积压的大量音符不会在同一帧被一次性创建成几百个精灵（避免“死亡螺旋”），
	// 而是分摊到随后的若干帧生成；音符只是延后一两帧出现，绝不会丢失。
	public var maxNotesPerFrame:Int = 0;
	// 过期音符即时结算：生成时若某音符早已越过 noteKillOffset（正常也必定判 miss），
	// 直接结算而不加入渲染组、不参与逐帧绘制与物理。复用既有阈值，判定语义零偏差。
	public var instantResolveExpired:Bool = true;
	// 关闭逐音符脚本回调：跳过 onSpawnNote / goodNoteHit(Pre) / noteMiss / opponentNoteHit(Pre)
	// 的 Lua/HScript 调用。密集谱下这些逐音符调用开销巨大。⚠ 会使依赖这些回调的 modchart 失效，默认关闭。
	public var disableNoteLua:Bool = false;

	// ===== 综合音符性能优化总开关 =====
	// 控制不影响对象生命周期的优化（容器 push 替代 insert(0)、PreloadedChartNote 原生 class、
	// 皮肤缓存统一清理、cos/sin 缓存、notesHitArray 改用 Timer.stamp、Lua 热路径去 indexOf）。
	// 这些改动不改变 Note 实例生命周期，脚本安全。关闭则全量回退。默认开启。
	public var noteOptimization:Bool = true;

	// ===== 对象池开关 =====
	// 开启后按 (noteData) 分桶复用普通音符实例，消除每秒数十~数百次 new/destroy 的 GC 停顿。
	// ⚠ 风险：复用的 Note 实例对脚本而言不再是“每个都是全新对象”。若谱面/modchart 的
	// onSpawnNote / goodNoteHit / noteMiss 回调保存了 Note 对象引用并跨 spawn 访问其字段，
	// 可能读到被复用的脏数据。默认关闭；仅在你确认所用脚本不依赖音符对象持久引用时开启。
	public var notePooling:Bool = false;

	// 脚本回调 index 参数归一化：开启后用稳定生成序号 preloadIndex 替代 notes.members.indexOf()，
	// 消除脚本激活时每次命中/生成的全数组 O(n) 扫描（SPAM 谱 + 脚本 mod 掉的明显 CPU 源）。
	// ⚠ 开启后脚本回调里的 index 将读到"生成序号"而非"notes 当前数组位置"，若某 modchart 依赖后者请保持关闭。
	// 默认关闭 = 沿用 indexOf 语义，与 Psych 原版回调行为完全一致，保证既有模组兼容性。
	public var luaNoteIndexPerf:Bool = false;

	// ===== 帧末批量 compact =====
	// 开启后音符销毁不再即时 splice（改为标记 exists=false，在 update 末尾一次单遍紧凑 notes/normalNotes/holdNotes），
	// 把 SPAM 高密度谱下每颗销毁 3 次 O(n) 左移降为一帧一次的 O(n)，是销毁路径的主要 CPU 优化。
	// ⚠ 代价：脚本在“命中/错过后同一帧内”观察 notes.length 会看到比实际多一帧的延迟；若某 modchart 依赖
	// 即时缩容，请关闭（关闭即回退原“销毁即 splice”行为，对脚本实时生效）。默认开启。
	public var batchCompactNotes:Bool = true;

	public var timeBarType:String = 'Time Left';
	public var scoreZoom:Bool = true;
	public var noReset:Bool = false;
	public var healthBarAlpha:Float = 1;
	public var hitsoundVolume:Float = 0;
	public var hitsound:String = 'none';
	// 打击音随判定偏移变调：开启后命中音高随命中时机偏移（偏早=更高，偏晚=更低）
	public var hitsoundPitchOffset:Bool = false;
	// 变调强度：命中窗口边缘处相对基础音高的偏移比例（如 0.25 = ±25% 音高）
	public var hitsoundPitchRange:Float = 0.25;
	// 打击音对象池：复用 FlxSound 实例播放 hitsound/missnote，降低高密度谱的分配与 GC 卡顿
	public var hitSoundPoolEnabled:Bool = true;
	// 对象池大小：高密度谱连打时同时响起的打击音数量上限
	public var hitSoundPoolSize:Int = 50;
	public var pauseMusic:String = 'Tea Time';
	// 主菜单音乐：'Default' 使用标准 freakyMenu；其它值对应 assets/music/freakyMenu-<选项名>.<SOUND_EXT>（文件需自备）
	public var daMenuMusic:String = 'Default';
	// 画面每拍缩放特效（标题界面 3%，主界面 1.5%）：true=开启，false=关闭
	public var beatScale:Bool = true;
	public var checkForUpdates:Bool = true;
	public var receiveBetaBuilds:Bool = false; // 更新检查是否包含测试版（Pre-release）构建：关闭时只检查正式版
	public var disableNetworking:Bool = false; // 全局联网开关：true 时拦截所有联网行为
	public var comboStacking:Bool = true;
	public var gameplaySettings:Map<String, Dynamic> = [
		'scrollspeed' => 1.0,
		'scrolltype' => 'multiplicative', 
		// anyone reading this, amod is multiplicative speed mod, cmod is constant speed mod, and xmod is bpm based speed mod.
		// an amod example would be chartSpeed * multiplier
		// cmod would just be constantSpeed = chartSpeed
		// and xmod basically works by basing the speed on the bpm.
		// iirc (beatsPerSecond * (conductorToNoteDifference / 1000)) * noteSize (110 or something like that depending on it, prolly just use note.height)
		// bps is calculated by bpm / 60
		// oh yeah and you'd have to actually convert the difference to seconds which I already do, because this is based on beats and stuff. but it should work
		// just fine. but I wont implement it because I don't know how you handle sustains and other stuff like that.
		// oh yeah when you calculate the bps divide it by the songSpeed or rate because it wont scroll correctly when speeds exist.
		// -kade
		'songspeed' => 1.0,
		'healthgain' => 1.0,
		'healthloss' => 1.0,
		'instakill' => false,
		'practice' => false,
		'botplay' => false,
		'playOpponent' => false,
		'healthmodel' => 'default',        // 血量模型：'default'=原生 Psych，'kade'=Kade 固定加减血规则，'leather'=Leather 判定加减血规则
		'antiMash' => false,              // Leather 血量模型专属：开启时 shit 判定扣血，用于反连打
	];

	public var comboOffset:Array<Int> = [0, 0, 0, 0, 0, 0, 0, 0]; // [0,1]评级 [2,3]combo数字(combo字样共用) [4,5]额外的EX评级 [6,7]msTimeTxt(始终作为二次偏移)
	public var ratingOffset:Int = 0;
	public var hitWindowPreset:String = 'Psych / Kade';
	public var perfectWindow:Float = 23.00;
	public var sickWindow:Float = 45.00;
	public var goodWindow:Float = 90.00;
	public var badWindow:Float = 135.00;
	public var shitWindow:Float = 180.00; // Shit判定窗口（作为safeZoneOffset上限）
	public var useShitWindowAsSafeZone:Bool = true; // 是否使用shitWindow替代safeFrames计算safeZoneOffset
	public var softJudgmentEdge:Bool = false; // 是否在判定窗口边缘启用软边缘插值（避免卡边界时判定跳变）
	public var safeFrames:Float = 10.0;
	public var guitarHeroSustains:Bool = true;
	public var breakComboOnBad:Bool = false; // 命中 bad 时断连
	public var breakComboOnShit:Bool = false; // 命中 shit 时断连
	public var accuracyMode:String = 'accurate'; // 准确率模式: 'accurate' (按评级固定加权) 或 'complex' (wife3 毫秒精度)
	public var sustainAccuracy:Bool = true; // 长条(尾音)命中是否计入准确率
	public var kadeScoring:Bool = false; // Kade 计分制：bad=0/shit=-300/good=200/sick=350，命中Shit断连并计miss，套用Kade加减血
	public var kadeHoldVisual:Bool = false; // Kade 长条视觉：显示为分段，判定区间已走过的长条段淡出到0.3（纯视觉，不影响判定）
	public var sustainTailFix:String = 'off'; // 长按音符尾条判定优化: 'off'=原版, 'extend'=延伸末段到可见尾部(A), 'earlyHit'=放宽末段提前命中(B), 'both'=两者皆用
	public var holdReleaseInstantMiss:Bool = false; // 特性1: 启用guitarHeroSustains时，长条命中期间松手立刻判定miss
	public var holdTailJudge:Bool = false; // 特性2: 长条尾部算一个有效命中(加combo+显示评级,但不加分;超时未命中照样断连并miss)
	public var holdScoreBonus:Bool = false; // 特性3: 长条命中期间持续加分直到长条结束(参考原版Funkin)
	public var holdTailLeniency:Bool = false; // 特性2宽容: 尾条判定(释放时机)是否放宽判定窗口
	public var holdTailLeniencyMs:Float = 20.0; // 特性2宽容量(ms)，默认20，范围0-50
	// Extra Keys 相关设置
	public var touchLaneMode:String = 'auto'; // 触屏多键轨道：'auto' = 跟随谱面键数 / '4k' = 固定 4 键
	public var showKeyPreview:Bool = true; // 开局在每个 strum 下方短暂显示对应按键名（EK KeybindShowcase）
	public var keyPreviewStyle:String = 'ek'; // 键位预览样式：'ek' = EK KeybindShowcase（背景块+双键位切换）/ 'le' = LE extraKeyReminders（白字黑阴影+逐列淡出）
	public var inputSystem:String = 'default'; // 输入判定系统: 'default' (传统) 或 'rhythm' (Rhythm模式，只允许击中最近的音符)
	public var discordRPC:Bool = true;
	public var loadingScreen:Bool = true;
	public var basiclanguage:String = 'en-US';
	public var language:String = 'zh_cn';
	public var keyViewer:Bool = false; // 游戏内按键显示覆盖层（复刻 JKPS 效果）
	public var keyViewerProfile:Bool = false; // KeyViewer 左侧图标 + 底部自定义名字（关闭时按键垂直居中）
	public var keyViewerName:String = ''; // KeyViewer 底部显示的自定义名字（留空则读取 images/keyviewer/name.txt）

	//杂七杂八的特性
	public var fpsCounterSize:Int = 14;
	public var rainbowfpscounter:Bool = false;
	public var exgameversion:Bool = false;
	public var exratingDisplay:Bool = true;
	public var showHaxelibs:Bool = false;
	public var rmPerfect:String = 'enable'; // 'enable'=正常(Perfect独立判定), 'remove'=完全移除Perfect, 'sickPlus'=Perfect变为Sick+状态(算Sick但可选显示Perfect贴图,给Perfect分数)
	public var ratbounce:Bool = true;
	public var scoretxtstyle:String = 'Kathy';
	public var scoreLanguage:String = 'auto'; // 分数文字（scoreTxt）显示语言：'auto' 跟随游戏语言，或指定 English/简体中文/繁體中文/日本語/한국어
	public var rmmsTimeTxt:Bool = false;
	public var showModeLabelInMsTxt:Bool = true;
	public var msTimingStyle:String = 'Kathy'; // ms 毫秒显示风格: 'Kathy'(Psych 静态文本) / 'Kade'(Kade 弹出+判定颜色)
	public var msTimingOffsetMode:String = 'independent'; // msTimeTxt 位置偏移方式: 'independent'(独立偏移 [6,7]) / 'numScore'(跟随 combo 数字 [2,3])
	public var scoretxtbounce:Bool = false;
	public var exratbounce:Bool = false;
	public var iconbopstyle:String = 'Kathy';
	public var iconbopNormalize:Bool = true; // 图标回弹是否按刷新率归一化（true=任意刷新率表现一致，高刷屏不再偏快/偏慢）
	public var healthbarstyle:String = 'Psych';
	public var ratingsAlpha:Float = 1;
	public var customFadeStyle:String = 'V-Slice';
	public var blueArchiveLanguage:String = 'EN';
	public var showRunningOS:Bool = false;
	//NFE的特性
	//public var CustomFadeSound:Bool = true;
	//public var CustomFadeText:Bool = true;

	//用于MRE加载图片更改，之后也许需要优化
	public var randomIndex :Int = 32;

	public var smoothHP:Bool = true;
	public var healthOverflow:Bool = false; // 超满血：需配合 smoothHP；开启后血量可超过 100%，并让小图标向血条外溢出移动
	public var healthOverflowDrain:Float = 20; // 超满血回落速度系数（lerp），越大回落越快
	public var smoothHPSpeed:Float = 10; // 丝滑血条平滑系数（lerp），越大血条追得越紧、延迟越小
	public var forceSingleSplashAnim:Bool = false;
	public var volumeTheme:String = "Psych";
	public var cpuStrums: Bool = true;
	public var extrahp: Bool = true;
	public var botplayStyle:String = "Psych(New)";
	public var showcaseStyle:String = "Psych";
	public var fpsFont:String = "Psych";
	public var timebarStyle:String = "Psych";
	public var legacynotepos:Bool = false;
	public var legacyHUD:Bool = false; // 兼容旧版Psych(0.6.x): 将HUD元素直接加入state而非uiGroup, 供旧模组脚本用getObjectOrder/setObjectOrder定位
	public var chartingVersion:String = '1.0.4-Kathy'; // 制谱器版本: '1.0.4-Kathy' | '1.0.4-Official' | '0.7.3' | '0.6.3'
	// Lua API 兼容版本：决定 setObjectCamera / doTween* / makeAnimatedLuaSprite 等 API 的默认参数与行为
	// 'auto' = 自动识别（暂时回落到 1.0.4），'1.0.4' = KathyEngine 原生（默认），'0.7.3' / '0.6.3' = 旧版脚本兼容
	public var luaCompatVersion:String = '1.0.4';
	// Leather Engine 脚本 API 兼容模式：
	// 'off'     = 不启用 LE 脚本层（LE mod 的 scripts/*.lua 不会被加载）
	// 'auto'    = 自动检测：谱面 format=LEATHER 走 Official 系，LEATHER LTS 走 LTS 系（默认）
	// 'official'= 强制使用 LE Official 0.5.x API
	// 'lts'     = 强制使用 LE LTS 1.1.x API
	// 参考 LE 源码：D:\VibeCode\LeatherEngine-Official\source\modding\ModchartUtilities.hx
	//              D:\VibeCode\LeatherEngine-LTS\LeatherEngine-main\source\modding\scripts\languages\LuaScript.hx
	public var leatherScriptCompat:String = 'auto';
	public var ratingsPos:String = "camHUD";

	public var fpsPosition:String = "TOP_LEFT"; // "TOP_LEFT", "TOP_RIGHT", "BOTTOM_LEFT", "BOTTOM_RIGHT"
	public var fpsSpacing:Int = 10;

	// 启动开屏模式: 'Kathy' = 自定义 Logo 开屏, 'Flixel' = Flixel 自带 splash, 'None' = 直接进游戏
	public var splashMode:String = 'Kathy';
	public var hudSize:Float = 1.0;
	public var enableModsImport:Bool = false; // Enable Mods Import in the main menu
	public var eventDebug:Bool = true;
	public var botplayScore:Bool = true;
	public var botplayPerfectTiming:Bool = false; // BotPlay 模式下强制显示 0ms 命中时间
	public var systemCursor:Bool = false;
	public var hudZoomStyle:String = "default";
	public var showNPS:Bool = true; // Show NPS in the HUD
	public var showResultScreen:Bool = true; // Show the result screen after finishing a song
	public var comboSprDisplay:Bool = false; //据说这是官方废稿，我不确定
	// combo 数字纹理显示模式：'Psych' = 当前逻辑(补0到3位)；'Default' = 类似Psych但不补0；'OG Funkin' = combo≥10才显示, 断连后首次命中显示000
	public var comboNumDisplay:String = 'Default';
	public var ratingFallStyle:String = "Legacy"; // 禁用Combo Stacking时的跳动风格：Legacy = 向下速度，Kathy = 向下移动一段距离，Camellia = 原地缩放回弹 + 固定节奏淡出（复刻自 VSCam）
	// Camellia 风格的缩放基准：Proportional = 基于引擎现有 0.7 基准等比回弹，Original = 照搬原版 0.45 → 0.4 绝对数值
	public var camelliaScaleMode:String = "Proportional";
	
	public var backgroundVolume:Bool = true; // 是否启用后台降音
	public var backgroundVolumeLevel:Float = 0.2; // 后台音量级别

	public var fixedTimestep:Bool = true; // 固定时间步长（？）

	public var ratCounter:Bool = true; // 评分计数器
	public var ratCounterAnimation:Bool = true; // 评分计数器动画效果
	public var waterMarkPlay:Bool = true; // 水印
	public var enableGameLog:Bool = false; // 启用游戏内日志显示（按F3切换）
	public var legacyMainMenu:Bool = false; // 是否使用旧版主菜单UI（Psych Engine v0.7.3原生样式）
	public var developer:Bool = false; // 开发者模式：启用后可进入编辑器菜单(MasterEditorMenu)，legacy主界面显示toolbox入口
	public var enableConsoleLog:Bool = true; // 是否在终端/控制台输出日志（debug/移动端默认启用，其余可自定义
	public var garbageCollectorEnabled:Bool = true; // 是否启用原生GC（cpp.NativeGc / hl.Gc），关闭可减少周期性掉帧
	public var useOptimizedNoteLoading:String = 'AUTO'; // OFF / ON / AUTO — AUTO 根据谱面 NPS 自动选择
	public var requestAdminPrivilege:Bool = false; // 是否请求管理员权限（Windows专用）
	public var keepSingAnimation:Bool = true; // 保持sing动画不返回idle（用于Hyperactive成就）
	public var cacheResourcesOnReload:Bool = true; // 重载曲目时缓存资源以加速加载
	public var forceHoldAnimations:Bool = false; // 箭头命中时只播放一次动画，不依赖hold动画
	public var timeBarStripes:Bool = false; // 时间条是否显示条纹
	public var timeBarGradient:Bool = false; // 时间条是否使用渐变（对手色→玩家色，支持Psych与Leather (Legacy)样式）
	public var singleHoldNoteAnimation:Bool = true; // 按住长条音符时只播放一次confirm动画
	public var autoResetStrumAnim:Bool = true; // 是否自动恢复箭头默认动画（普通按键和hold note）
	public var ghostEffect:Bool = true; // 多押时角色的ghost残影效果

	public var playStateAdaptiveWidth:Bool = false; // PlayState宽屏自适应：高度锁定720，宽度960~1680自适应

	public var chartEditorFollowWindow:Bool = false; // 制谱器分辨率是否跟随窗口：true=跟随窗口(720p~1080p自适应)，false=使用游戏默认固定分辨率1280x720

	// 制谱器深浅色模式：'Light' 亮色 | 'Dark' 深色 | 'Default' 跟随制谱器内保存的主题
	public var chartEditorTheme:String = 'Default';

	// 当模组没有perfect/marvelous贴图时，是否改用sick贴图显示
	public var fallbackPerfectToSick:Bool = true;
	public var fallbackEXPerfectToSick:Bool = true;

	public var soundTrayStyle:String = 'Flixel';
	public var holdNoteBehind:Bool = false; // 将 hold note 放在正常音符和 strum 箭头下面

	// FPS计数器自定义设置
	public var fpsColor:FlxColor = 0xFFE6CAFF; // FPS计数器颜色
	public var fpsOpacity:Float = 1.0; // FPS计数器不透明度
	public var fpsFontSize:Int = 14; // FPS计数器字体大小
	public var fpsShowFPS:Bool = true; // 显示FPS
	public var fpsShowDelay:Bool = true; // 显示延迟
	public var fpsShowRAM:Bool = true; // 显示内存使用
	public var fpsShowMemPeak:Bool = true; // 显示内存峰值
	public var fpsShowObjects:Bool = true; // 显示对象数量
	public var fpsBgEnabled:Bool = false; // 是否启用FPS计数器背景
	public var fpsBgColor:FlxColor = 0xFF000000; // FPS计数器背景颜色
	public var fpsBgOpacity:Float = 0.5; // FPS计数器背景不透明度
	public var fpsBgPadding:Int = 5; // FPS计数器背景内边距
	public var fpsForceMB:Bool = false; // 是否强制显示MB而非GB
	public var fpsShowPlatform:Bool = false; // 显示Platform信息
	public var fpsShowOSVersion:Bool = false; // 显示OS版本
	public var fpsShowResolution:Bool = false; // 显示分辨率
	public var fpsShowRefreshRate:Bool = false; // 显示刷新率

	// 窗口标题
	public var windowTitle:String = "Kathy Engine";
	public var windowTitlePreset:String = "Kathy Engine";
	public var fakeOSVersion:String = "1.5.1";
	public var watermarkType:String = 'Kathy';

	// Fake Psych 版本伪装
	public var fakePsychVersion:String = "1.0.4";

	// 旧版短类名兼容层（0.6.3/0.7.3 脚本可用短名，如 getPropertyFromClass('Note',...)）
	public var enableLegacyClassAlias:Bool = true;

	// 动态窗口标题（Dynamic Window Title）
	public var dynamicWindowTitle:Bool = false; // 启用动态窗口标题（显示当前界面/模组/曲目信息）
	public var windowTitleShowState:Bool = true; // 标题中显示当前界面/状态名称
	public var windowTitleShowMod:Bool = true; // 标题中显示当前模组名称
	public var windowTitleShowSong:Bool = true; // 标题中显示当前游玩曲目
	public var windowTitleShowDifficulty:Bool = false; // 标题中显示当前曲目难度

	// Leather 风格相关
	public var biggerInfoText:Bool = false; // 更大的信息文本
	public var loadLeatherIcons:String = 'default'; // 小图标样式: 'default'=默认, 'leather'=Leather Engine 格式(leather/<角色名>-icons.png), 'os'=OS 风格(icon-<角色名>.png)，支持 Mods 覆盖
	public var opponentSplashes:Bool = false; // 启用后对手侧箭头击打也会显示 NoteSplash
	public var holdCovers:Bool = true; // 长条按住期间在箭头上显示 Hold Cover 光效（类似原版 FNF），末尾播放爆发动画
	public var opponentHoldCovers:Bool = false; // 对手侧也显示 Hold Cover（需 CPU Strums 可见）
	public var noteTimerEnabled:Bool = true; // 箭头倒计时：两箭头间隔 ≥ 3秒 时显示圆形进度圈 + 整数秒
	public var noteTimerLayer:String = 'Above Notes'; // 箭头倒计时图层：'Above Notes' 压在箭头之上（默认），'Below Notes' 在箭头之下
	public var noteTimerDisplay:String = 'Seconds'; // 箭头倒计时数字显示：'Seconds' 按秒取整（默认），'Beats' 按 Beat 取整
	public var noteTimerStepped:Bool = false; // 圆环裁剪动效：true = 按 beat/秒 离散跳变（脉冲感），false = 丝滑连续裁剪（默认）
	public var multiKeyLayoutStyle:String = 'PsychEK'; // 多键（>4K）箭头布局风格：'PsychEK' 自适应收缩贴合屏幕（默认），'Leather' 照搬 Leather 引擎表驱动尺寸/间距（无自适应）

	// Simple Info Display (Leather风格) 设置
	public var fpsLayer:String = "Stage"; // FPS计数器所在图层: "Stage" 或 "Game"
	public var fpsStyle:String = "Psych"; // FPS计数器样式: "Psych" 或 "Simple"
	public var simpleInfoColor:FlxColor = 0x000000; // SimpleInfoDisplay 颜色
	public var simpleInfoFontSize:Int = 12; // SimpleInfoDisplay 字体大小（_sans 用 12px，与 Leather 一致）
	public var simpleInfoShowFPS:Bool = true; // SimpleInfoDisplay 显示FPS
	public var simpleInfoShowMem:Bool = true; // SimpleInfoDisplay 显示内存
	public var simpleInfoShowVersion:Bool = false; // SimpleInfoDisplay 显示版本

	// 原版 FunkinDebugDisplay 风格（"Debug" fpsStyle）设置
	public var fpsDebugMode:String = "Simple"; // Debug 面板模式: "Off" / "Simple" / "Advanced"
	public var fpsDebugHotkey:Int = FlxKey.F2; // 独立开关+循环模式的快捷键键码（openfl Keyboard keyCode）
	public var fpsDebugFontSize:Int = 12; // Debug 面板文字字号
	public var fpsDebugFont:String = "VCR"; // Debug 面板字体: "VCR" / "Quantico"
	public var fpsDebugTextColor:FlxColor = 0xFFFFFFFF; // Debug 面板文字/折线颜色
	public var fpsDebugBgEnabled:Bool = true; // 是否显示衬底面板
	public var fpsDebugBgOuter:FlxColor = 0xFF3D3F41; // 面板外框色
	public var fpsDebugBgInner:FlxColor = 0xFF2C2F30; // 面板内底色
	public var fpsDebugBgOpacity:Float = 0.5; // 面板不透明度
	public var fpsDebugPadding:Int = 3; // 面板边框内缩（INNER_RECT_DIFF）
	public var fpsDebugPanelWidth:Int = 234; // Simple 面板内区宽度（Advanced 固定铺高）
	public var fpsDebugUpdateDelay:Int = 100; // 更新间隔（毫秒，DC）
	public var fpsDebugHistoryMax:Int = 100; // 折线历史采样长度
	public var fpsDebugLineThickness:Float = 1; // 折线粗细
	public var fpsDebugGraphSmooth:Bool = true; // 折线图是否启用曲线平滑（用二次贝塞尔圆滑，看起来不那么尖锐）
	public var fpsDebugGraphHeight:Int = 25; // 每条折线图高度
	public var fpsDebugGraphTextGap:Int = 8; // 折线图与上方文本的间距
	public var fpsDebugAxisColor:FlxColor = 0xFFFFFFFF; // 坐标轴颜色
	public var fpsDebugAxisAlpha:Float = 0.5; // 坐标轴透明度
	public var fpsDebugAxisInset:Int = 4; // 图形相对坐标轴缩进
	public var fpsDebugShowFPSGraph:Bool = true; // 显示 FPS 折线图（含实时值）
	public var fpsDebugShowAvg:Bool = true; // FPS 折线显示平均值
	public var fpsDebugShowLow:Bool = true; // FPS 折线显示 1% low
	public var fpsDebugShowGCMem:Bool = true; // 显示 GC 内存折线图
	public var fpsDebugShowTaskMem:Bool = true; // 显示任务内存折线图
	public var fpsDebugShowPlatform:Bool = true; // Simple 模式 FPS 行是否附带平台信息

	// KeyViewer 累计按键总数（keyViewerTotal）已移至 objects.KeyViewer 内部独立存档，
	// 不再存放在 ClientPrefs 主设置里，以免主设置文件损坏时把它一起清零。
	// KeyViewer 轨迹方向：'auto' 跟随 downscroll，'up' 强制上升，'down' 强制下落
	public var keyViewerTrail:String = 'auto';
	// KeyViewer 位置偏移（像素，相对默认位置）：在设置内拖动校准，跨重启持久化
	public var keyViewerPosX:Float = 0;
	public var keyViewerPosY:Float = 0;
	// KeyViewer 轨迹速度（像素/秒），可在设置中调节
	public var keyViewerTrailSpeed:Float = 300;

}

class ClientPrefs {
	public static var data:SaveVariables = {};
	public static var defaultData:SaveVariables = {};

	/**
	 * 把 stageQuality 字符串映射成 openfl.display.StageQuality。
	 * 供 Main 启动与设置界面实时切换使用。
	 */
	public static function getStageQuality():StageQuality
	{
		return switch (data.stageQuality)
		{
			case 'LOW': StageQuality.LOW;
			case 'HIGH': StageQuality.HIGH;
			case 'BEST': StageQuality.BEST;
			default: StageQuality.MEDIUM;
		}
	}

	//Every key has two binds, add your key bind down here and then add your control on options/ControlsSubState.hx and Controls.hx
	public static var keyBinds:Map<String, Array<FlxKey>> = [
		//Key Bind, Name for ControlsSubState
		'note_left'		=> [D, LEFT],
		'note_down'		=> [F, DOWN],
		'note_up'		=> [J, UP],
		'note_right'	=> [K, RIGHT],
		
		'ui_left'		=> [A, LEFT],
		'ui_down'		=> [S, DOWN],
		'ui_up'			=> [W, UP],
		'ui_right'		=> [D, RIGHT],
		
		'accept'		=> [SPACE, ENTER],
		'back'			=> [BACKSPACE, ESCAPE],
		'pause'			=> [ENTER, ESCAPE],
		'reset'			=> [R],
		
		'volume_mute'	=> [ZERO],
		'volume_up'		=> [NUMPADPLUS, PLUS],
		'volume_down'	=> [NUMPADMINUS, MINUS],
		
		'debug_1'		=> [SEVEN],
		'debug_2'		=> [EIGHT],
		'debug_3'		=> [F7],
		'debug_4'		=> [F6],
		
		'fullscreen'	=> [F11]
	];
	public static var gamepadBinds:Map<String, Array<FlxGamepadInputID>> = [
		'note_up'		=> [DPAD_UP, Y],
		'note_left'		=> [DPAD_LEFT, X],
		'note_down'		=> [DPAD_DOWN, A],
		'note_right'	=> [DPAD_RIGHT, B],
		
		'ui_up'			=> [DPAD_UP, LEFT_STICK_DIGITAL_UP],
		'ui_left'		=> [DPAD_LEFT, LEFT_STICK_DIGITAL_LEFT],
		'ui_down'		=> [DPAD_DOWN, LEFT_STICK_DIGITAL_DOWN],
		'ui_right'		=> [DPAD_RIGHT, LEFT_STICK_DIGITAL_RIGHT],
		
		'accept'		=> [A, START],
		'back'			=> [B],
		'pause'			=> [START],
		'reset'			=> [BACK]
	];
	public static var mobileBinds:Map<String, Array<MobileInputID>> = [
		'note_up'		=> [NOTE_UP],
		'note_left'		=> [NOTE_LEFT],
		'note_down'		=> [NOTE_DOWN],
		'note_right'	=> [NOTE_RIGHT],

		'ui_up'			=> [UP],
		'ui_left'		=> [LEFT],
		'ui_down'		=> [DOWN],
		'ui_right'		=> [RIGHT],

		'accept'		=> [A],
		'back'			=> [B],
		'pause'			=> [#if android NONE #else P #end],
		'reset'			=> [NONE]
	];
	public static var defaultKeys:Map<String, Array<FlxKey>> = null;
	public static var defaultButtons:Map<String, Array<FlxGamepadInputID>> = null;
	public static var defaultMobileBinds:Map<String, Array<MobileInputID>> = null;

	public static function resetKeys(controller:Null<Bool> = null) //Null = both, False = Keyboard, True = Controller
	{
		if(controller != true)
			for (key in keyBinds.keys())
				if(defaultKeys.exists(key))
					keyBinds.set(key, defaultKeys.get(key).copy());

		if(controller != false)
			for (button in gamepadBinds.keys())
				if(defaultButtons.exists(button))
					gamepadBinds.set(button, defaultButtons.get(button).copy());
	}

	public static function clearInvalidKeys(key:String)
	{
		var keyBind:Array<FlxKey> = keyBinds.get(key);
		var gamepadBind:Array<FlxGamepadInputID> = gamepadBinds.get(key);
		var mobileBind:Array<MobileInputID> = mobileBinds.get(key);
		while(keyBind != null && keyBind.contains(NONE)) keyBind.remove(NONE);
		while(gamepadBind != null && gamepadBind.contains(NONE)) gamepadBind.remove(NONE);
		while(mobileBind != null && mobileBind.contains(NONE)) mobileBind.remove(NONE);
	}

	public static function loadDefaultKeys()
	{
		// Extra Keys：从 extrakeys.json 注册多键档位的默认键位（"{mania}_key_{i}"）。
		// 必须在 copy 到 defaultKeys 之前完成，否则用户 reset 键位后多键档位会丢失。
		registerExtraKeysDefaults();

		defaultKeys = keyBinds.copy();
		defaultButtons = gamepadBinds.copy();
		defaultMobileBinds = mobileBinds.copy();
	}

	/** 从 extrakeys.json 把每个 mania 档位的默认键盘键位灌进 keyBinds。
	 *  action 命名："{mania}_key_{lane}"，与 PlayState.applyMania 生成的 keysArray 对齐。
	 *  已存在的 action（用户在设置里改过）不覆盖。 */
	static function registerExtraKeysDefaults():Void
	{
		try {
			ExtraKeysHandler.ensure();
			var ek = ExtraKeysHandler.instance.data;
			if (ek == null || ek.keybinds == null) return;

			for (mania in 0...ek.keybinds.length) {
				var lanes = ek.keybinds[mania];
				if (lanes == null) continue;
				for (i in 0...lanes.length) {
					var actionName:String = Std.string(mania) + '_key_' + i;
					if (keyBinds.exists(actionName)) continue;

					var keys:Array<FlxKey> = [];
					if (lanes[i] != null) {
						for (kc in lanes[i]) {
							try {
								keys.push(cast kc); // int keycode -> FlxKey
							} catch (e:Dynamic) {}
						}
					}
					if (keys.length > 0) keyBinds.set(actionName, keys);
				}
			}
			trace('[EK] Registered ' + ek.keybinds.length + ' mania-mode default keybinds.');
		} catch (e:Dynamic) {
			trace('[EK] registerExtraKeysDefaults failed: $e');
		}
	}

	/**
	 * Extra Keys：把 arrowRGB / arrowRGBPixel / arrowHSV 扩展为 18 色（来自 extrakeys.json 的全局色表），
	 * 保证多键谱任意列（styleIndex 0..17）取色不越界。
	 * - 用户已自定义的前 4 项保留不动；缺项（如旧存档只有 4 项）用 EK 色表补齐 4..17。
	 * - HSV 模式没有每档色表，用 [0,0,0]（不变色）补齐，视觉与 4 键一致。
	 */
	/** Extra Keys：运行时入口（PlayState 进游戏时再次调用，兜底 loadPrefs 早期加载失败）。 */
	public static function ensureEKArrowColors():Void
	{
		try {
			ExtraKeysHandler.ensure();
			var ek = ExtraKeysHandler.instance.data;
			if (ek == null || ek.colors == null || ek.colors.length < 18) return;
			var targetLen:Int = 18;
			// 先把 defaultData（出厂色表）补齐到 18 色，与 EK 原版 loadArrowRGBData 一致：
			// 0..3 保持 Psych 出厂色（与 extrakeys colors[0..3] 同值），4..17 用 EK 全局色表补齐，
			// 保证 R 键重置在多键页能取到正确样式默认色（列索引≠样式索引）。
			if (defaultData.arrowRGB != null && defaultData.arrowRGB.length < targetLen) {
				while (defaultData.arrowRGB.length < targetLen) {
					var dIdx:Int = defaultData.arrowRGB.length;
					var dc = ek.colors[dIdx];
					if (dc != null) defaultData.arrowRGB.push([FlxColor.fromString('#' + dc.inner), FlxColor.fromString('#' + dc.border), FlxColor.fromString('#' + dc.outline)]);
					else defaultData.arrowRGB.push([147, 0, 220]);
				}
			}
			if (ek.pixelNoteColors != null && ek.pixelNoteColors.length >= 18 && defaultData.arrowRGBPixel != null && defaultData.arrowRGBPixel.length < targetLen) {
				while (defaultData.arrowRGBPixel.length < targetLen) {
					var dPxIdx:Int = defaultData.arrowRGBPixel.length;
					var dpc = ek.pixelNoteColors[dPxIdx];
					if (dpc != null) defaultData.arrowRGBPixel.push([FlxColor.fromString('#' + dpc.inner), FlxColor.fromString('#' + dpc.border), FlxColor.fromString('#' + dpc.outline)]);
					else defaultData.arrowRGBPixel.push([195, 75, 75]);
				}
			}
			if (data.arrowRGB != null && data.arrowRGB.length < targetLen) {
				while (data.arrowRGB.length < targetLen) {
					var idx:Int = data.arrowRGB.length;
					var c = ek.colors[idx];
					if (c != null) data.arrowRGB.push([FlxColor.fromString('#' + c.inner), FlxColor.fromString('#' + c.border), FlxColor.fromString('#' + c.outline)]);
					else data.arrowRGB.push([147, 0, 220]);
				}
			}
			if (ek.pixelNoteColors != null && ek.pixelNoteColors.length >= 18 && data.arrowRGBPixel != null && data.arrowRGBPixel.length < targetLen) {
				while (data.arrowRGBPixel.length < targetLen) {
					var idx:Int = data.arrowRGBPixel.length;
					var c = ek.pixelNoteColors[idx];
					if (c != null) data.arrowRGBPixel.push([FlxColor.fromString('#' + c.inner), FlxColor.fromString('#' + c.border), FlxColor.fromString('#' + c.outline)]);
					else data.arrowRGBPixel.push([195, 75, 75]);
				}
			}
			if (data.arrowHSV != null && data.arrowHSV.length < targetLen) {
				while (data.arrowHSV.length < targetLen) data.arrowHSV.push([0, 0, 0]);
			}
		} catch (e:Dynamic) {
			trace('[EK] ensureEKArrowColors failed: $e');
		}
	}

	public static function saveSettings() {
		for (key in Reflect.fields(data))
			Reflect.setField(FlxG.save.data, key, Reflect.field(data, key));

		#if ACHIEVEMENTS_ALLOWED Achievements.save(); #end

		// flush the main save and check the return value; on failure only log, never throw
		var ok = FlxG.save.flush();
		if (ok != true)
			FlxG.log.error('ClientPrefs: Failed to save main save (funkin.sol), flush returned ' + ok);
		else
			writeBackupSave(); // only write the backup after a successful main save, so the backup is always intact

		//Placing this in a separate save so that it can be manually deleted without removing your Score and stuff
		var save:FlxSave = new FlxSave();
		save.bind('controls_v3', CoolUtil.getSavePath());
		save.data.keyboard = keyBinds;
		save.data.gamepad = gamepadBinds;
		save.data.mobile = mobileBinds;
		save.flush();
		FlxG.log.add("Settings saved!");
	}

	/**
	 * Bind and return the backup SharedObject (funkin_backup) for the main save.
	 * Returns null if binding fails or throws; caller must check.
	 */
	private static function getBackupSave():FlxSave {
		try {
			var backup:FlxSave = new FlxSave();
			if (backup.bind('funkin_backup', CoolUtil.getSavePath()))
				return backup;
		} catch (e:Dynamic) {
			FlxG.log.error('ClientPrefs: Failed to bind backup save: ' + e);
		}
		return null;
	}

	/**
	 * Write all fields of the current ClientPrefs.data into the standalone backup save.
	 * On failure only log; never interrupt the main flow.
	 */
	private static function writeBackupSave():Void {
		var backup:FlxSave = getBackupSave();
		if (backup == null) return;
		try {
			for (key in Reflect.fields(data))
				Reflect.setField(backup.data, key, Reflect.field(data, key));
			if (backup.flush() != true)
				FlxG.log.error('ClientPrefs: Failed to save backup (funkin_backup)');
		} catch (e:Dynamic) {
			FlxG.log.error('ClientPrefs: Exception while writing backup save: ' + e);
		}
	}



	public static function loadPrefs() {
		#if ACHIEVEMENTS_ALLOWED Achievements.load(); #end

		// @:structInit 类不支持 new，手动补全 SaveVariables 字段的默认值
		if (Reflect.fields(defaultData).length == 0) {
			defaultData.fakeOSVersion = '1.5.1';
			defaultData.fakePsychVersion = '1.0.4';
			defaultData.enableLegacyClassAlias = true;
			defaultData.windowTitle = 'Kathy Engine';
			defaultData.windowTitlePreset = 'Kathy Engine';
		}

		// Corruption detection & auto-restore: if the main save is truncated/corrupted (zero fields),
		// but the backup still holds data, restore the main save from it and self-heal via flush.
		// On first run both are empty, so we fall through to defaults; no false trigger.
		try {
			if (FlxG.save.data != null && Reflect.fields(FlxG.save.data).length == 0) {
				var backup:FlxSave = getBackupSave();
				if (backup != null && Reflect.fields(backup.data).length > 0) {
					for (key in Reflect.fields(backup.data))
						Reflect.setField(FlxG.save.data, key, Reflect.field(backup.data, key));
					if (FlxG.save.flush() != true)
						FlxG.log.error('ClientPrefs: Failed to flush main save after restoring from backup');
					else
						FlxG.log.add('ClientPrefs: Main save was corrupted, auto-restored from backup (funkin_backup)');
				}
			}
		} catch (e:Dynamic) {
			// The restore process must never throw on the startup path; on failure silently fall back to defaults
			FlxG.log.error('ClientPrefs: Exception during backup restore, skipped: ' + e);
		}

		for (key in Reflect.fields(data))
			if (key != 'gameplaySettings' && Reflect.hasField(FlxG.save.data, key))
				Reflect.setField(data, key, Reflect.field(FlxG.save.data, key));
		
		// 旧存档兼容：ghostTapping Bool → ghostTappingMode String
		if (Reflect.hasField(FlxG.save.data, 'ghostTapping'))
		{
			var oldVal:Dynamic = Reflect.field(FlxG.save.data, 'ghostTapping');
			if (!Reflect.hasField(FlxG.save.data, 'ghostTappingMode'))
			{
				data.ghostTappingMode = (oldVal == true) ? 'always' : 'off';
			}
			// 让 Bool 与 String 保持一致（迁移后 Bool 仅作兼容读取）
			data.ghostTapping = data.ghostTappingMode != 'off';
			// 从存档数据删除 Bool 键，下次保存就只剩 String
			Reflect.deleteField(FlxG.save.data, 'ghostTapping');
		}
		// 旧存档兼容：上一版模式名 → 新版
		if (data.ghostTappingMode == 'psych') data.ghostTappingMode = 'always';
		else if (data.ghostTappingMode == 'vslice') data.ghostTappingMode = 'whenSinging';
		else if (data.ghostTappingMode == 'cooldown') data.ghostTappingMode = 'whenSinging';
		else if (data.ghostTappingMode == 'disabled') data.ghostTappingMode = 'off';
		
		// 确保 soundTrayStyle 被正确初始化
		if (data.soundTrayStyle == null) {
			data.soundTrayStyle = 'Flixel';
		}

		// 为 comboOffset 新增的槽位补默认值（兼容老存档升级；[6,7]msTimeTxt，超出槽位保留但已不使用）
		if (data.comboOffset == null)
			data.comboOffset = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
		else if (data.comboOffset.length < 10) {
			while (data.comboOffset.length < 10) data.comboOffset.push(0);
		}

		// 新增 msTimeTxt 偏移方式字段默认值（兼容老存档升级）
		if (!Reflect.hasField(FlxG.save.data, 'msTimingOffsetMode'))
			data.msTimingOffsetMode = 'independent';

		// 为 1.5.x 新增的移动端判定补偿字段填充默认值（兼容老存档升级）
		// FlxG.save.data 里没有对应键时，Reflect.hasField 返回 false，此时保持类声明中的默认值。
		if (!Reflect.hasField(FlxG.save.data, 'mobileJudgmentCompensation'))
			data.mobileJudgmentCompensation = FlxG.onMobile;
		if (!Reflect.hasField(FlxG.save.data, 'mobileJudgmentOffset') || data.mobileJudgmentOffset < 0)
			data.mobileJudgmentOffset = 10.0;

		// 为 1.5.x 新增的 Shit 窗口与 SafeZone 模式填充默认值（兼容老存档升级）
		if (!Reflect.hasField(FlxG.save.data, 'shitWindow') || data.shitWindow <= 0)
			data.shitWindow = 180.0;
		if (!Reflect.hasField(FlxG.save.data, 'useShitWindowAsSafeZone'))
			data.useShitWindowAsSafeZone = true;
		if (!Reflect.hasField(FlxG.save.data, 'softJudgmentEdge'))
			data.softJudgmentEdge = false;

		// 为 1.5.x 新增的打击音随偏移变调字段填充默认值（兼容老存档升级）
		if (!Reflect.hasField(FlxG.save.data, 'hitsoundPitchOffset'))
			data.hitsoundPitchOffset = false;
		if (!Reflect.hasField(FlxG.save.data, 'hitsoundPitchRange') || data.hitsoundPitchRange <= 0)
			data.hitsoundPitchRange = 0.25;

		// 为 1.5.x 新增的打击音对象池新字段填充默认值（兼容老存档升级）
		if (!Reflect.hasField(FlxG.save.data, 'hitSoundPoolEnabled'))
			data.hitSoundPoolEnabled = true;
		if (!Reflect.hasField(FlxG.save.data, 'hitSoundPoolSize') || data.hitSoundPoolSize < 1)
			data.hitSoundPoolSize = 50;

		// 为帧自适应同步新增字段填充默认值（兼容老存档升级）
		if (!Reflect.hasField(FlxG.save.data, 'useFrameAdaptiveSync'))
			data.useFrameAdaptiveSync = false;
		if (!Reflect.hasField(FlxG.save.data, 'syncSpeedMultiplier') || data.syncSpeedMultiplier <= 0)
			data.syncSpeedMultiplier = 1.0;

		// 向后兼容：将旧版 Bool 类型的 rmPerfect 转换为新版 String 三选一
		// 旧 false → 'enable'(正常), 旧 true → 'remove'(完全移除), 新存档直接为 String
		if (Reflect.hasField(FlxG.save.data, 'rmPerfect'))
		{
			var savedRmPerfect:Dynamic = Reflect.field(FlxG.save.data, 'rmPerfect');
			if (savedRmPerfect == true)
				data.rmPerfect = 'remove';
			else if (savedRmPerfect == false)
				data.rmPerfect = 'enable';
			// 若已是 String ('enable'/'remove'/'sickPlus') 则保持不变
		}
		// 兼容重命名：改名前（off→enable）已有玩家存档直接写入字符串 'off'，归一化为 'enable'
		if (data.rmPerfect == 'off')
			data.rmPerfect = 'enable';

		// Extra Keys：arrowRGB / arrowRGBPixel / arrowHSV 由 4 色扩展到 18 色（取自 extrakeys.json），
		// 保证多键谱第 5 列及以后的颜色索引（styleIndex 0..17）不会越界。
		// 用户已自定义的前 4 项保留，4..17 用 EK 全局色表补齐；HSV 模式用 [0,0,0]（不变色）补齐。
		ensureEKArrowColors();

		// 确保窗口标题从预设中正确初始化
		if (data.windowTitlePreset != null) {
			data.windowTitle = data.windowTitlePreset;
		}

		// 从存档恢复 Fake OS / Psych 版本号，覆盖源码默认值
		MainMenuState.psychEngineVersion = data.fakePsychVersion;
		MainMenuState.osEngineVersion = data.fakeOSVersion;

		// 确保 FlxG 完全初始化后再应用设置
		if (FlxG.game != null) {
			// 应用固定时间步长设置
			FlxG.fixedTimestep = data.fixedTimestep;

			// 根据当前设置更新 FPS 计数器（updateFPSLayer 内部已调用 updateFPSCounterVisibility
			Main.updateFPSLayer();

			if(Main.gameLogVar != null)
				Main.gameLogVar.setEnabled(data.enableGameLog);


			#if (!html5 && !switch)
			FlxG.autoPause = ClientPrefs.data.autoPause;

			if(FlxG.save.data.framerate == null) {
				final refreshRate:Int = FlxG.stage.application.window.displayMode.refreshRate;
				data.framerate = Std.int(FlxMath.bound(refreshRate, 60, 240));
			}
			#end

			if (data.fpsRework)
				FlxG.stage.window.frameRate = data.framerate;
			else
			{
				if (data.framerate > FlxG.drawFramerate)
				{
					FlxG.updateFramerate = data.framerate;
					FlxG.drawFramerate = data.framerate;
				}
				else
				{
					FlxG.drawFramerate = data.framerate;
					FlxG.updateFramerate = data.framerate;
				}
			}
		}

		if(FlxG.save.data.gameplaySettings != null)
		{
			var savedMap:Map<String, Dynamic> = FlxG.save.data.gameplaySettings;
			for (name => value in savedMap)
				data.gameplaySettings.set(name, value);
		}

		// 兼容旧版设置：'kadehealth' 已更名为 'healthmodel'，迁移旧值并清除旧键
		if (FlxG.save.data.gameplaySettings != null)
		{
			var legacyMap:Map<String, Dynamic> = FlxG.save.data.gameplaySettings;
			if (legacyMap.exists('kadehealth') && !data.gameplaySettings.exists('healthmodel'))
				data.gameplaySettings.set('healthmodel', legacyMap.get('kadehealth'));
			data.gameplaySettings.remove('kadehealth');
			legacyMap.remove('kadehealth');
		}
		
		// flixel automatically saves your volume!
		if (FlxG.game != null) {
			if(FlxG.save.data.volume != null)
				FlxG.sound.volume = FlxG.save.data.volume;
			if (FlxG.save.data.mute != null)
				FlxG.sound.muted = FlxG.save.data.mute;
		}

		#if DISCORD_ALLOWED DiscordClient.check(); #end

		// controls on a separate save file
		var save:FlxSave = new FlxSave();
		save.bind('controls_v3', CoolUtil.getSavePath());
		if(save != null)
		{
			if(save.data.keyboard != null)
			{
				var loadedControls:Map<String, Array<FlxKey>> = save.data.keyboard;
				for (control => keys in loadedControls)
					if(keyBinds.exists(control)) keyBinds.set(control, keys);
			}
			if(save.data.gamepad != null)
			{
				var loadedControls:Map<String, Array<FlxGamepadInputID>> = save.data.gamepad;
				for (control => keys in loadedControls)
					if(gamepadBinds.exists(control)) gamepadBinds.set(control, keys);
			}
			if(save.data.mobile != null) {
				var loadedControls:Map<String, Array<MobileInputID>> = save.data.mobile;
				for (control => keys in loadedControls)
					if(mobileBinds.exists(control)) mobileBinds.set(control, keys);
			}
			reloadVolumeKeys();
		}
	}

	inline public static function getGameplaySetting(name:String, defaultValue:Dynamic = null, ?customDefaultValue:Bool = false):Dynamic
	{
		if(!customDefaultValue) defaultValue = defaultData.gameplaySettings.get(name);
		return /*PlayState.isStoryMode ? defaultValue : */ (data.gameplaySettings.exists(name) ? data.gameplaySettings.get(name) : defaultValue);
	}

	public static function reloadVolumeKeys()
	{
		TitleState.muteKeys = keyBinds.get('volume_mute').copy();
		TitleState.volumeDownKeys = keyBinds.get('volume_down').copy();
		TitleState.volumeUpKeys = keyBinds.get('volume_up').copy();
		toggleVolumeKeys(true);
	}
	public static function toggleVolumeKeys(?turnOn:Bool = true)
	{
		final emptyArray = [];
		FlxG.sound.muteKeys = (!Controls.instance.mobileC && turnOn) ? TitleState.muteKeys : emptyArray;
		FlxG.sound.volumeDownKeys = (!Controls.instance.mobileC && turnOn) ? TitleState.volumeDownKeys : emptyArray;
		FlxG.sound.volumeUpKeys = (!Controls.instance.mobileC && turnOn) ? TitleState.volumeUpKeys : emptyArray;
	}

	/** 检查一个 Dynamic 值是否是可 Reflect 的匿名对象（而非 null、数组或基本类型） */
	public static function _dynaIsObject(val:Dynamic):Bool
	{
		if (val == null) return false;
		try {
			// Reflect.fields 对基本类型和 null 会抛异常或返回空数组
			var fields = Reflect.fields(val);
			return fields != null && fields.length >= 0;
		} catch (e:Dynamic) { return false; }
	}

	/**
	 * 类型安全的 Reflect.setField。
	 * 只有类型兼容时才写值，否则跳过。返回 true 表示类型不匹配已跳过。
	 * 支持 Bool、Int、Float、String、Array<Int> 的安全写入。
	 * 用途：导出文件里的字段类型可能和新版代码不一致（比如 Bool 被改成 String），
	 *       用这个函数避免类型不匹配导致崩溃或数据损坏。
	 */
	public static function _safeSetField(target:Dynamic, key:String, newVal:Dynamic):Bool
	{
		try
		{
			var curVal:Dynamic = Reflect.field(target, key);

			// 当前值类型判断
			var curIsBool   = curVal is Bool;
			var curIsInt    = curVal is Int;
			var curIsFloat  = curVal is Float;
			var curIsString = curVal is String;
			var curIsArray  = curVal is Array;

			// 新值类型判断
			var newIsBool   = newVal is Bool;
			var newIsInt    = newVal is Int;
			var newIsFloat  = newVal is Float;
			var newIsString = newVal is String;
			var newIsArray  = newVal is Array;

			if (curIsBool && newIsBool)                     // Bool ↔ Bool
			{
				Reflect.setField(target, key, newVal);
				return false;
			}
			else if ((curIsInt || curIsFloat) && (newIsInt || newIsFloat))  // Int/Float ↔ Int/Float（互通）
			{
				Reflect.setField(target, key, curIsInt ? Std.int(newVal) : newVal);
				return false;
			}
			else if (curIsString && newIsString)            // String ↔ String
			{
				Reflect.setField(target, key, newVal);
				return false;
			}
			else if (curIsArray && newIsArray)              // Array ↔ Array
			{
				Reflect.setField(target, key, newVal);
				return false;
			}

			// 类型不匹配，跳过
			return true; // 返回 true = 已跳过（调用方用来计数）
		}
		catch (e:Dynamic) { return true; } // 任何异常也跳过
	}

	// ========================================================================
	// 设置导入导出功能 (Settings Import / Export)
	// ========================================================================

	// ---------- 导出 ----------

	/**
	 * 序列化 ClientPrefs 到 JSON-compatible 的 Dynamic 对象。
	 * config 决定包含哪些分区。
	 */
	public static function buildExportData(config:ExportConfig):Dynamic
	{
		var obj:Dynamic = cast {};
		Reflect.setField(obj, 'version', 1);
		Reflect.setField(obj, 'engine', 'KathyEngine');
		Reflect.setField(obj, 'exportDate', Date.now().toString());
		var sectionsArr:Array<String> = [];
		Reflect.setField(obj, 'sections', sectionsArr);

		// 1. SaveVariables 主设置
		if (config.includePrefs)
		{
			var prefsObj:Dynamic = cast {};
			for (key in Reflect.fields(data))
			{
				// gameplaySettings 单独处理
				if (key == 'gameplaySettings') continue;
				var val:Dynamic = Reflect.field(data, key);
				Reflect.setField(prefsObj, key, val);
			}
			Reflect.setField(obj, 'prefs', prefsObj);
			sectionsArr.push('prefs');
		}

		// 2. Keyboard 键位（FlxKey 枚举 → Int）
		if (config.includeKeyboard)
		{
			var kbObj:Dynamic = cast {};
			for (name => keys in keyBinds)
			{
				var intKeys:Array<Int> = [];
				for (k in keys) intKeys.push(Std.int(k));
				Reflect.setField(kbObj, name, intKeys);
			}
			Reflect.setField(obj, 'keyboard', kbObj);
			sectionsArr.push('keyboard');
		}

		// 3. Gamepad 键位
		if (config.includeGamepad)
		{
			var gpObj:Dynamic = cast {};
			for (name => keys in gamepadBinds)
			{
				var intKeys:Array<Int> = [];
				for (k in keys) intKeys.push(Std.int(k));
				Reflect.setField(gpObj, name, intKeys);
			}
			Reflect.setField(obj, 'gamepad', gpObj);
			sectionsArr.push('gamepad');
		}

		// 4. Mobile 键位
		if (config.includeMobile)
		{
			var mbObj:Dynamic = cast {};
			for (name => keys in mobileBinds)
			{
				var intKeys:Array<Int> = [];
				for (k in keys) intKeys.push(Std.int(k));
				Reflect.setField(mbObj, name, intKeys);
			}
			Reflect.setField(obj, 'mobile', mbObj);
			sectionsArr.push('mobile');
		}

		// 5. gameplaySettings Map → 普通对象
		if (config.includeGameplay)
		{
			var gsObj:Dynamic = cast {};
			for (name => value in data.gameplaySettings)
				Reflect.setField(gsObj, name, value);
			Reflect.setField(obj, 'gameplay', gsObj);
			sectionsArr.push('gameplay');
		}

		return obj;
	}

	/** 将导出数据编码为目标格式的字符串 */
	public static function encodeExport(data:Dynamic, format:String):String
	{
		var jsonStr:String = Json.stringify(data);

		switch (format)
		{
			case 'json':
				return jsonStr;
			case 'base64':
				var bytes:Bytes = Bytes.ofString(jsonStr);
				return EncodingUtils.base64Encode(bytes);
			case 'zlib':
				var raw:Bytes = Bytes.ofString(jsonStr);
				#if sys
				var compressed:Bytes = EncodingUtils.zlibCompress(raw);
				if (compressed != null)
					return EncodingUtils.base64Encode(compressed);
				else
					return EncodingUtils.base64Encode(raw); // 压缩失败降级到 base64
				#else
				// 非 sys 目标（html5 等）无 zlib，降级 base64
				return EncodingUtils.base64Encode(raw);
				#end
		}
		return jsonStr;
	}

	/** 一键导出：build + encode */
	public static function exportSettings(config:ExportConfig):String
	{
		return encodeExport(buildExportData(config), config.format);
	}

	// ---------- 导入 ----------

	/**
	 * 从字符串解码。自动检测格式（通过前缀 b64: / zlib: 或尝试 JSON 解析）。
	 * 返回 null 表示无法解析。
	 */
	public static function decodeImport(raw:String):Null<Dynamic>
	{
		if (raw == null || raw.trim().length == 0) return null;

		var trimmed = raw.trim();

		// 尝试直接 JSON 解析
		try {
			var obj = Json.parse(trimmed);
			if (obj != null && _dynaIsObject(obj))
				return obj;
		} catch (e:Dynamic) { /* 不是纯 JSON，继续尝试 */ }

		// 尝试 Base64 解码
		try {
			var decoded = EncodingUtils.base64Decode(trimmed);
			if (decoded != null)
			{
				// 先尝试作为 zlib 解压
				#if sys
				var decompressed = EncodingUtils.zlibDecompress(decoded);
				if (decompressed != null)
				{
					var jsonStr2:String = decompressed.toString();
					var obj2 = Json.parse(jsonStr2);
					if (obj2 != null && _dynaIsObject(obj2))
						return obj2;
				}
				#end

				// 直接作为 JSON 字符串解析
				var jsonStr:String = decoded.toString();
				var obj3 = Json.parse(jsonStr);
				if (obj3 != null && _dynaIsObject(obj3))
					return obj3;
			}
		} catch (e2:Dynamic) { /* 忽略 */ }

		return null;
	}

	/**
	 * 验证导入数据结构，返回可报告的 ImportResult（不含实际应用）。
	 * 用于 UI 预览"即将修改哪些选项"。
	 */
	public static function previewImport(raw:String):ImportResult
	{
		var result:ImportResult = new ImportResult();
		var importObj:Dynamic = decodeImport(raw);
		if (importObj == null)
		{
			result.success = false;
			result.errorMsg = '无法解析：输入不是有效的 JSON / Base64 / Zlib+Base64 格式';
			return result;
		}

		// 检查 version 字段是否存在（可选）
		if (!Reflect.hasField(importObj, 'prefs') && !Reflect.hasField(importObj, 'keyboard') &&
			!Reflect.hasField(importObj, 'gamepad') && !Reflect.hasField(importObj, 'mobile') &&
			!Reflect.hasField(importObj, 'gameplay'))
		{
			result.success = false;
			result.errorMsg = '数据格式不合法：未找到任何可识别的设置分区 (prefs/keyboard/gamepad/mobile/gameplay)';
			return result;
		}

		// 检测各分区
		if (Reflect.hasField(importObj, 'prefs'))
		{
			var prefsData:Dynamic = importObj.prefs;
			if (_dynaIsObject(prefsData))
			{
				result.appliedFieldCount = Reflect.fields(prefsData).length;
				result.loadedSections.push('prefs');
			}
			else
				result.skippedSections.push('prefs');
		}
		if (Reflect.hasField(importObj, 'keyboard'))
		{
			if (_dynaIsObject(importObj.keyboard)) result.loadedSections.push('keyboard');
			else result.skippedSections.push('keyboard');
		}
		if (Reflect.hasField(importObj, 'gamepad'))
		{
			if (_dynaIsObject(importObj.gamepad)) result.loadedSections.push('gamepad');
			else result.skippedSections.push('gamepad');
		}
		if (Reflect.hasField(importObj, 'mobile'))
		{
			if (_dynaIsObject(importObj.mobile)) result.loadedSections.push('mobile');
			else result.skippedSections.push('mobile');
		}
		if (Reflect.hasField(importObj, 'gameplay'))
		{
			if (_dynaIsObject(importObj.gameplay)) result.loadedSections.push('gameplay');
			else result.skippedSections.push('gameplay');
		}

		result.success = result.loadedSections.length > 0;
		if (!result.success)
			result.errorMsg = '数据存在但没有可应用的有效分区';

		return result;
	}

	/**
	 * 实际应用导入数据。返回 ImportResult（包含成功/失败信息）。
	 * @param raw 原始输入字符串
	 * @param applySections 可选——指定要应用的分区；null = 应用所有检测到的分区
	 */
	public static function applyImport(raw:String, ?applySections:Null<Array<String>>):ImportResult
	{
		var result = previewImport(raw);
		if (!result.success) return result;

		var importObj:Dynamic = decodeImport(raw);
		if (importObj == null)
		{
			result.success = false;
			result.errorMsg = '解析失败';
			return result;
		}

		// 决定要应用哪些分区
		var toApply:Array<String> = [];
		if (applySections != null)
		{
			for (s in applySections)
				if (result.loadedSections.contains(s)) toApply.push(s);
		}
		else
		{
			toApply = result.loadedSections.copy();
		}

		try
		{
			var typeMismatchSkipped:Int = 0;

			// 1. prefs —— 覆盖 ClientPrefs.data 的字段
			if (toApply.contains('prefs') && Reflect.hasField(importObj, 'prefs'))
			{
				var prefsData:Dynamic = Reflect.field(importObj, 'prefs');
				if (_dynaIsObject(prefsData))
				{
					for (key in Reflect.fields(prefsData))
					{
						if (key == 'gameplaySettings') continue;
						if (Reflect.hasField(data, key))
						{
							var newVal:Dynamic = Reflect.field(prefsData, key);
							if (newVal != null)
							{
								if (_safeSetField(data, key, newVal))
									typeMismatchSkipped++;
							}
						}
					}
				}
			}

			// 2. keyboard
			if (toApply.contains('keyboard') && Reflect.hasField(importObj, 'keyboard'))
			{
				var kbData:Dynamic = Reflect.field(importObj, 'keyboard');
				if (_dynaIsObject(kbData))
				{
					for (name in Reflect.fields(kbData))
					{
						if (keyBinds.exists(name))
						{
							var arr = Reflect.field(kbData, name);
							var newKeys:Array<FlxKey> = [];
							var keyArr:Array<Dynamic> = cast arr; for (k in keyArr) newKeys.push(cast Std.int(k));
							keyBinds.set(name, newKeys);
						}
					}
				}
			}

			// 3. gamepad
			if (toApply.contains('gamepad') && Reflect.hasField(importObj, 'gamepad'))
			{
				var gpData:Dynamic = Reflect.field(importObj, 'gamepad');
				if (_dynaIsObject(gpData))
				{
					for (name in Reflect.fields(gpData))
					{
						if (gamepadBinds.exists(name))
						{
							var arr = Reflect.field(gpData, name);
							var newKeys:Array<FlxGamepadInputID> = [];
							var keyArr:Array<Dynamic> = cast arr; for (k in keyArr) newKeys.push(cast Std.int(k));
							gamepadBinds.set(name, newKeys);
						}
					}
				}
			}

			// 4. mobile
			if (toApply.contains('mobile') && Reflect.hasField(importObj, 'mobile'))
			{
				var mbData:Dynamic = Reflect.field(importObj, 'mobile');
				if (_dynaIsObject(mbData))
				{
					for (name in Reflect.fields(mbData))
					{
						if (mobileBinds.exists(name))
						{
							var arr = Reflect.field(mbData, name);
							var newKeys:Array<MobileInputID> = [];
							var keyArr:Array<Dynamic> = cast arr; for (k in keyArr) newKeys.push(cast Std.int(k));
							mobileBinds.set(name, newKeys);
						}
					}
				}
			}

			// 5. gameplaySettings
			if (toApply.contains('gameplay') && Reflect.hasField(importObj, 'gameplay'))
			{
				var gsData:Dynamic = Reflect.field(importObj, 'gameplay');
				if (_dynaIsObject(gsData))
				{
					for (name in Reflect.fields(gsData))
					{
						var val:Dynamic = Reflect.field(gsData, name);
						data.gameplaySettings.set(name, val);
					}
				}
			}

			// 保存
			saveSettings();
			reloadVolumeKeys();

			result.typeMismatchCount = typeMismatchSkipped;
			if (typeMismatchSkipped > 0)
				result.errorMsg = Std.string(typeMismatchSkipped) + ' 个字段因类型不匹配被跳过（新版已变更这些设置的类型）';

			result.success = true;
		}
		catch (e:Dynamic)
		{
			result.success = false;
			result.errorMsg = '应用过程出错: ' + e;
			FlxG.log.error('ClientPrefs.applyImport 异常: ' + e);
		}

		return result;
	}
}

/** 简单的 Base64 + Zlib 工具（独立类，避免污染 ClientPrefs 主类） */
class EncodingUtils
{
	private static var _b64Chars:String = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

	/** 将 Bytes 做 Base64 编码 */
	public static function base64Encode(input:Bytes):String
	{
		var len:Int = input.length;
		var out:String = '';
		var i:Int = 0;
		while (i + 3 <= len)
		{
			var n:Int = (input.get(i) << 16) | (input.get(i + 1) << 8) | input.get(i + 2);
			out += _b64Chars.charAt((n >> 18) & 0x3F);
			out += _b64Chars.charAt((n >> 12) & 0x3F);
			out += _b64Chars.charAt((n >> 6) & 0x3F);
			out += _b64Chars.charAt(n & 0x3F);
			i += 3;
		}
		var remaining = len - i;
		if (remaining == 1)
		{
			var n2:Int = input.get(i) << 16;
			out += _b64Chars.charAt((n2 >> 18) & 0x3F);
			out += _b64Chars.charAt((n2 >> 12) & 0x3F);
			out += '==';
		}
		else if (remaining == 2)
		{
			var n3:Int = (input.get(i) << 16) | (input.get(i + 1) << 8);
			out += _b64Chars.charAt((n3 >> 18) & 0x3F);
			out += _b64Chars.charAt((n3 >> 12) & 0x3F);
			out += _b64Chars.charAt((n3 >> 6) & 0x3F);
			out += '=';
		}
		return out;
	}

	/** 解码 Base64 字符串为 Bytes；非法输入返回 null */
	public static function base64Decode(input:String):Null<Bytes>
	{
		if (input == null) return null;
		// 去除空白
		var s:String = ~/[ \t\r\n]/g.replace(input, '');
		var sLen:Int = s.length;
		if (sLen % 4 != 0) return null;

		var out:BytesOutput = new BytesOutput();
		var i:Int = 0;
		while (i < sLen)
		{
			var c0:Int = _b64Index(s.charAt(i));
			var c1:Int = _b64Index(s.charAt(i + 1));
			var c2:Int = _b64Index(s.charAt(i + 2));
			var c3:Int = _b64Index(s.charAt(i + 3));
			if (c0 < 0 || c1 < 0) return null;

			var n:Int = (c0 << 18) | (c1 << 12);
			if (c2 >= 0) n |= (c2 << 6);
			if (c3 >= 0) n |= c3;

			out.writeByte((n >> 16) & 0xFF);
			if (s.charAt(i + 2) != '=') out.writeByte((n >> 8) & 0xFF);
			if (s.charAt(i + 3) != '=') out.writeByte(n & 0xFF);

			i += 4;
		}
		return out.getBytes();
	}

	private static function _b64Index(c:String):Int
	{
		var idx = _b64Chars.indexOf(c);
		if (idx >= 0) return idx;
		if (c == '=') return -2; // padding
		return -1;
	}

	/** Zlib 压缩（Haxe 4 无内置 haxe.io.Compress，始终返回 null 降级） */
	public static function zlibCompress(input:Bytes):Null<Bytes>
	{
		// Haxe 4 无内置 zlib 支持；如需压缩，可引入 hxcompress 等第三方库
		return null;
	}
	public static function zlibDecompress(input:Bytes):Null<Bytes>
	{
		return null;
	}
}
