class_name EggDeath
extends CanvasLayer
## Easter-egg death (the EASTER EGG test pad): Ingrid walks up to the body, grabs an ankle and drags it feet first
## along the ground in tugs, then flings it onto a heap of other Keis, talking the whole time in game subtitles.
## The Player calls update() every frame of this death; it moves the body and the camera and picks the BodySprite
## frame (egg_sprites: walk up, grab, drag, thrown, landed; the heap shows behind the landed one).
## In the F4 preview only the camera plays (the living player isn't moved).

## [start second, line] - Ingrid's subtitles; each shows until the next (or for `line_time`).
@export var lines: Array = [
	[0.6, "Oh! Another one dead..."],
	[2.7, "Don't worry, we have lots of you for testing."],
	[5.0, "Hup... heavier than the last one."],
	[7.3, "Into the pile you go!"],
]
@export var line_time := 3.0
@export var speaker := "Ingrid"
@export var speaker_color := Color(0.95, 0.66, 0.25)
@export var walk_up_until := 2.6  ## frame 1: she walks up
@export var grab_until := 3.6  ## frame 2: grabs the ankle; then the drag
@export var drag_until := 7.2
@export var throw_until := 8.1  ## frame 4 in the air; then the landed frame on the heap
@export var drag_speed := 0.9  ## m/s on average; it comes in tugs
@export var tug_time := 0.55  ## seconds per tug (the frame swaps with each)
@export var drag_bob := 0.04  ## metres the head bumps up with each tug
@export var throw_distance := 2.2
@export var throw_height := 1.1
@export var throw_spin := 360.0  ## degrees the view flips over in the air

var t := -1.0  ## seconds into the sequence; -1 when not playing
var _player: Player
var _dir := Vector3.FORWARD
var _preview := false
var lift := 0.0  ## metres the camera rises above the death view right now (drag bumps, the throw arc)
var _panel := PanelContainer.new()
var _name := Label.new()
var _text := Label.new()
var _font := preload("res://fonts/Barlow-Medium.ttf")


func _init(p: Player) -> void:
	_player = p


func _ready() -> void:
	layer = 4  # over the HUD
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.55)
	bg.set_corner_radius_all(4)
	bg.content_margin_left = 18
	bg.content_margin_right = 18
	bg.content_margin_top = 8
	bg.content_margin_bottom = 8
	_panel.add_theme_stylebox_override("panel", bg)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_panel.add_child(row)
	for l: Label in [_name, _text]:
		l.add_theme_font_override("font", _font)
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		l.add_theme_constant_override("outline_size", 4)
		row.add_child(l)
	_name.text = speaker + ":"
	_name.add_theme_color_override("font_color", speaker_color)
	_text.add_theme_color_override("font_color", Color(1, 1, 1))
	_panel.modulate.a = 0.0
	add_child(_panel)


func playing() -> bool:
	return t >= 0.0


## BodySprite frame index into egg_sprites.
func frame() -> int:
	if t < walk_up_until:
		return 0
	if t < grab_until:
		return 1
	if t < drag_until:
		return 2 if fmod(t - grab_until, tug_time) < tug_time * 0.5 else 1  # pull / reach again
	return 3 if t < throw_until else 4


## Still running: the last subtitle hasn't finished (the HUD holds its death text until then).
func busy() -> bool:
	return playing() and t < float(lines[-1][0]) + line_time


func landed() -> bool:
	return t >= throw_until


## One frame of the sequence: moves the body (not in the preview) and sets the camera height, pitch and roll on top
## of the death camera.
func update(delta: float) -> void:
	if t < 0.0:
		_start()
	t += delta
	var step := 0.0
	var add := 0.0
	if t >= grab_until and t < drag_until:
		var p := fmod(t - grab_until, tug_time) / tug_time
		step = drag_speed * 2.0 * pow(sin(p * PI), 2.0) * delta  # surges, averaging drag_speed
		add = drag_bob * sin(p * PI)
		_player.head.rotation.z += deg_to_rad(1.5 * sin(p * TAU))
	elif t >= drag_until and t < throw_until:
		var u := (t - drag_until) / (throw_until - drag_until)
		step = throw_distance / (throw_until - drag_until) * delta
		add = throw_height * 4.0 * u * (1.0 - u)
		_player.head.rotation.x += deg_to_rad(throw_spin * (1.0 - pow(1.0 - u, 2.0)))
	lift = add
	if step > 0.0 and not _preview and not _wall_ahead(step):
		_player.global_position += _dir * step
	_subtitle()


## A wall (not the floor she slides on) within this step, checked at body height: the drag stops there.
func _wall_ahead(step: float) -> bool:
	var from := _player.global_position + Vector3.UP * 0.3
	var q := PhysicsRayQueryParameters3D.create(from, from + _dir * (step + 0.35), Ballistics.WORLD, [_player.get_rid()])
	return not _player.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func stop() -> void:
	lift = 0.0
	t = -1.0
	_panel.modulate.a = 0.0


func _start() -> void:
	t = 0.0
	_preview = _player.alive
	# Dragged the way the pad faces (open ground), else the way she was facing; the view looks down the body at her.
	var src := _player.last_damage_source() as Node3D
	var d := -(src.global_basis.z if src else _player.global_basis.z)
	d.y = 0.0
	_dir = d.normalized() if d.length() > 0.01 else Vector3.FORWARD
	if not _preview:  # the F4 preview keeps her look
		_player.look_yaw = rad_to_deg(atan2(-_dir.x, -_dir.z))


func _subtitle() -> void:
	var shown := ""
	var alpha := 0.0
	for i in lines.size():
		var start: float = lines[i][0]
		var stop_at: float = minf(lines[i + 1][0] if i + 1 < lines.size() else INF, start + line_time)
		if t >= start and t < stop_at:
			shown = lines[i][1]
			alpha = clampf(minf((t - start) / 0.15, (stop_at - t) / 0.25), 0.0, 1.0)
	if not shown.is_empty():
		_text.text = shown
	_panel.modulate.a = alpha
	var vp := get_viewport().get_visible_rect().size
	var px := int(30.0 * vp.y / 1080.0)
	_name.add_theme_font_size_override("font_size", px)
	_text.add_theme_font_size_override("font_size", px)
	_panel.reset_size()
	_panel.position = Vector2((vp.x - _panel.size.x) * 0.5, vp.y * 0.86 - _panel.size.y * 0.5)
