extends "res://scripts/match.gd"
## Training ground: one player and a ball on an empty pitch, for practising
## moves and for checking animations. It is the real match (same controls,
## physics, contact and poses), with the clock, referee, team AI and
## substitutions left out. Only the keeper and, if wanted, one defender are
## out there with you.
##
## On top of the match controls:
##   D-pad left/right  [ ]   pick a move from the list
##   R3 (right stick)  T     play it (a pose, a ball fed to you, a set piece or a run)
##   D-pad down        Backspace  ball back at your feet
##   D-pad up          Tab   slow motion: full, half, quarter, a tenth
##   View (Back)       V     close camera (right stick or , . to go round, zoom with right stick)
##   Pause: Y / K keeper on or off, X / J defender on or off, Back / M to the menu

const PracticeView := preload("res://scripts/practice_view.gd")
const PracticeHud := preload("res://scripts/practice_hud.gd")

const SPEEDS := [1.0, 0.5, 0.25, 0.1]
const BALL_BACK_AFTER := 1.2   # seconds the keeper or defender holds it before it comes back to you
const LOOSE_BACK_AFTER := 2.0  # a slow ball this far from you comes back after this long
const LOOSE_FAR := 12.0
const RESET_X := 35.0          # you start this many yards out from the goal you attack

## [label, kind, what, power]. Kinds: "pose" plays a one-off animation on
## your player with no ball involved; "feed" sends a ball at you to deal
## with for real; "set" sets up a restart; "run" runs a circle on its own
## until you touch the stick.
const MOVES := [
	["Full swing", "pose", "swing", 1.0],
	["Half swing", "pose", "swing", 0.5],
	["Pass", "pose", "pass", 0.6],
	["Volley", "pose", "volley", 1.0],
	["Shy (overhead)", "pose", "shy", 1.0],
	["Block", "pose", "block", 1.0],
	["Cleek", "pose", "cleek", 1.0],
	["Barge", "pose", "barge", 1.0],
	["Poke", "pose", "poke", 1.0],
	["Tackle", "pose", "tackle", 1.0],
	["Trap on the caman", "pose", "trap", 1.0],
	["Feet trap", "pose", "feet_trap", 1.0],
	["Pencil (feet together)", "pose", "pencil", 1.0],
	["Thigh trap", "pose", "thigh_trap", 1.0],
	["Chest trap", "pose", "chest_trap", 1.0],
	["Air kill", "pose", "air_kill", 1.0],
	["Air clear", "pose", "air_clear", 1.0],
	["Stumble", "pose", "stumble", 0.3],
	["Knocked down", "pose", "stumble", 1.0],
	["Keeper save left", "pose", "save_left", 1.0],
	["Keeper save right", "pose", "save_right", 1.0],
	["Keeper save high left", "pose", "save_high_left", 1.0],
	["Keeper save high right", "pose", "save_high_right", 1.0],
	["Keeper save at feet", "pose", "save_feet", 1.0],
	["Celebrate", "pose", "celebrate", 1.0],
	["Ball fed: along the grass", "feed", "ground", 0.0],
	["Ball fed: bouncing", "feed", "bounce", 0.0],
	["Ball fed: dropping from high", "feed", "high", 0.0],
	["Ball fed: chest high", "feed", "chest", 0.0],
	["Ball fed: hard drive", "feed", "drive", 0.0],
	["Take a shy", "set", "Shy", 0.0],
	["Take a free hit", "set", "Free hit", 0.0],
	["Take a penalty", "set", "Penalty hit", 0.0],
	["Take a corner", "set", "Corner", 0.0],
	["Run a circle: walk", "run", "walk", 0.0],
	["Run a circle: jog", "run", "jog", 0.0],
	["Run a circle: sprint", "run", "sprint", 0.0],
]

var move_index := 0
var speed_index := 0
var close_cam := false
var keeper_on := true
var defender_on := false
var goals := 0
var practice_keeper: Player = null
var practice_defender: Player = null
var circle_pace := ""             # "walk", "jog" or "sprint" while running a circle on its own
var circle_centre := Vector2.ZERO
var _held_t := 0.0                # how long the keeper or defender has had it


func _ready() -> void:
	_setup_practice_input()
	if config.is_empty():
		var game := get_node_or_null("/root/Game")
		if game:
			config = game.match_config()
	config["human_side"] = 0
	_setup()
	if not manual_step:
		var view := PracticeView.new()
		view.name = "View"
		add_child(view)
		view.director.replays_enabled = false
		var layer := CanvasLayer.new()
		var hud := PracticeHud.new()
		hud.match_node = self
		hud.view = view
		layer.add_child(hud)
		add_child(layer)


func _exit_tree() -> void:
	Engine.time_scale = 1.0


func _setup() -> void:
	super._setup()
	half_seconds = INF
	# You: the home team's best striker. Against you: their keeper and a back.
	human = null
	for p in squads[0]:
		if not p.is_keeper() and (human == null or p.r("shooting") > human.r("shooting")):
			human = p
	for p in squads[1]:
		if p.is_keeper():
			practice_keeper = p
		elif p.role == "DEF" and (practice_defender == null or p.r("tackling") > practice_defender.r("tackling")):
			practice_defender = p
	referee.pos = Vector2(PITCH.x / 2.0, -4.0)   # watching from the touchline
	_set_lineup()
	reset_ball()


## Only the players in use stay on the pitch.
func _set_lineup() -> void:
	squads = [[human], []]
	if keeper_on and practice_keeper != null:
		squads[1].append(practice_keeper)
	if defender_on and practice_defender != null:
		squads[1].append(practice_defender)
	players = squads[0] + squads[1]


func set_keeper(on: bool) -> void:
	keeper_on = on
	_set_lineup()
	if on:
		practice_keeper.pos = own_goal(1) + Vector2(-attack_dir[0] * 1.2, 0)
		practice_keeper.vel = Vector2.ZERO


func set_defender(on: bool) -> void:
	defender_on = on
	_set_lineup()
	if on:
		_place_defender()


func _place_defender() -> void:
	var d := practice_defender
	d.pos = human.pos + Vector2(attack_dir[0] * 8.0, 0)
	d.vel = Vector2.ZERO
	d.facing = Vector2(-attack_dir[0], 0)
	d.stagger = 0.0
	d.swing_t = -1.0
	d.cooldown = 1.0


## The match calls this at kick-off and after a goal; here there's no throw-up.
func _start_throw_up() -> void:
	state = State.PLAY


## The ball back at your feet, a fair way out from goal, play on.
func reset_ball() -> void:
	state = State.PLAY
	circle_pace = ""
	_clear_set_piece()
	penalty_taker = null
	gather_keeper = null
	shy_lift = null
	battle = {}
	charge = -1.0
	_held_t = 0.0
	var goal := target_goal(0)
	for p in players:
		p.vel = Vector2.ZERO
		p.desired = Vector2.ZERO
		p.stagger = 0.0
		p.lunge = 0.0
		p.swing_t = -1.0
		p.shy_ready = false
		p.shy_toss = false
		p.hop_t = 0.0
	human.pos = Vector2(goal.x - attack_dir[0] * RESET_X, PITCH.y / 2.0)
	human.facing = Vector2(attack_dir[0], 0)
	human.stick = Body.rest_spot(human)
	if practice_keeper in players:
		practice_keeper.pos = goal - Vector2(attack_dir[0] * 1.2, 0)
		practice_keeper.facing = Vector2(-attack_dir[0], 0)
	if practice_defender in players:
		_place_defender()
	ball_pos = Vector2(human.stick.x, human.stick.y)
	ball_z = 0.0
	ball_vel = Vector2.ZERO
	ball_vz = 0.0
	flight += 1
	_take_control(human)
	human.touch_block = 0.0
	protected_timer = 0.0


# ---------------------------------------------------------------- loop

func _physics_process(delta: float) -> void:
	if manual_step:
		return
	if Input.is_action_just_pressed("pause"):
		paused = not paused
	if paused:
		if Input.is_action_just_pressed("quit_match"):
			get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
		elif Input.is_action_just_pressed("practice_keeper"):
			set_keeper(not keeper_on)
		elif Input.is_action_just_pressed("practice_defender"):
			set_defender(not defender_on)
		return
	if Input.is_action_just_pressed("practice_next"):
		move_index = (move_index + 1) % MOVES.size()
	if Input.is_action_just_pressed("practice_prev"):
		move_index = (move_index - 1 + MOVES.size()) % MOVES.size()
	if Input.is_action_just_pressed("practice_play"):
		play_move(move_index)
	if Input.is_action_just_pressed("practice_reset"):
		reset_ball()
	if Input.is_action_just_pressed("practice_slow"):
		set_speed((speed_index + 1) % SPEEDS.size())
	if Input.is_action_just_pressed("practice_camera"):
		close_cam = not close_cam
	step(delta)


func set_speed(i: int) -> void:
	speed_index = i
	Engine.time_scale = SPEEDS[i]


## The match's own step, less the clock, the referee and substitutions.
func step(dt: float) -> void:
	message_timer = max(0.0, message_timer - dt)
	match state:
		State.PLAY:
			_update_set_piece(dt)
			_update_players(dt)
			_take_penalty(dt)
			_update_ball(dt)
			_check_ball_out()
			_ball_back(dt)
		State.GOAL:
			state_timer -= dt
			_update_ball(dt)
			for p in players:
				p.desired = Vector2.ZERO
				_move(p, dt)
			if state_timer <= 0.0:
				reset_ball()


## When the keeper or the defender has won it, or it has come to rest away
## from you, it comes back to you.
func _ball_back(dt: float) -> void:
	if (carrier != null and carrier != human) or gather_keeper != null:
		_held_t += dt
		if _held_t >= BALL_BACK_AFTER:
			_say("Saved" if carrier == practice_keeper or gather_keeper != null else "Tackled", 1.0)
			reset_ball()
	elif carrier == null and shy_lift == null and set_piece_taker_now() == null \
			and ball_vel.length() < 3.0 and ball_z < 0.1 and ball_pos.distance_to(human.pos) > LOOSE_FAR:
		_held_t += dt
		if _held_t >= LOOSE_BACK_AFTER:
			reset_ball()
	else:
		_held_t = 0.0


## The keeper does the keeper's job; the defender closes you down.
func _ai_team(t: int, dt: float) -> void:
	for p in squads[t]:
		if p == human:
			continue
		if p.is_keeper():
			if carrier == p:
				p.desired = Vector2.ZERO   # holds it until it comes back to you
			else:
				_ai_keeper(p, dt)
		elif carrier == p:
			p.desired = Vector2.ZERO
		else:
			_ai_chase(p, dt)


func _human_control(dt: float) -> void:
	if circle_pace != "":
		var raw := Input.get_vector("move_left", "move_right", "move_up", "move_down")
		if raw.length() > 0.3:
			circle_pace = ""   # the stick takes over again
		else:
			_run_circle()
			return
	super._human_control(dt)


## Round and round a 10-yard circle so the run can be watched from all sides.
func _run_circle() -> void:
	var p := human
	var off := p.pos - circle_centre
	if off.length() < 0.5:
		off = Vector2(10.0, 0.0)
	var tangent := off.normalized().rotated(PI / 2.0)
	var radial := -off.normalized() * (off.length() - 10.0) * 0.3
	var speed: float = {"walk": WALK_SPEED, "jog": p.top_speed() * JOG, "sprint": p.top_speed()}[circle_pace]
	p.desired = (tangent + radial).normalized() * speed
	p.sprinting = circle_pace == "sprint"


## Over the line: a goal counts, anything else just comes back to you.
func _check_ball_out() -> void:
	if ball_pos.x >= 0.0 and ball_pos.x <= PITCH.x and ball_pos.y >= 0.0 and ball_pos.y <= PITCH.y:
		return
	var end_x := 0.0 if ball_pos.x < 0.0 else PITCH.x
	var in_goal: bool = (ball_pos.x < 0.0 or ball_pos.x > PITCH.x) \
		and abs(ball_pos.y - PITCH.y / 2.0) < GOAL_W / 2.0 and ball_z < CROSSBAR
	if in_goal and end_x == target_goal(0).x:
		_goal(0)
	else:
		_say("Wide" if ball_pos.x < 0.0 or ball_pos.x > PITCH.x else "Out", 1.0)
		reset_ball()


## A goal in practice: no score bug, no replay, the ball comes back.
func _goal(_team: int) -> void:
	goals += 1
	state = State.GOAL
	state_timer = 1.5
	carrier = null
	gather_keeper = null
	_clear_set_piece()
	ball_vel *= 0.15
	ball_vz = 0.0
	charge = -1.0
	_say("GOAL!", 1.5)
	events.append({"type": "goal", "team": 0, "half": 1, "clock": 0.0})


# ---------------------------------------------------------------- moves

func play_move(i: int) -> void:
	var mv: Array = MOVES[i]
	match str(mv[1]):
		"pose":
			if str(mv[2]) == "stumble":
				human.stagger = 1.3 * float(mv[3])   # the view reads how hard from this
			anim(human, str(mv[2]), float(mv[3]))
		"feed":
			feed(str(mv[2]))
		"set":
			_set_piece_drill(str(mv[2]))
		"run":
			if carrier == human:
				carrier = null   # leave the ball where it is
			circle_pace = str(mv[2])
			circle_centre = human.pos + human.facing.rotated(-PI / 2.0) * 10.0


## Sends a ball at you from up the pitch, as if from a teammate.
func feed(kind: String) -> void:
	if state != State.PLAY:
		return
	circle_pace = ""
	_clear_set_piece()
	penalty_taker = null
	gather_keeper = null
	carrier = null
	var dist: float = {"ground": 20.0, "bounce": 18.0, "high": 30.0, "chest": 14.0, "drive": 28.0}[kind]
	var from := human.pos + human.facing * dist
	from = Vector2(clamp(from.x, 1.0, PITCH.x - 1.0), clamp(from.y, 1.0, PITCH.y - 1.0))
	var to := human.pos + human.facing * 0.8
	var d := from.distance_to(to)
	var dir := (to - from).normalized()
	var z0 := 0.0
	var speed := 14.0
	var arrive_z := 0.0
	match kind:
		"ground":
			speed = 14.0
		"bounce":
			speed = 13.0
			arrive_z = 0.5
		"high":
			speed = 15.0
			arrive_z = 1.6
		"chest":
			speed = 12.0
			z0 = 1.0
			arrive_z = 1.4
		"drive":
			speed = 28.0
			z0 = 0.1
			arrive_z = 0.4
	ball_pos = from
	ball_z = z0
	ball_vel = dir * speed
	var t := d / speed
	# Straight up enough to come down at that height when it reaches you
	# (a bouncing ball comes down short and bounces on to you).
	ball_vz = 0.0 if kind == "ground" else (arrive_z - z0 + 0.5 * GRAVITY * t * t) / t
	if kind == "bounce":
		ball_vz = 3.0
	flight += 1
	last_team = 0
	human.touch_block = 0.0
	_held_t = 0.0


func _set_piece_drill(kind: String) -> void:
	reset_ball()
	match kind:
		"Shy":
			_restart(0, Vector2(human.pos.x, 0.0), "Shy")
		"Free hit":
			var goal := target_goal(0)
			award_free_hit(0, goal - Vector2(attack_dir[0] * 25.0, -6.0), "Free hit")
		"Penalty hit":
			award_penalty(0, "Penalty hit")
		"Corner":
			_restart(0, Vector2(target_goal(0).x - attack_dir[0] * 1.0, 1.0), "Corner")


# ---------------------------------------------------------------- input

func _setup_practice_input() -> void:
	_add_input("practice_next", [KEY_BRACKETRIGHT], [JOY_BUTTON_DPAD_RIGHT])
	_add_input("practice_prev", [KEY_BRACKETLEFT], [JOY_BUTTON_DPAD_LEFT])
	_add_input("practice_play", [KEY_T], [JOY_BUTTON_RIGHT_STICK])
	_add_input("practice_reset", [KEY_BACKSPACE], [JOY_BUTTON_DPAD_DOWN])
	_add_input("practice_slow", [KEY_TAB], [JOY_BUTTON_DPAD_UP])
	_add_input("practice_camera", [KEY_V], [JOY_BUTTON_BACK])
	_add_input("practice_keeper", [KEY_K], [JOY_BUTTON_Y])
	_add_input("practice_defender", [KEY_J], [JOY_BUTTON_X])
	_add_input("practice_orbit_left", [KEY_COMMA], [])
	_add_input("practice_orbit_right", [KEY_PERIOD], [])


func _add_input(action: String, keys: Array, buttons: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(action, e)
	for b in buttons:
		var e := InputEventJoypadButton.new()
		e.button_index = b
		InputMap.action_add_event(action, e)
