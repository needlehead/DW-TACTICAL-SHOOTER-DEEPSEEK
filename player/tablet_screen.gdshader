shader_type canvas_item;
// The tablet screen: rendered at ~2x the size it shows and averaged down here (4 taps across each screen pixel's
// footprint), so small text stays crisp without stair-steps. Backlit: undo_tint cancels SpriteShadow's darkening.

uniform vec3 undo_tint = vec3(1.0);

void fragment() {
	vec2 f = fwidth(UV) * 0.25;
	vec4 c = texture(TEXTURE, UV + vec2(-f.x, -f.y)) + texture(TEXTURE, UV + vec2(f.x, -f.y))
		+ texture(TEXTURE, UV + vec2(-f.x, f.y)) + texture(TEXTURE, UV + vec2(f.x, f.y));
	COLOR = c * 0.25;
	COLOR.rgb *= undo_tint;
}
