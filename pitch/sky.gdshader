// Scottish summer sky: blue gradient, sun disc and drifting cumulus.
shader_type sky;

uniform vec3 top_color : source_color = vec3(0.16, 0.38, 0.78);
uniform vec3 horizon_color : source_color = vec3(0.63, 0.77, 0.92);
uniform vec3 ground_color : source_color = vec3(0.33, 0.37, 0.30);
uniform vec3 cloud_color : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 cloud_shadow_color : source_color = vec3(0.62, 0.66, 0.74);
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.35;
uniform float cloud_speed = 0.004;
uniform float sun_size = 0.9;       // degrees

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
	for (int i = 0; i < 5; i++) {
		v += a * vnoise(p);
		p = p * 2.07 + vec2(5.3, 1.9);
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 d = EYEDIR;
	float up = clamp(d.y, 0.0, 1.0);
	vec3 col = mix(horizon_color, top_color, pow(up, 0.55));
	col = mix(col, ground_color, smoothstep(0.0, -0.08, d.y));

	if (LIGHT0_ENABLED) {
		float sd = dot(d, LIGHT0_DIRECTION);
		float disc_edge = cos(radians(sun_size));
		col += LIGHT0_COLOR * LIGHT0_ENERGY * smoothstep(disc_edge - 0.0004, disc_edge, sd) * 4.0;
		col += LIGHT0_COLOR * pow(max(sd, 0.0), 60.0) * 0.25 * LIGHT0_ENERGY;
	}

	if (d.y > 0.0 && cloud_cover > 0.0) {
		vec2 uv = d.xz / (d.y + 0.12) * 1.3 + vec2(TIME * cloud_speed, 0.0);
		float n = fbm(uv);
		float lo = 1.0 - cloud_cover;
		float c = smoothstep(lo * 0.75, lo * 0.75 + 0.22, n);
		float body = smoothstep(lo * 0.75, lo * 0.75 + 0.45, fbm(uv + vec2(0.04, 0.03)));
		vec3 cc = mix(cloud_color, cloud_shadow_color, body * 0.8);
		col = mix(col, cc, c * smoothstep(0.0, 0.1, d.y));
	}
	COLOR = col;
}
