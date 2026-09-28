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
		_test_no_advantage_in_own_half()
		_test_card_rate()
		_test_swing_into_player()
		_test_late_block_no_foul()
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
	m.referee.chance_cards = false
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
	var aimed := false
	for i in 120:
		m.step(1.0 / 60.0)
		if not aimed and m.carrier == null:
			# Struck: send it straight in, whatever the swing did, so a
			# miss-hit going wide can't make this test flaky.
			aimed = true
			m.ball_vel = (goal - m.ball_pos).normalized() * 30.0
			m.ball_z = 0.3
			m.ball_vz = 0.0
			m.ball_sim.set_spin(Vector3.ZERO)
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
	b.pos = m.target_goal(1) - Vector2(m.attack_dir[1] * 40.0, 0)  # in the opponents' half
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


func _test_no_advantage_in_own_half() -> void:
	print("Foul on a player in their own half")
	var m = _new_match()
	var b = _outfield(m, 1, "CHB")
	b.pos = m.own_goal(1) + Vector2(m.attack_dir[1] * 30.0, 0)
	m.carrier = b
	m.last_team = 1
	m.events.append({"type": "foul", "kind": "hack", "by": _outfield(m, 0, "CHF"), "on": b, "at": b.pos, "severity": 0.3})
	m.referee.step(0.0)
	_check(_last_call(m) == "free hit", "straight to a free hit, no advantage")
	m.free()


func _test_card_rate() -> void:
	print("Cards for ordinary fouls")
	var m = _new_match()
	m.referee.chance_cards = true
	var fouled = _outfield(m, 1, "CHB")
	var yellows := 0
	for i in 200:
		m.referee.fouls = {}
		m.referee.yellows = {}
		var by = null
		for p in m.squads[0]:
			if not p.is_keeper():
				by = p
				break
		if by == null:
			break
		var before: int = m.referee.team_cards(0, "yellow")
		m.events.append({"type": "foul", "kind": "push", "by": by, "on": fouled, "at": Vector2(75, 30), "severity": 0.45})
		m.referee.step(0.0)
		yellows += m.referee.team_cards(0, "yellow") - before
	_check(yellows >= 8 and yellows <= 50, "some pushes in the back are booked, most aren't (%d of 200)" % yellows)
	m.free()


func _test_swing_into_player() -> void:
	print("Swing misses the ball and hits a player")
	var m = _new_match()
	var p = _outfield(m, 0, "CHF")
	var q = _outfield(m, 1, "CHB")
	p.pos = Vector2(60, 30)
	p.facing = Vector2.RIGHT
	q.pos = Vector2(61.2, 30)
	var called := false
	for i in 20:  # the follow-through doesn't always catch them
		m.events.append({"type": "hit", "team": 0, "kind": "fresh_air", "curve": 0.0, "shy": false, "by": p})
		m.referee.step(0.0)
		if m.referee.calls.size() > 0:
			called = true
			break
	_check(called and m.referee.calls[-1]["kind"] == "swing", "foul for swinging into the player")
	var m2 = _new_match()
	p = _outfield(m2, 0, "CHF")
	p.pos = Vector2(60, 30)
	p.facing = Vector2.RIGHT
	for q2 in m2.squads[1]:
		q2.pos = Vector2(100, q2.pos.y)
	for i in 20:
		m2.events.append({"type": "hit", "team": 0, "kind": "fresh_air", "curve": 0.0, "shy": false, "by": p})
		m2.referee.step(0.0)
	_check(m2.referee.calls.is_empty(), "a swing at fresh air with nobody near is fine")
	m.free()
	m2.free()


func _test_late_block_no_foul() -> void:
	print("Late block")
	var m = _new_match()
	var p = _outfield(m, 0, "CHF")
	var q = _outfield(m, 1, "CHB")
	q.pos = p.pos + Vector2(1.0, 0)
	q.block_t = 1.0
	q.counter_age = 0.0
	m.ball_pos = Vector2(q.stick.x, q.stick.y)
	m.Counters.intercept(m, p)
	m.referee.step(0.0)
	var late := false
	for e in m.events:
		if e["type"] == "late_block":
			late = true
	_check(late, "the swing catches the blocker")
	_check(m.referee.calls.is_empty(), "no foul given")
	m.free()
