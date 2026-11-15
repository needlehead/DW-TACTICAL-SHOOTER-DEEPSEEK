class_name SpriteShadow
extends CanvasModulate
## Shades the 2D viewmodel (gun, body, phone) when the player's hands are out of the sun. Sprites can't
## receive real 3D shadows, so a few rays from around the hands toward the sun measure how lit they are,
## and this CanvasModulate (tints its whole CanvasLayer) fades between `lit_color` and `shadow_color`.

@export var lit_color := Color(1, 1, 1)
@export var shadow_color := Color(0.5, 0.53, 0.62)  ## sky-lit shade: darker and a bit cool
@export var fade_speed := 6.0  ## 1/s; walking into shadow fades instead of snapping
## Sample points in camera space (right, up, back): gun hands, grip, chest. More points = softer edges.
@export var samples := PackedVector3Array([Vector3(0.15, -0.2, -0.45), Vector3(0.05, -0.3, -0.25), Vector3(0.0, -0.45, 0.0)])

var _sun: DirectionalLight3D

@onready var player: Player = owner


func _process(delta: float) -> void:
	if _sun == null:
		_sun = _find_sun()
	var lit := 1.0
	if _sun and _sun.visible and _sun.shadow_enabled:
		var cam := player.camera.global_transform
		var points := PackedVector3Array()
		for s in samples:
			points.append(cam * s)
		lit = lit_fraction(player.get_world_3d().direct_space_state, points, _sun.global_basis.z, [player.get_rid()])
	color = color.lerp(shadow_color.lerp(lit_color, lit), 1.0 - exp(-fade_speed * delta))


## Share of `points` with a clear line to the sun (`to_sun` = direction toward it).
static func lit_fraction(space: PhysicsDirectSpaceState3D, points: PackedVector3Array, to_sun: Vector3, exclude: Array[RID]) -> float:
	var clear := 0
	for p in points:
		if space.intersect_ray(PhysicsRayQueryParameters3D.create(p, p + to_sun * 200.0, 1, exclude)).is_empty():
			clear += 1
	return float(clear) / maxf(points.size(), 1)


func _find_sun() -> DirectionalLight3D:
	for n in get_tree().current_scene.find_children("*", "DirectionalLight3D", true, false):
		return n as DirectionalLight3D
	return null
