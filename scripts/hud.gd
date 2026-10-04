extends Control
## Controlled-player info, power bar and messages over the 3D match. The score
## bug, clock, cards and goal graphics are TV graphics (broadcast/tv_graphics.gd).

const TeamData := preload("res://scripts/team_data.gd")
const SubsMenu := preload("res://scripts/subs_menu.gd")
const StatsPanel := preload("res://scripts/stats_panel.gd")

var match_node: Node
var view: Node
var font: Font
var tv: ShintyTVGraphics
var subs_menu: Control
var stats_panel: Control
var commentary: ShintyCommentary


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
	subs_menu = SubsMenu.new()
	subs_menu.match_node = match_node
	add_child(subs_menu)
	stats_panel = StatsPanel.new()
	stats_panel.match_node = match_node
	stats_panel.subs_menu = subs_menu
	stats_panel.tv = tv
	add_child(stats_panel)
	# Commentary captions (and voice, where recorded): broadcast/commentary.gd.
	commentary = ShintyCommentary.new()
	commentary.m = match_node
	commentary.view = view
	add_child(commentary)


func _process(_delta: float) -> void:
	# The pre-match build-up has the screen to itself (broadcast/prematch.gd).
	var build_up: bool = view != null and view.get("prematch") != null
	tv.visible = not build_up
	queue_redraw()


func _draw() -> void:
	var m := match_node
	if view != null and view.get("prematch") != null:
		return
	var teams: Array = m.teams
	var screen := get_viewport_rect().size
	var w := screen.x
	if tv.replay_active or subs_menu.is_open():
		return  # a replay shows only the TV graphics; the subs screen covers the rest
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
			if m.charge_kind == "shoot":
				# The sweet spot: let go here for a banger.
				var z: float = m.BANGER_TIMING
				var hot: bool = m.charge >= z and m.charge <= 1.0
				draw_rect(Rect2(c + Vector2(40 * z, -2), Vector2(40 * (1.0 - z), 10)), Color(1, 1, 1, 0.9 if hot else 0.45), false, 1.0)
			if m.charge > 1.0:
				# Overswing: no extra power, just more chance of a miss-hit.
				draw_rect(Rect2(c + Vector2(40, 0), Vector2(40 * (m.charge - 1.0), 6)), Color(0.9, 0.1, 0.1))
	_draw_weather(Vector2(w - 250, 104))
	var help := _hint(
		"Move L Stick   Pass/Poke A   Shoot B   Long hit X   Through/Block Y   Sprint RT   Shield LT   Switch LB   Cleek RB   Barge L3   Pause Start",
		"Move WASD/Arrows   Sprint Shift   Shoot Space/Click   Long hit X   Shield Z   Pass/Poke E   Through/Block F   Cleek C   Barge R   Switch Q   Pause Esc")
	draw_rect(Rect2(Vector2(0, screen.y - 24), Vector2(w, 24)), Color(0, 0, 0, 0.45))
	draw_string(font, Vector2(0, screen.y - 7), help, HORIZONTAL_ALIGNMENT_CENTER, w, 13, Color(1, 1, 1, 0.8))
	var centre_text := ""
	var sub := ""
	if m.paused:
		centre_text = "Paused"
		if m.human_side >= 0:
			sub = _hint("Start to resume    A for team and subs    Back to quit to menu",
				"Esc to resume    Enter for team and subs    M to quit to menu")
		else:
			sub = _hint("Start to resume    Back to quit to menu", "Esc to resume    M to quit to menu")
	elif m.state == m.State.FULL_TIME:
		centre_text = "Full time: %s %d - %d %s" % [teams[0]["name"], m.score[0], m.score[1], teams[1]["name"]]
		sub = _hint("Press A for the menu", "Press Space or Enter for the menu")
	elif m.message_timer > 0.0 and not m.message.begins_with("GOAL"):  # the TV graphics show goals
		# Calls in play (a shy, a foul, a save) sit small in the bottom left,
		# above the player panel, out of the way of the play.
		var lines: PackedStringArray = m.message.split("\n", true, 1)
		var head := lines[0]
		var note := lines[1] if lines.size() > 1 else ""
		var bw: float = max(font.get_string_size(head, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x,
			font.get_string_size(note, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x) + 28
		var bh := 56.0 if note != "" else 36.0
		var box := Rect2(Vector2(20, screen.y - 74 - bh), Vector2(min(bw, w * 0.45), bh))
		draw_rect(box, Color(0, 0, 0, 0.6))
		draw_rect(Rect2(box.position, Vector2(4, bh)), Color(1, 0.85, 0.2, 0.9))
		draw_string(font, box.position + Vector2(14, 25), head, HORIZONTAL_ALIGNMENT_LEFT, box.size.x - 20, 20, Color.WHITE)
		if note != "":
			draw_string(font, box.position + Vector2(14, 46), note, HORIZONTAL_ALIGNMENT_LEFT, box.size.x - 20, 13, Color(1, 1, 1, 0.8))
	if centre_text != "" and not stats_panel.is_showing():   # the stats screen has its own title and buttons
		var box := Rect2(Vector2(w / 2.0 - 330, screen.y / 2.0 - 40), Vector2(660, 80 if sub != "" else 56))
		draw_rect(box, Color(0, 0, 0, 0.65))
		var size := 28
		while size > 16 and font.get_string_size(centre_text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > box.size.x - 20:
			size -= 2   # e.g. full time between two long club names
		draw_string(font, box.position + Vector2(0, 38), centre_text, HORIZONTAL_ALIGNMENT_CENTER, box.size.x, size, Color.WHITE)
		if sub != "":
			draw_string(font, box.position + Vector2(0, 66), sub, HORIZONTAL_ALIGNMENT_CENTER, box.size.x, 15, Color(1, 1, 1, 0.8))
	if m.paused and view != null and view.get("director") != null:
		# Which camera, under the pause box: Y changes it, R3 zooms (match_view.gd).
		var cam: ShintyTVCamera = view.director.camera
		var line := "Camera: %s     Y / Tab  change camera     R3 / V  zoom %s" % [
			Game.CAMERA_NAMES[cam.view], "out" if cam.zoomed else "in"]
		var cb := Rect2(Vector2(w / 2.0 - 330, screen.y / 2.0 + 48), Vector2(660, 30))
		draw_rect(cb, Color(0, 0, 0, 0.65))
		draw_string(font, cb.position + Vector2(0, 21), line, HORIZONTAL_ALIGNMENT_CENTER, cb.size.x, 15, Color(1, 0.85, 0.2))


## The pitch and the wind, with an arrow showing which way it blows on screen.
func _draw_weather(at: Vector2) -> void:
	var m := match_node
	if m.weather.is_empty() or m.weather.get("kind", -1) < 0:
		return
	draw_string(font, at + Vector2(0, 0), ShintyWeather.describe(m.weather), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.85))
	var wind: Vector2 = ShintyWeather.wind_at(m.weather, m.weather_t)
	if wind.length() < 1.0 or view == null:
		return
	var mid: Vector2 = m.PITCH / 2.0
	var dir: Vector2 = view.screen_pos(mid + wind.normalized() * 10.0, 0.0) - view.screen_pos(mid, 0.0)
	if dir.length() < 0.5:
		return
	dir = dir.normalized()
	var c := at + Vector2(-16, -4)
	var tip := c + dir * 9.0
	var col := Color(1, 1, 1, 0.85)
	draw_line(c - dir * 9.0, tip, col, 2.0)
	draw_line(tip, tip - dir.rotated(0.5) * 6.0, col, 2.0)
	draw_line(tip, tip - dir.rotated(-0.5) * 6.0, col, 2.0)


func _panel_text(pos: Vector2, text: String, font_size: int) -> void:
	var sz := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	draw_rect(Rect2(pos - Vector2(8, font_size + 4), sz + Vector2(16, 10)), Color(0, 0, 0, 0.5))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)


## The on-screen hint for the device picked in Settings. Looks the Game
## autoload up at run time: this script is also compiled by headless tests
## before the autoloads exist, where `Game.hint` would not resolve.
func _hint(pad: String, keys: String) -> String:
	var game := get_node_or_null("/root/Game")
	return game.hint(pad, keys) if game else pad
