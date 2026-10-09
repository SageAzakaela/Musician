require "DeadAirComposition"
-- Clip-focused editing and a chronological song-wide undo history.
DeadAirClipEditing={}
local Q,S,C,R,P,A=DeadAirClipEditing,DeadAirScore,DeadAirComposition,DeadAirRoll,DeadAirSongParts,DeadAirArrangement
local function clamp(n,a,b)return math.max(a,math.min(b,n))end
function Q:currentClip()local p=self.song.parts[self.activePart];return p and p.clips[self.activeClip or 1]end
function Q:clipBars(ticks)return (string.format("%.6f",ticks/384):gsub("0+$",""):gsub("%.$",""))end
function Q:refreshClipTiming(force)
    if not self.clipStartEntry then return end
    local c=self:currentClip();local p=self.song.parts[self.activePart]
    local signature=c and table.concat({p.part,self.activeClip,c.start,c.length,c.loopLength or 0},":")or "none"
    if force or signature~=self.clipTimingSignature then
        self.clipTimingSignature=signature
        self.clipStartEntry:setText(c and self:clipBars(c.start+384)or "")
        self.clipLengthEntry:setText(c and self:clipBars(c.length)or "")
        self.clipLoopEntry:setText(c and c.loopLength and self:clipBars(c.loopLength)or "")
    end
    local editable=c~=nil and not(self.transport or self.pending or self.saving)
    self.clipStartEntry:setEditable(editable);self.clipLengthEntry:setEditable(editable)
    self.clipLoopEntry:setEditable(editable and c.loopLength~=nil or false)
    self.clipApplyButton:setEnable(editable)
end
function Q:toggleClipTiming()
    self.clipTiming=not self.clipTiming;self:refreshClipTiming(true);self:layout()
end
function Q:applyClipTiming()
    if not self:editable()then return false end
    local c=self:currentClip();if not c then self.message="Select a clip first.";return false end
    local start,length,loop=tonumber(self.clipStartEntry:getText()),tonumber(self.clipLengthEntry:getText()),tonumber(self.clipLoopEntry:getText())
    local function valid(n,minimum,maximum)return n and n==n and n>=minimum and n<=maximum end
    if not valid(start,1,S.MAX_BARS+1)or not valid(length,0,S.MAX_BARS)or(c.loopLength and not valid(loop,0,S.MAX_BARS))then
        self.message="Use bar numbers: Start begins at 1; lengths must be positive. 8 = eight bars, 0.25 = one beat.";return false
    end
    start=math.floor((start-1)*384+.5);length=math.floor(length*384+.5);loop=c.loopLength and math.floor(loop*384+.5)or nil
    if not self:settings()then return false end
    c=self:currentClip();if c.start==start and c.length==length and c.loopLength==loop then self:refreshClipTiming(true);return true end
    local edited,err=C.retimeClip(self.song.parts[self.activePart],self.notes,self.activeClip,start,length,loop,self:loopCapacity())
    if not edited then self.message=err;return false end
    self:checkpoint();self.song.parts[self.activePart].clips=edited.clips;self.notes=edited.notes
    local chosen=edited.clips[self.activeClip];table.sort(edited.clips,function(a,b)return a.start<b.start end)
    for i,clip in ipairs(edited.clips)do if clip==chosen then self.activeClip=i;break end end
    self:extendTo(start+length);self.arrCache=nil;self:rebuildPitches();self:focusClip(self.activeClip);self:refreshClipTiming(true)
    self.message=loop and "Loop source is exactly "..self:clipBars(loop).." bars. Repeats rebuilt; Ctrl+Z restores the previous timing."or "Clip timing applied. Notes kept; Ctrl+Z restores the previous timing."
    return true
end
function Q:editBounds()
    local c=self:currentClip()
    if c and not self.editWholeTrack then return c.start,c.start+(c.loopLength or c.length)end
    return 0,self:ticks()
end
function Q:noteEditable(n)
    local lo,hi=self:editBounds();if n.t<lo or n.t>=hi then return false end
    for _,c in ipairs(self.song.parts[self.activePart].clips)do
        if c.loopLength and n.t>=c.start+c.loopLength and n.t<c.start+c.length then return false end
    end
    return true
end
function Q:partSnapshot(notes)
    local song=S.copy(self.song);local p=song.parts[self.activePart]
    p.notes=notes or S.encode(self.notes);p.profile=self.instrument.selected-1;p.partName=S.text(self.partEntry:getText(),48)or p.partName
    song.title=S.text(self.titleEntry:getText(),64)or song.title;song.bpm=tonumber(self.bpmEntry:getText())or song.bpm;song.bars=self.score.bars
    return {song=song,active=self.activePart,clip=self.activeClip,whole=self.editWholeTrack,first=self.firstTick,view=self.viewTicks,pitch=self.pitchScroll,context=self.editContext}
end
function Q:pushUndo(snapshot)
    self.undoStack[#self.undoStack+1]=snapshot
    if #self.undoStack>50 then table.remove(self.undoStack,1)end
    self.redoStack={};self.dirty=true
end
function Q:checkpoint()self:pushUndo(self:partSnapshot())end
function Q:restoreEdit(snapshot)
    local revision,id=self.song.revision,self.song.song
    local song,err=C.copy(snapshot.song);if not song then self.message=err;return false end
    song.revision=revision;song.song=id;self.song=song
    self:stopAudition();self:stopMonitor();self:loadPart(clamp(snapshot.active,1,#song.parts))
    self.activeClip=clamp(snapshot.clip or 1,1,math.max(1,#self.song.parts[self.activePart].clips))
    self.editWholeTrack=snapshot.whole;self.firstTick=snapshot.first;self.viewTicks=snapshot.view;self.pitchScroll=snapshot.pitch
    self.editContext=snapshot.context or "notes";self.arrCache=nil;self.otherNoteCount=nil;self.selected={};self.dirty=true
    local clip=self:currentClip();self.phraseEntry:setText(clip and clip.name or "Clip")
    self:rebuildPitches();self:clampView();self:layout();self:refreshClipTiming(true);return true
end
function Q:undo(redo)
    if not self:editable()then return end
    local from,to=redo and self.redoStack or self.undoStack,redo and self.undoStack or self.redoStack
    local snapshot=from[#from];if not snapshot then return end
    local current=self:partSnapshot()
    if self:restoreEdit(snapshot)then table.remove(from);to[#to+1]=current;self.message=redo and "Redone."or "Undone."end
end
function Q:loopCapacity()
    local others=0;for i,p in ipairs(self.song.parts)do if i~=self.activePart then others=others+#(S.decode(p.notes,self.song.bars*384)or {})end end
    return math.min(S.MAX_NOTES,S.MAX_TOTAL_NOTES-others)
end
function Q:syncLoops()
    local notes,err=C.expandLoops(self.song.parts[self.activePart],self.notes,self:loopCapacity())
    if not notes then self.message=err;return false end
    self.notes=notes;return true
end
function Q:settings()if not self:syncLoops()then return false end;return P.settings(self)end
function Q:commit(before)
    if S.equal(S.encode(self.notes),before)then return end
    for _,n in ipairs(self.notes)do if self.selected[n]and not self:noteEditable(n)then
        self.notes=S.decode(before,S.MAX_BARS*384);self.selected={};self:rebuildPitches()
        self.message="Repeated notes are linked to the loop source. Unroll before editing a repetition.";return
    end end
    local snapshot=self:partSnapshot(before)
    if not self:syncLoops()then local err=self.message;self.notes=S.decode(before,S.MAX_BARS*384);self.selected={};self:rebuildPitches();self.message=err;return end
    self:pushUndo(snapshot);C.cover(self.song.parts[self.activePart],self.notes);self.arrCache=nil;self:rebuildPitches();self.editContext="notes"
end
function Q:rememberPartView()
    self.partViews[self.score.part]={firstTick=self.firstTick,pitchScroll=self.pitchScroll,viewTicks=self.viewTicks,clip=self.activeClip,whole=self.editWholeTrack}
end
function Q:loadPart(index)
    local undo,redo=self.undoStack,self.redoStack
    P.loadPart(self,index);self.undoStack=undo;self.redoStack=redo
    local view=self.partViews[self.score.part];self.activeClip=view and view.clip or 1;self.editWholeTrack=view and view.whole or false
    self:clampView();self:refreshClipTiming(true)
end
function Q:acceptSaved(song)
    local ids={};for i,p in ipairs(song.parts)do local old=self.song.parts[i];if old then ids[old.part]=p.part end end
    for _,history in ipairs({self.undoStack,self.redoStack})do for _,state in ipairs(history)do
        for _,p in ipairs(state.song.parts)do p.part=ids[p.part]or p.part end
        state.song.active=ids[state.song.active]or state.song.active
    end end
    P.acceptSaved(self,song)
end
function Q:addPart()
    if not self:editable()or not self:settings()then return end
    if #self.song.parts>=S.MAX_PARTS then self.message="This song already has eight tracks.";return end
    self:checkpoint();P.addPart(self);self.editContext="track"
end
function Q:deletePart(index)
    if not self:editable()or not self:settings()then return end
    index=index or self.activePart;if not self.song.parts[index]then return end
    self:checkpoint();local name=self.song.parts[index].partName
    self:stopAudition();self:stopMonitor();table.remove(self.song.parts,index)
    if #self.song.parts==0 then
        self.partSerial=self.partSerial+1
        self.song.parts[1]={part="draft-"..getTimestampMs().."-"..self.partSerial,partName="Part 1",profile=0,notes="",clips={}}
    end
    self:loadPart(math.min(index,#self.song.parts));self.editContext="track";self.dirty=true
    self.message="Deleted "..name..". Ctrl+Z restores the track, clips and notes."
end
function Q:focusClip(index)
    self.editWholeTrack=false;A.focusClip(self,index)
    local c=self:currentClip();if c then self.firstTick=c.start;self.viewTicks=math.max(48,c.loopLength or c.length);self:clampView()end
    self.editContext="clip";self:refreshClipTiming(true)
end
function Q:toggleEditScope()
    self.editWholeTrack=not self.editWholeTrack;self.selected={};self:fitNotes(self.editWholeTrack)
end
function Q:clampView()
    local lo,hi=self:editBounds();self.viewTicks=clamp(self.viewTicks,math.min(48,hi-lo),hi-lo)
    self.firstTick=clamp(self.firstTick,lo,math.max(lo,hi-self.viewTicks))
    self.pitchScroll=clamp(self.pitchScroll,0,math.max(0,#self.pitches-self.rows));self.topNote=self.pitches[math.floor(self.pitchScroll)+1]or 127
end
function Q:fitNotes(whole)
    if whole then self.editWholeTrack=true end
    local all=self.notes;local visible={};for _,n in ipairs(all)do if self:noteEditable(n)then visible[#visible+1]=n end end
    self.notes=visible;R.fitNotes(self,whole);self.notes=all;self:clampView()
end
function Q:noteRect(n)if self:noteEditable(n)then return R.noteRect(self,n)end end
function Q:point(x,y,outside)
    if not outside and (x<self.gridX or x>=self.gridX+self.gridW or y<self.gridY or y>=self.gridY+self.gridH)then return nil end
    local lo,hi=self:editBounds();local t=math.floor(clamp(self:tickAt(x),lo,hi-1)/self:step())*self:step()
    return clamp(t,lo,hi-1),self:pitchAt(y)
end
function Q:addNote(t,pitch,length)
    local lo,hi=self:editBounds();if t<lo or t>=hi then return end
    if not self:noteEditable({t=t})then self.message="Edit the loop source, or Unroll to edit repetitions.";return end
    return R.addNote(self,t,pitch,math.min(length,hi-t))
end
function Q:selectAll()self.editContext="notes";self.selected={};for _,n in ipairs(self.notes)do if self:noteEditable(n)and self.pitchIndex[n.n]then self.selected[n]=true end end end
function Q:quantize()
    if not self:editable()or not self:settings()then return end
    local before=S.encode(self.notes);local count=self:selectedCount();local lo,hi=self:editBounds()
    for _,n in ipairs(self.notes)do if self:noteEditable(n)and(count==0 or self.selected[n])then
        local q=S.quantize({{n=n.n,t=n.t-lo,d=n.d,v=n.v}},math.min(self:step(),hi-lo),hi-lo)[1];n.t=q.t+lo;n.d=q.d
    end end
    self:commit(before);self.message="Quantized "..(count>0 and "selected notes."or "this clip's notes.")
end
function Q:toggleLoop()
    if not self:editable()or not self:settings()then return end
    local c=self:currentClip();if not c then return end
    if c.loopLength then self:unrollClip();return end
    self:checkpoint();c.loopLength=c.length;self.editWholeTrack=false;self.arrCache=nil
    self:refreshClipTiming(true)
    self.message="Loop on. Drag the right edge to repeat; Timing sets the exact source length in bars."
end
function Q:unrollClip()
    if not self:editable()or not self:settings()then return end
    local c=self:currentClip();if not c or not c.loopLength then return end
    self:checkpoint();c.loopLength=nil;self:focusClip(self.activeClip);self.arrCache=nil
    self.message="Unrolled. Every repetition is now independently editable. Ctrl+Z restores the loop."
end
function Q:joinTrackClips()
    if not self:editable()or not self:settings()then return end
    local p=self.song.parts[self.activePart];if #p.clips<2 then self:unrollClip();return end
    self:checkpoint();local first,last=p.clips[1].start,0
    for _,c in ipairs(p.clips)do last=math.max(last,c.start+c.length)end
    p.clips={{name=p.partName,start=first,length=last-first}};self:focusClip(1);self.arrCache=nil
    self.message="Joined this track's clips. Notes and gaps are kept; Ctrl+Z restores the separate clips."
end
function Q:arrStep()
    local step=self:step();while step/self.arrTicks*self.arrW<9 do step=step*2 end;return step
end
function Q:dropNotes(clip,drop)
    local root=clip.rootPitch
    if not root then
        local first=math.huge;root=127
        for _,n in ipairs(clip.notes)do if n.t<first then first=n.t;root=n.n elseif n.t==first then root=math.min(root,n.n)end end
    end
    local delta=(drop.pitch and not clip.drums)and drop.pitch-root or 0;local result={}
    for _,n in ipairs(clip.notes)do
        if n.n+delta<0 or n.n+delta>127 then return nil,"That root puts notes outside MIDI range."end
        result[#result+1]={n=n.n+delta,t=n.t+drop.at,d=n.d,v=n.v}
    end
    return result
end
function Q:insertLibraryClip(clip,drop,layer)
    if self.transport=="library"or self.pending=="library"then self:stop()end
    if not self:editable()or not self:settings()then return false end
    local index=drop.new and #self.song.parts+1 or drop.part;local at=math.floor(drop.at or 0)
    if not S.integer(index,1,S.MAX_PARTS)or(not drop.new and not self.song.parts[index])then self.message="This song already has eight tracks.";return false end
    if not S.integer(at,0,S.MAX_BARS*384-1)or not S.integer(clip.length,1,S.MAX_BARS*384-at)then self.message="The clip exceeds the timeline capacity.";return false end
    for _,n in ipairs(clip.notes)do if not S.integer(n.n,0,127)or not S.integer(n.t,0,clip.length-1)or not S.integer(n.d,1,clip.length-n.t)or not S.integer(n.v,1,127)then self.message="Invalid clip notes.";return false end end
    local additions,err=self:dropNotes(clip,{at=at,pitch=drop.pitch});if not additions then self.message=err;return false end
    local previous=self.song.parts[index];local p=previous and S.copy(previous)or {part="draft-import",partName=clip.name,profile=self.instrument.selected-1,notes="",clips={}}
    local notes=S.decode(p.notes,self.song.bars*384)or {};local others=0
    for i,part in ipairs(self.song.parts)do if i~=index then others=others+#S.decode(part.notes,self.song.bars*384)end end
    if clip.drums and #notes>0 and p.profile~=9 then self.message="Drop drums on a drum track, or use New track.";return false end
    if clip.drums and #notes==0 then p.profile=9 end
    local target,chosen;local finish=at+clip.length
    if drop.zone=="roll"then
        for i,c in ipairs(p.clips)do if at>=c.start and at<c.start+c.length then target=c;chosen=i;break end end
        if target and target.loopLength and finish>target.start+target.loopLength then self.message="This drop crosses the loop source boundary. Unroll, or choose a shorter pattern.";return false end
        if target then
            for _,c in ipairs(p.clips)do if c~=target and at<c.start+c.length and finish>c.start then self.message="That drop crosses another clip. Shorten it or Join track first.";return false end end
            target.length=math.max(target.length,finish-target.start)
        end
    end
    if not target then
        local kept={}
        for _,c in ipairs(p.clips)do
            local overlap=at<c.start+c.length and finish>c.start;local filled=false
            for _,n in ipairs(notes)do if n.t>=c.start and n.t<c.start+c.length then filled=true;break end end
            if overlap and filled and not layer then self.message="That arrangement space is occupied. Drop into the piano roll to add notes, or choose free space.";return false end
            if not overlap or filled then if overlap then c.loopLength=nil end;kept[#kept+1]=c end
        end
        if #kept>=128 then self.message="This track has reached its clip capacity.";return false end
        target={name=S.text(clip.name,48)or "MIDI clip",start=at,length=clip.length};kept[#kept+1]=target;p.clips=kept
    end
    -- Merge identical starts/pitches inside a piano-roll drop instead of stacking duplicate voices.
    local added=0;local byKey={};if drop.zone=="roll"then for _,n in ipairs(notes)do byKey[n.t..":"..n.n]=n end end
    for _,n in ipairs(additions)do local existing=byKey[n.t..":"..n.n]
        if existing then existing.d=math.max(existing.d,n.d);existing.v=n.v else notes[#notes+1]=n;added=added+1 end
    end
    notes,err=C.expandLoops(p,notes,math.min(S.MAX_NOTES,S.MAX_TOTAL_NOTES-others))
    if not notes then self.message=err;return false end
    C.cover(p,notes);if #p.clips>128 then self.message="This track has reached its clip capacity.";return false end
    local snapshot=self:partSnapshot();local oldFirst,oldView,oldPitch=self.firstTick,self.viewTicks,self.pitchScroll
    self:stopAudition();self:stopMonitor();self:rememberPartView()
    if drop.new then
        self.partSerial=self.partSerial+1;p.part="draft-"..getTimestampMs().."-"..self.partSerial
        self.song.parts[index]=p
    else self.song.parts[index]=p end
    p.notes=S.encode(notes);self:extendTo(finish);self:loadPart(index);self:pushUndo(snapshot)
    for i,c in ipairs(p.clips)do if at>=c.start and at<c.start+c.length then self.activeClip=i;break end end
    self.editWholeTrack=false;self.selected={};local placed={}
    for _,n in ipairs(additions)do placed[n.t..":"..n.n]=true end
    for _,n in ipairs(self.notes)do if placed[n.t..":"..n.n]and self:noteEditable(n)then self.selected[n]=true end end
    if drop.zone=="roll"then
        self.firstTick=oldFirst;self.viewTicks=oldView;self.pitchScroll=oldPitch;self.cursorTick=finish;self:clampView();self.editContext="notes"
    else self:focusClip(self.activeClip)end
    local c=self:currentClip();self.phraseEntry:setText(c and c.name or "Clip");self.arrCache=nil;self.otherNoteCount=nil;self:updateMonitor()
    self.message="Added "..added.." notes"..(drop.pitch and not clip.drums and " rooted at "..self:pitchName(drop.pitch)or "")..". Ctrl+Z undoes the drop."
    return true
end
function Q:onKeyPress(key)
    if self:isKeyConsumed(key)and not self.drag and not self.help then
        local ctrl=isCtrlKeyDown();local focus=self.editContext or "notes"
        if key==Keyboard.KEY_DELETE or key==Keyboard.KEY_BACK then
            if focus=="track"then self:deletePart();return elseif focus=="clip"then self:deletePhrase();return end
        elseif ctrl and key==Keyboard.KEY_D and focus=="clip"then self:duplicatePhrase();return end
    end
    R.onKeyPress(self,key)
end
function Q:onMouseDown(x,y)
    if y>=self.gridY or (y>=self.rulerY and y<self.gridY)then self.editContext="notes"end
    return R.onMouseDown(self,x,y)
end
function Q:drawLoopGuides()
    if self.arrHidden then return end
    for row=1,self.trackRows do local p=self.song.parts[row+(self.trackScroll or 0)]
        if p then for _,c in ipairs(p.clips)do if c.loopLength then
            local step=c.loopLength;while step/self.arrTicks*self.arrW<12 do step=step*2 end
            local y=self.arrY+self.arrRulerH+(row-1)*self.trackH
            self:setStencilRect(self.trackW,y,self.arrW,self.trackH)
            for t=c.start+math.max(1,math.ceil((self.arrFirst-c.start)/step))*step,math.min(c.start+c.length-1,self.arrFirst+self.arrTicks),step do
                self:drawRect(self.trackW+(t-self.arrFirst)/self.arrTicks*self.arrW,y+5,1,self.trackH-12,.65,.84,.83,.63)
            end
            self:clearStencilRect()
        end end end
    end
end
