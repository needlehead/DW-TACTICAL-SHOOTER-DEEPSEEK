class_name Phone
extends TextureRect
## Diegetic status device: Tab and Kei lowers the gun and raises it (WeaponManager.phone_open / phone_blend).
## The screen is drawn into a SubViewport and mapped onto the phone's screen quad in the frame, so it
## sways and gets the bodycam lens with everything else. Read-only pages, flipped with Q/E or the wheel:
## Status, Objective, Run, Gear. Fields for systems the game doesn't have yet show a dim dash.
## Layout, fonts and the heroine-colour palette follow the design mockup in docs/ui_mockup.

const PAGES := ["STATUS", "OBJECTIVE", "RUN", "GEAR"]
const HEADER_H := 48.0
const ENEMY := Color("#FF5A4E")
const CAUTION := Color(1.0, 0.8, 0.2)
const DANGER := Color(1.0, 0.3, 0.25)

@export var frame: Texture2D
## Screen corners on the frame (0-1 UV): top-left, top-right, bottom-right, bottom-left.
@export var screen_quad := PackedVector2Array([Vector2(0.3898, 0.3778), Vector2(0.6195, 0.3826), Vector2(0.6223, 0.6674), Vector2(0.382, 0.6604)])
@export var raise_drop := 0.8  ## screen heights below the bottom edge when put away
@export var sway_amount := 1.0  ## 1 = moves exactly like the gun (sway, walk bob, inertia)
@export var sway_tilt := 0.6  ## radians of tilt per screen height of sideways sway
@export var overscan := 0.06  ## extra size so sway never shows the frame's cut-off edges
## Hold position and size (scaled around the bottom centre); F4 -> Tablet edits it.
@export var layout: PhoneLayout = preload("res://player/phone_layout.tres")
@export var heroine_name := "KEI FUJIWARA"
## The heroine's colour: the whole screen's palette (background, header, tab, labels, accents) is derived from it.
@export var heroine_color := Color("#529364")
@export var outfit_name := "HEAVY METAL"
@export var outfit_sprite: Texture2D  ## front and back views side by side; Gear shows one, R turns it
@export_range(0.0, 1.0) var outfit_split := 0.51  ## where the front view ends and the back begins (0-1 across)
@export var outfit_turn_time := 0.3
@export var screen_size := Vector2i(720, 500)
@export var map_scale := 8.0  ## Objective map: pixels per metre
@export var flip_time := 0.2  ## page change: the new page slides in from the flip side and fades up
@export var flip_slide := 80.0  ## pixels the new page travels
## Thumb press on a page change: the tablet dips and tips toward the pressing side (Q left, E right), then springs back.
@export var press_dip := 0.012  ## screen heights
@export var press_tilt := 0.025  ## radians

var c := {}  ## palette, from theme(heroine_color)
var _vp := SubViewport.new()
var _screen := Control.new()
var _poly := Polygon2D.new()
var _outfit_front: AtlasTexture
var _outfit_back: AtlasTexture
var _back := false  ## Gear: showing the outfit's back
var _turn := 1.0  ## 0..1 through the outfit turn
var _run_start := 0.0  ## Run page clock; restarts on level reset
var _page := 0  ## page being drawn (follows manager.phone_page)
var _from_page := 0
var _flip := 1.0  ## 0..1 through the page change
var _flip_dir := 1
# Barlow, as in the design: condensed for labels, tabs and titles, regular width for values.
var _f_label := _font("res://fonts/BarlowCondensed-SemiBold.ttf", 2)
var _f_tab := _font("res://fonts/BarlowCondensed-SemiBold.ttf", 1)
var _f_title := _font("res://fonts/BarlowCondensed-Bold.ttf", 1)
var _f_value := _font("res://fonts/Barlow-SemiBold.ttf", 0)
var _f_soft := _font("res://fonts/Barlow-Medium.ttf", 0)

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
	_poly.antialiased = true  # smooth screen edges as the tablet sways and tilts
	add_child(_poly)
	c = theme(heroine_color)
	if outfit_sprite:
		var img := outfit_sprite.get_image()
		var split := int(img.get_width() * outfit_split)
		_outfit_front = _crop(img, Rect2i(0, 0, split, img.get_height()))
		_outfit_back = _crop(img, Rect2i(split, 0, img.get_width() - split, img.get_height()))


func _crop(img: Image, area: Rect2i) -> AtlasTexture:
	var a := AtlasTexture.new()
	a.atlas = outfit_sprite
	var used := img.get_region(area).get_used_rect()
	a.region = Rect2(used.position + area.position, used.size)
	return a


static func _font(path: String, spacing: int) -> FontVariation:
	var f := FontVariation.new()
	f.base_font = load(path)
	f.spacing_glyph = spacing
	return f


## The screen's palette from one heroine colour (same recipe as the design mockup).
static func theme(main: Color) -> Dictionary:
	var ground := main.lerp(Color.BLACK, 0.87)
	var dim := main.lerp(Color.WHITE, 0.55)
	return {
		"main": main, "ground": ground, "header": main.lerp(Color.BLACK, 0.76), "panel": main.lerp(Color.BLACK, 0.8),
		"text": main.lerp(Color.WHITE, 0.92), "soft": main.lerp(Color.WHITE, 0.72), "dim": dim, "dash": dim.lerp(ground, 0.35),
		"accent": main.lerp(Color.WHITE, 0.25),
		"on_main": main.lerp(Color.BLACK, 0.9) if main.srgb_to_linear().get_luminance() > 0.18 else Color.WHITE,
		"card": Color(main, 0.24), "card2": Color(main, 0.08), "line": Color(main, 0.35),
	}


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
	if visible and manager.phone_open and _page == 3 and Input.is_action_just_pressed("reload"):  # R turns the outfit
		_back = not _back
		_turn = 0.0
		manager.click()
	elif not visible:
		_back = false  # opens on the front again
	_turn = minf(_turn + delta / maxf(outfit_turn_time, 0.01), 1.0)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if visible else SubViewport.UPDATE_DISABLED
	var lens := (owner.get_node("PostFXLayer/Bodycam") as ColorRect).material as ShaderMaterial
	lens.set_shader_parameter("tablet_on", visible)
	if not visible:
		return
	var vp := get_viewport_rect().size
	size = vp * (1.0 + overscan)
	var e := 1.0 - pow(1.0 - t, 3.0)  # ease out: quick lift, gentle settle
	var sway: Vector2 = hands.hand_offset(vp.y, false, false) * sway_amount
	var press := sin(PI * _flip)  # 0 -> 1 -> 0 over the page change
	position = Vector2(-vp.x * overscan * 0.5, 0.0) + layout.hold_offset * vp.y + sway + Vector2(0.0, ((1.0 - e) * raise_drop + press * press_dip) * vp.y)
	pivot_offset = Vector2(size.x * 0.5, size.y)  # held in both hands: scale and tilt around the bottom centre
	scale = Vector2.ONE * layout.hold_scale
	rotation = sway.x / vp.y * sway_tilt + _flip_dir * press * press_tilt
	var pts := PackedVector2Array()
	for uv in screen_quad:
		pts.append(uv * size)
	_poly.polygon = pts
	_match_resolution(pts)
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


## Render the screen at about the size it appears, so text and lines stay sharp instead of being shrunk from
## 720x500 without mipmaps (which skips pixels and looks jagged). The pages still lay out in screen_size units.
func _match_resolution(pts: PackedVector2Array) -> void:
	var px := get_screen_transform().get_scale()
	var shown := Vector2(pts[0].distance_to(pts[1]) * px.x, pts[0].distance_to(pts[3]) * px.y)
	var k := clampf(maxf(shown.x / screen_size.x, shown.y / screen_size.y), 0.25, 2.0)
	if absf(k - _screen.scale.x) < 0.04 * _screen.scale.x:  # sway changes it a little every frame; resize on real changes
		return
	var res := Vector2i((Vector2(screen_size) * k).ceil())
	_vp.size = res
	_screen.scale = Vector2(k, k)
	_poly.uv = PackedVector2Array([Vector2.ZERO, Vector2(res.x, 0), Vector2(res), Vector2(0, res.y)])


func _draw_screen() -> void:
	var s := Vector2(screen_size)
	_screen.draw_rect(Rect2(Vector2.ZERO, s), c.ground)
	# Page first, so the header covers it while it slides; ease-out, then fade up from the background.
	var e := 1.0 - pow(1.0 - _flip, 3.0)
	_screen.draw_set_transform(Vector2(_flip_dir * (1.0 - e) * flip_slide, 0.0))
	[_draw_status, _draw_objective, _draw_run, _draw_gear][_page].call()
	_screen.draw_set_transform(Vector2.ZERO)
	if e < 1.0:
		_screen.draw_rect(Rect2(0, HEADER_H, s.x, s.y - HEADER_H), Color(c.ground, 1.0 - e))
	# Header: name, page tabs (the highlight slides from the old tab to the new one, Q/E at the ends), clock.
	_screen.draw_rect(Rect2(0, 0, s.x, HEADER_H), c.header)
	var mid := HEADER_H * 0.5
	_mid(16, mid, heroine_name, _f_title, 22, c.text)
	_mid(0, mid, Time.get_time_string_from_system().left(5), _f_tab, 22, c.dim, s.x - 16, HORIZONTAL_ALIGNMENT_RIGHT)
	var x := 200.0
	_mid(x, mid, "Q", _f_tab, 13, c.dim)
	x += _w("Q", _f_tab, 13) + 10.0
	var tabs: Array[Rect2] = []
	for i in PAGES.size():
		var tw := _w(PAGES[i], _f_tab, 16) + 18.0
		tabs.append(Rect2(x, mid - 13, tw, 26))
		x += tw + 4.0
	var a := tabs[_from_page]
	var b := tabs[_page]
	_screen.draw_rect(Rect2(a.position.lerp(b.position, e), a.size.lerp(b.size, e)), c.main)
	for i in PAGES.size():
		_mid(tabs[i].position.x + 9, mid, PAGES[i], _f_tab, 16, c.on_main if i == _page else c.dim)
	_mid(x + 6, mid, "E", _f_tab, 13, c.dim)


## Status: face, condition and heart monitor on the left; the weapon and ammo as tiles filling the right.
func _draw_status() -> void:
	var h := player.health
	var f := clampf(h.current / h.max_health, 0.0, 1.0)
	var tier := 0 if f > 0.66 else 1 if f > 0.33 else 2
	var col: Color = [c.accent, CAUTION, DANGER][tier]  # the condition keeps its warning colours for every heroine
	var now := Time.get_ticks_msec() / 1000.0
	var row := 378.0  # condition line, between the face and the monitor
	var face_box := Rect2(16, 62, 250, row - 10 - 62)
	_screen.draw_rect(face_box, c.panel)
	var face: Texture2D = portrait.face()
	if face:
		_cover_top(face, face_box)
	var base := row + _f_title.get_ascent(32)
	_screen.draw_string(_f_label, Vector2(16, base), "CONDITION", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, c.dim)
	if tier < 2 or fmod(now, 0.8) < 0.55:  # DANGER blinks
		_screen.draw_string(_f_title, Vector2(16, base), ["FINE", "CAUTION", "DANGER"][tier], HORIZONTAL_ALIGNMENT_RIGHT, 250, 32, col)
	_draw_ecg(Rect2(16, 420, 250, 64), col, [70.0, 100.0, 140.0][tier], now)

	var w := player.weapons.current
	var cw := (422.0 - 8.0) / 2.0
	var rh := (422.0 - 16.0) / 3.0
	_tile(Rect2(282, 62, 422, rh), "WEAPON", w.data.display_name.to_upper(), _f_title, 34, c.card)
	var cells := [["MODE", WeaponData.mode_name(w.mode)], ["MAG", w.mag_estimate()],
		["SPARE MAGS", str(w.spare.size())], ["FRAGS", str(manager.grenades)]]
	for i in cells.size():
		var r := Rect2(282 + (i % 2) * (cw + 8.0), 62 + (1 + i / 2) * (rh + 8.0), cw, rh)
		_tile(r, cells[i][0], cells[i][1], _f_value, 30, c.card2)


## Objective: heading-up map of the targets around Kei (she's the arrow, up is where she faces).
func _draw_objective() -> void:
	var box := Rect2(16, 64, 330, 420)
	_screen.draw_rect(box, Color(0, 0, 0, 0.35))
	var me := box.position + Vector2(box.size.x * 0.5, box.size.y * 0.7)
	for r in [10.0, 20.0]:
		_screen.draw_arc(me, r * map_scale, 0.0, TAU, 48, Color(c.dim, 0.25), 1.0)
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
			_screen.draw_line(p - Vector2(5, 5), p + Vector2(5, 5), c.dim, 2.0)
			_screen.draw_line(p - Vector2(5, -5), p + Vector2(5, -5), c.dim, 2.0)
		else:
			_screen.draw_circle(p, 5.0, ENEMY)
	_screen.draw_colored_polygon(PackedVector2Array([me + Vector2(0, -12), me + Vector2(8, 8), me + Vector2(-8, 8)]), c.accent)

	var x := 362.0
	_t(x, 64, "OBJECTIVE", _f_label, 15, c.dim)
	_t(x, 82, "CLEAR THE KILLHOUSE", _f_title, 28, c.text)
	_t(x, 131, "TARGETS DOWN", _f_label, 15, c.dim)
	_t(x, 131, "%d / %d" % [down, targets.size()], _f_label, 15, c.text, 342, HORIZONTAL_ALIGNMENT_RIGHT)
	_bar(Rect2(x, 155, 342, 12), float(down) / maxf(targets.size(), 1))
	_field(x, 185, "CAPTURE", null)
	_field(x, 247, "CACHES LEFT", null)
	_field(x, 309, "CHECKPOINT", null)


## Run: how long this run has gone (big), then money, threat and what's carried.
func _draw_run() -> void:
	var e := int(Time.get_ticks_msec() / 1000.0 - _run_start)
	var base := 72.0 + _f_title.get_ascent(72)
	_screen.draw_string(_f_label, Vector2(16, base), "ELAPSED", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, c.dim)
	_screen.draw_string(_f_title, Vector2(16 + _w("ELAPSED", _f_label, 15) + 20, base), "%02d:%02d" % [e / 60, e % 60], HORIZONTAL_ALIGNMENT_LEFT, -1, 72, c.accent)
	_screen.draw_rect(Rect2(16, base + 18, 688, 1), c.line)
	_field(16, base + 36, "CREDITS", null)
	_field(376, base + 36, "THREAT", null)
	_field(16, base + 96, "CARRIED", null)


## Gear: both guns (the one in hand highlighted), ammo and grenades; the outfit, front or back (R turns it).
func _draw_gear() -> void:
	var y := 64.0
	for w in manager.weapons:
		var held := w == manager.current
		_screen.draw_rect(Rect2(16, y, 448, 73), c.card if held else c.card2)
		_t(28, y + 8, w.data.display_name.to_upper(), _f_title, 24, c.text)
		if held:
			_t(28, y + 13, "IN HAND", _f_label, 14, c.accent, 424, HORIZONTAL_ALIGNMENT_RIGHT)
		var modes := PackedStringArray()
		for m in w.data.modes():
			modes.append(WeaponData.mode_name(m))
		_t(28, y + 41, "%s  ·  %d spare mags" % [" / ".join(modes), w.spare.size()], _f_soft, 18, c.soft)
		y += 73.0 + 14.0
	y += 4.0
	_field(16, y, "AMMO TYPE", null)
	_field(248, y, "GRENADES", "FRAG ×%d" % manager.grenades)

	var view := Rect2(484, 64, 220, 306)
	_screen.draw_rect(view, c.panel)
	var showing_back := _back if _turn >= 0.5 else not _back  # sides swap edge-on, halfway through the turn
	var tex: Texture2D = _outfit_back if showing_back else _outfit_front
	if tex:
		var sx := absf(cos(PI * _turn))  # squash to edge-on and back out: reads as turning around
		_screen.draw_set_transform(Vector2(view.get_center().x * (1.0 - sx), 0.0), 0.0, Vector2(sx, 1.0))
		_fit_bottom(tex, view)
		_screen.draw_set_transform(Vector2.ZERO)
	_t(492, 70, "BACK" if showing_back else "FRONT", _f_label, 14, c.dim)
	var btn := Rect2(484, 378, 220, 44)
	_screen.draw_rect(btn, c.card2)
	_screen.draw_rect(btn, c.line, false, 1.0)
	var key_w := _w("R", _f_tab, 16) + 14.0
	var total := key_w + 10.0 + _w("ROTATE", _f_tab, 16)
	var kx := btn.get_center().x - total * 0.5
	_screen.draw_rect(Rect2(kx, btn.get_center().y - 11, key_w, 22), c.main)
	_mid(kx + 7, btn.get_center().y, "R", _f_tab, 16, c.on_main)
	_mid(kx + key_w + 10.0, btn.get_center().y, "ROTATE", _f_tab, 16, c.text)
	_t(484, 430, "OUTFIT", _f_label, 15, c.dim)
	_t(484, 448, outfit_name, _f_title, 26, c.text)


## Every Dummy in the level.
func dummies() -> Array[Dummy]:
	var out: Array[Dummy] = []
	for n in get_tree().get_nodes_in_group("resettable"):
		if n is Dummy:
			out.append(n)
	return out


## Text with its top at y (draw_string takes the baseline).
func _t(x: float, y: float, text: String, f: Font, px: int, col: Color, width := -1.0, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	_screen.draw_string(f, Vector2(x, y + f.get_ascent(px)), text, align, width, px, col)


## Text centred vertically on cy.
func _mid(x: float, cy: float, text: String, f: Font, px: int, col: Color, width := -1.0, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	_screen.draw_string(f, Vector2(x, cy + (f.get_ascent(px) - f.get_descent(px)) * 0.5), text, align, width, px, col)


func _w(text: String, f: Font, px: int) -> float:
	return f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x


## Label over a value; null = the system isn't in the game yet (dim dash).
func _field(x: float, y: float, label: String, value: Variant) -> void:
	_t(x, y, label, _f_label, 15, c.dim)
	_t(x, y + 18, "—" if value == null else str(value), _f_value, 22, c.dash if value == null else c.text)


## A tinted tile with a label over a value, the pair centred vertically.
func _tile(r: Rect2, label: String, value: String, f: Font, px: int, bg: Color) -> void:
	_screen.draw_rect(r, bg)
	var y := r.position.y + (r.size.y - (18.0 + px * 1.1)) * 0.5
	_t(r.position.x + 14, y, label, _f_label, 15, c.dim)
	_t(r.position.x + 14, y + 18, value, f, px, c.text, r.size.x - 28)


func _bar(box: Rect2, f: float) -> void:
	_screen.draw_rect(box, Color(0, 0, 0, 0.45))
	_screen.draw_rect(Rect2(box.position, Vector2(box.size.x * clampf(f, 0.0, 1.0), box.size.y)), c.accent)


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


## Draw a texture as large as fits in the box, keeping aspect, standing on the box's bottom edge.
func _fit_bottom(tex: Texture2D, box: Rect2) -> void:
	var ts := Vector2(tex.get_size())
	var k := minf(box.size.x / ts.x, box.size.y / ts.y)
	var sz := ts * k
	_screen.draw_texture_rect(tex, Rect2(box.position + Vector2((box.size.x - sz.x) * 0.5, box.size.y - sz.y), sz), false)


## Fill the box with the texture (cropping the sides or the bottom), keeping its top edge.
func _cover_top(tex: Texture2D, box: Rect2) -> void:
	var ts := Vector2(tex.get_size())
	var k := maxf(box.size.x / ts.x, box.size.y / ts.y)
	var src := box.size / k
	_screen.draw_texture_rect_region(tex, box, Rect2(Vector2((ts.x - src.x) * 0.5, 0.0), src))
