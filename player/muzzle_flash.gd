extends Control
## Muzzle flash for unsuppressed sprite guns: a quick additive burst (hot core, soft glow, a few random spikes)
## drawn in front of the weapon sprite at its muzzle_uv. Each shot gets a new size and spin. Hip only: the aimed
## frames don't say where the muzzle is (the 3D muzzle light still flashes the world when aimed).

@export var lifetime := 0.05
@export var size_range := Vector2(0.07, 0.11)  ## flash radius range, fraction of screen height
@export var color := Color(1.0, 0.75, 0.35)
@export var spikes := 5

var _t := 99.0
var _radius := 0.0
var _spin := 0.0
var _lengths := PackedFloat32Array()
var _glow: Texture2D

@onready var player: Player = owner
@onready var sprite: TextureRect = $"../SpriteViewmodel"


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://player/unshaded_add.gdshader")  # light: additive and never shaded
	material = mat
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	_glow = tex
	for w in (owner.get_node("LeanPivot/Head/Camera3D/Viewmodel/Weapons") as WeaponManager).weapons:
		w.fired.connect(_on_fired.bind(w))


func _on_fired(w: Weapon) -> void:
	if w.data.suppressed or not sprite.visible or not _at_hip(w):
		return
	_t = 0.0
	z_index = -1 if w.data.muzzle_behind else 0  # -1: under the gun sprite, so the gun hides the flash
	_radius = randf_range(size_range.x, size_range.y)
	_spin = randf() * TAU
	_lengths.resize(spikes)
	for i in spikes:
		_lengths[i] = randf_range(0.6, 1.0)


## The muzzle position is only known on the hip frames (idle / shoot).
func _at_hip(w: Weapon) -> bool:
	return sprite.texture == w.data.idle_sprite or sprite.texture == w.data.shoot_sprite


func _process(delta: float) -> void:
	_t += delta
	visible = _t < lifetime
	if visible:
		(material as ShaderMaterial).set_shader_parameter("undo_tint", (owner.get_node("ViewmodelLayer/SpriteShadow") as SpriteShadow).undo_tint())
		queue_redraw()


func _draw() -> void:
	if _lengths.is_empty():  # nothing fired yet
		return
	var w := player.weapons.current
	var c := sprite.get_global_transform() * (w.data.muzzle_uv * sprite.size)
	var fade := 1.0 - _t / lifetime
	var r := _radius * get_viewport_rect().size.y * (0.8 + 0.4 * fade)
	draw_texture_rect(_glow, Rect2(c - Vector2.ONE * r * 1.6, Vector2.ONE * r * 3.2), false, Color(color, 0.6 * fade))
	for i in spikes:
		var a := _spin + TAU * i / spikes
		var tip := c + Vector2.from_angle(a) * r * _lengths[i]
		var side := Vector2.from_angle(a + PI * 0.5) * r * 0.12
		draw_colored_polygon(PackedVector2Array([c + side, tip, c - side]), Color(color, fade))
	draw_circle(c, r * 0.22, Color(1, 0.95, 0.85, fade))
