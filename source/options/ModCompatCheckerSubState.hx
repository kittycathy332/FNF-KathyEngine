package options;

import flixel.text.FlxText;
import flixel.util.FlxColor;
import flixel.util.FlxTimer;
import psychlua.compat.ModCompatScanner;
import psychlua.compat.ModCompatScanner.CompatReport;
import psychlua.compat.ModCompatScanner.CompatFinding;

/**
 * 模组兼容性检测界面。
 *
 * 两个模式：
 *   - 模组列表：选择要检测的模组（来自 mods/ 目录）
 *   - 报告：列出该模组脚本里「在 Kathy / Psych 1.0.4 / Psych Legacy 下不兼容或存疑」的
 *     函数调用与回调钩子
 *
 * 操作：
 *   上/下 选择或滚动，确定 进入/深度重扫，返回 退出/回到列表
 *
 * 检测结果来自静态扫描（必要时叠加运行探针），仅供参考。
 */
class ModCompatCheckerSubState extends MusicBeatSubstate
{
	static final MODE_LIST:Int = 0;
	static final MODE_REPORT:Int = 1;

	/** 次要文字用的浅灰（flixel 5.9 的 FlxColor 没有 LIGHT_GRAY） */
	static final COL_DIM:Int = 0xFFC8C8C8;

	var bg:FlxSprite;
	var titleText:FlxText;
	var hintText:FlxText;
	var summaryText:FlxText;
	var leInfoText:FlxText; // Leather Engine 模组识别行（青色）
	var emptyText:FlxText;

	var mode:Int = MODE_LIST;

	// 列表模式
	var mods:Array<String> = [];
	var selected:Int = 0;

	// 报告模式
	var report:CompatReport = null;
	var deepMode:Bool = false;
	var scanning:Bool = false;

	// 统一的「行」容器
	var rows:Array<FlxText> = [];
	var rowHeights:Array<Float> = [];
	var scroll:Float = 0;
	var maxScroll:Float = 0;

	var viewTop:Float = 150;
	var viewBottom:Float = 600;

	// unifont 覆盖中/日/韩等宽字符，报告的说明文案含中文，vcr.ttf 会缺字形
	var fontPath:String = 'unifont-18.0.01.otf';

	public function new()
	{
		super();

		bg = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, FlxColor.BLACK);
		bg.alpha = 0.85;
		bg.scrollFactor.set();
		add(bg);

		viewTop = 150;
		viewBottom = FlxG.height - 110;

		// fieldWidth=0 → 自动宽度、不折行（折行会压到下面的汇总行）；过长由 updateTitle 缩放
		titleText = new FlxText(40, 40, 0, OptionsLanguage.get('mod_compat_checker', 'Mod Compatibility Checker'), 40);
		titleText.setFormat(Paths.font(fontPath), 40, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		titleText.borderSize = 2;
		titleText.scrollFactor.set();
		add(titleText);

		summaryText = new FlxText(40, 96, FlxG.width - 80, '', 24);
		summaryText.setFormat(Paths.font(fontPath), 24, COL_DIM, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		summaryText.borderSize = 2;
		summaryText.scrollFactor.set();
		add(summaryText);

		// Leather Engine 模组识别行（青色）：报告模式显示 LE 类型 + 当前脚本 API 运行时
		leInfoText = new FlxText(40, 0, FlxG.width - 80, '', 20);
		leInfoText.setFormat(Paths.font(fontPath), 20, 0xFF67E8F9, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		leInfoText.borderSize = 1.6;
		leInfoText.scrollFactor.set();
		leInfoText.visible = false;
		add(leInfoText);

		emptyText = new FlxText(60, viewTop + 40, FlxG.width - 120, '', 28);
		emptyText.setFormat(Paths.font(fontPath), 28, FlxColor.GRAY, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		emptyText.scrollFactor.set();
		emptyText.visible = false;
		add(emptyText);

		hintText = new FlxText(40, FlxG.height - 76, FlxG.width - 80, '', 20);
		hintText.setFormat(Paths.font(fontPath), 20, COL_DIM, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		hintText.borderSize = 2;
		hintText.scrollFactor.set();
		add(hintText);

		enterListMode();

		addTouchPad('UP_DOWN', 'A_B');
		addTouchPadCamera();
	}

	// ------------------------------------------------------------------ 模式切换

	function enterListMode():Void
	{
		mode = MODE_LIST;
		mods = ModCompatScanner.listMods();
		report = null;
		selected = 0;
		scroll = 0;
		leInfoText.visible = false; // 回到列表时隐藏 LE 识别行
		clearRows();

		if (mods.length == 0)
		{
			emptyText.text = OptionsLanguage.get('mod_compat_no_mods', 'No mods found in the mods/ folder.');
			emptyText.visible = true;
		}
		else
		{
			emptyText.visible = false;
			for (i in 0...mods.length)
			{
				// 模组名后加 LE 引擎徽章（青色高亮）；非 LE 模组保持白字
				var lt:Int = ModCompatScanner.detectLeather(mods[i]);
				var badge:String = ModCompatScanner.leatherTypeName(lt);
				var rowText:String = (badge != '') ? mods[i] + '   [' + badge + ']' : mods[i];
				var rowColor:Int = (lt != ModCompatScanner.LE_NONE) ? 0xFF67E8F9 : FlxColor.WHITE;
				addRow(rowText, rowColor, 28, 10);
			}
		}
		updateTitle(OptionsLanguage.get('mod_compat_checker', 'Mod Compatibility Checker'));
		summaryText.text = OptionsLanguage.get('mod_compat_pick_hint', 'Pick a mod to scan its .lua / .hx scripts.');
		hintText.text = OptionsLanguage.get('mod_compat_hint_list', '[Up/Down] Select    [Accept] Scan    [Back] Exit');
		layoutRows();
	}

	function enterReportMode():Void
	{
		mode = MODE_REPORT;
		scroll = 0;
		clearRows();
		emptyText.visible = false;
		updateTitle(OptionsLanguage.get('mod_compat_report_title', 'Compatibility Report') + ': ' + report.mod);

		var sevError:Int = 0;
		var sevWarn:Int = 0;
		for (f in report.findings)
		{
			if (f.severity >= ModCompatScanner.SEV_ERROR) sevError++;
			else if (f.severity >= ModCompatScanner.SEV_WARN) sevWarn++;
		}

		summaryText.text = OptionsLanguage.get('mod_compat_summary', 'Scanned')
			+ ': '
			+ report.scannedFiles
			+ ' file(s) [lua: ' + report.luaFiles + ', hx: ' + report.hxFiles + ']  |  '
			+ OptionsLanguage.get('mod_compat_incompatible', 'Incompatible') + ': ' + sevError + '   '
			+ OptionsLanguage.get('mod_compat_warning', 'Warning') + ': ' + sevWarn
			+ '   API: ' + report.knownNames;

		// LE / 脚本运行时识别行：显示模组类型 + 当前 leatherScriptCompat 下的脚本路由
		var lt:Int = ModCompatScanner.detectLeather(report.mod);
		var compat:String = backend.ClientPrefs.data.leatherScriptCompat;
		if (compat == null || compat.length == 0) compat = 'auto';
		var prefix:String = (lt != ModCompatScanner.LE_NONE)
			? 'Leather Engine mod [' + ModCompatScanner.leatherTypeName(lt) + ']  ->  '
			: 'Psych-family mod  ->  ';
		if (compat == 'off')
		{
			// 全部走 Psych API：LE 模组也值得提示（其脚本可能依赖 LE API）
			if (lt != ModCompatScanner.LE_NONE)
			{
				leInfoText.text = prefix + 'leatherScriptCompat = off：全部脚本按 Psych API 加载，LE API 写法将报「函数不存在」';
				leInfoText.color = 0xFFFFD166;
				leInfoText.visible = true;
			}
			else
				leInfoText.visible = false;
		}
		else if (compat == 'official' || compat == 'lts')
		{
			leInfoText.text = prefix + 'leatherScriptCompat = ' + compat + '：全部脚本强制走 LE API 运行时';
			leInfoText.color = 0xFF67E8F9;
			leInfoText.visible = true;
		}
		else
		{
			leInfoText.text = prefix + 'leatherScriptCompat = auto：按脚本内容自动分流（LE API 脚本 → LE 运行时，Psych API 脚本 → Psych 运行时，同一模组可并存）';
			leInfoText.color = 0xFF67E8F9;
			leInfoText.visible = true;
		}
		if (leInfoText.visible)
		{
			leInfoText.y = summaryText.y + summaryText.textField.textHeight + 4 + summaryText.borderSize * 2 + 2;
		}

		if (report.findings.length == 0)
		{
			emptyText.text = OptionsLanguage.get('mod_compat_all_ok', 'No compatibility issues found. Looks fine!');
			emptyText.visible = true;
		}
		else
		{
			var shown:Int = 0;
			var limit:Int = 60;
			for (f in report.findings)
			{
				if (shown >= limit)
				{
					addRow('... +' + (report.findings.length - limit) + ' more', FlxColor.GRAY, 24, 8);
					break;
				}
				shown++;

				var color:Int = f.severity >= ModCompatScanner.SEV_ERROR ? FlxColor.RED
					: (f.severity >= ModCompatScanner.SEV_WARN ? FlxColor.YELLOW : COL_DIM);
				var tag:String = f.severity >= ModCompatScanner.SEV_ERROR ? '[X]'
					: (f.severity >= ModCompatScanner.SEV_WARN ? '[!]' : '[i]');
				var kind:String = f.isHook ? 'hook' : 'func';
				addRow(tag + ' ' + f.name + '  (' + kind + ')', color, 26, 2);

				var verStr:String = f.versions.length > 0 ? f.versions.join('/') : '-';
				var fileStr:String = f.files != null && f.files.length > 0 ? f.files.join(', ') : '';
				if (fileStr.length > 90) fileStr = fileStr.substr(0, 87) + '...';
				addRow('    -> ' + f.note + '   [' + verStr + ']' + (fileStr != '' ? '  @ ' + fileStr : ''), FlxColor.GRAY, 20, 16);
			}
		}

		hintText.text = OptionsLanguage.get('mod_compat_hint_report', '[Up/Down] Scroll   [Accept] Deep re-scan   [Back] Back to list');
		layoutRows();

		if (report.errors.length > 0 && report.findings.length == 0)
			emptyText.text += '\n(' + report.errors.length + ' file(s) could not be read)';
	}

	// ------------------------------------------------------------------ 行构建/布局

	function clearRows():Void
	{
		for (r in rows)
		{
			remove(r);
			r.destroy();
		}
		rows = [];
		rowHeights = [];
		scroll = 0;
		maxScroll = 0;
	}

	/**
	 * 添加一行文本。
	 * @param gapAfter 该行之后额外留出的空白（用于拉开分组间距）
	 * 行高不再写死：FlxText 在 fieldWidth>0 时会强制 wordWrap，长文本会折行，
	 * 所以这里用 textField.textHeight 取「折行后的真实高度」，避免行与行重叠。
	 */
	function addRow(text:String, color:Int, size:Int, gapAfter:Float = 6):Void
	{
		var t:FlxText = new FlxText(60, 0, FlxG.width - 120, text, size);
		t.setFormat(Paths.font(fontPath), size, color, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		t.borderSize = 1.6;
		t.scrollFactor.set();
		add(t);
		rows.push(t);

		// 真实渲染高度 = 文字高度 + VERTICAL_GUTTER(4) + 描边上下各 borderSize
		var h:Float = t.textField.textHeight + 4 + t.borderSize * 2;
		rowHeights.push(h + gapAfter);
	}

	/** 依据 scroll 重新摆放每一行（只显示视口内的） */
	function layoutRows():Void
	{
		// 汇总行/标题若折行会变高，视口顶部据此下移，避免压住第一行
		viewBottom = FlxG.height - 110;
		var baseY:Float = summaryText.y + summaryText.textField.textHeight + 4 + summaryText.borderSize * 2;
		// LE 识别行可见时把视口再往下推一行
		if (leInfoText.visible)
			baseY += leInfoText.textField.textHeight + 4 + leInfoText.borderSize * 2 + 4;
		viewTop = baseY + 10;
		emptyText.y = viewTop + 24;

		var y:Float = viewTop - scroll;
		for (i in 0...rows.length)
		{
			var r:FlxText = rows[i];
			var h:Float = rowHeights[i];
			r.x = 60;
			r.y = y;
			r.visible = (y + h > viewTop) && (y < viewBottom);
			y += h;
		}

		var total:Float = 0;
		for (h in rowHeights) total += h;
		maxScroll = Math.max(0, total - (viewBottom - viewTop));
		if (scroll > maxScroll) scroll = maxScroll;
		if (scroll < 0) scroll = 0;
	}

	function updateTitle(t:String):Void
	{
		titleText.text = t;
		titleText.updateHitbox(); // autoSize 下先重算尺寸，width 才是实时文本宽度
		var tw:Float = titleText.width;
		var maxW:Float = FlxG.width - 80;
		var scale:Float = (tw > maxW && tw > 0) ? maxW / tw : 1;
		titleText.scale.set(scale, scale);
	}

	// ------------------------------------------------------------------ 更新

	override function update(elapsed:Float):Void
	{
		if (mode == MODE_LIST) updateListMode();
		else updateReportMode();

		if (touchPad == null)
		{
			addTouchPad('UP_DOWN', 'A_B');
			addTouchPadCamera();
		}
		super.update(elapsed);
	}

	function updateListMode():Void
	{
		if (mods.length == 0)
		{
			if (controls.BACK) close();
			return;
		}

		var prev:Int = selected;
		if (controls.UI_UP_P) selected--;
		if (controls.UI_DOWN_P) selected++;
		if (selected < 0) selected = mods.length - 1;
		if (selected >= mods.length) selected = 0;
		if (selected != prev) FlxG.sound.play(Paths.sound('scrollMenu'));

		// 高亮
		for (i in 0...rows.length)
		{
			var r:FlxText = rows[i];
			var on:Bool = (i == selected);
			r.color = on ? FlxColor.WHITE : COL_DIM;
			r.alpha = on ? 1 : 0.65;
		}
		ensureVisible(selected);

		if (controls.BACK)
		{
			FlxG.sound.play(Paths.sound('cancelMenu'));
			close();
			return;
		}
		if (controls.ACCEPT)
		{
			FlxG.sound.play(Paths.sound('confirmMenu'));
			startScan(false);
		}
	}

	function updateReportMode():Void
	{
		if (controls.UI_UP) scroll -= 900 * FlxG.elapsed;
		if (controls.UI_DOWN) scroll += 900 * FlxG.elapsed;
		if (scroll < 0) scroll = 0;
		if (scroll > maxScroll) scroll = maxScroll;
		layoutRows();

		if (controls.BACK)
		{
			FlxG.sound.play(Paths.sound('cancelMenu'));
			enterListMode();
			return;
		}
		if (controls.ACCEPT && !scanning)
		{
			FlxG.sound.play(Paths.sound('confirmMenu'));
			startScan(true);
		}
	}

	/** 用一帧把「扫描中…」渲染出来后再做同步扫描 */
	function startScan(deep:Bool):Void
	{
		deepMode = deep;
		scanning = true;
		summaryText.text = deep
			? OptionsLanguage.get('mod_compat_scanning_deep', 'Deep scanning (running probe)...')
			: OptionsLanguage.get('mod_compat_scanning', 'Scanning...');

		var modName:String = mods[selected];
		new FlxTimer().start(0.05, function(_:FlxTimer)
		{
			report = ModCompatScanner.scan(modName, deep);
			scanning = false;
			enterReportMode();
		});
	}

	/** 让选中的行保持可见（列表模式的滚动） */
	function ensureVisible(index:Int):Void
	{
		var top:Float = 0;
		for (i in 0...index) top += rowHeights[i];
		var bottom:Float = top + rowHeights[index];
		var viewH:Float = viewBottom - viewTop;

		if (top < scroll) scroll = top;
		else if (bottom > scroll + viewH) scroll = bottom - viewH;
		if (scroll < 0) scroll = 0;
		layoutRows();
	}
}
