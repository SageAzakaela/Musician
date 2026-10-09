package azakaela.deadair;

import java.nio.file.Path;
import java.util.Arrays;

/** Synchronized MIDI, safety and world-noise state around the bundled Java SoundFont sampler. */
public final class VoiceEngine implements AutoCloseable {
    public static final int RATE = 48000, MAX_VOICES = 128, MAX_KEYS = 48;
    // Make the quiet GM bank usable at normal listening levels. Apply once, after mixing.
    static final double OUTPUT_GAIN = Math.pow(10,12.0/20);
    public static final String[] PROFILES = {"Piano", "Acoustic guitar", "Electric guitar", "Bass", "Banjo", "Flute", "Trumpet", "Saxophone", "Violin", "Drums", "Harmonica", "Whistle", "Tuning fork", "Kick drum", "Tom drum", "Snare drum"};
    private static final int[] PROGRAMS = {0,25,27,33,105,73,56,65,40,0,22,78,80,0,0,0};
    private final Note[] notes = new Note[MAX_KEYS];
    // Physical keys are independent of sampled voice lifetime and sustain-pedal tails.
    private final long[][] heldSince = new long[16][128];
    private final DrumActivity drumActivity=new DrumActivity();
    private int heldCount, attackNote=-1;
    private long motionReset, resetAttack;
    private final boolean[] sustain = new boolean[16];
    private final double[] volume = new double[16], expression = new double[16];
    private SoundFontSampler sampler;
    private float[] audition;
    private int auditionAt;
    private ScorePlayer score;
    private LiveMidiPlayer remote;
    private final LiveMidiCapture broadcast=new LiveMidiCapture();
    private int profile, transpose, channelFilter = -1, attacks, attackVelocity;
    private String error="";
    private double gain = 0.3, peak;
    private boolean armed;
    private long leaseUntil, attackSerial, frame, serial;

    public VoiceEngine() {
        for (int i=0; i<notes.length; i++) notes[i] = new Note();
        resetTracking();
    }
    public synchronized void open(Path common) {open(common,null);}
    public synchronized void open(Path common,SoundfontSetup.Resolved mapping) {
        close();
        sampler = new SoundFontSampler(common,16,128,mapping);
        try { selectPreset(); score=new ScorePlayer(common,mapping); remote=new LiveMidiPlayer(common,mapping); panic(); }
        catch (RuntimeException | Error e) { close(); throw e; }
    }
    public synchronized boolean ready() { return sampler != null; }
    public synchronized String error() { return error; }
    public synchronized String soundStatus() {
        return sampler == null ? "Open audio to load Gervill + GeneralUser GS." : sampler.version + " / "+sampler.summary;
    }
    public synchronized String inputRouteStatus(int lastChannel) {
        if(channelFilter>=0 && lastChannel>=0 && channelFilter!=lastChannel)
            return "Last channel "+(lastChannel+1)+" filtered out by channel "+(channelFilter+1)+". Set MIDI channel to 0 (all).";
        if(!armed)return "Performance: waiting for an equipped instrument / editor MIDI monitor.";
        if(gain==0)return "Listening volume is zero.";
        if(lastChannel>=0 && lastChannel<16 && (volume[lastChannel]==0 || expression[lastChannel]==0))
            return "Channel "+(lastChannel+1)+" muted by MIDI "+(volume[lastChannel]==0?"volume (CC7)":"expression (CC11)")+". F11 resets controllers.";
        return "Performance: ready / "+(channelFilter<0?"all MIDI channels":"channel "+(channelFilter+1));
    }
    public synchronized void configure(int profile, int transpose, int channelFilter, double gain) {
        int p = Math.max(0, Math.min(PROFILES.length-1, profile));
        int t = Math.max(-24, Math.min(24, transpose));
        int c = Math.max(-1, Math.min(15, channelFilter));
        boolean changed = p != this.profile;
        if (changed || t != this.transpose || c != this.channelFilter) panic();
        this.profile=p; this.transpose=t; this.channelFilter=c;
        this.gain=Double.isFinite(gain) ? Math.max(0, Math.min(1, gain)) : 0.3;
        if (changed && sampler != null) selectPreset();
    }
    static boolean drums(int profile) {return profile==9 || profile>=13;}
    static int bank(int profile) {return drums(profile)?128:profile==12?8:0;}
    static int program(int profile) {return PROGRAMS[profile];}
    private boolean drums() { return drums(profile); }
    private int renderedNote(int input){return switch(profile){case 13->36;case 14->43;case 15->38;default->input+(profile==9?0:transpose);};}
    private void selectPreset() { sampler.profile(profile); }
    public synchronized void arm(boolean enabled) {
        panic(); if(enabled) error=""; armed=enabled && sampler!=null; leaseUntil=System.nanoTime()+750_000_000L;
    }
    public synchronized void heartbeat() { if (armed) leaseUntil=System.nanoTime()+750_000_000L; }
    synchronized void scoreLoad(se.krka.kahlua.vm.KahluaTable parts,int bpm,int ticks,boolean click) {
        if(score==null)throw new IllegalStateException("Open audio first");score.load(parts,bpm,ticks,click);
    }
    synchronized void scoreStart(double delayMs) {if(score!=null){long now=System.nanoTime();score.start(now+(long)(Math.max(-600000,Math.min(30000,delayMs))*1_000_000),now);}}
    synchronized void scoreStop(){if(score!=null)score.stop();}
    synchronized void scoreHeartbeat(){if(score!=null)score.heartbeat(System.nanoTime());}
    synchronized boolean scoreActive(){return score!=null&&score.active();}
    synchronized double scoreTick(){return score==null?0:score.tick();}
    synchronized void scoreClick(boolean value){if(score!=null)score.metronome(value);}
    synchronized void scoreGain(int part,double gain){if(score!=null)score.gain(part,gain);}
    synchronized se.krka.kahlua.vm.KahluaTable scoreState(int part){return score==null?MidiTake.table():score.state(part);}
    synchronized void liveCapture(boolean enabled){broadcast.enable(enabled,System.nanoTime());}
    synchronized se.krka.kahlua.vm.KahluaTable livePoll(){return broadcast.drain(profile,System.nanoTime());}
    synchronized boolean liveReceive(int owner,se.krka.kahlua.vm.KahluaTable packet,double gain){return remote!=null && remote.accept(LivePacket.read(owner,packet),gain,System.nanoTime());}
    synchronized void liveGain(int owner,double value){if(remote!=null)remote.gain(owner,value);}
    synchronized void liveStop(int owner){if(remote!=null)remote.stop(owner);}
    synchronized void liveStopAll(){if(remote!=null)remote.stop();}
    synchronized se.krka.kahlua.vm.KahluaTable liveState(int owner){return remote==null?MidiTake.table():remote.state(owner);}
    public synchronized long attackSerial() { return attackSerial; }
    public synchronized int attackVelocity() { return attackVelocity; }
    public record MotionState(long attack,int velocity,int note,int held,long reset,long resetAttack) {}
    public synchronized MotionState motionState() {
        return new MotionState(attackSerial,attackVelocity,attackNote,heldCount,motionReset,resetAttack);
    }
    public synchronized se.krka.kahlua.vm.KahluaTable drumState(){return drums()?drumActivity.table():MidiTake.table();}
    public synchronized boolean isArmed() { return armed; }
    public synchronized void expire(long now) { if (armed && now > leaseUntil) arm(false); }
    public synchronized void preview(float[] samples){audition=samples;auditionAt=0;}
    public synchronized void panic() {
        audition=null;auditionAt=0;
        broadcast.clear();
        resetTracking(); attacks=0; peak=0;
        if (sampler != null) {
            sampler.render(SoundFontSampler.BLOCK); // Commit queued events before sending all-sounds-off.
            for (int c=0; c<16; c++) { sampler.silence(c); sampler.resetChannel(c); }
            sampler.render(SoundFontSampler.BLOCK); // Drain pre-panic samples from the native internal buffer.
        }
    }
    private void resetTracking() {
        drumActivity.reset();
        for (Note n:notes) n.active=false;
        for (long[] channel:heldSince) Arrays.fill(channel,0);
        heldCount=0; motionReset++; resetAttack=attackSerial;
        Arrays.fill(sustain,false); Arrays.fill(volume,1); Arrays.fill(expression,1);
    }
    private void releaseHeld(int channel,int key) {
        if(heldSince[channel][key]!=0) { heldSince[channel][key]=0; heldCount--; }
    }
    private void releaseHeldChannel(int channel) {
        for(int key=0;key<128;key++) releaseHeld(channel,key);
    }
    public synchronized int activeVoices() { return armed && sampler!=null ? sampler.voices() : 0; }
    public synchronized int consumeActivity() {
        if (!armed) { attacks=0; return 0; }
        int result=attacks; attacks=0;
        if (peak>0.001 && sampler.voices()>0)
            for (Note n:notes) if (n.active) result=Math.max(result,(int)(n.velocity*volume[n.channel]*expression[n.channel]));
        return result;
    }
    public synchronized void midi(int command, int channel, int d1, int d2) {
        expire(System.nanoTime());
        if (!armed || channel<0 || channel>15 || d1<0 || d1>127 || d2<0 || d2>127) return;
        if (channelFilter>=0 && channel!=channelFilter) return;
        if (command!=0x90 && command!=0x80 && command!=0xE0 && command!=0xB0) return;
        // Ignored controllers enqueue nothing. Counting them here can silence a chord
        // from a multi-channel controller even though the native queue is almost empty.
        if (command==0xB0 && !supportedController(d1)) return;
        // The Java sampler applies messages synchronously; it has no native event
        // queue to overflow. Dense controller traffic must not disarm performance.
        if (command==0x90 && d2>0) {
            int key=renderedNote(d1);
            if (key<0 || key>127) return;
            Note slot=null, oldest=notes[0];
            for (Note n:notes) {
                if (n.active && n.channel==channel && (n.key==d1 || (drums() && n.rendered==key))) { release(n); n.active=false; }
                if (!n.active && slot==null) slot=n;
                if (n.serial<oldest.serial) oldest=n;
            }
            if (slot==null) { slot=oldest; release(slot); }
            slot.start(channel,d1,key,d2,++serial,frame);
            if (!sampler.noteOn(channel,key,d2)) { slot.active=false; return; }
            broadcast.midi(0x90,channel,key,d2,System.nanoTime());
            if(heldSince[channel][d1]==0) heldCount++;
            heldSince[channel][d1]=frame+1;
            attackSerial++; attackVelocity=d2; attackNote=key;
            if(drums())drumActivity.hit(key,d2);
            attacks=Math.max(attacks,(int)(d2*volume[channel]*expression[channel]));
        } else if (command==0x80 || command==0x90) {
            releaseHeld(channel,d1);
            int key=renderedNote(d1);
            if(key>=0 && key<=127)broadcast.midi(0x80,channel,key,0,System.nanoTime());
            for (Note n:notes) if (n.active && n.channel==channel && n.key==d1 && n.held) {
                n.held=false;
                // Drum strikes are one-shots; key-up must not cut a second strike from another key.
                if (!drums()) sampler.noteOff(channel,n.rendered);
                if (!drums() && !sustain[channel]) n.released=frame;
            }
        } else if (command==0xE0) {sampler.bend(channel,d1 | (d2<<7));broadcast.midi(command,channel,d1,d2,System.nanoTime());}
        else if (command==0xB0) {controller(channel,d1,d2);broadcast.midi(command,channel,d1,drums()&&d1==64?0:d2,System.nanoTime());}
        // Ignore bank/program/SysEx messages: the game instrument owns its sound.
    }
    static boolean supportedController(int cc) {
        return cc==1 || cc==7 || cc==11 || cc==64 || cc==120 || cc==121 || cc==123;
    }
    private void controller(int c,int cc,int value) {
        if (cc==64) {
            sustain[c]=!drums() && value>=64;
            sampler.cc(c,cc,drums()?0:value);
            if (!sustain[c]) for (Note n:notes) if (n.channel==c && !n.held && n.released<0) n.released=frame;
        } else if (cc==7 || cc==11) {
            if (cc==7) volume[c]=value/127.0; else expression[c]=value/127.0;
            sampler.cc(c,cc,value);
        } else if (cc==120) {
            sampler.silence(c);
            releaseHeldChannel(c);
            for (Note n:notes) if (n.channel==c) n.active=false;
        } else if (cc==123) {
            sampler.cc(c,cc,value);
            releaseHeldChannel(c);
            for (Note n:notes) if (n.channel==c) { n.held=false; if (!sustain[c]) n.released=frame; }
        } else if (cc==121) {
            sampler.resetChannel(c); sustain[c]=false; volume[c]=1; expression[c]=1;
            for (Note n:notes) if (n.channel==c && !n.held) n.released=frame;
        } else if (cc==1) sampler.cc(c,cc,value);
    }
    private void release(Note n) { if (n.active && sampler!=null) {sampler.noteOff(n.channel,n.rendered);broadcast.midi(0x80,n.channel,n.rendered,0,System.nanoTime());} }
    /** Interleaved signed little-endian stereo PCM; limit float output before integer conversion. */
    public synchronized void render(byte[] out, int frames) {
        if (frames<0 || frames>out.length/4) throw new IllegalArgumentException("PCM buffer too small");
        expire(System.nanoTime());
        if (sampler==null || (!armed && !scoreActive() && audition==null && (remote==null || !remote.active()))) { Arrays.fill(out,0,frames*4,(byte)0); peak=0; return; }
        peak=0;
        for (int start=0; start<frames; start+=SoundFontSampler.BLOCK) {
            int count=Math.min(SoundFontSampler.BLOCK,frames-start);
            float[] samples=armed?sampler.render(count):null;
            float[] music=score.render(count,System.nanoTime());
            float[] nearby=remote.render(count,System.nanoTime());
            for (int i=0; i<count*2; i++) {
                float raw=(samples==null?0:samples[i])+music[i]+nearby[i];
                float activityRaw=Float.isFinite(raw)?raw:0;
                if(audition!=null){raw+=audition[auditionAt++];if(auditionAt>=audition.length)audition=null;}
                if (!Float.isFinite(raw)) raw=0;
                peak=Math.max(peak,Math.abs(activityRaw));
                int value=(int)(Math.tanh(raw*gain*OUTPUT_GAIN)*30000);
                int at=start*4+i*2; out[at]=(byte)value; out[at+1]=(byte)(value>>8);
            }
            frame+=count;
        }
        for (Note n:notes) if (n.active) {
            if (drums() && !n.gated && frame-n.started>RATE*2L) { release(n); n.gated=true; n.released=frame; }
            if (frame-n.started>RATE*30L) {
                // A lost note-off cannot leave a voice held forever by the sustain pedal.
                sampler.silence(n.channel);
                broadcast.midi(0xb0,n.channel,120,0,System.nanoTime());
                releaseHeldChannel(n.channel);
                for (Note other:notes) if (other.channel==n.channel) other.active=false;
            }
            else if (n.released>=0 && frame-n.released>RATE*5L) n.active=false;
        }
        if (sampler.voices()==0) for (Note n:notes) n.active=false;
        // Natural decay may retire all sample voices before a lost physical key-up.
        for(int c=0;c<16;c++) for(int k=0;k<128;k++)
            if(heldSince[c][k]!=0 && frame+1-heldSince[c][k]>RATE*30L) {releaseHeld(c,k);broadcast.midi(0xb0,c,120,0,System.nanoTime());}
    }
    /** Built off the audio thread, committed under one short engine lock. */
    static final class Prepared implements AutoCloseable {
        SoundFontSampler sampler;ScorePlayer score;LiveMidiPlayer remote;
        Prepared(Path common,SoundfontSetup.Resolved mapping){try{sampler=new SoundFontSampler(common,16,128,mapping);score=new ScorePlayer(common,mapping);remote=new LiveMidiPlayer(common,mapping);}catch(RuntimeException|Error e){close();throw e;}}
        public void close(){if(sampler!=null)sampler.close();if(score!=null)score.close();if(remote!=null)remote.close();}
    }
    synchronized void install(Prepared next){close();sampler=next.sampler;score=next.score;remote=next.remote;next.sampler=null;next.score=null;next.remote=null;selectPreset();panic();}
    @Override public synchronized void close() {
        audition=null;auditionAt=0;broadcast.enable(false,System.nanoTime());broadcast.clear();
        armed=false; resetTracking(); attacks=0; peak=0; error="";
        if (sampler!=null) { sampler.close(); sampler=null; }
        if (score!=null) { score.close(); score=null; }
        if (remote!=null) { remote.close(); remote=null; }
    }
    private static final class Note {
        boolean active,held,gated;
        int channel,key,rendered,velocity;
        long serial,started,released;
        void start(int c,int k,int r,int v,long s,long f) {
            channel=c; key=k; rendered=r; velocity=v; serial=s; started=f;
            released=-1; active=true; held=true; gated=false;
        }
    }
}
