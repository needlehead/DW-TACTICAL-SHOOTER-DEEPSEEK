extends Control
## Minimal HUD: aim-point dot (shows freeaim), hit marker, damage-direction arcs, toasts,
## weapon/fire mode, and an exact ammo readout only when toggled (F2) for debugging.

@export var show_aim_dot := true
@export var hit_marker_time := 0.25
@export var damage_indicator_time := 1.5

var show_ammo := false

var _hit_t := 0.0
var _hit_kill := false
var _damage_sources: Array[Dictionary] = []  # {pos: Vector3, t: float}
var _toast_t := 0.0
var _info: Label
var _toast: Label
var _center: Label

@onready var player: Player = owner
@onready var bodycam: Bodycam = owner.get_node("PostFXLayer/Bodycam")


func _ready() -> void:
	_info = Label.new()
	_toast = Label.new()
	_center = Label.new()
	for l: Label in [_info, _toast, _center]:
		l.add_theme_font_size_override("font_size", 18)
		l.add_theme_color_override("font_shadow_color", Color.BLACK)
		add_child(l)
	_info.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 24)
	_info.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_info.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 120)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_center.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_center.add_theme_font_size_override("font_size", 32)
	Game.hit_confirmed.connect(_on_hit_confirmed)
	Game.toast_requested.connect(_on_toast)
	(owner.get_node("Health") as Health).damaged.connect(_on_player_damaged)  # player @onready vars are not set yet


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_ammo"):
		show_ammo = not show_ammo


func _on_hit_confirmed(_zone: StringName, _damage: float, killed: bool) -> void:
	_hit_t = hit_marker_time
	_hit_kill = killed


func _on_toast(text: String) -> void:
	_toast.text = text
	_toast_t = 1.5


func _on_player_damaged(_amount: float, _zone: StringName, source: Node) -> void:
	if source is Node3D:
		_damage_sources.append({"pos": (source as Node3D).global_position, "t": damage_indicator_time})


func _process(delta: float) -> void:
	_hit_t -= delta
	_toast_t -= delta
	_toast.visible = _toast_t > 0.0
	for i in range(_damage_sources.size() - 1, -1, -1):
		_damage_sources[i].t -= delta
		if _damage_sources[i].t <= 0.0:
			_damage_sources.remove_at(i)

	var w := player.weapons.current
	var text := "%s  |  %s" % [w.data.display_name, WeaponData.mode_name(w.mode)]
	if show_ammo:
		text += "\n%d%s  |  spares %s" % [w.mag, " +1" if w.chambered else "", str(w.spare)]
	text += "\nFrags %d   HP %d" % [player.weapons.grenades, ceili(player.health.current)]
	_info.text = text
	_center.text = "" if player.alive else "DEAD - press F5"
	queue_redraw()


func _draw() -> void:
	var cam := player.camera
	var aim := cam.global_position - player.aim_basis().z * 50.0
	var c := size * 0.5
	if not cam.is_position_behind(aim):
		c = bodycam.to_screen(cam.unproject_position(aim))
	var through_holo := player.ads_blend > 0.8 and player.weapons.current.data.reticle_size > 0.0
	if show_aim_dot and player.alive and not through_holo:
		draw_circle(c, 2.0, Color(1, 1, 1, 0.6))
	if _hit_t > 0.0:
		var col := Color(1, 0.2, 0.2) if _hit_kill else Color.WHITE
		col.a = _hit_t / hit_marker_time
		for s: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			draw_line(c + s * 6.0, c + s * 14.0, col, 2.0, true)
	for d in _damage_sources:
		# Angle 0 = straight ahead (top of screen), positive = to the right.
		var local: Vector3 = player.global_basis.inverse() * ((d.pos as Vector3) - player.global_position)
		var a := atan2(local.x, -local.z) - PI * 0.5
		draw_arc(size * 0.5, 140.0, a - 0.3, a + 0.3, 16, Color(1, 0.1, 0.1, float(d.t) / damage_indicator_time), 6.0, true)
