extends RefCounted
## Kingussie Camanachd's pitch, The Dell, laid out from the satellite view
## and a drone photo of a match day.
##
## The real pitch runs north-west to south-east; here its long axis is X as
## usual, so -X is the north-west end and -Z the north-east side. North-west
## end: a green ball-stop net behind the hail and the small timber clubhouse
## by the corner. North-east side: dugouts, small covered stands, a
## portakabin and the big gravel car park with match-day marquees, young tree
## plantations beyond and the town up the slope. South-west side: a tall line
## of spruce close along the touchline, hospitality trailers and parked cars
## in front of it, then the River Spey, which curves round the south-east end
## behind the other ball-stop net, with the A9 beyond. The pitch is railed all
## round and striped lengthways. The Monadhliath and the Cairngorms close in
## on the horizon.

const WATER_LEVEL := -1.0

var p: ShintyPitch
var hl: float
var hw: float
var river: PackedVector2Array
var roads: Array[PackedVector2Array] = []
var town := Vector2(-430.0, -390.0)


func _init(pitch: ShintyPitch) -> void:
	p = pitch
	hl = p.hl
	hw = p.hw
	river = PackedVector2Array([Vector2(-3000, 520), Vector2(-1500, 300), Vector2(-700, 165),
			Vector2(-400, 125), Vector2(-250, 105), Vector2(-150, 95), Vector2(-80, 85), Vector2(-10, 68),
			Vector2(50, 58), Vector2(92, 46), Vector2(122, 15), Vector2(138, -30), Vector2(148, -80),
			Vector2(165, -160), Vector2(210, -260), Vector2(300, -420), Vector2(450, -700),
			Vector2(700, -1200), Vector2(1000, -2200), Vector2(1300, -3200)])
	roads = [
		# Track from the car park up to the town.
		PackedVector2Array([Vector2(-40, -hw - 28), Vector2(-25, -124), Vector2(-120, -260), town]),
		# The A9, on the far side of the river bend.
		PackedVector2Array([Vector2(215, 900), Vector2(185, 200), Vector2(200, -80), Vector2(320, -500), Vector2(700, -1500)]),
	]


func extra_cloud() -> float:
	return 0.1


## Thinner haze than Aberdour so the hills read on the horizon.
## Ad boards hang on the rail (3.5 m out), with a gap in front of the
## dugouts either side of halfway.
func board_rows() -> Array:
	var z := -hw - 3.35
	var x := hl + 3.35
	return [[Vector2(-hl, z), Vector2(-12.5, z), 0], [Vector2(12.5, z), Vector2(hl, z), 4],
		[Vector2(-x, -hw * 0.8), Vector2(-x, hw * 0.8), 3], [Vector2(x, -hw * 0.8), Vector2(x, hw * 0.8), 5]]


func fog_density() -> float:
	return 0.00009


func water() -> Dictionary:
	return {"level": WATER_LEVEL, "color": Color(0.1, 0.12, 0.12), "roughness": 0.06, "wave_scale": 0.8}


func ground_look() -> Dictionary:
	return {
		"wear": 0.12,
		"stripe_along_length": true,
		"stripe_width": 5.0,
		"stripe_strength": 0.11,
		"grass_color": Color(0.27, 0.45, 0.17),
		"rough_color": Color(0.5, 0.47, 0.31),     # dry straw-coloured meadow
		"earth_color": Color(0.3, 0.27, 0.25),     # heather on the hills
		"gravel_color": Color(0.55, 0.53, 0.5),
		"sand_color": Color(0.52, 0.49, 0.44),     # river shingle
		"field_strength": 0.35,
		"field_start": 260.0,
	}


func height_m(x: float, z: float) -> float:
	var wild: float = p.wildness(x, z, 10.0, 10.0)
	var pos := Vector2(x, z)
	# Floodplain: nearly flat, rising gently towards the town.
	var slope := 22.0 * smoothstep(150.0, 700.0, -(x * 0.55 + z * 0.75))
	# Hills all round: the Monadhliath to the west, the Cairngorms to the east.
	var r := pos.length()
	var ang := atan2(z, x)
	var amp := 380.0 + 320.0 * maxf(0.0, cos(ang)) + 120.0 * maxf(0.0, -cos(ang))
	var ridge := 1.0 - absf(p.noise.get_noise_2d(x * 0.06, z * 0.06))
	var hills := amp * smoothstep(900.0, 4200.0, r) * (0.45 + 0.55 * ridge)
	var h: float = maxf(slope, hills) + p.noise.get_noise_2d(x, z) * 1.2
	h *= wild
	# The Spey: a channel with shingle banks.
	var d: float = p.dist_to_path(pos, river)
	# Its bank stops short of the lines so the corner by it stays flat.
	var out := maxf(absf(x) - hl, absf(z) - hw)
	return lerpf(h, -2.8, (1.0 - smoothstep(9.0, 17.0, d)) * smoothstep(3.0, 8.0, out))


func ground_mask(x: float, z: float, h: float) -> Color:
	var c := Color(0, 0, 0, 0)
	var pos := Vector2(x, z)
	c.g = p.wildness(x, z, 8.0, 8.0)
	c.r = smoothstep(35.0, 150.0, h)  # heather
	# Gravel car park along the north-east side and round the north corner.
	if z < -(hw + 5.0) and z > -(hw + 32.0) and x > -hl - 8.0 and x < hl + 4.0:
		c.b = 1.0
	if x > -hl - 30.0 and x < -hl * 0.4 and z < -(hw + 4.0) and z > -(hw + 50.0):
		c.b = 0.9
	for road in roads:
		if p.dist_to_path(pos, road) < 3.2:
			c.b = 1.0
	# River shingle.
	c.a = smoothstep(-0.2, -1.2, h)
	if c.a > 0.0:
		c.g *= 1.0 - c.a
	return c


func build(root: Node3D, rng: RandomNumberGenerator) -> void:
	_build_trees(root, rng)
	_build_long_grass(root, rng)
	_build_ground_furniture(root)
	_build_town(root, rng)
	_build_cars(root, rng)


func _build_trees(root: Node3D, rng: RandomNumberGenerator) -> void:
	var near := ShintyPitch.TreeBatch.new()
	var far := ShintyPitch.TreeBatch.new()
	# Birch, alder and the odd pine along both banks of the Spey.
	for i in river.size() - 1:
		var a := river[i]
		var b := river[i + 1]
		if a.length() > 900.0 and b.length() > 900.0:
			continue
		var dir := (b - a).normalized()
		var side := Vector2(-dir.y, dir.x)
		var t := 0.0
		var len := a.distance_to(b)
		while t < len:
			for s in [-1.0, 1.0]:
				if rng.randf() < 0.75:
					var q: Vector2 = a + dir * t + side * s * rng.randf_range(12.0, 24.0)
					if absf(q.x) < hl + 14.0 and absf(q.y) < hw + 20.0:
						continue
					var h: float = p.height_m(q.x, q.y)
					var base := Vector3(q.x, h, q.y)
					var roll := rng.randf()
					if roll < 0.6:
						p.add_birch(near, rng, base)
					elif roll < 0.85:
						p.add_broadleaf(near, rng, base, 0.75)
					else:
						p.add_pine(near, rng, base)
			t += rng.randf_range(5.0, 9.0)
	# The tall line of spruce along the south-west side, a few metres back from
	# the rail, and round the corners.
	var x := -hl - 18.0
	while x < hl + 22.0:
		var q := Vector2(x, hw + rng.randf_range(13.0, 17.0))
		p.add_pine(near, rng, Vector3(q.x, p.height_m(q.x, q.y), q.y))
		x += rng.randf_range(3.2, 4.6)
	# Young plantations north-east of the car park, in blocks.
	for block in [Rect2(-10, -150, 45, 30), Rect2(45, -130, 35, 45), Rect2(20, -95, 30, 18)]:
		var bz: float = block.position.y
		while bz < block.end.y:
			var bx: float = block.position.x
			while bx < block.end.x:
				p.add_bush(far, rng, Vector3(bx, p.height_m(bx, bz), bz))
				bx += 4.5
			bz += 4.5
	# Scattered birches in the meadows east of the ground.
	for i in 40:
		var q := Vector2(rng.randf_range(hl + 15.0, hl + 90.0), rng.randf_range(-hw - 120.0, -hw))
		if p.dist_to_path(q, river) > 20.0:
			p.add_birch(near, rng, Vector3(q.x, p.height_m(q.x, q.y), q.y))
	# Pine woods on the lower hill slopes.
	var spacing: float = [16.0, 11.0, 8.0][p.scenery_detail]
	var gz := -900.0
	while gz < 900.0:
		var gx := -900.0
		while gx < 900.0:
			var px := gx + rng.randf_range(-spacing, spacing) * 0.45
			var pz := gz + rng.randf_range(-spacing, spacing) * 0.45
			var h: float = p.height_m(px, pz)
			var patch: float = p.noise.get_noise_2d(px * 0.4, pz * 0.4)
			if h > 8.0 and patch > 0.05 and Vector2(px, pz).distance_to(town) > 120.0:
				p.add_woodland(far, rng, Vector3(px, h - 0.4, pz), 1.0)
			gx += spacing
		gz += spacing
	p.emit_trees(root, near, 12, 7, 64, "TreesNear")
	p.emit_trees(root, far, 8, 5, 22, "Woodland")


## Tussocks in the unmown meadow round the ground, greener by the river.
func _build_long_grass(root: Node3D, rng: RandomNumberGenerator) -> void:
	var meadow := func(x: float, z: float) -> float:
		var c := ground_mask(x, z, p.height_m(x, z))
		return c.g * (1.0 - c.b) * (1.0 - c.a)
	var bank := func(x: float, z: float) -> float:
		return meadow.call(x, z) * (1.0 - smoothstep(10.0, 30.0, p.dist_to_path(Vector2(x, z), river)))
	p.emit_tufts(root, rng, 11000, Rect2(-hl - 80.0, -hw - 70.0, hl * 2.0 + 170.0, hw * 2.0 + 130.0),
			meadow, Color(0.55, 0.5, 0.32))
	p.emit_tufts(root, rng, 3000, Rect2(-hl - 80.0, hw + 15.0, hl * 2.0 + 170.0, 50.0),
			bank, Color(0.38, 0.45, 0.22))


func _build_ground_furniture(root: Node3D) -> void:
	var holder := Node3D.new()
	holder.name = "Ground"
	root.add_child(holder)
	var steel: Material = p.mat("green_steel", Color(0.2, 0.3, 0.24), 0.6)
	var roof_mat: Material = p.mat("stand_roof", Color(0.5, 0.52, 0.53), 0.5)
	var white: Material = p.mat("white_panel", Color(0.9, 0.9, 0.88), 0.6)
	var dark: Material = p.mat("stand_inside", Color(0.12, 0.13, 0.13), 0.9)
	var seat: Material = p.mat("stand_seat", Color(0.55, 0.12, 0.14), 0.6)

	# Rail round the pitch, 3.5 m outside the lines.
	var m := 3.5
	var corners := [Vector2(-hl - m, -hw - m), Vector2(hl + m, -hw - m), Vector2(hl + m, hw + m), Vector2(-hl - m, hw + m)]
	var rail_mat: Material = p.mat("pitch_rail", Color(0.85, 0.85, 0.83), 0.5)
	for i in 4:
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % 4]
		p.add_fence(root, a, b, 1.1, 2.5, Color(0.85, 0.85, 0.83), false)
		var mid := (a + b) * 0.5
		var r: MeshInstance3D = p.add_box(holder, Vector3(a.distance_to(b), 0.06, 0.06), Vector3(mid.x, 1.08, mid.y), rail_mat)
		r.rotation.y = -atan2(b.y - a.y, b.x - a.x)

	# Ball-stop nets behind both hails: green netting on tall posts over a row
	# of solid green panels.
	var net_green := Color(0.14, 0.42, 0.26)
	var panel: Material = p.mat("net_panel", Color(0.3, 0.62, 0.38), 0.7)
	for end in [-1.0, 1.0]:
		var nx: float = end * (hl + 7.0)
		p.add_fence(root, Vector2(nx, -21.0), Vector2(nx, 21.0), 7.0, 4.2, net_green, true, 0.22)
		p.add_box(holder, Vector3(0.12, 1.3, 42.0), Vector3(nx, 0.65, 0), panel)
	# The club's small timber clubhouse by the north-west corner, with a deck.
	var hut := Node3D.new()
	hut.name = "Clubhouse"
	hut.position = Vector3(-hl - 16.0, 0, hw * 0.35)
	holder.add_child(hut)
	var timber: Material = p.mat("timber", Color(0.55, 0.42, 0.3), 0.9)
	var hut_roof: Material = p.mat("hut_roof_green", Color(0.18, 0.3, 0.22), 0.7)
	p.add_box(hut, Vector3(7.0, 3.0, 9.0), Vector3(0, 1.5, 0), timber)
	var hr: MeshInstance3D = p.add_roof(hut, Vector3(8.0, 1.8, 9.8), Vector3(0, 3.9, 0), hut_roof)
	hr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	p.add_box(hut, Vector3(2.5, 0.25, 9.0), Vector3(4.7, 0.55, 0), timber)
	p.add_box(hut, Vector3(0.1, 1.4, 1.0), Vector3(3.53, 1.7, -2.2), p.mat("window", Color(0.12, 0.14, 0.17), 0.2))
	p.add_box(hut, Vector3(0.1, 2.0, 1.0), Vector3(3.53, 1.0, 1.5), p.mat("door_dark", Color(0.18, 0.2, 0.22), 0.7))
	# Small covered stands on the car park side, past the dugouts.
	for sx in [30.0, 40.0]:
		var st := Node3D.new()
		st.position = Vector3(sx, 0, -hw - 6.5)
		holder.add_child(st)
		p.add_box(st, Vector3(7.0, 2.6, 0.15), Vector3(0, 1.3, -1.4), steel)
		for s in [-1.0, 1.0]:
			p.add_box(st, Vector3(0.15, 2.6, 2.8), Vector3(s * 3.5, 1.3, 0), steel)
		p.add_box(st, Vector3(7.4, 0.12, 3.2), Vector3(0, 2.66, -0.1), roof_mat)
		for tier in 2:
			p.add_box(st, Vector3(6.6, 0.4 + tier * 0.4, 0.9), Vector3(0, (0.4 + tier * 0.4) * 0.5, 0.6 - tier * 0.9), p.mat("stand_step", Color(0.6, 0.6, 0.58), 0.9))
			p.add_box(st, Vector3(6.4, 0.1, 0.4), Vector3(0, 0.45 + tier * 0.4, 0.5 - tier * 0.9), seat)
	# Match-day marquees on the gravel, and hospitality trailers in front of
	# the spruce on the other side.
	var canvas: Material = p.mat("marquee", Color(0.95, 0.95, 0.94), 0.8)
	for mq in [[Vector3(-hl * 0.35, 0, -hw - 46.0), Vector3(34.0, 3.0, 9.0)], [Vector3(-hl - 6.0, 0, -hw - 24.0), Vector3(14.0, 3.0, 10.0)]]:
		var c: Vector3 = mq[0]
		var sz: Vector3 = mq[1]
		p.add_box(holder, sz, c + Vector3(0, sz.y * 0.5, 0), canvas)
		var mr: MeshInstance3D = p.add_roof(holder, Vector3(sz.z + 0.2, 1.6, sz.x + 0.2), c + Vector3(0, sz.y + 0.8, 0), canvas)
		mr.rotation.y = PI * 0.5
	var trailer: Material = p.mat("trailer_white", Color(0.92, 0.93, 0.94), 0.5)
	for tx in [hl * 0.38, hl * 0.62]:
		p.add_box(holder, Vector3(13.0, 3.6, 2.6), Vector3(tx, 2.2, hw + 8.5), trailer)
		p.add_box(holder, Vector3(13.0, 0.4, 2.6), Vector3(tx, 0.2, hw + 8.5), p.mat("tyre", Color(0.08, 0.08, 0.08), 0.8))
	p.add_box(holder, Vector3(16.0, 3.8, 2.6), Vector3(-hl - 2.0, 2.3, hw + 11.0), trailer)

	# Dugouts either side of halfway on the north-east side, and a portakabin.
	for sx in [-9.0, 9.0]:
		var dug := Node3D.new()
		dug.position = Vector3(sx, 0, -hw - 5.0)
		holder.add_child(dug)
		p.add_box(dug, Vector3(5.0, 2.1, 0.15), Vector3(0, 1.05, -0.9), white)
		p.add_box(dug, Vector3(5.2, 0.12, 2.0), Vector3(0, 2.15, 0), white)
		for s in [-1.0, 1.0]:
			p.add_box(dug, Vector3(0.12, 2.1, 1.9), Vector3(s * 2.5, 1.05, 0), white)
		p.add_box(dug, Vector3(4.6, 0.45, 0.5), Vector3(0, 0.23, -0.5), seat)
	p.add_box(holder, Vector3(7.0, 2.6, 2.6), Vector3(20.0, 1.3, -hw - 8.0), p.mat("portakabin", Color(0.72, 0.78, 0.72), 0.7))
	p.add_box(holder, Vector3(6.0, 2.6, 2.4), Vector3(-19.0, 1.3, -hw - 8.5), p.mat("container", Color(0.2, 0.36, 0.28), 0.7))
	# Timekeeper's box on the south-west side.
	p.add_box(holder, Vector3(2.4, 2.2, 1.8), Vector3(-1.0, 1.1, hw + 5.5), white)
	p.add_box(holder, Vector3(2.8, 0.12, 2.2), Vector3(-1.0, 2.26, hw + 5.5), roof_mat)



func _build_town(root: Node3D, rng: RandomNumberGenerator) -> void:
	var holder := Node3D.new()
	holder.name = "Town"
	root.add_child(holder)
	var rows: int = [3, 5, 6][p.scenery_detail]
	for row in rows:
		for i in 7:
			var q := town + Vector2(i * 14.0 - 42.0 + (row % 2) * 6.0, row * -24.0 + 50.0)
			if rng.randf() < 0.85:
				p.add_house(holder, rng, Vector3(q.x, p.height_m(q.x, q.y), q.y), 0.75 + rng.randf_range(-0.1, 0.1))
	# A farmhouse and steading across the river.
	for q in [Vector2(-260, 260), Vector2(-240, 275)]:
		p.add_house(holder, rng, Vector3(q.x, p.height_m(q.x, q.y), q.y), 0.3)


func _build_cars(root: Node3D, rng: RandomNumberGenerator) -> void:
	var holder := Node3D.new()
	holder.name = "Cars"
	root.add_child(holder)
	# Match-day parking on the gravel, noses to the rail.
	p.park_row(holder, rng, Vector3(-hl + 8.0, 0, -hw - 13.0), Vector3(-26.0, 0, -hw - 13.0), -PI * 0.5, 0.6)
	p.park_row(holder, rng, Vector3(28.0, 0, -hw - 13.0), Vector3(hl - 4.0, 0, -hw - 13.0), -PI * 0.5, 0.6)
	p.park_row(holder, rng, Vector3(-hl + 12.0, 0, -hw - 26.0), Vector3(hl - 10.0, 0, -hw - 26.0), PI * 0.5, 0.35)
	p.add_van(holder, Vector3(-hl - 20.0, 0, -hw - 30.0), 0.4)
	# More on the grass in front of the spruce at the north-west end.
	p.park_row(holder, rng, Vector3(-hl + 6.0, 0, hw + 9.0), Vector3(-hl * 0.45, 0, hw + 9.0), PI * 0.5, 0.7)
