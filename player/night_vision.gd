class_name NightVision
extends TextureRect
## PVS-15-style night vision. Pick the goggles up first (NVGPickup), then N flips them down / up: the gun lowers,
## the hands bring the goggles to the eyes (frames, reversed to take them off) and the tubes come on.
## Through the tubes (ui/night_vision.gdshader): two round fields of view, light amplified (the camera's exposure is
## raised, so dark rooms read and daylight washes out), green-white phosphor, grain, bloom around bright lights.
## Close and magnified things can't be focused through the tubes: the gun sprite goes soft (gun_defocus) and a
## magnified scope shows an amplified but blurry picture (scope_blur). IR lasers only show through them (WeaponLights).

@export var frames: Array[Texture2D] = []  ## hands bringing the goggles to the eyes, first to last
@export var lower_time := 0.2  ## gun down before the hands come up, and back up after
@export var frames_time := 0.6
@export var exposure := 3.0  ## world light amplification while on
@export var power_time := 0.35  ## tubes fading up after they come on
@export var hand_fill := Color(0.55, 0.55, 0.55)  ## through the tubes the hands lift to at least this (SpriteShadow)
@export var gun_defocus := 0.004  ## blur radius on the gun sprite, frame heights
@export var scope_blur := 0.025  ## blur radius in a magnified scope's lens (fraction of the lens)

var owned := false
var on := false  ## tubes active
var _t := -1.0  ## seconds into a flip; < 0 = idle
var _putting_on := true
var _strength := 0.0
var _attrs := CameraAttributesPractical.new()
var _old_attrs: CameraAttributes

@onready var player: Player = owner
@onready var manager: WeaponManager = owner.get_node("LeanPivot/Head/Camera3D/Viewmodel/Weapons")
@onready var fx: ColorRect = owner.get_node("PostFXLayer/NightVisionFX")


func _ready() -> void:
	add_to_group("resettable")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://ui/night_vision.gdshader")
	fx.material = mat
	fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fx.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("night_vision"):
		toggle()


## Start flipping the goggles down (or up). False when it can't happen right now.
func toggle() -> bool:
	if not owned:
		Game.toast("No night vision")
		return false
	var w := manager.current
	if busy() or not player.alive or manager.phone_open or manager.phone_blend > 0.0 or manager.state != WeaponManager.State.READY \
			or w.is_reloading():
		return false
	_putting_on = not on
	_t = 0.0
	if not _putting_on:
		set_on(false)  # grabbing the goggles takes them off the eyes at once
	return true


## 0..1: how far the tubes have powered up (effects fade in with it).
func strength() -> float:
	return _strength


func busy() -> bool:
	return _t >= 0.0


func set_on(v: bool) -> void:
	if v == on:
		return
	on = v
	if v:
		_old_attrs = player.camera.attributes
		_attrs.exposure_multiplier = exposure
		player.camera.attributes = _attrs
	else:
		player.camera.attributes = _old_attrs


func reset() -> void:
	owned = false
	set_on(false)
	_t = -1.0
	_strength = 0.0
	texture = null
	manager.gear_lower = 0.0


func _process(delta: float) -> void:
	var vp := get_viewport_rect().size
	position = Vector2.ZERO
	size = vp
	fx.position = Vector2.ZERO
	fx.size = vp  # anchors alone leave it 0x0 under a CanvasLayer
	if not player.alive and busy():
		_t = -1.0
	var lower := 0.0
	texture = null
	if busy():
		_t += delta
		var total := lower_time * 2.0 + frames_time
		var f := (_t - lower_time) / frames_time  # 0..1 through the hand frames
		if _t < lower_time:
			lower = _t / lower_time
		elif f <= 1.0:
			lower = 1.0
			if not frames.is_empty():
				var i := clampi(int(f * frames.size()), 0, frames.size() - 1)
				texture = frames[i if _putting_on else frames.size() - 1 - i]
		else:
			lower = clampf(1.0 - (_t - lower_time - frames_time) / lower_time, 0.0, 1.0)
			if _putting_on:
				set_on(true)
		if _t >= total:
			_t = -1.0
	manager.gear_lower = lower
	_strength = move_toward(_strength, 1.0 if on else 0.0, delta / maxf(power_time, 0.01))
	fx.visible = _strength > 0.0
	if fx.visible:
		(fx.material as ShaderMaterial).set_shader_parameter("strength", _strength)
