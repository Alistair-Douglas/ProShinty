extends SceneTree
## Every ground is flat where the match is played: the players and the ball
## are drawn at height 0, so any rise in the land over the pitch (and a few
## metres round it) shows them sunk into the grass.

const MARGIN := 3.0      ## metres past the lines that must be flat too
const LIMIT := 0.02      ## metres


func _initialize() -> void:
	var ok := true
	var files := ["aberdour.gd", "kingussie.gd", "tighnabruaich.gd", "portree.gd"]
	for v in ShintyPitch.VENUE_NAMES.size():
		var p := ShintyPitch.new()
		p.hl = p.length_yd * ShintyPitch.YARD_M * 0.5
		p.hw = p.width_yd * ShintyPitch.YARD_M * 0.5
		p.noise.seed = p.layout_seed
		p.noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		p.noise.frequency = 0.012
		p._layout = load("res://pitch/venues/" + files[v]).new(p)
		var worst := 0.0
		var at := Vector2.ZERO
		var x := -p.hl - MARGIN
		while x <= p.hl + MARGIN:
			var z := -p.hw - MARGIN
			while z <= p.hw + MARGIN:
				var h := absf(p.height_m(x, z))
				if h > worst:
					worst = h
					at = Vector2(x, z)
				z += 1.0
			x += 1.0
		print("%s: highest point on the pitch %.3f m at %s" % [ShintyPitch.VENUE_NAMES[v], worst, at])
		if worst > LIMIT:
			ok = false
			print("FAIL: %s pitch not flat" % ShintyPitch.VENUE_NAMES[v])
		p.free()
	print("ground test ", "passed" if ok else "FAILED")
	quit(0 if ok else 1)
