@tool
class_name ShintyPitch
extends Node3D
## A 3D shinty pitch at a real ground, picked with `venue`:
##
## - Aberdour (Fife): open parkland between the railway and Brachi Woods to the
##   north and a tree-lined path to the south, with the beach and the Firth of
##   Forth past the east end.
## - Kingussie (The Dell): a striped, railed pitch with a stand behind the west
##   hail, dugouts and a gravel car park on the north side, and the River Spey
##   curving round the south side and the east end, under the Cairngorms.
## - Tighnabruaich (Kyles Athletic): on the shore of the Kyles of Bute, with a
##   rocky sea wall and the loch along one side, the shore road and a wooded
##   hillside along the other, and the clubhouse and tennis court at one end.
## - Portree (Skye Camanachd): on a shelf above the town, with the white social
##   club and the school on one side, a steep heather bank with the ad boards
##   on the other, a wooded gully and glamping pods past one end, and Portree
##   Bay and Ben Tianavaig beyond the other.
##
## Everything is generated when the node enters the tree (also in the editor).
## The layout of each ground lives in venues/; this script holds the pitch,
## markings, lighting, the public API and the building blocks every ground uses.
##
## Coordinates: the pitch is centred on this node, lengthways along X and
## across along Z. West goal is at -X, east goal at +X, the far (north)
## touchline at -Z. Match code that works in yards with the origin in a corner
## (like the 2D game) converts with sim_to_world() / world_to_sim().

enum Venue { ABERDOUR, KINGUSSIE, TIGHNABRUAICH, PORTREE }
enum Lighting { SUMMER_AFTERNOON, SUMMER_EVENING, OVERCAST }
enum Detail { LOW, MEDIUM, HIGH }

## Tree and car models dropped into pitch/models/ (see scenery_models.gd).
const SceneryModels := preload("res://pitch/scenery_models.gd")

## Display names for menus, in Venue order.
const VENUE_NAMES := ["Aberdour", "Kingussie (The Dell)", "Tighnabruaich (Kyles Athletic)", "Portree (Skye)"]
## The club that plays at each venue, for matching a home team to its ground.
const VENUE_CLUBS := ["Aberdour", "Kingussie", "Kyles", "Skye"]
const YARD_M := 0.9144
const GOAL_WIDTH_YD := 4.0      # 12 ft between the posts
const GOAL_HEIGHT_YD := 3.3333  # 10 ft to the crossbar

@export var venue: Venue = Venue.ABERDOUR:
	set(v):
		venue = v
		_queue_rebuild()

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
## Trees, hills, buildings, cars and water. Off leaves just the pitch and a
## flat surround, which is handy for debugging.
@export var show_scenery := true:
	set(v):
		show_scenery = v
		_queue_rebuild()
@export var scenery_detail: Detail = Detail.MEDIUM:
	set(v):
		scenery_detail = v
		_queue_rebuild()
## Shadows and screen effects: LOW for older graphics, MEDIUM for laptops
## with integrated graphics (Intel Iris Xe and up), HIGH for the full look
## (8K shadow map, soft contact shadows, SSIL and screen-space reflections). Scenery amount is `scenery_detail`, set separately.
@export var graphics_quality: Detail = Detail.HIGH:
	set(v):
		graphics_quality = v
		_queue_rebuild()
## Simple white hails so the pitch looks right on its own. Turn off once the
## real goal models are placed at goal_transform().
@export var show_placeholder_goals := true:
	set(v):
		show_placeholder_goals = v
		_queue_rebuild()
@export var show_flags := true:
	set(v):
		show_flags = v
		_queue_rebuild()
## 0 = lush green, 1 = dry midsummer park. Negative uses the ground's own look.
@export_range(-1.0, 1.0) var grass_wear := -1.0:
	set(v):
		grass_wear = v
		_queue_rebuild()
@export var layout_seed := 1877:
	set(v):
		layout_seed = v
		_queue_rebuild()

var _gen: Node3D
var _pending := false
var _mats := {}
var _layout: RefCounted  # the venue script instance (venues/*.gd)
var _cars := {}  # car model -> [[holder, local transform, paint]], see add_car
## Half length and half width of the pitch in metres. Scenery is laid out in
## metres around these and scaled to world units at the end.
var hl := 0.0
var hw := 0.0
var noise := FastNoiseLite.new()


func _ready() -> void:
	if _gen == null:  # not already built off the tree (see build_now)
		_rebuild()


## Builds most of the ground before the node joins the tree, and is safe to
## call from a worker thread so a menu can get a ground ready without a
## stall. Call finish_build() on the main thread afterwards: merging the
## scenery reads meshes back from the renderer, which only works there.
func build_now() -> void:
	_rebuild(false)


func finish_build() -> void:
	_finish_build()


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


## Where this ground's pitchside ad boards go (see ShintyAdBoard.place_row):
## an Array of rows [from, to, first], with `from` and `to` on the ground in
## this node's units (boards face the pitch) and `first` the index of the
## first sponsor. A venue can set its own with board_rows(); by default there
## is a row along the far touchline, where the TV camera sees it, and one
## behind each hail.
func board_rows() -> Array:
	var rows: Array
	if _layout != null and _layout.has_method("board_rows"):
		rows = _layout.board_rows()
	else:
		rows = [[Vector2(-hl, -hw - 3.7), Vector2(hl, -hw - 3.7), 0],
			[Vector2(-hl - 4.6, -hw * 0.8), Vector2(-hl - 4.6, hw * 0.8), 3],
			[Vector2(hl + 4.6, -hw * 0.8), Vector2(hl + 4.6, hw * 0.8), 5]]
	var s := units_per_yard / YARD_M
	var out := []
	for r in rows:
		var a: Vector2 = r[0]
		var b: Vector2 = r[1]
		out.append([Vector3(a.x, height_m(a.x, a.y), a.y) * s, Vector3(b.x, height_m(b.x, b.y), b.y) * s, r[2]])
	return out


## Ground height in world units at a point in this node's space (0 on the pitch).
func ground_height(p: Vector3) -> float:
	var s := units_per_yard / YARD_M
	return height_m(p.x / s, p.z / s) * s


# --- Build ------------------------------------------------------------------

func _queue_rebuild() -> void:
	if not is_inside_tree() or _pending:
		return
	_pending = true
	_rebuild.call_deferred()


func _rebuild(finish := true) -> void:
	_pending = false
	if _gen:
		remove_child(_gen)
		_gen.queue_free()
	_gen = Node3D.new()
	_gen.name = "Generated"
	add_child(_gen)

	hl = length_yd * YARD_M * 0.5
	hw = width_yd * YARD_M * 0.5
	noise.seed = layout_seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.012
	_mats.clear()
	var files := ["aberdour.gd", "kingussie.gd", "tighnabruaich.gd", "portree.gd"]
	_layout = _load_local("venues/" + files[venue]).new(self)

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
		_build_water(root)
		_cars.clear()
		_layout.build(root, rng)
		_emit_car_models(root)
	if finish:
		_finish_build()


func _finish_build() -> void:
	var s := units_per_yard / YARD_M
	if show_scenery:
		_batch_scenery(_gen.get_node("Site"))
	if add_ground_collision:
		_build_collision(s)
	if include_environment:
		_build_environment()


## Height of the land in metres at (x, z) metres from the centre spot.
func height_m(x: float, z: float) -> float:
	if not show_scenery:
		return 0.0
	return _layout.height_m(x, z)


## 0 inside the flat park around the pitch, rising to 1 beyond it.
func wildness(x: float, z: float, margin_x := 22.0, margin_z := 20.0) -> float:
	var fx := smoothstep(hl + margin_x, hl + margin_x + 18.0, abs(x))
	var fz := smoothstep(hw + margin_z, hw + margin_z + 18.0, abs(z))
	return max(fx, fz)


func _build_ground(root: Node3D) -> void:
	# 4 m grid over the park and nearby land, much coarser further out so the
	# land runs on to the horizon hills without costing many triangles.
	var xs: PackedFloat32Array
	var zs: PackedFloat32Array
	if show_scenery:
		xs = _grid_axis(hl + 360.0, 7000.0)
		zs = _grid_axis(hw + 320.0, 7000.0)
	else:
		xs = _grid_axis(hl + 40.0, hl + 40.0)
		zs = _grid_axis(hw + 40.0, hw + 40.0)
	var nx := xs.size()
	var nz := zs.size()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for iz in nz:
		for ix in nx:
			var x := xs[ix]
			var z := zs[iz]
			var h := height_m(x, z)
			st.set_color(_layout.ground_mask(x, z, h) if show_scenery else Color(0, 0, 0, 0))
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
	st.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.name = "Ground"
	mi.mesh = st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = _load_local("ground.gdshader")
	mat.set_shader_parameter("unit", YARD_M)  # the Site node is in metres
	mat.set_shader_parameter("noise_tex", _load_local("ground_noise.png"))
	mat.set_shader_parameter("pitch_size", Vector2(length_yd, width_yd))
	var look: Dictionary = _layout.ground_look()
	for k in look:
		mat.set_shader_parameter(k, look[k])
	if grass_wear >= 0.0:
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
			step = min(step * 1.25, 400.0)
		v += step
	half.append(outer)
	var out := PackedFloat32Array()
	for i in range(half.size() - 1, 0, -1):
		out.append(-half[i])
	for h in half:
		out.append(h)
	return out


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
	# Broadcast camera spot above the south touchline.
	var cam := Marker3D.new()
	cam.name = "BroadcastCamera"
	var pos := Vector3(0.0, 20.0, hw + 10.0) * s
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
	var white := mat("goal_post", Color(0.96, 0.96, 0.96), 0.4)
	var net := StandardMaterial3D.new()
	net.albedo_color = Color(1, 1, 1, 0.22)
	net.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	net.cull_mode = BaseMaterial3D.CULL_DISABLED
	net.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for end in 2:
		var g := Node3D.new()
		var sx := -1.0 if end == 0 else 1.0
		g.position = Vector3(sx * hl, 0, 0)
		holder.add_child(g)
		for side in [-1.0, 1.0]:
			add_cyl(g, Vector3(0, height * 0.5, side * half_w), r, height, white)
			add_cyl(g, Vector3(sx * depth, height * 0.4, side * half_w), r * 0.6, height * 0.8, white)
		var bar := add_cyl(g, Vector3(0, height, 0), r, half_w * 2.0 + r * 2.0, white)
		bar.rotation.x = PI * 0.5
		var box := add_box(g, Vector3(depth, height, half_w * 2.0), Vector3(sx * depth * 0.5, height * 0.5, 0), net)
		box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _build_flags(root: Node3D) -> void:
	var pole := mat("flag_pole", Color(0.95, 0.95, 0.95), 0.5)
	var cloth := mat("flag_cloth", Color(0.85, 0.12, 0.1), 0.8)
	cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Corner flags only: shinty has none at halfway.
	for p in [Vector2(-hl, -hw), Vector2(hl, -hw), Vector2(-hl, hw), Vector2(hl, hw)]:
		var f := Node3D.new()
		f.position = Vector3(p.x, 0, p.y)
		root.add_child(f)
		add_cyl(f, Vector3(0, 0.75, 0), 0.02, 1.5, pole)
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(0.4, 0.3)
		q.mesh = qm
		q.material_override = cloth
		q.position = Vector3(0.2, 1.33, 0)
		f.add_child(q)


## One big flat water plane; the ground mesh hides it except where the venue
## carves the land below its level (the sea at Aberdour, the Spey at Kingussie).
func _build_water(root: Node3D) -> void:
	var w: Dictionary = _layout.water()
	var sea := MeshInstance3D.new()
	sea.name = "Water"
	var pm := PlaneMesh.new()
	pm.size = Vector2(16000, 16000)
	sea.mesh = pm
	var m := ShaderMaterial.new()
	m.shader = _load_local("water.gdshader")
	m.set_shader_parameter("deep_color", w.color)
	m.set_shader_parameter("roughness", w.roughness)
	m.set_shader_parameter("sky_color", _lighting_preset().sky_horizon)
	if w.has("wave_scale"):
		m.set_shader_parameter("wave_scale", w.wave_scale)
	sea.material_override = m
	sea.position = Vector3(0, w.level, 0)
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(sea)


func _build_collision(s: float) -> void:
	var body := StaticBody3D.new()
	body.name = "GroundBody"
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(hl * 2.0 + 60.0, 2.0, hw * 2.0 + 60.0) * s
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
	sun.directional_shadow_blend_splits = true
	sun.shadow_normal_bias = 1.2
	match graphics_quality:
		Detail.LOW:
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
			sun.directional_shadow_max_distance = 130.0 * units_per_yard / YARD_M
			sun.directional_shadow_split_1 = 0.3
		Detail.MEDIUM:
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
			sun.directional_shadow_max_distance = 220.0 * units_per_yard / YARD_M
			sun.directional_shadow_split_1 = 0.07
			sun.directional_shadow_split_2 = 0.2
			sun.directional_shadow_split_3 = 0.5
		_:
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
			sun.directional_shadow_max_distance = 320.0 * units_per_yard / YARD_M
			sun.directional_shadow_split_1 = 0.05
			sun.directional_shadow_split_2 = 0.15
			sun.directional_shadow_split_3 = 0.4
			sun.light_angular_distance = 0.5  # soft shadow edges (Forward+)
	_gen.add_child(sun)

	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = _load_local("sky.gdshader")
	sky_mat.set_shader_parameter("top_color", p.sky_top)
	sky_mat.set_shader_parameter("horizon_color", p.sky_horizon)
	sky_mat.set_shader_parameter("cloud_cover", clamp(p.clouds + _layout.extra_cloud(), 0.0, 1.0))
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
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = p.exposure * 1.15
	env.fog_enabled = true
	# A little bluer and darker than the horizon so distant hills turn hazy
	# blue rather than washing out white.
	env.fog_light_color = p.sky_horizon.lerp(p.sky_top, 0.35) * 0.8
	env.fog_sun_scatter = 0.08
	env.fog_density = _layout.fog_density() / units_per_yard * YARD_M
	env.fog_aerial_perspective = 0.4
	env.fog_sky_affect = 0.0
	env.glow_enabled = true
	env.glow_intensity = 0.45
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.1
	# Forward+ only (the Compatibility renderer warns about them).
	if RenderingServer.get_current_rendering_method() == "forward_plus":
		env.ssao_enabled = graphics_quality != Detail.LOW
		env.ssao_radius = 1.2
		env.ssao_intensity = 1.6
		env.ssao_light_affect = 0.2
		env.ssil_enabled = graphics_quality == Detail.HIGH
		env.ssil_radius = 4.0
		env.ssr_enabled = graphics_quality == Detail.HIGH
		env.ssr_max_steps = 48
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


# --- Building blocks shared by the venues -------------------------------------

class TreeBatch:
	var trunks: Array[Transform3D] = []
	var trunk_colors: Array[Color] = []
	var canopies: Array[Transform3D] = []
	var colors: Array[Color] = []
	var models := {}  # model -> [[transform, colour], ...]

	func add_trunk(xf: Transform3D, color := Color(0.3, 0.26, 0.21)) -> void:
		trunks.append(xf)
		trunk_colors.append(color.srgb_to_linear())

	## A limb from `from`, leaning `tilt` radians from upright towards `heading`.
	func add_limb(from: Vector3, length: float, radius: float, tilt: float, heading: float) -> void:
		var basis := Basis(Vector3.UP, heading) * Basis(Vector3.RIGHT, tilt)
		var dir := basis * Vector3.UP
		add_trunk(Transform3D(basis * Basis.from_scale(Vector3(radius, length, radius)), from + dir * length * 0.5))


func leaf_color(rng: RandomNumberGenerator, dark := false) -> Color:
	var c: Color
	if dark:
		c = Color(0.16, 0.24, 0.12).lerp(Color(0.2, 0.3, 0.14), rng.randf())
	else:
		c = Color(0.26, 0.38, 0.14).lerp(Color(0.36, 0.47, 0.18), rng.randf())
	return c.srgb_to_linear()


## Puts a tree model of the first kind in `kinds` that has one at `base`,
## `height` metres tall (a Callable, so the rng is only used when there is a
## model). False if there are no models of those kinds.
func _place_tree_model(b: TreeBatch, kinds: Array, rng: RandomNumberGenerator, base: Vector3, height: Callable) -> bool:
	var m = SceneryModels.pick(SceneryModels.TREE_DIR, kinds, rng)
	if m == null:
		return false
	var k: float = height.call() / maxf(m.size.y, 0.01)
	var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * k), base + Vector3(0, -0.1, 0))
	if not b.models.has(m):
		b.models[m] = []
	b.models[m].append([xf, (m.leaf_color * rng.randf_range(0.9, 1.08)).srgb_to_linear()])
	return true


## Mature park tree (sycamore, beech, lime): short trunk, big lumpy crown.
## Smaller ones (size under 0.85) are rowans when there are rowan models.
func add_broadleaf(b: TreeBatch, rng: RandomNumberGenerator, base: Vector3, size := 1.0) -> void:
	var kinds := ["beech", "broadleaf", "rowan"] if size >= 0.85 else ["rowan", "broadleaf", "beech"]
	if _place_tree_model(b, kinds, rng, base, func(): return rng.randf_range(11.0, 16.0) * size):
		return
	var trunk_h := rng.randf_range(3.5, 6.0) * size
	var trunk_r := rng.randf_range(0.3, 0.55) * size
	b.add_trunk(Transform3D(Basis.from_scale(Vector3(trunk_r, trunk_h + 2.0, trunk_r)), base + Vector3(0, (trunk_h + 2.0) * 0.5, 0)))
	var r := rng.randf_range(4.2, 6.8) * size
	for i in 4:
		b.add_limb(base + Vector3(0, trunk_h * rng.randf_range(0.8, 1.0), 0), r * rng.randf_range(0.7, 0.95),
				trunk_r * 0.5, rng.randf_range(0.5, 0.9), i * TAU / 4.0 + rng.randf_range(-0.4, 0.4))
	var top := base + Vector3(0, trunk_h + r * 0.75, 0)
	var col := leaf_color(rng)
	b.canopies.append(Transform3D(Basis.from_scale(Vector3(r, r * 0.82, r)), top))
	b.colors.append(col)
	for i in rng.randi_range(3, 5):
		var a := rng.randf() * TAU
		var rr := r * rng.randf_range(0.5, 0.72)
		var off := Vector3(cos(a) * r * 0.62, rng.randf_range(-0.25, 0.45) * r, sin(a) * r * 0.62)
		b.canopies.append(Transform3D(Basis.from_scale(Vector3(rr, rr * 0.85, rr)), top + off))
		b.colors.append(col * rng.randf_range(0.9, 1.08))


## Dense dark evergreen crown down to the ground (holm oak, yew).
func add_dark_round(b: TreeBatch, rng: RandomNumberGenerator, base: Vector3) -> void:
	if _place_tree_model(b, ["yew"], rng, base, func(): return rng.randf_range(9.0, 12.0)):
		return
	var r := rng.randf_range(5.5, 7.5)
	b.add_trunk(Transform3D(Basis.from_scale(Vector3(0.6, 3.0, 0.6)), base + Vector3(0, 1.5, 0)))
	var col := leaf_color(rng, true)
	b.canopies.append(Transform3D(Basis.from_scale(Vector3(r, r * 1.2, r)), base + Vector3(0, r * 1.15, 0)))
	b.colors.append(col)
	for i in 3:
		var a := rng.randf() * TAU
		var rr := r * rng.randf_range(0.55, 0.7)
		b.canopies.append(Transform3D(Basis.from_scale(Vector3(rr, rr * 1.1, rr)),
				base + Vector3(cos(a) * r * 0.5, r * rng.randf_range(0.8, 1.8), sin(a) * r * 0.5)))
		b.colors.append(col * rng.randf_range(0.9, 1.1))


## Woodland tree seen from a distance: two blobs, no visible trunk.
func add_woodland(b: TreeBatch, rng: RandomNumberGenerator, base: Vector3, dark_share := 0.4) -> void:
	var r := rng.randf_range(3.2, 5.2)
	var col := leaf_color(rng, rng.randf() < dark_share)
	b.canopies.append(Transform3D(Basis.from_scale(Vector3(r, r * 1.1, r)), base + Vector3(0, r * 1.25, 0)))
	b.colors.append(col)
	var a := rng.randf() * TAU
	b.canopies.append(Transform3D(Basis.from_scale(Vector3(r, r, r) * 0.7), base + Vector3(cos(a) * r * 0.6, r * 1.6, sin(a) * r * 0.6)))
	b.colors.append(col * 1.05)


## Birch or alder by the river: thin pale trunk, narrow light crown.
func add_birch(b: TreeBatch, rng: RandomNumberGenerator, base: Vector3) -> void:
	if _place_tree_model(b, ["birch"], rng, base, func(): return rng.randf_range(8.0, 13.0)):
		return
	var h := rng.randf_range(7.0, 12.0)
	b.add_trunk(Transform3D(Basis.from_scale(Vector3(0.18, h, 0.18)), base + Vector3(0, h * 0.5, 0)), Color(0.85, 0.84, 0.8))
	var col := Color(0.4, 0.5, 0.2).lerp(Color(0.5, 0.56, 0.26), rng.randf()).srgb_to_linear()
	var r := rng.randf_range(1.8, 2.8)
	for i in 3:
		var off := Vector3(rng.randf_range(-0.8, 0.8), h * (0.55 + i * 0.17), rng.randf_range(-0.8, 0.8))
		b.canopies.append(Transform3D(Basis.from_scale(Vector3(r, r * 1.3, r) * (1.0 - i * 0.18)), base + off))
		b.colors.append(col * rng.randf_range(0.92, 1.08))


## Scots pine: tall bare trunk with a flat dark crown on top.
func add_pine(b: TreeBatch, rng: RandomNumberGenerator, base: Vector3) -> void:
	if _place_tree_model(b, ["pine"], rng, base, func(): return rng.randf_range(12.0, 19.0)):
		return
	var h := rng.randf_range(10.0, 17.0)
	b.add_trunk(Transform3D(Basis.from_scale(Vector3(0.3, h, 0.3)), base + Vector3(0, h * 0.5, 0)), Color(0.5, 0.33, 0.24))
	var col := Color(0.12, 0.2, 0.12).lerp(Color(0.16, 0.25, 0.14), rng.randf()).srgb_to_linear()
	var r := rng.randf_range(2.5, 3.8)
	b.canopies.append(Transform3D(Basis.from_scale(Vector3(r, r * 0.55, r)), base + Vector3(0, h, 0)))
	b.colors.append(col)
	b.canopies.append(Transform3D(Basis.from_scale(Vector3(r, r * 0.5, r) * 0.7), base + Vector3(rng.randf_range(-1, 1), h - r * 0.6, rng.randf_range(-1, 1))))
	b.colors.append(col * 0.95)


func add_bush(b: TreeBatch, rng: RandomNumberGenerator, base: Vector3) -> void:
	if _place_tree_model(b, ["bush"], rng, base, func(): return rng.randf_range(1.2, 2.6)):
		return
	var r := rng.randf_range(1.0, 2.2)
	b.canopies.append(Transform3D(Basis.from_scale(Vector3(r * 1.3, r, r * 1.3)), base + Vector3(0, r * 0.6, 0)))
	b.colors.append(leaf_color(rng, rng.randf() < 0.5))


## Turns a batch into two MultiMeshes: trunks and limbs, and canopies. Each
## canopy blob is a lumpy core wrapped in `cards` leaf cards, which give the
## ragged outline, the dappled shadows and the gaps you see through real trees.
func emit_trees(root: Node3D, b: TreeBatch, segs: int, rings: int, cards: int, label: String) -> void:
	_emit_tree_models(root, b, label)
	if not b.trunks.is_empty():
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.65
		cyl.bottom_radius = 1.0
		cyl.height = 1.0
		cyl.radial_segments = 7
		cyl.rings = 1
		cyl.cap_top = false
		cyl.cap_bottom = false
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = cyl
		mm.instance_count = b.trunks.size()
		for i in b.trunks.size():
			mm.set_instance_transform(i, b.trunks[i])
			mm.set_instance_color(i, b.trunk_colors[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = label + "Trunks"
		mmi.multimesh = mm
		var bark := ShaderMaterial.new()
		bark.shader = _load_local("bark.gdshader")
		mmi.material_override = bark
		root.add_child(mmi)
	if b.canopies.is_empty():
		return
	var mm2 := MultiMesh.new()
	mm2.transform_format = MultiMesh.TRANSFORM_3D
	mm2.use_colors = true
	if graphics_quality == Detail.LOW:
		cards = int(cards * 0.6)
	mm2.mesh = _canopy_mesh(segs, rings, cards)
	mm2.instance_count = b.canopies.size()
	for i in b.canopies.size():
		mm2.set_instance_transform(i, b.canopies[i])
		mm2.set_instance_color(i, b.colors[i])
	var mmi2 := MultiMeshInstance3D.new()
	mmi2.name = label + "Canopy"
	mmi2.multimesh = mm2
	var cm := ShaderMaterial.new()
	cm.shader = _load_local("canopy.gdshader")
	cm.set_shader_parameter("leaf_tex", _load_local("leaves.png"))
	cm.set_shader_parameter("noise_tex", _load_local("ground_noise.png"))
	mmi2.material_override = cm
	# Far trees swap to a plain blob with no leaf cards (see _split_multimesh).
	var far := ShaderMaterial.new()
	far.shader = _load_local("canopy_far.gdshader")
	far.set_shader_parameter("noise_tex", _load_local("ground_noise.png"))
	far.set_shader_parameter("leaf_tile", _load_local("leaves_tile.png"))
	mmi2.set_meta("far_mesh", _canopy_mesh(maxi(segs - 4, 6), maxi(rings - 2, 4), 0, 0.95))
	mmi2.set_meta("far_material", far)
	root.add_child(mmi2)


## One MultiMesh per tree model. Each carries the parts of its far version
## (see _add_far_trees): the model's own _far file, or else a plain blob
## crown and trunk fitted to the model.
func _emit_tree_models(root: Node3D, b: TreeBatch, label: String) -> void:
	var n := 0
	for m in b.models:
		var list: Array = b.models[m]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = m.mesh
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i][0])
			mm.set_instance_color(i, list[i][1])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "%sModel%d" % [label, n]
		mmi.multimesh = mm
		mmi.set_meta("far_parts", _tree_far_parts(m))
		root.add_child(mmi)
		n += 1


func _tree_far_parts(m) -> Array:
	if m.far:
		return [[m.far, null, Transform3D.IDENTITY]]
	var far := ShaderMaterial.new()
	far.shader = _load_local("canopy_far.gdshader")
	far.set_shader_parameter("noise_tex", _load_local("ground_noise.png"))
	far.set_shader_parameter("leaf_tile", _load_local("leaves_tile.png"))
	var crown: AABB = m.canopy
	var blob := Transform3D(Basis.from_scale(crown.size * 0.5), crown.get_center())
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.65
	cyl.bottom_radius = 1.0
	cyl.height = 1.0
	cyl.radial_segments = 6
	cyl.rings = 1
	cyl.cap_top = false
	cyl.cap_bottom = false
	var top: float = crown.position.y + crown.size.y * 0.3
	var r := maxf(m.size.y * 0.018, 0.1)
	var trunk := Transform3D(Basis.from_scale(Vector3(r, top, r)), Vector3(0, top * 0.5, 0))
	var bark := mat("far_bark%s" % m.bark_color.to_html(), m.bark_color, 0.95)
	return [[_canopy_mesh(10, 6, 0, 0.95), far, blob], [cyl, bark, trunk]]


## Unit-radius canopy blob: a sphere core (UV2.x = 0) of radius `core` and
## leaf cards (UV2.x = 1) scattered over its surface. Every vertex gets a normal pointing
## out from the centre, so the blob shades as one soft mass.
func _canopy_mesh(segs: int, rings: int, cards: int, core := 0.82) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sphere := SphereMesh.new()
	sphere.radius = core
	sphere.height = core * 2.0
	sphere.radial_segments = segs
	sphere.rings = rings
	var arrays := sphere.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for i in idx:
		var v := verts[i]
		st.set_normal(v.normalized())
		st.set_uv(Vector2(0.5, 0.5))
		st.set_uv2(Vector2(0.0, 0.0))
		st.add_vertex(v)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7 + cards
	for c in cards:
		# Even-ish spread over the sphere, more cards towards the top.
		var y := rng.randf_range(-0.55, 1.0)
		var a := rng.randf() * TAU
		var ring := sqrt(1.0 - y * y)
		var n := Vector3(cos(a) * ring, y, sin(a) * ring)
		var centre := n * rng.randf_range(0.8, 1.02)
		var size := rng.randf_range(0.45, 0.7)
		# Card plane roughly facing outwards, spun randomly about its normal.
		var tangent := n.cross(Vector3.UP if absf(n.y) < 0.95 else Vector3.RIGHT).normalized()
		tangent = tangent.rotated(n, rng.randf() * TAU)
		var bitangent := n.cross(tangent)
		var tilt := rng.randf_range(-0.5, 0.5)
		bitangent = (bitangent + n * tilt).normalized()
		var corners := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
		var order := [0, 1, 2, 0, 2, 3]
		for k in order:
			var cc: Vector2 = corners[k]
			var v := centre + (tangent * cc.x + bitangent * cc.y) * size * 0.5
			st.set_normal(v.normalized())
			st.set_uv(cc * 0.5 + Vector2(0.5, 0.5))
			st.set_uv2(Vector2(1.0, rng.randf()))
			st.add_vertex(v)
	st.index()  # share corner vertices: the wind and lumps run once per vertex
	return st.commit()


## Scatters about `count` tufts of long grass over `area` (metres). `density`
## is called with (x, z) and returns the chance, 0 to 1, of keeping a tuft
## there. Colours follow `color`, varied a little per tuft.
func emit_tufts(root: Node3D, rng: RandomNumberGenerator, count: int, area: Rect2, density: Callable, color: Color) -> void:
	count = int(count * [0.4, 1.0, 1.8][scenery_detail])
	var xforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	for i in count:
		var x := rng.randf_range(area.position.x, area.end.x)
		var z := rng.randf_range(area.position.y, area.end.y)
		if rng.randf() >= float(density.call(x, z)):
			continue
		var size := rng.randf_range(0.5, 1.0)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(size * 1.1, size * rng.randf_range(0.6, 1.1), size * 1.1))
		xforms.append(Transform3D(basis, Vector3(x, height_m(x, z) - 0.03, z)))
		colors.append((color * rng.randf_range(0.85, 1.12)).srgb_to_linear())
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _tuft_mesh()
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_color(i, colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "LongGrass"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = [80.0, 140.0, 220.0][graphics_quality]  # a few pixels high beyond this
	var mat := ShaderMaterial.new()
	mat.shader = _load_local("tuft.gdshader")
	mmi.material_override = mat
	root.add_child(mmi)


## Three crossed 1 m x 0.5 m cards standing on the ground (UV.y 0 at the top).
func _tuft_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 3:
		var a := k * PI / 3.0
		var dx := Vector3(cos(a), 0, sin(a)) * 0.5
		var n := Vector3(-sin(a), 0, cos(a))
		var quad := [[-dx, Vector2(0, 1)], [dx, Vector2(1, 1)], [dx + Vector3(0, 0.5, 0), Vector2(1, 0)],
				[-dx + Vector3(0, 0.5, 0), Vector2(0, 0)]]
		for i in [0, 1, 2, 0, 2, 3]:
			st.set_normal(n)
			st.set_uv(quad[i][1])
			st.add_vertex(quad[i][0])
	return st.commit()


## A house with a pitched roof, chimney and windows on its two long sides
## (which face +X and -X before `yaw`).
func add_house(holder: Node3D, rng: RandomNumberGenerator, base: Vector3, yaw: float) -> void:
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
	var wall_mat := mat("wall%d" % wi, walls[wi], 0.95)
	add_box(house, Vector3(w, h + 1.5, l), Vector3(0, (h + 1.5) * 0.5 - 1.5, 0), wall_mat)
	var ri := rng.randi() % roofs.size()
	add_roof(house, Vector3(w + 0.6, rh, l + 0.4), Vector3(0, h + rh * 0.5, 0), mat("roof%d" % ri, roofs[ri], 0.85))
	add_box(house, Vector3(0.7, 1.6, 1.0), Vector3(0, h + rh * 0.6, l * 0.5 - 0.6), wall_mat)
	var glass := mat("window", Color(0.12, 0.14, 0.17), 0.2)
	var frame := mat("window_frame", Color(0.95, 0.95, 0.93), 0.8)
	var n_win := int(l / 3.2)
	for side in [-1.0, 1.0]:
		for i in n_win:
			var wz := (i - (n_win - 1) * 0.5) * 3.0
			for wy in [1.4, 3.9]:
				if wy > h - 1.2:
					continue
				add_box(house, Vector3(0.08, 1.35, 1.05), Vector3(side * w * 0.5, wy, wz), frame)
				add_box(house, Vector3(0.1, 1.15, 0.85), Vector3(side * w * 0.5, wy, wz), glass)


## Pitched roof whose ridge runs along local Z.
func add_roof(parent: Node3D, size: Vector3, pos: Vector3, m: Material) -> MeshInstance3D:
	var roof := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = size
	roof.mesh = pm
	roof.material_override = m
	roof.position = pos
	parent.add_child(roof)
	return roof


## A parked car; its nose points along +X before `yaw`.
func add_car(holder: Node3D, rng: RandomNumberGenerator, pos: Vector3, yaw: float) -> void:
	var paints := [Color(0.93, 0.93, 0.93), Color(0.08, 0.08, 0.09), Color(0.62, 0.64, 0.66),
			Color(0.1, 0.15, 0.32), Color(0.62, 0.08, 0.08), Color(0.3, 0.31, 0.33)]
	var model = SceneryModels.pick_car(rng)
	if model:
		_place_car_model(holder, model, pos, yaw + rng.randf_range(-0.05, 0.05), paints[rng.randi() % paints.size()])
		return
	var idx := rng.randi() % paints.size()
	var paint := mat("paint%d" % idx, paints[idx], 0.35)
	var car := Node3D.new()
	car.position = pos
	car.rotation.y = yaw + rng.randf_range(-0.05, 0.05)
	holder.add_child(car)
	var length := rng.randf_range(4.0, 4.6)
	add_box(car, Vector3(length, 0.72, 1.8), Vector3(0, 0.66, 0), paint)
	add_box(car, Vector3(length * 0.52, 0.56, 1.62), Vector3(-length * 0.06, 1.3, 0), mat("car_glass", Color(0.1, 0.12, 0.15), 0.15))
	add_box(car, Vector3(length * 0.48, 0.07, 1.58), Vector3(-length * 0.06, 1.6, 0), paint)
	var tyre := mat("tyre", Color(0.06, 0.06, 0.06), 0.9)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var w := add_cyl(car, Vector3(sx * length * 0.32, 0.33, sz * 0.82), 0.33, 0.24, tyre)
			w.rotation.x = PI * 0.5


func add_van(holder: Node3D, pos: Vector3, yaw: float) -> void:
	var model = SceneryModels.pick(SceneryModels.CAR_DIR, ["van", "minibus"], RandomNumberGenerator.new())
	if model:
		_place_car_model(holder, model, pos, yaw, Color(0.93, 0.93, 0.93))
		return
	var van := Node3D.new()
	van.position = pos
	van.rotation.y = yaw
	holder.add_child(van)
	var white := mat("paint0", Color(0.93, 0.93, 0.93), 0.35)
	add_box(van, Vector3(5.3, 1.95, 2.0), Vector3(-0.3, 1.35, 0), white)
	add_box(van, Vector3(0.9, 0.8, 1.9), Vector3(2.55, 1.9, 0), mat("car_glass", Color(0.1, 0.12, 0.15), 0.15))
	add_box(van, Vector3(1.2, 0.9, 2.0), Vector3(2.4, 0.8, 0), white)
	var tyre := mat("tyre", Color(0.06, 0.06, 0.06), 0.9)
	for sx in [-1.9, 2.1]:
		for sz in [-1.0, 1.0]:
			var w := add_cyl(van, Vector3(sx, 0.36, sz * 0.9), 0.36, 0.26, tyre)
			w.rotation.x = PI * 0.5


## Cars from models are gathered here and drawn by _emit_car_models, one
## MultiMesh per model, with `paint` on the materials named as paint.
func _place_car_model(holder: Node3D, model, pos: Vector3, yaw: float, paint: Color) -> void:
	var k: float = SceneryModels.car_length(model) / maxf(model.size.x, 0.01)
	if not _cars.has(model):
		_cars[model] = []
	_cars[model].append([holder, Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * k), pos), paint])


func _emit_car_models(root: Node3D) -> void:
	var n := 0
	for m in _cars:
		var list: Array = _cars[m]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = m.mesh
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, _relative_xform(root, list[i][0]) * list[i][1])
			mm.set_instance_color(i, list[i][2])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "CarModel%d" % n
		mmi.multimesh = mm
		if m.far:
			mmi.set_meta("far_parts", [[m.far, null, Transform3D.IDENTITY]])
		root.add_child(mmi)
		n += 1


## Cars parked side by side along a line from `a` to `b`, noses pointing `yaw`.
func park_row(holder: Node3D, rng: RandomNumberGenerator, a: Vector3, b: Vector3, yaw: float, fill := 0.7, gap := 2.9) -> void:
	var n := int(a.distance_to(b) / gap)
	for i in n + 1:
		if rng.randf() < fill:
			add_car(holder, rng, a.lerp(b, float(i) / max(n, 1)), yaw)


## Posts every `spacing` metres from `a` to `b` following the ground, plus a
## see-through mesh panel (a chain-link or ball-stop fence) if `panel` is set.
func add_fence(root: Node3D, a: Vector2, b: Vector2, height: float, spacing: float, color: Color, panel := true, panel_alpha := 0.3) -> void:
	var len := a.distance_to(b)
	var n := int(len / spacing) + 1
	var posts := MultiMesh.new()
	posts.transform_format = MultiMesh.TRANSFORM_3D
	var box := BoxMesh.new()
	box.size = Vector3(0.08, height, 0.08)
	posts.mesh = box
	posts.instance_count = n
	for i in n:
		var p := a.lerp(b, float(i) / max(n - 1, 1))
		posts.set_instance_transform(i, Transform3D(Basis(), Vector3(p.x, height_m(p.x, p.y) + height * 0.5, p.y)))
	var pmi := MultiMeshInstance3D.new()
	pmi.multimesh = posts
	pmi.material_override = mat("fence%s" % color.to_html(), color, 0.6)
	root.add_child(pmi)
	if not panel:
		return
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color.r, color.g, color.b, panel_alpha)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mid := (a + b) * 0.5
	var mesh := add_box(root, Vector3(len, height * 0.95, 0.02), Vector3(mid.x, height_m(mid.x, mid.y) + height * 0.5, mid.y), m)
	mesh.rotation.y = -atan2(b.y - a.y, b.x - a.x)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Distance from p to the polyline pts (all in the XZ plane).
static func dist_to_path(p: Vector2, pts: PackedVector2Array) -> float:
	var best := INF
	for i in pts.size() - 1:
		var a := pts[i]
		var ab := pts[i + 1] - a
		var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		best = min(best, p.distance_to(a + ab * t))
	return best


func mat(key: String, color: Color, roughness: float) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	_mats[key] = m
	return m


func add_box(parent: Node3D, size: Vector3, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


func add_cyl(parent: Node3D, pos: Vector3, radius: float, height: float, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 10
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


# --- Draw-call batching -------------------------------------------------------

## Scenery is laid out in cells this size (metres) once it is built, so the
## camera and each shadow cascade only draw the cells they can see.
const BATCH_CELL := 60.0
## How far from the pitch (metres) scenery still casts shadows, by quality.
## Beyond it the shadow would be a few blurry pixels in the last cascade.
const SHADOW_REACH := [15.0, 70.0, INF]
## Metres from the camera within which trees keep their full canopy, by quality.
const TREE_NEAR := [45.0, 85.0, 170.0]


## Cuts the scenery's draw calls without changing what it looks like: each big
## MultiMesh (trees) is split into cells, and plain-material meshes (houses,
## cars, walls, fences) are merged per cell and material. Far cells stop
## casting shadows below HIGH quality.
func _batch_scenery(root: Node3D) -> void:
	var reach: float = SHADOW_REACH[graphics_quality]
	for mmi in root.find_children("*", "MultiMeshInstance3D", true, false):
		_split_multimesh(root, mmi, reach)
	var groups := {}
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		if not _batchable(mi):
			continue
		var xf := _relative_xform(root, mi)
		var cell := _cell_of(xf * mi.mesh.get_aabb().get_center())
		for surf in mi.mesh.get_surface_count():
			var key := [cell, mi.material_override, mi.cast_shadow, _surface_layout(mi.mesh, surf)]
			if not groups.has(key):
				groups[key] = []
			groups[key].append([mi.mesh, surf, xf])
		mi.get_parent().remove_child(mi)
		mi.queue_free()
	for key in groups:
		var st := SurfaceTool.new()
		for item in groups[key]:
			st.append_from(item[0], item[1], item[2])
		var merged := MeshInstance3D.new()
		merged.name = "Batch"
		merged.mesh = st.commit()
		merged.material_override = key[1]
		merged.cast_shadow = key[2]
		if _cell_distance(key[0]) > reach:
			merged.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(merged)


## Which vertex attributes a surface has; only like surfaces merge together.
func _surface_layout(mesh: Mesh, surf: int) -> int:
	var arrays := mesh.surface_get_arrays(surf)
	var bits := 0
	for i in arrays.size():
		if arrays[i] != null and not (arrays[i] is Array and arrays[i].is_empty()):
			bits |= 1 << i
	return bits


func _batchable(mi: MeshInstance3D) -> bool:
	var m := mi.material_override as StandardMaterial3D
	return mi.mesh != null and m != null and mi.is_visible_in_tree() and mi.get_child_count() == 0 \
		and mi.visibility_range_end == 0.0 and m.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED \
		and m.billboard_mode == BaseMaterial3D.BILLBOARD_DISABLED and mi.get_script() == null


func _relative_xform(root: Node3D, n: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	while n != root:
		xf = n.transform * xf
		n = n.get_parent()
	return xf


func _cell_of(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / BATCH_CELL), floori(p.z / BATCH_CELL))


## Metres from the pitch's edge to the nearest point of a cell.
func _cell_distance(cell: Vector2i) -> float:
	var lo := Vector2(cell) * BATCH_CELL
	var hi := lo + Vector2.ONE * BATCH_CELL
	var dx := maxf(0.0, maxf(lo.x - hl, -hl - hi.x))
	var dz := maxf(0.0, maxf(lo.y - hw, -hw - hi.y))
	return Vector2(dx, dz).length()


func _split_multimesh(root: Node3D, mmi: MultiMeshInstance3D, reach: float) -> void:
	var mm := mmi.multimesh
	var lod := mmi.has_meta("far_mesh") or mmi.has_meta("far_parts")
	if mm == null or mm.transform_format != MultiMesh.TRANSFORM_3D or (mm.instance_count < 64 and not lod):
		return
	var cells := {}
	var base := _relative_xform(root, mmi)
	for i in mm.instance_count:
		var cell := _cell_of(base * mm.get_instance_transform(i).origin)
		if not cells.has(cell):
			cells[cell] = []
		cells[cell].append(i)
	if cells.size() < 2 and not lod:
		return
	for cell in cells:
		var list: Array = cells[cell]
		var part := MultiMesh.new()
		part.transform_format = MultiMesh.TRANSFORM_3D
		part.use_colors = mm.use_colors
		part.use_custom_data = mm.use_custom_data
		part.mesh = mm.mesh
		part.instance_count = list.size()
		for j in list.size():
			var i: int = list[j]
			part.set_instance_transform(j, mm.get_instance_transform(i))
			if mm.use_colors:
				part.set_instance_color(j, mm.get_instance_color(i))
			if mm.use_custom_data:
				part.set_instance_custom_data(j, mm.get_instance_custom_data(i))
		var chunk := mmi.duplicate(0) as MultiMeshInstance3D
		chunk.name = "%s_%d_%d" % [mmi.name, cell.x, cell.y]
		chunk.multimesh = part
		var shadows := chunk.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and _cell_distance(cell) <= reach
		if not shadows:
			chunk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.get_parent().add_child(chunk)
		if lod:
			_add_far_trees(root, mmi, chunk, shadows)
	mmi.get_parent().remove_child(mmi)
	mmi.queue_free()


## Canopy LOD for one cell of trees. Close up the camera sees the full canopy
## with its leaf cards; past TREE_NEAR it sees a plain opaque blob, which is a
## fraction of the triangles and needs no cut-out. Below HIGH the shadow also
## comes from the plain blob (cut-out shadows are costly), so trees still
## shade the ground under them but without the dappling.
func _add_far_trees(root: Node3D, mmi: MultiMeshInstance3D, chunk: MultiMeshInstance3D, shadows: bool) -> void:
	var near: float = TREE_NEAR[graphics_quality] * root.scale.x
	# No margins: with fading off they act as hysteresis, and a cell starting
	# inside the margin could show neither version.
	chunk.visibility_range_end = near
	var parts: Array = mmi.get_meta("far_parts") if mmi.has_meta("far_parts") \
		else [[mmi.get_meta("far_mesh"), mmi.get_meta("far_material"), Transform3D.IDENTITY]]
	var high := graphics_quality == Detail.HIGH
	if shadows and not high:
		chunk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var k := 0
	for part in parts:
		# Each part (a model's far version, or a fitted blob crown and trunk)
		# sits at `offset` within every tree.
		var copies := chunk.multimesh.duplicate() as MultiMesh
		copies.mesh = part[0]
		var offset: Transform3D = part[2]
		if offset != Transform3D.IDENTITY:
			for i in copies.instance_count:
				copies.set_instance_transform(i, copies.get_instance_transform(i) * offset)
		var far := MultiMeshInstance3D.new()
		far.name = "%sFar%d" % [chunk.name, k]
		far.multimesh = copies
		far.transform = chunk.transform
		far.material_override = part[1]
		far.visibility_range_begin = near
		far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows and high \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		chunk.get_parent().add_child(far)
		if shadows and not high:
			var caster := far.duplicate(0) as MultiMeshInstance3D
			caster.name = "%sShadow%d" % [chunk.name, k]
			caster.visibility_range_begin = 0.0
			caster.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			chunk.get_parent().add_child(caster)
		k += 1


func _load_local(file: String) -> Resource:
	return load(get_script().resource_path.get_base_dir().path_join(file))
