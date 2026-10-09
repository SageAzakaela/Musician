package azakaela.deadair;

import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.vm.*;
import se.krka.kahlua.luaj.compiler.LuaCompiler;
import se.krka.kahlua.converter.*;
import se.krka.kahlua.integration.expose.LuaJavaClassExposer;
import java.lang.reflect.*;

/** Exercises the shipped Kahlua conversion and global-class method calls, without booting a save. */
public final class BridgeTest {
    public static void main(String[] args) throws Exception {
        J2SEPlatform platform=J2SEPlatform.getInstance();
        KahluaTable env=platform.newEnvironment();
        KahluaConverterManager converters=new KahluaConverterManager();
        zombie.Lua.KahluaNumberConverter.install(converters);
        LuaJavaClassExposer exposer=new LuaJavaClassExposer(converters,platform,env);
        KahluaTable api=platform.newTable();env.rawset("DeadAirMidi",api);
        for(Method method:DeadAirMidi.class.getDeclaredMethods())
            if(Modifier.isStatic(method.getModifiers()) && Modifier.isPublic(method.getModifiers()))
                exposer.exposeGlobalClassFunction(api,DeadAirMidi.class,method,method.getName());
        KahluaThread thread=new KahluaThread(platform,env);
        String checks="assert(not DeadAirMidi.connected()); assert(not DeadAirMidi.performing()); " +
            "DeadAirMidi.configure(0, -12, -1, 0.3); DeadAirMidi.perform(true); " +
            "assert(not DeadAirMidi.performing()); DeadAirMidi.heartbeat(); DeadAirMidi.panic(); " +
            "assert(DeadAirMidi.activeVoices()==0); assert(DeadAirMidi.consumeActivity()==0); " +
            "assert(string.find(DeadAirMidi.soundStatus(),'Gervill')); assert(type(DeadAirMidi.status())=='string'); assert(DeadAirMidi.inputCount()==0); " +
            "assert(DeadAirMidi.noteCount()==0 and DeadAirMidi.lastChannel()==-1); assert(DeadAirMidi.inputKey(-1)=='' and DeadAirMidi.inputIndex('missing')==-1); assert(DeadAirMidi.connectedInput()==''); assert(type(DeadAirMidi.inputStatus())=='string' and type(DeadAirMidi.inputRouteStatus())=='string'); " +
            "assert(DeadAirMidi.inputName(-1)=='Unavailable input'); " +
            "assert(DeadAirMidi.messageCount()==0 and DeadAirMidi.lastNote()==-1); " +
            "assert(DeadAirMidi.attackSerial()==0); assert(DeadAirMidi.attackVelocity()==0); " +
            "assert(not DeadAirMidi.guitarAnimationReady()); " +
            "assert(not DeadAirMidi.animationReady('Bob_PlayFluteExperiencedA')); assert(not DeadAirMidi.animationReady('')); " +
            "DeadAirMidi.guitarMode(true); DeadAirMidi.guitarMode(false); assert(type(DeadAirMidi.guitarStatus())=='string'); " +
            "DeadAirMidi.audioResponse(2); assert(string.find(DeadAirMidi.audioStatus(),'Balanced')); DeadAirMidi.audioResponse(1); " +
            "DeadAirMidi.audioDriver(3); assert(string.find(DeadAirMidi.audioStatus(),'Java Sound')); DeadAirMidi.audioDriver(1); " +
            "DeadAirMidi.touchResponse(2); DeadAirMidi.touchResponse(1); " +
            "assert(type(DeadAirMidi.motionState().drums)=='table'); assert(DeadAirMidi.motionState().held==0 and DeadAirMidi.motionState().attack==0); " +
            "assert(DeadAirMidi.animate(nil,'DeadAirGuitar','Bob_PlayGuitarAcoustic',1,-1)==0); " +
            "assert(type(DeadAirMidi.clock())=='number'); assert(not DeadAirMidi.audioReady()); " +
            "DeadAirMidi.liveCapture(false); assert(type(DeadAirMidi.livePoll())=='table'); assert(not DeadAirMidi.liveReceive(1,{},1)); " +
            "DeadAirMidi.liveGain(1,0.5); DeadAirMidi.liveStop(1); DeadAirMidi.liveStopAll(); assert(type(DeadAirMidi.liveState(1))=='table'); " +
            "assert(type(DeadAirMidi.scoreLoad({{profile=0,notes={{n=60,t=0,d=12,v=100}}}},120,384,false))=='string'); " +
            "DeadAirMidi.scoreStart(100); DeadAirMidi.scoreHeartbeat(); DeadAirMidi.scoreGain(0,0.5); DeadAirMidi.scoreMetronome(true); " +
            "assert(not DeadAirMidi.scoreActive()); assert(DeadAirMidi.scoreTick()==0); assert(type(DeadAirMidi.scoreState(0))=='table'); DeadAirMidi.scoreStop(); " +
            "DeadAirMidi.recordStart(120,384,-1,4); assert(DeadAirMidi.recording()); assert(type(DeadAirMidi.recordStop())=='table'); assert(not DeadAirMidi.recording()); " +
            "DeadAirMidi.recordStartOpen(120,-1,0,2048); assert(DeadAirMidi.recording()); assert(type(DeadAirMidi.recordNotes(0))=='table'); DeadAirMidi.recordStop(); " +
            "assert(type(DeadAirMidi.libraryState().roots)=='table'); assert(type(DeadAirMidi.librarySearch('test',0,0).rows)=='table'); " +
            "local token=DeadAirMidi.libraryOpenPath('invalid.txt'); assert(DeadAirMidi.libraryResult(token,-1,'auto').state=='error'); " +
            "local stale=DeadAirMidi.libraryRequest('missing'); assert(DeadAirMidi.libraryResult(stale,-1,'auto').state=='error'); " +
            "assert(type(DeadAirMidi.soundfontState().mappings)=='table'); assert(#DeadAirMidi.soundfontState().mappings==16); DeadAirMidi.soundfontStopPreview(); " +
            "DeadAirMidi.midiBackend(1); DeadAirMidi.midiBackend(2); DeadAirMidi.connect(-1); DeadAirMidi.disconnect();";
        thread.call(LuaCompiler.loadstring(checks,"Dead Air bridge verification",env),null,null,null);
        System.out.println("PASS: actual game Kahlua static-method bridge and Lua-to-Java numeric conversions");
    }
}
