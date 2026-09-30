extends SceneTree
## Close-ups of a caman's bas: from the toe end (its triangular section) and
## from the side.
##   xvfb-run -s "-screen 0 1280x720x24" godot --path . -s tests/render_bas_closeup.gd -- <out.png>


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("2a3440")
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.65)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 40, 0)
	root.add_child(sun)
	var cam_node := Node3D.new()
	root.add_child(cam_node)
	ShintyCaman.build(cam_node, {"wood": 1, "face": 1, "face_back": 1}, true)
	var L := ShintyPlayerModel.CAMAN_LENGTH
	var cam := Camera3D.new()
	cam.fov = 30
	root.add_child(cam)
	# Three shots side by side: the toe end on, from the front face, from above.
	var shots := [[Vector3(0.0, -L + 0.0, -0.5), Vector3(0, -L + 0.02, -0.1)],
		[Vector3(0.5, -L + 0.12, -0.08), Vector3(0, -L + 0.08, -0.06)],
		[Vector3(0.25, -L + 0.3, -0.35), Vector3(0, -L + 0.02, -0.07)]]
	var img := Image.create(1920, 640, false, Image.FORMAT_RGBA8)
	for k in shots.size():
		cam.look_at_from_position(shots[k][0], shots[k][1])
		for i in 6:
			await process_frame
		var shot := root.get_texture().get_image()
		shot.convert(Image.FORMAT_RGBA8)
		shot.resize(960, 540)
		img.blit_rect(shot, Rect2i(160, 0, 640, 540), Vector2i(k * 640, 50))
	img.save_png(out)
	quit()
