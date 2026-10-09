package azakaela.deadair;

import java.io.IOException;
import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import se.krka.kahlua.vm.KahluaTable;

/** Bounded SMF reader. Never opens MIDI devices, executes SysEx, or changes source files. */
final class MidiClipFile {
    static final int MAX_BYTES=4*1024*1024,MAX_EVENTS=200000,MAX_NOTES=32768;
    record Event(long tick,int track,int status,int a,int b){}
    record Note(int pitch,int tick,int duration,int velocity,int group){}
    record Group(int track,int channel,String name,boolean drums){}
    record Down(long tick,int velocity,int group){}
    record Clip(String name,List<Note> notes,List<Group> groups,int length,double bpm,String meter,String warning,String hint) {
        KahluaTable table(int selected,String mapping) {
            if(selected < -1||selected>=groups.size())throw new IllegalArgumentException("Choose a MIDI part.");
            String mode=mapping==null?"auto":mapping;String lower=name.toLowerCase(Locale.ROOT);
            boolean drums=selected>=0?groups.get(selected).drums:groups.stream().allMatch(Group::drums);
            if(mode.equals("auto")&&selected<0&&groups.stream().anyMatch(Group::drums)&&!drums)
                throw new IllegalArgumentException("This file mixes drums and melody. Choose one MIDI part first.");
            if(mode.equals("auto"))mode=hint.equals("livesd")?"livesd":drums?"gm":"keep";
            String notice=warning;
            if(mapping!=null&&mapping.equals("auto")&&hint.equals("unison")&&!lower.contains("consolidated")) {
                mode=unisonVoice(lower);
                if(mode==null)throw new IllegalArgumentException("This sample-trigger clip needs a drum sound. Choose one in Mapping, or use its Consolidated file.");
                notice=join(notice,"Sample trigger mapped to "+mode+".");
            }
            boolean mapped=!mode.equals("keep");
            if(!Set.of("keep","gm","livesd","kick","snare","clap","closed hat","open hat","pedal hat","tom","crash","ride","tambourine","cowbell","claves").contains(mode))throw new IllegalArgumentException("Unknown drum mapping.");
            KahluaTable out=MidiTake.table(),list=MidiTake.table(),choices=MidiTake.table();int count=0,unknown=0;
            for(Note n:notes)if(selected<0||n.group==selected) {
                if(++count>ScorePlayer.MAX_NOTES)throw new IllegalArgumentException("This MIDI selection exceeds 16,384 notes. Choose one source part.");
                int pitch=map(n.pitch,mode);if(mapped&&(pitch<35||pitch>81))unknown++;
                KahluaTable row=MidiTake.table();row.rawset("n",(double)pitch);row.rawset("t",(double)n.tick);row.rawset("d",(double)n.duration);row.rawset("v",(double)n.velocity);list.rawset((double)count,row);
            }
            if(count==0)throw new IllegalArgumentException("This MIDI part contains no notes.");
            for(int i=0;i<groups.size();i++){Group g=groups.get(i);choices.rawset((double)i+1,g.name+" / ch "+(g.channel+1)+(g.drums?" / drums":""));}
            if(unknown>0)notice=join(notice,unknown+" notes are outside the GM percussion range; mapping may need adjustment.");
            out.rawset("name",name);out.rawset("notes",list);out.rawset("groups",choices);out.rawset("length",(double)length);out.rawset("bpm",bpm);out.rawset("meter",meter);
            out.rawset("drums",mapped);out.rawset("warning",notice);out.rawset("mapping",mode);return out;
        }
    }
    static int map(int n,String mode){return switch(mode){case "livesd"->n==22?42:n==26?46:n;case "kick"->36;case "snare"->38;case "clap"->39;case "closed hat"->42;case "open hat"->46;case "pedal hat"->44;case "tom"->45;case "crash"->49;case "ride"->51;case "tambourine"->54;case "cowbell"->56;case "claves"->75;default->n;};}
    static String unisonVoice(String n){
        if(n.contains("hatclsd")||n.contains("closedhat"))return "closed hat";
        if(n.contains("hatopen")||n.contains("openhat"))return "open hat";
        if(n.contains("kick"))return "kick";if(n.contains("snare"))return "snare";if(n.contains("clap"))return "clap";
        if(n.contains("ride"))return "ride";if(n.contains("crash"))return "crash";if(n.contains("tom"))return "tom";
        if(n.contains("tamb"))return "tambourine";if(n.contains("cowbell"))return "cowbell";return null;
    }
    static String join(String a,String b){return a.isEmpty()?b:a+" "+b;}
    static final class Reader {
        final byte[] data;int at,end;
        Reader(byte[] data){this.data=data;end=data.length;}
        int u8(){if(at>=end)throw new IllegalArgumentException("Truncated MIDI data.");return data[at++]&255;}
        int u16(){return u8()*256+u8();}
        long u32(){return ((long)u16()<<16)|u16();}
        int vlq(){int value=0;for(int i=0;i<4;i++){int b=u8();value=(value<<7)|(b&127);if(b<128)return value;}throw new IllegalArgumentException("Invalid MIDI variable length.");}
        void skip(long count){if(count<0||count>end-at)throw new IllegalArgumentException("Truncated MIDI chunk.");at+=(int)count;}
        byte[] bytes(int n){int start=at;skip(n);return Arrays.copyOfRange(data,start,at);}
    }
    static Clip read(Path path,String hint,boolean forceDrums)throws IOException {
        long size=Files.size(path);if(size<14||size>MAX_BYTES)throw new IllegalArgumentException("Choose a MIDI file smaller than 4 MB.");
        byte[] bytes;try(var in=Files.newInputStream(path)){bytes=in.readNBytes(MAX_BYTES+1);}if(bytes.length>MAX_BYTES)throw new IllegalArgumentException("MIDI file grew beyond 4 MB.");
        Reader r=new Reader(bytes);if(r.u32()!=0x4d546864L)throw new IllegalArgumentException("Not a Standard MIDI File.");
        long header=r.u32();if(header<6||header>r.end-r.at)throw new IllegalArgumentException("Invalid MIDI header.");
        int format=r.u16(),tracks=r.u16(),ppq=r.u16();r.skip(header-6);
        if(format>1)throw new IllegalArgumentException("MIDI format 2 is not supported; export format 0 or 1.");
        if((ppq&0x8000)!=0)throw new IllegalArgumentException("SMPTE-timed MIDI is not supported; export beat-based MIDI.");
        if(ppq<1||tracks<1||tracks>128||(format==0&&tracks!=1))throw new IllegalArgumentException("Invalid MIDI timing or track count.");
        List<Event> events=new ArrayList<>();String[] names=new String[tracks];long lastTick=0,firstTempo=Long.MAX_VALUE;double bpm=120;String meter="4/4";Set<Integer> tempos=new HashSet<>();boolean controllers=false,signatures=false;int eventCount=0;
        for(int track=0;track<tracks;track++) {
            if(r.u32()!=0x4d54726bL)throw new IllegalArgumentException("Missing MIDI track chunk.");
            long length=r.u32();int fileEnd=r.end;if(length>fileEnd-r.at)throw new IllegalArgumentException("Truncated MIDI track.");r.end=r.at+(int)length;
            int running=0;long tick=0;boolean ended=false;
            while(r.at<r.end) {
                if(++eventCount>MAX_EVENTS)throw new IllegalArgumentException("MIDI file has too many events.");
                tick+=r.vlq();if(tick*96.0/ppq>ScorePlayer.MAX_TICKS)throw new IllegalArgumentException("MIDI file exceeds the song timeline capacity.");
                int status=r.u8();if(status<128){r.at--;if(running==0)throw new IllegalArgumentException("Invalid MIDI running status.");status=running;}
                if(status==255) {
                    int kind=r.u8(),n=r.vlq();byte[] data=r.bytes(n);
                    if(kind==3)names[track]=new String(data,StandardCharsets.UTF_8).replaceAll("[\\p{Cntrl}]","");
                    if(kind==81&&n==3){int us=(data[0]&255)*65536+(data[1]&255)*256+(data[2]&255);if(us>0){if(tick<firstTempo){bpm=60_000_000.0/us;firstTempo=tick;}tempos.add(us);}}
                    if(kind==88&&n>=2){int denom=data[1]&255;if(denom<8){String m=(data[0]&255)+"/"+(1<<denom);if(!m.equals("4/4")){signatures=true;meter=m;}}}
                    if(kind==47){ended=true;r.at=r.end;break;}
                } else if(status==240||status==247) {r.skip(r.vlq());running=0;controllers=true;}
                else if(status>=128&&status<240) {
                    running=status;int cmd=status&240,a=r.u8(),b=(cmd==192||cmd==208)?0:r.u8();if(a>127||b>127)throw new IllegalArgumentException("Invalid MIDI channel data.");
                    if(cmd==128||cmd==144||cmd==176)events.add(new Event(tick,track,status,a,b));
                    if((cmd==176&&a!=64&&a!=120&&a!=121&&a!=123)||cmd==224||cmd==208||cmd==160)controllers=true;
                } else throw new IllegalArgumentException("Unsupported MIDI system event.");
            }
            if(!ended)throw new IllegalArgumentException("MIDI track is missing its end marker.");
            lastTick=Math.max(lastTick,tick);r.end=fileEnd;
        }
        events.sort(Comparator.comparingLong(Event::tick));
        Map<Integer,ArrayDeque<Down>> held=new HashMap<>(),released=new HashMap<>();boolean[] sustain=new boolean[16];
        List<Group> groups=new ArrayList<>();Map<Integer,Integer> groupIndex=new HashMap<>();List<Note> notes=new ArrayList<>();
        for(Event e:events) {
            // Keep source-track voices separate when parts share a MIDI channel/pitch.
            int ch=e.status&15,key=(e.track*16+ch)*128+e.a,cmd=e.status&240;
            if(cmd==144&&e.b>0){int groupKey=e.track*16+ch;Integer group=groupIndex.get(groupKey);if(group==null){if(groups.size()>=128)throw new IllegalArgumentException("Too many MIDI source parts.");group=groups.size();groupIndex.put(groupKey,group);String name=names[e.track];if(name==null||name.isBlank())name="Track "+(e.track+1);groups.add(new Group(e.track,ch,name.substring(0,Math.min(80,name.length())),forceDrums||ch==9));}held.computeIfAbsent(key,k->new ArrayDeque<>()).add(new Down(e.tick,e.b,group));}
            else if(cmd==128||cmd==144){var q=held.get(key);if(q!=null&&!q.isEmpty()){Down d=q.removeFirst();if(sustain[ch])released.computeIfAbsent(key,k->new ArrayDeque<>()).add(d);else finish(notes,key,d,e.tick,ppq);}}
            else if(cmd==176&&e.a==64){sustain[ch]=e.b>=64;if(!sustain[ch])flush(notes,released,ch,e.tick,ppq);}
            else if(cmd==176&&(e.a==120||e.a==123||e.a==121)){flush(notes,released,ch,e.tick,ppq);if(e.a!=121)flush(notes,held,ch,e.tick,ppq);sustain[ch]=false;}
        }
        boolean unclosed=held.values().stream().anyMatch(q->!q.isEmpty());
        for(int ch=0;ch<16;ch++){flush(notes,held,ch,lastTick,ppq);flush(notes,released,ch,lastTick,ppq);}
        if(notes.isEmpty())throw new IllegalArgumentException("This MIDI file contains no note events.");
        notes.sort(Comparator.comparingInt(Note::tick).thenComparingInt(Note::pitch));int end=(int)Math.round(lastTick*96.0/ppq);for(Note n:notes)end=Math.max(end,n.tick+n.duration);
        String warning="";if(tempos.size()>1)warning=join(warning,"Tempo changes use the song's single BPM.");if(signatures)warning=join(warning,"Source meter "+meter+"; beat timing is kept on the 4/4 ruler.");if(controllers)warning=join(warning,"Pitch bend, expression and other automation are not imported.");if(unclosed)warning=join(warning,"Unclosed notes ended at the clip boundary.");
        String name=path.getFileName().toString().replaceFirst("(?i)\\.midi?$","");
        return new Clip(name,List.copyOf(notes),List.copyOf(groups),Math.max(96,end),bpm,meter,warning,hint);
    }
    private static void finish(List<Note> out,int key,Down d,long end,int ppq) {
        if(out.size()>=MAX_NOTES)throw new IllegalArgumentException("MIDI file exceeds 32,768 source notes. Export a smaller selection.");
        int t=(int)Math.round(d.tick*96.0/ppq),stop=(int)Math.round(end*96.0/ppq);if(t>=ScorePlayer.MAX_TICKS)throw new IllegalArgumentException("MIDI note exceeds timeline.");
        out.add(new Note(key%128,t,Math.min(ScorePlayer.MAX_TICKS-t,Math.max(1,stop-t)),d.velocity,d.group));
    }
    private static void flush(List<Note> out,Map<Integer,ArrayDeque<Down>> state,int ch,long tick,int ppq){for(var entry:state.entrySet()){int key=entry.getKey();if(key/128%16!=ch)continue;var q=entry.getValue();while(!q.isEmpty())finish(out,key,q.removeFirst(),tick,ppq);}}
}
