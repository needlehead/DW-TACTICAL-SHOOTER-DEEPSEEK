extends TextureRect
## Doom-style first-person body: full-screen frames of your own legs/torso, rendered looking down.
## Slides up into view as you look down, plays walk frames by distance travelled (so feet match speed,
## reversed when backing up), and shows the death frame when dead. Drawn behind the weapon sprite.

@export var idle_sprite: Texture2D
@export var walk_sprites: Array[Texture2D] = []
@export var dead_sprite: Texture2D
@export var frame_pitch := -80.0  ## look pitch (degrees) the frames were rendered at; fully in view there
@export var cycle_length := 3.5  ## metres walked per loop of walk_sprites; raise to slow the legs
@export var body_scale := 0.65  ## frame size; shrinks toward the bottom centre so the cut-off torso stays at the screen edge
@export var min_walk_speed := 0.3  ## below this (m/s) the idle frame shows

var _phase := 0.0

@onready var player: Player = owner


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED


func _process(delta: float) -> void:
	var vp := get_viewport_rect().size
	size = vp
	pivot_offset = Vector2(vp.x * 0.5, vp.y)
	scale = Vector2.ONE * body_scale
	if not player.alive:
		texture = dead_sprite
		position = Vector2.ZERO
		visible = texture != null
		return
	# Angle above the render pitch -> screen distance the body drops (linear in FOV is close enough here).
	var pitch := player.look_pitch + player.recoil.y
	var drop := maxf(0.0, (pitch - frame_pitch) * vp.y / player.camera.fov)
	visible = drop < vp.y and player.stance != Player.Stance.PRONE
	if not visible:
		return
	position = Vector2(0.0, drop)

	var speed := player.horizontal_speed()
	if speed < min_walk_speed or walk_sprites.is_empty() or not player.is_on_floor():
		texture = idle_sprite
		return
	var forward := -player.global_basis.z
	var dir := -1.0 if player.velocity.dot(forward) < -0.1 else 1.0
	_phase = fposmod(_phase + dir * speed * delta / cycle_length, 1.0)
	texture = walk_sprites[mini(int(_phase * walk_sprites.size()), walk_sprites.size() - 1)]
