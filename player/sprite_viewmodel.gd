extends TextureRect
## Doom-style 2D viewmodel. Shows the active weapon's frame (idle / shoot / reload / ADS) and moves it
## with the same sway, bob, inertia, kick and lowering the 3D viewmodel computes. Shoot frames get a
## directional motion blur that fades over the frame. Hidden for weapons without sprites (greybox 3D gun instead).

## Extra size around the screen so bob and kick never reveal the frame's cut-off bottom edge.
@export var overscan := 0.1
## Screen heights of movement per unit of each 3D pose component.
@export var sway_scale := 1.2
@export var bob_scale := 2.5
@export var inertia_scale := 1.0
@export var freeaim_scale := 1.5
@export var kick_scale := 1.5
@export var lower_drop := 0.6
@export var sprint_drop := 0.12
## Used only when the weapon has no ads_sprite: zoom and shift the hip frame toward centre.
@export var ads_zoom := 0.12
@export var ads_shift := Vector2(-0.1, -0.03)

var _blur := ShaderMaterial.new()

@onready var player: Player = owner
@onready var viewmodel: Node3D = owner.get_node("LeanPivot/Head/Camera3D/Viewmodel")


func _ready() -> void:
	_blur.shader = preload("res://player/motion_blur.gdshader")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	# Always attached (2 identical taps when idle) so the shader compiles at load, not on the first shot.
	material = _blur


func _process(_delta: float) -> void:
	var w := player.weapons.current
	texture = w.current_sprite(player.ads_blend)
	visible = texture != null and player.alive
	if not visible:
		return
	var d := w.data
	var vp := get_viewport_rect().size
	var k := vp.y
	var ads := 0.0 if d.ads_sprite else player.ads_blend
	var sway: Vector2 = viewmodel.sway
	var bob: Vector3 = viewmodel.bob
	var inertia: Vector3 = viewmodel.inertia_offset
	var kick: Vector3 = viewmodel.kick_pos
	var kick_rot: Vector3 = viewmodel.kick_rot
	var lower: float = viewmodel.lower

	var off := Vector2(
		-sway.x * sway_scale + bob.x * bob_scale + inertia.x * inertia_scale - deg_to_rad(player.freeaim.x) * freeaim_scale,
		-sway.y * sway_scale - bob.y * bob_scale - inertia.y * inertia_scale - deg_to_rad(player.freeaim.y) * freeaim_scale
			+ kick.z * kick_scale + lower * lower_drop + player.sprint_blend * sprint_drop) * k
	off += Vector2(ads_shift.x * vp.x, ads_shift.y * k) * ads + d.sprite_offset * k

	size = vp * (1.0 + overscan)
	position = Vector2(-vp.x * overscan * 0.5, 0.0) + off  # overscan hangs below the screen
	pivot_offset = Vector2(size.x * 0.5, size.y)
	scale = Vector2.ONE * (1.0 + ads_zoom * ads)
	rotation = kick_rot.z * 0.5 + player.sprint_blend * 0.08

	var shooting := texture == d.shoot_sprite and d.shoot_blur > 0.0
	var fade := 1.0 - w.since_shot / d.shoot_frame_time if shooting else 0.0
	# Angle in image space (counter-clockwise from +x); UV y points down and is scaled by the frame aspect.
	var a := deg_to_rad(d.shoot_blur_angle)
	var aspect := float(texture.get_width()) / texture.get_height()
	_blur.set_shader_parameter("blur_dir", Vector2(cos(a), -sin(a) * aspect) * d.shoot_blur * fade)
	_blur.set_shader_parameter("samples", 12 if shooting else 2)
