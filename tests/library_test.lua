-- Exercise the production library and editor together. Native audio/catalog are stand-ins here.
local S,C,E,P,D=DeadAirScore,DeadAirComposition,DeadAirSongEditor,DeadAirPatterns,DeadAir
client=false;server=false;connected=false;D.Songs.cleanup();player.dead=false
local patterns=0
for kind=1,3 do for _,row in ipairs(P.rows(kind,''))do
    patterns=patterns+1
    for _,key in ipairs({0,6,11})do for _,beats in ipairs({1,4,8})do
        local c=P.make(kind,row.index,key,5,beats)
        assert(c.length>0 and #c.notes>0)
        for _,n in ipairs(c.notes)do assert(n.n>=0 and n.n<=127 and n.t>=0 and n.d>0 and n.t+n.d<=c.length and n.v<=127)end
    end end
end end
assert(patterns==37)
local minor=P.make(2,8,0,3,4);assert(minor.notes[4].n==58 and minor.notes[10].n==55 and minor.notes[11].n==59)
local native={};for _,name in ipairs({'libraryRefresh','libraryState','librarySearch','libraryRequest','libraryResult'})do native[name]=DeadAirMidi[name]end
local revision,loads,searches,refreshes=1,0,0,0
DeadAirMidi.libraryRefresh=function()refreshes=refreshes+1 end
DeadAirMidi.libraryState=function()return {revision=revision,status='Catalog ready',roots={'Drum pack','Chord pack'}}end
DeadAirMidi.librarySearch=function(q,source,offset)searches=searches+1;return {count=61,rows={{id='clip',name='Imported clip',path='Drum pack / Rock.mid'}}}end
DeadAirMidi.libraryRequest=function(id)loads=loads+1;return loads end
local result={state='loading'}
DeadAirMidi.libraryResult=function(token,group,mapping)return result end
local function editor()
    local e=E:new(paper(),S.new());e:initialise();e:setVisible(true);e.hear=false;e:toggleLibrary();return e,e.libraryPanel
end
for _,v in ipairs({{1024,768,18},{1280,720,14},{1920,1080,22}})do
    screenWidth,screenHeight,fontHeight=unpack(v);local e,b=editor();e.scaleEnabled=true;e.showVelocity=true;e:layout()
    assert(e.gridW>200 and e.gridH>=96,'Library leaves no usable piano roll')
    assert(e.gridX+e.gridW<=b.x and b.x+b.width<=e.width)
    for _,folders in ipairs({false,true})do b.showFolders=folders;b:layout();b:prerender()
        assert(b.listY+b.listH<=b.bottomY,'Library list overlaps clip controls')
        local visible={};for _,c in pairs(b.children)do if c.visible~=false then
            assert(c.x>=0 and c.y>=0 and c.x+c.width<=b.width+1 and c.y+c.height<=b.height+1,'Library control out of bounds')
            for _,old in ipairs(visible)do assert(c.x+c.width<=old.x or old.x+old.width<=c.x or c.y+c.height<=old.y or old.y+old.height<=c.y,'Library controls overlap')end
            visible[#visible+1]=c
        end end
    end;e:close()
end
screenWidth,screenHeight,fontHeight=1280,720,14
local e,b=editor();assert(#b.rows==16);b:selectRow(1);assert(#b.raw.notes==3)
b.root.selected=3;b:regenerate();assert(b.raw.notes[1].n==50)
b.shift:setText('12');b.stretch.selected=3;local clip=b:clip();assert(clip.notes[1].n==62 and clip.length==768)
b.shift:setText('999');assert(not b:clip());b.shift:setText('0');b.stretch.selected=2
-- A real drag from the browser row into the arrangement.
local dx,dy=e.trackW+4,e.arrY+e.arrRulerH+10
b:onMouseDown(20,b.listY+5);b.mx=dx-b.x;b.my=dy-b.y;b:onMouseMove(1,1);assert(e.libraryGhost)
b:onMouseUpOutside(b.mx,b.my);assert(#e.notes==3 and not e.libraryGhost and not b.capture)
local saved=S.encode(e.notes);local c=b:clip()
assert(not e:insertLibraryClip(c,{part=1,at=0},false) and S.equal(saved,S.encode(e.notes)),'Import overwrote an occupied phrase')
assert(e:insertLibraryClip(c,{part=1,at=0},true) and #e.notes==6);e:undo();assert(#e.notes==3)
assert(e:insertLibraryClip(c,{part=1,at=384},false) and #e.notes==6);e:undo();assert(#e.notes==3)
e.instrument.selected=2;e:settings();assert(e:insertLibraryClip(c,{new=true,at=768},false)and #e.song.parts==2 and e.instrument.selected==2 and e.notes[1].t==768)
e:undo();assert(#e.song.parts==1 and #e.notes==3);e:addPart();e.instrument.selected=2;e:settings()
-- Drums ignore transpose, choose the kit on empty tracks, and restore profile on undo.
b.source.selected=3;b:refreshRows();b:selectRow(1);b.shift:setText('12');c=b:clip();assert(c.drums and c.notes[1].n==36)
assert(not e:insertLibraryClip(c,{part=1,at=768},false))
assert(e:insertLibraryClip(c,{part=2,at=0},false)and e.instrument.selected==10);e:undo();assert(e.instrument.selected==2 and #e.notes==0)
-- Private audition does not follow the arrangement, or inherit track mute/solo.
e.song.parts[2].mute=true;e.playFrom=384;e.firstTick=384;e.arrFirst=0
e:previewLibrary(c);e:update();assert(e.transport=='library'and loaded.ticks==c.length and loaded.parts[1].profile==9 and not loaded.click)
local gain=gains[0];assert(gain==1,'Library preview must not apply master volume twice');e:applyTrackGains();assert(gains[0]==gain)
scoreTick=99999;e:update();assert(e.firstTick==384 and e.arrFirst==0);scoreTick=0
b:refreshRows();assert(not e.transport)
-- Catalog query, async drop queuing, mapping failures and recovery, and cancellation.
b.source.selected=4;b:refreshRows();b:selectRow(1);assert(b.request and not b.raw)
b:insertAt({part=2,at=0});assert(b.queued and #e.notes==0)
result={state='ready',clip=c};b:pollResult();assert(not b.queued and #e.notes==#c.notes)
e:undo();b:selectRow(1);result={state='error',message='Choose a percussion sound',groups={'Percussion'}};b:pollResult();assert(b.error and not b.raw and #b.group.options==2)
result={state='ready',clip=c};b:remap();assert(b.raw and not b.error)
result={state='loading'};b:selectRow(1);b:insertAt({part=2,at=0});e:toggleLibrary();assert(not b.queued and not b.capture)
result={state='ready',clip=c};e:toggleLibrary();b:pollResult();assert(#e.notes==0)
b.search:setText('funk');local before=searches;b:poll();time=time+250;b:poll();assert(searches>before and b.query=='funk')
b.search.focused=true;local mode=e.mode;e:onKeyPress(Keyboard.KEY_B);assert(e.mode==mode);b.search.focused=false
e:close()
-- All capacity rejections leave the current song intact.
e,b=editor();c=P.make(1,1,0,3,4)
for i=2,8 do e:addPart()end;local count=#e.song.parts
assert(not e:insertLibraryClip(c,{new=true,at=0},false) and #e.song.parts==count)
assert(not e:insertLibraryClip(c,{part=8,at=S.MAX_BARS*384},false)and #e.notes==0)
e:close()
for _,name in ipairs({'libraryRefresh','libraryState','librarySearch','libraryRequest','libraryResult'})do DeadAirMidi[name]=native[name]end
print('PASS: 37 built-in patterns, library layout at three sizes, real editor drag/drop, overlap/layer/undo, instrument choice, private audition, async drop/mapping recovery, search/focus/cancel and capacity rejection')
