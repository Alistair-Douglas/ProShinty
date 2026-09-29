extends Node
## Menu music (autoload "Music"): plays music/playlist.json shuffled, with a
## crossfade between tracks. Tracks flagged demo_only (not licensed) play only
## in the editor or a build exported with the "demo" feature; the export plugin
## in addons/demo_music leaves their files out of any other build. The mp3s are
## not in git, so a missing file is simply skipped.

const PLAYLIST_PATH := "res://music/playlist.json"
const DIR := "res://music/"
const CROSSFADE := 4.0  # seconds
const VOLUME_NAMES := ["Off", "25%", "50%", "75%", "100%"]
const SETTINGS_PATH := "user://settings.cfg"

## 0..4 = Off..100%. Saved between runs.
var volume_step := 3
var tracks: Array = []  ## playable tracks: {file, title, artist, stream}
var now_playing := {}

var _players: Array[AudioStreamPlayer] = []
var _cur := 0  ## index into _players
var _order: Array = []
var _next := 0
var _playing := false
var _fading := false


## Whether demo-only (unlicensed) tracks may play in this build.
static func demo_allowed() -> bool:
	return OS.has_feature("editor") or OS.has_feature("demo")


## A track entry's demo-only flag: set explicitly, or implied by licensed: false.
static func is_demo_only(t: Dictionary) -> bool:
	return bool(t.get("demo_only", false)) or not bool(t.get("licensed", true))


## The music files an export with these features must leave out: every
## demo-only track, unless the export has the "demo" feature.
static func files_to_leave_out(features: PackedStringArray) -> Array:
	var out := []
	if "demo" in features:
		return out
	for t in all_tracks():
		if is_demo_only(t):
			out.append(DIR + str(t["file"]))
	return out


## The playlist's entries plus any other mp3/ogg/wav dropped into music/
## under a different name. Those extras have no known licence, so they count
## as demo only.
static func all_tracks() -> Array:
	var out := []
	var listed := {}
	for t in read_playlist():
		if t is Dictionary and t.has("file"):
			out.append(t)
			listed[str(t["file"]).to_lower()] = true
	for f in _music_files():
		if not listed.has(f.to_lower()):
			out.append({"file": f, "title": f.get_basename(), "licensed": false, "demo_only": true})
	return out


## Audio files in music/. In an exported build only the .import stubs are
## listed, so those are mapped back to the original name.
static func _music_files() -> Array:
	var found := {}
	for f in DirAccess.get_files_at(DIR):
		if f.ends_with(".import") or f.ends_with(".remap"):
			f = f.get_basename()
		if f.get_extension().to_lower() in ["mp3", "ogg", "wav"]:
			found[f] = true
	var names := found.keys()
	names.sort()
	return names


static func read_playlist() -> Array:
	if not FileAccess.file_exists(PLAYLIST_PATH):
		return []
	var data = JSON.parse_string(FileAccess.get_file_as_string(PLAYLIST_PATH))
	return data.get("tracks", []) if data is Dictionary else []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		volume_step = clampi(int(cfg.get_value("audio", "music", volume_step)), 0, 4)
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.volume_db = -80.0
		add_child(p)
		_players.append(p)
	for t in all_tracks():
		if is_demo_only(t) and not demo_allowed():
			continue
		var stream := _load(DIR + str(t["file"]))
		if stream == null:
			continue
		var entry: Dictionary = t.duplicate()
		entry["stream"] = stream
		tracks.append(entry)


func _load(path: String) -> AudioStream:
	if ResourceLoader.exists(path):
		return load(path) as AudioStream
	if FileAccess.file_exists(path):  # not imported yet (fresh drop, headless)
		match path.get_extension().to_lower():
			"mp3": return AudioStreamMP3.load_from_file(path)
			"ogg": return AudioStreamOggVorbis.load_from_file(path)
			"wav": return AudioStreamWAV.load_from_file(path)
	return null


func _target_db() -> float:
	return -80.0 if volume_step == 0 else linear_to_db(volume_step / 4.0) - 6.0


func set_volume_step(v: int, remember := true) -> void:
	volume_step = clampi(v, 0, 4)
	if _playing and not _fading:
		_players[_cur].volume_db = _target_db()
	if volume_step == 0:
		stop(0.3)
	elif not _playing:
		play()
	if remember:
		var cfg := ConfigFile.new()
		cfg.load(SETTINGS_PATH)
		cfg.set_value("audio", "music", volume_step)
		cfg.save(SETTINGS_PATH)


## Starts the playlist (no-op if already playing, muted or empty).
func play() -> void:
	if _playing or tracks.is_empty() or volume_step == 0:
		return
	_playing = true
	_start_next(1.5)


## Fades the music out and stops.
func stop(fade := 1.5) -> void:
	if not _playing:
		return
	_playing = false
	_fading = false
	for p in _players:
		if p.playing:
			var tw := create_tween()
			tw.tween_property(p, "volume_db", -80.0, fade)
			tw.tween_callback(p.stop)


func _start_next(fade: float) -> void:
	if _next >= _order.size():
		var last = _order.back() if not _order.is_empty() else -1
		_order = range(tracks.size())
		_order.shuffle()
		if _order.size() > 1 and _order[0] == last:
			_order.reverse()  # never the same track twice in a row
		_next = 0
	var t: Dictionary = tracks[_order[_next]]
	_next += 1
	var old := _players[_cur]
	_cur = 1 - _cur
	var p := _players[_cur]
	p.stream = t["stream"]
	p.volume_db = -80.0
	p.play()
	now_playing = t
	_fading = true
	var tw := create_tween().set_parallel()
	tw.tween_property(p, "volume_db", _target_db(), fade)
	if old.playing:
		tw.tween_property(old, "volume_db", -80.0, fade)
	tw.chain().tween_callback(func():
		old.stop()
		_fading = false)


func _process(_delta: float) -> void:
	if not _playing or _fading:
		return
	var p := _players[_cur]
	var length := p.stream.get_length() if p.stream else 0.0
	if not p.playing or (length > 0.0 and p.get_playback_position() >= length - CROSSFADE):
		_start_next(CROSSFADE)
