package azakaela.deadair;

import javax.sound.midi.*;
import java.util.*;

/** Synthetic packets and fake ports only: never enumerates or opens real hardware. */
public final class MidiInputTest {
    static int checks;
    static void check(boolean ok,String why){checks++;if(!ok)throw new AssertionError(why);}
    static ShortMessage packet(int command,int channel,int a,int b)throws Exception{
        return new ShortMessage(command,channel,a,b);
    }
    static final class Raw extends MidiMessage {
        Raw(int... values){super(new byte[values.length]);for(int i=0;i<values.length;i++)data[i]=(byte)values[i];}
        public Object clone(){return this;}
    }
    static final class TestInfo extends MidiDevice.Info {
        TestInfo(String name){super(name,"Test vendor","Test input","1");}
    }
    static final class Port implements MidiDevice {
        final TestInfo info;final int transmitters;
        Port(String name,int transmitters){this.info=new TestInfo(name);this.transmitters=transmitters;}
        public TestInfo getDeviceInfo(){return info;}
        public void open(){throw new AssertionError("Tests must never open a device");}
        public void close(){}
        public boolean isOpen(){return false;}
        public long getMicrosecondPosition(){return -1;}
        public int getMaxReceivers(){return 0;}
        public int getMaxTransmitters(){return transmitters;}
        public Receiver getReceiver(){throw new AssertionError("No device receivers in this test");}
        public List<Receiver> getReceivers(){return List.of();}
        public Transmitter getTransmitter(){throw new AssertionError("No device transmitters in this test");}
        public List<Transmitter> getTransmitters(){return List.of();}
    }
    static final class Provider implements MidiInputs.Provider {
        List<Port> ports;MidiDevice.Info broken=new TestInfo("Vanished port");
        Provider(Port... ports){this.ports=List.of(ports);}
        public MidiDevice.Info[] infos(){var infos=new ArrayList<MidiDevice.Info>();infos.add(broken);for(var p:ports)infos.add(p.info);return infos.toArray(MidiDevice.Info[]::new);}
        public MidiDevice device(MidiDevice.Info info)throws MidiUnavailableException{
            for(var p:ports)if(p.info==info)return p;
            throw new MidiUnavailableException("Port disappeared");
        }
    }
    public static void main(String[] args)throws Exception{
        List<int[]> received=new ArrayList<>();
        MidiInputReceiver r=new MidiInputReceiver((cmd,ch,a,b,time)->received.add(new int[]{cmd,ch,a,b}));
        check(r.notes()==0 && r.lastChannel()==-1 && r.status().contains("waiting"),"Fresh input waits for notes");
        for(int c=0;c<16;c++){
            r.send(packet(0x90,c,60,100),-1);
            r.send(packet(0x80,c,60,0),-1);
        }
        check(r.notes()==16 && received.size()==32,"All 16 channels, including six independent guitar strings");
        for(int c=0;c<16;c++)check(received.get(c*2)[1]==c,"Channel preserved "+c);
        r.send(packet(0x90,3,61,0),-1);
        check(r.notes()==16 && received.get(32)[3]==0,"Velocity-zero release is forwarded, not counted as a note");
        r.send(new Raw(0x95,42,81),-1);
        check(r.notes()==17 && r.lastNote()==42 && r.lastChannel()==5 && r.lastVelocity()==81,"Provider-specific message delivers note/channel/velocity");
        r.send(new Raw(0x85,42,0),-1);
        r.send(new Raw(0xb5,64,127),-1);
        r.send(new Raw(0xe5,0,64),-1);
        r.send(new Raw(0xc5,25),-1);
        check(received.size()==38,"Note-off, sustain, bend and two-byte messages preserved");
        long before=r.messages();int delivered=received.size();
        for(var m:List.of(new Raw(0xf8),new Raw(0xfe),new Raw(0xf0,1,2,0xf7),new Raw(0x90,60),new Raw(0x90,128,99)))r.send(m,-1);
        check(r.messages()==before+5 && received.size()==delivered,"Non-note traffic counted, malformed packets ignored");
        check(r.status().contains("channels 1,2,3,4,5,6"),"Visible string-channel evidence");
        r.close();before=r.messages();r.send(packet(0x90,0,60,90),-1);
        check(!r.active() && r.messages()==before && received.size()==delivered && r.status().contains("closed"),"Retired receiver rejects late callbacks");
        MidiInputReceiver fresh=new MidiInputReceiver((cmd,ch,a,b,time)->{});
        check(fresh.notes()==0 && fresh.messages()==0 && fresh.lastNote()==-1,"Reconnect starts fresh counters");
        MidiInputReceiver failing=new MidiInputReceiver((cmd,ch,a,b,time)->{throw new IllegalStateException("test failure");});
        failing.send(packet(0x90,0,60,99),-1);
        check(!failing.active() && failing.status().contains("test failure") && failing.notes()==1,"Receive failures visible and invalidate connection instead of silently losing notes");
        MidiTake take=new MidiTake();take.begin(120,384,-1,System.nanoTime());
        MidiInputReceiver recorder=new MidiInputReceiver((cmd,ch,a,b,time)->take.midi(cmd,ch,a,b,time));
        for(int c=0;c<6;c++)recorder.send(packet(0x90,c,60,100),-1);
        for(int c=0;c<6;c++)recorder.send(packet(0x80,c,60,0),-1);
        check(take.stop(System.nanoTime()).len()==6,"Six strings on the same pitch remain separate in recording");
        Port keyboard=new Port("Keyboard",-1),guitar=new Port("AeroBand Midi",-1),out=new Port("Output",0);
        Provider provider=new Provider(keyboard,out,guitar);
        var original=MidiInputs.scan(provider);
        check(original.size()==2,"Output and vanished port excluded without hiding working inputs");
        String guitarKey=original.get(1).key();
        Port replugged=new Port("AeroBand Midi",-1);provider.ports=List.of(replugged,keyboard,out);
        check(MidiInputs.index(MidiInputs.scan(provider),guitarKey)==0,"Selection follows identity after reorder");
        check(MidiInputs.resolve(provider,guitarKey)==replugged,"Connection resolves fresh provider info after replug");
        provider.ports=List.of(keyboard);
        try{MidiInputs.resolve(provider,guitarKey);throw new AssertionError("Must not fall back to keyboard");}
        catch(MidiUnavailableException expected){check(expected.getMessage().contains("no longer available"),"Missing input fails explicitly");}
        provider.ports=List.of(new Port("AeroBand Midi",-1),new Port("AeroBand Midi",-1));
        var duplicates=MidiInputs.scan(provider);
        check(!duplicates.get(0).key().equals(duplicates.get(1).key()),"Identical names retain separate ordinal identities");
        VoiceEngine engine=new VoiceEngine();engine.configure(0,0,0,0.3);
        check(engine.inputRouteStatus(5).contains("filtered out"),"Channel mismatch visible without sampler startup");
        engine.configure(0,0,-1,0.3);
        check(!engine.inputRouteStatus(5).contains("filtered out"),"All-channel mode accepts guitar channels");
        System.out.println("PASS: "+checks+" hardware-free MIDI input checks; no devices enumerated or opened");
    }
}
