package substates;

import haxe.Exception;
/*#if FEATURE_STEPMANIA
	import smTools.SMFile;
	#end */
#if FEATURE_FILESYSTEM
import sys.FileSystem;
import sys.io.File;
#end
import states.StoryMenuState;
import states.FreeplayState;
import states.PlayState;
import states.MainMenuState;
import backend.Mods;
import backend.Song;
import backend.Rating;
import backend.ClientPrefs;
import backend.Difficulty;
import backend.Highscore;
import openfl.geom.Matrix;
import openfl.display.BitmapData;
import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFormatAlign;
import openfl.text.TextFieldAutoSize;
import flixel.system.FlxSound;
import flixel.util.FlxAxes;
import flixel.FlxSubState;
import flixel.input.FlxInput;
import flixel.input.keyboard.FlxKey;
import flixel.FlxG;
import flixel.FlxObject;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.util.FlxColor;
import lime.app.Application;
import flixel.math.FlxMath;
import flixel.util.FlxTimer;
import backend.HitGraph;
import backend.ui.PsychUIButton;
import backend.Language;
import states.editors.content.Prompt;
import flixel.text.FlxText;

using StringTools;
using DateTools;

class ResultsScreen extends FlxSubState
{
	// OpenFL 层容器
	public var overlaySprite:Sprite;

	public var background:FlxSprite;
	public var text:TextField;

	public var graph:HitGraph;

	public var comboText:TextField;
	public var contText:TextField;
	public var settingsText:TextField;
	public var replayText:TextField;

	public var music:FlxSound;

	public var graphData:BitmapData;

	public var ranking:String;
	public var accuracy:String;

	public var canReplay:Bool = false; // 是否可以回放
	public var replayPressed:Bool = false; // 是否按下了回放键
	public var savePressed:Bool = false; // 是否按下保存回放键（防抖）

	private var saveReplayTimer:FlxTimer = null; // 保存回放的提示定时器

	// 移动端按钮"二次确认"状态：第一次点击进入待确认，第二次点击才真正执行
	private var pendingBtn:PsychUIButton = null; // 当前处于待确认状态的按钮
	private var pendingBtnOrigLabel:String = '';
	private var pendingBtnOrigBg:FlxColor = FlxColor.WHITE;
	private var pendingBtnOrigFg:FlxColor = FlxColor.WHITE;
	private var pendingBtnTime:Float = 0;
	private static inline var PENDING_CONFIRM_TIME:Float = 3.0; // 待确认超时时间（秒）
	private static inline var ARM_BG:FlxColor = 0xFFFFDD00; // 待确认时的醒目底色
	private static inline var ARM_FG:FlxColor = FlxColor.BLACK; // 待确认时的文字色

	// 移动端一次物理按压可能同时触发 PsychUIButton 的 touch 与 mouse 两个回调（触摸会映射到鼠标），
	// 导致二次确认的"第一次点击"被误判成"再次点击"而直接执行。用时间窗去抖拦截同一次按压的重复回调。
	// 使用 openfl.Lib.getTimer() 的毫秒值作为时间戳（FlxG 无全局运行时间字段）。
	private var lastBtnClickTick:Float = -100; // 最近一次按钮回调触发的时间戳（毫秒）
	private static inline var BTN_DEBOUNCE:Float = 150; // 去抖时间窗（毫秒）

	override function create()
	{
		// 创建 OpenFL 层容器
		overlaySprite = new Sprite();

		// 创建背景（Flixel 对象）
		background = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, FlxColor.BLACK);
		background.alpha = 0;
		background.scrollFactor.set();
		add(background);

		// 将 overlay 添加到 OpenFL stage 的最顶层
		if (FlxG.stage != null)
		{
			FlxG.stage.addChild(overlaySprite);
		}

		// 获取实际的物理屏幕尺寸
		var stageWidth:Float = FlxG.stage.stageWidth;
		var stageHeight:Float = FlxG.stage.stageHeight;

		// 计算缩放比例（基于逻辑分辨率到物理分辨率的比例）
		var scaleX:Float = stageWidth / 1280;
		var scaleY:Float = stageHeight / 720;
		var scale:Float = Math.min(scaleX, scaleY); // 保持宽高比

		// 创建 HitGraph（偏右上角，宽度放大一倍，高度适中）
		graph = new HitGraph(Math.floor(stageWidth - 560 * scale), Math.floor(20 * scale), Math.floor(500 * scale), Math.floor(250 * scale));
		graph.alpha = 0;
		overlaySprite.addChild(graph);

		// if (!PlayState.inResults)
		{
			music = new FlxSound().loadEmbedded(Paths.music('breakfast'), true, true);
			music.volume = 0;
			music.play(false, FlxG.random.int(0, Std.int(music.length / 2)));
			FlxG.sound.list.add(music);
		}

		// 统计判定数量
		var perfects = 0;
		var sicks = 0;
		var goods = 0;
		var bads = 0;
		var shits = 0;
		for (r in PlayState.instance.ratingsData)
		{
			switch (r.name)
			{
				case "perfect":
					perfects = r.hits;
				case "sick":
					sicks = r.hits;
				case "good":
					goods = r.hits;
				case "bad":
					bads = r.hits;
				case "shit":
					shits = r.hits;
			}
		}

		// 创建标题文本（偏左上角）
		text = createTextField(Math.floor(20 * scale), Math.floor(-80 * scale), Math.floor(stageWidth - 300 * scale), FlxColor.WHITE, Math.floor(42 * scale),
			Paths.font(Language.get('uitab_font')));
		text.text = Language.get('results_song_cleared');
		overlaySprite.addChild(text);

		var score = PlayState.instance.songScore;
		if (PlayState.isStoryMode)
		{
			score = PlayState.campaignScore;
			text.text = Language.get('results_week_cleared');
		}

		// 组合文本
		var sickPlus:Int = PlayState.instance.songSickPlus;
		var comboStr = 'Judgements:\n'
			+ (ClientPrefs.data.rmPerfect == 'enable' ? 'Perfects - ${perfects}\n' : "")
			+ 'Sicks - ${sicks}' + (ClientPrefs.data.rmPerfect == 'sickPlus' && sickPlus > 0 ? ' (Sick+ : ${sickPlus})' : '') + '\n'
			+ 'Goods - ${goods}\n'
			+ 'Bads - ${bads}\n'
			+ 'Shits - ${shits}\n\n'
			+ 'Combo Breaks: ${PlayState.instance.songMisses}\n'
			+ 'Score: ${PlayState.instance.songScore}\n'
			+ 'Accuracy: ${Std.string(Math.floor(PlayState.instance.ratingPercent * 10000) / 100)}%\n\n\n'
			+ 'Note Rate: ${PlayState.instance.songSpeed} x';

		// 创建判定文本（偏左并垂直居中）
		var comboTextY = (stageHeight - Math.floor(150 * scale)) / 2;
		comboText = createTextField(Math.floor(20 * scale), Math.floor(-100 * scale), Math.floor(stageWidth - 300 * scale), FlxColor.WHITE,
			Math.floor(32 * scale));
		comboText.text = comboStr;
		overlaySprite.addChild(comboText);

		// 为每个判定添加不同颜色
		var idx = 0;
		if (ClientPrefs.data.rmPerfect == 'enable')
		{
			idx = comboStr.indexOf('Perfects');
			comboText.setTextFormat(new TextFormat("assets/fonts/vcr.ttf", Math.floor(32 * scale), 0xFFFFC0CB), idx, idx + ('Perfects - ${perfects}'.length));
		}
		idx = comboStr.indexOf('Sicks');
		var sicksLineLen:Int = 'Sicks - ${sicks}'.length + (ClientPrefs.data.rmPerfect == 'sickPlus' && sickPlus > 0 ? ' (Sick+ - ${sickPlus})'.length : 0);
		comboText.setTextFormat(new TextFormat("assets/fonts/vcr.ttf", Math.floor(32 * scale), 0xFF87CEFA), idx, idx + sicksLineLen);
		idx = comboStr.indexOf('Goods');
		comboText.setTextFormat(new TextFormat("assets/fonts/vcr.ttf", Math.floor(32 * scale), 0xFF66CDAA), idx, idx + ('Goods - ${goods}'.length));
		idx = comboStr.indexOf('Bads');
		comboText.setTextFormat(new TextFormat("assets/fonts/vcr.ttf", Math.floor(32 * scale), 0xFFF4A460), idx, idx + ('Bads - ${bads}'.length));
		idx = comboStr.indexOf('Shits');
		comboText.setTextFormat(new TextFormat("assets/fonts/vcr.ttf", Math.floor(32 * scale), 0xFFFF4500), idx, idx + ('Shits - ${shits}'.length));

		// contText（偏右下角）
		contText = createTextField(Math.floor(stageWidth - 520 * scale), Math.floor(stageHeight + 80 * scale), Math.floor(500 * scale), FlxColor.WHITE,
			Math.floor(32 * scale), Paths.font(Language.get('uitab_font')));
		if (PlayState.isCommandLineMode)
		{
			// 命令行直启：回车退出游戏，且不支持回看/保存回放
			contText.text = #if mobile '' #else 'Press \'ENTER\' to exit.' #end;
		}
		else
		{
			// 移动端已改用右下角按钮，不再显示触摸屏幕提示文字
			contText.text = #if mobile '' #else Language.get('results_ctrl_hint') #end;
		}
		overlaySprite.addChild(contText);

		// 修正底部信息位置：文本右缘贴齐画面右边距，底部贴齐底部边距。
		// 之前 y 用了固定值 stageHeight - 60*scale，而提示是多行文本（约3行），
		// 实际高度超出预留空间导致内容溢出屏幕底部。现按真实文本高度计算目标 y。
		var contTextX:Float = contText.x;
		var contTextY:Float = stageHeight - 60 * scale;
		#if !mobile
		if (Std.string(contText.text).length > 0)
		{
			var infoMargin:Float = 20 * scale;
			contTextX = stageWidth - infoMargin - contText.textWidth;
			contTextY = stageHeight - infoMargin - contText.textHeight;
		}
		#end

		// 检查是否有回放数据
		canReplay = PlayState.instance.replayData != null && PlayState.instance.replayData.length > 0;

		// 填充 HitGraph 数据（graph 已经添加到 overlaySprite 了）
		if (PlayState.instance.hitHistory != null && PlayState.instance.hitHistory.length > 0)
		{
			for (hitData in PlayState.instance.hitHistory)
			{
				graph.addToHistory(hitData[0], hitData[1], hitData[2]);
			}
			graph.update();
		}

		/*var sicks = PlayState.sicks;
			var goods = PlayState.goods;
		 */
		if (sicks == Math.POSITIVE_INFINITY)
			sicks = 0;
		if (goods == Math.POSITIVE_INFINITY)
			goods = 0;

		// 创建设置文本（偏左下角）
		var averageMs:Float = 0;
		// if (PlayState.instance.songHits > 0)
		@:privateAccess
		averageMs = PlayState.instance.allNotesMs / PlayState.instance.songHits;

		settingsText = createTextField(Math.floor(20 * scale), Math.floor(stageHeight + 60 * scale), Math.floor(stageWidth - 300 * scale), FlxColor.WHITE,
			Math.floor(18 * scale), Paths.font(Language.get('uitab_font')));
		var avgVal:Float = Math.round(averageMs * 100) / 100;
		settingsText.text = '${Language.get('results_avg_label')}: ' + '$avgVal' + 'ms (' + (ClientPrefs.data.rmPerfect == 'enable' ? "PERFECT:" + ClientPrefs.data.perfectWindow + "ms," : "") + 'SICK:${ClientPrefs.data.sickWindow}ms,GOOD:${ClientPrefs.data.goodWindow}ms,BAD:${ClientPrefs.data.badWindow}ms)';
		overlaySprite.addChild(settingsText);

		/*var sicks = PlayState.sicks;
			var goods = PlayState.goods;
		 */

		// 动画效果（需要手动实现 OpenFL 对象的动画）
		FlxTween.tween(background, {alpha: 0.5}, 0.5);
		// OpenFL 对象的动画
		FlxTween.num(-80 * scale, 20 * scale, 0.5, {ease: FlxEase.expoInOut}, (val) -> text.y = val);
		FlxTween.num(-100 * scale, comboTextY, 0.5, {ease: FlxEase.expoInOut}, (val) -> comboText.y = val);
		FlxTween.num(stageHeight + 80 * scale, contTextY, 0.5, {ease: FlxEase.expoInOut}, (val) -> contText.y = val);
		contText.x = contTextX;
		FlxTween.num(stageHeight + 60 * scale, stageHeight - 50 * scale, 0.5, {ease: FlxEase.expoInOut}, (val) -> settingsText.y = val);
		FlxTween.num(0, 1.0, 0.5, {ease: FlxEase.expoInOut}, (val) -> graph.alpha = val);

		cameras = [FlxG.cameras.list[FlxG.cameras.list.length - 1]];

		#if !desktop
		// 移动端：右下角按钮（替代"触摸屏幕任意处直接继续"的逻辑）
		var btnW:Int = 150;
		var btnH:Int = 50;
		var gap:Int = 15;
		var margin:Int = 15;
		var btnY:Float = FlxG.height - btnH - margin;
		if (PlayState.isCommandLineMode)
			createMobileButton(FlxG.width - btnW - margin, btnY, btnW, btnH, Language.get('results_btn_exit'), 0xFFFF9999, 0xFF8B0000, exitGame);
		else
		{
			// 退出（对应桌面端 ENTER：非命令行返回选歌），二次确认已在按钮上实现
			createMobileButton(FlxG.width - btnW - margin, btnY, btnW, btnH, Language.get('results_btn_exit'), 0xFFFF9999, 0xFF8B0000,
				() ->
				{
					if (!replayPressed && !savePressed)
						handleContinue();
				});
			// 观看回放（对应桌面端 F8），二次确认已在按钮上实现
			if (canReplay)
				createMobileButton(FlxG.width - 2 * btnW - gap - margin, btnY, btnW, btnH, Language.get('results_btn_replay'), 0xFF99FF99, 0xFF006400,
					() ->
					{
						if (!replayPressed)
						{
							replayPressed = true;
							handleReplay();
						}
					});
			// 保存回放（对应桌面端 F9），二次确认已在按钮上实现
			createMobileButton(FlxG.width - 3 * btnW - 2 * gap - margin, btnY, btnW, btnH, Language.get('results_btn_save'), 0xFF99CCFF, 0xFF00008B,
				() ->
				{
					if (!savePressed)
					{
						savePressed = true;
						saveReplay();
					}
				});
		}
		#end

		super.create();
	}

	var frames = 0;

	// 处理继续的逻辑
	private function handleContinue():Void
	{
		trace('WENT BACK TO FREEPLAY??');
		#if DISCORD_ALLOWED DiscordClient.resetClientID(); #end
		PlayState.instance.canResync = false;
		PlayState.changedDifficulty = false;
		Mods.loadTopMod();
		FlxG.sound.playMusic(Paths.menuMusicAudio());
		MusicBeatState.switchState(new FreeplayState());
		close(); // 关闭substate
	}

	// 处理回放逻辑
	private function handleReplay():Void
	{
		trace('STARTING REPLAY...');

		if (music != null)
			music.fadeOut(0.3);

		// 设置静态变量，传递回放数据到新的PlayState
		PlayState.pendingReplayData = PlayState.instance.replayData.copy();
		PlayState.shouldStartReplay = true;
		PlayState.retainReplayOnRestart = true; // 结算切走后旧 PlayState 的 destroy() 会保留这些静态数据，供新 PlayState 继续消费并进入回放
		PlayState.isStoryMode = false;

		// 与 FreeplayState.doPlayReplay 保持一致：恢复歌曲所在模组目录，
		// 并重新解析当前歌曲谱面（applyChart），确保背景/资源按正确的目录与 SONG 加载
		var songFolder:String = PlayState._lastLoadedModDirectory;
		Mods.currentModDirectory = songFolder;
		var inst = PlayState.instance;
		if (inst != null && inst.songName != null)
		{
			try
			{
				var songLowercase:String = Paths.formatToSongPath(inst.songName);
				var poop:String = Highscore.formatSong(songLowercase, PlayState.storyDifficulty);
				Song.loadFromJson(poop, songLowercase); // 内部会 applyChart，刷新 PlayState.SONG 与谱面路径
			}
			catch (e:Dynamic)
			{
				trace('Replay: failed to reload song chart, falling back: ' + e);
			}
			Mods.currentModDirectory = songFolder;
		}

		// 预加载 stage 背景、角色等资源，避免回放时背景丢失
		LoadingState.prepareToSong();

		// 关闭substate并重新加载PlayState
		close();

		// 切换到新的PlayState（会自动加载回放数据）
		LoadingState.loadAndSwitchState(new PlayState());
	}

	// 命令行直启：退出整个游戏
	private function exitGame():Void
	{
		PlayState.instance.canResync = false;
		PlayState.changedDifficulty = false;
		if (FlxG.save != null)
			FlxG.save.flush(); // 落盘（分数等）
		close();
		#if DISCORD_ALLOWED
		DiscordClient.resetClientID();
		#end
		Sys.exit(0);
	}

	// 保存回放（对应桌面端 F9）
	private function saveReplay():Void
	{
		#if FEATURE_FILESYSTEM
		try
		{
			var moddir:String = (Mods.currentModDirectory != null && Mods.currentModDirectory.length > 0) ? Mods.currentModDirectory : 'global';
			var replayFolder:String = Paths.mods(moddir + '/replay');
			if (!FileSystem.exists(replayFolder))
				FileSystem.createDirectory(replayFolder);
			var chartPath:String = Song.chartPath != null ? Song.chartPath : (PlayState.SONG != null ? PlayState.SONG.song : '');
			var statMTime:Dynamic = null;
			if (chartPath != null)
			{
				try
				{
					var s = FileSystem.stat(chartPath);
					if (s != null && Reflect.hasField(s, 'mtime'))
						statMTime = Reflect.field(s, 'mtime');
				}
				catch (e:Dynamic)
				{
					// 文件不存在或无法访问，忽略错误，chartMTime保持为null
				}
			}
			var saveTime:String = Date.now().format('%Y-%m-%d_%H-%M-%S');
			var saveName:String = Paths.formatToSongPath(PlayState.SONG.song) + '-' + saveTime + '.replay.json';
			var savePath:String = replayFolder + '/' + saveName;

			// 统计判定分布（与结算页一致），写入 meta 供回放选择界面展示
			var judgePerfects:Int = 0;
			var judgeSicks:Int = 0;
			var judgeGoods:Int = 0;
			var judgeBads:Int = 0;
			var judgeShits:Int = 0;
			if (PlayState.instance != null && PlayState.instance.ratingsData != null)
			{
				for (r in PlayState.instance.ratingsData)
				{
					switch (r.name)
					{
						case "perfect": judgePerfects = r.hits;
						case "sick": judgeSicks = r.hits;
						case "good": judgeGoods = r.hits;
						case "bad": judgeBads = r.hits;
						case "shit": judgeShits = r.hits;
					}
				}
			}

			var outObj:Dynamic = {
				// 文件格式版本：回放协议版本 + 写入时的引擎版本。
				// 旧文件没有这两个字段，视为 v1.0（无统计字段）；未来 replay 数组结构变更时可在此做兼容判断。
				replayVersion: "2.0",
				kathyVersion: MainMenuState.kathyEngineVersion,
				meta: {
					song: PlayState.SONG.song,
					chartPath: chartPath,
					chartMTime: statMTime,
					difficulty: Difficulty.getString(PlayState.storyDifficulty, false),
					// 保存时的本机时区偏移（分钟，UTC 以东为负），供回放选择界面显示 "UTC+8" 这类地区信息
					tzOffset: Date.now().getTimezoneOffset(),
					// 回放选择界面展示用统计（旧版本回放无这些字段，选择界面会以 — 占位）
					accuracyPercent: (PlayState.instance != null) ? PlayState.instance.ratingPercent : 0,
					score: (PlayState.instance != null) ? PlayState.instance.songScore : 0,
					maxCombo: (PlayState.instance != null) ? PlayState.instance.maxCombo : 0,
					misses: (PlayState.instance != null) ? PlayState.instance.songMisses : 0,
					judgeBreakdown: {
						perfect: judgePerfects,
						sick: judgeSicks,
						good: judgeGoods,
						bad: judgeBads,
						shit: judgeShits
					},
					judgmentSettings: {
						rmPerfect: ClientPrefs.data.rmPerfect,
						perfectWindow: ClientPrefs.data.perfectWindow,
						sickWindow: ClientPrefs.data.sickWindow,
						goodWindow: ClientPrefs.data.goodWindow,
						badWindow: ClientPrefs.data.badWindow,
						safeFrames: ClientPrefs.data.safeFrames,
						ratingOffset: ClientPrefs.data.ratingOffset,
						hitsoundVolume: ClientPrefs.data.hitsoundVolume,
						noteOffset: ClientPrefs.data.noteOffset,
					},
					gameplaySettings: {
						// Basic gameplay preferences
						downScroll: ClientPrefs.data.downScroll,
						middleScroll: ClientPrefs.data.middleScroll,
						opponentStrums: ClientPrefs.data.opponentStrums,
						ghostTappingMode: ClientPrefs.data.ghostTappingMode,
						noReset: ClientPrefs.data.noReset,
						guitarHeroSustains: ClientPrefs.data.guitarHeroSustains,
						sustainTailFix: ClientPrefs.data.sustainTailFix,
						holdReleaseInstantMiss: ClientPrefs.data.holdReleaseInstantMiss,
						holdTailJudge: ClientPrefs.data.holdTailJudge,
						holdScoreBonus: ClientPrefs.data.holdScoreBonus,
						holdTailLeniency: ClientPrefs.data.holdTailLeniency,
						holdTailLeniencyMs: ClientPrefs.data.holdTailLeniencyMs,
						popUpRating: ClientPrefs.data.popUpRating,

						// Gameplay changers settings
						scrolltype: ClientPrefs.getGameplaySetting('scrolltype', 'multiplicative'),
						scrollspeed: ClientPrefs.getGameplaySetting('scrollspeed', 1.0),
						songspeed: ClientPrefs.getGameplaySetting('songspeed', 1.0),
						healthgain: ClientPrefs.getGameplaySetting('healthgain', 1.0),
						healthloss: ClientPrefs.getGameplaySetting('healthloss', 1.0),
						instakill: ClientPrefs.getGameplaySetting('instakill', false),
						practice: ClientPrefs.getGameplaySetting('practice', false),
						botplay: ClientPrefs.getGameplaySetting('botplay', false),
						playOpponent: ClientPrefs.getGameplaySetting('playOpponent', false),
						healthmodel: ClientPrefs.getGameplaySetting('healthmodel', 'default'),
						antiMash: ClientPrefs.getGameplaySetting('antiMash', false),
						breakComboOnBad: ClientPrefs.data.breakComboOnBad,
						breakComboOnShit: ClientPrefs.data.breakComboOnShit,
						accuracyMode: ClientPrefs.data.accuracyMode,
						sustainAccuracy: ClientPrefs.data.sustainAccuracy,
						kadeScoring: ClientPrefs.data.kadeScoring
					}
				},
				replay: PlayState.instance.replayData
			};
			File.saveContent(savePath, haxe.Json.stringify(outObj, "\t"));
			// 保存成功：播放提示音 + 显示屏幕中央提示（水平、垂直居中）
			FlxG.sound.play(Paths.sound('KYE/confirm_replay_save'));
			var center:TextField = createTextField(0, 0, Math.floor(600), FlxColor.WHITE, 24, Paths.font(Language.get('uitab_font')));
			center.text = Language.get('results_replay_saved', [moddir, saveName]);
			// 基于物理屏幕尺寸居中：OpenFL 同步读取文本度量（宽高），使提示真正位于画面正中间
			var sw:Float = FlxG.stage != null ? FlxG.stage.stageWidth : FlxG.width;
			var sh:Float = FlxG.stage != null ? FlxG.stage.stageHeight : FlxG.height;
			center.x = (sw - center.textWidth) / 2;
			center.y = (sh - center.textHeight) / 2;
			overlaySprite.addChild(center);

			// 使用成员变量保存timer，并添加安全检查
			saveReplayTimer = new FlxTimer();
			saveReplayTimer.start(2, function(tw:FlxTimer)
			{
				// 检查overlaySprite和center是否还存在且在舞台上
				if (overlaySprite != null && FlxG.stage != null && FlxG.stage.contains(overlaySprite))
				{
					if (center != null && overlaySprite.contains(center))
					{
						overlaySprite.removeChild(center);
					}
				}
			});
		}
		catch (e:Dynamic)
		{
			trace('Failed to save replay: ' + e);
		}
		#end
	}

	// 移动端：创建右下角按钮
	#if !desktop
	private function createMobileButton(x:Float, y:Float, w:Int, h:Int, label:String, bgColor:FlxColor, textColor:FlxColor, onClick:Void->Void):PsychUIButton
	{
		var btn:PsychUIButton = null;
		btn = new PsychUIButton(x, y, label, function()
		{
			// 去抖：拦截同一次物理按压因 touch+mouse 双回调导致的重复触发，
			// 避免二次确认的"第一次点击"被当成"再次点击"而直接执行。
			if (openfl.Lib.getTimer() - lastBtnClickTick < BTN_DEBOUNCE) return;
			lastBtnClickTick = openfl.Lib.getTimer();

			// 按钮上二次确认：第一次点击进入"再次点击确认"待确认态，第二次点击才真正执行
			if (pendingBtn == btn)
			{
				// 已处于待确认态：真正执行动作
				resetPendingConfirm();
				onClick();
			}
			else
			{
				// 重置上一个（若有）并进入待确认态
				resetPendingConfirm();
				pendingBtn = btn;
				pendingBtnOrigLabel = label;
				pendingBtnOrigBg = bgColor;
				pendingBtnOrigFg = textColor;
				pendingBtnTime = PENDING_CONFIRM_TIME;
				btn.label = Language.get('results_confirm_again');
				btn.normalStyle = {bgColor: ARM_BG, textColor: ARM_FG, bgAlpha: 1};
				btn.hoverStyle = {bgColor: ARM_BG.getLightened(0.1), textColor: ARM_FG, bgAlpha: 1};
				btn.clickStyle = {bgColor: ARM_BG.getDarkened(0.1), textColor: FlxColor.WHITE, bgAlpha: 1};
			}
		}, w, h);
		btn.text.size = 22; // 随按钮放大
		btn.text.y = y + h / 2 - btn.text.height / 2;
		btn.normalStyle = {bgColor: bgColor, textColor: textColor, bgAlpha: 1};
		btn.hoverStyle = {bgColor: bgColor.getLightened(0.2), textColor: textColor, bgAlpha: 1};
		btn.clickStyle = {bgColor: bgColor.getDarkened(0.2), textColor: FlxColor.WHITE, bgAlpha: 1};
		btn.scrollFactor.set();
		// 显式绑定与结算界面相同的 camera，避免 PsychUIButton.update 因 camera 为 null 而直接 return，导致点击失效
		btn.cameras = cameras;
		add(btn);
		return btn;
	}

	// 复位按钮的待确认状态（还原原文字与配色）
	private function resetPendingConfirm():Void
	{
		if (pendingBtn != null)
		{
			pendingBtn.label = pendingBtnOrigLabel;
			pendingBtn.normalStyle = {bgColor: pendingBtnOrigBg, textColor: pendingBtnOrigFg, bgAlpha: 1};
			pendingBtn.hoverStyle = {bgColor: pendingBtnOrigBg.getLightened(0.2), textColor: pendingBtnOrigFg, bgAlpha: 1};
			pendingBtn.clickStyle = {bgColor: pendingBtnOrigBg.getDarkened(0.2), textColor: FlxColor.WHITE, bgAlpha: 1};
			pendingBtn = null;
		}
	}

	// 移动端：通用二次确认已在按钮上实现（createMobileButton），不再使用屏幕中间弹窗。
	#end

	override function update(elapsed:Float)
	{
		super.update(elapsed);

		if (music != null)
			if (music.volume < 0.5)
				music.volume += 0.01 * elapsed;

		// 按钮"再次点击确认"待确认态超时自动复位（仅移动端按钮逻辑）
		#if !desktop
		if (pendingBtn != null)
		{
			pendingBtnTime -= elapsed;
			if (pendingBtnTime <= 0)
				resetPendingConfirm();
		}
		#end

		// keybinds

		/*if (PlayerSettings.player1.controls.ACCEPT)
			{
				if (music != null)
					music.fadeOut(0.3);

				PlayState.loadRep = false;
				PlayState.stageTesting = false;
				PlayState.rep = null;

				#if !switch
				Highscore.saveScore(PlayState.SONG.songId, Math.round(PlayState.instance.songScore), PlayState.storyDifficulty);
				Highscore.saveCombo(PlayState.SONG.songId, Ratings.GenerateLetterRank(PlayState.instance.accuracy), PlayState.storyDifficulty);
				#end

				if (PlayState.isStoryMode)
				{
					FlxG.sound.playMusic(Paths.menuMusicAudio());
					Conductor.changeBPM(102);
					FlxG.switchState(new MainMenuState());
				}
				else
					FlxG.switchState(new FreeplayState());
				PlayState.instance.clean();
		}*/
		/*if (FlxG.keys.justPressed.F1 && !PlayState.loadRep)
			{
				PlayState.rep = null;

				PlayState.loadRep = false;
				PlayState.stageTesting = false;

				#if !switch
				Highscore.saveScore(PlayState.SONG.songId, Math.round(PlayState.instance.songScore), PlayState.storyDifficulty);
				Highscore.saveCombo(PlayState.SONG.songId, Ratings.GenerateLetterRank(PlayState.instance.accuracy), PlayState.storyDifficulty);
				#end

				if (music != null)
					music.fadeOut(0.3);

				PlayState.isStoryMode = false;
				PlayState.storyDifficulty = PlayState.storyDifficulty;
				LoadingState.loadAndSwitchState(new PlayState());
				PlayState.instance.clean();
		}*/

		// 桌面端：ENTER键继续，R键回放
		if (FlxG.keys.justPressed.ENTER)
		{
			if (PlayState.isCommandLineMode)
				exitGame(); // 命令行直启：回车退出游戏
			else
				handleContinue();
		}
		else if (FlxG.keys.justPressed.F8 && canReplay && !replayPressed && !PlayState.isCommandLineMode)
		{
			replayPressed = true;
			handleReplay();
		}
		else if (FlxG.keys.justPressed.F9
			&& !PlayState.isCommandLineMode
			&& PlayState.instance != null
			&& PlayState.instance.replayData != null
			&& PlayState.instance.replayData.length > 0
			&& !savePressed)
		{
			savePressed = true;
			saveReplay();
		}
	}

	override function destroy()
	{
		// 清理timer
		if (saveReplayTimer != null)
		{
			saveReplayTimer.cancel();
			saveReplayTimer = null;
		}

		// 从 OpenFL stage 移除 overlay
		if (overlaySprite != null && FlxG.stage != null && FlxG.stage.contains(overlaySprite))
		{
			FlxG.stage.removeChild(overlaySprite);
			overlaySprite = null;
		}

		super.destroy();
	}

	// 创建 OpenFL TextField 的辅助函数
	private function createTextField(X:Float = 0, Y:Float = 0, Width:Float = 0, Color:FlxColor = FlxColor.WHITE, Size:Int = 12,
		Font:String = "assets/fonts/vcr.ttf"):TextField
	{
		var tf = new TextField();
		tf.x = X;
		tf.y = Y;
		tf.width = Width;
		tf.multiline = true;
		tf.wordWrap = true;
		tf.embedFonts = true;
		tf.selectable = false;
		tf.defaultTextFormat = new TextFormat(Font, Size, Color.to24Bit());
		tf.alpha = Color.alphaFloat;
		tf.autoSize = TextFieldAutoSize.LEFT;
		return tf;
	}
}
