require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISComboBox"
require "ISUI/ISTextEntryBox"
require "DeadAirScore"
require "DeadAirPatterns"
require "DeadAirComposition"
DeadAirLibrary={}
DeadAirLibraryPanel=ISPanel:derive("DeadAirLibraryPanel")
local L,B,S,C=DeadAirLibrary,DeadAirLibraryPanel,DeadAirScore,DeadAirComposition
local function clamp(v,a,b)return math.max(a,math.min(b,v))end
local function short(text,width)
    text=tostring(text or "");local tm=getTextManager();if tm:MeasureStringX(UIFont.Small,text)<=width then return text end
    while #text>0 and tm:MeasureStringX(UIFont.Small,text.."...")>width do text=text:sub(1,-2)end;return text.."..."
end
local function place(c,x,y,w,h)c:setX(x);c:setY(y);c:setWidth(w);c:setHeight(h)end
local function button(self,title,fn,tip)
    local b=ISButton:new(0,0,70,self.h,title,self,fn);b:initialise();if tip then b:setTooltip(tip)end;self:addChild(b);return b
end
local function choice(self,values,selected,fn)
    local c=ISComboBox:new(0,0,100,self.h,self,nil);c:initialise();for _,v in ipairs(values)do c:addOption(v)end;c.selected=selected or 1;c:setOnChange(self,fn or function()end);self:addChild(c);return c
end
local function entry(self,text,max)
    local e=ISTextEntryBox:new(text,0,0,100,self.h);e:initialise();e:instantiate();e.javaObject:setMaxTextLength(max);self:addChild(e);self.editor.textFields[#self.editor.textFields+1]=e;return e
end
function B:new(editor)
    local o=ISPanel.new(self,0,0,340,600);o.editor=editor;o.h=editor.controlH;o.fontH=editor.fontH;o.rows={};o.offset=0;o.scroll=0;o.total=0;o.layer=false
    o.backgroundColor={r=.09,g=.10,b=.08,a=1};o.borderColor={r=.34,g=.36,b=.28,a=1};return o
end
function B:initialise()
    ISPanel.initialise(self)
    self.hide=button(self,"Hide",function(p)p.editor:toggleLibrary()end)
    self.source=choice(self,{"Built-in / Chords","Built-in / Progressions","Built-in / Drum patterns","Local / All folders"},1,function(p)p.offset=0;p:refreshRows()end)
    self.search=entry(self,"",100);self.previous=button(self,"<",function(p)p.offset=math.max(0,p.offset-60);p:refreshRows()end)
    self.search:setPlaceholderText("Search names / folders")
    self.next=button(self,">",function(p)if p.offset+60<p.total then p.offset=p.offset+60;p:refreshRows()end end)
    self.refresh=button(self,"Refresh",function(p)if DeadAir.api()and DeadAirMidi.libraryRefresh then DeadAirMidi.libraryRefresh()else p.editor.message="Restart and approve DeadAir.jar 0.9.0 for local MIDI files."end end)
    self.folders=button(self,"Folders",function(p)p.showFolders=not p.showFolders;p:layout()end,"Add a local MIDI folder, or open one .mid file by path. Your packs stay outside the mod.")
    self.path=entry(self,"",1024)
    self.path:setPlaceholderText("Paste a folder or .mid path")
    self.addFolder=button(self,"Add folder",function(p)if p.path:getText()~=""and DeadAir.api()and DeadAirMidi.libraryAddFolder then DeadAirMidi.libraryAddFolder(p.path:getText())end end)
    self.openFile=button(self,"Open MIDI",function(p)if not DeadAir.api()or not DeadAirMidi.libraryOpenPath then p.editor.message="Restart and approve the updated Java mod.";return end;if p.editor.transport=="library"or p.editor.pending=="library"then p.editor:stop()end;p:cancelDrag();p.error=nil;p.request=DeadAirMidi.libraryOpenPath(p.path:getText());p.requestAt=getTimestampMs();p.raw=nil;p.selectedRow=nil;p.group.selected=1;p:pollResult()end)
    local keys={};for _,n in ipairs({"C","C#","D","D#","E","F","F#","G","G#","A","A#","B"})do keys[#keys+1]="Key "..n end
    self.root=choice(self,keys,self.editor.rootNote.selected,function(p)p:regenerate()end)
    self.octave=choice(self,{"Oct 2","Oct 3","Oct 4","Oct 5"},2,function(p)p:regenerate()end)
    self.duration=choice(self,{"1 beat","2 beats","1 bar","2 bars"},3,function(p)p:regenerate()end)
    self.group=choice(self,{"All MIDI parts"},1,function(p)p:remap()end)
    self.mapNames={"Auto mapping","Keep pitches","GM drum kit","Live Session Drums","Kick","Snare","Clap","Closed hat","Open hat","Pedal hat","Tom","Crash","Ride","Tambourine","Cowbell","Claves"}
    self.mapValues={"auto","keep","gm","livesd","kick","snare","clap","closed hat","open hat","pedal hat","tom","crash","ride","tambourine","cowbell","claves"}
    self.mapping=choice(self,self.mapNames,1,function(p)p:remap()end)
    self.shift=entry(self,"0",4);self.stretch=choice(self,{"Time 1/2x","Time 1x","Time 2x","Time 4x"},2)
    self.tempo=button(self,"Use BPM",function(p)local c=p.raw;if c and S.integer(math.floor(c.bpm+.5),30,300)and p.editor:editable()then p.editor.bpmEntry:setText(tostring(math.floor(c.bpm+.5)));p.editor:settings()end end,"Use this file's first tempo for the entire song. Import otherwise follows the song tempo.")
    self.preview=button(self,"Preview",function(p)if p.editor.transport=="library"or p.editor.pending=="library"then p.editor:stop()else local c=p:clip();if c then p.editor:previewLibrary(c)end end end)
    self.insert=button(self,"Insert",function(p)p:insertAt({part=p.editor.activePart,at=p.editor.cursorTick or 0,zone="roll"})end)
    self.newTrack=button(self,"New track",function(p)p:insertAt({new=true,at=p.editor.cursorTick or 0,zone="roll"})end)
    self.layerButton=button(self,"Layer: OFF",function(p)p.layer=not p.layer end,"Arrangement only: Off needs free space; On combines overlapping clips. Piano-roll drops always add notes to the current clip.")
    self:layout();self:refreshRows()
    if DeadAir.api()and DeadAirMidi.libraryRefresh then DeadAirMidi.libraryRefresh()end
end
function B:layout()
    local w,h,g=self.width,self.h,5;local y=8+h+g
    place(self.hide,w-64,6,56,h)
    place(self.source,10,y,w-20,h);y=y+h+g
    place(self.search,10,y,w-20,h);self.searchY=y;y=y+h+g
    local tm=getTextManager();local fw=math.max(77,tm:MeasureStringX(UIFont.Small,"Folders")+18);local rw=math.max(80,tm:MeasureStringX(UIFont.Small,"Refresh")+18)
    place(self.previous,10,y,30,h);place(self.next,44,y,30,h);place(self.refresh,w-15-fw-rw,y,rw,h);place(self.folders,w-10-fw,y,fw,h);y=y+h+g
    for _,c in ipairs({self.path,self.addFolder,self.openFile})do c:setVisible(self.showFolders==true)end
    if self.showFolders then place(self.path,10,y,w-20,h);y=y+h+g;place(self.addFolder,10,y,(w-25)/2,h);place(self.openFile,15+(w-25)/2,y,(w-25)/2,h);y=y+h+g end
    self.listY=y;self.rowH=self.fontH*2+9
    self.bottomY=self.height-(6*h+6*g+3*self.fontH+10)
    self.listH=math.max(self.rowH,self.bottomY-self.listY-6);self.visibleRows=math.max(1,math.floor(self.listH/self.rowH))
    y=self.bottomY+3*self.fontH+5
    local builtin=self.source.selected<=3 and not self.request
    self.root:setVisible(builtin);self.octave:setVisible(builtin);self.duration:setVisible(builtin)
    local third=(w-30)/3
    place(self.root,10,y,third,h);place(self.octave,15+third,y,third,h);place(self.duration,20+2*third,y,third,h)
    self.group:setVisible(not builtin);place(self.group,10,y,w-20,h);y=y+h+g
    self.mapping:setVisible(not builtin);place(self.mapping,10,y,w-20,h)
    self.layerButton:setVisible(builtin);place(self.layerButton,10,y,w-20,h);y=y+h+g
    self.shiftLabelY=y;place(self.shift,58,y,45,h);place(self.stretch,108,y,w-118,h);y=y+h+g
    place(self.preview,10,y,(w-30)/3,h);place(self.insert,15+(w-30)/3,y,(w-30)/3,h);place(self.newTrack,20+2*(w-30)/3,y,(w-30)/3,h);y=y+h+g
    self.tempo:setVisible(not builtin);place(self.tempo,10,y,90,h)
    if not builtin then self.layerButton:setVisible(true);place(self.layerButton,105,y,w-115,h)end
    self.hintY=y+h+3;self.scroll=clamp(self.scroll,0,math.max(0,#self.rows-self.visibleRows))
end
function B:cancelDrag()self.dragging=nil;self.queued=nil;self.editor.libraryGhost=nil;self:setCapture(false)end
function B:refreshRows()
    if self.editor.transport=="library"or self.editor.pending=="library"then self.editor:stop()end
    self:cancelDrag();self.raw=nil;self.request=nil;self.error=nil;self.selectedRow=nil;self.scroll=0
    local selected=self.source.selected;local query=self.search:getText();self.query=query
    if selected<=3 then self.rows=DeadAirPatterns.rows(selected,query);self.total=#self.rows;self.offset=0
    elseif DeadAir.api()and DeadAirMidi.librarySearch then local r=DeadAirMidi.librarySearch(query,selected-4,self.offset);self.rows=r.rows or {};self.total=r.count or 0
    else self.rows={};self.total=0;self.editor.message="Built-in patterns work now. Restart and approve DeadAir.jar 0.9.0 to load local files."end
    self:layout()
end
function B:regenerate()
    local row=self.selectedRow and self.rows[self.selectedRow];if not row or not row.builtin then return end
    self.raw=DeadAirPatterns.make(row.builtin,row.index,self.root.selected-1,self.octave.selected+1,({1,2,4,8})[self.duration.selected]);self.raw.bpm=self.editor.score.bpm
    if self.editor.transport=="library"or self.editor.pending=="library"then self.editor:stop()end
end
function B:selectRow(index)
    local row=self.rows[index];if not row then return end
    if self.editor.transport=="library"or self.editor.pending=="library"then self.editor:stop()end
    self.selectedRow=index;self.raw=nil;self.error=nil;self.request=nil;self.queued=nil;self.group:clear();self.group:addOption("All MIDI parts");self.group.selected=1
    if row.builtin then self:regenerate()
    elseif DeadAir.api()and DeadAirMidi.libraryRequest then self.request=DeadAirMidi.libraryRequest(row.id);self.requestAt=getTimestampMs();self:pollResult()end
    self:layout()
end
function B:remap()
    if self.editor.transport=="library"or self.editor.pending=="library"then self.editor:stop()end
    self.error=nil;self:pollResult()
end
function B:pollResult()
    if not self.request or not DeadAir.api()or not DeadAirMidi.libraryResult then return end
    local result=DeadAirMidi.libraryResult(self.request,self.group.selected-2,self.mapValues[self.mapping.selected]);local groups=result.clip and result.clip.groups or result.groups
    if groups and #self.group.options~=#groups+1 then
        local selected=self.group.selected;self.group:clear();self.group:addOption("All MIDI parts");for _,name in ipairs(groups)do self.group:addOption(name)end;self.group.selected=math.min(selected,#self.group.options)
    end
    if result.state=="ready"then self.raw=result.clip;self.error=nil
        if self.queued then local drop=self.queued;self.queued=nil;self:insertAt(drop)end
    elseif result.state=="error"or result.state=="stale"then self.raw=nil;self.error=result.message or "Choose the clip again after Refresh.";self.editor.message=self.error;self.queued=nil
    elseif getTimestampMs()-(self.requestAt or 0)>15000 then self.error="MIDI loading timed out. Choose the clip again.";self.request=nil;self.queued=nil end
end
function B:poll()
    local now=getTimestampMs();local query=self.search:getText()
    if query~=self.lastSearch then self.lastSearch=query;self.searchAt=now end
    if query~=self.query and now-(self.searchAt or now)>220 then self.offset=0;self:refreshRows()end
    if now>=(self.pollAt or 0)then
        self.pollAt=now+150
        if self.request and not self.raw and not self.error then self:pollResult()end
        if DeadAir.api()and DeadAirMidi.libraryState then local state=DeadAirMidi.libraryState();self.status=state.status
            if self.revision~=state.revision then
                self.revision=state.revision;local selected=self.source.selected;self.source:clear()
                for _,name in ipairs({"Built-in / Chords","Built-in / Progressions","Built-in / Drum patterns","Local / All folders"})do self.source:addOption(name)end
                for _,name in ipairs(state.roots or {})do self.source:addOption(name)end;self.source.selected=math.min(selected,#self.source.options)
                if selected>3 then self.offset=0;self:refreshRows()end
            end
        end
    end
end
function B:clip()
    if not self.raw then self.editor.message=self.error or "Choose a clip and wait for it to load.";return nil end
    local shift=tonumber(self.shift:getText());if not S.integer(shift,-48,48)then self.editor.message="Transpose must be -48 to +48 semitones.";return nil end
    if self.raw.drums then shift=0 end
    local factor=({.5,1,2,4})[self.stretch.selected];local out=S.copy(self.raw);out.notes={};out.length=math.ceil(out.length*factor);if out.rootPitch then out.rootPitch=out.rootPitch+shift end
    for _,n in ipairs(self.raw.notes)do
        local pitch=n.n+shift;if pitch<0 or pitch>127 then self.editor.message="That transpose would put notes outside MIDI range.";return nil end
        local t=math.floor(n.t*factor+.5);local finish=math.max(t+1,math.floor((n.t+n.d)*factor+.5));out.notes[#out.notes+1]={n=pitch,t=t,d=finish-t,v=n.v};out.length=math.max(out.length,finish)
    end;return out
end
function B:dropAt(x,y)
    local e=self.editor
    if x>=e.trackW and x<e.trackW+e.arrW and not e.arrHidden and y>=e.arrY+e.arrRulerH and y<e.arrY+e.arrH then
        local index=math.floor((y-e.arrY-e.arrRulerH)/e.trackH)+1+(e.trackScroll or 0)
        if e.song.parts[index]then return {part=index,at=math.max(0,math.floor((e.arrFirst+(x-e.trackW)/e.arrW*e.arrTicks)/e:arrStep())*e:arrStep()),zone="arrangement"}end
    end
    if x>=e.gridX and x<e.gridX+e.gridW and y>=e.gridY and y<e.gridY+e.gridH then local t,pitch=e:point(x,y);return {part=e.activePart,at=t,pitch=not isAltKeyDown()and pitch or nil,zone="roll"}end
end
function B:insertAt(drop)
    if self.request and not self.raw and not self.error then self.queued=drop;self.editor.message="Loading the dropped MIDI clip...";return end
    local clip=self:clip();if clip then self.editor:insertLibraryClip(clip,drop,self.layer)end
end
function B:onMouseDown(x,y)
    if y>=self.listY and y<self.listY+self.listH and x>=10 and x<self.width-10 then
        local index=math.floor((y-self.listY)/self.rowH)+1+self.scroll
        if self.rows[index]then self:selectRow(index);self.dragging={x=x,y=y};self:setCapture(true)end
    end;return true
end
function B:onMouseMove(dx,dy)
    local d=self.dragging;if not d then return true end
    local x,y=self:getMouseX(),self:getMouseY();if math.abs(x-d.x)+math.abs(y-d.y)>5 then d.moved=true end
    if d.moved then local drop=self:dropAt(self.x+x,self.y+y);self.editor.libraryGhost=drop and {drop=drop,name=self.raw and self.raw.name or "MIDI clip",length=self.raw and self.raw.length or 384,clip=self:clip()}or nil end
    return true
end
function B:onMouseMoveOutside(dx,dy)return self:onMouseMove(dx,dy)end
function B:onMouseUp(x,y)
    local d=self.dragging;self.dragging=nil;self:setCapture(false);self.editor.libraryGhost=nil
    if d and d.moved then local drop=self:dropAt(self.x+x,self.y+y);if drop then self:insertAt(drop)end end;return true
end
function B:onMouseUpOutside(x,y)return self:onMouseUp(x,y)end
function B:onMouseDoubleClick(x,y)
    self:cancelDrag();if x>=10 and x<self.width-10 and y>=self.listY and y<self.listY+self.listH then self:insertAt({part=self.editor.activePart,at=self.editor.cursorTick or 0,zone="roll"})end;return true
end
function B:onMouseWheel(delta)self.scroll=clamp(self.scroll+delta*3,0,math.max(0,#self.rows-self.visibleRows));return true end
function B:prerender()
    ISPanel.prerender(self);self.layerButton:setTitle(self.layer and "Layer: ON"or "Layer: OFF");self.preview:setTitle((self.editor.transport=="library"or self.editor.pending=="library")and "Stop"or "Preview")
    self:drawText("CLIP LIBRARY",12,10,.80,.84,.68,1,UIFont.Small)
    if self.search:getText()==""then self:drawText("Search names / folders",18,self.searchY+4,.48,.51,.43,1,UIFont.Small)end
    self:drawRect(10,self.listY,self.width-20,self.listH,1,.055,.06,.05)
    self:setStencilRect(10,self.listY,self.width-20,self.listH)
    for row=1,self.visibleRows do local index=row+self.scroll;local entry=self.rows[index];if entry then local y=self.listY+(row-1)*self.rowH
        if index==self.selectedRow then self:drawRect(10,y,self.width-20,self.rowH,1,.26,.30,.19)end
        self:drawText(short(entry.name,self.width-32),16,y+3,.83,.85,.73,1,UIFont.Small)
        self:drawText(short(entry.path,self.width-32),16,y+4+self.fontH,.52,.56,.47,1,UIFont.Small)
    end end;self:clearStencilRect()
    if #self.rows==0 then self:drawText(short(self.source.selected<=3 and "No matching patterns"or "Refresh or add a MIDI folder",self.width-30),16,self.listY+10,.67,.69,.58,1,UIFont.Small)end
    local c=self.raw;self:drawText(short(c and c.name or self.error or "Select, preview, then drag into the song.",self.width-20),10,self.bottomY,.83,.84,.69,1,UIFont.Small)
    local info=c and (#c.notes.." notes / "..string.format("%.2g",c.length/384).." bars / "..math.floor(c.bpm+.5).." BPM")or (self.total.." matches / "..(self.offset+1).."-"..math.min(self.total,self.offset+#self.rows))
    self:drawText(short(info,self.width-20),10,self.bottomY+self.fontH+2,.65,.69,.57,1,UIFont.Small)
    self:drawText(short(c and c.warning~=""and c.warning or self.status or "Original built-in musical patterns",self.width-20),10,self.bottomY+2*self.fontH+4,.81,.69,.45,1,UIFont.Small)
    self:drawText("Shift",10,self.shiftLabelY+4,.67,.71,.59,1,UIFont.Small)
    self:drawText(short("Roll: root at mouse / Alt: keep pitches",self.width-20),10,self.hintY,.60,.66,.54,1,UIFont.Small)
end
function L:toggleLibrary()
    if not self.libraryPanel then self.libraryPanel=B:new(self);self.libraryPanel:initialise();self:addChild(self.libraryPanel)end
    self.libraryOpen=not self.libraryOpen;self.libraryPanel:setVisible(self.libraryOpen)
    if self.libraryOpen then self.details=false end
    if not self.libraryOpen then self:blurFields();self.libraryPanel:cancelDrag();if self.transport=="library"or self.pending=="library"then self:stop()end end
    self:layout()
end
function L:updateLibrary()if self.libraryOpen and self.libraryPanel then self.libraryPanel:poll()end end
function L:previewLibrary(clip)
    if not self:editable()or not self:settings()then return end
    if not DeadAir.api()or not DeadAirMidi.scoreLoad then self.message="Restart and approve the Java mod for audio preview.";return end
    if DeadAir.Songs.net or DeadAir.Songs.lobby then self.message="Leave the ensemble before auditioning clips.";return end
    self:stopAudition();DeadAir.stop();self.pending="library";self.pendingAt=getTimestampMs();self.pendingClip=clip
    self.pendingParts={{profile=clip.drums and 9 or self.instrument.selected-1,notes=clip.notes}};DeadAirMidi.openAudio();self.message="Preparing private clip preview..."
end
function L:drawLibraryDrop()
    local ghost=self.libraryGhost;if not ghost then return end;local d=ghost.drop
    if d.zone=="roll"and ghost.clip then
        local notes=self:dropNotes(ghost.clip,d)
        self:setStencilRect(self.gridX,self.gridY,self.gridW,self.gridH)
        for _,n in ipairs(notes or {})do local x,y,w,h=DeadAirRoll.noteRect(self,n);if x then
            self:drawRect(x,y+1,math.max(3,w-1),h-2,.48,.85,.86,.48);self:drawRectBorder(x,y+1,math.max(3,w-1),h-2,.9,.95,.94,.64)
        end end
        self:clearStencilRect();return
    end
    if not self.arrHidden then local row=d.part-(self.trackScroll or 0);if row>=1 and row<=self.trackRows then
        local x=self.trackW+(d.at-self.arrFirst)/self.arrTicks*self.arrW;local y=self.arrY+self.arrRulerH+(row-1)*self.trackH
        self:setStencilRect(self.trackW,y,self.arrW,self.trackH);self:drawRect(x,y+3,ghost.length/self.arrTicks*self.arrW,self.trackH-6,.42,.70,.75,.40)
        self:drawText(short(ghost.name,200),x+5,y+6,.95,.94,.77,1,UIFont.Small);self:clearStencilRect()
    end end
end
