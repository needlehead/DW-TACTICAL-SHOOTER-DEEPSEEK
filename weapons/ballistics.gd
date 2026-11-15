class_name Ballistics
## Bullet tracing with penetration and falloff. Hitscan today; trace_segment() is the unit a
## projectile mode would call once per physics tick (from last position to new position).

const WORLD := 1
const ACTORS := 2
const HITBOX := 4
const PENETRABLE := 8


## Per-bullet state, carried across segments and penetrations.
class Shot:
	var data: WeaponData
	var origin: Vector3
	var source: Node
	var exclude: Array[RID] = []
	var damage_mult := 1.0
	var penetrations := 0


static func fire(space: PhysicsDirectSpaceState3D, origin: Vector3, dir: Vector3, data: WeaponData,
		source: Node, exclude: Array[RID], damage_mult := 1.0) -> void:
	var shot := Shot.new()
	shot.data = data
	shot.origin = origin
	shot.source = source
	shot.exclude.assign(exclude)
	shot.damage_mult = damage_mult
	# shortcut: PROJECTILE mode resolves instantly too; add a Projectile node that steps trace_segment() with velocity + gravity when needed.
	trace_segment(space, shot, origin, origin + dir * data.max_range)


## Returns true when the bullet stopped inside this segment.
static func trace_segment(space: PhysicsDirectSpaceState3D, shot: Shot, from: Vector3, to: Vector3) -> bool:
	var dir := (to - from).normalized()
	for i in shot.data.max_penetrations + 1:
		var q := PhysicsRayQueryParameters3D.create(from, to, WORLD | HITBOX, shot.exclude)
		q.collide_with_areas = true
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return false
		var pos: Vector3 = hit.position
		var normal: Vector3 = hit.normal
		var hitbox := hit.collider as Hitbox
		if hitbox:
			hitbox.hit(shot.data.damage_at(shot.origin.distance_to(pos)) * shot.damage_mult, shot.source)
			Impact.puff(pos, normal, Color(0.6, 0.05, 0.05), 10)
			return true
		Impact.bullet_hole(pos, normal, hit.collider)
		var penetrable := PhysicsServer3D.body_get_collision_layer(hit.rid) & PENETRABLE
		if not penetrable or shot.penetrations >= shot.data.max_penetrations:
			return true
		shot.penetrations += 1
		shot.damage_mult *= shot.data.penetration_power
		shot.exclude.append(hit.rid)
		from = pos + dir * 0.01
	return true


## Random direction inside a cone of `degrees` half-angle around `forward` (uniform over the disc).
static func spread_dir(forward: Vector3, degrees: float) -> Vector3:
	var up := Vector3.UP if absf(forward.y) < 0.99 else Vector3.RIGHT
	var right := forward.cross(up).normalized()
	up = right.cross(forward)
	var r := sqrt(randf()) * tan(deg_to_rad(degrees))
	var a := randf() * TAU
	return (forward + right * cos(a) * r + up * sin(a) * r).normalized()
