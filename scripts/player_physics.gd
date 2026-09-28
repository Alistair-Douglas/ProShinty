extends RefCounted
## How players' bodies and camans move in the match. The AI and the human
## controls only say where each player wants to go (Player.desired) and what
## they want to do (hit, pass, tackle); everything here turns that into
## movement that has weight:
##
##  * Running (football): quick first steps, then a slower build to top
##    speed; braking takes a stride or two; the faster you go, the wider you
##    turn. Heavier players get going more slowly but win collisions.
##  * Contact (ice hockey): bodies are solid. Players who meet exchange
##    momentum, so a big player at speed knocks a smaller one off balance,
##    and a hard enough hit on the ball carrier knocks the ball loose.
##  * Caman: every player's stick head is tracked. It is carried in front on
##    the stick side, reaches out for a loose ball or an opponent's ball
##    (a hockey poke check), one-handed at full stretch (further, but only a
##    tap or a block, not control), and only touches the ball where the stick
##    head (or a keeper's hands and body) actually gets to it.
##  * Keeper: dives across when a shot is going wide of them.
##
## Units are the match's: yards, seconds, pitch x/y plus a height.

const BODY_R := 0.38          ## body radius for collisions (yards)
const STICK_REACH := 1.8      ## body centre to caman head at full stretch (one hand)
const TWO_HAND_REACH := 1.4   ## beyond this the lower hand lets go
const LUNGE_REACH := 0.5      ## extra reach while lunging (poke check or dive)
const STICK_SPEED := 10.0     ## how fast a player can move the caman head (yd/s)
const STICK_REST := Vector2(0.62, 0.23)  ## carried: ahead, and out to the stick side
const CONTACT_R := 0.32       ## caman head this close to the ball touches it
const BODY_BLOCK_R := 0.32    ## ball this close to a body is blocked by it
const BODY_HEIGHT := 1.9      ## yards; a ball above this goes over a player
const OVERHEAD := 2.6         ## height of the caman head in an overhead strike
const RESTITUTION := 0.2      ## how bouncy body contact is
const REACT_RADIUS := 3.2     ## start reaching for a loose ball this close
const STICK_CLEAR := 0.1      ## caman shaft and head keep this far off other bodies
const SPRINT_DRIVE := 1.6     ## extra acceleration while sprinting


static func setup(p) -> void:
	p.mass = float(ShintyPlayerModel.body_from_stats(p.data)["weight_kg"])
	p.hand = -1.0 if str(p.data.get("hand", "R")).to_upper().begins_with("L") else 1.0
	p.stick = rest_spot(p)


## Right-hand side of the way the player faces (pitch coordinates).
static func right_of(p) -> Vector2:
	return Vector2(-p.facing.y, p.facing.x)


## Where the caman head sits when the player is just carrying it.
static func rest_spot(p) -> Vector3:
	var v: Vector2 = p.pos + p.facing * STICK_REST.x + right_of(p) * (STICK_REST.y * p.hand)
	return Vector3(v.x, v.y, 0.0)


static func max_reach(p) -> float:
	var r := STICK_REACH
	if p.is_keeper():
		r += 0.15 + p.r("keeping") / 100.0 * 0.35
	if p.lunge > 0.0:
		r += LUNGE_REACH
	return r


## Highest point the caman head can get to at a horizontal distance `d`.
static func max_height(p, d: float, keeper_area: bool) -> float:
	var top := 3.2 if keeper_area else 2.3
	return maxf(0.3, top - 0.6 * maxf(0.0, d - 1.0))


# ---------------------------------------------------------------- running

static func move(m, p, dt: float) -> void:
	var top: float = p.top_speed() * lerpf(0.8, 1.0, p.stamina)
	if p == m.carrier:
		top *= 0.88
		if p.shielding:
			top *= m.SHIELD_SPEED
	if m.in_battle(p):
		top *= m.BATTLE_SLOW
	if p.swing_t >= 0.0:
		top *= 0.55   # planting the feet for the hit
	if p.stagger > 0.0:
		top *= 0.35
	# Running backwards (facing the ball while retreating) is slower.
	if p.desired.length() > 0.3 and p.desired.normalized().dot(p.facing) < -0.3:
		top *= 0.6
	var want: Vector2 = p.desired.limit_length(top)
	if p.shy_toss or (p.shy_ready and p == m.carrier) or p == m.set_piece_taker_now():
		want = Vector2.ZERO   # standing over a shy, hit-out or corner (turning still aims it)
	var old: Vector2 = p.vel
	var speed := old.length()
	var u: Vector2
	if speed > 0.3:
		u = old / speed
	elif want.length() > 0.01:
		u = want.normalized()
	else:
		u = p.facing
	var dv := want - old
	var along := dv.dot(u)
	var perp := dv - u * along
	var balance := 0.4 if p.stagger > 0.0 else 1.0
	var mass_k := pow(78.0 / maxf(p.mass, 40.0), 0.25)
	var frac := clampf(speed / maxf(top, 0.1), 0.0, 1.0)
	# Acceleration falls away as you near top speed. Sprinting drives
	# harder (a footballer's burst), so kicking on from a jog builds up to
	# full speed in about half a second instead of creeping there.
	var build: float = maxf(0.2, 1.0 - frac)
	if p.sprinting:
		build = maxf(0.35, 1.0 - frac * frac) * SPRINT_DRIVE
	var accel: float = (8.5 + p.r("pace") * 0.045) * mass_k * build * balance
	var brake: float = (13.0 + p.r("pace") * 0.03) * mass_k * balance
	# Turning: sharp at a jog, wide at full tilt.
	var turn: float = (15.0 + p.r("control") * 0.03) * (1.0 - 0.45 * frac) * mass_k * balance
	along = clampf(along, -brake * dt, accel * dt)
	perp = perp.limit_length(turn * dt)
	p.vel = old + u * along + perp
	p.accel = (p.vel - old) / maxf(dt, 0.0001)
	p.pos += p.vel * dt
	p.pos.x = clampf(p.pos.x, -2.0, m.PITCH.x + 2.0)
	p.pos.y = clampf(p.pos.y, -2.0, m.PITCH.y + 2.0)
	# The body turns at a limited rate too. Keepers, and anyone jogging or
	# standing, keep their eyes on the ball; runners face where they run.
	var look: Vector2 = p.desired
	if p.shielding and p == m.carrier:
		look = shield_dir(m, p)   # back into the man, ball on the far side
	var to_ball: Vector2 = m.ball_pos - p.pos
	if p != m.carrier and p.swing_t < 0.0 and to_ball.length() > 0.5 and to_ball.length() < 30.0 \
			and (p.is_keeper() or p.desired.length() < 3.0):
		look = to_ball
	if look.length() > 0.3:
		var rate := lerpf(12.0, 5.0, frac) * balance
		var ang: float = p.facing.angle_to(look)
		p.facing = p.facing.rotated(clampf(ang, -rate * dt, rate * dt)).normalized()
	if p.sprinting and p.vel.length() > 3.0:
		p.stamina = maxf(0.0, p.stamina - dt * 0.06 * (1.5 - p.r("stamina") / 100.0))
	else:
		p.stamina = minf(1.0, p.stamina + dt * 0.04)


## Shielding: the way to keep the ball, directly away from the nearest
## opponent (or where the player is going if nobody is close).
static func shield_dir(m, p) -> Vector2:
	var best = null
	var best_d := 6.0
	for o in m.squads[1 - p.team]:
		var d: float = o.pos.distance_to(p.pos)
		if d < best_d:
			best_d = d
			best = o
	if best == null or best_d < 0.01:
		return p.desired.normalized() if p.desired.length() > 0.3 else p.facing
	return (p.pos - best.pos) / best_d


# ---------------------------------------------------------------- contact

## Solid bodies: push overlapping players apart (heavier ones move less) and,
## when they were closing on each other, exchange momentum.
static func collide(m) -> void:
	var n: int = m.players.size()
	for i in n:
		var a = m.players[i]
		for j in range(i + 1, n):
			var b = m.players[j]
			var off: Vector2 = b.pos - a.pos
			var d := off.length()
			if d >= BODY_R * 2.0 or d < 0.001:
				continue
			var nrm := off / d
			var inv_a: float = 1.0 / a.mass
			var inv_b: float = 1.0 / b.mass
			var corr: float = (BODY_R * 2.0 - d) / (inv_a + inv_b)
			a.pos -= nrm * corr * inv_a
			b.pos += nrm * corr * inv_b
			var closing: float = (b.vel - a.vel).dot(nrm)
			if closing >= 0.0:
				continue
			var impulse: float = -(1.0 + RESTITUTION) * closing / (inv_a + inv_b)
			if a.team != b.team:
				impulse *= maxf(m.Counters.barge_contact(m, a, b), m.Counters.barge_contact(m, b, a))
			a.vel -= nrm * impulse * inv_a
			b.vel += nrm * impulse * inv_b
			if a.team != b.team:
				_knock(m, a, impulse * inv_a, b)
				_knock(m, b, impulse * inv_b, a)


## A player jolted by `dv` yards/s. Strong, balanced players ride it; past
## their limit they stumble, and a stumbling ball carrier loses the ball.
static func _knock(m, p, dv: float, by) -> void:
	var hold: float = 3.0 + (p.r("tackling") * 0.6 + p.r("control") * 0.4) / 100.0 * 3.0
	if p.shielding and p == m.carrier:
		hold *= 1.35   # braced, holding the ball up
	if p.stagger > 0.0:
		hold *= 0.6
	if dv > hold:
		# Knocked over from behind without a barge: a push in the back.
		# Only a clear shove counts; brushing into someone's back doesn't.
		if by.barge_t <= 0.0 and dv > hold * 1.25 and p.facing.dot((p.pos - by.pos).normalized()) > 0.5:
			m.events.append({"type": "foul", "kind": "push", "by": by, "on": p, "at": p.pos,
				"severity": clampf((dv - hold) / hold, 0.1, 1.0)})
		p.stagger = clampf(0.35 + (dv - hold) * 0.25, 0.35, 1.3)
		p.swing_t = -1.0
		m.anim(p, "stumble")
		m.events.append({"type": "knockdown", "team": p.team})
		if p == m.carrier:
			m.spill(p, by)
	elif p == m.carrier and dv > hold * 0.55 and randf() < (dv / hold - 0.55) * 0.8:
		m.spill(p, by)


# ---------------------------------------------------------------- caman

## Move each caman head towards what its player is reaching for, at the
## speed hands can move it, never further than arms and stick allow.
static func update_stick(m, p, dt: float) -> void:
	var rest := rest_spot(p)
	var target := rest
	var keeper_area: bool = p.is_keeper() and p.pos.distance_to(m.own_goal(p.team)) < 14.0
	p.stick_target = null
	if p == m.carrier and p.shielding:
		# Holding it up: the ball kept on the stick, on the far side of the body.
		var away: Vector2 = shield_dir(m, p)
		target = Vector3(p.pos.x + away.x * 0.75, p.pos.y + away.y * 0.75, 0.0)
	elif p == m.carrier:
		target = rest + Vector3(p.facing.x, p.facing.y, 0.0) * 0.08
		# Dribbling: the caman reaches out to meet the ball as the player runs
		# onto it, taps it, and comes back to be carried while it rolls on.
		var ball_at := Vector3(m.ball_pos.x, m.ball_pos.y, 0.0)
		if m.is_dribbling(p) and ball_at.distance_to(rest) < 1.0 + 0.5 * m.dribble_assist(p):
			target = ball_at
	elif p.shy_toss:
		target = Vector3(p.pos.x + p.facing.x * m.SHY_ARM, p.pos.y + p.facing.y * m.SHY_ARM, OVERHEAD)
	elif m.in_throw_up(p):
		# Caman raised high over the spot; as the ball drops, go up to meet it.
		target = Vector3(p.pos.x + p.facing.x * 0.45, p.pos.y + p.facing.y * 0.45, OVERHEAD)
		if m.throw_up_tossed and m.throw_up_t > m.throw_up_swing.get(p, 99.0) - 0.15:
			target = Vector3(m.ball_pos.x, m.ball_pos.y, clampf(m.ball_z, 1.5, OVERHEAD))
	elif p.stagger <= 0.0:
		var ball := Vector3(m.ball_pos.x, m.ball_pos.y, m.ball_z)
		var ahead := ball + Vector3(m.ball_vel.x, m.ball_vel.y, m.ball_vz) * 0.1
		var near: float = p.pos.distance_to(m.ball_pos)
		if p.block_t > 0.0:
			p.stick_target = Vector3(ball.x, ball.y, 0.0)   # back of the stick over the ball
		elif p.is_keeper() and p.save_point != null:
			p.stick_target = p.save_point
		elif m.carrier == null and near < REACT_RADIUS + (1.5 if keeper_area else 0.0):
			p.stick_target = ahead
		elif m.carrier != null and m.carrier.team != p.team and near < max_reach(p) + 0.8:
			p.stick_target = ball  # stick on the ball, hockey style
		if p.stick_target != null:
			target = p.stick_target
	# The stick is carried along with the body.
	var cur: Vector3 = p.stick + Vector3(p.vel.x, p.vel.y, 0.0) * dt
	var spd := STICK_SPEED * (1.7 if p.lunge > 0.0 else 1.0) * (0.5 if p.stagger > 0.0 else 1.0)
	cur += (_clamp_reach(p, target, keeper_area) - cur).limit_length(spd * dt)
	p.stick = _clear_bodies(m, p, _clamp_reach(p, cur, keeper_area), keeper_area)
	p.one_hand = p != m.carrier and Vector2(p.stick.x, p.stick.y).distance_to(p.pos) > TWO_HAND_REACH
	var out := Vector2(p.stick.x - rest.x, p.stick.y - rest.y).length()
	p.reach = clampf(maxf(out / 1.1, p.stick.z / 2.2), 0.0, 1.0)
	if p == m.carrier:
		p.reach = 0.6   # stick down on the ball


static func _clamp_reach(p, v: Vector3, keeper_area: bool) -> Vector3:
	var flat: Vector2 = Vector2(v.x, v.y) - p.pos
	var r := max_reach(p)
	if flat.length() > r:
		flat = flat.normalized() * r
	var h := clampf(v.z, 0.0, maxf(max_height(p, flat.length(), keeper_area), OVERHEAD if (p.shy_toss or p.throw_up) else 0.0))
	return Vector3(p.pos.x + flat.x, p.pos.y + flat.y, h)


## Bodies are solid to camans too: the head can't sit inside another player,
## and the shaft (from the hands, just in front of the body, to the head)
## can't pass through one. A caman that would is swung round the side of
## them, or held short, instead. Overhead (a shy) it clears everyone.
static func _clear_bodies(m, p, head: Vector3, keeper_area: bool) -> Vector3:
	if head.z > BODY_HEIGHT:
		return head
	var hands: Vector2 = p.pos + p.facing * 0.25
	var clear := BODY_R + STICK_CLEAR
	for q in m.players:
		if q == p:
			continue
		var h := Vector2(head.x, head.y)
		if q.pos.distance_squared_to(p.pos) > 16.0:
			continue
		var close: Vector2 = Geometry2D.get_closest_point_to_segment(q.pos, hands, h)
		var off: Vector2 = close - q.pos
		var d := off.length()
		if d >= clear:
			continue
		if close.distance_to(h) < 0.05:
			# The head itself is in them: push it straight out.
			var out: Vector2 = off / d if d > 0.001 else (h - p.pos).normalized()
			h = q.pos + out * clear
		else:
			# The shaft goes through them: turn the caman round their side,
			# pivoting at the hands, whichever way is nearer.
			var r := hands.distance_to(h)
			var to_q: Vector2 = q.pos - hands
			var side := signf(to_q.cross(h - hands))
			if side == 0.0:
				side = p.hand
			var need := asin(clampf(clear / maxf(to_q.length(), clear), 0.0, 1.0))
			var dir: Vector2 = to_q.normalized().rotated(side * need)
			h = hands + dir * minf(r, maxf(to_q.length() - clear, 0.3)) if to_q.length() < clear + 0.05 \
				else hands + dir.rotated(side * 0.02) * r
		head = _clamp_reach(p, Vector3(h.x, h.y, head.z), keeper_area)
	return head


## Closest the ball came to point `q` while it moved from `a` to `b` (3D).
static func path_distance(q: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	var t := 0.0 if l2 < 1e-8 else clampf((q - a).dot(ab) / l2, 0.0, 1.0)
	return q.distance_to(a + ab * t)


# ---------------------------------------------------------------- keeper

## A keeper facing a shot works out where it will cross in front of them and
## reaches for it; if it is going wide of where they stand, they dive.
static func keeper_reflex(m, k, dt: float) -> void:
	k.save_point = null
	if m.carrier != null or m.state != m.State.PLAY:
		return
	var g: Vector2 = m.own_goal(k.team)
	var toward: float = -m.attack_dir[k.team]
	var vx: float = m.ball_vel.x * toward
	if vx < 6.0 or m.ball_pos.distance_to(g) > 40.0:
		return
	var t: float = (k.pos.x - m.ball_pos.x) / m.ball_vel.x
	if t < 0.0 or t > 1.6:
		return
	var y: float = m.ball_pos.y + m.ball_vel.y * t
	var z: float = maxf(0.0, m.ball_z + m.ball_vz * t - 0.5 * m.GRAVITY * t * t)
	if absf(y - g.y) > m.GOAL_W / 2.0 + 2.5:
		return   # going well wide: let it go
	k.save_point = Vector3(k.pos.x, y, z)
	var dy: float = y - k.pos.y
	var standing := max_reach(k) - LUNGE_REACH * (1.0 if k.lunge > 0.0 else 0.0) - 0.35
	if absf(dy) > standing and k.lunge <= 0.0 and t < 0.7 and k.stagger <= 0.0:
		# Dive: a burst across the goal, faster for better keepers.
		k.lunge = 0.7
		var burst: float = 4.5 + k.r("keeping") / 100.0 * 3.5
		k.vel.y += signf(dy) * burst
		var side := signf(Vector2(0, dy).dot(right_of(k)))
		m.anim(k, "save_right" if side > 0.0 else "save_left")
