extends "res://scripts/match_view.gd"
## The match view for the training ground, plus a close camera that orbits
## your player, for watching moves and animations up close.

const Body := preload("res://scripts/player_physics.gd")

var cam_yaw := 0.0        # round the player, world-fixed so a run can be watched go by
var cam_dist := 6.0
var _was_close := false


func _process(delta: float) -> void:
	super._process(delta)
	# The keeper and defender come and go: show whoever is out there.
	for p in figures:
		if p in m.players:
			figures[p]["root"].visible = true
		if m.close_cam:
			figures[p]["tag"].visible = false   # the number and marker would fill the screen
			figures[p]["arrow"].visible = false
	# Showing a carry or the throw-up stance in the training ground.
	var you = m.human
	if you != null and figures.has(you) and not director.playing:
		var model: ShintyPlayerModel = figures[you]["model"]
		if not figures[you].has("own_shoulder"):
			figures[you]["own_shoulder"] = model.shoulder_carry
		model.shoulder_carry = figures[you]["own_shoulder"] if m.force_shoulder == null else m.force_shoulder
		if m.hold_pose == "throw_up":
			# Caman raised high, crossed over the spot in front, as at a throw-up.
			model.held_pose = &"throw_up"
			model.set_reach(w(you.pos + you.facing * 0.5, Body.OVERHEAD), 1.0)


func _update_camera(delta: float) -> void:
	var p = m.human
	if not m.close_cam or p == null:
		_was_close = false
		super._update_camera(delta)
		return
	# Camera moves at real speed, even with the play in slow motion.
	var real: float = delta / maxf(Engine.time_scale, 0.01)
	var at := w(p.pos)
	if not _was_close:
		_was_close = true
		var f := w(p.pos + p.facing) - at
		# Start three-quarters on, from the front and to the side: the
		# swing and the stick are clearest from there.
		cam_yaw = atan2(f.x, f.z) + deg_to_rad(60.0)
	var rx := Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
	var ry := Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	rx = 0.0 if absf(rx) < 0.2 else rx
	ry = 0.0 if absf(ry) < 0.2 else ry
	rx += Input.get_axis("practice_orbit_left", "practice_orbit_right")
	cam_yaw -= rx * 2.2 * real
	cam_dist = clampf(cam_dist + ry * 6.0 * real, 2.5, 16.0)
	var back := Vector3(sin(cam_yaw), 0.0, cos(cam_yaw))
	var eye := at + back * cam_dist + Vector3(0, 1.0 + cam_dist * 0.22, 0)
	var k := 1.0 - exp(-real * 8.0)
	camera.position = camera.position.lerp(eye, k)
	camera.look_at(at + Vector3(0, 0.9, 0), Vector3.UP)
	camera.fov = 50.0
