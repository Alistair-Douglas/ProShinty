// Scottish summer sky: blue gradient with a hazy horizon, sun disc and glow,
// and two layers of drifting cloud (puffy cumulus and high wisps). Cumulus
// are lit from the sun's side, with grey undersides and bright edges.
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

float fbm(vec2 p, int octaves) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < octaves; i++) {
		v += a * vnoise(p);
		p = p * 2.07 + vec2(5.3, 1.9);
		a *= 0.5;
	}
	return v;
}

float cumulus(vec2 uv, float lo) {
	float n = fbm(uv, 6);
	return smoothstep(lo, lo + 0.18, n);
}

void sky() {
	vec3 d = EYEDIR;
	float up = clamp(d.y, 0.0, 1.0);
	vec3 col = mix(horizon_color, top_color, pow(up, 0.5));
	// Brighter, whiter haze in a thin band at the horizon.
	col = mix(col, mix(horizon_color, vec3(0.92, 0.93, 0.94), 0.4), exp(-up * 28.0) * 0.6);
	col = mix(col, ground_color, smoothstep(0.0, -0.08, d.y));

	vec3 sun_dir = vec3(0.0, 1.0, 0.0);
	vec3 sun_col = vec3(1.0);
	float sun_e = 0.0;
	if (LIGHT0_ENABLED) {
		sun_dir = LIGHT0_DIRECTION;
		sun_col = LIGHT0_COLOR;
		sun_e = LIGHT0_ENERGY;
		float sd = dot(d, sun_dir);
		float disc_edge = cos(radians(sun_size));
		col += sun_col * sun_e * smoothstep(disc_edge - 0.0004, disc_edge, sd) * 4.0;
		col += sun_col * (pow(max(sd, 0.0), 40.0) * 0.3 + pow(max(sd, 0.0), 6.0) * 0.08) * sun_e;
	}

	if (d.y > 0.0 && cloud_cover > 0.0) {
		vec2 base = d.xz / (d.y + 0.12);
		vec2 drift = vec2(TIME * cloud_speed, TIME * cloud_speed * 0.3);
		float fade = smoothstep(0.0, 0.12, d.y);
		// High wispy layer.
		vec2 wuv = base * vec2(0.6, 2.2) + drift * 0.6 + 31.0;
		float wisp = smoothstep(0.55, 0.9, fbm(wuv, 5)) * (0.3 + cloud_cover * 0.4);
		col = mix(col, mix(col, cloud_color, 0.85), wisp * fade);
		// Cumulus: density here, and a step towards the sun for lighting.
		vec2 uv = base * 1.3 + drift;
		float lo = (1.0 - cloud_cover) * 0.75;
		float c = cumulus(uv, lo);
		if (c > 0.001) {
			vec2 to_sun = normalize(sun_dir.xz + vec2(0.0001)) * 0.06;
			float toward = cumulus(uv + to_sun, lo);
			float thick = smoothstep(lo, lo + 0.45, fbm(uv, 4));
			// Lit where the cloud thins towards the sun, grey where it's thick.
			float lit = clamp(0.6 + (c - toward) * 1.6 - thick * 0.35, 0.0, 1.0);
			vec3 cc = mix(cloud_shadow_color, cloud_color, lit);
			cc += sun_col * pow(max(dot(d, sun_dir), 0.0), 8.0) * (1.0 - thick) * 0.35 * sun_e;
			// Distant clouds melt into the haze.
			cc = mix(cc, horizon_color, exp(-up * 9.0) * 0.5);
			col = mix(col, cc, c * fade);
		}
	}
	COLOR = col;
}
