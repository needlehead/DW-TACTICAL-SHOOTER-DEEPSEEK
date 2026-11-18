extends PanelContainer
## F1 debug panel: live stats plus sliders that edit the active WeaponData (and a few player
## values) while the game runs. "Save .tres" writes the weapon's current values to disk.

## [property, min, max, step] on the active WeaponData.
const WEAPON_TUNABLES := [
	["damage", 5.0, 150.0, 1.0],
	["rpm", 60.0, 1200.0, 10.0],
	["camera_recoil", 0.0, 3.0, 0.05],
	["recoil_recovery", 0.0, 30.0, 0.5],
	["hip_spread", 0.0, 10.0, 0.1],
	["ads_spread", 0.0, 3.0, 0.05],
	["move_spread", 0.0, 6.0, 0.1],
	["spread_per_shot", 0.0, 2.0, 0.05],
	["ads_time", 0.05, 1.0, 0.01],
	["reload_time", 0.3, 6.0, 0.05],
	["empty_reload_time", 0.3, 6.0, 0.05],
	["speed_reload_time", 0.3, 6.0, 0.05],
	["vm_kick_back", 0.0, 0.15, 0.005],
	["vm_kick_rot", 0.0, 15.0, 0.25],
]
const PLAYER_TUNABLES := [
	["deadzone_deg", 0.0, 10.0, 0.25],
	["mouse_sensitivity", 0.01, 0.3, 0.005],
	["ground_accel", 2.0, 30.0, 0.5],
]

var _stats: Label
var _rows := {}  # property -> [HSlider, Label, target_is_player]
var _bound: WeaponData

@onready var player: Player = owner


func _ready() -> void:
	visible = false
	position = Vector2(12, 12)
	var box := VBoxContainer.new()
	add_child(box)
	_stats = Label.new()
	box.add_child(_stats)
	for t: Array in WEAPON_TUNABLES:
		_add_row(box, t, false)
	box.add_child(HSeparator.new())
	for t: Array in PLAYER_TUNABLES:
		_add_row(box, t, true)
	var save := Button.new()
	save.text = "Save weapon .tres"
	save.focus_mode = Control.FOCUS_NONE
	save.pressed.connect(_save)
	box.add_child(save)


func _add_row(box: VBoxContainer, t: Array, on_player: bool) -> void:
	var row := HBoxContainer.new()
	var name_label := Label.new()
	name_label.text = t[0]
	name_label.custom_minimum_size.x = 150
	var slider := HSlider.new()
	slider.min_value = t[1]
	slider.max_value = t[2]
	slider.step = t[3]
	slider.custom_minimum_size.x = 180
	slider.focus_mode = Control.FOCUS_NONE
	var value := Label.new()
	value.custom_minimum_size.x = 60
	slider.value_changed.connect(_on_slider.bind(t[0], on_player))
	row.add_child(name_label)
	row.add_child(slider)
	row.add_child(value)
	box.add_child(row)
	_rows[t[0]] = [slider, value, on_player]


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_panel"):
		visible = not visible
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if visible else Input.MOUSE_MODE_CAPTURED
		_bind()


func _bind() -> void:
	_bound = player.weapons.current.data
	for prop: String in _rows:
		var r: Array = _rows[prop]
		var src: Object = player if r[2] else _bound
		(r[0] as HSlider).set_value_no_signal(src.get(prop))
		(r[1] as Label).text = str(snappedf(src.get(prop), 0.001))


func _on_slider(v: float, prop: String, on_player: bool) -> void:
	(player if on_player else _bound).set(prop, v)
	(_rows[prop][1] as Label).text = str(snappedf(v, 0.001))


func _save() -> void:
	var err := ResourceSaver.save(_bound)
	Game.toast("Saved %s: %s" % [_bound.resource_path, error_string(err)])


func _process(_delta: float) -> void:
	if not visible:
		return
	var w := player.weapons.current
	if w.data != _bound:
		_bind()
	var stance_name: String = Player.Stance.keys()[player.stance]
	_stats.text = "\n".join([
		"%s  |  %s  |  %s" % [w.data.display_name, WeaponData.mode_name(w.mode), "RELOADING %.1fs" % w.reload_left if w.is_reloading() else "ready"],
		"mag %d%s   spares %s   frags %d" % [w.mag, " +1" if w.chambered else "", str(w.spare), player.weapons.grenades],
		"recoil (%.2f, %.2f) deg   shot #%d" % [player.recoil.x, player.recoil.y, w.shot_index],
		"spread %.2f deg   bloom %.2f" % [w.current_spread(), w.bloom],
		"%s   speed %.2f m/s   ADS %d%%   lean %.2f" % [stance_name, player.horizontal_speed(), roundi(player.ads_blend * 100.0), player.lean],
		"last hit: %s" % Game.last_hit,
		"last TTK: %s" % Game.last_ttk,
		"FPS %d" % Engine.get_frames_per_second(),
	])
