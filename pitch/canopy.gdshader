// Low-detail tree canopy: a sphere pushed into lumps by noise, shaded darker
// underneath. Leaf colour comes from the MultiMesh instance colour.
shader_type spatial;
render_mode diffuse_burley;

uniform float lumpiness = 0.28;
uniform float leaf_scale = 1.6;

varying float height_shade;
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

void vertex() {
	vec3 seed = MODEL_MATRIX[3].xyz * 0.173;
	float n = noise3(VERTEX * 1.7 + seed) * 0.7 + noise3(VERTEX * 3.9 + seed) * 0.3;
	VERTEX += NORMAL * (n - 0.45) * lumpiness * 2.0;
	height_shade = clamp(VERTEX.y * 0.5 + 0.5, 0.0, 1.0);
	leaf_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float leaves = noise3(leaf_pos * leaf_scale) * 0.6 + noise3(leaf_pos * leaf_scale * 3.1) * 0.4;
	vec3 col = COLOR.rgb * mix(0.5, 1.12, height_shade);
	col *= 0.75 + 0.45 * leaves;
	ALBEDO = col;
	ROUGHNESS = 0.9;
	SPECULAR = 0.15;
	BACKLIGHT = COLOR.rgb * 0.35;
}
