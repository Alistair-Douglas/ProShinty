extends SceneTree
## Headless check of the weather: dry, damp and wet pitches change the bounce
## and the run of the ball, wind pushes a high ball but not a rolling one, and
## players lose their footing on a soaking pitch.
## Run: godot --headless --path . -s tests/weather_test.gd

const TeamData := preload("res://scripts/team_data.gd")
const MatchScene := preload("res://scenes/match.tscn")

var _done := false
var _fails := 0


func _process(_delta: float) -> bool:
	if not _done:
		_done = true
		_run()
		print("weather test: %s" % ("FAILED (%d)" % _fails if _fails > 0 else "passed"))
		quit(1 if _fails > 0 else 0)
	return false


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails += 1


func _run() -> void:
	_test_bounce_and_roll()
	_test_wind()
	_test_random_weather()
	_test_slips()


## A lofted ball, 22 m/s at 30 degrees, then rolling out. Returns
## [height of the first bounce, distance to where it stops, m].
func _flight(wet: float, wind := Vector3.ZERO, launch := Vector3(22.0 * cos(PI / 6.0), 22.0 * sin(PI / 6.0), 0.0)) -> Array:
	seed(7)
	var b := ShintyBallPhysics.new()
	b.wetness = wet
	b.wind = wind
	b.strike(launch)
	var bounced := false
	var top := 0.0
	for i in 60 * 30:
		for e in b.step(1.0 / 60.0):
			if e["type"] in ["bounce", "landed"]:
				bounced = true
		if bounced:
			top = maxf(top, b.height())
		if bounced and b.velocity.length() < 0.01:
			break
	return [top, Vector2(b.position.x, b.position.z).length(), b.position]


func _test_bounce_and_roll() -> void:
	var dry := _flight(0.0)
	var damp := _flight(0.5)
	var wet := _flight(1.0)
	print("  bounce after landing (m): dry %.2f  damp %.2f  wet %.2f" % [dry[0], damp[0], wet[0]])
	print("  where it stops (m):       dry %.1f  damp %.1f  wet %.1f" % [dry[1], damp[1], wet[1]])
	_check(dry[0] > damp[0] and damp[0] > wet[0], "a dry pitch bounces highest, a wet one lowest")
	_check(dry[1] > damp[1] and damp[1] > wet[1], "a dry pitch runs furthest, a wet one holds the ball up")
	# A ball hit along the ground: a wet pitch slows it sooner.
	var dry_g := _flight(0.0, Vector3.ZERO, Vector3(15, 0, 0))
	var wet_g := _flight(1.0, Vector3.ZERO, Vector3(15, 0, 0))
	print("  ground ball at 15 m/s runs: dry %.1f m  wet %.1f m" % [dry_g[1], wet_g[1]])
	_check(dry_g[1] > wet_g[1] * 1.3, "a ground ball runs much further on a dry pitch")


func _test_wind() -> void:
	var cross := Vector3(0, 0, 8.0)   # 8 m/s (18 mph) across the line of the hit
	var calm := _flight(0.5)
	var windy := _flight(0.5, cross)
	var drift: float = windy[2].z - calm[2].z
	print("  high ball pushed %.1f m sideways by an 18 mph crosswind" % drift)
	_check(drift > 3.0, "the wind pushes the high ball")
	var low_calm := _flight(0.5, Vector3.ZERO, Vector3(12, 0, 0))
	var low_windy := _flight(0.5, cross, Vector3(12, 0, 0))
	var low_drift: float = low_windy[2].z - low_calm[2].z
	print("  ball along the ground pushed %.2f m" % low_drift)
	_check(absf(low_drift) < 0.2, "the wind leaves a rolling ball alone")
	# Into the wind the ball falls short, with it it carries on.
	var into := _flight(0.5, Vector3(-8, 0, 0))
	var behind := _flight(0.5, Vector3(8, 0, 0))
	_check(into[1] < calm[1] and behind[1] > calm[1], "a headwind holds a high ball up, a tailwind carries it")


func _test_random_weather() -> void:
	var seen := {}
	for i in 200:
		var w := ShintyWeather.make(ShintyWeather.Kind.RANDOM)
		seen[w["kind"]] = true
		if not (w["wet"] >= 0.0 and w["wet"] <= 1.0):
			_check(false, "wetness in range")
			return
	_check(seen.size() == ShintyWeather.KINDS.size() and not seen.has(ShintyWeather.Kind.RANDOM),
		"Random picks every kind of weather (%d seen)" % seen.size())
	_check(ShintyWeather.make()["wet"] == 0.5 and ShintyWeather.make()["wind"] == Vector2.ZERO,
		"no weather given: the old damp, still conditions")


func _test_slips() -> void:
	var teams := TeamData.load_teams()
	var slips := {}
	for kind in [ShintyWeather.Kind.SUNNY, ShintyWeather.Kind.POURING]:
		var n := 0
		var downs := 0
		for i in 2:
			var m = MatchScene.instantiate()
			m.manual_step = true
			m.config = {"home": teams[0], "away": teams[1], "human_side": -1, "difficulty": 1,
				"half_seconds": 120.0, "seed": 300 + i, "weather": kind, "extra_time": false}
			root.add_child(m)
			var steps := 0
			while m.state != m.State.FULL_TIME and steps < 60 * 400:
				m.step(1.0 / 60.0)
				steps += 1
			_check(m.state == m.State.FULL_TIME, "%s match %d reaches full time" % [ShintyWeather.NAMES[kind], i + 1])
			for e in m.events:
				if e["type"] == "slip":
					n += 1
				elif e["type"] == "knockdown":
					downs += 1
			m.free()
		slips[kind] = n
		print("  %s: %d slips, %d knockdowns over two matches" % [ShintyWeather.NAMES[kind], n, downs])
	_check(slips[ShintyWeather.Kind.SUNNY] == 0, "nobody slips on a dry pitch")
	_check(slips[ShintyWeather.Kind.POURING] > 0, "players go down on a soaking pitch")
