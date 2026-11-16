shader_type canvas_item;
// Low stamina: the edges of the view drain of colour and darken (tunnel vision), breathing in and out with her.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform float strength = 0.0;  // 0 rested .. 1 empty
uniform float pulse = 0.0;  // 0..1 with the breath (1 = inhale: the tunnel closes in a little)
uniform float darken = 1.0;  // edge darkening share; lowered while badly hurt so the red damage warning stays clear

void fragment() {
	vec3 col = texture(screen_tex, SCREEN_UV).rgb;
	vec2 d = (SCREEN_UV - 0.5) * vec2(SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x, 1.0);
	float r = length(d);  // 0.5 at top/bottom middle, ~1 in the corners
	float edge = smoothstep(0.32 - 0.08 * pulse, 0.95, r) * strength;
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(lum), clamp(edge * 1.2, 0.0, 0.85));
	col *= 1.0 - edge * (0.5 + 0.2 * pulse) * darken;
	COLOR = vec4(col, 1.0);
}
