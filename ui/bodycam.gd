class_name Bodycam
extends ColorRect
## Bodycam look: full-screen post-process over the world and weapon sprite (HUD stays undistorted on
## a higher layer), a REC/timestamp overlay, and a wider FOV while on. F3 toggles it.

@export var enabled := true
@export var bodycam_fov := 95.0  ## vertical FOV while on; the lens magnifies the centre, so go wider
@export var device_label := "UNIT 07"

var _normal_fov := 75.0
var _overlay: Label

@onready var player: Player = owner


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_normal_fov = player.base_fov
	_overlay = Label.new()
	_overlay.add_theme_font_size_override("font_size", 20)
	_overlay.add_theme_color_override("font_color", Color(0.95, 0.95, 0.9))
	_overlay.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_overlay.add_theme_constant_override("outline_size", 4)
	_overlay.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_overlay)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 28)
	_overlay.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_apply()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_bodycam"):
		enabled = not enabled
		_apply()


func _apply() -> void:
	visible = enabled
	player.base_fov = bodycam_fov if enabled else _normal_fov


func _process(_delta: float) -> void:
	if not visible:
		return
	var blink := "●" if int(Time.get_ticks_msec() / 500.0) % 2 == 0 else "  "
	_overlay.text = "%s REC   %s\n%s" % [blink, Time.get_datetime_string_from_system(false, true), device_label]


## Where a point of the undistorted image ends up on screen (inverse of the shader lookup),
## so HUD markers sit on what they point at. Fixed-point iteration; converges fast for mild lenses.
func to_screen(p: Vector2) -> Vector2:
	if not visible:
		return p
	var vp := get_viewport_rect().size
	var target := p / vp
	var uv := target
	for i in 6:
		uv += target - distort(uv, vp.x / vp.y)
	return uv * vp


func distort(uv: Vector2, aspect: float) -> Vector2:
	var param: Variant = (material as ShaderMaterial).get_shader_parameter("distortion")
	var k: float = param if param != null else 0.22
	var d := uv - Vector2(0.5, 0.5)
	var da := d * Vector2(aspect, 1.0)
	var corner := (aspect * aspect + 1.0) * 0.25
	return Vector2(0.5, 0.5) + d * (1.0 + k * da.dot(da)) / (1.0 + k * corner)
