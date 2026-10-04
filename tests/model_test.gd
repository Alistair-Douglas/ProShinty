extends SceneTree
## Headless checks for the shinty models and physics.
## Run: godot --headless --path . -s tests/model_test.gd

var failures := 0
var root3d: Node3D


func check(ok: bool, what: String) -> void:
	if ok:
		print("  ok   ", what)
	else:
		failures += 1
		print("  FAIL ", what)


func _initialize() -> void:
	root3d = Node3D.new()
	get_root().add_child(root3d)
	_run.call_deferred()
	create_timer(90.0).timeout.connect(func(): print("TIMEOUT"); quit(2))


func _run() -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://data/teams.json"))
	var teams: Array = data["teams"]

	print("Players")
	var heights := []
	for team in teams:
		for p in team["players"]:
			var m := ShintyPlayerModel.new()
			root3d.add_child(m)
			m.setup(p, team)
			m.advance(0.016)
			var top := _highest_point(m)
			heights.append([p["name"], team["short"], m.height_cm, top, m.build])
			if p["number"] == 1 or p["number"] == 11:
				print("    %s %s: %.0f cm, build %.2f, head top at %.2f m, kit %s helmet %s" % [
					team["short"], p["name"], m.height_cm, m.build, top,
					m.shirt_color.to_html(false), m.helmet_color.to_html(false)])
			check(absf(top - m.height_cm / 100.0) < 0.1, "%s %s stands %.2f m for %.0f cm" % [team["short"], p["name"], top, m.height_cm])
			m.queue_free()
	var tall := ShintyPlayerModel.new()
	root3d.add_child(tall)
	tall.setup({"name": "Big", "number": 5, "height_cm": 195, "weight_kg": 100}, teams[0])
	var short := ShintyPlayerModel.new()
	root3d.add_child(short)
	short.setup({"name": "Wee", "number": 7, "height_cm": 168, "weight_kg": 62}, teams[1])
	tall.advance(0.016)
	short.advance(0.016)
	check(_highest_point(tall) > _highest_point(short) + 0.2, "height_cm/weight_kg overrides change size")
	check(tall.build > short.build + 0.3, "weight_kg changes build (%.2f vs %.2f)" % [tall.build, short.build])
	check(short.helmet_color == Color(teams[1]["colors"]["primary"]), "helmet takes the team colour")

	print("Swing")
	var striker := ShintyPlayerModel.new()
	striker.manual_update = true
	root3d.add_child(striker)
	striker.setup(teams[0]["players"][10], teams[0])
	var hits := []
	striker.strike.connect(func(pos, pow): hits.append([pos, pow]))
	striker.play_action(&"swing", 1.0)
	var max_head_speed := 0.0
	var min_head_y := 9.0
	var max_head_y := -9.0
	for i in 60:
		striker.advance(1.0 / 60.0)
		var hp := striker.get_caman_head_position()
		min_head_y = minf(min_head_y, hp.y)
		max_head_y = maxf(max_head_y, hp.y)
		max_head_speed = maxf(max_head_speed, striker.get_caman_head_velocity().length())
	check(hits.size() == 1, "swing emits one strike (got %d)" % hits.size())
	if hits.size() == 1:
		var at: Vector3 = hits[0][0]
		print("    contact at ", at, "  strike spot ", striker.get_strike_spot())
		check(at.y < 0.08 and at.y > -0.01, "caman meets the ground ball (head y %.2f)" % at.y)
		check(at.distance_to(striker.get_strike_spot()) < 0.3, "contact is at the strike spot (%.2f m)" % at.distance_to(striker.get_strike_spot()))
	check(max_head_y > 1.3, "backswing lifts the caman head high (%.2f m)" % max_head_y)
	check(min_head_y > -0.02, "caman never goes into the ground (%.2f)" % min_head_y)
	print("    animated head speed peak %.1f m/s" % max_head_speed)
	var lefty := ShintyPlayerModel.new()
	lefty.manual_update = true
	root3d.add_child(lefty)
	lefty.setup({"name": "Lefty", "number": 9, "hand": "L"}, teams[0])
	lefty.advance(0.016)
	check(_hook_y(striker) > 0.3, "standing after a swing, the hook faces up (%.2f)" % _hook_y(striker))
	var blocker := ShintyPlayerModel.new()
	blocker.manual_update = true
	root3d.add_child(blocker)
	blocker.setup(teams[0]["players"][4], teams[0])
	blocker.set_reach(Vector3(0.2, 0.03, -0.9), 1.0)
	blocker.play_action(&"block", 1.0)
	for i in 15:
		blocker.advance(1.0 / 60.0)
	check(_hook_y(blocker) < -0.3, "blocking, the hook is turned down (%.2f)" % _hook_y(blocker))
	check(lefty.get_strike_spot().x < 0.0 and lefty.get_caman_head_position().x < 0.0, "left-hander carries the caman on the left")

	print("Carry and running swing")
	var runner := ShintyPlayerModel.new()
	runner.manual_update = true
	root3d.add_child(runner)
	runner.setup(teams[0]["players"][10], teams[0])
	var runner_start := [runner._seed, runner._phase, runner._time]
	runner.shoulder_carry = false
	runner.set_locomotion(Vector3(0, 0, -6.0))
	for i in 60:
		runner.advance(1.0 / 60.0)
	var carried := runner.get_caman_head_position()
	check(carried.y > 0.15 and carried.y < 0.8 and carried.z < -0.4, "running, the caman head is carried low out in front (%s)" % carried)
	check(_top_hand_gap(runner) > 0.15, "running, the top hand is off the caman (%.2f m)" % _top_hand_gap(runner))
	check(_hook_y(runner) > 0.3, "running, the hook of the caman faces up (%.2f)" % _hook_y(runner))
	runner.look_at_point(runner.global_transform * Vector3(0, 0, -2.5))
	for i in 40:
		runner.advance(1.0 / 60.0)
	check(_top_hand_gap(runner) < 0.12, "closing on the ball, both hands are on the caman (%.2f m)" % _top_hand_gap(runner))
	runner.look_at_point(null)
	check(_hook_y(runner) > 0.3, "carried two-handed, the hook faces up (%.2f)" % _hook_y(runner))
	var run_hits := []
	runner.strike.connect(func(pos, pow): run_hits.append(pos))
	runner.play_action(&"swing", 1.0)
	var gap_at_hit := -1.0
	for i in 60:
		runner.advance(1.0 / 60.0)
		if run_hits.size() == 1 and gap_at_hit < 0.0:
			gap_at_hit = _top_hand_gap(runner)
	check(run_hits.size() == 1 and (run_hits[0] as Vector3).y < 0.08, "a swing on the run still meets the ground ball")
	check(gap_at_hit >= 0.0 and gap_at_hit < 0.12, "both hands are on the caman at contact (%.2f m)" % gap_at_hit)
	var lefty_run := ShintyPlayerModel.new()
	lefty_run.manual_update = true
	root3d.add_child(lefty_run)
	lefty_run.setup({"name": "Lefty", "number": 9, "hand": "L"}, teams[0])
	# Everyone runs a little out of step; line the lefty's stride up with the
	# runner's for the comparison.
	lefty_run._seed = runner_start[0]
	lefty_run._phase = runner_start[1]
	lefty_run._time = runner_start[2]
	lefty_run.shoulder_carry = false
	lefty_run.set_locomotion(Vector3(0, 0, -6.0))
	for i in 60:
		lefty_run.advance(1.0 / 60.0)
	check(absf(lefty_run.get_caman_head_position().x + carried.x) < 0.1, "left-hander carries the caman the mirror way (%.2f vs %.2f)" % [lefty_run.get_caman_head_position().x, carried.x])
	var shoulder := ShintyPlayerModel.new()
	shoulder.manual_update = true
	root3d.add_child(shoulder)
	shoulder.setup(teams[0]["players"][10], teams[0])
	shoulder.shoulder_carry = true
	shoulder.set_locomotion(Vector3(0, 0, -6.0))
	for i in 60:
		shoulder.advance(1.0 / 60.0)
	check(shoulder.get_caman_head_position().y > 1.5, "a shoulder carrier holds the caman up by the shoulder (head %.2f m)" % shoulder.get_caman_head_position().y)
	var styles := {}
	for t in teams:
		for p in t["players"]:
			styles[ShintyPlayerModel.carries_on_shoulder(p)] = true
	check(styles.size() == 2, "some players carry on the shoulder, some by the waist")
	var lefty_hits := []
	lefty_run.strike.connect(func(pos, pow): lefty_hits.append(pos))
	lefty_run.play_action(&"swing", 1.0)
	for i in 60:
		lefty_run.advance(1.0 / 60.0)
	check(lefty_hits.size() == 1 and (lefty_hits[0] as Vector3).y < 0.08 and (lefty_hits[0] as Vector3).x < 0.0,
		"a left-hander's running swing meets the ground ball on the left")
	for a in ["pass", "volley", "tackle", "trap", "feet_trap", "thigh_trap", "chest_trap", "save_left", "save_right", "save_feet", "save_high_left", "save_high_right", "celebrate"]:
		var done := [false]
		var cb := func(n): done[0] = true
		striker.action_finished.connect(cb)
		striker.play_action(StringName(a), 0.8, 1.2)
		for i in 120:
			striker.advance(1.0 / 60.0)
		striker.action_finished.disconnect(cb)
		check(done[0], "%s plays and finishes" % a)
	striker.set_locomotion(Vector3(0, 0, -7))
	var foot_min := 9.0
	for i in 90:
		striker.advance(1.0 / 60.0)
		foot_min = minf(foot_min, _foot_y(striker))
	check(foot_min > -0.08 and foot_min < 0.12, "feet stay near the ground when sprinting (lowest %.2f)" % foot_min)

	print("Ball flight")
	var b := ShintyBallPhysics.new()
	var v := 40.0
	var ang := deg_to_rad(25)
	b.strike(Vector3(0, sin(ang), -cos(ang)) * v, Vector3(40, 0, 0))
	var predicted := b.predict_landing()
	var landed := _fly(b)
	print("    40 m/s at 25 deg lands after %.1f m (vacuum would be %.1f m)" % [landed.length(), v * v * sin(2 * ang) / 9.81])
	check(landed.length() > 60 and landed.length() < 110, "long lofted hit carries 60-110 m")
	check(predicted.distance_to(Vector3(landed.x, 0, landed.y)) < 1.5 or absf(predicted.length() - landed.length()) < 1.5, "predict_landing matches the flight")
	b = ShintyBallPhysics.new()
	b.strike(Vector3(0, 0, -20))
	var rolled := _roll(b)
	print("    20 m/s ground ball rolls %.1f m" % rolled)
	check(rolled > 35 and rolled < 70, "ground ball at 20 m/s rolls 35-70 m")
	b = ShintyBallPhysics.new()
	b.position = Vector3(0, 3, 0)
	var ev_all := []
	for i in 300:
		ev_all.append_array(b.step(1.0 / 60.0))
	var bounces := ev_all.filter(func(e): return e["type"] == "bounce").size()
	check(bounces >= 2 and not b.is_airborne(), "dropped ball bounces (%d) and settles" % bounces)

	print("Strike physics")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var still := ShintyStrike.compute({"aim": Vector3.FORWARD, "power": 1.0, "skill": 99, "control": 99, "rng": rng})
	var weak := ShintyStrike.compute({"aim": Vector3.FORWARD, "power": 1.0, "skill": 30, "control": 99, "rng": rng})
	var tap := ShintyStrike.compute({"aim": Vector3.FORWARD, "power": 0.1, "skill": 60, "control": 99, "rng": rng})
	print("    full hit by a 99 shooter: %.1f m/s (%.0f km/h); by a 30 shooter: %.1f m/s; tap: %.1f m/s" % [
		still["speed"], still["speed"] * 3.6, weak["speed"], tap["speed"]])
	check(still["speed"] > 38 and still["speed"] < 50, "top hit speed is 38-50 m/s")
	check(weak["speed"] < still["speed"] - 4, "shooting rating raises hit speed")
	var oncoming := ShintyStrike.compute({"aim": Vector3.FORWARD, "power": 1.0, "skill": 99, "control": 99,
		"ball_velocity": Vector3(0, 0, 15), "rng": rng})
	check(oncoming["speed"] > still["speed"], "an oncoming ball goes back faster (%.1f m/s)" % oncoming["speed"])
	var miss := ShintyStrike.compute({"aim": Vector3.FORWARD, "power": 1.0, "contact_offset": 0.5})
	check(miss["miss"], "ball out of reach is a miss")
	var off := ShintyStrike.compute({"aim": Vector3.FORWARD, "power": 1.0, "skill": 99, "control": 99, "contact_offset": 0.25, "rng": rng})
	check(off["speed"] < still["speed"] * 0.85, "off-centre contact loses pace (%.1f m/s)" % off["speed"])
	var lob := ShintyStrike.compute({"aim": Vector3.FORWARD, "power": 0.8, "loft": 1.0, "skill": 80, "control": 80, "rng": rng})
	check((lob["velocity"] as Vector3).y > 10, "loft sends the ball up (vy %.1f)" % (lob["velocity"] as Vector3).y)
	var spread := []
	for i in 200:
		var s := ShintyStrike.compute({"aim": Vector3.FORWARD, "power": 0.8, "skill": 40, "control": 50, "rng": rng})
		var vv: Vector3 = s["velocity"]
		spread.append(absf(rad_to_deg(atan2(vv.x, -vv.z))))
	var spread_good := []
	for i in 200:
		var s := ShintyStrike.compute({"aim": Vector3.FORWARD, "power": 0.8, "skill": 95, "control": 95, "rng": rng})
		var vv: Vector3 = s["velocity"]
		spread_good.append(absf(rad_to_deg(atan2(vv.x, -vv.z))))
	var avg := func(a: Array) -> float: return a.reduce(func(x, y): return x + y, 0.0) / a.size()
	print("    average aim error: %.1f deg (rating 40), %.1f deg (rating 95)" % [avg.call(spread), avg.call(spread_good)])
	check(avg.call(spread) > avg.call(spread_good) * 2.0, "better players are more accurate")
	var p30 := ShintyStrike.power_for_distance(30.0, 70.0, 0.0)
	var p60 := ShintyStrike.power_for_distance(60.0, 70.0, 0.8)
	print("    power for a 30 m ground pass %.2f, 60 m lob %.2f" % [p30, p60])
	check(p30 > 0.0 and p30 < p60, "power_for_distance scales with distance")

	print("Hail")
	var hail := ShintyHailModel.new()
	root3d.add_child(hail)
	hail.global_position = Vector3(0, 0, -20)
	hail.rotation.y = PI  # net towards -Z world, pitch towards +Z
	var r := _shoot_at(hail, Vector3(0, 0.5, 0), Vector3(0, 1.2, -20), 30.0)
	check(r["goal"], "shot at the middle of the hail is a goal")
	check(r["net"], "the net stops it")
	check(r["final"].z > -22.0 and r["final"].z < -19.5, "ball stays in the net (z %.2f)" % r["final"].z)
	r = _shoot_at(hail, Vector3(0, 0.5, 0), Vector3(1.88, 1.0, -20), 30.0)
	check(r["post"] and not r["goal"], "shot at the post rebounds, no goal")
	r = _shoot_at(hail, Vector3(0, 0.5, 0), Vector3(0, 3.6, -20), 30.0)
	check(not r["goal"], "shot over the bar is no goal")
	r = _shoot_at(hail, Vector3(0, 0.5, 0), Vector3(3.5, 1.0, -20), 30.0)
	check(not r["goal"], "shot wide is no goal")
	r = _shoot_at(hail, Vector3(0, 0.5, -26), Vector3(0, 1.0, -20), 20.0)
	check(not r["goal"], "shot into the back of the net from behind is no goal")

	print("Body physics")
	# A knock rocks the trunk, which settles again.
	var rock := _figure("Rocker", 4)
	rock.set_locomotion(Vector3(0, 0, -4))
	_step(rock, 1.0)
	var calm := rock._sway.length()
	rock.set_locomotion(Vector3(3, 0, -4))
	var most := 0.0
	for f in 30:
		rock.advance(1.0 / 60.0)
		most = maxf(most, rock._sway.length())
	_step(rock, 2.0)
	print("    trunk sway: running %.3f, knocked %.3f, after %.3f rad" % [calm, most, rock._sway.length()])
	check(most > calm + 0.1, "a knock rocks the trunk")
	check(rock._sway.length() < calm + 0.03, "and it settles again")
	# Nobody moves in step with anyone else.
	var a1 := _figure("Twin A", 2)
	var a2 := _figure("Twin B", 3)
	var apart := 0.0
	for f in 360:
		a1.advance(1.0 / 60.0)
		a2.advance(1.0 / 60.0)
		var hips1: Vector3 = a1._skel.get_bone_pose_position(a1._bone["Hips"])
		var hips2: Vector3 = a2._skel.get_bone_pose_position(a2._bone["Hips"])
		apart = maxf(apart, hips1.distance_to(hips2))
	check(apart > 0.01, "two players standing don't sway in step (%.3f m apart)" % apart)
	# A small knock is a stumble; a big one puts them on the grass and they get up.
	for pw in [0.3, 1.0]:
		var k := _figure("Faller %.1f" % pw, 5)
		k.set_locomotion(Vector3(0, 0, -5))
		_step(k, 1.0)
		k.set_locomotion(Vector3(0, 0, -1))
		k.advance(1.0 / 60.0)
		k.play_action(&"stumble", pw)
		var low := 9.0
		var went_down := false
		var t := 0.0
		while k.is_busy() and t < 4.0:
			k.advance(1.0 / 60.0)
			t += 1.0 / 60.0
			low = minf(low, _head_y(k))
			went_down = went_down or k.is_down()
		_step(k, 0.3)
		print("    stumble %.1f: lowest head %.2f m, over after %.2f s, head then %.2f m" % [pw, low, t, _head_y(k)])
		if pw < 0.5:
			check(not went_down and low > 1.0, "a small knock is a stumble, not a fall")
		else:
			check(went_down and low < 0.5, "a big knock puts them on the grass")
			check(t < 2.0, "and they're up within two seconds")
			check(k._rag == null and _head_y(k) > 1.4, "standing again, ragdoll gone")
	# Knocked down while running along: the body goes where the player goes.
	var mover := _figure("Mover", 6)
	mover.set_locomotion(Vector3(0, 0, -5))
	_step(mover, 0.5)
	mover.set_locomotion(Vector3(0, 0, -1.5))
	mover.advance(1.0 / 60.0)
	mover.play_action(&"stumble", 1.0)
	for f in 50:
		mover.position += Vector3(0, 0, -1.5) / 60.0
		mover.advance(1.0 / 60.0)
	var hips_w: Vector3 = mover._skel.global_transform * mover._skel.get_bone_global_pose(mover._bone["Hips"]).origin
	check(Vector2(hips_w.x - mover.position.x, hips_w.z - mover.position.z).length() < 1.2,
		"a fallen body stays with the player (%.2f m away)" % Vector2(hips_w.x - mover.position.x, hips_w.z - mover.position.z).length())
	# Something else happening cuts the lie-down short.
	mover.play_action(&"swing", 1.0)
	_step(mover, 0.35)
	check(mover._rag == null, "a new action takes the body back from the ragdoll")

	print("Match adapter (yards)")
	var fake := FakeMatch.new()
	var sim := ShintyMatchAdapter.BallSim.new(Vector2(150, 75), 4.0, 3.33)
	fake.ball_pos = Vector2(130, 37.5)
	var st := ShintyMatchAdapter.strike({"shooting": 90, "control": 90}, Vector2(1, 0), 0.9, 0.15, "shot", Vector2.ZERO, 0.0, 0.0, rng)
	fake.ball_vel = st["ball_vel"]
	fake.ball_vz = st["ball_vz"]
	var goal_end := -1
	for i in 240:
		for e in sim.step(fake, 1.0 / 60.0):
			if e["type"] == "goal":
				goal_end = e["end"]
	check(goal_end == 1, "BallSim scores in the x = 150 hail from 20 yards (end %d)" % goal_end)
	check(fake.ball_pos.x > 150.0 and fake.ball_pos.x < 152.5, "ball ends in the net (x %.1f yd)" % fake.ball_pos.x)
	var fig := ShintyMatchAdapter.build_player(root3d, teams[1]["players"][3], teams[1])
	ShintyMatchAdapter.update_player(fig, Vector2(5, 0), 0.3)
	check(fig["model"].is_busy(), "adapter starts the swing when the match swings")
	check(absf(_highest_point(fig["model"]) - fig["model"].height_cm / 100.0 / 0.9144) < 0.15, "adapter figure is in yards")

	print("Imported body (Blender)")
	ShintyPlayerLook.body_dir = "res://tests/fixtures/bodies"
	for bb in [0.2, 0.9]:
		var im := ShintyPlayerModel.new()
		root3d.add_child(im)
		im.setup(teams[0]["players"][5], teams[0])
		im.build = bb
		im.advance(0.016)
		var body_mi := im.find_child("Body", true, false) as MeshInstance3D
		var aabb := body_mi.mesh.get_aabb()
		check(absf(aabb.get_center().x) < 0.1, "imported body is centred (x %.3f)" % aabb.get_center().x)
		# The fixture is a 1,400-triangle body: far fewer than the built one.
		var tris := 0
		for si in body_mi.mesh.get_surface_count():
			tris += body_mi.mesh.surface_get_array_index_len(si) / 3
		ShintyPlayerLook.use_imported_bodies = false
		var built := ShintyPlayerModel.new()
		root3d.add_child(built)
		built.setup(teams[0]["players"][5], teams[0])
		built.build = bb
		var built_mi := built.find_child("Body", true, false) as MeshInstance3D
		var built_tris := 0
		for si in built_mi.mesh.get_surface_count():
			built_tris += built_mi.mesh.surface_get_array_index_len(si) / 3
		built.queue_free()
		ShintyPlayerLook.use_imported_bodies = true
		check(built_tris - tris > 2000, "the imported body replaces the built one (%d vs %d triangles)" % [tris, built_tris])
		check(im.find_child("SpineAttach", true, false).has_meta("mesh_aabb"), "imported shirt front is measured for the sponsor")
		im.play_action(&"swing", 1.0)
		_step(im, 0.3)
		check(im.get_caman_head_position().is_finite(), "a player with an imported body swings")
		im.queue_free()
	ShintyPlayerLook.body_dir = "res://models/bodies"

	print("")
	print("FAILURES: %d" % failures if failures else "ALL PASSED")
	quit(1 if failures else 0)


class FakeMatch:
	var ball_pos := Vector2.ZERO
	var ball_vel := Vector2.ZERO
	var ball_z := 0.0
	var ball_vz := 0.0


func _shoot_at(hail: ShintyHailModel, from: Vector3, target: Vector3, speed: float) -> Dictionary:
	var b := ShintyBallPhysics.new()
	b.hails = [hail]
	b.place(from)
	# Aim with a little lift so the ball arrives at target height.
	var d := target - from
	var flat := Vector2(d.x, d.z).length()
	var t := flat / speed
	var vy := (d.y + 0.5 * 9.81 * t * t * 1.1) / t
	var dir := Vector3(d.x, 0, d.z).normalized() * speed
	b.strike(Vector3(dir.x, vy, dir.z))
	var out := {"goal": false, "net": false, "post": false}
	for i in 240:
		for e in b.step(1.0 / 60.0):
			if out.has(e["type"]):
				out[e["type"]] = true
	out["final"] = b.position
	return out


func _fly(b: ShintyBallPhysics) -> Vector2:
	for i in 1200:
		for e in b.step(1.0 / 120.0):
			if e["type"] == "bounce" or e["type"] == "landed":
				return Vector2(e["position"].x, e["position"].z)
	return Vector2(b.position.x, b.position.z)


func _roll(b: ShintyBallPhysics) -> float:
	for i in 1200:
		b.step(1.0 / 60.0)
		if b.velocity.length() < 0.01:
			break
	return Vector2(b.position.x, b.position.z).length()


func _highest_point(n: Node) -> float:
	var best := -99.0
	for c in n.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		if not mi.is_visible_in_tree() or mi.get_parent().name == "Caman":
			continue
		var aabb := mi.global_transform * mi.get_aabb()
		best = maxf(best, aabb.end.y)
	return best


func _foot_y(m: ShintyPlayerModel) -> float:
	var sk: Skeleton3D = m.get_node("Skeleton3D")
	var lo := 99.0
	for side in ["Left", "Right"]:
		var i := sk.find_bone(side + "Foot")
		lo = minf(lo, (sk.global_transform * sk.get_bone_global_pose(i).origin).y)
	return lo - 0.06 * m.height_cm / 180.0


## How far the top hand is from its grip at the butt of the caman, in metres.
func _top_hand_gap(m: ShintyPlayerModel) -> float:
	var sk: Skeleton3D = m.get_node("Skeleton3D")
	var side := "Right" if m.left_handed else "Left"
	var wrist := sk.global_transform * sk.get_bone_global_pose(sk.find_bone(side + "Hand")).origin
	var grip: Vector3 = m._caman.global_transform * Vector3(0, -ShintyPlayerModel.GRIP_TOP, 0)
	return maxf(0.0, wrist.distance_to(grip) - ShintyPlayerModel.HAND_GRIP * m.height_cm / 180.0)


## Which way the hook of the bas points: +1 straight up, -1 at the grass.
func _hook_y(m: ShintyPlayerModel) -> float:
	return (m._caman.global_transform.basis * Vector3(0, 0, -1)).normalized().y


func _figure(name: String, number: int) -> ShintyPlayerModel:
	var m := ShintyPlayerModel.new()
	m.manual_update = true
	root3d.add_child(m)
	m.setup({"name": name, "number": number, "position": "LM"}, {})
	return m


func _step(m: ShintyPlayerModel, secs: float) -> void:
	for f in int(secs * 60.0):
		m.advance(1.0 / 60.0)


func _head_y(m: ShintyPlayerModel) -> float:
	return (m._skel.global_transform * m._skel.get_bone_global_pose(m._bone["Head"]).origin).y
