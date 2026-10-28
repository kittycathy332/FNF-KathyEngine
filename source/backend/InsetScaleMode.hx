package backend;

import flixel.FlxG;
import flixel.system.scaleModes.BaseScaleMode;

/**
 * Flixel scale mode that letterboxes the game inside a uniform inset.
 *
 * Used by the pseudo window frame: the game content is scaled into
 * `window size - 2 * inset`, leaving a real empty margin for the frame.
 * Unlike scaling the game root display object, this also keeps Flixel's
 * pointer mapping (scaleMode.scale) correct.
 */
class InsetScaleMode extends BaseScaleMode
{
	public var inset:Float = 0;

	public function new(inset:Float)
	{
		super();
		this.inset = inset;
	}

	override public function onMeasure(Width:Int, Height:Int):Void
	{
		FlxG.width = FlxG.initialWidth;
		FlxG.height = FlxG.initialHeight;

		var availableWidth = Width - inset * 2;
		var availableHeight = Height - inset * 2;

		if (availableWidth < 1) availableWidth = 1;
		if (availableHeight < 1) availableHeight = 1;

		var gameWidth = FlxG.width;
		var gameHeight = FlxG.height;
		var factor = Math.min(availableWidth / gameWidth, availableHeight / gameHeight);

		var contentWidth = gameWidth * factor;
		var contentHeight = gameHeight * factor;

		gameSize.set(contentWidth, contentHeight);
		deviceSize.set(Width, Height);
		scale.set(factor, factor);
		offset.set((Width - contentWidth) * 0.5, (Height - contentHeight) * 0.5);

		if (FlxG.game != null)
		{
			FlxG.game.x = offset.x;
			FlxG.game.y = offset.y;
		}
	}
}
