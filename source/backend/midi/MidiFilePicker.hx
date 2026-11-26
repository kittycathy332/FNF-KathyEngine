package backend.midi;

import haxe.io.Bytes;
import lime.ui.FileDialog;

/**
 *  跨平台的 MIDI 文件选择器。
 *
 *  - 桌面：lime 原生文件对话框，直接拿到字节流
 *  - Android：系统 SAF / Documents UI（可访问下载、Drive 等任意位置）
 *  - HTML5：浏览器 <input type="file"> + FileReader
 *  - iOS：项目现有能力里没有原生文档选择器，返回 false（可后续补 UIDocumentPicker）
 *
 *  返回的 Bytes 可以直接喂给 MidiPlayer：
 *    MidiFilePicker.pick(function(bytes, name) {
 *        var player = new MidiPlayer(bytes);
 *        player.play();
 *    });
 */
class MidiFilePicker
{
	public static function pick(?onPicked:Bytes->String->Void, ?onCancel:Void->Void, ?onError:Void->Void, ?mimeType:String = "audio/midi"):Bool
	{
		#if android
		return pickAndroid(onPicked, onCancel, onError, mimeType);
		#elseif (js && html5)
		return pickHtml5(onPicked, onCancel, onError);
		#elseif desktop
		return pickDesktop(onPicked, onCancel, onError);
		#else
		if (onError != null) onError();
		return false;
		#end
	}

	#if android
	static function pickAndroid(onPicked:Bytes->String->Void, onCancel:Void->Void, onError:Void->Void, mimeType:String):Bool
	{
		return mobile.backend.AndroidFilePicker.pickBytes(mimeType, function(bytes:Bytes, name:String)
		{
			if (bytes == null)
			{
				if (onCancel != null) onCancel();
				return;
			}
			if (onPicked != null) onPicked(bytes, name != null ? name : "picked.mid");
		});
	}
	#end

	#if desktop
	static function pickDesktop(onPicked:Bytes->String->Void, onCancel:Void->Void, onError:Void->Void):Bool
	{
		var dialog = new FileDialog();
		dialog.onOpen.add(function(resource:lime.utils.Resource)
		{
			var bytes:Bytes = cast resource;
			if (onPicked != null) onPicked(bytes, "picked.mid");
		});
		dialog.onCancel.add(function()
		{
			if (onCancel != null) onCancel();
		});

		// macOS 的 tiny filedialog 对 filter 支持不稳定，直接不过滤。
		var filter = #if mac null #else "*.mid;*.midi" #end;
		var opened = dialog.open(filter, null, "选择 MIDI 文件");
		if (!opened && onError != null)
			onError();
		return opened;
	}
	#end

	#if (js && html5)
	static function pickHtml5(onPicked:Bytes->String->Void, onCancel:Void->Void, onError:Void->Void):Bool
	{
		var input:js.html.InputElement = cast js.Browser.document.createElement("input");
		input.type = "file";
		input.accept = ".mid,.midi,audio/midi,audio/x-midi";
		input.style.display = "none";
		js.Browser.document.body.appendChild(input);

		function cleanup():Void
		{
			if (input.parentNode != null)
				input.parentNode.removeChild(input);
		}

		input.onchange = function(_)
		{
			var files = input.files;
			if (files == null || files.length == 0)
			{
				cleanup();
				if (onCancel != null) onCancel();
				return;
			}

			var file = files[0];
			var reader = new js.html.FileReader();
			reader.onload = function(_)
			{
				cleanup();
				var buffer:js.lib.ArrayBuffer = cast reader.result;
				var view = new js.lib.Uint8Array(buffer);
				var bytes = Bytes.alloc(view.length);
				for (i in 0...view.length)
					bytes.set(i, view[i]);
				if (onPicked != null) onPicked(bytes, file.name);
			};
			reader.onerror = function(_)
			{
				cleanup();
				if (onError != null) onError();
			};
			reader.readAsArrayBuffer(file);
		};

		input.click();
		return true;
	}
	#end
}
