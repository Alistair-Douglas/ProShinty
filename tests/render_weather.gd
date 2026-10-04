extends SceneTree
## Renders a match in each kind of weather to the folder given after `--`
## (default renders/weather), or just one if named after the folder. Needs a display:
##   xvfb-run godot --path . --rendering-method gl_compatibility -s tests/render_weather.gd -- /tmp/out

const TeamData := preload("res://scripts/team_data.gd")
const MatchScene := preload("res://scenes/match.tscn")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "res://renders/weather"
	DirAccess.make_dir_recursive_absolute(out)
	var teams := TeamData.load_teams()
	var kinds := range(1, ShintyWeather.NAMES.size())
	if args.size() > 1:
		kinds = [ShintyWeather.NAMES.find(args[1])]   # just one, by name
	for kind in kinds:
		var m = MatchScene.instantiate()
		m.config = {"home": teams[0], "away": teams[1], "human_side": -1, "difficulty": 1,
			"half_seconds": 180.0, "seed": 5, "weather": kind, "venue": 1}
		root.add_child(m)
		for i in 60:
			await process_frame
		var file: String = out + "/" + ShintyWeather.NAMES[kind].to_snake_case() + ".png"
		root.get_viewport().get_texture().get_image().save_png(file)
		print("saved ", file, "  ", ShintyWeather.describe(m.weather))
		m.queue_free()
		await process_frame
	quit()
