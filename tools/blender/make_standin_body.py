"""Build a rough stand-in for an MPFB body, to test import_body.py without
Blender's MPFB add-on: a smooth skin-modifier figure in an A-pose with a
"Game engine"-style rig (pelvis, spine_01..03, clavicle_l, upperarm_l, ...)
and automatic weights, exported as glTF like MPFB's own export.

    python3 tools/blender/make_standin_body.py out.glb [build 0..1]
"""
import sys
import math
import bpy
from mathutils import Vector

out = sys.argv[1]
build = float(sys.argv[2]) if len(sys.argv) > 2 else 0.5
g = 0.85 + 0.35 * build  # girth

bpy.ops.wm.read_factory_settings(use_empty=True)

# Joints in Blender space (Z up, the figure faces -Y), metres.
A = math.radians(42)  # arm angle down from horizontal in the A-pose
J = {"pelvis": (0, 0, 0.97), "spine_01": (0, 0.005, 1.06), "spine_02": (0, 0.01, 1.19), "spine_03": (0, 0.01, 1.32),
     "neck_01": (0, 0.02, 1.47), "head": (0, 0.0, 1.57), "head_end": (0, 0.0, 1.78)}
for s, sx in (("l", 1), ("r", -1)):
    sh = Vector((sx * 0.185, 0.02, 1.43))
    J["clavicle_" + s] = (sx * 0.03, 0.0, 1.41)
    J["upperarm_" + s] = tuple(sh)
    el = sh + Vector((sx * math.cos(A), 0, -math.sin(A))) * 0.29
    J["lowerarm_" + s] = tuple(el)
    wr = el + Vector((sx * math.cos(A), 0, -math.sin(A))) * 0.26
    J["hand_" + s] = tuple(wr)
    J["hand_end_" + s] = tuple(wr + Vector((sx * math.cos(A), 0, -math.sin(A))) * 0.17)
    J["thigh_" + s] = (sx * 0.095, 0.0, 0.92)
    J["calf_" + s] = (sx * 0.1, -0.01, 0.49)
    J["foot_" + s] = (sx * 0.105, 0.02, 0.08)
    J["ball_" + s] = (sx * 0.11, -0.12, 0.02)
    J["toe_end_" + s] = (sx * 0.11, -0.19, 0.02)

# Skin-modifier skeleton: vertices with radii, edges between them.
pts, rad, edges = [], [], []
def P(name_or_xyz, r):
    pts.append(Vector(J[name_or_xyz] if isinstance(name_or_xyz, str) else name_or_xyz))
    rad.append(r)
    return len(pts) - 1
def chain(*ids):
    for a, b in zip(ids, ids[1:]):
        edges.append((a, b))

hip = P("pelvis", (0.15 * g, 0.1 * g))
s1 = P("spine_01", (0.14 * g, 0.1 * g))
s2 = P("spine_02", (0.15 * g, 0.1 * g))
s3 = P("spine_03", (0.17 * g, 0.11 * g))
nk = P("neck_01", (0.055, 0.055))
hd = P("head", (0.075, 0.09))
ht = P("head_end", (0.03, 0.03))
chain(hip, s1, s2, s3, nk, hd, ht)
for s in ("l", "r"):
    sh = P("upperarm_" + s, (0.055 * g, 0.055 * g))
    el = P("lowerarm_" + s, (0.042 * g, 0.042 * g))
    wr = P("hand_" + s, (0.03, 0.025))
    he = P("hand_end_" + s, (0.02, 0.012))
    chain(s3, sh, el, wr, he)
    th = P("thigh_" + s, (0.08 * g, 0.08 * g))
    kn = P("calf_" + s, (0.05 * g, 0.05 * g))
    an = P("foot_" + s, (0.035, 0.035))
    bl = P("ball_" + s, (0.04, 0.025))
    te = P("toe_end_" + s, (0.03, 0.02))
    chain(hip, th, kn, an, bl, te)

me = bpy.data.meshes.new("Body")
me.from_pydata([tuple(p) for p in pts], edges, [])
body = bpy.data.objects.new("Body", me)
bpy.context.collection.objects.link(body)
skin = body.modifiers.new("Skin", "SKIN")
for i, r in enumerate(rad):
    body.data.skin_vertices[0].data[i].radius = r
body.data.skin_vertices[0].data[hip].use_root = True
sub = body.modifiers.new("Sub", "SUBSURF")
sub.levels = 2
bpy.context.view_layer.objects.active = body
body.select_set(True)
bpy.ops.object.modifier_apply(modifier="Skin")
bpy.ops.object.modifier_apply(modifier="Sub")

# Rig with Game engine bone names.
arm = bpy.data.armatures.new("Armature")
rig = bpy.data.objects.new("Armature", arm)
bpy.context.collection.objects.link(rig)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode="EDIT")
def bone(name, head, tail, parent=None):
    b = arm.edit_bones.new(name)
    b.head = Vector(J[head]) if isinstance(head, str) else Vector(head)
    b.tail = Vector(J[tail]) if isinstance(tail, str) else Vector(tail)
    if parent:
        b.parent = arm.edit_bones[parent]
        b.use_connect = False
    return b
bone("root", (0, 0, 0), (0, 0, 0.2))
bone("pelvis", "pelvis", "spine_01", "root")
bone("spine_01", "spine_01", "spine_02", "pelvis")
bone("spine_02", "spine_02", "spine_03", "spine_01")
bone("spine_03", "spine_03", "neck_01", "spine_02")
bone("neck_01", "neck_01", "head", "spine_03")
bone("head", "head", "head_end", "neck_01")
for s in ("l", "r"):
    bone("clavicle_" + s, "clavicle_" + s, "upperarm_" + s, "spine_03")
    bone("upperarm_" + s, "upperarm_" + s, "lowerarm_" + s, "clavicle_" + s)
    bone("lowerarm_" + s, "lowerarm_" + s, "hand_" + s, "upperarm_" + s)
    bone("hand_" + s, "hand_" + s, "hand_end_" + s, "lowerarm_" + s)
    bone("thigh_" + s, "thigh_" + s, "calf_" + s, "pelvis")
    bone("calf_" + s, "calf_" + s, "foot_" + s, "thigh_" + s)
    bone("foot_" + s, "foot_" + s, "ball_" + s, "calf_" + s)
    bone("ball_" + s, "ball_" + s, "toe_end_" + s, "foot_" + s)
arm.edit_bones["root"].use_deform = False
bpy.ops.object.mode_set(mode="OBJECT")

bpy.ops.object.select_all(action="DESELECT")
body.select_set(True)
rig.select_set(True)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.parent_set(type="ARMATURE_AUTO")

bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", export_skins=True, export_animations=False,
                          export_apply=True)
print("stand-in body: %d triangles -> %s" % (sum(len(p.vertices) - 2 for p in body.data.polygons), out))
