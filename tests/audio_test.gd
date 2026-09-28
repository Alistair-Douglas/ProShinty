extends SceneTree
## Headless check that the match sound hears the match: a computer-vs-computer
## match with ShintyMatchAudio attached must thwack on strikes and cheer goals.
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
		push_error("crowd_loop.wav must be imported as a loop")
		ok = false
	var teams := TeamData.load_teams()
	var m = MatchScene.instantiate()
	m.manual_step = true
	m.config = {"home": teams[0], "away": teams[1], "human_side": -1, "difficulty": 1, "half_seconds": 180.0, "seed": 101}
	root.add_child(m)
	var audio := ShintyMatchAudio.new()
	m.add_child(audio)
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
	var thwacks: int = audio.heard.get("thwack_1", 0) + audio.heard.get("thwack_2", 0) + audio.heard.get("thwack_3", 0)
	var cheers: int = audio.heard.get("cheer_1", 0) + audio.heard.get("cheer_2", 0)
	print("Strikes %d, thwacks %d; goals %d, cheers %d; all sounds %s" % [strikes, thwacks, goals, cheers, str(audio.heard)])
	if strikes == 0 or thwacks != strikes:
		push_error("every strike should thwack")
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
