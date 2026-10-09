package azakaela.deadair;

import musician.gervill.*;
import javax.sound.midi.*;
import javax.sound.sampled.*;
import java.nio.*;
import java.nio.file.*;
import java.io.IOException;
import java.util.*;

/** Bundled Java SF2 renderer. Opens a memory stream only, never a device or default sound bank. */
final class SoundFontSampler implements AutoCloseable {
    static final int BLOCK=256, CONTROL_FRAMES=64;
    private static volatile int touch=1;
    static void touchResponse(int value){touch=Math.max(1,Math.min(2,value));}
    static int playedVelocity(int value){return value<=0?0:touch==2?(int)Math.round(Math.sqrt(value/127.0)*127):value;}
    private static SF2Soundbank cachedBank;
    private static Path cachedPath;
    private final SoftSynthesizer synth=new SoftSynthesizer();
    private AudioInputStream stream;
    private MidiChannel[] channels;
    private SF2Soundbank bank;
    private final Map<String,Integer> patches=new HashMap<>();
    private final byte[] bytes=new byte[BLOCK*8];
    private final FloatBuffer floats=ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN).asFloatBuffer();
    private final float[] pcm=new float[BLOCK*2];
    final String version="Gervill / Java SF2";
    final String summary;
    private final int[] profileBanks=new int[16];

    SoundFontSampler(Path common){this(common,16,128);}
    SoundFontSampler(Path common,int channelCount,int polyphony){this(common,channelCount,polyphony,null);}
    SoundFontSampler(Path common,int channelCount,int polyphony,SoundfontSetup.Resolved mapping){
        summary=mapping==null?"GeneralUser GS":mapping.summary();
        Path path=common.resolve("media/soundfonts/GeneralUser-GS.sf2").toAbsolutePath().normalize();
        if(!Files.isRegularFile(path))throw new IllegalStateException("Missing sound bank: "+path);
        try {
            bank=bank(path);
            Map<String,Object> config=new HashMap<>();
            config.put("load default soundbank",false);
            config.put("midi channels",channelCount);config.put("max polyphony",polyphony);
            config.put("control rate",(float)VoiceEngine.RATE/CONTROL_FRAMES);
            config.put("interpolation","cubic");config.put("reverb",false);config.put("chorus",false);
            config.put("jitter correction",false);
            config.put("auto gain control",false); // The engine limits the final combined mix once.
            AudioFormat format=new AudioFormat(AudioFormat.Encoding.PCM_FLOAT,VoiceEngine.RATE,32,2,8,VoiceEngine.RATE,false);
            stream=synth.openStream(format,config);channels=synth.getChannels();
            if(channels.length!=channelCount)throw new IllegalStateException("Sampler channel allocation failed");
            // Preload on the device worker; instrument switches never load files.
            for(int p=0;p<VoiceEngine.PROFILES.length;p++){
                if(mapping==null){presetChannel(0,VoiceEngine.bank(p),VoiceEngine.program(p),VoiceEngine.drums(p));profileBanks[p]=patches.get(VoiceEngine.bank(p)+":"+VoiceEngine.program(p)+":"+VoiceEngine.drums(p));}
                else{
                    int target=(121<<7)+32+p; // GM2 melodic-bank addressing also works on channel 10.
                    if(!synth.loadInstrument(new ModelMappedInstrument(mapping.instruments()[p],new Patch(target,0))))throw new IllegalStateException("Could not load "+VoiceEngine.PROFILES[p]);
                    profileBanks[p]=target;
                }
            }
        } catch(Exception|LinkageError e){close();throw new IllegalStateException("Sound bank could not open: "+e.getMessage(),e);}
    }
    private static synchronized SF2Soundbank bank(Path path)throws Exception{
        if(cachedBank==null || !path.equals(cachedPath)){
            cachedBank=new SF2Soundbank(path.toFile());cachedPath=path;
        }
        return cachedBank;
    }
    void profile(int channel,int profile){channels[channel].programChange(profileBanks[profile],0);}
    void profile(int profile){for(int c=0;c<16;c++)profile(c,profile);}
    void preset(int bank,int program,boolean drum){for(int c=0;c<16;c++)presetChannel(c,bank,program,drum);}
    void presetChannel(int c,int bankNumber,int program,boolean drum){
        String key=bankNumber+":"+program+":"+drum;
        Integer mapped=patches.get(key);
        if(mapped==null){
            ModelPatch patch=new ModelPatch(drum?0:bankNumber<<7,program,drum);
            Instrument instrument=bank.getInstrument(patch);
            if(!(instrument instanceof ModelInstrument model))throw new IllegalStateException("Missing instrument preset: "+key);
            // Explicit GM2 bank remapping works on every channel, including channel 10 and >16.
            mapped=(121<<7)+patches.size();
            if(!synth.loadInstrument(new ModelMappedInstrument(model,new Patch(mapped,0))))
                throw new IllegalStateException("Could not load instrument preset: "+key);
            patches.put(key,mapped);
        }
        channels[c].programChange(mapped,0);
    }
    boolean noteOn(int c,int n,int v){channels[c].noteOn(n,playedVelocity(v));return true;}
    void noteOff(int c,int n){channels[c].noteOff(n);}
    void cc(int c,int n,int v){channels[c].controlChange(n,v);}
    void bend(int c,int v){channels[c].setPitchBend(v);}
    int voices(){return synth.getActiveVoiceCount();}
    void silence(int c){channels[c].allSoundOff();}
    void resetChannel(int c){
        channels[c].resetAllControllers();cc(c,64,0);cc(c,7,127);cc(c,11,127);cc(c,1,0);
        cc(c,101,0);cc(c,100,0);cc(c,6,2);cc(c,38,0);cc(c,101,127);cc(c,100,127);bend(c,8192);
    }
    float[] render(int frames){
        if(frames<0 || frames>BLOCK)throw new IllegalArgumentException("Invalid sampler block length");
        if(stream==null)throw new IllegalStateException("Sampler is closed");
        try{
            int needed=frames*8,at=0;
            while(at<needed){int n=stream.read(bytes,at,needed-at);if(n<=0)throw new IOException("Sampler stream ended");at+=n;}
            for(int i=0;i<frames*2;i++)pcm[i]=floats.get(i);
            return pcm;
        }catch(IOException e){throw new IllegalStateException("SoundFont render failed",e);}
    }
    public void close(){
        if(stream!=null){try{stream.close();}catch(IOException ignored){}stream=null;}
        synth.close();channels=null;bank=null;patches.clear();
    }
}
