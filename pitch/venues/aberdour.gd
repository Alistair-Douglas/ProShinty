extends RefCounted
## Aberdour Shinty Club's pitch, laid out from the satellite view and photos.
##
## The pitch runs west to east. North (-Z): a path, a strip of long grass and
## earthworks, the fenced railway on a low embankment, then Brachi Woods
## climbing to Hawkcraig in the north-east and houses to the north-west.
## South (+Z): a tree-lined path running at a slant, with cars parked along it,
## and Hawkcraig Park's fields beyond. East: paths, a hut, a walled garden,
## then Silversands beach and the Firth of Forth, with Inchcolm out in the
## water and the Lothian shore on the horizon. West: a car park behind the
## hail and the village.

const SEA_LEVEL := -3.5
const SEA_FLOOR := -7.5

var p: ShintyPitch
var hl: float
var hw: float
var rail_z: float
var rail_path: PackedVector2Array
var avenue: PackedVector2Array  # the tree-lined path to the south
var east_paths: Array[PackedVector2Array] = []
var inchcolm := Vector2(420.0, 1500.0)


func _init(pitch: ShintyPitch) -> void:
	p = pitch
	hl = p.hl
	hw = p.hw
	rail_z = -(hw + 36.0)
	rail_path = PackedVector2Array([Vector2(-3000, rail_z), Vector2(hl + 50, rail_z),
			Vector2(hl + 110, rail_z - 40), Vector2(hl + 190, rail_z - 200), Vector2(hl + 600, -3000)])
	avenue = PackedVector2Array([Vector2(-hl - 90, hw + 55), Vector2(hl + 28, hw + 17)])
	east_paths = [
		PackedVector2Array([Vector2(hl + 28, hw + 17), Vector2(hl + 14, hw * 0.35), Vector2(hl + 40, -4.0),
				Vector2(hl + 95, -8.0), Vector2(hl + 118, -hw - 25), Vector2(hl + 150, -hw - 120)]),
		PackedVector2Array([Vector2(hl + 95, -8.0), Vector2(hl + 110, hw + 40), Vector2(hl + 100, hw + 90)]),
		PackedVector2Array([Vector2(-hl - 200, -hw - 8), Vector2(hl + 118, -hw - 25)]),  # path by the railway
	]


func extra_cloud() -> float:
	return 0.0


func fog_density() -> float:
	return 0.0005


func water() -> Dictionary:
	return {"level": SEA_LEVEL, "color": Color(0.16, 0.27, 0.36), "roughness": 0.12}


func ground_look() -> Dictionary:
	return {"wear": 0.55}


## Land height in metres. Positive on land away from the (dead flat) park.
func height_m(x: float, z: float) -> float:
	var wild: float = p.wildness(x, z)
	var woods := 38.0 * smoothstep(hw + 45.0, hw + 140.0, -z) * smoothstep(-hl * 0.6, hl * 0.4, x)
	var north := 24.0 * smoothstep(hw + 50.0, hw + 260.0, -z)
	var west := 14.0 * smoothstep(hl + 60.0, hl + 260.0, -x)
	var far := 170.0 * smoothstep(1400.0, 4500.0, maxf(-z, -x * 0.8)) * (0.6 + 0.4 * p.noise.get_noise_2d(x * 0.05, z * 0.05))
	var rise: float = maxf(maxf(woods, north), maxf(west, far))
	var h: float = (rise + p.noise.get_noise_2d(x, z) * (1.5 + rise * 0.15)) * wild

	# The railway runs level on a low embankment, in a cutting through the woods.
	var rd: float = p.dist_to_path(Vector2(x, z), rail_path)
	h = lerpf(h, 1.6, 1.0 - smoothstep(4.5, 13.0, rd))

	# Coast: sea past the east end and, beyond Hawkcraig Park, to the south.
	var coast_x := hl + 135.0 + maxf(0.0, -z - (hw + 150.0)) * 0.9
	var south_z := hw + 260.0 + maxf(0.0, -x - 300.0) * 0.35
	var d: float = minf(coast_x - x, south_z - z)
	var land := smoothstep(-5.0, 40.0, d)
	h = h * land + SEA_FLOOR * (1.0 - land)
	# Inchcolm, and the Lothian shore across the Forth.
	var isle := SEA_FLOOR + 34.0 * smoothstep(260.0, 50.0, Vector2(x, z).distance_to(inchcolm))
	var lothian := SEA_FLOOR + smoothstep(5200.0, 5800.0, z) * (75.0 + 45.0 * p.noise.get_noise_2d(x * 0.03, 0.0))
	return maxf(h, maxf(isle, lothian))


## Vertex masks for the ground shader: r earth, g rough grass, b gravel, a sand.
func ground_mask(x: float, z: float, h: float) -> Color:
	var c := Color(0, 0, 0, 0)
	var pos := Vector2(x, z)
	c.g = p.wildness(x, z, 24.0, 22.0)
	# Long grass between the north path and the earthworks.
	if z < -(hw + 10.0) and z > -(hw + 14.0) and x > -hl * 0.15:
		c.g = 0.8
	# Earthworks between the path and the railway fence (photo 1).
	if z < -(hw + 13.0) and z > -(hw + 27.0) and x > -hl * 0.05 and x < hl + 20.0:
		c.r = 1.0
		c.g = 0.0
	# Railway ballast, footpaths and the west car park.
	if p.dist_to_path(pos, rail_path) < 3.8:
		c.b = 1.0
	if p.dist_to_path(pos, avenue) < 2.4:
		c.b = 0.9
	for path in east_paths:
		if p.dist_to_path(pos, path) < 1.6:
			c.b = 0.85
	if x < -(hl + 10.0) and x > -(hl + 32.0) and z < -6.0 and z > -(hw + 2.0):
		c.b = 1.0
	# Beach.
	c.a = smoothstep(-0.6, -2.2, h)
	if c.a > 0.0:
		c.g *= 1.0 - c.a
		c.b *= 1.0 - c.a
	return c


func build(root: Node3D, rng: RandomNumberGenerator) -> void:
	_build_trees(root, rng)
	_build_buildings(root, rng)
	_build_cars(root, rng)
	_build_railway(root)
	_build_earthworks(root)


func _build_trees(root: Node3D, rng: RandomNumberGenerator) -> void:
	var big := ShintyPitch.TreeBatch.new()
	var small := ShintyPitch.TreeBatch.new()

	# The avenue along the south path: a row either side.
	var a := avenue[0]
	var b := avenue[1]
	var dir := (b - a).normalized()
	var side := Vector2(-dir.y, dir.x)
	var t := 0.0
	var length := a.distance_to(b)
	while t < length:
		for s in [-5.5, 5.5]:
			var q: Vector2 = a + dir * (t + rng.randf_range(-1.5, 1.5)) + side * s
			p.add_broadleaf(big, rng, Vector3(q.x, 0, q.y))
		t += rng.randf_range(9.0, 13.0)

	# North side: the clump of big dark trees and a lone one further east.
	for i in 4:
		var px := lerpf(-hl * 0.42, -hl * 0.12, i / 3.0) + rng.randf_range(-3, 3)
		p.add_dark_round(big, rng, Vector3(px, 0, -(hw + 18.0) + rng.randf_range(-2, 2)))
	p.add_dark_round(big, rng, Vector3(hl * 0.36, 0, -(hw + 19.0)))
	# Trees lining the railway, thickest west of the earthworks.
	var x := -hl - 160.0
	while x < hl + 50.0:
		if x < -hl * 0.5 or rng.randf() < 0.25:
			p.add_broadleaf(big, rng, Vector3(x, 0, rail_z + 10.0 + rng.randf_range(-2, 2)), 0.85)
		p.add_broadleaf(big, rng, Vector3(x + 5.0, 0, rail_z - 10.0 + rng.randf_range(-2, 2)), 0.9)
		x += rng.randf_range(9.0, 14.0)
	# A few trees round the west car park.
	for i in 5:
		p.add_broadleaf(big, rng, Vector3(-hl - 38.0 + rng.randf_range(-4, 4), 0, rng.randf_range(-hw, hw * 0.5)))
	# Bushes in the long grass.
	x = -hl * 0.1
	while x < hl + 20.0:
		if rng.randf() < 0.5:
			p.add_bush(small, rng, Vector3(x, 0, -(hw + rng.randf_range(10.0, 13.5))))
		x += rng.randf_range(4.0, 9.0)
	# Hedgerow trees on Hawkcraig Park's field edges.
	var z := hw + 70.0
	while z < hw + 240.0:
		p.add_broadleaf(big, rng, Vector3(-hl - 40.0 + rng.randf_range(-2, 2), 0, z), 0.8)
		z += rng.randf_range(12.0, 20.0)
	x = -hl - 200.0
	while x < hl + 60.0:
		if rng.randf() < 0.6:
			p.add_broadleaf(big, rng, Vector3(x, 0, hw + 140.0 + rng.randf_range(-2, 2)), 0.8)
		x += rng.randf_range(12.0, 20.0)

	# Woodland: Brachi Woods and Hawkcraig are dense, the rest is scattered.
	var spacing: float = [11.0, 7.5, 6.0][p.scenery_detail]
	var gz := -(hw + 420.0)
	while gz < hw + 260.0:
		var gx := -(hl + 380.0)
		while gx < hl + 200.0:
			var px := gx + rng.randf_range(-spacing, spacing) * 0.45
			var pz := gz + rng.randf_range(-spacing, spacing) * 0.45
			var h: float = p.height_m(px, pz)
			var rd: float = p.dist_to_path(Vector2(px, pz), rail_path)
			var chance := 0.0
			if h < 0.3 or rd < 9.0:
				chance = 0.0
			elif pz < -(hw + 50.0) and px > -hl * 0.4:
				chance = 0.92  # Brachi Woods and Hawkcraig
			elif px > hl + 20.0 and pz < hw * 0.2:
				chance = 0.45  # trees round the paths at the east end
			elif px > hl + 20.0 and (px < hl + 70.0 and pz > hw + 20.0):
				chance = 0.0  # walled garden
			elif px > hl + 20.0:
				chance = 0.2
			elif h > 2.0:
				chance = 0.035
			if rng.randf() < chance and p.dist_to_path(Vector2(px, pz), avenue) > 9.0:
				p.add_woodland(small, rng, Vector3(px, h - 0.4, pz))
			gx += spacing
		gz += spacing

	p.emit_trees(root, big, 18, 9, "TreesNear")
	p.emit_trees(root, small, 10, 6, "Woodland")


func _build_buildings(root: Node3D, rng: RandomNumberGenerator) -> void:
	var holder := Node3D.new()
	holder.name = "Buildings"
	root.add_child(holder)
	var count: int = [6, 10, 14][p.scenery_detail]
	# Two terraces north-west of the railway, facing the pitch.
	for row in 2:
		for i in count:
			var px := -hl - 110.0 + i * 11.5 + row * 5.0
			var pz := rail_z - 34.0 - row * 26.0 - rng.randf_range(0.0, 3.0)
			if px > -hl * 0.45:
				break
			p.add_house(holder, rng, Vector3(px, p.height_m(px, pz), pz), PI * 0.5)
	# The village street west of the park.
	for i in count:
		var pz := -hw - 10.0 + i * 13.0
		var px := -hl - 150.0 - (i % 2) * 3.0
		p.add_house(holder, rng, Vector3(px, p.height_m(px, pz), pz), 0.0)
	# By the beach: the café and a couple of houses.
	var cafe := Node3D.new()
	cafe.position = Vector3(hl + 112.0, p.height_m(hl + 112.0, hw + 78.0), hw + 78.0)
	cafe.rotation.y = 0.2
	holder.add_child(cafe)
	var white: Material = p.mat("cafe", Color(0.92, 0.9, 0.86), 0.9)
	p.add_box(cafe, Vector3(9.0, 5.0, 16.0), Vector3(0, 1.5, 0), white)
	p.add_roof(cafe, Vector3(9.8, 2.6, 16.6), Vector3(0, 5.3, 0), p.mat("roof0", Color(0.24, 0.25, 0.28), 0.85))
	for i in 2:
		var px := hl + 95.0 + i * 14.0
		var pz := hw + 100.0 + i * 8.0
		p.add_house(holder, rng, Vector3(px, p.height_m(px, pz), pz), 0.3)
	# The timber hut where the avenue meets the east end (satellite view).
	var hut := Node3D.new()
	hut.name = "Hut"
	hut.position = Vector3(hl + 12.0, 0, hw * 0.55)
	hut.rotation.y = 0.3
	holder.add_child(hut)
	p.add_box(hut, Vector3(8.0, 3.0, 5.0), Vector3(0, 1.5, 0), p.mat("timber", Color(0.55, 0.42, 0.3), 0.9))
	var roof: MeshInstance3D = p.add_roof(hut, Vector3(5.6, 1.7, 8.6), Vector3(0, 3.85, 0), p.mat("hut_roof", Color(0.55, 0.3, 0.22), 0.85))
	roof.rotation.y = PI * 0.5
	# The walled garden south-east of the pitch.
	var stone: Material = p.mat("stone_wall", Color(0.6, 0.55, 0.48), 1.0)
	var x0 := hl + 22.0
	var x1 := hl + 66.0
	var z0 := hw + 24.0
	var z1 := hw + 82.0
	p.add_box(holder, Vector3(x1 - x0, 1.8, 0.5), Vector3((x0 + x1) * 0.5, 0.9, z0), stone)
	p.add_box(holder, Vector3(x1 - x0, 1.8, 0.5), Vector3((x0 + x1) * 0.5, 0.9, z1), stone)
	p.add_box(holder, Vector3(0.5, 1.8, z1 - z0), Vector3(x0, 0.9, (z0 + z1) * 0.5), stone)
	p.add_box(holder, Vector3(0.5, 1.8, z1 - z0), Vector3(x1, 0.9, (z0 + z1) * 0.5), stone)
	# The ruined abbey on Inchcolm.
	var ih: float = p.height_m(inchcolm.x, inchcolm.y)
	p.add_box(holder, Vector3(30, 12, 14), Vector3(inchcolm.x, ih + 5.0, inchcolm.y), p.mat("abbey", Color(0.62, 0.6, 0.56), 1.0))
	p.add_box(holder, Vector3(6, 22, 6), Vector3(inchcolm.x + 10.0, ih + 10.0, inchcolm.y), p.mat("abbey", Color(0.62, 0.6, 0.56), 1.0))


func _build_cars(root: Node3D, rng: RandomNumberGenerator) -> void:
	var holder := Node3D.new()
	holder.name = "Cars"
	root.add_child(holder)
	# Car park behind the west hail.
	p.park_row(holder, rng, Vector3(-hl - 18.0, 0, -hw + 3.0), Vector3(-hl - 18.0, 0, -9.0), 0.0)
	p.park_row(holder, rng, Vector3(-hl - 27.0, 0, -hw + 3.0), Vector3(-hl - 27.0, 0, -12.0), PI, 0.45)
	# Parked along the north side of the avenue, noses to the pitch (photo 3).
	var a := avenue[0]
	var b := avenue[1]
	var dir := (b - a).normalized()
	var yaw := -atan2(dir.y, dir.x) + PI * 0.5
	var off := Vector2(dir.y, -dir.x) * 2.6
	var start := a.lerp(b, 0.45) + off
	var end := b + off - dir * 6.0
	p.park_row(holder, rng, Vector3(start.x, 0, start.y), Vector3(end.x, 0, end.y), yaw, 0.65, 3.1)
	var v := start.lerp(end, 0.35) + off * 0.2
	p.add_van(holder, Vector3(v.x, 0, v.y), yaw)


func _build_railway(root: Node3D) -> void:
	var steel: Material = p.mat("rail", Color(0.35, 0.33, 0.32), 0.4)
	for i in rail_path.size() - 1:
		var a := rail_path[i]
		var b := rail_path[i + 1]
		if a.x > hl + 600.0:
			break
		var dir := (b - a).normalized()
		var side := Vector2(-dir.y, dir.x)
		var len := a.distance_to(b)
		var mid := (a + b) * 0.5
		for off in [-2.8, -1.36, 1.36, 2.8]:
			var q: Vector2 = mid + side * off
			var r: MeshInstance3D = p.add_box(root, Vector3(len + 0.5, 0.16, 0.08), Vector3(q.x, 1.72, q.y), steel)
			r.rotation.y = -atan2(dir.y, dir.x)
			r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Lineside fence facing the pitch, as in photo 1.
	p.add_fence(root, Vector2(-hl - 160.0, rail_z + 7.0), Vector2(hl + 50.0, rail_z + 7.0), 1.8, 2.5, Color(0.45, 0.47, 0.45))


func _build_earthworks(root: Node3D) -> void:
	var soil: Material = p.mat("soil", Color(0.5, 0.32, 0.22), 1.0)
	for q in [Vector3(hl * 0.3, 0, -(hw + 20.0)), Vector3(hl * 0.62, 0, -(hw + 22.0)), Vector3(hl * 0.08, 0, -(hw + 21.0))]:
		var heap := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 1.0
		sm.height = 2.0
		sm.radial_segments = 12
		sm.rings = 6
		sm.is_hemisphere = true
		heap.mesh = sm
		heap.scale = Vector3(8.0, 3.0, 4.5)
		heap.position = q
		heap.material_override = soil
		root.add_child(heap)
