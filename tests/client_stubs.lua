
require=function() end
function getText(x) return x end
Keyboard={KEY_F10=68,KEY_F11=87,KEY_F12=88}
UIFont={Small=1,Large=2}
Events={}
for _,name in ipairs({'OnFillInventoryObjectContextMenu','OnFillWorldObjectContextMenu','OnKeyPressed','OnTick','OnPlayerDeath','OnMainMenuEnter','OnGameStart'}) do
 Events[name]={handlers={},Add=function(f) table.insert(Events[name].handlers,f) end}
end
function fire(name,...) for _,f in ipairs(Events[name].handlers) do f(...) end end
local saved={};local index=0
function getFileWriter(name) if name=='MusicianEditorLayout.ini' then return nil end;saved={};return {write=function(self,s)table.insert(saved,s)end,close=function()end} end
function getFileReader(name) if name=='MusicianEditorLayout.ini' then return nil end;index=0;return {readLine=function()index=index+1;return saved[index]end,close=function()end} end
luautils={split=function(s,sep)local t={};for p in s:gmatch('[^'..sep..'\r\n]+')do t[#t+1]=p end;return t end}
UI={}
function UI:derive(name)local o={};setmetatable(o,{__index=self});o.__index=o;return o end
function UI:new(x,y,w,h)local o={x=x,y=y,width=w,height=h,children={},options={},selected=1};setmetatable(o,{__index=self});return o end
function UI:initialise()end
function UI:addChild(child)self.children[#self.children+1]=child end
function UI:setTitle(t)self.title=t end
function UI:setEnable(b)self.enabled=b end
function UI:setVisible(b)self.visible=b end
function UI:isVisible()return self.visible==true end
function UI:bringToTop()self.raised=true end
function UI:addToUIManager()self.inManager=true end
function UI:removeFromUIManager()self.inManager=false end
function UI:drawText(...)end
function UI:prerender()end
function UI:clear()self.options={} end
function UI:addOption(s)self.options[#self.options+1]=s end
ISPanel=UI:derive('ISPanel');ISComboBox=UI:derive('ISComboBox');ISButton=UI:derive('ISButton')
function ISButton:new(x,y,w,h,title,target,callback)
 local b=UI.new(self,x,y,w,h);b.title=title;b.target=target;b.callback=callback;return b
end
function click(button)button.callback(button.target,button)end
item={kind='Base.GuitarAcoustic',condition=5}
function item:getFullType()return self.kind end
function item:getCondition()return self.condition end
player={x=100,y=100,z=0,dead=false,sleep=false,moving=false,held=item}
function player:getPrimaryHandItem()return self.held end
function player:isDead()return self.dead end
function player:isAsleep()return self.sleep end
function player:isPlayerMoving()return self.moving end
function player:isAiming()return self.aiming end
function player:getVehicle()return self.vehicle end
function player:getX()return self.x end
function player:getY()return self.y end
function player:getZ()return self.z end
function player:getSquare()return getCell():getGridSquare(math.floor(self.x),math.floor(self.y),self.z)end
function player:faceThisObject(o)self.facing=o end
function player:shouldBeTurning()return false end
function player:setTimedActionToRetrigger(v)end
function player:setIsFarming(v)end
function player:clearVariable(k)self.vars[k]=nil end
player.vars={};player.secondary={marker='original secondary item'}
function player:getSecondaryHandItem()return self.secondary end
function player:StartAction(a)a.lua:start()end
ISLogSystem={logAction=function()end}
LuaTimedActionNew={new=function(lua,character)
 local a={lua=lua}
 function a:setOverrideHandModelsObject(primary,secondary) character.overridePrimary=primary;character.overrideSecondary=secondary end
 function a:setActionAnim(name)character.animation=name end
 function a:setAnimVariable(key,value)assert(type(value)=='string' or type(value)=='boolean','Native anim setter requires string/boolean');character.vars[key]=tonumber(value)or value end
 function a:forceComplete()character.overridePrimary=nil;character.overrideSecondary=nil;lua:perform()end
 function a:isStarted()return true end
 return a
end}
queue={queue={}}
function queue:indexOf(action)for i,a in ipairs(self.queue)do if a==action then return i end end;return -1 end
function queue:onCompleted(action)local i=self:indexOf(action);if i>0 then table.remove(self.queue,i)end end
function queue:removeFromQueue(action)self:onCompleted(action)end
function queue:resetQueue()self.queue={}end
ISTimedActionQueue={getTimedActionQueue=function()return queue end,add=function(action)
 table.insert(queue.queue,action)
 if #queue.queue==1 and action.begin then action:begin()end
 return queue
end}
ISEquipWeaponAction={new=function(self,p,it,time,primary,twoHands)return {equip=true,item=it}end}
ISInventoryPaneContextMenu={transferIfNeeded=function(p,it)transferred=it end}
function getSpecificPlayer(i)if i==0 then return player end end
function instanceof(v,c)return v==item end
paused=false;typing=false;client=false;time=0
function isClient()return client end
function isGamePaused()return paused end
function getTimestampMs()return time end
function getCore()return {isDoingTextEntry=function()return typing end,getScreenWidth=function()return 1280 end,getScreenHeight=function()return 720 end} end
noiseCount=0
function addSound(p,x,y,z,r,v)noiseCount=noiseCount+1;noiseRadius=r end
connected=false;performing=false;busy=false;activity=100;devices={'Keystation 49 MK3','MIDIIN2 (Keystation 49 MK3)'}
DeadAirMidi={
 midiBackend=function(value)midiBackend=value end,
 refresh=function()refreshes=(refreshes or 0)+1 end,
 inputCount=function()return #devices end,inputName=function(i)return devices[i+1]end,
 inputKey=function(i)return devices[i+1] or '' end,
 inputIndex=function(key)for i,name in ipairs(devices)do if name==key then return i-1 end end;return -1 end,
 noteCount=function()return 12 end,inputStatus=function()return 'MIDI: 12 notes / channels 1,2,3,4,5,6' end,
 inputRouteStatus=function()return 'Performance: ready / all MIDI channels' end,
 connected=function()return connected end,performing=function()return performing end,busy=function()return busy end,
 status=function()return 'Ready' end,messageCount=function()return 123 end,lastNote=function()return 60 end,lastVelocity=function()return 100 end,
activeVoices=function()return performing and (voices or 3) or 0 end,
 connect=function(i)selectedDevice=i;connected=true end,disconnect=function()connected=false;performing=false end,
 perform=function(v)performing=v and connected;if v then voices=3 end end,configure=function(...)configuration={...}end,
 heartbeat=function()heartbeats=(heartbeats or 0)+1 end,consumeActivity=function()return activity end,
 panic=function()panics=(panics or 0)+1;voices=0;held=0;motionReset=motionReset+1 end
}
attackSerial=0;attackVelocity=100;held=0;motionReset=0
DeadAirMidi.motionState=function()return {attack=attackSerial,velocity=attackVelocity,held=held,reset=motionReset,resetAttack=attackSerial,drums=drumTelemetry or {}}end
DeadAirMidi.animate=function(character,action,clip,speed,phase)
 assert(character==player and action==player.animation)
 drivenSpeed=speed;drivenPhase=phase;drivenClip=clip;drivenTracks=drivenTracks or {};drivenTracks[clip]={speed=speed,phase=phase};return 1
end
animationReady=true
DeadAirMidi.animationReady=function(clip)lastCheckedClip=clip;return animationReady end
DeadAirMidi.attackSerial=function()return attackSerial end
DeadAirMidi.attackVelocity=function()return attackVelocity end
DeadAirMidi.guitarStatus=function()return 'FluidSynth / GeneralUser GS' end
DeadAirMidi.soundStatus=DeadAirMidi.guitarStatus
DeadAirMidi.audioResponse=function(value)audioResponse=value end
DeadAirMidi.touchResponse=function(value)touchResponse=value end
DeadAirMidi.audioDriver=function(value)audioDriver=value end
DeadAirMidi.audioStatus=function()return 'Audio: Fast / output buffer 10.7 ms' end
DeadAirMidi.guitarMode=function(value)guitarSampleMode=value end
