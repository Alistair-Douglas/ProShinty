extends SceneTree
## Plays a match with the TV coverage, forces a goal and checks the GOAL
## graphic, the replay (match held, then resumed) and saves screenshots.
## xvfb-run godot --path . -s tests/tv_test.gd -- <out_dir>
var out := ""
var frame := 0
var m: Node
var ok := true
var saw_replay := false
var clock_at_replay := -1.0
var goal_frame := -1


func _initialize() -> void:
	out = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else ""
	change_scene_to_file("res://scenes/match.tscn")


func _shot(name: String) -> void:
	if out != "":
		root.get_texture().get_image().save_png(out + "/" + name + ".png")
	print("shot ", name)


func _process(_d: float) -> bool:
	frame += 1
	if m == null:
		m = current_scene
		return false
	var view = m.get_node("View")
	var dir = view.director
	match frame:
		150:
			_shot("tv_live")
			print("boards: ", view.get_node("AdBoards").get_child_count())
			ok = ok and view.get_node("AdBoards").get_child_count() > 10
		170:
			# Send the ball flying at the goal for a real goal.
			m.carrier = null
			m.ball_pos = Vector2(122.0, 36.0)
			m.ball_vel = Vector2(45.0, 1.0)
			m.ball_z = 2.4
			m.ball_vz = 0.0
		175:
			_shot("tv_shot")
		240:
			if m.score[0] + m.score[1] == 0:
				print("no natural goal; forcing one")
				m.ball_pos = Vector2(148.0, 37.0)
				m._goal(0)
	if goal_frame < 0 and m.score[0] + m.score[1] > 0:
		goal_frame = frame
		print("goal at frame ", frame)
	if goal_frame > 0 and frame == goal_frame + 6:
		_shot("tv_goal")
	if dir.playing and not saw_replay:
		saw_replay = true
		clock_at_replay = m.clock
		print("replay started at frame ", frame)
	if saw_replay and dir.playing and frame % 12 == 0:
		_shot("tv_replay_%d" % frame)
		if m.clock != clock_at_replay:
			print("FAIL: match clock ran during the replay")
			ok = false
	if saw_replay and not dir.playing and frame > 250:
		print("replay finished at frame ", frame, "; match state ", m.state)
		_shot("tv_after")
		print("PASS" if ok else "FAIL")
		quit(0 if ok else 1)
		return true
	if frame > 1500:
		print("FAIL: no replay (saw_replay=%s)" % saw_replay)
		quit(1)
		return true
	return false
