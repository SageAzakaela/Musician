require "DeadAirInstruments"
require "DeadAirKit"
require "TimedActions/WalkToTimedAction"
require "Util/AdjacentFreeTileFinder"

DeadAirWorld={}
local W=DeadAirWorld
local I=DeadAirInstruments
local function spriteName(object)
    local sprite=object and object:getSprite()
    return sprite and sprite:getName()
end
function W.describe(object)
    if not object or object:getObjectIndex()<0 or not object:getSquare() then return nil end
    local sprite=object:getSprite()
    if not sprite then return nil end
    local name=sprite:getName()
    local layout=I.pianoTiles[name]
    if layout then return {object=object,sprite=name,instrument=I.piano[layout.side],layout=layout} end
    local p=sprite:getProperties()
    if not p then return nil end
    local custom,group=p:get("CustomName"),p:get("GroupName")
    for key,instrument in pairs(I.drums) do
        if (custom=="Drum" and group==key) or custom==key.." Drum" then
            return {object=object,sprite=name,instrument=instrument}
        end
    end
    return nil
end
function W.valid(target)
    return target and target.object and target.object:getObjectIndex()>=0
        and target.object:getSquare()~=nil and spriteName(target.object)==target.sprite
        and (not target.kit or DeadAirKit.valid(target.kit))
end
local function clearReach(target,stand)
    if not AdjacentFreeTileFinder.privTrySquareForWalls(target.object:getSquare(),stand)then return false end
    if target.kit then
        for _,piece in pairs(target.kit.parts)do
            if not AdjacentFreeTileFinder.privTrySquareForWalls(piece:getSquare(),stand)then return false end
        end
    end
    return true
end
function W.atInstrument(player,target)
    if not W.valid(target) or not target.stand then return false end
    local square=player:getSquare()
    return square and square:getX()==target.stand:getX() and square:getY()==target.stand:getY()
        and square:getZ()==target.stand:getZ()
        and clearReach(target,square)
end
function W.prepare(player,target)
    if not W.valid(target) then return false,"That instrument is no longer there." end
    local square=target.object:getSquare()
    if player:getZ()~=square:getZ() then return false,"Reach the instrument's floor first." end
    local candidates={}
    if target.kit then
        candidates[1]=getCell():getGridSquare(target.kit.x,target.kit.y,target.kit.z)
    elseif target.layout then
        candidates[1]=getCell():getGridSquare(square:getX()+target.layout.dx,square:getY()+target.layout.dy,square:getZ())
    elseif DeadAirKit.piece(target.object) then
        local dx,dy=DeadAirKit.standOffset(target.object)
        candidates[1]=getCell():getGridSquare(square:getX()+dx,square:getY()+dy,square:getZ())
    else
        for _,offset in ipairs({{0,1},{1,0},{0,-1},{-1,0}}) do
            local candidate=getCell():getGridSquare(square:getX()+offset[1],square:getY()+offset[2],square:getZ())
            if candidate then candidates[#candidates+1]=candidate end
        end
    end
    local best,distance
    for _,candidate in ipairs(candidates) do
        if AdjacentFreeTileFinder.privTrySquare(square,candidate) and clearReach(target,candidate) then
            local d=(player:getX()-candidate:getX()-0.5)^2+(player:getY()-candidate:getY()-0.5)^2
            if not distance or d<distance then best=candidate;distance=d end
        end
    end
    if not best then return false,"Clear a space in front of the instrument first." end
    target.stand=best
    return true
end
function W.select(target)
    DeadAir.stop()
    DeadAir.worldTarget=target
    local player=getSpecificPlayer(0)
    local ok,reason=W.prepare(player,target)
    if not ok then DeadAir.notice=reason;return end
    local queue=ISTimedActionQueue.getTimedActionQueue(player)
    if #queue.queue>0 then DeadAir.notice="Finish your current action before taking position.";return end
    if not W.atInstrument(player,target) then
        local walk=ISWalkToTimedAction:new(player,target.stand);DeadAir.approachAction=walk;ISTimedActionQueue.add(walk)
    end
    DeadAir.notice="Selected "..target.instrument[2]..". Play MIDI or a song part when in position."
    DeadAir.configure()
end
function W.context(playerIndex,context,worldobjects,test)
    if playerIndex~=0 then return end
    local seen={};local targets={}
    local function scan(square,group)
        if not square then return end
        local objects=square:getObjects()
        for i=0,objects:size()-1 do
            local object=objects:get(i)
            if not seen[object] then
                local target=W.describe(object)
                if target then
                    local p=object:getSprite():getProperties()
                    if not group or (target.layout and p:get("GroupName")==group) then
                        seen[object]=true;targets[#targets+1]=target
                    end
                end
            end
        end
    end
    for _,object in ipairs(worldobjects) do
        local square=object:getSquare()
        scan(square)
        local sprite=object:getSprite()
        local props=sprite and sprite:getProperties()
        -- A grand piano's lid/body can be clicked instead of its keyboard piece.
        if square and props and props:get("CustomName")=="Piano" then
            for dx=-2,2 do for dy=-2,2 do
                scan(getCell():getGridSquare(square:getX()+dx,square:getY()+dy,square:getZ()),props:get("GroupName"))
            end end
        end
    end
    if test then
        if #targets>0 then return ISWorldObjectContextMenu.setTest() end
        return
    end
    -- One closest keyboard side per piano is sufficient for the menu.
    local player=getSpecificPlayer(0)
    table.sort(targets,function(a,b)
        local sa,sb=a.object:getSquare(),b.object:getSquare()
        return (sa:getX()-player:getX())^2+(sa:getY()-player:getY())^2 < (sb:getX()-player:getX())^2+(sb:getY()-player:getY())^2
    end)
    local added={}
    for _,target in ipairs(targets) do
        if not added.kit then
            local kit=DeadAirKit.near(target.object)
            if kit then
                added.kit=true
                context:addOption("Play complete drum kit with MIDI (Musician)",{object=kit.object,sprite=spriteName(kit.object),instrument=I.kit,kit=kit},W.select)
            end
        end
        if not added[target.instrument[2]] then
            context:addOption("Play "..target.instrument[2].." with MIDI (Musician)",target,W.select)
            added[target.instrument[2]]=true
        end
    end
end
