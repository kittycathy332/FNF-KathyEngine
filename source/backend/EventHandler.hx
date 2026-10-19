package backend;

import flixel.FlxG;
import flixel.tweens.FlxTween;
import flixel.tweens.FlxEase;
import flixel.util.FlxColor;
import flixel.text.FlxText;
import flixel.group.FlxGroup.FlxTypedGroup;
import objects.Note.EventNote;
import backend.Conductor;
import backend.Paths;
import backend.ClientPrefs;
import psychlua.LuaUtils;
import objects.Character;
import backend.BaseStage;
import states.PlayState;

/**
 * EventHandler 类用于处理游戏中的事件逻辑
 * 包括事件触发、预缓存和调试显示
 */
class EventHandler
{
    // 引用 PlayState 实例以访问其属性和方法
    private var playState:PlayState;

    // 事件调试相关
    private var eventDebugGroup:FlxTypedGroup<FlxText>;
    private var eventTexts:Array<FlxText> = [];
    private var maxEventTexts:Int = 8;

    // 已推送的事件列表，用于避免重复推送
    public var eventsPushed:Array<String> = [];

    public function new(playState:PlayState)
    {
        this.playState = playState;
        this.eventDebugGroup = playState.eventDebugGroup;
    }

    /**
     * 检查事件笔记并触发相应事件
     */
    public function checkEventNote():Void
    {
        while(playState.eventNotes.length > 0) {
            var leStrumTime:Float = playState.eventNotes[0].strumTime;
            if(Conductor.songPosition < leStrumTime) {
                return;
            }

            var value1:String = '';
            if(playState.eventNotes[0].value1 != null)
                value1 = playState.eventNotes[0].value1;

            var value2:String = '';
            if(playState.eventNotes[0].value2 != null)
                value2 = playState.eventNotes[0].value2;

            var value3:String = '';
            if(playState.eventNotes[0].value1 != null)
                value3 = playState.eventNotes[0].value3;

            var value4:String = '';
            if(playState.eventNotes[0].value4 != null)
                value4 = playState.eventNotes[0].value4;

            triggerEvent(playState.eventNotes[0].event, value1, value2, value3, value4, leStrumTime);
            playState.eventNotes.shift();
        }
    }

    /**
     * 触发事件的主要函数
     */
    public function triggerEvent(eventName:String, value1:String, value2:String, value3:String, value4:String, strumTime:Float):Void
    {
        var flValue1:Null<Float> = Std.parseFloat(value1);
        var flValue2:Null<Float> = Std.parseFloat(value2);
        var flValue3:Null<Float> = Std.parseFloat(value3);
        var flValue4:Null<Float> = Std.parseFloat(value4);
        if(Math.isNaN(flValue1)) flValue1 = null;
        if(Math.isNaN(flValue2)) flValue2 = null;
        if(Math.isNaN(flValue3)) flValue3 = null;
        if(Math.isNaN(flValue4)) flValue4 = null;
        if (PlayState.chartingMode && ClientPrefs.data.eventDebug) {
            showEventDebug(eventName, [value1, value2, value3, value4], strumTime);
        }
        switch(eventName) {
            case 'Hey!':
                var value:Int = 2;
                switch(value1.toLowerCase().trim()) {
                    case 'bf' | 'boyfriend' | '0':
                        value = 0;
                    case 'gf' | 'girlfriend' | '1':
                        value = 1;
                }

                if(flValue2 == null || flValue2 <= 0) flValue2 = 0.6;

                if(value != 0) {
                    if(playState.dad.curCharacter.startsWith('gf')) { //Tutorial GF is actually Dad! The GF is an imposter!! ding ding ding ding ding ding ding, dindinding, end my suffering
                        playState.dad.playAnim('cheer', true);
                        playState.dad.specialAnim = true;
                        playState.dad.heyTimer = flValue2;
                    } else if (playState.gf != null) {
                        playState.gf.playAnim('cheer', true);
                        playState.gf.specialAnim = true;
                        playState.gf.heyTimer = flValue2;
                    }
                }
                if(value != 1) {
                    playState.boyfriend.playAnim('hey', true);
                    playState.boyfriend.specialAnim = true;
                    playState.boyfriend.heyTimer = flValue2;
                }

            case 'Set GF Speed':
                if(flValue1 == null || flValue1 < 1) flValue1 = 1;
                playState.gfSpeed = Math.round(flValue1);

            case 'Add Camera Zoom':
                if(ClientPrefs.data.camZooms/* && FlxG.camera.zoom < 1.35*/) {
                    if(flValue1 == null) flValue1 = 0.015;
                    if(flValue2 == null) flValue2 = 0.03;

                    FlxG.camera.zoom += flValue1;
                    playState.camHUD.zoom += flValue2;
                }

            case 'Play Animation':
                //trace('Anim to play: ' + value1);
                var char:Character = playState.dad;
                switch(value2.toLowerCase().trim()) {
                    case 'bf' | 'boyfriend':
                        char = playState.boyfriend;
                    case 'gf' | 'girlfriend':
                        char = playState.gf;
                    default:
                        if(flValue2 == null) flValue2 = 0;
                        switch(Math.round(flValue2)) {
                            case 1: char = playState.boyfriend;
                            case 2: char = playState.gf;
                        }
                }

                if (char != null)
                {
                    char.playAnim(value1, true);
                    char.specialAnim = true;
                }

            case 'Camera Follow Pos':
                if(playState.camFollow != null)
                {
                    playState.isCameraOnForcedPos = false;
                    if(flValue1 != null || flValue2 != null)
                    {
                        playState.isCameraOnForcedPos = true;
                        if(flValue1 == null) flValue1 = 0;
                        if(flValue2 == null) flValue2 = 0;
                        playState.camFollow.x = flValue1;
                        playState.camFollow.y = flValue2;
                    }
                }

            case 'Alt Idle Animation':
                var char:Character = playState.dad;
                switch(value1.toLowerCase().trim()) {
                    case 'gf' | 'girlfriend':
                        char = playState.gf;
                    case 'boyfriend' | 'bf':
                        char = playState.boyfriend;
                    default:
                        var val:Int = Std.parseInt(value1);
                        if(Math.isNaN(val)) val = 0;

                        switch(val) {
                            case 1: char = playState.boyfriend;
                            case 2: char = playState.gf;
                        }
                }

                if (char != null)
                {
                    char.idleSuffix = value2;
                    char.recalculateDanceIdle();
                }

            case 'Screen Shake':
                var valuesArray:Array<String> = [value1, value2];
                var targetsArray:Array<FlxCamera> = [playState.camGame, playState.camHUD];
                for (i in 0...targetsArray.length) {
                    var split:Array<String> = valuesArray[i].split(',');
                    var duration:Float = 0;
                    var intensity:Float = 0;
                    if(split[0] != null) duration = Std.parseFloat(split[0].trim());
                    if(split[1] != null) intensity = Std.parseFloat(split[1].trim());
                    if(Math.isNaN(duration)) duration = 0;
                    if(Math.isNaN(intensity)) intensity = 0;

                    if(duration > 0 && intensity != 0) {
                        targetsArray[i].shake(intensity, duration);
                    }
                }


            case 'Change Character':
                var charType:Int = 0;
                switch(value1.toLowerCase().trim()) {
                    case 'gf' | 'girlfriend':
                        charType = 2;
                    case 'dad' | 'opponent':
                        charType = 1;
                    default:
                        charType = Std.parseInt(value1);
                        if(Math.isNaN(charType)) charType = 0;
                }

                switch(charType) {
                    case 0:
                        if(playState.boyfriend.curCharacter != value2) {
                            if(!playState.boyfriendMap.exists(value2)) {
                                playState.addCharacterToList(value2, charType);
                            }

                            var lastAlpha:Float = playState.boyfriend.alpha;
                            playState.boyfriend.alpha = 0.00001;
                            playState.boyfriend = playState.boyfriendMap.get(value2);
                            playState.boyfriend.alpha = lastAlpha;
                            playState.iconP1.changeIcon(playState.boyfriend.healthIcon);
                            playState.applyIconStates(); // 换图标后立刻按当前血量恢复 输/赢 状态，避免回到普通态
                        }
                        playState.setOnScripts('boyfriendName', playState.boyfriend.curCharacter);

                    case 1:
                        if(playState.dad.curCharacter != value2) {
                            if(!playState.dadMap.exists(value2)) {
                                playState.addCharacterToList(value2, charType);
                            }

                            var wasGf:Bool = playState.dad.curCharacter.startsWith('gf-') || playState.dad.curCharacter == 'gf';
                            var lastAlpha:Float = playState.dad.alpha;
                            playState.dad.alpha = 0.00001;
                            playState.dad = playState.dadMap.get(value2);
                            if(!playState.dad.curCharacter.startsWith('gf-') && playState.dad.curCharacter != 'gf') {
                                if(wasGf && playState.gf != null) {
                                    playState.gf.visible = true;
                                }
                            } else if(playState.gf != null) {
                                playState.gf.visible = false;
                            }
                            playState.dad.alpha = lastAlpha;
                            playState.iconP2.changeIcon(playState.dad.healthIcon);
                            playState.applyIconStates(); // 换图标后立刻按当前血量恢复 输/赢 状态，避免回到普通态
                        }
                        playState.setOnScripts('dadName', playState.dad.curCharacter);

                    case 2:
                        if(playState.gf != null)
                        {
                            if(playState.gf.curCharacter != value2)
                            {
                                if(!playState.gfMap.exists(value2)) {
                                    playState.addCharacterToList(value2, charType);
                                }

                                var lastAlpha:Float = playState.gf.alpha;
                                playState.gf.alpha = 0.00001;
                                playState.gf = playState.gfMap.get(value2);
                                playState.gf.alpha = lastAlpha;
                            }
                            playState.setOnScripts('gfName', playState.gf.curCharacter);
                        }
                }
                playState.reloadHealthBarColors();

            case 'Change Scroll Speed':
                if (playState.songSpeedType != "constant")
                {
                    if(flValue1 == null) flValue1 = 1;
                    if(flValue2 == null) flValue2 = 0;
                    if(value3 == null) value3 = 'linear';

                    var newValue:Float = PlayState.SONG.speed * ClientPrefs.getGameplaySetting('scrollspeed') * flValue1;
                    var easeFunc:EaseFunction = getEaseFunctionFromString(value3); // Helper function to get ease
                    if(flValue2 <= 0) {
                        playState.songSpeed = newValue;
                    } else {
                        playState.songSpeedTween = FlxTween.tween(playState, {songSpeed: newValue}, flValue2 / playState.playbackRate, {
                            ease: easeFunc,
                            onComplete: function(twn:FlxTween) {
                                playState.songSpeedTween = null;
                            }
                        });
                    }
                }

            case 'Set Property':
                try
                {
                    var trueValue:Dynamic = value2.trim();
                    if (trueValue == 'true' || trueValue == 'false') trueValue = trueValue == 'true';
                    else if (flValue2 != null) trueValue = flValue2;
                    else trueValue = value2;

                    var split:Array<String> = value1.split('.');
                    if(split.length > 1) {
                        LuaUtils.setVarInArray(LuaUtils.getPropertyLoop(split), split[split.length-1], trueValue);
                    } else {
                        LuaUtils.setVarInArray(playState, value1, trueValue);
                    }
                }
                catch(e:Dynamic)
                {
                    var len:Int = e.message.indexOf('\n') + 1;
                    if(len <= 0) len = e.message.length;
                    #if (LUA_ALLOWED || HSCRIPT_ALLOWED)
                    playState.addTextToDebug('ERROR ("Set Property" Event) - ' + e.message.substr(0, len), FlxColor.RED);
                    #else
                    FlxG.log.warn('ERROR ("Set Property" Event) - ' + e.message.substr(0, len));
                    #end
                }

            case 'Play Sound':
                if(flValue2 == null) flValue2 = 1;
                FlxG.sound.play(Paths.sound(value1), flValue2);

            case 'Change Window Title':
                if (value1 != null && value1.trim() != "") {
                    FlxG.stage.window.title = value1.trim();
                } else {
                    FlxG.stage.window.title = 'IDK';
                }

            case 'Toggle IconBop':
                var enable:Bool = true;
                if(value1.toLowerCase().trim() == 'off' || value1.toLowerCase().trim() == 'false' || value1.toLowerCase().trim() == '0') {
                    enable = false;
                }
                playState.iconBopEnabled = enable;

            case 'Add IconBop':
                playState.iconBopNow();

            // —— LE LTS 双侧轨道数：change keycount 事件（value1=玩家键数、value2=对手键数）实时切换 ——
            // 参考 LTS EventHandler：写回 SONG 两侧键数 → 更新两侧 EK 档配置 → 重建 strums/键位 → 重排音符
            // 首字母大写为主（制谱器新写入）；同时保留小写分支兼容已存在的旧谱面。
            case 'Change KeyCount', 'change keycount':
                var plrKeys:Int = (value1 != null && value1 != '' && !Math.isNaN(Std.parseFloat(value1))) ? Std.parseInt(value1) : 4;
                var oppKeys:Int = (value2 != null && value2 != '' && !Math.isNaN(Std.parseFloat(value2))) ? Std.parseInt(value2) : 4;
                if (plrKeys < 1) plrKeys = 4;
                if (oppKeys < 1) oppKeys = 4;
                playState.changeKeyCounts(plrKeys, oppKeys);
        }

        playState.stagesFunc(function(stage:BaseStage) stage.eventCalled(eventName, value1, value2, flValue1, flValue2, strumTime));
        playState.callOnScripts('onEvent', [eventName, value1, value2, value3, value4, strumTime]);
    }

    /**
     * 获取缓动函数
     */
    private function getEaseFunctionFromString(easeName:String):EaseFunction {
        return switch(easeName.toLowerCase()) {
            case 'linear': FlxEase.linear;
            case 'quadIn': FlxEase.quadIn;
            case 'quadOut': FlxEase.quadOut;
            case 'quadInOut': FlxEase.quadInOut;
            case 'cubeIn': FlxEase.cubeIn;
            case 'cubeOut': FlxEase.cubeOut;
            case 'cubeInOut': FlxEase.cubeInOut;
            case 'quartIn': FlxEase.quartIn;
            case 'quartOut': FlxEase.quartOut;
            case 'quartInOut': FlxEase.quartInOut;
            case 'quintIn': FlxEase.quintIn;
            case 'quintOut': FlxEase.quintOut;
            case 'quintInOut': FlxEase.quintInOut;
            case 'sineIn': FlxEase.sineIn;
            case 'sineOut': FlxEase.sineOut;
            case 'sineInOut': FlxEase.sineInOut;
            case 'bounceIn': FlxEase.bounceIn;
            case 'bounceOut': FlxEase.bounceOut;
            case 'bounceInOut': FlxEase.bounceInOut;
            case 'circIn': FlxEase.circIn;
            case 'circOut': FlxEase.circOut;
            case 'circInOut': FlxEase.circInOut;
            case 'expoIn': FlxEase.expoIn;
            case 'expoOut': FlxEase.expoOut;
            case 'expoInOut': FlxEase.expoInOut;
            case 'backIn': FlxEase.backIn;
            case 'backOut': FlxEase.backOut;
            case 'backInOut': FlxEase.backInOut;
            case 'elasticIn': FlxEase.elasticIn;
            case 'elasticOut': FlxEase.elasticOut;
            case 'elasticInOut': FlxEase.elasticInOut;
            case 'smoothStepIn': FlxEase.smoothStepIn;
            case 'smoothStepOut': FlxEase.smoothStepOut;
            case 'smoothStepInOut': FlxEase.smoothStepInOut;
            case 'smootherStepIn': FlxEase.smootherStepIn;
            case 'smootherStepOut': FlxEase.smootherStepOut;
            case 'smootherStepInOut': FlxEase.smootherStepInOut;
            default: FlxEase.linear; // Default to linear if unknown
        }
    }

    /**
     * 显示事件调试信息
     */
    private function showEventDebug(eventName:String, values:Array<String>, strumTime:Float):Void {
        if (!PlayState.chartingMode) return;

        var text:String = 'TriggerEvent: $eventName\nTime: ${Math.round(strumTime)}ms | Step: ${Math.floor(Conductor.songPosition / Conductor.stepCrochet)}';
        if (values.length > 0) text += '\nValues: ${values.join(", ")}';

        var debugText:FlxText = new FlxText(20, 0, FlxG.width - 40, text, 16);
        debugText.setFormat(Paths.font("unifont-18.0.01.otf"), 16, FlxColor.CYAN, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
        debugText.borderSize = 3;
        debugText.scrollFactor.set();
        debugText.cameras = [playState.camArchived];

        // 添加到组和数组
        eventDebugGroup.add(debugText);
        eventTexts.push(debugText);

        // 更新所有文本位置，使其显示在上部
        for (i in 0...eventTexts.length) {
            eventTexts[i].y = 90 + (i * 55);
        }

        FlxTween.tween(debugText, { alpha: 0 }, (60 / Conductor.bpm) * 4 , {
            ease: FlxEase.circIn,
            onComplete: function(tween:FlxTween) {
                // 动画完成后移除文本
                eventDebugGroup.remove(debugText, true);
                eventTexts.remove(debugText);
                debugText.destroy();

                // 重新调整剩余文本的位置
                for (i in 0...eventTexts.length) {
                    eventTexts[i].y = 90 + (i * 55);
                }
            }
        });

        // 清理旧文本
        if (eventTexts.length > maxEventTexts) {
            var oldText = eventTexts.shift();
            eventDebugGroup.remove(oldText, true);
            oldText.destroy();
        }
    }

    /**
     * 事件预缓存 - 只为不同事件调用一次
     */
    public function eventPushed(event:EventNote):Void
    {
        eventPushedUnique(event);
        if(eventsPushed.contains(event.event)) {
            return;
        }

        playState.stagesFunc(function(stage:BaseStage) stage.eventPushed(event));
        eventsPushed.push(event.event);
    }

    /**
     * 事件预缓存 - 为每个同名事件调用
     */
    public function eventPushedUnique(event:EventNote):Void
    {
        switch(event.event) {
            case "Change Character":
                var charType:Int = 0;
                switch(event.value1.toLowerCase()) {
                    case 'gf' | 'girlfriend':
                        charType = 2;
                    case 'dad' | 'opponent':
                        charType = 1;
                    default:
                        var val1:Int = Std.parseInt(event.value1);
                        if(Math.isNaN(val1)) val1 = 0;
                        charType = val1;
                }

                var newCharacter:String = event.value2;
                playState.addCharacterToList(newCharacter, charType);

            case 'Play Sound':
                Paths.sound(event.value1); //Precache sound
        }
        playState.stagesFunc(function(stage:BaseStage) stage.eventPushedUnique(event));
    }

    /**
     * 事件提前触发
     */
    public function eventEarlyTrigger(event:EventNote):Float {
        var returnedValue:Null<Float> = playState.callOnScripts('eventEarlyTrigger', [event.event, event.value1, event.value2, event.value3, event.value4, event.strumTime], true);
        if(returnedValue != null && returnedValue != 0) {
            return returnedValue;
        }

        switch(event.event) {
            case 'Kill Henchmen': //Better timing so that the kill sound matches the beat intended
                return 280; //Plays 280ms before the actual position
        }
        return 0;
    }
}