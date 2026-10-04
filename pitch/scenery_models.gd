extends RefCounted
## Tree and car models made in Blender or taken from free packs, used in place
## of the code-built ones when they are present.
##
## Drop glTF (.glb/.gltf) or .fbx files into pitch/models/trees/ and
## pitch/models/cars/. The start of the file name says what a model is:
##   trees: pine_*, birch_*, rowan_*, beech_*, broadleaf_*, yew_*, bush_*
##   cars:  hatchback_*, estate_*, saloon_*, suv_*, landrover_*, pickup_*,
##          van_*, minibus_* (any other name is a car of its own size)
## A file named like the model plus _far (pine_1_far.glb) is its far version.
## Trees without one get a plain blob crown and trunk sized to the model;
## cars without one stay as they are at any distance.
##
## Models are recentred so the base sits on the origin, and cars are turned so
## their length runs along +X. Trees are scaled to the height the venue asks
## for. A car material whose name contains paint, body or main is repainted
## per car; other materials keep their colours.

const TREE_DIR := "res://pitch/models/trees"
const CAR_DIR := "res://pitch/models/cars"
const EXTS := ["glb", "gltf", "fbx"]
const LEAF_WORDS := ["leaf", "leaves", "foliage", "needle", "canopy", "crown", "green"]
const PAINT_WORDS := ["paint", "body", "main", "carcolor", "car_color", "colour"]
## Usual length in metres of each kind of car, used to size the models.
const CAR_LENGTH := {"hatchback": 4.0, "estate": 4.7, "saloon": 4.6, "sedan": 4.6, "suv": 4.6,
		"landrover": 4.5, "pickup": 5.3, "van": 5.3, "minibus": 6.2}


class Model:
	var path: String
	var kind: String
	var mesh: Mesh
	var far: Mesh           # the model's own far version, if it has one
	var size: Vector3       # after recentring (and turning, for cars)
	var canopy: AABB        # trees: where the leaves are
	var leaf_color := Color(0.3, 0.42, 0.16)
	var bark_color := Color(0.3, 0.26, 0.21)
	var far_parts: Array = []   # [[mesh, material, offset]], see ShintyPitch._add_far_trees


static var _libraries := {}


## Every model in `dir`, grouped by kind. Loaded once per run.
static func library(dir: String) -> Dictionary:
	if _libraries.has(dir):
		return _libraries[dir]
	var lib := {}
	_libraries[dir] = lib
	var files := {}
	if not DirAccess.dir_exists_absolute(dir):
		return lib
	for f in DirAccess.get_files_at(dir):
		# Exported games list the source file only through its .import/.remap.
		f = f.trim_suffix(".import").trim_suffix(".remap")
		if f.get_extension().to_lower() in EXTS:
			files[f] = true
	for f in files:
		var stem: String = f.get_basename()
		if stem.ends_with("_far"):
			continue
		var model := _load_model(dir.path_join(f), dir == CAR_DIR)
		if model == null:
			continue
		for g in files:
			if String(g).get_basename() == stem + "_far":
				model.far = _flatten(dir.path_join(g), model, true)
		model.kind = stem.get_slice("_", 0).to_lower()
		if not lib.has(model.kind):
			lib[model.kind] = []
		lib[model.kind].append(model)
	return lib


## A model of the first kind in `kinds` that has any, or null. Uses `rng`
## only when there is a model to pick, so venues lay out exactly as before
## when the folder is empty.
static func pick(dir: String, kinds: Array, rng: RandomNumberGenerator) -> Model:
	var lib := library(dir)
	for k in kinds:
		if lib.has(k):
			var list: Array = lib[k]
			return list[rng.randi() % list.size()]
	return null


## Any car model, or null.
static func pick_car(rng: RandomNumberGenerator, kinds: Array = []) -> Model:
	var lib := library(CAR_DIR)
	if lib.is_empty():
		return null
	if kinds.is_empty():
		kinds = lib.keys()
		kinds.sort()
		kinds = [kinds[rng.randi() % kinds.size()]]
	return pick(CAR_DIR, kinds, rng)


static func car_length(m: Model) -> float:
	if CAR_LENGTH.has(m.kind):
		return CAR_LENGTH[m.kind]
	return m.size.x if m.size.x > 3.0 and m.size.x < 7.5 else 4.4


static func _load_model(path: String, is_car: bool) -> Model:
	var m := Model.new()
	m.path = path
	m.mesh = _flatten(path, m, false, is_car)
	if m.mesh == null:
		return null
	if not is_car:
		_measure_tree(m, m.get_meta("surfaces"))
	m.remove_meta("surfaces")
	return m


## Bakes every mesh in the scene at `path` into one mesh with as few
## surfaces as it can: one per textured material, plus (trees) one for all
## the plain-coloured materials, their colours baked into the vertices, and
## (cars) one for the paint. Each surface is a draw call per tree cell, so
## this matters more than triangles. The first call (`far` false) works out the recentring for
## `m`; the far version reuses it so the two line up.
static func _flatten(path: String, m: Model, far: bool, is_car := false) -> Mesh:
	var res = load(path)
	var scene: Node
	if res is PackedScene:
		scene = res.instantiate()
	elif res is Mesh:
		scene = MeshInstance3D.new()
		scene.mesh = res
	else:
		push_warning("scenery model %s did not load" % path)
		return null
	var parts := []   # [mesh, surface, xform, material]
	var bounds := AABB()
	var first := true
	var nodes: Array = scene.find_children("*", "MeshInstance3D", true, false)
	if scene is MeshInstance3D:
		nodes.push_front(scene)
	for mi: MeshInstance3D in nodes:
		if mi.mesh == null:
			continue
		var xf := Transform3D.IDENTITY
		var n: Node = mi
		while n != scene and n is Node3D:
			xf = n.transform * xf
			n = n.get_parent()
		for s in mi.mesh.get_surface_count():
			if mi.mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			parts.append([mi.mesh, s, xf, mi.get_active_material(s)])
		var box := xf * mi.mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	if parts.is_empty():
		scene.free()
		return null
	if not far:
		# Base centre on the origin; cars turned so their length runs along X.
		var turn := Basis.IDENTITY
		if is_car and bounds.size.z > bounds.size.x:
			turn = Basis(Vector3.UP, PI * 0.5)
		var c := bounds.get_center()
		var fix := Transform3D(turn, Vector3.ZERO) * Transform3D(Basis.IDENTITY, -Vector3(c.x, bounds.position.y, c.z))
		m.set_meta("fix", fix)
		m.size = (fix * bounds).size
	var fix: Transform3D = m.get_meta("fix")
	var surfaces := []   # [arrays, material]
	var named_paint := false
	for p in parts:
		var st := SurfaceTool.new()
		st.append_from(p[0], p[1], fix * p[2])
		var mat: Material = p[3]
		if is_car and mat is BaseMaterial3D and _is_paint(mat):
			named_paint = true
			mat = mat.duplicate()
			mat.vertex_color_use_as_albedo = true
			mat.vertex_color_is_srgb = true
			mat.albedo_color = Color.WHITE
		surfaces.append([st.commit_to_arrays(), mat])
	if is_car and not named_paint:
		surfaces = _split_paint(surfaces)
	if not far:
		m.set_meta("surfaces", surfaces)
	surfaces = _merge_surfaces(surfaces, not is_car)
	var im := ImporterMesh.new()
	for sf in surfaces:
		var mat: Material = sf[1]
		im.add_surface(Mesh.PRIMITIVE_TRIANGLES, sf[0], [], {}, mat, mat.resource_name if mat else "")
	scene.free()
	# Simpler versions for distance; the renderer picks one by screen size.
	im.generate_lods(25.0, 60.0, [])
	return im.get_mesh()


## Cars textured from one colour atlas (like Kenney's) have no paint
## material, so the paint is found from the texture: the triangles using the
## atlas cell that covers the most area, leaving out dark and grey ones
## (tyres, glass, trim),
## move to a surface of their own that takes each car's paint.
static func _split_paint(surfaces: Array) -> Array:
	var area := {}
	var total := 0.0
	var keys := []   # per surface: the colour key of each triangle
	for sf in surfaces:
		var k := PackedInt32Array()
		keys.append(k)
		var mat = sf[1]
		if not (mat is BaseMaterial3D and mat.albedo_texture):
			continue
		var img: Image = mat.albedo_texture.get_image()
		if img == null:
			continue
		if img.is_compressed():
			img.decompress()
		var arrays: Array = sf[0]
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uvs = arrays[Mesh.ARRAY_TEX_UV]
		if uvs == null:
			continue
		var idx = arrays[Mesh.ARRAY_INDEX]
		if idx == null:
			idx = PackedInt32Array(range(verts.size()))
			arrays[Mesh.ARRAY_INDEX] = idx
		var w := img.get_width()
		var h := img.get_height()
		for t in range(0, idx.size(), 3):
			var uv: Vector2 = (uvs[idx[t]] + uvs[idx[t + 1]] + uvs[idx[t + 2]]) / 3.0
			var c := img.get_pixel(clampi(int(fposmod(uv.x, 1.0) * w), 0, w - 1), clampi(int(fposmod(uv.y, 1.0) * h), 0, h - 1))
			var key := -1
			var a := (verts[idx[t + 1]] - verts[idx[t]]).cross(verts[idx[t + 2]] - verts[idx[t]]).length() * 0.5
			total += a
			if c.v >= 0.3 and c.s >= 0.25:
				# By atlas cell rather than exact colour: swatches are often gradients.
				key = int(fposmod(uv.y, 1.0) * 4.0) * 8 + int(fposmod(uv.x, 1.0) * 8.0)
				area[key] = area.get(key, 0.0) + a
			k.append(key)
	if area.is_empty():
		return surfaces
	var paint_key: int = area.keys()[0]
	for key in area:
		if area[key] > area[paint_key]:
			paint_key = key
	if area[paint_key] < total * 0.12:
		return surfaces  # no clear body colour (a white or grey car): leave it
	var paint := StandardMaterial3D.new()
	paint.resource_name = "paint"
	paint.vertex_color_use_as_albedo = true
	paint.vertex_color_is_srgb = true
	paint.roughness = 0.35
	paint.metallic = 0.2
	var out := []
	for i in surfaces.size():
		var k: PackedInt32Array = keys[i]
		if k.is_empty():
			out.append(surfaces[i])
			continue
		var arrays: Array = surfaces[i][0]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var rest := PackedInt32Array()
		var body := PackedInt32Array()
		for t in k.size():
			for j in 3:
				if k[t] == paint_key:
					body.append(idx[t * 3 + j])
				else:
					rest.append(idx[t * 3 + j])
		for part in [[rest, surfaces[i][1]], [body, paint]]:
			if part[0].is_empty():
				continue
			var copy := arrays.duplicate()
			copy[Mesh.ARRAY_INDEX] = part[0]
			out.append([copy, part[1]])
	return out


## Joins surfaces that share a material. With `bake_flat`, untextured opaque
## materials all become one surface with their colours in the vertices
## (trees: the instance colour then varies the whole tree a little).
static func _merge_surfaces(surfaces: Array, bake_flat: bool) -> Array:
	var groups := {}
	var order := []
	var flat := StandardMaterial3D.new()
	flat.resource_name = "baked"
	flat.vertex_color_use_as_albedo = true
	flat.vertex_color_is_srgb = true
	flat.roughness = 0.9
	for sf in surfaces:
		var arrays: Array = sf[0]
		var mat: Material = sf[1]
		var key: Variant = mat
		if bake_flat and mat is BaseMaterial3D and mat.albedo_texture == null \
				and mat.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and not mat.vertex_color_use_as_albedo:
			key = flat
			var n: int = arrays[Mesh.ARRAY_VERTEX].size()
			var cols := PackedColorArray()
			cols.resize(n)
			cols.fill(mat.albedo_color)
			arrays = arrays.duplicate()
			arrays[Mesh.ARRAY_COLOR] = cols
			# Only what every surface has, so they can join.
			for a in [Mesh.ARRAY_TANGENT, Mesh.ARRAY_TEX_UV2, Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS,
					Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM1, Mesh.ARRAY_CUSTOM2, Mesh.ARRAY_CUSTOM3]:
				arrays[a] = null
		if not groups.has(key):
			groups[key] = []
			order.append(key)
		groups[key].append(arrays)
	var out := []
	for key in order:
		var list: Array = groups[key]
		if list.size() == 1:
			out.append([list[0], key])
			continue
		var am := ArrayMesh.new()
		var st := SurfaceTool.new()
		for arrays in list:
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			st.append_from(am, am.get_surface_count() - 1, Transform3D.IDENTITY)
		out.append([st.commit_to_arrays(), key])
	return out


static func _is_paint(mat: Material) -> bool:
	var n := mat.resource_name.to_lower()
	for w in PAINT_WORDS:
		if w in n:
			return true
	return false


static func _is_leaf(mat: Material) -> bool:
	if mat == null:
		return false
	var n := mat.resource_name.to_lower()
	for w in LEAF_WORDS:
		if w in n:
			return true
	return mat is BaseMaterial3D and mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED


## Where the crown is, and the colours of leaves and bark, for the far blob.
static func _measure_tree(m: Model, surfaces: Array) -> void:
	var crown := AABB()
	var found := false
	var leaf_sum := Vector4.ZERO
	var bark_sum := Vector4.ZERO
	for sf in surfaces:
		var mat: Material = sf[1]
		var arrays: Array = sf[0]
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var col := _material_color(mat)
		var w := float(verts.size())
		if _is_leaf(mat):
			for v in verts:
				crown = AABB(v, Vector3.ZERO) if not found else crown.expand(v)
				found = true
			leaf_sum += Vector4(col.r, col.g, col.b, 1.0) * w
		else:
			bark_sum += Vector4(col.r, col.g, col.b, 1.0) * w
	if not found:
		crown = AABB(Vector3(-m.size.x * 0.5, m.size.y * 0.4, -m.size.z * 0.5), Vector3(m.size.x, m.size.y * 0.6, m.size.z))
	m.canopy = crown
	if leaf_sum.w > 0.0:
		m.leaf_color = Color(leaf_sum.x / leaf_sum.w, leaf_sum.y / leaf_sum.w, leaf_sum.z / leaf_sum.w)
	if bark_sum.w > 0.0:
		m.bark_color = Color(bark_sum.x / bark_sum.w, bark_sum.y / bark_sum.w, bark_sum.z / bark_sum.w)


## A material's average colour (its colour times its texture's average), sRGB.
static func _material_color(mat: Material) -> Color:
	if not mat is BaseMaterial3D:
		return Color(0.5, 0.5, 0.5)
	var c: Color = mat.albedo_color
	var tex: Texture2D = mat.albedo_texture
	if tex:
		var img := tex.get_image()
		if img:
			if img.is_compressed():
				img.decompress()
			img.convert(Image.FORMAT_RGBA8)
			img.resize(16, 16, Image.INTERPOLATE_BILINEAR)
			# Weighted by alpha, so the cut-away parts of a leaf texture don't count.
			var sum := Vector4.ZERO
			for y in 16:
				for x in 16:
					var t := img.get_pixel(x, y)
					sum += Vector4(t.r, t.g, t.b, 1.0) * t.a
			if sum.w > 0.0:
				c = Color(c.r * sum.x / sum.w, c.g * sum.y / sum.w, c.b * sum.z / sum.w)
	return c
