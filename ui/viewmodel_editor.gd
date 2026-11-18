class_name ViewmodelEditor
extends Control
## In-game viewmodel alignment editor (F4). Frees the mouse and edits sprite placement. The panel is a small
## window: drag its title bar to move it; every value of the current mode has a number box (type or use the arrows).
##   Hip    - drag the gun (or arrow keys) to set sprite_offset; changes show live.
##   Sight  - the last aim frame fills the screen; drag the box over the sight glass / lens to set sight_window
##            (or canted_sight_window while the canted sight is selected: Canted button)
##            (drag the corner handle or mouse wheel to resize, arrows nudge, Shift = bigger steps).
##   Muzzle - the idle frame fills the screen; click the barrel end to set muzzle_uv (suppressor smoke origin).
##   Tablet - raises the phone; drag to move it, mouse wheel to bring it closer / further (phone_layout.tres).
##   Dead   - shows the death view while alive (Standing / Prone button picks which): drag moves the death frame,
##            wheel scales it, right-drag moves its tilt centre, [ ] tilt (roll) the view,
##            PgUp / PgDn camera height (death_view.tres).
##   Legs   - the legs walk in place (Walk / Sprint button picks the speed); cycle_length / run_cycle_length set how
##            fast they step; in the sprint preview drag moves the run frames and wheel scales them (body_view.tres).
## Save writes the edited resource; Revert restores what it had when the editor opened.

enum Mode { HIP, SIGHT, MUZZLE, TABLET, DEAD, LEGS }

const STEP := 0.001  ## arrow-key nudge (fraction of screen); Shift x10
const HANDLE := 14.0  ## corner handle size in pixels
const MODE_NAMES := ["Hip", "Sight", "Muzzle", "Tablet", "Dead", "Legs"]
const HELP := [
	"Drag the gun on screen to place it. Arrows nudge, Shift = x10.",
	"Drag the green box over the sight glass; corner handle or wheel resizes. Canted switches to the canted sight.",
	"Click the barrel end on screen: muzzle flash, smoke and laser come from here.",
	"Drag to move the tablet, wheel = closer / further. Arrows nudge.",
	"Camera: pitch / yaw / roll of this death, its keep_look (1 = keep where she was looking), height, settle time. Frame: drag moves it, wheel scales, right-drag moves its tilt centre (yellow). [ ] roll, PgUp / PgDn height.",
	"cycle_length / run_cycle_length: metres per loop of the walk / run. Feet sliding: raise it (slower legs); stepping too fast: lower it. Sprint preview: drag moves the run frames, wheel scales them, to line up with the walk.",
]
const DIM := Color(0.62, 0.68, 0.78)

var mode := Mode.HIP
var dead_kind := 0  ## Dead mode previews Player.DEATHS[dead_kind]
const DEATH_NAMES := ["standing", "prone", "standing 2", "launched (grenade)"]
var legs_sprint := false  ## Legs mode previews at sprint speed
var _drag := ""  # "", "move", "resize" or "pivot"
var _originals := {}  # Resource -> {property: value}
var _mode_buttons: Array[Button] = []
var _panel := PanelContainer.new()
var _panel_drag := false
var _context: Label
var _next_button: Button
var _canted_button: Button
var _prone_button: Button
var _speed_button: Button
var _fields: GridContainer
var _spins: Array = []  # [SpinBox, Resource, property, component]
var _fields_key := ""  # what the number boxes were built for; rebuilt when it changes
var _help: Label

@onready var player: Player = owner


func _ready() -> void:
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.06, 0.07, 0.09, 0.92)
	bg.border_color = Color(1, 1, 1, 0.1)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(8)
	bg.set_content_margin_all(12)
	bg.shadow_color = Color(0, 0, 0, 0.4)
	bg.shadow_size = 8
	_panel.add_theme_stylebox_override("panel", bg)
	_panel.position = Vector2(16, 16)
	add_child(_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.custom_minimum_size.x = 440
	_panel.add_child(col)

	# Title bar: drag it to move the window.
	var title := HBoxContainer.new()
	title.mouse_filter = Control.MOUSE_FILTER_STOP
	title.mouse_default_cursor_shape = Control.CURSOR_MOVE
	title.gui_input.connect(_on_title_input)
	col.add_child(title)
	var name_label := _label(title, "VIEWMODEL EDITOR", 15, Color.WHITE)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label(title, "drag to move", 12, DIM)
	_button(title, "  ×  ", toggle).tooltip_text = "Close (F4)"

	# Mode tabs.
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 2)
	col.add_child(tabs)
	var group := ButtonGroup.new()
	for m in MODE_NAMES.size():
		var b := _button(tabs, MODE_NAMES[m], set_mode.bind(m))
		b.toggle_mode = true
		b.button_group = group
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_mode_buttons.append(b)

	# What is being edited, and the buttons that switch it.
	var ctx := HBoxContainer.new()
	col.add_child(ctx)
	_context = _label(ctx, "", 14, Color.WHITE)
	_context.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_next_button = _button(ctx, "Next weapon", _next_weapon)
	_canted_button = _button(ctx, "Canted", func() -> void: player.weapons.current.toggle_canted())
	_prone_button = _button(ctx, "Standing", func() -> void:
		dead_kind = (dead_kind + 1) % DEATH_NAMES.size()
		player.death_t = 0.0  # play it from the start (the launch is an animation)
		_sync_preview())
	_speed_button = _button(ctx, "Walk", func() -> void:
		legs_sprint = not legs_sprint
		_sync_preview())

	col.add_child(HSeparator.new())
	_fields = GridContainer.new()
	_fields.columns = 2
	_fields.add_theme_constant_override("h_separation", 12)
	col.add_child(_fields)
	_help = _label(col, "", 13, DIM)
	_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_help.custom_minimum_size.x = 440
	col.add_child(HSeparator.new())

	var foot := HBoxContainer.new()
	col.add_child(foot)
	_button(foot, "Save", save).tooltip_text = "Write the edited values to their .tres file"
	_button(foot, "Revert", revert).tooltip_text = "Back to the values from when the editor opened"
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(spacer)
	_button(foot, "Close (F4)", toggle)
	set_mode(Mode.HIP)


func _button(parent: Node, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE  # keep arrow keys for nudging
	b.pressed.connect(action)
	parent.add_child(b)
	return b


func _label(parent: Node, text: String, px: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", col)
	parent.add_child(l)
	return l


func _on_title_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_panel_drag = event.pressed
	elif event is InputEventMouseMotion and _panel_drag:
		var vp := get_viewport_rect().size
		_panel.position = (_panel.position + (event as InputEventMouseMotion).relative).clamp(Vector2.ZERO, vp - _panel.size)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("viewmodel_editor"):
		toggle()


func toggle() -> void:
	visible = not visible
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if visible else Input.MOUSE_MODE_CAPTURED
	player.weapons.phone_forced = visible and mode == Mode.TABLET
	_sync_preview()
	if visible:
		_remember(data())
		_remember_layout()
		_remember_view()
		_remember_body()


func _remember_body() -> void:
	var b := body_view()
	if not _originals.has(b):
		_originals[b] = {"cycle_length": b.cycle_length, "run_cycle_length": b.run_cycle_length, "run_scale": b.run_scale,
			"run_offset": b.run_offset}


func death_view() -> DeathView:
	return player.death_view


func body_view() -> BodyView:
	return (player.get_node("ViewmodelLayer/BodySprite") as Node).get("view")


func _sync_preview() -> void:
	if player.weapons:  # null during _ready
		player.preview_death = dead_kind + 1 if visible and mode == Mode.DEAD else 0
		player.preview_walk = (player.sprint_speed if legs_sprint else player.walk_speed) if visible and mode == Mode.LEGS else 0.0


## The resource the current mode edits (what Save and Revert act on).
func _target() -> Resource:
	return layout() if mode == Mode.TABLET else death_view() if mode == Mode.DEAD else body_view() if mode == Mode.LEGS else data()


func layout() -> PhoneLayout:
	return (player.get_node("ViewmodelLayer/Phone") as Node).get("layout")


func data() -> WeaponData:
	return player.weapons.current.data


## The sight window being edited: the canted one while the canted sight is active.
func _window_prop() -> String:
	var w := player.weapons.current
	return "canted_sight_window" if w.using_canted() else "sight_window"


func _window() -> Rect2:
	return data().get(_window_prop())


func _set_window(r: Rect2) -> void:
	data().set(_window_prop(), r)


func set_mode(m: int) -> void:
	mode = m
	if player.weapons:  # null during _ready, before the player has set up its weapons
		player.weapons.phone_forced = visible and m == Mode.TABLET
	for i in _mode_buttons.size():
		_mode_buttons[i].set_pressed_no_signal(i == m)
	_sync_preview()


## Arrow-key nudge (dir in screen fractions); also the entry point tests use.
func nudge(dir: Vector2) -> void:
	var d := data()
	match mode:
		Mode.HIP:
			d.sprite_offset += dir
		Mode.SIGHT:
			_set_window(Rect2(_window().position + dir, _window().size))
		Mode.MUZZLE:
			d.muzzle_uv += dir
		Mode.TABLET:
			layout().hold_offset += dir
		Mode.DEAD:
			_set_dead("offset", _dead("offset") + dir)
		Mode.LEGS:
			if legs_sprint:
				body_view().run_offset += dir
			else:
				body_view().cycle_length = maxf(0.5, body_view().cycle_length - dir.y * 10.0)  # up = slower legs


## The previewed death's settings (DeathView stand_*, prone_*, stand2_* or launch_*).
func _dead(prop: String) -> Variant:
	return death_view().get(Player.DEATHS[dead_kind] + prop)


func _set_dead(prop: String, value: Variant) -> void:
	death_view().set(Player.DEATHS[dead_kind] + prop, value)


func save() -> void:
	var res := _target()
	var err := ResourceSaver.save(res)
	Game.toast(("Saved " + res.resource_path.get_file()) if err == OK else "Save failed (%s)" % error_string(err))
	if err == OK:
		_originals.erase(res)
		_remember(data())
		_remember_layout()
		_remember_view()
		_remember_body()


func revert() -> void:
	var res := _target()
	for p: String in _originals.get(res, {}):
		res.set(p, _originals[res][p])


func _remember_layout() -> void:
	var l := layout()
	if not _originals.has(l):
		_originals[l] = {"hold_scale": l.hold_scale, "hold_offset": l.hold_offset}


func _remember_view() -> void:
	var v := death_view()
	if not _originals.has(v):
		_originals[v] = {}
		for prop: Dictionary in v.get_property_list():
			if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
				_originals[v][prop.name] = v.get(prop.name)


func _remember(d: WeaponData) -> void:
	if not _originals.has(d):
		_originals[d] = {"sprite_offset": d.sprite_offset, "sight_window": d.sight_window,
			"canted_sight_window": d.canted_sight_window, "muzzle_uv": d.muzzle_uv}


func _next_weapon() -> void:
	var m := player.weapons
	var next := (m.weapons.find(m.current) + 1) % m.weapons.size()
	_remember(m.weapons[next].data)
	m.select(next)


# --- Number boxes ---------------------------------------------------------------------------------------------

## The values the current mode edits: [label, resource, property, step].
func _field_specs() -> Array:
	var d := data()
	match mode:
		Mode.HIP:
			return [["sprite_offset", d, "sprite_offset", 0.001]]
		Mode.SIGHT:
			return [[_window_prop(), d, _window_prop(), 0.001]]
		Mode.MUZZLE:
			return [["muzzle_uv", d, "muzzle_uv", 0.001]]
		Mode.TABLET:
			return [["hold_offset", layout(), "hold_offset", 0.001], ["hold_scale", layout(), "hold_scale", 0.01]]
		Mode.LEGS:
			var b := body_view()
			return [["cycle_length", b, "cycle_length", 0.1], ["run_cycle_length", b, "run_cycle_length", 0.1],
				["run_scale", b, "run_scale", 0.01], ["run_offset", b, "run_offset", 0.001]]
	var v := death_view()
	var p: String = Player.DEATHS[dead_kind]
	var specs := [[p + "pitch", v, p + "pitch", 1.0], [p + "yaw", v, p + "yaw", 1.0], [p + "roll", v, p + "roll", 0.5],
		[p + "keep_look", v, p + "keep_look", 0.05], ["eye_height", v, "eye_height", 0.01], ["camera_time", v, "camera_time", 0.05],
		[p + "offset", v, p + "offset", 0.001], [p + "scale", v, p + "scale", 0.01], [p + "pivot", v, p + "pivot", 0.005]]
	if p == "launch_":
		specs += [["launch_time", v, "launch_time", 0.05], ["launch_height", v, "launch_height", 0.05],
			["launch_spin", v, "launch_spin", 15.0]]
	return specs


func _rebuild_fields() -> void:
	for n in _fields.get_children():
		n.queue_free()
	_spins.clear()
	for spec: Array in _field_specs():
		_label(_fields, spec[0], 14, DIM)
		var row := HBoxContainer.new()
		_fields.add_child(row)
		var value: Variant = (spec[1] as Resource).get(spec[2])
		var names: Array = {TYPE_VECTOR2: ["x ", "y "], TYPE_RECT2: ["x ", "y ", "w ", "h "]}.get(typeof(value), [""])
		for i in names.size():
			var s := SpinBox.new()
			s.step = 0.0001  # display / typing precision; the arrows use the coarser per-field step
			s.custom_arrow_step = spec[3]
			s.min_value = -10.0
			s.max_value = 10.0
			s.allow_greater = true
			s.allow_lesser = true
			s.prefix = names[i]
			s.select_all_on_focus = true
			s.custom_minimum_size.x = 100
			s.set_value_no_signal(_component(value, i))
			s.value_changed.connect(_on_spin.bind(spec[1], spec[2], i))
			row.add_child(s)
			_spins.append([s, spec[1], spec[2], i])


func _on_spin(x: float, res: Resource, prop: String, i: int) -> void:
	res.set(prop, _with_component(res.get(prop), i, x))


static func _component(v: Variant, i: int) -> float:
	match typeof(v):
		TYPE_VECTOR2:
			return (v as Vector2)[i]
		TYPE_RECT2:
			var r := v as Rect2
			return [r.position.x, r.position.y, r.size.x, r.size.y][i]
	return float(v)


static func _with_component(v: Variant, i: int, x: float) -> Variant:
	match typeof(v):
		TYPE_VECTOR2:
			var p := v as Vector2
			p[i] = x
			return p
		TYPE_RECT2:
			var r := v as Rect2
			match i:
				0: r.position.x = x
				1: r.position.y = x
				2: r.size.x = x
				_: r.size.y = x
			return r
	return x


# --- Editing on screen ----------------------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey or not event.pressed:
		return
	if get_viewport().gui_get_focus_owner() is LineEdit:  # typing in a number box
		return
	var k := event as InputEventKey
	var step := STEP * (10.0 if k.shift_pressed else 1.0)
	var dirs := {KEY_LEFT: Vector2.LEFT, KEY_RIGHT: Vector2.RIGHT, KEY_UP: Vector2.UP, KEY_DOWN: Vector2.DOWN}
	if dirs.has(k.keycode):
		nudge(dirs[k.keycode] * step)
		get_viewport().set_input_as_handled()
	elif mode == Mode.DEAD and k.keycode in [KEY_BRACKETLEFT, KEY_BRACKETRIGHT, KEY_PAGEUP, KEY_PAGEDOWN]:
		var v := death_view()
		var big := 5.0 if k.shift_pressed else 1.0
		match k.keycode:
			KEY_BRACKETLEFT: _set_dead("roll", _dead("roll") - 0.5 * big)
			KEY_BRACKETRIGHT: _set_dead("roll", _dead("roll") + 0.5 * big)
			KEY_PAGEUP: v.eye_height += 0.02 * big
			KEY_PAGEDOWN: v.eye_height = maxf(0.05, v.eye_height - 0.02 * big)
		get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	var vp := get_viewport_rect().size
	var d := data()
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		get_viewport().gui_release_focus()  # clicking the screen leaves the number boxes, so arrows nudge again
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if not mb.pressed:
				_drag = ""
			elif mode == Mode.DEAD or mode == Mode.LEGS:
				_drag = "move"
			elif mode == Mode.MUZZLE:
				d.muzzle_uv = mb.position / vp
			elif mode == Mode.SIGHT and mb.position.distance_to(_window().end * vp) < HANDLE * 1.5:
				_drag = "resize"
			else:
				_drag = "move"
		elif mode == Mode.DEAD and mb.button_index == MOUSE_BUTTON_RIGHT:
			_drag = "pivot" if mb.pressed else ""
		elif mode == Mode.DEAD and mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_set_dead("scale", _dead("scale") * (1.02 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.02))
		elif mode == Mode.LEGS and legs_sprint and mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			body_view().run_scale *= 1.02 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.02
		elif mode == Mode.TABLET and mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			layout().hold_scale *= 1.02 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.02
		elif mode == Mode.SIGHT and mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var f := 1.03 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.03
			var r := _window()
			_set_window(Rect2(r.get_center() - r.size * f * 0.5, r.size * f))
		accept_event()
	elif event is InputEventMouseMotion and _drag != "":
		var rel := (event as InputEventMouseMotion).relative
		match mode:
			Mode.HIP:
				d.sprite_offset += rel / vp.y
			Mode.TABLET:
				layout().hold_offset += rel / vp.y
			Mode.LEGS:
				if legs_sprint:
					body_view().run_offset += rel / vp.y
			Mode.DEAD:
				if _drag == "pivot":
					_set_dead("pivot", _dead("pivot") + rel / vp)
				else:
					_set_dead("offset", _dead("offset") + rel / vp.y)
			Mode.SIGHT:
				if _drag == "resize":
					_set_window(Rect2(_window().position, (_window().size + rel / vp).max(Vector2(0.005, 0.005))))
				else:
					_set_window(Rect2(_window().position + rel / vp, _window().size))
		accept_event()


func _process(_delta: float) -> void:
	if not visible:
		return
	position = Vector2.ZERO
	size = get_viewport_rect().size  # anchors alone leave it 0x0 under a CanvasLayer, and then the screen gets no clicks
	var weapon_mode := mode in [Mode.HIP, Mode.SIGHT, Mode.MUZZLE]
	_next_button.visible = weapon_mode
	_canted_button.visible = mode == Mode.SIGHT
	_canted_button.text = "Canted: on" if player.weapons.current.using_canted() else "Canted: off"
	_prone_button.visible = mode == Mode.DEAD
	_prone_button.text = "Showing: " + DEATH_NAMES[dead_kind]
	_speed_button.visible = mode == Mode.LEGS
	_speed_button.text = "Preview: sprint" if legs_sprint else "Preview: walk"
	var res := _target()
	_context.text = ("%s  ·  %s" % [data().display_name, res.resource_path.get_file()]) if weapon_mode else res.resource_path.get_file()
	_help.text = HELP[mode]
	var key := "%d %s %s %s" % [mode, dead_kind, _window_prop(), res.resource_path]
	if key != _fields_key:
		_fields_key = key
		_rebuild_fields()
	for s: Array in _spins:  # follow on-screen edits, except in the box being typed into
		var box := s[0] as SpinBox
		if not box.get_line_edit().has_focus():
			box.set_value_no_signal(_component((s[1] as Resource).get(s[2]), s[3]))
	queue_redraw()


func _draw() -> void:
	var vp := get_viewport_rect().size
	var d := data()
	var c := vp * 0.5
	if mode == Mode.DEAD:
		var p: Vector2 = _dead("pivot") * vp
		draw_arc(p, 10.0, 0.0, TAU, 24, Color(1, 0.8, 0.2), 2.0)
		draw_line(p - Vector2(16, 0), p + Vector2(16, 0), Color(1, 0.8, 0.2), 1.0)
		draw_line(p - Vector2(0, 16), p + Vector2(0, 16), Color(1, 0.8, 0.2), 1.0)
		return
	if mode == Mode.LEGS:
		return
	if mode == Mode.HIP or mode == Mode.TABLET:
		draw_line(c - Vector2(12, 0), c + Vector2(12, 0), Color(1, 1, 1, 0.7), 1.0)
		draw_line(c - Vector2(0, 12), c + Vector2(0, 12), Color(1, 1, 1, 0.7), 1.0)
		return
	# Sight / muzzle: the frame fills the screen exactly, so screen position / size = frame UV.
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.12, 0.12, 0.14))
	var frame: Texture2D = d.idle_sprite
	if mode == Mode.SIGHT:
		var frames := player.weapons.current.aim_frames()
		frame = frames.back() if not frames.is_empty() else d.ads_sprite
	if frame == null:
		draw_string(ThemeDB.fallback_font, c, "This weapon has no frame for this mode", HORIZONTAL_ALIGNMENT_CENTER, -1, 20)
		return
	draw_texture_rect(frame, Rect2(Vector2.ZERO, vp), false)
	if mode == Mode.SIGHT:
		var r := Rect2(_window().position * vp, _window().size * vp)
		draw_rect(r, Color(0, 1, 0.4, 0.15))
		draw_rect(r, Color(0, 1, 0.4), false, 2.0)
		var rc := r.get_center()
		draw_line(rc - Vector2(8, 0), rc + Vector2(8, 0), Color(0, 1, 0.4), 1.0)
		draw_line(rc - Vector2(0, 8), rc + Vector2(0, 8), Color(0, 1, 0.4), 1.0)
		draw_rect(Rect2(r.end - Vector2(HANDLE, HANDLE) * 0.5, Vector2(HANDLE, HANDLE)), Color(0, 1, 0.4))
	else:
		var m := d.muzzle_uv * vp
		draw_circle(m, 6.0, Color(1, 0.3, 0.2))
		draw_arc(m, 14.0, 0.0, TAU, 24, Color(1, 0.3, 0.2), 2.0)
