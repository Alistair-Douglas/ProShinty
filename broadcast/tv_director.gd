class_name ShintyTVDirector
extends Node
## Runs the match coverage like a TV director: the live camera, recording for
## replays, and after a goal the GOAL graphic followed by a replay from a
## couple of angles, with slow motion at the finish. After the whistle for a
## foul, a short replay of the foul before the free hit is taken. The match is
## held while a replay plays. A / Space / Enter (or any hit or pass) skips it.
##
## Lives under the match view, which calls live_camera() for its camera,
## after_frame() once it has drawn a frame, and step() instead of drawing
## while `playing` is true.

const REPLAY_DELAY := 1.8      ## seconds after the goal before the replay
const REPLAY_BEFORE := 6.0     ## seconds of play before the goal to show
const REPLAY_AFTER := 1.4      ## ... and after it
const SLOW_FROM := 2.2         ## slow motion for this long before the goal
const SLOW_SPEED := 0.4
const FOUL_DELAY := 0.9        ## seconds after the whistle before a foul replay
const FOUL_BEFORE := 3.5       ## seconds of play before the foul to show
const FOUL_AFTER := 0.8        ## ... and after it
const FOUL_SLOW := 1.2         ## slow motion for this long before the foul

var view: Node3D              ## the match view (its parent)
var m: Node                   ## the match
var graphics: ShintyTVGraphics
var camera := ShintyTVCamera.new()
var replay := ShintyReplay.new()
var playing := false
var replays_enabled := true
var foul_replays := true
var kind := ""                 ## "goal" or "foul" while a replay is playing

var _last_score := [0, 0]
var _replay_at := -1.0
var _goal_time := 0.0
var _goal_x := 0.0
var _t := 0.0
var _angle := 0
var _angles: Array = []
var _cam_look := Vector3.ZERO
var _ending := false
var _pending := ""            ## the replay waiting for _replay_at
var _whistles_seen := 0
var _caption := ""
var _foul_at := Vector3.ZERO  ## where the foul happened, in view space


func setup(p_view: Node3D, figures: Array, ball: Node3D) -> void:
	view = p_view
	m = view.get_parent()
	process_mode = Node.PROCESS_MODE_ALWAYS
	replay.track(figures, ball)
	_last_score = [m.score[0], m.score[1]]
	_whistles_seen = m.referee.whistles.size()


## Live camera: [eye, look, fov] for the match view.
func live_camera(delta: float) -> Array:
	var ball := Vector3(m.ball_pos.x - m.PITCH.x / 2.0, m.ball_z, m.ball_pos.y - m.PITCH.y / 2.0)
	var vel := Vector3(m.ball_vel.x, 0.0, m.ball_vel.y)
	var aspect: float = view.get_viewport().get_visible_rect().size.aspect()
	return camera.live(delta, ball, vel, m.PITCH.x / 2.0, m.PITCH.y / 2.0, aspect)


## Called by the view after each live frame.
func after_frame(delta: float) -> void:
	if m.paused:
		return  # nothing to record, and no replay starts under the pause menu
	replay.record(delta)
	for t in 2:
		if m.score[t] > _last_score[t]:
			_on_goal(t)
	_last_score = [m.score[0], m.score[1]]
	var whistles: Array = m.referee.whistles
	while _whistles_seen < whistles.size():
		_on_whistle(whistles[_whistles_seen])
		_whistles_seen += 1
	if _replay_at >= 0.0 and replay.time >= _replay_at:
		_replay_at = -1.0
		_start_replay()


func _on_goal(team: int) -> void:
	if graphics:
		graphics.show_goal(team)
	_goal_time = replay.time
	_goal_x = m.ball_pos.x - m.PITCH.x / 2.0
	if replays_enabled:
		_pending = "goal"
		_replay_at = replay.time + REPLAY_DELAY


## The referee blew for a foul: show it again before the free hit, unless a
## goal replay is already lined up.
func _on_whistle(w: Dictionary) -> void:
	if not (replays_enabled and foul_replays) or playing or _pending == "goal" and _replay_at >= 0.0:
		return
	_goal_time = replay.time - float(w.get("ago", 0.0))
	var at: Vector2 = w["at"]
	_foul_at = Vector3(at.x - m.PITCH.x / 2.0, 0.0, at.y - m.PITCH.y / 2.0)
	_goal_x = _foul_at.x
	_pending = "foul"
	_caption = "FOUL: %s" % String(m.referee.FOUL_NAMES.get(w["kind"], w["kind"])).to_upper()
	_replay_at = replay.time + FOUL_DELAY


func _start_replay() -> void:
	if graphics:
		graphics.wipe(_begin_playback)
	else:
		_begin_playback()


func _begin_playback() -> void:
	kind = _pending
	_pending = ""
	playing = true
	_ending = false
	m.process_mode = Node.PROCESS_MODE_DISABLED
	view.process_mode = Node.PROCESS_MODE_ALWAYS
	replay.hold_models(true)
	for f in replay.figures:
		for key in ["ring", "arrow", "tag"]:
			if f.has(key):
				f[key].visible = false
	if graphics:
		graphics.replay_active = true
		graphics.replay_caption = _caption if kind == "foul" else ""
	_t = maxf(replay.first_time(), _goal_time - (FOUL_BEFORE if kind == "foul" else REPLAY_BEFORE))
	# Two angles: the first chosen per goal, then from behind the goal. A
	# foul is seen from the side, then from across the pitch in slow motion.
	_angles = [[1, 2][randi() % 2], 0]
	if kind == "foul":
		_angles = [1, 2] if randi() % 2 == 0 else [2, 1]
	_angle = 0
	_cam_look = _focus(replay.show_at(_t))


## Advance the replay by one drawn frame.
func step(delta: float) -> void:
	if _ending:
		return
	var skip := Input.is_action_just_pressed("ui_accept") or Input.is_action_just_pressed("shoot") \
		or Input.is_action_just_pressed("pass")
	var foul := kind == "foul"
	var slow_from := FOUL_SLOW if foul else SLOW_FROM
	var speed := SLOW_SPEED if _t > _goal_time - slow_from else 1.0
	_t += delta * speed
	var end_t := minf(_goal_time + (FOUL_AFTER if foul else REPLAY_AFTER), replay.time)
	# Cut to the second angle for the last part.
	var cut_t := _goal_time - slow_from
	var want := 0 if _t < cut_t else 1
	if want != _angle:
		_angle = want
		_cam_look = _focus(replay.show_at(_t))
	var ball := _focus(replay.show_at(_t))
	_cam_look = _cam_look.lerp(ball, 1.0 - exp(-delta * 5.0))
	var shot := ShintyTVCamera.replay_shot(_angles[_angle], _cam_look, _goal_x, m.PITCH.y / 2.0)
	var cam: Camera3D = view.camera
	cam.position = shot[0]
	cam.look_at(shot[1], Vector3.UP)
	cam.fov = shot[2]
	if _t >= end_t or skip:
		_ending = true
		if graphics:
			graphics.wipe(_end_playback)
		else:
			_end_playback()


## What the replay camera follows: the ball, or for a foul the spot where it
## happened, leaning a little toward the ball.
func _focus(ball: Vector3) -> Vector3:
	if kind == "foul":
		return _foul_at.lerp(Vector3(ball.x, 0.0, ball.z), 0.3)
	return ball


func _end_playback() -> void:
	playing = false
	replay.hold_models(false)
	m.process_mode = Node.PROCESS_MODE_INHERIT
	view.process_mode = Node.PROCESS_MODE_INHERIT
	kind = ""
	if graphics:
		graphics.replay_active = false
	# Put everything back where the live match has it.
	replay.show_at(replay.time)
