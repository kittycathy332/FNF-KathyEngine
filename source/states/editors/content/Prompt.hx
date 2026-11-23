package states.editors.content;

import flixel.util.FlxDestroyUtil;
import backend.Language;
import backend.Paths;

@:allow(states.editors.ChartingState)
class ExitConfirmationPrompt extends Prompt
{
	public function new(?finishCallback:Void->Void)
	{
		super(Language.get('stage_editor_prompt_exit_title'), function()
		{
			FlxG.mouse.visible = false;
			MusicBeatState.switchState(new states.editors.MasterEditorMenu());
			FlxG.sound.playMusic(Paths.menuMusicAudio());
			if(finishCallback != null) finishCallback();
		}, Language.get('stage_editor_prompt_yes'));
	}
}

@:allow(states.editors.ChartingState)
class Prompt extends BasePrompt
{
	var yesFunction:Void->Void;
	var noFunction:Void->Void;
	var _yesTxt:String = Language.get('stage_editor_prompt_yes');
	var _noTxt:String = Language.get('stage_editor_prompt_cancel');
	public function new(title:String, yesFunction:Void->Void, ?noFunction:Void->Void, ?_yesTxt:String, ?_noTxt:String)
	{
		if(_yesTxt != null) this._yesTxt = _yesTxt;
		if(_noTxt != null) this._noTxt = _noTxt;
		this.yesFunction = yesFunction;
		controls.isInSubstate = true;
		this.noFunction = noFunction;
		super(title, promptCreate);
	}

	function promptCreate(_)
	{
		var btnY = 390;
		var btn:PsychUIButton = new PsychUIButton(0, btnY, _yesTxt, function() {
			yesFunction();
			controls.isInSubstate = false;
			_pendingClose = true;
		});
		btn.normalStyle.bgColor = FlxColor.RED;
		btn.normalStyle.textColor = FlxColor.WHITE;
		btn.screenCenter(X);
		btn.x -= 100;
		btn.cameras = cameras;
		add(btn);

		var btn:PsychUIButton = new PsychUIButton(0, btnY, _noTxt, function() { _pendingClose = true; });
		btn.screenCenter(X);
		btn.x += 100;
		btn.cameras = cameras;
		add(btn);
	}

	override function close()
	{
		if(noFunction != null) noFunction();
		super.close();
	}
}

@:allow(states.editors.ChartingState)
class BasePrompt extends MusicBeatSubstate
{
	var _sizeX:Float = 0;
	var _sizeY:Float = 0;
	var _title:String;

	public var onCreate:BasePrompt->Void;
	public var onUpdate:BasePrompt->Float->Void;
	/** 可选关闭钩子（MobileFilePicker 用它保证取消路径一定释放 busy 标志）。 */
	public var onClose:Void->Void;
	var _pendingClose:Bool = false;
	public function new(?sizeX:Float = 420, ?sizeY:Float = 160, title:String, ?onCreate:BasePrompt->Void, ?onUpdate:BasePrompt->Float->Void)
	{
		this._sizeX = sizeX;
		this._sizeY = sizeY;
		this._title = title;
		this.onCreate = onCreate;
		this.onUpdate = onUpdate;
		super();
	}

	public var bg:FlxSprite;
	public var titleText:FlxText;
	override function create()
	{
		cameras = [FlxG.cameras.list[FlxG.cameras.list.length - 1]];
		bg = new FlxSprite().makeGraphic(1, 1, FlxColor.BLACK);
		bg.alpha = 0.8;
		bg.scale.set(_sizeX, _sizeY);
		bg.updateHitbox();
		bg.screenCenter();
		bg.cameras = cameras;
		add(bg);
		
		titleText = new FlxText(0, bg.y + 30, 400, _title, 12);
		titleText.font = Paths.font(Language.get('uitab_font'));
		titleText.screenCenter(X);
		titleText.alignment = CENTER;
		titleText.cameras = cameras;
		add(titleText);
		
		if(onCreate != null)
			onCreate(this);
		super.create();
	}

	var _blockInput:Float = 0.1;
	override function update(elapsed:Float)
	{
		if(!active) return;

		super.update(elapsed);

		if(_pendingClose)
		{
			_pendingClose = false;
			close();
			return;
		}

		_blockInput = Math.max(0, _blockInput - elapsed);
		if(_blockInput <= 0 && FlxG.keys.justPressed.ESCAPE)
		{
			controls.isInSubstate = false;
			_pendingClose = true;
			return;
		}

		if(onUpdate != null)
			onUpdate(this, elapsed);
	}

	override function close()
	{
		if(onClose != null) onClose();
		super.close();
	}

	override function destroy()
	{
		super.destroy();
	}
}
