require "DeadAirScore"
-- Editor-only editing and navigation; never modifies saved paper until Save is pressed.
DeadAirRoll={}
local R,S=DeadAirRoll,DeadAirScore
local function clamp(v,a,b)return math.max(a,math.min(b,v))end
local function round(v)return math.floor(v+.5)end
local function ctrl()return isCtrlKeyDown and isCtrlKeyDown()end
local function shift()return isShiftKeyDown and isShiftKeyDown()end
local function alt()return isAltKeyDown and isAltKeyDown()end
R.scales={
    {"Major",{0,2,4,5,7,9,11}},{"Natural minor",{0,2,3,5,7,8,10}},
    {"Harmonic minor",{0,2,3,5,7,8,11}},{"Melodic minor",{0,2,3,5,7,9,11}},
    {"Dorian",{0,2,3,5,7,9,10}},{"Phrygian",{0,1,3,5,7,8,10}},
    {"Lydian",{0,2,4,6,7,9,11}},{"Mixolydian",{0,2,4,5,7,9,10}},
    {"Locrian",{0,1,3,5,6,8,10}},{"Major pentatonic",{0,2,4,7,9}},
    {"Minor pentatonic",{0,3,5,7,10}},{"Blues",{0,3,5,6,7,10}}
}
function R:inScale(n)
    if not self.scaleEnabled then return true end
    local pc=(n-(self.rootNote.selected-1))%12
    for _,v in ipairs(DeadAirRoll.scales[self.scaleType.selected][2])do if pc==v then return true end end
    return false
end
function R:scaleChanged()
    self:finishDrag(false);self.fold=false;self.selected={};self:rebuildPitches()
    local target=self.scaleAnchor or 72;local best,distance=0,128
    for i,n in ipairs(self.pitches)do if math.abs(n-target)<distance then best=i-1;distance=math.abs(n-target)end end
    self.pitchScroll=best-math.floor(self.rows/3);self:clampView();self:layout()
end
function R:step()return S.step(self.denominators[self.grid.selected],self.triplet)end
function R:ticks()return self.score.bars*384 end
function R:selectedCount()local n=0;for _,note in ipairs(self.notes)do if self.selected[note]then n=n+1 end end;return n end
function R:checkpoint()
    self.undoStack[#self.undoStack+1]=self:partSnapshot()
    if #self.undoStack>50 then table.remove(self.undoStack,1)end
    self.redoStack={};self.dirty=true
end
function R:commit(before)
    if S.equal(S.encode(self.notes),before) then return end
    self.undoStack[#self.undoStack+1]=self:partSnapshot(before);if #self.undoStack>50 then table.remove(self.undoStack,1)end
    self.redoStack={};self.dirty=true;DeadAirComposition.cover(self.song.parts[self.activePart],self.notes);self.arrCache=nil;self:rebuildPitches()
end
function R:undo(redo)
    if not self:editable()then return end
    local from,to=redo and self.redoStack or self.undoStack,redo and self.undoStack or self.redoStack
    local wire=table.remove(from);if not wire then return end
    to[#to+1]=self:partSnapshot();self.notes=S.decode(wire.notes,S.MAX_BARS*384);self.song.parts[self.activePart].clips=S.copy(wire.clips)
    if wire.profile then self.instrument.selected=wire.profile+1;self.song.parts[self.activePart].profile=wire.profile;self:updateMonitor()end
    self:extendTo(wire.bars*384);self.activeClip=math.min(self.activeClip or 1,#wire.clips);self.arrCache=nil;self.selected={};self.dirty=true;self:rebuildPitches()
end
function R:rebuildPitches()
    self.pitches={};self.pitchIndex={}
    local seen={};for _,n in ipairs(self.notes)do seen[n.n]=true end
    for n=127,0,-1 do
        if self.transport=="record"or ((not self.fold or #self.notes==0 or seen[n]) and (not self.scaleOnly or self:inScale(n)))then self.pitches[#self.pitches+1]=n end
    end
    if #self.pitches==0 then for n=127,0,-1 do if not self.scaleOnly or self:inScale(n)then self.pitches[#self.pitches+1]=n end end end
    for i,n in ipairs(self.pitches)do self.pitchIndex[n]=i-1 end
    self.pitchScroll=clamp(self.pitchScroll or 44,0,math.max(0,#self.pitches-(self.rows or 24)))
    self.topNote=self.pitches[math.floor(self.pitchScroll)+1] or 127
end
-- Center musical material, not the top of the MIDI range. This only changes the
-- viewport; pitches, scale settings and recorded timing remain untouched.
function R:centerPitchRange(low,high)
    if not self.rows or not self.pitches or #self.pitches==0 then return end
    local top,bottom
    for i,pitch in ipairs(self.pitches)do if pitch>=low and pitch<=high then top=top or i-1;bottom=i-1 end end
    if not top then
        local target=(low+high)/2;local distance=128
        for i,pitch in ipairs(self.pitches)do if math.abs(pitch-target)<distance then top=i-1;bottom=i-1;distance=math.abs(pitch-target)end end
    end
    if bottom-top+5>self.rows then
        self.rowH=clamp(math.floor(self.availableGridH/(bottom-top+5)),10,self.rowH);self:layout()
    end
    self.pitchScroll=(top+bottom)/2-(self.rows-1)/2;self:clampView()
end
function R:recordPitch(pitch)
    if not S.integer(pitch,0,127)then return end
    self.recordPitchLow=math.min(self.recordPitchLow or pitch,pitch);self.recordPitchHigh=math.max(self.recordPitchHigh or pitch,pitch)
    if self.follow and not self.drag then self:centerPitchRange(self.recordPitchLow,self.recordPitchHigh)end
end
function R:clampView()
    self.viewTicks=clamp(self.viewTicks,48,self:ticks())
    self.firstTick=clamp(self.firstTick,0,math.max(0,self:ticks()-self.viewTicks))
    self.pitchScroll=clamp(self.pitchScroll,0,math.max(0,#self.pitches-self.rows));self.topNote=self.pitches[math.floor(self.pitchScroll)+1] or 127
end
function R:fitNotes(wholeSong)
    if self.drag then return end
    local lo,hi,first,last=127,0,self:ticks(),0
    for _,n in ipairs(self.notes)do lo=math.min(lo,n.n);hi=math.max(hi,n.n);first=math.min(first,n.t);last=math.max(last,n.t+n.d)end
    if wholeSong or #self.notes==0 then self.firstTick=0;self.viewTicks=self:ticks()
    else self.firstTick=math.floor(first/384)*384;self.viewTicks=math.max(384,math.ceil(last/384)*384-self.firstTick)end
    if #self.notes>0 then
        if not self.fold then
            local top,bottom=self.pitchIndex[hi],self.pitchIndex[lo]
            if not top or not bottom then
                top,bottom=#self.pitches-1,0;local found=false
                for _,n in ipairs(self.notes)do local row=self.pitchIndex[n.n];if row then found=true;top=math.min(top,row);bottom=math.max(bottom,row)end end
                if not found then top,bottom=0,#self.pitches-1 end
            end
            self.rowH=clamp(math.floor(self.availableGridH/(bottom-top+5)),10,28);self:layout();self.pitchScroll=clamp(top-2,0,127)
        else self.pitchScroll=0 end
    end
    self:clampView()
end
function R:zoom(factor,x)
    local anchor=clamp((x or (self.gridX+self.gridW/2))-self.gridX,0,self.gridW)/self.gridW
    local tick=self.firstTick+anchor*self.viewTicks
    self.viewTicks=clamp(self.viewTicks*factor,48,self:ticks());self.firstTick=tick-anchor*self.viewTicks;self:clampView()
end
function R:zoomPitch(factor,y)
    local row=((y or (self.gridY+self.gridH/2))-self.gridY)/self.rowH+self.pitchScroll
    self.rowH=clamp(round(self.rowH*factor),10,32);self:layout()
    self.pitchScroll=row-((y or (self.gridY+self.gridH/2))-self.gridY)/self.rowH;self:clampView()
end
function R:pitchAt(y)
    local row=clamp(math.floor((y-self.gridY)/self.rowH+self.pitchScroll),0,#self.pitches-1)
    return self.pitches[row+1]
end
function R:tickAt(x)return self.firstTick+(x-self.gridX)/self.gridW*self.viewTicks end
function R:point(x,y,outside)
    if not outside and (x<self.gridX or x>=self.gridX+self.gridW or y<self.gridY or y>=self.gridY+self.gridH)then return nil end
    local tick=clamp(self:tickAt(x),0,self:ticks()-1)
    return math.floor(tick/self:step())*self:step(),self:pitchAt(y)
end
function R:noteRect(n)
    local row=self.pitchIndex[n.n];if not row then return nil end
    return self.gridX+(n.t-self.firstTick)/self.viewTicks*self.gridW,self.gridY+(row-self.pitchScroll)*self.rowH,n.d/self.viewTicks*self.gridW,self.rowH
end
function R:hit(x,y)
    if not self:point(x,y)then return nil end
    local pitch=self:pitchAt(y)
    for i=#self.notes,1,-1 do local n=self.notes[i]
        if self:noteEditable(n)and n.n==pitch then local nx,ny,w=self:noteRect(n)
            if x>=math.max(self.gridX,nx) and x<math.min(self.gridX+self.gridW,nx+math.max(3,w)) then
                local edge=clamp(w*.22,1,6)
                local side=(x>=nx+w-edge and nx+w<=self.gridX+self.gridW) and "right" or (x<nx+edge and nx>=self.gridX and w>=18) and "left" or nil
                return i,n,side
            end
        end
    end
end
function R:noteLength()
    local choice=self.length.selected
    if choice==1 then return self:step()elseif choice==2 then return self.lastLength or self:step()end
    return S.step(({32,16,8,4,2,1})[choice-2],self.triplet)
end
function R:inputVelocity()return clamp(tonumber(self.velocity:getText()) or 100,1,127)end
function R:addNote(t,pitch,length)
    if self:noteRoom()<1 then self.message="Note capacity reached. Start another sheet or remove notes.";return nil end
    for _,n in ipairs(self.notes)do if n.n==pitch and n.t==t then return nil end end
    local n={n=pitch,t=t,d=math.min(length,self:ticks()-t),v=round(self:inputVelocity())}
    self.notes[#self.notes+1]=n;self.selected[n]=true;self:audition(pitch,n.v);return n
end
function R:eraseAt(t,pitch)
    for i=#self.notes,1,-1 do local n=self.notes[i];if self:noteEditable(n)and n.n==pitch and t>=n.t and t<n.t+n.d then self.selected[n]=nil;table.remove(self.notes,i)end end
end
function R:paintTo(t,pitch)
    local d=self.drag;local step=self:step();local start=d.lastPaint or t;local dir=t<start and -step or step
    local count=math.abs(t-start)/step
    for i=0,count do
        local at=clamp(start+i*dir,0,self:ticks()-1);at=math.floor(at/step)*step
        local pn=round((d.lastPitch or pitch)+(pitch-(d.lastPitch or pitch))*(count==0 and 1 or i/count))
        if self.fold or (self.scaleEnabled and self.scaleOnly)then
            local a,b=self.pitchIndex[d.lastPitch or pitch],self.pitchIndex[pitch]
            pn=self.pitches[round(a+(b-a)*(count==0 and 1 or i/count))+1]
        end
        local key=at..":"..pn
        if not d.visited[key] then
            d.visited[key]=true
            if d.kind=="erase"then self:eraseAt(at,pn)else self:addNote(at,pn,self:noteLength())end
        end
    end
    d.lastPaint=t;d.lastPitch=pitch
end
function R:deleteSelected()
    if not self:editable()then return end
    local before=S.encode(self.notes)
    for i=#self.notes,1,-1 do if self.selected[self.notes[i]]then table.remove(self.notes,i)end end
    self.selected={};self:commit(before)
end
function R:selectAll()self.selected={};for _,n in ipairs(self.notes)do if self.pitchIndex[n.n]then self.selected[n]=true end end end
function R:copySelection(cut)
    if self:selectedCount()==0 then return end
    local notes={};local start=self:ticks()
    for _,n in ipairs(self.notes)do if self.selected[n]then notes[#notes+1]=S.copy(n);start=math.min(start,n.t)end end
    for _,n in ipairs(notes)do n.t=n.t-start end
    DeadAirRoll.clipboard=notes
    if cut then self:deleteSelected()end
end
function R:paste(duplicate)
    if not self:editable()then return end
    local notes=DeadAirRoll.clipboard;local at=self.cursorTick or math.floor(self.firstTick/self:step())*self:step()
    if duplicate then
        notes={};local start,finish=self:ticks(),0
        for _,n in ipairs(self.notes)do if self.selected[n]then notes[#notes+1]=S.copy(n);start=math.min(start,n.t);finish=math.max(finish,n.t+n.d)end end
        if #notes==0 then return end
        for _,n in ipairs(notes)do n.t=n.t-start end
        at=math.ceil(finish/self:step())*self:step()
    end
    if not notes or #notes==0 then return end
    if #notes>self:noteRoom() then self.message="Not enough room on this sheet for those notes.";return end
    local endTick=0;for _,n in ipairs(notes)do endTick=math.max(endTick,at+n.t+n.d)end
    local lo,hi=self:editBounds();if at<lo or (not self.editWholeTrack and endTick>hi)then self.message="That paste crosses this clip boundary. Extend or Unroll the clip first.";return end
    if endTick>self:ticks()and not self:extendTo(endTick)then return end
    local before=S.encode(self.notes);self.selected={}
    for _,n in ipairs(notes)do local copy=S.copy(n);copy.t=copy.t+at;self.notes[#self.notes+1]=copy;self.selected[copy]=true end
    self.cursorTick=endTick;self:commit(before)
end
function R:nudge(dt,dn)
    if not self:editable() or self:selectedCount()==0 then return end
    local minT,maxT,minN,maxN=self:ticks(),0,127,0
    for _,n in ipairs(self.notes)do if self.selected[n]then minT=math.min(minT,n.t);maxT=math.max(maxT,n.t+n.d);minN=math.min(minN,n.n);maxN=math.max(maxN,n.n)end end
    local lo,hi=self:editBounds();dt=clamp(dt,lo-minT,hi-maxT);dn=clamp(dn,-minN,127-maxN)
    local rowDelta
    if math.abs(dn)==1 and (self.fold or (self.scaleEnabled and self.scaleOnly))then
        local low,high=1-#self.pitches,#self.pitches-1
        for _,n in ipairs(self.notes)do if self.selected[n] and self.pitchIndex[n.n]then local row=self.pitchIndex[n.n];low=math.max(low,-row);high=math.min(high,#self.pitches-1-row)end end
        rowDelta=clamp(-dn,low,high)
    end
    local before=S.encode(self.notes)
    for _,n in ipairs(self.notes)do if self.selected[n]then n.t=n.t+dt;n.n=rowDelta and self.pitchIndex[n.n] and self.pitches[self.pitchIndex[n.n]+rowDelta+1] or n.n+dn end end
    self:commit(before)
end
function R:quantize()
    if not self:editable() or not self:settings()then return end
    local before=S.encode(self.notes);local count=self:selectedCount()
    for _,n in ipairs(self.notes)do if count==0 or self.selected[n]then local q=S.quantize({n},self:step(),self:ticks())[1];n.t=q.t;n.d=q.d end end
    self:commit(before);self.message=count>0 and "Quantized the selected notes." or "Quantized all notes."
end
function R:setVelocity()
    if not self:editable()then return end
    local before=S.encode(self.notes);for _,n in ipairs(self.notes)do if self.selected[n]then n.v=round(self:inputVelocity())end end;self:commit(before)
end
function R:blurFields()for _,field in ipairs(self.textFields)do field:unfocus()end end
function R:textFocused()for _,field in ipairs(self.textFields)do if field:isFocused()then return true end end;return false end
function R:beginDrag(kind,x,y)
    self.drag={kind=kind,x=x,y=y,before=S.encode(self.notes),first=self.firstTick,view=self.viewTicks,pitch=self.pitchScroll,rowH=self.rowH,visited={}}
    self:setCapture(true);return self.drag
end
function R:finishDrag(cancel)
    local d=self.drag;if not d then return end
    if self:arrFinish(cancel)then return end
    self.drag=nil;self:setCapture(false)
    if cancel then self.notes=S.decode(d.before,S.MAX_BARS*384);self.selected={};self:rebuildPitches()
    elseif d.edit then self:commit(d.before)end
end
function R:onMouseDown(x,y)
    self:bringToTop();self:blurFields()
    if self:arrMouseDown(x,y)then return true end
    if self.help then return true end
    if x>=self.width-18 and y>=self.height-18 then local d=self:beginDrag("resizeWindow",x,y);d.width=self.width;d.height=self.height;return true end
    if y<self.titleH then local d=self:beginDrag("window",x,y);d.px=self.x;d.py=self.y;return true end
    if y>=self.overviewY and y<self.overviewY+self.overviewH and x>=self.gridX and x<self.gridX+self.gridW then
        local d=self:beginDrag("overview",x,y);local t=(x-self.gridX)/self.gridW*self:ticks()
        d.offset=(t>=self.firstTick and t<=self.firstTick+self.viewTicks) and t-self.firstTick or self.viewTicks/2
        self.firstTick=t-d.offset;self:clampView();return true
    end
    if y>=self.rulerY and y<self.gridY and x>=self.gridX then self:beginDrag("ruler",x,y);return true end
    if x>=10 and x<self.gridX and y>=self.gridY and y<self.gridY+self.gridH then
        self:audition(self:pitchAt(y),self:inputVelocity());self:beginDrag("keys",x,y);return true
    end
    if self.showVelocity and y>=self.velocityY and y<self.velocityY+self.velocityH and x>=self.gridX and x<self.gridX+self.gridW then
        if not self:editable()then return true end
        local best,dist
        for _,n in ipairs(self.notes)do local nx=self.gridX+(n.t-self.firstTick)/self.viewTicks*self.gridW;local dx=math.abs(nx-x)
            if self:noteEditable(n)and dx<=8 and (not dist or dx<dist)then best=n;dist=dx end
        end
        if best then if not self.selected[best]then self.selected={[best]=true}end;local d=self:beginDrag("velocityLane",x,y);d.edit=true;self:updateDrag(x,y)end
        return true
    end
    local t,pitch=self:point(x,y);if not t then return true end
    self.cursorTick=t
    if alt() and not self:hit(x,y)then self:beginDrag("pan",x,y);return true end
    if not self:editable() or not self:settings()then return true end
    local _,n,edge=self:hit(x,y)
    if n then
        if shift()then self.selected[n]=not self.selected[n];return true end
        if not self.selected[n]then self.selected={[n]=true}end
        local d=self:beginDrag(alt() and "velocity" or edge and (edge=="right" and "end" or "start") or "move",x,y)
        d.edit=true;d.original={};d.copy=ctrl() and d.kind=="move";d.anchorPitch=n.n;d.anchorRow=self.pitchIndex[n.n]
        for _,note in ipairs(self.notes)do if self.selected[note]then d.original[#d.original+1]={note=note,old=S.copy(note)}end end
        self:audition(n.n,n.v);return true
    end
    if self.mode=="draw" then
        if self.gridW/self.viewTicks*self:step()<3 then self.message="Zoom in to draw accurately (Ctrl + wheel or +).";return true end
        self.selected={};local d=self:beginDrag(n and "erase" or "paint",x,y);d.edit=true;self:paintTo(t,pitch)
    else
        local previous={};if shift()then for note,v in pairs(self.selected)do previous[note]=v end end
        if not shift()then self.selected={}end
        local d=self:beginDrag("marquee",x,y);d.previous=previous;d.toX=x;d.toY=y
    end
    return true
end
function R:updateDrag(x,y)
    local d=self.drag;if not d then return end
    if self:arrDrag(x,y)then return end
    local dx,dy=x-d.x,y-d.y
    if d.kind=="window"then
        self:setX(clamp(self.x+(x-d.x),0,math.max(0,getCore():getScreenWidth()-self.width)))
        self:setY(clamp(self.y+(y-d.y),0,math.max(0,getCore():getScreenHeight()-self.titleH)));return
    elseif d.kind=="resizeWindow"then
        self.maximized=false;local sw,sh=getCore():getScreenWidth(),getCore():getScreenHeight()
        local minW,minH=math.min(820,sw-20),math.min(500,sh-20)
        self:setX(math.min(self.x,sw-minW-8));self:setY(math.min(self.y,sh-minH-8))
        self:setWidth(clamp(d.width+dx,minW,sw-self.x-8));self:setHeight(clamp(d.height+dy,minH,sh-self.y-8));self:layout();return
    elseif d.kind=="overview"then self.firstTick=(x-self.gridX)/self.gridW*self:ticks()-d.offset;self:clampView();return
    elseif d.kind=="pan"then self.firstTick=d.first-dx/self.gridW*d.view;self.pitchScroll=d.pitch-dy/self.rowH;self:clampView();return
    elseif d.kind=="keys"then self.rowH=clamp(round(d.rowH*2^(dx/150)),10,32);self:layout();self.pitchScroll=d.pitch-dy/self.rowH;self:clampView();return
    elseif d.kind=="ruler"then
        self.viewTicks=clamp(d.view*2^(dy/120),48,self:ticks());self.firstTick=d.first+(d.x-self.gridX)/self.gridW*d.view-(x-self.gridX)/self.gridW*self.viewTicks;self:clampView();return
    elseif d.kind=="marquee"then
        d.toX=clamp(x,self.gridX,self.gridX+self.gridW);d.toY=clamp(y,self.gridY,self.gridY+self.gridH)
        self.selected={};for note,v in pairs(d.previous)do self.selected[note]=v end
        local left,right=math.min(d.x,d.toX),math.max(d.x,d.toX);local top,bottom=math.min(d.y,d.toY),math.max(d.y,d.toY)
        for _,n in ipairs(self.notes)do local nx,ny,w,h=self:noteRect(n)
            if nx and nx<right and nx+w>left and ny<bottom and ny+h>top then self.selected[n]=true end
        end;return
    elseif d.kind=="velocityLane"then
        local v=clamp(round(127*(1-(y-self.velocityY)/self.velocityH)),1,127)
        for _,n in ipairs(self.notes)do if self.selected[n]then n.v=v end end;self.velocity:setText(tostring(v));return
    end
    if d.kind=="paint" or d.kind=="erase"then local t,pitch=self:point(x,y,true);self:paintTo(t,pitch);return end
    if not d.moved and math.abs(dx)+math.abs(dy)<4 then return end
    if not d.moved then
        d.moved=true
        if d.copy then
            if #d.original>self:noteRoom() then self.message="Not enough room to duplicate this selection.";self:finishDrag(true);return end
            self.selected={};for _,pair in ipairs(d.original)do local n=S.copy(pair.old);self.notes[#self.notes+1]=n;pair.note=n;self.selected[n]=true end
        end
    end
    local step=(alt() and d.kind~="velocity") and 1 or self:step()
    local dt=round(dx/self.gridW*self.viewTicks/step)*step
    local dn=-round(dy/self.rowH)
    if (self.fold or (self.scaleEnabled and self.scaleOnly)) and d.kind=="move"then dn=self.pitches[clamp(d.anchorRow-dn+1,1,#self.pitches)]-d.anchorPitch end
    local lo,hi=self:editBounds();local minT,maxT,minN,maxN,minD=self:ticks(),0,127,0,self:ticks()
    for _,p in ipairs(d.original)do local n=p.old;minT=math.min(minT,n.t);maxT=math.max(maxT,n.t+n.d);minN=math.min(minN,n.n);maxN=math.max(maxN,n.n);minD=math.min(minD,n.d)end
    if d.kind=="move"then local lo,hi=self:editBounds();dt=clamp(dt,lo-minT,hi-maxT);dn=clamp(dn,-minN,127-maxN)
    elseif d.kind=="end"then dt=clamp(dt,1-minD,hi-maxT)
    elseif d.kind=="start"then dt=clamp(dt,lo-minT,minD-1)end
    local rowDelta
    if d.kind=="move" and (self.fold or (self.scaleEnabled and self.scaleOnly))then
        rowDelta=round(dy/self.rowH);local low,high=1-#self.pitches,#self.pitches-1
        for _,p in ipairs(d.original)do local row=self.pitchIndex[p.old.n];if row then low=math.max(low,-row);high=math.min(high,#self.pitches-1-row)end end
        rowDelta=clamp(rowDelta,low,high)
    end
    for _,p in ipairs(d.original)do local n,old=p.note,p.old
        if d.kind=="move"then n.t=old.t+dt;n.n=rowDelta and self.pitchIndex[old.n] and self.pitches[self.pitchIndex[old.n]+rowDelta+1] or old.n+dn
        elseif d.kind=="end"then n.d=old.d+dt;self.lastLength=n.d
        elseif d.kind=="start"then n.t=old.t+dt;n.d=old.d-dt;self.lastLength=n.d
        elseif d.kind=="velocity"then n.v=clamp(old.v-round(dy),1,127);self.velocity:setText(tostring(n.v))end
    end
    if d.kind=="move" and dn~=d.lastDn then d.lastDn=dn;local n=d.original[1].note;self:audition(n.n,n.v)end
end
function R:onMouseMove(dx,dy)
    self.hoverX=self:getMouseX();self.hoverY=self:getMouseY()
    if self.drag then self:updateDrag(self.hoverX,self.hoverY)end
    return true
end
function R:onMouseMoveOutside(dx,dy)return self:onMouseMove(dx,dy)end
function R:onMouseUp(x,y)self:finishDrag(false);return true end
function R:onMouseUpOutside(x,y)return self:onMouseUp(x,y)end
function R:onRightMouseDown(x,y)
    if self.help then return true end
    local t,pitch=self:point(x,y);if not t or not self:editable()then return true end
    self:blurFields();self.selected={};local d=self:beginDrag("erase",x,y);d.edit=true;self:paintTo(t,pitch);return true
end
function R:onRightMouseUp(x,y)self:finishDrag(false);return true end
function R:onRightMouseUpOutside(x,y)return self:onRightMouseUp(x,y)end
function R:onMouseDoubleClick(x,y)
    if self.mode~="select" or not self:editable()then return true end
    self:finishDrag(false);local t,pitch=self:point(x,y)
    if t and not self:hit(x,y)then local before=S.encode(self.notes);self.selected={};self:addNote(t,pitch,self:noteLength());self:commit(before)end
    return true
end
function R:onMouseWheel(delta)
    if self.drag then return true end
    if self:arrWheel(delta)then return true end
    if ctrl() and shift()then self:zoomPitch(delta<0 and 1.2 or 1/1.2,self:getMouseY())
    elseif ctrl()then self:zoom(delta<0 and .8 or 1.25,self:getMouseX())
    elseif shift()then self.firstTick=self.firstTick+delta*self.viewTicks/8;self:clampView()
    else self.pitchScroll=self.pitchScroll+delta*3;self:clampView()end
    return true
end
function R:keyHandled(key)
    for _,name in ipairs({"B","SPACE","DELETE","BACK","ESCAPE","LEFT","RIGHT","UP","DOWN","ADD","SUBTRACT","EQUALS","MINUS","F","T"})do if key==Keyboard["KEY_"..name]then return true end end
    if ctrl()then for _,name in ipairs({"A","C","X","V","D","Z","Y","S","U"})do if key==Keyboard["KEY_"..name]then return true end end end
    return false
end
function R:isKeyConsumed(key)return self:isVisible() and not self:textFocused() and not getCore():isDoingTextEntry() and self:keyHandled(key)end
function R:onKeyPress(key)
    if not self:isKeyConsumed(key)then return end
    if key==Keyboard.KEY_ESCAPE and self.libraryPanel and self.libraryPanel.dragging then self.libraryPanel:cancelDrag();return end
    if key==Keyboard.KEY_ESCAPE then if self.help then self.help=false elseif self.drag then self:finishDrag(true)else self.selected={}end;return end
    if self.help then return end
    if self.drag then return end
    if ctrl()then
        if key==Keyboard.KEY_A then self:selectAll()
        elseif key==Keyboard.KEY_C then self:copySelection(false)
        elseif key==Keyboard.KEY_X then self:copySelection(true)
        elseif key==Keyboard.KEY_V then self:paste(false)
        elseif key==Keyboard.KEY_D then self:paste(true)
        elseif key==Keyboard.KEY_Z then self:undo(shift())
        elseif key==Keyboard.KEY_Y then self:undo(true)
        elseif key==Keyboard.KEY_S then self:save()
        elseif key==Keyboard.KEY_U then self:quantize()end
        return
    end
    if key==Keyboard.KEY_B then self.mode=self.mode=="draw" and "select" or "draw"
    elseif key==Keyboard.KEY_SPACE then if self.transport or self.pending then self:stop()else self:preview(false)end
    elseif key==Keyboard.KEY_DELETE or key==Keyboard.KEY_BACK then self:deleteSelected()
    elseif key==Keyboard.KEY_LEFT then self:nudge(-self:step(),0)
    elseif key==Keyboard.KEY_RIGHT then self:nudge(self:step(),0)
    elseif key==Keyboard.KEY_UP then self:nudge(0,shift() and 12 or 1)
    elseif key==Keyboard.KEY_DOWN then self:nudge(0,shift() and -12 or -1)
    elseif key==Keyboard.KEY_ADD or key==Keyboard.KEY_EQUALS then self:zoom(.5)
    elseif key==Keyboard.KEY_SUBTRACT or key==Keyboard.KEY_MINUS then self:zoom(2)
    elseif key==Keyboard.KEY_F then self:fitNotes(shift())
    elseif key==Keyboard.KEY_T then self.triplet=not self.triplet end
end
