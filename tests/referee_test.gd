extends SceneTree
## Headless checks for the referee's decisions, one staged situation each.
## Run: godot --headless --path . -s tests/referee_test.gd

const TeamData := preload("res://scripts/team_data.gd")
const MatchScene := preload("res://scenes/match.tscn")

var _done := false
var _failures := 0
var _teams: Array


func _process(_delta: float) -> bool:
	if not _done:
		_done = true
		_teams = TeamData.load_teams()
		_test_push_in_back_free_hit()
		_test_foul_in_d_is_penalty()
		_test_shoulder_barge_is_legal()
		_test_second_yellow_sends_off()
		_test_offside()
		_test_no_goal_direct_from_free_hit()
		_test_keeper_hands_outside_d()
		_test_advantage()
		_test_keeper_catch()
		print("Referee tests: %s" % ("all passed" if _failures == 0 else "%d failed" % _failures))
		quit(0 if _failures == 0 else 1)
	return false


func _check(ok: bool, what: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		_failures += 1


## A match in open play, with the ball loose in midfield and nothing moving.
func _new_match():
	var m = MatchScene.instantiate()
	m.manual_step = true
	m.config = {"home": _teams[0], "away": _teams[1], "human_side": -1, "difficulty": 1, "half_seconds": 600.0, "seed": 7}
	root.add_child(m)
	m.referee.always_sees = true
	m.state = m.State.PLAY
	m.ball_pos = m.PITCH / 2.0
	m.ball_vel = Vector2.ZERO
	m.ball_z = 0.0
	m.ball_vz = 0.0
	m.referee.step(0.0)
	return m


func _outfield(m, team: int, code: String):
	for p in m.squads[team]:
		if p.position_code == code:
			return p
	return null


func _last_call(m) -> String:
	return m.referee.calls[-1]["call"] if m.referee.calls.size() > 0 else ""


func _test_push_in_back_free_hit() -> void:
	print("Push in the back in midfield")
	var m = _new_match()
	var a = _outfield(m, 0, "LM")
	var b = _outfield(m, 1, "LM")
	m.events.append({"type": "foul", "kind": "push", "by": a, "on": b, "at": Vector2(60, 30), "severity": 0.3})
	m.referee.step(0.0)
	_check(_last_call(m) == "free hit", "free hit awarded")
	_check(m.carrier != null and m.carrier.team == 1, "fouled team has the ball")
	_check(m.ball_pos.distance_to(Vector2(60, 30)) < 0.1, "taken where the foul happened")
	var closest := 99.0
	m.protected_timer = 2.0
	m._update_players(0.0)
	for o in m.squads[0]:
		closest = min(closest, o.pos.distance_to(m.carrier.pos))
	_check(closest >= 4.9, "opponents stand 5 yards off (%.1f)" % closest)
	m.free()


func _test_foul_in_d_is_penalty() -> void:
	print("Foul inside the D")
	var m = _new_match()
	var def = _outfield(m, 1, "FB")
	var fwd = _outfield(m, 0, "FF")
	var goal: Vector2 = m.target_goal(0)
	var at: Vector2 = goal - Vector2(m.attack_dir[0] * 6.0, 1.0)
	m.events.append({"type": "foul", "kind": "hack", "by": def, "on": fwd, "at": at, "severity": 0.3})
	m.referee.step(0.0)
	_check(_last_call(m) == "penalty", "penalty hit awarded")
	_check(abs(abs(m.ball_pos.x - goal.x) - 20.0) < 0.1 and abs(m.ball_pos.y - goal.y) < 0.1, "ball on the spot 20 yards out")
	var keeper = m._keeper_of(1)
	var ok := true
	for p in m.players:
		if p != m.carrier and p != keeper and (p.pos.x - m.ball_pos.x) * m.attack_dir[0] > -4.9:
			ok = false
	_check(ok, "everyone else is behind the ball")
	# The computer strikes it once players have stood back.
	var struck := false
	for i in 240:
		m.step(1.0 / 60.0)
		for e in m.events:
			if e["type"] == "strike" and e["by"].team == 0:
				struck = true
		if struck:
			break
	_check(struck, "the penalty is struck")
	m.free()


func _test_shoulder_barge_is_legal() -> void:
	print("Shoulder barge")
	var m = _new_match()
	m.events.append({"type": "foul", "kind": "barge", "by": _outfield(m, 0, "LM"), "on": _outfield(m, 1, "LM"), "at": Vector2(70, 30)})
	m.referee.step(0.0)
	_check(m.referee.calls.is_empty(), "play on")
	m.free()


func _test_second_yellow_sends_off() -> void:
	print("Two bad fouls by one player")
	var m = _new_match()
	var a = _outfield(m, 0, "CHB")
	var b = _outfield(m, 1, "CHF")
	for i in 2:
		m.events.append({"type": "foul", "kind": "stick", "by": a, "on": b, "at": Vector2(50, 40), "severity": 0.9})
		m.referee.step(0.0)
	_check(m.referee.team_cards(0, "red") == 1, "red card after a second yellow")
	_check(not (a in m.players) and m.squads[0].size() == 11, "sent off and not replaced")
	m.free()


func _test_offside() -> void:
	print("Offside")
	var m = _new_match()
	var goal: Vector2 = m.target_goal(0)
	var passer = _outfield(m, 0, "CHF")
	var fwd = _outfield(m, 0, "FF")
	fwd.pos = goal - Vector2(m.attack_dir[0] * 5.0, 0)
	passer.pos = goal - Vector2(m.attack_dir[0] * 30.0, 0)
	m.carrier = passer
	m.ball_pos = passer.pos
	m.events.append({"type": "strike", "by": passer, "at": passer.pos})  # the pass
	m.referee.step(0.0)
	m.events.append({"type": "touch", "by": fwd, "at": fwd.pos, "hands": false})
	m.referee.step(0.0)
	_check(_last_call(m) == "offside", "offside given")
	_check(m.carrier != null and m.carrier.team == 1, "free hit to the defenders")
	# Onside: the same forward outside the D when the ball is played.
	var m2 = _new_match()
	fwd = _outfield(m2, 0, "FF")
	passer = _outfield(m2, 0, "CHF")
	fwd.pos = goal - Vector2(m2.attack_dir[0] * 14.0, 0)
	passer.pos = goal - Vector2(m2.attack_dir[0] * 30.0, 0)
	m2.carrier = passer
	m2.ball_pos = passer.pos
	m2.events.append({"type": "strike", "by": passer, "at": passer.pos})  # the pass
	m2.referee.step(0.0)
	m2.events.append({"type": "touch", "by": fwd, "at": goal - Vector2(m2.attack_dir[0] * 5.0, 0), "hands": false})
	m2.referee.step(0.0)
	_check(m2.referee.calls.is_empty(), "onside run into the D is fine")
	m.free()
	m2.free()


func _test_no_goal_direct_from_free_hit() -> void:
	print("Goal straight from a free hit")
	var m = _new_match()
	var goal: Vector2 = m.target_goal(0)
	var spot: Vector2 = goal - Vector2(m.attack_dir[0] * 25.0, 0)
	m.events.append({"type": "foul", "kind": "hack", "by": _outfield(m, 1, "CHB"), "on": _outfield(m, 0, "CHF"), "at": spot, "severity": 0.3})
	m.referee.step(0.0)
	var taker = m.carrier
	var keeper = m._keeper_of(1)
	m.squads[1].erase(keeper)  # nobody to save it
	m.players.erase(keeper)
	for p in m.players:
		if p != taker:
			p.pos = Vector2(m.PITCH.x / 2.0, p.pos.y)  # and nobody in the way
	m._strike_speed(taker, (goal - m.ball_pos).normalized(), 30.0, 0.3, "shooting")
	for i in 120:
		m.step(1.0 / 60.0)
		if m.state != m.State.PLAY:
			break
	_check(m.score[0] == 0, "no goal given")
	_check(m.referee.calls[-1]["kind"] == "direct from a free hit", "disallowed as direct from a free hit")
	m.free()


func _test_keeper_hands_outside_d() -> void:
	print("Keeper handles outside the D")
	var m = _new_match()
	var k = m._keeper_of(1)
	var at: Vector2 = m.own_goal(1) - Vector2(m.attack_dir[1] * -13.0, 0)
	m.events.append({"type": "touch", "by": k, "at": at, "hands": true})
	m.referee.step(0.0)
	_check(_last_call(m) == "free hit", "free hit against the keeper")
	var m2 = _new_match()
	k = m2._keeper_of(1)
	m2.events.append({"type": "touch", "by": k, "at": m2.own_goal(1) - Vector2(m2.attack_dir[1] * -4.0, 0), "hands": true})
	m2.referee.step(0.0)
	_check(m2.referee.calls.is_empty(), "hands inside the D are fine")
	m.free()
	m2.free()


func _test_advantage() -> void:
	print("Advantage")
	var m = _new_match()
	var b = _outfield(m, 1, "LM")
	m.carrier = b
	m.last_team = 1
	m.events.append({"type": "foul", "kind": "hack", "by": _outfield(m, 0, "LM"), "on": b, "at": b.pos, "severity": 0.3})
	m.referee.step(0.0)
	_check(_last_call(m) == "advantage", "advantage played while the fouled team keeps the ball")
	m.carrier = _outfield(m, 0, "RM")
	m.last_team = 0
	m.referee.step(0.1)
	_check(_last_call(m) == "free hit", "brought back when the ball is lost")
	_check(m.carrier.team == 1, "fouled team gets the free hit")
	m.free()


func _test_keeper_catch() -> void:
	print("Keeper catches the ball")
	var m = _new_match()
	var k = m._keeper_of(1)
	var at: Vector2 = m.own_goal(1) - Vector2(m.attack_dir[1] * -3.0, 0)
	m.carrier = k
	m.events.append({"type": "touch", "by": k, "at": at, "hands": true})
	m.referee.step(0.0)
	_check(_last_call(m) == "penalty", "a catch in the D is a penalty hit")
	# A save that drops the ball at the keeper's feet, gathered with the caman.
	var m2 = _new_match()
	k = m2._keeper_of(1)
	m2.events.append({"type": "touch", "by": k, "at": at, "hands": true})
	m2.events.append({"type": "save", "team": 1, "by": k})
	m2.referee.step(0.0)
	m2.carrier = k
	m2.referee.step(0.1)
	_check(m2.referee.calls.is_empty(), "a deflected save is fine")
	m.free()
	m2.free()
