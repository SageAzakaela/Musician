package azakaela.deadair;

import java.nio.ByteBuffer;
import java.nio.file.*;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.vm.*;
import se.krka.kahlua.luaj.compiler.LuaCompiler;
import zombie.core.network.ByteBufferReader;
import zombie.core.network.ByteBufferWriter;
import zombie.network.TableNetworkUtils;

/** Real game serialization of a full composition; does not open or modify a save. */
public final class SongDataTest {
 public static void main(String[] args)throws Exception {
  long began=System.nanoTime();
  var platform=J2SEPlatform.getInstance();var env=platform.newEnvironment();var thread=new KahluaThread(platform,env);
  thread.call(LuaCompiler.loadstring("require=function()end","test prelude",env),null,null,null);
  Path shared=Path.of(args[0]).resolve("42/media/lua/shared");
  for(String name:new String[]{"DeadAirScore","DeadAirComposition"})
   thread.call(LuaCompiler.loadstring(Files.readString(shared.resolve(name+".lua")),name,env),null,null,null);
  String fixture="local C,S=DeadAirComposition,DeadAirScore; local notes={}; for i=1,3072 do notes[i]={n=127,t=90000000+i,d=10000000,v=127}end; " +
   "local song={version=3,song=string.rep('s',80),title=string.rep('T',64),bpm=300,bars=S.MAX_BARS,revision=100000000,active=string.rep('p',79)..'8',parts={}}; " +
   "for i=1,8 do local clips={};for j=1,127 do clips[j]={name=string.rep('C',48),start=(j-1)*1000,length=1000,loopLength=1000}end; " +
   "clips[128]={name=string.rep('C',48),start=90000000,length=S.MAX_BARS*384-90000000}; " +
   "song.parts[i]={part=string.rep('p',79)..i,partName=string.rep('P',48),profile=i,notes=S.encode(notes),clips=clips,mute=false,solo=false}end; " +
   "song=assert(C.validate(song)); packet={mode='saveSong',item=123,revision=100000000,composition=song}; " +
   "itemData={DeadAirComposition=song}";
  thread.call(LuaCompiler.loadstring(fixture,"maximum composition",env),null,null,null);
  // The real multiplayer UdpConnection allocates 1,000,000 bytes for outgoing packets.
  ByteBuffer bytes=ByteBuffer.allocate(1_000_000);
  TableNetworkUtils.save((KahluaTable)env.rawget("packet"),new ByteBufferWriter(bytes));int networkBytes=bytes.position();bytes.flip();
  KahluaTable restored=platform.newTable();TableNetworkUtils.load(restored,new ByteBufferReader(bytes));env.rawset("restored",restored);
  thread.call(LuaCompiler.loadstring("local S=DeadAirScore;local s=assert(DeadAirComposition.validate(restored.composition)); assert(#s.parts==8 and s.active==string.rep('p',79)..'8'); assert(#S.decode(s.parts[8].notes,S.MAX_BARS*384)==3072); assert(S.equal(s.parts[1].notes,packet.composition.parts[1].notes));assert(#s.parts[8].clips==128 and s.parts[8].clips[1].loopLength==1000)","network round trip",env),null,null,null);
  bytes.clear();((KahluaTable)env.rawget("itemData")).save(bytes);int itemBytes=bytes.position();bytes.flip();
  restored=platform.newTable();restored.load(bytes,249);env.rawset("restored",restored);
  thread.call(LuaCompiler.loadstring("local s=assert(DeadAirComposition.validate(restored.DeadAirComposition)); assert(#s.parts==8 and s.active==string.rep('p',79)..'8'); assert(DeadAirScore.equal(s.parts[8].notes,itemData.DeadAirComposition.parts[8].notes) and not restored.DeadAirScore and s.parts[8].clips[1].loopLength==1000);local extra=DeadAirScore.decode(s.parts[1].notes,DeadAirScore.MAX_BARS*384);extra[#extra+1]={n=60,t=0,d=1,v=1};s.parts[1].notes=DeadAirScore.encode(extra);assert(not DeadAirComposition.validate(s))","item mod data round trip",env),null,null,null);
  if(networkBytes>950000||itemBytes>950000)throw new AssertionError("Insufficient packet headroom");
  System.out.println("PASS: real game Kahlua, network ("+networkBytes+" bytes) and item mod-data ("+itemBytes+" bytes): 24,576 notes, maximum timestamps/durations/names and 1,024 clips with loop metadata round-trip below 1 MB; oversized song rejected; no save or connection opened");
  System.out.println("SongData elapsed: "+(System.nanoTime()-began)/1_000_000+" ms");
  long loopBegan=System.nanoTime();
  thread.call(LuaCompiler.loadstring("local C,S=DeadAirComposition,DeadAirScore; local p={clips={{name='Loop',start=0,length=64*384,loopLength=384}}};local notes={};for i=0,15 do notes[#notes+1]={n=60+i%5,t=i*24,d=24,v=90}end;local expanded=assert(C.expandLoops(p,notes,S.MAX_NOTES));assert(#expanded==1024);expanded[1].n=54;expanded=assert(C.expandLoops(p,expanded,S.MAX_NOTES));for i=0,63 do assert(expanded[1+i*16].n==54)end;loopSong=assert(C.validate({version=3,title='Loop test',bpm=120,bars=64,parts={{part='loop',partName='Guitar',profile=1,notes=S.encode(expanded),clips=p.clips}}}))","loop generation and editing",env),null,null,null);
  bytes.clear();((KahluaTable)env.rawget("loopSong")).save(bytes);bytes.flip();
  restored=platform.newTable();restored.load(bytes,249);env.rawset("restoredLoop",restored);
  thread.call(LuaCompiler.loadstring("local C,S=DeadAirComposition,DeadAirScore;local song=assert(C.validate(restoredLoop));assert(song.parts[1].clips[1].loopLength==384 and #S.native(C.score(song,1),0).notes==1024)","saved loop playback",env),null,null,null);
  System.out.println("PASS: real Kahlua 64-bar loop: 1,024 notes, source edit updates every repeat, item round trip and native score: "+(System.nanoTime()-loopBegan)/1_000_000+" ms");
 }
}
