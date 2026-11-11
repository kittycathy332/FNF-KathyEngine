package states.editors.old.content;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.text.FlxText;
import flixel.ui.FlxButton;
import flixel.util.FlxColor;
import openfl.geom.Rectangle;

/**
 * The confirmation popup shipped with Psych 0.6.x / 0.7.x, kept as-is so the ported editors
 * behave (and look) exactly like their original versions.
 *
 * Psych 1.0's `states.editors.content.Prompt` has an incompatible constructor and a completely
 * different look, so it can't be reused here without breaking the "faithful port" goal.
 */
class Prompt extends MusicBeatSubstate
{
	var selected = 0;

	public var okc:Void->Void;
	public var cancelc:Void->Void;

	var theText:String = '';
	var goAnyway:Bool = false;
	var panel:FlxSprite;
	var panelbg:FlxSprite;
	var buttonAccept:FlxButton;
	var buttonNo:FlxButton;
	var cornerSize:Int = 10;

	/** 原版弹窗写死 300x150；短文本保持原尺寸，长文本按内容撑开。 */
	static inline var MIN_PANEL_W:Int = 300;
	static inline var MIN_PANEL_H:Int = 150;
	/** 面板左右内边距、顶部留白，以及底部留给按钮的空间 */
	static inline var PAD_X:Int = 16;
	static inline var PAD_TOP:Int = 14;
	static inline var PAD_BOTTOM:Int = 46;

	public function new(promptText:String = '', defaultSelected:Int = 0, okCallback:Void->Void, cancelCallback:Void->Void, acceptOnDefault:Bool = false,
			option1:String = null, option2:String = null)
	{
		selected = defaultSelected;
		okc = okCallback;
		cancelc = cancelCallback;
		theText = promptText;
		goAnyway = acceptOnDefault;

		var op1 = (option1 != null) ? option1 : 'OK';
		var op2 = (option2 != null) ? option2 : 'CANCEL';

		buttonAccept = new FlxButton(473.3, 450, op1, function()
		{
			if (okc != null)
				okc();
			close();
		});
		buttonNo = new FlxButton(633.3, 450, op2, function()
		{
			if (cancelc != null)
				cancelc();
			close();
		});
		super();
	}

	override public function create():Void
	{
		super.create();

		if (goAnyway)
		{
			if (okc != null)
				okc();
			close();
			return;
		}

		// --- 自适应尺寸 ---------------------------------------------------
		// fieldWidth = 0 时 flixel 会关掉 wordWrap 并打开 autoSize，
		// textField.textWidth / textHeight 就是「最长行宽」和「原始总高」。
		var probe:FlxText = new FlxText(0, 0, 0, theText, 16);
		probe.alignment = 'center';
		var rawW:Float = 0;
		var rawH:Float = 0;
		try
		{
			rawW = probe.textField.textWidth;
			rawH = probe.textField.textHeight;
		}
		catch (e:Dynamic) {}
		// FlxText 构造后 width/height 已由 regenGraphic() 算好（含 4px VERTICAL_GUTTER），
		// 取两路较大值，避免任何一路在目标平台上低估导致裁字。
		rawW = Math.max(rawW, probe.width);
		rawH = Math.max(rawH, probe.height);
		var lineCount:Int = theText.split('\n').length;
		if (rawW <= 0) rawW = 280;             // 测量失败：退回原版可用宽度
		if (rawH <= 0) rawH = lineCount * 22; // 16px 字号 + 行距的粗估

		// 宽度按最长行撑开，但设下限保持原观感、上限避免顶满屏幕
		var maxW:Float = Math.min(640, FlxG.width * 0.8);
		var panelW:Int = Std.int(Math.min(maxW, Math.max(MIN_PANEL_W, rawW + PAD_X * 2)));
		if (panelW < MIN_PANEL_W) panelW = MIN_PANEL_W;
		var innerW:Int = Std.int(Math.max(1, panelW - PAD_X * 2));
		try { probe.destroy(); } catch (e:Dynamic) {}

		// 用最终宽度再量一次：超长行会被 wordWrap 折行，行数可能变多，
		// 面板高度必须按折行后的实际高度算，否则文字仍会溢出底边。
		var textshit:FlxText = new FlxText(0, 0, innerW, theText, 16);
		textshit.alignment = 'center';
		var realH:Float = 0;
		try { realH = textshit.textField.textHeight; } catch (e:Dynamic) {}
		realH = Math.max(realH, textshit.height); // wordWrap 后的真实渲染高度，兜底
		if (realH <= 0) realH = rawH;
		var maxH:Float = FlxG.height * 0.85;
		var panelH:Int = Std.int(Math.min(maxH, Math.max(MIN_PANEL_H, Math.ceil(realH) + PAD_TOP + PAD_BOTTOM)));
		if (panelH < MIN_PANEL_H) panelH = MIN_PANEL_H;

		panel = new FlxSprite(0, 0);
		panelbg = new FlxSprite(0, 0);
		makeSelectorGraphic(panel, panelW, panelH, 0xff999999);
		makeSelectorGraphic(panelbg, panelW + 4, panelH + 4, 0xff000000);
		panel.scrollFactor.set();
		panel.screenCenter();
		panelbg.scrollFactor.set();
		panelbg.screenCenter();

		add(panelbg);
		add(panel);
		add(buttonAccept);
		add(buttonNo);

		// 文本按面板内边距排版，不再 screenCenter()：
		// 原版把整块文本垂直居中，行数一多就会顶出框、把按钮压在字上。
		textshit.setPosition(panel.x + PAD_X, panel.y + PAD_TOP);
		textshit.scrollFactor.set();
		add(textshit);

		buttonAccept.screenCenter();
		buttonNo.screenCenter();
		buttonAccept.x -= buttonNo.width / 1.5;
		buttonAccept.y = panel.y + panel.height - 30;
		buttonNo.x += buttonNo.width / 1.5;
		buttonNo.y = panel.y + panel.height - 30;
	}

	function makeSelectorGraphic(panel:FlxSprite, w:Int, h:Int, color:FlxColor)
	{
		panel.makeGraphic(w, h, color);
		// 原版遗留：固定 y=190 的黑线在 150 高的面板上完全落在画布外（本就无效）。
		// 面板自适应变高后它会突然出现在中间，这里不再绘制。

		panel.pixels.fillRect(new Rectangle(0, 0, cornerSize, cornerSize), 0x0); // top left
		drawCircleCornerOnSelector(panel, false, false, color);
		panel.pixels.fillRect(new Rectangle(panel.width - cornerSize, 0, cornerSize, cornerSize), 0x0); // top right
		drawCircleCornerOnSelector(panel, true, false, color);
		panel.pixels.fillRect(new Rectangle(0, panel.height - cornerSize, cornerSize, cornerSize), 0x0); // bottom left
		drawCircleCornerOnSelector(panel, false, true, color);
		panel.pixels.fillRect(new Rectangle(panel.width - cornerSize, panel.height - cornerSize, cornerSize, cornerSize), 0x0); // bottom right
		drawCircleCornerOnSelector(panel, true, true, color);
	}

	function drawCircleCornerOnSelector(panel:FlxSprite, flipX:Bool, flipY:Bool, color:FlxColor)
	{
		var antiX:Float = (panel.width - cornerSize);
		var antiY:Float = flipY ? (panel.height - 1) : 0;
		if (flipY)
			antiY -= 2;
		panel.pixels.fillRect(new Rectangle((flipX ? antiX : 1), Std.int(Math.abs(antiY - 8)), 10, 3), color);
		if (flipY)
			antiY += 1;
		panel.pixels.fillRect(new Rectangle((flipX ? antiX : 2), Std.int(Math.abs(antiY - 6)), 9, 2), color);
		if (flipY)
			antiY += 1;
		panel.pixels.fillRect(new Rectangle((flipX ? antiX : 3), Std.int(Math.abs(antiY - 5)), 8, 1), color);
		panel.pixels.fillRect(new Rectangle((flipX ? antiX : 4), Std.int(Math.abs(antiY - 4)), 7, 1), color);
		panel.pixels.fillRect(new Rectangle((flipX ? antiX : 5), Std.int(Math.abs(antiY - 3)), 6, 1), color);
		panel.pixels.fillRect(new Rectangle((flipX ? antiX : 6), Std.int(Math.abs(antiY - 2)), 5, 1), color);
		panel.pixels.fillRect(new Rectangle((flipX ? antiX : 8), Std.int(Math.abs(antiY - 1)), 3, 1), color);
	}
}
