extends SceneTree
## Screenshots of the match stats screen: on the pause screen, at half time
## (held once the players are off until A / Enter) and at full time.
## xvfb-run godot --path . -s tests/render_stats.gd -- <out_dir>
var out := ""
var frame := 0
var m: Node
var panel: Control
var ok := true
var full_seen := -1


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
	if panel == null:
		panel = m.find_children("*", "Control", true, false).filter(func(c): return c.has_method("is_showing"))[0]
	match frame:
		600:
			m.paused = true
		606:
			ok = ok and panel.mode() == "pause"
			_shot("stats_pause")
			m.paused = false
		610:
			m.clock = m.half_length()   # blow for half time
		1100:
			ok = ok and m.state == m.State.HALF_TIME
			_shot("stats_half_time")
			_press("ui_accept")
		1200:
			ok = ok and m.state != m.State.HALF_TIME
			m.score = [2, 1]
			m.clock = m.half_length()   # and full time
	# A goal just before the whistle has its replay first; the stats follow.
	if frame > 1200 and m.state == m.State.FULL_TIME and panel.mode() == "full" and full_seen < 0:
		full_seen = frame
	if full_seen > 0 and frame == full_seen + 10 or frame > 4000:
		ok = ok and panel.mode() == "full"
		_shot("stats_full_time")
		print("stats screen ", "ok" if ok else "FAILED")
		quit(0 if ok else 1)
	return false
