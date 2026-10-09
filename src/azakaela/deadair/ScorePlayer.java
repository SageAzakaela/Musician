package azakaela.deadair;

import java.nio.file.Path;
import java.util.*;
import se.krka.kahlua.vm.KahluaTable;

/** A shared audio clock for up to eight parts. Called only while holding VoiceEngine's lock. */
final class ScorePlayer implements AutoCloseable {
    static final int PPQ=96,MAX_PARTS=8,MAX_NOTES=16384,MAX_TICKS=262144*4*PPQ;
    private final SoundFontSampler synth;
    private final float[] pcm=new float[SoundFontSampler.BLOCK*2];
    private final long[] attacks=new long[MAX_PARTS];
    private final int[] held=new int[MAX_PARTS],velocities=new int[MAX_PARTS];
    private final int[][] keys=new int[MAX_PARTS][128];
    private final int[] gains=new int[MAX_PARTS];
    private final DrumActivity[] drumActivity=new DrumActivity[MAX_PARTS];
    private final int[] partProfiles=new int[MAX_PARTS],lastNotes=new int[MAX_PARTS];
    private Event[] events=new Event[0];
    private long cursor,total,startNanos,leaseUntil,reset;
    private double framesPerTick,beatFrames;
    private int next,count;
    private boolean active,click;
    record Event(long frame,int part,int note,int velocity) {}
    ScorePlayer(Path common){this(common,null);}
    ScorePlayer(Path common,SoundfontSetup.Resolved mapping){synth=new SoundFontSampler(common,16,128,mapping);for(int i=0;i<MAX_PARTS;i++)drumActivity[i]=new DrumActivity();stop();}
    static int number(KahluaTable t,String key,int min,int max) {
        Object v=t.rawget(key);
        if(!(v instanceof Number n) || !Double.isFinite(n.doubleValue()) || n.doubleValue()!=Math.rint(n.doubleValue()) || n.doubleValue()<min || n.doubleValue()>max)
            throw new IllegalArgumentException("Invalid score "+key);
        return n.intValue();
    }
    void load(KahluaTable parts,int bpm,int ticks,boolean metronome) {
        if(bpm<30||bpm>300||(ticks!=0&&ticks<96)||ticks>MAX_TICKS||parts==null||parts.len()<1||parts.len()>MAX_PARTS)throw new IllegalArgumentException("Invalid score length or tempo");
        boolean openEnded=ticks==0;if(openEnded)ticks=MAX_TICKS;
        List<Event> result=new ArrayList<>();int[] profiles=new int[parts.len()];
        double f=VoiceEngine.RATE*60.0/(bpm*PPQ);
        for(int c=0;c<parts.len();c++) {
            if(!(parts.rawget((double)c+1) instanceof KahluaTable part))throw new IllegalArgumentException("Invalid part");
            int profile=number(part,"profile",0,15);profiles[c]=profile;
            if(!(part.rawget("notes") instanceof KahluaTable notes)||notes.len()>MAX_NOTES)throw new IllegalArgumentException("Too many notes");
            for(int i=1;i<=notes.len();i++) {
                if(!(notes.rawget((double)i) instanceof KahluaTable n))throw new IllegalArgumentException("Invalid note");
                int pitch=number(n,"n",0,127),time=number(n,"t",0,ticks-1),duration=number(n,"d",1,ticks-time),velocity=number(n,"v",1,127);
                pitch=switch(profile){case 13->36;case 14->43;case 15->38;default->pitch;};
                result.add(new Event(Math.round(time*f),c,pitch,velocity));result.add(new Event(Math.round((time+duration)*f),c,pitch,0));
            }
        }
        result.sort(Comparator.comparingLong(Event::frame).thenComparingInt(Event::velocity));
        long last=-1;int burst=0;
        for(Event e:result){burst=e.frame==last?burst+1:1;last=e.frame;if(burst>64)throw new IllegalArgumentException("Too many simultaneous note events; simplify the chord or split its timing");}
        stop();count=parts.len();System.arraycopy(profiles,0,partProfiles,0,count);framesPerTick=f;beatFrames=f*PPQ;total=openEnded?Long.MAX_VALUE/2:Math.round(ticks*f);click=metronome;
        for(int c=0;c<count;c++)synth.profile(c,profiles[c]);
        events=result.toArray(Event[]::new);cursor=0;next=0;
    }
    void start(long when,long now) {
        silence();next=0;cursor=Math.round((now-when)*VoiceEngine.RATE/1_000_000_000.0);startNanos=when;active=true;heartbeat(now);
        // A late listener joins the existing timeline; old completed notes never replay.
        while(next<events.length && events[next].frame<cursor) {
            Event e=events[next++];
            if(e.velocity>0){keys[e.part][e.note]++;velocities[e.part]=e.velocity;}
            else if(keys[e.part][e.note]>0)keys[e.part][e.note]--;
        }
        for(int c=0;c<count;c++)for(int k=0;k<128;k++)if(keys[c][k]>0){held[c]++;attacks[c]++;synth.noteOn(c,k,velocities[c]);}
        if(cursor>=total+VoiceEngine.RATE)stop();
    }
    void heartbeat(long now){leaseUntil=now+1_500_000_000L;}
    boolean active(){return active;}
    double tick(){return framesPerTick>0?Math.max(0,cursor/framesPerTick):0;}
    long startNanos(){return startNanos;}
    void metronome(boolean value){click=value;}
    void gain(int part,double value){if(part>=0&&part<count){int v=(int)(127*Math.max(0,Math.min(1,Double.isFinite(value)?value:0)));if(gains[part]!=v){synth.cc(part,7,v);gains[part]=v;}}}
    KahluaTable state(int part) {
        KahluaTable t=MidiTake.table();boolean valid=part>=0&&part<count;
        t.rawset("attack",valid?(double)attacks[part]:0.0);t.rawset("velocity",valid?(double)velocities[part]:0.0);
        t.rawset("note",valid?(double)lastNotes[part]:-1.0);t.rawset("drums",valid&&VoiceEngine.drums(partProfiles[part])?drumActivity[part].table():MidiTake.table());
        t.rawset("held",valid?(double)held[part]:0.0);t.rawset("reset",(double)reset);t.rawset("resetAttack",0.0);return t;
    }
    private void apply(Event e) {
        int c=e.part,k=e.note;
        if(e.velocity>0){if(keys[c][k]++==0)held[c]++;synth.noteOn(c,k,e.velocity);attacks[c]++;velocities[c]=e.velocity;lastNotes[c]=k;if(VoiceEngine.drums(partProfiles[c]))drumActivity[c].hit(k,e.velocity);}
        else if(keys[c][k]>0 && --keys[c][k]==0){held[c]--;synth.noteOff(c,k);}
    }
    float[] render(int frames,long now) {
        Arrays.fill(pcm,0,frames*2,0);
        if(!active)return pcm;
        if(now>leaseUntil){stop();return pcm;}
        int at=0;
        while(at<frames) {
            while(next<events.length && events[next].frame<=cursor)apply(events[next++]);
            int n=frames-at;
            if(cursor<0)n=(int)Math.min(n,-cursor);
            else {
                if(next<events.length)n=(int)Math.min(n,Math.max(1,events[next].frame-cursor));
                var raw=synth.render(n);
                for(int i=0;i<n*2;i++)pcm[at*2+i]=raw[i];
            }
            if(click && cursor<total)for(int i=0;i<n;i++) {
                double frame=cursor+i;double b=Math.floor(frame/beatFrames),phase=frame-b*beatFrames;
                if(phase<VoiceEngine.RATE*.025) {
                    float v=(float)(.18*(1-phase/(VoiceEngine.RATE*.025))*Math.sin(phase*2*Math.PI*(Math.floorMod((long)b,4)==0?1500:1000)/VoiceEngine.RATE));
                    pcm[(at+i)*2]+=v;pcm[(at+i)*2+1]+=v;
                }
            }
            cursor+=n;at+=n;
        }
        if(cursor>=total+VoiceEngine.RATE)stop();
        return pcm;
    }
    private void silence() {
        for(int c=0;c<16;c++){synth.silence(c);synth.resetChannel(c);}
        // Retire release voices and discard buffered PCM before a new score/count-in.
        synth.render(SoundFontSampler.BLOCK);synth.render(SoundFontSampler.BLOCK);
        for(int[] k:keys)Arrays.fill(k,0);
        Arrays.fill(held,0);Arrays.fill(attacks,0);Arrays.fill(velocities,0);Arrays.fill(gains,127);reset++;
        Arrays.fill(lastNotes,-1);for(DrumActivity activity:drumActivity)activity.reset();
    }
    void stop(){active=false;silence();}
    @Override public void close(){synth.close();}
}
