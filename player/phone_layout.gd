class_name PhoneLayout
extends Resource
## How the phone is held on screen (edited live with F4 -> Tablet, saved to phone_layout.tres).

@export var hold_scale := 1.3  ## frame size: larger = closer to the camera
## Where the frame's bottom-left corner (the arm's exit point) sits relative to the screen's, in screen heights.
@export var hold_offset := Vector2(-0.2, 0.06)
