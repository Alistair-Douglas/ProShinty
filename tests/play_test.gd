extends SceneTree
## Drives the real game with simulated key presses and saves screenshots.
## Needs a display: xvfb-run godot --path . -s tests/play_test.gd -- <out_dir>

var frame := 0
var out_dir := "user://"
var match_node: Node = null
var _pressed := false


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	change_scene_to_file("res://scenes/main_menu.tscn")


func _shot(name: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png(out_dir.path_join(name))
	print("saved ", name)


func _process(_delta: float) -> bool:
	# Wait on the loading screen, then press a key to start the match.
	if frame >= 20 and current_scene and current_scene.name == "Loading":
		if current_scene.ready_to_play and not _pressed:
			_pressed = true
			var e := InputEventKey.new()
			e.keycode = KEY_SPACE
			e.pressed = true
			root.push_input(e)
		return false
	frame += 1
	if frame == 20:
		assert(root.has_node("Game"), "Game autoload missing")
		_shot("menu.png")
		current_scene.call("_start")
	if frame == 40:
		match_node = current_scene
		print("scene: ", match_node.name, " human: ", match_node.human != null)
		Input.action_press("move_right")
	if frame == 150:
		_shot("match_early.png")
		Input.action_press("shoot")
	if frame == 190:
		Input.action_release("shoot")
		Input.action_release("move_right")
	if frame == 200:
		print("after hit: carrier=", match_node.carrier, " ball=", match_node.ball_pos, " shots=", match_node.shots)
	if frame > 200 and frame % 30 == 0:
		# Chase and hit the ball with whoever is selected.
		var h = match_node.human
		Input.action_release("move_left"); Input.action_release("move_right")
		Input.action_release("move_up"); Input.action_release("move_down")
		var d: Vector2 = match_node.ball_pos - h.pos
		if abs(d.x) > 1: Input.action_press("move_right" if d.x > 0 else "move_left")
		if abs(d.y) > 1: Input.action_press("move_down" if d.y > 0 else "move_up")
		if match_node.carrier == h:
			Input.action_press("move_right" if match_node.attack_dir[0] == 1 else "move_left")
			Input.action_press("pass")
		else:
			Input.action_release("pass")
			Input.action_press("switch")
	if frame > 200 and frame % 30 == 5:
		Input.action_release("switch")
	if frame == 900:
		_shot("match_later.png")
		print("minute ", match_node.match_minute(), " score ", match_node.score, " human ", match_node.human.number)
		return true
	return false
