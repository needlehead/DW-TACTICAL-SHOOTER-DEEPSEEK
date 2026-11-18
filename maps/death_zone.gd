class_name DeathZone
extends Area3D
## Test pad: stepping on it kills the player at once, to check the death views (F5 respawns).
## damage_zone picks the death: &"torso" gives the normal one (random standing, or prone if you crawl on),
## &"blast" the grenade launch.

@export var damage_zone := &"torso"


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2  # player body
	body_entered.connect(func(body: Node3D) -> void:
		if body is Player and (body as Player).alive:
			(body as Player).health.take_damage(1.0e6, damage_zone, self))
