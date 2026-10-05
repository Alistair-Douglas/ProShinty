// Shared by canopy.gdshader (near trees) and canopy_far.gdshader (far trees,
// FAR defined: the core only, opaque).
// Tree canopy blob (see ShintyPitch._canopy_mesh): a lumpy core plus leaf
// cards cut out with a baked leaf pattern (pitch/leaves.png). Leaf colour comes from the
// MultiMesh instance colour. Normals point out from the blob centre so each
// blob shades as one soft mass; the whole crown sways a little in the wind.
uniform float lumpiness = 0.22;
uniform float leaf_density = 3.2;   // leaf clusters across one card
uniform float wind_strength = 0.05;
uniform sampler2D leaf_tex : hint_default_white, filter_linear, repeat_disable;
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
// The leaf pattern again, tiled over far blobs so they keep a leafy clumping.
uniform sampler2D leaf_tile : hint_default_white, filter_linear_mipmap, repeat_enable;

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

// Leaf-cluster cut-out, baked by tools/bake_scenery_textures.gd (four
// variants in a 2x2 atlas, each also mirrored by the card's seed).
float leaves(vec2 uv, float seed) {
	int v = int(seed * 4.0) & 3;
	vec2 u = clamp(uv, vec2(0.004), vec2(0.996));
	if (fract(seed * 7.13) > 0.5) {
		u.x = 1.0 - u.x;
	}
	float a = texture(leaf_tex, (u + vec2(float(v & 1), float(v >> 1))) * 0.5).r;
	// Thin out towards the card edge so no square outline shows.
	float edge = length((uv - 0.5) * 2.0);
	return a * (1.0 - smoothstep(0.55, 1.0, edge));
}

// Soft 2D value noise from the baked tile, standing in for 3D noise.
float mottle_at(vec3 p) {
	return texture(noise_tex, p.xz * (1.3 / 64.0) + p.y * 0.013).b * 0.6
		+ texture(noise_tex, p.zx * (4.1 / 64.0) + p.y * 0.029).b * 0.4;
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
#ifndef FAR
	// Keep the outward blob normal on both faces of the leaf cards.
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
#endif
	float mottle = mottle_at(leaf_pos);
	// The instance colour is linear. The Compatibility renderer lights and
	// outputs in sRGB, so there it goes back to sRGB or the leaves come out
	// almost black.
	vec3 leaf = COLOR.rgb;
	if (OUTPUT_IS_SRGB) {
		leaf = mix(leaf * 12.92, 1.055 * pow(leaf, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), leaf));
	}
	vec3 col = leaf * mix(0.45, 1.1, height_shade);
#ifndef FAR
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
#else
	// Far off: leaf clumps and the gaps between them, painted on the blob.
	float clumps = texture(leaf_tile, leaf_pos.xz * 0.45 + vec2(leaf_pos.y * 0.3)).r;
	col *= mix(0.72, 1.06, clumps);
#endif
	col *= 0.8 + 0.35 * mottle;
	ALBEDO = col;
	ROUGHNESS = 0.85;
	SPECULAR = 0.2;
	BACKLIGHT = leaf * 0.3;
}
