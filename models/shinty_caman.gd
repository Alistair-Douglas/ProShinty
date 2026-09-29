class_name ShintyCaman
extends RefCounted
## A caman (shinty stick) built from a design: the shape of the bas, the wood
## finish, grip tape (with an optional second tape spiralled over it), tape
## round the bas and painted bands on the shaft. The caman designer edits a
## design; players carry their club's design (see ShintyPlayerModel.setup).
##
## A design is a plain Dictionary so it saves to JSON as is:
##   shape    index into SHAPES
##   wood     index into WOODS ("Painted" uses `paint`)
##   paint    "#rrggbb"
##   grip     "#rrggbb" grip tape
##   wrap     bool, a second tape wound over the grip
##   grip2    "#rrggbb" that second tape
##   bas_tape "#rrggbb" tape round the bas
##   bands    0..3 painted bands low on the shaft
##   band     "#rrggbb"
##   helmet   "" for the club colour, else "#rrggbb"
##
## Geometry: the butt of the handle is the origin, the shaft runs down -Y and
## the bas curves towards -Z (ShintyPlayerModel.HEAD_LOCAL is its striking
## centre). Every shape keeps the same length so the swing physics hold.

const SHAPES := ["Classic", "Big bas", "Light", "Keeper"]
const WOODS := ["Natural ash", "Honey", "Dark stain", "Painted"]
## [light grain, dark grain] per wood finish.
const WOOD_TONES := [
	[Color("c89a62"), Color("8a5f33")],
	[Color("dcae6a"), Color("a86f2c")],
	[Color("6e4526"), Color("3b2412")],
]

## The colours the designer offers, in order, with names.
const PALETTE := [
	["Black", "141417"], ["White", "f2f2f0"], ["Grey", "8a9096"], ["Navy", "16254f"],
	["Royal blue", "1f4fb8"], ["Sky blue", "6fb3e6"], ["Red", "c8102e"], ["Maroon", "6d1a2c"],
	["Orange", "f07c1a"], ["Gold", "f2c400"], ["Green", "1e8a3c"], ["Lime", "8fd63c"],
	["Purple", "6b3fa0"], ["Pink", "e8659a"], ["Teal", "1a9aa0"], ["Brown", "6b4423"],
]

const DEFAULT := {
	"shape": 0, "wood": 0, "paint": "#1f4fb8", "grip": "#141417", "wrap": false,
	"grip2": "#f2f2f0", "bas_tape": "#141417", "bands": 0, "band": "#c8102e", "helmet": "",
}

const TAPE2_SHADER := """
shader_type spatial;
uniform vec4 tape : source_color = vec4(0.08, 0.08, 0.09, 1.0);
uniform vec4 tape2 : source_color = vec4(1.0);
uniform float wrap2 = 0.0;
void fragment() {
	// Overlapping spiral wraps of grip tape (u and v are in metres).
	float w = fract(UV.y / 0.022 + UV.x / 0.11);
	float edge = smoothstep(0.0, 0.08, w) * smoothstep(1.0, 0.85, w);
	vec3 c = tape.rgb * (0.75 + 0.35 * edge);
	// A second, narrower tape wound over the first at a longer pitch.
	float s = fract(UV.y / 0.07 - UV.x / 0.11);
	float on2 = smoothstep(0.0, 0.03, s) * smoothstep(0.36, 0.33, s) * wrap2;
	float e2 = smoothstep(0.0, 0.06, s) * smoothstep(0.36, 0.3, s);
	c = mix(c, tape2.rgb * (0.8 + 0.25 * e2), on2);
	ALBEDO = c;
	ROUGHNESS = 0.88;
}
"""

static var _cache := {}


## A complete design: missing or broken keys fall back to DEFAULT.
static func sanitize(d: Variant) -> Dictionary:
	var out := DEFAULT.duplicate()
	if not (d is Dictionary):
		return out
	for k in DEFAULT:
		if not d.has(k):
			continue
		var v: Variant = d[k]
		match typeof(DEFAULT[k]):
			TYPE_INT:
				if v is int or v is float:
					out[k] = int(v)
			TYPE_BOOL:
				out[k] = bool(v)
			TYPE_STRING:
				var s := str(v)
				if s == "" and k == "helmet":
					out[k] = ""
				elif Color.html_is_valid(s):
					out[k] = "#" + Color.html(s).to_html(false)
	out["shape"] = clampi(out["shape"], 0, SHAPES.size() - 1)
	out["wood"] = clampi(out["wood"], 0, WOODS.size() - 1)
	out["bands"] = clampi(out["bands"], 0, 3)
	return out


## A starting design in a club's colours: grip in the main colour, the second
## tape and bands in the other.
static func for_team(team: Dictionary) -> Dictionary:
	var c: Dictionary = team.get("colors", {})
	var d := DEFAULT.duplicate()
	var primary := str(c.get("primary", "#141417"))
	var secondary := str(c.get("secondary", "#f2f2f0"))
	d["grip"] = primary
	d["grip2"] = secondary
	d["band"] = primary
	return sanitize(d)


static func color(d: Dictionary, key: String) -> Color:
	return Color(str(d.get(key, DEFAULT.get(key, "#141417"))))


## Adds the caman's meshes under `parent`. `detail` false leaves out the bas
## tape and bands (distant players).
static func build(parent: Node3D, design: Dictionary = {}, detail := true) -> void:
	var d := sanitize(design)
	var L := ShintyPlayerModel.CAMAN_LENGTH
	var shape: int = d["shape"]
	# Shaft thickness, bas depth (along -Z), bas thickness (across X).
	var thick: float = [1.0, 1.04, 0.9, 1.06][shape]
	var reach: float = [1.0, 1.12, 0.94, 1.18][shape]
	var face: float = [1.0, 1.12, 0.9, 1.4][shape]
	var pts := PackedVector3Array()
	var rad := PackedVector2Array()
	var shaft := [[0.0, 0.0165, 0.0145], [-0.3, 0.0158, 0.0138], [-0.6, 0.0148, 0.0135],
		[-(L - 0.16), 0.0138, 0.0145], [-(L - 0.1), 0.0148, 0.02]]
	for s in shaft:
		pts.append(Vector3(0, s[0], 0))
		rad.append(Vector2(s[1], s[2]) * thick)
	# The bas: a curved wedge, both faces flat enough to strike with.
	var bas := [[-(L - 0.07), 0.0, 0.017, 0.026], [-(L - 0.045), -0.008, 0.0185, 0.032],
		[-(L - 0.025), -0.025, 0.019, 0.035], [-(L - 0.012), -0.05, 0.0185, 0.034],
		[-(L - 0.006), -0.08, 0.017, 0.03], [-(L - 0.004), -0.105, 0.014, 0.024], [-(L - 0.004), -0.118, 0.01, 0.016]]
	for b in bas:
		pts.append(Vector3(0, b[0], b[1] * reach))
		rad.append(Vector2(b[2] * face, b[3] * lerpf(1.0, reach, 0.6)))
	_add(parent, ShintyMesh.sweep(pts, rad, 12, 2.6, false, Vector3.RIGHT), wood_material(d))

	var grip := tape_material(color(d, "grip"), color(d, "grip2") if d["wrap"] else Color.BLACK, d["wrap"])
	_add(parent, ShintyMesh.loft([[0.004, 0.0185 * thick, 0.0165 * thick], [-0.3, 0.0178 * thick, 0.016 * thick]], 12, 2.0, true), grip)
	_add(parent, ShintyMesh.loft([[0.012, 0.012, 0.011], [0.006, 0.019, 0.017], [0.0, 0.021 * thick, 0.019 * thick],
		[-0.012, 0.019 * thick, 0.017 * thick]], 12), ShintyMesh.tape(color(d, "grip")))
	if not detail:
		return
	# Tape round the neck of the bas, as players do to protect it.
	_add(parent, ShintyMesh.loft([[-(L - 0.1), 0.0152 * thick, 0.0205 * thick],
		[-(L - 0.07), 0.0175 * face, 0.0265 * lerpf(1.0, reach, 0.6)]], 12, 2.4, true), ShintyMesh.tape(color(d, "bas_tape")))
	# Painted bands low on the shaft.
	var paint := ShintyMesh.solid(color(d, "band"), 0.4, 0.0, 0.5)
	for i in int(d["bands"]):
		var y := -0.62 - i * 0.034
		var r := Vector2(0.0147, 0.0137) * thick + Vector2(0.0007, 0.0007)
		_add(parent, ShintyMesh.loft([[y, r.x, r.y], [y - 0.016, r.x - 0.0002, r.y]], 12, 2.0, true), paint)


static func wood_material(d: Dictionary) -> Material:
	var w: int = d["wood"]
	if w < WOOD_TONES.size():
		return ShintyMesh.wood(WOOD_TONES[w][0], WOOD_TONES[w][1])
	# Painted: the grain still shows faintly through the paint.
	var p := color(d, "paint")
	return ShintyMesh.wood(p.lightened(0.08), p.darkened(0.3))


static func tape_material(base: Color, over: Color, wrap: bool) -> ShaderMaterial:
	var key := "%s/%s/%s" % [base.to_html(), over.to_html(), wrap]
	if _cache.has(key):
		return _cache[key]
	if not _cache.has("shader"):
		var s := Shader.new()
		s.code = TAPE2_SHADER
		_cache["shader"] = s
	var m := ShaderMaterial.new()
	m.shader = _cache["shader"]
	m.set_shader_parameter("tape", base)
	m.set_shader_parameter("tape2", over)
	m.set_shader_parameter("wrap2", 1.0 if wrap else 0.0)
	_cache[key] = m
	return m


static func _add(parent: Node3D, mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	parent.add_child(mi)
	return mi
