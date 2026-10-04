extends RefCounted
## Match stats for the half-time, full-time and pause screens. Like the
## referee, it only watches: it reads the match's `events` list (and the
## referee's books) and counts, per side. Call update() as often as you like
## (the stats screen calls it every frame); possession is shared out by the
## match clock, so it is the same however often that is.
##
## What counts as what:
##   shots            strikes at goal: the match counts a shot when a player
##                    goes for goal (match.shots), and the shot is that
##                    player's next strike (an air shot doesn't count). Any
##                    goal is a shot on target, deflections included.
##   shots on target  shots that went in or that the keeper had to save
##   saves            shots on target the keeper kept out
##   possession       match time with the ball on a side's stick, or last
##                    played by them while it is loose
##   passes completed a strike picked up next by a team-mate (a touch, a
##                    first-time hit, or a body stop)
##   tackles won      a clean steal, or a stick battle won
##   fouls            fouls the referee saw (penalised or advantage played)
##   free hits        free hits awarded (fouls and offside)
##   corners, bye-hits, penalty hits, yellow and red cards

var m: Node

var shots_made := [0, 0]
var on_target_n := [0, 0]
var passes := [0, 0]
var tackles := [0, 0]
var saves := [0, 0]
var free_hits := [0, 0]
var penalties := [0, 0]
var corners := [0, 0]
var bye_hits := [0, 0]
var held := [0.0, 0.0]            ## seconds of match time each side had the ball

var _next_event := 0
var _pass_from = null              ## the Player whose strike may be a pass
var _shooter := [null, null]       ## each side: a player who has just gone for goal
var _shot_live = null              ## the Player whose shot is on its way
var _match_shots := [0, 0]         ## match.shots when last looked
var _last_clock := 0.0
var _last_half := 1


func _init(match_node: Node = null) -> void:
	if match_node != null:
		setup(match_node)


func setup(match_node: Node) -> void:
	m = match_node
	_match_shots = [int(m.shots[0]), int(m.shots[1])]
	_last_clock = m.clock
	_last_half = m.half


func update() -> void:
	_going_for_goal()
	_read_events()
	_possession()


# ---------------------------------------------------------------- the numbers

func goals(t: int) -> int:
	return int(m.score[t])


func on_target(t: int) -> int:
	return on_target_n[t]


func shots(t: int) -> int:
	return shots_made[t]


## Share of possession, 0..100. Even until anyone has had the ball.
func possession(t: int) -> int:
	var total: float = held[0] + held[1]
	if total <= 0.0:
		return 50
	var home := int(round(held[0] / total * 100.0))
	return home if t == 0 else 100 - home


func fouls(t: int) -> int:
	var n := 0
	var books: Dictionary = m.referee.fouls
	for p in books:
		if p.team == t:
			n += int(books[p])
	return n


func cards(t: int, colour: String) -> int:
	return m.referee.team_cards(t, colour)


## The table the stats screen draws: [label, home, away, show as a bar].
## Penalty hits only appear once there has been one.
func rows() -> Array:
	update()
	var out := [
		["Goals", goals(0), goals(1), false],
		["Shots", shots(0), shots(1), true],
		["Shots on target", on_target(0), on_target(1), true],
		["Possession %", possession(0), possession(1), true],
		["Passes completed", passes[0], passes[1], true],
		["Tackles won", tackles[0], tackles[1], true],
		["Fouls", fouls(0), fouls(1), true],
		["Free hits", free_hits[0], free_hits[1], true],
	]
	if penalties[0] + penalties[1] > 0:
		out.append(["Penalty hits", penalties[0], penalties[1], true])
	out.append_array([
		["Yellow cards", cards(0, "yellow"), cards(1, "yellow"), false],
		["Red cards", cards(0, "red"), cards(1, "red"), false],
		["Saves", saves[0], saves[1], true],
		["Corners", corners[0], corners[1], true],
		["Bye-hits", bye_hits[0], bye_hits[1], true],
	])
	return out


# ---------------------------------------------------------------- counting

func _read_events() -> void:
	while _next_event < m.events.size():
		var e: Dictionary = m.events[_next_event]
		_next_event += 1
		match e["type"]:
			"strike":
				_received(e["by"])
				_pass_from = e["by"]
				_struck(e["by"])
			"hit":
				if e.get("kind", "") == "fresh_air" and e.get("by") == _shooter[e["team"]]:
					_shooter[e["team"]] = null   # swung and missed it altogether
			"touch":
				_received(e["by"])
				if not e["by"].is_keeper():
					_shot_live = null   # blocked, or picked up
			"goal":
				var t: int = e["team"]
				if _shot_live == null or _shot_live.team != t:
					shots_made[t] += 1   # in off someone, or a long hit that dropped in
				on_target_n[t] += 1
				_shot_live = null
				_pass_from = null
			"tackle":
				if e.get("won", false):
					tackles[e["by"].team] += 1
				_pass_from = null
			"battle_won":
				tackles[e["team"]] += 1
			"save":
				var k: int = e["team"]
				if _shot_live != null and _shot_live.team != k:
					saves[k] += 1
					on_target_n[1 - k] += 1
				_shot_live = null
				_pass_from = null
			"Free hit":
				free_hits[e["team"]] += 1
				_pass_from = null
			"Penalty hit":
				penalties[e["team"]] += 1
				_pass_from = null
			"Corner":
				corners[e["team"]] += 1
				_pass_from = null
			"Hit-out":
				bye_hits[e["team"]] += 1
				_pass_from = null
			"Shy", "throw_up", "half_end":
				_pass_from = null
		if e["type"] in ["Free hit", "Penalty hit", "Corner", "Hit-out", "Shy", "throw_up", "half_end"]:
			_shot_live = null
			_shooter = [null, null]


## The match has counted a shot: whoever is on the ball (or, for you, your
## player) is going for goal, and their next strike is the shot.
func _going_for_goal() -> void:
	for t in 2:
		if int(m.shots[t]) > _match_shots[t]:
			var p = m.carrier if m.carrier != null and m.carrier.team == t else null
			if p == null and m.human != null and m.human.team == t:
				p = m.human
			_shooter[t] = p
		_match_shots[t] = int(m.shots[t])


func _struck(p) -> void:
	if p == _shooter[p.team]:
		shots_made[p.team] += 1
		_shooter[p.team] = null
		_shot_live = p
	else:
		_shot_live = null


## The ball's next touch after a strike: a pass is complete if a team-mate
## got it.
func _received(p) -> void:
	if _pass_from != null and p != null and p != _pass_from and p.team == _pass_from.team:
		passes[p.team] += 1
	_pass_from = null


func _possession() -> void:
	if m.half != _last_half:
		_last_half = m.half
		_last_clock = 0.0
	var dt: float = m.clock - _last_clock
	_last_clock = m.clock
	if dt <= 0.0 or m.state != m.State.PLAY:
		return
	var t := -1
	if m.carrier != null:
		t = m.carrier.team
	elif m.last_team >= 0:
		t = m.last_team
	if t >= 0:
		held[t] += dt
