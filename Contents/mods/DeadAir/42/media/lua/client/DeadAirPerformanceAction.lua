require "TimedActions/ISBaseTimedAction"
require "TimedActions/ISTimedActionQueue"
require "DeadAirMotion"
require "DeadAirDrumMotion"

DeadAirPerformanceAction=ISBaseTimedAction:derive("DeadAirPerformanceAction")
function DeadAirPerformanceAction:new(character,source,instrument,worldTarget,animated)
    local o=ISBaseTimedAction.new(self,character)
    o.item=source;o.instrument=instrument;o.worldTarget=worldTarget;o.animated=animated
    o.maxTime=-1;o.useProgressBar=false
    o.stopOnWalk=true;o.stopOnRun=true;o.stopOnAim=true
    o.speedVariable=instrument.action=="DeadAirGuitar" and "DeadAirGuitarSpeed" or "DeadAirPlayingSpeed"
    return o
end
function DeadAirPerformanceAction:isValid()
    if self.stopping or not DeadAir.allowed(self.character) or not (DeadAirMidi.connected() or self.scorePart~=nil) then return false end
    if self.worldTarget then return DeadAirWorld.atInstrument(self.character,self.worldTarget) end
    return self.character:getPrimaryHandItem()==self.item and self.item:getCondition()>0
end
function DeadAirPerformanceAction:waitToStart()
    if self.worldTarget then
        self.character:faceThisObject(self.item)
        return self.character:shouldBeTurning()
    end
    return false
end
function DeadAirPerformanceAction:start()
    if not self:isValid() then self:requestStop();return end
    if self.animated and not DeadAir.animationReady(self.instrument) then
        DeadAir.notice=DeadAir.animationStatus(self.instrument);self:requestStop();return
    end
    if self.animated and self.instrument.drumMode then
        if self.instrument.drumMode=="kick" then self:setOverrideHandModels(nil,nil)
        else self:setOverrideHandModels("DeadAir.DrumstickPerformance","DeadAir.DrumstickPerformance")end
    elseif self.worldTarget then self:setOverrideHandModels(nil,nil)
    elseif self.animated then
        if self.instrument.hand=="secondary" then self:setOverrideHandModels(nil,self.instrument.visualModel or self.item)
        elseif self.instrument.hand=="bow" then self:setOverrideHandModels("DeadAir.ViolinBow",self.instrument.visualModel or self.item)
        else self:setOverrideHandModels(self.instrument.visualModel or self.item,nil) end
    end
    if self.animated then
        self:setActionAnim(self.instrument.action)
        self:setAnimVariable(self.speedVariable,"0")
    end
    self.started=true;DeadAir.playingItem=self.item;DeadAir.approachAction=nil;DeadAir.notice=nil
    DeadAir.configure()
    DeadAirMidi.guitarMode(self.instrument[1]==1)
    if self.scorePart==nil and not DeadAirMidi.performing() then DeadAirMidi.perform(true) end
    if self.scorePart==nil then DeadAir.autoItem=self.item;DeadAir.autoAttack=DeadAirMidi.attackSerial() end
    if self.animated then
        local state=self.scorePart~=nil and DeadAirMidi.scoreState(self.scorePart) or DeadAirMidi.motionState()
        self.motion=DeadAirMotion.new(self.instrument,state,getTimestampMs())
        if self.instrument.drumMode then self.drumMotion=DeadAirDrumMotion.new(self.instrument,state,getTimestampMs(),self.fromNote or self.scorePart~=nil)end
        if self.fromNote or self.scorePart~=nil then self.motion.lastAttack=math.max(0,state.attack-1) end
    end
end
function DeadAirPerformanceAction:update()
    if self.stopping then return end
    if not self:isValid() or not (self.scorePart~=nil and DeadAirMidi.scoreActive() or self.scorePart==nil and DeadAirMidi.performing()) then self:requestStop();return end
    if self.worldTarget then self.character:faceThisObject(self.item) end
    if not self.animated then return end
    if self.drumMotion then
        local state=self.scorePart~=nil and DeadAirMidi.scoreState(self.scorePart) or DeadAirMidi.motionState()
        self.liveTracks=DeadAirDrumMotion.drive(self.character,self.instrument,self.drumMotion,state,getTimestampMs(),false);return
    end
    local speed,phase=DeadAirMotion.update(self.motion,self.scorePart~=nil and DeadAirMidi.scoreState(self.scorePart) or DeadAirMidi.motionState(),getTimestampMs())
    self:setAnimVariable(self.speedVariable,tostring(speed))
    self.liveTracks=DeadAirMidi.animate(self.character,self.instrument.action,self.instrument.clip,speed,phase)
end
function DeadAirPerformanceAction:panic()
    if self.drumMotion and self.action then DeadAirDrumMotion.drive(self.character,self.instrument,self.drumMotion,DeadAirMidi.motionState(),getTimestampMs(),true);return end
    if self.motion then DeadAirMotion.panic(self.motion,DeadAirMidi.motionState()) end
    if self.animated and self.action then
        self:setAnimVariable(self.speedVariable,"0")
        DeadAirMidi.animate(self.character,self.instrument.action,self.instrument.clip,0,self.instrument.readyPhase or (self.instrument.gesture=="strike" and 0 or -1))
    end
end
function DeadAirPerformanceAction:cleanup()
    if self.cleaned then return end
    self:panic()
    self.cleaned=true
    if self.started and self.animated then self.character:clearVariable(self.speedVariable) end
    if DeadAir.performanceAction==self then
        DeadAir.performanceAction=nil;DeadAir.playingItem=nil
        DeadAir.lastX=nil;DeadAir.lastY=nil
        DeadAirMidi.perform(false);DeadAirMidi.guitarMode(false)
    end
end
function DeadAirPerformanceAction:requestStop()
    if self.stopping then return end
    self.stopping=true;self:panic();DeadAirMidi.perform(false)
    if self.action then self:forceComplete()
    else ISTimedActionQueue.getTimedActionQueue(self.character):removeFromQueue(self);self:cleanup() end
end
function DeadAirPerformanceAction:stop() self:cleanup();ISBaseTimedAction.stop(self) end
function DeadAirPerformanceAction:perform() self:cleanup();ISBaseTimedAction.perform(self) end
function DeadAirPerformanceAction:forceCancel() self:cleanup() end
