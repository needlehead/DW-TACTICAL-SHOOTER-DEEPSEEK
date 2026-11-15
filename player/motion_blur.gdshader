shader_type canvas_item;
// Directional motion blur for the shoot sprite: averages samples along blur_dir (UV units, full streak length).

uniform vec2 blur_dir = vec2(0.0, 0.025);
uniform int samples : hint_range(2, 32) = 12;

void fragment() {
	vec4 acc = vec4(0.0);
	for (int i = 0; i < samples; i++) {
		float t = float(i) / float(samples - 1) - 0.5;
		vec4 c = texture(TEXTURE, UV + blur_dir * t);
		acc += vec4(c.rgb * c.a, c.a);  // premultiply so transparent edges don't darken the streak
	}
	acc /= float(samples);
	// COLOR already holds the texture sample here; replace it rather than multiply, or colours get squared.
	COLOR = vec4(acc.rgb / max(acc.a, 0.0001), acc.a);
}
