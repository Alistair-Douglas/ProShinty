@tool
extends EditorPlugin
## Adds the export plugin that keeps unlicensed menu music out of release builds.

var _export: EditorExportPlugin


func _enter_tree() -> void:
	_export = preload("res://addons/demo_music/export_plugin.gd").new()
	add_export_plugin(_export)


func _exit_tree() -> void:
	remove_export_plugin(_export)
	_export = null
