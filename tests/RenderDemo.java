package azakaela.deadair;

import java.io.*;
import java.nio.file.*;
import javax.sound.sampled.*;

/** Original audition phrase rendered offline through the production sampler; never opens speakers. */
public final class RenderDemo {
    public static void main(String[] args) throws Exception {
        ByteArrayOutputStream pcm=new ByteArrayOutputStream();
        try(VoiceEngine e=new VoiceEngine()) {
            e.open(Path.of(args[0]));
            for(int p:new int[]{0,1,7,8,9}) {
                e.configure(p,0,-1,.3);e.arm(true);
                for(int i=0;i<6;i++) {
                    int key=p==9?new int[]{36,42,38,42,36,38}[i]:new int[]{60,64,67,72,67,64}[i];
                    e.midi(0x90,0,key,i%2==0?104:86);pcm.write(EngineTest.render(e,14400));
                    e.midi(0x80,0,key,0);pcm.write(EngineTest.render(e,4800));
                }
                pcm.write(EngineTest.render(e,24000));e.panic();pcm.write(new byte[4800*4]);
            }
        }
        byte[] bytes=pcm.toByteArray();Path target=Path.of(args[1]);
        try(AudioInputStream stream=new AudioInputStream(new ByteArrayInputStream(bytes),new AudioFormat(48000,16,2,true,false),bytes.length/4)) {
            AudioSystem.write(stream,AudioFileFormat.Type.WAVE,target.toFile());
        }
        System.out.println("Rendered piano, acoustic guitar, alto sax, violin and drums: "+target);
    }
}
