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
	for p: Node in get_tree().root.find_children("*", "", true, false):
		if p is AudioStreamPlayer or p is AudioStreamPlayer3D:
			p.call("stop")
	for i in 3:  # let the audio server drop the stopped playbacks before quitting
		await get_tree().process_frame
	print("SMOKE TEST: %s" % ("OK" if failures == 0 else "%d FAILURES" % failures))
	get_tree().quit(1 if failures else 0)


func _logic_checks() -> void:
	var data: WeaponData = load("res://weapons/data/smg.tres")
	_check(is_equal_approx(data.damage_at(0.0), data.damage), "no falloff up close")
	_check(is_equal_approx(data.damage_at(1000.0), data.damage * data.min_damage_mult), "falloff floor")
	_check(data.modes() == [WeaponData.SEMI, WeaponData.BURST, WeaponData.AUTO], "SMG modes semi+burst+auto")

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
	# Sprite frames: idle, shoot right after a shot, reload frames spread over the reload.
	w.since_shot = 99.0
	_check(w.current_sprite(0.0) == data.idle_sprite, "idle sprite")
	w.since_shot = 0.0
	_check(w.current_sprite(0.0) == data.shoot_sprite, "shoot sprite right after firing")
	w.since_shot = 99.0
	data.reload_fps = 0.0
	w.start_reload()
	_check(w.current_sprite(0.0) == data.reload_sprites[0], "first reload frame at start")
	w.reload_left = w.reload_total * 0.5
	_check(w.current_sprite(0.0) == data.reload_sprites[4], "middle reload frame halfway")
	data.reload_fps = 10.0
	w.reload_left = w.reload_total - 0.35
	_check(w.current_sprite(0.0) == data.reload_sprites[3], "reload_fps 10: frame 3 at 0.35 s")
	w.reload_left = 0.01
	_check(w.current_sprite(0.0) == data.reload_sprites[-1], "reload_fps: last frame holds")
	w.reload_left = 0.0
	w.mag = 0
	w.chambered = false
	w.start_reload()
	var empty_frames := data.empty_reload_sprites if not data.empty_reload_sprites.is_empty() else data.reload_sprites
	_check(w.empty_reload and w.current_sprite(0.0) == empty_frames[0], "empty reload uses empty_reload_sprites")
	w.reload_left = 0.0
	var saved_aim := data.aim_sprites
	data.aim_sprites = [data.reload_sprites[0], data.reload_sprites[1], data.reload_sprites[2]]
	_check(w.current_sprite(0.0) == data.idle_sprite, "aim frames: idle at hip")
	_check(w.current_sprite(0.5) == data.aim_sprites[1], "aim frames: middle frame half aimed")
	_check(w.current_sprite(1.0) == data.aim_sprites[-1], "aim frames: last frame fully aimed")
	w.since_shot = 0.0
	_check(w.current_sprite(1.0) == data.aim_sprites[-1], "aimed firing keeps the aim frame")
	w.since_shot = 99.0
	data.aim_sprites = saved_aim
	data.reload_fps = 0.0
	w.free()

	# TTK sanity: SMG kills in 4 torso hits / 1 head hit up close; limbs take longer.
	var h := Health.new()
	add_child(h)
	for i in 3:
		h.take_damage(data.damage, &"torso", null)
	_check(not h.dead, "SMG: alive after 3 torso hits")
	h.take_damage(data.damage, &"torso", null)
	_check(h.dead, "SMG: dead after 4 torso hits")
	h.reset()
	h.take_damage(data.damage, &"head", null)
	_check(h.dead, "SMG: one-shot headshot")
	h.reset()
	for i in 3:
		h.take_damage(data.damage, &"arms", null)
	_check(not h.dead, "SMG: survives 3 arm hits")
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
	for i in 4:
		w._shoot()
	w.data.hip_spread = hip
	player.weapons._play_foley(player.weapons.aim_sound)
	_check(player.weapons.switch_phase == 0.0 and player.weapons.state == WeaponManager.State.READY, "aim sound doesn't lower the gun")
	var screen := player.get_viewport().get_visible_rect().size
	var saved_aim := player.viewmodel_aim
	player.viewmodel_aim = screen * 0.5 + Vector2(200, 0)
	_check((-player.aim_basis().z).dot(player.camera.global_basis.x) > 0.05, "hip fire follows the gun: sprite aimed right -> shots go right")
	player.viewmodel_aim = Vector2.INF
	_check((-player.aim_basis().z).is_equal_approx(-player.freeaim_basis().z), "no sprite gun: falls back to view + freeaim")
	player.viewmodel_aim = saved_aim
	var rifle := player.weapons.weapons[1]
	_check(rifle.data.display_name == "Radian Rifle" and rifle.data.scope_magnification > 0.0 and rifle.current_sprite(1.0) == rifle.data.aim_sprites[-1],
		"rifle in slot 2, scoped, last aim frame when fully aimed")
	var ed := player.get_node("HUDLayer/ViewmodelEditor") as ViewmodelEditor
	var before := ed.data().sprite_offset
	ed.toggle()
	ed.nudge(Vector2(0.01, 0.0))
	var moved := ed.data().sprite_offset.is_equal_approx(before + Vector2(0.01, 0.0))
	ed.revert()
	_check(moved and ed.data().sprite_offset == before, "viewmodel editor: nudge moves the gun, revert restores")
	ed.toggle()
	_check(rifle.current_sprite(0.0, 0.4) == rifle.data.idle_sprite and rifle.current_sprite(0.0, 0.6) == rifle.data.sprint_sprite,
		"rifle sprint frame swaps in at the bottom of the dip")
	rifle.toggle_canted()
	rifle.cant_t = 0.5
	_check(is_equal_approx(rifle.sight_progress(1.0), 1.0 - rifle.data.cant_dip), "sight switch dips mid-roll")
	rifle.cant_t = 1.0
	_check(rifle.canted and rifle.current_sprite(1.0) == rifle.data.canted_aim_sprites[-1] and rifle.aim_window() == rifle.data.canted_sight_window,
		"rifle canted sight: own frames and window")
	rifle.toggle_canted()
	rifle.cant_t = 0.0
	_check(not rifle.canted and rifle.current_sprite(1.0) == rifle.data.aim_sprites[-1], "rifle canted toggles back to the ACOG")
	var phone_script: GDScript = load("res://player/phone.gd")
	_check(is_equal_approx(phone_script.ecg(0.20), 1.0) and phone_script.ecg(0.35) == 0.0 and phone_script.ecg(0.22) < 1.0,
		"phone ECG: R spike peaks at 1, flat between beats")
	var amb := get_node("/root/Ambience")
	var all: Array[String] = ["a", "b", "c"]
	var pass1: Array[String] = amb.shuffled(all, "a")
	_check(pass1.size() == 3 and pass1[0] != "a" and pass1.has("a"), "ambience shuffle: full pass, no back-to-back repeat")
	var probe := player.get_node("ReverbProbe") as ReverbProbe
	var space := player.get_world_3d().direct_space_state
	var sky := probe.estimate(space, Vector3(0, 300, 0), [] as Array[RID])
	_check(sky.enclosure == 0.0 and is_equal_approx(sky.wet, probe.wet_range.x), "reverb: open sky is driest")
	var here := probe.estimate(space, player.camera.global_position, [player.get_rid()] as Array[RID])
	_check(here.wet >= sky.wet and AudioServer.get_bus_index(&"World") >= 0, "reverb: World bus exists, walls add reverb")
	var sky_pts := PackedVector3Array([Vector3(0, 300, 0)])
	var under_ground := PackedVector3Array([Vector3(0, -5, 0)])
	_check(SpriteShadow.lit_fraction(space, sky_pts, Vector3.UP, []) == 1.0 and SpriteShadow.lit_fraction(space, under_ground, Vector3.UP, []) == 0.0,
		"sprite shadow: open sky lit, under the ground shaded")
	_check(w.mag_estimate() == "Nearly full", "phone mag estimate at 25/30")
	player.weapons.phone_blend = 0.75
	_check(not player.weapons.can_fire() and player.weapons.phone_gun_lower() == 1.0 and player.weapons.phone_raise() == 0.5,
		"phone up: gun fully lowered, phone half raised, can't fire")
	player.weapons.phone_blend = 0.0
	_check(target.health.dead, "4 SMG torso shots kill a 10 m dummy")
	_check(Game.last_ttk.contains("4 hits"), "TTK recorded: " + Game.last_ttk)
	_check(w.mag == 25, "4 rounds spent")
	# Penetration: the 15 m dummy stands behind a thin board, so it takes reduced damage.
	var pen_target := level.get_node("Dummies/Range4") as Dummy
	d = pen_target.global_position + Vector3.UP * 1.17 - player.camera.global_position
	player.look_yaw = rad_to_deg(atan2(-d.x, -d.z))
	player.look_pitch = rad_to_deg(asin(d.y / d.length()))
	player.recoil = Vector2.ZERO
	player.recoil_target = Vector2.ZERO
	var vm = player.get_node("LeanPivot/Head/Camera3D/Viewmodel")  # shots follow the gun: let the last burst's kick settle
	vm.kick_pos = Vector3.ZERO
	vm.kick_rot = Vector3.ZERO
	for i in 2:
		await get_tree().process_frame
	w.data.hip_spread = 0.0
	w._shoot()
	w.data.hip_spread = hip
	var taken := pen_target.health.max_health - pen_target.health.current
	_check(taken > 0.0 and taken < w.data.damage * 0.9, "penetration hit for reduced damage: %.1f" % taken)
	var blast_target := level.get_node("Dummies/Range1") as Dummy
	var g := (load("res://weapons/grenade.tscn") as PackedScene).instantiate() as Grenade
	g.thrower = player
	level.add_child(g)
	g.global_position = blast_target.global_position + Vector3(0.5, 0.2, -1.0)
	g.explode()
	_check(blast_target.health.dead, "grenade 1.1 m away kills")
	Game.reset_level()
	_check(not target.health.dead and w.mag == 29, "reset revives dummies and refills ammo")
	# HUD markers through the bodycam lens: to_screen() must invert the shader's distortion.
	var cam_fx := level.get_node("Player/PostFXLayer/Bodycam") as Bodycam
	var vp := cam_fx.get_viewport_rect().size
	for q: Vector2 in [vp * 0.5, vp * Vector2(0.3, 0.7), vp * Vector2(0.9, 0.1)]:
		var on_screen := cam_fx.to_screen(q)
		_check(cam_fx.distort(on_screen / vp, vp.x / vp.y).distance_to(q / vp) < 0.001, "bodycam lens inverse at %s" % q)
	var panel := level.get_node("Player/HUDLayer/DebugPanel")
	panel.visible = true
	panel.call("_bind")
	panel.call("_process", 0.016)
	panel.visible = false
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
