extends Control
## Main menu. A live 3D scene of the chosen ground sits behind four screens:
##   hub       Play match, Squads, Controls, Quit
##   kickoff   pick both clubs, the pitch, your side, difficulty and half length
##   squads    browse every club's players and ratings
##   controls  keyboard and controller buttons
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
	_show("hub", true)
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
	var shades := {"hub": [0.9, 0.35, 0.0], "kickoff": [0.0, 0.75, 0.15], "squads": [0.35, 0.3, 0.55], "controls": [0.3, 0.3, 0.5]}
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
	if e.is_action_pressed("ui_cancel") and current in ["kickoff", "squads", "controls"]:
		_show("hub")
		get_viewport().set_input_as_handled()


# --- Hub ------------------------------------------------------------------------

func _build_hub() -> void:
	var s := _screen("hub")
	var col := VBoxContainer.new()
	col.position = Vector2(56, 176)
	col.add_theme_constant_override("separation", 14)
	s.add_child(col)
	var play := _tile(col, "PLAY MATCH", "Pick two clubs and take on the computer", func(): _show("kickoff"), true)
	_tile(col, "SQUADS", "%d clubs, every player rated" % Game.teams.size(), func():
		squad_pick.select(Game.home_index)
		_refresh_squad()
		_show("squads"))
	_tile(col, "CONTROLS", "Keyboard and controller", func(): _show("controls"))
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
	p.position = Vector2(56, 560)
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
	diff_pick = ShintyStepper.new("Difficulty", ["Easy", "Normal", "Hard"], Game.difficulty)
	length_pick = ShintyStepper.new("Half length", HALF_LENGTHS.map(func(m): return "%d minutes" % m), maxi(HALF_LENGTHS.find(Game.half_minutes), 0))
	for st in [side_pick, pitch_pick, diff_pick, length_pick]:
		st.custom_minimum_size = Vector2(280, 74)
		row.add_child(st)
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
	for st in [side_pick, pitch_pick]:
		st.focus_neighbor_top = home_pick.get_path()
	for st in [diff_pick, length_pick]:
		st.focus_neighbor_top = away_pick.get_path()
	for st in [side_pick, pitch_pick, diff_pick, length_pick]:
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
	["Hit the ball (hold for power)", "Space", "X  /  Square"],
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
	s.set_meta("first", back)


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
