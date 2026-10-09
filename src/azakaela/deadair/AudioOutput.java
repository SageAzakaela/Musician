package azakaela.deadair;

import javax.sound.sampled.*;
import java.nio.file.Path;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.locks.LockSupport;

/** Built-in Java Sound output; no additional runtime, helper process or native library. */
public final class AudioOutput implements AutoCloseable {
    static final int BLOCK_FRAMES=64;
    static final int[] BUFFER_FRAMES={256,1024,2048};
    static final int[] QUEUE_FRAMES={128,512,1536};
    interface LineFactory {SourceDataLine create(AudioFormat format)throws LineUnavailableException;}
    private final LineFactory lines;
    private final VoiceEngine engine;
    private final int response,driver;
    private final CountDownLatch started=new CountDownLatch(1);
    private volatile SourceDataLine line;
    private volatile boolean running;
    private volatile String error="",description="Audio opening";
    private volatile int acceptedFrames;
    private volatile int queuedTarget;
    private volatile long advancedFrames;
    private Thread thread;
    public AudioOutput(VoiceEngine engine) {this(engine,1);}
    public AudioOutput(VoiceEngine engine,int response) {this(engine,response,null,4);}
    public AudioOutput(VoiceEngine engine,int response,Path common,int driver) {
        this(engine,response,AudioSystem::getSourceDataLine);
    }
    AudioOutput(VoiceEngine engine,int response,LineFactory lines) {
        this.engine=engine;this.response=Math.max(1,Math.min(3,response));this.driver=4;this.lines=lines;
    }
    static String responseName(int value) {return switch(value) {case 2 -> "Balanced";case 3 -> "Extra stability";default -> "Fast";};}
    static String driverName(int value) {return "Java Sound";}
    public int response() {return response;}
    public int driver() {return driver;}
    public String description() {return "Audio: "+description;}
    public void open() throws LineUnavailableException {
        running=true;
        thread=new Thread(this::pump,"DeadAir-Audio");thread.setDaemon(true);thread.setPriority(Thread.NORM_PRIORITY+2);thread.start();
        try {
            if(!started.await(10,TimeUnit.SECONDS)) {close();throw new LineUnavailableException("Audio driver took too long to open");}
        } catch(InterruptedException e) {Thread.currentThread().interrupt();close();throw new LineUnavailableException("Audio connection interrupted");}
        if(!running)throw new LineUnavailableException(error);
    }
    private void ready(String label,int frames) {description=label;acceptedFrames=frames;started.countDown();}
    private void pump() {
        try {
            AudioFormat format=new AudioFormat(VoiceEngine.RATE,16,2,true,false);
            SourceDataLine candidate=lines.create(format);line=candidate;
            candidate.open(format,BUFFER_FRAMES[response-1]*4);candidate.start();
            int capacity=candidate.getBufferSize()/4;
            if(capacity<BLOCK_FRAMES)throw new IllegalStateException("Audio buffer is too small");
            queuedTarget=Math.min(capacity,QUEUE_FRAMES[response-1]);
            ready(String.format(java.util.Locale.ROOT,"Java Sound / %s / queue target %.1f ms / buffer %.1f ms",responseName(response),queuedTarget/48.0,capacity/48.0),capacity);
            byte[] buffer=new byte[BLOCK_FRAMES*4];
            while(running) {
                // Some Java mixers enlarge the requested buffer. Filling that whole
                // buffer (and rendering the next block before write blocks) adds delay.
                // Wait BEFORE rendering so newly arrived MIDI reaches the next block.
                int free=candidate.available()/4;
                int queued=capacity-Math.max(0,Math.min(capacity,free));
                if(free<BLOCK_FRAMES || queued+BLOCK_FRAMES>queuedTarget){
                    advancedFrames=candidate.getLongFramePosition();
                    LockSupport.parkNanos(250_000L);continue;
                }
                engine.render(buffer,BLOCK_FRAMES);
                int offset=0;
                while(running && offset<buffer.length) {
                    int written=candidate.write(buffer,offset,buffer.length-offset);
                    if(written<=0)throw new IllegalStateException("Audio output stopped accepting samples");offset+=written;
                }
                advancedFrames=candidate.getLongFramePosition();
            }
        } catch(Exception | LinkageError e) {if(running)error="Audio stopped: "+(e.getMessage()==null?e.getClass().getSimpleName():e.getMessage());}
        finally {running=false;started.countDown();engine.arm(false);SourceDataLine current=line;if(current!=null)current.close();}
    }
    public boolean isRunning() {return running;}
    public String error() {return error;}
    public int bufferFrames() {return acceptedFrames;}
    public int queueTargetFrames() {return queuedTarget;}
    public long advancedFrames() {return advancedFrames;}
    public long underflows() {return 0;}
    @Override public void close() {
        running=false;engine.arm(false);
        SourceDataLine current=line;
        if(current!=null) {current.stop();current.flush();current.close();}
        if(thread!=null && Thread.currentThread()!=thread) {
            try {thread.join(5000);}catch(InterruptedException e) {Thread.currentThread().interrupt();throw new IllegalStateException("Audio shutdown interrupted",e);}
            if(thread.isAlive())throw new IllegalStateException("Audio driver has not stopped; sampler remains allocated");
        }
    }
}
