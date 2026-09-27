extends SceneTree
## Opens the loading screen once per picture, waits for it to finish loading
## the match, and saves a screenshot of each.
## xvfb-run godot --path . -s tests/loading_test.gd -- <out_dir>
var loading: GDScript
var out := ""
var shown := 0
var frame := 0


func _initialize() -> void:
	out = OS.get_cmdline_user_args()[0]
	loading = load("res://scripts/loading_screen.gd")
	loading._next = 0
	change_scene_to_file("res://scenes/loading.tscn")


func _process(_d: float) -> bool:
	frame += 1
	if frame > 1200:
		push_error("loading screen %d never became ready" % shown)
		return true
	var s = current_scene
	if s and s.get("ready_to_play") and frame > 20:
		root.get_texture().get_image().save_png("%s/loading_%d.png" % [out, shown])
		print("loading screen %d ready" % shown)
		shown += 1
		frame = 0
		if shown == loading.SLIDES.size():
			return true
		change_scene_to_file("res://scenes/loading.tscn")
	return false
