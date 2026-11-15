shader_type canvas_item;
// Damage feedback: red that creeps in from the screen edges. `hit` flashes on each hit and fades; `low` is the
// slow heartbeat pulse at low health.

uniform float hit = 0.0;
uniform float low = 0.0;
uniform vec4 tint : source_color = vec4(0.55, 0.0, 0.02, 1.0);

void fragment() {
	vec2 d = UV - 0.5;
	d.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;  // round, not stretched to the screen's aspect
	float r = length(d);  // 0.5 at top/bottom middle, ~0.9 at the sides, ~1 in the corners
	float edge = smoothstep(0.45, 1.05, r);
	COLOR = vec4(tint.rgb, clamp(edge * (hit * 0.75 + low * 0.65), 0.0, 0.8));
}
