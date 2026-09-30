extends RefCounted
## Substitutions: each side's bench, the changes it has left, players tiring
## over the match, knocks that injure, the computer's own changes, and the
## players jogging off and on. The match creates it in _setup() and calls
## step() every frame; the pause menu (scripts/subs_menu.gd) asks for changes
## through request().
##
## Rules (docs/rules.md): each side names its bench (everyone in teams.json
## after the starting twelve), makes at most MAX_SUBS changes, and a player
## who comes off can't go back on. A sent-off player isn't replaced. A change
## asked for in open play waits for the ball to go dead (a goal, half time,
## or a restart such as a shy, hit-out, corner or free hit); the new player
## comes on from the dugout and the other walks off to it.

const TeamData := preload("res://scripts/team_data.gd")
const Body := preload("res://scripts/player_physics.gd")

const MAX_SUBS := 3
## A player's legs over a whole match with a middling stamina rating: they
## fall this far by full time (more for low stamina, and faster sprinting).
const LEGS_DRAIN := 0.3
const HALF_TIME_REST := 0.08
## The computer brings a tired player off once their legs are below this,
## but not before this share of the match has gone.
const TIRED := 0.8
const TIRED_FROM := 0.55
const LAST_SUB_FROM := 0.75   # the last change is kept for an injury until then
const WALK_OFF := 4.0          # yd/s, walking to the bench
## The dugouts: this far either side of halfway and back from the far
## touchline, in yards (scripts/subs_bench.gd draws them there).
const DUGOUT_X := 9.84
const DUGOUT_BACK := 5.47

var m                            # the match (match.gd)
var bench := [[], []]            # player dictionaries still available
var used := [0, 0]
var pending := [[], []]          # [{off: Player, on: Dictionary}] waiting for a dead ball
var came_off := [[], []]         # dictionaries of players substituted off
var legs := {}                   # Player -> 0..1, caps their stamina
var injured := {}                # Player -> 0..1 how bad
var leaving: Array = []          # Players walking off to the bench (drawn, not playing)
var made: Array = []             # {team, off, on, minute} for the TV graphic
var auto := [false, false]       # the computer makes the changes for this side
var menu_open := false
var _menu_closed_ms := -100000
var _think := 0.0
var _last_half := 1


func setup(match_node) -> void:
	m = match_node
	for t in 2:
		var starters: Array = TeamData.starting_twelve(m.teams[t])
		for pd in m.teams[t]["players"]:
			if not pd in starters:
				bench[t].append(pd)
		auto[t] = t != m.human_side
	for p in m.players:
		legs[p] = 1.0


## Changes the side can still make, counting ones already waiting.
func subs_left(t: int) -> int:
	return MAX_SUBS - used[t] - pending[t].size()


## Ask to bring `on` (a bench player dictionary) on for `off`. Returns an
## empty string if it's queued, else why not.
func request(off, on: Dictionary) -> String:
	var t: int = off.team
	if not off in m.squads[t]:
		return "%s isn't on the pitch" % off.data.get("name", "")
	if not on in bench[t]:
		return "%s isn't on the bench" % on.get("name", "")
	if pending_for(off) != null:
		return "%s is already coming off" % off.data.get("name", "")
	if pending[t].any(func(r): return r["on"] == on):
		return "%s is already going on" % on.get("name", "")
	if subs_left(t) <= 0:
		return "No substitutions left"
	pending[t].append({"off": off, "on": on})
	return ""


func cancel(off) -> void:
	var r = pending_for(off)
	if r != null:
		pending[off.team].erase(r)


func pending_for(off):
	for r in pending[off.team]:
		if r["off"] == off:
			return r
	return null


## True while the subs screen is up, or just after it closed (so the button
## that closed it doesn't also unpause the match).
func menu_busy() -> bool:
	return menu_open or Time.get_ticks_msec() - _menu_closed_ms < 250


func set_menu_open(open: bool) -> void:
	if menu_open and not open:
		_menu_closed_ms = Time.get_ticks_msec()
	menu_open = open


## Share of the match played, 0 at the first throw-up to 1 at full time.
func match_share() -> float:
	return clampf(m.match_seconds() / (90.0 * 60.0), 0.0, 1.0)


# ---------------------------------------------------------------- per frame

func step(dt: float) -> void:
	_read_events()
	if m.half != _last_half:
		_last_half = m.half
		for p in legs:
			legs[p] = minf(1.0, legs[p] + HALF_TIME_REST)   # a breather at half time
	if m.state == m.State.PLAY:
		_tire(dt)
	for p in m.players:
		var cap: float = legs.get(p, 1.0)
		if injured.has(p):
			cap = minf(cap, 1.0 - injured[p])
		p.stamina = minf(p.stamina, cap)
	_walk_off(dt)
	_think -= dt
	if _think <= 0.0:
		_think = 1.0
		for t in 2:
			if auto[t]:
				_computer_subs(t)
	if ball_dead():
		for t in 2:
			for r in pending[t].duplicate():
				if _can_come_off(r["off"]):
					pending[t].erase(r)
					_make(r["off"], r["on"])


## Play has stopped: a goal, half time, or a restart waiting to be taken.
func ball_dead() -> bool:
	if m.state == m.State.GOAL or m.state == m.State.HALF_TIME:
		return true
	return m.state == m.State.PLAY and m.restart_taker() != null


func _tire(dt: float) -> void:
	var per_sec: float = 1.0 / (m.half_seconds * 2.0)
	for p in m.players:
		var rate: float = LEGS_DRAIN * (1.3 - p.r("stamina") / 100.0) / 0.6
		if p.sprinting:
			rate *= 1.6
		elif p.is_keeper():
			rate *= 0.3
		legs[p] = maxf(0.3, legs.get(p, 1.0) - rate * per_sec * dt)


var _next_event := 0


## Late blocks and heavy knockdowns can injure: the harder the knock, the
## likelier and the worse.
func _read_events() -> void:
	if _next_event > m.events.size():
		_next_event = 0
	while _next_event < m.events.size():
		var e: Dictionary = m.events[_next_event]
		_next_event += 1
		var p = e.get("on")
		if p == null or not p in m.players or injured.has(p):
			continue
		var chance := 0.0
		if e["type"] == "late_block":
			chance = 0.1 + 0.3 * clampf((p.stagger - 0.5) / 0.8, 0.0, 1.0)
		elif e["type"] == "knockdown":
			chance = 0.03 + 0.12 * clampf((p.stagger - 0.35) / 0.95, 0.0, 1.0)
		if chance > 0.0 and randf() < chance:
			injured[p] = randf_range(0.25, 0.6)
			m.events.append({"type": "injury", "team": p.team, "on": p})
			m._say("%s is injured" % p.data.get("name", "A player"), 1.5)


# ---------------------------------------------------------------- the computer

func _computer_subs(t: int) -> void:
	if subs_left(t) <= 0 or not pending[t].is_empty() or m.state == m.State.FULL_TIME:
		return
	var share := match_share()
	# Anyone hurt comes off first, the worst first.
	var worst = null
	for p in m.squads[t]:
		if injured.get(p, 0.0) >= 0.35 and (worst == null or injured[p] > injured[worst]):
			worst = p
	if worst != null:
		var on = best_replacement(worst)
		if on != null:
			request(worst, on)
			return
	# Then the most tired outfield player, from the second half on.
	if share < TIRED_FROM or (subs_left(t) == 1 and share < LAST_SUB_FROM):
		return
	var tired = null
	for p in m.squads[t]:
		if p.is_keeper():
			continue
		if legs.get(p, 1.0) < TIRED and (tired == null or legs[p] < legs[tired]):
			tired = p
	if tired != null:
		var on = best_replacement(tired)
		if on != null:
			request(tired, on)


## The bench player best suited to replace `off`: a keeper for a keeper,
## otherwise the same kind of player (back, centre, forward) if there is one,
## then the best rated. Null if nobody fits.
func best_replacement(off):
	var best = null
	var best_score := -INF
	for pd in bench[off.team]:
		if pending[off.team].any(func(r): return r["on"] == pd):
			continue
		var keeper: bool = TeamData.role_of(str(pd.get("position", ""))) == "GK"
		if keeper != off.is_keeper():
			continue
		var score: float = TeamData.overall({"position": off.position_code, "pace": pd["pace"], "control": pd["control"],
			"passing": pd["passing"], "shooting": pd["shooting"], "tackling": pd["tackling"], "keeping": pd["keeping"]})
		if TeamData.role_of(str(pd.get("position", ""))) == off.role:
			score += 10.0
		if score > best_score:
			best_score = score
			best = pd
	return best


# ---------------------------------------------------------------- making the change

## Not while they're on the ball, taking the restart or in the throw-up.
func _can_come_off(p) -> bool:
	if not p in m.squads[p.team]:
		return false
	if p == m.carrier or p == m.penalty_taker or p == m.gather_keeper or p == m.shy_lift:
		return false
	if p == m.restart_taker() or p in m.throw_up_pair:
		return false
	return not m.in_battle(p)


## Just in front of the side's dugout on the far touchline (the home side's
## is in the half it defends first).
func bench_spot(t: int) -> Vector2:
	return Vector2(m.PITCH.x / 2.0 + (-DUGOUT_X if t == 0 else DUGOUT_X), -DUGOUT_BACK + 1.6)


func _make(off, on_data: Dictionary) -> void:
	var t: int = off.team
	var p = m.get_script().Player.new()
	p.team = t
	p.data = on_data
	p.number = int(on_data.get("number", 0))
	p.position_code = off.position_code   # takes the other's place in the side
	p.role = off.role
	p.home = off.home
	p.pos = bench_spot(t)
	p.facing = Vector2(0, 1)
	Body.setup(p)
	var i: int = m.squads[t].find(off)
	m.squads[t][i] = p
	m.players[m.players.find(off)] = p
	legs[p] = 1.0
	bench[t].erase(on_data)
	came_off[t].append(off.data)
	used[t] += 1
	# Forget the one going off wherever the match and the AI kept track of them.
	var ai = m.team_ai
	ai.plans.erase(off)
	ai.preset.erase(off)
	for marks in ai.marks:
		marks.erase(off)
		for k in marks.keys():
			if marks[k] == off:
				marks.erase(k)
	for k in ai.focus_player.size():
		if ai.focus_player[k] == off:
			ai.focus_player[k] = null
	if m.human == off:
		m.human = m._nearest_outfield(t, m.ball_pos, null)
	if m.has_method("_apply_shapes"):
		m._apply_shapes()   # the team shape and who marks whom, with the new man in it
	off.vel = Vector2.ZERO
	off.desired = Vector2.ZERO
	off.swing_t = -1.0
	off.reach = 0.0
	leaving.append(off)
	var minute: int = m.match_minute()
	made.append({"team": t, "off": off.data, "on": on_data, "minute": minute})
	m.events.append({"type": "substitution", "team": t, "off": off, "on": p})


## Players coming off walk to their bench and then leave the picture.
func _walk_off(dt: float) -> void:
	for p in leaving.duplicate():
		var to: Vector2 = bench_spot(p.team)
		var d: Vector2 = to - p.pos
		if d.length() < 0.5:
			leaving.erase(p)
			continue
		p.vel = d.normalized() * WALK_OFF
		p.facing = d.normalized()
		p.pos += p.vel * dt
		p.stick = Body.rest_spot(p)
