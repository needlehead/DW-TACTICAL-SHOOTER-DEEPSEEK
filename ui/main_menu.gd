extends Control
## Title menu: Kei's idle animation (frames rendered in Koikatsu) on the right, the menu on the left.
## Deploy loads the killhouse. Look follows the design mockup in docs/ui_mockup (Barlow, filled = selected).

const GAME_SCENE := "res://maps/killhouse.tscn"
const FRAMES := "res://ui/menu_anim/%03d.webp"  ## cropped + scaled from koikatsu sprites/testing/menu/menuanim
const FRAME_COUNT := 120
const TEXT := Color("#E8ECF2")
const DIM := Color("#93A3BC")
const INK := Color("#0B0D12")

@export var fps := 30.0
## The last frame doesn't match the first, so play forward then back to hide the seam.
@export var ping_pong := true
@export var accent := Color("#45D27A")

var _frames: Array[Texture2D] = []
var _t := 0.0

@onready var portrait: TextureRect = $Portrait
@onready var deploy: Button = %Deploy


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for i in FRAME_COUNT:
		_frames.append(load(FRAMES % i))
	portrait.texture = _frames[0]
	_style()
	deploy.pressed.connect(func() -> void: get_tree().change_scene_to_file(GAME_SCENE))
	%Quit.pressed.connect(get_tree().quit)
	deploy.grab_focus()  # keyboard / pad works without touching the mouse


func _style() -> void:
	var cond := load("res://fonts/BarlowCondensed-SemiBold.ttf")
	var bold := load("res://fonts/BarlowCondensed-Bold.ttf")
	_label($Menu/Tag, _spaced(cond, 4), 16, DIM)
	_label($Menu/Title, _spaced(bold, 2), 84, TEXT)
	_label($Menu/Subtitle, _spaced(cond, 3), 20, accent)
	_label($Hint, _spaced(cond, 2), 15, DIM)
	# Outlined at rest, filled when selected: keyboard focus and the mouse move the same selection.
	var rest := _box(Color(TEXT, 0.04), Color(TEXT, 0.22))
	var picked := _box(TEXT, TEXT)
	for b: Button in [deploy, %Quit]:
		b.add_theme_font_override("font", _spaced(bold, 3))
		b.add_theme_font_size_override("font_size", 26)
		b.add_theme_stylebox_override("normal", rest)
		for state in ["hover", "pressed", "focus", "hover_pressed"]:
			b.add_theme_stylebox_override(state, picked)
		b.add_theme_color_override("font_color", TEXT)
		for state in ["font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
			b.add_theme_color_override(state, INK)
		b.mouse_entered.connect(b.grab_focus)


func _label(l: Label, f: Font, px: int, col: Color) -> void:
	l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", col)


func _spaced(base: Font, spacing: int) -> FontVariation:
	var f := FontVariation.new()
	f.base_font = base
	f.spacing_glyph = spacing
	return f


func _box(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(2)
	s.content_margin_left = 24
	s.content_margin_right = 24
	return s


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
