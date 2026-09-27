extends Node3D
## One shinty match: pitch, two 12-a-side teams, ball physics and computer AI.
## The simulation runs on a flat 2D pitch in yards (x along the pitch, y across,
## ball_z is height). MatchView draws it in 3D and Hud draws the scoreboard.
## Set `config` before adding to the tree (or leave empty to read from Game).

const TeamData := preload("res://scripts/team_data.gd")
const MatchView := preload("res://scripts/match_view.gd")
const Hud := preload("res://scripts/hud.gd")
const Referee := preload("res://scripts/referee.gd")

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
var referee := Referee.new()
var penalty_taker: Player = null



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
			squads[t].append(p)
			players.append(p)
	# Clash check: if both teams wear similar colours, the away side switches.
	if _color_close(colors[0][0], colors[1][0]):
		colors[1] = [colors[1][1], colors[1][0]]
	referee.setup(self)
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
	if state != State.PLAY and state != State.FULL_TIME:
		referee.step(dt)
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
		_move(p, dt)
	_separate()
	if protected_timer > 0.0 and carrier != null:
		for o in squads[1 - carrier.team]:
			var off: Vector2 = o.pos - carrier.pos
			if off.length() < 5.0:
				o.pos = carrier.pos + off.normalized() * 5.0 if off.length() > 0.01 else carrier.pos + Vector2(0, 5)


func _move(p: Player, dt: float) -> void:
	var speed: float = p.top_speed() * lerp(0.8, 1.0, p.stamina)
	var want := p.desired
	if want.length() > speed:
		want = want.normalized() * speed
	if p == carrier:
		want = want.limit_length(speed * 0.88)
	p.vel = p.vel.move_toward(want, 30.0 * dt)
	p.pos += p.vel * dt
	p.pos.x = clamp(p.pos.x, -2.0, PITCH.x + 2.0)
	p.pos.y = clamp(p.pos.y, -2.0, PITCH.y + 2.0)
	if p.desired.length() > 0.3:
		p.facing = p.desired.normalized()
	if p.sprinting and p.vel.length() > 3.0:
		p.stamina = max(0.0, p.stamina - dt * 0.06 * (1.5 - p.r("stamina") / 100.0))
	else:
		p.stamina = min(1.0, p.stamina + dt * 0.04)


func _separate() -> void:
	var n := players.size()
	for i in n:
		var a: Player = players[i]
		for j in range(i + 1, n):
			var b: Player = players[j]
			var off := b.pos - a.pos
			var d := off.length()
			if d < PLAYER_R * 2.0 and d > 0.001:
				var push := off / d * (PLAYER_R * 2.0 - d) * 0.5
				a.pos -= push
				b.pos += push


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
		p.think -= dt
		if p.think <= 0.0 and p.pos.distance_to(carrier.pos) < REACH + 0.5:
			p.think = _reaction(p.team)
			_try_tackle(p, carrier)


func _ai_carrier(p: Player, dt: float) -> void:
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
		if carrier != null and carrier.team != p.team and p.pos.distance_to(carrier.pos) < REACH + 0.8:
			_try_tackle(p, carrier)
		else:
			charge = 0.0
	if charge >= 0.0:
		charge = min(1.0, charge + dt * 1.3)
		if not Input.is_action_pressed("shoot"):
			if carrier == p or _ball_in_reach(p):
				_human_shoot(p, aim, charge)
			else:
				p.swing = 0.25
			charge = -1.0
	if Input.is_action_just_pressed("pass"):
		if carrier == p or _ball_in_reach(p):
			_human_pass(p, aim)
		elif carrier != null and carrier.team != p.team and p.pos.distance_to(carrier.pos) < REACH + 0.8:
			_try_tackle(p, carrier)


func _ball_in_reach(p: Player) -> bool:
	return carrier == null and p.touch_block <= 0.0 and ball_z < REACH_HEIGHT and p.pos.distance_to(ball_pos) < REACH + 0.4


func _human_shoot(p: Player, aim: Vector2, power: float) -> void:
	var goal := target_goal(p.team)
	var to_goal := goal - p.pos
	var loft := power * 7.0
	if to_goal.length() < 45.0 and abs(aim.angle_to(to_goal)) < deg_to_rad(40.0):
		# Aim assist: pull the shot towards the hail, placement follows the stick.
		var spot := goal + Vector2(0, clamp(aim.y * 6.0, -1.0, 1.0) * (GOAL_W / 2.0 - 0.5))
		aim = (spot - p.pos).normalized()
		loft = 0.5 + power * 3.0
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


func _strike_speed(p: Player, dir: Vector2, speed: float, loft: float, skill_key: String, power: float = 0.5) -> void:
	carrier = null
	ball_pos = p.pos + dir.normalized() * (PLAYER_R + 0.6)
	var res := ShintyMatchAdapter.strike_like_match(p.data, dir, speed, loft, skill_key, ball_vel, ball_vz, _skill_mod(p.team))
	ball_vel = res["ball_vel"]
	ball_vz = res["ball_vz"]
	ball_sim.set_spin(res["spin"])
	ball_z = max(ball_z, 0.2)
	dir = ball_vel.normalized() if ball_vel.length() > 0.1 else dir
	p.touch_block = 0.35
	p.swing = 0.3
	p.facing = dir
	last_team = p.team
	if p == penalty_taker:
		penalty_taker = null
	events.append({"type": "strike", "by": p, "at": ball_pos})


func _take_control(p: Player) -> void:
	carrier = p
	last_team = p.team
	ball_z = 0.0
	ball_vz = 0.0
	p.think = _reaction(p.team) + (0.6 if p.is_keeper() else 0.0)
	# The computer distributes for your keeper; you take over whoever else wins it.
	if p.team == human_side and not p.is_keeper():
		human = p


func _try_tackle(t: Player, o: Player) -> void:
	if t.cooldown > 0.0 or protected_timer > 0.0 or carrier != o:
		return
	t.swing = 0.25
	if t.pos.distance_to(o.pos) > REACH + 0.6:
		t.cooldown = 0.35
		return
	var chance: float = clamp(0.4 + (t.r("tackling") - o.r("control")) / 100.0 * 0.8 + _skill_mod(t.team) - _skill_mod(o.team), 0.12, 0.85)
	var won := randf() < chance
	events.append({"type": "tackle", "by": t, "on": o, "won": won, "at": o.pos})
	if won:
		carrier = null
		o.touch_block = 0.5
		o.cooldown = 0.4
		if randf() < 0.6:
			_take_control(t)
		else:
			ball_vel = Vector2.from_angle(randf() * TAU) * randf_range(4.0, 8.0)
			last_team = t.team
	else:
		t.cooldown = 0.7


func _update_ball(dt: float) -> void:
	if carrier != null:
		ball_pos = carrier.pos + carrier.facing * (PLAYER_R + 0.55)
		ball_vel = carrier.vel
		ball_z = 0.0
		ball_vz = 0.0
		return
	ball_sim.step(self, dt)
	if state == State.PLAY:
		_ball_touches()


func _ball_touches() -> void:
	var sp := ball_vel.length()
	var best: Player = null
	var best_d := INF
	var best_keeper := false
	for p in players:
		if p.touch_block > 0.0:
			continue
		var reach := REACH
		var h := REACH_HEIGHT
		var keeping: bool = p.is_keeper() and p.pos.distance_to(own_goal(p.team)) < 14.0
		if keeping:
			reach = 1.7 + p.r("keeping") / 100.0 * 1.4
			h = KEEPER_REACH_HEIGHT
		if ball_z > h:
			continue
		var d: float = p.pos.distance_to(ball_pos)
		if d < reach and d < best_d:
			best = p
			best_d = d
			best_keeper = keeping
	if best == null:
		return
	var p := best
	p.touch_block = 0.25
	events.append({"type": "touch", "by": p, "at": ball_pos, "hands": best_keeper})
	if sp < 8.0 + p.r("control") * 0.08:
		_take_control(p)
		return
	var chance: float
	if best_keeper:
		chance = clamp(0.45 + p.r("keeping") / 100.0 * 0.55 - (sp - 20.0) * 0.012 + _skill_mod(p.team), 0.25, 0.97)
	else:
		chance = clamp(p.r("control") / 100.0 * (18.0 / sp) + _skill_mod(p.team), 0.05, 0.9)
		if p.team == last_team:
			chance += 0.15
	if randf() < chance:
		if best_keeper and sp > 16.0:
			# Parry: knock it back out and away from goal.
			ball_vel = Vector2(-ball_vel.x * 0.3, ball_vel.y * 0.3 + randf_range(-8.0, 8.0))
			ball_vz = randf_range(1.0, 4.0)
			last_team = p.team
			p.swing = 0.3
			p.touch_block = 0.4
			events.append({"type": "save", "team": p.team, "by": p})
		else:
			_take_control(p)
	elif randf() < 0.4:
		ball_vel = ball_vel.rotated(randf_range(-1.2, 1.2)) * 0.5
		ball_vz = max(ball_vz, randf_range(0.0, 2.0))
		last_team = p.team


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
		var spot := Vector2(clamp(ball_pos.x, 1.0, PITCH.x - 1.0), clamp(ball_pos.y, 0.5, PITCH.y - 0.5))
		_restart(1 - last_team if last_team >= 0 else 0, spot, "Shy")


func _restart(team: int, spot: Vector2, label: String) -> void:
	var taker := _nearest_outfield(team, spot, null)
	var toward := (Vector2(PITCH.x / 2.0, PITCH.y / 2.0) - spot).normalized()
	if label == "Hit-out":
		toward = Vector2(attack_dir[team], 0)
	taker.pos = spot - toward * (PLAYER_R + 0.55)
	taker.vel = Vector2.ZERO
	taker.facing = toward
	ball_vel = Vector2.ZERO
	ball_vz = 0.0
	_take_control(taker)
	taker.think = 0.9
	protected_timer = 1.5
	_say(label, 1.2)
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
	taker.pos = spot - toward * (PLAYER_R + 0.55)
	taker.vel = Vector2.ZERO
	taker.facing = toward
	ball_pos = spot
	ball_z = 0.0
	ball_vel = Vector2.ZERO
	ball_vz = 0.0
	charge = -1.0
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
	ball_vel *= 0.15
	ball_vz = 0.0
	charge = -1.0
	_say("HAIL!  %s" % teams[team]["name"], GOAL_PAUSE)
	events.append({"type": "goal", "team": team, "half": half, "clock": clock})


func match_minute() -> int:
	return int(clock / half_seconds * 45.0) + (45 if half == 2 else 0)
