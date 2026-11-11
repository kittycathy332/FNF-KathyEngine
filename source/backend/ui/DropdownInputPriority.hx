package backend.ui;

import flixel.FlxG;
import flixel.ui.FlxButton;
import flixel.addons.ui.FlxUIButton;
import flixel.addons.ui.FlxUICheckBox;
import flixel.addons.ui.FlxUIInputText;
import flixel.addons.ui.FlxUINumericStepper;

/**
 * 「下拉框输入优先级」全局守卫。
 *
 * 引擎里并存三套下拉框（0.6.3 / 0.7.3 的 FlxUIDropDownMenuCustom、1.0 的
 * PsychUIDropDownMenu、1.0.4 原版的 VUIDropDownMenu），它们的列表都是画在
 * 按钮之上的独立图层。flixel 的鼠标输入是「每个对象各自检测」，没有按 z-order
 * 消费事件的机制，于是点在被列表盖住的按钮判定区时，列表项与被盖住的按钮会
 * 在同一帧一起响应。flixel-ui 的 FlxUI.forceFocus() 对这些按钮也不起作用。
 *
 * 屏蔽范围是「指针所在位置」，不是整个编辑器：只有当鼠标/触点落在展开列表
 * 实际覆盖的矩形内时才生效。列表外的所有 UI（按钮、输入框、stepper、网格）
 * 一律照常可操作 —— 下拉框优先不等于全局模态。
 *
 * 命中判定同时给三处使用：
 *   - preUpdate 的 sync()：决定是否冻结 flixel-ui 控件（063/073 用）；
 *   - PsychUI* / VUI* 控件 update() 开头的 shouldBlockInput()（新版用）；
 *   - 各编辑器的 suppressMouse / ignoreClickForThisFrame。
 * 每帧只计算一次并缓存，避免 10 个控件各遍历一遍列表项。
 *
 * 冻结（active=false + 摘除点击回调 / 事件广播，收起后原样还原）只对
 * 063 / 073 的 flixel-ui 控件执行。新版 PsychUI* / VUI* 的 10 个控件已在自己
 * update() 开头装了 shouldBlockInput() 自检闸门，不需要再冻结；而且一旦冻结
 * PsychUIBox / PsychUITab 这类布局容器，FlxTypedGroup.update() 就不再向下分发，
 * 连展开中的下拉框和它的选项 item 都会收不到 update —— 列表能拉下来却点不动。
 * 收起当帧仍屏蔽一次点击（closing 标志），下一帧 preUpdate 自动清除。
 *
 * 移动端滑动：FlxUIDropDownMenuCustom.update() 读全局 FlxG.swipes，与对象
 * active 无关。但 active=false 会阻止 FlxState/FlxGroup 把 update() 往下传，
 * 所以下拉框的祖先容器绝不能被冻结 —— protected（整棵子树放行）与
 * keepActive（只保活当前对象、仍继续递归）两种豁免必须分开。
 */
class DropdownInputPriority
{
	static var openMenus:haxe.ds.ObjectMap<Dynamic, Bool>;
	/** 被冻结的对象 -> 冻结前的 active 值 */
	static var frozen:haxe.ds.ObjectMap<Dynamic, Bool>;
	/** 被摘除回调的对象 -> [{o:字段所属对象, f:字段名, v:原值}] */
	static var frozenCallbacks:haxe.ds.ObjectMap<Dynamic, Array<Dynamic>>;
	/** 上一次冻结时「展开中的下拉框」集合，用于检测同帧内 A 收起 / B 展开 */
	static var lastOpen:haxe.ds.ObjectMap<Dynamic, Bool>;
	/** 当前展开下拉框的整棵子树，供 PsychUI* / VUI* 控件在 update() 里自查放行 */
	static var currentProtected:haxe.ds.ObjectMap<Dynamic, Bool> = new haxe.ds.ObjectMap();
	static var frozenState:Bool = false;
	/** 收起后的当帧仍屏蔽（吞掉本次点击），下一帧 preUpdate 自动清除 */
	static var closing:Bool = false;
	/** 指针命中判定的每帧缓存：10 个控件都会查，一帧只算一次 */
	static var hitCacheValid:Bool = false;
	static var hitCache:Bool = false;
	static var lastState:flixel.FlxState = null;
	static var initialized:Bool = false;
	/** 新版 UI 跳过冻结的一次性诊断标记，避免每帧刷盘 */
	static var selfGuardLogged:Bool = false;

	static function init():Void
	{
		if (initialized) return;
		initialized = true;
		openMenus = new haxe.ds.ObjectMap();
		frozen = new haxe.ds.ObjectMap();
		frozenCallbacks = new haxe.ds.ObjectMap();
		lastOpen = new haxe.ds.ObjectMap();
		currentProtected = new haxe.ds.ObjectMap();
		FlxG.signals.preUpdate.add(onPreUpdate);
		FlxG.signals.preStateSwitch.add(reset);
	}

	/** 每帧开头：使位置缓存失效、清掉「收起当帧」标志，再执行冻结同步。 */
	static function onPreUpdate():Void
	{
		hitCacheValid = false;
		closing = false;
		sync();
	}

	/**
	 * 供 PsychUI* / VUI* 控件在自身 update() 开头调用：本对象此刻是否该让位给
	 * 展开中的下拉框。这是「结构性根治」——不依赖 flixel 的 active 分发、
	 * 不依赖守卫能否遍历到控件，控件自己就不再读 FlxG.mouse 去抢点击/焦点。
	 *
	 * 展开中的下拉框及其整棵子树（含选项 item）放行；收起后的当帧仍然返回
	 * true（frozenState 要到下一帧 preUpdate 才清），因此「收起 + 吞掉点击」
	 * 的语义在这里同样成立。
	 */
	public static function shouldBlockInput(obj:Dynamic):Bool
	{
		init();
		if (obj == null) return false;
		if (!isOpen() && !closing) return false;
		if (currentProtected != null && currentProtected.exists(obj)) return false;
		// 收起当帧：吞掉这一次点击，避免它落到刚被列表盖住的控件上
		if (!isOpen()) return true;
		// 展开中：只有指针真的落在列表覆盖区里才让位，区域外一切照常
		return pointerInsideOpenList();
	}

	/** 下拉框展开 / 收起时调用。幂等：滚轮滚动列表会反复传 true，不会重复计数。 */
	public static function setOpen(menu:Dynamic, open:Bool):Void
	{
		init();
		if (menu == null) return;
		var wasAny:Bool = isOpen();
		var was:Bool = openMenus.exists(menu);
		if (open) openMenus.set(menu, true);
		else openMenus.remove(menu);
		var now:Bool = openMenus.exists(menu);
		// 立刻维护放行名单：展开发生在按钮 update() 里，不能等下一帧 preUpdate，
		// 否则同帧其它控件自查时下拉框自己也会被误挡。状态没翻转时（滚轮反复
		// 传 true）不重建，避免每帧遍历列表项。
		if (was != now)
		{
			rebuildProtected();
			dbg('setOpen ' + shortName(menu) + ' open=' + open
				+ ' total=' + count(openMenus) + ' protected=' + count(currentProtected));
		}
		var nowAny:Bool = isOpen();
		if (wasAny && !nowAny) closing = true;
		hitCacheValid = false;
	}

	/** 由当前展开集合重建「整棵子树」放行名单。 */
	static function rebuildProtected():Void
	{
		currentProtected = new haxe.ds.ObjectMap();
		for (m in openMenus.keys()) collectSubtree(m, currentProtected);
	}

	/** 是否「有下拉框展开」（不表示要冻结）。 */
	public static function isOpen():Bool
	{
		init();
		for (k in openMenus.keys()) return true;
		return false;
	}

	/**
	 * 下拉框「展开」入口的闸门（063 / 073 的 FlxUIDropDownMenuCustom 用）。
	 *
	 * 现象：A 展开时点它的选项，若该选项位置正好压着另一个下拉框 B 的 header，
	 * B 的 header 会在同一帧也收到这次点击，于是 A 选中 + B 被拉下同时发生。
	 * 只靠 preUpdate 的 active 冻结 / 回调摘除不够：preUpdate 早于 updateInput()，
	 * 读到的是上一帧指针位置；触控或「移动+点击」在同一帧完成时整轮冻结会漏掉。
	 * 这里直接卡在展开入口，与输入分发方式无关。
	 *
	 * 收起（vis=false）永远不拦，否则下拉框会关不掉。
	 */
	public static function shouldBlockDropdownOpen(menu:Dynamic):Bool
	{
		init();
		if (menu == null) return false;
		if (openMenus.exists(menu)) return false; // 自己已展开：滚轮 / 过滤刷新放行
		if (closing) return true;                 // 本帧刚有下拉框收起：吞掉这次点击
		for (m in openMenus.keys())
		{
			if (m != null && m != menu) return true; // 不允许两个下拉框同时展开
		}
		return false;
	}

	/**
	 * 指针是否落在任一展开列表的覆盖区域内。结果每帧缓存一次。
	 * 这就是「下拉框优先」的唯一生效范围：列表矩形之内，别的控件让位；
	 * 矩形之外，编辑器完全正常。
	 */
	public static function pointerInsideOpenList():Bool
	{
		init();
		if (!isOpen()) return false;
		if (hitCacheValid) return hitCache;
		hitCache = computePointerHit();
		hitCacheValid = true;
		return hitCache;
	}

	static function computePointerHit():Bool
	{
		for (m in openMenus.keys())
		{
			var cam:Dynamic = null;
			try cam = Reflect.field(m, 'camera') catch (e:Dynamic) {}
			if (cam == null) cam = FlxG.camera;

			// 新版 / 063 的可见选项按钮：坐标就是列表实际覆盖区
			var items:Dynamic = Reflect.field(m, '_items');
			if (items == null) items = Reflect.field(m, 'list');
			if (items != null && Std.isOfType(items, Array))
			{
				for (it in (cast items:Array<Dynamic>))
				{
					if (it == null) continue;
					if (Reflect.field(it, 'visible') != true || Reflect.field(it, 'active') != true) continue;
					if (hitSprite(it, cam)) return true;
				}
			}
			// 新版列表背景：展开时 scale.y 被拉伸到覆盖全部选项
			var bg:Dynamic = Reflect.field(m, 'bg');
			if (bg != null && hitSprite(bg, cam)) return true;
			// 063 / 073 列表底板
			var panel:Dynamic = Reflect.field(m, 'dropPanel');
			if (panel != null && Reflect.field(panel, 'visible') == true && hitSprite(panel, cam)) return true;
		}
		return false;
	}

	static function hitSprite(o:Dynamic, cam:Dynamic):Bool
	{
		if (o == null) return false;
		try return FlxG.mouse.overlaps(o, cam) catch (e:Dynamic) { return false; }
	}

	static function sync():Void
	{
		var state:flixel.FlxState = FlxG.state;
		if (state != lastState)
		{
			// 切 state：旧 state 的对象可能已销毁，直接丢弃冻结记录按新 state 重算
			frozen = new haxe.ds.ObjectMap();
			frozenCallbacks = new haxe.ds.ObjectMap();
			frozenState = false;
			lastOpen = new haxe.ds.ObjectMap();
			lastState = state;
		}

		// 冻结条件 = 指针在列表覆盖区内。鼠标一移出列表，本帧就恢复全部控件。
		// 这里直接算、不写每帧缓存：preUpdate 早于 updateInput()，鼠标位置还是
		// 上一帧的；缓存留给 state.update() 期间的第一个控件调用，那时输入已刷新。
		if (!computePointerHit())
		{
			if (frozenState)
			{
				restore();
				frozenState = false;
				lastOpen = new haxe.ds.ObjectMap();
			}
			return;
		}

		// 新版 / 1.0.4 的 PsychUI* / VUI* 控件自带 shouldBlockInput() 闸门，
		// 这里绝不能冻结：日志实测 frozen 里全是 PsychUIBox / PsychUITab 这类
		// 布局容器（keep=0），它们一旦 active=false 就切断整条 update 分发链，
		// 下拉框自己和选项 item 都收不到帧更新，表现为「选项无法点击」。
		// 只保留状态查询（isOpen / pointerInsideOpenList / currentProtected / closing）。
		if (selfGuardedMenus())
		{
			if (!selfGuardLogged)
			{
				selfGuardLogged = true;
				dbg('SKIP-FREEZE self-guarded PsychUI*/VUI* UI: containers stay active so dropdown items receive update()');
			}
			if (frozenState)
			{
				restore();
				frozenState = false;
				lastOpen = new haxe.ds.ObjectMap();
			}
			return;
		}

		// 展开集合没变：维持现状，省掉整树遍历；但仍要压住输入框焦点
		if (frozenState && sameSet(openMenus, lastOpen))
		{
			clearFocus();
			return;
		}

		// 集合变化：先恢复上一轮冻结，再按新的展开对象重算。
		// 同一帧里 A 收起 + B 展开时 frozenState 仍是 true，但受保护子树已经换了；
		// 不重算就会把 B 的列表项沿用 A 那轮的冻结状态，导致 B 既不能点也不能滑动。
		if (frozenState) restore();
		frozenState = true;
		lastOpen = new haxe.ds.ObjectMap();
		for (m in openMenus.keys()) lastOpen.set(m, true);

		rebuildProtected();
		var protected:haxe.ds.ObjectMap<Dynamic, Bool> = currentProtected;

		// 祖先只「保活」不「跳过递归」：冻结任何容器都会让 flixel 不再把
		// update() 往下传，下拉框的触控滑动（FlxG.swipes）就收不到了。
		var keepActive:haxe.ds.ObjectMap<Dynamic, Bool> = new haxe.ds.ObjectMap();
		markAncestors(state, protected, keepActive, new haxe.ds.ObjectMap());

		var stats:Dynamic = {nodes: 0, frozen: 0, callbacks: 0, cbObjects: 0, names: []};
		walk(state, protected, keepActive, new haxe.ds.ObjectMap(), stats);
		dbg((stats.frozen > 0 ? 'FREEZE' : 'FREEZE-EMPTY!')
			+ ' state=' + shortName(state) + ' nodes=' + stats.nodes
			+ ' protected=' + count(protected) + ' keep=' + count(keepActive)
			+ ' frozen=' + stats.frozen + ' callbackFields=' + stats.callbacks
			+ ' callbackObjects=' + stats.cbObjects
			+ ' classes=[' + stats.names.join(',') + ']');
	}

	/**
	 * 当前展开的是否全是自带 shouldBlockInput() 闸门的新版下拉框。
	 * 063 / 073 的 FlxUIDropDownMenuCustom 没有闸门，仍需走 active 冻结。
	 */
	static function selfGuardedMenus():Bool
	{
		var found:Bool = false;
		for (m in openMenus.keys())
		{
			var cn:String = '';
			try
			{
				var c:Class<Dynamic> = Type.getClass(m);
				if (c != null) cn = Type.getClassName(c);
			}
			catch (e:Dynamic) {}
			if (cn == null) cn = '';
			if (cn.indexOf('PsychUIDropDownMenu') < 0 && cn.indexOf('VUIDropDownMenu') < 0)
				return false;
			found = true;
		}
		return found;
	}

	/** 两个 ObjectMap 是否含有完全相同的 key 集合。 */
	static function sameSet(a:haxe.ds.ObjectMap<Dynamic, Bool>, b:haxe.ds.ObjectMap<Dynamic, Bool>):Bool
	{
		var na:Int = 0;
		for (k in a.keys()) na++;
		var nb:Int = 0;
		for (k in b.keys()) nb++;
		if (na != nb) return false;
		for (k in a.keys()) if (!b.exists(k)) return false;
		return true;
	}

	static function count(m:haxe.ds.ObjectMap<Dynamic, Bool>):Int
	{
		var n:Int = 0;
		for (k in m.keys()) n++;
		return n;
	}

	static function shortName(obj:Dynamic):String
	{
		if (obj == null) return 'null';
		try
		{
			var c:Class<Dynamic> = Type.getClass(obj);
			if (c != null)
			{
				var n:String = Type.getClassName(c);
				if (n != null)
				{
					var parts:Array<String> = n.split('.');
					return parts[parts.length - 1];
				}
			}
		}
		catch (e:Dynamic) {}
		return Std.string(obj);
	}

	/** 诊断：只在 Windows 桌面写文件，且仅在状态变化时写，不会每帧刷盘。 */
	static function dbg(msg:String):Void
	{
		#if windows
		try
		{
			var dir:String = '';
			try dir = haxe.io.Path.directory(Sys.programPath()) catch (e:Dynamic) {}
			var path:String = (dir.length > 0 ? dir + '/' : '') + 'dropdown_priority.log';
			var prev:String = sys.FileSystem.exists(path) ? sys.io.File.getContent(path) : '';
			if (prev.length > 120000) prev = prev.substr(prev.length - 60000);
			sys.io.File.saveContent(path, prev + '[' + Date.now().toString() + '] ' + msg + '\n');
		}
		catch (e:Dynamic) {}
		#end
	}

	static function restore():Void
	{
		dbg('RESTORE active=' + count(frozen) + ' callbacks=' + countCB());
		for (o in frozen.keys())
		{
			try o.active = frozen.get(o) catch (e:Dynamic) {}
		}
		frozen = new haxe.ds.ObjectMap();
		restoreCallbacks();
	}

	static function countCB():Int
	{
		if (frozenCallbacks == null) return 0;
		var n:Int = 0;
		for (k in frozenCallbacks.keys()) n++;
		return n;
	}

	/** 摘除点击回调：即使容器绕过 active 调用了 update()，也不会执行业务逻辑。 */
	static function disableCallbacks(obj:Dynamic, stats:Dynamic):Void
	{
		var saved:Array<Dynamic> = [];
		// StyledButton / PsychUIButton / VUIButton：public var onClick
		try
		{
			if (Reflect.hasField(obj, 'onClick'))
			{
				var v:Dynamic = Reflect.field(obj, 'onClick');
				if (v != null)
				{
					Reflect.setField(obj, 'onClick', null);
					saved.push({o: obj, f: 'onClick', v: v});
					stats.callbacks++;
				}
			}
		}
		catch (e:Dynamic) {}
		// FlxButton / FlxUIButton：onUp.callback（FlxButtonEvent.callback 可写）
		try
		{
			var ev:Dynamic = Reflect.field(obj, 'onUp');
			if (ev != null && Reflect.hasField(ev, 'callback'))
			{
				var v:Dynamic = Reflect.field(ev, 'callback');
				if (v != null)
				{
					Reflect.setField(ev, 'callback', null);
					saved.push({o: ev, f: 'callback', v: v});
					stats.callbacks++;
				}
			}
		}
		catch (e:Dynamic) {}
		// 自绘控件的事件广播：PsychUIButton / VUIButton 即使 onClick 被摘除，
		// update() 里仍会 PsychUIEventHandler.event(CLICK_EVENT, this) 把点击
		// 送到 ChartingState.UIEvent()。把广播开关一并临时关掉。
		try
		{
			for (field in ['broadcastButtonEvent', 'broadcastBoxEvents', 'broadcastItemEvent'])
			{
				if (!Reflect.hasField(obj, field)) continue;
				var bv:Dynamic = Reflect.field(obj, field);
				if (bv == true)
				{
					Reflect.setField(obj, field, false);
					saved.push({o: obj, f: field, v: bv});
					stats.callbacks++;
				}
			}
		}
		catch (e:Dynamic) {}
		if (saved.length > 0) frozenCallbacks.set(obj, saved);
	}

	static function restoreCallbacks():Void
	{
		if (frozenCallbacks == null) return;
		for (list in frozenCallbacks)
		{
			if (list == null) continue;
			for (s in list)
			{
				try Reflect.setField(s.o, s.f, s.v) catch (e:Dynamic) {}
			}
		}
		frozenCallbacks = new haxe.ds.ObjectMap();
	}

	/** 展开期间压住输入框焦点，防止「纯文本框」被穿透聚焦。 */
	static function clearFocus():Void
	{
		for (o in frozen.keys())
		{
			try
			{
				if (Reflect.hasField(o, 'hasFocus') && Reflect.field(o, 'hasFocus') == true)
					Reflect.setField(o, 'hasFocus', false);
			}
			catch (e:Dynamic) {}
		}
	}

	static function reset():Void
	{
		openMenus = new haxe.ds.ObjectMap();
		frozen = new haxe.ds.ObjectMap();
		frozenCallbacks = new haxe.ds.ObjectMap();
		lastOpen = new haxe.ds.ObjectMap();
		currentProtected = new haxe.ds.ObjectMap();
		frozenState = false;
		closing = false;
		hitCacheValid = false;
		hitCache = false;
		selfGuardLogged = false;
		lastState = null;
	}

	/** 取 group 的 members；兼容 getter 属性与 FlxSpriteGroup 内部 group。 */
	static function members(obj:Dynamic):Array<Dynamic>
	{
		if (obj == null) return null;
		try
		{
			var v:Dynamic = Reflect.field(obj, 'members');
			if (v == null) v = Reflect.getProperty(obj, 'members');
			if (v != null && Std.isOfType(v, Array))
			{
				var arr:Array<Dynamic> = cast v;
				return arr;
			}
			// FlxSpriteGroup 把成员放在内部 group.members
			var g:Dynamic = Reflect.field(obj, 'group');
			if (g != null)
			{
				var gv:Dynamic = Reflect.field(g, 'members');
				if (gv != null && Std.isOfType(gv, Array))
				{
					var arr2:Array<Dynamic> = cast gv;
					return arr2;
				}
			}
		}
		catch (e:Dynamic) { return null; }
		return null;
	}

	/** 把展开中的下拉框及其整棵子树标记为「不冻结」。 */
	static function collectSubtree(obj:Dynamic, out:haxe.ds.ObjectMap<Dynamic, Bool>):Void
	{
		if (obj == null || out.exists(obj)) return;
		out.set(obj, true);
		var kids:Array<Dynamic> = members(obj);
		if (kids != null) for (k in kids) collectSubtree(k, out);
	}

	/**
	 * 标记所有「路径上能到达受保护对象」的祖先，让它们只保活、不被冻结。
	 * cache 记录已算结果，兼容一个对象挂在多个 group 下的情况，并防止环。
	 */
	static function markAncestors(obj:Dynamic, prot:haxe.ds.ObjectMap<Dynamic, Bool>,
			keep:haxe.ds.ObjectMap<Dynamic, Bool>, cache:haxe.ds.ObjectMap<Dynamic, Bool>):Bool
	{
		if (obj == null) return false;
		if (prot.exists(obj)) return true;
		if (cache.exists(obj)) return cache.get(obj) == true;
		cache.set(obj, false); // 先占位防环
		var hit:Bool = false;
		var kids:Array<Dynamic> = members(obj);
		if (kids != null) for (k in kids) if (markAncestors(k, prot, keep, cache)) hit = true;
		cache.set(obj, hit);
		if (hit) keep.set(obj, true);
		return hit;
	}

	static function walk(obj:Dynamic, prot:haxe.ds.ObjectMap<Dynamic, Bool>,
			keep:haxe.ds.ObjectMap<Dynamic, Bool>, seen:haxe.ds.ObjectMap<Dynamic, Bool>, stats:Dynamic):Void
	{
		if (obj == null || seen.exists(obj)) return;
		seen.set(obj, true);
		stats.nodes++;
		if (prot.exists(obj)) return; // 展开的下拉框整棵子树放行

		// keep 中的是下拉框的祖先容器：不能冻结 active（否则 flixel 不再把
		// update() 往下传），但仍要摘掉它自己的回调/广播，避免容器级拖拽或
		// 点击穿透。其余控件照常「active 冻结 + 摘回调」双保险。
		if (!keep.exists(obj) && isInteractive(obj))
		{
			var was:Bool = true;
			try was = obj.active catch (e:Dynamic) {}
			frozen.set(obj, was);
			try obj.active = false catch (e:Dynamic) {}
			stats.frozen++;
			if (stats.names.length < 25) stats.names.push(shortName(obj));
		}
		// 对所有非 protected 对象都尝试摘除：不依赖 isInteractive() 判定，
		// 任何带 onClick / onUp.callback / broadcast* 的对象都不会漏。
		var before:Int = stats.callbacks;
		disableCallbacks(obj, stats);
		if (stats.callbacks > before) stats.cbObjects++;
		var kids:Array<Dynamic> = members(obj);
		if (kids != null) for (k in kids) walk(k, prot, keep, seen, stats);
	}

	static function isInteractive(obj:Dynamic):Bool
	{
		if (obj == null) return false;
		// 下拉框的选项 item 永远不能被冻结 / 摘 onClick，否则「列表拉下来了
		// 但选项点不动」。正常路径下它们已在 currentProtected 里，这里是兜底。
		var itemClass:String = '';
		try
		{
			var ic:Class<Dynamic> = Type.getClass(obj);
			if (ic != null) itemClass = Type.getClassName(ic);
		}
		catch (e:Dynamic) {}
		if (itemClass != null && itemClass.indexOf('DropDownItem') >= 0) return false;
		// flixel / flixel-ui 原生控件
		if (Std.isOfType(obj, FlxButton)) return true;
		if (Std.isOfType(obj, FlxUIButton)) return true;
		if (Std.isOfType(obj, FlxUICheckBox)) return true;
		if (Std.isOfType(obj, FlxUIInputText)) return true;
		if (Std.isOfType(obj, FlxUINumericStepper)) return true;
		// 自绘按钮 / 输入框：用公开字段识别，避免 backend 包反向依赖编辑器包
		if (Std.isOfType(obj, StyledButton)) return true;
		if (Reflect.hasField(obj, 'onClick')) return true;  // PsychUIButton / VUIButton / StyledButton
		if (Reflect.hasField(obj, 'onUp')) return true;
		if (Reflect.hasField(obj, 'hasFocus')) return true; // flixel-ui 各类输入框 / stepper
		// 新版 / 1.0.4 的自绘控件体系（PsychUI* / VUI*）全是 FlxSpriteGroup，
		// 其中 InputText / CheckBox / Stepper / Slider 既没有 onClick/onUp，
		// 也没有 hasFocus 实例字段 —— 焦点走的是静态 focusOn，在 update() 里
		// 直接 `focusOn = this` 抢焦点。上面几条全识别不到，导致「纯文本框」
		// 在下拉框展开时从未被冻结，点击选项时照样穿透。按类名整系命中。
		var cn:String = '';
		try
		{
			var c:Class<Dynamic> = Type.getClass(obj);
			if (c != null) cn = Type.getClassName(c);
		}
		catch (e:Dynamic) {}
		if (cn != null && (cn.indexOf('PsychUI') >= 0 || cn.indexOf('VUI') >= 0)) return true;
		return false;
	}
}
