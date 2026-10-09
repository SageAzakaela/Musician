"""Author short neutral-to-contact drum gestures on the existing PZ-compatible rig.
Run with Blender in background mode. No world/combat events are embedded.
"""
import bpy,math,json
from mathutils import Vector,Matrix,Quaternion
from pathlib import Path
root=Path(__file__).resolve().parents[1]
source=root/'Contents/mods/DeadAir/common/media/anims_X/Bob_PlayGuitarExperiencedA.fbx'
out=root/'Contents/mods/DeadAir/common/media/anims_X'
bpy.ops.wm.read_factory_settings(use_empty=True);bpy.ops.import_scene.fbx(filepath=str(source))
rig=next(o for o in bpy.data.objects if o.type=='ARMATURE');bpy.context.scene.frame_set(1)
base={b.name:b.matrix_basis.copy()for b in rig.pose.bones};rig.animation_data_clear()
# PZ's AnimationOnly loader still selects a mesh and requires its bone bindings.
# Preserve the existing 480-vertex carrier mesh; it is not rendered by this path.
skin_meshes=[ob for ob in bpy.data.objects if ob.type=='MESH' and any(m.type=='ARMATURE' and m.object==rig for m in ob.modifiers)]
assert skin_meshes and all(len(ob.vertex_groups)>0 for ob in skin_meshes),'Animation export needs a bound mesh'
for ob in list(bpy.data.objects):
    if ob!=rig and ob not in skin_meshes:bpy.data.objects.remove(ob,do_unlink=True)
scene=bpy.context.scene;scene.render.fps=30
def world(b):return rig.matrix_world@b.matrix
def setworld(b,m):b.matrix=rig.matrix_world.inverted()@m;bpy.context.view_layer.update()
def rotate_at(b,position,delta):
    m=world(b);q=delta@m.to_quaternion();setworld(b,Matrix.LocRotScale(position,q,m.to_scale()))
def reset():
    for b in rig.pose.bones:b.matrix_basis=base[b.name].copy()
    bpy.context.view_layer.update()
def arm(side,target,direction=(0,-.78,-.63)):
    # Anatomical two-link IK with an outward elbow pole. Work in imported rig units.
    u=rig.pose.bones['Bip01_'+side+'_UpperArm'];f=rig.pose.bones['Bip01_'+side+'_Forearm'];h=rig.pose.bones['Bip01_'+side+'_Hand']
    sign=1 if side=='L' else -1
    shoulder=world(u).translation;elbow=world(f).translation;hand=world(h).translation
    a=(elbow-shoulder).length;b=(hand-elbow).length
    tip=Vector(target);direction=Vector(direction).normalized();wrist=tip-direction*14
    axis=wrist-shoulder;distance=min(axis.length,a+b-.2);axis.normalize()
    pole=Vector((sign,0,-.15));pole=(pole-axis*pole.dot(axis)).normalized()
    along=(a*a-b*b+distance*distance)/(2*distance);height=math.sqrt(max(0,a*a-along*along))
    joint=shoulder+axis*along+pole*height;wrist=shoulder+axis*distance
    rotate_at(u,shoulder,(elbow-shoulder).normalized().rotation_difference((joint-shoulder).normalized()))
    elbow=world(f).translation;hand=world(h).translation
    rotate_at(f,elbow,(hand-elbow).normalized().rotation_difference((wrist-elbow).normalized()))
    hand=world(h).translation;m=world(h)
    olddir=m.to_quaternion()@Vector((0,1,0));rotate_at(h,hand,olddir.rotation_difference(direction))
    prop=rig.pose.bones['Bip01_Prop2' if side=='L' else 'Bip01_Prop1']
    grip=hand+direction*3
    setworld(prop,Matrix.LocRotScale(grip,direction.to_track_quat('Y','Z'),world(prop).to_scale()))
    return list(grip),list(grip+direction*11.2054)
def ready():
    reset();arm('L',(12,-24,57));arm('R',(-12,-24,57))
targets={
    'Snare':(8,-23,48),'Hat':(15,-19,66),'Floor':(-25,-20,50),
    'RackLow':(-9,-30,60),'RackHigh':(9,-30,63),'Cymbal':(-23,-20,76),
    'Practice':(0,-25,54),
    'Single':(0,-28,48),
}
report={'targets':targets,'clips':{}}
def export(name,frames):
    scene.name=name
    scene.frame_start=1;scene.frame_end=frames;scene.frame_set(1)
    rig.animation_data.action.name=name
    bpy.ops.object.select_all(action='DESELECT');rig.select_set(True);bpy.context.view_layer.objects.active=rig
    for mesh in skin_meshes:mesh.select_set(True)
    bpy.ops.export_scene.fbx(filepath=str(out/(name+'.fbx')),use_selection=True,object_types={'ARMATURE','MESH'},add_leaf_bones=False,
        bake_anim=True,bake_anim_use_all_bones=True,bake_anim_use_nla_strips=False,bake_anim_use_all_actions=False,
        bake_anim_force_startend_keying=True,bake_anim_simplify_factor=0,axis_forward='-Z',axis_up='Y',path_mode='AUTO')
    rig.animation_data_clear()
def key(frame):
    for b in rig.pose.bones:
        b.rotation_mode='QUATERNION';b.keyframe_insert('location',frame=frame);b.keyframe_insert('rotation_quaternion',frame=frame);b.keyframe_insert('scale',frame=frame)
def snapshot():return {b.name:list(world(b).translation)for b in rig.pose.bones}
# Resting posture used by the torso, legs and unused limbs.
for frame in (1,31):ready();key(frame)
report['clips']['DeadAirDrumReady']={'ready':snapshot()};export('DeadAirDrumReady',31)
for side in ('L','R'):
    name='DeadAirDrum'+side;poses=[]
    # Eight one-second slots; the animation controller selects the requested slot.
    for idx,(targetName,target)in enumerate(targets.items()):
        for j in range(31):
            ready();phase=j/30
            # A small wind-up, contact at 45%, then a controlled rebound.
            contact=max(0,1-abs(phase-.45)/.45) if phase<=.9 else 0
            contact=contact*contact*(3-2*contact)
            neutral=Vector((12 if side=='L' else -12,-24,57))
            tip=neutral.lerp(Vector(target),contact)
            if phase<.16:tip.z+=math.sin(phase/.16*math.pi)*5
            grip,actual=arm(side,tip);frame=1+idx*30+j;key(frame)
            if j in (0,14,30):poses.append({'target':targetName,'phase':phase,'bones':snapshot(),'tip':actual,'requested':list(tip)})
    report['clips'][name]=poses;export(name,241)
# Ankle-only pedal press: no attack pose, hip lift, stomp or body movement.
for side in ('R','L'):
    name='DeadAirPedal'+side;poses=[]
    for j in range(31):
        ready();b=rig.pose.bones['Bip01_'+side+'_Foot'];m=world(b)
        press=math.sin(math.pi*j/30)
        setworld(b,Matrix.LocRotScale(m.translation,Quaternion(Vector((1,0,0)),math.radians(12)*press)@m.to_quaternion(),m.to_scale()))
        key(j+1)
        if j in (0,15,30):poses.append({'phase':j/30,'bones':snapshot()})
    report['clips'][name]=poses;export(name,31)
# A small sideways tap against the other hand, not an overhead tool swing.
# The controller traverses ready -> tap -> ready instead of looping this clip.
poses=[]
for j in range(31):
    ready();t=j/30;t=t*t*(3-2*t)
    up=Vector((0,0,1));leftdir=Vector((-.8,0,-.6))
    arm('L',Vector((3,-20,70))+leftdir*14,leftdir)
    arm('R',Vector((-9+9*t,-20,58))+up*14,up)
    key(j+1)
    if j in (0,15,30):poses.append({'phase':j/30,'bones':snapshot()})
report['clips']['DeadAirForkTap']=poses;export('DeadAirForkTap',31)
(root/'test-results').mkdir(exist_ok=True)
(root/'test-results/drum-poses.json').write_text(json.dumps(report,indent=2))
print('Generated five drum clips and a tuning-fork tap; target slots:',list(targets))
