require "DeadAirScore"
DeadAirLiveProtocol={VERSION=1,RANGE=45,MAX_STREAMS=32}
local P,S=DeadAirLiveProtocol,DeadAirScore
local controllers={[1]=true,[7]=true,[11]=true,[64]=true,[120]=true,[121]=true,[123]=true}
function P.rows(wire,timed,at)
    if type(wire)~="string" or #wire>4096 then return nil end
    local out,keys={},{};local pos,last,count=1,math.max(0,at-1000),0
    while pos<=#wire do
        local finish=wire:find(";",pos,true);if not finish then return nil end
        local token=wire:sub(pos,finish-1);local t,status,a,b
        if timed then t,status,a,b=token:match("^(%d+),(%d+),(%d+),(%d+)$")
        else status,a,b=token:match("^(%d+),(%d+),(%d+)$");t=at end
        t,status,a,b=tonumber(t),tonumber(status),tonumber(a),tonumber(b)
        if not S.integer(t,last,at) or not S.integer(status,128,239) or not S.integer(a,0,127) or not S.integer(b,0,127) then return nil end
        local cmd=math.floor(status/16)*16
        if cmd~=128 and cmd~=144 and cmd~=224 and not(cmd==176 and controllers[a])then return nil end
        if not timed and cmd==144 and b>0 then
            local key=(status%16)*128+a;if keys[key]then return nil end;keys[key]=true;count=count+1;if count>48 then return nil end
        end
        out[#out+1]={t=t,status=status,a=a,b=b};last=t;pos=finish+1
        if #out>(timed and 128 or 256)then return nil end
    end
    return out
end
function P.frame(args)
    if type(args)~="table" or args.v~=P.VERSION or not S.integer(args.epoch,1,2147483647)
        or not S.integer(args.seq,1,2147483647) or not S.integer(args.profile,0,15)
        or not S.integer(args.at,0,1000000000) or type(args.reset)~="boolean" then return nil end
    local events=P.rows(args.events,true,args.at);local state=P.rows(args.state,false,args.at)
    if not events or not state then return nil end
    return {v=1,epoch=args.epoch,seq=args.seq,profile=args.profile,at=args.at,events=args.events,state=args.state,reset=args.reset},#events
end
function P.position(p)return p and type(p.x)=="number" and p.x==p.x and math.abs(p.x)<=100000 and type(p.y)=="number" and p.y==p.y and math.abs(p.y)<=100000 and S.integer(p.z,-32,32)end
function P.near(player,position)
    return player and P.position(position) and player:getZ()==position.z and (player:getX()-position.x)^2+(player:getY()-position.y)^2<P.RANGE^2
end
function P.gain(player,position)
    if not P.near(player,position)then return 0 end
    local distance=math.sqrt((player:getX()-position.x)^2+(player:getY()-position.y)^2)
    return math.max(0,1-distance/P.RANGE)^2
end
