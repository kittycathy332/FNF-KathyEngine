package backend;

import backend.Song;
import objects.Note;

typedef BPMChangeEvent =
{
	var stepTime:Int;
	var songTime:Float;
	var bpm:Float;
	@:optional var stepCrochet:Float;

	// 线性 BPM 过渡支持（可选）
	@:optional var endBPM:Float;    // 过渡结束时的 BPM
	@:optional var rampSteps:Float; // 过渡持续的步数（0/缺省 = 瞬时跳变，保持旧行为）
}

class Conductor
{
	public static var bpm(default, set):Float = 100;
	public static var crochet:Float = ((60 / bpm) * 1000); // beats in milliseconds
	public static var stepCrochet:Float = crochet / 4; // steps in milliseconds
	public static var songPosition:Float = 0;
	public static var offset:Float = 0;

	//public static var safeFrames:Int = 10;
	public static var safeZoneOffset:Float = 0; // is calculated in create(), is safeFrames in milliseconds

	public static var bpmChangeMap:Array<BPMChangeEvent> = [];

	// 单个 step 的毫秒基数：stepCrochet = STEP_MS / bpm；其中 STEP_MS = 60 * 1000 / 4 = 15000
	static inline var STEP_MS:Float = 15000;

	public static function judgeNote(arr:Array<Rating>, diff:Float=0):Rating
	{
		var data:Array<Rating> = arr;

		var absDiff:Float = Math.abs(diff);

		// Perfect判定逻辑 (现在在第一位)
		if (ClientPrefs.data.rmPerfect == 'enable' && absDiff <= data[0].hitWindow)
			return data[0];

		// 确定起始索引
		var startIndex:Int = (ClientPrefs.data.rmPerfect == 'enable') ? 1 : 0;

		// 按时间差匹配判定等级
		var useSoftEdge:Bool = ClientPrefs.data.softJudgmentEdge;
		for(i in startIndex...data.length)
		{
			var window:Float = data[i].hitWindow;
			if (absDiff <= window)
			{
				// 启用软边缘时，在当前窗口最外 20% 区域倾向"向下一级"判定，
				// 以避免刚好卡边界时出现明显跳变。
				if (useSoftEdge && i + 1 < data.length)
				{
					var nextWindow:Float = data[i + 1].hitWindow;
					var t:Float = (absDiff - window) / (nextWindow - window);
					if (t > -0.2 && t < 0.0) // 最外 20% 边缘带
						return data[i + 1];
				}
				return data[i];
			}
		}
		return data[data.length - 1];
	}

	// 返回缺省事件（无 BPM 映射时），rampSteps=0 表示恒定 BPM
	static function makeDefault():BPMChangeEvent
	{
		return {
			stepTime: 0,
			songTime: 0,
			bpm: bpm,
			stepCrochet: stepCrochet,
			endBPM: bpm,
			rampSteps: 0
		};
	}

	// 计算从 startBPM 线性过渡到 endBPM、经历 rampSteps 步所花费的时间(ms)
	// 积分：∫ 15000 / (b0 + (b1-b0)*u/R) du，闭式解为 15000*R/(b1-b0)*ln(b1/b0)
	public static function rampTime(startBPM:Float, endBPM:Float, rampSteps:Float):Float
	{
		if (rampSteps <= 0) return 0;
		if (startBPM == endBPM) return rampSteps * STEP_MS / startBPM;
		return STEP_MS * rampSteps / (endBPM - startBPM) * Math.log(endBPM / startBPM);
	}

	// 取包含指定时间的最近 BPM 段（返回原始段，bpm 为段起点 BPM，不填瞬时值）
	static function getRawSegmentByTime(time:Float):BPMChangeEvent
	{
		var last = makeDefault();
		for (i in 0...bpmChangeMap.length)
		{
			if (time >= bpmChangeMap[i].songTime)
				last = bpmChangeMap[i];
		}
		return last;
	}

	// 取包含指定 step 的最近 BPM 段
	static function getRawSegmentByStep(step:Float):BPMChangeEvent
	{
		var last = makeDefault();
		for (i in 0...bpmChangeMap.length)
		{
			if (bpmChangeMap[i].stepTime <= step)
				last = bpmChangeMap[i];
		}
		return last;
	}

	/**
	 * 轻量判断：指定时间是否正处于线性 BPM 过渡区间内。
	 * 只查原始段、不复制 struct、不算 exp，供 UI 高频轮询决定是否细粒度刷新。
	 */
	public static function isInBpmRamp(time:Float):Bool
	{
		var seg = getRawSegmentByTime(time);
		if (seg.rampSteps == null || seg.rampSteps <= 0 || seg.endBPM == null) return false;
		return time < seg.songTime + rampTime(seg.bpm, seg.endBPM, seg.rampSteps);
	}

	// 给定时间，返回该时刻的瞬时 BPM / stepCrochet
	public static function getBPMFromSeconds(time:Float):BPMChangeEvent
	{
		var seg = getRawSegmentByTime(time);
		if (seg.rampSteps == null || seg.rampSteps <= 0 || seg.endBPM == null)
			return seg;

		// 复制段并填入瞬时值
		var out:BPMChangeEvent = {
			stepTime: seg.stepTime,
			songTime: seg.songTime,
			bpm: seg.bpm,
			stepCrochet: seg.stepCrochet,
			endBPM: seg.endBPM,
			rampSteps: seg.rampSteps
		};

		var tRampEnd = seg.songTime + rampTime(seg.bpm, seg.endBPM, seg.rampSteps);
		if (time <= tRampEnd)
		{
			var ratio = (time - seg.songTime) * (seg.endBPM - seg.bpm) / (STEP_MS * seg.rampSteps);
			out.bpm = seg.bpm * Math.exp(ratio);
		}
		else
		{
			out.bpm = seg.endBPM;
		}
		out.stepCrochet = STEP_MS / out.bpm;
		return out;
	}

	// 给定 step，返回该位置的瞬时 BPM / stepCrochet
	public static function getBPMFromStep(step:Float):BPMChangeEvent
	{
		var seg = getRawSegmentByStep(step);
		if (seg.rampSteps == null || seg.rampSteps <= 0 || seg.endBPM == null)
			return seg;

		var out:BPMChangeEvent = {
			stepTime: seg.stepTime,
			songTime: seg.songTime,
			bpm: seg.bpm,
			stepCrochet: seg.stepCrochet,
			endBPM: seg.endBPM,
			rampSteps: seg.rampSteps
		};

		var sEnd = seg.stepTime + seg.rampSteps;
		if (step <= seg.stepTime)
			out.bpm = seg.bpm;
		else if (step >= sEnd)
			out.bpm = seg.endBPM;
		else
			out.bpm = seg.bpm + (seg.endBPM - seg.bpm) * (step - seg.stepTime) / seg.rampSteps;

		out.stepCrochet = STEP_MS / out.bpm;
		return out;
	}

	public static function getCrotchetAtTime(time:Float){
		var lastChange = getBPMFromSeconds(time);
		return lastChange.stepCrochet*4;
	}

	// 给定 step，返回其对应的时间(ms)。线性 BPM 下用积分闭式解。
	public static function getTimeFromStep(step:Float):Float
	{
		var seg = getRawSegmentByStep(step);
		if (seg.rampSteps == null || seg.rampSteps <= 0 || step <= seg.stepTime)
			return seg.songTime + (step - seg.stepTime) * seg.stepCrochet;

		var sEnd = seg.stepTime + seg.rampSteps;
		if (step <= sEnd)
		{
			var b = seg.bpm + (seg.endBPM - seg.bpm) * (step - seg.stepTime) / seg.rampSteps;
			return seg.songTime + rampTime(seg.bpm, b, (step - seg.stepTime));
		}
		else
		{
			var tRampEnd = seg.songTime + rampTime(seg.bpm, seg.endBPM, seg.rampSteps);
			return tRampEnd + (step - sEnd) * STEP_MS / seg.endBPM;
		}
	}

	public static function beatToSeconds(beat:Float): Float{
		return getTimeFromStep(beat * 4);
	}

	public static function getStep(time:Float):Float
	{
		var seg = getRawSegmentByTime(time);
		if (seg.rampSteps == null || seg.rampSteps <= 0)
			return seg.stepTime + (time - seg.songTime) / seg.stepCrochet;

		var tRampEnd = seg.songTime + rampTime(seg.bpm, seg.endBPM, seg.rampSteps);
		var sEnd = seg.stepTime + seg.rampSteps;
		if (time <= tRampEnd)
		{
			var ratio = (time - seg.songTime) * (seg.endBPM - seg.bpm) / (STEP_MS * seg.rampSteps);
			var b = seg.bpm * Math.exp(ratio);
			return seg.stepTime + seg.rampSteps * (b - seg.bpm) / (seg.endBPM - seg.bpm);
		}
		else
		{
			return sEnd + (time - tRampEnd) * seg.endBPM / STEP_MS;
		}
	}

	public static function getStepRounded(time:Float):Int
	{
		return Math.floor(getStep(time));
	}

	public static function getBeat(time:Float):Float
	{
		return getStep(time)/4;
	}

	public static function getBeatRounded(time:Float):Int
	{
		return Math.floor(getStep(time)/4);
	}

	public static function mapBPMChanges(song:SwagSong)
	{
		bpmChangeMap = [];

		var curBPM:Float = song.bpm;
		var totalSteps:Int = 0;
		var totalPos:Float = 0;
		for (i in 0...song.notes.length)
		{
			var sec = song.notes[i];
			var deltaSteps:Int = Math.round(getSectionBeats(song, i) * 4);

			if(sec.changeBPM && sec.bpm != null && sec.bpm != curBPM)
			{
				// 线性过渡：从 curBPM 在 rampSteps 步内爬升到 sec.bpm
				var rampSteps:Float = (sec.bpmRamp != null) ? Math.min(sec.bpmRamp, deltaSteps) : 0;
				// 瞬时跳变(rampSteps==0)时 bpm 取目标值以保持旧行为；
				// 过渡(rampSteps>0)时 bpm 取起点值，供过渡积分公式使用。
				var eventBPM:Float = (rampSteps > 0) ? curBPM : sec.bpm;
				var event:BPMChangeEvent = {
					stepTime: totalSteps,
					songTime: totalPos,
					bpm: eventBPM,           // 瞬时=目标BPM；过渡=起点BPM
					stepCrochet: calculateCrochet(eventBPM)/4,
					endBPM: sec.bpm,         // 过渡终点 BPM
					rampSteps: rampSteps     // 过渡步数（>0 才视为过渡）
				};
				bpmChangeMap.push(event);

				// 累计本段耗时：先走 ramp，剩余步以终点 BPM 匀速
				var rampPortion:Float = Math.min(rampSteps, deltaSteps);
				if (rampPortion > 0)
					totalPos += rampTime(curBPM, sec.bpm, rampPortion);
				totalPos += (deltaSteps - rampPortion) * (calculateCrochet(sec.bpm) / 4);

				curBPM = sec.bpm;
			}
			else
			{
				totalPos += ((60 / curBPM) * 1000 / 4) * deltaSteps;
			}

			totalSteps += deltaSteps;
		}
		// 重置全局基础 BPM / stepCrochet，使 makeDefault()（用于首个 changeBPM 之前的段）
		// 始终反映歌曲基准 BPM，而不是沿用上一次（如 PlayState 播放后）遗留的瞬时 BPM。
		Conductor.bpm = song.bpm;

		trace("new BPM map BUDDY " + bpmChangeMap);
	}

	static function getSectionBeats(song:SwagSong, section:Int)
	{
		var val:Null<Float> = null;
		if(song.notes[section] != null) val = song.notes[section].sectionBeats;
		return val != null ? val : 4;
	}

	inline public static function calculateCrochet(bpm:Float){
		return (60/bpm)*1000;
	}

	public static function set_bpm(newBPM:Float):Float {
		bpm = newBPM;
		crochet = calculateCrochet(bpm);
		stepCrochet = crochet / 4;

		return bpm = newBPM;
	}
}
