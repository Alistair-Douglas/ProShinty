extends Control
## Loading screen between the menu and a match: a full-screen picture from
## ui/loading/ with a shinty fact or tip, the match-up with both crests, and a
## progress bar. Once the match is loaded, any button starts it.
## The pictures are rendered from the game itself by tests/render_loading_art.gd.

const MATCH_SCENE := "res://scenes/match.tscn"
const OverlayShader := preload("res://ui/menu_overlay.gdshader")
const TartanShader := preload("res://ui/tartan.gdshader")
const MIN_SECONDS := 2.5

## Picture, headline, kicker and text for each loading screen.
const SLIDES := [
	["swing", "THE SWING", "TIP", "Hold Space to wind up, then let go to hit. The longer you hold, the harder the ball flies, so pick your moment."],
	["air", "IN THE AIR", "DID YOU KNOW", "Unlike hockey, shinty lets you play the ball in the air and strike it with either side of the caman."],
	["keeper", "LAST LINE", "DID YOU KNOW", "Each side fields twelve players: a goalkeeper and eleven outfield players, on a pitch up to 170 yards long."],
	["chase", "SHOULDER TO SHOULDER", "DID YOU KNOW", "Shinty is a contact sport. A fair shoulder-to-shoulder challenge is allowed, so hold your line when you chase a loose ball."],
	["first_ball", "FIRST BALL", "DID YOU KNOW", "Every match starts with the referee throwing the ball up between two players, who swing at it as it drops."],
]
const TIPS := [
	"Press Q to switch to the player nearest the ball.",
	"Hold Shift to sprint, but keep an eye on your stamina.",
	"Press E for a quick pass to the teammate you're facing.",
	"The Camanachd Association has run the sport since 1893.",
	"Shinty has been played in the Highlands for well over a thousand years.",
]

## Which picture comes next; starts random and then steps through them all.
static var _next := -1

var ready_to_play := false
var _elapsed := 0.0
var _progress := 0.0
var _shown := 0.0
var _art: TextureRect
var _bar: Control
var _prompt: Label
var _status: Label
var _tip: Label
var _tip_i := 0
var _packed: PackedScene


func _ready() -> void:
	theme = ShintyStyle.make_theme()
	if _next < 0:
		_next = randi() % SLIDES.size()
	var slide: Array = SLIDES[_next]
	_next = (_next + 1) % SLIDES.size()
	_tip_i = randi() % TIPS.size()

	var bg := ColorRect.new()
	bg.color = ShintyStyle.INK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_art = TextureRect.new()
	_art.texture = load("res://ui/loading/%s.jpg" % slide[0])
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_art.set_anchors_preset(Control.PRESET_FULL_RECT)
	_art.pivot_offset = Vector2(640, 360)
	add_child(_art)

	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	var sm := ShaderMaterial.new()
	sm.shader = OverlayShader
	sm.set_shader_parameter("left_shade", 0.88)
	sm.set_shader_parameter("bottom_shade", 0.8)
	shade.material = sm
	add_child(shade)

	var strip := ColorRect.new()
	var tm := ShaderMaterial.new()
	tm.shader = TartanShader
	strip.material = tm
	strip.size = Vector2(12, 720)
	add_child(strip)

	# Logo and "loading" at the top.
	var logo := HBoxContainer.new()
	logo.position = Vector2(52, 24)
	logo.add_theme_constant_override("separation", 5)
	logo.add_child(ShintyStyle.label("PRO", 30, "black", ShintyStyle.GOLD))
	logo.add_child(ShintyStyle.label("SHINTY", 30, "black"))
	add_child(logo)

	# The story for this picture.
	var story := VBoxContainer.new()
	story.position = Vector2(56, 206)
	story.custom_minimum_size = Vector2(560, 0)
	story.add_theme_constant_override("separation", 6)
	add_child(story)
	var kicker := ShintyStyle.tag(slide[2], ShintyStyle.GOLD)
	kicker.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	story.add_child(kicker)
	var head := ShintyStyle.label(slide[1], 76, "black")
	head.add_theme_constant_override("line_spacing", -18)
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.custom_minimum_size = Vector2(560, 0)
	story.add_child(head)
	var body := ShintyStyle.label(slide[3], 24, "medium", Color(1, 1, 1, 0.9))
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(500, 0)
	story.add_child(body)

	_build_matchup_bar()

	ResourceLoader.load_threaded_request(MATCH_SCENE)
	# Gentle push in on the picture, and fade up from black.
	_art.scale = Vector2.ONE * 1.02
	create_tween().tween_property(_art, "scale", Vector2.ONE * 1.1, 14.0)
	modulate = Color.BLACK
	create_tween().tween_property(self, "modulate", Color.WHITE, 0.35)


func _build_matchup_bar() -> void:
	var band := ColorRect.new()
	band.color = Color(0.03, 0.05, 0.07, 0.9)
	band.position = Vector2(0, 590)
	band.size = Vector2(1280, 130)
	add_child(band)
	var edge := ColorRect.new()
	var tm := ShaderMaterial.new()
	tm.shader = TartanShader
	edge.material = tm
	edge.position = Vector2(0, 586)
	edge.size = Vector2(1280, 4)
	add_child(edge)

	var cfg := {}
	if Game.teams.size() >= 2:
		cfg = Game.match_config()
		var home: Dictionary = cfg["home"]
		var away: Dictionary = cfg["away"]
		_team_block(home, Vector2(56, 606), false, Game.human_side == 0)
		_team_block(away, Vector2(56 + 250 + 70, 606), true, Game.human_side == 1)
		var vs := ShintyStyle.label("VS", 30, "black", ShintyStyle.GOLD)
		vs.position = Vector2(56 + 250 + 14, 624)
		add_child(vs)
		var venue: String = ShintyPitch.VENUE_NAMES[int(cfg.get("venue", 0))]
		var info := ShintyStyle.label("%s   ·   %s   ·   %d MINUTE HALVES" % [
			venue.to_upper(), ["EASY", "NORMAL", "HARD"][Game.difficulty], Game.half_minutes],
			16, "bold", ShintyStyle.MUTED)
		info.position = Vector2(56, 684)
		add_child(info)

	_status = ShintyStyle.label("LOADING", 18, "bold", ShintyStyle.MUTED)
	_status.position = Vector2(844, 606)
	add_child(_status)
	_bar = Control.new()
	_bar.position = Vector2(844, 636)
	_bar.size = Vector2(380, 16)
	_bar.draw.connect(_draw_bar)
	add_child(_bar)
	_prompt = ShintyStyle.label("PRESS SPACE OR  Ⓐ  TO PLAY", 24, "black", ShintyStyle.GOLD)
	_prompt.position = Vector2(844, 664)
	_prompt.visible = false
	add_child(_prompt)
	_tip = ShintyStyle.label("", 16, "semibold", Color(1, 1, 1, 0.7))
	_tip.position = Vector2(844, 668)
	_tip.size = Vector2(390, 40)
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip.text = "TIP  " + TIPS[_tip_i]
	add_child(_tip)


func _team_block(team: Dictionary, at: Vector2, right: bool, you: bool) -> void:
	var crest := ShintyCrest.new()
	crest.team = team
	crest.size = Vector2(52, 60)
	crest.position = at
	add_child(crest)
	var text := str(team["name"]).to_upper()
	var fs := 26
	while fs > 16 and ShintyStyle.font("black").get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > 186:
		fs -= 1
	var name := ShintyStyle.label(text, fs, "black")
	name.position = at + Vector2(62, 2 + (26 - fs) * 0.6)
	add_child(name)
	var sub := ShintyStyle.label(("YOU" if you else "CPU") + "   ·   OVR %d" % int(team["overall"]), 15, "bold",
		ShintyStyle.GOLD if you else ShintyStyle.MUTED)
	sub.position = at + Vector2(63, 34)
	add_child(sub)


func _draw_bar() -> void:
	var r := Rect2(Vector2.ZERO, _bar.size)
	_bar.draw_style_box(ShintyStyle.box(Color(1, 1, 1, 0.12), ShintyStyle.SLANT), r)
	var w := maxf(r.size.x * _shown, 10.0)
	_bar.draw_style_box(ShintyStyle.box(ShintyStyle.GOLD, ShintyStyle.SLANT), Rect2(Vector2.ZERO, Vector2(w, r.size.y)))
	# A ball rolling along the front of the bar.
	var c := Vector2(w, r.size.y * 0.5)
	_bar.draw_circle(c, 11.0, Color.WHITE)
	var a := _elapsed * 7.0
	_bar.draw_arc(c, 7.0, a, a + PI * 0.9, 12, Color(0.8, 0.1, 0.12), 1.6, true)
	_bar.draw_arc(c, 7.0, a + PI, a + PI * 1.9, 12, Color(0.8, 0.1, 0.12), 1.6, true)


func _process(delta: float) -> void:
	_elapsed += delta
	if not ready_to_play:
		var p := []
		var st := ResourceLoader.load_threaded_get_status(MATCH_SCENE, p)
		if st == ResourceLoader.THREAD_LOAD_LOADED:
			_progress = 1.0
		elif st == ResourceLoader.THREAD_LOAD_IN_PROGRESS and not p.is_empty():
			_progress = p[0]
		elif st == ResourceLoader.THREAD_LOAD_FAILED or st == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_status.text = "COULDN'T LOAD THE MATCH"
			_status.add_theme_color_override("font_color", ShintyStyle.BAD)
			set_process(false)
			return
		# The bar never runs ahead of the real load, and takes at least
		# MIN_SECONDS so the picture and fact can be read.
		_shown = minf(_progress, minf(1.0, _elapsed / MIN_SECONDS))
		if _shown >= 1.0:
			_packed = ResourceLoader.load_threaded_get(MATCH_SCENE)
			ready_to_play = true
			_status.text = "READY"
			_status.add_theme_color_override("font_color", ShintyStyle.GOLD)
			_tip.visible = false
			_prompt.visible = true
	else:
		_prompt.modulate.a = 0.55 + 0.45 * absf(sin(_elapsed * 2.6))
	if not ready_to_play and fmod(_elapsed, 4.0) < delta and _elapsed > 1.0:
		_tip_i = (_tip_i + 1) % TIPS.size()
		_tip.text = "TIP  " + TIPS[_tip_i]
	_bar.queue_redraw()


func _unhandled_input(e: InputEvent) -> void:
	if not ready_to_play:
		return
	var go: bool = (e is InputEventKey and e.pressed and not e.echo) \
		or (e is InputEventJoypadButton and e.pressed) \
		or (e is InputEventMouseButton and e.pressed)
	if go:
		get_viewport().set_input_as_handled()
		set_process_unhandled_input(false)
		var tw := create_tween()
		tw.tween_property(self, "modulate", Color.BLACK, 0.25)
		tw.tween_callback(func(): get_tree().change_scene_to_packed(_packed))
