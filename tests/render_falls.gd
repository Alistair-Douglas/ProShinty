extends SceneTree
## Renders knockdowns frame by frame, side on: top row knocked backwards
## off a challenge, bottom row pushed from behind and going down forwards.
## xvfb-run godot --path . --resolution 2400x1100 -s tests/render_falls.gd -- <out.png>

const TIMES := [0.3, 1.0, 1.25, 1.4, 1.55]
const GAP := 2.4


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://falls.png"
	var world := Node3D.new()
	root.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	world.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.36, 0.55, 0.32)
	env.environment.ambient_light_color = Color(0.75, 0.75, 0.78)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.add_child(env)
	var team := {"colors": {"primary": "#1d4fb8", "secondary": "#f2f2f2", "pattern": "hoops"}}
	for row in 2:
		for i in TIMES.size():
			var m := ShintyPlayerModel.new()
			m.manual_update = true
			world.add_child(m)
			m.setup({"number": 7, "name": "Player 7", "position": "LM"}, team)
			var x := (i - (TIMES.size() - 1) / 2.0) * GAP + 0.3
			m.position = Vector3(x, -row * 2.6, 0)
			m.rotation.y = PI * 0.5   # running left (towards -X)
			m.set_locomotion(Vector3(-5, 0, 0))
			for f in 60:
				m.advance(1.0 / 60.0)
			# Row 0: met head on and knocked back; row 1: shoved from behind.
			m.set_locomotion(Vector3(-1.0, 0, 0) if row == 0 else Vector3(-8.5, 0, 0))
			m.advance(1.0 / 60.0)
			m.play_action(&"stumble", 1.0)
			var t := 0.0
			while t < TIMES[i]:
				m.advance(1.0 / 60.0)
				t += 1.0 / 60.0
			if row == 0:
				var tag := Label3D.new()
				tag.text = "%.2f s" % TIMES[i]
				tag.font_size = 30
				tag.outline_size = 10
				tag.pixel_size = 0.004
				tag.position = Vector3(x + 0.6, 2.1, 0)
				world.add_child(tag)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 6.0
	cam.position = Vector3(0, -0.4, 10)
	world.add_child(cam)
	cam.make_current()
	for i in 6:
		await process_frame
	root.get_texture().get_image().save_png(out)
	print("saved ", out)
	quit()
