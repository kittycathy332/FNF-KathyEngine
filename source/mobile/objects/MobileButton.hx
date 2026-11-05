package mobile.objects;

/**
 * 带动画的屏幕按钮（返回 / 暂停）。
 * 素材来自 assets/shared/images/mobile/backButton、pauseButton（Sparrow Atlas）。
 * 基于 TouchButton，因此天然支持多指与触摸判定。
 */
class MobileButton extends TouchButton
{
	static inline var MARGIN:Float = 16;

	public var key(default, null):String;
	public var anchorRight:Bool = false;

	public function new(image:String, prefix:String, key:String, scale:Float = 1)
	{
		super(0, 0, []);
		this.key = key;

		statusAlphas = [1.0, 1.0, 0.65];

		frames = Paths.getSparrowAtlas('mobile/$image');
		if (frames != null)
		{
			animation.addByIndices('idle', prefix, [0], '', 24, false);
			animation.addByPrefix('press', prefix, 24, false);
			animation.play('idle');
		}

		setGraphicSize(Std.int(width * scale));
		updateHitbox();
		scrollFactor.set();
		antialiasing = ClientPrefs.data.antialiasing;

		onDown.callback = press;
	}

	/** 播放按下动画（松开后自动回到 idle） */
	public function press():Void
	{
		if (frames != null)
			animation.play('press', true);
	}

	public override function update(elapsed:Float):Void
	{
		super.update(elapsed);
		if (anchorRight)
			x = FlxG.width - width - MARGIN;
		if (animation.curAnim != null && animation.curAnim.name == 'press' && animation.curAnim.finished)
			animation.play('idle');
	}

	/**
	 * 右上/右下角的返回按钮。
	 * @param onPress 点击回调（按钮自身会先播放动画）
	 */
	public static function back(?onPress:Void->Void, ?camera:FlxCamera, top:Bool = false):MobileButton
	{
		var button:MobileButton = new MobileButton('backButton', 'back', 'back', 0.65);
		button.setPosition(FlxG.width - button.width - MARGIN, top ? MARGIN : FlxG.height - button.height - MARGIN);
		button.anchorRight = true;
		button.visible = FlxG.onMobile;
		if (camera != null)
			button.cameras = [camera];
		if (onPress != null)
			button.onDown.callback = () ->
			{
				button.press();
				onPress();
			};
		return button;
	}

	/** 右上角的暂停按钮 */
	public static function pause(?onPress:Void->Void, ?camera:FlxCamera):MobileButton
	{
		var button:MobileButton = new MobileButton('pauseButton', 'pause', 'pause', 0.8);
		button.setPosition(FlxG.width - button.width - MARGIN, MARGIN);
		button.anchorRight = true;
		button.visible = FlxG.onMobile;
		if (camera != null)
			button.cameras = [camera];
		if (onPress != null)
			button.onDown.callback = () ->
			{
				button.press();
				onPress();
			};
		return button;
	}
}
