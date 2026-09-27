class_name ShintyMatchAdapter
extends RefCounted
## Glue between the shinty models (metres, 3D) and the match in
## shinty-game (yards; 2D pitch position plus a height). The match keeps
## ball_pos/ball_vel (Vector2, yards) and ball_z/ball_vz (height, yards); the
## view maps pitch (x, y) to world (x, z) with one unit per yard.
##
## Three things live here:
##  * build_player(): a ShintyPlayerModel scaled to yards, returned in the same
##    dictionary shape match_view.gd's _build_player() uses.
##  * strike(): ShintyStrike physics, answered in the match's yard units.
##  * BallSim: ShintyBallPhysics (drag, spin, bounce, roll, posts, net, goals)
##    stepped on the match's ball variables.

const YARD := 0.9144              ## metres per yard
const TO_YARDS := 1.0 / YARD


## A player figure for match_view.gd. `team` is the team dictionary from
## teams.json (or use team_from_colors()). The returned dictionary has the
## old keys (root, leg_l, leg_r, caman) as empty pivots, so existing code that
## rotates them keeps working while it is switched over, plus `model`.
static func build_player(parent: Node3D, player_data: Dictionary, team: Dictionary) -> Dictionary:
	var root := Node3D.new()
	parent.add_child(root)
	var model := ShintyPlayerModel.new()
	model.scale = Vector3.ONE * TO_YARDS
	root.add_child(model)
	model.setup(player_data, team)
	var pivots := {}
	for key in ["leg_l", "leg_r", "caman"]:
		var n := Node3D.new()
		n.name = key
		root.add_child(n)
		pivots[key] = n
	return {"root": root, "model": model, "leg_l": pivots["leg_l"], "leg_r": pivots["leg_r"],
		"caman": pivots["caman"], "was_swinging": false}


## A team dictionary from two colours, for code that only has m.colors.
static func team_from_colors(primary: Color, secondary: Color) -> Dictionary:
	return {"colors": {"primary": "#" + primary.to_html(false), "secondary": "#" + secondary.to_html(false)}}


## Per-frame update for a figure built above. `vel` is the player's velocity
## in yards/s; `swing_timer` is the match's p.swing (starts at 0.25-0.3 when a
## hit happens); `ball_world` is the ball position in view space, for the
## head to follow (or null).
static func update_player(f: Dictionary, vel: Vector2, swing_timer: float, is_keeper_action: bool = false, ball_world = null) -> void:
	var model: ShintyPlayerModel = f["model"]
	model.set_locomotion(Vector3(vel.x, 0.0, vel.y) * YARD)
	if ball_world != null:
		model.look_at_point(ball_world)
	var swinging := swing_timer > 0.0
	if swinging and not f["was_swinging"]:
		model.play_hit_now(&"swing", 0.9)
	f["was_swinging"] = swinging


## ShintyStrike in yards. `dir` is the aim on the pitch (Vector2); `loft` is
## 0..1; `ball_vel`/`ball_vz` are the ball's current velocity in yards/s.
## Returns {ball_vel: Vector2, ball_vz: float, miss, mishit, quality}.
static func strike(player_data: Dictionary, dir: Vector2, power: float, loft: float, kind: String,
		ball_vel: Vector2 = Vector2.ZERO, ball_vz: float = 0.0, contact_offset_yards: float = 0.0,
		rng: RandomNumberGenerator = null) -> Dictionary:
	var skill := float(player_data.get("passing" if kind == "pass" else "shooting", 60))
	var res := ShintyStrike.compute({
		"aim": Vector3(dir.x, 0.0, dir.y), "power": power, "skill": skill,
		"control": float(player_data.get("control", 60)), "loft": loft,
		"ball_velocity": Vector3(ball_vel.x, ball_vz, ball_vel.y) * YARD,
		"contact_offset": contact_offset_yards * YARD, "rng": rng,
	})
	var v: Vector3 = res["velocity"] * TO_YARDS
	return {"ball_vel": Vector2(v.x, v.z), "ball_vz": v.y, "spin": res["spin"],
		"miss": res["miss"], "mishit": res["mishit"], "quality": res["quality"]}


## Drop-in for match.gd's _strike_speed(): the match asks for a speed and an
## upward speed (both yards/s); this turns them into a swing power and loft for
## the player's rating, then runs the strike physics. `skill_key` is the
## rating used ("shooting" or "passing"); `skill_bonus` is the match's
## difficulty modifier (as a fraction, e.g. 0.05).
static func strike_like_match(player_data: Dictionary, dir: Vector2, speed: float, vz: float,
		skill_key: String, ball_vel: Vector2 = Vector2.ZERO, ball_vz: float = 0.0,
		skill_bonus: float = 0.0, rng: RandomNumberGenerator = null) -> Dictionary:
	var data := player_data.duplicate()
	var skill := clampf(float(data.get(skill_key, 60)) + skill_bonus * 100.0, 1.0, 99.0)
	data["shooting"] = skill
	data["passing"] = skill
	var power := ShintyStrike.power_for_speed(speed * YARD, skill)
	var loft := ShintyStrike.loft_for_angle(rad_to_deg(atan2(vz, maxf(speed, 0.1))))
	return strike(data, dir, power, loft, "pass" if skill_key == "passing" else "shot", ball_vel, ball_vz, 0.0, rng)


## Like strike_like_match(), but runs ShintyStrike.compute_swing(), so the
## ball can curve and be miss-hit (thin, fat, heel, toe or a fresh-air miss).
## `difficulty` (0..1) is the extra error from the situation (running flat
## out, off balance, under pressure, an overswing); `contact_offset_yards` is
## how far the ball was from the bas when the swing arrived.
## Returns strike_like_match()'s keys plus kind, curve and side_spin.
static func swing_like_match(player_data: Dictionary, dir: Vector2, speed: float, vz: float,
		skill_key: String, ball_vel: Vector2 = Vector2.ZERO, ball_vz: float = 0.0,
		skill_bonus: float = 0.0, difficulty: float = 0.0, contact_offset_yards: float = 0.0,
		rng: RandomNumberGenerator = null) -> Dictionary:
	var skill := clampf(float(player_data.get(skill_key, 60)) + skill_bonus * 100.0, 1.0, 99.0)
	var res := ShintyStrike.compute_swing({
		"aim": Vector3(dir.x, 0.0, dir.y),
		"power": ShintyStrike.power_for_speed(speed * YARD, skill),
		"loft": ShintyStrike.loft_for_angle(rad_to_deg(atan2(vz, maxf(speed, 0.1)))),
		"skill": skill, "control": clampf(float(player_data.get("control", 60)) + skill_bonus * 100.0, 1.0, 99.0),
		"ball_velocity": Vector3(ball_vel.x, ball_vz, ball_vel.y) * YARD,
		"difficulty": difficulty, "contact_offset": contact_offset_yards * YARD, "rng": rng,
	})
	var v: Vector3 = res["velocity"] * TO_YARDS
	return {"ball_vel": Vector2(v.x, v.z), "ball_vz": v.y, "spin": res["spin"],
		"miss": res["miss"], "mishit": res["mishit"], "quality": res["quality"],
		"kind": res["kind"], "curve": res["curve"], "side_spin": res["side_spin"]}


## Ball physics running on the match's variables. Create one per match:
##   var sim := ShintyMatchAdapter.BallSim.new(PITCH, GOAL_W, CROSSBAR)
## then each tick replace the ball integration with
##   var events := sim.step(self, dt)
## Events have a "type" (bounce, landed, stopped, post, net, goal) and, for
## goals, "end" = 0 for the hail at x = 0 or 1 for the one at x = PITCH.x.
class BallSim:
	var physics := ShintyBallPhysics.new()
	var _hails: Array = []
	var _spin_pending := false
	var _pending_spin := Vector3.ZERO

	func _init(pitch: Vector2, goal_w_yards: float, crossbar_yards: float) -> void:
		for end in [0, 1]:
			var h := ShintyHailModel.new()
			h.width = goal_w_yards * YARD
			h.height = crossbar_yards * YARD
			var z_axis := Vector3(-1, 0, 0) if end == 0 else Vector3(1, 0, 0)
			var basis := Basis(Vector3.UP.cross(z_axis), Vector3.UP, z_axis)
			var origin := Vector3(pitch.x * end, 0.0, pitch.y / 2.0) * YARD
			h.physics_transform = Transform3D(basis, origin)
			h.set_meta("end", end)
			_hails.append(h)
		physics.hails = _hails

	## Call when the match sets the ball directly (throw-up, shy, hit, carry).
	func pull(m) -> void:
		physics.position = Vector3(m.ball_pos.x, 0.0, m.ball_pos.y) * YARD \
			+ Vector3(0, m.ball_z * YARD + ShintyBallPhysics.RADIUS, 0)
		physics.velocity = Vector3(m.ball_vel.x, m.ball_vz, m.ball_vel.y) * YARD

	## Write the ball state back into the match.
	func push(m) -> void:
		var p := physics.position * TO_YARDS
		m.ball_pos = Vector2(p.x, p.z)
		m.ball_z = maxf(0.0, (physics.position.y - ShintyBallPhysics.RADIUS) * TO_YARDS)
		var v := physics.velocity * TO_YARDS
		m.ball_vel = Vector2(v.x, v.z)
		m.ball_vz = v.y

	## Pull, simulate dt seconds, push. Spin is kept between calls as long as
	## the match does not change the velocity itself; call set_spin() after a
	## strike to pass on ShintyStrike's spin.
	func step(m, dt: float) -> Array:
		var keep_spin := physics.spin
		var before := physics.velocity
		pull(m)
		if physics.velocity.distance_to(before) > 0.05:
			keep_spin = Vector3.ZERO if not _spin_pending else _pending_spin
			physics.goal_armed = true
		_spin_pending = false
		physics.spin = keep_spin
		var events := physics.step(dt)
		push(m)
		for e in events:
			if e.has("hail"):
				e["end"] = e["hail"].get_meta("end")
				e.erase("hail")
		return events

	func set_spin(spin: Vector3) -> void:
		_spin_pending = true
		_pending_spin = spin

	## Where a lofted ball will land, in pitch yards.
	func predict_landing() -> Vector2:
		var p := physics.predict_landing() * TO_YARDS
		return Vector2(p.x, p.z)
