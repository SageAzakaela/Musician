package azakaela.deadair;
import javax.sound.midi.*;
import javax.sound.sampled.*;
public final class Diagnostics {
    public static void main(String[] args) throws Exception {
        System.out.println("Java: "+System.getProperty("java.version"));
        System.out.println("Game: "+zombie.core.Core.getInstance().getVersion());
        int count=0;
        for(MidiDevice.Info info:MidiSystem.getMidiDeviceInfo()) {
            MidiDevice d=MidiSystem.getMidiDevice(info);
            if(!(d instanceof Sequencer) && !(d instanceof Synthesizer) && d.getMaxTransmitters()!=0) {
                System.out.println("MIDI input "+count+++": "+info.getName()+" / "+info.getVendor());
            }
        }
        System.out.println("Input count: "+count+" (none opened)");
        AudioFormat format=new AudioFormat(48000,16,2,true,false);
        System.out.println("48kHz stereo PCM output supported: "+AudioSystem.isLineSupported(new DataLine.Info(SourceDataLine.class,format)));
    }
}
