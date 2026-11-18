shader_type canvas_item;
// Dialogue backdrop: the game behind, heavily blurred (the screen's mip levels) and a little darkened.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform float blur_lod = 4.5;
uniform float dim = 0.85;
uniform float amount : hint_range(0.0, 1.0) = 1.0;  // fades in / out

void fragment() {
	vec3 sharp = texture(screen_tex, SCREEN_UV).rgb;
	vec3 soft = textureLod(screen_tex, SCREEN_UV, blur_lod).rgb * dim;
	COLOR = vec4(mix(sharp, soft, amount), 1.0);
}
