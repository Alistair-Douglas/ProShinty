extends SceneTree
## Headless tuning aid for the team AI: plays ten computer-vs-computer matches
## and prints how often hits reach a team-mate, goals, shots and restarts.
## Run: godot --headless --path . -s tests/ai_stats.gd

const TeamData := preload("res://scripts/team_data.gd")
const MatchScene := preload("res://scenes/match.tscn")
const MATCHES := 10


var _done := false


func _process(_delta: float) -> bool:
	if not _done:
		_done = true
		_run()
	return false


func _run() -> void:
	var teams := TeamData.load_teams()
	var goals := 0
	var shots := 0
	var reached := 0
	var missed := 0
	var spread := 0.0
	var samples := 0
	var outs := {}
	for i in MATCHES:
		var m = MatchScene.instantiate()
		m.manual_step = true
		m.config = {"home": teams[0], "away": teams[1], "human_side": -1, "difficulty": 1, "half_seconds": 180.0, "seed": 100 + i}
		root.add_child(m)
		var prev = null
		var hit_by := -1
		while m.state != m.State.FULL_TIME:
			m.step(1.0 / 60.0)
			if prev != null and m.carrier == null and m.ball_vel.length() >= 9.0:
				hit_by = prev.team
			if m.carrier != null:
				if hit_by >= 0:
					if m.carrier.team == hit_by:
						reached += 1
					else:
						missed += 1
					hit_by = -1
				# How spread out the team on the ball is around the carrier.
				var total := 0.0
				for q in m.squads[m.carrier.team]:
					total += q.pos.distance_to(m.carrier.pos)
				spread += total / 12.0
				samples += 1
			prev = m.carrier
		for e in m.events:
			if e["type"] in ["Shy", "Corner", "Hit-out"]:
				outs[e["type"]] = outs.get(e["type"], 0) + 1
		goals += m.score[0] + m.score[1]
		shots += m.shots[0] + m.shots[1]
		m.free()
	print("Hits reaching a team-mate: %d of %d (%.0f%%)" % [reached, reached + missed, 100.0 * reached / max(1, reached + missed)])
	print("Goals %d, shots %d, average distance from carrier %.1f yd, restarts %s" % [goals, shots, spread / max(1, samples), outs])
	quit(0)
