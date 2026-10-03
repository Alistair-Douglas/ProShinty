extends Control
## The training ground's pose editor: adjust the picked move with sliders and
## watch it repeat, in slow motion if wanted, from the close camera. Saved to
## data/poses.json, which every match reads (see models/shinty_pose_tweaks.gd).
##
## Controller: D-pad / left stick up and down to pick a row, left and right to
## change it, A to press a button, B to finish. Mouse and keyboard work too.

signal closed

var match_node: Node
var action := "swing"
var phase := 1
var _title: Label
var _phase_buttons: Array = []
var _length: HSlider
var _length_value: Label
var _length_row: Control
var _phases: HFlowContainer
var _sliders := {}    # slider key -> [HSlider, value Label]
var _speed_button: Button
var _note: Label
var _updating := false


func _ready() -> void:
	theme = ShintyStyle.make_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel := PanelContainer.new()
	var sb := ShintyStyle.box(ShintyStyle.PANEL)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", sb)
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -460
	panel.offset_top = 8
	panel.offset_right = -8
	panel.offset_bottom = -52
	add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	panel.add_child(col)

	_title = ShintyStyle.label("POSE EDITOR", 26, "black", ShintyStyle.GOLD)
	col.add_child(_title)

	_phases = HFlowContainer.new()
	_phases.add_theme_constant_override("h_separation", 6)
	col.add_child(_phases)

	var lrow := _row(col, "How long it takes")
	_length_row = lrow[0].get_parent()
	_length = lrow[0]
	_length_value = lrow[1]
	_length.min_value = 0.5
	_length.max_value = 2.0
	_length.step = 0.05
	_length.value_changed.connect(func(v):
		if not _updating:
			ShintyPoseTweaks.set_length(action, v)
		_length_value.text = "x%.2f" % v)

	col.add_child(ShintyStyle.label("At this moment:", 15, "medium", ShintyStyle.MUTED))
	for s in ShintyPoseTweaks.SLIDERS:
		var r := _row(col, s[1])
		var sl: HSlider = r[0]
		sl.min_value = -float(s[4])
		sl.max_value = float(s[4])
		sl.step = 1.0
		var key: String = s[0]
		var unit := " cm" if s[2] in ["caman", "grip"] else "°"
		sl.value_changed.connect(func(v):
			if not _updating:
				ShintyPoseTweaks.set_value(action, phase, key, v)
			r[1].text = "%+d%s" % [int(v), unit])
		_sliders[key] = r

	var buttons := HFlowContainer.new()
	buttons.add_theme_constant_override("h_separation", 6)
	buttons.add_theme_constant_override("v_separation", 6)
	col.add_child(buttons)
	_speed_button = _button("Speed", func():
		match_node.set_speed((match_node.speed_index + 1) % match_node.SPEEDS.size())
		_refresh_speed())
	buttons.add_child(_speed_button)
	buttons.add_child(_button("Reset moment", func():
		ShintyPoseTweaks.reset(action, phase)
		_load_values()))
	buttons.add_child(_button("Reset move", func():
		ShintyPoseTweaks.reset(action)
		_load_values()))
	buttons.add_child(_button("Save", _save))
	buttons.add_child(_button("Done", func(): closed.emit()))
	_note = ShintyStyle.label("", 14, "medium", ShintyStyle.MUTED)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_note)


func open(p_action: String, label: String) -> void:
	action = p_action
	_title.text = "POSE EDITOR: " + label.to_upper()
	_note.text = "Each slider sets the move at the moment picked above; it blends in and out between moments. Set for a right-hander: left-handers get the mirror image."
	visible = true
	# One-off moves have a wind-up, strike and finish; a run has each foot
	# forward; a held pose has just the one.
	for b in _phase_buttons:
		b.queue_free()
	_phase_buttons = []
	var names: Array = ShintyPoseTweaks.phase_names(action)
	for i in names.size():
		var b := _button(names[i], func(): _set_phase(i))
		b.toggle_mode = true
		_phases.add_child(b)
		_phase_buttons.append(b)
	_length_row.visible = ShintyPoseTweaks.has_length(action)
	var first := 1 if names.size() == 3 and ShintyPoseTweaks.has_length(action) else (2 if names.size() == 3 else 0)
	_set_phase(first)
	_refresh_speed()
	_phase_buttons[first].grab_focus()


func _unhandled_input(e: InputEvent) -> void:
	if visible and e.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		closed.emit()


func _set_phase(i: int) -> void:
	phase = i
	for j in _phase_buttons.size():
		_phase_buttons[j].button_pressed = j == i
	_load_values()


func _load_values() -> void:
	_updating = true
	_length.value = ShintyPoseTweaks.length_scale(action)
	for key in _sliders:
		_sliders[key][0].value = ShintyPoseTweaks.get_value(action, phase, key)
	_updating = false


func _refresh_speed() -> void:
	var s: float = match_node.SPEEDS[match_node.speed_index]
	_speed_button.text = "Speed: " + ("full" if s >= 1.0 else "1/%d" % roundi(1.0 / s))


func _save() -> void:
	var path := ShintyPoseTweaks.save()
	_note.text = ("Saved to " + path) if path != "" else "Couldn't save: the file couldn't be written."


func _button(text: String, action_fn: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 17)
	for n in ["normal", "hover", "pressed", "hover_pressed"]:
		var st: StyleBox = theme.get_stylebox(n, "Button").duplicate()
		st.content_margin_left = 14
		st.content_margin_right = 14
		st.content_margin_top = 4
		st.content_margin_bottom = 4
		b.add_theme_stylebox_override(n, st)
	b.focus_entered.connect(func(): b.add_theme_color_override("font_color", ShintyStyle.GOLD))
	b.focus_exited.connect(func(): b.remove_theme_color_override("font_color"))
	b.pressed.connect(action_fn)
	return b


## A labelled slider row: returns [HSlider, value Label].
func _row(parent: Control, text: String) -> Array:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var name := ShintyStyle.label(text, 15, "medium")
	name.custom_minimum_size = Vector2(190, 0)
	row.add_child(name)
	var sl := HSlider.new()
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sl.custom_minimum_size = Vector2(0, 22)
	row.add_child(sl)
	var val := ShintyStyle.label("0", 15, "semibold")
	val.custom_minimum_size = Vector2(56, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(val)
	sl.focus_entered.connect(func(): name.add_theme_color_override("font_color", ShintyStyle.GOLD))
	sl.focus_exited.connect(func(): name.add_theme_color_override("font_color", ShintyStyle.TEXT))
	return [sl, val]
