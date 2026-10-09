-- Gesture timing is visual only. MIDI reaches FluidSynth before this game-thread update.
DeadAirMotion={}
local M=DeadAirMotion
function M.new(instrument,state,now)
    return {instrument=instrument,lastAttack=state.attack,reset=state.reset,
        lastGroup=-1000000,untilTime=0,started=now,duration=250,speed=0,phase=instrument.readyPhase or -1,velocity=0,lastUpdate=now,cycle=0}
end
function M.panic(m,state)
    m.lastAttack=state.attack;m.reset=state.reset;m.untilTime=0
    m.lastGroup=-1000000;m.speed=0;m.phase=m.instrument.readyPhase or (m.instrument.gesture=="strike" and 0 or -1)
end
function M.update(m,state,now)
    local instrument=m.instrument
    if m.reset~=state.reset then
        -- Clear a previous gesture, but preserve a new note received after the reset.
        M.panic(m,state);m.lastAttack=state.resetAttack
    end
    if state.attack~=m.lastAttack then
        m.lastAttack=state.attack
        -- MIDI chords often arrive over several frames. Treat them as one gesture.
        if now-m.lastGroup>=55 then
            m.lastGroup=now;m.started=now;m.velocity=state.velocity
            m.duration=instrument.gesture=="strike" and (320-state.velocity/127*80) or (instrument.gesture=="keys" and 180 or 260)
        else m.velocity=math.max(m.velocity,state.velocity) end
        m.untilTime=now+m.duration
    end
    if instrument.gesture=="strike" then
        local elapsed=now-m.started
        local striking=m.lastGroup>-1000000 and elapsed<m.duration
        m.speed=striking and 1 or 0
        -- Move out and back to the same ready pose; no frozen mid-strike limb.
        local progress=striking and math.max(0,elapsed/m.duration) or 0
        m.phase=(progress<0.5 and progress*2 or (1-progress)*2)*instrument.strikeEnd
        return m.speed,m.phase
    end
    if instrument.sustain and state.held>0 then m.untilTime=math.max(m.untilTime,now+70) end
    local envelope=math.max(0,math.min(1,(m.untilTime+80-now)/80))
    if m.lastGroup==-1000000 then envelope=0 end
    m.speed=envelope*(0.65+m.velocity/127*0.75)*instrument.speed
    m.phase=-1
    if instrument.phaseWindow then
        local dt=math.max(0,math.min(100,now-m.lastUpdate));m.lastUpdate=now
        m.cycle=m.cycle+dt/1000*m.speed
        local a,b=instrument.phaseWindow[1],instrument.phaseWindow[2]
        -- The middle of the vanilla emote is the actual playing pose. Never revisit raise/lower.
        m.phase=a+(b-a)*(.5+.5*math.sin(m.cycle*2.2))
        if m.lastGroup==-1000000 then m.phase=instrument.readyPhase end
    end
    return m.speed,m.phase
end
