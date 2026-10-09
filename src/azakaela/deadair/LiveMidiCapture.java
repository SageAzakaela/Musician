package azakaela.deadair;

import java.util.*;
import se.krka.kahlua.vm.KahluaTable;

/** Bounded copy of accepted performance MIDI. Drained on the game thread, never sends network traffic. */
final class LiveMidiCapture {
    static final int MAX_EVENTS=128;
    private final int[][] velocity=new int[16][128];
    private final boolean[][] held=new boolean[16][128];
    private final int[] volume=new int[16],expression=new int[16],pedal=new int[16],bend=new int[16],modulation=new int[16];
    private final List<int[]> events=new ArrayList<>();
    private boolean enabled,reset;
    private long origin=System.nanoTime(),lastDrain,epoch=1,sequence;
    LiveMidiCapture(){clear();}
    void enable(boolean value,long now){if(value!=enabled){enabled=value;restart(now,!snapshot().isEmpty());}}
    private void restart(long now,boolean recover){epoch++;sequence=0;origin=now;lastDrain=0;events.clear();reset=recover;}
    void clear(){
        for(int[] row:velocity)Arrays.fill(row,0);for(boolean[] row:held)Arrays.fill(row,false);
        Arrays.fill(volume,127);Arrays.fill(expression,127);Arrays.fill(pedal,0);Arrays.fill(bend,8192);Arrays.fill(modulation,0);
        restart(System.nanoTime(),false);
    }
    private void released(int c){for(int n=0;n<128;n++)if(!held[c][n])velocity[c][n]=0;}
    void midi(int command,int c,int a,int b,long now){
        if(command==0x90 && b>0){velocity[c][a]=b;held[c][a]=true;}
        else if(command==0x80 || command==0x90){held[c][a]=false;if(pedal[c]<64)velocity[c][a]=0;}
        else if(command==0xe0)bend[c]=a|(b<<7);
        else if(command==0xb0){
            switch(a){
                case 7 -> volume[c]=b;
                case 11 -> expression[c]=b;
                case 1 -> modulation[c]=b;
                case 64 -> {pedal[c]=b;if(b<64)released(c);}
                case 120 -> {Arrays.fill(velocity[c],0);Arrays.fill(held[c],false);}
                case 123 -> {Arrays.fill(held[c],false);if(pedal[c]<64)released(c);}
                case 121 -> {volume[c]=expression[c]=127;pedal[c]=modulation[c]=0;bend[c]=8192;released(c);}
                default -> {return;}
            }
        }else return;
        if(!enabled)return;
        if(events.size()>=MAX_EVENTS || now-origin>1_000_000_000_000_000L){restart(now,true);return;}
        events.add(new int[]{(int)Math.max(0,(now-origin)/1_000_000),command|c,a,b});
    }
    private static void row(StringBuilder s,int status,int a,int b){s.append(status).append(',').append(a).append(',').append(b).append(';');}
    private String snapshot(){
        StringBuilder s=new StringBuilder();
        for(int c=0;c<16;c++){
            if(volume[c]!=127)row(s,0xb0|c,7,volume[c]);if(expression[c]!=127)row(s,0xb0|c,11,expression[c]);
            if(pedal[c]!=0)row(s,0xb0|c,64,pedal[c]);if(modulation[c]!=0)row(s,0xb0|c,1,modulation[c]);
            if(bend[c]!=8192)row(s,0xe0|c,bend[c]&127,bend[c]>>7);
        }
        int count=0;
        // Bound late-join recovery, prioritizing physically held notes over old pedal tails.
        for(boolean down:new boolean[]{true,false})for(int c=0;c<16;c++)for(int n=0;n<128;n++)if(velocity[c][n]>0 && held[c][n]==down && count<48){
            row(s,0x90|c,n,velocity[c][n]);if(!down)row(s,0x80|c,n,0);count++;
        }
        return s.toString();
    }
    KahluaTable drain(int profile,long now){
        KahluaTable t=MidiTake.table();
        if(!enabled || (sequence>0 && events.isEmpty() && now-lastDrain<500_000_000L))return t;
        StringBuilder wire=new StringBuilder();
        for(int[] e:events){wire.append(e[0]).append(',');row(wire,e[1],e[2],e[3]);}
        t.rawset("v",1.0);t.rawset("epoch",(double)epoch);t.rawset("seq",(double)++sequence);
        t.rawset("profile",(double)profile);t.rawset("at",(double)Math.max(0,(now-origin)/1_000_000));
        t.rawset("events",wire.toString());t.rawset("state",snapshot());t.rawset("reset",reset);
        events.clear();reset=false;lastDrain=now;return t;
    }
}
