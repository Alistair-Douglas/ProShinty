class_name ShintyKitSponsor
extends RefCounted
## Prints a sponsor across the front of a player's shirt.
##
## Works with any ShintyPlayerModel: it finds the shirt pieces the model hangs
## on its "Spine" bone (or their size, recorded as "mesh_aabb" when they were
## baked into one mesh), measures them, and adds a print flush with the front of
## the shirt, so it follows the body and fits slim and heavy builds. Call it
## after setup() (and again after rebuild(), which clears it).
##
## `texture` is white on transparent (ShintySponsors.shirt_texture()); it is
## printed in the kit's trim colour unless `color` is given.

const NODE_NAME := "SponsorPrint"


static func apply(model: ShintyPlayerModel, texture: Texture2D, color = null) -> MeshInstance3D:
	var skel := model.find_child("Skeleton3D", true, false) as Skeleton3D
	if skel == null or texture == null:
		return null
	var holder := skel.get_node_or_null("SpineAttach") as Node3D
	if holder == null:
		return null
	var old := holder.get_node_or_null(NODE_NAME)
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
	var mi := MeshInstance3D.new()
	mi.name = NODE_NAME
	var q := QuadMesh.new()
	q.size = Vector2(width, height)
	mi.mesh = q
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = texture
	mat.albedo_color = color if color is Color else model.trim_color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.4
	mat.roughness = 0.75
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Across the upper abdomen, below the chest number and crest, facing -Z
	# (the model's front).
	mi.position = Vector3(box.get_center().x, box.position.y + box.size.y * 0.76, box.position.z - 0.004)
	mi.rotation.y = PI
	holder.add_child(mi)
	return mi
