class_name ScopeView
extends Control
## Picture-in-picture magnified optic. A second camera renders the world at `magnification` into a SubViewport
## that is drawn inside the lens of the last aim frame (circle mask, rim vignette, scope shadow when the gun
## sways off your eye) with an ACOG-style reticle on top. Only renders while visible.

const SHADOW_GAIN := 1.6  ## how hard sway pushes the scope shadow in

var magnification := 4.0
var reticle_color := Color(1.0, 0.35, 0.1)

var _vp := SubViewport.new()
var _cam := Camera3D.new()
var _mat := ShaderMaterial.new()
var _reticle := Control.new()
var _reticle_mat := ShaderMaterial.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vp.size = Vector2i(768, 768)
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_vp.add_child(_cam)
	add_child(_vp)
	_cam.current = true  # current inside its own viewport; it shares the level's World3D
	_mat.shader = preload("res://player/scope_lens.gdshader")
	material = _mat
	_reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reticle.set_anchors_preset(Control.PRESET_FULL_RECT)
	_reticle.draw.connect(_draw_reticle)
	_reticle_mat.shader = preload("res://player/unshaded.gdshader")
	_reticle.material = _reticle_mat
	add_child(_reticle)  # own canvas item: not masked by the lens shader


## Point the scope camera along the aim and refresh; call every frame while visible.
func follow(player: Player) -> void:
	_cam.global_transform = Transform3D(player.aim_basis(), player.camera.global_position)
	_cam.fov = player.base_fov / magnification
	_cam.cull_mask = player.camera.cull_mask  # world only, never the viewmodel layer
	_cam.attributes = player.camera.attributes  # amplified with the night vision, like the main view
	var nv := player.get_node("ViewmodelLayer/NightVision") as NightVision
	_mat.set_shader_parameter("blur", nv.scope_blur * nv.strength() if nv else 0.0)
	var centre := get_global_transform() * (size * 0.5)
	var eye := (get_viewport_rect().size * 0.5 - centre) / (size.x * 0.5)
	_mat.set_shader_parameter("eye_offset", eye * SHADOW_GAIN)
	var undo: Vector3 = (player.get_node("ViewmodelLayer/SpriteShadow") as SpriteShadow).undo_tint()
	_mat.set_shader_parameter("undo_tint", undo)
	_reticle_mat.set_shader_parameter("undo_tint", undo)
	queue_redraw()
	_reticle.queue_redraw()


func _process(_delta: float) -> void:
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if is_visible_in_tree() else SubViewport.UPDATE_DISABLED


func _draw() -> void:
	draw_texture_rect(_vp.get_texture(), Rect2(Vector2.ZERO, size), false)


func _draw_reticle() -> void:
	var c := size * 0.5
	var r := size.x * 0.5
	var ink := Color(0.02, 0.02, 0.02, 0.9)
	var w := maxf(1.0, r * 0.008)
	# Hairlines out to the rim and the bullet-drop post below the chevron.
	_reticle.draw_line(c + Vector2(-r, 0), c + Vector2(-r * 0.3, 0), ink, w, true)
	_reticle.draw_line(c + Vector2(r * 0.3, 0), c + Vector2(r, 0), ink, w, true)
	_reticle.draw_line(c + Vector2(0, r * 0.12), c + Vector2(0, r * 0.75), ink, w, true)
	for i in 4:  # drop marks, narrower further down
		var y := r * (0.28 + 0.13 * i)
		var half := r * (0.09 - 0.017 * i)
		_reticle.draw_line(c + Vector2(-half, y), c + Vector2(half, y), ink, w, true)
	# Illuminated chevron: apex is the aim point.
	var glow := Color(reticle_color, 0.3)
	for pass_i in 2:
		var col := glow if pass_i == 0 else reticle_color
		var cw := w * (3.5 if pass_i == 0 else 1.8)
		_reticle.draw_polyline(PackedVector2Array([c + Vector2(-r * 0.07, r * 0.09), c, c + Vector2(r * 0.07, r * 0.09)]), col, cw, true)
