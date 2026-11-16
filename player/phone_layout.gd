class_name PhoneLayout
extends Resource
## How the phone is held on screen (edited live with F4 -> Tablet, saved to phone_layout.tres).

@export var hold_scale := 1.0  ## frame size: larger = closer to the camera (scales around the bottom centre)
## How far the frame is moved from where the render puts it, in screen heights.
@export var hold_offset := Vector2.ZERO
