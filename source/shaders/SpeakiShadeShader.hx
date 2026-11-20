package shaders;

/**
 * 「着色器」选项的演示着色器：RGB 色差 + 沿对角线扫过的冷光带。
 * 只处理 sprite 自身像素，总共 3 次纹理采样、无额外 pass，开启/关闭的差异一眼可见。
 */
class SpeakiShadeShader extends FlxShader
{
	@:glFragmentSource('
		#pragma header

		uniform float uTime;

		void main()
		{
			vec2 uv = openfl_TextureCoordv;

			// chromatic aberration: red / blue sampled in opposite directions (~0.8% of the sprite width)
			float ca = 0.008;
			vec4 rSample = flixel_texture2D(bitmap, clamp(uv + vec2(ca, 0.0), 0.0, 1.0));
			vec4 bSample = flixel_texture2D(bitmap, clamp(uv - vec2(ca, 0.0), 0.0, 1.0));
			vec4 base = flixel_texture2D(bitmap, uv);
			vec4 color = vec4(rSample.r, base.g, bSample.b, base.a);

			// cold light band sweeping diagonally across the sprite
			float t = (uv.x + uv.y) * 0.5;
			float pos = fract(uTime * 0.45);
			float d = (t - pos) * 7.0;
			float band = exp(-d * d);
			color.rgb += vec3(0.55, 0.85, 1.0) * color.a * band * 0.6;

			// slight overall darkening so the band does not wash the sprite out
			color.rgb *= 0.96;

			gl_FragColor = color;
		}')
	public function new()
	{
		super();
	}
}
