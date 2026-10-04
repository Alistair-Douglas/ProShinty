"""Measure how loose a shirt sits on an MPFB human, for the game's kit.

    python3 tools/blender/shirt_fit.py Clothed.blend tools/blender/shirt_fit.json

The .blend is an MPFB human wearing MPFB clothes (any shirt; long sleeves are
fine). For every vertex of MPFB's base mesh it writes how far out from the
skin the shirt is, in metres (0 where the shirt doesn't reach). Every MPFB
human shares the base mesh, so rig_mpfb_basemesh.py --fit can lay this
shirt's fit onto any other body: looser over the back and under the arms,
closer over the chest, as that shirt hangs.
"""
import json
import sys

import bpy  # first: it provides mathutils
from mathutils.bvhtree import BVHTree

src, out = sys.argv[1], sys.argv[2]
bpy.ops.wm.open_mainfile(filepath=src)
human = next(o for o in bpy.data.objects if o.type == "MESH" and "joint-pelvis" in o.vertex_groups)
clothes = [o for o in bpy.data.objects if o.type == "MESH" and o.get("MPFB_GEN_object_type") == "Clothes"]
# Every clothes piece counts; the converter only uses the fit on the shirt.
for o in clothes:
    for m in o.modifiers:
        if m.type == "SUBSURF":
            m.show_viewport = False
for m in human.modifiers:
    if m.type == "MASK":
        m.show_viewport = False
dg = bpy.context.evaluated_depsgraph_get()
hm = human.evaluated_get(dg).to_mesh()


def tree(o):
    me = o.evaluated_get(dg).to_mesh()
    return BVHTree.FromPolygons([o.matrix_world @ v.co for v in me.vertices], [p.vertices[:] for p in me.polygons])


trees = [tree(o) for o in clothes]
fit = [0.0] * len(hm.vertices)
mw, nm = human.matrix_world, human.matrix_world.to_3x3()
for v in hm.vertices:
    p, n = mw @ v.co, (nm @ v.normal).normalized()
    best = None
    for t in trees:
        hit = t.ray_cast(p, n, 0.08)  # straight out from the skin
        if hit[0] is not None and (best is None or hit[3] < best):
            best = hit[3]
    if best is not None:
        fit[v.index] = round(best, 4)
with open(out, "w") as f:
    json.dump({"source": src.rsplit("/", 1)[-1], "clothes": [o.name for o in clothes], "fit": fit}, f, separators=(",", ":"))
print("wrote %s: %d of %d vertices covered" % (out, sum(1 for x in fit if x > 0), len(fit)))
