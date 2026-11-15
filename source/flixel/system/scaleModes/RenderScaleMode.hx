package flixel.system.scaleModes;

import flixel.FlxG;

/**
 * 离线渲染专用缩放模式（放在 flixel.system.scaleModes 包内，
 * 才能写 FlxG.width / FlxG.height —— FlxG 用 @:allow 授权了这个包）。
 *
 * 作用：把「游戏逻辑分辨率」和「窗口 framebuffer 分辨率」彻底解耦。
 *  - 逻辑尺寸锁死在进入渲染时的 FlxG.width / FlxG.height（通常是 1280x720），
 *    所以 PlayState 里所有硬编码的 1280x720 HUD / 相机坐标都不需要改动；
 *  - 画面等比铺满被 RenderClock 放大的窗口，多出的部分留黑边，
 *    readPixels() 读回的就是目标输出分辨率（真正的超采样，而非 CPU 拉伸）。
 *
 * 与 PlayStateScaleMode 的区别：后者会按窗口宽高比重算逻辑宽度、高度锁 720，
 * 本类则把宽高一并锁死，保证任何目标分辨率下 HUD 布局完全一致。
 */
class RenderScaleMode extends BaseScaleMode
{
	public var lockWidth:Int;
	public var lockHeight:Int;

	public function new(lockWidth:Int, lockHeight:Int)
	{
		super();
		this.lockWidth = lockWidth;
		this.lockHeight = lockHeight;
	}

	override public function onMeasure(Width:Int, Height:Int):Void
	{
		if (Width <= 0) Width = lockWidth;
		if (Height <= 0) Height = lockHeight;

		// 关键：无视窗口尺寸，逻辑坐标恒等于渲染前的尺寸
		FlxG.width = lockWidth;
		FlxG.height = lockHeight;

		updateGameSize(Width, Height);
		updateDeviceSize(Width, Height);
		updateScaleOffset();
		updateGamePosition();
	}

	/** 等比缩放铺满窗口，做过宽/过高时留黑边，避免画面变形 */
	override function updateGameSize(Width:Int, Height:Int):Void
	{
		var gameRatio:Float = FlxG.width / FlxG.height;
		var windowRatio:Float = Width / Height;

		if (windowRatio < gameRatio)
		{
			gameSize.x = Width;
			gameSize.y = Math.floor(Width / gameRatio);
		}
		else
		{
			gameSize.y = Height;
			gameSize.x = Math.floor(Height * gameRatio);
		}
	}
}
