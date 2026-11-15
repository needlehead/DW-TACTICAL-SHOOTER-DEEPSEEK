class_name Impact
## Impact visuals: capped bullet-hole decals, a dust burst tinted to the surface colour, flying debris,
## and blood puffs for hitboxes. Meshes/materials are built once and shared.

const MAX_DECALS := 150

static var _decals: Array[Decal] = []
static var _hole_tex: Texture2D
static var _dust_mesh: QuadMesh
static var _chunk_mesh: BoxMesh
static var _dust_ramp: Gradient
static var _dust_scale: Curve


## Bullet hitting a world surface.
static func bullet_hole(pos: Vector3, normal: Vector3, collider: Object) -> void:
	var parent := collider as Node3D  # parent to the hit object so holes ride along on doors
	if parent == null:
		return
	_init_shared()
	var d := Decal.new()
	d.texture_albedo = _hole_tex
	d.size = Vector3(0.11, 0.12, 0.11) * randf_range(0.85, 1.15)
	d.cull_mask = 1
	parent.add_child(d)
	# Decals project along their -Y, so align +Y with the surface normal; random spin hides repetition.
	var b := Basis(Vector3.RIGHT, PI) if normal.dot(Vector3.UP) < -0.999 else Basis(Quaternion(Vector3.UP, normal))
	d.global_transform = Transform3D(b.rotated(normal, randf() * TAU), pos)
	_decals.append(d)
	if _decals.size() > MAX_DECALS:
		var old: Decal = _decals.pop_front()
		if is_instance_valid(old):
			old.queue_free()

	var surface := _surface_color(collider)
	dust(pos, normal, surface.darkened(0.2))
	puff(pos, normal, surface.darkened(0.35), 10, 4.5)


## Soft billboard dust cloud that bursts off the surface, swells and fades.
static func dust(pos: Vector3, normal: Vector3, color: Color, amount := 7) -> void:
	var root := _root()
	if root == null:
		return
	_init_shared()
	var p := CPUParticles3D.new()
	p.mesh = _dust_mesh
	p.one_shot = true
	p.amount = amount
	p.lifetime = 0.9
	p.explosiveness = 0.95
	p.direction = normal
	p.spread = 28.0
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 2.2
	p.damping_min = 2.5
	p.damping_max = 4.0
	p.gravity = Vector3(0, -0.4, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	p.scale_amount_curve = _dust_scale
	p.color = color
	p.color_ramp = _dust_ramp
	p.angle_min = 0.0
	p.angle_max = 360.0
	_spawn(root, p, pos)


## Small solid chunks (debris on walls, blood on hitboxes).
static func puff(pos: Vector3, normal: Vector3, color: Color, amount := 8, speed := 3.0) -> void:
	var root := _root()
	if root == null:
		return
	_init_shared()
	var p := CPUParticles3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	p.mesh = _chunk_mesh
	p.material_override = mat
	p.one_shot = true
	p.amount = amount
	p.lifetime = 0.6
	p.explosiveness = 1.0
	p.direction = normal
	p.spread = 40.0
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -9.8, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.3
	p.angular_velocity_min = -720.0
	p.angular_velocity_max = 720.0
	_spawn(root, p, pos)


static func _spawn(root: Node, p: CPUParticles3D, pos: Vector3) -> void:
	root.add_child(p)
	p.global_position = pos
	p.emitting = true
	p.finished.connect(p.queue_free)


## Albedo of the hit object's material (CSG greybox and meshes), so dust matches the wall.
static func _surface_color(collider: Object) -> Color:
	var mat: Variant = collider.get("material")
	if mat == null:
		mat = collider.get("material_override")
	return (mat as BaseMaterial3D).albedo_color if mat is BaseMaterial3D else Color(0.6, 0.58, 0.54)


static func _root() -> Node:
	return (Engine.get_main_loop() as SceneTree).current_scene


static func _init_shared() -> void:
	if _hole_tex:
		return
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.35, 0.6, 1.0])
	g.colors = PackedColorArray([Color(0.02, 0.02, 0.02, 1), Color(0.08, 0.07, 0.06, 1), Color(0.25, 0.23, 0.2, 0.6), Color(0, 0, 0, 0)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	_hole_tex = tex

	var soft := Gradient.new()
	soft.set_color(0, Color(1, 1, 1, 1))
	soft.set_color(1, Color(1, 1, 1, 0))
	var soft_tex := GradientTexture2D.new()
	soft_tex.gradient = soft
	soft_tex.fill = GradientTexture2D.FILL_RADIAL
	soft_tex.fill_from = Vector2(0.5, 0.5)
	soft_tex.fill_to = Vector2(1.0, 0.5)
	var dust_mat := StandardMaterial3D.new()
	dust_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dust_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	dust_mat.vertex_color_use_as_albedo = true
	dust_mat.albedo_texture = soft_tex
	dust_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_dust_mesh = QuadMesh.new()
	_dust_mesh.size = Vector2(0.3, 0.3)
	_dust_mesh.material = dust_mat

	_chunk_mesh = BoxMesh.new()
	_chunk_mesh.size = Vector3.ONE * 0.022

	_dust_ramp = Gradient.new()
	_dust_ramp.set_color(0, Color(1, 1, 1, 0.75))
	_dust_ramp.set_color(1, Color(1, 1, 1, 0))
	_dust_scale = Curve.new()
	_dust_scale.max_value = 2.0
	_dust_scale.add_point(Vector2(0, 0.35))
	_dust_scale.add_point(Vector2(1, 1.6))
