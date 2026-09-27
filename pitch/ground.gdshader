// Ground for the shinty pitch and the land around it.
// Pitch markings are drawn here rather than baked into a texture, so they stay
// sharp at any camera distance and follow whatever pitch size the scene uses.
// Vertex colour channels are masks painted by shinty_pitch.gd:
//   r = bare earth, g = rough grass, b = gravel, a = sand.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform float unit = 0.9144;                  // world units per yard
uniform vec2 pitch_size = vec2(150.0, 75.0);  // yards
uniform float line_width = 0.11;              // yards (about 4 inches)
uniform float d_radius = 10.0;                // the D around each hail
uniform float penalty_dist = 20.0;            // penalty spot from the goal line
uniform float spot_arc_radius = 5.0;          // centre circle and penalty arcs
uniform float corner_arc_radius = 2.0;
uniform float stripe_width = 6.0;             // yards per mowing stripe
uniform float stripe_strength = 0.09;
uniform bool stripe_along_length = false;  // lengthwise bands instead of across
uniform float wear = 0.55;                    // 0 = lush, 1 = dry summer park

uniform vec3 grass_color : source_color = vec3(0.33, 0.45, 0.19);
uniform vec3 grass_dry_color : source_color = vec3(0.52, 0.52, 0.28);
uniform vec3 rough_color : source_color = vec3(0.30, 0.38, 0.18);
uniform vec3 earth_color : source_color = vec3(0.52, 0.34, 0.23);
uniform vec3 gravel_color : source_color = vec3(0.52, 0.50, 0.46);
uniform vec3 sand_color : source_color = vec3(0.80, 0.73, 0.57);
uniform vec3 line_color : source_color = vec3(0.94, 0.94, 0.92);
// Farmland beyond the park: a patchwork of fields split by hedges.
uniform float field_strength = 1.0;
uniform float field_start = 140.0;            // metres from the centre spot
uniform vec3 crop_color : source_color = vec3(0.64, 0.59, 0.33);
uniform vec3 hedge_color : source_color = vec3(0.13, 0.2, 0.09);

varying vec3 local_pos;
varying vec3 view_local;  // camera to this point, in the ground's own space

void vertex() {
	local_pos = VERTEX;
	vec3 cam_local = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
	view_local = VERTEX - cam_local;
}

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(17.1, 3.7);
		a *= 0.5;
	}
	return v;
}

float ring(vec2 p, vec2 c, float r) {
	return abs(length(p - c) - r);
}

float disc(vec2 p, vec2 c, float r) {
	return max(length(p - c) - r, 0.0);
}

// Distance in yards from p (yards, pitch centre at 0) to the nearest marking.
float marking_dist(vec2 p) {
	vec2 h = pitch_size * 0.5;
	vec2 q = abs(p);
	vec2 e = q - h;
	// Boundary: sidelines and bylines.
	float d = (e.x <= 0.0 && e.y <= 0.0) ? min(-e.x, -e.y) : length(max(e, 0.0));
	if (q.y <= h.y) {
		d = min(d, q.x); // halfway line
	}
	d = min(d, ring(p, vec2(0.0), spot_arc_radius));
	d = min(d, disc(p, vec2(0.0), 0.25));
	// Both ends are mirror images, so work in |x|.
	vec2 qe = vec2(q.x, p.y);
	vec2 goal = vec2(h.x, 0.0);
	if (q.x <= h.x) {
		d = min(d, ring(qe, goal, d_radius));
	}
	vec2 pen = vec2(h.x - penalty_dist, 0.0);
	d = min(d, disc(qe, pen, 0.25));
	if (q.x <= pen.x) {
		d = min(d, ring(qe, pen, spot_arc_radius));
	}
	if (q.x <= h.x && q.y <= h.y) {
		d = min(d, ring(q, h, corner_arc_radius));
	}
	return d;
}

vec3 fields(vec2 m, float n_mid, out float hedge) {
	// Rotate and warp the grid so the fields don't line up with the pitch.
	mat2 rot = mat2(vec2(0.94, 0.34), vec2(-0.34, 0.94));
	vec2 q = rot * m / 150.0 + vec2(fbm(m * 0.004), fbm(m * 0.004 + 7.0)) * 0.6;
	vec2 cell = floor(q);
	vec2 f = fract(q);
	float r = hash(cell + 3.1);
	vec3 col = rough_color;
	if (r < 0.3) {
		col = grass_color * 0.95;                 // pasture
	} else if (r < 0.48) {
		col = crop_color;                         // barley or hay
	} else if (r < 0.58) {
		col = earth_color * 0.85;                 // ploughed
	} else if (r < 0.8) {
		col = mix(grass_color, rough_color, 0.5);
	}
	col *= 0.9 + 0.2 * n_mid;
	float edge = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y)) * 150.0;  // metres to the hedge
	hedge = 1.0 - smoothstep(1.2, 3.0, edge);
	return col;
}

void fragment() {
	vec2 wp = local_pos.xz;          // world units
	vec2 p = wp / unit;              // yards
	vec2 h = pitch_size * 0.5;
	vec2 m = wp / unit * 0.9144;     // metres, so noise scale is unit independent
	float px_size = length(fwidth(m)); // metres covered by one pixel, for fading detail

	float n_big = fbm(m * 0.045);
	float n_mid = fbm(m * 0.3 + 11.0);
	float n_fine = vnoise(m * 2.7);
	float detail = 1.0 - smoothstep(0.15, 0.8, px_size);  // blade-scale detail only up close
	float n_blade = mix(0.5, vnoise(m * 11.0), detail);
	float dry = smoothstep(0.42, 0.78, n_big * 0.65 + n_mid * 0.35) * wear;
	vec3 col = mix(grass_color, grass_dry_color, dry);
	col *= 0.88 + 0.16 * n_fine + 0.1 * (n_blade - 0.5);

	// Mowing stripes. Alternate bands have their blades laid in opposite
	// directions, so how light a band looks depends on where you view it from,
	// like a real mown pitch.
	float on_pitch = step(abs(p.x), h.x + 2.0) * step(abs(p.y), h.y + 2.0);
	float band = mod(floor((stripe_along_length ? p.y : p.x) / stripe_width), 2.0) * 2.0 - 1.0;
	vec2 lay = stripe_along_length ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
	float facing = dot(normalize(view_local.xz + vec2(0.0001)), lay);
	float sheen = band * sign(facing + 0.001) * mix(0.5, 1.0, abs(facing));
	col *= 1.0 + sheen * stripe_strength * on_pitch;

	// Worn patches in the goalmouths and around the centre, where play is busiest.
	vec2 mouth = vec2(abs(p.x) - h.x, p.y);
	float worn = smoothstep(9.0, 1.5, length(mouth * vec2(1.0, 0.7))) * on_pitch;
	worn += smoothstep(6.0, 0.5, length(p)) * 0.5;
	col = mix(col, mix(grass_dry_color, earth_color, 0.35), clamp(worn * (0.35 + 0.4 * n_mid), 0.0, 0.6));

	vec3 rough = rough_color * (0.85 + 0.3 * n_mid);
	float farm = field_strength * smoothstep(field_start, field_start + 60.0, length(m));
	float hedge = 0.0;
	if (farm > 0.0) {
		rough = mix(rough, fields(m, n_mid, hedge), farm);
		hedge *= farm;
	}
	col = mix(col, rough, COLOR.g);
	col = mix(col, hedge_color * (0.8 + 0.4 * n_fine), hedge * COLOR.g);
	col = mix(col, earth_color * (0.85 + 0.25 * n_mid), COLOR.r);
	col = mix(col, gravel_color * (0.9 + 0.2 * n_fine), COLOR.b);
	col = mix(col, sand_color * (0.92 + 0.12 * n_mid), COLOR.a);

	float d = marking_dist(p);
	float half_w = line_width * 0.5;
	float aa = fwidth(d) * 0.75 + 0.0001;
	float line = 1.0 - smoothstep(half_w - aa, half_w + aa, d);
	line *= 0.88 + 0.12 * n_fine; // chalk is never perfectly even
	line *= on_pitch;
	col = mix(col, line_color, line);

	// Blade-scale bumps catch the light up close.
	float bx = vnoise(m * 11.0 + vec2(0.07, 0.0)) - vnoise(m * 11.0);
	float bz = vnoise(m * 11.0 + vec2(0.0, 0.07)) - vnoise(m * 11.0);
	NORMAL_MAP = normalize(vec3(bx * detail * 4.0, bz * detail * 4.0, 1.0)) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.8;

	ALBEDO = col;
	float grassy = 1.0 - max(max(COLOR.r, COLOR.b), max(COLOR.a, line));
	ROUGHNESS = mix(0.9, 0.78, grassy * on_pitch) + dry * 0.08;
	SPECULAR = mix(0.2, 0.35, grassy);
}
