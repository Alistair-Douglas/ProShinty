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
## A poke that misses the ball can catch the carrier's caman or body instead.
const TACKLE_FOUL := 0.07
## A stick battle can turn into hacking at the other player's caman.
const BATTLE_FOUL := 0.12
## Chance of a yellow card for a foul of severity 1 (scaled down for milder
## ones); a push in the back is booked more readily.
const YELLOW_CHANCE := 0.3
const RED_CHANCE := 0.01
const RUN_SPEED := 7.0
const FOUL_NAMES := {
	"push": "push in the back", "hack": "hacking", "stick": "caman on the man",
	"swing": "swung the caman into a player",
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
## Tests set these so every foul is seen and cards only come when certain.
var always_sees := false
var chance_cards := true

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
			"tackle":
				_on_tackle(e)
			"battle":
				_on_battle()
			"swing_contact":
				_on_swing_contact(e)
			"save":
				if e.has("by"):
					_touched(e["by"])
			"Free hit":
				_clear()
				_free_hit_taker = e.get("taker")
			"throw_up":
				_clear()
				# The referee throws the ball up at the centre spot, from the side.
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


## The physics reports the clear fouls (pushes, late blocks). A referee also
## pulls up clumsy challenges: a poke that misses the ball, more so from
## behind or when tired, sometimes catches the man or his caman.
func _on_tackle(e: Dictionary) -> void:
	if e.get("won", false):
		return
	var t = e["by"]
	var o = e["on"]
	var off: Vector2 = t.pos - o.pos
	var behind := 0.0
	if off.length() > 0.01 and o.facing.length() > 0.01:
		behind = max(0.0, -o.facing.normalized().dot(off.normalized()))
	var chance: float = TACKLE_FOUL * (1.6 - t.r("tackling") / 100.0) + behind * 0.12 + (1.0 - t.stamina) * 0.05
	if randf() >= chance:
		return
	var kind := "push" if behind > 0.6 else "hack"
	var severity: float = 0.15 + randf() * 0.55 + behind * 0.2
	_on_foul({"kind": kind, "by": t, "on": o, "at": e.get("at", o.pos), "severity": severity})


## Two players fighting for the ball with their sticks: now and then one
## comes down on the other's caman.
func _on_battle() -> void:
	var b: Dictionary = m.battle
	if b.is_empty() or randf() >= BATTLE_FOUL:
		return
	var t = b["t"] if randf() < 0.6 else b["o"]
	var o = b["o"] if t == b["t"] else b["t"]
	_on_foul({"kind": "hack", "by": t, "on": o, "at": o.pos, "severity": 0.2 + randf() * 0.4})


## A swing that missed the ball and caught a player (the match reports it
## as "swing_contact"). Hitting the player instead of the ball is a foul, and
## a dangerous one, unless the swing came through the front of a player who
## had the ball: that's part of playing for it. A swing that catches a late
## blocker is never a foul; that comes in as "late_block", not here.
func _on_swing_contact(e: Dictionary) -> void:
	if e.get("front", false) and e.get("had_ball", false):
		return
	_on_foul({"kind": "swing", "by": e["by"], "on": e["on"], "at": e["at"], "severity": 0.35 + randf() * 0.5})


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
	var card := _card_for(p, kind, severity)
	var in_d: bool = at.distance_to(m.own_goal(p.team)) < m.D_RADIUS
	# Advantage: only when the fouled team keeps the ball going forward in the
	# opponents' half; otherwise the whistle goes.
	var attacking: bool = m.carrier != null and m.carrier.team == team \
		and m.own_frac(team, m.carrier.pos.x) > 0.5
	if card == "" and not in_d and attacking:
		_advantage = {"team": team, "offender": p, "at": at, "kind": kind, "timer": ADVANTAGE_SECONDS}
		_log("advantage", team, kind)
		m._say("Advantage %s" % m.teams[team]["name"], 1.2)
		return
	_whistle(p, team, at, kind, in_d, card)


## Certain cards: a very bad foul is a red, a bad one or a third foul by a
## player a yellow. Otherwise a yellow is a judgement call that gets likelier
## the worse the foul, and a push in the back is punished harder.
func _card_for(p, kind: String, severity: float) -> String:
	if severity > 0.97:
		return "red"
	if severity > 0.8 or fouls[p] == 3:
		return "yellow"
	if not chance_cards:
		return ""
	var harsh := 1.4 if kind == "push" or kind == "swing" else 1.0
	if randf() < RED_CHANCE * severity * harsh:
		return "red"
	if randf() < YELLOW_CHANCE * severity * severity * harsh:
		return "yellow"
	return ""


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
		target = m.ball_pos + Vector2(-1.4, 0)
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
