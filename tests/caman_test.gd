extends SceneTree
## Checks the caman designer's pieces: designs survive bad data, every shape
## keeps its striking centre where the swing physics expect it, a club's
## caman and helmet reach its players, saved designs load again, and the
## designer screen edits and saves a design.
## godot --headless --path . -s tests/caman_test.gd

var ok := true


func _initialize() -> void:
	_run.call_deferred()


func _check(cond: bool, what: String) -> void:
	if not cond:
		print("FAIL ", what)
		ok = false


func _rng(seed_val: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_val
	return r


func _run() -> void:
	var game = root.get_node("Game")
	game.camans_path = "user://camans_test.json"  # leave this machine's own designs alone

	# Bad or partial data falls back to the defaults.
	var d := ShintyCaman.sanitize({"shape": 99, "grip": "not a colour", "bands": -2, "wrap": 1, "helmet": ""})
	_check(d["shape"] == ShintyCaman.SHAPES.size() - 1, "shape clamped")
	_check(d["grip"] == ShintyCaman.DEFAULT["grip"], "bad colour replaced")
	_check(d["bands"] == 0 and d["wrap"] == true and d["helmet"] == "", "bands, wrap, helmet")
	_check(ShintyCaman.sanitize("junk") == ShintyCaman.DEFAULT, "non-dictionary")
	var kin: Dictionary = game.teams[0]
	var club := ShintyCaman.for_team(kin)
	_check(Color(club["grip"]).is_equal_approx(Color(str(kin["colors"]["primary"]))), "club grip colour")

	# Every shape: the bas reaches the striking centre, and the full design builds.
	for shape in ShintyCaman.SHAPES.size():
		var n := Node3D.new()
		root.add_child(n)
		ShintyCaman.build(n, {"shape": shape, "wood": 3, "wrap": true, "bands": 3}, true)
		var box := AABB()
		for c in n.get_children():
			box = box.merge(c.get_aabb()) if box.has_volume() else c.get_aabb()
		var head := ShintyPlayerModel.HEAD_LOCAL
		_check(n.get_child_count() == 3 + 1 + 3, "shape %d has shaft, grip, knob, bas tape and 3 bands" % shape)
		_check(absf(box.position.y + ShintyPlayerModel.CAMAN_LENGTH) < 0.03, "shape %d length" % shape)
		_check(box.position.z < head.z and box.end.z > head.z - 0.06, "shape %d bas round the striking centre" % shape)
		n.free()

	# A club's caman and helmet reach its players; keepers get the keeper's bas.
	var team: Dictionary = kin.duplicate()
	team["caman"] = ShintyCaman.sanitize({"shape": 1, "helmet": "#f2c400", "grip": "#1e8a3c"})
	var m := ShintyPlayerModel.new()
	root.add_child(m)
	m.setup({"number": 9, "position": "CF"}, team)
	_check(m.caman_design["shape"] == 1 and m.caman_design["grip"] == "#1e8a3c", "player carries the club caman")
	_check(m.helmet_color.is_equal_approx(Color("f2c400")), "helmet colour from the design")
	var gk := ShintyPlayerModel.new()
	root.add_child(gk)
	gk.setup({"number": 1, "position": "GK"}, team)
	_check(gk.caman_design["shape"] == ShintyCaman.SHAPES.find("Keeper"), "keeper's bas")
	_check(team["caman"]["shape"] == 1, "keeper change doesn't touch the club design")
	m.queue_free()
	gk.queue_free()

	# The bench builds, shows the helmet and turns the caman.
	var bench := ShintyCamanBench.new()
	bench.set_design({"wrap": true, "bands": 2}, kin)
	root.add_child(bench)
	await process_frame
	_check(bench.find_child("DesignedCaman", true, false) != null, "bench shows the caman")
	_check(bench._helmet_holder.get_child_count() > 5, "bench shows a helmet")
	bench.free()

	# Saving gives the club the design and it loads again next time.
	game.set_team_caman(3, {"grip": "#6b3fa0", "bands": 2})
	var id := str(game.teams[3]["id"])
	game.teams[3].erase("caman")
	game._load_camans()
	_check(game.teams[3].has("caman") and game.teams[3]["caman"]["grip"] == "#6b3fa0", "saved design loads")
	_check(game.team_caman(3)["bands"] == 2, "team_caman")
	_check(game.camans.has(id), "camans keyed by club id")

	# One player can have a caman of their own; the rest keep the club's.
	var ps: Array = game.teams[3]["players"]
	var nine: int = int(ps[0]["number"])
	var other: Dictionary = ps[1]
	game.set_player_caman(3, nine, {"grip": "#f07c1a", "face": 3})
	game.teams[3].erase("caman")
	for p in ps:
		p.erase("caman")
	game._load_camans()
	_check(ps[0]["caman"]["grip"] == "#f07c1a" and ps[0]["caman"]["face"] == 3, "player's own caman loads")
	_check(other["caman"]["grip"] == "#6b3fa0", "team-mates keep the club caman")
	_check(game.has_own_caman(3, nine) and not game.has_own_caman(3, int(other["number"])), "has_own_caman")
	_check(game.player_caman(3, nine)["grip"] == "#f07c1a", "player_caman")
	game.set_team_caman(3, {"grip": "#1e8a3c"})
	_check(ps[0]["caman"]["grip"] == "#f07c1a" and other["caman"]["grip"] == "#1e8a3c", "club save keeps own camans")
	var pm := ShintyPlayerModel.new()
	root.add_child(pm)
	pm.setup(ps[0], game.teams[3])
	_check(pm.caman_design["grip"] == "#f07c1a", "model carries the player's own caman")
	pm.queue_free()
	# The first designer saved a bare club design; it still loads.
	var f := FileAccess.open(game.camans_path, FileAccess.WRITE)
	f.store_string(JSON.stringify({id: {"shape": 2, "grip": "#8fd63c"}}))
	f.close()
	game._load_camans()
	_check(game.team_caman(3)["shape"] == 2 and not game.has_own_caman(3, nine), "old save format")

	# Face angle: a laid-back face launches the same swing higher, an upright one lower.
	var elev := []
	for face in [0, 1, 3]:
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		var r := ShintyStrike.compute_swing({"aim": Vector3.FORWARD, "power": 0.8, "loft": 0.3, "skill": 80.0,
			"control": 80.0, "rng": rng, "face_degrees": ShintyCaman.FACE_DEGREES[face]})
		var v: Vector3 = r["velocity"]
		elev.append(rad_to_deg(atan2(v.y, Vector2(v.x, v.z).length())))
	_check(elev[0] < elev[1] and elev[1] < elev[2], "face angle sets launch height %s" % [elev])
	var hit_front := ShintyMatchAdapter.swing_like_match({"caman": {"face": 3, "face_back": 0}, "shooting": 80, "control": 80},
		Vector2.RIGHT, 30.0, 6.0, "shooting", Vector2.ZERO, 0.0, 0.0, 0.0, 0.0, _rng(3), false)
	var hit_back := ShintyMatchAdapter.swing_like_match({"caman": {"face": 3, "face_back": 0}, "shooting": 80, "control": 80},
		Vector2.RIGHT, 30.0, 6.0, "shooting", Vector2.ZERO, 0.0, 0.0, 0.0, 0.0, _rng(3), true)
	_check(hit_front["ball_vz"] > hit_back["ball_vz"], "shies use the back face")

	# The designer screen: open, change the grip tape, save to a club.
	load("res://ui/menu_backdrop.gd").lite = true
	var menu = load("res://scenes/main_menu.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	menu._open_designer()
	menu._show("camans", true)
	menu.design_club.select(5)
	menu._design_club_changed()
	var grip: ShintyOptionRow = menu.design_rows["grip"]
	grip.step(1)
	var want: String = "#" + ShintyCaman.PALETTE[grip.selected][1]
	_check(menu.design["grip"] == want, "grip row changes the design")
	menu.design_rows["band"].step(1)
	_check(menu.design["bands"] == 1, "picking a band colour adds a band")
	_check(menu.backdrop.bench.design["grip"] == want, "bench follows the design")
	menu._save_design()
	_check(game.teams[5].get("caman", {}).get("grip", "") == want, "save gives the club the caman")
	# Give one player their own: the picker lists the squad by shirt number.
	var club_face: int = game.team_caman(5)["face"]
	menu.design_player.step(1)
	var n: int = menu._design_number()
	_check(n > 0, "player picker lists players")
	menu.design_rows["face"].step(1)
	menu._save_design()
	_check(game.has_own_caman(5, n) and game.player_caman(5, n)["face"] == menu.design["face"], "save gives one player a caman")
	_check(game.team_caman(5)["face"] == club_face, "club caman unchanged")
	menu.queue_free()

	DirAccess.remove_absolute(ProjectSettings.globalize_path(game.camans_path))

	print("caman test: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
