extends SceneTree
## Renders every club in its home kit (left) and change kit (right).
## xvfb-run godot --path . --resolution 2400x1500 -s tests/render_kits.gd -- <out.png>
const TeamData := preload("res://scripts/team_data.gd")
const COLS := 8


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://kits.png"
	var world := Node3D.new()
	root.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 20, 0)
	world.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.36, 0.55, 0.32)
	env.environment.ambient_light_color = Color(0.75, 0.75, 0.78)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.add_child(env)
	var teams := TeamData.load_teams()
	var rows := ceili(teams.size() / float(COLS))
	for i in teams.size():
		var t: Dictionary = teams[i]
		var cell := Vector3((i % COLS - (COLS - 1) / 2.0) * 2.0, -(i / COLS) * 2.6, 0)
		var kits := [TeamData.home_kit(t), TeamData.away_kit(t)]
		for k in 2:
			var m := ShintyPlayerModel.new()
			world.add_child(m)
			m.setup({"number": 7, "name": "Player 7", "position": "LM"}, {"colors": kits[k]})
			m.position = cell + Vector3(-0.4 + k * 0.8, 0, 0)
			m.rotation.y = PI
		var tag := Label3D.new()
		tag.text = "%s%s" % [t["name"], "" if t["colors"].get("source") == "club" else " *"]
		tag.font_size = 40
		tag.outline_size = 10
		tag.pixel_size = 0.004
		tag.position = cell + Vector3(0, -0.25, 0.3)
		world.add_child(tag)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = rows * 2.6 + 0.4
	cam.position = Vector3(0, -(rows - 1) * 1.3 + 0.8, 10)
	world.add_child(cam)
	cam.make_current()
	for i in 12:
		await process_frame
	root.get_texture().get_image().save_png(out)
	print("saved ", out)
	quit()
