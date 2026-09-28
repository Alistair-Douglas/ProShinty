shader_type canvas_item;
// Darkens the 3D scene behind the menus so text reads: a shade from the left
// (hub), from the bottom (team select), a vignette, and a slow diagonal
// light sweep with fine slanted lines for a broadcast-graphics feel.

uniform float left_shade : hint_range(0.0, 1.0) = 0.85;
uniform float bottom_shade : hint_range(0.0, 1.0) = 0.6;
uniform float full_shade : hint_range(0.0, 1.0) = 0.0;
uniform vec4 ink : source_color = vec4(0.04, 0.066, 0.086, 1.0);

void fragment() {
	vec2 uv = UV;
	float a = 0.0;
	a = max(a, left_shade * (1.0 - smoothstep(0.08, 0.62, uv.x)));
	a = max(a, bottom_shade * smoothstep(0.45, 1.0, uv.y));
	a = max(a, 0.55 * smoothstep(0.18, 0.0, uv.y));
	vec2 c = uv - 0.5;
	a = max(a, smoothstep(0.35, 0.85, length(c * vec2(1.0, 0.8))) * 0.7);
	a = mix(a, 1.0, full_shade * 0.8);
	// Slanted pinstripes, very faint.
	float lines = step(0.5, fract((FRAGCOORD.x + FRAGCOORD.y * 0.45) / 6.0));
	a += lines * 0.04 * a;
	// Light sweep.
	float sweep = fract(TIME * 0.05);
	float d = abs((uv.x + uv.y * 0.45) * 0.7 - (sweep * 2.2 - 0.6));
	float glow = smoothstep(0.12, 0.0, d) * 0.06;
	COLOR = vec4(ink.rgb + vec3(glow * 3.0), clamp(a + glow, 0.0, 1.0));
}
