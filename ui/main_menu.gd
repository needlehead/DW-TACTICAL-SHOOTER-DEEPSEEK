extends Control
## Title menu: Kei's idle animation (frames rendered in Koikatsu) on the right, the menu on the left.
## Deploy loads the killhouse.

const GAME_SCENE := "res://maps/killhouse.tscn"
const FRAMES := "res://ui/menu_anim/%03d.webp"  ## cropped + scaled from koikatsu sprites/testing/menu/menuanim
const FRAME_COUNT := 120

@export var fps := 30.0
## The last frame doesn't match the first, so play forward then back to hide the seam.
@export var ping_pong := true

var _frames: Array[Texture2D] = []
var _t := 0.0

@onready var portrait: TextureRect = $Portrait
@onready var deploy: Button = %Deploy


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for i in FRAME_COUNT:
		_frames.append(load(FRAMES % i))
	portrait.texture = _frames[0]
	deploy.pressed.connect(func() -> void: get_tree().change_scene_to_file(GAME_SCENE))
	%Quit.pressed.connect(get_tree().quit)
	deploy.grab_focus()  # keyboard / pad works without touching the mouse


## Frame shown at time t (seconds).
func frame_at(t: float) -> int:
	var n := FRAME_COUNT
	var i := int(t * fps)
	if not ping_pong:
		return i % n
	i %= 2 * n - 2
	return i if i < n else 2 * n - 2 - i


func _process(delta: float) -> void:
	_t += delta
	portrait.texture = _frames[frame_at(_t)]
