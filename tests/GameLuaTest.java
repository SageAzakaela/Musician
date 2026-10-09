package azakaela.deadair;
import java.nio.file.*;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.vm.*;
import se.krka.kahlua.luaj.compiler.LuaCompiler;

/** Runs the editor/network Lua fixtures in PZ's actual VM, with UI/audio doubles. */
public final class GameLuaTest {
    public static void main(String[] args) throws Exception {
        var platform=J2SEPlatform.getInstance();KahluaTable env=null;KahluaThread thread=null;
        Path folder=Path.of(args[0]);int count=0;
        for(String line:Files.readAllLines(folder.resolve("manifest.tsv"))) {
            if(line.equals("reset")){
                env=platform.newEnvironment();thread=new KahluaThread(platform,env);
                var owner=KahluaThread.class.getDeclaredField("debugOwnerThread");owner.setAccessible(true);owner.set(thread,Thread.currentThread());
                continue;
            }
            String[] row=line.split("\t",3);
            try {
                var closure=LuaCompiler.loadstring(Files.readString(folder.resolve(row[1])),row[2],env);
                if(row[0].equals("run"))thread.call(closure,null,null,null);
                count++;
            }catch(Throwable error){System.err.println("FAIL: "+row[2]+" ("+row[1]+")");throw error;}
        }
        System.out.println("PASS: "+count+" Lua chunks in the installed game's Kahlua VM; UI/audio/network remain simulated; no devices or saves opened.");
    }
}
