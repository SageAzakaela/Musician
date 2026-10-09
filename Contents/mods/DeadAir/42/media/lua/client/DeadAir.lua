require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISComboBox"
require "PZAPI/ModOptions"
require "DeadAirInstruments"
require "DeadAirPerformanceAction"
require "DeadAirWorld"
require "TimedActions/ISEquipWeaponAction"
require "ISUI/ISInventoryPaneContextMenu"
require "MusicianSoundfonts"

DeadAir = DeadAir or {}
local D = DeadAir
D.instruments = DeadAirInstruments.held
local options=PZAPI.ModOptions:create("DeadAir","Musician")
options:addTitle("MIDI connection")
options:addDescription("MIDI and audio use the game\'s built-in Java support. No extra audio runtime is needed.")
local input=options:addComboBox("midiInput","MIDI input","Refresh inputs after plugging in your controller. Channel 0 accepts every string on a MIDI guitar.")
input:addItem("Refresh to find MIDI inputs",true)
options:addButton("refreshInputs","Refresh MIDI inputs",nil,function() D.refreshInputs() end)
options:addButton("connectInput","Connect MIDI",nil,function()
    if not D.api() then return end
    local chosenBackend=2
    if chosenBackend~=D.scannedBackend then D.refreshInputs();D.notice="Inputs refreshed. Choose your controller and press Connect.";return end
    for _,id in ipairs({"audioResponse","touchResponse"})do local o=options:getOption(id);if o.element then o:setValue(o.element.selected)end end
    for _,id in ipairs({"volume","transpose","channel"}) do
        local o=options:getOption(id)
        if o.element and o.element.getCurrentValue then o:setValue(o.element:getCurrentValue()) end
    end
    local choice=input.element and input.element.selected or input:getValue()
    local key=D.inputKeys and D.inputKeys[choice]
    local index=key and DeadAirMidi.inputIndex and DeadAirMidi.inputIndex(key) or choice-1
    if index<0 or index>=DeadAirMidi.inputCount() then D.notice="Selected input is disconnected. Refresh and choose it again.";return end
    D.configure();input:setValue(choice);DeadAirMidi.connect(index)
end)
options:addButton("disconnectInput","Disconnect MIDI",nil,function() D.stop();if D.api() then DeadAirMidi.disconnect() end end)
options:addButton("soundfonts","Soundfonts / instrument sounds",nil,function() MusicianSoundfonts.show() end)
options:addTitle("Performance")
options:addDescription("Connect above, equip an instrument, and play a MIDI note. Right-click a piano or drum to take position. Right-click blank paper to write a song.")
options:addSlider("volume","Listening volume",0,100,1,30,"Master volume for live instruments, songs and clip previews. Louder output with soft peak limiting. This changes your listening level, not the instrument's world noise.")
options:addSlider("transpose","Transpose (semitones)",-24,24,1,0)
options:addSlider("channel","MIDI channel (0 = all)",0,16,1,0)
local touch=options:addComboBox("touchResponse","Touch response","Soft touch makes light notes easier to hear. Natural uses the soundfont's original velocity response. Applies to your listening only; recorded notes and transmitted MIDI keep their original velocities.")
touch:addItem("Natural",false)
touch:addItem("Soft touch",true)
options:addTickBox("noise","Music attracts zombies",true)
options:addTickBox("guitarMode","Playing animations",true,"MIDI drives strums, bowing, key presses, wind phrases and percussion gestures. Your previous guitar-mode preference is preserved.")
options:addTickBox("broadcastLive","Share live MIDI with nearby players",true,"Multiplayer: broadcasts your equipped instrument while playing in the world. Songbook monitoring and previews stay private.")
options:addTickBox("hearLive","Hear nearby live musicians",true,"Multiplayer: hear up to eight nearby live musicians, with distance fading. You do not need a MIDI controller.")
local response=options:addComboBox("audioResponse","Audio response","Fast targets 2.7 ms of queued audio at 48 kHz. Your Windows driver adds its own delay. Balanced and Extra stability allow more headroom if playback crackles. Reconnect to apply.")
response:addItem("Fast",true)
response:addItem("Balanced",false)
response:addItem("Extra stability",false)
options:addKeyBind("openKey","Show / hide performance panel",Keyboard.KEY_F10)
options:addKeyBind("panicKey","Panic: stop every note",Keyboard.KEY_F11)
options:addKeyBind("guitarKey","Toggle playing animations",Keyboard.KEY_F12)
D.options=options

function D.api() return DeadAirMidi ~= nil end
function D.animationReady(instrument)
    instrument=instrument or D.instrument(getSpecificPlayer(0))
    if not (instrument and instrument.clip and D.api() and DeadAirMidi.animationReady and DeadAirMidi.animate and DeadAirMidi.motionState) then return false end
    if instrument.tracks then for _,track in ipairs(instrument.tracks)do if not DeadAirMidi.animationReady(track.clip)then return false end end end
    return DeadAirMidi.animationReady(instrument.clip)
end
function D.animationStatus(instrument)
    instrument=instrument or D.instrument(getSpecificPlayer(0))
    if not instrument then return "Select an instrument to check its playing pose." end
    if not instrument.clip then return "MIDI sound available; no dedicated playing animation yet." end
    if not D.api() or (DeadAirMidi.animationReady==nil or DeadAirMidi.animate==nil or DeadAirMidi.motionState==nil) then
        return "Playing animation: restart and approve the updated DeadAir.jar."
    end
    local action=D.performanceAction
    if action and action.instrument==instrument and action.liveTracks~=nil then
        return action.liveTracks>0 and "Playing animation: connected to MIDI" or "Playing animation: waiting for the game's action track"
    end
    return D.animationReady(instrument) and "Playing animation: ready" or "Playing animation: missing. Restart with Musician enabled."
end
function D.value(id) return options:getOption(id):getValue() end
function D.instrument(player)
    if not player then return nil end
    if D.worldTarget then
        if DeadAirWorld.valid(D.worldTarget) then return D.worldTarget.instrument,D.worldTarget.object end
        return nil
    end
    local item=player:getPrimaryHandItem()
    if item and item:getCondition()>0 then return D.instruments[item:getFullType()],item end
    return nil
end
function D.allowed(player)
    if not player or player:isDead() or player:isAsleep() or player:getVehicle() or player:isPlayerMoving() or player:isAiming() then return false end
    if isGamePaused() or getCore():isDoingTextEntry() then return false end
    return true
end
function D.stop()
    if D.Live then D.Live.stopSending()end
    D.autoItem=nil;D.autoAttack=nil
    D.playingItem=nil
    D.lastX=nil;D.lastY=nil
    if D.api() then DeadAirMidi.perform(false) end
    if D.performanceAction then D.performanceAction:requestStop() end
    if D.approachAction then
        local walk=D.approachAction;D.approachAction=nil
        local queue=ISTimedActionQueue.getTimedActionQueue(walk.character)
        if queue:indexOf(walk)~=-1 then
            if walk.action then walk:forceComplete() else queue:removeFromQueue(walk) end
        end
    end
end
function D.panic()
    if D.Live then D.Live.stopSending();D.Live.clearRemote()end
    if D.Songs then D.Songs.stop() end
    if D.api() then DeadAirMidi.panic() end
    if D.performanceAction then D.performanceAction:panic() end
end
function D.refreshInputs()
    if D.api() and not DeadAirMidi.busy() then
        local selected=input.element and input.element.selected or input:getValue()
        local chosenBackend=2
        if DeadAirMidi.midiBackend then DeadAirMidi.midiBackend(chosenBackend) end
        if D.scannedBackend~=chosenBackend then D.inputKeys=nil;selected=1 end
        D.scanBackend=chosenBackend
        D.scanSelection=D.inputKeys and D.inputKeys[selected]
        D.scanName=input.values[selected]
        D.scanIndex=selected
        DeadAirMidi.refresh();D.scanPending=true
    end
end
function D.connectionTick()
    if not D.api() then return end
    if D.scanPending and not DeadAirMidi.busy() then
        D.scanPending=false;D.scannedBackend=D.scanBackend
        local selected=D.scanIndex or input:getValue();input.values={};D.inputKeys={}
        local matched=nil
        for i=0,DeadAirMidi.inputCount()-1 do
            input:addItem(DeadAirMidi.inputName(i),false)
            local key=DeadAirMidi.inputKey and DeadAirMidi.inputKey(i) or DeadAirMidi.inputName(i)
            D.inputKeys[i+1]=key
            if key==D.scanSelection then matched=i+1 end
        end
        if D.scanSelection and not matched then
            input:addItem((D.scanName or "Selected input"):gsub(" %(disconnected%)$", "").." (disconnected)",false)
            selected=#input.values;D.inputKeys[selected]=D.scanSelection
        elseif matched then selected=matched end
        if #input.values==0 then input:addItem("No MIDI inputs found",false) end
        if input.element then input.element:clear();for _,name in ipairs(input.values) do input.element:addOption(name) end end
        input:setValue(math.max(1,math.min(selected,#input.values)))
    end
    local b=options:getOption("connectInput")
    local choice=input.element and input.element.selected or input:getValue()
    b:setEnabled(not DeadAirMidi.busy() and choice>0 and choice<=DeadAirMidi.inputCount())
    if b.element then
        local title="Connect MIDI"
        if DeadAirMidi.connected() then title=DeadAirMidi.noteCount and ("Reconnect MIDI ("..string.format("%.0f",DeadAirMidi.noteCount()).." notes)") or "Reconnect MIDI" end
        b.element:setTitle(title)
        b.element:setTooltip(DeadAirMidi.status().."\n"..(DeadAirMidi.inputStatus and DeadAirMidi.inputStatus() or "Restart and approve DeadAir.jar 0.13.0 for input status.").."\n"..(DeadAirMidi.inputRouteStatus and DeadAirMidi.inputRouteStatus() or "").."\n"..DeadAirMidi.audioStatus())
    end
    if isGamePaused() then
        -- Private editor audio can continue while the world is paused.
        if D.Songs and D.Songs.editor then D.Songs.editor:update()
        else
            if D.Songs and (D.Songs.solo or D.Songs.net) then D.Songs.stop() end
            if DeadAirMidi.performing() then D.stop() end
        end
    end
end
function D.configure()
    if not D.api() then return end
    local instrument=D.instrument(getSpecificPlayer(0))
    if D.editorActive and D.Songs and D.Songs.editor then instrument={D.Songs.editor.instrument.selected-1}end
    if DeadAirMidi.audioResponse then DeadAirMidi.audioResponse(D.value("audioResponse")) end
    if DeadAirMidi.touchResponse then DeadAirMidi.touchResponse(D.value("touchResponse")) end
    if DeadAirMidi.audioDriver then DeadAirMidi.audioDriver(4) end
    DeadAirMidi.configure(instrument and instrument[1] or 0,D.editorActive and 0 or D.value("transpose"),D.value("channel")-1,D.value("volume")/100)
end
function options:apply()
    if D.guitarEnabled~=D.value("guitarMode") then D.stop() end
    D.guitarEnabled=D.value("guitarMode")
    D.configure()
end
function D.toggleGuitar()
    options:getOption("guitarMode"):setValue(not D.value("guitarMode"))
    options:apply();PZAPI.ModOptions:save()
end
function D.startPerformance(fromNote)
    local player=getSpecificPlayer(0)
    local instrument,item=D.instrument(player)
    if not D.api() or not D.allowed(player) or not instrument or not (DeadAirMidi.connected() or D.scorePart~=nil) then return end
    if D.scorePart~=nil and not DeadAirMidi.scoreActive() then return end
    if D.performanceAction then D.notice="Finishing the previous performance...";return end
    local animated=D.guitarEnabled and instrument.clip~=nil
    if animated and not D.animationReady(instrument) then
        D.notice=D.animationStatus(instrument);print("[Musician] "..D.notice);return
    end
    local queue=ISTimedActionQueue.getTimedActionQueue(player)
    if #queue.queue>0 then D.notice="Finish the current action before performing.";return end
    if D.worldTarget then
        local ok,reason=DeadAirWorld.prepare(player,D.worldTarget)
        if not ok then D.notice=reason;return end
    end
    local action=DeadAirPerformanceAction:new(player,item,instrument,D.worldTarget,animated)
    action.fromNote=fromNote;action.scorePart=D.scorePart
    D.performanceAction=action;D.playingItem=item;D.noiseAt=0;D.notice=nil
    if D.worldTarget and not DeadAirWorld.atInstrument(player,D.worldTarget) then
        local walk=ISWalkToTimedAction:new(player,D.worldTarget.stand)
        D.approachAction=walk
        ISTimedActionQueue.add(walk)
        D.notice="Walking to the instrument..."
    end
    ISTimedActionQueue.add(action)
    if queue:indexOf(action)==-1 then action:cleanup();D.notice="The survivor cannot start that action right now." end
end
function D.equipInstrument(item,playerIndex)
    local player=getSpecificPlayer(playerIndex)
    if not D.allowed(player) or not item or not D.instruments[item:getFullType()] or item:getCondition()<=0 then return end
    D.stop();D.worldTarget=nil
    ISInventoryPaneContextMenu.transferIfNeeded(player,item)
    ISTimedActionQueue.add(ISEquipWeaponAction:new(player,item,50,true,false))
    D.notice="Equipping instrument. Play a MIDI note when ready."
end
D.equipGuitar=D.equipInstrument

D.Panel=ISPanel:derive("DeadAirPanel")
function D.Panel:new(x,y)
    local o=ISPanel.new(self,x,y,560,264)
    o.backgroundColor={r=.055,g=.065,b=.07,a=.96};o.moveWithMouse=true;return o
end
function D.Panel:initialise()
    ISPanel.initialise(self)
    self.hideButton=ISButton:new(470,12,72,26,"Hide",self,function(panel)panel:hide()end)
    self.hideButton:initialise();self:addChild(self.hideButton)
    local panic=ISButton:new(16,224,100,26,"Stop sound",self,D.panic);panic:initialise();self:addChild(panic)
end
function D.Panel:hide()self:setVisible(false);self:removeFromUIManager()end
function D.Panel:close()self:hide();D.panel=nil end
function D.Panel:prerender()
    ISPanel.prerender(self)
    self:drawText("MUSICIAN / 0.13.0",16,14,.6,1,.8,1,UIFont.Large)
    local instrument=D.instrument(getSpecificPlayer(0))
    local lines={D.api() and DeadAirMidi.status() or "Approve the updated DeadAir.jar and restart.",
        D.api() and DeadAirMidi.inputStatus and DeadAirMidi.inputStatus() or "Restart and approve DeadAir.jar 0.13.0 for input status.",
        "Instrument: "..(instrument and instrument[2] or "equip one to play"),
        D.api() and DeadAirMidi.inputRouteStatus and DeadAirMidi.inputRouteStatus() or "Restart and approve DeadAir.jar 0.13.0 for input status.",
        D.api() and DeadAirMidi.audioStatus() or "",D.animationStatus(),
        D.Live and D.Live.status()or "Right-click a sheet of paper to write, edit or play a song.",D.notice or "F10 hides this window. MIDI stays connected."}
    for i,line in ipairs(lines)do self:drawText(line:sub(1,85),16,48+(i-1)*21,.78,.85,.82,1,UIFont.Small)end
end
function D.open()
    if D.panel and D.panel:isVisible() then D.panel:hide() else D.show() end
end
function D.show()
    if D.panel then
        if not D.panel:isVisible() then D.panel:setVisible(true);D.panel:addToUIManager() end
        D.panel:bringToTop()
        return
    end
    if not getSpecificPlayer(0) then return end
    local w,h=getCore():getScreenWidth(),getCore():getScreenHeight()
    local panel=D.Panel:new(math.max(0,(w-560)/2),math.max(0,(h-478)/2))
    panel:initialise();panel:setVisible(true);panel:addToUIManager();D.panel=panel
end
function D.context(playerIndex,context,items)
    if playerIndex~=0 then return end
    local player=getSpecificPlayer(playerIndex)
    for _,entry in ipairs(items) do
        local item=entry
        if not instanceof(entry,"InventoryItem") then item=entry.items and entry.items[1] end
        if item and D.instruments[item:getFullType()] and item:getCondition()>0 then
            context:addOption("Equip for MIDI (Musician)",item,D.equipInstrument,playerIndex)
        end
        if item and D.instruments[item:getFullType()] and item==player:getPrimaryHandItem() then
            context:addOption("Ready for MIDI (Musician)",nil,function() D.stop();D.worldTarget=nil end)
            return
        end
    end
end
function D.tick()
    if not D.api() then return end
    if D.Songs and D.Songs.tick then D.Songs.tick() end
    if D.editorActive then return end
    local player=getSpecificPlayer(0)
    local instrument,item=D.instrument(player)
    if D.approachAction then
        local queue=ISTimedActionQueue.getTimedActionQueue(player)
        if not player or player:isDead() or player:getVehicle() or not DeadAirWorld.valid(D.worldTarget) then D.stop();return end
        if queue:indexOf(D.approachAction)~=-1 then return end
        D.approachAction=nil
    end
    if D.scorePart~=nil then
        if not D.allowed(player) or not instrument or instrument[1]~=D.scoreProfile then
            if D.Songs then D.Songs.stop() end;D.stop();return
        end
        if not D.performanceAction then D.startPerformance(false) end
        return
    end
    if not D.allowed(player) or not instrument or not DeadAirMidi.connected() then D.stop();return end
    if D.worldTarget and not DeadAirWorld.atInstrument(player,D.worldTarget) then D.stop();return end
    local queue=ISTimedActionQueue.getTimedActionQueue(player)
    if not D.performanceAction and #queue.queue>0 then D.stop();return end
    if D.autoItem~=item then
        D.stop();D.configure();D.autoItem=item
        D.autoAttack=DeadAirMidi.attackSerial()
    end
    if not DeadAirMidi.performing() then DeadAirMidi.perform(true);D.autoAttack=DeadAirMidi.attackSerial() end
    DeadAirMidi.heartbeat()
    local attack=DeadAirMidi.attackSerial()
    if attack~=(D.autoAttack or attack) then
        if not D.performanceAction then D.startPerformance(true) end
        D.autoAttack=attack
    end
    if D.performanceAction and D.performanceAction.started and item~=D.playingItem then D.stop();return end
    local now=getTimestampMs()
    if now>=(D.noiseAt or 0) then
        D.noiseAt=now+500;local activity=DeadAirMidi.consumeActivity()
        if D.value("noise") and activity>0 then
            local radius=math.max(4,math.floor(instrument[3]*(.35+.65*activity/127)))
            addSound(player,math.floor(player:getX()),math.floor(player:getY()),math.floor(player:getZ()),radius,radius)
        end
    end
end
function D.key(key)
    if key==D.value("panicKey") then D.panic();return end
    if getCore():isDoingTextEntry() then return end
    if key==D.value("guitarKey") and getSpecificPlayer(0) then D.toggleGuitar()
    elseif key==D.value("openKey") then D.open() end
end
function D.cleanup()
    if MusicianSoundfonts.panel then MusicianSoundfonts.panel:close()end
    if D.Live then D.Live.cleanup()end
    if D.Songs then D.Songs.cleanup() end
    D.stop();D.lastX=nil;D.lastY=nil
    if D.performanceAction then D.performanceAction:cleanup() end
    D.worldTarget=nil
    if D.panel then D.panel:close() end
    if D.api() then DeadAirMidi.disconnect() end
end
Events.OnFillInventoryObjectContextMenu.Add(D.context)
Events.OnFillWorldObjectContextMenu.Add(DeadAirWorld.context)
Events.OnKeyPressed.Add(D.key)
Events.OnTick.Add(D.tick)
Events.OnTickEvenPaused.Add(D.connectionTick)
Events.OnPlayerDeath.Add(D.cleanup)
Events.OnMainMenuEnter.Add(D.cleanup)
Events.OnGameStart.Add(function()
    MusicianSoundfonts.sync()
    D.stop();D.worldTarget=nil;D.guitarEnabled=D.value("guitarMode");D.configure();D.refreshInputs()
    print("[Musician] "..D.animationStatus())
end)

require "DeadAirSongs"
require "DeadAirLive"
