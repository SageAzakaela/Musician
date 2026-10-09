require "DeadAirScore"
require "DeadAirPaper"
require "DeadAirKit"
-- Server owns membership, score snapshots, readiness and the shared start time.
DeadAirServer={sessions={},serial=0,rates={}}
local N,S=DeadAirServer,DeadAirScore
local profiles={Keytar=0,GuitarAcoustic=1,GuitarElectric=2,GuitarElectricBass=3,Banjo=4,Flute=5,Trumpet=6,Saxophone=7,Violin=8,Drumstick=9,Harmonica=10,Whistle=11,Whistle_Bone=11,TuningFork=12}
local piano={recreational_01_8=true,recreational_01_9=true,recreational_01_12=true,recreational_01_13=true,recreational_01_40=true,recreational_01_41=true,recreational_01_48=true,recreational_01_49=true}
local function now()return getTimestampMs()end
local function reply(p,command,args)sendServerCommand(p,"DeadAir",command,args)end
local function errorTo(p,text)reply(p,"error",{message=text})end
local function near(a,b,r)return a and b and a:getZ()==b:getZ() and (a:getX()-b:getX())^2+(a:getY()-b:getY())^2<=r*r end
local function member(session,p)for _,m in ipairs(session.members)do if m.player==p then return m end end end
local function sessionFor(p)for _,s in pairs(N.sessions)do if member(s,p)then return s end end end
local function online(p)
    local list=getOnlinePlayers();for i=0,list:size()-1 do if list:get(i)==p then return true end end;return false
end
local function instrument(p,profile,world)
    if p:isDead() or p:isAsleep() or p:getVehicle() or p:isPlayerMoving() or p:isAiming() then return false end
    if world then
        if type(world)~="table" then return false end
        if not S.integer(world.x,-100000,100000) or not S.integer(world.y,-100000,100000) or not S.integer(world.z,-32,32) then return false end
        if p:getZ()~=world.z or (p:getX()-world.x-.5)^2+(p:getY()-world.y-.5)^2>4 then return false end
        local square=getCell():getGridSquare(world.x,world.y,world.z);if not square then return false end
        local objects=square:getObjects()
        if profile==9 then
            for i=0,objects:size()-1 do local kit=DeadAirKit.build(objects:get(i))
                if kit and math.floor(p:getX())==kit.x and math.floor(p:getY())==kit.y then return true end
            end
            return false
        end
        for i=0,objects:size()-1 do local spr=objects:get(i):getSprite();if spr then
            if profile==0 and piano[spr:getName()] then return true end
            local props=spr:getProperties();local group=props and props:get("GroupName");local custom=props and props:get("CustomName")
            for key,value in pairs({Kick=13,Tom=14,Snare=15})do if profile==value and ((custom=="Drum" and group==key) or custom==key.." Drum")then return true end end
        end end
        return false
    end
    local item=p:getPrimaryHandItem();return item and item:getCondition()>0 and profiles[item:getType()]==profile
end
local function sheet(m,s,headerOnly)
    local item=S.find(m.player:getInventory(),m.item);local score=headerOnly and S.header(item)or S.read(item)
    return type(score)=="table"and score.song==s.song and score.part==m.part and score.revision==m.revision and score.profile==m.profile and score.bpm==s.bpm and score.bars==s.bars and score or nil
end
local function state(s)
    local roster={}
    for _,m in ipairs(s.members)do roster[#roster+1]={id=m.player:getOnlineID(),name=m.player:getUsername(),part=m.partName,ready=m.ready==true,loaded=m.loaded==true}end
    for _,m in ipairs(s.members)do reply(m.player,"lobby",{id=s.id,title=s.title,host=s.host:getOnlineID(),phase=s.phase,members=roster})end
end
local function cancel(s,reason)
    for _,p in ipairs(s.listeners or {})do reply(p,"stop",{id=s.id,message=reason})end
    for _,m in ipairs(s.members)do reply(m.player,"left",{id=s.id,message=reason})end
    N.sessions[s.id]=nil
end
local function leave(p)
    local s=sessionFor(p);if not s then return end
    if s.host==p or s.phase~="gathering" then cancel(s,"The ensemble stopped.");return end
    for i,m in ipairs(s.members)do if m.player==p then table.remove(s.members,i);break end end
    for _,m in ipairs(s.members)do m.ready=false end
    reply(p,"left",{id=s.id});state(s)
end
local function add(s,p,item,score)
    s.members[#s.members+1]={player=p,item=item:getID(),part=score.part,revision=score.revision,profile=score.profile,partName=score.partName,ready=false}
    for _,m in ipairs(s.members)do m.ready=false end;s.touched=now();state(s);return true
end
local function inviteListener(s,p)
    s.listeners[#s.listeners+1]=p
    reply(p,"prepare",{id=s.id,bpm=s.bpm,bars=s.bars,count=#s.parts})
    for index,part in ipairs(s.parts)do reply(p,"part",{id=s.id,index=index,part=part})end
    if s.start then reply(p,"start",{id=s.id,at=s.start})end
end
local function prepare(s)
    s.parts={};s.listeners={};s.phase="loading";s.touched=now()
    for _,m in ipairs(s.members)do
        local score=sheet(m,s)
        if not score or not instrument(m.player,m.profile,m.world) then cancel(s,"A musician's paper or instrument changed.");return end
        s.parts[#s.parts+1]={score=score,owner=m.player:getOnlineID(),x=m.player:getX(),y=m.player:getY(),z=m.player:getZ(),world=m.world};m.loaded=false
        m.notes=S.decode(score.notes,score.bars*384)
    end
    local players=getOnlinePlayers()
    for i=0,players:size()-1 do local p=players:get(i)
        if near(p,s.host,60) then
            inviteListener(s,p)
        end
    end
    state(s)
end
function N.command(module,command,p,args)
    if module~="DeadAir" or type(args)~="table" or not p then return end
    local id=p:getOnlineID();local r=N.rates[id] or {at=now(),n=0};N.rates[id]=r
    if now()-r.at>1000 then r.at=now();r.n=0 end;r.n=r.n+1;if r.n>20 then return end
    if command=="clock" then if type(args.sent)=="number" then reply(p,"clock",{sent=args.sent,server=now()})end;return end
    if command=="write" then
        local s=sessionFor(p);if s then return errorTo(p,"Leave the ensemble before editing its sheets.")end
        local result,err=DeadAirPaper.write(p,args);if result then reply(p,"saved",result)else errorTo(p,err)end;return
    end
    if command=="leave" then leave(p);return end
    if command=="list" then
        local rows={}
        for _,s in pairs(N.sessions)do if s.phase=="gathering" and near(p,s.host,30) then rows[#rows+1]={id=s.id,title=s.title,host=s.host:getUsername(),song=s.song,count=#s.members}end end
        reply(p,"sessions",{rows=rows});return
    end
    if command=="host" or command=="join" then
        if sessionFor(p)then return errorTo(p,"Leave your current ensemble first.")end
        local item=S.find(p:getInventory(),args.item);local score=S.read(item)
        if not score then return errorTo(p,"Carry a saved song part first.")end
        if command=="host" then
            local count=0;for _ in pairs(N.sessions)do count=count+1 end;if count>=32 then return errorTo(p,"Too many ensembles are active.")end
            N.serial=N.serial+1;local s={id=tostring(now()).."-"..N.serial,host=p,title=score.title,song=score.song,bpm=score.bpm,bars=score.bars,members={},phase="gathering",touched=now()}
            N.sessions[s.id]=s;add(s,p,item,score)
        else
            local s=N.sessions[args.id]
            if not s or s.phase~="gathering" or not near(p,s.host,30) or #s.members>=8 then return errorTo(p,"That ensemble is unavailable.")end
            if s.song~=score.song or s.bpm~=score.bpm or s.bars~=score.bars then return errorTo(p,"Use a part of the same song with the same tempo and length.")end
            local ok,err=add(s,p,item,score);if not ok then errorTo(p,err)end
        end;return
    end
    local s=N.sessions[args.id];local m=s and member(s,p)
    if not m then return end
    if command=="ready" and args.ready==false and s.phase~="gathering" then cancel(s,"A musician withdrew their readiness.");return end
    if command=="ready" and s.phase=="gathering" then
        if args.ready~=true then m.ready=false;state(s);return end
        if not sheet(m,s) or not instrument(p,m.profile,args.world) then return errorTo(p,"Equip this part's instrument, or take position at its piano or drum.")end
        m.world=args.world;m.noise=args.noise~=false;m.ready=true;s.touched=now();state(s)
    elseif command=="start" and s.host==p and s.phase=="gathering" then
        for _,v in ipairs(s.members)do if not v.ready then return errorTo(p,"Every musician must confirm Ready first.")end end
        prepare(s)
    elseif command=="loaded" and s.phase=="loading" then
        if args.ok~=true then cancel(s,"A musician could not prepare audio.");return end
        m.loaded=true
        for _,v in ipairs(s.members)do if not v.loaded then state(s);return end end
        s.phase="scheduled";s.start=now()+3000;s.finish=s.start+s.bars*4*60000/s.bpm+1000
        for _,listener in ipairs(s.listeners)do reply(listener,"start",{id=s.id,at=s.start})end;state(s)
    end
end
function N.tick()
    local time=now();if time<(N.nextCheck or 0)then return end;N.nextCheck=time+250
    for _,s in pairs(N.sessions)do
        local reason
        for _,m in ipairs(s.members)do
            if not online(m.player) or m.player:isDead() or not near(m.player,s.host,30) or not sheet(m,s,true) then reason="A musician left or no longer has their part.";break end
            if m.ready and not instrument(m.player,m.profile,m.world) then
                if s.phase=="gathering" then m.ready=false;state(s)else reason="A musician stopped playing.";break end
            end
        end
        if s.finish and time>s.finish then reason="Song finished." end
        if s.phase=="loading" and time-s.touched>20000 then reason="Audio preparation timed out." end
        if s.phase=="gathering" and time-s.touched>300000 then reason="Ensemble expired." end
        if reason then cancel(s,reason)
        elseif s.start and time>=s.start and time<(s.finish-1000) then
            -- Broadcast positions sparingly; every listener renders all parts on one clock.
            if time>=(s.positionAt or 0)then
                s.positionAt=time+500;local positions={}
                local tick=(time-s.start)*s.bpm*96/60000
                local radii={26,20,28,25,20,16,32,28,20,24,18,28,8,30,26,30}
                for i,m in ipairs(s.members)do
                    positions[i]={x=m.player:getX(),y=m.player:getY(),z=m.player:getZ(),owner=m.player:getOnlineID()}
                    s.parts[i].x=m.player:getX();s.parts[i].y=m.player:getY();s.parts[i].z=m.player:getZ()
                    if m.noise then
                        local velocity=0
                        for _,n in ipairs(m.notes)do if n.t<=tick and n.t+n.d>=math.max(0,tick-s.bpm*96/120) then velocity=math.max(velocity,n.v)end end
                        if velocity>0 then local r=math.max(4,math.floor(radii[m.profile+1]*(.35+.65*velocity/127)));addSound(m.player,math.floor(m.player:getX()),math.floor(m.player:getY()),math.floor(m.player:getZ()),r,r)end
                    end
                end
                local players=getOnlinePlayers()
                for i=0,players:size()-1 do local p=players:get(i)
                    if near(p,s.host,60)then local found=false;for _,listener in ipairs(s.listeners)do if listener==p then found=true;break end end
                        if not found then inviteListener(s,p)end
                    end
                end
                for _,listener in ipairs(s.listeners)do reply(listener,"positions",{id=s.id,positions=positions})end
            end
        end
    end
end
Events.OnClientCommand.Add(N.command)
Events.OnTick.Add(N.tick)
-- Shared authoritative checks for live playing; never trust a client's instrument claim.
N.validInstrument=instrument
N.inEnsemble=function(player)return sessionFor(player)~=nil end
