"""Production Lua modules under Lua 5.1; game ModOptions and base action, simulated UI/network peers."""
from pathlib import Path
import argparse,sys
p=argparse.ArgumentParser();p.add_argument('--game',required=True,type=Path);p.add_argument('--lupa-path',type=Path);a=p.parse_args()
if a.lupa_path:sys.path.insert(0,str(a.lupa_path))
from lupa.lua51 import LuaRuntime
root=Path(__file__).resolve().parents[1];lua=LuaRuntime(unpack_returned_tuples=True)
prelude=(root/'tests/client_stubs.lua').read_text(encoding='utf-8')
lua.execute(prelude)
lua.execute('''
for _,name in ipairs({'OnTickEvenPaused','OnServerCommand','OnClientCommand'})do Events[name]={handlers={},Add=function(f)table.insert(Events[name].handlers,f)end}end
server=false;function isServer()return server end
function UI:setCapture(v)self.capture=v end
function UI:getMouseX()return self.mx or 0 end;function UI:getMouseY()return self.my or 0 end
function UI:onMouseDown()end;function UI:onMouseMove()end;function UI:onMouseUp()end
function UI:drawRect(...)end
function UI:drawRectBorder(...)end;function UI:drawTextCentre(...)end
function UI:setStencilRect(...)end;function UI:clearStencilRect()end
function UI:setX(v)self.x=v end;function UI:setY(v)self.y=v end
function UI:setWidth(v)self.width=v end;function UI:setHeight(v)self.height=v end
function UI:setWantKeyEvents(v)end;function UI:setWantMouseEvents(v)end
function UI:setOnChange(target,fn)self.target=target;self.onChange=fn end
function UI:setToolTipMap(map)self.tooltip=map end
function UI:unfocus()self.focused=false end;function UI:isFocused()return self.focused==true end
fontHeight=14;screenWidth=1280;screenHeight=720
function getTextManager()return {getFontHeight=function()return fontHeight end,MeasureStringX=function(_,font,s)return #s*fontHeight*.48 end}end
function getCore()return {isDoingTextEntry=function()return typing end,getScreenWidth=function()return screenWidth end,getScreenHeight=function()return screenHeight end}end
for i,name in ipairs({'B','SPACE','DELETE','BACK','ESCAPE','LEFT','RIGHT','UP','DOWN','ADD','SUBTRACT','EQUALS','MINUS','F','T','A','C','X','V','D','Z','Y','S','U','E','J','L'})do Keyboard['KEY_'..name]=100+i end
ISContextMenu={get=function()return {options={},addOption=function(self,title,target,fn,...)local o={title=title,target=target,fn=fn,args={...}};self.options[#self.options+1]=o;return o end}end}
function isCtrlKeyDown()return ctrlDown==true end;function isShiftKeyDown()return shiftDown==true end;function isAltKeyDown()return altDown==true end
function UI:setTooltip(t)self.tooltip=t end
function UI:setText(v)self.text=v end;function UI:getText()return self.text end
function UI:setPlaceholderText(v)self.placeholderText=v end
function UI:instantiate()self.javaObject={setMaxTextLength=function()end}end
function UI:setEditable(v)self.editable=v end
ISTextEntryBox=UI:derive('ISTextEntryBox')
function ISTextEntryBox:new(text,x,y,w,h)local o=UI.new(self,x,y,w,h);o.text=tostring(text);return o end
function list(items)return {size=function()return #items end,get=function(_,i)return items[i+1]end}end
function inventory(items)return {getItems=function()return list(items)end}end
local uid=100
function paper()
 uid=uid+1;local p={id=uid,md={},name='Paper',page=''}
 function p:getID()return self.id end;function p:getFullType()return 'Base.SheetPaper2'end
 function p:getModData()return self.md end;function p:seePage()return self.page end
 function p:setName(n)self.name=n end;function p:setCustomName(v)self.custom=v end
 return p
end
local oldInstance=instanceof
function instanceof(v,c)if c=='InventoryItem'then return type(v)=='table' and (v.getFullType~=nil)end;return false end
function player:getOnlineID()return self.id or 1 end
function player:getUsername()return self.name or 'Aza'end
function player:getInventory()return self.inventory end
function item:getType()return self.kind:sub(6)end
function item:getID()return 10 end
player.inventory=inventory({item})
DeadAirMidi.audioReady=function()return audioReady==true end
DeadAirMidi.openAudio=function()audioReady=true end
DeadAirMidi.clock=function()return time end
DeadAirMidi.scoreLoad=function(parts,bpm,ticks,click)loaded={parts=parts,bpm=bpm,ticks=ticks,click=click};return ''end
DeadAirMidi.scoreStart=function(delay)scoreActive=true;scoreDelay=delay end
DeadAirMidi.scoreActive=function()return scoreActive==true end
DeadAirMidi.scoreTick=function()return scoreTick or 0 end
DeadAirMidi.scoreStop=function()scoreActive=false end
DeadAirMidi.scoreHeartbeat=function()scoreHeartbeats=(scoreHeartbeats or 0)+1 end
DeadAirMidi.scoreMetronome=function(v)metro=v end
DeadAirMidi.scoreGain=function(i,g)gains=gains or {};gains[i]=g end
DeadAirMidi.scoreState=function()return {attack=0,velocity=0,held=0,reset=0,resetAttack=0}end
local localDrive=DeadAirMidi.animate
DeadAirMidi.animate=function(actor,...)if actor==player then return localDrive(actor,...)else return 0 end end
DeadAirMidi.recordStart=function(...)recordArgs={...}end
DeadAirMidi.recordStartOpen=function(bpm,channel,count,capacity)recordArgs={bpm,0,channel,count,capacity}end
DeadAirMidi.recordNotes=function()return {}end
DeadAirMidi.recordFull=function()return false end
DeadAirMidi.recordStop=function()return {{n=65,t=12,d=24,v=90}}end
function ZombRand(n)uid=uid+1;return uid%n end
function syncItemModData(p,it)synced=(synced or 0)+1 end
function syncItemFields(p,it)fields=(fields or 0)+1 end
outbox={};requests={}
function sendServerCommand(p,module,command,args)outbox[#outbox+1]={p=p,module=module,command=command,args=args}end
function sendClientCommand(p,module,command,args)requests[#requests+1]={p=p,module=module,command=command,args=args}end
function getOnlinePlayers()return list(peers or {player})end
''')
for path in ['media/lua/shared/ISBaseObject.lua','media/lua/shared/TimedActions/ISBaseTimedAction.lua','media/lua/client/PZAPI/ModOptions.lua']:
    lua.execute((a.game/path).read_text(encoding='utf-8-sig'))
mod=root/'Contents/mods/DeadAir/42/media/lua'
for path in mod.rglob('*.lua'):
    lua.execute('assert(loadstring(...))',path.read_text(encoding='utf-8'))
for name in ['DeadAirScore','DeadAirComposition','DeadAirClipOps','DeadAirPaper','DeadAirKit']:lua.execute((mod/'shared'/f'{name}.lua').read_text(encoding='utf-8'))
for name in ['MusicianSoundfonts','DeadAirInstruments','DeadAirMotion','DeadAirDrumMotion','DeadAirPerformanceAction','DeadAirWorld','DeadAir','DeadAirRoll','DeadAirRollView','DeadAirSongParts','DeadAirArrangement','DeadAirPatterns','DeadAirLibrary','DeadAirClipEditing','DeadAirWorkflow','DeadAirWorkspace','DeadAirAppearance','DeadAirSongEditor','DeadAirSongs']:
    lua.execute((mod/'client'/f'{name}.lua').read_text(encoding='utf-8'))
lua.execute('''
local D,S,C=DeadAir,DeadAirScore,DeadAir.Songs
local volume=D.options:getOption('volume')
assert(volume.min==0 and volume.max==100 and volume:getValue()==30,'Listening volume must span 0 to 100 with the existing default')
volume:setValue(100);D.configure();assert(configuration[4]==1,'Maximum listening volume must reach the engine')
volume:setValue(30)
assert(D.options:getOption('touchResponse'):getValue()==2 and touchResponse==2,'Soft touch should be enabled and reach Java')
D.options:getOption('touchResponse'):setValue(1);D.configure();assert(touchResponse==1,'Natural touch response should remain selectable')
D.options:getOption('touchResponse'):setValue(2);D.configure()
fire('OnGameStart');D.refreshInputs();D.connectionTick();assert(#D.options:getOption('midiInput').values==2)
D.options:getOption('midiInput'):setValue(2);D.options:getOption('connectInput').onclick();assert(connected and selectedDevice==1)
D.guitarEnabled=true;queue.queue={};D.tick();assert(performing and not D.performanceAction)
local panicsBefore=panics or 0
attackSerial=1;held=1;D.tick();assert(D.performanceAction and performing)
D.performanceAction:update();assert(drivenSpeed>0 and (panics or 0)==panicsBefore)
player.moving=true;D.tick();assert(not performing);player.moving=false
item.kind='Base.Violin';D.tick();assert(configuration[1]==8 and performing and not D.performanceAction)
attackSerial=2;D.tick();assert(D.performanceAction.instrument[1]==8)
D.open();local panel=D.panel;D.open();assert(not panel:isVisible() and connected and performing)
D.stop();D.options:getOption('disconnectInput').onclick();assert(not connected)
assert(S.step(32,false)==12 and S.step(32,true)==8)
local q=S.quantize({{n=60,t=13,d=10,v=100}},12,384);assert(q[1].t==12 and q[1].d==12)
q=S.quantize({{n=60,t=383,d=1,v=100}},8,384);assert(q[1].t==376 and q[1].d==8)
assert(not S.decode('60,0,5,90;junk',384));assert(not S.decode('60,383,5,90;',384));assert(not S.decode('128,0,1,90;',384))
local first,extra,third=paper(),paper(),paper();player.inventory=inventory({item,first,extra,third})
local written=paper();written.page='a private note';assert(not S.blank(written))
C.open(first);local e=C.editor;assert(D.editorActive and #e.notes==0)
local drawnPitch=e:pitchAt(e.gridY+3*e.rowH)
e:onMouseDown(e.gridX+8,e.gridY+3*e.rowH);e.mx=e.gridX+80;e.my=e.gridY+3*e.rowH;e:onMouseMove(1,0);e:onMouseUp(0,0)
assert(#e.notes>1 and e.notes[1].d==24 and e.notes[1].n==drawnPitch)
e:save();assert(S.read(first) and first.custom and e.score.revision==1)
local song=S.read(first).song;local part=S.read(first).part
e:paperAction('copy');assert(S.read(extra).song==song and S.read(extra).part==part)
e:paperAction('part');assert(C.editor.item==first and #e.song.parts==2 and e.score.part~=part and #e.notes==0 and S.blank(third))
e=C.editor;connected=true;e:preview(true);e:update();assert(e.transport=='record' and recordArgs[4]==4 and loaded.click and scoreDelay==2000)
paused=true;D.connectionTick();paused=false;assert(e.transport=='record' and scoreActive)
e:stop();assert(#e.notes==1 and e.notes[1].n==65)
e:save();e:paperAction('export');assert(S.read(third).song==song and S.read(third).part~=part and S.read(third).notes~='')
e:switchPart(1);e:save();e:close();assert(not D.editorActive)
local stale,err=DeadAirPaper.write(player,{mode='save',item=third.id,revision=0,score=S.read(third)});assert(not stale and err:find('changed'))
local result=DeadAirPaper.write(player,{mode='copy',item=first.id,blank=extra.id});assert(not result)
-- Preview does not need a controller; movement cancels an in-world score.
item.kind='Base.Keytar';connected=false;C.play(third);C.tick();assert(C.solo and scoreActive and D.scorePart==0)
player.moving=true;C.tick();assert(not scoreActive and not C.solo);player.moving=false
-- Missing Java APIs provide a message, not a crash.
local load=DeadAirMidi.scoreLoad;DeadAirMidi.scoreLoad=nil;C.play(third);assert(D.notice:find('updated'));DeadAirMidi.scoreLoad=load
-- Refresh follows the visible selection, not the old numeric slot or saved index.
local midiInput=D.options:getOption('midiInput')
local savedDevices=devices
midiInput.element=ISComboBox:new(0,0,200,20);midiInput.element.selected=2
D.refreshInputs();devices={savedDevices[2],savedDevices[1]};D.connectionTick()
assert(midiInput:getValue()==1 and midiInput.element.selected==1)
D.options:getOption('connectInput').onclick();assert(selectedDevice==0)
D.refreshInputs();devices={savedDevices[1]};D.connectionTick()
assert(midiInput:getValue()==2 and midiInput.values[2]:find('disconnected') and not D.options:getOption('connectInput').isEnabled)
selectedDevice=-99;D.options:getOption('connectInput').onclick();assert(selectedDevice==-99)
D.refreshInputs();devices=savedDevices;D.connectionTick()
assert(midiInput:getValue()==2 and D.options:getOption('connectInput').isEnabled)
D.options:getOption('connectInput').onclick();assert(selectedDevice==1)
-- Connect applies the slider values currently shown, including all-channel selection.
local channel=D.options:getOption('channel');channel:setValue(1)
channel.element={getCurrentValue=function()return 0 end,setCurrentValue=function()end}
D.options:getOption('connectInput').onclick();assert(configuration[3]==-1)
channel.element=nil;midiInput.element=nil;connected=false;D.notice=nil
assert(D.options:getOption('midiBackend')==nil and D.options:getOption('audioDriver')==nil)
D.refreshInputs();D.connectionTick();assert(midiBackend==2 and D.scannedBackend==2)
connected=false;D.notice=nil
print('PASS: built-in Java MIDI routing, device reorder, missing-port protection, replug selection and unsaved all-channel setting')
print('PASS: automatic first-note performance, equipped timbre switching, Mod Options connection, score schema, editor drawing, paper copying/parts, MIDI recording flow and solo cancellation')
testFirst=first;testThird=third
''')
lua.execute((mod/'server/DeadAirServer.lua').read_text(encoding='utf-8'))
lua.execute('''
server=true;client=false;outbox={};local N,S=DeadAirServer,DeadAirScore
local p1=player;p1.x=1;p1.y=1;local p2=setmetatable({id=2,name='Second',x=2,y=1,held={kind='Base.Keytar',getFullType=item.getFullType,getType=item.getType,getCondition=item.getCondition,condition=5}}, {__index=player})
local p3=setmetatable({id=3,name='Listener',x=3,y=1},{__index=player})
p1.held=item;item.kind='Base.Keytar';local original=testFirst;original.md.DeadAirComposition.parts[1].profile=0
p2.inventory=inventory({testThird});p1.inventory=inventory({original});p3.inventory=inventory({});peers={p1,p2,p3}
local function cmd(p,c,args)time=time+60;N.command('DeadAir',c,p,args or {})end
cmd(p1,'host',{item=original.id});local sid;for id in pairs(N.sessions)do sid=id end;assert(sid)
cmd(p2,'join',{id=sid,item=testThird.id});assert(#N.sessions[sid].members==2,outbox[#outbox].args.message)
cmd(p1,'ready',{id=sid,ready=true});cmd(p1,'start',{id=sid});assert(N.sessions[sid].phase=='gathering')
cmd(p2,'ready',{id=sid,ready=true});cmd(p1,'start',{id=sid});assert(N.sessions[sid].phase=='loading')
cmd(p1,'loaded',{id=sid,ok=true});assert(not N.sessions[sid].start)
cmd(p2,'loaded',{id=sid,ok=true});assert(N.sessions[sid].start==time+3000)
local starts={};for _,v in ipairs(outbox)do if v.command=='start'then starts[v.p:getOnlineID()]=v.args.at end end
assert(starts[1]==starts[2] and starts[2]==starts[3])
local p4=setmetatable({id=4,name='Late listener',x=3,y=1,inventory=inventory({})},{__index=player});peers={p1,p2,p3,p4}
time=N.sessions[sid].start+500;N.tick()
local lateStart;for _,v in ipairs(outbox)do if v.p==p4 and v.command=='start'then lateStart=v.args.at end end
assert(lateStart==starts[1], 'Late listener received a fresh timeline instead of the original start')
cmd(p3,'leave',{});assert(N.sessions[sid])
p2.moving=true;time=time+500;N.tick();assert(not N.sessions[sid]);p2.moving=false
-- Ownership checks, wrong songs and replayed sheet writes.
local before=original.md.DeadAirComposition.revision
cmd(p2,'write',{mode='save',item=original.id,revision=before,score=S.read(original)});assert(original.md.DeadAirComposition.revision==before)
cmd(p1,'host',{item=original.id});for id in pairs(N.sessions)do sid=id end
local own=testThird.md.DeadAirScore.song;testThird.md.DeadAirScore.song='wrong'
cmd(p2,'join',{id=sid,item=testThird.id});assert(#N.sessions[sid].members==1);testThird.md.DeadAirScore.song=own
cmd(p1,'leave',{});assert(not N.sessions[sid])
cmd(p1,'host',{item=original.id});for id in pairs(N.sessions)do sid=id end
cmd(p1,'ready',{id=sid,ready=true});cmd(p1,'start',{id=sid});cmd(p1,'loaded',{id=sid,ok=true})
assert(N.sessions[sid].start);cmd(p1,'ready',{id=sid,ready=false});assert(not N.sessions[sid],'Readiness withdrawal during countdown did not cancel')
print('PASS: two simulated musicians and a listener; server ownership, matching song, explicit readiness, load acknowledgements, identical future start, movement cancellation and unauthorized writes')
server=false;client=true;local C=DeadAir.Songs;C.cleanup();D=DeadAir;D.guitarEnabled=false
time=20000;C.pings={[time-20]=true};C.command('DeadAir','clock',{sent=time-20,server=50000});assert(C.offset==30010)
local score=DeadAirScore.read(original)
C.command('DeadAir','prepare',{id='test',bpm=score.bpm,bars=score.bars,count=2})
C.command('DeadAir','part',{id='test',index=1,part={score=score,owner=1,x=1,y=1,z=0}})
C.tick();assert(not C.net.loaded)
C.command('DeadAir','part',{id='test',index=2,part={score=score,owner=2,x=2,y=1,z=0}})
C.tick();assert(C.net.loaded)
C.command('DeadAir','start',{id='test',at=53010});C.tick();assert(scoreDelay==3000 and #loaded.parts==2 and D.scorePart==0)
C.command('DeadAir','stop',{id='test',message='stopped'});assert(not C.net and not scoreActive)
print('PASS: client clock offset, complete-part preload barrier, shared-clock transport, local part selection and server stop')
''')
print('PASS: every shipped Lua file parses as Lua 5.1')
lua.execute((root/'tests/roll_test.lua').read_text(encoding='utf-8'))
lua.execute((root/'tests/song_parts_test.lua').read_text(encoding='utf-8'))
lua.execute((root/'tests/studio_test.lua').read_text(encoding='utf-8'))
lua.execute((root/'tests/library_test.lua').read_text(encoding='utf-8'))
lua.execute((root/'tests/clip_editing_test.lua').read_text(encoding='utf-8'))
lua.execute((root/'tests/clip_timing_test.lua').read_text(encoding='utf-8'))
lua.execute((root/'tests/workflow_test.lua').read_text(encoding='utf-8'))
lua.execute((root/'tests/customization_test.lua').read_text(encoding='utf-8'))
lua.execute((root/'tests/recording_regression_test.lua').read_text(encoding='utf-8'))

lua.execute('client=false;server=false;DeadAir.cleanup();player.inventory=inventory({item});player.moving=false')
lua.execute((root/'tests/world_test.lua').read_text(encoding='utf-8'))
lua.execute((root/'tests/motion_test.lua').read_text(encoding='utf-8'))
