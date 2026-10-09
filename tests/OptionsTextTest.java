package azakaela.deadair;

import java.nio.file.*;
import java.util.regex.*;

/** Exercise the same actual game translator used when MainOptions builds our controls. */
public final class OptionsTextTest {
    public static void main(String[] args)throws Exception{
        String lua=Files.readString(Path.of(args[0]));
        Matcher labels=Pattern.compile("options:add(?:Slider|ComboBox|Button|TickBox|KeyBind)\\(\"[^\"]+\",\"([^\"]+)\"").matcher(lua);
        int count=0;
        while(labels.find()){
            String label=labels.group(1);
            // Translator catches bad formats, then formats the same label again in its logger.
            // Offline logging can be disabled, hiding the exception seen in a running game.
            try{label.formatted();zombie.core.Translator.getText(label);}
            catch(RuntimeException e){throw new AssertionError("Mod Options label failed actual game translation: "+label,e);}
            count++;
        }
        if(count<10)throw new AssertionError("Missing expected Mod Options labels");
        System.out.println("PASS: "+count+" Mod Options labels through actual game Translator");
    }
}
