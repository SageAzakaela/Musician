package azakaela.deadair;
import java.nio.file.Path;
import se.krka.kahlua.vm.KahluaTable;

/** Offline production sampler, score scheduler and MIDI timestamp tests. No device is opened. */
public final class CompositionTest {
    static int checks;
    static void check(boolean b,String s){checks++;if(!b)throw new AssertionError(s);}
    static KahluaTable note(int n,int t,int d,int v){var a=MidiTake.table();a.rawset("n",(double)n);a.rawset("t",(double)t);a.rawset("d",(double)d);a.rawset("v",(double)v);return a;}
    static KahluaTable part(int profile,KahluaTable... notes){var p=MidiTake.table();var list=MidiTake.table();for(int i=0;i<notes.length;i++)list.rawset((double)i+1,notes[i]);p.rawset("profile",(double)profile);p.rawset("notes",list);return p;}
    static KahluaTable parts(KahluaTable... parts){var t=MidiTake.table();for(int i=0;i<parts.length;i++)t.rawset((double)i+1,parts[i]);return t;}
    static double num(KahluaTable t,String key){return ((Number)t.rawget(key)).doubleValue();}
    static double energy(float[] pcm,int frames){double sum=0;for(int i=0;i<frames*2;i++)sum+=Math.abs(pcm[i]);return sum;}
    static void render(ScorePlayer s,int frames,long now){for(int i=0;i<frames;i+=64)s.render(Math.min(64,frames-i),now);}
    public static void main(String[] args){
        long now=1_000_000_000L;MidiTake take=new MidiTake();take.begin(120,768,-1,now);
        take.midi(0x90,0,60,99,now-1);take.midi(0x90,0,61,100,now+10_000_000);take.midi(0x80,0,61,0,now+30_000_000);
        var result=take.stop(now+100_000_000);check(result.len()==1,"Count-in notes excluded; short taps captured between game ticks");
        var n=(KahluaTable)result.rawget(1.0);check(num(n,"n")==61&&num(n,"t")==2&&num(n,"d")==4,"Timestamped onset and duration, independent of frame polling");
        take.begin(120,384,2,now);take.midi(0x90,0,60,100,now);take.midi(0x90,2,65,80,now);take.midi(0xB0,2,64,127,now+1);take.midi(0x80,2,65,0,now+100_000_000);take.midi(0xB0,2,64,0,now+500_000_000);
        result=take.stop(now+600_000_000);check(result.len()==1&&num((KahluaTable)result.rawget(1.0),"d")==96,"Channel filter and sustain recording");
        take.begin(120,96,-1,now);take.midi(0x90,0,70,100,now);result=take.stop(now+3_000_000_000L);check(num((KahluaTable)result.rawget(1.0),"d")==96,"Stop clamps held keys at song end");
        take.begin(300,0,-1,now,512);for(int i=0;i<600;i++){take.midi(0x90,0,60,90,now+i*100000L);take.midi(0x80,0,60,0,now+i*100000L+1);}
        check(take.stop(now+1_000_000_000).len()==512&&take.full(),"Explicit capacity overflow retains captured notes");
        take.begin(120,0,-1,now,2048);
        for(int i=0;i<1200;i++){long at=now+i*250_000_000L;take.midi(0x90,0,60,90,at);take.midi(0x80,0,60,0,at+100_000_000);}
        check(take.active()&&!take.full()&&take.count()==1200,"Open take survives 64 bars and 512 notes");
        check(take.snapshot(1190).len()==10&&take.snapshot(1200).len()==0,"Incremental UI snapshots do not consume the take");
        take.midi(0x90,0,72,100,now+301_000_000_000L);
        result=take.stop(now+302_000_000_000L);n=(KahluaTable)result.rawget(1201.0);
        check(result.len()==1201&&num(n,"t")==57792&&num(n,"d")==192,"Manual Stop flushes held notes beyond old duration");
        try(ScorePlayer s=new ScorePlayer(Path.of(args[0]))){
            s.load(parts(part(1,note(60,0,96,100)),part(8,note(67,0,192,100))),120,384,false);
            s.start(now+1_000_000_000,now);
            check(energy(s.render(64,now),64)==0,"Scheduled countdown is silent without metronome");
            render(s,48000-64,now);s.render(64,now);
            check(num(s.state(0),"attack")==1&&num(s.state(1),"attack")==1,"Both instrument parts start on one audio clock");
            double e=0;for(int i=0;i<20;i++)e+=energy(s.render(64,now),64);check(e>0,"Native sample playback is audible in rendered PCM");
            render(s,24000,now);check(num(s.state(0),"held")==0&&num(s.state(1),"held")==1,"Part note-offs are independent");
            s.stop();check(energy(s.render(64,now),64)==0&&!s.active(),"Stop silences every part");
            s.load(parts(part(0,note(60,0,48,100),note(64,192,96,100))),120,384,false);
            s.start(now-500_000_000,now);check(num(s.state(0),"held")==0,"Late listener skips completed notes");
            double stale=0;for(int i=0;i<10;i++)stale+=energy(s.render(64,now),64);check(stale<.001,"Late listener does not replay stale note tails");
            s.start(now-1_100_000_000,now);check(num(s.state(0),"held")==1,"Late listener resumes a currently held note");
            s.render(64,now+2_000_000_000);check(!s.active(),"Missing game heartbeat stops the score");
            s.load(parts(part(0)),120,96,true);s.start(now+1_000_000_000,now);check(energy(s.render(64,now),64)>0,"Metronome sounds during count-in");
            s.metronome(false);check(energy(s.render(64,now),64)==0,"Metronome toggle takes effect without restarting");
            try{s.load(parts(part(0,note(60,0,400,100))),120,384,false);throw new AssertionError("Invalid duration accepted");}catch(IllegalArgumentException ok){checks++;}
            try{s.load(parts(part(0)),0,384,false);throw new AssertionError("Invalid BPM accepted");}catch(IllegalArgumentException ok){checks++;}
            s.load(parts(part(0),part(1),part(2),part(3),part(4),part(5),part(6),part(7)),120,384,false);checks++;
            s.load(parts(part(9,note(36,0,12,99),note(38,0,12,88),note(42,0,12,77)),part(9,note(50,0,12,66))),120,384,false);
            s.start(now,now);s.render(64,now);
            var kit0=(KahluaTable)s.state(0).rawget("drums");var kit1=(KahluaTable)s.state(1).rawget("drums");
            for(String key:new String[]{"kick","snare","hat"})check(num((KahluaTable)kit0.rawget(key),"attack")==1,"Score simultaneous surface: "+key);
            check(num((KahluaTable)kit1.rawget("rackHigh"),"attack")==1&&num((KahluaTable)kit0.rawget("rackHigh"),"attack")==0,"Ensemble drum parts keep separate motion counters");
            s.stop();check(num((KahluaTable)((KahluaTable)s.state(0).rawget("drums")).rawget("kick"),"attack")==0,"Score stop clears drum motions");
            KahluaTable[] longNotes=new KahluaTable[1200];for(int i=0;i<longNotes.length;i++)longNotes[i]=note(60,i*48,24,90);
            s.load(parts(part(0,longNotes)),120,60000,false);s.start(now-300_000_000_000L,now);
            check(s.active(),"Long playback accepts more than 512 notes and 64 bars");
            s.load(parts(part(0,note(60,0,12,90))),120,0,true);s.start(now-300_000_000_000L,now);
            check(s.active()&&energy(s.render(64,now),64)>0,"Open metronome continues after backing ends beyond 64 bars");
            s.stop();check(!s.active(),"Open playback stops explicitly");
        }
        try(VoiceEngine engine=new VoiceEngine()){
            engine.open(Path.of(args[0]));engine.configure(1,0,-1,.3);
            engine.scoreLoad(parts(part(0,note(60,0,96,100))),120,384,false);engine.scoreStart(0);
            byte[] pcm=new byte[256*4];double e=0;for(int i=0;i<10;i++){engine.scoreHeartbeat();engine.render(pcm,256);e+=EngineTest.rms(pcm);}
            check(e>0&&!engine.isArmed(),"Score playback works without a MIDI connection or armed live instrument");
            engine.arm(true);engine.midi(0x90,0,67,110);long serial=engine.attackSerial();engine.heartbeat();engine.render(pcm,256);
            check(engine.attackSerial()==serial&&engine.motionState().held()==1,"Armed first note survives the animation handoff");
            engine.scoreStop();engine.arm(false);engine.render(pcm,256);check(EngineTest.rms(pcm)==0,"Both audio paths stop cleanly");
        }
        System.out.println("PASS: "+checks+" production score scheduling, multi-part samples, recording, count-in, late join and safety checks");
    }
}
