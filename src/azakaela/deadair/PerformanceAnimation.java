package azakaela.deadair;

import zombie.characters.IsoGameCharacter;
import zombie.core.skinnedmodel.advancedanimation.*;
import zombie.core.skinnedmodel.animation.AnimationTrack;

/** Called only from the game's timed-action update. Never from MIDI/audio threads. */
public final class PerformanceAnimation {
    private PerformanceAnimation() {}

    public static int drive(IsoGameCharacter character,String action,String clip,double speed,double phase) {
        if(character==null || action==null || !action.startsWith("DeadAir") || clip==null
                || !action.equals(character.getVariableString("PerformingAction"))) return 0;
        AdvancedAnimator animator=character.getAdvancedAnimator();
        if(animator==null) return 0;
        int count=driveLayer(animator.getRootLayer(),action,clip,speed,phase);
        for(int i=0;i<animator.getSubLayerCount();i++)
            count+=driveLayer(animator.getSubLayerAt(i),action,clip,speed,phase);
        return count;
    }
    static int driveLayer(AnimLayer layer,String action,String clip,double speed,double phase) {
        if(layer==null) return 0;
        int count=0;
        for(LiveAnimNode live:layer.getLiveAnimNodes()) {
            AnimNode node=live.getSourceNode();
            if(!live.isActive() || node==null || !(action.equals(node.name) || node.name.startsWith(action+"_")) || !clip.equals(node.animName)) continue;
            for(int i=0;i<live.getMainAnimationTracksCount();i++) {
                AnimationTrack track=live.getMainAnimationTrackAt(i);
                if(apply(track,clip,speed,phase)) count++;
            }
        }
        return count;
    }
    static boolean apply(AnimationTrack track,String clip,double speed,double phase) {
        if(track==null || !track.hasClip() || !clip.equals(track.getClip().name)) return false;
        float rate=Double.isFinite(speed)?(float)Math.max(0,Math.min(4,speed)):0;
        // Speed variables seed new tracks; existing tracks require this explicit update.
        // A nonnegative phase drives a percussion stroke without queuing/restarting actions.
        if(Double.isFinite(phase) && phase>=0) {
            track.setSpeedDelta(0);
            track.moveCurrentTimeValueToFraction((float)Math.min(.9999,phase));
        } else track.setSpeedDelta(rate);
        return true;
    }
}
