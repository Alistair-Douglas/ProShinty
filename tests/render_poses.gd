extends SceneTree
## Renders a sheet of player poses (standing, jogging, sprinting and the swing
## from top of backswing to follow-through), seen from the side (top row) and
## from in front at an angle (bottom row).
## xvfb-run godot --path . --resolution 2400x1100 -s tests/render_poses.gd -- <out.png>

const POSES := [
	["Standing", 0.0, &"", 0.0],
	["Jogging", 3.0, &"", 0.0],
	["Sprinting", 7.0, &"", 0.0],
	["Near the ball", 3.0, &"near", 0.0],
	["Swing on the run", 5.0, &"swing", 0.36],
	["Swing: top", 0.0, &"swing", 0.36],
	["Swing: contact", 0.0, &"swing", 0.47],
	["Swing: follow", 0.0, &"swing", 0.62],
]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://poses.png"
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
		for i in POSES.size():
			var pose: Array = POSES[i]
			var m := ShintyPlayerModel.new()
			m.manual_update = true
			world.add_child(m)
			m.setup({"number": 7, "name": "Player 7", "position": "LM"}, team)
			var x := (i - (POSES.size() - 1) / 2.0) * 1.15
			m.position = Vector3(x, -row * 2.5, 0)
			# Top row: side on, facing left (+X is the camera's right). Bottom
			# row: towards the camera and a little to its left.
			m.rotation.y = PI * 0.5 if row == 0 else PI * 0.8
			var speed: float = pose[1]
			var vel := m.global_transform.basis * Vector3(0, 0, -speed)
			m.set_locomotion(vel)
			for f in 40:
				m.advance(1.0 / 60.0)
			var act: StringName = pose[2]
			if act == &"near":
				# The ball a couple of metres ahead: both hands come on.
				m.look_at_point(m.global_transform * Vector3(0, 0, -2.5))
				for f in 40:
					m.advance(1.0 / 60.0)
			elif act != &"":
				m.play_action(act, 1.0)
				var target: float = pose[3] * ShintyPlayerModel.ACTIONS[String(act)]
				var t := 0.0
				while t < target:
					var dt := minf(1.0 / 120.0, target - t)
					m.advance(dt)
					t += dt
			if row == 0:
				var tag := Label3D.new()
				tag.text = pose[0]
				tag.font_size = 30
				tag.outline_size = 10
				tag.pixel_size = 0.004
				tag.position = Vector3(x, 2.1, 0)
				world.add_child(tag)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 5.6
	cam.position = Vector3(0, -0.3, 10)
	world.add_child(cam)
	cam.make_current()
	for i in 6:
		await process_frame
	root.get_texture().get_image().save_png(out)
	print("saved ", out)
	quit()
