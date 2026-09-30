extends RefCounted
## Off-ball decisions for computer-controlled players: where to stand and when
## to run. The match calls begin_team() once per team each frame and then
## off_ball() for every outfield player who isn't on the ball, chasing it or
## under human control. This only sets p.desired (through the match's steering
## helpers); movement, collisions and the ball stay in match.gd.
##
## In possession players take one of these jobs, re-thought every half second
## or so, and a run is carried through before they think again:
##   support  - offer a short, open passing angle near the ball carrier
##   run      - sprint in behind the defence, into the gap between defenders
##   overlap  - a wide player bursts past the carrier down the touchline
##   check    - a forward drops short towards the ball to receive it
##   hold     - keep width and shape, pushed up with the play
## The team plays a 4-3-4. Out of possession one or two press the ball (the
## match picks them), a midfielder covers behind, and the backs stay
## goal-side of the forwards they mark, so the back four take whatever shape,
## diamond or square, the other side's forwards stand in. The other
## midfielders hold a zonal shape that shifts with the ball, picking up
## runners from deep.
## Forwards: shinty is man-marking, forward against back, so forwards hold
## their positions up the park whoever has the ball. They don't track back,
## support short or go wide on overlaps; the one thing they do is drop short
## to take a pass, then go back out to their spot.
## Loose balls: the side whose nearest player will get there first starts
## shaping up to attack, the other side drops into its defensive shape.

enum Job { HOLD, SUPPORT, RUN, OVERLAP, CHECK, COVER, MARK }

const MAX_RUNNERS := 2        # forward runs at once, per team
const SUPPORTERS := 2         # short options near the carrier
const MARK_REFRESH := 0.4     # seconds between marking reassignments
const MAX_MARKERS := 2        # midfielders picking up runners from deep; the rest is zonal
const MAX_CHECKS := 1         # forwards dropping short at once, per team


class Plan:
	var job := 0
	var target := Vector2.ZERO
	var sprint := false
	var timer := 0.0          # time left on this plan before re-thinking
	var run_cooldown := 0.0   # rest between forward runs


var m                          # the match node (match.gd)
var plans := {}                # Player -> Plan
var marks := [{}, {}]          # per team: our Player -> opponent Player
var mark_timer := [0.0, 0.0]
var attacking := [false, false]
var focus := [Vector2.ZERO, Vector2.ZERO]   # where the ball is (or will be) won
var focus_player := [null, null]            # who has it, or will get it
var supporters := [[], []]
var cover := [null, null]
var preset := {}               # Player -> where they stand for the current restart
var preset_for := []           # [taker, kind, spot] the presets were worked out for


func _init(match_node) -> void:
	m = match_node


func _plan(p) -> Plan:
	if not plans.has(p):
		var pl := Plan.new()
		pl.timer = randf() * 0.5
		plans[p] = pl
	return plans[p]


## Work out the team's situation for this frame. chasers are the players the
## match has already sent after the ball.
func begin_team(t: int, dt: float, chasers: Array) -> void:
	for p in m.squads[t]:
		var pl := _plan(p)
		pl.timer -= dt
		pl.run_cooldown = max(0.0, pl.run_cooldown - dt)
	var c = m.carrier
	if c != null:
		attacking[t] = c.team == t
		focus[t] = c.pos
		focus_player[t] = c
	else:
		# Loose ball: whoever gets there first decides who is attacking.
		var pt: Vector2 = m._ball_intercept_point()
		var ours := _nearest_time(t, pt)
		var theirs := _nearest_time(1 - t, pt)
		attacking[t] = ours[1] + 0.25 < theirs[1]
		focus[t] = pt
		focus_player[t] = ours[0] if attacking[t] else theirs[0]
	supporters[t] = []
	cover[t] = null
	if attacking[t]:
		_pick_supporters(t, chasers)
	else:
		_pick_cover(t, chasers)
		mark_timer[t] -= dt
		if mark_timer[t] <= 0.0:
			mark_timer[t] = MARK_REFRESH
			_assign_marks(t, chasers)
	# Winning or losing the ball means everyone thinks again straight away.
	for p in m.squads[t]:
		var pl: Plan = plans[p]
		var att_job: bool = pl.job in [Job.SUPPORT, Job.RUN, Job.OVERLAP, Job.CHECK]
		var def_job: bool = pl.job in [Job.COVER, Job.MARK]
		if (attacking[t] and def_job) or (not attacking[t] and att_job):
			pl.timer = min(pl.timer, m._reaction(t) * 0.5)
			pl.job = Job.HOLD


func off_ball(p, dt: float) -> void:
	var pl := _plan(p)
	var t: int = p.team
	var spot = _restart_spot(p)
	if spot != null:
		m._steer_to(p, spot, p.pos.distance_to(spot) > 5.0 and p.stamina > 0.15)
		return
	if attacking[t]:
		if pl.timer <= 0.0 or _run_finished(p, pl):
			_think_attack(p, pl)
		_follow_attack(p, pl)
	else:
		_defend(p, pl)
	var tgt := _legal(t, pl.target)
	m._steer_to(p, tgt, pl.sprint and p.stamina > 0.15)


# ---------------------------------------------------------------- attacking

func _think_attack(p, pl: Plan) -> void:
	var t: int = p.team
	pl.timer = 0.5 + randf() * 0.5 + (0.3 if m.human_side >= 0 and t != m.human_side and m.difficulty == 0 else 0.0)
	pl.sprint = false
	var holder = focus_player[t]
	var ball: Vector2 = focus[t]
	var ball_frac: float = m.own_frac(t, ball.x)
	var my_frac: float = m.own_frac(t, p.pos.x)
	var ahead: float = (p.pos.x - ball.x) * m.attack_dir[t]

	if p in supporters[t]:
		pl.job = Job.SUPPORT
		pl.target = _support_spot(p, ball)
		return

	# Forwards: drop short to receive when a team-mate has it within passing
	# range, otherwise stay in position (or, now and again, run in behind).
	var dist_ball: float = p.pos.distance_to(ball)
	if p.role == "FWD" and holder != null and holder.team == t and holder != p \
			and dist_ball > 12.0 and dist_ball < 45.0 and ahead > 4.0 \
			and pl.run_cooldown <= 0.0 and _count_jobs(t, Job.CHECK) < MAX_CHECKS and randf() < 0.45:
		pl.job = Job.CHECK
		var to_ball: Vector2 = (ball - p.pos).normalized()
		var side := Vector2(-to_ball.y, to_ball.x) * (1.0 if randf() < 0.5 else -1.0)
		pl.target = p.pos + to_ball * randf_range(6.0, 9.0) + side * 2.5
		pl.sprint = true
		pl.timer = 1.2 + randf() * 0.4
		pl.run_cooldown = pl.timer + 2.0   # then back out to their spot
		return

	# Forward runs: forwards and midfielders level with or ahead of the ball,
	# once the team is out of its own quarter. Quicker players go more often.
	var runners := _count_jobs(t, Job.RUN) + _count_jobs(t, Job.OVERLAP)
	var eager: float = 0.25 + p.r("pace") / 100.0 * 0.35
	if p.role == "MID":
		eager += 0.15
	elif p.role == "FWD":
		eager *= 0.5   # mostly they hold their spot
	if p.role != "DEF" and runners < MAX_RUNNERS and pl.run_cooldown <= 0.0 \
			and ball_frac > 0.25 and ahead > -8.0 and my_frac < 0.9 and randf() < eager:
		pl.job = Job.RUN
		pl.target = _run_spot(p, ball)
		pl.sprint = true
		pl.timer = 1.8 + randf() * 1.4
		pl.run_cooldown = pl.timer + 2.5
		return

	# Overlap: a wide player behind the ball on the same flank goes round it.
	var wide: bool = p.position_code in ["LM", "RM"]
	var same_side: bool = sign(p.pos.y - m.PITCH.y / 2.0) == sign(ball.y - m.PITCH.y / 2.0)
	if wide and same_side and holder != null and ahead < -2.0 and ahead > -22.0 \
			and runners < MAX_RUNNERS and pl.run_cooldown <= 0.0 and ball_frac > 0.3 \
			and randf() < 0.5:
		var touch_y: float = 7.0 if ball.y < m.PITCH.y / 2.0 else m.PITCH.y - 7.0
		pl.job = Job.OVERLAP
		pl.target = Vector2(ball.x + m.attack_dir[t] * (14.0 + randf() * 6.0), lerp(ball.y, touch_y, 0.75))
		pl.sprint = true
		pl.timer = 2.0 + randf()
		pl.run_cooldown = pl.timer + 3.0
		return

	pl.job = Job.HOLD
	pl.target = _hold_spot(p)


func _follow_attack(p, pl: Plan) -> void:
	# Supporters keep adjusting as the carrier moves; runs keep their line.
	var t: int = p.team
	if pl.job == Job.SUPPORT and pl.timer > 0.0 and p.pos.distance_to(pl.target) < 2.0:
		var ball: Vector2 = focus[t]
		if pl.target.distance_to(ball) > 18.0 or pl.target.distance_to(ball) < 6.0:
			pl.target = _support_spot(p, ball)
	elif pl.job == Job.HOLD:
		pl.target = _hold_spot(p)


func _run_finished(p, pl: Plan) -> bool:
	return pl.job in [Job.RUN, Job.OVERLAP, Job.CHECK] and p.pos.distance_to(pl.target) < 1.5


## The best spot 8-16 yards from the ball with a clear lane and some space,
## not too close to another team-mate.
func _support_spot(p, ball: Vector2) -> Vector2:
	var t: int = p.team
	var fwd := Vector2(m.attack_dir[t], 0)
	var best: Vector2 = p.pos
	var best_s := -INF
	for i in 10:
		var ang := deg_to_rad(-100.0 + 200.0 * i / 9.0) + randf_range(-0.1, 0.1)
		var spot: Vector2 = ball + fwd.rotated(ang) * randf_range(8.0, 16.0)
		spot = _in_pitch(spot)
		var lane: float = min(m._lane_clearance(t, ball, spot), 5.0)
		var space: float = min(_space_at(1 - t, spot), 8.0)
		var mates := _space_at(t, spot, p)
		var s: float = lane * 2.0 + space * 1.2 + (spot.x - ball.x) * m.attack_dir[t] * 0.25 \
			- p.pos.distance_to(spot) * 0.25 - max(0.0, 6.0 - mates) * 1.5 \
			- max(0.0, 14.0 - _edge_dist(spot)) * 0.6
		if s > best_s:
			best_s = s
			best = spot
	return best


## Into the gap in or behind the defensive line, angled towards goal.
func _run_spot(p, ball: Vector2) -> Vector2:
	var t: int = p.team
	var dir: int = m.attack_dir[t]
	var line_x := _defensive_line_x(t)
	var depth: float = randf_range(4.0, 12.0)
	var run_x: float = line_x + dir * depth
	# Never a run backwards, and not miles ahead of the ball either.
	if (run_x - p.pos.x) * dir < 6.0:
		run_x = p.pos.x + dir * randf_range(8.0, 14.0)
	if (run_x - ball.x) * dir > 45.0:
		run_x = ball.x + dir * 45.0
	var goal_y: float = m.PITCH.y / 2.0
	var best_y: float = p.pos.y
	var best_s := -INF
	var from_y: float = p.pos.y
	if p.role == "FWD":
		from_y = m.home_world(p).y   # a forward's run stays in their own channel
		goal_y = lerp(from_y, goal_y, 0.4)
	for i in 7:
		var y: float = lerp(from_y, goal_y, i / 6.0) + randf_range(-4.0, 4.0)
		var spot := _in_pitch(Vector2(run_x, y))
		var s: float = min(_space_at(1 - t, spot), 10.0) * 1.5 + min(_space_at(t, spot, p), 8.0) \
			- abs(y - goal_y) * 0.08 + min(m._lane_clearance(t, ball, spot), 5.0)
		if s > best_s:
			best_s = s
			best_y = y
	return _in_pitch(Vector2(run_x, best_y))


## Formation spot, pushed further up when we have the ball so forwards stretch
## the defence, and kept wide. Backs stay goal-side of their forward, a bit
## looser than when defending.
func _hold_spot(p) -> Vector2:
	var t: int = p.team
	if p.role == "DEF" and p.man != null:
		return _mark_spot(p, p.man, 6.0)
	var h: Vector2 = m.home_world(p)
	var push := 0.0
	match p.role:
		"FWD": push = 8.0
		"MID": push = 5.0
		"DEF": push = 3.0
	h.x += m.attack_dir[t] * push
	# Forwards don't go much beyond the defensive line while holding.
	if p.role == "FWD":
		var line_x := _defensive_line_x(t)
		if (h.x - line_x) * m.attack_dir[t] > 3.0:
			h.x = line_x + m.attack_dir[t] * 3.0
	if p.position_code in ["LHF", "RHF"]:
		h.y = lerp(h.y, 6.0 if p.home.y < 0.5 else m.PITCH.y - 6.0, 0.3)
	return _in_pitch(h)


func _pick_supporters(t: int, chasers: Array) -> void:
	var ball: Vector2 = focus[t]
	var ranked := []
	for p in m.squads[t]:
		if p.is_keeper() or p == focus_player[t] or p == m.human or p in chasers or p.role == "FWD":
			continue
		if p.role == "DEF" and m.own_frac(t, ball.x) > 0.3:
			continue   # the backs stay with their forwards

		var pl: Plan = plans[p]
		if pl.job in [Job.RUN, Job.OVERLAP] and pl.timer > 0.0:
			continue
		ranked.append(p)
	ranked.sort_custom(func(a, b): return a.pos.distance_squared_to(ball) < b.pos.distance_squared_to(ball))
	supporters[t] = ranked.slice(0, SUPPORTERS)


# ---------------------------------------------------------------- defending

func _defend(p, pl: Plan) -> void:
	var t: int = p.team
	var goal: Vector2 = m.own_goal(t)
	var ball: Vector2 = focus[t]
	pl.sprint = false
	if p == cover[t]:
		# Sit between the ball and our goal, a few yards behind the presser.
		pl.job = Job.COVER
		pl.target = ball + (goal - ball).normalized() * 7.0
		pl.sprint = p.pos.distance_to(pl.target) > 6.0
		return
	if p.role == "DEF" and p.man != null:
		# Man-marking: goal-side of their forward, tighter the nearer the
		# ball, so the back four take the shape the forwards stand in.
		var man = p.man
		var near: float = clamp(1.0 - man.pos.distance_to(ball) / 35.0, 0.0, 1.0)
		pl.job = Job.MARK
		pl.target = _mark_spot(p, man, lerp(4.5, 2.0, near))
		pl.sprint = p.pos.distance_to(pl.target) > 4.0 or man.vel.length() > 6.0
		return
	var o = marks[t].get(p)
	if o != null:
		pl.job = Job.MARK
		# Goal-side of the opponent, tighter the closer they are to the ball,
		# and leaning into the passing lane.
		var near: float = clamp(1.0 - o.pos.distance_to(ball) / 40.0, 0.0, 1.0)
		var gap: float = lerp(4.5, 2.2, near)
		var spot: Vector2 = o.pos + (goal - o.pos).normalized() * gap
		spot = spot.lerp(o.pos.lerp(ball, 0.3), (1.0 - near) * 0.35)
		# Track runners: aim where they are going, not where they are.
		spot += o.vel * 0.2
		pl.target = spot
		pl.sprint = p.pos.distance_to(spot) > 4.0 or o.vel.length() > 6.0
		return
	pl.job = Job.HOLD
	pl.target = _shape_spot(p)
	pl.sprint = p.pos.distance_to(pl.target) > 12.0
	if p.role == "FWD":
		pl.sprint = p.pos.distance_to(pl.target) > 6.0   # get back out to your spot


## Goal-side of `man`, `gap` yards back towards our goal and leaning a little
## towards the ball. A back follows a forward who drops deep only so far.
func _mark_spot(p, man, gap: float) -> Vector2:
	var t: int = p.team
	var goal: Vector2 = m.own_goal(t)
	var ball: Vector2 = focus[t]
	var spot: Vector2 = man.pos + (goal - man.pos).normalized() * gap + man.vel * 0.2
	spot = spot.lerp(spot.lerp(ball, 0.25), clamp(1.0 - man.pos.distance_to(ball) / 40.0, 0.0, 1.0) * 0.4)
	if m.own_frac(t, spot.x) > 0.55:
		spot.x = m.frac_to_world(t, Vector2(0.55, 0.0)).x
	return _in_pitch(spot)


## Formation spot squeezed towards the ball and pulled back towards our goal.
func _shape_spot(p) -> Vector2:
	var t: int = p.team
	var h: Vector2 = m.home_world(p)
	var ball: Vector2 = focus[t]
	if p.role == "FWD":
		return _in_pitch(h)   # forwards stay up the park on their man
	h.y = lerp(h.y, ball.y, 0.15)
	h.x -= m.attack_dir[t] * (4.0 if p.role != "DEF" else 2.0)
	return _in_pitch(h)


func _pick_cover(t: int, chasers: Array) -> void:
	var ball: Vector2 = focus[t]
	var best = null
	var best_d := INF
	for p in m.squads[t]:
		if p.is_keeper() or p == m.human or p in chasers or p.role != "MID":
			continue   # the backs are on their men, the forwards up the park
		var d: float = p.pos.distance_to(ball)
		if d < best_d:
			best_d = d
			best = p
	cover[t] = best


## Most dangerous opponents first (nearest our goal, then nearest the ball),
## each picked up by the closest free defender or midfielder.
func _assign_marks(t: int, chasers: Array) -> void:
	var goal: Vector2 = m.own_goal(t)
	var ball: Vector2 = focus[t]
	var free := []
	for p in m.squads[t]:
		if p.is_keeper() or p == m.human or p in chasers or p == cover[t]:
			continue
		if p.role != "MID":
			continue   # forwards stay up the park; the backs have their men
		if p.role == "MID" and m.own_frac(t, ball.x) > 0.6:
			continue   # midfielders hold their zone while the ball is up the park
		free.append(p)
	var threats := []
	for o in m.squads[1 - t]:
		if o.is_keeper() or o == focus_player[t] or o.role == "FWD":
			continue   # the backs have the forwards
		if m.own_frac(t, o.pos.x) > 0.5:
			continue   # too far up the pitch to worry about
		threats.append(o)
	threats.sort_custom(func(a, b):
		return a.pos.distance_to(goal) + a.pos.distance_to(ball) * 0.4 < b.pos.distance_to(goal) + b.pos.distance_to(ball) * 0.4)
	var old: Dictionary = marks[t]
	var out := {}
	for o in threats.slice(0, MAX_MARKERS):
		if free.is_empty():
			break
		var pick = null
		var pick_d := INF
		for p in free:
			var d: float = p.pos.distance_to(o.pos)
			if old.get(p) == o:
				d -= 4.0   # stick with your man rather than swapping constantly
			if d < pick_d:
				pick_d = d
				pick = p
		if pick_d > 30.0:
			continue
		out[pick] = o
		free.erase(pick)
	marks[t] = out


# ---------------------------------------------------------------- restarts

## Where p stands while a hit-out, corner or shy is taken, or null in open
## play. The spots are worked out once per restart, so everyone walks to a
## set position and waits there, like a real team setting up.
func _restart_spot(p):
	var taker = m.set_piece_taker_now()
	var kind: String = m.set_piece
	if taker == null:
		taker = m.shy_taker()
		kind = "Shy"
	if taker == null or kind == "Free hit":
		return null   # a free hit: everyone else plays on and can make runs
	if preset_for.size() != 3 or preset_for[0] != taker or preset_for[1] != kind \
			or preset_for[2].distance_to(m.ball_pos) > 3.0:
		_build_presets(taker, kind)
	return preset.get(p)


func _build_presets(taker, kind: String) -> void:
	preset = {}
	preset_for = [taker, kind, m.ball_pos]
	var spot: Vector2 = m.ball_pos
	var t: int = taker.team
	var taken := []   # short options the taking side offers
	if kind == "Shy":
		# Two short options: one down the line, one infield. The rest of the
		# team takes its shape round the shy.
		var inward: float = 1.0 if spot.y < m.PITCH.y / 2.0 else -1.0
		var line := Vector2(spot.x + m.attack_dir[t] * 10.0, spot.y + inward * 5.0)
		var infield := Vector2(spot.x + m.attack_dir[t] * 2.0, spot.y + inward * 13.0)
		for want in [line, infield]:
			var best = null
			for q in m.squads[t]:
				if q.is_keeper() or q == taker or q == m.human or preset.has(q) or q.role == "FWD":
					continue
				if best == null or q.pos.distance_to(want) < best.pos.distance_to(want):
					best = q
			if best != null:
				preset[best] = _in_pitch(want)
				taken.append(want)
	for q in m.players:
		if q.is_keeper() or q == taker or q == m.human or preset.has(q):
			continue
		var s = null
		if kind == "Corner":
			s = _corner_spot(q)
		elif kind == "Penalty hit":
			# Everyone but the taker and the keeper stands back behind the ball.
			s = q.pos
			var dir: int = m.attack_dir[t]
			if (s.x - spot.x) * dir > -m.FREE_HIT_BACK:
				s.x = spot.x - dir * (m.FREE_HIT_BACK + 2.0)
		if s == null:
			s = m.home_at(q, spot)
			if kind == "Hit-out" and q.team == t and q.position_code in ["LHB", "RHB", "LM", "RM", "LHF", "RHF"]:
				# Width to give the taker somewhere to hit it.
				s.y = lerp(s.y, 6.0 if q.home.y < 0.5 else m.PITCH.y - 6.0, 0.4)
		preset[q] = s
	# The other side picks up the short options goal-side.
	for want in taken:
		var best = null
		for q in m.squads[1 - t]:
			if q.is_keeper() or q == m.human or q.role == "FWD":
				continue
			if best == null or preset[q].distance_to(want) < preset[best].distance_to(want):
				best = q
		if best != null:
			preset[best] = want + (m.own_goal(1 - t) - want).normalized() * 2.5
	for q in preset:
		var s: Vector2 = _in_pitch(preset[q])
		if q.team != t and s.distance_to(spot) < m.FREE_HIT_BACK + 1.0:
			s = spot + (s - spot).normalized() * (m.FREE_HIT_BACK + 1.0) if s.distance_to(spot) > 0.1 else spot + Vector2(-m.attack_dir[t] * 6.0, 0)
		preset[q] = _legal(q.team, s)


# ---------------------------------------------------------------- corners

## At a corner the attackers crowd the edge of the D (they can't be in it
## before the ball) and the defenders fill it, goal-side. Returns null for
## anyone who just keeps their shape.
func _corner_spot(p):
	var taker = m.set_piece_taker
	var att: bool = p.team == taker.team
	var goal: Vector2 = m.target_goal(taker.team)
	var into := Vector2(-m.attack_dir[taker.team], 0)
	var group := []
	for q in m.squads[p.team]:
		if q.is_keeper() or q == taker:
			continue
		if (att and q.role != "DEF") or (not att and q.role != "FWD"):
			group.append(q)
	var i := group.find(p)
	if i < 0:
		return null
	var k: float = (i + 0.5) / group.size()
	var ang := lerpf(-1.2, 1.2, k)
	var r: float = m.D_RADIUS + 1.5 if att else lerpf(3.0, m.D_RADIUS - 1.5, fmod(k * 3.0, 1.0))
	return goal + into.rotated(ang) * r


# ---------------------------------------------------------------- helpers

## [player, seconds] for whoever on team t reaches pt first.
func _nearest_time(t: int, pt: Vector2) -> Array:
	var best = null
	var best_t := INF
	for p in m.squads[t]:
		if p.is_keeper():
			continue
		var s: float = p.pos.distance_to(pt) / p.top_speed()
		if s < best_t:
			best_t = s
			best = p
	return [best, best_t]


## x of the deepest outfield opponent, the line our runners aim to beat.
func _defensive_line_x(t: int) -> float:
	var dir: int = m.attack_dir[t]
	var deepest: float = m.PITCH.x / 2.0
	var found := false
	for o in m.squads[1 - t]:
		if o.is_keeper():
			continue
		if not found or o.pos.x * dir > deepest * dir:
			deepest = o.pos.x
			found = true
	return deepest


## Distance from spot to the nearest player of team t (optionally skipping one).
func _space_at(t: int, spot: Vector2, skip = null) -> float:
	var best := 99.0
	for q in m.squads[t]:
		if q == skip:
			continue
		best = min(best, q.pos.distance_to(spot))
	return best


## Yards from spot to the nearer sideline.
func _edge_dist(spot: Vector2) -> float:
	return min(spot.y, m.PITCH.y - spot.y)


func _count_jobs(t: int, job: int) -> int:
	var n := 0
	for p in m.squads[t]:
		var pl: Plan = plans.get(p)
		if pl != null and pl.job == job and pl.timer > 0.0:
			n += 1
	return n


## Keep targets on the park, a few yards in so passes to them stay in play.
func _in_pitch(v: Vector2) -> Vector2:
	return Vector2(clamp(v.x, 4.0, m.PITCH.x - 4.0), clamp(v.y, 6.0, m.PITCH.y - 6.0))


## Shinty's area rule: no attacker in the opposition D before the ball gets
## there, so runs stop at its edge until the ball is in.
func _legal(t: int, v: Vector2) -> Vector2:
	var g: Vector2 = m.target_goal(t)
	var r: float = m.D_RADIUS + 0.8
	if m.ball_pos.distance_to(g) > m.D_RADIUS and v.distance_to(g) < r:
		var off := v - g
		if off.length() < 0.01:
			off = Vector2(-m.attack_dir[t], 0)
		v = g + off.normalized() * r
	return v
