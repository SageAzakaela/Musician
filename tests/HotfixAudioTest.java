package azakaela.deadair;
import musician.gervill.*;
import java.nio.file.*;
import java.util.*;

/** Actual shipped sample-zone routing and dense live input; no devices are opened. */
public final class HotfixAudioTest {
    static int checks;
    static void check(boolean value,String message){checks++;if(!value)throw new AssertionError(message);}
    static void zones(Path common)throws Exception {
        var mapping=SoundfontSetup.bundled(common);
        for(int profile=0;profile<16;profile++) {
            ModelPerformer[] performers=mapping.instruments()[profile].getPerformers();
            List<Integer> actual=new ArrayList<>(),expected=new ArrayList<>();
            var indexed=new ModelStandardIndexedDirector(performers,(i,c)->actual.add(i));
            // Compare optimized routing with the simple reference director, including
            // empty key/velocity intersections in the actual piano and drum banks.
            var reference=new ModelStandardDirector(performers,(i,c)->expected.add(i));
            for(int key=0;key<128;key++)for(int velocity=1;velocity<=127;velocity++) {
                actual.clear();expected.clear();indexed.noteOn(key,velocity);reference.noteOn(key,velocity);
                check(actual.equals(expected),VoiceEngine.PROFILES[profile]+" note "+key+" velocity "+velocity+" selected wrong samples: "+actual+" instead of "+expected);
                actual.clear();expected.clear();indexed.noteOff(key,velocity);reference.noteOff(key,velocity);
                check(actual.equals(expected),"Release sample routing differs");
            }
        }
    }
    static void rapid(Path common)throws Exception {
        try(VoiceEngine e=new VoiceEngine()) {
            e.open(common,SoundfontSetup.bundled(common));
            for(int profile:new int[]{0,1,4,9}) {
                e.configure(profile,0,-1,.3);e.arm(true);
                // A delayed audio callback can collect valid expression/bend traffic
                // along with a chord. None of it may disable local performance.
                for(int i=0;i<256;i++){e.midi(0xb0,i%6,11,100);e.midi(0xe0,i%6,0,64);}
                for(int key:new int[]{60,64,67})e.midi(0x90,0,key,100);
                check(e.isArmed()&&e.error().isEmpty(),"Dense MIDI disabled "+VoiceEngine.PROFILES[profile]);
                check(e.motionState().held()==3,"Chord notes disappeared after controller burst");
                check(EngineTest.rms(EngineTest.render(e,2048))>1,"Dense-input chord is silent");
                e.panic();e.heartbeat();long before=e.attackSerial();
                for(int i=0;i<96;i++) {
                    int key=profile==9?new int[]{36,38,42,46}[i%4]:60+i%12;
                    e.heartbeat();e.midi(0x90,0,key,100);
                    check(EngineTest.rms(EngineTest.render(e,600))>1,"Fast passage silent at "+profile+" / "+i);
                    e.midi(0x80,0,key,0);EngineTest.render(e,600);
                }
                check(e.attackSerial()-before==96&&e.isArmed(),"Fast passage lost note attacks");
                e.panic();check(e.activeVoices()==0,"Panic must still clear dense input");
            }
        }
    }
    public static void main(String[] args)throws Exception {
        Path common=Path.of(args[0]);
        if(args.length==1||args[1].equals("zones"))zones(common);
        if(args.length==1||args[1].equals("rapid"))rapid(common);
        System.out.println("PASS: "+checks+" sample-zone, note-off, dense-controller, chord and fast-passage checks; no hardware opened");
    }
}
