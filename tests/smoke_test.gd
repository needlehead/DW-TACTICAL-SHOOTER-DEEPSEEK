extends Node
## Headless check: loads every script/scene/resource, then runs logic asserts.
## Run: godot --headless --path . res://tests/smoke_test.tscn

var failures := 0


func _ready() -> void:
	for path in _files("res://", ["gd", "tscn", "tres"]):
		if path.begins_with("res://tests/") or path.begins_with("res://maps/tools/"):
			continue
		if load(path) == null:
			_fail("could not load " + path)
	_logic_checks()
	print("SMOKE TEST: %s" % ("OK" if failures == 0 else "%d FAILURES" % failures))
	get_tree().quit(1 if failures else 0)


func _logic_checks() -> void:
	var data: WeaponData = load("res://weapons/data/assault_rifle.tres")
	_check(is_equal_approx(data.damage_at(0.0), data.damage), "no falloff up close")
	_check(is_equal_approx(data.damage_at(1000.0), data.damage * data.min_damage_mult), "falloff floor")
	_check(data.modes() == [WeaponData.SEMI, WeaponData.AUTO], "AR modes semi+auto")

	var w := Weapon.new()
	w.data = data
	w.refill()
	_check(w.chambered and w.mag == 29 and w.spare.size() == 5, "spawns with 29+1 and 5 spares")
	for i in 10:
		w.cycle_round()
	w.finish_reload()  # tactical: keeps the chambered round
	_check(w.chambered and w.mag == 30, "tactical reload gives 30+1")
	_check(w.spare.size() == 5 and w.spare.has(19), "partial mag goes back to the pouch untouched")
	for i in 31:
		w.cycle_round()
	_check(not w.chambered and w.mag == 0, "empty after 31 shots")
	w.finish_reload()  # empty: chambers from the new mag
	_check(w.chambered and w.mag == 29 and w.spare.size() == 4, "empty reload gives 29+1, empty mag dropped")
	w.free()

	# TTK sanity: AR kills in 3 torso hits / 1 head hit up close; limbs take longer.
	var h := Health.new()
	add_child(h)
	for i in 2:
		h.take_damage(data.damage, &"torso", null)
	_check(not h.dead, "AR: alive after 2 torso hits")
	h.take_damage(data.damage, &"torso", null)
	_check(h.dead, "AR: dead after 3 torso hits")
	h.reset()
	h.take_damage(data.damage, &"head", null)
	_check(h.dead, "AR: one-shot headshot")
	h.reset()
	for i in 3:
		h.take_damage(data.damage, &"arms", null)
	_check(not h.dead, "AR: survives 3 arm hits")
	h.queue_free()


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fail(what)


func _fail(msg: String) -> void:
	failures += 1
	push_error(msg)


func _files(dir: String, exts: Array) -> Array[String]:
	var out: Array[String] = []
	for f in DirAccess.get_files_at(dir):
		if f.get_extension() in exts:
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		if not d.begins_with("."):
			out.append_array(_files(dir.path_join(d), exts))
	return out
