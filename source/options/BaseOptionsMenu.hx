package options;

import flixel.input.keyboard.FlxKey;
import flixel.input.gamepad.FlxGamepad;
import flixel.input.gamepad.FlxGamepadInputID;
import flixel.input.gamepad.FlxGamepadManager;

import objects.CheckboxThingie;
import objects.AttachedFlxText;
import options.Option;
import backend.InputFormatter;
import flixel.text.FlxText;

import flixel.addons.display.FlxBackdrop;
import flixel.FlxSubState;
import flixel.addons.display.FlxGridOverlay;
import backend.CoolUtil;
import flixel.input.touch.FlxTouch;
import mobile.backend.TouchUtil;

class BaseOptionsMenu extends MusicBeatSubstate
{
	private var curOption:Option = null;
	private var curSelected:Int = 0;
	private var optionsArray:Array<Option>;

	private var grpOptions:FlxTypedGroup<FlxText>;
	private var checkboxGroup:FlxTypedGroup<CheckboxThingie>;
	private var grpTexts:FlxTypedGroup<AttachedFlxText>;

	private var listCenterY:Float = 0;
	private var itemSpacing:Float = 56;
	private var listBaseX:Float = 0;

	// STRING 候选值面板（屏幕右侧列出可切换的选项）
	private var candidateBG:FlxSprite;
	private var candidateLines:FlxTypedGroup<FlxText>;
	private var candidatePanelVisible:Bool = false;
	private var candidateForSelected:Int = -1;
	private var _flashDummy:Float = 0; // 仅供重置闪红 tween 补间用的占位字段
	private var candidateLineH:Float = 32;
	private var candidatePadX:Float = 18;
	private var candidatePadY:Float = 12;
	private var candidateMargin:Float = 20;
	private var _lastBgW:Int = -1; // 候选面板背景上次尺寸（避免每次刷新都重建位图）
	private var _lastBgH:Int = -1;

	private var descBox:FlxSprite;
	private var descText:FlxText;
	private var _lastDesc:String = null;   // 上次描述文本，避免重复赋值导致重复光栅化
	private var _descBoxDirty:Bool = true;  // 描述文本/位置变化时才重算背景框尺寸

	private var _optionsBuildIndex:Int = 0;
	private var _optionsBuilt:Bool = false;
	private var _loadingText:FlxText = null;
	private var _grid:FlxBackdrop;

	public var title:String;
	public var rpcTitle:String;

	public var bg:FlxSprite;
	public var bg1:FlxSprite;
	public var bg2:FlxSprite;
	public function new()
	{
		controls.isInSubstate = true;

		super();

		if(title == null) title = 'Options';
		if(rpcTitle == null) rpcTitle = 'Options Menu';
		
		#if DISCORD_ALLOWED
		DiscordClient.changePresence(rpcTitle, null);
		#end

		bg2 = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, FlxColor.BLACK);
		bg2.screenCenter();
		bg2.antialiasing = ClientPrefs.data.antialiasing;
		bg2.alpha = 0;
		add(bg2);
		FlxTween.tween(bg2, {alpha: 0.6}, 0.5, {ease: FlxEase.quadOut});

		// 添加背景方块移动效果（加载完成后才显示）
		_grid = new FlxBackdrop(CoolUtil.getCachedGrid(80, 80, 160, 160, true, 0x33FFFFFF, 0x0));
		_grid.velocity.set(40, 40);
		_grid.visible = false;
		add(_grid);

		// avoids lagspikes while scrolling through menus!
		grpOptions = new FlxTypedGroup<FlxText>();
		add(grpOptions);

		grpTexts = new FlxTypedGroup<AttachedFlxText>();
		add(grpTexts);

		checkboxGroup = new FlxTypedGroup<CheckboxThingie>();
		add(checkboxGroup);

		listCenterY = FlxG.height * OptionsConfig.SUBMENU_SELECTED_Y_RATIO;
		itemSpacing = OptionsConfig.SUBMENU_ITEM_SPACING;
		listBaseX = OptionsConfig.SUBMENU_ITEM_X;

		descBox = new FlxSprite().makeGraphic(1, 1, FlxColor.BLACK);
		descBox.alpha = 0.6;
		add(descBox);

		// STRING 候选值面板（默认隐藏，选中 STRING 项时飞入右侧）
		candidateLines = new FlxTypedGroup<FlxText>();
		candidateBG = new FlxSprite();
		candidateBG.makeGraphic(1, 1, FlxColor.BLACK);
		candidateBG.alpha = 0;
		candidateBG.scrollFactor.set();
		add(candidateBG);
		add(candidateLines);

		// 标题用 FlxText 替代 Alphabet（Alphabet 每个字母都是独立 Sprite，创建极慢）
		var titleText:FlxText = new FlxText(75, 45, 0, title, 45);
		titleText.setFormat(Paths.font(Language.get('game_font')), 45, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		titleText.borderSize = 2.4;
		titleText.antialiasing = ClientPrefs.data.antialiasing;
		titleText.alpha = 0.4;
		add(titleText);

		descText = new FlxText(50, 600, 1180, "", 32);
		descText.setFormat(Paths.font(Language.get('game_font')), 32, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		descText.scrollFactor.set();
		descText.borderSize = 2.4;
		add(descText);

		// 加载提示文字
		_loadingText = new FlxText(20, 0, 0, 'Loading...\nPlease wait...', 24);
		_loadingText.setFormat(Paths.font("vcr.ttf"), 36, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		_loadingText.scrollFactor.set();
		_loadingText.borderSize = 2;
		_loadingText.antialiasing = ClientPrefs.data.antialiasing;
		_loadingText.y = 100;
		_loadingText.x = FlxG.width - _loadingText.width - 100;
		add(_loadingText);

		// 动画返回按钮
		if (FlxG.onMobile)
		{
			var backBtn:MobileButton = MobileButton.back(() -> {
				FlxG.sound.play(Paths.sound('cancelMenu'));
				close();
			}, null, true);
			add(backBtn);
		}

		// keybindManager 和 touchPad 延后到 onOptionsBuilt 才创建，避免拖慢构造函数
		// （构造函数只做最轻量的 UI 基础搭建）

		// 立即一次性构建所有选项，彻底消除分帧延迟
		_optionsBuildIndex = 0;
		_optionsBuilt = false;
		if (optionsArray == null) optionsArray = [];
		while (!_optionsBuilt)
			buildNextOptions();
	}

	private function buildNextOptions():Void
	{
		while (_optionsBuildIndex < optionsArray.length)
		{
			var i:Int = _optionsBuildIndex;
			var optionText:FlxText = new FlxText(0, 0, 0, optionsArray[i].name, OptionsConfig.SUBMENU_ITEM_SIZE);
			optionText.setFormat(Paths.font(Language.get('game_font')), OptionsConfig.SUBMENU_ITEM_SIZE, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			optionText.borderSize = 2;
			optionText.antialiasing = ClientPrefs.data.antialiasing;
			optionText.ID = i;
			optionText.scrollFactor.set();

			// 所有类型统一从 SUBMENU_ITEM_X 起始，保证左对齐
			optionText.x = OptionsConfig.SUBMENU_ITEM_X;
			optionText.y = listCenterY + i * itemSpacing;
			grpOptions.add(optionText);

			if(optionsArray[i].type == BOOL)
			{
				var on:Bool = (optionsArray[i].getValue() == true);
				var valueText:AttachedFlxText = new AttachedFlxText(optionText.x, optionText.y, 0, on ? Language.get('enabled') : Language.get('disabled'), OptionsConfig.SUBMENU_VALUE_SIZE);
				valueText.setFormat(Paths.font(Language.get('game_font')), OptionsConfig.SUBMENU_VALUE_SIZE, on ? OptionsConfig.OPTION_ON_COLOR : OptionsConfig.OPTION_OFF_COLOR, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
				valueText.borderSize = 2;
				valueText.antialiasing = ClientPrefs.data.antialiasing;
				valueText.sprTracker = optionText;
				valueText.offsetX = optionText.width + 60;
				valueText.copyAlpha = true;
				valueText.ID = i;
				valueText.scrollFactor.set();
				grpTexts.add(valueText);
				optionsArray[i].child = valueText;
			}
			else if (optionsArray[i].type != BUTTON)
			{
				var valueText:AttachedFlxText = new AttachedFlxText(optionText.x, optionText.y, 0, '' + optionsArray[i].getValue(), OptionsConfig.SUBMENU_VALUE_SIZE);
				valueText.setFormat(Paths.font(Language.get('game_font')), OptionsConfig.SUBMENU_VALUE_SIZE, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
				valueText.borderSize = 2;
				valueText.antialiasing = ClientPrefs.data.antialiasing;
				valueText.sprTracker = optionText;
				valueText.offsetX = optionText.width + 60;
				valueText.copyAlpha = true;
				valueText.ID = i;
				valueText.scrollFactor.set();
				grpTexts.add(valueText);
				optionsArray[i].child = valueText;
			}
			if (optionsArray[i].type != BUTTON) {
				updateTextFrom(optionsArray[i]);
			}

			_optionsBuildIndex++;
		}

		if (_optionsBuildIndex >= optionsArray.length)
		{
			_optionsBuilt = true;
			changeSelection();
			scrollVisual = curSelected; // 构建完成即对齐，避免首帧滑动
			reloadCheckboxes();
			onOptionsBuilt();
		}
	}

	public function onOptionsBuilt():Void
	{
		// 选项构建完成后再初始化 keybindManager 和 touchPad，避免拖慢构造函数
		keybindManager = new KeybindManager();
		addTouchPad('LEFT_FULL', 'A_B_C');
		addTouchPadCamera();

		if (_grid != null)
		{
			_grid.visible = true;
			_grid.alpha = 0;
			FlxTween.tween(_grid, {alpha: 1}, 0.5, {ease: FlxEase.quadOut});
		}

		if (_loadingText != null)
		{
			_loadingText.text = LanguageBasic.getPhrase('done', 'Done');
			FlxTween.tween(_loadingText, {alpha: 0, y: _loadingText.y + 20}, 0.5, {ease: FlxEase.quadIn, onComplete: function(tween:FlxTween) {
				if (_loadingText != null)
				{
					remove(_loadingText);
					_loadingText.destroy();
					_loadingText = null;
				}
			}});
		}
	}

	public function addOption(option:Option) {
		if(optionsArray == null || optionsArray.length < 1) optionsArray = [];
		optionsArray.push(option);
		return option;
	}

	var nextAccept:Int = 5;
	var holdTime:Float = 0;
	var holdValue:Float = 0;

	var keybindManager:KeybindManager;
	var lastMouseClickTime:Float = 0;
	var lastMouseClickIndex:Int = -1;

	// 平滑滚动位置（浮点索引）：整列作为整体一起缓动滚动，快速滚动/触屏拖拽时所有项目统一滑动，
	// 避免出现“只有选中项及相邻几项有动效、其余瞬移”的不一致观感
	private var scrollVisual:Float = 0;
	private var touchScrollActive:Bool = false; // 触屏拖拽进行中（updateItemLayout 据此跳过缓动，改为手指直接驱动 scrollVisual）

	// 滚动提示音最小间隔（秒）：快速滚动（Shift / 触屏拖拽）时限制音效频率，避免叠加过多声音实例导致卡顿
	private static inline var SCROLL_SND_INTERVAL:Float = 0.04;
	private var _lastScrollSndT:Float = 0;

#if mobile
	// 触屏拖拽滚动（仅移动端 / 设置子界面）：以连续浮点位置 1:1 跟随手指，松手吸附到最近项，避免瞬移
	private var touchScrollTouch:FlxTouch = null;
	private var touchScrollStartY:Float = 0;       // 拖拽起点手指 Y
	private var touchScrollStartVisual:Float = 0;  // 拖拽起点平滑滚动位置
#end
	override function update(elapsed:Float)
	{
		updateItemLayout(elapsed);
		super.update(elapsed);

		// 按住 Shift 时快速滚动（每次跳 4 项，与 LanguageSubState 一致）
		var mult:Int = (FlxG.keys.pressed.SHIFT) ? 4 : 1;

#if !mobile
		// 鼠标滚轮切换选项（按住 Shift 快速滚动 ×4）
		if (FlxG.mouse.wheel != 0) {
			changeSelection((FlxG.mouse.wheel > 0 ? -1 : 1) * mult);
		}

		// 检测鼠标左右键
		if (FlxG.mouse.justPressed) {
			var now = FlxG.game.ticks / 1000.0;
			if (lastMouseClickIndex == curSelected && (now - lastMouseClickTime) < OptionsConfig.DOUBLE_CLICK_THRESHOLD) {
				// 双击，什么都不做（交由右键或其它逻辑处理）
			} else {
				// 单击，BOOL类型切换：点击选项文本区域即切换（复选框已改为右侧 Enabled/Disabled 文本）
				if (curOption != null && curOption.type == BOOL && !curOption.disabled) {
					var opt = grpOptions.members[curSelected];
					if (opt != null &&
						FlxG.mouse.x >= opt.x && FlxG.mouse.x <= opt.x + opt.width &&
						FlxG.mouse.y >= opt.y && FlxG.mouse.y <= opt.y + opt.height) {
						FlxG.sound.play(Paths.sound('scrollMenu'));
						curOption.setValue((curOption.getValue() == true) ? false : true);
						curOption.change();
						reloadCheckboxes();
					}
				}
			}
			lastMouseClickTime = now;
			lastMouseClickIndex = curSelected;
		}
		if (FlxG.mouse.justPressedRight) {
			// 鼠标右键退出
			close();
			FlxG.sound.play(Paths.sound('cancelMenu'));
		}
#end

#if mobile
		// 触屏拖拽滚动列表（按住方向键触摸板时不触发，避免冲突）
		handleTouchScroll();
#end

		// Handle keybinding
		if (keybindManager != null && keybindManager.isBinding) {
			if (keybindManager.update(elapsed)) {
				reloadCheckboxes();
			}
			return;
		}

		if (controls.UI_UP_P)
		{
			changeSelection(-1 * mult);
		}
		if (controls.UI_DOWN_P)
		{
			changeSelection(1 * mult);
		}

		if (controls.BACK) {
			close();
			FlxG.sound.play(Paths.sound('cancelMenu'));
		}

		if(nextAccept <= 0)
		{
			if(curOption.disabled)
			{
				// 禁用的选项不允许修改
			}
			else
			{
				switch(curOption.type)
				{
					case BOOL:
						if(controls.ACCEPT)
						{
							FlxG.sound.play(Paths.sound('scrollMenu'));
							curOption.setValue((curOption.getValue() == true) ? false : true);
							curOption.change();
							reloadCheckboxes();
						}

					case KEYBIND:
						if(controls.ACCEPT)
						{
							keybindManager.startBinding(curOption, function() {
								reloadCheckboxes();
							});
							if (keybindManager.getOverlay() != null) add(keybindManager.getOverlay());
							if (keybindManager.getTitle() != null) add(keybindManager.getTitle());
							if (keybindManager.getInstructions() != null) add(keybindManager.getInstructions());
						}

					case BUTTON:
						if(controls.ACCEPT)
						{
							FlxG.sound.play(Paths.sound('scrollMenu'));
							curOption.change();
						}

					default:
						if(controls.UI_LEFT || controls.UI_RIGHT)
						{
							var pressed = (controls.UI_LEFT_P || controls.UI_RIGHT_P);
							if(holdTime > OptionsConfig.INPUT_COOLDOWN || pressed)
							{
								if(pressed)
								{
									var add:Dynamic = null;
									if(curOption.type != STRING)
										add = controls.UI_LEFT ? -curOption.changeValue : curOption.changeValue;

									switch(curOption.type)
									{
										case INT, FLOAT, PERCENT:
											holdValue = curOption.getValue() + add;
											if(holdValue < curOption.minValue) holdValue = curOption.minValue;
											else if (holdValue > curOption.maxValue) holdValue = curOption.maxValue;

											if(curOption.type == INT)
											{
												holdValue = Math.round(holdValue);
												curOption.setValue(holdValue);
											}
											else
											{
												holdValue = FlxMath.roundDecimal(holdValue, curOption.decimals);
												curOption.setValue(holdValue);
											}

										case STRING:
											var num:Int = curOption.curOption;
											if(controls.UI_LEFT_P) --num;
											else num++;

											if(num < 0)
												num = curOption.options.length - 1;
											else if(num >= curOption.options.length)
												num = 0;

											curOption.curOption = num;
											curOption.setValue(curOption.options[num]);

											default:
											}
											updateTextFrom(curOption);
											refreshCandidatePanel();
											curOption.change();
											FlxG.sound.play(Paths.sound('scrollMenu'));
								}
								else if(curOption.type != STRING)
								{
									holdValue += curOption.scrollSpeed * elapsed * (controls.UI_LEFT ? -1 : 1);
									if(holdValue < curOption.minValue) holdValue = curOption.minValue;
									else if (holdValue > curOption.maxValue) holdValue = curOption.maxValue;

									switch(curOption.type)
									{
										case INT:
											curOption.setValue(Math.round(holdValue));

										case PERCENT:
											curOption.setValue(FlxMath.roundDecimal(holdValue, curOption.decimals));

										default:
									}
									updateTextFrom(curOption);
									curOption.change();
								}
							}

							if(curOption.type != STRING)
								holdTime += elapsed;
						}
						else if(controls.UI_LEFT_R || controls.UI_RIGHT_R)
						{
							if(holdTime > OptionsConfig.INPUT_COOLDOWN) FlxG.sound.play(Paths.sound('scrollMenu'));
							holdTime = 0;
						}
				}
			}

			if(controls.RESET || (touchPad != null && touchPad.buttonC != null && touchPad.buttonC.justPressed))
			{
				var leOption:Option = optionsArray[curSelected];
				if(!leOption.disabled)
				{
					if(leOption.type != KEYBIND)
					{
						leOption.setValue(leOption.defaultValue);
						if(leOption.type != BOOL)
						{
							if(leOption.type == STRING) leOption.curOption = leOption.options.indexOf(leOption.getValue());
							updateTextFrom(leOption);
						}
					}
					else
					{
						leOption.setValue(!Controls.instance.controllerMode ? leOption.defaultKeys.keyboard : leOption.defaultKeys.gamepad);
						if (keybindManager != null) {
							keybindManager.updateBindDisplay(null, leOption, grpTexts);
						}
					}
					leOption.change();
					FlxG.sound.play(Paths.sound('cancelMenu'));
					reloadCheckboxes();
					refreshCandidatePanel(true);
					}
			}
		}

		if(nextAccept > 0) {
			nextAccept -= 1;
		}
	}

	function updateTextFrom(option:Option) {
		if(option.type == KEYBIND)
		{
			if (keybindManager != null) {
				keybindManager.updateBindDisplay(null, option, grpTexts);
			}
			return;
		}

		if(option.type == BOOL) {
			var on:Bool = (option.getValue() == true);
			if (option.child != null) {
				option.child.text = on ? Language.get('enabled') : Language.get('disabled');
				option.child.color = on ? OptionsConfig.OPTION_ON_COLOR : OptionsConfig.OPTION_OFF_COLOR;
			}
			return;
		}

		if(option.type == STRING) {
			// 类似 noteskin 选择器：用箭头包住当前可选值，并着强调色，提示可左右切换
			var val:Dynamic = option.getValue();
			// 若该选项配置了可选项本地化映射，则用显示文案替代原始存储值（存储值不变）
			var show:String = Std.string(val);
			if (option.valueLocalizations != null && option.valueLocalizations.exists(Std.string(val)))
				show = option.valueLocalizations.get(Std.string(val));
			option.text = '${OptionsConfig.SUBMENU_STRING_ARROW.charAt(0)}$show${OptionsConfig.SUBMENU_STRING_ARROW.charAt(2)}';
			if (option.child != null) option.child.color = OptionsConfig.SUBMENU_STRING_COLOR;
			return;
		}

		var text:String = option.displayFormat;
		var val:Dynamic = option.getValue();
		if(option.type == PERCENT) val *= 100;
		var def:Dynamic = option.defaultValue;
		option.text = text.replace('%v', val).replace('%d', def);
	}
	
#if mobile
	// 手指是否落在"任一屏幕控件"上：设置导航 touchPad 或玩法触屏控件 mobileControls。
	// 若是，则不把该触摸识别为列表拖拽，避免按虚拟键时背景选项跟着拖动、互相抢输入。
	private function isTouchOnUIControls(t:FlxTouch):Bool
	{
		if (touchPad != null && touchPadCam != null && t.overlaps(touchPad, touchPadCam))
			return true;

		if (mobileControls != null && mobileControls.instance != null)
		{
			var cam = (mobileControlsCam != null) ? mobileControlsCam : touchPadCam;
			if (cam != null && t.overlaps(mobileControls.instance, cam))
				return true;
		}
		return false;
	}

	private function handleTouchScroll():Void {
		if (!touchScrollActive) {
			// 仅在"列表区域"的非控件触摸按下时开始滚动，避免与虚拟按键冲突
			for (t in FlxG.touches.list) {
				if (t.justPressed && !isTouchOnUIControls(t)) {
					touchScrollActive = true;
					touchScrollTouch = t;
					touchScrollStartY = t.y;
					touchScrollStartVisual = scrollVisual; // 从当前平滑位置起算，避免突跳
					prevTouchSel = curSelected;
					break;
				}
			}
			if (!touchScrollActive) return;
		}

		// 找回当前活动的触摸（FlxTouch 对象在同一根手指按下期间保持稳定引用）
		var active:FlxTouch = null;
		for (t in FlxG.touches.list) {
			if (t == touchScrollTouch) {
				active = t;
				break;
			}
		}

		if (active == null || active.justReleased || active.released) {
			// 松手：选中项吸附到最近整数项；scrollVisual 不立即跳变，
			// 交由 updateItemLayout 的 lerp 平滑收尾（避免松手瞬间整列突然移动）
			touchScrollActive = false;
			touchScrollTouch = null;
			curSelected = Math.round(scrollVisual);
			curOption = optionsArray[curSelected];
			prevTouchSel = curSelected;
			updateDescText();
			refreshCandidatePanel();
			return;
		}

		// 连续模型：手指向上拖（y 减小）→ 列表内容上移 → 选中项增大。
		// 以浮点 scrollVisual 1:1 跟随手指，整列统一滑动，绝不瞬移；
		// 顶/底夹住不回环（仅移动端，键盘仍保留回环）。
		var dragPx:Float = touchScrollStartY - active.y; // 向上为正
		var targetVisual:Float = touchScrollStartVisual + dragPx / itemSpacing;
		var lastIdx:Int = optionsArray.length - 1;
		if (targetVisual < 0) targetVisual = 0;
		else if (targetVisual > lastIdx) targetVisual = lastIdx;
		scrollVisual = targetVisual;

		var newSel:Int = Math.round(scrollVisual);
		if (newSel != prevTouchSel) {
			curSelected = newSel;
			curOption = optionsArray[curSelected];
			prevTouchSel = newSel;
			// 限频滚动音效
			var tnow:Float = FlxG.game.ticks / 1000.0;
			if (tnow - _lastScrollSndT >= SCROLL_SND_INTERVAL) {
				FlxG.sound.play(Paths.sound('scrollMenu'));
				_lastScrollSndT = tnow;
			}
			// 描述/候选面板在松手时才刷新（见上面 release 分支）
		}
	}

	private var prevTouchSel:Int = 0; // 触屏拖拽中上一帧的选中项（用于检测跨项与限频音效）
#end

	function changeSelection(change:Int = 0, skipRefresh:Bool = false, skipDesc:Bool = false)
	{
		curSelected = FlxMath.wrap(curSelected + change, 0, optionsArray.length - 1);
		curOption = optionsArray[curSelected]; //shorter lol

		// skipDesc=true 时由调用方统一刷新描述（触摸拖拽期间冻结、松手才同步，避免每步重算）
		if (!skipDesc) updateDescText();
		// skipRefresh=true 时由调用方统一刷新（快速滚动时每帧只重建一次候选面板，避免卡顿）
		if (!skipRefresh) refreshCandidatePanel();
		// 快速滚动时限制提示音频率，避免一帧内多次调用叠加大量音效实例造成卡顿
		var t:Float = FlxG.game.ticks / 1000.0;
		if (t - _lastScrollSndT >= SCROLL_SND_INTERVAL) {
			FlxG.sound.play(Paths.sound('scrollMenu'));
			_lastScrollSndT = t;
		}
	}

	// 仅当描述文本真正变化时，才更新 descText 并重算背景框（避免快速滚动中重复光栅化）
	private function updateDescText():Void
	{
		var sel:Option = optionsArray[curSelected];
		var desc:String = sel.description;
		// 禁用项在描述后追加原因说明，指明为何不可用
		if (sel.disabled)
		{
			if (sel.disabledReason != null)
				desc += '\n[' + sel.disabledReason + ']';
			else if (sel.requirement != null && sel.requirement.length > 0)
				desc += '\n[' + OptionsLanguage.get('requirement_prefix', '需要: ') + sel.requirement + ']';
		}

		if (desc != _lastDesc) {
			_lastDesc = desc;
			descText.text = desc;
			descText.screenCenter(Y);
			descText.y += 270;
			_descBoxDirty = true;
		}
	}

	// 若当前选中项是有候选值的 STRING 选项，在右侧列出所有可选项并高亮当前值；否则隐藏面板
	// flashDefault=true 时，理论默认项会闪红一下（用于重置反馈）
	private function refreshCandidatePanel(flashDefault:Bool = false):Void
	{
		var opt:Option = optionsArray[curSelected];
		var list:Array<String> = (opt != null && opt.type == STRING && opt.options != null) ? opt.options : null;
		var shouldShow:Bool = (list != null && list.length > 0);
		var defaultVal:String = (opt != null) ? Std.string(opt.defaultValue) : null;

		if (!shouldShow)
		{
			if (candidatePanelVisible)
			{
				candidatePanelVisible = false;
				candidateForSelected = -1;
				hideCandidatePanel();
			}
			return;
		}

		var wasVisible:Bool = candidatePanelVisible;
		candidatePanelVisible = true;

		// 取消可能仍在进行的重置闪红补间（作用于 this），避免与后续重新着色冲突
		FlxTween.cancelTweensOf(this);

		var current:String = Std.string(opt.getValue());

		// 复用候选行对象池：仅在行数不足时新建，切换选项时仅更新文本/颜色/位置，避免频繁分配与销毁对象
		var needed:Int = list.length;
		for (i in candidateLines.members.length...needed)
		{
			var t:FlxText = new FlxText(0, 0, 0, '', OptionsConfig.SUBMENU_VALUE_SIZE);
			t.setFormat(Paths.font(Language.get('game_font')), OptionsConfig.SUBMENU_VALUE_SIZE, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			t.borderSize = 2;
			t.antialiasing = ClientPrefs.data.antialiasing;
			t.scrollFactor.set();
			candidateLines.add(t);
		}
		// 多余的行隐藏，等待下次需要时复用
		for (i in needed...candidateLines.members.length)
			candidateLines.members[i].visible = false;

		var lineW:Float = 0.0;
		for (i => val in list)
		{
			var line:FlxText = candidateLines.members[i];
			line.visible = true;
			FlxTween.cancelTweensOf(line); // 清掉可能残留的淡入/闪红补间
			var display:String = LanguageBasic.getPhrase('setting_${opt.translationKey}-$val', val);
			if (line.text != display) line.text = display;
			lineW = Math.max(lineW, line.width);
		}

		var bgW:Float = lineW + candidatePadX * 2;
		var bgH:Float = list.length * candidateLineH + candidatePadY * 2;
		var targetX:Float = FlxG.width - candidateMargin - bgW;
		var targetY:Float = (FlxG.height - bgH) / 2;

		// 仅在尺寸变化时重建背景图，避免每次刷新都分配新位图导致卡顿
		if (Math.ceil(bgW) != _lastBgW || Math.ceil(bgH) != _lastBgH) {
			candidateBG.makeGraphic(Math.ceil(bgW), Math.ceil(bgH), FlxColor.BLACK);
			_lastBgW = Math.ceil(bgW);
			_lastBgH = Math.ceil(bgH);
		}

		var defaultIndex:Int = -1;
		for (i => val in list)
		{
			var line:FlxText = candidateLines.members[i];
			line.setPosition(targetX + candidatePadX, targetY + candidatePadY + i * candidateLineH + (candidateLineH - line.height) / 2);
			if (val == defaultVal) defaultIndex = i;
			line.color = (val == current) ? OptionsConfig.SUBMENU_STRING_COLOR : FlxColor.WHITE;
		}

		if (!wasVisible)
		{
			var finalX:Float = targetX + candidatePadX;
			// 背景从屏幕右侧飞入 + 淡入
			FlxTween.cancelTweensOf(candidateBG);
			candidateBG.setPosition(FlxG.width, targetY);
			candidateBG.alpha = 0;
			FlxTween.tween(candidateBG, {x: targetX, alpha: 0.55}, 0.3, {ease: FlxEase.quartOut});

			// 候选文本从右侧滑入 + 淡入（逐行 stagger）
			for (i in 0...needed)
			{
				var line:FlxText = candidateLines.members[i];
				line.x = finalX + 30;
				line.alpha = 0;
				FlxTween.cancelTweensOf(line);
				FlxTween.tween(line, {x: finalX, alpha: 1}, 0.28, {startDelay: 0.06 + i * 0.03, ease: FlxEase.quartOut});
			}
		}
		else if (candidateForSelected != curSelected)
		{
			// 已显示但切换到不同 STRING 选项：保持面板位置，直接就位（不再逐行淡入，
			// 避免快速滚动时每帧都创建大量补间对象造成卡顿）
			candidateBG.setPosition(targetX, targetY);
			candidateBG.alpha = 0.55;
			for (i in 0...needed)
			{
				var line:FlxText = candidateLines.members[i];
				FlxTween.cancelTweensOf(line);
				line.alpha = 1;
			}
		}
		else
		{
			candidateBG.setPosition(targetX, targetY);
			candidateBG.alpha = 0.55;
			for (i in 0...needed) candidateLines.members[i].alpha = 1;
		}

		// 重置反馈：理论默认项先变红，再平滑过渡回正常高亮色（红→蓝/白）
		if (flashDefault && defaultIndex >= 0)
		{
			var defLine:FlxText = candidateLines.members[defaultIndex];
			if (defLine != null)
			{
				FlxTween.cancelTweensOf(defLine);
				var targetColor:Int = (defaultVal == current) ? OptionsConfig.SUBMENU_STRING_COLOR : FlxColor.WHITE;
				_flashDummy = 0;
				defLine.color = FlxColor.RED;
				FlxTween.tween(this, {_flashDummy: 1}, 0.4, {
					onUpdate: function(twn:FlxTween) {
						if (defLine != null && defLine.alive)
							defLine.color = FlxColor.interpolate(targetColor, FlxColor.RED, 1 - _flashDummy);
					},
					onComplete: function(twn:FlxTween) {
						if (defLine != null && defLine.alive)
							defLine.color = targetColor;
					}
				});
			}
		}

		candidateForSelected = curSelected;
	}

	// 面板飞出右侧 + 淡出（背景与候选文本一起滑出）
	private function hideCandidatePanel():Void
	{
		// 取消可能仍在进行中的重置闪红补间，避免在隐藏时继续改色
		FlxTween.cancelTweensOf(this);
		// 背景飞出右侧 + 淡出
		FlxTween.cancelTweensOf(candidateBG);
		FlxTween.tween(candidateBG, {x: FlxG.width, alpha: 0}, 0.25, {ease: FlxEase.quartIn});
		// 候选文本滑出右侧 + 淡出
		for (line in candidateLines.members)
		{
			FlxTween.cancelTweensOf(line);
			FlxTween.tween(line, {x: line.x + 30, alpha: 0}, 0.2, {ease: FlxEase.quadIn});
		}
	}

	// 每帧根据 curSelected 平滑计算列表项的位置/缩放/透明度，实现滚动效果。
	// 数值文本与复选框通过各自的 sprTracker 跟随 optionText，无需在此处理。
	private function updateItemLayout(elapsed:Float):Void
	{
		var lerp:Float = Math.exp(-elapsed * OptionsConfig.SUBMENU_LAYOUT_LERP);
		// 触屏拖拽时 scrollVisual 已由手指直接驱动（见 handleTouchScroll），此处不再缓动，避免与手指抢位置；
		// 非拖拽时（键盘/滚轮/松手后）才平滑缓动到 curSelected
		if (!touchScrollActive) scrollVisual = FlxMath.lerp(curSelected, scrollVisual, lerp);
		for (num => item in grpOptions.members)
		{
			var offset:Int = num - curSelected;
			// Y 位置由平滑滚动位置驱动，全列一致缓动/跟手，无需逐行吸附
			item.y = listCenterY + (num - scrollVisual) * itemSpacing;

			// Freeplay 式连续水平投影：选中行固定在最右，离选中行越远的项向左缩进越多，形成扇形纵深。
			// 用 |dist| 做幂次曲线(SUBMENU_X_DRIFT_CURVE)让边缘呈弧形而非直线三角，滚动轨迹更"圆"。
			// 由 scrollVisual(平滑浮点距离) 驱动，滚动时水平偏移连续滑动。
			var dist:Float = num - scrollVisual;
			var shaped:Float = Math.pow(Math.abs(dist), OptionsConfig.SUBMENU_X_DRIFT_CURVE);
			var targetX:Float = listBaseX + OptionsConfig.SUBMENU_SELECTED_OFFSET_X
				+ OptionsConfig.SUBMENU_SELECTED_EXTRA_OFFSET_X
				- shaped * OptionsConfig.SUBMENU_X_DRIFT_PER_ITEM;
			item.x = targetX;

			var targetAlpha:Float = (offset == 0) ? OptionsConfig.SUBMENU_SELECTED_ALPHA : OptionsConfig.SUBMENU_UNSELECTED_ALPHA;
			if (optionsArray[num].disabled) targetAlpha *= OptionsConfig.SUBMENU_DISABLED_ALPHA_MULT;
			item.alpha = FlxMath.lerp(targetAlpha, item.alpha, lerp);

			var targetScale:Float = (offset == 0) ? OptionsConfig.SUBMENU_SELECTED_SCALE : OptionsConfig.SUBMENU_NORMAL_SCALE;
			item.scale.x = FlxMath.lerp(targetScale, item.scale.x, lerp);
			item.scale.y = item.scale.x;
		}

		// 右侧数值/Enabled 文本跟随选中项一起缩放，保持视觉一致
		for (text in grpTexts) {
			var isSelected:Bool = (text.ID == curSelected);
			var targetScale:Float = isSelected ? OptionsConfig.SUBMENU_SELECTED_SCALE : OptionsConfig.SUBMENU_NORMAL_SCALE;
			text.scale.x = FlxMath.lerp(targetScale, text.scale.x, lerp);
			text.scale.y = text.scale.x;
		}

		// 描述背景框仅在描述文本/位置变化时才重算尺寸，避免每帧空算
		if (_descBoxDirty) {
			descBox.setPosition(descText.x - 10, descText.y - 10);
			descBox.setGraphicSize(Std.int(descText.width + 20), Std.int(descText.height + 25));
			descBox.updateHitbox();
			_descBoxDirty = false;
		}
	}

	function reloadCheckboxes() {
		for (checkbox in checkboxGroup)
			checkbox.daValue = Std.string(optionsArray[checkbox.ID].getValue()) == 'true'; //Do not take off the Std.string() from this, it will break a thing in Mod Settings Menu

		// BOOL 选项已改为右侧 "Enabled/Disabled" 文本，随状态刷新颜色
		for (text in grpTexts) {
			var opt = optionsArray[text.ID];
			if (opt != null && opt.type == BOOL) {
				var on:Bool = (opt.getValue() == true);
				text.text = on ? Language.get('enabled') : Language.get('disabled');
				text.color = on ? OptionsConfig.OPTION_ON_COLOR : OptionsConfig.OPTION_OFF_COLOR;
			}
		}
	}
	
	// 统一计算选项列表标签：altText 优先，其次禁用项追加前提条件，否则用原始名称
	private function getOptionLabel(optData:Option):String
	{
		if (optData.altText != null)
			return optData.altText;
		if (optData.disabled && optData.requirement != null && optData.requirement.length > 0)
			return optData.name + ' (' + OptionsLanguage.get('requirement_prefix', '需要: ') + optData.requirement + ')';
		return optData.name;
	}

	function refreshAllTexts() {
		// 刷新标题
		//titleText.text = title;

		// 刷新选项文本
		for (i in 0...grpOptions.length) {
			var opt = grpOptions.members[i];
			var optData = optionsArray[i];
			opt.text = getOptionLabel(optData);
			// 标签变长后，把右侧数值/状态文本推开，避免重叠
			if (optData.child != null)
				cast(optData.child, AttachedFlxText).offsetX = opt.width + 60;
		}

		// 刷新描述（走统一逻辑，保持缓存与背景框一致）
		updateDescText();
	}

	override function destroy()
	{
		if (keybindManager != null)
		{
			keybindManager.destroy();
			keybindManager = null;
		}
		if (_loadingText != null)
			FlxTween.cancelTweensOf(_loadingText);
		super.destroy();
	}

	/**
	 * 统一在打开子状态前移除自身 touchPad，避免与子状态的 touchPad 重叠渲染。
	 * （MusicBeatSubstate 有独立的 touchPad 成员，Controls.requestedInstance 切换到子状态后，
	 *  本 touchPad 虽然不再响应输入，但仍残留在父 state 的成员列表里被继续 draw）
	 */
	override function openSubState(SubState:FlxSubState):Void
	{
		persistentDraw = false;
		removeTouchPad();
		super.openSubState(SubState);
	}

	override function closeSubState()
	{
		super.closeSubState(); // 销毁内层 subState（MusicBeatSubstate.destroy 会把 instance 置 null）
		
		// 关键：必须在重建 touchPad 之后、让 Controls 仍走 MusicBeatSubstate 分支。
		// 因为顶层 OptionsState 的 touchPad 在 openSelectedSubState 时已被 removeTouchPad 清掉，
		// 之后 OptionsState 就不知道我们打开了几层 BaseOptionsMenu 子类，不会自动重建 touchPad。
		// 所以 Controls.requestedInstance 必须保持在 MusicBeatSubstate 链上，指向当前 BaseOptionsMenu 子类自己。
		MusicBeatSubstate.instance = cast(this, MusicBeatSubstate);
		controls.isInSubstate = true;
		
		removeTouchPad(); // 双保险：如果内层销毁时没清干净
		addTouchPad('LEFT_FULL', 'A_B_C');
		addTouchPadCamera(); // removeTouchPad 已销毁 touchPadCam，这里必须重建，否则 isTouchOnUIControls 失效、虚拟键会被当成列表拖拽吞掉
		persistentDraw = true;
#if mobile
		// 重置触屏拖拽滚动状态，避免从子状态返回后残留的手指/选中污染虚拟键输入
		touchScrollActive = false;
		touchScrollTouch = null;
#end
	}
}