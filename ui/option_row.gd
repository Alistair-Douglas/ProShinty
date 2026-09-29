class_name ShintyOptionRow
extends ShintyStepper
## A compact one-line "caption  ◀ value ▶" setting for long option lists like
## the caman designer's. Colour choices show a swatch beside the name. Keys,
## d-pad, stick, clicks and the scroll wheel work as on ShintyStepper.

## One Color per item (or null for no swatch); empty for a plain text row.
var swatches: Array = []
## Dimmed while the setting has no effect (a paint colour on bare wood); it
## can still be changed.
var inactive := false:
	set(v):
		inactive = v
		queue_redraw()


func _init(p_caption := "", p_items: Array = [], p_selected := 0, p_swatches: Array = []) -> void:
	super(p_caption, p_items, p_selected)
	swatches = p_swatches
	custom_minimum_size = Vector2(360, 34)


func _draw() -> void:
	var focused := has_focus()
	var r := Rect2(Vector2.ZERO, size)
	var bg := ShintyStyle.box(ShintyStyle.GOLD if focused else Color(1, 1, 1, 0.04 if not _hover else 0.08))
	bg.set_corner_radius_all(6)
	draw_style_box(bg, r)
	var dim := 0.45 if inactive and not focused else 1.0
	var fg := ShintyStyle.GOLD_DARK if focused else ShintyStyle.TEXT
	var cap := Color(ShintyStyle.GOLD_DARK, 0.75) if focused else ShintyStyle.MUTED
	var mid := size.y * 0.5
	draw_string(ShintyStyle.font("semibold"), Vector2(14, mid + 7), caption, HORIZONTAL_ALIGNMENT_LEFT, size.x * 0.42, 19, Color(cap, cap.a * dim))

	# Value on the right, between the arrows.
	var left := size.x * 0.44
	var right := size.x - 14.0
	var a := Color(fg, (0.9 if items.size() > 1 else 0.25) * dim)
	var s := 5.5
	draw_colored_polygon(PackedVector2Array([Vector2(left, mid), Vector2(left + s, mid - s), Vector2(left + s, mid + s)]), a)
	draw_colored_polygon(PackedVector2Array([Vector2(right, mid), Vector2(right - s, mid - s), Vector2(right - s, mid + s)]), a)
	var text := "" if items.is_empty() else str(items[selected])
	var f := ShintyStyle.font("bold")
	var x := left + 16.0
	var avail := right - 14.0 - x
	var sw: Variant = swatches[selected] if selected < swatches.size() else null
	if sw is Color:
		var chip := Rect2(Vector2(x, mid - 10), Vector2(20, 20))
		var cb := ShintyStyle.box(sw)
		cb.set_corner_radius_all(10)
		cb.border_width_left = 2
		cb.border_width_right = 2
		cb.border_width_top = 2
		cb.border_width_bottom = 2
		cb.border_color = Color(ShintyStyle.GOLD_DARK, 0.5) if focused else Color(1, 1, 1, 0.35)
		draw_style_box(cb, chip)
		x += 28.0
		avail -= 28.0
	var fs := 20
	while fs > 13 and f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > avail:
		fs -= 1
	draw_string(f, Vector2(x, mid + fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, avail, fs, Color(fg, dim))
