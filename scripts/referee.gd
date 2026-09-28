extends RefCounted
## The referee. It watches the match through the match's `events` list and
## enforces the rules of shinty (summarised in docs/rules.md): fouls, advantage,
## free hits, penalty hits, offside, keeper handling, no goals direct from a
## free hit, and yellow and red cards. It also runs about the pitch so the view
## can draw it, and it only sees what a referee could: a foul far from it, or a
## push in the back, can go unpunished.
##
## The match tells it what happened; it never decides how play itself works.
## Events it reads (dictionaries appended to match.events):
##   strike  {by, at}              a player hit the ball
##   touch   {by, at, hands}       a player got a touch on a loose ball
##                                 (hands = a keeper stopping it with the hands)
##   foul    {kind, by, on, at, severity}
##                                 contact the physics saw happen: "push" (in
##                                 the back), "hack", "stick" (caman on the man),
##                                 or "trip", "head", "kick", "hands". "barge"
##                                 (shoulder to shoulder) is legal.
##   save, goal, Shy, Corner, Hit-out, Free hit, Penalty hit, half_end

const FREE_HIT_YARDS := 5.0       ## opponents stand back this far
const PENALTY_YARDS := 20.0       ## penalty hit, from the goal line
const ADVANTAGE_SECONDS := 3.0
const RUN_SPEED := 7.0
const FOUL_NAMES := {
	"push": "push in the back", "hack": "hacking", "stick": "caman on the man",
	"trip": "trip", "head": "ball played with the head", "kick": "ball kicked",
	"hands": "handball", "keeper_catch": "keeper caught the ball", "obstruction": "obstruction", "keeper_hands": "keeper handled outside the D",
}

var m: Node                       ## the match
var pos := Vector2.ZERO           ## where the referee stands, in yards
var vel := Vector2.ZERO
var facing := Vector2.DOWN

## Keepers may deflect the ball (open palm, stick or body) but not catch it.
## A save that drops the ball at their feet is fine; taking hold of it with
## the hands is a foul.
var penalise_keeper_catch := true
## Tests set this so every foul is seen.
var always_sees := false

var fouls := {}                   ## Player -> fouls committed
var yellows := {}                 ## Player -> yellow cards
var cards := []                   ## {player, team, colour, minute}
var calls := []                   ## every decision: {call, team, kind, minute}
var sent_off := []

var _next_event := 0
var _offside_team := -1           ## team whose strike froze offside positions
var _offside_players := []
var _offside_ball := Vector2.ZERO
var _free_hit_taker = null        ## a goal can't come straight from a free hit
var _advantage := {}              ## {team, offender, at, kind, timer}


func setup(match_node: Node) -> void:
	m = match_node
	pos = m.PITCH / 2.0 + Vector2(0, -2.0)


func step(dt: float) -> void:
	_read_events()
	if m.state == m.State.PLAY and not _advantage.is_empty():
		_update_advantage(dt)
	_run(dt)


## Called by the match before it counts a goal. False means no goal.
func goal_stands(team: int) -> bool:
	if _free_hit_taker != null and _free_hit_taker.team == team:
		_free_hit_taker = null
		calls.append({"call": "no goal", "team": team, "kind": "direct from a free hit", "minute": m.match_minute()})
		return false
	return true


func team_cards(team: int, colour: String) -> int:
	var n := 0
	for c in cards:
		if c["team"] == team and c["colour"] == colour:
			n += 1
	return n


# ---------------------------------------------------------------- events

func _read_events() -> void:
	while _next_event < m.events.size():
		var e: Dictionary = m.events[_next_event]
		_next_event += 1
		match e["type"]:
			"strike":
				_on_strike(e["by"], e["at"])
			"touch":
				_on_touch(e["by"], e["at"], e.get("hands", false))
			"foul":
				_on_foul(e)
			"save":
				if e.has("by"):
					_touched(e["by"])
			"Free hit":
				_clear()
				_free_hit_taker = e.get("taker")
			"throw_up":
				_clear()
				# The referee throws the ball up at the centre spot, standing
				# between the goals' line and the two centres (who are either
				# side of the spot across the pitch).
				pos = m.ball_pos + Vector2(-1.4, 0)
				vel = Vector2.ZERO
			"Shy", "Corner", "Hit-out", "Penalty hit", "goal", "half_end":
				_clear()


func _clear() -> void:
	_advantage = {}
	_offside_team = -1
	_offside_players = []
	_free_hit_taker = null


## Any touch by someone other than the free-hit taker makes a goal legal again.
func _touched(p) -> void:
	if _free_hit_taker != null and p != _free_hit_taker:
		_free_hit_taker = null


func _on_strike(p, at: Vector2) -> void:
	_touched(p)
	# Offside: attackers already inside the opponents' D, ahead of the ball,
	# when a team-mate plays it may not be the next to play it.
	_offside_team = p.team
	_offside_ball = at
	_offside_players = []
	for mate in m.squads[p.team]:
		if mate != p and _in_offside_position(mate, at):
			_offside_players.append(mate)


func _on_touch(p, at: Vector2, hands: bool) -> void:
	_touched(p)
	if _offside_team >= 0:
		if p.team != _offside_team:
			_offside_team = -1
		elif p in _offside_players:
			var team: int = 1 - p.team
			_offside_team = -1
			if _sees(at, "offside"):
				_log("offside", team, "offside")
				var goal: Vector2 = m.own_goal(team)
				var spot := Vector2(goal.x + m.attack_dir[team] * (m.D_RADIUS + 1.0), at.y)
				m.award_free_hit(team, spot, "Offside: free hit to %s" % m.teams[team]["name"])
				return
		else:
			_offside_team = -1
	if hands and p.is_keeper():
		var d: float = at.distance_to(m.own_goal(p.team))
		if d > m.D_RADIUS + 0.5:
			_on_foul({"kind": "keeper_hands", "by": p, "on": null, "at": at, "severity": 0.2})
		elif penalise_keeper_catch and m.carrier == p:
			_on_foul({"kind": "keeper_catch", "by": p, "on": null, "at": at, "severity": 0.1})


func _in_offside_position(p, ball_at: Vector2) -> bool:
	var goal: Vector2 = m.target_goal(p.team)
	if p.pos.distance_to(goal) >= m.D_RADIUS:
		return false
	return abs(goal.x - p.pos.x) < abs(goal.x - ball_at.x)


func _on_foul(e: Dictionary) -> void:
	var kind: String = e.get("kind", "foul")
	if kind == "barge" or kind == "shoulder":
		return  # shoulder to shoulder is a fair challenge
	var p = e["by"]
	var at: Vector2 = e.get("at", p.pos)
	if p == null or not (p in m.players):
		return
	if not _sees(at, kind):
		calls.append({"call": "missed", "team": p.team, "kind": kind, "minute": m.match_minute()})
		return
	var team: int = 1 - p.team
	fouls[p] = fouls.get(p, 0) + 1
	var severity: float = e.get("severity", 0.3)
	var card := ""
	if severity > 0.97:
		card = "red"
	elif severity > 0.8 or fouls[p] == 3 or fouls[p] == 6:
		card = "yellow"
	var in_d: bool = at.distance_to(m.own_goal(p.team)) < m.D_RADIUS
	# Advantage: let play go on while the fouled team still has the ball.
	if card == "" and not in_d and m.carrier != null and m.carrier.team == team:
		_advantage = {"team": team, "offender": p, "at": at, "kind": kind, "timer": ADVANTAGE_SECONDS}
		_log("advantage", team, kind)
		m._say("Advantage %s" % m.teams[team]["name"], 1.2)
		return
	_whistle(p, team, at, kind, in_d, card)


func _whistle(p, team: int, at: Vector2, kind: String, in_d: bool, card: String) -> void:
	_advantage = {}
	var what: String = FOUL_NAMES.get(kind, kind)
	var text: String
	if in_d:
		_log("penalty", team, kind)
		text = "Penalty hit to %s (%s)" % [m.teams[team]["name"], what]
	else:
		_log("free hit", team, kind)
		text = "Free hit to %s (%s)" % [m.teams[team]["name"], what]
	if card != "":
		text += "\n" + _book(p, card)
	if in_d:
		m.award_penalty(team, text)
	else:
		m.award_free_hit(team, at, text)


func _book(p, colour: String) -> String:
	var who := "%s #%d" % [m.teams[p.team]["name"], p.number]
	if colour == "yellow":
		yellows[p] = yellows.get(p, 0) + 1
		if yellows[p] >= 2:
			cards.append({"player": p, "team": p.team, "colour": "yellow", "minute": m.match_minute()})
			colour = "red"
			who += " (second yellow)"
	cards.append({"player": p, "team": p.team, "colour": colour, "minute": m.match_minute()})
	if colour == "red":
		sent_off.append(p)
		m.send_off(p)
		return "Red card: %s is sent off" % who
	return "Yellow card: %s" % who


func _update_advantage(dt: float) -> void:
	var team: int = _advantage["team"]
	var lost: bool = (m.carrier != null and m.carrier.team != team) or (m.carrier == null and m.last_team != team)
	if lost:
		var a := _advantage
		_whistle(a["offender"], team, a["at"], a["kind"], false, "")
		return
	_advantage["timer"] -= dt
	if _advantage["timer"] <= 0.0:
		_advantage = {}


func _sees(at: Vector2, kind: String) -> bool:
	if always_sees:
		return true
	var chance: float = clamp(1.05 - pos.distance_to(at) / 70.0, 0.4, 0.97)
	if kind == "push":
		chance *= 0.65  # a push in the back is easy to miss
	elif kind == "offside":
		chance = max(chance, 0.85)  # the line is marked; it's rarely missed
	return randf() < chance


func _log(call: String, team: int, kind: String) -> void:
	calls.append({"call": call, "team": team, "kind": kind, "minute": m.match_minute()})


# ---------------------------------------------------------------- running

func _run(dt: float) -> void:
	var target: Vector2 = m.ball_pos
	if m.state == m.State.THROW_UP:
		# The referee throws the ball up between the two centres.
		target = m.ball_pos + Vector2(0, -1.4)
	else:
		# Trail the play on the far side, on a diagonal, about 12 yards off.
		var dir := 0.0
		if m.carrier != null:
			dir = m.attack_dir[m.carrier.team]
		elif m.last_team >= 0:
			dir = m.attack_dir[m.last_team]
		target = m.ball_pos + Vector2(-dir * 9.0, -9.0)
		target.x = clamp(target.x, 8.0, m.PITCH.x - 8.0)
		target.y = clamp(target.y, 4.0, m.PITCH.y - 4.0)
	var off := target - pos
	var want := Vector2.ZERO
	if off.length() > 1.0:
		want = off.normalized() * min(RUN_SPEED, off.length() * 1.2)
	vel = vel.move_toward(want, 14.0 * dt)
	pos += vel * dt
	var look: Vector2 = m.ball_pos - pos
	if look.length() > 0.5:
		facing = look.normalized()
