class_name Grenade
extends RigidBody3D
## Placeholder frag: physics arc, fuse, radius damage with falloff, blocked by world geometry.

@export var fuse := 3.5
@export var radius := 9.0
@export var max_damage := 250.0  ## at the centre; Health zone multiplier for &"blast" is 1.0
@export var falloff_exponent := 1.5  ## >1 keeps the lethal core tight

var thrower: Node


func _ready() -> void:
	get_tree().create_timer(fuse, false, true).timeout.connect(explode)


func explode() -> void:
	var space := get_world_3d().direct_space_state
	var center := global_position + Vector3.UP * 0.1
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = sphere
	q.transform = Transform3D(Basis(), center)
	q.collide_with_areas = true
	q.collide_with_bodies = false
	q.collision_mask = Ballistics.HITBOX
	# Each target takes damage once, from its closest visible hitbox.
	var best := {}  # Health -> damage
	for r in space.intersect_shape(q, 128):
		var hb := r.collider as Hitbox
		if hb == null or hb.health == null:
			continue
		var los := PhysicsRayQueryParameters3D.create(center, hb.global_position, Ballistics.WORLD)
		if not space.intersect_ray(los).is_empty():
			continue
		var t := clampf(1.0 - center.distance_to(hb.global_position) / radius, 0.0, 1.0)
		var dmg := max_damage * pow(t, falloff_exponent)
		if dmg > float(best.get(hb.health, 0.0)):
			best[hb.health] = dmg
	for h: Health in best:
		h.take_damage(best[h], &"blast", thrower)
	Impact.puff(center, Vector3.UP, Color(0.35, 0.3, 0.25), 40, 9.0)
	_flash(center)
	queue_free()


func _flash(pos: Vector3) -> void:
	var light := OmniLight3D.new()
	light.omni_range = radius
	light.light_energy = 8.0
	light.light_color = Color(1.0, 0.7, 0.4)
	get_parent().add_child(light)
	light.global_position = pos
	light.create_tween().tween_property(light, "light_energy", 0.0, 0.25)
	get_tree().create_timer(0.3).timeout.connect(light.queue_free)
