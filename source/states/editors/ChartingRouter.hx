package states.editors;

import backend.ClientPrefs;
import states.PlayState;
import states.LoadingState;
import states.editors.old.OldChartingState063;
import states.editors.old.OldChartingState073;

/**
 * 根据 ClientPrefs.data.chartingVersion 路由到对应版本的制谱器：
 *  - '1.0.4-Kathy'  -> 现有 ChartingState (KathyEngine 改版，支持多键 + 触屏) [默认]
 *  - '1.0.4-Official'-> Vanilla104ChartingState (PE 1.0.4 原版，仅 4 键，无触屏)
 *  - '0.7.3'        -> OldChartingState073 (0.7.3 复刻，Extra Keys 多键版，+触屏) —— EK 制谱器复刻
 *  - '0.6.3'        -> OldChartingState063 (0.6.3 复刻，现已补齐 1K-18K 多键 + 轨道横滚，+触屏)
 *
 * 1.0 改版 / 0.7.3 / 0.6.3 均已支持多键；仅 1.0.4-Official 仍是 4 键时代产物，
 * 因此遇到多键谱面时由该编辑器自己通过 currentChartIsFourKey() 回落到 1.0 改版制谱器。
 */
class ChartingRouter
{
	public static final VERSION_1_0:String = '1.0.4-Kathy';
	public static final VERSION_1_0_4_VANILLA:String = '1.0.4-Official';

	/** 旧存档里可能保存的是 '1.0' 或 '1.0.4-vanilla'，统一映射到新名称以免回落到 1.0。 */
	public static final VERSION_1_0_LEGACY:String = '1.0';
	public static final VERSION_1_0_4_VANILLA_LEGACY:String = '1.0.4-vanilla';
	public static final VERSION_0_7_3:String = '0.7.3';
	public static final VERSION_0_6_3:String = '0.6.3';

	public static final VERSIONS:Array<String> =
		[VERSION_1_0, VERSION_1_0_4_VANILLA, VERSION_0_7_3, VERSION_0_6_3];

	/** 当前谱面是否为 4 键（mania == null 或 3）。多键谱面会回落到支持多键的编辑器。 */
	public static function currentChartIsFourKey():Bool
	{
		if (PlayState.SONG == null) return true;
		var mania:Null<Int> = PlayState.SONG.mania;
		return (mania == null || mania == 3);
	}

	/** 解析出实际可用的制谱器版本。 */
	public static function resolveVersion():String
	{
		var version:String = ClientPrefs.data.chartingVersion;
		if (version == VERSION_1_0_LEGACY)
			version = VERSION_1_0;
		if (version == VERSION_1_0_4_VANILLA_LEGACY)
			version = VERSION_1_0_4_VANILLA;
		if (version == null || VERSIONS.indexOf(version) < 0)
			return VERSION_1_0;

		return version;
	}

	public static function createChartingState():MusicBeatState
	{
		return switch (resolveVersion())
		{
			case VERSION_1_0_4_VANILLA: new states.editors.vanilla104.ChartingState();
			case VERSION_0_6_3: new OldChartingState063();
			case VERSION_0_7_3: new OldChartingState073();
			default: new ChartingState();
		}
	}

	public static function openChartingEditor(useLoadingState:Bool = false):Void
	{
		var state:MusicBeatState = createChartingState();

		if (useLoadingState)
			LoadingState.loadAndSwitchState(state, false);
		else
			MusicBeatState.switchState(state);
	}
}
