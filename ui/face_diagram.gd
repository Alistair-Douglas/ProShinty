class_name ShintyFaceDiagram
extends Control
## The caman designer's bas cross-section: a triangle, wide at the sole,
## with the front face on the right and the back face on the left. Each face
## leans as far as the design says, and an arc off each face shows how high
## a hit off it goes (ShintyCaman.face_degrees).

var design := {}:
	set(v):
		design = ShintyCaman.sanitize(v)
		queue_redraw()


func _init() -> void:
	custom_minimum_size = Vector2(280, 176)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var bg := ShintyStyle.box(ShintyStyle.PANEL)
	bg.set_corner_radius_all(6)
	bg.border_width_top = 3
	bg.border_color = ShintyStyle.GOLD
	draw_style_box(bg, Rect2(Vector2.ZERO, size))
	var f := ShintyStyle.font("bold")
	draw_string(f, Vector2(14, 24), "BAS SECTION", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, ShintyStyle.GOLD)
	if design.is_empty():
		return
	var cx := size.x * 0.5
	var sole := size.y - 30.0
	var half := 34.0
	var tall := 74.0
	# Same polygon the caman's bas is built from, scaled up.
	var tri := ShintyCaman._triangle(Vector2(half, tall * 0.5), ShintyCaman._face_taper(design, false),
		ShintyCaman._face_taper(design, true))
	var pts := PackedVector2Array()
	for q in tri:
		pts.append(Vector2(cx + q.x, sole - tall * 0.5 - q.y))
	draw_colored_polygon(pts, ShintyCaman.wood_colour(design))
	pts.append(pts[0])
	draw_polyline(pts, Color(1, 1, 1, 0.55), 1.5, true)
	draw_line(Vector2(cx - half - 12, sole + 1), Vector2(cx + half + 12, sole + 1), Color(ShintyStyle.GOOD, 0.6), 2.0)
	# Launch off each face: an arc whose height follows the face angle.
	for back in [false, true]:
		var deg := ShintyCaman.face_degrees(design, back)
		var dir := -1.0 if back else 1.0
		var from := Vector2(cx + dir * (half + 8.0), sole - 10.0)
		var rise := 18.0 + (deg + 5.0) * 2.4
		var arc := PackedVector2Array()
		for i in 13:
			var t := i / 12.0
			arc.append(from + Vector2(dir * t * 70.0, -rise * 4.0 * t * (1.0 - t)))
		draw_polyline(arc, ShintyStyle.GOLD, 2.0, true)
		draw_circle(arc[arc.size() - 1], 3.5, ShintyStyle.TEXT)
		var label := "%s  %s%d°" % ["BACK" if back else "FRONT", "+" if deg >= 0.0 else "", int(deg)]
		var w := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		var x := cx + dir * 72.0 - w * 0.5
		draw_string(f, Vector2(clampf(x, 8.0, size.x - w - 8.0), sole + 21.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, ShintyStyle.MUTED)
