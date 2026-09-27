class_name ShintyBallPhysics
extends RefCounted
## Flight, bounce and roll of a shinty ball, in metres and seconds.
## Pure state and maths (no nodes), so the match logic can run it headless.
## Gravity, air drag and Magnus lift from spin act in the air; the ball bounces
## on grass and then rolls to a stop. Hails (ShintyHailModel nodes) in `hails`
## add post, crossbar and net collisions and report goals.

const RADIUS := 0.032          ## shinty ball: about 6.4 cm across
const MASS := 0.078            ## kg (cork and worsted core in leather)
const GRAVITY := 9.81
const AIR_DENSITY := 1.2
const DRAG_CD := 0.45
const GROUND_RESTITUTION := 0.45  ## share of vertical speed kept on a bounce
const BOUNCE_FRICTION := 0.82     ## share of horizontal speed kept on a bounce
const ROLL_DECEL := 1.3           ## m/s^2 of grass resistance
const ROLL_DRAG := 0.22           ## extra slowing per second, proportional to speed
const SPIN_DECAY := 0.5
const ROLL_CURVE := 0.012         ## m/s^2 of sideways pull per rad/s of sidespin while rolling
const ROLL_SPIN_DECAY := 1.4      ## sidespin dies faster once the ball grips the grass

const _AREA := PI * RADIUS * RADIUS
const K_DRAG := 0.5 * AIR_DENSITY * DRAG_CD * _AREA / MASS
const K_LIFT := 0.5 * AIR_DENSITY * _AREA / MASS

var position := Vector3(0, RADIUS, 0)
var velocity := Vector3.ZERO
var spin := Vector3.ZERO          ## angular velocity, rad/s
var ground_y := 0.0
var hails: Array = []             ## ShintyHailModel nodes to collide with
var goal_armed := true            ## re-armed on every strike so a goal counts once


func duplicate_state() -> ShintyBallPhysics:
	var c := ShintyBallPhysics.new()
	c.position = position
	c.velocity = velocity
	c.spin = spin
	c.ground_y = ground_y
	return c


func is_airborne() -> bool:
	return position.y > ground_y + RADIUS + 0.003 or velocity.y > 0.05


func height() -> float:
	return position.y - RADIUS - ground_y


## Hit the ball: set its velocity (m/s) and spin (rad/s).
func strike(new_velocity: Vector3, new_spin: Vector3 = Vector3.ZERO) -> void:
	velocity = new_velocity
	spin = new_spin
	goal_armed = true
	if velocity.y > 0.0:
		position.y = maxf(position.y, ground_y + RADIUS + 0.004)


func place(at: Vector3) -> void:
	position = Vector3(at.x, maxf(at.y, ground_y + RADIUS), at.z)
	velocity = Vector3.ZERO
	spin = Vector3.ZERO
	goal_armed = true


## Advance by dt seconds. Returns events as dictionaries with a "type" of
## bounce, landed, stopped, post, net or goal (plus position and details).
func step(dt: float) -> Array:
	var events: Array = []
	var n := clampi(ceili(velocity.length() * dt / 0.04), 1, 32)
	var h := dt / n
	for i in n:
		var prev := position
		var was_moving := velocity.length_squared() > 0.0001
		_integrate(h, events)
		for hail in hails:
			if is_instance_valid(hail):
				hail.collide_ball(self, prev, events, h)
		if was_moving and velocity.length_squared() <= 0.0001 and not is_airborne():
			events.append({"type": "stopped", "position": position})
	return events


## Where the ball will first touch the ground (ignores hails). Returns the
## current position if it is already on the ground.
func predict_landing(max_time: float = 8.0) -> Vector3:
	if not is_airborne():
		return position
	var c := duplicate_state()
	var t := 0.0
	while t < max_time:
		var ev := c.step(1.0 / 120.0)
		t += 1.0 / 120.0
		for e in ev:
			if e["type"] == "bounce" or e["type"] == "landed":
				return e["position"]
	return c.position


## Time until the ball first touches the ground, or 0 if it is on it.
func predict_air_time(max_time: float = 8.0) -> float:
	if not is_airborne():
		return 0.0
	var c := duplicate_state()
	var t := 0.0
	while t < max_time:
		var ev := c.step(1.0 / 120.0)
		t += 1.0 / 120.0
		for e in ev:
			if e["type"] == "bounce" or e["type"] == "landed":
				return t
	return max_time


func _integrate(h: float, events: Array) -> void:
	var floor_y := ground_y + RADIUS
	if is_airborne():
		var s := velocity.length()
		var acc := Vector3(0, -GRAVITY, 0)
		if s > 0.01:
			acc -= velocity * (K_DRAG * s)
			var w := spin.length()
			if w > 0.5:
				var cl := minf(0.3, 1.2 * RADIUS * w / s)
				var lift_dir := spin.cross(velocity)
				if lift_dir.length_squared() > 1e-8:
					acc += lift_dir.normalized() * (K_LIFT * cl * s * s)
		velocity += acc * h
		position += velocity * h
		spin *= exp(-SPIN_DECAY * h)
		if position.y < floor_y:
			position.y = floor_y
			var vy := -velocity.y
			var flat := Vector3(velocity.x, 0, velocity.z)
			if vy > 1.2:
				events.append({"type": "bounce", "position": position, "speed": vy})
				velocity = flat * BOUNCE_FRICTION + Vector3(0, vy * GROUND_RESTITUTION, 0)
				var side := spin.y
				spin = spin.lerp(Vector3.UP.cross(velocity) / RADIUS, 0.5)
				spin.y = side * 0.7  # sidespin survives the bounce, so it kicks on
			else:
				events.append({"type": "landed", "position": position})
				velocity = flat * BOUNCE_FRICTION
	else:
		position.y = floor_y
		velocity.y = 0.0
		var s := velocity.length()
		var side := spin.y * exp(-ROLL_SPIN_DECAY * h)
		if s > 0.0:
			var ns := maxf(0.0, s - (ROLL_DECEL + ROLL_DRAG * s) * h)
			velocity *= ns / s
			# A ball rolling with sidespin drifts the way it is spinning.
			if ns > 0.5 and absf(side) > 0.5:
				var sideways := Vector3.UP.cross(velocity / ns)
				velocity += sideways * (side * ROLL_CURVE * h)
				velocity = velocity.normalized() * ns
			if ns < 0.05:
				velocity = Vector3.ZERO
		position += velocity * h
		spin = Vector3.UP.cross(velocity) / RADIUS + Vector3.UP * side
