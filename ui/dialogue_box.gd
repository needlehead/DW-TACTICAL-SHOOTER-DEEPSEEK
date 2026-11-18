class_name DialogueBox
extends CanvasLayer
## Story dialogue screen: pauses the game, blurs it behind the character portraits and stacks the lines as speech
## boxes down the middle (Ingrid right of centre in orange, Kei left in green), the newest at the bottom; older
## ones scroll up when the column is full. F / Space / click shows the next line, Esc skips to the end.
## Laid out on a 1920x1080 stage scaled to the screen height.

signal finished

const STAGE := Vector2(1920.0, 1080.0)
const BOX_SIZE := Vector2(382.0, 86.0)
const ROW_TOP := 107.0
const ROW_PITCH := 115.0
const MAX_ROWS := 8
## Speaker -> [box left x on the stage, gradient top colour, gradient bottom colour]. Others sit centred in grey.
const SPEAKERS := {
	"Ingrid": [925.0, Color(0.22, 0.17, 0.12), Color(0.82, 0.56, 0.17)],
	"Kei": [760.0, Color(0.13, 0.19, 0.17), Color(0.32, 0.58, 0.39)],
}
const OTHER := [842.0, Color(0.16, 0.16, 0.17), Color(0.42, 0.42, 0.44)]

var _lines: Array = []
var _shown := 0
var _since := 0.0  # ignores the key press that opened it
var _closing := false
var _stage := Control.new()
var _column := Control.new()  # holds the boxes; slides up as they pile up
var _blur := ColorRect.new()
var _portraits := TextureRect.new()
var _font := preload("res://fonts/Barlow-Medium.ttf")


## Opens the conversation over the game (one at a time). portraits: the full-screen character art.
static func open(dialogue: Dialogue, portraits: Texture2D, tree: SceneTree) -> DialogueBox:
	if tree.get_first_node_in_group(&"dialogue_box"):
		return null
	var box := DialogueBox.new()
	box._lines = dialogue.lines()
	box._portraits.texture = portraits
	tree.root.add_child(box)
	return box


func _ready() -> void:
	add_to_group(&"dialogue_box")
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	var mat := ShaderMaterial.new()
	mat.shader = preload("res://ui/dialogue_blur.gdshader")
	mat.set_shader_parameter("amount", 0.0)
	_blur.material = mat
	_blur.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_blur)

	_stage.size = STAGE
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stage)
	_portraits.size = STAGE
	_portraits.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portraits.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portraits.modulate.a = 0.0
	_stage.add_child(_portraits)
	_stage.add_child(_column)

	var hint := Label.new()
	hint.text = "F / Click   next          Esc   skip"
	hint.add_theme_font_override("font", _font)
	hint.add_theme_font_size_override("font_size", 22)
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	hint.add_theme_constant_override("outline_size", 6)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.position = Vector2(0.0, STAGE.y - 52.0)
	hint.size = Vector2(STAGE.x, 40.0)
	_stage.add_child(hint)

	var t := create_tween().set_parallel()
	t.tween_property(mat, "shader_parameter/amount", 1.0, 0.25)
	t.tween_property(_portraits, "modulate:a", 1.0, 0.3)
	_next()


func _process(delta: float) -> void:
	_since += delta
	var vp := get_viewport().get_visible_rect().size
	_blur.size = vp
	var k := vp.y / STAGE.y
	_stage.scale = Vector2(k, k)
	_stage.position = Vector2((vp.x - STAGE.x * k) * 0.5, 0.0)


func _unhandled_input(event: InputEvent) -> void:
	if _closing or _since < 0.2:
		return
	var next: bool = event.is_action_pressed("interact") or event.is_action_pressed("ui_accept") \
		or (event is InputEventMouseButton and event.pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT)
	if next:
		_next()
	elif event.is_action_pressed("ui_cancel"):
		close()
	else:
		return
	get_viewport().set_input_as_handled()


## Shows the next line, or closes after the last.
func _next() -> void:
	if _shown >= _lines.size():
		close()
		return
	var line: Array = _lines[_shown]
	var row := _shown
	_shown += 1
	var style: Array = SPEAKERS.get(line[0], OTHER)
	var box := _make_box("%s: %s" % line, style[1], style[2])
	box.position = Vector2(style[0], ROW_TOP + row * ROW_PITCH)
	_column.add_child(box)
	# Pop in: fade up and slide in from its side.
	box.modulate.a = 0.0
	var from_x := 24.0 if style[0] > 842.0 else -24.0
	box.position.x += from_x
	var t := box.create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(box, "modulate:a", 1.0, 0.18)
	t.tween_property(box, "position:x", box.position.x - from_x, 0.22)
	# Column full: scroll the oldest up out of view.
	var overflow := maxi(_shown - MAX_ROWS, 0)
	if overflow > 0:
		create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT) \
			.tween_property(_column, "position:y", -overflow * ROW_PITCH, 0.25)


func _make_box(text: String, top: Color, bottom: Color) -> Control:
	var box := Control.new()
	box.size = BOX_SIZE
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var g := Gradient.new()
	g.set_color(0, top)
	g.set_color(1, bottom)
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0.5, 0.0)
	gt.fill_to = Vector2(0.5, 1.0)
	var bg := TextureRect.new()
	bg.texture = gt
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.size = BOX_SIZE
	bg.modulate.a = 0.94
	box.add_child(bg)
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", _font)
	label.add_theme_font_size_override("font_size", 26 if text.length() <= 34 else 21)
	label.add_theme_color_override("font_color", Color(1, 1, 1))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.35))
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.position = Vector2(24.0, 0.0)
	label.size = BOX_SIZE - Vector2(48.0, 0.0)
	box.add_child(label)
	return box


func close() -> void:
	if _closing:
		return
	_closing = true
	var t := create_tween().set_parallel()
	t.tween_property(_blur.material, "shader_parameter/amount", 0.0, 0.2)
	t.tween_property(_stage, "modulate:a", 0.0, 0.2)
	await t.finished
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	finished.emit()
	queue_free()
