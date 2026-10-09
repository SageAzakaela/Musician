DeadAirInstruments = {}
local I=DeadAirInstruments
-- Numeric fields retain the existing profile/name/noise-radius contract.
local function instrument(profile,name,radius,action,clip,hand,sustain,speed)
    return {profile,name,radius,action=action,clip=clip,hand=hand or "primary",sustain=sustain or false,speed=speed or 1,gesture=({[0]="keys",[9]="strike",[12]="strike",[13]="strike",[14]="strike",[15]="strike"})[profile] or (sustain and "held" or "strum"),strikeEnd=profile==13 and 0.33 or 0.65}
end
I.held={
    ["Base.Keytar"]=instrument(0,"Keytar",22,"DeadAirKeytar","Bob_PlayKeytarExperiencedA"),
    ["Base.GuitarAcoustic"]=instrument(1,"Acoustic guitar",20,"DeadAirGuitar","Bob_PlayGuitarAcoustic","secondary"),
    ["Base.GuitarElectric"]=instrument(2,"Electric guitar",28,"DeadAirBass","Bob_PlayGuitarBassExperiencedA"),
    ["Base.GuitarElectricBass"]=instrument(3,"Bass guitar",25,"DeadAirBass","Bob_PlayGuitarBassExperiencedA"),
    ["Base.Banjo"]=instrument(4,"Banjo",20,"DeadAirBanjo","Bob_PlayGuitarExperiencedA"),
    ["Base.Flute"]=instrument(5,"Flute",16,"DeadAirFlute","Bob_PlayFluteExperiencedA","primary",true,0.6),
    ["Base.Trumpet"]=instrument(6,"Trumpet",32,"DeadAirTrumpet","Bob_PlayTrumpetExperiencedA","primary",true,0.6),
    ["Base.Saxophone"]=instrument(7,"Saxophone",28,"DeadAirSaxophone","Bob_PlaySaxophoneExperiencedA","primary",true,0.6),
    ["Base.Violin"]=instrument(8,"Violin",20,"DeadAirViolin","Bob_PlayViolinDefault","bow",true,0.7),
    ["Base.Drumstick"]=instrument(9,"Drumstick practice / drum kit",24,"DeadAirDrum","Bob_IdleHammer_Surface"),
    ["Base.Harmonica"]=instrument(10,"Harmonica",18,"DeadAirHarmonica","Bob_EmoteBlowHarmonica_R","primary",true,0.8),
    ["Base.Whistle"]=instrument(11,"Whistle",28,"DeadAirWhistle","Bob_EmoteBlowWhistle_R","primary",true,0.8),
    ["Base.Whistle_Bone"]=instrument(11,"Bone whistle",26,"DeadAirWhistle","Bob_EmoteBlowWhistle_R","primary",true,0.8),
    ["Base.TuningFork"]=instrument(12,"Tuning fork",8,"DeadAirTuningFork","DeadAirForkTap"),
}
-- The authored secondary-hand acoustic clip predates B42's rotated carry attachment.
I.held["Base.GuitarAcoustic"].visualModel="DeadAir.AcousticPerformance"
I.held["Base.Violin"].visualModel="DeadAir.ViolinPerformance"
I.held["Base.TuningFork"].visualModel="Base.TuningFork"
I.held["Base.TuningFork"].strikeEnd=.999
for _,kind in ipairs({"Base.Harmonica","Base.Whistle","Base.Whistle_Bone"})do
    I.held[kind].phaseWindow={.28,.68};I.held[kind].readyPhase=.45
end
I.piano={}
for _,side in ipairs({"SL","SR","EL","ER"}) do
    I.piano[side]=instrument(0,"Piano",26,"DeadAirPiano"..side,"Bob_PlayStandingPiano"..side,"none",false,0.8)
end
I.drums={
    Kick=instrument(13,"Kick drum",30,"DeadAirKick","Bob_AttackFloorStamp","none"),
    Tom=instrument(14,"Tom drum",26,"DeadAirDrum","Bob_IdleHammer_Surface","none"),
    Snare=instrument(15,"Snare drum",30,"DeadAirDrum","Bob_IdleHammer_Surface","none"),
}
local function percussion(def,mode)
    def.action="DeadAirPercussion";def.clip="DeadAirDrumReady";def.drumMode=mode;def.gesture="drums"
    def.tracks={{limb="rest",clip="DeadAirDrumReady"},{limb="left",clip="DeadAirDrumL"},{limb="right",clip="DeadAirDrumR"},{limb="footR",clip="DeadAirPedalR"},{limb="footL",clip="DeadAirPedalL"}}
    return def
end
percussion(I.held["Base.Drumstick"],"practice")
percussion(I.drums.Kick,"kick");percussion(I.drums.Tom,"floor");percussion(I.drums.Snare,"snare")
I.kit=percussion(instrument(9,"Drum kit",30,"DeadAirPercussion","DeadAirDrumReady","none"),"kit")
-- Only keyboard-facing pieces are performance targets. Grand-piano body pieces
-- are resolved to these from the world menu, never from localized display text.
I.pianoTiles={
    recreational_01_8={side="SL",dx=0,dy=1},recreational_01_9={side="SR",dx=0,dy=1},
    recreational_01_12={side="EL",dx=1,dy=0},recreational_01_13={side="ER",dx=1,dy=0},
    recreational_01_40={side="SL",dx=0,dy=1},recreational_01_41={side="SR",dx=0,dy=1},
    recreational_01_48={side="EL",dx=1,dy=0},recreational_01_49={side="ER",dx=1,dy=0},
}
