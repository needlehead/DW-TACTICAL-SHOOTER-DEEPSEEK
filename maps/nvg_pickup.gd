class_name NVGPickup
extends StaticBody3D
## Night vision goggles on a stand. Interact (F) to pick them up: the player owns them and N flips them down.
## Comes back on level reset (F5), which also takes them off the player.


func _ready() -> void:
	add_to_group("resettable")


func interact(user: Node3D) -> void:
	if not visible:
		return
	var nv := user.get_node_or_null("ViewmodelLayer/NightVision") as NightVision
	if nv == null:
		return
	nv.owned = true
	visible = false
	collision_layer = 0
	Game.toast("Picked up night vision: N to flip down")


func reset() -> void:
	visible = true
	collision_layer = 1
