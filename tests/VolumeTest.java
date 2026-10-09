package azakaela.deadair;

import java.nio.file.Path;
import java.util.Locale;
import se.krka.kahlua.vm.KahluaTable;

/** Real FluidSynth rendering to memory only. Never opens audio outputs or MIDI inputs. */
public final class VolumeTest {
    static int checks;
    static void check(boolean ok,String message){checks++;if(!ok)throw new AssertionError(message);}
    static byte[] render(VoiceEngine engine,int frames){
        byte[] pcm=new byte[frames*4],block=new byte[256*4];
        for(int i=0;i<frames;i+=256){int n=Math.min(256,frames-i);engine.heartbeat();engine.scoreHeartbeat();engine.render(block,n);System.arraycopy(block,0,pcm,i*4,n*4);}
        return pcm;
    }
    static double live(VoiceEngine e,int profile,double gain,int velocity){
        e.scoreStop();e.configure(profile,0,-1,gain);e.arm(true);
        e.midi(0x90,0,profile==9?36:60,velocity);
        return EngineTest.rms(render(e,16000));
    }
    static double score(VoiceEngine e,double gain){
        e.arm(false);e.configure(1,0,-1,gain);
        e.scoreLoad(CompositionTest.parts(CompositionTest.part(1,CompositionTest.note(60,0,192,110))),120,384,false);
        e.scoreStart(0);e.scoreGain(0,1);
        return EngineTest.rms(render(e,16000));
    }
    public static void main(String[] args){
        boolean measurementsOnly=args.length>1&&args[1].equals("--measure");
        try(VoiceEngine e=new VoiceEngine()){
            e.open(Path.of(args[0]));
            for(int p=0;p<VoiceEngine.PROFILES.length;p++){
                double at60=live(e,p,.6,110),at100=live(e,p,1,110);
                System.out.printf(Locale.ROOT,"LEVEL,%d,%s,%.3f,%.3f%n",p,VoiceEngine.PROFILES[p],at60,at100);
                if(!measurementsOnly){
                    check(at60>100,"Preset audible at 60: "+p);
                    check(at100>at60*1.25,"Volume can increase beyond 60: "+p);
                }
            }
            if(measurementsOnly)return;
            check(live(e,1,0,110)==0,"Master mute is exact silence for live MIDI");
            check(e.consumeActivity()==110,"Listening mute does not remove world-noise activity");
            live(e,1,1,110);check(e.consumeActivity()==110,"Boost does not increase world-noise activity");
            double soft=live(e,1,1,32),hard=live(e,1,1,120);
            check(hard>soft*2,"Velocity dynamics remain at full master volume");
            double preview60=score(e,.6),preview100=score(e,1);
            check(preview100>preview60*1.25,"Master gain also controls unarmed score playback");
            check(score(e,0)==0,"Master mute is exact silence for score playback");
            score(e,1);e.scoreGain(0,0);render(e,4096);
            check(EngineTest.rms(render(e,1024))==0,"Track mute still silences the boosted output");
            e.scoreGain(0,1);check(EngineTest.rms(render(e,1024))>10,"Unmute restores the track");
            KahluaTable[] parts=new KahluaTable[8];
            for(int p=0;p<8;p++){
                KahluaTable[] notes=new KahluaTable[8];
                for(int n=0;n<8;n++)notes[n]=CompositionTest.note(48+n*3,0,192,127);
                parts[p]=CompositionTest.part(p,notes);
            }
            e.scoreStop();e.configure(8,0,-1,1);e.arm(true);
            e.scoreLoad(CompositionTest.parts(parts),120,384,true);e.scoreStart(0);
            for(int n=36;n<84;n++)e.midi(0x90,0,n,127);
            byte[] dense=render(e,16000);int peak=0;
            for(int i=0;i<dense.length;i+=2)peak=Math.max(peak,Math.abs((short)((dense[i]&255)|(dense[i+1]<<8))));
            check(peak>10000&&peak<=30000,"48 live keys plus eight parts and click remain bounded without PCM overflow");
            e.scoreStop();e.panic();check(EngineTest.rms(render(e,1024))==0,"Stop and panic leave exact silence after dense mix");
        }
        System.out.println("PASS: "+checks+" offline master-volume, dynamics, mute, world-noise and dense-mix checks");
    }
}
