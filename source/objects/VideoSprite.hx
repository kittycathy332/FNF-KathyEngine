package objects;

import flixel.addons.display.FlxPieDial;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.graphics.FlxGraphic;
import openfl.display.BitmapData;
import openfl.geom.Point;
import openfl.geom.Rectangle;

#if hxvlc
import hxvlc.flixel.FlxVideoSprite;
#end

class VideoSprite extends FlxSpriteGroup {
	#if VIDEOS_ALLOWED
	public var finishCallback:Void->Void = null;
	public var onSkip:Void->Void = null;

	final _timeToSkip:Float = 1;
	public var holdingTime:Float = 0;
	public var videoSprite:FlxVideoSprite;
	public var skipSprite:FlxPieDial;
	public var cover:FlxSprite;
	public var canSkip(default, set):Bool = false;

	private var videoName:String;

	public var waiting:Bool = false;

	// ===== 离线渲染逐帧模式 =====
	var renderFrames:backend.RenderVideoFrames = null;
	var renderSprite:FlxSprite = null;
	var renderBd:BitmapData = null;
	var renderStartMs:Float = 0;
	var renderPlaying:Bool = false;
	var renderDone:Bool = false;
	var renderRate:Float = 1;
	var renderLoop:Bool = false;

	public function new(videoName:String, isWaiting:Bool, canSkip:Bool = false, shouldLoop:Dynamic = false) {
		super();

		this.videoName = videoName;
		scrollFactor.set();
		cameras = [FlxG.cameras.list[FlxG.cameras.list.length - 1]];

		waiting = isWaiting;
		if(!waiting)
		{
			cover = new FlxSprite().makeGraphic(1, 1, FlxColor.BLACK);
			cover.scale.set(FlxG.width + 100, FlxG.height + 100);
			cover.screenCenter();
			cover.scrollFactor.set();
			add(cover);
		}

		// 离线渲染：hxvlc 走真实墙钟且 bitmap 挂在 OpenFL 最顶层，无法跟随虚拟时钟。
		// 这里改用预解码帧 + 普通 FlxSprite；对象仍然由调用方照常 add，
		// 所以它在哪个图层、用哪个相机，完全由游戏原本的逻辑决定。
		if(backend.RenderClock.active)
		{
			initRenderFrames(videoName, shouldLoop);
			if(canSkip) this.canSkip = true;
			return;
		}

		// initialize sprites
		videoSprite = new FlxVideoSprite();
		videoSprite.antialiasing = ClientPrefs.data.antialiasing;
		add(videoSprite);
		if(canSkip) this.canSkip = true;

		// callbacks
		if(!shouldLoop) videoSprite.bitmap.onEndReached.add(finishVideo);

		videoSprite.bitmap.onFormatSetup.add(function()
		{
			videoSprite.setGraphicSize(FlxG.width);
			videoSprite.updateHitbox();
			videoSprite.screenCenter();
		});

		// start video and adjust resolution to screen size
		videoSprite.load(videoName, shouldLoop ? ['input-repeat=65545'] : null);
	}

	function initRenderFrames(name:String, shouldLoop:Dynamic)
	{
		renderLoop = (shouldLoop == true)
			|| (Std.string(shouldLoop).indexOf('input-repeat') >= 0);

		// 设置页「视频过场」：Skip 完全不解码、不占空间；Freeze 只取首帧。
		var d = ClientPrefs.data;
		var mode:String = (d == null || d.renderCutscene == null) ? 'FFmpeg' : d.renderCutscene;

		var fps:Int = backend.RenderClock.videoFps();
		var w:Int = FlxG.width;
		var h:Int = FlxG.height;
		var cacheDir:String = backend.RenderClock.outputDir + 'video_cache/';
		renderFrames = new backend.RenderVideoFrames(name, fps, w, h, cacheDir,
			backend.RenderClock.videoLog, mode);

		// 保留 videoSprite 供模组脚本访问 bitmap.rate 等字段（不 load、不显示）。
		videoSprite = new FlxVideoSprite();
		try { videoSprite.bitmap.rate = 1; } catch (e:Dynamic) {}

		if(mode == 'Skip')
		{
			// 不建 renderSprite：下一帧 updateRenderFrames 立即收尾走回调，
			// 游戏按原本流程开倒计时/推进，成片里完全没有视频内容。
			return;
		}

		if(renderFrames.ready)
		{
			// 固定的 BitmapData + 每帧 copyPixels；避免反复 loadGraphic 产生
			// 无法释放的 FlxGraphic，那样长时间播放会越渲越卡。
			renderBd = new BitmapData(w, h, true, 0);
			renderSprite = new FlxSprite();
			renderSprite.loadGraphic(FlxGraphic.fromBitmapData(renderBd, false, null, false));
			renderSprite.scrollFactor.set();
			renderSprite.screenCenter();
			add(renderSprite);
		}
		else
			backend.RenderClock.videoLog('[video] fallback, no frames: ' + renderFrames.error);
	}

	function updateRenderFrames()
	{
		if(!renderPlaying || renderDone || renderFrames == null) return;

		// Skip：视频不进入成片，立刻正常收尾（finishCallback 会开倒计时/推进流程）。
		if(renderFrames.mode == 'Skip')
		{
			backend.RenderClock.videoLog('[video] SKIP finished immediately: ' + videoName);
			renderDone = true;
			renderPlaying = false;
			finishVideo();
			return;
		}
		if(renderSprite == null) return;

		try { renderRate = videoSprite.bitmap.rate; } catch (e:Dynamic) {}
		if(renderRate <= 0) renderRate = 1;

		var now:Float = backend.RenderClock.videoMs();
		var deltaMs:Float = (now - renderStartMs) * renderRate;
		var idx:Int = Std.int(deltaMs / 1000 * renderFrames.fps);

		if(idx >= renderFrames.totalFrames)
		{
			if(renderLoop)
			{
				renderStartMs = now;
				idx = 0;
			}
			else
			{
				renderDone = true;
				renderPlaying = false;
				finishVideo();
				return;
			}
		}
		if(idx < 0) idx = 0;

		var bd:BitmapData = renderFrames.getFrame(idx);
		if(bd == null || renderBd == null) return;
		try
		{
			renderBd.copyPixels(bd, new Rectangle(0, 0, bd.width, bd.height), new Point(0, 0));
		}
		catch (e:Dynamic)
		{
			backend.RenderClock.videoLog('[video] copyPixels failed: ' + Std.string(e));
		}
	}

	var alreadyDestroyed:Bool = false;
	override function destroy()
	{
		if(alreadyDestroyed)
			return;

		trace('Video destroyed');
		if(cover != null)
		{
			remove(cover);
			cover.destroy();
		}

		if(renderFrames != null)
		{
			renderFrames.dispose();
			renderFrames = null;
		}
		// 渲染模式下 stub 没有 add 进 group，需要手动释放它挂到 FlxG.game 的 bitmap
		if(backend.RenderClock.active && videoSprite != null)
		{
			try { videoSprite.destroy(); } catch (e:Dynamic) {}
			videoSprite = null;
		}

		finishCallback = null;
		onSkip = null;

		if(FlxG.state != null)
		{
			if(FlxG.state.members.contains(this))
				FlxG.state.remove(this);

			if(FlxG.state.subState != null && FlxG.state.subState.members.contains(this))
				FlxG.state.subState.remove(this);
		}
		super.destroy();
		alreadyDestroyed = true;
	}
	function finishVideo()
	{
		if (!alreadyDestroyed)
		{
			if(finishCallback != null)
				finishCallback();

			destroy();
		}
	}

	override function update(elapsed:Float)
	{
		if(renderFrames != null)
		{
			updateRenderFrames();
			if(alreadyDestroyed) return;
		}
		else if(canSkip)
		{
			if(Controls.instance.pressed('accept'))
			{
				holdingTime = Math.max(0, Math.min(_timeToSkip, holdingTime + elapsed));
			}
			else if (holdingTime > 0)
			{
				holdingTime = Math.max(0, FlxMath.lerp(holdingTime, -0.1, FlxMath.bound(elapsed * 3, 0, 1)));
			}
			updateSkipAlpha();

			if(holdingTime >= _timeToSkip)
			{
				if(onSkip != null) onSkip();
				finishCallback = null;
				videoSprite.bitmap.onEndReached.dispatch();
				trace('Skipped video');
				return;
			}
		}
		super.update(elapsed);
	}

	function set_canSkip(newValue:Bool)
	{
		canSkip = newValue;
		if(canSkip)
		{
			if(skipSprite == null)
			{
				skipSprite = new FlxPieDial(0, 0, 40, FlxColor.WHITE, 40, true, 24);
				skipSprite.replaceColor(FlxColor.BLACK, FlxColor.TRANSPARENT);
				skipSprite.x = FlxG.width - (skipSprite.width + 80);
				skipSprite.y = FlxG.height - (skipSprite.height + 72);
				skipSprite.amount = 0;
				add(skipSprite);
			}
		}
		else if(skipSprite != null)
		{
			remove(skipSprite);
			skipSprite.destroy();
			skipSprite = null;
		}
		return canSkip;
	}

	function updateSkipAlpha()
	{
		if(skipSprite == null) return;
		skipSprite.amount = Math.min(1, Math.max(0, (holdingTime / _timeToSkip) * 1.025));
		skipSprite.alpha = FlxMath.remapToRange(skipSprite.amount, 0.025, 1, 0, 1);
	}

	public function play()
	{
		if(renderFrames != null)
		{
			renderPlaying = true;
			renderDone = false;
			renderStartMs = backend.RenderClock.videoMs();
			if(renderFrames.mode != 'Skip' && renderFrames.audioPath != '' && backend.RenderClock.active)
			{
				backend.RenderClock.registerVideoAudio(renderFrames.audioPath,
					renderStartMs, renderFrames.durationMs, 1);
			}
			return;
		}
		videoSprite?.play();
	}
	public function resume()
	{
		if(renderFrames != null) { renderPlaying = true; return; }
		videoSprite?.resume();
	}
	public function pause()
	{
		if(renderFrames != null) { renderPlaying = false; return; }
		videoSprite?.pause();
	}
	#end
}
