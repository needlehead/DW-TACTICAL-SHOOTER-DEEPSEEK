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
@export var sprint_drop := 0.12  ## weapons without a sprint frame
@export var sprint_dip := 0.55  ## weapons with a sprint frame: how far the gun drops while swapping poses
@export var sprint_swap_time := 0.5  ## seconds for the whole dip-and-swap (the sprint itself starts immediately)
## Used only when the weapon has no ads_sprite/aim_sprites: zoom and shift the hip frame toward centre.
@export var mode_switch_rot := -0.07  ## radians the gun twists while flicking the fire selector
@export var mode_switch_drop := Vector2(0.02, 0.035)  ## screen heights right/down at the peak of the flick
## Reload sway: the hands tilt and dip into the reload and wander a little while working the mag.
@export var reload_tilt := 0.045  ## radians at the middle of the reload
@export var reload_dip := 0.03  ## screen heights down at the middle of the reload
@export var reload_wobble := 0.008  ## screen heights of hand wander on top
## Lower stances pull the gun in toward the face (Insurgency-style). Blends with eye height, so it follows
## the stance change smoothly. Values are at full prone; crouch gets about 40% of them.
@export var low_stance_zoom := 0.14
@export var low_stance_shift := Vector2(-0.04, 0.02)  ## screen heights (x left/right, y down)
## Guns without a shoot frame: the idle frame is shoved back by each shot instead (screen heights right/down, radians).
@export var fire_shove := Vector2(0.008, 0.025)
@export var fire_shove_rot := 0.012
## Passive hand shake: a small, quick tremor on the gun, even standing still (the tablet stays steady).
@export var shake_amount := 0.005  ## screen heights
@export var shake_roll := 0.004  ## radians (gun only)
@export var shake_speed := 1.4  ## tremor rate
@export var flash_light := 1.2  ## how brightly an unsuppressed shot lights the gun sprite
@export var flash_light_time := 0.07  ## seconds the light takes to fade
@export var lean_roll := 0.1  ## radians the gun cants into a full lean (hip only: aimed, the sights stay lined up)
@export var lean_shift := 0.04  ## screen heights the gun slides toward the lean side (hip only)
@export var ads_zoom := 0.12
@export var ads_shift := Vector2(-0.1, -0.03)

var _blur := ShaderMaterial.new()
var _shake := FastNoiseLite.new()
var _sprint_t := 0.0  # own slower, eased sprint blend for the pose swap
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
func hand_offset(k: float, with_freeaim := true, with_shake := true) -> Vector2:
	var sway: Vector2 = viewmodel.sway
	var bob: Vector3 = viewmodel.bob
	var inertia: Vector3 = viewmodel.inertia_offset
	var fa := Vector2(deg_to_rad(player.freeaim.x), deg_to_rad(player.freeaim.y)) * freeaim_scale if with_freeaim else Vector2.ZERO
	return Vector2(
		-sway.x * sway_scale + bob.x * bob_scale + inertia.x * inertia_scale - fa.x,
		-sway.y * sway_scale - bob.y * bob_scale - inertia.y * inertia_scale - fa.y) * k + (shake(0.0) * shake_amount * k if with_shake else Vector2.ZERO)


## Hand tremor at channel offset ch: smooth noise, -1..1 per axis; calmer while aiming down sights.
func shake(ch: float) -> Vector2:
	var t := Time.get_ticks_msec() / 1000.0 * shake_speed * 60.0
	return Vector2(_shake.get_noise_2d(t, ch), _shake.get_noise_2d(t, ch + 100.0)) * (1.0 - 0.6 * player.ads_blend)


## 1 right after a shot fading to 0 over shoot_frame_time, for guns that fire on the idle frame (no shoot frame).
func shot_shove(w: Weapon) -> float:
	if w.data.shoot_sprite or texture != w.data.idle_sprite:
		return 0.0
	return maxf(0.0, 1.0 - w.since_shot / w.data.shoot_frame_time)


## Reload hand motion as a screen offset (screen heights). Eased in and out (zero slope at both ends) so the
## reload starts and lands on the rest pose; the wobble rides on that envelope. x is wander only, y is dip + wander.
func reload_sway(w: Weapon) -> Vector2:
	if not w.is_reloading():
		return Vector2.ZERO
	var p := clampf(1.0 - w.reload_left / w.reload_total, 0.0, 1.0)
	var env := (1.0 - cos(TAU * p)) * 0.5
	return Vector2(sin(TAU * p * 2.0) * reload_wobble, reload_dip + sin(TAU * p * 3.0) * reload_wobble * 0.6) * env


func _process(delta: float) -> void:
	var w := player.weapons.current
	_sprint_t = move_toward(_sprint_t, 1.0 if player.is_sprinting else 0.0, delta / sprint_swap_time)
	texture = w.current_sprite(player.ads_blend, _sprint_t)
	visible = texture != null and player.alive
	if not visible:
		player.viewmodel_aim = Vector2.INF
		return
	var d := w.data
	var vp := get_viewport_rect().size
	var k := vp.y
	var ads := 0.0 if d.ads_sprite or not d.aim_sprites.is_empty() else player.ads_blend
	var kick: Vector3 = viewmodel.kick_pos
	var kick_rot: Vector3 = viewmodel.kick_rot
	var lower: float = viewmodel.lower

	# With a sprint frame the pose itself shows sprinting: just dip out and back while it swaps.
	var sprint_pose := d.sprint_sprite != null
	# Eased bump (0 slope at both ends, deepest at the swap) so the gun settles down and up instead of snapping.
	var sprint_off := (1.0 - cos(TAU * _sprint_t)) * 0.5 * sprint_dip if sprint_pose else player.sprint_blend * sprint_drop
	var off := hand_offset(k) + Vector2(0.0, kick.z * kick_scale + lower * lower_drop + sprint_off) * k
	off += Vector2(ads_shift.x * vp.x, ads_shift.y * k) * ads + d.sprite_offset * k
	var flick := sin(PI * clampf(w.since_mode_switch / d.mode_switch_time, 0.0, 1.0))
	# 0 standing .. 1 prone; released while aiming down sights so the sight alignment holds.
	var low := clampf((player.eye_heights[0] - player.eye_height) / (player.eye_heights[0] - player.eye_heights[2]), 0.0, 1.0)
	low *= 1.0 - player.ads_blend
	off += low_stance_shift * k * low
	off += mode_switch_drop * k * flick
	var rl := reload_sway(w)
	off += rl * k
	var shove := shot_shove(w)
	off.x += player.lean * lean_shift * k * (1.0 - player.ads_blend)
	off += fire_shove * k * shove

	size = vp * (1.0 + overscan)
	var base := Vector2(-vp.x * overscan * 0.5, 0.0)  # overscan hangs below the screen
	var frames := w.aim_frames()
	var window := w.aim_window()
	if not frames.is_empty() and window.has_area():
		# Slide the frame so the sight glass ends up on the screen centre (the aim point once fully aimed).
		var sight := base + window.get_center() * size + d.sprite_offset * k
		off += (vp * 0.5 - sight) * w.sight_progress(player.ads_blend)
	position = base + off
	var rest_aim := vp * 0.5 - (base + d.sprite_offset * k)  # sprite-local point that sits on screen centre at rest
	pivot_offset = Vector2(size.x * 0.5, size.y)
	scale = Vector2.ONE * (1.0 + ads_zoom * ads) * (1.0 + low_stance_zoom * low)
	rotation = shake(300.0).x * shake_roll + player.lean * lean_roll * (1.0 - player.ads_blend) + kick_rot.z * 0.5 + (0.0 if sprint_pose else player.sprint_blend * 0.08) + mode_switch_rot * flick + reload_tilt * (rl.y / reload_dip if reload_dip > 0.0 else 0.0) + fire_shove_rot * shove
	# Where the barrel points: the rest point carried by the sprite's motion; aiming pulls it onto the sights (centre).
	player.viewmodel_aim = (get_transform() * rest_aim).lerp(vp * 0.5, player.ads_blend)

	var shooting := (texture == d.shoot_sprite or shove > 0.0) and d.shoot_blur > 0.0
	var fade := 1.0 - w.since_shot / d.shoot_frame_time if shooting else 0.0
	# Angle in image space (counter-clockwise from +x); UV y points down and is scaled by the frame aspect.
	var a := deg_to_rad(d.shoot_blur_angle)
	var aspect := float(texture.get_width()) / texture.get_height()
	_blur.set_shader_parameter("blur_dir", Vector2(cos(a), -sin(a) * aspect) * d.shoot_blur * fade)
	_blur.set_shader_parameter("samples", 12 if shooting else 2)
	# Muzzle flash lights the gun: local around the muzzle at the hip, an even glow when aimed (muzzle unknown).
	var flash := 0.0 if d.suppressed else maxf(0.0, 1.0 - w.since_shot / flash_light_time)
	var hip := texture == d.idle_sprite or texture == d.shoot_sprite
	_blur.set_shader_parameter("flash_strength", flash * (flash_light if hip else flash_light * 0.5))
	_blur.set_shader_parameter("flash_uv", d.muzzle_uv)
	_blur.set_shader_parameter("flash_radius", 0.45 if hip else 3.0)
	_blur.set_shader_parameter("aspect", aspect)

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
