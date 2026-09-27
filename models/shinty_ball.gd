@tool
class_name ShintyBallModel
extends Node3D
## A shinty ball: white leather with a stitched seam, a ground shadow that
## shrinks as the ball rises, and an optional landing marker for high balls.
##
## By default it simulates itself with ShintyBallPhysics (metres). Set
## `simulate` to false to drive `position` from your own match logic; the ball
## still spins to match its movement and the shadow still follows.

signal bounced(position: Vector3, speed: float)
signal landed(position: Vector3)
signal stopped(position: Vector3)
signal hit_post(position: Vector3, speed: float)
signal hit_net(position: Vector3)
signal goal(hail: Node3D)

## Run the built-in physics. Off = you move the ball yourself.
@export var simulate := true
## Enlarge the visible ball (not its physics). Broadcast cameras need 2-4x.
@export_range(0.5, 8.0, 0.1) var display_scale := 1.0:
	set(v): display_scale = v; _apply_scale()
@export var show_shadow := true
## Show where a lofted ball will come down.
@export var show_landing_marker := false
## Collide with every ShintyHailModel in the "shinty_hail" group.
@export var auto_find_hails := true

var physics := ShintyBallPhysics.new()

var _ball: Node3D
var _shadow: MeshInstance3D
var _marker: MeshInstance3D
var _last_pos := Vector3.ZERO
var _shadow_mat: StandardMaterial3D


func _ready() -> void:
	_build()
	physics.position = global_position if is_inside_tree() else position
	if physics.position.y < ShintyBallPhysics.RADIUS:
		physics.position.y = ShintyBallPhysics.RADIUS
	_last_pos = physics.position
	if auto_find_hails and not Engine.is_editor_hint():
		_find_hails.call_deferred()


## Hit the ball with a velocity (m/s) and optional spin (rad/s).
func strike(velocity: Vector3, spin: Vector3 = Vector3.ZERO) -> void:
	physics.strike(velocity, spin)


## Put the ball somewhere, at rest.
func place(at: Vector3) -> void:
	physics.place(at)
	global_position = physics.position
	_last_pos = physics.position


func get_velocity() -> Vector3:
	return physics.velocity


func is_airborne() -> bool:
	return physics.is_airborne()


## Height of the bottom of the ball above the pitch.
func get_height() -> float:
	return physics.height()


func predict_landing(max_time: float = 8.0) -> Vector3:
	return physics.predict_landing(max_time)


func _find_hails() -> void:
	if physics.hails.is_empty():
		physics.hails = get_tree().get_nodes_in_group("shinty_hail")


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if simulate:
		var events := physics.step(delta)
		global_position = physics.position
		for e in events:
			match e["type"]:
				"bounce": bounced.emit(e["position"], e["speed"])
				"landed": landed.emit(e["position"])
				"stopped": stopped.emit(e["position"])
				"post": hit_post.emit(e["position"], e["speed"])
				"net": hit_net.emit(e["position"])
				"goal": goal.emit(e["hail"])
	else:
		physics.position = global_position


func _process(_delta: float) -> void:
	if _ball == null:
		return
	# Roll/spin the visible ball to match how far it moved.
	var pos := global_position
	var moved := pos - _last_pos
	_last_pos = pos
	var r := ShintyBallPhysics.RADIUS * display_scale
	if simulate and physics.is_airborne() and physics.spin.length() > 0.1:
		var w := physics.spin
		_ball.basis = Basis(w.normalized(), w.length() * _delta) * _ball.basis
	elif moved.length() > 0.0005:
		var axis := Vector3.UP.cross(Vector3(moved.x, 0, moved.z))
		if axis.length() > 0.0001:
			_ball.basis = Basis(axis.normalized(), Vector3(moved.x, 0, moved.z).length() / r) * _ball.basis
	_ball.basis = _ball.basis.orthonormalized().scaled(Vector3.ONE * display_scale)
	# Shadow on the ground under the ball
	if _shadow:
		var ground := physics.ground_y if simulate else 0.0
		var h := maxf(0.0, pos.y - ground)
		_shadow.visible = show_shadow
		_shadow.global_position = Vector3(pos.x, ground + 0.004, pos.z)
		var k := clampf(1.0 - h / 12.0, 0.25, 1.0)
		_shadow.scale = Vector3.ONE * display_scale * lerpf(1.6, 1.0, k)
		_shadow_mat.albedo_color = Color(0, 0, 0, 0.45 * k)
	if _marker:
		var show := show_landing_marker and simulate and physics.height() > 1.0 and physics.velocity.y < 6.0
		_marker.visible = show
		if show:
			var land := physics.predict_landing()
			_marker.global_position = Vector3(land.x, physics.ground_y + 0.01, land.z)


func _apply_scale() -> void:
	if _ball:
		_ball.basis = _ball.basis.orthonormalized().scaled(Vector3.ONE * display_scale)


func _build() -> void:
	for c in get_children():
		if c.has_meta("shinty_generated"):
			remove_child(c)
			c.queue_free()
	var r := ShintyBallPhysics.RADIUS
	_ball = Node3D.new()
	_ball.set_meta("shinty_generated", true)
	add_child(_ball)
	var leather := StandardMaterial3D.new()
	leather.albedo_color = Color("f4f1e6")
	leather.roughness = 0.55
	var sphere := SphereMesh.new()
	sphere.radius = r
	sphere.height = r * 2.0
	sphere.radial_segments = 20
	sphere.rings = 12
	var body := MeshInstance3D.new()
	body.mesh = sphere
	body.material_override = leather
	_ball.add_child(body)
	# The seam: a raised stitched band round the ball, so spin is visible.
	var seam := TorusMesh.new()
	seam.inner_radius = r * 0.97
	seam.outer_radius = r * 1.06
	seam.rings = 24
	seam.ring_segments = 6
	var seam_mat := StandardMaterial3D.new()
	seam_mat.albedo_color = Color("b0302a")
	seam_mat.roughness = 0.7
	var s1 := MeshInstance3D.new()
	s1.mesh = seam
	s1.material_override = seam_mat
	s1.rotation = Vector3(0.0, 0.0, 0.35)
	_ball.add_child(s1)
	_apply_scale()

	_shadow = MeshInstance3D.new()
	_shadow.set_meta("shinty_generated", true)
	var disc := CylinderMesh.new()
	disc.top_radius = r * 1.1
	disc.bottom_radius = r * 1.1
	disc.height = 0.001
	disc.radial_segments = 16
	_shadow.mesh = disc
	_shadow_mat = StandardMaterial3D.new()
	_shadow_mat.albedo_color = Color(0, 0, 0, 0.45)
	_shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shadow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shadow.material_override = _shadow_mat
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shadow.top_level = true
	add_child(_shadow)

	_marker = MeshInstance3D.new()
	_marker.set_meta("shinty_generated", true)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.35
	ring.outer_radius = 0.45
	_marker.mesh = ring
	var mm := StandardMaterial3D.new()
	mm.albedo_color = Color(1, 0.92, 0.25, 0.7)
	mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_marker.material_override = mm
	_marker.scale = Vector3(1, 0.05, 1)
	_marker.top_level = true
	_marker.visible = false
	add_child(_marker)
