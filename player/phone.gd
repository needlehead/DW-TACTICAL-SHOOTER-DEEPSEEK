extends TextureRect
## Diegetic status phone: hold Tab and Kei lowers the gun and raises a phone (WeaponManager.phone_blend).
## The screen is drawn into a SubViewport and mapped onto the phone's screen quad in the frame, so it
## sways and gets the bodycam lens with everything else. Read-only: name, outfit, vitals, weapon, mags.

@export var frame: Texture2D
## Screen corners on the frame (0-1 UV): top-left, top-right, bottom-right, bottom-left.
@export var screen_quad := PackedVector2Array([Vector2(0.3813, 0.474), Vector2(0.5229, 0.4556), Vector2(0.5318, 0.6208), Vector2(0.3896, 0.6535)])
@export var raise_drop := 0.8  ## screen heights below the bottom edge when put away
@export var sway_amount := 1.0  ## 1 = moves exactly like the gun (sway, walk bob, inertia)
@export var sway_tilt := 0.6  ## radians of tilt per screen height of sideways sway
@export var overscan := 0.06  ## extra size so sway never shows the frame's cut-off edges
## Hold position and size (scaled around the arm's exit corner, which stays off-screen); F4 -> Tablet edits it.
@export var layout: PhoneLayout = preload("res://player/phone_layout.tres")
@export var heroine_name := "KEI FUJIWARA"
@export var outfit_name := "HEAVY METAL"
@export var outfit_sprite: Texture2D
@export var screen_size := Vector2i(720, 500)

const BG := Color(0.04, 0.07, 0.13)
const DIM := Color(0.55, 0.65, 0.8)
const TEXT := Color(0.92, 0.95, 1.0)

var _vp := SubViewport.new()
var _screen := Control.new()
var _poly := Polygon2D.new()
var _outfit: AtlasTexture

@onready var player: Player = owner
@onready var manager: WeaponManager = owner.get_node("LeanPivot/Head/Camera3D/Viewmodel/Weapons")
@onready var portrait: Node = owner.get_node("HUDLayer/Portrait")
@onready var hands = owner.get_node("ViewmodelLayer/SpriteViewmodel")  # shares the gun's sway/bob


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	texture = frame
	_vp.size = screen_size
	_vp.disable_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_screen.size = screen_size
	_screen.draw.connect(_draw_screen)
	_vp.add_child(_screen)
	add_child(_vp)
	_poly.texture = _vp.get_texture()
	_poly.uv = PackedVector2Array([Vector2.ZERO, Vector2(screen_size.x, 0), Vector2(screen_size), Vector2(0, screen_size.y)])
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://player/unshaded.gdshader")  # the screen is backlit: it never darkens in shade or the dark
	_poly.material = mat
	add_child(_poly)
	if outfit_sprite:
		_outfit = AtlasTexture.new()
		_outfit.atlas = outfit_sprite
		_outfit.region = Rect2(outfit_sprite.get_image().get_used_rect())


func _process(_delta: float) -> void:
	var t := manager.phone_raise()
	visible = t > 0.0 and player.alive and frame != null
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if visible else SubViewport.UPDATE_DISABLED
	if not visible:
		return
	var vp := get_viewport_rect().size
	size = vp * (1.0 + overscan)
	var e := 1.0 - pow(1.0 - t, 3.0)  # ease out: quick lift, gentle settle
	var sway: Vector2 = hands.hand_offset(vp.y, false) * sway_amount
	position = Vector2(-vp.x * overscan * 0.5, 0.0) + layout.hold_offset * vp.y + sway + Vector2(0.0, (1.0 - e) * raise_drop * vp.y)
	pivot_offset = Vector2(0.0, size.y)  # arm's exit corner stays put under scale and tilt
	scale = Vector2.ONE * layout.hold_scale
	rotation = sway.x / vp.y * sway_tilt
	var pts := PackedVector2Array()
	for uv in screen_quad:
		pts.append(uv * size)
	_poly.polygon = pts
	(_poly.material as ShaderMaterial).set_shader_parameter("undo_tint", (owner.get_node("ViewmodelLayer/SpriteShadow") as SpriteShadow).undo_tint())
	_screen.queue_redraw()


func _draw_screen() -> void:
	var s := Vector2(screen_size)
	var font := ThemeDB.fallback_font
	_screen.draw_rect(Rect2(Vector2.ZERO, s), BG)
	_screen.draw_rect(Rect2(0, 0, s.x, 44), Color(0.08, 0.13, 0.24))
	_screen.draw_string(font, Vector2(16, 31), heroine_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, TEXT)
	_screen.draw_string(font, Vector2(0, 31), Time.get_time_string_from_system().left(5), HORIZONTAL_ALIGNMENT_RIGHT, s.x - 16, 24, DIM)

	# Condition: health face, status word and a sweeping heart monitor (faster and redder as health drops).
	var h := player.health
	var f := clampf(h.current / h.max_health, 0.0, 1.0)
	var face: Texture2D = portrait.face()
	if face:
		_fit(face, Rect2(16, 56, 200, 290))
	var tier := 0 if f > 0.66 else 1 if f > 0.33 else 2
	var col: Color = [Color(0.3, 0.95, 0.45), Color(1.0, 0.8, 0.2), Color(1.0, 0.25, 0.2)][tier]
	var now := Time.get_ticks_msec() / 1000.0
	_screen.draw_string(font, Vector2(16, 368), "CONDITION", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, DIM)
	if tier < 2 or fmod(now, 0.8) < 0.55:  # DANGER blinks
		_screen.draw_string(font, Vector2(16, 398), ["FINE", "CAUTION", "DANGER"][tier], HORIZONTAL_ALIGNMENT_LEFT, -1, 28, col)
	_draw_ecg(Rect2(16, 408, 200, 70), col, [70.0, 100.0, 140.0][tier], now)

	# Outfit.
	if _outfit:
		_fit(_outfit, Rect2(232, 56, 230, 360))
	_screen.draw_string(font, Vector2(232, 440), "OUTFIT", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, DIM)
	_screen.draw_string(font, Vector2(232, 470), outfit_name, HORIZONTAL_ALIGNMENT_LEFT, 230, 24, TEXT)

	# Loadout.
	var w := player.weapons.current
	var rows := [
		["WEAPON", w.data.display_name],
		["MODE", WeaponData.mode_name(w.mode)],
		["MAG", w.mag_estimate()],
		["SPARE MAGS", str(w.spare.size())],
		["FRAGS", str(player.weapons.grenades)],
	]
	var y := 80.0
	for r: Array in rows:
		_screen.draw_string(font, Vector2(478, y), r[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, DIM)
		_screen.draw_string(font, Vector2(478, y + 30), r[1], HORIZONTAL_ALIGNMENT_LEFT, s.x - 494, 24, TEXT)
		y += 78.0


## Heart monitor: the trace is drawn by a sweeping head and fades out behind it over one sweep.
func _draw_ecg(box: Rect2, col: Color, bpm: float, now: float) -> void:
	_screen.draw_rect(box, Color(0, 0, 0, 0.35))
	const SWEEP := 1.6  # seconds per pass across the box
	const N := 90
	var head := fmod(now, SWEEP) / SWEEP  # 0..1 across the box
	var prev := Vector2.ZERO
	for i in N + 1:
		var x := float(i) / N
		var age := fposmod(head - x, 1.0)  # 0 at the head, 1 a full sweep ago
		var t := now - age * SWEEP
		var p := Vector2(box.position.x + x * box.size.x, box.get_center().y - ecg(fmod(t * bpm / 60.0, 1.0)) * box.size.y * 0.42)
		if i > 0 and age < 0.98 and fposmod(head - (float(i - 1) / N), 1.0) > age:  # don't join across the head
			_screen.draw_line(prev, p, Color(col, 1.0 - age), 2.0, true)
		prev = p
	_screen.draw_circle(Vector2(box.position.x + head * box.size.x, box.get_center().y - ecg(fmod(now * bpm / 60.0, 1.0)) * box.size.y * 0.42), 3.0, col)


## One heartbeat (P wave, QRS spike, T wave) over phase 0..1; returns -0.4..1 (up = positive).
static func ecg(phase: float) -> float:
	if phase < 0.08:
		return 0.12 * sin(phase / 0.08 * PI)
	if phase < 0.14:
		return 0.0
	if phase < 0.17:
		return lerpf(0.0, -0.2, (phase - 0.14) / 0.03)
	if phase < 0.20:
		return lerpf(-0.2, 1.0, (phase - 0.17) / 0.03)
	if phase < 0.24:
		return lerpf(1.0, -0.4, (phase - 0.20) / 0.04)
	if phase < 0.28:
		return lerpf(-0.4, 0.0, (phase - 0.24) / 0.04)
	if phase > 0.42 and phase < 0.58:
		return 0.25 * sin((phase - 0.42) / 0.16 * PI)
	return 0.0


## Draw a texture as large as fits in the box, keeping aspect, centred.
func _fit(tex: Texture2D, box: Rect2) -> void:
	var ts := Vector2(tex.get_size())
	var k := minf(box.size.x / ts.x, box.size.y / ts.y)
	_screen.draw_texture_rect(tex, Rect2(box.position + (box.size - ts * k) * 0.5, ts * k), false)
