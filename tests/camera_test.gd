extends SceneTree
## The pre-match build-up and the three live cameras: plays the build-up
## through (flight, walk-out, throw-up), checks the match is held and then
## starts with everyone on their throw-up spots, then tries TV, close TV and
## end to end with and without zoom. Saves screenshots when given a folder.
## xvfb-run godot --path . -s tests/camera_test.gd -- <out_dir>
var out := ""
var frame := 0
var m: Node
var view: Node
var ok := true
var spots := {}
var prematch_done_frame := -1
var clock_at_end := 0.0
var cam_phase := 0
var cam_frame := 0
var dist := {}


func _initialize() -> void:
	out = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else ""
	root.get_node("Game").prematch_next = true
	root.get_node("Game").camera_view = 0
	change_scene_to_file("res://scenes/match.tscn")


func _shot(name: String) -> void:
	if out != "":
		root.get_texture().get_image().save_png(out + "/" + name + ".png")
	print("shot ", name)


func _check(cond: bool, what: String) -> void:
	if not cond:
		ok = false
		print("FAIL: ", what)


func _process(_d: float) -> bool:
	frame += 1
	if m == null:
		m = current_scene
		return false
	if view == null:
		view = m.get_node("View")
		_check(view.prematch != null, "build-up starts")
		for p in view.prematch._snap:
			spots[p] = view.prematch._snap[p][0]
		return false
	var pm = view.prematch
	if pm != null:
		_check(m.manual_step, "match held during the build-up")
		_check(m.clock == 0.0, "clock still during the build-up")
		var t: float = pm.t
		if frame == 60:
			_shot("prematch_flight")
		if frame == 60 * 9:
			_shot("prematch_walkout")
			var p = m.squads[0][0]
			_check(p.vel.length() > 1.0, "players walking out")
			_check(absf(p.pos.x - m.PITCH.x / 2.0) < 3.0, "walking out at halfway")
		if frame == 60 * 16 + 30:
			_shot("prematch_throwup")
		if frame > 60 * 30:
			_check(false, "build-up never ended (t=%.1f)" % t)
			return _end()
		return false
	if prematch_done_frame < 0:
		prematch_done_frame = frame
		print("build-up over at frame ", frame)
		for p in spots:
			_check(p.pos.distance_to(spots[p]) < 0.01, "%s back on the throw-up spot" % p.position_code)
		_check(not m.manual_step, "match released")
		_check(view.ball.visible, "ball shown")
		clock_at_end = m.clock
		return false
	# Cameras: 90 frames each, unzoomed then zoomed.
	if frame >= prematch_done_frame + 120:
		var cam: ShintyTVCamera = view.director.camera
		var c: Camera3D = view.camera
		cam_frame += 1
		if cam_frame == 1:
			cam.view = cam_phase / 2
			cam.zoomed = cam_phase % 2 == 1
		if cam_frame == 90:
			var focus: Vector3 = view.ball.global_position
			var d := c.global_position.distance_to(focus)
			var key := "%s%s" % [Game.CAMERA_NAMES[cam.view], " zoomed" if cam.zoomed else ""]
			dist[key] = d
			print("%s: eye %s, %.1f yd from the ball, fov %.1f" % [key, c.global_position, d, c.fov])
			_check(c.global_position.is_finite() and c.fov > 5.0 and c.fov < 80.0, key + " camera sane")
			_shot("camera_" + key.to_snake_case().replace(" ", "_"))
			cam_phase += 1
			cam_frame = 0
			if cam_phase >= 6:
				_check(dist["TV"] > dist["Close TV"], "close TV nearer than TV")
				_check(dist["Close TV"] > dist["End to end"], "end to end nearest")
				_check(dist["End to end zoomed"] < dist["End to end"], "zoom brings end to end in")
				_check(m.state != m.State.THROW_UP and m.clock > clock_at_end, "the throw-up was played and the clock runs")
				return _end()
	return false


func _end() -> bool:
	print("camera test ", "PASSED" if ok else "FAILED")
	quit(0 if ok else 1)
	return true
