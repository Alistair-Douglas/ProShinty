extends RefCounted
## The four ways to stop an opponent's swing:
##
##  1. Swing together. Both players swing at the same ball. Whoever's caman
##     arrives first gets it; arrive within a few hundredths of a second of
##     each other and the camans clash and the ball goes anywhere. (Handled
##     where each swing lands: match.gd _contact() calls clash().)
##  2. Shove. A shoulder barge is legal. Barging someone in the back is a foul,
##     but the referee doesn't always see it. (start_barge(), barge_contact().)
##  3. Block. Turn the stick so its back is over the ball in the swing's path,
##     so their swing hits your stick. Block too late and you get hit (and
##     hurt), but it isn't a foul.
##  4. Cleek. Raise the stick under the arc of their swing so it comes down on
##     your caman and glances off: they miss, and the ball is there for you.
##     Only against hits of half power or more.
##
## Contact goes into match.events for the referee as
##   {type: "foul", kind, by, on, at, severity}
## kind "barge" (legal shoulder barge), "push" (in the back), "hack" (a poke
## through the carrier's body; from match.gd). A swing that catches a late
## blocker hurts them but is not a foul ("late_block" event). The referee
## itself calls a swing that misses the ball and hits an opponent.
## player_physics.gd also reports knock-downs from behind as "push".
## The match emits "strike", "touch" and "tackle" events alongside.
##
## Units are the match's (yards, seconds).

const Body := preload("res://scripts/player_physics.gd")

const CLASH_WINDOW := 0.05     ## swings this close together clash
const BLOCK_TIME := 0.6        ## how long a block is held
const BLOCK_SET := 0.12        ## a block needs this long to be set; later and you get hit
const BLOCK_RANGE := 0.55      ## blocker's stick head this close to the ball covers it
const CLEEK_TIME := 0.45
const CLEEK_SET := 0.08
const CLEEK_RANGE := 2.4       ## stand this close to the swinger to get under the arc
const CLEEK_MIN_POWER := 0.5   ## only hits of half power or more can be cleeked
const BARGE_TIME := 0.35
const BARGE_BURST := 3.5       ## yd/s thrown into a barge
const BARGE_BRACE := 1.35      ## a braced shoulder hits harder
const FLOOR_PACE := 0.9         ## a sprinting barger at this share of top speed floors a slower player
const FLOOR_SLOWER := 0.75      ## ...who is moving at under this share of the barger's speed
const FLOOR_TIME := 1.3         ## seconds a floored player is out of play (full fall)
const FLOOR_SHOVE := 4.0        ## yd/s the floored player is sent the way of the barge
const REF_SEES := 0.55         ## chance the referee spots a push in the back


static func tick(p, dt: float) -> void:
	p.block_t = maxf(0.0, p.block_t - dt)
	p.cleek_t = maxf(0.0, p.cleek_t - dt)
	p.barge_t = maxf(0.0, p.barge_t - dt)
	p.counter_age += dt


static func start_block(m, p) -> void:
	if p.block_t > 0.0 or p.cleek_t > 0.0 or p.stagger > 0.0 or p.swing_t >= 0.0:
		return
	p.block_t = BLOCK_TIME
	p.counter_age = 0.0
	m.anim(p, "block")


static func start_cleek(m, p) -> void:
	if p.block_t > 0.0 or p.cleek_t > 0.0 or p.stagger > 0.0 or p.swing_t >= 0.0:
		return
	p.cleek_t = CLEEK_TIME
	p.counter_age = 0.0
	m.anim(p, "cleek")


## Throw a shoulder into the nearest opponent within reach.
static func start_barge(m, p) -> bool:
	if p.barge_t > 0.0 or p.stagger > 0.0 or p.cooldown > 0.0:
		return false
	var best = null
	var best_d := 2.3
	for o in m.squads[1 - p.team]:
		var d: float = o.pos.distance_to(p.pos)
		if d < best_d:
			best_d = d
			best = o
	if best == null:
		return false
	var dir: Vector2 = (best.pos - p.pos).normalized()
	p.barge_t = BARGE_TIME
	p.barge_hit = false
	p.cooldown = 0.6
	p.vel += dir * BARGE_BURST
	p.facing = dir
	m.anim(p, "barge")
	return true


## Called by the body collision when a barging player meets an opponent.
## Returns the extra force factor for the impulse. A push in the back is a
## foul if the referee sees it.
static func barge_contact(m, barger, victim) -> float:
	if barger.barge_t <= 0.0 or barger.barge_hit:
		return 1.0
	barger.barge_hit = true
	var push: Vector2 = (victim.pos - barger.pos).normalized()
	var in_the_back: bool = victim.facing.dot(push) > 0.5
	m.events.append({"type": "barge", "team": barger.team, "in_the_back": in_the_back})
	# For the referee: a shoulder barge is legal ("barge"), a push in the back
	# is a foul ("push"). Without a referee in the match, judge it here.
	m.events.append({"type": "foul", "kind": "push" if in_the_back else "barge", "by": barger,
		"on": victim, "at": victim.pos, "severity": 0.4 if in_the_back else 0.0})
	if in_the_back and not ("referee" in m) and randf() < REF_SEES:
		m.foul_pending = [barger, victim]
	if floors(barger, victim):
		_floor(m, barger, victim, push)
	return BARGE_BRACE


## A barger at full pace into a slower player who isn't holding the ball up
## or barging back puts them on the ground.
static func floors(barger, victim) -> bool:
	var pace: float = barger.vel.length()
	return barger.sprinting and pace >= barger.top_speed() * FLOOR_PACE \
		and victim.vel.length() < pace * FLOOR_SLOWER \
		and not victim.shielding and victim.barge_t <= 0.0


## Sent flying the way of the barge and down on the grass, then back up.
static func _floor(m, barger, victim, push: Vector2) -> void:
	victim.vel += push * FLOOR_SHOVE
	victim.stagger = maxf(victim.stagger, FLOOR_TIME)
	victim.swing_t = -1.0
	victim.block_t = 0.0
	victim.cleek_t = 0.0
	m.anim(victim, "stumble", 1.0)
	m.events.append({"type": "knockdown", "team": victim.team, "on": victim, "floored": true})
	if victim == m.carrier:
		m.spill(victim, barger)


## Just before `p`'s caman meets the ball: does an opponent's block or cleek
## get in the way, or does their own swing clash with it? Returns true if the
## swing is dealt with here (and _contact should stop).
static func intercept(m, p) -> bool:
	var ball := Vector2(m.ball_pos.x, m.ball_pos.y)
	for q in m.squads[1 - p.team]:
		if q.stagger > 0.0:
			continue
		# Cleek: stick up under the arc, so the swing glances off it.
		if q.cleek_t > 0.0 and q.counter_age >= CLEEK_SET and q.pos.distance_to(p.pos) < CLEEK_RANGE \
				and cleekable(p):
			var chance: float = clampf(0.4 + (q.r("tackling") - p.r("control")) / 100.0 * 0.6, 0.15, 0.75)
			q.cleek_t = 0.0
			if randf() < chance:
				_cleeked(m, p, q)
				return true
		# Block: the back of the stick over the ball, in the swing's path.
		if q.block_t > 0.0 and Vector2(q.stick.x, q.stick.y).distance_to(ball) < BLOCK_RANGE:
			q.block_t = 0.0
			if q.counter_age < BLOCK_SET:
				# Too late: the swing catches the blocker. Not a foul (they put
				# themselves there), but it hurts: the harder the swing, the
				# longer they're off balance, and a big one puts them down.
				var share: float = p.swing_req.get("share", 0.5)
				q.stagger = clampf(0.5 + share * 0.8, 0.5, 1.3)
				q.swing_t = -1.0
				m.anim(q, "stumble")
				m.events.append({"type": "late_block", "team": q.team, "on": q})
				if p == m.human or q == m.human:
					m._say("Late block! %s is hurt" % q.data.get("name", "The blocker"), 1.2)
				if randf() < 0.4:
					return false   # and the ball still gets through
			_blocked(m, p, q)
			return true
	return false


## Cleeks only work against hits of half power or more.
static func cleekable(s) -> bool:
	return s.swing_req.get("share", 0.0) >= CLEEK_MIN_POWER


## Two swings arriving together: the camans clash and the ball goes anywhere.
static func clash(m, p, q) -> void:
	p.swing_t = -1.0
	q.swing_t = -1.0
	p.touch_block = 0.25
	q.touch_block = 0.25
	m.carrier = null
	m.ball_vel = Vector2.from_angle(randf() * TAU) * randf_range(6.0, 18.0)
	m.ball_vz = randf_range(0.0, 4.0)
	m.ball_sim.set_spin(Vector3.ZERO)
	m.last_team = -1 if randf() < 0.5 else q.team
	m.events.append({"type": "clash", "team": p.team})
	if p == m.human or q == m.human:
		m._say("Camans clash!", 1.0)


static func _cleeked(m, p, q) -> void:
	p.swing_t = -1.0
	p.touch_block = 0.4
	q.touch_block = 0.0
	if m.carrier == p:
		m.carrier = null
		m.ball_vel = p.vel * 0.3
		m.ball_vz = 0.0
	if randf() < 0.3:
		m.anim(p, "stumble")
	m.events.append({"type": "cleek", "team": q.team})
	if p == m.human or q == m.human:
		m._say("Cleeked!", 1.0)


static func _blocked(m, p, q) -> void:
	p.swing_t = -1.0
	p.touch_block = 0.3
	if m.carrier == p:
		m.carrier = null
	# The swing smacks into the stick: the ball squirts a short way.
	m.ball_vel = Vector2.from_angle(randf() * TAU) * randf_range(0.5, 3.0)
	m.ball_vz = 0.0
	m.last_team = q.team
	m.events.append({"type": "stick_block", "team": q.team})
	if p == m.human or q == m.human:
		m._say("Blocked!", 1.0)


## Computer players: an opponent near the ball is winding up. Pick a counter
## the way a real player would, from how close they are and how long until
## the swing lands. Returns true if they did something.
static func ai_counter(m, p) -> bool:
	var s = m.carrier
	if s == null or s.team == p.team or s.swing_t < 0.0:
		return false
	if p.block_t > 0.0 or p.cleek_t > 0.0 or p.swing_t >= 0.0 or p.stagger > 0.0:
		return false
	# Each swing is read once: react to it or don't.
	if p.read_swing == s.anim_seq:
		return false
	p.read_swing = s.anim_seq
	var d_body: float = p.pos.distance_to(s.pos)
	var d_ball: float = p.pos.distance_to(m.ball_pos)
	var skill: float = p.r("tackling") / 100.0
	# Reading the swing takes a moment; better tacklers read it sooner.
	if randf() > 0.25 + 0.5 * skill:
		return false
	var left: float = s.swing_t
	var my_swing := ShintyPlayerModel.contact_delay("pass", 0.5)
	if d_body < CLEEK_RANGE - 0.3 and left > CLEEK_SET + 0.05 and cleekable(s) and randf() < 0.3:
		start_cleek(m, p)
	elif d_ball < Body.TWO_HAND_REACH and left > BLOCK_SET and randf() < 0.6:
		start_block(m, p)
	elif d_ball < Body.max_reach(p) and left > my_swing - 0.03:
		# Swing with them: a pass-length swing lands quickly.
		var dir: Vector2 = (m.target_goal(p.team) - p.pos).normalized()
		m._strike_speed(p, dir, 20.0, 1.0, "passing")
	elif d_body < 2.0:
		start_barge(m, p)
	else:
		return false
	return true
