class_name ReverbProbe
extends Node
## Room-aware reverb for world sounds (guns, footsteps). A few times a second, cast rays around the listener (the player's eyes) to judge
## how enclosed the space is and how far the walls are, then steer the reverb on the "World" bus:
## small closed rooms -> short, wet ring; open ground -> drier, with a slapback echo off distant walls.

@export var update_interval := 0.15
@export var ray_length := 40.0
@export var rays := 12
@export var near_wall := 6.0  ## walls closer than this count as "enclosing"
@export var wet_range := Vector2(0.05, 0.4)  ## wet at fully open .. fully enclosed
@export var footstep_wet_scale := 0.4  ## footsteps get this share of the gunfire wetness
@export var smoothing := 4.0  ## how fast the reverb settles after moving between spaces (1/s)

var _t := 0.0
var _target := {}
var _reverb: AudioEffectReverb
var _steps_reverb: AudioEffectReverb

@onready var player: Player = owner


func _ready() -> void:
	_reverb = _bus_reverb(&"World")
	_steps_reverb = _bus_reverb(&"Footsteps")


static func _bus_reverb(bus_name: StringName) -> AudioEffectReverb:
	var bus := AudioServer.get_bus_index(bus_name)
	if bus >= 0 and AudioServer.get_bus_effect_count(bus) > 0:
		return AudioServer.get_bus_effect(bus, 0) as AudioEffectReverb
	return null


func _process(delta: float) -> void:
	if _reverb == null:
		return
	_t -= delta
	if _t <= 0.0:
		_t = update_interval
		_target = estimate(player.get_world_3d().direct_space_state, player.camera.global_position, [player.get_rid()])
	var k := 1.0 - exp(-smoothing * delta)
	for p: String in ["wet", "room_size", "damping", "predelay_msec", "predelay_feedback"]:
		_reverb.set(p, lerpf(_reverb.get(p), _target[p], k))
		if _steps_reverb:
			var v: float = _target[p] * (footstep_wet_scale if p == "wet" else 1.0)
			_steps_reverb.set(p, lerpf(_steps_reverb.get(p), v, k))


## Reverb settings for a listener at `from`. A pure query, so tests can probe any spot in the level.
func estimate(space: PhysicsDirectSpaceState3D, from: Vector3, exclude: Array[RID]) -> Dictionary:
	var near := 0
	var total := 0.0
	for i in rays:
		var a := TAU * i / rays
		var d := _cast(space, from, Vector3(cos(a), 0.0, sin(a)), exclude)
		total += d
		if d < near_wall:
			near += 1
	var mean := total / rays
	var roofed := _cast(space, from, Vector3.UP, exclude) < ray_length
	var enclosure := clampf(float(near) / rays + (0.25 if roofed else 0.0), 0.0, 1.0)
	return {
		"enclosure": enclosure,
		"wet": lerpf(wet_range.x, wet_range.y, enclosure),
		"room_size": clampf(mean / 30.0, 0.1, 0.9),
		"damping": lerpf(0.75, 0.35, enclosure),  # open air eats the highs
		"predelay_msec": clampf(mean * 2.0 / 343.0 * 1000.0, 5.0, 200.0),  # sound's round trip to the walls
		"predelay_feedback": lerpf(0.35, 0.05, enclosure),  # outdoors: distinct slapback echoes
	}


func _cast(space: PhysicsDirectSpaceState3D, from: Vector3, dir: Vector3, exclude: Array[RID]) -> float:
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + dir * ray_length, 1, exclude))
	return from.distance_to(hit.position) if hit else ray_length
