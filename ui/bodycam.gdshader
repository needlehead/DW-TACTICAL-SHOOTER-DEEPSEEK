shader_type canvas_item;
// Bodycam post-process: wide-lens barrel distortion, edge chromatic aberration, over-sharpening,
// washed-out grade, vignette and grain. Reads everything drawn below it (3D world + weapon sprite).

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform float distortion : hint_range(0.0, 1.0) = 0.22;  // barrel strength; corners stay pinned to corners
uniform float aberration : hint_range(0.0, 0.03) = 0.006;  // R/B split, grows toward the edges
uniform float sharpen : hint_range(0.0, 2.0) = 0.6;
uniform float saturation : hint_range(0.0, 1.5) = 0.9;
uniform float contrast : hint_range(0.5, 1.5) = 1.12;
uniform float brightness : hint_range(-0.2, 0.2) = 0.0;
uniform float highlight_knee : hint_range(0.5, 1.0) = 0.75;  // brightness above this rolls off softly instead of clipping
uniform vec3 tint = vec3(0.98, 1.0, 1.02);
uniform float vignette : hint_range(0.0, 1.0) = 0.55;
uniform float grain : hint_range(0.0, 0.3) = 0.05;
// The tablet (frame + hands) is kept free of colour fringing: Phone passes its frame texture and the screen -> frame
// transform; where the frame is opaque, aberration is off. Everything else of the lens still applies to it.
uniform bool tablet_on = false;
uniform sampler2D tablet_tex : filter_linear, repeat_disable;
uniform vec2 tablet_x = vec2(1.0, 0.0);  // inverse transform columns (viewport pixels -> frame local)
uniform vec2 tablet_y = vec2(0.0, 1.0);
uniform vec2 tablet_o = vec2(0.0);
uniform vec2 tablet_size = vec2(1.0);
uniform vec2 view_size = vec2(1.0);

// Must match Bodycam.distort() in bodycam.gd (used to place HUD markers).
vec2 distort(vec2 uv, float aspect) {
	vec2 d = uv - 0.5;
	vec2 da = d * vec2(aspect, 1.0);
	float corner = (aspect * aspect + 1.0) * 0.25;
	return 0.5 + d * (1.0 + distortion * dot(da, da)) / (1.0 + distortion * corner);
}

float tablet_mask(vec2 uv) {
	if (!tablet_on) return 0.0;
	vec2 p = uv * view_size;
	vec2 f = (tablet_x * p.x + tablet_y * p.y + tablet_o) / tablet_size;
	if (f.x < 0.0 || f.x > 1.0 || f.y < 0.0 || f.y > 1.0) return 0.0;
	return texture(tablet_tex, f).a;
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
	// No split on the tablet, and none that would pull the tablet's colours out past its outline.
	vec2 uv_r = 0.5 + from_c * (1.0 + aberration);
	vec2 uv_b = 0.5 + from_c * (1.0 - aberration);
	float m = tablet_mask(uv);
	col.r = mix(texture(screen_tex, uv_r).r, col.r, max(m, tablet_mask(uv_r)));
	col.b = mix(texture(screen_tex, uv_b).b, col.b, max(m, tablet_mask(uv_b)));

	// Unsharp mask: cheap cameras over-sharpen.
	vec3 blur = (texture(screen_tex, uv + vec2(px.x, 0.0) * 1.5).rgb + texture(screen_tex, uv - vec2(px.x, 0.0) * 1.5).rgb
		+ texture(screen_tex, uv + vec2(0.0, px.y) * 1.5).rgb + texture(screen_tex, uv - vec2(0.0, px.y) * 1.5).rgb) * 0.25;
	col += (col - blur) * sharpen * (1.0 - m);  // the tablet screen is already crisp: oversharpening only rings its text

	// Grade brightness only, keeping each pixel's colour ratios, with a soft shoulder: per-channel contrast clipped
	// light skin's red first and washed it out to pale peach.
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(lum), col, saturation);
	float graded = (lum - 0.5) * contrast + 0.5 + brightness;
	if (graded > highlight_knee) {
		float e = graded - highlight_knee;
		graded = highlight_knee + e / (1.0 + e / (1.0 - highlight_knee));
	}
	col += graded - lum;  // shift, not scale: scaling blew up colour fringes on near-black pixels
	col *= tint;

	float edge = dot(SCREEN_UV - 0.5, SCREEN_UV - 0.5) * 2.0;  // 0 centre, 1 corner
	col *= 1.0 - vignette * smoothstep(0.25, 1.0, edge);
	col += (hash(SCREEN_UV * 1000.0 + fract(TIME * 7.13)) - 0.5) * grain * (1.0 - 0.7 * m);  // less noise over the tablet

	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
