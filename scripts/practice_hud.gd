extends Control
## Training ground overlay: the move picked, slow motion, camera, who is out
## there, the hit meter and the controls.

var match_node: Node
var view: Node
var font: Font


func _ready() -> void:
	font = ThemeDB.fallback_font
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var m := match_node
	var screen := get_viewport_rect().size
	var w := screen.x
	# The move list: the one picked, with its neighbours either side.
	var box := Rect2(Vector2(24, 24), Vector2(400, 150))
	draw_rect(box, Color(0, 0, 0, 0.6))
	draw_rect(Rect2(box.position, Vector2(4, box.size.y)), Color(1, 0.85, 0.2, 0.9))
	draw_string(font, box.position + Vector2(16, 26), "TRAINING GROUND", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 0.85, 0.2))
	var n: int = m.MOVES.size()
	for k in [-1, 0, 1]:
		var i: int = (m.move_index + k + n) % n
		var text: String = m.MOVES[i][0]
		var y: float = 62.0 + (k + 1) * 26.0
		if k == 0:
			draw_string(font, box.position + Vector2(16, y), "◀  " + text + "  ▶", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)
		else:
			draw_string(font, box.position + Vector2(40, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.5))
	var info := "Speed %s   Camera %s   Goals %d" % [_speed_text(m.SPEEDS[m.speed_index]), "close" if m.close_cam else "TV", m.goals]
	draw_string(font, box.position + Vector2(16, 140), info, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.85))
	if m.editing:
		var tip := "Up / down pick a row    Left / right change it    A press    B or Esc when done    Right stick or , . turns the camera"
		draw_rect(Rect2(Vector2(0, screen.y - 44), Vector2(w, 44)), Color(0, 0, 0, 0.5))
		draw_string(font, Vector2(0, screen.y - 17), tip, HORIZONTAL_ALIGNMENT_CENTER, w, 15, Color(1, 1, 1, 0.9))
		return
	var who := "Keeper %s   Defender %s" % ["in" if m.keeper_on else "out", "in" if m.defender_on else "out"]
	draw_string(font, Vector2(w - 260, 44), who, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.85))

	var human = m.human
	if human != null and m.charge >= 0.0 and view != null:
		var c: Vector2 = view.screen_pos(human.pos, 3.0) + Vector2(-20, -8)
		draw_rect(Rect2(c, Vector2(40, 6)), Color(0, 0, 0, 0.6))
		var full: float = min(m.charge, 1.0)
		draw_rect(Rect2(c, Vector2(40 * full, 6)), Color(1, 0.4 + 0.5 * (1.0 - full), 0.1))
		if m.charge > 1.0:
			draw_rect(Rect2(c + Vector2(40, 0), Vector2(40 * (m.charge - 1.0), 6)), Color(0.9, 0.1, 0.1))

	if m.message_timer > 0.0:
		var size := 30 if m.message.begins_with("GOAL") else 20
		draw_string(font, Vector2(0, screen.y * 0.3), m.message, HORIZONTAL_ALIGNMENT_CENTER, w, size, Color.WHITE)

	var pad := "Pick move D-pad ◀ ▶   Play it R3   Ball back D-pad ▼   Slow motion D-pad ▲   Camera View   Close camera turn: right stick   Pause Start"
	var keys := "Keys: pick [ ]   play T   edit pose Y   ball back Backspace   slow motion Tab   camera V (turn , .)   pause Esc   plus the match controls"
	draw_rect(Rect2(Vector2(0, screen.y - 44), Vector2(w, 44)), Color(0, 0, 0, 0.5))
	draw_string(font, Vector2(0, screen.y - 26), pad, HORIZONTAL_ALIGNMENT_CENTER, w, 13, Color(1, 1, 1, 0.85))
	draw_string(font, Vector2(0, screen.y - 8), keys, HORIZONTAL_ALIGNMENT_CENTER, w, 13, Color(1, 1, 1, 0.65))

	if m.paused:
		var pb := Rect2(Vector2(w / 2.0 - 300, screen.y / 2.0 - 70), Vector2(600, 170))
		draw_rect(pb, Color(0, 0, 0, 0.7))
		draw_string(font, pb.position + Vector2(0, 40), "Paused", HORIZONTAL_ALIGNMENT_CENTER, pb.size.x, 28, Color.WHITE)
		draw_string(font, pb.position + Vector2(0, 76), "Y / K  %s the keeper     X / J  %s a defender" % ["take off" if m.keeper_on else "bring on", "take off" if m.defender_on else "bring on"],
			HORIZONTAL_ALIGNMENT_CENTER, pb.size.x, 16, Color(1, 1, 1, 0.9))
		draw_string(font, pb.position + Vector2(0, 106), "A / Enter  edit this move in the pose editor",
			HORIZONTAL_ALIGNMENT_CENTER, pb.size.x, 16, Color(1, 0.85, 0.2))
		draw_string(font, pb.position + Vector2(0, 140), "Start / Esc to carry on     Back / M for the menu",
			HORIZONTAL_ALIGNMENT_CENTER, pb.size.x, 15, Color(1, 1, 1, 0.75))


func _speed_text(s: float) -> String:
	if s >= 1.0:
		return "full"
	return {0.5: "half", 0.25: "quarter", 0.1: "a tenth"}.get(s, str(s))
