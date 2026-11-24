package debug;

import openfl.display.Sprite;
import openfl.display.Shape;
import openfl.text.TextField;
import openfl.text.TextFormat;

/**
 * 长按 F5 / Shift+F5 的确认进度提示（贴游戏画面右上角）。
 * 只在按住快捷键期间可见，松开立即隐藏。
 * 满 2 秒后由 Main 执行一次清理 + 刷新，本类只负责显示进度。
 * 出现时先花 0.5 秒从右侧飞入，进度条走非线性（慢-快-慢）。
 */
class HoldConfirmHud extends Sprite
{
	private static inline var WIDTH:Float = 368;
	private static inline var FLY_SECONDS:Float = 0.5; // 飞入时长

	private var bg:Shape;
	private var barBg:Shape;
	private var bar:Shape;
	private var title:TextField;
	private var hint:TextField;
	private var fontName:String;
	private var showTime:Float = 0;
	private var targetX:Float = 0;

	public function new()
	{
		super();
		fontName = backend.Paths.font('unifont-18.0.01.otf');
		// TextFormat.font 需要字体族名而不是文件路径，否则会静默回退到系统默认字体（中文可能变方框）
		try
		{
			var f = openfl.utils.Assets.getFont(fontName);
			if (f != null) fontName = f.fontName;
		}
		catch (e:Dynamic) {}

		bg = new Shape();
		addChild(bg);

		barBg = new Shape();
		addChild(barBg);

		bar = new Shape();
		addChild(bar);

		title = new TextField();
		title.width = WIDTH;
		title.height = 24;
		title.selectable = false;
		title.mouseEnabled = false;
		addChild(title);

		hint = new TextField();
		hint.width = WIDTH;
		hint.height = 20;
		hint.selectable = false;
		hint.mouseEnabled = false;
		addChild(hint);

		visible = false;
	}

	/** 开始显示。isAll=true 表示 Shift+F5 全清模式。 */
	public function show(isAll:Bool):Void
	{
		var titleFmt = new TextFormat(fontName, 16, isAll ? 0xFF7A6E : 0xFFD166, true);
		title.defaultTextFormat = titleFmt;
		title.text = isAll
			? backend.Language.getWithFallback('f5_hold_clean_all', 'Shift+F5  清除全部资源并重载')
			: backend.Language.getWithFallback('f5_hold_clean', 'F5  清理闲置资源并刷新');
		title.setTextFormat(titleFmt);

		var hintFmt = new TextFormat(fontName, 16, 0xE8E8E8);
		hint.defaultTextFormat = hintFmt;
		hint.text = backend.Language.getWithFallback('f5_hold_hint', '按住 2 秒执行 · 松开取消');
		hint.setTextFormat(hintFmt);

		var stage = openfl.Lib.current.stage;
		targetX = (stage != null) ? stage.stageWidth - WIDTH - 16 : 0;
		showTime = haxe.Timer.stamp();

		visible = true;
		update(0);
	}

	/** 更新进度（0~1，线性时间比例），内部做飞入 + 非线性进度条。 */
	public function update(progress:Float):Void
	{
		if (!visible) return;

		// 飞入：0.5 秒内从屏幕右侧外滑入到右上角，easeOutCubic
		var fly = (haxe.Timer.stamp() - showTime) / FLY_SECONDS;
		if (fly < 0) fly = 0;
		if (fly > 1) fly = 1;
		var flyEase = 1 - Math.pow(1 - fly, 3);
		var offscreenX = targetX + WIDTH + 40;
		this.x = offscreenX + (targetX - offscreenX) * flyEase;
		this.y = 16;

		// 进度条非线性：easeInOutCubic（慢-快-慢）
		var p = progress < 0 ? 0 : (progress > 1 ? 1 : progress);
		var pe = p < 0.5
			? 4 * p * p * p
			: 1 - Math.pow(-2 * p + 2, 3) / 2;
		var done = p >= 1;

		bg.graphics.clear();
		bg.graphics.beginFill(0x000000, 0.78);
		bg.graphics.drawRect(-8, -6, WIDTH + 16, 76);
		bg.graphics.endFill();
		bg.graphics.lineStyle(1, 0xFFFFFF, 0.35);
		bg.graphics.drawRect(-8, -6, WIDTH + 16, 76);

		barBg.graphics.clear();
		barBg.graphics.beginFill(0x2A2A2A, 0.95);
		barBg.graphics.drawRect(0, 0, WIDTH, 12);
		barBg.graphics.endFill();

		bar.graphics.clear();
		bar.graphics.beginFill(done ? 0x5FD38B : 0xE8A33D, 0.98);
		bar.graphics.drawRect(0, 0, WIDTH * pe, 12);
		bar.graphics.endFill();

		title.x = 0;
		title.y = 0;
		barBg.x = 0;
		barBg.y = 28;
		bar.x = 0;
		bar.y = 28;
		hint.x = 0;
		hint.y = 46;
	}

	public function hide():Void
	{
		visible = false;
	}
}
