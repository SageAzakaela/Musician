require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISComboBox"
require "ISUI/ISTextEntryBox"
require "DeadAirScore"
require "DeadAirRoll"
require "DeadAirRollView"
require "DeadAirSongParts"
require "DeadAirArrangement"
require "DeadAirLibrary"
require "DeadAirClipEditing"
require "DeadAirWorkflow"
require "DeadAirWorkspace"
require "MusicianSoundfonts"
DeadAirSongEditor=ISPanel:derive("DeadAirSongEditor")
local E,S=DeadAirSongEditor,DeadAirScore
function E:new(item,score)
    local o=ISPanel.new(self,8,8,getCore():getScreenWidth()-16,getCore():getScreenHeight()-16)
    o.item=item;o.song=(score.version==2 or score.version==3) and DeadAirComposition.copy(score)or DeadAirComposition.fromScore(score)
    o.activePart=DeadAirComposition.index(o.song);score=DeadAirComposition.score(o.song,o.activePart);o.score=score;o.notes=S.decode(score.notes,score.bars*384)or {}
    o.partViews={};o.partSerial=0;o.monitor=true;o.arrFirst=0;o.arrTicks=math.max(3072,score.bars*384);o.trackScroll=0;o.activeClip=1;o.playFrom=0
    o.undoStack={};o.redoStack={};o.selected={};o.mode="draw";o.cursorTick=0
    o.backgroundColor={r=.075,g=.08,b=.07,a=.99};o.borderColor={r=.31,g=.32,b=.28,a=1};o.moveWithMouse=false
    o.firstTick=0;o.pitchScroll=44;o.viewTicks=math.min(1536,score.bars*384)
    o.maximized=true;o.details=false;o.fold=false;o.showVelocity=false;o.follow=true;o.hear=true
    o.scaleEnabled=false;o.scaleOnly=true
    o.metronome=true;o.triplet=false;o.denominators={1,2,4,8,16,32}
    o.message="Add parts and choose their instruments here. No equipped instrument is needed. Save song keeps all parts."
    return o
end
function E:initialise()ISPanel.initialise(self);self:buildControls()end
function E:editable()
    if self.transport or self.pending or self.saving then self.message="Stop playback or recording before editing.";return false end
    return true
end
function E:preview(record)
    if not self:editable() or not self:settings() then return end
    if not DeadAir.api() or not DeadAirMidi.scoreLoad then self.message="Restart and approve the updated DeadAir.jar.";return end
    if record and not DeadAirMidi.connected() then self.message="Connect your MIDI keyboard in Mod Options first.";return end
    if DeadAir.Songs.net or DeadAir.Songs.lobby then self.message="Leave the ensemble before previewing or recording.";return end
    if record and not DeadAirMidi.recordStartOpen then self.message="Restart and approve DeadAir.jar 0.9.0 to record longer takes.";return end
    if record and self:noteRoom()<1 then self.message="Song note capacity reached. Start a new sheet before recording.";return end
    self.playFrom=math.max(0,math.min(self.playFrom or 0,self:ticks()-96))
    local parts,err=self:previewParts(record);if not parts then self.message=err;return end
    self.pendingParts=parts
    self:stopAudition();DeadAir.stop();self.pending=record and "record" or "preview";self.pendingAt=getTimestampMs()
    DeadAirMidi.openAudio();self.message="Preparing audio..."
end
function E:startPending()
    if not DeadAirMidi.audioReady() then
        if getTimestampMs()-self.pendingAt>15000 then self.pending=nil;self.message=DeadAirMidi.status()end;return
    end
    local record=self.pending=="record";local library=self.pending=="library";self.pending=nil
    local parts=self.pendingParts;self.pendingParts=nil
    local err=DeadAirMidi.scoreLoad(parts,self.score.bpm,library and self.pendingClip.length or record and 0 or self.score.bars*384-self.playFrom,not library and self.metronome)
    if err~="" then self.message=err;return end
    -- Prepare the undo state before starting either transport or MIDI capture.
    if record then
        self:checkpoint();self.recordBase=S.copy(self.notes);self.recordOldBars=self.score.bars
        self.recordOrigin=self.playFrom or 0;self.recordSeen=0;self.recordDrawAt=0
        self.recordPitchLow=nil;self.recordPitchHigh=nil
        local state=DeadAirMidi.motionState and DeadAirMidi.motionState();self.recordAttack=state and state.attack
    end
    self.transport=library and "library"or record and "record" or "preview"
    local countIn=record and 4*60000/self.score.bpm or 0
    self.started=DeadAirMidi.clock()+countIn
    DeadAir.configure()
    DeadAirMidi.scoreStart(countIn);if library then DeadAirMidi.scoreGain(0,1)else self:applyTrackGains()end
    if record then
        self:updateMonitor();self:rebuildPitches()
        DeadAirMidi.recordStartOpen(self.score.bpm,DeadAir.value("channel")-1,4,self:noteRoom())
    end
    if library then self.message="Private clip preview: "..self.pendingClip.name..". "..(self.pendingClip.warning or "");self.pendingClip=nil;return end
    self.message=record and "One-bar count-in, then recording this part"..(#parts>1 and " with the other parts as backing" or "")..". Recording continues until Stop; the timeline grows with your take."
        or "Private preview: "..#parts.." part"..(#parts==1 and "" or "s")..". "..(self.previewNames or self.score.partName)
end
function E:stop()
    self.pending=nil;self.pendingParts=nil;self.pendingClip=nil;self:stopAudition()
    if DeadAir.api() then
        if self.transport=="record" then
            local take=DeadAirMidi.recordStop();local origin=self.recordOrigin or self.playFrom or 0
            -- Incremental display is provisional. Stop returns the complete take,
            -- including held notes; combine it with the original only once.
            self.notes=self.recordBase or self.notes;local added=0;local finish=math.max(origin+1,self:transportTick())
            local low,high
            for _,n in ipairs(take)do local copy=S.copy(n);copy.t=copy.t+origin;self.notes[#self.notes+1]=copy;added=added+1
                finish=math.max(finish,copy.t+copy.d);low=math.min(low or 127,copy.n);high=math.max(high or 0,copy.n)
            end
            local p=self.song.parts[self.activePart];local chosen
            if added>0 then
                local ending=math.ceil(finish/384)*384
                -- Overdubs in a generated repetition must become real notes. Keep
                -- the existing materialized repetitions and unroll touched loops.
                for i,c in ipairs(p.clips)do if origin<c.start+c.length and ending>c.start then
                    c.loopLength=nil;c.loopStart=nil
                    if origin>=c.start and origin<c.start+c.length then chosen=c end
                end end
                if chosen then chosen.length=math.max(chosen.length,ending-chosen.start)
                elseif #p.clips<128 then chosen={name="Take "..(#p.clips+1),start=origin,length=ending-origin};p.clips[#p.clips+1]=chosen
                else
                    -- Keep a full track saveable: extend its nearest clip instead
                    -- of introducing an invalid 129th clip after capture.
                    chosen=p.clips[1];for _,c in ipairs(p.clips)do if c.start<=origin then chosen=c end end
                    local oldEnd=chosen.start+chosen.length;chosen.start=math.min(chosen.start,origin)
                    chosen.length=math.max(oldEnd,ending)-chosen.start;chosen.loopLength=nil;chosen.loopStart=nil
                end
                DeadAirComposition.cover(p,self.notes)
                for i,c in ipairs(p.clips)do if origin>=c.start and origin<c.start+c.length then self.activeClip=i;break end end
            end
            local ending=added>0 and finish or 0
            for _,n in ipairs(self.notes)do ending=math.max(ending,n.t+n.d)end
            self.score.bars=math.max(self.recordOldBars or 1,math.ceil(ending/384));self.song.bars=self.score.bars;self:extendTo(ending)
            p.notes=S.encode(self.notes);self.arrCache=nil;self.recordBase=nil;self.recordSeen=nil;self.recordOrigin=nil
            self.recordStoppedPitch=low and {low,high}or nil
            self.message="Recorded "..added.." notes. Save to paper to keep the song."..(DeadAirMidi.recordFull()and " Note capacity reached; captured notes were kept."or "")
        end
        DeadAirMidi.scoreStop();DeadAirMidi.perform(false)
    end
    self.transport=nil;self:rebuildPitches()
    if self.recordStoppedPitch then
        local range=self.recordStoppedPitch;self.recordStoppedPitch=nil;self:focusClip(self.activeClip)
        self:centerPitchRange(range[1],range[2]);self:refreshClipTiming(true)
    end
end
function E:update()
    self:updateLibrary()
    if self.saving and getTimestampMs()-self.saveAt>10000 then self.saving=false;self.message="Save response timed out. Reopen the paper to check before saving again."end
    self:updateMonitor();self:updateAudition()
    if self.pending then self:startPending()end
    if self.transport then
        if not getSpecificPlayer(0) or getSpecificPlayer(0):isDead()then self:stop();return end
        DeadAirMidi.scoreHeartbeat()
        if self.transport=="library"then if not DeadAirMidi.scoreActive()then self:stop()end;return end
        local tick=self:transportTick()
        if self.transport=="record"then
            self:extendTo(tick+384)
            if getTimestampMs()-(self.recordDrawAt or 0)>100 then
                self.recordDrawAt=getTimestampMs()
                for _,n in ipairs(DeadAirMidi.recordNotes(self.recordSeen or 0))do local copy=S.copy(n);copy.t=copy.t+(self.recordOrigin or self.playFrom or 0);self.notes[#self.notes+1]=copy;self.recordSeen=self.recordSeen+1
                    self:recordPitch(copy.n)
                end
                local state=DeadAirMidi.motionState and DeadAirMidi.motionState()
                if state and state.attack~=self.recordAttack and DeadAirMidi.clock()>=self.started then
                    self.recordAttack=state.attack;if state.velocity and state.velocity>0 then self:recordPitch(state.note)end
                end
                self.arrCache=nil
            end
        end
        if self.follow and tick>=self.arrFirst+self.arrTicks then self.arrFirst=math.floor(tick/self.arrTicks)*self.arrTicks end
        if self.follow and not self.drag and (tick<self.firstTick or tick>=self.firstTick+self.viewTicks)then
            self.firstTick=math.floor(math.max(0,tick)/self.viewTicks)*self.viewTicks;self:clampView()
        end
        if self.transport=="record" then DeadAirMidi.heartbeat()end
        if not DeadAirMidi.scoreActive() or (self.transport=="record" and (DeadAirMidi.recordFull()or not DeadAirMidi.connected()or tick>=S.MAX_BARS*384-384)) then self:stop()end
    end
end

function E:stopAudition()
    self.auditionPending=nil
    if self.auditioning and DeadAir.api()then DeadAirMidi.scoreStop()end
    self.auditioning=nil
end
function E:audition(pitch,velocity)
    if not self.hear or self.transport or self.pending or self.saving or not DeadAir.api() or not DeadAirMidi.scoreLoad then return end
    if DeadAir.Songs and (DeadAir.Songs.net or DeadAir.Songs.lobby or DeadAir.Songs.solo)then return end
    self.auditionPending={n=pitch,v=math.floor(velocity),at=getTimestampMs()}
    if not DeadAirMidi.audioReady()then
        if not self.audioRequested or getTimestampMs()-self.audioRequested>15000 then self.audioRequested=getTimestampMs();DeadAirMidi.openAudio()end
    end
    self:updateAudition()
end
function E:updateAudition()
    if not self.hear then self:stopAudition();return end
    if self.auditioning then
        DeadAirMidi.scoreHeartbeat()
        if not DeadAirMidi.scoreActive() or getTimestampMs()>self.auditionUntil then
            DeadAirMidi.scoreStop();self.auditioning=nil
        end
    end
    local n=self.auditionPending;if not n then return end
    if getTimestampMs()-n.at>1500 then self.auditionPending=nil;return end
    if not DeadAirMidi.audioReady() or (self.auditionAt and getTimestampMs()-self.auditionAt<45)then return end
    self.auditionPending=nil;self.auditionAt=getTimestampMs()
    local err=DeadAirMidi.scoreLoad({{profile=self.instrument.selected-1,notes={{n=n.n,t=0,d=48,v=n.v}}}},120,384,false)
    if err~="" then self.message=err;self.auditioning=nil;return end
    DeadAirMidi.scoreStart(0);self.auditioning=true;self.auditionUntil=getTimestampMs()+350
end
for name,fn in pairs(DeadAirRoll)do if type(fn)=="function" then E[name]=fn end end
for name,fn in pairs(DeadAirRollView)do if type(fn)=="function" then E[name]=fn end end

for name,fn in pairs(DeadAirSongParts)do if type(fn)=="function"then E[name]=fn end end
for name,fn in pairs(DeadAirArrangement)do if type(fn)=="function"then E[name]=fn end end
for name,fn in pairs(DeadAirLibrary)do if type(fn)=="function"then E[name]=fn end end

for name,fn in pairs(DeadAirClipEditing)do if type(fn)=="function"then E[name]=fn end end
for name,fn in pairs(DeadAirWorkflow)do if type(fn)=="function"then E[name]=fn end end
for name,fn in pairs(DeadAirWorkspace)do if type(fn)=="function"then E[name]=fn end end
