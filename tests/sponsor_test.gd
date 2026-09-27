extends SceneTree
## Checks the shirt sponsor and ad boards build, and saves a close-up.
## xvfb-run godot --path . -s tests/sponsor_test.gd -- <out.png>
var out := ""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0] if args.size() > 0 else ""
	_run.call_deferred()


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	sun.shadow_enabled = true
	world.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.5, 0.65, 0.8)
	env.environment.ambient_light_color = Color(0.7, 0.7, 0.75)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.add_child(env)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.25, 0.5, 0.2)
	ground.material_override = gm
	world.add_child(ground)

	var ok := true
	var ids := ShintySponsors.ids()
	print("sponsors: ", ids.size())
	ok = ok and ids.size() >= 4
	var teams := [
		{"id": "kingussie", "colors": {"primary": "#b3122e", "secondary": "#f2f2f2"}},
		{"id": "aberdour", "colors": {"primary": "#1f4fa3", "secondary": "#ffd23f"}},
	]
	for i in 2:
		var m := ShintyPlayerModel.new()
		world.add_child(m)
		m.setup({"number": 7 + i, "name": "Player %d" % (7 + i), "position": "LM", "pace": 70, "tackling": 50 + i * 30}, teams[i])
		m.position = Vector3(-0.45 + i * 0.9, 0, 0)
		m.rotation.y = PI
		var sid := ShintySponsors.for_team(teams[i])
		var print_node := ShintyKitSponsor.apply(m, ShintySponsors.shirt_texture(sid))
		print("team %s sponsor %s print %s" % [teams[i]["id"], sid, print_node != null])
		ok = ok and print_node != null
	var boards := ShintyAdBoard.place_row(world, Vector3(-9, 0, -4), Vector3(9, 0, -4), Vector3(0, 0, 10))
	print("boards: ", boards.size())
	ok = ok and boards.size() == 2
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.fov = 40
	cam.transform = Transform3D.IDENTITY.translated(Vector3(0.3, 1.35, 3.6)).looking_at(Vector3(0, 1.0, -1.0), Vector3.UP)
	cam.make_current()
	for i in 10:
		await process_frame
	if out != "":
		root.get_texture().get_image().save_png(out)
	print("PASS" if ok else "FAIL")
	quit(0 if ok else 1)
