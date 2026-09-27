extends SceneTree
## Headless check: plays computer-vs-computer matches and prints the results.
## Run: godot --headless --path . -s tests/sim_test.gd

const TeamData := preload("res://scripts/team_data.gd")
const MatchScene := preload("res://scenes/match.tscn")


var _done := false


func _process(_delta: float) -> bool:
	if not _done:
		_done = true
		_run()
	return false


func _run() -> void:
	var teams := TeamData.load_teams()
	assert(teams.size() >= 2, "need two teams")
	for t in teams:
		assert(TeamData.starting_twelve(t).size() == 12, "%s needs 12 starters" % t["name"])
	var totals := [0, 0]
	var goals := 0
	var outs := {}
	var ref_calls := {}
	var cards := {"yellow": 0, "red": 0}
	for i in 6:
		var m = MatchScene.instantiate()
		m.manual_step = true
		m.config = {"home": teams[0], "away": teams[1], "human_side": -1, "difficulty": 1, "half_seconds": 180.0, "seed": 100 + i}
		root.add_child(m)
		var steps := 0
		while m.state != m.State.FULL_TIME and steps < 60 * 400:
			m.step(1.0 / 60.0)
			steps += 1
		for e in m.events:
			if e["type"] in ["Shy", "Corner", "Hit-out", "save"]:
				outs[e["type"]] = outs.get(e["type"], 0) + 1
		for c in m.referee.calls:
			var key: String = c["call"] if c["call"] != "missed" else "missed " + c["kind"]
			ref_calls[key] = ref_calls.get(key, 0) + 1
		for c in m.referee.cards:
			cards[c["colour"]] += 1
		print("Match %d: %s %d - %d %s   shots %s  (%d steps, full time: %s)" % [i + 1, teams[0]["name"], m.score[0], m.score[1], teams[1]["name"], str(m.shots), steps, m.state == m.State.FULL_TIME])
		totals[0] += m.score[0]
		totals[1] += m.score[1]
		goals += m.score[0] + m.score[1]
		m.free()
	print("Totals: ", totals, "  restarts/saves: ", outs)
	print("Referee: ", ref_calls, "  cards: ", cards)
	quit(0 if goals > 0 else 1)
