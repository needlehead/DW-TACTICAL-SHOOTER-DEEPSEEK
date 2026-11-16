extends Control
## Title menu: Kei's render on the right with a live, Live2D-style idle (see live_portrait.gdshader) that
## follows the mouse, the menu on the left. Deploy loads the killhouse.

const GAME_SCENE := "res://maps/killhouse.tscn"

@export var look_smoothing := 4.0  ## how quickly the head follows the mouse (per second)

var _look := Vector2.ZERO

@onready var portrait: TextureRect = $Portrait
@onready var deploy: Button = %Deploy


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	deploy.pressed.connect(func() -> void: get_tree().change_scene_to_file(GAME_SCENE))
	%Quit.pressed.connect(get_tree().quit)
	deploy.grab_focus()  # keyboard / pad works without touching the mouse


func _process(delta: float) -> void:
	var vp := get_viewport_rect().size
	var target := ((get_viewport().get_mouse_position() / vp) * 2.0 - Vector2.ONE).clampf(-1.0, 1.0)
	_look = _look.lerp(target, 1.0 - exp(-look_smoothing * delta))
	(portrait.material as ShaderMaterial).set_shader_parameter("look", _look)
