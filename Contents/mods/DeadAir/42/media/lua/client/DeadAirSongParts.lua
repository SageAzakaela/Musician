require "DeadAirComposition"
DeadAirSongParts={}
local P,C,S=DeadAirSongParts,DeadAirComposition,DeadAirScore
function P:refreshPartPicker()
    if not self.partPicker then return end
    self.partPicker:clear()
    for i,part in ipairs(self.song.parts)do self.partPicker:addOption(i..". "..part.partName.." - "..S.names[part.profile+1])end
    self.partPicker.selected=self.activePart
end
function P:settings()
    local bpm,bars=tonumber(self.bpmEntry:getText()),tonumber(self.barsEntry:getText())
    if not S.integer(bpm,30,300)or not S.integer(bars,1,S.MAX_BARS)then self.message="Tempo must be 30-300 BPM.";return false end
    bars=math.max(bars,self.score.bars);for _,n in ipairs(self.notes)do bars=math.max(bars,math.ceil((n.t+n.d)/384))end
    local song=S.copy(self.song);song.title=S.text(self.titleEntry:getText(),64);song.bpm=bpm;song.bars=bars
    local part=song.parts[self.activePart];part.partName=S.text(self.partEntry:getText(),48);part.profile=self.instrument.selected-1;part.notes=S.encode(self.notes);C.cover(part,self.notes)
    for i,p in ipairs(song.parts)do
        local notes=S.decode(p.notes,self.song.bars*384)
        for _,n in ipairs(notes or {})do if n.t+n.d>bars*384 then self.message="Part "..i.." extends past that length. Shorten its notes first.";return false end end
    end
    local valid,err=C.validate(song);if not valid then self.message=err;return false end
    part=valid.parts[self.activePart]
    local previous=self.song.parts[self.activePart]
    if valid.title~=self.song.title or bpm~=self.song.bpm or bars~=self.song.bars or not S.equal(part.notes,previous.notes) or part.partName~=previous.partName or part.profile~=previous.profile then self.dirty=true end
    self.song=valid;self.score=C.score(valid,self.activePart);self.barsEntry:setText(tostring(valid.bars));self.arrCache=nil;self:refreshPartPicker();return true
end
function P:rememberPartView()
    self.partViews[self.score.part]={undo=self.undoStack,redo=self.redoStack,firstTick=self.firstTick,pitchScroll=self.pitchScroll,viewTicks=self.viewTicks}
end
function P:loadPart(index)
    self.activePart=index;self.song.active=self.song.parts[index].part;self.score=C.score(self.song,index)
    self.activeClip=1;self.arrCache=nil;self.otherNoteCount=nil
    self.notes=S.decode(self.score.notes,self.score.bars*384)or {};self.selected={};self.drag=nil;self:setCapture(false)
    local view=self.partViews[self.score.part]
    self.undoStack=view and view.undo or {};self.redoStack=view and view.redo or {}
    self.firstTick=view and view.firstTick or 0;self.pitchScroll=view and view.pitchScroll or 44;self.viewTicks=view and view.viewTicks or math.min(1536,self.score.bars*384)
    self.titleEntry:setText(self.score.title);self.partEntry:setText(self.score.partName);self.bpmEntry:setText(tostring(self.score.bpm));self.barsEntry:setText(tostring(self.score.bars));self.instrument.selected=self.score.profile+1
    self:refreshPartPicker();self:rebuildPitches();self:layout();self:clampView();self:updateMonitor()
    if index<=(self.trackScroll or 0)then self.trackScroll=index-1
    elseif index>(self.trackScroll or 0)+math.max(1,self.trackRows or 1)then self.trackScroll=index-math.max(1,self.trackRows or 1)end
    local clip=self.song.parts[index].clips[1];if self.phraseEntry then self.phraseEntry:setText(clip and clip.name or "Clip 1")end
end
function P:switchPart(index)
    if not S.integer(index,1,#self.song.parts)then return end
    if not self:editable()or not self:settings()then self.partPicker.selected=self.activePart;return end
    if index==self.activePart then return end
    self:stopAudition();self:stopMonitor();self:rememberPartView();self:loadPart(index);self.dirty=true
    self.message="Editing "..self.score.partName..". Other parts keep their notes."
end
function P:addPart()
    if not self:editable()or not self:settings()then return end
    if #self.song.parts>=S.MAX_PARTS then self.message="This song already has eight parts.";return end
    self:stopAudition();self:stopMonitor();self:rememberPartView()
    self.partSerial=self.partSerial+1
    local id="draft-"..tostring(getTimestampMs()).."-"..self.partSerial
    self.song.parts[#self.song.parts+1]={part=id,partName="Part "..(#self.song.parts+1),profile=0,notes="",clips={{name="Clip 1",start=0,length=math.min(4,self.song.bars)*384}}}
    self:loadPart(#self.song.parts);self.dirty=true
    self.message="Added "..self.score.partName..". Choose its instrument above; Save song keeps every part on this paper."
end
function P:acceptSaved(song)
    -- Saving assigns permanent IDs to new parts; keep their editing histories.
    for i,part in ipairs(song.parts)do
        local old=self.song.parts[i]
        if old and old.part~=part.part then self.partViews[part.part]=self.partViews[old.part];self.partViews[old.part]=nil end
    end
    self.song=C.copy(song);self.activePart=C.index(self.song);self.score=C.score(self.song,self.activePart)
    self.dirty=false;self.saving=false;self:refreshPartPicker()
end
function P:save()
    if not self:editable()or not self:settings()then return end
    self.saving=true;self.saveAt=getTimestampMs();self.message="Saving all "..#self.song.parts.." parts..."
    DeadAir.Songs.write({mode="saveSong",item=self.item:getID(),revision=self.song.revision,composition=C.copy(self.song)})
end
function P:paperAction(mode)
    if mode=="part"then self:addPart();return end
    if not self:editable()or not self:settings()then return end
    if self.dirty or not C.read(self.item)then self.message="Save song before copying it to another sheet.";return end
    local blank=S.blankIn(getSpecificPlayer(0):getInventory())
    if not blank then self.message="Copying needs another blank sheet. Adding parts inside this song does not.";return end
    DeadAir.Songs.write({mode=mode,item=self.item:getID(),blank=blank:getID(),part=self.score.part})
end
function P:previewParts(record)
    local result={};self.previewMap={};self.previewNames=""
    -- Keep every track loaded so M/S can change without interrupting the audio clock.
    for i,part in ipairs(self.song.parts)do
        local native=S.native(C.score(self.song,i),self.playFrom or 0)
        if record and i==self.activePart then native.notes={}end
        result[#result+1]=native;self.previewMap[i]=#result-1
        self.previewNames=self.previewNames..(i>1 and ", "or "")..part.partName
    end
    return result
end
function P:stopMonitor()
    if self.monitoring and DeadAir.api()then DeadAirMidi.perform(false)end
    self.monitoring=nil;self.monitorProfile=nil
end
function P:updateMonitor()
    if not self.monitor or not DeadAir.api() or not getSpecificPlayer(0) or getSpecificPlayer(0):isDead() or not DeadAirMidi.connected() then self:stopMonitor();return end
    if DeadAir.Songs and (DeadAir.Songs.net or DeadAir.Songs.lobby or DeadAir.Songs.solo)then self:stopMonitor();return end
    local profile=self.instrument.selected-1;local channel=DeadAir.value("channel")-1;local volume=DeadAir.value("volume")/100
    if self.monitorProfile~=profile or self.monitorChannel~=channel or self.monitorVolume~=volume then
        DeadAirMidi.configure(profile,0,channel,volume);self.monitorProfile=profile;self.monitorChannel=channel;self.monitorVolume=volume
    end
    if not DeadAirMidi.performing()then DeadAirMidi.perform(true)end
    self.monitoring=true;DeadAirMidi.heartbeat()
end
function P:close()
    if self.libraryPanel then self.libraryPanel:cancelDrag();self.libraryPanel:setVisible(false)end
    self:stop();self:stopMonitor()
    -- Keep all parts even if a text field currently has invalid settings.
    if not self:settings()then self.song.parts[self.activePart].notes=S.encode(self.notes)end
    DeadAir.Songs.drafts[self.item:getID()]=self.dirty and C.copy(self.song)or nil
    self:setVisible(false);self:removeFromUIManager();DeadAir.editorActive=nil;DeadAir.Songs.editor=nil;DeadAir.autoItem=nil
end
