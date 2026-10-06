class_name ShintyStars
extends Control
## A team's star rating: five stars, filled in half-star steps, sized to the
## control's height.

const GAP := 0.18   # space between stars, as a share of a star's width

var stars := 0.0:
	set(v):
		stars = v
		queue_redraw()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Width needed to show five stars at height `h`.
static func width_for(h: float) -> float:
	return h * (5.0 + 4.0 * GAP)


func _draw() -> void:
	var h := size.y
	for i in 5:
		var star := _star(Vector2(h * (1.0 + GAP) * i + h / 2.0, h * 0.54), h / 2.0)
		draw_colored_polygon(star, Color(ShintyStyle.MUTED, 0.35))
		var fill := clampf(stars - i, 0.0, 1.0)
		if fill >= 1.0:
			draw_colored_polygon(star, ShintyStyle.GOLD)
		elif fill > 0.0:
			var left := h * (1.0 + GAP) * i + h * fill
			var mask := PackedVector2Array([Vector2(left - h, -1.0), Vector2(left, -1.0), Vector2(left, h + 1.0), Vector2(left - h, h + 1.0)])
			for poly in Geometry2D.intersect_polygons(star, mask):
				draw_colored_polygon(poly, ShintyStyle.GOLD)


static func _star(c: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in 10:
		var a := -PI / 2.0 + k * PI / 5.0
		pts.append(c + Vector2(cos(a), sin(a)) * (r if k % 2 == 0 else r * 0.45))
	return pts
