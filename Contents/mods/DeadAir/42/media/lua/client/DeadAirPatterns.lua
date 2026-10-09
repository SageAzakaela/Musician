-- Original procedural building blocks. No commercial MIDI files are bundled here.
DeadAirPatterns={}
local P=DeadAirPatterns
P.chords={
    {"major","Major",{0,4,7}}, {"minor","Minor",{0,3,7}}, {"power","Power / fifth",{0,7,12}},
    {"sus2","Sus2",{0,2,7}}, {"sus4","Sus4",{0,5,7}}, {"dim","Diminished",{0,3,6}}, {"aug","Augmented",{0,4,8}},
    {"maj7","Major 7",{0,4,7,11}}, {"min7","Minor 7",{0,3,7,10}}, {"dom7","Dominant 7",{0,4,7,10}},
    {"dim7","Diminished 7",{0,3,6,9}}, {"half7","Half diminished 7",{0,3,6,10}}, {"add9","Add9",{0,4,7,14}},
    {"maj9","Major 9",{0,4,7,11,14}}, {"min9","Minor 9",{0,3,7,10,14}}, {"dom9","Dominant 9",{0,4,7,10,14}}
}
P.progressions={
    {"four","I - V - vi - IV",{1,5,6,4},"major"}, {"six","vi - IV - I - V",{6,4,1,5},"major"},
    {"cadence","I - IV - V - I",{1,4,5,1},"major"}, {"jazz","ii - V - I",{2,5,1},"major",true},
    {"turnaround","I - vi - ii - V",{1,6,2,5},"major",true}, {"minor","i - VI - III - VII",{1,6,3,7},"minor"},
    {"minor_cadence","i - iv - v - i",{1,4,5,1},"minor"}, {"descending","i - VII - VI - V",{1,7,6,5},"minor"},
    {"blues","12-bar blues",{1,1,1,1,4,4,1,1,5,4,1,5},"blues",true}
}
P.drums={{"rock","Rock / eighths"},{"half","Half-time"},{"four","Four on the floor"},{"punk","Punk drive"},{"double","Double-kick metal"},{"blast","Alternating blast"},{"shuffle","Shuffle / triplets"},{"hiphop","Hip-hop backbeat"},{"synth","Synth-pop"},{"funk","Syncopated funk"},{"fill","Tom fill"},{"count","Count-in / closed hats"}}
function P.rows(kind,query)
    local list=kind==1 and P.chords or kind==2 and P.progressions or P.drums;local out={};query=(query or ""):lower()
    for i,v in ipairs(list)do if query==""or v[2]:lower():find(query,1,true)then out[#out+1]={id="builtin:"..kind..":"..i,name=v[2],path=kind==1 and "Chord / choose root and octave"or kind==2 and (v[4].." / choose root and chord length")or "Drums / General MIDI",builtin=kind,index=i}end end
    return out
end
function P.make(kind,index,root,octave,beats)
    root=root or 0;octave=octave or 3;beats=beats or 4
    local clip={notes={},length=beats*96,bpm=120,meter="4/4",warning="",drums=kind==3};local base=12*(octave+1)+root;clip.rootPitch=kind~=3 and base or nil
    local function note(n,t,d,v)clip.notes[#clip.notes+1]={n=n,t=t,d=d,v=v or 96}end
    if kind==1 then
        local c=P.chords[index];if not c then return nil end;clip.name=c[2]
        for _,interval in ipairs(c[3])do note(base+interval,0,beats*96)end
    elseif kind==2 then
        local p=P.progressions[index];if not p then return nil end;clip.name=p[2];clip.length=#p[3]*beats*96
        local scale=p[4]=="minor"and {0,2,3,5,7,8,10}or p[4]=="harmonic"and {0,2,3,5,7,8,11}or {0,2,4,5,7,9,11}
        for at,degree in ipairs(p[3])do
            if p[4]=="blues"then for _,interval in ipairs({0,4,7,10})do note(base+scale[degree]+interval,(at-1)*beats*96,beats*96-3)end
            elseif p[1]=="descending"and degree==5 then for _,interval in ipairs({0,4,7})do note(base+7+interval,(at-1)*beats*96,beats*96-3)end
            else for step=0,p[5]and 3 or 2 do local pos=degree-1+step*2;note(base+scale[pos%7+1]+math.floor(pos/7)*12,(at-1)*beats*96,beats*96-3)end end
        end
    else
        local pattern=P.drums[index];if not pattern then return nil end;clip.name=pattern[2];clip.length=384
        local function hits(pitch,times,velocity)for _,t in ipairs(times)do note(pitch,t,12,velocity or 100)end end
        local id=pattern[1]
        if id=="fill"then hits(36,{0,192});for i=0,15 do note(({48,45,43,41})[math.floor(i/4)+1],i*24,12,82+i*2)end
        elseif id=="count"then hits(42,{0,96,192,288},80)
        else
            if id=="shuffle"then for b=0,3 do hits(42,{b*96,b*96+64},75)end
            else local step=(id=="double"or id=="funk")and 24 or 48;for t=0,383,step do note(42,t,12,t%96==0 and 84 or 65)end end
            if id=="half"then hits(36,{0,144,192});hits(38,{192})
            elseif id=="four"or id=="synth"then hits(36,{0,96,192,288});hits(38,{96,288});hits(46,{48,144,240,336},70)
            elseif id=="punk"then hits(36,{0,48,192,240});hits(38,{96,288},115)
            elseif id=="double"then for t=0,383,24 do note(36,t,12,100)end;hits(38,{96,288},112)
            elseif id=="blast"then for t=0,383,48 do note(36,t,12,100);note(38,t+24,12,105)end
            elseif id=="hiphop"then hits(36,{0,168,240});hits(38,{96,288},108)
            elseif id=="funk"then hits(36,{0,72,168,240,336});hits(38,{96,288},107);hits(38,{216,264},42)
            else hits(36,{0,192});hits(38,{96,288},108)end
        end
    end
    table.sort(clip.notes,function(a,b)if a.t==b.t then return a.n<b.n end;return a.t<b.t end)
    return clip
end
