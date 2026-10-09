require "DeadAirScore"
-- Font-aware layout and drawing for the paper editor.
DeadAirRollView={}
local V,S=DeadAirRollView,DeadAirScore
local function clamp(v,a,b)return math.max(a,math.min(b,v))end
local function measure(s)return getTextManager():MeasureStringX(UIFont.Small,tostring(s))end
local function short(s,w)
    s=tostring(s);if measure(s)<=w then return s end
    while #s>0 and measure(s.."...")>w do s=s:sub(1,-2)end
    return s.."..."
end
local function place(c,x,y,w,h)c:setX(x);c:setY(y);c:setWidth(w);c:setHeight(h)end
local function button(self,title,fn,tip)
    local b=ISButton:new(0,0,80,self.controlH,title,self,fn);b:initialise();self:addChild(b)
    b.rollWidth=measure(title)+24;if tip then b:setTooltip(tip)end;return b
end
local function combo(self,values,selected,width,tip)
    local b=ISComboBox:new(0,0,width,self.controlH,self,nil);b:initialise()
    for _,v in ipairs(values)do b:addOption(v)end;b.selected=selected or 1;self:addChild(b);b.rollWidth=width
    if tip then b:setToolTipMap({defaultTooltip=tip})end;return b
end
local function entry(self,text,max,width)
    local e=ISTextEntryBox:new(tostring(text),0,0,width,self.controlH);e:initialise();e:instantiate();e.javaObject:setMaxTextLength(max)
    self:addChild(e);e.rollWidth=width;self.textFields[#self.textFields+1]=e;return e
end
function V:buildControls()
    self.fontH=getTextManager():getFontHeight(UIFont.Small);self.controlH=math.max(26,self.fontH+10);self.titleH=self.controlH+10
    self.textFields={};self.toolbar={};self.tools={};self.detailFields={};self.partControls={}
    local function top(title,fn,tip)local b=button(self,title,fn,tip);self.toolbar[#self.toolbar+1]=b;return b end
    local function tool(title,fn,tip)local b=button(self,title,fn,tip);self.tools[#self.tools+1]=b;return b end
    local function choice(values,index,width,tip)local b=combo(self,values,index,width,tip);self.tools[#self.tools+1]=b;return b end
    self.libraryButton=top("Library",function(p)p:toggleLibrary()end,"Browse built-in chords, progressions and drum patterns, or your own MIDI folders. Drag a clip onto a track.")
    self.soundfontsButton=top("Sounds",function()MusicianSoundfonts.show()end,"Choose soundfont presets for each instrument. These are your local listening settings.")
    self.playButton=top("Play",function(p)if p.transport or p.pending then p:stop()else p:preview(false)end end,"Space: preview / stop")
    self.recordButton=top("Record",function(p)p:preview(true)end,"Record your MIDI keyboard after a one-bar count-in. Adds a take; does not erase notes.")
    self.previewScope=combo(self,{"This part","Whole song"},1,measure("Whole song")+34,"Play only the selected part, or all parts in this song. Preview is private and needs no equipped instrument.")
    self.previewScope.selected=2;self.previewScope:setVisible(false)
    top("Stop",function(p)p:stop();p.playFrom=0 end,"Stop; return the playhead to the beginning.")
    self.metroButton=top("Click: ON",function(p)p.metronome=not p.metronome;if DeadAir.api()then DeadAirMidi.scoreMetronome(p.metronome)end end,"Toggle the metronome for preview and recording.")
    top("Save song",function(p)p:save()end,"Ctrl+S. Saves every part on this sheet of paper.")
    top("Undo",function(p)p:undo(false)end,"Ctrl+Z. One undo per drawing stroke.")
    top("Redo",function(p)p:undo(true)end,"Ctrl+Shift+Z or Ctrl+Y")
    self.detailsButton=top("Details",function(p)p.details=not p.details;if p.details and p.libraryOpen then p:toggleLibrary()else p:layout()end end,"Names, shared tempo and length, and paper copies.")
    self.helpButton=top("Help",function(p)p.help=not p.help end,"Show editing shortcuts.")
    self.modeButton=tool("Draw [B]",function(p)p.mode=p.mode=="draw" and "select" or "draw"end,"B switches Draw / Select. Draw paints notes; Select moves and box-selects.")
    self.modeButton.rollWidth=measure("Select [B]")+24;self.metroButton.rollWidth=measure("Click: OFF")+24
    self.grid=choice({"Grid 1/1","Grid 1/2","Grid 1/4","Grid 1/8","Grid 1/16","Grid 1/32"},5,measure("Grid 1/32")+34,"Snap grid, down to 1/32 notes.")
    self.tripletButton=tool("Straight",function(p)p.triplet=not p.triplet end,"T: straight / triplet grid.")
    self.length=choice({"Len: Grid","Len: Last","Len: 1/32","Len: 1/16","Len: 1/8","Len: 1/4","Len: 1/2","Len: 1/1"},1,measure("Len: Last")+34,"New note length: grid, last resized note, or a fixed value.")
    tool("Quantize",function(p)p:quantize()end,"Ctrl+U. Snaps the selection, or all notes if nothing is selected.")
    tool("-",function(p)p:zoom(2)end,"Zoom out in time. Ctrl+wheel zooms around the pointer.")
    tool("+",function(p)p:zoom(.5)end,"Zoom in in time.")
    tool("Fit",function(p)p:fitNotes(false)end,"F: fit notes. Shift+F: fit whole song.")
    self.foldButton=tool("Fold",function(p)p.fold=not p.fold;p.pitchScroll=0;p:rebuildPitches();if not p.fold then p:fitNotes(false)end end,"Show only pitches used by this part. Turn off to add new pitches.")
    self.scaleButton=tool("Scale",function(p)p.scaleAnchor=p:pitchAt(p.gridY+p.gridH/3);p.scaleEnabled=not p.scaleEnabled;p:scaleChanged()end,"Choose a root and scale. Only scale hides other pitches; it never changes your notes.")
    self.velButton=tool("Velocity",function(p)p.showVelocity=not p.showVelocity;p:layout()end,"Show note velocities. Drag a stem to adjust selected notes.")
    self.auditionButton=tool("Hear",function(p)p.hear=not p.hear;if not p.hear then p:stopAudition()end end,"Hear notes when drawing, selecting or clicking the piano keys.")
    self.followButton=tool("Follow",function(p)p.follow=not p.follow end,"Follow the playhead during preview or recording.")
    local scaleNames={};for _,scale in ipairs(DeadAirRoll.scales)do scaleNames[#scaleNames+1]=scale[1]end
    self.rootNote=combo(self,{"Root C","Root C# / Db","Root D","Root D# / Eb","Root E","Root F","Root F# / Gb","Root G","Root G# / Ab","Root A","Root A# / Bb","Root B"},1,measure("Root C# / Db")+32)
    self.scaleType=combo(self,scaleNames,1,measure("Major pentatonic")+32)
    self.rootNote:setOnChange(self,function(p)p:scaleChanged()end);self.scaleType:setOnChange(self,function(p)p:scaleChanged()end)
    self.scaleViewButton=button(self,"Only scale",function(p)p.scaleOnly=not p.scaleOnly;p:scaleChanged()end,"Switch between hiding out-of-scale pitches and highlighting the scale in the full keyboard.")
    self.scaleControls={self.rootNote,self.scaleType,self.scaleViewButton}
    local function field(label,value,max,width)
        local e=entry(self,value,max,width);self.detailFields[#self.detailFields+1]={label=label,control=e,width=width};return e
    end
    self.titleEntry=field("Song",self.score.title,64,250)
    self.partEntry=field("Part",self.score.partName,48,170)
    self.partPicker=combo(self,{},1,math.max(260,measure("8. Guitar - Acoustic guitar")+36),"Switch the part you are editing. Every part keeps its own notes and instrument.")
    self.partPicker:setOnChange(self,function(p,c)p:switchPart(c.selected)end)
    self.instrument=combo(self,S.names,self.score.profile+1,math.max(210,measure("Drum kit / drumstick")+34),"Sound for the selected part. You do not need to own or equip this instrument to compose.")
    self.instrument:setOnChange(self,function(p)
        if p.transport or p.pending or p.saving then p.instrument.selected=p.score.profile+1;p.message="Stop playback or recording before changing instruments.";return end
        p:stopAudition();p.dirty=true;p:settings();p:updateMonitor()
    end)
    self.partButton=button(self,"Add part",function(p)p:addPart()end,"Add an empty part inside this song. No extra paper or instrument required.")
    self.monitorButton=button(self,"MIDI: OFF",function(p)p.monitor=not p.monitor;if p.monitor then p:updateMonitor()else p:stopMonitor()end end,"Hear the selected instrument from your connected MIDI keyboard while editing, without pressing Record. Only you hear it.")
    self.partControls={self.partPicker,self.instrument,self.partButton,self.monitorButton}
    self:refreshPartPicker()
    self.bpmEntry=field("BPM",self.score.bpm,3,math.max(60,measure("300")+20))
    self.barsEntry=entry(self,self.score.bars,6,math.max(84,measure("Bars (4/4)")+8))
    self.copyButton=button(self,"Copy song",function(p)p:paperAction("copy")end,"Copy the whole saved song onto another blank sheet.")
    self.exportButton=button(self,"Copy part",function(p)p:paperAction("export")end,"Copy the selected saved part onto blank paper for another musician.")
    self.detailFields[#self.detailFields+1]={label="Paper",control=self.copyButton,width=self.copyButton.rollWidth}
    self.detailFields[#self.detailFields+1]={label="",control=self.exportButton,width=self.exportButton.rollWidth}
    self.velocity=entry(self,100,3,54);self.applyVelocity=button(self,"Set",function(p)p:setVelocity()end,"Apply this velocity to selected notes; new notes also use this value.")
    self.closeButton=button(self,"Close",function(p)p:close()end,"Close keeps a draft for this game session. Save to paper to keep it across sessions.")
    self.maxButton=button(self,"Restore",function(p)p:toggleMaximize()end,"Expand / restore the editor. Drag the bottom-right corner to resize.")
    self.arrControls={}
    local function arrange(title,fn,tip)local b=button(self,title,fn,tip);self.arrControls[#self.arrControls+1]=b;return b end
    arrange("Fit song",function(p)p:fitArrangement()end,"Show the complete arrangement. Ctrl+wheel over tracks zooms; Shift+wheel scrolls time.")
    self.arrAdd=arrange("+ Track",function(p)p:addPart()end,"Add a track with its own instrument. No extra sheet required.")
    arrange("+ Clip",function(p)p:newPhrase()end,"Create a four-bar clip in free space at or after the playhead.")
    arrange("Duplicate",function(p)p:duplicatePhrase()end,"Duplicate the selected clip and all its notes into free space.")
    arrange("Delete clip",function(p)p:deletePhrase()end,"Remove the selected clip and its notes. Undo restores them.")
    self.deleteTrackButton=arrange("Delete track",function(p)p:deletePart()end,"Delete the selected track. Ctrl+Z restores it, including all notes and clips.")
    self.joinTrackButton=arrange("Join track",function(p)p:joinTrackClips()end,"Combine all clips on this track into one editable clip, keeping notes and gaps. Undo restores them.")
    self.loopButton=button(self,"Loop: OFF",function(p)p:toggleLoop()end,"Loop the selected clip. Drag its arrangement right edge to repeat the source cycle. Editing the source updates every repeat.")
    self.unrollButton=button(self,"Unroll",function(p)p:unrollClip()end,"Turn this clip's loop repetitions into independently editable notes, keeping the sound. Undo restores the loop.")
    self.scopeButton=button(self,"Clip notes",function(p)p:toggleEditScope()end,"Clip notes edits only the selected clip or its loop source. Track notes shows the whole track. Generated repeats remain protected until Unroll.")
    self.clipTimingButton=button(self,"Timing",function(p)p:toggleClipTiming()end,"Set the exact clip start, clip length and loop source length in bars. Use 8 for an eight-bar loop; 0.25 is one beat.")
    self.clipTimingFields={}
    local function timing(label,tip)
        local width=math.max(130,measure(label)+20);local control=entry(self,"",16,width)
        control:setTooltip(tip);self.clipTimingFields[#self.clipTimingFields+1]={label=label,control=control,width=width};return control
    end
    self.clipStartEntry=timing("Start bar","Song position: 1 is the beginning, 2 is bar two, 1.25 is bar one beat two.")
    self.clipLengthEntry=timing("Clip length (bars)","Total arrangement length, including repeats. Fractions are allowed: 0.25 is one beat.")
    self.clipLoopEntry=timing("Loop length (bars)","Length of one repeating cycle. Enable Loop first. Changing this rebuilds repeats from the original source notes, keeping their timing.")
    self.clipApplyButton=button(self,"Apply timing",function(p)p:applyClipTiming()end,"Apply all timing fields together. Notes are kept; overlapping clips and edits that cut source notes are rejected. Ctrl+Z undoes the change.")
    self.clipTimingFields[#self.clipTimingFields+1]={label="",control=self.clipApplyButton,width=self.clipApplyButton.rollWidth}
    self.loopButton.rollWidth=measure("Loop: OFF")+24;self.scopeButton.rollWidth=measure("Track notes")+24
    self.focusButton=top("Focus notes",function(p)p.notesOnly=not p.notesOnly;p:layout()end,"Hide or show the arrangement to give the piano roll more space.")
    self.soloButton=button(self,"Solo part",function(p)p:toggleTrack(p.activePart,"solo")end,"Hear only this part. Play normally previews all unmuted tracks.")
    self.phraseEntry=entry(self,"Clip 1",48,150)
    self.renameButton=button(self,"Name",function(p)p:renamePhrase()end,"Apply this name to the selected clip.")
    self.partControls={self.instrument,self.monitorButton,self.loopButton,self.unrollButton,self.scopeButton,self.clipTimingButton,self.phraseEntry,self.renameButton}
    self.partPicker:setVisible(false);self.partButton:setVisible(false);self.barsEntry:setVisible(false)
    -- Tempo is part of the transport; song and track names live in Details.
    for i=#self.detailFields,1,-1 do if self.detailFields[i].control==self.bpmEntry then table.remove(self.detailFields,i)end end
    table.insert(self.toolbar,5,self.bpmEntry);self.bpmEntry.rollWidth=104
    self.advancedTools={self.length,self.foldButton,self.auditionButton,self.followButton}
    for i=#self.tools,1,-1 do for _,c in ipairs(self.advancedTools)do if self.tools[i]==c then table.remove(self.tools,i);break end end end
    for _,c in pairs(self.children or {})do
        if c.backgroundColor then c.backgroundColor={r=.12,g=.13,b=.11,a=1};c.borderColor={r=.35,g=.36,b=.31,a=1}end
    end
    self.recordButton.backgroundColor={r=.30,g=.15,b=.12,a=1}
    self.rowH=math.max(14,self.fontH+2)
    self:rebuildPitches();self:layout()
    self:refreshClipTiming(true)
    local clip=self.song.parts[self.activePart].clips[1];if clip then self.phraseEntry:setText(clip.name)end
    if #self.notes>0 then self:fitNotes(false)end
    self:setWantKeyEvents(true);self:setWantMouseEvents(true)
end
function V:toggleMaximize()
    if self.maximized then
        self.maximized=false;local sw,sh=getCore():getScreenWidth(),getCore():getScreenHeight()
        self:setWidth(math.min(1060,sw-40));self:setHeight(math.min(670,sh-40));self:setX((sw-self.width)/2);self:setY((sh-self.height)/2)
    else
        self.maximized=true;self:setX(8);self:setY(8);self:setWidth(getCore():getScreenWidth()-16);self:setHeight(getCore():getScreenHeight()-16)
    end;self:layout()
end
function V:layout(compact)
    if not self.toolbar then return end
    local h,gap=self.controlH,5;local y=self.titleH
    local libraryW=math.max(320,math.min(410,self.width*.28));self.bodyW=self.width-(self.libraryOpen and libraryW+8 or 0)
    self.arrHidden=self.notesOnly or (self.libraryOpen and compact==true);local limit=self.width
    local function flow(controls,startX)
        local x=startX or 12
        for _,c in ipairs(controls)do
            local w=math.min(limit-24,c.rollWidth);c:setVisible(true)
            if x+w>limit-12 and x>12 then x=12;y=y+h+gap end
            if c==self.bpmEntry then self.bpmLabelX=x;self.bpmLabelY=y;place(c,x+38,y,w-38,h)else place(c,x,y,w,h)end;x=x+w+gap
        end;y=y+h+gap
    end
    flow(self.toolbar);limit=self.bodyW
    if self.libraryPanel then place(self.libraryPanel,self.bodyW+4,y,libraryW-4,self.height-y-10);self.libraryPanel:layout()end
    self.arrHeaderY=y
    for _,c in ipairs(self.arrControls)do c:setVisible(not self.arrHidden)end
    if not self.arrHidden then if self.bodyW<980 then y=y+self.fontH+6;flow(self.arrControls)else flow(self.arrControls,220)end end
    self.arrY=y;self.arrRulerH=self.fontH+10;self.trackH=math.max(42,self.fontH*2+12)
    self.trackW=math.max(200,math.min(310,self.bodyW*.24));self.arrW=self.bodyW-self.trackW-16
    self.trackRows=self.arrHidden and 0 or math.max(1,math.min(#self.song.parts,4,math.floor(self.height*.24/self.trackH)))
    if self.details then self.trackRows=math.min(1,self.trackRows)end
    self.arrH=self.arrHidden and 0 or self.arrRulerH+self.trackRows*self.trackH
    self.trackScroll=math.min(self.trackScroll or 0,math.max(0,#self.song.parts-self.trackRows))
    y=y+self.arrH+6;self.partLabelY=y;y=y+self.fontH+6
    if self.libraryOpen then self.phraseEntry:setVisible(false);self.renameButton:setVisible(false);if self.arrHidden then flow({self.partPicker,self.instrument,self.loopButton,self.unrollButton,self.scopeButton,self.clipTimingButton})else flow({self.instrument,self.loopButton,self.unrollButton,self.scopeButton,self.clipTimingButton})end else flow(self.partControls)end
    local timingX=12;local timingH=h+self.fontH+4
    for _,f in ipairs(self.clipTimingFields)do
        f.control:setVisible(self.clipTiming==true)
        if self.clipTiming then
            if timingX+f.width>self.bodyW-12 and timingX>12 then timingX=12;y=y+timingH+gap end
            f.x=timingX;f.y=y;place(f.control,timingX,y+self.fontH+3,f.width,h);timingX=timingX+f.width+gap
        end
    end
    if self.clipTiming then y=y+timingH+gap end
    flow(self.tools)
    for _,c in ipairs(self.advancedTools)do c:setVisible(self.details)end
    if self.details then flow(self.advancedTools)end
    for _,c in ipairs(self.scaleControls)do c:setVisible(self.scaleEnabled)end
    if self.scaleEnabled then flow(self.scaleControls)end
    local x=12;local detailH=h+self.fontH+4
    for _,f in ipairs(self.detailFields)do
        f.control:setVisible(self.details)
        if self.details then
            if x+f.width>self.bodyW-12 and x>12 then x=12;y=y+detailH+gap end
            f.x=x;f.y=y;place(f.control,x,y+self.fontH+3,f.width,h);x=x+f.width+gap
        end
    end
    if self.details then y=y+detailH+gap end
    self.gridX=math.max(60,measure("C#-1")+20);self.gridW=self.bodyW-self.gridX-16
    self.rulerY=y+2;self.gridY=self.rulerY+self.fontH+10
    self.overviewH=20;self.overviewY=self.height-3*self.fontH-36
    self.velocityH=math.max(64,2*self.fontH+self.controlH+10);self.velocityY=self.overviewY-self.velocityH-6
    self.availableGridH=math.max(32,(self.showVelocity and self.velocityY or self.overviewY)-self.gridY-6)
    if self.libraryOpen and not compact and self.availableGridH<110 then self:layout(true);return end
    self.rows=math.max(1,math.floor(self.availableGridH/self.rowH));self.gridH=self.rows*self.rowH
    self:clampView()
    place(self.closeButton,self.width-self.closeButton.rollWidth-10,5,self.closeButton.rollWidth,h)
    place(self.maxButton,self.closeButton.x-self.maxButton.rollWidth-5,5,self.maxButton.rollWidth,h)
    self.velocity:setVisible(self.showVelocity);self.applyVelocity:setVisible(self.showVelocity)
    if self.showVelocity then place(self.velocity,10,self.velocityY+self.fontH+1,44,h);place(self.applyVelocity,10,self.velocityY+self.fontH+h+3,44,math.max(18,self.fontH+2))end
    self.soloButton:setVisible(false);self.monitorButton:setVisible(not self.libraryOpen)
    self.partPicker:setVisible(self.libraryOpen==true and self.arrHidden==true);self.partButton:setVisible(false);self.barsEntry:setVisible(false);self.previewScope:setVisible(false)
    self.layoutW=self.width;self.layoutH=self.height
end

local names={"C","C#","D","D#","E","F","F#","G","G#","A","A#","B"}
function V:pitchName(n)return names[n%12+1]..(math.floor(n/12)-1)end
function V:prerender()
    ISPanel.prerender(self)
    if self.width~=self.layoutW or self.height~=self.layoutH then self:layout()end
    self:drawArrangement()
    local focused=self:currentClip()
    self:refreshClipTiming()
    self.loopButton:setTitle(focused and focused.loopLength and "Loop: ON"or "Loop: OFF")
    self.unrollButton:setEnable(focused~=nil and focused.loopLength~=nil)
    self.scopeButton:setTitle(self.editWholeTrack and "Track notes"or "Clip notes")
    self.libraryButton.backgroundColor=self.libraryOpen and {r=.31,g=.34,b=.24,a=1}or {r=.12,g=.13,b=.11,a=1}
    self:drawText("BPM",self.bpmLabelX,self.bpmLabelY+5,.68,.70,.61,1,UIFont.Small)
    self.focusButton:setTitle(self.notesOnly and "Show tracks"or "Focus notes")
    self.soloButton.backgroundColor=self.song.parts[self.activePart].solo and {r=.4,g=.43,b=.27,a=1}or {r=.12,g=.13,b=.11,a=1}
    local tick=self.transport and self:transportTick()or (self.playFrom or 0)
    local position=tostring(math.floor(tick/384)+1).."."..tostring(math.floor(tick%384/96)+1)
    if not self.arrHidden then self:drawText("ARRANGEMENT  "..position,14,self.arrHeaderY+6,.73,.76,.61,1,UIFont.Small)end
    local clip=self:currentClip()
    self:drawText(short(self.partEntry:getText().." / "..(clip and (clip.name..(clip.loopLength and " / source "..self:clipBars(clip.loopLength).." bars"or ""))or "Piano roll").."   -   "..(self.transport=="record"and "RECORDING"or "Private preview"),self.bodyW-28),14,self.partLabelY,.78,.80,.67,1,UIFont.Small)
    self.playButton:setTitle(self.transport=="preview" and "Stop" or "Play")
    self.metroButton:setTitle(self.metronome and "Click: ON" or "Click: OFF")
    self.modeButton:setTitle(self.mode=="draw" and "Draw [B]" or "Select [B]")
    self.tripletButton:setTitle(self.triplet and "Triplets" or "Straight")
    self.maxButton:setTitle(self.maximized and "Restore" or "Expand")
    self.scaleViewButton:setTitle(self.scaleOnly and "Only scale" or "All pitches")
    self.monitorButton:setTitle(self.monitor and "MIDI: ON" or "MIDI: OFF")
    for _,v in ipairs({{self.modeButton,self.mode=="draw"},{self.foldButton,self.fold},{self.scaleButton,self.scaleEnabled},{self.velButton,self.showVelocity},{self.auditionButton,self.hear},{self.followButton,self.follow},{self.detailsButton,self.details},{self.clipTimingButton,self.clipTiming}})do
        v[1].backgroundColor=v[2] and {r=.31,g=.34,b=.24,a=1}or{r=.12,g=.13,b=.11,a=1}
    end
    local subtitle="MUSICIAN / SONGBOOK   /   "..self.titleEntry:getText().."  -  "..self.partEntry:getText()..(self.dirty and " *" or "")
    self:drawText(short(subtitle,self.maxButton.x-28),14,10,.82,.84,.70,1,UIFont.Small)
    -- The workspace owns sidebar labels. Its button rows have no legacy x/y;
    -- drawing them here would pass nil coordinates into the Java UI bridge.
    if self.details and not self.workflowReady then for _,f in ipairs(self.detailFields)do self:drawText(f.label,f.x,f.y,.65,.72,.75,1,UIFont.Small)end end
    if self.clipTiming then for _,f in ipairs(self.clipTimingFields)do self:drawText(f.label,f.x,f.y,.73,.76,.61,1,UIFont.Small)end end
    local x,y,w,h=self.gridX,self.gridY,self.gridW,self.gridH
    self:drawRect(x,self.rulerY,w,y-self.rulerY,1,.11,.15,.17)
    self:drawRect(10,y,x-12,h,1,.1,.13,.15)
    self:setStencilRect(10,y,self.width-20,h)
    for row=math.floor(self.pitchScroll),math.min(#self.pitches-1,math.ceil(self.pitchScroll+self.rows))do
        local n=self.pitches[row+1];local py=y+(row-self.pitchScroll)*self.rowH
        local black=({[1]=true,[3]=true,[6]=true,[8]=true,[10]=true})[n%12]
        self:drawRect(x,py,w,self.rowH,1,black and .09 or .12,black and .10 or .13,black and .08 or .11)
        if self.scaleEnabled and self:inScale(n)then self:drawRect(x,py,w,self.rowH,.12,.3,.72,.55)end
        self:drawRect(10,py,x-14,self.rowH-1,1,black and .16 or .68,black and .20 or .73,black and .23 or .74)
        if n%12==(self.scaleEnabled and self.rootNote.selected-1 or 0) then self:drawRect(x,py,w,1,.6,.4,.75,.57)end
        if self.rowH>=self.fontH or n%12==(self.scaleEnabled and self.rootNote.selected-1 or 0) or self.fold then self:drawText(self:pitchName(n),14,py+(self.rowH-self.fontH)/2,black and .82 or .08,black and .88 or .13,black and .88 or .15,1,UIFont.Small)end
    end
    self:clearStencilRect()
    local step=self:step();local lineStep=step
    while lineStep/self.viewTicks*w<5 do lineStep=lineStep*2 end
    self:setStencilRect(x,y,w,h)
    for t=math.ceil(self.firstTick/lineStep)*lineStep,self.firstTick+self.viewTicks,lineStep do
        local px=x+(t-self.firstTick)/self.viewTicks*w
        self:drawRect(px,y,t%384==0 and 2 or 1,h,t%384==0 and .6 or t%96==0 and .3 or .12,.5,.65,.63)
    end
    if not self.drag and self.mode=="draw" and self.hoverX and not self.transport then
        local t,pitch=self:point(self.hoverX,self.hoverY)
        if t and not self:hit(self.hoverX,self.hoverY) then local nx,ny,nw,nh=self:noteRect({t=t,n=pitch,d=self:noteLength()})
            if nx then self:drawRect(nx,ny+1,nw-1,nh-2,.16,.55,1,.8)end
        end
    end
    for _,n in ipairs(self.notes)do
        local nx,ny,nw,nh=self:noteRect(n)
        if nx and ny+nh>y and ny<y+h and nx+nw>x and nx<x+w then
            local sel=self.selected[n];local ww=math.max(3,nw-1)
            self:drawRect(nx,ny+1,ww,nh-2,1,sel and .77 or .48,sel and .80 or (.48+n.v/127*.17),sel and .56 or .35)
            if sel then self:drawRectBorder(nx,ny+1,ww,nh-2,.9,.78,1,.91)end
            local grip=math.min(4,ww*.16);self:drawRect(nx+ww-grip,ny+3,grip,math.max(1,nh-6),.65,.83,1,.9)
            if nw>18 then self:drawRect(nx,ny+3,math.min(2,ww*.1),math.max(1,nh-6),.5,.83,1,.9)end
            if nw>measure(self:pitchName(n.n))+12 and nh>=self.fontH+2 then
                self:drawText(self:pitchName(n.n),nx+5,ny+(nh-self.fontH)/2,.035,.13,.13,1,UIFont.Small)
            end
        end
    end
    if self.drag and self.drag.kind=="marquee"then
        local d=self.drag;local mx,my=math.min(d.x,d.toX),math.min(d.y,d.toY);local mw,mh=math.abs(d.toX-d.x),math.abs(d.toY-d.y)
        self:drawRect(mx,my,mw,mh,.12,.5,.9,1);self:drawRectBorder(mx,my,mw,mh,.85,.55,.9,1)
    end
    if self.transport and self.transport~="library"and DeadAir.api()then
        local tick=self:transportTick()
        if tick>=self.firstTick and tick<=self.firstTick+self.viewTicks then self:drawRect(x+(tick-self.firstTick)/self.viewTicks*w,y,2,h,1,1,.72,.28)end
    end
    self:clearStencilRect()
    self:setStencilRect(x,self.rulerY,w,y-self.rulerY)
    local labelStep=96
    while labelStep/self.viewTicks*w<64 do labelStep=labelStep*2 end
    for t=math.ceil(self.firstTick/labelStep)*labelStep,self.firstTick+self.viewTicks,labelStep do
        local label=t%384==0 and tostring(math.floor(t/384)+1) or (math.floor(t/384)+1).."."..(math.floor(t%384/96)+1)
        self:drawText(label,x+(t-self.firstTick)/self.viewTicks*w+4,self.rulerY+3,.75,.85,.84,1,UIFont.Small)
    end;self:clearStencilRect()
    self:drawText("Pitch",12,self.rulerY+3,.65,.75,.76,1,UIFont.Small)
    if self.showVelocity then
        self:drawText("Vel.",10,self.velocityY,.65,.75,.76,1,UIFont.Small)
        self:drawRect(x,self.velocityY,w,self.velocityH,1,.10,.11,.085)
        self:setStencilRect(x,self.velocityY,w,self.velocityH)
        for _,n in ipairs(self.notes)do if self:noteEditable(n)then
            local nx=x+(n.t-self.firstTick)/self.viewTicks*w;local nh=n.v/127*(self.velocityH-5);local ny=self.velocityY+self.velocityH-nh
            self:drawRect(nx,ny,2,nh,.8,.62,.69,.42)
            self:drawRect(nx-3,ny-2,7,5,1,self.selected[n] and .85 or .60,.78,.53)
        end end;self:clearStencilRect()
    end
    self:drawText("Song",12,self.overviewY+4,.6,.72,.72,1,UIFont.Small)
    self:drawRect(x,self.overviewY,w,self.overviewH,1,.11,.15,.17)
    for _,n in ipairs(self.notes)do self:drawRect(x+n.t/self:ticks()*w,self.overviewY+2+(127-n.n)/127*(self.overviewH-5),math.max(2,n.d/self:ticks()*w),2,.7,.35,.85,.68)end
    local ox,ow=x+self.firstTick/self:ticks()*w,self.viewTicks/self:ticks()*w
    self:drawRect(ox,self.overviewY,ow,self.overviewH,.10,.7,1,.88);self:drawRectBorder(ox,self.overviewY,ow,self.overviewH,.85,.6,.9,.8)
    local info=self.editContext=="track"and "TRACK"or self.editContext=="clip"and "CLIP"or(self.mode=="draw"and "DRAW"or "SELECT")
    info=info.."   "..#self.notes.." notes   "..self:selectedCount().." selected   Bars "..(math.floor(self.firstTick/384)+1).."-"..math.ceil((self.firstTick+self.viewTicks)/384).." / "..self.score.bars
    info=info.."   "..S.names[self.instrument.selected].." / "..self.bpmEntry:getText().." BPM"
    if self.scaleEnabled then
        local hidden=0;for _,n in ipairs(self.notes)do if not self.pitchIndex[n.n]then hidden=hidden+1 end end
        info=info.."   "..self.rootNote.options[self.rootNote.selected]:sub(6).." "..DeadAirRoll.scales[self.scaleType.selected][1]..(hidden>0 and " ("..hidden.." notes hidden)" or "")
    end
    if self.hoverX and self:point(self.hoverX,self.hoverY)then local _,pitch=self:point(self.hoverX,self.hoverY);local _,n=self:hit(self.hoverX,self.hoverY);info=info.."   "..self:pitchName(pitch)..(n and " vel "..n.v or "")end
    local fy=self.overviewY+self.overviewH+4
    self:drawText(short(info,self.bodyW-28),12,fy,.68,.85,.79,1,UIFont.Small)
    self:drawText(short(self.message,self.bodyW-28),12,fy+self.fontH+2,1,.8,.46,1,UIFont.Small)
    local hint=self.mode=="draw" and "Drag: draw / move  |  Right-drag: erase  |  B: box select  |  Drag note edges: length" or "Drag a box: select  |  Ctrl-drag: copy  |  Alt-drag: velocity  |  Delete: remove  |  Ctrl+D: duplicate"
    if self.editContext=="track"then hint="Track selected  |  Delete: remove track  |  Ctrl+Z: restore  |  Click piano roll to edit notes"
    elseif self.editContext=="clip"then hint="Clip selected  |  Delete: remove clip  |  Ctrl+D: duplicate clip  |  Click piano roll to edit notes"end
    self:drawText(short(hint.."  |  Ctrl+wheel: zoom  |  Help: shortcuts",self.bodyW-28),12,fy+2*self.fontH+4,.58,.68,.72,1,UIFont.Small)
    self:drawLibraryDrop()
    self:drawRect(self.width-11,self.height-6,7,2,1,.55,.8,.72);self:drawRect(self.width-6,self.height-11,2,7,1,.55,.8,.72)
end
function V:render()
    if not self.help then return end
    local lines={"PIANO ROLL SHORTCUTS","B: Draw / Select     Space: preview / stop","Draw: paint empty space. Drag notes to move; right-drag erases.","Select: click / drag notes. Drag empty space to box-select.","Shift-click: add/remove selection. Ctrl+A: select all.","Drag either note edge: resize. Choose Len for new notes.","Ctrl-drag: copy notes. Alt-drag a note: change velocity.","Ctrl+C / X / V: copy / cut / paste at the last grid click.","Ctrl+D: duplicate after selection. Delete: remove selection.","Arrows: move selected notes. Shift+Up/Down: octave.","Ctrl+Z: undo. Ctrl+Shift+Z / Ctrl+Y: redo. Ctrl+S: save.","Ctrl+U: quantize selection, or all notes. T: triplet grid.","Wheel: pitches. Shift+wheel: time. Ctrl+wheel: time zoom.","Ctrl+Shift+wheel: pitch zoom. F: fit notes. Shift+F: song.","Drag top ruler: pan time; up/down zooms. Drag keys: pitches.","Click/drag the song overview to travel. Alt+empty drag: pan.","Fold: used pitches. Velocity: editable stems. Hear: audition.","Drag title to move window; bottom-right corner resizes.","Tracks: click clip to focus; drag to move; edge resizes.","R selects the recording track. Recording ends at Stop.","Drop chords in the roll: root follows pitch. Alt keeps source pitch.","Loop: drag clip edge to repeat. Edit the source; Unroll to separate.","Delete removes the focused notes, clip, or track. Ctrl+Z restores.","Join track combines its clips and keeps notes/gaps. Undo restores."}
    local width=0;for _,line in ipairs(lines)do width=math.max(width,measure(line)+32)end;width=math.min(width,self.width-32)
    local height=#lines*(self.fontH+5)+22;local xx=(self.width-width)/2;local yy=math.max(self.titleH+5,math.min(self.gridY+20,self.height-height-14))
    self:drawRect(xx,yy,width,height,.98,.07,.11,.13);self:drawRectBorder(xx,yy,width,height,1,.4,.75,.64)
    for i,line in ipairs(lines)do self:drawText(short(line,width-30),xx+15,yy+10+(i-1)*(self.fontH+5),.78,.9,.87,1,UIFont.Small)end
end
