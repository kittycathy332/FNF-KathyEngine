package substates;

import flixel.util.FlxDestroyUtil;
import backend.Language;
import backend.Paths;
import backend.ui.PsychUIButton;
import backend.ui.PsychUIRadioGroup;

/**
 * 回放选择器 Substate：左侧回放时间列表，右侧详情面板（准度/分数/连击/MISS/判定/变速/版本）。
 * 排序可切换时间/准度。ESC 或取消按钮关闭，选中后回调 onSelect(path)。
 */
class ReplayPickerSubState extends MusicBeatSubstate
{
	var matchedList:Array<Dynamic>;
	var onSelect:String->Void;

	var sortMode:String = 'time';
	var sorted:Array<Dynamic>;

	// UI 控件
	var bg:FlxSprite;
	var titleText:FlxText;
	var radioGrp:PsychUIRadioGroup;
	var detailText:FlxText;
	var sortBtn:PsychUIButton;

	var sizeX:Float = 820;
	var sizeY:Float = 520;
	var maxItems:Int;

	public function new(matchedList:Array<Dynamic>, onSelect:String->Void)
	{
		super();
		this.matchedList = matchedList;
		this.onSelect = onSelect;
		this.sorted = matchedList.copy();
		this.maxItems = Std.int(Math.min(6, sorted.length));
	}

	override function create()
	{
		controls.isInSubstate = true;
		cameras = [FlxG.cameras.list[FlxG.cameras.list.length - 1]];
		super.create();

		// 半透明黑底
		bg = new FlxSprite().makeGraphic(Std.int(sizeX), Std.int(sizeY), FlxColor.BLACK);
		bg.alpha = 0.85;
		bg.screenCenter();
		bg.cameras = cameras;
		add(bg);

		// 标题
		titleText = new FlxText(0, bg.y + 16, 400, Language.get('freeplay_replay_picker_title'), 24);
		titleText.font = Paths.font(Language.get('uitab_font'));
		titleText.screenCenter(X);
		titleText.alignment = CENTER;
		titleText.cameras = cameras;
		add(titleText);

		// 排序切换按钮
		sortBtn = new PsychUIButton(0, bg.y + 24, Language.get('replay_sort_time'), function() {
			sortMode = (sortMode == 'time') ? 'acc' : 'time';
			sortBtn.label = (sortMode == 'time') ? Language.get('replay_sort_time') : Language.get('replay_sort_acc');
			resort();
			radioGrp.labels = rebuildLabels();
			radioGrp.checked = 0;
			restyleRadios();
			if (sorted.length > 0)
				detailText.text = buildDetail(sorted[0]);
		}, 180, 36);
		sortBtn.text.size = 24;
		sortBtn.text.antialiasing = false;
		sortBtn.resize(180, 36);
		sortBtn.cameras = cameras;
		sortBtn.x = bg.x + sizeX - 200;
		add(sortBtn);

		// 左侧回放列表
		radioGrp = new PsychUIRadioGroup(0, 0, rebuildLabels(), 56, maxItems, false, 280);
		radioGrp.checked = 0;
		radioGrp.x = bg.x + 20;
		radioGrp.y = bg.y + 70;
		radioGrp.cameras = cameras;
		add(radioGrp);
		restyleRadios();

		// 右侧详情面板背景
		var detailBG:FlxSprite = new FlxSprite();
		detailBG.makeGraphic(500, 336, FlxColor.BLACK);
		detailBG.alpha = 0.5;
		detailBG.x = bg.x + sizeX - 520;
		detailBG.y = bg.y + 70;
		detailBG.cameras = cameras;
		add(detailBG);

		// 右侧详情文本
		detailText = new FlxText(detailBG.x + 10, detailBG.y + 10, 480, buildDetail(sorted[0]), 24);
		detailText.font = Paths.font(Language.get('uitab_font'));
		detailText.antialiasing = false;
		detailText.cameras = cameras;
		add(detailText);

		// 选中回放时更新详情
		radioGrp.onClick = function() {
			var idx:Int = radioGrp.checked;
			if (idx >= 0 && idx < sorted.length)
				detailText.text = buildDetail(sorted[idx]);
		};

		// 播放按钮
		var btn:PsychUIButton = new PsychUIButton(0, bg.y + sizeY - 55, Language.get('freeplay_replay_play'), function() {
			var idx:Int = radioGrp.checked;
			if (idx < 0 || idx >= sorted.length) return;
			var path:String = Std.string(Reflect.field(sorted[idx], 'path'));
			controls.isInSubstate = false;
			close();
			if (onSelect != null) onSelect(path);
		}, 200, 48);
		btn.text.size = 24;
		btn.text.antialiasing = false;
		btn.resize(200, 48);
		btn.cameras = cameras;
		btn.x = bg.x + sizeX / 2 - 220;
		add(btn);

		// 取消按钮
		var cancelBtn:PsychUIButton = new PsychUIButton(0, bg.y + sizeY - 55, Language.get('freeplay_replay_cancel'), function() {
			controls.isInSubstate = false;
			close();
		}, 200, 48);
		cancelBtn.text.size = 24;
		cancelBtn.text.antialiasing = false;
		cancelBtn.resize(200, 48);
		cancelBtn.normalStyle.bgColor = FlxColor.RED;
		cancelBtn.normalStyle.textColor = FlxColor.WHITE;
		cancelBtn.cameras = cameras;
		cancelBtn.x = bg.x + sizeX / 2 + 20;
		add(cancelBtn);
	}

	/** 左侧列表文字放大到 24px，圆圈放大 2x */
	function restyleRadios():Void
	{
		if (radioGrp == null) return;
		radioGrp.space = 56;
		for (radio in radioGrp.radios)
		{
			if (radio == null) continue;
			radio.text.size = 24;
			radio.box.scale.set(2, 2);
		}
	}

	function resort():Void
	{
		if (sortMode == 'acc')
		{
			sorted.sort(function(a:Dynamic, b:Dynamic):Int {
				var ma:Dynamic = Reflect.hasField(a, 'meta') ? Reflect.field(a, 'meta') : null;
				var mb:Dynamic = Reflect.hasField(b, 'meta') ? Reflect.field(b, 'meta') : null;
				var aa:Null<Float> = fieldFloat(ma, 'accuracyPercent');
				var bb:Null<Float> = fieldFloat(mb, 'accuracyPercent');
				if (aa == null && bb == null) return 0;
				if (aa == null) return 1;
				if (bb == null) return -1;
				return (bb > aa ? 1 : (bb < aa ? -1 : 0));
			});
		}
		else
		{
			sorted.sort(function(a:Dynamic, b:Dynamic):Int {
				var am:Float = Reflect.hasField(a, 'mtime') ? Std.parseFloat(Std.string(Reflect.field(a, 'mtime'))) : 0;
				var bm:Float = Reflect.hasField(b, 'mtime') ? Std.parseFloat(Std.string(Reflect.field(b, 'mtime'))) : 0;
				return (bm > am ? 1 : (bm < am ? -1 : 0));
			});
		}
	}

	function rebuildLabels():Array<String>
	{
		var arr:Array<String> = [];
		for (it in sorted) arr.push(shortTime(Std.string(Reflect.field(it, 'name'))));
		return arr;
	}

	// ---- 时间戳辅助 ----

	function extractStamp(name:String):String
	{
		var s:String = name;
		var idx:Int = s.lastIndexOf('.replay.json');
		if (idx >= 0)
			s = s.substr(0, idx);
		if (s.length >= 19)
		{
			var tail:String = s.substr(s.length - 19, 19);
			if (tail.charAt(4) == '-' && tail.charAt(7) == '-' && tail.charAt(10) == '_'
				&& tail.charAt(13) == '-' && tail.charAt(16) == '-')
				return tail;
		}
		return '';
	}

	function shortTime(name:String):String
	{
		var st:String = extractStamp(name);
		if (st.length >= 16)
			return st.substr(5, 5) + ' ' + st.substr(11, 2) + ':' + st.substr(14, 2);
		return (st.length > 0 ? st : '—');
	}

	function fullTime(name:String):String
	{
		var st:String = extractStamp(name);
		if (st.length == 19)
			return st.substr(0, 10) + ' ' + st.substr(11, 2) + ':' + st.substr(14, 2) + ':' + st.substr(17, 2);
		return (st.length > 0 ? st : '—');
	}

	// ---- 评级与字段读取 ----

	function rankLetter(acc01:Float):String
	{
		if (acc01 >= 0.999935) return 'AAAAA';
		if (acc01 >= 0.99980)  return 'AAAA.';
		if (acc01 >= 0.99970)  return 'AAAA';
		if (acc01 >= 0.99955)  return 'AAA:';
		if (acc01 >= 0.9990)   return 'AAA.';
		if (acc01 >= 0.9970)   return 'AAA';
		if (acc01 >= 0.990)    return 'AA:';
		if (acc01 >= 0.965)    return 'AA.';
		if (acc01 >= 0.93)     return 'AA';
		if (acc01 >= 0.90)      return 'A:';
		if (acc01 >= 0.85)     return 'A.';
		if (acc01 >= 0.80)     return 'A';
		if (acc01 >= 0.70)      return 'B';
		if (acc01 >= 0.60)      return 'C';
		return 'D';
	}

	function fieldFloat(meta:Dynamic, field:String):Null<Float>
	{
		if (meta == null || !Reflect.hasField(meta, field)) return null;
		var v = Reflect.field(meta, field);
		if (v == null) return null;
		try { return Std.parseFloat(Std.string(v)); } catch (e:Dynamic) { return null; }
	}

	function buildDetail(entry:Dynamic):String
	{
		var meta:Dynamic = (entry != null && Reflect.hasField(entry, 'meta')) ? Reflect.field(entry, 'meta') : null;
		var name:String = (entry != null && Reflect.hasField(entry, 'name')) ? Std.string(Reflect.field(entry, 'name')) : '';
		var lines:Array<String> = [];

		// 时区
		var tzStr:String = '';
		if (meta != null && Reflect.hasField(meta, 'tzOffset'))
		{
			try
			{
				var tzMin:Float = Std.parseFloat(Std.string(Reflect.field(meta, 'tzOffset')));
				var tzHrs:Float = -tzMin / 60;
				var sign:String = tzHrs >= 0 ? '+' : '-';
				var absHrs:Float = Math.abs(tzHrs);
				var hrs:Int = Std.int(Math.floor(absHrs));
				var mins:Int = Std.int(Math.round((absHrs - hrs) * 60));
				tzStr = ' (UTC' + sign + Std.string(hrs);
				if (mins != 0) tzStr += ':' + (mins < 10 ? '0' : '') + Std.string(mins);
				tzStr += ')';
			}
			catch (e:Dynamic) { tzStr = ''; }
		}
		lines.push(Language.get('replay_detail_time') + ': ' + fullTime(name) + tzStr);

		var acc:Null<Float> = fieldFloat(meta, 'accuracyPercent');
		if (acc != null)
		{
			var accPct:Float = Math.floor(acc * 10000) / 100;
			lines.push(Language.get('replay_detail_accuracy') + ': ' + Std.string(accPct) + '%   [' + rankLetter(acc) + ']');
		}
		else lines.push(Language.get('replay_detail_accuracy') + ': —');

		var sc:Null<Float> = fieldFloat(meta, 'score');
		lines.push(Language.get('replay_detail_score') + ': ' + (sc != null ? Std.string(Std.int(sc)) : '—'));

		var mc:Null<Float> = fieldFloat(meta, 'maxCombo');
		lines.push(Language.get('replay_detail_maxcombo') + ': ' + (mc != null ? Std.string(Std.int(mc)) : '—'));

		var ms:Null<Float> = fieldFloat(meta, 'misses');
		lines.push(Language.get('replay_detail_misses') + ': ' + (ms != null ? Std.string(Std.int(ms)) : '—'));

		var jb:Dynamic = (meta != null && Reflect.hasField(meta, 'judgeBreakdown')) ? Reflect.field(meta, 'judgeBreakdown') : null;
		if (jb != null)
		{
			var jl:Array<String> = [];
			var p:Null<Float> = fieldFloat(jb, 'perfect');
			var s:Null<Float> = fieldFloat(jb, 'sick');
			var g:Null<Float> = fieldFloat(jb, 'good');
			var b:Null<Float> = fieldFloat(jb, 'bad');
			var sh:Null<Float> = fieldFloat(jb, 'shit');
			if (p != null) jl.push('Perfect ' + Std.string(Std.int(p)));
			if (s != null) jl.push('Sick ' + Std.string(Std.int(s)));
			if (g != null) jl.push('Good ' + Std.string(Std.int(g)));
			if (b != null) jl.push('Bad ' + Std.string(Std.int(b)));
			if (sh != null) jl.push('Shit ' + Std.string(Std.int(sh)));
			lines.push(Language.get('replay_detail_judges') + ': ' + (jl.length > 0 ? jl.join('  ·  ') : '—'));
		}
		else lines.push(Language.get('replay_detail_judges') + ': —');

		var gs:Dynamic = (meta != null && Reflect.hasField(meta, 'gameplaySettings')) ? Reflect.field(meta, 'gameplaySettings') : null;
		if (gs != null)
		{
			var sp:String = Reflect.hasField(gs, 'songspeed') ? Std.string(Reflect.field(gs, 'songspeed')) : '—';
			var scr:String = Reflect.hasField(gs, 'scrollspeed') ? Std.string(Reflect.field(gs, 'scrollspeed')) : '—';
			lines.push(Language.get('replay_detail_speed') + ': ' + Language.get('replay_detail_song') + ' ' + sp + 'x  /  ' + Language.get('replay_detail_scroll') + ' ' + scr + 'x');
		}
		else lines.push(Language.get('replay_detail_speed') + ': —');

		// 版本信息
		var rv:String = (entry != null && Reflect.hasField(entry, 'replayVersion') && Reflect.field(entry, 'replayVersion') != null)
			? Std.string(Reflect.field(entry, 'replayVersion')) : '1.0';
		var kv:String = (entry != null && Reflect.hasField(entry, 'kathyVersion') && Reflect.field(entry, 'kathyVersion') != null)
			? Std.string(Reflect.field(entry, 'kathyVersion')) : '—';
		lines.push('');
		lines.push(Language.get('replay_detail_ver_replay') + ': v' + rv);
		lines.push(Language.get('replay_detail_ver_kathy') + ': v' + kv);

		return lines.join('\n');
	}

	override function update(elapsed:Float)
	{
		super.update(elapsed);
		if (controls.BACK)
		{
			controls.isInSubstate = false;
			close();
		}
	}
}
