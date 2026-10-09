package azakaela.deadair;

import java.nio.file.Path;
import javax.sound.sampled.*;
import java.lang.reflect.Field;
import java.util.Locale;

/** Opt-in hardware smoke test. Streams only zero-volume PCM; no input port or recording is opened. */
public final class AudioOutputSmoke {
    public static void main(String[] args) throws Exception {
        try (VoiceEngine engine=new VoiceEngine(); AudioOutput out=new AudioOutput(engine)) {
            engine.open(Path.of(args[0]));engine.configure(8,0,-1,0);out.open();engine.arm(true);
            for(int key=36;key<84;key++)engine.midi(0x90,0,key,100);
            Field field=AudioOutput.class.getDeclaredField("line");field.setAccessible(true);
            SourceDataLine line=(SourceDataLine)field.get(out);
            long start=System.nanoTime();
            while(System.nanoTime()-start<3_000_000_000L) {engine.heartbeat();Thread.sleep(10);}
            long frames=line.getLongFramePosition();
            if(!out.isRunning() || !out.error().isEmpty() || frames<48000*2.5) throw new AssertionError("Audio worker stalled: "+frames+" frames, "+out.error());
            if(out.bufferFrames()<AudioOutput.BLOCK_FRAMES || out.queueTargetFrames()!=Math.min(out.bufferFrames(),AudioOutput.QUEUE_FRAMES[0])) throw new AssertionError("Invalid Fast queue target: "+out.queueTargetFrames());
            System.out.printf(Locale.ROOT,"PASS: production worker, muted 48-key sampler load, %s, block=%d, %.3fs output advanced in 3s%n",out.description(),AudioOutput.BLOCK_FRAMES,frames/48000.0);
        }
        AudioFormat format=new AudioFormat(48000,16,2,true,false);
        boolean found=false;
        for(Mixer.Info info:AudioSystem.getMixerInfo()) {
            if(!info.getName().startsWith("IXO22 (") || !AudioSystem.getMixer(info).isLineSupported(new DataLine.Info(SourceDataLine.class,format)))continue;
            found=true;
            try(SourceDataLine line=(SourceDataLine)AudioSystem.getMixer(info).getLine(new DataLine.Info(SourceDataLine.class,format))) {
                line.open(format,512*4);line.start();byte[] silence=new byte[128*4];
                long start=System.nanoTime();long max=0,framesWritten=0;
                while(System.nanoTime()-start<3_000_000_000L) {
                    long t=System.nanoTime();int written=line.write(silence,0,silence.length);
                    if(written!=silence.length)throw new AssertionError("Partial IXO22 test write");
                    max=Math.max(max,System.nanoTime()-t);framesWritten+=written/4;
                }
                if(line.getLongFramePosition()<48000*2.5)throw new AssertionError("IXO22 stream stalled");
                System.out.printf(Locale.ROOT,"PASS: %s / actual buffer %d frames / %.2f ms; %.3fs output advanced; max write wait %.3f ms; %d frames written%n",info.getName(),line.getBufferSize()/4,line.getBufferSize()/192.0,line.getLongFramePosition()/48000.0,max/1e6,framesWritten);
                line.stop();line.flush();
            }
        }
        if(!found)System.out.println("IXO22 not found; only the default-output smoke test ran.");
        System.out.println("Silent streaming only; no physical controller-to-headphone latency or listening quality measurement.");
    }
}
