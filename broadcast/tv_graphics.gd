class_name ShintyTVGraphics
extends Control
## TV graphics over the match: the score bug and match clock (top left), the
## channel mark with LIVE or REPLAY (top right), a GOAL banner, half-time and
## full-time straps, the substitution board, and the swipe that runs in and
## out of replays.

const TeamData := preload("res://scripts/team_data.gd")

var match_node: Node
var replay_active := false
## Shown under a replay (e.g. the foul it shows); empty for none.
var replay_caption := ""
## Whether the "Skip" hint shows during replays.
var show_skip_hint := true
var hide_strap := false   ## the stats screen (scripts/stats_panel.gd) is up instead

var _goal_t := -1.0
var _goal_team := 0
var _wipe_t := -1.0
var _wipe_mid: Callable
var _wipe_fired := false
var _crests: Array = []
var _time := 0.0
var _subs_seen := 0
var _sub_t := -1.0
var _sub: Dictionary = {}

const SUB_SHOW := 5.0   ## seconds the substitution board stays up


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS


## Show the GOAL banner for `team`.
func show_goal(team: int) -> void:
	_goal_t = 0.0
	_goal_team = team


## Run the swipe; `at_middle` is called when the screen is covered.
func wipe(at_middle: Callable) -> void:
	_wipe_t = 0.0
	_wipe_mid = at_middle
	_wipe_fired = false


func _process(delta: float) -> void:
	_time += delta
	_watch_subs(delta)
	if _goal_t >= 0.0:
		_goal_t += delta
		if _goal_t > 2.6 or replay_active:
			_goal_t = -1.0
	if _wipe_t >= 0.0:
		_wipe_t += delta
		if _wipe_t >= 0.32 and not _wipe_fired:
			_wipe_fired = true
			if _wipe_mid.is_valid():
				_wipe_mid.call()
		if _wipe_t > 0.7:
			_wipe_t = -1.0
	queue_redraw()


func _team_short(t: Dictionary) -> String:
	var s := str(t.get("short", ""))
	return s.to_upper() if s != "" else str(t.get("name", "?")).left(3).to_upper()


func _clock_text() -> String:
	var m := match_node
	var secs := int(m.match_seconds())
	return "%02d:%02d" % [secs / 60, secs % 60]


func _draw() -> void:
	var m := match_node
	if m == null:
		return
	if _crests.is_empty():
		_crests = [TeamData.logo(m.teams[0]), TeamData.logo(m.teams[1])]
	var screen := get_viewport_rect().size
	_draw_bug(m)
	_draw_channel(screen)
	if _goal_t >= 0.0:
		_draw_goal(m, screen)
	elif not replay_active and not hide_strap and (m.state == m.State.HALF_TIME or m.state == m.State.FULL_TIME):
		var strap := "FULL TIME"
		if m.state == m.State.HALF_TIME:
			strap = "EXTRA TIME" if m.half == 2 else "HALF TIME"
		_draw_strap(m, screen, strap)
	if _sub_t >= 0.0 and not replay_active:
		_draw_sub(m, screen)
	if replay_active:
		_draw_replay_strip(screen)
	_draw_wipe(screen)


## During a replay: what it shows (bottom left) and how to skip it (bottom right).
func _draw_replay_strip(screen: Vector2) -> void:
	var bold := ShintyStyle.font("bold")
	var black := ShintyStyle.font("black")
	var y := screen.y - 64.0
	if replay_caption != "":
		var cw := bold.get_string_size(replay_caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x + 40.0
		draw_style_box(ShintyStyle.box(Color(0.05, 0.07, 0.09, 0.85), ShintyStyle.SLANT), Rect2(28, y, cw, 34))
		draw_string(bold, Vector2(48, y + 24), replay_caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)
	if not show_skip_hint:
		return
	var key := "A / ENTER"
	var kw := black.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x + 20.0
	var w := kw + 76.0
	var x := screen.x - 28.0 - w
	draw_style_box(ShintyStyle.box(Color(0.05, 0.07, 0.09, 0.85), ShintyStyle.SLANT), Rect2(x, y, w, 34))
	draw_style_box(ShintyStyle.box(ShintyStyle.GOLD, ShintyStyle.SLANT), Rect2(x + 8, y + 6, kw, 22))
	draw_string(black, Vector2(x + 8, y + 23), key, HORIZONTAL_ALIGNMENT_CENTER, kw, 16, ShintyStyle.GOLD_DARK)
	draw_string(bold, Vector2(x + kw + 18, y + 24), "Skip", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)


## Put the board up for each change the match makes, one after the other.
func _watch_subs(delta: float) -> void:
	var s = match_node.get("subs") if match_node != null else null
	if s == null:
		return
	if _sub_t >= 0.0:
		_sub_t += delta
		if _sub_t > SUB_SHOW:
			_sub_t = -1.0
	if _sub_t < 0.0 and _subs_seen < s.made.size():
		_sub = s.made[_subs_seen]
		_subs_seen += 1
		_sub_t = 0.0


# --- Score bug -----------------------------------------------------------------------

func _draw_bug(m) -> void:
	var bold := ShintyStyle.font("bold")
	var black := ShintyStyle.font("black")
	var x := 28.0
	var y := 22.0
	var h := 36.0
	# Channel chip
	draw_rect(Rect2(x, y, 44, h), ShintyStyle.GOLD)
	draw_string(black, Vector2(x, y + 27), "PS", HORIZONTAL_ALIGNMENT_CENTER, 44, 22, ShintyStyle.GOLD_DARK)
	x += 44
	for side in 2:
		var team: Dictionary = m.teams[side]
		var col: Color = m.colors[side][0]
		var box_w := 82.0
		draw_rect(Rect2(x, y, box_w, h), Color(0.05, 0.07, 0.09, 0.92))
		draw_rect(Rect2(x if side == 0 else x + box_w - 6, y, 6, h), col)
		var tx := x + (12.0 if side == 0 else 6.0)
		if _crests[side] != null:
			var cr := Rect2(Vector2(x + (10 if side == 0 else box_w - 36), y + 5), Vector2(26, 26))
			draw_texture_rect(_crests[side], cr, false)
			tx = x + (40.0 if side == 0 else 8.0)
		draw_string(bold, Vector2(tx, y + 26), _team_short(team), HORIZONTAL_ALIGNMENT_LEFT, 44, 21, Color.WHITE)
		x += box_w
		if side == 0:
			# Score
			draw_rect(Rect2(x, y, 70, h), Color(0.95, 0.96, 0.97))
			draw_string(black, Vector2(x, y + 28), "%d - %d" % [m.score[0], m.score[1]], HORIZONTAL_ALIGNMENT_CENTER, 70, 25, Color(0.05, 0.07, 0.09))
			x += 70
	# Clock
	draw_rect(Rect2(x, y, 78, h), Color(0.12, 0.16, 0.19, 0.92))
	draw_string(bold, Vector2(x, y + 26), _clock_text(), HORIZONTAL_ALIGNMENT_CENTER, 78, 21, Color.WHITE)
	x += 78
	draw_rect(Rect2(x, y, 34, h), Color(0.12, 0.16, 0.19, 0.75))
	draw_string(bold, Vector2(x, y + 25), ("%dH" % m.half if m.half <= 2 else "ET"), HORIZONTAL_ALIGNMENT_CENTER, 34, 16, ShintyStyle.MUTED)
	# Cards under each team's box
	var ref = m.get("referee")
	if ref != null and ref.has_method("team_cards"):
		for t in 2:
			var n := 0
			var bx := 28.0 + 44.0 + (0.0 if t == 0 else 82.0 + 70.0)
			for colour in ["yellow", "red"]:
				var c := Color(1.0, 0.85, 0.1) if colour == "yellow" else Color(0.9, 0.1, 0.1)
				for i in ref.team_cards(t, colour):
					draw_rect(Rect2(Vector2(bx + 8 + n * 11, y + h + 4), Vector2(8, 12)), c)
					n += 1


func _draw_channel(screen: Vector2) -> void:
	var bold := ShintyStyle.font("bold")
	var black := ShintyStyle.font("black")
	var x := screen.x - 28.0
	var label := "REPLAY" if replay_active else "LIVE"
	var lw := 86.0
	var r := Rect2(x - lw, 22, lw, 30)
	draw_style_box(ShintyStyle.box(ShintyStyle.GOLD if replay_active else Color(0.8, 0.1, 0.12), ShintyStyle.SLANT), r)
	if not replay_active:
		var pulse := 0.6 + 0.4 * absf(sin(_time * 2.5))
		draw_circle(r.position + Vector2(18, 15), 5.0, Color(1, 1, 1, pulse))
	draw_string(black, r.position + Vector2(8 if replay_active else 18, 23), label, HORIZONTAL_ALIGNMENT_CENTER, lw - 16 - (0 if replay_active else 10), 20,
		ShintyStyle.GOLD_DARK if replay_active else Color.WHITE)
	draw_string(black, Vector2(x - lw - 150, 44), "PRO", HORIZONTAL_ALIGNMENT_RIGHT, 60, 20, Color(ShintyStyle.GOLD, 0.9))
	draw_string(black, Vector2(x - lw - 88, 44), "SHINTY TV", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1, 0.9))


# --- Banners ---------------------------------------------------------------------------

func _draw_goal(m, screen: Vector2) -> void:
	var t := _goal_t
	var inn := ease(clampf(t / 0.35, 0.0, 1.0), -2.5)
	var out := ease(clampf((t - 2.2) / 0.4, 0.0, 1.0), 2.0)
	var slide := (1.0 - inn) * -screen.x + out * screen.x
	var col: Color = m.colors[_goal_team][0]
	var y := screen.y - 190.0
	var black := ShintyStyle.font("black")
	var bold := ShintyStyle.font("bold")
	# Team-colour band with a gold edge, and the word GOAL across it.
	var band := Rect2(Vector2(slide - 40, y), Vector2(screen.x * 0.72, 92))
	draw_style_box(ShintyStyle.box(Color(col, 0.95), ShintyStyle.SLANT), band)
	draw_style_box(ShintyStyle.box(ShintyStyle.GOLD, ShintyStyle.SLANT), Rect2(band.position + Vector2(0, 92), Vector2(band.size.x, 6)))
	var gx := slide + 70.0
	var scale := 1.0 + 0.08 * sin(clampf(t * 6.0, 0.0, PI))
	var gs := int(84 * scale)
	var text_col := Color.WHITE if col.get_luminance() < 0.6 else ShintyStyle.GOLD_DARK
	draw_string(black, Vector2(gx + 3, y + 78 + 3), "GOAL!", HORIZONTAL_ALIGNMENT_LEFT, -1, gs, Color(0, 0, 0, 0.35))
	draw_string(black, Vector2(gx, y + 78), "GOAL!", HORIZONTAL_ALIGNMENT_LEFT, -1, gs, text_col)
	var tx := gx + black.get_string_size("GOAL!", HORIZONTAL_ALIGNMENT_LEFT, -1, gs).x + 34
	if _crests[_goal_team] != null:
		draw_texture_rect(_crests[_goal_team], Rect2(Vector2(tx, y + 12), Vector2(68, 68)), false)
		tx += 84
	draw_string(black, Vector2(tx, y + 50), str(m.teams[_goal_team]["name"]).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 34, text_col)
	draw_string(bold, Vector2(tx, y + 80), "%s %d - %d %s" % [_team_short(m.teams[0]), m.score[0], m.score[1], _team_short(m.teams[1])],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(text_col, 0.85))


func _draw_strap(m, screen: Vector2, title: String) -> void:
	var black := ShintyStyle.font("black")
	var bold := ShintyStyle.font("bold")
	var w := 560.0
	var r := Rect2(Vector2((screen.x - w) / 2.0, screen.y - 170), Vector2(w, 96))
	draw_rect(r, Color(0.04, 0.06, 0.08, 0.92))
	draw_rect(Rect2(r.position, Vector2(w, 30)), ShintyStyle.GOLD)
	draw_string(black, r.position + Vector2(0, 24), title, HORIZONTAL_ALIGNMENT_CENTER, w, 22, ShintyStyle.GOLD_DARK)
	for side in 2:
		var cx := r.position.x + (40.0 if side == 0 else w - 40.0 - 180.0)
		draw_string(black, Vector2(cx, r.position.y + 76), str(m.teams[side]["name"]).to_upper(),
			HORIZONTAL_ALIGNMENT_LEFT if side == 0 else HORIZONTAL_ALIGNMENT_RIGHT, 180, 26, Color.WHITE)
	draw_string(black, Vector2(r.position.x, r.position.y + 80), "%d - %d" % [m.score[0], m.score[1]], HORIZONTAL_ALIGNMENT_CENTER, w, 36, Color.WHITE)


## The substitution board, bottom left: the team, then the player going off
## (red, arrow down) and the one coming on (green, arrow up). Slides in and out.
func _draw_sub(m, screen: Vector2) -> void:
	var t := _sub_t
	var inn := ease(clampf(t / 0.35, 0.0, 1.0), -2.5)
	var out := ease(clampf((t - (SUB_SHOW - 0.4)) / 0.4, 0.0, 1.0), 2.0)
	var black := ShintyStyle.font("black")
	var bold := ShintyStyle.font("bold")
	var team: int = _sub["team"]
	var w := 420.0
	var x := 28.0 - (1.0 - inn + out) * (w + 40.0)
	var y := screen.y - 250.0
	var col: Color = m.colors[team][0]
	draw_rect(Rect2(x, y, w, 34), ShintyStyle.GOLD)
	draw_string(black, Vector2(x + 14, y + 25), "SUBSTITUTION", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, ShintyStyle.GOLD_DARK)
	draw_string(bold, Vector2(x, y + 25), "%d'" % int(_sub["minute"]), HORIZONTAL_ALIGNMENT_RIGHT, w - 14, 18, ShintyStyle.GOLD_DARK)
	draw_rect(Rect2(x, y + 34, w, 36), Color(0.05, 0.07, 0.09, 0.94))
	draw_rect(Rect2(x, y + 34, 6, 36), col)
	var tx := x + 16.0
	if _crests[team] != null:
		draw_texture_rect(_crests[team], Rect2(Vector2(tx, y + 38), Vector2(28, 28)), false)
		tx += 36.0
	draw_string(bold, Vector2(tx, y + 60), str(m.teams[team]["name"]).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, w - (tx - x) - 10, 19, Color.WHITE)
	var rows := [[_sub["off"], Color(0.86, 0.16, 0.16), false], [_sub["on"], Color(0.2, 0.75, 0.3), true]]
	for i in 2:
		var ry := y + 70.0 + i * 34.0
		var pd: Dictionary = rows[i][0]
		var c: Color = rows[i][1]
		draw_rect(Rect2(x, ry, w, 34), Color(0.1, 0.13, 0.16, 0.94))
		draw_rect(Rect2(x, ry, 40, 34), c)
		var cx := x + 20.0
		var up: bool = rows[i][2]
		var tip := Vector2(cx, ry + (8.0 if up else 26.0))
		var base := ry + (24.0 if up else 10.0)
		draw_colored_polygon(PackedVector2Array([tip, Vector2(cx - 9, base), Vector2(cx + 9, base)]), Color.WHITE)
		draw_string(black, Vector2(x + 50, ry + 25), str(int(pd.get("number", 0))), HORIZONTAL_ALIGNMENT_CENTER, 34, 19, c.lightened(0.3))
		draw_string(bold, Vector2(x + 92, ry + 24), str(pd.get("name", "")), HORIZONTAL_ALIGNMENT_LEFT, w - 102, 18, Color.WHITE)


## A slanted dark panel with a gold edge and the channel name sweeps across.
func _draw_wipe(screen: Vector2) -> void:
	if _wipe_t < 0.0:
		return
	var k := _wipe_t / 0.7
	var cx := lerpf(-screen.x * 0.6, screen.x * 1.6, ease(k, -1.8))
	var half := screen.x * 0.55
	var skew := screen.y * 0.35
	var poly := PackedVector2Array([
		Vector2(cx - half + skew, 0), Vector2(cx + half + skew, 0),
		Vector2(cx + half - skew, screen.y), Vector2(cx - half - skew, screen.y)])
	draw_colored_polygon(poly, ShintyStyle.INK)
	var edge := PackedVector2Array([
		Vector2(cx + half + skew, 0), Vector2(cx + half + skew + 26, 0),
		Vector2(cx + half - skew + 26, screen.y), Vector2(cx + half - skew, screen.y)])
	draw_colored_polygon(edge, ShintyStyle.GOLD)
	var black := ShintyStyle.font("black")
	draw_string(black, Vector2(cx - 170, screen.y / 2.0 + 24), "PRO", HORIZONTAL_ALIGNMENT_LEFT, -1, 64, ShintyStyle.GOLD)
	draw_string(black, Vector2(cx - 50, screen.y / 2.0 + 24), "SHINTY", HORIZONTAL_ALIGNMENT_LEFT, -1, 64, Color.WHITE)
	draw_string(black, Vector2(cx - 168, screen.y / 2.0 + 62), "REPLAY" if not replay_active else "BACK TO LIVE", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, ShintyStyle.MUTED)
