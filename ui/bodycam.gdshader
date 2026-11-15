shader_type canvas_item;
// Bodycam post-process: wide-lens barrel distortion, edge chromatic aberration, over-sharpening,
// washed-out grade, vignette and grain. Reads everything drawn below it (3D world + weapon sprite).

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform float distortion : hint_range(0.0, 1.0) = 0.22;  // barrel strength; corners stay pinned to corners
uniform float aberration : hint_range(0.0, 0.03) = 0.006;  // R/B split, grows toward the edges
uniform float sharpen : hint_range(0.0, 2.0) = 0.6;
uniform float saturation : hint_range(0.0, 1.5) = 0.8;
uniform float contrast : hint_range(0.5, 1.5) = 1.12;
uniform float brightness : hint_range(-0.2, 0.2) = 0.02;
uniform vec3 tint = vec3(0.98, 1.0, 1.02);
uniform float vignette : hint_range(0.0, 1.0) = 0.55;
uniform float grain : hint_range(0.0, 0.3) = 0.05;

// Must match Bodycam.distort() in bodycam.gd (used to place HUD markers).
vec2 distort(vec2 uv, float aspect) {
	vec2 d = uv - 0.5;
	vec2 da = d * vec2(aspect, 1.0);
	float corner = (aspect * aspect + 1.0) * 0.25;
	return 0.5 + d * (1.0 + distortion * dot(da, da)) / (1.0 + distortion * corner);
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE;
	float aspect = px.y / px.x;
	vec2 uv = distort(SCREEN_UV, aspect);
	vec2 from_c = uv - 0.5;

	vec3 col = texture(screen_tex, uv).rgb;
	col.r = texture(screen_tex, 0.5 + from_c * (1.0 + aberration)).r;
	col.b = texture(screen_tex, 0.5 + from_c * (1.0 - aberration)).b;

	// Unsharp mask: cheap cameras over-sharpen.
	vec3 blur = (texture(screen_tex, uv + vec2(px.x, 0.0) * 1.5).rgb + texture(screen_tex, uv - vec2(px.x, 0.0) * 1.5).rgb
		+ texture(screen_tex, uv + vec2(0.0, px.y) * 1.5).rgb + texture(screen_tex, uv - vec2(0.0, px.y) * 1.5).rgb) * 0.25;
	col += (col - blur) * sharpen;

	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(lum), col, saturation);
	col = (col - 0.5) * contrast + 0.5 + brightness;
	col *= tint;

	float edge = dot(SCREEN_UV - 0.5, SCREEN_UV - 0.5) * 2.0;  // 0 centre, 1 corner
	col *= 1.0 - vignette * smoothstep(0.25, 1.0, edge);
	col += (hash(SCREEN_UV * 1000.0 + fract(TIME * 7.13)) - 0.5) * grain;

	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
