class_name ShintyPrematch
extends Node
## The build-up before the first throw-up, the way TV opens a game: a camera
## flight over the ground, the two teams walking out side by side behind the
## referee with the team sheets on screen, then down to the throw-up and over
## to the live camera. A, Space or Enter skips it.
##
## The match is held (manual_step) until it ends; the view draws the players
## from their match state as usual, so this only moves them about: it keeps
## everyone's throw-up spot and puts them back there before play starts.
## Lives under the match view, which calls step() and place_camera() each
## drawn frame while `view.prematch` is set.

const TeamData := preload("res://scripts/team_data.gd")

const FLIGHT := 6.5          ## seconds of flight over the ground
const WALK := 8.5            ## ... walking out
const SETTLE := 3.5          ## ... down to the throw-up and over to live
const SETTLE_SKIPPED := 1.2
const FADE := 0.6            ## the dip to black between walk-out and throw-up
const WALK_SPEED := 1.7      ## yards a second, a steady walk
const FILE_GAP := 1.6        ## yards between players in each file
const FILE_SIDE := 1.1       ## each file this far either side of halfway
const HEAD_START_Y := 2.0    ## the referee starts this far onto the pitch (far side, between the dugouts)

var view: Node3D
var m: Node
var t := 0.0
var overlay: Control

var _snap := {}              ## Player -> [pos, facing, throw_up]
var _ref_snap := []
var _settle_from := -1.0     ## when the throw-up shot began (t)
var _settle_len := SETTLE
var _fade_at := -1.0         ## when the dip to black began (t)
var _ground := ""
var _crests: Array = []
var _lineups: Array = [[], []]   ## per team: [[number, name, position], ...]
var _flight := {}            ## the ground's own way round, if it has one (ShintyPitch.intro_flight)


func setup(p_view: Node3D) -> void:
	view = p_view
	m = view.get_parent()
	process_mode = Node.PROCESS_MODE_ALWAYS
	m.manual_step = true     # hold the match: no clock, no throw-up yet
	for p in m.players:
		_snap[p] = [p.pos, p.facing, p.throw_up]
	var ref = m.referee
	_ref_snap = [ref.pos, ref.facing]
	_ground = ShintyPitch.VENUE_NAMES[clampi(int(m.config.get("venue", 0)), 0, ShintyPitch.VENUE_NAMES.size() - 1)]
	_crests = [TeamData.logo(m.teams[0]), TeamData.logo(m.teams[1])]
	_flight = view.pitch.intro_flight()
	for t2 in 2:
		for p in m.squads[t2]:
			_lineups[t2].append([p.number, str(p.data.get("name", "")), p.position_code])
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	overlay = Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.draw.connect(_draw_overlay)
	layer.add_child(overlay)
	view.ball.visible = false   # in the referee's pocket until the throw-up
	_walk_positions(0.0)


## Moves everyone for this frame. Time only runs once the match is on screen
## (a loading screen may build it underneath first).
func step(delta: float) -> void:
	if view.get_tree().current_scene != m:
		_walk_positions(0.0)
		return
	t += delta
	var skip := t > 0.3 and (Input.is_action_just_pressed("ui_accept") or Input.is_action_just_pressed("pass")
		or Input.is_action_just_pressed("shoot"))
	if skip:
		if _settle_from >= 0.0:
			_finish()
			return
		if _fade_at < 0.0:
			_fade_at = t
			_settle_len = SETTLE_SKIPPED
	if _fade_at < 0.0 and t >= FLIGHT + WALK - FADE * 0.5:
		_fade_at = t
	if _fade_at >= 0.0 and _settle_from < 0.0 and t >= _fade_at + FADE * 0.5:
		# Under the black: everyone to their throw-up spots.
		_settle_from = t
		_restore()
		view.ball.visible = true
	if _settle_from < 0.0:
		_walk_positions(maxf(0.0, t - FLIGHT))
	elif t >= _settle_from + _settle_len:
		_finish()
		return
	overlay.queue_redraw()


## Where each file has got to `s` seconds into the walk-out: the referee in
## front, home on the left file and away on the right, walking towards the
## TV side.
func _walk_positions(s: float) -> void:
	var head := Vector2(m.PITCH.x / 2.0, HEAD_START_Y + WALK_SPEED * s)
	var vel := Vector2(0.0, WALK_SPEED if s > 0.0 else 0.0)
	var ref = m.referee
	ref.pos = head
	ref.vel = vel
	ref.facing = Vector2(0, 1)
	for team in 2:
		var side := -FILE_SIDE if team == 0 else FILE_SIDE
		var i := 0
		for p in m.squads[team]:
			if not (p in m.players):
				continue
			p.pos = head + Vector2(side, -2.2 - i * FILE_GAP)
			p.vel = vel
			p.facing = Vector2(0, 1)
			p.throw_up = false
			i += 1


func _restore() -> void:
	for p in _snap:
		p.pos = _snap[p][0]
		p.facing = _snap[p][1]
		p.throw_up = _snap[p][2]
		p.vel = Vector2.ZERO
	var ref = m.referee
	ref.pos = _ref_snap[0]
	ref.facing = _ref_snap[1]
	ref.vel = Vector2.ZERO


func _finish() -> void:
	if _settle_from < 0.0:
		_restore()
	view.ball.visible = true
	m.manual_step = false
	view.prematch = null
	queue_free()


## The camera for this frame.
func place_camera(cam: Camera3D, delta: float) -> void:
	var shot: Array
	if _settle_from >= 0.0:
		# Low by the throw-up, rising and swinging over to the live camera.
		var live: Array = view.director.live_camera(delta)
		var k := clampf((t - _settle_from) / _settle_len, 0.0, 1.0)
		k = k * k * (3.0 - 2.0 * k)
		var centre: Vector3 = view.w(m.PITCH / 2.0)
		var low := [centre + Vector3(5.0, 2.6, 8.0), centre + Vector3(0, 1.4, 0), 40.0]
		shot = [low[0].lerp(live[0], k), low[1].lerp(live[1], k), lerpf(low[2], live[2], k)]
	elif t < FLIGHT:
		shot = _flight_shot(t / FLIGHT)
	else:
		shot = _walk_shot(t - FLIGHT)
	cam.position = shot[0]
	cam.look_at(shot[1], Vector3.UP)
	cam.fov = shot[2]


## High over the ground, sweeping round from behind one goal and coming down
## towards the stand (or the ground's own way round).
func _flight_shot(k: float) -> Array:
	var e := k * k * (3.0 - 2.0 * k)
	var a := lerpf(_flight.get("from", -0.55), _flight.get("to", 1.2), e)
	var r := lerpf(115.0, _flight.get("radius", 85.0), e)
	var h := lerpf(55.0, _flight.get("height", 32.0), e)   # stays over the trees round the ground
	var centre: Vector3 = view.w(m.PITCH / 2.0)
	var eye: Vector3 = centre + Vector3(cos(a) * r, h, sin(a) * r)
	var look: Vector3 = _flight.get("look", Vector3.ZERO)
	return [eye, centre + Vector3(0, 0, -10.0).lerp(look, e), lerpf(42.0, 36.0, e)]


## In front of the referee, low, backing away as the teams come on.
func _walk_shot(s: float) -> Array:
	var head: Vector3 = view.w(Vector2(m.PITCH.x / 2.0, HEAD_START_Y + WALK_SPEED * s))
	var k := clampf(s / WALK, 0.0, 1.0)
	var eye: Vector3 = head + Vector3(lerpf(6.0, -3.0, k), 1.9, 9.0)
	return [eye, head + Vector3(0, 1.2, -6.0), 42.0]


# ---------------------------------------------------------------- graphics

func _draw_overlay() -> void:
	var screen := overlay.get_viewport_rect().size
	if t < FLIGHT and _settle_from < 0.0:
		_draw_title(screen, clampf(t / 0.6, 0.0, 1.0) * clampf((FLIGHT - t) / 0.5, 0.0, 1.0))
	elif _settle_from < 0.0:
		var s := t - FLIGHT
		var a := clampf(s / 0.5, 0.0, 1.0) * clampf((WALK - FADE - s) / 0.4, 0.0, 1.0)
		_draw_sheet(screen, 0, a)
		_draw_sheet(screen, 1, a)
	if _fade_at >= 0.0:
		var f := 1.0 - absf((t - _fade_at) / (FADE * 0.5) - 1.0)
		if f > 0.0:
			overlay.draw_rect(Rect2(Vector2.ZERO, screen), Color(0, 0, 0, clampf(f, 0.0, 1.0)))
	var black := ShintyStyle.font("black")
	overlay.draw_string(black, Vector2(screen.x - 220, screen.y - 22), "Ⓐ / SPACE  SKIP", HORIZONTAL_ALIGNMENT_RIGHT, 200, 15,
		Color(1, 1, 1, 0.6))


## "LIVE FROM" the ground, with the fixture under it.
func _draw_title(screen: Vector2, a: float) -> void:
	if a <= 0.0:
		return
	var black := ShintyStyle.font("black")
	var bold := ShintyStyle.font("bold")
	var w := 640.0
	var x := (screen.x - w) / 2.0
	var y := screen.y - 190.0
	var ink := ShintyStyle.INK
	ink.a = 0.92 * a
	var gold := ShintyStyle.GOLD
	gold.a = a
	var white := Color(1, 1, 1, a)
	overlay.draw_rect(Rect2(x, y, w, 38), gold)
	overlay.draw_string(black, Vector2(x, y + 28), "LIVE FROM " + _ground.to_upper(), HORIZONTAL_ALIGNMENT_CENTER, w, 22, Color(ShintyStyle.GOLD_DARK, a))
	overlay.draw_rect(Rect2(x, y + 38, w, 70), ink)
	for side in 2:
		var col: Color = m.colors[side][0]
		col.a = a
		var bx := x if side == 0 else x + w - 8
		overlay.draw_rect(Rect2(bx, y + 38, 8, 70), col)
		var cx := x + 22.0 if side == 0 else x + w - 76.0
		if _crests[side] != null:
			overlay.draw_texture_rect(_crests[side], Rect2(Vector2(cx, y + 45), Vector2(56, 56)), false, Color(1, 1, 1, a))
		var name := str(m.teams[side].get("name", "")).to_upper()
		var nx := x + 90.0 if side == 0 else x + w / 2.0 + 30.0
		overlay.draw_string(bold, Vector2(nx, y + 82), name, HORIZONTAL_ALIGNMENT_LEFT if side == 0 else HORIZONTAL_ALIGNMENT_RIGHT,
			w / 2.0 - 120.0, 24, white)
	overlay.draw_string(black, Vector2(x + w / 2.0 - 30, y + 82), "v", HORIZONTAL_ALIGNMENT_CENTER, 60, 24, gold)


## A team sheet down one side: crest, club, then number, name and position.
func _draw_sheet(screen: Vector2, side: int, a: float) -> void:
	if a <= 0.0:
		return
	var black := ShintyStyle.font("black")
	var bold := ShintyStyle.font("bold")
	var w := 300.0
	var row := 24.0
	var rows: Array = _lineups[side]
	var h := 70.0 + rows.size() * row + 10.0
	var slide := (1.0 - a) * (w + 40.0)
	var x := 32.0 - slide if side == 0 else screen.x - w - 32.0 + slide
	var y := (screen.y - h) / 2.0 - 10.0
	var ink := ShintyStyle.INK
	ink.a = 0.9
	var col: Color = m.colors[side][0]
	overlay.draw_rect(Rect2(x, y, w, h), ink)
	overlay.draw_rect(Rect2(x, y, w, 62), col.darkened(0.15))
	overlay.draw_rect(Rect2(x, y + 62, w, 4), ShintyStyle.GOLD)
	var tx := x + 14.0
	if _crests[side] != null:
		overlay.draw_texture_rect(_crests[side], Rect2(Vector2(x + 10, y + 7), Vector2(48, 48)), false)
		tx = x + 68.0
	var text_col := Color.WHITE if col.get_luminance() < 0.6 else ShintyStyle.INK
	overlay.draw_string(black, Vector2(tx, y + 30), str(m.teams[side].get("name", "")).to_upper(), HORIZONTAL_ALIGNMENT_LEFT,
		x + w - tx - 10.0, 20, text_col)
	overlay.draw_string(bold, Vector2(tx, y + 51), "STARTING TWELVE", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(text_col, 0.8))
	var ry := y + 66.0 + 6.0
	for r in rows:
		overlay.draw_string(black, Vector2(x + 12, ry + 18), str(r[0]), HORIZONTAL_ALIGNMENT_RIGHT, 28, 16, ShintyStyle.GOLD)
		overlay.draw_string(bold, Vector2(x + 52, ry + 18), str(r[1]), HORIZONTAL_ALIGNMENT_LEFT, w - 110, 16, Color.WHITE)
		overlay.draw_string(bold, Vector2(x + w - 52, ry + 18), str(r[2]), HORIZONTAL_ALIGNMENT_RIGHT, 40, 14, ShintyStyle.MUTED)
		ry += row
