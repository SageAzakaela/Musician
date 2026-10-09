local E,S,C,O,D=DeadAirSongEditor,DeadAirScore,DeadAirComposition,DeadAirClipOps,DeadAir
client=false;server=false;connected=false;ctrlDown=false;shiftDown=false;altDown=false;typing=false
D.Songs.cleanup();screenWidth,screenHeight,fontHeight=1440,900,16
local function fresh(notes,clips)
    local score=S.new();score.bars=16;score.notes=S.encode(notes or {})
    local sheet=paper();player.inventory=inventory({sheet})
    local e=E:new(sheet,score);e:initialise();e:setVisible(true);e.hear=false
    D.Songs.editor=e;D.editorActive=true
    if clips then e.song.parts[1].clips=S.copy(clips)end
    assert(e:settings());e:focusClip(1);return e,sheet
end
local function n(p,t,d,v)return {n=p,t=t,d=d or 24,v=v or 90}end
local function clip(start,length,period,offset)return {name='Groove',start=start,length=length,loopLength=period,loopStart=offset}end
local e=fresh({n(60,0)}, {clip(0,1536)})
assert(e:step()==24 and e:arrStep()==384)
e.grid.selected=6;assert(e:step()==12 and e:arrStep()==384)
e.arrGrid.selected=3;assert(e:arrStep()==96 and e:step()==12)
altDown=true;assert(e:arrStep()==1);altDown=false
e.arrGrid.selected=7;e.grid.selected=7;assert(e:step()==1 and e:arrStep()==1)
e.arrGrid.selected=6;e.arrAdaptive=true;e.arrTicks=384*512;e:prerender()
assert(e:arrStep()>12 and e.arrSnapButton.title:find('Auto'))
e.grid.selected=6;e.noteAdaptive=true;e.viewTicks=1536;e.gridW=300;assert(e:step()==48)
e:close()
-- Intro is played once; only the explicit loop interval is repeated.
local sheet;e,sheet=fresh({n(48,0,96),n(60,384,48)}, {clip(0,1536)})
assert(e:setLoopRange(384,768));assert(e:currentClip().loopStart==384 and e:currentClip().loopLength==384)
assert(#e.notes==4 and e.notes[1].n==48 and e.notes[2].t==384 and e.notes[4].t==1152)
assert(not e:noteEditable(e.notes[3]) and e:noteEditable(e.notes[2]))
local wire=S.encode(e.notes);e:save();local saved=assert(C.read(sheet))
assert(saved.parts[1].clips[1].loopStart==384 and S.equal(saved.parts[1].notes,wire))
assert(S.equal(S.encode(S.native(C.score(saved,1),0).notes),wire))
local bad=S.copy(saved);bad.parts[1].clips[1].loopStart=1536;assert(not C.validate(bad))
bad=S.copy(saved);bad.parts[1].clips[1].loopStart='bad';assert(not C.validate(bad))
e:undo();assert(not e:currentClip().loopStart and #e.notes==2);e:undo(true);assert(#e.notes==4)
local history=#e.undoStack;assert(not e:setLoopRange(0,384));assert(#e.undoStack==history and S.equal(S.encode(e.notes),wire))
-- Loop timing survives moving the clip beyond another clip and preserves focus.
e.song.parts[1].clips[2]=clip(2304,384);e.notes[#e.notes+1]=n(70,2304)
e:refreshClipTiming(true);e.clipStartEntry:setText('9');e.loopStartEntry:setText('10')
assert(e:applyClipTiming());assert(e.activeClip==2 and e:currentClip().start==3072 and e:currentClip().loopStart==384)
e:undo();assert(e:currentClip().start==0);e:close()
-- Split held notes at a precise cursor; rejection is atomic.
local part={clips={clip(0,768)}};local notes={n(60,300,180,72),n(64,600)}
local split=assert(O.split(part,notes,1,384,100));assert(#split.clips==2 and #split.notes==3)
assert(split.notes[1].d==84 and split.notes[2].t==384 and split.notes[2].d==96 and split.notes[2].v==72)
assert(not O.split(part,notes,1,0,100));assert(not O.split(part,notes,1,384,2));assert(notes[1].d==180)
-- Each repetition, including a partial tail, can become independent without losing notes.
for _,at in ipairs({384,768,1152,1536})do
    local p={clips={clip(0,1700,384,384)}}
    local source=assert(C.expandLoops(p,{n(48,0),n(60,384,96)},100))
    local edit=assert(O.unique(p,source,1,at,100));local variation=edit.clips[edit.active]
    assert(variation.start==at and not variation.loopLength)
    local expanded=assert(C.expandLoops(edit,edit.notes,100));assert(S.equal(S.encode(source),S.encode(expanded)))
    for _,note in ipairs(edit.notes)do if note.t==at then note.n=72 end end
    expanded=assert(C.expandLoops(edit,edit.notes,100));local changed=0
    for _,note in ipairs(expanded)do if note.n==72 then changed=changed+1;assert(note.t==at)end end
    assert(changed==1,'A variation changed another repetition')
end
-- Consolidation and group edits preserve gaps and refuse to cross an unselected clip.
part={clips={clip(0,384),clip(768,384),clip(1536,384)}};notes={n(60,0),n(64,768),n(67,1536)}
assert(not O.consolidate(part,notes,{[1]=true,[3]=true},100))
local joined=assert(O.consolidate(part,notes,{[1]=true,[2]=true},100))
assert(#joined.clips==2 and joined.clips[1].length==1152 and S.equal(S.encode(joined.notes),S.encode(notes)))
local moved=assert(O.move(part,notes,{[1]=true,[2]=true},384,false,100))
assert(moved.notes[1].t==384 and moved.notes[2].t==1152 and moved.notes[3].t==1536)
assert(not O.move(part,notes,{[1]=true,[2]=true},768,false,100))
local duplicated=assert(O.move(part,notes,{[1]=true,[2]=true},2304,true,100))
assert(#duplicated.clips==5 and duplicated.notes[4].t==2304 and duplicated.notes[5].t==3072)
assert(not O.move(part,notes,{[1]=true,[2]=true},2304,true,4))
-- Real editor keyboard, context-menu and undo paths.
e=fresh({n(60,0,96),n(62,192,96)}, {clip(0,1536,384)})
e.clipCursor=768;ctrlDown=true;e:onKeyPress(Keyboard.KEY_E);ctrlDown=false
assert(#e.song.parts[1].clips==2 and e.activeClip==2);e:undo();assert(#e.song.parts[1].clips==1)
e.clipCursor=800;assert(e:uniqueRepeat());assert(e:currentClip().start==768 and not e:currentClip().loopLength)
local before=S.encode(e.notes);e:selectAll();e:nudge(0,1)
for _,note in ipairs(e.notes)do if note.t>=768 and note.t<1152 then assert(note.n==61 or note.n==63)else assert(note.n==60 or note.n==62)end end
e:undo();assert(S.equal(before,S.encode(e.notes)));e:undo();assert(#e.song.parts[1].clips==1)
e:clipMenu(100,100);assert(#e.workflowMenu.options>=8)
e.transport='preview';e:clipMenu(100,100);assert(e.workflowMenu.options[1].notAvailable);e.transport=nil
e.clipCursor=384;e.phraseEntry.focused=true;ctrlDown=true;e:onKeyPress(Keyboard.KEY_E);ctrlDown=false;e.phraseEntry.focused=false
assert(#e.song.parts[1].clips==1,'Typing triggered a clip shortcut')
e:close()
-- Multi-selection via mouse, duplicate/delete, and a single undo for a group drag.
e=fresh(notes,part.clips);e:fitArrangement();e:prerender()
local function hit(i)for _,h in ipairs(e.trackHits)do if h.part==1 and h.clip==i then return h end end end
local h=hit(2);shiftDown=true;e:onMouseDown(h.x+12,h.y+8);shiftDown=false
assert(e.clipSelection[1]and e.clipSelection[2]and not e.clipSelection[3])
h=hit(1);local x,y=h.x+12,h.y+8;local undo=#e.undoStack;e:onMouseDown(x,y)
e.mx=x+384/e.arrTicks*e.arrW;e.my=y;e:onMouseMove(1,0);e:onMouseUp(e.mx,y)
assert(#e.undoStack==undo+1 and e.notes[1].t==384 and e.notes[2].t==1152)
e:undo();assert(e.notes[1].t==0 and e.clipSelection[1]and e.clipSelection[2])
e:duplicatePhrase();assert(#e.notes==5 and e.notes[4].t==1920 and e.notes[5].t==2688)
e:deletePhrase();assert(#e.notes==3);e:undo();assert(#e.notes==5);e:undo();assert(#e.notes==3)
ctrlDown=true;e:onKeyPress(Keyboard.KEY_J);ctrlDown=false;assert(#e.song.parts[1].clips==2 and e:currentClip().length==1152)
e:undo();e:close()
-- Brace handles: fixed viewport while dragging, cancellation and time-selection action.
e=fresh({n(60,0,48)}, {clip(0,1536,384)});e.viewTicks=1536;e:layout();e:prerender()
local function brace(t,delta,cancel)
    local x=e.gridX+t/e.viewTicks*e.gridW;local y=e.loopY+e.loopH/2
    e:onMouseDown(x,y);assert(e.drag and e.drag.kind=='loopEnd')
    e.mx=x+delta/e.viewTicks*e.gridW;e.my=y;e:onMouseMove(1,0)
    if cancel then e:onKeyPress(Keyboard.KEY_ESCAPE)else e:onMouseUp(e.mx,y)end
end
brace(384,384,true);assert(e:currentClip().loopLength==384 and #e.notes==4)
brace(384,384);assert(e:currentClip().loopLength==768 and #e.notes==2);e:undo()
e.viewTicks=1536;e:layout();shiftDown=true;e:onMouseDown(e.gridX,e.loopY+8);shiftDown=false
e.mx=e.gridX+768/e.viewTicks*e.gridW;e.my=e.loopY+8;e:onMouseMove(1,0);e:onMouseUp(e.mx,e.my)
ctrlDown=true;e:onKeyPress(Keyboard.KEY_L);ctrlDown=false
assert(e:currentClip().loopLength==768 and #e.notes==2)
e:undo();e:loopPreset(2);assert(e:currentClip().loopLength==768);e:close()
-- Resizable split, persistent per-user layout, bounded/corrupt preference handling.
screenWidth,screenHeight,fontHeight=1920,1080,14
e=fresh();e:layout();local dy=e.dividerY;local initial=e.arrContentH
local originalPitch=e.pitchScroll;local center=e.pitchScroll+e.rows/2
local beforeNotes=DeadAirScore.encode(e.notes);local beforeUndo=#e.undoStack
-- Even ONE track grows by individual pixels; use the bottom of the visible handle.
local grab=dy+e.dividerH-1
e:onMouseDown(40,grab);assert(e.drag.kind=='divider' and e.capture)
e.mx=40;e.my=grab+7;e:onMouseMove(0,1)
assert(e.dividerY==dy+7 and e.arrContentH==initial+7 and e.trackRows==1)
e.my=grab+143;e:onMouseMoveOutside(0,1)
assert(e.dividerY==dy+143 and math.abs(e.pitchScroll+e.rows/2-center)<.01)
e:onKeyPress(Keyboard.KEY_ESCAPE)
assert(not e.drag and not e.capture and e.arrangementHeight==nil and e.dividerY==dy and e.pitchScroll==originalPitch)
e:onMouseDown(40,grab);e.mx=40;e.my=grab+143;e:onMouseMove(0,1);e:onMouseUpOutside(40,e.my)
assert(e.arrContentH==initial+143 and not e.capture);local height=e.arrangementHeight
assert(DeadAirScore.equal(beforeNotes,DeadAirScore.encode(e.notes)) and #e.undoStack==beforeUndo)
dy=e.dividerY;e:onMouseDown(40,dy+2);e.mx=40;e.my=dy-60;e:onMouseMove(0,-1);e:onKeyPress(Keyboard.KEY_ESCAPE);assert(e.arrangementHeight==height)
local reader,writer=getFileReader,getFileWriter;local prefs={}
function getFileWriter(name)assert(name=='MusicianEditorLayout.ini');prefs={};return {write=function(_,s)prefs[#prefs+1]=s:gsub('\n$','')end,close=function()end}end
function getFileReader(name)assert(name=='MusicianEditorLayout.ini');local i=0;return {readLine=function()i=i+1;return prefs[i]end,close=function()end}end
e.arrGrid.selected=4;e.grid.selected=6;e.arrAdaptive=true;e.inspectorOpen=false;e:writeLayout()
local restored=fresh();assert(restored.arrGrid.selected==4 and restored.grid.selected==6 and restored.arrAdaptive and not restored.inspectorOpen and restored.arrangementHeight==height)
prefs={'version=1','arrangementHeight=99999','arrGrid=99999','noteGrid=-99'};restored:readLayout();assert(restored.arrangementHeight==8192 and restored.arrGrid.selected==7 and restored.grid.selected==1)
prefs={'version=bad','arrGrid=2'};restored:readLayout();assert(restored.arrGrid.selected==7)
getFileReader,getFileWriter=reader,writer;restored:close();e:close()
-- Resizing reveals all tracks and repairs scroll offsets; shrinking only the
-- window must not destroy the preferred size, and a later grab must not jump.
e=fresh();for i=2,8 do e:addPart()end
e.arrangementHeight=e.trackH;e:layout();e.trackScroll=7
dy=e.dividerY;e:onMouseDown(40,dy+3);e.mx=40;e.my=dy+10000;e:onMouseMove(0,1);e:onMouseUp(40,e.my)
assert(e.trackRows==8 and e.trackScroll==0 and e.availableGridH>=100 and not e.arrHidden)
height=e.arrangementHeight;e:setHeight(800);e:layout()
assert(e.arrContentH<height and e.arrangementHeight==height and e.availableGridH>=100)
dy=e.dividerY;initial=e.arrContentH;e:onMouseDown(40,dy+3);e.mx=40;e.my=dy-4;e:onMouseMove(0,-1)
assert(e.arrContentH==initial-7 and e.dividerY==dy-7,'Dragging a clamped layout jumped')
e:onKeyPress(Keyboard.KEY_ESCAPE);assert(e.arrangementHeight==height)
e:setHeight(1064);e:layout();assert(e.arrContentH==height)
dy=e.dividerY;e:onMouseDown(40,dy+3);e.mx=40;e.my=-10000;e:onMouseMove(0,-1);e:onMouseUp(40,e.my)
assert(e.arrContentH==e.trackH and e.trackRows==1)
e:close()
-- Accessible controls at common screens and larger font sizes, including inspector scrolling.
for _,size in ipairs({{1024,768,18},{1280,720,22},{1920,1080,22}})do
    screenWidth,screenHeight,fontHeight=size[1],size[2],size[3]
    e=fresh();e.scaleEnabled=true;e:rebuildPitches();e.showVelocity=true
    for _,details in ipairs({false,true})do for _,scroll in ipairs({0,99999})do
        e.details=details;e.inspectorScroll=scroll;e:layout();e:prerender()
        assert(e.gridH>=32 and e.gridY+e.gridH<=e.velocityY)
        local visible={}
        for _,c in pairs(e.children)do if c:isVisible()then
            assert(c.x>=0 and c.y>=0 and c.x+c.width<=e.width and c.y+c.height<=e.height,'Control outside window')
            visible[#visible+1]=c
        end end
        for i=1,#visible do for j=i+1,#visible do local a,b=visible[i],visible[j]
            assert(not(a.x<b.x+b.width and a.x+a.width>b.x and a.y<b.y+b.height and a.y+a.height>b.y),'Workspace controls overlap')
        end end
    end end
    e:close()
end
screenWidth,screenHeight,fontHeight=1280,720,14
print('PASS: independent/adaptive snapping; loop brace, intro-once range, shortcuts and paper persistence; held-note split, unique repetitions, consolidation and group edits with atomic limits/undo; context menus, divider/preferences and inspector layouts')
