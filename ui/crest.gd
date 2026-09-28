class_name ShintyCrest
extends Control
## A club crest: the club's logo, named by club id (e.g. "kingussie.png") in
## one of FOLDERS, or else a shield in the club colours with its initials.
## user://crests/ lets a player swap in their own badge without a rebuild.

const FOLDERS := ["user://crests/", "res://data/logos/", "res://crests/"]

static var _cache := {}

var team: Dictionary = {}:
	set(v):
		team = v
		_texture = badge_for(str(v.get("id", "")))
		queue_redraw()

var _texture: Texture2D


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## The club's badge image if one is installed, else null.
static func badge_for(id: String) -> Texture2D:
	if id == "":
		return null
	if _cache.has(id):
		return _cache[id]
	var tex: Texture2D = null
	for folder in FOLDERS:
		var path: String = folder + id + ".png"
		if folder.begins_with("res://") and ResourceLoader.exists(path):
			tex = load(path)
		elif FileAccess.file_exists(path):
			var img := Image.load_from_file(path)
			if img:
				tex = ImageTexture.create_from_image(img)
		if tex:
			break
	_cache[id] = tex
	return tex


static func initials(t: Dictionary) -> String:
	var s := str(t.get("short", ""))
	if s != "":
		return s.to_upper()
	var out := ""
	for w in str(t.get("name", "?")).split(" ", false):
		out += w.left(1)
	return out.left(3).to_upper()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	if _texture:
		var ts := _texture.get_size()
		var k := minf(r.size.x / ts.x, r.size.y / ts.y)
		var d := ts * k
		draw_texture_rect(_texture, Rect2((r.size - d) / 2.0, d), false)
		return
	var c: Dictionary = team.get("colors", {})
	var primary := Color(str(c.get("primary", "#33414a")))
	var secondary := Color(str(c.get("secondary", "#f2f2f2")))
	# Shield: flat top, straight sides, curving to a point.
	var w := minf(r.size.x, r.size.y / 1.15)
	var h := w * 1.15
	var o := (r.size - Vector2(w, h)) / 2.0
	var pts := PackedVector2Array()
	pts.append(o + Vector2(0, 0))
	pts.append(o + Vector2(w, 0))
	pts.append(o + Vector2(w, h * 0.52))
	for i in range(1, 12):
		var a := float(i) / 12.0
		var x := lerpf(w, w * 0.5, a)
		var y := lerpf(h * 0.52, h, sin(a * PI / 2.0))
		pts.append(o + Vector2(x, y))
	pts.append(o + Vector2(w * 0.5, h))
	var right_side := pts.size() - 1
	for i in range(right_side - 1, 2, -1):
		pts.append(Vector2(o.x * 2.0 + w - pts[i].x, pts[i].y))
	pts.append(o + Vector2(0, h * 0.52))
	draw_colored_polygon(pts, primary)
	# Diagonal sash in the second colour, clipped to the shield.
	var band := PackedVector2Array([
		o + Vector2(w * 0.62, 0), o + Vector2(w, 0), o + Vector2(w, h * 0.2),
		o + Vector2(w * 0.24, h * 0.9), o + Vector2(w * 0.05, h * 0.62)])
	var clipped := Geometry2D.intersect_polygons(band, pts)
	for poly in clipped:
		draw_colored_polygon(poly, Color(secondary, 0.9))
	var outline := pts.duplicate()
	outline.append(pts[0])
	draw_polyline(outline, secondary.lerp(Color.WHITE, 0.3), maxf(2.0, w * 0.035), true)
	# Initials with a soft shadow so they read on either colour.
	var f := ShintyStyle.font("black")
	var text := initials(team)
	var fs := int(w * (0.36 if text.length() <= 3 else 0.28))
	var tw := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var base := o + Vector2((w - tw) / 2.0, h * 0.5 + fs * 0.34)
	draw_string(f, base + Vector2(2, 3), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.45))
	draw_string(f, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
