extends Node
## Global game state (autoload "Game"): loaded squads, menu choices and controls.

const TeamData := preload("res://scripts/team_data.gd")

var teams: Array = []
var home_index := 0
var away_index := 1
var human_side := 0  # 0 = you play the home team, 1 = the away team
var difficulty := 1  # 0 easy, 1 normal, 2 hard
var half_minutes := 3  # real minutes per half
var venue := -1  # ShintyPitch.Venue; -1 until picked = the home team's ground
var last_result := {}
## 0 Low, 1 Medium, 2 High (ShintyPitch.Detail). Saved between runs.
var graphics_quality := 1

## Camans from the caman designer, saved between runs, by club id:
## {"team": design, "players": {shirt number: design}}. A player with their
## own caman carries it; the rest carry the club's (ShintyCaman designs).
var camans := {}

const SETTINGS_PATH := "user://settings.cfg"
const CAMANS_PATH := "user://camans.json"
## Where designs are saved; tests point this elsewhere.
var camans_path := CAMANS_PATH
const GRAPHICS_NAMES := ["Low", "Medium", "High"]


func _ready() -> void:
	teams = TeamData.load_teams()
	if teams.size() > 1:
		away_index = 1
	_setup_input()
	_load_camans()
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK and cfg.has_section_key("graphics", "quality"):
		graphics_quality = clampi(int(cfg.get_value("graphics", "quality")), 0, 2)
	elif RenderingServer.get_video_adapter_type() == RenderingDevice.DEVICE_TYPE_DISCRETE_GPU:
		graphics_quality = 2  # first run on a gaming GPU: the full look
	_apply_graphics()


func set_graphics_quality(q: int, remember := true) -> void:
	graphics_quality = clampi(q, 0, 2)
	_apply_graphics()
	if not remember:
		return
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("graphics", "quality", graphics_quality)
	cfg.save(SETTINGS_PATH)


## Renderer-wide settings; the pitch reads graphics_quality for its sun and
## screen effects when a match starts (see match_view.gd).
func _apply_graphics() -> void:
	var q := graphics_quality
	var vp := get_viewport()
	vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][q]
	# Low draws the 3D view at 80% and upscales it with FSR; menus stay sharp.
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if q == 0 else Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = 0.8 if q == 0 else 1.0
	RenderingServer.directional_shadow_atlas_set_size([2048, 4096, 8192][q], true)
	RenderingServer.directional_soft_shadow_filter_set_quality(
		[RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW, RenderingServer.SHADOW_QUALITY_SOFT_LOW,
		RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM][q])


## The caman a club's players carry: its saved design, else one in its colours.
func team_caman(team_index: int) -> Dictionary:
	var team: Dictionary = teams[team_index]
	if team.has("caman"):
		return ShintyCaman.sanitize(team["caman"])
	return ShintyCaman.for_team(team)


## The caman one player carries: their own, else the club's.
func player_caman(team_index: int, number: int) -> Dictionary:
	var own: Dictionary = _club_camans(team_index).get("players", {}).get(str(number), {})
	return ShintyCaman.sanitize(own) if not own.is_empty() else team_caman(team_index)


## Whether a player has a caman of their own.
func has_own_caman(team_index: int, number: int) -> bool:
	return _club_camans(team_index).get("players", {}).has(str(number))


## Gives a club a caman design and remembers it. Players with their own
## caman keep it unless `everyone`.
func set_team_caman(team_index: int, design: Dictionary, everyone := false) -> void:
	var c := _club_camans(team_index)
	c["team"] = ShintyCaman.sanitize(design)
	if everyone:
		c.erase("players")
	_apply_camans(team_index)
	_save_camans()


## Gives one player (by shirt number) their own caman.
func set_player_caman(team_index: int, number: int, design: Dictionary) -> void:
	var c := _club_camans(team_index)
	if not c.has("players"):
		c["players"] = {}
	c["players"][str(number)] = ShintyCaman.sanitize(design)
	_apply_camans(team_index)
	_save_camans()


func _club_key(team_index: int) -> String:
	var team: Dictionary = teams[team_index]
	return str(team.get("id", team["name"]))


func _club_camans(team_index: int) -> Dictionary:
	var key := _club_key(team_index)
	if not camans.has(key):
		camans[key] = {}
	return camans[key]


## Puts the saved camans on the club and its players ("caman" keys), which
## the player models and the strike physics read.
func _apply_camans(team_index: int) -> void:
	var team: Dictionary = teams[team_index]
	var c: Dictionary = camans.get(_club_key(team_index), {})
	if c.has("team"):
		team["caman"] = c["team"]
	else:
		team.erase("caman")
	var own: Dictionary = c.get("players", {})
	for p in team.get("players", []):
		var key := str(p.get("number", ""))
		if own.has(key):
			p["caman"] = own[key]
		elif c.has("team"):
			p["caman"] = c["team"]
		else:
			p.erase("caman")


func _save_camans() -> void:
	var f := FileAccess.open(camans_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(camans, "\t"))


func _load_camans() -> void:
	camans = {}
	var data: Variant = null
	if FileAccess.file_exists(camans_path):
		data = JSON.parse_string(FileAccess.get_file_as_string(camans_path))
	if not (data is Dictionary):
		data = {}
	for i in teams.size():
		var key := _club_key(i)
		var saved: Variant = data.get(key, null)
		if saved is Dictionary:
			var c := {}
			if saved.has("shape"):  # the first designer saved a bare club design
				c["team"] = ShintyCaman.sanitize(saved)
			else:
				if saved.get("team", null) is Dictionary:
					c["team"] = ShintyCaman.sanitize(saved["team"])
				if saved.get("players", null) is Dictionary:
					c["players"] = {}
					for n in saved["players"]:
						c["players"][str(n)] = ShintyCaman.sanitize(saved["players"][n])
			camans[key] = c
		_apply_camans(i)


func match_config() -> Dictionary:
	return {
		"home": teams[home_index],
		"away": teams[away_index],
		"human_side": human_side,
		"difficulty": difficulty,
		"half_seconds": half_minutes * 60.0,
		"venue": max(venue, 0),
	}


func _setup_input() -> void:
	_bind("move_left", [KEY_A, KEY_LEFT], [], [JOY_AXIS_LEFT_X, -1.0])
	_bind("move_right", [KEY_D, KEY_RIGHT], [], [JOY_AXIS_LEFT_X, 1.0])
	_bind("move_up", [KEY_W, KEY_UP], [], [JOY_AXIS_LEFT_Y, -1.0])
	_bind("move_down", [KEY_S, KEY_DOWN], [], [JOY_AXIS_LEFT_Y, 1.0])
	_bind("shoot", [KEY_SPACE], [JOY_BUTTON_X], [], [MOUSE_BUTTON_LEFT])
	_bind("hit", [KEY_X], [], [JOY_AXIS_TRIGGER_RIGHT, 1.0])
	_bind("shield", [KEY_Z], [], [JOY_AXIS_TRIGGER_LEFT, 1.0])
	_bind("pass", [KEY_E], [JOY_BUTTON_A])
	_bind("switch", [KEY_Q], [JOY_BUTTON_LEFT_SHOULDER])
	_bind("block", [KEY_F], [JOY_BUTTON_Y])
	_bind("cleek", [KEY_C], [JOY_BUTTON_B])
	_bind("barge", [KEY_R], [JOY_BUTTON_LEFT_STICK])
	_bind("sprint", [KEY_SHIFT], [JOY_BUTTON_RIGHT_SHOULDER])
	_bind("pause", [KEY_ESCAPE, KEY_P], [JOY_BUTTON_START])
	_bind("quit_match", [KEY_M], [JOY_BUTTON_BACK])
	# Menus on a controller: A selects and B goes back. Godot's own ui_accept
	# and ui_cancel only have keys.
	_add_button("ui_accept", JOY_BUTTON_A)
	_add_button("ui_cancel", JOY_BUTTON_B)
	# Change a picker (club, pitch, ...) with the right stick or bumpers.
	_bind("menu_prev", [], [JOY_BUTTON_LEFT_SHOULDER], [JOY_AXIS_RIGHT_X, -1.0])
	_bind("menu_next", [], [JOY_BUTTON_RIGHT_SHOULDER], [JOY_AXIS_RIGHT_X, 1.0])


func _add_button(action: String, button: JoyButton) -> void:
	for e in InputMap.action_get_events(action):
		if e is InputEventJoypadButton and e.button_index == button:
			return
	var b := InputEventJoypadButton.new()
	b.button_index = button
	InputMap.action_add_event(action, b)


func _bind(action: String, keys: Array, buttons: Array = [], axis: Array = [], mouse: Array = []) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action, 0.3)
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(action, e)
	for b in buttons:
		var e := InputEventJoypadButton.new()
		e.button_index = b
		InputMap.action_add_event(action, e)
	for b in mouse:
		var e := InputEventMouseButton.new()
		e.button_index = b
		InputMap.action_add_event(action, e)
	if not axis.is_empty():
		var e := InputEventJoypadMotion.new()
		e.axis = axis[0]
		e.axis_value = axis[1]
		InputMap.action_add_event(action, e)
