package backend.ui;

import backend.FreeplayCategory;
import backend.SongMetadata;
import backend.WeekData;
import haxe.ui.Toolkit;
import haxe.ui.components.Button;
import haxe.ui.components.CheckBox;
import haxe.ui.components.Label;
import haxe.ui.components.TextField;
import haxe.ui.components.VerticalScroll;
import haxe.ui.constants.ScrollMode;
import haxe.ui.containers.Absolute;
import haxe.ui.containers.Box;
import haxe.ui.containers.HBox;
import haxe.ui.containers.ScrollView;
import haxe.ui.containers.VBox;
import haxe.ui.core.Component;
import haxe.ui.core.Screen;
import haxe.ui.events.MouseEvent;
import haxe.ui.events.UIEvent;
import haxe.ui.tooltips.ToolTipManager;
#if mobile
import lime.math.Rectangle;
#end

/**
 * Freeplay 分区编辑器（haxe.ui 绘制，由 FreeplayState 直接持有）。
 *
 * 布局：左侧分区列表（新建 / 删除 / 选中），右侧名称、颜色、可搜索的曲目多选列表。
 * 勾选 = 加入分区；取消勾选 = 移出分区（若该曲目是靠 folders / weeks 规则命中的，
 * 会自动写入 exclude 条目，避免被规则再次拉回来）。
 *
 * 保存时只把真正改动过（或新建 / 删除）的分区交给 FreeplayCategory.saveAll 写盘。
 */
class FreeplayCategoryEditor
{
	private static inline var MARGIN_X:Float = 40;
	private static inline var MARGIN_Y:Float = 30;
	private static inline var LEFT_W:Float = 300;
	private static inline var GAP:Float = 12;
	private static inline var PAD:Float = 12;
	private static inline var ROW_H:Float = 24;
	/** 虚拟列表最多创建多少个行控件（按可见高度决定，另有上限防极端分辨率） */
	private static inline var ROW_POOL_MAX:Int = 60;
	/** 曲目列表滚动条滑块的最小高度（曲目很多时滑块按比例会变得极短，给个下限方便拖动） */
	private static inline var MIN_THUMB_H:Float = 44;
	/**
	 * 编辑器统一字号。
	 *
	 * unifont 是按 16px 像素网格设计的字体，13/14/15/18 这类非 16 倍数会让 FreeType
	 * 把字形重新缩放一遍，小字就会发糊；统一成 16px（与游戏里其它 HaxeUI 文本一致）
	 * 才能落在像素网格上保持清晰。
	 */
	private static inline var FONT_SIZE:Int = 16;

	/** 左侧分区列表：不同来源（全局 / 各模组）之间的空行高度与组名标题高度 */
	private static inline var GROUP_GAP_H:Float = 12;
	private static inline var GROUP_TITLE_H:Float = 24;
	/** 分区行高度与行间距（Absolute 手动排版，拖动排序时按这两个值算落点） */
	private static inline var CAT_ROW_H:Float = 30;
	private static inline var CAT_ROW_GAP:Float = 3;
	/** 拖动排序手柄的宽度 */
	private static inline var HANDLE_W:Float = 26;
	/** 长按多久（秒）后进入拖动排序 */
	private static inline var LONG_PRESS_TIME:Float = 0.4;
	/** 长按前指针移动超过这个距离（像素）就视为想滚动列表，放弃这次长按 */
	private static inline var PRESS_TOLERANCE:Float = 8;
	/** 拖动到列表上下边缘多少像素内时自动滚动 */
	private static inline var SORT_EDGE:Float = 26;

	/** 可选主题色；0 表示默认（亮黄）。 */
	private static var PRESET_COLORS:Array<Int> = [
		0,
		0xFF8B5CF6,
		0xFF00E5FF,
		0xFFFF7A00,
		0xFFEF4444,
		0xFF22C55E,
		0xFFEC4899,
		0xFF3B82F6,
		0xFF14B8A6,
		0xFFFFFFFF
	];

	public var onClose:Void->Void;
	public var onSaved:Void->Void;

	private var songs:Array<SongMetadata>;
	private var cats:Array<FreeplayCategory> = [];
	private var removedIds:Array<String> = [];
	private var originalSigs:Map<String, String> = new Map();
	/** 打开编辑器时的分区顺序快照（id 序列），用于判断是否只改了顺序 */
	private var originalOrderSig:String = '';
	private var sel:Int = -1;

	private var font:String;
	private var dim:Box = null;
	private var root:HBox = null;
	private var catBox:Absolute = null;
	private var catItems:Array<Label> = [];
	/** 与 catItems 一一对应的行容器（Absolute 手动排版，拖动排序时整行跟手/缓动） */
	private var catRows:Array<HBox> = [];
	/** 每一行在内容坐标里的目标 y（cats 下标对齐） */
	private var catRowTargets:Array<Float> = [];
	/** 组名标题与分组空行（重建时创建，位置由 layoutCategoryRows 负责） */
	private var catHeaders:Array<Label> = [];
	private var catGaps:Array<Box> = [];
	/** 行缓动中：为 true 时 update() 每帧把各行插值到目标位置 */
	private var catAnimating:Bool = false;
	private var catScroll:ScrollView = null;
	/** 正在拖动排序的行（cats 下标；-1 表示没有在拖动） */
	private var draggingIdx:Int = -1;
	/** 被拖动行及其原样式（松手后恢复，避免整表重建带来的闪烁） */
	private var draggingRow:HBox = null;
	private var draggingRowStyle:String = '';
	private var draggingHandle:Label = null;
	private var draggingHandleStyle:String = '';
	/** 按下点与被拖动行顶部的偏移（内容坐标），拖动时让行跟手 */
	private var sortGrabOffset:Float = 0;
	/** 长按检测：按下的行、按下时刻与按下位置（屏幕坐标） */
	private var pressRow:Int = -1;
	private var pressStamp:Float = 0;
	private var pressX:Float = 0;
	private var pressY:Float = 0;
	/** 拖动过程中最近一次的指针屏幕纵坐标（贴边自动滚动用） */
	private var sortScreenY:Float = 0;
	private var nameField:TextField = null;
	private var searchField:TextField = null;
	private var songScroll:ScrollView = null;
	private var songContent:Absolute = null;
	private var rowPool:Array<CheckBox> = [];
	/** 每个槽位当前绑定的行号（filtered 数组的下标；-1 表示空槽） */
	private var rowFilteredIndex:Array<Int> = [];
	private var membership:Array<Bool> = [];
	private var filtered:Array<Int> = [];
	private var songRowW:Float = 0;
	// 缓存每首歌对应的周目文件名/显示名，避免 1000+ 首 × 多个分区时反复查表
	private var songWeekFile:Array<String> = [];
	private var songWeekName:Array<String> = [];
	// 曲名路径 / 归一化文件夹：每首歌只算一次，匹配时零分配
	private var songPath:Array<String> = [];
	private var songFolder:Array<String> = [];
	private var swatches:Array<Box> = [];
	private var deleteBtn:Button = null;
	private var deleteArmed:Bool = false;
	/** 当前分区来源标注（全局配置 / 某个模组配置 / 新建） */
	private var sourceLabel:Label = null;
	/** 曲目列表的竖向滚动条（懒查找，滚动条可能因内容变化被 ScrollView 重建） */
	private var songVScroll:VerticalScroll = null;
	/** 新建分区的目标选择弹窗（保存时出现，选择后写盘） */
	private var targetDim:Box = null;
	private var targetPanel:VBox = null;
	#if mobile
	/** 当前唤起系统软键盘的输入框（null 表示键盘已收起） */
	private var keyboardField:TextField = null;
	#end

	/** 深色主题样式是否已注入（全局 StyleSheet 只需注入一次）。 */
	private static var _themeApplied:Bool = false;

	/**
	 * 编辑器配色修复。
	 *
	 * haxe.ui 默认使用浅色主题：ScrollView 是纯白底（$tertiary-background-color）、
	 * 按钮是浅灰渐变底、复选框是白色方块，而编辑器面板是深色，于是出现「又黑又白」。
	 * 这里用 `.fpce` 作用域（挂在 root 上）覆盖这些控件配色，不影响 Freeplay 搜索框、
	 * 设置页按钮等其它 HaxeUI 界面。
	 *
	 * 注意：haxe.ui 的样式按规则顺序后者覆盖前者，所以通用 `.button` 规则写在前面，
	 * 滚动条按钮（也是 .button）的规则写在后面，避免被通用规则盖掉。
	 */
	private static function ensureEditorTheme():Void
	{
		if (_themeApplied)
			return;
		_themeApplied = true;

		if (!Toolkit.initialized)
		{
			Toolkit.autoScale = false;
			Toolkit.init();
		}

		Toolkit.styleSheet.parse('
			.fpce .scrollview {
				background-color: #101018;
				border: 1px solid #3A3A4A;
			}
			.fpce .scrollview .scrollview-contents {
				background-color: none;
			}
			.fpce .button {
				background: #1C1C28 #1C1C28 vertical;
				color: #E6E6F0;
				border: 1px solid #3A3A4A;
				border-radius: 3px;
			}
			.fpce .button:hover {
				background: #2A2A3C #2A2A3C vertical;
				color: #FFFFFF;
				border-color: #FFD800;
			}
			.fpce .button:down {
				background: #FFD800 #FFD800 vertical;
				color: #0C0C12;
				border-color: #FFD800;
				filter: none;
			}
			.fpce .button:disabled {
				background: #16161E #16161E vertical;
				color: #5A5A6A;
				border-color: #2A2A38;
			}
			.fpce .button .label {
				color: #E6E6F0;
			}
			.fpce .button:hover .label {
				color: #FFFFFF;
			}
			.fpce .button:down .label {
				color: #0C0C12;
			}
			.fpce .button:disabled .label {
				color: #5A5A6A;
			}
			.fpce .scroll {
				background-color: #0C0C12;
			}
			.fpce .scroll .button {
				background-color: #4A4A5E;
				border: none;
				filter: none;
				opacity: 0.85;
			}
			.fpce .scroll .button:hover {
				opacity: 1;
			}
			.fpce .vertical-scroll {
				border-left: 1px solid #3A3A4A;
			}
			.fpce .horizontal-scroll {
				border-top: 1px solid #3A3A4A;
			}
			.fpce .checkbox-label {
				color: #DDDDDD;
			}
			.fpce .checkbox-value {
				background-color: #20202C;
				border: 1px solid #55556A;
				filter: none;
			}
			.fpce .checkbox-value:hover, .fpce .checkbox-value:active {
				border-color: #FFD800;
			}
			/*
			 * 勾选状态不用 haxe.ui 默认的 check-blue.png 图片，改成纯色块。
			 * 该图片由 FlxGraphic 缓存共享同一个 FlxFrame，而组件销毁时
			 * FlxSprite.destroy 会把这个共享 FlxFrame 一并销毁，导致下一次打开
			 * 编辑器时所有复选框变成 Flixel 的默认图；不使用图片即可彻底规避。
			 */
			.fpce .checkbox-value:selected {
				icon: none;
				background-color: #FFD800;
				border-color: #FFD800;
			}
			/* 右侧曲目列表的滚动条加宽一倍（默认 8px → 16px），滑块同步加宽，触屏更好拖 */
			.fpce .fpc-songview .vertical-scroll {
				width: 16px;
				padding-left: 2px;
			}
			.fpce .fpc-songview .scroll .button {
				width: 13px;
			}
		');
	}

	public function new(songList:Array<SongMetadata>)
	{
		songs = songList;
		font = Paths.font('unifont-18.0.01.otf');

		for (c in FreeplayCategory.loadAll())
		{
			cats.push(c);
			originalSigs.set(c.id, signature(c));
		}
		originalOrderSig = orderSignature();

		// 周目信息只查一次：分区匹配/计数/同步都会用到，1000+ 首时省下大量 Map 查询
		for (i in 0...songs.length)
		{
			songWeekFile.push(weekFileName(songs[i]));
			songWeekName.push(weekDisplayName(songs[i]));
			songPath.push(Paths.formatToSongPath(songs[i].songName));
			songFolder.push(FreeplayCategory.normalizeFolderName(songs[i].folder));
		}
	}

	// ==================== 对外接口 ====================

	/** 创建并挂载全部组件（此时才真正绘制到屏幕上）。 */
	public function build():Void
	{
		ensureEditorTheme();

		var panelW:Float = FlxG.width - MARGIN_X * 2;
		var panelH:Float = FlxG.height - MARGIN_Y * 2;
		var innerH:Float = panelH - PAD * 2;
		var rightW:Float = panelW - PAD * 2 - LEFT_W - GAP;

		dim = new Box();
		dim.x = 0;
		dim.y = 0;
		dim.width = FlxG.width;
		dim.height = FlxG.height;
		dim.styleString = 'background-color: #000000; background-opacity: 0.6;';

		root = new HBox();
		// 作用域标记：下面的深色配色规则只作用于 .fpce 子树，不影响其它 HaxeUI 界面
		root.addClass('fpce');
		root.x = MARGIN_X;
		root.y = MARGIN_Y;
		root.width = panelW;
		root.height = panelH;
		root.styleString = 'padding: ${PAD}px; horizontal-spacing: ${GAP}px; background-color: #0C0C12; background-opacity: 0.96; border-color: #333340; border-size: 2px;';

		// ---------- 左列：分区列表 ----------
		var left:VBox = new VBox();
		left.width = LEFT_W;
		left.height = innerH;
		left.styleString = 'padding: 0; vertical-spacing: 8px;';

		var title:Label = makeLabel(OptionsLanguage.get('freeplay_cat_editor_title', 'CATEGORY EDITOR'), FONT_SIZE, '#FFD800');
		title.width = LEFT_W;
		title.height = 26;

		catScroll = new ScrollView();
		catScroll.width = LEFT_W;
		catScroll.height = Std.int(innerH - 26 - 34 - 16);
		// 直接写死在组件上：即使主题样式未命中也不会出现白底列表
		catScroll.styleString = 'background-color: #101018; border-color: #3A3A4A; border-size: 1px;';
		// 惯性滑动：松手后按拖动速度自然减速（触屏/鼠标拖动都生效）
		catScroll.scrollMode = ScrollMode.INERTIAL;

		// 分区列表用 Absolute 手动排版：拖动排序时可以逐行缓动到新位置，
		// 不需要每次换位都重建整个列表（重建正是之前"闪一下/很卡"的原因）
		catBox = new Absolute();
		catBox.width = LEFT_W - 18;
		catBox.styleString = 'padding: 0;';
		catScroll.addComponent(catBox);

		var leftBtns:HBox = new HBox();
		leftBtns.width = LEFT_W;
		leftBtns.height = 34;
		leftBtns.styleString = 'padding: 0; horizontal-spacing: 8px;';
		var btnW:Float = (LEFT_W - 8) / 2;
		var newBtn:Button = makeButton(OptionsLanguage.get('freeplay_cat_editor_new', 'New'), btnW, 32, createCategory);
		deleteBtn = makeButton(OptionsLanguage.get('freeplay_cat_editor_delete', 'Delete'), btnW, 32, deleteCategory);
		leftBtns.addComponent(newBtn);
		leftBtns.addComponent(deleteBtn);

		left.addComponent(title);
		left.addComponent(catScroll);
		left.addComponent(leftBtns);

		// ---------- 右列：名称 / 颜色 / 曲目 ----------
		var right:VBox = new VBox();
		right.width = rightW;
		right.height = innerH;
		right.styleString = 'padding: 0; vertical-spacing: 8px;';

		var labelW:Float = 64;
		var fieldW:Float = rightW - labelW - 8;

		// 名称
		var nameRow:HBox = new HBox();
		nameRow.width = rightW;
		nameRow.height = 30;
		nameRow.styleString = 'padding: 0; horizontal-spacing: 8px; vertical-align: center;';
		var nameLbl:Label = makeLabel(OptionsLanguage.get('freeplay_cat_editor_name', 'Name'), FONT_SIZE, '#9C9CAA');
		nameLbl.width = labelW;
		nameField = new TextField();
		nameField.width = fieldW;
		nameField.height = 26;
		nameField.maxChars = 48;
		nameField.allowFocus = true;
		nameField.styleString = 'font-name: $font; font-size: ${FONT_SIZE}px; padding: 3px 6px;';
		#if mobile
		// 软键盘可能被输入法的「完成」键收起，点一下输入框就重新唤起（下一帧刷新）
		nameField.registerEvent(MouseEvent.CLICK, function(_) keyboardField = null);
		#end
		nameRow.addComponent(nameLbl);
		nameRow.addComponent(nameField);

		// 来源标注：注明当前分区来自全局配置、某个模组配置，还是本次新建
		var sourceRow:HBox = new HBox();
		sourceRow.width = rightW;
		sourceRow.height = 22;
		sourceRow.styleString = 'padding: 0; horizontal-spacing: 8px; vertical-align: center;';
		sourceLabel = makeLabel('', FONT_SIZE, '#8A8AA0');
		sourceLabel.width = rightW;
		sourceRow.addComponent(sourceLabel);

		// 颜色
		var colorRow:HBox = new HBox();
		colorRow.width = rightW;
		colorRow.height = 30;
		colorRow.styleString = 'padding: 0; horizontal-spacing: 8px; vertical-align: center;';
		var colorLbl:Label = makeLabel(OptionsLanguage.get('freeplay_cat_editor_color', 'Color'), FONT_SIZE, '#9C9CAA');
		colorLbl.width = labelW;
		colorRow.addComponent(colorLbl);
		for (c in PRESET_COLORS)
		{
			var sw:Box = new Box();
			sw.width = 26;
			sw.height = 24;
			sw.tooltip = FreeplayCategory.colorToHex(c == 0 ? 0xFFFFD800 : c);
			sw.styleString = swatchStyle(c, false);
			var color:Int = c;
			sw.registerEvent(MouseEvent.CLICK, function(_) pickColor(color));
			colorRow.addComponent(sw);
			swatches.push(sw);
		}

		// 搜索
		var searchRow:HBox = new HBox();
		searchRow.width = rightW;
		searchRow.height = 30;
		searchRow.styleString = 'padding: 0; horizontal-spacing: 8px; vertical-align: center;';
		var searchLbl:Label = makeLabel(OptionsLanguage.get('freeplay_cat_editor_search_label', 'Search'), FONT_SIZE, '#9C9CAA');
		searchLbl.width = labelW;
		searchField = new TextField();
		searchField.width = fieldW;
		searchField.height = 26;
		searchField.maxChars = 40;
		searchField.styleString = 'font-name: $font; font-size: ${FONT_SIZE}px; padding: 3px 6px;';
		#if mobile
		searchField.registerEvent(MouseEvent.CLICK, function(_) keyboardField = null);
		#end
		searchField.registerEvent(UIEvent.CHANGE, function(_) applySongFilter());
		searchField.registerEvent(UIEvent.SUBMIT, function(_) searchField.focus = false);
		searchRow.addComponent(searchLbl);
		searchRow.addComponent(searchField);

		// 曲目列表（虚拟滚动：只创建可见窗口内的行，1000+ 首也不会卡）
		songScroll = new ScrollView();
		songScroll.width = rightW;
		songScroll.height = Std.int(Math.max(80, innerH - 30 * 3 - 22 - 34 - 8 * 5));
		songScroll.styleString = 'background-color: #101018; border-color: #3A3A4A; border-size: 1px;';
		songScroll.scrollMode = ScrollMode.INERTIAL;
		// 标记这个滚动视图：让加宽后的滚动条样式只作用于它，不影响左侧分区列表
		songScroll.addClass('fpc-songview');
		// 滚动条加宽到 16px，内容区宽度相应多让出 8px，避免出现横向滚动条
		songRowW = rightW - 26;
		songContent = new Absolute();
		songContent.width = songRowW;
		songContent.height = ROW_H;
		songScroll.addComponent(songContent);

		var poolSize:Int = Std.int(Math.ceil(songScroll.height / ROW_H)) + 4;
		poolSize = Std.int(Math.min(ROW_POOL_MAX, Math.max(6, poolSize)));
		for (i in 0...poolSize)
		{
			var row:CheckBox = new CheckBox();
			row.width = songRowW;
			row.height = ROW_H;
			row.left = 0;
			row.top = 0;
			row.allowFocus = false;
			row.hidden = true;
			row.styleString = 'font-name: $font; font-size: ${FONT_SIZE}px; color: #DDDDDD;';
			songContent.addComponent(row);
			rowPool.push(row);
			rowFilteredIndex.push(-1);
		}

		// 底部按钮
		var bottom:HBox = new HBox();
		bottom.width = rightW;
		bottom.height = 34;
		bottom.styleString = 'padding: 0; horizontal-spacing: 8px;';
		var spacer:Box = new Box();
		spacer.width = Math.max(0, rightW - 110 * 2 - 8 - 4);
		spacer.height = 1;
		var cancelBtn:Button = makeButton(OptionsLanguage.get('freeplay_cat_editor_cancel', 'Cancel'), 110, 32, close);
		var saveBtn:Button = makeButton(OptionsLanguage.get('freeplay_cat_editor_save', 'Save'), 110, 32, save);
		bottom.addComponent(spacer);
		bottom.addComponent(cancelBtn);
		bottom.addComponent(saveBtn);

		right.addComponent(nameRow);
		right.addComponent(sourceRow);
		right.addComponent(colorRow);
		right.addComponent(searchRow);
		right.addComponent(songScroll);
		right.addComponent(bottom);

		root.addComponent(left);
		root.addComponent(right);

		Screen.instance.addComponent(dim);
		Screen.instance.addComponent(root);

		// 拖动排序：手柄按下后由编辑器在屏幕层跟踪移动/松手（列表重建时手柄组件会被替换掉）
		Screen.instance.registerEvent(MouseEvent.MOUSE_MOVE, onEditorMouseMove);
		Screen.instance.registerEvent(MouseEvent.MOUSE_UP, onEditorMouseUp);

		selectCategory(cats.length > 0 ? 0 : -1);
	}

	/** 移除并销毁所有组件（关闭编辑器时调用）。 */
	public function destroy():Void
	{
		clearToolTips();
		blurFields();
		closeTargetPicker();
		Screen.instance.unregisterEvent(MouseEvent.MOUSE_MOVE, onEditorMouseMove);
		Screen.instance.unregisterEvent(MouseEvent.MOUSE_UP, onEditorMouseUp);
		if (root != null)
		{
			Screen.instance.removeComponent(root, true);
			root = null;
		}
		if (dim != null)
		{
			Screen.instance.removeComponent(dim, true);
			dim = null;
		}
		catItems = [];
		catRows = [];
		catRowTargets = [];
		catHeaders = [];
		catGaps = [];
		catAnimating = false;
		draggingIdx = -1;
		draggingRow = null;
		draggingHandle = null;
		pressRow = -1;
		rowPool = [];
		rowFilteredIndex = [];
		membership = [];
		filtered = [];
		swatches = [];
		catBox = null;
		catScroll = null;
		songScroll = null;
		songContent = null;
		nameField = null;
		searchField = null;
		deleteBtn = null;
		sourceLabel = null;
		songVScroll = null;
	}

	public function isTyping():Bool
	{
		return (nameField != null && nameField.focus) || (searchField != null && searchField.focus);
	}

	public function blurFields():Void
	{
		if (nameField != null)
			nameField.focus = false;
		if (searchField != null)
			searchField.focus = false;
		#if mobile
		// 编辑器的 update() 在弹窗打开时会被跳过，这里主动收起系统键盘
		if (keyboardField != null)
		{
			keyboardField = null;
			setSoftKeyboard(false);
		}
		#end
	}

	#if mobile
	/**
	 * 每帧同步系统软键盘状态：输入框获得焦点时唤起，失焦时收起。
	 *
	 * haxe.ui(Flixel) 的输入框底层是 FlxInputText，它只会处理硬件键盘的 KEY_DOWN；
	 * 打开 lime 窗口的 textInputEnabled（即 SDL_StartTextInput）后 Android 会弹出系统输入法，
	 * 输入法提交的字符通过 window.onTextInput 送进当前聚焦的 FlxInputText，
	 * 中文、表情等也能正常写入，不需要自己拼接字符串。
	 */
	private function updateSoftKeyboard():Void
	{
		var field:TextField = null;
		if (nameField != null && nameField.focus)
			field = nameField;
		else if (searchField != null && searchField.focus)
			field = searchField;

		if (field == null)
		{
			if (keyboardField != null)
			{
				keyboardField = null;
				setSoftKeyboard(false);
			}
			return;
		}
		if (field == keyboardField)
			return;
		keyboardField = field;
		setSoftKeyboard(true);
	}

	/** 唤起 / 收起系统键盘；唤起时告知输入法输入框的位置，避免候选栏遮住它。 */
	private function setSoftKeyboard(show:Bool):Void
	{
		var window = FlxG.stage.window;
		if (window == null)
			return;
		try
		{
			var field:TextField = keyboardField;
			if (show && field != null && FlxG.width > 0 && FlxG.height > 0)
			{
				// HaxeUI 用游戏逻辑坐标（FlxG 尺寸），窗口是物理像素，这里做换算
				var sx:Float = window.width / FlxG.width;
				var sy:Float = window.height / FlxG.height;
				var pos:{x:Float, y:Float} = absolutePosition(field);
				if (pos.x >= 0 && pos.y >= 0 && field.width > 0 && field.height > 0)
					window.setTextInputRect(new Rectangle(pos.x * sx, pos.y * sy, field.width * sx, field.height * sy));
			}
			window.textInputEnabled = show;
		}
		catch (e:Dynamic)
			trace('[FREEPLAY] 软键盘切换失败: ' + e);
	}

	/** HaxeUI 组件的全局坐标（累加各级父组件的相对位置）。 */
	private static function absolutePosition(c:Component):{x:Float, y:Float}
	{
		var x:Float = 0;
		var y:Float = 0;
		var cur:Component = c;
		while (cur != null)
		{
			x += cur.x;
			y += cur.y;
			cur = cur.parentComponent;
		}
		return {x: x, y: y};
	}
	#end

	/** BACK 键：软键盘展开时先收起键盘（返回 true 表示已处理，编辑器本身不关闭）。 */
	public function cancelSoftKeyboard():Bool
	{
		#if mobile
		if (keyboardField == null)
			return false;
		keyboardField = null;
		setSoftKeyboard(false);
		if (nameField != null)
			nameField.focus = false;
		if (searchField != null)
			searchField.focus = false;
		return true;
		#else
		return false;
		#end
	}

	// ==================== 分区列表 ====================

	private function selectCategory(idx:Int):Void
	{
		commitAll();
		sel = idx;
		deleteArmed = false;
		if (deleteBtn != null)
			deleteBtn.text = OptionsLanguage.get('freeplay_cat_editor_delete', 'Delete');
		rebuildCategoryList();
		refreshEditor();
	}

	private function rebuildCategoryList():Void
	{
		catBox.removeAllComponents();
		catItems = [];
		catRows = [];
		catHeaders = [];
		catGaps = [];
		catRowTargets = [];
		draggingRow = null;
		draggingHandle = null;
		var lastGroup:String = null;
		for (i in 0...cats.length)
		{
			var idx:Int = i;
			var cat:FreeplayCategory = cats[i];
			var group:String = groupFile(cat);

			// 不同来源（全局 / 各模组 / 新建）之间空一行并给个组名，方便区分和分组排序
			if (group != lastGroup)
			{
				if (i > 0)
				{
					var gap:Box = new Box();
					gap.width = catBox.width;
					gap.height = GROUP_GAP_H;
					gap.styleString = 'background-color: none;';
					gap.left = 0;
					catBox.addComponent(gap);
					catGaps.push(gap);
				}
				var header:Label = makeLabel(groupTitle(cat), FONT_SIZE, '#6E6E84');
				header.width = catBox.width;
				header.height = GROUP_TITLE_H;
				header.styleString += ' padding: 3px 4px;';
				header.left = 0;
				catBox.addComponent(header);
				catHeaders.push(header);
				lastGroup = group;
			}

			var isSel:Bool = (idx == sel);
			var row:HBox = new HBox();
			row.width = catBox.width;
			row.height = CAT_ROW_H;
			row.left = 0;
			row.styleString = rowStyleFor(isSel, false);

			// 拖动排序时行控件只是数组换位（不重建），所以回调里不能捕获创建时的下标 idx：
			// 排序后下标已经变了，用旧下标点击会选到别的分区，甚至因为下标恰好等于 sel
			// 而"点了没反应"。每次事件都按 catRows 里的当前位置重新查。
			var currentIndex = function():Int return catRows.indexOf(row);

			// 左侧手柄：长按后可以上下拖动这一行来排序
			var handle:Label = new Label();
			handle.text = '☰';
			handle.width = HANDLE_W;
			handle.height = CAT_ROW_H;
			handle.styleString = 'font-name: $font; font-size: ${FONT_SIZE}px; padding: 4px 0; color: '
				+ (isSel ? '#0C0C12' : '#5A5A6E');
			handle.registerEvent(MouseEvent.MOUSE_DOWN, function(e:MouseEvent) {
				// 取消冒泡：否则 ScrollView 会把这次按下当成拖动列表（长按期间列表会跟着乱滑）
				e.cancel();
				var i:Int = currentIndex();
				if (i >= 0)
					beginPress(i, e);
			});

			var item:Label = new Label();
			item.text = catLabelText(cat);
			item.width = catBox.width - HANDLE_W - 2;
			item.height = CAT_ROW_H;
			item.styleString = 'font-name: $font; font-size: ${FONT_SIZE}px; padding: 4px 4px; '
				+ ((isSel) ? 'color: #0C0C12;' : 'color: #C8C8D0;');
			row.registerEvent(MouseEvent.CLICK, function(_) {
				var i:Int = currentIndex();
				if (i >= 0 && i != sel)
					selectCategory(i);
			});

			row.addComponent(handle);
			row.addComponent(item);
			catBox.addComponent(row);
			catItems.push(item);
			catRows.push(row);
			catRowTargets.push(0);
		}
		layoutCategoryRows(true);
	}

	private static function rowStyleFor(selected:Bool, dragging:Bool):String
	{
		if (dragging)
			return 'padding: 0; vertical-align: center; background-color: #2E2E44; border-color: #FFD800; border-size: 1px;';
		return 'padding: 0; vertical-align: center; ' + (selected ? 'background-color: #FFD800;' : '');
	}

	/**
	 * 按当前 cats 顺序计算每一行的目标 y，并更新内容总高度。
	 * immediate=true 时直接把行放到目标位置（列表重建后用）；
	 * 否则只更新目标值，由 update() 里的 animateCategoryRows 逐帧缓动过去。
	 */
	private function layoutCategoryRows(immediate:Bool):Void
	{
		if (catBox == null)
			return;
		var y:Float = 0;
		var lastGroup:String = null;
		var gi:Int = 0;
		var hi:Int = 0;
		for (i in 0...cats.length)
		{
			var group:String = groupFile(cats[i]);
			if (group != lastGroup)
			{
				if (i > 0)
				{
					if (gi < catGaps.length)
						catGaps[gi++].top = y;
					y += GROUP_GAP_H + CAT_ROW_GAP;
				}
				if (hi < catHeaders.length)
					catHeaders[hi++].top = y;
				y += GROUP_TITLE_H + CAT_ROW_GAP;
				lastGroup = group;
			}
			catRowTargets[i] = y;
			if (immediate && i < catRows.length)
				catRows[i].top = y;
			y += CAT_ROW_H + CAT_ROW_GAP;
		}
		catBox.height = y;
		if (!immediate)
			catAnimating = true;
	}

	/** 逐帧把各行插值到目标位置（被拖动的行由指针驱动，不参与缓动）。 */
	private function animateCategoryRows():Void
	{
		if (draggingIdx >= 0)
		{
			// 拖动期间其它行也要让位，所以这里不做整体早退
		}
		else if (!catAnimating)
			return;

		var k:Float = Math.min(0.5, FlxG.elapsed * 18);
		var moving:Bool = false;
		for (i in 0...catRows.length)
		{
			if (i == draggingIdx)
				continue;
			var row:HBox = catRows[i];
			if (row == null || i >= catRowTargets.length)
				continue;
			var target:Float = catRowTargets[i];
			var cur:Float = (row.top == null) ? 0 : row.top;
			var diff:Float = target - cur;
			if (Math.abs(diff) < 0.5)
			{
				if (diff != 0)
					row.top = target;
			}
			else
			{
				row.top = cur + diff * k;
				moving = true;
			}
		}
		if (draggingIdx >= 0)
			moving = true;
		catAnimating = moving;
	}

	/** 分组依据：分区归属的配置文件（新建分区为空字符串）。 */
	private static function groupFile(cat:FreeplayCategory):String
	{
		return FreeplayCategory.groupFileOf(cat);
	}

	/** 分组标题：全局 / 模组目录名 / 新建。 */
	private function groupTitle(cat:FreeplayCategory):String
	{
		var path:String = groupFile(cat);
		if (path.length == 0)
			return OptionsLanguage.get('freeplay_cat_editor_group_new', 'NEW (not saved yet)');
		if (path == Paths.mods('freeplay_categories.json'))
			return OptionsLanguage.get('freeplay_cat_editor_source_global', 'Global');
		// mods/<模组>/freeplay_categories.json → 取模组目录名
		var rel:String = relativeModPath(path);
		var slash:Int = rel.indexOf('/');
		return (slash > 0) ? rel.substr(0, slash) : rel;
	}

	/** 同一来源的分区在 cats 里是连续的一段，返回这段的起止下标。 */
	private function groupRangeOf(idx:Int):{start:Int, end:Int}
	{
		var key:String = groupFile(cats[idx]);
		var start:Int = idx;
		while (start > 0 && groupFile(cats[start - 1]) == key)
			start--;
		var end:Int = idx;
		while (end + 1 < cats.length && groupFile(cats[end + 1]) == key)
			end++;
		return {start: start, end: end};
	}

	// ==================== 长按拖动排序 ====================

	/** 手柄按下：开始长按计时。 */
	private function beginPress(idx:Int, e:MouseEvent):Void
	{
		if (draggingIdx >= 0)
			return;
		pressRow = idx;
		pressStamp = haxe.Timer.stamp();
		pressX = e.screenX;
		pressY = e.screenY;
	}

	/** 每帧检查长按是否到时间（不使用 Timer，避免回调在非主线程里操作 UI）。 */
	private function updateLongPress():Void
	{
		if (pressRow < 0 || draggingIdx >= 0)
			return;
		if (pressRow >= cats.length)
		{
			pressRow = -1;
			return;
		}
		if (haxe.Timer.stamp() - pressStamp >= LONG_PRESS_TIME)
			startSorting(pressRow);
	}

	private function startSorting(idx:Int):Void
	{
		pressRow = -1;
		if (idx < 0 || idx >= cats.length || idx >= catRows.length)
			return;
		draggingIdx = idx;
		sortScreenY = pressY;

		// 抓住的位置：按下点相对行顶部的偏移，拖动时整行跟着指针走
		sortGrabOffset = pressY - catBox.screenTop - ((catRows[idx].top == null) ? 0 : catRows[idx].top);

		draggingRow = catRows[idx];
		draggingRowStyle = draggingRow.styleString;
		draggingRow.styleString = rowStyleFor(false, true);
		// 画在最上层，拖动时不会被相邻行盖住
		catBox.setComponentIndex(draggingRow, catBox.numComponents - 1);

		draggingHandle = cast draggingRow.getComponentAt(0);
		if (draggingHandle != null)
		{
			draggingHandleStyle = draggingHandle.styleString;
			draggingHandle.styleString = 'font-name: $font; font-size: ${FONT_SIZE}px; padding: 4px 0; color: #FFD800;';
		}
		catAnimating = true;
	}

	private function onEditorMouseMove(e:MouseEvent):Void
	{
		if (draggingIdx >= 0)
		{
			sortScreenY = e.screenY;
			dragRowToPointer();
			applySortPosition(e.screenY - catBox.screenTop);
			return;
		}
		// 还没到长按时间就明显移动了：认为用户想滚动列表，放弃这次长按
		if (pressRow >= 0 && (Math.abs(e.screenX - pressX) > PRESS_TOLERANCE || Math.abs(e.screenY - pressY) > PRESS_TOLERANCE))
			pressRow = -1;
	}

	/** 让被拖动的行跟住指针（内容坐标，忽略滚动位移）。 */
	private function dragRowToPointer():Void
	{
		if (draggingRow == null || catBox == null)
			return;
		var y:Float = sortScreenY - catBox.screenTop - sortGrabOffset;
		if (y < 0)
			y = 0;
		draggingRow.top = y;
	}

	private function onEditorMouseUp(_:MouseEvent):Void
	{
		pressRow = -1;
		if (draggingIdx < 0)
			return;
		if (draggingRow != null)
			draggingRow.styleString = draggingRowStyle;
		if (draggingHandle != null)
			draggingHandle.styleString = draggingHandleStyle;
		draggingRow = null;
		draggingHandle = null;
		draggingIdx = -1;
		// 松手后让整行缓动回它的槽位，而不是直接重建列表（重建会闪一下）
		layoutCategoryRows(false);
	}

	/** 根据指针位置把正在拖动的行挪到对应位置（只在同一来源分组内移动）。 */
	private function applySortPosition(pointerY:Float):Void
{
		if (draggingIdx < 0 || draggingIdx >= cats.length)
			return;

		var range:{start:Int, end:Int} = groupRangeOf(draggingIdx);
		var target:Int = draggingIdx;
		for (j in range.start...range.end + 1)
		{
			if (j >= catRowTargets.length)
				continue;
			if (pointerY < catRowTargets[j] + CAT_ROW_H * 0.5)
			{
				target = j;
				break;
			}
			target = j;
		}

		var from:Int = draggingIdx;
		var to:Int = (target > from) ? target - 1 : target;
		if (to < range.start)
			to = range.start;
		if (to > range.end)
			to = range.end;
		if (to == from)
			return;

		var moved:FreeplayCategory = cats[from];
		cats.splice(from, 1);
		cats.insert(to, moved);
		// 行控件与文字标签跟着一起换位（不重建组件，只让它们缓动到新位置）
		var movedRow:HBox = catRows.splice(from, 1)[0];
		catRows.insert(to, movedRow);
		var movedLabel:Label = catItems.splice(from, 1)[0];
		catItems.insert(to, movedLabel);

		// 选中项跟着移动，右侧编辑面板内容不变
		if (sel == from)
			sel = to;
		else if (from < to && sel > from && sel <= to)
			sel--;
		else if (from > to && sel >= to && sel < from)
			sel++;

		draggingIdx = to;
		layoutCategoryRows(false);
	}

	/** 拖动到列表上下边缘时自动滚动，并重新计算落点。 */
	private function updateSortAutoScroll():Void
	{
		if (draggingIdx < 0 || catScroll == null)
			return;
		var top:Float = catScroll.screenTop;
		var bottom:Float = top + catScroll.height;
		var pos:Float = catScroll.vscrollPos;
		if (sortScreenY < top + SORT_EDGE)
			pos = Math.max(0, pos - 6);
		else if (sortScreenY > bottom - SORT_EDGE)
			pos = Math.min(catScroll.vscrollMax, pos + 6);

		if (pos != catScroll.vscrollPos)
		{
			catScroll.vscrollPos = pos;
			applySortPosition(sortScreenY - catBox.screenTop);
		}
	}

	private function catLabelText(cat:FreeplayCategory):String
	{
		return cat.getDisplayName() + '  (' + countSongs(cat) + ')';
	}

	private function countSongs(cat:FreeplayCategory):Int
	{
		var n:Int = 0;
		for (i in 0...songs.length)
		{
			if (cat.matchesPrepared(songPath[i], songFolder[i], songWeekFile[i], songWeekName[i]))
				n++;
		}
		return n;
	}

	private function refreshEditor():Void
	{
		var cat:FreeplayCategory = currentCat();
		var has:Bool = (cat != null);

		if (nameField != null)
		{
			nameField.text = has ? (cat.name == null ? '' : cat.name) : '';
			nameField.disabled = !has;
		}
		if (searchField != null)
		{
			searchField.text = '';
			searchField.disabled = !has;
		}

		resetSongView();
		updateSwatches();
		updateSourceLabel();
	}

	/** 刷新"来源"标注：全局配置 / 模组配置 / 本次新建（保存时写入全局）。 */
	private function updateSourceLabel():Void
	{
		if (sourceLabel == null)
			return;

		var cat:FreeplayCategory = currentCat();
		if (cat == null)
		{
			sourceLabel.text = '';
			return;
		}

		var globalPath:String = Paths.mods('freeplay_categories.json');
		var kind:String;
		// 全局 + 模组都定义过时以模组为准（保存也写回模组文件）
		var path:String = (cat.modSourceFile != null && cat.modSourceFile.length > 0) ? cat.modSourceFile
			: ((cat.sourceFile == null) ? '' : cat.sourceFile);
		if (path.length == 0)
		{
			kind = OptionsLanguage.get('freeplay_cat_editor_source_new', 'New (choose location on save)');
			path = globalPath;
		}
		else if (path == globalPath)
			kind = OptionsLanguage.get('freeplay_cat_editor_source_global', 'Global');
		else
			kind = OptionsLanguage.get('freeplay_cat_editor_source_mod', 'Mod');

		sourceLabel.text = OptionsLanguage.get('freeplay_cat_editor_source', 'Source: ') + kind + '  ' + relativeModPath(path);
	}

	/** 把绝对路径裁成 `mods/...` 相对路径，方便玩家直接对照文件位置。 */
	private static function relativeModPath(path:String):String
	{
		if (path == null || path.length == 0)
			return '';
		var base:String = Paths.mods('');
		if (path.indexOf(base) == 0)
			return path.substr(base.length);
		return path;
	}

	private function currentCat():FreeplayCategory
	{
		if (sel < 0 || sel >= cats.length)
			return null;
		return cats[sel];
	}

	private function createCategory():Void
	{
		commitAll();
		var cat:FreeplayCategory = new FreeplayCategory();
		cat.id = nextCategoryId();
		cat.name = OptionsLanguage.get('freeplay_cat_editor_new_name', 'New Category');
		cats.push(cat);
		selectCategory(cats.length - 1);
	}

	private function deleteCategory():Void
	{
		var cat:FreeplayCategory = currentCat();
		if (cat == null)
			return;

		if (!deleteArmed)
		{
			deleteArmed = true;
			deleteBtn.text = OptionsLanguage.get('freeplay_cat_editor_delete_confirm', 'Delete?');
			return;
		}

		var oldSel:Int = sel;
		commitAll();
		if (originalSigs.exists(cat.id) && !removedIds.contains(cat.id))
			removedIds.push(cat.id);
		cats.remove(cat);
		sel = -1;
		var nextSel:Int = (cats.length > 0) ? Std.int(Math.min(oldSel, cats.length - 1)) : -1;
		selectCategory(nextSel);
	}

	private function nextCategoryId():String
	{
		var n:Int = 1;
		var id:String = '';
		do
		{
			id = 'cat-' + n;
			n++;
		}
		while (idExists(id));
		return id;
	}

	private function idExists(id:String):Bool
	{
		if (removedIds.contains(id))
			return true;
		for (c in cats)
			if (c.id == id)
				return true;
		return false;
	}

	// ==================== 曲目多选（虚拟滚动） ====================

	/** 每帧由 FreeplayState 调用：同步勾选状态，并按滚动位置重绑可见行。 */
	public function update():Void
	{
		// 保存目标弹窗展开时，底下的曲目列表不可操作，跳过同步省点开销
		if (songContent == null || targetPanel != null)
			return;
		#if mobile
		updateSoftKeyboard();
		#end
		updateLongPress();
		updateSortAutoScroll();
		// 拖动中：贴边滚动会改变内容位置，每帧重新对齐被拖动的行并重算落点
		if (draggingIdx >= 0 && catBox != null)
		{
			dragRowToPointer();
			applySortPosition(sortScreenY - catBox.screenTop);
		}
		animateCategoryRows();
		updateScrollThumb();
		syncRowStates();
		bindRows();
	}

	/**
	 * 给曲目列表的滚动条滑块加最小高度。
	 *
	 * haxe.ui 的滑块高度 = 可见高度 / 内容高度 × 轨道高度，曲目上千首时滑块只有十几像素，
	 * 触屏几乎拖不住。这里按同样的比例算一遍，低于下限时通过 Scroll.thumbSize 固定成
	 * MIN_THUMB_H；不触发下限时置回 null，恢复 haxe.ui 的默认按比例计算。
	 */
	private function updateScrollThumb():Void
	{
		if (songScroll == null)
			return;
		// 滚动条可能随内容多少被 ScrollView 内部创建 / 销毁，失效时重新查找
		if (songVScroll == null || songVScroll.parentComponent == null)
			songVScroll = songScroll.findComponent(null, VerticalScroll);
		if (songVScroll == null)
			return;

		var trackH:Float = songVScroll.height;
		if (trackH <= 0)
			return;

		var contentH:Float = filtered.length * ROW_H;
		var target:Null<Float> = null;
		if (contentH > trackH)
		{
			// 与 VerticalScrollLayout 的比例算法一致
			var propH:Float = trackH * (trackH / contentH);
			if (propH < MIN_THUMB_H)
				target = MIN_THUMB_H;
		}

		if (songVScroll.thumbSize == target)
			return;
		songVScroll.thumbSize = target;
		// DefaultBehaviour 改值不会自动重排，手动让滚动条重新算滑块高度与位置
		songVScroll.invalidateComponentLayout();
	}

	/** 重建当前分区的勾选状态与列表内容（切换分区 / 打开面板时调用）。 */
	private function resetSongView():Void
	{
		membership = [];
		filtered = [];
		if (songScroll != null)
			songScroll.vscrollPos = 0;

		var cat:FreeplayCategory = currentCat();
		if (cat != null)
		{
			for (i in 0...songs.length)
				membership.push(cat.matchesPrepared(songPath[i], songFolder[i], songWeekFile[i], songWeekName[i]));
		}

		recomputeFilter();
		applyContentHeight();
		clearRowBindings();
		bindRows();
	}

	/** 按搜索词计算可见曲目索引（空搜索词 = 全部）。 */
	private function recomputeFilter():Void
	{
		filtered = [];
		var q:String = (searchField == null || searchField.text == null) ? '' : searchField.text.toLowerCase().trim();
		for (i in 0...songs.length)
		{
			if (q.length == 0)
			{
				filtered.push(i);
				continue;
			}
			var meta:SongMetadata = songs[i];
			var folder:String = (meta.folder == null) ? '' : meta.folder;
			var text:String = (meta.songName + ' ' + folder).toLowerCase();
			if (text.indexOf(q) != -1)
				filtered.push(i);
		}
	}

	private function applyContentHeight():Void
	{
		if (songContent == null)
			return;
		songContent.width = songRowW;
		songContent.height = Math.max(ROW_H, filtered.length * ROW_H);
	}

	/**
	 * 增量绑定可见行：只处理"滚出 / 滚入"窗口的那几行。
	 *
	 * 早期版本按每 16 行一页整页重绑，拖动时一帧内会改掉几十行的文字和坐标，
	 * 视觉上就是"闪一下、列表瞬移"；改成逐行增量后每次通常只动 1~2 行，滚动全程平滑。
	 */
	private function bindRows():Void
	{
		if (songContent == null || songScroll == null)
			return;
		if (filtered.length == 0)
		{
			clearRowBindings();
			return;
		}

		var scrollY:Float = songScroll.vscrollPos;
		if (Math.isNaN(scrollY) || scrollY < 0)
			scrollY = 0;
		var first:Int = Std.int(scrollY / ROW_H);
		if (first < 0)
			first = 0;

		// 需要覆盖的行区间：可见范围上下各多留一行，避免滚动到边界时闪空行
		var visible:Int = Std.int(Math.ceil(songScroll.height / ROW_H)) + 1;
		var lo:Int = first - 1;
		if (lo < 0)
			lo = 0;
		var hi:Int = first + visible + 2;
		if (hi > filtered.length)
			hi = filtered.length;

		// 1) 释放滚出区间的槽位
		for (slot in 0...rowPool.length)
		{
			var fidx:Int = rowFilteredIndex[slot];
			if (fidx < 0)
				continue;
			if (fidx < lo || fidx >= hi)
			{
				rowFilteredIndex[slot] = -1;
				rowPool[slot].hidden = true;
			}
		}

		// 2) 给区间里还没绑定的行找空槽位
		var slotCursor:Int = 0;
		for (fidx in lo...hi)
		{
			var bound:Bool = false;
			for (slot in 0...rowPool.length)
			{
				if (rowFilteredIndex[slot] == fidx)
				{
					bound = true;
					break;
				}
			}
			if (bound)
				continue;

			while (slotCursor < rowPool.length && rowFilteredIndex[slotCursor] >= 0)
				slotCursor++;
			if (slotCursor >= rowPool.length)
				break; // 池子不够（正常不会发生，创建时已按可见高度留了余量）
			bindRow(slotCursor, fidx);
			slotCursor++;
		}
	}

	/** 清空所有行的绑定（筛选条件 / 分区变化后重新开始）。 */
	private function clearRowBindings():Void
	{
		for (slot in 0...rowPool.length)
		{
			rowFilteredIndex[slot] = -1;
			rowPool[slot].hidden = true;
		}
	}

	private function bindRow(slot:Int, fidx:Int):Void
	{
		var row:CheckBox = rowPool[slot];
		var songIdx:Int = filtered[fidx];
		rowFilteredIndex[slot] = fidx;
		row.hidden = false;
		row.top = fidx * ROW_H;

		var meta:SongMetadata = songs[songIdx];
		var folder:String = (meta.folder == null) ? '' : meta.folder;
		row.text = (folder.length > 0) ? meta.songName + '  [' + folder + ']' : meta.songName;
		row.selected = (songIdx < membership.length) ? membership[songIdx] : false;
	}

	/** 记录用户在当前可见行上的勾选变化（滚出视野前必须先把状态回写）。 */
	private function syncRowStates():Void
	{
		for (slot in 0...rowPool.length)
		{
			var fidx:Int = rowFilteredIndex[slot];
			if (fidx < 0 || fidx >= filtered.length)
				continue;
			var songIdx:Int = filtered[fidx];
			if (songIdx < 0 || songIdx >= membership.length)
				continue;
			membership[songIdx] = rowPool[slot].selected;
		}
	}

	private function applySongFilter():Void
	{
		syncRowStates();
		if (songScroll != null)
			songScroll.vscrollPos = 0;
		recomputeFilter();
		applyContentHeight();
		clearRowBindings();
		bindRows();
	}

	/** 把界面上的勾选状态与名称写回当前分区模型。 */
	private function commitAll():Void
	{
		syncRowStates();
		var cat:FreeplayCategory = currentCat();
		if (cat == null)
			return;

		if (nameField != null)
			cat.name = (nameField.text == null) ? '' : nameField.text.trim();

		// 勾选状态存在 membership 里（不只存在于可见行），所以滚出视野的改动不会丢
		if (membership.length != songs.length)
			return;

		for (i in 0...songs.length)
		{
			var has:Bool = cat.matchesPrepared(songPath[i], songFolder[i], songWeekFile[i], songWeekName[i]);
			if (membership[i] != has)
				setMembership(cat, songs[i], membership[i]);
		}
	}

	private function setMembership(cat:FreeplayCategory, meta:SongMetadata, member:Bool):Void
	{
		var path:String = Paths.formatToSongPath(meta.songName);
		var folder:String = (meta.folder == null) ? '' : meta.folder;
		var wf:String = weekFileName(meta);
		var wn:String = weekDisplayName(meta);

		// 任何改动都先清掉旧的 exclude，再按需求决定是否重新写入
		removeEntries(cat.exclude, path, folder);

		if (member)
		{
			if (!cat.matchesRules(meta, wf, wn))
				addEntry(cat.songs, path, folder);
		}
		else
		{
			removeEntries(cat.songs, path, folder);
			if (cat.matchesRules(meta, wf, wn))
				addEntry(cat.exclude, path, folder);
		}
	}

	private static function addEntry(list:Array<Array<String>>, path:String, folder:String):Void
	{
		for (s in list)
		{
			var f:String = (s[1] == null) ? '' : s[1];
			if (s[0] == path && f == folder)
				return;
		}
		list.push([path, folder]);
	}

	private static function removeEntries(list:Array<Array<String>>, path:String, folder:String):Void
	{
		var normFolder:String = FreeplayCategory.normalizeFolderName(folder);
		var i:Int = list.length - 1;
		while (i >= 0)
		{
			var s:Array<String> = list[i];
			var f:String = (s[1] == null) ? '' : s[1];
			if (s[0] == path && (f.length == 0 || FreeplayCategory.normalizeFolderName(f) == normFolder))
				list.splice(i, 1);
			i--;
		}
	}

	private function weekFileName(meta:SongMetadata):String
	{
		if (meta.week >= 0 && meta.week < WeekData.weeksList.length)
			return WeekData.weeksList[meta.week];
		return '';
	}

	private function weekDisplayName(meta:SongMetadata):String
	{
		var key:String = weekFileName(meta);
		if (key.length == 0)
			return '';
		var week:WeekData = WeekData.weeksLoaded.get(key);
		return (week != null && week.weekName != null) ? week.weekName : '';
	}

	// ==================== 颜色 ====================

	private function pickColor(color:Int):Void
	{
		var cat:FreeplayCategory = currentCat();
		if (cat == null)
			return;
		cat.color = color;
		updateSwatches();
	}

	private function updateSwatches():Void
	{
		var cat:FreeplayCategory = currentCat();
		var c:Int = (cat == null) ? 0 : cat.color;
		for (i in 0...swatches.length)
			swatches[i].styleString = swatchStyle(PRESET_COLORS[i], PRESET_COLORS[i] == c);
	}

	private static function swatchStyle(color:Int, selected:Bool):String
	{
		var hex:String = FreeplayCategory.colorToHex(color == 0 ? 0xFFFFD800 : color);
		return 'background-color: $hex; border-size: ${selected ? 2 : 1}px; border-color: ${selected ? '#FFFFFF' : '#333340'};';
	}

	// ==================== 保存 ====================

	private function save():Void
	{
		// 选择弹窗还没关，忽略重复点击
		if (targetPanel != null)
			return;

		commitAll();
		if (sel >= 0 && sel < cats.length && catItems.length == cats.length)
			catItems[sel].text = catLabelText(cats[sel]);

		var edited:Array<FreeplayCategory> = [];
		for (c in cats)
		{
			if (!originalSigs.exists(c.id) || originalSigs.get(c.id) != signature(c))
				edited.push(c);
		}

		// 只调整了顺序（没改内容）也要写盘，让 Freeplay 的 Tab 顺序跟着变
		var orderChanged:Bool = orderSignature() != originalOrderSig;
		var order:Array<FreeplayCategory> = orderChanged ? cats : null;

		if (edited.length == 0 && removedIds.length == 0 && !orderChanged)
		{
			if (onClose != null)
				onClose();
			return;
		}

		// 有本次新建的分区时，先弹窗让玩家选写到全局还是某个模组；
		// 只改已有分区则不需要选（会原地写回原文件）
		var hasNew:Bool = false;
		for (c in edited)
		{
			if (c.sourceFile == null || c.sourceFile.length == 0)
			{
				hasNew = true;
				break;
			}
		}
		if (hasNew)
		{
			askNewTarget(function(target:String) doSave(edited, target, order));
			return;
		}
		doSave(edited, null, order);
	}

	private function doSave(edited:Array<FreeplayCategory>, newCatTarget:String, order:Array<FreeplayCategory>):Void
	{
		FreeplayCategory.saveAll(edited, removedIds, newCatTarget, order);
		if (onSaved != null)
			onSaved();
	}

	/**
	 * 新建分区的保存目标选择弹窗。
	 *
	 * 全局配置（mods/freeplay_categories.json）和每个模组自带的
	 * mods/<模组>/freeplay_categories.json 都可选；选模组时分类就跟着模组走，
	 * 整个模组目录可以直接打包分享。
	 */
	private function askNewTarget(onPick:String->Void):Void
	{
		if (targetPanel != null)
			return;
		blurFields();

		var globalPath:String = Paths.mods('freeplay_categories.json');
		var targets:Array<{ path:String, label:String }> = [];
		targets.push({
			path: globalPath,
			label: OptionsLanguage.get('freeplay_cat_editor_target_global', 'Global') + '  ' + relativeModPath(globalPath)
		});
		for (mod in FreeplayCategory.orderedModDirectories())
		{
			var path:String = Paths.mods(mod + '/freeplay_categories.json');
			var exists:Bool = false;
			for (t in targets)
				if (t.path == path)
					exists = true;
			if (exists)
				continue;
			targets.push({
				path: path,
				label: OptionsLanguage.get('freeplay_cat_editor_target_mod', 'Mod') + '  ' + mod + '/freeplay_categories.json'
			});
		}

		var panelW:Float = Math.min(520, FlxG.width - 80);
		var rowH:Float = 36;
		var maxListH:Float = Math.max(rowH, FlxG.height - 60 - 108);
		var listH:Float = Math.min(targets.length * (rowH + 6), maxListH);
		if (listH < rowH)
			listH = rowH;
		var panelH:Float = 108 + listH;

		targetDim = new Box();
		targetDim.x = 0;
		targetDim.y = 0;
		targetDim.width = FlxG.width;
		targetDim.height = FlxG.height;
		targetDim.styleString = 'background-color: #000000; background-opacity: 0.7;';
		// 点遮罩不关闭弹窗：必须明确选择目标或点取消，避免误触丢掉没保存的改动
		targetDim.registerEvent(MouseEvent.CLICK, function(_) {});

		targetPanel = new VBox();
		targetPanel.addClass('fpce');
		targetPanel.width = panelW;
		targetPanel.height = panelH;
		targetPanel.x = Std.int((FlxG.width - panelW) / 2);
		targetPanel.y = Std.int((FlxG.height - panelH) / 2);
		targetPanel.styleString = 'padding: 14px; vertical-spacing: 10px; background-color: #0C0C12; '
			+ 'background-opacity: 0.98; border-color: #FFD800; border-size: 2px;';

		var title:Label = makeLabel(OptionsLanguage.get('freeplay_cat_editor_target_title', 'Save new categories to'), FONT_SIZE, '#FFD800');
		title.width = panelW - 28;
		title.height = 26;

		var list:ScrollView = new ScrollView();
		list.width = panelW - 28;
		list.height = listH;
		list.styleString = 'background-color: #101018; border-color: #3A3A4A; border-size: 1px;';
		// 复用曲目列表的加宽滚动条样式（16px），触屏更容易拖
		list.addClass('fpc-songview');
		list.scrollMode = ScrollMode.INERTIAL;

		var listBox:VBox = new VBox();
		// 预留滚动条宽度，避免横向滚动
		listBox.width = list.width - 24;
		listBox.styleString = 'padding: 0; vertical-spacing: 6px;';
		for (t in targets)
		{
			var target:String = t.path;
			var btn:Button = makeButton(t.label, listBox.width, rowH, function() {
				closeTargetPicker();
				onPick(target);
			});
			btn.tooltip = relativeModPath(t.path);
			listBox.addComponent(btn);
		}
		list.addComponent(listBox);

		var bottom:HBox = new HBox();
		bottom.width = panelW - 28;
		bottom.height = 34;
		bottom.styleString = 'padding: 0; horizontal-spacing: 8px;';
		var spacer:Box = new Box();
		spacer.width = Math.max(0, bottom.width - 110);
		spacer.height = 1;
		var cancelBtn:Button = makeButton(OptionsLanguage.get('freeplay_cat_editor_cancel', 'Cancel'), 110, 32, closeTargetPicker);
		bottom.addComponent(spacer);
		bottom.addComponent(cancelBtn);

		targetPanel.addComponent(title);
		targetPanel.addComponent(list);
		targetPanel.addComponent(bottom);

		Screen.instance.addComponent(targetDim);
		Screen.instance.addComponent(targetPanel);
	}

	private function closeTargetPicker():Void
	{
		clearToolTips();
		if (targetPanel != null)
		{
			Screen.instance.removeComponent(targetPanel, true);
			targetPanel = null;
		}
		if (targetDim != null)
		{
			Screen.instance.removeComponent(targetDim, true);
			targetDim = null;
		}
	}

	/** BACK 键：目标选择弹窗打开时只关弹窗（返回 true 表示已处理，编辑器本身不关闭）。 */
	public function cancelTargetPicker():Bool
	{
		if (targetPanel == null)
			return false;
		closeTargetPicker();
		return true;
	}

	private function close():Void
	{
		if (onClose != null)
			onClose();
	}

	/**
	 * 销毁界面前清掉 tooltip 的悬停状态与待触发定时器。
	 *
	 * haxe.ui 的 ToolTipManager 是鼠标悬停 500ms 后才真正弹 tooltip（延迟由 TimerImpl 驱动）。
	 * 如果组件在这段时间里被销毁（例如点「全局」保存目标按钮后弹窗和编辑器一起被移除），
	 * 定时器仍会到点触发，而此时该组件的 tooltip 配置已随组件销毁被移除，
	 * 内部取到 null 再访问字段就会空引用崩溃（ToolTipManager.showToolTipForComponent line 279）。
	 * 销毁前主动取消当前悬停与定时器可以根治。
	 */
	private static function clearToolTips():Void
	{
		// stopCurrent 是 private：它负责停掉定时器、清空当前悬停组件并注销相关鼠标事件
		@:privateAccess ToolTipManager.instance.stopCurrent();
		ToolTipManager.instance.hideCurrentToolTip();
	}

	/** 当前分区顺序（id 序列），用于判断是否只改了排序。 */
	private function orderSignature():String
	{
		var ids:Array<String> = [];
		for (c in cats)
			ids.push((c == null) ? '' : c.id);
		return ids.join('|');
	}

	private static function signature(c:FreeplayCategory):String
	{
		return c.id + '|' + c.name + '|' + c.color + '|' + c.folders.join(',') + '|' + c.weeks.join(',')
			+ '|' + songSig(c.songs) + '|' + songSig(c.exclude);
	}

	private static function songSig(list:Array<Array<String>>):String
	{
		var out:String = '';
		for (s in list)
			out += s[0] + ':' + ((s[1] == null) ? '' : s[1]) + ';';
		return out;
	}

	// ==================== 通用控件 ====================

	private function makeLabel(text:String, size:Int, color:String):Label
	{
		var l:Label = new Label();
		l.text = text;
		l.styleString = 'font-name: $font; font-size: ${size}px; color: $color;';
		return l;
	}

	private function makeButton(text:String, w:Float, h:Float, fn:Void->Void):Button
	{
		var b:Button = new Button();
		b.text = text;
		b.width = w;
		b.height = h;
		b.allowFocus = false;
		b.styleString = 'font-name: $font; font-size: ${FONT_SIZE}px;';
		b.registerEvent(MouseEvent.CLICK, function(_) fn());
		return b;
	}
}
