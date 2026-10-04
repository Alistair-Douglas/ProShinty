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
const Subs := preload("res://scripts/substitutions.gd")

const PITCH := Vector2(150, 75)
const GOAL_W := 4.0          # 12 ft between the posts
const CROSSBAR := 3.33       # 10 ft
const D_RADIUS := 10.0
const GRAVITY := 10.7        # yards/s^2
const PLAYER_R := 0.75
const REACH := 1.7           # how far a caman reaches
const REACH_HEIGHT := 2.3
const KEEPER_REACH_HEIGHT := 3.2
const THIGH_HEIGHT := 1.0       # a body stop below this is on the thigh, above it the chest
const KEEPER_BEAT := 0.3        # chance a shot on target beats the keeper outright...
const KEEPER_BEAT_HARD := 0.2    # ...more for a hard one...
const KEEPER_BEAT_CORNER := 0.35 # ...and more again high into a corner
const KEEPER_HIGH := 1.8         # a shot this high is a high one
const CORNER_IN := 1.0           # within this of a post is in the corner
const KEEPER_STICK_HEIGHT := 1.2   # above this a keeper turns the ball away with the caman
const SHOT_INSIDE := 0.45       # shots are aimed this far inside the post
const LOW_SHOT := 0.35          # a low shot crosses the line about this high (yards)
const MID_SHOT := 1.5
const TOP_CORNER := 2.85        # just under the bar (3.33)
const SHOT_DRAG := 0.012        # flight time allowance per yard for the ball slowing
const GOAL_PAUSE := 3.0
const HALF_TIME_PAUSE := 7.0     # long enough to see everyone walk off towards the dugouts
const EXTRA_TIME_PAUSE := 4.0    # the break before extra time: players stay out on the pitch
const THROW_UP_AIM_MAX := 1.1   # rad: how far off straight up the park a throw-up can be aimed
const THROUGH_LEAD := 8.0       # yd: a through ball is played this far ahead of the runner
const CHIP_ANGLE := 36.0        # degrees: a chipped through ball is launched this steeply
const CHIP_PACE := 1.12         # a lofted strike comes off a little slower than asked: make it up
const WALK_SPEED := 1.6
const SHOOTOUT_KICKS := 5       # penalties each before sudden death
const SHOOTOUT_PAUSE := 2.5
const PEN_IDLE_MAX := 20.0      # s: a penalty you leave this long is hit for you
const PEN_GUESS := 0.35         # a keeper's chance of guessing a penalty right, plus up to 0.2 for keeping
const MOUSE_AIM_MS := 4000      # the mouse aims hits while it's been moved this recently          # yd/s: walking off at half time and full time
const PENALTY_SPOT := 20.0   # penalty hit, yards from the goal line
const FREE_HIT_BACK := 5.0   # opponents stand this far off a set piece
const SWING_CATCH := 0.5     # a swing that misses the ball catches a player in its path
const TRIP_TIME := 1.0       # a player a caman catches goes down and is back in play a second later
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
const THROW_UP_GAP := 0.42   # each centre stands this far from the spot, face to face
const SET_PIECE_PAUSE := 2.2 # hit-outs and corners: play stops while players get set
const FREE_HIT_PAUSE := 1.2  # a free hit: a moment to line it up, opponents 5 yards off
const SET_PIECE_MIN := 1.0   # a human taker can't hit it before this
const FEET_HEIGHT := 0.35     # yards: a ball below this is stopped with the feet
const FEET_EXTRA := 0.15      # feet planted either side reach a little wider than the body
const RATING_MID := 65.0     # ratings either side of this are pushed further out in play
const RATING_STRETCH := 1.6
const RATING_GAP_EDGE := 0.0035  # per point of team rating difference, capped at 0.12
const HOP_REACH := 0.45       # yd: how far sideways a player jumps, feet together, to stop a ground ball (at full control)
const HOP_TIME := 0.14        # s: how long that jump takes
const FEET_GAP := 0.2         # yd: land further off the ball's line than this and it bounces past
const BODY_STOP_SPEED := 12.0 # yd/s: a stop with the body or feet is sure below about this
const DRIBBLE_REACH := 1.0    # yards from the body: the caman stays on a dribbled ball within this
const LONG_HIT_ANGLE := 32.0  # degrees: a full-power long hit is launched this steeply
const LONG_HIT_BOOST := 1.2   # a full long hit goes this much faster than a full shot
const BANGER_TIMING := 0.88   # hold shoot to at least this much of full power (no overswing)
const BANGER_BOOST := 1.25    # and the ball flies this much faster than a normal full hit
const JOG := 0.6             # jogging (no sprint): this share of top speed
const SHIELD_SPEED := 0.45   # shielding the ball: walking pace, body between ball and man
const BATTLE_TIME := 0.8     # a stick battle for the ball lasts this long
const SWEEP_ZONE := 0.35    # yards: the caman head sweeps this far either side of the strike spot, low over the grass
const DUMMY_SHOW := 0.3     # hit meter shown before pulling out: a full backswing sells the dummy
const DUMMY_RANGE := 3.5     # yards: markers this close can bite on it
const DUMMY_SOLD := 0.7      # s: a marker who bites is planted this long
const DUMMY_FRESH := 3.0     # s: a second dummy sooner than this sells less
const BATTLE_SLOW := 0.35    # both players are near enough stood still while they fight for it

enum State { THROW_UP, PLAY, GOAL, HALF_TIME, FULL_TIME }


class Player:
	var team: int
	var data: Dictionary
	var number: int
	var position_code: String
	var role: String
	var home: Vector2
	var man: Player          # a back: the opposing forward they mark
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
	var dive_rest := 0.0     # keeper: getting up after a dive, no second dive yet
	var hop := Vector2.ZERO  # a sideways jump, feet together, to get in line with a ball
	var hop_t := 0.0         # time left in the jump
	var stick := Vector3.ZERO    # caman head: pitch x, y and height
	var stick_prev := Vector3.ZERO  # where it was last step (swept contact)
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
	var shielding := false   # carrier holding the ball up, body between it and the man
	var judge := Vector3.ZERO  # how far off this player's read of the ball in the air is
	var judge_flight := -1     # the flight that read was made for
	var beat_flight := -1      # keeper: the shot already judged for beating them
	var use_body := false      # going to take this ball on the body, stick out of the way
	var hold_t := 0.0        # AI: how long to keep holding it up
	var sold := 0.0          # bit on a dummy: committed and planted for this long

	## A rating as play uses it: stretched away from the middle so the gap
	## between a top Premiership player and a lower-league one shows.
	func r(key: String) -> float:
		return clampf(RATING_MID + (float(data.get(key, 50)) - RATING_MID) * RATING_STRETCH, 1.0, 99.0)

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
var weather := {}      # wetness, wind, rain and light (ShintyWeather.make)
var weather_t := 0.0   # seconds of match so far, for the gusts
var score := [0, 0]
var shots := [0, 0]
var state := State.THROW_UP
var fwd_shape := ["diamond", "diamond"]   # each side's front four: "diamond" or "square"
var state_timer := 0.0
var half := 1
var clock := 0.0
var half_seconds := 180.0
var extra_time := true
var shootout := false     # level after extra time: penalties (see _start_shootout)
var shoot_kicks := [[], []]   # per team, true for each penalty scored, false for a miss
var shoot_order := [[], []]   # each side's takers, best hitter first
var shoot_turn := 0           # whose penalty is next
var shoot_wait := 0.0         # pause before the next one
var shoot_live := false       # a penalty is being taken
var shoot_t := 0.0            # time since it was struck
var shoot_event_i := 0        # events from this index on belong to this penalty
var shoot_result := []        # penalties scored by each side once it's decided    # a draw at full time goes to two halves of extra time
var break_kind := ""      # during State.HALF_TIME: "half" (walk off) or "extra" (before extra time)
var human_side := 0
var human: Player = null
var difficulty := 1
var attack_dir := [1, -1]
var protected_timer := 0.0
var paused := false
var charge := -1.0
## A stick battle for the carrier's ball: {"t": tackler, "o": carrier,
## "time": s, "effort": {player: extra}}. Empty when there isn't one.
var battle := {}
const SHOOT_RANGE := 70.0   # the shoot button aims at goal from within this many yards
var charge_aim := Vector2.RIGHT   # where the stick pointed as the hit button went down
var charge_steer := Vector2.ZERO  # and the steer for a shot (zero: the far corner)
var charge_kind := "shoot"   # which button is being held: "shoot" (at goal) or "hit" (long)
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
var subs := Subs.new()             # benches and substitutions (substitutions.gd)
var penalty_taker: Player = null
var pen_idle := 0.0              # how long your penalty taker has stood over it
var penalty_side := 0.0           # the corner a computer penalty taker has picked (+1 or -1 across the goal)
var gather_keeper: Player = null   # a saved ball dropping to the keeper
var foul_pending = null            # [offender, fouled] seen by the referee
var gather_t := 0.0
var team_ai: TeamAI
var set_piece := ""                # "Hit-out", "Corner", "Free hit" or "Penalty hit" while one is being taken
var set_piece_taker: Player = null
var set_piece_t := 0.0             # seconds since it was awarded
var throw_up_pair: Array = []     # the two centres contesting the throw-up
var throw_up_tossed := false
var throw_up_t := 0.0              # seconds since the ball went up
var throw_up_ideal := 0.0          # when it drops to where a caman meets it overhead
var throw_up_swing := {}           # Player -> when they swing at it
var throw_up_aim := {}             # Player -> where they'll knock it, as an angle off straight up the park
var shy_lift: Player = null        # taking a shy with the ball still in the hand
var shy_lift_t := 0.0
var shy_lift_from := Vector3.ZERO
var mouse_moved_ms := -100000      # when the mouse last moved (it aims hits for a while after)
var restart_aim := 0.0             # the player's aim at a restart, off restart_base
var restart_target: Player = null  # who a computer restart taker has picked out (turns to face them first)
var restart_long := false          # and whether it's a long hit to them rather than a pass
var restart_base := Vector2.RIGHT  # straight in from the line (a shy) or the default aim
var dribble_vel := Vector2.ZERO    # a dribbled ball rolling ahead of its carrier
var dribble_taps := 0
var since_dummy := 99.0            # seconds since the last dummy (one straight after sells less)
var flight := 0                    # bumped each time the ball is sent somewhere new (players re-read it)
var ball_shift := Vector3.ZERO     # running total of the ball being moved onto a caman, body or glove (see _place_ball)



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
	extra_time = bool(config.get("extra_time", true))
	if config.has("seed"):
		seed(int(config["seed"]))
	weather = ShintyWeather.make(config.get("weather"))
	ball_sim.physics.wetness = float(weather["wet"])
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
	# Each side's forwards line up in a diamond or a square (the backs then
	# take the shape of the forwards they face).
	for t in 2:
		fwd_shape[t] = str(config.get("shapes", ["", ""])[t])
		if not TeamData.FORWARD_SHAPES.has(fwd_shape[t]):
			fwd_shape[t] = "square" if randf() < 0.4 else "diamond"
	_apply_shapes()
	referee.setup(self)
	subs.setup(self)
	_start_throw_up()
	if human_side >= 0:
		human = _nearest_outfield(human_side, ball_pos, null)


## Home spots from the two forward shapes, and each back's man to mark.
func _apply_shapes() -> void:
	for p in players:
		p.home = TeamData.shaped_home(p.position_code, fwd_shape[p.team], fwd_shape[1 - p.team])
		p.man = null
		var code: String = TeamData.MARKS.get(p.position_code, "")
		for o in squads[1 - p.team]:
			if code != "" and o.position_code == code:
				p.man = o


# ---------------------------------------------------------------- main loop

func _physics_process(delta: float) -> void:
	if manual_step:
		return
	if Input.is_action_just_pressed("pause") and state != State.FULL_TIME and not subs.menu_busy():
		paused = not paused
	if paused:
		if Input.is_action_just_pressed("quit_match") and not subs.menu_busy():
			get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
		return
	if state == State.FULL_TIME and (Input.is_action_just_pressed("ui_accept") or Input.is_action_just_pressed("shoot")):
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
		return
	step(delta)


func step(dt: float) -> void:
	message_timer = max(0.0, message_timer - dt)
	weather_t += dt
	var wind := ShintyWeather.wind_at(weather, weather_t) * ShintyMatchAdapter.YARD
	ball_sim.physics.wind = Vector3(wind.x, 0.0, wind.y)
	subs.step(dt)
	if state != State.PLAY and state != State.FULL_TIME:
		referee.step(dt)
	match state:
		State.THROW_UP:
			_step_throw_up(dt)
		State.PLAY:
			if shootout:
				_step_shootout(dt)
				return
			_update_set_piece(dt)
			if shy_taker() == null and set_piece_taker_now() == null:
				clock += dt   # the clock stops while a shy, hit-out or corner is taken
			_update_players(dt)
			_take_penalty(dt)
			_update_ball(dt)
			referee.step(dt)
			_check_ball_out()
			if clock >= half_length() and state == State.PLAY:
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
			_walk_off(dt, break_kind == "half")
			if state_timer <= 0.0:
				half += 1
				clock = 0.0
				# Ends change every half, extra time included.
				attack_dir = [1, -1] if half % 2 == 1 else [-1, 1]
				_start_throw_up()
		State.FULL_TIME:
			_walk_off(dt, true)


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
	throw_up_aim = {}
	for p in players:
		# Everyone else starts in their normal positions across the pitch,
		# forwards up in the other half beside the backs marking them.
		p.pos = frac_to_world(p.team, p.home)
		p.throw_up = false
		p.facing = Vector2(attack_dir[p.team], 0)
		if p.position_code == "LM" and throw_up_pair.size() == p.team:
			# The two centres stand over the spot face to face across the
			# pitch, each with his back to a touchline, camans raised and
			# crossed high over the ball.
			var face := Vector2(attack_dir[p.team], 0).rotated(PI / 2.0)
			p.pos = PITCH / 2.0 - face * THROW_UP_GAP
			p.facing = face
			p.throw_up = true
			throw_up_pair.append(p)
			# The computer picks a spot up the park; you aim yours with the stick.
			throw_up_aim[p] = 0.0 if p == human else randf_range(-0.9, 0.9)
		p.vel = Vector2.ZERO
		p.desired = Vector2.ZERO
		p.stagger = 0.0
		p.lunge = 0.0
		p.swing_t = -1.0
		p.shy_ready = false
		p.shy_toss = false
		p.stick = Body.rest_spot(p)
	gather_keeper = null
	# You take your side's throw-up: control goes to your centre in it.
	for p in throw_up_pair:
		if p.team == human_side:
			human = p
			throw_up_aim[p] = 0.0
	_say("Throw-up", 1.2)
	events.append({"type": "throw_up"})


func _end_half() -> void:
	carrier = null
	ball_vel = Vector2.ZERO
	_clear_set_piece()
	penalty_taker = null
	if half == 1 or half == 3:
		state = State.HALF_TIME
		break_kind = "half" if half == 1 else "extra"
		state_timer = HALF_TIME_PAUSE if half == 1 else EXTRA_TIME_PAUSE
		_say("Half time" if half == 1 else "Half time in extra time", state_timer)
	elif half == 2 and extra_time and score[0] == score[1]:
		# Level at full time: two halves of extra time, 15 minutes each.
		state = State.HALF_TIME
		break_kind = "extra"
		state_timer = EXTRA_TIME_PAUSE
		_say("Full time: level\nExtra time: two halves of 15 minutes", EXTRA_TIME_PAUSE)
	elif half == 4 and score[0] == score[1]:
		# Still level after extra time: a penalty shootout.
		_start_shootout()
	else:
		state = State.FULL_TIME
		_say("Full time" if half == 2 else "Full time after extra time", 9999.0)
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


## The better side (by team rating) gets an edge on every contest; on top of
## that, computer teams get a small edge on hard and a handicap on easy.
func _skill_mod(team: int) -> float:
	var gap: float = clampf((float(teams[team].get("overall", 65)) - float(teams[1 - team].get("overall", 65))) * RATING_GAP_EDGE, -0.12, 0.12)
	if human_side < 0 or team == human_side:
		return gap
	return gap + [-0.1, 0.0, 0.08][difficulty]


func _reaction(team: int) -> float:
	if human_side >= 0 and team != human_side:
		return [0.55, 0.35, 0.2][difficulty] + randf() * 0.15
	return 0.3 + randf() * 0.15


# ---------------------------------------------------------------- players

func _update_players(dt: float) -> void:
	protected_timer = max(0.0, protected_timer - dt)
	since_dummy += dt
	for p in players:
		p.cooldown = max(0.0, p.cooldown - dt)
		p.touch_block = max(0.0, p.touch_block - dt)
		p.swing = max(0.0, p.swing - dt)
		p.stagger = max(0.0, p.stagger - dt)
		p.lunge = max(0.0, p.lunge - dt)
		p.sold = max(0.0, p.sold - dt)
		p.dive_rest = max(0.0, p.dive_rest - dt)
		if p.hop_t > 0.0:
			var step: float = min(dt, p.hop_t)
			p.pos += p.hop * step / HOP_TIME
			p.hop_t -= step
		Counters.tick(p, dt)
		p.sprinting = false
		if p != carrier:
			p.shielding = false
			p.hold_t = 0.0
	if human != null and human.is_keeper() and carrier != human and gather_keeper != human:
		human = _nearest_outfield(human_side, ball_pos, null)   # it's gone: back to an outfield player
	for t in 2:
		_ai_team(t, dt)
	if human != null and state == State.PLAY:
		_human_control(dt)
	elif human != null:
		human.desired = Vector2.ZERO
	_respect_restart()
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
	_update_battle(dt)
	for p in players:
		Body.update_stick(self, p, dt)
		if p.swing_t >= 0.0:
			p.swing_t -= dt
			if p.swing_t < 0.0:
				_contact(p)
	_hold_off_restart()


## The player standing over a restart (a hit-out, corner, shy or free hit
## not yet taken), or null in open play.
func restart_taker() -> Player:
	var t := set_piece_taker_now()
	if t != null:
		return t
	for p in players:
		if p.shy_toss or (p.shy_ready and carrier == p):
			return p
	if protected_timer > 0.0 and carrier != null:
		return carrier
	return null


## Opponents near a restart don't run at the taker: whatever their job, the
## part of their run that goes into the 5 yards is dropped, so they stop at
## the edge (or walk round it) and stand, instead of running on the spot
## against it.
func _respect_restart() -> void:
	var taker := restart_taker()
	if taker == null:
		return
	for o in squads[1 - taker.team]:
		for c in [ball_pos, taker.pos]:
			var off: Vector2 = o.pos - c
			if off.length() > FREE_HIT_BACK + 1.5 or off.length() < 0.01:
				continue
			var out: Vector2 = off.normalized()
			var inward: float = o.desired.dot(-out)
			if inward > 0.0:
				o.desired += out * inward
				o.sprinting = false


## Until a restart is taken, no opponent may come within FREE_HIT_BACK yards
## of the ball (or of a shy taker). Anyone who tries is stopped at the edge,
## however long the taker stands over it.
func _hold_off_restart() -> void:
	var taker := restart_taker()
	if taker == null:
		return
	for o in squads[1 - taker.team]:
		for c in [ball_pos, taker.pos]:
			var off: Vector2 = o.pos - c
			if off.length() >= FREE_HIT_BACK:
				continue
			var out: Vector2 = off.normalized() if off.length() > 0.01 else Vector2(-attack_dir[taker.team], 0)
			o.pos = c + out * FREE_HIT_BACK
			var inward: float = o.vel.dot(-out)
			if inward > 0.0:
				o.vel += out * inward   # stopped at the edge, not bounced off it


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
	var speed := p.top_speed() * (1.0 if sprint else JOG)
	p.desired = off / d * speed * min(1.0, d / 3.0)
	p.sprinting = sprint and d > 3.0


func _steer_dir(p: Player, dir: Vector2, sprint: bool) -> void:
	p.desired = dir.normalized() * p.top_speed() * (1.0 if sprint else 0.8)
	p.sprinting = sprint


# ---------------------------------------------------------------- AI

func _ai_team(t: int, dt: float) -> void:
	var have := carrier != null and carrier.team == t
	var chasers := []
	var standing := restart_taker()
	if state == State.PLAY and not have and (standing == null or standing.team == t):
		var pt := _ball_intercept_point()
		var ranked := []
		for p in squads[t]:
			if not p.is_keeper() and p != human:
				ranked.append(p)
		# Backs stay with their forward and forwards stay up the park, so the
		# ball is chased by whoever is nearest in the middle unless it's in
		# a back's or forward's own part of the pitch.
		var bx := own_frac(t, pt.x)
		var cost := func(p: Player) -> float:
			var d: float = p.pos.distance_to(pt)
			if p.role == "DEF" and bx > 0.35:
				d += 10.0
			elif p.role == "FWD" and bx < 0.6:
				d += 8.0
			return d
		ranked.sort_custom(func(a, b): return cost.call(a) < cost.call(b))
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
		if p.is_keeper() and not (p == carrier and p == set_piece_taker_now()):
			_ai_keeper(p, dt)
		elif p.sold > 0.0:
			p.desired = Vector2.ZERO   # bought a dummy: planted, going nowhere
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
	if p.swing_t >= 0.0 or in_battle(p):
		return   # mid-swing or fighting for it: committed
	p.hold_t = max(0.0, p.hold_t - dt)
	p.shielding = p.hold_t > 0.0
	if p == penalty_taker:
		return   # struck at goal by _take_penalty once everyone is set
	if p.shy_ready or p == set_piece_taker_now():
		# A shy, hit-out or corner has to be taken: pass it to someone open or
		# hit it long. The target is picked early and the taker turns to face
		# it while everyone gets set, so the camera behind them looks where
		# the ball is going (no snapping round at the last moment).
		if restart_target == null or not restart_target in players:
			restart_target = _best_pass(p, false)
			restart_long = restart_target == null
			if restart_long:
				restart_target = _long_target(p)
		# Aim where they're running to, as the pass will be led into it.
		var at: Vector2 = target_goal(p.team) if restart_target == null else restart_target.pos + restart_target.vel * 0.8
		var lim: float = PI if set_piece == "Free hit" else PI / 2.0   # a free hit can go back
		var want: float = clamp(restart_base.angle_to(at - p.pos), -lim, lim)
		restart_aim = move_toward(restart_aim, want, RESTART_AIM_RATE * 1.5 * dt)
		p.facing = restart_base.rotated(restart_aim)
		p.think -= dt
		if p.think <= 0.0 and protected_timer <= 0.0 and (absf(angle_difference(restart_aim, want)) < 0.25 or p.think < -1.5):
			var to := restart_target
			restart_target = null
			if to != null and not restart_long:
				_pass_to(p, to)
			else:
				_hit_long(p, to)
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
		if pressure < 2.5 and p.hold_t <= 0.0 and randf() < 0.4:
			# Nothing on: hold it up, back into the man, and wait for support.
			p.hold_t = randf_range(0.8, 1.8)
			p.shielding = true
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


func _ai_shoot(p: Player, pick: float = 0.0) -> void:
	var goal := target_goal(p.team)
	var keeper := _keeper_of(1 - p.team)
	var side := 1.0 if randf() < 0.5 else -1.0
	if pick != 0.0:
		side = pick   # a corner already picked out (a penalty hit)
	elif keeper != null and abs(keeper.pos.y - goal.y) > 0.4:
		side = -sign(keeper.pos.y - goal.y)
	var aim := goal + Vector2(0, side * (GOAL_W / 2.0 - SHOT_INSIDE))
	var d := p.pos.distance_to(goal)
	var dir: Vector2 = (aim - p.pos).normalized()
	if d > 14.0 and randf() < p.r("shooting") / 100.0 * 0.12:
		# Now and then a good hitter really leathers one into the top corner.
		var bang: float = _full_speed(p) * BANGER_BOOST
		_strike_speed(p, dir, bang, _shot_vz(p.pos, aim, bang, TOP_CORNER), "shooting", 1.0)
		shots[p.team] += 1
		return
	# Picks a corner: mostly low, sometimes high.
	var r := randf()
	var height: float = LOW_SHOT if r < 0.5 else (TOP_CORNER - 0.3 if r < 0.8 else MID_SHOT)
	var power: float = clamp(d / 30.0 + 0.45, 0.55, 1.0)
	var speed: float = lerp(10.0, _full_speed(p), power)
	_strike_speed(p, dir, speed, _shot_vz(p.pos, aim, speed, height), "shooting", power)
	shots[p.team] += 1


## Launch speed upwards for a shot from `from` at `speed` to cross the goal
## line at `height` above the grass (gravity, with a little allowance for
## the ball slowing through the air).
func _shot_vz(from: Vector2, to: Vector2, speed: float, height: float) -> float:
	var d: float = from.distance_to(to)
	var t: float = d / maxf(speed, 1.0) * (1.0 + d * SHOT_DRAG)
	return clampf((height - 0.1 + 0.5 * GRAVITY * t * t) / maxf(t, 0.05), 0.0, speed * 0.7)


func _ai_pass(p: Player, forward_only: bool) -> bool:
	var best := _best_pass(p, forward_only)
	if best == null:
		return false
	_pass_to(p, best)
	return true


## The team-mate most worth passing to, or null if nobody is on.
func _best_pass(p: Player, forward_only: bool) -> Player:
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
		return null
	return best


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


func _hit_long(p: Player, to: Player = null) -> void:
	var best: Player = to if to != null else _long_target(p)
	var aim := target_goal(p.team) if best == null else best.pos
	var speed: float = lerp(10.0, _full_speed(p) * LONG_HIT_BOOST, 0.85)
	_strike_speed(p, (aim - p.pos).normalized(), speed, _loft_at(speed, LONG_HIT_ANGLE - 4.0), "passing", 0.85)


## The team-mate furthest up the park (roughly), for a long hit.
func _long_target(p: Player) -> Player:
	var best: Player = null
	var best_x := -INF
	for m in squads[p.team]:
		if m == p or m.is_keeper():
			continue
		var x: float = own_frac(p.team, m.pos.x) + randf() * 0.15
		if x > best_x:
			best_x = x
			best = m
	return best


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
		p.desired = mv.normalized() * p.top_speed() * (1.0 if sprint else JOG) * clamp(mv.length(), 0.35, 1.0)
		p.sprinting = sprint
	else:
		p.desired = Vector2.ZERO
	if Input.is_action_just_pressed("switch"):
		var pick := _nearest_outfield(human_side, ball_pos, p)
		if pick != null and carrier != p:
			human = pick
			charge = -1.0
			return
	# A pass or hit goes where the stick points the moment the button goes
	# down (not the smoothed run, which lags behind it), so it can be steered
	# without changing how you run; on keyboard and mouse, at the pointer.
	var hit_aim := _hit_aim(p)
	var aim := hit_aim if hit_aim != Vector2.ZERO else (raw.normalized() if raw.length() > 0.15 else p.facing)
	p.shielding = carrier == p and Input.is_action_pressed("shield") and p.swing_t < 0.0
	if in_battle(p):
		# Fighting for the ball: every press of a stick button is more effort.
		charge = -1.0
		for a in ["shoot", "hit", "pass", "shield", "barge"]:
			if Input.is_action_just_pressed(a):
				battle["effort"][p] = min(battle["effort"].get(p, 0.0) + 6.0, 24.0)
		return
	if p == set_piece_taker_now() or (p.shy_ready and carrier == p):
		# Standing over a restart: the stick turns the aim smoothly, within
		# a half circle (for a shy, from up the line round to down the line).
		p.desired = Vector2.ZERO
		# The camera is behind the taker here, so the stick is read as the
		# player sees it: left turns the aim left, right turns it right, up
		# is straight ahead (not the pitch's own directions, which made left
		# swing the aim round to the right).
		var rel: Vector2 = restart_base * -raw.y + restart_base.rotated(PI / 2.0) * raw.x
		if hit_aim != Vector2.ZERO:
			rel = hit_aim   # the mouse: aim at the pointer
		if set_piece == "Free hit" and p == set_piece_taker_now():
			# A free hit can go any way, backwards included: left and right
			# keep turning the aim (and the camera behind it) all the way round.
			if hit_aim != Vector2.ZERO:
				var turn: float = angle_difference(restart_aim, restart_base.angle_to(hit_aim))
				restart_aim = wrapf(restart_aim + clampf(turn, -RESTART_AIM_RATE * 1.5 * dt, RESTART_AIM_RATE * 1.5 * dt), -PI, PI)
			elif absf(raw.x) > 0.15:
				restart_aim = wrapf(restart_aim + raw.x * RESTART_AIM_RATE * 1.5 * dt, -PI, PI)
		elif rel.length() > 0.15 and rel.normalized().dot(restart_base) > -0.9:
			var want: float = clamp(restart_base.angle_to(rel), -PI / 2.0, PI / 2.0)
			restart_aim = move_toward(restart_aim, want, RESTART_AIM_RATE * dt)
		p.facing = restart_base.rotated(restart_aim)
		aim = p.facing
	if p == set_piece_taker_now() and set_piece_t < SET_PIECE_MIN:
		return   # play has stopped: let everyone get set first
	if Input.is_action_just_pressed("shoot") or Input.is_action_just_pressed("hit"):
		# Also how you swing at an opponent's ball: beat their swing to it.
		charge = 0.0
		charge_kind = "hit" if Input.is_action_just_pressed("hit") else "shoot"
		# Aimed as the button goes down; the swing keeps that direction.
		charge_aim = aim
		charge_steer = hit_aim if hit_aim != Vector2.ZERO else raw
	if Input.is_action_just_pressed("block"):
		# Y / F: with the ball it's a through ball (as in FIFA); without it,
		# a block or a cleek on an opponent's swing, picked by where you are.
		if carrier == p and p.swing_t < 0.0 and p != set_piece_taker_now() and not p.shy_ready:
			# Holding LB (switch, which does nothing on the ball) chips it.
			_human_through(p, aim, Input.is_action_pressed("switch"))
		else:
			Counters.start_counter(self, p)
	if Input.is_action_just_pressed("barge"):
		Counters.start_barge(self, p)
	if charge >= 0.0 and Input.is_action_just_pressed("pass") and carrier == p \
			and p != set_piece_taker_now() and not p.shy_ready:
		# A or E mid-backswing: pull out of the hit, a dummy.
		_dummy(p)
		return
	if charge >= 0.0:
		# Golf-style meter: it fills to full power, then keeps going into an
		# overswing that adds power error (miss-hits and curve) but no power.
		charge = min(OVERSWING_MAX, charge + dt * 1.3)
		if not Input.is_action_pressed(charge_kind):
			# Swing whether or not the ball is there yet: timing a first-time
			# hit on a ball arriving is up to you. Miss it and it's fresh air.
			var restart: bool = p == set_piece_taker_now() or (p.shy_ready and carrier == p)
			if charge_kind == "shoot" and not restart:
				_human_shoot(p, charge_steer, charge)
			else:
				_human_hit(p, aim if restart else charge_aim, charge)
			charge = -1.0
	if Input.is_action_just_pressed("pass"):
		if carrier == p or _ball_in_reach(p):
			_human_pass(p, aim)
		elif carrier != null and carrier.team != p.team and p.pos.distance_to(carrier.pos) < REACH + 0.8:
			_try_tackle(p, carrier)


## On keyboard and mouse, hits are aimed at the pointer while the mouse has
## been used lately. Zero otherwise.
func _hit_aim(p: Player) -> Vector2:
	var view := get_node_or_null("View")
	if view != null and Time.get_ticks_msec() - mouse_moved_ms < MOUSE_AIM_MS:
		var at = view.pitch_at_screen(get_viewport().get_mouse_position())
		if at != null and (at - p.pos).length() > 0.5:
			return (at - p.pos).normalized()
	return Vector2.ZERO


func _input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		mouse_moved_ms = Time.get_ticks_msec()


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


## The shoot button: always at goal, wherever the player is facing. Hold for
## power; the stick picks the corner (steer one way or the other of the goal
## for that post, or leave it for the far corner).
func _human_shoot(p: Player, steer_in: Vector2, charged: float) -> void:
	var power: float = min(charged, 1.0)
	p.overswing = max(0.0, charged - 1.0) / (OVERSWING_MAX - 1.0)
	p.charged = power
	var goal := target_goal(p.team)
	var to_goal := goal - p.pos
	if to_goal.length() > SHOOT_RANGE:
		# Too far out to shoot: it's a long hit where the player is aiming.
		_human_hit(p, p.facing if steer_in.length() < 0.3 else steer_in.normalized(), charged)
		return
	var side: float
	if abs(steer_in.y) > 0.3:
		# Steering up or down the pitch picks that post.
		side = clamp(steer_in.y * 2.0, -1.0, 1.0)
	else:
		side = -signf(p.pos.y - goal.y) if abs(p.pos.y - goal.y) > 1.0 else (1.0 if randf() < 0.5 else -1.0)
	var spot := goal + Vector2(0, side * (GOAL_W / 2.0 - SHOT_INSIDE))
	var aim := (spot - p.pos).normalized()
	if carrier == p or _ball_in_reach(p):
		shots[p.team] += 1
	p.facing = aim
	if charged >= BANGER_TIMING and charged <= 1.0:
		# Timed to perfection at full power, no overswing: an absolute banger,
		# into the top corner.
		var bang: float = _full_speed(p) * BANGER_BOOST
		_strike_speed(p, aim, bang, _shot_vz(p.pos, spot, bang, TOP_CORNER), "shooting", 1.0)
		_say("What a hit!", 1.0)
		return
	# A soft one is kept low; the harder it's hit, the higher it's aimed.
	var speed: float = lerp(10.0, _full_speed(p), max(power, 0.2))
	var height: float = LOW_SHOT if power < 0.55 else lerp(LOW_SHOT, MID_SHOT + 0.6, (power - 0.55) / 0.45)
	var loft: float = _shot_vz(p.pos, spot, speed, height)
	if to_goal.length() >= 45.0:
		loft = 0.5 + power * 5.0   # from distance it has to be lofted in
	_strike_speed(p, aim, speed, loft, "shooting", max(power, 0.2))


## Ball speed of a full-power strike by this player.
func _full_speed(p: Player) -> float:
	return 20.0 + p.r("shooting") * 0.26


## Vertical launch speed for a hit of `speed` at `degrees` above the grass.
func _loft_at(speed: float, degrees: float) -> float:
	return speed * tan(deg_to_rad(degrees))


## The long-hit button (and a restart): straight where the player is aiming,
## lofted more the harder it's hit. Clearances, long balls, shies.
func _human_hit(p: Player, aim: Vector2, charged: float) -> void:
	var power: float = min(charged, 1.0)
	p.overswing = max(0.0, charged - 1.0) / (OVERSWING_MAX - 1.0)
	p.charged = power
	# A big hit goes up and comes down: the harder it's hit, the higher it's
	# launched, so a full clearance is a proper parabola, not a skimmer.
	# A long hit is the full swing: at full power it carries past halfway
	# from a hit-out.
	var speed: float = lerp(10.0, _full_speed(p) * LONG_HIT_BOOST, max(power, 0.2))
	_strike_speed(p, aim, speed, _loft_at(speed, lerp(8.0, LONG_HIT_ANGLE, power)), "shooting", max(power, 0.2))


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


## A through ball: played into the space ahead of a team-mate making a run
## (the one most in line with the stick), for them to run onto.
func _human_through(p: Player, aim: Vector2, chip: bool = false) -> void:
	var best: Player = null
	var best_score := -INF
	for m in squads[p.team]:
		if m == p or m.is_keeper():
			continue
		var off: Vector2 = m.pos - p.pos
		var d := off.length()
		if d < 4.0 or d > 55.0:
			continue
		var cosang := aim.dot(off / d)
		var fwd: float = (m.pos.x - p.pos.x) * attack_dir[p.team]
		if cosang < 0.3 or fwd < 0.0:
			continue
		var s := cosang * 30.0 + fwd * 0.3 - d * 0.3
		if s > best_score:
			best_score = s
			best = m
	if best == null:
		if chip:
			_strike_speed(p, aim, 16.0, 7.0, "passing")
		else:
			_strike_speed(p, aim, 20.0, 0.4, "passing")
		return
	# Into space ahead of them: where they're running, or up the park.
	var run: Vector2 = best.vel.normalized() if best.vel.length() > 2.0 else Vector2(attack_dir[p.team], 0)
	if run.x * attack_dir[p.team] < 0.2:
		run = (run + Vector2(attack_dir[p.team], 0) * 0.8).normalized()
	var spot: Vector2 = best.pos + run * THROUGH_LEAD
	spot = Vector2(clampf(spot.x, 2.0, PITCH.x - 2.0), clampf(spot.y, 2.0, PITCH.y - 2.0))
	var d := p.pos.distance_to(spot)
	if chip:
		# Lifted over the defence: launched steeply enough to clear a caman
		# held up a few yards off, slower than along the grass, and paced to
		# drop onto the spot for the runner.
		var up: float = tan(deg_to_rad(CHIP_ANGLE))
		var cs: float = sqrt(0.5 * GRAVITY * d * (1.0 + d * SHOT_DRAG) / up) * CHIP_PACE
		_strike_speed(p, (spot - p.pos).normalized(), cs, cs * up, "passing")
	else:
		var speed: float = clampf(d * 0.75 + 10.0, 14.0, 34.0)
		_strike_speed(p, (spot - p.pos).normalized(), speed, 0.4, "passing")
	if p.team == human_side:
		human = best


## A dummy: shape to hit, then pull out of it. A computer marker close
## enough to block, cleek or swing with it may bite: they commit to the
## counter and are planted for a moment while the carrier goes by. Better
## control against worse tackling sells it more, as does a longer backswing
## shown; one straight after another sells less.
func _dummy(p: Player) -> void:
	var shown: float = clampf(charge / DUMMY_SHOW, 0.0, 1.0)
	var fresh: float = clampf(since_dummy / DUMMY_FRESH, 0.3, 1.0)
	since_dummy = 0.0
	charge = -1.0
	p.overswing = 0.0
	var bit := 0
	for q in squads[1 - p.team]:
		if q == human or q.is_keeper() or q.stagger > 0.0 or q.sold > 0.0 \
				or q.pos.distance_to(p.pos) > DUMMY_RANGE:
			continue
		var edge: float = (p.r("control") - q.r("tackling")) / 100.0
		if randf() >= clampf(0.45 + edge, 0.15, 0.9) * shown * fresh:
			continue
		bit += 1
		q.sold = DUMMY_SOLD
		q.cooldown = maxf(q.cooldown, DUMMY_SOLD)
		q.think = DUMMY_SOLD
		if q.pos.distance_to(p.pos) < Counters.CLEEK_RANGE - 0.3 and randf() < 0.4:
			Counters.start_cleek(self, q)
		else:
			Counters.start_block(self, q)
	events.append({"type": "dummy", "team": p.team, "by": p, "sold": bit})
	if p == human:
		_say("Dummy sold!" if bit > 0 else "Dummy", 1.0)


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
	# How hard, as a share of this player's full hit: cleeks only work on
	# swings of half power or more (a short swing has no arc to get under).
	var share: float = clampf(speed / _full_speed(p), 0.0, 1.5)
	p.swing_req = {"dir": dir, "speed": speed, "loft": loft, "skill_key": skill_key, "kind": kind, "share": share}
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
		# First-time hit: how close the ball comes to the caman as it sweeps
		# through the hitting zone (see _sweep_meet), not just where the
		# ball happens to be on the contact frame.
		var met := _sweep_meet(p, req)
		offset = max(0.0, met[0] - Body.CONTACT_R)
		if met[1].z > REACH_HEIGHT or offset > 0.7:
			offset = 99.0
		else:
			_place_ball(Vector2(met[1].x, met[1].y), met[1].z)
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
		ball_vel, ball_vz, _skill_mod(p.team), clamp(diff, 0.0, 1.0), offset, null, shy)
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
		# Struck where it is, carried or loose: the caman is steered to the
		# ball (the view's set_meet), not the ball pulled onto the caman.
		_place_ball(ball_pos, max(ball_z, 0.2))
	flight += 1
	ball_vel = res["ball_vel"]
	ball_vz = res["ball_vz"]
	ball_sim.set_spin(res["spin"])
	p.touch_block = 0.35
	last_team = p.team
	events.append({"type": "hit", "team": p.team, "kind": res["kind"], "curve": res["curve"], "shy": shy})
	if p == penalty_taker:
		_keeper_guesses(p)
		penalty_taker = null
	events.append({"type": "strike", "by": p, "at": ball_pos})
	if p == human or (p.team == human_side and shy):
		var note := {"thin": "Topped it", "fat": "Skied it", "heel": "Off the heel", "toe": "Off the toe"}
		if note.has(res["kind"]):
			_say(note[res["kind"]], 1.0)
		elif abs(res["curve"]) > 5.0 and req["speed"] > 22.0:
			_say("Bending it " + ("left" if res["curve"] > 0.0 else "right"), 1.0)


## Swept contact for a first-time hit. Through the hitting zone the caman head
## travels along the line of the hit, fast, low over the grass, while the ball
## goes its own way. Find when the two come closest within that sweep (or a
## frame either side, whichever is longer) and how close: a ball moving across
## the swing is met where the paths cross, rather than missed because it was a
## frame early or late. Returns [distance, where the ball was met].
func _sweep_meet(p: Player, req: Dictionary) -> Array:
	var spot := Body.rest_spot(p) + Vector3(p.facing.x, p.facing.y, 0.0) * 0.1
	var dir: Vector2 = req.get("dir", p.facing)
	var hs: float = ShintyStrike.head_speed(clampf(req.get("share", 0.6), 0.0, 1.0), p.r(req.get("skill_key", "shooting"))) * ShintyMatchAdapter.TO_YARDS
	var window: float = maxf(SWEEP_ZONE / maxf(hs, 1.0), 1.0 / 60.0)
	var ball := Vector3(ball_pos.x, ball_pos.y, ball_z)
	var bv := Vector3(ball_vel.x, ball_vel.y, ball_vz)
	var rel := ball - spot
	var relv := bv - Vector3(dir.x, dir.y, 0.0) * hs
	var t := 0.0
	if relv.length_squared() > 1e-6:
		t = clampf(-rel.dot(relv) / relv.length_squared(), -window, window)
	var at := ball + bv * t
	at.z = maxf(0.0, at.z)
	return [(rel + relv * t).length(), at]


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
	if human in throw_up_pair and not manual_step:
		# Aim the knock up the park with the stick, like lining up a free hit
		# (the arrow on the grass shows where it'll go).
		var raw := Input.get_vector("move_left", "move_right", "move_up", "move_down")
		var fwd := Vector2(attack_dir[human.team], 0)
		if raw.length() > 0.15 and raw.dot(fwd) > -0.3:
			var want: float = clamp(fwd.angle_to(raw), -THROW_UP_AIM_MAX, THROW_UP_AIM_MAX)
			throw_up_aim[human] = move_toward(throw_up_aim.get(human, 0.0), want, RESTART_AIM_RATE * 2.0 * dt)
	if not throw_up_tossed:
		state_timer -= dt
		if state_timer <= 0.0:
			_toss_throw_up()
		return
	throw_up_t += dt
	ball_z += ball_vz * dt
	ball_vz -= GRAVITY * dt
	if human in throw_up_pair and not manual_step and (Input.is_action_just_pressed("shoot") \
			or Input.is_action_just_pressed("hit") or Input.is_action_just_pressed("pass")):
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
		_say("Throw-up: aim with the stick, press Shoot as it drops", 1.6)


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
	# Knocked where the winner aimed it, less exactly the scrappier the contact.
	var dir := throw_up_dir(w).rotated(randfn(0.0, lerp(0.35, 0.08, clean)))
	ball_vel = dir * lerp(5.0, 15.0, clean)
	ball_vz = randf_range(0.5, 3.5)
	last_team = w.team
	events.append({"type": "strike", "by": w, "at": ball_pos})
	events.append({"type": "throw_up_won", "team": w.team})


## Where a centre in the throw-up means to knock it: up the park, off to
## one side or the other as they've aimed.
func throw_up_dir(p: Player) -> Vector2:
	return Vector2(attack_dir[p.team], 0).rotated(throw_up_aim.get(p, 0.0))


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
	events.append({"type": "hit", "team": p.team, "kind": "fresh_air", "curve": 0.0, "shy": shy, "by": p})
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
	_swing_follow_through(p)
	if keeps_ball and carrier == p:
		return   # swung over the top of it; it's still at your feet
	if carrier == null and ball_z > 1.0 and ball_vz > 0.0:
		ball_vz = 0.0


## A swing that misses the ball carries on through: an opponent standing in
## its path can take the caman and go down. The referee decides whether that
## was a foul (see referee.gd).
func _swing_follow_through(p: Player) -> void:
	for q in squads[1 - p.team]:
		var off: Vector2 = q.pos - p.pos
		var d := off.length()
		if d < 0.1 or d > Body.STICK_REACH + Body.BODY_R:
			continue
		if p.facing.length() < 0.01 or p.facing.normalized().dot(off / d) < 0.3:
			continue
		if randf() >= SWING_CATCH:
			return
		var had_ball: bool = carrier == q
		# From the front: the swing came from where the player was facing.
		var front: bool = q.facing.length() > 0.01 and q.facing.normalized().dot(-off / d) > 0.3
		trip(q)
		events.append({"type": "swing_contact", "by": p, "on": q, "at": q.pos, "front": front, "had_ball": had_ball})
		if had_ball:
			spill(q, p)
		return


## A caman caught a player who wasn't blocking: they are tripped, go down,
## and are back in play TRIP_TIME later. (A late blocker is only hurt: see
## swing_counters.)
func trip(q: Player) -> void:
	q.stagger = max(q.stagger, TRIP_TIME)
	q.swing_t = -1.0
	q.shielding = false
	anim(q, "stumble", clamp(q.stagger / 1.3, 0.0, 1.0))


func _take_control(p: Player) -> void:
	carrier = p
	last_team = p.team
	ball_z = 0.0
	ball_vz = 0.0
	gather_keeper = null
	p.think = _reaction(p.team) + (0.6 if p.is_keeper() else 0.0)
	# Whoever wins it on your side is yours, your keeper included: saves are
	# automatic, but once the keeper has it you move and clear it yourself.
	if p.team == human_side:
		human = p


## A tackle is a stick check (a hockey poke): lunge the caman at the ball.
## It has to physically reach the ball, and a carrier shielding the ball with
## their body is much harder to take it from.
func _try_tackle(t: Player, o: Player) -> void:
	if t.cooldown > 0.0 or protected_timer > 0.0 or carrier != o or t.stagger > 0.0 or not battle.is_empty():
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
	if o.shielding:
		chance *= 0.7    # braced for it, and strong on the ball
	chance *= lerp(1.0, 0.6, clamp((d - 1.2) / 1.0, 0.0, 1.0))
	# Rarely a clean steal: a poke that gets there usually starts a battle.
	var roll := randf()
	var won := roll < chance * 0.3
	events.append({"type": "tackle", "by": t, "on": o, "won": won, "at": o.pos, "one_hand": d > Body.TWO_HAND_REACH})
	if not won and roll < chance:
		battle = {"t": t, "o": o, "time": 0.0, "effort": {}}
		events.append({"type": "battle", "team": t.team, "at": ball_pos})
		t.cooldown = 0.2
		return
	if not won and shielded and d > Body.TWO_HAND_REACH and randf() < 0.06:
		# Reaching one-handed through the carrier's body for the ball: caman
		# on the man.
		events.append({"type": "foul", "kind": "hack", "by": t, "on": o, "at": o.pos, "severity": 0.3})
		trip(o)
		spill(o, t)
		t.cooldown = 1.0
		return
	if won:
		_steal(t, o)
	else:
		t.cooldown = 1.0


## The tackler has taken it: the ball is knocked off the carrier's stick.
func _steal(t: Player, o: Player) -> void:
	carrier = null
	o.touch_block = 0.5
	o.cooldown = 0.4
	o.swing_t = -1.0
	o.shielding = false
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


func in_battle(p: Player) -> bool:
	return not battle.is_empty() and (battle["t"] == p or battle["o"] == p)


## Two sticks on the ball: they lean in and fight for it. Strength, ball
## control, tackling and holding it up decide it, and so does effort (the
## player hammering a stick button). The carrier usually keeps it, or it
## squirts loose for a 50/50; only now and then does the tackler come away
## with it cleanly.
func _update_battle(dt: float) -> void:
	if battle.is_empty():
		return
	var t: Player = battle["t"]
	var o: Player = battle["o"]
	if state != State.PLAY or carrier != o or t.stagger > 0.0 or o.stagger > 0.0 \
			or t.pos.distance_to(ball_pos) > Body.max_reach(t) + 0.4:
		battle = {}   # knocked off, or the carrier got away from them
		t.cooldown = max(t.cooldown, 0.6)
		return
	battle["time"] += dt
	if battle["time"] < BATTLE_TIME:
		return
	var eff: Dictionary = battle["effort"]
	if t != human:
		eff[t] = randf_range(0.0, 14.0)
	if o != human:
		eff[o] = randf_range(0.0, 14.0)
	var so: float = o.r("control") * 0.55 + o.r("tackling") * 0.2 + (o.mass - 75.0) * 0.8 \
		+ (18.0 if o.shielding else 0.0) + eff.get(o, 0.0) + _skill_mod(o.team) * 100.0
	var st: float = t.r("tackling") * 0.6 + t.r("control") * 0.15 + (t.mass - 75.0) * 0.8 \
		+ eff.get(t, 0.0) + _skill_mod(t.team) * 100.0
	var diff: float = (so - st) / 40.0 + randfn(0.0, 0.5)
	battle = {}
	if diff > -0.1:
		# The carrier rides it and keeps the ball.
		t.cooldown = 1.2
		t.touch_block = 0.6
		events.append({"type": "battle_kept", "team": o.team})
	elif diff < -0.8:
		events.append({"type": "battle_won", "team": t.team})
		_steal(t, o)
	else:
		# Neither gets it: the ball squirts out between them.
		carrier = null
		last_team = t.team
		o.touch_block = 0.25
		t.touch_block = 0.25
		o.shielding = false
		var across := (o.pos - t.pos).orthogonal().normalized()
		if randf() < 0.5:
			across = -across
		ball_vel = across.rotated(randf_range(-0.6, 0.6)) * randf_range(3.0, 6.0)
		ball_vz = 0.0
		events.append({"type": "battle_loose", "team": o.team})
		events.append({"type": "clash", "team": t.team})


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
## Puts the ball somewhere it didn't fly to on its own (onto the caman that met
## it, a chest, a glove). The jump is added to ball_shift so the view can draw
## the ball from where it was and blend the gap out over a few frames.
func _place_ball(at: Vector2, z: float) -> void:
	ball_shift += Vector3(at.x - ball_pos.x, at.y - ball_pos.y, z - ball_z)
	ball_pos = at
	ball_z = z


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
		and not p.shielding and not in_battle(p) \
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
	var in_reach: bool = ball_pos.distance_to(c.pos) < DRIBBLE_REACH - 0.2 * assist
	# The ball has dropped level with or behind the player (a turn, or they
	# ran onto it): rather than drag it along behind, they reach back with
	# the caman and touch it round in front of them again.
	var ahead: float = (ball_pos - c.pos).dot(dir)
	if ahead < 0.35 and ball_pos.distance_to(c.pos) < DRIBBLE_REACH + 0.3 \
			and head.distance_to(ball_pos) < tap_r + 0.5:
		var front: Vector2 = c.pos + c.vel * 0.3 + dir * (0.9 - 0.2 * assist)
		dribble_vel = ((front - ball_pos) / 0.3).limit_length(12.0)
		dribble_taps += 1
		return
	if in_reach and head.distance_to(ball_pos) < tap_r and dribble_vel.dot(dir) < run + 0.5:
		# The tap: just firm enough to roll a yard or so ahead, so the caman
		# is back on it within a stride; better ball players keep it closer,
		# and the player's touches are softer still.
		var lead: float = lerp(1.7, 1.1, c.r("control") / 100.0)
		lead = lerp(lead, 0.6, assist)   # the player keeps it tight, to turn with it
		dribble_vel = dir * max(run + lead, 2.5)
		dribble_taps += 1
		return
	var on_stick: bool = head.distance_to(ball_pos) < 0.5
	if assist > 0.0 and on_stick and dribble_vel.length() > 0.3:
		# The player's caman shepherds a rolling touch round as they turn.
		var bend: float = dribble_vel.angle_to(dir)
		dribble_vel = dribble_vel.rotated(clampf(bend, -3.0 * dt, 3.0 * dt))
	var overrun: bool = (ball_pos - head).dot(dir) < -0.1
	if assist > 0.0 and on_stick \
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
			if randf() > (0.2 + (o.r("tackling") - c.r("control")) / 250.0) * (1.0 - 0.5 * assist):
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
	var body: Player = null
	for p in players:
		if p.touch_block > 0.0 or p.stagger > 0.0:
			continue
		var keeping: bool = p.is_keeper() and p.pos.distance_to(own_goal(p.team)) < 14.0
		var d: float = Body.swept_distance(p.stick_prev, p.stick, before, now)
		var reach := Body.CONTACT_R
		if keeping:
			# Hands and body: anywhere within the keeper's reach and height.
			var body_d: float = Body.path_distance(Vector3(p.pos.x, p.pos.y, 0.0), Vector3(before.x, before.y, 0.0), Vector3(now.x, now.y, 0.0))
			var hands: float = 0.75 + p.r("keeping") / 100.0 * 0.45 + (0.8 if p.lunge > 0.0 else 0.0)
			if body_d < hands and min(before.z, now.z) < KEEPER_REACH_HEIGHT:
				d = min(d, body_d * Body.CONTACT_R / hands)
		if keeping and d < reach and _keeper_beaten(p, sp):
			continue
		if d < reach and d < best_d:
			best = p
			best_d = d
			best_keeper = keeping
		elif body == null and min(before.z, now.z) < Body.BODY_HEIGHT:
			# Any player, either side, can stop the ball with the body or feet.
			var low: bool = min(before.z, now.z) < FEET_HEIGHT
			var bd: float = Body.path_distance(Vector3(p.pos.x, p.pos.y, now.z), before, now)
			var extra: float = 0.0
			if low:
				# A ground ball just wide of them: they jump across to it (not mid-swing).
				extra = FEET_EXTRA + (_hop_reach(p) if p.swing_t < 0.0 and p.hop_t <= 0.0 else 0.0)
			if bd < Body.BODY_BLOCK_R + extra:
				body = p
	if best == null:
		if body != null and sp > 1.5:
			_body_touch(body, sp)
		return
	var p := best
	p.touch_block = 0.25
	events.append({"type": "touch", "by": p, "at": ball_pos, "hands": best_keeper and p.pos.distance_to(ball_pos) > Body.CONTACT_R})
	# One-handed at full stretch you can stop or tap a ball, rarely control it.
	var grip: float = 0.55 if p.one_hand and not best_keeper else 1.0
	if ball_z > FEET_HEIGHT and not best_keeper:
		grip *= lerp(1.0, 0.5, _running(p))   # a ball in the air is hard to kill on the run
	flight += 1
	if not best_keeper:
		if ball_z <= FEET_HEIGHT and sp < (8.0 + p.r("control") * 0.08) * grip:
			_take_control(p)
			anim(p, "trap")
			return
		_stick_touch(p, sp, grip)
		return
	var stretch: float = clamp((p.pos.distance_to(ball_pos) - 1.0) / 1.2, 0.0, 1.0)
	var chance: float
	if best_keeper:
		chance = clamp(0.36 + p.r("keeping") / 100.0 * 0.5 - (sp - 20.0) * 0.012 - stretch * 0.3 + _skill_mod(p.team), 0.2, 0.95)
	# Straight at the keeper: it hits the body. Low, the feet are together
	# and the stick is down in front of them, so it never goes through the
	# legs; higher, it comes off the body or the stick and back out.
	# (Judged along where the ball is going, not just where it is now.)
	var ahead3 := Vector3(ball_pos.x + ball_vel.x * 0.3, ball_pos.y + ball_vel.y * 0.3, ball_z)
	var at_body: bool = best_keeper and ball_z < Body.BODY_HEIGHT \
		and Body.path_distance(Vector3(p.pos.x, p.pos.y, ball_z), Vector3(ball_pos.x, ball_pos.y, ball_z), ahead3) < Body.BODY_R + 0.3
	if at_body and ball_z < FEET_HEIGHT + 0.25:
		_keeper_save(p, "feet")
		return
	if at_body:
		chance = maxf(chance, 0.8)
	if randf() < chance or at_body:
		if best_keeper:
			# In the air, the keeper turns it away with the caman (a keeper
			# may deflect the ball but not catch it).
			var how := "smother"
			if ball_z > KEEPER_STICK_HEIGHT or (at_body and randf() >= chance):
				how = "stick"
			_keeper_save(p, how)
		else:
			_take_control(p)
			anim(p, "trap")
	elif randf() < 0.5:
		# Fingertips: a touch that takes the pace off but doesn't stop it.
		ball_vel = ball_vel.rotated(randf_range(-0.3, 0.3)) * 0.7
		last_team = p.team
	else:
		# Off the keeper's caman: wood, so it comes off it rather than through it.
		_stick_rebound(p, p.r("keeping") / 100.0, ball_z > FEET_HEIGHT)


## A shot on target reaching the keeper: are they beaten by it before they
## can get a touch? Judged once a shot. Most shots are kept out, the hard
## ones less often, and one hit high into a corner beats the keeper more
## often than not. A beaten keeper is left grasping as it goes by.
func _keeper_beaten(k: Player, sp: float) -> bool:
	if k.beat_flight == flight:
		return false
	var g := own_goal(k.team)
	var toward: float = -attack_dir[k.team]
	if ball_vel.x * toward < 5.0:
		return false
	var t: float = (g.x - ball_pos.x) / ball_vel.x
	if t < 0.0 or t > 1.5:
		return false
	var y: float = ball_pos.y + ball_vel.y * t
	var z: float = ball_z + ball_vz * t - 0.5 * GRAVITY * t * t
	if absf(y - g.y) > GOAL_W / 2.0 or z > CROSSBAR or z < -0.5:
		return false   # going wide or over: nothing to beat
	k.beat_flight = flight
	if absf(y - k.pos.y) < Body.BODY_R + 0.3 and z < Body.BODY_HEIGHT:
		return false   # straight at them: it hits the keeper
	var hard: float = clampf((sp - 20.0) / 15.0, 0.0, 1.0)
	var corner: bool = z > KEEPER_HIGH and absf(y - g.y) > GOAL_W / 2.0 - CORNER_IN
	var beat: float = KEEPER_BEAT + KEEPER_BEAT_HARD * hard + (KEEPER_BEAT_CORNER if corner else 0.0) \
		- (k.r("keeping") - 60.0) / 100.0 * 0.4 - _skill_mod(k.team)
	if randf() >= clampf(beat, 0.05, 0.9):
		return false
	k.touch_block = maxf(k.touch_block, t + 0.2)
	return true


## An outfield player's caman has got to the ball. Nothing goes through a
## stick: it is controlled, knocked down, cleared, or comes off the wood.
## Along the ground a good touch kills it. In the air, control decides:
## a good player holds the caman up sideways with the curve of the bas down
## so the face knocks it down onto the grass, and a back under pressure in
## their own half swats it away with the back of the stick, like a shy. A
## poor one has it ping off the stick (or misses it altogether, see
## player_physics, or takes it on the body instead).
func _stick_touch(p: Player, sp: float, grip: float) -> void:
	var c: float = p.r("control") / 100.0
	var stretch: float = clamp((p.pos.distance_to(ball_pos) - 1.0) / 1.2, 0.0, 1.0)
	var mate: float = 0.15 if p.team == last_team else 0.0
	if ball_z <= FEET_HEIGHT:
		var chance: float = clamp(c * (18.0 / sp) * lerp(1.0, 0.7, stretch) * grip + _skill_mod(p.team) + mate, 0.05, 0.9)
		if randf() < chance:
			_take_control(p)
			anim(p, "trap")
		else:
			_stick_rebound(p, c, false)
		return
	var defending: bool = own_frac(p.team, ball_pos.x) < 0.4 and (p.role == "DEF" or _nearest_opponent_dist(p) < 4.0)
	if defending and ball_z > 0.8 and not p.one_hand:
		var clean: float = clamp(lerp(0.4, 0.92, c) - stretch * 0.25 - maxf(sp - 20.0, 0.0) * 0.01 + _skill_mod(p.team), 0.15, 0.95)
		if randf() < clean:
			_air_clear(p, c)
		else:
			_stick_rebound(p, c, true)
		return
	var kill: float = clamp((c * 1.2 - 0.25) * clamp(16.0 / maxf(sp, 1.0), 0.4, 1.4) * lerp(1.0, 0.6, stretch) * grip \
		+ _skill_mod(p.team) + mate, 0.03, 0.95)
	if randf() < kill:
		_air_kill(p, c)
	else:
		_stick_rebound(p, c, true)


## Where a player who has just killed the ball puts it: the way they want to
## go (or are facing), edged away from the nearest opponent.
func _useful_dir(p: Player) -> Vector2:
	var want: Vector2 = p.desired if p.desired.length() > 0.5 else p.facing
	want = want.normalized()
	var near: Player = null
	var nd := 4.0
	for o in squads[1 - p.team]:
		var d: float = o.pos.distance_to(p.pos)
		if d < nd:
			nd = d
			near = o
	if near != null and nd > 0.05:
		want = (want - (near.pos - p.pos) / nd * 0.6 * (1.0 - nd / 4.0)).normalized()
	return want if want.length() > 0.1 else p.facing


## Knocked down out of the air with the face of the bas: it drops onto the
## grass just in front, going where the player wants it, ready to gather.
func _air_kill(p: Player, c: float) -> void:
	ball_vel = _useful_dir(p) * lerp(0.8, 2.0, c) + p.vel * 0.7
	ball_vz = -lerp(2.0, 4.0, c)
	ball_sim.set_spin(Vector3.ZERO)
	p.touch_block = 0.15
	last_team = p.team
	anim(p, "air_kill")
	events.append({"type": "air_kill", "team": p.team})


## A back clearing it first time out of the air with the back of the stick,
## swatted away up the park like a shy, off towards the wing away from trouble.
func _air_clear(p: Player, c: float) -> void:
	var up: Vector2 = (target_goal(p.team) - p.pos).normalized()
	var wing: float = signf(PITCH.y / 2.0 - ball_pos.y)
	var dir: Vector2 = up.rotated(-wing * attack_dir[p.team] * randf_range(0.0, 0.5) + randfn(0.0, lerp(0.45, 0.12, c)))
	if dir.dot(up) < 0.2:
		dir = up
	ball_vel = dir * lerp(13.0, 22.0, p.r("shooting") / 100.0) * randf_range(0.85, 1.05)
	ball_vz = randf_range(3.0, 6.0)
	ball_sim.set_spin(Vector3.ZERO)
	p.touch_block = 0.35
	last_team = p.team
	anim(p, "air_clear")
	events.append({"type": "hit", "team": p.team, "kind": "clear", "curve": 0.0, "shy": false})
	events.append({"type": "strike", "by": p, "at": ball_pos})


## Off the wood: the ball bounces off the caman like off a plank, the face
## pointing back at it. Soft hands (control) take more of the pace off and
## send it roughly where the player wants; poor ones, or a ball in the air,
## have it ping off anywhere.
func _stick_rebound(p: Player, c: float, air: bool) -> void:
	var head := Vector2(p.stick.x, p.stick.y)
	var incoming := ball_vel.normalized() if ball_vel.length() > 0.1 else (head - p.pos).normalized()
	var out := head - p.pos
	out = out.normalized() if out.length() > 0.05 else p.facing
	var n := (-incoming + out * 0.5).normalized()
	var e: float = lerp(0.6, 0.3, c) * (0.75 if p.one_hand else 1.0)
	if air:
		e = lerp(0.75, 0.35, c)
	var rel := ball_vel - p.vel
	var vn := rel.dot(n)
	if vn < 0.0:
		var tang := rel - n * vn
		rel = -n * vn * e + tang * 0.7
	var v := rel + p.vel
	# Some say in where it goes, and a poor touch scatters it.
	var steer := clampf(v.angle_to(_useful_dir(p)), -0.35, 0.35) * c
	v = v.rotated(steer + randfn(0.0, lerp(0.7, 0.12, c) * (1.3 if air else 1.0)))
	ball_vel = v
	if air:
		ball_vz = absf(ball_vz) * e * 0.5 + randf_range(0.5, 3.5) * (1.2 - c)
	else:
		ball_vz = max(0.0, ball_vz) + randf_range(0.0, 1.0) * (1.0 - c)
	ball_sim.set_spin(Vector3.ZERO)
	p.touch_block = 0.3
	last_team = p.team
	events.append({"type": "stick_rebound", "team": p.team, "air": air})


## 0 standing still, 1 flat out.
func _running(p: Player) -> float:
	return clamp(p.vel.length() / p.top_speed(), 0.0, 1.0)


## The ball has hit a player's body or feet (legal for everyone in shinty).
## Coming at them at a pace they can handle, they kill it: feet planted and
## together for a ball along the ground, or off the body for one in the air,
## and it drops dead in front of them to gather with the caman. Otherwise it
## comes off them, losing most of its pace.
func _body_touch(p: Player, sp: float) -> void:
	var feet: bool = ball_z < FEET_HEIGHT
	var at_them: bool = ball_vel.dot(p.pos - ball_pos) > 0.0
	var limit: float = BODY_STOP_SPEED + p.r("control") * 0.12
	if p.team == last_team and (sp >= limit or not at_them):
		return   # a team-mate's hit: they get out of its way, or let it run
	var chance: float = clamp(0.95 - sp / limit * 0.45 + (0.05 if feet else -0.15), 0.2, 0.95)
	if not feet:
		chance *= lerp(1.0, 0.35, _running(p))   # killing a ball in the air on the run is hard
	last_team = p.team
	p.touch_block = 0.12
	events.append({"type": "touch", "by": p, "at": ball_pos, "hands": false, "body": true})
	if feet and at_them and sp < limit:
		_feet_stop(p, sp, limit)
		return
	if at_them and sp < limit and randf() < chance:
		var front := (ball_pos - p.pos)
		front = front.normalized() if front.length() > 0.05 else p.facing
		_place_ball(p.pos + front * (Body.BODY_R + 0.12), ball_z)
		# Softened, and dropped where it's useful: a yard or so the way they
		# want to go, moving with them; better players place it better.
		ball_vel = _useful_dir(p) * lerp(0.4, 1.6, p.r("control") / 100.0) + p.vel * 0.6
		ball_vz = 0.0 if feet else min(ball_vz, 0.0)
		ball_sim.set_spin(Vector3.ZERO)
		flight += 1
		# Seen: feet together for a ball along the ground, legs together and
		# straight like a pencil for one at knee to waist height, the chest
		# for anything higher.
		anim(p, "feet_trap" if feet else ("pencil" if ball_z < THIGH_HEIGHT else "chest_trap"))
		events.append({"type": "body_stop", "team": p.team, "feet": feet})
		return
	if sp > 4.0:
		flight += 1
		# Off the legs or body: it loses most of its pace and kicks off sideways.
		var n := (ball_pos - p.pos).normalized()
		ball_vel = (ball_vel * 0.25).bounce(n) if ball_vel.dot(n) < 0.0 else ball_vel * 0.4
		ball_vel = ball_vel.rotated(randf_range(-0.6, 0.6))
		ball_vz = max(0.0, ball_vz * 0.3)
		p.touch_block = 0.3
		anim(p, "stumble", 0.2)   # it catches them: a flinch as it comes off them
		events.append({"type": "block", "team": p.team})


## How far sideways a player will jump to get their feet in line with a
## ground ball: less on the run.
func _hop_reach(p: Player) -> float:
	return HOP_REACH * lerp(0.5, 1.0, p.r("control") / 100.0) * lerp(1.0, 0.4, _running(p))


## A ground ball at their feet: they jump sideways, feet together, into its
## line. Control decides how well they judge the jump: a good player lands
## on it and kills it dead; a poor one now and then jumps short or long, and
## the ball clips a boot and bounces on past.
func _feet_stop(p: Player, sp: float, limit: float) -> void:
	var dir := ball_vel.normalized()
	var rel := ball_pos - p.pos
	var off := rel - dir * rel.dot(dir)   # from their feet to the ball's line
	var need := off.length()
	var side := off / need if need > 0.02 else Vector2(-dir.y, dir.x) * (1.0 if randf() < 0.5 else -1.0)
	var c: float = p.r("control") / 100.0
	var sigma: float = lerp(0.42, 0.06, c) * (0.6 + 0.5 * sp / limit) * (0.7 + need) * lerp(1.0, 1.6, _running(p))
	var err: float = randfn(0.0, sigma)   # < 0 jumped short, > 0 jumped long
	var land := need + err
	p.hop = side * land
	p.hop_t = HOP_TIME if absf(land) > 0.05 else 0.0
	p.touch_block = 0.2
	anim(p, "feet_trap")
	if absf(err) <= FEET_GAP:
		# Landed on it: dead between the feet, a touch in front.
		var at := p.pos + p.hop
		var front := (ball_pos - at)
		front = front.normalized() if front.length() > 0.05 else p.facing
		_place_ball(at + front * (Body.BODY_R + 0.12), ball_z)
		ball_vel = _useful_dir(p) * lerp(0.4, 1.6, p.r("control") / 100.0) + p.vel * 0.6
		ball_vz = 0.0
		ball_sim.set_spin(Vector3.ZERO)
		events.append({"type": "body_stop", "team": p.team, "feet": true})
		return
	# Misjudged: it catches the edge of a boot and bounces on past, off to
	# the side they missed it on.
	var away: float = -signf(err)
	ball_vel = ball_vel.rotated(away * randf_range(0.15, 0.4) * signf(dir.cross(side))) * randf_range(0.55, 0.8)
	ball_vz = randf_range(0.8, 2.0)
	p.touch_block = 0.45
	events.append({"type": "block", "team": p.team, "bounced_past": true})


## A save: the keeper smothers it with stick, hand or body and the ball drops
## dead at their feet, then they gather it. No rebounds.
func _keeper_save(k: Player, how: String = "smother") -> void:
	# The caman (or glove) is where the ball is stopped, not a yard short of it.
	var flat := ball_pos - k.pos
	var reach: float = Body.max_reach(k)
	var at := k.pos + flat.limit_length(reach)
	_place_ball(at, ball_z)
	k.stick = Vector3(at.x, at.y, min(ball_z, KEEPER_REACH_HEIGHT))
	if how == "stick":
		# Turned away with the caman: the ball flies back out, away from the
		# goal and off to the side it was going, and is anyone's.
		var sp: float = ball_vel.length()
		var out := Vector2(attack_dir[k.team], 0.0)
		var wide: float = signf(ball_pos.y - own_goal(k.team).y)
		if wide == 0.0:
			wide = 1.0 if randf() < 0.5 else -1.0
		ball_vel = (out * randf_range(0.3, 0.45) + Vector2(0, wide) * randf_range(0.15, 0.35)) * maxf(sp, 10.0)
		ball_vz = randf_range(1.0, 4.0)
		ball_sim.set_spin(Vector3.ZERO)
		last_team = k.team
		k.touch_block = 0.4
		k.save_point = null
		var side := signf(Vector2(0, ball_pos.y - k.pos.y).dot(Body.right_of(k)))
		anim(k, "save_high_right" if side >= 0.0 else "save_high_left")
		events.append({"type": "save", "team": k.team, "by": k, "deflect": true})
		_say("Turned away!", 1.0)
		return
	if how == "feet":
		anim(k, "save_feet")
	elif k.lunge <= 0.0:
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
	if label == "Hit-out" and _keeper_of(team) != null:
		taker = _keeper_of(team)   # the keeper takes the bye-hits
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
	restart_target = null
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
	_say("Bye-hit" if label == "Hit-out" else label, 1.2 if set_piece == "" else protected_timer)
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
	# The taker stands over the ball and hits it (or passes it) from the
	# spot, aiming with the stick like a hit-out; they can't run with it.
	# Everyone else plays on and can make runs.
	set_piece = "Free hit"
	set_piece_taker = taker
	restart_base = toward
	restart_aim = 0.0
	restart_target = null
	taker.think = FREE_HIT_PAUSE
	protected_timer = FREE_HIT_PAUSE
	_say(text, 2.2)
	events.append({"type": "Free hit", "team": team, "taker": taker})


## A penalty hit, 20 yards straight out from the goal. Everyone but the taker
## and the keeper goes back behind the ball.
func award_penalty(team: int, text: String, taker: Player = null) -> void:
	var goal := target_goal(team)
	var spot := goal - Vector2(attack_dir[team] * PENALTY_SPOT, 0)
	if taker == null:
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
	var toward := (goal - spot).normalized()
	_place_taker(taker, spot, toward)
	penalty_taker = taker
	penalty_side = 0.0
	pen_idle = 0.0
	# Taken like a hit-out: play stops, the taker stands over the ball on the
	# spot and aims it (the camera comes round behind), then strikes it.
	set_piece = "Penalty hit"
	set_piece_taker = taker
	restart_base = toward
	restart_aim = 0.0
	restart_target = null
	taker.think = SET_PIECE_PAUSE
	protected_timer = SET_PIECE_PAUSE
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


## A penalty hit is struck: the keeper has had to guess a side. Guess wrong
## and they're diving the other way, with no chance of it.
func _keeper_guesses(taker: Player) -> void:
	var keeper := _keeper_of(1 - taker.team)
	if keeper == null or ball_vel.length() < 5.0 or absf(ball_vel.y) < 0.3:
		return
	if randf() > PEN_GUESS + keeper.r("keeping") / 100.0 * 0.2:
		keeper.touch_block = 1.2
		keeper.save_point = null
		var dive_right: bool = Vector2(0, -signf(ball_vel.y)).dot(Body.right_of(keeper)) > 0.0
		anim(keeper, "save_right" if dive_right else "save_left")


## The computer strikes its penalty hits at goal once players have stood back.
## Like a free hit, the taker stands over the ball and lines it up first:
## they pick a corner early and turn the aim round to it, then hit it.
func _take_penalty(dt: float) -> void:
	if penalty_taker == null:
		return
	if carrier != penalty_taker:
		penalty_taker = null
		return
	if penalty_taker == human:
		pen_idle += dt
		if pen_idle < PEN_IDLE_MAX:
			return   # yours to hit (left alone long enough, it's hit for you)
	var p := penalty_taker
	var goal := target_goal(p.team)
	if penalty_side == 0.0:
		penalty_side = 1.0 if randf() < 0.5 else -1.0
	var aim := goal + Vector2(0, penalty_side * (GOAL_W / 2.0 - SHOT_INSIDE))
	var want: float = clamp(restart_base.angle_to(aim - p.pos), -PI / 2.0, PI / 2.0)
	restart_aim = move_toward(restart_aim, want, RESTART_AIM_RATE * dt)
	p.facing = restart_base.rotated(restart_aim)
	if protected_timer <= 0.2:
		_ai_shoot(p, penalty_side)
		penalty_side = 0.0


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
	if shootout:
		_shootout_kick_done(true)
		return
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


# ---------------------------------------------------------------- penalty shootout

## Level after extra time: five penalty hits each from the spot, taken in
## turn at the same end, then sudden death. Your team's takers are yours to
## hit; the computer keeps goal for both sides.
func _start_shootout() -> void:
	shootout = true
	state = State.PLAY
	shoot_kicks = [[], []]
	shoot_turn = 0
	for t in 2:
		# Best hitters first; round again if it goes on long enough.
		var order: Array = squads[t].filter(func(p): return not p.is_keeper())
		order.sort_custom(func(a, b): return a.r("shooting") > b.r("shooting"))
		shoot_order[t] = order
	shoot_wait = SHOOTOUT_PAUSE
	shoot_live = false
	_say("Still level after extra time\nPenalty shootout: five each, then sudden death", SHOOTOUT_PAUSE)
	events.append({"type": "shootout"})
	_line_up_for_shootout(-1)


func _step_shootout(dt: float) -> void:
	if shoot_wait > 0.0:
		shoot_wait -= dt
		for p in players:
			p.desired = Vector2.ZERO
			_move(p, dt)
		_separate()
		if shoot_wait <= 0.0:
			_shootout_next_kick()
		return
	_update_players(dt)
	_take_penalty(dt)
	_update_ball(dt)
	if not shoot_live:
		return
	if penalty_taker == null and set_piece_taker_now() == null:
		shoot_t += dt
	for i in range(shoot_event_i, events.size()):
		if events[i]["type"] == "save":
			_shootout_kick_done(false)   # the keeper's kept it out
			return
	var keeper := _keeper_of(1 - shoot_turn)
	var slow: bool = ball_vel.length() < 1.5 and ball_z < 0.3
	if ball_pos.x < 0.0 or ball_pos.x > PITCH.x or ball_pos.y < 0.0 or ball_pos.y > PITCH.y:
		var in_goal: bool = ball_pos.x > PITCH.x and absf(ball_pos.y - PITCH.y / 2.0) < GOAL_W / 2.0 and ball_z < CROSSBAR
		_shootout_kick_done(in_goal)
	elif (carrier != null and carrier == keeper) or (shoot_t > 0.8 and slow) or shoot_t > 4.0:
		_shootout_kick_done(false)


func _shootout_next_kick() -> void:
	var t := shoot_turn
	var order: Array = shoot_order[t].filter(func(p): return p in players)
	if order.is_empty():
		_shootout_kick_done(false)
		return
	var taker: Player = order[shoot_kicks[t].size() % order.size()]
	_line_up_for_shootout(t)
	award_penalty(t, "Penalty %d: %s, #%d %s" % [shoot_kicks[t].size() + 1, teams[t]["name"], taker.number, taker.data.get("name", "")], taker)
	# Nobody else is involved: the rest wait in the centre circle.
	for p in players:
		if p != taker and not (p.is_keeper() and p.team != t):
			p.pos = _shootout_spot(p)
			p.vel = Vector2.ZERO
	if human_side == t:
		human = taker   # you hit your own team's penalties
	shoot_live = true
	shoot_t = 0.0
	shoot_event_i = events.size()


## Every kick is at the same end: point the taking side at the east goal.
func _line_up_for_shootout(t: int) -> void:
	if t >= 0:
		attack_dir = [1, -1] if t == 0 else [-1, 1]
	for p in players:
		if p.is_keeper() and t >= 0 and p.team != t:
			continue
		p.pos = _shootout_spot(p)
		p.vel = Vector2.ZERO
		p.facing = Vector2(1, 0)
		p.swing_t = -1.0


func _shootout_spot(p: Player) -> Vector2:
	if p.is_keeper():
		return Vector2(PITCH.x / 2.0 + (4.0 if p.team == 0 else -4.0), PITCH.y / 2.0 + 9.0)
	var i: int = p.number % 15
	var row := Vector2(PITCH.x / 2.0 + (i - 7) * 0.9, PITCH.y / 2.0 + (-3.0 if p.team == 0 else 3.0))
	return row


func _shootout_kick_done(scored: bool) -> void:
	if not shoot_live:
		return
	shoot_live = false
	var t := shoot_turn
	shoot_kicks[t].append(scored)
	penalty_taker = null
	carrier = null
	_clear_set_piece()
	ball_vel = Vector2.ZERO
	ball_vz = 0.0
	charge = -1.0
	var got := [shoot_kicks[0].count(true), shoot_kicks[1].count(true)]
	var took := [shoot_kicks[0].size(), shoot_kicks[1].size()]
	events.append({"type": "shootout_kick", "team": t, "scored": scored, "tally": got.duplicate()})
	var tally := "%s %d - %d %s" % [teams[0]["name"], got[0], got[1], teams[1]["name"]]
	var winner := -1
	if took[0] <= SHOOTOUT_KICKS and took[1] <= SHOOTOUT_KICKS:
		# Five each: over once one side can't catch the other.
		for a in 2:
			if got[a] > got[1 - a] + (SHOOTOUT_KICKS - took[1 - a]):
				winner = a
	if winner < 0 and took[0] == took[1] and took[0] >= SHOOTOUT_KICKS and got[0] != got[1]:
		winner = 0 if got[0] > got[1] else 1   # sudden death
	if winner >= 0:
		shootout = false
		state = State.FULL_TIME
		shoot_result = got
		_say("%s win %d - %d on penalties\nFull time after extra time" % [teams[winner]["name"], got[winner], got[1 - winner]], 9999.0)
		var game := get_node_or_null("/root/Game") if is_inside_tree() else null
		if game:
			game.last_result = {"home": teams[0]["name"], "away": teams[1]["name"], "score": score.duplicate(), "penalties": got.duplicate()}
		events.append({"type": "half_end", "half": half, "score": score.duplicate()})
		return
	_say(("Scored!" if scored else "Missed!") + "\n" + tally, SHOOTOUT_PAUSE)
	shoot_turn = 1 - t
	shoot_wait = SHOOTOUT_PAUSE


## Length of the current half: extra time halves are 15 minutes to a 45.
func half_length() -> float:
	return half_seconds if half <= 2 else half_seconds / 3.0


## Match time in seconds as the clock on the TV shows it (45-minute halves,
## then 15-minute halves of extra time).
func match_seconds() -> float:
	var start: float = [0.0, 45.0, 90.0, 105.0][clampi(half - 1, 0, 3)] * 60.0
	var mins: float = 45.0 if half <= 2 else 15.0
	return start + clock / half_length() * mins * 60.0


func match_minute() -> int:
	return int(match_seconds() / 60.0)


## Half time and full time: play is over, so the players walk off towards
## their team's dugout (or, before extra time, just stand and get a breather).
func _walk_off(dt: float, to_dugout: bool) -> void:
	for p in players:
		p.sprinting = false
		p.shielding = false
		p.swing_t = -1.0
		p.desired = Vector2.ZERO
		if to_dugout:
			# Gathered along the touchline in front of the dugout, a little
			# spread out so they don't all walk to one spot.
			var d: Vector2 = dugout(p.team) + Vector2((p.number - 8) * 0.9, 0.0)
			var off: Vector2 = d - p.pos
			if off.length() > 0.6:
				p.desired = off.normalized() * WALK_SPEED * lerpf(0.9, 1.1, p.number / 15.0)
		_move(p, dt)
	_separate()


## Where a team's dugout is on the near touchline, in pitch yards (as the
## benches in subs_bench.gd place it: the home side's is in the half it
## defends first). Players walking off stop on the line in front of it.
func dugout(t: int) -> Vector2:
	return Vector2(PITCH.x / 2.0 + (-9.84 if t == 0 else 9.84), -1.2)
