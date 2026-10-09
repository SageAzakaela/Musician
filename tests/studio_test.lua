-- Studio split: real production editor paths, long sheets and manual-stop recording.
local S,C,E,D=DeadAirScore,DeadAirComposition,DeadAirSongEditor,DeadAir
client=false;server=false;D.Songs.cleanup();connected=false
local p=paper();player.inventory=inventory({p});player.dead=false
local score=S.new();score.bars=160
local notes={};for i=1,1400 do notes[i]={n=48+i%24,t=(i-1)*40,d=24,v=100}end
score.notes=S.encode(notes);assert(type(score.notes)=='table'and #score.notes>1)
local legacy=C.fromScore(score);assert(legacy.version==3 and #S.decode(legacy.parts[1].notes,160*384)==1400)
assert(not S.decode({[1]='60,0,1,90;',extra='bad'},384))
assert(not S.decode({'60,0,1,90;',{}},384))
local e=E:new(p,legacy);e:initialise();e:setVisible(true);e.hear=false;D.Songs.editor=e;D.editorActive=true
e:save();assert(not e.saving and C.read(p).bars==160 and not p.md.DeadAirScore)
assert(#S.decode(S.read(p).notes,160*384)==1400,'Long saved performance sheet did not round-trip')
local copy,export=paper(),paper();player.inventory=inventory({p,copy,export})
e:paperAction('copy');e:paperAction('export');assert(#S.decode(S.read(copy).notes,160*384)==1400 and #S.decode(S.read(export).notes,160*384)==1400)
e:close()
-- Phrases move the original note events, and save/undo never creates a phantom old clip.
score=S.new();score.bars=8;score.notes='60,0,96,90;64,384,96,90;'
e=E:new(paper(),score);e:initialise();e:setVisible(true);e.hear=false
local part=e.song.parts[1];part.clips={{name='Intro',start=0,length=768},{name='Answer',start=1536,length=768}}
e.notes[3]={n=67,t=1536,d=96,v=90};assert(e:settings());e:fitArrangement();e:prerender()
local hit;for _,r in ipairs(e.trackHits)do if r.clip==1 then hit=r end end;assert(hit)
local x,y=hit.x+20,hit.y+15;e:onMouseDown(x,y);assert(e.drag.kind=='clipGroup')
e.mx=x+384/e.arrTicks*e.arrW;e.my=y;e:onMouseMove(1,0);e:onMouseUp(e.mx,y)
assert(e.notes[1].t==384 and e.notes[2].t==768 and e.notes[3].t==1536)
assert(e:settings()and #e.song.parts[1].clips==2 and e.song.parts[1].clips[1].start==384,'Move produced a phantom phrase')
e:undo();assert(e.notes[1].t==0 and e.song.parts[1].clips[1].start==0)
e:undo(true);assert(e.notes[1].t==384 and e.song.parts[1].clips[1].start==384)
e:prerender();for _,r in ipairs(e.trackHits)do if r.clip==1 then hit=r end end
e.arrGrid.selected=3 -- quarter-note arrangement snapping for this trim test
x,y=hit.x+hit.w-2,hit.y+12;e:onMouseDown(x,y);assert(e.drag.kind=='clipEnd')
e.mx=x-768/e.arrTicks*e.arrW;e.my=y;e:onMouseMove(-1,0);e:onMouseUp(e.mx,y)
assert(e.song.parts[1].clips[1].length==480 and e.notes[2].t+e.notes[2].d==864,'Phrase trim cut a note')
e:undo();assert(e.song.parts[1].clips[1].length==768)
e:prerender();for _,r in ipairs(e.trackHits)do if r.clip==1 then hit=r end end
x,y=hit.x+20,hit.y+12;e:onMouseDown(x,y);e.mx=x+1152/e.arrTicks*e.arrW;e.my=y;e:onMouseMove(1,0);e:onMouseUp(e.mx,y)
assert(e.song.parts[1].clips[1].start==384,'A phrase overwrote its neighbor')
e:focusClip(1);e:duplicatePhrase();assert(#e.notes==5 and #e.song.parts[1].clips==3)
local duplicated=e.song.parts[1].clips[e.activeClip];assert(duplicated.start>=2304)
e:deletePhrase();assert(#e.notes==3);e:undo();assert(#e.notes==5 and #e.song.parts[1].clips==3)
e:focusClip(1);e.phraseEntry:setText('New intro');e:renamePhrase();assert(e.song.parts[1].clips[1].name=='New intro');e:undo();assert(e.song.parts[1].clips[1].name=='Intro')
e:addPart();e:toggleTrack(1,'solo');assert(e:audible(1)and not e:audible(2));e:toggleTrack(1,'solo');e:toggleTrack(2,'mute');assert(not e:audible(2))
local volume=D.options:getOption('volume');local oldVolume=volume:getValue();volume:setValue(60)
e.monitor=false;configuration=nil
e:preview(false);e:update();assert(e.transport=='preview'and gains[0]==1 and gains[1]==0)
assert(configuration[4]==.6,'Disconnected preview with monitoring off must apply master volume')
e:toggleTrack(2,'mute');assert(gains[1]==1 and e.transport=='preview','Unmuting must not apply master volume twice')
e:stop();e:close();volume:setValue(oldVolume)
-- Simulate a take crossing 64 bars and 512 notes, including incremental preview and a held final note.
p=paper();player.inventory=inventory({p});connected=true;D.Songs.open(p);e=D.Songs.editor;e.hear=false
local stop,peek=DeadAirMidi.recordStop,DeadAirMidi.recordNotes
local take={};for i=1,800 do take[i]={n=50+i%20,t=(i-1)*48,d=24,v=100}end
DeadAirMidi.recordNotes=function(from)local out={};for i=from+1,math.min(600,#take)do out[#out+1]=S.copy(take[i])end;return out end
DeadAirMidi.recordStop=function()return S.copy(take)end
e:preview(true);e:update();assert(loaded.ticks==0 and recordArgs[2]==0 and recordArgs[5]==S.MAX_NOTES)
time=time+205000;scoreTick=39000;e:update();assert(e.transport=='record'and e.score.bars>64 and #e.notes==600,'Take stopped at old boundary')
time=time+200;e:update();assert(#e.notes==600,'Incremental notes duplicated')
e:stop();assert(#e.notes==800 and e.notes[800].t==799*48 and e.score.bars==math.ceil(39000/384))
e:save();assert(C.read(p).bars>64 and #S.decode(S.read(p).notes,C.read(p).bars*384)==800)
e:close();D.Songs.open(p);e=D.Songs.editor;assert(#e.notes==800);e:close()
DeadAirMidi.recordStop=stop;DeadAirMidi.recordNotes=peek;scoreTick=0;connected=false
print('PASS: Studio track/phrase hit testing, note-preserving move/duplicate/delete/undo, rename, live mute/solo, 160-bar paged paper save/copy/export, v1 migration and open recording across 64 bars/512 notes with incremental preview and exact Stop retention')
