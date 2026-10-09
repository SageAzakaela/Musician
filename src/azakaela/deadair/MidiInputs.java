package azakaela.deadair;

import javax.sound.midi.*;
import java.util.*;

/** Refreshable device identities: Windows can renumber ports when USB devices change. */
final class MidiInputs {
    record Entry(MidiDevice.Info info,String key) {}
    interface Provider {
        MidiDevice.Info[] infos();
        MidiDevice device(MidiDevice.Info info) throws MidiUnavailableException;
    }
    static final Provider SYSTEM=new Provider(){
        public MidiDevice.Info[] infos(){return MidiSystem.getMidiDeviceInfo();}
        public MidiDevice device(MidiDevice.Info info)throws MidiUnavailableException{return MidiSystem.getMidiDevice(info);}
    };
    static List<Entry> scan(Provider provider){
        List<Entry> found=new ArrayList<>();Map<String,Integer> copies=new HashMap<>();
        for(MidiDevice.Info info:provider.infos()){
            try {
                MidiDevice d=provider.device(info);
                if(d instanceof Sequencer || d instanceof Synthesizer || d.getMaxTransmitters()==0)continue;
                String signature=info.getClass().getName()+"|"+field(info.getName())+field(info.getVendor())+field(info.getDescription())+field(info.getVersion());
                int ordinal=copies.merge(signature,1,Integer::sum);
                found.add(new Entry(info,signature+"|"+ordinal));
            }catch(MidiUnavailableException|IllegalArgumentException ignored){ /* One vanished port must not hide the others. */ }
        }
        return List.copyOf(found);
    }
    private static String field(String value){return value.length()+":"+value;}
    static int index(List<Entry> entries,String key){
        for(int i=0;i<entries.size();i++)if(entries.get(i).key().equals(key))return i;
        return -1;
    }
    static MidiDevice resolve(Provider provider,String key)throws MidiUnavailableException{
        List<Entry> fresh=scan(provider);int index=index(fresh,key);
        if(index<0)throw new MidiUnavailableException("Selected MIDI input is no longer available. Refresh and choose it again.");
        return provider.device(fresh.get(index).info());
    }
}
