extends RefCounted
## Col Glen's pitch at Glendaruel, by Kilmodan Primary School, laid out from
## an aerial view and photos of the ground.
##
## An open rural pitch on the floor of the glen. Far side (-Z): a line of
## alders, birch and oak along the River Ruel, fields across the water, and a
## big steep hillside, part forestry plantation and part open grass and
## bracken. Near side (+Z): the school and its car park towards the east end,
## a few houses along the road behind, and the other side of the glen rising
## further off. Yellow posts and rope run along both touchlines. East end: a
## walled garden with a polytunnel and the play park. West end: hedges and a
## burn running down to the river, and farmland down the glen.

const WATER_LEVEL := -2.4

var p: ShintyPitch
var hl: float
var hw: float
var river: PackedVector2Array
var burn: PackedVector2Array
var road: PackedVector2Array
var school: Vector2


func _init(pitch: ShintyPitch) -> void:
	p = pitch
	hl = p.hl
	hw = p.hw
	school = Vector2(hl * 0.62, hw + 27.0)
	# The Ruel runs down the glen past the far side.
	river = PackedVector2Array([Vector2(hl + 600.0, -hw - 70.0), Vector2(hl + 160.0, -hw - 40.0), Vector2(hl + 40.0, -hw - 19.0),
		Vector2(-hl, -hw - 17.0), Vector2(-hl - 70.0, -hw - 8.0), Vector2(-hl - 220.0, -hw - 40.0), Vector2(-hl - 700.0, -hw - 10.0)])
	burn = PackedVector2Array([Vector2(-hl - 30.0, hw + 120.0), Vector2(-hl - 14.0, hw + 30.0), Vector2(-hl - 22.0, -hw - 8.0), Vector2(-hl - 70.0, -hw - 8.0)])
	road = PackedVector2Array([Vector2(-hl - 600.0, hw + 170.0), Vector2(-hl - 60.0, hw + 95.0), Vector2(hl * 0.3, hw + 70.0),
		Vector2(hl + 30.0, hw + 50.0), Vector2(hl + 120.0, hw + 10.0), Vector2(hl + 600.0, -hw + 40.0)])


func extra_cloud() -> float:
	return 0.35


func fog_density() -> float:
	return 0.00018


func water() -> Dictionary:
	return {"level": WATER_LEVEL, "color": Color(0.07, 0.09, 0.08), "roughness": 0.08, "wave_scale": 0.9}


func ground_look() -> Dictionary:
	return {
		"wear": 0.3,
		"stripe_width": 6.0,
		"stripe_strength": 0.05,
		"grass_color": Color(0.29, 0.46, 0.15),
		"rough_color": Color(0.28, 0.4, 0.16),     # grass and bracken on the open hill
		"earth_color": Color(0.07, 0.12, 0.06),    # forestry plantation from afar
		"gravel_color": Color(0.33, 0.33, 0.34),   # tarmac
		"sand_color": Color(0.38, 0.33, 0.24),     # the river's stony banks
		"field_strength": 0.0,
	}


## A country pitch: no ad boards.
func board_rows() -> Array:
	return []


func height_m(x: float, z: float) -> float:
	var pos := Vector2(x, z)
	var n := p.noise.get_noise_2d(x, z)
	var ridge := 1.0 - absf(p.noise.get_noise_2d(x * 0.03, z * 0.03))
	# The glen floor rises gently up the glen (+X); the hills rise steeply,
	# close behind the river and further off on the near side.
	var floor_h := 6.0 * smoothstep(100.0, 1500.0, x)
	var far_hill := 400.0 * smoothstep(hw + 90.0, hw + 620.0, -z) * (0.75 + 0.25 * ridge)
	var near_hill := 360.0 * smoothstep(hw + 230.0, hw + 1100.0, z) * (0.7 + 0.3 * ridge)
	var land := floor_h + far_hill + near_hill + (n * 1.2 + p.noise.get_noise_2d(x * 0.2, z * 0.2) * 1.5) * smoothstep(0.0, 30.0, far_hill + near_hill + 10.0 * n)
	land *= p.wildness(x, z, 6.0, 6.0)
	# The river and the burn, cut into the glen floor.
	var dr: float = p.dist_to_path(pos, river)
	land = lerpf(land, WATER_LEVEL - 1.6, 1.0 - smoothstep(4.0, 9.0, dr))
	var db: float = p.dist_to_path(pos, burn)
	land = lerpf(land, WATER_LEVEL - 0.6, (1.0 - smoothstep(1.2, 3.5, db)) * smoothstep(4.0, 10.0, _outside(pos)))
	return land


## How far `pos` is outside the pitch's lines.
func _outside(pos: Vector2) -> float:
	return maxf(absf(pos.x) - hl, absf(pos.y) - hw)


func ground_mask(x: float, z: float, h: float) -> Color:
	var c := Color(0, 0, 0, 0)
	var pos := Vector2(x, z)
	# Open hill above the glen floor, with forestry blocks on it.
	var hill := smoothstep(4.0, 25.0, h - 6.0 * smoothstep(100.0, 1500.0, x))
	c.g = maxf(hill, p.wildness(x, z, 3.0, 3.0) * 0.25)
	var forest := smoothstep(-0.05, 0.1, p.noise.get_noise_2d(x * 0.18 + 400.0, z * 0.3))
	c.r = forest * smoothstep(12.0, 30.0, h) * (1.0 - smoothstep(300.0, 360.0, h))
	# Stony banks by the river.
	if p.dist_to_path(pos, river) < 7.0:
		c.a = 0.8
	if p.dist_to_path(pos, road) < 3.0 or (absf(x - school.x - 22.0) < 10.0 and z > hw + 16.0 and z < hw + 36.0):
		c.b = 1.0
	if c.b > 0.0 or c.a > 0.0:
		c.r = 0.0
	return c


func build(root: Node3D, rng: RandomNumberGenerator) -> void:
	_build_trees(root, rng)
	_build_school(root, rng)
	_build_ropes(root)
	_build_extras(root, rng)
	var rough := func(x: float, z: float) -> float:
		var c := ground_mask(x, z, p.height_m(x, z))
		return (1.0 - c.b) * (1.0 - c.a) * p.wildness(x, z, 4.0, 6.0)
	p.emit_tufts(root, rng, 3000, Rect2(-hl - 30.0, -hw - 14.0, hl * 2.0 + 60.0, 10.0), rough, Color(0.4, 0.46, 0.22))
	p.emit_tufts(root, rng, 1500, Rect2(-hl - 26.0, -hw, 18.0, hw * 2.0), rough, Color(0.4, 0.46, 0.22))


func _build_trees(root: Node3D, rng: RandomNumberGenerator) -> void:
	var near := ShintyPitch.TreeBatch.new()
	var far := ShintyPitch.TreeBatch.new()
	var detail: float = [0.5, 0.8, 1.0][p.scenery_detail]
	# Along both banks of the Ruel: a near-continuous line of alder, birch and
	# oak, thinning out down the glen.
	for i in river.size() - 1:
		var a: Vector2 = river[i]
		var b: Vector2 = river[i + 1]
		var steps := int(a.distance_to(b) / (7.0 / detail))
		for s in steps:
			var q := a.lerp(b, (s + rng.randf()) / float(steps))
			for side in [-1.0, 1.0]:
				if side > 0.0 and q.length() > 260.0 and rng.randf() < 0.6:
					continue
				var off: Vector2 = (b - a).normalized().orthogonal() * side * rng.randf_range(6.0, 10.0)
				var t: Vector2 = q + off
				var h: float = p.height_m(t.x, t.y)
				if t.length() < 300.0:
					if rng.randf() < 0.35:
						p.add_birch(near, rng, Vector3(t.x, h, t.y))
					else:
						p.add_broadleaf(near, rng, Vector3(t.x, h, t.y), rng.randf_range(0.7, 1.05))
				else:
					p.add_woodland(far, rng, Vector3(t.x, h - 0.3, t.y), 0.3)
	# Along the burn and the hedges past the west end.
	for i in burn.size() - 1:
		var a: Vector2 = burn[i]
		var b: Vector2 = burn[i + 1]
		var steps := int(a.distance_to(b) / (9.0 / detail))
		for s in steps:
			var q := a.lerp(b, (s + rng.randf()) / float(steps)) + Vector2(rng.randf_range(-3.0, 3.0), rng.randf_range(-3.0, 3.0))
			if absf(q.y) < 14.0:
				continue  # the view down the pitch from behind the hail
			p.add_broadleaf(near, rng, Vector3(q.x, p.height_m(q.x, q.y), q.y), rng.randf_range(0.6, 0.95))
	# Trees round the school, the houses and the garden at the east end.
	for i in int(24 * detail):
		var q := Vector2(rng.randf_range(hl * 0.1, hl + 60.0), rng.randf_range(hw + 40.0, hw + 75.0))
		if rng.randf() < 0.5:
			q = Vector2(hl + rng.randf_range(20.0, 70.0), rng.randf_range(-hw - 5.0, hw + 30.0))
		p.add_broadleaf(near, rng, Vector3(q.x, p.height_m(q.x, q.y), q.y), rng.randf_range(0.6, 1.0))
	# Forestry on the hills: rows of dark spruce where the ground says so, and
	# scattered birch and rowan on the open hill.
	var spacing: float = [16.0, 12.0, 9.5][p.scenery_detail]
	var gz := -hw - 120.0
	while gz > -hw - 520.0:
		var gx := -520.0
		while gx < 620.0:
			var px := gx + rng.randf_range(-0.4, 0.4) * spacing
			var pz := gz + rng.randf_range(-0.4, 0.4) * spacing
			var h: float = p.height_m(px, pz)
			var c := ground_mask(px, pz, h)
			if c.r > 0.5:
				p.add_woodland(far, rng, Vector3(px, h - 0.5, pz), 0.85)
				var q := Vector2(px + spacing * 0.5, pz + spacing * 0.5)
				p.add_woodland(far, rng, Vector3(q.x, p.height_m(q.x, q.y) - 0.5, q.y), 0.85)
			elif c.g > 0.5 and rng.randf() < 0.06:
				p.add_woodland(far, rng, Vector3(px, h - 0.4, pz), 0.2)
			gx += spacing * (1.0 + absf(gz + hw) / 400.0)
		gz -= spacing
	p.emit_trees(root, near, 12, 7, 64, "TreesNear")
	p.emit_trees(root, far, 8, 5, 22, "Woodland")


## Kilmodan Primary School: a long white single-storey building with a grey
## roof and a wing at one end, its car park beside it, and a few houses.
func _build_school(root: Node3D, rng: RandomNumberGenerator) -> void:
	var holder := Node3D.new()
	holder.name = "School"
	holder.position = Vector3(school.x, p.height_m(school.x, school.y), school.y)
	root.add_child(holder)
	var white: Material = p.mat("harl", Color(0.9, 0.89, 0.85), 0.95)
	var slate: Material = p.mat("slate", Color(0.2, 0.21, 0.23), 0.8)
	var glass: Material = p.mat("window", Color(0.12, 0.14, 0.17), 0.2)
	p.add_box(holder, Vector3(26.0, 3.4, 9.0), Vector3(0, 1.7, 0), white)
	var roof := p.add_roof(holder, Vector3(9.8, 2.6, 26.6), Vector3(0, 4.7, 0), slate)
	roof.rotation.y = PI * 0.5
	p.add_box(holder, Vector3(9.0, 3.4, 10.0), Vector3(-9.0, 1.7, 9.0), white)
	p.add_roof(holder, Vector3(9.8, 2.4, 10.6), Vector3(-9.0, 4.6, 9.2), slate)
	for i in 7:
		p.add_box(holder, Vector3(1.8, 1.4, 0.1), Vector3(-10.5 + i * 3.5, 1.9, -4.56), glass)
	var cars := Node3D.new()
	cars.name = "Cars"
	root.add_child(cars)
	p.park_row(cars, rng, Vector3(school.x + 17.0, 0, hw + 19.0), Vector3(school.x + 17.0, 0, hw + 34.0), 0.0, 0.5)
	p.park_row(cars, rng, Vector3(school.x + 27.0, 0, hw + 19.0), Vector3(school.x + 27.0, 0, hw + 34.0), PI, 0.4)
	# Houses along the road and by the garden.
	var houses := Node3D.new()
	houses.name = "Houses"
	root.add_child(houses)
	for q in [Vector2(-hl * 0.3, hw + 92.0), Vector2(hl * 0.05, hw + 86.0), Vector2(hl * 0.55, hw + 78.0), Vector2(hl + 22.0, hw + 62.0),
			Vector2(hl + 55.0, hw + 30.0), Vector2(hl + 80.0, -hw + 10.0), Vector2(-hl - 120.0, hw + 120.0), Vector2(hl + 260.0, hw - 30.0)]:
		p.add_house(houses, rng, Vector3(q.x, p.height_m(q.x, q.y), q.y), rng.randf_range(-0.3, 0.3))


## Yellow posts and rope a couple of metres outside both touchlines.
func _build_ropes(root: Node3D) -> void:
	var holder := Node3D.new()
	holder.name = "Ropes"
	root.add_child(holder)
	var yellow := Color(0.85, 0.9, 0.1)
	var rope: Material = p.mat("rope_yellow", Color(0.85, 0.85, 0.12), 0.7)
	for side in [-1.0, 1.0]:
		var z: float = side * (hw + 2.0)
		p.add_fence(root, Vector2(-hl, z), Vector2(hl, z), 1.1, 3.4, yellow, false)
		var r := p.add_box(holder, Vector3(hl * 2.0, 0.025, 0.025), Vector3(0, 1.0, z), rope)
		r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## The polytunnel and garden at the east end, the play park, a shed and a
## picnic bench by the near touchline.
func _build_extras(root: Node3D, rng: RandomNumberGenerator) -> void:
	var holder := Node3D.new()
	holder.name = "Extras"
	root.add_child(holder)
	var tunnel := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 2.6
	cm.bottom_radius = 2.6
	cm.height = 18.0
	cm.radial_segments = 14
	tunnel.mesh = cm
	tunnel.material_override = p.mat("polytunnel", Color(0.86, 0.88, 0.86), 0.4)
	tunnel.rotation.x = PI * 0.5
	tunnel.position = Vector3(hl + 30.0, -0.6, -hw - 2.0)
	holder.add_child(tunnel)
	p.add_fence(root, Vector2(hl + 20.0, -hw - 8.0), Vector2(hl + 44.0, -hw - 8.0), 1.4, 2.5, Color(0.42, 0.3, 0.2), false)
	# Play park: swings and a climbing frame.
	var steel: Material = p.mat("play_red", Color(0.7, 0.15, 0.12), 0.5)
	var base := Vector3(hl + 30.0, 0.0, hw + 6.0)
	for s in [-1.0, 1.0]:
		var leg := p.add_box(holder, Vector3(0.1, 2.6, 0.1), base + Vector3(s * 2.0, 1.2, 0), steel)
		leg.rotation.z = s * 0.15
	p.add_box(holder, Vector3(4.4, 0.1, 0.1), base + Vector3(0, 2.45, 0), steel)
	p.add_box(holder, Vector3(2.5, 1.6, 2.5), base + Vector3(6.0, 0.8, 1.0), p.mat("play_wood", Color(0.5, 0.36, 0.22), 0.8))
	# A shed near the school end of the touchline, and a picnic bench.
	p.add_box(holder, Vector3(3.2, 2.4, 2.4), Vector3(hl * 0.4, 1.2, hw + 9.0), p.mat("shed_green", Color(0.22, 0.32, 0.22), 0.8))
	var timber: Material = p.mat("timber", Color(0.42, 0.3, 0.2), 0.9)
	var t := Vector3(-hl * 0.25, 0, hw + 7.0)
	p.add_box(holder, Vector3(1.8, 0.08, 0.8), t + Vector3(0, 0.75, 0), timber)
	for s in [-1.0, 1.0]:
		p.add_box(holder, Vector3(1.8, 0.06, 0.3), t + Vector3(0, 0.45, s * 0.65), timber)
	# Hay bales and a gate in the field down the glen.
	for i in 6:
		var q := Vector2(-hl - 90.0 + rng.randf_range(-20.0, 20.0), rng.randf_range(-hw, hw + 40.0))
		var bale := p.add_cyl(holder, Vector3(q.x, p.height_m(q.x, q.y) + 0.7, q.y), 0.75, 1.2, p.mat("bale", Color(0.12, 0.12, 0.12), 0.4))
		bale.rotation.z = PI * 0.5
