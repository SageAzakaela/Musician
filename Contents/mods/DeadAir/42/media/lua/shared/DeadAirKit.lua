-- Shared, language-independent furniture recognition for client and ensemble validation.
DeadAirKit={}
local K=DeadAirKit
local facing={N={0,-1},E={1,0},S={0,1},W={-1,0}}
local tiles={
    recreational_01_56={"Kick","N"},recreational_01_57={"Tom","N"},recreational_01_58={"Snare","N"},
    recreational_01_59={"Kick","W"},recreational_01_60={"Snare","W"},recreational_01_61={"Tom","W"},
    recreational_01_64={"Kick","S"},recreational_01_65={"Tom","S"},recreational_01_69={"Snare","S"},
    recreational_01_67={"Kick","E"},recreational_01_68={"Tom","E"},recreational_01_66={"Snare","E"},
}
function K.piece(object)
    if not object or object:getObjectIndex()<0 or not object:getSquare()then return nil end
    local sprite=object:getSprite();if not sprite then return nil end
    local known=tiles[sprite:getName()];if known then return known[1],known[2]end
    return nil
end
function K.build(kick)
    local kind,dir=K.piece(kick);if kind~="Kick"then return nil end
    local f=facing[dir];local right={-f[2],f[1]};local square=kick:getSquare()
    local x,y,z=square:getX()-f[1],square:getY()-f[2],square:getZ()
    local parts={Kick=kick};local positions={}
    for _,pair in ipairs({{"Snare",-1},{"Tom",1}})do
        -- Side pieces may sit beside the player or one tile forward, but not across the kit.
        for front=0,1 do
            local tx,ty=x+right[1]*pair[2]+f[1]*front,y+right[2]*pair[2]+f[2]*front
            local s=getCell():getGridSquare(tx,ty,z)
            if s then local objects=s:getObjects();for i=0,objects:size()-1 do
                local o=objects:get(i);local p,pdir=K.piece(o)
                if p==pair[1] and pdir==dir and not parts[p]then parts[p]=o;positions[p]={x=tx,y=ty}end
            end end
        end
    end
    if not parts.Snare or not parts.Tom then return nil end
    return {object=kick,parts=parts,positions=positions,x=x,y=y,z=z,facing=dir}
end
function K.valid(kit)
    local current=kit and K.build(kit.object)
    return current and current.x==kit.x and current.y==kit.y and current.z==kit.z and current.facing==kit.facing
        and current.parts.Tom==kit.parts.Tom and current.parts.Snare==kit.parts.Snare
        and current.positions.Tom.x==kit.positions.Tom.x and current.positions.Tom.y==kit.positions.Tom.y
        and current.positions.Snare.x==kit.positions.Snare.x and current.positions.Snare.y==kit.positions.Snare.y or false
end
function K.near(object)
    local square=object and object:getSquare();if not square then return nil end
    for dx=-2,2 do for dy=-2,2 do local s=getCell():getGridSquare(square:getX()+dx,square:getY()+dy,square:getZ())
        if s then local objects=s:getObjects();for i=0,objects:size()-1 do local kit=K.build(objects:get(i))
            if kit and (kit.parts.Kick==object or kit.parts.Snare==object or kit.parts.Tom==object)then return kit end
        end end
    end end
end
function K.standOffset(object)
    local _,dir=K.piece(object);local f=dir and facing[dir];return f and -f[1],f and -f[2]
end
