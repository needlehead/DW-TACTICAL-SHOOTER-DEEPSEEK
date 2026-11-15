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
## Used only when the weapon has no ads_sprite/aim_sprites: zoom and shift the hip frame toward centre.
@export var mode_switch_rot := -0.07  ## radians the gun twists while flicking the fire selector
@export var mode_switch_drop := Vector2(0.02, 0.035)  ## screen heights right/down at the peak of the flick
## Lower stances pull the gun in toward the face (Insurgency-style). Blends with eye height, so it follows
## the stance change smoothly. Values are at full prone; crouch gets about 40% of them.
@export var low_stance_zoom := 0.14
@export var low_stance_shift := Vector2(-0.04, 0.02)  ## screen heights (x left/right, y down)
@export var ads_zoom := 0.12
@export var ads_shift := Vector2(-0.1, -0.03)

var _blur := ShaderMaterial.new()
var _holo := HoloSight.new()
var _scope := ScopeView.new()

@onready var player: Player = owner
@onready var viewmodel: Node3D = owner.get_node("LeanPivot/Head/Camera3D/Viewmodel")


func _ready() -> void:
	_blur.shader = preload("res://player/motion_blur.gdshader")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	# Always attached (2 identical taps when idle) so the shader compiles at load, not on the first shot.
	material = _blur
	add_child(_holo)
	add_child(_scope)


## Sway, bob, inertia (and the gun's freeaim) as a screen offset (pixels); anything held in the hands uses it.
## The phone passes with_freeaim = false: the aim deadzone belongs to the gun, not the off hand.
func hand_offset(k: float, with_freeaim := true) -> Vector2:
	var sway: Vector2 = viewmodel.sway
	var bob: Vector3 = viewmodel.bob
	var inertia: Vector3 = viewmodel.inertia_offset
	var fa := Vector2(deg_to_rad(player.freeaim.x), deg_to_rad(player.freeaim.y)) * freeaim_scale if with_freeaim else Vector2.ZERO
	return Vector2(
		-sway.x * sway_scale + bob.x * bob_scale + inertia.x * inertia_scale - fa.x,
		-sway.y * sway_scale - bob.y * bob_scale - inertia.y * inertia_scale - fa.y) * k


func _process(_delta: float) -> void:
	var w := player.weapons.current
	texture = w.current_sprite(player.ads_blend)
	visible = texture != null and player.alive
	if not visible:
		return
	var d := w.data
	var vp := get_viewport_rect().size
	var k := vp.y
	var ads := 0.0 if d.ads_sprite or not d.aim_sprites.is_empty() else player.ads_blend
	var kick: Vector3 = viewmodel.kick_pos
	var kick_rot: Vector3 = viewmodel.kick_rot
	var lower: float = viewmodel.lower

	var off := hand_offset(k) + Vector2(0.0, kick.z * kick_scale + lower * lower_drop + player.sprint_blend * sprint_drop) * k
	off += Vector2(ads_shift.x * vp.x, ads_shift.y * k) * ads + d.sprite_offset * k
	var flick := sin(PI * clampf(w.since_mode_switch / d.mode_switch_time, 0.0, 1.0))
	# 0 standing .. 1 prone; released while aiming down sights so the sight alignment holds.
	var low := clampf((player.eye_heights[0] - player.eye_height) / (player.eye_heights[0] - player.eye_heights[2]), 0.0, 1.0)
	low *= 1.0 - player.ads_blend
	off += low_stance_shift * k * low
	off += mode_switch_drop * k * flick

	size = vp * (1.0 + overscan)
	var base := Vector2(-vp.x * overscan * 0.5, 0.0)  # overscan hangs below the screen
	var frames := w.aim_frames()
	var window := w.aim_window()
	if not frames.is_empty() and window.has_area():
		# Slide the frame so the sight glass ends up on the screen centre (the aim point once fully aimed).
		var sight := base + window.get_center() * size + d.sprite_offset * k
		off += (vp * 0.5 - sight) * w.sight_progress(player.ads_blend)
	position = base + off
	pivot_offset = Vector2(size.x * 0.5, size.y)
	scale = Vector2.ONE * (1.0 + ads_zoom * ads) * (1.0 + low_stance_zoom * low)
	rotation = kick_rot.z * 0.5 + player.sprint_blend * 0.08 + mode_switch_rot * flick

	var shooting := texture == d.shoot_sprite and d.shoot_blur > 0.0
	var fade := 1.0 - w.since_shot / d.shoot_frame_time if shooting else 0.0
	# Angle in image space (counter-clockwise from +x); UV y points down and is scaled by the frame aspect.
	var a := deg_to_rad(d.shoot_blur_angle)
	var aspect := float(texture.get_width()) / texture.get_height()
	_blur.set_shader_parameter("blur_dir", Vector2(cos(a), -sin(a) * aspect) * d.shoot_blur * fade)
	_blur.set_shader_parameter("samples", 12 if shooting else 2)

	var aimed: bool = window.has_area() and not frames.is_empty() and texture == frames.back()
	var dot_size := d.canted_dot_size if w.using_canted() else d.reticle_size
	_holo.visible = aimed and dot_size > 0.0
	if _holo.visible:
		_holo.position = window.position * size
		_holo.size = window.size * size
		_holo.diameter = dot_size * k
		_holo.color = d.canted_dot_color if w.using_canted() else d.reticle_color
		_holo.dot_only = w.using_canted()
		_holo.queue_redraw()
	_scope.visible = aimed and not w.using_canted() and d.scope_magnification > 0.0
	if _scope.visible:
		_scope.position = window.position * size
		_scope.size = window.size * size
		_scope.magnification = d.scope_magnification
		_scope.reticle_color = d.reticle_color
		_scope.follow(player)
