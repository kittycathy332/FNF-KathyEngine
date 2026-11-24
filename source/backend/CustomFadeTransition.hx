package backend;

import flixel.util.FlxGradient;
import flixel.FlxSubState;
import flixel.text.FlxText;
import flixel.tweens.FlxTween;
import flixel.util.FlxColor;
import flixel.FlxSprite;
import flixel.graphics.FlxGraphic;
import openfl.display.BitmapData;
import openfl.utils.Assets;
import flixel.FlxObject;
import states.MainMenuState;
import sys.FileSystem;
import haxe.io.Path;
import backend.ClientPrefs;

class CustomFadeTransition extends FlxSubState {
	public static var finishCallback: Void -> Void;
	public static var isReloading: Bool = false; // 标记是否是刷新操作
	public static var reloadingStateType:Class<flixel.FlxState> = null; // 存储要 reload 的 state 类型
	var isTransIn: Bool = false;
	var isReloadingTransition: Bool = false; // 记住这个转场是否是刷新操作
	var transBlack: FlxSprite;
	var transGradient: FlxSprite;
	var duration: Float;
	var loadLeft: FlxSprite;
	var loadRight: FlxSprite;
	var loadAlpha: FlxSprite;
	var WaterMark: FlxText;
	var EventText: FlxText;
	var StateNameText: FlxText; // 显示要 reload 的 state 名称
	var transBG: FlxSprite;
	static var kathyImages:Array<String> = [];
	static var lastRandomIndex:Int = -1;
	static var baGlowImages:Array<String> = [];
	static var currentImageIndex:Int = 0;

	// 强制 BA 转场显示指定图片（key 相对 images/，不含扩展名），一次性用完即清。
	// 供 Shift+F5 全清重载时显示固定的 37 号贴图。
	public static var forceBAImage:String = null;

	// 强制本次转场使用的风格（如 'Blue Archive'），一次性用完即清。
	// 供 Shift+F5 无视玩家设置、强制走 BA 转场。
	public static var forceStyle:String = null;

	// 强制 reload 文案与偏红字体色（Shift+F5 全清场景）。
	public static var forceReloadText:String = null;
	public static var forceReloadColor:Int = -1; // <0 表示不覆盖

	// 当前 BA 转场正在使用的 graphic（转场图 + 黑色遮罩），供 Shift+F5 全清时保护，避免定格画面绿屏。
	public static var protectedGraphics:Array<flixel.graphics.FlxGraphic> = [];

	// 本次转场实际使用的风格（create 时定下，update 复用）
	var currentStyle:String = null;
	
	public static function resetBlueArchiveImages() {
		kathyImages = [];
	}

	/**
	 * 按当前 Blue Archive 语言拼一个编号贴图的 key（兜底图 / Shift+F5 固定图共用）。
	 * 37 号图在四种语言里都使用小写后缀；但 CN 目录的素材沿用韩服命名，实际以 _kr 结尾。
	 * 注意：其它编号的图片后缀大小写并不统一（如 44 号在 JP/KR/CN 为大写），不要随意改编号。
	 */
	public static function baImageKey(number:Int):String
	{
		var lang:String = ClientPrefs.data.blueArchiveLanguage;
		var suffix:String = (lang == 'CN') ? 'kr' : lang.toLowerCase();
		return 'menuExtend/CustomFadeTransition/Blue_Archive/' + lang + '/LoadingImage_' + number + '_' + suffix;
	}

    var baLoadingPics:FlxSprite;
    var baGlowPics:FlxSprite;
    var baLoadingPicTween: FlxTween;
    var loadLeftTween: FlxTween;
    var loadRightTween: FlxTween;
    var loadAlphaTween: FlxTween;
    var EventTextTween: FlxTween;
    var loadTextTween: FlxTween;
    var imageTimer:Float = 0;
    var frameDuration:Float = 0.02; // Time between frames in seconds
    var totalFrames:Int = 39; // Total number of frames (0-39)

    public function new(duration: Float, isTransIn: Bool) {
        this.duration = duration;
        this.isTransIn = isTransIn;
        this.isReloadingTransition = isReloading; // 保存当前是否是刷新操作
        // 不要立即重置，延迟到 create() 中，确保转场创建完成后再重置
        super();
    }
    override function create() {
		// 保存状态后立即重置静态变量
		var savedReloading = isReloading;
		var savedReloadingStateType = reloadingStateType;
		isReloading = false;
		reloadingStateType = null;

		// forceStyle 一次性读取后立刻清空，避免影响后续正常转场
		var forced:String = forceStyle;
		forceStyle = null;

		// 兼容性检查：确保风格是有效的值（含强制风格）
		var validStyles:Array<String> = ['None', 'V-Slice', 'NovaFlare Move', 'NovaFlare Alpha', 'Blue Archive', 'BA_Schale_Glow'];
		var styleToUse:String = forced != null ? forced : ClientPrefs.data.customFadeStyle;
		if (!validStyles.contains(styleToUse)) {
			styleToUse = 'V-Slice';
		}
		// 保存本次实际使用的风格，供 update() 复用（不再依赖可能已变化的玩家设置）
		currentStyle = styleToUse;
		
		// 兼容性检查：确保 blueArchiveLanguage 是有效的值
		var validLanguages:Array<String> = ['CN', 'JP', 'KR', 'EN'];
		if (!validLanguages.contains(ClientPrefs.data.blueArchiveLanguage)) {
			ClientPrefs.data.blueArchiveLanguage = 'EN';
		}

        var cam: FlxCamera = new FlxCamera();
        cam.bgColor = 0x00;
        FlxG.cameras.add(cam, false);
        cameras = [FlxG.cameras.list[FlxG.cameras.list.length - 1]];
        
        // 原版
        var width: Int = Std.int(FlxG.width / Math.max(camera.zoom, 0.001));
        var height: Int = Std.int(FlxG.height / Math.max(camera.zoom, 0.001));
        
        
        if (baGlowImages.length == 0) {
            var imagePath = Paths.getPath('images/menuExtend/CustomFadeTransition/BA_Schale/Light/Glow', IMAGE);
            if (FileSystem.exists(imagePath)) {
                for (i in 0...totalFrames) {
                    var fileName = i;
                    baGlowImages.push('menuExtend/CustomFadeTransition/BA_Schale/Light/Glow/' + fileName);
                }
            }
            // Fallback if no images found
            if (baGlowImages.length == 0) {
                baGlowImages.push('menuExtend/CustomFadeTransition/BA_Schale/Light/Glow/35');
            }
        }

        if (currentStyle == 'BA_Schale_Glow') {
            baGlowPics = new FlxSprite(0, 0);
            baGlowPics.scrollFactor.set();
            baGlowPics.antialiasing = ClientPrefs.data.antialiasing;
            baGlowPics.loadGraphic(Paths.image(baGlowImages[0])); // Load the image here to get its dimensions

            var imageWidth:Float = baGlowPics.width;
            var imageHeight:Float = baGlowPics.height;

            var scaleX:Float = FlxG.width / imageWidth;
            var scaleY:Float = FlxG.height / imageHeight;

            var scale:Float = Math.max(scaleX, scaleY); // Use the larger scale to cover the whole screen

            baGlowPics.scale.set(scale, scale);
            baGlowPics.updateHitbox();
            baGlowPics.screenCenter();
            add(baGlowPics);

            // Set initial frame
            currentImageIndex = isTransIn ? 33 : 0;
            updateGlowImage();

            // Play sound
            if (!isTransIn) {
                FlxG.sound.play(Paths.sound('BA/UI_Loading'));
            } else {
                FlxG.sound.play(Paths.sound('BA/UI_Login'));            
            }
        } else if (currentStyle == 'NovaFlare Move') {
            loadRight = new FlxSprite(isTransIn ? 0 : 1280, 0).loadGraphic(Paths.image('menuExtend/CustomFadeTransition/NF/loadingR'));
            loadRight.scrollFactor.set();
            loadRight.antialiasing = ClientPrefs.data.antialiasing;        
            add(loadRight);
            loadRight.setGraphicSize(FlxG.width, FlxG.height);
            loadRight.updateHitbox();
            
            loadLeft = new FlxSprite(isTransIn ? 0 : -1280, 0).loadGraphic(Paths.image('menuExtend/CustomFadeTransition/NF/loadingL'));
            loadLeft.scrollFactor.set();
            loadLeft.antialiasing = ClientPrefs.data.antialiasing;
            add(loadLeft);
            loadLeft.setGraphicSize(FlxG.width, FlxG.height);
            loadLeft.updateHitbox();
            
            WaterMark = new FlxText(isTransIn ? 50 : -1230, 720 - 50 - 50 * 2, 0, 'KATHY ENGINE V' + MainMenuState.kathyEngineVersion, 50);
            WaterMark.scrollFactor.set();
            WaterMark.setFormat(Assets.getFont("assets/fonts/loadText.ttf").fontName, 50, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
            WaterMark.antialiasing = ClientPrefs.data.antialiasing;
            add(WaterMark);
            
            EventText = new FlxText(isTransIn ? 50 : -1230, 720 - 50 - 50, 0, 'LOADING . . . . . . ', 50);
            EventText.scrollFactor.set();
            EventText.setFormat(Assets.getFont("assets/fonts/loadText.ttf").fontName, 50, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
            EventText.antialiasing = ClientPrefs.data.antialiasing;
            add(EventText);
            
            if (!isTransIn) {
                try {
                    FlxG.sound.play(Paths.sound('NFE/loading_close_move')/*,ClientPrefs.data.CustomFadeSound*/);
                } catch (e: Dynamic) {}
                loadLeftTween = FlxTween.tween(loadLeft, {x: 0}, duration, {
                    onComplete: function(twn: FlxTween) {
                        if (finishCallback != null) {
                            finishCallback();
                        }
                    },
                    ease: FlxEase.expoInOut
                });
                loadRightTween = FlxTween.tween(loadRight, {x: 0}, duration, {
                    onComplete: function(twn: FlxTween) {
                        if (finishCallback != null) {
                            finishCallback();
                        }
                    },
                    ease: FlxEase.expoInOut
                });
                loadTextTween = FlxTween.tween(WaterMark, {x: 50}, duration, {
                    onComplete: function(twn: FlxTween) {
                        if (finishCallback != null) {
                            finishCallback();
                        }
                    },
                    ease: FlxEase.expoInOut
                });
                EventTextTween = FlxTween.tween(EventText, {x: 50}, duration, {
                    onComplete: function(twn: FlxTween) {
                        if (finishCallback != null) {
                            finishCallback();
                        }
                    },
                    ease: FlxEase.expoInOut
                });
            } else {
                try {
                    FlxG.sound.play(Paths.sound('NFE/loading_open_move')/*,ClientPrefs.data.CustomFadeSound*/);
                } catch (e: Dynamic) {}
                EventText.text = 'COMPLETED !';
                loadLeftTween = FlxTween.tween(loadLeft, {x: -1280}, duration, {
                    onComplete: function(twn: FlxTween) {
                        close();
                    },
                    ease: FlxEase.expoInOut
                });
                loadRightTween = FlxTween.tween(loadRight, {x: 1280}, duration, {
                    onComplete: function(twn: FlxTween) {
                        close();
                    },
                    ease: FlxEase.expoInOut
                });
                loadTextTween = FlxTween.tween(WaterMark, {x: -1230}, duration, {
                    onComplete: function(twn: FlxTween) {
                        close();
                    },
                    ease: FlxEase.expoInOut
                });
                EventTextTween = FlxTween.tween(EventText, {x: -1230}, duration, {
                    onComplete: function(twn: FlxTween) {
                        close();
                    },
                    ease: FlxEase.expoInOut
                });
            }
        } else if (currentStyle == 'NovaFlare Alpha') {
            loadAlpha = new FlxSprite( 0, 0).loadGraphic(Paths.image('menuExtend/CustomFadeTransition/NF/loadingAlpha'));
            loadAlpha.scrollFactor.set();
            loadAlpha.antialiasing = ClientPrefs.data.antialiasing;		
            add(loadAlpha);
            loadAlpha.setGraphicSize(FlxG.width, FlxG.height);
            loadAlpha.updateHitbox();
            
            WaterMark = new FlxText( 50, 720 - 50 - 50 * 2, 0, 'KATHY ENGINE V' + MainMenuState.kathyEngineVersion, 50);
            WaterMark.scrollFactor.set();
            WaterMark.setFormat(Assets.getFont("assets/fonts/loadText.ttf").fontName, 50, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
            WaterMark.antialiasing = ClientPrefs.data.antialiasing;
            add(WaterMark);
            
            EventText= new FlxText( 50, 720 - 50 - 50, 0, 'LOADING . . . . . . ', 50);
            EventText.scrollFactor.set();
            EventText.setFormat(Assets.getFont("assets/fonts/loadText.ttf").fontName, 50, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
            EventText.antialiasing = ClientPrefs.data.antialiasing;
            add(EventText);
            
            if(!isTransIn) {
                try{
                    FlxG.sound.play(Paths.sound('NFE/loading_close_alpha'));
                }
                WaterMark.alpha = 0;
                EventText.alpha = 0;
                loadAlpha.alpha = 0;
                loadAlphaTween = FlxTween.tween(loadAlpha, {alpha: 1}, duration, {
                    onComplete: function(twn:FlxTween) {
                        if(finishCallback != null) {
                            finishCallback();
                        }
                    },
                ease: FlxEase.sineInOut});
                
                loadTextTween = FlxTween.tween(WaterMark, {alpha: 1}, duration, {
                    onComplete: function(twn:FlxTween) {
                        if(finishCallback != null) {
                            finishCallback();
                        }
                    },
                ease: FlxEase.sineInOut});
                
                EventTextTween = FlxTween.tween(EventText, {alpha: 1}, duration, {
                    onComplete: function(twn:FlxTween) {
                        if(finishCallback != null) {
                            finishCallback();
                        }
                    },
                ease: FlxEase.sineInOut});
                
            } else {
                try{
                    FlxG.sound.play(Paths.sound('NFE/loading_open_alpha'));
                }
                EventText.text = 'COMPLETED !';
                loadAlphaTween = FlxTween.tween(loadAlpha, {alpha: 0}, duration, {
                    onComplete: function(twn:FlxTween) {
                        close();
                    },
                ease: FlxEase.sineInOut});
                
                loadTextTween = FlxTween.tween(WaterMark, {alpha: 0}, duration, {
                    onComplete: function(twn:FlxTween) {
                        close();
                    },
                ease: FlxEase.sineInOut});
                
                EventTextTween = FlxTween.tween(EventText, {alpha: 0}, duration, {
                    onComplete: function(twn:FlxTween) {
                        close();
                    },
                ease: FlxEase.sineInOut});
                
                
                }
            } else if (currentStyle == 'Blue Archive') {
            // 每次转场重建保护列表：否则历史转场的贴图会被 static 数组永久保活，
            // 还会让 Shift+F5 的全清误把这些旧图当成受保护对象跳过。
            protectedGraphics = [];
            // 初始化图片列表（只在第一次加载时）
            //
            // 图片列表以前只从「本地文件系统」枚举，一旦 CopyState 复制失败，本地目录缺图，
            // 列表就会变空/残缺，转场随即看不到图。这里改为优先用资源清单(OpenFLAssets.list)
            // 枚举 —— Paths.image() 在本地文件缺失时会自动回退到 APK 内的 IMAGE 资源，
            // 因此只要 key 正确就能取到图，不再受复制结果影响。
            if (kathyImages.length == 0) {
                var language:String = ClientPrefs.data.blueArchiveLanguage;
                var basePath:String = 'menuExtend/CustomFadeTransition/Blue_Archive/' + language + '/';
                var imagePath = Paths.getPath('images/menuExtend/CustomFadeTransition/Blue_Archive/' + language + '/', IMAGE);

                // 1) 本地文件系统（若已复制）
                if (FileSystem.exists(imagePath)) {
                    for (file in FileSystem.readDirectory(imagePath)) {
                        if (Path.extension(file).toLowerCase() != 'txt') {
                            kathyImages.push(basePath + Path.withoutExtension(file));
                        }
                    }
                }

                // 2) 资源清单兜底：从 APK 打包资源里枚举，避免本地缺图导致列表为空
                if (kathyImages.length == 0) {
                    var prefix:String = 'assets/shared/images/' + basePath;
                    for (asset in Assets.list()) {
                        if (asset.startsWith(prefix) && Path.extension(asset).toLowerCase() != 'txt') {
                            var rel:String = asset.substr(prefix.length);
                            kathyImages.push(basePath + Path.withoutExtension(rel));
                        }
                    }
                }

                // 3) 仍然没有就用一个确定存在的 key（跟随当前语言，含 CN 的 _kr 命名差异）
                if (kathyImages.length == 0)
                    kathyImages.push(baImageKey(37));
            }

            // 随机选择新图片（确保不重复）
            if (!isTransIn) {
                ClientPrefs.data.randomIndex = FlxG.random.int(0, kathyImages.length - 1, [lastRandomIndex]);
            }

            // 存档里的索引可能越界：换语言 / 换模组后图片数量会变，且 isTransIn 时
            // 不重新随机、直接沿用上一次的值（ClientPrefs 默认是 32）。越界后
            // kathyImages[...] 为 null → Paths.image(null) → StringMap.exists(null)
            // → hxSehException，表现为「进不去曲目」。这里统一钳制回合法范围。
            if (kathyImages.length == 0)
                kathyImages.push(baImageKey(37));
            var imgIndex:Int = ClientPrefs.data.randomIndex;
            if (imgIndex < 0 || imgIndex >= kathyImages.length)
            {
                imgIndex %= kathyImages.length;
                if (imgIndex < 0) imgIndex += kathyImages.length;
            }
            ClientPrefs.data.randomIndex = imgIndex;
            lastRandomIndex = imgIndex;

            transBlack = new FlxSprite().makeGraphic(1, 1, FlxColor.BLACK);
            transBlack.setGraphicSize(FlxG.width * 1.2, FlxG.height * 1.2);
            transBlack.updateHitbox();
            transBlack.scrollFactor.set();
            transBlack.screenCenter();
            add(transBlack);
            // 黑色遮罩也在 bitmap 缓存里，Shift+F5 全清时须保护，否则定格画面露出绿色占位色
            protectedGraphics.push(transBlack.graphic);

            // transBG 没有被 add 到显示列表，却每次转场都要同步解码一张整屏 PNG，
            // 是纯粹的主线程开销，这里不再加载。若之后要用回来，把下面几行取消注释即可。
            // transBG = new FlxSprite(0, 0).loadGraphic(Paths.image('menuExtend/CustomFadeTransition/BA/Login_Pad_BG'));
            // transBG.updateHitbox();
            // transBG.scrollFactor.set();
            // transBG.screenCenter();
            // add(transBG);

            // 图片加载（完全按照NovaFlare的方式）
            // Shift+F5 全清时强制显示指定图片（如 37 号贴图），一次性消费
            var imgKey:String = (forceBAImage != null) ? forceBAImage : kathyImages[ClientPrefs.data.randomIndex];
            forceBAImage = null;
            var loadingGraphic = Paths.image(imgKey); // 记录当前转场图，供全清时保护

            // 缺图兜底：资源复制失败时 Paths.image() 会返回 null，loadGraphic(null)
            // 会让 frameWidth=0 → setGraphicSize 算出 Infinity → updateHitbox 得 NaN，
            // 下一帧 tween 读起始值时就抛 "not numeric"。这里必须保证拿到有效 graphic。
            if (loadingGraphic == null)
                loadingGraphic = Paths.image(baImageKey(37));
            if (loadingGraphic == null)
            {
                // 连兜底图都没有：造一张纯色图，保证尺寸有限、流程不中断
                var solid:BitmapData = new BitmapData(Std.int(FlxG.width), Std.int(FlxG.height), true, FlxColor.BLACK);
                solid.fillRect(solid.rect, FlxColor.BLACK);
                loadingGraphic = FlxGraphic.fromBitmapData(solid);
            }
            protectedGraphics.push(loadingGraphic);
            baLoadingPics = new FlxSprite(0, 0).loadGraphic(loadingGraphic);
            baLoadingPics.scrollFactor.set();
            baLoadingPics.antialiasing = ClientPrefs.data.antialiasing;
            
            // 自适应屏幕尺寸，所有语言都使用 16:9 比例（80% 屏幕大小）
            var targetAspectRatio:Float = 16.0 / 9.0;
            var targetWidth:Float = FlxG.width * 0.80;
            var targetHeight:Float = targetWidth / targetAspectRatio;
            
            // 如果目标高度超过屏幕高度，则按高度调整
            if (targetHeight > FlxG.height * 0.80) {
                targetHeight = FlxG.height * 0.80;
                targetWidth = targetHeight * targetAspectRatio;
            }
            
            // NaN 拦截：即使上面兜底失效，也不能让无效尺寸进入 tween。
            // setGraphicSize 在 frameWidth=0 时会算出 Infinity，updateHitbox 再变 NaN，
            // 最终 FlxTween.tween({y: NaN}) 在 setStartValues 抛 "not numeric"。
            var frameOk:Bool = baLoadingPics.frameWidth > 0 && baLoadingPics.frameHeight > 0
                && Math.isFinite(baLoadingPics.frameWidth) && Math.isFinite(baLoadingPics.frameHeight);
            if (frameOk) {
                baLoadingPics.setGraphicSize(Std.int(targetWidth), Std.int(targetHeight));
                baLoadingPics.updateHitbox();
            }

            // 正确居中；若尺寸异常则用屏幕中心，保证坐标有限
            if (frameOk && Math.isFinite(baLoadingPics.width) && Math.isFinite(baLoadingPics.height)) {
                baLoadingPics.x = (FlxG.width - baLoadingPics.width) / 2;
                baLoadingPics.y = (FlxG.height - baLoadingPics.height) / 2;
            } else {
                baLoadingPics.x = FlxG.width / 2;
                baLoadingPics.y = FlxG.height / 2;
            }

            add(baLoadingPics);

            // 保存图片的最终位置，并做最后一道有限值钳制
            var finalY:Float = baLoadingPics.y;
            if (!Math.isFinite(finalY))
                finalY = (FlxG.height - targetHeight) / 2;
            if (!Math.isFinite(finalY))
                finalY = FlxG.height / 2;
            baLoadingPics.y = finalY;

            // 透明通道设置和初始位置
            baLoadingPics.alpha = isTransIn ? 1 : 0;
            if (!isTransIn) {
                // 渐显：从屏幕下方开始
                baLoadingPics.y = 100;
            }
            // 渐隐：从当前位置开始，飞出到下方

            // 简易Loading文本（右下角）
            // Shift+F5 全清时可覆盖 reload 文案与偏红字体色
            var loadingText:String = isTransIn ? 'Done!' : (isReloadingTransition ? 'Reloading...' : 'Loading...');
            var eventColor:Int = FlxColor.WHITE;
            if (forceReloadText != null && !isTransIn) { loadingText = forceReloadText; }
            if (forceReloadColor >= 0) { eventColor = forceReloadColor; }
            // 一次性消费，避免影响后续正常转场
            forceReloadText = null;
            forceReloadColor = -1;
            // 宽度足够容纳单行文案（原 250 会让较长文案折成多行）
            EventText = new FlxText(FlxG.width - 520, FlxG.height - 150, 440, loadingText, 36);
            EventText.scrollFactor.set();
            EventText.setFormat(Assets.getFont("assets/fonts/arturito-slab.ttf").fontName, 36, eventColor, RIGHT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
            EventText.antialiasing = ClientPrefs.data.antialiasing;
            EventText.alpha = isTransIn ? 1 : 0;
            add(EventText);

            // 显示要 reload 的 state 名称（只在 reload 操作时显示）
            if (isReloadingTransition && savedReloadingStateType != null) {
                var stateName:String = Type.getClassName(savedReloadingStateType);
                StateNameText = new FlxText(FlxG.width - 750, FlxG.height - 105, FlxG.width - 600, stateName, 28);
                StateNameText.scrollFactor.set();
                StateNameText.setFormat(Assets.getFont("assets/fonts/arturito-slab.ttf").fontName, 28, FlxColor.YELLOW, RIGHT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
                StateNameText.antialiasing = ClientPrefs.data.antialiasing;
                StateNameText.alpha = 1; // 初始显示（reload 时需要显示）
                add(StateNameText);
            }

            // 动画效果
            if (!isTransIn) {
                FlxG.sound.play(Paths.sound('BA/UI_Loading'));
                // 从下方飞入 + 淡入
                baLoadingPicTween = FlxTween.tween(baLoadingPics, {y: finalY, alpha: 1}, duration, {
                    onComplete: function(twn:FlxTween) {
                        if (finishCallback != null) finishCallback();
                    },
                    ease: FlxEase.quartOut
                });
                EventText.alpha = 1;
                if (StateNameText != null) {
                    StateNameText.alpha = 1; // 确保 StateNameText 也显示
                }
            } else {
                FlxG.sound.play(Paths.sound('BA/UI_Login'));
                // 修改文本为Done!
                EventText.text = 'Done!';
                EventText.alpha = 1;
                // 设置文本淡出动画（比图片稍早一点完成）
                FlxTween.tween(EventText, {alpha: 0}, duration * 0.7, {ease: FlxEase.linear});

                // StateNameText 也淡出
                if (StateNameText != null) {
                    StateNameText.alpha = 1;
                    FlxTween.tween(StateNameText, {alpha: 0}, duration * 0.7, {ease: FlxEase.linear});
                }

                // 飞出到下方 + 淡出
                baLoadingPicTween = FlxTween.tween(baLoadingPics, {y: 100, alpha: 0}, duration, {
                    onComplete: function(twn:FlxTween) {
                        close();
                    },
                    ease: FlxEase.quartIn
                });
            }
        } else if (currentStyle == 'None') {
            // 无转场效果：不渲染任何视觉元素
        } else {
            //原版
            transGradient = FlxGradient.createGradientFlxSprite(1, height, (isTransIn ? [0x0, FlxColor.BLACK] : [FlxColor.BLACK, 0x0]));
            transGradient.scale.x = width;
            transGradient.updateHitbox();
            transGradient.scrollFactor.set();
            transGradient.screenCenter(X);
            add(transGradient);
            transBlack = new FlxSprite().makeGraphic(1, 1, FlxColor.BLACK);
            transBlack.scale.set(width, height + 400);
            transBlack.updateHitbox();
            transBlack.scrollFactor.set();
            transBlack.screenCenter(X);
            add(transBlack);
            if (isTransIn)
                transGradient.y = transBlack.y - transBlack.height;
            else
                transGradient.y = -transGradient.height;
        }

        super.create();
    }

    function updateGlowImage() {
        if (baGlowPics != null && baGlowImages.length > 0) {
            var frameIndex = Std.int(Math.min(currentImageIndex, baGlowImages.length - 1));
            baGlowPics.loadGraphic(Paths.image(baGlowImages[frameIndex]));
            baGlowPics.updateHitbox();
            baGlowPics.screenCenter();
        }
    }

    override function update(elapsed: Float) {
        if (currentStyle == 'BA_Schale_Glow') {
            imageTimer += elapsed;
            
            // Update frame if enough time has passed
            if (imageTimer >= frameDuration) {
                imageTimer = 0;
                
                if (!isTransIn) {
                    // Transition in: show frames 0-33
                    if (currentImageIndex < 33) {
                        currentImageIndex++;
                        updateGlowImage();
                    } else {
                        // Transition complete
                        if (finishCallback != null) {
                            finishCallback();
                        }
                    }
                } else {
                    // Transition out: show frames 33-39
                    if (currentImageIndex < totalFrames) {
                        currentImageIndex++;
                        updateGlowImage();
                    } else {
                        // Transition complete
                        close();
                    }
                }
            }
        } else if (currentStyle == 'V-Slice') {
            super.update(elapsed);
            final height: Float = FlxG.height * Math.max(camera.zoom, 0.001);
            final targetPos: Float = transGradient.height + 50 * Math.max(camera.zoom, 0.001);
            if (duration > 0)
                transGradient.y += (height + targetPos) * elapsed / duration;
            else
                transGradient.y = (targetPos) * elapsed;
            if (isTransIn)
                transBlack.y = transGradient.y + transGradient.height;
            else
                transBlack.y = transGradient.y - transBlack.height;
            if (transGradient.y >= targetPos) {
                close();
                if (finishCallback != null) finishCallback();
                finishCallback = null;
            }
        } else if (currentStyle == 'Blue Archive') {
		transBlack.alpha = baLoadingPics.alpha;
           // transBG.alpha = baLoadingPics.alpha;
           /* if (baLoadingPics.alpha <= 0) {
                close();
                if (finishCallback != null) finishCallback();
                finishCallback = null;
            }
*/
			/*//还没改
            super.update(elapsed);
            final height: Float = FlxG.height * Math.max(camera.zoom, 0.001);
            final targetPos: Float = transGradient.height + 50 * Math.max(camera.zoom, 0.001);
            if (duration > 0)
                transGradient.y += (height + targetPos) * elapsed / duration;
            else
                transGradient.y = (targetPos) * elapsed;
            if (isTransIn)
                transBlack.y = transGradient.y + transGradient.height;
            else
                transBlack.y = transGradient.y - transBlack.height;
            if (transGradient.y >= targetPos) {
                close();
                if (finishCallback != null) finishCallback();
                finishCallback = null;
            }*/
        } else if (currentStyle == 'None') {
            // 无转场效果：立即触发回调（切换状态）并关闭，不渲染任何视觉元素
            if (finishCallback != null) finishCallback();
            finishCallback = null;
            close();
        }
    }
}