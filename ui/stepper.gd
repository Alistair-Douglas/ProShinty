class_name ShintyStepper
extends Control
## A "◀ value ▶" selector, FIFA style: focus it and press left/right (keys,
## d-pad or stick) or click the arrows to change the value. Draws its own
## caption above the value.

signal changed(index: int)

var caption := ""
var items: Array = []
var selected := 0:
	set(v):
		if items.is_empty():
			selected = 0
		else:
			selected = posmod(v, items.size())
		queue_redraw()
var wrap := true

var _hover := false


func _init(p_caption := "", p_items: Array = [], p_selected := 0) -> void:
	caption = p_caption
	items = p_items
	selected = p_selected
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size = Vector2(260, 74)
	mouse_entered.connect(func(): _hover = true; grab_focus(); queue_redraw())
	mouse_exited.connect(func(): _hover = false; queue_redraw())
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)


func select(i: int) -> void:
	selected = i


func get_item_text(i: int) -> String:
	return str(items[i])


func step(dir: int) -> void:
	if items.size() < 2:
		return
	var next := selected + dir
	if not wrap and (next < 0 or next >= items.size()):
		return
	selected = next
	changed.emit(selected)


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
		if e.button_index == MOUSE_BUTTON_LEFT:
			step(-1 if e.position.x < size.x * 0.5 else 1)
			accept_event()
		elif e.button_index == MOUSE_BUTTON_WHEEL_UP:
			step(-1)
			accept_event()
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			step(1)
			accept_event()


func _draw() -> void:
	var focused := has_focus()
	var r := Rect2(Vector2(0, 26), Vector2(size.x, size.y - 26))
	var bg := ShintyStyle.box(ShintyStyle.GOLD if focused else ShintyStyle.PANEL_LIGHT, ShintyStyle.SLANT)
	if not focused:
		bg.border_width_left = 3
		bg.border_color = ShintyStyle.GOLD if _hover else Color(1, 1, 1, 0.18)
	draw_style_box(bg, r)
	var cap_font := ShintyStyle.font("bold")
	draw_string(cap_font, Vector2(4, 19), caption.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 15,
		ShintyStyle.GOLD if focused else ShintyStyle.MUTED)
	var fg := ShintyStyle.GOLD_DARK if focused else ShintyStyle.TEXT
	var f := ShintyStyle.font("bold")
	var text := "" if items.is_empty() else str(items[selected]).to_upper()
	var fs := 22
	var avail := r.size.x - 84
	while fs > 14 and f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > avail:
		fs -= 1
	var mid := r.position.y + r.size.y * 0.5
	draw_string(f, Vector2(r.position.x + 42, mid + fs * 0.35), text, HORIZONTAL_ALIGNMENT_CENTER, avail, fs, fg)
	# Arrows
	var a := Color(fg, 0.9 if items.size() > 1 else 0.25)
	var s := 7.0
	draw_colored_polygon(PackedVector2Array([Vector2(20, mid), Vector2(20 + s, mid - s), Vector2(20 + s, mid + s)]), a)
	var x := r.size.x - 20
	draw_colored_polygon(PackedVector2Array([Vector2(x, mid), Vector2(x - s, mid - s), Vector2(x - s, mid + s)]), a)
