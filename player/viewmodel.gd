extends Node3D
## Viewmodel pose: hip/ADS blend, freeaim, look sway, movement inertia, bob, recoil kick,
## sprint pose, reload tilt, switch lowering and lowering against walls.

@export var sway_amount := 0.25  ## look-delta degrees -> radians of lag
@export var sway_smooth := 10.0
@export var inertia := 0.012  ## metres of lag per m/s of velocity
@export var bob_amount := 0.012
@export var kick_return := 14.0
@export var wall_check_extra := 0.15  ## added to gun length for the wall probe

var _sway := Vector2.ZERO
var _inertia := Vector3.ZERO
var _bob_t := 0.0
var _kick_pos := Vector3.ZERO
var _kick_rot := Vector3.ZERO
var _reload_blend := 0.0

@onready var player: Player = owner
@onready var manager: WeaponManager = $Weapons


func _ready() -> void:
	for w in manager.weapons:
		w.fired.connect(_on_fired.bind(w))


func _on_fired(w: Weapon) -> void:
	var d := w.data
	var ads := player.ads_blend
	_kick_pos.z += d.vm_kick_back * (1.0 - 0.4 * ads)
	_kick_rot.x += deg_to_rad(d.vm_kick_rot) * (1.0 - 0.5 * ads)
	_kick_rot.z += deg_to_rad(randf_range(-1.0, 1.0) * d.vm_kick_rot * 0.5)


func _process(delta: float) -> void:
	var d := manager.current.data
	var ads := player.ads_blend
	var still := 1.0 - 0.8 * ads

	_sway = _sway.lerp(-player.look_delta * deg_to_rad(sway_amount) * still, minf(1.0, sway_smooth * delta))
	player.look_delta = Vector2.ZERO

	var local_vel := player.global_basis.inverse() * player.velocity
	_inertia = _inertia.lerp(-local_vel * inertia * still, minf(1.0, 6.0 * delta))

	var hs := player.horizontal_speed()
	if player.is_on_floor():
		_bob_t += delta * hs * 2.4
	var bob := Vector3(sin(_bob_t) * bob_amount, absf(cos(_bob_t)) * bob_amount, 0.0) * minf(hs / 3.0, 1.6) * (1.0 - 0.85 * ads)

	_kick_pos = _kick_pos.lerp(Vector3.ZERO, minf(1.0, kick_return * delta))
	_kick_rot = _kick_rot.lerp(Vector3.ZERO, minf(1.0, kick_return * delta))
	_reload_blend = move_toward(_reload_blend, 1.0 if manager.current.is_reloading() else 0.0, delta * 4.0)
	_update_wall_block(d, delta)

	var lower := maxf(player.wall_block, manager.switch_phase)
	var sprint := player.sprint_blend
	var pose := d.hip_offset.lerp(Vector3(0.0, 0.0, -d.ads_distance), ads)
	position = pose + bob + _inertia + _kick_pos \
		+ Vector3(0.0, -0.22, 0.08) * lower + Vector3(-0.05, -0.06, 0.0) * sprint + Vector3(0, -0.05, 0) * _reload_blend
	rotation = Vector3(
		deg_to_rad(player.freeaim.y) + _sway.y + _kick_rot.x - 0.9 * lower - 0.35 * sprint - 0.3 * _reload_blend,
		deg_to_rad(player.freeaim.x) + _sway.x + 0.7 * sprint,
		_kick_rot.z + 0.6 * _reload_blend + 0.2 * sprint)


## Pull the gun down when its length would intersect geometry in front ("weapon lowering").
func _update_wall_block(d: WeaponData, delta: float) -> void:
	var cam := player.camera
	var length := d.vm_size.z + absf(d.hip_offset.z) + wall_check_extra
	var from := cam.global_position
	var q := PhysicsRayQueryParameters3D.create(from, from - player.aim_basis().z * length, Ballistics.WORLD)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var target := 0.0
	if not hit.is_empty():
		target = clampf(inverse_lerp(length, length * 0.45, from.distance_to(hit.position)), 0.0, 1.0)
	player.wall_block = move_toward(player.wall_block, target, delta * 5.0)
