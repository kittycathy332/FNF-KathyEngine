package options;

/**
 * 音频 —— 分类重组阶段 2 自动生成。
 * 选项来自：GameplaySettingsSubState.hx, ExtraGameplaySettingSubState.hx, VisualsSettingsSubState.hx
 * 共 12 项；辅助函数按需从源文件带入。
 */
import states.PlayState;
import objects.KeyViewer;
import backend.MusicBeatState;
import flixel.text.FlxText;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.util.FlxTimer;
import backend.CustomFadeTransition;
import objects.Note;
import objects.StrumNote;
import objects.NoteSplash;
import objects.Alphabet;

class AudioSettingsSubState extends BaseOptionsMenu
{
	var changedMusic:Bool = false;
	function onChangeHitsound()
	{
		var soundName:String = ClientPrefs.data.hitsound;
		if (soundName != null && soundName != 'none')
			FlxG.sound.play(Paths.sound('hitsounds/' + soundName), 1.0);
	}

	function onChangeHitsoundVolume()
	{
		var useSound:String = 'hitsound';
		if (ClientPrefs.data.hitsound != 'none' && ClientPrefs.data.hitsound != null && ClientPrefs.data.hitsound.length > 0)
			useSound = 'hitsounds/' + ClientPrefs.data.hitsound;
		FlxG.sound.play(Paths.sound(useSound), ClientPrefs.data.hitsoundVolume);
	}

	function onChangeMenuMusic()
	{
		if (FlxG.sound.music != null)
			FlxG.sound.playMusic(Paths.menuMusicAudio());
		changedMusic = true;
	}

	function onChangePauseMusic()
	{
		if(ClientPrefs.data.pauseMusic == 'None')
			FlxG.sound.music.volume = 0;
		else
			FlxG.sound.playMusic(Paths.music(Paths.formatToSongPath(ClientPrefs.data.pauseMusic)));

		changedMusic = true;
	}

	override function destroy()
	{
		// 试听暂停/主菜单音乐后退出时恢复菜单 BGM（原 VisualsSettingsSubState.destroy）
		if (changedMusic && !OptionsState.onPlayState)
			FlxG.sound.playMusic(Paths.menuMusicAudio(), 1, true);
		super.destroy();
	}

	public function new()
	{
		title = Language.get('audio_menu');
		rpcTitle = 'Audio Menu';

		var option: Option;









		option = new Option(Language.get('hitsound'),
			Language.get("hitsound_desc"),
			'hitsound',
			STRING,
			CoolUtil.coolTextFile(Paths.txt('hitsoundList')));
		addOption(option);


		option.onChange = onChangeHitsound;
		option = new Option(Language.get('hitsound_volume'),
			Language.get("hitsoundvolume_desc"),
			'hitsoundVolume',
			PERCENT);
		addOption(option);


		option.scrollSpeed = 1.6;
		option.minValue = 0.0;
		option.maxValue = 1;
		option.changeValue = 0.1;
		option.decimals = 1;
		option.onChange = onChangeHitsoundVolume;
		option = new Option(Language.get('hitsound_pitch_offset'),
			Language.get('hitsound_pitch_offset_desc'),
			'hitsoundPitchOffset',
			BOOL);
		addOption(option);
		option = new Option(Language.get('hitsound_pitch_range'),
			Language.get('hitsound_pitch_range_desc'),
			'hitsoundPitchRange',
			FLOAT);
		option.scrollSpeed = 20;
		option.minValue = 0.05;
		option.maxValue = 0.6;
		option.changeValue = 0.05;
		option.decimals = 2;
		addOption(option);
		option = new Option(Language.get('hitsound_pool_enabled'),
			Language.get('hitsound_pool_enabled_desc'),
			'hitSoundPoolEnabled',
			BOOL);
		addOption(option);
		option = new Option(Language.get('hitsound_pool_size'),
			Language.get('hitsound_pool_size_desc'),
			'hitSoundPoolSize',
			INT);
		option.scrollSpeed = 20;
		option.minValue = 10;
		option.maxValue = 500;
		option.changeValue = 5;
		addOption(option);
		option = new Option(Language.get('background_volume'),
			Language.get("bgvol_desc"),
			'backgroundVolume',
			BOOL);
		addOption(option);
		option = new Option(Language.get('background_volume_level'),
			Language.get("bgvol_level_desc"),
			'backgroundVolumeLevel',
			PERCENT);
		option.scrollSpeed = 2;
		option.minValue = 0;
		option.maxValue = 1;
		option.changeValue = 0.02;
		option.decimals = 2;
		addOption(option);
		option = new Option(Language.get('pause_music'),
			Language.get("pausemusic_desc"),
			'pauseMusic',
			STRING,
			['None', 'Tea Time', 'Breakfast', 'Breakfast (Pico)', "Romantic Smile"]);
		addOption(option);


		option.onChange = onChangePauseMusic;

		// 主菜单音乐：'Default' 用标准 freakyMenu；其余由 freakyMenu-BPM.json 定义的三要素（显示名/音频文件/BPM）加自动扫描组成
		var menuMusicOptions:Array<String> = Paths.availableMenuMusicNames();
		option = new Option(Language.get('menu_music'),
			Language.get("menumusic_desc"),
			'daMenuMusic',
			STRING,
			menuMusicOptions);
		addOption(option);


		option.onChange = onChangeMenuMusic;

		// 画面每拍缩放特效（标题界面 3%，主界面 1.5%）

		super();
	}
}
