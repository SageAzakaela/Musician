package azakaela.deadair;

import java.util.*;
import se.krka.kahlua.vm.KahluaTable;
import se.krka.kahlua.j2se.J2SEPlatform;

/** MIDI-thread timestamps, independent of UI frame rate. One bounded take, no device ownership. */
final class MidiTake {
    private final long[][] down=new long[16][128];
    private final int[][] velocity=new int[16][128];
    private final boolean[][] released=new boolean[16][128];
    private final boolean[] pedal=new boolean[16];
    private final List<int[]> notes=new ArrayList<>();
    private long start,end;
    private int bpm,length,channel,capacity=ScorePlayer.MAX_NOTES;
    private boolean active,full;
    synchronized void begin(int bpm,int ticks,int channel,long start) {
        begin(bpm,ticks,channel,start,ScorePlayer.MAX_NOTES);
    }
    synchronized void begin(int bpm,int ticks,int channel,long start,int capacity) {
        cancel();this.capacity=Math.max(1,Math.min(ScorePlayer.MAX_NOTES,capacity));this.bpm=bpm;this.length=ticks==0?ScorePlayer.MAX_TICKS:ticks;this.channel=channel;this.start=start;
        end=ticks==0?Long.MAX_VALUE:start+Math.round(ticks*60_000_000_000.0/(bpm*96));active=true;
    }
    synchronized void cancel() {
        active=false;full=false;notes.clear();Arrays.fill(pedal,false);
        for(long[] a:down)Arrays.fill(a,0);
        for(boolean[] a:released)Arrays.fill(a,false);
    }
    synchronized boolean active() { return active; }
    synchronized boolean full() { return full; }
    synchronized void midi(int command,int c,int n,int v,long now) {
        if(!active || now<start || now>end || c<0 || c>15 || n<0 || n>127 || v<0 || v>127 || (channel>=0&&channel!=c))return;
        if(command==0x90 && v>0) {
            finish(c,n,now);down[c][n]=now;velocity[c][n]=v;released[c][n]=false;
        } else if(command==0x80 || command==0x90) {
            if(pedal[c])released[c][n]=true;else finish(c,n,now);
        } else if(command==0xB0 && n==64) {
            pedal[c]=v>=64;
            if(!pedal[c])for(int k=0;k<128;k++)if(released[c][k])finish(c,k,now);
        } else if(command==0xB0 && (n==120 || n==123 || n==121)) {
            for(int k=0;k<128;k++)finish(c,k,now);pedal[c]=false;
        }
    }
    private void finish(int c,int n,long now) {
        if(down[c][n]==0)return;
        int t=(int)Math.round((down[c][n]-start)*bpm*96/60_000_000_000.0);
        int stop=(int)Math.round((Math.min(now,end)-start)*bpm*96/60_000_000_000.0);
        if(t<length && notes.size()<capacity)notes.add(new int[]{n,Math.max(0,t),Math.max(1,Math.min(length-t,stop-t)),velocity[c][n]});
        else full=true;
        if(notes.size()>=capacity)full=true;
        down[c][n]=0;released[c][n]=false;
    }
    synchronized int count(){return notes.size();}
    synchronized KahluaTable snapshot(int from) {
        KahluaTable out=table();int i=1;
        for(int at=Math.max(0,from);at<notes.size();at++){int[] n=notes.get(at);KahluaTable t=table();t.rawset("n",(double)n[0]);t.rawset("t",(double)n[1]);t.rawset("d",(double)n[2]);t.rawset("v",(double)n[3]);out.rawset((double)i++,t);}
        return out;
    }
    synchronized KahluaTable stop(long now) {
        for(int c=0;c<16;c++)for(int n=0;n<128;n++)finish(c,n,now);
        active=false;notes.sort(Comparator.comparingInt(n->n[1]));
        KahluaTable out=table();int i=1;
        for(int[] n:notes){KahluaTable t=table();t.rawset("n",(double)n[0]);t.rawset("t",(double)n[1]);t.rawset("d",(double)n[2]);t.rawset("v",(double)n[3]);out.rawset((double)i++,t);}
        return out;
    }
    static KahluaTable table(){return J2SEPlatform.getInstance().newTable();}
}
