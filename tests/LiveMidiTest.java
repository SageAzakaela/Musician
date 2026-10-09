package azakaela.deadair;

import java.nio.file.Path;
import se.krka.kahlua.vm.KahluaTable;

/** Synthetic network packets and memory-only FluidSynth rendering; no ports or audio outputs. */
public final class LiveMidiTest {
    static int checks;
    static void check(boolean yes,String why){checks++;if(!yes)throw new AssertionError(why);}
    static KahluaTable packet(int epoch,int seq,int profile,int at,String events,String state,boolean reset){
        var t=MidiTake.table();t.rawset("v",1.0);t.rawset("epoch",(double)epoch);t.rawset("seq",(double)seq);t.rawset("profile",(double)profile);t.rawset("at",(double)at);t.rawset("events",events);t.rawset("state",state);t.rawset("reset",reset);return t;
    }
    static double render(LiveMidiPlayer p,int frames,long now){
        double sum=0;for(int at=0;at<frames;at+=256){int n=Math.min(256,frames-at);float[] raw=p.render(n,now);for(int i=0;i<n*2;i++)sum+=raw[i]*raw[i];}return Math.sqrt(sum/(frames*2));
    }
    static int state(LiveMidiPlayer p,int owner,String key){Object v=p.state(owner).rawget(key);return v instanceof Number n?n.intValue():0;}
    public static void main(String[] args)throws Exception{
        Path common=Path.of(args[0]);long now=System.nanoTime();
        LiveMidiCapture capture=new LiveMidiCapture();
        capture.midi(0x90,0,60,80,now);check(capture.drain(1,now).rawget("epoch")==null,"Private monitoring cannot enter network queue");
        capture.clear();capture.enable(true,now);capture.midi(0x90,0,60,81,now+1_000_000);capture.midi(0x80,0,60,127,now+2_000_000);
        var first=capture.drain(1,now+3_000_000);var parsed=LivePacket.read(1,first);
        check(parsed.events().size()==2 && !parsed.reset() && parsed.state().isEmpty(),"First short note is retained even when released before network flush");
        check(parsed.events().get(0).b()==81 && parsed.events().get(1).status()==0x80,"Attack and release velocities remain distinct");
        check(capture.drain(1,now+10_000_000).rawget("epoch")==null,"Silent stream sends bounded heartbeats, not one message per frame");
        check(capture.drain(1,now+600_000_000).rawget("epoch")!=null,"Idle heartbeat keeps listener state alive");
        capture.midi(0xb0,0,64,127,now+601_000_000);capture.midi(0x90,0,60,90,now+602_000_000);capture.midi(0x80,0,60,0,now+603_000_000);
        var held=LivePacket.read(1,capture.drain(1,now+604_000_000));
        check(held.state().size()==3,"Snapshot contains sustain and released-but-ringing note");
        for(int i=0;i<200;i++)capture.midi(0xe0,0,i%128,64,now+605_000_000+i);
        var overflow=LivePacket.read(1,capture.drain(1,now+606_000_000));
        check(overflow.reset() && overflow.events().size()<=128,"Capture overflow recovers from bounded snapshot without delaying local MIDI");
        for(int n=0;n<128;n++)capture.midi(0x90,1,n,100,now+607_000_000+n);
        check(LivePacket.read(1,capture.drain(1,now+608_000_000)).state().stream().filter(e->(e.status()&0xf0)==0x90).count()<=48,"Pedal/held snapshot has bounded note capacity");
        for(String invalid:new String[]{"0,144,60,128;","0,240,60,80;","0,176,74,80;","0,144,60,80","-1,144,60,80;","2,144,60,80;","0,144,60,80;;"}){
            try{LivePacket.read(1,packet(1,1,1,0,invalid,"",false));throw new AssertionError("Invalid event accepted: "+invalid);}catch(IllegalArgumentException expected){checks++;}
        }
        try{LivePacket.read(1,packet(1,1,1,0,"","144,60,90;144,60,80;",false));throw new AssertionError("Duplicate snapshot note accepted");}catch(IllegalArgumentException expected){checks++;}
        try(LiveMidiPlayer p=new LiveMidiPlayer(common)){
            StringBuilder chord=new StringBuilder(),snapshot=new StringBuilder();
            for(int c=0;c<6;c++){chord.append("0,").append(144+c).append(",60,").append(75+c).append(';');snapshot.append(144+c).append(",60,").append(75+c).append(';');}
            var six=LivePacket.read(7,packet(1,1,1,0,chord.toString(),snapshot.toString(),false));
            check(p.accept(six,1,now),"Six-channel guitar enters listener synth");
            check(render(p,LiveMidiPlayer.BUFFER_FRAMES,now)==0,"Listener jitter buffer does not play notes early");
            double firstLevel=render(p,512,now);System.out.println("First remote guitar RMS="+firstLevel+" held="+state(p,7,"held")+" voices="+p.voices());
            check(firstLevel>.001 && state(p,7,"held")==6 && p.voices()>=6,"All six same-pitch strings reach actual sampled audio");
            check(!p.accept(six,1,now) && state(p,7,"attack")==6,"Duplicate packets never retrigger a chord");
            check(p.accept(LivePacket.read(7,packet(1,2,1,100,"100,128,60,0;","",false)),1,now),"Independent string release queued");
            render(p,6000,now);check(state(p,7,"held")==5,"One string note-off preserves the other five");
            // A gap discards old queued events and restores current state, including releases.
            p.accept(LivePacket.read(7,packet(1,4,1,200,"","145,64,80;",false)),1,now);
            render(p,LiveMidiPlayer.BUFFER_FRAMES+256,now);check(state(p,7,"held")==1 && state(p,7,"note")==64,"Lost packet recovers authoritative held state");
            check(!p.accept(LivePacket.read(7,packet(1,3,1,150,"150,144,80,127;","",false)),1,now),"Reordered packet cannot revive old notes");
            p.stop();
            for(int owner=0;owner<8;owner++)check(p.accept(LivePacket.read(owner,packet(2,1,8,0,"0,144,69,100;","144,69,100;",false)),1,now),"Separate performer accepted "+owner);
            check(!p.accept(LivePacket.read(9,packet(2,1,8,0,"","",false)),1,now),"Ninth performer cannot allocate unbounded native state");
            check(render(p,6000,now)>.001,"Eight performers mix audibly");
            check(p.voices()>=8,"Each performer has actual native voices, including MIDI channels above 16");
            p.stop(0);check(state(p,0,"held")==0 && state(p,1,"held")==1,"Stopping one performer preserves others");
            for(int owner=1;owner<8;owner++)p.gain(owner,0);
            render(p,4096,now);check(render(p,1024,now)<.0001,"Distance/listener mute silences remote mix");
            p.gain(1,1);check(render(p,4096,now)>.001,"Distance gain restores a sustained note");
            render(p,256,now+2_000_000_000);check(!p.active() && render(p,256,now+2_000_000_000)==0,"Disconnect/heartbeat timeout produces silence");
            p.accept(LivePacket.read(1,packet(3,25,8,1000,"999,144,70,100;","176,64,127;144,60,90;128,60,0;",true)),1,now);
            check(render(p,5000,now)>.001 && state(p,1,"held")==0,"Late listener reconstructs a pedal-held note without old physical gesture");
            p.accept(LivePacket.read(1,packet(3,26,8,1100,"1100,176,64,0;","",false)),1,now);
            render(p,VoiceEngine.RATE*5,now);check(p.voices()==0,"Pedal release reaches listener sound bank");
            p.stop();
            p.accept(LivePacket.read(1,packet(4,1,8,0,"0,144,60,90;","144,60,90;",false)),1,now);
            render(p,4000,now);
            p.accept(LivePacket.read(1,packet(4,2,8,20,"20,128,60,0;","",false)),1,now);
            render(p,VoiceEngine.RATE*29-4000,now);
            p.accept(LivePacket.read(1,packet(4,3,8,29000,"29000,144,69,90;","144,69,90;",false)),1,now);
            render(p,VoiceEngine.RATE*2,now);
            check(state(p,1,"held")==1 && render(p,1024,now)>.001,"A released old note cannot silence newer notes thirty seconds later");
            p.stop();
            for(int owner=0;owner<8;owner++)p.accept(LivePacket.read(owner,packet(5,1,1,0,chord.toString(),snapshot.toString(),false)),1,now);
            long start=System.nanoTime();render(p,VoiceEngine.RATE,now);double seconds=(System.nanoTime()-start)/1e9;
            check(seconds<1,"Remote eight-guitar render keeps up with real time");System.out.printf("Remote 48-key render: %.3fs per second of memory audio%n",seconds);
            check(p.voices()>=48,"Every string of eight simultaneous guitars has a native voice");
            p.stop();StringBuilder burst=new StringBuilder();for(int i=0;i<128;i++)burst.append("0,144,").append(36+i%48).append(",100;");
            for(int owner=0;owner<8;owner++)p.accept(LivePacket.read(owner,packet(6,1,1,0,burst.toString(),"",false)),1,now);
            check(render(p,8000,now)>.001 && p.voices()<=256,"Dense eight-player burst respects bounded native polyphony");
            p.stop();check(render(p,1024,now)==0,"Dense burst still permits immediate silence");
        }
        try(VoiceEngine e=new VoiceEngine()){
            e.open(common);e.configure(1,12,5,.3);e.arm(true);e.liveCapture(true);
            e.midi(0x90,0,40,80);e.midi(0x90,5,40,90);
            var frame=LivePacket.read(1,e.livePoll());
            check(frame.events().size()==1 && frame.events().get(0).status()==149 && frame.events().get(0).a()==52,"Broadcast mirrors accepted channel and transposes exactly once");
            e.midi(0x80,5,40,0);check(LivePacket.read(1,e.livePoll()).events().get(0).a()==52,"Transposed release matches broadcast note");
            e.arm(false);e.liveCapture(false);
            e.liveReceive(4,packet(1,1,8,0,"0,144,69,100;","144,69,100;",false),1);
            check(EngineTest.rms(EngineTest.render(e,8000))>50,"Listener hears live player with local performance disarmed and no MIDI device");
            e.panic();check(EngineTest.rms(EngineTest.render(e,4096))>50,"Routine local instrument reset does not kill remote listener audio");
            e.configure(1,0,-1,0);check(EngineTest.rms(EngineTest.render(e,1024))==0,"Existing listening volume also controls remote music");
            e.liveStopAll();check(e.liveState(4).rawget("attack")==null,"Explicit network panic clears listener state");
        }
        System.out.println("PASS: "+checks+" live-MIDI capture, malformed packet, native listener, guitar-channel, recovery and isolation checks; no hardware opened");
    }
}
