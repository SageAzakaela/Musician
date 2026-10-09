local E,S,C,P,D=DeadAirSongEditor,DeadAirScore,DeadAirComposition,DeadAirPatterns,DeadAir
client=false;server=false;connected=false;D.Songs.cleanup();player.dead=false;player.moving=false
ctrlDown=false;altDown=false;shiftDown=false;typing=false
screenWidth,screenHeight,fontHeight=1440,900,16
local function fresh(notes,bars)
    local s=S.new();s.bars=bars or 8;s.notes=S.encode(notes or {})
    local sheet=paper();player.inventory=inventory({sheet});local e=E:new(sheet,s);e:initialise();e:setVisible(true);e.hear=false;D.Songs.editor=e;D.editorActive=true
    return e,sheet
end
local function resize(e,length,cancel)
    e.arrGrid.selected=3;e:fitArrangement();e:prerender();local hit
    for _,r in ipairs(e.trackHits)do if r.part==e.activePart and r.clip==e.activeClip then hit=r end end
    assert(hit and hit.resize);local old=e:currentClip().length
    local x,y=hit.x+hit.w-2,hit.y+8;e:onMouseDown(x,y);assert(e.drag.kind=='clipEnd')
    e.mx=x+(length-old)/e.arrTicks*e.arrW;e.my=y;e:onMouseMove(1,0)
    if cancel then e:onKeyPress(Keyboard.KEY_ESCAPE)else e:onMouseUp(e.mx,e.my)end
end
local e,sheet=fresh();e:toggleLibrary();local b=e.libraryPanel;b.duration.selected=1;b:selectRow(1)
e.pitchScroll=e.pitchIndex[72];e:clampView();local first,view,arr=e.firstTick,e.viewTicks,e.arrTicks
local x=e.gridX+96/e.viewTicks*e.gridW+1;local y=e.gridY+(e.pitchIndex[66]-e.pitchScroll+.5)*e.rowH
local drop=b:dropAt(x,y);assert(drop.zone=='roll'and drop.pitch==66 and drop.at==96)
b:onMouseDown(20,b.listY+5);b.mx=x-b.x;b.my=y-b.y;b:onMouseMove(1,0);assert(e.libraryGhost.drop.pitch==66)
e:prerender();b:onMouseUpOutside(b.mx,b.my)
assert(#e.notes==3 and e.notes[1].n==66 and e.notes[2].n==70 and e.notes[3].n==73)
assert(#e.song.parts[1].clips==1 and e.firstTick==first and e.viewTicks==view and e.arrTicks==arr,'Roll drop created a new clip or moved the viewport')
drop.at=192;drop.pitch=62;assert(e:insertLibraryClip(b:clip(),drop,false));assert(#e.notes==6 and #e.song.parts[1].clips==1)
assert(e:insertLibraryClip(b:clip(),drop,false)and #e.notes==6,'Repeated same-place drops stack identical voices')
e:undo();assert(#e.notes==6);e:undo();assert(#e.notes==3);e:undo(true);assert(#e.notes==6)
altDown=true;assert(b:dropAt(x,y).pitch==nil);altDown=false
-- Progression tonic is separate from its first chord root (vi-IV-I-V starts on vi).
local progression=P.make(2,2,0,3,1);local rooted=e:dropNotes(progression,{at=0,pitch=54})
assert(rooted[1].n==63,'A progression drop anchored its first chord instead of its tonic')
local drums=P.make(3,1,0,3,4);local hits=e:dropNotes(drums,{at=0,pitch=90});assert(hits[1].n==36)
local imported={notes={{n=60,t=12,d=24,v=90},{n=64,t=12,d=24,v=90}},length=96,drums=false};assert(e:dropNotes(imported,{at=0,pitch=66})[1].n==66)
local before=S.encode(e.notes);assert(not e:insertLibraryClip(P.make(1,16,0,5,4),{part=1,zone='roll',at=0,pitch=127},false));assert(S.equal(before,S.encode(e.notes)))
e:close()
-- Loop source edits update repeats; scope protects independent clips.
e,sheet=fresh({{n=60,t=0,d=96,v=90},{n=64,t=0,d=96,v=90},{n=67,t=288,d=96,v=90},{n=76,t=3091,d=37,v=71}},12)
e.song.parts[1].clips={{name='One bar',start=0,length=384},{name='Neighbor',start=3072,length=384}};assert(e:settings());e:focusClip(1)
e:toggleLoop();assert(e:currentClip().loopLength==384)
resize(e,1536);assert(e:currentClip().length==1536 and #e.notes==13 and e.viewTicks==384)
e:selectAll();assert(e:selectedCount()==3);e:nudge(0,1)
local total=0;for _,n in ipairs(e.notes)do if n.t<1536 then assert(n.n==61 or n.n==65 or n.n==68);total=total+1 else assert(n.n==76 and n.t==3091 and n.v==71)end end;assert(total==12)
e:quantize();local neighbor;for _,n in ipairs(e.notes)do if n.n==76 then neighbor=n end end;assert(neighbor.t==3091 and neighbor.d==37,'Quantize changed a different clip')
local encoded=S.encode(e.notes);resize(e,384,true);assert(e:currentClip().length==1536 and S.equal(encoded,S.encode(e.notes)),'Cancelled loop trim lost notes')
resize(e,960);assert(e:currentClip().length==960 and #e.notes==9)
for _,n in ipairs(e.notes)do assert(n.t<960 or n.t>=3072,'Shrinking loop left old repeats')end
e:undo();assert(e:currentClip().length==1536 and #e.notes==13);e:undo(true);assert(#e.notes==9)
e:save();local stored=assert(C.read(sheet));assert(stored.parts[1].clips[1].loopLength==384)
local native=S.native(C.score(stored,1),0);assert(#native.notes==9)
e:close();e=E:new(sheet,C.read(sheet));e:initialise();e:setVisible(true);e.hear=false;D.Songs.editor=e;D.editorActive=true;e:focusClip(1)
assert(e:currentClip().loopLength==384 and #e.notes==9 and e.viewTicks==384)
e:selectAll();e:deleteSelected();assert(#e.notes==1 and e.notes[1].n==76);e:undo();assert(#e.notes==9)
e:unrollClip();assert(not e:currentClip().loopLength and #e.notes==9 and e.viewTicks==960)
e:selectAll();assert(e:selectedCount()==8);e:undo();assert(e:currentClip().loopLength==384)
e:joinTrackClips();assert(#e.song.parts[1].clips==1 and not e:currentClip().loopLength and #e.notes==9);e:undo();assert(#e.song.parts[1].clips==2)
-- Moving and duplicating a loop keep its source/repeats aligned and its neighbor intact.
local sourceWire=S.encode(e.notes)
e:fitArrangement();e:prerender();local r;for _,hit in ipairs(e.trackHits)do if hit.part==1 and hit.clip==1 then r=hit end end
e:onMouseDown(r.x+10,r.y+10);assert(e.drag.kind=='clipGroup');e.mx=r.x+10+384/e.arrTicks*e.arrW;e.my=r.y+10;e:onMouseMove(1,0);e:onMouseUp(e.mx,e.my)
assert(e:currentClip().start==384 and e:currentClip().loopLength==384 and #e.notes==9)
for _,n in ipairs(e.notes)do if n.n~=76 then assert(n.t>=384 and n.t<1344)end end
e:undo();assert(S.equal(sourceWire,S.encode(e.notes)))
e:duplicatePhrase();assert(#e.song.parts[1].clips==3 and e:currentClip().loopLength==384 and #e.notes==17)
e:deletePhrase();assert(#e.notes==9);e:undo();assert(#e.notes==17);e:undo();assert(#e.notes==9 and #e.song.parts[1].clips==2)
-- Track view must not let a source note silently disappear into protected repeats.
e:focusClip(1);e.editWholeTrack=true;e:selectAll();e.selected={};e.selected[e.notes[1]]=true
local unchanged=S.encode(e.notes);e:nudge(384,0);assert(S.equal(unchanged,S.encode(e.notes)))
assert(not e:addNote(400,80,12));e:fitNotes(true);e.mode='draw';e.hoverX=e.gridX+400/e.viewTicks*e.gridW;e.hoverY=e.gridY+8;e:prerender();e.hoverX=nil;e.hoverY=nil;e:focusClip(1)
e:preview(false);local playable=false;for _,part in ipairs(e:previewParts(false))do if #part.notes==9 then playable=true end end;assert(playable);e:stop()
-- Track deletion, including the last track, participates in the same chronological undo.
local originalId=e.song.parts[1].part;local originalNotes=S.encode(e.notes)
e:addPart();e.partEntry:setText('Drums');e.instrument.selected=10;assert(e:settings());local secondId=e.song.parts[2].part
assert(e:insertLibraryClip(drums,{part=2,at=0,zone='roll'},false));local count=#e.notes
e:deletePart(1);assert(#e.song.parts==1 and #e.notes==count and e.song.parts[1].part==secondId)
e:undo();assert(#e.song.parts==2 and e.song.parts[1].part==originalId and S.equal(e.song.parts[1].notes,originalNotes))
e:undo(true);assert(#e.song.parts==1 and e.song.parts[1].part==secondId)
e:save();local revision=e.song.revision;e:undo();assert(#e.song.parts==2 and e.song.revision==revision);e:save();assert(C.read(sheet).parts[1].part==originalId)
e:deletePart(2);e:deletePart(1);assert(#e.song.parts==1 and #e.notes==0);e:undo();assert(e.song.parts[1].part==originalId and #e.notes==9)
-- Delete follows focus, and typing never deletes a track.
e.editContext='track';e.titleEntry.focused=true;e:onKeyPress(Keyboard.KEY_DELETE);assert(#e.notes==9);e.titleEntry.focused=false
e.editContext='clip';e:focusClip(1);e:onKeyPress(Keyboard.KEY_DELETE);assert(#e.notes==1 and #e.song.parts[1].clips==1);e:undo();assert(#e.notes==9)
e:close()
-- Partial cycles truncate only the generated final note; overflow rejects before allocating repeats.
local p={clips={{name='Loop',start=0,length=960,loopLength=384}}}
local looped=assert(C.expandLoops(p,{{n=60,t=0,d=384,v=100}},10));assert(#looped==3 and looped[3].t==768 and looped[3].d==192)
assert(not C.expandLoops({clips={{start=0,length=S.MAX_BARS*384,loopLength=1}}},{{n=60,t=0,d=1,v=100}},S.MAX_NOTES))
assert(not C.expandLoops({clips={{start=0,length=768,loopLength=384}}},{{n=60,t=0,d=400,v=100}},S.MAX_NOTES))
local invalid=C.fromScore(S.new());invalid.parts[1].clips[1].loopLength=0;assert(not C.validate(invalid))
e,sheet=fresh({{n=60,t=0,d=1,v=100}});e.song.parts[1].clips={{name='Tiny',start=0,length=1,loopLength=1}};assert(e:settings());e:focusClip(1)
local previous=S.encode(e.notes);local clips=S.copy(e.song.parts[1].clips)
-- A drop that would be multiplied past capacity is atomic.
e.song.parts[1].clips[1].length=8192;assert(e:settings());local initial=#e.notes
local dense={name='Dense chord',notes={{n=64,t=0,d=1,v=90},{n=67,t=0,d=1,v=90}},length=1,warning=''}
assert(not e:insertLibraryClip(dense,{part=1,zone='roll',at=0},false)and #e.notes==initial)
e:close()
screenWidth,screenHeight,fontHeight=1280,720,14
print('PASS: F# chord-root drag preview/drop, progression tonic, drum pitch preservation, same-clip note merging, stable viewport, loop extend/shrink/cancel/edit/unroll, neighbor isolation, chronological undo, track deletion and save/reopen/export, partial cycles and atomic capacity rejection')
