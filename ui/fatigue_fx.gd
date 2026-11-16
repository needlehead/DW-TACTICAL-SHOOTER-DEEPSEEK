class_name FatigueFX
extends ColorRect
## Screen cue for low stamina: grey, dark edges that pulse with each breath; fades as stamina recovers.
## Drawn before the bodycam (so its REC overlay stays bright); while badly hurt the darkening backs off so the
## low-health red reads first.

@export var start := 0.2  ## fatigue (0..1) where the effect begins
@export var full := 0.9  ## fatigue where it is at full strength
@export var hurt_ease := 0.85  ## how much of the edge darkening drops out at near-zero health

@onready var player: Player = owner


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://ui/fatigue_fx.gdshader")
	material = mat


func _process(_delta: float) -> void:
	var s := smoothstep(start, full, player.fatigue) if player.alive else 0.0
	visible = s > 0.001
	if not visible:
		return
	position = Vector2.ZERO
	size = get_viewport_rect().size  # anchors alone leave it 0x0 under a CanvasLayer
	var mat := material as ShaderMaterial
	mat.set_shader_parameter("strength", s)
	mat.set_shader_parameter("pulse", 0.5 + 0.5 * sin(player.breath_phase()))
	var low: float = (owner.get_node("HUDLayer/DamageFeedback") as DamageFeedback).low_health
	var f := player.health.current / player.health.max_health
	var hurt := clampf(1.0 - f / low, 0.0, 1.0) if low > 0.0 else 0.0  # 0 above the heartbeat threshold .. 1 near death
	mat.set_shader_parameter("darken", 1.0 - hurt_ease * hurt)
