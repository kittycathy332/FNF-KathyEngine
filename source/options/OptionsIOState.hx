package options;

import backend.ClientPrefs;
import backend.ExportConfig;
import backend.ImportResult;
import backend.Language;
import backend.Paths;
import backend.MusicBeatState;
import flixel.FlxG;
import flixel.FlxObject;
import flixel.FlxSprite;
import flixel.group.FlxGroup;
import flixel.text.FlxText;
import flixel.tweens.FlxTween;
import flixel.tweens.FlxEase;
import flixel.ui.FlxButton;
import flixel.util.FlxTimer;
import lime.system.Clipboard;
import openfl.events.MouseEvent;
import openfl.events.KeyboardEvent;
import openfl.ui.Keyboard;
import sys.FileSystem;
import sys.io.File;
#if desktop
import states.editors.content.FileDialogHandler;
import flash.net.FileFilter;
#end

/**
 * 设置导入导出子界面。纯 Flixel，零 openfl 依赖。
 */
class OptionsIOState extends MusicBeatState
{
	static var PAD_X:Float = 60;
	static var PAD_TOP:Float = 60;
	static var TAB_H:Float = 44;

	var curTab:String = 'export';
	var exportConfig:ExportConfig = new ExportConfig();
	var exportResultText:String = '';
	var exportFormatIdx:Int = 0;
	var importRawText:String = '';
	var importPreview:ImportResult = null;
	var importParsedObj:Dynamic = null;
	var importSectionsEnabled:Map<String, Bool> = [];
	var gameClipboard:String = '';
	var antialias:Bool = true;

	var bg:FlxSprite;
	var headerText:FlxText;
	var tabExportBtn:FlxButton;
	var tabImportBtn:FlxButton;
	var tabIndicator:FlxSprite;
	var contentGroup:FlxGroup;
	var hintText:FlxText;

	// 导出预览
	var exportPreviewGroup:FlxGroup;
	var exportPreviewBg:FlxSprite;
	var exportPreviewText:FlxText;
	var exportScrollY:Float = 0;
	var exportScrollMax:Float = 0;
	var exportMaskX:Float = 0;
	var exportMaskY:Float = 0;
	var exportMaskW:Int = 0;
	var exportMaskH:Int = 0;
	var exportTextBaseY:Float = 0;

	var grpExport:FlxGroup;
	var exportCheckboxes:Array<FlxButton> = [];
	var exportCbStates:Array<Bool> = [];
	var formatButtons:Array<FlxButton> = [];
	var exportBtnGenerate:FlxButton;
	var exportBtnCopy:FlxButton;
	var exportBtnSaveFile:FlxButton;
	#if desktop
	var exportBtnChoosePath:FlxButton;
	#end
	#if desktop
	var importBtnChooseFile:FlxButton;
	var _fileDlg:FileDialogHandler;
	#end

	var grpImport:FlxGroup;
	var importAreaBg:FlxSprite;
	var importPreviewText:FlxText;
	var importBtnPaste:FlxButton;
	var importBtnClear:FlxButton;
	var importBtnParse:FlxButton;
	var importParseResultText:FlxText;

	var importListGroup:FlxGroup;
	var importListBg:FlxSprite;
	var importScrollY:Float = 0;
	var importScrollMax:Float = 0;
	var importListMaskX:Float = 0;
	var importListMaskY:Float = 0;
	var importListMaskW:Int = 0;
	var importListMaskH:Int = 0;
	var importBaseYs:Array<Float> = [];

	var importBtnConfirm:FlxButton;
	var importBtnCancel:FlxButton;

	var touchStartY:Float = -1;
	var touchLastScrollY:Float = 0;
	var touchActiveScrollTarget:Int = -1;
	var confirmDialog:FlxGroup = null;

	public function new()
	{
		super();
		antialias = ClientPrefs.data.antialiasing;
	}

	override function create()
	{
		super.create();
		bg = new FlxSprite().makeGraphic(Std.int(FlxG.width), Std.int(FlxG.height), 0xE5000000);
		bg.alpha = 0.85;
		add(bg);

		headerText = new FlxText(PAD_X, 16, FlxG.width - PAD_X * 2, Language.get('settings_io_title'), 28);
		headerText.setFormat(Paths.font(Language.get('game_font')), 28, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		headerText.borderSize = 3;
		headerText.antialiasing = antialias;
		add(headerText);

		// 右上角关闭按钮
		// 右上角关闭按钮（"退出"）
		var closeBtn = new FlxButton(FlxG.width - PAD_X - 90, 10, Language.get('io_exit'), function() { backToOptions(); });
		closeBtn.width = 90; closeBtn.height = 44;
		closeBtn.makeGraphic(90, 44, 0xFF884444);
		closeBtn.label.setFormat(Paths.font(Language.get('game_font')), 22, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		closeBtn.label.borderSize = 2; closeBtn.label.antialiasing = antialias;
		add(closeBtn);

		var tabW:Float = 160;
		var tabGap:Float = 20;
		var tabStartX:Float = (FlxG.width - tabW * 2 - tabGap) / 2;
		tabExportBtn = makeTab(tabStartX, PAD_TOP, tabW, TAB_H, Language.get('io_export'), 'export', true);
		tabImportBtn = makeTab(tabStartX + tabW + tabGap, PAD_TOP, tabW, TAB_H, Language.get('io_import'), 'import', false);
		add(tabExportBtn);
		add(tabImportBtn);

		tabIndicator = new FlxSprite().makeGraphic(Std.int(tabW), 4, 0xFFFFD700);
		tabIndicator.x = tabExportBtn.x;
		tabIndicator.y = tabExportBtn.y + TAB_H + 2;
		add(tabIndicator);

		contentGroup = new FlxGroup();
		add(contentGroup);
		buildExportPanel();
		buildImportPanel();
		switchTab('export');

		hintText = new FlxText(PAD_X, FlxG.height - 30, FlxG.width - PAD_X * 2, Language.get('io_hint'), 18);
		hintText.setFormat(Paths.font(Language.get('game_font')), 18, 0xFFBBBBBB, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		hintText.borderSize = 1.5;
		hintText.antialiasing = antialias;
		add(hintText);

		addTouchPad('LEFT_FULL', 'A_B_C');
		addTouchPadCamera();
		FlxG.stage.addEventListener(MouseEvent.MOUSE_WHEEL, onGlobalWheel);
		FlxG.stage.addEventListener(KeyboardEvent.KEY_UP, onStageKeyUp);
	}

	override function destroy()
	{
		if (FlxG.stage != null) FlxG.stage.removeEventListener(MouseEvent.MOUSE_WHEEL, onGlobalWheel);
		if (FlxG.stage != null) FlxG.stage.removeEventListener(KeyboardEvent.KEY_UP, onStageKeyUp);
		super.destroy();
	}

	function onStageKeyUp(e:KeyboardEvent):Void
	{
		if (e.keyCode == Keyboard.ESCAPE)
		{
			backToOptions();
		}
	}

	function makeTab(x:Float, y:Float, w:Float, h:Float, label:String, tab:String, active:Bool):FlxButton
	{
		// 注意：必须用 tab 标识（'export'/'import'）切换，不能用 label 反查语言文本，
		// 否则切换语言后 label 与 Language.get 结果不一致会导致 tab 判定失效。
		var btn = new FlxButton(x, y, label, function() { switchTab(tab); });
		btn.width = w; btn.height = h; btn.label.text = label;
		btn.label.setFormat(Paths.font(Language.get('game_font')), 22, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		btn.label.borderSize = 2; btn.label.antialiasing = antialias;
		btn.makeGraphic(Std.int(w), Std.int(h), active ? 0xFF444444 : 0xFF222222);
		return btn;
	}

	function clamp(v:Float, lo:Float, hi:Float):Float { return Math.max(lo, Math.min(v, hi)); }
	function _refreshImportPreview():Void { if (importRawText.length == 0) { importPreviewText.text = Language.get('io_paste_here'); importPreviewText.color = 0xFF888888; } else { importPreviewText.text = importRawText; importPreviewText.color = 0xFFCCCCCC; } }

	function switchTab(tab:String):Void
	{
		// 切 tab 时关闭确认弹窗
		if (confirmDialog != null) removeConfirmDialog();
		curTab = tab;
		tabExportBtn.makeGraphic(Std.int(tabExportBtn.width), Std.int(tabExportBtn.height), tab == 'export' ? 0xFF444444 : 0xFF222222);
		tabImportBtn.makeGraphic(Std.int(tabImportBtn.width), Std.int(tabImportBtn.height), tab == 'import' ? 0xFF444444 : 0xFF222222);
		FlxTween.tween(tabIndicator, { x: (tab == 'export') ? tabExportBtn.x : tabImportBtn.x }, 0.2, { ease: FlxEase.quadOut });
		grpExport.visible = (tab == 'export');
		grpImport.visible = (tab == 'import');
	}

	function isOverRect(mx:Float, my:Float, rx:Float, ry:Float, rw:Int, rh:Int):Bool
	{ return mx >= rx && mx <= rx + rw && my >= ry && my <= ry + rh; }

	function onGlobalWheel(e:MouseEvent):Void
	{
		if (curTab == 'export' && isOverRect(FlxG.mouse.x, FlxG.mouse.y, exportMaskX, exportMaskY, exportMaskW, exportMaskH))
		{ exportScrollY = Std.int(clamp(exportScrollY + e.delta * 3, 0, exportScrollMax)); applyExportScroll(); }
		else if (curTab == 'import' && importListBg != null && importListBg.visible
			&& isOverRect(FlxG.mouse.x, FlxG.mouse.y, importListMaskX, importListMaskY, importListMaskW, importListMaskH))
		{ importScrollY = Std.int(clamp(importScrollY + e.delta * 3, 0, importScrollMax)); applyImportListScroll(); }
	}

	function buildExportPanel():Void
	{
		grpExport = new FlxGroup();
		contentGroup.add(grpExport);
		var topY:Float = PAD_TOP + TAB_H + 16;
		var leftX:Float = PAD_X;
		var colW:Float = (FlxG.width - PAD_X * 2) / 2 - 10;
		var rightX:Float = leftX + colW + 20;

		var labelSections = new FlxText(leftX, topY, colW, Language.get('io_export_sections'), 22);
		labelSections.setFormat(Paths.font(Language.get('game_font')), 22, 0xFFFFD700, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		labelSections.borderSize = 2; labelSections.antialiasing = antialias;
		grpExport.add(labelSections);

		var sectionDefs:Array<String> = ['io_sec_prefs', 'io_sec_keyboard', 'io_sec_gamepad', 'io_sec_mobile', 'io_sec_gameplay'];
		var sectionKeys:Array<String> = ['prefs', 'keyboard', 'gamepad', 'mobile', 'gameplay'];
		for (i in 0...sectionDefs.length)
		{
			var checkY = labelSections.y + 36 + i * 32;
			var cb = new FlxButton(leftX, checkY, ''); cb.width = 22; cb.height = 22; cb.label.visible = false; cb.makeGraphic(22, 22, 0xFF00AA00);
			var idx = i;
			cb.onUp.callback = function() { exportCbStates[idx] = !exportCbStates[idx]; exportCheckboxes[idx].makeGraphic(22, 22, exportCbStates[idx] ? 0xFF00AA00 : 0xFF555555); setSectionInclude(sectionKeys[idx], exportCbStates[idx]); };
			exportCheckboxes.push(cb); exportCbStates.push(true); grpExport.add(cb);
			var lbl = new FlxText(leftX + 32, checkY + 2, colW - 32, Language.get(sectionDefs[i]), 18);
			lbl.setFormat(Paths.font(Language.get('game_font')), 18, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			lbl.borderSize = 1.5; lbl.antialiasing = antialias; grpExport.add(lbl);
		}

		var labelFmt = new FlxText(rightX, topY, colW, Language.get('io_export_format'), 22);
		labelFmt.setFormat(Paths.font(Language.get('game_font')), 22, 0xFFFFD700, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		labelFmt.borderSize = 2; labelFmt.antialiasing = antialias; grpExport.add(labelFmt);
		var fmtNames:Array<String> = ['io_fmt_json', 'io_fmt_b64', 'io_fmt_zlib'];
		var fmtVals:Array<String> = ['json', 'base64', 'zlib'];
		for (i in 0...3)
		{
			var fBtn = new FlxButton(rightX, labelFmt.y + 36 + i * 48, Language.get(fmtNames[i]));
			fBtn.width = colW; fBtn.height = 34;
			fBtn.makeGraphic(Std.int(colW), 34, (i == exportFormatIdx) ? 0xFF444444 : 0xFF222222);
			fBtn.label.setFormat(Paths.font(Language.get('game_font')), 20, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			fBtn.label.borderSize = 1.5; fBtn.label.antialiasing = antialias; fBtn.label.x = 12;
			var idx = i;
			fBtn.onUp.callback = function() { exportFormatIdx = idx; for (j in 0...formatButtons.length) formatButtons[j].makeGraphic(Std.int(colW), 34, (j == idx) ? 0xFF444444 : 0xFF222222); exportConfig.format = fmtVals[idx]; };
			formatButtons.push(fBtn); grpExport.add(fBtn);
		}

		var btnY = FlxG.height - 80;
		exportMaskX = rightX; exportMaskY = topY + 220; exportMaskW = Std.int(colW); exportMaskH = Std.int(Math.max(80, btnY - exportMaskY - 6));
		exportPreviewBg = new FlxSprite().makeGraphic(exportMaskW, exportMaskH, 0xFF111111);
		exportPreviewBg.x = exportMaskX; exportPreviewBg.y = exportMaskY; exportPreviewBg.scrollFactor.set(); grpExport.add(exportPreviewBg);

		exportPreviewGroup = new FlxGroup(); grpExport.add(exportPreviewGroup);
		exportPreviewText = new FlxText(exportMaskX + 4, exportMaskY + 4, exportMaskW - 8, '', 13);
		exportPreviewText.setFormat(Paths.font("vcr.ttf"), 13, 0xFFCCCCCC, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		exportPreviewText.borderSize = 1; exportPreviewText.antialiasing = false;
		// 关键：开启 openfl TextField 原生换行 + 裁剪（wordWrap 在 Flixel 封装层无效）
		exportPreviewText.textField.multiline = true;
		exportPreviewText.textField.wordWrap = true;
		exportPreviewText.textField.selectable = false;
		exportPreviewText.textField.width = exportMaskW - 8;
		exportPreviewText.textField.height = exportMaskH - 8;
		exportTextBaseY = exportPreviewText.y;
		exportPreviewGroup.add(exportPreviewText);

		exportBtnGenerate = new FlxButton(rightX, btnY, Language.get('io_generate'), onGenerate);
		exportBtnGenerate.width = 130; exportBtnGenerate.height = 40; exportBtnGenerate.makeGraphic(130, 40, 0xFF228B22);
		exportBtnGenerate.label.setFormat(Paths.font(Language.get('game_font')), 18, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		exportBtnGenerate.label.borderSize = 2; exportBtnGenerate.label.antialiasing = antialias; grpExport.add(exportBtnGenerate);

		exportBtnCopy = new FlxButton(rightX + 140, btnY, Language.get('io_copy'), onCopy);
		exportBtnCopy.width = 130; exportBtnCopy.height = 40; exportBtnCopy.makeGraphic(130, 40, 0xFF1E90FF);
		exportBtnCopy.label.setFormat(Paths.font(Language.get('game_font')), 18, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		exportBtnCopy.label.borderSize = 2; exportBtnCopy.label.antialiasing = antialias; grpExport.add(exportBtnCopy);

		exportBtnSaveFile = new FlxButton(rightX + 280, btnY, Language.get('io_save_file'), onSaveToFile);
		exportBtnSaveFile.width = 130; exportBtnSaveFile.height = 40; exportBtnSaveFile.makeGraphic(130, 40, 0xFF9932CC);
		exportBtnSaveFile.label.setFormat(Paths.font(Language.get('game_font')), 18, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		exportBtnSaveFile.label.borderSize = 2; exportBtnSaveFile.label.antialiasing = antialias; grpExport.add(exportBtnSaveFile);

		#if desktop
		exportBtnChoosePath = new FlxButton(rightX + 420, btnY, Language.get('io_choose_path'), onChooseSavePath);
		exportBtnChoosePath.width = 130; exportBtnChoosePath.height = 40; exportBtnChoosePath.makeGraphic(130, 40, 0xFFD2691E);
		exportBtnChoosePath.label.setFormat(Paths.font(Language.get('game_font')), 16, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		exportBtnChoosePath.label.borderSize = 2; exportBtnChoosePath.label.antialiasing = antialias; grpExport.add(exportBtnChoosePath);
		#end

		// Feedback 文本改用左下角 hintText（通过 hintText.color 切换颜色）
	}

	function applyExportScroll():Void
	{
		// 用 openfl TextField 原生 scrollV 滚动（比手动改 y 更稳定，自动配合裁剪）
		if (exportPreviewText != null && exportPreviewText.textField != null)
			exportPreviewText.textField.scrollV = Std.int(exportScrollY);
	}

	function setSectionInclude(key:String, include:Bool):Void
	{
		switch (key)
		{
			case 'prefs': exportConfig.includePrefs = include;
			case 'keyboard': exportConfig.includeKeyboard = include;
			case 'gamepad': exportConfig.includeGamepad = include;
			case 'mobile': exportConfig.includeMobile = include;
			case 'gameplay': exportConfig.includeGameplay = include;
		}
	}

	function onGenerate():Void
	{
		var any = exportConfig.includePrefs || exportConfig.includeKeyboard || exportConfig.includeGamepad || exportConfig.includeMobile || exportConfig.includeGameplay;
		if (!any) { hintText.text = Language.get('io_nothing_to_export'); return; }
		var fmtVals:Array<String> = ['json', 'base64', 'zlib'];
		exportConfig.format = fmtVals[exportFormatIdx];
		exportResultText = ClientPrefs.exportSettings(exportConfig);
		exportPreviewText.text = exportResultText;
		exportScrollY = 0;
		// 用 openfl TextField 原生 textHeight 算最大滚动
		var tfH:Int = Std.int(exportPreviewText.textField != null ? exportPreviewText.textField.textHeight : 0);
		exportScrollMax = Std.int(Math.max(0, tfH - (exportMaskH - 8) + 20));
		applyExportScroll();
		hintText.color = 0xFFBBBBBB;
		hintText.text = Language.get('io_generated') + ': ' + exportResultText.length + ' ' + Language.get('io_chars');
	}

	function onCopy():Void
	{
		if (exportResultText.length == 0) { hintText.text = Language.get('io_nothing_to_copy'); return; }
		gameClipboard = exportResultText;
		try { Clipboard.text = exportResultText; hintText.color = 0xFFFFD700; hintText.text = Language.get('io_copied') + ' (' + exportResultText.length + ' ' + Language.get('io_chars') + ')'; }
		catch (e:Dynamic) { hintText.color = 0xFFFFD700; hintText.text = Language.get('io_copied') + ' (' + Language.get('io_internal_only') + ')'; }
		new FlxTimer().start(1.5, function(_) { hintText.color = 0xFFBBBBBB; hintText.text = Language.get('io_hint'); });
	}

	// ===== 文件保存 / 导入 =====

	function _getSaveRootDir():String
	{
		// 跨平台：用户数据根目录跟随「存储位置」设置
		var root:String = #if android StorageUtil.getExternalStorageDirectory() #else Sys.getCwd() + '/' #end + 'backups';
		if (!FileSystem.exists(root))
		{
			try { FileSystem.createDirectory(root); } catch (e:Dynamic) {}
		}
		return root;
	}

	function _makeTimestampedFileName(fmt:String):String
	{
		var d:Date = Date.now();
		var p = function(n:Int):String return Std.string(n).length == 1 ? '0' + Std.string(n) : Std.string(n);
		var ts:String = d.getFullYear() + '-' + p(d.getMonth() + 1) + '-' + p(d.getDate()) + '_' + p(d.getHours()) + '-' + p(d.getMinutes()) + '-' + p(d.getSeconds());
		var ext:String = (fmt == 'base64') ? 'b64' : (fmt == 'zlib') ? 'zlib' : 'json';
		return 'settings_' + ts + '.' + ext;
	}

	function onSaveToFile():Void
	{
		if (exportResultText.length == 0) { onGenerate(); if (exportResultText.length == 0) return; }
		var dir:String = _getSaveRootDir();
		var fileName:String = _makeTimestampedFileName(exportConfig.format);
		var fullPath:String = dir + '/' + fileName;
		try
		{
			File.saveContent(fullPath, exportResultText);
			hintText.color = 0xFFFFD700; hintText.text = Language.get('io_saved_to_file') + ': ' + fileName;
		new FlxTimer().start(2.5, function(_) { hintText.color = 0xFFBBBBBB; hintText.text = Language.get('io_hint'); });
		}
		catch (e:Dynamic)
		{
			hintText.color = 0xFFFF6666; hintText.text = Language.get('io_save_failed');
		new FlxTimer().start(2.5, function(_) { hintText.color = 0xFFBBBBBB; hintText.text = Language.get('io_hint'); });
		}
	}

	#if desktop
	function onChooseSavePath():Void
	{
		if (exportResultText.length == 0) { onGenerate(); if (exportResultText.length == 0) return; }
		if (_fileDlg == null) _fileDlg = new FileDialogHandler();
		var ext:String = (exportConfig.format == 'base64') ? 'b64' : (exportConfig.format == 'zlib') ? 'zlib' : 'json';
		var defaultName:String = _makeTimestampedFileName(exportConfig.format);
		var filter:Array<FileFilter> = [new FileFilter('Backup Files', '*.' + ext + ';*.json;*.b64;*.zlib'), new FileFilter('All Files', '*.*')];
		_fileDlg.save(defaultName, exportResultText,
			function() { hintText.text = Language.get('io_saved_to_file') + ': ' + (_fileDlg.path != null ? _fileDlg.path : defaultName); },
			function() {},
			function() { hintText.text = Language.get('io_save_failed'); }
		);
	}

	function onChooseImportFile():Void
	{
		if (_fileDlg == null) _fileDlg = new FileDialogHandler();
		var filter:Array<FileFilter> = [new FileFilter('Backup Files', '*.json;*.b64;*.zlib;*.txt'), new FileFilter('All Files', '*.*')];
		_fileDlg.open(null, Language.get('io_choose_file'), filter,
			function()
			{
				try
				{
					importRawText = File.getContent(_fileDlg.path);
					// 关键：换了源文件必须清旧解析结果，否则 buildImportSectionList 会残留旧 child
					clearImportPreview();
					_refreshImportPreview();
					hintText.text = Language.get('io_loaded_from') + ': ' + (_fileDlg.path != null ? _fileDlg.path : '?');
				}
				catch (e:Dynamic) { hintText.text = Language.get('io_load_failed'); }
			},
			function() {},
			function() { hintText.text = Language.get('io_load_failed'); }
		);
	}
	#end

	function buildImportPanel():Void
	{
		grpImport = new FlxGroup(); contentGroup.add(grpImport);
		var topY:Float = PAD_TOP + TAB_H + 16;
		var leftX:Float = PAD_X;
		var w:Float = FlxG.width - PAD_X * 2;

		var labelPaste = new FlxText(leftX, topY, w, Language.get('io_paste_here'), 20);
		labelPaste.setFormat(Paths.font(Language.get('game_font')), 20, 0xFFFFD700, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		labelPaste.borderSize = 2; labelPaste.antialiasing = antialias; grpImport.add(labelPaste);

		var areaH:Int = 180;
		importAreaBg = new FlxSprite().makeGraphic(Std.int(w), areaH, 0xFF111111);
		importAreaBg.x = leftX; importAreaBg.y = labelPaste.y + 32; importAreaBg.scrollFactor.set(); grpImport.add(importAreaBg);

		// 预览文本（游戏内部渲染）+ 点击整个区域可编辑
		importPreviewText = new FlxText(leftX + 8, importAreaBg.y + 6, Std.int(w) - 16, Language.get('io_paste_here'), 14);
		importPreviewText.setFormat(Paths.font("vcr.ttf"), 14, 0xFF888888, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		importPreviewText.borderSize = 1; importPreviewText.antialiasing = false;
		// 开启 openfl TextField 原生换行 + 裁剪
		importPreviewText.textField.multiline = true;
		importPreviewText.textField.wordWrap = true;
		importPreviewText.textField.selectable = false;
		importPreviewText.textField.width = Std.int(w) - 16;
		importPreviewText.textField.height = areaH - 12;
		grpImport.add(importPreviewText);

		var btnRowY = importAreaBg.y + areaH + 6;
		importBtnPaste = makeIOButton(leftX, btnRowY, 140, 36, Language.get('io_paste_btn'), 0xFF1E90FF, function() { try { var t:String = null; if (gameClipboard.length > 0) t = gameClipboard; else { try { t = Clipboard.text; } catch (_) {} } if (t != null && t.length > 0) { importRawText = t; _refreshImportPreview(); hintText.text = Language.get('io_pasted') + ' (' + t.length + ' ' + Language.get('io_chars') + ')'; } else hintText.text = Language.get('io_clipboard_empty'); } catch (e:Dynamic) { hintText.text = Language.get('io_clipboard_error'); } });
		grpImport.add(importBtnPaste);
		importBtnClear = makeIOButton(leftX + 150, btnRowY, 120, 36, Language.get('io_clear'), 0xFF884444, function() { importRawText = ''; _refreshImportPreview(); hintText.text = ''; });
		grpImport.add(importBtnClear);
		importBtnParse = makeIOButton(leftX + 280, btnRowY, 150, 36, Language.get('io_parse'), 0xFF228B22, function() { runImportParse(); });
		grpImport.add(importBtnParse);
		#if desktop
		importBtnChooseFile = makeIOButton(leftX + 440, btnRowY, 170, 36, Language.get('io_choose_file'), 0xFF9932CC, function() { onChooseImportFile(); });
		grpImport.add(importBtnChooseFile);
		#end

		var parseY = btnRowY + 46;
		importParseResultText = new FlxText(leftX, parseY, w, '', 18);
		importParseResultText.setFormat(Paths.font(Language.get('game_font')), 18, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		importParseResultText.borderSize = 2; importParseResultText.antialiasing = antialias; grpImport.add(importParseResultText);

		var listTopY = parseY + 32;
		var listBottomSafe = FlxG.height - 100;
		var listH:Int = Std.int(Math.max(100, listBottomSafe - listTopY));
		importListMaskX = leftX; importListMaskY = listTopY; importListMaskW = Std.int(w); importListMaskH = listH;

		importListBg = new FlxSprite().makeGraphic(importListMaskW, importListMaskH, 0xFF181818);
		importListBg.x = importListMaskX; importListBg.y = importListMaskY; importListBg.visible = false; importListBg.scrollFactor.set(); grpImport.add(importListBg);

		importListGroup = new FlxGroup(); importListGroup.visible = false; grpImport.add(importListGroup);

		importBtnConfirm = new FlxButton(leftX, FlxG.height - 80, Language.get('io_confirm_import'));
		importBtnConfirm.width = 200; importBtnConfirm.height = 44; importBtnConfirm.makeGraphic(200, 44, 0xFFDC143C);
		importBtnConfirm.label.setFormat(Paths.font(Language.get('game_font')), 22, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		importBtnConfirm.label.borderSize = 2; importBtnConfirm.label.antialiasing = antialias; importBtnConfirm.visible = false;
		importBtnConfirm.onUp.callback = function() { showConfirmDialog(); }; grpImport.add(importBtnConfirm);

		importBtnCancel = new FlxButton(leftX + 220, FlxG.height - 80, Language.get('io_cancel'));
		importBtnCancel.width = 160; importBtnCancel.height = 44; importBtnCancel.makeGraphic(160, 44, 0xFF555555);
		importBtnCancel.label.setFormat(Paths.font(Language.get('game_font')), 20, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		importBtnCancel.label.borderSize = 2; importBtnCancel.label.antialiasing = antialias; importBtnCancel.visible = false;
		importBtnCancel.onUp.callback = function() { clearImportPreview(); }; grpImport.add(importBtnCancel);
	}

	function makeIOButton(x:Float, y:Float, w:Int, h:Int, label:String, color:Int, cb:Void->Void):FlxButton
	{
		var btn = new FlxButton(x, y, label, cb); btn.width = w; btn.height = h; btn.makeGraphic(w, h, color);
		btn.label.setFormat(Paths.font(Language.get('game_font')), 18, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		btn.label.borderSize = 2; btn.label.antialiasing = antialias; return btn;
	}

	function applyImportListScroll():Void
	{
		var idx:Int = 0;
		for (basic in importListGroup.members)
		{
			var child:FlxObject = cast basic;
			var by:Float = (idx < importBaseYs.length) ? importBaseYs[idx] : child.y;
			child.y = by - importScrollY;
			child.visible = (child.y + child.height > importListMaskY && child.y < importListMaskY + importListMaskH);
			idx++;
		}
	}

	function runImportParse():Void
	{
		if (importRawText.length == 0) { hintText.text = Language.get('io_nothing_to_parse'); return; }
		importPreview = ClientPrefs.previewImport(importRawText);
		importParsedObj = ClientPrefs.decodeImport(importRawText);
		if (!importPreview.success)
		{
			importParseResultText.text = Language.get('io_parse_failed') + ': ' + importPreview.errorMsg;
			importParseResultText.color = 0xFFFF6666; clearImportPreview(); return;
		}
		var secNames:Array<String> = [];
		for (s in importPreview.loadedSections) secNames.push(sectionDisplayName(s));
		var msg = Language.get('io_parse_ok') + ': ' + secNames.join(', ');
		if (importPreview.appliedFieldCount > 0) msg += ' | ' + importPreview.appliedFieldCount + ' ' + Language.get('io_fields');
		importParseResultText.text = msg; importParseResultText.color = 0xFF66FF66;
		buildImportSectionList(); importBtnConfirm.visible = true; importBtnCancel.visible = true;
	}

	function sectionDisplayName(s:String):String
	{
		switch (s) { case 'prefs': return Language.get('io_sec_prefs'); case 'keyboard': return Language.get('io_sec_keyboard'); case 'gamepad': return Language.get('io_sec_gamepad'); case 'mobile': return Language.get('io_sec_mobile'); case 'gameplay': return Language.get('io_sec_gameplay'); default: return s; }
	}

	function buildImportSectionList():Void
	{
		if (importListGroup != null)
		{
			var _membs = importListGroup.members.copy();
			for (basic in _membs)
			{
				var cld:FlxObject = cast basic;
				if (cld != null) importListGroup.remove(basic);
				if (cld != null && cld.exists) cld.destroy();
			}
		}
		importSectionsEnabled.clear(); importBaseYs = [];
		importListBg.visible = true; importListGroup.visible = true;

		var y:Float = importListMaskY + 8;
		var lx:Float = importListMaskX + 12;
		var rx:Float = importListMaskX + importListMaskW - 12;

		var title = new FlxText(lx, y, rx - lx, Language.get('io_preview_title'), 16);
		title.setFormat(Paths.font(Language.get('game_font')), 16, 0xFFFFD700, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		title.borderSize = 1.5; title.antialiasing = antialias; importListGroup.add(title); importBaseYs.push(y); y += title.height + 6;

		for (s in importPreview.loadedSections)
		{
			importSectionsEnabled.set(s, true);
			var curS = s;
			var cb = new FlxButton(lx, y, ''); cb.width = 18; cb.height = 18; cb.makeGraphic(18, 18, 0xFF00AA00); cb.label.visible = false;
			cb.onUp.callback = function() { var cur = importSectionsEnabled.get(curS); cur = !cur; importSectionsEnabled.set(curS, cur); cb.makeGraphic(18, 18, cur ? 0xFF00AA00 : 0xFF555555); };
			importListGroup.add(cb); importBaseYs.push(y);
			var lbl = new FlxText(lx + 26, y + 1, rx - lx - 26, sectionDisplayName(s), 16);
			lbl.setFormat(Paths.font(Language.get('game_font')), 16, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			lbl.borderSize = 1.5; lbl.antialiasing = antialias; importListGroup.add(lbl); importBaseYs.push(y + 1); y += 22;
			var detail = new FlxText(lx + 26, y, rx - lx - 26, getSectionDetail(s), 13);
			detail.setFormat(Paths.font("vcr.ttf"), 13, 0xFFBBBBBB, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			detail.borderSize = 1; detail.antialiasing = false; detail.wordWrap = true; importListGroup.add(detail); importBaseYs.push(y); y += Math.max(detail.height + 4, 16);
		}
		importScrollY = 0; importScrollMax = Std.int(Math.max(0, y - importListMaskY - importListMaskH + 20));
		applyImportListScroll();
	}

	function getSectionDetail(s:String):String
	{
		if (importParsedObj == null) return '';
		var sec:Dynamic = Reflect.field(importParsedObj, s);
		if (sec == null || !ClientPrefs._dynaIsObject(sec)) return '';
		var keys:Array<String> = Reflect.fields(sec);
		switch (s)
		{
			case 'prefs': return keys.length + ' ' + Language.get('io_fields') + ': ' + keys.slice(0, 5).join(', ') + (keys.length > 5 ? ' ...' : '');
			case 'keyboard': case 'gamepad': case 'mobile': return keys.length + ' ' + Language.get('io_binds');
			case 'gameplay': return keys.length + ' ' + Language.get('io_settings') + ': ' + keys.join(', ');
		}
		return '';
	}

	function clearImportPreview():Void
	{
		importPreview = null;
		importParsedObj = null;
		if (importParseResultText != null) { importParseResultText.text = ''; importParseResultText.color = FlxColor.WHITE; }
		if (importListBg != null) importListBg.visible = false;
		if (importListGroup != null) importListGroup.visible = false;
		if (importBtnConfirm != null) importBtnConfirm.visible = false;
		if (importBtnCancel != null) importBtnCancel.visible = false;
		importSectionsEnabled.clear();
		importBaseYs = [];
		importScrollY = 0;
	}

	function showConfirmDialog():Void
	{
		// 防止重复点击：先关掉旧的
		if (confirmDialog != null) removeConfirmDialog();
		var toApply:Array<String> = [];
		for (s in importPreview.loadedSections) if (importSectionsEnabled.get(s)) toApply.push(sectionDisplayName(s));
		if (toApply.length == 0) { hintText.text = Language.get('io_nothing_to_apply'); return; }
		var dlgW = FlxG.width - 200; var dlgH = 380; var cx:Float = 100; var cy:Float = (FlxG.height - dlgH) / 2;
		confirmDialog = new FlxGroup(); add(confirmDialog);
		var overlay = new FlxSprite().makeGraphic(Std.int(FlxG.width), Std.int(FlxG.height), 0xAA000000); overlay.scrollFactor.set(); confirmDialog.add(overlay);
		var bg = new FlxSprite().makeGraphic(Std.int(dlgW), Std.int(dlgH), 0xFF222222); bg.x = cx; bg.y = cy; bg.scrollFactor.set(); confirmDialog.add(bg);
		var title = new FlxText(cx + 20, cy + 16, dlgW - 40, Language.get('io_confirm_title'), 24);
		title.setFormat(Paths.font(Language.get('game_font')), 24, 0xFFFF6666, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		title.borderSize = 2; title.antialiasing = antialias; confirmDialog.add(title);
		var body:String = Language.get('io_confirm_warning') + '\n\n' + Language.get('io_confirm_will_apply') + '\n';
		for (s in toApply) body += '  * ' + s + '\n';
		body += '\n' + Language.get('io_confirm_prompt');
		var bodyText = new FlxText(cx + 20, cy + 60, dlgW - 40, body, 18);
		bodyText.setFormat(Paths.font(Language.get('game_font')), 18, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		bodyText.borderSize = 1.5; bodyText.antialiasing = antialias; bodyText.wordWrap = true; bodyText.scrollFactor.set(); confirmDialog.add(bodyText);
		var btnY = cy + dlgH - 60;
		var yesBtn = new FlxButton(cx + dlgW - 280, btnY, Language.get('io_yes_apply'));
		yesBtn.width = 130; yesBtn.height = 40; yesBtn.makeGraphic(130, 40, 0xFFDC143C);
		yesBtn.label.setFormat(Paths.font(Language.get('game_font')), 20, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		yesBtn.label.borderSize = 2; yesBtn.label.antialiasing = antialias; yesBtn.onUp.callback = function() { removeConfirmDialog(); doConfirmImport(); };
		confirmDialog.add(yesBtn);
		var noBtn = new FlxButton(cx + dlgW - 140, btnY, Language.get('io_no_cancel'));
		noBtn.width = 120; noBtn.height = 40; noBtn.makeGraphic(120, 40, 0xFF555555);
		noBtn.label.setFormat(Paths.font(Language.get('game_font')), 20, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		noBtn.label.borderSize = 2; noBtn.label.antialiasing = antialias; noBtn.onUp.callback = function() { removeConfirmDialog(); };
		confirmDialog.add(noBtn);
	}

	function removeConfirmDialog():Void
	{
		if (confirmDialog != null) { remove(confirmDialog); confirmDialog.destroy(); confirmDialog = null; }
	}

	function doConfirmImport():Void
	{
		var toApply:Array<String> = [];
		for (s in importPreview.loadedSections) if (importSectionsEnabled.get(s)) toApply.push(s);
		var result = ClientPrefs.applyImport(importRawText, toApply);
		if (result.success)
	{
		hintText.text = Language.get('io_import_ok');
		var noticeSound = Paths.sound('notice');
		FlxG.sound.play(noticeSound);
		// 等音频播完再退出（Sound.length 是毫秒，FlxTimer 用秒）
		var waitSec:Float = noticeSound.length / 1000.0;
		if (waitSec <= 0) waitSec = 0.5; // 保险
		new FlxTimer().start(waitSec, function(_) { backToOptions(); });
	}
	else hintText.text = Language.get('io_import_failed') + ': ' + result.errorMsg;
	}

	override function update(elapsed:Float)
	{
		super.update(elapsed);

		if (FlxG.mouse.justPressed)
		{
			touchStartY = FlxG.mouse.screenY; touchActiveScrollTarget = -1;
			if (curTab == 'export' && isOverRect(FlxG.mouse.screenX, touchStartY, exportMaskX, exportMaskY, exportMaskW, exportMaskH)) touchActiveScrollTarget = 0;
			else if (curTab == 'import' && importListBg != null && importListBg.visible && isOverRect(FlxG.mouse.screenX, touchStartY, importListMaskX, importListMaskY, importListMaskW, importListMaskH)) touchActiveScrollTarget = 1;
			touchLastScrollY = touchStartY;
		}
		if (FlxG.mouse.pressed && touchStartY >= 0)
		{
			var curY = FlxG.mouse.screenY; var dy = curY - touchLastScrollY;
			if (touchActiveScrollTarget == 0) { exportScrollY = Std.int(clamp(exportScrollY - dy, 0, exportScrollMax)); applyExportScroll(); }
			else if (touchActiveScrollTarget == 1) { importScrollY = Std.int(clamp(importScrollY - dy, 0, importScrollMax)); applyImportListScroll(); }
			touchLastScrollY = curY;
		}
		if (FlxG.mouse.justReleased) { touchStartY = -1; touchActiveScrollTarget = -1; }

		if (confirmDialog != null) { if (FlxG.keys.justPressed.ESCAPE || FlxG.keys.justPressed.BACKSPACE || controls.BACK || (touchPad != null && touchPad.buttonB != null && touchPad.buttonB.justPressed) || FlxG.gamepads.anyJustPressed(B)) { removeConfirmDialog(); return; } }
		else { if (FlxG.keys.justPressed.ESCAPE || FlxG.keys.justPressed.BACKSPACE || controls.BACK || (touchPad != null && touchPad.buttonB != null && touchPad.buttonB.justPressed) || FlxG.gamepads.anyJustPressed(B)) { backToOptions(); return; } }
	}

	function backToOptions():Void
	{
		if (confirmDialog != null) { remove(confirmDialog); confirmDialog.destroy(); confirmDialog = null; }
		removeTouchPad();
		ClientPrefs.saveSettings();
		FlxG.switchState(new options.OptionsState());
	}
}

