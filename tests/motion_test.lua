-- Pure gesture timing plus the real timed-action integration, with native UI stand-ins.
local function state(attack,held,velocity,reset,baseline)
    return {attack=attack,held=held or 0,velocity=velocity or 100,reset=reset or 0,resetAttack=baseline or 0}
end
local definitions={}
for _,def in pairs(DeadAirInstruments.held)do definitions[#definitions+1]=def end
for _,def in pairs(DeadAirInstruments.piano)do definitions[#definitions+1]=def end
for _,def in pairs(DeadAirInstruments.drums)do definitions[#definitions+1]=def end
assert(#definitions==21)
for _,def in ipairs(definitions) do if not def.drumMode then
    assert(def.clip and def.action and def.gesture,'Every supported instrument has a gesture')
    local m=DeadAirMotion.new(def,state(0),10000)
    assert(DeadAirMotion.update(m,state(0),10000)==0,def[2]..' moved before a note')
    assert(DeadAirMotion.update(m,state(1,1),10010)>0,def[2]..' did not respond')
    local began=m.started
    DeadAirMotion.update(m,state(4,4),10030)
    assert(m.started==began,def[2]..' restarted on a chord')
    local speed,phase=DeadAirMotion.update(m,state(4,4),10075)
    assert(speed>0)
    if def.gesture=='strike' then assert(phase>0 and phase<=def.strikeEnd) end
    speed,phase=DeadAirMotion.update(m,state(4,4),11000)
    if def.sustain then assert(speed>0,def[2]..' stopped while held')
    else assert(speed==0,def[2]..' kept repeating a held key') end
    -- Release with pedal/samples still ringing: the motion input is physical keys only.
    speed=DeadAirMotion.update(m,state(4,0),11200);assert(speed==0,def[2]..' ignored key release')
    if def.gesture=='strike' then assert(m.phase==0,'Strike did not return to ready position') end
    assert(DeadAirMotion.update(m,state(5,1),11220)>0,'Next note did not retrigger')
    DeadAirMotion.panic(m,state(5));assert(m.speed==0)
    assert(DeadAirMotion.update(m,state(5),11300)==0,'Panic revived an old attack')
    -- A reset between updates must discard pre-reset attacks, but keep post-reset ones.
    assert(DeadAirMotion.update(m,state(7,0,100,1,7),11400)==0,'Reconfiguration revived stale attacks')
    assert(DeadAirMotion.update(m,state(9,1,100,2,8),11500)>0,'First post-reset note was swallowed')
end end
local violin=DeadAirInstruments.held['Base.Violin']
local soft=DeadAirMotion.new(violin,state(0),0)
local hard=DeadAirMotion.new(violin,state(0),0)
assert(DeadAirMotion.update(hard,state(1,1,127),10)>DeadAirMotion.update(soft,state(1,1,20),10),'Velocity does not affect bow movement')
-- Exercise every actual held-item action, not just the pure timing helper.
for kind,def in pairs(DeadAirInstruments.held) do
    DeadAir.cleanup();queue.queue={};item.kind=kind;player.held=item;connected=true
    held=0;DeadAir.guitarEnabled=true;DeadAir.startPerformance()
    local action=DeadAir.performanceAction;assert(action and action.animated)
    action:update();assert(drivenSpeed==0)
    attackSerial=attackSerial+1;held=1;time=time+100;action:update()
    time=time+70;action:update()
    if def.drumMode then
        assert(action.liveTracks==5 and drivenTracks.DeadAirDrumL.phase>0,kind..' did not drive independent percussion layers')
    else assert(action.liveTracks==1 and drivenClip==def.clip and drivenSpeed>0,kind..' did not reach live-track bridge')end
    DeadAir.panic();assert(drivenSpeed==0)
    DeadAir.stop();assert(not performing and not DeadAir.performanceAction and player.vars[action.speedVariable]==nil)
end
DeadAir.cleanup()
-- Keep mouth instruments inside the measured playing segment through holds and rests.
for _,kind in ipairs({'Base.Harmonica','Base.Whistle','Base.Whistle_Bone'})do
    local m=DeadAirMotion.new(DeadAirInstruments.held[kind],state(0),0)
    for t=0,10000,20 do
        local count=math.floor(t/600)+1;local pressed=t%600<200 and 1 or 0
        local speed,p=DeadAirMotion.update(m,state(count,pressed),t)
        assert(p>=.28 and p<=.68,kind..' entered the raise/lower segment')
    end
    DeadAirMotion.panic(m,state(20));assert(m.phase==.45)
end
local function drumState(counts,reset)
    local s=state(0,0,100,reset);s.drums={}
    for k,v in pairs(counts)do s.drums[k]={attack=v,velocity=100};s.attack=s.attack+v end
    return s
end
local kit=DeadAirInstruments.kit
local m=DeadAirDrumMotion.new(kit,drumState({}),0)
local all=drumState({kick=1,snare=1,hat=1,hatPedal=1})
DeadAirDrumMotion.update(m,all,10)
local p=DeadAirDrumMotion.update(m,all,80)
assert(p.left>0 and p.left<1/8 and p.right>1/8 and p.right<2/8 and p.footR>0 and p.footL>0,'Simultaneous kick/snare/hat/pedal lost a limb')
p=DeadAirDrumMotion.update(m,all,300);for _,v in pairs(p)do assert(v==0,'Held drum repeated or froze at contact')end
for _,case in ipairs({{'floor','right',2},{'rackLow','right',3},{'rackHigh','left',4},{'cymbal','right',5}})do
    local fresh=drumState({});local dm=DeadAirDrumMotion.new(kit,fresh,0)
    local hit=drumState({[case[1]]=1});DeadAirDrumMotion.update(dm,hit,10)
    local phases=DeadAirDrumMotion.update(dm,hit,80)
    assert(phases[case[2]]>case[3]/8 and phases[case[2]]<(case[3]+1)/8,'Wrong surface: '..case[1])
    DeadAirDrumMotion.panic(dm,hit);phases=DeadAirDrumMotion.update(dm,hit,90)
    for _,v in pairs(phases)do assert(v==0,'Panic revived an old drum hit')end
end
DeadAirDrumMotion.update(m,drumState({},1),400)
p=DeadAirDrumMotion.update(m,drumState({},1),450);for _,v in pairs(p)do assert(v==0)end
DeadAirDrumMotion.update(m,drumState({kick=1},2),500)
p=DeadAirDrumMotion.update(m,drumState({kick=1},2),550);assert(p.footR>0 and p.left==0 and p.right==0,'First post-reset kick swallowed or stale hands replayed')
local first=DeadAirDrumMotion.new(kit,all,0,true);DeadAirDrumMotion.update(first,all,0)
p=DeadAirDrumMotion.update(first,all,70);assert(p.left>0 and p.right>0 and p.footR>0,'Auto-start swallowed chord surfaces')
print('PASS: mouth poses never lower; independent simultaneous pedals/hands, exact tom/cymbal slots, no held-key repeat, panic/reset and first-note handoff')
print('PASS: all 21 instrument/piano-side definitions respond; chord grouping, velocity, key release, pedal-tail separation, percussion return, panic, reset and action-to-native routing')
