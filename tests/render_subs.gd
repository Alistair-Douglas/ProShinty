extends SceneTree
## Screenshots of substitutions: the team screen (formation and bench) from the pause menu (driven
## with ui actions, as a pad would), then the TV board and the players
## jogging off and on at the next stoppage, and the benches (subs in bibs
## in the dugouts, and the player who came off sat beside them).
## xvfb-run godot --path . -s tests/render_subs.gd -- <out_dir>
var out := ""
var frame := 0
var m: Node
var menu: Control
var ok := true


func _initialize() -> void:
	out = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else ""
	change_scene_to_file("res://scenes/match.tscn")


func _shot(name: String) -> void:
	if out != "":
		root.get_texture().get_image().save_png(out + "/" + name + ".png")
	print("shot ", name)


func _press(action: String) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	Input.parse_input_event(e)
	var r := InputEventAction.new()
	r.action = action
	r.pressed = false
	Input.parse_input_event(r)


func _process(_d: float) -> bool:
	frame += 1
	if m == null:
		m = current_scene
		return false
	if menu == null:
		menu = m.find_children("*", "Control", true, false).filter(func(c): return c.has_method("is_open"))[0]
	match frame:
		60:
			# Close up on the home dugout: the bench in neon bibs.
			var view = m.get_node("View")
			var t := 0
			var cam := Camera3D.new()
			cam.name = "BenchCam"
			view.add_child(cam)
			var at: Vector3 = view.w(view.benches.dugout_sim(t))
			cam.position = at + Vector3(0.8, 2.4, 4.2)
			cam.look_at(at + Vector3(0, 0.5, -0.4), Vector3.UP)
			cam.current = true
		64:
			_shot("subs_bench_0")
			var view = m.get_node("View")
			view.get_node("BenchCam").free()
			view.camera.current = true
			ok = ok and view.benches.seated.size() == 10
		100:
			m.paused = true
		104:
			_press("ui_accept")          # open the subs screen
		106:
			_shot("subs_formation")
		108:
			_press("ui_right")           # move up the pitch in the formation
		110:
			_press("ui_down")
		112:
			ok = ok and menu.focus != null and not menu.on_bench
			print("picked to come off: ", menu.focus.data["name"])
			_press("ui_accept")          # pick them to come off
		116:
			_shot("subs_pick")
		120:
			_press("ui_accept")          # the suggested bench player goes on
		124:
			_shot("subs_menu")
			ok = ok and m.subs.pending[m.human_side].size() == 1
		128:
			_press("ui_cancel")          # back to the pause screen
		134:
			ok = ok and not menu.is_open() and m.paused
			m.paused = false
		136:
			m._restart(1, Vector2(m.PITCH.x / 2.0 + 8.0, m.PITCH.y), "Shy")   # a stoppage near the benches
		150:
			_shot("subs_board")
		200:
			_shot("subs_jog")
			for p in m.subs.leaving:
				p.pos = m.subs.bench_spot(p.team)   # skip the rest of the walk off
		204:
			var view = m.get_node("View")
			var cam := Camera3D.new()
			cam.name = "BenchCam"
			view.add_child(cam)
			var at: Vector3 = view.w(view.benches.dugout_sim(m.human_side))
			cam.position = at + Vector3(0.8, 2.4, 4.2)
			cam.look_at(at + Vector3(0, 0.5, -0.4), Vector3.UP)
			cam.current = true
		208:
			_shot("subs_bench_after")
			var view = m.get_node("View")
			print("seated after the change: ", view.benches.seated.size())
			ok = ok and view.benches.seated.size() == 10
			ok = ok and m.subs.used[m.human_side] == 1
			print("subs made: ", m.subs.made)
			print("RESULT: ", "ok" if ok else "FAILED")
			quit(0 if ok else 1)
	return false
