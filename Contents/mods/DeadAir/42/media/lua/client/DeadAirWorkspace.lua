-- Editor-only layout/preferences. Song data never contains window settings.
DeadAirWorkspace={}
local X,V,S,P,L=DeadAirWorkspace,DeadAirRollView,DeadAirScore,DeadAirSongParts,DeadAirLibrary
local function clamp(v,a,b)return math.max(a,math.min(b,v))end
local function measure(s)return getTextManager():MeasureStringX(UIFont.Small,s)end
local function place(c,x,y,w,h)c:setX(x);c:setY(y);c:setWidth(w);c:setHeight(h);c:setVisible(true)end
local function button(self,label,fn,tip)
    local b=ISButton:new(0,0,80,self.controlH,label,self,fn);b:initialise();self:addChild(b);b.rollWidth=measure(label)+22;b:setTooltip(tip or label);return b
end
local function entry(self)
    local e=ISTextEntryBox:new("",0,0,100,self.controlH);e:initialise();e:instantiate();e.javaObject:setMaxTextLength(16);self:addChild(e);self.textFields[#self.textFields+1]=e;return e
end
local function combo(self,values)
    local c=ISComboBox:new(0,0,140,self.controlH,self,nil);c:initialise();for _,v in ipairs(values)do c:addOption(v)end;c.selected=1;c.rollWidth=150;self:addChild(c);return c
end
function X:readLayout()
    if not getFileReader then return end
    local data={};pcall(function()
        local file=getFileReader("MusicianEditorLayout.ini",false);if not file then return end
        for i=1,24 do local line=file:readLine();if not line then break end;local key,value=line:match("^(%a+)=(%-?[%d%.]+)$");if key then data[key]=tonumber(value)end end;file:close()
    end)
    if data.version~=1 then return end
    if data.arrangementHeight then self.arrangementHeight=clamp(data.arrangementHeight,42,8192)end
    self.inspectorOpen=data.inspector==1;self.arrAdaptive=data.arrAdaptive==1;self.noteAdaptive=data.noteAdaptive==1
    if data.arrGrid then self.arrGrid.selected=math.floor(clamp(data.arrGrid,1,7))end
    if data.noteGrid then self.grid.selected=math.floor(clamp(data.noteGrid,1,7))end
    if data.maximized==0 and data.width and data.height then
        self.maximized=false;self:setWidth(clamp(data.width,820,getCore():getScreenWidth()-16));self:setHeight(clamp(data.height,500,getCore():getScreenHeight()-16))
        self:setX(math.max(0,(getCore():getScreenWidth()-self.width)/2));self:setY(math.max(0,(getCore():getScreenHeight()-self.height)/2))
    end
end
function X:writeLayout()
    if not getFileWriter then return end
    local data={version=1,arrangementHeight=self.arrangementHeight or self.trackH*math.min(3,#self.song.parts),inspector=self.inspectorOpen and 1 or 0,
        arrGrid=self.arrGrid.selected,noteGrid=self.grid.selected,arrAdaptive=self.arrAdaptive and 1 or 0,noteAdaptive=self.noteAdaptive and 1 or 0,
        maximized=self.maximized and 1 or 0,width=self.width,height=self.height}
    pcall(function()local file=getFileWriter("MusicianEditorLayout.ini",true,false);if not file then return end
        for key,value in pairs(data)do file:write(key.."="..math.floor(value).."\n")end;file:close()
    end)
end
function X:close()self:writeLayout();P.close(self)end
function X:toggleClipTiming()
    self.inspectorOpen=not self.inspectorOpen;self.details=false;self.clipTiming=self.inspectorOpen
    if self.inspectorOpen and self.libraryOpen then L.toggleLibrary(self)end
    self:refreshClipTiming(true);self:layout()
end
function X:toggleLibrary()
    if not self.libraryOpen then self.inspectorOpen=false;self.details=false end
    L.toggleLibrary(self);self:layout()
end
function X:buildControls()
    V.buildControls(self)
    self.grid:addOption("Notes off")
    for i=1,6 do self.grid.options[i]="Notes 1/"..self.denominators[i]end
    self.grid.rollWidth=measure("Notes 1/32")+34
    self.arrGrid=combo(self,{"Clips 1 bar","Clips 1/2","Clips 1/4","Clips 1/8","Clips 1/16","Clips 1/32","Clips off"})
    self.arrGrid:setToolTipMap({defaultTooltip="Independent arrangement snap. Hold Alt during a clip drag to bypass snapping."})
    self.arrSnapButton=button(self,"Fixed",function(p)p.arrAdaptive=not p.arrAdaptive end,"Fixed keeps the chosen interval. Adaptive widens it when zoomed out; the button shows the interval actually used.");self.arrSnapButton.rollWidth=120
    self.noteSnapButton=button(self,"Fixed",function(p)p.noteAdaptive=not p.noteAdaptive end,"Fixed/adaptive note grid. The button shows the actual adaptive interval. Choose Notes off for free timing.");self.noteSnapButton.rollWidth=120
    self.loopStartEntry=entry(self);self.loopStartEntry:setTooltip("Loop start in song bars. Notes before this point play once; this range repeats until the clip ends.")
    self.inspectorButton=self.clipTimingButton;self.inspectorButton:setTitle("Inspector");self.inspectorButton.rollWidth=measure("Inspector")+24
    self.splitButton=button(self,"Split",function(p)p:splitClip()end,"Ctrl+E: split the selected clip at the cursor, including sustained notes crossing it.")
    self.consolidateButton=button(self,"Consolidate",function(p)p:consolidateClips()end,"Ctrl+J: combine selected clips, preserving their notes and gaps. Ctrl/Shift-click clips to select several on one track.")
    self.uniqueButton=button(self,"Make unique",function(p)p:uniqueRepeat()end,"Right-click a loop repetition, then make only that repetition independently editable.")
    self.loopSelectionButton=button(self,"Loop selection",function(p)p:loopSelection()end,"Ctrl+L: loop selected notes or Shift-dragged time. Split off later source notes first if they extend beyond the new end.")
    self.loopPresets={};for _,bars in ipairs({1,2,4,8})do local value=bars;self.loopPresets[#self.loopPresets+1]=button(self,tostring(value).." bar",function(p)p:loopPreset(value)end,"Set the loop to "..value.." bars. Existing source notes are protected.")end
    self.clipMenuButton=button(self,"Clip actions",function(p)p:clipMenu(p.clipMenuButton.x,p.clipMenuButton.y+p.controlH)end,"Split, consolidate, variation, duplicate and delete. Also available by right-clicking a clip.")
    self.loopFitButton=button(self,"Fit clip",function(p)local c=p:currentClip();if c then p.firstTick=c.start;p.viewTicks=c.length;p:clampView()end end,"Show the whole selected clip, including dimmed generated repetitions.")
    local toolbar={}
    for _,c in ipairs(self.toolbar)do if c~=self.detailsButton and c~=self.soundfontsButton and c~=self.focusButton then toolbar[#toolbar+1]=c end end
    table.insert(toolbar,2,self.inspectorButton);self.toolbar=toolbar
    self.arrControls={self.arrControls[1],self.arrAdd,self.arrControls[3],self.clipMenuButton,self.arrGrid,self.arrSnapButton}
    self.partControls={self.partPicker,self.scopeButton,self.loopFitButton,self.focusButton}
    self.partPicker.rollWidth=260;self.focusButton.rollWidth=measure("Show tracks")+24
    table.insert(self.tools,3,self.noteSnapButton)
    self.detailsButton.onclick=function(p)p.details=not p.details;p.inspectorOpen=true;p.libraryOpen=false;if p.libraryPanel then p.libraryPanel:setVisible(false)end;p:layout()end
    self.detailsButton.callback=self.detailsButton.onclick
    self.clipTimingFields={}
    self.workflowReady=true;self.inspectorOpen=true;self:readLayout();self:refreshClipTiming(true);self:layout()
    if #self.notes==0 then self:centerPitchRange(60,60)else self:fitNotes(false)end
    for _,c in pairs(self.children)do if c.backgroundColor then c.backgroundColor={r=.12,g=.13,b=.11,a=1};c.borderColor={r=.35,g=.36,b=.31,a=1}end end
    self.recordButton.backgroundColor={r=.30,g=.15,b=.12,a=1}
end
function X:layout(compact,arrangementLimit)
    if not self.workflowReady then return V.layout(self,compact)end
    local h,gap=self.controlH,5;local y=self.titleH;local limit=self.width
    for _,c in pairs(self.children)do c:setVisible(false)end
    local function flow(controls,startX)
        local x=startX or 12
        for _,c in ipairs(controls)do local w=math.min(c.rollWidth,limit-24)
            if x+w>limit-12 and x>12 then x=12;y=y+h+gap end
            if c==self.bpmEntry then self.bpmLabelX=x;self.bpmLabelY=y;place(c,x+38,y,w-38,h)else place(c,x,y,w,h)end;x=x+w+gap
        end;y=y+h+gap
    end
    flow(self.toolbar);self.sideY=y
    local sidebar=self.libraryOpen and math.max(320,math.min(410,self.width*.28))or self.inspectorOpen and math.max(260,math.min(330,self.width*.26))or 0
    self.bodyW=self.width-(sidebar>0 and sidebar+8 or 0);limit=self.bodyW;self.inspectorX=self.bodyW+8;self.inspectorW=sidebar-12
    if self.libraryOpen and self.libraryPanel then place(self.libraryPanel,self.bodyW+4,y,sidebar-4,self.height-y-10);self.libraryPanel:layout()end
    self.arrHidden=self.notesOnly or compact==true;self.arrHeaderY=y
    if not self.arrHidden then y=y+self.fontH+6;flow(self.arrControls)end
    self.arrY=y;self.arrRulerH=self.fontH+10;self.trackH=math.max(42,self.fontH*2+12)
    self.trackW=math.max(200,math.min(280,self.bodyW*.24));self.arrW=self.bodyW-self.trackW-16
    -- Size the viewport in pixels, independently of the number of tracks.
    -- Only complete rows receive input; spare space remains available for tracks.
    local wanted=self.arrangementHeight or math.min(3,#self.song.parts)*self.trackH
    self.arrContentH=self.arrHidden and 0 or clamp(wanted,self.trackH,arrangementLimit or math.max(self.trackH,self.height))
    self.trackRows=self.arrHidden and 0 or math.max(1,math.min(#self.song.parts,math.floor(self.arrContentH/self.trackH)))
    self.arrH=self.arrHidden and 0 or self.arrRulerH+self.arrContentH
    self.trackScroll=clamp(self.trackScroll or 0,0,math.max(0,#self.song.parts-self.trackRows))
    y=y+self.arrH;self.dividerY=y;self.dividerH=math.max(18,self.fontH+6);y=y+(self.arrHidden and 4 or self.dividerH)
    self.partLabelY=y;y=y+self.fontH+6;flow(self.partControls);flow(self.tools)
    if self.scaleEnabled then flow(self.scaleControls)end
    self.gridX=math.max(60,measure("C#-1")+20);self.gridW=self.bodyW-self.gridX-16
    self.loopY=y+2;self.loopH=self.fontH+8;self.rulerY=self.loopY+self.loopH;self.gridY=self.rulerY+self.fontH+10
    self.overviewH=20;self.overviewY=self.height-3*self.fontH-36
    self.velocityH=math.max(64,2*self.fontH+h+10);self.velocityY=self.overviewY-self.velocityH-6
    self.availableGridH=(self.showVelocity and self.velocityY or self.overviewY)-self.gridY-6
    -- Reserve a usable piano roll after accounting for wrapped toolbars, scale
    -- controls and velocity. A smaller window clamps the view, not the saved size.
    self.arrangementMaxHeight=math.floor(self.arrContentH+self.availableGridH-100)
    if self.availableGridH<100 and not self.arrHidden then
        if self.arrangementMaxHeight>=self.trackH then self:layout(compact,self.arrangementMaxHeight)
        else self:layout(true)end
        return
    end
    self.availableGridH=math.max(32,self.availableGridH);self.rows=math.max(1,math.floor(self.availableGridH/self.rowH));self.gridH=self.rows*self.rowH;self:clampView()
    place(self.closeButton,self.width-self.closeButton.rollWidth-10,5,self.closeButton.rollWidth,h)
    place(self.maxButton,self.closeButton.x-self.maxButton.rollWidth-5,5,self.maxButton.rollWidth,h)
    if self.showVelocity then place(self.velocity,10,self.velocityY+self.fontH+1,44,h);place(self.applyVelocity,10,self.velocityY+self.fontH+h+3,44,math.max(18,self.fontH+2))end
    self.inspectorLabels={};self.clipTiming=self.inspectorOpen and not self.libraryOpen
    if self.inspectorOpen and not self.libraryOpen then
        local x,w=self.inspectorX,self.inspectorW;local sy=self.sideY+self.fontH+10
        local before={};for _,c in pairs(self.children)do if c:isVisible()then before[c]=true end end
        local offset=self.inspectorScroll or 0;sy=sy-offset
        local function label(text,control,width)
            self.inspectorLabels[#self.inspectorLabels+1]={text=text,x=x,y=sy};sy=sy+self.fontH+3;place(control,x,sy,width or w,h);sy=sy+h+gap
        end
        local function row(controls)
            local cw=(w-gap*(#controls-1))/#controls
            for i,c in ipairs(controls)do place(c,x+(i-1)*(cw+gap),sy,cw,h)end;sy=sy+h+gap
        end
        row({self.detailsButton,self.soundfontsButton})
        if self.details then
            for _,f in ipairs(self.detailFields)do if f.control~=self.copyButton and f.control~=self.exportButton then label(f.label,f.control)end end
            row({self.copyButton,self.exportButton});row({self.foldButton,self.auditionButton});row({self.followButton,self.length})
        else
            label("Clip name",self.phraseEntry,w-self.renameButton.rollWidth-gap);place(self.renameButton,x+w-self.renameButton.rollWidth,sy-h-gap,self.renameButton.rollWidth,h)
            label("Track instrument",self.instrument);row({self.monitorButton,self.followButton})
            row({self.loopButton,self.unrollButton});row(self.loopPresets);row({self.loopSelectionButton})
            local fields={{"Clip start",self.clipStartEntry},{"Clip bars",self.clipLengthEntry},{"Loop start",self.loopStartEntry},{"Loop bars",self.clipLoopEntry}}
            local half=(w-gap)/2
            for i=1,4,2 do
                for j=0,1 do local f=fields[i+j];self.inspectorLabels[#self.inspectorLabels+1]={text=f[1],x=x+j*(half+gap),y=sy};place(f[2],x+j*(half+gap),sy+self.fontH+3,half,h)end
                sy=sy+self.fontH+3+h+gap
            end
            row({self.clipApplyButton});row({self.splitButton,self.consolidateButton});row({self.uniqueButton});row({self.length,self.auditionButton})
        end
        self.inspectorMaxScroll=math.max(0,sy+offset-(self.height-30))
        if offset>self.inspectorMaxScroll then self.inspectorScroll=self.inspectorMaxScroll;self:layout(compact);return end
        for _,c in pairs(self.children)do if c:isVisible()and not before[c]then
            if c.y<self.sideY+self.fontH+10 or c.y+c.height>self.height-30 then c:setVisible(false)end
        end end
    end
    self.layoutW=self.width;self.layoutH=self.height
end
function X:prerender()
    V.prerender(self)
    self.arrSnapButton:setTitle(self.arrAdaptive and "Auto "..self:snapLabel(self:arrStep())or "Fixed")
    self.noteSnapButton:setTitle(self.noteAdaptive and "Auto "..self:snapLabel(self:step())or "Fixed")
    self.inspectorButton:setTitle("Inspector")
    if not self.arrHidden then
        local active=self.drag and self.drag.kind=="divider"
        local hover=self:overArrangementDivider(self:getMouseX(),self:getMouseY())
        local label=active and "Resize tracks  |  Esc: cancel"or "Drag to resize tracks"
        local width=measure(label);local x=(self.bodyW-width)/2;local cy=self.dividerY+self.dividerH/2
        self:drawRect(12,self.dividerY,self.bodyW-28,self.dividerH,1,(active or hover)and .25 or .16,(active or hover)and .28 or .18,.12)
        self:drawRect(20,cy-1,math.max(0,x-32),2,.8,.50,.54,.37)
        self:drawRect(x+width+12,cy-1,math.max(0,self.bodyW-x-width-36),2,.8,.50,.54,.37)
        self:drawText(label,x,self.dividerY+(self.dividerH-self.fontH)/2,.80,.83,.65,1,UIFont.Small)
    end
    if self.inspectorOpen and not self.libraryOpen then
        self:drawRectBorder(self.inspectorX-4,self.sideY-3,self.inspectorW+8,self.height-self.sideY-7,1,.31,.34,.26)
        self:drawText(self.details and "SONG / VIEW"or "CLIP INSPECTOR",self.inspectorX,self.sideY,.80,.82,.68,1,UIFont.Small)
        self:setStencilRect(self.inspectorX,self.sideY+self.fontH+10,self.inspectorW,self.height-self.sideY-self.fontH-40)
        for _,f in ipairs(self.inspectorLabels)do self:drawText(f.text,f.x,f.y,.70,.73,.62,1,UIFont.Small)end
        self:clearStencilRect()
        if (self.inspectorMaxScroll or 0)>0 then self:drawText("Scroll here for more",self.inspectorX,self.height-25,.70,.73,.62,1,UIFont.Small)end
    end
    local c=self:currentClip();if c then
        local x,y,w=self.gridX,self.loopY,self.gridW;local first=c.start+(c.loopStart or 0);local last=first+(c.loopLength or c.length)
        local a=x+(first-self.firstTick)/self.viewTicks*w;local b=x+(last-self.firstTick)/self.viewTicks*w
        self:drawRect(x,y,w,self.loopH,1,.12,.14,.10);self:setStencilRect(x,y,w,self.loopH)
        self:drawRect(a,y+4,b-a,self.loopH-8,.6,.39,.45,.28)
        self:drawRect(a,y+3,6,self.loopH-6,1,.84,.77,.47);self:drawRect(b-6,y+3,6,self.loopH-6,1,.84,.77,.47)
        local text=(c.loopLength and "LOOP "or "LOOP RANGE ")..self:clipBars(last-first).." bars"
        if measure(text)<b-a-22 then self:drawText(text,math.max(x+8,a+9),y+3,.86,.86,.70,1,UIFont.Small)end
        if self.timeSelection then local lo,hi=self.timeSelection[1],self.timeSelection[2];self:drawRect(x+(lo-self.firstTick)/self.viewTicks*w,y,(hi-lo)/self.viewTicks*w,self.loopH,.5,.65,.80,.85)end
        self:clearStencilRect()
        -- Generated notes are context only, never editable source events.
        self:setStencilRect(x,self.gridY,w,self.gridH)
        for _,n in ipairs(self.notes)do if n.t>=c.start and n.t<c.start+c.length and not self:noteEditable(n)then
            local nx,ny,nw,nh=DeadAirRoll.noteRect(self,n);if nx then self:drawRect(nx,ny+1,nw,nh-2,.17,.58,.64,.43)end
        end end;self:clearStencilRect()
    end
    if self.editContext=="notes"then self:drawRectBorder(self.gridX,self.gridY,self.gridW,self.gridH,1,.57,.63,.42)end
end
function X:overArrangementDivider(x,y)
    return not self.arrHidden and self.dividerY~=nil and x>=12 and x<=self.bodyW-16 and y>=self.dividerY and y<self.dividerY+self.dividerH
end
function X:onMouseWheel(delta)
    if self.help then self.helpScroll=clamp((self.helpScroll or 0)+delta*3,0,self.helpMaxScroll or 0);return true end
    if self.inspectorOpen and not self.libraryOpen and self:getMouseX()>=self.inspectorX then
        self.inspectorScroll=clamp((self.inspectorScroll or 0)+delta*(self.controlH+5),0,self.inspectorMaxScroll or 0);self:layout();return true
    end
    return DeadAirRoll.onMouseWheel(self,delta)
end
function X:render()
    if not self.help then return end
    local lines={
        "B: Draw / Select. Space: preview / stop.",
        "Draw in empty space; right-drag erases notes.",
        "Drag notes to move. Drag either edge to resize.",
        "Select mode: drag empty space to box-select.",
        "Shift-click adds/removes notes. Ctrl+A selects all.",
        "Ctrl-drag copies notes. Alt-drag changes velocity.",
        "Ctrl+C / X / V: copy / cut / paste at the last grid click.",
        "Arrows move notes; Shift+Up/Down moves an octave.",
        "Ctrl+U: quantize. T: straight / triplet grid.",
        "Notes and Clips have independent snap controls.",
        "Fixed uses your interval. Auto widens it as you zoom out.",
        "Alt bypasses snap when dragging clips or loop handles.",
        "Drag the loop brace ends. Inspector: exact bars, 1/2/4/8.",
        "Notes before the loop brace play once; the brace repeats.",
        "Shift-drag the brace strip selects time. Ctrl+L loops it.",
        "Ctrl+L also loops selected notes. Later source notes",
        "must be split off first; shortening never cuts them.",
        "Ctrl-click clips toggles selection; Shift-click selects a range.",
        "Drag selected clips together. Ctrl+D duplicates the group.",
        "Ctrl+E: split at cursor. Ctrl+J: consolidate selected clips.",
        "Right-click a repetition > Make unique to edit a variation.",
        "Split/consolidate keep notes, including gaps and held notes.",
        "Delete removes focused notes, clips or track. Ctrl+Z restores.",
        "Ctrl+Z: undo. Ctrl+Y / Ctrl+Shift+Z: redo. Ctrl+S: save.",
        "Wheel: pitches. Shift+wheel: time. Ctrl+wheel: time zoom.",
        "Ctrl+Shift+wheel: pitch zoom. F: fit notes. Shift+F: song.",
        "Drag ruler: pan time; up/down zooms. Drag keys: pitches.",
        "Fit clip shows dim repetitions; their source stays editable.",
        "Drag the divider between tracks and notes to resize.",
        "Inspector toggles the sidebar; scroll it for hidden controls.",
        "R arms a recording track. Recording ends at Stop.",
        "Drop chords in the roll: root follows pitch. Alt keeps pitch.",
        "Drag title to move window; bottom-right corner resizes."
    }
    local row=self.fontH+5;local width=0
    for _,line in ipairs(lines)do width=math.max(width,measure(line)+32)end;width=math.min(width,self.width-32)
    local visible=math.max(1,math.min(#lines,math.floor((self.height-self.titleH-90)/row)))
    self.helpMaxScroll=#lines-visible;self.helpScroll=clamp(self.helpScroll or 0,0,self.helpMaxScroll)
    local height=(visible+2)*row+22;local x=(self.width-width)/2;local y=(self.height-height)/2
    self:drawRect(x,y,width,height,.99,.07,.10,.075);self:drawRectBorder(x,y,width,height,1,.45,.5,.34)
    self:setStencilRect(x+8,y,width-16,height)
    self:drawText("MUSICIAN SHORTCUTS",x+15,y+10,.86,.88,.72,1,UIFont.Small)
    for i=1,visible do self:drawText(lines[self.helpScroll+i],x+15,y+10+i*row,.78,.85,.74,1,UIFont.Small)end
    self:drawText("Scroll for more   |   Escape closes help",x+15,y+10+(visible+1)*row,.9,.8,.46,1,UIFont.Small)
    self:clearStencilRect()
end
