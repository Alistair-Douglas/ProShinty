extends SceneTree
## Headless tuning aid for ball contact: plays computer-vs-computer matches
## and counts how the ball is met: controlled, knocked down out of the air,
## cleared, off the wood, on the body, and how often an air ball is missed.
## Run: godot --headless --path . -s tests/contact_stats.gd [matches]

const TeamData := preload("res://scripts/team_data.gd")
const MatchScene := preload("res://scenes/match.tscn")

var _done := false


func _process(_delta: float) -> bool:
	if not _done:
		_done = true
		_run()
	return false


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var matches := int(args[0]) if args.size() > 0 else 6
	var teams := TeamData.load_teams()
	var count := {}
	var goals := 0
	var shots := 0
	var swaps := 0
	for i in matches:
		var m = MatchScene.instantiate()
		m.manual_step = true
		m.config = {"home": teams[i % teams.size()], "away": teams[(i + 5) % teams.size()], "human_side": -1,
			"difficulty": 1, "half_seconds": 180.0, "seed": 300 + i}
		root.add_child(m)
		var prev_team := -1
		while m.state != m.State.FULL_TIME:
			m.step(1.0 / 60.0)
			if m.carrier != null:
				if prev_team >= 0 and m.carrier.team != prev_team:
					swaps += 1
				prev_team = m.carrier.team
		for e in m.events:
			var k: String = e["type"]
			if k == "touch":
				k = "touch_body" if e.get("body", false) else ("touch_hands" if e.get("hands", false) else "touch_stick")
			elif k == "stick_rebound":
				k = "stick_rebound_air" if e.get("air", false) else "stick_rebound_ground"
			elif k == "body_stop":
				k = "body_stop_feet" if e.get("feet", false) else "body_stop_air"
			if k in ["touch_body", "touch_hands", "touch_stick", "stick_rebound_air", "stick_rebound_ground",
					"body_stop_feet", "body_stop_air", "air_kill", "block", "save"]:
				count[k] = count.get(k, 0) + 1
			elif k == "hit" and e.get("kind", "") == "clear":
				count["air_clear"] = count.get("air_clear", 0) + 1
		goals += m.score[0] + m.score[1]
		shots += m.shots[0] + m.shots[1]
		m.free()
	print("%d matches: goals %d, shots %d, possession changes %d" % [matches, goals, shots, swaps])
	var keys := count.keys()
	keys.sort()
	for k in keys:
		print("  %-22s %d" % [k, count[k]])
	quit(0)
