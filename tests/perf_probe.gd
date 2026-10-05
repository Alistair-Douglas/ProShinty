extends SceneTree
## Measures what a match costs to draw at each ground: draw calls, triangles
## and objects (camera pass and shadow pass), plus CPU/GPU frame times.
## Needs a renderer (not --headless):
##   xvfb-run godot --path . -s tests/perf_probe.gd [-- quality=low|medium|high] [split]
## `split` also measures with the players hidden, to separate players from scenery,
## `without=Canopy,LongGrass` with matching scenery hidden, and `wide` from two
## fixed cameras that take in the scenery.

const MatchScene := preload("res://scenes/match.tscn")


func _initialize() -> void:
	_run.call_deferred()


func _info(kind: int, what: int) -> int:
	return RenderingServer.viewport_get_render_info(root.get_viewport_rid(), kind, what)


func _sample(frames: int) -> Dictionary:
	var vp := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	var acc := {"draw": 0.0, "prims": 0.0, "objs": 0.0, "sh_draw": 0.0, "sh_prims": 0.0, "cpu": 0.0, "gpu": 0.0, "frame": 0.0}
	for i in frames:
		var t0 := Time.get_ticks_usec()
		await process_frame
		acc["frame"] += (Time.get_ticks_usec() - t0) / 1000.0
		acc["draw"] += _info(RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
		acc["prims"] += _info(RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)
		acc["objs"] += _info(RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME)
		acc["sh_draw"] += _info(RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
		acc["sh_prims"] += _info(RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)
		acc["cpu"] += RenderingServer.viewport_get_measured_render_time_cpu(vp)
		acc["gpu"] += RenderingServer.viewport_get_measured_render_time_gpu(vp)
	for k in acc:
		acc[k] /= frames
	return acc


func _fmt(label: String, s: Dictionary) -> String:
	return "%-28s draws %5d (+%5d shadow)  tris %6.2fM (+%5.2fM shadow)  objects %4d  frame %6.1f ms  render cpu %5.1f gpu %6.1f" % [
		label, s["draw"], s["sh_draw"], s["prims"] / 1e6, s["sh_prims"] / 1e6, s["objs"], s["frame"], s["cpu"], s["gpu"]]


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var game = root.get_node("Game")
	for a in args:
		if a.begins_with("quality="):
			var q := a.get_slice("=", 1)
			if game.has_method("set_graphics_quality"):
				game.set_graphics_quality(["low", "medium", "high"].find(q), false)
	print("renderer ", RenderingServer.get_current_rendering_method(), " on ", RenderingServer.get_video_adapter_name(),
		", quality ", game.get("graphics_quality") if "graphics_quality" in game else "n/a")
	for venue in ShintyPitch.VENUE_NAMES.size():
		var m = MatchScene.instantiate()
		m.config = {"home": game.teams[0], "away": game.teams[1], "human_side": 0, "difficulty": 1,
			"half_seconds": 180.0, "venue": venue, "seed": 11}
		root.add_child(m)
		for i in 30:
			await process_frame
		var name: String = ShintyPitch.VENUE_FILES[venue].get_basename().capitalize()
		print(_fmt(name, await _sample(40)))
		if "split" in args:
			var view = m.get_node("View")
			for p in view.figures:
				view.figures[p]["root"].hide()
			view.referee_figure["root"].hide()
			view.set_process(false)
			await process_frame
			print(_fmt(name + " (no players)", await _sample(20)))
		# wide: two fixed cameras that take in the scenery round the pitch, the
		# views where trees and long grass cost the most.
		if "wide" in args:
			var cam := Camera3D.new()
			cam.fov = 45.0
			cam.far = 6000.0
			m.add_child(cam)
			cam.current = true
			for v in [[Vector3(0, 18, 55), Vector3(0, 0, -30), "wide across"], [Vector3(70, 8, 30), Vector3(-80, 5, -40), "wide along"]]:
				cam.position = v[0]
				cam.look_at(v[1])
				await process_frame
				print(_fmt(name + " (" + v[2] + ")", await _sample(15)))
				if "shot" in args:
					root.get_viewport().get_texture().get_image().save_png(OS.get_cache_dir().path_join("perf_%s_%s_%s.png" % [name.to_lower(), v[2].replace(" ", "_"), game.get("graphics_quality")]))
			cam.queue_free()
			await process_frame
		# without=Canopy,LongGrass hides scenery whose node name contains any of
		# those, to see what each part costs.
		for a in args:
			if a.begins_with("without="):
				var parts := a.get_slice("=", 1).split(",")
				for n in m.find_children("*", "GeometryInstance3D", true, false):
					for part in parts:
						if part in String(n.name):
							n.hide()
				await process_frame
				print(_fmt(name + " (" + a + ")", await _sample(20)))
		if "shot" in args:
			root.get_viewport().get_texture().get_image().save_png(OS.get_cache_dir().path_join("perf_%s_%s.png" % [name.to_lower(), game.get("graphics_quality")]))
		m.queue_free()
		await process_frame
		await process_frame
	quit()
