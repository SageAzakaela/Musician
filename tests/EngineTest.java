package azakaela.deadair;

import java.nio.file.*;
import java.util.*;

/** Exercises the real bundled DLL and SF2, not a mock sampler. Does not open speakers or MIDI ports. */
public final class EngineTest {
    static int checks;
    static void check(boolean yes,String message) { checks++; if(!yes) throw new AssertionError(message); }
    static byte[] render(VoiceEngine e,int frames) {
        byte[] result=new byte[frames*4], block=new byte[256*4];
        for(int i=0;i<frames;i+=256) {
            int n=Math.min(256,frames-i);e.heartbeat();e.render(block,n);System.arraycopy(block,0,result,i*4,n*4);
        }
        return result;
    }
    static double rms(byte[] a) {
        double sum=0;for(int i=0;i<a.length;i+=2) { int n=(short)((a[i]&255)|(a[i+1]<<8));sum+=(double)n*n; }
        return Math.sqrt(sum/(a.length/2));
    }
    // Drum decay thresholds were measured at the original master calibration.
    // Normalize quiet tails only; loudness and peak tests use the actual boosted PCM.
    static double referenceTailRms(byte[] pcm) { return rms(pcm)/VoiceEngine.OUTPUT_GAIN; }
    static void start(VoiceEngine e,int p) { e.configure(p,0,-1,.3);e.arm(true); }
    static void silent(VoiceEngine e,String label) { check(rms(render(e,1024))==0,label); }
    static double pitch(byte[] a) {
        int crossings=0;
        for(int i=4;i<a.length;i+=4) {
            int prev=(short)((a[i-4]&255)|(a[i-3]<<8)),now=(short)((a[i]&255)|(a[i+1]<<8));
            if(prev<=0 && now>0) crossings++;
        }
        return crossings*48000.0/(a.length/4);
    }
    public static void main(String[] args) throws Exception {
        Path common=Path.of(args[0]);
        try(VoiceEngine e=new VoiceEngine()) {
            e.arm(true);check(!e.isArmed(),"No silent fallback when sampler is unavailable");
            try { e.open(common.resolve("missing"));throw new AssertionError("Missing bank accepted"); }
            catch(IllegalStateException expected) { check(!e.ready(),"Failed load cleans up"); }
            e.open(common);check(e.ready() && e.soundStatus().contains("Gervill"),"Real native library and bank loaded");
            Set<Integer> timbres=new HashSet<>();
            for(int p=0;p<VoiceEngine.PROFILES.length;p++) {
                start(e,p);long attacks=e.attackSerial();int key=p==9?36:60;
                e.midi(0x90,0,key,110);byte[] pcm=render(e,16000);
                double level=rms(pcm);System.out.printf(Locale.ROOT,"%s RMS %.1f, voices %d%n",VoiceEngine.PROFILES[p],level,e.activeVoices());
                check(level>15,"Audible bank preset: "+p);
                timbres.add(Arrays.hashCode(pcm));
                check(e.attackSerial()==attacks+1 && e.attackVelocity()==110,"Attack telemetry: "+p);
                check(e.motionState().held()==1 && e.motionState().note()==(p==13?36:p==14?43:p==15?38:key),"Physical held key survives sample decay: "+p);
                e.midi(0x80,0,key,0);
                check(e.motionState().held()==0,"Physical release independent of voice tails: "+p);
                render(e,48000*5);
                if(p==14){System.out.printf(Locale.ROOT,"Floor tom at five seconds: RMS %.2f%n",rms(render(e,4096)));render(e,48000*3);}
                check(e.activeVoices()==0 || ((p==9 || p>=13) && referenceTailRms(render(e,4096))<4),"Released note ends or drum tail reaches original decay threshold: "+p);
            }
            check(timbres.size()>=13,"Distinct sampled instrument outputs");
            start(e,9);
            int[] surfaces={36,38,42,44,43,47,50,51};
            for(int n:surfaces)e.midi(0x90,0,n,110);
            var drums=e.drumState();
            for(String name:DrumActivity.NAMES){var row=(se.krka.kahlua.vm.KahluaTable)drums.rawget(name);check(((Number)row.rawget("attack")).intValue()==1&&((Number)row.rawget("velocity")).intValue()==110,"Simultaneous MIDI surface telemetry: "+name);}
            check(DrumActivity.group(39)==-1&&DrumActivity.group(60)==-1,"Handclap and auxiliary percussion do not fabricate kit strikes");
            e.panic();for(String name:DrumActivity.NAMES)check(((Number)((se.krka.kahlua.vm.KahluaTable)e.drumState().rawget(name)).rawget("attack")).intValue()==0,"Panic clears surface: "+name);
            start(e,5);e.midi(0x90,0,38,100);check(e.drumState().rawget("snare")==null,"Melodic pitch 38 does not become a snare hit");
            start(e,8);e.midi(0x90,0,60,80);e.midi(0x90,0,60,110);
            check(e.motionState().held()==1,"Repeated key-on does not leak held count");
            e.midi(0x90,1,60,100);check(e.motionState().held()==2,"Same pitch on different channels has separate held state");
            e.midi(0xB0,0,123,0);check(e.motionState().held()==1,"Channel notes-off preserves another channel's keys");
            e.midi(0xB0,1,120,0);check(e.motionState().held()==0,"Channel sound-off clears held keys");
            long generation=e.motionState().reset();e.panic();
            check(e.motionState().reset()>generation && e.motionState().resetAttack()==e.attackSerial(),"Panic supplies an atomic reset baseline");
            start(e,9);e.midi(0x90,0,36,100);render(e,48000*3);
            check(e.activeVoices()==0 && e.motionState().held()==1,"Finished drum sample does not fabricate physical key-up");
            render(e,48000*28);check(e.motionState().held()==0,"Lost held key expires even after its sample has decayed");
            start(e,8);e.midi(0x90,0,60,100);e.midi(0xB0,0,64,127);e.midi(0x90,0,60,0);
            check(rms(render(e,48000))>50 && e.activeVoices()>0,"Sustain holds velocity-zero note-off");
            check(e.motionState().held()==0,"Pedal sustain never keeps bow/wind gestures held");
            e.midi(0xB0,0,64,0);render(e,48000*3);check(e.activeVoices()==0,"Pedal release clears voices");
            start(e,8);e.midi(0x90,0,60,100);e.midi(0xB0,0,64,127);e.midi(0x80,0,60,0);e.midi(0xB0,0,121,0);
            render(e,48000*3);check(e.activeVoices()==0,"Reset controllers releases sustained notes");
            start(e,8);e.midi(0x90,0,60,100);e.midi(0x90,1,64,100);render(e,512);int both=e.activeVoices();
            e.midi(0xB0,0,120,0);render(e,512);check(e.activeVoices()>0 && e.activeVoices()<both,"Channel all-sound-off preserves other channel");
            e.midi(0xB0,1,123,0);render(e,48000*3);check(e.activeVoices()==0,"All-notes-off releases remaining channel");
            start(e,8);e.midi(0x90,0,60,100);render(e,100);e.panic();silent(e,"Panic flushes even partial native audio blocks");
            check(e.activeVoices()==0 && e.consumeActivity()==0,"Panic clears sound and world-noise state");
            e.midi(0x90,0,60,100);e.arm(false);silent(e,"Disarmed output silent");
            long serial=e.attackSerial();e.midi(0x90,0,60,100);check(e.attackSerial()==serial,"Disarmed MIDI cannot gesture");
            start(e,0);e.configure(0,12,1,.3);serial=e.attackSerial();
            e.midi(0x90,0,60,100);e.midi(0x90,1,127,100);check(e.attackSerial()==serial,"Channel and transposed range filtering");
            check(e.motionState().held()==0,"Rejected MIDI cannot enter physical gesture state");
            e.midi(0x90,1,60,100);check(rms(render(e,512))>10,"Selected channel accepted");
            e.configure(0,0,1,.3);silent(e,"Transpose change silences previous notes");
            start(e,8);e.midi(0x90,0,60,100);e.expire(Long.MAX_VALUE);
            check(!e.isArmed() && e.activeVoices()==0,"Watchdog disarms missing heartbeat");silent(e,"Watchdog silences output");
            check(e.motionState().held()==0,"Watchdog clears held gestures");
            start(e,5);e.midi(0x90,0,69,32);double quiet=rms(render(e,12000));
            e.panic();e.midi(0x90,0,69,120);check(rms(render(e,12000))>quiet*2,"Velocity affects sampled loudness");
            e.midi(0xB0,0,7,0);render(e,4096);check(rms(render(e,1024))<1,"CC7 channel mute");
            e.midi(0xB0,0,7,127);e.midi(0xB0,0,11,0);render(e,4096);check(rms(render(e,1024))<1,"CC11 expression mute");
            start(e,8);e.midi(0x90,0,60,100);check(e.consumeActivity()==100,"MIDI attacks reach world noise");
            e.configure(8,0,-1,0);silent(e,"Listening mute produces exact silence");check(e.consumeActivity()>0,"Listening mute preserves world noise");
            start(e,12);e.midi(0x90,0,69,100);render(e,4800);double base=pitch(render(e,48000));
            System.out.printf(Locale.ROOT,"Tuning fork A4 %.1f Hz%n",base);check(Math.abs(base-440)<5,"Tuning fork uses true-pitch sine preset");
            e.midi(0xE0,0,127,127);render(e,4096);double bent=pitch(render(e,48000));
            check(Math.abs(bent/base-Math.pow(2,2/12.0))<.02,"Pitch bend reaches two semitones");
            start(e,5);e.midi(0x90,9,69,100);check(rms(render(e,12000))>50,"MIDI channel ten remains melodic for flute");
            e.midi(0xC0,9,0,0);e.midi(0xB0,9,0,128);check(e.isArmed(),"Program and malformed bank messages cannot switch instruments");
            for(int p=13;p<=15;p++) {
                start(e,p);e.configure(p,24,-1,.3);e.midi(0x90,0,127,110);
                check(rms(render(e,12000))>15,"Placed drum ignores transpose and maps any key: "+p);
                e.midi(0x90,0,126,100);e.midi(0x80,0,127,0);check(rms(render(e,12000))>15,"Drum strike survives another key's release: "+p);
                render(e,48000*10);double tail=rms(render(e,4096));System.out.printf(Locale.ROOT,"Drum %d at ten seconds: RMS %.2f%n",p,tail);
                check(tail/VoiceEngine.OUTPUT_GAIN<(p==14?4:1),"One-shot drums retain original decay without key-up: "+p);
            }
            start(e,14);e.midi(0x90,0,60,100);e.midi(0x80,0,60,0);e.midi(0xB0,0,64,127);
            render(e,48000*10);check(referenceTailRms(render(e,4096))<4,"Floor-tom auto-release survives sustain CC after key-up at original decay threshold");
            start(e,8);e.midi(0x90,0,60,100);e.midi(0xB0,0,64,127);e.midi(0x80,0,60,0);
            render(e,48000*31);check(e.activeVoices()==0,"Thirty-second safety cutoff clears a pedal-held lost note");
            start(e,8);for(int n=36;n<84;n++) e.midi(0x90,0,n,100);
            long time=System.nanoTime();byte[] stress=render(e,48000);double seconds=(System.nanoTime()-time)/1e9;
            System.out.printf(Locale.ROOT,"48-key / %d-native-voice render: %.3fs per 1s audio%n",e.activeVoices(),seconds);
            check(seconds<1,"Sampler keeps up with real time on this machine");
            int peak=0;for(int i=0;i<stress.length;i+=2) peak=Math.max(peak,Math.abs((short)((stress[i]&255)|(stress[i+1]<<8))));
            check(peak<=30000,"PCM limiter prevents clipping overflow");
            Random random=new Random(721);
            for(int i=0;i<5000;i++) {e.heartbeat();e.midi(new int[]{0x90,0x80,0xB0,0xE0}[random.nextInt(4)],random.nextInt(20)-2,random.nextInt(150)-10,random.nextInt(150)-10);}
            render(e,1024);check(e.activeVoices()<=VoiceEngine.MAX_VOICES,"Random and malformed MIDI bounded by native polyphony");
            check(e.isArmed() && e.error().isEmpty(),"Synchronous Java MIDI stays armed under dense input with bounded polyphony");
            e.panic();silent(e,"Stress panic silence");
            start(e,8);check(e.error().isEmpty(),"Starting again clears overload status");
            Thread input=new Thread(()->{for(int i=0;i<1000;i++){e.midi(0x90,i%16,60+i%12,90);e.midi(0x80,i%16,60+i%12,0);}});
            input.start();render(e,24000);input.join();e.panic();silent(e,"Concurrent MIDI and audio safely serialized");
            for(int cycle=0;cycle<3;cycle++) {e.close();check(!e.ready(),"Native instance closes");e.open(common);start(e,0);e.midi(0x90,0,60,100);check(rms(render(e,1024))>10,"Native instance reconnects");}
            e.close();e.render(new byte[16],4);check(e.activeVoices()==0,"Render after close cannot access freed native memory");
        }
        System.out.println("PASS: "+checks+" actual Gervill, sampled audio and MIDI safety checks");
    }
}
