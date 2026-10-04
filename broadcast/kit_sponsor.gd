class_name ShintyKitSponsor
extends RefCounted
## Prints a sponsor across the front of a player's shirt.
##
## Works with any ShintyPlayerModel: it finds the shirt pieces the model hangs
## on its "Spine" bone (or the bone the skeleton names in "sponsor_holder") (or their size, recorded as "mesh_aabb" when they were
## baked into one mesh), measures them, and adds a print flush with the front of
## the shirt, so it follows the body and fits slim and heavy builds. Call it
## after setup() (and again after rebuild(), which clears it). On an imported
## body the print is skinned like the shirt, so it bends with the chest.
##
## `texture` is white on transparent (ShintySponsors.shirt_texture()); it is
## printed in the kit's trim colour unless `color` is given, on a panel in the
## shirt colour.

const NODE_NAME := "SponsorPrint"


static func apply(model: ShintyPlayerModel, texture: Texture2D, color = null) -> MeshInstance3D:
	var skel := model.find_child("Skeleton3D", true, false) as Skeleton3D
	if skel == null or texture == null:
		return null
	var holder := skel.get_node_or_null(str(skel.get_meta("sponsor_holder", "SpineAttach"))) as Node3D
	if holder == null:
		return null
	for parent in [holder, skel]:
		var old: Node = (parent as Node).get_node_or_null(NODE_NAME)
		if old:
			old.free()
	# The shirt's front surface and width, from the meshes on this bone.
	var box := AABB()
	var first := true
	if holder.has_meta("mesh_aabb"):  # the pieces were baked into one body mesh
		box = holder.get_meta("mesh_aabb")
		first = false
	for c in holder.get_children():
		if c is MeshInstance3D and c.mesh and c.name != NODE_NAME:
			var b: AABB = c.transform * c.mesh.get_aabb()
			box = b if first else box.merge(b)
			first = false
	if first:
		return null
	var width := box.size.x * 0.8
	var height := width / 3.0
	# Across the middle of the box (the upper abdomen, or the chest when the
	# model hangs it on its chest).
	var centre := Vector3(box.get_center().x, box.position.y + box.size.y * 0.5, box.position.z)
	# The shirt's front across that height (an imported body records it as
	# "front_curve", x and z samples), so the print wraps round the body
	# instead of standing off it like a board.
	var curve: PackedVector2Array = holder.get_meta("front_curve", PackedVector2Array())
	if curve.size() >= 2:  # keep it off the sides, where the body turns away
		width *= 0.85
		height = width / 3.0
	# A panel in the shirt's own colour behind the print keeps it readable on
	# hoops and stripes (on a plain shirt it doesn't show).
	var root := MeshInstance3D.new()
	root.name = NODE_NAME
	var panel_col: Color = model.shirt_color
	var ink: Color = color if color is Color else model.trim_color
	if ink.is_equal_approx(panel_col):
		ink = Color.WHITE if panel_col.get_luminance() < 0.5 else Color(0.08, 0.08, 0.1)
	root.mesh = _strip(width * 1.08, height * 1.25, centre, curve, 0.011)
	var pm := StandardMaterial3D.new()
	pm.albedo_color = panel_col
	pm.roughness = 0.8
	root.material_override = pm
	root.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mi := MeshInstance3D.new()
	mi.name = "Print"
	mi.mesh = _strip(width, height, centre, curve, 0.0145)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = texture
	mat.albedo_color = ink
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.4
	mat.roughness = 0.75
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	if skel.has_meta("torso_skin") and holder is BoneAttachment3D:
		# Skinned like the shirt under it (an imported body), so it bends
		# with the chest when the player twists and swings.
		var at := skel.get_bone_global_rest(skel.find_bone((holder as BoneAttachment3D).bone_name)).origin
		var skin := skel.create_skin_from_rest_transforms()
		var data: Array = skel.get_meta("torso_skin")
		for m in [root, mi]:
			m.mesh = _skinned(m.mesh, at, data)
			m.skin = skin
		skel.add_child(root)
		root.skeleton = NodePath("..")
		mi.skeleton = NodePath("../..")
	else:
		holder.add_child(root)
	return root


## The strip moved into skeleton space at `at`, each corner weighted like the
## nearest point of the shirt (`data`: points, then 4 bones and 4 weights each).
static func _skinned(mesh: ArrayMesh, at: Vector3, data: Array) -> ArrayMesh:
	var pts: PackedVector3Array = data[0]
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	for i in verts.size():
		verts[i] += at
		var best := 0
		var dist := INF
		for k in pts.size():
			var d := pts[k].distance_squared_to(verts[i])
			if d < dist:
				dist = d
				best = k
		for j in 4:
			bones.append(data[1][best * 4 + j])
			weights.append(data[2][best * 4 + j])
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


## A strip facing -Z (the model's front), centred on `c`, following `curve`
## (x, z of the shirt front; flat at c.z without one), `lift` in front of it.
## UVs read the right way round from the front.
static func _strip(width: float, height: float, c: Vector3, curve: PackedVector2Array, lift: float) -> ArrayMesh:
	var cols := 24
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var norms := PackedVector3Array()
	for i in cols + 1:
		var u := float(i) / cols
		var x := c.x + (0.5 - u) * width  # the front faces -Z, so left to right on screen is +x to -x
		var z := c.z
		if curve.size() >= 2:
			z = _front_z(curve, x)
		for j in 2:
			verts.append(Vector3(x, c.y + (0.5 - j) * height, z - lift))
			uvs.append(Vector2(u, j))
			norms.append(Vector3(0, 0, -1))
	var idx := PackedInt32Array()
	for i in cols:
		var a := i * 2
		idx.append_array([a, a + 2, a + 1, a + 1, a + 2, a + 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


static func _front_z(curve: PackedVector2Array, x: float) -> float:
	if x <= curve[0].x:
		return curve[0].y
	for i in range(1, curve.size()):
		if x <= curve[i].x:
			var t := (x - curve[i - 1].x) / maxf(curve[i].x - curve[i - 1].x, 1e-5)
			return lerpf(curve[i - 1].y, curve[i].y, t)
	return curve[curve.size() - 1].y
