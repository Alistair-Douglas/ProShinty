class_name ShintyMenuBackdrop
extends Node3D
## The live 3D scene behind the menus: the chosen ground, a ball on the centre
## spot and two players in the picked clubs' kits squaring up to each other.
## The camera eases between a few framings as the menu changes screen.

const PitchScene := preload("res://pitch/shinty_pitch.tscn")

## Camera framings: position, and the point it looks at (metres, centre spot
## is the origin, the players stand either side of it along x).
const SHOTS := {
	"hub": [Vector3(-1.7, 1.1, 5.2), Vector3(-1.7, 1.05, 0.0)],
	"kickoff": [Vector3(0.0, 1.0, 5.4), Vector3(0.0, 0.62, 0.0)],
	"squads": [Vector3(-12.0, 3.0, 18.0), Vector3(4.0, 0.5, 0.0)],
	"wide": [Vector3(-26.0, 9.0, 40.0), Vector3(0.0, 0.0, 0.0)],
}

var pitch: Node3D
var camera: Camera3D
var home_player: ShintyPlayerModel
var away_player: ShintyPlayerModel
var ball: ShintyBallModel
## The caman designer's bench on the near touchline; built the first time the
## designer opens (see show_bench).
var bench: ShintyCamanBench

var _shot := "hub"
var _from := Transform3D()
var _to := Transform3D()
var _t := 1.0
var _time := 0.0
var _venue_timer: SceneTreeTimer

## No scenery or sun shadows: for tests on slow software renderers.
static var lite := false


func _ready() -> void:
	pitch = PitchScene.instantiate()
	pitch.venue = maxi(Game.venue, 0)
	pitch.lighting = 1  # summer evening: low, warm light for the menus
	pitch.show_placeholder_goals = true
	pitch.add_ground_collision = false
	if lite:
		pitch.show_scenery = false
	add_child(pitch)
	if lite:
		for sun in pitch.find_children("*", "DirectionalLight3D", true, false):
			sun.shadow_enabled = false

	var dummy := {"number": 0, "position": "CF", "pace": 70, "tackling": 60}
	home_player = _hero(dummy, Vector3(-0.62, 0, 0), -PI * 0.5)
	away_player = _hero(dummy, Vector3(0.62, 0, 0), PI * 0.5)
	ball = ShintyBallModel.new()
	ball.simulate = false
	ball.auto_find_hails = false
	ball.display_scale = 1.4
	add_child(ball)
	ball.place(Vector3(0, 0.04, 0.15))
	home_player.look_at_point(Vector3(0, 0.1, 0.15))
	away_player.look_at_point(Vector3(0, 0.1, 0.15))

	camera = Camera3D.new()
	camera.fov = 42.0
	camera.near = 0.05
	camera.far = 900.0
	add_child(camera)
	camera.make_current()
	_to = _shot_transform(_shot)
	_from = _to
	camera.transform = _to


func _hero(player: Dictionary, pos: Vector3, yaw: float) -> ShintyPlayerModel:
	var m := ShintyPlayerModel.new()
	add_child(m)
	m.setup(player)
	m.position = pos
	m.rotation.y = yaw
	m.charge_swing()  # camans drawn back, ready for the ball
	return m


## Dress the two players in the picked clubs' kits. Uses each club's number 11
## (or first outfield player) so heights and builds differ per club.
func set_teams(home: Dictionary, away: Dictionary) -> void:
	home_player.setup(_face_of(home), home)
	away_player.setup(_face_of(away), away)


func _face_of(team: Dictionary) -> Dictionary:
	for p in team.get("players", []):
		if str(p.get("position", "")) == "CF":
			return p
	var ps: Array = team.get("players", [])
	return ps[ps.size() - 1] if not ps.is_empty() else {}


## Move the match to another ground. Waits a moment so flicking through the
## list doesn't rebuild the scenery for every step.
func set_venue(v: int) -> void:
	if pitch.venue == v:
		return
	_venue_timer = get_tree().create_timer(0.45)
	var timer := _venue_timer
	timer.timeout.connect(func():
		if timer == _venue_timer:
			pitch.venue = v)


func set_shot(name: String, instant := false) -> void:
	_shot = name
	_from = camera.transform
	_to = _shot_transform(name)
	_t = 1.0 if instant else 0.0
	if instant:
		camera.transform = _to


## Puts the caman designer's bench just off the near touchline, a little
## towards the west hail, inside the rails and fences the grounds put 3 m out
## so nothing stands between the camera and the bench.
func show_bench() -> ShintyCamanBench:
	if bench == null:
		bench = ShintyCamanBench.new()
		add_child(bench)
	var p := Vector3(-9.0, 0.0, pitch.pitch_size().y * 0.5 + 0.8)
	p.y = pitch.ground_height(p)
	bench.position = p
	return bench


func _shot_transform(name: String) -> Transform3D:
	if name == "designer":
		return show_bench().camera_transform()
	var s: Array = SHOTS[name]
	return Transform3D.IDENTITY.translated(s[0]).looking_at(s[1], Vector3.UP)


func _process(delta: float) -> void:
	_time += delta
	if _t < 1.0:
		_t = minf(1.0, _t + delta / 1.1)
	var k := ease(_t, -2.4)
	var tr := _from.interpolate_with(_to, k)
	# A slow handheld drift so the scene never looks frozen.
	var drift := 0.12 if _shot == "designer" else 1.0  # close to the bench: barely moves
	tr.origin += Vector3(sin(_time * 0.21) * 0.12, sin(_time * 0.33) * 0.05, cos(_time * 0.17) * 0.1) * drift
	camera.transform = tr
