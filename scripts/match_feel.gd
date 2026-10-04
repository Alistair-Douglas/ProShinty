class_name ShintyMatchFeel
extends Node3D
## How a hit feels: the picture holds for a moment on a firm strike
## (hit-stop), the camera jolts on the big ones, the pad rumbles with the
## power of your hits and the knocks you take, a puff of grass and mud flies
## up where the caman meets a ball on the ground, and a hard-hit ball leaves a
## short streak behind it. Like the match sound, it is all driven by the
## events in match.events; the match knows nothing about it.
##
## Lives under the match view, which calls step() each drawn frame and
## kick_camera() once it has placed the camera.

const FIRM_HIT := 22.0      ## yd/s: your strike this hard holds the picture for a moment
const BIG_HIT := 32.0       ## yd/s: anyone's strike this hard holds it, and jolts the camera
const HARD_HIT := 42.0      ## yd/s: about the hardest strike there is
const STOP_SHORT := 0.04    ## s of hit-stop on a firm hit ...
const STOP_LONG := 0.07     ## ... up to this on the hardest
const STOP_SPEED := 0.05    ## the game runs this fast while the picture holds
const KICK_DEG := 0.7       ## the biggest camera jolt, in degrees
const KICK_FOV := 1.4       ## and how much it punches in
const TRAIL_FROM := 26.0    ## yd/s: a ball hit this hard leaves a streak
const TRAIL_TIME := 0.5     ## s the streak lasts
const TRAIL_POINTS := 12
const TRAIL_WIDTH := 0.13   ## yd
const PUFFS := 4            ## grass puffs that can be in the air at once

var view: Node3D            ## the match view (its parent)
var m: Node                 ## the match
var rumble := true          ## off if the settings say so (Game.rumble, when there is one)
var stops := 0              ## counts, for the tests
var kicks := 0
var puffs_made := 0
var trails := 0
var rumbles := 0

var _next_event := 0
var _stop_until := 0        # clock time (usec) the hit-stop ends; 0 = none
var _kick := 0.0            # size of the camera jolt now, 0 to 1
var _kick_dir := Vector2.ZERO
var _puffs: Array[CPUParticles3D] = []
var _next_puff := 0
var _trail: MeshInstance3D
var _trail_mesh := ImmediateMesh.new()
var _trail_points: Array[Vector3] = []
var _trail_left := 0.0
var _last_kind := ""


func setup(p_view: Node3D) -> void:
	view = p_view
	m = view.get_parent()
	process_physics_priority = 100   # after the match has stepped, so a strike's speed is known
	var game := get_node_or_null("/root/Game")
	if game != null and game.get("rumble") != null:
		rumble = bool(game.get("rumble"))
	var low: bool = game != null and int(game.get("graphics_quality")) == 0
	for i in PUFFS:
		_puffs.append(_build_puff(8 if low else 16))
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_trail = MeshInstance3D.new()
	_trail.name = "BallTrail"
	_trail.mesh = _trail_mesh
	_trail.material_override = mat
	_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_trail)
	_next_event = m.events.size()


func _exit_tree() -> void:
	if _stop_until > 0:
		Engine.time_scale = 1.0   # never leave the game slowed


func _physics_process(_delta: float) -> void:
	while _next_event < m.events.size():
		var e: Dictionary = m.events[_next_event]
		_next_event += 1
		_on_event(e)


## Each drawn frame: end the hit-stop when its real time is up, settle the
## camera jolt and draw the streak.
func step(delta: float) -> void:
	var real: float = delta / Engine.time_scale if Engine.time_scale > 0.0 else delta
	if _stop_until > 0 and Time.get_ticks_usec() >= _stop_until:
		_stop_until = 0
		Engine.time_scale = 1.0
	_kick *= exp(-real * 12.0)
	_draw_trail(real)


## Called by the view once the camera is placed for this frame.
func kick_camera(cam: Camera3D) -> void:
	if _kick < 0.01:
		return
	cam.rotate_object_local(Vector3.RIGHT, deg_to_rad(KICK_DEG) * _kick * _kick_dir.y)
	cam.rotate_object_local(Vector3.UP, deg_to_rad(KICK_DEG) * _kick * _kick_dir.x)
	cam.fov -= KICK_FOV * _kick


func _on_event(e: Dictionary) -> void:
	var human = m.human
	match e["type"]:
		"hit":
			_last_kind = e.get("kind", "")
		"strike":
			var sp: float = Vector3(m.ball_vel.x, m.ball_vel.y, m.ball_vz).length()
			var k: float = clampf((sp - 8.0) / (HARD_HIT - 8.0), 0.0, 1.0)
			var mine: bool = human != null and e.get("by") == human
			if _last_kind != "fresh_air":
				if sp >= BIG_HIT or (mine and sp >= FIRM_HIT):
					hit_stop(lerpf(STOP_SHORT, STOP_LONG, clampf((sp - FIRM_HIT) / (HARD_HIT - FIRM_HIT), 0.0, 1.0)))
				if sp >= BIG_HIT:
					kick(0.5 + 0.5 * clampf((sp - BIG_HIT) / (HARD_HIT - BIG_HIT), 0.0, 1.0))
				if m.ball_z < 0.4:
					puff(e.get("at", m.ball_pos), k)
				if sp >= TRAIL_FROM:
					start_trail()
			if mine:
				_rumble(0.25 + 0.5 * k, 0.15 + 0.85 * k * k, 0.07 + 0.13 * k)
			_last_kind = ""
		"touch":
			if e.get("by") == human and human != null:
				_rumble(0.15, 0.0, 0.05)
		"tackle":
			if human != null and (e.get("on") == human or e.get("by") == human):
				_rumble(0.35, 0.45, 0.15)
		"swing_contact":
			if human != null and e.get("on") == human:
				_rumble(0.4, 0.9, 0.25)
		"knockdown":
			if human != null and e.get("on") == human:
				_rumble(0.5, 1.0, 0.3)
			if e.get("floored", false):
				kick(0.4)
		"foul":
			if human != null and e.get("on") == human:
				_rumble(0.3, 0.6, 0.2)
		"clash", "battle", "stick_block", "cleek", "block", "late_block", "body_stop", "air_kill", "stick_rebound":
			# Your man in the thick of it: whoever is nearest the ball on your side.
			if human != null and e.get("team", -1) == human.team and human.pos.distance_to(m.ball_pos) < 2.5:
				_rumble(0.3, 0.35, 0.1)
		"save":
			if human != null and e.get("team", -1) == human.team:
				_rumble(0.2, 0.4, 0.12)
		"goal":
			if human != null and e.get("team", -1) == human.team:
				_rumble(0.6, 0.6, 0.45)


## Holds the picture for a moment: the game crawls, then carries on.
func hit_stop(seconds: float) -> void:
	if m.paused or view.director.playing:
		return
	_stop_until = maxi(_stop_until, Time.get_ticks_usec() + int(seconds * 1e6))
	Engine.time_scale = STOP_SPEED
	stops += 1


func kick(size: float) -> void:
	_kick = maxf(_kick, size)
	_kick_dir = Vector2(randf_range(-0.6, 0.6), randf_range(0.6, 1.0) * (1.0 if randf() < 0.5 else -1.0))
	kicks += 1


## A puff of grass and mud off the turf where the caman met the ball.
func puff(at: Vector2, size: float) -> void:
	var p := _puffs[_next_puff]
	_next_puff = (_next_puff + 1) % _puffs.size()
	p.position = view.w(at, 0.05)
	p.initial_velocity_min = lerpf(1.2, 2.5, size)
	p.initial_velocity_max = lerpf(2.5, 5.0, size)
	p.restart()
	p.emitting = true
	puffs_made += 1


func start_trail() -> void:
	_trail_left = TRAIL_TIME
	_trail_points.clear()
	trails += 1


func _rumble(weak: float, strong: float, seconds: float) -> void:
	if not rumble:
		return
	rumbles += 1
	for pad in Input.get_connected_joypads():
		Input.start_joy_vibration(pad, clampf(weak, 0.0, 1.0), clampf(strong, 0.0, 1.0), seconds)


func _build_puff(amount: int) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "GrassPuff"
	p.one_shot = true
	p.emitting = false
	p.amount = amount
	p.lifetime = 0.7
	p.explosiveness = 0.95
	p.direction = Vector3.UP
	p.spread = 55.0
	p.gravity = Vector3(0, -9.0, 0)
	p.damping_min = 1.0
	p.damping_max = 3.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	var fade := Curve.new()
	fade.add_point(Vector2(0, 1))
	fade.add_point(Vector2(1, 0.3))
	p.scale_amount_curve = fade
	# Torn grass and a few clods of earth.
	var colours := Gradient.new()
	colours.set_color(0, Color(0.30, 0.48, 0.16))
	colours.set_color(1, Color(0.33, 0.24, 0.14))
	colours.add_point(0.6, Color(0.36, 0.52, 0.2))
	p.color_initial_ramp = colours
	var quad := QuadMesh.new()
	quad.size = Vector2(0.07, 0.07)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	quad.material = mat
	p.mesh = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	return p


## The streak: the ball's last few drawn spots, as a ribbon turned to the
## camera that thins and fades towards the tail.
func _draw_trail(real: float) -> void:
	_trail_mesh.clear_surfaces()
	if _trail_left <= 0.0:
		return
	_trail_left -= real
	var speed: float = m.ball_vel.length()
	if m.carrier != null or speed < 12.0:
		_trail_left = minf(_trail_left, 0.12)   # stopped or caught: let it fade quickly
	var head: Vector3 = view.ball.position
	if _trail_points.is_empty() or _trail_points[0].distance_to(head) > 0.05:
		_trail_points.push_front(head)
		if _trail_points.size() > TRAIL_POINTS:
			_trail_points.pop_back()
	if _trail_points.size() < 2:
		return
	var cam: Camera3D = view.camera
	var fade: float = clampf(_trail_left / 0.2, 0.0, 1.0)
	_trail_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var n := _trail_points.size()
	for i in n:
		var pt: Vector3 = _trail_points[i]
		var along: Vector3 = (_trail_points[maxi(i - 1, 0)] - _trail_points[mini(i + 1, n - 1)]).normalized()
		var side: Vector3 = along.cross(cam.global_position - pt).normalized()
		var k := 1.0 - float(i) / float(n - 1)
		var half := TRAIL_WIDTH * 0.5 * (0.3 + 0.7 * k)
		var c := Color(1.0, 1.0, 0.95, 0.55 * k * fade)
		_trail_mesh.surface_set_color(c)
		_trail_mesh.surface_add_vertex(pt + side * half)
		_trail_mesh.surface_set_color(c)
		_trail_mesh.surface_add_vertex(pt - side * half)
	_trail_mesh.surface_end()
