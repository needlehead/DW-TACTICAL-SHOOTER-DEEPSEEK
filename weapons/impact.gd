class_name Impact
## Impact visuals: capped bullet-hole decals and one-shot particle puffs.

const MAX_DECALS := 150

static var _decals: Array[Decal] = []
static var _hole_tex: Texture2D


static func bullet_hole(pos: Vector3, normal: Vector3, collider: Object) -> void:
	var parent := collider as Node3D  # parent to the hit object so holes ride along on doors
	if parent == null:
		return
	if _hole_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(0.03, 0.03, 0.03, 1.0))
		g.set_color(1, Color(0.0, 0.0, 0.0, 0.0))
		var tex := GradientTexture2D.new()
		tex.gradient = g
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		tex.width = 32
		tex.height = 32
		_hole_tex = tex
	var d := Decal.new()
	d.texture_albedo = _hole_tex
	d.size = Vector3(0.08, 0.1, 0.08)
	d.cull_mask = 1
	parent.add_child(d)
	# Decals project along their -Y, so align +Y with the surface normal.
	var b := Basis(Vector3.RIGHT, PI) if normal.dot(Vector3.UP) < -0.999 else Basis(Quaternion(Vector3.UP, normal))
	d.global_transform = Transform3D(b, pos)
	_decals.append(d)
	if _decals.size() > MAX_DECALS:
		var old: Decal = _decals.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	puff(pos, normal, Color(0.55, 0.5, 0.42))


static func puff(pos: Vector3, normal: Vector3, color: Color, amount := 8, speed := 3.0) -> void:
	var root := (Engine.get_main_loop() as SceneTree).current_scene
	if root == null:
		return
	var p := CPUParticles3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE * 0.025
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mesh.material = mat
	p.mesh = mesh
	p.one_shot = true
	p.amount = amount
	p.lifetime = 0.5
	p.explosiveness = 1.0
	p.direction = normal
	p.spread = 35.0
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -6, 0)
	root.add_child(p)
	p.global_position = pos
	p.emitting = true
	p.finished.connect(p.queue_free)
