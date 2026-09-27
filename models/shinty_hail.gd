@tool
class_name ShintyHailModel
extends Node3D
## A shinty hail (goal): two posts 12 ft apart, a crossbar 10 ft up, a net
## frame and a net that ripples when the ball hits it. It also provides the
## collision maths for ShintyBallPhysics: posts and crossbar rebound the ball,
## the net swallows it, and a goal is reported when the whole ball crosses the
## line between the posts and under the bar.
##
## Local space, in metres: the goal line runs along X through the origin, the
## pitch is in front (-Z) and the net is behind (+Z). Rotate the node so -Z
## points up the pitch.

signal goal_scored(position: Vector3)

@export var width := 3.66:          ## between the inside of the posts (12 ft)
	set(v): width = v; _queue_build()
@export var height := 3.05:         ## ground to underside of the crossbar (10 ft)
	set(v): height = v; _queue_build()
@export var post_radius := 0.05:
	set(v): post_radius = v; _queue_build()
@export var depth_top := 0.9:       ## how far the net runs back at the top
	set(v): depth_top = v; _queue_build()
@export var depth_bottom := 1.8:    ## and at the bottom
	set(v): depth_bottom = v; _queue_build()
@export var post_color := Color("f6f6f2"):
	set(v): post_color = v; _queue_build()
@export var net_color := Color(1, 1, 1, 0.9):
	set(v): net_color = v; _queue_build()

const POST_RESTITUTION := 0.55
const FRAME_RESTITUTION := 0.3
const NET_DAMPING := 0.12

## Set this to collide in a coordinate space other than the scene's (for
## example when the hail is not in the tree, as ShintyMatchAdapter does).
var physics_transform = null

var _net_mat: ShaderMaterial
var _ripple_age := 10.0
var _built := false

const NET_SHADER := """
shader_type spatial;
render_mode cull_disabled, blend_mix, depth_draw_opaque, unshaded;
uniform vec4 net_color : source_color = vec4(1.0);
uniform float cell = 0.1;
uniform float thickness = 0.1;
uniform vec3 impact = vec3(0.0, -100.0, 0.0);
uniform vec3 push = vec3(0.0, 0.0, 1.0);
uniform float age = 10.0;
uniform float strength = 0.0;

void vertex() {
	float d = distance(VERTEX, impact);
	float w = strength * exp(-d * d * 2.0) * exp(-age * 3.5) * cos(age * 18.0);
	VERTEX += push * w;
}

void fragment() {
	vec2 uv = UV / cell;
	vec2 f = abs(fract(uv) - 0.5);
	vec2 fw = fwidth(uv);
	float edge = 0.5 - thickness;
	vec2 l = smoothstep(vec2(edge) - fw, vec2(edge) + fw, f);
	float a = max(l.x, l.y);
	float haze = clamp(max(fw.x, fw.y) * 1.5, 0.0, 1.0);
	a = mix(a, 0.3, haze);
	ALBEDO = net_color.rgb;
	ALPHA = a * net_color.a;
}
"""


func _ready() -> void:
	add_to_group("shinty_hail")
	_build()


func _process(delta: float) -> void:
	if not _built:
		_build()
	if _ripple_age < 5.0:
		_ripple_age += delta
		_net_mat.set_shader_parameter("age", _ripple_age)


## Back of the net (local z) at a given height.
func back_z(y: float) -> float:
	return lerpf(depth_bottom, depth_top, clampf(y / height, 0.0, 1.0))


## Collide a ShintyBallPhysics with this hail. `prev` is the ball's world
## position before this sub-step. Appends post/net/goal events.
func collide_ball(ball: ShintyBallPhysics, prev: Vector3, events: Array, dt: float = 1.0 / 60.0) -> void:
	var xf: Transform3D = physics_transform if physics_transform != null else global_transform
	var inv := xf.affine_inverse()
	var p: Vector3 = inv * ball.position
	var pp: Vector3 = inv * prev
	var r := ShintyBallPhysics.RADIUS
	# Quick reject: nowhere near this hail.
	if p.z < -1.0 or p.z > depth_bottom + 1.0 or absf(p.x) > width / 2.0 + 1.0 or p.y > height + 1.0:
		return
	var v: Vector3 = inv.basis * ball.velocity
	var half := width / 2.0
	var pc := half + post_radius
	var bar_y := height + post_radius

	# Goal: the whole ball over the line, between the posts, under the bar.
	if ball.goal_armed and pp.z < r and p.z >= r:
		var t := (r - pp.z) / maxf(0.0001, p.z - pp.z)
		var cross := pp.lerp(p, t)
		if absf(cross.x) < half and cross.y < height:
			ball.goal_armed = false
			events.append({"type": "goal", "position": ball.position, "hail": self})
			goal_scored.emit(ball.position)

	# Posts and crossbar (capsules), then the frame tubes behind.
	var hit := false
	var segs := [
		[Vector3(-pc, 0, 0), Vector3(-pc, bar_y + post_radius, 0), post_radius, POST_RESTITUTION],
		[Vector3(pc, 0, 0), Vector3(pc, bar_y + post_radius, 0), post_radius, POST_RESTITUTION],
		[Vector3(-pc, bar_y, 0), Vector3(pc, bar_y, 0), post_radius, POST_RESTITUTION],
	]
	for s in segs:
		var res := _collide_segment(p, v, s[0], s[1], s[2] + r, s[3])
		if res.size() > 0:
			p = res[0]
			v = res[1]
			if s[3] == POST_RESTITUTION and res[2] > 1.0:
				events.append({"type": "post", "position": xf * p, "speed": res[2]})
			hit = true

	# Net: a closed box behind the line that swallows the ball from either side.
	var inside := _inside_net(p)
	var was_inside := _inside_net(pp)
	if inside and not was_inside:
		var entered_front := pp.z < 0.0 and absf(pp.x) < half and pp.y < height
		if not entered_front:
			# Came through the netting from outside: bounce weakly back out.
			p = pp
			v = -v * NET_DAMPING
			_ripple(p, -v)
			events.append({"type": "net", "position": xf * p})
			hit = true
	elif inside:
		var touched := false
		if p.x < -half + r and v.x < 0.0:
			p.x = -half + r
			v.x = -v.x * NET_DAMPING
			touched = true
		elif p.x > half - r and v.x > 0.0:
			p.x = half - r
			v.x = -v.x * NET_DAMPING
			touched = true
		if p.y > height - r and v.y > 0.0:
			p.y = height - r
			v.y = -v.y * NET_DAMPING
			touched = true
		var bz := back_z(p.y)
		if p.z > bz - r and v.z > 0.0:
			var push_dir := v.normalized()
			_ripple(p, push_dir * v.length())
			p.z = bz - r
			v = Vector3(v.x * 0.3, v.y * 0.3, -v.z * NET_DAMPING * 0.4)
			touched = true
		# A slow ball inside has already hit the netting: the loose net soaks
		# up what is left, so it drops and stays in.
		if v.length() < 6.0:
			var soak := exp(-6.0 * dt)
			v.x *= soak
			v.z *= soak
			hit = true
		if touched:
			if p.y > r + 0.01 or v.length() > 1.0:
				events.append({"type": "net", "position": xf * p})
			hit = true

	if hit:
		ball.position = xf * p
		ball.velocity = xf.basis.orthonormalized() * v
		ball.spin *= 0.3


func _inside_net(p: Vector3) -> bool:
	return absf(p.x) < width / 2.0 and p.y < height and p.z > 0.0 and p.z < back_z(p.y)


## Push a sphere of radius `rad` out of the segment a-b. Returns
## [new position, new velocity, impact speed] or [] if they do not touch.
func _collide_segment(p: Vector3, v: Vector3, a: Vector3, b: Vector3, rad: float, e: float) -> Array:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	var c := a + ab * t
	var d := p - c
	var dist := d.length()
	if dist >= rad or dist < 0.00001:
		return []
	var n := d / dist
	var vn := v.dot(n)
	var np := c + n * rad
	if vn >= 0.0:
		return [np, v, 0.0]
	var nv := v - n * vn * (1.0 + e)
	# A little friction along the surface
	var tangential := nv - n * nv.dot(n)
	nv -= tangential * 0.1
	return [np, nv, -vn]


func _ripple(local_pos: Vector3, push_vec: Vector3) -> void:
	if _net_mat == null:
		return
	_ripple_age = 0.0
	_net_mat.set_shader_parameter("impact", local_pos)
	_net_mat.set_shader_parameter("push", push_vec.normalized() if push_vec.length() > 0.01 else Vector3.BACK)
	_net_mat.set_shader_parameter("strength", clampf(push_vec.length() * 0.02, 0.05, 0.4))
	_net_mat.set_shader_parameter("age", 0.0)


func _queue_build() -> void:
	_built = false


func _build() -> void:
	_built = true
	for c in get_children():
		if c.has_meta("shinty_generated"):
			remove_child(c)
			c.queue_free()
	var root := Node3D.new()
	root.set_meta("shinty_generated", true)
	add_child(root)
	var post_mat := StandardMaterial3D.new()
	post_mat.albedo_color = post_color
	post_mat.roughness = 0.35
	var frame_mat := StandardMaterial3D.new()
	frame_mat.albedo_color = Color("9a9ea4")
	frame_mat.roughness = 0.4
	frame_mat.metallic = 0.6

	var half := width / 2.0
	var pc := half + post_radius
	var bar_y := height + post_radius
	_tube(root, Vector3(-pc, 0, 0), Vector3(-pc, bar_y + post_radius, 0), post_radius, post_mat)
	_tube(root, Vector3(pc, 0, 0), Vector3(pc, bar_y + post_radius, 0), post_radius, post_mat)
	_tube(root, Vector3(-pc - post_radius, bar_y, 0), Vector3(pc + post_radius, bar_y, 0), post_radius, post_mat)
	# Net frame: top stays, back uprights and ground bars.
	var fr := 0.02
	for sx in [-1.0, 1.0]:
		var x: float = sx * half
		_tube(root, Vector3(x, height, 0), Vector3(x, height, depth_top), fr, frame_mat)
		_tube(root, Vector3(x, height, depth_top), Vector3(x, 0, depth_bottom), fr, frame_mat)
		_tube(root, Vector3(x, 0.01, 0), Vector3(x, 0.01, depth_bottom), fr, frame_mat)
	_tube(root, Vector3(-half, height, depth_top), Vector3(half, height, depth_top), fr, frame_mat)
	_tube(root, Vector3(-half, 0.01, depth_bottom), Vector3(half, 0.01, depth_bottom), fr, frame_mat)

	# Net surfaces as fine grids so the ripple shader can bend them.
	var sh := Shader.new()
	sh.code = NET_SHADER
	_net_mat = ShaderMaterial.new()
	_net_mat.shader = sh
	_net_mat.set_shader_parameter("net_color", net_color)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bl := Vector3(-half, 0, depth_bottom)
	var br := Vector3(half, 0, depth_bottom)
	var tl := Vector3(-half, height, depth_top)
	var tr := Vector3(half, height, depth_top)
	_grid(st, bl, br, tl, tr)                                                     # back
	_grid(st, Vector3(-half, height, 0), Vector3(half, height, 0), tl, tr)        # roof
	_grid(st, Vector3(-half, 0, 0), bl, Vector3(-half, height, 0), tl)            # left side
	_grid(st, Vector3(half, 0, 0), br, Vector3(half, height, 0), tr)              # right side
	st.generate_normals()
	var net := MeshInstance3D.new()
	net.mesh = st.commit()
	net.material_override = _net_mat
	net.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(net)


## A subdivided quad from corners a (0,0), b (1,0), c (0,1), d (1,1).
## UVs are in metres so the mesh cells stay square.
func _grid(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	var nu := maxi(2, int(a.distance_to(b) / 0.25))
	var nv := maxi(2, int(a.distance_to(c) / 0.25))
	var len_u := a.distance_to(b)
	var len_v := a.distance_to(c)
	for i in nu:
		for j in nv:
			var q := []
			for k in [[i, j], [i + 1, j], [i, j + 1], [i + 1, j + 1]]:
				var u := float(k[0]) / nu
				var w := float(k[1]) / nv
				var pos := a.lerp(b, u).lerp(c.lerp(d, u), w)
				q.append([pos, Vector2(u * len_u, w * len_v)])
			for idx in [0, 1, 2, 2, 1, 3]:
				st.set_uv(q[idx][1])
				st.add_vertex(q[idx][0])


func _tube(parent: Node3D, a: Vector3, b: Vector3, r: float, mat: Material) -> void:
	var m := CylinderMesh.new()
	m.top_radius = r
	m.bottom_radius = r
	m.height = a.distance_to(b)
	m.radial_segments = 12
	m.rings = 1
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	var y := (b - a).normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	mi.transform = Transform3D(Basis(x, y, x.cross(y)), (a + b) / 2.0)
	parent.add_child(mi)
