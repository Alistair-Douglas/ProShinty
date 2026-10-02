extends Control
## The team screen, opened from the pause screen (A / Enter): your side laid
## out on a pitch in its formation, with the bench beside it. Works with a pad
## or the keyboard: move round the pitch with the stick or arrows, pick the
## player to come off, then who goes on from the bench. The change is made as
## soon as the ball is dead (straight away if it already is). Picking a player
## who is already due off cancels that change. Y / F turns computer-made
## changes on or off for your side. B / Esc goes back.

const TeamData := preload("res://scripts/team_data.gd")

const W := 1000.0
const H := 520.0
const PITCH_SIZE := Vector2(600, 340)
const ROW_H := 44.0

var match_node: Node
var on_bench := false   # focus is on the bench list, not the pitch
var focus = null        # the Player focused on the pitch
var row := 0            # the bench row focused
var picked = null       # the Player chosen to come off
var note := ""          # why the last pick didn't work
var _open := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _subs():
	return match_node.get("subs") if match_node != null else null


func _side() -> int:
	return int(match_node.human_side)


func is_open() -> bool:
	return _open


func open() -> void:
	_open = true
	on_bench = false
	row = 0
	picked = null
	note = ""
	var squad: Array = match_node.squads[_side()]
	focus = match_node.human if match_node.human in squad else (squad[0] if not squad.is_empty() else null)
	_subs().set_menu_open(true)
	queue_redraw()


func close() -> void:
	_open = false
	_subs().set_menu_open(false)
	queue_redraw()


func _process(_delta: float) -> void:
	if _open and not match_node.paused:
		close()
	queue_redraw()


func _input(event: InputEvent) -> void:
	var m := match_node
	if m == null or _subs() == null or _side() < 0:
		return
	if not _open:
		if m.paused and event.is_action_pressed("ui_accept") and not event.is_echo() and not _subs().menu_busy():
			open()
			get_viewport().set_input_as_handled()
		return
	var handled := true
	var dir := Vector2.ZERO
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		if picked != null:
			focus = picked
			picked = null
			on_bench = false
		else:
			close()
	elif event.is_action_pressed("ui_up", true):
		dir = Vector2.UP
	elif event.is_action_pressed("ui_down", true):
		dir = Vector2.DOWN
	elif event.is_action_pressed("ui_left", true):
		dir = Vector2.LEFT
	elif event.is_action_pressed("ui_right", true):
		dir = Vector2.RIGHT
	elif event.is_action_pressed("ui_accept") and not event.is_echo():
		_choose()
	elif event.is_action_pressed("block"):
		var s = _subs()
		s.auto[_side()] = not s.auto[_side()]
	else:
		handled = false
	if dir != Vector2.ZERO:
		_move(dir)
	if handled:
		get_viewport().set_input_as_handled()


## Move the focus: round the pitch towards the nearest player that way, off
## its right-hand end onto the bench, and back again.
func _move(dir: Vector2) -> void:
	var bench: Array = _subs().bench[_side()]
	if on_bench:
		if dir == Vector2.LEFT and picked == null:
			on_bench = false
		elif dir.y != 0.0:
			row = clampi(row + int(dir.y), 0, maxi(bench.size() - 1, 0))
		return
	var squad: Array = match_node.squads[_side()]
	if focus == null or not focus in squad:
		focus = squad[0] if not squad.is_empty() else null
		return
	var from := _spot(focus)
	var best = null
	var best_d := INF
	for p in squad:
		if p == focus:
			continue
		var d := _spot(p) - from
		var along := d.dot(dir)
		if along <= 4.0:
			continue
		var score := along + absf(d.cross(dir)) * 2.0   # prefer straight that way
		if score < best_d:
			best_d = score
			best = p
	if best != null:
		focus = best
	elif dir == Vector2.RIGHT and not bench.is_empty():
		on_bench = true
		row = clampi(row, 0, bench.size() - 1)


func _choose() -> void:
	var s = _subs()
	var t := _side()
	note = ""
	if not on_bench:
		if focus == null:
			return
		if s.pending_for(focus) != null:
			s.cancel(focus)   # changed your mind
			return
		if s.subs_left(t) <= 0:
			note = "No substitutions left"
			return
		if s.bench[t].is_empty():
			note = "Nobody left on the bench"
			return
		picked = focus
		on_bench = true
		var best = s.best_replacement(focus)
		row = maxi(0, s.bench[t].find(best)) if best != null else 0
	else:
		var bench: Array = s.bench[t]
		if picked == null or bench.is_empty():
			on_bench = picked != null
			return
		var why: String = s.request(picked, bench[row])
		if why != "":
			note = why
		focus = picked
		picked = null
		on_bench = false


# ---------------------------------------------------------------- drawing

var _pitch_rect := Rect2()


## Where a player's formation spot is drawn: our goal on the left.
func _spot(p) -> Vector2:
	var f: Vector2 = p.home
	var r := _pitch_rect
	return r.position + Vector2(lerpf(0.05, 0.95, f.x) * r.size.x, lerpf(0.1, 0.9, f.y) * r.size.y)


func _draw() -> void:
	if not _open:
		return
	var m := match_node
	var s = _subs()
	var t := _side()
	var screen := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, screen), Color(0, 0, 0, 0.55))
	var bold := ShintyStyle.font("bold")
	var black := ShintyStyle.font("black")
	var semi := ShintyStyle.font("semibold")
	var o := Vector2((screen.x - W) / 2.0, maxf(16.0, (screen.y - H) / 2.0))
	draw_rect(Rect2(o, Vector2(W, H)), Color(0.04, 0.06, 0.08, 0.95))
	draw_rect(Rect2(o, Vector2(W, 44)), ShintyStyle.GOLD)
	draw_string(black, o + Vector2(18, 33), "TEAM AND SUBSTITUTIONS", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, ShintyStyle.GOLD_DARK)
	draw_string(bold, o + Vector2(0, 31), "%s   ·   %d of %d subs left" % [str(m.teams[t]["name"]).to_upper(), s.subs_left(t), s.MAX_SUBS],
		HORIZONTAL_ALIGNMENT_RIGHT, W - 18, 20, ShintyStyle.GOLD_DARK)
	_pitch_rect = Rect2(o + Vector2(18, 90), PITCH_SIZE)
	draw_string(bold, o + Vector2(18, 78), "FORMATION  (attacking to the right)", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, ShintyStyle.MUTED)
	_draw_pitch(_pitch_rect)
	var kit: Color = m.colors[t][0]
	var trim: Color = m.colors[t][1]
	for p in m.squads[t]:
		_draw_marker(p, kit, trim, s, bold, semi)
	# The bench.
	var bx := o.x + 18 + PITCH_SIZE.x + 24
	var bw := W - (bx - o.x) - 18
	draw_string(bold, Vector2(bx, o.y + 78), "BENCH" if picked == null else "ON FOR %s?" % str(picked.data.get("name", "")).to_upper(),
		HORIZONTAL_ALIGNMENT_LEFT, bw, 17, ShintyStyle.GOLD if picked != null else ShintyStyle.MUTED)
	var bench: Array = s.bench[t]
	if bench.is_empty():
		draw_string(semi, Vector2(bx, o.y + 120), "Nobody left on the bench", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, ShintyStyle.MUTED)
	for i in bench.size():
		var pd: Dictionary = bench[i]
		var r := Rect2(Vector2(bx, o.y + 90 + i * ROW_H), Vector2(bw, ROW_H - 6))
		var focused := on_bench and row == i
		var going: bool = s.pending[t].any(func(q): return q["on"] == pd)
		draw_rect(r, ShintyStyle.PANEL_LIGHT)
		if focused:
			draw_rect(Rect2(r.position, Vector2(4, r.size.y)), ShintyStyle.GOLD)
			draw_rect(r, Color(ShintyStyle.GOLD, 0.9), false, 2.0)
		draw_string(bold, r.position + Vector2(8, 26), str(int(pd.get("number", 0))), HORIZONTAL_ALIGNMENT_RIGHT, 26, 18,
			ShintyStyle.GOLD if focused else ShintyStyle.MUTED)
		draw_string(semi, r.position + Vector2(44, 26), str(pd.get("name", "")), HORIZONTAL_ALIGNMENT_LEFT, 120, 18, Color.WHITE)
		draw_string(bold, r.position + Vector2(166, 26), str(pd.get("position", "")), HORIZONTAL_ALIGNMENT_LEFT, 44, 15, ShintyStyle.MUTED)
		draw_string(bold, r.position + Vector2(0, 26), "GOING ON" if going else "OVR %d" % int(pd.get("overall", 0)),
			HORIZONTAL_ALIGNMENT_RIGHT, bw - 10, 15, ShintyStyle.GOLD if going else ShintyStyle.MUTED)
	# What the focused player is, and the footer.
	var info := ""
	if not on_bench and focus != null and focus in m.squads[t]:
		info = "%d %s   %s   OVR %d   Fitness %d%%" % [focus.number, focus.data.get("name", ""), TeamData.POSITION_NAMES.get(focus.position_code, focus.position_code),
			int(focus.data.get("overall", 0)), roundi(s.legs.get(focus, 1.0) * 100.0)]
		if s.injured.has(focus):
			info += "   INJURED"
	elif on_bench and not bench.is_empty():
		var pd: Dictionary = bench[row]
		info = "%d %s   %s   OVR %d" % [int(pd.get("number", 0)), pd.get("name", ""), TeamData.POSITION_NAMES.get(str(pd.get("position", "")), ""), int(pd.get("overall", 0))]
	draw_string(bold, Vector2(o.x + 18, o.y + H - 74), info, HORIZONTAL_ALIGNMENT_LEFT, W - 36, 18, Color.WHITE)
	var off_names := []
	for pd in s.came_off[t]:
		off_names.append("%d %s" % [int(pd.get("number", 0)), pd.get("name", "")])
	var line := note
	if line == "" and not s.pending[t].is_empty() and not s.ball_dead():
		line = "Changes are made when the ball next goes dead"
	elif line == "" and not off_names.is_empty():
		line = "Off (can't come back on): " + ", ".join(off_names)
	draw_string(semi, Vector2(o.x + 18, o.y + H - 46), line, HORIZONTAL_ALIGNMENT_LEFT, W - 36, 16, ShintyStyle.BAD if note != "" else ShintyStyle.MUTED)
	var help := Game.hint("L Stick move    A pick    B back    Y computer subs: %s", "Arrows move    Enter pick    Esc back    F computer subs: %s") % ("ON" if s.auto[t] else "OFF")
	draw_string(bold, Vector2(o.x + 18, o.y + H - 18), help, HORIZONTAL_ALIGNMENT_LEFT, W - 36, 16, ShintyStyle.TEXT)


func _draw_pitch(r: Rect2) -> void:
	draw_rect(r, Color(0.16, 0.42, 0.2))
	for i in 8:
		if i % 2 == 0:
			draw_rect(Rect2(r.position + Vector2(r.size.x / 8.0 * i, 0), Vector2(r.size.x / 8.0, r.size.y)), Color(1, 1, 1, 0.04))
	var line := Color(1, 1, 1, 0.7)
	draw_rect(r, line, false, 2.0)
	draw_line(r.position + Vector2(r.size.x / 2.0, 0), r.position + Vector2(r.size.x / 2.0, r.size.y), line, 2.0)
	draw_arc(r.get_center(), r.size.y * 0.13, 0, TAU, 40, line, 2.0)
	for end in [0.0, 1.0]:
		var gx: float = r.position.x + end * r.size.x
		var c := Vector2(gx, r.get_center().y)
		draw_arc(c, r.size.y * 0.16, -PI / 2.0 if end == 0.0 else PI / 2.0, PI / 2.0 if end == 0.0 else PI * 1.5, 24, line, 2.0)
		draw_rect(Rect2(c + Vector2(-6 if end == 0.0 else 0, -r.size.y * 0.035), Vector2(6, r.size.y * 0.07)), Color.WHITE)


func _draw_marker(p, kit: Color, trim: Color, s, bold: Font, semi: Font) -> void:
	var c := _spot(p)
	var focused: bool = not on_bench and focus == p
	var is_picked: bool = picked == p
	var going_off = s.pending_for(p)
	if focused or is_picked:
		draw_circle(c, 22.0, ShintyStyle.GOLD)
	draw_circle(c, 17.0, trim)
	draw_circle(c, 15.0, kit)
	var num_col := Color.WHITE if kit.get_luminance() < 0.6 else Color(0.05, 0.07, 0.09)
	draw_string(bold, c + Vector2(-20, 7), str(p.number), HORIZONTAL_ALIGNMENT_CENTER, 40, 19, num_col)
	var name := str(p.data.get("name", ""))
	draw_string(semi, c + Vector2(-50, 36), name, HORIZONTAL_ALIGNMENT_CENTER, 100, 14, Color.WHITE)
	# Fitness under the name.
	var legs: float = s.legs.get(p, 1.0)
	var bar := Rect2(c + Vector2(-18, 41), Vector2(36, 4))
	draw_rect(bar, Color(0, 0, 0, 0.5))
	var fc := ShintyStyle.GOOD if legs > 0.8 else (ShintyStyle.GOLD if legs > 0.65 else ShintyStyle.BAD)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * legs, bar.size.y)), fc)
	if going_off != null:
		_tag(c + Vector2(12, -26), "OFF: %d" % int(going_off["on"].get("number", 0)), ShintyStyle.GOLD, bold)
	elif s.injured.has(p):
		_tag(c + Vector2(12, -26), "INJURED", ShintyStyle.BAD, bold)


func _tag(at: Vector2, text: String, c: Color, font: Font) -> void:
	var sz := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
	draw_rect(Rect2(at, sz + Vector2(8, 2)), c)
	draw_string(font, at + Vector2(4, 13), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, ShintyStyle.GOLD_DARK if c == ShintyStyle.GOLD else Color.WHITE)
