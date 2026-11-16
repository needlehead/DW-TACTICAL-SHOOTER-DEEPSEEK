class_name WeaponManager
extends Node3D
## Owns the loadout: switching (holster -> equip), input routing and fire permission.

signal weapon_changed(weapon: Weapon)

enum State { READY, HOLSTER, EQUIP }

@export var loadout: Array[WeaponData] = []
@export var grenade_scene: PackedScene
@export var grenade_count := 2
@export var throw_speed := 14.0
@export var equip_sound: AudioStream  ## gun coming up: weapon switch, after a grenade, phone put away
@export var aim_sound: AudioStream  ## raising the gun to aim
@export var page_sound: AudioStream  ## device page flip
@export var handling_volume_db := -6.0
@export var phone_time := 0.6  ## Tab: gun goes down (first half), then the phone comes up (second half); same for every heroine

var weapons: Array[Weapon] = []
var current: Weapon
var state := State.EQUIP
var switch_phase := 1.0  ## 0 = raised, 1 = fully lowered; drives the viewmodel
var player: Player

var grenades := 0
var phone_blend := 0.0  ## 0 = gun up, 0.5 = gun down, 1 = phone fully raised
var gear_lower := 0.0  ## 0..1 gun lowered for a hands action (NightVision flipping the goggles)
var phone_forced := false  ## viewmodel editor's Tablet mode keeps the phone raised
## Tab toggles the phone; damage, sprinting, firing or aiming closes it. While open, Q/E or the wheel flip pages.
var phone_open := false
var phone_page := 0  ## Phone.PAGES index; every open starts on Status (0)
var _foley: AudioStreamPlayer
var _next := 0


func _ready() -> void:
	player = owner as Player
	for d in loadout:
		var w := Weapon.new()
		w.data = d
		w.player = player
		w.visible = false
		add_child(w)
		w.refill()
		weapons.append(w)
	grenades = grenade_count
	_foley = AudioStreamPlayer.new()
	_foley.max_polyphony = 2
	add_child(_foley)
	_activate(0)
	player.get_node("Health").damaged.connect(func(_a: float, _z: StringName, _s: Node) -> void: phone_open = false)


func select(index: int) -> void:
	if index >= weapons.size() or (weapons[index] == current and state != State.HOLSTER):
		return
	_next = index
	current.cancel_reload()
	state = State.HOLSTER


func refill() -> void:
	for w in weapons:
		w.refill()
	grenades = grenade_count


## Throw from the eye along the aim; the gun dips and comes back up like a short weapon switch.
func throw_grenade() -> void:
	if state != State.READY or current.is_reloading() or player.is_sprinting:
		return
	if grenades <= 0:
		Game.toast("No grenades")
		return
	grenades -= 1
	var g := grenade_scene.instantiate() as Grenade
	g.thrower = player
	player.get_parent().add_child(g)
	var fwd := -player.freeaim_basis().z
	g.global_position = player.camera.global_position + fwd * 0.4
	g.linear_velocity = player.velocity + fwd * throw_speed + Vector3.UP * 2.0
	state = State.EQUIP
	switch_phase = 1.0
	_play_foley(equip_sound)


func _unhandled_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if phone_open and mb and mb.pressed:
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			flip_page(-1)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			flip_page(1)


func flip_page(dir: int) -> void:
	phone_page = posmod(phone_page + dir, Phone.PAGES.size())
	click()


## Device button click (page flip, outfit turn).
func click() -> void:
	_play_foley(page_sound)


## Gun lowering share of the phone transition (0..1).
func phone_gun_lower() -> float:
	return clampf(phone_blend * 2.0, 0.0, 1.0)


## Phone raise share of the phone transition (0..1).
func phone_raise() -> float:
	return clampf(phone_blend * 2.0 - 1.0, 0.0, 1.0)


func can_fire() -> bool:
	return state == State.READY and phone_blend == 0.0 and gear_lower == 0.0 and player.controls_active() and not player.is_sprinting \
		and player.sprint_recovery <= 0.0 and player.wall_block < 0.6


func _process(delta: float) -> void:
	var active := player.controls_active()
	if active and Input.is_action_just_pressed("phone"):
		phone_open = not phone_open and state == State.READY and not current.is_reloading() and gear_lower == 0.0
		phone_page = 0
	if not active or player.is_sprinting or Input.is_action_just_pressed("fire") or Input.is_action_just_pressed("ads"):
		phone_open = false
	if phone_open:  # flipping is free: works while the phone is still coming up
		if Input.is_action_just_pressed("lean_left"):
			flip_page(-1)
		if Input.is_action_just_pressed("lean_right"):
			flip_page(1)
	var phone_target := 1.0 if phone_forced or phone_open else 0.0
	var was_lowered := phone_blend >= 0.5
	phone_blend = move_toward(phone_blend, phone_target, delta / maxf(phone_time, 0.01))
	if was_lowered and phone_blend < 0.5:
		_play_foley(equip_sound)  # gun coming back up after the phone
	if active and Input.is_action_just_pressed("ads") and not player.ads_blocked and not player.is_sprinting:
		_play_foley(aim_sound)
	if active and phone_blend == 0.0 and gear_lower == 0.0:
		for i in weapons.size():
			if Input.is_action_just_pressed("weapon_%d" % (i + 1)):
				select(i)
		if Input.is_action_just_pressed("fire_mode"):
			current.cycle_mode()
		if Input.is_action_just_pressed("alt_sight"):
			current.toggle_canted()
		if Input.is_action_just_pressed("toggle_laser") and current.data.laser:
			current.laser_mode = (current.laser_mode + 1) % 3  # visible -> IR -> off
			Game.toast(["LASER OFF", "LASER VISIBLE", "LASER IR (night vision only)"][current.laser_mode])
		if Input.is_action_just_pressed("toggle_flashlight") and current.data.flashlight:
			current.light_on = not current.light_on
			Game.toast("LIGHT " + ("ON" if current.light_on else "OFF"))
		if Input.is_action_just_pressed("reload") and state == State.READY:
			current.start_reload()
		if Input.is_action_just_pressed("grenade"):
			throw_grenade()

	match state:
		State.HOLSTER:
			switch_phase = move_toward(switch_phase, 1.0, delta / current.data.holster_time)
			if switch_phase >= 1.0:
				_activate(_next)
		State.EQUIP:
			switch_phase = move_toward(switch_phase, 0.0, delta / current.data.equip_time)
			if switch_phase <= 0.0:
				state = State.READY
	# Pushed every frame so live-tuned values apply immediately.
	player.ads_blocked = state != State.READY or current.is_reloading() or phone_blend > 0.0 or gear_lower > 0.0
	player.ads_time = current.data.ads_time
	player.ads_zoom = current.data.ads_zoom
	player.sprint_to_fire = current.data.sprint_to_fire_time
	current.tick(delta, active and Input.is_action_pressed("fire"), active and Input.is_action_just_pressed("fire"), can_fire())


func _activate(index: int) -> void:
	if current:
		current.visible = false
	current = weapons[index]
	current.visible = true
	state = State.EQUIP
	switch_phase = 1.0
	weapon_changed.emit(current)
	_play_foley(equip_sound)


func _play_foley(s: AudioStream) -> void:
	if s == null or _foley == null:
		return
	_foley.stream = s
	_foley.volume_db = handling_volume_db
	_foley.play()
