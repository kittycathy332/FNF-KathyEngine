package backend;

// Language.hx —— 本地化整合模块
// 将原本分散的各个专属本地化包统一收拢到本模块中，作为本模块的子类型：
//   StageEditorLanguage / OptionsLanguage / CharacterEditorLanguage
//   / WeekEditorLanguage / SubEditorsLanguage / ScoreLanguage
// 子类型路径为 backend.Language.XXX，外部通过 import backend.Language.XXX 使用。

import openfl.utils.Assets;
import haxe.Json;
import backend.ui.PsychUIInputText;

class Language {
    private static var currentLang:Map<String, String> = new Map();
    private static var fallbackLang:String = ClientPrefs.data.language;
    
    // 添加语言变更回调
    private static var onLanguageChangedCallbacks:Array<Void->Void> = [];
    
    public static function addCallback(callback:Void->Void) {
        if (!onLanguageChangedCallbacks.contains(callback))
            onLanguageChangedCallbacks.push(callback);
    }
    
    public static function removeCallback(callback:Void->Void) {
        onLanguageChangedCallbacks.remove(callback);
    }

    public static function load() {
        var lang = ClientPrefs.data.language;
        if(lang == null) lang = fallbackLang; // 额外保障
        
        currentLang.clear();
        if(!loadLanguage(lang) && lang != fallbackLang) {
            loadLanguage(fallbackLang);
        }

        // 合并设置界面（Options）专属语言包（assets/languages/options/{lang}.json）
        OptionsLanguage.mergeInto(currentLang, lang);

        // 合并场景编辑器（Stage Editor）专属语言包（assets/languages/editors/stage_editor/{lang}.json）
        StageEditorLanguage.mergeInto(currentLang, lang);

        // 合并角色编辑器（Character Editor）专属语言包（assets/languages/editors/character_editor/{lang}.json）
        CharacterEditorLanguage.mergeInto(currentLang, lang);

        // 合并周目编辑器（Week Editor）专属语言包（assets/languages/editors/week_editor/{lang}.json）
        WeekEditorLanguage.mergeInto(currentLang, lang);

        // 合并子编辑器（Menu Char/Dialogue/Note Splash/Hold Cover）专属语言包
        SubEditorsLanguage.mergeInto(currentLang, lang);

        // 设置 UI 组件默认字体，确保下拉框/数字框/输入框能正确显示 CJK 字符
        PsychUIInputText.defaultFont = Paths.font(get('uitab_font'));

        // 通知所有监听者语言已更改
        for (callback in onLanguageChangedCallbacks) {
            callback();
        }
    }
    
    private static function loadLanguage(lang:String):Bool {
        try {
            var rawJson = Assets.getText('assets/languages/$lang.json');
            if(rawJson == null) return false;

            var parsedData:Dynamic = Json.parse(rawJson);
            for (key in Reflect.fields(parsedData)) {
                currentLang.set(key, Reflect.field(parsedData, key));
            }
            return true;
        } catch(e) {
            trace("Language load error: " + e.message);
            return false;
        }
    }

    public static function get(key:String, ?params:Array<String>):String {
        var value = currentLang.exists(key) ? currentLang.get(key) : key; // 如果键不存在，返回键本身
        if (params != null) {
            for (i in 0...params.length) {
                // 同时支持两种占位符风格：
                //  - Kathy 新增键：{$0}（0-based，带 $）
                //  - 早期/翻译遗留键：{0}（0-based，无 $，如 charting_msg_zoom）
                // 先替换带 $ 的（更具体），再替换无 $ 的；{$0} 不包含 {0} 子串，互不冲突。
                value = StringTools.replace(value, '{$' + i + '}', params[i]);
                value = StringTools.replace(value, '{' + i + '}', params[i]);
            }
        }
        return value;
    }
    
    /**
     * 优先使用模组 .lang（LanguageBasic，兼容旧的自定义语言文件）；
     * 命不中时回退到 JSON 语言包（Language.get）。
     * 两套体系的占位符编号不同（.lang 是 {1} 起、JSON 是 {0} 起），由各自内部处理，
     * 调用方只需按顺序传值即可。
     */
    public static function getWithFallback(key:String, ?defaultPhrase:String, ?params:Array<Dynamic>):String {
        var basic:String = LanguageBasic.getPhrase(key, null, params);
        if (basic != null && basic != key)
            return basic;

        var jsonParams:Array<String> = null;
        if (params != null) {
            jsonParams = [];
            for (p in params) jsonParams.push(Std.string(p));
        }

        var json:String = get(key, jsonParams);
        if (json != key)
            return json;

        // 两套体系都没有该 key 时才使用默认英文文案（占位符用 {0} 起，与 JSON 一致）
        if (defaultPhrase != null) {
            var out:String = defaultPhrase;
            if (jsonParams != null) {
                for (i in 0...jsonParams.length)
                    out = StringTools.replace(out, '{' + i + '}', jsonParams[i]);
            }
            return out;
        }
        return json;
    }

    // 获取游戏字体文件
    public static function getGameFont():String {
        return currentLang.get("game_font");
    }
}

/** Stage Editor 专属本地化包（本模块子类型 backend.Language.StageEditorLanguage）。 */
class StageEditorLanguage
{
	public static function mergeInto(target:Map<String, String>, lang:String):Void
	{
		if (tryMerge(target, 'assets/languages/editors/stage_editor/$lang.json'))
			return;
		if (lang != 'en_us')
			tryMerge(target, 'assets/languages/editors/stage_editor/en_us.json');
	}

	public static function get(key:String, ?defaultValue:String):String
	{
		var val:String = Language.get(key);
		if (val != null && val != key)
			return val;
		if (defaultValue != null)
			return defaultValue;
		return key;
	}

	private static function tryMerge(target:Map<String, String>, path:String):Bool
	{
		if (!Assets.exists(path))
			return false;

		try
		{
			var parsed:Dynamic = Json.parse(Assets.getText(path));
			for (key in Reflect.fields(parsed))
				target.set(key, Reflect.field(parsed, key));
			return true;
		}
		catch (e:Dynamic)
		{
			trace('StageEditorLanguage merge error (' + path + '): ' + e);
			return false;
		}
	}
}

/** Options（设置界面）专属本地化包（本模块子类型 backend.Language.OptionsLanguage）。 */
class OptionsLanguage
{
	// 将设置界面语言包合并进传入的目标表（通常是 Language 的全局表）。
	public static function mergeInto(target:Map<String, String>, lang:String):Void
	{
		if (tryMerge(target, 'assets/languages/options/$lang.json'))
			return;
		if (lang != 'en_us')
			tryMerge(target, 'assets/languages/options/en_us.json');
	}

	// 读取设置界面文本，并支持默认值回退。
	public static function get(key:String, ?defaultValue:String):String
	{
		var val:String = Language.get(key);
		if (val != null && val != key)
			return val;
		if (defaultValue != null)
			return defaultValue;
		return key;
	}

	private static function tryMerge(target:Map<String, String>, path:String):Bool
	{
		if (!Assets.exists(path))
			return false;

		try
		{
			var parsed:Dynamic = Json.parse(Assets.getText(path));
			for (key in Reflect.fields(parsed))
				target.set(key, Reflect.field(parsed, key));
			return true;
		}
		catch (e:Dynamic)
		{
			trace('OptionsLanguage merge error (' + path + '): ' + e);
			return false;
		}
	}
}

/** Character Editor 专属本地化包（本模块子类型 backend.Language.CharacterEditorLanguage）。 */
class CharacterEditorLanguage
{
	public static function mergeInto(target:Map<String, String>, lang:String):Void
	{
		if (tryMerge(target, 'assets/languages/editors/character_editor/$lang.json'))
			return;
		if (lang != 'en_us')
			tryMerge(target, 'assets/languages/editors/character_editor/en_us.json');
	}

	private static function tryMerge(target:Map<String, String>, path:String):Bool
	{
		if (!Assets.exists(path))
			return false;

		try
		{
			var parsed:Dynamic = Json.parse(Assets.getText(path));
			for (key in Reflect.fields(parsed))
				target.set(key, Reflect.field(parsed, key));
			return true;
		}
		catch (e:Dynamic)
		{
			trace('CharacterEditorLanguage merge error (' + path + '): ' + e);
			return false;
		}
	}
}

/** Week Editor 专属本地化包（本模块子类型 backend.Language.WeekEditorLanguage）。 */
class WeekEditorLanguage
{
	public static function mergeInto(target:Map<String, String>, lang:String):Void
	{
		if (tryMerge(target, 'assets/languages/editors/week_editor/$lang.json'))
			return;
		if (lang != 'en_us')
			tryMerge(target, 'assets/languages/editors/week_editor/en_us.json');
	}

	private static function tryMerge(target:Map<String, String>, path:String):Bool
	{
		if (!Assets.exists(path))
			return false;

		try
		{
			var parsed:Dynamic = Json.parse(Assets.getText(path));
			for (key in Reflect.fields(parsed))
				target.set(key, Reflect.field(parsed, key));
			return true;
		}
		catch (e:Dynamic)
		{
			trace('WeekEditorLanguage merge error (' + path + '): ' + e);
			return false;
		}
	}
}

/** 子编辑器（Menu Char / Dialogue / Dialogue Char / Note Splash / Hold Cover）专属本地化包（本模块子类型 backend.Language.SubEditorsLanguage）。 */
class SubEditorsLanguage
{
	static final EDITOR_PATHS:Array<String> = [
		'menu_character_editor',
		'dialogue_editor',
		'dialogue_character_editor',
		'notesplash_editor',
		'hold_cover_editor'
	];

	public static function mergeInto(target:Map<String, String>, lang:String):Void
	{
		for (path in EDITOR_PATHS)
			if (!tryMerge(target, 'assets/languages/editors/$path/$lang.json') && lang != 'en_us')
				tryMerge(target, 'assets/languages/editors/$path/en_us.json');
	}

	private static function tryMerge(target:Map<String, String>, path:String):Bool
	{
		if (!Assets.exists(path))
			return false;

		try
		{
			var parsed:Dynamic = Json.parse(Assets.getText(path));
			for (key in Reflect.fields(parsed))
				target.set(key, Reflect.field(parsed, key));
			return true;
		}
		catch (e:Dynamic)
		{
			trace('SubEditorsLanguage merge error (' + path + '): ' + e);
			return false;
		}
	}
}

/** Score（分数文字 scoreTxt）专用本地化系统（本模块子类型 backend.Language.ScoreLanguage）。 */
class ScoreLanguage
{
	private static var scoreLang:Map<String, String> = new Map<String, String>();
	private static var loaded:Bool = false;

	// 将设置值解析为分数文本语言代码（对应 assets/languages/scoretxt/ 下的文件名）。
	// 'auto' 跟随游戏语言；其余选项值本身即语言代码，直接作为文件名返回。
	public static function resolveLang():String
	{
		var pref:String = ClientPrefs.data.scoreLanguage;
		if (pref == null || pref == '' || pref == 'auto')
			return ClientPrefs.data.language;
		return pref;
	}

	// 原始引擎（英文）默认值：当 scoretxt JSON 缺失某 key 时回退到此，
	// 从而尽可能保证原有兼容性（不会出现 score_label_xxx 这类裸 key）。
	private static var DEFAULTS:Map<String, String> = [
		'score_font'             => 'vcr.ttf',
		'score_label_score'      => 'Score',
		'score_label_nps'        => 'NPS',
		'score_label_miss'       => 'Miss',
		'score_label_misses'     => 'Misses',
		'score_label_acc'        => 'Acc',
		'score_label_combobreaks'=> 'Combo Breaks',
		'score_label_average'    => 'Average',
		'score_label_accuracy'   => 'Accuracy',
		'score_label_rating'     => 'Rating'
	];

	// 载入对应语言的分数文本；可传入强制语言代码（测试用）
	public static function load(?forceLang:String):Void
	{
		var lang:String = (forceLang != null && forceLang.length > 0) ? forceLang : resolveLang();
		if (lang == null || lang.length == 0) lang = 'en_us';

		scoreLang = new Map<String, String>();
		loaded = false;

		if (tryLoad(lang))
			return;

		// 目标语言文件缺失时回退到 en_us
		if (lang != 'en_us')
			tryLoad('en_us');
	}

	private static function tryLoad(lang:String):Bool
	{
		var path:String = 'assets/languages/scoretxt/$lang.json';
		if (!Assets.exists(path))
			return false;

		try
		{
			var raw:String = Assets.getText(path);
			var parsed:Dynamic = Json.parse(raw);
			for (key in Reflect.fields(parsed))
				scoreLang.set(key, Reflect.field(parsed, key));
			loaded = scoreLang.keys().hasNext();
			return loaded;
		}
		catch (e:Dynamic)
		{
			trace('ScoreLanguage load error (' + lang + '): ' + e);
			return false;
		}
	}

	public static function get(key:String):String
	{
		// 优先级：scoretxt 专属文件 > 主语言 JSON（模组兼容）> 内嵌英文默认值
		if (scoreLang.exists(key))
			return scoreLang.get(key);
		var fromMain:String = Language.get(key);
		if (fromMain != null && fromMain != key)
			return fromMain;
		if (DEFAULTS.exists(key))
			return DEFAULTS.get(key);
		return key;
	}

	// 获取分数文字字体（英文默认回退到引擎原生的 vcr.ttf）
	public static function getScoreFont():String
	{
		var font:String = get('score_font');
		if (font == null || font.length == 0)
			font = 'vcr.ttf';
		return font;
	}

	// 将 ratingFC 原始 token（如 "PFC" / "FC" / "?"）翻译为当前分数语言文本。
	// 缺失时回退到原始 token 本身（即英文/原逻辑），保证兼容性。
	public static function getRatingFC(token:String):String
	{
		if (token == null) return '';
		var key:String = 'ratingfc_' + token.toLowerCase();
		if (scoreLang.exists(key))
			return scoreLang.get(key);
		return token;
	}

	// 将 ratingStuff 的评分名（如 "You Suck!" / "Sick!" / "Perfect!!"）翻译为当前分数语言文本。
	// 以英文原 token 作为 scoretxt JSON 的键；缺失时回退到原始 token 本身，保证兼容性。
	// 注意：这里只用于显示层，ratingName 本体仍保持英文 token（不影响判定/脚本）。
	public static function getRatingName(token:String):String
	{
		if (token == null) return '';
		if (scoreLang.exists(token))
			return scoreLang.get(token);
		return token;
	}

	// 将 Leather 评级前缀（FC / SDB / GFC / SDG / PFC / SDP / MFC / SDCB / CLEAR）翻译为当前分数语言文本。
	// 与 ratingFC 重叠的（fc/pfc/sdcb/clear）复用 ratingfc_ 键；
	// Leather 专属的（sdb/gfc/sdg/sdp/mfc）使用 lrank_ 键；
	// 缺失时回退到原始 token 本身，保证兼容性。
	public static function getLeatherRankPrefix(token:String):String
	{
		if (token == null || token.length == 0) return '';
		var lower:String = token.toLowerCase();
		if (scoreLang.exists('ratingfc_' + lower))
			return scoreLang.get('ratingfc_' + lower);
		if (scoreLang.exists('lrank_' + lower))
			return scoreLang.get('lrank_' + lower);
		return token;
	}

	// 将 Leather 评级名（SSSS / SSS / SS / S / AA / A / B+ / B / C / D / E / F / G）翻译为当前分数语言文本。
	// 以 lname_ + 原 token 作为键；音游中这些字母评级通常保留原样，缺失时回退到原始 token。
	public static function getLeatherRankName(token:String):String
	{
		if (token == null) return '';
		if (scoreLang.exists('lname_' + token))
			return scoreLang.get('lname_' + token);
		return token;
	}
}