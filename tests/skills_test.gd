extends SceneTree
## Skill moves: a dummy sells a close marker (planted, no tackle) and sells
## less straight after another; a chipped through ball goes up over a caman
## and comes down near the runner, where a plain one stays on the grass.
## godot --headless --path . -s tests/skills_test.gd

const TeamData := preload("res://scripts/team_data.gd")
const MatchScene := preload("res://scenes/match.tscn")

var _done := false
var ok := true


func _process(_d: float) -> bool:
	if not _done:
		_done = true
		_run()
	return false


func _check(cond: bool, what: String) -> void:
	print(("PASS " if cond else "FAIL ") + what)
	ok = ok and cond


func _new_match(seed: int):
	var teams := TeamData.load_teams()
	var m = MatchScene.instantiate()
	m.manual_step = true
	m.config = {"home": teams[0], "away": teams[1], "human_side": 0, "difficulty": 1, "half_seconds": 600.0, "seed": seed}
	root.add_child(m)
	m.state = m.State.PLAY
	m.protected_timer = 0.0
	return m


## Everyone but the named players out of the way, the human on the ball
## in midfield facing up the park.
func _clear(m, keep: Array) -> void:
	var i := 0
	for p in m.players:
		if p in keep:
			continue
		p.pos = Vector2(5.0 + i * 2.0, 3.0 if p.team == 0 else 72.0)
		p.vel = Vector2.ZERO
		i += 1
	var h = m.human
	h.pos = Vector2(70, 37.5)
	h.vel = Vector2.ZERO
	h.facing = Vector2(m.attack_dir[0], 0)
	m.carrier = h
	m.ball_pos = h.pos + h.facing * 0.8
	m.ball_z = 0.0
	m.ball_vel = Vector2.ZERO
	m.ball_vz = 0.0
	m.dribble_vel = Vector2.ZERO


func _marker(m):
	for q in m.squads[1]:
		if not q.is_keeper():
			return q
	return null


func _dummy_tests() -> void:
	var m = _new_match(7)
	var h = m.human
	var q = _marker(m)
	# How often a marker two yards off bites on a full dummy, and on one
	# straight after another.
	var bites := 0
	var quick_bites := 0
	for i in 200:
		_clear(m, [h, q])
		q.pos = h.pos + h.facing * 2.0
		q.sold = 0.0
		q.stagger = 0.0
		q.block_t = 0.0
		q.cleek_t = 0.0
		m.since_dummy = 99.0
		m.charge = 0.5
		m._dummy(h)
		if q.sold > 0.0:
			bites += 1
		q.sold = 0.0
		q.block_t = 0.0
		q.cleek_t = 0.0
		m.charge = 0.5
		m._dummy(h)   # straight after the first
		if q.sold > 0.0:
			quick_bites += 1
	print("dummy: bit %d of 200, straight after %d of 200" % [bites, quick_bites])
	_check(bites > 40, "a close marker bites on a dummy")
	_check(quick_bites < bites, "a second dummy straight after sells less")
	_check(m.charge < 0.0 and m.carrier == h, "the dummy cancels the hit and keeps the ball")
	# A sold marker is planted: no closer and no tackle while it lasts.
	var sold_once := false
	for i in 50:
		_clear(m, [h, q])
		q.pos = h.pos + h.facing * 2.5
		q.sold = 0.0
		q.cooldown = 0.0
		m.since_dummy = 99.0
		m.charge = 0.5
		m._dummy(h)
		if q.sold > 0.0:
			sold_once = true
			break
	_check(sold_once, "found a marker who bit")
	var start: float = q.pos.distance_to(h.pos)
	var tackled := false
	for s in 30:   # half a second
		m.step(1.0 / 60.0)
		if m.carrier != h:
			tackled = true
	_check(not tackled, "a sold marker doesn't take the ball")
	_check(q.pos.distance_to(h.pos) >= start - 0.6, "a sold marker is planted (%.2f -> %.2f yd)" % [start, q.pos.distance_to(h.pos)])
	# A dummy with no backswing shown sells nothing.
	_clear(m, [h, q])
	q.pos = h.pos + h.facing * 2.0
	q.sold = 0.0
	m.since_dummy = 99.0
	m.charge = 0.0
	m._dummy(h)
	_check(q.sold == 0.0, "no backswing shown, nobody bites")
	m.free()


## Hit a through ball and follow it until it lands or the marker gets to
## it. Returns [highest, where it first came down].
func _through(chip: bool) -> Array:
	var m = _new_match(11)
	var h = m.human
	var mate = null
	for p in m.squads[0]:
		if p != h and not p.is_keeper():
			mate = p
			break
	var q = _marker(m)
	_clear(m, [h, mate, q])
	mate.pos = h.pos + Vector2(m.attack_dir[0] * 22.0, 4.0)
	mate.vel = Vector2.ZERO
	q.pos = h.pos + Vector2(m.attack_dir[0] * 6.0, 1.0)   # in the way
	var aim: Vector2 = (mate.pos - h.pos).normalized()
	var spot: Vector2 = h.pos + aim * m.through_reach(0.5)   # where it's played: the stick, half weight
	m._human_through(h, aim, chip, 0.5)
	var top := 0.0
	var landed = null
	var struck := false
	for s in 360:
		m.step(1.0 / 60.0)
		if m.carrier == null:
			struck = true
		if struck and m.last_team != h.team:
			break   # the marker got to it: what they do with it isn't the pass
		if struck:
			top = maxf(top, m.ball_z)
			if landed == null and top > 0.3 and m.ball_z <= 0.05:
				landed = m.ball_pos
		if landed != null:
			break
	var out := [top, landed, spot]
	m.free()
	return out


func _chip_tests() -> void:
	var chip := _through(true)
	var flat := _through(false)
	print("chip: top %.2f yd, came down at %s for %s; flat top %.2f yd" % [chip[0], str(chip[1]), str(chip[2]), flat[0]])
	_check(chip[0] > 2.4, "a chipped through ball goes over a caman held up")
	_check(chip[1] != null and chip[1].distance_to(chip[2]) < 6.0, "and comes down near the runner's spot")
	_check(flat[0] < 1.2, "a plain through ball stays low")


func _run() -> void:
	seed(3)
	_dummy_tests()
	_chip_tests()
	print("PASS" if ok else "FAIL")
	quit(0 if ok else 1)
