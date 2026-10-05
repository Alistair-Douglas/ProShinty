extends RefCounted
## Mossfield Park, Oban: Oban Camanachd's and Oban Celtic's ground, laid out
## from aerial views and photos of it.
##
## The pitch sits in a hollow on the edge of the town, ringed by wooded hills.
## Far side (-Z): the covered stand left of halfway, with white terraced steps,
## yellow stair edges, blue steelwork and a curved roof, then a wall of tall
## conifers, the training pitch behind them and a wooded crag rising above.
## Near side (+Z): a gravel track along the touchline that sweeps round the
## east end, the white club buildings and sheds towards the west, and past
## halfway the grass mound, a flat-topped plateau whose steep banks the crowd
## sits on. West end: a big gravel yard and car park with tall trees along the
## pitch, then Mossfield Avenue and the town running down to Oban Bay. East
## end: the track, trees and a craggy knoll, with houses on the slopes.

const WATER_LEVEL := -12.0
const MOUND_H := 4.5
const CRAG_H := 60.0

var p: ShintyPitch
var hl: float
var hw: float
var track: PackedVector2Array
var roads: Array[PackedVector2Array] = []
var mound: Vector2           # centre of the grass mound
var mound_r := Vector2(40.0, 25.0)
var crag: Vector2            # the wooded crag behind the far side
var knoll: Vector2           # the craggy knoll past the east end
var stand_x := -31.0         # middle of the stand along the far touchline
var stand_len := 32.0
var stand_z: float           # front of the terracing
var yard: Rect2              # the gravel yard and car park past the west end
var training: Rect2          # the training pitch behind the far side


func _init(pitch: ShintyPitch) -> void:
	p = pitch
	hl = p.hl
	hw = p.hw
	stand_z = -hw - 4.8
	mound = Vector2(hl * 0.55, hw + 41.0)
	crag = Vector2(30.0, -hw - 185.0)
	knoll = Vector2(hl + 150.0, hw + 120.0)
	yard = Rect2(-hl - 62.0, -hw - 6.0, 54.0, hw * 2.0 + 22.0)
	training = Rect2(-46.0, -hw - 62.0, 104.0, 40.0)
	# The track along the near side and round the east end.
	track = PackedVector2Array([Vector2(-hl - 8.0, hw + 5.5), Vector2(hl - 4.0, hw + 5.5),
		Vector2(hl + 6.0, hw - 2.0), Vector2(hl + 7.5, -hw - 4.0), Vector2(hl - 10.0, -hw - 7.5)])
	# Alltan Tartach behind the club buildings and the mound; Mossfield
	# Avenue past the west end; Glencruitten Road beyond the training pitch.
	roads.append(PackedVector2Array([Vector2(-hl - 300.0, hw + 30.0), Vector2(-hl - 70.0, hw + 30.0),
		Vector2(-12.0, hw + 36.0), Vector2(-4.0, hw + 78.0), Vector2(hl + 60.0, hw + 92.0), Vector2(hl + 200.0, hw + 130.0)]))
	roads.append(PackedVector2Array([Vector2(-hl - 75.0, hw + 30.0), Vector2(-hl - 78.0, -hw - 40.0),
		Vector2(-hl - 70.0, -hw - 70.0), Vector2(-hl - 120.0, -hw - 240.0)]))
	roads.append(PackedVector2Array([Vector2(-hl - 70.0, -hw - 70.0), Vector2(hl + 40.0, -hw - 72.0), Vector2(hl + 160.0, -hw - 40.0)]))


func extra_cloud() -> float:
	return 0.25


func fog_density() -> float:
	return 0.00016


func water() -> Dictionary:
	return {"level": WATER_LEVEL, "color": Color(0.08, 0.15, 0.19), "roughness": 0.06, "wave_scale": 0.5}


func ground_look() -> Dictionary:
	return {
		"wear": 0.1,
		"stripe_width": 5.0,
		"stripe_strength": 0.1,
		"grass_color": Color(0.27, 0.47, 0.15),
		"rough_color": Color(0.09, 0.16, 0.07),    # the wooded hills from afar
		"earth_color": Color(0.36, 0.35, 0.32),    # rock on the crags
		"gravel_color": Color(0.44, 0.42, 0.39),
		"sand_color": Color(0.27, 0.27, 0.28),     # tarmac
		"field_strength": 0.0,
	}


## Ad boards along the far touchline, the stand behind them, and the usual
## rows behind each hail.
func board_rows() -> Array:
	return [[Vector2(-hl, -hw - 3.7), Vector2(hl, -hw - 3.7), 0],
		[Vector2(-hl - 4.6, -hw * 0.8), Vector2(-hl - 4.6, hw * 0.8), 3],
		[Vector2(hl + 4.6, -hw * 0.8), Vector2(hl + 4.6, hw * 0.8), 5]]


func height_m(x: float, z: float) -> float:
	var pos := Vector2(x, z)
	var n := p.noise.get_noise_2d(x, z)
	# The mound: a flat top with steep banks.
	var e := Vector2((x - mound.x) / mound_r.x, (z - mound.y) / mound_r.y).length()
	var mnd := MOUND_H * smoothstep(1.0, 0.72, e)
	# Hills all round, lower towards the town and the bay in the west.
	var r := pos.length()
	var west := maxf(0.0, -x / maxf(r, 1.0))
	var ridge := 1.0 - absf(p.noise.get_noise_2d(x * 0.04, z * 0.04))
	var hills := (160.0 - 135.0 * west) * smoothstep(240.0, 1100.0, r) * (0.6 + 0.4 * ridge)
	hills += 12.0 * smoothstep(60.0, 220.0, r) * (1.0 - west)
	# The crag behind the far side, its rock face towards the pitch, and the
	# knoll past the east end.
	var c := CRAG_H * minf(1.0, 1.3 * smoothstep(125.0, 45.0, pos.distance_to(crag))) * (0.9 + 0.1 * n)
	var k := 42.0 * smoothstep(105.0, 30.0, pos.distance_to(knoll)) * (0.9 + 0.1 * n)
	var rough := p.noise.get_noise_2d(x * 0.2, z * 0.2) * 3.0 + n * 1.2
	var land := (maxf(hills, maxf(c, k)) + rough) * p.wildness(x, z, 6.0, 6.0)
	# The training pitch and the yard are level.
	land *= smoothstep(0.0, 8.0, _rect_inset(training, pos)) * smoothstep(0.0, 6.0, _rect_inset(yard, pos))
	land = maxf(land, mnd)
	# Down to Oban Bay past the town.
	land = lerpf(land, WATER_LEVEL - 6.0, smoothstep(900.0, 1100.0, -x - absf(z) * 0.35))
	return land


## How far `pos` is outside `r` (negative inside).
func _rect_inset(r: Rect2, pos: Vector2) -> float:
	var d := Vector2(maxf(r.position.x - pos.x, pos.x - r.end.x), maxf(r.position.y - pos.y, pos.y - r.end.y))
	return maxf(d.x, d.y)


func ground_mask(x: float, z: float, h: float) -> Color:
	var c := Color(0, 0, 0, 0)
	var pos := Vector2(x, z)
	# The wooded hills: dark green from a distance.
	c.g = smoothstep(4.0, 15.0, h) * p.wildness(x, z, 20.0, 20.0)
	# Rock on the crag's face and the knoll's top.
	var dc := pos.distance_to(crag)
	var face := smoothstep(100.0, 90.0, dc) * smoothstep(70.0, 80.0, dc) * smoothstep(0.5, 0.8, (z - crag.y) / maxf(dc, 1.0))
	var top := smoothstep(30.0, 18.0, pos.distance_to(knoll)) * 0.7
	var patchy := smoothstep(0.05, 0.35, p.noise.get_noise_2d(x * 0.15, z * 0.15))
	c.r = maxf(face, top) * patchy * 0.75
	# Gravel: the track and the yard; tarmac on the roads.
	if p.dist_to_path(pos, track) < 2.6 or yard.has_point(pos):
		c.b = 1.0
	if pos.x > -hl * 0.75 and pos.x < -4.0 and z > hw + 8.0 and z < hw + 34.0:
		c.b = 1.0   # the yard round the club buildings
	for road in roads:
		if p.dist_to_path(pos, road) < 3.4:
			c.a = 1.0
			c.b = 0.0
	if training.has_point(pos):
		c.g = 0.0
	if c.b > 0.0 or c.a > 0.0:
		c.r = 0.0
		c.g = 0.0
	return c


func build(root: Node3D, rng: RandomNumberGenerator) -> void:
	_build_trees(root, rng)
	_build_stand(root)
	_build_club(root)
	_build_training(root)
	_build_houses(root, rng)
	_build_cars(root, rng)
	var edge := func(x: float, z: float) -> float:
		var c := ground_mask(x, z, p.height_m(x, z))
		return (1.0 - c.b) * (1.0 - c.a) * p.wildness(x, z, 8.0, 10.0) * (1.0 - smoothstep(10.0, 30.0, p.height_m(x, z)))
	p.emit_tufts(root, rng, 2500, Rect2(hl + 4.0, -hw - 30.0, 40.0, hw * 2.0 + 40.0), edge, Color(0.36, 0.44, 0.2))


## Spectators on the stand's terracing, facing the pitch: [position, facing,
## front row] like ShintyCrowd's own spots.
func crowd_spots(rng: RandomNumberGenerator, density: float) -> Array:
	var spots := []
	for tier in 6:
		var z := stand_z - 0.9 - tier * 0.8
		var y := 0.3 + 0.4 * (tier + 1)
		var x := stand_x - stand_len * 0.5 + 2.0
		while x < stand_x + stand_len * 0.5 - 2.0:
			x += 1.0 / density * rng.randf_range(0.5, 1.3)
			if rng.randf() < 0.4 + 0.08 * tier:
				continue
			spots.append([Vector3(x, y, z + rng.randf_range(-0.1, 0.1)), Vector3(-x * 0.01, 0, 1).normalized(), false])
	return spots


func _build_trees(root: Node3D, rng: RandomNumberGenerator) -> void:
	var near := ShintyPitch.TreeBatch.new()
	var far := ShintyPitch.TreeBatch.new()
	var detail: float = [0.5, 0.8, 1.0][p.scenery_detail]
	# The wall of tall conifers behind the stand and along the far side.
	var x := -hl - 12.0
	while x < hl + 2.0:
		var q := Vector2(x, -hw - rng.randf_range(14.0, 18.0))
		p.add_pine(near, rng, Vector3(q.x, 0.0, q.y))
		x += rng.randf_range(3.5, 5.5) / detail
	# Tall trees along the west end, between the pitch and the yard.
	var z := -hw - 8.0
	while z < hw * 0.5:
		var q := Vector2(-hl - rng.randf_range(8.0, 11.0), z)
		if absf(z) < 16.0:
			z += 4.0
			continue   # keep the view down the pitch from behind the hail clear
		if rng.randf() < 0.75:
			p.add_pine(near, rng, Vector3(q.x, 0.0, q.y))
		else:
			p.add_broadleaf(near, rng, Vector3(q.x, 0.0, q.y), rng.randf_range(0.8, 1.0))
		z += rng.randf_range(4.5, 7.0) / detail
	# Trees past the east end and round the mound, and by the club buildings.
	for i in int(34 * detail):
		var q := Vector2(hl + rng.randf_range(14.0, 60.0), rng.randf_range(-hw - 30.0, hw + 20.0))
		p.add_broadleaf(near, rng, Vector3(q.x, p.height_m(q.x, q.y), q.y), rng.randf_range(0.65, 1.0))
	for i in int(14 * detail):
		var a := rng.randf() * TAU
		var q := mound + Vector2(cos(a) * mound_r.x, sin(a) * mound_r.y) * rng.randf_range(1.1, 1.3)
		if q.y < hw + 20.0:
			continue
		p.add_broadleaf(near, rng, Vector3(q.x, p.height_m(q.x, q.y), q.y), rng.randf_range(0.6, 0.9))
	for i in int(10 * detail):
		var q := Vector2(rng.randf_range(-hl * 0.8, -6.0), hw + rng.randf_range(38.0, 52.0))
		p.add_broadleaf(near, rng, Vector3(q.x, p.height_m(q.x, q.y), q.y), rng.randf_range(0.6, 0.9))
	# Woods on the crag, the knoll and the hills round about: thinner further out.
	var spacing: float = [17.0, 12.5, 10.0][p.scenery_detail]
	var gz := -420.0
	while gz < 420.0:
		var gx := -300.0
		while gx < 450.0:
			var r := Vector2(gx, gz).length()
			var keep := 1.0 - smoothstep(250.0, 420.0, r)
			if rng.randf() < keep and p.noise.get_noise_2d(gx * 0.5, gz * 0.5) > 0.0:
				var px := gx + rng.randf_range(-0.5, 0.5) * spacing
				var pz := gz + rng.randf_range(-0.5, 0.5) * spacing
				var h: float = p.height_m(px, pz)
				var c := ground_mask(px, pz, h)
				if h > 3.0 and c.b == 0.0 and c.a == 0.0 and c.r < 0.3 and not _built_up(Vector2(px, pz)):
					if r < 200.0:
						p.add_broadleaf(near, rng, Vector3(px, h, pz), rng.randf_range(0.7, 1.0))
					else:
						p.add_woodland(far, rng, Vector3(px, h - 0.4, pz), 0.45)
			gx += spacing
		gz += spacing
	# The crag and the knoll are wooded all over but for the rock.
	for hill in [[crag, 115.0], [knoll, 100.0]]:
		var n_trees := int(PI * hill[1] * hill[1] / (spacing * spacing * 0.8))
		for i in n_trees:
			var a := rng.randf() * TAU
			var q: Vector2 = hill[0] + Vector2(cos(a), sin(a)) * hill[1] * sqrt(rng.randf())
			var h: float = p.height_m(q.x, q.y)
			var c := ground_mask(q.x, q.y, h)
			if c.r < 0.3 and c.a == 0.0 and h > 3.0:
				p.add_woodland(far, rng, Vector3(q.x, h - 0.4, q.y), 0.5)
	for i in int(40 * detail):
		var q := Vector2(rng.randf_range(-hl - 520.0, -hl - 150.0), rng.randf_range(-330.0, 300.0))
		p.add_woodland(far, rng, Vector3(q.x, p.height_m(q.x, q.y) - 0.4, q.y), 0.3)
	p.emit_trees(root, near, 12, 7, 64, "TreesNear")
	p.emit_trees(root, far, 8, 5, 22, "Woodland")


## Where the houses are, so the woods stay out of the gardens.
func _built_up(q: Vector2) -> bool:
	return (q.y > hw + 70.0 and q.y < hw + 110.0 and q.x > -hl - 40.0 and q.x < hl * 0.4) \
		or (q.x < -hl - 60.0 and q.x > -hl - 120.0 and q.y > -hw - 60.0 and q.y < hw + 80.0) \
		or (q.x < -hl - 160.0)


## The stand: six white terraced steps with dark seat edges and yellow stair
## nosings at the ends, blue steel columns, pale cladding at the back and a
## curved dark roof.
func _build_stand(root: Node3D) -> void:
	var holder := Node3D.new()
	holder.name = "Stand"
	holder.position = Vector3(stand_x, 0.0, stand_z)
	root.add_child(holder)
	var white: Material = p.mat("terrace_white", Color(0.9, 0.9, 0.88), 0.85)
	var dark: Material = p.mat("terrace_edge", Color(0.2, 0.2, 0.21), 0.8)
	var yellow: Material = p.mat("stair_yellow", Color(0.95, 0.78, 0.1), 0.6)
	var blue: Material = p.mat("stand_blue", Color(0.12, 0.24, 0.55), 0.5)
	var clad: Material = p.mat("stand_clad", Color(0.72, 0.76, 0.66), 0.7)
	var roof_mat: Material = p.mat("stand_roof_green", Color(0.22, 0.27, 0.27), 0.6)
	var L := stand_len
	var depth := 0.6 + 6.0 * 0.8
	# The concrete walkway in front, then the steps.
	p.add_box(holder, Vector3(L + 2.0, 0.3, 0.6), Vector3(0, 0.15, -0.3), p.mat("concrete", Color(0.62, 0.61, 0.58), 0.9))
	for tier in 6:
		var h := 0.3 + 0.4 * (tier + 1)
		var z := -0.6 - tier * 0.8 - 0.4
		p.add_box(holder, Vector3(L, h, 0.8), Vector3(0, h * 0.5, z), white)
		p.add_box(holder, Vector3(L - 2.6, 0.07, 0.12), Vector3(0, h - 0.02, z + 0.36), dark)
		for s in [-1.0, 1.0]:
			p.add_box(holder, Vector3(1.2, 0.06, 0.14), Vector3(s * (L * 0.5 - 0.65), h + 0.01, z + 0.35), yellow)
	# Back wall and end walls, with blue columns.
	var back := -depth
	var wall_h := 5.6
	p.add_box(holder, Vector3(L, wall_h, 0.15), Vector3(0, wall_h * 0.5, back), clad)
	for i in 9:
		var cx := -L * 0.5 + i * L / 8.0
		p.add_box(holder, Vector3(0.22, wall_h + 0.4, 0.22), Vector3(cx, (wall_h + 0.4) * 0.5, back + 0.15), blue)
	for s in [-1.0, 0.0, 1.0]:
		p.add_box(holder, Vector3(0.24, 5.9, 0.24), Vector3(s * (L * 0.5 - 0.15), 2.95, -0.15), blue)
	# Cross-bracing in the middle bay of the back wall.
	for d in [-1.0, 1.0]:
		var brace := p.add_box(holder, Vector3(0.12, 4.6, 0.1), Vector3(L / 16.0, 2.9, back + 0.12), blue)
		brace.rotation.z = d * 0.62
	# Handrails up the stairs at each end.
	for s in [-1.0, 1.0]:
		var rail := p.add_box(holder, Vector3(0.06, 0.06, depth * 1.12), Vector3(s * (L * 0.5 + 0.05), 1.0 + 1.3, -depth * 0.5), blue)
		rail.rotation.x = 0.46
	# The roof: a shallow curve from front to back, with a fascia along the front.
	var segs := 6
	var front_z := 0.9
	var prev := Vector2(front_z, 5.9)
	for i in segs:
		var t := float(i + 1) / segs
		var zz := lerpf(front_z, back - 0.6, t)
		var yy := lerpf(5.9, 6.2, t) + 1.4 * sin(PI * t)
		var a := prev
		var b := Vector2(zz, yy)
		var seg := p.add_box(holder, Vector3(L + 1.4, 0.14, a.distance_to(b) + 0.05), Vector3(0, (a.y + b.y) * 0.5, (a.x + b.x) * 0.5), roof_mat)
		seg.rotation.x = atan2(a.y - b.y, b.x - a.x)
		prev = b
	p.add_box(holder, Vector3(L + 1.4, 0.8, 0.1), Vector3(0, 5.6, front_z + 0.02), roof_mat)
	# A rail along the front of the walkway.
	p.add_box(holder, Vector3(L + 2.0, 0.05, 0.05), Vector3(0, 1.05, 0.05), p.mat("rail_steel", Color(0.7, 0.71, 0.72), 0.4))


## The club's white flat-roofed buildings, sheds and containers by the near
## side towards the west end, and a hut by the track.
func _build_club(root: Node3D) -> void:
	var holder := Node3D.new()
	holder.name = "ClubBuildings"
	root.add_child(holder)
	var white: Material = p.mat("render_white", Color(0.9, 0.9, 0.87), 0.9)
	var grey: Material = p.mat("plant_grey", Color(0.45, 0.46, 0.47), 0.6)
	var glass: Material = p.mat("window", Color(0.12, 0.14, 0.17), 0.2)
	var red: Material = p.mat("door_red", Color(0.62, 0.1, 0.1), 0.6)
	# The pavilion: a big white block with plant on the roof.
	var pav := Vector3(-hl * 0.5, 0.0, hw + 21.0)
	p.add_box(holder, Vector3(17.0, 4.6, 12.0), pav + Vector3(0, 2.3, 0), white)
	p.add_box(holder, Vector3(17.4, 0.3, 12.4), pav + Vector3(0, 4.75, 0), grey)
	for i in 4:
		p.add_box(holder, Vector3(2.2, 1.0, 1.6), pav + Vector3(-5.5 + i * 3.6, 5.4, -1.0 + (i % 2) * 2.5), grey)
	for i in 5:
		p.add_box(holder, Vector3(1.8, 1.3, 0.1), pav + Vector3(-6.4 + i * 3.2, 2.6, -6.05), glass)
	# The changing block: smaller, with a red door.
	var blk := Vector3(-hl * 0.22, 0.0, hw + 18.5)
	p.add_box(holder, Vector3(10.0, 3.6, 7.0), blk + Vector3(0, 1.8, 0), white)
	p.add_box(holder, Vector3(10.3, 0.25, 7.3), blk + Vector3(0, 3.7, 0), grey)
	p.add_box(holder, Vector3(1.1, 2.1, 0.1), blk + Vector3(-2.0, 1.05, -3.55), red)
	p.add_box(holder, Vector3(2.4, 1.0, 0.1), blk + Vector3(2.0, 2.2, -3.55), glass)
	# Sheds and containers behind.
	var shed: Material = p.mat("shed_blue", Color(0.32, 0.38, 0.46), 0.7)
	var rust: Material = p.mat("container_rust", Color(0.45, 0.24, 0.16), 0.8)
	var blue: Material = p.mat("container_blue", Color(0.2, 0.42, 0.7), 0.6)
	p.add_box(holder, Vector3(12.0, 3.2, 6.0), Vector3(-hl * 0.42, 1.6, hw + 32.0), shed)
	p.add_box(holder, Vector3(6.0, 2.6, 2.4), Vector3(-hl * 0.27, 1.3, hw + 31.0), rust)
	p.add_box(holder, Vector3(6.0, 2.6, 2.4), Vector3(-hl * 0.27, 1.3, hw + 28.2), blue)
	# The groundsman's hut by the track, near the mound.
	p.add_box(holder, Vector3(3.2, 2.5, 2.2), Vector3(hl * 0.28, 1.25, hw + 10.5), white)


## The training pitch behind the conifers: level grass, white lines and a
## green ball-stop fence round it.
func _build_training(root: Node3D) -> void:
	var holder := Node3D.new()
	holder.name = "Training"
	root.add_child(holder)
	var line: Material = p.mat("court_line", Color(0.9, 0.9, 0.88), 0.8)
	var t := training.grow(-3.0)
	var mid := t.get_center()
	for z in [t.position.y, t.end.y]:
		var l := p.add_box(holder, Vector3(t.size.x, 0.03, 0.12), Vector3(mid.x, 0.02, z), line)
		l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for x in [t.position.x, mid.x, t.end.x]:
		var l := p.add_box(holder, Vector3(0.12, 0.03, t.size.y), Vector3(x, 0.02, mid.y), line)
		l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var a := training.position
	var b := training.end
	for e in [[a, Vector2(b.x, a.y)], [Vector2(b.x, a.y), b], [b, Vector2(a.x, b.y)], [Vector2(a.x, b.y), a]]:
		p.add_fence(root, e[0], e[1], 3.0, 3.0, Color(0.16, 0.3, 0.2), true, 0.22)


## Oban's houses: terraces behind the near side, villas along Mossfield
## Avenue past the west end, a few up by the crag, and the town beyond.
func _build_houses(root: Node3D, rng: RandomNumberGenerator) -> void:
	var holder := Node3D.new()
	holder.name = "Houses"
	root.add_child(holder)
	for row in 2:
		for i in 9:
			var q := Vector2(-hl - 20.0 + i * 15.0 + rng.randf_range(-1.5, 1.5), hw + 84.0 + row * 18.0)
			p.add_house(holder, rng, Vector3(q.x, p.height_m(q.x, q.y), q.y), PI * 0.5 + rng.randf_range(-0.05, 0.05))
	for i in 7:
		var q := Vector2(-hl - 92.0 + rng.randf_range(-3.0, 3.0), -hw - 40.0 + i * 20.0)
		p.add_house(holder, rng, Vector3(q.x, p.height_m(q.x, q.y), q.y), rng.randf_range(-0.1, 0.1))
	for q in [Vector2(-70.0, -hw - 88.0), Vector2(-40.0, -hw - 92.0), Vector2(hl + 70.0, -hw - 60.0), Vector2(hl + 95.0, -hw - 20.0),
			Vector2(hl + 70.0, hw + 70.0), Vector2(hl + 40.0, -hw - 95.0)]:
		p.add_house(holder, rng, Vector3(q.x, p.height_m(q.x, q.y), q.y), rng.randf_range(-0.4, 0.4))
	# The town: streets of houses running down to the bay.
	var rows: int = [4, 6, 9][p.scenery_detail]
	for row in rows:
		var yaw := rng.randf_range(-0.3, 0.3)
		for i in 16:
			if rng.randf() > 0.7:
				continue
			var q := Vector2(-hl - 160.0 - row * 34.0 - rng.randf_range(0.0, 8.0), -330.0 + i * 40.0 + rng.randf_range(-8.0, 8.0))
			p.add_house(holder, rng, Vector3(q.x, p.height_m(q.x, q.y), q.y), yaw + rng.randf_range(-0.1, 0.1))


func _build_cars(root: Node3D, rng: RandomNumberGenerator) -> void:
	var holder := Node3D.new()
	holder.name = "Cars"
	root.add_child(holder)
	for i in 4:
		var x := -hl - 22.0 - i * 9.0
		for side in [-1.0, 1.0]:
			p.park_row(holder, rng, Vector3(x, 0, side * 14.0), Vector3(x, 0, side * (hw - 4.0)), 0.0 if i % 2 == 0 else PI, 0.55)
	p.park_row(holder, rng, Vector3(-hl * 0.75, 0, hw + 12.0), Vector3(-hl * 0.6, 0, hw + 12.0), PI * 0.5, 0.6)
	p.park_row(holder, rng, Vector3(-hl * 0.12, 0, hw + 26.0), Vector3(-6.0, 0, hw + 26.0), -PI * 0.5, 0.5)
