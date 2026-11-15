class_name WeaponManager
extends Node3D
## Owns the loadout: switching (holster -> equip), input routing and fire permission.

signal weapon_changed(weapon: Weapon)

enum State { READY, HOLSTER, EQUIP }

@export var loadout: Array[WeaponData] = []
@export var grenade_scene: PackedScene
@export var grenade_count := 2
@export var throw_speed := 14.0

var weapons: Array[Weapon] = []
var current: Weapon
var state := State.EQUIP
var switch_phase := 1.0  ## 0 = raised, 1 = fully lowered; drives the viewmodel
var player: Player

var grenades := 0
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


func can_fire() -> bool:
	return state == State.READY and player.controls_active() and not player.is_sprinting \
		and player.sprint_recovery <= 0.0 and player.wall_block < 0.6


func _process(delta: float) -> void:
	var active := player.controls_active()
	if active:
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
	player.ads_blocked = state != State.READY or current.is_reloading()
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
