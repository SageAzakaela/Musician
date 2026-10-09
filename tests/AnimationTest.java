package azakaela.deadair;

import zombie.core.skinnedmodel.advancedanimation.*;
import java.nio.file.*;
import java.util.List;
import zombie.core.skinnedmodel.animation.*;
import org.lwjgl.util.vector.Vector3f;
import org.lwjgl.util.vector.Quaternion;

public final class AnimationTest {
    public static void main(String[] args) throws Exception {
        Path root=Path.of(args[0]);
        // 42.21 loadHumanAnimations lists common first and returns on null before scanning 42.
        var common=root.resolve("common/media/anims_X").toFile().listFiles();
        if(common==null) throw new AssertionError("Missing common animation directory: game skips version animations");
        Path clip=root.resolve("common/media/anims_X/Bob_PlayGuitarAcoustic.fbx");
        if(!Files.isRegularFile(clip)) throw new AssertionError("Guitar FBX must be in common/media/anims_X");
        if(Files.exists(root.resolve("42/media/anims_X/Bob_PlayGuitarAcoustic.fbx"))) throw new AssertionError("Stale version-folder clip would duplicate the common clip");
        AnimNode node=AnimNode.Parse(root.resolve("42/media/AnimSets/player/actions/DeadAirGuitar.xml").toString());
        if(node==null) throw new AssertionError("Animation node failed to parse");
        if(!"DeadAirGuitar".equals(node.name) || !"Bob_PlayGuitarAcoustic".equals(node.animName)) throw new AssertionError("Wrong animation binding");
        AnimationVariableSource variables=new AnimationVariableSource();
        variables.setVariable("DeadAirGuitarSpeed",0f);
        if(node.getSpeedScale(variables)!=0) throw new AssertionError("Idle pose must freeze");
        variables.setVariable("DeadAirGuitarSpeed",1.25f);
        if(node.getSpeedScale(variables)!=1.25f) throw new AssertionError("MIDI-driven speed variable not bound");
        int count=0;
        try(var paths=Files.list(root.resolve("42/media/AnimSets/player/actions"))) {
            for(Path path:paths.filter(p->p.toString().endsWith(".xml")).toList()) {
                AnimNode parsed=AnimNode.Parse(path.toString());
                if(parsed==null) throw new AssertionError("Bad animation node: "+path);
                if(parsed.name.equals("DeadAirDrum") || parsed.name.equals("DeadAirKick") || parsed.name.equals("DeadAirTuningFork"))
                    check(parsed.events.isEmpty() && !parsed.useDeferredMovement && !parsed.useDeferedRotation,"Percussion must not execute attacks, sounds or root motion");
                variables.setVariable("PerformingAction",parsed.name.startsWith("DeadAirPercussion_")?"DeadAirPercussion":parsed.name);
                if(!parsed.checkConditions(variables)) throw new AssertionError("Action condition does not match: "+path);
                variables.setVariable("PerformingAction","UnrelatedAction");
                if(parsed.checkConditions(variables)) throw new AssertionError("Action overrides unrelated activity: "+path);
                String speed=parsed.name.equals("DeadAirGuitar")?"DeadAirGuitarSpeed":"DeadAirPlayingSpeed";
                variables.setVariable(speed,0f);
                if(parsed.getSpeedScale(variables)!=0f) throw new AssertionError("Cannot hold idle pose: "+path);
                variables.setVariable(speed,1.25f);
                if(parsed.getSpeedScale(variables)!=1.25f) throw new AssertionError("No MIDI speed binding: "+path);
                boolean exists=Files.exists(root.resolve("common/media/anims_X/"+parsed.animName+".fbx"))
                    ||Files.exists(root.resolve("common/media/anims_X/"+parsed.animName+".x"))
                    ||Files.exists(Path.of("media/anims_X/Bob/"+parsed.animName+".x"));
                if(!exists) throw new AssertionError("Missing animation file: "+parsed.animName);
                count++;
            }
        }
        if(count!=22) throw new AssertionError("Expected 22 instrument/piano/layer action nodes, got "+count);
        percussionLayers(root,variables);
        liveTrackRegression(node,variables);
        System.out.println("PASS: "+count+" game-parsed animation nodes, isolated action conditions, clip file coverage and variable speed (no visual render)");
    }
    static void percussionLayers(Path root,AnimationVariableSource variables) {
        AnimState state=new AnimState();state.name="actions";
        AnimLayer layer=AnimLayer.alloc(null,null);
        for(String limb:new String[]{"rest","left","right","footR","footL"}) {
            AnimNode node=AnimNode.Parse(root.resolve("42/media/AnimSets/player/actions/DeadAirPercussion_"+limb+".xml").toString());
            state.addNode(node);
            check(node.events.isEmpty()&&!node.useDeferredMovement&&!node.useDeferedRotation&&!node.syncTrackingEnabled,"Drum layers have no combat events, root motion or phase synchronization");
            AnimationTrack track=track(node.animName);
            LiveAnimNode live=LiveAnimNode.alloc(layer,node);live.setActive(true);live.addMainTrack(track);layer.getLiveAnimNodes().add(live);
        }
        variables.setVariable("PerformingAction","DeadAirPercussion");
        check(state.getAnimNodes(variables,new java.util.ArrayList<>()).size()==5,"Real game selects all five matching limb layers together");
        int i=0;
        for(LiveAnimNode live:layer.getLiveAnimNodes()) {
            AnimNode node=state.nodes.get(i++);
            check(PerformanceAnimation.driveLayer(layer,"DeadAirPercussion",node.animName,0,.4)==1,"Only the requested limb track changes phase");
        }
        check(PerformanceAnimation.driveLayer(layer,"Unrelated", "DeadAirDrumL",1,.8)==0,"Layer prefix matching cannot animate another action");
        variables.setVariable("PerformingAction","Walk");check(state.getAnimNodes(variables,new java.util.ArrayList<>()).isEmpty(),"No drum layer leaks into walking");
        System.out.println("PASS: real game simultaneously selects five percussion layers; native bridge isolates each limb");
    }
    static void check(boolean yes,String why) { if(!yes) throw new AssertionError(why); }
    static AnimationTrack track(String name) {
        Keyframe first=new Keyframe(new Vector3f(),new Quaternion(),new Vector3f(1,1,1));
        first.bone=0;first.boneName="Bip01_R_Hand";first.time=0;
        Keyframe last=new Keyframe(new Vector3f(1,0,0),new Quaternion(),new Vector3f(1,1,1));
        last.bone=0;last.boneName=first.boneName;last.time=1;
        AnimationTrack track=AnimationTrack.alloc();
        track.startClip(new AnimationClip(1,List.of(first,last),name,true),true,0);
        return track;
    }
    static void liveTrackRegression(AnimNode node,AnimationVariableSource variables) {
        AnimationTrack owned=track(node.animName),other=track("UnrelatedWalk");
        owned.setSpeedDelta(0);other.setSpeedDelta(1);
        variables.setVariable("DeadAirGuitarSpeed",1.25f);
        owned.UpdateKeyframes(.2f);
        check(owned.getCurrentTrackTime()==0,"Regression setup: speed variable alone leaves a running track frozen");
        AnimLayer layer=AnimLayer.alloc(null,null);
        LiveAnimNode live=LiveAnimNode.alloc(layer,node);live.setActive(true);live.addMainTrack(owned);live.addMainTrack(other);
        layer.getLiveAnimNodes().add(live);
        check(PerformanceAnimation.driveLayer(layer,node.name,node.animName,1.25,-1)==1,"Only the matching active action clip is driven");
        owned.UpdateKeyframes(.2f);
        Vector3f position=new Vector3f();owned.get(0,position,new Quaternion(),new Vector3f());
        check(Math.abs(owned.getCurrentTrackTime()-.25f)<.001 && position.x>.2f,"Live track advances time AND interpolated bone pose");
        float before=owned.getCurrentTrackTime();
        PerformanceAnimation.driveLayer(layer,node.name,node.animName,0,-1);owned.UpdateKeyframes(.2f);
        check(owned.getCurrentTrackTime()==before,"Release freezes the current pose");
        PerformanceAnimation.driveLayer(layer,node.name,node.animName,1,-1);owned.UpdateKeyframes(.1f);
        check(owned.getCurrentTrackTime()>before,"Next note resumes without restarting the clip");
        check(other.getSpeedDelta()==1,"Unrelated movement track unchanged");
        live.setActive(false);
        check(PerformanceAnimation.driveLayer(layer,node.name,node.animName,3,-1)==0,"Fading or inactive action is not driven");
        live.setActive(true);
        PerformanceAnimation.driveLayer(layer,node.name,node.animName,1,.6);owned.UpdateKeyframes(.1f);
        check(Math.abs(owned.getCurrentTrackTime()-.6f)<.001,"Strike phase is exact and not advanced again by game playback");
        PerformanceAnimation.driveLayer(layer,node.name,node.animName,0,0);owned.UpdateKeyframes(.1f);
        check(owned.getCurrentTrackTime()==0,"Strike returns to ready pose");
        check(node.getSpeedScale(variables)==1.25f,"Shared animation definition remains unchanged");
        check(PerformanceAnimation.drive(null,node.name,node.animName,1,-1)==0,"Missing survivor is safe");
        System.out.println("PASS: real game live tracks, bone interpolation, release/resume, strike phase and unrelated-track isolation (headless)");
    }
}
