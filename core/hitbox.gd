class_name Hitbox
extends Area3D
## A damage zone on the "hitbox" physics layer. Bullets and blasts find these, never the movement capsule.

@export var zone: StringName = &"torso"
## Defaults to the "Health" node of the scene this hitbox belongs to.
@export var health: Health


func _ready() -> void:
	collision_layer = Ballistics.HITBOX
	collision_mask = 0
	if health == null:
		health = owner.get_node_or_null("Health") as Health


func hit(damage: float, source: Node) -> void:
	if health:
		health.take_damage(damage, zone, source)


func set_enabled(on: bool) -> void:
	collision_layer = Ballistics.HITBOX if on else 0
