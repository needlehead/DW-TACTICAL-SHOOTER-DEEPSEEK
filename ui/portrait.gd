extends TextureRect
## Doom-style status portrait in the bottom-left corner, picked by health: full / hurt / low / dead.
## Frames are full-screen renders; each is cropped to its visible pixels once at load.

@export var full: Texture2D
@export var hurt: Texture2D  ## at or below hurt_below
@export var low: Texture2D  ## at or below low_below
@export var dead: Texture2D
@export_range(0.0, 1.0) var hurt_below := 0.66  ## fraction of max health
@export_range(0.0, 1.0) var low_below := 0.33
@export var height := 0.22  ## fraction of screen height
@export var margin := 24.0

var _cropped := {}  # Texture2D -> AtlasTexture

@onready var health: Health = owner.get_node("Health")


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	for t: Texture2D in [full, hurt, low, dead]:
		if t:
			var a := AtlasTexture.new()
			a.atlas = t
			a.region = Rect2(t.get_image().get_used_rect())
			_cropped[t] = a


func _process(_delta: float) -> void:
	var f := health.current / health.max_health
	var t := dead if health.dead else low if f <= low_below else hurt if f <= hurt_below else full
	texture = _cropped.get(t)
	if texture == null:
		return
	var vp := get_viewport_rect().size
	var h := vp.y * height
	size = Vector2(h * texture.get_width() / texture.get_height(), h)
	position = Vector2(margin, vp.y - h)  # bottom edge flush, like the cut-off chest in the renders
