package azakaela.deadair;

import java.nio.file.Path;
import java.util.*;
import se.krka.kahlua.vm.KahluaTable;

/** Listener-only sampler and short jitter buffer. Never delays or feeds back the local MIDI path. */
final class LiveMidiPlayer implements AutoCloseable {
    static final int PLAYERS=8,BUFFER_FRAMES=VoiceEngine.RATE*80/1000;
    private final SoundFontSampler synth;
    private final Slot[] slots=new Slot[PLAYERS];
    private final float[] pcm=new float[SoundFontSampler.BLOCK*2];
    private long cursor,order,lastEventFrame;
    private int pendingEvents;
    private record Scheduled(long frame,long order,LivePacket.Event event){}
    private static final class Slot {
        final int index;
        int owner=-1,epoch,sequence,profile,lastAt,held,velocity,lastNote=-1;
        long base,lease,attack,reset,resetAttack;
        double gain=1;
        final int[] volume=new int[16],appliedVolume=new int[16];
        final boolean[] sustain=new boolean[16];
        final boolean[][] keys=new boolean[16][128];
        final long[][] since=new long[16][128];
        final DrumActivity drums=new DrumActivity();
        final PriorityQueue<Scheduled> queue=new PriorityQueue<>(Comparator.comparingLong(Scheduled::frame).thenComparingLong(Scheduled::order));
        Slot(int index){this.index=index;Arrays.fill(volume,127);Arrays.fill(appliedVolume,-1);}
    }
    LiveMidiPlayer(Path common){this(common,null);}
    LiveMidiPlayer(Path common,SoundfontSetup.Resolved mapping){synth=new SoundFontSampler(common,PLAYERS*16,256,mapping);for(int i=0;i<PLAYERS;i++)slots[i]=new Slot(i);}
    private Slot find(int owner){for(Slot s:slots)if(s.owner==owner)return s;return null;}
    boolean active(){for(Slot s:slots)if(s.owner>=0)return true;return false;}
    private void clear(Slot s,boolean retire){
        s.queue.clear();s.held=0;s.velocity=0;s.lastNote=-1;s.reset++;s.resetAttack=s.attack;s.drums.reset();
        for(int c=0;c<16;c++){
            synth.silence(s.index*16+c);Arrays.fill(s.keys[c],false);Arrays.fill(s.since[c],0);
            s.volume[c]=127;s.appliedVolume[c]=-1;s.sustain[c]=false;
        }
        if(retire)s.owner=-1;
    }
    void stop(int owner){Slot s=find(owner);if(s!=null)clear(s,true);}
    void stop(){for(Slot s:slots)if(s.owner>=0)clear(s,true);}
    void gain(int owner,double gain){Slot s=find(owner);if(s!=null)s.gain=Double.isFinite(gain)?Math.max(0,Math.min(1,gain)):0;}
    private void volume(Slot s,int c){int value=(int)Math.round(s.volume[c]*s.gain);if(value!=s.appliedVolume[c]){synth.cc(s.index*16+c,7,value);s.appliedVolume[c]=value;}}
    boolean accept(LivePacket p,double gain,long now){
        Slot s=find(p.owner());boolean fresh=s==null;
        if(s==null){for(Slot candidate:slots)if(candidate.owner<0){s=candidate;break;}if(s==null)return false;}
        if(!fresh && (p.epoch()<s.epoch || (p.epoch()==s.epoch && p.sequence()<=s.sequence)))return false;
        boolean newEpoch=fresh || p.epoch()!=s.epoch;
        boolean recover=p.reset() || (!newEpoch && (p.sequence()!=s.sequence+1 || p.at()<s.lastAt || p.profile()!=s.profile));
        long target=newEpoch?cursor+BUFFER_FRAMES:s.base+p.at()*48L;
        if(!newEpoch && (target<cursor-VoiceEngine.RATE/4 || target>cursor+VoiceEngine.RATE/2))recover=true;
        if(newEpoch || recover){
            clear(s,false);s.owner=p.owner();s.profile=p.profile();s.gain=Math.max(0,Math.min(1,Double.isFinite(gain)?gain:0));
            for(int c=0;c<16;c++){int ch=s.index*16+c;synth.resetChannel(ch);synth.profile(ch,s.profile);volume(s,c);}
            s.base=cursor+BUFFER_FRAMES-p.at()*48L;
        }
        s.epoch=p.epoch();s.sequence=p.sequence();s.lastAt=p.at();s.lease=now+1_500_000_000L;gain(p.owner(),gain);
        // A new listener receives a snapshot instead of replaying old, completed notes.
        List<LivePacket.Event> events=(recover || (newEpoch && p.sequence()>1))?p.state():p.events();
        if(s.queue.size()+events.size()>512){clear(s,true);return false;}
        for(LivePacket.Event e:events)s.queue.add(new Scheduled(Math.max(cursor,s.base+e.time()*48L),++order,e));
        return true;
    }
    private void keyOff(Slot s,int c,int n){if(s.keys[c][n]){s.keys[c][n]=false;s.held--;}}
    private void released(Slot s,int c){for(int n=0;n<128;n++)if(!s.keys[c][n])s.since[c][n]=0;}
    private void apply(Slot s,LivePacket.Event e){
        int cmd=e.status()&0xf0,c=e.status()&15,ch=s.index*16+c,n=e.a(),v=e.b();
        if(cmd==0x90 && v>0){
            synth.noteOn(ch,n,v);if(!s.keys[c][n])s.held++;s.keys[c][n]=true;s.since[c][n]=cursor+1;
            s.attack++;s.velocity=v;s.lastNote=n;if(VoiceEngine.drums(s.profile))s.drums.hit(n,v);
        }else if(cmd==0x80 || cmd==0x90){keyOff(s,c,n);if(!VoiceEngine.drums(s.profile)){synth.noteOff(ch,n);if(!s.sustain[c])s.since[c][n]=0;}}
        else if(cmd==0xe0)synth.bend(ch,n|(v<<7));
        else if(cmd==0xb0){
            if(n==7){s.volume[c]=v;volume(s,c);}
            else if(n==121){synth.resetChannel(ch);s.volume[c]=127;s.appliedVolume[c]=-1;s.sustain[c]=false;released(s,c);volume(s,c);}
            else if(n==120){synth.silence(ch);for(int k=0;k<128;k++){keyOff(s,c,k);s.since[c][k]=0;}}
            else {
                synth.cc(ch,n,n==64&&VoiceEngine.drums(s.profile)?0:v);
                if(n==64){s.sustain[c]=!VoiceEngine.drums(s.profile)&&v>=64;if(!s.sustain[c]&&!VoiceEngine.drums(s.profile))released(s,c);}
                if(n==123){for(int k=0;k<128;k++)keyOff(s,c,k);if(!s.sustain[c]&&!VoiceEngine.drums(s.profile))released(s,c);}
            }
        }
    }
    float[] render(int frames,long now){
        Arrays.fill(pcm,0,frames*2,0);
        for(Slot s:slots)if(s.owner>=0 && now>s.lease)clear(s,true);
        if(!active()){cursor+=frames;return pcm;}
        for(Slot s:slots)if(s.owner>=0)for(int c=0;c<16;c++)volume(s,c);
        int at=0;
        while(at<frames){
            // Spread dense controller bursts across complete synthesis control blocks.
            // This bounds the work performed before the next audio render.
            if(cursor-lastEventFrame>=64)pendingEvents=0;
            for(Slot s:slots)while(s.owner>=0 && !s.queue.isEmpty() && s.queue.peek().frame<=cursor && pendingEvents<48){
                LivePacket.Event e=s.queue.remove().event;apply(s,e);
                // Controllers/bends can update every voice on a channel; reset invokes several CCs.
                pendingEvents+=((e.status()&0xf0)==0xb0 || (e.status()&0xf0)==0xe0)?8:1;lastEventFrame=cursor;
            }
            int n=frames-at;
            if(pendingEvents>=48)n=(int)Math.min(n,64-(cursor-lastEventFrame));
            else for(Slot s:slots)if(s.owner>=0 && !s.queue.isEmpty())n=(int)Math.min(n,Math.max(1,s.queue.peek().frame-cursor));
            var raw=synth.render(n);for(int i=0;i<n*2;i++)pcm[at*2+i]=raw[i];
            cursor+=n;at+=n;
        }
        for(Slot s:slots)if(s.owner>=0)for(int c=0;c<16;c++)for(int k=0;k<128;k++)if(s.since[c][k]>0){
            long age=cursor+1-s.since[c][k];
            if(age>VoiceEngine.RATE*30L){synth.silence(s.index*16+c);for(int n=0;n<128;n++){keyOff(s,c,n);s.since[c][n]=0;}break;}
            if(VoiceEngine.drums(s.profile) && age>VoiceEngine.RATE*2L){synth.noteOff(s.index*16+c,k);keyOff(s,c,k);s.since[c][k]=0;}
        }
        return pcm;
    }
    KahluaTable state(int owner){
        var t=MidiTake.table();Slot s=find(owner);if(s==null)return t;
        t.rawset("attack",(double)s.attack);t.rawset("velocity",(double)s.velocity);t.rawset("note",(double)s.lastNote);t.rawset("held",(double)s.held);
        t.rawset("reset",(double)s.reset);t.rawset("resetAttack",(double)s.resetAttack);t.rawset("drums",s.drums.table());return t;
    }
    int voices(){return synth.voices();}
    @Override public void close(){synth.close();}
}
