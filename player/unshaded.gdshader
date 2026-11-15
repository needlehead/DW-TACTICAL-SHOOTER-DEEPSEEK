shader_type canvas_item;
// For self-lit overlays (scope view lines, illuminated reticles) on the viewmodel layer: multiplying by the
// inverse of SpriteShadow's tint cancels the CanvasModulate, so they never darken in shade.

uniform vec3 undo_tint = vec3(1.0);

void fragment() {
	COLOR.rgb *= undo_tint;
}
