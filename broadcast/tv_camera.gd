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
## Replays: a few set angles, chosen per replay (behind the goal, low from the
## side, and high from the far side).

const GANTRY_HEIGHT := 24.0
const GANTRY_BACK := 36.0     ## beyond the near touchline
const GANTRY_SLIDE := 0.22    ## how far the gantry camera tracks along the stand
const WINDOW := 34.0          ## yards of pitch across the screen in normal play
const WINDOW_FAST := 52.0     ## ... when the ball is flying long

var eye := Vector3.ZERO
var look := Vector3.ZERO
var fov := 30.0
var _started := false


## Update the live camera. `ball` is the ball's world position, `ball_vel`
## its velocity (world units per second), `half_width` half the pitch width.
## Returns [eye, look, vertical fov in degrees].
func live(delta: float, ball: Vector3, ball_vel: Vector3, half_length: float, half_width: float, aspect: float) -> Array:
	var lead := Vector3(ball_vel.x, 0.0, ball_vel.z) * 0.45
	var target := ball + lead
	target.x = clampf(target.x, -half_length + 12.0, half_length - 12.0)
	target.z = clampf(target.z * 0.7, -half_width * 0.6, half_width * 0.6)
	target.y = minf(ball.y * 0.4, 6.0)
	var new_eye := Vector3(target.x * GANTRY_SLIDE, GANTRY_HEIGHT, half_width + GANTRY_BACK)
	if not _started:
		_started = true
		look = target
		eye = new_eye
	# Critically damped follow: smooth, no overshoot, quicker when play is far off.
	var k := 1.0 - exp(-delta * 2.2)
	look = look.lerp(target, k)
	eye = eye.lerp(new_eye, 1.0 - exp(-delta * 1.2))
	var speed := Vector2(ball_vel.x, ball_vel.z).length()
	var window := lerpf(WINDOW, WINDOW_FAST, clampf((speed - 12.0) / 25.0, 0.0, 1.0))
	var dist := eye.distance_to(look)
	var fov_h := 2.0 * atan(window * 0.5 / dist)
	var fov_v := rad_to_deg(2.0 * atan(tan(fov_h * 0.5) / maxf(aspect, 0.5)))
	fov = lerpf(fov, clampf(fov_v, 9.0, 40.0), 1.0 - exp(-delta * 1.6))
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
