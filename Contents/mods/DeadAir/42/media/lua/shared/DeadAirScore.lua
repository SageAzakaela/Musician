-- This schema is shared by inventory, editor and server. Never execute score data as Lua.
DeadAirScore={VERSION=1,PPQ=96,MAX_NOTES=16384,MAX_TOTAL_NOTES=24576,MAX_BARS=262144,MAX_PARTS=8,MAX_PAGES=32}
local S=DeadAirScore
S.names={"Piano / keytar","Acoustic guitar","Electric guitar","Bass guitar","Banjo","Flute","Trumpet","Saxophone","Violin","Drum kit / drumstick","Harmonica","Whistle","Tuning fork","Kick drum","Tom drum","Snare drum"}
function S.integer(x,a,b) return type(x)=="number" and x==x and x%1==0 and x>=a and x<=b end
function S.text(x,max)
    if type(x)~="string" then return nil end
    x=x:gsub("[%c]",""):sub(1,max)
    return #x>0 and x or nil
end
function S.decode(wire,ticks)
    if type(wire)=="table"then
        if #wire<1 or #wire>S.MAX_PAGES then return nil,"Invalid note pages."end
        local pages={};local count=0
        for k,v in pairs(wire)do if not S.integer(k,1,#wire)or type(v)~="string"or #v>16000 then return nil,"Invalid note page."end;count=count+1 end
        if count~=#wire then return nil,"Missing note page."end
        for _,page in ipairs(wire)do pages[#pages+1]=page end
        wire=table.concat(pages)
    elseif type(wire)~="string"or #wire>18000 then return nil,"This part is too large."end
    local notes={};local consumed=0;local count=0;local ordered=true;local lastT,lastN=-1,-1
    while consumed<#wire do
        local finish=wire:find(";",consumed+1,true);if not finish then return nil,"Invalid note data."end
        local token=wire:sub(consumed+1,finish-1)
        local n,t,d,v=token:match("^(%d+),(%d+),(%d+),(%d+)$")
        n=tonumber(n);t=tonumber(t);d=tonumber(d);v=tonumber(v)
        if not S.integer(n,0,127) or not S.integer(t,0,ticks-1) or not S.integer(d,1,ticks-t) or not S.integer(v,1,127) then return nil,"Invalid note in this part." end
        count=count+1;notes[count]={n=n,t=t,d=d,v=v};consumed=finish
        if t<lastT or (t==lastT and n<lastN)then ordered=false end;lastT=t;lastN=n
        if count>S.MAX_NOTES then return nil,"This part has reached its note capacity (16,384)." end
    end
    if consumed~=#wire then return nil,"Invalid note data." end
    if not ordered then table.sort(notes,function(a,b) if a.t==b.t then return a.n<b.n end;return a.t<b.t end)end
    return notes
end
function S.encode(notes)
    local out={}
    for _,n in ipairs(notes) do out[#out+1]=string.format("%d,%d,%d,%d;",n.n,n.t,n.d,n.v) end
    local pages,page,size={}, {},0
    for _,token in ipairs(out)do
        if size+#token>16000 then pages[#pages+1]=table.concat(page);page={};size=0 end
        page[#page+1]=token;size=size+#token
    end
    pages[#pages+1]=table.concat(page)
    return #pages==1 and pages[1]or pages
end
function S.equal(a,b)
    if type(a)=="table"then a=table.concat(a)end
    if type(b)=="table"then b=table.concat(b)end
    return a==b
end
function S.validate(x)
    if type(x)~="table" or x.version~=1 or not S.integer(x.bpm,30,300) or not S.integer(x.bars,1,S.MAX_BARS) or not S.integer(x.profile,0,15) then return nil,"Invalid song settings." end
    local title,partName=S.text(x.title,64),S.text(x.partName,48)
    if not title or not partName then return nil,"Give the song and part a name." end
    local notes,err=S.decode(x.notes,x.bars*384);if not notes then return nil,err end
    return {version=1,title=title,partName=partName,bpm=x.bpm,bars=x.bars,profile=x.profile,notes=S.encode(notes),song=S.text(x.song,80),part=S.text(x.part,80),revision=S.integer(x.revision,0,100000000) and x.revision or 0},nil,notes
end
function S.copy(x) local t={};for k,v in pairs(x)do t[k]=type(v)=="table"and S.copy(v)or v end;return t end
function S.new()return {version=1,title="Untitled song",partName="Part 1",bpm=120,bars=8,profile=0,notes="",revision=0} end
function S.step(denominator,triplet)return 384/denominator*(triplet and 2/3 or 1) end
function S.quantize(notes,step,ticks)
    local out={}
    for _,n in ipairs(notes) do
        local t=math.min(ticks-step,math.max(0,math.floor(n.t/step+.5)*step))
        local finish=math.max(t+step,math.floor((n.t+n.d)/step+.5)*step)
        out[#out+1]={n=n.n,t=t,d=math.min(ticks,finish)-t,v=n.v}
    end
    return out
end
function S.paper(item)return item and item:getFullType()=="Base.SheetPaper2" end
-- Lightweight identity checks for the running ensemble; full notes are validated at preparation.
function S.header(item)
    if not S.paper(item) then return nil end
    local song=item:getModData().DeadAirComposition
    if song and DeadAirComposition then
        if type(song)~="table"or (song.version~=2 and song.version~=3)or type(song.parts)~="table"or #song.parts<1 or #song.parts>S.MAX_PARTS then return nil end
        for _,p in ipairs(song.parts)do if type(p)~="table"then return nil end end
        local score=DeadAirComposition.score(song)
        if not S.text(score.title,64)then return nil end
        return score
    end
    return item:getModData().DeadAirScore
end
function S.read(item)
    local s=S.validate(S.header(item))
    return s and s.song and s.part and s or nil
end
function S.blank(item)
    if not S.paper(item) or item:getModData().DeadAirScore or item:getModData().DeadAirComposition then return false end
    local page=item:seePage(1)
    return page==nil or page==""
end
function S.find(container,id,depth)
    if not container or (depth or 0)>6 then return nil end
    local list=container:getItems()
    for i=0,list:size()-1 do local item=list:get(i)
        if item:getID()==id then return item end
        if instanceof(item,"InventoryContainer") then local found=S.find(item:getInventory(),id,(depth or 0)+1);if found then return found end end
    end
end
function S.blankIn(container,depth)
    if not container or (depth or 0)>6 then return nil end
    local list=container:getItems()
    for i=0,list:size()-1 do local item=list:get(i)
        if S.blank(item) then return item end
        if instanceof(item,"InventoryContainer") then local found=S.blankIn(item:getInventory(),(depth or 0)+1);if found then return found end end
    end
end
function S.native(score,from)
    local notes=S.decode(score.notes,score.bars*384)or {};local out={};from=from or 0
    for _,n in ipairs(notes)do if n.t+n.d>from then local start=math.max(from,n.t);out[#out+1]={n=n.n,t=start-from,d=n.t+n.d-start,v=n.v}end end
    return {profile=score.profile,notes=out}
end
