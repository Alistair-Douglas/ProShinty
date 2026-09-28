shader_type spatial;
// Face of a pitchside advertising board. Shows tex_a, and while `slide` runs
// from 0 to 1 rolls it up to reveal tex_b, like an LED board changing advert.
// `glow` > 0 makes it light up (LED); 0 is a printed board.

uniform sampler2D tex_a : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_b : source_color, filter_linear_mipmap, repeat_enable;
uniform float repeats = 1.0;
uniform float slide : hint_range(0.0, 1.0) = 0.0;
uniform float glow = 0.0;

void fragment() {
	vec2 uv = vec2(fract(UV.x * repeats), UV.y + slide);
	vec3 c = uv.y < 1.0 ? texture(tex_a, uv).rgb : texture(tex_b, vec2(uv.x, uv.y - 1.0)).rgb;
	// A faint horizontal line pattern on LED boards.
	float scan = glow > 0.0 ? 0.92 + 0.08 * step(0.5, fract(UV.y * 48.0)) : 1.0;
	ALBEDO = c * mix(1.0, 0.55, clamp(glow, 0.0, 1.0)) * scan;
	EMISSION = c * glow * scan;
	ROUGHNESS = glow > 0.0 ? 0.35 : 0.8;
	SPECULAR = 0.3;
}
