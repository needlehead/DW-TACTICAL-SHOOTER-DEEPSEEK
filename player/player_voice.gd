class_name PlayerVoice
extends Node
## The heroine's voice: a damage grunt when hit, a death sound when killed, and breathing that swells while
## sprinting and fades smoothly out when she stops. Swap the clip sets per heroine; the breath
## loop is generic (my sounds/generic/breath_loop.ogg, cut with tools/make_breath_loop.py).

@export var damage_sounds: Array[AudioStream] = []
@export var death_sounds: Array[AudioStream] = []
@export var breath_loop: AudioStream
@export var voice_db := -4.0
@export var breath_db := -18.0  ## breathing volume at full exertion
@export var damage_cooldown := 0.45  ## seconds; automatic fire doesn't stack grunts
@export var exertion_rise := 0.6  ## per second while sprinting
@export var exertion_fall := 0.5  ## per second after sprinting: fades out over ~2 s

var exertion := 0.0
var _breath_level := 0.0
var _since_hurt := 99.0
var _voice := AudioStreamPlayer.new()
var _breath := AudioStreamPlayer.new()

@onready var player: Player = owner


func _ready() -> void:
	add_child(_voice)
	add_child(_breath)
	_voice.volume_db = voice_db
	if breath_loop:
		breath_loop.set("loop", true)
		_breath.stream = breath_loop
		_breath.volume_db = -80.0
		_breath.play(randf() * breath_loop.get_length())  # random phase: heroines don't breathe in sync
	var health := owner.get_node("Health") as Health  # player's @onready refs aren't set yet
	health.damaged.connect(_on_damaged)
	health.died.connect(func(_source: Node) -> void: _say(death_sounds))


func _on_damaged(_amount: float, _zone: StringName, _source: Node) -> void:
	if player.health.dead or _since_hurt < damage_cooldown:
		return
	_since_hurt = 0.0
	_say(damage_sounds)


func _say(clips: Array[AudioStream]) -> void:
	if clips.is_empty():
		return
	_voice.stream = clips.pick_random()
	_voice.play()


## Breathing loudness 0..1: only from sprinting.
func breath_target() -> float:
	return exertion if player.alive else 0.0


func _process(delta: float) -> void:
	_since_hurt += delta
	exertion = clampf(exertion + (exertion_rise if player.is_sprinting else -exertion_fall) * delta, 0.0, 1.0)
	_breath_level = move_toward(_breath_level, breath_target(), delta * (4.0 if not player.alive else 1.0))
	# Squared fade sounds even to the ear: no audible "cut" as the level reaches zero.
	_breath.volume_db = linear_to_db(maxf(_breath_level * _breath_level, 0.0001)) + breath_db
