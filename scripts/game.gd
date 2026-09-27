extends Node
## Global game state (autoload "Game"): loaded squads, menu choices and controls.

const TeamData := preload("res://scripts/team_data.gd")

var teams: Array = []
var home_index := 0
var away_index := 1
var human_side := 0  # 0 = you play the home team, 1 = the away team
var difficulty := 1  # 0 easy, 1 normal, 2 hard
var half_minutes := 3  # real minutes per half
var last_result := {}


func _ready() -> void:
	teams = TeamData.load_teams()
	if teams.size() > 1:
		away_index = 1
	_setup_input()


func match_config() -> Dictionary:
	return {
		"home": teams[home_index],
		"away": teams[away_index],
		"human_side": human_side,
		"difficulty": difficulty,
		"half_seconds": half_minutes * 60.0,
	}


func _setup_input() -> void:
	_bind("move_left", [KEY_A, KEY_LEFT], [], [JOY_AXIS_LEFT_X, -1.0])
	_bind("move_right", [KEY_D, KEY_RIGHT], [], [JOY_AXIS_LEFT_X, 1.0])
	_bind("move_up", [KEY_W, KEY_UP], [], [JOY_AXIS_LEFT_Y, -1.0])
	_bind("move_down", [KEY_S, KEY_DOWN], [], [JOY_AXIS_LEFT_Y, 1.0])
	_bind("shoot", [KEY_SPACE], [JOY_BUTTON_X])
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
