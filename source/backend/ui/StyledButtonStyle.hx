package backend.ui;

/**
 * StyledButton 的外观 / 手感配置。
 *
 * 通用 UI 样式类：不绑定任何 State / 编辑器，任何需要自绘按钮的地方都能直接
 * `new StyledButton(...)` 并传入本类（或修改默认 style 后 rebuild()）。
 *
 * 颜色一律写成 0xAARRGGBB（必须带 FF alpha）：flixel 的 FlxColor 与 OpenFL 都用 ARGB，
 * 写成 6 位 0xRRGGBB 会被当成 alpha=0，也就是完全透明。
 *
 * 运行时改任意字段后，调用按钮的 rebuild() / setStyle() 即可换肤，不需要重建对象。
 * 多个按钮共用同一份 style 时，若想单独改某一个，请用 copy() 先复制。
 */
class StyledButtonStyle
{
	/** 按钮边长（纹理与命中区都是 size x size） */
	public var size:Int = 44;
	/**
	 * 圆角参数。这里传的是 OpenFL drawRoundRect 的 ellipseWidth / ellipseHeight，
	 * 即圆角椭圆的**直径**，不是半径：实际圆角半径 = 本值 / 2。
	 * 11 => 5.5px（明显圆角）；1 => 0.5px（近乎方角，flixelClassic 用这个值复刻原生按钮）。
	 */
	public var cornerRadius:Float = 11;
	public var borderThickness:Float = 2;
	public var borderColor:Int = 0xFF123A5C;
	/** 顶部内侧的高光线 */
	public var rimColor:Int = 0xFFBCE6FF;
	public var rimAlpha:Float = 0.55;
	public var rimThickness:Float = 1;

	/** 主体竖向渐变（上浅下深） */
	public var topColor:Int = 0xFF74BEF3;
	public var bottomColor:Int = 0xFF2C6CB0;

	/** 玻璃质感：顶部白色光泽 / 底部内阴影强度（0~1） */
	public var glossStrength:Float = 0.30;
	public var shadeStrength:Float = 0.22;
	/** 四段渐变的位置（0~255）：光泽 / topColor / bottomColor / 内阴影 */
	public var gradientRatios:Array<Int> = [0, 55, 200, 255];

	/** 内置箭头的样式；设置了 iconPainter 自绘图标时这些字段不生效 */
	public var arrowColor:Int = 0xFFFFFFFF;
	public var arrowShadowColor:Int = 0xFF0B2B47;
	public var arrowSize:Float = 8.5;
	public var arrowThickness:Float = 3.2;
	/** 箭头下方偏移阴影的透明度，0 = 不画阴影（Flixel 默认皮肤无图标阴影） */
	public var arrowShadowAlpha:Float = 0.55;

	/** 三态色调：悬停提亮 / 按下压暗（0~1） */
	public var hoverBright:Float = 0.13;
	public var pressDark:Float = 0.26;
	/** 三态明暗是否同时作用于外描边；false 时描边保持恒定色（Flixel 默认皮肤如此） */
	public var tintBorder:Bool = true;
	/** 按下态顶部高光线的明暗调整，负值让高光变暗以模拟凹陷；0 = 跟随常态 */
	public var pressedRimTint:Float = 0;
	/** 按下态这条线的宽度；0 = 跟随 rimThickness。可单独把凹陷暗线加粗而不影响常态白高光 */
	public var pressedRimThickness:Float = 0;

	/**
	 * 按下反馈增强：在主体顶部叠一层向下淡出的黑色渐变，做出「按进去」的内凹阴影。
	 * 0 = 不启用（默认，其它预设行为不变）。这是烘焙期一次性绘制，运行时零开销。
	 * 该叠层按直角绘制，适合方角皮肤；圆角皮肤请保持 0，否则会溢出圆角。
	 */
	public var pressInsetAlpha:Float = 0;
	/** 内凹阴影带的高度，占按钮边长的比例（0~1） */
	public var pressInsetSize:Float = 0.26;

	/** 按下手感：缩放、内容下沉、缩放插值系数 */
	public var pressScale:Float = 0.93;
	public var pressOffsetY:Float = 1;
	public var smoothing:Float = 0.30;

	/**
	 * 按下缩放是否做平滑插值（补间动画）。
	 * false 时缩放立即吸附到目标值，没有任何过渡；但三态明暗、顶部高光线反转、
	 * 图标下沉仍会即时切换 —— 即「去掉动画，保留按下 / 聚焦反馈」。
	 * flixelClassic() 默认关闭，对齐原生 FlxButton 的状态硬切换手感。
	 */
	public var animatePress:Bool = true;

	/** 主体下方的半透明投影 */
	public var shadowAlpha:Float = 0.35;
	public var shadowOffsetY:Float = 2;

	public function new() {}

	/** 复制一份，方便基于预设做局部微调（自动包含以后新增的字段） */
	public function copy():StyledButtonStyle
	{
		var s = new StyledButtonStyle();
		for (f in Reflect.fields(this))
		{
			var v = Reflect.field(this, f);
			if (Std.isOfType(v, Array))
				v = (cast v : Array<Dynamic>).copy();
			Reflect.setField(s, f, v);
		}
		return s;
	}

	/** 预设：蓝色玻璃（默认皮肤） */
	public static function glassBlue():StyledButtonStyle
		return new StyledButtonStyle();

	/**
	 * 预设：复刻 flixel 5.9 自带 FlxButton 皮肤（flixel/images/ui/button.png）的观感，
	 * 但仍是矢量自绘、不依赖任何贴图，也保持方形尺寸。
	 *
	 * 常态 / 悬停精确采样自原贴图 80x20 四帧：
	 * - 方角 + 1px 纯黑外框（外框恒定，不随三态变色）
	 * - 顶部白色高光线、底部一段压暗边
	 * - 主体灰 #C0C0C0；悬停提亮到 #D3D3D3（+0.30）
	 * - 图标深灰 #333333，无图标阴影 / 无投影 / 无玻璃光泽
	 *
	 * 按下态为可读性做过增强，不再严格等于原贴图采样值（原贴图按下仅 -0.16，
	 * 在 44x44 灰阶上几乎看不出变化）：
	 * - pressDark=0.28 => #8A8A8A，与常态灰度差从 31 提到 54
	 * - 顶部反转暗线加粗到 2px / tint -0.78（常态仍是 1px 白高光）
	 * - 顶部内凹阴影带 pressInsetAlpha=0.34、高度 26%，静态烘焙、无补间
	 * - 图标下沉 2px，不缩放
	 * - 仍是即时硬切换（animatePress=false），没有任何动画
	 */
	public static function flixelClassic():StyledButtonStyle
	{
		var s = new StyledButtonStyle();
		s.cornerRadius = 1;
		s.borderThickness = 1;
		s.borderColor = 0xFF000000;
		s.tintBorder = false;

		s.rimColor = 0xFFFFFFFF;
		s.rimAlpha = 1;
		s.rimThickness = 1;        // 常态保持原贴图的 1px 白高光
		s.pressedRimTint = -0.78;  // 按下时反转成 #383838 暗线
		s.pressedRimThickness = 2; // 只加粗按下态的凹陷线，不影响常态

		s.topColor = 0xFFC0C0C0;
		s.bottomColor = 0xFFC0C0C0;
		s.glossStrength = 0;
		s.shadeStrength = 0.30;
		s.gradientRatios = [0, 24, 205, 255];

		s.arrowColor = 0xFF333333;
		s.arrowShadowColor = 0xFF000000;
		s.arrowShadowAlpha = 0;
		s.arrowSize = 7.5;
		s.arrowThickness = 2.4;

		s.hoverBright = 0.30;
		s.pressDark = 0.28;         // #C0C0C0 -> #8A8A8A，比原贴图 -0.16 更明显
		s.pressInsetAlpha = 0.34;   // 顶部内凹阴影，按下才出现
		s.pressInsetSize = 0.26;
		s.pressScale = 1;
		s.pressOffsetY = 2;
		// 原生 FlxButton 的三态是硬切换：不做缩放补间，也不逐帧 lerp
		s.smoothing = 0;
		s.animatePress = false;

		s.shadowAlpha = 0;
		s.shadowOffsetY = 0;
		return s;
	}

	/** 预设：暗色金属 */
	public static function darkMetal():StyledButtonStyle
	{
		var s = new StyledButtonStyle();
		s.borderColor = 0xFF0A1119;
		s.rimColor = 0xFF6D8BA5;
		s.topColor = 0xFF4A5A6B;
		s.bottomColor = 0xFF1B2530;
		s.arrowColor = 0xFFE6F3FF;
		s.arrowShadowColor = 0xFF05090D;
		s.glossStrength = 0.18;
		return s;
	}

	/**
	 * 预设：纯黑白（Kathy 编谱器的轨道左右平移按钮）。
	 * 黑底 + 白描边 + 白箭头，8px 圆角，和 box 面板的黑底白字风格一致。
	 * cornerRadius 传的是 drawRoundRect 的椭圆直径，所以 16 = 实际半径 8px。
	 */
	public static function monoBlack():StyledButtonStyle
	{
		var s = new StyledButtonStyle();
		s.cornerRadius = 16;
		s.borderThickness = 2;
		s.borderColor = 0xFFFFFFFF;
		s.tintBorder = false; // 三态都保持白色描边

		s.rimColor = 0xFFFFFFFF;
		s.rimAlpha = 0.35;
		s.rimThickness = 1;
		s.pressedRimTint = -0.5;

		s.topColor = 0xFF000000;
		s.bottomColor = 0xFF000000;
		s.glossStrength = 0;
		s.shadeStrength = 0;
		s.gradientRatios = [0, 64, 192, 255];

		s.arrowColor = 0xFFFFFFFF;
		s.arrowShadowColor = 0xFF000000;
		s.arrowShadowAlpha = 0;
		s.arrowSize = 8.5;
		s.arrowThickness = 3.0;

		s.hoverBright = 0.18;
		s.pressDark = 0.10;
		s.pressInsetAlpha = 0; // 圆角皮肤不叠直角内凹阴影
		s.shadowAlpha = 0;
		s.shadowOffsetY = 0;
		return s;
	}

	/** 预设：荧光绿 */
	public static function neonGreen():StyledButtonStyle
	{
		var s = new StyledButtonStyle();
		s.borderColor = 0xFF0B3320;
		s.rimColor = 0xFFC8FFDC;
		s.topColor = 0xFF7CF3A8;
		s.bottomColor = 0xFF189A5A;
		s.arrowShadowColor = 0xFF05351F;
		s.glossStrength = 0.34;
		return s;
	}
}
