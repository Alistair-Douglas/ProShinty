class_name ShintyPlayerLook
extends RefCounted
## Everything you see on a ShintyPlayerModel: sculpted body, face and hair,
## kit (fabric shader, numbers, name, crest), boots, helmet and caman.
## ShintyPlayerModel builds the skeleton and animation; it calls dress() to
## hang these meshes on its bones. Nothing here moves bones, so animation and
## physics code can change without touching the look, and the other way round.
##
## Bone-local conventions: torso and head bones point up (+Y), arms and legs
## point down (-Y), the player faces -Z, and 1 unit is 1 metre at 1.80 m tall
## (the skeleton node carries the height scale).

const HAIR_COLOURS := [Color("2a1d14"), Color("4a3020"), Color("6b4a2b"), Color("a0703c"),
	Color("c9a063"), Color("8e3b1e"), Color("151313"), Color("7d7a76")]
const EYE_COLOURS := [Color("3b5f86"), Color("4d6b3b"), Color("5a3b22"), Color("2d2018"), Color("5f7a8a")]
const BOOT_COLOURS := [Color("16161a"), Color("16161a"), Color("f2f2f2"), Color("1d3b8f"), Color("c8102e"), Color("111111")]
const SOLE_COLOURS := [Color("e8e8e8"), Color("f2c400"), Color("16161a"), Color("ff6a13")]
const FLASH_COLOURS := [Color("f2f2f2"), Color("e8ff3a"), Color("ff3d6e"), Color("00c2d1"), Color("c9a54a")]

var m: ShintyPlayerModel
var skel: Skeleton3D
var w := 1.0     # girth
var sw := 1.0    # shoulder/hip width
var seed_val := 0
var detail := true
var seg := 16
var body_file := {}   # an imported body (models/bodies/*.json), or empty for the built one

## Use bodies made in Blender (models/bodies/*.json, from
## tools/blender/import_body.py) when there are any. Set false for the
## built-in body.
static var use_imported_bodies := true
static var body_dir := "res://models/bodies"
static var _body_cache := {}


static func dress(model: ShintyPlayerModel, skeleton: Skeleton3D) -> Node3D:
	var d := ShintyPlayerLook.new()
	d.m = model
	d.skel = skeleton
	d.w = lerpf(0.86, 1.22, model.build)
	d.sw = lerpf(0.94, 1.1, model.build)
	d.seed_val = ShintyPlayerModel._seed_of(model.player_data) if not model.player_data.is_empty() \
		else absi(hash(model.shirt_number * 7919 + int(model.height_cm)))
	d.detail = not model.low_detail
	d.seg = 16 if d.detail else 10
	d.body_file = _pick_body(model.build) if use_imported_bodies and d.detail else {}
	d._body()
	d._kit_details()
	d._head()
	var cam := d._caman()
	_bake(skeleton, cam)
	return cam


## Few draw calls: every piece is baked into one skinned mesh on the skeleton,
## one surface per material (plain-coloured parts share a single surface), and
## a second single-surface copy casts the shadow. Each piece follows its bone
## rigidly, exactly as it did hanging from a BoneAttachment3D; the caman rides
## on its own "Caman" bone, which ShintyPlayerModel poses every frame.
static func _bake(skeleton: Skeleton3D, cam: Node3D) -> void:
	var surfaces := {}   # material (or &"solid") -> _Part
	var shadow := _Part.new()
	var joints := _joints(skeleton)
	var caman_bone := skeleton.find_bone("Caman")
	for holder in skeleton.get_children():
		var bone := -1
		var base := Transform3D.IDENTITY
		if holder is BoneAttachment3D:
			bone = skeleton.find_bone(holder.bone_name)
			base = skeleton.get_bone_global_rest(bone)
		elif holder == cam:
			bone = caman_bone
		if bone < 0:
			continue
		for c in holder.get_children():
			if not (c is MeshInstance3D):
				continue
			var mat: Material = c.material_override
			var key: Variant = &"solid" if mat is StandardMaterial3D else mat
			if not surfaces.has(key):
				surfaces[key] = _Part.new()
			var xf: Transform3D = base * c.transform
			# Remember the size of what hung here (in the holder's space) for
			# code that fits things to the body, like ShintyKitSponsor.
			var local: AABB = c.transform * c.mesh.get_aabb()
			holder.set_meta("mesh_aabb", holder.get_meta("mesh_aabb").merge(local) if holder.has_meta("mesh_aabb") else local)
			surfaces[key].add(c.mesh, xf, bone, mat, joints)
			var size: Vector3 = c.mesh.get_aabb().size
			if maxf(size.x, maxf(size.y, size.z)) > 0.03:  # eyes, studs and laces cast nothing you'd see
				shadow.add(c.mesh, xf, bone, null, joints)
			holder.remove_child(c)
			c.free()
	# An imported body comes with its own bones and weights.
	for r in skeleton.get_meta("raw_parts", []):
		var key: Variant = r[0]
		if not surfaces.has(key):
			surfaces[key] = _Part.new()
		surfaces[key].add_raw(r[1], r[2], r[3], r[4], r[5], r[6], r[7])
		shadow.add_raw(r[1], r[2], r[3], r[4], r[5], r[6])
	if skeleton.has_meta("raw_parts"):
		skeleton.remove_meta("raw_parts")
	var mesh := ArrayMesh.new()
	for key in surfaces:
		surfaces[key].commit(mesh, true)
		mesh.surface_set_material(mesh.get_surface_count() - 1, ShintyMesh.solid_vc() if key is StringName else key)
	var skin := skeleton.create_skin_from_rest_transforms()
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = mesh
	body.skin = skin
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	skeleton.add_child(body)
	body.skeleton = NodePath("..")
	var shadow_mesh := ArrayMesh.new()
	shadow.commit(shadow_mesh, false)
	var caster := MeshInstance3D.new()
	caster.name = "ShadowCaster"
	caster.mesh = shadow_mesh
	caster.skin = skin
	caster.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	skeleton.add_child(caster)
	caster.skeleton = NodePath("..")


## Where one bone bends against the next: [upper, lower, joint position,
## axis pointing into the lower bone, blend radius, reach], in skeleton space.
## Vertices of either bone near the joint follow both, so elbows, knees,
## wrists, ankles and the spine bend smoothly instead of creasing.
const JOINTS := [
	["LeftUpperArm", "LeftLowerArm", 0.06, 0.1], ["RightUpperArm", "RightLowerArm", 0.06, 0.1],
	["LeftLowerArm", "LeftHand", 0.03, 0.06], ["RightLowerArm", "RightHand", 0.03, 0.06],
	["LeftUpperLeg", "LeftLowerLeg", 0.07, 0.12], ["RightUpperLeg", "RightLowerLeg", 0.07, 0.12],
	["LeftLowerLeg", "LeftFoot", 0.03, 0.08], ["RightLowerLeg", "RightFoot", 0.03, 0.08],
	["Hips", "Spine", 0.05, 0.25], ["Spine", "Chest", 0.05, 0.25], ["Chest", "UpperChest", 0.05, 0.25],
	["UpperChest", "Neck", 0.03, 0.1], ["Neck", "Head", 0.03, 0.1],
	# Shoulders and hips swing too far to blend both ways (the torso would be
	# dragged out with the arm), so only the top of the sleeve and of the
	# shorts leg lean back on the body, which keeps them from poking out.
	["UpperChest", "LeftUpperArm", 0.06, 0.12, true], ["UpperChest", "RightUpperArm", 0.06, 0.12, true],
	["Hips", "LeftUpperLeg", 0.07, 0.16, true], ["Hips", "RightUpperLeg", 0.07, 0.16, true],
]


static func _joints(skeleton: Skeleton3D) -> Array:
	var out := []
	for j in JOINTS:
		var up := skeleton.find_bone(j[0])
		var lo := skeleton.find_bone(j[1])
		var at := skeleton.get_bone_global_rest(lo).origin
		# Limbs hang down (-Y) and the spine and neck point up (+Y) at rest.
		var axis := Vector3.UP if j[1] in ["Spine", "Chest", "UpperChest", "Neck", "Head"] else Vector3.DOWN
		out.append([up, lo, at, axis, j[2], j[3], j.size() > 4])
	return out


## Bones and weights for a vertex at `p` (skeleton space) on a piece that
## hangs from `bone`.
static func _weigh(p: Vector3, bone: int, joints: Array) -> Array:
	for j in joints:
		if bone != j[1] and (bone != j[0] or j[6]):
			continue
		var d: Vector3 = p - j[2]
		if d.length() > j[5]:
			continue
		var t: float = d.dot(j[3])
		var r: float = j[4]
		if t < -r or t > r:
			continue
		var w_lo := smoothstep(-r, r, t)
		if j[6]:  # one-sided: at most half the weight goes back to the body
			w_lo = 0.5 + 0.5 * smoothstep(-r, r, t)
		# A piece on the upper bone reaching past the joint (a sleeve over the
		# elbow) still leans on its own bone a little, and the other way round.
		return [j[0], j[1], 1.0 - w_lo, w_lo]
	return [bone, bone, 1.0, 0.0]


## Vertex data for one surface of the baked player.
class _Part:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var colors := PackedColorArray()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var idx := PackedInt32Array()

	func add(mesh: Mesh, xf: Transform3D, bone: int, mat: Material, joints: Array) -> void:
		var nb := xf.basis.inverse().transposed()
		var col := Color.WHITE
		var rm := Vector2(1, 0)
		if mat is StandardMaterial3D:
			col = mat.albedo_color
			col.a = mat.clearcoat if mat.clearcoat_enabled else 0.0
			rm = Vector2(mat.roughness, mat.metallic)
		for s in mesh.get_surface_count():
			var a := mesh.surface_get_arrays(s)
			var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var n: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
			var uv: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
			var first := verts.size()
			for i in v.size():
				var p := xf * v[i]
				verts.append(p)
				norms.append((nb * n[i]).normalized() if n.size() > i else Vector3.UP)
				uvs.append(uv[i] if uv.size() > i else Vector2.ZERO)
				uv2s.append(rm)
				colors.append(col)
				var bw: Array = ShintyPlayerLook._weigh(p, bone, joints)
				bones.append_array([bw[0], bw[1], 0, 0])
				weights.append_array([bw[2], bw[3], 0.0, 0.0])
			var src: PackedInt32Array = a[Mesh.ARRAY_INDEX]
			if src.is_empty():
				src = PackedInt32Array(range(v.size()))
			for i in src:
				idx.append(first + i)

	func add_raw(v: PackedVector3Array, n: PackedVector3Array, uv: PackedVector2Array, b: PackedInt32Array,
			wt: PackedFloat32Array, src: PackedInt32Array, col := PackedColorArray()) -> void:
		var first := verts.size()
		verts.append_array(v)
		norms.append_array(n)
		uvs.append_array(uv)
		for i in v.size():
			uv2s.append(Vector2(1, 0))
			colors.append(col[i] if i < col.size() else Color.WHITE)
		bones.append_array(b)
		weights.append_array(wt)
		for i in src:
			idx.append(first + i)

	func commit(mesh: ArrayMesh, shaded: bool) -> void:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_BONES] = bones
		arrays[Mesh.ARRAY_WEIGHTS] = weights
		arrays[Mesh.ARRAY_INDEX] = idx
		if shaded:
			arrays[Mesh.ARRAY_NORMAL] = norms
			arrays[Mesh.ARRAY_TEX_UV] = uvs
			arrays[Mesh.ARRAY_TEX_UV2] = uv2s
			arrays[Mesh.ARRAY_COLOR] = colors
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


func _pick(list: Array, salt: int) -> Variant:
	return list[absi(hash(seed_val + salt * 104729)) % list.size()]


func _chance(salt: int) -> float:
	return float(absi(hash(seed_val * 31 + salt)) % 1000) / 1000.0


# --- Body ------------------------------------------------------------------------

func _body() -> void:
	var skin := ShintyMesh.skin(m.skin_color)
	var shirt_pattern := _team_pattern()
	var shirt := ShintyMesh.fabric(m.shirt_color, m.trim_color, Vector2(-9, -9), Vector2(-9, -9), shirt_pattern[0], shirt_pattern[1])
	var chest_band := ShintyMesh.fabric(m.shirt_color, m.trim_color, Vector2(0.105, 0.14) if shirt_pattern[0] == 0 else Vector2(-9, -9),
		Vector2(-9, -9), shirt_pattern[0], shirt_pattern[1])
	var shorts := ShintyMesh.fabric(m.shorts_color, m.shirt_color, Vector2(-9, -9), Vector2(-9, -9), 0, 0.1, 0.75)
	var socks := ShintyMesh.fabric(m.socks_color, m.trim_color, Vector2(0.0, 0.03), Vector2(0.055, 0.075), 0, 0.1, 0.9)
	socks.set_shader_parameter("ribs", 0.0004)
	if not body_file.is_empty():
		var look := _face_look()
		var hair_col: Color = look.hair.lerp(m.skin_color, 0.45) if look.style == "buzz" else look.hair
		# Facial hair is painted on the imported face's beard zones (from the
		# converter: 0.5 jaw and cheeks, 1 chin and upper lip).
		var fh_col: Color = look.hair.lerp(m.skin_color, 0.15)
		var face_skin: Material = skin
		match look.facial:
			"stubble": face_skin = ShintyMesh.skin(m.skin_color, fh_col, 0.4, false, 0.45)
			"beard": face_skin = ShintyMesh.skin(m.skin_color, fh_col, 0.4, false, 0.85)
			"goatee": face_skin = ShintyMesh.skin(m.skin_color, fh_col, 0.8, false, 0.85)
			"moustache": face_skin = ShintyMesh.skin(m.skin_color, fh_col, 2.0, true, 0.85)
		_imported_body({"skin": face_skin, "hair": ShintyMesh.solid(hair_col, 0.85), "torso": chest_band, "shirt": shirt, "cuff": ShintyMesh.fabric(m.trim_color, m.trim_color),
			"shorts": shorts, "socks": socks})
		return

	# Pelvis in shorts, with the shirt hem hanging over the waistband.
	var hips := _attach("Hips")
	_mesh(hips, _loft([
		[-0.14, 0.13 * w, 0.085 * w], [-0.1, 0.158 * w * sw, 0.1 * w], [-0.03, 0.166 * w * sw, 0.108 * w],
		[0.04, 0.158 * w, 0.104 * w], [0.1, 0.146 * w, 0.098 * w]], seg, 2.4), shorts)
	# Abdomen and chest: the shirt, sculpted a little at the chest and back.
	var spine := _attach("Spine")
	_mesh(spine, _loft([
		[-0.075, 0.158 * w, 0.107 * w], [-0.03, 0.156 * w, 0.106 * w], [0.05, 0.148 * w, 0.1 * w],
		[0.15, 0.156 * w, 0.106 * w, -0.004]], seg, 2.3), shirt)
	var chest := _attach("Chest")
	_mesh(chest, _loft([
		[-0.02, 0.156 * w, 0.106 * w, -0.004], [0.05, 0.168 * w * sw, 0.114 * w, -0.012],
		[0.1, 0.178 * w * sw, 0.116 * w, -0.014], [0.16, 0.184 * w * sw, 0.11 * w, -0.01]], seg, 2.3), chest_band)
	var upper := _attach("UpperChest")
	_mesh(upper, _loft([
		[-0.02, 0.184 * w * sw, 0.11 * w, -0.01], [0.04, 0.192 * w * sw, 0.108 * w, -0.008],
		[0.08, 0.2 * w * sw, 0.098 * w, 0.0], [0.105, 0.18 * w * sw, 0.088 * w, 0.003], [0.122, 0.145 * w * sw, 0.078 * w, 0.005],
		[0.135, 0.1 * w, 0.066 * w, 0.006], [0.155, 0.062, 0.052, 0.004]], seg, 2.3), shirt)
	# Collar in the trim colour
	_mesh(upper, _loft([[0.13, 0.066, 0.056, 0.003], [0.165, 0.058, 0.05, 0.0]], seg, 2.0, true),
		ShintyMesh.fabric(m.trim_color, m.trim_color))

	for side in ["Left", "Right"]:
		var sgn := -1.0 if side == "Left" else 1.0
		# Upper arm: deltoid in the shirt, short sleeve with a trim cuff, bicep below.
		var ua := _attach(side + "UpperArm")
		_mesh(ua, _loft([
			[0.03, 0.03 * w, 0.034 * w, 0.0, -0.012 * (-1.0 if side == "Left" else 1.0)], [0.0, 0.058 * w, 0.06 * w],
			[-0.06, 0.062 * w, 0.059 * w],
			[-0.15, 0.058 * w, 0.056 * w], [-0.17, 0.059 * w, 0.057 * w]], seg), shirt)
		_mesh(ua, _loft([[-0.155, 0.06 * w, 0.058 * w], [-0.185, 0.06 * w, 0.058 * w]], seg, 2.0, true),
			ShintyMesh.fabric(m.trim_color, m.trim_color))
		_mesh(ua, _loft([
			[-0.14, 0.05 * w, 0.052 * w], [-0.2, 0.049 * w, 0.051 * w, -0.004], [-0.26, 0.043 * w, 0.044 * w],
			[-0.3, 0.04 * w, 0.041 * w]], seg), skin)
		# Forearm: thick near the elbow, tapering to the wrist.
		var la := _attach(side + "LowerArm")
		_mesh(la, _loft([
			[0.02, 0.04 * w, 0.041 * w], [-0.05, 0.046 * w, 0.042 * w], [-0.12, 0.041 * w, 0.036 * w],
			[-0.22, 0.031 * w, 0.026 * w], [-0.275, 0.027, 0.022]], seg), skin)
		# Hand: gripping the caman. When it holds the stick the hand bone
		# is turned so the shaft runs along its X, HAND_GRIP below the wrist.
		_grip_hand(_attach(side + "Hand"), side, skin)

	for side in ["Left", "Right"]:
		# Thigh with a front quad bulge; loose shorts leg over the top.
		var ul := _attach(side + "UpperLeg")
		_mesh(ul, _loft([
			[0.04, 0.078 * w, 0.08 * w], [-0.05, 0.084 * w, 0.086 * w, -0.004], [-0.16, 0.078 * w, 0.08 * w, -0.008],
			[-0.3, 0.064 * w, 0.064 * w, -0.004], [-0.4, 0.052 * w, 0.054 * w], [-0.455, 0.05 * w, 0.052 * w]], seg), skin)
		_mesh(ul, _loft([
			[0.05, 0.098 * w, 0.098 * w], [-0.08, 0.1 * w, 0.1 * w, -0.004], [-0.2, 0.098 * w, 0.096 * w, -0.006]], seg, 2.0, true), shorts)
		# Shin: calf muscle behind, sock over most of it with trim hoops at the top.
		var ll := _attach(side + "LowerLeg")
		_mesh(ll, _loft([
			[0.03, 0.05 * w, 0.052 * w], [-0.05, 0.053 * w, 0.058 * w, 0.01], [-0.14, 0.052 * w, 0.06 * w, 0.014],
			[-0.26, 0.042 * w, 0.045 * w, 0.006], [-0.38, 0.032 * w, 0.034 * w], [-0.44, 0.032, 0.036]], seg), skin)
		_mesh(ll, _sock_mesh(), socks, Vector3(0, -0.07, 0))
		# Boot: shaped upper, contrasting sole, a few studs.
		var foot := _attach(side + "Foot")
		_boot(foot, 1.0 if side == "Left" else -1.0)


## A body made in Blender, in place of the built one. The file holds one
## mesh per kit part, already bent into the skeleton's rest pose at 1.80 m
## and weighted to its bones; here it is fitted to this player (shoulder and
## hip width, girth) and handed to _bake with its own weights. Hands, boots,
## head and helmet, collar and the kit's numbers stay as built.
func _imported_body(mats: Dictionary) -> void:
	var names: Array = body_file["bones"]
	var bone_of := PackedInt32Array()
	var shift := []      # this skeleton's joints minus the file's
	var axis_a := []
	var axis_b := []
	var refs: Dictionary = body_file["ref"]
	for n in names:
		var b := skel.find_bone(n)
		bone_of.append(b)
		var at := skel.get_bone_global_rest(b).origin
		var r: Array = refs[n]
		shift.append(at - Vector3(r[0], r[1], r[2]))
		axis_a.append(at)
		var child := -1
		for c in skel.get_bone_children(b):
			if skel.get_bone_name(c) != "Caman":
				child = c
				break
		axis_b.append(skel.get_bone_global_rest(child).origin if child >= 0 else at + Vector3.UP * 0.1)
	# Girth relative to the build the body was made at.
	var k := w / lerpf(0.86, 1.22, float(body_file.get("build", 0.5)))
	k = clampf(lerpf(1.0, k, 0.6), 0.9, 1.12)
	var parts := []
	var torso_pts := PackedVector3Array()
	var torso_bones := PackedInt32Array()
	var torso_weights := PackedFloat32Array()
	for key in body_file["surfaces"]:
		if not mats.has(key):
			continue
		var sd: Dictionary = body_file["surfaces"][key]
		var v: Array = sd["v"]
		var nr: Array = sd["n"]
		var uv: Array = sd["uv"]
		var bi: Array = sd["b"]
		var wt: Array = sd["w"]
		var count := v.size() / 3
		var verts := PackedVector3Array()
		var norms := PackedVector3Array()
		var uvs := PackedVector2Array()
		var bones := PackedInt32Array()
		var weights := PackedFloat32Array()
		verts.resize(count)
		norms.resize(count)
		uvs.resize(count)
		bones.resize(count * 4)
		weights.resize(count * 4)
		for i in count:
			var p := Vector3(v[i * 3], v[i * 3 + 1], v[i * 3 + 2])
			var main: int = bi[i * 4]
			# Girth: out from the main bone's axis.
			var a: Vector3 = axis_a[main]
			var ab: Vector3 = axis_b[main] - a
			var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
			var on := a + ab * t
			p = on + (p - on) * k
			var off := Vector3.ZERO
			for j in 4:
				off += shift[bi[i * 4 + j]] * float(wt[i * 4 + j])
				bones[i * 4 + j] = bone_of[bi[i * 4 + j]]
				weights[i * 4 + j] = wt[i * 4 + j]
			p += off
			verts[i] = p
			norms[i] = Vector3(nr[i * 3], nr[i * 3 + 1], nr[i * 3 + 2])
			uvs[i] = Vector2(uv[i * 2], uv[i * 2 + 1])
			if key == "torso":
				torso_pts.append(p)
				for j in 4:
					torso_bones.append(bones[i * 4 + j])
					torso_weights.append(weights[i * 4 + j])
		# Skin shading baked by the converter (flush, lips, beard zones).
		var cols := PackedColorArray()
		var c: Array = sd.get("c", [])
		for i in c.size() / 4:
			cols.append(Color(c[i * 4], c[i * 4 + 1], c[i * 4 + 2], c[i * 4 + 3]))
		parts.append([mats[key], verts, norms, uvs, bones, weights, PackedInt32Array(sd["i"]), cols])
	skel.set_meta("raw_parts", parts)
	_torso_pts = torso_pts

	var trim := mats["cuff"] as Material
	for b in ["Hips", "Spine", "Chest", "UpperChest"]:
		_attach(b)
	# Shirt front for the sponsor print, across the chest as on real shirts
	# (ShintyKitSponsor reads sponsor_holder, then mesh_aabb and front_curve).
	var holder := _find_attach("Chest")
	var at := skel.get_bone_global_rest(skel.find_bone("Chest")).origin
	var box := AABB()
	var first := true
	for p in torso_pts:
		if p.y > at.y - 0.04 and p.y < at.y + 0.12:
			if first:
				box = AABB(p - at, Vector3.ZERO)
				first = false
			else:
				box = box.expand(p - at)
	if not first:
		skel.set_meta("sponsor_holder", String(holder.name))
		# The shirt's skinning, so the print bends with it instead of riding
		# one bone (in skeleton rest space).
		skel.set_meta("torso_skin", [torso_pts, torso_bones, torso_weights])
		holder.set_meta("mesh_aabb", box)
		# The shirt front across the sponsor's height, for the print to follow.
		var y := box.position.y + box.size.y * 0.5
		var bins := {}
		for p in torso_pts:
			var q := p - at
			if q.z < 0.0 and absf(q.y - y) < 0.07:
				var bin := roundi(q.x / 0.02)
				bins[bin] = minf(bins.get(bin, 0.0), q.z)
		var keys := bins.keys()
		keys.sort()
		var curve := PackedVector2Array()
		for bin in keys:  # the front-most of each bin and its neighbours, so folds stay behind
			curve.append(Vector2(bin * 0.02, minf(bins[bin], minf(bins.get(bin - 1, 0.0), bins.get(bin + 1, 0.0)))))
		holder.set_meta("front_curve", curve)
	var upper := _find_attach("UpperChest")
	_mesh(upper, _loft([[0.13, 0.066, 0.056, 0.003], [0.165, 0.058, 0.05, 0.0]], seg, 2.0, true), trim)
	for side in ["Left", "Right"]:
		_attach(side + "UpperArm")
		_attach(side + "LowerArm")
		_grip_hand(_attach(side + "Hand"), side, mats["skin"])
		_attach(side + "UpperLeg")
		_attach(side + "LowerLeg")
		_boot(_attach(side + "Foot"), 1.0 if side == "Left" else -1.0)


var _torso_pts := PackedVector3Array()


## Depth of the shirt surface at a spot on a torso bone, for things printed
## on it: the built body's guess, or the imported body's actual surface
## (the outermost point within span either side, so a wide print clears
## the shoulder blades).
func _shirt_z(holder: Node3D, guess: Vector3, lift := 0.002, span := 0.03) -> float:
	if _torso_pts.is_empty():
		return guess.z
	var at := skel.get_bone_global_rest(skel.find_bone((holder as BoneAttachment3D).bone_name)).origin
	var q := at + guess
	var best := 0.0
	var found := false
	for p in _torso_pts:
		if absf(p.x - q.x) < span and absf(p.y - q.y) < 0.03 and signf(p.z) == signf(guess.z):
			if not found or absf(p.z) > absf(best):
				best = p.z
				found = true
	return (best - at.z + signf(guess.z) * lift) if found else guess.z


## The imported body for this build: lean, average or stocky, by the file's
## name; any body if those aren't all there. Empty when there are none.
static func _pick_body(build: float) -> Dictionary:
	var dir := body_dir
	if _body_cache.get("_dir", "") != dir:
		_body_cache = {"_dir": dir}
	if not _body_cache.has("_list"):
		var files := []
		if DirAccess.dir_exists_absolute(dir):
			for f in DirAccess.get_files_at(dir):
				if f.ends_with(".json"):
					files.append(f)
		files.sort()
		_body_cache["_list"] = files
	var files: Array = _body_cache["_list"]
	if files.is_empty():
		return {}
	var want := "lean" if build < 0.36 else ("stocky" if build > 0.64 else "average")
	var name: String = files[0]
	for f in files:
		if want in f:
			name = f
	if not _body_cache.has(name):
		var data = JSON.parse_string(FileAccess.get_file_as_string(dir + "/" + name))
		_body_cache[name] = data if data is Dictionary and data.has("surfaces") else {}
	return _body_cache[name]


## A hand closed round the shaft, in the hand bone's grip frame: the shaft
## runs along X (thumb side towards the bas) through (0, -HAND_GRIP, 0), the
## wrist at the origin. Four fingers curl from the knuckles over the far side
## of the shaft and tuck into the palm; the thumb wraps the other way over
## the index finger. The back of the hand faces +Z on the right hand and -Z
## on the left.
func _grip_hand(hand: Node3D, side: String, skin: Material) -> void:
	var g := Vector3(0, -ShintyPlayerModel.HAND_GRIP, 0)
	var bz := 1.0 if side == "Right" else -1.0
	var hs := lerpf(0.95, 1.06, m.build)  # bigger hands on bigger players
	# Palm and back of the hand, wrist to knuckles, closed over the shaft.
	_mesh(hand, _loft([
		[0.012, 0.026, 0.02, 0.0], [-0.02, 0.036 * hs, 0.024, 0.0],
		[-0.05, 0.04 * hs, 0.028, -bz * 0.002], [-0.07, 0.039 * hs, 0.022, bz * 0.006]], seg, 2.6), skin)
	var r_wrap := 0.0265  # round the taped shaft (up to 1.75 cm radius on a thick keeper's caman)
	var fingers := [[0.026, 0.0088, 1.0], [0.009, 0.0093, 1.04], [-0.009, 0.009, 1.0], [-0.025, 0.008, 0.9]]
	if not detail:
		fingers = [[0.0, 0.009, 1.0]]  # one band for all four, 3.4 cm wide
	for f in fingers:
		var pts := PackedVector3Array()
		var rad := PackedVector2Array()
		var steps := 6 if detail else 4
		for k in steps + 1:
			var u := float(k) / steps
			# From the knuckle on the back of the hand, round the far side of
			# the shaft, into the palm.
			var ang := lerpf(deg_to_rad(15.0), deg_to_rad(178.0 * f[2]), u)
			# Out at the knuckle, snug round the shaft, the tip pressed in.
			var rr: float = r_wrap * (lerpf(1.18, 1.0, u * 3.0) if u < 0.34 else lerpf(1.0, 0.86, (u - 0.34) / 0.66))
			pts.append(g + Vector3(f[0] * hs, -sin(ang) * rr, bz * cos(ang) * rr))
			var t: float = f[1] * lerpf(1.0, 0.8, u)
			rad.append(Vector2(t if detail else 0.034 * hs, t))
		# Mirrored on the right hand, so flip the frame to keep the faces outward.
		_mesh(hand, ShintyMesh.sweep(pts, rad, 6, 2.0, false, Vector3.RIGHT * -bz), skin)
	# Thumb: from the heel of the hand on the thumb side, round the near side
	# of the shaft, its tip resting on the curled index finger.
	var th := PackedVector3Array([Vector3(0.03, -0.018, -bz * 0.016), Vector3(0.04, -0.045, -bz * 0.02),
		Vector3(0.036, -0.074, -bz * 0.02), Vector3(0.024, -0.093, -bz * 0.008)])
	var tr := PackedVector2Array([Vector2(0.013, 0.012), Vector2(0.0105, 0.0105), Vector2(0.0095, 0.009), Vector2(0.008, 0.0075)])
	for i in th.size():
		th[i].x *= hs
	_mesh(hand, ShintyMesh.sweep(th, tr, 6 if detail else 4, 2.0, false, Vector3.RIGHT * -bz), skin)


func _sock_mesh() -> ArrayMesh:
	# v runs downward from the sock top (UV v = 0 at the top) so the hoops sit there.
	var rings := [
		[0.0, 0.056 * w, 0.063 * w, 0.013], [-0.07, 0.056 * w, 0.064 * w, 0.014], [-0.19, 0.047 * w, 0.051 * w, 0.006],
		[-0.31, 0.038 * w, 0.04 * w, 0.0], [-0.38, 0.037, 0.04, 0.002]]
	return _loft(rings, seg, 2.0, true)


func _boot(foot: Node3D, inside: float) -> void:
	var col: Color = _pick(BOOT_COLOURS, 3)
	var sole_col: Color = _pick(SOLE_COLOURS, 4)
	var flash_col: Color = _pick(FLASH_COLOURS, 6)
	if flash_col.is_equal_approx(col):
		flash_col = sole_col
	# Foot bone space: ankle at the origin, grass at y = -0.06, toe towards -Z.
	# Stations heel to toe: [z, half width, bottom, top, x offset]. A low-cut
	# football boot: heel counter up round the ankle, a lace panel falling
	# away over the instep, a wide forefoot turned in at the big toe and a
	# slim toe with a little spring.
	var t := inside * 0.006
	var upper_st := [
		[0.078, 0.012, -0.049, -0.008], [0.074, 0.026, -0.05, 0.012], [0.064, 0.036, -0.05, 0.028],
		[0.042, 0.04, -0.05, 0.032], [0.012, 0.041, -0.05, 0.03], [-0.02, 0.043, -0.05, 0.022],
		[-0.055, 0.046, -0.05, 0.006, t * 0.3], [-0.095, 0.049, -0.05, -0.008, t * 0.6],
		[-0.135, 0.047, -0.049, -0.018, t], [-0.17, 0.04, -0.048, -0.026, t * 1.2],
		[-0.192, 0.029, -0.046, -0.031, t * 1.4], [-0.204, 0.016, -0.044, -0.035, t * 1.5],
		[-0.209, 0.006, -0.043, -0.038, t * 1.5]]
	_mesh(foot, ShintyMesh.shoe(upper_st, seg + 2, 2.4, 6.0), ShintyMesh.solid(col, 0.4, 0.0, 0.35))
	# Sole plate: a little proud of the upper all round, heel slightly thicker.
	var sole_st := []
	for st in upper_st:
		var z: float = st[0]
		var hw: float = st[1] + 0.004 if st[1] > 0.02 else st[1] + 0.002
		var thick := lerpf(0.012, 0.008, clampf(-z / 0.2, 0.0, 1.0))
		var lift := maxf(0.0, (-z - 0.17) * 0.25)  # toe spring
		sole_st.append([z + signf(z) * 0.002, hw, -0.06 + lift, -0.06 + lift + thick, st[4] if st.size() > 4 else 0.0])
	_mesh(foot, ShintyMesh.shoe(sole_st, 10 if detail else 8, 8.0, 8.0), ShintyMesh.solid(sole_col, 0.55))
	if not detail:
		return
	# Side flash on both sides, from under the heel collar forward along the midfoot.
	var flash := ShintyMesh.solid(flash_col, 0.45)
	for sx in [-1.0, 1.0]:
		var pts := PackedVector3Array()
		var rad := PackedVector2Array()
		for k in 6:
			var u := k / 5.0
			var z := lerpf(0.05, -0.1, u)
			var hw := _station_width(upper_st, z)
			pts.append(Vector3(sx * (hw + 0.0012), lerpf(-0.012, -0.036, u) + sin(u * PI) * 0.01, z))
			rad.append(Vector2(lerpf(0.006, 0.0025, u), 0.0015))
		_mesh(foot, ShintyMesh.sweep(pts, rad, 6, 3.0, false, Vector3.UP), flash)
	# Laces across the lace panel, following the top of the upper.
	var lace := ShintyMesh.solid(Color("f0f0f0") if col.get_luminance() < 0.5 else Color("2a2a2e"), 0.8)
	for i in 5:
		var z := -0.012 - i * 0.017
		var top := _station_top(upper_st, z)
		var l := _mesh(foot, _loft([[-0.017, 0.003, 0.003], [0.017, 0.003, 0.003]], 6), lace, Vector3(0, top + 0.0025, z))
		l.rotation = Vector3(-0.35, 0, PI / 2)
	# Studs: conical, four under the forefoot and two under the heel.
	var stud := ShintyMesh.solid(Color("d8d8d8"), 0.3, 0.7)
	for sp in [Vector3(0.028, 0, 0.05), Vector3(-0.028, 0, 0.05), Vector3(0.03, 0, -0.08),
			Vector3(-0.03, 0, -0.08), Vector3(0.024, 0, -0.14), Vector3(-0.024, 0, -0.14)]:
		_mesh(foot, _loft([[0.0, 0.0075, 0.0075], [-0.009, 0.005, 0.005]], 6), stud, sp + Vector3(0, -0.059, 0))


static func _station_width(st: Array, z: float) -> float:
	return _station_value(st, z, 1)


static func _station_top(st: Array, z: float) -> float:
	return _station_value(st, z, 3)


static func _station_value(st: Array, z: float, k: int) -> float:
	for i in st.size() - 1:
		if z <= st[i][0] and z >= st[i + 1][0]:
			return lerpf(st[i][k], st[i + 1][k], inverse_lerp(st[i][0], st[i + 1][0], z))
	return st[0][k] if z > st[0][0] else st[st.size() - 1][k]


## Shirt pattern from team data: colors.pattern = "hoops" or "stripes".
func _team_pattern() -> Array:
	var p := str(m.get_meta("kit_pattern", "")).to_lower()
	if m.is_keeper:
		return [0, 0.12]
	if p == "hoops":
		return [1, 0.14]
	if p == "stripes":
		return [2, 0.06]
	return [0, 0.12]


# --- Kit details -----------------------------------------------------------------

func _kit_details() -> void:
	if not detail:
		return
	var upper := _find_attach("UpperChest")
	var chest := _find_attach("Chest")
	# Small number and crest: up near the collarbones when the sponsor goes
	# across the chest (imported bodies), else on the chest.
	var hi := 0.15 if skel.has_meta("sponsor_holder") else 0.02
	# Number on the back and a small one on the front (shinty shirts carry no
	# names).
	if m.shirt_number > 0:
		var back := _label(str(m.shirt_number), 110, 0.0021)
		back.position = Vector3(0, 0.0, _shirt_z(upper, Vector3(0, 0.0, 0.112 * w), 0.002, 0.075))
		upper.add_child(back)
		var front := _label(str(m.shirt_number), 64, 0.0012)
		front.position = Vector3(0.075 * w, hi, _shirt_z(chest, Vector3(0.075 * w, hi, -0.118 * w)))
		front.rotation.y = PI
		chest.add_child(front)
	# Club crest on the left breast: a shield in the trim colour.
	var crest := _loft([[0.0, 0.004, 0.022], [0.02, 0.018, 0.024], [0.045, 0.02, 0.022], [0.052, 0.02, 0.02]], 10, 3.0)
	var ci := _mesh(chest, crest, ShintyMesh.solid(m.trim_color, 0.6),
		Vector3(-0.075 * w, hi + 0.01, _shirt_z(chest, Vector3(-0.075 * w, hi + 0.01, -0.114 * w), 0.007, 0.04)))
	ci.rotation = Vector3(PI / 2 - 0.1, 0, 0)
	ci.scale = Vector3(1, 1, 0.12)


func _label(text: String, size: int, px: float) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = px
	l.outline_size = int(size * 0.12)
	l.modulate = m.trim_color
	l.outline_modulate = m.shirt_color.darkened(0.5)
	l.double_sided = false
	l.shaded = true
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Too small to read beyond this, so don't draw it (metres; x1.1 in yards).
	l.visibility_range_end = 45.0
	l.visibility_range_end_margin = 5.0
	l.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Oswald", "Bebas Neue", "Impact", "Arial Narrow", "DejaVu Sans Condensed", "Sans"])
	f.font_weight = 800
	l.font = f
	return l


# --- Head, face, hair ----------------------------------------------------------------

func _head() -> void:
	var skin := ShintyMesh.skin(m.skin_color)
	var look := _face_look()
	var hair_col: Color = look.hair
	var style: String = look.style
	var facial: String = look.facial
	var hair := ShintyMesh.solid(hair_col, 0.85)
	var neck := _attach("Neck")
	if body_file.is_empty():  # an imported body brings its own neck
		_mesh(neck, _loft([[-0.02, 0.058, 0.056], [0.06, 0.052, 0.05, 0.004], [0.13, 0.05, 0.048, 0.008]], seg), skin)

	var head := _attach("Head")
	var c := Vector3(0, 0.11, 0)
	# An imported body may bring its own head and face (MPFB's): then only
	# the eyes, eyebrows, hair and helmet are added here.
	var own_head: bool = body_file.get("bones", []).has("Head")
	var fit := 1.0  # helmet and hair size for the imported head
	if own_head and body_file.has("skull"):
		var sk: Array = body_file["skull"]
		c = Vector3(sk[0], sk[1], sk[2])
		fit = sk[3]
	# Skull and face in one sculpted piece: chin, jaw, cheekbones, brow. Each
	# player's face is a little different: jaw width, chin length, cheeks.
	var jaw: float = (0.066 + 0.01 * m.build) * look.jaw
	var chin: float = look.chin
	var cheek: float = look.cheek
	var face := [
		[-0.112 - chin, 0.006, 0.005, -0.087], [-0.106 - chin, 0.022 * look.jaw, 0.019, -0.08],
		[-0.1 - chin * 0.8, 0.034 * look.jaw, 0.03, -0.074], [-0.08 - chin * 0.4, jaw * 0.85, 0.058, -0.045],
		[-0.05, jaw, 0.08, -0.018], [-0.015, 0.074 * cheek, 0.094, -0.006], [0.02, 0.079, 0.1, 0.0],
		[0.06, 0.079, 0.1, 0.006], [0.095, 0.068, 0.086, 0.01], [0.118, 0.04, 0.052, 0.012],
		[0.128, 0.01, 0.014, 0.012]]
	if not own_head:
		_mesh(head, _loft(face, seg + 2, 2.1), skin, c)
	# Nose: narrow bridge, rounded tip, wider at the nostrils.
	var ns: float = look.nose
	var nose := ShintyMesh.sweep(PackedVector3Array([Vector3(0, 0.032, -0.088), Vector3(0, 0.008, -0.1 + (1.0 - ns) * 0.012),
		Vector3(0, -0.012, -0.109 + (1.0 - ns) * 0.016), Vector3(0, -0.022, -0.106 + (1.0 - ns) * 0.012)]),
		PackedVector2Array([Vector2(0.0065, 0.005), Vector2(0.008, 0.008) * ns, Vector2(0.0125, 0.011) * ns, Vector2(0.013, 0.007) * ns]), 8)
	if not own_head:
		_mesh(head, nose, skin, c)
	if detail:
		# Brow ridge (under the helmet's front edge when one is worn).
		if not m.wear_helmet and not own_head:
			_mesh(head, ShintyMesh.sweep(PackedVector3Array([Vector3(-0.058, 0.04, -0.078), Vector3(-0.03, 0.043, -0.088),
				Vector3(0, 0.044, -0.09), Vector3(0.03, 0.043, -0.088), Vector3(0.058, 0.04, -0.078)]),
				PackedVector2Array([Vector2(0.003, 0.003), Vector2(0.006, 0.006), Vector2(0.006, 0.006), Vector2(0.006, 0.006), Vector2(0.003, 0.003)]), 8), skin, c)
		# Lips: a fuller lower lip and a thinner upper one with a dip in the
		# middle, a touch further out under a beard so they still show.
		var lip := ShintyMesh.solid(m.skin_color.lerp(Color(0.62, 0.3, 0.3), 0.35), 0.5)
		var lz := -0.003 if facial == "beard" else 0.0
		if not own_head:
			_mesh(head, ShintyMesh.sweep(PackedVector3Array([Vector3(-0.022, -0.043, -0.094 + lz), Vector3(-0.01, -0.0405, -0.099 + lz),
				Vector3(0, -0.0415, -0.1 + lz), Vector3(0.01, -0.0405, -0.099 + lz), Vector3(0.022, -0.043, -0.094 + lz)]),
				PackedVector2Array([Vector2(0.002, 0.002), Vector2(0.0035, 0.004), Vector2(0.003, 0.0035), Vector2(0.0035, 0.004), Vector2(0.002, 0.002)]), 6), lip, c)
			_mesh(head, ShintyMesh.sweep(PackedVector3Array([Vector3(-0.02, -0.0455, -0.094 + lz), Vector3(0, -0.048, -0.0995 + lz),
				Vector3(0.02, -0.0455, -0.094 + lz)]),
				PackedVector2Array([Vector2(0.0025, 0.003), Vector2(0.0055, 0.0055), Vector2(0.0025, 0.003)]), 6), lip, c)
		# Eyes: white, iris, pupil; eyebrows in the hair colour.
		var white := ShintyMesh.solid(Color("f2eee6"), 0.25)
		var iris := ShintyMesh.solid(_pick(EYE_COLOURS, 2), 0.2)
		var pupil := ShintyMesh.solid(Color("0b0b0c"), 0.1)
		var eyes: Array = body_file.get("eyes", []) if own_head else []
		for sx in [-1.0, 1.0]:
			var e := c + Vector3(sx * 0.034, 0.02, -0.084)
			if eyes.size() == 2:  # in the imported face's sockets (head-bone space)
				var ep: Array = eyes[0 if sx < 0.0 else 1]
				var hr: Array = body_file["ref"]["Head"]
				e = Vector3(ep[0] - hr[0], ep[1] - hr[1], ep[2] - hr[2]) + Vector3(0, 0, -0.003)
			_mesh(head, _ellipsoid(0.0135, 0.009, 0.008, 6, 10), white, e)
			_mesh(head, _ellipsoid(0.0068, 0.0068, 0.004, 4, 8), iris, e + Vector3(0, 0, -0.0065))
			_mesh(head, _ellipsoid(0.0032, 0.0032, 0.002, 3, 6), pupil, e + Vector3(0, 0, -0.0092))
			var brow := _mesh(head, _loft([[-0.016, 0.004, 0.003], [0.016, 0.003, 0.002]], 6), hair,
				e + Vector3(sx * 0.002, 0.017, -0.011))
			brow.rotation.z = PI / 2 + sx * 0.12
			if not m.wear_helmet and not own_head:  # otherwise inside the helmet's ear pads
				var ear := _mesh(head, _ellipsoid(0.01, 0.028, 0.018, 6, 8), skin, c + Vector3(sx * 0.08, 0.005, 0.012))
				ear.rotation.y = sx * 0.3
	# Hair. A crop sits close to the skull; a buzz cut closer still and
	# showing the skin through; long hair also hangs below the helmet at the
	# back of the neck.
	var cap_off := -0.002 if style == "buzz" else (0.004 if style == "long" else 0.0)
	var cap_col := hair_col.lerp(m.skin_color, 0.45) if style == "buzz" else hair_col
	var cap := []
	for r in [[0.0, 0.082, 0.1, 0.012], [0.05, 0.083, 0.102, 0.008], [0.095, 0.072, 0.09, 0.01],
			[0.12, 0.042, 0.056, 0.012], [0.131, 0.01, 0.014, 0.012]]:
		cap.append([r[0] + (cap_off if r[0] > 0.125 else 0.0), r[1] + cap_off, r[2] + cap_off, r[3]])
	var cap_mat := hair if cap_col == hair_col else ShintyMesh.solid(cap_col, 0.95)
	var before := head.get_child_count()
	if not own_head:  # the imported head has its hair in the mesh
		_mesh(head, _loft(cap, seg, 2.1, false, -0.3, PI + 0.3), cap_mat, c)
	if not m.wear_helmet and not own_head:  # the front, from a hairline across the forehead
		_mesh(head, _loft(cap.slice(1), seg, 2.1, false, PI - 0.1, TAU + 0.1), cap_mat, c)
	if style == "long":
		_mesh(head, _loft([[-0.125, 0.058, 0.066, 0.034], [-0.105, 0.066, 0.078, 0.03], [-0.07, 0.074, 0.09, 0.022],
			[-0.03, 0.082, 0.1, 0.014], [0.0, 0.085, 0.103, 0.012], [0.035, 0.084, 0.102, 0.01]], seg, 2.2, false, 0.3, PI - 0.3), hair, c)
	# Facial hair: a shell over the jaw and chin, close for stubble and
	# standing off for a beard, or just the chin and lip for a goatee.
	if detail and facial != "none" and not own_head:
		var fh_col := hair_col.lerp(m.skin_color, 0.15)
		match facial:
			"stubble":
				_face_shell(head, face, -0.02, 0.0018, 0.0, PI + 0.2, TAU - 0.2,
					ShintyMesh.skin(m.skin_color.lerp(hair_col, 0.3)), c)
			"beard":
				_face_shell(head, face, -0.018, 0.003, 0.009, PI + 0.15, TAU - 0.15, ShintyMesh.solid(fh_col, 0.95), c)
				_moustache(head, ShintyMesh.solid(fh_col, 0.95), c, 0.004)
			"goatee":
				_face_shell(head, face, -0.07, 0.003, 0.006, PI + 0.85, TAU - 0.85, ShintyMesh.solid(fh_col, 0.95), c)
				_moustache(head, ShintyMesh.solid(fh_col, 0.95), c, 0.0)
			"moustache":
				_moustache(head, ShintyMesh.solid(fh_col, 0.95), c, 0.0)
	if m.wear_helmet:
		_helmet(head, c)
	if fit != 1.0:  # sized for the built skull: scale round its centre
		var about := Transform3D(Basis.from_scale(Vector3.ONE * fit), c * (1.0 - fit))
		for i in range(before, head.get_child_count()):
			var n := head.get_child(i) as Node3D
			n.transform = about * n.transform


## How this player looks: hair colour, hair style, facial hair and face
## shape. Squad data can set "hair" (a colour name or hex), "hair_style"
## (crop, buzz, long) and "facial_hair" (none, stubble, beard, goatee,
## moustache); anything left out is picked from the player's seed so the
## same player always looks the same.
func _face_look() -> Dictionary:
	var p := m.player_data
	var hair_col: Color = _pick(HAIR_COLOURS, 1)
	if m.skin_color.get_luminance() < 0.35:
		hair_col = Color("141111")
	var named := {"black": "151313", "dark": "2a1d14", "brown": "4a3020", "mid": "6b4a2b", "light": "a0703c",
		"fair": "c9a063", "blond": "c9a063", "blonde": "c9a063", "red": "8e3b1e", "ginger": "b5562a",
		"grey": "7d7a76", "gray": "7d7a76", "white": "c8c5bf"}
	var h := str(p.get("hair", "")).strip_edges().to_lower()
	if named.has(h):
		hair_col = Color(named[h])
	elif h != "" and Color.html_is_valid(h):
		hair_col = Color.html(h)
	var style := str(p.get("hair_style", "")).strip_edges().to_lower()
	if not style in ["crop", "buzz", "long"]:
		var r := _chance(11)
		style = "crop" if r < 0.6 else ("buzz" if r < 0.85 else "long")
	var facial := str(p.get("facial_hair", "")).strip_edges().to_lower()
	if not facial in ["none", "stubble", "beard", "goatee", "moustache"]:
		var r := _chance(5)
		facial = "none" if r < 0.42 else ("stubble" if r < 0.72 else ("beard" if r < 0.86 else ("goatee" if r < 0.95 else "moustache")))
	return {"hair": hair_col, "style": style, "facial": facial,
		"jaw": lerpf(0.93, 1.08, _chance(21)), "chin": lerpf(-0.004, 0.007, _chance(22)),
		"cheek": lerpf(0.96, 1.04, _chance(23)), "nose": lerpf(0.85, 1.2, _chance(24))}


## A shell over the lower face, `off` off the skin (`grow` more at the chin),
## from under the chin up to height `top`, over the front arc only.
func _face_shell(head: Node3D, face: Array, top: float, off: float, grow: float, from: float, to: float, mat: Material, c: Vector3) -> void:
	var rings := []
	var low: float = face[0][0]
	for r in face:
		if r[0] > top:
			break
		var k := clampf(1.0 - (r[0] - low) / (top - low), 0.0, 1.0)  # 1 at the chin
		var o := off + grow * k
		rings.append([r[0] - (o if r == face[0] else 0.0), r[1] + o, r[2] + o, r[3] - grow * k * 0.4])
	var t: Array = face[rings.size()] if rings.size() < face.size() else face[-1]
	var u: float = (top - rings[-1][0]) / maxf(t[0] - rings[-1][0], 0.001)
	rings.append([top, lerpf(rings[-1][1], t[1] + off, u), lerpf(rings[-1][2], t[2] + off, u), lerpf(rings[-1][3], t[3], u)])
	_mesh(head, _loft(rings, seg, 2.1, false, from, to), mat, c)


func _moustache(head: Node3D, mat: Material, c: Vector3, droop: float) -> void:
	_mesh(head, ShintyMesh.sweep(PackedVector3Array([Vector3(-0.027, -0.042 - droop, -0.092), Vector3(-0.016, -0.034, -0.099),
		Vector3(0, -0.0325, -0.103), Vector3(0.016, -0.034, -0.099), Vector3(0.027, -0.042 - droop, -0.092)]),
		PackedVector2Array([Vector2(0.002, 0.002), Vector2(0.0045, 0.005), Vector2(0.004, 0.0045), Vector2(0.0045, 0.005), Vector2(0.002, 0.002)]), 6), mat, c)


## Helmet in the style players wear: a hurling-type shell with a raised
## crown panel, slotted vents, white foam lining, and a stainless steel cage
## fixed at the brow and temples with a chin cup and strap. Most players wear
## the team colour; some wear two-tone or white shells.
func _helmet(head: Node3D, c: Vector3) -> void:
	var main_col := m.helmet_color
	var panel_col := m.helmet_color
	var style := _chance(9)
	if not m.is_keeper and style < 0.18:
		main_col = Color("f2f2f2")
	elif not m.is_keeper and style < 0.33 and _color_gap(m.helmet_color, m.trim_color) > 0.25:
		panel_col = m.trim_color
	var shell := ShintyMesh.solid(main_col, 0.38, 0.0, 0.55)
	var panel := ShintyMesh.solid(panel_col.darkened(0.06) if panel_col == main_col else panel_col, 0.38, 0.0, 0.55)
	var foam := ShintyMesh.solid(Color("ecebe6"), 0.9)
	var dark := ShintyMesh.solid(Color("18181c"), 0.85)
	var metal := ShintyMesh.solid(Color("d2d5d9"), 0.3, 0.6)
	# Shell: the dome, then the sides and back coming down past the ears to
	# the nape, open at the face. It sits a finger's width off the skull.
	_mesh(head, _loft([
		[0.03, 0.096, 0.121, 0.012], [0.07, 0.096, 0.121, 0.013], [0.105, 0.084, 0.108, 0.015],
		[0.128, 0.066, 0.084, 0.016], [0.143, 0.04, 0.05, 0.016], [0.15, 0.01, 0.012, 0.016]], seg + 4, 2.3), shell, c)
	_mesh(head, _loft([
		[-0.075, 0.084, 0.098, 0.03], [-0.045, 0.092, 0.108, 0.022], [-0.005, 0.097, 0.118, 0.015],
		[0.036, 0.098, 0.122, 0.012]], seg, 2.3, false, -0.5, PI + 0.5), shell, c)
	# Brow rim: a rolled edge across the forehead where the cage clips on.
	_mesh(head, _loft([[0.03, 0.1, 0.124, 0.011], [0.042, 0.1, 0.124, 0.011]], seg + 4, 2.3, true, PI + 0.5, TAU - 0.5), shell, c)
	# Crown panel: a raised strip from the brow over the top to the back,
	# following the shell's centre line just proud of it.
	var prof := PackedVector2Array()  # (y, z) up the front, over, down the back
	var dome_rings := [[0.036, 0.121, 0.012], [0.07, 0.121, 0.013], [0.105, 0.108, 0.015], [0.128, 0.084, 0.016], [0.143, 0.05, 0.016]]
	for r in dome_rings:
		prof.append(Vector2(r[0], r[2] - r[1]))
	prof.append(Vector2(0.15, 0.016))
	for i in range(dome_rings.size() - 1, -1, -1):
		prof.append(Vector2(dome_rings[i][0], dome_rings[i][2] + dome_rings[i][1]))
	prof.append(Vector2(-0.005, 0.015 + 0.118))
	var cp := PackedVector3Array()
	var cr := PackedVector2Array()
	for i in prof.size():
		var tng := prof[mini(i + 1, prof.size() - 1)] - prof[maxi(i - 1, 0)]
		var out := Vector2(-tng.y, tng.x).normalized()  # (dy, dz) pointing away from the skull
		if out.x < 0.0 and prof[i].y > 0.14:
			out = -out
		if Vector2(prof[i].x - 0.07, prof[i].y - 0.015).dot(out) < 0.0:
			out = -out
		var q := prof[i] + out * 0.004
		cp.append(c + Vector3(0, q.x, q.y))
		cr.append(Vector2(lerpf(0.03, 0.036, sin(PI * float(i) / (prof.size() - 1))), 0.0045))
	_mesh(head, ShintyMesh.sweep(cp, cr, seg, 3.0, false, Vector3.RIGHT), panel)
	# Foam lining showing under the brow and round the face opening, and the
	# white ear pads either side.
	_mesh(head, _loft([[0.024, 0.093, 0.116, 0.012], [0.034, 0.095, 0.119, 0.011]], seg + 4, 2.3, true, PI + 0.55, TAU - 0.55), foam, c)
	for sx in [-1.0, 1.0]:
		var pad := _mesh(head, _loft([[-0.05, 0.008, 0.012], [-0.03, 0.01, 0.016], [0.025, 0.011, 0.018], [0.04, 0.008, 0.014]], 10, 2.6), foam,
			c + Vector3(sx * 0.09, -0.02, -0.03))
		pad.rotation.x = 0.45
	if detail:
		# Vents: two slots stacked on the forehead each side of the panel,
		# two at the back and two along each side.
		var slot := ShintyMesh.loft([[-0.001, 0.012, 0.0045], [0.003, 0.011, 0.0038]], 8, 4.0)
		for sx in [-1.0, 1.0]:
			for i in 2:
				_surface_piece(head, slot, dark, c, Vector3(sx * 0.052, 0.068 + i * 0.018, 0.0))
			_surface_piece(head, slot, dark, c, Vector3(sx * 0.03, 0.08, 1.0))
			for i in 2:
				_surface_piece(head, slot, dark, c, Vector3(sx * 0.097, 0.055 + i * 0.022, 0.5), true)
		# Fixings: rivets at the temples where the cage and strap attach, and
		# the two clips on the brow.
		for sx in [-1.0, 1.0]:
			_mesh(head, _ellipsoid(0.007, 0.007, 0.003, 3, 8), metal, c + Vector3(sx * 0.1, 0.0, -0.035)).rotation.y = sx * PI / 2
			_mesh(head, _loft([[-0.006, 0.006, 0.004], [0.006, 0.006, 0.004]], 6, 3.0), dark,
				c + Vector3(sx * 0.014, 0.038, -0.127)).rotation.x = PI / 2
		var brand := _label("CORRIE", 40, 0.0006)
		brand.modulate = Color.WHITE if main_col.get_luminance() < 0.6 else Color("1b1b1f")
		brand.outline_size = 0
		brand.visibility_range_end = 18.0
		for sx in [-1.0, 1.0]:
			var b := brand if sx < 0.0 else brand.duplicate() as Label3D
			b.position = c + Vector3(sx * 0.1015, 0.035, 0.03)
			b.rotation = Vector3(0, sx * PI / 2, 0)
			head.add_child(b)
	# Cage: bars bent round the face from temple to temple, standing off the
	# face and tucking in under the chin. v runs 0 (brow) to 1 (chin).
	var bars_h := [0.0, 0.17, 0.34, 0.5, 0.66, 0.82, 1.0] if detail else [0.0, 0.5, 1.0]
	var bars_v := [-50.0, -30.0, -6.0, 6.0, 30.0, 50.0] if detail else [-30.0, 0.0, 30.0]
	var thick := Vector2(0.0033, 0.0033)
	for v in bars_h:
		var span := lerpf(80.0, 58.0, v)
		var pts := PackedVector3Array()
		var rad := PackedVector2Array()
		for j in 11:
			pts.append(c + _cage_point(v, deg_to_rad(lerpf(-span, span, j / 10.0))))
			rad.append(thick)
		_mesh(head, ShintyMesh.sweep(pts, rad, 4), metal)
	for deg in bars_v:
		var pts := PackedVector3Array()
		var rad := PackedVector2Array()
		for k in 7:
			pts.append(c + _cage_point(k / 6.0, deg_to_rad(deg)))
			rad.append(thick)
		_mesh(head, ShintyMesh.sweep(pts, rad, 4), metal)
	# Side frame: the outer bar from the temple rivet down to the chin corner.
	for sx in [-1.0, 1.0]:
		var pts := PackedVector3Array()
		var rad := PackedVector2Array()
		for k in 7:
			var v := k / 6.0
			pts.append(c + _cage_point(v, sx * deg_to_rad(lerpf(80.0, 58.0, v))))
			rad.append(Vector2(0.0045, 0.0045))
		_mesh(head, ShintyMesh.sweep(pts, rad, 5), metal)
	# Chin cup inside the bottom of the cage, and the strap up to the ear pads.
	_mesh(head, _ellipsoid(0.032, 0.016, 0.022, 5, 10), dark, c + Vector3(0, -0.118, -0.078))
	for sx in [-1.0, 1.0]:
		_mesh(head, ShintyMesh.sweep(PackedVector3Array([c + Vector3(sx * 0.094, -0.045, -0.01), c + Vector3(sx * 0.078, -0.09, -0.04),
			c + Vector3(sx * 0.03, -0.118, -0.07)]), PackedVector2Array([Vector2(0.0025, 0.008), Vector2(0.0025, 0.008), Vector2(0.0025, 0.008)]), 6), dark)


## A point on the cage: v from 0 at the brow to 1 under the chin, a = angle
## round the face (0 straight ahead). Head space, relative to the skull centre.
static func _cage_point(v: float, a: float) -> Vector3:
	var y := lerpf(0.036, -0.13, v)
	# Half width and depth of the cage at this height: widest at the cheeks,
	# furthest out in front of the mouth, drawn in under the chin.
	var half_w := lerpf(0.114, 0.084, v * v)
	var depth := 0.138 + 0.01 * sin(v * PI * 0.8) - 0.03 * pow(v, 3.0)
	return Vector3(sin(a) * half_w, y, 0.012 - cos(a) * depth)


## Place a small piece flat on the helmet shell. `spot` is (x, y, where) with
## where 0 = front, 1 = top towards the back, 0.5 = side; `side` turns it to
## run along the side of the shell.
func _surface_piece(head: Node3D, mesh: Mesh, mat: Material, c: Vector3, spot: Vector3, side := false) -> void:
	var x := spot.x
	var y := spot.y
	var hw := 0.098
	var hd := 0.122
	var pos: Vector3
	var normal: Vector3
	if side:
		var z := lerpf(-0.03, 0.05, spot.z)
		pos = Vector3(signf(x) * hw * 1.005, y, z + 0.012)
		normal = Vector3(signf(x), 0.25, 0).normalized()
	elif spot.z > 0.5:
		pos = Vector3(x, y + 0.035, 0.09)
		normal = Vector3(0, 0.6, 1).normalized()
	else:
		var k := clampf(x / hw, -0.95, 0.95)
		pos = Vector3(x, y, 0.012 - hd * sqrt(1.0 - k * k) - 0.001)
		normal = Vector3(k, 0.35, -sqrt(1.0 - k * k)).normalized()
	var mi := _mesh(head, mesh, mat, c + pos)
	# The slot's thin axis is its local Y; lay that along the surface normal.
	mi.basis = Basis(Quaternion(Vector3.UP, normal)) * (Basis(Vector3.UP, PI / 2) if side else Basis())


static func _color_gap(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()


# --- Caman ---------------------------------------------------------------------------

## Builds the caman under the skeleton and returns it. The butt of the handle
## is the origin, the shaft runs down -Y and the bas (head) curves towards -Z;
## ShintyPlayerModel.HEAD_LOCAL is its striking centre.
func _caman() -> Node3D:
	var cam := Node3D.new()
	cam.name = "Caman"
	skel.add_child(cam)
	# Shape, wood, tape and bands come from the club's design (ShintyCaman).
	ShintyCaman.build(cam, m.caman_design, detail)
	return cam


# --- Helpers -------------------------------------------------------------------------

func _attach(bone_name: String) -> BoneAttachment3D:
	var a := BoneAttachment3D.new()
	a.name = bone_name + "Attach"
	a.bone_name = bone_name
	skel.add_child(a)
	return a


func _find_attach(bone_name: String) -> Node3D:
	return skel.get_node(bone_name + "Attach")


func _mesh(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


## ShintyMesh.loft with extra rings eased in between the given ones
## (Catmull-Rom), so limbs and torso curve smoothly instead of kinking.
func _loft(rings: Array, segments: int = 16, squareness: float = 2.0, open_ends: bool = false,
		arc_from: float = 0.0, arc_to: float = TAU) -> ArrayMesh:
	if rings.size() >= 3:
		var full := []
		for r in rings:
			full.append([r[0], r[1], r[2], r[3] if r.size() > 3 else 0.0, r[4] if r.size() > 4 else 0.0])
		var dense := []
		var steps := 1
		for i in full.size() - 1:
			var a: Array = full[maxi(i - 1, 0)]
			var b: Array = full[i]
			var c: Array = full[i + 1]
			var d: Array = full[mini(i + 2, full.size() - 1)]
			dense.append(b)
			for k in range(1, steps + 1):
				var t := float(k) / (steps + 1)
				var ring := []
				for j in 5:
					ring.append(_catmull(a[j], b[j], c[j], d[j], t))
				# Radii never undershoot below the smaller neighbour (no pinching).
				ring[1] = maxf(ring[1], minf(b[1], c[1]) * 0.9)
				ring[2] = maxf(ring[2], minf(b[2], c[2]) * 0.9)
				dense.append(ring)
		dense.append(full[full.size() - 1])
		rings = dense
	return ShintyMesh.loft(rings, segments, squareness, open_ends, arc_from, arc_to)


static func _catmull(p0: float, p1: float, p2: float, p3: float, t: float) -> float:
	var t2 := t * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
		+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t2 * t)


func _ellipsoid(rx: float, ry: float, rz: float, n := 7, segs := 10) -> ArrayMesh:
	var rings := []
	for i in n + 1:
		var a := lerpf(-PI / 2, PI / 2, float(i) / n)
		rings.append([sin(a) * ry, maxf(cos(a) * rx, 0.0004), maxf(cos(a) * rz, 0.0004)])
	return ShintyMesh.loft(rings, segs)
