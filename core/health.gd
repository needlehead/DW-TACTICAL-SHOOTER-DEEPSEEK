class_name Health
extends Node
## Hit points for anything damageable. All damage goes through take_damage() so items
## (armor, perks) can hook in later. No regeneration.

signal damaged(amount: float, zone: StringName, source: Node)
signal died(source: Node)

@export var max_health := 100.0
## Multiplier per hit zone; unknown zones (e.g. &"blast") use 1.0.
@export var zone_multipliers := {&"head": 4.0, &"torso": 1.0, &"arms": 0.6, &"legs": 0.7}

var current := 0.0
var dead := false


func _ready() -> void:
	reset()


func reset() -> void:
	current = max_health
	dead = false


## Returns damage actually applied after the zone multiplier.
func take_damage(amount: float, zone: StringName, source: Node) -> float:
	if dead:
		return 0.0
	var dmg := amount * float(zone_multipliers.get(zone, 1.0))
	current = maxf(current - dmg, 0.0)
	dead = current <= 0.0
	damaged.emit(dmg, zone, source)
	Game.record_damage(self, dmg, zone, source, dead)
	if dead:
		died.emit(source)
	return dmg
