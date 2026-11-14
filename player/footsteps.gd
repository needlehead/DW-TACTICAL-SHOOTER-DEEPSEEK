extends Node3D
## Footstep audio hook. No assets yet: drop streams into `steps` and they play on each stride.
## `speed` is forwarded so AI hearing can hook the same signal later.

@export var steps: Array[AudioStream] = []
@export var volume_db := -8.0

var _audio := AudioStreamPlayer3D.new()


func _ready() -> void:
	add_child(_audio)
	(get_parent() as Player).footstep.connect(_on_footstep)


func _on_footstep(speed: float) -> void:
	if steps.is_empty():
		return
	_audio.stream = steps.pick_random()
	_audio.volume_db = volume_db + linear_to_db(clampf(speed / 5.0, 0.3, 1.0))
	_audio.play()
