shader_type canvas_item;
// Scope lens: masks the picture-in-picture view to a circle, darkens toward the rim, and adds the
// "scope shadow" a real optic shows when your eye is off its axis (eye_offset, in lens radii).

uniform vec2 eye_offset = vec2(0.0);
uniform float rim_softness = 0.03;

void fragment() {
	vec2 d = UV * 2.0 - 1.0;
	float r = length(d);
	float mask = 1.0 - smoothstep(1.0 - rim_softness, 1.0, r);
	float shadow = smoothstep(0.6, 1.05, length(d - eye_offset));
	// COLOR already holds the view texture here; scale it, don't multiply by it again.
	vec3 col = COLOR.rgb * (1.0 - 0.95 * shadow) * (1.0 - 0.3 * r * r);
	COLOR = vec4(col, mask);
}
