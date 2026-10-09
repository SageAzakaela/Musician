"""Real live protocol/server/client Lua with simulated players and Java audio; no network/hardware."""
from pathlib import Path
import argparse,sys
p=argparse.ArgumentParser();p.add_argument('--game',required=True,type=Path);p.add_argument('--lupa-path',type=Path);a=p.parse_args()
if a.lupa_path:sys.path.insert(0,str(a.lupa_path))
from lupa.lua51 import LuaRuntime
root=Path(__file__).resolve().parents[1];mod=root/'Contents/mods/DeadAir/42/media/lua'
lua=LuaRuntime(unpack_returned_tuples=True)
lua.execute((root/'tests/client_stubs.lua').read_text())
lua.execute('''
for _,name in ipairs({'OnTickEvenPaused','OnServerCommand','OnClientCommand'})do Events[name]={handlers={},Add=function(f)table.insert(Events[name].handlers,f)end}end
function list(a)return {size=function()return #a end,get=function(_,i)return a[i+1]end}end
function player:getOnlineID()return self.id or 1 end
function player:getUsername()return self.name or 'Test'end
function item:getType()return self.kind:sub(6)end
function getOnlinePlayers()return list(peers)end
function isServer()return server~=false end
outbox={};requests={}
function sendServerCommand(p,module,command,args)outbox[#outbox+1]={p=p,module=module,command=command,args=args}end
function sendClientCommand(p,module,command,args)requests[#requests+1]={p=p,module=module,command=command,args=args}end
function clone(t)local r={};for k,v in pairs(t)do r[k]=v end;return r end
p1=player;p1.id=1;p1.x=1;p1.y=1
p2=setmetatable({id=2,x=2,y=1,held=item},{__index=player})
p3=setmetatable({id=3,x=3,y=1,held=item},{__index=player})
far=setmetatable({id=4,x=100,y=100},{__index=player})
upstairs=setmetatable({id=5,x=1,y=1,z=1},{__index=player})
peers={p1,p2,p3,far,upstairs}
function frame(seq,events,state,at,epoch)
 return {v=1,epoch=epoch or 1,seq=seq,profile=1,at=at or (seq-1)*50,events=events or '',state=state or '',reset=false}
end
''')
for name in ['DeadAirScore','DeadAirKit','DeadAirLiveProtocol']:lua.execute((mod/'shared'/(name+'.lua')).read_text())
for name in ['DeadAirServer','DeadAirLiveServer']:lua.execute((mod/'server'/(name+'.lua')).read_text())
lua.execute('''
local L,P=DeadAirLiveServer,DeadAirLiveProtocol
function resetServer()L.streams={};L.rates={};L.nextCheck=0;outbox={};time=time+2000;p1.moving=false;p1.dead=false;p1.held=item;peers={p1,p2,p3,far,upstairs};item.kind='Base.GuitarAcoustic' end
function emit(packet)L.command('DeadAirLive','frame',p1,packet)end
resetServer()
local f=frame(1,'0,144,60,90;','144,60,90;');f.owner=2;f.x=999
emit(f)
assert(#outbox==2 and outbox[1].p==p2 and outbox[2].p==p3)
assert(outbox[1].args.owner==1 and outbox[1].args.x==1 and outbox[1].args.events==f.events and not outbox[1].args.reset,'first notes and authenticated owner/position must be retained')
firstRelay=clone(outbox[1].args)
local n=#outbox;emit(f);assert(#outbox==n,'duplicates must not relay')
local wrong=frame(2);wrong.profile=8;emit(wrong);assert(not L.streams[1] and outbox[#outbox].command=='stop','wrong equipped instrument must end stream')
resetServer();emit(frame(1));p1.moving=true;L.tick();assert(not L.streams[1],'movement must stop live music')
resetServer();emit(frame(1));p1.dead=true;L.tick();assert(not L.streams[1],'death must stop live music')
resetServer();emit(frame(1));peers={p2,p3};L.tick();assert(not L.streams[1] and not L.rates[1],'disconnect releases stream and limits')
resetServer();emit(frame(1));time=time+1501;L.tick();assert(not L.streams[1],'timeout must stop live music')
server=false;local online=getOnlinePlayers;getOnlinePlayers=function()error('single-player must not access server online roster')end;L.tick();getOnlinePlayers=online;server=true
resetServer();emit(frame(1));p2.x=100;L.tick();assert(not L.streams[1].listeners[2] and outbox[#outbox].command=='stop','walking out of range stops listener')
p2.x=2;time=time+500;emit(frame(2,'500,144,60,90;','144,60,90;',500));assert(L.streams[1].listeners[2])
local joined;for _,m in ipairs(outbox)do if m.command=='frame'and m.p==p2 and m.args.seq==2 then joined=m.args end end
assert(joined.reset and joined.events=='' and joined.state=='144,60,90;','returning listener gets current state, not past strikes')
resetServer();local bad=frame(1);bad.world={x='oops',y=1,z=0};emit(bad);assert(not L.streams[1],'malformed placed instrument must not relay')
resetServer();DeadAirServer.sessions={fake={members={{player=p1}}}};emit(frame(1));assert(not L.streams[1],'written ensemble participant cannot simultaneously inject live MIDI');DeadAirServer.sessions={}
for _,events in ipairs({'0,144,60,128;','0,240,60,90;','0,176,74,90;','0,144,60,90;;','garbage'})do
 resetServer();emit(frame(1,events));assert(not L.streams[1])
end
resetServer();local bad=frame(1);bad.at=0/0;emit(bad);assert(not L.streams[1])
resetServer();emit(frame(1,'','144,60,90;144,60,80;'));assert(not L.streams[1],'duplicate snapshot pitches rejected')
resetServer();emit(frame(1,string.rep('0,144,60,90;',129)));assert(not L.streams[1],'event count bounded')
resetServer();for i=1,41 do time=time+1;emit(frame(i))end;assert(not L.streams[1],'packet flood must be stopped')
resetServer();local many=string.rep('0,144,60,90;',128);for i=1,16 do time=time+1;emit(frame(i,many,'',0))end;assert(not L.streams[1],'event flood must be stopped')
resetServer();for i=10,41 do L.streams[i]={}end;emit(frame(1));assert(not L.streams[1],'global stream count bounded')
resetServer();emit(frame(1));local epoch=L.streams[1].epoch;L.command('DeadAirLive','stop',p2,{owner=1,epoch=1});assert(L.streams[1],'another player cannot stop owner stream')
L.command('DeadAirLive','stop',p1,{epoch=1});assert(not L.streams[1])
print('PASS: real live server Lua; nearby routing, no echo/spoofing, first notes, late join, movement/death/disconnect/timeouts, instrument ownership, malformed data and traffic bounds')
''')
lua.execute((a.game/'media/lua/shared/ISBaseObject.lua').read_text(encoding='utf-8-sig'))
lua.execute((a.game/'media/lua/client/PZAPI/ModOptions.lua').read_text(encoding='utf-8-sig'))
lua.execute((mod/'client/DeadAirInstruments.lua').read_text())
lua.execute('DeadAirWorld={context=function()end,atInstrument=function()return true end,valid=function()return true end}')
lua.execute((mod/'client/DeadAir.lua').read_text())
lua.execute('''
audioReady=true;received={};stopped={};capture=false;client=true;player=p3
DeadAirMidi.liveCapture=function(v)capture=v end
DeadAirMidi.livePoll=function()local f=nextFrame or {};nextFrame=nil;return f end
DeadAirMidi.liveReceive=function(owner,packet,gain)received[#received+1]={owner=owner,packet=clone(packet),gain=gain};return true end
DeadAirMidi.liveGain=function(owner,gain)lastGain=gain end
DeadAirMidi.liveStop=function(owner)stopped[#stopped+1]=owner end
DeadAirMidi.liveStopAll=function()allStopped=true end
DeadAirMidi.liveState=function()return {attack=1,velocity=90,held=1}end
DeadAirMidi.audioReady=function()return audioReady end
DeadAirMidi.openAudio=function()audioReady=true;opens=(opens or 0)+1 end
DeadAir.Songs={remoteMotion=function(net,p,stop)motionCalls=(motionCalls or 0)+1 end,world=function()return nil end}
''')
lua.execute((mod/'client/DeadAirLive.lua').read_text())
lua.execute('''
local D,L=DeadAir,DeadAir.Live
local function empty(t)for _ in pairs(t)do return false end;return true end
function deliver(seq,events,state,at,epoch)local f=frame(seq,events,state,at,epoch);f.owner=1;f.x=1;f.y=1;f.z=0;L.command('DeadAirLive','frame',f);return f end
connected=false;performing=false
local f=deliver(1,'0,144,60,90;','144,60,90;')
assert(#received==1 and received[1].owner==1 and received[1].gain>0,'listener must work without MIDI controller')
L.command('DeadAirLive','frame',f);assert(#received==1,'duplicate packet rejected before native audio')
local own=clone(f);own.owner=3;L.command('DeadAirLive','frame',own);assert(#received==1,'own echoed MIDI must never be rendered twice')
L.command('DeadAirLive','stop',{owner=1,epoch=1,seq=1});assert(not L.remote[1] and stopped[#stopped]==1)
L.command('DeadAirLive','frame',f);assert(not L.remote[1],'late pre-stop packet cannot revive notes')
deliver(2,'50,144,60,90;','144,60,90;');assert(L.remote[1],'a later packet can resume after returning into range')
D.options:getOption('hearLive'):setValue(false);L.tick();assert(empty(L.remote) and allStopped)
deliver(3);assert(empty(L.remote),'listening opt-out must ignore incoming music')
D.options:getOption('hearLive'):setValue(true)
audioReady=false;deliver(4,'150,144,62,90;','144,62,90;');assert(L.remote[1].waiting)
L.tick();assert(opens==1);L.tick();assert(received[#received].packet.reset and received[#received].packet.events=='','cold listener recovers current notes after asynchronous audio startup')
time=time+1600;L.tick();assert(empty(L.remote),'client independently expires a missing stop')
connected=true;performing=true;player.moving=false;player.dead=false;paused=false;D.editorActive=false
nextFrame=frame(1);L.nextSend=0;L.tick();assert(capture and requests[#requests].module=='DeadAirLive'and requests[#requests].command=='frame')
D.editorActive=true;L.tick();assert(not capture and requests[#requests].command=='stop','editor monitoring must be private')
D.editorActive=false;D.scorePart=0;L.tick();assert(not capture,'score playback must not be re-broadcast as live MIDI');D.scorePart=nil
D.options:getOption('broadcastLive'):setValue(false);L.tick();assert(not capture)
D.options:getOption('broadcastLive'):setValue(true);time=time+100;nextFrame=frame(1);L.tick();D.stop();assert(not capture and requests[#requests].command=='stop','movement/action stop hook ends publication immediately')
L.cleanup();assert(empty(L.remote)and empty(L.seen)and not capture)
print('PASS: real live client Lua; no-controller listening, duplicate/echo/stale-stop rejection, range return, listening opt-out, asynchronous startup, timeout, editor/score privacy and immediate lifecycle cleanup')
''')
