package backend.ui;

import backend.FreeplayCategory;
import backend.SongMetadata;
import backend.WeekData;
import haxe.ui.Toolkit;
import haxe.ui.components.Button;
import haxe.ui.components.CheckBox;
import haxe.ui.components.Label;
import haxe.ui.components.TextField;
import haxe.ui.containers.Absolute;
import haxe.ui.containers.Box;
import haxe.ui.containers.HBox;
import haxe.ui.containers.ScrollView;
import haxe.ui.containers.VBox;
import haxe.ui.core.Screen;
import haxe.ui.events.MouseEvent;
import haxe.ui.events.UIEvent;

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
	private static inline var ROW_H:Float = 22;
	/** 虚拟列表最多创建多少个行控件（按可见高度决定，另有上限防极端分辨率） */
	private static inline var ROW_POOL_MAX:Int = 60;
	/** 每次重新绑定覆盖的行数：多留一页余量，滚动时只在跨页时才重绑，减少文字重排与 GC */
	private static inline var ROW_PAGE:Int = 16;

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
	private var sel:Int = -1;

	private var font:String;
	private var dim:Box = null;
	private var root:HBox = null;
	private var catBox:VBox = null;
	private var catItems:Array<Label> = [];
	private var nameField:TextField = null;
	private var searchField:TextField = null;
	private var songScroll:ScrollView = null;
	private var songContent:Absolute = null;
	private var rowPool:Array<CheckBox> = [];
	private var rowSongIndex:Array<Int> = [];
	private var membership:Array<Bool> = [];
	private var filtered:Array<Int> = [];
	private var firstRow:Int = -999;
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

		var title:Label = makeLabel(OptionsLanguage.get('freeplay_cat_editor_title', 'CATEGORY EDITOR'), 18, '#FFD800');
		title.width = LEFT_W;
		title.height = 26;

		var catScroll:ScrollView = new ScrollView();
		catScroll.width = LEFT_W;
		catScroll.height = Std.int(innerH - 26 - 34 - 16);
		// 直接写死在组件上：即使主题样式未命中也不会出现白底列表
		catScroll.styleString = 'background-color: #101018; border-color: #3A3A4A; border-size: 1px;';

		catBox = new VBox();
		catBox.width = LEFT_W - 18;
		catBox.styleString = 'padding: 0; vertical-spacing: 3px;';
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
		var nameLbl:Label = makeLabel(OptionsLanguage.get('freeplay_cat_editor_name', 'Name'), 15, '#9C9CAA');
		nameLbl.width = labelW;
		nameField = new TextField();
		nameField.width = fieldW;
		nameField.height = 26;
		nameField.maxChars = 48;
		nameField.allowFocus = true;
		nameField.styleString = 'font-name: $font; font-size: 15px; padding: 3px 6px;';
		nameRow.addComponent(nameLbl);
		nameRow.addComponent(nameField);

		// 颜色
		var colorRow:HBox = new HBox();
		colorRow.width = rightW;
		colorRow.height = 30;
		colorRow.styleString = 'padding: 0; horizontal-spacing: 8px; vertical-align: center;';
		var colorLbl:Label = makeLabel(OptionsLanguage.get('freeplay_cat_editor_color', 'Color'), 15, '#9C9CAA');
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
		var searchLbl:Label = makeLabel(OptionsLanguage.get('freeplay_cat_editor_search_label', 'Search'), 15, '#9C9CAA');
		searchLbl.width = labelW;
		searchField = new TextField();
		searchField.width = fieldW;
		searchField.height = 26;
		searchField.maxChars = 40;
		searchField.styleString = 'font-name: $font; font-size: 15px; padding: 3px 6px;';
		searchField.registerEvent(UIEvent.CHANGE, function(_) applySongFilter());
		searchField.registerEvent(UIEvent.SUBMIT, function(_) searchField.focus = false);
		searchRow.addComponent(searchLbl);
		searchRow.addComponent(searchField);

		// 曲目列表（虚拟滚动：只创建可见窗口内的行，1000+ 首也不会卡）
		songScroll = new ScrollView();
		songScroll.width = rightW;
		songScroll.height = Std.int(Math.max(80, innerH - 30 * 3 - 34 - 8 * 4));
		songScroll.styleString = 'background-color: #101018; border-color: #3A3A4A; border-size: 1px;';
		songRowW = rightW - 18;
		songContent = new Absolute();
		songContent.width = songRowW;
		songContent.height = ROW_H;
		songScroll.addComponent(songContent);

		var poolSize:Int = Std.int(Math.ceil(songScroll.height / ROW_H)) + 2 + ROW_PAGE;
		poolSize = Std.int(Math.min(ROW_POOL_MAX, Math.max(ROW_PAGE + 8, poolSize)));
		for (i in 0...poolSize)
		{
			var row:CheckBox = new CheckBox();
			row.width = songRowW;
			row.height = ROW_H;
			row.left = 0;
			row.top = 0;
			row.allowFocus = false;
			row.hidden = true;
			row.styleString = 'font-name: $font; font-size: 14px; color: #DDDDDD;';
			songContent.addComponent(row);
			rowPool.push(row);
			rowSongIndex.push(-1);
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
		right.addComponent(colorRow);
		right.addComponent(searchRow);
		right.addComponent(songScroll);
		right.addComponent(bottom);

		root.addComponent(left);
		root.addComponent(right);

		Screen.instance.addComponent(dim);
		Screen.instance.addComponent(root);

		selectCategory(cats.length > 0 ? 0 : -1);
	}

	/** 移除所有组件（关闭编辑器时调用）。 */
	public function destroy():Void
	{
		blurFields();
		if (root != null)
		{
			Screen.instance.removeComponent(root);
			root = null;
		}
		if (dim != null)
		{
			Screen.instance.removeComponent(dim);
			dim = null;
		}
		catItems = [];
		rowPool = [];
		rowSongIndex = [];
		membership = [];
		filtered = [];
		swatches = [];
		catBox = null;
		songScroll = null;
		songContent = null;
		nameField = null;
		searchField = null;
		deleteBtn = null;
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
		for (i in 0...cats.length)
		{
			var idx:Int = i;
			var cat:FreeplayCategory = cats[i];
			var item:Label = new Label();
			item.text = catLabelText(cat);
			item.width = catBox.width;
			item.height = 30;
			item.styleString = 'font-name: $font; font-size: 15px; padding: 4px 8px; '
				+ ((idx == sel) ? 'background-color: #FFD800; color: #0C0C12;' : 'color: #C8C8D0;');
			item.registerEvent(MouseEvent.CLICK, function(_) {
				if (idx != sel)
					selectCategory(idx);
			});
			catBox.addComponent(item);
			catItems.push(item);
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
		if (songContent == null)
			return;
		syncRowStates();
		bindRows();
	}

	/** 重建当前分区的勾选状态与列表内容（切换分区 / 打开面板时调用）。 */
	private function resetSongView():Void
	{
		firstRow = -999;
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

	/** 只重绑可见窗口内的行（滚动位置变化时才真正重新绑定）。 */
	private function bindRows():Void
	{
		if (songContent == null)
			return;

		var scrollY:Float = (songScroll == null) ? 0 : songScroll.vscrollPos;
		if (Math.isNaN(scrollY) || scrollY < 0)
			scrollY = 0;
		var first:Int = Std.int(scrollY / ROW_H);
		if (filtered.length > 0 && first > filtered.length - 1)
			first = filtered.length - 1;
		// 按“页”对齐：滚动不超过 ROW_PAGE 行时完全不需要重绑（减少文字重排与 GC）
		var pageFirst:Int = Std.int(first / ROW_PAGE) * ROW_PAGE;
		if (pageFirst == firstRow)
			return;
		firstRow = pageFirst;

		for (slot in 0...rowPool.length)
		{
			var idx:Int = pageFirst + slot;
			var row:CheckBox = rowPool[slot];
			if (idx >= filtered.length)
			{
				rowSongIndex[slot] = -1;
				row.hidden = true;
				continue;
			}

			var songIdx:Int = filtered[idx];
			rowSongIndex[slot] = songIdx;
			row.hidden = false;
			row.top = idx * ROW_H;

			var meta:SongMetadata = songs[songIdx];
			var folder:String = (meta.folder == null) ? '' : meta.folder;
			row.text = (folder.length > 0) ? meta.songName + '  [' + folder + ']' : meta.songName;
			row.selected = (songIdx < membership.length) ? membership[songIdx] : false;
		}
	}

	/** 记录用户在当前可见行上的勾选变化（滚出视野前必须先把状态回写）。 */
	private function syncRowStates():Void
	{
		for (slot in 0...rowPool.length)
		{
			var idx:Int = rowSongIndex[slot];
			if (idx < 0 || idx >= membership.length)
				continue;
			membership[idx] = rowPool[slot].selected;
		}
	}

	private function applySongFilter():Void
	{
		syncRowStates();
		firstRow = -999;
		if (songScroll != null)
			songScroll.vscrollPos = 0;
		recomputeFilter();
		applyContentHeight();
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
		commitAll();
		if (sel >= 0 && sel < cats.length && catItems.length == cats.length)
			catItems[sel].text = catLabelText(cats[sel]);

		var edited:Array<FreeplayCategory> = [];
		for (c in cats)
		{
			if (!originalSigs.exists(c.id) || originalSigs.get(c.id) != signature(c))
				edited.push(c);
		}

		if (edited.length == 0 && removedIds.length == 0)
		{
			if (onClose != null)
				onClose();
			return;
		}

		FreeplayCategory.saveAll(edited, removedIds);
		if (onSaved != null)
			onSaved();
	}

	private function close():Void
	{
		if (onClose != null)
			onClose();
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
		b.styleString = 'font-name: $font; font-size: 15px;';
		b.registerEvent(MouseEvent.CLICK, function(_) fn());
		return b;
	}
}
