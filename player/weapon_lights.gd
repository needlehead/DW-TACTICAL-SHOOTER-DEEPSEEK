class_name WeaponLights
extends Control
## Gun attachments (see WeaponData "Attachments"): laser sight, weapon flashlight and IR illuminator.
## Laser: a crisp dot in the world where the shots go (the same ray as hip fire, Player.aim_basis()) and a 2D beam
## from the emitter on the sprite to the dot, in any light; aimed at the sky the beam runs out toward the aim, no dot. IR mode (dot and beam) only shows through night vision.
## Flashlight: a shadowed spotlight from just below the eye, pointing where the gun points.
## IR illuminator: a wide flood light the same way; IR is invisible to the eye, so it only shines while the night
## vision is on.

const IR_COLOR := Color(0.9, 1.0, 0.9)  ## IR shows as bright white-green through the tubes
const DOT_SIZE := 0.015  ## dot quad size; fixed on screen, so this is a fraction of the view height
@export var beam_width := 3.0  ## pixels at the emitter (1080p); thins to a hair at the dot
@export var beam_strength := 0.6  ## beam alpha (any light)
@export var ir_energy := 3.0  ## IR illuminator
@export var ir_range := 45.0
@export var ir_angle := 32.0  ## wider than the flashlight: a flood, not a spot
@export var light_energy := 6.0
@export var light_range := 40.0
@export var light_angle := 24.0  ## spot half-angle, degrees
## Guns with a sprint pose point away while sprinting, and so do their light and laser: degrees (right, up).
@export var sprint_aside := Vector2(-45.0, -20.0)

var dot_visible := false
var _dot := MeshInstance3D.new()
var _light := SpotLight3D.new()
var _ir := SpotLight3D.new()
var _beam_from := Vector2.ZERO
var _beam_to := Vector2.ZERO
var _beam_alpha := 0.0
var _beam_color := Color.WHITE

@onready var player: Player = owner
@onready var sprite: TextureRect = $"../SpriteViewmodel"
@onready var shade: SpriteShadow = $"../SpriteShadow"
@onready var nv: NightVision = $"../NightVision"


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://player/unshaded_add.gdshader")  # the beam is light: additive, never shaded
	material = mat

	var g := Gradient.new()  # solid core, short soft edge: a crisp dot, no halo
	g.offsets = PackedFloat32Array([0.0, 0.45, 0.7])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
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
	_light.top_level = true
	_light.shadow_enabled = true
	_light.light_color = Color(1.0, 0.96, 0.88)
	_light.spot_angle_attenuation = 1.6
	_ir.top_level = true
	_ir.shadow_enabled = true
	_ir.spot_angle_attenuation = 1.2
	for n: Node3D in [_dot, _light, _ir]:
		n.visible = false
		player.add_child.call_deferred(n)


func _process(_delta: float) -> void:
	var w := player.weapons.current
	var d := w.data
	var shown := player.alive and sprite.visible
	var cam := player.camera
	var aim := player.aim_basis()
	if d.sprint_sprite:
		var s := player.sprint_blend
		aim = Basis(cam.global_basis.y, deg_to_rad(-sprint_aside.x) * s) * aim * Basis(Vector3.RIGHT, deg_to_rad(sprint_aside.y) * s)

	_light.visible = shown and d.flashlight and w.light_on
	if _light.visible:
		_light.light_energy = light_energy
		_light.spot_range = light_range
		_light.spot_angle = light_angle
		# Just below and right of the eye: close enough to read as the gun's light, far enough to cast visible shadows.
		_light.global_transform = Transform3D(aim, cam.global_position + cam.global_basis * Vector3(0.12, -0.15, 0.0))
	_ir.visible = shown and d.ir_illuminator and w.ir_on and nv.on
	if _ir.visible:
		_ir.light_energy = ir_energy
		_ir.spot_range = ir_range
		_ir.spot_angle = ir_angle
		_ir.global_transform = Transform3D(aim, cam.global_position + cam.global_basis * Vector3(0.1, -0.12, 0.0))

	var ir := w.laser_mode == 2
	# Off while the gun is lowered for sprinting; an IR laser only shows through night vision.
	var lasing := shown and d.laser and w.laser_mode > 0 and (not ir or nv.on) and player.sprint_blend < 0.5
	var laser_color := IR_COLOR if ir else d.laser_color
	dot_visible = false
	_beam_alpha = 0.0
	if lasing:
		var from := cam.global_position
		var q := PhysicsRayQueryParameters3D.create(from, from - aim.z * 300.0, Ballistics.WORLD | Ballistics.HITBOX,
			[player.get_rid()] + player.hitbox_rids())
		q.collide_with_areas = true
		var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
		# Nothing hit (sky, open distance): no dot, but the beam still runs out toward the aim.
		dot_visible = not hit.is_empty()
		var p: Vector3 = (hit.position + hit.normal * 0.01) if dot_visible else from - aim.z * 300.0
		if dot_visible:
			_dot.global_position = p
			(_dot.mesh.surface_get_material(0) as StandardMaterial3D).albedo_color = laser_color
		# Beam only from the hip frames (the emitter's place on the aimed frames isn't known).
		var hip := sprite.texture == d.idle_sprite or sprite.texture == d.shoot_sprite
		if hip and not cam.is_position_behind(p):
			_beam_from = sprite.get_global_transform() * (d.laser_uv * sprite.size)
			_beam_to = cam.unproject_position(p)
			_beam_alpha = 1.0 if nv.on else beam_strength
			_beam_color = laser_color
	_dot.visible = dot_visible
	visible = _beam_alpha > 0.01
	if visible:
		(material as ShaderMaterial).set_shader_parameter("undo_tint", shade.undo_tint())
		queue_redraw()


func _draw() -> void:
	var c := _beam_color
	var dir := (_beam_to - _beam_from).normalized()
	var side := Vector2(-dir.y, dir.x) * beam_width * 0.5 * get_viewport_rect().size.y / 1080.0
	draw_polygon(PackedVector2Array([_beam_from + side, _beam_to, _beam_from - side]),
		PackedColorArray([Color(c, _beam_alpha), Color(c, _beam_alpha * 0.15), Color(c, _beam_alpha)]))
