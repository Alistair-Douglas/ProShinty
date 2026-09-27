extends Node3D
## Showcase for the shinty models: both squads lined up, a forward hitting
## balls at the hail, a keeper trying to save, and players running laps.
##
## Keys: 1 line-up camera, 2 close-up, 3 behind the striker, 4 by the hail,
## Space hits now, L toggles lofted hits.
## Screenshots (for tests): --shot=<name> --out=<file.png> after "--".

const TeamsPath := "res://data/teams.json"

var teams: Array = []
var striker: ShintyPlayerModel
var keeper: ShintyPlayerModel
var ball: ShintyBallModel
var hail: ShintyHailModel
var runners: Array = []
var camera: Camera3D
var cam_mode := 1
var lofted := true
var rng := RandomNumberGenerator.new()
var _next_hit := 1.0
var _shot := ""
var _out := ""
var _hit_count := 0


func _ready() -> void:
	rng.seed = 2026
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			_shot = a.substr(7)
		elif a.begins_with("--out="):
			_out = a.substr(6)
	var data = JSON.parse_string(FileAccess.get_file_as_string(TeamsPath))
	teams = data["teams"]
	_build_world()

	hail = ShintyHailModel.new()
	add_child(hail)
	hail.position = Vector3(0, 0, -24)
	hail.rotation.y = PI

	# Line-ups: Kingussie on the left, Aberdour on the right, facing the camera.
	for ti in teams.size():
		var team: Dictionary = teams[ti]
		var i := 0
		for p in team["players"]:
			var m := ShintyPlayerModel.new()
			add_child(m)
			m.setup(p, team)
			var side := -1.0 if ti == 0 else 1.0
			m.position = Vector3(side * (2.2 + i * 1.05), 0, 6.0)
			m.rotation.y = PI  # face +Z, towards the line-up camera
			m.look_at_point(Vector3(0, 1.6, 16))
			i += 1

	# Striker (Kingussie CF) and keeper (Aberdour GK)
	striker = ShintyPlayerModel.new()
	add_child(striker)
	striker.setup(_find(teams[0], "CF"), teams[0])
	striker.position = Vector3(1.5, 0, -8)
	keeper = ShintyPlayerModel.new()
	add_child(keeper)
	keeper.setup(_find(teams[1], "GK"), teams[1])
	keeper.position = Vector3(0, 0, -23.2)
	keeper.rotation.y = PI
	striker.strike.connect(_on_strike)

	ball = ShintyBallModel.new()
	ball.display_scale = 2.5
	ball.show_landing_marker = true
	add_child(ball)
	ball.goal.connect(func(_h): _celebrate())
	_reset_ball()

	# Two players jogging and sprinting round a loop
	for k in 2:
		var r := ShintyPlayerModel.new()
		add_child(r)
		var team: Dictionary = teams[k]
		r.setup(team["players"][4 + k], team)
		r.auto_face = true
		r.set_meta("speed", 3.5 if k == 0 else 7.5)
		r.set_meta("angle", k * PI)
		runners.append(r)

	camera = Camera3D.new()
	camera.fov = 50
	add_child(camera)
	camera.current = true
	if _shot != "":
		_run_shot.call_deferred()
		get_tree().create_timer(30.0).timeout.connect(func(): print("shot timed out"); get_tree().quit(2))


func _find(team: Dictionary, pos: String) -> Dictionary:
	for p in team["players"]:
		if p["position"] == pos:
			return p
	return team["players"][0]


func _build_world() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("5d86b8")
	sky_mat.sky_horizon_color = Color("b9c9d6")
	sky_mat.ground_horizon_color = Color("55624a")
	sky_mat.ground_bottom_color = Color("3a4433")
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	add_child(sun)
	# Grass with mown stripes
	for i in 12:
		var strip := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(60, 6)
		strip.mesh = pm
		var gm := StandardMaterial3D.new()
		gm.albedo_color = Color("2f5f27") if i % 2 == 0 else Color("36692c")
		gm.roughness = 0.95
		strip.material_override = gm
		strip.position = Vector3(0, 0, -33 + i * 6)
		add_child(strip)
	var lm := StandardMaterial3D.new()
	lm.albedo_color = Color(0.95, 0.95, 0.95)
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var goal_line := MeshInstance3D.new()
	var gl := PlaneMesh.new()
	gl.size = Vector2(60, 0.1)
	goal_line.mesh = gl
	goal_line.material_override = lm
	goal_line.position = Vector3(0, 0.005, -24)
	add_child(goal_line)
	# The D in front of the hail (10 yard radius)
	var n := 40
	for i in n:
		var a0 := PI * i / n
		var a1 := PI * (i + 1) / n
		var r := 9.14
		var p0 := Vector3(cos(a0) * r, 0.005, -24 + sin(a0) * r)
		var p1 := Vector3(cos(a1) * r, 0.005, -24 + sin(a1) * r)
		var seg := MeshInstance3D.new()
		var sm := PlaneMesh.new()
		sm.size = Vector2(p0.distance_to(p1) + 0.02, 0.1)
		seg.mesh = sm
		seg.material_override = lm
		seg.position = (p0 + p1) / 2.0
		seg.rotation.y = -atan2(p1.z - p0.z, p1.x - p0.x)
		add_child(seg)


func _process(delta: float) -> void:
	# Striker: line up behind the ball and hit it at the hail.
	if not striker.is_busy():
		_next_hit -= delta
		if _next_hit <= 0.0 and not ball.is_airborne() and ball.get_velocity().length() < 0.1:
			_hit_count += 1
			striker.play_action(&"swing", rng.randf_range(0.75, 1.0))
	striker.look_at_point(ball.global_position)
	keeper.look_at_point(ball.global_position)
	# Keeper shuffles across to cover the ball's line.
	var target_x := clampf(ball.global_position.x * 0.3, -1.3, 1.3)
	if not keeper.is_busy():
		var dx := target_x - keeper.position.x
		keeper.position.x += clampf(dx, -2.0 * delta, 2.0 * delta)
		keeper.set_locomotion(Vector3(signf(dx) * minf(absf(dx) * 3.0, 2.0), 0, 0))
		var v := ball.get_velocity()
		if v.z < -10.0 and ball.global_position.z < -12.0:
			var tt := (-23.2 - ball.global_position.z) / v.z
			var arrive_x := ball.global_position.x + v.x * tt
			keeper.play_action(&"save_left" if arrive_x < keeper.position.x - 0.3 else &"save_right" if arrive_x > keeper.position.x + 0.3 else &"trap")
	# Runners go round an oval.
	for r in runners:
		var sp: float = r.get_meta("speed")
		var ang: float = r.get_meta("angle") + delta * sp / 9.0
		r.set_meta("angle", ang)
		var pos := Vector3(cos(ang) * 11.0, 0, -4 + sin(ang) * 7.0)
		var vel: Vector3 = (pos - r.position) / maxf(delta, 0.001)
		r.position = pos
		r.set_locomotion(vel)
	# Ball reset once it stops or is out of play.
	if ball.get_velocity().length() < 0.05 and not ball.is_airborne() and _next_hit < -2.0:
		_reset_ball()
	_update_camera(delta)


func _on_strike(_head: Vector3, power: float) -> void:
	var target := Vector3(rng.randf_range(-1.4, 1.4), 0, -24)
	var aim := target - ball.global_position
	var loft := rng.randf_range(0.12, 0.3) if lofted else 0.0
	var res := ShintyStrike.hit(striker, ball, aim, power, loft, "shot", rng)
	_next_hit = 0.0
	if res["miss"]:
		print("Missed the ball")


func _celebrate() -> void:
	striker.play_action(&"celebrate")


func _reset_ball() -> void:
	ball.place(striker.get_strike_spot() + Vector3(0, ShintyBallPhysics.RADIUS, 0))
	_next_hit = 1.2


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed:
		match e.keycode:
			KEY_1: cam_mode = 1
			KEY_2: cam_mode = 2
			KEY_3: cam_mode = 3
			KEY_4: cam_mode = 4
			KEY_L: lofted = not lofted
			KEY_SPACE: _next_hit = 0.0


func _update_camera(_delta: float) -> void:
	match cam_mode:
		1:
			camera.position = Vector3(0, 2.6, 21)
			camera.look_at(Vector3(0, 1.0, 6))
		2:
			var p := Vector3(-2.2, 0, 6)
			camera.position = p + Vector3(0.9, 1.75, 2.1)
			camera.look_at(p + Vector3(0, 1.35, 0))
		3:
			camera.position = striker.position + Vector3(2.5, 1.9, 4.5)
			camera.look_at(Vector3(0, 1.0, -20))
		4:
			camera.position = Vector3(6.5, 2.2, -16)
			camera.look_at(Vector3(-0.5, 1.1, -23.5))
		5:
			camera.position = striker.position + Vector3(2.6, 1.3, 0.4)
			camera.look_at(striker.position + Vector3(0, 0.9, -0.4))


# --- Scripted screenshots -------------------------------------------------------

func _run_shot() -> void:
	match _shot:
		"lineup":
			cam_mode = 1
			await _frames(30)
		"closeup":
			cam_mode = 2
			await _frames(30)
		"swing":
			cam_mode = 5
			_next_hit = 999.0
			await _frames(20)
			striker.play_action(&"swing", 1.0)
			await get_tree().create_timer(striker.time_to_contact() * 0.7).timeout
		"flight":
			cam_mode = 3
			await _wait_for(func(): return ball.global_position.z < -14.0, 8.0)
		"goal":
			cam_mode = 4
			await _wait_for(func(): return ball.global_position.z < -24.6, 12.0)
			await get_tree().create_timer(0.05).timeout
		"run":
			cam_mode = 1
			camera.position = Vector3(0, 3.0, 12)
			await _frames(40)
			camera.look_at(runners[1].position + Vector3(0, 1, 0))
	await _frames(2)
	var img := get_viewport().get_texture().get_image()
	img.save_png(_out)
	print("saved ", _out)
	get_tree().quit()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _wait_for(cond: Callable, timeout: float) -> void:
	var t := 0.0
	while t < timeout and not cond.call():
		await get_tree().process_frame
		t += get_process_delta_time()
