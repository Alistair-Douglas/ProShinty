extends SceneTree
## Headless check of substitutions: benches, the three-change limit, no
## re-entry, changes waiting for a dead ball, and the computer's own changes.
## Run: godot --headless --path . -s tests/subs_test.gd

const TeamData := preload("res://scripts/team_data.gd")
const MatchScene := preload("res://scenes/match.tscn")

var _done := false
var _fails := 0


func _process(_delta: float) -> bool:
	if not _done:
		_done = true
		_run()
		quit(1 if _fails > 0 else 0)
	return false


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		printerr("FAIL: ", what)
	else:
		print("ok: ", what)


func _match(teams: Array, human: int, seed_: int):
	var m = MatchScene.instantiate()
	m.manual_step = true
	m.config = {"home": teams[0], "away": teams[1], "human_side": human, "difficulty": 1, "half_seconds": 180.0, "seed": seed_}
	root.add_child(m)
	return m


func _run() -> void:
	var teams := TeamData.load_teams()
	_check(teams.all(func(t): return t["players"].size() >= 17), "every team has a bench of five")

	# A change you ask for in open play waits for the ball to go dead.
	var m = _match(teams, 0, 7)
	var s = m.subs
	_check(s.bench[0].size() == 5 and s.bench[1].size() == 5, "both benches have five")
	while m.state != m.State.PLAY or s.ball_dead():
		m.step(1.0 / 60.0)
	var off = null
	for p in m.squads[0]:
		if p != m.carrier and not p.is_keeper():
			off = p
			break
	var on: Dictionary = s.best_replacement(off)
	_check(on != null and TeamData.role_of(on["position"]) == off.role, "a replacement of the same kind is found")
	_check(s.request(off, on) == "", "the change is accepted")
	_check(s.request(off, s.bench[0][0]) != "", "a player can't be taken off twice")
	var waited := false
	var steps := 0
	while s.used[0] == 0 and steps < 60 * 400:
		if not s.ball_dead():
			waited = true
		m.step(1.0 / 60.0)
		steps += 1
	_check(s.used[0] == 1, "the change was made at a dead ball")
	_check(waited, "it waited for play to stop")
	_check(not off in m.players and off in s.leaving, "the player going off leaves the pitch and walks to the bench")
	_check(m.squads[0].size() == 12, "still twelve on the pitch")
	var sub = m.squads[0].filter(func(p): return p.data == on)
	_check(sub.size() == 1 and sub[0].position_code == off.position_code, "the substitute takes the same position")
	_check(not on in s.bench[0], "the substitute left the bench")
	_check(not off.data in s.bench[0], "no re-entry: the player off isn't back on the bench")
	# Use the other two, then the limit.
	for i in 2:
		var o2 = m.squads[0][2 + i]
		_check(s.request(o2, s.bench[0][i]) == "", "change %d accepted" % (i + 2))
	_check(s.subs_left(0) == 0, "three changes used up")
	_check(s.request(m.squads[0][6], s.bench[0][3]) == "No substitutions left", "a fourth change is refused")
	m.free()

	# Computer against computer: both sides use their changes sensibly.
	var total := 0
	var injuries := 0
	for i in 4:
		m = _match(teams, -1, 200 + i)
		s = m.subs
		steps = 0
		while m.state != m.State.FULL_TIME and steps < 60 * 600:
			m.step(1.0 / 60.0)
			steps += 1
		for e in m.events:
			if e["type"] == "injury":
				injuries += 1
		print("Match %d: %s %d - %d %s  subs %s  %s" % [i + 1, teams[0]["name"], m.score[0], m.score[1], teams[1]["name"], str(s.used),
			", ".join(s.made.map(func(r): return "%d' %s on for %s" % [r["minute"], r["on"]["name"], r["off"]["name"]]))])
		for t in 2:
			_check(s.used[t] <= s.MAX_SUBS, "match %d side %d kept to the limit" % [i + 1, t])
			_check(m.squads[t].size() <= 12, "match %d side %d has at most twelve" % [i + 1, t])
			var offs := {}
			for r in s.made:
				if r["team"] == t:
					_check(not offs.has(r["on"]), "no re-entry: nobody who came off goes back on")
					_check(not offs.has(r["off"]), "nobody comes off twice")
					offs[r["off"]] = true
		total += s.used[0] + s.used[1]
		m.free()
	print("Computer changes in 4 matches: %d, injuries: %d" % [total, injuries])
	_check(total >= 4, "the computer makes changes")
	print("Substitution tests: %s" % ("FAILED" if _fails > 0 else "passed"))
