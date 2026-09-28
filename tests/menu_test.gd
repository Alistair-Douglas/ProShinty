extends SceneTree
## Drives the main menu with keys and the mouse and saves screenshots.
## xvfb-run godot --path . -s tests/menu_test.gd -- <out_dir>
## Each step waits a few frames (and any condition) before it runs, so the
## test stays short on slow software renderers such as CI's.
var out := ""
var step := 0
var wait := 0
var steps: Array = []


func _initialize() -> void:
	out = OS.get_cmdline_user_args()[0]
	root.scaling_3d_scale = 0.5
	var m = func(): return current_scene
	var hub_button = func(i: int): return m.call().screens["hub"].get_meta("first").get_parent().get_child(i)
	steps = [
		# A lighter menu backdrop; loaded at run time, once the Game autoload exists.
		[1, func(): load("res://ui/menu_backdrop.gd").lite = true; change_scene_to_file("res://scenes/main_menu.tscn")],
		[8, func(): _shot("menu_hub"); print("focus: ", root.gui_get_focus_owner().get_class()); _key(KEY_ENTER)],
		[6, func(): _shot("menu_kickoff_start"); print("screen: ", m.call().current); m.call().away_pick.grab_focus()],
		[1, func(): _key(KEY_RIGHT)],
		[1, func(): m.call().home_pick.grab_focus()],
		[1, func(): _key(KEY_LEFT)],
		[6, func():
			var s = m.call()
			_shot("menu_kickoff")
			print("home %s away %s pitch %s" % [s.home_pick.team()["name"], s.away_pick.team()["name"], s.pitch_pick.get_item_text(s.pitch_pick.selected)])
			_key(KEY_ESCAPE)],
		[4, func(): hub_button.call(1).grab_focus()],
		[1, func(): _key(KEY_ENTER)],
		[6, func(): _shot("menu_squads"); _key(KEY_ESCAPE)],
		[4, func(): hub_button.call(2).grab_focus()],
		[1, func(): _key(KEY_ENTER)],
		[6, func(): _shot("menu_controls"); _key(KEY_ESCAPE)],
		[4, func(): hub_button.call(0).grab_focus()],
		[1, func(): _key(KEY_ENTER)],
		[4, func(): m.call().start_button.grab_focus()],
		[1, func(): _key(KEY_ENTER)],
		[4, func(): print("scene now: ", current_scene.name); _shot("loading")],
		# Wait for the match to load, then press a key to start it.
		[1, func(): _shot("loading_ready"); print("loading ready: ", current_scene.get("ready_to_play")); _key(KEY_SPACE),
			func(): return current_scene.get("ready_to_play") == true],
		[3, func():
			print("scene now: ", current_scene.name, "  venue: ", current_scene.get("config").get("venue") if current_scene.get("config") else "-")
			_shot("match"),
			func(): return current_scene != null and current_scene.name == "Match"],
	]


func _key(k: Key) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new(); e.keycode = k; e.physical_keycode = k; e.pressed = pressed
		root.push_input(e)


func _shot(name: String) -> void:
	root.get_texture().get_image().save_png(out + "/" + name + ".png")


func _process(_d: float) -> bool:
	if step >= steps.size():
		return true
	var s: Array = steps[step]
	if s.size() > 2 and not s[2].call():
		return false
	wait += 1
	if wait < s[0]:
		return false
	wait = 0
	step += 1
	print("step %d at %.1fs" % [step, Time.get_ticks_msec() / 1000.0])
	s[1].call()
	return step >= steps.size()
