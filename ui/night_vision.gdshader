shader_type canvas_item;
// Night vision through PVS-15-style dual tubes (drawn under the bodycam: it is what her eyes see). The world is
// already amplified by the camera's exposure (NightVision.exposure); this pass maps light onto the phosphor with a
// soft shoulder (bright scenes wash out), blooms around bright sources, overlays the faint honeycomb of the tube's
// fibre-optic plate and a slow brightness shimmer, softens a little, and limits the view to two overlapping round
// tubes with dark housing around them.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;  // mips = blurred copies for the halo
uniform float strength : hint_range(0.0, 1.0) = 1.0;  // 0 = off, 1 = full (fades in as the tubes power up)
uniform float gain = 2.0;  // phosphor response to light; higher = brighter, washes out sooner
uniform vec3 phosphor : source_color = vec3(0.78, 1.0, 0.82);  // green-white
uniform float bloom = 1.2;  // halo strength around bright light (flashlight, muzzle flash, lit doorways)
uniform float honeycomb = 0.07;  // strength of the fixed hex fibre pattern
uniform float honeycomb_size = 3.0;  // hex cell size in screen pixels
uniform float shimmer = 0.05;  // slow, soft brightness wander across the tube (no per-pixel noise)
uniform float tube_radius = 0.44;  // per tube, fraction of screen height
uniform float tube_offset = 0.2;  // tube centres left / right of the screen centre, fraction of screen height
uniform float housing = 0.04;  // how much of the unaided view shows around the tubes

// 0 at a hex cell's centre .. 1 at its edge (fibre walls of the tube's fibre-optic plate).
float hex_edge(vec2 p) {
	const vec2 s = vec2(1.0, 1.7320508);
	vec2 a = mod(p, s) - s * 0.5;
	vec2 b = mod(p - s * 0.5, s) - s * 0.5;
	vec2 g = dot(a, a) < dot(b, b) ? a : b;
	vec2 q = abs(g);
	return clamp(max(dot(q, s * 0.5), q.x) * 2.0, 0.0, 1.0);
}

float luma(vec3 c) {
	return dot(c, vec3(0.3, 0.59, 0.11));
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 px = SCREEN_PIXEL_SIZE;
	vec3 raw = texture(screen_tex, uv).rgb;
	// Slight softness: image tubes are never pin sharp.
	vec3 c = (raw * 2.0 + texture(screen_tex, uv + vec2(px.x, 0.0)).rgb + texture(screen_tex, uv - vec2(px.x, 0.0)).rgb
		+ texture(screen_tex, uv + vec2(0.0, px.y)).rgb + texture(screen_tex, uv - vec2(0.0, px.y)).rgb) / 6.0;
	float l = luma(c);
	// Bloom: bright light spills into its surroundings. Read from the screen's blurred mip levels (a smooth halo);
	// sampling a ring of points instead copied thin bright things (laser beams, dots) into ghost lines.
	float glow = max(luma(textureLod(screen_tex, uv, 3.0).rgb) - 0.55, 0.0) * 0.6
		+ max(luma(textureLod(screen_tex, uv, 5.0).rgb) - 0.5, 0.0);
	float v = 1.0 - exp(-(l * gain + glow * bloom));
	vec2 sp = uv / px;  // screen pixels
	v *= 1.0 - honeycomb * smoothstep(0.6, 1.0, hex_edge(sp / honeycomb_size));
	v *= 1.0 + shimmer * sin(TIME * 1.3 + uv.x * 3.0) * sin(TIME * 0.9 - uv.y * 2.5);
	vec3 nv = phosphor * clamp(v, 0.0, 1.2);

	// Two round tubes side by side, slightly darker toward their rims.
	vec2 p = (uv - 0.5) * vec2(px.y / px.x, 1.0);
	float d = min(length(p - vec2(-tube_offset, 0.0)), length(p - vec2(tube_offset, 0.0)));
	float inside = 1.0 - smoothstep(tube_radius - 0.012, tube_radius, d);
	nv *= mix(0.6, 1.0, 1.0 - smoothstep(tube_radius * 0.55, tube_radius, d));
	vec3 through = mix(raw * housing, nv, inside);
	COLOR = vec4(mix(raw, through, strength), 1.0);
}
