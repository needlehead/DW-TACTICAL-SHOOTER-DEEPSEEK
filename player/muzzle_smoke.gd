extends Control
## Suppressor smoke for sprite weapons: soft screen-space wisps that puff out of the muzzle on each
## shot, drift up and sideways, swell and fade. Drawn over the weapon sprite.

@export var puffs_per_shot := 2
@export var lifetime := 0.9
@export var start_size := 0.025  ## fraction of screen height
@export var end_size := 0.11
@export var rise_speed := 0.06  ## screen heights per second
@export var spread_speed := 0.05
@export var opacity := 0.35
@export var color := Color(0.85, 0.85, 0.82)
@export var look_drag := 1.0  ## 1 = smoke stays put in the world while you turn; 0 = glued to the screen

var _puffs: Array[Dictionary] = []  # {pos: Vector2, vel: Vector2, age: float, spin: float}
var _tex: Texture2D
var _last_look := Vector2.ZERO

@onready var player: Player = owner
@onready var sprite: TextureRect = $"../SpriteViewmodel"


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	_tex = tex
	var manager := owner.get_node("LeanPivot/Head/Camera3D/Viewmodel/Weapons") as WeaponManager
	for w in manager.weapons:
		w.fired.connect(_on_fired.bind(w))


func _on_fired(w: Weapon) -> void:
	if not w.data.suppressed or not sprite.visible:
		return
	# Muzzle point on the frame, through the sprite's current offset/scale/rotation.
	var muzzle := sprite.get_global_transform() * (w.data.muzzle_uv * sprite.size)
	var k := get_viewport_rect().size.y
	for i in puffs_per_shot:
		_puffs.append({
			"pos": muzzle,
			"vel": Vector2(randf_range(-1.0, 0.4) * spread_speed, -randf_range(0.5, 1.0) * rise_speed) * k,
			"age": randf_range(0.0, 0.1),
			"spin": randf_range(-1.0, 1.0),
		})


func _process(delta: float) -> void:
	var k := get_viewport_rect().size.y
	# Turning the view slides the world (and the smoke hanging in it) across the screen.
	var look := Vector2(player.look_yaw + player.recoil.x, player.look_pitch + player.recoil.y)
	var drag := (look - _last_look) * k / player.camera.fov * look_drag
	_last_look = look
	for i in range(_puffs.size() - 1, -1, -1):
		var p := _puffs[i]
		p.age += delta
		if p.age >= lifetime:
			_puffs.remove_at(i)
			continue
		p.vel *= 1.0 - minf(1.0, 1.5 * delta)  # air drag
		p.pos += p.vel * delta + drag
	queue_redraw()


func _draw() -> void:
	var k := get_viewport_rect().size.y
	for p in _puffs:
		var t: float = p.age / lifetime
		var s := lerpf(start_size, end_size, sqrt(t)) * k
		var c := color
		c.a = opacity * (1.0 - t) * minf(1.0, t * 8.0)
		draw_set_transform(p.pos, float(p.spin) * t, Vector2.ONE)
		draw_texture_rect(_tex, Rect2(-s * 0.5, -s * 0.5, s, s), false, c)
	draw_set_transform(Vector2.ZERO)
