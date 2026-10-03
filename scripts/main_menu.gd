extends Control
## Main menu. A live 3D scene of the chosen ground sits behind four screens:
##   hub       Play match, Squads, Controls, Quit
##   kickoff   pick both clubs, the pitch, your side, difficulty and half length
##   squads    browse every club's players and ratings
##   controls  keyboard and controller buttons
##   camans    the caman designer: build a stick on a bench by the pitch and
##             give it to a club (the club's players carry it in matches)
## Play match goes through the loading screen (scenes/loading.tscn).

const TeamData := preload("res://scripts/team_data.gd")
const OverlayShader := preload("res://ui/menu_overlay.gdshader")
const TartanShader := preload("res://ui/tartan.gdshader")
const HALF_LENGTHS := [2, 3, 5, 10]

var backdrop: ShintyMenuBackdrop
var overlay: ColorRect
var screens := {}
var current := ""
var screen_title: Label
var hints: Label

# Kick-off screen
var home_pick: ShintyTeamCard
var away_pick: ShintyTeamCard
var pitch_pick: ShintyStepper
var weather_pick: ShintyStepper
var side_pick: ShintyStepper
var diff_pick: ShintyStepper
var length_pick: ShintyStepper
var start_button: Button

# Squads screen
var squad_pick: ShintyStepper
var squad_crest: ShintyCrest
var squad_grid: GridContainer
var squad_title: Label
var squad_sub: Label

# Caman designer
var design := {}
var design_rows := {}
var design_club: ShintyStepper
var design_player: ShintyStepper
var design_numbers: Array = []  ## shirt numbers behind design_player's items (0 = whole team)
var design_save: Button
var design_status: Label
var design_faces: ShintyFaceDiagram
var _dragging := false


func _ready() -> void:
	theme = ShintyStyle.make_theme()
	var ok := Game.teams.size() >= 2
	if ok:
		# 3D nodes under a Control still render into the window, behind the UI.
		backdrop = ShintyMenuBackdrop.new()
		add_child(backdrop)
		backdrop.set_teams(Game.teams[Game.home_index], Game.teams[Game.away_index])
	else:
		var bg := ColorRect.new()
		bg.color = ShintyStyle.INK
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bg)

	overlay = ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sm := ShaderMaterial.new()
	sm.shader = OverlayShader
	overlay.material = sm
	add_child(overlay)

	_build_chrome()
	if not ok:
		_build_problem()
		_show("problem")
		return
	_build_hub()
	_build_kickoff()
	_build_squads()
	_build_controls()
	_build_designer()
	_show("hub", true)
	Music.play()
	# Fade in over the first frames while the ground finishes building.
	var fade := ColorRect.new()
	fade.color = ShintyStyle.INK
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fade)
	create_tween().tween_property(fade, "modulate:a", 0.0, 0.8).set_delay(0.15)
	get_tree().create_timer(1.2).timeout.connect(fade.queue_free)


# --- Shared frame: logo, screen title, button hints -----------------------------

func _build_chrome() -> void:
	var strip := ColorRect.new()
	var tm := ShaderMaterial.new()
	tm.shader = TartanShader
	strip.material = tm
	strip.position = Vector2(0, 0)
	strip.size = Vector2(12, 720)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(strip)

	var logo := HBoxContainer.new()
	logo.position = Vector2(52, 22)
	logo.add_theme_constant_override("separation", 6)
	logo.add_child(ShintyStyle.label("PRO", 46, "black", ShintyStyle.GOLD))
	logo.add_child(ShintyStyle.label("SHINTY", 46, "black"))
	add_child(logo)
	var bar := ColorRect.new()
	bar.material = tm
	bar.position = Vector2(54, 80)
	bar.size = Vector2(196, 5)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)

	screen_title = ShintyStyle.label("", 30, "black")
	screen_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	screen_title.position = Vector2(700, 32)
	screen_title.size = Vector2(524, 40)
	add_child(screen_title)

	hints = ShintyStyle.label("", 17, "semibold", ShintyStyle.MUTED)
	hints.position = Vector2(56, 684)
	hints.size = Vector2(1168, 24)
	add_child(hints)


func _screen(name: String) -> Control:
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.visible = false
	add_child(c)
	screens[name] = c
	return c


const SCREEN_INFO := {
	"hub": ["", "hub", "▲ ▼  Move       Enter  Select"],
	"kickoff": ["KICK OFF", "kickoff", "◀ ▶  Change       ▲ ▼  Move       Enter  Play       Esc  Back"],
	"squads": ["SQUADS", "squads", "◀ ▶  Change club       Esc  Back"],
	"controls": ["CONTROLS", "wide", "Esc  Back"],
	"camans": ["CAMAN DESIGNER", "designer", "▲ ▼  Move       ◀ ▶  Change       Drag  Turn the caman       Esc  Back"],
	"problem": ["", "", ""],
}


func _show(name: String, instant := false) -> void:
	if current != "":
		screens[current].visible = false
	current = name
	var s: Control = screens[name]
	s.visible = true
	var info: Array = SCREEN_INFO[name]
	screen_title.text = info[0]
	hints.text = info[2]
	if backdrop and info[1] != "":
		backdrop.set_shot(info[1], instant)
	var sm: ShaderMaterial = overlay.material
	var shades := {"hub": [0.9, 0.35, 0.0], "kickoff": [0.0, 0.75, 0.15], "squads": [0.35, 0.3, 0.55], "controls": [0.3, 0.3, 0.5], "camans": [0.75, 0.25, 0.0]}
	var target: Array = shades.get(name, [0.0, 0.0, 0.8])
	var tw := create_tween().set_parallel()
	tw.tween_interval(0.01)
	for i in 3:
		var key: String = ["left_shade", "bottom_shade", "full_shade"][i]
		if instant:
			sm.set_shader_parameter(key, target[i])
		else:
			tw.tween_method(func(v): sm.set_shader_parameter(key, v), sm.get_shader_parameter(key), target[i], 0.35)
	if not instant:
		s.modulate.a = 0.0
		s.position.x = 40
		tw.tween_property(s, "modulate:a", 1.0, 0.25)
		tw.tween_property(s, "position:x", 0.0, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var first: Control = s.get_meta("first", null)
	if first:
		first.grab_focus.call_deferred()


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_cancel") and current in ["kickoff", "squads", "controls", "camans"]:
		_show("hub")
		get_viewport().set_input_as_handled()
	elif current == "camans" and backdrop and backdrop.bench:
		# Drag anywhere off the panel to turn the caman on its stand.
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
			_dragging = e.pressed
		elif e is InputEventMouseMotion and _dragging:
			backdrop.bench.spin(e.relative.x * 0.012)


# --- Hub ------------------------------------------------------------------------

func _build_hub() -> void:
	var s := _screen("hub")
	var col := VBoxContainer.new()
	col.position = Vector2(56, 150)
	col.add_theme_constant_override("separation", 14)
	s.add_child(col)
	var play := _tile(col, "PLAY MATCH", "Pick two clubs and take on the computer", func(): _show("kickoff"), true)
	_tile(col, "SQUADS", "%d clubs, every player rated" % Game.teams.size(), func():
		squad_pick.select(Game.home_index)
		_refresh_squad()
		_show("squads"))
	_tile(col, "CAMAN DESIGNER", "Build a caman and give it to a club", func():
		_open_designer()
		_show("camans"))
	_tile(col, "CONTROLS", "Keyboard, controller and graphics", func(): _show("controls"))
	_tile(col, "QUIT", "Back to the desktop", func(): get_tree().quit())
	s.set_meta("first", play)

	if not Game.last_result.is_empty():
		s.add_child(_last_result_card(Game.last_result))
	if TeamData.load_error != "":
		var note := ShintyStyle.label(TeamData.load_error, 17, "medium", Color(1, 0.8, 0.4))
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.position = Vector2(56, 630)
		note.size = Vector2(700, 44)
		s.add_child(note)


func _tile(parent: Control, title: String, sub: String, action: Callable, big := false) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(470 if big else 430, 96 if big else 72)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 30
	v.offset_top = 10 if big else 6
	v.add_theme_constant_override("separation", -4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := ShintyStyle.label(title, 38 if big else 30, "black")
	var st := ShintyStyle.label(sub, 18, "medium", ShintyStyle.MUTED)
	v.add_child(t)
	v.add_child(st)
	b.add_child(v)
	ShintyStyle.focus_button(b)
	b.focus_entered.connect(func():
		t.add_theme_color_override("font_color", ShintyStyle.GOLD_DARK)
		st.add_theme_color_override("font_color", Color(ShintyStyle.GOLD_DARK, 0.75)))
	b.focus_exited.connect(func():
		t.add_theme_color_override("font_color", ShintyStyle.TEXT)
		st.add_theme_color_override("font_color", ShintyStyle.MUTED))
	b.pressed.connect(action)
	parent.add_child(b)
	return b


func _last_result_card(r: Dictionary) -> Control:
	var p := PanelContainer.new()
	var sb := ShintyStyle.box(ShintyStyle.PANEL, ShintyStyle.SLANT)
	sb.content_margin_left = 26
	sb.content_margin_right = 26
	sb.content_margin_top = 10
	sb.content_margin_bottom = 12
	sb.border_width_top = 3
	sb.border_color = ShintyStyle.GOLD
	p.add_theme_stylebox_override("panel", sb)
	p.position = Vector2(860, 572)
	var v := VBoxContainer.new()
	v.add_child(ShintyStyle.label("LAST MATCH", 16, "bold", ShintyStyle.GOLD))
	v.add_child(ShintyStyle.label("%s  %d - %d  %s" % [str(r["home"]).to_upper(), r["score"][0], r["score"][1], str(r["away"]).to_upper()], 28, "black"))
	p.add_child(v)
	return p


# --- Kick off (team select) ------------------------------------------------------

func _build_kickoff() -> void:
	var s := _screen("kickoff")
	home_pick = ShintyTeamCard.new("HOME", Game.teams, Game.home_index)
	home_pick.position = Vector2(56, 104)
	s.add_child(home_pick)
	away_pick = ShintyTeamCard.new("AWAY", Game.teams, Game.away_index)
	away_pick.position = Vector2(804, 104)
	s.add_child(away_pick)

	var vs := ShintyStyle.label("VS", 60, "black", ShintyStyle.GOLD)
	vs.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vs.position = Vector2(540, 96)
	vs.size = Vector2(200, 70)
	s.add_child(vs)

	var row := HBoxContainer.new()
	row.position = Vector2(56, 484)
	row.add_theme_constant_override("separation", 16)
	s.add_child(row)
	side_pick = ShintyStepper.new("You play as", ["Home team", "Away team"], Game.human_side)
	pitch_pick = ShintyStepper.new("Pitch", ShintyPitch.VENUE_NAMES, maxi(Game.venue, 0))
	weather_pick = ShintyStepper.new("Weather", ShintyWeather.NAMES, Game.weather)
	diff_pick = ShintyStepper.new("Difficulty", ["Easy", "Normal", "Hard"], Game.difficulty)
	length_pick = ShintyStepper.new("Half length", HALF_LENGTHS.map(func(m): return "%d minutes" % m), maxi(HALF_LENGTHS.find(Game.half_minutes), 0))
	for st in [side_pick, pitch_pick, weather_pick, diff_pick, length_pick]:
		st.custom_minimum_size = Vector2(280 if st == pitch_pick else 200, 74)
		row.add_child(st)
	weather_pick.custom_minimum_size.x = 220
	if Game.venue < 0:
		_pick_home_ground()

	start_button = Button.new()
	start_button.text = "PLAY MATCH"
	start_button.add_theme_font_override("font", ShintyStyle.font("black"))
	start_button.add_theme_font_size_override("font_size", 32)
	start_button.position = Vector2(904, 590)
	start_button.size = Vector2(320, 64)
	ShintyStyle.focus_button(start_button)
	start_button.pressed.connect(_start)
	s.add_child(start_button)
	var back := Button.new()
	back.text = "BACK"
	back.position = Vector2(56, 598)
	back.size = Vector2(150, 50)
	ShintyStyle.focus_button(back)
	back.pressed.connect(func(): _show("hub"))
	s.add_child(back)

	# Focus runs top to bottom: cards, settings, play.
	for card in [home_pick, away_pick]:
		card.focus_neighbor_bottom = side_pick.get_path()
	home_pick.focus_neighbor_right = away_pick.get_path()
	away_pick.focus_neighbor_left = home_pick.get_path()
	for st in [side_pick, pitch_pick, weather_pick]:
		st.focus_neighbor_top = home_pick.get_path()
	for st in [diff_pick, length_pick]:
		st.focus_neighbor_top = away_pick.get_path()
	for st in [side_pick, pitch_pick, weather_pick, diff_pick, length_pick]:
		st.focus_neighbor_bottom = start_button.get_path()
	start_button.focus_neighbor_top = length_pick.get_path()
	start_button.focus_neighbor_left = back.get_path()
	back.focus_neighbor_right = start_button.get_path()
	back.focus_neighbor_top = side_pick.get_path()
	s.set_meta("first", start_button)

	home_pick.changed.connect(func(_i):
		_pick_home_ground()
		_teams_changed())
	away_pick.changed.connect(func(_i): _teams_changed())
	side_pick.changed.connect(func(_i): _teams_changed())
	pitch_pick.changed.connect(func(i): backdrop.set_venue(i))
	_teams_changed()


func _teams_changed() -> void:
	home_pick.controlled = side_pick.selected == 0
	away_pick.controlled = side_pick.selected == 1
	backdrop.set_teams(home_pick.team(), away_pick.team())


## Picking a home team moves the match to its ground, if it has one.
func _pick_home_ground() -> void:
	var team_name: String = Game.teams[home_pick.selected]["name"]
	for i in ShintyPitch.VENUE_CLUBS.size():
		if team_name.containsn(ShintyPitch.VENUE_CLUBS[i]):
			pitch_pick.select(i)
			backdrop.set_venue(i)
			return


func _start() -> void:
	if home_pick.selected == away_pick.selected:
		away_pick.select((home_pick.selected + 1) % Game.teams.size())
	Game.home_index = home_pick.selected
	Game.away_index = away_pick.selected
	Game.venue = pitch_pick.selected
	Game.weather = weather_pick.selected
	Game.human_side = side_pick.selected
	Game.difficulty = diff_pick.selected
	Game.half_minutes = HALF_LENGTHS[length_pick.selected]
	get_tree().change_scene_to_file("res://scenes/loading.tscn")


# --- Squads ------------------------------------------------------------------------

const SQUAD_COLUMNS := [["", 44], ["POS", 56], ["#", 36], ["NAME", 250], ["PAC", 56], ["CTL", 56], ["PAS", 56], ["SHT", 56], ["TKL", 56], ["GK", 56]]


func _build_squads() -> void:
	var s := _screen("squads")
	var left := VBoxContainer.new()
	left.position = Vector2(56, 110)
	left.custom_minimum_size = Vector2(300, 0)
	left.add_theme_constant_override("separation", 10)
	s.add_child(left)
	var names: Array = Game.teams.map(func(t): return t["name"])
	squad_pick = ShintyStepper.new("Club", names, Game.home_index)
	squad_pick.custom_minimum_size = Vector2(300, 74)
	squad_pick.changed.connect(func(_i): _refresh_squad())
	left.add_child(squad_pick)
	squad_crest = ShintyCrest.new()
	squad_crest.custom_minimum_size = Vector2(300, 230)
	left.add_child(squad_crest)
	squad_title = ShintyStyle.label("", 36, "black")
	squad_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	squad_title.custom_minimum_size = Vector2(300, 0)
	left.add_child(squad_title)
	squad_sub = ShintyStyle.label("", 18, "medium", ShintyStyle.MUTED)
	squad_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	squad_sub.custom_minimum_size = Vector2(300, 0)
	left.add_child(squad_sub)

	var panel := PanelContainer.new()
	var sb := ShintyStyle.box(ShintyStyle.PANEL)
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	sb.border_width_top = 3
	sb.border_color = ShintyStyle.GOLD
	panel.add_theme_stylebox_override("panel", sb)
	panel.position = Vector2(392, 110)
	s.add_child(panel)
	squad_grid = GridContainer.new()
	squad_grid.columns = SQUAD_COLUMNS.size()
	squad_grid.add_theme_constant_override("h_separation", 8)
	squad_grid.add_theme_constant_override("v_separation", 5)
	panel.add_child(squad_grid)
	s.set_meta("first", squad_pick)
	_refresh_squad()


func _refresh_squad() -> void:
	var team: Dictionary = Game.teams[squad_pick.selected]
	squad_crest.team = team
	squad_title.text = str(team["name"]).to_upper()
	var bits := []
	for k in ["ground", "location", "league"]:
		if str(team.get(k, "")) != "" and not str(team[k]) in bits:
			bits.append(str(team[k]))
	bits.append("Team OVR %d" % int(team["overall"]))
	squad_sub.text = "  ·  ".join(bits)
	for c in squad_grid.get_children():
		c.queue_free()
	for col in SQUAD_COLUMNS:
		var h := ShintyStyle.label(col[0], 16, "bold", ShintyStyle.GOLD)
		h.custom_minimum_size = Vector2(col[1], 0)
		squad_grid.add_child(h)
	for p in TeamData.starting_twelve(team):
		squad_grid.add_child(_rating_badge(int(p["overall"])))
		squad_grid.add_child(ShintyStyle.label(p["position"], 20, "bold", ShintyStyle.MUTED))
		squad_grid.add_child(ShintyStyle.label(str(p["number"]), 20, "semibold", ShintyStyle.MUTED))
		squad_grid.add_child(ShintyStyle.label(str(p["name"]), 21, "bold"))
		for k in ["pace", "control", "passing", "shooting", "tackling", "keeping"]:
			var v := int(p.get(k, 0))
			squad_grid.add_child(ShintyStyle.label(str(v), 20, "semibold",
				ShintyStyle.GOOD if v >= 75 else (ShintyStyle.TEXT if v >= 55 else ShintyStyle.MUTED)))


func _rating_badge(ovr: int) -> Control:
	var p := PanelContainer.new()
	var sb := ShintyStyle.box(ShintyStyle.rating_color(ovr), ShintyStyle.SLANT)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	p.add_theme_stylebox_override("panel", sb)
	var l := ShintyStyle.label(str(ovr), 20, "black", ShintyStyle.GOLD_DARK)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(l)
	p.custom_minimum_size = Vector2(44, 0)
	return p


# --- Controls ------------------------------------------------------------------------

const CONTROL_ROWS := [
	["Move", "W A S D  /  Arrows", "Left stick"],
	["Shoot at goal (hold for power)", "Space  /  Left click", "X  /  Square"],
	["Long hit (hold for power)", "X", "RT  /  R2"],
	["Shield / hold up the ball (hold)", "Z", "LT  /  L2"],
	["Pass", "E", "A  /  Cross"],
	["Switch player", "Q", "LB  /  L1"],
	["Sprint", "Shift", "RB  /  R1"],
	["Pause", "Esc  /  P", "Start"],
	["Leave match (while paused)", "M", "Back  /  Select"],
]


func _build_controls() -> void:
	var s := _screen("controls")
	var panel := PanelContainer.new()
	var sb := ShintyStyle.box(ShintyStyle.PANEL)
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	sb.content_margin_top = 16
	sb.content_margin_bottom = 20
	sb.border_width_top = 3
	sb.border_color = ShintyStyle.GOLD
	panel.add_theme_stylebox_override("panel", sb)
	panel.position = Vector2(56, 120)
	s.add_child(panel)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 40)
	grid.add_theme_constant_override("v_separation", 14)
	panel.add_child(grid)
	for h in ["ACTION", "KEYBOARD", "CONTROLLER"]:
		var l := ShintyStyle.label(h, 17, "bold", ShintyStyle.GOLD)
		l.custom_minimum_size = Vector2(300 if h == "ACTION" else 250, 0)
		grid.add_child(l)
	for r in CONTROL_ROWS:
		grid.add_child(ShintyStyle.label(r[0], 24, "bold"))
		grid.add_child(ShintyStyle.label(r[1], 24, "semibold", ShintyStyle.MUTED))
		grid.add_child(ShintyStyle.label(r[2], 24, "semibold", ShintyStyle.MUTED))
	var back := Button.new()
	back.text = "BACK"
	back.position = Vector2(56, 598)
	back.size = Vector2(150, 50)
	ShintyStyle.focus_button(back)
	back.pressed.connect(func(): _show("hub"))
	s.add_child(back)
	# Low / Medium / High: applies straight away and is remembered (Game.gd).
	var gfx := ShintyStepper.new("Graphics", Game.GRAPHICS_NAMES, Game.graphics_quality)
	gfx.position = Vector2(250, 586)
	gfx.size = Vector2(300, 74)
	gfx.changed.connect(func(i): Game.set_graphics_quality(i))
	s.add_child(gfx)
	# Menu music volume (Music autoload), remembered like the graphics.
	var mus := ShintyStepper.new("Music", Music.VOLUME_NAMES, Music.volume_step)
	mus.position = Vector2(570, 586)
	mus.size = Vector2(300, 74)
	mus.changed.connect(func(i): Music.set_volume_step(i))
	s.add_child(mus)
	back.focus_neighbor_right = gfx.get_path()
	gfx.focus_neighbor_left = back.get_path()
	gfx.focus_neighbor_right = mus.get_path()
	mus.focus_neighbor_left = gfx.get_path()
	s.set_meta("first", back)


# --- Caman designer --------------------------------------------------------------------

## Rows of the designer panel: [key, caption, kind]. Kinds: a list of names
## from ShintyCaman, "colour", "club_colour" (the palette plus the club's own),
## "wrap" (off/on) or "bands".
const DESIGN_ROWS := [
	["", "BAS"],
	["shape", "Shape", "shapes"],
	["face", "Front face", "faces"],
	["face_back", "Back face", "faces"],
	["", "WOOD AND TAPE"],
	["wood", "Wood", "woods"],
	["paint", "Paint", "colour"],
	["grip", "Grip tape", "colour"],
	["wrap", "Double wrap", "wrap"],
	["grip2", "Second tape", "colour"],
	["bas_tape", "Bas tape", "colour"],
	["", "FINISH"],
	["bands", "Painted bands", "bands"],
	["band", "Band colour", "colour"],
	["helmet", "Helmet", "club_colour"],
]


func _build_designer() -> void:
	var s := _screen("camans")
	var panel := PanelContainer.new()
	var sb := ShintyStyle.box(ShintyStyle.PANEL)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 12
	sb.border_width_top = 3
	sb.border_color = ShintyStyle.GOLD
	panel.add_theme_stylebox_override("panel", sb)
	panel.position = Vector2(56, 98)
	panel.size = Vector2(420, 530)
	s.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	panel.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 2)
	scroll.add_child(list)

	var names: Array = ShintyCaman.PALETTE.map(func(c): return c[0])
	var chips: Array = ShintyCaman.PALETTE.map(func(c): return Color(c[1]))
	var first: Control = null
	for row in DESIGN_ROWS:
		if row[0] == "":
			var h := ShintyStyle.label(row[1], 15, "bold", ShintyStyle.GOLD)
			h.custom_minimum_size = Vector2(0, 22)
			h.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
			list.add_child(h)
			continue
		var r: ShintyOptionRow
		match row[2]:
			"shapes": r = ShintyOptionRow.new(row[1], ShintyCaman.SHAPES)
			"faces": r = ShintyOptionRow.new(row[1], ShintyCaman.FACES)
			"woods": r = ShintyOptionRow.new(row[1], ShintyCaman.WOODS)
			"wrap": r = ShintyOptionRow.new(row[1], ["Off", "On"])
			"bands": r = ShintyOptionRow.new(row[1], ["None", "One", "Two", "Three"])
			"colour": r = ShintyOptionRow.new(row[1], names, 0, chips)
			"club_colour": r = ShintyOptionRow.new(row[1], ["Club colour"] + names, 0, [null] + chips)
		r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.set_meta("key", row[0])
		r.set_meta("kind", row[2])
		r.changed.connect(func(i): _design_row_changed(row[0], row[2], i))
		list.add_child(r)
		design_rows[row[0]] = r
		if first == null:
			first = r

	# Who gets it: a club, the whole team or one player, and the save button.
	var names_c: Array = Game.teams.map(func(t): return t["name"])
	design_club = ShintyStepper.new("Club", names_c, Game.home_index)
	design_club.position = Vector2(516, 586)
	design_club.size = Vector2(250, 74)
	design_club.changed.connect(func(_i):
		_design_players()
		_design_club_changed())
	s.add_child(design_club)
	design_player = ShintyStepper.new("Give it to", ["Whole team"])
	design_player.position = Vector2(780, 586)
	design_player.size = Vector2(250, 74)
	design_player.changed.connect(func(_i): _design_club_changed())
	s.add_child(design_player)
	design_save = Button.new()
	design_save.text = "SAVE"
	design_save.add_theme_font_override("font", ShintyStyle.font("black"))
	design_save.add_theme_font_size_override("font_size", 30)
	design_save.position = Vector2(1048, 596)
	design_save.size = Vector2(176, 64)
	ShintyStyle.focus_button(design_save)
	design_save.pressed.connect(_save_design)
	s.add_child(design_save)
	design_faces = ShintyFaceDiagram.new()
	design_faces.position = Vector2(944, 96)
	design_faces.size = Vector2(280, 176)
	s.add_child(design_faces)
	design_status = ShintyStyle.label("", 17, "semibold", ShintyStyle.MUTED)
	design_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	design_status.position = Vector2(700, 560)
	design_status.size = Vector2(524, 26)
	s.add_child(design_status)

	var back := Button.new()
	back.text = "BACK"
	back.position = Vector2(56, 636)
	back.size = Vector2(150, 40)
	ShintyStyle.focus_button(back)
	back.pressed.connect(func(): _show("hub"))
	s.add_child(back)
	var reset := Button.new()
	reset.text = "RESET"
	reset.position = Vector2(226, 636)
	reset.size = Vector2(150, 40)
	ShintyStyle.focus_button(reset)
	reset.pressed.connect(_design_club_changed)
	s.add_child(reset)
	s.set_meta("reset", reset)

	# Focus: down the panel, then to the buttons; right from the panel goes to the club.
	var rows: Array = design_rows.values()
	for r in rows:
		r.focus_neighbor_right = design_club.get_path()
	rows[0].focus_neighbor_top = back.get_path()
	rows[-1].focus_neighbor_bottom = back.get_path()
	back.focus_neighbor_top = rows[-1].get_path()
	reset.focus_neighbor_top = rows[-1].get_path()
	back.focus_neighbor_bottom = rows[0].get_path()
	back.focus_neighbor_right = reset.get_path()
	reset.focus_neighbor_left = back.get_path()
	reset.focus_neighbor_right = design_club.get_path()
	design_club.focus_neighbor_left = rows[0].get_path()
	design_club.focus_neighbor_right = design_player.get_path()
	design_club.focus_neighbor_top = rows[0].get_path()
	design_club.focus_neighbor_bottom = design_player.get_path()
	design_player.focus_neighbor_left = design_club.get_path()
	design_player.focus_neighbor_right = design_save.get_path()
	design_player.focus_neighbor_top = design_club.get_path()
	design_player.focus_neighbor_bottom = design_save.get_path()
	design_save.focus_neighbor_left = design_player.get_path()
	design_save.focus_neighbor_top = design_player.get_path()
	s.set_meta("first", first)


## Opens the designer on the club you last picked, with its current caman.
func _open_designer() -> void:
	design_club.select(home_pick.selected if home_pick else Game.home_index)
	_design_players()
	_design_club_changed()


## Fills the "Give it to" picker: the whole team, then each player by number.
func _design_players() -> void:
	var team: Dictionary = Game.teams[design_club.selected]
	var ps: Array = team.get("players", []).duplicate()
	ps.sort_custom(func(a, b): return int(a.get("number", 0)) < int(b.get("number", 0)))
	var items := ["Whole team"]
	design_numbers = [0]
	for p in ps:
		items.append("%d  %s" % [int(p.get("number", 0)), str(p.get("name", ""))])
		design_numbers.append(int(p.get("number", 0)))
	design_player.items = items
	design_player.select(0)


## The chosen player's shirt number, or 0 for the whole team.
func _design_number() -> int:
	return design_numbers[design_player.selected] if design_player.selected < design_numbers.size() else 0


## Loads the chosen club's (or player's) caman into the designer; also Reset.
func _design_club_changed() -> void:
	var n := _design_number()
	design = (Game.team_caman(design_club.selected) if n == 0 else Game.player_caman(design_club.selected, n)).duplicate()
	_design_refresh(true)


func _design_row_changed(key: String, kind: String, i: int) -> void:
	match kind:
		"colour":
			design[key] = "#" + ShintyCaman.PALETTE[i][1]
		"club_colour":
			design[key] = "" if i == 0 else "#" + ShintyCaman.PALETTE[i - 1][1]
		"wrap":
			design[key] = i == 1
		_:
			design[key] = i
	# Picking a colour for a part that's switched off switches it on.
	if key == "paint" and design["wood"] != ShintyCaman.WOODS.find("Painted"):
		design["wood"] = ShintyCaman.WOODS.find("Painted")
	elif key == "grip2":
		design["wrap"] = true
	elif key == "band" and design["bands"] == 0:
		design["bands"] = 1
	_design_refresh(false)


## Puts `design` on the rows, the bench and the status line.
func _design_refresh(saved: bool) -> void:
	design = ShintyCaman.sanitize(design)
	for key in design_rows:
		var r: ShintyOptionRow = design_rows[key]
		var v: Variant = design[key]
		match str(r.get_meta("kind")):
			"colour", "club_colour":
				var idx := _palette_index(str(v))
				if r.get_meta("kind") == "club_colour":
					idx = 0 if str(v) == "" else idx + 1
				r.selected = maxi(idx, 0)
			"wrap":
				r.selected = 1 if v else 0
			_:
				r.selected = int(v)
	design_rows["paint"].inactive = design["wood"] != ShintyCaman.WOODS.find("Painted")
	design_rows["grip2"].inactive = not design["wrap"]
	design_rows["band"].inactive = design["bands"] == 0
	var team: Dictionary = Game.teams[design_club.selected]
	design_faces.design = design
	if backdrop:
		backdrop.show_bench().set_design(design, team)
	var n := _design_number()
	var who: String = team["name"] if n == 0 else design_player.get_item_text(design_player.selected)
	if saved and n != 0:
		var own: bool = Game.has_own_caman(design_club.selected, n)
		design_status.text = ("%s has a caman of their own" if own else "%s carries the club caman") % who
	elif saved:
		design_status.text = ("%s's own caman" if team.has("caman") else "%s's colours: not saved yet") % who
	else:
		design_status.text = "Changed: save to give it to %s" % who
	design_status.add_theme_color_override("font_color", ShintyStyle.MUTED if saved else ShintyStyle.GOLD)


## Nearest palette entry to a colour, so club colours land on a swatch.
func _palette_index(hex: String) -> int:
	if not Color.html_is_valid(hex):
		return -1
	var c := Color(hex)
	var best := -1
	var best_d := INF
	for i in ShintyCaman.PALETTE.size():
		var d := TeamData.colour_distance(c, Color(ShintyCaman.PALETTE[i][1]))
		if d < best_d:
			best_d = d
			best = i
	return best


func _save_design() -> void:
	var team: Dictionary = Game.teams[design_club.selected]
	var n := _design_number()
	if n == 0:
		Game.set_team_caman(design_club.selected, design)
		design_status.text = "Saved: %s's players will carry this caman" % team["name"]
	else:
		Game.set_player_caman(design_club.selected, n, design)
		design_status.text = "Saved: %s will carry this caman" % design_player.get_item_text(design_player.selected)
	design_status.add_theme_color_override("font_color", ShintyStyle.GOOD)
	if home_pick:
		_teams_changed()  # the players behind the menu pick it up too


# --- Squads file problem ----------------------------------------------------------

## Shown instead of the menu when the squads file can't be used.
func _build_problem() -> void:
	var s := _screen("problem")
	var msg := ShintyStyle.label("", 22, "medium", Color(1, 0.85, 0.5))
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg.position = Vector2(56, 130)
	msg.size = Vector2(760, 300)
	msg.text = "The squads couldn't be loaded, so a match can't start.\n\n%s\n\nThe game needs at least two teams, each with one player at every position (GK, FB, LHB, CHB, RHB, LM, RM, LHF, CHF, RHF, CF, FF)." % (TeamData.load_error if TeamData.load_error != "" else "No teams found.")
	s.add_child(msg)
	var quit := Button.new()
	quit.text = "QUIT"
	quit.position = Vector2(56, 460)
	quit.size = Vector2(180, 54)
	ShintyStyle.focus_button(quit)
	quit.pressed.connect(func(): get_tree().quit())
	s.add_child(quit)
	s.set_meta("first", quit)
