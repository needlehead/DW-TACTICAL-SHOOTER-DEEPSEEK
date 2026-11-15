class_name Dummy
extends CharacterBody3D
## Test target with hit zones. Optionally patrols (NavigationAgent3D), turns toward the
## player when it sees them or gets shot, and returns deliberately inaccurate fire.

@export var patrol_points := PackedVector3Array()  ## global positions; empty = stationary
@export var shoots_back := true
@export var weapon: WeaponData
@export var body_color := Color(0.75, 0.45, 0.3)
@export var move_speed := 1.6
@export var turn_speed := 4.0  ## rad/s
@export var sight_range := 35.0
@export var reaction_time := 0.6
@export var aim_error_deg := 4.0
@export var fire_interval := 0.7
@export var damage_scale := 0.4
@export var alert_duration := 4.0

var _home: Transform3D
var _patrol_index := 0
var _alert := 0.0
var _react := 0.0
var _fire_cd := 0.0
var _audio: AudioStreamPlayer3D
var _fall: Tween
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var health: Health = $Health
@onready var agent: NavigationAgent3D = $NavigationAgent3D
@onready var body: Node3D = $Body
@onready var muzzle: Node3D = $Body/Muzzle
@onready var flash: Node3D = $Body/Muzzle/Flash
@onready var collision: CollisionShape3D = $Collision


func _ready() -> void:
	add_to_group("resettable")
	_home = global_transform
	health.died.connect(_on_died)
	health.damaged.connect(_on_damaged)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = body_color
	for m in body.get_children():
		if m is MeshInstance3D:
			(m as MeshInstance3D).material_override = mat
	if not patrol_points.is_empty():
		agent.target_position = patrol_points[0]


func reset() -> void:
	global_transform = _home
	velocity = Vector3.ZERO
	health.reset()
	if _fall:
		_fall.kill()
	body.rotation = Vector3.ZERO
	collision.disabled = false
	_set_hitboxes(true)
	_alert = 0.0
	_patrol_index = 0
	if not patrol_points.is_empty():
		agent.target_position = patrol_points[0]


func _physics_process(delta: float) -> void:
	if health.dead:
		return
	var player := get_tree().get_first_node_in_group("player") as Player
	var sees := player != null and player.alive and _can_see(player)
	if sees and _alert <= 0.0:
		_react = reaction_time
	if sees:
		_alert = alert_duration
	_alert -= delta
	_fire_cd -= delta

	velocity.x = 0.0
	velocity.z = 0.0
	if _alert > 0.0 and player:
		_face(player.global_position, delta)
		_react -= delta
		if shoots_back and sees and _react <= 0.0 and _fire_cd <= 0.0:
			_shoot(player)
			_fire_cd = fire_interval * randf_range(0.7, 1.3)
	elif not patrol_points.is_empty():
		_patrol(delta)
	velocity.y = 0.0 if is_on_floor() else velocity.y - _gravity * delta
	move_and_slide()


func _patrol(delta: float) -> void:
	if NavigationServer3D.map_get_iteration_id(agent.get_navigation_map()) == 0:
		return  # navmesh not baked yet
	if agent.is_navigation_finished():
		_patrol_index = (_patrol_index + 1) % patrol_points.size()
		agent.target_position = patrol_points[_patrol_index]
		return
	var next := agent.get_next_path_position()
	var dir := next - global_position
	dir.y = 0.0
	if dir.length() > 0.05:
		dir = dir.normalized()
		velocity.x = dir.x * move_speed
		velocity.z = dir.z * move_speed
		_face(next, delta)


func _face(target: Vector3, delta: float) -> void:
	var d := target - global_position
	rotation.y = rotate_toward(rotation.y, atan2(-d.x, -d.z), turn_speed * delta)


func _can_see(player: Player) -> bool:
	var eye := global_position + Vector3.UP * 1.6
	var target := player.camera.global_position
	if eye.distance_to(target) > sight_range:
		return false
	if _alert <= 0.0 and (-global_basis.z).dot((target - eye).normalized()) < 0.2:
		return false  # outside the view cone while unaware
	var q := PhysicsRayQueryParameters3D.create(eye, target, Ballistics.WORLD)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _shoot(player: Player) -> void:
	var from := muzzle.global_position
	var aim := player.camera.global_position + Vector3.DOWN * 0.35
	var dir := Ballistics.spread_dir((aim - from).normalized(), aim_error_deg)
	Ballistics.fire(get_world_3d().direct_space_state, from, dir, weapon, self, _hitbox_rids(), damage_scale)
	if weapon.fire_sound:
		if _audio == null:
			_audio = AudioStreamPlayer3D.new()
			_audio.bus = &"World"
			add_child(_audio)
			_audio.stream = weapon.fire_sound
			_audio.volume_db = weapon.fire_volume_db
		_audio.play()
	flash.visible = true
	await get_tree().create_timer(0.05).timeout
	flash.visible = false


func _on_damaged(_amount: float, _zone: StringName, source: Node) -> void:
	if source is Player and _alert <= 0.0:
		_react = reaction_time
		_alert = alert_duration


func _on_died(_source: Node) -> void:
	collision.set_deferred("disabled", true)
	_set_hitboxes(false)
	_fall = create_tween()
	_fall.tween_property(body, "rotation:x", PI * 0.5, 0.35).set_ease(Tween.EASE_IN)


func _hitboxes() -> Array[Hitbox]:
	var out: Array[Hitbox] = []
	for c in body.get_children():
		if c is Hitbox:
			out.append(c)
	return out


func _hitbox_rids() -> Array[RID]:
	var out: Array[RID] = []
	for hb in _hitboxes():
		out.append(hb.get_rid())
	return out


func _set_hitboxes(on: bool) -> void:
	for hb in _hitboxes():
		hb.set_enabled(on)
