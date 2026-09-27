// Tree trunks and limbs. Colour comes from the MultiMesh instance colour
// (brown bark, white birch, red-brown pine) with vertical streaks and moss
// towards the ground.
shader_type spatial;
render_mode diffuse_burley;

varying vec3 local;

float hash2(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), u.x),
			mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	local = VERTEX;
}

void fragment() {
	float around = atan(local.z, local.x) * 2.0;
	float streak = vnoise(vec2(around * 3.0, local.y * 1.5));
	vec3 col = COLOR.rgb * (0.75 + 0.4 * streak);
	// Birch: dark bands across the white bark.
	float pale = smoothstep(0.35, 0.6, dot(COLOR.rgb, vec3(0.33)));
	float band = step(0.82, vnoise(vec2(around * 1.5, local.y * 18.0)));
	col = mix(col, col * 0.25, band * pale);
	// Moss and damp near the base.
	col = mix(col, vec3(0.12, 0.16, 0.07), smoothstep(-0.2, -0.5, local.y) * 0.5 * (1.0 - pale));
	ALBEDO = col;
	ROUGHNESS = 0.95;
	SPECULAR = 0.1;
}
