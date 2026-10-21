package objects;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.FlxObject;
import flixel.FlxCamera;
import flixel.FlxBasic;
import flixel.group.FlxGroup;
import flixel.math.FlxMath;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import backend.Paths;
import backend.Mods;
import backend.ClientPrefs;
import backend.CoolUtil;
import flixel.util.FlxSave;
import shaders.RoundedCornerShader;
import backend.Controls;
import states.PlayState;
import flixel.input.keyboard.FlxKey;
import openfl.display.Shape;
import openfl.display.BitmapData;
import openfl.display.BitmapDataChannel;
import openfl.geom.Matrix;
import openfl.geom.Point;
import openfl.geom.Rectangle;
#if MODS_ALLOWED
import sys.io.File;
import sys.FileSystem;
#end

/**
 * 游戏内按键显示覆盖层（KeyViewer）。
 * 复刻 JKPS 的 dark-minimalistic-nano + white-orange 主题：
 *   - 深色背景块 (25,25,25)，圆角 + 1px 描边
 *   - 按键本体为代码绘制的圆角深色块，圆角描边（默认白，按下立刻变橙黄）
 *   - 按下发光层为代码绘制的圆角橙黄填充，平滑淡入淡出（white-orange 的 Light animation 色 255,180,0）
 *   - 白色键名 (BlackSugarPlumCandy-Bold.ttf，支持中英日韩)
 *   - 显示 KPS / Total / Max
 *   - 可选资料条（ClientPrefs.keyViewerProfile）：左侧放圆角裁剪的自定义图标，底部显示自定义名字；
 *     没有图标（或选项关闭）时左侧不留空缺，按键在背景中垂直居中
 * 按键布局跟随玩家实际键位（原生 4 键），全部用矢量代码绘制，不依赖贴图。
 */
class KeyViewer extends FlxGroup
{
	// ---- 累计按键总数（独立存档，与主设置隔离，避免主设置损坏连累清零）----
	public static var keyViewerTotal:Int = 0;
	private static var keyViewerSave:FlxSave = null;

	/** 绑定并加载独立存档；旧版值若仍留在主设置里则一次性迁移过来。惰性调用。 */
	public static function initKeyViewerTotal():Void {
		if (keyViewerSave == null) {
			keyViewerSave = new FlxSave();
			keyViewerSave.bind('keyviewer_v1', CoolUtil.getSavePath());
		}
		if (keyViewerSave.data != null && keyViewerSave.data.total != null) {
			keyViewerTotal = keyViewerSave.data.total;
		} else if (FlxG.save != null && Reflect.hasField(FlxG.save.data, 'keyViewerTotal')) {
			// 兼容老存档：旧版曾把 keyViewerTotal 写进主设置，迁移到独立存档
			keyViewerTotal = Reflect.field(FlxG.save.data, 'keyViewerTotal');
			saveKeyViewerTotal(); // 落到独立存档，下一次就不再走迁移分支
		}
	}

	/** 把当前 keyViewerTotal 写入独立存档，返回是否成功刷盘。 */
	public static function saveKeyViewerTotal():Bool {
		if (keyViewerSave == null) initKeyViewerTotal();
		if (keyViewerSave.data == null) {
			FlxG.log.error('KeyViewer Total 保存失败（存档未绑定）');
			return false;
		}
		keyViewerSave.data.total = keyViewerTotal;
		var ok:Bool = keyViewerSave.flush();
		if (!ok) {
			FlxG.log.error('KeyViewer Total 保存失败（flush 返回 false），本次累计可能丢失');
		}
		return ok;
	}

	// ---- 主题配色（dark-minimalistic-nano）----
	static final BG_COLOR:FlxColor = 0xFF191919; // 25,25,25
	static final TEXT_COLOR:FlxColor = 0xFFFFFFFF; // 白色
	static final FONT_NAME:String = 'BlackSugarPlumCandy-Bold.ttf'; // 支持中英日韩
	static final KEY_NAME_SIZE:Int = 20;     // 按键名基础字号（长名字会自适应缩小以完整显示）
	static final KEY_NAME_MIN:Int = 9;       // 按键名最小字号下限
	static final KEY_NAME_PAD:Int = 6;      // 按键名左右内边距（防止贴边）

	// ---- 按键按钮尺寸 ----
	static final SLOT_W:Int = 46;     // 按键槽位宽度（= 按键视觉尺寸，使可视间隔等于 BTN_GAP）
	static final BTN_SIZE:Int = 46;   // 实际按键视觉尺寸
	static final BTN_GAP:Int = 5;
	static final KEY_AREA_PAD:Int = 8; // 按键在按键区内上下内边距（up 模式即顶边留白，与键距 BTN_GAP 解耦）
	static final TEXT_AREA_W:Int = 100; // 按键右侧统计文本区宽度（有图标时仅作图标最大边长上限，不再占固定宽度）

	// ---- 描边（圆角描边，复刻 white-orange 主题）----
	static final BORDER_THICK:Int = 3;            // 按键描边厚度（像素）
	static final BORDER_COLOR:FlxColor = 0xFFFFFFFF; // 描边默认色（白）
	static final PRESS_COLOR:FlxColor = 0xFFFFB400;  // 按下高亮色（白橙主题：橙黄 255,180,0）
	static final CAP_COLOR:FlxColor = 0xFF1E1E1E;    // 按键本体深色（JKPS button 30,30,30）
	static final GLOW_ALPHA_MAX:Float = 0.65;        // 按下发光层最大不透明度
	static final KEY_RADIUS:Float = 10;              // 按键圆角半径
	static final BG_BORDER_THICK:Int = 1;            // 背景描边厚度（1px）
	static final BG_RADIUS:Float = 18;               // 背景圆角半径（稍大）

	// ---- 可选的「图标 + 名字」资料条（ClientPrefs.keyViewerProfile）----
	static final NAME_FONT_SIZE:Int = 15;
	static final NAME_TOP_PAD:Int = 4;      // 名字条与按键描边的间距（紧贴正下方）
	static final NAME_BOTTOM_PAD:Int = 6;   // 名字条底部与背景底边间距（略宽）
	static final NAME_LINE_GAP:Int = 8;     // 名字单行额外行高（受控，不依赖字体自带大行距）
	static final ICON_PAD:Int = 8;        // 图标距左侧区域边缘的内边距
	static final ICON_RADIUS:Float = 10;  // 图标圆角裁剪半径（实际角半径，单位像素）
	static final ICON_KEYS:Array<String> = ['keyViewer/icon', 'keyviewer/icon']; // 图标查找路径（大小写兼容）
	static final NAME_FILES:Array<String> = ['images/keyViewer/name.txt', 'images/keyviewer/name.txt'];
	static final DEFAULT_NAME:String = 'PLAYER';

	// ---- 按键轨迹可视化（复刻 JKPS Key press visualization）----
	static final VIS_SPEED:Float = 300;       // 默认每秒向上移动/拉长速度（像素/秒，与帧率无关）
	static final FADE_DIST:Float = 500;       // 飘出消失距离（Fade out distance）
	static final MAX_STRETCH:Float = 250;     // 按住时长条最大拉长量（上限）
	static final FADE_LINE:Float = 200;       // 遮罩线：距按键顶端 200px，白块超出此线被裁切渐隐
	static final VIS_SPAWN_Y:Float = 0;       // 生成位置相对按钮顶端的偏移（0 = 恰好在按键描边顶部）
	static final PARTICLE_H:Float = 16;       // 单条轨迹粒子高度
	static final POOL_PER_KEY:Int = 12;       // 每键粒子池容量（上限同时存在的轨迹数）
	static final DOWN_TRAIL_AREA:Int = 120;   // 下落模式下面板整体上移的像素，给按键下方留出屏幕空隙绘制向下轨迹

	var keysArray:Array<String>;
	var keyCaps:Array<FlxSprite> = [];   // 按键本体（圆角深色填充）
	var keyBorders:Array<FlxSprite> = []; // 按键圆角描边外框（按下时颜色立刻变橙黄）
	var keyGlows:Array<FlxSprite> = [];  // 按键按下发光层（圆角橙黄，平滑淡入淡出）
	var keyLabels:Array<FlxText> = [];
	var keyPressGlow:Array<Float> = []; // 发光层按下强度 0..1（平滑动画）

	// 按键轨迹可视化粒子：particles[i] = 第 i 个键的粒子池
	// 按住时该条从按键顶端持续向上"拉长"（stretch 增长），松开后整条上飘（drift 增长）
	var particles:Array<Array<FlxSprite>> = [];
	var particleStretch:Array<Array<Float>> = []; // 按住期间已拉长量
	var particleDrift:Array<Array<Float>> = [];   // 松开后已上飘量
	var particleHolding:Array<Array<Bool>> = [];  // 该条当前是否仍处于按住状态
	var particleAnchorY:Array<Array<Float>> = []; // 长条锚定 y（上升=按键顶端，下落=按键底端）
	var particleDown:Array<Array<Bool>> = []; // 每个粒子的轨迹方向：true=向下，false=向上

	var statsText:FlxText; // 右侧 KPS / Total / Max（单行多行文本，收紧行距）

	var iconSprite:FlxSprite; // 左侧自定义图标（可为 null）
	var nameText:FlxText;     // 底部自定义名字（可为 null）
	public var bgSprite:FlxSprite = null; // 背景面板（供位置校准界面做拖动命中检测）
	public var viewerCam:FlxCamera = null; // 自定义相机：位置校准/预览态注入 camHUD；游戏内用 camOther

	var keyTimes:Array<Float> = []; // 最近一次按下的时间戳（毫秒），用于计算 KPS
	var totalKeys:Int = 0;
	var maxKps:Int = 0; // 峰值 KPS

	var startTime:Float = 0;
	var saveDirty:Bool = false;   // Total 发生变化，待落盘
	var lastSaveAt:Float = -9999; // 上次落盘时间（毫秒），用于节流

	public function new()
	{
		super();

		// 累计按键总数：从独立持久存档读取，跨游戏重启保留（惰性加载）
		if (keyViewerSave == null) initKeyViewerTotal();
		totalKeys = keyViewerTotal;

		rebuild();
	}

	/**
	 * 重建 KeyViewer 全部视觉元素（背景、图标、名字、按键、统计文本）。
	 * changekeycount 中途触发时，PlayState.keysArray.length 变化，update() 检测到后调用此方法，
	 * dispose 旧布局后按新键数重建，保持与谱面当前键数一致。
	 * new() 里调一次，之后 update() 里按需自动调。
	 */
	private function rebuild():Void
	{
		// 先 dispose 全部旧成员（FlxSprite / FlxText / Shape 等），防止 GPU 纹理泄漏；
		// FlxGroup.dispose 会把 members 里的 FlxBasic 全部 destroy 并 dispose，但不清空 members，
		// 后续 add() 会追加到新数组。为安全起见同时清空按键相关缓存数组。
		for (m in members) { if (m != null) m.destroy(); }
		members = [];
		keyCaps = []; keyBorders = []; keyGlows = []; keyLabels = []; keyPressGlow = [];
		particles = []; particleStretch = []; particleDrift = [];
		particleHolding = []; particleAnchorY = []; particleDown = [];
		if (bgSprite != null) { bgSprite = null; }
		if (statsText != null) { statsText = null; }
		if (iconSprite != null) { iconSprite = null; }
		if (nameText != null) { nameText = null; }

		// 读取玩家实际键位（固定 4 键 action 列表）；位置校准/预览态无 PlayState 时用默认 4K 布局
		keysArray = (PlayState.instance != null)
			? PlayState.instance.keysArray.copy()
			: ['note_left', 'note_down', 'note_up', 'note_right'];

		var nKeys:Int = keysArray.length;
		// 布局使用固定槽位 SLOT_W，使背景面板尺寸不随按键视觉大小变化
		var totalWidth:Int = nKeys * SLOT_W + (nKeys - 1) * BTN_GAP;

		// ---- 资料条（左侧图标 + 底部名字）----
		var profileOn:Bool = ClientPrefs.data.keyViewerProfile;
		// 左侧图标：支持 png 静图 / gif 动图 / 精灵图集(idle 动画)，按文件后缀自动兼容
		var iconBmp:BitmapData = null; // 仅静图使用，供圆角裁剪
		var iconObj:FlxSprite = null;  // 非静图显示对象（gif 为 FlxGifSprite，精灵为 FlxSprite）
		var iconSrcW:Int = 0;          // 源图自然尺寸，用于等比缩放
		var iconSrcH:Int = 0;
		if (profileOn)
		{
			var info = findIconInfo();
			if (info != null)
			{
				switch (info.type)
				{
				case 'gif':
					var g = new FlxGifSprite(0, 0);
					// mods 覆盖优先：mods 下的 gif 是绝对文件系统路径，必须读成字节再喂给 loadGif，
					// 否则 Assets.getBytes 会把 Windows 盘符 E: 误判为“资源库名:路径”分隔符而崩溃。
					// 解析失败时（无 mods 覆盖 / 无内置 gif）退回相对资源路径字符串（与 aris.gif 加载一致，可正常读取）。
					var loaded:Bool = false;
					#if MODS_ALLOWED
					var gifBytes:haxe.io.Bytes = resolveGifBytes(info.key);
					if (gifBytes != null) { g.loadGif(gifBytes); loaded = true; }
					#end
					if (!loaded)
						g.loadGif('assets/shared/images/' + info.key + '.gif');
					g.antialiasing = ClientPrefs.data.antialiasing;
						iconObj = g;
						iconSrcW = Std.int(g.width);
						iconSrcH = Std.int(g.height);
					case 'sprite':
						var s = new FlxSprite(0, 0);
						try { s.frames = Paths.getSparrowAtlas(info.key); } catch (e:Dynamic) {}
						if (s.frames != null && s.frames.numFrames > 0)
						{
							// 优先按 idle 前缀；无 idle 帧则把全部帧作为 idle 循环播放
							var idlePrefix:String = null;
							for (f in s.frames.frames)
							{
								if (f.name.toLowerCase().indexOf('idle') >= 0) { idlePrefix = 'idle'; break; }
							}
							if (idlePrefix != null)
								s.animation.addByPrefix('idle', idlePrefix, 24, true);
							else
							{
								var idx:Array<Int> = [for (i in 0...s.frames.numFrames) i];
								s.animation.add('idle', idx, 24, true);
							}
							s.animation.play('idle');
							s.antialiasing = ClientPrefs.data.antialiasing;
							iconObj = s;
							iconSrcW = Std.int(s.width);
							iconSrcH = Std.int(s.height);
						}
					default: // 'png' 静图
						// 必须 allowGPU=false：本引擎在 GPU 缓存开启时会丢弃位图的 CPU surface，
						// 之后用 BitmapData.draw 绘制它会触发 Cairo 段错误（cairo_paint）。
						var graphic = Paths.image(info.key, null, false);
						if (graphic != null && graphic.bitmap != null && graphic.bitmap.width > 0 && graphic.bitmap.height > 0)
						{
							iconBmp = graphic.bitmap;
							iconSrcW = iconBmp.width;
							iconSrcH = iconBmp.height;
						}
				}
			}
		}
		var hasIcon:Bool = (iconBmp != null || iconObj != null);

		// 按键区高度：按键在区内垂直居中所需的上下内边距（KEY_AREA_PAD），与键距 BTN_GAP 解耦
		var keyAreaH:Int = BTN_SIZE + KEY_AREA_PAD * 2;

		// 左侧区域宽度：与右侧统计区等宽（TEXT_AREA_W），达成左右对称；无图标时收起为 0
		var leftW:Int = hasIcon ? TEXT_AREA_W : 0;

		// 背景宽度：左侧区域 + 两侧留白 + 按键区 + 右侧统计区（不依赖名字条高度，先算出来用于创建名字文本）
		var bgW:Int = leftW + BTN_GAP * 2 + totalWidth + TEXT_AREA_W;

		// 底部名字文本（资料条开启时始终显示，可多行；先创建以定位）
		var nameBandH:Float = 0;
		if (profileOn)
		{
			nameText = new FlxText(0, 0, bgW, getProfileName(), NAME_FONT_SIZE);
			nameText.setFormat(Paths.font(FONT_NAME), NAME_FONT_SIZE, TEXT_COLOR, CENTER);
			nameText.scrollFactor.set(0, 0);
			// 用受控行高计算文本块高度，不信任字体自带的大行距/度量，避免背景被撑爆或文本溢出
			var lineCount:Int = getProfileName().split('\n').length;
			nameBandH = lineCount * (NAME_FONT_SIZE + NAME_LINE_GAP);
		}

		// 轨迹方向（按下时确定，整局不变）：下落模式需把名字移到按键上方，
		// 并在按键下方预留可见轨迹区，否则向下生成的白块会直接冲出屏幕底部。
		var downTrail:Bool = trailGoesDown();

		// 面板总高度：名字带 + 按键区（下落模式的向下轨迹绘制在面板外的屏幕空隙中，不计入面板高度）
		var bgH:Int;
		if (downTrail)
		{
			bgH = Math.ceil(NAME_TOP_PAD + nameBandH + NAME_BOTTOM_PAD + keyAreaH);
		}
		else
		{
			bgH = Math.ceil((keyAreaH + BTN_SIZE) / 2 + NAME_TOP_PAD + nameBandH + NAME_BOTTOM_PAD);
		}

		// 左侧图标：在左侧框内等比自适应缩放以填充。
		// 缩放上限取「左侧框宽」与「整块面板高度」较小者：宽度上限=左侧框宽（保持左右对称），
		// 高度上限=整块面板高度（图标在左列、名字在按键下方，不同列不重叠，可随面板撑满左列，
		// 消除“小图大框”的空旷感）。
		var iconW:Int = 0;
		var iconH:Int = 0;
		if (hasIcon)
		{
			var maxW:Float = leftW - ICON_PAD * 2; // 左侧框宽上限（无图标时 leftW=0，不会进入此分支）
			var maxH:Float = bgH - ICON_PAD * 2;   // 整块面板高度上限
			var sc:Float = Math.min(maxW / iconSrcW, maxH / iconSrcH);
			iconW = Std.int(Math.max(1, Math.round(iconSrcW * sc)));
			iconH = Std.int(Math.max(1, Math.round(iconSrcH * sc)));
		}
		var bgX:Float = (FlxG.width - bgW) / 2; // 整个面板居中于屏幕
		// 下落模式：面板整体上移 DOWN_TRAIL_AREA，给按键下方的向下轨迹留出屏幕空隙
		var bottomGap:Float = downTrail ? DOWN_TRAIL_AREA : 0;
		var bgY:Float = FlxG.height - bgH - 6 - bottomGap;

		// 用户自定义位置偏移（在设置内通过拖动校准，持久化保存）；应用于整块面板
		bgX += ClientPrefs.data.keyViewerPosX;
		bgY += ClientPrefs.data.keyViewerPosY;

		// 按键垂直位置：下落模式紧贴名字带下方（随名字增长整体上移、按键屏位置不变）；上升模式在按键区内居中
		var yPos:Float = downTrail
			? bgY + NAME_TOP_PAD + nameBandH + NAME_BOTTOM_PAD
			: bgY + (keyAreaH - BTN_SIZE) / 2;

		// 背景面板（圆角 + 1px 描边）
		var bg = makeRoundRect(bgW, bgH, BG_COLOR, BG_BORDER_THICK, BORDER_COLOR, BG_RADIUS);
		bg.setPosition(bgX, bgY);
		bgSprite = bg;
		bg.alpha = 0.85;
		bg.scrollFactor.set(0, 0);
		add(bg);

		// 左侧自定义图标：已在前面按实际尺寸缩放（iconW×iconH）+ 圆角裁剪；
		// 左侧区域宽度已紧贴图标，这里只需居中对齐即可。
		if (hasIcon)
		{
			var icon:FlxSprite;
			if (iconBmp != null)
			{
				icon = new FlxSprite();
				icon.loadGraphic(makeRoundedBitmap(iconBmp, iconW, iconH, ICON_RADIUS));
				icon.antialiasing = ClientPrefs.data.antialiasing;
			}
			else
			{
				icon = iconObj; // gif / 精灵：已加载且正在播放动画
				icon.setGraphicSize(iconW, iconH);
				icon.updateHitbox();
				icon.antialiasing = ClientPrefs.data.antialiasing;
				// 动画精灵无法像 png 那样预渲染圆角位图，改用 GPU shader 按 UV 裁剪圆角，
				// 与 png 的 makeRoundedBitmap 视觉效果一致（uSize 用显示尺寸，半径用 ICON_RADIUS）。
				// 注意：uSize/uRadius 由 FlxShader 宏在子类上生成，必须用 RoundedCornerShader 类型变量持有。
				var rc:RoundedCornerShader = new RoundedCornerShader();
				rc.uSize.value = [iconW, iconH];
				rc.uRadius.value = [ICON_RADIUS];
				icon.shader = rc;
			}
			icon.setPosition(
				Math.round(bgX + (leftW - iconW) / 2),
				Math.round(bgY + (bgH - iconH) / 2)); // 含名字条的整块内垂直居中
			icon.scrollFactor.set(0, 0);
			add(icon);
			iconSprite = icon;
		}

		// 按键区域起点（左侧区域 + 内边距）
		var keyStartX:Float = bgX + leftW + BTN_GAP;

		for (i in 0...nKeys)
		{
			var slotX:Float = keyStartX + i * (SLOT_W + BTN_GAP);
			var bx:Float = slotX + (SLOT_W - BTN_SIZE) / 2;

			// 按键本体：圆角深色填充（替代 Button.png 贴图）
			var cap = makeRoundRect(BTN_SIZE, BTN_SIZE, CAP_COLOR, 0, 0, KEY_RADIUS);
			cap.setPosition(bx, yPos);
			cap.scrollFactor.set(0, 0);
			add(cap);
			keyCaps.push(cap);

			// 按键按下发光层：圆角橙黄填充，alpha 平滑变化（替代 Animation.png）
			var glow = makeRoundRect(BTN_SIZE, BTN_SIZE, PRESS_COLOR, 0, 0, KEY_RADIUS);
			glow.setPosition(bx, yPos);
			glow.scrollFactor.set(0, 0);
			glow.alpha = 0;
			glow.scale.set(0.85, 0.85);
			add(glow);
			keyGlows.push(glow);

			// 预建该键的轨迹可视化粒子池（按下时激活：先拉长，松开后上飘消失）
			// 在描边之前 add，使轨迹绘制在描边之下（描边最后绘制，盖在轨迹之上）
			var pPool:Array<FlxSprite> = [];
			var pStretch:Array<Float> = [];
			var pDrift:Array<Float> = [];
			var pHolding:Array<Bool> = [];
			var pAnchor:Array<Float> = [];
			var pDown:Array<Bool> = [];
			var pW:Float = BTN_SIZE; // 轨迹条宽度跟随按键（描边）宽度
			for (p in 0...POOL_PER_KEY)
			{
				var pSpr = new FlxSprite(bx + (BTN_SIZE - pW) / 2, yPos);
				pSpr.makeGraphic(Math.round(pW), Math.round(PARTICLE_H), TEXT_COLOR);
				pSpr.scrollFactor.set(0, 0);
				pSpr.visible = false;
				pSpr.active = false;
				add(pSpr);
				pPool.push(pSpr);
				pStretch.push(0);
				pDrift.push(0);
				pHolding.push(false);
				pAnchor.push(0);
				pDown.push(false);
			}
			particles.push(pPool);
			particleStretch.push(pStretch);
			particleDrift.push(pDrift);
			particleHolding.push(pHolding);
			particleAnchorY.push(pAnchor);
			particleDown.push(pDown);

			// 按键圆角描边外框（按下时颜色立刻切换，不与发光层共用缓动）
			// 放在轨迹之后 add，使其绘制在轨迹之上（轨迹位于描边之下）
			var border = makeRoundRect(BTN_SIZE, BTN_SIZE, FlxColor.TRANSPARENT, BORDER_THICK, BORDER_COLOR, KEY_RADIUS);
			border.setPosition(bx, yPos);
			border.scrollFactor.set(0, 0);
			add(border);
			keyBorders.push(border);

			// 键名文字（真实物理按键），字号自适应：名字过长时缩小以完整显示于按键内
			var keyName:String = getKeyName(keysArray[i]);
			var label = new FlxText(bx, yPos, BTN_SIZE, keyName, KEY_NAME_SIZE);
			label.setFormat(Paths.font(FONT_NAME), KEY_NAME_SIZE, TEXT_COLOR, CENTER);
			// 自适应：先按自动宽度测量真实像素宽，超出则等比缩小字号（下限 KEY_NAME_MIN）
			label.fieldWidth = 0;
			var natW:Float = label.width;
			if (natW > BTN_SIZE - KEY_NAME_PAD)
			{
				var fit:Int = Math.floor(KEY_NAME_SIZE * (BTN_SIZE - KEY_NAME_PAD) / natW);
				if (fit < KEY_NAME_MIN) fit = KEY_NAME_MIN;
				label.size = fit;
				label.setFormat(Paths.font(FONT_NAME), fit, TEXT_COLOR, CENTER);
			}
			label.fieldWidth = BTN_SIZE; // 恢复按字段宽度居中对齐
			label.x = bx;
			label.y = yPos + (BTN_SIZE - label.height) / 2;
			label.scrollFactor.set(0, 0);
			add(label);
			keyLabels.push(label);

			keyPressGlow.push(0.0);
		}

		// 右侧 KPS / Total / Max：用单个多行文本，行距收紧（STAT_LINE_GAP），并在按键区内垂直居中
		var textX:Float = keyStartX + totalWidth + BTN_GAP;
		var textW:Float = TEXT_AREA_W - BTN_GAP;
		statsText = new FlxText(textX, 0, textW, 'KPS: 0\nTotal: 0\nMax: 0', 14);
		statsText.setFormat(Paths.font(FONT_NAME), 14, TEXT_COLOR, LEFT);
		statsText.fieldWidth = 0; // 禁用 fieldWidth 限制，防止 Total 达到6位及以上时文本换行
		statsText.scrollFactor.set(0, 0);
		statsText.y = Math.round(yPos + (BTN_SIZE - statsText.height) / 2);
		add(statsText);

		// 底部/顶部名字：随轨迹方向切换位置，水平居中于按键区中心
		if (nameText != null)
		{
			// 以「按键区」中心为基准水平居中（而非整个面板，避免右侧统计区把名字挤偏）
			var keyCenterX:Float = keyStartX + totalWidth / 2;
			nameText.x = Math.round(keyCenterX - bgW / 2);
			if (downTrail)
			{
				// 下落模式：名字置于面板顶部（按键上方），腾出按键下方给向下轨迹
				nameText.y = Math.round(bgY + NAME_TOP_PAD + Math.max(0, (nameBandH - nameText.height) / 2));
			}
			else
			{
				// 上升模式：名字紧贴按键描边正下方，并在文本带内垂直居中（兼容多行）
				var keyBottom:Float = yPos + BTN_SIZE;
				var nameTopY:Float = keyBottom + NAME_TOP_PAD;
				nameText.y = Math.round(nameTopY + Math.max(0, (nameBandH - nameText.height) / 2));
			}
			add(nameText);
		}

		// 全部挂到相机（默认 camOther；位置校准/预览态用注入的 viewerCam）
		var useCam:FlxCamera = (viewerCam != null)
			? viewerCam
			: ((PlayState.instance != null) ? PlayState.instance.camOther : null);
		for (member in members)
		{
			if (member != null && Std.isOfType(member, FlxSprite))
				member.cameras = (useCam != null) ? [useCam] : null;
		}

		startTime = FlxG.game.ticks;
	}

	override public function update(elapsed:Float):Void
	{
		super.update(elapsed);

		// changekeycount 中途触发时，PlayState.keysArray.length 会变；
		// 检测到变化后重建整个布局（背景/图标/按键/统计全部按新键数重建），
		// 保证 KeyViewer 与谱面当前键数保持一致。纯 4K / 纯多K 谱面（无 changekeycount 事件）无额外开销。
		if (PlayState.instance != null && PlayState.instance.keysArray.length != keysArray.length)
		{
			rebuild();
			return; // 本帧已重建，跳过后续按键状态更新（下一帧正常渲染）
		}

		var now:Float = FlxG.game.ticks;
		// 校准/预览态无 PlayState 时（无 controls），跳过按键交互逻辑，避免空引用
		if (PlayState.instance == null || PlayState.instance.controls == null)
			return;
		var controls = PlayState.instance.controls;
		// Botplay / Replay 模式下不计入按键 Total（仍保留 KPS、Max 与按下时的白块显示）
		var countTotal:Bool = !PlayState.instance.cpuControlled && !PlayState.instance.isReplaying;
		// 'off' 时完全关闭按键轨迹可视化（不生成也不更新白块）
		var trailEnabled:Bool = ClientPrefs.data.keyViewerTrail != 'off';

		for (i in 0...keysArray.length)
		{
			var action:String = keysArray[i];
			var glow = keyGlows[i];

			// 发光层按下强度（0→1 淡入，1→0 淡出），用于平滑动画
			var target:Float = controls.pressed(action) ? 1.0 : 0.0;
			keyPressGlow[i] = FlxMath.lerp(target, keyPressGlow[i], Math.exp(-elapsed * 18));

			// 按键描边：按下立刻切换为橙黄，松开立刻恢复白色（与发光动画不同）
			keyBorders[i].color = controls.pressed(action) ? PRESS_COLOR : BORDER_COLOR;

			// 发光层：圆角橙黄填充，平滑淡入淡出 + 轻微缩放
			glow.alpha = keyPressGlow[i] * GLOW_ALPHA_MAX;
			glow.scale.set(
				FlxMath.lerp(0.85, 1.0, keyPressGlow[i]),
				FlxMath.lerp(0.85, 1.0, keyPressGlow[i]));

			if (controls.justPressed(action))
			{
				keyTimes.push(now);
				if (countTotal)
				{
					totalKeys++;
					saveDirty = true; // Total 变化，待落盘
				}
				if (trailEnabled) spawnTrail(i); // 生成一条轨迹长条（方向由设置决定）
			}

			if (trailEnabled) { // 关闭轨迹可视化时跳过整段粒子更新
			// 更新该键的所有轨迹粒子
			var pool:Array<FlxSprite> = particles[i];
			var stretch:Array<Float> = particleStretch[i];
			var drift:Array<Float> = particleDrift[i];
			var holding:Array<Bool> = particleHolding[i];
			var anchorY:Array<Float> = particleAnchorY[i];

			for (p in 0...pool.length)
			{
		var spr:FlxSprite = pool[p];
		if (!spr.active) continue;
		var d:Bool = particleDown[i][p]; // 该粒子轨迹方向：true=下落，false=上升

		if (holding[p])
		{
			if (controls.pressed(action))
			{
				// 按住中：长条从 0 高度向上拉长，到遮罩线(200)即暂停（封顶不再变长）
				stretch[p] = Math.min(FADE_LINE, stretch[p] + ClientPrefs.data.keyViewerTrailSpeed * elapsed);
			}
			else
			{
				// 刚松开：转为飘走阶段（整体上飘、淡出回收）
				holding[p] = false;
			}
		}
		else
			{
				// 已松开：整条沿轨迹方向飘走（高度保持），漂移量同步更新 spr.y
				drift[p] += ClientPrefs.data.keyViewerTrailSpeed * elapsed;
			spr.y += d ? ClientPrefs.data.keyViewerTrailSpeed * elapsed : -ClientPrefs.data.keyViewerTrailSpeed * elapsed; // 下落 / 上升
			}

		// 长条高度完全由 stretch 决定（stretch=0 即最小高度≈0，瞬间点击不产生高块）
		var h:Float = Math.max(1, stretch[p]);
		spr.setGraphicSize(Math.round(BTN_SIZE), Math.round(h));
		spr.updateHitbox();
		if (holding[p])
		{
			// 按住中：钉住锚点，顶部/底边随 stretch 变化，不叠加漂移
			spr.y = d ? anchorY[p] : anchorY[p] - h;
			spr.alpha = 1;
		}
		// 飘走阶段：spr.y 已在上面累加，这里不再重设

			// 剪辑与移动同步完成：在统一应用 spr.y 之后立即计算 clipRect
			// 遮罩线：上升=按键顶端上方 FADE_LINE；下落=按键底端下方 FADE_LINE。
			// clipRect 使用帧坐标，需按 scale.y 换算屏幕差值。
			var fadeLineY:Float = d ? (anchorY[p] + FADE_LINE) : (anchorY[p] - FADE_LINE);
			var lineLocalTex:Float = (fadeLineY - spr.y) / spr.scale.y;
			if (d) // 下落：保留线以上部分
			{
				if (lineLocalTex <= 0)
					spr.clipRect = new flixel.math.FlxRect(0, 0, spr.frameWidth, 0);
				else if (lineLocalTex >= spr.frameHeight)
					spr.clipRect = null;
				else
					spr.clipRect = new flixel.math.FlxRect(0, 0, spr.frameWidth, lineLocalTex);
			}
			else // 上升：保留线以下部分
			{
				if (lineLocalTex <= 0)
					spr.clipRect = null;
				else if (lineLocalTex >= spr.frameHeight)
					spr.clipRect = new flixel.math.FlxRect(0, 0, spr.frameWidth, 0);
				else
					spr.clipRect = new flixel.math.FlxRect(0, lineLocalTex, spr.frameWidth, spr.frameHeight - lineLocalTex);
			}

			// 飘走阶段整体淡出
			if (!holding[p])
				spr.alpha = Math.max(0, spr.alpha - (ClientPrefs.data.keyViewerTrailSpeed / FADE_DIST) * elapsed);

		// 回收：仅飘走阶段，整条越过遮罩线（上升=底部到线以上，下落=顶部到线以下）或 alpha 归零
		var bottomY:Float = spr.y + spr.height;
		var passed:Bool = d ? (spr.y >= fadeLineY) : (bottomY <= fadeLineY);
		if (!holding[p] && (spr.alpha <= 0.001 || passed))
			{
				spr.visible = false;
				spr.active = false;
				spr.alpha = 0;
				spr.clipRect = null;
			}
			}
			}
		}

		// 计算 KPS（最近 1 秒内的按键数）
		var cutoff:Float = now - 1000;
		while (keyTimes.length > 0 && keyTimes[0] < cutoff)
			keyTimes.shift();

		var currentKps:Int = keyTimes.length;
		if (currentKps > maxKps)
			maxKps = currentKps;

		if (statsText != null)
			statsText.text = 'KPS: ' + currentKps + '\nTotal: ' + totalKeys + '\nMax: ' + maxKps;

		// 节流落盘：Total 变化后至少每 1 秒写一次，避免每次按键都刷盘
		if (saveDirty && now - lastSaveAt > 1000)
			flushTotal();
	}

	// 将累计 Total 写入持久存档（ClientPrefs 会自动保存）
	function flushTotal():Void
	{
		if (keyViewerTotal != totalKeys)
		{
			keyViewerTotal = totalKeys;
			saveKeyViewerTotal();
		}
		saveDirty = false;
		lastSaveAt = FlxG.game.ticks;
	}

	override function destroy():Void
	{
		// 销毁前兜底保存，防止漏掉最后一秒内的按键
		if (saveDirty)
			flushTotal();
		super.destroy();
	}

	// 根据设置决定轨迹方向：'down'=强制下落，'up'=强制上升，'auto'=跟随游戏内 downscroll 设置
	function trailGoesDown():Bool
	{
		return switch (ClientPrefs.data.keyViewerTrail)
		{
			case 'down': true;
			case 'auto': !ClientPrefs.data.downScroll; // auto 与 downscroll 相反：非下落时白块向下
			default: false; // 'up' 或未知值
		}
	}

	/**
	 * 整体平移整个 KeyViewer（位置校准界面拖动用）。
	 * 直接累加每个成员的屏幕坐标；偏移量由调用方记录到 ClientPrefs。
	 */
	public function moveBy(dx:Float, dy:Float):Void
	{
		for (m in members)
		{
			if (m != null && Std.isOfType(m, FlxObject))
			{
				var o:FlxObject = cast m;
				o.x += dx;
				o.y += dy;
			}
		}
	}

	/**
	 * 在第 i 个键顶部生成一条轨迹粒子（按键轨迹可视化）。
	 * 从粒子池中取一个未激活的，重置位置/透明度/进度后激活。
	 */
	function spawnTrail(i:Int):Void
	{
		var pool:Array<FlxSprite> = particles[i];
		var stretch:Array<Float> = particleStretch[i];
		var drift:Array<Float> = particleDrift[i];
		var holding:Array<Bool> = particleHolding[i];
		var anchorY:Array<Float> = particleAnchorY[i];
		var pDownArr:Array<Bool> = particleDown[i];
		var down:Bool = trailGoesDown(); // 本次生成的轨迹方向（按下时确定，全程不变）

		// 快速连按：先把该键仍在"按住"状态的上一条转成飘走，避免多条长条根部重叠
		for (q in 0...pool.length)
		{
			if (pool[q].active && holding[q])
				holding[q] = false;
		}

		for (p in 0...pool.length)
		{
			if (!pool[p].active)
			{
				var spr:FlxSprite = pool[p];
			var btn:FlxSprite = keyCaps[i];
			var pW:Float = BTN_SIZE; // 轨迹条宽度跟随按键（描边）宽度
			pDownArr[p] = down;
			// 上升：锚定按键顶端，长条由此向上延伸；下落：锚定按键底端，长条由此向下延伸
			anchorY[p] = down ? (btn.y + BTN_SIZE) : (btn.y + VIS_SPAWN_Y);
			spr.x = btn.x + (BTN_SIZE - pW) / 2;
			spr.setGraphicSize(Math.round(pW), Math.round(PARTICLE_H));
			spr.updateHitbox();
			// 初始单块：上升时块底贴按键顶端（向上生成），下落时块顶贴按键底端（向下生成）
			spr.y = down ? anchorY[p] : anchorY[p] - PARTICLE_H;
				spr.alpha = 1;
				spr.clipRect = null;
				spr.visible = true;
				spr.active = true;
				stretch[p] = 0;
				drift[p] = 0;
				holding[p] = true;
				return;
			}
		}
		// 池满则忽略（同时按下超过 POOL_PER_KEY 条轨迹时）
	}

	/**
	 * 将 action 名转换为可读物理按键名。
	 * 从 Controls 的 keyboardBinds 取第一个绑定键。
	 */
	function getKeyName(action:String):String
	{
		// 优先用游戏内 controls；校准/预览态无 PlayState 时，临时创建 Controls 读取 ClientPrefs 真实键位
		var binds:Array<FlxKey> = null;
		if (PlayState.instance != null && PlayState.instance.controls != null)
			binds = PlayState.instance.controls.keyboardBinds.get(action);
		else
			binds = (new Controls()).keyboardBinds.get(action);

		if (binds != null && binds.length > 0)
		{
			var key:FlxKey = binds[0];
			var name:String = key.toString();
			// 修正常见按键显示
			switch (name)
			{
				case 'LEFT': return '←';
				case 'RIGHT': return '→';
				case 'UP': return '↑';
				case 'DOWN': return '↓';
				case 'SPACE': return 'SPACE';
				case 'ENTER': return 'ENTER';
				case 'ESCAPE': return 'ESC';
				case 'BACKSPACE': return '⌫';
				case 'TAB': return 'TAB';
				case 'SHIFT': return 'SHIFT';
				case 'CONTROL': return 'CTRL';
				case 'ALT': return 'ALT';
				default:
					// 去掉可能的 "G" 前缀（gamepad 枚举）等，仅保留可读部分
					if (name != null && name.length > 0)
						return name;
					return convertActionName(action);
			}
		}
		return convertActionName(action);
	}

	/**
	 * 当 action 没有键盘绑定时（如纯手柄），回退用 action 名首字母。
	 */
	function convertActionName(action:String):String
	{
		if (action.startsWith('note_'))
			return action.substr(5, 1).toUpperCase();
		return action.substr(0, 1).toUpperCase();
	}

	/**
	 * 按文件后缀自动查找左侧自定义图标，返回类型与资源 key。
	 * 支持：icon.gif（动图）/ icon.xml 或 icon.json（精灵图集，配合同名 png）/ icon.png（静图）。
	 * 找不到时返回 null，此时左侧空缺会被收起。
	 */
	function findIconInfo():{type:String, key:String}
	{
		for (key in ICON_KEYS)
		{
			if (Paths.fileExists('images/$key.gif', IMAGE) || Paths.fileExists('images/$key.gif', BINARY))   // gif 动图
				return {type: 'gif', key: key};
			if (Paths.fileExists('images/$key.xml', TEXT) || Paths.fileExists('images/$key.json', TEXT)) // 精灵图集
				return {type: 'sprite', key: key};
			if (Paths.fileExists('images/$key.png', IMAGE))   // 静态 png
				return {type: 'png', key: key};
		}
		return null;
	}

	#if MODS_ALLOWED
	/**
	 * 兼容 mods 地解析 gif 图标字节：先查全局 mods、再查当前 mod 目录（及顶层 mods），
	 * 最后回退内置资源（返回 null，由调用方改用相对路径字符串加载）。
	 * 必须读成字节喂给 FlxGifSprite.loadGif，否则 Windows 绝对路径的盘符 E: 会被
	 * Assets.getBytes 误判为“资源库名:路径”分隔符而崩溃。
	 */
	function resolveGifBytes(key:String):haxe.io.Bytes
	{
		// 1) 全局 mods（任意启用的全局 mod 目录）
		for (mod in Mods.getGlobalMods())
		{
			var p:String = Paths.mods('$mod/images/$key.gif');
			if (FileSystem.exists(p)) return File.getBytes(p);
		}
		// 2) 当前 mod 目录 / 顶层 mods
		if (Mods.currentModDirectory != null && Mods.currentModDirectory.length > 0)
		{
			var p:String = Paths.mods(Mods.currentModDirectory + '/images/$key.gif');
			if (FileSystem.exists(p)) return File.getBytes(p);
		}
		var top:String = Paths.mods('images/$key.gif');
		if (FileSystem.exists(top)) return File.getBytes(top);
		// 3) 内置资源：交给调用方用相对路径字符串加载（aris.gif 同款，可正常读取）
		return null;
	}
	#end

	/**
	 * 把源位图等比缩放绘制到 w×h，并做圆角裁剪（超出圆角的部分 alpha 置 0）。
	 * 实现：先按目标尺寸平滑重绘，再用一张圆角遮罩的 alpha 通道覆盖结果 alpha。
	 */
	function makeRoundedBitmap(src:BitmapData, w:Int, h:Int, radius:Float):BitmapData
	{
		// 防御：源位图无效或目标尺寸不合法时，直接返回空白，避免 Cairo 段错误
		if (src == null || src.width <= 0 || src.height <= 0 || w <= 0 || h <= 0)
			return new BitmapData(Std.int(Math.max(1, w)), Std.int(Math.max(1, h)), true, 0x00000000);

		w = Std.int(Math.max(1, w));
		h = Std.int(Math.max(1, h));

		var out = new BitmapData(w, h, true, 0x00000000);
		var mtx = new Matrix();
		mtx.scale(w / src.width, h / src.height);
		out.draw(src, mtx, null, null, null, true);

		// 圆角遮罩：圆角内 alpha=255，圆角外 alpha=0
		// 注意：Cairo 在圆角半径超过矩形一半时会崩溃，这里把半径钳制到安全范围
		var r:Float = Math.min(radius, Math.min(w, h) / 2 - 0.5);
		if (r < 0) r = 0;
		var mask = new BitmapData(w, h, true, 0x00000000);
		var shape = new Shape();
		var g = shape.graphics;
		g.beginFill(0xFFFFFF, 1);
		g.drawRoundRect(0, 0, w, h, r * 2, r * 2);
		g.endFill();
		mask.draw(shape, null, null, null, null, true);

		out.copyChannel(mask, new Rectangle(0, 0, w, h), new Point(0, 0), BitmapDataChannel.ALPHA, BitmapDataChannel.ALPHA);
		mask.dispose();
		return out;
	}

	/**
	 * 取底部显示的自定义名字：
	 * 优先 ClientPrefs.keyViewerName，其次 images/keyViewer/name.txt，最后回退默认名。
	 */
	function getProfileName():String
	{
		var name:String = ClientPrefs.data.keyViewerName;
		if (name != null) name = name.trim();

		if (name == null || name.length == 0)
		{
			for (file in NAME_FILES)
			{
				var txt:String = Paths.getTextFromFile(file);
				if (txt != null)
				{
					txt = txt.trim();
					if (txt.length > 0)
					{
						// 支持多行：保留换行（背景高度会随行数自适应）
						name = ~/(\r\n|\r)/g.replace(txt, '\n');
						break;
					}
				}
			}
		}

		if (name == null || name.length == 0) name = DEFAULT_NAME;
		return name;
	}

	/**
	 * 用矢量绘制一个圆角矩形 sprite：填充 fill 色，并以 thickness 像素的 stroke 色描边。
	 * 用于背景面板等需要圆角+描边的元素。
	 */
	function makeRoundRect(w:Int, h:Int, fill:FlxColor, thickness:Int, stroke:FlxColor, radius:Float):FlxSprite
	{
		var bd = new BitmapData(w, h, true, 0x00000000);
		var shape = new Shape();
		var g = shape.graphics;
		if (thickness > 0)
			g.lineStyle(thickness, stroke, 1);
		g.beginFill(fill, 1);
		g.drawRoundRect(thickness / 2, thickness / 2, w - thickness, h - thickness, radius, radius);
		g.endFill();
		bd.draw(shape);

		var spr = new FlxSprite();
		spr.loadGraphic(bd);
		return spr;
	}
}
