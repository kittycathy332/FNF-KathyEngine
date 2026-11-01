package objects;

import flixel.group.FlxGroup;
import flixel.util.FlxStringUtil;
import states.FreeplayState;

/**
 * Music player used for Freeplay
 */
@:access(states.FreeplayState)
class MusicPlayer extends FlxGroup
{
	public var instance:FreeplayState;
	public var controls:Controls;

	public var playing(get, never):Bool;

	public var playingMusic:Bool = false;
	public var curTime:Float;

	/** 右侧播放器面板（歌曲名 / 播放控制按钮 / 时间进度）的总高度 */
	static inline var PANEL_HEIGHT:Float = 120;
	/** 倍速文本与上下箭头的字号 */
	static inline var RATE_FONT_SIZE:Int = 28;
	/** 上下箭头点击区域在垂直方向的额外留白（方便触控） */
	static inline var RATE_HIT_PAD:Float = 6;
	/** 按下时箭头向下位移的像素，做出"按下去"的立体感 */
	static inline var RATE_PRESS_OFFSET:Float = 2;
	/** 倍速箭头悬停 / 按下时的高亮色 */
	static inline var RATE_ACTIVE_COLOR:Int = 0xFFFFD800;
	/** 快进 / 快退按钮的时间步长（毫秒） */
	static inline var SEEK_STEP:Float = 5000;
	/** 播放控制按钮（快退 / 暂停继续 / 快进）的字号 */
	static inline var TRANSPORT_FONT_SIZE:Int = 20;
	/** 三颗控制按钮之间的间隔 */
	static inline var TRANSPORT_GAP:Float = 4;
	/** 曲名很短时，三颗按钮至少要占的宽度，避免被压成一条线 */
	static inline var TRANSPORT_MIN_BTN_W:Float = 30;
	/** 按下时按钮文字下沉的像素 */
	static inline var TRANSPORT_PRESS_OFFSET:Float = 2;
	/** 控制按钮悬停 / 按下时的高亮色 */
	static inline var TRANSPORT_ACTIVE_COLOR:Int = 0xFFFFD800;
	/** 曲名与按钮行之间保留的垂直间隔 */
	static inline var TRANSPORT_TOP_GAP:Float = 2;
	/** 时间文本字号：fusion-pixel 10px 字体按 3 倍渲染 */
	static inline var TIME_FONT_SIZE:Int = 30;
	/** 时间文本专用字体（只含数字与符号，用 latin 版即可） */
	static inline var TIME_FONT:String = 'fusion-pixel/10/fusion-pixel-10px-monospaced-latin.ttf';

	var songBG:FlxSprite;
	var songTxt:FlxText;
	var timeTxt:FlxText;
	var progressBarBG:FlxSprite;
	var progressBarFill:FlxSprite;
	/** 进度条当前填充比例（0~1），每帧按音频时间刷新 */
	var barFill:Float = 0;
	/** 进度条实际显示的填充比例：向 barFill 平滑逼近，避免音频时间分块刷新造成一格一格跳 */
	var barFillShown:Float = 0;
	var playbackBG:FlxSprite;
	var playbackSymbols:Array<FlxText> = [];
	var playbackTxt:FlxText;
	/** 上下箭头各自的聚焦/按下底色 */
	var rateHl:Array<FlxSprite> = [];
	/** 鼠标/触控当前按住的倍速方向（1 加速、-1 减速、0 未按） */
	var ratePressDir:Int = 0;
	var rateHoldTime:Float = 0;
	/** 进度条上方的三颗播放控制按钮：快退 5s / 暂停继续 / 快进 5s */
	var transportTxt:Array<FlxText> = [];
	var transportHl:Array<FlxSprite> = [];
	/** 当前按住的按钮索引（-1 表示没有） */
	var transportPress:Int = -1;
	/** 按钮行的布局矩形（与进度条同宽），用于命中测试与排版 */
	var transportLeft:Float = 0;
	var transportBtnW:Float = 0;
	var transportTop:Float = 0;
	var transportHeight:Float = 0;
	/** 面板实际高度：按内容自适应，避免中间出现一条空白带 */
	var panelH:Float = PANEL_HEIGHT;

	var wasPlaying:Bool;

	var holdPitchTime:Float = 0;
	var playbackRate(default, set):Float = 1;

	public function new(instance:FreeplayState)
	{
		super();

		this.instance = instance;
		this.controls = instance.controls;

		var xPos:Float = FlxG.width * 0.7;

		songBG = new FlxSprite(xPos - 6, 0).makeGraphic(1, Std.int(PANEL_HEIGHT), 0xFF000000);
		songBG.alpha = 0.6;
		// FlxSprite 默认以帧中心为缩放原点：改 scale.y 后整块背景会往下偏移，
		// 所以把垂直原点固定到顶边，缩放时始终贴住 y=0。
		songBG.origin.y = 0;
		add(songBG);

		playbackBG = new FlxSprite(xPos - 6, 0).makeGraphic(1, Std.int(PANEL_HEIGHT), 0xFF000000);
		playbackBG.alpha = 0.6;
		playbackBG.origin.y = 0;
		add(playbackBG);

		// 倍速箭头的聚焦/按下底色：纯黑小块，叠在半透明面板上明显变暗
		for (i in 0...2)
		{
			var hl:FlxSprite = new FlxSprite().makeGraphic(1, 1, 0xFF000000);
			hl.alpha = 0.85;
			hl.origin.set(0, 0);
			hl.visible = false;
			rateHl.push(hl);
			add(hl);
		}

		songTxt = new FlxText(FlxG.width * 0.7, 0, 0, "", 32);
		// 用按语言映射的像素字体：中文「正在播放」需要 CJK 字形，vcr.ttf 没有
		songTxt.setFormat(Paths.font(Language.get('uitab_font')), 32, FlxColor.WHITE, RIGHT);
		add(songTxt);

		// 自绘进度条（灰底 + 黑色填充）：用 1px 精灵横向缩放来推进，
		// 宽度是连续浮点数，不会像 FlxBar 那样按整数像素分档跳格。
		// 先创建它，让时间文本叠在进度条上方（同一 FlxGroup 按添加顺序绘制）。
		progressBarBG = makeBarSprite(FlxColor.GRAY);
		progressBarFill = makeBarSprite(FlxColor.BLACK);
		progressBarBG.scale.set(FlxG.width * 0.3, 8);
		add(progressBarBG);
		add(progressBarFill);

		// 进度条上方的三颗播放控制按钮：快退 5s / 暂停继续 / 快进 5s。
		// 先建底色再建文字，保证文字画在底色之上。
		var symbols:Array<String> = ['<<', '||', '>>'];
		for (i in 0...3)
		{
			var hl:FlxSprite = new FlxSprite().makeGraphic(1, 1, 0xFF000000);
			hl.alpha = 0.85;
			hl.origin.set(0, 0);
			hl.visible = false;
			transportHl.push(hl);
			add(hl);
		}

		for (i in 0...3)
		{
			var text:FlxText = new FlxText();
			text.setFormat(Paths.font('vcr.ttf'), TRANSPORT_FONT_SIZE, FlxColor.WHITE, CENTER);
			text.text = symbols[i];
			text.visible = false;
			transportTxt.push(text);
			add(text);
		}

		timeTxt = new FlxText(xPos, songTxt.y + 60, 0, "", TIME_FONT_SIZE);
		timeTxt.setFormat(Paths.font(TIME_FONT), TIME_FONT_SIZE, FlxColor.WHITE, RIGHT);
		add(timeTxt);

		for (i in 0...2)
		{
			var text:FlxText = new FlxText();
			text.setFormat(Paths.font('vcr.ttf'), RATE_FONT_SIZE, FlxColor.WHITE, CENTER);
			text.text = '^';
			if (i == 1)
				text.flipY = true;
			text.visible = false;
			playbackSymbols.push(text);
			add(text);
		}

		playbackTxt = new FlxText(FlxG.width * 0.6, 20, 0, "", RATE_FONT_SIZE);
		playbackTxt.setFormat(Paths.font("vcr.ttf"), RATE_FONT_SIZE, FlxColor.WHITE);
		add(playbackTxt);

		switchPlayMusic();
	}

	override function update(elapsed:Float)
	{
		super.update(elapsed);

		if (!playingMusic)
		{
			return;
		}

		var songName:String = instance.songs[FreeplayState.curSelected].songName;
		if (playing && !wasPlaying)
			songTxt.text = Language.getWithFallback('musicplayer_playing', 'PLAYING: {0}', [songName]);
		else
			songTxt.text = Language.getWithFallback('musicplayer_paused', 'PLAYING: {0} (PAUSED)', [songName]);

		// if(FlxG.keys.justPressed.K) trace('Time: ${FreeplayState.vocals.time}, Playing: ${FreeplayState.vocals.playing}');

		if (controls.UI_LEFT_P)
		{
			if (playing)
				wasPlaying = true;

			pauseOrResume();

			curTime = FlxG.sound.music.time - 1000;
			instance.holdTime = 0;

			if (curTime < 0)
				curTime = 0;

			FlxG.sound.music.time = curTime;
			setVocalsTime(curTime);
			instance.lastBeatHit = -1; // 重置beat检测
		}
		if (controls.UI_RIGHT_P)
		{
			if (playing)
				wasPlaying = true;

			pauseOrResume();

			curTime = FlxG.sound.music.time + 1000;
			instance.holdTime = 0;

			if (curTime > FlxG.sound.music.length)
				curTime = FlxG.sound.music.length;

			FlxG.sound.music.time = curTime;
			setVocalsTime(curTime);
			instance.lastBeatHit = -1; // 重置beat检测
		}

		if (controls.UI_LEFT || controls.UI_RIGHT)
		{
			instance.holdTime += elapsed;
			if (instance.holdTime > 0.5)
			{
				curTime += 40000 * elapsed * (controls.UI_LEFT ? -1 : 1);
			}

			var difference:Float = Math.abs(curTime - FlxG.sound.music.time);
			if (curTime + difference > FlxG.sound.music.length)
				curTime = FlxG.sound.music.length;
			else if (curTime - difference < 0)
				curTime = 0;

			FlxG.sound.music.time = curTime;
			setVocalsTime(curTime);
			instance.lastBeatHit = -1; // 重置beat检测
		}

		if (controls.UI_LEFT_R || controls.UI_RIGHT_R)
		{
			FlxG.sound.music.time = curTime;
			setVocalsTime(curTime);

			if (wasPlaying)
			{
				pauseOrResume(true);
				wasPlaying = false;
			}
		}
		if (controls.UI_UP_P)
		{
			holdPitchTime = 0;
			playbackRate += 0.05;
			setPlaybackRate();
		}
		else if (controls.UI_DOWN_P)
		{
			holdPitchTime = 0;
			playbackRate -= 0.05;
			setPlaybackRate();
		}
		if (controls.UI_DOWN || controls.UI_UP)
		{
			holdPitchTime += elapsed;
			if (holdPitchTime > 0.6)
			{
				playbackRate += 0.05 * (controls.UI_UP ? 1 : -1);
				setPlaybackRate();
			}
		}

		// ---- 鼠标 / 触控：点上下箭头调整倍速，按住可连续调整 ----
		var hoverDir:Int = rateButtonAt(FlxG.mouse.x, FlxG.mouse.y);
		if (FlxG.mouse.justPressed && hoverDir != 0)
		{
			ratePressDir = hoverDir;
			rateHoldTime = 0;
			stepPlaybackRate(hoverDir);
		}
		else if (ratePressDir != 0)
		{
			if (!FlxG.mouse.pressed || hoverDir != ratePressDir)
				ratePressDir = 0;
			else
			{
				// 按住 0.5 秒后每 0.1 秒再调一档
				rateHoldTime += elapsed;
				if (rateHoldTime > 0.5)
				{
					rateHoldTime = 0.4;
					stepPlaybackRate(ratePressDir);
				}
			}
		}

		// 悬停/按住时高亮箭头，并给对应箭头加一块黑色底，明确"已聚焦/已按下"
		var activeDir:Int = (ratePressDir != 0) ? ratePressDir : hoverDir;
		playbackSymbols[0].color = (hoverDir == 1 || ratePressDir == 1) ? RATE_ACTIVE_COLOR : FlxColor.WHITE;
		playbackSymbols[1].color = (hoverDir == -1 || ratePressDir == -1) ? RATE_ACTIVE_COLOR : FlxColor.WHITE;
		rateHl[0].visible = activeDir == 1;
		rateHl[1].visible = activeDir == -1;
		// 悬停用 0.85 的黑底，真正按下时加深到不透明，按下感更明显
		rateHl[0].alpha = (ratePressDir == 1) ? 1 : 0.85;
		rateHl[1].alpha = (ratePressDir == -1) ? 1 : 0.85;

		// ---- 鼠标 / 触控：进度条上方的三颗控制按钮，点击立即生效（不再"先暂停再调整"）----
		var hoverBtn:Int = transportButtonAt(FlxG.mouse.x, FlxG.mouse.y);
		if (FlxG.mouse.justPressed && hoverBtn >= 0)
		{
			transportPress = hoverBtn;
			pressTransportButton(hoverBtn);
		}
		else if (transportPress >= 0 && (!FlxG.mouse.pressed || hoverBtn != transportPress))
			transportPress = -1;

		for (i in 0...transportTxt.length)
		{
			var active:Bool = (transportPress == i) || (hoverBtn == i);
			transportTxt[i].color = active ? TRANSPORT_ACTIVE_COLOR : FlxColor.WHITE;
			transportHl[i].visible = active;
			transportHl[i].alpha = (transportPress == i) ? 1 : 0.85;
		}

		if (instance.touchPad.buttonC.justPressed || controls.RESET)
		{
			playbackRate = 1;
			setPlaybackRate();

			FlxG.sound.music.time = 0;
			setVocalsTime(0);
			instance.lastBeatHit = -1; // 重置beat检测
		}

		if (playing)
		{
			if (FreeplayState.vocals != null)
				FreeplayState.vocals.volume = (FreeplayState.vocals.length > FlxG.sound.music.time) ? 0.8 : 0;
			if (FreeplayState.opponentVocals != null)
				FreeplayState.opponentVocals.volume = (FreeplayState.opponentVocals.length > FlxG.sound.music.time) ? 0.8 : 0;

			if ((FreeplayState.vocals != null
				&& FreeplayState.vocals.length > FlxG.sound.music.time
				&& Math.abs(FlxG.sound.music.time - FreeplayState.vocals.time) >= 25)
				|| (FreeplayState.opponentVocals != null
					&& FreeplayState.opponentVocals.length > FlxG.sound.music.time
					&& Math.abs(FlxG.sound.music.time - FreeplayState.opponentVocals.time) >= 25))
			{
				pauseOrResume();
				setVocalsTime(FlxG.sound.music.time);
				pauseOrResume(true);
			}
		}

		// 先刷新文本再排版，避免文本宽度变化导致进度条/时间文本滞后一帧
		updateTimeTxt();
		updatePlaybackTxt();
		updateTransportTxt();
		positionSong();
		// 每帧按当前 music.time 刷新进度条，保证平滑推进（不止在打开播放器时更新一次）
		updateProgressBar();
	}

	function setVocalsTime(time:Float)
	{
		if (FreeplayState.vocals != null && FreeplayState.vocals.length > time)
			FreeplayState.vocals.time = time;
		if (FreeplayState.opponentVocals != null && FreeplayState.opponentVocals.length > time)
			FreeplayState.opponentVocals.time = time;
	}

	public function pauseOrResume(resume:Bool = false)
	{
		if (resume)
		{
			if (!FlxG.sound.music.playing)
				FlxG.sound.music.resume();

			if (FreeplayState.vocals != null && FreeplayState.vocals.length > FlxG.sound.music.time && !FreeplayState.vocals.playing)
				FreeplayState.vocals.resume();
			if (FreeplayState.opponentVocals != null
				&& FreeplayState.opponentVocals.length > FlxG.sound.music.time
				&& !FreeplayState.opponentVocals.playing)
				FreeplayState.opponentVocals.resume();
		}
		else
		{
			FlxG.sound.music.pause();

			if (FreeplayState.vocals != null)
				FreeplayState.vocals.pause();
			if (FreeplayState.opponentVocals != null)
				FreeplayState.opponentVocals.pause();
		}
	}

	public function switchPlayMusic()
	{
		FreeplayState.isFreeplayPlayingMusic = playingMusic;
		FlxG.autoPause = (!playingMusic && ClientPrefs.data.autoPause);
		active = visible = playingMusic;

		instance.scoreBG.visible = instance.diffText.visible = instance.scoreText.visible = !playingMusic; // Hide Freeplay texts and boxes if playingMusic is true
		songTxt.visible = timeTxt.visible = songBG.visible = playbackTxt.visible = playbackBG.visible = playingMusic; // Show Music Player texts and boxes if playingMusic is true
		progressBarBG.visible = progressBarFill.visible = playingMusic;

		for (i in playbackSymbols)
			i.visible = playingMusic;
		for (i in transportTxt)
			i.visible = playingMusic;

		holdPitchTime = 0;
		ratePressDir = 0;
		rateHoldTime = 0;
		transportPress = -1;
		for (hl in rateHl)
			hl.visible = false;
		for (hl in transportHl)
			hl.visible = false;
		instance.holdTime = 0;
		playbackRate = 1;
		updatePlaybackTxt();

		if (playingMusic)
		{
			final space:String = (instance.controls.mobileC) ? "X" : "SPACE";
			final escape:String = (instance.controls.mobileC) ? "B" : "ESCAPE";
			final reset:String = (instance.controls.mobileC) ? "C" : "R";

			instance.bottomText.text = Language.getWithFallback('musicplayer_tip', '{0}: Pause | {1}: Exit | {2}: Reset the Song', [space, escape, reset]);
			updateTimeTxt();
			updateTransportTxt();
			positionSong();
			updateProgressBar();
		}
		else
		{
			barFill = 0;
			barFillShown = 0;
			progressBarFill.scale.x = 0;

			instance.bottomText.text = instance.bottomString;
			instance.positionHighscore();
		}
	}

	function updatePlaybackTxt()
	{
		var text = "";
		if (playbackRate is Int)
			text = playbackRate + '.00';
		else
		{
			var playbackRate = Std.string(playbackRate);
			if (playbackRate.split('.')[1].length < 2) // Playback rates for like 1.1, 1.2 etc
				playbackRate += '0';

			text = playbackRate;
		}
		playbackTxt.text = text + 'x';
	}

	function positionSong()
	{
		var length:Int = instance.songs[FreeplayState.curSelected].songName.length;
		var shortName:Bool = length < 5; // Fix for song names like Ugh, Guns
		songTxt.x = FlxG.width - songTxt.width - 6;
		if (shortName)
			songTxt.x -= 10 * length - length;
		songBG.scale.x = FlxG.width - songTxt.x + 12;
		if (shortName)
			songBG.scale.x += 6 * length;
		// 最小宽度：曲名很短时也要保证时间文本和三颗控制按钮放得下
		var minBandW:Float = Math.max(timeTxt.width + 16, TRANSPORT_MIN_BTN_W * 3 + TRANSPORT_GAP * 2 + 2);
		if (songBG.scale.x < minBandW)
			songBG.scale.x = minBandW;
		songBG.x = FlxG.width - (songBG.scale.x / 2);
		// 右侧黑色背景条的实际绘制矩形：songBG 以自身中心为原点缩放，
		// 左边缘 = x + 半个像素 - 半个缩放宽度（不能简单写成 x - 宽度/2）
		var bandW:Float = songBG.scale.x;
		var bandL:Float = Math.max(0, songBG.x + 0.5 - bandW * 0.5);
		var bandR:Float = Math.min(FlxG.width, bandL + bandW);

		// 控制按钮与进度条都放在背景条内，左右各内缩 1px，保证绝不比背景条更宽
		var barX:Float = bandL + 1;
		var barW:Float = Math.max(0, bandR - bandL - 2);
		// 进度条高度直接等于时间文本高度
		var barH:Float = timeTxt.height;

		// 三颗控制按钮与进度条同宽，横向三等分
		transportLeft = barX;
		transportBtnW = Math.max(1, (barW - TRANSPORT_GAP * 2) / 3);
		transportHeight = transportTxt[0].height + 4;

		// 自上而下排：曲名 → 控制按钮 → 进度条，全部贴住面板顶部。
		transportTop = songTxt.y + songTxt.height + TRANSPORT_TOP_GAP;
		// 面板高度取二者较大：右侧内容（按钮下留 3px 再接进度条）与左侧三行倍速区
		panelH = Math.max(transportTop + transportHeight + 3 + barH, 3 * playbackTxt.height);
		songBG.scale.y = panelH / songBG.frameHeight;
		playbackBG.scale.y = panelH / playbackBG.frameHeight;

		// 进度条贴住面板底边，下方不留边距
		var barY:Float = panelH - barH;

		// 时间文本在进度条内水平居中，垂直方向与进度条等高
		timeTxt.y = barY;
		timeTxt.x = Math.round(barX + (barW - timeTxt.width) / 2);

		playbackBG.scale.x = playbackTxt.width + 30;
		playbackBG.x = songBG.x - (songBG.scale.x / 2);
		playbackBG.x -= playbackBG.scale.x;

		// 倍速面板的可视矩形（Sprite 默认以帧中心为缩放原点，左边缘 = x + 0.5 - scale.x / 2）
		var rateLeft:Float = playbackBG.x + 0.5 - playbackBG.scale.x * 0.5;
		var rateCenterX:Float = rateLeft + playbackBG.scale.x * 0.5;

		// 数字水平居中；三行（上箭头 / 数字 / 下箭头）整体在面板内垂直居中
		playbackTxt.x = Math.round(rateCenterX - playbackTxt.width * 0.5);
		var rateBlockH:Float = 3 * playbackTxt.height;
		playbackTxt.y = Math.round((panelH - rateBlockH) * 0.5 + playbackTxt.height);

		progressBarBG.scale.set(barW, barH);
		progressBarBG.x = barX;
		progressBarBG.y = barY;
		progressBarFill.x = barX;
		progressBarFill.y = barY;

		// 三颗控制按钮：文字在按钮格内居中，按下时下沉一点形成"按下去"的立体感
		for (i in 0...3)
		{
			var rectX:Float = transportLeft + i * (transportBtnW + TRANSPORT_GAP);
			var text:FlxText = transportTxt[i];
			text.x = Math.round(rectX + (transportBtnW - text.width) * 0.5);
			text.y = Math.round(transportTop + (transportHeight - text.height) * 0.5);
			if (transportPress == i)
				text.y += TRANSPORT_PRESS_OFFSET;

			var hl:FlxSprite = transportHl[i];
			hl.scale.set(transportBtnW, transportHeight);
			hl.x = rectX;
			hl.y = transportTop;
		}

		for (i in 0...2)
		{
			var text = playbackSymbols[i];
			text.x = Math.round(rateCenterX - text.width * 0.5);
			text.y = playbackTxt.y;

			if (i == 0)
				text.y -= playbackTxt.height;
			else
				text.y += playbackTxt.height;

			// 真正按住时箭头向下沉一点，配合更实的黑色底片形成"按下"效果
			if (ratePressDir == ((i == 0) ? 1 : -1))
				text.y += RATE_PRESS_OFFSET;

			// 箭头底色：宽度与倍速面板一致，高度正好是箭头那一行
			var hl:FlxSprite = rateHl[i];
			hl.scale.set(playbackBG.scale.x, text.height);
			hl.x = rateLeft;
			hl.y = text.y;
		}
	}

	function updateTimeTxt()
	{
		timeTxt.text = FlxStringUtil.formatTime(FlxG.sound.music.time / 1000, false) + ' / ' + FlxStringUtil.formatTime(FlxG.sound.music.length / 1000, false);
	}

	/** 中间那颗按钮随播放状态切换：播放中显示暂停符号，暂停时显示继续符号。 */
	function updateTransportTxt():Void
	{
		var middle:String = playing ? '||' : '>';
		if (transportTxt[1].text != middle)
			transportTxt[1].text = middle;
	}

	/** 立即跳到目标时间（不先暂停音频），让快进/快退点击即时生效。 */
	function seekBy(delta:Float):Void
	{
		var target:Float = FlxMath.bound(FlxG.sound.music.time + delta, 0, FlxG.sound.music.length);
		FlxG.sound.music.time = target;
		curTime = target;
		instance.holdTime = 0;
		setVocalsTime(target);
		instance.lastBeatHit = -1; // 重置beat检测

		updateTimeTxt();
		updateProgressBar();
	}

	/** 点击三颗控制按钮：0 快退、1 暂停/继续、2 快进。 */
	function pressTransportButton(index:Int):Void
	{
		switch (index)
		{
			case 0:
				seekBy(-SEEK_STEP);
			case 1:
				if (playing)
					pauseOrResume();
				else
					pauseOrResume(true);
			case 2:
				seekBy(SEEK_STEP);
		}
	}

	/** 鼠标/触控落在控制按钮行内时返回按钮索引（0~2），否则 -1。 */
	function transportButtonAt(mx:Float, my:Float):Int
	{
		if (my < transportTop || my > transportTop + transportHeight)
			return -1;

		for (i in 0...3)
		{
			var bx:Float = transportLeft + i * (transportBtnW + TRANSPORT_GAP);
			if (mx >= bx && mx <= bx + transportBtnW)
				return i;
		}
		return -1;
	}

	/** 1×1 纯色精灵，靠 scale 拉伸成任意宽度（origin 置于左上角，缩放时左边缘不会移动）。 */
	function makeBarSprite(color:Int):FlxSprite
	{
		var sprite:FlxSprite = new FlxSprite().makeGraphic(1, 1, color);
		sprite.antialiasing = false;
		sprite.origin.set(0, 0);
		return sprite;
	}

	/** 按当前音频时间刷新填充宽度：向目标比例平滑逼近，不会有整像素/百分比分档的顿挫。 */
	function updateProgressBar():Void
	{
		var len:Float = FlxG.sound.music.length;
		barFill = (len > 0) ? FlxMath.bound(FlxG.sound.music.time / len, 0, 1) : 0;

		// 音频时间是分段刷新的，直接赋值会让进度条一格一格跳；用与帧率无关的 lerp 追近目标。
		// 正常播放只用很短半衰期抹平顿挫；快进 / 快退 / 重置这类大跳变给更长的半衰期，
		// 让进度条平滑地"滑过去"，而不是瞬移到位。
		var diff:Float = barFill - barFillShown;
		var halfLife:Float = (Math.abs(diff) > 0.005) ? 0.15 : 0.05;
		barFillShown += diff * (1 - Math.pow(0.5, FlxG.elapsed / halfLife));

		progressBarFill.scale.set(progressBarBG.scale.x * barFillShown, progressBarBG.scale.y);
	}

	/** 按 +1 / -1 调整一档倍速（setter 会夹到 0.25~3 并保留两位小数）。 */
	function stepPlaybackRate(dir:Int):Void
	{
		playbackRate += 0.05 * dir;
		setPlaybackRate();
	}

	/** 鼠标/触控落在上下箭头的行内时返回 +1（加速）或 -1（减速），否则 0。 */
	function rateButtonAt(mx:Float, my:Float):Int
	{
		// 倍速面板以自身中心为原点缩放，用它的真实绘制矩形做命中
		var boxW:Float = playbackBG.scale.x;
		var boxL:Float = playbackBG.x + 0.5 - boxW * 0.5;
		if (mx < boxL || mx > boxL + boxW)
			return 0;

		for (i in 0...playbackSymbols.length)
		{
			var s:FlxText = playbackSymbols[i];
			if (my >= s.y - RATE_HIT_PAD && my <= s.y + s.height + RATE_HIT_PAD)
				return (i == 0) ? 1 : -1;
		}
		return 0;
	}

	function setPlaybackRate()
	{
		FlxG.sound.music.pitch = playbackRate;
		if (FreeplayState.vocals != null)
			FreeplayState.vocals.pitch = playbackRate;
		if (FreeplayState.opponentVocals != null)
			FreeplayState.opponentVocals.pitch = playbackRate;
	}

	function get_playing():Bool
	{
		return FlxG.sound.music.playing;
	}

	function set_playbackRate(value:Float):Float
	{
		var value = FlxMath.roundDecimal(value, 2);
		if (value > 3)
			value = 3;
		else if (value <= 0.25)
			value = 0.25;
		return playbackRate = value;
	}
}
