require "DeadAirScore"
require "DeadAirComposition"
DeadAirPaper={}
local P,S=DeadAirPaper,DeadAirScore
local function uid(player)return tostring(getTimestampMs()).."-"..tostring(player:getOnlineID()).."-"..tostring(ZombRand(1000000000)) end
local function storeSong(player,target,song,mode)
    DeadAirComposition.store(target,song)
    if isServer()then syncItemModData(player,target);syncItemFields(player,target)end
    return {item=target:getID(),composition=song,mode=mode}
end
function P.write(player,args)
    if type(args)~="table" or player:isDead() then return nil,"You cannot write now." end
    local source=S.find(player:getInventory(),args.item)
    if not S.paper(source) then return nil,"Keep the sheet in your inventory." end
    local old=S.read(source);local target=source;local score
    local C=DeadAirComposition;local oldSong=C.read(source)
    if args.mode=="saveSong" then
        if not oldSong and not S.blank(source)then return nil,"This sheet already has writing on it."end
        if (oldSong and oldSong.revision or 0)~=args.revision then return nil,"This sheet changed. Reopen it before saving."end
        local song,err=C.validate(args.composition);if not song then return nil,err end
        song.song=oldSong and oldSong.song or uid(player);song.revision=(oldSong and oldSong.revision or 0)+1
        for _,part in ipairs(song.parts)do
            if part.part:find("^draft%-")then local previous=part.part;part.part=uid(player);if song.active==previous then song.active=part.part end end
        end
        return storeSong(player,source,song,args.mode)
    elseif args.mode=="copy" and source:getModData().DeadAirComposition then
        if not oldSong then return nil,"This song could not be read."end
        target=S.find(player:getInventory(),args.blank)
        if not target or target==source or not S.blank(target)then return nil,"You need another blank sheet of paper."end
        return storeSong(player,target,oldSong,args.mode)
    elseif args.mode=="export" then
        if not oldSong then return nil,"Save the song first."end
        target=S.find(player:getInventory(),args.blank)
        if not target or target==source or not S.blank(target)then return nil,"You need another blank sheet of paper."end
        local found;for i,part in ipairs(oldSong.parts)do if part.part==args.part then found=i end end
        if not found then return nil,"That part is no longer in this song."end
        score=C.score(oldSong,found)
    elseif args.mode=="save" and source:getModData().DeadAirComposition then
        return nil,"This paper contains a whole song. Reopen it with the updated editor." 
    end
    if args.mode=="export" then
        -- The validated selected part above becomes an ordinary performance sheet.
    elseif args.mode=="copy" or args.mode=="part" then
        if not old then return nil,"Save the original song first." end
        target=S.find(player:getInventory(),args.blank)
        if not target or target==source or not S.blank(target) then return nil,"You need another blank sheet of paper." end
        score=S.copy(old)
        if args.mode=="part" then score.part=uid(player);score.partName="New part";score.notes="";score.revision=0 end
    elseif args.mode=="save" then
        if not old and not S.blank(source) then return nil,"This sheet already has writing on it." end
        if (old and old.revision or 0)~=args.revision then return nil,"This sheet changed. Reopen it before saving." end
        local err;score,err=S.validate(args.score);if not score then return nil,err end
        score.song=old and old.song or uid(player)
        score.part=old and old.part or uid(player)
        score.revision=(old and old.revision or 0)+1
    else return nil,"Unknown paper action." end
    target:getModData().DeadAirScore=score
    target:setName(score.title.." - "..score.partName);target:setCustomName(true)
    if isServer() then syncItemModData(player,target);syncItemFields(player,target) end
    return {item=target:getID(),score=score,mode=args.mode}
end
