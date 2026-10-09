package azakaela.deadair;

import me.zed_0xff.zombie_buddy.Exposer;
import javax.sound.midi.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicBoolean;

@Exposer.LuaClass
public final class DeadAirMidi {
    private static final VoiceEngine ENGINE=new VoiceEngine();
    private static final MidiTake TAKE=new MidiTake();
    private static final ExecutorService WORKER=Executors.newSingleThreadExecutor(r->{Thread t=new Thread(r,"DeadAir-Devices");t.setDaemon(true);return t;});
    private static final AtomicBoolean BUSY=new AtomicBoolean();
    private record Input(String key,String name,int backend) {}
    private static volatile List<Input> inputs=List.of();
    private static volatile String status="Choose a MIDI input and connect.";
    private static volatile MidiDevice device;
    private static volatile Transmitter transmitter;
    private static volatile AudioOutput output;
    private static volatile MidiInputReceiver receiver;
    private static volatile String connectedInput="";
    private static volatile int audioResponse=1;
    private static volatile int audioDriver=4;
    private static final java.util.concurrent.atomic.AtomicInteger FONT_PREVIEW=new java.util.concurrent.atomic.AtomicInteger();
    private static final class FontsHolder {
        static final SoundfontSetup INSTANCE=new SoundfontSetup(java.nio.file.Path.of(zombie.ZomboidFileSystem.instance.getCacheDir(),"Lua","MusicianSoundfonts.properties"));
    }
    private interface FontTask {void run(SoundfontSetup setup,java.nio.file.Path common)throws Exception;}
    private static boolean fontTask(String label,FontTask task){
        if(!BUSY.compareAndSet(false,true))return false;
        WORKER.execute(()->{SoundfontSetup setup=FontsHolder.INSTANCE;try{var common=commonDirectory();setup.initialize(common);task.run(setup,common);}catch(Exception|LinkageError e){setup.message(label+": "+safe(e));}finally{BUSY.set(false);}});return true;
    }
    public static se.krka.kahlua.vm.KahluaTable soundfontState(){return FontsHolder.INSTANCE.state();}
    public static boolean soundfontRefresh(){return fontTask("Soundfonts",(setup,common)->setup.inspect(SoundfontSetup.BUNDLED));}
    public static boolean soundfontInspect(String id){return fontTask("Soundfont could not load",(setup,common)->setup.inspect(id));}
    public static boolean soundfontAdd(String path){return fontTask("Soundfont not added",(setup,common)->setup.add(path));}
    public static void soundfontBrowse(){
        // Only an explicit UI click opens the picker. A text-path field remains available.
        javax.swing.SwingUtilities.invokeLater(()->{try{
            javax.swing.JFileChooser chooser=new javax.swing.JFileChooser();chooser.setDialogTitle("Musician - choose an SF2 soundfont");
            chooser.setFileFilter(new javax.swing.filechooser.FileNameExtensionFilter("SoundFont 2 (*.sf2)","sf2"));chooser.setAcceptAllFileFilterUsed(false);
            if(chooser.showOpenDialog(null)==javax.swing.JFileChooser.APPROVE_OPTION)soundfontAdd(chooser.getSelectedFile().getAbsolutePath());
        }catch(Exception|LinkageError e){WORKER.execute(()->FontsHolder.INSTANCE.message("File picker unavailable. Paste the SF2 path instead."));}});
    }
    public static void soundfontPacks(se.krka.kahlua.vm.KahluaTable registrations){
        if(registrations==null||registrations.len()>32)return;
        record Pack(String mod,String key,String name,String path){}
        List<Pack> list=new ArrayList<>();
        for(int i=1;i<=registrations.len();i++)if(registrations.rawget((double)i) instanceof se.krka.kahlua.vm.KahluaTable t){
            Object m=t.rawget("modId"),k=t.rawget("key"),n=t.rawget("name"),p=t.rawget("path");
            if(m instanceof String mod&&k instanceof String key&&n instanceof String name&&p instanceof String path&&mod.matches("[A-Za-z0-9_.-]{1,128}")&&key.matches("[A-Za-z0-9_.-]{1,64}")&&path.length()<=1024)
                list.add(new Pack(mod,key,SoundfontSetup.clean(name),path));
        }
        WORKER.execute(()->{Map<String,SoundfontSetup.Bank> found=new LinkedHashMap<>();
            for(Pack p:list)try{
                if(!zombie.ZomboidFileSystem.instance.getModIDs().contains(p.mod))continue;
                var mod=zombie.gameStates.ChooseGameInfo.getAvailableModDetails(p.mod);if(mod==null)continue;
                String id="pack:"+p.mod+":"+p.key;
                found.put(id,new SoundfontSetup.Bank(id,p.name,java.nio.file.Path.of(p.path),java.nio.file.Path.of(mod.getCommonDir())));
            }catch(Exception ignored){}
            FontsHolder.INSTANCE.packs(found);
        });
    }
    public static boolean soundfontApply(se.krka.kahlua.vm.KahluaTable rows){
        final SoundfontSetup.Choice[] choices;
        try{choices=SoundfontSetup.choices(rows);}catch(Exception e){WORKER.execute(()->FontsHolder.INSTANCE.message(safe(e)));return false;}
        FONT_PREVIEW.incrementAndGet();ENGINE.preview(null);
        return fontTask("Sounds not applied",(setup,common)->{
            if(TAKE.active()||ENGINE.scoreActive())throw new IllegalStateException("Stop recording and song playback before applying sounds.");
            SoundfontSetup.Resolved mapping=setup.resolve(choices);
            // Test/preload every mapping before changing saved settings or the working engine.
            try(VoiceEngine.Prepared next=new VoiceEngine.Prepared(common,mapping)){
                synchronized(ENGINE){
                    if(TAKE.active()||ENGINE.scoreActive())throw new IllegalStateException("Stop recording and song playback before applying sounds.");
                    setup.save(choices);
                    if(ENGINE.ready())ENGINE.install(next);
                }
            }
            setup.message(mapping.warnings().isEmpty()?"Applied. These sounds are used for live playing, songs and nearby musicians.":"Applied with included-sound fallback: "+String.join("; ",mapping.warnings()));
        });
    }
    public static boolean soundfontPreview(String bank,String preset,int profile){
        if(profile<0||profile>=16)return false;int token=FONT_PREVIEW.incrementAndGet();
        return fontTask("Preview failed",(setup,common)->{
            var chosen=setup.preset(bank,preset);var base=SoundfontSetup.bundled(common);var voices=base.instruments().clone();voices[profile]=chosen.instrument();
            var mapping=new SoundfontSetup.Resolved(voices,"Preset preview",List.of());
            float[] pcm=new float[VoiceEngine.RATE*4];
            try(SoundFontSampler preview=new SoundFontSampler(common,16,128,mapping)){
                preview.profile(0,profile);preview.resetChannel(0);int[] notes=chosen.drums()?new int[]{36,38,42,46}:new int[]{60,64,67,72};
                int previous=-1;
                for(int frame=0;frame<VoiceEngine.RATE*2;frame+=256){
                    int step=frame/(VoiceEngine.RATE/4);
                    if(step<4&&step!=previous){if(previous>=0)preview.noteOff(0,notes[previous]);preview.noteOn(0,notes[step],90);previous=step;}
                    if(frame>=VoiceEngine.RATE&&previous>=0){preview.noteOff(0,notes[previous]);previous=-1;}
                    int count=Math.min(256,VoiceEngine.RATE*2-frame);System.arraycopy(preview.render(count),0,pcm,frame*2,count*2);
                }
            }
            if(token!=FONT_PREVIEW.get())return;
            if(!audioReady()){
                try{closeResources();ENGINE.open(common,setup.resolve());AudioOutput a=new AudioOutput(ENGINE,audioResponse,common,audioDriver);output=a;a.open();status="Audio ready";}
                catch(Exception|LinkageError e){closeResources();throw e;}
            }
            if(token==FONT_PREVIEW.get())ENGINE.preview(pcm);
            setup.message("Preview: "+chosen.name()+" (only you can hear this).");
        });
    }
    public static void soundfontStopPreview(){FONT_PREVIEW.incrementAndGet();ENGINE.preview(null);}
    private static SoundfontSetup.Resolved soundfontMapping(java.nio.file.Path common)throws java.io.IOException {
        SoundfontSetup setup=FontsHolder.INSTANCE;setup.initialize(common);var mapping=setup.resolve();
        if(!mapping.warnings().isEmpty())setup.message(String.join("; ",mapping.warnings()));return mapping;
    }
    private DeadAirMidi() {}
    private static final class LibraryHolder {
        static final MidiLibrary INSTANCE=new MidiLibrary(java.nio.file.Path.of(zombie.ZomboidFileSystem.instance.getCacheDir(),"Lua","DeadAirMidiFolders.txt"));
    }
    public static void libraryRefresh(){LibraryHolder.INSTANCE.refresh();}
    public static void libraryAddFolder(String path){LibraryHolder.INSTANCE.addFolder(path);}
    public static se.krka.kahlua.vm.KahluaTable libraryState(){return LibraryHolder.INSTANCE.state();}
    public static se.krka.kahlua.vm.KahluaTable librarySearch(String query,int source,int offset){return LibraryHolder.INSTANCE.search(query,source,offset);}
    public static int libraryRequest(String id){return LibraryHolder.INSTANCE.request(id);}
    public static int libraryOpenPath(String path){return LibraryHolder.INSTANCE.openPath(path);}
    public static se.krka.kahlua.vm.KahluaTable libraryResult(int token,int group,String mapping){return LibraryHolder.INSTANCE.result(token,group,mapping);}

    public static void midiBackend(int value){ /* Legacy setting; built-in Java MIDI is the only backend. */ }
    public static void refresh() {
        if(!BUSY.compareAndSet(false,true)) return;
        WORKER.execute(()->{
            try {
                List<Input> found=new ArrayList<>();
                for(var input:MidiInputs.scan(MidiInputs.SYSTEM))
                    found.add(new Input("java:"+input.key(),input.info().getName()+" / Java MIDI",2));
                inputs=List.copyOf(found);
                if(!connected()) status=found.isEmpty()?"No MIDI inputs found. Plug in a controller, then Refresh.":"Choose a MIDI input and connect.";
            } catch(Exception|LinkageError e) {inputs=List.of();status="MIDI scan failed: "+safe(e)+". Close other apps using the controller, then refresh.";}
            finally { BUSY.set(false); }
        });
    }
    public static int inputCount() { return inputs.size(); }
    public static String inputName(int index) {
        List<Input> snapshot=inputs;
        return index>=0 && index<snapshot.size() ? snapshot.get(index).name() : "Unavailable input";
    }
    public static String inputKey(int index) {
        List<Input> snapshot=inputs;
        return index>=0 && index<snapshot.size()?snapshot.get(index).key():"";
    }
    public static int inputIndex(String key) {List<Input> snapshot=inputs;for(int i=0;i<snapshot.size();i++)if(snapshot.get(i).key().equals(key))return i;return -1;}
    public static String connectedInput() { return connectedInput; }
    public static String inputStatus() {
        MidiInputReceiver r=receiver;
        return r==null?"MIDI: disconnected":r.status();
    }
    public static String inputRouteStatus() {
        MidiInputReceiver r=receiver;
        return r==null?"Choose a MIDI input in Options > Mods > Musician.":ENGINE.inputRouteStatus(r.lastChannel());
    }
    public static boolean busy() { return BUSY.get(); }
    public static boolean connected() {
        MidiDevice d=device; AudioOutput a=output;MidiInputReceiver r=receiver;
        return r!=null && r.active() && (d!=null && d.isOpen()) && a!=null && a.isRunning();
    }
    public static String status() {
        MidiInputReceiver r=receiver;
        if(r!=null && !r.error().isEmpty())return "MIDI receive error: "+r.error();
        AudioOutput a=output;
        if(a!=null && !a.error().isEmpty()) return a.error();
        if(!ENGINE.error().isEmpty()) return ENGINE.error();
        return status;
    }
    public static long messageCount() { MidiInputReceiver r=receiver;return r==null?0:r.messages(); }
    public static long noteCount() { MidiInputReceiver r=receiver;return r==null?0:r.notes(); }
    public static int lastNote() { MidiInputReceiver r=receiver;return r==null?-1:r.lastNote(); }
    public static int lastVelocity() { MidiInputReceiver r=receiver;return r==null?0:r.lastVelocity(); }
    public static int lastChannel() { MidiInputReceiver r=receiver;return r==null?-1:r.lastChannel(); }
    public static int activeVoices() { return ENGINE.activeVoices(); }
    public static long attackSerial() { return ENGINE.attackSerial(); }
    public static int attackVelocity() { return ENGINE.attackVelocity(); }
    public static se.krka.kahlua.vm.KahluaTable motionState() {
        synchronized(ENGINE) {
        var state=ENGINE.motionState();
        var table=se.krka.kahlua.j2se.J2SEPlatform.getInstance().newTable();
        table.rawset("attack",(double)state.attack()); table.rawset("velocity",(double)state.velocity());
        table.rawset("note",(double)state.note()); table.rawset("held",(double)state.held());
        table.rawset("reset",(double)state.reset());
        table.rawset("resetAttack",(double)state.resetAttack());
        table.rawset("drums",ENGINE.drumState());
        return table;
        }
    }
    public static int animate(zombie.characters.IsoGameCharacter character,String action,String clip,double speed,double phase) {
        return PerformanceAnimation.drive(character,action,clip,speed,phase);
    }
    public static String soundStatus() { return ENGINE.soundStatus(); }
    public static void audioResponse(int value) { audioResponse=Math.max(1,Math.min(3,value)); }
    public static void touchResponse(int value) {SoundFontSampler.touchResponse(value);}
    public static void audioDriver(int value) { audioDriver=4; }
    public static String audioStatus() {
        AudioOutput a=output;
        if(a==null || !a.isRunning()) return "Audio: "+AudioOutput.driverName(audioDriver)+" / "+AudioOutput.responseName(audioResponse)+" (on next connection)";
        return a.description()+(a.response()!=audioResponse || a.driver()!=audioDriver ? "; reconnect to apply" : "");
    }
    public static String guitarStatus() { return soundStatus(); }
    public static boolean hasGuitarSamples() { return ENGINE.ready(); }
    /** Query the game's loaded human clips, not merely the presence of our FBX on disk. */
    public static boolean guitarAnimationReady() {
        return animationReady("Bob_PlayGuitarAcoustic");
    }
    public static boolean animationReady(String name) {
        if(name==null || name.isEmpty()) return false;
        var mesh=zombie.scripting.ScriptManager.instance.getAnimationsMesh("Human");
        if(mesh==null || mesh.modelMesh==null || mesh.modelMesh.skinningData==null) return false;
        var clip=mesh.modelMesh.skinningData.animationClips.get(name);
        return clip!=null && clip.getDuration()>0;
    }
    public static void guitarMode(boolean enabled) { /* Compatibility: all instruments use the built-in SoundFont sampler. */ }
    public static boolean performing() { return ENGINE.isArmed() && connected(); }
    public static void configure(int profile,int transpose,int channel,double gain) { ENGINE.configure(profile,transpose,channel,gain); }
    public static void heartbeat() {
        if(connected()) ENGINE.heartbeat(); else ENGINE.arm(false);
    }
    public static int consumeActivity() { return ENGINE.consumeActivity(); }
    public static void perform(boolean enabled) { ENGINE.arm(enabled && connected()); }
    public static void panic() { FONT_PREVIEW.incrementAndGet();ENGINE.panic(); ENGINE.scoreStop(); ENGINE.liveStopAll(); TAKE.cancel(); }
    public static void liveCapture(boolean enabled){ENGINE.liveCapture(enabled);}
    public static se.krka.kahlua.vm.KahluaTable livePoll(){return ENGINE.livePoll();}
    public static boolean liveReceive(int owner,se.krka.kahlua.vm.KahluaTable packet,double gain){
        try{return ENGINE.liveReceive(owner,packet,gain);}catch(IllegalArgumentException e){ENGINE.liveStop(owner);return false;}
    }
    public static void liveGain(int owner,double gain){ENGINE.liveGain(owner,gain);}
    public static void liveStop(int owner){ENGINE.liveStop(owner);}
    public static void liveStopAll(){ENGINE.liveStopAll();}
    public static se.krka.kahlua.vm.KahluaTable liveState(int owner){return ENGINE.liveState(owner);}
    public static double clock() {return System.nanoTime()/1_000_000.0;}
    public static boolean audioReady(){AudioOutput a=output;return a!=null&&a.isRunning();}
    /** Listening and score preview do not require a physical MIDI controller. */
    public static void openAudio() {
        if(audioReady()||!BUSY.compareAndSet(false,true))return;
        java.nio.file.Path common;
        try{common=commonDirectory();}catch(Exception e){status=safe(e);BUSY.set(false);return;}
        WORKER.execute(()->{try{closeResources();ENGINE.open(common,soundfontMapping(common));AudioOutput a=new AudioOutput(ENGINE,audioResponse,common,audioDriver);output=a;a.open();status="Audio ready";}
            catch(Exception|LinkageError e){closeResources();status="Audio failed: "+safe(e);}finally{BUSY.set(false);}});
    }
    private static java.nio.file.Path commonDirectory(){
        var mod=zombie.gameStates.ChooseGameInfo.getAvailableModDetails("DeadAir");
        if(mod==null)throw new IllegalStateException("Musician mod directory is unavailable");
        return java.nio.file.Path.of(mod.getCommonDir());
    }
    public static String scoreLoad(se.krka.kahlua.vm.KahluaTable parts,int bpm,int ticks,boolean click){
        try{ENGINE.scoreLoad(parts,bpm,ticks,click);return "";}catch(Exception e){ENGINE.scoreStop();return safe(e);}
    }
    public static void scoreStart(double delayMs){ENGINE.scoreStart(delayMs);}
    public static void scoreStop(){ENGINE.scoreStop();}
    public static boolean scoreActive(){return ENGINE.scoreActive();}
    public static double scoreTick(){return ENGINE.scoreTick();}
    public static void scoreHeartbeat(){ENGINE.scoreHeartbeat();}
    public static void scoreMetronome(boolean value){ENGINE.scoreClick(value);}
    public static void scoreGain(int part,double gain){ENGINE.scoreGain(part,gain);}
    public static se.krka.kahlua.vm.KahluaTable scoreState(int part){return ENGINE.scoreState(part);}
    public static void recordStart(int bpm,int ticks,int channel,int countInBeats){
        if(bpm<30||bpm>300||ticks<96||ticks>ScorePlayer.MAX_TICKS)return;
        TAKE.begin(bpm,ticks,channel,System.nanoTime()+(long)(Math.max(0,Math.min(4,countInBeats))*60_000_000_000.0/bpm));
    }
    public static void recordStartOpen(int bpm,int channel,int countInBeats,int capacity){
        if(bpm<30||bpm>300||channel < -1||channel>15||capacity<1||capacity>ScorePlayer.MAX_NOTES)return;
        TAKE.begin(bpm,0,channel,System.nanoTime()+(long)(Math.max(0,Math.min(4,countInBeats))*60_000_000_000.0/bpm),capacity);
    }
    public static se.krka.kahlua.vm.KahluaTable recordNotes(int from){return TAKE.snapshot(from);}
    public static se.krka.kahlua.vm.KahluaTable recordStop(){return TAKE.stop(System.nanoTime());}
    public static boolean recording(){return TAKE.active();}
    public static boolean recordFull(){return TAKE.full();}
    public static void connect(int index) {
        List<Input> snapshot=inputs;
        if(index<0 || index>=snapshot.size() || !BUSY.compareAndSet(false,true)) return;
        java.nio.file.Path commonDirectory;
        try {
            var mod=zombie.gameStates.ChooseGameInfo.getAvailableModDetails("DeadAir");
            if(mod==null) throw new IllegalStateException("Musician mod directory is unavailable");
            commonDirectory=java.nio.file.Path.of(mod.getCommonDir());
        } catch(Exception e) { status="Sampler unavailable: "+safe(e); BUSY.set(false); return; }
        Input selected=snapshot.get(index);
        ENGINE.arm(false); status="Connecting...";
        WORKER.execute(()->{
            try {
                closeResources();
                MidiInputReceiver r=new MidiInputReceiver((command,channel,d1,d2,now)->{
                    TAKE.midi(command,channel,d1,d2,now);
                    ENGINE.midi(command,channel,d1,d2);
                });
                receiver=r;connectedInput=selected.name();
                MidiDevice d=MidiInputs.resolve(MidiInputs.SYSTEM,selected.key().substring(5));
                device=d;d.open();
                Transmitter t=d.getTransmitter();transmitter=t;t.setReceiver(r);
                ENGINE.open(commonDirectory,soundfontMapping(commonDirectory));
                AudioOutput a=new AudioOutput(ENGINE,audioResponse,commonDirectory,audioDriver);output=a;a.open();
                status="MIDI port open: "+connectedInput;
                System.out.println("[Musician] MIDI input: "+connectedInput);
                System.out.println("[Musician] "+a.description());
            } catch(Exception | LinkageError e) { closeResources(); status="Connection failed: "+safe(e); }
            finally { BUSY.set(false); }
        });
    }
    public static void disconnect() {
        FONT_PREVIEW.incrementAndGet();ENGINE.preview(null);
        ENGINE.arm(false);
        // Queued cleanup also cancels a connection that is still opening.
        WORKER.execute(()->{closeResources();status="Disconnected. Choose an input and connect.";});
    }
    private static void closeResources() {
        MidiInputReceiver r=receiver;receiver=null;
        if(r!=null){System.out.println("[Musician] Closing "+connectedInput+": "+r.status());r.close();}
        connectedInput="";TAKE.cancel();ENGINE.scoreStop();ENGINE.arm(false);
        Transmitter t=transmitter; transmitter=null; if(t!=null) t.close();
        MidiDevice d=device; device=null; if(d!=null) d.close();
        AudioOutput a=output; output=null; if(a!=null) a.close();
        ENGINE.close();
    }
    private static String safe(Throwable e) {
        String s=e.getMessage(); return s==null ? e.getClass().getSimpleName() : s.replace('\n',' ').replace('\r',' ');
    }
}
