require "DeadAirScore"
require "DeadAirPaper"
require "DeadAirComposition"
require "DeadAirSongEditor"
local D,S=DeadAir,DeadAirScore
D.Songs={drafts={}}
local C=D.Songs
local function send(command,args)local player=getSpecificPlayer(0);if player then sendClientCommand(player,"DeadAir",command,args or {})end end
local function message(text)
    D.notice=text
    if C.editor then C.editor.message=text;C.editor.saving=false end
    if C.panel then C.panel.message=text end
end
function C.saved(args)
    local item=S.find(getSpecificPlayer(0):getInventory(),args.item);if not item then message("The saved sheet is no longer in your inventory.");return end
    local score=S.validate(args.score);if not score and not args.composition then return end
    local composition=args.composition and DeadAirComposition.validate(args.composition)
    if args.composition and not composition then message("The saved song response was invalid.");return end
    if composition then DeadAirComposition.store(item,composition)
    else item:getModData().DeadAirScore=score;item:setName(score.title.." - "..score.partName);item:setCustomName(true)end
    C.drafts[args.item]=nil
    if args.mode=="part" then if C.editor then C.editor:close()end;C.open(item);return end
    if C.editor and C.editor.item:getID()==args.item then C.editor:acceptSaved(composition or DeadAirComposition.fromScore(score))end
    message(args.mode=="copy" and "Copied the song onto the extra sheet." or args.mode=="export" and "Copied the selected part for another musician." or "Saved the whole song to paper.")
end
function C.write(args)
    if isClient()then send("write",args)
    else local result,err=DeadAirPaper.write(getSpecificPlayer(0),args);if result then C.saved(result)else message(err)end end
end
function C.open(item)
    if C.lobby or C.net then message("Leave the ensemble before editing a part.");return end
    if C.editor then C.editor:close()end
    local saved=S.read(item)
    if not saved and not S.blank(item) then message("Use blank paper or an existing song part.");return end
    local draft=C.drafts[item:getID()]
    if draft and saved and draft.revision~=saved.revision then draft=nil;C.drafts[item:getID()]=nil end
    local score=draft or DeadAirComposition.read(item) or DeadAirComposition.fromScore(S.new())
    local importMessage;local originalCount=#score.parts
    if not draft and not item:getModData().DeadAirComposition then score,importMessage=DeadAirComposition.collect(score,getSpecificPlayer(0):getInventory())end
    C.stop();D.stop();D.editorActive=true
    local panel=DeadAirSongEditor:new(item,score);panel:initialise();panel:addToUIManager();panel:setVisible(true);C.editor=panel
    panel.dirty=draft~=nil or #score.parts>originalCount
    if importMessage then panel.message=importMessage end
    panel:updateMonitor()
end
function C.world()
    local t=D.worldTarget;if not t or not DeadAirWorld.atInstrument(getSpecificPlayer(0),t) then return nil end
    local sq=t.object:getSquare();return {x=sq:getX(),y=sq:getY(),z=sq:getZ()}
end
function C.stop(localOnly)
    if C.editor then C.editor:stop()end
    if C.net and D.api() then C.remoteMotion(C.net,getSpecificPlayer(0),true)end
    if D.api() and DeadAirMidi.scoreStop then DeadAirMidi.scoreStop()end
    D.scorePart=nil;D.scoreProfile=nil
    if C.net and not localOnly then if C.lobby then send("leave",{id=C.net.id})end;C.net=nil end
    if C.solo then C.solo=nil;D.stop()end
end
function C.play(item)
    local score=S.read(item);local profile=D.instrument(getSpecificPlayer(0))
    if not score then return end
    if not D.api() or not DeadAirMidi.scoreLoad then message("Restart and approve the updated DeadAir.jar.");return end
    if not profile or profile[1]~=score.profile then message("Equip "..S.names[score.profile+1]..", or take position at that placed instrument.");return end
    if C.editor or C.lobby or C.net then message("Close the editor or leave the current ensemble first.");return end
    if isClient()then C.ensemble(item);return end
    D.stop();D.configure();DeadAirMidi.openAudio()
    C.solo={item=item,score=score,at=getTimestampMs(),pending=true};message("Preparing the song...")
end
function C.context(index,context,items)
    if index~=0 then return end
    for _,entry in ipairs(items)do local item=entry;if not instanceof(item,"InventoryItem")then item=entry.items and entry.items[1]end
        if S.paper(item) and S.find(getSpecificPlayer(0):getInventory(),item:getID()) then
            if S.read(item)then
                context:addOption("Edit song (Musician)",item,C.open)
                context:addOption("Play song part (Musician)",item,C.play)
                if isClient()then context:addOption("Sync with musicians (Musician)",item,C.ensemble)end
                context:addOption("Copy song to blank paper",item,function(source)local blank=S.blankIn(getSpecificPlayer(0):getInventory());if blank then C.write({mode="copy",item=source:getID(),blank=blank:getID()})else message("You need another blank sheet of paper.")end end)
                context:addOption("Add or switch song parts",item,C.open)
            elseif S.blank(item)then context:addOption("Write a song (Musician)",item,C.open)end
            return
        end
    end
end
C.Lobby=ISPanel:derive("DeadAirEnsemble")
function C.Lobby:new(item)
    local o=ISPanel.new(self,math.max(0,(getCore():getScreenWidth()-640)/2),100,640,500)
    o.item=item;o.moveWithMouse=true;o.backgroundColor={r=.04,g=.055,b=.065,a=.98};o.message="Host an ensemble or join a nearby one for this song.";return o
end
function C.Lobby:initialise()
    ISPanel.initialise(self)
    local function b(x,y,w,title,fn)local o=ISButton:new(x,y,w,28,title,self,fn);o:initialise();self:addChild(o);return o end
    self.sessions=ISComboBox:new(16,74,606,28,self,nil);self.sessions:initialise();self:addChild(self.sessions)
    b(16,112,128,"Refresh nearby",function()send("list",{})end)
    b(154,112,126,"Host ensemble",function(p)send("host",{item=p.item:getID()})end)
    b(290,112,126,"Join selected",function(p)local row=C.rows and C.rows[p.sessions.selected];if row then send("join",{id=row.id,item=p.item:getID()})end end)
    b(426,112,196,"Leave ensemble",function()send("leave",{});C.stop(true);C.net=nil;C.lobby=nil;D.stop()end)
    b(16,386,180,"Confirm: I'm ready",function()
        if C.lobby then send("ready",{id=C.lobby.id,ready=true,world=C.world(),noise=D.value("noise")})end
    end)
    b(206,386,150,"Not ready",function()if C.lobby then send("ready",{id=C.lobby.id,ready=false})end end)
    b(366,386,256,"Start together (host)",function()if C.lobby then send("start",{id=C.lobby.id})end end)
    b(548,16,74,"Hide",function(p)p:setVisible(false);p:removeFromUIManager()end)
end
function C.Lobby:prerender()
    ISPanel.prerender(self)
    self:drawText("PLAY TOGETHER",16,14,.55,1,.8,1,UIFont.Large)
    local score=S.header(self.item);self:drawText(score and tostring(score.title).." / "..tostring(score.partName)or "Song sheet unavailable",16,48,.8,.9,.85,1,UIFont.Small)
    local lobby=C.lobby
    if lobby then
        self:drawText("Ensemble: "..lobby.phase,16,158,.9,.85,.55,1,UIFont.Small)
        for i,m in ipairs(lobby.members)do
            self:drawText((m.ready and "READY  " or "WAITING  ")..m.name.." / "..m.part,16,184+(i-1)*24,.75,.85,.8,1,UIFont.Small)
        end
    end
    self:drawText(self.message:sub(1,94),16,432,1,.8,.4,1,UIFont.Small)
    self:drawText("Everyone confirms Ready. The host starts after all parts are ready.",16,458,.65,.75,.72,1,UIFont.Small)
end
function C.ensemble(item)
    if C.editor then message("Close the song editor before joining an ensemble.");return end
    if not isClient() then C.play(item);return end
    if not D.api() or not DeadAirMidi.scoreLoad then message("Approve the updated Java engine first.");return end
    if C.panel then C.panel:setVisible(false);C.panel:removeFromUIManager()end
    C.panel=C.Lobby:new(item);C.panel:initialise();C.panel:addToUIManager();C.panel:setVisible(true)
    send("list",{});C.pingAt=0
end
function C.command(module,command,args)
    if module~="DeadAir" or type(args)~="table" then return end
    if command=="error"then message(args.message or "Song action failed.");return end
    if command=="saved"then C.saved(args);return end
    if command=="clock"then
        if not D.api() or type(args.sent)~="number" or type(args.server)~="number" or not C.pings or not C.pings[args.sent]then return end
        local time=DeadAirMidi.clock();local rtt=time-args.sent;C.pings[args.sent]=nil
        if rtt>=0 and (not C.bestRtt or rtt<C.bestRtt or time-(C.clockAt or 0)>30000) then C.bestRtt=rtt;C.offset=args.server-(args.sent+time)/2;C.clockAt=time end
        return
    end
    if command=="sessions"then
        C.rows=args.rows or {};if C.panel then C.panel.sessions:clear();for _,s in ipairs(C.rows)do C.panel.sessions:addOption(s.title.." / "..s.host.." ("..s.count.."/8)")end end;return
    end
    if command=="lobby"then C.lobby=args;message("Ensemble: "..args.phase);return end
    if command=="left"then
        if C.lobby and C.lobby.id==args.id then C.lobby=nil;C.stop(true);C.net=nil;D.stop();message(args.message or "Left the ensemble.")end;return
    end
    if command=="stop"then if C.net and C.net.id==args.id then C.stop(true);C.net=nil;D.stop();message(args.message or "Ensemble stopped.")end;return end
    if command=="prepare"then
        if not D.api() or not DeadAirMidi.scoreLoad or C.editor or C.solo then return end
        if C.net and C.net.id~=args.id then if C.lobby and C.lobby.id==args.id then send("loaded",{id=args.id,ok=false})end;return end
        if not S.integer(args.count,1,8)or not S.integer(args.bpm,30,300)or not S.integer(args.bars,1,S.MAX_BARS)then return end
        C.net={id=args.id,count=args.count,bpm=args.bpm,bars=args.bars,parts={},at=getTimestampMs()};D.configure();DeadAirMidi.openAudio();C.pingAt=0;return
    end
    local net=C.net;if not net or net.id~=args.id then return end
    if command=="part" and S.integer(args.index,1,net.count) and type(args.part)=="table" then
        local score=S.validate(args.part.score)
        if score and score.bpm==net.bpm and score.bars==net.bars then net.parts[args.index]={score=score,owner=args.part.owner,x=args.part.x,y=args.part.y,z=args.part.z,world=args.part.world}end
    elseif command=="start" and type(args.at)=="number"then net.start=args.at
    elseif command=="positions" and type(args.positions)=="table"then
        for i,p in ipairs(args.positions)do if net.parts[i] then net.parts[i].x=p.x;net.parts[i].y=p.y;net.parts[i].z=p.z end end
    end
end
function C.remoteMotion(net,player,stop)
    if not player or not net.playing then return end
    local players=getOnlinePlayers()
    for i,part in ipairs(net.parts)do
        if part.owner~=player:getOnlineID()then
            local actor
            for p=0,players:size()-1 do if players:get(p):getOnlineID()==part.owner then actor=players:get(p);break end end
            local instrument
            if actor then
                local item=actor:getPrimaryHandItem();instrument=item and D.instruments[item:getFullType()]
                if part.world then
                    local w=part.world;local square=getCell():getGridSquare(w.x,w.y,w.z)
                    if square then local objects=square:getObjects();for o=0,objects:size()-1 do
                        local target=DeadAirWorld.describe(objects:get(o))
                        if part.score.profile==9 and DeadAirKit.build(objects:get(o))then instrument=DeadAirInstruments.kit;break end
                        if target and target.instrument[1]==part.score.profile then instrument=target.instrument;break end
                    end end
                end
            end
            if actor and instrument and instrument[1]==part.score.profile then
                local state=part.live and DeadAirMidi.liveState(part.owner)or DeadAirMidi.scoreState(i-1)
                if type(state.attack)~="number" then state={attack=0,velocity=0,held=0,reset=0,resetAttack=0}end
                if not part.motion or part.motion.instrument~=instrument then
                    part.motion=DeadAirMotion.new(instrument,state,getTimestampMs());part.motion.lastAttack=math.max(0,state.attack-1)
                    part.drumMotion=instrument.drumMode and DeadAirDrumMotion.new(instrument,state,getTimestampMs(),true) or nil
                end
                if part.drumMotion then
                    DeadAirDrumMotion.drive(actor,instrument,part.drumMotion,state,getTimestampMs(),stop or not D.guitarEnabled)
                else
                local speed,phase=DeadAirMotion.update(part.motion,state,getTimestampMs())
                if stop or not D.guitarEnabled then speed=0;phase=instrument.readyPhase or (instrument.gesture=="strike" and 0 or -1) end
                -- Only drives matching DeadAir tracks already replicated by the game's action sync.
                DeadAirMidi.animate(actor,instrument.action,instrument.clip,speed,phase)
                end
            end
        end
    end
end
function C.tick()
    local player=getSpecificPlayer(0);if not player then return end
    if isClient() and D.api() and DeadAirMidi.clock then
        local time=DeadAirMidi.clock()
        if time>=(C.pingAt or 0)then
            C.pingAt=time+((C.net or C.panel) and 1000 or 10000);C.pings={[time]=true};send("clock",{sent=time})
        end
    end
    if C.editor then C.editor:update()end
    local solo=C.solo
    if solo then
        local instrument,item=D.instrument(player)
        if not S.find(player:getInventory(),solo.item:getID()) or not D.allowed(player) or not instrument or instrument[1]~=solo.score.profile then C.stop();return end
        if solo.pending then
            if DeadAirMidi.audioReady()then
                local err=DeadAirMidi.scoreLoad({S.native(solo.score)},solo.score.bpm,solo.score.bars*384,false)
                if err~=""then message(err);C.stop();return end
                D.scorePart=0;D.scoreProfile=solo.score.profile;DeadAirMidi.scoreStart(250);solo.pending=false;message("Playing "..solo.score.title)
            elseif getTimestampMs()-solo.at>15000 then message(DeadAirMidi.status());C.stop();return end
        else
            DeadAirMidi.scoreHeartbeat();if not DeadAirMidi.scoreActive()then C.stop();return end
            if D.value("noise") and getTimestampMs()>=(solo.noiseAt or 0)then
                solo.noiseAt=getTimestampMs()+500;local state=DeadAirMidi.scoreState(0)
                if state.attack~=(solo.noiseAttack or 0) or state.held>0 then
                    local radius=math.max(4,math.floor(instrument[3]*(.35+.65*state.velocity/127)))
                    addSound(player,math.floor(player:getX()),math.floor(player:getY()),math.floor(player:getZ()),radius,radius)
                end
                solo.noiseAttack=state.attack
            end
        end
    end
    local net=C.net;if not net then return end
    if not net.loaded and DeadAirMidi.audioReady() and C.offset then
        local parts={};for i=1,net.count do if not net.parts[i]then return end;parts[i]=S.native(net.parts[i].score)end
        local err=DeadAirMidi.scoreLoad(parts,net.bpm,net.bars*384,false)
        if err~=""then send("loaded",{id=net.id,ok=false});message(err);C.net=nil;return end
        net.loaded=true;send("loaded",{id=net.id,ok=true})
    end
    if not net.loaded and getTimestampMs()-net.at>15000 then send("loaded",{id=net.id,ok=false});message("Unable to prepare ensemble audio.");C.net=nil;return end
    if net.loaded and net.start and not net.playing then
        D.stop();DeadAirMidi.scoreStart(net.start-(DeadAirMidi.clock()+C.offset));net.playing=true
        for i,part in ipairs(net.parts)do if part.owner==player:getOnlineID()then D.scorePart=i-1;D.scoreProfile=part.score.profile;break end end
        message("Everyone is ready. Starting together...")
    end
    if net.playing then
        DeadAirMidi.scoreHeartbeat()
        for i,part in ipairs(net.parts)do
            local distance=math.sqrt((player:getX()-part.x)^2+(player:getY()-part.y)^2)
            DeadAirMidi.scoreGain(i-1,player:getZ()==part.z and math.max(0,1-distance/45)^2 or 0)
        end
        C.remoteMotion(net,player)
        if not DeadAirMidi.scoreActive()then C.stop();C.net=nil;D.stop()end
    end
end
function C.cleanup()
    C.stop();if C.editor then C.editor:close()end
    if C.lobby and isClient()then send("leave",{id=C.lobby.id})end
    C.lobby=nil;C.net=nil;C.solo=nil;C.pings=nil;C.offset=nil;C.bestRtt=nil
    if C.panel then C.panel:setVisible(false);C.panel:removeFromUIManager();C.panel=nil end
end
Events.OnFillInventoryObjectContextMenu.Add(C.context)
Events.OnServerCommand.Add(C.command)
