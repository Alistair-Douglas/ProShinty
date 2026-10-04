extends SceneTree
## Checks the spectators and goal judges: every ground gets a crowd (thinner
## on Low graphics), and the judges raise the flag for a ball wide, point to
## the right corner for a corner and wave for a goal.
## godot --headless --fixed-fps 60 --path . -s tests/crowd_test.gd
## With a display and an output folder it also saves screenshots:
## xvfb-run godot --fixed-fps 60 --path . -s tests/crowd_test.gd -- <out_dir>

var out := ""
var frame := 0
var m: Node
var ok := true
var step := 0
var wait := 0
var _close: Camera3D


## A camera near a judge (and a stretch of crowd) for the next screenshot.
func _close_up(view: Node3D, end: int) -> void:
	if out == "":
		return
	var j: Node3D = view.goal_judges.judges[end]["f"]["root"]
	_close = Camera3D.new()
	view.add_child(_close)
	var sgn := -1.0 if end == 0 else 1.0
	_close.position = j.position + Vector3(-sgn * 9.0, 3.0, 5.0)
	_close.look_at(j.position + Vector3(0, 1.0, -3.0))
	_close.fov = 50.0
	_close.make_current()


func _initialize() -> void:
	out = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else ""



func _check(cond: bool, what: String) -> void:
	print(("ok   " if cond else "FAIL ") + what)
	ok = ok and cond


func _check_grounds() -> void:
	var colors := [[Color.RED, Color.WHITE], [Color.BLUE, Color.YELLOW]]
	for v in ShintyPitch.VENUE_NAMES.size():
		var pitch := ShintyPitch.new()
		pitch.venue = v
		pitch.include_environment = false
		root.add_child(pitch)
		var counts := []
		for q in 3:
			var crowd := ShintyCrowd.new()
			root.add_child(crowd)
			crowd.build(pitch, colors, q)
			counts.append(crowd.count)
			crowd.free()
		print("%s: crowd Low/Medium/High %s" % [ShintyPitch.VENUE_NAMES[v], counts])
		# Tighnabruaich's small ground holds about 55 on Low once the dugouts are kept clear.
		_check(counts[0] > 45 and counts[0] < counts[1] and counts[1] < counts[2] and counts[2] < 1500,
			"%s crowd size scales with graphics" % ShintyPitch.VENUE_NAMES[v])
		pitch.free()


func _shot(name: String) -> void:
	if out != "":
		if _close != null:
			_close.queue_free()
			_close = null
		root.get_texture().get_image().save_png(out + "/" + name + ".png")
		print("shot ", name)


## Hand height above the shoulder for a judge's arm, in the model's metres.
func _hand_rise(j: ShintyGoalJudges, end: int, side: String) -> float:
	var skel: Skeleton3D = j.judges[end]["f"]["model"].find_child("Skeleton3D", true, false)
	var hand := skel.get_bone_global_pose(skel.find_bone(side + "Hand")).origin
	var sh := skel.get_bone_global_pose(skel.find_bone(side + "UpperArm")).origin
	return hand.y - sh.y


func _process(_d: float) -> bool:
	frame += 1
	if frame == 1:
		# The pitch builds itself on entering the tree, so wait for a frame.
		_check_grounds()
		change_scene_to_file("res://scenes/match.tscn")
		return false
	if m == null:
		m = current_scene
		return false
	var view = m.get_node("View")
	var j: ShintyGoalJudges = view.goal_judges
	if frame < 30:
		return false
	if wait > 0:
		wait -= 1
		return false
	match step:
		0:
			_check(view.crowd.count > 60, "match has a crowd (%d)" % view.crowd.count)
			_check(j.signal_at(0) == ShintyGoalJudges.Call.NONE and j.signal_at(1) == ShintyGoalJudges.Call.NONE,
				"judges start with flags down")
			_check(_hand_rise(j, 0, "Right") < -0.3, "flag arm hangs down at rest")
			# Wide at the east end: a hit-out.
			m._restart(1, Vector2(m.PITCH.x - m.D_RADIUS, m.PITCH.y / 2.0), "Hit-out")
			wait = 30
		1:
			_check(j.signal_at(1) == ShintyGoalJudges.Call.RAISE, "east judge raises the flag for a wide")
			_check(j.signal_at(0) == ShintyGoalJudges.Call.NONE, "west judge stays still")
			_check(_hand_rise(j, 1, "Right") > 0.3, "flag held up (%.2f)" % _hand_rise(j, 1, "Right"))
			_shot("judge_wide")
			_close_up(view, 0)
			# Corner at the west end, near side (+z, the judge's right).
			m._restart(1, Vector2(1.0, m.PITCH.y - 1.0), "Corner")
			wait = 80
		2:
			_check(j.signal_at(0) == ShintyGoalJudges.Call.CORNER, "west judge signals the corner")
			var side := "Right" if j.corner_side(0) > 0.0 else "Left"
			_check(side == "Right", "points with the arm on the near corner's side")
			var rise := _hand_rise(j, 0, side)
			_check(rise > -0.25 and rise < 0.3, "arm points out along the goal line (%.2f)" % rise)
			_shot("judge_corner")
			_close_up(view, 1)
			# Far-side corner at the east end: the other arm.
			m._restart(0, Vector2(m.PITCH.x - 1.0, 1.0), "Corner")
			wait = 80
		3:
			_check(j.signal_at(1) == ShintyGoalJudges.Call.CORNER, "east judge signals the far corner")
			var side := "Right" if j.corner_side(1) > 0.0 else "Left"
			# East judge faces west: the far (-z) corner is on the right.
			_check(side == "Right", "east judge points to the far corner with the right arm")
			_shot("judge_corner_far")
			m.ball_pos = Vector2(m.PITCH.x - 0.5, m.PITCH.y / 2.0)
			m._goal(0)
			if out != "":
				# Look at the far-side crowd celebrating.
				_close = Camera3D.new()
				view.add_child(_close)
				_close.position = Vector3(-20.0, 4.0, -m.PITCH.y / 2.0 + 12.0)
				_close.look_at(Vector3(-8.0, 1.0, -m.PITCH.y / 2.0 - 6.0))
				_close.fov = 50.0
				_close.make_current()
			wait = 20
		4:
			var end := 0 if m.own_goal(1).x < m.PITCH.x / 2.0 else 1
			_check(j.signal_at(end) == ShintyGoalJudges.Call.GOAL, "judge waves for a goal")
			_check(view.crowd.material.get_shader_parameter("cheer_home") > 0.5, "home fans cheer")
			_shot("crowd_goal")
			print("PASS" if ok else "FAIL")
			quit(0 if ok else 1)
			return true
	step += 1
	if frame > 3000:
		quit(1)
		return true
	return false
