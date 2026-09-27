// Tree canopy blob (see ShintyPitch._canopy_mesh): a lumpy core plus leaf
// cards cut out with a procedural leaf pattern. Leaf colour comes from the
// MultiMesh instance colour. Normals point out from the blob centre so each
// blob shades as one soft mass; the whole crown sways a little in the wind.
shader_type spatial;
render_mode diffuse_burley, cull_disabled;

uniform float lumpiness = 0.22;
uniform float leaf_density = 3.2;   // leaf clusters across one card
uniform float wind_strength = 0.05;

varying float height_shade;
varying float is_card;
varying float card_seed;
varying vec3 leaf_pos;

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise3(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i + vec3(0, 0, 0)), hash3(i + vec3(1, 0, 0)), f.x),
			mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x),
			mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float hash2(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

// Coverage of overlapping leaf-cluster ellipses at uv (0..1 across the card).
float leaves(vec2 uv, float seed) {
	vec2 g = uv * leaf_density;
	vec2 c = floor(g);
	float a = 0.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 cc = c + vec2(float(i), float(j));
			vec2 o = vec2(hash2(cc + seed * 13.0), hash2(cc + seed * 13.0 + 1.7));
			vec2 d = g - (cc + o);
			float ang = hash2(cc + 5.3) * 6.2832;
			d = mat2(vec2(cos(ang), sin(ang)), vec2(-sin(ang), cos(ang))) * d;
			d.x *= 1.7;
			a = max(a, 1.0 - length(d) / 0.62);
		}
	}
	// Thin out towards the card edge so no square outline shows.
	float edge = length((uv - 0.5) * 2.0);
	return a * (1.0 - smoothstep(0.55, 1.0, edge));
}

void vertex() {
	vec3 seed = MODEL_MATRIX[3].xyz * 0.173;
	is_card = UV2.x;
	card_seed = UV2.y;
	if (is_card < 0.5) {
		float n = noise3(VERTEX * 1.7 + seed) * 0.7 + noise3(VERTEX * 3.9 + seed) * 0.3;
		VERTEX += NORMAL * (n - 0.45) * lumpiness * 2.0;
	}
	// Wind: the crown sways, more at the top, each tree out of step.
	float phase = dot(seed, vec3(1.0, 0.0, 1.0)) * 3.0;
	float sway = sin(TIME * 1.2 + phase) + 0.4 * sin(TIME * 2.9 + phase * 1.7);
	VERTEX.xz += vec2(sway, sway * 0.6) * wind_strength * (VERTEX.y + 1.0);
	height_shade = clamp(VERTEX.y * 0.5 + 0.5, 0.0, 1.0);
	leaf_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Keep the outward blob normal on both faces of the leaf cards.
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	float mottle = noise3(leaf_pos * 1.3) * 0.6 + noise3(leaf_pos * 4.1) * 0.4;
	vec3 col = COLOR.rgb * mix(0.45, 1.1, height_shade);
	if (is_card > 0.5) {
		float a = leaves(UV, card_seed);
		ALPHA = a;
		ALPHA_SCISSOR_THRESHOLD = 0.35;
		// Leaf clusters vary a little in colour.
		col *= 0.95 + 0.16 * (hash2(floor(UV * leaf_density) + card_seed) - 0.5);
		col *= 0.88 + 0.15 * a;
	} else {
		col *= 0.82;  // the inside of the crown is in shade
	}
	col *= 0.8 + 0.35 * mottle;
	ALBEDO = col;
	ROUGHNESS = 0.85;
	SPECULAR = 0.2;
	BACKLIGHT = COLOR.rgb * 0.3;
}
