class_name Player
extends CharacterBody3D
## First-person controller: weighty movement, stances, lean, freeaim deadzone and recoil-aware look.
## The active weapon pushes its handling values (ads_time, ads_zoom, ...) into this node on equip.

signal footstep(speed: float)
signal jumped
signal landed(fall_speed: float)

enum Stance { STAND, CROUCH, PRONE }

@export_group("Look")
@export var mouse_sensitivity := 0.08  ## degrees per mouse pixel
@export var base_fov := 75.0
@export var deadzone_deg := 3.0  ## hip-fire freeaim radius; the gun moves inside it before the view turns
@export var max_pitch := 88.0

## Handheld camera noise (always on, like a third-person follow cam): slow, smooth drift of the view.
@export_group("Camera noise")
@export var cam_noise_deg := Vector3(0.6, 0.7, 0.4)  ## pitch, yaw, roll amplitude at rest
@export var cam_noise_speed := 0.45  ## drift rate; higher = busier
@export var cam_noise_moving := 1.8  ## amplitude multiplier at full sprint speed
@export var cam_noise_ads := 0.35  ## amplitude multiplier while aiming down sights
@export_group("Movement")
@export var walk_speed := 3.2
@export var sprint_speed := 5.6
@export var crouch_speed := 1.9
@export var prone_speed := 0.8
@export var ads_speed_mult := 0.6
@export var ground_accel := 9.0  ## m/s^2 toward wish velocity
@export var ground_decel := 11.0  ## m/s^2 when there is no input
@export var jump_velocity := 3.6
@export var vault_max_height := 1.3
@export var vault_push := 2.0

@export_group("Stance")  # arrays are indexed by Stance
@export var eye_heights := PackedFloat32Array([1.65, 1.1, 0.35])
@export var dead_eye_height := 0.25  ## camera drops to the floor on death
@export var dead_prone_roll := 14.0  ## degrees the view tilts when killed while prone
@export var capsule_heights := PackedFloat32Array([1.8, 1.25, 0.6])
@export var stance_spread_mult := PackedFloat32Array([1.0, 0.75, 0.5])
@export var stance_recoil_mult := PackedFloat32Array([1.0, 0.8, 0.6])
@export var stance_change_speed := 4.0  ## eye height m/s

@export_group("Lean")
@export var lean_angle := 12.0
@export var lean_shift := 0.3
@export var lean_speed := 6.0

@export_group("Footsteps")
@export var stride_length := 1.7

# Pushed by the weapon manager.
var ads_time := 0.3
var ads_zoom := 1.0
var sprint_to_fire := 0.25
var ads_blocked := false
# Written by the viewmodel: 0 = clear, 1 = gun fully pushed down by a wall.
var wall_block := 0.0

var stance := Stance.STAND
var alive := true
var lean := 0.0
var ads_blend := 0.0
var sprint_blend := 0.0
var is_sprinting := false
var sprint_recovery := 0.0  ## seconds until the gun can fire after sprinting
var freeaim := Vector2.ZERO  ## degrees (yaw, pitch) of the gun relative to the view
var look_delta := Vector2.ZERO  ## accumulated look input, consumed by the viewmodel for sway
var recoil := Vector2.ZERO  ## degrees currently added to the view
var recoil_target := Vector2.ZERO
var recoil_recovery := 8.0
var since_shot := 99.0
var look_yaw := 0.0
var look_pitch := 0.0
var viewmodel_aim := Vector2.INF  ## screen point the 2D gun's barrel points at (set by SpriteViewmodel); INF = none
var death_roll := 0.0  ## current view roll in degrees (prone death)
var eye_height := 1.65
var spawn_transform: Transform3D

var _stride := 0.0
var _cam_noise := FastNoiseLite.new()  # simplex, default frequency: 60 samples ~ one slow wander
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var collision: CollisionShape3D = $Collision
@onready var lean_pivot: Node3D = $LeanPivot
@onready var head: Node3D = $LeanPivot/Head
@onready var camera: Camera3D = $LeanPivot/Head/Camera3D
@onready var weapons: WeaponManager = $LeanPivot/Head/Camera3D/Viewmodel/Weapons
@onready var weapon_camera: Camera3D = $ViewmodelLayer/Container/SubViewport/WeaponCamera
@onready var health: Health = $Health
@onready var _hitbox_rids: Array[RID] = [($LeanPivot/TorsoHitbox as Hitbox).get_rid(), ($LeanPivot/Head/HeadHitbox as Hitbox).get_rid()]


func _ready() -> void:
	add_to_group("player")
	add_to_group("resettable")
	spawn_transform = global_transform
	look_yaw = rotation_degrees.y
	eye_height = eye_heights[stance]
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	health.died.connect(func(_source: Node) -> void: alive = false)
	# The viewmodel renders in its own transparent viewport so it never clips into walls.
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.55, 0.6)
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	weapon_camera.environment = env


func hitbox_rids() -> Array[RID]:
	return _hitbox_rids


## Reset key: full health and ammo; respawn only if dead.
func reset() -> void:
	if not alive:
		global_transform = spawn_transform
		look_yaw = rotation_degrees.y
		look_pitch = 0.0
		velocity = Vector3.ZERO
		_set_stance(Stance.STAND)
	alive = true
	health.reset()
	recoil = Vector2.ZERO
	recoil_target = Vector2.ZERO
	weapons.refill()


func controls_active() -> bool:
	return alive and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion and controls_active():
		# Scale by zoom so ADS feels the same per screen distance.
		_apply_look(-motion.relative * mouse_sensitivity * camera.fov / base_fov)
	elif event.is_action_pressed("toggle_mouse"):
		var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if captured else Input.MOUSE_MODE_CAPTURED
	elif not controls_active():
		return
	elif event.is_action_pressed("crouch"):
		_set_stance(Stance.STAND if stance == Stance.CROUCH else Stance.CROUCH)
	elif event.is_action_pressed("prone"):
		_set_stance(Stance.STAND if stance == Stance.PRONE else Stance.PRONE)
	elif event.is_action_pressed("interact"):
		_interact()


func _apply_look(d: Vector2) -> void:
	look_delta += d
	freeaim += d
	var clamped := freeaim.limit_length(deadzone_deg * (1.0 - ads_blend))
	var excess := freeaim - clamped
	freeaim = clamped
	# Pulling against recoil eats it first, so countered recoil doesn't later "recover" below the target.
	for i in 2:
		if excess[i] * recoil[i] < 0.0:
			var take := signf(recoil[i]) * minf(absf(recoil[i]), absf(excess[i]))
			recoil[i] -= take
			recoil_target[i] -= take
			excess[i] += take
	look_yaw += excess.x
	look_pitch = clampf(look_pitch + excess.y, -max_pitch, max_pitch)


## kick: degrees (x = yaw right, y = pitch up). recovery: degrees per second once firing stops.
func add_recoil(kick: Vector2, recovery: float) -> void:
	recoil_target += Vector2(-kick.x, kick.y) * stance_recoil_mult[stance]
	recoil_recovery = recovery
	since_shot = 0.0


## Direction the gun points. With a 2D sprite gun: the camera ray through the screen point its barrel points
## at, so sway, bob, inertia, kick and the freeaim drift all move the shots with the gun you see.
func aim_basis() -> Basis:
	if not viewmodel_aim.is_finite():
		return freeaim_basis()
	return Basis.looking_at(camera.project_ray_normal(viewmodel_aim), camera.global_basis.y)


## The view rotated by freeaim only: for things that follow your head rather than the gun (wall check, throws).
## Camera drift (radians) at time t: three smooth noise channels, louder on the move, quieter when aiming.
func camera_noise(t: float) -> Vector3:
	var move := clampf(horizontal_speed() / sprint_speed, 0.0, 1.0)
	var k := lerpf(1.0, cam_noise_moving, move) * lerpf(1.0, cam_noise_ads, ads_blend)
	var n := Vector3(_cam_noise.get_noise_2d(t * cam_noise_speed * 60.0, 0.0), _cam_noise.get_noise_2d(t * cam_noise_speed * 60.0, 100.0),
		_cam_noise.get_noise_2d(t * cam_noise_speed * 60.0, 200.0))
	return Vector3(deg_to_rad(cam_noise_deg.x * n.x), deg_to_rad(cam_noise_deg.y * n.y), deg_to_rad(cam_noise_deg.z * n.z)) * k if alive else Vector3.ZERO


func freeaim_basis() -> Basis:
	return camera.global_basis * Basis.from_euler(Vector3(deg_to_rad(freeaim.y), deg_to_rad(freeaim.x), 0.0))


func horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


func _process(delta: float) -> void:
	since_shot += delta
	if since_shot > 0.12:
		recoil_target = recoil_target.move_toward(Vector2.ZERO, recoil_recovery * delta)
	recoil = recoil.lerp(recoil_target, minf(1.0, 30.0 * delta))
	_apply_look(Vector2.ZERO)  # re-clamps freeaim as the ADS deadzone shrinks
	rotation.y = deg_to_rad(look_yaw + recoil.x)
	head.rotation.x = deg_to_rad(clampf(look_pitch + recoil.y, -max_pitch, max_pitch))
	var roll_target := dead_prone_roll if stance == Stance.PRONE else 0.0
	death_roll = 0.0 if alive else move_toward(death_roll, roll_target, dead_prone_roll / 0.7 * delta)  # eases in over 0.7 s
	head.rotation.z = deg_to_rad(death_roll)
	camera.rotation = camera_noise(Time.get_ticks_msec() / 1000.0)

	var eye_target := eye_heights[stance] if alive else dead_eye_height
	eye_height = move_toward(eye_height, eye_target, stance_change_speed * delta)
	lean_pivot.position.y = eye_height * 0.5
	head.position.y = eye_height * 0.5
	camera.fov = base_fov / lerpf(1.0, ads_zoom, ads_blend)
	weapon_camera.global_transform = camera.global_transform
	weapon_camera.fov = 60.0 / lerpf(1.0, ads_zoom, ads_blend * 0.3)


func _physics_process(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back") if controls_active() else Vector2.ZERO
	var wants_ads := controls_active() and Input.is_action_pressed("ads")
	is_sprinting = controls_active() and Input.is_action_pressed("sprint") and input.y < -0.5 and is_on_floor() and not wants_ads
	if is_sprinting and stance != Stance.STAND and not _set_stance(Stance.STAND):
		is_sprinting = false
	sprint_recovery = sprint_to_fire if is_sprinting else maxf(sprint_recovery - delta, 0.0)
	var ads_target := 1.0 if wants_ads and not is_sprinting and not ads_blocked else 0.0
	ads_blend = move_toward(ads_blend, ads_target, delta / maxf(ads_time, 0.01))
	sprint_blend = move_toward(sprint_blend, 1.0 if is_sprinting else 0.0, delta * 5.0)

	if is_on_floor():
		var wish := global_basis * Vector3(input.x, 0.0, input.y) * _target_speed()
		var rate := ground_accel if input != Vector2.ZERO else ground_decel
		var hv := Vector3(velocity.x, 0.0, velocity.z).move_toward(wish, rate * delta)
		velocity = Vector3(hv.x, velocity.y, hv.z)
		if controls_active() and Input.is_action_just_pressed("jump"):
			_jump_or_vault()
	else:
		velocity.y -= _gravity * delta  # no air control: momentum only
	var was_airborne := not is_on_floor()
	var fall_speed := -velocity.y
	move_and_slide()
	if was_airborne and is_on_floor() and fall_speed > 1.5:  # ignore steps and slopes
		landed.emit(fall_speed)
	_update_lean(delta)
	_update_footsteps(delta)


func _target_speed() -> float:
	var s := walk_speed
	match stance:
		Stance.STAND:
			s = sprint_speed if is_sprinting else walk_speed
		Stance.CROUCH:
			s = crouch_speed
		Stance.PRONE:
			s = prone_speed
	return s * lerpf(1.0, ads_speed_mult, ads_blend)


func _jump_or_vault() -> void:
	if stance != Stance.STAND:
		_set_stance(Stance.CROUCH if stance == Stance.PRONE else Stance.STAND)
		return
	var fwd := -global_basis.z
	var low := global_position + Vector3.UP * 0.5
	var high := global_position + Vector3.UP * (vault_max_height + 0.1)
	if _ray(low, low + fwd * 0.9) and not _ray(high, high + fwd * 0.9):
		velocity.y = sqrt(2.0 * _gravity * (vault_max_height + 0.15))
		velocity += fwd * vault_push
	else:
		velocity.y = jump_velocity
	jumped.emit()


## Returns false if there's no headroom for the new stance.
func _set_stance(s: Stance) -> bool:
	if s == stance:
		return true
	var h := capsule_heights[s]
	if h > capsule_heights[stance] and _ray(global_position + Vector3.UP * 0.2, global_position + Vector3.UP * (h + 0.05)):
		return false
	stance = s
	var capsule := collision.shape as CapsuleShape3D
	capsule.height = h
	collision.position.y = h * 0.5
	return true


func _update_lean(delta: float) -> void:
	var target := Input.get_axis("lean_left", "lean_right") if controls_active() and not is_sprinting and not weapons.phone_open else 0.0  # Q/E flip phone pages instead
	if target != 0.0:
		# Shorten the lean when a wall is beside the head so the camera never pokes through.
		var from := global_position + Vector3.UP * eye_height
		var reach := lean_shift + 0.45
		var hit := _ray_hit(from, from + global_basis.x * signf(target) * reach)
		if not hit.is_empty():
			var dist := from.distance_to(hit.position)
			target *= clampf((dist - 0.25) / (reach - 0.25), 0.0, 1.0)
	lean = move_toward(lean, target, lean_speed * delta)
	lean_pivot.rotation.z = -deg_to_rad(lean_angle) * lean
	lean_pivot.position.x = lean * lean_shift


func _update_footsteps(delta: float) -> void:
	if not is_on_floor():
		return
	_stride += horizontal_speed() * delta
	if _stride >= stride_length:
		_stride = 0.0
		footstep.emit(horizontal_speed())


func _interact() -> void:
	var from := camera.global_position
	var hit := _ray_hit(from, from - camera.global_basis.z * 2.2)
	var n: Node = hit.get("collider")
	while n and not n.has_method("interact"):
		n = n.get_parent()
	if n:
		n.interact(self)


func _ray_hit(from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, Ballistics.WORLD, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(q)


func _ray(from: Vector3, to: Vector3) -> bool:
	return not _ray_hit(from, to).is_empty()
