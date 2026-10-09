-- Independent visual limbs. Audio has already sounded by the time these counters are read.
DeadAirDrumMotion={}
local D=DeadAirDrumMotion
local groups={"kick","snare","hat","hatPedal","floor","rackLow","rackHigh","cymbal"}
local targets={snare=0,hat=1,floor=2,rackLow=3,rackHigh=4,cymbal=5,practice=6,single=7}
local routes={kick="footR",snare="left",hat="right",hatPedal="footL",floor="right",rackLow="right",rackHigh="left",cymbal="right"}
local function phase(limb,now)
    if not limb or now-limb.started>=limb.duration then return 0 end
    local progress=math.max(0,(now-limb.started)/limb.duration)
    return limb.pedal and progress or (limb.slot+progress)/8
end
function D.new(instrument,state,now,includeFirst)
    local m={instrument=instrument,seen={},limbs={},reset=state.reset,attack=state.attack}
    for _,key in ipairs(groups)do local v=state.drums and state.drums[key];m.seen[key]=includeFirst and 0 or (v and v.attack or 0)end
    if includeFirst then m.attack=math.max(0,m.attack-1)end
    return m
end
function D.panic(m,state)
    m.limbs={};m.reset=state.reset;m.attack=state.attack
    for _,key in ipairs(groups)do local v=state.drums and state.drums[key];m.seen[key]=v and v.attack or 0 end
end
local function strike(m,limb,key,velocity,now)
    local previous=m.limbs[limb]
    -- Closely spaced samples of the same surface share a stroke; distinct limbs never do.
    if previous and previous.key==key and now-previous.started<32 then return end
    m.limbs[limb]={key=key,slot=targets[key] or 6,pedal=limb=="footR" or limb=="footL",started=now,duration=200-(velocity or 100)/127*55}
end
function D.update(m,state,now)
    if m.reset~=state.reset then
        m.limbs={};m.reset=state.reset;m.seen={};m.attack=state.resetAttack or state.attack
    end
    local instrument=m.instrument
    if instrument.drumMode=="kit" then
        -- Deterministic priorities on one hand: a hand cannot hit three surfaces at once.
        -- Kick, pedal-hat, snare and stick-hat remain four separate simultaneous gestures.
        for _,key in ipairs(groups)do
            local v=state.drums and state.drums[key]
            if v and v.attack~=(m.seen[key] or 0) then
                if v.attack>(m.seen[key] or 0)then strike(m,routes[key],key,v.velocity,now)end
                m.seen[key]=v.attack
            end
        end
    elseif state.attack~=m.attack then
        local key=instrument.drumMode
        if key=="practice"then
            local limb=(m.practiceSide=="left") and "right" or "left";m.practiceSide=limb;strike(m,limb,"practice",state.velocity,now)
        else strike(m,routes[key],key=="kick" and key or "single",state.velocity,now)end
    end
    m.attack=state.attack
    local result={};for _,limb in ipairs({"left","right","footR","footL"})do result[limb]=phase(m.limbs[limb],now)end
    m.phases=result;return result
end
function D.drive(actor,instrument,m,state,now,stop)
    if stop then D.panic(m,state)else D.update(m,state,now)end
    local p=stop and {} or m.phases;local count=0
    for _,track in ipairs(instrument.tracks)do count=count+DeadAirMidi.animate(actor,instrument.action,track.clip,0,p[track.limb] or 0)end
    return count
end
