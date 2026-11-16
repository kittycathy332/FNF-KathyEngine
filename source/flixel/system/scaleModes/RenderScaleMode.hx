package flixel.system.scaleModes;

import flixel.FlxG;

/**
 * 离线渲染专用缩放模式（放在 flixel.system.scaleModes 包内，
 * 才能写 FlxG.width / FlxG.height —— FlxG 用 @:allow 授权了这个包）。
 *
 * 唯一策略：锁定项目原本的逻辑尺寸，把窗口等比铺满目标分辨率。
 * 逻辑分辨率绝不让导出尺寸改写 —— 实测改了会让所有固定坐标 UI / 菜单错位。
 * 该模式覆盖 PlayStateScaleMode 的自动宽度逻辑，但保持 height=720、width 自适应
 * 的结果不变（进入渲染时由 PlayState.create() 决定好的 FlxG.width/height）。
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
		if (Width <= 0) Width = 1280;
		if (Height <= 0) Height = 720;

		FlxG.width = lockWidth;
		FlxG.height = lockHeight;
		updateGameSize(Width, Height);
		updateDeviceSize(Width, Height);
		updateScaleOffset();
		updateGamePosition();
	}

	/** 等比缩放铺满窗口，多余空间留黑边，避免画面变形 */
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
