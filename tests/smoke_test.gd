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
	await _runtime_checks()
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


## Plays the real level for a few seconds: patrols move, shots register, TTK and reset work.
func _runtime_checks() -> void:
	var level: Node = load("res://maps/killhouse.tscn").instantiate()
	add_child(level)
	var patrol := level.get_node("Dummies").get_children().filter(func(d: Node) -> bool: return d.name.begins_with("Patrol"))[0] as Dummy
	var start := patrol.global_position
	for i in 240:
		await get_tree().physics_frame
	_check(patrol.global_position.distance_to(start) > 1.0, "patrol dummy moves along its route")

	var player := level.get_node("Player") as Player
	var target := level.get_node("Dummies/Range0") as Dummy
	var d := target.global_position + Vector3.UP * 1.17 - player.camera.global_position
	player.look_yaw = rad_to_deg(atan2(-d.x, -d.z))
	player.look_pitch = rad_to_deg(asin(d.y / d.length()))
	for i in 2:  # process_frame fires before nodes process, so wait for one full frame
		await get_tree().process_frame
	var w := player.weapons.current
	var hip := w.data.hip_spread
	w.data.hip_spread = 0.0
	for i in 3:
		w._shoot()
	w.data.hip_spread = hip
	_check(target.health.dead, "3 AR torso shots kill a 10 m dummy")
	_check(Game.last_ttk.contains("3 hits"), "TTK recorded: " + Game.last_ttk)
	_check(w.mag == 26, "3 rounds spent")
	var blast_target := level.get_node("Dummies/Range1") as Dummy
	var g := (load("res://weapons/grenade.tscn") as PackedScene).instantiate() as Grenade
	g.thrower = player
	level.add_child(g)
	g.global_position = blast_target.global_position + Vector3(0.5, 0.2, -1.0)
	g.explode()
	_check(blast_target.health.dead, "grenade 1.1 m away kills")
	Game.reset_level()
	_check(not target.health.dead and w.mag == 29, "reset revives dummies and refills ammo")
	level.queue_free()


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
