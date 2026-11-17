extends TextureRect
## Doom-style first-person body: full-screen frames of your own legs/torso, rendered looking down.
## Slides up into view as you look down, plays walk frames by distance travelled (so feet match speed,
## reversed when backing up), and shows the death frame when dead. Drawn behind the weapon sprite.

@export var idle_sprite: Texture2D
@export var walk_sprites: Array[Texture2D] = []
@export var run_sprites: Array[Texture2D] = []  ## while sprinting; empty falls back to walk_sprites
@export var dead_sprite: Texture2D
@export var dead_prone_sprite: Texture2D  ## used when killed while prone; empty falls back to dead_sprite
@export var crouch_idle_sprite: Texture2D  ## crouched frames; empty falls back to the standing ones
@export var crouch_walk_sprites: Array[Texture2D] = []
@export var frame_pitch := -80.0  ## look pitch (degrees) the frames were rendered at; fully in view there
@export var view: BodyView  ## walk speed of the legs (F4 -> Legs)
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
	if player.shows_death():
		var v := player.death_view
		var prone := player.death_prone() and dead_prone_sprite != null
		texture = dead_prone_sprite if prone else dead_sprite
		var p := "prone_" if prone else "stand_"
		# The body lies on the floor, so the frame tilts on screen with the world, around its pivot; the overscale
		# (eased in with the tilt) keeps the frame's cut-off edges off screen.
		var roll: float = v.get(p + "roll")
		var tilt := clampf(player.death_roll / roll, 0.0, 1.0) if roll != 0.0 else 1.0
		pivot_offset = vp * (v.get(p + "pivot") as Vector2)
		rotation = deg_to_rad(player.death_roll)
		scale = Vector2.ONE * lerpf(1.0, v.get(p + "scale"), tilt)
		position = (v.get(p + "offset") as Vector2) * vp.y
		visible = texture != null
		return
	# Angle above the render pitch -> screen distance the body drops (linear in FOV is close enough here).
	var pitch := player.look_pitch + player.recoil.y
	var drop := maxf(0.0, (pitch - frame_pitch) * vp.y / player.camera.fov)
	var preview := player.preview_walk > 0.0  # F4 -> Legs: walk in place, fully in view
	if preview:
		drop = 0.0
	visible = drop < vp.y and player.stance != Player.Stance.PRONE
	if not visible:
		return
	position = Vector2(0.0, drop)
	scale = Vector2.ONE * body_scale
	rotation = 0.0

	var crouched := player.stance == Player.Stance.CROUCH
	var idle := crouch_idle_sprite if crouched and crouch_idle_sprite else idle_sprite
	var walk := crouch_walk_sprites if crouched and not crouch_walk_sprites.is_empty() else walk_sprites
	var speed := player.preview_walk if preview else player.horizontal_speed()
	if speed < min_walk_speed or walk.is_empty() or not (preview or player.is_on_floor()):
		texture = idle
		return
	var running := (speed >= player.sprint_speed if preview else player.is_sprinting) and not run_sprites.is_empty()
	if running:  # the run render is framed closer: its own size and shift (F4 -> Legs, sprint preview)
		walk = run_sprites
		scale *= view.run_scale
		position += view.run_offset * vp.y
	var forward := -player.global_basis.z
	var dir := -1.0 if player.velocity.dot(forward) < -0.1 and not preview else 1.0
	# The phase is shared, so switching between walk and run keeps the legs at the same point of the stride.
	_phase = fposmod(_phase + dir * speed * delta / (view.run_cycle_length if running else view.cycle_length), 1.0)
	texture = walk[mini(int(_phase * walk.size()), walk.size() - 1)]
