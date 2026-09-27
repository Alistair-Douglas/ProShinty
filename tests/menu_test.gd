extends SceneTree
var frame := 0
var out := ""
func _initialize() -> void:
	out = OS.get_cmdline_user_args()[0]
	change_scene_to_file("res://scenes/main_menu.tscn")
func _click(p: Vector2) -> void:
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = p
		e.global_position = p
		root.push_input(e)
func _key(k: Key) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new(); e.keycode = k; e.physical_keycode = k; e.pressed = pressed
		root.push_input(e)
func _process(_d: float) -> bool:
	frame += 1
	var m = current_scene
	if frame == 10: print("focus: ", root.gui_get_focus_owner()); _click(Vector2(295, 222))  # away team dropdown
	if frame == 20: root.get_texture().get_image().save_png(out + "/popup.png"); _key(KEY_UP); _key(KEY_ENTER)
	if frame == 30: print("away selected: ", m.away_pick.selected, "  pitch: ", m.pitch_pick.get_item_text(m.pitch_pick.selected)); root.get_texture().get_image().save_png(out + "/after_pick.png"); _key(KEY_DOWN); _key(KEY_DOWN)
	if frame == 35: _key(KEY_ESCAPE)  # close any list the arrows opened
	if frame == 40: print("focus after arrows: ", root.gui_get_focus_owner()); _click(Vector2(227, 444))  # Play match
	if frame == 60: print("scene now: ", current_scene.name, "  venue: ", current_scene.config.get("venue")); root.get_texture().get_image().save_png(out + "/match.png"); return true
	return false
