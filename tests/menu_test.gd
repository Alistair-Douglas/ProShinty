extends SceneTree
## Drives the main menu with keys and the mouse and saves screenshots.
## xvfb-run godot --path . -s tests/menu_test.gd -- <out_dir>
var frame := 0
var out := ""


func _initialize() -> void:
	out = OS.get_cmdline_user_args()[0]
	change_scene_to_file("res://scenes/main_menu.tscn")


func _key(k: Key) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new(); e.keycode = k; e.physical_keycode = k; e.pressed = pressed
		root.push_input(e)


func _shot(name: String) -> void:
	root.get_texture().get_image().save_png(out + "/" + name + ".png")


func _process(_d: float) -> bool:
	frame += 1
	var m = current_scene
	match frame:
		90: _shot("menu_hub"); print("focus: ", root.gui_get_focus_owner().get_class()); _key(KEY_ENTER)
		150: _shot("menu_kickoff_start"); print("screen: ", m.current)
		151: m.away_pick.grab_focus()
		152: _key(KEY_RIGHT)
		153: m.home_pick.grab_focus()
		154: _key(KEY_LEFT)
		200: _shot("menu_kickoff"); print("home %s away %s pitch %s" % [m.home_pick.team()["name"], m.away_pick.team()["name"], m.pitch_pick.get_item_text(m.pitch_pick.selected)])
		201: _key(KEY_ESCAPE)
		230: m.screens["hub"].get_meta("first").get_parent().get_child(1).grab_focus()
		231: _key(KEY_ENTER)
		290: _shot("menu_squads"); _key(KEY_ESCAPE)
		300: m.screens["hub"].get_meta("first").get_parent().get_child(2).grab_focus()
		301: _key(KEY_ENTER)
		360: _shot("menu_controls"); _key(KEY_ESCAPE)
		370: m.screens["hub"].get_meta("first").grab_focus()
		371: _key(KEY_ENTER)
		420: m.start_button.grab_focus()
		421: _key(KEY_ENTER)
		470: print("scene now: ", current_scene.name); _shot("loading")
		700: _shot("loading_ready"); print("loading ready: ", current_scene.get("ready_to_play")); _key(KEY_SPACE)
		800: print("scene now: ", current_scene.name, "  venue: ", current_scene.get("config").get("venue") if current_scene.get("config") else "-"); _shot("match"); return true
	return false
