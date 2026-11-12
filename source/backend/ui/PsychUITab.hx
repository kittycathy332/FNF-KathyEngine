package backend.ui;

import backend.Paths;
import flixel.graphics.FlxGraphic;
import flixel.util.FlxDestroyUtil;
import flixel.math.FlxPoint;
import openfl.display.BitmapData;
import openfl.display.Shape;

class PsychUITab extends FlxSprite
{
	public var name(default, set):String;
	public var text:FlxText;
	public var menu:FlxSpriteGroup = new FlxSpriteGroup();

	/** tab 头圆角半径（px）。默认 0 = 方角，其它编辑器不受影响 */
	public var cornerRadius:Float = 0;
	/** 四角独立开关，由所属 PsychUIBox.updateTabs() 按位置与最小化状态设置 */
	public var roundTopLeft:Bool = true;
	public var roundTopRight:Bool = true;
	public var roundBottomLeft:Bool = false;
	public var roundBottomRight:Bool = false;
	var _roundedBaked:Bool = false;
	var _tabW:Int = 0;
	var _tabH:Int = 0;
	static var _roundedTabCache:Map<String, FlxGraphic> = new Map<String, FlxGraphic>();

	public function new(name:String)
	{
		super();
		makeGraphic(1, 1, FlxColor.WHITE);
		color = FlxColor.BLACK;
		alpha = 0.6;
		antialiasing = false;

		@:bypassAccessor this.name = name;
		text = new FlxText(0, 0, 200, name);
		text.setFormat(Paths.font(Language.get('uitab_font')), Std.parseInt(Language.get('charting_tab_size')), FlxColor.BLACK, CENTER);
	}

	override function draw()
	{
		super.draw();

		if(visible && text != null && text.exists && text.visible)
		{
			text.x = x;
			text.y = y + height/2 - text.height/2;
			text.draw();
		}
	}

	override function destroy()
	{
		text = FlxDestroyUtil.destroy(text);
		menu = FlxDestroyUtil.destroy(menu);
		super.destroy();
	}
	
	public function updateMenu(parent:PsychUIBox, elapsed:Float)
	{
		if(menu != null && menu.exists && menu.active)
		{
			menu.scrollFactor.set(parent.scrollFactor.x, parent.scrollFactor.y);
			menu.update(elapsed);
		}
	}

	public function drawMenu(parent:PsychUIBox)
	{
		if(menu != null && menu.exists && menu.visible)
		{
			menu.x = parent.x;
			menu.y = parent.y + parent.tabHeight;
			menu.draw();
		}
	}

	public function resize(width:Int, height:Int)
	{
		_tabW = width;
		_tabH = height;
		if (cornerRadius > 0)
		{
			// 白色圆角位图：外部仍靠 color 动态染成白/黑（选中/未选中），四角透明。
			// 四角各自开关，所以「首尾圆、中间方」与最小化时的整条圆角都能共用一套缓存。
			var flags:Int = (roundTopLeft ? 1 : 0) | (roundTopRight ? 2 : 0)
				| (roundBottomLeft ? 4 : 0) | (roundBottomRight ? 8 : 0);
			var key:String = 'PsychUITab:rounded:${width}x${height}r${Std.int(cornerRadius * 2)}f$flags';
			var graph:FlxGraphic = _roundedTabCache.get(key);
			if (graph == null || graph.isDestroyed)
			{
				var bd:BitmapData = new BitmapData(Std.int(Math.max(1, width)), Std.int(Math.max(1, height)), true, 0);
				var shape:Shape = new Shape();
				var g = shape.graphics;
				var r:Float = cornerRadius;
				g.beginFill(0xFFFFFF, 1);
				g.drawRoundRectComplex(0, 0, bd.width, bd.height,
					roundTopLeft ? r : 0, roundTopRight ? r : 0,
					roundBottomLeft ? r : 0, roundBottomRight ? r : 0);
				g.endFill();
				bd.draw(shape);
				PsychUIRounded.hardenAlpha(bd); // 去掉 OpenFL 矢量绘制的半透明圆角边
				graph = FlxGraphic.fromBitmapData(bd, false, key);
				_roundedTabCache.set(key, graph);
			}
			frames = graph.imageFrame;
			antialiasing = false;
			_roundedBaked = true;
		}
		else if (_roundedBaked)
		{
			makeGraphic(1, 1, FlxColor.WHITE);
			_roundedBaked = false;
		}
		setGraphicSize(width, height);
		updateHitbox();
		text.fieldWidth = width;
	}

	/** 设置圆角半径并立即重绘 tab 头；传 0 还原方角 */
	public function setCornerRadius(value:Float):Void
	{
		cornerRadius = value;
		if (_tabW > 0 && _tabH > 0) resize(_tabW, _tabH);
	}

	function set_name(v:String)
	{
		text.text = v;
		return (name = v);
	}


	override function set_cameras(v:Array<FlxCamera>)
	{
		text.cameras = v;
		menu.cameras = v;
		return super.set_cameras(v);
	}

	override function set_camera(v:FlxCamera)
	{
		text.camera = v;
		menu.camera = v;
		return super.set_camera(v);
	}
}