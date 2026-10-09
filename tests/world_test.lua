-- Runs in lua_test.py's game-Lua harness, with explicit native-world stand-ins.
local squares={}
local function squareAt(x,y,z)
    local key=x..','..y..','..z
    if not squares[key] then
        local s={x=x,y=y,z=z,objects={},standable=true,wall=false}
        function s:getX()return self.x end
        function s:getY()return self.y end
        function s:getZ()return self.z end
        function s:getObjects()
            return {size=function()return #s.objects end,get=function(_,i)return s.objects[i+1]end}
        end
        squares[key]=s
    end
    return squares[key]
end
function getCell()return {getGridSquare=function(_,x,y,z)return squareAt(x,y,z)end}end
AdjacentFreeTileFinder={
    privTrySquare=function(src,dest)return src and dest and dest.standable and not dest.wall end,
    privTrySquareForWalls=function(src,dest)return src and dest and not src.wall and not dest.wall end,
}
ISWorldObjectContextMenu={setTest=function()worldMenuAvailable=true;return true end}
ISWalkToTimedAction={new=function(_,character,location)
    local walk={character=character,location=location,walk=true}
    function walk:begin()self.action={};walking=true end
    function walk:forceComplete()walking=false;queue:onCompleted(self)end
    return walk
end}
local function objectAt(x,y,name,custom,group)
    local s=squareAt(x,y,0)
    local object={square=s,spriteName=name,index=0,custom=custom,group=group}
    function object:getSquare()return self.square end
    function object:getObjectIndex()return self.index end
    function object:getSprite()
        return {getName=function()return object.spriteName end,getProperties=function()
            return {get=function(_,key)if key=='CustomName' then return object.custom elseif key=='GroupName' then return object.group end end}
        end}
    end
    s.objects[#s.objects+1]=object;s.standable=false
    return object
end
local function reset()
    DeadAir.cleanup();queue.queue={};connected=true;animationReady=true
    squares={};player.x=100.5;player.y=100.5;player.z=0;player.moving=false
    item.kind='Base.GuitarAcoustic';player.held=item;voices=3;held=0
    DeadAir.options:getOption('guitarMode'):setValue(true);DeadAir.options:apply()
end
local function finishWalk()
    local walk=DeadAir.approachAction;assert(walk and walk.walk and not performing)
    player.x=walk.location.x+0.5;player.y=walk.location.y+0.5;player.z=walk.location.z
    walk:forceComplete();player.moving=false;DeadAir.tick();assert(not DeadAir.approachAction)
    attackSerial=attackSerial+1;held=1;DeadAir.tick()
end

reset()
local count=0
for kind,def in pairs(DeadAir.instruments) do
    item.kind=kind;player.held=item
    DeadAir.startPerformance()
    assert(performing and configuration[1]==def[1],kind..' did not select its voice')
    local action=DeadAir.performanceAction
    assert(action and action.instrument==def)
    if def.clip then assert(player.animation==def.action and lastCheckedClip==def.clip) end
    if def.hand=='bow' then assert(player.overridePrimary=='DeadAir.ViolinBow' and player.overrideSecondary==def.visualModel) end
    if def.sustain then
        held=1;attackSerial=attackSerial+1;action:update();time=time+1000;action:update()
        assert(player.vars[action.speedVariable]>0,'Sustained instrument stopped moving')
        held=0;time=time+200;action:update();assert(player.vars[action.speedVariable]==0,'Audio tail kept gesture alive');voices=0
    end
    DeadAir.stop();assert(not performing and not DeadAir.performanceAction and #queue.queue==0)
    count=count+1
end
assert(count==14)
for _,kind in ipairs({'Base.GuitarPick','Base.LargemouthBass','Base.GuitarAcousticNeck_Broken','Base.Guitarcase'}) do
    item.kind=kind;DeadAir.startPerformance();assert(not performing,'Accessory/weapon fragment incorrectly playable')
end

local pianoCount=0
for tile,layout in pairs(DeadAirInstruments.pianoTiles) do
    reset()
    local piano=objectAt(105,105,tile,'Piano','Western')
    local target=DeadAirWorld.describe(piano);assert(target)
    DeadAirWorld.select(target);connected=true
    assert(not performing and #queue.queue==1,'Piano sounded before reaching it')
    player.moving=true;DeadAir.tick();assert(DeadAir.approachAction,'Automatic mode cancelled its own walk')
    assert(target.stand.x==105+layout.dx and target.stand.y==105+layout.dy)
    finishWalk();assert(performing and configuration[1]==0 and player.animation=='DeadAirPiano'..layout.side)
    assert(player.overridePrimary==nil and player.overrideSecondary==nil and player.held==item)
    assert(DeadAirPerformanceAction.waitToStart(DeadAir.performanceAction)==false and player.facing==piano)
    local action=DeadAir.performanceAction
    DeadAir.show();DeadAir.panel:hide();fire('OnTick')
    assert(performing and connected and DeadAir.worldTarget==target and DeadAir.performanceAction==action)
    DeadAir.open();assert(DeadAir.panel:isVisible() and DeadAir.worldTarget==target and performing)
    -- Removing the furniture must stop the sustained action and audio.
    piano.index=-1;DeadAir.performanceAction:update()
    assert(not performing and not DeadAir.performanceAction)
    pianoCount=pianoCount+1
end
assert(pianoCount==8)

reset()
local piano=objectAt(102,102,'recreational_01_8','Piano','Western')
local target=DeadAirWorld.describe(piano)
squareAt(102,103,0).standable=false
DeadAirWorld.select(target);connected=true;DeadAir.startPerformance()
assert(not performing and not DeadAir.performanceAction and #queue.queue==0 and DeadAir.notice:find('Clear'))
squareAt(102,103,0).standable=true;squareAt(102,103,0).wall=true
DeadAir.startPerformance();assert(not performing and not DeadAir.performanceAction)
squareAt(102,103,0).wall=false
player.z=1;DeadAir.startPerformance();assert(not performing and DeadAir.notice:find('floor'))
player.z=0;DeadAir.startPerformance();assert(DeadAir.approachAction)
queue.queue[#queue.queue+1]={marker='unrelated'}
DeadAir.stop();assert(not performing and not DeadAir.performanceAction and not walking)
assert(#queue.queue==1 and queue.queue[1].marker=='unrelated','Stop cleared a subsequent user action')
queue.queue={};DeadAirWorld.select(target);queue.queue={};fire('OnTick')
assert(not DeadAir.performanceAction and not DeadAir.approachAction,'Cancelled path left a stuck performance')

reset()
for group,profile in pairs({Kick=13,Tom=14,Snare=15}) do
    local drum=objectAt(101,102,'test_'..group,'Drum',group)
    local description=DeadAirWorld.describe(drum)
    assert(description and description.instrument[1]==profile)
    DeadAirWorld.select(description);connected=true
    if DeadAir.approachAction then finishWalk() end
    assert(performing and DeadAir.performanceAction.animated)
    attackSerial=attackSerial+1;DeadAir.performanceAction:update();time=time+70;DeadAir.performanceAction:update()
    local clip=group=='Kick' and 'DeadAirPedalR' or group=='Snare' and 'DeadAirDrumL' or 'DeadAirDrumR'
    assert(drivenTracks[clip].phase>0,'Placed drum did not strike the correct limb')
    player.x=player.x+2;fire('OnTick');assert(not performing)
    DeadAir.worldTarget=nil
end
assert(not DeadAirWorld.describe(objectAt(110,110,'metal','Drum','Metal')))
assert(not DeadAirWorld.describe(objectAt(111,110,'stool','Stool','Piano')))

reset()
local keyboard=objectAt(103,104,'recreational_01_40','Piano','Black Grand')
local body=objectAt(103,103,'recreational_01_42','Piano','Black Grand')
local menu={options={},addOption=function(self,label,target,callback)self.options[#self.options+1]={target=target,callback=callback}end}
DeadAirWorld.context(0,menu,{body},true)
assert(worldMenuAvailable and #menu.options==0)
DeadAirWorld.context(0,menu,{body,body},false)
assert(#menu.options==1 and menu.options[1].target.object==keyboard)
DeadAir.show();local oldPanel=DeadAir.panel;oldPanel:hide()
menu.options[1].callback(menu.options[1].target)
assert(DeadAir.worldTarget.object==keyboard and DeadAir.panel==oldPanel and not oldPanel:isVisible())
oldPanel:hide()
item.kind='Base.Flute';DeadAir.equipInstrument(item,0)
assert(not DeadAir.worldTarget and queue.queue[1].equip and not DeadAir.panel:isVisible())
queue.queue={};DeadAir.cleanup()
print('PASS: 14 held item types, 8 piano keyboard tiles, 3 placed drums, sustained poses, approach, walls, floor, removal and cancellation')
for _,layout in ipairs({{56,58,57,0,-1},{59,60,61,-1,0},{64,69,65,0,1},{67,66,68,1,0}})do
  for front=0,1 do
    reset();local fx,fy=layout[4],layout[5];local rx,ry=-fy,fx
    local kick=objectAt(105+fx,105+fy,'recreational_01_'..layout[1],'Drum','Kick')
    local snare=objectAt(105-rx+fx*front,105-ry+fy*front,'recreational_01_'..layout[2],'Drum','Snare')
    assert(not DeadAirKit.build(kick),'Incomplete kit accepted')
    local tom=objectAt(105+rx+fx*front,105+ry+fy*front,'recreational_01_'..layout[3],'Drum','Tom')
    local kit=DeadAirKit.build(kick);assert(kit and kit.x==105 and kit.y==105 and DeadAirKit.valid(kit))
    assert(DeadAirKit.near(snare).object==kick and DeadAirKit.near(tom).object==kick)
    local menu={options={},addOption=function(self,label,target,callback)self.options[#self.options+1]={target=target,callback=callback}end}
    DeadAirWorld.context(0,menu,{tom},false)
    assert(#menu.options==2 and menu.options[1].target.kit,'Complete-kit action not discoverable from side piece')
    local target=menu.options[1].target
    squareAt(105,105,0).standable=false;assert(not DeadAirWorld.prepare(player,target))
    squareAt(105,105,0).standable=true;squareAt(105,105,0).wall=true;assert(not DeadAirWorld.prepare(player,target))
    squareAt(105,105,0).wall=false
    tom.square.wall=true;assert(not DeadAirWorld.prepare(player,target),'Side drum behind a wall accepted');tom.square.wall=false
    DeadAirWorld.select(target);finishWalk()
    DeadAir.performanceAction:waitToStart()
    assert(configuration[1]==9 and player.animation=='DeadAirPercussion' and player.facing==kick,'Kit action, profile or facing')
    assert(player.overridePrimary=='DeadAir.DrumstickPerformance' and player.overrideSecondary=='DeadAir.DrumstickPerformance')
    tom.index=-1;DeadAir.performanceAction:update();assert(not performing and not DeadAirKit.valid(kit),'Removed kit piece left active playback')
    tom.index=0;tom.spriteName='recreational_01_62';assert(not DeadAirKit.build(kick),'Stool accepted as a drum')
  end
end
reset();queue.queue={};DeadAir.cleanup()
print('PASS: three-piece kit recognition in four directions, two layouts, exact stance, context discovery, blockers, removal and stool exclusion')
