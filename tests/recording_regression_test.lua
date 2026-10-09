local E,S,C,D=DeadAirSongEditor,DeadAirScore,DeadAirComposition,DeadAir
client=false;server=false;connected=true;audioReady=true;ctrlDown=false;shiftDown=false;altDown=false;typing=false
D.Songs.cleanup();player.dead=false;player.moving=false;scoreTick=0
screenWidth,screenHeight,fontHeight=1440,900,16
local function note(n,t,d)return {n=n,t=t,d=d or 24,v=77}end
local function fresh(notes,clips)
    local s=S.new();s.bars=16;s.notes=S.encode(notes or {})
    local paper=paper();player.inventory=inventory({paper});local e=E:new(paper,s);e:initialise();e:setVisible(true);e.hear=false
    D.Songs.editor=e;D.editorActive=true
    if clips then e.song.parts[1].clips=S.copy(clips);assert(e:settings());e:focusClip(1)end
    return e,paper
end
local function visible(e,pitch)
    local row=e.pitchIndex[pitch];return row and row>=e.pitchScroll and row<e.pitchScroll+e.rows
end
local oldNext,oldStop,oldPeek,oldMotion,oldStart=next,DeadAirMidi.recordStop,DeadAirMidi.recordNotes,DeadAirMidi.motionState,DeadAirMidi.recordStartOpen
next=nil -- Match the actual PZ VM even when this suite is run through Lua 5.1.
local e,sheet=fresh()
assert(visible(e,60),'An empty piano roll should include middle C')
local selected=e:clipSelectionSet();assert(selected[1]);e.clipSelection={[2]=false,[99]=true};assert(e:clipSelectionSet()[1])
local original=S.encode(e.notes);local history=#e.undoStack
local take={note(48,12,48),note(55,1800,96),note(60,2016,240)}
local attack=0;local heldPitch=48;local heldVelocity=100
DeadAirMidi.motionState=function()return {attack=attack,note=heldPitch,velocity=heldVelocity,held=1}end
local available=0
DeadAirMidi.recordNotes=function(from)local a={};for i=from+1,available do a[#a+1]=S.copy(take[i])end;return a end
DeadAirMidi.recordStop=function()return S.copy(take)end
local started=false
DeadAirMidi.recordStartOpen=function(...)assert(#e.undoStack==history+1,'Capture started before its undo checkpoint');started=true;return oldStart(...)end
e:preview(true);e:update();assert(started and e.transport=='record'and e.recordBase and e.recordSeen==0)
-- A held note moves the pitch viewport before a note-off adds a completed event.
time=time+2200;scoreTick=24;attack=1;e.pitchScroll=0;e:update()
assert(visible(e,48) and #e.notes==0,'Held input should center the recording range before release')
-- Follow off respects manual navigation, then recent completed notes catch up.
e.follow=false;e.pitchScroll=0;attack=2;heldPitch=36;time=time+200;e:update();assert(e.pitchScroll==0)
e.follow=true;available=2;scoreTick=1900;time=time+200;e:update()
assert(#e.notes==2 and e.recordSeen==2 and visible(e,48)and visible(e,55))
assert(e:noteRect(e.notes[2]) and e.firstTick<=1900 and e.firstTick+e.viewTicks>1900,'Recording past the old clip must remain visible')
time=time+200;e:update();assert(#e.notes==2,'Incremental capture duplicated notes')
scoreTick=2256;e:stop();assert(#e.notes==3 and e.notes[3].d==240 and e.notes[3].t==2016)
assert(#e.song.parts[1].clips==1,'Recording into an existing clip created a redundant overlapping take')
assert(visible(e,48)and visible(e,60))
e:save();local saved=assert(C.read(sheet));assert(#S.decode(saved.parts[1].notes,saved.bars*384)==3)
assert(#S.native(C.score(saved,1),0).notes==3)
e:undo();assert(S.equal(S.encode(e.notes),original));e:undo(true);assert(#e.notes==3)
e:close();e=E:new(sheet,saved);e:initialise();e:setVisible(true);e.hear=false;assert(#e.notes==3);e:close()
-- Non-zero origin, generated-loop overdub, a distant neighbor and held final note.
scoreTick=0;available=0;started=false
e,sheet=fresh({note(60,768),note(88,3840)},{{name='Loop',start=768,length=1536,loopLength=384},{name='Neighbor',start=3840,length=384}})
assert(#e.notes==5);local before=S.encode(e.notes);e.playFrom=1152;history=#e.undoStack
take={note(52,12,36),note(57,400,220)}
e:preview(true);e:update();assert(e.recordOrigin==1152)
available=1;scoreTick=96;time=time+2200;attack=3;heldPitch=52;e:update();assert(#e.notes==6)
assert(e:noteEditable(e.notes[6]),'A recorded note in a generated repeat was hidden')
scoreTick=640;e:stop();assert(#e.notes==7 and #e.song.parts[1].clips==2)
assert(not e.song.parts[1].clips[1].loopLength and e.song.parts[1].clips[1].length==1536)
assert(e.song.parts[1].clips[2].start==3840 and e.song.parts[1].clips[2].length==384)
assert(take[1].t==12,'UI capture changed the native event timestamp')
e:save();saved=assert(C.read(sheet));local captured=S.decode(saved.parts[1].notes,saved.bars*384)
assert(#captured==7);local found=0
for _,n in ipairs(captured)do if n.n==52 then assert(n.t==1164 and n.d==36);found=found+1 elseif n.n==57 then assert(n.t==1552 and n.d==220);found=found+1 end end
assert(found==2 and #S.native(C.score(saved,1),0).notes==7,'Saving removed notes recorded over a loop')
e:undo();assert(e:currentClip().loopLength==384 and S.equal(before,S.encode(e.notes)))
e:undo(true);assert(#e.notes==7 and not e:currentClip().loopLength);e:close()
-- Empty takes neither add clips nor silently disable a loop.
e=fresh({note(60,0)},{{name='Loop',start=0,length=1536,loopLength=384}})
history=#e.undoStack;scoreTick=0;take={};available=0;before=S.encode(e.notes)
e:preview(true);e:update();scoreTick=5000;e:update();e:stop()
assert(#e.song.parts[1].clips==1 and e:currentClip().loopLength==384 and S.equal(S.encode(e.notes),before)and e.score.bars==16)
e:close()
-- Recording shows actual pitches even with scale/fold filters, then restores filters.
e=fresh();e.scaleEnabled=true;e.scaleOnly=true;e.fold=true;e.rootNote.selected=1;e:rebuildPitches();assert(not e.pitchIndex[61])
history=#e.undoStack;scoreTick=0;take={note(61,0,60)};available=0
e:preview(true);e:update();assert(e.pitchIndex[61]and e.fold and e.scaleOnly)
available=1;scoreTick=60;time=time+2200;e:update();assert(visible(e,61));e:stop()
assert(e.notes[1].n==61 and not e.pitchIndex[61]and e.fold and e.scaleOnly);e:close()
-- A track with no clips gets a real take; a full clip list stays saveable.
e=fresh();e.song.parts[1].clips={};e.playFrom=384;history=#e.undoStack;scoreTick=0;available=0;take={note(60,12,48)}
e:preview(true);e:update();scoreTick=96;e:stop();assert(#e.song.parts[1].clips==1 and e.notes[1].t==396);assert(e:settings());e:close()
e=fresh();e.song.bars=256;e.score.bars=256;e.barsEntry:setText('256');e.song.parts[1].clips={}
for i=1,128 do e.song.parts[1].clips[i]={name='Clip',start=(i-1)*768,length=384}end
e.playFrom=384;history=#e.undoStack;scoreTick=0;e:preview(true);e:update();scoreTick=96;e:stop()
assert(#e.song.parts[1].clips==128 and e.notes[1].t==396);assert(e:settings());e:close()
next=oldNext;DeadAirMidi.recordStop=oldStop;DeadAirMidi.recordNotes=oldPeek;DeadAirMidi.motionState=oldMotion;DeadAirMidi.recordStartOpen=oldStart
connected=false;scoreTick=0;screenWidth,screenHeight,fontHeight=1280,720,14
print('PASS: recording with absent next(), checkpoint before capture, pitch/time follow, completed/held events exactly once, loop overdub and neighbor preservation, save/reopen/native score, undo/redo, empty take and temporary recording pitch filters')
