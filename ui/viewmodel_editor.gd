class_name ViewmodelEditor
extends Control
## In-game viewmodel alignment editor (F4). Frees the mouse and edits the current weapon's sprite placement:
##   Hip    - drag the gun (or arrow keys) to set sprite_offset; changes show live.
##   Sight  - the last aim frame fills the screen; drag the box over the sight glass / lens to set sight_window
##            (drag the corner handle or mouse wheel to resize, arrows nudge, Shift = bigger steps).
##   Muzzle - the idle frame fills the screen; click the barrel end to set muzzle_uv (suppressor smoke origin).
## Save writes the weapon's .tres; Revert restores what it had when the editor opened.

enum Mode { HIP, SIGHT, MUZZLE }

const STEP := 0.001  ## arrow-key nudge (fraction of screen); Shift x10
const HANDLE := 14.0  ## corner handle size in pixels

var mode := Mode.HIP
var _drag := ""  # "", "move" or "resize"
var _originals := {}  # WeaponData -> {property: value}
var _info: Label
var _mode_buttons: Array[Button] = []

@onready var player: Player = owner


func _ready() -> void:
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var panel := PanelContainer.new()
	panel.position = Vector2(16, 16)
	add_child(panel)
	var col := VBoxContainer.new()
	panel.add_child(col)
	var bar := HBoxContainer.new()
	col.add_child(bar)
	for m: int in [Mode.HIP, Mode.SIGHT, Mode.MUZZLE]:
		var b := _button(bar, ["Hip", "Sight", "Muzzle"][m], set_mode.bind(m))
		b.toggle_mode = true
		_mode_buttons.append(b)
	_button(bar, "Next weapon", _next_weapon)
	_button(bar, "Save", save)
	_button(bar, "Revert", revert)
	_button(bar, "Close (F4)", toggle)
	_info = Label.new()
	col.add_child(_info)
	set_mode(Mode.HIP)


func _button(parent: Node, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE  # keep arrow keys for nudging
	b.pressed.connect(action)
	parent.add_child(b)
	return b


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("viewmodel_editor"):
		toggle()


func toggle() -> void:
	visible = not visible
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if visible else Input.MOUSE_MODE_CAPTURED
	if visible:
		_remember(data())


func data() -> WeaponData:
	return player.weapons.current.data


func set_mode(m: int) -> void:
	mode = m
	for i in _mode_buttons.size():
		_mode_buttons[i].button_pressed = i == m


## Arrow-key nudge (dir in screen fractions); also the entry point tests use.
func nudge(dir: Vector2) -> void:
	var d := data()
	match mode:
		Mode.HIP:
			d.sprite_offset += dir
		Mode.SIGHT:
			d.sight_window.position += dir
		Mode.MUZZLE:
			d.muzzle_uv += dir


func save() -> void:
	var d := data()
	var err := ResourceSaver.save(d)
	Game.toast(("Saved " + d.resource_path.get_file()) if err == OK else "Save failed (%s)" % error_string(err))
	if err == OK:
		_originals.erase(d)
		_remember(d)


func revert() -> void:
	var d := data()
	for p: String in _originals.get(d, {}):
		d.set(p, _originals[d][p])


func _remember(d: WeaponData) -> void:
	if not _originals.has(d):
		_originals[d] = {"sprite_offset": d.sprite_offset, "sight_window": d.sight_window, "muzzle_uv": d.muzzle_uv}


func _next_weapon() -> void:
	var m := player.weapons
	var next := (m.weapons.find(m.current) + 1) % m.weapons.size()
	_remember(m.weapons[next].data)
	m.select(next)


func _input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey or not event.pressed:
		return
	var k := event as InputEventKey
	var step := STEP * (10.0 if k.shift_pressed else 1.0)
	var dirs := {KEY_LEFT: Vector2.LEFT, KEY_RIGHT: Vector2.RIGHT, KEY_UP: Vector2.UP, KEY_DOWN: Vector2.DOWN}
	if dirs.has(k.keycode):
		nudge(dirs[k.keycode] * step)
		get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	var vp := get_viewport_rect().size
	var d := data()
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if not mb.pressed:
				_drag = ""
			elif mode == Mode.MUZZLE:
				d.muzzle_uv = mb.position / vp
			elif mode == Mode.SIGHT and mb.position.distance_to((d.sight_window.end) * vp) < HANDLE * 1.5:
				_drag = "resize"
			else:
				_drag = "move"
		elif mode == Mode.SIGHT and mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var f := 1.03 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.03
			var c := d.sight_window.get_center()
			d.sight_window.size *= f
			d.sight_window.position = c - d.sight_window.size * 0.5
		accept_event()
	elif event is InputEventMouseMotion and _drag != "":
		var rel := (event as InputEventMouseMotion).relative
		match mode:
			Mode.HIP:
				d.sprite_offset += rel / vp.y
			Mode.SIGHT:
				if _drag == "resize":
					d.sight_window.size = (d.sight_window.size + rel / vp).max(Vector2(0.005, 0.005))
				else:
					d.sight_window.position += rel / vp
		accept_event()


func _process(_delta: float) -> void:
	if not visible:
		return
	var d := data()
	_info.text = "%s  (%s)\nsprite_offset = %s\nsight_window = %s\nmuzzle_uv = %s\nDrag to move. Arrows nudge, Shift = x10.%s" % [
		d.display_name, d.resource_path.get_file(), d.sprite_offset, d.sight_window, d.muzzle_uv,
		"  Corner handle / wheel resizes." if mode == Mode.SIGHT else ""]
	queue_redraw()


func _draw() -> void:
	var vp := get_viewport_rect().size
	var d := data()
	var c := vp * 0.5
	if mode == Mode.HIP:
		draw_line(c - Vector2(12, 0), c + Vector2(12, 0), Color(1, 1, 1, 0.7), 1.0)
		draw_line(c - Vector2(0, 12), c + Vector2(0, 12), Color(1, 1, 1, 0.7), 1.0)
		return
	# Sight / muzzle: the frame fills the screen exactly, so screen position / size = frame UV.
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.12, 0.12, 0.14))
	var frame: Texture2D = d.idle_sprite
	if mode == Mode.SIGHT:
		frame = d.aim_sprites.back() if not d.aim_sprites.is_empty() else d.ads_sprite
	if frame == null:
		draw_string(ThemeDB.fallback_font, c, "This weapon has no frame for this mode", HORIZONTAL_ALIGNMENT_CENTER, -1, 20)
		return
	draw_texture_rect(frame, Rect2(Vector2.ZERO, vp), false)
	if mode == Mode.SIGHT:
		var r := Rect2(d.sight_window.position * vp, d.sight_window.size * vp)
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
