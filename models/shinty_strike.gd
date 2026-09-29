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


## A full swing modelled the way golf games do it. Where compute() adds a
## single random aim error, this samples the things that really go wrong in a
## swing and lets the physics follow from them:
##   * face angle: which way the bas points at impact (sets start direction)
##   * swing path: which way the head is travelling (face minus path is
##     sidespin, so the ball curves: face left of path hooks left)
##   * strike point: high on the ball (thin, skids low), under it (fat, skied
##     and short), towards the heel or toe (loses pace, gear-effect spin)
## Extra keys on top of compute()'s:
##   difficulty: float    0..1 extra error from running flat out, being off
##                        balance, pressure or an overswing
##   contact_offset: float  metres the ball was away from the sweet spot when
##                        the swing arrived (adds to the strike point error)
##   shape: float         -1..1 deliberate curve (negative bends it left)
##   face_degrees: float  how far the caman's face is laid back from standard
##                        (ShintyCaman.face_degrees): more launch, a little
##                        less pace; negative for an upright face
## Returns compute()'s keys plus: kind ("clean", "thin", "fat", "heel", "toe",
## "fresh_air"), curve (face minus path, degrees) and side_spin (rad/s).
static func compute_swing(params: Dictionary) -> Dictionary:
	var rng: RandomNumberGenerator = params.get("rng", null)
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var ball_v: Vector3 = params.get("ball_velocity", Vector3.ZERO)
	var power := clampf(float(params.get("power", 0.7)), 0.0, 1.0)
	var sk := clampf(float(params.get("skill", 60.0)), 0.0, 99.0) / 99.0
	var ct := clampf(float(params.get("control", 60.0)), 0.0, 99.0) / 99.0
	var loft := clampf(float(params.get("loft", 0.0)), 0.0, 1.0)
	var diff := clampf(float(params.get("difficulty", 0.0)), 0.0, 1.0)
	var shape := clampf(float(params.get("shape", 0.0)), -1.0, 1.0)
	var offset := float(params.get("contact_offset", 0.0))
	var face_deg := float(params.get("face_degrees", 0.0))

	# How big the errors are: bigger swings, worse players, harder situations.
	var effort := (0.55 + 0.75 * power) * (1.0 + 1.6 * diff)
	var sig_face := deg_to_rad(lerpf(3.0, 0.6, sk)) * effort
	var sig_path := deg_to_rad(lerpf(2.4, 0.7, ct)) * effort
	var sig_v := lerpf(0.022, 0.006, ct) * effort
	var sig_l := lerpf(0.024, 0.007, ct) * effort
	# Now and then a swing really goes wrong (the golf "shank").
	if rng.randf() < lerpf(0.1, 0.015, ct) * (0.5 + power) * (1.0 + 2.0 * diff):
		sig_v *= 2.6
		sig_l *= 2.6
		sig_face *= 1.8
	# A fast ball coming across the swing is harder to time.
	var incoming := clampf((ball_v.length() - 8.0) / 30.0, 0.0, 1.0) * (1.0 - 0.6 * ct)
	sig_v *= 1.0 + incoming
	sig_l *= 1.0 + incoming
	var face := rng.randfn(0.0, sig_face)
	var path := rng.randfn(0.0, sig_path)
	var v_err := rng.randfn(0.0, sig_v) + offset * rng.randf_range(-0.7, 0.7)
	var l_err := rng.randfn(0.0, sig_l) + offset * rng.randf_range(-0.7, 0.7)
	# A deliberate curve: open or close the face against the path.
	face += deg_to_rad(4.0) * -shape
	path += deg_to_rad(2.5) * shape

	# Swinging over the top of it, or reaching and missing it entirely.
	if v_err > 0.05 or absf(l_err) > 0.085 or offset > MAX_REACH:
		return {"velocity": ball_v, "spin": Vector3.ZERO, "speed": ball_v.length(),
			"quality": 0.0, "miss": true, "mishit": true, "kind": "fresh_air",
			"curve": 0.0, "side_spin": 0.0}
	var miss_dist := Vector2(v_err, l_err).length()
	var quality := 1.0 - smoothstep(0.008, 0.07, miss_dist)
	var kind := "clean"
	if quality < 0.6:
		if absf(v_err) >= absf(l_err):
			kind = "thin" if v_err > 0.0 else "fat"
		else:
			kind = "toe" if l_err > 0.0 else "heel"

	# Gear effect: a toe hit twists the face shut, a heel hit opens it.
	face += l_err * 3.0
	var aim: Vector3 = params.get("aim", Vector3.FORWARD)
	aim.y = 0.0
	aim = aim.normalized() if aim.length() > 0.001 else Vector3.FORWARD
	# Start direction is mostly the face, a little the path (the golf D-plane).
	var start_yaw := face * 0.8 + path * 0.2
	var flat := aim.rotated(Vector3.UP, start_yaw)

	# Launch angle: thin contacts come off low, fat ones balloon.
	var elev_deg := lerpf(3.0, 38.0, loft) + face_deg
	if kind == "thin":
		elev_deg -= v_err * 260.0
	elif kind == "fat":
		elev_deg += -v_err * 420.0
	elev_deg += rng.randfn(0.0, 1.0 + (1.0 - quality) * 4.0)
	var elev := deg_to_rad(clampf(elev_deg, -2.0, 62.0))
	var n := (flat * cos(elev) + Vector3.UP * sin(elev)).normalized()

	# The collision itself, as in compute(). Fat hits lose the most pace.
	var m := ShintyBallPhysics.MASS
	var e := RESTITUTION * lerpf(0.6, 1.0, quality)
	var vh := head_speed(power, sk * 99.0) * lerpf(0.5, 1.0, quality)
	vh *= 1.0 - face_deg * 0.006  # a laid-back face glances more of the swing away
	if kind == "fat":
		vh *= lerpf(0.55, 1.0, quality)
	var v_in := ball_v.dot(n)
	var v_out := ((m - e * CAMAN_MASS) * v_in + (1.0 + e) * CAMAN_MASS * vh) / (CAMAN_MASS + m)
	var velocity := n * v_out + (ball_v - n * v_in) * 0.15

	# Spin: backspin from loft (more when fat, less when thin), sidespin from
	# face against path. Positive sidespin (about +Y) bends the ball left.
	var back := lerpf(8.0, 80.0, loft) * lerpf(0.5, 1.0, quality)
	if kind == "fat":
		back *= 1.6
	elif kind == "thin":
		back *= 0.3
	var side := clampf((face - path) * vh * 22.0, -90.0, 90.0)
	var back_axis := flat.cross(Vector3.UP).normalized()
	var spin := back_axis * back + Vector3.UP * side
	return {"velocity": velocity, "spin": spin, "speed": velocity.length(), "quality": quality,
		"miss": false, "mishit": kind != "clean", "kind": kind,
		"curve": rad_to_deg(face - path), "side_spin": side}


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
