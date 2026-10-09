package azakaela.deadair;

import javax.sound.midi.*;
import java.nio.file.*;
import java.util.*;
import se.krka.kahlua.vm.KahluaTable;

/** Generated SMF fixtures. Optional pack scan is read-only and never copies third-party MIDI. */
public final class MidiImportTest {
    static int checks;
    static void check(boolean yes,String message){checks++;if(!yes)throw new AssertionError(message);}
    static void msg(Track t,int command,int ch,int a,int b,long tick)throws Exception{ShortMessage m=new ShortMessage();m.setMessage(command,ch,a,b);t.add(new MidiEvent(m,tick));}
    static void meta(Track t,int type,byte[] bytes,long tick)throws Exception{MetaMessage m=new MetaMessage();m.setMessage(type,bytes,bytes.length);t.add(new MidiEvent(m,tick));}
    static KahluaTable rows(KahluaTable t,String key){return (KahluaTable)t.rawget(key);}
    static int number(KahluaTable t,String key){return ((Number)t.rawget(key)).intValue();}
    static void fail(Path path,String hint,boolean drums,String text)throws Exception{try{MidiClipFile.read(path,hint,drums);throw new AssertionError("Accepted "+text);}catch(IllegalArgumentException ok){checks++;}}
    static void ready(MidiLibrary l)throws Exception{long until=System.nanoTime()+15_000_000_000L;while(Boolean.TRUE.equals(l.state().rawget("busy"))&&System.nanoTime()<until)Thread.sleep(10);check(!Boolean.TRUE.equals(l.state().rawget("busy")),"Index finishes asynchronously");}
    public static void main(String[] args)throws Exception{
        Path temp=Files.createTempDirectory("deadair-midi-test-");
        try {
            Sequence seq=new Sequence(Sequence.PPQ,480);Track lead=seq.createTrack(),kit=seq.createTrack();
            meta(lead,3,"Keys".getBytes(),0);meta(lead,81,new byte[]{7,(byte)161,32},0);meta(lead,81,new byte[]{10,44,42},1920);
            meta(lead,88,new byte[]{3,2,24,8},0);msg(lead,0x90,0,60,99,0);msg(lead,0xB0,0,64,127,100);msg(lead,0x80,0,60,0,200);msg(lead,0xB0,0,64,0,480);
            msg(lead,0x90,0,64,90,960);msg(lead,0x90,0,64,0,1440);msg(lead,0xE0,0,0,64,1500);
            msg(kit,0x90,9,36,110,240);msg(kit,0x80,9,36,0,300);meta(kit,47,new byte[0],1920);
            Path file=temp.resolve("Mixed Clip.mid");MidiSystem.write(seq,1,file.toFile());byte[] original=Files.readAllBytes(file);
            var clip=MidiClipFile.read(file,"gm",false);check(clip.notes().size()==3&&clip.groups().size()==2,"SMF1 tracks/channels become selectable parts");
            check(clip.notes().get(0).tick()==0&&clip.notes().get(0).duration()==96,"Sustain notes preserve musical duration");
            check(clip.length()==384&&clip.bpm()==120,"PPQ conversion, trailing rest and first tempo");
            check(clip.warning().contains("Tempo changes")&&clip.warning().contains("3/4")&&clip.warning().contains("Pitch bend"),"Lossy automation/meter handling is explicit");
            try{clip.table(-1,"auto");throw new AssertionError("Mixed melody and drums merged silently");}catch(IllegalArgumentException ok){checks++;}
            var selected=clip.table(0,"auto");check(rows(selected,"notes").len()==2&&!Boolean.TRUE.equals(selected.rawget("drums")),"Select melody without percussion");
            var percussion=clip.table(1,"auto");check(number((KahluaTable)rows(percussion,"notes").rawget(1.0),"n")==36&&Boolean.TRUE.equals(percussion.rawget("drums")),"Channel ten detects GM drums");
            check(!Boolean.TRUE.equals(clip.table(1,"keep").rawget("drums")),"Keep pitches explicitly uses the current melodic instrument");
            check(Arrays.equals(original,Files.readAllBytes(file)),"Import leaves original bytes unchanged");
            Sequence overlap=new Sequence(Sequence.PPQ,96);Track a=overlap.createTrack(),b=overlap.createTrack();
            msg(a,0x90,0,60,90,0);msg(a,0x80,0,60,0,96);msg(b,0x90,0,60,80,24);msg(b,0x80,0,60,0,48);
            meta(a,81,new byte[]{10,44,42},96);meta(b,81,new byte[]{7,(byte)161,32},0);
            Path shared=temp.resolve("Shared-channel.mid");MidiSystem.write(overlap,1,shared.toFile());var voices=MidiClipFile.read(shared,"gm",false);
            check(voices.notes().get(0).duration()==96&&voices.notes().get(1).duration()==24,"Overlapping same-key source tracks retain their own note-offs");
            check(voices.bpm()==120,"First chronological tempo, even in a later source track");Files.delete(shared);
            Path running=temp.resolve("Running.mid");Files.write(running,HexFormat.of().parseHex("4d546864000000060000000100604d54726b0000001100903c64003e500c3c000c3e0000ff2f00"));
            var runningClip=MidiClipFile.read(running,"gm",false);check(runningClip.notes().size()==2&&runningClip.notes().get(0).duration()==12&&runningClip.notes().get(1).duration()==24,"Running status and velocity-zero note-offs");Files.delete(running);
            Sequence single=new Sequence(Sequence.PPQ,96);Track t=single.createTrack();msg(t,0x90,0,60,100,24);msg(t,0x80,0,60,0,48);meta(t,47,new byte[0],384);
            Path kick=temp.resolve("Kit_01_120_Kick.mid");MidiSystem.write(single,0,kick.toFile());var trigger=MidiClipFile.read(kick,"unison",true).table(-1,"auto");
            check(number((KahluaTable)rows(trigger,"notes").rawget(1.0),"n")==36,"Unison sample trigger is a kick, not MIDI C4");
            Path perc=temp.resolve("Kit_01_120_Perc.mid");Files.copy(kick,perc);var unknown=MidiClipFile.read(perc,"unison",true);
            try{unknown.table(-1,"auto");throw new AssertionError("Guessed ambiguous percussion");}catch(IllegalArgumentException ok){checks++;}
            check(number((KahluaTable)rows(unknown.table(-1,"claves"),"notes").rawget(1.0),"n")==75,"Ambiguous triggers accept a user-selected sound");
            check(MidiClipFile.map(22,"livesd")==42&&MidiClipFile.map(26,"livesd")==46&&MidiClipFile.map(41,"livesd")==41,"Session Drums articulations map to GM hats; standard tom kept");
            Path bad=temp.resolve("bad.mid");Files.write(bad,new byte[]{1,2,3});fail(bad,"gm",false,"non-MIDI file");
            byte[] corrupted=Files.readAllBytes(kick);corrupted[9]=2;Files.write(bad,corrupted);fail(bad,"gm",false,"format 2");
            corrupted=Files.readAllBytes(kick);corrupted[12]=(byte)0xE7;Files.write(bad,corrupted);fail(bad,"gm",false,"SMPTE timing");
            corrupted=Files.readAllBytes(kick);for(int i=18;i<22;i++)corrupted[i]=(byte)255;Files.write(bad,corrupted);fail(bad,"gm",false,"oversized declared chunk");
            Files.delete(bad);Files.copy(kick,temp.resolve("._ignore.mid"));Files.createDirectories(temp.resolve("__MACOSX"));Files.copy(kick,temp.resolve("__MACOSX/ignore.mid"));
            Path config=temp.resolve("folders.txt");Files.writeString(config,"Test\tnotes\tgm\t"+temp+"\nTest duplicate\tnotes\tgm\t"+temp+"\n");
            MidiLibrary library=new MidiLibrary(config);library.refresh();ready(library);check(number(library.state(),"count")==3,"Index ignores Apple resource forks and duplicate roots");
            var found=library.search("mixed clip",0,0);check(number(found,"count")==1,"Search matches all case-insensitive words");String id=(String)((KahluaTable)rows(found,"rows").rawget(1.0)).rawget("id");
            int token=library.request(id);KahluaTable result=null;for(int i=0;i<300;i++){result=library.result(token,0,"auto");if(!"loading".equals(result.rawget("state")))break;Thread.sleep(5);}
            check("ready".equals(result.rawget("state"))&&rows(rows(result,"clip"),"notes").len()==2,"Async selected clip load returns safe note tables");
            library.refresh();ready(library);check("error".equals(library.result(library.request(id),0,"auto").rawget("state")),"Old catalog IDs cannot point at different files after refresh");
            if(args.length>0){
                MidiLibrary real=new MidiLibrary(Path.of(args[0]));long began=System.nanoTime();real.refresh();ready(real);System.out.println("LOCAL CATALOG: "+real.state().rawget("status")+" / "+(System.nanoTime()-began)/1_000_000+" ms");
                int files=0,notes=0,errors=0;Map<String,Integer> mappings=new TreeMap<>();
                for(var root:MidiLibrary.readRoots(Path.of(args[0]))){try(var paths=Files.walk(root.path())){for(Path p:paths.filter(Files::isRegularFile).filter(MidiLibrary::midi).filter(p->!p.toString().contains("__MACOSX")).sorted().limit(30).toList()){
                    try{var data=MidiClipFile.read(p,root.mapping(),root.kind().equals("drums"));files++;notes+=data.notes().size();try{var mapped=data.table(-1,"auto");mappings.merge((String)mapped.rawget("mapping"),1,Integer::sum);}catch(IllegalArgumentException expected){mappings.merge("needs explicit sound/part",1,Integer::sum);}}
                    catch(Exception e){errors++;System.out.println("LOCAL IMPORT ERROR: "+root.label()+" / "+p.getFileName()+" / "+e.getMessage());}
                }}}
                System.out.println("LOCAL SAMPLES: "+files+" clips / "+notes+" notes / mappings "+mappings+" / errors "+errors);check(errors==0,"Real-pack samples parse without errors");
            }
            System.out.println("PASS: "+checks+" SMF parsing, sustain, mappings, malformed data, async library, stale IDs and source-preservation checks; no device opened");
        }finally{try(var paths=Files.walk(temp)){for(Path p:paths.sorted(Comparator.reverseOrder()).toList())Files.deleteIfExists(p);}}
    }
}
