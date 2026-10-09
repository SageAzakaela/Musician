require "DeadAirServer"
require "DeadAirLiveProtocol"
DeadAirLiveServer={streams={},rates={},serial=0}
local L,P=DeadAirLiveServer,DeadAirLiveProtocol
local function now()return getTimestampMs()end
local function reply(player,command,args)sendServerCommand(player,"DeadAirLive",command,args)end
local function finish(id)
    local s=L.streams[id];if not s then return end
    for _,p in pairs(s.listeners)do reply(p,"stop",{owner=id,epoch=s.epoch,seq=s.frame and s.frame.seq or 0})end
    L.streams[id]=nil
end
local function current(s)return {x=s.player:getX(),y=s.player:getY(),z=s.player:getZ()}end
local function valid(s)return not DeadAirServer.inEnsemble(s.player) and DeadAirServer.validInstrument(s.player,s.profile,s.world)end
local function forward(s,frame,initial)
    local pos=current(s);local listeners={};local players=getOnlinePlayers()
    for i=0,players:size()-1 do local p=players:get(i);local id=p:getOnlineID()
        if p~=s.player and not p:isDead() and P.near(p,pos)then
            listeners[id]=p
            local data={v=1,owner=s.player:getOnlineID(),epoch=s.epoch,seq=frame.seq,at=frame.at,profile=s.profile,
                events=frame.events,state=frame.state,reset=frame.reset,x=pos.x,y=pos.y,z=pos.z,world=s.world}
            -- Joining midway should reconstruct held notes, never replay old drum/strum bursts.
            if not initial and s.listeners[id]~=p then data.reset=true;data.events="" end
            reply(p,"frame",data)
        end
    end
    for id,p in pairs(s.listeners)do if listeners[id]~=p then reply(p,"stop",{owner=s.player:getOnlineID(),epoch=s.epoch,seq=frame.seq})end end
    s.listeners=listeners
end
function L.command(module,command,p,args)
    if module~="DeadAirLive" or not p or type(args)~="table"then return end
    local id=p:getOnlineID();local time=now();local s=L.streams[id]
    if command=="stop"then if s and s.player==p and args.epoch==s.sourceEpoch then finish(id)end;return end
    if command~="frame"then return end
    local rate=L.rates[id]
    if not rate or rate.player~=p then rate={player=p,at=time,packets=0,events=0,lastEpoch=0,lastSeq=0};L.rates[id]=rate end
    if time-rate.at>=1000 then rate.at=time;rate.packets=0;rate.events=0 end
    rate.packets=rate.packets+1
    if rate.packets>40 then finish(id);return end
    local frame,count=P.frame(args);if not frame then finish(id);return end
    rate.events=rate.events+count;if rate.events>2000 then finish(id);return end
    if frame.epoch<rate.lastEpoch or (frame.epoch==rate.lastEpoch and frame.seq<=rate.lastSeq)then return end
    if DeadAirServer.inEnsemble(p) or not DeadAirServer.validInstrument(p,frame.profile,args.world)then finish(id);return end
    if s and (s.player~=p or s.sourceEpoch~=frame.epoch or s.profile~=frame.profile or frame.at<s.at)then finish(id);s=nil end
    if not s then
        local total=0;for _ in pairs(L.streams)do total=total+1 end;if total>=P.MAX_STREAMS then return end
        L.serial=L.serial+1;s={player=p,sourceEpoch=frame.epoch,epoch=L.serial,profile=frame.profile,listeners={}}
        L.streams[id]=s
    end
    if args.world then s.world={x=args.world.x,y=args.world.y,z=args.world.z}else s.world=nil end
    local initial=s.frame==nil
    rate.lastEpoch=frame.epoch;rate.lastSeq=frame.seq;s.at=frame.at;s.touched=time;s.frame=frame
    forward(s,frame,initial)
end
function L.tick()
    if not isServer()then return end
    local time=now();if time<(L.nextCheck or 0)then return end;L.nextCheck=time+250
    local players=getOnlinePlayers();local online={}
    for i=0,players:size()-1 do local p=players:get(i);online[p:getOnlineID()]=p end
    for id,s in pairs(L.streams)do
        if online[id]~=s.player or time-s.touched>1500 or not valid(s)then finish(id)
        else
            local pos=current(s)
            for listener,p in pairs(s.listeners)do if online[listener]~=p or not P.near(p,pos)or p:isDead()then reply(p,"stop",{owner=id,epoch=s.epoch,seq=s.frame.seq});s.listeners[listener]=nil end end
        end
    end
    for id,rate in pairs(L.rates)do if online[id]~=rate.player then L.rates[id]=nil end end
end
Events.OnClientCommand.Add(L.command)
Events.OnTick.Add(L.tick)
