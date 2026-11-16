shader_type canvas_item;
// Night vision through PVS-15-style dual tubes (drawn under the bodycam: it is what her eyes see). The world is
// already amplified by the camera's exposure (NightVision.exposure); this pass maps light onto the phosphor with a
// soft shoulder (bright scenes wash out), blooms around bright sources, adds tube grain and scintillation, softens a
// little, and limits the view to two overlapping round tubes with dark housing around them.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform float strength : hint_range(0.0, 1.0) = 1.0;  // 0 = off, 1 = full (fades in as the tubes power up)
uniform float gain = 2.0;  // phosphor response to light; higher = brighter, washes out sooner
uniform vec3 phosphor : source_color = vec3(0.78, 1.0, 0.82);  // green-white
uniform float bloom = 1.2;  // halo strength around bright light (flashlight, muzzle flash, lit doorways)
uniform float grain = 0.13;
uniform float tube_radius = 0.44;  // per tube, fraction of screen height
uniform float tube_offset = 0.2;  // tube centres left / right of the screen centre, fraction of screen height
uniform float housing = 0.04;  // how much of the unaided view shows around the tubes

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
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
	// Bloom: bright light in a ring around this pixel spills into it.
	float glow = 0.0;
	for (int i = 0; i < 8; i++) {
		float a = float(i) * 0.785398;
		for (int r = 1; r <= 2; r++) {
			vec2 o = vec2(cos(a), sin(a)) * float(r) * 0.018 * vec2(px.x / px.y, 1.0);
			glow += max(luma(texture(screen_tex, uv + o).rgb) - 0.65, 0.0) / float(r);
		}
	}
	float v = 1.0 - exp(-(l * gain + glow * bloom * 0.25));
	vec2 cell = floor(uv / px * 0.5);  // grain at half resolution, re-rolled ~30 times a second
	float t = floor(TIME * 30.0);
	v += (hash(cell + t) - 0.5) * grain;
	v += step(0.9985, hash(cell * 1.7 + t * 3.1)) * 0.6;  // scintillation: sparse bright specks
	vec3 nv = phosphor * clamp(v, 0.0, 1.2);

	// Two round tubes side by side, slightly darker toward their rims.
	vec2 p = (uv - 0.5) * vec2(px.y / px.x, 1.0);
	float d = min(length(p - vec2(-tube_offset, 0.0)), length(p - vec2(tube_offset, 0.0)));
	float inside = 1.0 - smoothstep(tube_radius - 0.012, tube_radius, d);
	nv *= mix(0.6, 1.0, 1.0 - smoothstep(tube_radius * 0.55, tube_radius, d));
	vec3 through = mix(raw * housing, nv, inside);
	COLOR = vec4(mix(raw, through, strength), 1.0);
}
