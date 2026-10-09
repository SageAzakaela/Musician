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
        for i=1,48 do local line=file:readLine();if not line then break end;local key,value=line:match("^(%a+)=(%-?[%d%.]+)$");if key then data[key]=tonumber(value)end end;file:close()
    end)
    if data.version~=1 and data.version~=2 then return end
    if data.arrangementHeight then self.arrangementHeight=clamp(data.arrangementHeight,42,8192)end
    if data.version==2 then
        if data.autoFit==1 then self.arrangementHeight=nil end
        self.compactControls=data.compact~=0;self.notesOnly=data.notesOnly==1;self.showVelocity=data.velocity==1
        self.showOverview=data.overview~=0;self.showHints=data.hints==1;self.inspectorAdvanced=data.advanced==1
        self.themeIndex=math.floor(clamp(data.theme or 1,1,4));self.trackDensity=math.floor(clamp(data.tracks or 1,1,3))
        self.sidebarWidth=clamp(data.sidebar or 280,240,440);self.velocityHeight=clamp(data.velocityHeight or 64,44,360)
        self.accentColor=data.accent and data.accent>=0 and math.floor(clamp(data.accent,0,16777215))or nil
    end
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
    local data={version=2,arrangementHeight=self.arrangementHeight,autoFit=self.arrangementHeight and 0 or 1,inspector=self.inspectorOpen and 1 or 0,
        arrGrid=self.arrGrid.selected,noteGrid=self.grid.selected,arrAdaptive=self.arrAdaptive and 1 or 0,noteAdaptive=self.noteAdaptive and 1 or 0,
        maximized=self.maximized and 1 or 0,width=self.width,height=self.height,compact=self.compactControls and 1 or 0,
        notesOnly=self.notesOnly and 1 or 0,velocity=self.showVelocity and 1 or 0,overview=self.showOverview and 1 or 0,hints=self.showHints and 1 or 0,
        advanced=self.inspectorAdvanced and 1 or 0,theme=self.themeIndex or 1,accent=self.accentColor or -1,tracks=self.trackDensity or 1,
        sidebar=self.sidebarWidth or 280,velocityHeight=self.velocityHeight or 64}
    pcall(function()local file=getFileWriter("MusicianEditorLayout.ini",true,false);if not file then return end
        for key,value in pairs(data)do file:write(key.."="..math.floor(value).."\n")end;file:close()
    end)
end
function X:close()self:writeLayout();P.close(self)end
function X:toggleClipTiming()
    self.inspectorOpen=self.viewSettings or not self.inspectorOpen;self.viewSettings=false;self.details=false;self.clipTiming=self.inspectorOpen
    if self.inspectorOpen and self.libraryOpen then L.toggleLibrary(self)end
    self:refreshClipTiming(true);self:layout()
end
function X:toggleLibrary()
    self.viewSettings=false
    if not self.libraryOpen then self.inspectorOpen=false;self.details=false end
    L.toggleLibrary(self);self:layout()
end
function X:viewChanged()
    local center=self.pitchScroll+self.rows/2
    self:layout();self.pitchScroll=center-self.rows/2;self:clampView();self:writeLayout()
end
function X:fitTracks()
    self.arrangementHeight=nil;self.notesOnly=false;self:viewChanged()
end
function X:toggleViewSettings()
    self.viewSettings=not self.viewSettings;self.inspectorOpen=self.viewSettings;self.details=false
    if self.libraryOpen then L.toggleLibrary(self)end
    self.inspectorScroll=0;self:viewChanged()
end
function X:applyViewPreset(index)
    self.arrangementHeight=nil;self.notesOnly=index==2;self.showVelocity=index==2
    if index==3 then self.arrangementHeight=math.floor(self.height*.40)end
    self.showOverview=true;self.showHints=false;self.compactControls=true
    self:viewChanged()
end
function X:resetView()
    self.arrangementHeight=nil;self.notesOnly=false;self.showVelocity=false;self.showOverview=true;self.showHints=false
    self.compactControls=true;self.trackDensity=1;self.sidebarWidth=280;self.velocityHeight=64;self.inspectorAdvanced=false
    self.themeIndex=1;self.accentColor=nil;self.inspectorScroll=0;self:rebuildTheme();self:viewChanged()
end
function X:noteMenu()
    local menu=ISContextMenu.get(0,(self.getAbsoluteX and self:getAbsoluteX()or self.x)+self.moreButton.x,(self.getAbsoluteY and self:getAbsoluteY()or self.y)+self.moreButton.y+self.controlH)
    local function action(label,fn)menu:addOption(label,self,fn)end
    local function activate(p,c)(c.onclick or c.callback)(p,c)end
    action("Fit notes   F",function(p)p:fitNotes(false)end)
    action("Fit clip",function(p)activate(p,p.loopFitButton)end)
    action(self.editWholeTrack and "Edit selected clip"or "Edit whole track",function(p)p:toggleEditScope()end)
    action("Zoom in",function(p)p:zoom(.5)end);action("Zoom out",function(p)p:zoom(2)end)
    action(self.noteAdaptive and "Use fixed note grid"or "Use adaptive note grid",function(p)p.noteAdaptive=not p.noteAdaptive;p:writeLayout()end)
    action(self.arrAdaptive and "Use fixed clip grid"or "Use adaptive clip grid",function(p)p.arrAdaptive=not p.arrAdaptive;p:writeLayout()end)
    action(self.fold and "Show all pitches"or "Fold to used pitches",function(p)activate(p,p.foldButton)end)
    action(self.follow and "Stop following playhead"or "Follow playhead",function(p)p.follow=not p.follow end)
    action(self.hear and "Turn note audition off"or "Hear notes while editing",function(p)activate(p,p.auditionButton)end)
    self.noteActionsMenu=menu
end
function X:buildControls()
    V.buildControls(self)
    self.compactControls=true;self.showOverview=true;self.showHints=false;self.trackDensity=1;self.sidebarWidth=280;self.velocityHeight=64;self.themeIndex=1
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
    self.fitTracksButton=button(self,"Fit tracks",function(p)p:fitTracks()end,"Automatically fit the arrangement height to its tracks. Drag its divider for a manual height.")
    self.viewFitButton=button(self,"Fit tracks",function(p)p:fitTracks()end)
    self.viewButton=button(self,"View",function(p)p:toggleViewSettings()end,"Customize layout, panels, theme and colors. Settings are saved on this computer.")
    self.moreButton=button(self,"More",function(p)p:noteMenu()end,"Fit, zoom, clip/track scope, snapping, fold, audition and follow.")
    self.advancedButton=button(self,"Advanced",function(p)p.inspectorAdvanced=not p.inspectorAdvanced;p:layout();p:writeLayout()end,"Extra clip operations and note-view settings.")
    self.editInspectorButton=button(self,"Edit",function(p)p.details=false;p.viewSettings=false;p.inspectorScroll=0;p:layout()end,"Inspector follows the selected notes, clip or track.")
    self.presetChoice=combo(self,{"Balanced","Notes focus","Arrangement focus"});self.presetChoice:setOnChange(self,function(p,c)p:applyViewPreset(c.selected)end)
    self.densityChoice=combo(self,{"Compact controls","Comfortable controls"});self.densityChoice:setOnChange(self,function(p,c)p.compactControls=c.selected==1;p:viewChanged()end)
    self.trackChoice=combo(self,{"Compact tracks","Standard tracks","Spacious tracks"});self.trackChoice:setOnChange(self,function(p,c)p.trackDensity=c.selected;p:viewChanged()end)
    local themes={};for _,t in ipairs(DeadAirAppearance.themes)do themes[#themes+1]=t.name end
    self.themeChoice=combo(self,themes);self.themeChoice:setOnChange(self,function(p,c)p:chooseTheme(c.selected)end)
    local accents={};for _,t in ipairs(DeadAirAppearance.accents)do accents[#accents+1]=t[1]end
    self.accentChoice=combo(self,accents);self.accentChoice:setOnChange(self,function(p,c)p:chooseAccent(c.selected)end)
    self.accentEntry=entry(self);self.accentEntry:setTooltip("Custom accent: six hexadecimal color digits, such as #B09BDD.")
    self.accentApply=button(self,"Apply",function(p)p:applyAccent()end)
    self.resetViewButton=button(self,"Reset view",function(p)p:resetView()end,"Reset layout and colors. Keeps the song, notes and audio settings.")
    self.panelButtons={}
    for _,spec in ipairs({{"Tracks","notesOnly",true},{"Velocity","showVelocity"},{"Overview","showOverview"},{"Hints","showHints"}})do
        local key,inverse=spec[2],spec[3];local b=button(self,spec[1],function(p)p[key]=not p[key];p:viewChanged()end)
        self.panelButtons[#self.panelButtons+1]={button=b,key=key,inverse=inverse,label=spec[1]}
    end
    local toolbar={}
    for _,c in ipairs(self.toolbar)do if c~=self.detailsButton and c~=self.soundfontsButton and c~=self.focusButton then toolbar[#toolbar+1]=c end end
    table.insert(toolbar,2,self.inspectorButton);table.insert(toolbar,3,self.viewButton);self.toolbar=toolbar
    self.arrControls={self.arrControls[1],self.arrAdd,self.arrControls[3],self.clipMenuButton,self.arrGrid,self.fitTracksButton}
    self.partControls={self.partPicker,self.scopeButton,self.loopFitButton,self.focusButton}
    self.partPicker.rollWidth=260;self.focusButton.rollWidth=measure("Show tracks")+24
    table.insert(self.tools,3,self.noteSnapButton)
    self.compactTools={self.modeButton,self.grid,self.tripletButton}
    for _,c in ipairs(self.tools)do if c.title=="Quantize"then self.compactTools[#self.compactTools+1]=c end end
    for _,c in ipairs({self.scaleButton,self.velButton,self.moreButton})do self.compactTools[#self.compactTools+1]=c end
    self.detailsButton.onclick=function(p)p.details=not p.details;p.viewSettings=false;p.inspectorOpen=true;p.libraryOpen=false;p.inspectorScroll=0;if p.libraryPanel then p.libraryPanel:setVisible(false)end;p:layout()end
    self.detailsButton.callback=self.detailsButton.onclick
    self.clipTimingFields={}
    self.workflowReady=true;self.inspectorOpen=false;self:readLayout();self:refreshClipTiming(true);self:rebuildTheme();self:layout()
    if #self.notes==0 then self:centerPitchRange(60,60)else self:fitNotes(false)end
    self:styleControls()
end
function X:layout(compact,arrangementLimit)
    if not self.workflowReady then return V.layout(self,compact)end
    self.controlH=math.max(self.compactControls and 22 or 26,self.fontH+(self.compactControls and 6 or 10))
    self.titleH=self.controlH+8
    local h,gap=self.controlH,self.compactControls and 3 or 5;local y=self.titleH;local limit=self.width
    for _,c in pairs(self.children)do c:setVisible(false)end
    local function flow(controls,startX)
        local x=startX or 12
        for _,c in ipairs(controls)do local w=math.min(c.rollWidth,limit-24)
            if x+w>limit-12 and x>12 then x=12;y=y+h+gap end
            if c==self.bpmEntry then self.bpmLabelX=x;self.bpmLabelY=y;place(c,x+38,y,w-38,h)else place(c,x,y,w,h)end;x=x+w+gap
        end;y=y+h+gap
    end
    flow(self.toolbar);self.sideY=y
    local sidebar=self.libraryOpen and math.max(320,math.min(410,self.width*.28))or self.inspectorOpen and clamp(self.sidebarWidth or 280,240,math.max(240,math.min(440,self.width-500)))or 0
    self.bodyW=self.width-(sidebar>0 and sidebar+8 or 0);limit=self.bodyW;self.inspectorX=self.bodyW+8;self.inspectorW=sidebar-12
    if self.libraryOpen and self.libraryPanel then place(self.libraryPanel,self.bodyW+4,y,sidebar-4,self.height-y-10);self.libraryPanel:layout()end
    self.arrHidden=self.notesOnly or compact==true;self.arrHeaderY=y
    if not self.arrHidden then flow(self.arrControls)end
    self.arrY=y;self.arrRulerH=self.fontH+8;self.trackH=math.max(38,self.fontH*2+8)+((self.trackDensity or 1)-1)*12
    self.trackW=math.max(200,math.min(280,self.bodyW*.24));self.arrW=self.bodyW-self.trackW-16
    -- Size the viewport in pixels, independently of the number of tracks.
    -- Only complete rows receive input; spare space remains available for tracks.
    local wanted=self.arrangementHeight or #self.song.parts*self.trackH
    self.arrContentH=self.arrHidden and 0 or clamp(wanted,self.trackH,arrangementLimit or math.max(self.trackH,self.height))
    self.trackRows=self.arrHidden and 0 or math.max(1,math.min(#self.song.parts,math.floor(self.arrContentH/self.trackH)))
    self.arrH=self.arrHidden and 0 or self.arrRulerH+self.arrContentH
    self.trackScroll=clamp(self.trackScroll or 0,0,math.max(0,#self.song.parts-self.trackRows))
    y=y+self.arrH;self.dividerY=y;self.dividerH=math.max(18,self.fontH+6);y=y+(self.arrHidden and 4 or self.dividerH)
    self.partLabelY=y
    local noteTools={};if self.arrHidden then noteTools[#noteTools+1]=self.partPicker end
    for _,c in ipairs(self.compactTools)do noteTools[#noteTools+1]=c end;flow(noteTools)
    if self.scaleEnabled then flow(self.scaleControls)end
    self.gridX=math.max(60,measure("C#-1")+20);self.gridW=self.bodyW-self.gridX-16
    self.loopY=y+2;self.loopH=self.fontH+8;self.rulerY=self.loopY+self.loopH;self.gridY=self.rulerY+self.fontH+10
    self.overviewH=self.showOverview and 18 or 0
    local footerH=(self.showHints and 3 or 2)*(self.fontH+2)+12
    self.overviewY=self.height-footerH-self.overviewH
    self.velocityMaxHeight=math.max(44,self.overviewY-self.gridY-110-(self.arrHidden and 0 or self.arrContentH-self.trackH))
    self.velocityH=clamp(self.velocityHeight or 64,44,self.velocityMaxHeight);self.velocityY=self.overviewY-self.velocityH-6
    self.velocityDividerY=self.velocityY-10
    self.availableGridH=(self.showVelocity and self.velocityDividerY or self.overviewY)-self.gridY-6
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
    self.inspectorLabels={};self.clipTiming=self.inspectorOpen and not self.libraryOpen
    self.inspectorContext=self.editContext=="notes"and "notes"or self.editContext=="track"and "track"or "clip"
    if self.inspectorOpen and not self.libraryOpen then
        local x,w=self.inspectorX,self.inspectorW;local sy=self.sideY+self.fontH+10
        local before={};for _,c in pairs(self.children)do if c:isVisible()then before[c]=true end end
        local offset=self.inspectorScroll or 0;sy=sy-offset
        local function label(text,control,width)
            local line=""
            for word in text:gmatch("%S+")do
                local combined=line==""and word or line.." "..word
                if line~=""and measure(combined)>w then self.inspectorLabels[#self.inspectorLabels+1]={text=line,x=x,y=sy};sy=sy+self.fontH+2;line=word
                else line=combined end
            end
            self.inspectorLabels[#self.inspectorLabels+1]={text=line,x=x,y=sy};sy=sy+self.fontH+3;place(control,x,sy,width or w,h);sy=sy+h+gap
        end
        local function row(controls)
            local cw=(w-gap*(#controls-1))/#controls
            for _,c in ipairs(controls)do if measure(c.title or "")+14>cw then
                for _,item in ipairs(controls)do place(item,x,sy,w,h);sy=sy+h+gap end;return
            end end
            for i,c in ipairs(controls)do place(c,x+(i-1)*(cw+gap),sy,cw,h)end;sy=sy+h+gap
        end
        row({self.editInspectorButton,self.detailsButton,self.soundfontsButton})
        if self.viewSettings then
            for _,spec in ipairs(self.panelButtons)do local on=self[spec.key];if spec.inverse then on=not on end;spec.button:setTitle(spec.label..(on and ": ON"or ": OFF"))end
            label("Workspace preset",self.presetChoice)
            row({self.panelButtons[1].button,self.panelButtons[2].button});row({self.panelButtons[3].button,self.panelButtons[4].button})
            row({self.viewFitButton});label("Spacing",self.densityChoice);label("Track height",self.trackChoice)
            label("Theme",self.themeChoice);label("Accent color",self.accentChoice)
            label("Custom color (#RRGGBB)",self.accentEntry,w-self.accentApply.rollWidth-gap)
            place(self.accentApply,x+w-self.accentApply.rollWidth,sy-h-gap,self.accentApply.rollWidth,h)
            row({self.resetViewButton})
            self.inspectorLabels[#self.inspectorLabels+1]={text="Drag edge to resize.",x=x,y=sy};sy=sy+self.fontH+6
            self.densityChoice.selected=self.compactControls and 1 or 2;self.trackChoice.selected=self.trackDensity or 1
        elseif self.details then
            for _,f in ipairs(self.detailFields)do if f.control~=self.copyButton and f.control~=self.exportButton then label(f.label,f.control)end end
            row({self.copyButton,self.exportButton});row({self.foldButton,self.auditionButton});row({self.followButton,self.length})
        elseif self.inspectorContext=="notes"then
            label("Track instrument",self.instrument)
            row({self.monitorButton,self.auditionButton});label("New note length",self.length)
            label("Velocity (selected / new notes)",self.velocity,w-self.applyVelocity.rollWidth-gap)
            place(self.applyVelocity,x+w-self.applyVelocity.rollWidth,sy-h-gap,self.applyVelocity.rollWidth,h)
            row({self.advancedButton})
            if self.inspectorAdvanced then row({self.foldButton,self.followButton});row({self.scopeButton,self.loopFitButton})end
        elseif self.inspectorContext=="track"then
            label("Track name",self.partEntry);label("Instrument",self.instrument);row({self.monitorButton,self.soloButton});row({self.advancedButton})
            if self.inspectorAdvanced then row({self.deleteTrackButton});row({self.joinTrackButton});row({self.exportButton})end
        else
            label("Clip name",self.phraseEntry,w-self.renameButton.rollWidth-gap);place(self.renameButton,x+w-self.renameButton.rollWidth,sy-h-gap,self.renameButton.rollWidth,h)
            label("Track instrument",self.instrument);row({self.monitorButton,self.followButton})
            row({self.loopButton,self.unrollButton})
            local fields={{"Clip start",self.clipStartEntry},{"Clip bars",self.clipLengthEntry},{"Loop start",self.loopStartEntry},{"Loop bars",self.clipLoopEntry}}
            local half=(w-gap)/2
            for i=1,4,2 do
                for j=0,1 do local f=fields[i+j];self.inspectorLabels[#self.inspectorLabels+1]={text=f[1],x=x+j*(half+gap),y=sy};place(f[2],x+j*(half+gap),sy+self.fontH+3,half,h)end
                sy=sy+self.fontH+3+h+gap
            end
            row({self.clipApplyButton});row({self.advancedButton})
            if self.inspectorAdvanced then row(self.loopPresets);row({self.loopSelectionButton});row({self.splitButton,self.consolidateButton});row({self.uniqueButton});row({self.scopeButton,self.loopFitButton})end
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
    local context=self.editContext=="notes"and "notes"or self.editContext=="track"and "track"or "clip"
    if self.workflowReady and context~=self.inspectorContext and not self.drag and not self:textFocused()then self.inspectorScroll=0;self:layout()end
    V.prerender(self)
    self:styleControls()
    self.arrSnapButton:setTitle(self.arrAdaptive and "Auto "..self:snapLabel(self:arrStep())or "Fixed")
    self.noteSnapButton:setTitle(self.noteAdaptive and "Auto "..self:snapLabel(self:step())or "Fixed")
    self.inspectorButton:setTitle("Inspector")
    if not self.arrHidden then
        local active=self.drag and self.drag.kind=="divider"
        local hover=self:overArrangementDivider(self:getMouseX(),self:getMouseY())
        local label=active and "Resize tracks  |  Esc: cancel"or "Drag to resize tracks"
        local width=measure(label);local x=(self.bodyW-width)/2;local cy=self.dividerY+self.dividerH/2
        self:themeRect((active or hover)and "active"or "panel",12,self.dividerY,self.bodyW-28,self.dividerH)
        self:themeRect("accent",20,cy-1,math.max(0,x-32),2,.8)
        self:themeRect("accent",x+width+12,cy-1,math.max(0,self.bodyW-x-width-36),2,.8)
        self:themeText("muted",label,x,self.dividerY+(self.dividerH-self.fontH)/2)
    end
    if self.inspectorOpen and not self.libraryOpen then
        self:themeBorder("border",self.inspectorX-4,self.sideY-3,self.inspectorW+8,self.height-self.sideY-7)
        self:themeRect("border",self.bodyW,self.sideY,3,self.height-self.sideY-8)
        self:themeText("text",self.viewSettings and "CUSTOMIZE VIEW"or self.details and "SONG"or self.inspectorContext:upper().." INSPECTOR",self.inspectorX,self.sideY)
        self:setStencilRect(self.inspectorX,self.sideY+self.fontH+10,self.inspectorW,self.height-self.sideY-self.fontH-40)
        for _,f in ipairs(self.inspectorLabels)do self:themeText("muted",f.text,f.x,f.y)end
        self:clearStencilRect()
        if (self.inspectorMaxScroll or 0)>0 then self:drawText("Scroll here for more",self.inspectorX,self.height-25,.70,.73,.62,1,UIFont.Small)end
    end
    if self.showVelocity then
        local hover=self:getMouseY()>=self.velocityDividerY and self:getMouseY()<self.velocityY
        self:themeRect(hover and "active"or "panel",self.gridX,self.velocityDividerY,self.gridW,10)
        self:themeRect("accent",self.gridX+self.gridW/2-18,self.velocityDividerY+4,36,2)
    end
    local c=self:currentClip();if c then
        local x,y,w=self.gridX,self.loopY,self.gridW;local first=c.start+(c.loopStart or 0);local last=first+(c.loopLength or c.length)
        local a=x+(first-self.firstTick)/self.viewTicks*w;local b=x+(last-self.firstTick)/self.viewTicks*w
        self:themeRect("panel",x,y,w,self.loopH);self:setStencilRect(x,y,w,self.loopH)
        self:themeRect("active",a,y+4,b-a,self.loopH-8)
        self:themeRect("accent",a,y+3,6,self.loopH-6);self:themeRect("accent",b-6,y+3,6,self.loopH-6)
        local text=self.partEntry:getText().." / "..c.name.."   |   "..(c.loopLength and "Loop "or "Range ")..self:clipBars(last-first).." bars"
        if measure(text)<w-24 then self:themeText("text",text,x+10,y+3)end
        if self.timeSelection then local lo,hi=self.timeSelection[1],self.timeSelection[2];self:drawRect(x+(lo-self.firstTick)/self.viewTicks*w,y,(hi-lo)/self.viewTicks*w,self.loopH,.5,.65,.80,.85)end
        self:clearStencilRect()
        -- Generated notes are context only, never editable source events.
        self:setStencilRect(x,self.gridY,w,self.gridH)
        for _,n in ipairs(self.notes)do if n.t>=c.start and n.t<c.start+c.length and not self:noteEditable(n)then
            local nx,ny,nw,nh=DeadAirRoll.noteRect(self,n);if nx then self:themeRect("accent",nx,ny+1,nw,nh-2,.17)end
        end end;self:clearStencilRect()
    end
    if self.editContext=="notes"then self:themeBorder("accent",self.gridX,self.gridY,self.gridW,self.gridH)end
end
function X:onMouseDown(x,y)
    if not self.help then
        local kind
        if self.showVelocity and x>=self.gridX and x<=self.gridX+self.gridW and y>=self.velocityDividerY and y<self.velocityY then kind="velocitySize"
        elseif self.inspectorOpen and not self.libraryOpen and x>=self.bodyW-3 and x<self.inspectorX and y>=self.sideY then kind="sidebarSize"end
        if kind then
            self:blurFields();local d=self:beginDrag(kind,x,y);d.preference=kind=="velocitySize"and self.velocityHeight or self.sidebarWidth
            d.size=kind=="velocitySize"and self.velocityH or self.width-self.bodyW-8;d.pitchCenter=self.pitchScroll+self.rows/2;return true
        end
    end
    return DeadAirWorkflow.onMouseDown(self,x,y)
end
function X:arrDrag(x,y)
    local d=self.drag
    if d and (d.kind=="velocitySize"or d.kind=="sidebarSize")then
        if d.kind=="velocitySize"then self.velocityHeight=clamp(d.size+d.y-y,44,self.velocityMaxHeight)
        else self.sidebarWidth=clamp(d.size+d.x-x,240,math.max(240,math.min(440,self.width-500)))end
        self:layout();self.pitchScroll=d.pitchCenter-self.rows/2;self:clampView();return true
    end
    return DeadAirWorkflow.arrDrag(self,x,y)
end
function X:arrFinish(cancel)
    local d=self.drag
    if d and (d.kind=="velocitySize"or d.kind=="sidebarSize")then
        self.drag=nil;self:setCapture(false)
        if cancel then
            if d.kind=="velocitySize"then self.velocityHeight=d.preference else self.sidebarWidth=d.preference end
            self:layout();self.pitchScroll=d.pitch;self:clampView()
        else self:writeLayout()end
        return true
    end
    return DeadAirWorkflow.arrFinish(self,cancel)
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
        "View: layout presets, panels, themes and custom accent colors.",
        "Drag the inspector's left edge or velocity's top edge to resize.",
        "Fit tracks restores automatic height; View > Reset view resets colors too.",
        "More: fit/zoom, grid behavior, fold, audition and follow.",
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
