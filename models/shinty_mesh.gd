class_name ShintyMesh
extends RefCounted
## Mesh helpers for the procedural models: smooth swept tubes (limbs, torso,
## head, boots, caman) and a small material library (fabric, skin, wood,
## leather, gloss) that works in the GL Compatibility renderer.

## Sweep a cross-section along a path. `points` are the centres, `radii` the
## half-width (x) and half-depth (z) at each point as Vector2. The section is a
## superellipse: `squareness` 2 is an ellipse, 3-4 is a rounded box. The
## x axis of each section starts along `side` (default +X) and is carried
## along the path without twisting. Ends are closed unless `open_ends`.
## UVs: u runs round the section in metres, v along the path in metres, so
## fabric and grain shaders keep a constant scale.
static func sweep(points: PackedVector3Array, radii: PackedVector2Array, segments: int = 16,
		squareness: float = 2.0, open_ends: bool = false, side: Vector3 = Vector3.RIGHT,
		arc_from: float = 0.0, arc_to: float = TAU) -> ArrayMesh:
	var n := points.size()
	var full := is_equal_approx(arc_to - arc_from, TAU)
	var ring := segments + 1
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var along := 0.0
	var frame_x := side
	var e := 2.0 / maxf(squareness, 0.5)
	for i in n:
		var t: Vector3
		if i == 0:
			t = points[1] - points[0]
		elif i == n - 1:
			t = points[n - 1] - points[n - 2]
		else:
			t = points[i + 1] - points[i - 1]
		t = t.normalized()
		frame_x = (frame_x - t * frame_x.dot(t))
		if frame_x.length() < 0.001:
			frame_x = t.cross(Vector3.FORWARD)
		frame_x = frame_x.normalized()
		var frame_z := frame_x.cross(t).normalized()
		if i > 0:
			along += points[i].distance_to(points[i - 1])
		var r := radii[i]
		var perim := PI * (3.0 * (r.x + r.y) - sqrt((3.0 * r.x + r.y) * (r.x + 3.0 * r.y)))
		for j in ring:
			var a := lerpf(arc_from, arc_to, float(j) / segments)
			var c := cos(a)
			var s := sin(a)
			var px := signf(c) * pow(absf(c), e) * r.x
			var pz := signf(s) * pow(absf(s), e) * r.y
			verts.append(points[i] + frame_x * px + frame_z * pz)
			# Normal of the superellipse, scaled by the radii
			var nx := signf(c) * pow(absf(c), 2.0 - e) / maxf(r.x, 0.0001)
			var nz := signf(s) * pow(absf(s), 2.0 - e) / maxf(r.y, 0.0001)
			norms.append((frame_x * nx + frame_z * nz).normalized())
			uvs.append(Vector2(perim * float(j) / segments * (arc_to - arc_from) / TAU, along))
	for i in n - 1:
		for j in segments:
			var a0 := i * ring + j
			var b0 := a0 + ring
			idx.append_array([a0, a0 + 1, b0, a0 + 1, b0 + 1, b0])
	if not open_ends and full:
		for end in [0, n - 1]:
			var centre := points[end]
			var t2 := (points[1] - points[0]) if end == 0 else (points[n - 1] - points[n - 2])
			t2 = t2.normalized() * (-1.0 if end == 0 else 1.0)
			# Domed cap: push the centre out a little so ends look rounded.
			var bulge := minf(radii[end].x, radii[end].y) * 0.55
			var ci := verts.size()
			verts.append(centre + t2 * bulge)
			norms.append(t2)
			uvs.append(Vector2(0, along if end == n - 1 else 0.0))
			var base: int = end * ring
			for j in segments:
				if end == 0:
					idx.append_array([ci, base + j, base + j + 1])
				else:
					idx.append_array([ci, base + j + 1, base + j])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


## A straight tube along +Y (or -Y for negative heights) with rings given as
## [y, half_width, half_depth, z_offset, x_offset] (offsets optional).
static func loft(rings: Array, segments: int = 16, squareness: float = 2.0, open_ends: bool = false,
		arc_from: float = 0.0, arc_to: float = TAU) -> ArrayMesh:
	var pts := PackedVector3Array()
	var rad := PackedVector2Array()
	for r in rings:
		var oz: float = r[3] if r.size() > 3 else 0.0
		var ox: float = r[4] if r.size() > 4 else 0.0
		pts.append(Vector3(ox, r[0], oz))
		rad.append(Vector2(r[1], r[2]))
	return sweep(pts, rad, segments, squareness, open_ends, Vector3.RIGHT, arc_from, arc_to)


## A closed shape along -Z whose sections are flat underneath and rounded on
## top, like a boot or a sole. Stations are [z, half_width, bottom_y, top_y,
## x_offset] from heel to toe; `top_sq` and `bottom_sq` are the superellipse
## exponents of the upper and lower halves (2 = round, higher = squarer).
static func shoe(stations: Array, segments: int = 16, top_sq: float = 2.3, bottom_sq: float = 6.0) -> ArrayMesh:
	var n := stations.size()
	var ring := segments + 1
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var along := 0.0
	for i in n:
		var st: Array = stations[i]
		var hw: float = st[1]
		var yb: float = st[2]
		var yt: float = st[3]
		var ox: float = st[4] if st.size() > 4 else 0.0
		if i > 0:
			along += absf(st[0] - stations[i - 1][0])
		var mid := (yb + yt) / 2.0
		var hh := (yt - yb) / 2.0
		for j in ring:
			# Start at the bottom centre so the UV seam hides under the sole.
			var a := -PI / 2 + TAU * float(j) / segments
			var c := cos(a)
			var s := sin(a)
			var e := 2.0 / (top_sq if s > 0.0 else bottom_sq)
			verts.append(Vector3(ox + signf(c) * pow(absf(c), e) * hw, mid + signf(s) * pow(absf(s), e) * hh, st[0]))
			uvs.append(Vector2(float(j) / segments * (hw + hh) * 3.2, along))
	for i in n - 1:
		for j in segments:
			var a0 := i * ring + j
			var b0 := a0 + ring
			idx.append_array([a0, a0 + 1, b0, a0 + 1, b0 + 1, b0])
	# Close heel and toe with a fan round the section centre.
	for end in [0, n - 1]:
		var st: Array = stations[end]
		var ci := verts.size()
		verts.append(Vector3(st[4] if st.size() > 4 else 0.0, (st[2] + st[3]) / 2.0, st[0]))
		uvs.append(Vector2(0, along if end == n - 1 else 0.0))
		var base: int = end * ring
		for j in segments:
			if end == 0:
				idx.append_array([ci, base + j, base + j + 1])
			else:
				idx.append_array([ci, base + j + 1, base + j])
	# Smooth normals from the faces (the seam vertices share a position, so
	# average by position to hide it).
	var norms := PackedVector3Array()
	norms.resize(verts.size())
	for t in range(0, idx.size(), 3):
		var p0 := verts[idx[t]]
		var fn := (verts[idx[t + 1]] - p0).cross(verts[idx[t + 2]] - p0)
		for k in 3:
			norms[idx[t + k]] += fn
	for i in n:
		var s0 := i * ring
		var joined := norms[s0] + norms[s0 + segments]
		norms[s0] = joined
		norms[s0 + segments] = joined
	# Godot's front faces wind clockwise, so the face cross products point in.
	for i in norms.size():
		norms[i] = -norms[i].normalized()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


# --- Materials -------------------------------------------------------------------

static var _cache := {}

const FABRIC_SHADER := """
shader_type spatial;
render_mode cull_back;
uniform vec4 base_color : source_color = vec4(0.7, 0.1, 0.15, 1.0);
uniform vec4 trim_color : source_color = vec4(1.0);
// Bands in the trim colour along the mesh (v in metres): x = start, y = end.
uniform vec4 band_a = vec4(-9.0, -9.0, 0.0, 0.0);
uniform vec4 band_b = vec4(-9.0, -9.0, 0.0, 0.0);
// Pattern: 0 plain, 1 hoops, 2 vertical stripes
uniform float pattern = 0.0;
uniform float pattern_scale = 0.12;
uniform float roughness = 0.82;
uniform float weave = 1.0;
// Knitted ribs running down the cloth (socks), as a height in metres.
uniform float ribs = 0.0;

float in_band(float v, vec4 b) { return step(b.x, v) * step(v, b.y); }

void fragment() {
	vec3 c = base_color.rgb;
	float t = max(in_band(UV.y, band_a), in_band(UV.y, band_b));
	if (pattern > 0.5 && pattern < 1.5) {
		t = max(t, step(0.5, fract(UV.y / pattern_scale)));
	} else if (pattern > 1.5) {
		t = max(t, step(0.5, fract(UV.x / pattern_scale)));
	}
	c = mix(c, trim_color.rgb, t);
	// Knit: fine diagonal weave, only visible up close.
	vec2 k = UV * 520.0;
	float knit = sin(k.x + k.y) * sin(k.x - k.y);
	// Folds: soft drapes hanging down the cloth plus a few diagonal creases,
	// as a height (in metres) that bends the shading normal. u runs round
	// the body; multiples of 20 in u repeat exactly once round a body, arm
	// or leg, so there is no seam.
	float drape = sin(UV.x * 20.0 + sin(UV.y * 11.0) * 2.0);
	float crease = sin(UV.x * 40.0 + UV.y * 38.0 + cos(UV.x * 20.0) * 1.5);
	crease *= smoothstep(0.2, 0.9, sin(UV.x * 20.0 + UV.y * 7.0 + 1.3));
	float h = weave * (drape * 0.0055 + crease * 0.002)
		+ ribs * sin(UV.x * 600.0) * clamp(2.0 - fwidth(UV.x * 600.0), 0.0, 1.0);  // fade before they shimmer
	vec3 dpx = dFdx(VERTEX), dpy = dFdy(VERTEX);
	vec3 r1 = cross(dpy, NORMAL), r2 = cross(NORMAL, dpx);
	float det = dot(dpx, r1);
	vec3 grad = sign(det) * (dFdx(h) * r1 + dFdy(h) * r2);
	NORMAL = normalize(abs(det) * NORMAL - grad);
	c *= 1.0 + weave * (knit * 0.035 - (0.5 - 0.5 * drape) * 0.05);
	ALBEDO = c;
	ROUGHNESS = roughness;
	SPECULAR = 0.25;
	RIM = 0.35;
	RIM_TINT = 0.6;
}
"""

const SKIN_SHADER := """
shader_type spatial;
uniform vec4 skin : source_color = vec4(0.9, 0.75, 0.62, 1.0);
uniform vec4 flush : source_color = vec4(0.85, 0.45, 0.4, 1.0);
varying vec3 obj;
void vertex() { obj = VERTEX; }
void fragment() {
	// Slight warmth where skin is thin (fake subsurface) and pore-level variation.
	float n = sin(obj.x * 310.0) * sin(obj.y * 290.0) * sin(obj.z * 330.0);
	vec3 c = skin.rgb * (1.0 + n * 0.025);
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	c = mix(mix(c, flush.rgb, 0.18), c, facing);
	ALBEDO = c;
	ROUGHNESS = 0.55;
	SPECULAR = 0.35;
	RIM = 0.2;
	RIM_TINT = 1.0;
	BACKLIGHT = flush.rgb * 0.25;
}
"""

const WOOD_SHADER := """
shader_type spatial;
uniform vec4 light_wood : source_color = vec4(0.78, 0.6, 0.38, 1.0);
uniform vec4 dark_wood : source_color = vec4(0.55, 0.38, 0.2, 1.0);
uniform float varnish = 0.35;
void fragment() {
	// Ash grain runs along the stick (v); wobble it round the shaft (u).
	float g = sin(UV.y * 55.0 + sin(UV.x * 40.0) * 2.5 + sin(UV.y * 7.0) * 3.0);
	g = smoothstep(0.2, 1.0, g * 0.5 + 0.5);
	float fine = sin(UV.y * 400.0 + UV.x * 60.0) * 0.5 + 0.5;
	vec3 c = mix(light_wood.rgb, dark_wood.rgb, g * 0.7 + fine * 0.1);
	ALBEDO = c;
	ROUGHNESS = mix(0.7, 0.3, varnish);
	SPECULAR = 0.5;
}
"""

const TAPE_SHADER := """
shader_type spatial;
uniform vec4 tape : source_color = vec4(0.08, 0.08, 0.09, 1.0);
void fragment() {
	// Overlapping spiral wraps of grip tape
	float w = fract(UV.y / 0.022 + UV.x / 0.11);
	float edge = smoothstep(0.0, 0.08, w) * smoothstep(1.0, 0.85, w);
	ALBEDO = tape.rgb * (0.75 + 0.35 * edge);
	ROUGHNESS = 0.9;
}
"""

const BALL_SHADER := """
shader_type spatial;
uniform vec4 leather : source_color = vec4(0.96, 0.95, 0.9, 1.0);
uniform vec4 stitch : source_color = vec4(0.7, 0.15, 0.12, 1.0);
varying vec3 obj;
void vertex() { obj = VERTEX; }
void fragment() {
	vec3 p = normalize(obj);
	// One seam round the ball's equator (the ball is rotated as it spins).
	float d = p.y;
	float ang = atan(p.z, p.x);
	float groove = 1.0 - smoothstep(0.0, 0.035, abs(d));
	float dash = step(0.45, fract(ang * 44.0 / 6.2831853));
	float rows = 1.0 - smoothstep(0.0, 0.02, abs(abs(d) - 0.075));
	// Leather grain
	float grain = sin(p.x * 180.0) * sin(p.y * 170.0) * sin(p.z * 190.0);
	vec3 c = leather.rgb * (1.0 + grain * 0.03);
	c *= 1.0 - groove * 0.35;
	c = mix(c, stitch.rgb, rows * dash);
	ALBEDO = c;
	ROUGHNESS = mix(0.45, 0.8, groove);
	SPECULAR = 0.45;
}
"""


## Plain-coloured parts baked together (see ShintyPlayerLook._bake): albedo in
## the vertex colour (sRGB, alpha = clearcoat), roughness and metallic in UV2.
const SOLID_VC_SHADER := """
shader_type spatial;
void fragment() {
	vec3 c = COLOR.rgb;
	ALBEDO = mix(pow((c + vec3(0.055)) * (1.0 / 1.055), vec3(2.4)), c * (1.0 / 12.92), lessThan(c, vec3(0.04045)));
	ROUGHNESS = UV2.x;
	METALLIC = UV2.y;
	SPECULAR = mix(0.5, 0.8, UV2.y);
	CLEARCOAT = COLOR.a;
	CLEARCOAT_ROUGHNESS = 0.15;
}
"""


static func _shader(key: String, code: String) -> Shader:
	if not _cache.has(key):
		var s := Shader.new()
		s.code = code
		_cache[key] = s
	return _cache[key]


static func fabric(base: Color, trim: Color, band_a := Vector2(-9, -9), band_b := Vector2(-9, -9),
		pattern := 0, pattern_scale := 0.12, roughness := 0.82) -> ShaderMaterial:
	var key := "fab/%s/%s/%s/%s/%d/%.3f/%.2f" % [base.to_html(), trim.to_html(), band_a, band_b, pattern, pattern_scale, roughness]
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = _shader("fabric_shader", FABRIC_SHADER)
	m.set_shader_parameter("base_color", base)
	m.set_shader_parameter("trim_color", trim)
	m.set_shader_parameter("band_a", Vector4(band_a.x, band_a.y, 0, 0))
	m.set_shader_parameter("band_b", Vector4(band_b.x, band_b.y, 0, 0))
	m.set_shader_parameter("pattern", float(pattern))
	m.set_shader_parameter("pattern_scale", pattern_scale)
	m.set_shader_parameter("roughness", roughness)
	_cache[key] = m
	return m


static func skin(color: Color) -> ShaderMaterial:
	var key := "skin/" + color.to_html()
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = _shader("skin_shader", SKIN_SHADER)
	m.set_shader_parameter("skin", color)
	m.set_shader_parameter("flush", color.lerp(Color(0.85, 0.35, 0.3), 0.5))
	_cache[key] = m
	return m


static func wood(light: Color = Color("c89a62"), dark: Color = Color("8a5f33")) -> ShaderMaterial:
	var key := "wood/%s/%s" % [light.to_html(), dark.to_html()]
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = _shader("wood_shader", WOOD_SHADER)
	m.set_shader_parameter("light_wood", light)
	m.set_shader_parameter("dark_wood", dark)
	_cache[key] = m
	return m


static func tape(color: Color = Color("141417")) -> ShaderMaterial:
	var key := "tape/" + color.to_html()
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = _shader("tape_shader", TAPE_SHADER)
	m.set_shader_parameter("tape", color)
	_cache[key] = m
	return m


static func ball_leather() -> ShaderMaterial:
	if _cache.has("ball"):
		return _cache["ball"]
	var m := ShaderMaterial.new()
	m.shader = _shader("ball_shader", BALL_SHADER)
	_cache["ball"] = m
	return m


static func solid_vc() -> ShaderMaterial:
	if _cache.has("solid_vc"):
		return _cache["solid_vc"]
	var m := ShaderMaterial.new()
	m.shader = _shader("solid_vc_shader", SOLID_VC_SHADER)
	_cache["solid_vc"] = m
	return m


## Plain StandardMaterial3D, cached. `clearcoat` gives helmets their gloss.
static func solid(color: Color, roughness: float, metallic: float = 0.0, clearcoat: float = 0.0) -> StandardMaterial3D:
	var key := "solid/%s/%.2f/%.2f/%.2f" % [color.to_html(), roughness, metallic, clearcoat]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	if metallic > 0.5:
		m.metallic_specular = 0.8
	if clearcoat > 0.0:
		m.clearcoat_enabled = true
		m.clearcoat = clearcoat
		m.clearcoat_roughness = 0.15
	_cache[key] = m
	return m
