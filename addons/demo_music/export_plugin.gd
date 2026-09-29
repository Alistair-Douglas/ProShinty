@tool
extends EditorExportPlugin
## Skips every music file flagged demo_only (or licensed: false) in
## music/playlist.json unless the export preset has the custom feature "demo".

const Music := preload("res://scripts/music.gd")

var _skip := {}


func _get_name() -> String:
	return "DemoMusicGuard"


func _export_begin(features: PackedStringArray, _is_debug: bool, _path: String, _flags: int) -> void:
	_skip.clear()
	for path in Music.files_to_leave_out(features):
		_skip[path] = true
	if not _skip.is_empty():
		print("Demo music guard: leaving out %d unlicensed track(s)" % _skip.size())


func _export_file(path: String, _type: String, _features: PackedStringArray) -> void:
	if _skip.has(path):
		skip()
