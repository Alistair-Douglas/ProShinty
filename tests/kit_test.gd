extends SceneTree
## Checks every club has a home and change kit, and that no pairing of clubs
## puts two sides in shirts that look alike.
## godot --headless --path . -s tests/kit_test.gd
const TeamData := preload("res://scripts/team_data.gd")


func _initialize() -> void:
	var teams := TeamData.load_teams()
	var ok := teams.size() >= 37
	var spares := 0
	for t in teams:
		var home := TeamData.home_kit(t)
		var away := TeamData.away_kit(t)
		for k in ["primary", "secondary", "shorts", "socks"]:
			if not home.has(k) or not away.has(k):
				print("FAIL %s kit has no %s" % [t["id"], k])
				ok = false
		if TeamData.kits_clash(home, away):
			print("FAIL %s change kit looks like its home kit" % t["id"])
			ok = false
		for u in teams:
			if u == t:
				continue
			var kits := TeamData.match_kits(t, u)
			if TeamData.kits_clash(kits[0], kits[1]):
				print("FAIL %s v %s: shirts clash" % [t["id"], u["id"]])
				ok = false
			if kits[1] != TeamData.home_kit(u) and kits[1] != TeamData.away_kit(u):
				spares += 1
			var ref := {"primary": TeamData.referee_colour(kits)}
			if TeamData.kits_clash(ref, kits[0]) or TeamData.kits_clash(ref, kits[1]):
				print("FAIL %s v %s: referee clashes" % [t["id"], u["id"]])
				ok = false
	# The clubs Alistair named: Aberdour in black and white, Kingussie in red and blue.
	var by_id := {}
	for t in teams:
		by_id[t["id"]] = t
	var abd := TeamData.home_kit(by_id["aberdour"])
	var kin := TeamData.home_kit(by_id["kingussie"])
	ok = ok and Color(abd["primary"]).get_luminance() < 0.15 and Color(abd["secondary"]).get_luminance() > 0.85
	ok = ok and Color(kin["primary"]).r > 0.6 and Color(kin["secondary"]).b > 0.6 and kin.get("pattern") == "hoops"
	# Kingussie v Aberdour (the default fixture) wear their home kits.
	var fixture := TeamData.match_kits(by_id["kingussie"], by_id["aberdour"])
	ok = ok and fixture[1] == abd
	print("teams %d, pairings on a spare kit %d" % [teams.size(), spares])
	print("KIT TEST ", "PASSED" if ok else "FAILED")
	quit(0 if ok else 1)
