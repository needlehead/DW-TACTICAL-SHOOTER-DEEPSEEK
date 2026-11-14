extends Node
## Autoload hub: reset key, hit confirmation / TTK bookkeeping and HUD toasts.

signal hit_confirmed(zone: StringName, damage: float, killed: bool)
signal toast_requested(text: String)

## Hits further apart than this start a new TTK measurement on the same target.
const ENGAGEMENT_TIMEOUT := 3.0

var last_hit := "-"
var last_ttk := "-"
var _engagements := {}  # Health -> {start, last, hits}


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("reset"):
		reset_level()


func reset_level() -> void:
	_engagements.clear()
	get_tree().call_group("resettable", "reset")
	toast("Reset: dummies respawned, ammo refilled")


func toast(text: String) -> void:
	toast_requested.emit(text)


## Called by Health for every damage event; only player-dealt damage to other targets is tracked.
func record_damage(target: Node, damage: float, zone: StringName, source: Node, killed: bool) -> void:
	if source == null or not source.is_in_group("player") or target.owner == source:
		return
	var now := Time.get_ticks_msec() / 1000.0
	var e: Dictionary = _engagements.get(target, {})
	if e.is_empty() or now - float(e.last) > ENGAGEMENT_TIMEOUT:
		e = {"start": now, "last": now, "hits": 0}
		_engagements[target] = e
	e.hits += 1
	e.last = now
	last_hit = "%s  %.0f dmg" % [zone, damage]
	if killed:
		last_ttk = "%.2fs  %d hits" % [now - float(e.start), e.hits]
		_engagements.erase(target)
	hit_confirmed.emit(zone, damage, killed)
