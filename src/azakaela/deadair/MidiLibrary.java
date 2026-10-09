package azakaela.deadair;

import java.io.*;
import java.nio.file.*;
import java.nio.file.attribute.BasicFileAttributes;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;
import se.krka.kahlua.vm.KahluaTable;

/** Filename-only local catalog. All filesystem/SMF work uses a separate daemon, never the audio worker. */
final class MidiLibrary {
    record Root(String label,String kind,String mapping,Path path){}
    record Entry(String id,String name,String relative,Root root,Path path,String search){}
    private final Path config;
    private final ExecutorService worker=Executors.newSingleThreadExecutor(r->{Thread t=new Thread(r,"DeadAir-MidiLibrary");t.setDaemon(true);return t;});
    private final AtomicBoolean scanning=new AtomicBoolean();private final AtomicInteger serial=new AtomicInteger();
    private volatile List<Root> roots=List.of();private volatile List<Entry> entries=List.of();private volatile Map<String,Entry> byId=Map.of();
    private volatile String status="Add a MIDI folder, then Refresh.";private volatile int revision;private volatile Load load;
    record Load(int token,MidiClipFile.Clip clip,String error){}
    MidiLibrary(Path config){this.config=config;}
    static String clean(String s){return s==null?"":s.replaceAll("[\\p{Cntrl}]","").strip();}
    static boolean midi(Path p){String n=p.getFileName().toString().toLowerCase(Locale.ROOT);return !n.startsWith("._")&&(n.endsWith(".mid")||n.endsWith(".midi"));}
    static List<Root> readRoots(Path file)throws IOException {
        if(!Files.exists(file))return List.of();if(Files.size(file)>65536)throw new IOException("MIDI folder list is too large.");
        List<Root> result=new ArrayList<>();Set<Path> seen=new HashSet<>();
        for(String line:Files.readAllLines(file)){
            if(line.isBlank()||line.startsWith("#"))continue;String[] p=line.split("\t",4);if(p.length!=4)continue;
            Path path=Path.of(p[3]).toAbsolutePath().normalize();if(seen.add(path))result.add(new Root(clean(p[0]),p[1].equals("drums")?"drums":"notes",Set.of("livesd","unison").contains(p[2])?p[2]:"gm",path));
            if(result.size()>=64)break;
        }return List.copyOf(result);
    }
    void refresh(){if(!scanning.compareAndSet(false,true))return;status="Scanning MIDI filenames...";worker.execute(()->{try{scan(readRoots(config));}catch(Exception e){status="Library: "+e.getMessage();}finally{scanning.set(false);}});}
    void addFolder(String value){
        if(!scanning.compareAndSet(false,true))return;status="Adding MIDI folder...";
        worker.execute(()->{try{
            String raw=value==null?"":value.strip();if(raw.startsWith("\"")&&raw.endsWith("\""))raw=raw.substring(1,raw.length()-1);
            if(raw.isBlank())throw new IOException("Enter a folder path.");
            Path path=Path.of(raw).toRealPath();if(!Files.isDirectory(path))throw new IOException("Choose an existing folder.");
            List<Root> updated=new ArrayList<>(readRoots(config));if(updated.stream().noneMatch(r->r.path.equals(path))){if(updated.size()>=64)throw new IOException("Folder capacity reached (64).");String name=clean(path.getFileName()==null?path.toString():path.getFileName().toString());String low=name.toLowerCase(Locale.ROOT);updated.add(new Root(name,low.contains("drum")||low.contains("live sd")?"drums":"notes",low.contains("live sd")?"livesd":low.contains("unison")&&low.contains("drum")?"unison":"gm",path));}
            Files.createDirectories(config.getParent());List<String> lines=new ArrayList<>();lines.add("# Musician local MIDI folders: label, kind, mapping, absolute path (tab separated)");
            for(Root r:updated)lines.add(r.label+"\t"+r.kind+"\t"+r.mapping+"\t"+r.path);
            Path temp=Files.createTempFile(config.getParent(),"deadair-midi-",".tmp");try{Files.write(temp,lines);try{Files.move(temp,config,StandardCopyOption.ATOMIC_MOVE,StandardCopyOption.REPLACE_EXISTING);}catch(AtomicMoveNotSupportedException e){Files.move(temp,config,StandardCopyOption.REPLACE_EXISTING);}}finally{Files.deleteIfExists(temp);}
            scan(updated);
        }catch(Exception e){status="Folder not added: "+e.getMessage();}finally{scanning.set(false);}});
    }
    private void scan(List<Root> sources)throws IOException {
        List<Entry> found=new ArrayList<>();Set<Path> seen=new HashSet<>();int generation=revision+1;int[] unavailable={0};boolean[] capped={false};
        for(Root root:sources){
            if(!Files.isDirectory(root.path)){unavailable[0]++;continue;}
            Files.walkFileTree(root.path,EnumSet.noneOf(FileVisitOption.class),32,new SimpleFileVisitor<>(){
                @Override public FileVisitResult preVisitDirectory(Path dir,BasicFileAttributes attrs){String n=dir.getFileName()==null?"":dir.getFileName().toString();return n.equals("__MACOSX")||n.startsWith(".")?FileVisitResult.SKIP_SUBTREE:FileVisitResult.CONTINUE;}
                @Override public FileVisitResult visitFileFailed(Path file,IOException e){unavailable[0]++;return FileVisitResult.CONTINUE;}
                @Override public FileVisitResult visitFile(Path path,BasicFileAttributes attrs){
                    if(found.size()>=100000){capped[0]=true;return FileVisitResult.TERMINATE;}
                    if(attrs.isRegularFile()&&attrs.size()<=MidiClipFile.MAX_BYTES&&midi(path)&&seen.add(path.toAbsolutePath().normalize())){
                        String relative=root.path.relativize(path).toString();String name=path.getFileName().toString().replaceFirst("(?i)\\.midi?$","");
                        found.add(new Entry(generation+":"+found.size(),name,relative,root,path,(root.label+" "+relative).toLowerCase(Locale.ROOT)));
                    }return FileVisitResult.CONTINUE;
                }
            });if(capped[0])break;
        }
        found.sort(Comparator.comparing(e->e.search));Map<String,Entry> index=new HashMap<>();for(Entry e:found)index.put(e.id,e);
        roots=List.copyOf(sources);entries=List.copyOf(found);byId=Map.copyOf(index);revision=generation;
        status=found.size()+" local MIDI files"+(unavailable[0]>0?"; "+unavailable[0]+" unavailable folders/files":"")+(capped[0]?"; filename capacity reached (100,000)":"")+". Source files stay in place.";
    }
    KahluaTable state(){KahluaTable out=MidiTake.table(),list=MidiTake.table();out.rawset("busy",scanning.get());out.rawset("status",status);out.rawset("revision",(double)revision);out.rawset("count",(double)entries.size());for(int i=0;i<roots.size();i++)list.rawset((double)i+1,roots.get(i).label);out.rawset("roots",list);return out;}
    KahluaTable search(String query,int source,int offset){
        String[] terms=clean(query).toLowerCase(Locale.ROOT).split("\\s+");List<Entry> snapshot=entries;List<Root> sources=roots;offset=Math.max(0,offset);
        KahluaTable result=MidiTake.table(),rows=MidiTake.table();int count=0,returned=0;
        for(Entry e:snapshot){if(source>0&&(source>sources.size()||!e.root.equals(sources.get(source-1))))continue;boolean match=true;for(String word:terms)if(!e.search.contains(word)){match=false;break;}if(!match)continue;
            if(count++>=offset&&returned<60){KahluaTable row=MidiTake.table();row.rawset("id",e.id);row.rawset("name",clean(e.name));row.rawset("path",clean(e.relative));row.rawset("source",e.root.label);row.rawset("drums",e.root.kind.equals("drums"));rows.rawset((double)++returned,row);}
        }result.rawset("rows",rows);result.rawset("count",(double)count);result.rawset("offset",(double)offset);result.rawset("revision",(double)revision);return result;
    }
    int request(String id){Entry e=byId.get(id);if(e==null){int n=serial.incrementAndGet();load=new Load(n,null,"Refresh the library and choose the clip again.");return n;}return request(e.path,e.root.mapping,e.root.kind.equals("drums"));}
    int openPath(String value){
        try{String path=value.strip();if(path.startsWith("\"")&&path.endsWith("\""))path=path.substring(1,path.length()-1);Path p=Path.of(path).toAbsolutePath().normalize();if(!midi(p))throw new IllegalArgumentException("Choose a .mid or .midi file.");return request(p,"gm",false);}
        catch(Exception e){int n=serial.incrementAndGet();load=new Load(n,null,e.getMessage());return n;}
    }
    private int request(Path path,String hint,boolean drums){int n=serial.incrementAndGet();load=new Load(n,null,null);worker.execute(()->{try{MidiClipFile.Clip clip=MidiClipFile.read(path,hint,drums);if(serial.get()==n)load=new Load(n,clip,null);}catch(Exception e){if(serial.get()==n)load=new Load(n,null,e.getMessage());}});return n;}
    KahluaTable result(int token,int group,String mapping){
        KahluaTable out=MidiTake.table();Load current=load;if(current==null||current.token!=token){out.rawset("state","stale");return out;}
        if(current.error!=null){out.rawset("state","error");out.rawset("message",current.error);return out;}
        if(current.clip==null){out.rawset("state","loading");return out;}
        try{out.rawset("clip",current.clip.table(group,mapping));out.rawset("state","ready");}
        catch(IllegalArgumentException e){out.rawset("state","error");out.rawset("message",e.getMessage());KahluaTable groups=MidiTake.table();for(int i=0;i<current.clip.groups().size();i++)groups.rawset((double)i+1,current.clip.groups().get(i).name());out.rawset("groups",groups);}
        return out;
    }
}
