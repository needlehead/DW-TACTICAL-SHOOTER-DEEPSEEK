shader_type canvas_item;
// Directional motion blur for the shoot sprite: averages samples along blur_dir (UV units, full streak length).

uniform vec2 blur_dir = vec2(0.0, 0.025);
uniform int samples : hint_range(2, 32) = 12;
// Muzzle flash lighting the gun: warm light strongest at flash_uv, falling off over flash_radius (frame heights).
uniform vec2 flash_uv = vec2(0.5);
uniform float flash_strength = 0.0;
uniform float flash_radius = 0.35;
uniform float aspect = 1.7778;
uniform vec3 flash_color = vec3(1.0, 0.72, 0.4);
// Defocus (night vision focuses far, so the gun up close goes soft): disc blur radius in frame heights.
uniform float defocus = 0.0;
// Reload crossfade: the next frame dissolved in by next_mix (premultiplied, so a limb moving away fades out too).
uniform sampler2D next_tex : filter_linear;
uniform float next_mix = 0.0;

// Premultiplied blend of this frame's sample c with the next frame at the same UV (TEXTURE can't be passed to a function).
vec4 premix(vec4 c, vec2 uv) {
	vec4 p = vec4(c.rgb * c.a, c.a);
	if (next_mix > 0.0) {
		vec4 n = texture(next_tex, uv);
		p = mix(p, vec4(n.rgb * n.a, n.a), next_mix);
	}
	return p;
}

void fragment() {
	vec4 acc = vec4(0.0);
	for (int i = 0; i < samples; i++) {
		float t = float(i) / float(samples - 1) - 0.5;
		vec2 uv = UV + blur_dir * t;
		acc += premix(texture(TEXTURE, uv), uv);  // premultiplied so transparent edges don't darken the streak
	}
	acc /= float(samples);
	if (defocus > 0.0) {
		vec4 d = acc;
		for (int i = 0; i < 12; i++) {
			float a = float(i) * 0.5235988;  // 12 taps on two rings
			float r = defocus * (i % 2 == 0 ? 1.0 : 0.5);
			vec2 uv = UV + vec2(cos(a) / aspect, sin(a)) * r;
			d += premix(texture(TEXTURE, uv), uv);
		}
		acc = d / 13.0;
	}
	// COLOR already holds the texture sample here; replace it rather than multiply, or colours get squared.
	vec3 col = acc.rgb / max(acc.a, 0.0001);
	float lit = flash_strength * (1.0 - smoothstep(0.0, flash_radius, length((UV - flash_uv) * vec2(aspect, 1.0))));
	COLOR = vec4(col + flash_color * lit * col, acc.a);  // light scales the surface colour (lit, not painted over)
}
