package azakaela.deadair;

import java.nio.file.Path;
import javax.sound.midi.ShortMessage;

/** Synthetic six-string packets through the real receiver and acoustic sampler; no device access. */
public final class GuitarInputTest {
    static int checks;
    static void check(boolean yes,String why){checks++;if(!yes)throw new AssertionError(why);}
    static void send(MidiInputReceiver r,boolean packed,int cmd,int ch,int a,int b)throws Exception{
        if(packed)r.sendPacked((cmd|ch)|(a<<8)|(b<<16),3,System.nanoTime());
        else r.send(new ShortMessage(cmd,ch,a,b),-1);
    }
    public static void main(String[] args)throws Exception{
        try(VoiceEngine e=new VoiceEngine()){
            e.open(Path.of(args[0]));
            for(boolean packed:new boolean[]{false,true}){
                String route=packed?"Windows packets":"Java packets";
                MidiInputReceiver r=new MidiInputReceiver((cmd,ch,a,b,time)->e.midi(cmd,ch,a,b));
                EngineTest.start(e,1);
                long before=e.attackSerial();
                int[] chord={40,47,52,56,59,64};
                for(int c=0;c<6;c++)send(r,packed,0x90,c,chord[c],70+c*8);
                check(e.attackSerial()==before+6 && e.motionState().held()==6,route+": all six acoustic strings accepted");
                check(EngineTest.rms(EngineTest.render(e,256))>10 && e.activeVoices()>=6,route+": real acoustic sound bank voices every string");
                int voices=e.activeVoices();
                for(int c=0;c<6;c++){
                    send(r,packed,0xb0,c,120,0);
                    EngineTest.render(e,256);
                    check(e.activeVoices()<voices && (c==5 || e.activeVoices()>0),route+": muting string "+(c+1)+" removes only its native voices");
                    voices=e.activeVoices();
                }
                EngineTest.start(e,1);
                for(int c=0;c<6;c++)send(r,packed,0x90,c,60,90);
                EngineTest.render(e,256);
                for(int c=0;c<6;c++){
                    send(r,packed,c%2==0?0x80:0x90,c,60,0);
                    check(e.motionState().held()==5-c,route+": same-pitch string releases independently "+c);
                }
                EngineTest.render(e,VoiceEngine.RATE*5);
                check(e.activeVoices()==0,route+": every same-pitch release reaches native sampler");
                for(int velocity=1;velocity<=127;velocity++){
                    EngineTest.start(e,1);
                    send(r,packed,0x90,velocity%6,60,velocity);
                    check(r.lastVelocity()==velocity && e.attackVelocity()==velocity,route+": velocity preserved exactly: "+velocity);
                    send(r,packed,0x80,velocity%6,60,127);
                    check(r.lastVelocity()==velocity && e.attackVelocity()==velocity,route+": release velocity cannot replace attack velocity");
                }
                EngineTest.start(e,1);before=e.attackSerial();
                // Unsupported controllers do not enqueue native events. They must not spend its budget.
                for(int c=0;c<6;c++){
                    for(int i=0;i<20;i++)send(r,packed,0xb0,c,74,i);
                    send(r,packed,0x90,c,chord[c],95);
                }
                check(e.isArmed() && e.error().isEmpty() && e.attackSerial()==before+6 && e.motionState().held()==6,
                    route+": ignored-controller bursts cannot disarm or cut off a chord");
                check(EngineTest.rms(EngineTest.render(e,1024))>10 && e.activeVoices()>=6,route+": chord survives controller burst in native audio");
                r.close();e.panic();
            }
        }
        System.out.println("PASS: "+checks+" acoustic-guitar packet, native chord and velocity checks; no MIDI/audio device opened");
    }
}
