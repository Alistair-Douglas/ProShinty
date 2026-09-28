shader_type spatial;
// Spectators drawn as MultiMeshes (see crowd.gd). Each mesh vertex says which
// part it belongs to in UV.x (0 jacket, 1 trousers, 2 skin, 3 hair or hat,
// 4 wheelchair and shoes, 5 scarf) and, for arm vertices, which arm in UV.y (-1 left,
// +1 right) and the shoulder it swings about in UV2. Vertex alpha 0 means
// the figure stays put when cheering (a wheelchair user).
// Per spectator: COLOR is the jacket colour; INSTANCE_CUSTOM holds
// r = trousers index, g = skin index, b = hair index (6 = hat), a = who they
// support (0 neutral, 1 home, 2 away) plus a phase in the fraction.
render_mode cull_back, diffuse_lambert, specular_disabled;

uniform float cheer_home : hint_range(0.0, 1.0) = 0.0;
uniform float cheer_away : hint_range(0.0, 1.0) = 0.0;
// Each team's second colour, for supporters' scarves and hats.
uniform vec3 home_second : source_color = vec3(1.0);
uniform vec3 away_second : source_color = vec3(1.0);

varying vec3 v_color;

const vec3 TROUSERS[6] = vec3[](vec3(0.1, 0.12, 0.2), vec3(0.18, 0.18, 0.19), vec3(0.3, 0.26, 0.2),
		vec3(0.07, 0.07, 0.08), vec3(0.22, 0.3, 0.42), vec3(0.35, 0.33, 0.3));
const vec3 SKIN[5] = vec3[](vec3(0.93, 0.76, 0.62), vec3(0.86, 0.66, 0.52), vec3(0.95, 0.8, 0.7),
		vec3(0.62, 0.44, 0.32), vec3(0.8, 0.6, 0.46));
const vec3 HAIR[6] = vec3[](vec3(0.12, 0.09, 0.07), vec3(0.3, 0.2, 0.12), vec3(0.55, 0.5, 0.45),
		vec3(0.62, 0.35, 0.15), vec3(0.1, 0.12, 0.22), vec3(0.45, 0.1, 0.1));

void vertex() {
	vec4 c = INSTANCE_CUSTOM;
	float side = floor(c.a + 0.01);
	float phase = fract(c.a) * 6.2832;
	float cheer = side > 1.5 ? cheer_away : (side > 0.5 ? cheer_home : 0.35 * max(cheer_home, cheer_away));
	int part = int(UV.x + 0.5);
	vec3 v = VERTEX;
	// Arms swing up about the shoulder when cheering.
	if (abs(UV.y) > 0.5) {
		float s = sign(UV.y);
		float a = s * cheer * (2.5 + 0.3 * sin(TIME * 7.0 + phase));
		vec2 pivot = vec2(s * UV2.x, UV2.y);
		vec2 rel = v.xy - pivot;
		float ca = cos(a);
		float sa = sin(a);
		v.xy = pivot + vec2(ca * rel.x - sa * rel.y, sa * rel.x + ca * rel.y);
	}
	// Idle weight shifting, and jumping when cheering.
	float stands = COLOR.a;
	v.x += sin(TIME * 0.7 + phase) * 0.025 * v.y * stands;
	v.y += cheer * abs(sin(TIME * 6.5 + phase)) * 0.18 * stands;
	VERTEX = v;
	vec3 second = side > 1.5 ? away_second : (side > 0.5 ? home_second : COLOR.rgb * 0.6);
	if (part == 1) {
		v_color = TROUSERS[int(c.r + 0.5) % 6];
	} else if (part == 2) {
		v_color = SKIN[int(c.g + 0.5) % 5];
	} else if (part == 3) {
		int h = int(c.b + 0.5);
		v_color = h >= 6 ? second : HAIR[h % 6];
	} else if (part == 4) {
		v_color = vec3(0.1, 0.1, 0.11);
	} else if (part == 5) {
		v_color = second;
	} else {
		v_color = COLOR.rgb;
	}
}

void fragment() {
	ALBEDO = v_color;
	ROUGHNESS = 0.9;
}
