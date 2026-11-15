shader_type canvas_item;
render_mode blend_add;
// Additive version of unshaded.gdshader, for the holographic reticle (light projected on glass).

uniform vec3 undo_tint = vec3(1.0);

void fragment() {
	COLOR.rgb *= undo_tint;
}
