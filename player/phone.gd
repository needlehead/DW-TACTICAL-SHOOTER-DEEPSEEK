class_name Phone
extends TextureRect
## Diegetic status device: Tab and Kei lowers the gun and raises it (WeaponManager.phone_open / phone_blend).
## The screen is drawn into a SubViewport and mapped onto the phone's screen quad in the frame, so it
## sways and gets the bodycam lens with everything else. Read-only pages, flipped with Q/E or the wheel:
## Status, Objective, Run, Gear. Fields for systems the game doesn't have yet show a dim dash.

const PAGES := ["STATUS", "OBJECTIVE", "RUN", "GEAR"]

@export var frame: Texture2D
## Screen corners on the frame (0-1 UV): top-left, top-right, bottom-right, bottom-left.
@export var screen_quad := PackedVector2Array([Vector2(0.3898, 0.3778), Vector2(0.6195, 0.3826), Vector2(0.6223, 0.6674), Vector2(0.382, 0.6604)])
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
@export var map_scale := 8.0  ## Objective map: pixels per metre
@export var flip_time := 0.2  ## page change: the new page slides in from the flip side and fades up
@export var flip_slide := 80.0  ## pixels the new page travels
## Thumb press on a page change: the tablet dips and tips toward the pressing side (Q left, E right), then springs back.
@export var press_dip := 0.012  ## screen heights
@export var press_tilt := 0.025  ## radians

const BG := Color(0.04, 0.07, 0.13)
const DIM := Color(0.55, 0.65, 0.8)
const TEXT := Color(0.92, 0.95, 1.0)

var _vp := SubViewport.new()
var _screen := Control.new()
var _poly := Polygon2D.new()
var _outfit: AtlasTexture
var _run_start := 0.0  ## Run page clock; restarts on level reset
var _page := 0  ## page being drawn (follows manager.phone_page)
var _from_page := 0
var _flip := 1.0  ## 0..1 through the page change
var _flip_dir := 1

@onready var player: Player = owner
@onready var manager: WeaponManager = owner.get_node("LeanPivot/Head/Camera3D/Viewmodel/Weapons")
@onready var portrait: Node = owner.get_node("HUDLayer/Portrait")
@onready var hands = owner.get_node("ViewmodelLayer/SpriteViewmodel")  # shares the gun's sway/bob


func _ready() -> void:
	add_to_group("resettable")
	reset()
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


func reset() -> void:
	_run_start = Time.get_ticks_msec() / 1000.0


func _process(delta: float) -> void:
	var t := manager.phone_raise()
	visible = t > 0.0 and player.alive and frame != null
	if manager.phone_page != _page:
		_flip_dir = 1 if manager.phone_page == (_page + 1) % PAGES.size() else -1
		_from_page = _page
		_page = manager.phone_page
		_flip = 0.0 if visible else 1.0  # reset to Status while put away: no animation
	_flip = minf(_flip + delta / maxf(flip_time, 0.01), 1.0)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if visible else SubViewport.UPDATE_DISABLED
	var lens := (owner.get_node("PostFXLayer/Bodycam") as ColorRect).material as ShaderMaterial
	lens.set_shader_parameter("tablet_on", visible)
	if not visible:
		return
	var vp := get_viewport_rect().size
	size = vp * (1.0 + overscan)
	var e := 1.0 - pow(1.0 - t, 3.0)  # ease out: quick lift, gentle settle
	var sway: Vector2 = hands.hand_offset(vp.y, false) * sway_amount
	var press := sin(PI * _flip)  # 0 -> 1 -> 0 over the page change
	position = Vector2(-vp.x * overscan * 0.5, 0.0) + layout.hold_offset * vp.y + sway + Vector2(0.0, ((1.0 - e) * raise_drop + press * press_dip) * vp.y)
	pivot_offset = Vector2(size.x * 0.5, size.y)  # held in both hands: scale and tilt around the bottom centre
	scale = Vector2.ONE * layout.hold_scale
	rotation = sway.x / vp.y * sway_tilt + _flip_dir * press * press_tilt
	var pts := PackedVector2Array()
	for uv in screen_quad:
		pts.append(uv * size)
	_poly.polygon = pts
	(_poly.material as ShaderMaterial).set_shader_parameter("undo_tint", (owner.get_node("ViewmodelLayer/SpriteShadow") as SpriteShadow).undo_tint())
	_screen.queue_redraw()
	# Tell the bodycam where the tablet is, so it leaves its colour fringing off it.
	var inv := get_global_transform().affine_inverse()
	lens.set_shader_parameter("tablet_tex", frame)
	lens.set_shader_parameter("tablet_x", inv.x)
	lens.set_shader_parameter("tablet_y", inv.y)
	lens.set_shader_parameter("tablet_o", inv.origin)
	lens.set_shader_parameter("tablet_size", size)
	lens.set_shader_parameter("view_size", vp)


func _draw_screen() -> void:
	var s := Vector2(screen_size)
	var font := ThemeDB.fallback_font
	_screen.draw_rect(Rect2(Vector2.ZERO, s), BG)
	# Page first, so the header covers it while it slides; ease-out, then fade up from the background.
	var e := 1.0 - pow(1.0 - _flip, 3.0)
	_screen.draw_set_transform(Vector2(_flip_dir * (1.0 - e) * flip_slide, 0.0))
	[_draw_status, _draw_objective, _draw_run, _draw_gear][_page].call()
	_screen.draw_set_transform(Vector2.ZERO)
	if e < 1.0:
		_screen.draw_rect(Rect2(0, 44, s.x, s.y - 44), Color(BG, 1.0 - e))
	_screen.draw_rect(Rect2(0, 0, s.x, 44), Color(0.08, 0.13, 0.24))
	_screen.draw_string(font, Vector2(16, 31), heroine_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, TEXT)
	_screen.draw_string(font, Vector2(0, 31), Time.get_time_string_from_system().left(5), HORIZONTAL_ALIGNMENT_RIGHT, s.x - 16, 24, DIM)
	# Page tabs: the highlight slides from the old tab to the new one; Q/E hints at the ends.
	var x := 236.0
	var tabs: Array[Rect2] = []
	for i in PAGES.size():
		var wpx := font.get_string_size(PAGES[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		tabs.append(Rect2(x - 6, 8, wpx + 12, 28))
		x += wpx + 18.0
	var a := tabs[_from_page]
	var b := tabs[_page]
	_screen.draw_rect(Rect2(a.position.lerp(b.position, e), a.size.lerp(b.size, e)), Color(0.2, 0.35, 0.6))
	_screen.draw_string(font, Vector2(236.0 - 26.0, 29), "Q", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, DIM)
	for i in PAGES.size():
		_screen.draw_string(font, tabs[i].position + Vector2(6, 20), PAGES[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, TEXT if i == _page else DIM)
	_screen.draw_string(font, Vector2(x - 4, 29), "E", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, DIM)


func _draw_status() -> void:
	var s := Vector2(screen_size)
	var font := ThemeDB.fallback_font
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


## Objective: heading-up map of the targets around Kei (she's the arrow, up is where she faces).
func _draw_objective() -> void:
	var font := ThemeDB.fallback_font
	var box := Rect2(16, 56, 330, 428)
	_screen.draw_rect(box, Color(0, 0, 0, 0.35))
	var me := box.position + Vector2(box.size.x * 0.5, box.size.y * 0.7)
	for r in [10.0, 20.0]:
		_screen.draw_arc(me, r * map_scale, 0.0, TAU, 48, Color(DIM, 0.25), 1.0)
	var fwd := -player.global_basis.z
	var right := player.global_basis.x
	var targets := dummies()
	var down := 0
	for d in targets:
		var rel := d.global_position - player.global_position
		var p := me + Vector2(rel.dot(right), -rel.dot(fwd)) * map_scale
		if d.health.dead:
			down += 1
		if not box.grow(-6).has_point(p):
			continue
		if d.health.dead:
			_screen.draw_line(p - Vector2(5, 5), p + Vector2(5, 5), DIM, 2.0)
			_screen.draw_line(p - Vector2(5, -5), p + Vector2(5, -5), DIM, 2.0)
		else:
			_screen.draw_circle(p, 5.0, Color(1.0, 0.3, 0.25))
	_screen.draw_colored_polygon(PackedVector2Array([me + Vector2(0, -10), me + Vector2(7, 8), me + Vector2(-7, 8)]), Color(0.3, 0.95, 0.45))

	var col := 362.0
	_field(col, 80, "OBJECTIVE", "CLEAR THE KILLHOUSE")
	_screen.draw_string(font, Vector2(col, 158), "TARGETS DOWN", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, DIM)
	_screen.draw_string(font, Vector2(col, 158), "%d / %d" % [down, targets.size()], HORIZONTAL_ALIGNMENT_RIGHT, 342, 18, TEXT)
	_bar(Rect2(col, 168, 342, 12), float(down) / maxf(targets.size(), 1))
	_field(col, 230, "CAPTURE", null)
	_field(col, 308, "CACHES LEFT", null)
	_field(col, 386, "CHECKPOINT", null)


## Run: money, what's carried, how long this run has gone, how hot it is.
func _draw_run() -> void:
	var e := int(Time.get_ticks_msec() / 1000.0 - _run_start)
	_field(16, 80, "ELAPSED", "%02d:%02d" % [e / 60, e % 60], 40)
	_field(16, 190, "CREDITS", null)
	_field(16, 268, "THREAT", null)
	_field(362, 80, "CARRIED", null)


## Gear: both guns, grenades, outfit.
func _draw_gear() -> void:
	var y := 80.0
	for w in manager.weapons:
		var modes := PackedStringArray()
		for m in w.data.modes():
			modes.append(WeaponData.mode_name(m))
		var title := ("> " if w == manager.current else "") + w.data.display_name
		_field(16, y, title, "%s  |  %d spare mags" % ["/".join(modes), w.spare.size()])
		y += 78.0
	_field(16, y, "AMMO TYPE", null)
	_field(16, y + 78.0, "GRENADES", "FRAG x%d" % manager.grenades)
	if _outfit:
		_fit(_outfit, Rect2(478, 56, 226, 360))
	_field(478, 440, "OUTFIT", outfit_name)


## Every Dummy in the level.
func dummies() -> Array[Dummy]:
	var out: Array[Dummy] = []
	for n in get_tree().get_nodes_in_group("resettable"):
		if n is Dummy:
			out.append(n)
	return out


## Label over a value; null = the system isn't in the game yet (dim dash).
func _field(x: float, y: float, label: String, value: Variant, px := 24) -> void:
	var font := ThemeDB.fallback_font
	_screen.draw_string(font, Vector2(x, y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, DIM)
	var text: String = "-" if value == null else str(value)
	_screen.draw_string(font, Vector2(x, y + 30 + px - 24), text, HORIZONTAL_ALIGNMENT_LEFT, screen_size.x - x - 16, px, Color(DIM, 0.5) if value == null else TEXT)


func _bar(box: Rect2, f: float) -> void:
	_screen.draw_rect(box, Color(0, 0, 0, 0.4))
	_screen.draw_rect(Rect2(box.position, Vector2(box.size.x * clampf(f, 0.0, 1.0), box.size.y)), Color(0.3, 0.95, 0.45))


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
