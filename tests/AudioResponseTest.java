package azakaela.deadair;
import musician.gervill.*;
import java.nio.file.*;
import java.lang.reflect.*;
import java.util.*;
import javax.sound.sampled.*;

/** Tests actual SF2 dynamics and the production output worker with an in-memory line. */
public final class AudioResponseTest {
    static int checks;
    static void check(boolean value,String message){checks++;if(!value)throw new AssertionError(message);}
    static void curves()throws Exception {
        Method convert=SF2Instrument.class.getDeclaredMethod("convertSource",int.class);convert.setAccessible(true);
        int[] kinds={SF2Modulator.SOURCE_TYPE_LINEAR,SF2Modulator.SOURCE_TYPE_CONCAVE,SF2Modulator.SOURCE_TYPE_CONVEX,SF2Modulator.SOURCE_TYPE_SWITCH};
        int[] transforms={ModelStandardTransform.TRANSFORM_LINEAR,ModelStandardTransform.TRANSFORM_CONCAVE,ModelStandardTransform.TRANSFORM_CONVEX,ModelStandardTransform.TRANSFORM_SWITCH};
        for(int i=0;i<4;i++)for(int flags:new int[]{0,256,512,768})for(int source:new int[]{2,128+7,128+11}){
            ModelSource m=(ModelSource)convert.invoke(null,source|flags|kinds[i]);
            ModelStandardTransform t=(ModelStandardTransform)m.getTransform();
            check(t.getTransform()==transforms[i],"SF2 curve type decoded incorrectly");
            check(t.getDirection()==((flags&256)!=0)&&t.getPolarity()==((flags&512)!=0),"Direction/polarity changed with curve type");
        }
    }
    static double sound(VoiceEngine e,int profile,int velocity){
        e.configure(profile,0,-1,.69);e.arm(true);e.midi(0x90,0,60,velocity);
        check(e.attackVelocity()==velocity,"Touch response changed MIDI telemetry velocity");
        return EngineTest.rms(EngineTest.render(e,12000));
    }
    static void dynamics(Path common)throws Exception {
        try(VoiceEngine e=new VoiceEngine()){
            e.open(common,SoundfontSetup.bundled(common));SoundFontSampler.touchResponse(1);
            double quiet=sound(e,0,32),loud=sound(e,0,100);
            check(quiet>loud*.15,"Piano quiet layer is nearly muted");
            double below=sound(e,0,63),above=sound(e,0,64);
            check(above/below<1.8&&above/below>.6,"Piano has a binary half-velocity jump");
            double naturalGuitar=sound(e,1,16);
            SoundFontSampler.touchResponse(2);
            check(SoundFontSampler.playedVelocity(0)==0&&SoundFontSampler.playedVelocity(127)==127,"Touch curve breaks note-off/full accents");
            int previous=0;for(int v=1;v<=127;v++){int played=SoundFontSampler.playedVelocity(v);check(played>=previous&&played>=v&&played<=127,"Touch response is not bounded/monotonic");previous=played;}
            for(int p:new int[]{0,1})for(int v:new int[]{1,4,8,16,32,48,64,100,127})check(sound(e,p,v)>5,"Soft piano/guitar note rendered as silence");
            check(sound(e,1,16)>naturalGuitar*3,"Soft touch does not help light guitar notes");
            e.liveCapture(true);e.panic();e.midi(0x90,0,60,16);
            check(e.livePoll().rawget("events").toString().contains("144,60,16;"),"Touch response changed transmitted velocity");
            MidiTake take=new MidiTake();long now=1_000_000_000L;take.begin(120,384,-1,now);take.midi(0x90,0,60,16,now);take.midi(0x80,0,60,0,now+100_000_000);
            var recorded=(se.krka.kahlua.vm.KahluaTable)take.stop(now+200_000_000).rawget(1.0);
            check(((Number)recorded.rawget("v")).intValue()==16,"Touch response changed recorded velocity");
            SoundFontSampler.touchResponse(1);check(SoundFontSampler.playedVelocity(16)==16,"Natural response cannot be restored");
        }finally{SoundFontSampler.touchResponse(1);}
    }
    static final class MemoryLine implements InvocationHandler {
        final int capacity;int queued,maxQueued;volatile int firstNoteAhead=-1;long played;boolean closed;
        MemoryLine(int frames){capacity=frames;}
        synchronized void consume(int frames){int n=Math.min(queued,frames);queued-=n;played+=n;}
        synchronized int queued(){return queued;}
        public synchronized Object invoke(Object proxy,Method method,Object[] args){
            return switch(method.getName()) {
                case "getBufferSize"->capacity*4;
                case "available"->(capacity-queued)*4;
                case "getLongFramePosition"->played;
                case "write"->{int n=Math.min((int)args[2]/4,32);byte[] pcm=(byte[])args[0];for(int i=(int)args[1];i<(int)args[1]+n*4;i++)if(firstNoteAhead<0&&pcm[i]!=0)firstNoteAhead=queued;queued+=n;maxQueued=Math.max(maxQueued,queued);if(queued>capacity)throw new AssertionError("Worker overfilled line");yield n*4;}
                case "flush"->{queued=0;yield null;}
                case "close"->{closed=true;yield null;}
                case "isOpen","isRunning","isActive"->!closed;
                default->null;
            };
        }
        SourceDataLine line(){return (SourceDataLine)Proxy.newProxyInstance(getClass().getClassLoader(),new Class[]{SourceDataLine.class},this);}
    }
    interface Condition{boolean done();}
    static void await(Condition c)throws Exception {long end=System.nanoTime()+1_000_000_000L;while(!c.done()&&System.nanoTime()<end)Thread.sleep(1);check(c.done(),"Offline audio worker did not progress");}
    static long frame(VoiceEngine e)throws Exception {Field field=VoiceEngine.class.getDeclaredField("frame");field.setAccessible(true);synchronized(e){return field.getLong(e);}}
    static void queue(Path common)throws Exception {
        for(int capacity:new int[]{256,8192})for(int response=1;response<=3;response++){
            try(VoiceEngine e=new VoiceEngine()){
            e.open(common);e.configure(1,0,-1,.69);e.arm(true);MemoryLine line=new MemoryLine(capacity);
            try(AudioOutput output=new AudioOutput(e,response,format->line.line())){
                output.open();int target=output.queueTargetFrames();await(()->line.queued()==target);
                long frames=frame(e);Thread.sleep(8);check(frame(e)==frames,"Rendered future audio while queue was full");
                e.midi(0x90,0,60,100);
                for(int i=0;i<4&&line.firstNoteAhead<0;i++){line.consume(64);await(()->line.queued()==target);}
                check(line.firstNoteAhead>=0&&line.firstNoteAhead<target,"New note sits behind excess queued audio");
                check(line.maxQueued<=target,"Driver-expanded capacity became extra latency");
                check(output.error().isEmpty(),"Partial output writes failed");
            }
            check(line.closed,"Closing output leaked line");
            }
        }
    }
    public static void main(String[] args)throws Exception {
        curves();dynamics(Path.of(args[0]));queue(Path.of(args[0]));
        System.out.println("PASS: "+checks+" SF2 curves, quiet notes, raw velocity, and bounded output-queue checks; no hardware opened");
    }
}
