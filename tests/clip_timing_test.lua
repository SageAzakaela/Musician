local E,S,C,D=DeadAirSongEditor,DeadAirScore,DeadAirComposition,DeadAir
client=false;server=false;connected=false;D.Songs.cleanup();player.dead=false
ctrlDown=false;altDown=false;shiftDown=false;typing=false
screenWidth,screenHeight,fontHeight=1440,900,16
local function fresh(notes,clips,bars)
    local score=S.new();score.bars=bars or 64;score.notes=S.encode(notes)
    local sheet=paper();player.inventory=inventory({sheet})
    local e=E:new(sheet,score);e:initialise();e:setVisible(true);e.hear=false
    D.Songs.editor=e;D.editorActive=true;e.song.parts[1].clips=S.copy(clips);assert(e:settings());e:focusClip(1)
    return e,sheet
end
local function drag(e,kind,delta,cancel)
    e:prerender();local hit
    for _,r in ipairs(e.trackHits)do if r.part==e.activePart and r.clip==e.activeClip then hit=r end end
    assert(hit)
    local x=kind=='clipEnd'and hit.x+hit.w-2 or hit.x+10;local y=hit.y+8
    e:onMouseDown(x,y);assert(e.drag.kind==kind)
    e.mx=x+delta/e.arrTicks*e.arrW;e.my=y;e:onMouseMove(1,0)
    if cancel then e:onKeyPress(Keyboard.KEY_ESCAPE)else e:onMouseUp(e.mx,e.my)end
end
local function apply(e,start,length,loop)
    e.clipStartEntry:setText(tostring(start));e.clipLengthEntry:setText(tostring(length));e.clipLoopEntry:setText(loop and tostring(loop)or '')
    return e:applyClipTiming()
end
-- A 7.875-bar edge must reach bar 9 on the 1/1 grid. Snapping the delta
-- rounds this small repair to zero and leaves every repetition early.
local e,sheet=fresh({{n=38,t=0,d=24,v=90},{n=45,t=2976,d=48,v=71}},{{name='Take',start=0,length=3024}},8)
e.arrGrid.selected=1;e:fitArrangement();drag(e,'clipEnd',48)
assert(e:currentClip().length==3072,'Off-grid clip edge stayed off-grid')
assert(e.notes[2].t==2976 and e.notes[2].d==48)
e:toggleLoop();assert(e:currentClip().loopLength==3072)
e:undo();e:undo();assert(e:currentClip().length==3024)
drag(e,'clipEnd',48,true);assert(e:currentClip().length==3024)
-- The note-protection clamp must also land on the selected grid, while
-- respecting unquantized performance timing and note tails.
e.notes[2].d=74;assert(e:settings());assert(e:currentClip().length==3050)
drag(e,'clipEnd',-384);assert(e:currentClip().length==3072 and e.notes[2].d==74)
e:close()
e=fresh({{n=60,t=85,d=30,v=73}},{{name='Offset',start=48,length=768}},8)
e.arrGrid.selected=1;e:fitArrangement();drag(e,'clipGroup',336)
assert(e:currentClip().start==384 and e.notes[1].t==421,'Move retained an off-grid start or quantized the performance')
e:undo();assert(e:currentClip().start==48 and e.notes[1].t==85);e:close()
-- Repair an existing six-cycle take. Old generated notes at tick 3024
-- must not become part of the newly enlarged 3072-tick source.
local original={{n=38,t=0,d=24,v=90},{n=45,t=2990,d=24,v=71},{n=77,t=19981,d=31,v=63}}
local clips={{name='Take',start=0,length=18144,loopLength=3024},{name='Neighbor',start=19968,length=384}}
e,sheet=fresh(original,clips);assert(e:syncLoops());assert(#e.notes==13)
local before=S.encode(e.notes)
e.inspectorOpen=false;click(e.clipTimingButton)
assert(e.clipTiming and e.clipLoopEntry:getText()=='7.875')
e.clipLoopEntry:setText('8');e.clipLengthEntry:setText('48');e:prerender()
assert(e.clipLoopEntry:getText()=='8','Rendering overwrote a pending timing edit')
click(e.clipApplyButton)
assert(e:currentClip().loopLength==3072 and e:currentClip().length==18432 and #e.notes==13)
for cycle=0,5 do
    local a,b=e.notes[cycle*2+1],e.notes[cycle*2+2]
    assert(a.t==cycle*3072 and a.n==38 and a.d==24 and a.v==90)
    assert(b.t==cycle*3072+2990 and b.n==45 and b.d==24 and b.v==71)
end
assert(e.notes[13].t==19981 and e.notes[13].d==31 and e.notes[13].v==63)
local repaired=S.encode(e.notes);e:undo();assert(e:currentClip().loopLength==3024 and S.equal(before,S.encode(e.notes)))
e:undo(true);assert(e:currentClip().loopLength==3072 and S.equal(repaired,S.encode(e.notes)))
e:save();local stored=assert(C.read(sheet));assert(stored.parts[1].clips[1].loopLength==3072)
assert(S.equal(stored.parts[1].notes,repaired));assert(S.equal(S.encode(S.native(C.score(stored,1),0).notes),repaired))
e:close();e=E:new(sheet,stored);e:initialise();e:setVisible(true);e.hear=false;D.Songs.editor=e;D.editorActive=true;e:focusClip(1)
assert(e.clipLoopEntry:getText()=='8'and e:currentClip().length==18432)
-- Invalid edits are atomic, keep source notes, and do not consume undo history.
local undoCount=#e.undoStack
for _,values in ipairs({{1,48,4},{1,48,49},{1,64,8},{1,0,8},{0,48,8},{1,'bad',8},{1,48,'1e999'}})do
    assert(not apply(e,values[1],values[2],values[3]));assert(S.equal(S.encode(e.notes),repaired))
    assert(e:currentClip().length==18432 and e:currentClip().loopLength==3072 and #e.undoStack==undoCount)
end
e:focusClip(2);assert(e.clipStartEntry:getText()=='53'and e.clipLoopEntry:getText()=='')
assert(apply(e,50,1));assert(e:currentClip().start==18816 and e.notes[13].t==18829)
e:undo();assert(e:currentClip().start==19968 and e.notes[13].t==19981)
e:close()
-- Fractional bars, triplet periods and a one-tick period round-trip exactly.
e=fresh({{n=60,t=0,d=1,v=80}},{{name='Small',start=0,length=384,loopLength=384}},8)
assert(apply(e,1,8,8/3));assert(e:currentClip().loopLength==1024 and #e.notes==3 and e.notes[3].t==2048)
e:undo();assert(apply(e,1,1/384,1/384));e:refreshClipTiming(true)
assert(e:applyClipTiming()and e:currentClip().loopLength==1)
e.clipStartEntry.focused=true;e:onKeyPress(Keyboard.KEY_DELETE);assert(#e.notes==1);e.clipStartEntry.focused=false
local notes=S.encode(e.notes);assert(not C.retimeClip(e.song.parts[1],e.notes,1,0,384,1,2));assert(S.equal(notes,S.encode(e.notes)))
e:close()
-- The exact controls must stay accessible with the library and larger fonts.
for _,size in ipairs({{1024,768,18},{1280,720,16},{1920,1080,22}})do
    screenWidth,screenHeight,fontHeight=size[1],size[2],size[3]
    e=fresh({{n=60,t=0,d=96,v=90}},{{name='Clip',start=0,length=3072}},8);e.inspectorOpen=false;e:toggleClipTiming()
    for _,library in ipairs({false,true})do
        if library then e:toggleLibrary()end
        e:layout();e:prerender();assert(e.gridH>=96 and e.gridY+e.gridH<=e.overviewY)
        local visible={}
        for _,c in ipairs(e.children)do if c.visible~=false then
            assert(c.x>=0 and c.y>=0 and c.x+c.width<=e.width and c.y+c.height<=e.height)
            visible[#visible+1]=c
        end end
        for i=1,#visible do for j=i+1,#visible do local a,b=visible[i],visible[j]
            assert(not(a.x<b.x+b.width and a.x+a.width>b.x and a.y<b.y+b.height and a.y+a.height>b.y),'Timing controls overlap')
        end end
    end
    e:close()
end
screenWidth,screenHeight,fontHeight=1280,720,14
print('PASS: absolute clip snapping, note-safe aligned trimming, exact loop repair without source contamination, six-cycle phase alignment, fractional/triplet timing, atomic rejection, undo/redo, save/reopen/playback and timing-control layouts')
