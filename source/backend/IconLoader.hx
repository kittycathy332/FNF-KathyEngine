package backend;

import haxe.io.Bytes;
import lime.system.System;
import openfl.display.BitmapData;
import openfl.utils.Assets;
import openfl.utils.ByteArray;
import sys.FileSystem;
import sys.io.File;

/**
 * Loads the icon that the game is already using, without adding a separate
 * `titlebar_icon.png` asset.
 *
 * Windows builds ship `icon.ico` (generated from Project.xml `<icon>`), so the
 * ICO's largest image is decoded at runtime. Linux/macOS builds use the
 * existing `icon.png` asset instead.
 */
class IconLoader
{
	public static function loadGameIcon():BitmapData
	{
		// Linux / macOS: Project.xml already copies icon.png into the app.
		try
		{
			if (Assets.exists("icon.png"))
			{
				var data = Assets.getBitmapData("icon.png");
				if (data != null) return data;
			}
		}
		catch (e:Dynamic) {}

		// Windows: decode the generated icon.ico directly.
		var dir = System.applicationDirectory;
		var candidates = [
			dir + "/icon.ico",
			dir + "\\icon.ico",
			"icon.ico"
		];

		for (path in candidates)
		{
			if (FileSystem.exists(path))
			{
				var data = loadIco(path);
				if (data != null) return data;
			}
		}

		// Last chance: a plain icon.png next to the executable.
		var pngCandidates = [
			dir + "/icon.png",
			dir + "\\icon.png",
			"icon.png"
		];

		for (path in pngCandidates)
		{
			if (FileSystem.exists(path))
			{
				try
				{
					var data = BitmapData.fromFile(path);
					if (data != null) return data;
				}
				catch (e:Dynamic) {}
			}
		}

		return null;
	}

	private static function loadIco(path:String):BitmapData
	{
		try
		{
			var data = File.getBytes(path);
			if (data.length < 6) return null;

			var count = u16(data, 4);
			var bestOffset = 0;
			var bestSize = 0;
			var bestScore = 0;

			for (i in 0...count)
			{
				var p = 6 + i * 16;
				if (p + 16 > data.length) break;

				var w = data.get(p);
				var h = data.get(p + 1);
				if (w == 0) w = 256;
				if (h == 0) h = 256;

				var size = u32(data, p + 8);
				var offset = u32(data, p + 12);
				if (size <= 0 || offset <= 0 || offset + size > data.length) continue;

				var score = w * h;
				if (score > bestScore)
				{
					bestScore = score;
					bestSize = size;
					bestOffset = offset;
				}
			}

			if (bestSize <= 0) return null;

			if (isPng(data, bestOffset))
			{
				var png = data.sub(bestOffset, bestSize);
				try
				{
					var bitmap = BitmapData.fromBytes(ByteArray.fromBytes(png));
					if (bitmap != null && bitmap.width > 0 && bitmap.height > 0)
						return bitmap;
				}
				catch (e:Dynamic) {}
			}

			return decodeBmp(data, bestOffset, bestSize);
		}
		catch (e:Dynamic)
		{
			return null;
		}
	}

	private static function decodeBmp(data:Bytes, offset:Int, size:Int):BitmapData
	{
		if (offset + 40 > data.length) return null;

		var headerSize = u32(data, offset);
		if (headerSize < 40 || offset + headerSize > data.length) return null;

		var width = u32(data, offset + 4);
		var rawHeight = u32(data, offset + 8);
		var bitCount = u16(data, offset + 14);
		var compression = u32(data, offset + 16);

		if (width <= 0 || rawHeight == 0 || compression != 0) return null;

		var height = Std.int(Math.abs(rawHeight) / 2);
		if (height <= 0) return null;

		var bytesPerPixel = bitCount == 32 ? 4 : (bitCount == 24 ? 3 : 0);
		if (bytesPerPixel == 0) return null;

		var stride = ((width * bytesPerPixel + 3) >> 2) << 2;
		var xorOffset = offset + headerSize;
		var andOffset = xorOffset + stride * height;
		var andStride = ((width + 31) >> 5) << 2;
		var topDown = rawHeight < 0;

		if (xorOffset + stride * height > data.length) return null;

		var hasAlpha = false;
		if (bitCount == 32)
		{
			for (i in 0...(width * height))
			{
				if (data.get(xorOffset + i * 4 + 3) > 0)
				{
					hasAlpha = true;
					break;
				}
			}
		}

		var bitmap = new BitmapData(width, height, true, 0);
		var maskAvailable = andOffset + andStride * height <= data.length;

		for (y in 0...height)
		{
			var row = topDown ? y : (height - 1 - y);
			var src = xorOffset + row * stride;
			var maskRow = andOffset + row * andStride;

			for (x in 0...width)
			{
				var b = 0;
				var g = 0;
				var r = 0;
				var a = 255;

				if (bitCount == 32)
				{
					var sp = src + x * 4;
					b = data.get(sp);
					g = data.get(sp + 1);
					r = data.get(sp + 2);
					a = data.get(sp + 3);
				}
				else
				{
					var sp = src + x * 3;
					b = data.get(sp);
					g = data.get(sp + 1);
					r = data.get(sp + 2);
				}

				var transparent = false;
				if (maskAvailable)
				{
					var mask = data.get(maskRow + (x >> 3));
					transparent = ((mask >> (7 - (x & 7))) & 1) != 0;
				}

				if (bitCount == 32 && hasAlpha)
				{
					if (transparent) a = 0;
				}
				else
				{
					a = transparent ? 0 : 255;
				}

				bitmap.setPixel32(x, y, (a << 24) | (r << 16) | (g << 8) | b);
			}
		}

		return bitmap;
	}

	private static inline function isPng(data:Bytes, offset:Int):Bool
	{
		if (offset + 8 > data.length) return false;
		return data.get(offset) == 0x89
			&& data.get(offset + 1) == 0x50
			&& data.get(offset + 2) == 0x4E
			&& data.get(offset + 3) == 0x47;
	}

	private static inline function u16(data:Bytes, pos:Int):Int
	{
		return data.get(pos) | (data.get(pos + 1) << 8);
	}

	private static inline function u32(data:Bytes, pos:Int):Int
	{
		return data.get(pos)
			| (data.get(pos + 1) << 8)
			| (data.get(pos + 2) << 16)
			| (data.get(pos + 3) << 24);
	}
}
