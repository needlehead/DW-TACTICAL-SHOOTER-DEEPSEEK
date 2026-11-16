class_name DeathView
extends Resource
## How death looks (edited live with F4 -> Dead, saved to death_view.tres): the camera on the floor and the
## first-person death frames. "Prone" is the frame and tilt used when killed while prone.

@export var eye_height := 0.25  ## camera height (m) once dead
@export var prone_roll := 14.0  ## degrees the view tilts when killed while prone; the prone frame tilts with it
@export var stand_offset := Vector2.ZERO  ## death frame shift, screen heights
@export var stand_scale := 1.0
@export var prone_offset := Vector2.ZERO
@export var prone_scale := 1.37  ## at full tilt; overscale keeps the arms' cut-off ends off screen
@export var prone_pivot := Vector2(0.875, 0.667)  ## tilt and scale centre, 0-1 of the screen (near the right hand)
