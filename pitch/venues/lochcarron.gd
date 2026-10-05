extends RefCounted
## Lochcarron's pitch, laid out from aerial views and street photos.
##
## The pitch runs from the A896 down towards the shore of Loch Carron. West
## end (-X): a chain-link fence with tall ball-stop poles behind the hail, the
## main road along the end, and houses and woods on the hillside above. Far
## side (-Z): the single-storey white cottages of Murray Square, and towards
## the shore the club's small white clubhouse with a red roof and a green shed.
## Near side (+Z): a post-and-wire fence and gate, Park Road and its houses,
## the gym near the shore end, and the Allt nan Carnan burn behind running
## down to the loch. East end (+X): a gravel oval and the playground, then the
## shore, the sea loch and the hills across the water.

const WATER_LEVEL := -4.0

var p: ShintyPitch
var hl: float
var hw: float
var burn: PackedVector2Array
var roads: Array[PackedVector2Array] = []
var oval: Vector2
var club: Vector2


func _init(pitch: ShintyPitch) -> void:
	p = pitch
	hl = p.hl
	hw = p.hw
	oval = Vector2(hl + 32.0, hw * 0.25)
	club = Vector2(hl * 0.72, -hw - 11.0)
	burn = PackedVector2Array([Vector2(-hl - 300.0, hw + 120.0), Vector2(-hl - 40.0, hw + 52.0), Vector2(hl * 0.3, hw + 46.0),
		Vector2(hl + 30.0, hw + 38.0), Vector2(hl + 90.0, hw + 50.0), Vector2(hl + 160.0, hw + 40.0)])
	# The A896 along the west end, Park Road down the near side, the lane into
	# Murray Square, and Church Street off the main road.
	roads.append(PackedVector2Array([Vector2(-hl + 120.0, -hw - 600.0), Vector2(-hl - 6.0, -hw - 120.0), Vector2(-hl - 15.0, 0.0),
		Vector2(-hl - 40.0, hw + 140.0), Vector2(-hl - 40.0, hw + 700.0)]))
	roads.append(PackedVector2Array([Vector2(-hl - 15.0, hw + 7.5), Vector2(hl + 6.0, hw + 7.5), Vector2(hl + 14.0, hw + 3.0)]))
	roads.append(PackedVector2Array([Vector2(-hl - 12.0, -hw - 22.0), Vector2(hl * 0.6, -hw - 22.0), Vector2(hl + 10.0, -hw - 14.0)]))
	roads.append(PackedVector2Array([Vector2(-hl - 30.0, hw + 80.0), Vector2(-20.0, hw + 120.0), Vector2(hl * 0.6, hw + 200.0)]))


func extra_cloud() -> float:
	return 0.3


func fog_density() -> float:
	return 0.00011


func water() -> Dictionary:
	return {"level": WATER_LEVEL, "color": Color(0.08, 0.14, 0.18), "roughness": 0.05, "wave_scale": 0.6}


func ground_look() -> Dictionary:
	return {
		"wear": 0.18,
		"stripe_width": 6.0,
		"stripe_strength": 0.06,
		"grass_color": Color(0.3, 0.47, 0.15),
		"rough_color": Color(0.3, 0.4, 0.18),      # rough grass and bracken
		"earth_color": Color(0.33, 0.29, 0.22),    # heather and bracken on the hills
		"gravel_color": Color(0.45, 0.43, 0.4),
		"sand_color": Color(0.3, 0.3, 0.31),       # tarmac
		"field_strength": 0.0,
	}


## A few boards along the far side; the road end has the fence.
func board_rows() -> Array:
	return [[Vector2(-hl * 0.6, -hw - 3.7), Vector2(hl * 0.4, -hw - 3.7), 0],
		[Vector2(hl + 4.6, -hw * 0.6), Vector2(hl + 4.6, hw * 0.6), 5]]


## Where the shore is, in metres along X, for a point `z` across.
func _shore_x(z: float) -> float:
	return hl + 85.0 + 30.0 * sin(z * 0.012) + 0.00015 * z * z


func height_m(x: float, z: float) -> float:
	var pos := Vector2(x, z)
	var n := p.noise.get_noise_2d(x, z)
	var ridge := 1.0 - absf(p.noise.get_noise_2d(x * 0.03, z * 0.03))
	# The hillside rising behind the village, north of the main road.
	var hill := 420.0 * smoothstep(hl + 40.0, hl + 1200.0, -x) * (0.7 + 0.3 * ridge)
	hill += 25.0 * smoothstep(hl + 10.0, hl + 120.0, -x)
	var rough := (n * 1.3 + p.noise.get_noise_2d(x * 0.2, z * 0.2) * 1.5) * p.wildness(x, z, 30.0, 40.0)
	var land := (hill + rough) * p.wildness(x, z, 8.0, 8.0)
	# Down to the shore, the loch, and the hills across the water.
	var sx := _shore_x(z)
	land = lerpf(land, WATER_LEVEL - 3.0, smoothstep(sx - 25.0, sx + 10.0, x))
	var across := 650.0 * smoothstep(2200.0, 3600.0, x) * (0.65 + 0.35 * ridge)
	land = maxf(land, WATER_LEVEL - 3.0 + across)
	# The burn.
	var db: float = p.dist_to_path(pos, burn)
	land = lerpf(land, minf(land, WATER_LEVEL - 0.6), 1.0 - smoothstep(1.5, 4.5, db))
	return land


func ground_mask(x: float, z: float, h: float) -> Color:
	var c := Color(0, 0, 0, 0)
	var pos := Vector2(x, z)
	c.g = p.wildness(x, z, 4.0, 5.0) * 0.5 + smoothstep(10.0, 40.0, h) * 0.5
	c.r = smoothstep(120.0, 300.0, h) * (0.6 + 0.4 * p.noise.get_noise_2d(x * 0.05, z * 0.05))
	# The gravel oval and the car parks.
	var e := Vector2((x - oval.x) / 26.0, (z - oval.y) / 20.0).length()
	if absf(e - 1.0) < 0.12:
		c.b = 1.0
	if (x > hl * 0.62 and x < hl + 6.0 and z > hw + 11.0 and z < hw + 26.0):
		c.b = 1.0
	for road in roads:
		if p.dist_to_path(pos, road) < 3.0:
			c.a = 1.0
	# Shingle and weed along the shore.
	var sx := _shore_x(z)
	if x > sx - 22.0 and h < WATER_LEVEL + 3.5:
		c.b = maxf(c.b, 0.7)
	if c.b > 0.0 or c.a > 0.0:
		c.r = 0.0
		c.g = 0.0
	return c


func build(root: Node3D, rng: RandomNumberGenerator) -> void:
	_build_trees(root, rng)
	_build_houses(root, rng)
	_build_club(root)
	_build_fences(root)
	_build_extras(root, rng)
	var rough := func(x: float, z: float) -> float:
		var c := ground_mask(x, z, p.height_m(x, z))
		return (1.0 - c.b) * (1.0 - c.a) * p.wildness(x, z, 3.0, 4.0)
	p.emit_tufts(root, rng, 2000, Rect2(-hl - 10.0, hw + 1.5, hl * 2.0 + 20.0, 5.0), rough, Color(0.45, 0.46, 0.25))
	p.emit_tufts(root, rng, 1500, Rect2(hl + 4.0, -hw - 10.0, 60.0, hw * 2.0 + 20.0), rough, Color(0.42, 0.45, 0.23))


func _build_trees(root: Node3D, rng: RandomNumberGenerator) -> void:
	var near := ShintyPitch.TreeBatch.new()
	var far := ShintyPitch.TreeBatch.new()
	var detail: float = [0.5, 0.8, 1.0][p.scenery_detail]
	# Along the burn.
	for i in burn.size() - 1:
		var a: Vector2 = burn[i]
		var b: Vector2 = burn[i + 1]
		var steps := int(a.distance_to(b) / (10.0 / detail))
		for s in steps:
			var q: Vector2 = a.lerp(b, (s + rng.randf()) / float(steps)) + Vector2(rng.randf_range(-4.0, 4.0), rng.randf_range(-4.0, 4.0))
			if rng.randf() < 0.3:
				p.add_birch(near, rng, Vector3(q.x, p.height_m(q.x, q.y), q.y))
			else:
				p.add_broadleaf(near, rng, Vector3(q.x, p.height_m(q.x, q.y), q.y), rng.randf_range(0.6, 0.95))
	# A big spruce by the road end, trees in the gardens and round the playground.
	p.add_pine(near, rng, Vector3(-hl - 6.0, 0.0, -hw - 6.0))
	p.add_pine(near, rng, Vector3(-hl - 9.0, 0.0, -hw - 1.0))
	for i in int(30 * detail):
		var q := Vector2(rng.randf_range(-hl, hl), -hw - rng.randf_range(32.0, 60.0))
		if i % 3 == 0:
			q = Vector2(rng.randf_range(-hl, hl * 0.6), hw + rng.randf_range(24.0, 40.0))
		elif i % 3 == 1 and i < 18:
			q = Vector2(hl + rng.randf_range(10.0, 60.0), rng.randf_range(-hw - 20.0, -hw + 20.0))
		p.add_broadleaf(near, rng, Vector3(q.x, p.height_m(q.x, q.y), q.y), rng.randf_range(0.55, 0.9))
	# Woods on the hillside above the main road.
	var spacing: float = [16.0, 12.0, 9.5][p.scenery_detail]
	var gx := -hl - 40.0
	while gx > -hl - 520.0:
		var gz := -520.0
		while gz < 520.0:
			var px := gx + rng.randf_range(-0.5, 0.5) * spacing
			var pz := gz + rng.randf_range(-0.5, 0.5) * spacing
			var h: float = p.height_m(px, pz)
			var c := ground_mask(px, pz, h)
			var keep := 1.0 / (1.0 + absf(gx + hl) / 250.0)
			if rng.randf() < keep and c.a == 0.0 and c.r < 0.4 and p.noise.get_noise_2d(px * 0.3, pz * 0.3) > -0.1 and not _houses_at(Vector2(px, pz)):
				if Vector2(px, pz).length() < 230.0:
					p.add_broadleaf(near, rng, Vector3(px, h, pz), rng.randf_range(0.7, 1.0))
				else:
					p.add_woodland(far, rng, Vector3(px, h - 0.4, pz), 0.5)
			gz += spacing
		gx -= spacing
	p.emit_trees(root, near, 12, 7, 64, "TreesNear")
	p.emit_trees(root, far, 8, 5, 22, "Woodland")


func _houses_at(q: Vector2) -> bool:
	return absf(q.x + hl + 35.0) < 20.0 and absf(q.y) < 200.0


## Murray Square's white cottages behind the far side, Park Road's houses on
## the near side, and the village along the main road.
func _build_houses(root: Node3D, rng: RandomNumberGenerator) -> void:
	var holder := Node3D.new()
	holder.name = "Houses"
	root.add_child(holder)
	var white: Material = p.mat("harl", Color(0.9, 0.89, 0.85), 0.95)
	var slate: Material = p.mat("slate", Color(0.2, 0.21, 0.23), 0.8)
	var glass: Material = p.mat("window", Color(0.12, 0.14, 0.17), 0.2)
	# Murray Square: long single-storey cottages, gable ends to the pitch,
	# then a second row along the lane.
	for row in 2:
		var n := 6 if row == 0 else 5
		for i in n:
			var q := Vector2(-hl + 12.0 + i * (hl * 1.7 / n) + rng.randf_range(-2.0, 2.0), -hw - 14.0 - row * 22.0)
			var b := Node3D.new()
			b.position = Vector3(q.x, p.height_m(q.x, q.y), q.y)
			b.rotation.y = rng.randf_range(-0.03, 0.03)
			holder.add_child(b)
			var L := rng.randf_range(14.0, 18.0)
			p.add_box(b, Vector3(L, 3.4, 7.5), Vector3(0, 1.7 - 0.3, 0), white)
			var roof := p.add_roof(b, Vector3(8.2, 2.4, L + 0.4), Vector3(0, 4.25 - 0.3, 0), slate)
			roof.rotation.y = PI * 0.5
			p.add_box(b, Vector3(0.7, 1.2, 0.7), Vector3(L * 0.3, 4.6, 0), white)
			for k in 4:
				p.add_box(b, Vector3(1.2, 1.2, 0.1), Vector3(-L * 0.35 + k * L * 0.23, 1.6, 3.78), glass)
	# Park Road: a mix of houses, with a red sandstone villa by the main road.
	for i in 7:
		var q := Vector2(-hl + 8.0 + i * 17.0 + rng.randf_range(-2.0, 2.0), hw + 18.0 + rng.randf_range(-1.0, 2.0))
		p.add_house(holder, rng, Vector3(q.x, p.height_m(q.x, q.y), q.y), PI * 0.5 + rng.randf_range(-0.05, 0.05))
	var villa := Node3D.new()
	villa.position = Vector3(-hl - 26.0, p.height_m(-hl - 26.0, -hw - 4.0), -hw - 4.0)
	holder.add_child(villa)
	var sand: Material = p.mat("sandstone", Color(0.5, 0.36, 0.31), 0.9)
	p.add_box(villa, Vector3(9.0, 7.0, 11.0), Vector3(0, 3.0, 0), sand)
	p.add_roof(villa, Vector3(9.6, 3.2, 11.4), Vector3(0, 8.1, 0), slate)
	# The village along the main road and on the slope above.
	var rows: int = [2, 3, 4][p.scenery_detail]
	for row in rows:
		for i in 10:
			if rng.randf() > 0.7:
				continue
			var q := Vector2(-hl - 35.0 + rng.randf_range(-12.0, 12.0) - row * 30.0, -200.0 + i * 42.0 + rng.randf_range(-6.0, 6.0))
			if absf(q.y) < hw + 10.0 and row == 0:
				continue
			p.add_house(holder, rng, Vector3(q.x, p.height_m(q.x, q.y), q.y), rng.randf_range(-0.2, 0.2))
	for q in [Vector2(-hl * 0.4, hw + 95.0), Vector2(0.0, hw + 110.0), Vector2(hl * 0.4, hw + 140.0), Vector2(hl * 0.2, -hw - 85.0),
			Vector2(-hl * 0.5, -hw - 80.0), Vector2(hl + 30.0, -hw - 60.0)]:
		p.add_house(holder, rng, Vector3(q.x, p.height_m(q.x, q.y), q.y), rng.randf_range(-0.3, 0.3))


## The clubhouse: small and white with a red roof, a green shed beside it,
## and the gym on the near side by the shore end.
func _build_club(root: Node3D) -> void:
	var holder := Node3D.new()
	holder.name = "Clubhouse"
	holder.position = Vector3(club.x, p.height_m(club.x, club.y), club.y)
	root.add_child(holder)
	var white: Material = p.mat("harl", Color(0.9, 0.89, 0.85), 0.95)
	var red: Material = p.mat("roof_red", Color(0.62, 0.25, 0.18), 0.85)
	var glass: Material = p.mat("window", Color(0.12, 0.14, 0.17), 0.2)
	p.add_box(holder, Vector3(14.0, 3.0, 7.0), Vector3(0, 1.5, 0), white)
	var roof := p.add_roof(holder, Vector3(7.8, 1.9, 14.6), Vector3(0, 3.95, 0), red)
	roof.rotation.y = PI * 0.5
	p.add_box(holder, Vector3(14.05, 0.3, 7.05), Vector3(0, 2.35, 0), p.mat("club_blue_band", Color(0.3, 0.55, 0.75), 0.6))
	for i in 3:
		p.add_box(holder, Vector3(1.6, 1.1, 0.1), Vector3(-4.5 + i * 3.0, 1.6, 3.55), glass)
	p.add_box(holder, Vector3(1.0, 2.0, 0.1), Vector3(5.0, 1.0, 3.55), p.mat("door_dark", Color(0.18, 0.2, 0.22), 0.7))
	# A bench in front, and the green shed beside.
	var timber: Material = p.mat("timber", Color(0.42, 0.3, 0.2), 0.9)
	p.add_box(holder, Vector3(2.0, 0.08, 0.5), Vector3(-2.0, 0.5, 4.2), timber)
	var shed := Node3D.new()
	shed.position = Vector3(10.5, 0, 0.5)
	holder.add_child(shed)
	var green: Material = p.mat("shed_green", Color(0.3, 0.42, 0.3), 0.8)
	p.add_box(shed, Vector3(5.5, 2.6, 6.0), Vector3(0, 1.3, 0), green)
	var sr := p.add_roof(shed, Vector3(6.2, 1.1, 6.2), Vector3(0, 3.15, 0), green)
	sr.rotation.y = PI * 0.5
	p.add_box(shed, Vector3(2.6, 2.1, 0.1), Vector3(0, 1.05, 3.02), p.mat("door_brown", Color(0.35, 0.25, 0.18), 0.8))
	# The gym: a low building with blue cladding by the near side.
	var gym := Vector3(hl * 0.82, 0.0, hw + 18.0)
	p.add_box(root, Vector3(16.0, 4.0, 9.0), gym + Vector3(0, 2.0, 0), white)
	p.add_box(root, Vector3(16.3, 0.5, 9.3), gym + Vector3(0, 4.2, 0), p.mat("clad_blue", Color(0.32, 0.45, 0.6), 0.6))


## Chain-link fence with tall ball-stop poles along the road end, a post and
## wire fence down the near side, and street lights on Park Road.
func _build_fences(root: Node3D) -> void:
	var grey := Color(0.4, 0.43, 0.42)
	var x0 := -hl - 7.0
	p.add_fence(root, Vector2(x0, -hw - 4.0), Vector2(x0, hw + 3.0), 2.6, 3.2, grey, true, 0.18)
	p.add_fence(root, Vector2(x0, -hw - 4.0), Vector2(-hl + 30.0, -hw - 4.0), 2.0, 3.2, grey, true, 0.15)
	# The tall poles behind the hail, and a fine net between them.
	p.add_fence(root, Vector2(x0 - 0.3, -12.0), Vector2(x0 - 0.3, 12.0), 9.0, 6.0, grey, true, 0.08)
	p.add_fence(root, Vector2(-hl - 10.0, hw + 3.0), Vector2(hl + 8.0, hw + 3.0), 1.1, 3.0, Color(0.36, 0.3, 0.22), false)
	var holder := Node3D.new()
	holder.name = "Lamps"
	root.add_child(holder)
	var lamp: Material = p.mat("lamp_post", Color(0.55, 0.57, 0.58), 0.5)
	for i in 5:
		var x := -hl + 10.0 + i * 30.0
		var pole := p.add_cyl(holder, Vector3(x, 3.5, hw + 10.5), 0.07, 7.0, lamp)
		pole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		p.add_box(holder, Vector3(0.8, 0.1, 0.25), Vector3(x, 7.0, hw + 10.2), lamp)
	# Signs on the road fence.
	var blue: Material = p.mat("sign_blue", Color(0.15, 0.4, 0.7), 0.5)
	p.add_box(holder, Vector3(0.08, 0.7, 2.2), Vector3(x0 - 0.2, 1.8, hw - 6.0), blue)
	p.add_box(holder, Vector3(0.08, 0.4, 2.2), Vector3(x0 - 0.2, 1.1, hw - 6.0), blue)


## The playground by the shore, and boats pulled up on the shingle.
func _build_extras(root: Node3D, rng: RandomNumberGenerator) -> void:
	var holder := Node3D.new()
	holder.name = "Extras"
	root.add_child(holder)
	var steel: Material = p.mat("play_red", Color(0.7, 0.15, 0.12), 0.5)
	var base := Vector3(hl + 40.0, 0.0, -hw - 8.0)
	base.y = p.height_m(base.x, base.z)
	for s in [-1.0, 1.0]:
		var leg := p.add_box(holder, Vector3(0.1, 2.6, 0.1), base + Vector3(s * 2.0, 1.2, 0), steel)
		leg.rotation.z = s * 0.15
	p.add_box(holder, Vector3(4.4, 0.1, 0.1), base + Vector3(0, 2.45, 0), steel)
	p.add_box(holder, Vector3(2.5, 1.6, 2.5), base + Vector3(6.0, 0.8, 1.5), p.mat("play_wood", Color(0.5, 0.36, 0.22), 0.8))
	p.add_box(holder, Vector3(0.4, 1.8, 3.2), base + Vector3(-5.0, 0.9, 2.0), p.mat("play_blue", Color(0.2, 0.4, 0.75), 0.5))
	var hull: Material = p.mat("boat_white", Color(0.88, 0.88, 0.86), 0.6)
	for i in 4:
		var z := -hw - 30.0 + i * 9.0 + rng.randf_range(-2.0, 2.0)
		var x := _shore_x(z) - 16.0 + rng.randf_range(-3.0, 3.0)
		var boat := p.add_box(holder, Vector3(4.2, 0.8, 1.6), Vector3(x, p.height_m(x, z) + 0.4, z), hull)
		boat.rotation.y = rng.randf_range(-0.6, 0.6)
