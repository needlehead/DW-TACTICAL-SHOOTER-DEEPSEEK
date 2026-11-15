extends Node3D
## Footstep audio: a random clip from `steps` on each stride (louder when moving faster), plus jump and
## landing clips. On the Footsteps bus: the same room-aware reverb as gunfire, but lighter.
## `speed` is forwarded so AI hearing can hook the same signal later.

@export var steps: Array[AudioStream] = []
@export var volume_db := -8.0
@export var jump_sounds: Array[AudioStream] = []
@export var land_sounds: Array[AudioStream] = []

var _audio: AudioStreamPlayer3D


func _ready() -> void:
	_audio = AudioStreamPlayer3D.new()
	_audio.bus = &"Footsteps"
	_audio.max_polyphony = 3  # a landing can overlap the last step
	add_child(_audio)
	var player := get_parent() as Player
	player.footstep.connect(_on_footstep)
	player.jumped.connect(func() -> void: _play(jump_sounds, volume_db))
	player.landed.connect(func(fall: float) -> void: _play(land_sounds, volume_db + linear_to_db(clampf(fall / 6.0, 0.4, 1.0))))


func _play(clips: Array[AudioStream], db: float) -> void:
	if clips.is_empty():
		return
	_audio.stream = clips.pick_random()
	_audio.volume_db = db
	_audio.pitch_scale = randf_range(0.95, 1.05)
	_audio.play()


func _on_footstep(speed: float) -> void:
	if steps.is_empty():
		return
	_audio.stream = steps.pick_random()
	_audio.volume_db = volume_db + linear_to_db(clampf(speed / 5.0, 0.3, 1.0))
	_audio.pitch_scale = randf_range(0.94, 1.06)
	_audio.play()
