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

	var menu: Control = load("res://ui/main_menu.gd").new()
	var at := func(f: int) -> int: return menu.frame_at((f + 0.5) / menu.fps)
	_check(at.call(0) == 0 and at.call(119) == 119 and at.call(120) == 118 and at.call(238) == 0, "menu idle ping-pongs")
	menu.free()


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
	player.cam_noise_deg = Vector3.ZERO  # scripted shots below need a steady view and gun
	player.breath_sway_deg = Vector2.ZERO
	player.fatigue_sway_deg = Vector2.ZERO
	player.get_node("ViewmodelLayer/SpriteViewmodel").set("shake_amount", 0.0)
	player.get_node("ViewmodelLayer/SpriteViewmodel").set("shake_roll", 0.0)
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
	var lights := player.get_node("ViewmodelLayer/WeaponLights") as WeaponLights
	_check(lights.dot_visible, "laser dot lands where the gun points")
	var zone := level.get_node("DarkArea/DarkZone") as DarkZone
	var saved_pos := player.global_position
	player.global_position = zone.global_position + Vector3(-2.0, 0.05, 2.0)
	for i in 4:
		await get_tree().physics_frame
	_check(zone.has_player(), "dark zone notices the player")
	player.global_position = saved_pos
	for i in 4:
		await get_tree().physics_frame
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
	ed.set_mode(ViewmodelEditor.Mode.TABLET)
	var hold := ed.layout().hold_offset
	ed.nudge(Vector2(0.0, 0.02))
	var tablet_moved := ed.layout().hold_offset.is_equal_approx(hold + Vector2(0.0, 0.02)) and player.weapons.phone_forced
	ed.revert()
	_check(tablet_moved and ed.layout().hold_offset == hold, "viewmodel editor: tablet mode raises the phone, nudges and reverts")
	ed.dead_kind = 1
	ed.set_mode(ViewmodelEditor.Mode.DEAD)
	var po := player.death_view.prone_offset
	ed.nudge(Vector2(0.0, 0.03))
	var dead_ok := player.preview_death == 2 and player.shows_death() and player.death_prone() \
		and player.death_view.prone_offset.is_equal_approx(po + Vector2(0.0, 0.03))
	ed.revert()
	# Grenade death preview: thrown frame first, landed frame once the launch is over.
	ed.dead_kind = 3
	ed._sync_preview()
	var body := player.get_node("ViewmodelLayer/BodySprite")
	player.death_t = 0.0
	body._process(0.0)
	var thrown: Texture2D = body.texture
	player.death_t = 1.0
	body._process(0.0)
	_check(player.death_kind() == "launch_" and thrown == body.launch_sprites[0] and body.texture == body.launch_sprites[2],
		"grenade death: thrown frame, then the landed frame")
	# Easter egg preview: walk up, grab, drag (tugs), thrown, landed on the heap - and the camera only, no moving.
	ed.dead_kind = 4
	ed._sync_preview()
	var pos := player.global_position
	var seen := []
	for k in 100:  # steps only the sequence: a full player._process would also settle earlier recoil
		player.egg.update(0.1)
		body._process(0.0)
		var f: int = body.egg_sprites.find(body.texture)
		if seen.is_empty() or seen[-1] != f:
			seen.append(f)
	_check(seen.slice(0, 3) == [0, 1, 2] and seen.slice(-2) == [3, 4] and body._back.visible
		and player.global_position.is_equal_approx(pos), "easter egg death: frames in order, heap behind, preview doesn't move her: %s" % [seen])
	player.egg.stop()
	ed.dead_kind = 0
	ed._sync_preview()
	body._process(0.0)
	_check(not body._back.visible, "easter egg death: the heap goes away once that death is over")
	player.eye_height = player.eye_heights[player.stance]
	_check(dead_ok and player.death_view.prone_offset == po, "viewmodel editor: dead mode previews the prone death, nudges and reverts")
	ed.set_mode(ViewmodelEditor.Mode.HIP)
	_check(player.preview_death == 0, "viewmodel editor: leaving dead mode ends the preview")
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
	var kei: Dictionary = phone_script.theme(Color("#529364"))
	var dark: Dictionary = phone_script.theme(Color("#1E2A6E"))
	_check(kei.on_main.get_luminance() < 0.2 and dark.on_main == Color.WHITE and kei.ground.get_luminance() < 0.1,
		"tablet palette: dark text on a light heroine colour, white on a dark one, near-black background")
	var fx := player.get_node("HUDLayer/DamageFeedback") as DamageFeedback
	_check(fx.low_pulse(1.0, 0.0) == 0.0 and fx.low_pulse(0.1, 0.0) > 0.0, "damage feedback: heartbeat vignette only at low health")
	var svm = player.get_node("ViewmodelLayer/SpriteViewmodel")
	rifle.reload_total = 2.0
	rifle.reload_left = 1.0
	var mid: Vector2 = svm.reload_sway(rifle)
	rifle.reload_left = 1.999
	var rl_start: Vector2 = svm.reload_sway(rifle)
	rifle.reload_left = 0.0
	_check(mid.y > 0.02 and rl_start.length() < 0.001 and svm.reload_sway(rifle) == Vector2.ZERO, "reload sway: eases in, dips mid-reload, lands at rest")
	var voice := player.get_node("PlayerVoice") as PlayerVoice
	voice.exertion = 0.0
	var calm := voice.breath_target()
	voice.exertion = 0.8
	_check(calm == 0.0 and voice.breath_target() == 0.8 and voice.breath_loop.get("loop"), "breathing: silent at rest and full health, follows exertion, loops")
	voice.exertion = 0.0
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
	var wm := player.weapons
	wm.phone_open = true
	wm.phone_page = 0
	wm.flip_page(-1)
	var wrapped := wm.phone_page == Phone.PAGES.size() - 1
	wm.flip_page(1)
	player.health.damaged.emit(1.0, &"torso", null)
	_check(wrapped and wm.phone_page == 0 and not wm.phone_open, "phone pages wrap; taking damage closes the phone")
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
	var ed2 := player.get_node("HUDLayer/ViewmodelEditor") as ViewmodelEditor
	var was_open := ed2.visible
	if not was_open:
		ed2.toggle()
	ed2.dead_kind = 0
	ed2.set_mode(ViewmodelEditor.Mode.DEAD)  # standing death preview
	var sr := player.death_view.stand_roll
	player.death_view.stand_roll = 9.0
	player._process(1.0)  # one long step: the roll eases in over 0.7 s
	var stand_rolled := is_equal_approx(player.death_roll, 9.0) and not player.death_prone()
	player.death_view.stand_roll = sr
	ed2.set_mode(ViewmodelEditor.Mode.HIP)
	if not was_open:
		ed2.toggle()
	player.eye_height = player.eye_heights[player.stance]
	player.death_roll = 0.0
	_check(stand_rolled, "standing death has its own view roll")
	var talk: Dictionary = (load("res://dialogue/ingrid_intro.tres") as Dialogue).compile()
	_check(talk.steps.size() == 7 and talk.steps[0] == ["say", "Ingrid", "You seem cool."], "dialogue: lines parse into speaker / text")
	var talk2: Dictionary = (load("res://dialogue/ingrid_range_day.tres") as Dialogue).compile()
	var menus: Array = talk2.steps.filter(func(s: Array) -> bool: return s[0] == "choose")
	var landed := true
	for m: Array in menus:
		for o: Array in m[1]:
			landed = landed and talk2.labels.has(o[1])
	_check(menus.size() == 2 and menus[0][1].size() == 3 and landed, "dialogue: choices parse and every option has a branch")
	# Speed reload (double-tapped reload): quicker, and the old magazine is thrown away instead of pocketed.
	var rw: Weapon = null
	for wpn: Weapon in player.weapons.weapons:
		if wpn.data.resource_path.ends_with("rifle.tres"):
			rw = wpn
	var mags_before := rw.spare.size()
	rw.reload_left = 0.0
	rw.mag = 7
	rw.chambered = true
	rw.start_reload()
	var sped := rw.speed_up()
	rw.reload_left = 0.01
	rw.tick(0.02, false, false, false)
	_check(sped and rw.reload_total == rw.data.speed_reload_time and rw.spare.size() == mags_before - 1 and rw.mag == rw.data.mag_size,
		"speed reload: quicker and the old magazine is gone, not pocketed")
	_check(get_tree().get_nodes_in_group(&"dropped_mag").size() == 1, "speed reload: the thrown magazine lands in the world")
	for dm in get_tree().get_nodes_in_group(&"dropped_mag"):
		dm.free()
	rw.refill()
	# Stamina: recovers after a rest; low stamina means a much bigger aim wobble.
	var bs := player.breath_sway_deg
	var fs := player.fatigue_sway_deg
	player.breath_sway_deg = Vector2(0.1, 0.14)
	player.fatigue_sway_deg = Vector2(1.4, 0.9)
	player.stamina = 1.0
	player._update_stamina(0.0)
	var rested := player.sway_amplitude()
	player.stamina = 0.0
	player._update_stamina(0.0)
	var tired := player.sway_amplitude()
	player._since_sprint = 99.0
	player._update_stamina(1.0)
	_check(tired.x > rested.x * 5.0 and player.stamina > 0.0, "stamina: empty = big aim wobble; it recovers after a rest")
	player.stamina = 1.0
	player._update_stamina(0.0)
	player.breath_sway_deg = bs
	player.fatigue_sway_deg = fs
	# Night vision: pick up, flip down (gun lowers, hands, tubes on, world amplified), IR laser only through it.
	var nv := player.get_node("ViewmodelLayer/NightVision") as NightVision
	var pickup := level.get_node("NVGPickup") as NVGPickup
	var no_nvg := not nv.toggle()
	pickup.interact(player)
	var flipped := nv.toggle()
	nv._process(nv.lower_time * 0.5)
	var gun_down := player.weapons.gear_lower > 0.0 and not player.weapons.can_fire()
	for i in 20:
		nv._process(0.06)
	var amplified := nv.on and player.camera.attributes != null and player.camera.attributes.exposure_multiplier > 1.0
	var w2 := player.weapons.current
	var wl := player.get_node("ViewmodelLayer/WeaponLights")
	var mode_was := w2.laser_mode
	w2.laser_mode = 2
	wl._process(0.016)
	var ir_seen: bool = wl.dot_visible or not w2.data.laser
	nv.toggle()
	for i in 20:
		nv._process(0.06)
	wl._process(0.016)
	var ir_hidden: bool = not wl.dot_visible
	w2.laser_mode = mode_was
	_check(no_nvg and not pickup.visible and flipped and gun_down and amplified and not nv.on and player.weapons.gear_lower == 0.0,
		"night vision: needs the pickup, flips down with the gun lowered, amplifies, flips back up")
	_check(ir_seen and ir_hidden, "IR laser only shows through night vision")
	pickup.reset()
	nv.reset()
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
