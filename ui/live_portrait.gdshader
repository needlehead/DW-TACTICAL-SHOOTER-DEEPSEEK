shader_type canvas_item;
// Live2D-style idle on a single flat render: the picture is warped per pixel by soft regions instead of cut
// into parts. Breathing lifts the upper body and swells the chest, the head tilts and turns toward the mouse
// around the neck, the hair drifts, the whole body sways a hair over the feet. Points are in texture UV.

uniform vec2 look = vec2(0.0);  // mouse, -1..1 from the screen centre (smoothed by the script)
uniform vec2 head = vec2(0.465, 0.12);  // head centre
uniform vec2 neck = vec2(0.465, 0.21);  // head pivot
uniform vec2 chest = vec2(0.47, 0.33);
uniform float head_radius = 0.11;  // in screen-height units
uniform float chest_radius = 0.16;
uniform float breath_period = 3.6;  // seconds
uniform float breath = 0.004;  // upper body lift, UV
uniform float swell = 0.012;  // chest widening
uniform float head_tilt = 0.035;  // radians from the idle drift + mouse
uniform float head_turn = 0.012;  // UV the head shifts toward the mouse
uniform float hair = 0.0015;
uniform float sway = 0.004;  // whole body rotation over the feet, radians
uniform float parallax = 0.006;  // whole picture shift toward the mouse

vec2 rot(vec2 p, vec2 pivot, float a, float aspect) {
	vec2 d = (p - pivot) * vec2(aspect, 1.0);
	d = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a))) * d;
	return pivot + d / vec2(aspect, 1.0);
}

float blob(vec2 uv, vec2 c, float r, float aspect) {
	return 1.0 - smoothstep(r * 0.4, r, length((uv - c) * vec2(aspect, 1.0)));
}

void fragment() {
	float aspect = TEXTURE_PIXEL_SIZE.y / TEXTURE_PIXEL_SIZE.x;
	float t = TIME;
	float b = sin(TAU * t / breath_period);
	float b01 = b * 0.5 + 0.5;
	// Each step maps the output pixel back to where it comes from in the picture (inverse warp, so signs flip).
	vec2 uv = UV - look * parallax;
	uv = rot(uv, vec2(0.5, 1.0), -(sin(t * 0.45) * sway + look.x * sway * 0.5), aspect);
	float upper = smoothstep(0.7, 0.25, uv.y);  // hips down stay planted
	uv.y += b01 * breath * upper;
	float wc = blob(uv, chest, chest_radius, aspect);
	uv.x -= (uv.x - chest.x) * swell * b01 * wc;
	uv.y += (uv.y - chest.y) * swell * 0.5 * b01 * wc;
	float wh = blob(uv, head, head_radius, aspect);
	float tilt = (sin(t * 0.7) * 0.4 + sin(t * 0.31) * 0.6) * head_tilt * 0.5 + look.x * head_tilt;
	uv = mix(uv, rot(uv, neck, -tilt, aspect), wh);
	uv -= look * vec2(1.0, 0.6) * head_turn * wh;
	float wt = smoothstep(0.22, 0.02, uv.y) * wh;  // hair: the top of the head
	uv.x -= sin(t * 1.3 + uv.y * 30.0) * hair * wt;
	vec4 c = texture(TEXTURE, uv);
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) c.a = 0.0;
	COLOR = c;  // COLOR arrives pre-filled with the unwarped sample: replace it, never multiply
}
