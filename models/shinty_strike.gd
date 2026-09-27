class_name ShintyStrike
extends RefCounted
## The physics of a caman hitting the ball, in metres and seconds.
##
## A strike is a collision between the caman head (moving at a speed set by
## the player's power and rating) and the ball (which may already be moving).
## Along the line of the hit we use the one-dimensional collision law with a
## coefficient of restitution, so a ball coming towards the player is sent back
## harder than a still one, and a mistimed or off-centre contact loses pace
## and direction. Loft sets the launch angle and backspin (which lifts a
## lofted ball through ShintyBallPhysics' Magnus force).

const CAMAN_MASS := 0.36      ## effective mass of caman head plus hands at contact, kg
const RESTITUTION := 0.6      ## ash wood on a leather ball
const SWEET_SPOT := 0.08      ## m: contacts closer than this are clean
const MAX_REACH := 0.35       ## m: further than this from the head is a miss
const MIN_HEAD_SPEED := 9.0   ## m/s for a gentle tap
const MAX_HEAD_SPEED := 30.0  ## m/s for a full swing by an average hitter


## Caman head speed for a swing of `power` (0..1) by a player rated `skill`.
static func head_speed(power: float, skill: float) -> float:
	return lerpf(MIN_HEAD_SPEED, MAX_HEAD_SPEED, clampf(power, 0.0, 1.0)) * (0.85 + 0.3 * clampf(skill, 0.0, 99.0) / 99.0)


## Work out what happens when the caman meets the ball.
## Keys (all optional except aim):
##   aim: Vector3        direction to hit towards (flattened to the ground)
##   power: float        0..1, how hard the swing is
##   skill: float        shooting rating for shots, passing rating for passes
##   control: float      control rating (clean contact, fewer mishits)
##   loft: float         0 = along the ground, 1 = high lob
##   ball_velocity: Vector3  the ball's velocity before contact
##   contact_offset: float   metres between caman head and ball at contact
##   rng: RandomNumberGenerator  for repeatable results
## Returns {velocity, spin, speed, quality (0..1), miss (bool), mishit (bool)}.
static func compute(params: Dictionary) -> Dictionary:
	var rng: RandomNumberGenerator = params.get("rng", null)
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var ball_v: Vector3 = params.get("ball_velocity", Vector3.ZERO)
	var offset := float(params.get("contact_offset", 0.0))
	if offset > MAX_REACH:
		return {"velocity": ball_v, "spin": Vector3.ZERO, "speed": ball_v.length(),
			"quality": 0.0, "miss": true, "mishit": false}
	var power := clampf(float(params.get("power", 0.7)), 0.0, 1.0)
	var skill := clampf(float(params.get("skill", 60.0)), 0.0, 99.0)
	var control := clampf(float(params.get("control", 60.0)), 0.0, 99.0)
	var loft := clampf(float(params.get("loft", 0.0)), 0.0, 1.0)

	# Contact quality: how close to the middle of the bas the ball was met.
	var quality := 1.0 - smoothstep(SWEET_SPOT, MAX_REACH, offset)
	# Fast incoming balls are harder to meet cleanly.
	quality *= 1.0 - clampf((ball_v.length() - 10.0) / 60.0, 0.0, 0.35) * (1.0 - control / 99.0)
	var mishit := rng.randf() < lerpf(0.16, 0.02, control / 99.0) * (0.5 + power)
	if mishit:
		quality *= rng.randf_range(0.35, 0.7)

	# Direction: aim plus an error that grows with power and shrinks with skill.
	var aim: Vector3 = params.get("aim", Vector3.FORWARD)
	aim.y = 0.0
	aim = aim.normalized() if aim.length() > 0.001 else Vector3.FORWARD
	var sigma := deg_to_rad(lerpf(8.0, 1.2, skill / 99.0) * (0.6 + 0.8 * power) + (1.0 - quality) * 10.0)
	var yaw_err := rng.randfn(0.0, sigma)
	var flat := aim.rotated(Vector3.UP, yaw_err)
	var elev := deg_to_rad(lerpf(3.0, 38.0, loft)) + rng.randfn(0.0, deg_to_rad((1.0 - quality) * 9.0 + 1.0))
	elev = clampf(elev, deg_to_rad(-2.0), deg_to_rad(60.0))
	var n := (flat * cos(elev) + Vector3.UP * sin(elev)).normalized()

	# 1-D collision along n between the caman head and the ball.
	var m := ShintyBallPhysics.MASS
	var big_m := CAMAN_MASS
	var e := RESTITUTION * lerpf(0.6, 1.0, quality)
	var vh := head_speed(power, skill) * lerpf(0.55, 1.0, quality)
	var v_in := ball_v.dot(n)
	var v_out := ((m - e * big_m) * v_in + (1.0 + e) * big_m * vh) / (big_m + m)
	var tangential := (ball_v - n * v_in) * 0.15
	var velocity := n * v_out + tangential

	# Backspin for lofted hits (lift), sidespin from a slice or hook.
	var back_axis := flat.cross(Vector3.UP).normalized()
	var spin := back_axis * lerpf(8.0, 80.0, loft) * quality
	spin += Vector3.UP * clampf(-yaw_err * 60.0, -25.0, 25.0)
	return {"velocity": velocity, "spin": spin, "speed": velocity.length(),
		"quality": quality, "miss": false, "mishit": mishit}


## Hit a ShintyBallModel with a ShintyPlayerModel's caman. Uses the real
## distance between the caman head and the ball as the contact offset.
## `stats` is the player's JSON dictionary; `kind` is "shot" or "pass".
static func hit(player: ShintyPlayerModel, ball: ShintyBallModel, aim: Vector3, power: float,
		loft: float = 0.0, kind: String = "shot", rng: RandomNumberGenerator = null) -> Dictionary:
	var stats: Dictionary = player.player_data
	var skill := float(stats.get("passing" if kind == "pass" else "shooting", 60))
	var offset := player.get_caman_head_position().distance_to(ball.global_position)
	var res := compute({
		"aim": aim, "power": power, "skill": skill, "control": float(stats.get("control", 60)),
		"loft": loft, "ball_velocity": ball.get_velocity(), "contact_offset": offset, "rng": rng,
	})
	if not res["miss"]:
		ball.strike(res["velocity"], res["spin"])
	return res


## Power (0..1) to pass or shoot a still ball `distance` metres. Ground
## balls are aimed to still be rolling at `arrive_speed` when they get there;
## lofted balls to land at that distance. Returns -1 if out of range.
static func power_for_distance(distance: float, skill: float, loft: float = 0.0, arrive_speed: float = 4.0) -> float:
	var lo := 0.0
	var hi := 1.0
	if _carry(1.0, skill, loft, arrive_speed) < distance:
		return -1.0
	for i in 18:
		var mid := (lo + hi) / 2.0
		if _carry(mid, skill, loft, arrive_speed) < distance:
			lo = mid
		else:
			hi = mid
	return (lo + hi) / 2.0


## Power (0..1) that sends a still ball off at `speed` m/s with a clean
## contact. Values above 1 are beyond this player and are clamped.
static func power_for_speed(speed: float, skill: float) -> float:
	var m := ShintyBallPhysics.MASS
	var vh := speed * (CAMAN_MASS + m) / ((1.0 + RESTITUTION) * CAMAN_MASS)
	var base := vh / (0.85 + 0.3 * clampf(skill, 0.0, 99.0) / 99.0)
	return clampf((base - MIN_HEAD_SPEED) / (MAX_HEAD_SPEED - MIN_HEAD_SPEED), 0.0, 1.0)


## Loft (0..1) for a launch angle in degrees, the inverse of compute()'s mapping.
static func loft_for_angle(degrees: float) -> float:
	return clampf((degrees - 3.0) / 35.0, 0.0, 1.0)


## Chance (0..1) of trapping a ball arriving at `speed` m/s.
static func trap_chance(speed: float, control: float) -> float:
	var comfortable := 12.0 + control * 0.25
	return clampf(1.05 - maxf(0.0, speed - comfortable) / 20.0, 0.1, 0.98)


## How far a perfect strike carries: to first landing for lofted hits, or to
## where a ground ball has slowed to `arrive_speed`.
static func _carry(power: float, skill: float, loft: float, arrive_speed: float) -> float:
	var vh := head_speed(power, skill)
	var m := ShintyBallPhysics.MASS
	var e := RESTITUTION
	var v := (1.0 + e) * CAMAN_MASS * vh / (CAMAN_MASS + m)
	var elev := deg_to_rad(lerpf(3.0, 38.0, loft))
	var b := ShintyBallPhysics.new()
	var dir := Vector3(0, sin(elev), -cos(elev))
	b.strike(dir * v, Vector3.RIGHT * lerpf(8.0, 80.0, loft))  # backspin, as in compute()
	var t := 0.0
	while t < 12.0:
		var ev := b.step(1.0 / 60.0)
		t += 1.0 / 60.0
		if loft > 0.15:
			for x in ev:
				if x["type"] == "bounce" or x["type"] == "landed":
					return Vector2(b.position.x, b.position.z).length()
		elif not b.is_airborne() and b.velocity.length() <= arrive_speed:
			return Vector2(b.position.x, b.position.z).length()
	return Vector2(b.position.x, b.position.z).length()
