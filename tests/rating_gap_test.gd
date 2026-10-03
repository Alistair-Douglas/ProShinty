extends SceneTree
## Headless check: a top Premiership side should beat a bottom-division side
## most of the time. Run: godot --headless --path . -s tests/rating_gap_test.gd

const TeamData := preload("res://scripts/team_data.gd")
const MatchScene := preload("res://scenes/match.tscn")

const MATCHES := 6


var _done := false


func _process(_delta: float) -> bool:
	if not _done:
		_done = true
		_run()
	return false


func _team(teams: Array, id: String) -> Dictionary:
	for t in teams:
		if t["id"] == id:
			return t
	return {}


func _run() -> void:
	var teams := TeamData.load_teams()
	var top := _team(teams, "kingussie")
	var bottom := _team(teams, "uddingston")
	assert(not top.is_empty() and not bottom.is_empty(), "need Kingussie and Uddingston")
	print("%s OVR %d   %s OVR %d" % [top["name"], top["overall"], bottom["name"], bottom["overall"]])
	var wins := 0
	var losses := 0
	var goals := [0, 0]
	for i in MATCHES:
		# Swap ends every other match so home advantage doesn't decide it.
		var flip := i % 2 == 1
		var m = MatchScene.instantiate()
		m.manual_step = true
		m.config = {"home": bottom if flip else top, "away": top if flip else bottom, "human_side": -1, "difficulty": 1, "half_seconds": 180.0, "seed": 500 + i}
		root.add_child(m)
		var steps := 0
		while m.state != m.State.FULL_TIME and steps < 60 * 600:
			m.step(1.0 / 60.0)
			steps += 1
		var t_goals: int = m.score[1 if flip else 0]
		var b_goals: int = m.score[0 if flip else 1]
		goals[0] += t_goals
		goals[1] += b_goals
		if t_goals > b_goals:
			wins += 1
		elif t_goals < b_goals:
			losses += 1
		print("Match %d: %s %d - %d %s" % [i + 1, top["name"], t_goals, b_goals, bottom["name"]])
		m.free()
	print("%s won %d, lost %d of %d; goals %d - %d" % [top["name"], wins, losses, MATCHES, goals[0], goals[1]])
	if wins <= losses or goals[0] <= goals[1]:
		push_error("the stronger side should come out on top")
		quit(1)
		return
	print("RATING GAP OK")
	quit()
