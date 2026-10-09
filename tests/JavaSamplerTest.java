package azakaela.deadair;
import java.nio.file.*;
import java.util.*;

/** Actual Java renderer and shipped SF2; never opens MIDI/audio devices. */
public final class JavaSamplerTest {
    static int checks;
    static void check(boolean ok,String why){checks++;if(!ok)throw new AssertionError(why);}
    static void drain(SoundFontSampler s){s.render(256);s.render(256);}
    static int onset(SoundFontSampler s,int channel,int velocity){
        s.noteOn(channel,60,velocity);int onset=-1;
        for(int t=0;t<1024;t+=64){float[] a=s.render(64);for(int i=0;i<128;i++)if(onset<0&&Math.abs(a[i])>.00001)onset=t+i/2;}
        return onset;
    }
    public static void main(String[] args)throws Exception{
        Path common=Path.of(args[0]);
        check(!Files.exists(common.resolve("media/native")),"Clean payload must not rely on native sampler/output files");
        for(int count:new int[]{16,128})for(int velocity:new int[]{16,75,110,127}){
            try(SoundFontSampler s=new SoundFontSampler(common,count,count==16?128:256)){
                for(int c=0;c<count;c++){s.resetChannel(c);s.presetChannel(c,0,25,false);}
                for(int channel:new int[]{0,count-1}){
                    for(int i=0;i<15;i++)s.render(256);
                    int first=onset(s,channel,velocity);
                    check(first>=0 && first<128,"SF2 guitar sample offset removes recorded silence; onset="+first);
                    s.cc(channel,64,127);s.noteOff(channel,60);drain(s);
                    check(s.voices()>0,"Pedal retains released note");
                    s.silence(channel);drain(s);
                    check(s.voices()==0,"All-sound-off also ends released pedal voices");
                    s.resetChannel(channel);drain(s);
                }
            }
        }
        try(SoundFontSampler a=new SoundFontSampler(common);SoundFontSampler b=new SoundFontSampler(common)){
            a.preset(0,25,false);b.preset(0,25,false);a.resetChannel(0);b.resetChannel(0);
            drain(a);drain(b);a.noteOn(0,60,100);b.noteOn(0,60,100);
            float[] whole=a.render(256).clone(),split=new float[512];int at=0;
            for(int n:new int[]{1,7,63,128,57}){float[] p=b.render(n);System.arraycopy(p,0,split,at*2,n*2);at+=n;}
            check(Arrays.equals(whole,split),"Partial rendering does not skip or duplicate samples");
        }
        System.out.println("PASS: "+checks+" Java-only payload, sample-onset, global SF2 offset, pedal cleanup, high-channel and render-boundary checks; no hardware opened");
    }
}