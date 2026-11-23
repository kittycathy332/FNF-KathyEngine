package states.editors.vanilla104.content;

import openfl.net.FileReference;
import openfl.events.Event;
import openfl.events.IOErrorEvent;
import flash.net.FileFilter;

import haxe.Exception;
import sys.io.File;
import lime.ui.*;

import flixel.FlxBasic;
#if android
import mobile.backend.AndroidFilePicker;
#end

//Currently only supports OPEN and SAVE, might change that in the future, who knows
class FileDialogHandler extends FlxBasic
{
	var _fileRef:FileReferenceCustom;
	var _dialogMode:FileDialogType = OPEN;
	public function new()
	{
		_fileRef = new FileReferenceCustom();
		_fileRef.addEventListener(Event.CANCEL, onCancelFn);
		_fileRef.addEventListener(IOErrorEvent.IO_ERROR, onErrorFn);

		super();
	}

	// callbacks
	public var onComplete:Void->Void;
	public var onCancel:Void->Void;
	public var onError:Void->Void;

	var _currentEvent:openfl.events.Event->Void;

	public function save(?fileName:String = '', ?dataToSave:String = '', ?onComplete:Void->Void, ?onCancel:Void->Void, ?onError:Void->Void)
	{
		if(!completed)
		{
			throw new Exception('You must finish previous operation before starting a new one.');
		}

		#if android
		// Android：原生「另存为」对话框（ACTION_CREATE_DOCUMENT），废弃自制列表选择器
		_startUp(onComplete, onCancel, onError);
		var name:String = (fileName != null && fileName.length > 0) ? fileName : 'chart.json';
		var mime:String = mimeFromName(name);
		AndroidFilePicker.saveFile(name, mime, dataToSave == null ? '' : dataToSave, function(ok:Bool, uri:String)
		{
			completed = true;
			if(!ok || uri == null)
			{
				if(onCancel != null) onCancel();
				return;
			}
			this.path = uri;
			if(onComplete != null) onComplete();
		});
		return;
		#elseif ios
		// iOS：无原生保存对话框，用纯 Haxe 选择器兜底（UI 层大多隐藏）
		_startUp(onComplete, onCancel, onError);
		MobileFilePicker.onDone = function(path:String, data:String)
		{
			completed = true;
			if(path == null)
			{
				if(onCancel != null) onCancel();
				return;
			}
			if(dataToSave != null)
			{
				try
				{
					var dir:String = haxe.io.Path.directory(path);
					if(dir.length > 0 && !sys.FileSystem.exists(dir))
						sys.FileSystem.createDirectory(dir);
					sys.io.File.saveContent(path, dataToSave);
				}
				catch(e:Dynamic)
				{
					if(onError != null) onError();
					return;
				}
			}
			this.path = path;
			if(onComplete != null) onComplete();
		};
		if(!MobileFilePicker.pick(MobileFilePicker.MODE_SAVE, fileName, '保存文件', null))
		{
			completed = true;
			if(onError != null) onError();
		}
		return;
		#end

		this._dialogMode = SAVE;
		_startUp(onComplete, onCancel, onError);

		removeEvents();
		_currentEvent = onSaveComplete;
		_fileRef.addEventListener(#if desktop Event.SELECT #else Event.COMPLETE #end, _currentEvent);
		_fileRef.save(dataToSave, fileName);
	}

	public function open(?defaultName:String = null, ?title:String = null, ?filter:Array<FileFilter> = null, ?onComplete:Void->Void, ?onCancel:Void->Void, ?onError:Void->Void)
	{
		if(!completed)
		{
			throw new Exception('You must finish previous operation before starting a new one.');
		}

		#if android
		// Android：走系统原生文件选择器（SAF / Documents UI），可从下载/Drive 等任意位置选
		_startUp(onComplete, onCancel, onError);
		AndroidFilePicker.pick(mimeTypeFromFilter(filter), function(text:String, name:String)
		{
			completed = true;
			if(text == null)
			{
				if(onCancel != null) onCancel();
				return;
			}
			// content:// URI 不可直接用 File.getContent 读；把内容落盘到 saves/，
			// 回填一个真实可读路径给调用方（Song.chartPath 等后续读写都依赖它）。
			var fileName:String = (name != null && name.length > 0) ? name : (defaultName != null ? defaultName : 'picked.json');
			var dest:String = mobile.backend.StorageUtil.getExternalStorageDirectory() + 'saves/' + fileName;
			try
			{
				var dir:String = haxe.io.Path.directory(dest);
				if(dir.length > 0 && !sys.FileSystem.exists(dir)) sys.FileSystem.createDirectory(dir);
				sys.io.File.saveContent(dest, text);
			}
			catch(e:Dynamic)
			{
				if(onError != null) onError();
				return;
			}
			this.path = dest;
			this.data = text;
			if(onComplete != null) onComplete();
		});
		return;
		#elseif ios
		// iOS：无原生文件选择能力（无 UIDocumentPicker 扩展），用纯 Haxe 目录枚举兜底；
		// 相关菜单项在 UI 层按 #if ios 隐藏，此处保留仅为 API 完整性。
		_startUp(onComplete, onCancel, onError);
		MobileFilePicker.onDone = function(path:String, data:String)
		{
			completed = true;
			if(path == null)
			{
				if(onCancel != null) onCancel();
				return;
			}
			this.path = path;
			this.data = data;
			if(onComplete != null) onComplete();
		};
		if(!MobileFilePicker.pick(MobileFilePicker.MODE_OPEN, defaultName, title, 'json'))
		{
			completed = true;
			if(onError != null) onError();
		}
		return;
		#end

		this._dialogMode = OPEN;
		_startUp(onComplete, onCancel, onError);
		if(filter == null) filter = [new FileFilter('JSON', 'json')];
		#if mac
		filter = [];
		#end

		removeEvents();
		_currentEvent = onLoadComplete;
		_fileRef.addEventListener(#if desktop Event.SELECT #else Event.COMPLETE #end, _currentEvent);
		_fileRef.browseEx(OPEN, defaultName, title, filter);
	}

	public function openDirectory(?title:String = null, ?onComplete:Void->Void, ?onCancel:Void->Void, ?onError:Void->Void)
	{
		if(!completed)
		{
			throw new Exception('You must finish previous operation before starting a new one.');
		}

		#if android
		// Android：系统目录选择器（ACTION_OPEN_DOCUMENT_TREE），多文件保存用
		_startUp(onComplete, onCancel, onError);
		AndroidFilePicker.pickDirectory(function(uri:String)
		{
			completed = true;
			if(uri == null)
			{
				if(onCancel != null) onCancel();
				return;
			}
			this.path = uri;
			if(onComplete != null) onComplete();
		});
		return;
		#elseif ios
		_startUp(onComplete, onCancel, onError);
		MobileFilePicker.onDone = function(path:String, data:String)
		{
			completed = true;
			if(path == null)
			{
				if(onCancel != null) onCancel();
				return;
			}
			this.path = path;
			if(onComplete != null) onComplete();
		};
		if(!MobileFilePicker.pick(MobileFilePicker.MODE_DIRECTORY, null, title, null))
		{
			completed = true;
			if(onError != null) onError();
		}
		return;
		#end

		this._dialogMode = OPEN_DIRECTORY;
		_startUp(onComplete, onCancel, onError);

		removeEvents();
		_currentEvent = onLoadDirectoryComplete;
		_fileRef.addEventListener(#if desktop Event.SELECT #else Event.COMPLETE #end, _currentEvent);
		_fileRef.browseEx(OPEN_DIRECTORY, null, title);
	}

	#if android
	/** 从文件名推断 MIME，供 ACTION_CREATE_DOCUMENT 使用。 */
	static function mimeFromName(name:String):String
	{
		var lower:String = name.toLowerCase();
		if(lower.endsWith('.json')) return 'application/json';
		if(lower.endsWith('.txt')) return 'text/plain';
		if(lower.endsWith('.png')) return 'image/png';
		if(lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
		if(lower.endsWith('.ogg') || lower.endsWith('.mp3') || lower.endsWith('.wav')) return 'audio/*';
		return '*/*';
	}

	/** 把 FileFilter 首个扩展名转成 SAF MIME（json→application/json，其余 image/* 等）。 */
	static function mimeTypeFromFilter(filter:Array<FileFilter>):String
	{
		if(filter == null || filter.length < 1 || filter[0] == null || filter[0].extension == null)
			return 'application/json';
		var raw:String = filter[0].extension;
		raw = StringTools.replace(raw, '*.', '');
		if(raw.indexOf(';') >= 0) return '*/*'; // 多扩展名时不过滤，回调按实际扩展判断
		raw = StringTools.trim(raw).toLowerCase();
		if(raw.length < 1) return 'application/json';
		return switch(raw)
		{
			case 'json': 'application/json';
			case 'txt': 'text/plain';
			case 'png': 'image/png';
			case 'jpg', 'jpeg': 'image/jpeg';
			case 'ogg', 'mp3', 'wav': 'audio/*';
			case 'mp4', 'webm': 'video/*';
			default: '*/*';
		};
	}
	#end

	public var data:String;
	public var path:String;
	public var completed:Bool = true;
	function onSaveComplete(_)
	{
		@:privateAccess
		this.path = _fileRef._trackSavedPath;
		this.completed = true;
		trace('Saved file to: $path');

		removeEvents();
		this.completed = true;
		if(onComplete != null) onComplete();
	}

	function onLoadComplete(_)
	{
		@:privateAccess
		this.path = _fileRef.__path;
		this.data = File.getContent(this.path);
		this.completed = true;
		trace('Loaded file from: $path');

		removeEvents();
		this.completed = true;
		if(onComplete != null)
			onComplete();
	}

	function onLoadDirectoryComplete(_)
	{
		@:privateAccess
		this.path = _fileRef.__path;
		this.completed = true;
		trace('Loaded directory: $path');

		removeEvents();
		this.completed = true;
		if(onComplete != null)
			onComplete();
	}

	function onCancelFn(_)
	{
		removeEvents();
		this.completed = true;
		if(onCancel != null) onError();
	}

	function onErrorFn(_)
	{
		removeEvents();
		this.completed = true;
		if(onError != null) onError();
	}

	function _startUp(onComplete:Void->Void, onCancel:Void->Void, onError:Void->Void)
	{
		this.onComplete = onComplete;
		this.onCancel = onCancel;
		this.onError = onError;
		this.completed = false;

		this.data = null;
		this.path = null;
	}

	function removeEvents()
	{
		if(_currentEvent == null) return;
		
		_fileRef.removeEventListener(#if desktop Event.SELECT #else Event.COMPLETE #end, _currentEvent);
		_currentEvent = null;
	}

	override function destroy()
	{
		removeEvents();
		_fileRef = null;
		_currentEvent = null;
		onComplete = null;
		onCancel = null;
		onError = null;
		data = null;
		path = null;
		completed = true;
		super.destroy();
	}
}

//Only way I could find to keep the path after saving a file
class FileReferenceCustom extends FileReference
{
	@:allow(backend.FileDialogHandler)
	var _trackSavedPath:String;
	override function saveFileDialog_onSelect(path:String):Void
	{
		_trackSavedPath = path;
		super.saveFileDialog_onSelect(path);
	}
	
	public function browseEx(browseType:FileDialogType = OPEN, ?defaultName:String, ?title:String = null, ?typeFilter:Array<FileFilter> = null):Bool
	{
		__data = null;
		__path = null;

		#if desktop
		var filter = null;

		if (typeFilter != null)
		{
			var filters = [];

			for (type in typeFilter)
			{
				filters.push(StringTools.replace(StringTools.replace(type.extension, "*.", ""), ";", ","));
			}

			filter = filters.join(";");
		}

		var openFileDialog = new FileDialog();
		openFileDialog.onCancel.add(openFileDialog_onCancel);
		openFileDialog.onSelect.add(openFileDialog_onSelect);
		openFileDialog.browse(browseType, filter, defaultName, title);
		return true;
		#elseif (js && html5)
		var filter = null;
		if (typeFilter != null)
		{
			var filters = [];
			for (type in typeFilter)
			{
				filters.push(StringTools.replace(StringTools.replace(type.extension, "*.", "."), ";", ","));
			}
			filter = filters.join(",");
		}
		if (filter != null)
		{
			__inputControl.setAttribute("accept", filter);
		}
		__inputControl.onchange = function()
		{
			var file = __inputControl.files[0];
			modificationDate = Date.fromTime(file.lastModified);
			creationDate = modificationDate;
			size = file.size;
			type = "." + Path.extension(file.name);
			name = Path.withoutDirectory(file.name);
			__path = file.name;
			dispatchEvent(new Event(Event.SELECT));
		}
		__inputControl.click();
		return true;
		#end

		return false;
	}
}