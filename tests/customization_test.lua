local S=DeadAirScore
local function fresh()
    local score=S.new();score.notes='60,0,96,80;64,96,96,90;'
    local e=DeadAirSongEditor:new(paper(),score);e:initialise();e:setVisible(true);e.hear=false;return e
end
local function press(c)(c.onclick or c.callback)(c.target,c)end
local function visibleLayout(e)
    local visible={}
    for _,c in pairs(e.children)do if c:isVisible()then
        assert(c.x>=0 and c.y>=0 and c.x+c.width<=e.width+.01 and c.y+c.height<=e.height+.01,'View control outside window')
        visible[#visible+1]=c
    end end
    for i=1,#visible do for j=i+1,#visible do local a,b=visible[i],visible[j]
        assert(not(a.x<b.x+b.width-.01 and a.x+a.width>b.x+.01 and a.y<b.y+b.height-.01 and a.y+a.height>b.y+.01),'View controls overlap')
    end end
end
screenWidth,screenHeight,fontHeight=1920,1080,18
local e=fresh();e:addPart();e:switchPart(1);e:layout()
assert(e.arrContentH==2*e.trackH and not e.partPicker:isVisible() and e.gridY<350,'Balanced view wastes vertical space')
local before=S.encode(e.notes);local history=#e.undoStack
press(e.viewButton);assert(e.viewSettings and e.inspectorOpen)
e.themeChoice.selected=2;e.themeChoice.onChange(e,e.themeChoice)
assert(e.themeIndex==2 and e.palette.base.r==DeadAirAppearance.themes[2].base.r)
e.accentChoice.selected=6;e.accentChoice.onChange(e,e.accentChoice);assert(e.accentColor==0xB09BDD)
e.accentEntry:setText('#123ABC');press(e.accentApply);assert(e.accentColor==0x123ABC)
e.accentEntry:setText('#nope');assert(not e:applyAccent() and e.accentColor==0x123ABC)
local function lum(c)local function f(v)return v<=.04045 and v/12.92 or ((v+.055)/1.055)^2.4 end;return .2126*f(c.r)+.7152*f(c.g)+.0722*f(c.b)end
for _,color in ipairs({0,0xFFFFFF,0xFF0000,0x00FF00,0x0000FF,0xB09BDD})do
    e.accentColor=color;e:rebuildTheme()
    for _,pair in ipairs({{'accent','onAccent'},{'selected','onSelected'},{'clip','onClip'},{'clipSelected','onClipSelected'}})do
        local a,b=lum(e.palette[pair[1]]),lum(e.palette[pair[2]])
        assert((math.max(a,b)+.05)/(math.min(a,b)+.05)>=4.5,'Custom color made text unreadable')
    end
end
for i=1,3 do e.presetChoice.selected=i;e.presetChoice.onChange(e,e.presetChoice);e:prerender();visibleLayout(e)end
assert(e.arrangementHeight);press(e.viewFitButton);assert(not e.arrangementHeight)
e:applyViewPreset(2);assert(e.arrHidden and e.partPicker:isVisible() and e.showVelocity)
-- Lane/sidebar resizing is layout-only, with capture, bounds and Escape.
e.mx=e.gridX+20;e.my=e.velocityDividerY+3;local y=e.my;local h=e.velocityH
e:onMouseDown(e.mx,e.my);assert(e.drag.kind=='velocitySize')
e.my=y-23;e:onMouseMoveOutside(0,-1);assert(e.velocityH==h+23)
e:onKeyPress(Keyboard.KEY_ESCAPE);assert(not e.drag and e.velocityH==h)
e:onMouseDown(e.gridX+20,e.velocityDividerY+3);e.mx=e.gridX+20;e.my=e.velocityDividerY-24;e:onMouseMove(0,-1);e:onMouseUpOutside(e.mx,e.my)
assert(e.velocityHeight>h and not e.capture)
local w=e.sidebarWidth;e:onMouseDown(e.bodyW+1,e.sideY+30);assert(e.drag.kind=='sidebarSize')
e.mx=e.drag.x-36;e.my=e.drag.y;e:onMouseMove(-1,0);e:onMouseUp(e.mx,e.my);assert(e.sidebarWidth==w+36)
-- Context follows completed gestures, while customization and Song remain pinned.
press(e.editInspectorButton);e.details=false;e.editContext='notes';e:prerender()
assert(e.inspectorContext=='notes' and e.velocity:isVisible() and not e.clipStartEntry:isVisible())
e.editContext='clip';e:prerender();assert(e.clipStartEntry:isVisible() and not e.velocity:isVisible())
e.editContext='track';e:prerender();assert(e.partEntry:isVisible() and not e.phraseEntry:isVisible())
press(e.advancedButton);assert(e.deleteTrackButton:isVisible())
e:noteMenu();assert(#e.noteActionsMenu.options>=10)
for _,o in ipairs(e.noteActionsMenu.options)do if o.title=='Fit clip'then o.fn(o.target)end end
assert(S.equal(before,S.encode(e.notes)) and #e.undoStack==history,'Appearance changed musical content/history')
-- Save every preference, restore it in another editor, and migrate v1 without losing settings.
local reader,writer=getFileReader,getFileWriter;local prefs={}
function getFileWriter(name)assert(name=='MusicianEditorLayout.ini');prefs={};return {write=function(_,s)prefs[#prefs+1]=s:gsub('\n$','')end,close=function()end}end
function getFileReader(name)assert(name=='MusicianEditorLayout.ini');local i=0;return {readLine=function()i=i+1;return prefs[i]end,close=function()end}end
e.themeIndex=3;e.accentColor=0xB09BDD;e.showOverview=false;e.showHints=true;e.trackDensity=3;e.compactControls=false;e:writeLayout()
local restored=fresh()
assert(restored.themeIndex==3 and restored.accentColor==0xB09BDD and restored.notesOnly and restored.showVelocity)
assert(not restored.showOverview and restored.showHints and restored.trackDensity==3 and not restored.compactControls)
assert(restored.velocityHeight==e.velocityHeight and restored.sidebarWidth==e.sidebarWidth)
restored:resetView();local defaults=fresh();assert(defaults.themeIndex==1 and not defaults.accentColor and defaults.arrangementHeight==nil and defaults.showOverview)
prefs={'version=1','arrangementHeight=321','inspector=1','arrGrid=4'}
local legacy=fresh();assert(legacy.arrangementHeight==321 and legacy.inspectorOpen and legacy.arrGrid.selected==4)
prefs={'version=2','theme=9999','accent=99999999','sidebar=-5','tracks=0','velocityHeight=99999'}
legacy:readLayout();assert(legacy.themeIndex==4 and legacy.accentColor==16777215 and legacy.sidebarWidth==240 and legacy.trackDensity==1 and legacy.velocityHeight==360)
getFileReader,getFileWriter=reader,writer
for _,editor in ipairs({e,restored,defaults,legacy})do editor:close()end
-- Themes, density, all inspector contexts and scrolling at smaller/larger font sizes.
for _,size in ipairs({{1024,768,18},{1280,720,22},{1920,1080,22}})do
    screenWidth,screenHeight,fontHeight=size[1],size[2],size[3];e=fresh();e.inspectorOpen=true
    for _,density in ipairs({true,false})do for theme=1,4 do
        e.compactControls=density;e:chooseTheme(theme)
        for _,context in ipairs({'clip','notes','track','view','song'})do
            e.viewSettings=context=='view';e.details=context=='song';e.editContext=context;e.showVelocity=true;e.scaleEnabled=true;e:rebuildPitches()
            for _,offset in ipairs({0,99999})do
                e.inspectorScroll=offset;e:layout();e:prerender();visibleLayout(e)
                assert(e.gridH>=32 and e.gridY+e.gridH<=e.velocityDividerY)
            end
        end
    end end;e:close()
end
screenWidth,screenHeight,fontHeight=1280,720,14
print('PASS: compact workspace, contextual inspector, View callbacks/presets, velocity/sidebar resize, theme/accent contrast, v1 migration/v2 persistence/reset, bounds and multi-screen/font/theme layouts; musical data/history unchanged')
