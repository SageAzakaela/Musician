require "DeadAirComposition"
DeadAirClipOps={}
local O,S,C=DeadAirClipOps,DeadAirScore,DeadAirComposition
local function finish(clips,notes,chosen,capacity)
    if #clips>128 then return nil,"A track holds up to 128 clips."end
    if #notes>capacity then return nil,"Not enough note capacity for this edit."end
    table.sort(clips,function(a,b)return a.start<b.start end)
    local selected={};local active
    for i,c in ipairs(clips)do
        if c.start<0 or c.start+c.length>S.MAX_BARS*384 then return nil,"The edit exceeds the timeline."end
        if i>1 and c.start<clips[i-1].start+clips[i-1].length then return nil,"Clips cannot overlap. Choose free space."end
        if chosen[c]then selected[i]=true;active=active or i end
    end
    table.sort(notes,function(a,b)if a.t~=b.t then return a.t<b.t end;return a.n<b.n end)
    return {clips=clips,notes=notes,selected=selected,active=active or 1}
end
-- Split sustained notes into bounded notes so both new clips remain playable.
local function cutNotes(notes,clip,cuts)
    local out={}
    for _,n in ipairs(notes)do
        if n.t>=clip.start and n.t<clip.start+clip.length then
            local at,last=n.t,n.t+n.d
            for _,cut in ipairs(cuts)do if cut>at and cut<last then
                out[#out+1]={n=n.n,t=at,d=cut-at,v=n.v};at=cut
            end end
            out[#out+1]={n=n.n,t=at,d=last-at,v=n.v}
        else out[#out+1]=S.copy(n)end
    end
    return out
end
function O.split(part,notes,index,tick,capacity)
    local c=part.clips[index]
    if not c or not S.integer(tick,c.start+1,c.start+c.length-1)then return nil,"Place the cursor inside the clip to split it."end
    local clips=S.copy(part.clips);local left=clips[index];left.length=tick-c.start;left.loopLength=nil;left.loopStart=nil
    local right={name=c.name.." B",start=tick,length=c.start+c.length-tick};clips[#clips+1]=right
    return finish(clips,cutNotes(notes,c,{tick}),{[right]=true},capacity)
end
function O.unique(part,notes,index,tick,capacity)
    local c=part.clips[index];if not c or not c.loopLength then return nil,"Choose a repetition in a looped clip."end
    local first=c.start+(c.loopStart or 0);local ending=c.start+c.length
    if tick<first or tick>=ending then return nil,"Choose a repetition inside the loop range."end
    local a=first+math.floor((tick-first)/c.loopLength)*c.loopLength;local b=math.min(ending,a+c.loopLength)
    local clips={};for i,clip in ipairs(part.clips)do if i~=index then clips[#clips+1]=S.copy(clip)end end
    if a>c.start then
        local before=S.copy(c);before.length=a-c.start
        if before.length<(c.loopStart or 0)+c.loopLength then before.loopLength=nil;before.loopStart=nil end
        clips[#clips+1]=before
    end
    local unique={name=c.name.." variation",start=a,length=b-a};clips[#clips+1]=unique
    if b<ending then local after={name=c.name,start=b,length=ending-b}
        if after.length>=c.loopLength then after.loopLength=c.loopLength end
        clips[#clips+1]=after
    end
    return finish(clips,cutNotes(notes,c,{a,b}),{[unique]=true},capacity)
end
function O.consolidate(part,notes,selected,capacity)
    local first,last,count=math.huge,0,0
    for i,c in ipairs(part.clips)do if selected[i]then first=math.min(first,c.start);last=math.max(last,c.start+c.length);count=count+1 end end
    if count==0 then return nil,"Select the clips to consolidate."end
    local clips={};local name
    for i,c in ipairs(part.clips)do
        if selected[i]then name=name or c.name
        elseif c.start<last and c.start+c.length>first then return nil,"Select all clips between the first and last clip."else clips[#clips+1]=S.copy(c)end
    end
    local joined={name=name,start=first,length=last-first};clips[#clips+1]=joined
    return finish(clips,S.copy(notes),{[joined]=true},capacity)
end
function O.move(part,notes,selected,delta,duplicate,capacity)
    local clips,chosen,ranges={},{},{}
    for i,c in ipairs(part.clips)do
        if selected[i]then
            ranges[#ranges+1]=c
            if duplicate then clips[#clips+1]=S.copy(c)end
            local moved=S.copy(c);moved.start=moved.start+delta
            if duplicate then moved.name=moved.name.." copy"end
            clips[#clips+1]=moved;chosen[moved]=true
        else clips[#clips+1]=S.copy(c)end
    end
    if #ranges==0 then return nil,"Select a clip first."end
    local out={}
    for _,n in ipairs(notes)do
        local selectedNote=false
        for _,c in ipairs(ranges)do if n.t>=c.start and n.t<c.start+c.length then selectedNote=true;break end end
        if not selectedNote or duplicate then out[#out+1]=S.copy(n)end
        if selectedNote then local moved=S.copy(n);moved.t=moved.t+delta;out[#out+1]=moved end
    end
    return finish(clips,out,chosen,capacity)
end
function O.delete(part,notes,selected,capacity)
    local clips,out={},{}
    for i,c in ipairs(part.clips)do if not selected[i]then clips[#clips+1]=S.copy(c)end end
    for _,n in ipairs(notes)do
        local remove=false;for i,c in ipairs(part.clips)do if selected[i]and n.t>=c.start and n.t<c.start+c.length then remove=true;break end end
        if not remove then out[#out+1]=S.copy(n)end
    end
    return finish(clips,out,{},capacity)
end
