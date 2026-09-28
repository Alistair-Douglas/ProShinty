extends SceneTree
## Renders the preview of each ground from each set view (and Aberdour in each
## lighting preset) to renders/. Needs a display:
##   xvfb-run godot --path . --rendering-method gl_compatibility -s tests/render_views.gd
## Add `-- quick` for just the match camera and west end of each ground, and
## `quality=0|1|2` for the Low/Medium/High graphics setting (default High).

func _initialize() -> void:
	var scene: Node3D = load("res://preview/preview.tscn").instantiate()
	root.add_child(scene)
	_run.call_deferred(scene)


func _run(scene: Node3D) -> void:
	DirAccess.make_dir_recursive_absolute("res://renders")
	var cam: Camera3D = scene.get_node("Camera")
	var pitch: Node3D = scene.get_node("ShintyPitch")
	var views := [[1, "broadcast"], [6, "match_camera"], [2, "west_end"], [3, "east_end"],
			[4, "looking_south"], [5, "aerial"]]
	for a in OS.get_cmdline_user_args():
		if a.begins_with("quality="):
			pitch.graphics_quality = int(a.get_slice("=", 1))
			root.get_node("Game").set_graphics_quality(pitch.graphics_quality, false)
	var shots := []
	for v in ShintyPitch.VENUE_NAMES.size():
		for view in views:
			shots.append([v, view[0], 0, view[1]])
	if "quick" in OS.get_cmdline_user_args():
		shots = shots.filter(func(s): return s[1] == 6 or s[1] == 2)
	shots.append([0, 1, 1, "broadcast_evening"])
	shots.append([0, 1, 2, "broadcast_overcast"])
	for s in shots:
		if pitch.venue != s[0]:
			pitch.venue = s[0]
		if pitch.lighting != s[2]:
			pitch.lighting = s[2]
		cam.set_view(s[1])
		for i in 12:
			await process_frame
		var name: String = ["aberdour", "kingussie", "tighnabruaich"][s[0]] + "_" + s[3]
		root.get_viewport().get_texture().get_image().save_png("res://renders/%s.png" % name)
		print("saved ", name)
	pitch.venue = 0
	pitch.lighting = 0
	await process_frame
	# Sanity checks on the API.
	var p: ShintyPitch = pitch
	assert(p.sim_to_world(Vector2(75, 37.5)).is_equal_approx(Vector3.ZERO))
	assert(p.world_to_sim(p.goal_position(1)).is_equal_approx(Vector2(150, 37.5)))
	print("pitch size ", p.pitch_size(), " goal east ", p.goal_position(1))
	quit()
