extends SceneTree
## Headless check of the training ground: every move in the list plays, fed
## balls reach the player, set pieces and runs work, shots score or come back.
## Run: godot --headless --path . -s tests/practice_test.gd

const TeamData := preload("res://scripts/team_data.gd")
const PracticeScene := preload("res://scenes/practice.tscn")
const DT := 1.0 / 60.0

var _done := false


func _process(_delta: float) -> bool:
	if not _done:
		_done = true
		_run()
	return false


func _steps(m, seconds: float) -> void:
	for i in int(seconds / DT):
		m.step(DT)


## The pose editor's tweaks change the model and the match's timing, and save.
func _pose_tweaks(teams: Array) -> void:
	ShintyPoseTweaks.res_path = "user://test_poses_res.json"
	ShintyPoseTweaks.user_path = "user://test_poses_user.json"
	ShintyPoseTweaks.data = {}
	var swing_at := func(t: float) -> Vector3:
		var p := ShintyPlayerModel.new()
		p.manual_update = true
		root.add_child(p)
		p.setup(teams[0]["players"][10], teams[0])
		p.play_action(&"swing", 1.0)
		var steps := int(t * 60.0)
		for i in steps:
			p.advance(1.0 / 60.0)
		var head := p.get_caman_head_position()
		p.free()
		return head
	var top: float = ShintyPlayerModel.contact_delay("swing", 1.0) * 0.5   # up in the backswing
	var before: Vector3 = swing_at.call(top)
	var delay_before := ShintyPlayerModel.contact_delay("swing", 1.0)
	ShintyPoseTweaks.set_value("swing", 0, "caman_up", 30.0)
	ShintyPoseTweaks.set_value("swing", 0, "spine_bend", 20.0)
	ShintyPoseTweaks.set_length("swing", 1.5)
	var after: Vector3 = swing_at.call(top * 1.5)
	print("swing head at the top: %s, tweaked %s" % [before, after])
	assert(after.distance_to(before) > 0.1, "a tweak moves the caman")
	assert(absf(ShintyPlayerModel.contact_delay("swing", 1.0) - delay_before * 1.5) < 0.01, "length changes the match's contact time")
	# The hands move along the shaft.
	ShintyPoseTweaks.reset("swing")
	var hands := func() -> float:
		var p := ShintyPlayerModel.new()
		p.manual_update = true
		root.add_child(p)
		p.setup(teams[0]["players"][10], teams[0])
		p.play_action(&"pass", 1.0)
		for i in 15:
			p.advance(1.0 / 60.0)
		var sk: Skeleton3D = p.find_children("*", "Skeleton3D", true, false)[0]
		var l := sk.get_bone_global_pose(sk.find_bone("LeftHand")).origin
		var r := sk.get_bone_global_pose(sk.find_bone("RightHand")).origin
		p.free()
		return l.distance_to(r)
	var gap_before: float = hands.call()
	ShintyPoseTweaks.set_value("pass", 1, "low_grip", 25.0)
	ShintyPoseTweaks.set_value("pass", 0, "low_grip", 25.0)
	var gap_after: float = hands.call()
	print("hands apart on a pass: %.2f m, lower hand moved down %.2f m" % [gap_before, gap_after])
	assert(gap_after > gap_before + 0.1, "the lower hand slides down the shaft")
	ShintyPoseTweaks.reset("pass")
	ShintyPoseTweaks.set_value("swing", 0, "caman_up", 30.0)
	var path := ShintyPoseTweaks.save()
	assert(path != "", "tweaks saved")
	ShintyPoseTweaks.data = {}
	ShintyPoseTweaks.ensure_loaded(true)
	assert(ShintyPoseTweaks.get_value("swing", 0, "caman_up") == 30.0, "tweaks load back")
	ShintyPoseTweaks.reset("swing")
	assert(ShintyPoseTweaks.length_scale("swing") == 1.0, "reset")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ShintyPoseTweaks.res_path))
	print("pose tweaks ok (saved to %s)" % path)


func _run() -> void:
	var teams := TeamData.load_teams()
	var m = PracticeScene.instantiate()
	m.manual_step = true
	m.config = {"home": teams[0], "away": teams[1], "human_side": 0, "difficulty": 1, "seed": 7}
	root.add_child(m)

	assert(m.players.size() == 2, "you and the keeper")
	assert(m.carrier == m.human, "the ball starts at your feet")
	assert(m.state == m.State.PLAY)

	# Every move in the list plays without an error.
	for i in m.MOVES.size():
		m.reset_ball()
		var seq: int = m.human.anim_seq
		m.play_move(i)
		var kind: String = m.MOVES[i][1]
		if kind == "pose":
			assert(m.human.anim_seq == seq + 1, "%s played" % m.MOVES[i][0])
		_steps(m, 2.0)
	print("all %d moves played" % m.MOVES.size())

	# Fed balls reach the player and are dealt with.
	for kind in ["ground", "bounce", "high", "chest", "drive"]:
		var reached := 0
		var won := 0
		for n in 10:
			m.reset_ball()
			m.human.facing = Vector2(1, 0).rotated(randf_range(-0.6, 0.6))
			m.feed(kind)
			var closest := INF
			var got := false
			for s in 180:
				m.step(DT)
				closest = min(closest, m.ball_pos.distance_to(m.human.pos))
				got = got or m.carrier == m.human
			if closest < 2.0:
				reached += 1
			if got:
				won += 1
		print("feed %-7s reached %d/10  under control %d/10" % [kind, reached, won])
		assert(reached >= 8, "a %s feed should reach the player" % kind)

	# Shots from the reset spot: a goal, a save or a miss, then the ball comes back.
	var goals_before: int = m.goals
	var back := 0
	for n in 10:
		m.reset_ball()
		m._human_shoot(m.human, Vector2.ZERO, 0.8)
		_steps(m, 7.0)
		if m.carrier == m.human and m.state == m.State.PLAY:
			back += 1
		else:
			print("  after shot: ball %s z %.1f vel %.1f carrier %s keeper %s msg %s" % [m.ball_pos, m.ball_z, m.ball_vel.length(), m.carrier.role if m.carrier else "-", m.practice_keeper.pos, m.message])
	print("shots: %d goals in 10, ball back %d times" % [m.goals - goals_before, back])
	assert(back >= 8, "the ball should come back after a shot")

	# Set pieces: you stand over the ball.
	for kind in ["Shy", "Free hit", "Penalty hit", "Corner"]:
		m._set_piece_drill(kind)
		_steps(m, 0.2)
		var ok: bool = m.carrier == m.human and (m.human.shy_ready if kind == "Shy" else m.set_piece_taker == m.human)
		print("%s: taker ready %s" % [kind, ok])
		assert(ok, kind + " set up")
		m._human_hit(m.human, m.human.facing, 0.6)
		_steps(m, 4.0)

	# Running a circle on its own, at each pace.
	for pace in ["walk", "jog", "sprint"]:
		m.reset_ball()
		m.play_move(m.MOVES.map(func(mv): return mv[2]).find(pace))
		_steps(m, 4.0)
		var r: float = m.human.pos.distance_to(m.circle_centre)
		var v: float = m.human.vel.length()
		print("circle %-6s radius %.1f speed %.1f yd/s" % [pace, r, v])
		assert(abs(r - 10.0) < 2.5, "stays on the circle")
		assert(v > 1.0, "keeps moving")

	# A defender comes on and closes you down.
	m.set_defender(true)
	m.reset_ball()
	assert(m.players.size() == 3)
	var gap0: float = m.practice_defender.pos.distance_to(m.human.pos)
	_steps(m, 1.0)
	assert(m.practice_defender.pos.distance_to(m.human.pos) < gap0, "defender closes in")
	_steps(m, 8.0)
	m.set_defender(false)
	m.set_keeper(false)
	assert(m.players.size() == 1)
	m.reset_ball()
	m._human_shoot(m.human, Vector2.ZERO, 0.6)
	_steps(m, 5.0)
	print("open goal: goals %d" % m.goals)

	# Over the touchline comes straight back.
	m.carrier = null
	m.ball_pos = Vector2(70, -1)
	m.step(DT)
	assert(m.carrier == m.human, "ball back after going out")

	m.set_speed(2)
	assert(Engine.time_scale == 0.25)
	m.set_speed(0)

	_pose_tweaks(teams)
	print("practice test passed")
	quit(0)
