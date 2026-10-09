-- Complete-song authoring on one sheet, with no instrument in the inventory.
local D,C,S,A=DeadAir,DeadAir.Songs,DeadAirScore,DeadAirComposition
C.cleanup();C.drafts={};client=false;server=false;player.held=nil;player.moving=false
local sheet=paper();player.inventory=inventory({sheet});connected=true
C.open(sheet);local e=C.editor
assert(performing and e.monitoring and configuration[1]==0 and not e.transport)
local sent,broadcasts,noises=#requests,#outbox,noiseCount
local beats=heartbeats;D.tick();assert(heartbeats>beats and not D.performanceAction)
paused=true;D.connectionTick();paused=false;assert(performing and not e.transport)
assert(#requests==sent and #outbox==broadcasts and noiseCount==noises,'Private monitoring triggered world performance')
local transpose=D.options:getOption('transpose');local oldTranspose=transpose:getValue();transpose:setValue(12)
D.configure();assert(configuration[2]==0,'Editor monitoring must match the written MIDI pitches')
e.hear=false;e:checkpoint();e.notes={{n=60,t=0,d=96,v=90}};e.partEntry:setText('Keys')
click(e.partButton);assert(#e.song.parts==2 and #e.notes==0 and e.item==sheet and player.inventory:getItems():size()==1)
e.instrument.selected=9;e.instrument.onChange(e.instrument.target,e.instrument)
assert(configuration[1]==8 and performing)
e.partEntry:setText('Strings');e:checkpoint();e.notes={{n=72,t=384,d=192,v=100}}
e.partPicker.selected=1;e.partPicker.onChange(e.partPicker.target,e.partPicker)
assert(e.activePart==1 and #e.notes==1 and e.notes[1].n==60 and e.instrument.selected==1 and #e.undoStack==3)
-- Undo is chronological across tracks: the last edit was the strings, even after selecting Keys.
e:undo();assert(e.activePart==2 and #e.notes==0);e:undo(true);assert(e.activePart==1)
e:switchPart(2);assert(e.notes[1].n==72 and e.instrument.selected==9 and #e.undoStack==3)
e:save();assert(not e.saving and not e.dirty and #A.read(sheet).parts==2 and S.read(sheet).profile==8)
local keysId=e.song.parts[1].part;assert(not keysId:find('^draft%-'))
e:undo();assert(e.activePart==2 and #e.notes==0);e:undo(true);assert(e.notes[1].n==72)
assert(e.song.parts[1].part==keysId,'Undo after first save lost permanent part identities')
e:switchPart(1);assert(#e.undoStack==3);e:switchPart(2);assert(#e.undoStack==3)
e.bpmEntry:setText('96');assert(e:settings());assert(A.score(e.song,1).bpm==96 and A.score(e.song,2).bpm==96)
e:switchPart(1);e.barsEntry:setText('1');assert(e:settings() and e.score.bars>=8,'Auto length silently cut off another part')
e.barsEntry:setText('8');assert(e:settings())
e:toggleTrack(1,"solo");local parts=e:previewParts(false);assert(#parts==2 and e:audible(1)and not e:audible(2));e:toggleTrack(1,"solo")
e.previewScope.selected=2;parts=e:previewParts(false);assert(#parts==2 and parts[2].profile==8)
parts=e:previewParts(true);assert(#parts[e.activePart].notes==0 and parts[2].notes[1].n==72)
e:preview(false);e:update();assert(e.transport=='preview' and #loaded.parts==2 and performing)
e:switchPart(2);assert(e.activePart==1 and e.partPicker.selected==1,'Changed parts while transport was running')
e:stop();e:update();assert(performing and not e.transport)
click(e.monitorButton);e:update();assert(not performing and not e.monitoring)
click(e.monitorButton);assert(performing)
connected=false;e:update();assert(not e.monitoring);connected=true;e:update();assert(performing)
player.dead=true;e:update();assert(not performing);player.dead=false;e:update();assert(performing)
e:save();e:close();assert(not performing and not D.editorActive and not C.drafts[sheet.id])
-- Saved song is independent of the paper/instrument inventory and survives reopen.
connected=false;C.open(sheet);e=C.editor;assert(#e.song.parts==2 and e.notes[1].n==60 and not e.dirty)
e:switchPart(2);e:checkpoint();e.notes[1].n=74;e:close();assert(C.drafts[sheet.id])
C.open(sheet);e=C.editor;assert(e.activePart==2 and e.notes[1].n==74 and e.dirty,'Unsaved part draft was lost on reopen')
local copy,export=paper(),paper();player.inventory=inventory({sheet,copy,export})
e:paperAction('copy');assert(S.blank(copy),'Unsaved draft copied an old version silently')
e:save();e:paperAction('copy');assert(#A.read(copy).parts==2 and A.read(copy).song==e.song.song)
e:paperAction('export');assert(not export.md.DeadAirComposition and S.read(export).part==e.score.part and S.read(export).profile==8)
assert(S.decode(S.read(export).notes,3072)[1].n==74)
local saved=A.read(sheet);local rev=saved.revision
local result,err=DeadAirPaper.write(player,{mode='saveSong',item=sheet.id,revision=rev-1,composition=saved});assert(not result and err:find('changed'))
local foreign=paper();result,err=DeadAirPaper.write(player,{mode='saveSong',item=foreign.id,revision=0,composition=saved});assert(not result)
local invalid=A.copy(saved);invalid.parts[2].part=invalid.parts[1].part;assert(not A.validate(invalid))
invalid=A.copy(saved);invalid.parts[2].notes='72,3070,96,90;';assert(not A.validate(invalid))
result,err=DeadAirPaper.write(player,{mode='saveSong',item=sheet.id,revision=rev,composition=invalid});assert(not result and A.read(sheet).revision==rev)
-- Full-song saves use the same ownership/sync boundary as individual sheets.
server=true;local priorSynced,priorFields=synced or 0,fields or 0
result=DeadAirPaper.write(player,{mode='saveSong',item=sheet.id,revision=rev,composition=saved})
assert(result and synced==priorSynced+1 and fields==priorFields+1 and result.composition.revision==rev+1)
server=false;C.saved(result);assert(e.song.revision==rev+1 and not e.saving)
for i=3,8 do e:addPart()end;assert(#e.song.parts==8)
e:addPart();assert(#e.song.parts==8 and e.message:find('eight'))
-- Validate and preview a maximum-size arrangement without a held instrument or controller.
for i,p in ipairs(e.song.parts)do local notes={};for j=1,512 do notes[j]={n=(j+i)%128,t=(j-1)*3,d=1,v=127}end;p.notes=S.encode(notes)end
e:loadPart(1);assert(e:settings());e.previewScope.selected=2;e:preview(false);e:update()
assert(e.transport=='preview' and #loaded.parts==8 and #loaded.parts[8].notes==512 and not connected)
e:stop();e:save();assert(#A.read(sheet).parts==8);e:close()
assert(#requests==sent and #outbox==broadcasts and noiseCount==noises,'Authoring or preview broadcast audio or created zombie noise')
transpose:setValue(oldTranspose);player.held=item;player.inventory=inventory({item});C.drafts={};D.configure()
-- Record mode must keep the selected track sound, even with a different world instrument.
local recordSheet=paper();player.inventory=inventory({recordSheet,item});player.held=item;connected=true
C.open(recordSheet);local recordEditor=C.editor
for _,profile in ipairs({0,4,9})do
    recordEditor.instrument.selected=profile+1;recordEditor:updateMonitor()
    recordEditor:preview(true);recordEditor:update()
    assert(recordEditor.transport=='record' and configuration[1]==profile and configuration[2]==0,'Recording replaced the selected piano/banjo/drum profile')
    assert(#loaded.parts[recordEditor.activePart].notes==0,'Recording doubled the active part in its backing track')
    recordEditor:stop()
end
recordEditor:close();C.drafts={};player.inventory=inventory({item});D.configure()
print('PASS: one-paper eight-part compositions; real button/callback dispatch, isolated notes/undo and instruments, shared tempo/length, permanent IDs, drafts/save/reopen, whole-song copies and individual exports, stale/invalid/ownership checks and server sync; private idle/paused MIDI monitoring and no-instrument/no-controller previews; piano/banjo/drum recording keeps selected profile without active-part doubling')
