class_name Door
extends AnimatableBody3D
## Hinged door (origin = hinge). Interact toggles it; it swings away from whoever opened it.
## On the penetrable layer, so bullets go through.

@export var open_angle := 100.0
@export var swing_time := 0.45

var is_open := false
var _closed_yaw := 0.0
var _tween: Tween


func _ready() -> void:
	add_to_group("resettable")
	_closed_yaw = rotation.y


func interact(user: Node3D) -> void:
	is_open = not is_open
	var target := _closed_yaw
	if is_open:
		var side := signf(global_basis.z.dot(user.global_position - global_position))
		target += deg_to_rad(open_angle) * (side if side != 0.0 else 1.0)
	if _tween:
		_tween.kill()
	_tween = create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_tween.tween_property(self, "rotation:y", target, swing_time).set_trans(Tween.TRANS_SINE)


func reset() -> void:
	if _tween:
		_tween.kill()
	is_open = false
	rotation.y = _closed_yaw
