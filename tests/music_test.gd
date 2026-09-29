extends SceneTree
## Headless check of the menu music: every playlist entry is flagged, a missing
## mp3 is skipped (they are not in git), the playlist crossfades when files
## are present, and the export guard leaves demo-only tracks out of a release.
## Run: godot --headless --path . -s tests/music_test.gd

const Music := preload("res://scripts/music.gd")

var _done := false


func _process(_delta: float) -> bool:
	if not _done:
		_done = true
		_run()
	return false


func _run() -> void:
	var ok := true
	var list := Music.read_playlist()
	if list.size() != 4:
		push_error("playlist.json should list 4 tracks, has %d" % list.size())
		ok = false
	for t in list:
		if not Music.is_demo_only(t):
			push_error("%s is not licensed and must be demo_only" % t.get("file"))
			ok = false
	if not Music.is_demo_only({"licensed": false}) or Music.is_demo_only({"licensed": true}):
		push_error("licensed: false should imply demo_only")
		ok = false

	var mus = root.get_node("Music")
	var present: int = Music._music_files().size()
	print("music: %d of %d mp3s present, %d playable" % [present, list.size(), mus.tracks.size()])
	if mus.tracks.size() != present:
		push_error("every present mp3 (and only those) should be playable here")
		ok = false
	mus.set_volume_step(2, false)
	mus.play()
	if present > 0:
		await create_timer(0.2).timeout
		if mus.now_playing.is_empty():
			push_error("play() should start a track")
			ok = false
		mus._start_next(0.1)  # crossfade to the next track
		await create_timer(0.4).timeout
		var sounding := 0
		for p in mus._players:
			sounding += int(p.playing)
		if sounding != 1:
			push_error("after a crossfade exactly one player should be playing, got %d" % sounding)
			ok = false
	mus.stop(0.1)
	await create_timer(0.3).timeout
	for p in mus._players:
		if p.playing:
			push_error("stop() should silence the music")
			ok = false

	# The export guard: release builds skip every demo-only file.
	# (the plugin itself can only be made inside the editor; it uses this list)
	if load("res://addons/demo_music/export_plugin.gd") == null:
		push_error("the export guard script should load")
		ok = false
	if Music.files_to_leave_out(PackedStringArray(["pc", "release"])).size() != Music.all_tracks().size():
		push_error("a release export should leave out every demo track")
		ok = false
	if not Music.files_to_leave_out(PackedStringArray(["pc", "demo"])).is_empty():
		push_error("a demo export should keep the demo tracks")
		ok = false

	print("MUSIC TEST: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
