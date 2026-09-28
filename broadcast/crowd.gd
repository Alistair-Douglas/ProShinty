class_name ShintyCrowd
extends Node3D
## Spectators standing round the pitch: along both touchlines behind the ad
## boards and, fewer, behind each hail. Most wear one team's colours; there
## are children, and wheelchair users along the front. Every spectator is an
## instance of one of two low-poly figures (about 200 triangles), drawn as a
## MultiMesh per side of the pitch, so the whole crowd costs a handful of draw
## calls and no shadows. They sway about, and when a team scores its
## supporters cheer with their arms up (cheer()).
##
## Built in metres round the pitch centre, like ShintyPitch's scenery, and
## scaled to the view's units with `unit_scale`. Spectators only go where the
## ground is fairly flat and dry, and stay clear of a few buildings pitchside.

const Shader_ := preload("res://broadcast/crowd.gdshader")

## Spectators per metre of touchline at each graphics setting (Low, Medium,
## High). A club game draws a few hundred, so this stays modest.
const DENSITY := [0.35, 0.6, 0.9]
## Rows behind the far touchline (behind the boards), the near touchline (clear
## of the low replay camera) and the goal lines, in metres from the line.
const FAR_ROWS := [5.3, 6.2, 7.1]
const NEAR_ROWS := [7.6, 8.5]
const END_ROWS := [5.6, 6.5]

## Things standing where spectators would, per ShintyPitch.Venue: Rect2s in
## metres (x along the pitch, y across) measured from the centre spot, with
## the pitch's half length and half width added by _keep_clear().
const KEEP_CLEAR := {
	1: [  # Kingussie: dugouts, portakabin, container, timekeeper's box
		[Vector2(-12.0, -7.0), Vector2(24.0, 3.2)],
		[Vector2(16.0, -9.8), Vector2(8.0, 3.6)],
		[Vector2(-22.5, -10.2), Vector2(7.0, 3.4)],
		[Vector2(-2.8, 4.2), Vector2(3.6, 2.6)],
	],
}

## Most of the crowd follows one of the two teams and wears its colours
## (jacket in the main colour, scarf or hat in the second); the rest are
## neutrals in everyday outdoor clothes.
const HOME_SHARE := 0.55
const AWAY_SHARE := 0.3
## Of the front row, how many watch from a wheelchair; of everyone else, how
## many are children.
const WHEELCHAIR_SHARE := 0.12
const CHILD_SHARE := 0.14
const OUTDOOR := [Color(0.13, 0.2, 0.35), Color(0.15, 0.3, 0.2), Color(0.3, 0.3, 0.32), Color(0.08, 0.08, 0.09),
	Color(0.45, 0.35, 0.25), Color(0.6, 0.6, 0.62), Color(0.2, 0.45, 0.6), Color(0.35, 0.18, 0.4)]

var unit_scale := 1.0
var material: ShaderMaterial
var count := 0
var _cheer := [0.0, 0.0]


## Fills the ground round `pitch` with spectators. `colors` is the match's
## [[home primary, home secondary], [away primary, away secondary]];
## `quality` is the graphics setting, 0 Low to 2 High.
func build(pitch: ShintyPitch, colors: Array, quality := 1, seed := 1877) -> void:
	for c in get_children():
		c.queue_free()
	count = 0
	material = ShaderMaterial.new()
	material.shader = Shader_
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var hl := pitch.hl
	var hw := pitch.hw
	var density: float = DENSITY[clampi(quality, 0, 2)]
	var clear := _keep_clear(int(pitch.venue), hl, hw)
	material.set_shader_parameter("home_second", colors[0][1])
	material.set_shader_parameter("away_second", colors[1][1])
	var meshes := [_standing_mesh(), _wheelchair_mesh()]
	var groups := [
		["Far", _line_spots(rng, pitch, Vector2(-hl + 2.0, 0), Vector2(hl - 2.0, 0), -hw, -1.0, FAR_ROWS, density, clear)],
		["Near", _line_spots(rng, pitch, Vector2(-hl + 2.0, 0), Vector2(hl - 2.0, 0), hw, 1.0, NEAR_ROWS, density, clear)],
		["West", _end_spots(rng, pitch, -hl, -1.0, density * 0.5, clear)],
		["East", _end_spots(rng, pitch, hl, 1.0, density * 0.5, clear)],
	]
	for g in groups:
		# Split each side by figure: standing (adults and children) or wheelchair.
		var by_kind := [[], []]
		for sp in g[1]:
			var chair: bool = sp[2] and rng.randf() < WHEELCHAIR_SHARE
			by_kind[1 if chair else 0].append(sp)
		for kind in 2:
			var spots: Array = by_kind[kind]
			if spots.is_empty():
				continue
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.use_custom_data = true
			mm.mesh = meshes[kind]
			mm.instance_count = spots.size()
			for i in spots.size():
				_fill(mm, i, spots[i], kind == 1, colors, rng)
			var mi := MultiMeshInstance3D.new()
			mi.name = g[0] + ("Wheelchairs" if kind == 1 else "")
			mi.multimesh = mm
			mi.material_override = material
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.scale = Vector3.ONE * unit_scale
			add_child(mi)
			count += spots.size()


## One spectator: where they stand, how big they are and what they wear.
func _fill(mm: MultiMesh, i: int, spot: Array, chair: bool, colors: Array, rng: RandomNumberGenerator) -> void:
	var pos: Vector3 = spot[0]
	var face: Vector3 = spot[1]
	var yaw := atan2(face.x, face.z) + rng.randf_range(-0.35, 0.35) * (0.3 if chair else 1.0)
	var size := rng.randf_range(0.92, 1.07)
	if not chair and rng.randf() < CHILD_SHARE:
		size = rng.randf_range(0.58, 0.75)
	var b := Basis(Vector3.UP, yaw).scaled(Vector3(size * rng.randf_range(0.92, 1.1), size, size))
	mm.set_instance_transform(i, Transform3D(b, pos))
	var r := rng.randf()
	var side := 0
	var jacket: Color = OUTDOOR[rng.randi() % OUTDOOR.size()]
	if r < HOME_SHARE:
		side = 1
		jacket = colors[0][0] if rng.randf() < 0.85 else colors[0][1]
	elif r < HOME_SHARE + AWAY_SHARE:
		side = 2
		jacket = colors[1][0] if rng.randf() < 0.85 else colors[1][1]
	jacket = jacket.darkened(rng.randf_range(0.0, 0.2))
	mm.set_instance_color(i, jacket)
	# Hair, or (index 6) a hat in the team's second colour.
	var hat := 6 if rng.randf() < 0.3 else rng.randi_range(0, 5)
	mm.set_instance_custom_data(i, Color(rng.randi_range(0, 5), rng.randi_range(0, 4), hat,
		side + rng.randf_range(0.0, 0.99)))


## Supporters of `team` (0 home, 1 away) celebrate for a few seconds.
func cheer(team: int, seconds := 5.0) -> void:
	_cheer[team] = seconds


func _process(delta: float) -> void:
	if material == null:
		return
	for t in 2:
		_cheer[t] = maxf(0.0, _cheer[t] - delta)
	# Ease in over half a second and out over the last second.
	material.set_shader_parameter("cheer_home", minf(1.0, _cheer[0]))
	material.set_shader_parameter("cheer_away", minf(1.0, _cheer[1]))


## Spectators in rows along a touchline at z = `line_z` (metres), `out` the
## direction away from the pitch (-1 far, +1 near). Returns [position, facing,
## front row].
func _line_spots(rng: RandomNumberGenerator, pitch: ShintyPitch, a: Vector2, b: Vector2, line_z: float,
		out: float, rows: Array, density: float, clear: Array) -> Array:
	var spots := []
	for row in rows.size():
		var z: float = line_z + out * rows[row]
		# Thinner at the back and towards the corners; bunched in groups.
		var x := a.x
		while x < b.x:
			x += 1.0 / density * rng.randf_range(0.6, 1.4) * (1.0 + row * 0.6)
			var group := pitch.noise.get_noise_2d(x * 3.0, z * 3.0 + 50.0)
			var corner := 1.0 - smoothstep(pitch.hl * 0.55, pitch.hl, absf(x)) * 0.6
			if rng.randf() > (0.55 + group) * corner:
				continue
			var p := Vector2(x, z + rng.randf_range(-0.35, 0.35))
			if _ok(pitch, p, clear):
				spots.append([Vector3(p.x, pitch.height_m(p.x, p.y), p.y), Vector3(-p.x * 0.15, 0, -out * 30.0).normalized(), row == 0])
	return spots


## Spectators behind the hail at x = `line_x`, leaving the middle clear for
## the judge's view and the camera behind the goal.
func _end_spots(rng: RandomNumberGenerator, pitch: ShintyPitch, line_x: float, out: float, density: float, clear: Array) -> Array:
	var spots := []
	for row in END_ROWS.size():
		var x: float = line_x + out * END_ROWS[row]
		var z := -pitch.hw * 0.75
		while z < pitch.hw * 0.75:
			z += 1.0 / density * rng.randf_range(0.6, 1.4)
			if absf(z) < 7.0:
				continue
			var group := pitch.noise.get_noise_2d(x * 3.0 + 90.0, z * 3.0)
			if rng.randf() > 0.5 + group:
				continue
			var p := Vector2(x + rng.randf_range(-0.3, 0.3), z)
			if _ok(pitch, p, clear):
				spots.append([Vector3(p.x, pitch.height_m(p.x, p.y), p.y), Vector3(-out, 0, -p.y * 0.02).normalized(), row == 0])
	return spots


## Somewhere a spectator can stand: fairly flat, above the water, and clear of
## pitchside buildings.
func _ok(pitch: ShintyPitch, p: Vector2, clear: Array) -> bool:
	for r in clear:
		if (r as Rect2).has_point(p):
			return false
	var h := pitch.height_m(p.x, p.y)
	if h < -0.5 or h > 3.0:
		return false
	var dx := absf(pitch.height_m(p.x + 0.8, p.y) - pitch.height_m(p.x - 0.8, p.y))
	var dz := absf(pitch.height_m(p.x, p.y + 0.8) - pitch.height_m(p.x, p.y - 0.8))
	return maxf(dx, dz) < 0.9


static func _keep_clear(venue: int, hl: float, hw: float) -> Array:
	var out := []
	for r in KEEP_CLEAR.get(venue, []):
		var pos: Vector2 = r[0]
		# The listed y is measured from the touchline on that side.
		pos.y += -hw if pos.y < 0.0 else hw
		out.append(Rect2(pos, r[1]))
	return out


## A spectator 1.75 m tall standing at the origin facing +Z. See
## crowd.gdshader for what the vertex colour, UV and UV2 hold.
static func _standing_mesh() -> ArrayMesh:
	var st := _begin()
	var sh := Vector2(0.28, 1.43)
	_box(st, Vector3(0, 0.44, 0), Vector3(0.34, 0.88, 0.22), 1.0)                 # legs
	_box(st, Vector3(0, 1.17, 0), Vector3(0.44, 0.6, 0.27), 0.0)                  # body
	for s in [-1.0, 1.0]:
		_box(st, Vector3(s * 0.28, 1.16, 0), Vector3(0.1, 0.56, 0.12), 0.0, s, sh)  # arm
		_box(st, Vector3(s * 0.28, 0.84, 0.01), Vector3(0.08, 0.1, 0.09), 2.0, s, sh)
	_box(st, Vector3(0, 1.45, 0.0), Vector3(0.26, 0.09, 0.3), 5.0)                # scarf
	_box(st, Vector3(0, 1.575, 0.01), Vector3(0.19, 0.23, 0.21), 2.0)             # head
	_box(st, Vector3(0, 1.71, -0.01), Vector3(0.21, 0.07, 0.23), 3.0)             # hair or hat
	return st.commit()


## A spectator in a wheelchair at the origin facing +Z: a seated figure, the
## seat and backrest, footplate and two big wheels. They don't jump.
static func _wheelchair_mesh() -> ArrayMesh:
	var st := _begin()
	st.set_color(Color(1, 1, 1, 0))   # alpha 0: no jumping
	var sh := Vector2(0.25, 1.05)
	_box(st, Vector3(0, 0.46, -0.04), Vector3(0.44, 0.05, 0.44), 4.0)             # seat
	_box(st, Vector3(0, 0.74, -0.25), Vector3(0.42, 0.5, 0.04), 4.0)              # backrest
	_box(st, Vector3(0, 0.1, 0.33), Vector3(0.3, 0.03, 0.14), 4.0)                # footplate
	for s in [-1.0, 1.0]:
		_wheel(st, Vector3(s * 0.27, 0.3, -0.08), 0.3, 0.035)
		_box(st, Vector3(s * 0.15, 0.3, 0.24), Vector3(0.03, 0.4, 0.03), 4.0)     # front frame
	_box(st, Vector3(0, 0.55, 0.1), Vector3(0.34, 0.16, 0.44), 1.0)               # thighs
	_box(st, Vector3(0, 0.3, 0.3), Vector3(0.3, 0.44, 0.14), 1.0)                 # shins
	_box(st, Vector3(0, 0.8, -0.08), Vector3(0.42, 0.56, 0.26), 0.0)              # body
	for s in [-1.0, 1.0]:
		_box(st, Vector3(s * 0.26, 0.8, -0.05), Vector3(0.1, 0.5, 0.12), 0.0, s, sh)
		_box(st, Vector3(s * 0.26, 0.51, -0.04), Vector3(0.08, 0.1, 0.09), 2.0, s, sh)
	_box(st, Vector3(0, 1.08, -0.08), Vector3(0.26, 0.09, 0.3), 5.0)
	_box(st, Vector3(0, 1.2, -0.07), Vector3(0.19, 0.23, 0.21), 2.0)
	_box(st, Vector3(0, 1.335, -0.09), Vector3(0.21, 0.07, 0.23), 3.0)
	return st.commit()


static func _begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_color(Color.WHITE)
	return st


## A box. `part` goes in UV.x; arm vertices carry the arm (-1 left, +1 right)
## in UV.y and the shoulder they swing about (x, y) in UV2.
static func _box(st: SurfaceTool, c: Vector3, size: Vector3, part: float, arm := 0.0, shoulder := Vector2.ZERO) -> void:
	var h := size * 0.5
	var faces := [
		[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)],
		[Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0)],
		[Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)],
		[Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)],
		[Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, -1)],
		[Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)],
	]
	st.set_uv(Vector2(part, arm))
	st.set_uv2(shoulder)
	for f in faces:
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var corners := []
		for k in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			corners.append(c + (n + u * k.x + v * k.y) * h)
		st.set_normal(n)
		for i in [0, 2, 1, 0, 3, 2]:
			st.add_vertex(corners[i])


## A wheel on the X axis: an eight-sided disc, `width` thick.
static func _wheel(st: SurfaceTool, c: Vector3, radius: float, width: float) -> void:
	st.set_uv(Vector2(4.0, 0.0))
	st.set_uv2(Vector2.ZERO)
	var n := 8
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var p0 := Vector3(0, cos(a0), sin(a0)) * radius
		var p1 := Vector3(0, cos(a1), sin(a1)) * radius
		for s in [-1.0, 1.0]:
			var off := Vector3(s * width * 0.5, 0, 0)
			st.set_normal(Vector3(s, 0, 0))
			# Clockwise seen from outside, so each side faces outwards.
			if s > 0.0:
				for q in [c + off, c + off + p1, c + off + p0]:
					st.add_vertex(q)
			else:
				for q in [c + off, c + off + p0, c + off + p1]:
					st.add_vertex(q)
		# Tyre tread.
		var mid := ((p0 + p1) * 0.5).normalized()
		st.set_normal(mid)
		var a := c + p0 + Vector3(width * 0.5, 0, 0)
		var b := c + p1 + Vector3(width * 0.5, 0, 0)
		var d := c + p1 - Vector3(width * 0.5, 0, 0)
		var e := c + p0 - Vector3(width * 0.5, 0, 0)
		for q in [a, b, d, a, d, e]:
			st.add_vertex(q)
