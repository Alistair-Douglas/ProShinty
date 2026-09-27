extends RefCounted
## Kyles Athletic's pitch at Tighnabruaich, laid out from an aerial photo.
##
## The pitch sits on the shore of the Kyles of Bute. Near side (+Z): a white
## rail on top of a rocky sea wall, a strip of shingle and the loch, with Bute
## across the water. Far side (-Z): a grass bank up to the shore road, with
## lamp posts and a fence, then a steep wooded hillside with big villas above
## the west end. East end: the car park, the clubhouse, a fenced tennis court
## and a play area. West end: a tall ball-stop net, trees and a cottage down
## by the shore.

const WATER_LEVEL := -2.8
const ROAD_LEVEL := 3.5

var p: ShintyPitch
var hl: float
var hw: float
var road_z: float


func _init(pitch: ShintyPitch) -> void:
	p = pitch
	hl = p.hl
	hw = p.hw
	road_z = -(hw + 18.0)


func extra_cloud() -> float:
	return 0.15


func fog_density() -> float:
	return 0.00022


func water() -> Dictionary:
	return {"level": WATER_LEVEL, "color": Color(0.08, 0.16, 0.18), "roughness": 0.05, "wave_scale": 0.5}


func ground_look() -> Dictionary:
	return {
		"wear": 0.1,
		"stripe_width": 5.0,
		"stripe_strength": 0.12,
		"grass_color": Color(0.26, 0.46, 0.16),
		"rough_color": Color(0.3, 0.42, 0.17),
		"gravel_color": Color(0.33, 0.33, 0.34),   # tarmac
		"sand_color": Color(0.45, 0.42, 0.37),     # shingle and weed
		"field_strength": 0.0,
	}


func height_m(x: float, z: float) -> float:
	var n := p.noise.get_noise_2d(x, z)
	# Far side: bank up to the road, then the hillside.
	# Beyond the east end the bank steepens so the car park stays level.
	var east := smoothstep(hl + 3.0, hl + 10.0, x)
	var bank := ROAD_LEVEL * smoothstep(lerpf(hw + 5.0, hw + 11.5, east), lerpf(hw + 15.0, hw + 15.5, east), -z)
	var hill := 110.0 * smoothstep(hw + 22.0, hw + 190.0, -z) * (0.8 + 0.2 * p.noise.get_noise_2d(x * 0.1, 0.0))
	var land := bank + hill + n * 1.5 * smoothstep(hw + 22.0, hw + 40.0, -z)
	# Ends: the shore flat carries on past both ends, a little lumpy.
	land += n * 0.8 * smoothstep(hl + 12.0, hl + 30.0, absf(x)) * (1.0 - smoothstep(hw + 5.0, hw + 12.0, -z))
	# Near side: the sea wall drops to shingle, then the loch bed.
	var wall := smoothstep(hw + 3.5, hw + 10.0, z)
	var shore := lerpf(land, -2.4, wall)
	shore = lerpf(shore, -3.3, smoothstep(hw + 10.0, hw + 18.0, z))
	shore = lerpf(shore, -8.0, smoothstep(hw + 18.0, hw + 45.0, z))
	# Bute, across the Kyles.
	var bute := -8.0 + smoothstep(hw + 1150.0, hw + 1500.0, z) * (170.0 + 70.0 * p.noise.get_noise_2d(x * 0.05, 0.0))
	return maxf(shore, bute)


func ground_mask(x: float, z: float, h: float) -> Color:
	var c := Color(0, 0, 0, 0)
	c.g = p.wildness(x, z, 6.0, 3.5)
	# The shore road and the car park at the east end.
	if absf(z - road_z) < 3.2:
		c.b = 1.0
	if x > hl + 5.0 and x < hl + 46.0 and z < -hw + 2.0 and z > road_z:
		c.b = 1.0
	# Shingle below the sea wall.
	c.a = smoothstep(-1.8, -2.6, h)
	if c.a > 0.0:
		c.g *= 1.0 - c.a
	return c


func build(root: Node3D, rng: RandomNumberGenerator) -> void:
	_build_trees(root, rng)
	_build_sea_wall(root, rng)
	_build_road(root)
	_build_ground_furniture(root)
	_build_houses(root, rng)
	_build_cars_and_boats(root, rng)
	var bank := func(x: float, z: float) -> float:
		var c := ground_mask(x, z, p.height_m(x, z))
		return c.g * (1.0 - c.b) * (1.0 - c.a)
	p.emit_tufts(root, rng, 5000, Rect2(-hl - 40.0, -hw - 16.0, hl * 2.0 + 60.0, 12.0), bank, Color(0.34, 0.44, 0.2))


func _build_trees(root: Node3D, rng: RandomNumberGenerator) -> void:
	var near := ShintyPitch.TreeBatch.new()
	var far := ShintyPitch.TreeBatch.new()
	# The wooded hillside above the road.
	var spacing: float = [9.0, 6.5, 5.0][p.scenery_detail]
	var gz := road_z - 6.0
	while gz > -(hw + 520.0):
		var gx := -hl - 420.0
		while gx < hl + 420.0:
			var px := gx + rng.randf_range(-spacing, spacing) * 0.45
			var pz := gz + rng.randf_range(-spacing, spacing) * 0.45
			var villas := px < -hl * 0.4 and px > -hl - 80.0 and pz > road_z - 70.0
			if not villas and rng.randf() < 0.9:
				var h: float = p.height_m(px, pz)
				if pz > road_z - 30.0 and rng.randf() < 0.35:
					p.add_broadleaf(near, rng, Vector3(px, h, pz), 0.8)
				else:
					p.add_woodland(far, rng, Vector3(px, h - 0.4, pz), 0.3)
			gx += spacing
		gz -= spacing
	# Trees round both ends of the pitch.
	for i in 26:
		var west := i % 2 == 0
		var px := (-hl - rng.randf_range(12.0, 70.0)) if west else (hl + rng.randf_range(48.0, 110.0))
		var pz := rng.randf_range(road_z + 4.0, hw + 2.0)
		if west and absf(pz) < 12.0:
			pz = 12.0 * signf(pz + 0.001) + pz  # leave the view along the pitch open
		p.add_broadleaf(near, rng, Vector3(px, p.height_m(px, pz), pz), rng.randf_range(0.7, 1.0))
	# Bushes along the top of the bank.
	var x := -hl - 20.0
	while x < hl + 4.0:
		if rng.randf() < 0.4:
			p.add_bush(near, rng, Vector3(x, ROAD_LEVEL - 0.3, road_z + 5.0 + rng.randf_range(-1, 1)))
		x += rng.randf_range(4.0, 10.0)
	p.emit_trees(root, near, 12, 7, 64, "TreesNear")
	p.emit_trees(root, far, 8, 5, 22, "Woodland")


## Boulders piled along the shore below the near touchline.
func _build_sea_wall(root: Node3D, rng: RandomNumberGenerator) -> void:
	var rock := SphereMesh.new()
	rock.radius = 1.0
	rock.height = 2.0
	rock.radial_segments = 7
	rock.rings = 4
	var xforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	var x := -hl - 30.0
	while x < hl + 60.0:
		for row in 3:
			var z := hw + 4.5 + row * 2.2 + rng.randf_range(-0.6, 0.6)
			var px := x + rng.randf_range(-0.6, 0.6)
			var s := rng.randf_range(0.7, 1.3)
			var basis := Basis.from_euler(Vector3(rng.randf() * 0.6, rng.randf() * TAU, rng.randf() * 0.6)).scaled(Vector3(s * 1.2, s * 0.7, s))
			xforms.append(Transform3D(basis, Vector3(px, p.height_m(px, z) + 0.1, z)))
			colors.append(Color(0.5, 0.49, 0.47).lerp(Color(0.66, 0.64, 0.6), rng.randf()).srgb_to_linear())
		x += rng.randf_range(1.4, 2.0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = rock
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_color(i, colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "SeaWall"
	mmi.multimesh = mm
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.9
	mmi.material_override = m
	root.add_child(mmi)


func _build_road(root: Node3D) -> void:
	var grey := p.mat("lamp_post", Color(0.55, 0.57, 0.58), 0.5)
	var x := -hl - 200.0
	while x < hl + 200.0:
		var post := p.add_cyl(root, Vector3(x, ROAD_LEVEL + 3.5, road_z + 4.0), 0.07, 7.0, grey)
		post.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		p.add_box(root, Vector3(0.2, 0.12, 1.4), Vector3(x, ROAD_LEVEL + 7.0, road_z + 3.4), grey)
		x += 32.0
	# Post-and-wire fence on the pitch side of the road.
	p.add_fence(root, Vector2(-hl - 200.0, road_z + 4.5), Vector2(hl + 5.0, road_z + 4.5), 1.1, 3.0, Color(0.45, 0.44, 0.4), false)


func _build_ground_furniture(root: Node3D) -> void:
	var holder := Node3D.new()
	holder.name = "Ground"
	root.add_child(holder)
	var white: Material = p.mat("pitch_rail", Color(0.9, 0.9, 0.88), 0.5)
	# White rail along the top of the sea wall.
	p.add_fence(root, Vector2(-hl - 6.0, hw + 3.0), Vector2(hl + 6.0, hw + 3.0), 1.0, 2.5, Color(0.9, 0.9, 0.88), false)
	p.add_box(holder, Vector3(hl * 2.0 + 12.0, 0.06, 0.06), Vector3(0, 0.98, hw + 3.0), white)
	# Ball-stop net along the west end.
	p.add_fence(root, Vector2(-hl - 6.0, -hw - 3.0), Vector2(-hl - 6.0, hw + 2.0), 6.0, 5.0, Color(0.12, 0.3, 0.16), true, 0.18)

	# Clubhouse: white harled walls and a dark roof, by the car park.
	var club := Node3D.new()
	club.name = "Clubhouse"
	club.position = Vector3(hl + 38.0, 0, -hw - 7.0)
	holder.add_child(club)
	var harl: Material = p.mat("harl", Color(0.93, 0.92, 0.88), 0.95)
	p.add_box(club, Vector3(16.0, 3.4, 7.0), Vector3(0, 1.7, 0), harl)
	var roof: MeshInstance3D = p.add_roof(club, Vector3(7.6, 1.6, 16.6), Vector3(0, 4.2, 0), p.mat("roof0", Color(0.24, 0.25, 0.28), 0.85))
	roof.rotation.y = PI * 0.5
	var glass: Material = p.mat("window", Color(0.12, 0.14, 0.17), 0.2)
	for i in 4:
		p.add_box(club, Vector3(1.6, 1.2, 0.1), Vector3(-5.5 + i * 3.6, 1.9, 3.52), glass)

	# Fenced tennis court (a green hard court) between the car park and the play area.
	var court := Rect2(hl + 10.0, -hw + 6.0, 34.0, 18.0)
	var c0 := court.position
	var c1 := court.end
	p.add_box(holder, Vector3(court.size.x, 0.04, court.size.y), Vector3(c0.x + court.size.x * 0.5, 0.02, c0.y + court.size.y * 0.5), p.mat("court", Color(0.2, 0.36, 0.26), 0.8))
	var lines: Material = p.mat("court_line", Color(0.9, 0.9, 0.88), 0.8)
	p.add_box(holder, Vector3(0.08, 0.05, court.size.y - 3.0), Vector3(c0.x + court.size.x * 0.5, 0.03, c0.y + court.size.y * 0.5), lines)
	p.add_box(holder, Vector3(court.size.x - 6.0, 0.05, 0.08), Vector3(c0.x + court.size.x * 0.5, 0.03, c0.y + 2.0), lines)
	p.add_box(holder, Vector3(court.size.x - 6.0, 0.05, 0.08), Vector3(c0.x + court.size.x * 0.5, 0.03, c1.y - 2.0), lines)
	for edge in [[c0, Vector2(c1.x, c0.y)], [Vector2(c1.x, c0.y), c1], [c1, Vector2(c0.x, c1.y)], [Vector2(c0.x, c1.y), c0]]:
		p.add_fence(root, edge[0], edge[1], 3.0, 3.0, Color(0.2, 0.3, 0.22), true, 0.25)
	# Play area: a few bright frames and a bench.
	var play := Vector3(hl + 32.0, 0, hw - 2.0)
	p.add_box(holder, Vector3(3.0, 2.2, 0.15), play, p.mat("play_red", Color(0.75, 0.15, 0.12), 0.6))
	p.add_box(holder, Vector3(0.15, 2.5, 3.0), play + Vector3(5.0, 0, 1.0), p.mat("play_yellow", Color(0.85, 0.7, 0.15), 0.6))
	p.add_box(holder, Vector3(2.0, 0.5, 0.6), play + Vector3(-4.0, 0.25, 3.0), p.mat("timber", Color(0.55, 0.42, 0.3), 0.9))


func _build_houses(root: Node3D, rng: RandomNumberGenerator) -> void:
	var holder := Node3D.new()
	holder.name = "Houses"
	root.add_child(holder)
	# Villas on the slope above the west end, looking out over the Kyles.
	for q in [Vector2(-hl - 55.0, road_z - 22.0), Vector2(-hl - 30.0, road_z - 25.0), Vector2(-hl - 8.0, road_z - 45.0)]:
		p.add_house(holder, rng, Vector3(q.x, p.height_m(q.x, q.y), q.y), PI * 0.5)
	# A cottage down by the shore at the west end.
	p.add_house(holder, rng, Vector3(-hl - 32.0, 0.0, hw - 4.0), 0.4)
	# The village carries on east along the shore road.
	var count: int = [4, 7, 10][p.scenery_detail]
	for i in count:
		var px := hl + 70.0 + i * 16.0
		var pz := road_z - 9.0 - rng.randf_range(0.0, 4.0)
		p.add_house(holder, rng, Vector3(px, p.height_m(px, pz), pz), PI * 0.5)


func _build_cars_and_boats(root: Node3D, rng: RandomNumberGenerator) -> void:
	var holder := Node3D.new()
	holder.name = "Cars"
	root.add_child(holder)
	p.park_row(holder, rng, Vector3(hl + 10.0, 0, -hw - 10.0), Vector3(hl + 28.0, 0, -hw - 10.0), -PI * 0.5, 0.7)
	p.park_row(holder, rng, Vector3(hl + 10.0, 0, -hw - 2.0), Vector3(hl + 26.0, 0, -hw - 2.0), PI * 0.5, 0.5)
	p.add_car(holder, rng, Vector3(-30.0, ROAD_LEVEL, road_z - 1.5), 0.0)
	# Small boats moored in the Kyles.
	var hull: Material = p.mat("hull", Color(0.93, 0.93, 0.92), 0.4)
	var deck: Material = p.mat("deck", Color(0.2, 0.3, 0.45), 0.6)
	for i in 4:
		var b := Node3D.new()
		b.position = Vector3(rng.randf_range(-hl, hl + 120.0), WATER_LEVEL + 0.25, hw + rng.randf_range(70.0, 260.0))
		b.rotation.y = rng.randf_range(-0.4, 0.4)
		holder.add_child(b)
		p.add_box(b, Vector3(6.0, 0.9, 2.2), Vector3.ZERO, hull)
		p.add_box(b, Vector3(2.2, 1.0, 1.6), Vector3(-0.5, 0.9, 0), deck)
		if i % 2 == 0:
			p.add_cyl(b, Vector3(0.6, 5.0, 0), 0.05, 9.0, hull)  # a mast
