class_name WeaponLights
extends Control
## Gun attachments (see WeaponData "Attachments"): a laser sight and a weapon flashlight.
## Laser: a dot in the world where the shots go (the same ray as hip fire, Player.aim_basis()), with a tiny glow
## on the surface, and a 2D beam from the emitter on the sprite to the dot. Like a real laser the beam only
## shows in low light: its strength follows how dark SpriteShadow has made the hands.
## Flashlight: a shadowed spotlight from just below the eye, pointing where the gun points.

const DOT_SIZE := 0.015  ## dot quad size; fixed on screen, so this is a fraction of the view height
@export var beam_width := 3.0  ## pixels at the emitter (1080p); thins to a hair at the dot
@export var beam_strength := 0.7  ## beam alpha in full darkness
@export var light_energy := 6.0
@export var light_range := 40.0
@export var light_angle := 24.0  ## spot half-angle, degrees

var dot_visible := false
var _dot := MeshInstance3D.new()
var _dot_glow := OmniLight3D.new()
var _light := SpotLight3D.new()
var _beam_from := Vector2.ZERO
var _beam_to := Vector2.ZERO
var _beam_alpha := 0.0

@onready var player: Player = owner
@onready var sprite: TextureRect = $"../SpriteViewmodel"
@onready var shade: SpriteShadow = $"../SpriteShadow"


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://player/unshaded_add.gdshader")  # the beam is light: additive, never shaded
	material = mat

	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	dm.fixed_size = true  # same size on screen at any distance, like a real dot
	dm.albedo_texture = tex
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * DOT_SIZE
	quad.material = dm
	_dot.mesh = quad
	_dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_dot.top_level = true
	_dot_glow.omni_range = 0.3
	_dot_glow.light_energy = 0.35
	_dot_glow.top_level = true
	_light.top_level = true
	_light.shadow_enabled = true
	_light.light_color = Color(1.0, 0.96, 0.88)
	_light.spot_angle_attenuation = 1.6
	for n: Node3D in [_dot, _dot_glow, _light]:
		n.visible = false
		player.add_child.call_deferred(n)


func _process(_delta: float) -> void:
	var w := player.weapons.current
	var d := w.data
	var shown := player.alive and sprite.visible
	var cam := player.camera
	var aim := player.aim_basis()

	_light.visible = shown and d.flashlight and w.light_on
	if _light.visible:
		_light.light_energy = light_energy
		_light.spot_range = light_range
		_light.spot_angle = light_angle
		# Just below and right of the eye: close enough to read as the gun's light, far enough to cast visible shadows.
		_light.global_transform = Transform3D(aim, cam.global_position + cam.global_basis * Vector3(0.12, -0.15, 0.0))

	dot_visible = shown and d.laser and w.laser_on
	_beam_alpha = 0.0
	if dot_visible:
		var from := cam.global_position
		var q := PhysicsRayQueryParameters3D.create(from, from - aim.z * 300.0, Ballistics.WORLD | Ballistics.HITBOX,
			[player.get_rid()] + player.hitbox_rids())
		q.collide_with_areas = true
		var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
		dot_visible = not hit.is_empty()
		if dot_visible:
			var p: Vector3 = hit.position + hit.normal * 0.01
			_dot.global_position = p
			_dot_glow.global_position = hit.position + hit.normal * 0.08
			_dot_glow.light_color = d.laser_color
			(_dot.mesh.surface_get_material(0) as StandardMaterial3D).albedo_color = d.laser_color
			# Beam only from the hip frames (the emitter's place on the aimed frames isn't known) and only in the dark.
			var hip := sprite.texture == d.idle_sprite or sprite.texture == d.shoot_sprite
			if hip and not cam.is_position_behind(p):
				_beam_from = sprite.get_global_transform() * (d.laser_uv * sprite.size)
				_beam_to = cam.unproject_position(p)
				_beam_alpha = beam_strength * darkness()
	_dot.visible = dot_visible
	_dot_glow.visible = dot_visible
	visible = _beam_alpha > 0.01
	if visible:
		(material as ShaderMaterial).set_shader_parameter("undo_tint", shade.undo_tint())
		queue_redraw()


## 0 in sunlight .. 1 pitch dark, read from how much SpriteShadow is darkening the hands.
func darkness() -> float:
	return clampf(1.0 - shade.color.get_luminance(), 0.0, 1.0)


func _draw() -> void:
	var c: Color = player.weapons.current.data.laser_color
	var dir := (_beam_to - _beam_from).normalized()
	var side := Vector2(-dir.y, dir.x) * beam_width * 0.5 * get_viewport_rect().size.y / 1080.0
	draw_polygon(PackedVector2Array([_beam_from + side, _beam_to, _beam_from - side]),
		PackedColorArray([Color(c, _beam_alpha), Color(c, _beam_alpha * 0.15), Color(c, _beam_alpha)]))
