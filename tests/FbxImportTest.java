package azakaela.deadair;
import java.nio.file.*;
import java.util.*;
import jassimp.*;
import zombie.core.skinnedmodel.model.jassimp.JAssImpImporter;
import zombie.core.skinnedmodel.model.jassimp.ProcessedAiScene;
import zombie.core.skinnedmodel.model.jassimp.ProcessedAiSceneParams;
import zombie.core.skinnedmodel.model.AnimationAsset;
import zombie.asset.AssetPath;

/** Load authored files through the game's real native FBX importer, without a renderer. */
public final class FbxImportTest {
 static void check(boolean b,String message){if(!b)throw new AssertionError(message);}
 public static void main(String[] args)throws Exception {
  JAssImpImporter.Init();Path root=Path.of(args[0]).resolve("common/media/anims_X");
  for(String clip:new String[]{"Bob_PlayGuitarExperiencedA","DeadAirDrumReady","DeadAirDrumL","DeadAirDrumR","DeadAirPedalR","DeadAirPedalL","DeadAirForkTap"}) {
   AiScene scene=Jassimp.importFile(root.resolve(clip+".fbx").toString());
   check(scene.getAnimations().size()==1,"One animation in "+clip);
   AiAnimation a=scene.getAnimations().get(0);
   Set<String> names=new HashSet<>();
   for(AiNodeAnim c:a.getChannels()) {
    names.add(c.getNodeName());
    for(int k=0;k<c.getNumPosKeys();k++)check(Float.isFinite(c.getPosKeyX(k))&&Float.isFinite(c.getPosKeyY(k))&&Float.isFinite(c.getPosKeyZ(k)),"Finite translation");
    for(int k=0;k<c.getNumRotKeys();k++) {
     double norm=Math.pow(c.getRotKeyW(k),2)+Math.pow(c.getRotKeyX(k),2)+Math.pow(c.getRotKeyY(k),2)+Math.pow(c.getRotKeyZ(k),2);
     check(Math.abs(norm-1)<.01,"Normalized rotation in "+clip+"/"+c.getNodeName());
    }
   }
   for(String bone:new String[]{"Bip01","Bip01_Pelvis","Bip01_L_Hand","Bip01_R_Hand","Bip01_Prop1","Bip01_Prop2","Bip01_R_Foot","Bip01_L_Foot"})check(names.contains(bone),"Missing bone "+bone+" in "+clip);
   double duration=a.getDuration()/a.getTicksPerSecond();
   System.out.println(clip+": "+duration+" seconds, "+names.size()+" bone channels");
   if(clip.startsWith("DeadAir"))check(Math.abs(duration-(clip.equals("DeadAirDrumL")||clip.equals("DeadAirDrumR")?8:1))<.04,"Expected phase-addressable duration");
   // Raw Assimp parsing alone accepts armature-only FBX. PZ additionally requires
   // a skinned mesh, even in AnimationOnly mode, or applyToAnimation dereferences null.
   var params=ProcessedAiSceneParams.create();params.scene=scene;
   params.mode=JAssImpImporter.LoadMode.AnimationOnly;params.animBonesScaleModifier=1;
   var processed=ProcessedAiScene.process(params);
   var asset=new AnimationAsset(new AssetPath(clip),null,new AnimationAsset.AnimationAssetParams());
   processed.applyToAnimation(asset);
   System.out.println("Registered clip names: "+asset.animationClips.keySet());
   check(asset.animationClips.containsKey(clip),"Game must register the exact action lookup name "+clip+", not Scene or another export take name");
   check(asset.animationClips!=null&&!asset.animationClips.isEmpty(),"PZ animation asset populated: "+clip);
   for(var animation:asset.animationClips.values())check(animation.getKeyframes().length>0,"Processed bone keyframes available: "+clip);
   check(scene.getMeshes().stream().anyMatch(AiMesh::hasBones),"PZ needs a bound mesh for "+clip);
   System.out.println("PASS: PZ AnimationOnly skeleton processing and applyToAnimation: "+clip);
  }
  System.out.println("PASS: native FBX parsing AND PZ skeleton-to-animation asset loading, bone coverage and durations (no visual render)");
 }
}
