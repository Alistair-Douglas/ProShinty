extends Node3D
## One shinty match: pitch, two 12-a-side teams, ball physics and computer AI.
## The simulation runs on a flat 2D pitch in yards (x along the pitch, y across,
## ball_z is height). MatchView draws it in 3D and Hud draws the scoreboard.
## Set `config` before adding to the tree (or leave empty to read from Game).

const TeamData := preload("res://scripts/team_data.gd")
const MatchView := preload("res://scripts/match_view.gd")
const Hud := preload("res://scripts/hud.gd")
const Body := preload("res://scripts/player_physics.gd")
const Counters := preload("res://scripts/swing_counters.gd")

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
const OVERSWING_MAX := 1.35  # hit meter past full power
const SHY_TOSS := 6.5        # yd/s: how hard a shy is thrown up
const SHY_ARM := 0.8         # the shy is tossed an arm's length in front
const SHY_ATTEMPTS := 3      # tries at a clean strike before the shy goes over

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
var colors := [[Color.RED, Color.WHITE], [Color.BLUE, Color.YELLOW]]
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
var gather_keeper: Player = null   # a saved ball dropping to the keeper
var foul_pending = null            # [offender, fouled] seen by the referee
var gather_t := 0.0



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
	human_side = int(config.get("human_side", 0))
	difficulty = int(config.get("difficulty", 1))
	half_seconds = float(config.get("half_seconds", 180.0))
	if config.has("seed"):
		seed(int(config["seed"]))
	for t in 2:
		var c: Dictionary = teams[t].get("colors", {})
		colors[t] = [Color.from_string(c.get("primary", "#cc2222"), Color.RED),
			Color.from_string(c.get("secondary", "#ffffff"), Color.WHITE)]
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
	# Clash check: if both teams wear similar colours, the away side switches.
	if _color_close(colors[0][0], colors[1][0]):
		colors[1] = [colors[1][1], colors[1][0]]
	_start_throw_up()
	if human_side >= 0:
		human = _nearest_outfield(human_side, ball_pos, null)


func _color_close(a: Color, b: Color) -> bool:
	return abs(a.r - b.r) + abs(a.g - b.g) + abs(a.b - b.b) < 0.35


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
	match state:
		State.THROW_UP:
			state_timer -= dt
			_update_players(dt)
			if state_timer <= 0.0:
				ball_vz = 9.0
				state = State.PLAY
		State.PLAY:
			clock += dt
			_update_players(dt)
			_update_ball(dt)
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
	ball_z = 0.6
	ball_vel = Vector2.ZERO
	ball_vz = 0.0
	protected_timer = 0.0
	for p in players:
		var f: Vector2 = p.home
		if p.position_code == "LM":
			f = Vector2(0.485, 0.5)
		elif not p.is_keeper():
			f.x = min(f.x * 0.55, 0.44)
		p.pos = frac_to_world(p.team, f)
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
	var f: Vector2 = p.home
	if not p.is_keeper():
		var bx := own_frac(p.team, ball_pos.x)
		f.x = clamp(f.x + (bx - 0.5) * 0.5, 0.05, 0.94)
		f.y = clamp(f.y + (ball_pos.y / PITCH.y - 0.5) * 0.3, 0.06, 0.94)
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
	if (protected_timer > 0.0 and carrier != null) or (guarded != null and guarded.shy_toss):
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
			var h := home_world(p)
			_steer_to(p, h, h.distance_to(p.pos) > 12.0)


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
		var d: float = p.pos.distance_to(m.pos)
		if d < 6.0 or d > 50.0:
			continue
		var fwd: float = (m.pos.x - p.pos.x) * attack_dir[p.team]
		if forward_only and fwd < 4.0:
			continue
		var open_space: float = min(_nearest_opponent_dist(m), 10.0)
		var lane: float = min(_lane_clearance(p.team, p.pos, m.pos), 5.0)
		var s: float = fwd * 0.5 + open_space * 1.5 + lane * 2.0 - d * 0.15
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
	var mv := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var sprint := Input.is_action_pressed("sprint") and p.stamina > 0.05
	if mv.length() > 0.15:
		p.desired = mv.normalized() * p.top_speed() * (1.0 if sprint else 0.78)
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
	ball_pos = p.pos + p.facing * SHY_ARM
	ball_z = 1.4
	# The toss is never perfect: a little drift, more for poorer ball control.
	var wobble: float = lerp(0.25, 0.05, p.r("control") / 100.0)
	ball_vel = Vector2(randfn(0.0, wobble), randfn(0.0, wobble))
	ball_vz = SHY_TOSS + randfn(0.0, wobble)
	# Strike when it comes back down to where the caman meets it overhead.
	var a := 0.5 * GRAVITY
	var c := Body.OVERHEAD - ball_z
	p.swing_t = (SHY_TOSS + sqrt(SHY_TOSS * SHY_TOSS - 4.0 * a * c)) / (2.0 * a)
	# High and long, whatever the taker was going to do with it.
	var req: Dictionary = p.swing_req
	req["speed"] = max(req["speed"], 22.0)
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
		diff += 0.1
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
	if p == human or (p.team == human_side and shy):
		var note := {"thin": "Topped it", "fat": "Skied it", "heel": "Off the heel", "toe": "Off the toe"}
		if note.has(res["kind"]):
			_say(note[res["kind"]], 1.0)
		elif abs(res["curve"]) > 5.0 and req["speed"] > 22.0:
			_say("Bending it " + ("left" if res["curve"] > 0.0 else "right"), 1.0)


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
	if _dist_to_segment(o.pos, t.pos, ball_pos) < Body.BODY_R * 1.2:
		chance *= 0.45   # the ball is on the far side of the carrier's body
	chance *= lerp(1.0, 0.6, clamp((d - 1.2) / 1.0, 0.0, 1.0))
	if randf() < chance:
		carrier = null
		o.touch_block = 0.5
		o.cooldown = 0.4
		o.swing_t = -1.0
		if randf() < 0.6:
			_take_control(t)
		else:
			# Poked away from the tackler.
			ball_vel = (ball_pos - t.pos).normalized().rotated(randf_range(-0.7, 0.7)) * randf_range(4.0, 8.0)
			last_team = t.team
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


func _update_ball(dt: float) -> void:
	if carrier != null:
		# The ball rides on the carrier's caman.
		ball_pos = Vector2(carrier.stick.x, carrier.stick.y)
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
			var hands: float = 0.9 + p.r("keeping") / 100.0 * 0.5 + (0.9 if p.lunge > 0.0 else 0.0)
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
	events.append({"type": "save", "team": k.team})
	_say("Save!", 1.0)


func _check_ball_out() -> void:
	if ball_pos.x < 0.0 or ball_pos.x > PITCH.x:
		var end_x := 0.0 if ball_pos.x < 0.0 else PITCH.x
		var defending := 0 if own_goal(0).x == end_x else 1
		if abs(ball_pos.y - PITCH.y / 2.0) < GOAL_W / 2.0 and ball_z < CROSSBAR:
			_goal(1 - defending)
		elif last_team == defending:
			var cy := 0.0 if ball_pos.y < PITCH.y / 2.0 else PITCH.y
			_restart(1 - defending, Vector2(abs(end_x - 1.0), abs(cy - 1.0)), "Corner")
		else:
			var gx: float = abs(end_x - 4.0)
			_restart(defending, Vector2(gx, PITCH.y / 2.0 + randf_range(-6.0, 6.0)), "Hit-out")
	elif ball_pos.y < 0.0 or ball_pos.y > PITCH.y:
		var spot := Vector2(clamp(ball_pos.x, 1.0, PITCH.x - 1.0), clamp(ball_pos.y, 0.5, PITCH.y - 0.5))
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
	taker.pos = spot - toward * (PLAYER_R + 0.55)
	taker.pos = Vector2(clamp(taker.pos.x, 1.5, PITCH.x - 1.5), clamp(taker.pos.y, 1.5, PITCH.y - 1.5))
	taker.vel = Vector2.ZERO
	taker.facing = toward
	taker.stagger = 0.0
	taker.stick = Body.rest_spot(taker)
	ball_vel = Vector2.ZERO
	ball_vz = 0.0
	_take_control(taker)
	# A shy is thrown up and struck overhead (see _throw_up_shy).
	taker.shy_ready = label == "Shy"
	taker.shy_attempts = 0
	taker.think = 0.9
	protected_timer = 1.5
	_say(label, 1.2)
	events.append({"type": label, "team": team})


func _goal(team: int) -> void:
	score[team] += 1
	state = State.GOAL
	state_timer = GOAL_PAUSE
	carrier = null
	gather_keeper = null
	ball_vel *= 0.15
	ball_vz = 0.0
	charge = -1.0
	_say("GOAL!  %s" % teams[team]["name"], GOAL_PAUSE)
	events.append({"type": "goal", "team": team, "half": half, "clock": clock})


func match_minute() -> int:
	return int(clock / half_seconds * 45.0) + (45 if half == 2 else 0)
