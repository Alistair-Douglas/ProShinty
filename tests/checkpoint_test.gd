extends SceneTree
## Headless integration check for the whole game. Plays computer-vs-computer
## matches between random clubs, then full matches through the real menu at
## every ground with a bot at the controls, and checks after every step that
## nothing has gone wrong: the ball and players stay on (or near) the pitch,
## play never sticks, restarts get taken and every match reaches full time.
## Run: godot --headless --fixed-fps 60 --path . -s tests/checkpoint_test.gd
## Add `-- quick` to play fewer, shorter matches.

const TeamData := preload("res://scripts/team_data.gd")
const MatchScene := preload("res://scenes/match.tscn")

const STUCK_SECONDS := 25.0   ## play with the clock stopped this long = stuck

var failures := 0
var quick := false
var _started := false

# Menu-driven matches
var _venue := 0
var _menu_frames := 0
var _match_frames := 0
var _match: Node = null
var _played := false   ## a menu match has started and not yet been counted
var _watch := {}


func _initialize() -> void:
	quick = "quick" in OS.get_cmdline_user_args()


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_sim_matches()
		change_scene_to_file("res://scenes/main_menu.tscn")
		return false
	return _drive_menu_matches()


func _fail(what: String) -> void:
	failures += 1
	if failures <= 40:
		print("  FAIL ", what)


# ---------------------------------------------------------------- invariants

func _new_watch() -> Dictionary:
	return {"still": 0.0, "last_clock": -1.0, "last_half": 1, "hold": 0.0, "holder": null, "goals": 0, "time": 0.0, "failed": {}}


## One failure of each kind per match, so a broken state doesn't flood the log.
func _once(w: Dictionary, key: String, what: String) -> void:
	if not w["failed"].has(key):
		w["failed"][key] = true
		_fail(what)


func _check(m: Node, w: Dictionary, dt: float, label: String) -> void:
	w["time"] += dt
	var at := "%s, half %d, %.0fs" % [label, m.half, m.clock]
	var b: Vector2 = m.ball_pos
	if not (is_finite(b.x) and is_finite(b.y) and is_finite(m.ball_z)):
		_once(w, "ball_nan", "%s: ball position is not a number" % at)
	elif b.x < -8.0 or b.x > m.PITCH.x + 8.0 or b.y < -8.0 or b.y > m.PITCH.y + 8.0 or m.ball_z < -0.5 or m.ball_z > 80.0:
		_once(w, "ball_out", "%s: ball far off the pitch at %s (height %.1f)" % [at, b, m.ball_z])
	for p in m.players:
		if not (is_finite(p.pos.x) and is_finite(p.pos.y)):
			_once(w, "player_nan", "%s: player #%d position is not a number" % [at, p.number])
		elif p.pos.x < -6.0 or p.pos.x > m.PITCH.x + 6.0 or p.pos.y < -6.0 or p.pos.y > m.PITCH.y + 6.0:
			_once(w, "player_out", "%s: team %d #%d wandered off to %s" % [at, p.team, p.number, p.pos])
	if m.carrier != null and not (m.carrier in m.players):
		_once(w, "ghost_carrier", "%s: the ball is carried by a player no longer on the pitch" % at)
	if m.carrier != null and m.carrier.pos.distance_to(b) > 4.0 and m.state == m.State.PLAY:
		_once(w, "ball_far_from_carrier", "%s: carrier #%d is %.1f yd from the ball" % [at, m.carrier.number, m.carrier.pos.distance_to(b)])
	if m.human_side >= 0 and m.state == m.State.PLAY:
		if m.human == null:
			_once(w, "no_human", "%s: nobody under the player's control" % at)
		elif not (m.human in m.players):
			_once(w, "human_gone", "%s: controlling a player who is no longer on the pitch" % at)
	var shy_takers := 0
	for p in m.players:
		if p.shy_toss or p.shy_ready:
			shy_takers += 1
	if shy_takers > 1:
		_once(w, "two_shies", "%s: %d players taking a shy at once" % [at, shy_takers])
	# Play should never stall: in open play the clock runs, except while a shy
	# is taken, and that must not last long. (No clock in a penalty shootout.)
	if m.state == m.State.PLAY and not m.shootout:
		if m.clock == w["last_clock"]:
			w["still"] += dt
			if w["still"] > STUCK_SECONDS:
				var who = m.shy_taker()
				_once(w, "stuck", "%s: clock stopped for %.0fs (shy taker: %s)" % [at, w["still"], "#%d" % who.number if who else "none"])
		else:
			w["still"] = 0.0
		# Nobody holds the ball for ever.
		if m.carrier != null and m.carrier == w["holder"]:
			w["hold"] += dt
			if w["hold"] > 30.0:
				_once(w, "hog", "%s: team %d #%d has held the ball for 30s" % [at, m.carrier.team, m.carrier.number])
		else:
			w["hold"] = 0.0
			w["holder"] = m.carrier
	w["last_clock"] = m.clock
	if m.half < w["last_half"]:
		_once(w, "half_back", "%s: went back a half" % at)
	w["last_half"] = m.half
	var goals: int = m.score[0] + m.score[1]
	if goals < w["goals"]:
		_once(w, "score_down", "%s: the score went down" % at)
	w["goals"] = goals


func _check_events(m: Node, label: String) -> void:
	var goals := 0
	for e in m.events:
		if e["type"] == "goal":
			goals += 1
	if goals != m.score[0] + m.score[1]:
		_fail("%s: %d goal events but the score is %s" % [label, goals, m.score])
	# A player on the pitch at the end is one who wasn't sent off.
	for p in m.referee.sent_off:
		if p in m.players:
			_fail("%s: #%d was sent off but is still playing" % [label, p.number])


# ---------------------------------------------------------------- computer v computer

func _sim_matches() -> void:
	var teams := TeamData.load_teams()
	if teams.size() < 2:
		_fail("fewer than two teams loaded: %s" % TeamData.load_error)
		return
	for t in teams:
		if TeamData.starting_twelve(t).size() != 12:
			_fail("%s doesn't have 12 starters" % t["name"])
	var n := 4 if quick else 12
	var half := 90.0 if quick else 180.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	print("Computer v computer, random clubs")
	for i in n:
		var a := rng.randi_range(0, teams.size() - 1)
		var b := (a + rng.randi_range(1, teams.size() - 1)) % teams.size()
		var m = MatchScene.instantiate()
		m.manual_step = true
		m.config = {"home": teams[a], "away": teams[b], "human_side": -1, "difficulty": i % 3, "half_seconds": half, "seed": 500 + i}
		root.add_child(m)
		var label := "%s v %s" % [teams[a]["name"], teams[b]["name"]]
		var w := _new_watch()
		var steps := 0
		var dt := 1.0 / 60.0
		while m.state != m.State.FULL_TIME and steps < 60 * (int(half) * 2 + 480):   # room for extra time and penalties
			m.step(dt)
			_check(m, w, dt, label)
			steps += 1
		if m.state != m.State.FULL_TIME:
			_fail("%s: never reached full time (half %d, clock %.0f)" % [label, m.half, m.clock])
		_check_events(m, label)
		print("  %-40s %d - %d  shots %s  cards %d" % [label, m.score[0], m.score[1], str(m.shots), m.referee.cards.size()])
		m.free()


# ---------------------------------------------------------------- through the menu

## Plays one full match at each ground through the real menu, with a bot
## pressing the controls, then returns to the menu with the result.
func _drive_menu_matches() -> bool:
	var scene := current_scene
	if scene == null:
		return false
	if scene.name != "Match":
		_menu_frames += 1
		if _played:
			# Back at the menu after a match.
			_played = false
			_match = null
			var r: Dictionary = root.get_node("Game").last_result
			if r.is_empty():
				_fail("no result recorded after the match at venue %d" % _venue)
			_venue += 1
			_menu_frames = 0
		if _venue >= 3:
			print("Checkpoint: %s" % ("all passed" if failures == 0 else "%d failures" % failures))
			quit(1 if failures else 0)
			return true
		if scene.get("ready_to_play") == true and scene.is_processing_unhandled_input():
			# The loading screen waits for a key once the match is loaded.
			var key := InputEventKey.new()
			key.keycode = KEY_SPACE
			key.pressed = true
			scene.call("_unhandled_input", key)
			return false
		if _menu_frames == 5:
			if scene.get("home_pick") == null:
				_fail("main menu has no team picker")
				quit(1)
				return true
			var n: int = scene.home_pick.item_count
			scene.home_pick.select([0, 2, 20][_venue] % n)
			scene.home_pick.item_selected.emit(scene.home_pick.selected)
			scene.away_pick.select([1, n - 1, 5][_venue] % n)
			scene.away_pick.item_selected.emit(scene.away_pick.selected)
			scene.pitch_pick.select(_venue)
			scene.side_pick.select(_venue % 2)
			scene.diff_pick.select(_venue)
			scene.length_pick.select(0)   # 2-minute halves
			scene.call("_start")
		return false
	if not _played:
		_played = true
		_match = scene
		_match_frames = 0
		_watch = _new_watch()
		print("Menu match %d at %s: %s v %s (you: %s)" % [_venue + 1, ShintyPitch.VENUE_NAMES[_venue],
			_match.teams[0]["name"], _match.teams[1]["name"], ["home", "away"][_match.human_side]])
		if int(_match.config.get("venue", -1)) != _venue:
			_fail("picked ground %d but the match is at %s" % [_venue, _match.config.get("venue")])
	_match_frames += 1
	var m := _match
	if _match_frames < 0:
		return false
	if m.state == m.State.FULL_TIME:
		_release_all()
		_check_events(m, "menu match %d" % (_venue + 1))
		print("  full time %d - %d, the bot started %d swings, held the ball up for %d frames" % [m.score[0], m.score[1], _swings, _shields])
		if _swings == 0:
			_fail("menu match %d: the bot's key presses never started a swing" % (_venue + 1))
		_swings = 0
		_shields = 0
		# What pressing a button at full time does.
		change_scene_to_file("res://scenes/main_menu.tscn")
		_match_frames = -1000000
		return false
	# Two 2-minute halves, plus extra time after a draw (two more 40-second
	# halves), a penalty shootout if still level, the breaks, and the clock
	# stopped for restarts.
	if _match_frames > 60 * 60 * 16:
		_fail("menu match %d never reached full time (half %d, clock %.0f, state %d, score %s)" % [_venue + 1, m.half, m.clock, m.state, m.score])
		quit(1)
		return true
	return false


## The bot presses keys at the start of each physics step, so the match sees
## them as just pressed in that step, as it would a real key press.
func _physics_process(delta: float) -> bool:
	var m = _match
	if not _played or _match_frames < 0 or not is_instance_valid(m) or m.state == m.State.FULL_TIME:
		return false
	if not m.paused:
		_check(m, _watch, delta, "menu match %d" % (_venue + 1))
	_bot(m)
	return false


var _swing_hold := 0
var _counted := false
var _shields := 0   ## frames the bot held the ball up
var _swings := 0   ## hits the bot started (checks key presses reach the match)


## A simple player: runs at the ball, dribbles at goal, swings when close,
## tries a block, cleek or barge now and then, and pauses once.
func _bot(m: Node) -> void:
	if m.state == m.State.HALF_TIME and not m.paused and _match_frames % 30 == 0:
		# The stats screen holds the break until A / Enter.
		for down in [true, false]:
			var e := InputEventAction.new()
			e.action = "ui_accept"
			e.pressed = down
			Input.parse_input_event(e)
	var h = m.human
	if h == null:
		return
	if _match_frames == 600:
		Input.action_press("pause")
	elif _match_frames == 602:
		Input.action_release("pause")
	elif _match_frames == 640:
		Input.action_press("pause")
	elif _match_frames == 642:
		Input.action_release("pause")
	if m.paused:
		return
	if m.charge >= 0.0 and _swing_hold > 0 and not _counted:
		_swings += 1
		_counted = true
	if _swing_hold == 0:
		_counted = false
	for a in ["move_left", "move_right", "move_up", "move_down", "switch", "pass", "block", "cleek", "barge", "sprint", "shield"]:
		Input.action_release(a)
	var target: Vector2 = m.ball_pos
	if m.carrier == h:
		target = m.target_goal(h.team)
	var d: Vector2 = target - h.pos
	if abs(d.x) > 0.5:
		Input.action_press("move_right" if d.x > 0 else "move_left")
	if abs(d.y) > 0.5:
		Input.action_press("move_down" if d.y > 0 else "move_up")
	if _match_frames % 90 < 45:
		Input.action_press("sprint")
	if _swing_hold > 0:
		_swing_hold -= 1
		if _swing_hold == 0:
			Input.action_release("shoot")
			Input.action_release("hit")
		return
	var near: bool = h.pos.distance_to(m.ball_pos) < 2.5
	if m.carrier == h and m._nearest_opponent_dist(h) < 2.5 and _match_frames % 200 < 100:
		Input.action_press("shield")   # hold it up under pressure
		_shields += 1
	if m.carrier == h:
		var to_goal: float = h.pos.distance_to(m.target_goal(h.team))
		if to_goal < 35.0 or randf() < 0.01:
			Input.action_press("shoot" if to_goal < 60.0 else "hit")   # long hit from deep
			_swing_hold = randi_range(20, 60)   # sometimes into the overswing
		elif randf() < 0.01:
			Input.action_press("pass")
	elif m.carrier != null and m.carrier.team != h.team and near:
		var r := randf()
		if r < 0.03:
			Input.action_press("block")
		elif r < 0.06:
			Input.action_press("cleek")
		elif r < 0.09:
			Input.action_press("barge")
		elif r < 0.15:
			Input.action_press("pass")   # poke at their ball
		elif r < 0.18:
			Input.action_press("shoot")
			_swing_hold = 8
	elif m.carrier == null and near and randf() < 0.1:
		Input.action_press("shoot")
		_swing_hold = 10
	elif m.carrier != null and m.carrier.team != h.team and _match_frames % 120 == 0:
		Input.action_press("switch")


func _release_all() -> void:
	for a in ["move_left", "move_right", "move_up", "move_down", "switch", "pass", "block", "cleek", "barge", "sprint", "shoot", "hit", "shield"]:
		Input.action_release(a)
	_swing_hold = 0
