extends Node3D
## Draws the match in 3D: the Aberdour pitch and scenery (pitch/shinty_pitch.tscn),
## hails, players with camans, the ball and a broadcast-style camera. It only
## reads the match state, never changes it. One world unit is one yard; the
## centre spot is the origin.

const PitchScene := preload("res://pitch/shinty_pitch.tscn")

var m: Node  # the match (parent)
var pitch: Node3D
var camera: Camera3D
var ball: Node3D
var ball_shadow: MeshInstance3D
var figures := {}  # Player -> Dictionary of nodes
var cam_x := 0.0
var cam_zoom := 1.0

const SKIN := Color(0.93, 0.76, 0.62)
const WOOD := Color(0.55, 0.36, 0.18)


func _ready() -> void:
	m = get_parent()
	pitch = PitchScene.instantiate()
	pitch.units_per_yard = 1.0
	pitch.length_yd = m.PITCH.x
	pitch.width_yd = m.PITCH.y
	pitch.show_placeholder_goals = false  # our own hails below
	add_child(pitch)
	_build_hails()
	for p in m.players:
		figures[p] = _build_player(p)
	var bm := ShintyBallModel.new()
	bm.simulate = false
	bm.auto_find_hails = false
	bm.scale = Vector3.ONE * ShintyMatchAdapter.TO_YARDS
	bm.display_scale = 4.0
	ball = bm
	add_child(ball)
	camera = Camera3D.new()
	camera.fov = 45.0
	camera.far = 6000.0  # the far shore of the Forth
	camera.current = true
	add_child(camera)
	cam_x = m.ball_pos.x - m.PITCH.x / 2.0
	_update_camera(1.0)


func w(v: Vector2, height: float = 0.0) -> Vector3:
	return pitch.sim_to_world(v, height)


# ---------------------------------------------------------------- per frame

func _process(delta: float) -> void:
	for p in m.players:
		_update_player(p, figures[p], delta)
	ball.position = w(m.ball_pos, m.ball_z + ShintyBallPhysics.RADIUS * ShintyMatchAdapter.TO_YARDS)
	_update_camera(delta)


func _update_player(p, f: Dictionary, delta: float) -> void:
	var root: Node3D = f["root"]
	var speed: float = p.vel.length()
	f["phase"] += delta * speed * 1.6
	root.position = w(p.pos)
	var dir := Vector3(p.facing.x, 0, p.facing.y)
	if dir.length() > 0.01:
		var target := atan2(-dir.x, -dir.z)
		root.rotation.y = lerp_angle(root.rotation.y, target, min(1.0, delta * 14.0))
	ShintyMatchAdapter.update_player(f, p.vel, p.swing, false, w(m.ball_pos, m.ball_z))
	f["ring"].visible = p == m.human
	f["arrow"].visible = p == m.human
	f["tag"].visible = p == m.human or p.is_keeper()


func _update_camera(delta: float) -> void:
	var target_x: float = clamp(m.ball_pos.x - m.PITCH.x / 2.0, -58.0, 58.0)
	cam_x = lerp(cam_x, target_x, min(1.0, delta * 2.5))
	var depth: float = m.ball_pos.y - m.PITCH.y / 2.0
	var look := Vector3(cam_x, 0.0, clamp(depth * 0.55, -14.0, 14.0))
	camera.position = look + Vector3(0, 21.0 * cam_zoom, 30.0 * cam_zoom)
	camera.look_at(look, Vector3.UP)


## Screen position of a pitch point, for the HUD.
func screen_pos(v: Vector2, height: float = 0.0) -> Vector2:
	return camera.unproject_position(w(v, height))


# ---------------------------------------------------------------- building

## Hail models: swap point for proper goal models. Each hail is built in the
## pitch's goal frame (origin on the goal line, +X across, -Z out of the pitch).
func _build_hails() -> void:
	for end in 2:
		var hail := ShintyHailModel.new()
		hail.name = "Hail%d" % end
		hail.width = m.GOAL_W * ShintyMatchAdapter.YARD
		hail.height = m.CROSSBAR * ShintyMatchAdapter.YARD
		# The pitch's goal frame has the net towards -Z; the model's is +Z.
		hail.transform = pitch.goal_transform(end) * Transform3D(
			Basis(Vector3.UP, PI).scaled(Vector3.ONE * ShintyMatchAdapter.TO_YARDS), Vector3.ZERO)
		add_child(hail)


func _build_player(p) -> Dictionary:
	var f := ShintyMatchAdapter.build_player(self, p.data, ShintyMatchAdapter.team_from_colors(m.colors[p.team][0], m.colors[p.team][1]))
	var root: Node3D = f["root"]
	var ring := _mesh(_torus(0.75, 0.95), _mat(Color(1, 0.92, 0.2), true))
	ring.position = Vector3(0, 0.04, 0)
	root.add_child(ring)
	var arrow := _mesh(_cone(0.25, 0.4), _mat(Color(1, 0.92, 0.2), true))
	arrow.rotation_degrees = Vector3(180, 0, 0)
	arrow.position = Vector3(0, 2.6, 0)
	root.add_child(arrow)
	var tag := Label3D.new()
	tag.text = str(p.number)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.font_size = 48
	tag.outline_size = 12
	tag.pixel_size = 0.01
	tag.position = Vector3(0, 2.25, 0)
	root.add_child(tag)
	root.position = w(p.pos)
	f.merge({"ring": ring, "arrow": arrow, "tag": tag, "phase": 0.0})
	return f


# ---------------------------------------------------------------- mesh helpers

func _mesh(mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	return mi


func _mat(c: Color, unshaded: bool = false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = c
	mat.roughness = 0.9
	if c.a < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if unshaded:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	return s


func _cylinder(r: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	return c


func _cone(r: float, h: float) -> CylinderMesh:
	var c := _cylinder(r, h)
	c.top_radius = 0.0
	return c


func _capsule(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	return c


func _torus(inner: float, outer: float) -> TorusMesh:
	var t := TorusMesh.new()
	t.inner_radius = inner
	t.outer_radius = outer
	return t
