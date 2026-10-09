package azakaela.deadair;
import musician.gervill.*;
import java.nio.file.*;
import java.util.*;
import javax.sound.midi.*;

/** Synthetic, original SF2 fixture; all playback renders to memory, never hardware. */
public final class SoundfontTest {
    static int checks;
    static void check(boolean ok,String why){checks++;if(!ok)throw new AssertionError(why);}
    static Path fixture(Path path)throws Exception {
        SF2Soundbank bank=new SF2Soundbank();bank.setName("Musician test bank");
        SF2Sample sample=new SF2Sample(bank);sample.setName("Original test tone");sample.setOriginalPitch(60);sample.setSampleRate(48000);
        byte[] pcm=new byte[24046*2];for(int i=0;i<24000;i++){short n=(short)(Math.sin(i*Math.PI*2*440/48000)*7000);pcm[i*2]=(byte)n;pcm[i*2+1]=(byte)(n>>8);}sample.setData(pcm);bank.addResource(sample);
        SF2Layer layer=new SF2Layer(bank);layer.setName("Test tone");SF2LayerRegion lr=new SF2LayerRegion();lr.setSample(sample);layer.getRegions().add(lr);bank.addResource(layer);
        for(boolean drums:new boolean[]{false,true}){SF2Instrument instrument=new SF2Instrument(bank);instrument.setName(drums?"Test kit":"Test lead");instrument.setPatch(new ModelPatch(drums?0:7<<7,12,drums));SF2InstrumentRegion region=new SF2InstrumentRegion();region.setLayer(layer);instrument.getRegions().add(region);bank.addInstrument(instrument);}
        bank.save(path.toFile());return path;
    }
    static double rms(SoundFontSampler s,int c){s.resetChannel(c);s.noteOn(c,60,100);double sum=0;for(int i=0;i<16;i++){float[] a=s.render(256);for(int j=0;j<512;j++)sum+=a[j]*a[j];}return Math.sqrt(sum/8192);}
    public static void main(String[] args)throws Exception {
        Path common=Path.of(args[0]),tmp=Files.createTempDirectory("musician-soundfont-test-");
        Path file=fixture(tmp.resolve("my custom bank.sf2")),config=tmp.resolve("settings.properties");
        SoundfontSetup setup=new SoundfontSetup(config);setup.initialize(common);setup.add("\""+file+"\"");
        String id=(String)setup.state().rawget("added");check(id.startsWith("file:"),"Quoted file path adds stable personal bank");
        var list=SoundfontSetup.presets(SoundfontSetup.readBank(file));check(list.size()==2,"Melodic and percussion presets enumerated");
        var lead=list.stream().filter(p->!p.drums()).findFirst().orElseThrow();var kit=list.stream().filter(SoundfontSetup.Preset::drums).findFirst().orElseThrow();
        check(lead.bank()==7&&lead.program()==12,"Bank/program labels use SF2 numbers");check(kit.key().endsWith(":1"),"Percussion identity preserved independently");
        var choices=SoundfontSetup.defaults();choices[1]=new SoundfontSetup.Choice(id,lead.key());choices[9]=new SoundfontSetup.Choice(id,kit.key());choices[13]=new SoundfontSetup.Choice(id,lead.key());
        setup.save(choices);SoundfontSetup again=new SoundfontSetup(config);again.initialize(common);
        check(Arrays.equals(choices,again.saved()),"Mappings and stable file identity survive restart");check(Files.exists(config.resolveSibling("settings.properties.bak")),"Previous config backed up");
        var mapped=again.resolve();check(mapped.warnings().isEmpty(),"One-instrument custom bank needs no missing GM presets");
        check(mapped.instruments()[1].getName().equals("Test lead")&&mapped.instruments()[0].getName().contains("Piano"),"Per-instrument mapping and included fallback coexist");
        check(mapped.instruments()[9].getName().equals("Test kit")&&mapped.instruments()[13].getName().equals("Test lead"),"Kit and individual drum mappings remain independent");
        try(SoundFontSampler s=new SoundFontSampler(common,128,256,mapped)){
            for(int c:new int[]{0,9,15,31,127}){s.profile(c,1);check(rms(s,c)>.005,"Custom patch audible on channel "+c);s.silence(c);s.render(256);s.render(256);}
            s.profile(9,9);check(rms(s,9)>.005,"Custom percussion patch audible on drum channel");
        }
        try(VoiceEngine e=new VoiceEngine()){
            e.open(common,mapped);e.configure(1,0,-1,.3);e.arm(true);e.midi(0x90,0,60,100);byte[] audio=new byte[4096*4];e.render(audio,4096);check(Arrays.stream(toInts(audio)).anyMatch(v->v!=0),"Live engine uses custom mappings");
            e.arm(false);e.liveCapture(true);long attack=e.attackSerial();float[] audition=new float[512];Arrays.fill(audition,.1f);e.preview(audition);e.render(new byte[1024],256);
            Object events=e.livePoll().rawget("events");check(e.attackSerial()==attack&&e.consumeActivity()==0&&(events==null||events.equals("")),"Private audition has no animation, world-noise or live-network note event");
            try(VoiceEngine.Prepared next=new VoiceEngine.Prepared(common,SoundfontSetup.bundled(common))){e.install(next);check(e.ready()&&!e.isArmed(),"Prepared mapping switch silences held notes and keeps engine usable");}
        }
        try(ScorePlayer score=new ScorePlayer(common,mapped)){
            var parts=MidiTake.table();var part=MidiTake.table();var notes=MidiTake.table();var note=MidiTake.table();note.rawset("n",60.0);note.rawset("t",0.0);note.rawset("d",96.0);note.rawset("v",100.0);notes.rawset(1.0,note);part.rawset("profile",1.0);part.rawset("notes",notes);parts.rawset(1.0,part);score.load(parts,120,384,false);long now=System.nanoTime();score.start(now,now);check(Arrays.stream(toInts(score.render(256,now))).anyMatch(v->v!=0),"Written score custom preset renders");
        }
        try(LiveMidiPlayer live=new LiveMidiPlayer(common,mapped)){
            long now=System.nanoTime();live.accept(LivePacket.read(1,LiveMidiTest.packet(1,1,1,0,"0,144,60,100;","144,60,100;",false)),1,now);LiveMidiTest.render(live,LiveMidiPlayer.BUFFER_FRAMES,now);check(LiveMidiTest.render(live,4096,now)>.005,"Remote listener uses local custom preset");
        }
        var missing=choices.clone();missing[2]=new SoundfontSetup.Choice("pack:disabled:main",lead.key());missing[3]=new SoundfontSetup.Choice(id,"0:127:0");var fallback=again.resolve(missing);
        check(fallback.warnings().size()==2,"Disabled pack and missing preset have independent fallbacks");check(fallback.instruments()[1].getName().equals("Test lead"),"One broken assignment cannot erase working assignments");
        again.packs(Map.of("pack:Fixture:main",new SoundfontSetup.Bank("pack:Fixture:main","Fixture pack",Path.of(file.getFileName().toString()),tmp)));
        missing[2]=new SoundfontSetup.Choice("pack:Fixture:main",lead.key());missing[3]=new SoundfontSetup.Choice("","");check(again.resolve(missing).warnings().isEmpty(),"Enabled SF2 addon resolves under mod common directory");
        again.packs(Map.of());check(again.resolve(missing).warnings().size()==1,"Disabling addon restores included sound without discarding mapping");
        try{SoundfontSetup.safePackPath(tmp,"../escape.sf2");throw new AssertionError("Pack escaped root");}catch(java.io.IOException expected){checks++;}
        try{SoundfontSetup.safePackPath(tmp,file.toAbsolutePath().toString());throw new AssertionError("Absolute pack path accepted");}catch(java.io.IOException expected){checks++;}
        Path bad=tmp.resolve("bad.sf2");Files.writeString(bad,"not a valid soundfont at all");try{setup.add(bad.toString());throw new AssertionError("Invalid SF2 accepted");}catch(java.io.IOException expected){checks++;}
        Files.move(file,tmp.resolve("moved.sf2"));check(again.resolve().warnings().size()==3,"Missing personal bank falls back on all three mapped instruments");
        check(again.saved()[1].bank().equals(id),"Unavailable file does not overwrite stored mapping");
        Path corrupt=tmp.resolve("corrupt.properties");Files.writeString(corrupt,"bad=\\uNOT!");SoundfontSetup recovered=new SoundfontSetup(corrupt);recovered.initialize(common);
        check(recovered.resolve().warnings().isEmpty()&&Files.readString(corrupt).equals("bad=\\uNOT!"),"Corrupt settings use included sounds without rewriting original file");
        System.out.println("PASS: "+checks+" custom soundfont persistence, mapping, channel, score, remote, privacy, fallback and addon-boundary checks; no hardware opened");
    }
    static int[] toInts(byte[] a){int[] b=new int[a.length];for(int i=0;i<a.length;i++)b[i]=a[i];return b;}
    static int[] toInts(float[] a){int[] b=new int[a.length];for(int i=0;i<a.length;i++)b[i]=(int)(a[i]*1000000);return b;}
}
