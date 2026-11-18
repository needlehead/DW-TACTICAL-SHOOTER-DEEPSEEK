class_name PortraitEditor
extends Control
## VN sprite editor (F4 while a conversation is open): place the character portraits. Click a character to select
## it, drag to move, mouse wheel to scale (around her feet), arrow keys nudge (Shift = x10). Save writes each
## edited Portrait .tres; Revert restores what they had when the editor opened. The conversation waits meanwhile.

const DIM := Color(0.62, 0.68, 0.78)

var box: DialogueBox
var selected := 0
var _drag := false
var _originals := {}  # Portrait -> [offset, scale]
var _panel := PanelContainer.new()
var _panel_drag := false
var _pick: HBoxContainer
var _spins: Array[SpinBox] = []  # x, y, scale
var _syncing := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	for p in box.portraits:
		_originals[p] = [p.offset, p.scale]

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.06, 0.07, 0.09, 0.92)
	bg.border_color = Color(1, 1, 1, 0.1)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(8)
	bg.set_content_margin_all(12)
	_panel.add_theme_stylebox_override("panel", bg)
	_panel.position = Vector2(16, 16)
	add_child(_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.custom_minimum_size.x = 380
	_panel.add_child(col)

	var title := HBoxContainer.new()
	title.mouse_filter = Control.MOUSE_FILTER_STOP
	title.mouse_default_cursor_shape = Control.CURSOR_MOVE
	title.gui_input.connect(_on_title_input)
	col.add_child(title)
	var name_label := _label(title, "VN SPRITE EDITOR", 15, Color.WHITE)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label(title, "drag to move", 12, DIM)

	_pick = HBoxContainer.new()
	col.add_child(_pick)
	var group := ButtonGroup.new()
	for i in box.portraits.size():
		var b := _button(_pick, box.portraits[i].resource_path.get_file().get_basename().capitalize(), select.bind(i))
		b.toggle_mode = true
		b.button_group = group
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	col.add_child(HSeparator.new())
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	col.add_child(grid)
	for f in [["offset x", 1.0], ["offset y", 1.0], ["scale", 0.01]]:
		_label(grid, f[0], 14, DIM)
		var s := SpinBox.new()
		s.step = 0.001
		s.custom_arrow_step = f[1]
		s.allow_greater = true
		s.allow_lesser = true
		s.min_value = -4000.0
		s.max_value = 4000.0
		s.select_all_on_focus = true
		s.custom_minimum_size.x = 140
		s.value_changed.connect(_on_spin.bind(_spins.size()))
		grid.add_child(s)
		_spins.append(s)
	var help := _label(col, "Click a character to pick her, drag to move, wheel to scale (around her feet). "
		+ "Arrows nudge, Shift = x10. Offsets are pixels of a 1080p screen.", 13, DIM)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.custom_minimum_size.x = 380
	col.add_child(HSeparator.new())
	var foot := HBoxContainer.new()
	col.add_child(foot)
	_button(foot, "Save", save).tooltip_text = "Write the portraits' placement to their .tres files"
	_button(foot, "Revert", revert).tooltip_text = "Back to the placement from when the editor opened"
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(spacer)
	_button(foot, "Close (F4)", box.toggle_editor)
	select(0)


func _button(parent: Node, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE  # keep arrow keys for nudging
	b.pressed.connect(action)
	parent.add_child(b)
	return b


func _label(parent: Node, text: String, px: int, c: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", c)
	parent.add_child(l)
	return l


func current() -> Portrait:
	return box.portraits[selected] if selected < box.portraits.size() else null


func select(i: int) -> void:
	selected = i
	for j in _pick.get_child_count():
		(_pick.get_child(j) as Button).set_pressed_no_signal(j == i)


func save() -> void:
	var failed := []
	for p in box.portraits:
		if ResourceSaver.save(p) != OK:
			failed.append(p.resource_path.get_file())
		else:
			_originals[p] = [p.offset, p.scale]
	Game.toast("Saved portraits" if failed.is_empty() else "Save failed: " + ", ".join(failed))


func revert() -> void:
	for p: Portrait in _originals:
		p.offset = _originals[p][0]
		p.scale = _originals[p][1]


func _on_spin(x: float, i: int) -> void:
	var p := current()
	if p == null or _syncing:
		return
	match i:
		0: p.offset.x = x
		1: p.offset.y = x
		2: p.scale = maxf(x, 0.05)


func _on_title_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_panel_drag = event.pressed
	elif event is InputEventMouseMotion and _panel_drag:
		_panel.position = (_panel.position + (event as InputEventMouseMotion).relative).clamp(Vector2.ZERO, size - _panel.size)


## A portrait's drawn area on screen.
func screen_rect(p: Portrait) -> Rect2:
	var r := p.drawn_rect()
	var piv := p.pivot()
	var a := piv + p.offset + (r.position - piv) * p.scale
	return Rect2(box.stage_to_screen(a), r.size * p.scale * box.stage_scale())


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		get_viewport().gui_release_focus()  # leave the number boxes so arrows nudge again
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_drag = mb.pressed
			if mb.pressed:  # pick the character under the mouse (the last drawn wins)
				for i in range(box.portraits.size() - 1, -1, -1):
					if screen_rect(box.portraits[i]).has_point(mb.position):
						select(i)
						break
		elif mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and current():
			current().scale *= 1.02 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.02
		accept_event()
	elif event is InputEventMouseMotion and _drag and current():
		current().offset += (event as InputEventMouseMotion).relative / box.stage_scale()
		accept_event()


func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or current() == null:
		return
	if get_viewport().gui_get_focus_owner() is LineEdit:  # typing in a number box
		return
	var k := event as InputEventKey
	var dirs := {KEY_LEFT: Vector2.LEFT, KEY_RIGHT: Vector2.RIGHT, KEY_UP: Vector2.UP, KEY_DOWN: Vector2.DOWN}
	if dirs.has(k.keycode):
		current().offset += dirs[k.keycode] * (10.0 if k.shift_pressed else 1.0)
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	size = get_viewport_rect().size  # anchors leave it 0x0 under a CanvasLayer
	var p := current()
	if p:
		_syncing = true
		var vals := [p.offset.x, p.offset.y, p.scale]
		for i in 3:
			if not _spins[i].get_line_edit().has_focus():
				_spins[i].set_value_no_signal(vals[i])
		_syncing = false
	queue_redraw()


func _draw() -> void:
	for i in box.portraits.size():
		var r := screen_rect(box.portraits[i])
		var on := i == selected
		draw_rect(r, Color(0.3, 1.0, 0.6, 0.9 if on else 0.25), false, 2.0 if on else 1.0)
		if on:
			var piv := box.stage_to_screen(box.portraits[i].pivot() + box.portraits[i].offset)
			draw_circle(piv, 5.0, Color(1, 0.8, 0.2))
