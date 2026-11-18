class_name DialogueBox
extends CanvasLayer
## Story dialogue screen: pauses the game, blurs it behind the character portraits and stacks the lines as speech
## boxes down the middle (Ingrid right of centre in orange, Kei left in green), the newest at the bottom; older
## ones scroll up when the column is full. F / Space / click shows the next line, Esc skips to the end.
## At a choice Kei's options appear as green boxes: click one or press its number; she says it and the
## conversation follows that branch (see Dialogue for the script format).
## F4 opens the VN sprite editor (PortraitEditor) to place the portraits.
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

var _steps: Array = []
var _labels := {}
var _pc := 0  # next step to run
var _rows := 0  # boxes put in the column so far
var _choices: Array = []  # [[box, label], ...] while a choice is up
var _since := 0.0  # ignores the key press that opened it
var _closing := false
var _stage := Control.new()
var _column := Control.new()  # holds the boxes; slides up as they pile up
var _blur := ColorRect.new()
var portraits: Array[Portrait] = []
var _portraits := Control.new()  # one full-screen layer per character portrait
var _layers: Array[TextureRect] = []
var _editor: PortraitEditor
var _font := preload("res://fonts/Barlow-Medium.ttf")


## Opens the conversation over the game (one at a time), with these character portraits.
static func open(dialogue: Dialogue, with_portraits: Array[Portrait], tree: SceneTree) -> DialogueBox:
	if tree.get_first_node_in_group(&"dialogue_box"):
		return null
	var box := DialogueBox.new()
	var compiled := dialogue.compile()
	box._steps = compiled.steps
	box._labels = compiled.labels
	box.portraits = with_portraits
	for p in with_portraits:
		var layer := TextureRect.new()
		layer.texture = p.texture
		layer.size = STAGE
		layer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		layer.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box._portraits.add_child(layer)
		box._layers.append(layer)
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
	_portraits.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	for i in _layers.size():
		var p := portraits[i]
		_layers[i].pivot_offset = p.pivot()
		_layers[i].position = p.offset
		_layers[i].scale = Vector2.ONE * p.scale


func stage_scale() -> float:
	return _stage.scale.x


func stage_to_screen(p: Vector2) -> Vector2:
	return _stage.position + p * _stage.scale.x


func toggle_editor() -> void:
	if _editor:
		_editor.queue_free()
		_editor = null
		return
	_editor = PortraitEditor.new()
	_editor.box = self
	add_child(_editor)


func _unhandled_input(event: InputEvent) -> void:
	if _closing or _since < 0.2:
		return
	if event.is_action_pressed("viewmodel_editor"):
		toggle_editor()
		get_viewport().set_input_as_handled()
		return
	if _editor:  # the conversation waits while placing portraits
		return
	if not _choices.is_empty():  # waiting for a pick: number keys (or a click on a box)
		if event is InputEventKey and event.pressed and not event.echo:
			var n := (event as InputEventKey).keycode - KEY_1
			if n >= 0 and n < _choices.size():
				_choose(n)
				get_viewport().set_input_as_handled()
		if event.is_action_pressed("ui_cancel"):
			close()
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


## Runs the script up to the next line (shown) or choice (waits for a pick); closes at the end.
func _next() -> void:
	while _pc < _steps.size():
		var step: Array = _steps[_pc]
		match step[0]:
			"goto":
				if step[1] == "end":
					break
				_pc = _labels.get(step[1], _steps.size())
			"say":
				_pc += 1
				_add_line(step[1], step[2])
				return
			"choose":
				_show_choices(step[1])
				return
	close()


func _add_line(speaker: String, text: String) -> void:
	var style: Array = SPEAKERS.get(speaker, OTHER)
	_place(_make_box("%s: %s" % [speaker, text], style[1], style[2]), style[0], _rows)
	_rows += 1
	_scroll()


## Kei's options, one box per row under the last line, numbered.
func _show_choices(options: Array) -> void:
	var style: Array = SPEAKERS["Kei"]
	for i in options.size():
		var box := _make_box("%d.  %s" % [i + 1, options[i][0]], style[1], style[2])
		box.mouse_filter = Control.MOUSE_FILTER_STOP
		box.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		box.mouse_entered.connect(func() -> void: box.self_modulate = Color(1.25, 1.25, 1.25))
		box.mouse_exited.connect(func() -> void: box.self_modulate = Color.WHITE)
		box.gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventMouseButton and e.pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
				_choose(i)
				box.accept_event())
		var outline := ReferenceRect.new()  # marks it as something to pick, not a line said yet
		outline.border_color = Color(1, 1, 1, 0.5)
		outline.border_width = 2.0
		outline.editor_only = false
		outline.size = BOX_SIZE
		outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(outline)
		_place(box, style[0], _rows + i)
		_choices.append([box, options[i][1], options[i][0]])
	_scroll(options.size())


## Kei says the picked option in place of the menu; the conversation jumps to its label.
func _choose(i: int) -> void:
	var picked: Array = _choices[i]
	for c: Array in _choices:
		c[0].queue_free()
	_choices.clear()
	_add_line("Kei", picked[2])
	var label: String = picked[1]
	_pc = _steps.size() if label == "end" else _labels.get(label, _steps.size())


## Puts a box in the column at a row and pops it in (fade up, slide in from its side).
func _place(box: Control, x: float, row: int) -> void:
	box.position = Vector2(x, ROW_TOP + row * ROW_PITCH)
	_column.add_child(box)
	box.modulate.a = 0.0
	var from_x := 24.0 if x > 842.0 else -24.0
	box.position.x += from_x
	var t := box.create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(box, "modulate:a", 1.0, 0.18)
	t.tween_property(box, "position:x", box.position.x - from_x, 0.22)


## Column full: scroll the oldest up out of view (extra = rows still taken below the lines, e.g. a choice menu).
func _scroll(extra := 0) -> void:
	var overflow := maxi(_rows + extra - MAX_ROWS, 0)
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
