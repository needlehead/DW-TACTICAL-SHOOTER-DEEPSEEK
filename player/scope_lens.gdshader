shader_type canvas_item;
// Scope lens: masks the picture-in-picture view to a circle, darkens toward the rim, and adds the
// "scope shadow" a real optic shows when your eye is off its axis (eye_offset, in lens radii).

uniform vec2 eye_offset = vec2(0.0);
uniform float rim_softness = 0.03;
uniform vec3 undo_tint = vec3(1.0);  // cancels SpriteShadow's tint: the lens shows the world as lit
uniform float blur = 0.0;  // UV radius; night vision can't focus through a magnified optic

void fragment() {
	vec2 d = UV * 2.0 - 1.0;
	float r = length(d);
	float mask = 1.0 - smoothstep(1.0 - rim_softness, 1.0, r);
	float shadow = smoothstep(0.6, 1.05, length(d - eye_offset));
	// COLOR already holds the view texture here; scale it, don't multiply by it again.
	vec3 view = COLOR.rgb;
	if (blur > 0.0) {
		vec3 acc = view;
		for (int i = 0; i < 16; i++) {
			float a = float(i) * 0.3926991;
			acc += texture(TEXTURE, UV + vec2(cos(a), sin(a)) * blur * (i % 2 == 0 ? 1.0 : 0.55)).rgb;
		}
		view = acc / 17.0;
	}
	vec3 col = view * (1.0 - 0.95 * shadow) * (1.0 - 0.3 * r * r);
	COLOR = vec4(col * undo_tint, mask);
}
