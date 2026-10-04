extends RefCounted
## Skye Camanachd's pitch in Portree, laid out from aerial views, a terrain
## map and photos of the ground.
##
## The pitch sits on a shelf above the town, with moorland rising to the hills
## on the west. Near side (+Z): the white social club with its dark roof and
## blue sign, blue containers and picnic tables, a gravel track that runs on
## round the south-east end, the car park and turning circle, then the Gaelic
## school and its all-weather pitch. Far side (-Z): a steep heather bank with
## the ad boards on it and trees along the top. North-west end (+X): the
## wooded gully of the Lon na h-Atha, with glamping pods on the hillside
## beyond. Floodlight poles stand along both sides. Looking south-east (-X)
## the land falls to Portree Bay, with Ben Tianavaig's flat top across the
## water.

const WATER_LEVEL := -62.0
const BANK_HEIGHT := 9.0

var p: ShintyPitch
var hl: float
var hw: float
var gully: PackedVector2Array
var roads: Array[PackedVector2Array] = []
var club: Vector3      # clubhouse centre, on the ground
var turning: Vector2   # turning circle at the end of the access road


func _init(pitch: ShintyPitch) -> void:
	p = pitch
	hl = p.hl
	hw = p.hw
	club = Vector3(hl * 0.3, 0.0, hw + 16.5)
	turning = Vector2(hl * 0.62, hw + 60.0)
	# The burn comes down off the moor, past the north-west end, and on north
	# towards the road.
	gully = PackedVector2Array([Vector2(hl + 320.0, -hw - 320.0), Vector2(hl + 70.0, -hw - 45.0),
		Vector2(hl + 22.0, -hw + 4.0), Vector2(hl + 20.0, hw + 30.0), Vector2(hl + 55.0, hw + 150.0)])
	# The B885 above the ground, and Struan Road down past the school to it.
	roads.append(PackedVector2Array([Vector2(hl + 300.0, hw + 50.0), Vector2(hl + 90.0, hw + 112.0),
		Vector2(0.0, hw + 122.0), Vector2(-hl - 70.0, hw + 150.0), Vector2(-hl - 320.0, hw + 270.0)]))
	roads.append(PackedVector2Array([turning, Vector2(-15.0, hw + 95.0), Vector2(-25.0, hw + 122.0)]))
	# Access road from the turning circle down to the car park.
	roads.append(PackedVector2Array([turning, Vector2(hl * 0.55, hw + 34.0)]))


## The pre-match flight starts over the car park looking out at the bank and
## the moor, swings round past the gully and comes down in front of the bank to
## end looking across the pitch at the clubhouse.
func intro_flight() -> Dictionary:
	return {"from": 0.55, "to": -1.3, "radius": 50.0, "height": 22.0, "look": club + Vector3(0, 2.0, 0)}


func extra_cloud() -> float:
	return 0.3


func fog_density() -> float:
	return 0.00012


func water() -> Dictionary:
	return {"level": WATER_LEVEL, "color": Color(0.08, 0.14, 0.17), "roughness": 0.06, "wave_scale": 0.4}


func ground_look() -> Dictionary:
	return {
		"wear": 0.14,
		"stripe_width": 5.0,
		"stripe_strength": 0.05,
		"grass_color": Color(0.3, 0.47, 0.15),
		"rough_color": Color(0.46, 0.45, 0.27),    # tussocky grass
		"earth_color": Color(0.27, 0.24, 0.17),    # heather and dead bracken
		"gravel_color": Color(0.5, 0.5, 0.49),
		"sand_color": Color(0.45, 0.43, 0.4),
		"field_strength": 0.25,
		"field_start": 320.0,
	}


## Ad boards along the bank on the far side, a couple of metres up it, and
## the usual rows behind each hail.
func board_rows() -> Array:
	var z := -hw - 14.0
	return [[Vector2(-hl + 4.0, z), Vector2(hl - 4.0, z), 0],
		[Vector2(-hl - 4.6, -hw * 0.8), Vector2(-hl - 4.6, hw * 0.8), 3],
		[Vector2(hl + 4.6, -hw * 0.8), Vector2(hl + 4.6, hw * 0.8), 5]]


func height_m(x: float, z: float) -> float:
	var pos := Vector2(x, z)
	var n := p.noise.get_noise_2d(x, z)
	var west := (x - z) * 0.7071  # metres towards the hills
	var east := -west               # metres towards the bay
	# Far side: the bank, steep from 9 m out, along the whole pitch.
	var along := 1.0 - smoothstep(hl + 25.0, hl + 60.0, absf(x))
	var bank := BANK_HEIGHT * smoothstep(hw + 9.0, hw + 22.0, -z) * along
	# Moor rising to the hills in the west, ridged and uneven.
	var ridge := 1.0 - absf(p.noise.get_noise_2d(x * 0.05, z * 0.05))
	var moor := 200.0 * smoothstep(40.0, 1200.0, west) * (0.75 + 0.25 * ridge)
	moor += 6.0 * smoothstep(hw + 20.0, hw + 120.0, -z) * (1.0 + n)
	moor *= p.wildness(x, z, 6.0, 6.0)   # the park round the pitch stays flat
	var rough := p.noise.get_noise_2d(x * 0.25, z * 0.25) * 5.0 + n * 1.5
	var land := maxf(bank, moor) + rough * p.wildness(x, z, 14.0, 22.0)
	# The hillside past the north-west end, where the pods are.
	land += 22.0 * smoothstep(hl + 28.0, hl + 130.0, x) * (1.0 - smoothstep(hw + 20.0, hw + 90.0, z))
	# Down to the town and the bay to the east.
	land -= 58.0 * smoothstep(250.0, 1250.0, east) * p.wildness(x, z, 30.0, 40.0)
	land = lerpf(land, WATER_LEVEL - 8.0, smoothstep(1250.0, 1400.0, east))
	# Ben Tianavaig across the water: steep sides and a broad flat top.
	var ben := Vector2(-4300.0, 1900.0)
	var d := pos.distance_to(ben)
	var top := 380.0 + 25.0 * p.noise.get_noise_2d(x * 0.02, z * 0.02)
	land = maxf(land, WATER_LEVEL - 8.0 + (top - WATER_LEVEL) * smoothstep(1700.0, 1250.0, d))
	# The burn's gully past the north-west end.
	var g: float = p.dist_to_path(pos, gully)
	land = lerpf(land, land - 6.0, 1.0 - smoothstep(3.0, 10.0, g))
	return land


func ground_mask(x: float, z: float, h: float) -> Color:
	var c := Color(0, 0, 0, 0)
	var pos := Vector2(x, z)
	c.g = p.wildness(x, z, 6.0, 5.0)
	# Heather and bracken on the bank, the moor and the hills; green fields
	# towards the town.
	var west := (x - z) * 0.7071
	var moor := smoothstep(-40.0, 60.0, west) * p.wildness(x, z, 14.0, 12.0)
	c.r = maxf(moor, smoothstep(40.0, 120.0, h))
	c.r = maxf(c.r, smoothstep(hw + 13.0, hw + 22.0, -z) * (1.0 - smoothstep(hl + 25.0, hl + 60.0, absf(x))) * 0.8)
	# Gravel: the track along the near side and round the south-east end,
	# and the car park beside the clubhouse.
	if z > hw + 5.5 and z < hw + 8.5 and x > -hl - 8.5 and x < club.x:
		c.b = 1.0
	if x > -hl - 8.5 and x < -hl - 5.5 and z > -hw * 0.4 and z < hw + 8.5:
		c.b = 1.0
	if x > club.x + 14.0 and x < hl + 14.0 and z > hw + 9.0 and z < hw + 34.0:
		c.b = 1.0
	if pos.distance_to(turning) < 13.0:
		c.b = 1.0
	for road in roads:
		if p.dist_to_path(pos, road) < 3.2:
			c.b = 1.0
	if c.b > 0.0:
		c.r = 0.0
	return c


func build(root: Node3D, rng: RandomNumberGenerator) -> void:
	_build_trees(root, rng)
	_build_clubhouse(root, rng)
	_build_ground_furniture(root)
	_build_school(root)
	_build_pods(root, rng)
	_build_houses(root, rng)
	_build_cars(root, rng)
	var rough := func(x: float, z: float) -> float:
		var c := ground_mask(x, z, p.height_m(x, z))
		return c.g * (1.0 - c.b) * (1.0 - c.r)
	var heather := func(x: float, z: float) -> float:
		var c := ground_mask(x, z, p.height_m(x, z))
		return c.r * (1.0 - c.b)
	p.emit_tufts(root, rng, 2500, Rect2(-hl - 40.0, hw + 4.0, hl * 2.0 + 60.0, 10.0), rough, Color(0.4, 0.46, 0.22))
	p.emit_tufts(root, rng, 5000, Rect2(-hl - 30.0, -hw - 26.0, hl * 2.0 + 50.0, 16.0), heather, Color(0.4, 0.33, 0.22))


func _build_trees(root: Node3D, rng: RandomNumberGenerator) -> void:
	var near := ShintyPitch.TreeBatch.new()
	var far := ShintyPitch.TreeBatch.new()
	var detail: float = [0.5, 0.8, 1.0][p.scenery_detail]
	# Along the top of the bank: birch, rowan and a few spruce, thickest at the
	# south-east end.
	var x := -hl - 45.0
	while x < hl + 10.0:
		var pz := -hw - rng.randf_range(17.0, 30.0)
		var h: float = p.height_m(x, pz)
		var r := rng.randf()
		if r < 0.25:
			p.add_pine(near, rng, Vector3(x, h, pz))
		elif r < 0.55:
			p.add_birch(near, rng, Vector3(x, h, pz))
		elif r < 0.8 or x < 0.0:
			p.add_broadleaf(near, rng, Vector3(x, h, pz), rng.randf_range(0.6, 0.85))
		x += rng.randf_range(5.0, 9.0) / detail * (0.7 if x < 0.0 else 1.2)
	# Down the gully, both banks.
	for i in gully.size() - 1:
		var a: Vector2 = gully[i]
		var b: Vector2 = gully[i + 1]
		var steps := int(a.distance_to(b) / (6.0 / detail))
		for s in steps:
			var q := a.lerp(b, (s + rng.randf()) / float(steps))
			var side := (b - a).normalized().orthogonal() * rng.randf_range(-7.0, 7.0)
			q += side
			if absf(q.y) < 32.0 and q.x < hl + 45.0:
				continue  # keep the view down the pitch from behind the hail clear
			var h: float = p.height_m(q.x, q.y)
			if q.length() < 260.0:
				if rng.randf() < 0.3:
					p.add_pine(near, rng, Vector3(q.x, h, q.y))
				else:
					p.add_broadleaf(near, rng, Vector3(q.x, h, q.y), rng.randf_range(0.6, 0.9))
			else:
				p.add_woodland(far, rng, Vector3(q.x, h - 0.4, q.y), 0.5)
	# A few trees by the school and the road, and woods on the edge of town.
	for i in int(10 * detail):
		var q := Vector2(rng.randf_range(-hl - 30.0, hl * 0.4), hw + rng.randf_range(88.0, 110.0))
		p.add_broadleaf(near, rng, Vector3(q.x, p.height_m(q.x, q.y), q.y), rng.randf_range(0.6, 0.9))
	var spacing: float = [16.0, 11.0, 9.0][p.scenery_detail]
	var gz := hw + 130.0
	while gz < hw + 380.0:
		var gx := -hl - 380.0
		while gx < -hl - 40.0:
			if p.noise.get_noise_2d(gx * 0.4, gz * 0.4) > -0.05:
				var px := gx + rng.randf_range(-3.0, 3.0)
				var pz := gz + rng.randf_range(-3.0, 3.0)
				p.add_woodland(far, rng, Vector3(px, p.height_m(px, pz) - 0.4, pz), 0.4)
			gx += spacing
		gz += spacing
	p.emit_trees(root, near, 12, 7, 64, "TreesNear")
	p.emit_trees(root, far, 8, 5, 22, "Woodland")


## The social club, from photos of it: long and low, white harled walls under
## a broad dark slate hip roof with deep eaves, a dish on the roof, and a
## sheltered veranda along the pitch side with brick piers, glazed doors and
## picnic tables out front. A tall floodlight with two lamps stands by the
## west gable; blue containers and the car park lie past the east gable.
func _build_clubhouse(root: Node3D, rng: RandomNumberGenerator) -> void:
	var holder := Node3D.new()
	holder.name = "Clubhouse"
	holder.position = club
	root.add_child(holder)
	var harl: Material = p.mat("harl", Color(0.9, 0.89, 0.85), 0.95)
	var slate: Material = p.mat("club_slate", Color(0.15, 0.16, 0.19), 0.75)
	var brick: Material = p.mat("club_brick", Color(0.42, 0.25, 0.2), 0.9)
	var frame: Material = p.mat("club_frame", Color(0.2, 0.17, 0.15), 0.7)
	var glass: Material = p.mat("window", Color(0.12, 0.14, 0.17), 0.2)
	var shade: Material = p.mat("club_shade", Color(0.3, 0.29, 0.27), 0.95)
	var L := 22.0          # along the touchline
	var D := 12.0          # back from the pitch
	var WALL := 3.0
	var VERANDA := 2.2     # the pitch side is set back this far under the roof
	var front := -D * 0.5
	# Walls: the back block full depth, the front wall set back for the veranda.
	p.add_box(holder, Vector3(L, WALL, D - VERANDA), Vector3(0, WALL * 0.5, VERANDA * 0.5), harl)
	# The veranda: its floor, the ends closed in harl, a dark recess behind.
	p.add_box(holder, Vector3(L, 0.25, VERANDA), Vector3(0, 0.12, front + VERANDA * 0.5), shade)
	for sx in [-1.0, 1.0]:
		p.add_box(holder, Vector3(2.4, WALL, VERANDA), Vector3(sx * (L * 0.5 - 1.2), WALL * 0.5, front + VERANDA * 0.5), harl)
	var wall_z := front + VERANDA - 0.06
	p.add_box(holder, Vector3(L - 4.8, WALL, 0.1), Vector3(0, WALL * 0.5, wall_z), shade)
	# Glazed doors and windows along the recess, and brick piers at the front.
	for i in 6:
		var wx := -7.0 + i * 2.8
		var door := i == 1 or i == 4
		var hgt := 2.2 if door else 1.5
		var y := 1.1 if door else 1.65
		p.add_box(holder, Vector3(1.7, hgt + 0.15, 0.08), Vector3(wx, y, wall_z - 0.05), frame)
		p.add_box(holder, Vector3(1.45, hgt - 0.1, 0.1), Vector3(wx, y, wall_z - 0.07), glass)
	for i in 5:
		p.add_box(holder, Vector3(0.45, WALL, 0.45), Vector3(-7.6 + i * 3.8, WALL * 0.5, front + 0.3), brick)
	# A rail across the front of the veranda between the piers.
	p.add_box(holder, Vector3(15.2, 0.08, 0.08), Vector3(0, 0.95, front + 0.3), frame)
	# Windows in the gables and the back.
	for sx in [-1.0, 1.0]:
		p.add_box(holder, Vector3(0.1, 1.2, 1.6), Vector3(sx * (L * 0.5 + 0.03), 1.7, 2.2), glass)
	for i in 3:
		p.add_box(holder, Vector3(1.4, 1.1, 0.1), Vector3(-6.0 + i * 6.0, 1.7, D * 0.5 + 0.03), glass)
	# The roof: a full hip with deep eaves, and the soffit under them.
	var eave := 0.9
	var roof := _hip_roof(L + eave * 2.0, D + eave * 2.0, 3.6, slate)
	roof.position = Vector3(0, WALL, 0)
	holder.add_child(roof)
	p.add_box(holder, Vector3(L + eave * 2.0, 0.12, D + eave * 2.0), Vector3(0, WALL - 0.02, 0), shade)
	# The satellite dish up on the west hip.
	var white: Material = p.mat("sign_white", Color(0.95, 0.95, 0.95), 0.6)
	var dish := p.add_cyl(holder, Vector3(-L * 0.5 + 3.2, WALL + 2.0, front + 3.8), 0.45, 0.15, white)
	dish.rotation = Vector3(-0.9, 0.5, 0)
	# The club sign on the front fascia.
	p.add_box(holder, Vector3(3.2, 0.7, 0.08), Vector3(0, WALL - 0.45, front - eave + 0.02), p.mat("skye_blue", Color(0.25, 0.55, 0.85), 0.5))
	# The floodlight by the west gable: a tall pole with two lamps on a bar.
	var grey := p.mat("lamp_post", Color(0.55, 0.57, 0.58), 0.5)
	var pole_at := Vector3(-L * 0.5 - 2.5, 0, front + 2.0)
	var pole := p.add_cyl(holder, pole_at + Vector3(0, 7.5, 0), 0.14, 15.0, grey)
	pole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	p.add_box(holder, Vector3(1.4, 0.12, 0.12), pole_at + Vector3(0, 15.0, -0.2), grey)
	for sx in [-1.0, 1.0]:
		p.add_box(holder, Vector3(0.55, 0.45, 0.3), pole_at + Vector3(sx * 0.55, 14.8, -0.35), grey)
	# Picnic tables in front of the veranda.
	var timber: Material = p.mat("timber", Color(0.42, 0.3, 0.2), 0.9)
	for i in 4:
		var t := Vector3(-5.5 + i * 3.8 + rng.randf_range(-0.4, 0.4), 0, front - 2.0)
		p.add_box(holder, Vector3(1.8, 0.08, 0.8), t + Vector3(0, 0.75, 0), timber)
		for s in [-1.0, 1.0]:
			p.add_box(holder, Vector3(1.8, 0.06, 0.3), t + Vector3(0, 0.45, s * 0.65), timber)
	# Blue containers past the east gable.
	var blue: Material = p.mat("container_blue", Color(0.2, 0.42, 0.7), 0.6)
	p.add_box(holder, Vector3(6.0, 2.6, 2.4), Vector3(L * 0.5 + 6.0, 1.3, -2.0), blue)
	p.add_box(holder, Vector3(6.0, 2.6, 2.4), Vector3(L * 0.5 + 6.0, 1.3, 0.6), blue)
	p.add_fence(root, Vector2(club.x - L * 0.5 - 8.0, club.z - 4.5), Vector2(club.x - L * 0.5 - 3.5, club.z - 4.5),
		1.1, 2.2, Color(0.6, 0.62, 0.64), true, 0.5)


## A hipped roof `w` long (X) and `d` deep (Z), its eaves at y = 0 and every
## slope pitched alike, so the ridge runs `w - d` long.
func _hip_roof(w: float, d: float, h: float, m: Material) -> MeshInstance3D:
	var a := w * 0.5
	var b := d * 0.5
	var r := maxf(a - b, 0.0)
	var e := [Vector3(-a, 0, -b), Vector3(a, 0, -b), Vector3(a, 0, b), Vector3(-a, 0, b)]
	var ridge := [Vector3(-r, h, 0), Vector3(r, h, 0)]
	var faces := [
		[e[0], ridge[0], ridge[1], e[1]],   # pitch side
		[e[2], ridge[1], ridge[0], e[3]],   # back
		[e[1], ridge[1], e[2]],             # east hip
		[e[3], ridge[0], e[0]],             # west hip
	]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for f in faces:
		var n: Vector3 = (f[1] - f[0]).cross(f[2] - f[0]).normalized()
		var tris := [[f[0], f[1], f[2]]]
		if f.size() == 4:
			tris.append([f[0], f[2], f[3]])
		for tri in tris:
			for v in tri:
				st.set_normal(n)
				st.set_uv(Vector2(v.x, v.z) * 0.25)
				st.add_vertex(v)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = m
	return mi


func _build_ground_furniture(root: Node3D) -> void:
	var holder := Node3D.new()
	holder.name = "Ground"
	root.add_child(holder)
	# Floodlight poles along both sides.
	var grey := p.mat("lamp_post", Color(0.55, 0.57, 0.58), 0.5)
	for side in [-1.0, 1.0]:
		var pz := (hw + 4.5) if side > 0.0 else -(hw + 8.5)
		for px in [-hl * 0.75, -hl * 0.25, hl * 0.25, hl * 0.75]:
			if side > 0.0 and absf(px - club.x) < 15.0:
				continue
			var base: float = p.height_m(px, pz)
			var pole := p.add_cyl(holder, Vector3(px, base + 7.5, pz), 0.12, 15.0, grey)
			pole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			p.add_box(holder, Vector3(1.6, 0.5, 0.5), Vector3(px, base + 15.0, pz - side * 0.3), grey)
	# The all-weather pitch by the school, fenced.
	var astro := Rect2(-hl * 0.15, hw + 34.0, 38.0, 22.0)
	var a0 := astro.position
	var a1 := astro.end
	p.add_box(holder, Vector3(astro.size.x, 0.06, astro.size.y), Vector3(a0.x + astro.size.x * 0.5, 0.03, a0.y + astro.size.y * 0.5),
		p.mat("astro", Color(0.22, 0.42, 0.24), 0.9))
	var lines: Material = p.mat("court_line", Color(0.9, 0.9, 0.88), 0.8)
	p.add_box(holder, Vector3(0.1, 0.07, astro.size.y - 2.0), Vector3(a0.x + astro.size.x * 0.5, 0.04, a0.y + astro.size.y * 0.5), lines)
	for edge in [[a0, Vector2(a1.x, a0.y)], [Vector2(a1.x, a0.y), a1], [a1, Vector2(a0.x, a1.y)], [Vector2(a0.x, a1.y), a0]]:
		p.add_fence(root, edge[0], edge[1], 3.5, 3.0, Color(0.2, 0.25, 0.22), true, 0.25)
	# The middle of the turning circle.
	var mid := p.add_cyl(holder, Vector3(turning.x, p.height_m(turning.x, turning.y) + 0.06, turning.y), 5.0, 0.15,
		p.mat("kerb", Color(0.78, 0.77, 0.74), 0.9))
	mid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The pizza van's hut and a shed beside the car park.
	p.add_box(holder, Vector3(4.5, 2.6, 2.4), Vector3(hl * 0.78, 1.3, hw + 31.0), p.mat("hut_dark", Color(0.2, 0.2, 0.22), 0.7))
	p.add_box(holder, Vector3(3.0, 2.4, 2.4), Vector3(hl * 0.78 + 5.0, 1.2, hw + 31.5), p.mat("timber", Color(0.42, 0.3, 0.2), 0.9))


## Bun-sgoil Ghàidhlig Phort Rìgh: a long flat-roofed school with solar panels.
func _build_school(root: Node3D) -> void:
	var holder := Node3D.new()
	holder.name = "School"
	var base := Vector2(-hl * 0.55, hw + 78.0)
	holder.position = Vector3(base.x, p.height_m(base.x, base.y), base.y)
	holder.rotation.y = -0.25
	root.add_child(holder)
	var wall: Material = p.mat("school_wall", Color(0.86, 0.86, 0.84), 0.9)
	var clad: Material = p.mat("school_clad", Color(0.55, 0.57, 0.6), 0.7)
	p.add_box(holder, Vector3(64.0, 8.0, 20.0), Vector3(0, 3.0, 0), wall)
	p.add_box(holder, Vector3(26.0, 6.0, 18.0), Vector3(-20.0, 2.0, -16.0), clad)
	p.add_box(holder, Vector3(64.6, 0.4, 20.6), Vector3(0, 7.2, 0), clad)
	var panel: Material = p.mat("solar", Color(0.1, 0.12, 0.18), 0.3)
	for i in 6:
		p.add_box(holder, Vector3(8.0, 0.15, 5.0), Vector3(-24.0 + i * 9.5, 7.6, 3.0), panel)
	var glass: Material = p.mat("window", Color(0.12, 0.14, 0.17), 0.2)
	for i in 12:
		p.add_box(holder, Vector3(3.0, 1.6, 0.1), Vector3(-27.0 + i * 5.0, 2.8, -10.06), glass)


## Glamping pods: little arched huts in rows on the hillside past the gully.
func _build_pods(root: Node3D, rng: RandomNumberGenerator) -> void:
	var holder := Node3D.new()
	holder.name = "Pods"
	root.add_child(holder)
	var shell: Material = p.mat("pod", Color(0.3, 0.33, 0.3), 0.85)
	var end_wall: Material = p.mat("pod_end", Color(0.45, 0.36, 0.26), 0.9)
	for i in 9:
		var q := Vector2(hl + 55.0 + (i % 3) * 16.0 + rng.randf_range(-2.0, 2.0), -hw * 0.6 + floorf(i / 3.0) * 18.0 + rng.randf_range(-2.0, 2.0))
		var pod := Node3D.new()
		pod.position = Vector3(q.x, p.height_m(q.x, q.y) - 0.6, q.y)
		pod.rotation.y = 0.5 + rng.randf_range(-0.15, 0.15)
		holder.add_child(pod)
		var arch := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 1.6
		cm.bottom_radius = 1.6
		cm.height = 4.6
		cm.radial_segments = 12
		arch.mesh = cm
		arch.material_override = shell
		arch.rotation.x = PI * 0.5
		pod.add_child(arch)
		p.add_box(pod, Vector3(2.6, 2.0, 0.1), Vector3(0, 0.7, 2.32), end_wall)
	# The site's hut and the Am Braigh restaurant up by the road.
	p.add_house(holder, rng, Vector3(hl + 40.0, p.height_m(hl + 40.0, hw * 0.9), hw * 0.9), 0.4)
	var braigh := Vector2(hl + 85.0, hw + 62.0)
	var b := Node3D.new()
	b.position = Vector3(braigh.x, p.height_m(braigh.x, braigh.y), braigh.y)
	b.rotation.y = 0.8
	holder.add_child(b)
	p.add_box(b, Vector3(9.0, 5.0, 26.0), Vector3(0, 2.0, 0), p.mat("harl", Color(0.93, 0.92, 0.88), 0.95))
	var r: MeshInstance3D = p.add_roof(b, Vector3(9.6, 2.6, 26.4), Vector3(0, 5.8, 0), p.mat("slate", Color(0.2, 0.21, 0.23), 0.8))
	r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


## Portree's houses on the slope down to the bay, and a few by the road.
func _build_houses(root: Node3D, rng: RandomNumberGenerator) -> void:
	var holder := Node3D.new()
	holder.name = "Houses"
	root.add_child(holder)
	var rows: int = [3, 5, 7][p.scenery_detail]
	for row in rows:
		for i in 8:
			if rng.randf() > 0.8:
				continue
			var q := Vector2(-hl - 40.0 - i * 26.0 - row * 12.0, hw + 150.0 + row * 34.0 + i * 8.0)
			q += Vector2(rng.randf_range(-6.0, 6.0), rng.randf_range(-6.0, 6.0))
			p.add_house(holder, rng, Vector3(q.x, p.height_m(q.x, q.y), q.y), 0.5 + rng.randf_range(-0.3, 0.3))
	for q in [Vector2(-hl * 0.2, hw + 140.0), Vector2(hl * 0.3, hw + 135.0), Vector2(-hl - 10.0, hw + 128.0)]:
		p.add_house(holder, rng, Vector3(q.x, p.height_m(q.x, q.y), q.y), 0.3)


func _build_cars(root: Node3D, rng: RandomNumberGenerator) -> void:
	var holder := Node3D.new()
	holder.name = "Cars"
	root.add_child(holder)
	p.park_row(holder, rng, Vector3(club.x + 26.0, 0, hw + 14.0), Vector3(hl + 10.0, 0, hw + 14.0), PI * 0.5, 0.7)
	p.park_row(holder, rng, Vector3(club.x + 26.0, 0, hw + 27.0), Vector3(hl + 8.0, 0, hw + 27.0), -PI * 0.5, 0.5)
	p.park_row(holder, rng, Vector3(-hl * 0.6, 0, hw + 10.0), Vector3(club.x - 16.0, 0, hw + 10.0), -PI * 0.5, 0.25)
