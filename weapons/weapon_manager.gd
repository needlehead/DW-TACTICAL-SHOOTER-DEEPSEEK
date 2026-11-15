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
@export var handling_volume_db := -6.0
@export var phone_time := 0.6  ## hold Tab: gun goes down (first half), then the phone comes up (second half)

var weapons: Array[Weapon] = []
var current: Weapon
var state := State.EQUIP
var switch_phase := 1.0  ## 0 = raised, 1 = fully lowered; drives the viewmodel
var player: Player

var grenades := 0
var phone_blend := 0.0  ## 0 = gun up, 0.5 = gun down, 1 = phone fully raised
var _phone_cancelled := false
var _foley: AudioStreamPlayer  # fire/ADS put the phone away until Tab is pressed again
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
	var fwd := -player.aim_basis().z
	g.global_position = player.camera.global_position + fwd * 0.4
	g.linear_velocity = player.velocity + fwd * throw_speed + Vector3.UP * 2.0
	state = State.EQUIP
	switch_phase = 1.0
	_play_foley(equip_sound)


## Gun lowering share of the phone transition (0..1).
func phone_gun_lower() -> float:
	return clampf(phone_blend * 2.0, 0.0, 1.0)


## Phone raise share of the phone transition (0..1).
func phone_raise() -> float:
	return clampf(phone_blend * 2.0 - 1.0, 0.0, 1.0)


func can_fire() -> bool:
	return state == State.READY and phone_blend == 0.0 and player.controls_active() and not player.is_sprinting \
		and player.sprint_recovery <= 0.0 and player.wall_block < 0.6


func _process(delta: float) -> void:
	var active := player.controls_active()
	var wants_phone := active and Input.is_action_pressed("phone")
	if not wants_phone:
		_phone_cancelled = false
	elif phone_blend > 0.0 and (Input.is_action_just_pressed("fire") or Input.is_action_just_pressed("ads")):
		_phone_cancelled = true
	var phone_target := 1.0 if wants_phone and not _phone_cancelled and state == State.READY and not current.is_reloading() else 0.0
	var was_lowered := phone_blend >= 0.5
	phone_blend = move_toward(phone_blend, phone_target, delta / maxf(phone_time, 0.01))
	if was_lowered and phone_blend < 0.5:
		_play_foley(equip_sound)  # gun coming back up after the phone
	if active and Input.is_action_just_pressed("ads") and not player.ads_blocked and not player.is_sprinting:
		_play_foley(aim_sound)
	if active and phone_blend == 0.0:
		for i in weapons.size():
			if Input.is_action_just_pressed("weapon_%d" % (i + 1)):
				select(i)
		if Input.is_action_just_pressed("fire_mode"):
			current.cycle_mode()
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
	player.ads_blocked = state != State.READY or current.is_reloading() or phone_blend > 0.0
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
