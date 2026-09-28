class_name ShintyStyle
extends RefCounted
## The look of the menus and loading screens: colours, fonts, the Godot theme
## and small builders for the recurring pieces (slanted tiles, panels, tags).
## Fonts are Barlow Condensed (SIL Open Font License, see ui/fonts/OFL.txt).

const INK := Color("0a1116")          ## page background behind everything
const PANEL := Color(0.06, 0.1, 0.13, 0.86)
const PANEL_LIGHT := Color(0.11, 0.17, 0.21, 0.92)
const LINE := Color(1, 1, 1, 0.12)
const TEXT := Color("f4f6f7")
const MUTED := Color("93a4ad")
const GOLD := Color("ffc82e")         ## focus, highlights, the main call to action
const GOLD_DARK := Color("1a1400")    ## text on gold
const HEATHER := Color("8b5cc7")      ## second accent, from the tartan
const GOOD := Color("5fd38a")
const BAD := Color("ff6b5a")

const SLANT := 0.22                   ## skew of tiles and buttons

static var _fonts := {}


static func font(weight: String = "semibold") -> Font:
	if not _fonts.has(weight):
		var file: String = {
			"medium": "BarlowCondensed-Medium.ttf",
			"semibold": "BarlowCondensed-SemiBold.ttf",
			"bold": "BarlowCondensed-Bold.ttf",
			"black": "BarlowCondensed-BlackItalic.ttf",
		}[weight]
		_fonts[weight] = load("res://ui/fonts/" + file)
	return _fonts[weight]


## Theme for every menu control. Buttons are slanted, focus is gold.
static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = font("semibold")
	t.default_font_size = 20

	t.set_color("font_color", "Label", TEXT)

	var normal := box(PANEL_LIGHT, SLANT)
	normal.border_width_left = 3
	normal.border_color = Color(1, 1, 1, 0.18)
	var hover := box(Color(0.16, 0.24, 0.29, 0.95), SLANT)
	hover.border_width_left = 3
	hover.border_color = GOLD
	var pressed := box(GOLD.darkened(0.15), SLANT)
	for s in [normal, hover, pressed]:
		s.content_margin_left = 28
		s.content_margin_right = 28
		s.content_margin_top = 8
		s.content_margin_bottom = 8
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("hover_pressed", "Button", pressed)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_stylebox("disabled", "Button", box(Color(0.1, 0.13, 0.15, 0.6), SLANT))
	t.set_font("font", "Button", font("bold"))
	t.set_font_size("font_size", "Button", 22)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", TEXT)
	t.set_color("font_focus_color", "Button", GOLD_DARK)
	t.set_color("font_pressed_color", "Button", GOLD_DARK)
	t.set_color("font_hover_pressed_color", "Button", GOLD_DARK)

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.25)
	sb.set_corner_radius_all(3)
	t.set_stylebox("grabber", "VScrollBar", sb)
	t.set_stylebox("grabber_highlight", "VScrollBar", sb)
	t.set_stylebox("scroll", "VScrollBar", box(Color(1, 1, 1, 0.05)))
	return t


static func box(color: Color, skew := 0.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.skew = Vector2(skew, 0)
	s.anti_aliasing = true
	return s


## Makes a Button draw gold while it has keyboard/controller focus, the same
## as when the mouse is over it, so there is always one obvious choice.
static func focus_button(b: Button) -> void:
	var gold := box(GOLD, SLANT)
	gold.content_margin_left = 28
	gold.content_margin_right = 28
	b.focus_entered.connect(func():
		b.add_theme_stylebox_override("normal", gold)
		b.add_theme_stylebox_override("hover", gold)
		b.add_theme_color_override("font_color", GOLD_DARK)
		b.add_theme_color_override("font_hover_color", GOLD_DARK))
	b.focus_exited.connect(func():
		for n in ["normal", "hover"]:
			b.remove_theme_stylebox_override(n)
		b.remove_theme_color_override("font_color")
		b.remove_theme_color_override("font_hover_color"))
	b.mouse_entered.connect(func(): b.grab_focus())


static func label(text: String, size := 20, weight := "semibold", color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(weight))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Small caps-style tag, like "HOME" or "YOU".
static func tag(text: String, bg: Color, fg := GOLD_DARK) -> PanelContainer:
	var p := PanelContainer.new()
	var s := box(bg, SLANT)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 1
	s.content_margin_bottom = 1
	p.add_theme_stylebox_override("panel", s)
	p.add_child(label(text, 16, "bold", fg))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


## Colour for a rating badge, FIFA style: gold 75+, silver 65+, bronze below.
static func rating_color(ovr: int) -> Color:
	if ovr >= 75:
		return Color("e9c24a")
	if ovr >= 65:
		return Color("b9c3c9")
	return Color("c7865a")


## Team rating out of five stars, in half stars, spread across the ratings the
## squads actually use.
static func stars(ovr: int) -> float:
	return clampf(snappedf((ovr - 52) / 5.0, 0.5), 0.5, 5.0)


## Readable text colour on top of `bg`.
static func text_on(bg: Color) -> Color:
	return GOLD_DARK if bg.get_luminance() > 0.55 else TEXT
