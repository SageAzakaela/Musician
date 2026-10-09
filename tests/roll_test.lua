local E,S=DeadAirSongEditor,DeadAirScore
local function fresh(notes)
    ctrlDown=false;shiftDown=false;altDown=false;typing=false
    local score=S.new();score.notes=S.encode(notes or {});local e=E:new(paper(),score);e:initialise();e:setVisible(true)
    e.hear=false;e.pitchScroll=44;e.rowH=16;e:layout();e.firstTick=0;e.viewTicks=1536
    return e
end
local function pos(e,t,n)local row=e.pitchIndex[n];return e.gridX+t/e.viewTicks*e.gridW,e.gridY+(row-e.pitchScroll+.5)*e.rowH end
local function down(e,t,n)local x,y=pos(e,t,n);e:onMouseDown(x,y);return x,y end
local function drag(e,x,y)e.mx=x;e.my=y;e:onMouseMove(0,0)end
local function up(e)e:onMouseUp(0,0)end
local function note(n,t,d,v)return {n=n,t=t,d=d,v=v or 100}end
local e=fresh();down(e,1,72);local x,y=pos(e,145,72);drag(e,x,y);up(e)
assert(#e.notes==7 and #e.undoStack==1,'Fast paint must fill crossed cells with one undo')
for i,n in ipairs(e.notes)do assert(n.t==(i-1)*24 and n.d==24)end
e:undo();assert(#e.notes==0);e:undo(true);assert(#e.notes==7)
local x,y=pos(e,1,72);e:onRightMouseDown(x,y);x,y=pos(e,145,72);drag(e,x,y);up(e);assert(#e.notes==0 and #e.undoStack==2)
e:undo();assert(#e.notes==7)
-- Unsnapped recordings do not jump to the pointer or a grid on a simple click.
e=fresh({note(72,13,90)});e.mode='select';local n=e.notes[1]
local x,y=down(e,50,72);up(e);assert(n.t==13 and n.d==90 and #e.undoStack==0)
down(e,50,72);drag(e,x+2,y+1);up(e);assert(n.t==13 and #e.undoStack==0)
down(e,50,72);drag(e,x+48/e.viewTicks*e.gridW,y-2*e.rowH);up(e);assert(n.t==61 and n.n==74 and #e.undoStack==1)
-- Both edges resize, and a group stays inside time/pitch bounds.
e=fresh({note(72,96,96)});e.mode='select';n=e.notes[1]
local nx,ny,nw=e:noteRect(n);e:onMouseDown(nx+nw-1,ny+8);assert(e.drag.kind=='end');drag(e,nx+nw-1+48/e.viewTicks*e.gridW,ny+8);up(e);assert(n.d==144 and e.lastLength==144)
nx,ny,nw=e:noteRect(n);e:onMouseDown(nx+1,ny+8);assert(e.drag.kind=='start');drag(e,nx+1+24/e.viewTicks*e.gridW,ny+8);up(e);assert(n.t==120 and n.d==120)
e.length.selected=2;assert(e:noteLength()==120)
e.notes={note(126,0,48),note(127,96,48)};e:selectAll();e:nudge(-96,12);assert(e.notes[1].t==0 and e.notes[1].n==126 and e.notes[2].n==127)
e:nudge(e:ticks(),0);assert(e.notes[2].t+e.notes[2].d==e:ticks() and e.notes[2].t-e.notes[1].t==96)
-- Ctrl-click only selects. A drag duplicates, undo removes only the copy.
e=fresh({note(72,96,96)});e.mode='select';ctrlDown=true;x,y=down(e,144,72);up(e);assert(#e.notes==1)
down(e,144,72);drag(e,x+96/e.viewTicks*e.gridW,y);up(e);ctrlDown=false;assert(#e.notes==2 and e.notes[2].t==192)
e:undo();assert(#e.notes==1 and e.notes[1].t==96)
-- Box selection, selected-only quantize, duplicate and clipboard paste.
e=fresh({note(72,13,70),note(71,100,50),note(65,450,24)});e.mode='select'
x,y=down(e,0,73);local xx,yy=pos(e,180,70);drag(e,xx,yy);up(e);assert(e:selectedCount()==2)
e:quantize();assert(e.notes[1].t==24 and e.notes[2].t==96 and e.notes[3].t==450)
e:paste(true);assert(#e.notes==5 and e:selectedCount()==2);e:copySelection(false);e.cursorTick=768;e:paste(false);assert(#e.notes==7)
e:deleteSelected();assert(#e.notes==5);e:undo();assert(#e.notes==7)
e.cursorTick=e:ticks()-1;local oldEnd=e:ticks();e:paste(false);assert(e:ticks()==oldEnd and #e.notes==7);e.editWholeTrack=true;e:paste(false);assert(e:ticks()>oldEnd and #e.notes==9);local before=S.encode(e.notes)
e.notes={};for i=1,S.MAX_NOTES do e.notes[i]=note(60,(i-1)*3,1)end;e:selectAll();before=S.encode(e.notes);e:paste(true);assert(S.equal(S.encode(e.notes),before))
-- Escape aborts a stroke; pointer leaving the grid clamps to the song.
e=fresh();down(e,24,72);e:onKeyPress(Keyboard.KEY_ESCAPE);assert(#e.notes==0 and not e.capture and #e.undoStack==0)
e.viewTicks=e:ticks();down(e,e:ticks()-24,72);drag(e,e.width+100,e.gridY+5);up(e)
for _,n in ipairs(e.notes)do assert(n.t+n.d<=e:ticks() and n.n>=0 and n.n<=127)end
-- Keyboard shortcuts must not eat text, or alter notes during playback.
e=fresh({note(72,24,24)});e:selectAll();e.titleEntry.focused=true
assert(not e:isKeyConsumed(Keyboard.KEY_B));e:onKeyPress(Keyboard.KEY_DELETE);assert(#e.notes==1)
e.titleEntry.focused=false;typing=true;assert(not e:isKeyConsumed(Keyboard.KEY_B));typing=false
e:onKeyPress(Keyboard.KEY_B);assert(e.mode=='select');e.transport='preview';e:onKeyPress(Keyboard.KEY_DELETE);assert(#e.notes==1);e.transport=nil
ctrlDown=true;e:onKeyPress(Keyboard.KEY_D);ctrlDown=false;assert(#e.notes==2)
ctrlDown=true;shiftDown=false;e:onKeyPress(Keyboard.KEY_Z);assert(#e.notes==1);shiftDown=true;e:onKeyPress(Keyboard.KEY_Z);assert(#e.notes==2);ctrlDown=false;shiftDown=false
-- Time/pitch zoom stays anchored; overview travels without editing.
e=fresh({note(72,300,48)});e.firstTick=384;local anchor=e.gridX+e.gridW*.4;local tick=e:tickAt(anchor);e:zoom(.5,anchor);assert(math.abs(e:tickAt(anchor)-tick)<.001)
local py=e.gridY+e.gridH*.4;local pitch=e:pitchAt(py);e:zoomPitch(1.2,py);assert(e:pitchAt(py)==pitch)
before=S.encode(e.notes);e:onMouseDown(e.gridX+e.gridW*.95,e.overviewY+3);up(e);assert(e.firstTick>384 and S.encode(e.notes)==before)
e.notes={note(48,0,48),note(72,96,48),note(80,192,48)};e.fold=true;e:rebuildPitches();assert(#e.pitches==3 and e.pitches[2]==72);e:fitNotes(false);assert(e.firstTick==0 and e.viewTicks==384)
e.mode='select';x,y=down(e,120,72);drag(e,x,y-e.rowH);up(e);assert(e.notes[2].n==80,'Fold drag follows displayed pitches')
-- Velocity, triplet grid and fixed lengths.
e=fresh({note(72,96,96,80)});e.mode='select';altDown=true;x,y=down(e,140,72);drag(e,x,y-30);up(e);altDown=false;assert(e.notes[1].v==110)
e.velocity:setText('200');e:setVelocity();assert(e.notes[1].v==127)
e.grid.selected=6;e.triplet=true;e.length.selected=1;assert(e:step()==8 and e:noteLength()==8)
e.length.selected=6;assert(e:noteLength()==64)
-- Font/screen layout must leave all controls on-screen and the roll usable.
for _,size in ipairs({{1329,760,14},{1280,720,16},{1024,768,18},{1920,1080,22}})do
    screenWidth,screenHeight,fontHeight=size[1],size[2],size[3];e=fresh()
    for _,details in ipairs({false,true})do for _,velocity in ipairs({false,true})do for _,scale in ipairs({false,true})do
        e.details=details;e.showVelocity=velocity;e.scaleEnabled=scale;e:rebuildPitches();e:layout();e:prerender();e:render()
        assert(e.gridH>=96,'Not enough grid height at '..screenWidth..' / '..fontHeight)
        assert(e.gridY+e.gridH<=e.overviewY and e.overviewY+e.overviewH<e.height)
        local visible={}
        for _,c in ipairs(e.children)do if c.visible~=false then
            assert(c.x>=0 and c.y>=0 and c.x+c.width<=e.width and c.y+c.height<=e.height,'Control outside window')
            visible[#visible+1]=c
        end end
        for i=1,#visible do for j=i+1,#visible do local a,b=visible[i],visible[j]
            assert(not(a.x<b.x+b.width and a.x+a.width>b.x and a.y<b.y+b.height and a.y+a.height>b.y),'Overlapping controls')
        end end
    end end end
end
screenWidth=1280;screenHeight=720;fontHeight=14
-- Short auditions use the existing sampler and cannot replace real playback.
e=fresh();e.hear=true;time=time+100;e:audition(60,90);assert(e.auditioning and loaded.parts[1].notes[1].n==60 and loaded.click==false)
e.transport='preview';local previous=loaded;e:audition(66,90);assert(loaded==previous);e.transport=nil;e:stopAudition();assert(not scoreActive)
e.hear=false;e:audition(60,90);assert(not e.auditioning)
e:close()
-- Scales are a view/drawing aid, never destructive pitch quantization.
e=fresh({note(60,0,24),note(61,24,24),note(64,48,24)});before=S.encode(e.notes)
e.scaleEnabled=true;e.scaleOnly=true;e.rootNote.selected=1;e.scaleType.selected=1;e:scaleChanged()
assert(e.pitchIndex[60] and not e.pitchIndex[61] and e.pitchIndex[64] and S.encode(e.notes)==before)
e:selectAll();assert(e:selectedCount()==2,'Hidden notes must not be silently selected for deletion')
e.notes={};e:rebuildPitches();e.pitchScroll=e.pitchIndex[84];e:clampView();e.mode='draw'
x,y=down(e,0,76);xx,yy=pos(e,240,60);drag(e,xx,yy);up(e)
assert(#e.notes==11);for _,n in ipairs(e.notes)do assert(e:inScale(n.n),'Fast diagonal drawing introduced an out-of-scale pitch')end
e.notes={note(72,24,96),note(76,144,96)};e:rebuildPitches();e:selectAll();e.mode='select'
x,y=down(e,60,72);drag(e,x,y-e.rowH);up(e);assert(e.notes[1].n==74 and e.notes[2].n==77)
e:nudge(0,1);assert(e.notes[1].n==76 and e.notes[2].n==79)
before=S.encode(e.notes);e.rootNote.selected=10;e.scaleType.selected=2;e:scaleChanged()
assert(e:inScale(69) and e:inScale(60) and not e:inScale(61) and S.encode(e.notes)==before)
e.scaleOnly=false;e:scaleChanged();assert(#e.pitches==128)
e.scaleEnabled=false;e:scaleChanged();assert(#e.pitches==128)
-- Local arrangements: identity, nested bags, duplicate revisions and current draft.
local oldInstance=instanceof
function instanceof(v,c)if c=='InventoryContainer' and v.bag then return true end;return oldInstance(v,c)end
local function sheet(part,revision,profile)
    local p=paper();local s=S.new();s.song='song-1';s.part=part;s.partName=part;s.revision=revision or 1;s.profile=profile or 0;s.notes=S.encode({note(60,0,96)})
    p.md.DeadAirScore=s;return p
end
local current,second,copy,unrelated=sheet('first'),sheet('second',1,8),sheet('second',2,2),sheet('other')
unrelated.md.DeadAirScore.song='another-song'
local bag={bag=true,getFullType=function()return 'Base.Bag'end,getInventory=function()return inventory({copy,unrelated})end}
player.inventory=inventory({current,second,bag})
local composition=DeadAirComposition.collect(DeadAirComposition.fromScore(S.read(current)),player.inventory)
e=E:new(current,composition);e:initialise();e:setVisible(true);e.hear=false;e.notes={note(67,96,192)};assert(e:settings())
e.previewScope.selected=2;local parts=e:previewParts(false)
assert(#parts==2 and parts[1].notes[1].n==67 and parts[2].profile==2,'Use current draft and latest duplicate, once each')
parts=e:previewParts(true);assert(#parts==2 and #parts[1].notes==0 and #parts[2].notes==1,'Recording keeps only other parts as backing')
local sent=#requests;local broadcasts=#outbox;DeadAir.Songs.net=nil;DeadAir.Songs.lobby=nil
e:preview(false);e:update();assert(#loaded.parts==2 and #requests==sent and #outbox==broadcasts,'Private preview sent a multiplayer command')
paused=true;DeadAir.Songs.editor=e;DeadAir.connectionTick();assert(e.transport=='preview' and scoreActive);paused=false;e:stop();DeadAir.Songs.editor=nil
copy.md.DeadAirScore.bpm=90;local unchanged=e:previewParts(false);assert(#unchanged==2 and #unchanged[2].notes==1,'Imported song must not depend on changing external paper')
local filtered=DeadAirComposition.collect(DeadAirComposition.fromScore(S.read(current)),inventory({current,copy}));assert(#filtered.parts==1)
copy.md.DeadAirScore.bpm=120;copy.md.DeadAirScore.bars=4;filtered=DeadAirComposition.collect(DeadAirComposition.fromScore(S.read(current)),inventory({current,copy}));assert(#filtered.parts==1)
copy.md.DeadAirScore.bars=8
local many={current};for i=1,8 do many[#many+1]=sheet('part-'..i)end;player.inventory=inventory(many)
local limited,err=DeadAirComposition.collect(DeadAirComposition.fromScore(S.read(current)),player.inventory);assert(#limited.parts==1 and err:find('eight'))
e:toggleTrack(1,"solo");parts=e:previewParts(false);assert(#parts==2 and e:audible(1)and not e:audible(2))
instanceof=oldInstance;e:close()
print('PASS: scales preserve notes; legacy arrangement import includes nested bags and latest duplicates, excludes mismatched parts and limits eight; private draft preview, recording backing and paused playback')
print('PASS: piano-roll paint/erase interpolation, undo/redo, no-jump selection, both-edge resize, bounded group moves, Ctrl-drag copies, marquee, clipboard, triplets, velocity, zoom, fold, typing safety, audition ownership, four screen/font layouts')
