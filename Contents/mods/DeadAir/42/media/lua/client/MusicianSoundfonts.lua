require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISComboBox"
require "ISUI/ISTextEntryBox"

-- Public registration API for optional soundfont-pack mods. No files are read here.
MusicianSoundfonts=MusicianSoundfonts or {packs={},serial=0}
local F=MusicianSoundfonts
function F.registerPack(pack)
    if type(pack)~="table"or type(pack.modId)~="string"or type(pack.key)~="string"or type(pack.path)~="string"or type(pack.name)~="string"then return false end
    local id=pack.modId..":"..pack.key
    F.packs[id]={modId=pack.modId,key=pack.key,path=pack.path,name=pack.name};F.serial=F.serial+1;return true
end
function F.sync()
    if not DeadAirMidi or not DeadAirMidi.soundfontPacks or F.sent==F.serial then return end
    local keys,rows={},{};for key in pairs(F.packs)do keys[#keys+1]=key end;table.sort(keys)
    for _,key in ipairs(keys)do if #rows<32 then rows[#rows+1]=F.packs[key]end end
    DeadAirMidi.soundfontPacks(rows);F.sent=F.serial
end

MusicianSoundfontPanel=ISPanel:derive("MusicianSoundfontPanel")
local P=MusicianSoundfontPanel
local function clamp(v,a,b)return math.max(a,math.min(b,v))end
local function place(c,x,y,w,h)c:setX(x);c:setY(y);c:setWidth(w);c:setHeight(h)end
local function short(s,w)
    s=tostring(s or "");local tm=getTextManager()
    if tm:MeasureStringX(UIFont.Small,s)<=w then return s end
    while #s>0 and tm:MeasureStringX(UIFont.Small,s.."...")>w do s=s:sub(1,-2)end;return s.."..."
end
local function button(self,text,fn,tip)
    local b=ISButton:new(0,0,80,self.rh,text,self,fn);b:initialise();self:addChild(b);if tip then b:setTooltip(tip)end;return b
end
local function entry(self,placeholder,max)
    local e=ISTextEntryBox:new("",0,0,100,self.rh);e:initialise();e:instantiate();e.javaObject:setMaxTextLength(max);e:setPlaceholderText(placeholder);self:addChild(e);return e
end
function P:new()
    local sw,sh=getCore():getScreenWidth(),getCore():getScreenHeight();local w,h=math.min(1060,sw-30),math.min(780,sh-30)
    local o=ISPanel.new(self,(sw-w)/2,(sh-h)/2,w,h);o.moveWithMouse=true;o.fontH=getTextManager():getFontHeight(UIFont.Small);o.rh=math.max(26,o.fontH+10)
    o.backgroundColor={r=.07,g=.08,b=.07,a=.99};o.borderColor={r=.36,g=.38,b=.29,a=1};o.profile=1;o.leftScroll=0;o.rightScroll=0;o.rows={};o.names={};o.bankIds={};return o
end
function P:initialise()
    ISPanel.initialise(self)
    self.closeButton=button(self,"Close",function(p)p:close()end,"Close discards mappings you have not applied.")
    self.path=entry(self,"Paste an SF2 file path, or use Browse...",1024)
    self.addButton=button(self,"Add file",function(p)if not DeadAirMidi.soundfontAdd(p.path:getText())then p.notice="Wait for the current operation to finish."end end)
    self.browseButton=button(self,"Browse...",function()DeadAirMidi.soundfontBrowse()end,"Opens a file picker. Fullscreen users can paste a path instead.")
    self.bank=ISComboBox:new(0,0,100,self.rh,self,nil);self.bank:initialise();self.bank:setOnChange(self,function(p)p:bankChanged()end);self:addChild(self.bank)
    self.search=entry(self,"Search preset names, bank or program numbers",100)
    self.previewButton=button(self,"Preview",function(p)local row=p.rows[p.selected];if row then p.notice=nil;if not DeadAirMidi.soundfontPreview(p.bankId,row.key,p.profile-1)then p.notice="Wait for the current operation to finish."end end end,"A short private phrase; does not change the assignment or broadcast MIDI.")
    self.stopButton=button(self,"Stop preview",function()DeadAirMidi.soundfontStopPreview()end)
    self.assignButton=button(self,"Assign sound",function(p)p:assign()end)
    self.defaultButton=button(self,"Use included sound",function(p)if p.draft then p.draft[p.profile]={bank="",preset=""};p.dirty=true;p.editSerial=(p.editSerial or 0)+1 end end)
    self.resetButton=button(self,"Reset all",function(p)if p.draft then for i=1,16 do p.draft[i]={bank="",preset=""}end;p.dirty=true;p.editSerial=(p.editSerial or 0)+1 end end,"Reset every assignment to the included sounds. Apply to save; custom files stay in your library.")
    self.applyButton=button(self,"Apply sounds",function(p)
        if p.draft then F.sync();p.notice=nil;p.appliedSerial=p.editSerial or 0;p.applying=DeadAirMidi.soundfontApply(p.draft);if not p.applying then p.notice="Wait for the current operation to finish."end end
    end,"Saves these choices for this computer. Stop song playback/recording first. Held live notes end when sounds switch.")
    self.refreshButton=button(self,"Refresh",function(p)F.sync();p.notice=nil;local accepted;if p.bankId then accepted=DeadAirMidi.soundfontInspect(p.bankId)else accepted=DeadAirMidi.soundfontRefresh()end;if not accepted then p.notice="Wait for the current operation to finish."end end)
    self:layout();F.sync();self.wantRefresh=not DeadAirMidi.soundfontRefresh();self:poll()
end
function P:layout()
    local w,h,r,f=self.width,self.height,self.rh,self.fontH
    self.left=math.max(220,math.floor(w*.32));self.rx=self.left+24;self.rw=w-self.rx-12
    place(self.closeButton,w-86,9,74,r)
    self.pathY=20+r+f;place(self.path,12,self.pathY,w-216,r);place(self.addButton,w-198,self.pathY,86,r);place(self.browseButton,w-106,self.pathY,94,r)
    self.bankY=self.pathY+r+12;place(self.bank,self.rx,self.bankY,self.rw-92,r);place(self.refreshButton,w-98,self.bankY,86,r)
    place(self.search,self.rx,self.bankY+r+6,self.rw,r)
    self.listY=self.bankY+2*r+14;self.bottom=h-3*r-3*f-34;self.listH=math.max(r,self.bottom-self.listY)
    self.leftRowH=2*f+12;self.rightRowH=f+12;self.leftRows=math.max(1,math.floor(self.listH/self.leftRowH));self.rightRows=math.max(1,math.floor(self.listH/self.rightRowH))
    place(self.defaultButton,12,self.bottom+6,self.left,r)
    local width=(self.rw-12)/3
    place(self.previewButton,self.rx,self.bottom+6,width,r);place(self.stopButton,self.rx+width+6,self.bottom+6,width,r);place(self.assignButton,self.rx+2*width+12,self.bottom+6,width,r)
    self.statusY=self.bottom+r+14;place(self.resetButton,12,h-r-12,96,r);place(self.applyButton,w-160,h-r-12,148,r)
end
function P:bankChanged()
    self.bankId=self.bankIds[self.bank.selected];self.selected=nil;self.rows={};self.rightScroll=0;self.notice=nil
    if self.bankId and not DeadAirMidi.soundfontInspect(self.bankId)then self.pendingBank=self.bankId end
end
function P:chooseProfile(i)
    self.profile=i;self.selected=nil;local choice=self.draft and self.draft[i]
    local id=choice and choice.bank~=""and choice.bank or "bundled"
    for n,key in ipairs(self.bankIds)do if key==id then self.bank.selected=n;if self.bankId~=id then self:bankChanged()else self:filter()end;return end end
    self.notice="This assignment's soundfont pack is unavailable. The included sound will play."
end
function P:filter()
    self.rows={};self.selected=nil;self.rightScroll=0;self.query=self.search:getText():lower()
    if not self.snapshot or self.snapshot.inspected~=self.bankId then return end
    for _,p in ipairs(self.snapshot.presets or {})do
        local text=p.name:lower().." "..tostring(p.bank).." "..tostring(p.program)
        if self.query==""or text:find(self.query,1,true)then self.rows[#self.rows+1]=p end
    end
    local assigned=self.draft and self.draft[self.profile]
    if assigned and assigned.bank==self.bankId then for i,row in ipairs(self.rows)do if row.key==assigned.preset then self.selected=i;self.rightScroll=math.max(0,i-self.rightRows);break end end end
end
function P:poll()
    local state=DeadAirMidi.soundfontState();self.snapshot=state
    if self.wantRefresh and not DeadAirMidi.busy()then self.wantRefresh=not DeadAirMidi.soundfontRefresh()end
    if self.pendingBank and not DeadAirMidi.busy()then local id=self.pendingBank;self.pendingBank=nil;if self.bankId==id then DeadAirMidi.soundfontInspect(id)end end
    if state.revision~=self.revision then
        self.revision=state.revision
        if not self.draft and state.loaded then self.draft={};for i,row in ipairs(state.mappings)do self.draft[i]={bank=row.bank,preset=row.preset}end end
        self.bank:clear();self.bankIds={}
        for i,b in ipairs(state.banks or {})do self.bank:addOption(b.name);self.bankIds[i]=b.id;if b.id==self.bankId then self.bank.selected=i end end
        if not self.bankId and #self.bankIds>0 then self.bankId=self.bankIds[1];self.bank.selected=1 end
        if state.added~=""and state.added~=self.added then self.added=state.added;self.bankId=state.added;for i,id in ipairs(self.bankIds)do if id==self.bankId then self.bank.selected=i end end end
        for _,p in ipairs(state.presets or {})do self.names[state.inspected.."/"..p.key]=p.name end
        self:filter()
        if self.applying and state.message:find("^Applied")then if(self.editSerial or 0)==self.appliedSerial then self.dirty=false end;self.applying=nil end
    end
    if self.search:getText():lower()~=self.query then self:filter()end
end
function P:assign()
    local row=self.rows[self.selected];if not row or not self.draft then return end
    self.draft[self.profile]={bank=self.bankId,preset=row.key};self.dirty=true;self.editSerial=(self.editSerial or 0)+1;self.notice="Assigned "..row.name..". Apply sounds to save."
end
function P:mappingLabel(i)
    local c=self.draft and self.draft[i];if not c or c.bank==""then return "Included sound"end
    return self.names[c.bank.."/"..c.preset]or(c.bank:find("^pack:")and "Pack preset "or"Preset ")..c.preset
end
function P:onMouseDown(x,y)
    if y>=self.listY and y<self.bottom then
        if x>=12 and x<12+self.left then local i=self.leftScroll+math.floor((y-self.listY)/self.leftRowH)+1;if i<=16 then self:chooseProfile(i)end
        elseif x>=self.rx then local i=self.rightScroll+math.floor((y-self.listY)/self.rightRowH)+1;if i<=#self.rows then self.selected=i end end
        return true
    end
    return ISPanel.onMouseDown(self,x,y)
end
function P:onMouseWheel(delta)
    if self:getMouseX()<self.rx then self.leftScroll=clamp(self.leftScroll-delta*3,0,math.max(0,16-self.leftRows))else self.rightScroll=clamp(self.rightScroll-delta*3,0,math.max(0,#self.rows-self.rightRows))end;return true
end
function P:prerender()
    ISPanel.prerender(self);self:poll()
    self:drawText("MUSICIAN / SOUNDS"..(self.dirty and " *"or""),12,12,.82,.86,.72,1,UIFont.Small)
    self:drawText(short("Local listening choices. Packs and mappings are not sent to other players.",self.width-24),12,16+self.rh,.62,.67,.60,1,UIFont.Small)
    self:drawText("Zomboid instrument",12,self.bankY+4,.85,.86,.78,1,UIFont.Small)
    self:drawText(short("Select a preset, then Assign sound.",self.left),12,self.bankY+self.rh+8,.6,.64,.58,1,UIFont.Small)
    self:drawRect(12,self.listY,self.left,self.listH,.7,.03,.04,.03);self:drawRect(self.rx,self.listY,self.rw,self.listH,.7,.03,.04,.03)
    for row=1,self.leftRows do local i=self.leftScroll+row;if i>16 then break end;local y=self.listY+(row-1)*self.leftRowH
        if i==self.profile then self:drawRect(12,y,self.left,self.leftRowH,.8,.25,.28,.19)end
        local info=self.snapshot.mappings and self.snapshot.mappings[i]
        self:drawText(short(info and info.name or "Loading...",self.left-16),20,y+3,.88,.88,.80,1,UIFont.Small)
        self:drawText(short(self:mappingLabel(i),self.left-16),20,y+self.fontH+6,.61,.70,.57,1,UIFont.Small)
    end
    for row=1,self.rightRows do local i=self.rightScroll+row;local p=self.rows[i];if not p then break end;local y=self.listY+(row-1)*self.rightRowH
        if i==self.selected then self:drawRect(self.rx,y,self.rw,self.rightRowH,.8,.25,.28,.19)end
        local suffix="  ["..p.bank..":"..p.program..(p.drums and " drums]"or"]")
        self:drawText(short(p.name..suffix,self.rw-16),self.rx+8,y+5,.84,.86,.77,1,UIFont.Small)
    end
    if #self.rows==0 then self:drawText(short("No presets shown. Choose a bank, clear search, or check the message below.",self.rw-16),self.rx+8,self.listY+8,.65,.68,.59,1,UIFont.Small)end
    local busy=DeadAirMidi.busy();local text=self.notice or(busy and "Loading sounds..."or self.snapshot.message)
    self:drawText(short(text,self.width-24),12,self.statusY,.85,.77,.48,1,UIFont.Small);self.applyButton:setTooltip(text)
    self:drawText(short("Drum presets keep GM percussion keys. Piano and keytar share one sound. Close discards unapplied changes.",self.width-24),12,self.statusY+self.fontH+4,.58,.63,.57,1,UIFont.Small)
end
function P:close()
    DeadAirMidi.soundfontStopPreview();self.path:unfocus();self.search:unfocus();self:setVisible(false);self:removeFromUIManager();F.panel=nil
end
function F.show()
    if not DeadAirMidi or not DeadAirMidi.soundfontState then if DeadAir then DeadAir.notice="Restart and approve Musician 0.13.0 for custom soundfonts."end;return end
    if F.panel then F.panel:bringToTop();return end
    local p=P:new();p:initialise();p:setVisible(true);p:addToUIManager();p:bringToTop();F.panel=p
end
