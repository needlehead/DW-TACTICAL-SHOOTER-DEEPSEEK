class_name Weapon
extends Node3D
## One carried weapon: trigger logic, ammo/magazines, spread, recoil and a greybox viewmodel.
## The node origin is the rear sight, so aiming down sights puts the origin on the eye line.

signal fired

@export var data: WeaponData

var mag := 0  ## rounds in the inserted magazine (not counting the chamber)
var chambered := false
var spare: Array[int] = []  ## round count of each spare magazine; never topped up
var mode := 0  ## 0 until refill() picks the most automatic mode
var bloom := 0.0
var shot_index := 0
var since_shot := 99.0
var reload_left := 0.0
var reload_total := 1.0
var empty_reload := false
var since_mode_switch := 99.0
var canted := false  ## canted sight selected (only if the weapon has one)
var cant_t := 0.0  ## 0 main sight .. 1 canted; eases toward `canted` so switching while aimed rolls through
var laser_mode := 1  ## 0 off, 1 visible, 2 IR (seen only through night vision); only matters if data.laser
var light_on := false  ## only matters if data.flashlight
var ir_on := false  ## only matters if data.ir_illuminator
var _fire_audio: AudioStreamPlayer3D
var player: Player

var _cooldown := 0.0
var _burst_left := 0
var _flash: Node3D
var _light: OmniLight3D


func _ready() -> void:
	_build_viewmodel()


func refill() -> void:
	chambered = true
	mag = data.mag_size - 1
	spare.clear()
	for i in data.spare_mags:
		spare.append(data.mag_size)
	reload_left = 0.0
	if mode not in data.modes():
		mode = data.modes()[-1]  # most automatic mode by default


func cycle_mode() -> void:
	var ms := data.modes()
	mode = ms[(ms.find(mode) + 1) % ms.size()]
	since_mode_switch = 0.0
	Game.toast(WeaponData.mode_name(mode))


func is_reloading() -> bool:
	return reload_left > 0.0


func start_reload() -> void:
	if is_reloading():
		return
	if spare.is_empty() or spare.max() <= mag:
		Game.toast("No fuller magazine")
		return
	empty_reload = not chambered
	reload_left = data.empty_reload_time if empty_reload else data.reload_time
	reload_total = reload_left


func cancel_reload() -> void:
	reload_left = 0.0


## Called every frame by the manager while this weapon is out.
func tick(delta: float, held: bool, pressed: bool, allowed: bool) -> void:
	since_shot += delta
	since_mode_switch += delta
	cant_t = move_toward(cant_t, 1.0 if canted else 0.0, delta / maxf(data.cant_time, 0.01))
	bloom = move_toward(bloom, 0.0, data.spread_recover * delta)
	_cooldown -= delta
	if is_reloading():
		reload_left -= delta
		if reload_left <= 0.0:
			finish_reload()
		return
	if not allowed:
		_burst_left = 0
		_cooldown = maxf(_cooldown, 0.0)
		return
	if pressed and not chambered:
		Game.toast("*click*")
	if pressed and _burst_left == 0 and mode != WeaponData.AUTO:
		_burst_left = data.burst_count if mode == WeaponData.BURST else 1
	while _cooldown <= 0.0:
		if _burst_left == 0 and mode == WeaponData.AUTO and held:
			_burst_left = 1
		if _burst_left == 0 or not chambered:
			_burst_left = 0
			break
		_shoot()
		_burst_left -= 1
		_cooldown += 60.0 / data.rpm
	if _burst_left == 0:
		_cooldown = maxf(_cooldown, 0.0)


## Swaps to the fullest spare. The old magazine goes back in the pouch with whatever it had left.
func finish_reload() -> void:
	reload_left = 0.0
	var best := spare.find(spare.max())
	var new_mag := spare[best]
	spare.remove_at(best)
	if mag > 0:
		spare.append(mag)
	mag = new_mag
	if not chambered:
		cycle_round()


## Fires the chambered round's slot: chamber the next one from the magazine if there is one.
func cycle_round() -> void:
	chambered = mag > 0
	if chambered:
		mag -= 1


func current_spread() -> float:
	var base := lerpf(data.hip_spread, data.ads_spread, player.ads_blend)
	var move := clampf(player.horizontal_speed() / player.walk_speed, 0.0, 1.5) * data.move_spread
	var air := 0.0 if player.is_on_floor() else 6.0
	return (base + bloom) * player.stance_spread_mult[player.stance] + move * (1.0 - 0.6 * player.ads_blend) + air


func _shoot() -> void:
	if since_shot > 60.0 / data.rpm + 0.15:
		shot_index = 0
	since_shot = 0.0
	cycle_round()
	var dir := Ballistics.spread_dir(-player.aim_basis().z, current_spread())
	Ballistics.fire(get_world_3d().direct_space_state, player.camera.global_position, dir, data, player, player.hitbox_rids())

	var pattern := data.recoil_pattern
	var kick := pattern[mini(shot_index, pattern.size() - 1)] if pattern.size() > 0 else Vector2.ZERO
	kick += Vector2(randf_range(-1, 1) * data.recoil_random.x, randf_range(-1, 1) * data.recoil_random.y)
	player.add_recoil(kick * data.camera_recoil, data.recoil_recovery)
	shot_index += 1
	bloom = minf(bloom + data.spread_per_shot, data.spread_max)
	fired.emit()
	_muzzle_flash()
	_play_fire_sound()


func _play_fire_sound() -> void:
	if data.fire_sound == null:
		return
	if _fire_audio == null:
		_fire_audio = AudioStreamPlayer3D.new()
		_fire_audio.bus = &"World"
		_fire_audio.max_polyphony = 8  # each shot's tail rings under the next
		add_child(_fire_audio)
	_fire_audio.stream = data.fire_sound
	_fire_audio.volume_db = data.fire_volume_db
	_fire_audio.pitch_scale = 1.0 + randf_range(-1.0, 1.0) * data.fire_pitch_jitter
	_fire_audio.play()


func _muzzle_flash() -> void:
	if data.suppressed:
		return
	_flash.visible = true
	_light.light_energy = 3.0
	await get_tree().create_timer(0.04).timeout
	_flash.visible = false
	_light.light_energy = 0.0


## Doom-style frame for the current state, or null when this weapon has no sprites.
## Rough fill of the loaded mag, as you'd judge it by weight (what the phone shows).
func mag_estimate() -> String:
	var f := float(mag) / data.mag_size
	if f >= 0.9:
		return "Full"
	if f >= 0.6:
		return "Nearly full"
	if f >= 0.35:
		return "Half"
	return "Nearly empty" if mag > 0 else "Empty"


## The sight on screen right now: flips to the canted one halfway through the roll.
func using_canted() -> bool:
	return cant_t >= 0.5 and not data.canted_aim_sprites.is_empty()


## Aim-in frames and sight window of the sight on screen.
func aim_frames() -> Array[Texture2D]:
	return data.canted_aim_sprites if using_canted() else data.aim_sprites


func aim_window() -> Rect2:
	return data.canted_sight_window if using_canted() else data.sight_window


## How far along the aim-in frames to show: ADS progress, dipped mid-roll so switching sights while aimed runs
## back down one sequence and up the other (both start from the idle pose) instead of snapping between them.
func sight_progress(ads_blend: float) -> float:
	return ads_blend * (1.0 - data.cant_dip * (1.0 - absf(cant_t * 2.0 - 1.0)))


func toggle_canted() -> void:
	canted = not canted and not data.canted_aim_sprites.is_empty()


func reload_frames() -> Array[Texture2D]:
	if empty_reload and not data.empty_reload_sprites.is_empty():
		return data.empty_reload_sprites
	return data.reload_sprites


## Index into reload_frames() being shown, or -1 when not reloading.
func reload_frame() -> int:
	var n := reload_frames().size()
	if not is_reloading() or n == 0:
		return -1
	var elapsed := reload_total - reload_left
	var frame := int(elapsed * data.reload_fps) if data.reload_fps > 0.0 else int(elapsed / reload_total * n)
	return mini(frame, n - 1)


func current_sprite(ads_blend: float, sprint_blend := 0.0) -> Texture2D:
	if data.idle_sprite == null:
		return null
	var rf := reload_frame()
	if rf >= 0:
		return reload_frames()[rf]
	var frames := aim_frames()
	var aimed_frames := ads_blend >= 0.5 and not frames.is_empty()  # hip shoot frame would jump off the sight
	if sprint_blend >= 0.5 and data.sprint_sprite:  # swap at the bottom of the sprint dip
		return data.sprint_sprite
	if since_shot < data.shoot_frame_time and data.shoot_sprite and not aimed_frames:
		return data.shoot_sprite
	var progress := sight_progress(ads_blend)
	if progress > 0.0 and not frames.is_empty():
		var n := frames.size()
		return frames[mini(int(progress * n), n - 1)]
	if ads_blend > 0.5 and data.ads_sprite:
		return data.ads_sprite
	return data.idle_sprite


func _build_viewmodel() -> void:
	var s := data.vm_size
	var top := -0.035  # body top sits just under the sights
	var muzzle := Vector3(0, top - s.y * 0.5, -s.z + 0.03)
	var sprite_weapon := data.idle_sprite != null  # sprite weapons keep only the muzzle light
	if not sprite_weapon:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = data.color
		_vm_box(Vector3(0, top - s.y * 0.5, -s.z * 0.5 + 0.05), s, mat)  # receiver + barrel
		_vm_box(Vector3(0, top - s.y - 0.06, -s.z * 0.35), Vector3(s.x * 0.7, 0.13, 0.07), mat)  # magazine
		_vm_box(Vector3(0, top - s.y - 0.04, 0.0), Vector3(s.x * 0.8, 0.1, 0.05), mat)  # grip
		var sight_mat := StandardMaterial3D.new()
		sight_mat.albedo_color = Color(0.9, 0.5, 0.1)
		_vm_box(Vector3(0, -0.0175, 0.0), Vector3(0.03, 0.035, 0.02), sight_mat)  # rear
		_vm_box(Vector3(0, -0.0175, -s.z + 0.1), Vector3(0.008, 0.035, 0.01), sight_mat)  # front post

	var flash := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.05
	sphere.height = 0.1
	var flash_mat := StandardMaterial3D.new()
	flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_mat.albedo_color = Color(1.0, 0.8, 0.3)
	sphere.material = flash_mat
	flash.mesh = sphere
	flash.layers = 0 if sprite_weapon else 2
	flash.position = muzzle
	flash.visible = false
	add_child(flash)
	_flash = flash
	_light = OmniLight3D.new()
	_light.omni_range = 4.0
	_light.light_energy = 0.0
	_light.light_color = Color(1.0, 0.8, 0.5)
	_light.position = muzzle
	add_child(_light)


func _vm_box(pos: Vector3, size: Vector3, mat: Material) -> void:
	var m := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	box.material = mat
	m.mesh = box
	m.position = pos
	m.layers = 2
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)
