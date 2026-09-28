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

var m: ShintyPlayerModel
var skel: Skeleton3D
var w := 1.0     # girth
var sw := 1.0    # shoulder/hip width
var seed_val := 0
var detail := true
var seg := 16


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
			surfaces[key].add(c.mesh, xf, bone, mat)
			var size: Vector3 = c.mesh.get_aabb().size
			if maxf(size.x, maxf(size.y, size.z)) > 0.03:  # eyes, studs and laces cast nothing you'd see
				shadow.add(c.mesh, xf, bone, null)
			holder.remove_child(c)
			c.free()
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

	func add(mesh: Mesh, xf: Transform3D, bone: int, mat: Material) -> void:
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
				verts.append(xf * v[i])
				norms.append((nb * n[i]).normalized() if n.size() > i else Vector3.UP)
				uvs.append(uv[i] if uv.size() > i else Vector2.ZERO)
				uv2s.append(rm)
				colors.append(col)
				bones.append_array([bone, 0, 0, 0])
				weights.append_array([1.0, 0.0, 0.0, 0.0])
			var src: PackedInt32Array = a[Mesh.ARRAY_INDEX]
			if src.is_empty():
				src = PackedInt32Array(range(v.size()))
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

	# Pelvis in shorts, with the shirt hem hanging over the waistband.
	var hips := _attach("Hips")
	_mesh(hips, ShintyMesh.loft([
		[-0.14, 0.13 * w, 0.085 * w], [-0.1, 0.158 * w * sw, 0.1 * w], [-0.03, 0.166 * w * sw, 0.108 * w],
		[0.04, 0.158 * w, 0.104 * w], [0.1, 0.146 * w, 0.098 * w]], seg, 2.4), shorts)
	# Abdomen and chest: the shirt, sculpted a little at the chest and back.
	var spine := _attach("Spine")
	_mesh(spine, ShintyMesh.loft([
		[-0.075, 0.158 * w, 0.107 * w], [-0.03, 0.156 * w, 0.106 * w], [0.05, 0.148 * w, 0.1 * w],
		[0.15, 0.156 * w, 0.106 * w, -0.004]], seg, 2.3), shirt)
	var chest := _attach("Chest")
	_mesh(chest, ShintyMesh.loft([
		[-0.02, 0.156 * w, 0.106 * w, -0.004], [0.05, 0.168 * w * sw, 0.114 * w, -0.012],
		[0.1, 0.178 * w * sw, 0.116 * w, -0.014], [0.16, 0.184 * w * sw, 0.11 * w, -0.01]], seg, 2.3), chest_band)
	var upper := _attach("UpperChest")
	_mesh(upper, ShintyMesh.loft([
		[-0.02, 0.184 * w * sw, 0.11 * w, -0.01], [0.04, 0.192 * w * sw, 0.108 * w, -0.008],
		[0.08, 0.2 * w * sw, 0.098 * w, 0.0], [0.105, 0.18 * w * sw, 0.088 * w, 0.003], [0.122, 0.145 * w * sw, 0.078 * w, 0.005],
		[0.135, 0.1 * w, 0.066 * w, 0.006], [0.155, 0.062, 0.052, 0.004]], seg, 2.3), shirt)
	# Collar in the trim colour
	_mesh(upper, ShintyMesh.loft([[0.13, 0.066, 0.056, 0.003], [0.165, 0.058, 0.05, 0.0]], seg, 2.0, true),
		ShintyMesh.fabric(m.trim_color, m.trim_color))

	for side in ["Left", "Right"]:
		var sgn := -1.0 if side == "Left" else 1.0
		# Upper arm: deltoid in the shirt, short sleeve with a trim cuff, bicep below.
		var ua := _attach(side + "UpperArm")
		_mesh(ua, ShintyMesh.loft([
			[0.03, 0.03 * w, 0.034 * w, 0.0, -0.012 * (-1.0 if side == "Left" else 1.0)], [0.0, 0.058 * w, 0.06 * w],
			[-0.06, 0.062 * w, 0.059 * w],
			[-0.15, 0.058 * w, 0.056 * w], [-0.17, 0.059 * w, 0.057 * w]], seg), shirt)
		_mesh(ua, ShintyMesh.loft([[-0.155, 0.06 * w, 0.058 * w], [-0.185, 0.06 * w, 0.058 * w]], seg, 2.0, true),
			ShintyMesh.fabric(m.trim_color, m.trim_color))
		_mesh(ua, ShintyMesh.loft([
			[-0.14, 0.05 * w, 0.052 * w], [-0.2, 0.049 * w, 0.051 * w, -0.004], [-0.26, 0.043 * w, 0.044 * w],
			[-0.3, 0.04 * w, 0.041 * w]], seg), skin)
		# Forearm: thick near the elbow, tapering to the wrist.
		var la := _attach(side + "LowerArm")
		_mesh(la, ShintyMesh.loft([
			[0.02, 0.04 * w, 0.041 * w], [-0.05, 0.046 * w, 0.042 * w], [-0.12, 0.041 * w, 0.036 * w],
			[-0.22, 0.031 * w, 0.026 * w], [-0.275, 0.027, 0.022]], seg), skin)
		# Hand: a gripping fist with a thumb wrapped round the caman.
		var hand := _attach(side + "Hand")
		_mesh(hand, ShintyMesh.loft([
			[0.01, 0.027, 0.021], [-0.03, 0.041, 0.024], [-0.065, 0.044, 0.028, -0.006],
			[-0.095, 0.036, 0.03, -0.012]], 12, 2.8), skin)
		if detail:
			var thumb := _mesh(hand, ShintyMesh.loft([[0.0, 0.012, 0.012], [-0.04, 0.011, 0.011], [-0.055, 0.009, 0.009]], 8),
				skin, Vector3(-sgn * 0.02, -0.035, -0.025))
			thumb.rotation = Vector3(0.9, 0.0, sgn * 0.5)

	for side in ["Left", "Right"]:
		# Thigh with a front quad bulge; loose shorts leg over the top.
		var ul := _attach(side + "UpperLeg")
		_mesh(ul, ShintyMesh.loft([
			[0.04, 0.078 * w, 0.08 * w], [-0.05, 0.084 * w, 0.086 * w, -0.004], [-0.16, 0.078 * w, 0.08 * w, -0.008],
			[-0.3, 0.064 * w, 0.064 * w, -0.004], [-0.4, 0.052 * w, 0.054 * w], [-0.455, 0.05 * w, 0.052 * w]], seg), skin)
		_mesh(ul, ShintyMesh.loft([
			[0.05, 0.098 * w, 0.098 * w], [-0.08, 0.1 * w, 0.1 * w, -0.004], [-0.2, 0.098 * w, 0.096 * w, -0.006]], seg, 2.0, true), shorts)
		# Shin: calf muscle behind, sock over most of it with trim hoops at the top.
		var ll := _attach(side + "LowerLeg")
		_mesh(ll, ShintyMesh.loft([
			[0.03, 0.05 * w, 0.052 * w], [-0.05, 0.053 * w, 0.058 * w, 0.01], [-0.14, 0.052 * w, 0.06 * w, 0.014],
			[-0.26, 0.042 * w, 0.045 * w, 0.006], [-0.38, 0.032 * w, 0.034 * w], [-0.44, 0.032, 0.036]], seg), skin)
		_mesh(ll, _sock_mesh(), socks, Vector3(0, -0.07, 0))
		# Boot: shaped upper, contrasting sole, a few studs.
		var foot := _attach(side + "Foot")
		_boot(foot)


func _sock_mesh() -> ArrayMesh:
	# v runs downward from the sock top (UV v = 0 at the top) so the hoops sit there.
	var rings := [
		[0.0, 0.056 * w, 0.063 * w, 0.013], [-0.07, 0.056 * w, 0.064 * w, 0.014], [-0.19, 0.047 * w, 0.051 * w, 0.006],
		[-0.31, 0.038 * w, 0.04 * w, 0.0], [-0.38, 0.037, 0.04, 0.002]]
	return ShintyMesh.loft(rings, seg, 2.0, true)


func _boot(foot: Node3D) -> void:
	var col: Color = _pick(BOOT_COLOURS, 3)
	var sole_col: Color = _pick(SOLE_COLOURS, 4)
	var pts := PackedVector3Array()
	var rad := PackedVector2Array()
	# Heel to toe along -Z; radii are (half width, half height).
	var prof := [
		[0.075, 0.034, 0.04, 0.0], [0.045, 0.041, 0.047, 0.0], [0.0, 0.044, 0.045, -0.004],
		[-0.06, 0.046, 0.037, -0.012], [-0.12, 0.044, 0.028, -0.02], [-0.165, 0.034, 0.02, -0.026],
		[-0.185, 0.018, 0.012, -0.03]]
	for p in prof:
		pts.append(Vector3(0, p[3] - 0.022, p[0]))
		rad.append(Vector2(p[1], p[2]))
	var upper := ShintyMesh.sweep(pts, rad, seg, 2.6, false, Vector3.RIGHT)
	_mesh(foot, upper, ShintyMesh.solid(col, 0.35, 0.0, 0.3))
	# Sole plate
	var sole := ShintyMesh.loft([[0.0, 0.047, 0.13], [0.012, 0.047, 0.13]], seg, 3.5)
	_mesh(foot, sole, ShintyMesh.solid(sole_col, 0.5), Vector3(0, -0.067, -0.055))
	if detail:
		var stud := ShintyMesh.solid(Color("d8d8d8"), 0.3, 0.7)
		for sp in [Vector3(0.025, 0, 0.05), Vector3(-0.025, 0, 0.05), Vector3(0.028, 0, -0.06),
				Vector3(-0.028, 0, -0.06), Vector3(0.022, 0, -0.14), Vector3(-0.022, 0, -0.14)]:
			_mesh(foot, ShintyMesh.loft([[0.0, 0.008, 0.008], [-0.012, 0.006, 0.006]], 6), stud, sp + Vector3(0, -0.067, 0))
		# Laces
		var lace := ShintyMesh.solid(Color("f0f0f0"), 0.8)
		for i in 4:
			_mesh(foot, ShintyMesh.loft([[-0.022, 0.003, 0.003], [0.022, 0.003, 0.003]], 6), lace,
				Vector3(0, 0.012 - i * 0.006, -0.03 - i * 0.022)).rotation.z = PI / 2


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
	# Number on the back, surname above it, small number on the front.
	if m.shirt_number > 0:
		var back := _label(str(m.shirt_number), 110, 0.0021)
		back.position = Vector3(0, 0.0, 0.112 * w)
		upper.add_child(back)
		var front := _label(str(m.shirt_number), 64, 0.0012)
		front.position = Vector3(0.075 * w, 0.02, -0.118 * w)
		front.rotation.y = PI
		chest.add_child(front)
	var surname := _surname()
	if surname != "":
		var name_label := _label(surname, 48, 0.00115)
		name_label.position = Vector3(0, 0.1, 0.103 * w)
		name_label.rotation.x = -0.12
		upper.add_child(name_label)
	# Club crest on the left breast: a shield in the trim colour.
	var crest := ShintyMesh.loft([[0.0, 0.004, 0.022], [0.02, 0.018, 0.024], [0.045, 0.02, 0.022], [0.052, 0.02, 0.02]], 10, 3.0)
	var ci := _mesh(chest, crest, ShintyMesh.solid(m.trim_color, 0.6), Vector3(-0.075 * w, 0.03, -0.114 * w))
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


func _surname() -> String:
	var n := str(m.player_data.get("name", "")).strip_edges()
	if n == "":
		return ""
	var parts := n.split(" ", false)
	var last: String = parts[parts.size() - 1]
	if last.is_valid_int() or last.to_lower() == "player":
		return ""
	return last.to_upper()


# --- Head, face, hair ----------------------------------------------------------------

func _head() -> void:
	var skin := ShintyMesh.skin(m.skin_color)
	var hair_col: Color = _pick(HAIR_COLOURS, 1)
	if m.skin_color.get_luminance() < 0.35:
		hair_col = Color("141111")
	var hair := ShintyMesh.solid(hair_col, 0.85)
	var neck := _attach("Neck")
	_mesh(neck, ShintyMesh.loft([[-0.02, 0.058, 0.056], [0.06, 0.052, 0.05, 0.004], [0.13, 0.05, 0.048, 0.008]], seg), skin)

	var head := _attach("Head")
	var c := Vector3(0, 0.11, 0)
	# Skull and face in one sculpted piece: chin, jaw, cheekbones, brow.
	var jaw := 0.066 + 0.01 * m.build
	_mesh(head, ShintyMesh.loft([
		[-0.108, 0.018, 0.016, -0.083], [-0.1, 0.034, 0.03, -0.074], [-0.08, jaw * 0.85, 0.058, -0.045],
		[-0.05, jaw, 0.08, -0.018], [-0.015, 0.074, 0.094, -0.006], [0.02, 0.079, 0.1, 0.0],
		[0.06, 0.079, 0.1, 0.006], [0.095, 0.068, 0.086, 0.01], [0.118, 0.04, 0.052, 0.012],
		[0.128, 0.01, 0.014, 0.012]], seg + 4, 2.1), skin, c)
	# Nose, brow ridge, lips, ears
	var nose := ShintyMesh.sweep(PackedVector3Array([Vector3(0, 0.03, -0.092), Vector3(0, 0.0, -0.106), Vector3(0, -0.018, -0.112)]),
		PackedVector2Array([Vector2(0.008, 0.006), Vector2(0.012, 0.012), Vector2(0.016, 0.012)]), 10)
	_mesh(head, nose, skin, c)
	if detail:
		_mesh(head, ShintyMesh.sweep(PackedVector3Array([Vector3(-0.06, 0.042, -0.086), Vector3(0, 0.046, -0.097), Vector3(0.06, 0.042, -0.086)]),
			PackedVector2Array([Vector2(0.008, 0.008), Vector2(0.01, 0.01), Vector2(0.008, 0.008)]), 8), skin, c)
		var lip := ShintyMesh.solid(m.skin_color.lerp(Color(0.62, 0.3, 0.3), 0.35), 0.5)
		_mesh(head, ShintyMesh.sweep(PackedVector3Array([Vector3(-0.022, -0.044, -0.094), Vector3(0, -0.042, -0.1), Vector3(0.022, -0.044, -0.094)]),
			PackedVector2Array([Vector2(0.004, 0.005), Vector2(0.006, 0.007), Vector2(0.004, 0.005)]), 8), lip, c)
		# Eyes: white, iris, pupil; eyebrows in the hair colour.
		var white := ShintyMesh.solid(Color("f2eee6"), 0.25)
		var iris := ShintyMesh.solid(_pick(EYE_COLOURS, 2), 0.2)
		var pupil := ShintyMesh.solid(Color("0b0b0c"), 0.1)
		for sx in [-1.0, 1.0]:
			var e := c + Vector3(sx * 0.034, 0.02, -0.084)
			_mesh(head, _ellipsoid(0.0135, 0.009, 0.008), white, e)
			_mesh(head, _ellipsoid(0.0068, 0.0068, 0.004), iris, e + Vector3(0, 0, -0.0065))
			_mesh(head, _ellipsoid(0.0032, 0.0032, 0.002), pupil, e + Vector3(0, 0, -0.0092))
			var brow := _mesh(head, ShintyMesh.loft([[-0.016, 0.004, 0.003], [0.016, 0.003, 0.002]], 6), hair,
				e + Vector3(sx * 0.002, 0.018, -0.006))
			brow.rotation.z = PI / 2 + sx * 0.12
			# Ears
			var ear := _mesh(head, _ellipsoid(0.01, 0.028, 0.018), skin, c + Vector3(sx * 0.08, 0.005, 0.012))
			ear.rotation.y = sx * 0.3
	# Hair: close crop under the helmet, visible at the back and sides.
	_mesh(head, ShintyMesh.loft([
		[0.0, 0.082, 0.1, 0.012], [0.05, 0.083, 0.102, 0.008], [0.095, 0.072, 0.09, 0.01],
		[0.12, 0.042, 0.056, 0.012], [0.131, 0.01, 0.014, 0.012]], seg, 2.1, false, -0.3, PI + 0.3), hair, c)
	# Some players have a beard or stubble.
	if detail and _chance(5) < 0.35 and m.skin_color.get_luminance() > 0.2:
		var beard := ShintyMesh.solid(hair_col.lerp(m.skin_color, 0.35), 0.95)
		_mesh(head, ShintyMesh.loft([
			[-0.109, 0.02, 0.018, -0.084], [-0.1, 0.036, 0.032, -0.075], [-0.08, jaw * 0.87, 0.06, -0.046],
			[-0.05, jaw * 1.02, 0.082, -0.018], [-0.02, 0.075, 0.094, -0.008]], seg, 2.1, false, PI + 0.25, TAU - 0.25), beard, c)
	if m.wear_helmet:
		_helmet(head, c)


func _helmet(head: Node3D, c: Vector3) -> void:
	var shell := ShintyMesh.solid(m.helmet_color, 0.28, 0.05, 0.8)
	var inner := ShintyMesh.solid(Color("1c1c20"), 0.8)
	var metal := ShintyMesh.solid(Color("c9ccd1"), 0.25, 0.9)
	# Dome over the top, a little bigger than the skull.
	_mesh(head, ShintyMesh.loft([
		[0.03, 0.096, 0.118, 0.008], [0.07, 0.096, 0.118, 0.01], [0.105, 0.083, 0.104, 0.012],
		[0.128, 0.064, 0.08, 0.014], [0.142, 0.038, 0.047, 0.014], [0.149, 0.01, 0.012, 0.014]], seg + 4, 2.2), shell, c)
	# Back and side skirt, open at the face.
	_mesh(head, ShintyMesh.loft([
		[-0.06, 0.09, 0.106, 0.016], [-0.02, 0.095, 0.114, 0.012], [0.035, 0.096, 0.118, 0.008]],
		seg, 2.2, false, -0.55, PI + 0.55), shell, c)
	# Padding visible at the rim
	_mesh(head, ShintyMesh.loft([[0.026, 0.093, 0.114, 0.008], [0.034, 0.093, 0.114, 0.008]], seg, 2.2, true), inner, c)
	# Peak over the brow
	var peak := _mesh(head, ShintyMesh.loft([[0.0, 0.07, 0.02], [0.006, 0.07, 0.02]], seg, 3.0), shell,
		c + Vector3(0, 0.038, -0.112))
	peak.rotation.x = 0.25
	# Vents along the top
	if detail:
		for i in 3:
			var vent := _mesh(head, ShintyMesh.loft([[-0.02, 0.004, 0.012], [0.02, 0.004, 0.012]], 6, 3.0), inner,
				c + Vector3((i - 1) * 0.03, 0.128 - absf(i - 1) * 0.01, 0.02))
			vent.rotation.x = PI / 2 - 0.3
	# Face guard: curved bars on an arc in front of the face.
	var r := 0.132
	var n_bars := 7 if detail else 3
	for i in n_bars:
		var a := deg_to_rad(lerpf(-58.0, 58.0, float(i) / (n_bars - 1)))
		var top := c + Vector3(sin(a) * r * 0.92, 0.03, -cos(a) * r)
		var bot := c + Vector3(sin(a) * r * 0.8, -0.115, -cos(a) * r * 0.86)
		_mesh(head, ShintyMesh.sweep(PackedVector3Array([top, (top + bot) / 2.0 + Vector3(0, 0, -0.006), bot]),
			PackedVector2Array([Vector2(0.004, 0.004), Vector2(0.004, 0.004), Vector2(0.004, 0.004)]), 6), metal)
	for y in ([0.03, -0.02, -0.07, -0.115] if detail else [0.03, -0.115]):
		var k := inverse_lerp(0.03, -0.115, y)
		var pts := PackedVector3Array()
		var rad := PackedVector2Array()
		for j in 11:
			var a2 := deg_to_rad(lerpf(-72.0, 72.0, j / 10.0))
			pts.append(c + Vector3(sin(a2) * r * lerpf(0.92, 0.8, k), y, -cos(a2) * r * lerpf(1.0, 0.86, k)))
			rad.append(Vector2(0.0045, 0.0045))
		_mesh(head, ShintyMesh.sweep(pts, rad, 6), metal)
	# Chin strap and cup
	var strap := ShintyMesh.solid(Color("1b1b1f"), 0.7)
	for sx in [-1.0, 1.0]:
		_mesh(head, ShintyMesh.sweep(PackedVector3Array([c + Vector3(sx * 0.088, -0.02, 0.0), c + Vector3(sx * 0.07, -0.08, -0.03),
			c + Vector3(sx * 0.03, -0.108, -0.066)]), PackedVector2Array([Vector2(0.003, 0.007), Vector2(0.003, 0.007), Vector2(0.003, 0.007)]), 6), strap)
	_mesh(head, _ellipsoid(0.03, 0.014, 0.02), strap, c + Vector3(0, -0.11, -0.074))


# --- Caman ---------------------------------------------------------------------------

## Builds the caman under the skeleton and returns it. The butt of the handle
## is the origin, the shaft runs down -Y and the bas (head) curves towards -Z;
## ShintyPlayerModel.HEAD_LOCAL is its striking centre.
func _caman() -> Node3D:
	var cam := Node3D.new()
	cam.name = "Caman"
	skel.add_child(cam)
	var L := ShintyPlayerModel.CAMAN_LENGTH
	var wood := ShintyMesh.wood()
	# Shaft: slightly oval, thinning towards the bas then flaring into it.
	var pts := PackedVector3Array()
	var rad := PackedVector2Array()
	var shaft := [[0.0, 0.0165, 0.0145], [-0.3, 0.0158, 0.0138], [-0.6, 0.0148, 0.0135],
		[-(L - 0.16), 0.0138, 0.0145], [-(L - 0.1), 0.0148, 0.02]]
	for s in shaft:
		pts.append(Vector3(0, s[0], 0))
		rad.append(Vector2(s[1], s[2]))
	# The bas: a curved wedge, both faces flat enough to strike with.
	var bas := [[-(L - 0.07), 0.0, 0.017, 0.026], [-(L - 0.045), -0.008, 0.0185, 0.032],
		[-(L - 0.025), -0.025, 0.019, 0.035], [-(L - 0.012), -0.05, 0.0185, 0.034],
		[-(L - 0.006), -0.08, 0.017, 0.03], [-(L - 0.004), -0.105, 0.014, 0.024], [-(L - 0.004), -0.118, 0.01, 0.016]]
	for b in bas:
		pts.append(Vector3(0, b[0], b[1]))
		rad.append(Vector2(b[2], b[3]))
	var mi := MeshInstance3D.new()
	mi.mesh = ShintyMesh.sweep(pts, rad, 12, 2.6, false, Vector3.RIGHT)
	mi.material_override = wood
	cam.add_child(mi)
	# Grip tape on the handle and a knob at the end
	var grip := MeshInstance3D.new()
	grip.mesh = ShintyMesh.loft([[0.004, 0.0185, 0.0165], [-0.3, 0.0178, 0.016]], 12, 2.0, true)
	grip.material_override = ShintyMesh.tape()
	cam.add_child(grip)
	var knob := MeshInstance3D.new()
	knob.mesh = ShintyMesh.loft([[0.012, 0.012, 0.011], [0.0, 0.021, 0.019], [-0.012, 0.019, 0.017]], 12)
	knob.material_override = ShintyMesh.tape()
	cam.add_child(knob)
	# Tape round the bas, as players do to protect it
	if detail:
		var bt := MeshInstance3D.new()
		bt.mesh = ShintyMesh.loft([[-(L - 0.1), 0.0152, 0.0205], [-(L - 0.07), 0.0175, 0.0265]], 12, 2.4, true)
		bt.material_override = ShintyMesh.tape(Color("1d1d22"))
		cam.add_child(bt)
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


func _ellipsoid(rx: float, ry: float, rz: float) -> ArrayMesh:
	var rings := []
	var n := 7
	for i in n + 1:
		var a := lerpf(-PI / 2, PI / 2, float(i) / n)
		rings.append([sin(a) * ry, maxf(cos(a) * rx, 0.0004), maxf(cos(a) * rz, 0.0004)])
	return ShintyMesh.loft(rings, 10)
