class_name HoloSight
extends Control
## EOTech-style holographic reticle (ring, centre dot, four inward ticks). Child of the sprite viewmodel,
## sized to the sight glass and clipped to it; the reticle sits on the true aim point, so it drifts
## inside the glass with sway instead of being painted onto the frame.

var diameter := 30.0
var color := Color(1.0, 0.2, 0.12)
var dot_only := false  ## plain red dot (diameter = dot size) instead of the EOTech ring


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	var add := ShaderMaterial.new()
	add.shader = preload("res://player/unshaded_add.gdshader")  # light projected on glass: additive, ignores shade
	material = add


func _draw() -> void:
	var player := get_parent().owner as Player
	var cam := player.camera
	var aim := cam.global_position - player.aim_basis().z * 50.0
	if cam.is_position_behind(aim):
		return
	var c := get_global_transform().affine_inverse() * cam.unproject_position(aim)
	(material as ShaderMaterial).set_shader_parameter("undo_tint", (player.get_node("ViewmodelLayer/SpriteShadow") as SpriteShadow).undo_tint())
	var r := diameter * 0.5
	var glow := Color(color, 0.25)
	if dot_only:
		draw_circle(c, r * 2.0, Color(color, 0.18))
		draw_circle(c, r, color)
		return
	for pass_i in 2:
		var col := glow if pass_i == 0 else color
		var wide := 2.5 if pass_i == 0 else 1.0
		draw_arc(c, r, 0.0, TAU, 48, col, maxf(1.0, r * 0.07) * wide, true)
		draw_circle(c, maxf(1.0, r * 0.05) * wide, col)
		for dir: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
			draw_line(c + dir * r, c + dir * r * 0.78, col, maxf(1.0, r * 0.07) * wide, true)
