// Sea and river water: small moving waves, a fresnel blend from the water's
// own colour (looking down) to the sky (looking across it), and sun glints.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec3 deep_color : source_color = vec3(0.1, 0.2, 0.28);
uniform vec3 sky_color : source_color = vec3(0.62, 0.74, 0.86);
uniform float roughness = 0.08;
uniform float wave_scale = 0.35;    // wave pattern frequency, per metre
uniform float wave_speed = 0.6;
uniform vec2 flow = vec2(0.0, 0.0); // river current, metres per second

varying vec3 world_pos;

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

float waves(vec2 p) {
	float t = TIME * wave_speed;
	vec2 q = p - flow * TIME;
	return vnoise(q * wave_scale + vec2(t, t * 0.4)) * 0.5
			+ vnoise(q * wave_scale * 2.3 - vec2(t * 0.7, -t * 0.5)) * 0.3
			+ vnoise(q * wave_scale * 5.1 + vec2(-t * 1.3, t)) * 0.2;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	float e = 0.15;
	float h0 = waves(p);
	float hx = waves(p + vec2(e, 0.0));
	float hz = waves(p + vec2(0.0, e));
	// Fade the ripples out in the distance so they don't shimmer.
	float fade = 1.0 - smoothstep(60.0, 900.0, length(world_pos - CAMERA_POSITION_WORLD));
	vec2 slope = vec2(hx - h0, hz - h0) / e * 0.35 * fade;
	NORMAL_MAP = normalize(vec3(-slope.x, -slope.y, 1.0)) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.0;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	ALBEDO = mix(deep_color, sky_color, fres * 0.8);
	ROUGHNESS = roughness;
	SPECULAR = 0.6;
	METALLIC = 0.0;
}
