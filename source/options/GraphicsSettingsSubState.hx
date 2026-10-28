package options;
import backend.AssetErrorOverlay;
import backend.GifAssets;
import com.yagp.Gif;
import flixel.util.FlxColor;
import flixel.math.FlxPoint;
import flixel.text.FlxText;

class GraphicsSettingsSubState extends BaseOptionsMenu
{
	var antialiasingOption:Int;
	var arisDance:Int;
	var spkGif:objects.GifSprite = null;
	var spkGifTween:FlxTween;
	var spkGifSizeTween:FlxTween;
	var spkGifPokeTween:FlxTween;
	var arisTween:FlxTween; // 保留变量名兼容 changeSelection 里的 arisDance 逻辑
	var spkGifBaseScale:Float = 1;
	var spkGifTargetScale:Float = 1; // 当前静止目标 scale（240 或 400 对应的比例）
	var _pokeCooldown:Bool = false; // 用 Bool + 音频回调，和 OptionsState 一致
	var spkGifOriginCenter:FlxPoint = new FlxPoint();
	var spkGifOriginBR:FlxPoint = new FlxPoint(); // 右下角锚点（抗锯齿选中时）
	var spkGifLastOriginMode:String = 'center'; // 'center' | 'br'，用于判断是否需要补偿位置
	var speakiSounds:Array<String> = [
		'speaki/ahh', 'speaki/ahhww', 'speaki/baseo_full', 'speaki/baseo',
		'speaki/choayo_1', 'speaki/choayo_2', 'speaki/choayo_23', 'speaki/choayo_excited',
		'speaki/speaki_will_tryhard', 'speaki/speaki', 'speaki/spq_baseo',
		'speaki/wwaah_full', 'speaki/wwaahh'
	];
	var warningText:FlxText; // 警告文本变量

	public function new()
		{
			title = Language.get('graphics_menu');
			rpcTitle = 'Graphics Settings Menu';

			#if desktop
			// 伪窗口边框：去掉系统标题栏和边框，改用游戏内标题栏/边框
			var option:Option = new Option(Language.get('borderless_name'),
				Language.get('borderless_desc'),
				'borderless',
				BOOL);
			option.onChange = function()
			{
				backend.PseudoTitleBar.applySettings();
			};
			addOption(option);
			#end

			// 图形设置选项
			var option:Option = new Option(Language.get('low_quality'),
				Language.get("low_quality_desc"),
				'lowQuality',
				BOOL);
			addOption(option);

			var option:Option = new Option(Language.get('anti_aliasing'),
				Language.get("antialiasing_desc"),
				'antialiasing',
				BOOL);
			option.onChange = onChangeAntiAliasing;
			addOption(option);
			antialiasingOption = optionsArray.length - 1;

			var option:Option = new Option(Language.get('shaders'),
				Language.get("shaders_desc"),
				'shaders',
				BOOL);
			addOption(option);

			var option:Option = new Option(Language.get('gpu_caching'),
				Language.get("gpu_caching_desc"),
				'cacheOnGPU',
				BOOL);
			addOption(option);

			var option:Option = new Option(Language.get('playstate_pixel_perfect'),
				Language.get("playstate_pixel_perfect_desc"),
				'playStatePixelPerfect',
				BOOL);
			addOption(option);

			var option:Option = new Option(Language.get('resource_caching_on_reload'),
				Language.get("resource_caching_desc"),
				'cacheResourcesOnReload',
				BOOL);
			addOption(option);

			// 图片资源加载失败时，就地显示「L 形角标 + 缺失路径」占位标记
			var option:Option = new Option(Language.get('asset_error_overlay'),
				Language.get("asset_error_overlay_desc"),
				'assetErrorOverlay',
				BOOL);
			option.onChange = function()
			{
				// 即时生效：清掉占位图缓存，后续对缺失资源的请求按新开关立即重建。
				AssetErrorOverlay.clearCache();
			}
			addOption(option);

			var option:Option = new Option(Language.get('optimized_note_loading'),
				Language.get("optimized_note_loading_desc"),
				'useOptimizedNoteLoading',
				STRING,
				['OFF', 'ON', 'AUTO']);
			addOption(option);

			#if !html5
			// 帧率设置（非HTML5平台）
			var option:Option = new Option(Language.get('framerate'),
				Language.get("framerate_desc"),
				'framerate',
				INT);
			addOption(option);
			arisDance = optionsArray.length - 1;

			final refreshRate:Int = FlxG.stage.application.window.displayMode.refreshRate;
			option.minValue = 20;
			option.maxValue = 1000;
			option.defaultValue = Std.int(FlxMath.bound(refreshRate, option.minValue, option.maxValue));
			option.displayFormat = '%v FPS';
			option.onChange = onChangeFramerate;
			#end

			var option:Option = new Option(Language.get('fps_rework'),
				Language.get("fps_rework_desc"),
				'fpsRework',
				BOOL);
			addOption(option);

			// PlayState宽屏自适应
			var option:Option = new Option(Language.get('playstate_adaptive_width'),
				Language.get("playstate_adaptive_width_desc"),
				'playStateAdaptiveWidth',
				BOOL);
			addOption(option);

			// 制谱器分辨率跟随窗口
			var option:Option = new Option(Language.get('chart_editor_follow_window'),
				Language.get("chart_editor_follow_window_desc"),
				'chartEditorFollowWindow',
				BOOL);
			addOption(option);

			// 制谱器深浅色主题
			var option:Option = new Option(Language.get('chart_editor_theme'),
				Language.get("chart_editor_theme_desc"),
				'chartEditorTheme',
				STRING,
				['Default', 'Light', 'Dark']);
			addOption(option);

			// 飞溅数量限制设置
			var option:Option = new Option(Language.get('splash_limit'),
				Language.get("splash_limit_desc"),
				'splashLimitEnabled',
				BOOL);
			addOption(option);

			var option:Option = new Option(Language.get('max_splashes'),
				Language.get("max_splashes_desc"),
				'splashLimit',
				INT);
			option.minValue = 1;
			option.maxValue = 128;
			option.defaultValue = 16;
			option.displayFormat = '%v';
			addOption(option);

			// 飞溅超限处理模式：现状（达到上限则忽略）或 覆盖（销毁最早生成的那个再生成）
			var option:Option = new Option(Language.get('splash_limit_mode'),
				Language.get("splash_limit_mode_desc"),
				'splashLimitMode',
				STRING,
				['skip', 'replace']);
			option.valueLocalizations = [
				'skip'    => Language.get('splash_limit_mode_skip'),
				'replace' => Language.get('splash_limit_mode_replace')
			];
			option.defaultValue = 'skip';
			addOption(option);

			// Hold Cover 数量限制设置（与飞溅数量限制类似）
			var option:Option = new Option(Language.get('hold_cover_limit'),
				Language.get("hold_cover_limit_desc"),
				'holdCoverLimitEnabled',
				BOOL);
			addOption(option);

			var option:Option = new Option(Language.get('max_hold_covers'),
				Language.get("max_hold_covers_desc"),
				'holdCoverLimit',
				INT);
			option.minValue = 1;
			option.maxValue = 128;
			option.defaultValue = 10;
			option.displayFormat = '%v';
			addOption(option);

			// 资源加载线程数（默认 1 = 单线程；数值越大加载越并行，但更耗内存、低端机可能 OOM）
			var option:Option = new Option(Language.get('loading_threads'),
				Language.get("loading_threads_desc"),
				'loadingThreadCount',
				INT);
			option.minValue = 1;
			option.maxValue = 16;
			option.defaultValue = 1;
			option.displayFormat = '%v';
			addOption(option);

			// 是否显示进入歌曲时的加载界面
			var option:Option = new Option(Language.get('show_loading_screen'),
				Language.get("show_loading_screen_desc"),
				'loadingScreen',
				BOOL);
			addOption(option);

			super();

			// spkGif（在 super() 后 add，确保在 BaseOptionsMenu 选项层之上）
			// 复用主设置界面的 minispeaki.gif（GifAssets 已缓存 → cache hit 秒开）
			// attach 后用第一帧渲染静态位图，然后 dispose GIF 播放器——零帧播放开销
			spkGif = new objects.GifSprite(0, 0);
			spkGif.disposeGifOnDestroy = false;
			spkGif.antialiasing = ClientPrefs.data.antialiasing;
			spkGif.scrollFactor.set();
			spkGif.visible = false;
			add(spkGif);

			GifAssets.load('assets/shared/images/gifs/minispeaki.gif', function(gif:Gif) {
					if (spkGif == null || !spkGif.exists) return;
					spkGif.attachGif(gif);
					spkGif.setGraphicSize(400);
					spkGifBaseScale = spkGif.scale.x;
					var isSpecial:Bool = (arisDance == curSelected) || (antialiasingOption == curSelected);
					var initSize:Float = (arisDance == curSelected) ? 240 : 400;
					if (initSize != 400)
						spkGif.setGraphicSize(initSize);
					spkGif.updateHitbox(); // centerOrigin() 默认居中

					// 预存两种锚点位置（基于原始帧，不随缩放变）
					spkGifOriginCenter.set(spkGif.frameWidth / 2, spkGif.frameHeight / 2);
					spkGifOriginBR.set(spkGif.frameWidth, spkGif.frameHeight);

					// 根据当前选中项设定初始锚点
					setSpkGifOrigin(curSelected);

					// 初始静止位置（按当前 origin 修正，与 changeSelection 保持一致）
					var ts:Float = spkGif.scale.x;
					spkGifTargetScale = ts;
					spkGif.x = spkGifRestX(isSpecial ? 800 : 1560, ts);
					spkGif.y = spkGifRestY(ts);
					spkGif.alpha = 0;
					spkGif.visible = true;
					FlxTween.tween(spkGif, {alpha: 0.9}, 0.5, {ease: FlxEase.quadOut});
				});

			// 初始化警告文本
			warningText = new FlxText(0, 50, FlxG.width - 40, "", 24);
			warningText.setFormat(Paths.font(Language.get('game_font')), 32, FlxColor.YELLOW, RIGHT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			warningText.visible = false;
			warningText.alpha = 0.8; // 添加透明度
			add(warningText); // 确保在最上层
		}

	function onChangeAntiAliasing()
	{
		for (sprite in members)
		{
			var sprite:FlxSprite = cast sprite;
			if(sprite != null && (sprite is FlxSprite) && !(sprite is FlxText)) {
				sprite.antialiasing = ClientPrefs.data.antialiasing;
			}
		}
	}

	function onChangeFramerate()
	{
		if(ClientPrefs.data.framerate > FlxG.drawFramerate)
		{
			ClientPrefs.data.fpsRework ? 
				FlxG.stage.window.frameRate = ClientPrefs.data.framerate :
				{
					FlxG.updateFramerate = ClientPrefs.data.framerate;
					FlxG.drawFramerate = ClientPrefs.data.framerate;
				};
		}
		else
		{
			ClientPrefs.data.fpsRework ?
				FlxG.stage.window.frameRate = ClientPrefs.data.framerate :
				{
					FlxG.drawFramerate = ClientPrefs.data.framerate;
					FlxG.updateFramerate = ClientPrefs.data.framerate;
				};
		}
	}

	override function destroy()
	{
		if (spkGifTween != null)
		{
			spkGifTween.cancel();
			spkGifTween.destroy();
			spkGifTween = null;
		}
		if (spkGifSizeTween != null)
		{
			spkGifSizeTween.cancel();
			spkGifSizeTween.destroy();
			spkGifSizeTween = null;
		}
		if (spkGifPokeTween != null)
		{
			spkGifPokeTween.cancel();
			spkGifPokeTween.destroy();
			spkGifPokeTween = null;
		}
		if (arisTween != null)
		{
			arisTween.cancel();
			arisTween.destroy();
			arisTween = null;
		}
		
		if (spkGif != null)
		{
			spkGif.destroy();
			spkGif = null;
		}
		
		super.destroy();
	}

	// 计算 spkGif 的静止位置。
	// Flixel 的渲染公式：渲染后左上角 = x + (1 - scale) * (origin - frame/2)
	// 所以以「中心锚点下的 x」为基准（baseX），再按当前 origin 偏离中心的量做修正，
	// 保证切换锚点后 sprite 的视觉位置一致（不会因 origin 变化而跳动/偏移）。
	private function spkGifRestX(baseX:Float, targetScale:Float):Float
	{
		var originDeltaX:Float = spkGif.origin.x - spkGif.frameWidth * 0.5;
		return baseX - (1 - targetScale) * originDeltaX;
	}

	private function spkGifRestY(targetScale:Float):Float
	{
		var originDeltaY:Float = spkGif.origin.y - spkGif.frameHeight * 0.5;
		var baseY:Float = (FlxG.height - spkGif.frameHeight * targetScale) * 0.5;
		return baseY - (1 - targetScale) * originDeltaY;
	}

	// 根据选中项切换锚点：FPS → 居中，抗锯齿 → 右下角，其他 → 居中（默认）
	private function setSpkGifOrigin(selIndex:Int):Void
	{
		if (spkGif == null || !spkGif.exists) return;

		var wantBR:Bool = (antialiasingOption == selIndex);
		var newMode:String = wantBR ? 'br' : 'center';
		if (newMode == spkGifLastOriginMode) return; // 没变就跳过

		// 切换前记住旧 origin
		var oldOx:Float = spkGif.origin.x;
		var oldOy:Float = spkGif.origin.y;

		// 切换 origin
		spkGif.origin.set(wantBR ? spkGifOriginBR.x : spkGifOriginCenter.x,
						  wantBR ? spkGifOriginBR.y : spkGifOriginCenter.y);
		spkGifLastOriginMode = newMode;

		// 切换瞬间补偿 x/y，避免视觉跳变（左上角不变）：
		// newTL = oldTL → x += (oldOrigin - newOrigin) * (1 - scale)
		var s:Float = spkGif.scale.x;
		spkGif.x += (oldOx - spkGif.origin.x) * (1 - s);
		spkGif.y += (oldOy - spkGif.origin.y) * (1 - s);
	}

	override function changeSelection(change:Int = 0, skipRefresh:Bool = false, skipDesc:Bool = false)
	{
		// 安全清理之前的所有 tween（poke 和 sizeTween 互斥）
		if (spkGifTween != null) { spkGifTween.cancel(); spkGifTween.destroy(); spkGifTween = null; }
		if (spkGifSizeTween != null) { spkGifSizeTween.cancel(); spkGifSizeTween.destroy(); spkGifSizeTween = null; }
		if (spkGifPokeTween != null) { spkGifPokeTween.cancel(); spkGifPokeTween.destroy(); spkGifPokeTween = null; }

		super.changeSelection(change, skipRefresh, skipDesc);

		if (spkGif != null && spkGif.exists)
		{
			// 锚点切换先做（位置补偿在 scale tween 之前）
			setSpkGifOrigin(curSelected);

			var isSpecial:Bool = (arisDance == curSelected) || (antialiasingOption == curSelected);
			var targetSize:Float = (arisDance == curSelected) ? 240 : 400;
			var targetScale:Float = spkGifBaseScale * (targetSize / 400);

			// 更新静止目标 scale（poke 弹回这个值，不会被 sizeTween 干扰）
			spkGifTargetScale = targetScale;

			// 目标位置：按当前 origin 修正，保证不同锚点下视觉落点一致
			var targetX:Float = spkGifRestX(isSpecial ? 800 : 1560, targetScale);
			var targetY:Float = spkGifRestY(targetScale);

			// x/y 位置过渡
			spkGifTween = FlxTween.tween(spkGif, {
				x: targetX, y: targetY
			}, 0.45, {
				ease: FlxEase.quadOut,
				onComplete: function(twn:FlxTween) {
					if (spkGifTween == twn) spkGifTween = null;
				}
			});

			// 先立刻 squash Y 轴（戳戳效果），再用 backOut ease 过渡到目标 scale
			// X/Y 同时过渡，确保不出现 X=1.0 Y=0.5 这种形变
			spkGif.scale.y *= 0.6;

			spkGifSizeTween = FlxTween.tween(spkGif.scale, {
				x: targetScale, y: targetScale
			}, 0.45, {
				ease: FlxEase.backOut,
				onComplete: function(_) { spkGifSizeTween = null; }
			});
		}
	}

	// 点击触发的戳戳动画：固定基准 scale + speaki 音效 + 音频结束冷却 + 与 sizeTween 互斥
	private function pokeSpkGif():Void
	{
		if (_pokeCooldown || spkGif == null || !spkGif.visible || !spkGif.exists) return;
		_pokeCooldown = true;

		// poke 和 sizeTween 互斥：pok ing 时取消正在进行的 size 过渡
		if (spkGifSizeTween != null) { spkGifSizeTween.cancel(); spkGifSizeTween.destroy(); spkGifSizeTween = null; }
		if (spkGifPokeTween != null) { spkGifPokeTween.cancel(); spkGifPokeTween.destroy(); }

		// 固定基准 scale（由 changeSelection 更新，poke 只读不写，永远不会变形）
		var s:Float = spkGifTargetScale;

		// 同时 squash x 和 y，保持比例一致（因为 origin 已居中，缩放围绕中心）
		spkGif.scale.set(s * 0.6, s * 0.6);
		spkGifPokeTween = FlxTween.tween(spkGif.scale, { x: s, y: s }, 0.45, {
			ease: FlxEase.quadOut,
			onComplete: function(_) { spkGifPokeTween = null; }
		});

		// 随机播放 speaki 语音（和 OptionsState 侧 Gif 相同音效）
		var key:String = speakiSounds[FlxG.random.int(0, speakiSounds.length - 1)];
		var snd = FlxG.sound.play(Paths.sound(key));
		if (snd != null)
			snd.onComplete = function() { _pokeCooldown = false; };
		else
			_pokeCooldown = false; // 音频加载失败也解除冷却
	}

	override function update(elapsed:Float)
	{
		super.update(elapsed);

		// spkGif 旋转：选中 FPS 选项时持续旋转（angle 保持 0~360 不累积），其他选项最多转半圈归位
		if (spkGif != null && spkGif.exists)
		{
			if (arisDance == curSelected)
				spkGif.angle = (spkGif.angle + 1) % 360;
			else
			{
				// 先把 angle 规范到 -180~180，再 lerp 到 0
				var a:Float = spkGif.angle % 360;
				if (a > 180) a -= 360;
				else if (a < -180) a += 360;
				spkGif.angle = FlxMath.lerp(0, a, Math.exp(-elapsed * 6));
			}

			// 点击 spkGif → 戳戳弹跳
			if (FlxG.mouse.justPressed && FlxG.mouse.overlaps(spkGif))
				pokeSpkGif();

			#if mobile
			// 移动端触摸也触发
			for (touch in FlxG.touches.list)
			{
				if (touch.justPressed && touch.overlaps(spkGif))
				{
					pokeSpkGif();
					break;
				}
			}
			#end
		}

		#if !html5
		final showWarning:Bool = curSelected == arisDance && 
			(ClientPrefs.data.framerate < 60 || ClientPrefs.data.framerate > 240);

		final isCritical:Bool = curSelected == arisDance && ClientPrefs.data.framerate > 480;

		warningText.visible = showWarning || isCritical;
		if (isCritical) {
			warningText.text = Language.get("fps_warning_2");
			warningText.color = FlxColor.RED;
		} else if (showWarning) {
			warningText.text = Language.get("fps_warning_1");
			warningText.color = FlxColor.YELLOW;
		}
		#end
	}
}
