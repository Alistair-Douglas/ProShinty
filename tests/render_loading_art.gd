extends SceneTree
## Renders the loading-screen artwork in ui/loading/ from the game's own
## pitch and player models, so the pictures can be remade whenever the models
## or grounds improve. Needs a display (xvfb-run on a server):
##   xvfb-run -s "-screen 0 1920x1080x24" godot --path . --resolution 1920x1080 \
##     -s tests/render_loading_art.gd -- [only=<shot>] [out=<dir>]

const PitchScene := preload("res://pitch/shinty_pitch.tscn")
const SHOTS := ["swing", "air", "keeper", "chase", "first_ball"]

## Two made-up kits for the art, so no real club is shown.
const NAVY := {"id": "art_navy", "colors": {"primary": "#14264a", "secondary": "#f2f2f2", "keeper": "#f2c400"}}
const RED := {"id": "art_red", "colors": {"primary": "#c8102e", "secondary": "#ffffff", "keeper": "#2e9e4f"}}

var out := "res://ui/loading/"
var only := ""


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("only="):
			only = a.substr(5)
		elif a.begins_with("out="):
			out = a.substr(4).trim_suffix("/") + "/"
	_run.call_deferred()


func _run() -> void:
	for shot in SHOTS:
		if only != "" and shot != only:
			continue
		var world := Node3D.new()
		root.add_child(world)
		var cam := Camera3D.new()
		cam.fov = 38.0
		cam.near = 0.05
		cam.far = 900.0
		world.add_child(cam)
		call("_shot_" + shot, world, cam)
		cam.make_current()
		for i in 12:
			await process_frame
		var img := root.get_texture().get_image()
		var path := ProjectSettings.globalize_path(out + shot + ".jpg")
		img.save_jpg(path, 0.86)
		print("saved ", path, " ", img.get_size())
		world.queue_free()
		await process_frame
	quit()


func _pitch(world: Node3D, venue: int, lighting: int) -> Node3D:
	var p := PitchScene.instantiate()
	p.venue = venue
	p.lighting = lighting
	p.add_ground_collision = false
	p.scenery_detail = 2
	world.add_child(p)
	return p


func _player(world: Node3D, team: Dictionary, pos: Vector3, yaw: float, number := 9, position := "CF", stats := {}) -> ShintyPlayerModel:
	var m := ShintyPlayerModel.new()
	m.manual_update = true
	world.add_child(m)
	var p := {"number": number, "position": position, "pace": 78, "tackling": 64, "shooting": 80}
	p.merge(stats, true)
	m.setup(p, team)
	m.position = pos
	m.rotation.y = yaw
	return m


## Step a model to `t` seconds into an action.
func _pose(m: ShintyPlayerModel, action: StringName, t: float, power := 1.0, height := 0.0) -> void:
	m.play_action(action, power, height)
	var step := 1.0 / 60.0
	var done := 0.0
	while done < t:
		m.advance(minf(step, t - done))
		done += step


func _run_cycle(m: ShintyPlayerModel, velocity: Vector3, t: float) -> void:
	m.set_locomotion(velocity)
	var done := 0.0
	while done < t:
		m.advance(1.0 / 60.0)
		done += 1.0 / 60.0


func _ball(world: Node3D, at: Vector3, scale := 1.0) -> ShintyBallModel:
	var b := ShintyBallModel.new()
	b.simulate = false
	b.auto_find_hails = false
	b.display_scale = scale
	world.add_child(b)
	b.place(at)
	return b


func _look(cam: Camera3D, from: Vector3, at: Vector3) -> void:
	cam.transform = Transform3D.IDENTITY.translated(from).looking_at(at, Vector3.UP)


# --- The pictures ---------------------------------------------------------------

## Low, side-on: a forward at the top of the backswing over a still ball.
func _shot_swing(world: Node3D, cam: Camera3D) -> void:
	_pitch(world, 0, 1)
	var m := _player(world, NAVY, Vector3(0, 0, 0), PI * 0.5)
	_pose(m, &"swing", 0.29)
	m.look_at_point(m.get_strike_spot())
	m.advance(0.0)
	_ball(world, m.get_strike_spot(), 1.3)
	var closing := _player(world, RED, Vector3(7.5, 0, -7.0), 0.0, 4, "CHB")
	_run_cycle(closing, Vector3(-4.0, 0, 5.0), 0.6)
	_look(cam, Vector3(-0.2, 0.45, 3.1), Vector3(0.45, 1.05, 0.0))
	cam.fov = 44.0


## A mid-air volley: the ball at head height, caman meeting it.
func _shot_air(world: Node3D, cam: Camera3D) -> void:
	_pitch(world, 1, 0)
	var m := _player(world, RED, Vector3(0, 0, 0), -PI * 0.2, 11)
	_pose(m, &"volley", 0.62 * 0.42, 1.0, 1.3)
	_ball(world, m.get_caman_head_position() + Vector3(0, 0.05, -0.08), 1.3)
	var chaser := _player(world, NAVY, Vector3(2.6, 0, 3.4), -PI * 0.75, 5, "RHB")
	_run_cycle(chaser, Vector3(-3.5, 0, -4.5), 0.43)
	chaser.look_at_point(m.get_caman_head_position())
	chaser.advance(0.0)
	_look(cam, Vector3(1.9, 0.35, -3.4), Vector3(0.0, 1.35, 0))
	cam.fov = 46.0


## Behind a shooter: the ball flying at the goal, the keeper diving.
func _shot_keeper(world: Node3D, cam: Camera3D) -> void:
	var pitch := _pitch(world, 1, 1)
	var g: Vector3 = pitch.goal_position(1)
	var keeper := _player(world, RED, g + Vector3(-0.6, 0, 0.2), PI * 0.5, 1, "GK", {"keeping": 85})
	_pose(keeper, &"save_left", 0.5)
	var shooter := _player(world, NAVY, g + Vector3(-9.2, 0, -2.2), -PI * 0.5 + 0.25, 10)
	_pose(shooter, &"swing", 0.78 * 0.62)
	_ball(world, g + Vector3(-4.6, 1.3, -0.9), 1.6)
	_look(cam, g + Vector3(-12.5, 0.7, -0.4), g + Vector3(0, 1.3, -1.2))
	cam.fov = 36.0


## Side-on at ground level: two players racing shoulder to shoulder.
func _shot_chase(world: Node3D, cam: Camera3D) -> void:
	_pitch(world, 0, 0)
	var a := _player(world, NAVY, Vector3(0, 0, 0.35), PI * 0.5, 7, "RM")
	var b := _player(world, RED, Vector3(0.7, 0, -0.9), PI * 0.5, 6, "LM")
	_run_cycle(a, Vector3(-8.5, 0, 0), 0.52)
	_run_cycle(b, Vector3(-8.5, 0, 0), 0.8)
	var ball := Vector3(-3.2, ShintyBallPhysics.RADIUS, 0.0)
	_ball(world, ball, 1.3)
	a.look_at_point(ball)
	b.look_at_point(ball)
	a.advance(0.0)
	b.advance(0.0)
	_look(cam, Vector3(-1.7, 0.55, 5.4), Vector3(-1.0, 1.0, 0))
	cam.fov = 40.0


## The start of every match: the ball thrown up between two players.
func _shot_first_ball(world: Node3D, cam: Camera3D) -> void:
	_pitch(world, 1, 1)
	var a := _player(world, NAVY, Vector3(-0.55, 0, 0), -PI * 0.5 + PI, 8, "CHF")
	var b := _player(world, RED, Vector3(0.55, 0, 0), PI * 0.5 + PI, 5, "CHB")
	a.rotation.y = -PI * 0.5
	b.rotation.y = PI * 0.5
	var ball := Vector3(0, 2.7, 0)
	for m in [a, b]:
		m.charge_swing()
		_run_cycle(m, Vector3.ZERO, 0.4)
		m.look_at_point(ball)
		m.advance(0.0)
	_ball(world, ball, 1.3)
	_look(cam, Vector3(0.4, 0.25, 4.0), Vector3(0, 1.75, 0))
	cam.fov = 50.0
