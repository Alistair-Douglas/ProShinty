class_name ShintyTVCamera
extends RefCounted
## Camera work for the match, the way TV covers a game.
##
## Live: one main camera on a gantry high in the stand at halfway. It pans to
## follow play, leading the ball a little, and zooms so the action fills the
## screen: tight when play is on the far side or at the other end, wider for
## long balls. Positions are in the match view's world units (yards, centre
## spot at the origin, near touchline at +z).
##
## Two more live angles for close play (Settings > Camera, or Y on the pause
## screen): close TV, a lower gantry nearer the touchline that tracks the
## play along the stand, and end to end, low behind your player looking up
## the park. A click of the right stick zooms any of them in and out.
##
## Replays: a few set angles, chosen per replay (behind the goal, low from the
## side, and high from the far side).

const GANTRY_HEIGHT := 24.0
const GANTRY_BACK := 36.0     ## beyond the near touchline
const GANTRY_SLIDE := 0.22    ## how far the gantry camera tracks along the stand
const WINDOW := 34.0          ## yards of pitch across the screen in normal play
const WINDOW_FAST := 52.0     ## ... when the ball is flying long

const CLOSE_HEIGHT := 11.0
const CLOSE_BACK := 13.0
const CLOSE_SLIDE := 0.65
const CLOSE_WINDOW := 24.0
const CLOSE_WINDOW_FAST := 38.0
const BEHIND_BACK := 15.0     ## end to end: yards behind the player
const BEHIND_HEIGHT := 7.5
const BEHIND_AHEAD := 14.0    ## ... and where it looks, ahead of them
const ZOOM_IN := 0.62         ## zoomed: the window or distance shrinks to this

enum View { TV, CLOSE, BEHIND }

var view := View.TV
var zoomed := false
var eye := Vector3.ZERO
var look := Vector3.ZERO
var fov := 30.0
var _started := false
var _zoom := 1.0              ## eased towards 1.0 or ZOOM_IN
var _view_was := -1


## Update the live camera. `ball` is the ball's world position, `ball_vel`
## its velocity (world units per second), `half_width` half the pitch width.
## Returns [eye, look, vertical fov in degrees].
func live(delta: float, ball: Vector3, ball_vel: Vector3, half_length: float, half_width: float, aspect: float) -> Array:
	_zoom = lerpf(_zoom, ZOOM_IN if zoomed else 1.0, 1.0 - exp(-delta * 4.0))
	if view != _view_was:
		# A new angle cuts straight to it, as a TV director would.
		_view_was = view
		_started = false
	if view == View.CLOSE:
		return _gantry(delta, ball, ball_vel, half_length, half_width, aspect,
			CLOSE_HEIGHT, CLOSE_BACK, CLOSE_SLIDE, CLOSE_WINDOW, CLOSE_WINDOW_FAST)
	return _gantry(delta, ball, ball_vel, half_length, half_width, aspect,
		GANTRY_HEIGHT, GANTRY_BACK, GANTRY_SLIDE, WINDOW, WINDOW_FAST)


func _gantry(delta: float, ball: Vector3, ball_vel: Vector3, half_length: float, half_width: float, aspect: float,
		height: float, back: float, slide: float, window_slow: float, window_fast: float) -> Array:
	var lead := Vector3(ball_vel.x, 0.0, ball_vel.z) * 0.45
	var target := ball + lead
	target.x = clampf(target.x, -half_length + 12.0, half_length - 12.0)
	target.z = clampf(target.z * 0.7, -half_width * 0.6, half_width * 0.6)
	target.y = minf(ball.y * 0.4, 6.0)
	var new_eye := Vector3(target.x * slide, height, half_width + back)
	if not _started:
		_started = true
		look = target
		eye = new_eye
	# Critically damped follow: smooth, no overshoot, quicker when play is far off.
	var k := 1.0 - exp(-delta * 2.2)
	look = look.lerp(target, k)
	eye = eye.lerp(new_eye, 1.0 - exp(-delta * 1.2))
	var speed := Vector2(ball_vel.x, ball_vel.z).length()
	var window := lerpf(window_slow, window_fast, clampf((speed - 12.0) / 25.0, 0.0, 1.0)) * _zoom
	var dist := eye.distance_to(look)
	var fov_h := 2.0 * atan(window * 0.5 / dist)
	var fov_v := rad_to_deg(2.0 * atan(tan(fov_h * 0.5) / maxf(aspect, 0.5)))
	fov = lerpf(fov, clampf(fov_v, 9.0, 40.0), 1.0 - exp(-delta * 1.6))
	return [eye, look, fov]


## End to end: low behind `player` (world position), looking the way their
## side attacks (`attack` is +1 or -1 along x), drawn a little towards the
## ball so a pass or a ball over the top stays in shot.
func behind(delta: float, player: Vector3, ball: Vector3, attack: float, half_length: float, half_width: float) -> Array:
	_zoom = lerpf(_zoom, ZOOM_IN if zoomed else 1.0, 1.0 - exp(-delta * 4.0))
	if view != _view_was:
		_view_was = view
		_started = false
	var d := Vector3(signf(attack) if attack != 0.0 else 1.0, 0.0, 0.0)
	var focus := player.lerp(ball, 0.3)
	focus.y = 0.0
	focus.x = clampf(focus.x, -half_length - 4.0, half_length + 4.0)
	focus.z = clampf(focus.z, -half_width, half_width)
	var target_look := focus + d * BEHIND_AHEAD * _zoom + Vector3(0, 1.0, 0)
	# Stay square to the pitch, sliding across with the play rather than
	# swinging round, so up the screen is always up the park.
	var target_eye := focus - d * BEHIND_BACK * _zoom + Vector3(0, BEHIND_HEIGHT * lerpf(0.75, 1.0, _zoom), 0)
	target_eye.z = focus.z * 0.85
	if not _started:
		_started = true
		eye = target_eye
		look = target_look
	eye = eye.lerp(target_eye, 1.0 - exp(-delta * 3.0))
	look = look.lerp(target_look, 1.0 - exp(-delta * 4.0))
	fov = lerpf(fov, 50.0, 1.0 - exp(-delta * 3.0))
	return [eye, look, fov]


## Replay angle `kind` (0 behind the goal, 1 low side, 2 high far side),
## following the ball; `goal_x` is the x of the goal that was scored in.
static func replay_shot(kind: int, ball: Vector3, goal_x: float, half_width: float) -> Array:
	var end := signf(goal_x)
	match kind:
		0:
			# Behind the goal, a little above the crossbar, looking out at play.
			var e := Vector3(goal_x + end * 14.0, 5.0, clampf(ball.z * 0.3, -6.0, 6.0))
			return [e, ball + Vector3(0, 1.0, 0), 30.0]
		1:
			# Low and close, from the near side, level with the play.
			var e := Vector3(ball.x - end * 9.0, 1.8, minf(ball.z + 15.0, half_width + 6.0))
			return [e, ball + Vector3(0, 1.1, 0), 30.0]
		_:
			# High on the far side, just in front of the boards, looking back.
			var e := Vector3(ball.x * 0.7 - end * 6.0, 9.0, -half_width - 1.5)
			return [e, ball + Vector3(0, 0.5, 0), 24.0]
