"""Rig an unrigged MPFB human saved as a .blend, then export it as .glb for
import_body.py. MPFB's base mesh carries a "joint-*" vertex group at every
joint (that is how MPFB places its own rigs), so the joints are found from
those, a Game engine-style skeleton is built on them, and the body is
weighted automatically.

    python3 tools/blender/rig_mpfb_basemesh.py Character.blend out.glb [--fit tools/blender/shirt_fit.json]

MPFB's lips, scalp and ears groups go into a vertex colour, and its mouth and
jaw joints become marker bones, for the converter's face shading. With --fit
(from shirt_fit.py) the shirt's looseness rides along too, in the colour's
alpha (metres / 0.05). Only the
body is kept: MPFB's helper geometry (tights, skirt, hair, eye and
teeth helpers) is cut away, and the body's shape keys (the MPFB sliders) are
baked in as they were saved.
"""
import sys

import bpy  # first: it provides bmesh and mathutils
import bmesh
from mathutils import Vector

src, out = sys.argv[1], sys.argv[2]
fit = None
if "--fit" in sys.argv:
    import json
    fit = json.load(open(sys.argv[sys.argv.index("--fit") + 1]))["fit"]
bpy.ops.wm.open_mainfile(filepath=src)
human = next(o for o in bpy.data.objects if o.type == "MESH" and
             (o.get("MPFB_GEN_object_type") == "Basemesh" or "joint-pelvis" in o.vertex_groups))
for o in list(bpy.data.objects):
    if o != human:
        bpy.data.objects.remove(o)

groups = {g.name: g.index for g in human.vertex_groups}


def joint(name):
    """Centre of a joint-* vertex group, world space, shape keys applied."""
    gi = groups["joint-" + name]
    pts = [v for v in mesh.vertices if any(g.group == gi and g.weight > 0.5 for g in v.groups)]
    c = sum((human.matrix_world @ v.co for v in pts), Vector())
    return c / len(pts)


# Bake the sliders: evaluate shape keys (not the mask) into a plain mesh.
for m in list(human.modifiers):
    human.modifiers.remove(m)
dg = bpy.context.evaluated_depsgraph_get()
mesh = bpy.data.meshes.new_from_object(human.evaluated_get(dg), preserve_all_data_layers=True, depsgraph=dg)
old = human.data
human.data = mesh
if old.users == 0:
    bpy.data.meshes.remove(old)

J = {}
for n in ["pelvis", "spine-1", "spine-2", "spine-3", "spine-4", "neck", "head", "head-2", "ground", "l-eye", "r-eye",
          "mouth", "jaw"]:
    J[n] = joint(n)
for s in ("l", "r"):
    for n in ["clavicle", "shoulder", "elbow", "hand", "hand-2", "upper-leg", "knee", "ankle", "foot-1", "foot-2"]:
        J[s + "-" + n] = joint(s + "-" + n)

# Keep the body only (remembering each vertex's base-mesh index for --fit).
orig = mesh.attributes.new("orig", "INT", "POINT")
for v in mesh.vertices:
    orig.data[v.index].value = v.index
bm = bmesh.new()
bm.from_mesh(mesh)
deform = bm.verts.layers.deform.verify()
body = groups["body"]
bmesh.ops.delete(bm, geom=[v for v in bm.verts if v[deform].get(body, 0.0) < 0.5], context="VERTS")
bm.to_mesh(mesh)
bm.free()
# MPFB's face groups, kept as a vertex colour for the converter: red the
# lips, green the scalp (where hair grows), blue the ears; alpha the shirt fit.
zones = mesh.color_attributes.new("zones", "FLOAT_COLOR", "POINT")
zi = [groups.get(n) for n in ("lips", "scalp", "ears")]
orig = mesh.attributes["orig"]
for v in mesh.vertices:
    w = {g.group: g.weight for g in v.groups}
    a = min(1.0, fit[orig.data[v.index].value] / 0.05) if fit else 0.0
    zones.data[v.index].color = [w.get(i, 0.0) if i is not None else 0.0 for i in zi] + [a]
mesh.color_attributes.active_color = zones
human.vertex_groups.clear()

# Skeleton with Game engine bone names, on MPFB's joints. The spine joints
# are ordered bottom to top by height.
spine = sorted(["spine-1", "spine-2", "spine-3", "spine-4"], key=lambda n: J[n].z)
arm = bpy.data.armatures.new("Armature")
rig = bpy.data.objects.new("Armature", arm)
bpy.context.collection.objects.link(rig)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode="EDIT")


def bone(name, head, tail, parent=None):
    b = arm.edit_bones.new(name)
    b.head, b.tail = head, tail
    if parent:
        b.parent = arm.edit_bones[parent]
    return b


bone("pelvis", J["pelvis"], J[spine[0]])
bone("spine_01", J[spine[0]], J[spine[1]], "pelvis")
bone("spine_02", J[spine[1]], J[spine[2]], "spine_01")
bone("spine_03", J[spine[2]], J[spine[3]], "spine_02")
bone("spine_04", J[spine[3]], J["neck"], "spine_03")
bone("neck_01", J["neck"], J["head"], "spine_04")
bone("head", J["head"], J["head-2"] if (J["head-2"] - J["head"]).length > 0.05 else J["head"] + Vector((0, 0, 0.2)), "neck_01")
for s in ("l", "r"):
    bone("clavicle_" + s, J[s + "-clavicle"], J[s + "-shoulder"], "spine_04")
    bone("upperarm_" + s, J[s + "-shoulder"], J[s + "-elbow"], "clavicle_" + s)
    bone("lowerarm_" + s, J[s + "-elbow"], J[s + "-hand"], "upperarm_" + s)
    hand_tip = J[s + "-hand"] + (J[s + "-hand"] - J[s + "-elbow"]).normalized() * 0.15
    bone("hand_" + s, J[s + "-hand"], hand_tip, "lowerarm_" + s)
    bone("thigh_" + s, J[s + "-upper-leg"], J[s + "-knee"], "pelvis")
    bone("calf_" + s, J[s + "-knee"], J[s + "-ankle"], "thigh_" + s)
    toe = min((J[s + "-foot-1"], J[s + "-foot-2"]), key=lambda p: p.y)  # the figure faces -Y
    bone("foot_" + s, J[s + "-ankle"], toe, "calf_" + s)
# Eye centres, as markers that weigh nothing (the converter reads them to
# place the game's eyeballs; MPFB's own eyes are helper geometry).
for s in ("l", "r"):
    e = bone("eye_" + s, J[s + "-eye"], J[s + "-eye"] + Vector((0, -0.03, 0)), "head")
    e.use_deform = False
for n in ("mouth", "jaw"):  # likewise, for the beard and stubble zones
    e = bone(n, J[n], J[n] + Vector((0, -0.03, 0)), "head")
    e.use_deform = False
bpy.ops.object.mode_set(mode="OBJECT")

bpy.ops.object.select_all(action="DESELECT")
human.select_set(True)
rig.select_set(True)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.parent_set(type="ARMATURE_AUTO")
weighted = sum(1 for v in human.data.vertices if v.groups)
print("rigged %s: %d vertices (%d weighted), %d triangles, height %.2f m" % (
    human.name, len(human.data.vertices), weighted, sum(len(p.vertices) - 2 for p in human.data.polygons),
    max((human.matrix_world @ v.co).z for v in human.data.vertices) - J["ground"].z))
bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", export_skins=True, export_animations=False,
                          export_morph=False, export_apply=True,
                          export_vertex_color="ACTIVE", export_active_vertex_color_when_no_material=True)
