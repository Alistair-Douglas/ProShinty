extends SceneTree
## Draws the board and shirt artwork for every sponsor in data/sponsors.json
## into broadcast/sponsors/. Needs a display (xvfb-run on a server):
##   xvfb-run godot --path . -s tests/render_sponsors.gd

const FONTS := {
	"Pacifico": "res://broadcast/fonts/Pacifico-Regular.ttf",
	"BreeSerif": "res://broadcast/fonts/BreeSerif-Regular.ttf",
	"RussoOne": "res://broadcast/fonts/RussoOne-Regular.ttf",
	"BarlowBlack": "res://ui/fonts/BarlowCondensed-BlackItalic.ttf",
}
const BOARD := Vector2i(1024, 152)
const SHIRT := Vector2i(480, 160)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://data/sponsors.json"))
	for s in data["sponsors"]:
		var font: Font = load(FONTS.get(s.get("font", ""), FONTS["BarlowBlack"]))
		await _render(_board(s, font), BOARD, "res://broadcast/sponsors/%s.png" % s["id"], false)
		await _render(_shirt(s, font), SHIRT, "res://broadcast/sponsors/%s_shirt.png" % s["id"], true)
	quit()


func _render(content: Control, size: Vector2i, path: String, transparent: bool) -> void:
	var vp := SubViewport.new()
	vp.size = size
	vp.transparent_bg = transparent
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	content.size = Vector2(size)
	vp.add_child(content)
	for i in 3:
		await process_frame
	var img := vp.get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(path))
	print("saved ", path)
	vp.queue_free()


func _fit(text: String, font: Font, max_w: float, start: int) -> int:
	var fs := start
	while fs > 12 and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > max_w:
		fs -= 2
	return fs


## Board: sponsor colour, name large, tagline smaller in the accent colour,
## with a slanted stripe at each end.
func _board(s: Dictionary, font: Font) -> Control:
	var c := Control.new()
	var tag_font: Font = load(FONTS["BarlowBlack"]).duplicate()
	var bg := Color(s["bg"])
	var fg := Color(s["fg"])
	var accent := Color(s["accent"])
	c.draw.connect(func():
		var w := float(BOARD.x)
		var h := float(BOARD.y)
		c.draw_rect(Rect2(0, 0, w, h), bg)
		for x0 in [0.0, w - 70.0]:
			c.draw_colored_polygon(PackedVector2Array([Vector2(x0 + 26, 0), Vector2(x0 + 44, 0), Vector2(x0 + 18, h), Vector2(x0, h)]), Color(accent, 0.8))
		var name: String = s["name"]
		var tag: String = s.get("tagline", "")
		var fs := _fit(name, font, w * 0.62, 96)
		var ts := int(fs * 0.42)
		var nw := font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var tw := tag_font.get_string_size(tag.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, ts).x
		var x := (w - (nw + 24 + tw)) / 2.0
		var asc := font.get_ascent(fs)
		var desc := font.get_descent(fs)
		var base := (h + asc - desc) / 2.0
		c.draw_string(font, Vector2(x, base), name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, fg)
		c.draw_string(tag_font, Vector2(x + nw + 24, base), tag.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, ts, accent if accent != bg else fg))
	return c


## Shirt print: the name only, white on transparent, so it takes the kit's
## trim colour.
func _shirt(s: Dictionary, font: Font) -> Control:
	var c := Control.new()
	c.draw.connect(func():
		var text: String = s.get("shirt", s["name"])
		var fs := _fit(text, font, SHIRT.x - 20.0, 120)
		var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var asc := font.get_ascent(fs)
		var desc := font.get_descent(fs)
		c.draw_string(font, Vector2((SHIRT.x - tw) / 2.0, (SHIRT.y + asc - desc) / 2.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE))
	return c
