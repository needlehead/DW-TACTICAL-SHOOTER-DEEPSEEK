class_name Portrait
extends Resource
## A character's dialogue portrait: full-screen art (a transparent 1920x1080 canvas with the character drawn where
## they stand) plus a placement tweak, edited live with F4 in the dialogue screen.

@export var texture: Texture2D
@export var offset := Vector2.ZERO  ## moved from where the art was drawn, in pixels of the 1920x1080 stage
@export var scale := 1.0  ## around the character's feet (bottom centre of the drawn area)

var _pivot := Vector2(-1.0, -1.0)


## The character's drawn area on the canvas (stage pixels, before offset / scale).
func drawn_rect() -> Rect2:
	var img := texture.get_image()
	if img.is_compressed():
		img.decompress()
	var r := Rect2(img.get_used_rect())
	var k := 1080.0 / img.get_height()  # canvas -> stage
	return Rect2(r.position * k, r.size * k)


## Feet: the point scale works around.
func pivot() -> Vector2:
	if _pivot.x < 0.0:
		var r := drawn_rect()
		_pivot = Vector2(r.get_center().x, r.end.y)
	return _pivot
