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

const SETTINGS_PATH := "user://settings.cfg"
const GRAPHICS_NAMES := ["Low", "Medium", "High"]


func _ready() -> void:
	teams = TeamData.load_teams()
	if teams.size() > 1:
		away_index = 1
	_setup_input()
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
	_bind("shoot", [KEY_SPACE], [JOY_BUTTON_X])
	_bind("hit", [KEY_X], [], [JOY_AXIS_TRIGGER_RIGHT, 1.0])
	_bind("pass", [KEY_E], [JOY_BUTTON_A])
	_bind("switch", [KEY_Q], [JOY_BUTTON_LEFT_SHOULDER])
	_bind("block", [KEY_F], [JOY_BUTTON_Y])
	_bind("cleek", [KEY_C], [JOY_BUTTON_B])
	_bind("barge", [KEY_R], [JOY_BUTTON_LEFT_STICK])
	_bind("sprint", [KEY_SHIFT], [JOY_BUTTON_RIGHT_SHOULDER])
	_bind("pause", [KEY_ESCAPE, KEY_P], [JOY_BUTTON_START])
	_bind("quit_match", [KEY_M], [JOY_BUTTON_BACK])


func _bind(action: String, keys: Array, buttons: Array = [], axis: Array = []) -> void:
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
	if not axis.is_empty():
		var e := InputEventJoypadMotion.new()
		e.axis = axis[0]
		e.axis_value = axis[1]
		InputMap.action_add_event(action, e)
