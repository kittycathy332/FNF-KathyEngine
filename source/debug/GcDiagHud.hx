package debug;

import openfl.display.Sprite;
import openfl.display.Shape;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFormatAlign;
import openfl.events.Event;

/**
 * 长按 F9 显示的轻量 GC 诊断 HUD（release 也可用）。
 * 只在按住 F9 时可见，松开即隐藏，不常驻、不影响正常游玩。
 * 显示：当前/峰值 GC 使用内存、GC 预留内存、进程内存、FPS。
 */
class GcDiagHud extends Sprite
{
	private var bg:Shape;
	private var text:TextField;
	private var holding:Bool = false;
	private var frames:Int = 0;
	private var lastFpsTime:Float = 0;
	private var fps:Float = 0;

	private var gcPeak:Float = 0;
	private var taskPeak:Float = 0;

	public function new()
	{
		super();
		bg = new Shape();
		addChild(bg);

		text = new TextField();
		text.width = 320;
		text.height = 120;
		text.multiline = true;
		text.wordWrap = false;
		text.selectable = false;
		text.mouseEnabled = false;
		text.defaultTextFormat = new TextFormat('_sans', 13, 0xFFFFFF, false, false, false, null, null, TextFormatAlign.LEFT);
		text.setTextFormat(new TextFormat('_sans', 13, 0xFFFFFF));
		addChild(text);

		visible = false;
		addEventListener(Event.ENTER_FRAME, onFrame);
	}

	public function setHolding(value:Bool):Void
	{
		holding = value;
		visible = value;
		if (value) redraw();
	}

	private function onFrame(e:Event):Void
	{
		frames++;
		var now = haxe.Timer.stamp();
		var dt = now - lastFpsTime;
		if (dt >= 0.5)
		{
			fps = frames / dt;
			frames = 0;
			lastFpsTime = now;
		}
		if (visible) redraw();
	}

	private inline function mb(bytes:Float):String
	{
		return Math.round(bytes / 1048576) + ' MB';
	}

	private function gcUsage():Float
	{
		#if cpp
		return cpp.vm.Gc.memInfo64(cpp.vm.Gc.MEM_INFO_USAGE);
		#else
		return 0;
		#end
	}

	private function gcReserved():Float
	{
		#if cpp
		return cpp.vm.Gc.memInfo64(cpp.vm.Gc.MEM_INFO_RESERVED);
		#else
		return 0;
		#end
	}

	private function redraw():Void
	{
		var gc = gcUsage();
		var reserved = gcReserved();
		var proc:Float = 0;
		try { proc = openfl.system.System.totalMemory; } catch (e:Dynamic) {}

		if (gc > gcPeak) gcPeak = gc;
		if (reserved > taskPeak) taskPeak = reserved;

		var lines = [
			'--- GC DIAG (hold F9) ---',
			'FPS        : ' + Math.round(fps),
			'GC  MEM    : ' + mb(gc) + '  (peak ' + mb(gcPeak) + ')',
			'GC  RESERVE: ' + mb(reserved) + '  (peak ' + mb(taskPeak) + ')',
			'ProcessMem : ' + mb(proc)
		];
		text.text = lines.join('\n');
		text.setTextFormat(new TextFormat('_sans', 13, 0xFFFFFF));

		bg.graphics.clear();
		bg.graphics.beginFill(0x000000, 0.72);
		bg.graphics.drawRect(0, 0, 326, text.textHeight + 12);
		bg.graphics.endFill();
		bg.graphics.lineStyle(1, 0xFFFFFF, 0.4);
		bg.graphics.drawRect(0, 0, 326, text.textHeight + 12);

		text.x = 6;
		text.y = 6;

		// 贴右下角
		var stage = openfl.Lib.current.stage;
		if (stage != null)
		{
			this.x = stage.stageWidth - this.width - 12;
			this.y = stage.stageHeight - this.height - 12;
		}
	}
}
