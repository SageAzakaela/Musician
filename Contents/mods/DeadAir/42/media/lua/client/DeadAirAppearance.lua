-- Local Songbook appearance only. Never serialized into songs or sent to peers.
DeadAirAppearance={}
local A=DeadAirAppearance
local function rgb(r,g,b)return {r=r,g=g,b=b,a=1}end
local function mix(a,b,t)return rgb(a.r+(b.r-a.r)*t,a.g+(b.g-a.g)*t,a.b+(b.b-a.b)*t)end
local function luminance(c)
    local function linear(v)return v<=.04045 and v/12.92 or ((v+.055)/1.055)^2.4 end
    return .2126*linear(c.r)+.7152*linear(c.g)+.0722*linear(c.b)
end
local function ink(c)return luminance(c)>.179 and rgb(0,0,0)or rgb(1,1,1)end
A.themes={
    {name="Zomboid",base=rgb(.075,.08,.07),panel=rgb(.12,.13,.11),accent=rgb(.58,.67,.39)},
    {name="Charcoal",base=rgb(.065,.067,.072),panel=rgb(.12,.125,.14),accent=rgb(.35,.70,.68)},
    {name="Slate",base=rgb(.065,.085,.11),panel=rgb(.105,.145,.185),accent=rgb(.38,.65,.87)},
    {name="High contrast",base=rgb(.025,.025,.025),panel=rgb(.10,.10,.10),accent=rgb(.96,.72,.25)}
}
A.accents={{"Theme default"},{"Olive",0x94AB63},{"Teal",0x59B3AD},{"Amber",0xE5AD59},{"Rose",0xD88198},{"Lavender",0xB09BDD},{"Blue",0x72AFE5},{"Custom"}}
function A:rebuildTheme()
    local t=A.themes[self.themeIndex or 1]or A.themes[1];local accent=t.accent
    if self.accentColor then local n=self.accentColor;accent=rgb(math.floor(n/65536)/255,math.floor(n/256)%256/255,n%256/255)end
    local white=rgb(1,1,1)
    -- Keep very dark user accents visible without changing the saved color.
    local brightness=.2126*accent.r+.7152*accent.g+.0722*accent.b
    if brightness<.28 then accent=mix(accent,white,(.28-brightness)/(1-brightness))end
    local p={base=t.base,panel=t.panel,accent=accent,text=rgb(.89,.90,.85),muted=rgb(.69,.73,.72),
        gridDark=mix(t.base,t.panel,.3),gridLight=mix(t.panel,white,.025),ruler=mix(t.panel,white,.045),
        line=rgb(.45,.49,.47),border=rgb(.34,.37,.33),warning=rgb(1,.78,.39),record=rgb(.40,.17,.14)}
    p.selected=mix(accent,white,.35);p.clip=mix(t.panel,accent,.48);p.clipSelected=mix(t.panel,accent,.72)
    p.active=mix(t.panel,accent,.36);p.hover=mix(t.panel,accent,.20)
    p.onAccent=ink(accent);p.onSelected=ink(p.selected);p.onClip=ink(p.clip);p.onClipSelected=ink(p.clipSelected)
    p.keyWhite=rgb(.70,.74,.73);p.keyBlack=rgb(.14,.17,.18)
    if self.themeIndex==4 then p.text=white;p.muted=rgb(.83,.83,.83);p.line=rgb(.65,.65,.65);p.border=rgb(.60,.60,.60)end
    self.palette=p;self.backgroundColor=p.base;self.borderColor=p.border
    if self.accentEntry then
        local n=self.accentColor;self.accentEntry:setText(n and string.format("#%06X",n)or "")
        self.themeChoice.selected=self.themeIndex or 1;self.accentChoice.selected=n and #A.accents or 1
        for i,v in ipairs(A.accents)do if n and v[2]==n then self.accentChoice.selected=i end end
    end
    self:styleControls()
end
function A:themeColor(role)return (self.palette or {}).text and self.palette[role]or A.themes[1].panel end
function A:themeRect(role,x,y,w,h,a)
    local c=self:themeColor(role);self:drawRect(x,y,w,h,a or 1,c.r,c.g,c.b)
end
function A:themeBorder(role,x,y,w,h,a)
    local c=self:themeColor(role);self:drawRectBorder(x,y,w,h,a or 1,c.r,c.g,c.b)
end
function A:themeText(role,text,x,y)
    local c=self:themeColor(role);self:drawText(text,x,y,c.r,c.g,c.b,1,UIFont.Small)
end
function A:styleControls()
    if not self.palette then return end
    local p=self.palette
    local function style(c)
        if c.backgroundColor then c.backgroundColor=p.panel;c.borderColor=p.border;c.backgroundColorMouseOver=p.hover;c.textColor=p.text;c.fontColor=p.text end
    end
    for _,c in pairs(self.children or {})do style(c)end
    if self.libraryPanel then for _,c in pairs(self.libraryPanel.children or {})do style(c)end end
    if self.recordButton then self.recordButton.backgroundColor=p.record end
    local flags={{self.libraryButton,self.libraryOpen},{self.inspectorButton,self.inspectorOpen and not self.viewSettings},
        {self.viewButton,self.viewSettings},{self.modeButton,self.mode=="draw"},{self.scaleButton,self.scaleEnabled},
        {self.velButton,self.showVelocity},{self.foldButton,self.fold},{self.auditionButton,self.hear},{self.followButton,self.follow},
        {self.detailsButton,self.details},{self.advancedButton,self.inspectorAdvanced},{self.monitorButton,self.monitor},
        {self.soloButton,self.song.parts[self.activePart].solo},{self.fitTracksButton,self.arrangementHeight==nil},
        {self.editInspectorButton,not self.details and not self.viewSettings}}
    for _,v in ipairs(flags)do if v[1]then v[1].backgroundColor=v[2]and p.active or p.panel end end
end
function A:chooseTheme(index)
    self.themeIndex=math.max(1,math.min(#A.themes,math.floor(index)));self:rebuildTheme();self:writeLayout()
end
function A:chooseAccent(index)
    local choice=A.accents[index];if not choice then return end
    if index==#A.accents then return end
    self.accentColor=choice[2];self:rebuildTheme();self:writeLayout()
end
function A:applyAccent()
    local text=self.accentEntry:getText():gsub("^#","")
    if #text~=6 or text:find("[^%x]")then self.message="Use six color digits, for example #B09BDD. Or choose a color above.";return false end
    self.accentColor=tonumber(text,16);self:rebuildTheme();self:writeLayout();return true
end
