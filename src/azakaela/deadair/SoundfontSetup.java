package azakaela.deadair;

import musician.gervill.*;
import javax.sound.midi.*;
import java.nio.file.*;
import java.io.*;
import java.util.*;
import se.krka.kahlua.vm.KahluaTable;

/** Local settings and optional pack catalogue. File parsing is called only on the device worker. */
final class SoundfontSetup {
    static final String BUNDLED="bundled";
    static final long MAX_BYTES=256L*1024*1024;
    record Bank(String id,String name,Path path,Path root) {}
    record Choice(String bank,String preset) {}
    record Preset(String key,String name,int bank,int program,boolean drums,ModelInstrument instrument) {}
    record Resolved(ModelInstrument[] instruments,String summary,List<String> warnings) {}
    private record Cached(long size,long modified,SF2Soundbank bank) {}
    private static final Map<Path,Cached> CACHE=new LinkedHashMap<>(8,.75f,true);
    private final Path config;
    private final LinkedHashMap<String,Bank> personal=new LinkedHashMap<>();
    private Map<String,Bank> packs=Map.of();
    private Choice[] saved=defaults();
    private boolean loaded;
    private Path common;
    private String message="Choose an instrument, a soundfont and a preset. Apply saves your mappings.";
    private int revision;
    private volatile KahluaTable published;
    private String inspected="",added="";
    private List<Preset> presets=List.of();
    SoundfontSetup(Path config){this.config=config;publish();}
    static Choice[] defaults(){Choice[] out=new Choice[16];Arrays.fill(out,new Choice("",""));return out;}
    static String clean(String s){return s==null?"":s.replaceAll("[\\p{Cntrl}]","").strip();}
    static String presetKey(Patch p){return p.getBank()+":"+p.getProgram()+":"+(p instanceof ModelPatch m&&m.isPercussion()?1:0);}
    static List<Preset> presets(SF2Soundbank bank)throws IOException {
        List<Preset> list=new ArrayList<>();
        if(bank.getInstruments().length>4096)throw new IOException("Soundfont has more than 4096 presets.");
        for(Instrument i:bank.getInstruments())if(i instanceof ModelInstrument m){Patch p=i.getPatch();list.add(new Preset(presetKey(p),clean(i.getName()),p.getBank()>>7,p.getProgram(),p instanceof ModelPatch mp&&mp.isPercussion(),m));}
        if(list.isEmpty())throw new IOException("This soundfont contains no instrument presets.");
        list.sort(Comparator.comparing(Preset::drums).thenComparingInt(Preset::bank).thenComparingInt(Preset::program));
        return List.copyOf(list);
    }
    static synchronized SF2Soundbank readBank(Path file)throws IOException {
        Path path=file.toRealPath();
        if(!path.getFileName().toString().toLowerCase(Locale.ROOT).endsWith(".sf2"))throw new IOException("Choose an SF2 soundfont (.sf2).");
        long size=Files.size(path),modified=Files.getLastModifiedTime(path).toMillis();
        if(size<12||size>MAX_BYTES)throw new IOException("Soundfont must be between 12 bytes and 256 MiB.");
        Cached cached=CACHE.get(path);
        if(cached!=null&&cached.size==size&&cached.modified==modified)return cached.bank;
        SF2Soundbank bank=new SF2Soundbank(path.toFile());presets(bank);
        CACHE.put(path,new Cached(size,modified,bank));
        while(CACHE.size()>4)CACHE.remove(CACHE.keySet().iterator().next());
        return bank;
    }
    static Path safePackPath(Path root,String relative)throws IOException {
        if(relative==null||relative.length()>1024)throw new IOException("Invalid soundfont pack path.");
        Path base=root.toRealPath(),part=Path.of(relative);
        if(part.isAbsolute())throw new IOException("Pack soundfonts need a relative path inside the mod's common folder.");
        Path path=base.resolve(part).normalize();
        if(!path.startsWith(base))throw new IOException("Soundfont pack path leaves its mod folder.");
        path=path.toRealPath();if(!path.startsWith(base))throw new IOException("Soundfont pack link leaves its mod folder.");
        return path;
    }
    synchronized void packs(Map<String,Bank> registered){packs=Map.copyOf(registered);revision++;publish();}
    synchronized void initialize(Path common)throws IOException {
        this.common=common;if(loaded)return;
        try{if(Files.exists(config)){
            if(Files.size(config)>131072)throw new IOException("Soundfont settings are too large; restore the settings backup.");
            Properties p=new Properties();try(Reader r=Files.newBufferedReader(config)){p.load(r);}
            for(int i=0;i<32;i++){
                String id=p.getProperty("file."+i+".id"),path=p.getProperty("file."+i+".path");
                if(id!=null&&id.startsWith("file:")&&path!=null)try{personal.put(id,new Bank(id,clean(p.getProperty("file."+i+".name",Path.of(path).getFileName().toString())),Path.of(path),null));}catch(InvalidPathException ignored){}
            }
            for(int i=0;i<16;i++){String bank=p.getProperty("instrument."+i+".bank",""),preset=p.getProperty("instrument."+i+".preset","");if(bank.length()<=256&&preset.length()<=64)saved[i]=new Choice(bank,preset);}
        }}catch(IOException|IllegalArgumentException e){personal.clear();saved=defaults();message="Could not read soundfont settings; using included sounds. The original file is preserved until Apply. "+safe(e);}
        loaded=true;revision++;publish();
    }
    synchronized Map<String,Bank> banks(){
        LinkedHashMap<String,Bank> all=new LinkedHashMap<>();
        if(common!=null)all.put(BUNDLED,new Bank(BUNDLED,"GeneralUser GS (included)",common.resolve("media/soundfonts/GeneralUser-GS.sf2"),null));
        packs.values().stream().sorted(Comparator.comparing(Bank::name)).forEach(b->all.put(b.id,b));all.putAll(personal);return all;
    }
    private Path path(Bank b)throws IOException {return b.root==null?b.path:safePackPath(b.root,b.path.toString());}
    synchronized void add(String value)throws IOException {
        String raw=value==null?"":value.strip();if(raw.startsWith("\"")&&raw.endsWith("\""))raw=raw.substring(1,raw.length()-1);
        Path path=Path.of(raw).toRealPath();readBank(path);
        for(Bank b:personal.values())if(b.path.equals(path)){added=b.id;inspect(b.id);return;}
        if(personal.size()>=32)throw new IOException("The personal soundfont list is full (32 files).");
        String id="file:"+UUID.randomUUID();Bank b=new Bank(id,path.getFileName().toString(),path,null);personal.put(id,b);
        try{save(saved);}catch(IOException e){personal.remove(id);throw e;}
        added=id;inspect(id);message="Added "+b.name+". Choose a preset and assign it to an instrument.";revision++;publish();
    }
    synchronized void inspect(String id)throws IOException {
        inspected=id;presets=List.of();revision++;publish();
        Bank bank=banks().get(id);if(bank==null)throw new IOException("Soundfont pack is unavailable. Enable its mod or choose another bank.");
        List<Preset> found=presets(readBank(path(bank)));inspected=id;presets=found;message=found.size()+" presets in "+bank.name+".";revision++;publish();
    }
    synchronized Preset preset(String bank,String key)throws IOException {
        Bank b=banks().get(bank);if(b==null)throw new IOException("Selected soundfont is unavailable.");
        for(Preset p:presets(readBank(path(b))))if(p.key.equals(key))return p;
        throw new IOException("Selected preset is missing. Refresh and choose it again.");
    }
    static Resolved bundled(Path common)throws IOException {
        SF2Soundbank bank=readBank(common.resolve("media/soundfonts/GeneralUser-GS.sf2"));ModelInstrument[] voices=new ModelInstrument[16];
        for(int i=0;i<16;i++){
            Instrument instrument=bank.getInstrument(new ModelPatch(VoiceEngine.drums(i)?0:VoiceEngine.bank(i)<<7,VoiceEngine.program(i),VoiceEngine.drums(i)));
            if(!(instrument instanceof ModelInstrument m))throw new IOException("Bundled instrument preset is missing: "+VoiceEngine.PROFILES[i]);voices[i]=m;
        }
        return new Resolved(voices,"GeneralUser GS",List.of());
    }
    synchronized Resolved resolve(Choice[] choices)throws IOException {
        ModelInstrument[] voices=bundled(common).instruments.clone();List<String> warnings=new ArrayList<>();int changed=0;long total=0;Set<Path> selectedFiles=new HashSet<>();
        for(int i=0;i<16;i++)if(!choices[i].bank.isEmpty())try{
                Bank bank=banks().get(choices[i].bank);if(bank==null)throw new IOException("Soundfont pack is unavailable");Path file=path(bank).toRealPath();
                if(!selectedFiles.contains(file)){long size=Files.size(file);if(total+size>512L*1024*1024)throw new IOException("Selected soundfonts exceed the 512 MiB combined limit");total+=size;selectedFiles.add(file);}
                voices[i]=preset(choices[i].bank,choices[i].preset).instrument;changed++;}
            catch(Exception e){warnings.add(VoiceEngine.PROFILES[i]+": using included sound ("+safe(e)+")");}
        return new Resolved(voices,changed==0?"GeneralUser GS":changed+" custom assignments / GeneralUser fallback",List.copyOf(warnings));
    }
    synchronized Resolved resolve()throws IOException{return resolve(saved);}
    synchronized Choice[] saved(){return saved.clone();}
    static Choice[] choices(KahluaTable table){
        if(table==null||table.len()!=16)throw new IllegalArgumentException("Expected one mapping for each of the 16 instruments.");
        Choice[] result=defaults();
        for(int i=0;i<16;i++){
            if(!(table.rawget((double)i+1) instanceof KahluaTable row))throw new IllegalArgumentException("Invalid soundfont mapping.");
            Object b=row.rawget("bank"),p=row.rawget("preset");
            if(!(b instanceof String bank)||!(p instanceof String preset)||bank.length()>256||preset.length()>64)throw new IllegalArgumentException("Invalid soundfont mapping.");
            if(bank.isEmpty()!=preset.isEmpty())throw new IllegalArgumentException("Choose both a soundfont and a preset.");
            result[i]=new Choice(bank,preset);
        }return result;
    }
    synchronized void save(Choice[] choices)throws IOException {
        Properties out=new Properties();out.setProperty("version","1");int i=0;
        for(Bank b:personal.values()){String key="file."+(i++)+".";out.setProperty(key+"id",b.id);out.setProperty(key+"name",b.name);out.setProperty(key+"path",b.path.toString());}
        for(i=0;i<16;i++){out.setProperty("instrument."+i+".bank",choices[i].bank);out.setProperty("instrument."+i+".preset",choices[i].preset);}
        Files.createDirectories(config.getParent());Path temp=Files.createTempFile(config.getParent(),"musician-soundfonts-",".tmp");
        try{
            try(Writer w=Files.newBufferedWriter(temp)){out.store(w,"Musician personal soundfont settings. Not sent to servers or other players.");}
            if(Files.exists(config))Files.copy(config,config.resolveSibling(config.getFileName()+".bak"),StandardCopyOption.REPLACE_EXISTING);
            try{Files.move(temp,config,StandardCopyOption.ATOMIC_MOVE,StandardCopyOption.REPLACE_EXISTING);}catch(AtomicMoveNotSupportedException e){Files.move(temp,config,StandardCopyOption.REPLACE_EXISTING);}
            saved=choices.clone();revision++;publish();
        }finally{Files.deleteIfExists(temp);}
    }
    synchronized void message(String text){message=clean(text);revision++;publish();}
    static String safe(Throwable e){return clean(e.getMessage()==null?e.getClass().getSimpleName():e.getMessage());}
    KahluaTable state(){return published;}
    private void publish(){
        KahluaTable out=MidiTake.table(),banks=MidiTake.table(),mapping=MidiTake.table(),rows=MidiTake.table();int i=0;
        for(Bank b:banks().values()){KahluaTable row=MidiTake.table();row.rawset("id",b.id);row.rawset("name",b.name);row.rawset("pack",b.root!=null);banks.rawset((double)++i,row);}
        for(i=0;i<16;i++){KahluaTable row=MidiTake.table();row.rawset("name",i==0?"Piano / keytar":VoiceEngine.PROFILES[i]);row.rawset("bank",saved[i].bank);row.rawset("preset",saved[i].preset);mapping.rawset((double)i+1,row);}
        i=0;for(Preset p:presets){KahluaTable row=MidiTake.table();row.rawset("key",p.key);row.rawset("name",p.name);row.rawset("bank",(double)p.bank);row.rawset("program",(double)p.program);row.rawset("drums",p.drums);rows.rawset((double)++i,row);}
        out.rawset("banks",banks);out.rawset("mappings",mapping);out.rawset("presets",rows);out.rawset("inspected",inspected);out.rawset("added",added);out.rawset("revision",(double)revision);out.rawset("message",message);out.rawset("loaded",loaded);published=out;
    }
}
