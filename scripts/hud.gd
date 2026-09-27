extends Control
## Scoreboard, controlled-player info, power bar and messages over the 3D match.

var match_node: Node
var view: Node
var font: Font


func _ready() -> void:
	font = ThemeDB.fallback_font
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var m := match_node
	var teams: Array = m.teams
	var colors: Array = m.colors
	var screen := get_viewport_rect().size
	var w := screen.x
	var bar := Rect2(Vector2(w / 2.0 - 260, 12), Vector2(520, 44))
	draw_rect(bar, Color(0, 0, 0, 0.6))
	draw_rect(Rect2(bar.position, Vector2(10, 44)), colors[0][0])
	draw_rect(Rect2(bar.end - Vector2(10, 44), Vector2(10, 44)), colors[1][0])
	var line := "%s  %d - %d  %s" % [teams[0]["name"].to_upper(), m.score[0], m.score[1], teams[1]["name"].to_upper()]
	draw_string(font, bar.position + Vector2(0, 30), line, HORIZONTAL_ALIGNMENT_CENTER, 440, 22, Color.WHITE)
	draw_string(font, bar.position + Vector2(440, 30), "%d'" % m.match_minute(), HORIZONTAL_ALIGNMENT_CENTER, 70, 20, Color(1, 0.9, 0.4))
	var human = m.human
	if human != null:
		var d: Dictionary = human.data
		var info := "You: #%d %s  (%s, OVR %d)" % [human.number, d.get("name", ""), human.position_code, int(d.get("overall", 0))]
		_panel_text(Vector2(20, 70), info, 15)
		draw_rect(Rect2(Vector2(w - 190, 76), Vector2(150, 8)), Color(0, 0, 0, 0.5))
		draw_rect(Rect2(Vector2(w - 190, 76), Vector2(150 * human.stamina, 8)), Color(0.3, 0.85, 0.4))
		draw_string(font, Vector2(w - 250, 85), "Stamina", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
		if m.charge >= 0.0 and view != null:
			var c: Vector2 = view.screen_pos(human.pos, 3.0) + Vector2(-20, -8)
			draw_rect(Rect2(c, Vector2(40, 6)), Color(0, 0, 0, 0.6))
			draw_rect(Rect2(c, Vector2(40 * m.charge, 6)), Color(1, 0.4 + 0.5 * (1.0 - m.charge), 0.1))
	var help := "Move WASD/Arrows   Sprint Shift   Hit Space (hold for power) / Tackle   Pass E   Switch Q   Pause Esc"
	draw_rect(Rect2(Vector2(0, screen.y - 24), Vector2(w, 24)), Color(0, 0, 0, 0.45))
	draw_string(font, Vector2(0, screen.y - 7), help, HORIZONTAL_ALIGNMENT_CENTER, w, 13, Color(1, 1, 1, 0.8))
	var centre_text := ""
	var sub := ""
	if m.paused:
		centre_text = "Paused"
		sub = "Esc to resume, M to quit to menu"
	elif m.state == m.State.FULL_TIME:
		centre_text = "Full time: %s %d - %d %s" % [teams[0]["name"], m.score[0], m.score[1], teams[1]["name"]]
		sub = "Press Space or Enter for the menu"
	elif m.message_timer > 0.0:
		centre_text = m.message
	if centre_text != "":
		var box := Rect2(Vector2(w / 2.0 - 330, screen.y / 2.0 - 40), Vector2(660, 80 if sub != "" else 56))
		draw_rect(box, Color(0, 0, 0, 0.65))
		draw_string(font, box.position + Vector2(0, 38), centre_text, HORIZONTAL_ALIGNMENT_CENTER, box.size.x, 28, Color.WHITE)
		if sub != "":
			draw_string(font, box.position + Vector2(0, 66), sub, HORIZONTAL_ALIGNMENT_CENTER, box.size.x, 15, Color(1, 1, 1, 0.8))


func _panel_text(pos: Vector2, text: String, font_size: int) -> void:
	var sz := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	draw_rect(Rect2(pos - Vector2(8, font_size + 4), sz + Vector2(16, 10)), Color(0, 0, 0, 0.5))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)
