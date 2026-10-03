extends SceneTree
## Plays a match with the TV coverage, forces a foul and checks the foul
## replay: it starts after the whistle with the match held, shows the foul
## caption, and one press of Enter (ui_accept) skips straight back to the
## free hit.
## xvfb-run godot --path . -s tests/foul_replay_test.gd -- <out_dir>
var out := ""
var frame := 0
var m: Node
var ok := true
var foul_frame := -1
var replay_frame := -1
var skip_frame := -1
var clock_at_replay := -1.0


func _initialize() -> void:
	out = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else ""
	change_scene_to_file("res://scenes/match.tscn")


func _shot(name: String) -> void:
	if out != "" and DisplayServer.get_name() != "headless":
		root.get_texture().get_image().save_png(out + "/" + name + ".png")
	print("shot ", name)


func _check(cond: bool, what: String) -> void:
	if not cond:
		print("FAIL: ", what)
		ok = false


func _process(_d: float) -> bool:
	frame += 1
	if m == null:
		m = current_scene
		return false
	var dir = m.get_node("View").director
	var gfx = dir.graphics
	if foul_frame < 0 and frame >= 200 and m.state == m.State.PLAY and not dir.playing and m.set_piece == "":
		# A push in the back by a home player, with no-one on the ball so the
		# referee can't play advantage.
		m.referee.always_sees = true
		m.referee.chance_cards = false
		m.carrier = null
		var by = null
		var on = null
		for p in m.players:
			if p.is_keeper():
				continue
			if p.team == 0 and by == null:
				by = p
			elif p.team == 1 and on == null:
				on = p
		var at: Vector2 = m.PITCH / 2.0 + Vector2(-10.0, 4.0)
		m.events.append({"type": "foul", "kind": "push", "by": by, "on": on, "at": at, "severity": 0.3})
		foul_frame = frame
	if foul_frame > 0 and frame > foul_frame and replay_frame < 0 and dir.playing:
		replay_frame = frame
		clock_at_replay = m.clock
		print("foul replay started %d frames after the foul (state %s)" % [frame - foul_frame, m.state])
		_check(dir.kind == "foul", "replay kind is '%s', not foul" % dir.kind)
		_check(m.set_piece == "Free hit", "no free hit awarded (set piece '%s')" % m.set_piece)
		_check(gfx == null or gfx.replay_caption.begins_with("FOUL"), "no foul caption")
	if replay_frame > 0 and frame == replay_frame + 40:
		_shot("foul_replay")
		_check(dir.playing, "replay ended before the skip")
		_check(m.clock == clock_at_replay, "match clock ran during the replay")
		Input.action_press("ui_accept")
		skip_frame = frame
	if skip_frame > 0 and frame == skip_frame + 1:
		Input.action_release("ui_accept")
	if skip_frame > 0 and frame == skip_frame + 60:
		_check(not dir.playing, "replay did not stop after the skip")
		_check(m.process_mode != Node.PROCESS_MODE_DISABLED, "match still held after the skip")
		_shot("foul_after")
		print("PASS" if ok else "FAIL")
		quit(0 if ok else 1)
		return true
	if frame > 900:
		print("FAIL: no foul replay (foul frame %d, replay frame %d)" % [foul_frame, replay_frame])
		quit(1)
		return true
	return false
