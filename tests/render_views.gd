extends SceneTree
## Renders the preview from each set view (and each lighting preset from the
## broadcast view) to renders/. Needs a display:
##   xvfb-run godot --path . --rendering-method gl_compatibility -s tests/render_views.gd

func _initialize() -> void:
	var scene: Node3D = load("res://preview/preview.tscn").instantiate()
	root.add_child(scene)
	_run.call_deferred(scene)


func _run(scene: Node3D) -> void:
	DirAccess.make_dir_recursive_absolute("res://renders")
	var cam: Camera3D = scene.get_node("Camera")
	var pitch: Node3D = scene.get_node("ShintyPitch")
	var shots := [[1, 0, "broadcast_afternoon"], [2, 0, "west_end"], [3, 0, "east_end"],
			[4, 0, "looking_south"], [5, 0, "aerial"], [1, 1, "broadcast_evening"], [1, 2, "broadcast_overcast"]]
	for s in shots:
		if pitch.lighting != s[1]:
			pitch.lighting = s[1]
		cam.set_view(s[0])
		for i in 12:
			await process_frame
		var img := root.get_viewport().get_texture().get_image()
		img.save_png("res://renders/%s.png" % s[2])
		print("saved ", s[2])
	# Sanity checks on the API.
	var p: ShintyPitch = pitch
	assert(p.sim_to_world(Vector2(75, 37.5)).is_equal_approx(Vector3.ZERO))
	assert(p.world_to_sim(p.goal_position(1)).is_equal_approx(Vector2(150, 37.5)))
	print("pitch size ", p.pitch_size(), " goal east ", p.goal_position(1))
	quit()
