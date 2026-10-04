"""Turn a body exported from Blender (MPFB "Game engine" rig, or any rig with
similar bone names) into a body file the game loads: models/bodies/<name>.json.

    python3 tools/blender/import_body.py body.glb models/bodies/average.json [--tris 3900] [--no-head]

Needs the `bpy` module (pip install bpy, Blender as a Python module), so it
runs anywhere Python 3.11 does; no Blender window or MPFB needed here.

What it does:
  1. Reads the .glb and maps every rig bone onto the game's skeleton
     (Hips, Spine, Chest, UpperChest, Neck, Left/Right UpperArm, LowerArm,
     UpperLeg, LowerLeg, Head). Hands and feet are cut off: the game keeps
     its own gripping hands and boots. The body's own head and face are
     kept (the game sizes its helmet to the skull and puts its eyes where
     the rig's eye_l/eye_r markers are); --no-head cuts the head off too and
     the game builds its own.
  2. Bends the body from its A-pose into the game's rest pose (arms and legs
     straight down) and stretches each limb to the game's bone lengths, so
     poses, the arm solver and the caman grip work unchanged.
  3. Cuts it down to the triangle budget for Intel Iris Xe laptops.
  4. Splits it into skin, shirt, shorts and socks, lifts the kit off the
     skin a little (looser on the shorts) and lays out the coordinates the
     fabric shader uses for hoops, stripes and trim bands.

The game's skeleton (ShintyPlayerModel._build) at 1.80 m, Godot space: Y up,
facing -Z, the player's left at -X.
"""
import json
import math
import sys

import bpy  # first: it provides bmesh and mathutils
import bmesh
import numpy as np
from mathutils import Vector

REF = {  # joint positions (global rest) of the game skeleton
    "Hips": (0, 0.98, 0), "Spine": (0, 1.08, 0), "Chest": (0, 1.22, 0), "UpperChest": (0, 1.36, 0),
    "Neck": (0, 1.49, 0), "Head": (0, 1.57, 0),
    "LeftUpperArm": (-0.19, 1.44, 0), "LeftLowerArm": (-0.19, 1.15, 0), "LeftHand": (-0.19, 0.88, 0),
    "RightUpperArm": (0.19, 1.44, 0), "RightLowerArm": (0.19, 1.15, 0), "RightHand": (0.19, 0.88, 0),
    "LeftUpperLeg": (-0.095, 0.93, 0), "LeftLowerLeg": (-0.095, 0.49, 0), "LeftFoot": (-0.095, 0.06, 0),
    "RightUpperLeg": (0.095, 0.93, 0), "RightLowerLeg": (0.095, 0.49, 0), "RightFoot": (0.095, 0.06, 0),
}
CHILD = {"Hips": "Spine", "Spine": "Chest", "Chest": "UpperChest", "UpperChest": "Neck", "Neck": "Head"}
for s in ("Left", "Right"):
    CHILD[s + "UpperArm"] = s + "LowerArm"
    CHILD[s + "LowerArm"] = s + "Hand"
    CHILD[s + "UpperLeg"] = s + "LowerLeg"
    CHILD[s + "LowerLeg"] = s + "Foot"
DROPPED = {"Head", "LeftHand", "RightHand", "LeftFoot", "RightFoot"}
NECK_LIFT = 0.035  # metres
if "--no-head" not in sys.argv:  # keep the body's own head and face
    DROPPED.discard("Head")
KEPT = [b for b in REF if b not in DROPPED]
HEAD_TOP = 0.238  # the game's skull top above the Head bone, which the helmet fits


def side_of(name):
    n = name.lower().replace(":", "_").replace(".", "_")
    if n.endswith(("_l", "left")) or "left" in n or n.endswith("l") and n[-2:-1] == "_":
        return "Left"
    if n.endswith(("_r", "right")) or "right" in n:
        return "Right"
    return ""


def game_bone(name):
    """Which game bone a rig bone belongs to ('' = ignore, '?spine' = spine chain)."""
    n = name.lower()
    s = side_of(name)
    for keys, part in ((("thumb", "index", "middle", "ring", "pinky", "finger", "hand", "wrist", "palm", "metacarpal"), "Hand"),
                       (("forearm", "lowerarm", "lower_arm", "elbow"), "LowerArm"),
                       (("upperarm", "upper_arm", "shoulder_twist", "arm"), "UpperArm"),
                       (("toe", "ball", "foot", "ankle"), "Foot"),
                       (("calf", "shin", "lowerleg", "lower_leg", "knee"), "LowerLeg"),
                       (("thigh", "upperleg", "upper_leg", "upleg", "leg"), "UpperLeg")):
        if any(k in n for k in keys):
            return (s + part) if s else ""
    if "clavicle" in n or "shoulder" in n or "collar" in n:
        return "UpperChest"
    if any(k in n for k in ("head", "jaw", "eye", "tongue", "teeth", "brow", "lip", "cheek", "nose", "ear")):
        return "Head"
    if "neck" in n:
        return "Neck"
    if "pelvis" in n or "hip" in n:
        return "Hips"
    if "spine" in n or "chest" in n or "torso" in n:
        return "?spine"
    return ""


def to_godot(v):
    """Blender (Z up, facing -Y, figure's left at +X) to Godot (Y up, facing -Z, left at -X)."""
    return np.array([-v[0], v[2], v[1]])


def frame(o, e):
    y = e - o
    y /= np.linalg.norm(y)
    z = np.array([0.0, 0.0, 1.0]) - y * y[2]
    if np.linalg.norm(z) < 1e-4:
        z = np.array([1.0, 0.0, 0.0]) - y * y[0]
    z /= np.linalg.norm(z)
    x = np.cross(y, z)
    return np.stack([x, y, z], axis=1)


def split(pos, vn, dense, tri, level, applies):
    """Cut every triangle the plane y = level runs through (where applies(tri)
    says so) into three, adding vertices on the plane; weights and normals are
    blended along the cut edges."""
    pos, vn, dense = list(pos), list(vn), list(dense)
    made = {}
    def cut(a, b):
        key = (min(a, b), max(a, b))
        if key not in made:
            t = (level - pos[a][1]) / (pos[b][1] - pos[a][1])
            pos.append(pos[a] + (pos[b] - pos[a]) * t)
            nrm = vn[a] + (vn[b] - vn[a]) * t
            vn.append(nrm / max(np.linalg.norm(nrm), 1e-9))
            dense.append(dense[a] + (dense[b] - dense[a]) * t)
            made[key] = len(pos) - 1
        return made[key]
    out = []
    for t in tri:
        side = [pos[i][1] > level for i in t]
        if all(side) or not any(side) or not applies(np.array(t)):
            out.append(t)
            continue
        # Rotate so vertex 0 is the one alone on its side.
        k = [i for i in range(3) if side.count(side[i]) == 1][0]
        a, b, c = t[k], t[(k + 1) % 3], t[(k + 2) % 3]
        ab, ac = cut(a, b), cut(a, c)
        out += [[a, ab, ac], [ab, b, c], [ab, c, ac]]
    return np.array(pos), np.array(vn), np.array(dense), np.array(out, dtype=np.int64)


def main():
    args = sys.argv[1:]
    src, out = args[0], args[1]
    tris = int(args[args.index("--tris") + 1]) if "--tris" in args else 3900
    name = out.rsplit("/", 1)[-1].rsplit(".", 1)[0]
    build = float(args[args.index("--build") + 1]) if "--build" in args else \
        (0.2 if "lean" in name else 0.8 if "stocky" in name else 0.5)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=src)
    rig = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    meshes = [o for o in bpy.data.objects if o.type == "MESH" and o.find_armature() == rig or
              o.type == "MESH" and o.parent == rig]
    if not meshes:
        meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    # The body is the biggest mesh; MPFB may add eyes, eyebrows or a proxy.
    body = max(meshes, key=lambda o: len(o.data.vertices))

    # --- Map rig bones to game bones -------------------------------------------
    mw = rig.matrix_world
    heads = {b.name: to_godot(mw @ b.head_local) for b in rig.data.bones}
    mapping = {b.name: game_bone(b.name) for b in rig.data.bones if b.use_deform}
    spine = sorted([n for n, g in mapping.items() if g == "?spine"], key=lambda n: heads[n][1])
    for i, n in enumerate(spine):
        mapping[n] = ("Spine", "Chest", "UpperChest")[min(2, i * 3 // max(1, len(spine)))]
    unmapped = [n for n, g in mapping.items() if g == ""]
    print("bones:", {g: [n for n, x in mapping.items() if x == g] for g in REF})
    if unmapped:
        print("ignored bones:", unmapped)

    # Joint positions on this body: the head of the first rig bone of each
    # game bone (lowest in the chain for the spine).
    joint = {}
    for g in REF:
        names = [n for n, x in mapping.items() if x == g]
        if not names:
            continue
        def depth(n):
            d, b = 0, rig.data.bones[n]
            while b.parent:
                d, b = d + 1, b.parent
            return d
        joint[g] = heads[min(names, key=depth)]
    missing = [g for g in REF if g not in joint]
    if missing:
        sys.exit("rig has no bones for %s; is this a Game engine rig?" % missing)
    scale = REF["Hips"][1] / joint["Hips"][1]
    for g in joint:
        joint[g] = joint[g] * scale

    # Per game bone: rig frame -> game frame, stretched along the bone.
    xf = {}
    for g in KEPT:
        if g == "Head":
            continue  # sized from the mesh below
        c = CHILD[g]
        o_src, e_src = joint[g], joint[c]
        o_dst, e_dst = np.array(REF[g], float), np.array(REF[c], float)
        r_src, r_dst = frame(o_src, e_src), frame(o_dst, e_dst)
        stretch = np.linalg.norm(e_dst - o_dst) / np.linalg.norm(e_src - o_src)
        m = r_dst @ np.diag([1.0, stretch, 1.0]) @ r_src.T
        xf[g] = (m, o_src, o_dst)

    # --- Cut off head, hands and feet; decimate -------------------------------
    bpy.context.view_layer.objects.active = body
    for mod in list(body.modifiers):
        if mod.type != "ARMATURE":
            bpy.ops.object.modifier_apply(modifier=mod.name)
    for mod in list(body.modifiers):
        body.modifiers.remove(mod)
    groups = {vg.index: vg.name for vg in body.vertex_groups}
    me = body.data

    def weights_of(v):
        acc = {}
        for ge in v.groups:
            g = mapping.get(groups.get(ge.group, ""), "")
            if g:
                acc[g] = acc.get(g, 0.0) + ge.weight
        return acc

    # glTF splits vertices along UV and shading seams; weld them back so the
    # kit can be lifted off the skin without opening cracks.
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-5)
    bm.to_mesh(me)
    bm.free()
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.verts.ensure_lookup_table()
    drop = set()
    for v in me.vertices:
        w = weights_of(v)
        tot = sum(w.values()) or 1.0
        if sum(w.get(d, 0.0) for d in DROPPED) / tot > 0.5:
            drop.add(v.index)
    bmesh.ops.delete(bm, geom=[bm.verts[i] for i in drop], context="VERTS")
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bm.to_mesh(me)
    bm.free()
    before = len(me.polygons)
    if before > tris:
        dec = body.modifiers.new("Decimate", "DECIMATE")
        dec.ratio = tris / before
        dec.use_collapse_triangulate = True
        bpy.ops.object.modifier_apply(modifier="Decimate")
    print("triangles: %d after cutting, %d after decimating" % (before, len(me.polygons)))

    eyes = []
    skull = None
    # --- Bend into the game's rest pose ----------------------------------------
    wmat = body.matrix_world
    n = len(me.vertices)
    pos = np.zeros((n, 3))
    W = np.zeros((n, len(KEPT)))
    for v in me.vertices:
        pos[v.index] = to_godot(wmat @ v.co) * scale
        w = weights_of(v)
        for g, x in w.items():
            if g in DROPPED:  # the last ring before a cut follows its parent
                g = {"Head": "Neck"}.get(g, g.replace("Hand", "LowerArm").replace("Foot", "LowerLeg"))
            W[v.index, KEPT.index(g)] += x
    empty = W.sum(1) == 0
    if empty.any():  # unweighted: nearest joint
        for i in np.where(empty)[0]:
            W[i, int(np.argmin([np.linalg.norm(pos[i] - joint[g]) for g in KEPT]))] = 1.0
    if "Head" in KEPT:
        # Turn the head upright and size it so its crown meets the game's
        # skull top, so the helmet fits.
        hi = KEPT.index("Head")
        mine = np.argmax(W, 1) == hi
        tail = to_godot(mw @ rig.data.bones[[n for n, x in mapping.items() if x == "Head"][0]].tail_local) * scale
        o_src = joint["Head"]
        r_src = frame(o_src, tail)
        o_dst = np.array(REF["Head"], float)
        r_dst = frame(o_dst, o_dst + np.array([0.0, 1.0, 0.0]))
        m = r_dst @ r_src.T
        # The head keeps its own size; the game fits its helmet to it. Our
        # built skull is 16 cm wide with its centre 12.8 cm below the crown.
        q = (pos[mine] - o_src) @ m.T
        top = q[:, 1].max()
        cran = q[q[:, 1] > top - 0.1]
        k = np.abs(cran[:, 0]).max() / 0.081
        cz = (cran[:, 2].max() + cran[:, 2].min()) / 2
        skull = [0.0, float(top - 0.128 * k), float(cz - 0.004 * k), float(k)]
        # Warped onto our shorter neck the chin sits on the collar: lift the
        # head a little and stretch the neck to meet it.
        dy, dz = NECK_LIFT, 0.0
        skull[1] += dy
        o_n, e_n = np.array(REF["Neck"], float), o_dst + np.array([0.0, dy, 0.0])
        r_n = frame(joint["Neck"], joint["Head"])
        stretch = np.linalg.norm(e_n - o_n) / np.linalg.norm(joint["Head"] - joint["Neck"])
        xf["Neck"] = (frame(o_n, e_n) @ np.diag([1.0, stretch, 1.0]) @ r_n.T, joint["Neck"], o_n)
        print("head: helmet scaled %.2f, lifted %.3f m (neck stretched %.2f)" % (k, dy, stretch))
        xf["Head"] = (m, o_src, o_dst + np.array([0.0, dy, dz]))
        for side in ("l", "r"):
            b = rig.data.bones.get("eye_" + side)
            if b:
                e = to_godot(mw @ b.head_local) * scale
                m, a, d = xf["Head"]
                eyes.append(list(np.round((e - a) @ m.T + d, 4)))
    # Keep the four strongest, normalised.
    order = np.argsort(-W, axis=1)
    keep = order[:, :4]
    W4 = np.take_along_axis(W, keep, 1)
    W4 /= W4.sum(1, keepdims=True)
    new = np.zeros_like(pos)
    for k in range(4):
        for gi, g in enumerate(KEPT):
            sel = keep[:, k] == gi
            if not sel.any():
                continue
            m, o_src, o_dst = xf[g]
            new[sel] += W4[sel, k:k + 1] * ((pos[sel] - o_src) @ m.T + o_dst)
    pos = new
    tri = np.array([[p.vertices[0], p.vertices[1], p.vertices[2]] for p in me.polygons], dtype=np.int64)
    # Normals from the bent shape (glTF winding is counter-clockwise).
    fn = np.cross(pos[tri[:, 1]] - pos[tri[:, 0]], pos[tri[:, 2]] - pos[tri[:, 0]])
    vn = np.zeros_like(pos)
    for k in range(3):
        np.add.at(vn, tri[:, k], fn)
    vn /= np.maximum(np.linalg.norm(vn, axis=1, keepdims=True), 1e-9)
    # Our mirror (Blender -> Godot flips X) reverses the winding; make faces
    # point outward again.
    centre = pos.mean(0)
    if np.mean(np.einsum("ij,ij->i", fn, pos[tri[:, 0]] - centre)) < 0:
        tri = tri[:, ::-1]
        vn = -vn
    # Godot draws clockwise faces as the front.
    tri = tri[:, ::-1]

    # --- Kit -----------------------------------------------------------------
    SLEEVE, CUFF = 0.155, 0.185
    WAIST_SHIRT, WAIST_SHORTS = 1.0, 1.06
    SHORTS_LEG = 0.2
    NECKLINE = 1.5
    SOCK_TOP = REF["LeftLowerLeg"][1] - 0.07
    # Cut the mesh along each kit edge (limbs hang straight down at rest, so
    # every edge is a height) so hems and sock tops are straight, not jagged.
    dense = np.zeros((len(pos), len(KEPT)))
    np.put_along_axis(dense, keep, W4, 1)
    names = np.array(KEPT)
    arm_y = REF["LeftUpperArm"][1]
    leg_y = REF["LeftUpperLeg"][1]
    cuts = [(SOCK_TOP, lambda d: np.char.endswith(d, "LowerLeg").any()),
            (leg_y - SHORTS_LEG, lambda d: all(x.endswith("UpperLeg") or x == "Hips" for x in d)),
            (arm_y - SLEEVE, lambda d: np.char.endswith(d, "UpperArm").any()),
            (arm_y - CUFF, lambda d: np.char.endswith(d, "UpperArm").any()),
            (WAIST_SHIRT, lambda d: all(x in ("Hips", "Spine", "Chest") for x in d)),
            (WAIST_SHORTS, lambda d: all(x in ("Hips", "Spine", "Chest") for x in d)),
            (NECKLINE, lambda d: all(x in ("Chest", "UpperChest", "Neck") for x in d))]
    for level, applies in cuts:
        pos, vn, dense, tri = split(pos, vn, dense, tri, level, lambda t: applies(names[np.argmax(dense[t], 1)]))
    order = np.argsort(-dense, axis=1)
    keep = order[:, :4]
    W4 = np.take_along_axis(dense, keep, 1)
    W4 /= W4.sum(1, keepdims=True)
    dom = names[keep[:, 0]]

    def along(i, g):  # distance down a limb bone from its joint (i: vertex or point)
        q = pos[i] if np.ndim(i) == 0 else i
        return float(np.dot(q - np.array(REF[g]), np.array(REF[CHILD[g]]) - np.array(REF[g])) /
                     np.linalg.norm(np.array(REF[CHILD[g]]) - np.array(REF[g])))

    def regions(c, g, i):
        """Surfaces a face belongs to, from its centre c and main bone g."""
        y = c[1]
        out = []
        if g.endswith("UpperArm"):
            d = along(c, g)
            if d < CUFF:
                out.append("cuff" if d > SLEEVE else "shirt")
            if d > SLEEVE - 0.03:
                out.append("skin")
        elif g == "Head" and eyes:
            # Hair: above a hairline on the forehead, over the crown and
            # down the back to the nape, and above the ears at the sides.
            r = c - np.mean(np.array(eyes), 0)
            hair = r[1] > 0.045 or r[2] > 0.065 and r[1] > -0.07 or abs(r[0]) > 0.06 and r[2] > 0.02 and r[1] > 0.025
            out.append("hair" if hair else "skin")
        elif g.endswith("LowerArm") or g == "Head":
            out.append("skin")
        elif g in ("Spine", "Chest", "UpperChest", "Neck", "Hips"):
            if y > WAIST_SHIRT and y < NECKLINE:
                out.append("torso")
            if y < WAIST_SHORTS:
                out.append("shorts")
            if y > NECKLINE - 0.03:
                out.append("skin")
        elif g.endswith("UpperLeg"):
            d = along(c, g)
            if d < SHORTS_LEG:
                out.append("shorts")
            if d > SHORTS_LEG - 0.03:
                out.append("skin")
        elif g.endswith("LowerLeg"):
            if y < SOCK_TOP:
                out.append("socks")
            if y > SOCK_TOP - 0.03:
                out.append("skin")
        else:
            out.append("skin")
        return out

    LIFT = {"hair": 0.002, "skin": 0.0, "torso": 0.009, "shirt": 0.01, "cuff": 0.011, "shorts": 0.013, "socks": 0.003}
    surf = {k: {"tri": []} for k in LIFT}
    for fi, t in enumerate(tri):
        i = int(t[np.argmax(W4[t, 0])])
        c = pos[t].mean(0)
        for r in regions(c, dom[i], i):
            surf[r]["tri"].append(t)

    bones_out = KEPT
    result = {"name": name, "source": src.rsplit("/", 1)[-1], "build": build,
              "bones": bones_out, "ref": {b: list(REF[b]) for b in bones_out}, "surfaces": {}}
    if "Head" in KEPT and eyes:
        result["eyes"] = [[float(x) for x in e] for e in eyes]
        result["skull"] = [round(x, 4) for x in skull]
    total = 0
    for name, s in surf.items():
        if not s["tri"]:
            continue
        t = np.array(s["tri"])
        used, inv = np.unique(t.ravel(), return_inverse=True)
        p = pos[used].copy()
        nrm = vn[used]
        lift = LIFT[name]
        if name == "shorts":  # looser towards the hem of each leg
            for k, vi in enumerate(used):
                g = dom[vi]
                if g.endswith("UpperLeg"):
                    p[k] += nrm[k] * (lift + 0.012 * min(1.0, max(0.0, along(vi, g)) / SHORTS_LEG))
                else:
                    p[k] += nrm[k] * lift
        elif name == "torso":  # the hem hangs over the shorts' waistband
            for k in range(len(used)):
                p[k] += nrm[k] * (lift + (0.008 if p[k][1] < WAIST_SHORTS + 0.02 else 0.0))
        else:
            p += nrm * lift
        uv = np.zeros((len(used), 2))
        for k, vi in enumerate(used):
            g = dom[vi]
            q = pos[vi]
            if name in ("shirt", "cuff"):
                a = np.array(REF[g])
                uv[k] = (math.atan2(q[2], q[0] - a[0]) * 0.05, along(vi, g))
            elif name == "socks":
                a = np.array(REF[g])
                uv[k] = (math.atan2(q[0] - a[0], -q[2]) * 0.05, SOCK_TOP - q[1])
            elif name == "torso":
                uv[k] = (math.atan2(q[0], -q[2]) * 0.15, q[1] - REF["Chest"][1] + 0.02)
            else:
                uv[k] = (math.atan2(q[0], -q[2]) * 0.15, q[1])
        total += len(t)
        result["surfaces"][name] = {
            "v": np.round(p, 4).ravel().tolist(),
            "n": np.round(nrm, 3).ravel().tolist(),
            "uv": np.round(uv, 4).ravel().tolist(),
            "b": keep[used].ravel().tolist(),
            "w": np.round(W4[used], 3).ravel().tolist(),
            "i": inv.astype(int).ravel().tolist(),
        }
    with open(out, "w") as f:
        json.dump(result, f, separators=(",", ":"))
    print("wrote %s: %d triangles in %s" % (out, total, ", ".join(result["surfaces"])))


main()
