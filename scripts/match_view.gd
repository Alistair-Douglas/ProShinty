extends Node3D
## Draws the match in 3D: the Aberdour pitch and scenery (pitch/shinty_pitch.tscn),
## hails, players with camans, the ball and a broadcast-style camera. It only
## reads the match state, never changes it. One world unit is one yard; the
## centre spot is the origin.

const PitchScene := preload("res://pitch/shinty_pitch.tscn")

var m: Node  # the match (parent)
var pitch: Node3D
var camera: Camera3D
var ball: MeshInstance3D
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
	ball = _mesh(_sphere(0.22), _mat(Color(0.98, 0.97, 0.9)))
	add_child(ball)
	ball_shadow = _mesh(_cylinder(0.22, 0.01), _mat(Color(0, 0, 0, 0.35)))
	add_child(ball_shadow)
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
	var b := w(m.ball_pos, m.ball_z + 0.22)
	ball.position = b
	ball_shadow.position = Vector3(b.x, 0.03, b.z)
	_update_camera(delta)


func _update_player(p, f: Dictionary, delta: float) -> void:
	var root: Node3D = f["root"]
	var speed: float = p.vel.length()
	f["phase"] += delta * speed * 1.6
	var bob: float = abs(sin(f["phase"])) * 0.12 * min(speed / 5.0, 1.0)
	root.position = w(p.pos, bob)
	var dir := Vector3(p.facing.x, 0, p.facing.y)
	if dir.length() > 0.01:
		var target := atan2(-dir.x, -dir.z)
		root.rotation.y = lerp_angle(root.rotation.y, target, min(1.0, delta * 14.0))
	# Legs swing while running.
	var stride: float = sin(f["phase"]) * 0.6 * min(speed / 4.0, 1.0)
	f["leg_l"].rotation.x = stride
	f["leg_r"].rotation.x = -stride
	# Caman: carried low in front, swung back and through when hitting.
	var arm: Node3D = f["caman"]
	var t: float = 1.0 - p.swing / 0.3
	if p.swing <= 0.0:
		arm.rotation.x = 0.6
	elif t < 0.4:
		arm.rotation.x = lerp(0.6, -1.6, t / 0.4)
	else:
		arm.rotation.x = lerp(-1.6, 1.8, (t - 0.4) / 0.6)
	arm.rotation.z = -0.25
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
	var post_mat := _mat(Color.WHITE)
	var net_mat := _mat(Color(1, 1, 1, 0.22))
	net_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for end in 2:
		var hail := Node3D.new()
		hail.name = "Hail%d" % end
		hail.transform = pitch.goal_transform(end)
		add_child(hail)
		var half: float = m.GOAL_W / 2.0
		for sx in [-half, half]:
			var post := _mesh(_cylinder(0.08, m.CROSSBAR), post_mat)
			post.position = Vector3(sx, m.CROSSBAR / 2.0, 0)
			hail.add_child(post)
		var bar := _mesh(_box(Vector3(m.GOAL_W, 0.14, 0.14)), post_mat)
		bar.position = Vector3(0, m.CROSSBAR, 0)
		hail.add_child(bar)
		var net := _mesh(_box(Vector3(m.GOAL_W, m.CROSSBAR, 2.0)), net_mat)
		net.position = Vector3(0, m.CROSSBAR / 2.0, -1.0)
		hail.add_child(net)


func _build_player(p) -> Dictionary:
	var prim: Color = m.colors[p.team][0]
	var sec: Color = m.colors[p.team][1]
	if p.is_keeper():
		prim = Color(0.12, 0.12, 0.12) if p.team == 0 else Color(0.3, 0.75, 0.3)
	var root := Node3D.new()
	add_child(root)
	var shirt := _mat(prim)
	var shorts := _mat(sec.darkened(0.2) if sec.get_luminance() > 0.5 else sec)
	var leg_mat := _mat(Color(0.12, 0.12, 0.14))
	var legs := []
	for side in [-1.0, 1.0]:
		var hip := Node3D.new()
		hip.position = Vector3(0.14 * side, 0.85, 0)
		root.add_child(hip)
		var leg := _mesh(_capsule(0.1, 0.85), leg_mat)
		leg.position = Vector3(0, -0.42, 0)
		hip.add_child(leg)
		legs.append(hip)
	var hips := _mesh(_box(Vector3(0.45, 0.25, 0.28)), shorts)
	hips.position = Vector3(0, 0.9, 0)
	root.add_child(hips)
	var body := _mesh(_capsule(0.26, 0.8), shirt)
	body.position = Vector3(0, 1.3, 0)
	root.add_child(body)
	var stripe := _mesh(_box(Vector3(0.5, 0.1, 0.5)), _mat(sec))
	stripe.position = Vector3(0, 1.35, 0)
	root.add_child(stripe)
	var head := _mesh(_sphere(0.16), _mat(SKIN))
	head.position = Vector3(0, 1.85, 0)
	root.add_child(head)
	# Caman pivots at the hands; the stick hangs down and forward.
	var hands := Node3D.new()
	hands.position = Vector3(0.28, 1.15, -0.1)
	root.add_child(hands)
	var stick := _mesh(_cylinder(0.035, 1.1), _mat(WOOD))
	stick.position = Vector3(0, -0.55, 0)
	hands.add_child(stick)
	var bas := _mesh(_box(Vector3(0.1, 0.1, 0.28)), _mat(WOOD.darkened(0.2)))
	bas.position = Vector3(0, -1.1, -0.1)
	hands.add_child(bas)
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
	return {"root": root, "leg_l": legs[0], "leg_r": legs[1], "caman": hands,
		"ring": ring, "arrow": arrow, "tag": tag, "phase": randf() * TAU}


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
