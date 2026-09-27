// Tufts of long grass: three crossed cards cut into tapering blades, dark at
// the root and pale at the tips, bending in the wind. Colour comes from the
// MultiMesh instance colour.
shader_type spatial;
render_mode diffuse_burley, cull_disabled;

uniform float blades = 14.0;
uniform float wind_strength = 0.12;

varying float seed;

float hash(float x) {
	return fract(sin(x * 127.1) * 43758.5453);
}

void vertex() {
	seed = fract(dot(MODEL_MATRIX[3].xyz, vec3(0.37, 0.0, 0.61)));
	float bend = pow(1.0 - UV.y, 2.0);  // UV.y is 0 at the top of the card
	float phase = seed * 6.2832;
	vec2 w = vec2(sin(TIME * 1.7 + phase + VERTEX.x), cos(TIME * 1.3 + phase)) * wind_strength;
	VERTEX.xz += w * bend;
	// Normals point up so the tuft lights like the ground it grows from.
	NORMAL = normalize(vec3(0.0, 1.0, 0.0) + NORMAL * 0.3);
}

void fragment() {
	// Both sides of a card light the same way (the back face would otherwise
	// get a flipped, downward normal and go black).
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	float x = UV.x * blades;
	float i = floor(x);
	float r = hash(i + seed * 17.0);
	float height = 0.55 + 0.45 * r;               // blade length, as a share of the card
	float along = 1.0 - UV.y;                     // 0 at the root, 1 at the card top
	float lean = (hash(i + 3.7 + seed) - 0.5) * 0.6 * along;
	float centre = 0.5 + lean;
	float half_w = 0.22 * (1.0 - along / height);  // tapering blade
	float blade = step(abs(fract(x) - centre), half_w) * step(along, height);
	ALPHA = blade;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	vec3 col = COLOR.rgb * mix(0.45, 1.15, along / height);
	col *= 0.9 + 0.2 * r;
	ALBEDO = col;
	ROUGHNESS = 0.9;
	SPECULAR = 0.2;
	BACKLIGHT = COLOR.rgb * 0.5;
}
