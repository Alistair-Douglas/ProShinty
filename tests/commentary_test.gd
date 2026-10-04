extends SceneTree
## Headless check of the match commentary: the lines file is sound (every
## category the commentator uses has lines, none repeats, none says "hail"),
## a computer-vs-computer match gets a line for every goal and for the
## breaks, and a recording dropped into user://commentary is spoken.
## Run: godot --headless --path . -s tests/commentary_test.gd

const TeamData := preload("res://scripts/team_data.gd")
const MatchScene := preload("res://scenes/match.tscn")

var _done := false


func _process(_delta: float) -> bool:
	if not _done:
		_done = true
		_run()
	return false


func _run() -> void:
	var ok := _check_lines()
	ok = _check_voice() and ok
	ok = _check_match() and ok
	print("Commentary test: %s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)


func _check_lines() -> bool:
	var ok := true
	var lines := ShintyCommentary.load_lines()
	var total := 0
	var seen := {}
	for cat in ShintyCommentary.PRIORITY:
		var pool: Array = lines.get(cat, [])
		if pool.size() < 5:
			push_error("commentary category %s has %d lines; want at least 5" % [cat, pool.size()])
			ok = false
	for cat in lines:
		if not ShintyCommentary.PRIORITY.has(cat):
			push_error("commentary category %s is never used" % cat)
			ok = false
		for text in lines[cat]:
			total += 1
			var t: String = text
			if "hail" in t.to_lower():
				push_error("say goal, not hail: %s" % t)
				ok = false
			if t.length() > 80:
				push_error("line too long for a caption: %s" % t)
				ok = false
			if seen.has(t):
				push_error("line used twice (%s and %s): %s" % [seen[t], cat, t])
				ok = false
			seen[t] = cat
	print("Commentary lines: %d in %d categories" % [total, lines.size()])
	if total < 300:
		push_error("expected a few hundred lines, got %d" % total)
		ok = false
	return ok


## A loose recording in user://commentary is picked up for its line.
func _check_voice() -> bool:
	var c := ShintyCommentary.new()
	root.add_child(c)
	DirAccess.make_dir_recursive_absolute("user://commentary")
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 22050
	var data := PackedByteArray()
	data.resize(22050)   # half a second of silence
	wav.data = data
	var ids: Array = []
	for i in c.lines["goal"].size():
		ids.append(ShintyCommentary.line_id_for("goal", i))
	for id in ids:
		wav.save_to_wav("user://commentary/%s.wav" % id)
	var ok := c.say("goal")
	ok = ok and c.said[-1]["voiced"] and c.player.playing
	if not ok:
		push_error("a recorded line should be spoken: %s" % str(c.said))
	# a filler can't talk over a goal
	if c.say("filler"):
		push_error("a filler line cut in on a goal")
		ok = false
	# the final whistle is called even straight after a shootout kick
	c._t += 30.0
	c.say("shootout_miss")
	if not c.say("full_time"):
		push_error("full time should cut in on a shootout kick")
		ok = false
	for id in ids:
		DirAccess.remove_absolute("user://commentary/%s.wav" % id)
	c.free()
	return ok


func _check_match() -> bool:
	var ok := true
	var teams := TeamData.load_teams()
	var m = MatchScene.instantiate()
	m.manual_step = true
	m.config = {"home": teams[0], "away": teams[1], "human_side": -1, "difficulty": 1, "half_seconds": 180.0, "seed": 202}
	root.add_child(m)
	var c := ShintyCommentary.new()
	c.m = m
	root.add_child(c)
	var steps := 0
	while m.state != m.State.FULL_TIME and steps < 60 * 900:
		m.step(1.0 / 60.0)
		c._process(1.0 / 60.0)
		steps += 1
	for i in 60:
		c._process(1.0 / 60.0)
	var goals := 0
	var breaks := 0
	for e in m.events:
		goals += 1 if e["type"] == "goal" else 0
		breaks += 1 if e["type"] == "half_end" else 0
	var cats := {}
	for s in c.said:
		cats[s["cat"]] = cats.get(s["cat"], 0) + 1
	var goal_lines: int = cats.get("goal", 0) + cats.get("goal_equaliser", 0) + cats.get("goal_late", 0)
	print("Goals %d, goal lines %d; %d lines said in %d categories: %s" % [goals, goal_lines, c.said.size(), cats.size(), str(cats)])
	if goal_lines != goals:
		push_error("every goal should get a line")
		ok = false
	if cats.get("match_start", 0) != 1:
		push_error("the start of the match should get a line")
		ok = false
	var break_lines: int = cats.get("half_time", 0) + cats.get("extra_time", 0) + cats.get("full_time", 0)
	# every break gets a line, bar the end of extra time that leads to penalties
	if break_lines < 2 or break_lines < breaks - 1:
		push_error("half time and full time should get lines (%d breaks, %d lines)" % [breaks, break_lines])
		ok = false
	if cats.size() < 8:
		push_error("a whole match should cover more kinds of play")
		ok = false
	m.queue_free()
	c.queue_free()
	return ok
