extends SceneTree
## Headless check that the match sound hears the match: a computer-vs-computer
## match with ShintyMatchAudio attached must thwack on strikes, crack off the
## posts and cheer goals.
## Run: godot --headless --path . -s tests/audio_test.gd

const TeamData := preload("res://scripts/team_data.gd")
const MatchScene := preload("res://scenes/match.tscn")


var _done := false


func _process(_delta: float) -> bool:
	if not _done:
		_done = true
		_run()
	return false


func _run() -> void:
	var ok := true
	var crowd: AudioStreamWAV = ShintyMatchAudio.CROWD_LOOP
	if crowd.loop_mode == AudioStreamWAV.LOOP_DISABLED:
		push_error("crowd_chatter.wav must be imported as a loop")
		ok = false
	var teams := TeamData.load_teams()
	var m = MatchScene.instantiate()
	m.manual_step = true
	m.config = {"home": teams[0], "away": teams[1], "human_side": -1, "difficulty": 1, "half_seconds": 180.0, "seed": 101}
	root.add_child(m)
	var audio := ShintyMatchAudio.new()
	m.add_child(audio)
	# a ball off the bar is picked up from the ball physics
	audio.off_the_post(20.0)
	if audio.heard.get("post_bat", 0) != 1:
		push_error("off_the_post should play the bat hit")
		ok = false
	audio.heard.erase("post_bat")
	var steps := 0
	while m.state != m.State.FULL_TIME and steps < 60 * 600:
		m.step(1.0 / 60.0)
		audio._process(1.0 / 60.0)
		steps += 1
	var strikes := 0
	var goals := 0
	for e in m.events:
		strikes += 1 if e["type"] == "strike" else 0
		goals += 1 if e["type"] == "goal" else 0
	var thwacks: int = audio.heard.get("strike", 0)
	var cheers: int = audio.heard.get("cheer_crowd", 0)
	var posts: int = m.ball_sim.post_hits.size()
	print("Strikes %d, thwacks %d; goals %d, cheers %d; posts %d; all sounds %s" % [strikes, thwacks, goals, cheers, posts, str(audio.heard)])
	if audio.heard.get("post_bat", 0) != posts:
		push_error("every hit off the post or bar should be heard")
		ok = false
	if strikes == 0 or thwacks != strikes:
		push_error("every strike should thwack")
		ok = false
	# A draw goes to extra time, so there can be more than one break: each
	# one gets its whistle (half time two blasts, the others the full one).
	var halves := 0
	var fulls := 0
	for e in m.events:
		if e["type"] == "half_end":
			if e.get("half", 1) == 1:
				halves += 1
			else:
				fulls += 1
	if halves != 1 or fulls < 1 or audio.heard.get("whistle_half", 0) != halves or audio.heard.get("whistle_full", 0) != fulls:
		push_error("half time and full time should each get their whistle")
		ok = false
	if audio.heard.get("whistle", 0) == 0:
		push_error("restarts should get a whistle")
		ok = false
	if cheers != goals:
		push_error("every goal should get a cheer")
		ok = false
	# harder hits are louder
	var soft: AudioStreamPlayer = null
	audio.strike(10.0)
	soft = audio._sfx[(audio._next_voice - 1 + audio._sfx.size()) % audio._sfx.size()]
	var soft_db := soft.volume_db
	audio.strike(38.0)
	var hard: AudioStreamPlayer = audio._sfx[(audio._next_voice - 1 + audio._sfx.size()) % audio._sfx.size()]
	if hard.volume_db <= soft_db:
		push_error("a hard strike should be louder than a soft one")
		ok = false
	m.free()
	print("Audio test ", "passed" if ok else "FAILED")
	quit(0 if ok else 1)
