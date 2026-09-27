extends Control
## Controlled-player info, power bar and messages over the 3D match. The score
## bug, clock, cards and goal graphics are TV graphics (broadcast/tv_graphics.gd).

const TeamData := preload("res://scripts/team_data.gd")

var match_node: Node
var view: Node
var font: Font
var tv: ShintyTVGraphics


func _ready() -> void:
	font = ThemeDB.fallback_font
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS  # keeps drawing while a replay holds the match
	tv = ShintyTVGraphics.new()
	tv.match_node = match_node
	add_child(tv)
	if view != null and view.get("director") != null:
		view.director.graphics = tv


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var m := match_node
	var teams: Array = m.teams
	var screen := get_viewport_rect().size
	var w := screen.x
	if tv.replay_active:
		return  # a replay shows only the TV graphics
	var human = m.human
	if human != null:
		var d: Dictionary = human.data
		var info := "You: #%d %s  (%s, OVR %d)" % [human.number, d.get("name", ""), human.position_code, int(d.get("overall", 0))]
		_panel_text(Vector2(28, screen.y - 44), info, 15)
		draw_rect(Rect2(Vector2(w - 190, 76), Vector2(150, 8)), Color(0, 0, 0, 0.5))
		draw_rect(Rect2(Vector2(w - 190, 76), Vector2(150 * human.stamina, 8)), Color(0.3, 0.85, 0.4))
		draw_string(font, Vector2(w - 250, 85), "Stamina", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
		if m.charge >= 0.0 and view != null:
			var c: Vector2 = view.screen_pos(human.pos, 3.0) + Vector2(-20, -8)
			draw_rect(Rect2(c, Vector2(40, 6)), Color(0, 0, 0, 0.6))
			var full: float = min(m.charge, 1.0)
			draw_rect(Rect2(c, Vector2(40 * full, 6)), Color(1, 0.4 + 0.5 * (1.0 - full), 0.1))
			if m.charge > 1.0:
				# Overswing: no extra power, just more chance of a miss-hit.
				draw_rect(Rect2(c + Vector2(40, 0), Vector2(40 * (m.charge - 1.0), 6)), Color(0.9, 0.1, 0.1))
	var help := "Move WASD/Arrows   Sprint Shift   Hit Space (hold)   Pass/Poke E   Block F   Cleek C   Barge R   Switch Q   Pause Esc"
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
	elif m.message_timer > 0.0 and not m.message.begins_with("GOAL"):  # the TV graphics show goals
		var lines: PackedStringArray = m.message.split("\n", true, 1)
		centre_text = lines[0]
		if lines.size() > 1:
			sub = lines[1]  # e.g. the referee's card
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
