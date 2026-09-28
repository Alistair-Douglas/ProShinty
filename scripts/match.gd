extends Node3D
## One shinty match: pitch, two 12-a-side teams, ball physics and computer AI.
## The simulation runs on a flat 2D pitch in yards (x along the pitch, y across,
## ball_z is height). MatchView draws it in 3D and Hud draws the scoreboard.
## Set `config` before adding to the tree (or leave empty to read from Game).

const TeamData := preload("res://scripts/team_data.gd")
const MatchView := preload("res://scripts/match_view.gd")
const Hud := preload("res://scripts/hud.gd")
const Referee := preload("res://scripts/referee.gd")
const Body := preload("res://scripts/player_physics.gd")
const Counters := preload("res://scripts/swing_counters.gd")
const TeamAI := preload("res://scripts/team_ai.gd")

const PITCH := Vector2(150, 75)
const GOAL_W := 4.0          # 12 ft between the posts
const CROSSBAR := 3.33       # 10 ft
const D_RADIUS := 10.0
const GRAVITY := 10.7        # yards/s^2
const PLAYER_R := 0.75
const REACH := 1.7           # how far a caman reaches
const REACH_HEIGHT := 2.3
const KEEPER_REACH_HEIGHT := 3.2
const GOAL_PAUSE := 3.0
const HALF_TIME_PAUSE := 3.0
const PENALTY_SPOT := 20.0   # penalty hit, yards from the goal line
const FREE_HIT_BACK := 5.0   # opponents stand this far off a set piece
const OVERSWING_MAX := 1.35  # hit meter past full power
const CARRY_CATCH_UP := 6.0  # yd/s: how fast a gathered ball settles onto the stick
const DRIBBLE_ROLL_DECEL := 4.0  # yd/s^2: a tapped ball slowing on the grass
const DRIBBLE_LOSE := 3.2    # yards: a touch this far from the carrier has got away
const SHY_TOSS := 6.5        # yd/s: how hard a shy is thrown up
const SHY_ARM := 0.8         # the shy is tossed an arm's length in front
const SHY_ATTEMPTS := 3      # tries at a clean strike before the shy goes over
const SHY_MIN_SPEED := 14.0  # yd/s: the softest shy
const SHY_MAX_SPEED := 38.0  # and the hardest
const RESTART_AIM_RATE := 1.2  # rad/s: how fast the player turns their aim at a restart
const SHY_HOLD := 0.35       # the ball is lifted in the hand this long before it leaves it
const THROW_UP_SET := 1.2   # seconds the pair stand ready before the ball goes up
const THROW_UP_TOSS := 8.0   # yd/s: the referee's throw
const THROW_UP_GAP := 0.8    # each centre stands this far from the spot
const SET_PIECE_PAUSE := 2.2 # hit-outs and corners: play stops while players get set
const SET_PIECE_MIN := 1.0   # a human taker can't hit it before this

enum State { THROW_UP, PLAY, GOAL, HALF_TIME, FULL_TIME }


class Player:
	var team: int
	var data: Dictionary
	var number: int
	var position_code: String
	var role: String
	var home: Vector2
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var desired := Vector2.ZERO
	var facing := Vector2.RIGHT
	var sprinting := false
	var stamina := 1.0
	var cooldown := 0.0      # after a tackle attempt
	var touch_block := 0.0   # can't touch the ball again yet
	var think := 0.0         # AI reaction timer
	var swing := 0.0         # caman swing animation
	# Body and caman physics (see player_physics.gd)
	var mass := 75.0         # kg
	var hand := 1.0          # 1 = right-handed (stick on the right), -1 = left
	var accel := Vector2.ZERO
	var stagger := 0.0       # off balance after a hard hit
	var lunge := 0.0         # poke check or keeper dive in progress
	var stick := Vector3.ZERO    # caman head: pitch x, y and height
	var stick_target = null      # Vector3 the caman is reaching for
	var save_point = null        # keeper: where the shot will cross
	var reach := 0.0         # 0 = carried, 1 = full stretch (for the view)
	var one_hand := false    # reaching one-handed at the end of the handle
	var swing_t := -1.0      # seconds until the caman meets the ball; < 0 = not swinging
	var swing_req := {}      # the hit being swung
	var shy_ready := false   # taking a shy: the next hit is thrown up and struck overhead
	var shy_toss := false    # ball thrown up, overhead strike coming
	var shy_attempts := 0
	var throw_up := false    # a centre contesting the throw-up, caman raised
	var anim := {}           # latest one-off animation, for the view
	var anim_seq := 0
	var charged := 0.0       # human: how much of the backswing was held
	# Countering a swing (see swing_counters.gd)
	var block_t := 0.0
	var cleek_t := 0.0
	var barge_t := 0.0
	var barge_hit := false
	var counter_age := 0.0
	var read_swing := -1     # AI: the opponent swing already reacted to
	var overswing := 0.0     # human: 0..1 past full power

	func r(key: String) -> float:
		return float(data.get(key, 50))

	func top_speed() -> float:
		return 5.8 + r("pace") / 100.0 * 3.0

	func is_keeper() -> bool:
		return role == "GK"


var config := {}
var manual_step := false   # tests drive step() themselves

var teams: Array = []
var players: Array = []
var squads := [[], []]
var colors := [[Color.RED, Color.WHITE], [Color.BLUE, Color.YELLOW]]   # [shirt, trim] of the kit each side wears
var kits := [{}, {}]   # the kit each side wears (TeamData.match_kits)
var score := [0, 0]
var shots := [0, 0]
var state := State.THROW_UP
var state_timer := 0.0
var half := 1
var clock := 0.0
var half_seconds := 180.0
var human_side := 0
var human: Player = null
var difficulty := 1
var attack_dir := [1, -1]
var protected_timer := 0.0
var paused := false
var charge := -1.0
var steer := Vector2.ZERO   # smoothed human steering direction
var message := ""
var message_timer := 0.0
var events: Array = []

var ball_pos := Vector2.ZERO
var ball_z := 0.0
var ball_vel := Vector2.ZERO
var ball_vz := 0.0
var ball_sim := ShintyMatchAdapter.BallSim.new(PITCH, GOAL_W, CROSSBAR)
var carrier: Player = null
var last_team := -1
var referee := Referee.new()
var penalty_taker: Player = null
var gather_keeper: Player = null   # a saved ball dropping to the keeper
var foul_pending = null            # [offender, fouled] seen by the referee
var gather_t := 0.0
var team_ai: TeamAI
var set_piece := ""                # "Hit-out" or "Corner" while one is being taken
var set_piece_taker: Player = null
var set_piece_t := 0.0             # seconds since it was awarded
var throw_up_pair: Array = []     # the two centres contesting the throw-up
var throw_up_tossed := false
var throw_up_t := 0.0              # seconds since the ball went up
var throw_up_ideal := 0.0          # when it drops to where a caman meets it overhead
var throw_up_swing := {}           # Player -> when they swing at it
var shy_lift: Player = null        # taking a shy with the ball still in the hand
var shy_lift_t := 0.0
var shy_lift_from := Vector3.ZERO
var restart_aim := 0.0             # the player's aim at a restart, off restart_base
var restart_base := Vector2.RIGHT  # straight in from the line (a shy) or the default aim
var dribble_vel := Vector2.ZERO    # a dribbled ball rolling ahead of its carrier
var dribble_taps := 0



func _ready() -> void:
	if config.is_empty():
		var game := get_node_or_null("/root/Game")
		if game:
			config = game.match_config()
	_setup()
	if not manual_step:
		var view := MatchView.new()
		view.name = "View"
		add_child(view)
		var layer := CanvasLayer.new()
		var hud := Hud.new()
		hud.match_node = self
		hud.view = view
		layer.add_child(hud)
		add_child(layer)


func _setup() -> void:
	teams = [config["home"], config["away"]]
	team_ai = TeamAI.new(self)
	human_side = int(config.get("human_side", 0))
	difficulty = int(config.get("difficulty", 1))
	half_seconds = float(config.get("half_seconds", 180.0))
	if config.has("seed"):
		seed(int(config["seed"]))
	kits = TeamData.match_kits(teams[0], teams[1])
	for t in 2:
		var c: Dictionary = kits[t]
		colors[t] = [Color.from_string(str(c.get("primary", "#cc2222")), Color.RED),
			Color.from_string(str(c.get("secondary", "#ffffff")), Color.WHITE)]
		for pd in TeamData.starting_twelve(teams[t]):
			var p := Player.new()
			p.team = t
			p.data = pd
			p.number = int(pd.get("number", 0))
			p.position_code = pd.get("position", "LM")
			p.role = TeamData.role_of(p.position_code)
			p.home = TeamData.FORMATION.get(p.position_code, Vector2(0.5, 0.5))
			Body.setup(p)
			squads[t].append(p)
			players.append(p)
	referee.setup(self)
	_start_throw_up()
	if human_side >= 0:
		human = _nearest_outfield(human_side, ball_pos, null)


# ---------------------------------------------------------------- main loop

func _physics_process(delta: float) -> void:
	if manual_step:
		return
	if Input.is_action_just_pressed("pause") and state != State.FULL_TIME:
		paused = not paused
	if paused:
		if Input.is_action_just_pressed("quit_match"):
			get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
		return
	if state == State.FULL_TIME and (Input.is_action_just_pressed("ui_accept") or Input.is_action_just_pressed("shoot")):
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
		return
	step(delta)


func step(dt: float) -> void:
	message_timer = max(0.0, message_timer - dt)
	if state != State.PLAY and state != State.FULL_TIME:
		referee.step(dt)
	match state:
		State.THROW_UP:
			_step_throw_up(dt)
		State.PLAY:
			_update_set_piece(dt)
			if shy_taker() == null and set_piece_taker_now() == null:
				clock += dt   # the clock stops while a shy, hit-out or corner is taken
			_update_players(dt)
			_take_penalty()
			_update_ball(dt)
			referee.step(dt)
			_check_ball_out()
			if clock >= half_seconds and state == State.PLAY:
				_end_half()
		State.GOAL:
			state_timer -= dt
			_update_ball(dt)
			for p in players:
				p.desired = Vector2.ZERO
				_move(p, dt)
			if state_timer <= 0.0:
				_start_throw_up()
		State.HALF_TIME:
			state_timer -= dt
			if state_timer <= 0.0:
				half = 2
				clock = 0.0
				attack_dir = [-1, 1]
				_start_throw_up()
		State.FULL_TIME:
			pass


func _say(text: String, seconds: float = 2.0) -> void:
	message = text
	message_timer = seconds


func _start_throw_up() -> void:
	state = State.THROW_UP
	state_timer = 1.2
	carrier = null
	last_team = -1
	ball_pos = PITCH / 2.0
	ball_z = 1.4   # in the referee's hand
	ball_vel = Vector2.ZERO
	ball_vz = 0.0
	protected_timer = 0.0
	_clear_set_piece()
	throw_up_pair = []
	throw_up_tossed = false
	throw_up_t = 0.0
	throw_up_swing = {}
	for p in players:
		var f: Vector2 = p.home
		if not p.is_keeper() and p.position_code != "LM":
			f.x = min(f.x * 0.55, 0.44)
		p.pos = frac_to_world(p.team, f)
		p.throw_up = false
		if p.position_code == "LM" and throw_up_pair.size() == p.team:
			# The two centres face each other over the spot, sticks raised.
			p.pos = PITCH / 2.0 - Vector2(attack_dir[p.team] * THROW_UP_GAP, 0)
			p.throw_up = true
			throw_up_pair.append(p)
		p.vel = Vector2.ZERO
		p.desired = Vector2.ZERO
		p.facing = Vector2(attack_dir[p.team], 0)
		p.stagger = 0.0
		p.lunge = 0.0
		p.swing_t = -1.0
		p.shy_ready = false
		p.shy_toss = false
		p.stick = Body.rest_spot(p)
	gather_keeper = null
	_say("Throw-up", 1.2)
	events.append({"type": "throw_up"})


func _end_half() -> void:
	carrier = null
	ball_vel = Vector2.ZERO
	if half == 1:
		state = State.HALF_TIME
		state_timer = HALF_TIME_PAUSE
		_say("Half time", HALF_TIME_PAUSE)
	else:
		state = State.FULL_TIME
		_say("Full time", 9999.0)
		var game := get_node_or_null("/root/Game") if is_inside_tree() else null
		if game:
			game.last_result = {"home": teams[0]["name"], "away": teams[1]["name"], "score": score.duplicate()}
	events.append({"type": "half_end", "half": half, "score": score.duplicate()})


# ---------------------------------------------------------------- geometry helpers

func frac_to_world(team: int, f: Vector2) -> Vector2:
	var x := f.x * PITCH.x if attack_dir[team] == 1 else (1.0 - f.x) * PITCH.x
	return Vector2(x, f.y * PITCH.y)


func own_frac(team: int, x: float) -> float:
	return x / PITCH.x if attack_dir[team] == 1 else 1.0 - x / PITCH.x


func target_goal(team: int) -> Vector2:
	return Vector2(PITCH.x if attack_dir[team] == 1 else 0.0, PITCH.y / 2.0)


func own_goal(team: int) -> Vector2:
	return target_goal(1 - team)


func home_world(p: Player) -> Vector2:
	return home_at(p, ball_pos)


## Formation spot for p with the ball at `ball` (see home_world).
func home_at(p: Player, ball: Vector2) -> Vector2:
	var f: Vector2 = p.home
	if not p.is_keeper():
		var bx := own_frac(p.team, ball.x)
		# Forwards are man-marked by the opposing backs and hold their line;
		# everyone else shifts up and down the park with the ball.
		var shift := 0.15 if p.role == "FWD" else 0.5
		f.x = clamp(f.x + (bx - 0.5) * shift, 0.05, 0.94)
		f.y = clamp(f.y + (ball.y / PITCH.y - 0.5) * (0.12 if p.role == "FWD" else 0.3), 0.06, 0.94)
		if carrier != null and carrier.team == p.team:
			f.x = min(f.x + 0.05, 0.94)
	return frac_to_world(p.team, f)


func _dist_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	return p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b))


func _lane_clearance(team: int, from: Vector2, to: Vector2) -> float:
	var best := 99.0
	for o in squads[1 - team]:
		best = min(best, _dist_to_segment(o.pos, from, to))
	return best


func _nearest_opponent_dist(p: Player) -> float:
	var best := 999.0
	for o in squads[1 - p.team]:
		best = min(best, o.pos.distance_to(p.pos))
	return best


func _nearest_outfield(team: int, point: Vector2, exclude: Player) -> Player:
	var best: Player = null
	var best_d := INF
	for p in squads[team]:
		if p.is_keeper() or p == exclude:
			continue
		var d: float = p.pos.distance_squared_to(point)
		if d < best_d:
			best_d = d
			best = p
	return best


func _ball_intercept_point() -> Vector2:
	var t: float = clamp(ball_vel.length() / 12.0, 0.0, 1.0)
	var pt := ball_pos + ball_vel * t
	return Vector2(clamp(pt.x, 0.0, PITCH.x), clamp(pt.y, 0.0, PITCH.y))


## Computer teams get a small edge on hard and a handicap on easy.
func _skill_mod(team: int) -> float:
	if human_side < 0 or team == human_side:
		return 0.0
	return [-0.1, 0.0, 0.08][difficulty]


func _reaction(team: int) -> float:
	if human_side >= 0 and team != human_side:
		return [0.55, 0.35, 0.2][difficulty] + randf() * 0.15
	return 0.3 + randf() * 0.15


# ---------------------------------------------------------------- players

func _update_players(dt: float) -> void:
	protected_timer = max(0.0, protected_timer - dt)
	for p in players:
		p.cooldown = max(0.0, p.cooldown - dt)
		p.touch_block = max(0.0, p.touch_block - dt)
		p.swing = max(0.0, p.swing - dt)
		p.stagger = max(0.0, p.stagger - dt)
		p.lunge = max(0.0, p.lunge - dt)
		Counters.tick(p, dt)
		p.sprinting = false
	if human != null and human.is_keeper() and carrier != human:
		human = _nearest_outfield(human_side, ball_pos, null)
	for t in 2:
		_ai_team(t, dt)
	if human != null and state == State.PLAY:
		_human_control(dt)
	elif human != null:
		human.desired = Vector2.ZERO
	for p in players:
		if p.is_keeper():
			Body.keeper_reflex(self, p, dt)
		_move(p, dt)
	_separate()
	if foul_pending != null:
		var fouled: Player = foul_pending[1]
		foul_pending = null
		_restart(fouled.team, fouled.pos, "Free hit")
		_say("Foul: push in the back", 1.5)
		return
	for p in players:
		Body.update_stick(self, p, dt)
		if p.swing_t >= 0.0:
			p.swing_t -= dt
			if p.swing_t < 0.0:
				_contact(p)
	var guarded: Player = carrier
	for p in players:
		if p.shy_toss:
			guarded = p   # opponents stand off while a shy is taken
	if (protected_timer > 0.0 and carrier != null) or (guarded != null and (guarded.shy_toss or guarded.shy_ready)):
		for o in squads[1 - guarded.team]:
			var off: Vector2 = o.pos - guarded.pos
			if off.length() < 5.0:
				o.pos = guarded.pos + off.normalized() * 5.0 if off.length() > 0.01 else guarded.pos + Vector2(0, 5)


func _move(p: Player, dt: float) -> void:
	Body.move(self, p, dt)


func _separate() -> void:
	Body.collide(self)


func _steer_to(p: Player, target: Vector2, sprint: bool) -> void:
	var off := target - p.pos
	var d := off.length()
	if d < 0.5:
		p.desired = Vector2.ZERO
		return
	var speed := p.top_speed() * (1.0 if sprint else 0.72)
	p.desired = off / d * speed * min(1.0, d / 3.0)
	p.sprinting = sprint and d > 3.0


func _steer_dir(p: Player, dir: Vector2, sprint: bool) -> void:
	p.desired = dir.normalized() * p.top_speed() * (1.0 if sprint else 0.8)
	p.sprinting = sprint


# ---------------------------------------------------------------- AI

func _ai_team(t: int, dt: float) -> void:
	var have := carrier != null and carrier.team == t
	var chasers := []
	if state == State.PLAY and not have:
		var pt := _ball_intercept_point()
		var ranked := []
		for p in squads[t]:
			if not p.is_keeper() and p != human:
				ranked.append(p)
		ranked.sort_custom(func(a, b): return a.pos.distance_squared_to(pt) < b.pos.distance_squared_to(pt))
		var n := 1
		if t != human_side and (difficulty == 2 or own_frac(t, ball_pos.x) < 0.35):
			n = 2
		chasers = ranked.slice(0, n)
	if state == State.PLAY:
		team_ai.begin_team(t, dt, chasers)
	for p in squads[t]:
		if p == human:
			continue
		if state == State.THROW_UP:
			p.desired = Vector2.ZERO
			continue
		if p.is_keeper():
			_ai_keeper(p, dt)
		elif p == carrier:
			_ai_carrier(p, dt)
		elif p in chasers:
			_ai_chase(p, dt)
		else:
			team_ai.off_ball(p, dt)


func _ai_chase(p: Player, dt: float) -> void:
	_steer_to(p, _ball_intercept_point(), true)
	if carrier != null and carrier.team != p.team:
		_steer_to(p, carrier.pos, true)
		if Counters.ai_counter(self, p):
			return
		p.think -= dt
		if p.think <= 0.0 and p.pos.distance_to(carrier.pos) < REACH + 0.5:
			p.think = _reaction(p.team)
			_try_tackle(p, carrier)


func _ai_carrier(p: Player, dt: float) -> void:
	if p.swing_t >= 0.0:
		return   # mid-swing: committed
	if p.shy_ready or p == set_piece_taker_now():
		# A shy, hit-out or corner has to be taken: pass it to someone open or hit it long.
		p.think -= dt
		if p.think <= 0.0 and protected_timer <= 0.0 and not _ai_pass(p, false):
			_hit_long(p)
		return
	var goal := target_goal(p.team)
	var to_goal := goal - p.pos
	var d := to_goal.length()
	var pressure := _nearest_opponent_dist(p)
	p.think -= dt
	if p.think <= 0.0 and protected_timer <= 0.0:
		p.think = _reaction(p.team)
		var shoot_range := 16.0 + p.r("shooting") * 0.16
		if d < shoot_range and abs(to_goal.normalized().x) > 0.5:
			if d < 20.0 or randf() < 0.35 or pressure < 3.0:
				_ai_shoot(p)
				return
		if pressure < 4.0 and randf() < 0.6 and _ai_pass(p, false):
			return
		if randf() < 0.12 and _ai_pass(p, true):
			return
		if own_frac(p.team, p.pos.x) < 0.3 and pressure < 6.0 and randf() < 0.5:
			_hit_long(p)
			return
	# Dribble towards goal, steering around opponents and away from the lines.
	var dir := to_goal.normalized()
	for o in squads[1 - p.team]:
		var off: Vector2 = p.pos - o.pos
		var dd := off.length()
		if dd < 7.0 and dd > 0.01 and off.dot(dir) < 1.0:
			dir += off / dd * (7.0 - dd) / 7.0 * 1.3
	if p.pos.y < 5.0:
		dir.y += 1.0
	elif p.pos.y > PITCH.y - 5.0:
		dir.y -= 1.0
	_steer_dir(p, dir, pressure < 6.0)


func _ai_shoot(p: Player) -> void:
	var goal := target_goal(p.team)
	var keeper := _keeper_of(1 - p.team)
	var side := 1.0 if randf() < 0.5 else -1.0
	if keeper != null and abs(keeper.pos.y - goal.y) > 0.4:
		side = -sign(keeper.pos.y - goal.y)
	var aim := goal + Vector2(0, side * (GOAL_W / 2.0 - 0.6))
	var d := p.pos.distance_to(goal)
	_strike(p, (aim - p.pos).normalized(), clamp(d / 30.0 + 0.45, 0.55, 1.0), randf_range(0.5, 3.0), "shooting")
	shots[p.team] += 1


func _ai_pass(p: Player, forward_only: bool) -> bool:
	var best: Player = null
	var best_score := -INF
	for m in squads[p.team]:
		if m == p or m.is_keeper():
			continue
		# Judge a runner by where they'll be when the ball arrives.
		var spot: Vector2 = m.pos + m.vel * 0.6
		var d: float = p.pos.distance_to(spot)
		if d < 6.0 or d > 50.0:
			continue
		var fwd: float = (spot.x - p.pos.x) * attack_dir[p.team]
		if forward_only and fwd < 4.0:
			continue
		var open_space: float = min(team_ai._space_at(1 - p.team, spot), 10.0)
		var lane: float = min(_lane_clearance(p.team, p.pos, spot), 5.0)
		var s: float = fwd * 0.5 + open_space * 1.5 + lane * 2.0 - d * 0.15 \
			- max(0.0, 8.0 - team_ai._edge_dist(spot)) * 0.8
		if s > best_score:
			best_score = s
			best = m
	if best == null or best_score < 5.0:
		return false
	_pass_to(p, best)
	return true


func _pass_to(p: Player, m: Player) -> void:
	var d := p.pos.distance_to(m.pos)
	var speed: float = clamp(d * 0.9 + 9.0, 13.0, 38.0)
	var t := d / speed * 1.3
	var lead := m.pos + m.vel * t * 0.7
	var loft := 0.4
	if d > 14.0 and _lane_clearance(p.team, p.pos, lead) < 2.5:
		loft = min(GRAVITY * t * 0.5, 9.0)  # lob it over the opponents
	_strike_speed(p, (lead - p.pos).normalized(), speed, loft, "passing")
	if p.team == human_side:
		human = m


func _hit_long(p: Player) -> void:
	var best: Player = null
	var best_x := -INF
	for m in squads[p.team]:
		if m == p or m.is_keeper():
			continue
		var x: float = own_frac(p.team, m.pos.x) + randf() * 0.15
		if x > best_x:
			best_x = x
			best = m
	var aim := target_goal(p.team) if best == null else best.pos
	_strike(p, (aim - p.pos).normalized(), 0.85, 7.0, "passing")


func _ai_keeper(k: Player, dt: float) -> void:
	var g := own_goal(k.team)
	if carrier == k:
		k.desired = Vector2.ZERO
		k.think -= dt
		if k.think <= 0.0:
			if not _ai_pass(k, true):
				_hit_long(k)
		return
	var tgt_y := ball_pos.y
	var toward: float = -attack_dir[k.team]
	if carrier == null and ball_vel.x * toward > 5.0:
		var t := (g.x - ball_pos.x) / ball_vel.x
		if t > 0.0 and t < 2.0:
			tgt_y = ball_pos.y + ball_vel.y * t
	tgt_y = clamp(tgt_y, g.y - GOAL_W / 2.0 - 0.6, g.y + GOAL_W / 2.0 + 0.6)
	var tgt := Vector2(g.x + attack_dir[k.team] * 1.2, tgt_y)
	# Come out for a loose ball in the D when no opponent is closer.
	if carrier == null and ball_pos.distance_to(g) < D_RADIUS and ball_vel.length() < 10.0 and ball_z < 1.0:
		var mine := k.pos.distance_to(ball_pos)
		var closer := false
		for o in squads[1 - k.team]:
			if o.pos.distance_to(ball_pos) < mine:
				closer = true
		if not closer:
			tgt = ball_pos
	_steer_to(k, tgt, true)


func _keeper_of(team: int) -> Player:
	for p in squads[team]:
		if p.is_keeper():
			return p
	return null


# ---------------------------------------------------------------- human control

func _human_control(dt: float) -> void:
	var p := human
	var raw := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var sprint := Input.is_action_pressed("sprint") and p.stamina > 0.05
	var mv := _smooth_steer(p, raw, dt)
	if mv.length() > 0.15:
		# Analogue: a half-pushed stick jogs, a full one runs.
		p.desired = mv.normalized() * p.top_speed() * (1.0 if sprint else 0.78) * clamp(mv.length(), 0.35, 1.0)
		p.sprinting = sprint
	else:
		p.desired = Vector2.ZERO
	if Input.is_action_just_pressed("switch"):
		var pick := _nearest_outfield(human_side, ball_pos, p)
		if pick != null and carrier != p:
			human = pick
			charge = -1.0
			return
	var aim := mv.normalized() if mv.length() > 0.15 else p.facing
	if p == set_piece_taker_now() or (p.shy_ready and carrier == p):
		# Standing over a restart: the stick turns the aim smoothly, within
		# a half circle (for a shy, from up the line round to down the line).
		p.desired = Vector2.ZERO
		if mv.length() > 0.15:
			var want: float = clamp(restart_base.angle_to(mv), -PI / 2.0, PI / 2.0)
			restart_aim = move_toward(restart_aim, want, RESTART_AIM_RATE * dt)
		p.facing = restart_base.rotated(restart_aim)
		aim = p.facing
	if p == set_piece_taker_now() and set_piece_t < SET_PIECE_MIN:
		return   # play has stopped: let everyone get set first
	if Input.is_action_just_pressed("shoot"):
		# Also how you swing at an opponent's ball: beat their swing to it.
		charge = 0.0
	if Input.is_action_just_pressed("block"):
		Counters.start_block(self, p)
	if Input.is_action_just_pressed("cleek"):
		Counters.start_cleek(self, p)
	if Input.is_action_just_pressed("barge"):
		Counters.start_barge(self, p)
	if charge >= 0.0:
		# Golf-style meter: it fills to full power, then keeps going into an
		# overswing that adds power error (miss-hits and curve) but no power.
		charge = min(OVERSWING_MAX, charge + dt * 1.3)
		if not Input.is_action_pressed("shoot"):
			# Swing whether or not the ball is there yet: timing a first-time
			# hit on a ball arriving is up to you. Miss it and it's fresh air.
			_human_shoot(p, aim, charge)
			charge = -1.0
	if Input.is_action_just_pressed("pass"):
		if carrier == p or _ball_in_reach(p):
			_human_pass(p, aim)
		elif carrier != null and carrier.team != p.team and p.pos.distance_to(carrier.pos) < REACH + 0.8:
			_try_tackle(p, carrier)


## Turn 8-way keyboard input into a full 360-degree steer: the direction
## sweeps round towards the keys held at a limited rate (slower with the ball
## and at speed), so tapping a diagonal key bends the run instead of snapping
## it. A gamepad stick is already analogue and passes straight through.
func _smooth_steer(p: Player, raw: Vector2, dt: float) -> Vector2:
	if raw.length() < 0.15:
		steer = Vector2.ZERO
		return raw
	var digital: bool = abs(raw.x) in [0.0, 1.0] and abs(raw.y) in [0.0, 1.0]
	if not digital:
		steer = raw
		return raw
	var want := raw.normalized()
	if steer.length() < 0.1:
		steer = p.facing if p.vel.length() > 1.0 and p.facing.dot(want) > -0.2 else want
	var frac: float = clamp(p.vel.length() / p.top_speed(), 0.0, 1.0)
	var rate: float = lerp(9.0, 4.0, frac) * (0.75 if carrier == p else 1.0)
	var ang := steer.angle_to(want)
	steer = steer.rotated(clamp(ang, -rate * dt, rate * dt)).normalized()
	return steer


func _ball_in_reach(p: Player) -> bool:
	return carrier == null and p.touch_block <= 0.0 and ball_z < REACH_HEIGHT and p.pos.distance_to(ball_pos) < Body.max_reach(p) + 0.4


func _human_shoot(p: Player, aim: Vector2, charged: float) -> void:
	var power: float = min(charged, 1.0)
	p.overswing = max(0.0, charged - 1.0) / (OVERSWING_MAX - 1.0)
	p.charged = power
	var goal := target_goal(p.team)
	var to_goal := goal - p.pos
	var loft := power * 7.0
	if to_goal.length() < 45.0 and abs(aim.angle_to(to_goal)) < deg_to_rad(40.0):
		# Aim assist: pull the shot towards the goal, placement follows the stick.
		var spot := goal + Vector2(0, clamp(aim.y * 6.0, -1.0, 1.0) * (GOAL_W / 2.0 - 0.5))
		aim = (spot - p.pos).normalized()
		loft = 0.5 + power * 3.0
		if carrier == p or _ball_in_reach(p):
			shots[p.team] += 1
	_strike(p, aim, max(power, 0.2), loft, "shooting")


func _human_pass(p: Player, aim: Vector2) -> void:
	var best: Player = null
	var best_score := -INF
	for m in squads[p.team]:
		if m == p or m.is_keeper():
			continue
		var off: Vector2 = m.pos - p.pos
		var d := off.length()
		if d < 3.0 or d > 60.0:
			continue
		var cosang := aim.dot(off / d)
		if cosang < 0.5:
			continue
		var s := cosang * 30.0 - d * 0.4
		if s > best_score:
			best_score = s
			best = m
	if best != null:
		_pass_to(p, best)
	else:
		_strike_speed(p, aim, 18.0, 0.5, "passing")


# ---------------------------------------------------------------- ball

func _strike(p: Player, dir: Vector2, power: float, loft: float, skill_key: String) -> void:
	var speed: float = lerp(10.0, 20.0 + p.r("shooting") * 0.26, power)
	_strike_speed(p, dir, speed, loft, skill_key, power)


## Start a hit. Like a golf swing it takes time: the caman goes back and comes
## through, and the ball is struck when it arrives (_contact), wherever the
## ball is by then. A carrier can be tackled or knocked off it mid-swing.
func _strike_speed(p: Player, dir: Vector2, speed: float, loft: float, skill_key: String, power: float = 0.5) -> void:
	if p.swing_t >= 0.0 or p.stagger > 0.0:
		return
	dir = dir.normalized()
	var skill := p.r(skill_key)
	var swing_power := ShintyStrike.power_for_speed(speed * ShintyMatchAdapter.YARD, skill)
	var kind := "pass" if skill_key == "passing" and loft < 3.0 and speed < 26.0 else "swing"
	p.swing_req = {"dir": dir, "speed": speed, "loft": loft, "skill_key": skill_key, "kind": kind}
	p.facing = dir
	p.swing = 0.3
	if p.shy_ready and carrier == p:
		_throw_up_shy(p)
		return
	var from_charge: float = p.charged if p == human else 0.0
	p.swing_t = ShintyPlayerModel.contact_delay(kind, swing_power, from_charge)
	anim(p, kind, swing_power, from_charge)
	p.charged = 0.0


## A shy: the taker tosses the ball straight up, an arm's length in front,
## and as it comes down brings the caman over the head with both hands, like
## a hammer, striking it with the back of the stick. Three attempts to make a
## clean strike; fresh air three times and the shy goes to the other side.
func _throw_up_shy(p: Player) -> void:
	p.shy_ready = false
	p.shy_toss = true
	p.shy_attempts += 1
	carrier = null
	# The ball is picked up and lifted in the free hand first (see
	# _lift_shy), then leaves the hand an arm's length in front at 1.4 yd.
	shy_lift = p
	shy_lift_t = 0.0
	shy_lift_from = Vector3(ball_pos.x, ball_pos.y, ball_z)
	ball_vel = Vector2.ZERO
	ball_vz = 0.0
	# Strike when it comes back down to where the caman meets it overhead.
	var a := 0.5 * GRAVITY
	var c := Body.OVERHEAD - 1.4
	p.swing_t = SHY_HOLD + (SHY_TOSS + sqrt(SHY_TOSS * SHY_TOSS - 4.0 * a * c)) / (2.0 * a)
	# Up and over, as hard as the taker chose to hit it.
	var req: Dictionary = p.swing_req
	req["speed"] = clamp(req["speed"], SHY_MIN_SPEED, SHY_MAX_SPEED)
	req["loft"] = max(req["loft"], req["speed"] * 0.45)
	req["kind"] = "shy"
	for o in players:
		o.touch_block = max(o.touch_block, p.swing_t + 0.1)
	anim(p, "shy", 1.0)


## The caman arrives. How cleanly it meets the ball decides the hit.
func _contact(p: Player) -> void:
	var req: Dictionary = p.swing_req
	var shy: bool = p.shy_toss
	p.shy_toss = false
	if not shy and Counters.intercept(self, p):
		return
	var offset := 0.0
	if shy:
		# How far the ball has drifted from where the overhead swing comes through.
		var spot := Vector3(p.pos.x + p.facing.x * SHY_ARM, p.pos.y + p.facing.y * SHY_ARM, Body.OVERHEAD)
		# The taker adjusts to a toss that drifts a little; beyond that it's a stretch.
		offset = max(0.0, spot.distance_to(Vector3(ball_pos.x, ball_pos.y, ball_z)) - 0.5)
	elif carrier == p:
		offset = 0.0
		# An opponent swinging at the same ball at the same moment: a clash.
		for q in squads[1 - p.team]:
			if q.swing_t >= 0.0 and q.swing_t < Counters.CLASH_WINDOW and q.pos.distance_to(ball_pos) < Body.max_reach(q) + 0.3:
				Counters.clash(self, p, q)
				return
	elif carrier == null or carrier.team != p.team:
		if carrier != null and carrier.swing_t >= 0.0 and carrier.swing_t < Counters.CLASH_WINDOW:
			Counters.clash(self, p, carrier)
			return
		# First-time hit: how far the ball is from where the caman comes through.
		var spot := Body.rest_spot(p) + Vector3(p.facing.x, p.facing.y, 0.0) * 0.1
		offset = max(0.0, spot.distance_to(Vector3(ball_pos.x, ball_pos.y, ball_z)) - Body.CONTACT_R)
		if ball_z > REACH_HEIGHT or offset > 0.7:
			offset = 99.0
	else:
		offset = 99.0   # a team-mate has it
	var mine := carrier == p
	if offset > 5.0:
		_fresh_air(p, mine, shy)
		return
	# What makes the hit harder: running flat out, being hustled, an overswing.
	var diff: float = clamp(p.vel.length() / p.top_speed(), 0.0, 1.0) * 0.3 + p.overswing * 0.7
	if not shy and _nearest_opponent_dist(p) < 2.0:
		diff += 0.2
	if shy:
		# Overhead with the back of the stick: the harder you go at it, the
		# likelier you are to miss it or shank it off the heel or toe.
		var force: float = clamp((req["speed"] - SHY_MIN_SPEED) / (SHY_MAX_SPEED - SHY_MIN_SPEED), 0.0, 1.0)
		diff += 0.05 + force * force * 0.7
	var res := ShintyMatchAdapter.swing_like_match(p.data, req["dir"], req["speed"], req["loft"], req["skill_key"],
		ball_vel, ball_vz, _skill_mod(p.team), clamp(diff, 0.0, 1.0), offset)
	p.overswing = 0.0
	if res["miss"]:
		_fresh_air(p, mine, shy)
		return
	if carrier != null and carrier != p:
		# Got there first and hit it off their stick.
		carrier.swing_t = -1.0
		carrier.touch_block = 0.3
		events.append({"type": "beat_to_it", "team": p.team})
	carrier = null
	if not shy:
		var at: Vector3 = p.stick if mine else Body.rest_spot(p)
		ball_pos = Vector2(at.x, at.y)
		ball_z = max(ball_z, 0.2)
	ball_vel = res["ball_vel"]
	ball_vz = res["ball_vz"]
	ball_sim.set_spin(res["spin"])
	p.touch_block = 0.35
	last_team = p.team
	events.append({"type": "hit", "team": p.team, "kind": res["kind"], "curve": res["curve"], "shy": shy})
	if p == penalty_taker:
		penalty_taker = null
	events.append({"type": "strike", "by": p, "at": ball_pos})
	if p == human or (p.team == human_side and shy):
		var note := {"thin": "Topped it", "fat": "Skied it", "heel": "Off the heel", "toe": "Off the toe"}
		if note.has(res["kind"]):
			_say(note[res["kind"]], 1.0)
		elif abs(res["curve"]) > 5.0 and req["speed"] > 22.0:
			_say("Bending it " + ("left" if res["curve"] > 0.0 else "right"), 1.0)


## The throw-up: the two centres stand face to face with their camans raised
## overhead, the referee throws the ball up between them, and as it drops
## both swing at it in the air. Whoever times it best knocks it away towards
## their own side; swing together and the sticks clash and it drops dead.
## The player (if one of the pair) times their own swing with the hit button.
func _step_throw_up(dt: float) -> void:
	for p in players:
		p.desired = Vector2.ZERO
		_move(p, dt)
		Body.update_stick(self, p, dt)
	if not throw_up_tossed:
		state_timer -= dt
		if state_timer <= 0.0:
			_toss_throw_up()
		return
	throw_up_t += dt
	ball_z += ball_vz * dt
	ball_vz -= GRAVITY * dt
	if human in throw_up_pair and not manual_step and Input.is_action_just_pressed("shoot"):
		throw_up_swing[human] = throw_up_t
	var last := 0.0
	for p in throw_up_pair:
		last = max(last, throw_up_swing.get(p, 0.0))
	if throw_up_t >= last or ball_z < 0.8:
		_resolve_throw_up()


func _toss_throw_up() -> void:
	throw_up_tossed = true
	ball_vz = THROW_UP_TOSS
	var a := 0.5 * GRAVITY
	var c := Body.OVERHEAD - ball_z
	throw_up_ideal = (THROW_UP_TOSS + sqrt(THROW_UP_TOSS * THROW_UP_TOSS - 4.0 * a * c)) / (2.0 * a)
	for p in throw_up_pair:
		# Better ball players read the drop better.
		var sigma: float = lerp(0.16, 0.05, p.r("control") / 100.0) - _skill_mod(p.team) * 0.3
		throw_up_swing[p] = throw_up_ideal + randfn(0.0, max(sigma, 0.03))
	if human in throw_up_pair:
		_say("Throw-up: press Hit as it drops", 1.6)


func _resolve_throw_up() -> void:
	state = State.PLAY
	ball_pos = PITCH / 2.0
	for p in throw_up_pair:
		p.throw_up = false
	var errs := []
	for p in throw_up_pair:
		errs.append(abs(throw_up_swing.get(p, 99.0) - throw_up_ideal))
	if throw_up_pair.size() < 2:
		ball_vz = min(ball_vz, 0.0)
		return
	var a: Player = throw_up_pair[0]
	var b: Player = throw_up_pair[1]
	for p in throw_up_pair:
		p.touch_block = 0.3
		anim(p, "cleek")
	if errs[0] > 0.28 and errs[1] > 0.28:
		# Both swung at fresh air: it drops between them.
		ball_vz = min(ball_vz, 0.0)
		events.append({"type": "throw_up_miss"})
		return
	if abs(errs[0] - errs[1]) < 0.015:
		# Sticks together: they clash and the ball drops dead.
		ball_vel = Vector2.from_angle(randf() * TAU) * randf_range(0.5, 2.5)
		ball_vz = 0.0
		events.append({"type": "throw_up_clash"})
		return
	var w: Player = a if errs[0] < errs[1] else b
	var clean: float = clamp(1.0 - min(errs[0], errs[1]) / 0.28, 0.2, 1.0)
	var dir := Vector2(attack_dir[w.team], 0).rotated(randf_range(-1.0, 1.0))
	ball_vel = dir * lerp(4.0, 12.0, clean)
	ball_vz = randf_range(0.5, 3.5)
	last_team = w.team
	events.append({"type": "strike", "by": w, "at": ball_pos})
	events.append({"type": "throw_up_won", "team": w.team})


## True for a centre in the throw-up while their caman is raised or swinging.
func in_throw_up(p: Player) -> bool:
	return state == State.THROW_UP and p in throw_up_pair


## The player standing over a hit-out or corner, or null once it's been hit
## (or lost).
func set_piece_taker_now() -> Player:
	if set_piece != "" and carrier == set_piece_taker and set_piece_taker != null:
		return set_piece_taker
	return null


func _update_set_piece(dt: float) -> void:
	if set_piece == "":
		return
	if set_piece_taker_now() == null:
		_clear_set_piece()   # struck, or lost: back to open play
		return
	set_piece_t += dt


func _clear_set_piece() -> void:
	set_piece = ""
	set_piece_taker = null
	set_piece_t = 0.0


## The player taking a shy (lining it up or with the ball in the air), or null.
func shy_taker() -> Player:
	for p in players:
		if p.shy_toss or (p.shy_ready and carrier == p):
			return p
	return null


func _fresh_air(p: Player, keeps_ball: bool, shy: bool = false) -> void:
	p.overswing = 0.0
	p.touch_block = 0.2
	events.append({"type": "hit", "team": p.team, "kind": "fresh_air", "curve": 0.0, "shy": shy})
	if shy:
		if p.shy_attempts < SHY_ATTEMPTS:
			# Catch it and go again.
			_take_control(p)
			p.shy_ready = true
			p.think = 0.8
			protected_timer = 1.0
			_say("Missed the shy: attempt %d of %d" % [p.shy_attempts + 1, SHY_ATTEMPTS], 1.2)
		else:
			_restart(1 - p.team, p.pos, "Shy")
		return
	if p == human:
		_say("Fresh air!", 1.0)
	if keeps_ball:
		return   # swung over the top of it; it's still at your feet
	if carrier == null and ball_z > 1.0 and ball_vz > 0.0:
		ball_vz = 0.0


func _take_control(p: Player) -> void:
	carrier = p
	last_team = p.team
	ball_z = 0.0
	ball_vz = 0.0
	gather_keeper = null
	p.think = _reaction(p.team) + (0.6 if p.is_keeper() else 0.0)
	# The computer distributes for your keeper; you take over whoever else wins it.
	if p.team == human_side and not p.is_keeper():
		human = p


## A tackle is a stick check (a hockey poke): lunge the caman at the ball.
## It has to physically reach the ball, and a carrier shielding the ball with
## their body is much harder to take it from.
func _try_tackle(t: Player, o: Player) -> void:
	if t.cooldown > 0.0 or protected_timer > 0.0 or carrier != o or t.stagger > 0.0:
		return
	t.swing = 0.25
	t.lunge = 0.35
	anim(t, "poke")
	var d := t.pos.distance_to(ball_pos)
	if d > Body.max_reach(t):
		t.cooldown = 0.35
		return
	var chance: float = clamp(0.4 + (t.r("tackling") - o.r("control")) / 100.0 * 0.8 + _skill_mod(t.team) - _skill_mod(o.team), 0.12, 0.85)
	var shielded := _dist_to_segment(o.pos, t.pos, ball_pos) < Body.BODY_R * 1.2
	if shielded:
		chance *= 0.45   # the ball is on the far side of the carrier's body
	chance *= lerp(1.0, 0.6, clamp((d - 1.2) / 1.0, 0.0, 1.0))
	var won := randf() < chance
	events.append({"type": "tackle", "by": t, "on": o, "won": won, "at": o.pos})
	if not won and shielded and randf() < 0.06:
		# Reaching through the carrier's body for the ball: caman on the man.
		events.append({"type": "foul", "kind": "hack", "by": t, "on": o, "at": o.pos, "severity": 0.3})
	if won:
		carrier = null
		o.touch_block = 0.5
		o.cooldown = 0.4
		o.swing_t = -1.0
		last_team = t.team
		# The ball never jumps between sticks: the poke knocks it loose and it
		# rolls. Usually the tackler hooks it back towards their own caman to
		# collect; sometimes it's poked away into space.
		if randf() < 0.6:
			var to_stick := Vector2(t.stick.x, t.stick.y) - ball_pos
			ball_vel = to_stick.normalized() * clamp(to_stick.length() * 3.0, 2.0, 5.0) + t.vel * 0.5
			t.touch_block = 0.0
		else:
			ball_vel = (ball_pos - t.pos).normalized().rotated(randf_range(-0.7, 0.7)) * randf_range(4.0, 8.0)
		ball_vz = 0.0
	else:
		t.cooldown = 0.7


## The carrier has been knocked off the ball: it squirts away.
func spill(p: Player, by: Player) -> void:
	if carrier != p:
		return
	carrier = null
	p.touch_block = 0.5
	var push := (p.pos - by.pos).normalized() if p.pos.distance_to(by.pos) > 0.01 else p.facing
	ball_vel = p.vel * 0.6 + push.rotated(randf_range(-0.8, 0.8)) * randf_range(2.0, 5.0)
	ball_vz = randf_range(0.0, 1.5)
	last_team = by.team
	events.append({"type": "spill", "team": p.team})


## Tell the view to play a one-off animation on this player.
func anim(p: Player, name: String, power: float = 1.0, from_charge: float = 0.0) -> void:
	p.anim = {"name": name, "power": power, "charge": from_charge}
	p.anim_seq += 1


## The shy taker's hand brings the ball up in front and lets it go.
func _lift_shy(dt: float) -> void:
	var p := shy_lift
	shy_lift_t += dt
	var k: float = clamp(shy_lift_t / SHY_HOLD, 0.0, 1.0)
	var e := k * k * (3.0 - 2.0 * k)
	var hand := Vector3(p.pos.x + p.facing.x * SHY_ARM, p.pos.y + p.facing.y * SHY_ARM, 1.4)
	var at := shy_lift_from.lerp(hand, e)
	ball_pos = Vector2(at.x, at.y)
	ball_z = at.z
	ball_vel = Vector2.ZERO
	ball_vz = 0.0
	if k >= 1.0:
		shy_lift = null
		# The toss is never perfect: a little drift, more for poorer ball control.
		var wobble: float = lerp(0.25, 0.05, p.r("control") / 100.0)
		ball_vel = Vector2(randfn(0.0, wobble), randfn(0.0, wobble))
		ball_vz = SHY_TOSS + randfn(0.0, wobble)


func _update_ball(dt: float) -> void:
	if shy_lift != null:
		if shy_lift.shy_toss and shy_lift in players:
			_lift_shy(dt)
			return
		shy_lift = null
	if carrier != null and is_dribbling(carrier):
		_dribble(dt)
		return
	dribble_vel = Vector2.ZERO
	if carrier != null:
		# The ball rides on the carrier's caman. When a player has just
		# gathered it, it runs onto the stick rather than jumping there.
		var on_stick := Vector2(carrier.stick.x, carrier.stick.y)
		ball_pos = ball_pos.move_toward(on_stick, (carrier.vel.length() + CARRY_CATCH_UP) * dt)
		if protected_timer > 0.0 or carrier.shy_ready:
			# Lining up a restart: the ball stays in play.
			ball_pos = Vector2(clamp(ball_pos.x, 0.3, PITCH.x - 0.3), clamp(ball_pos.y, 0.3, PITCH.y - 0.3))
		ball_vel = carrier.vel
		ball_z = 0.0
		ball_vz = 0.0
		return
	var before := Vector3(ball_pos.x, ball_pos.y, ball_z)
	ball_sim.step(self, dt)
	if gather_keeper != null:
		gather_t -= dt
		if gather_t <= 0.0 and state == State.PLAY:
			_take_control(gather_keeper)
			anim(carrier, "trap")
		return
	if state == State.PLAY:
		_ball_touches(before)


## Running with the ball, the carrier plays it like a footballer: a gentle
## tap along the ground a yard or two ahead, run onto it, tap it again. The
## caman only drags the ball (it rides on the stick) when standing, lining up
## a hit or at a restart.
func is_dribbling(p: Player) -> bool:
	return p == carrier and state == State.PLAY and protected_timer <= 0.0 and p.swing_t < 0.0 \
		and not p.shy_ready and set_piece_taker_now() == null and p.stagger <= 0.0 \
		and (p.vel.length() > 1.5 or dribble_vel.length() > 0.5)


## How much help a dribbler gets: 1 for the player's own man (softer
## touches, a quicker stick when turning, harder to nick), 0 for the computer.
func dribble_assist(p: Player) -> float:
	return 1.0 if p == human else 0.0


func _dribble(dt: float) -> void:
	var c := carrier
	var spd := dribble_vel.length()
	if spd > 0.0:
		dribble_vel = dribble_vel / spd * max(0.0, spd - DRIBBLE_ROLL_DECEL * dt)
	ball_pos += dribble_vel * dt
	ball_vel = dribble_vel
	ball_z = 0.0
	ball_vz = 0.0
	var want: Vector2 = c.desired if c.desired.length() > 0.5 else c.facing
	var dir := want.normalized()
	var run: float = max(c.vel.dot(dir), 0.0)
	var head := Vector2(c.stick.x, c.stick.y)
	var assist := dribble_assist(c)
	# Turning with the ball: the player gets the caman round to it sooner.
	var turning: bool = dribble_vel.length() > 0.5 and dribble_vel.normalized().dot(dir) < 0.75
	var tap_r: float = Body.CONTACT_R + 0.12 + (0.25 if turning else 0.1) * assist
	if head.distance_to(ball_pos) < tap_r and dribble_vel.dot(dir) < run + 0.5:
		# The tap: just firm enough to roll ahead of the player; better ball
		# players keep it closer, and the player's touches are softer still.
		var soft: float = lerp(1.45, 1.2, c.r("control") / 100.0)
		soft = lerp(soft, 1.08, assist)
		dribble_vel = dir * max(run * soft + lerp(1.0, 0.6, assist), 2.5)
		dribble_taps += 1
		return
	if assist > 0.0 and dribble_vel.length() > 0.3:
		# The player shepherds a rolling touch round with them as they turn.
		var bend: float = dribble_vel.angle_to(dir)
		dribble_vel = dribble_vel.rotated(clampf(bend, -3.0 * dt, 3.0 * dt))
	var overrun: bool = (ball_pos - head).dot(dir) < -0.1
	if assist > 0.0 and head.distance_to(ball_pos) < 1.8 \
			and (overrun or (dribble_vel.length() > 0.5 and dribble_vel.normalized().dot(dir) < 0.3)):
		# A sharp turn, or running past it: the player hooks the ball back
		# round with the caman rather than letting it run away.
		ball_pos = ball_pos.move_toward(head, (c.vel.length() + CARRY_CATCH_UP) * dt)
		dribble_vel = dribble_vel.move_toward(c.vel, 30.0 * dt)
		ball_vel = dribble_vel
		return
	var loose: bool = head.distance_to(ball_pos) > 0.8
	if loose:
		# Between touches the ball is there to be nicked by an opponent's caman.
		for o in squads[1 - c.team]:
			if o.touch_block > 0.0 or o.stagger > 0.0:
				continue
			if Vector2(o.stick.x, o.stick.y).distance_to(ball_pos) >= Body.CONTACT_R:
				continue
			if randf() > (0.25 + (o.r("tackling") - c.r("control")) / 250.0) * (1.0 - 0.5 * assist):
				o.touch_block = 0.5   # got a touch on it but the carrier kept it
				continue
			carrier = null
			c.touch_block = 0.3
			events.append({"type": "touch", "by": o, "at": ball_pos, "hands": false})
			events.append({"type": "nicked", "team": o.team})
			_take_control(o)
			anim(o, "trap")
			return
	if ball_pos.distance_to(c.pos) > DRIBBLE_LOSE + 0.5 * assist:
		# Overran it or turned away: it's a loose ball now.
		carrier = null
		c.touch_block = 0.15
		events.append({"type": "lost_touch", "team": c.team})


## Who gets to the ball this step. Outfield players touch it only with the
## caman head; it can also hit a body and deflect. Keepers in their area can
## stop it with stick, hands or body.
func _ball_touches(before: Vector3) -> void:
	var now := Vector3(ball_pos.x, ball_pos.y, ball_z)
	var sp := ball_vel.length()
	var best: Player = null
	var best_d := INF
	var best_keeper := false
	var blocker: Player = null
	for p in players:
		if p.touch_block > 0.0 or p.stagger > 0.0:
			continue
		var keeping: bool = p.is_keeper() and p.pos.distance_to(own_goal(p.team)) < 14.0
		var d: float = Body.path_distance(p.stick, before, now)
		var reach := Body.CONTACT_R
		if keeping:
			# Hands and body: anywhere within the keeper's reach and height.
			var body_d: float = Body.path_distance(Vector3(p.pos.x, p.pos.y, 0.0), Vector3(before.x, before.y, 0.0), Vector3(now.x, now.y, 0.0))
			var hands: float = 0.75 + p.r("keeping") / 100.0 * 0.45 + (0.8 if p.lunge > 0.0 else 0.0)
			if body_d < hands and min(before.z, now.z) < KEEPER_REACH_HEIGHT:
				d = min(d, body_d * Body.CONTACT_R / hands)
		if d < reach and d < best_d:
			best = p
			best_d = d
			best_keeper = keeping
		elif blocker == null and min(before.z, now.z) < Body.BODY_HEIGHT and p.team != last_team:
			var bd: float = Body.path_distance(Vector3(p.pos.x, p.pos.y, now.z), before, now)
			if bd < Body.BODY_BLOCK_R:
				blocker = p
	if best == null:
		if blocker != null and sp > 4.0:
			# Off the legs or body: it loses most of its pace and kicks off sideways.
			var n := (ball_pos - blocker.pos).normalized()
			ball_vel = (ball_vel * 0.25).bounce(n) if ball_vel.dot(n) < 0.0 else ball_vel * 0.4
			ball_vel = ball_vel.rotated(randf_range(-0.6, 0.6))
			ball_vz = max(0.0, ball_vz * 0.3)
			blocker.touch_block = 0.3
			last_team = blocker.team
			events.append({"type": "block", "team": blocker.team})
		return
	var p := best
	p.touch_block = 0.25
	events.append({"type": "touch", "by": p, "at": ball_pos, "hands": best_keeper and p.pos.distance_to(ball_pos) > Body.CONTACT_R})
	# One-handed at full stretch you can stop or tap a ball, rarely control it.
	var grip: float = 0.55 if p.one_hand and not best_keeper else 1.0
	if sp < (8.0 + p.r("control") * 0.08) * grip and not best_keeper:
		_take_control(p)
		anim(p, "trap")
		return
	if p.one_hand and not best_keeper and randf() < 0.5:
		# A one-handed block: the stick kills the ball's pace where it is.
		ball_vel = ball_vel.rotated(randf_range(-0.5, 0.5)) * 0.15
		ball_vz = 0.0
		last_team = p.team
		events.append({"type": "one_hand_block", "team": p.team})
		return
	var stretch: float = clamp((p.pos.distance_to(ball_pos) - 1.0) / 1.2, 0.0, 1.0)
	var chance: float
	if best_keeper:
		chance = clamp(0.36 + p.r("keeping") / 100.0 * 0.5 - (sp - 20.0) * 0.012 - stretch * 0.3 + _skill_mod(p.team), 0.2, 0.95)
	else:
		chance = clamp(p.r("control") / 100.0 * (18.0 / sp) * lerp(1.0, 0.7, stretch) * grip + _skill_mod(p.team), 0.05, 0.9)
		if p.team == last_team:
			chance += 0.15
	if randf() < chance:
		if best_keeper:
			_keeper_save(p)
		else:
			_take_control(p)
			anim(p, "trap")
	elif best_keeper and randf() < 0.5:
		# Fingertips: a touch that takes the pace off but doesn't stop it.
		ball_vel = ball_vel.rotated(randf_range(-0.3, 0.3)) * 0.7
		last_team = p.team
	elif not best_keeper and randf() < 0.4:
		ball_vel = ball_vel.rotated(randf_range(-1.2, 1.2)) * 0.5
		ball_vz = max(ball_vz, randf_range(0.0, 2.0))
		last_team = p.team


## A save: the keeper smothers it with stick, hand or body and the ball drops
## dead at their feet, then they gather it. No rebounds.
func _keeper_save(k: Player) -> void:
	# The caman (or glove) is where the ball is stopped, not a yard short of it.
	var flat := ball_pos - k.pos
	var reach: float = Body.max_reach(k)
	var at := k.pos + flat.limit_length(reach)
	ball_pos = at
	k.stick = Vector3(at.x, at.y, min(ball_z, KEEPER_REACH_HEIGHT))
	if k.lunge <= 0.0:
		anim(k, "trap")
	var to_k := k.pos - ball_pos
	ball_vel = to_k.normalized() * min(to_k.length(), 1.5) + ball_vel.normalized() * 0.3
	ball_vz = min(ball_vz, 0.0)
	ball_sim.set_spin(Vector3.ZERO)
	last_team = k.team
	k.swing = 0.3
	k.save_point = null
	gather_keeper = k
	gather_t = 0.35
	for o in players:
		if o != k:
			o.touch_block = max(o.touch_block, gather_t + 0.1)
	events.append({"type": "save", "team": k.team, "by": k})
	_say("Save!", 1.0)


func _check_ball_out() -> void:
	if ball_pos.x < 0.0 or ball_pos.x > PITCH.x:
		var end_x := 0.0 if ball_pos.x < 0.0 else PITCH.x
		var defending := 0 if own_goal(0).x == end_x else 1
		if abs(ball_pos.y - PITCH.y / 2.0) < GOAL_W / 2.0 and ball_z < CROSSBAR:
			if referee.goal_stands(1 - defending):
				_goal(1 - defending)
			else:
				_restart(defending, Vector2(abs(end_x - D_RADIUS), PITCH.y / 2.0), "Hit-out")
				_say("No goal: a free hit can't go straight in", 2.0)
		elif last_team == defending:
			var cy := 0.0 if ball_pos.y < PITCH.y / 2.0 else PITCH.y
			_restart(1 - defending, Vector2(abs(end_x - 1.0), abs(cy - 1.0)), "Corner")
		else:
			# Goal hit from the edge of the D.
			var gx: float = abs(end_x - D_RADIUS)
			_restart(defending, Vector2(gx, PITCH.y / 2.0 + randf_range(-4.0, 4.0)), "Hit-out")
	elif ball_pos.y < 0.0 or ball_pos.y > PITCH.y:
		# The shy is taken from the touchline where it went out.
		var spot := Vector2(clamp(ball_pos.x, 1.0, PITCH.x - 1.0), 0.0 if ball_pos.y < 0.0 else PITCH.y)
		_restart(1 - last_team if last_team >= 0 else 0, spot, "Shy")


func _restart(team: int, spot: Vector2, label: String) -> void:
	var taker := _nearest_outfield(team, spot, null)
	var toward := (Vector2(PITCH.x / 2.0, PITCH.y / 2.0) - spot).normalized()
	if label == "Hit-out":
		toward = Vector2(attack_dir[team], 0)
	for p in players:
		p.swing_t = -1.0
		p.shy_ready = false
		p.shy_toss = false
	if label == "Shy":
		# Toes just behind the line, facing straight in.
		var inward := Vector2(0, 1) if spot.y < PITCH.y / 2.0 else Vector2(0, -1)
		toward = inward
		taker.pos = spot - inward * 0.2
		spot += inward * 0.35
	else:
		taker.pos = spot - toward * (PLAYER_R + 0.55)
		taker.pos = Vector2(clamp(taker.pos.x, 1.5, PITCH.x - 1.5), clamp(taker.pos.y, 1.5, PITCH.y - 1.5))
	taker.vel = Vector2.ZERO
	taker.facing = toward
	taker.stagger = 0.0
	taker.stick = Body.rest_spot(taker)
	restart_base = toward
	restart_aim = 0.0
	# The ball is placed on the spot, not left where it went out.
	ball_pos = spot
	ball_vel = Vector2.ZERO
	ball_vz = 0.0
	_take_control(taker)
	# A shy is thrown up and struck overhead (see _throw_up_shy).
	taker.shy_ready = label == "Shy"
	taker.shy_attempts = 0
	taker.think = 0.9 if label != "Shy" else 1.8   # a shy: let everyone get to their spots
	protected_timer = 1.5
	_clear_set_piece()
	if label == "Hit-out" or label == "Corner":
		# Play stops: the taker stands over the ball, everyone else takes up
		# their positions and the camera comes round behind the taker.
		set_piece = label
		set_piece_taker = taker
		# A corner takes longer: everyone has to get up to the D.
		var pause: float = SET_PIECE_PAUSE + (1.0 if label == "Corner" else 0.0)
		taker.think = pause
		protected_timer = pause
		charge = -1.0
	_say(label, 1.2 if set_piece == "" else protected_timer)
	events.append({"type": label, "team": team, "taker": taker})


# ---------------------------------------------------------------- referee hooks

## A free hit where a foul happened. Opponents are held 5 yards off while the
## taker lines up. Free hits are indirect: the referee disallows a goal
## straight from one.
func award_free_hit(team: int, spot: Vector2, text: String) -> void:
	spot = Vector2(clamp(spot.x, 1.0, PITCH.x - 1.0), clamp(spot.y, 1.0, PITCH.y - 1.0))
	var taker := _nearest_outfield(team, spot, null)
	if taker == null:
		return
	var toward := (target_goal(team) - spot).normalized()
	penalty_taker = null
	_place_taker(taker, spot, toward)
	_say(text, 2.2)
	events.append({"type": "Free hit", "team": team, "taker": taker})


## A penalty hit, 20 yards straight out from the goal. Everyone but the taker
## and the keeper goes back behind the ball.
func award_penalty(team: int, text: String) -> void:
	var goal := target_goal(team)
	var spot := goal - Vector2(attack_dir[team] * PENALTY_SPOT, 0)
	var taker: Player = null
	for p in squads[team]:
		if not p.is_keeper() and (taker == null or p.r("shooting") > taker.r("shooting")):
			taker = p
	if taker == null:
		return
	var keeper := _keeper_of(1 - team)
	for p in players:
		if p == taker or p == keeper:
			continue
		var ahead: float = (p.pos.x - spot.x) * attack_dir[team]
		if ahead > -FREE_HIT_BACK:
			p.pos.x = spot.x - attack_dir[team] * (FREE_HIT_BACK + randf() * 4.0)
			p.vel = Vector2.ZERO
	if keeper != null:
		keeper.pos = Vector2(goal.x - attack_dir[team] * 0.8, goal.y)
		keeper.vel = Vector2.ZERO
	_place_taker(taker, spot, (goal - spot).normalized())
	penalty_taker = taker
	_say(text, 2.2)
	events.append({"type": "Penalty hit", "team": team, "taker": taker})


func _place_taker(taker: Player, spot: Vector2, toward: Vector2) -> void:
	# The whistle stops everything: swings in progress and any shy being taken.
	for p in players:
		p.swing_t = -1.0
		p.shy_ready = false
		p.shy_toss = false
	taker.pos = spot - toward * (PLAYER_R + 0.55)
	taker.vel = Vector2.ZERO
	taker.facing = toward
	ball_pos = spot
	ball_z = 0.0
	ball_vel = Vector2.ZERO
	ball_vz = 0.0
	charge = -1.0
	_clear_set_piece()
	_take_control(taker)
	taker.think = 1.8
	protected_timer = 2.0


## The computer strikes its penalty hits at goal once players have stood back.
func _take_penalty() -> void:
	if penalty_taker == null:
		return
	if carrier != penalty_taker:
		penalty_taker = null
	elif penalty_taker != human and protected_timer <= 0.2:
		_ai_shoot(penalty_taker)


## Sent off by the referee: the team plays on a player short.
func send_off(p: Player) -> void:
	squads[p.team].erase(p)
	players.erase(p)
	if carrier == p:
		carrier = null
	if penalty_taker == p:
		penalty_taker = null
	if human == p:
		human = _nearest_outfield(human_side, ball_pos, null)


func _goal(team: int) -> void:
	score[team] += 1
	state = State.GOAL
	state_timer = GOAL_PAUSE
	carrier = null
	gather_keeper = null
	_clear_set_piece()
	ball_vel *= 0.15
	ball_vz = 0.0
	charge = -1.0
	_say("GOAL!  %s" % teams[team]["name"], GOAL_PAUSE)
	events.append({"type": "goal", "team": team, "half": half, "clock": clock})


func match_minute() -> int:
	return int(clock / half_seconds * 45.0) + (45 if half == 2 else 0)
