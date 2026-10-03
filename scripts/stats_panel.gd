extends Control
## The match stats screen: both clubs side by side with their crests, then
## goals, shots, possession, passes, tackles, fouls, free hits, cards, saves,
## corners and bye-hits (counted by match_stats.gd). It comes up on the pause
## screen, at half time (and the breaks in extra time) and at full time.
##
## At a break the match waits on it: once the players are off, A / Enter
## starts the next half. A match with nobody at the controls carries on by
## itself after a few seconds. Full time and the pause screen keep their own
## buttons (the match and the team screen handle those).

const TeamData := preload("res://scripts/team_data.gd")
const MatchStats := preload("res://scripts/match_stats.gd")

const W := 640.0
const TITLE_H := 34.0
const HEAD_H := 92.0
const ROW_H := 29.0
const FOOT_H := 44.0
const AUTO_CONTINUE := 6.0   ## seconds a computer-only match waits at a break

var match_node: Node
var subs_menu: Control       ## the team screen covers the stats while it's open
var tv: Node                 ## the TV graphics: its half/full-time strap is hidden while the stats are up
var stats: MatchStats

var _continued := false      ## the player has said go on from this break
var _waited := 0.0
var _crests: Array = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	if stats == null:
		stats = MatchStats.new(match_node)


## Which screen the stats are part of right now: "pause", "half", "full" or "".
func mode() -> String:
	var m := match_node
	if m == null:
		return ""
	if tv != null and tv.get("replay_active"):
		return ""
	if m.paused:
		return "" if subs_menu != null and subs_menu.is_open() else "pause"
	if m.state == m.State.HALF_TIME:
		return "half"
	if m.state == m.State.FULL_TIME:
		return "full"
	return ""


func is_showing() -> bool:
	return mode() != ""


func _process(delta: float) -> void:
	var m := match_node
	if m == null:
		return
	stats.update()
	if m.state == m.State.HALF_TIME:
		# Hold the break, once everyone has walked off, until the player goes on.
		if not m.paused:
			_waited += delta
		if m.human_side < 0 and _waited > m.HALF_TIME_PAUSE + AUTO_CONTINUE:
			_continued = true
		if not _continued and m.state_timer < 0.1:
			m.state_timer = 0.1
	else:
		_continued = false
		_waited = 0.0
	if tv != null and "hide_strap" in tv:
		tv.hide_strap = is_showing()
	queue_redraw()


func _input(event: InputEvent) -> void:
	if mode() != "half" or _continued:
		return
	if event.is_action_pressed("ui_accept") and not event.is_echo():
		_continued = true
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- drawing

func _title() -> String:
	var m := match_node
	match mode():
		"pause":
			return "PAUSED   %d'" % m.match_minute()
		"half":
			if m.half == 1:
				return "HALF TIME"
			if m.half == 2:
				return "FULL TIME: LEVEL. EXTRA TIME NEXT"
			return "HALF TIME IN EXTRA TIME"
		"full":
			return "FULL TIME" if m.half <= 2 else "FULL TIME AFTER EXTRA TIME"
	return ""


## Pad buttons when a pad is in use, else keys (Game.hint once it has one).
func _hint(pad: String, keys: String) -> String:
	var g := get_node_or_null("/root/Game")
	if g != null and g.has_method("hint"):
		return g.hint(pad, keys)
	return pad if Input.get_connected_joypads().size() > 0 else keys


func _footer() -> String:
	var m := match_node
	match mode():
		"pause":
			if m.human_side >= 0:
				return _hint("Start resume    A team and subs    Back quit to menu",
					"Esc resume    Enter team and subs    M quit to menu")
			return _hint("Start resume    Back quit to menu", "Esc resume    M quit to menu")
		"half":
			if _continued:
				return "Teams coming back out..."
			if m.state_timer > 0.1:
				return "Players heading off"
			var next := "extra time" if m.half == 2 else "second half"
			return _hint("A start the %s    Start pause" % next, "Enter start the %s    Esc pause" % next)
		"full":
			return _hint("A back to the menu", "Space / Enter back to the menu")
	return ""


func _draw() -> void:
	if not is_showing():
		return
	var m := match_node
	var screen := get_viewport_rect().size
	var table: Array = stats.rows()
	var h := TITLE_H + HEAD_H + ROW_H * table.size() + 12.0 + FOOT_H
	# Between the score bug at the top and the help bar at the bottom.
	var top := 66.0
	var room := screen.y - top - 30.0
	var k: float = clampf(minf(room / h, (screen.x - 32.0) / W), 0.5, 1.6)
	var origin := Vector2((screen.x - W * k) / 2.0, top + maxf(0.0, (room - h * k) / 2.0))
	draw_set_transform(origin, 0.0, Vector2(k, k))
	if _crests.is_empty():
		_crests = [TeamData.logo(m.teams[0]), TeamData.logo(m.teams[1])]
	var black := ShintyStyle.font("black")
	var bold := ShintyStyle.font("bold")
	var semi := ShintyStyle.font("semibold")

	draw_rect(Rect2(Vector2.ZERO, Vector2(W, h)), Color(0.04, 0.06, 0.08, 0.93))
	draw_rect(Rect2(Vector2.ZERO, Vector2(W, TITLE_H)), ShintyStyle.GOLD)
	draw_string(black, Vector2(0, 25), _title(), HORIZONTAL_ALIGNMENT_CENTER, W, 22, ShintyStyle.GOLD_DARK)

	# The two clubs, crests on the outside, the score between them.
	var y := TITLE_H
	for side in 2:
		var team: Dictionary = m.teams[side]
		var col: Color = m.colors[side][0]
		var cx := 18.0 if side == 0 else W - 18.0 - 64.0
		var crest := Rect2(Vector2(cx, y + 14), Vector2(64, 64))
		if _crests[side] != null:
			var ts: Vector2 = _crests[side].get_size()
			var f := minf(64.0 / ts.x, 64.0 / ts.y)
			var d := ts * f
			draw_texture_rect(_crests[side], Rect2(crest.position + (crest.size - d) / 2.0, d), false)
		else:
			draw_circle(crest.get_center(), 30.0, col)
			draw_string(black, Vector2(crest.position.x, crest.position.y + 42), ShintyCrest.initials(team),
				HORIZONTAL_ALIGNMENT_CENTER, 64, 22, ShintyStyle.text_on(col))
		var club := str(team["name"]).to_upper()
		var nx := 92.0 if side == 0 else W / 2.0 + 52.0
		var nw := W / 2.0 - 52.0 - 92.0
		var fs := 24
		while fs > 14 and black.get_string_size(club, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > nw:
			fs -= 2
		draw_string(black, Vector2(nx, y + 50), club, HORIZONTAL_ALIGNMENT_LEFT if side == 0 else HORIZONTAL_ALIGNMENT_RIGHT,
			nw, fs, Color.WHITE)
		draw_rect(Rect2(Vector2(nx if side == 0 else nx + nw - 70.0, y + 60), Vector2(70, 5)), col)
	draw_string(black, Vector2(0, y + 58), "%d - %d" % [m.score[0], m.score[1]], HORIZONTAL_ALIGNMENT_CENTER, W, 40, Color.WHITE)

	# The stats, one row each: home on the left, away on the right, and a bar
	# showing how they compare in each side's colours.
	y += HEAD_H
	draw_rect(Rect2(Vector2(18, y - 4), Vector2(W - 36, 1)), ShintyStyle.LINE)
	for i in table.size():
		var row: Array = table[i]
		var ry := y + i * ROW_H
		if i % 2 == 1:
			draw_rect(Rect2(Vector2(10, ry), Vector2(W - 20, ROW_H)), Color(1, 1, 1, 0.035))
		var a: int = row[1]
		var b: int = row[2]
		var ca := ShintyStyle.TEXT if a >= b else ShintyStyle.MUTED
		var cb := ShintyStyle.TEXT if b >= a else ShintyStyle.MUTED
		draw_string(bold, Vector2(28, ry + 21), str(a), HORIZONTAL_ALIGNMENT_LEFT, 80, 20, ca)
		draw_string(bold, Vector2(W - 108, ry + 21), str(b), HORIZONTAL_ALIGNMENT_RIGHT, 80, 20, cb)
		draw_string(semi, Vector2(0, ry + 17), str(row[0]), HORIZONTAL_ALIGNMENT_CENTER, W, 16, ShintyStyle.MUTED)
		if row[3]:
			var bx := 150.0
			var bw := W - 300.0
			var by := ry + 22.0
			draw_rect(Rect2(Vector2(bx, by), Vector2(bw, 3)), Color(1, 1, 1, 0.08))
			if a + b > 0:
				var split := bw * float(a) / float(a + b)
				draw_rect(Rect2(Vector2(bx, by), Vector2(split, 3)), _bar(m.colors[0][0]))
				draw_rect(Rect2(Vector2(bx + split, by), Vector2(bw - split, 3)), _bar(m.colors[1][0]))

	var fy := h - FOOT_H
	draw_rect(Rect2(Vector2(0, fy), Vector2(W, FOOT_H)), Color(0, 0, 0, 0.35))
	draw_string(bold, Vector2(0, fy + 28), _footer(), HORIZONTAL_ALIGNMENT_CENTER, W, 17, ShintyStyle.TEXT)
	draw_set_transform(Vector2.ZERO)


## A kit colour that still shows on the dark panel.
func _bar(c: Color) -> Color:
	return c.lightened(0.35) if c.get_luminance() < 0.18 else c
