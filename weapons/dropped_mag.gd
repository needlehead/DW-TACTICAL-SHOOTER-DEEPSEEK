class_name DroppedMag
extends RigidBody3D
## A magazine thrown away by a speed reload: a thin box that tumbles and settles on the floor, showing the weapon's
## mag sprite on its broad face (so lying flat it faces up). Only collides with the world; the oldest go once there
## are more than MAX, and a level reset (F5) clears them. Once it stops moving it tips onto its broad face if it came
## to rest on an edge (seen edge-on the sprite is only a sliver), then stays put.

const MAX := 20
static var _used_rects := {}  # texture -> its drawn area (computed once)

var _half_thickness := 0.0
var _still := 0.0  # seconds it has barely moved


## Throws `tex` from `at` with `vel`; `length` is the mag's real length in metres.
static func spawn(parent: Node, tex: Texture2D, length: float, at: Vector3, vel: Vector3) -> DroppedMag:
	var m := DroppedMag.new()
	var region := _used_rect(tex)
	var size := Vector3(length * region.size.x / region.size.y, length, length * 0.16)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	m.add_child(shape)
	var s := Sprite3D.new()
	s.texture = tex
	s.region_enabled = true
	s.region_rect = region
	s.pixel_size = length / region.size.y
	# Mid-thickness, not on a face: whichever side it lands on, the picture stays clear of the floor (no z-fighting).
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC  # no sparkle when small / far
	s.shaded = true
	s.double_sided = true
	m.add_child(s)
	m._half_thickness = size.z * 0.5
	m.collision_layer = 0
	m.collision_mask = Ballistics.WORLD
	m.mass = 0.4
	m.linear_velocity = vel
	m.angular_velocity = Vector3(randf_range(-9, 9), randf_range(-9, 9), randf_range(-9, 9))
	m.add_to_group(&"dropped_mag")
	m.add_to_group(&"resettable")
	parent.add_child(m)
	m.global_position = at
	m.global_basis = Basis.from_euler(Vector3(randf() * TAU, randf() * TAU, randf() * TAU))
	var all := parent.get_tree().get_nodes_in_group(&"dropped_mag")
	if all.size() > MAX:
		all[0].queue_free()
	return m


static func _used_rect(tex: Texture2D) -> Rect2:
	if not _used_rects.has(tex):
		var img := tex.get_image()
		if img.is_compressed():
			img.decompress()
		_used_rects[tex] = Rect2(img.get_used_rect())
	return _used_rects[tex]


func _physics_process(delta: float) -> void:
	if freeze:
		return
	_still = _still + delta if linear_velocity.length() < 0.08 and angular_velocity.length() < 0.4 else 0.0
	if _still > 0.25:
		_settle()


## Comes to rest: frozen where it is if lying flat, else tipped over flat (keeping the way it points) onto the floor.
func _settle() -> void:
	freeze = true
	var b := global_basis
	if absf(b.z.normalized().y) > 0.95:
		return
	var up := Vector3.UP if b.z.y >= 0.0 else Vector3.DOWN
	var along := Vector3(b.y.x, 0.0, b.y.z)
	if along.length() < 0.01:
		along = Vector3(b.x.x, 0.0, b.x.z)
	along = along.normalized()
	var flat := Basis(along.cross(up), along, up).orthonormalized()
	var pos := global_position
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 0.2, pos + Vector3.DOWN * 1.0, Ballistics.WORLD)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		pos.y = hit.position.y + _half_thickness
	create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN) 		.tween_property(self, "global_transform", Transform3D(flat, pos), 0.15)


func reset() -> void:
	queue_free()
