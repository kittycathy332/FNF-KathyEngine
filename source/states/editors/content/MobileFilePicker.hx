package states.editors.content;

#if mobile

import flixel.FlxG;
import flixel.text.FlxText;
import flixel.util.FlxColor;

import backend.ui.PsychUIButton;
import backend.ui.PsychUIRadioGroup;
import mobile.backend.StorageUtil;
import states.editors.content.Prompt;

using StringTools;

/**
 * 移动端 JSON 文件选择器（Android / iOS 通用）。
 *
 * 桌面端 FileDialogHandler 依赖 lime FileDialog，而 openfl 的 FileReference.browse()
 * 在移动端只有 desktop / html5 分支，其余平台直接 return false 且不触发回调。
 * 本类用纯 Haxe 文件系统枚举 + PsychUI 控件补上这条能力，
 * 让 FileDialogHandler 在移动端的 open/save/openDirectory 三个模式都能工作。
 *
 * 数据源固定为 StorageUtil 用户数据根（saves/ + mods/<mod>/charts/ + mods/<mod>/），
 * 不依赖系统 SAF / UIDocumentPicker，因此 iOS 同样可用。
 */
class MobileFilePicker
{
	public static inline var MODE_OPEN:Int = 0;
	public static inline var MODE_SAVE:Int = 1;
	public static inline var MODE_DIRECTORY:Int = 2;

	/** 唯一回调：path 为选中路径（文件/目录绝对路径），data 为文件内容（目录/保存模式为 null）。path==null 表示取消或失败。 */
	public static var onDone:String->String->Void = null;

	static var _busy:Bool = false;
	static var _finishing:Bool = false;

	static function root():String
		return StorageUtil.getExternalStorageDirectory();

	/**
	 * 启动选择器。mode 见 MODE_*。
	 * defaultName 仅 SAVE 模式使用；ext 过滤后缀（不含点，如 'json'）。
	 * 返回 true 表示选择器已打开（结果走 onDone）；false 表示无法打开（onDone 未被调用）。
	 */
	public static function pick(mode:Int, ?defaultName:String, ?title:String, ?ext:String = 'json'):Bool
	{
		if (_busy)
			return false;

		StorageUtil.ensureStorageRoot();

		var rootPath:String = root();
		var items:Array<FileEntry> = switch (mode)
		{
			case MODE_OPEN: collectFiles(rootPath, ext);
			case MODE_SAVE: collectSaveTargets(rootPath, defaultName, ext);
			case MODE_DIRECTORY: collectDirectories(rootPath);
			default: [];
		}

		if (items.length < 1)
		{
			FlxG.log.warn('MobileFilePicker: no items found (mode=$mode, root=$rootPath)');
			return false;
		}

		_busy = true;
		var displayLabels:Array<String> = items.map(e -> e.label);
		var radioGrp:PsychUIRadioGroup = new PsychUIRadioGroup(0, 0, displayLabels, 26, Std.int(Math.min(9, items.length)), false, 420);
		radioGrp.checked = 0;

		// 内置箭头默认 visible=false，超过一页时手动打开，才能触摸滚动
		if (items.length > radioGrp.maxItems)
		{
			radioGrp.arrowUp.visible = true;
			radioGrp.arrowDown.visible = true;
		}

		var promptTitle:String = (title != null && title.length > 0) ? title : switch (mode)
		{
			case MODE_SAVE: '保存文件';
			case MODE_DIRECTORY: '选择目录';
			default: '选择文件';
		};

		_finishing = false;
		FlxG.state.persistentUpdate = false;
		var pickerPrompt = new Prompt.BasePrompt(540, 470, promptTitle, function(state:Prompt.BasePrompt)
		{
			var closeBtn:PsychUIButton = new PsychUIButton(state.bg.x + state.bg.width - 38, state.bg.y, 'X', function()
			{
				finish(null, null);
			}, 34);
			closeBtn.cameras = state.cameras;
			state.add(closeBtn);

			radioGrp.x = state.bg.x + 40;
			radioGrp.y = state.bg.y + 60;
			radioGrp.cameras = state.cameras;
			state.add(radioGrp);

			var hintText:FlxText = new FlxText(state.bg.x + 40, state.bg.y + 60 + radioGrp.maxItems * 26 + 12, 460,
				(mode == MODE_SAVE ? '选中文件将覆盖；新文件写入 saves/。' : '点击选中后按「确定」'), 12);
			hintText.font = Paths.font(Language.get('uitab_font'));
			hintText.color = FlxColor.GRAY;
			hintText.cameras = state.cameras;
			state.add(hintText);

			var confirmBtn:PsychUIButton = new PsychUIButton(radioGrp.x + 260, state.bg.y + state.bg.height - 54, '确定', function()
			{
				var idx:Int = radioGrp.checked;
				if (idx < 0 || idx >= items.length)
					return;
				var entry:FileEntry = items[idx];

				if (mode == MODE_OPEN)
				{
					var data:String = null;
					try data = sys.io.File.getContent(entry.path) catch (e:Dynamic) {}
					if (data == null)
					{
						FlxG.log.warn('MobileFilePicker: read failed (${entry.path})');
						finish(null, null);
						return;
					}
					finish(entry.path, data);
				}
				else finish(entry.path, null);
			}, 110);
			confirmBtn.cameras = state.cameras;
			state.add(confirmBtn);

			var cancelBtn:PsychUIButton = new PsychUIButton(radioGrp.x, state.bg.y + state.bg.height - 54, '取消', function()
			{
				finish(null, null);
			}, 110);
			cancelBtn.cameras = state.cameras;
			state.add(cancelBtn);
		});
		pickerPrompt.onClose = function()
		{
			// 用户按 ESC / 系统返回键关闭时也要释放 busy，否则后续所有打开操作都失效
			if (!_finishing) finish(null, null);
		};
		FlxG.state.openSubState(pickerPrompt);
		return true;
	}

	static function finish(path:String, data:String):Void
	{
		_finishing = true;
		_busy = false;
		var cb = onDone;
		onDone = null;
		if (cb != null) cb(path, data);
	}

	static function collectFiles(rootPath:String, ext:String):Array<FileEntry>
	{
		var result:Array<FileEntry> = [];
		var dirs:Array<String> = [rootPath + 'saves'];

		for (mod in safeList(rootPath + 'mods'))
		{
			if (mod == null || mod.length < 1) continue;
			dirs.push(rootPath + 'mods/$mod/charts');
			dirs.push(rootPath + 'mods/$mod');
			dirs.push(rootPath + 'mods/$mod/images');
			dirs.push(rootPath + 'mods/$mod/sounds');
			dirs.push(rootPath + 'mods/$mod/music');
		}

		// 非 json 扩展（图片/音频）时补充 assets 目录
		if (ext != null && ext.toLowerCase() != 'json')
		{
			dirs.push(rootPath + 'assets/images');
			dirs.push(rootPath + 'assets/sounds');
			dirs.push(rootPath + 'assets/music');
		}

		for (dir in dirs)
		{
			for (file in safeList(dir))
			{
				if (file == null || file.length < 1) continue;
				if (ext != null && ext.length > 0 && !file.endsWith('.' + ext)) continue;
				result.push({
					label: shorten(dir, file),
					path: dir + '/' + file
				});
			}
		}
		return sort(result);
	}

	static function collectSaveTargets(rootPath:String, defaultName:String, ext:String):Array<FileEntry>
	{
		var name:String = (defaultName != null && defaultName.length > 0) ? defaultName : 'chart.json';
		if (ext != null && ext.length > 0 && !name.endsWith('.' + ext))
			name += '.$ext';

		var result:Array<FileEntry> = [{label: name, path: rootPath + 'saves/' + name}];
		for (entry in collectFiles(rootPath, ext))
			if (result[0].path.toLowerCase() != entry.path.toLowerCase())
				result.push(entry);
		return result;
	}

	static function collectDirectories(rootPath:String):Array<FileEntry>
	{
		var result:Array<FileEntry> = [{label: 'saves/', path: rootPath + 'saves'}];
		for (mod in safeList(rootPath + 'mods'))
		{
			if (mod == null || mod.length < 1) continue;
			var chartDir:String = rootPath + 'mods/$mod/charts';
			if (isDirectory(chartDir))
				result.push({label: 'mods/$mod/charts/', path: chartDir});
			result.push({label: 'mods/$mod/', path: rootPath + 'mods/$mod'});
		}
		return sort(result);
	}

	static function sort(items:Array<FileEntry>):Array<FileEntry>
	{
		items.sort(function(a, b) return a.label < b.label ? -1 : (a.label > b.label ? 1 : 0));
		return items;
	}

	static function safeList(path:String):Array<String>
	{
		try
		{
			if (sys.FileSystem.exists(path))
				return sys.FileSystem.readDirectory(path);
		}
		catch (e:Dynamic) {}
		return [];
	}

	static function isDirectory(path:String):Bool
	{
		try return sys.FileSystem.isDirectory(path) catch (e:Dynamic) {}
		return false;
	}

	static function shorten(dir:String, file:String):String
	{
		var rootPath:String = root();
		var rel:String = dir.startsWith(rootPath) ? dir.substring(rootPath.length) : dir;
		return (rel.length > 0 ? rel + '/' : '') + file;
	}
}

private typedef FileEntry = {
	var label:String;
	var path:String;
}

#end
