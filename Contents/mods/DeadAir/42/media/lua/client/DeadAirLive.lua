require "DeadAirLiveProtocol"
local D,P,S=DeadAir,DeadAirLiveProtocol,DeadAirScore
D.Live={remote={},seen={}}
local L=D.Live
local function api()return D.api() and DeadAirMidi.livePoll~=nil end
local function send(command,args)local player=getSpecificPlayer(0);if isClient() and player then sendClientCommand(player,"DeadAirLive",command,args)end end
function L.stopSending()
    if L.epoch then send("stop",{epoch=L.epoch});L.epoch=nil end
    if api()then DeadAirMidi.liveCapture(false)end
end
local function remove(owner)
    local part=L.remote[owner]
    if part and D.Songs then D.Songs.remoteMotion({playing=true,parts={part}},getSpecificPlayer(0),true)end
    if api()then DeadAirMidi.liveStop(owner)end
    L.remote[owner]=nil
end
function L.clearRemote()for owner in pairs(L.remote)do remove(owner)end;if api()then DeadAirMidi.liveStopAll()end end
function L.cleanup()L.stopSending();L.clearRemote();L.seen={};L.nextSend=nil;L.openAt=nil end
function L.status()
    if not isClient()then return "Live sharing: multiplayer only. Editor previews stay private." end
    local count=0;for _ in pairs(L.remote)do count=count+1 end
    return "Live MIDI: "..(L.epoch and "sharing nearby"or "not broadcasting").." / "..(D.value("hearLive")and (count.." nearby musician(s)")or "listening off")
end
local function deliver(part)
    if not part.pending or not DeadAirMidi.audioReady()then return end
    local packet=part.pending
    if part.waiting then packet.reset=true;packet.events="" end
    local gain=P.gain(getSpecificPlayer(0),part)
    if DeadAirMidi.liveReceive(part.owner,packet,gain)then part.pending=nil;part.waiting=nil;part.playing=true end
end
function L.command(module,command,args)
    if module~="DeadAirLive" or type(args)~="table" or not isClient() or not api()then return end
    local player=getSpecificPlayer(0)
    if not player or not S.integer(args.owner,0,65535)or args.owner==player:getOnlineID()or not S.integer(args.epoch,1,2147483647)then return end
    local old=L.seen[args.owner]
    if command=="stop"then
        if not S.integer(args.seq,0,2147483647)then return end
        if old and (args.epoch<old.epoch or (args.epoch==old.epoch and args.seq<old.seq))then return end
        L.seen[args.owner]={epoch=args.epoch,seq=args.seq};remove(args.owner);return
    end
    if command~="frame" or not D.value("hearLive")or player:isDead()then return end
    local frame=P.frame(args);if not frame or not P.position(args)then return end
    if old and (frame.epoch<old.epoch or (frame.epoch==old.epoch and frame.seq<=old.seq))then return end
    L.seen[args.owner]={epoch=frame.epoch,seq=frame.seq}
    if not P.near(player,args)then remove(args.owner);return end
    local part=L.remote[args.owner]
    if not part then
        local count=0;for _ in pairs(L.remote)do count=count+1 end
        if count>=8 then return end
        part={owner=args.owner,live=true,score={profile=frame.profile}};L.remote[args.owner]=part
    end
    part.score.profile=frame.profile;part.x=args.x;part.y=args.y;part.z=args.z;part.world=args.world
    part.at=getTimestampMs();part.pending=frame
    if not DeadAirMidi.audioReady()then part.waiting=true else deliver(part)end
end
function L.tick()
    if not isClient()or not api()then return end
    local player=getSpecificPlayer(0);if not player then L.cleanup();return end
    local now=getTimestampMs()
    if not D.value("hearLive")or player:isDead()then L.clearRemote()
    else
        local pending=false;local parts={}
        for owner,part in pairs(L.remote)do
            if now-part.at>1500 or not P.near(player,part)then remove(owner)
            else
                if part.pending then deliver(part);pending=pending or part.pending~=nil end
                DeadAirMidi.liveGain(owner,P.gain(player,part));parts[#parts+1]=part
            end
        end
        if pending and not DeadAirMidi.audioReady()and not DeadAirMidi.busy()and now>=(L.openAt or 0)then
            L.openAt=now+2000;D.configure();DeadAirMidi.openAudio()
        end
        if #parts>0 and D.Songs then D.Songs.remoteMotion({playing=true,parts=parts},player,false)end
    end
    local eligible=D.value("broadcastLive")and not D.editorActive and D.scorePart==nil
        and not(D.Songs and (D.Songs.lobby or D.Songs.solo)) and D.allowed(player)and DeadAirMidi.performing()
    local instrument=D.instrument(player)
    eligible=eligible and instrument~=nil and (not D.worldTarget or DeadAirWorld.atInstrument(player,D.worldTarget))
    if not eligible then L.stopSending();return end
    DeadAirMidi.liveCapture(true)
    if now<(L.nextSend or 0)then return end;L.nextSend=now+50
    local frame=DeadAirMidi.livePoll()
    if frame and frame.epoch then
        L.epoch=frame.epoch;frame.world=D.Songs and D.Songs.world()or nil
        send("frame",frame)
    end
end
Events.OnServerCommand.Add(L.command)
Events.OnTick.Add(L.tick)
Events.OnTickEvenPaused.Add(L.tick)
