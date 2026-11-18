class_name DroppedMag
extends RigidBody3D
## A magazine thrown away by a speed reload: a thin box that tumbles and settles on the floor, showing the weapon's
## mag sprite on its broad face (so lying flat it faces up). Only collides with the world; the oldest go once there
## are more than MAX, and a level reset (F5) clears them.

const MAX := 20
static var _used_rects := {}  # texture -> its drawn area (computed once)


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
	s.position.z = size.z * 0.5  # on the broad face
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.shaded = true
	s.double_sided = true
	m.add_child(s)
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


func reset() -> void:
	queue_free()
