extends Control
## Title screen: pick teams, the pitch, which side you control, difficulty and
## match length.

const TeamData := preload("res://scripts/team_data.gd")

var home_pick: OptionButton
var away_pick: OptionButton
var pitch_pick: OptionButton
var side_pick: OptionButton
var diff_pick: OptionButton
var length_pick: OptionButton
var squad_text: RichTextLabel
var start_button: Button


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.14, 0.09)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := HBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 48
	root.offset_top = 36
	root.offset_right = -48
	root.offset_bottom = -36
	root.add_theme_constant_override("separation", 40)
	add_child(root)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(360, 0)
	left.add_theme_constant_override("separation", 12)
	root.add_child(left)

	var title := Label.new()
	title.text = "SHINTY"
	title.add_theme_font_size_override("font_size", 56)
	left.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Match day"
	subtitle.add_theme_font_size_override("font_size", 18)
	subtitle.modulate = Color(1, 1, 1, 0.7)
	left.add_child(subtitle)

	if Game.teams.size() < 2:
		_show_problem(left)
		return

	var names := []
	for t in Game.teams:
		names.append("%s  (OVR %d)" % [t["name"], t["overall"]])
	home_pick = _option(left, "Home team", names, Game.home_index)
	away_pick = _option(left, "Away team", names, Game.away_index)
	pitch_pick = _option(left, "Pitch", ShintyPitch.VENUE_NAMES, Game.venue)
	if Game.venue < 0:
		_pick_home_ground()
	side_pick = _option(left, "You control", ["Home team", "Away team"], Game.human_side)
	diff_pick = _option(left, "Difficulty", ["Easy", "Normal", "Hard"], Game.difficulty)
	length_pick = _option(left, "Half length", ["2 minutes", "3 minutes", "5 minutes", "10 minutes"], [2, 3, 5, 10].find(Game.half_minutes))
	home_pick.item_selected.connect(func(_i):
		_refresh_squads()
		_pick_home_ground())
	away_pick.item_selected.connect(func(_i): _refresh_squads())

	start_button = Button.new()
	start_button.text = "Play match"
	start_button.custom_minimum_size = Vector2(0, 48)
	start_button.pressed.connect(_start)
	left.add_child(start_button)
	var quit := Button.new()
	quit.text = "Quit"
	quit.pressed.connect(func(): get_tree().quit())
	left.add_child(quit)

	if not Game.last_result.is_empty():
		var r: Dictionary = Game.last_result
		var last := Label.new()
		last.text = "Last match: %s %d - %d %s" % [r["home"], r["score"][0], r["score"][1], r["away"]]
		left.add_child(last)

	squad_text = RichTextLabel.new()
	squad_text.bbcode_enabled = true
	squad_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	squad_text.add_theme_font_size_override("normal_font_size", 14)
	squad_text.add_theme_font_size_override("bold_font_size", 16)
	root.add_child(squad_text)
	_refresh_squads()
	start_button.grab_focus()
	if TeamData.load_error != "":
		var note := Label.new()
		note.text = TeamData.load_error
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.modulate = Color(1, 0.8, 0.4)
		left.add_child(note)


## Picking a home team moves the match to its ground, if it has one.
func _pick_home_ground() -> void:
	var team_name: String = Game.teams[home_pick.selected]["name"]
	for i in ShintyPitch.VENUE_NAMES.size():
		var ground: String = ShintyPitch.VENUE_NAMES[i].get_slice(" ", 0)
		if team_name.containsn(ground):
			pitch_pick.select(i)
			return


## Shown instead of the match setup when the squads file can't be used.
func _show_problem(parent: Control) -> void:
	var msg := Label.new()
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg.custom_minimum_size = Vector2(700, 0)
	msg.text = "The squads couldn't be loaded, so a match can't start.\n\n%s\n\nThe game needs at least two teams, each with one player at every position (GK, FB, LHB, CHB, RHB, LM, RM, LHF, CHF, RHF, CF, FF)." % (TeamData.load_error if TeamData.load_error != "" else "No teams found.")
	msg.modulate = Color(1, 0.85, 0.5)
	parent.add_child(msg)
	var quit := Button.new()
	quit.text = "Quit"
	quit.pressed.connect(func(): get_tree().quit())
	parent.add_child(quit)
	quit.grab_focus()


func _option(parent: Control, label: String, items: Array, selected: int) -> OptionButton:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(130, 0)
	row.add_child(l)
	var o := OptionButton.new()
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for it in items:
		o.add_item(it)
	o.select(max(selected, 0))
	row.add_child(o)
	parent.add_child(row)
	return o


func _refresh_squads() -> void:
	var text := ""
	for idx in [home_pick.selected, away_pick.selected]:
		var team: Dictionary = Game.teams[idx]
		text += "[b]%s[/b]  team overall %d\n" % [team["name"], team["overall"]]
		text += "[table=9]"
		for h in ["#", "Name", "Pos", "OVR", "PAC", "CTL", "PAS", "SHT", "TKL"]:
			text += "[cell][color=#9fd39f]%s[/color]  [/cell]" % h
		for p in TeamData.starting_twelve(team):
			for v in [p["number"], p["name"], p["position"], p["overall"], p["pace"], p["control"], p["passing"], p["shooting"], p["tackling"]]:
				text += "[cell]%s  [/cell]" % str(v)
		text += "[/table]\n\n"
	squad_text.text = text


func _start() -> void:
	if home_pick.selected == away_pick.selected:
		away_pick.select((home_pick.selected + 1) % Game.teams.size())
	Game.home_index = home_pick.selected
	Game.away_index = away_pick.selected
	Game.venue = pitch_pick.selected
	Game.human_side = side_pick.selected
	Game.difficulty = diff_pick.selected
	Game.half_minutes = [2, 3, 5, 10][length_pick.selected]
	get_tree().change_scene_to_file("res://scenes/match.tscn")
