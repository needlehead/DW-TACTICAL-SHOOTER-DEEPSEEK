class_name DarkZone
extends Area3D
## Marks a low-light area. Roof and walls block the sun; inside, the sky ambient (which otherwise lights every
## corner) fades down to `ambient_scale`, and SpriteShadow darkens the 2D hands, gun, body and phone to `hand_color`.
## shortcut: the ambient is the scene's single Environment, so shaded spots outside also dim while you're in here;
## a per-room ambient (baked LightmapGI or SDFGI) is the upgrade if the map grows open windows.

@export var hand_color := Color(0.1, 0.1, 0.13)
@export var ambient_scale := 0.3  ## share of the sky ambient left inside (the rest is the Environment ambient colour, black by default)
@export var fade_time := 0.8  ## seconds; reads like the bodycam adjusting

var _base_energy := -1.0


func _ready() -> void:
	add_to_group(&"dark_zone")
	collision_layer = 0
	collision_mask = 2  # player body


func has_player() -> bool:
	for b in get_overlapping_bodies():
		if b is Player:
			return true
	return false


func _process(delta: float) -> void:
	var env := get_world_3d().environment
	if env == null:
		return
	if _base_energy < 0.0:
		_base_energy = env.ambient_light_sky_contribution
	var target := _base_energy * (ambient_scale if has_player() else 1.0)
	env.ambient_light_sky_contribution = move_toward(env.ambient_light_sky_contribution, target, _base_energy * delta / fade_time)
