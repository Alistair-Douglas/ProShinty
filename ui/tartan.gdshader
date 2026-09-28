shader_type canvas_item;
// A woven tartan in heather, moss and night blue: the sett is read along x
// for the warp and along y for the weft, and a 2/2 twill picks which thread
// shows at each pixel. Used for the thin accent strips on the menus.

uniform float thread_px = 2.0;
uniform float opacity : hint_range(0.0, 1.0) = 1.0;
uniform vec4 c_dark : source_color = vec4(0.06, 0.09, 0.14, 1.0);
uniform vec4 c_moss : source_color = vec4(0.13, 0.27, 0.2, 1.0);
uniform vec4 c_heather : source_color = vec4(0.47, 0.3, 0.68, 1.0);
uniform vec4 c_gold : source_color = vec4(1.0, 0.78, 0.18, 1.0);

// Sett (in threads): dark 12, moss 16, dark 4, heather 10, dark 4, gold 2.
vec4 sett(float t) {
	float s = mod(t, 48.0);
	if (s < 12.0) return c_dark;
	if (s < 28.0) return c_moss;
	if (s < 32.0) return c_dark;
	if (s < 42.0) return c_heather;
	if (s < 46.0) return c_dark;
	return c_gold;
}

void fragment() {
	vec2 p = floor(FRAGCOORD.xy / thread_px);
	vec4 warp = sett(p.x);
	vec4 weft = sett(p.y);
	bool over = mod(p.x + p.y, 4.0) < 2.0;
	vec4 c = over ? warp : weft;
	c.rgb = mix(c.rgb, (warp.rgb + weft.rgb) * 0.5, 0.35);
	COLOR = vec4(c.rgb, opacity * COLOR.a);
}
