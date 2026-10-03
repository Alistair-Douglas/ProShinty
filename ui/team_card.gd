class_name ShintyTeamCard
extends Control
## One side of the team select: crest, club, overall rating, stars and the
## attack / midfield / defence split. Focus it and press left/right (or click
## the arrows, or scroll) to change club.

signal changed(index: int)
## Same as picking from a dropdown (OptionButton), for tests that drive the menu.
signal item_selected(index: int)

const TeamData := preload("res://scripts/team_data.gd")

var side_label := "HOME"
var controlled := false:
	set(v):
		controlled = v
		queue_redraw()
var teams: Array = []
var selected := 0:
	set(v):
		selected = posmod(v, maxi(teams.size(), 1))
		_refresh()

var item_count: int:
	get: return teams.size()

var _crest: ShintyCrest
var _lines := {}


func _init(p_side := "HOME", p_teams: Array = [], p_selected := 0) -> void:
	side_label = p_side
	teams = p_teams
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size = Vector2(420, 356)
	_crest = ShintyCrest.new()
	_crest.position = Vector2(26, 70)
	_crest.size = Vector2(132, 150)
	add_child(_crest)
	mouse_entered.connect(grab_focus)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	selected = p_selected
	item_selected.connect(func(i): changed.emit(i))


func select(i: int) -> void:
	selected = i


func team() -> Dictionary:
	return teams[selected] if not teams.is_empty() else {}


func step(dir: int) -> void:
	selected = selected + dir
	_tick()
	changed.emit(selected)


func _refresh() -> void:
	if teams.is_empty():
		return
	var t := team()
	_crest.team = t
	# Average rating per line of the starting twelve.
	var sums := {"ATT": [0, 0], "MID": [0, 0], "DEF": [0, 0]}
	for p in TeamData.starting_twelve(t):
		var role: String = TeamData.ROLE.get(p["position"], "MID")
		var key: String = {"FWD": "ATT", "MID": "MID", "DEF": "DEF", "GK": "DEF"}[role]
		sums[key][0] += int(p["overall"])
		sums[key][1] += 1
	for k in sums:
		_lines[k] = roundi(float(sums[k][0]) / maxi(sums[k][1], 1))
	queue_redraw()


func _tick() -> void:
	var music := get_node_or_null("/root/Music")
	if music:
		music.tick(1.25)


func _gui_input(e: InputEvent) -> void:
	# A controller's right stick and bumpers change the value, and its left
	# stick and d-pad move between controls, so it never gets stuck here.
	# The keyboard's arrows still change it.
	if e.is_action_pressed("menu_prev", true):
		step(-1)
		accept_event()
	elif e.is_action_pressed("menu_next", true):
		step(1)
		accept_event()
	elif e is InputEventKey and e.is_action_pressed("ui_left", true):
		step(-1)
		accept_event()
	elif e is InputEventKey and e.is_action_pressed("ui_right", true):
		step(1)
		accept_event()
	elif e is InputEventMouseButton and e.pressed:
		match e.button_index:
			MOUSE_BUTTON_LEFT:
				if e.position.x < 40 or e.position.x > size.x - 40:
					step(-1 if e.position.x < size.x * 0.5 else 1)
				accept_event()
			MOUSE_BUTTON_WHEEL_UP:
				step(-1)
				accept_event()
			MOUSE_BUTTON_WHEEL_DOWN:
				step(1)
				accept_event()


func _draw() -> void:
	if teams.is_empty():
		return
	var t := team()
	var c: Dictionary = t.get("colors", {})
	var primary := Color(str(c.get("primary", "#33414a")))
	var secondary := Color(str(c.get("secondary", "#f2f2f2")))
	var focused := has_focus()
	var w := size.x
	var h := size.y

	# Card body with the club colour sweeping in from the top right.
	draw_rect(Rect2(0, 0, w, h), ShintyStyle.PANEL)
	var sweep := PackedVector2Array([Vector2(w * 0.42, 0), Vector2(w, 0), Vector2(w, h * 0.62), Vector2(w * 0.78, h * 0.62)])
	draw_colored_polygon(sweep, Color(primary, 0.55))
	var stripe := PackedVector2Array([Vector2(w * 0.36, 0), Vector2(w * 0.42, 0), Vector2(w * 0.78, h * 0.62), Vector2(w * 0.72, h * 0.62)])
	draw_colored_polygon(stripe, Color(secondary, 0.7))
	draw_rect(Rect2(0, 0, w, 44), Color(0, 0, 0, 0.35))
	draw_rect(Rect2(0, h - 4, w, 4), primary)

	# Header: side and who controls it.
	var bold := ShintyStyle.font("bold")
	var black := ShintyStyle.font("black")
	draw_string(bold, Vector2(22, 30), side_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, ShintyStyle.MUTED)
	var who := "YOU" if controlled else "CPU"
	var tag_w := 58.0
	var tag := ShintyStyle.box(ShintyStyle.GOLD if controlled else Color(1, 1, 1, 0.16), ShintyStyle.SLANT)
	draw_style_box(tag, Rect2(w - tag_w - 22, 10, tag_w, 24))
	draw_string(bold, Vector2(w - tag_w - 22, 29), who, HORIZONTAL_ALIGNMENT_CENTER, tag_w, 18,
		ShintyStyle.GOLD_DARK if controlled else ShintyStyle.TEXT)

	# Name, shrunk to fit.
	var name := str(t.get("name", "")).to_upper()
	var fs := 44
	while fs > 22 and black.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > w - 190:
		fs -= 1
	var shadow := Color(0, 0, 0, 0.5)
	draw_string(black, Vector2(176, 104), name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, shadow)
	draw_string(black, Vector2(174, 102), name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ShintyStyle.TEXT)
	var where := str(t.get("ground", ""))
	if where == "":
		where = str(t.get("location", ""))
	draw_string(ShintyStyle.font("medium"), Vector2(176, 130), where.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, w - 200, 17, Color(1, 1, 1, 0.75))

	# Overall and stars.
	var ovr := int(t.get("overall", 0))
	draw_string(black, Vector2(174, 196), str(ovr), HORIZONTAL_ALIGNMENT_LEFT, -1, 64, ShintyStyle.rating_color(ovr))
	draw_string(bold, Vector2(252, 172), "OVR", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, ShintyStyle.MUTED)
	_draw_stars(Vector2(254, 188), ShintyStyle.stars(ovr))

	# Line ratings.
	var y := 244.0
	for k in ["ATT", "MID", "DEF"]:
		var v: int = _lines.get(k, 0)
		draw_string(bold, Vector2(28, y + 15), k, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, ShintyStyle.MUTED)
		draw_string(black, Vector2(w - 70, y + 16), str(v), HORIZONTAL_ALIGNMENT_RIGHT, 44, 22, ShintyStyle.TEXT)
		var bar := Rect2(78, y + 5, w - 170, 10)
		draw_rect(bar, Color(1, 1, 1, 0.1))
		var fill := clampf((v - 40.0) / 50.0, 0.04, 1.0)
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * fill, bar.size.y)), ShintyStyle.rating_color(v))
		y += 32.0

	# Change-club arrows, and a gold frame while focused.
	var mid := h * 0.42
	var a := Color(ShintyStyle.GOLD if focused else ShintyStyle.TEXT, 0.95 if focused else 0.45)
	for dir in [-1, 1]:
		var x := 12.0 if dir < 0 else w - 12.0
		draw_colored_polygon(PackedVector2Array([
			Vector2(x, mid), Vector2(x - dir * 12, mid - 14), Vector2(x - dir * 12, mid + 14)]), a)
	if focused:
		draw_rect(Rect2(1.5, 1.5, w - 3, h - 3), ShintyStyle.GOLD, false, 3.0)


func _draw_stars(at: Vector2, n: float) -> void:
	for i in 5:
		var fill := clampf(n - i, 0.0, 1.0)
		var cpos := at + Vector2(i * 26 + 10, 0)
		var pts := PackedVector2Array()
		for k in 10:
			var r := 11.0 if k % 2 == 0 else 4.6
			var ang := -PI / 2.0 + k * PI / 5.0
			pts.append(cpos + Vector2(cos(ang), sin(ang)) * r)
		draw_colored_polygon(pts, Color(1, 1, 1, 0.16))
		if fill >= 1.0:
			draw_colored_polygon(pts, ShintyStyle.GOLD)
		elif fill > 0.0:
			# Half star: left half only.
			var half := Geometry2D.intersect_polygons(pts, PackedVector2Array([
				cpos + Vector2(-12, -12), cpos + Vector2(0, -12), cpos + Vector2(0, 12), cpos + Vector2(-12, 12)]))
			for poly in half:
				draw_colored_polygon(poly, ShintyStyle.GOLD)
