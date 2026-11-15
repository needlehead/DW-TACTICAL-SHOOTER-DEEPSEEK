class_name DamageFeedback
extends ColorRect
## Getting hit: the screen edges flash red (scaled by damage), the view gets punched, and the bodycam lens
## glitches (colour fringing spike). Below low_health the edges pulse with a slow heartbeat.

@export var hit_per_damage := 1.0 / 35.0  ## flash strength per point of damage (35 dmg = full flash)
@export var hit_fade := 1.6  ## per second
@export var punch_deg := Vector2(1.2, 2.0)  ## max view kick (yaw, pitch) at a full flash
@export var lens_glitch := 0.02  ## extra bodycam aberration at a full flash
@export var low_health := 0.33  ## fraction of max health where the heartbeat vignette starts
@export var heartbeat_bpm := 80.0

var hit := 0.0
var _base_aberration := 0.006

@onready var player: Player = owner
@onready var bodycam: ColorRect = owner.get_node("PostFXLayer/Bodycam")


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://ui/damage_feedback.gdshader")
	material = mat
	var base: Variant = (bodycam.material as ShaderMaterial).get_shader_parameter("aberration")
	if base != null:
		_base_aberration = base
	(owner.get_node("Health") as Health).damaged.connect(_on_damaged)  # player's @onready refs aren't set yet


func _on_damaged(amount: float, _zone: StringName, _source: Node) -> void:
	var strength := clampf(amount * hit_per_damage, 0.15, 1.0)
	hit = clampf(hit + strength, 0.0, 1.0)
	player.recoil_target += Vector2(randf_range(-1.0, 1.0) * punch_deg.x, randf_range(0.3, 1.0) * punch_deg.y) * strength


## Heartbeat vignette strength 0..1 for a health fraction (0 above low_health).
func low_pulse(health_fraction: float, time: float) -> float:
	if health_fraction >= low_health or health_fraction <= 0.0:
		return 0.0
	var beat := pow(maxf(sin(time * TAU * heartbeat_bpm / 60.0), 0.0), 4.0)  # short thump per beat
	return (1.0 - health_fraction / low_health) * (0.55 + 0.45 * beat)


func _process(delta: float) -> void:
	hit = move_toward(hit, 0.0, hit_fade * delta)
	size = get_viewport_rect().size  # anchors alone leave it 0x0 under a CanvasLayer
	var f := player.health.current / player.health.max_health
	var low := low_pulse(f, Time.get_ticks_msec() / 1000.0) if player.alive else 0.0
	var mat := material as ShaderMaterial
	mat.set_shader_parameter("hit", hit)
	mat.set_shader_parameter("low", low)
	(bodycam.material as ShaderMaterial).set_shader_parameter("aberration", _base_aberration + lens_glitch * hit)
