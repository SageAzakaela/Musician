package azakaela.deadair;

import java.util.Arrays;
import se.krka.kahlua.vm.KahluaTable;

/** Fixed-size visual telemetry. Written with the engine lock; never delays MIDI to animate. */
final class DrumActivity {
    static final String[] NAMES={"kick","snare","hat","hatPedal","floor","rackLow","rackHigh","cymbal"};
    final long[] attacks=new long[8];
    final int[] velocities=new int[8];
    static int group(int note){return switch(note){
        case 35,36 -> 0;
        case 37,38,40 -> 1;
        case 42,46 -> 2;
        case 44 -> 3;
        case 41,43 -> 4;
        case 45,47 -> 5;
        case 48,50 -> 6;
        case 49,51,52,53,55,57,59 -> 7;
        default -> -1;
    };}
    void hit(int note,int velocity){int group=group(note);if(group>=0){attacks[group]++;velocities[group]=velocity;}}
    void reset(){Arrays.fill(attacks,0);Arrays.fill(velocities,0);}
    KahluaTable table(){
        KahluaTable out=MidiTake.table();
        for(int i=0;i<NAMES.length;i++){
            KahluaTable row=MidiTake.table();row.rawset("attack",(double)attacks[i]);row.rawset("velocity",(double)velocities[i]);out.rawset(NAMES[i],row);
        }
        return out;
    }
}
