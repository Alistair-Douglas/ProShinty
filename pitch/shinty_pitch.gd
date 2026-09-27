@tool
class_name ShintyPitch
extends Node3D
## A 3D shinty pitch modelled on Aberdour's home ground: open parkland with a
## tree-lined touchline and cars parked under the trees on the south side, a
## clump of big dark trees, earthworks and a wooded hill on the north side,
## houses on the rise behind the west end, and the Firth of Forth to the south.
##
## Everything is generated when the node enters the tree (also in the editor),
## so this one script plus the three shaders beside it is the whole pitch.
##
## Coordinates: the pitch is centred on this node, lengthways along X and
## across along Z. West goal is at -X, east goal at +X, north touchline at -Z.
## Match code that works in yards with the origin in a corner (like the 2D
## game) converts with sim_to_world() / world_to_sim().

enum Lighting { SUMMER_AFTERNOON, SUMMER_EVENING, OVERCAST }
enum Detail { LOW, MEDIUM, HIGH }

const YARD_M := 0.9144
const GOAL_WIDTH_YD := 4.0      # 12 ft between the posts
const GOAL_HEIGHT_YD := 3.3333  # 10 ft to the crossbar
const SEA_LEVEL_M := -3.5

@export_group("Pitch")
## Shinty rules allow 140 to 170 yards. Matches the 2D game's 150.
@export_range(140.0, 170.0, 1.0) var length_yd := 150.0:
	set(v):
		length_yd = v
		_queue_rebuild()
## Shinty rules allow 70 to 80 yards. Matches the 2D game's 75.
@export_range(70.0, 80.0, 1.0) var width_yd := 75.0:
	set(v):
		width_yd = v
		_queue_rebuild()
## World units per yard. 0.9144 means 1 unit = 1 metre (Godot's convention).
## Set to 1.0 if the match code wants to work in yards directly.
@export var units_per_yard := YARD_M:
	set(v):
		units_per_yard = max(v, 0.01)
		_queue_rebuild()
## Physics floor under the pitch and its surrounds, on collision layer 1.
@export var add_ground_collision := true:
	set(v):
		add_ground_collision = v
		_queue_rebuild()

@export_group("Look")
@export var lighting: Lighting = Lighting.SUMMER_AFTERNOON:
	set(v):
		lighting = v
		_queue_rebuild()
## Adds a WorldEnvironment (sky, fog, tone mapping) and the sun. Turn off if
## the scene that uses the pitch brings its own.
@export var include_environment := true:
	set(v):
		include_environment = v
		_queue_rebuild()
## Trees, hills, houses, cars and sea. Off leaves just the pitch and a flat
## surround, which is handy for debugging.
@export var show_scenery := true:
	set(v):
		show_scenery = v
		_queue_rebuild()
@export var scenery_detail: Detail = Detail.MEDIUM:
	set(v):
		scenery_detail = v
		_queue_rebuild()
## Simple white hails so the pitch looks right on its own. Turn off once the
## real goal models are placed at goal_position().
@export var show_placeholder_goals := true:
	set(v):
		show_placeholder_goals = v
		_queue_rebuild()
@export var show_flags := true:
	set(v):
		show_flags = v
		_queue_rebuild()
## 0 = lush green, 1 = dry midsummer park.
@export_range(0.0, 1.0) var grass_wear := 0.55:
	set(v):
		grass_wear = v
		_queue_rebuild()
@export var layout_seed := 1877:
	set(v):
		layout_seed = v
		_queue_rebuild()

var _gen: Node3D
var _pending := false
var _noise := FastNoiseLite.new()
var _mats := {}
# Half length and half width of the pitch in metres. Scenery is laid out in
# metres around these and scaled to world units at the end.
var _hl := 0.0
var _hw := 0.0


func _ready() -> void:
	_rebuild()


# --- Public API -------------------------------------------------------------

## World-space size of the playing area (length along X, width along Z).
func pitch_size() -> Vector2:
	return Vector2(length_yd, width_yd) * units_per_yard


## Converts a 2D-sim position in yards (origin at the north-west corner, x
## along the pitch, y across it) into a point in this node's space.
func sim_to_world(sim: Vector2, height_yd := 0.0) -> Vector3:
	return Vector3(sim.x - length_yd * 0.5, height_yd, sim.y - width_yd * 0.5) * units_per_yard


## Inverse of sim_to_world(); height is dropped.
func world_to_sim(p: Vector3) -> Vector2:
	return Vector2(p.x / units_per_yard + length_yd * 0.5, p.z / units_per_yard + width_yd * 0.5)


## Centre of the goal line at one end, on the ground. end 0 = west (sim x = 0),
## end 1 = east (sim x = length).
func goal_position(end: int) -> Vector3:
	var x := length_yd * 0.5 * units_per_yard
	return Vector3(-x if end == 0 else x, 0.0, 0.0)


## Transform for a goal model: origin at the centre of the goal line, -Z of the
## basis pointing out of the pitch (so the net sits behind the line), +X across.
func goal_transform(end: int) -> Transform3D:
	var yaw := PI * 0.5 if end == 0 else -PI * 0.5
	return Transform3D(Basis(Vector3.UP, yaw), goal_position(end))


## Ground height in world units at a point in this node's space (0 on the pitch).
func ground_height(p: Vector3) -> float:
	var s := units_per_yard / YARD_M
	return _height_m(p.x / s, p.z / s) * s


# --- Build ------------------------------------------------------------------

func _queue_rebuild() -> void:
	if not is_inside_tree() or _pending:
		return
	_pending = true
	_rebuild.call_deferred()


func _rebuild() -> void:
	_pending = false
	if _gen:
		remove_child(_gen)
		_gen.queue_free()
	_gen = Node3D.new()
	_gen.name = "Generated"
	add_child(_gen)

	_hl = length_yd * YARD_M * 0.5
	_hw = width_yd * YARD_M * 0.5
	_noise.seed = layout_seed
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.012
	_mats.clear()

	var s := units_per_yard / YARD_M
	var root := Node3D.new()  # everything below is in metres
	root.name = "Site"
	root.scale = Vector3.ONE * s
	_gen.add_child(root)

	_build_ground(root)
	_build_markers(s)
	if show_placeholder_goals:
		_build_goals(root)
	if show_flags:
		_build_flags(root)
	if show_scenery:
		var rng := RandomNumberGenerator.new()
		rng.seed = layout_seed
		_build_sea(root)
		_build_trees(root, rng)
		_build_houses(root, rng)
		_build_cars(root, rng)
		_build_site_fence_and_hut(root)
	if add_ground_collision:
		_build_collision(s)
	if include_environment:
		_build_environment()


## Height of the land in metres. Flat across the park, rising to the wooded
## hill north-east, a gentle rise with houses to the west and north-west, and
## dropping to the beach and sea to the south.
func _height_m(x: float, z: float) -> float:
	if not show_scenery:
		return 0.0
	var hl := _hl
	var hw := _hw
	var ne := 42.0 * smoothstep(-hl * 0.2, hl * 0.35, x) * smoothstep(hw + 50.0, hw + 120.0, -z)
	var east := 34.0 * smoothstep(hl + 40.0, hl + 140.0, x)
	var west := 18.0 * smoothstep(hl + 45.0, hl + 230.0, -x) * (1.0 - smoothstep(hw + 30.0, hw + 110.0, z))
	var north := 22.0 * smoothstep(hw + 55.0, hw + 240.0, -z) * (1.0 - smoothstep(-hl * 0.3, hl * 0.2, x) * 0.3)
	var rise: float = max(max(ne, east), max(west, north))
	var south := -7.5 * smoothstep(hw + 52.0, hw + 95.0, z)
	# Keep the park (pitch plus surrounds) dead flat.
	var fx := smoothstep(hl + 22.0, hl + 40.0, abs(x))
	var fz := smoothstep(hw + 20.0, hw + 38.0, abs(z))
	var wild: float = max(fx, fz)
	var bumps := _noise.get_noise_2d(x, z) * (2.0 + rise * 0.18)
	return (rise + bumps) * wild + south


func _build_ground(root: Node3D) -> void:
	# 4 m grid over the park and nearby hills, coarser further out so the land
	# runs on towards the horizon without costing many triangles.
	var xs: PackedFloat32Array
	var zs: PackedFloat32Array
	if show_scenery:
		xs = _grid_axis(_hl + 360.0, _hl + 1600.0)
		zs = _grid_axis(_hw + 320.0, _hw + 1500.0)
	else:
		xs = _grid_axis(_hl + 40.0, _hl + 40.0)
		zs = _grid_axis(_hw + 40.0, _hw + 40.0)
	var nx := xs.size()
	var nz := zs.size()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for iz in nz:
		for ix in nx:
			var x := xs[ix]
			var z := zs[iz]
			var h := _height_m(x, z)
			st.set_color(_ground_mask(x, z, h))
			st.set_uv(Vector2(x, z))
			st.add_vertex(Vector3(x, h, z))
	for iz in nz - 1:
		for ix in nx - 1:
			var i := iz * nx + ix
			st.add_index(i)
			st.add_index(i + 1)
			st.add_index(i + nx)
			st.add_index(i + 1)
			st.add_index(i + nx + 1)
			st.add_index(i + nx)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "Ground"
	mi.mesh = st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = _load_local("ground.gdshader")
	mat.set_shader_parameter("unit", YARD_M)  # the Site node is in metres
	mat.set_shader_parameter("pitch_size", Vector2(length_yd, width_yd))
	mat.set_shader_parameter("wear", grass_wear)
	mi.material_override = mat
	root.add_child(mi)


## Symmetric grid coordinates: 4 m steps out to `inner`, then growing to `outer`.
func _grid_axis(inner: float, outer: float) -> PackedFloat32Array:
	var half: Array[float] = []
	var v := 0.0
	var step := 4.0
	while v < outer:
		half.append(v)
		if v >= inner:
			step = min(step * 1.25, 120.0)
		v += step
	half.append(outer)
	var out := PackedFloat32Array()
	for i in range(half.size() - 1, 0, -1):
		out.append(-half[i])
	for h in half:
		out.append(h)
	return out


## Vertex colour masks for the ground shader (r earth, g rough, b gravel, a sand).
func _ground_mask(x: float, z: float, h: float) -> Color:
	var hl := _hl
	var hw := _hw
	var c := Color(0, 0, 0, 0)
	if not show_scenery:
		return c
	# Rough grass everywhere beyond the mown park.
	var park: float = 1.0 - max(smoothstep(hl + 24.0, hl + 36.0, abs(x)), smoothstep(hw + 22.0, hw + 32.0, abs(z)))
	c.g = 1.0 - park
	# Long-grass strip in front of the earthworks (photo: reeds before the site).
	if z < -(hw + 10.0) and z > -(hw + 18.0) and x > -hl * 0.15:
		c.g = 0.8
	# Earthworks at the foot of the wooded hill.
	if z < -(hw + 18.0) and z > -(hw + 48.0) and x > -hl * 0.05 and x < hl + 26.0:
		c.r = 1.0
		c.g = 0.0
	# Gravel: car park behind the west goal and the verge under the south trees.
	if x < -(hl + 10.0) and x > -(hl + 32.0) and z < -6.0 and z > -(hw + 6.0):
		c.b = 1.0
	if z > hw + 12.0 and z < hw + 19.0 and abs(x) < hl + 20.0:
		c.b = 0.85
	# Beach between the grass and the sea.
	c.a = smoothstep(-0.8, -2.2, h)
	if c.a > 0.0:
		c.g *= 1.0 - c.a
	return c


func _build_markers(s: float) -> void:
	var names := ["GoalWest", "GoalEast"]
	for end in 2:
		var m := Marker3D.new()
		m.name = names[end]
		m.transform = goal_transform(end)
		_gen.add_child(m)
	var centre := Marker3D.new()
	centre.name = "CentreSpot"
	_gen.add_child(centre)
	# Broadcast camera spot above the south touchline, in front of the trees.
	var cam := Marker3D.new()
	cam.name = "BroadcastCamera"
	var pos := Vector3(0.0, 20.0, _hw + 10.0) * s
	cam.transform = Transform3D(Basis.looking_at(-pos + Vector3(0, 0, -4.0 * s)), pos)
	_gen.add_child(cam)


func _build_goals(root: Node3D) -> void:
	var holder := Node3D.new()
	holder.name = "PlaceholderGoals"
	root.add_child(holder)
	var half_w := GOAL_WIDTH_YD * YARD_M * 0.5
	var height := GOAL_HEIGHT_YD * YARD_M
	var depth := 1.3
	var r := 0.05
	var white := _mat("goal_post", Color(0.96, 0.96, 0.96), 0.4)
	var net := StandardMaterial3D.new()
	net.albedo_color = Color(1, 1, 1, 0.22)
	net.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	net.cull_mode = BaseMaterial3D.CULL_DISABLED
	net.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for end in 2:
		var g := Node3D.new()
		var sx := -1.0 if end == 0 else 1.0
		g.position = Vector3(sx * _hl, 0, 0)
		holder.add_child(g)
		for side in [-1.0, 1.0]:
			_add_cyl(g, Vector3(0, height * 0.5, side * half_w), r, height, white)
			_add_cyl(g, Vector3(sx * depth, height * 0.4, side * half_w), r * 0.6, height * 0.8, white)
		var bar := _add_cyl(g, Vector3(0, height, 0), r, half_w * 2.0 + r * 2.0, white)
		bar.rotation.x = PI * 0.5
		# Net: back, roof and sides as one see-through box behind the line.
		var box := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(depth, height, half_w * 2.0)
		box.mesh = bm
		box.material_override = net
		box.position = Vector3(sx * depth * 0.5, height * 0.5, 0)
		box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		g.add_child(box)


func _build_flags(root: Node3D) -> void:
	var pole := _mat("flag_pole", Color(0.95, 0.95, 0.95), 0.5)
	var cloth := _mat("flag_cloth", Color(0.85, 0.12, 0.1), 0.8)
	cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
	var spots := [Vector2(-_hl, -_hw), Vector2(_hl, -_hw), Vector2(-_hl, _hw), Vector2(_hl, _hw),
			Vector2(0, -_hw - 1.0), Vector2(0, _hw + 1.0)]
	for p in spots:
		var f := Node3D.new()
		f.position = Vector3(p.x, 0, p.y)
		root.add_child(f)
		_add_cyl(f, Vector3(0, 0.75, 0), 0.02, 1.5, pole)
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(0.4, 0.3)
		q.mesh = qm
		q.material_override = cloth
		q.position = Vector3(0.2, 1.33, 0)
		f.add_child(q)


func _build_sea(root: Node3D) -> void:
	var sea := MeshInstance3D.new()
	sea.name = "Sea"
	var pm := PlaneMesh.new()
	pm.size = Vector2(9000, 6000)
	sea.mesh = pm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.16, 0.27, 0.36)
	m.roughness = 0.12
	m.metallic_specular = 0.7
	sea.material_override = m
	sea.position = Vector3(0, SEA_LEVEL_M, _hw + 3000.0 - 40.0)
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(sea)
	if scenery_detail == Detail.LOW:
		return
	# The far shore of the Forth: a long low hazy ridge.
	var shore := MeshInstance3D.new()
	shore.name = "FarShore"
	var bm := PrismMesh.new()
	bm.size = Vector3(260.0, 70.0, 9000.0)
	shore.mesh = bm
	shore.rotation.y = PI * 0.5
	shore.position = Vector3(-600, SEA_LEVEL_M + 30.0, _hw + 5200.0)
	shore.scale = Vector3(1.0, 1.0, 1.0)
	shore.material_override = _mat("far_shore", Color(0.42, 0.5, 0.5), 1.0)
	shore.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(shore)


# --- Trees ------------------------------------------------------------------

class TreeBatch:
	var trunks: Array[Transform3D] = []
	var canopies: Array[Transform3D] = []
	var colors: Array[Color] = []


func _build_trees(root: Node3D, rng: RandomNumberGenerator) -> void:
	var hl := _hl
	var hw := _hw
	var big := TreeBatch.new()
	var small := TreeBatch.new()  # woodland and bushes, lower poly

	# South touchline: a long row of mature broadleaves with cars under them.
	var x := -hl - 45.0
	while x < hl + 45.0:
		_add_broadleaf(big, rng, Vector3(x + rng.randf_range(-2, 2), 0, hw + 22.0 + rng.randf_range(-2, 2.5)))
		x += rng.randf_range(10.0, 15.0)
	# A looser second row towards the beach, with gaps to see the water.
	x = -hl - 80.0
	while x < hl + 80.0:
		if rng.randf() < 0.6:
			_add_broadleaf(big, rng, Vector3(x, 0, hw + 40.0 + rng.randf_range(-5, 5)))
		x += rng.randf_range(12.0, 22.0)

	# North side: the clump of big dark round trees left of centre.
	for i in 4:
		var px := lerpf(-hl * 0.42, -hl * 0.12, i / 3.0) + rng.randf_range(-3, 3)
		_add_dark_round(big, rng, Vector3(px, 0, -(hw + 17.0) + rng.randf_range(-3, 3)))
	_add_dark_round(big, rng, Vector3(hl * 0.36, 0, -(hw + 19.0)))
	# Broadleaves along the north-west side and around the car park.
	x = -hl - 40.0
	while x < -hl * 0.48:
		_add_broadleaf(big, rng, Vector3(x, 0, -(hw + 15.0) + rng.randf_range(-3, 3)))
		x += rng.randf_range(11.0, 16.0)
	for i in 5:
		_add_broadleaf(big, rng, Vector3(-hl - 38.0 + rng.randf_range(-4, 4), 0, rng.randf_range(-hw, hw)))
	# Bushes in the long grass in front of the earthworks.
	x = -hl * 0.1
	while x < hl + 20.0:
		if rng.randf() < 0.55:
			_add_bush(small, rng, Vector3(x, 0, -(hw + rng.randf_range(11.0, 17.0))))
		x += rng.randf_range(4.0, 9.0)

	# Woodland on the hills: dense on the north-east hill and east end,
	# scattered hedgerow trees on the western and northern fields.
	var spacing: float = [11.0, 7.5, 6.0][scenery_detail]
	var gz := -(hw + 330.0)
	while gz < hw + 60.0:
		var gx := -(hl + 350.0)
		while gx < hl + 350.0:
			var px := gx + rng.randf_range(-spacing, spacing) * 0.45
			var pz := gz + rng.randf_range(-spacing, spacing) * 0.45
			var h := _height_m(px, pz)
			var wooded := (px > -hl * 0.15 and pz < -(hw + 50.0)) or px > hl + 42.0
			var p := 0.0
			if wooded and h > 3.0:
				p = 0.92
			elif h > 2.0:
				p = 0.035
			if rng.randf() < p:
				_add_woodland(small, rng, Vector3(px, h - 0.4, pz))
			gx += spacing
		gz += spacing

	_emit_batch(root, big, 18, 9, "TreesNear")
	_emit_batch(root, small, 10, 6, "Woodland")


func _leaf_color(rng: RandomNumberGenerator, dark := false) -> Color:
	var c: Color
	if dark:
		c = Color(0.16, 0.24, 0.12).lerp(Color(0.2, 0.3, 0.14), rng.randf())
	else:
		c = Color(0.26, 0.38, 0.14).lerp(Color(0.36, 0.47, 0.18), rng.randf())
	return c.srgb_to_linear()


func _add_broadleaf(b: TreeBatch, rng: RandomNumberGenerator, base: Vector3) -> void:
	var trunk_h := rng.randf_range(3.5, 6.0)
	var trunk_r := rng.randf_range(0.3, 0.55)
	b.trunks.append(Transform3D(Basis.from_scale(Vector3(trunk_r, trunk_h + 2.0, trunk_r)), base + Vector3(0, (trunk_h + 2.0) * 0.5, 0)))
	var r := rng.randf_range(4.2, 6.8)
	var top := base + Vector3(0, trunk_h + r * 0.75, 0)
	var col := _leaf_color(rng)
	b.canopies.append(Transform3D(Basis.from_scale(Vector3(r, r * 0.82, r)), top))
	b.colors.append(col)
	for i in rng.randi_range(3, 5):
		var a := rng.randf() * TAU
		var rr := r * rng.randf_range(0.5, 0.72)
		var off := Vector3(cos(a) * r * 0.62, rng.randf_range(-0.25, 0.45) * r, sin(a) * r * 0.62)
		b.canopies.append(Transform3D(Basis.from_scale(Vector3(rr, rr * 0.85, rr)), top + off))
		b.colors.append(col * rng.randf_range(0.9, 1.08))


func _add_dark_round(b: TreeBatch, rng: RandomNumberGenerator, base: Vector3) -> void:
	var r := rng.randf_range(5.5, 7.5)
	b.trunks.append(Transform3D(Basis.from_scale(Vector3(0.6, 3.0, 0.6)), base + Vector3(0, 1.5, 0)))
	var col := _leaf_color(rng, true)
	b.canopies.append(Transform3D(Basis.from_scale(Vector3(r, r * 1.2, r)), base + Vector3(0, r * 1.15, 0)))
	b.colors.append(col)
	for i in 3:
		var a := rng.randf() * TAU
		var rr := r * rng.randf_range(0.55, 0.7)
		b.canopies.append(Transform3D(Basis.from_scale(Vector3(rr, rr * 1.1, rr)),
				base + Vector3(cos(a) * r * 0.5, r * rng.randf_range(0.8, 1.8), sin(a) * r * 0.5)))
		b.colors.append(col * rng.randf_range(0.9, 1.1))


func _add_woodland(b: TreeBatch, rng: RandomNumberGenerator, base: Vector3) -> void:
	var r := rng.randf_range(3.2, 5.2)
	var dark := rng.randf() < 0.4
	var col := _leaf_color(rng, dark)
	b.canopies.append(Transform3D(Basis.from_scale(Vector3(r, r * 1.1, r)), base + Vector3(0, r * 1.25, 0)))
	b.colors.append(col)
	var a := rng.randf() * TAU
	b.canopies.append(Transform3D(Basis.from_scale(Vector3(r, r, r) * 0.7), base + Vector3(cos(a) * r * 0.6, r * 1.6, sin(a) * r * 0.6)))
	b.colors.append(col * 1.05)


func _add_bush(b: TreeBatch, rng: RandomNumberGenerator, base: Vector3) -> void:
	var r := rng.randf_range(1.0, 2.2)
	b.canopies.append(Transform3D(Basis.from_scale(Vector3(r * 1.3, r, r * 1.3)), base + Vector3(0, r * 0.6, 0)))
	b.colors.append(_leaf_color(rng, rng.randf() < 0.5))


func _emit_batch(root: Node3D, b: TreeBatch, segs: int, rings: int, label: String) -> void:
	if not b.trunks.is_empty():
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.7
		cyl.bottom_radius = 1.0
		cyl.height = 1.0
		cyl.radial_segments = 7
		cyl.rings = 1
		cyl.cap_top = false
		cyl.cap_bottom = false
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = cyl
		mm.instance_count = b.trunks.size()
		for i in b.trunks.size():
			mm.set_instance_transform(i, b.trunks[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = label + "Trunks"
		mmi.multimesh = mm
		mmi.material_override = _mat("bark", Color(0.3, 0.26, 0.21), 0.95)
		root.add_child(mmi)
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = segs
	sphere.rings = rings
	var mm2 := MultiMesh.new()
	mm2.transform_format = MultiMesh.TRANSFORM_3D
	mm2.use_colors = true
	mm2.mesh = sphere
	mm2.instance_count = b.canopies.size()
	for i in b.canopies.size():
		mm2.set_instance_transform(i, b.canopies[i])
		mm2.set_instance_color(i, b.colors[i])
	var mmi2 := MultiMeshInstance3D.new()
	mmi2.name = label + "Canopy"
	mmi2.multimesh = mm2
	var cm := ShaderMaterial.new()
	cm.shader = _load_local("canopy.gdshader")
	mmi2.material_override = cm
	root.add_child(mmi2)


# --- Houses -----------------------------------------------------------------

func _build_houses(root: Node3D, rng: RandomNumberGenerator) -> void:
	var holder := Node3D.new()
	holder.name = "Houses"
	root.add_child(holder)
	var hl := _hl
	var hw := _hw
	var count: int = [6, 10, 14][scenery_detail]
	# A street of cottages on the rise behind the west end, facing the pitch.
	for i in count:
		var pz := -hw - 70.0 + i * 12.5 + rng.randf_range(-1.5, 1.5)
		var px := -hl - 95.0 - rng.randf_range(0.0, 6.0) - (i % 2) * 2.0
		_add_house(holder, rng, Vector3(px, _height_m(px, pz), pz), 0.0)
	# A terrace on the hill to the north-west, seen past the dark trees.
	for i in int(count * 0.5) + 2:
		var px := -hl * 0.95 + i * 11.0
		var pz := -hw - 95.0 - rng.randf_range(0.0, 4.0)
		_add_house(holder, rng, Vector3(px, _height_m(px, pz), pz), PI * 0.5)
	# A couple of bigger houses further up the west hill.
	for i in 3:
		var px := -hl - 150.0 - i * 25.0
		var pz := -hw - 20.0 + i * 30.0
		_add_house(holder, rng, Vector3(px, _height_m(px, pz), pz), rng.randf_range(-0.3, 0.3))


func _add_house(holder: Node3D, rng: RandomNumberGenerator, base: Vector3, yaw: float) -> void:
	var walls := [Color(0.9, 0.88, 0.82), Color(0.76, 0.72, 0.64), Color(0.66, 0.58, 0.48),
			Color(0.82, 0.8, 0.76), Color(0.58, 0.52, 0.44)]
	var roofs := [Color(0.24, 0.25, 0.28), Color(0.3, 0.3, 0.33), Color(0.45, 0.24, 0.18)]
	var w := rng.randf_range(6.0, 7.5)     # depth, across the ridge
	var l := rng.randf_range(8.0, 12.0)    # length, along the ridge
	var h := rng.randf_range(5.0, 6.5)
	var rh := rng.randf_range(2.4, 3.2)
	var house := Node3D.new()
	house.position = base
	house.rotation.y = yaw
	holder.add_child(house)
	var wi := rng.randi() % walls.size()
	var body := _add_box(house, Vector3(w, h + 1.5, l), Vector3(0, (h + 1.5) * 0.5 - 1.5, 0),
			_mat("wall%d" % wi, walls[wi], 0.95))
	body.name = "Walls"
	var roof := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(w + 0.6, rh, l + 0.4)
	roof.mesh = pm
	var ri := rng.randi() % roofs.size()
	roof.material_override = _mat("roof%d" % ri, roofs[ri], 0.85)
	roof.position = Vector3(0, h + rh * 0.5, 0)
	house.add_child(roof)
	_add_box(house, Vector3(0.7, 1.6, 1.0), Vector3(0, h + rh * 0.6, l * 0.5 - 0.6), _mat("wall%d" % wi, walls[wi], 0.95))
	var glass := _mat("window", Color(0.12, 0.14, 0.17), 0.2)
	var frame := _mat("window_frame", Color(0.95, 0.95, 0.93), 0.8)
	var n_win := int(l / 3.2)
	for side in [-1.0, 1.0]:
		for i in n_win:
			var wz := (i - (n_win - 1) * 0.5) * 3.0
			for wy in [1.4, 3.9]:
				if wy > h - 1.2:
					continue
				_add_box(house, Vector3(0.08, 1.35, 1.05), Vector3(side * w * 0.5, wy, wz), frame)
				_add_box(house, Vector3(0.1, 1.15, 0.85), Vector3(side * w * 0.5, wy, wz), glass)


# --- Cars -------------------------------------------------------------------

func _build_cars(root: Node3D, rng: RandomNumberGenerator) -> void:
	var holder := Node3D.new()
	holder.name = "Cars"
	root.add_child(holder)
	var hl := _hl
	var hw := _hw
	# Car park behind the west goal, nose in towards the pitch.
	var z := -hw - 2.0
	while z < -9.0:
		if rng.randf() < 0.7:
			_add_car(holder, rng, Vector3(-hl - 18.0, 0, z), 0.0)
		z += 2.9
	z = -hw
	while z < -12.0:
		if rng.randf() < 0.45:
			_add_car(holder, rng, Vector3(-hl - 27.0, 0, z), PI)
		z += 2.9
	# Parked on the verge under the south trees, facing the pitch.
	var x := -hl * 0.1
	var placed_van := false
	while x < hl + 12.0:
		if rng.randf() < 0.65:
			if not placed_van and x > hl * 0.2:
				_add_van(holder, Vector3(x, 0, hw + 15.5))
				placed_van = true
				x += 1.0
			else:
				_add_car(holder, rng, Vector3(x, 0, hw + 15.0), PI * 0.5)
		x += 3.1


func _add_car(holder: Node3D, rng: RandomNumberGenerator, pos: Vector3, yaw: float) -> void:
	var paints := [Color(0.93, 0.93, 0.93), Color(0.08, 0.08, 0.09), Color(0.62, 0.64, 0.66),
			Color(0.1, 0.15, 0.32), Color(0.62, 0.08, 0.08), Color(0.3, 0.31, 0.33)]
	var idx := rng.randi() % paints.size()
	var paint := _mat("paint%d" % idx, paints[idx], 0.35)
	var car := Node3D.new()
	car.position = pos
	car.rotation.y = yaw + rng.randf_range(-0.05, 0.05)
	holder.add_child(car)
	var length := rng.randf_range(4.0, 4.6)
	_add_box(car, Vector3(length, 0.72, 1.8), Vector3(0, 0.66, 0), paint)
	_add_box(car, Vector3(length * 0.52, 0.56, 1.62), Vector3(-length * 0.06, 1.3, 0), _mat("car_glass", Color(0.1, 0.12, 0.15), 0.15))
	_add_box(car, Vector3(length * 0.48, 0.07, 1.58), Vector3(-length * 0.06, 1.6, 0), paint)
	var tyre := _mat("tyre", Color(0.06, 0.06, 0.06), 0.9)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var w := _add_cyl(car, Vector3(sx * length * 0.32, 0.33, sz * 0.82), 0.33, 0.24, tyre)
			w.rotation.x = PI * 0.5


func _add_van(holder: Node3D, pos: Vector3) -> void:
	var van := Node3D.new()
	van.position = pos
	van.rotation.y = PI * 0.5
	holder.add_child(van)
	var white := _mat("paint0", Color(0.93, 0.93, 0.93), 0.35)
	_add_box(van, Vector3(5.3, 1.95, 2.0), Vector3(-0.3, 1.35, 0), white)
	_add_box(van, Vector3(0.9, 0.8, 1.9), Vector3(2.55, 1.9, 0), _mat("car_glass", Color(0.1, 0.12, 0.15), 0.15))
	_add_box(van, Vector3(1.2, 0.9, 2.0), Vector3(2.4, 0.8, 0), white)
	var tyre := _mat("tyre", Color(0.06, 0.06, 0.06), 0.9)
	for sx in [-1.9, 2.1]:
		for sz in [-1.0, 1.0]:
			var w := _add_cyl(van, Vector3(sx, 0.36, sz * 0.9), 0.36, 0.26, tyre)
			w.rotation.x = PI * 0.5


# --- Earthworks fence and hut -----------------------------------------------

func _build_site_fence_and_hut(root: Node3D) -> void:
	var hl := _hl
	var hw := _hw
	var fz := -(hw + 49.0)
	var x0 := -hl * 0.05
	var x1 := hl + 26.0
	var posts := MultiMesh.new()
	posts.transform_format = MultiMesh.TRANSFORM_3D
	var box := BoxMesh.new()
	box.size = Vector3(0.08, 1.9, 0.08)
	posts.mesh = box
	var n := int((x1 - x0) / 2.5) + 1
	posts.instance_count = n
	for i in n:
		var px := x0 + i * 2.5
		posts.set_instance_transform(i, Transform3D(Basis(), Vector3(px, _height_m(px, fz) + 0.95, fz)))
	var pmi := MultiMeshInstance3D.new()
	pmi.name = "FencePosts"
	pmi.multimesh = posts
	var grey := _mat("fence", Color(0.45, 0.47, 0.45), 0.6)
	pmi.material_override = grey
	root.add_child(pmi)
	var mesh_mat := StandardMaterial3D.new()
	mesh_mat.albedo_color = Color(0.4, 0.42, 0.4, 0.35)
	mesh_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var panel := _add_box(root, Vector3(x1 - x0, 1.8, 0.02), Vector3((x0 + x1) * 0.5, 0.95, fz), mesh_mat)
	panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Timber hut with a red tiled roof by the earthworks (seen in photo 1).
	var hut := Node3D.new()
	hut.name = "Hut"
	hut.position = Vector3(-hl * 0.02, 0, -(hw + 26.0))
	hut.rotation.y = 0.15
	root.add_child(hut)
	_add_box(hut, Vector3(9.0, 3.0, 5.5), Vector3(0, 1.5, 0), _mat("timber", Color(0.55, 0.42, 0.3), 0.9))
	var roof := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(6.2, 1.8, 9.6)
	roof.mesh = pm
	roof.rotation.y = PI * 0.5
	roof.material_override = _mat("hut_roof", Color(0.55, 0.3, 0.22), 0.85)
	roof.position = Vector3(0, 3.9, 0)
	hut.add_child(roof)
	# Soil heaps on the site.
	var soil := _mat("soil", Color(0.5, 0.32, 0.22), 1.0)
	for p in [Vector3(hl * 0.3, 0, -(hw + 34.0)), Vector3(hl * 0.62, 0, -(hw + 40.0)), Vector3(hl * 0.12, 0, -(hw + 42.0))]:
		var heap := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 1.0
		sm.height = 2.0
		sm.radial_segments = 12
		sm.rings = 6
		sm.is_hemisphere = true
		heap.mesh = sm
		heap.scale = Vector3(9.0, 3.5, 6.0)
		heap.position = p
		heap.material_override = soil
		root.add_child(heap)


# --- Physics and environment ------------------------------------------------

func _build_collision(s: float) -> void:
	var body := StaticBody3D.new()
	body.name = "GroundBody"
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(_hl * 2.0 + 60.0, 2.0, _hw * 2.0 + 60.0) * s
	shape.shape = bs
	shape.position = Vector3(0, -1.0 * s, 0)
	body.add_child(shape)
	_gen.add_child(body)


func _build_environment() -> void:
	var p := _lighting_preset()
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-p.elevation, p.yaw, 0.0)
	sun.light_color = p.sun_color
	sun.light_energy = p.sun_energy
	sun.shadow_enabled = true
	sun.shadow_blur = p.shadow_blur
	sun.directional_shadow_max_distance = 260.0 * units_per_yard / YARD_M
	sun.directional_shadow_blend_splits = true
	_gen.add_child(sun)

	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = _load_local("sky.gdshader")
	sky_mat.set_shader_parameter("top_color", p.sky_top)
	sky_mat.set_shader_parameter("horizon_color", p.sky_horizon)
	sky_mat.set_shader_parameter("cloud_cover", p.clouds)
	sky_mat.set_shader_parameter("cloud_color", p.cloud_color)
	sky_mat.set_shader_parameter("cloud_shadow_color", p.cloud_shadow)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = p.ambient
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = p.exposure
	env.tonemap_white = 6.0
	env.fog_enabled = true
	env.fog_light_color = p.sky_horizon
	env.fog_density = 0.0009 / units_per_yard * YARD_M
	env.fog_aerial_perspective = 0.7
	env.fog_sky_affect = 0.0
	env.ssao_enabled = true
	env.ssao_radius = 1.5
	env.ssao_intensity = 1.2
	env.glow_enabled = true
	env.glow_intensity = 0.3
	env.glow_bloom = 0.02
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	_gen.add_child(we)


func _lighting_preset() -> Dictionary:
	match lighting:
		Lighting.SUMMER_EVENING:
			return {
				"elevation": 17.0, "yaw": -105.0, "sun_color": Color(1.0, 0.84, 0.66), "sun_energy": 1.25,
				"shadow_blur": 1.5, "sky_top": Color(0.2, 0.36, 0.66), "sky_horizon": Color(0.86, 0.8, 0.72),
				"clouds": 0.38, "cloud_color": Color(1.0, 0.93, 0.85), "cloud_shadow": Color(0.62, 0.6, 0.66),
				"ambient": 0.8, "exposure": 1.05,
			}
		Lighting.OVERCAST:
			return {
				"elevation": 45.0, "yaw": -30.0, "sun_color": Color(0.9, 0.92, 0.95), "sun_energy": 0.35,
				"shadow_blur": 4.0, "sky_top": Color(0.55, 0.58, 0.62), "sky_horizon": Color(0.74, 0.76, 0.78),
				"clouds": 0.95, "cloud_color": Color(0.8, 0.81, 0.83), "cloud_shadow": Color(0.56, 0.58, 0.62),
				"ambient": 1.3, "exposure": 1.1,
			}
		_:
			return {
				"elevation": 52.0, "yaw": -30.0, "sun_color": Color(1.0, 0.97, 0.92), "sun_energy": 1.35,
				"shadow_blur": 1.0, "sky_top": Color(0.14, 0.36, 0.78), "sky_horizon": Color(0.64, 0.78, 0.93),
				"clouds": 0.34, "cloud_color": Color(1, 1, 1), "cloud_shadow": Color(0.66, 0.7, 0.78),
				"ambient": 0.75, "exposure": 1.0,
			}


# --- Helpers ----------------------------------------------------------------

func _load_local(file: String) -> Resource:
	return load(get_script().resource_path.get_base_dir().path_join(file))


func _mat(key: String, color: Color, roughness: float) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	_mats[key] = m
	return m


func _add_box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _add_cyl(parent: Node3D, pos: Vector3, radius: float, height: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 10
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi
