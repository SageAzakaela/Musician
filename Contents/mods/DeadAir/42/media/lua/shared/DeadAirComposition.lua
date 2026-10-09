require "DeadAirScore"
-- One paper can hold a complete arrangement. Individual v1 parts remain the wire format for performances.
DeadAirComposition={}
local C,S=DeadAirComposition,DeadAirScore
function C.validate(value)
    if type(value)~="table" or (value.version~=2 and value.version~=3) or type(value.parts)~="table" or #value.parts<1 or #value.parts>S.MAX_PARTS then return nil,"A song holds one to eight parts."end
    if not S.integer(value.bpm,30,300)or not S.integer(value.bars,1,S.MAX_BARS)then return nil,"Invalid song tempo or length."end
    local title=S.text(value.title,64);if not title then return nil,"Give the song a name."end
    local out={version=3,title=title,bpm=value.bpm,bars=value.bars,song=S.text(value.song,80),revision=S.integer(value.revision,0,100000000)and value.revision or 0,parts={}}
    local seen={};local total=0
    for i,p in ipairs(value.parts)do
        if type(p)~="table"then return nil,"Invalid song part."end
        local id=S.text(p.part,80);if not id or seen[id]then return nil,"Each part needs a unique identity."end;seen[id]=true
        local score,err,notes=S.validate({version=1,title=title,bpm=value.bpm,bars=value.bars,partName=p.partName,profile=p.profile,notes=p.notes,part=id,song=out.song,revision=out.revision})
        if not score then return nil,err end
        local clips={}
        if value.version==3 and p.clips~=nil then
            if type(p.clips)~="table"or #p.clips>128 then return nil,"A track holds up to 128 clips."end
            for j,c in ipairs(p.clips)do
                if type(c)~="table"or not S.integer(c.start,0,value.bars*384-1)or not S.integer(c.length,1,value.bars*384-c.start)then return nil,"Invalid clip range."end
                clips[j]={name=S.text(c.name,48)or "Clip "..j,start=c.start,length=c.length}
                if c.loopLength~=nil then
                    if not S.integer(c.loopLength,1,c.length)then return nil,"Invalid clip loop length."end
                    clips[j].loopLength=c.loopLength
                end
            end
            table.sort(clips,function(a,b)return a.start<b.start end)
            for j=2,#clips do if clips[j].start<clips[j-1].start+clips[j-1].length then return nil,"Clips on one track cannot overlap."end end
        else clips={{name=score.partName,start=0,length=value.bars*384}}end
        out.parts[i]={part=id,partName=score.partName,profile=score.profile,notes=score.notes,clips=clips,mute=p.mute==true,solo=p.solo==true}
        notes,err=C.expandLoops(out.parts[i],notes,math.min(S.MAX_NOTES,S.MAX_TOTAL_NOTES-total))
        if not notes then return nil,err end
        total=total+#notes;out.parts[i].notes=S.encode(notes)
        C.cover(out.parts[i],notes)
        if #out.parts[i].clips>128 then return nil,"A track holds up to 128 clips."end
    end
    out.active=seen[value.active]and value.active or out.parts[1].part
    return out
end
-- The first cycle is editable source material. Repeats are materialized for existing
-- score playback/export, bounded before allocation, and rebuilt from that source.
function C.expandLoops(part,notes,capacity)
    local loops={};for _,c in ipairs(part.clips or {})do if c.loopLength then loops[#loops+1]=c end end
    if #loops==0 then if #notes>capacity then return nil,"This song has reached its note capacity."end;return notes end
    table.sort(loops,function(a,b)return a.start<b.start end)
    local out,sources={},{};for i=1,#loops do sources[i]={}end
    for _,n in ipairs(notes)do
        local lo,hi,index=1,#loops,0
        while lo<=hi do local mid=math.floor((lo+hi)/2);if loops[mid].start<=n.t then index=mid;lo=mid+1 else hi=mid-1 end end
        local c=loops[index]
        if c and n.t<c.start+c.length then
            if n.t<c.start+c.loopLength then
                if n.t+n.d>c.start+c.loopLength then return nil,"Keep source notes inside the loop boundary, or Unroll first."end
                sources[index][#sources[index]+1]=n
            end
        else out[#out+1]=n end
    end
    local count=#out
    if count>capacity then return nil,"This song has reached its note capacity."end
    for i,c in ipairs(loops)do for _,n in ipairs(sources[i])do
        count=count+math.floor((c.length-1-(n.t-c.start))/c.loopLength)+1
        if count>capacity then return nil,"That loop exceeds the song's note capacity. Shorten it or remove notes."end
    end end
    local function order(list)
        for i=2,#list do local a,b=list[i-1],list[i];if a.t>b.t or(a.t==b.t and a.n>b.n)then
            table.sort(list,function(a,b)if a.t~=b.t then return a.t<b.t end;return a.n<b.n end);return
        end end
    end
    order(out)
    -- Generate cycles chronologically and merge, rather than sorting thousands of
    -- repeated events through the game's comparatively expensive Lua comparator.
    local result={};local outside=1
    for i,c in ipairs(loops)do local source=sources[i]
        if #source>0 then
            while out[outside]and out[outside].t<c.start do result[#result+1]=out[outside];outside=outside+1 end
            order(source)
            for offset=0,c.length-1,c.loopLength do for _,n in ipairs(source)do local at=n.t+offset
                if at>=c.start+c.length then break end
                result[#result+1]=offset==0 and n or {n=n.n,t=at,d=math.min(n.d,c.start+c.length-at),v=n.v}
            end end
        end
    end
    while out[outside]do result[#result+1]=out[outside];outside=outside+1 end
    return result
end
-- Notes use absolute song time. Clip ranges move the same notes without copying audio.
-- Drawing outside a clip extends the arrangement; overlapping ranges merge without losing notes.
function C.cover(part,notes)
    local clips=part.clips or {};part.clips=clips
    table.sort(clips,function(a,b)return a.start<b.start end)
    for _,n in ipairs(notes)do
        if #clips==0 then local start=math.floor(n.t/384)*384;clips[1]={name="Clip 1",start=start,length=math.ceil((n.t+n.d-start)/384)*384}end
        -- Binary search keeps large arrangements cheap in the game's interpreted Lua VM.
        local lo,hi,index=1,#clips,0
        while lo<=hi do local mid=math.floor((lo+hi)/2);if clips[mid].start<=n.t then index=mid;lo=mid+1 else hi=mid-1 end end
        local c=clips[math.max(1,index)]
        if index==0 then local oldEnd=c.start+c.length;c.start=math.floor(n.t/384)*384;c.length=oldEnd-c.start end
        c.length=math.max(c.length,n.t+n.d-c.start)
    end
    for i=#clips,2,-1 do local a,b=clips[i-1],clips[i];if b.start<a.start+a.length then a.length=math.max(a.length,b.start+b.length-a.start);a.loopLength=nil;table.remove(clips,i)end end
end
function C.fromScore(score)
    return C.validate({version=2,song=score.song,title=score.title,bpm=score.bpm,bars=score.bars,revision=score.revision or 0,active=score.part or "draft-1",
        parts={{part=score.part or "draft-1",partName=score.partName,profile=score.profile,notes=score.notes}}})
end
function C.copy(song)return C.validate(song)end
function C.index(song,id)for i,p in ipairs(song.parts)do if p.part==(id or song.active)then return i end end;return 1 end
function C.score(song,index)
    local p=song.parts[index or C.index(song)]
    return {version=1,song=song.song,title=song.title,bpm=song.bpm,bars=song.bars,revision=song.revision,part=p.part,partName=p.partName,profile=p.profile,notes=p.notes}
end
function C.read(item)
    if not S.paper(item)then return nil end
    local data=item:getModData().DeadAirComposition
    if data then return C.validate(data)end
    local score=S.read(item);return score and C.fromScore(score)
end
-- Bring old separate sheets into the new editor without consuming them or duplicating copied parts.
function C.collect(song,container)
    if not song.song or not container then return song end
    local chosen={};for _,part in ipairs(song.parts)do chosen[part.part]=true end
    local candidates={}
    local function scan(bag,depth)
        if not bag or depth>6 then return end
        local items=bag:getItems()
        for i=0,items:size()-1 do local item=items:get(i);local other=C.read(item)
            if other and other.song==song.song and other.bpm==song.bpm and other.bars==song.bars then
                for j,p in ipairs(other.parts)do if not chosen[p.part]then
                    local score=C.score(other,j);local old=candidates[score.part]
                    if not old or score.revision>old.revision then candidates[score.part]=score end
                end end
            end
            if instanceof(item,"InventoryContainer")then scan(item:getInventory(),depth+1)end
        end
    end
    scan(container,0);local extra={};for _,score in pairs(candidates)do extra[#extra+1]=score end
    table.sort(extra,function(a,b)return a.part<b.part end)
    if #song.parts+#extra>S.MAX_PARTS then return song,"Only eight parts fit in a song; extra carried sheets were not imported."end
    for _,score in ipairs(extra)do song.parts[#song.parts+1]={part=score.part,partName=score.partName,profile=score.profile,notes=score.notes}end
    return song
end
function C.store(item,song)
    item:getModData().DeadAirComposition=C.copy(song)
    item:getModData().DeadAirScore=nil -- Do not duplicate large tracks in item/network data.
    item:setName(song.title..(#song.parts>1 and " - "..#song.parts.." parts" or " - "..song.parts[1].partName));item:setCustomName(true)
end
