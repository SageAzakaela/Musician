package azakaela.deadair;

import java.util.*;
import se.krka.kahlua.vm.KahluaTable;

/** Validate the network boundary again before allowing MIDI into native audio. */
record LivePacket(int owner,int epoch,int sequence,int profile,int at,boolean reset,List<Event> events,List<Event> state) {
    record Event(int time,int status,int a,int b){}
    static boolean supported(int status,int a){
        int command=status&0xf0;
        return command==0x80 || command==0x90 || command==0xe0 || (command==0xb0 && VoiceEngine.supportedController(a));
    }
    static List<Event> decode(String wire,boolean timed,int at){
        if(wire==null || wire.length()>4096)throw new IllegalArgumentException("Live MIDI packet too large");
        List<Event> rows=new ArrayList<>();int last=Math.max(0,at-1000);
        if(wire.isEmpty())return rows;
        if(!wire.endsWith(";"))throw new IllegalArgumentException("Truncated live MIDI");
        for(String token:wire.substring(0,wire.length()-1).split(";",-1)){
            String[] fields=token.split(",",-1);
            if(fields.length!=(timed?4:3) || rows.size()>=(timed?128:256))throw new IllegalArgumentException("Invalid live MIDI rows");
            int[] n=new int[fields.length];
            for(int i=0;i<n.length;i++){if(!fields[i].matches("[0-9]{1,10}"))throw new IllegalArgumentException("Invalid live MIDI number");n[i]=Integer.parseInt(fields[i]);}
            int t=timed?n[0]:at,i=timed?1:0,status=n[i],a=n[i+1],b=n[i+2];
            if(t<last || t>at || status<128 || status>239 || a>127 || b>127 || !supported(status,a))throw new IllegalArgumentException("Invalid live MIDI event");
            rows.add(new Event(t,status,a,b));last=t;
        }
        if(!timed){int notes=0;Set<Integer> keys=new HashSet<>();for(Event e:rows)if((e.status&0xf0)==0x90 && e.b>0){if(!keys.add((e.status&15)*128+e.a) || ++notes>48)throw new IllegalArgumentException("Invalid live MIDI snapshot");}}
        return rows;
    }
    static LivePacket read(int owner,KahluaTable t){
        if(owner<0 || owner>65535 || t==null || ScorePlayer.number(t,"v",1,1)!=1)throw new IllegalArgumentException("Invalid live MIDI sender");
        int at=ScorePlayer.number(t,"at",0,1_000_000_000);
        Object events=t.rawget("events"),state=t.rawget("state");
        if(!(events instanceof String e) || !(state instanceof String s))throw new IllegalArgumentException("Invalid live MIDI data");
        return new LivePacket(owner,ScorePlayer.number(t,"epoch",1,Integer.MAX_VALUE),ScorePlayer.number(t,"seq",1,Integer.MAX_VALUE),ScorePlayer.number(t,"profile",0,15),at,Boolean.TRUE.equals(t.rawget("reset")),decode(e,true,at),decode(s,false,at));
    }
}
