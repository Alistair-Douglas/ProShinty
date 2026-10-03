extends SceneTree
## Headless check of the match stats (scripts/match_stats.gd) and the stats
## screen holding the half-time break (scripts/stats_panel.gd).
## Run: godot --headless --path . -s tests/stats_test.gd

const TeamData := preload("res://scripts/team_data.gd")
const MatchScene := preload("res://scenes/match.tscn")
const StatsPanel := preload("res://scripts/stats_panel.gd")

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


func _run() -> void:
	var teams := TeamData.load_teams()
	var m = MatchScene.instantiate()
	m.manual_step = true
	m.config = {"home": teams[0], "away": teams[1], "human_side": -1, "difficulty": 1,
		"half_seconds": 240.0, "extra_time": false, "seed": 11}
	root.add_child(m)
	var panel := StatsPanel.new()
	panel.match_node = m
	root.add_child(panel)
	var s = panel.stats
	var dt := 1.0 / 60.0

	_check(panel.mode() == "", "no stats screen during play")
	m.paused = true
	_check(panel.mode() == "pause", "stats on the pause screen")
	m.paused = false

	# First half, then the break: the screen comes up and holds the break.
	while m.state != m.State.HALF_TIME:
		m.step(dt)
		panel._process(dt)
	_check(panel.mode() == "half", "stats at half time")
	var held := 0.0
	while m.state == m.State.HALF_TIME and held < m.HALF_TIME_PAUSE + 2.0:
		m.step(dt)
		panel._process(dt)
		held += dt
	_check(m.state == m.State.HALF_TIME, "the break waits on the stats screen after the walk off")
	while m.state == m.State.HALF_TIME and held < 60.0:
		m.step(dt)
		panel._process(dt)
		held += dt
	_check(m.state != m.State.HALF_TIME and held < m.HALF_TIME_PAUSE + StatsPanel.AUTO_CONTINUE + 1.0,
		"with nobody playing, the second half starts by itself (%.1f s)" % held)

	while m.state != m.State.FULL_TIME:
		m.step(dt)
		panel._process(dt)
	_check(panel.mode() == "full", "stats at full time")

	var rows: Array = s.rows()
	for r in rows:
		print("  %-18s %4d  %4d" % [r[0], r[1], r[2]])
	for t in 2:
		_check(s.goals(t) == m.score[t], "goals match the score (side %d)" % t)
		_check(s.on_target(t) <= s.shots(t), "shots on target no more than shots (side %d)" % t)
		_check(s.goals(t) <= s.on_target(t), "every goal is a shot on target (side %d)" % t)
		_check(s.shots(t) <= m.shots[t] + s.goals(t), "shots come from the match's own count (side %d)" % t)
		_check(s.passes[t] > 5, "passes are being completed (side %d: %d)" % [t, s.passes[t]])
	_check(s.possession(0) + s.possession(1) == 100, "possession adds up to 100")
	_check(s.possession(0) > 15 and s.possession(0) < 85, "possession is shared (%d%%)" % s.possession(0))
	_check(s.held[0] + s.held[1] > m.half_seconds * 1.5, "possession covers most of the playing time")
	var fh := 0
	for e in m.events:
		if e["type"] == "Free hit":
			fh += 1
	_check(s.free_hits[0] + s.free_hits[1] == fh, "free hits counted")
	_check(s.corners[0] + s.corners[1] + s.bye_hits[0] + s.bye_hits[1] > 0, "restarts counted")
	var labels := rows.map(func(r): return r[0])
	for want in ["Goals", "Shots", "Shots on target", "Possession %", "Passes completed", "Tackles won",
			"Fouls", "Free hits", "Yellow cards", "Red cards", "Saves", "Corners", "Bye-hits"]:
		_check(want in labels, "row: " + want)
