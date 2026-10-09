require "DeadAirClipOps"
require "ISUI/ISContextMenu"
DeadAirWorkflow={}
local W,S,C,O,Q,A,R=DeadAirWorkflow,DeadAirScore,DeadAirComposition,DeadAirClipOps,DeadAirClipEditing,DeadAirArrangement,DeadAirRoll
local function clamp(v,a,b)return math.max(a,math.min(b,v))end
local function snap(t,step)return math.floor(t/step+.5)*step end
local function inside(x,y,r)return r and x>=r.x and x<r.x+r.w and y>=r.y and y<r.y+r.h end
function W:step()
    if self.grid.selected==7 then return 1 end
    local step=R.step(self)
    if self.noteAdaptive and self.gridW then while step/self.viewTicks*self.gridW<9 do step=step*2 end end
    return step
end
function W:arrStep()
    if isAltKeyDown()or(self.arrGrid and self.arrGrid.selected==7)then return 1 end
    if not self.arrGrid then return Q.arrStep(self)end
    local step=384/2^(self.arrGrid.selected-1)
    if self.arrAdaptive then while step/self.arrTicks*self.arrW<9 do step=step*2 end end
    return step
end
function W:snapLabel(step)
    if step==1 then return "off"end
    if step>=384 then return self:clipBars(step).." bar"end
    if 384%step==0 then return "1/"..(384/step)end
    return self:clipBars(step).." bar"
end
function W:clipSelectionSet()
    local selected={};for i in pairs(self.clipSelection or {})do if self.song.parts[self.activePart].clips[i]then selected[i]=true end end
    if not next(selected)and self:currentClip()then selected[self.activeClip]=true end
    return selected
end
function W:focusClip(index)
    Q.focusClip(self,index);self.clipSelection={[index]=true};self.timeSelection=nil;self.clipCursor=self:currentClip()and self:currentClip().start or 0
end
function W:loadPart(index)Q.loadPart(self,index);self.clipSelection={[self.activeClip]=true};self.timeSelection=nil end
function W:partSnapshot(notes)local state=Q.partSnapshot(self,notes);state.clipSelection=S.copy(self:clipSelectionSet());return state end
function W:restoreEdit(state)
    local ok=Q.restoreEdit(self,state);if ok then self.clipSelection=S.copy(state.clipSelection or {[self.activeClip]=true});self.timeSelection=nil end;return ok
end
function W:acceptClipEdit(edited,err,message)
    if not edited then self.message=err;return false end
    if not edited.active then
        local chosen=edited.clips[self.activeClip];table.sort(edited.clips,function(a,b)return a.start<b.start end)
        for i,c in ipairs(edited.clips)do if c==chosen then edited.active=i;break end end
    end
    self:checkpoint();self.song.parts[self.activePart].clips=edited.clips;self.notes=edited.notes
    for _,c in ipairs(edited.clips)do self:extendTo(c.start+c.length)end
    self.arrCache=nil;self:rebuildPitches();self:focusClip(edited.active or self.activeClip)
    self.clipSelection=edited.selected or {[self.activeClip]=true};self:refreshClipTiming(true);self.message=message;return true
end
function W:splitClip(tick)
    if not self:editable()or not self:settings()then return false end
    local edit,err=O.split(self.song.parts[self.activePart],self.notes,self.activeClip,tick or self.clipCursor or self.cursorTick,self:loopCapacity())
    return self:acceptClipEdit(edit,err,"Clip split. Notes crossing the cut are split too; Ctrl+Z restores the original.")
end
function W:uniqueRepeat(tick)
    if not self:editable()or not self:settings()then return false end
    local edit,err=O.unique(self.song.parts[self.activePart],self.notes,self.activeClip,tick or self.clipCursor or self.playFrom or 0,self:loopCapacity())
    return self:acceptClipEdit(edit,err,"This repetition is now an independent variation. Other repetitions keep their source.")
end
function W:consolidateClips()
    if not self:editable()or not self:settings()then return false end
    local edit,err=O.consolidate(self.song.parts[self.activePart],self.notes,self:clipSelectionSet(),self:loopCapacity())
    return self:acceptClipEdit(edit,err,"Selected clips consolidated. Notes and gaps kept; Ctrl+Z restores them.")
end
function W:deletePhrase()
    if not self:editable()or not self:settings()then return end
    local edit,err=O.delete(self.song.parts[self.activePart],self.notes,self:clipSelectionSet(),self:loopCapacity())
    self:acceptClipEdit(edit,err,"Selected clips deleted. Ctrl+Z restores them.")
end
function W:duplicatePhrase()
    if not self:editable()or not self:settings()then return end
    local p=self.song.parts[self.activePart];local selected=self:clipSelectionSet();local lo,hi=math.huge,0
    for i,c in ipairs(p.clips)do if selected[i]then lo=math.min(lo,c.start);hi=math.max(hi,c.start+c.length)end end
    if lo==math.huge then return end
    local at=hi;local span=hi-lo
    for _,c in ipairs(p.clips)do if c.start<at+span and c.start+c.length>at then at=c.start+c.length end end
    local edit,err=O.move(p,self.notes,selected,at-lo,true,self:loopCapacity())
    self:acceptClipEdit(edit,err,"Selected clips duplicated together, preserving the gaps.")
end
function W:setLoopRange(first,last)
    if not self:editable()or not self:settings()then return false end
    local c=self:currentClip();if not c then return false end
    if first<c.start or last<=first then self.message="Choose a loop range inside the clip.";return false end
    local edit,err=C.retimeClip(self.song.parts[self.activePart],self.notes,self.activeClip,c.start,math.max(c.length,last-c.start),last-first,self:loopCapacity(),first-c.start)
    return self:acceptClipEdit(edit,err,"Loop range set. Notes before the brace play once; the brace repeats. Ctrl+Z restores it.")
end
function W:loopPreset(bars)
    local c=self:currentClip();if not c then return end
    local first=c.start+(c.loopStart or 0);self:setLoopRange(first,first+bars*384)
end
function W:loopSelection()
    local first,last
    if self.timeSelection then first,last=self.timeSelection[1],self.timeSelection[2]
    else for n,on in pairs(self.selected)do if on then first=math.min(first or n.t,n.t);last=math.max(last or 0,n.t+n.d)end end end
    if not first then self.message="Select notes, or Shift-drag the loop strip to select time.";return false end
    local step=self:step();return self:setLoopRange(math.floor(first/step)*step,math.ceil(last/step)*step)
end
function W:applyClipTiming()
    if not self.loopStartEntry or not(self:currentClip()and self:currentClip().loopLength)then return Q.applyClipTiming(self)end
    if not self:editable()or not self:settings()then return false end
    local c=self:currentClip();local start=tonumber(self.clipStartEntry:getText());local length=tonumber(self.clipLengthEntry:getText())
    local first=tonumber(self.loopStartEntry:getText());local period=tonumber(self.clipLoopEntry:getText())
    for _,v in ipairs({start or -1,length or -1,first or -1,period or -1})do if v~=v or v<0 or v>S.MAX_BARS+1 then self.message="Enter valid bar numbers for the clip and loop range.";return false end end
    start=snap((start-1)*384,1);length=snap(length*384,1);first=snap((first-1)*384,1);period=snap(period*384,1)
    if start==c.start and length==c.length and period==c.loopLength and first==c.start+(c.loopStart or 0)then self:refreshClipTiming(true);return true end
    local edit,err=C.retimeClip(self.song.parts[self.activePart],self.notes,self.activeClip,start,length,period,self:loopCapacity(),first-start)
    return self:acceptClipEdit(edit,err,"Exact clip and loop timing applied. Ctrl+Z restores the previous timing.")
end
function W:clampView()
    if not self.pitches then return end
    local c=self:currentClip();local lo=c and not self.editWholeTrack and c.start or 0;local hi=c and not self.editWholeTrack and c.start+c.length or self:ticks()
    self.viewTicks=clamp(self.viewTicks,math.min(48,hi-lo),hi-lo);self.firstTick=clamp(self.firstTick,lo,math.max(lo,hi-self.viewTicks))
    self.pitchScroll=clamp(self.pitchScroll,0,math.max(0,#self.pitches-self.rows));self.topNote=self.pitches[math.floor(self.pitchScroll)+1]or 127
end
function W:arrMouseDown(x,y)
    if self.help or self.arrHidden or not self.arrY or y<self.arrY or y>=self.arrY+self.arrH then return false end
    for _,hit in ipairs(self.trackHits or {})do if hit.clip and inside(x,y,hit)then
        if not self:editable()or not self:settings()then return true end
        if hit.part~=self.activePart then self:switchPart(hit.part);self.clipSelection={}end
        local selected=self:clipSelectionSet();local anchor=self.activeClip
        Q.focusClip(self,hit.clip);self.clipCursor=clamp(snap(self.arrFirst+(x-self.trackW)/self.arrW*self.arrTicks,self:arrStep()),0,self:ticks()-1)
        if isCtrlKeyDown()then selected[hit.clip]=not selected[hit.clip]or nil;self.clipSelection=selected;return true end
        if isShiftKeyDown()then for i=math.min(anchor,hit.clip),math.max(anchor,hit.clip)do selected[i]=true end;self.clipSelection=selected;return true end
        self.clipSelection=selected[hit.clip]and selected or {[hit.clip]=true}
        local edge=hit.resize and x>=hit.x+hit.w-8
        if edge then self.clipSelection={[hit.clip]=true}end
        local c=self:currentClip();local d=self:beginDrag(edge and "clipEnd"or "clipGroup",x,y)
        d.snapshot=self:partSnapshot();d.clip=hit.clip;d.old=S.copy(c);d.clips=S.copy(self.song.parts[self.activePart].clips);d.notes=S.copy(self.notes);d.bars=self.score.bars;d.arrTicks=self.arrTicks;d.selection=S.copy(self.clipSelection)
        return true
    end end
    return A.arrMouseDown(self,x,y)
end
function W:arrDrag(x,y)
    local d=self.drag;if not d then return false end
    if d.kind=="divider"then self.arrangementHeight=clamp(d.height+y-d.y,self.trackH,math.max(self.trackH,self.height*.5));self:layout();return true end
    if d.kind=="clipGroup"then
        if not d.moved and math.abs(x-d.x)<5 then return true end;d.moved=true
        local step=self:arrStep();local destination=snap(d.old.start+(x-d.x)/self.arrW*d.arrTicks,step)
        local lo=d.old.start;for i,c in ipairs(d.clips)do if d.selection[i]then lo=math.min(lo,c.start)end end
        local delta=math.max(-lo,destination-d.old.start)
        local edit,err=O.move({clips=d.clips},d.notes,d.selection,delta,false,self:loopCapacity())
        if not edit then self.message=err;return true end
        self.song.parts[self.activePart].clips=edit.clips;self.notes=edit.notes;self.activeClip=edit.active;self.clipSelection=edit.selected;d.applied=true
        for _,c in ipairs(edit.clips)do self:extendTo(c.start+c.length)end
        self.arrCache=nil;return true
    end
    if d.kind=="loopStart"or d.kind=="loopEnd"or d.kind=="loopSelect"then
        local step=isAltKeyDown()and 1 or self:step();local tick=clamp(snap(d.first+(x-self.gridX)/self.gridW*d.view,step),d.old.start,S.MAX_BARS*384)
        if d.kind=="loopSelect"then self.timeSelection={math.min(d.tick,tick),math.max(d.tick,tick)};return true end
        local first=d.old.start+(d.old.loopStart or 0);local last=first+(d.old.loopLength or d.old.length)
        if d.kind=="loopStart"then first=math.min(tick,last-1)else last=math.max(first+1,tick)end
        local edit,err=C.retimeClip({clips=d.clips},d.notes,d.clip,d.old.start,math.max(d.old.length,last-d.old.start),last-first,self:loopCapacity(),first-d.old.start)
        if not edit then self.message=err;return true end
        self.song.parts[self.activePart].clips=edit.clips;self.notes=edit.notes;self:extendTo(d.old.start+edit.clips[d.clip].length);self.arrCache=nil;d.applied=true;return true
    end
    return A.arrDrag(self,x,y)
end
function W:arrFinish(cancel)
    local d=self.drag;if not d then return false end
    if d.kind=="divider"then self.drag=nil;self:setCapture(false);if cancel then self.arrangementHeight=d.height;self:layout()end;return true end
    if d.kind=="clipGroup"or d.kind=="loopStart"or d.kind=="loopEnd"or d.kind=="loopSelect"then
        self.drag=nil;self:setCapture(false)
        if cancel then self:restoreEdit(d.snapshot)
        elseif d.kind=="loopSelect"then self.message="Time selected. Loop selection (Ctrl+L) sets the loop; notes past the end must be split off first."
        elseif d.applied then self:pushUndo(d.snapshot);self:refreshClipTiming(true);self:rebuildPitches()end
        return true
    end
    return A.arrFinish(self,cancel)
end
function W:onMouseDown(x,y)
    if not self.help and self.dividerY and not self.arrHidden and y>=self.dividerY and y<self.dividerY+8 and x<self.bodyW then
        local d=self:beginDrag("divider",x,y);d.height=self.arrangementHeight or self.arrH-self.arrRulerH;return true
    end
    local c=self:currentClip()
    if not self.help and c and self.loopY and y>=self.loopY and y<self.loopY+self.loopH and x>=self.gridX and x<=self.gridX+self.gridW then
        if not self:editable()or not self:settings()then return true end
        local first=c.start+(c.loopStart or 0);local last=first+(c.loopLength or c.length)
        local left=self.gridX+(first-self.firstTick)/self.viewTicks*self.gridW;local right=self.gridX+(last-self.firstTick)/self.viewTicks*self.gridW
        local kind=not isShiftKeyDown()and math.abs(x-left)<=9 and "loopStart"or not isShiftKeyDown()and math.abs(x-right)<=9 and "loopEnd"or "loopSelect"
        local d=self:beginDrag(kind,x,y);d.snapshot=self:partSnapshot();d.old=S.copy(c);d.clip=self.activeClip;d.clips=S.copy(self.song.parts[self.activePart].clips);d.notes=S.copy(self.notes)
        d.tick=clamp(snap(self:tickAt(x),self:step()),c.start,c.start+c.length);self.editContext="notes";self:blurFields();return true
    end
    local result=Q.onMouseDown(self,x,y)
    if self.editContext=="notes"then self.clipCursor=self.cursorTick end;return result
end
function W:clipMenu(x,y)
    if not ISContextMenu or not ISContextMenu.get then return end
    local menu=ISContextMenu.get(0,(self.getAbsoluteX and self:getAbsoluteX()or self.x)+x,(self.getAbsoluteY and self:getAbsoluteY()or self.y)+y)
    local function option(label,fn,enabled)local o=menu:addOption(label,self,fn);o.notAvailable=enabled==false or self.transport~=nil or self.pending~=nil or self.saving==true end
    option("Split at cursor   Ctrl+E",function(p)p:splitClip()end)
    option("Consolidate selected   Ctrl+J",function(p)p:consolidateClips()end)
    option("Make this repeat unique",function(p)p:uniqueRepeat()end,self:currentClip()and self:currentClip().loopLength~=nil)
    option("Duplicate selected   Ctrl+D",function(p)p:duplicatePhrase()end)
    option("Delete selected clips   Delete",function(p)p:deletePhrase()end)
    option("Loop selection   Ctrl+L",function(p)p:loopSelection()end)
    option("Delete this track (undoable)",function(p)p:deletePart()end,#self.song.parts>1)
    menu:addOption("Clip inspector",self,function(p)p.inspectorOpen=true;p.libraryOpen=false;if p.libraryPanel then p.libraryPanel:setVisible(false)end;p:layout()end)
    self.workflowMenu=menu
end
function W:onRightMouseDown(x,y)
    for _,hit in ipairs(self.trackHits or {})do if not self.arrHidden and hit.clip and inside(x,y,hit)then
        if hit.part~=self.activePart then self:switchPart(hit.part)end
        if not self:clipSelectionSet()[hit.clip]then self:focusClip(hit.clip)end
        self.activeClip=hit.clip;self.editContext="clip";self.clipCursor=snap(self.arrFirst+(x-self.trackW)/self.arrW*self.arrTicks,self:arrStep());self:clipMenu(x,y);return true
    end end
    local tick=self:point(x,y)
    if self.mode=="select"and tick then self.clipCursor=tick;self:clipMenu(x,y);return true end
    return R.onRightMouseDown(self,x,y)
end
function W:keyHandled(key)
    if isCtrlKeyDown()and(key==Keyboard.KEY_E or key==Keyboard.KEY_J or key==Keyboard.KEY_L)then return true end
    return R.keyHandled(self,key)
end
function W:onKeyPress(key)
    if self:isKeyConsumed(key)and not self.drag and not self.help and isCtrlKeyDown()then
        if key==Keyboard.KEY_E then self:splitClip();return elseif key==Keyboard.KEY_J then self:consolidateClips();return elseif key==Keyboard.KEY_L then self:loopSelection();return end
    end
    return Q.onKeyPress(self,key)
end
