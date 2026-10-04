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
var _grounds := {}   ## venue -> its ShintyPitch, built (in the tree only while shown)
var _building := {}  ## venue -> [ShintyPitch, worker task id]
var _want_venue := -1
var _prebuild := false
var _looks := {}     ## side and club -> that club's ShintyPlayerModel
var _want_teams: Array = []
var _teams_timer: SceneTreeTimer

## No scenery or sun shadows: for tests on slow software renderers.
static var lite := false

## Where the two camans cross over the centre spot (metres).
const THROW_UP_CROSS := Vector3(0.0, 2.3, 0.15)
## How far past the centre each caman head reaches, so the shafts cross below
## the heads and each bas curls in over the other.
const CROSS_PAST := 0.22


func _ready() -> void:
	_show_ground(maxi(Game.venue, 0))
	# Get the other grounds ready in the background, so picking one is instant.
	get_tree().create_timer(1.5).timeout.connect(func(): _prebuild = true)
	ball = ShintyBallModel.new()
	ball.simulate = false
	ball.auto_find_hails = false
	ball.display_scale = 1.4
	add_child(ball)
	ball.place(Vector3(0, 0.04, 0.15))

	camera = Camera3D.new()
	camera.fov = 42.0
	camera.near = 0.05
	camera.far = 900.0
	add_child(camera)
	camera.make_current()
	_to = _shot_transform(_shot)
	_from = _to
	camera.transform = _to


func _hero(player: Dictionary, team: Dictionary, side: int) -> ShintyPlayerModel:
	var pos := Vector3(-0.5 if side == 0 else 0.5, 0, 0.15)
	var m := ShintyPlayerModel.new()
	m.setup(player, team)
	add_child(m)
	m.position = pos
	m.rotation.y = -PI * 0.5 if side == 0 else PI * 0.5
	# The throw-up: face to face over the ball, camans raised and crossed
	# high over the spot, waiting for the referee to throw it up.
	m.reach_face = Vector3(signf(pos.x), 0.0, 0.0)  # toe curls in, toward the other bas
	m.held_pose = &"throw_up"
	m.set_reach(THROW_UP_CROSS + Vector3(-signf(pos.x) * CROSS_PAST, 0.0, 0.0), 1.0)
	m.look_at_point(Vector3(0, 1.4, 0.15))
	return m


## Dress the two players in the picked clubs' kits. Uses each club's number 11
## (or first outfield player) so heights and builds differ per club.
## Each club's player is built once and kept, so flicking back is instant;
## a club not seen yet is built once the picker stops on it.
func set_teams(home: Dictionary, away: Dictionary) -> void:
	_want_teams = [home, away]
	if _looks.is_empty() or (_looks.has(_look_key(0, home)) and _looks.has(_look_key(1, away))):
		_apply_teams()
		return
	_teams_timer = get_tree().create_timer(0.2)
	var timer := _teams_timer
	timer.timeout.connect(func():
		if timer == _teams_timer:
			_apply_teams())


func _apply_teams() -> void:
	_teams_timer = null
	var shown: Array = []
	for side in 2:
		var team: Dictionary = _want_teams[side]
		var key := _look_key(side, team)
		if not _looks.has(key):
			_looks[key] = _hero(_face_of(team), team, side)
		shown.append(_looks[key])
	for m in _looks.values():
		var on: bool = m in shown
		m.visible = on
		m.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	home_player = shown[0]
	away_player = shown[1]


func _look_key(side: int, team: Dictionary) -> String:
	return "%d:%d" % [side, hash(team)]  # a new kit or caman design makes a new key


func _face_of(team: Dictionary) -> Dictionary:
	for p in team.get("players", []):
		if str(p.get("position", "")) == "CF":
			return p
	var ps: Array = team.get("players", [])
	return ps[ps.size() - 1] if not ps.is_empty() else {}


## Move the match to another ground. Each ground is built once on a worker
## thread and then kept, so changing ground never stalls the menu.
func set_venue(v: int) -> void:
	_want_venue = v
	if _grounds.has(v):
		_show_ground(v)
	elif not _building.has(v):
		var p := _new_ground(v)
		_building[v] = [p, WorkerThreadPool.add_task(p.build_now, false, "menu ground")]


func _new_ground(v: int) -> ShintyPitch:
	var p: ShintyPitch = PitchScene.instantiate()
	p.venue = v
	p.lighting = 1  # summer evening: low, warm light for the menus
	p.graphics_quality = Game.graphics_quality
	p.show_placeholder_goals = true
	p.add_ground_collision = false
	if lite:
		p.show_scenery = false
	return p


func _show_ground(v: int) -> void:
	if pitch and pitch.venue == v and pitch.is_inside_tree():
		return
	if not _grounds.has(v):
		_grounds[v] = _new_ground(v)  # built as it joins the tree
	if pitch and pitch.is_inside_tree():
		remove_child(pitch)
	pitch = _grounds[v]
	add_child(pitch)
	move_child(pitch, 0)
	if lite:
		for sun in pitch.find_children("*", "DirectionalLight3D", true, false):
			sun.shadow_enabled = false
	if bench:
		show_bench()  # stands just off this ground's touchline


## Takes in grounds the worker threads have finished, and builds the next one
## nobody has asked for yet, one at a time.
func _poll_grounds() -> void:
	for v in _building.keys():
		var job: Array = _building[v]
		if not WorkerThreadPool.is_task_completed(job[1]):
			continue
		WorkerThreadPool.wait_for_task_completion(job[1])
		_building.erase(v)
		job[0].finish_build()
		_grounds[v] = job[0]
		if v == _want_venue:
			_show_ground(v)
	if _prebuild and _building.is_empty():
		for v in ShintyPitch.VENUE_NAMES.size():
			if not _grounds.has(v):
				var p := _new_ground(v)
				_building[v] = [p, WorkerThreadPool.add_task(p.build_now, false, "menu ground")]
				break


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		# Don't wait here for a ground still being built: its thread can be
		# waiting on the renderer, which runs on this (the main) thread, so
		# waiting would freeze the game. A GroundReaper frees it once done.
		if not _building.is_empty():
			var reaper := GroundReaper.new()
			reaper.jobs = _building.values()
			Engine.get_main_loop().root.add_child.call_deferred(reaper)
		for g in _grounds.values():
			if is_instance_valid(g) and not g.is_inside_tree():
				g.free()


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
	_poll_grounds()
	_time += delta
	if _t < 1.0:
		_t = minf(1.0, _t + delta / 1.1)
	var k := ease(_t, -2.4)
	var tr := _from.interpolate_with(_to, k)
	# A slow handheld drift so the scene never looks frozen.
	var drift := 0.12 if _shot == "designer" else 1.0  # close to the bench: barely moves
	tr.origin += Vector3(sin(_time * 0.21) * 0.12, sin(_time * 0.33) * 0.05, cos(_time * 0.17) * 0.1) * drift
	camera.transform = tr


## Outlives the menu to free grounds whose worker threads were still
## building when the menu closed.
class GroundReaper extends Node:
	var jobs: Array = []

	func _init() -> void:
		add_to_group(&"ground_reapers")

	func _process(_delta: float) -> void:
		for job in jobs.duplicate():
			if WorkerThreadPool.is_task_completed(job[1]):
				WorkerThreadPool.wait_for_task_completion(job[1])
				job[0].free()
				jobs.erase(job)
		if jobs.is_empty():
			queue_free()
