class_name FatigueFX
extends ColorRect
## Screen cue for low stamina: grey, dark edges that pulse with each breath; fades as stamina recovers.

@export var start := 0.2  ## fatigue (0..1) where the effect begins
@export var full := 0.9  ## fatigue where it is at full strength

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
