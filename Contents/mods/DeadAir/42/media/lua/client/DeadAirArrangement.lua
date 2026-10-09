require "DeadAirComposition"
DeadAirArrangement={}
local A,S,C=DeadAirArrangement,DeadAirScore,DeadAirComposition
local function clamp(v,a,b)return math.max(a,math.min(b,v))end
local function inside(x,y,r)return r and x>=r.x and x<r.x+r.w and y>=r.y and y<r.y+r.h end
local function short(s,w)
    local tm=getTextManager();s=tostring(s)
    if tm:MeasureStringX(UIFont.Small,s)<=w then return s end
    while #s>0 and tm:MeasureStringX(UIFont.Small,s.."...")>w do s=s:sub(1,-2)end
    return s.."..."
end
function A:partSnapshot(notes)
    return {notes=notes or S.encode(self.notes),clips=S.copy(self.song.parts[self.activePart].clips or {}),bars=self.score.bars,profile=self.instrument.selected-1}
end
function A:noteRoom()
    if not self.otherNoteCount then
        self.otherNoteCount=0
        for i,p in ipairs(self.song.parts)do if i~=self.activePart then self.otherNoteCount=self.otherNoteCount+#(S.decode(p.notes,self.song.bars*384)or {})end end
    end
    local count=#self.notes+self.otherNoteCount
    return math.max(0,math.min(S.MAX_NOTES-#self.notes,S.MAX_TOTAL_NOTES-count))
end
function A:extendTo(tick)
    if tick>S.MAX_BARS*384 then self.message="This sheet has reached its timeline capacity. Start another sheet.";return false end
    local bars=math.max(self.score.bars,math.ceil(tick/384));self.score.bars=bars;self.song.bars=bars
    if self.barsEntry then self.barsEntry:setText(tostring(bars))end
    return true
end
function A:transportTick()return (self.playFrom or 0)+(DeadAir.api()and DeadAirMidi.scoreTick()or 0)end
function A:audible(index)
    local solo=false;for _,p in ipairs(self.song.parts)do if p.solo then solo=true;break end end
    local p=self.song.parts[index];return not p.mute and (not solo or p.solo)
end
function A:applyTrackGains()
    if not self.transport or self.transport=="library"or not DeadAir.api()then return end
    -- Listening volume is applied once by the master output; parts only need mute/solo.
    for i,slot in pairs(self.previewMap or {})do DeadAirMidi.scoreGain(slot,self:audible(i)and 1 or 0)end
end
function A:toggleTrack(index,field)
    if self.saving then return end
    self:checkpoint();local p=self.song.parts[index];p[field]=not p[field];self.dirty=true;self:applyTrackGains()
    self.message=p.partName..(field=="solo"and (p.solo and " soloed."or " solo off.")or (p.mute and " muted."or " unmuted."))
end
function A:fitArrangement()
    self.arrFirst=0;self.arrTicks=math.max(1536,self:ticks());self.trackScroll=clamp(self.trackScroll or 0,0,math.max(0,#self.song.parts-(self.trackRows or 3)))
end
function A:focusClip(index)
    local p=self.song.parts[self.activePart];local c=p.clips and p.clips[index]
    if not c then return end
    self.activeClip=index;self.selected={};self.firstTick=c.start;self.viewTicks=math.max(96,c.length);self.cursorTick=c.start;self.playFrom=c.start
    self:clampView();self.phraseEntry:setText(c.name)
    local lo,hi=127,0
    for _,n in ipairs(self.notes)do if n.t>=c.start and n.t<c.start+c.length then lo=math.min(lo,n.n);hi=math.max(hi,n.n)end end
    if hi>=lo and self.pitchIndex[hi]then self.pitchScroll=math.max(0,self.pitchIndex[hi]-2);self:clampView()end
end
function A:renamePhrase()
    if not self:editable()then return end
    local c=self.song.parts[self.activePart].clips[self.activeClip or 1];local name=S.text(self.phraseEntry:getText(),48)
    if c and name and name~=c.name then self:checkpoint();c.name=name;self.dirty=true end
end
function A:newPhrase()
    if not self:editable()or not self:settings()then return end
    local p=self.song.parts[self.activePart]
    if #p.clips>=128 then self.message="This track has reached its clip capacity.";return end
    local at=math.floor((self.playFrom or 0)/384)*384
    -- Place a new empty clip in free space, advancing past occupied clips.
    for _,c in ipairs(p.clips)do if at<c.start+c.length and at+1536>c.start then at=c.start+c.length end end
    if at+1536>S.MAX_BARS*384 then return end
    self:checkpoint();self:extendTo(at+1536);p.clips[#p.clips+1]={name="Clip "..(#p.clips+1),start=at,length=1536}
    table.sort(p.clips,function(a,b)return a.start<b.start end)
    for i,c in ipairs(p.clips)do if c.start==at then self:focusClip(i);break end end
    self:fitArrangement();self.arrCache=nil;self.dirty=true
end
function A:duplicatePhrase()
    if not self:editable()or not self:settings()then return end
    local p=self.song.parts[self.activePart];local c=p.clips[self.activeClip or 1];if not c then return end
    if #p.clips>=128 then self.message="This track has reached its clip capacity.";return end
    local at=c.start+c.length
    for _,other in ipairs(p.clips)do if at<other.start+other.length and at+c.length>other.start then at=other.start+other.length end end
    local copied={};for _,n in ipairs(self.notes)do if n.t>=c.start and n.t<c.start+c.length then local copy=S.copy(n);copy.t=at+n.t-c.start;copied[#copied+1]=copy end end
    if #copied>self:noteRoom()then self.message="Not enough note capacity to duplicate this clip.";return end
    if at+c.length>S.MAX_BARS*384 then return end
    self:checkpoint();self:extendTo(at+c.length);for _,n in ipairs(copied)do self.notes[#self.notes+1]=n end
    p.clips[#p.clips+1]={name=c.name.." copy",start=at,length=c.length,loopLength=c.loopLength,loopStart=c.loopStart};table.sort(p.clips,function(a,b)return a.start<b.start end)
    for i,other in ipairs(p.clips)do if other.start==at then self:focusClip(i);break end end
    self.arrCache=nil;self:fitArrangement();self:rebuildPitches()
end
function A:deletePhrase()
    if not self:editable()or not self:settings()then return end
    local p=self.song.parts[self.activePart];local c=p.clips[self.activeClip or 1];if not c then return end
    self:checkpoint()
    for i=#self.notes,1,-1 do local n=self.notes[i];if n.t>=c.start and n.t<c.start+c.length then table.remove(self.notes,i)end end
    table.remove(p.clips,self.activeClip or 1);self.activeClip=1;self.selected={};self.arrCache=nil;self:rebuildPitches()
    self.message="Clip removed. Undo restores the clip and its notes."
end
function A:arrMouseDown(x,y)
    if self.help or not self.arrY or (self.notesOnly or self.arrHidden) then return false end
    if y<self.arrY or y>=self.arrY+self.arrH then return false end
    if y<self.arrY+self.arrRulerH then
        if x>=self.trackW and not self.transport and not self.pending then self.playFrom=clamp(math.floor((self.arrFirst+(x-self.trackW)/self.arrW*self.arrTicks)/96)*96,0,self:ticks()-96)end
        return true
    end
    for _,r in ipairs(self.trackHits or {})do if inside(x,y,r)then
        if r.action=="mute"or r.action=="solo"then self:toggleTrack(r.part,r.action);return true end
        if not self:editable()or not self:settings()then return true end
        if r.part~=self.activePart then self:switchPart(r.part)end
        self.editContext=r.clip and "clip"or "track"
        if r.clip then
            self:focusClip(r.clip)
            local c=self.song.parts[self.activePart].clips[r.clip]
            local d=self:beginDrag(r.resize and x>=r.x+r.w-8 and "clipEnd"or "clipMove",x,y)
            d.snapshot=self:partSnapshot();d.clip=r.clip;d.old=S.copy(c);d.clips=S.copy(self.song.parts[self.activePart].clips);d.notes=S.copy(self.notes);d.bars=self.score.bars;d.arrTicks=self.arrTicks
        else self:focusClip(self.activeClip or 1);self.editContext="track"end
        return true
    end end
    return true
end
function A:arrDrag(x,y)
    local d=self.drag;if not d or (d.kind~="clipMove"and d.kind~="clipEnd")then return false end
    if not d.moved and math.abs(x-d.x)<5 then return true end;d.moved=true
    local step=self:arrStep();local delta=(x-d.x)/self.arrW*d.arrTicks
    local start,length=d.old.start,d.old.length
    if d.kind=="clipMove"then start=math.max(0,math.floor((start+delta)/step+.5)*step)else
        local minLength=96;for _,n in ipairs(d.notes)do if n.t>=start and n.t<start+length then minLength=math.max(minLength,n.t+n.d-start)end end
        -- Snap the destination edge, not the drag delta. Round the note-protection
        -- boundary UP too, so trimming against a note cannot leave a crooked edge.
        local minimum=start+(d.old.loopLength and (d.old.loopStart or 0)+d.old.loopLength or minLength)
        local finish=math.max(math.ceil(minimum/step)*step,math.floor((start+length+delta)/step+.5)*step)
        length=finish-start
    end
    local edited,err=C.retimeClip({clips=d.clips},d.notes,d.clip,start,length,d.old.loopLength,self:loopCapacity())
    if not edited then self.message=err;return true end
    self.song.parts[self.activePart].clips=edited.clips;self.notes=edited.notes;d.applied=true
    local changed=edited.clips[d.clip]
    self:extendTo(start+length);self.firstTick=start;self.viewTicks=math.max(48,changed.loopLength and (changed.loopStart or 0)+changed.loopLength or length);self.arrCache=nil;self:clampView()
    self.message="Clip starts at bar "..self:clipBars(start+384).."; length "..self:clipBars(length).." bars."
    return true
end
function A:arrFinish(cancel)
    local d=self.drag;if not d or (d.kind~="clipMove"and d.kind~="clipEnd")then return false end
    self.drag=nil;self:setCapture(false)
    local p=self.song.parts[self.activePart]
    if cancel then self:restoreEdit(d.snapshot);return true
    elseif d.applied then self:pushUndo(d.snapshot)end
    local chosen=p.clips[d.clip];table.sort(p.clips,function(a,b)return a.start<b.start end)
    for i,c in ipairs(p.clips)do if c==chosen then self.activeClip=i;break end end
    self.arrCache=nil;self:rebuildPitches();return true
end
function A:arrWheel(delta)
    if (self.notesOnly or self.arrHidden) or not self.arrY then return false end
    local x,y=self:getMouseX(),self:getMouseY();if y<self.arrY or y>=self.arrY+self.arrH then return false end
    if isCtrlKeyDown()then
        local fraction=clamp((x-self.trackW)/self.arrW,0,1);local at=self.arrFirst+fraction*self.arrTicks
        self.arrTicks=clamp(self.arrTicks*(delta<0 and .8 or 1.25),384,S.MAX_BARS*384);self.arrFirst=math.max(0,at-fraction*self.arrTicks)
    elseif isShiftKeyDown()then self.arrFirst=clamp(self.arrFirst+delta*self.arrTicks/8,0,math.max(0,self:ticks()-self.arrTicks))
    else self.trackScroll=clamp((self.trackScroll or 0)+delta,0,math.max(0,#self.song.parts-self.trackRows))end
    return true
end
function A:drawArrangement()
    self.trackHits={}
    if (self.notesOnly or self.arrHidden) then return end
    local x,w,y=self.trackW,self.arrW,self.arrY
    self:drawRect(12,y,(self.bodyW or self.width)-24,self.arrH,1,.105,.11,.095)
    self:drawRect(x,y,w,self.arrRulerH,1,.16,.17,.145)
    self:drawText("PART / INSTRUMENT",20,y+4,.68,.69,.62,1,UIFont.Small)
    local step=384;while step/self.arrTicks*w<52 do step=step*2 end
    self:setStencilRect(x,y,w,self.arrH)
    for tick=math.ceil(self.arrFirst/step)*step,self.arrFirst+self.arrTicks,step do
        local px=x+(tick-self.arrFirst)/self.arrTicks*w
        self:drawRect(px,y+self.arrRulerH,1,self.arrH-self.arrRulerH,.24,.55,.57,.46)
        self:drawText(tostring(math.floor(tick/384)+1),px+5,y+4,.78,.79,.70,1,UIFont.Small)
    end
    self:clearStencilRect()
    for row=1,self.trackRows do
        local i=row+(self.trackScroll or 0);local p=self.song.parts[i];local py=y+self.arrRulerH+(row-1)*self.trackH
        if p then
            local selected=i==self.activePart
            self:drawRect(12,py,(self.bodyW or self.width)-24,self.trackH-1,selected and .38 or .16,.31,.33,.26)
            local buttonW=math.max(24,self.fontH+8);local buttonH=math.max(22,self.fontH+6)
            local controls=x-3*buttonW-6;local textW=controls-26;local buttonY=py+(self.trackH-buttonH)/2
            self:drawText(short(p.partName,textW),20,py+4,selected and .88 or .73,selected and .90 or .75,.70,1,UIFont.Small)
            self:drawText(short(S.names[p.profile+1],textW),20,py+5+self.fontH,.60,.61,.54,1,UIFont.Small)
            for j,action in ipairs({"mute","solo","record"})do
                local bx=controls+(j-1)*buttonW;local on=action=="record"and selected or p[action]
                local label=action=="mute"and "M"or action=="solo"and "S"or "R"
                self:drawRect(bx,buttonY,buttonW-3,buttonH,1,on and (action=="record"and .48 or .40)or .16,on and (action=="record"and .21 or .43)or .17,on and .25 or .14)
                self:drawRectBorder(bx,buttonY,buttonW-3,buttonH,1,.38,.40,.32)
                self:drawText(label,bx+(buttonW-3-getTextManager():MeasureStringX(UIFont.Small,label))/2,buttonY+(buttonH-self.fontH)/2,.88,.87,.78,1,UIFont.Small)
                self.trackHits[#self.trackHits+1]={x=bx,y=buttonY,w=buttonW-3,h=buttonH,part=i,action=action}
            end
            self.trackHits[#self.trackHits+1]={x=12,y=py,w=x-12,h=self.trackH,part=i}
            local notes=i==self.activePart and self.notes or nil
            self.arrCache=self.arrCache or {}
            if not notes then self.arrCache[i]=self.arrCache[i]or S.decode(p.notes,self.song.bars*384);notes=self.arrCache[i]end
            self:setStencilRect(x,py,w,self.trackH-1)
            for j,c in ipairs(p.clips or {})do
                local cx=x+(c.start-self.arrFirst)/self.arrTicks*w;local cw=c.length/self.arrTicks*w
                if cx+cw>x and cx<x+w then
                    local active=selected and ((self.clipSelection and self.clipSelection[j])or j==(self.activeClip or 1));local audible=self:audible(i)
                    self:drawRect(cx+1,py+4,math.max(2,cw-2),self.trackH-9,audible and .94 or .40,active and .44 or .30,active and .47 or .34,active and .33 or .25)
                    self:drawRectBorder(cx+1,py+4,math.max(2,cw-2),self.trackH-9,1,active and .72 or .45,active and .75 or .49,active and .55 or .36)
                    if cw>35 then self:drawText(short(c.name..(c.loopLength and "  [loop]"or ""),cw-12),math.max(x+4,cx+6),py+6,.91,.91,.80,1,UIFont.Small)end
                    for _,n in ipairs(notes or {})do if n.t>=c.start and n.t<c.start+c.length then
                        local nx=x+(n.t-self.arrFirst)/self.arrTicks*w
                        self:drawRect(nx,py+24+(127-n.n)/127*9,math.max(1,n.d/self.arrTicks*w),2,.7,.79,.82,.64)
                    end end
                    self:drawRect(cx+cw-5,py+9,2,self.trackH-19,.65,.81,.82,.66)
                    self.trackHits[#self.trackHits+1]={x=math.max(x,cx),y=py+4,w=math.min(x+w,cx+cw)-math.max(x,cx),h=self.trackH-9,part=i,clip=j,resize=cx+cw<=x+w}
                end
            end
            if selected and self.transport=="record"then
                local from=x+((self.playFrom or 0)-self.arrFirst)/self.arrTicks*w
                local untilX=x+(self:transportTick()-self.arrFirst)/self.arrTicks*w
                self:drawRect(from,py+4,math.max(4,untilX-from),self.trackH-9,.36,.70,.28,.17)
                self:drawRectBorder(from,py+4,math.max(4,untilX-from),self.trackH-9,.9,.84,.47,.32)
                self:drawText("Recording...",math.max(x+4,from+6),py+6,.98,.78,.63,1,UIFont.Small)
            end
            self:clearStencilRect()
        else self:drawText(row==1 and "Add a part to begin"or "",20,py+10,.55,.57,.50,1,UIFont.Small)end
    end
    self:drawLoopGuides()
    local tick=self.transport and self.transport~="library"and self:transportTick()or (self.playFrom or 0)
    if tick>=self.arrFirst and tick<=self.arrFirst+self.arrTicks then self:drawRect(x+(tick-self.arrFirst)/self.arrTicks*w,y,2,self.arrH,1,.84,.65,.39)end
    if #self.song.parts>self.trackRows then
        self:drawText(tostring((self.trackScroll or 0)+1).."-"..math.min(#self.song.parts,(self.trackScroll or 0)+self.trackRows).." / "..#self.song.parts,x-60,y+4,.72,.73,.64,1,UIFont.Small)
    end
end
