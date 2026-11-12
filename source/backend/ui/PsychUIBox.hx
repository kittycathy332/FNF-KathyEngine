package backend.ui;

import flixel.graphics.FlxGraphic;
import openfl.display.BitmapData;
import openfl.display.Shape;

typedef UIStyleData = {
	var bgColor:FlxColor;
	var textColor:FlxColor;
	var bgAlpha:Float;
}

class PsychUIBox extends FlxSpriteGroup
{
	public static final CLICK_EVENT = "uibox_click";
	public static final MINIMIZE_EVENT = "uibox_minimize"; //called on both minimizing and maximizing
	public static final DRAG_EVENT = "uibox_drag";
	public static final DROP_EVENT = "uibox_drop";
	public var tabs(default, null):Array<PsychUITab> = [];
	
	public var selectedTab(default, set):PsychUITab = null;
	public var selectedIndex(default, set):Int = -1;
	public var selectedName(default, set):String = null;

	public var bg:FlxSprite;

	public var selectedStyle:UIStyleData = {
		bgColor: FlxColor.WHITE,
		textColor: FlxColor.BLACK,
		bgAlpha: 1
	};
	public var hoverStyle:UIStyleData = {
		bgColor: FlxColor.WHITE,
		textColor: FlxColor.BLACK,
		bgAlpha: 0.6
	};
	public var unselectedStyle:UIStyleData = {
		bgColor: FlxColor.BLACK,
		textColor: FlxColor.WHITE,
		bgAlpha: 0.6
	};

	public var canMove:Bool = true;
	public var canMinimize(default, set):Bool = true;
	public var isMinimized(default, set):Bool = false;
	public var minimizeOnFocusLost:Bool = false;
	// 当设置为 true 时，背景板(bg)会随选中的 tab 实时移动/缩放，作为下拉菜单的底板；
	// 解决点击切换 tab 时背景板延迟导致 minimizeOnFocusLost 误收起菜单的问题
	public var bgFollowsSelectedTab:Bool = false;
	/**
	 * 面板圆角半径（px）。默认 0 = 保持原来的纯方角，其它编辑器不受影响；
	 * 设 >0 后背景板变成「黑底 + 白细描边」的圆角位图，配合 PsychUITab 的
	 * 上圆角 tab 头使用。位图按尺寸缓存复用，不会每次 resize 都新建纹理。
	 */
	public var cornerRadius:Float = 0;
	var _roundedBaked:Bool = false;
	var _roundedKey:String = '';
	static var _roundedBgCache:Map<String, FlxGraphic> = new Map<String, FlxGraphic>();
	var _boxWidth:Int = 0;

	/**
	 * 最小 / 最大化的过渡时长（秒）。默认 0 = 立即切换，保持其它编辑器原行为。
	 * 只有 cornerRadius > 0 的圆角面板才会走动画（方角皮肤仍走原来的 scale.y 即时切换）。
	 */
	public var minimizeDuration:Float = 0;
	/** 动画期间把高度量化到 8px 一档，圆角位图按尺寸缓存，往返复用不会持续新建纹理 */
	static inline var ANIM_HEIGHT_QUANT:Int = 8;
	var _animActive:Bool = false;
	var _animFrom:Float = 0;
	var _animTo:Float = 0;
	var _animHeight:Float = 0;
	var _animTime:Float = 0;
	var _animProgress:Float = 0;

	public function new(x:Float, y:Float, width:Int, height:Int, tabs:Array<String> = null)
	{
		super(x, y);
		
		bg = new FlxSprite().makeGraphic(1, 1, FlxColor.WHITE);
		bg.color = FlxColor.BLACK;
		bg.alpha = 0.6;
		bg.antialiasing = false;
		add(bg);

		if(tabs != null)
		{
			for (tab in tabs)
			{
				var createdTab:PsychUITab = new PsychUITab(tab);
				this.tabs.push(createdTab);
				add(createdTab);
			}
		}

		resize(width, height);
		selectedIndex = 0;
		forceCheckNext = true;
	}

	var _draggingPos:FlxPoint;
	var _draggingPoint:FlxPoint;
	var _pressedBox:Bool = false;
	var _draggingBox:Bool = false;
	var _lastTab:PsychUITab;
	var _lastClick:Float = 0;

	public var forceCheckNext:Bool = false;
	public var broadcastBoxEvents:Bool = true;
	override function update(elapsed:Float)
	{
		super.update(elapsed);

		// 最小 / 最大化过渡：在其它输入逻辑之前推进，保证本帧背景板高度已是最新值
		if (_animActive) stepMinimizeAnimation(elapsed);

		_lastClick += elapsed;
		if(!FlxG.mouse.released && _draggingBox && canMove)
		{
			var newPoint:FlxPoint = FlxG.mouse.getPositionInCameraView(camera);
			setPosition(_draggingPos.x - (_draggingPoint.x - newPoint.x), _draggingPos.y - (_draggingPoint.y - newPoint.y));
		}
		else
		{
			var wasDragging:Bool = _draggingBox;
			_draggingPos = null;
			_draggingPoint = null;
			_draggingBox = false;
			if(FlxG.mouse.released)
			{
				if(_pressedBox) forceCheckNext = true;
				_pressedBox = false;
			}
			if(wasDragging && broadcastBoxEvents) PsychUIEventHandler.event(DROP_EVENT, this);
		}

		for (tab in tabs)
		{
			tab.scrollFactor.set(scrollFactor.x, scrollFactor.y);
			tab.text.scrollFactor.set(scrollFactor.x, scrollFactor.y);
		}

		var _ignoreTabUpdate:Bool = false;
		if(forceCheckNext || FlxG.mouse.justMoved || FlxG.mouse.justPressed || FlxG.mouse.justReleased)
		{
			forceCheckNext = false;
			for (tab in tabs)
			{
				if(FlxG.mouse.overlaps(tab, camera))
				{
					tab.color = hoverStyle.bgColor;
					tab.alpha = hoverStyle.bgAlpha;
					tab.text.color = hoverStyle.textColor;
	
					if(FlxG.mouse.justPressed)
						_pressedBox = true;

					if(!_draggingBox && canMove && _pressedBox && FlxG.mouse.pressed && (Math.abs(FlxG.mouse.deltaScreenX) > 1 || Math.abs(FlxG.mouse.deltaScreenY) > 1))
					{
						_draggingPos = FlxPoint.weak(x, y);
						_draggingPoint = FlxG.mouse.getPositionInCameraView(camera);
						_draggingBox = true;
						if(broadcastBoxEvents) PsychUIEventHandler.event(DRAG_EVENT, this);
					}
					
					if(FlxG.mouse.justReleased && canMinimize && _lastClick < 0.15 && selectedTab == tab && _lastTab == selectedTab)
					{
						_ignoreTabUpdate = true;
						isMinimized = !isMinimized;
						_lastClick = 0;
						//trace('do minimize: $isMinimized');
					}
					
					if(FlxG.mouse.justPressed)
					{
						if(selectedTab != tab)
						{
							isMinimized = false;
							_ignoreTabUpdate = true;
						}
						_lastTab = selectedTab;
						selectedTab = tab;
						_lastClick = 0;
						if(broadcastBoxEvents) PsychUIEventHandler.event(CLICK_EVENT, this);
					}
					else if(selectedTab != tab) continue;
				}
				
				var style:UIStyleData = (selectedTab == tab) ? selectedStyle : unselectedStyle;
				tab.color = style.bgColor;
				tab.alpha = style.bgAlpha;
				tab.text.color = style.textColor;
			}

			// 实时同步下拉菜单背景板到当前选中的 tab（需在下方 minimizeOnFocusLost 判定之前）
			if(bgFollowsSelectedTab && selectedTab != null && !isMinimized && !_animActive && tabs.length > 0)
			{
				bg.x = x + selectedIndex * (_boxWidth / tabs.length);
				var menuW:Int = Std.int(Math.max(1, selectedTab.menu.width));
				var menuH:Int = Std.int(Math.max(1, selectedTab.menu.height + 21));
				// 圆角皮肤必须按新尺寸重烘焙；直接缩放整尺寸位图会把圆角与白边压扁
				if (_roundedBaked) bakeRoundedBg(menuW, menuH, true);
				else
				{
					bg.setGraphicSize(menuW, menuH);
					bg.updateHitbox();
				}
			}
		}

		if(_ignoreTabUpdate)
		{
			if(broadcastBoxEvents)
				PsychUIEventHandler.event(MINIMIZE_EVENT, this);
		}
		else if(selectedTab != null && !isMinimized && menuVisibleDuringAnim())
			selectedTab.updateMenu(this, elapsed);

		if(minimizeOnFocusLost && FlxG.mouse.justPressed && !isMinimized && !FlxG.mouse.overlaps(bg, camera))
		{
			isMinimized = true;
			if(broadcastBoxEvents)
				PsychUIEventHandler.event(MINIMIZE_EVENT, this);
		}
	}

	override function set_cameras(v:Array<FlxCamera>)
	{
		for (tab in tabs) tab.cameras = v;
		return super.set_cameras(v);
	}

	override function set_camera(v:FlxCamera)
	{
		for (tab in tabs) tab.camera = v;
		return super.set_camera(v);
	}
			
	override function draw()
	{
		super.draw();

		if(selectedTab != null && !isMinimized && menuVisibleDuringAnim())
			selectedTab.drawMenu(this);
	}

	/** 展开动画过了大半才让内容出现，避免内容飘在还没长起来的小框外面 */
	inline function menuVisibleDuringAnim():Bool
	{
		return !_animActive || _animProgress >= 0.55;
	}

	override function destroy()
	{
		_animActive = false;
		tabs = null;
		selectedTab = null;
		super.destroy();
	}

	public function addTab(name:String)
	{
		var createdTab:PsychUITab = new PsychUITab(name);
		tabs.push(createdTab);
		add(createdTab);
		updateTabs();

		if(selectedTab == null)
			selectedTab = createdTab;
	}

	public var tabHeight:Int = 20;
	public function updateTabs()
	{
		if (tabs.length == 0) return;
		var wid:Int = Std.int(_boxWidth / tabs.length);
		var last:Int = tabs.length - 1;
		// 动画途中保持「上圆下方」，收起动画结束（真正的最小化终态）才补下两角
		var collapsed:Bool = isMinimized && !_animActive;
		for (num => tab in tabs)
		{
			// 只有整条标签栏的最左 / 最右两端需要外圆角，中间 tab 保持方角，
			// 否则每个标签看起来都像一枚独立胶囊。
			// 最小化时底部两角也圆，让整条标签栏收成一枚完整的圆角条。
			tab.roundTopLeft = (num == 0);
			tab.roundTopRight = (num == last);
			tab.roundBottomLeft = (num == 0 && collapsed);
			tab.roundBottomRight = (num == last && collapsed);
			tab.x = x + wid * num;
			tab.resize(wid, tabHeight);
			tab.cameras = cameras;
		}
	}

	var _originalHeight:Int = 0;
	public function resize(width:Int, height:Int)
	{
		// 外部改尺寸时直接落到终态，别让进行中的动画继续写旧高度
		_animActive = false;
		_originalHeight = height;
		_boxWidth = width;
		if (cornerRadius > 0) bakeRoundedBg(width, height, !isMinimized);
		else
		{
			bg.setGraphicSize(width, height);
			bg.updateHitbox();
		}
		updateTabs();
	}

	/** 设置圆角半径并立即重绘背景板；传 0 可还原成方角 */
	public function setCornerRadius(value:Float):Void
	{
		_animActive = false;
		cornerRadius = value;
		if (value > 0)
			bakeRoundedBg(_boxWidth, isMinimized ? tabHeight : _originalHeight, !isMinimized);
		else if (_roundedBaked)
		{
			bg.makeGraphic(1, 1, FlxColor.WHITE);
			bg.color = FlxColor.BLACK;
			bg.setGraphicSize(_boxWidth, _originalHeight);
			bg.updateHitbox();
			_roundedBaked = false;
			_roundedKey = '';
		}
		updateTabs();
	}

	/**
	 * 烘焙圆角背景板，按 宽x高x圆角x描边 缓存复用。
	 * withBorder=false 用于最小化状态：只留纯黑圆角底，不再有白描边，
	 * 避免和「选中/悬停 tab 的高亮」叠成双层框。
	 */
	function bakeRoundedBg(width:Int, height:Int, withBorder:Bool = true):Void
	{
		width = Std.int(Math.max(1, width));
		height = Std.int(Math.max(1, height));
		var key:String = 'PsychUIBox:rounded:${width}x${height}r${Std.int(cornerRadius * 2)}b${withBorder ? 1 : 0}';
		// 尺寸/半径/描边没变就别重复 set frames（bgFollowsSelectedTab 每帧都会调到这里）
		if (_roundedBaked && _roundedKey == key) return;
		var graph:FlxGraphic = _roundedBgCache.get(key);
		if (graph == null || graph.isDestroyed)
		{
			var bd:BitmapData = new BitmapData(width, height, true, 0);
			var shape:Shape = new Shape();
			var g = shape.graphics;
			var diameter:Float = Math.min(cornerRadius * 2, Math.min(width, height));
			if (withBorder) g.lineStyle(2, 0xFFFFFF, 1, true);
			g.beginFill(0x000000, 1);
			if (withBorder) g.drawRoundRect(1, 1, width - 2, height - 2, diameter, diameter);
			else g.drawRoundRect(0, 0, width, height, diameter, diameter);
			g.endFill();
			bd.draw(shape);
			// 半透明 AA 像素只出现在轮廓 / 圆角弧附近，只硬边化外圈即可。
			// 折叠动画每帧都要烘焙一张新高度的位图，全图逐像素会明显掉帧。
			PsychUIRounded.hardenEdges(bd, Std.int(Math.max(6, cornerRadius * 2 + 2)));
			graph = FlxGraphic.fromBitmapData(bd, false, key);
			_roundedBgCache.set(key, graph);
		}
		bg.frames = graph.imageFrame;
		bg.scale.set(1, 1);
		bg.color = FlxColor.WHITE; // 位图已含黑底与白边，不再整体染黑
		bg.antialiasing = false;
		bg.updateHitbox();
		_roundedBaked = true;
		_roundedKey = key;
	}

	private function set_selectedTab(v:PsychUITab)
	{
		if(v != null)
		{
			@:bypassAccessor selectedName = v.name;
			@:bypassAccessor selectedIndex = tabs.indexOf(v);
		}
		else
		{
			@:bypassAccessor selectedName = null;
			@:bypassAccessor selectedIndex = -1;
		}
		return (selectedTab = v);
	}

	private function set_selectedName(v:String)
	{
		if(v == null || v.trim().length < 1) selectedTab = null;

		for (tab in tabs)
		{
			if(tab.name == v)
			{
				selectedTab = tab;
				return v;
			}
		}
		return null;
	}

	private function set_selectedIndex(v:Int)
	{
		v = Std.int(Math.max(Math.min(v, tabs.length-1), -1));
		if(v > -1) selectedTab = tabs[v];
		else selectedTab = null;
		return v;
	}

	public function getTab(name:String)
	{
		for (tab in tabs)
			if(tab.name == name)
				return tab;

		return null;
	}

	function set_canMinimize(v:Bool)
	{
		isMinimized = false;
		return (canMinimize = v);
	}

	/** 最小化时背景板的目标高度：圆角皮肤只包住 tab 头，方角皮肤保持原有的 +20 */
	inline function minimizedHeight():Float
	{
		return cornerRadius > 0 ? tabHeight : (tabHeight + 20);
	}

	/** 把背景板设成指定高度（终态）；过渡帧走 applyAnimHeight() */
	function applyMinimizedHeight(h:Float, minimized:Bool):Void
	{
		if (_roundedBaked) bakeRoundedBg(_boxWidth, Std.int(Math.max(1, h)), !minimized);
		else bg.scale.y = h;
		bg.updateHitbox();
	}

	inline static function easeOutCubic(t:Float):Float
	{
		var f:Float = 1 - t;
		return 1 - f * f * f;
	}

	/**
	 * 展开用的轻回弹：主体仍是 easeOutCubic（起步平缓），只在末段 20% 叠加一个
	 * <=2% 的正弦鼓包，落点回到 1.0。标准 easeOutBack 起始斜率太陡，会让第一帧
	 * 直接从 20px 弹到 100+px，这里避免那种突兀感。
	 */
	inline static function easeOutBackSoft(t:Float):Float
	{
		var e:Float = easeOutCubic(t);
		if (t > 0.8) e += 0.02 * Math.sin((t - 0.8) / 0.2 * Math.PI);
		return e;
	}

	function applyAnimHeight(h:Float):Void
	{
		var q:Int = Std.int(Math.max(1, h));
		// 量化到 8px 一档，配合 bakeRoundedBg 的尺寸缓存：第一次经过某档烘焙一次，往返复用。
		// 收起末段（<=40px）不量化，否则 20px 的标签条会被量化成 24px 而跳一下。
		if (q > 40) q = Std.int(Math.round(q / ANIM_HEIGHT_QUANT) * ANIM_HEIGHT_QUANT);
		q = Std.int(FlxMath.bound(q, minimizedHeight(), _originalHeight + ANIM_HEIGHT_QUANT));
		// 动画全程带白描边：展开终态本来就有；收起只在最后一帧切到无描边，避免中途闪烁
		bakeRoundedBg(_boxWidth, q, true);
		bg.updateHitbox();
	}

	function stepMinimizeAnimation(elapsed:Float):Void
	{
		_animTime += elapsed;
		var t:Float = Math.min(1, _animTime / Math.max(0.01, minimizeDuration));
		_animProgress = t;
		var eased:Float = (_animTo > _animFrom) ? easeOutBackSoft(t) : easeOutCubic(t);
		var h:Float = _animFrom + (_animTo - _animFrom) * eased;
		var lo:Float = Math.min(_animFrom, _animTo);
		var hi:Float = Math.max(_animFrom, _animTo) + ANIM_HEIGHT_QUANT;
		_animHeight = FlxMath.bound(h, lo, hi);

		if (t >= 1)
		{
			_animActive = false;
			_animHeight = _animTo;
			applyMinimizedHeight(_animTo, isMinimized);
			// 收起动画结束后才把 tab 头底角补圆
			if (cornerRadius > 0 && tabs.length > 0) updateTabs();
		}
		else applyAnimHeight(_animHeight);
	}

	function set_isMinimized(v:Bool)
	{
		// 圆角皮肤是整尺寸烘焙位图：必须按目标高度重新烘焙，否则圆角与白边会被压扁。
		// 最小化时背景板只包住 tab 头（tabHeight，不再留 20px 黑空带），且不画白描边，
		// 避免和选中/悬停 tab 的高亮叠成双层框。
		var from:Float = _animActive ? _animHeight : bg.height;
		var to:Float = v ? minimizedHeight() : _originalHeight;
		_animActive = false; // 打断上一次动画，新目标从当前显示高度接着走

		@:bypassAccessor isMinimized = v;
		if (v) selectedTab = null;

		if (minimizeDuration > 0 && cornerRadius > 0 && _roundedBaked && Math.abs(to - from) > 2)
		{
			_animFrom = from;
			_animTo = to;
			_animHeight = from;
			_animTime = 0;
			_animProgress = 0;
			_animActive = true;
			applyAnimHeight(from);
		}
		else applyMinimizedHeight(to, v);

		// 只有圆角皮肤需要根据最小化状态重算 tab 的四角，其它编辑器保持原行为
		if (cornerRadius > 0 && tabs.length > 0) updateTabs();
		return isMinimized;
	}
}