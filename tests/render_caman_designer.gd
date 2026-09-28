extends SceneTree
## Screenshots of the caman designer with full scenery, a few designs.
##   xvfb-run -s "-screen 0 1280x720x24" godot --path . -s tests/render_caman_designer.gd -- <out_dir>

const DESIGNS := [
	["kingussie", {"shape": 0, "wood": 1, "grip": "#c8102e", "wrap": true, "grip2": "#1f4fb8", "bas_tape": "#141417", "bands": 2, "band": "#1f4fb8"}, 2],
	["newtonmore", {"shape": 1, "wood": 3, "paint": "#16254f", "grip": "#f2f2f0", "wrap": true, "grip2": "#f07c1a", "bas_tape": "#f07c1a", "bands": 3, "band": "#f07c1a", "helmet": "#f2f2f0"}, 5],
	["lovat", {"shape": 3, "wood": 2, "grip": "#f2c400", "bas_tape": "#141417", "bands": 1, "band": "#f2c400"}, 9],
]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	var game = root.get_node("Game")
	game.camans_path = "user://camans_render.json"
	change_scene_to_file("res://scenes/main_menu.tscn")
	for i in 30:
		await process_frame
	var menu = current_scene
	menu._open_designer()
	menu._show("camans", true)
	for d in DESIGNS:
		var idx := 0
		for i in game.teams.size():
			if game.teams[i]["id"] == d[0]:
				idx = i
		menu.design_club.select(idx)
		menu.design = d[1].duplicate()
		menu._design_refresh(false)
		menu.backdrop.bench._spin = 0.0
		menu.design_rows.values()[d[2]].grab_focus()
		for i in 20:
			await process_frame
		root.get_texture().get_image().save_png("%s/designer_%s.png" % [out, d[0]])
		print("saved ", d[0])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(game.camans_path))
	quit()
