class_name DeathView
extends Resource
## How death looks (edited live with F4 -> Dead, saved to death_view.tres): the camera on the floor and the
## first-person death frames. "Stand" is a death while standing or crouched, "prone" one while prone. Each has
## its own view roll; the death frame tilts with the view around its pivot (the body lies on the floor).

@export var eye_height := 0.25  ## camera height (m) once dead
@export var camera_time := 0.7  ## seconds the camera takes to settle into the death view (pitch, yaw, roll)
@export var stand_pitch := -60.0  ## degrees the dead camera looks up (+) / down (-) when killed standing / crouched
@export var stand_yaw := 0.0  ## degrees the dead camera turns right (-) / left (+) from where she faced
## 0 = the camera turns to stand_pitch whatever she was looking at; 1 = it keeps her last look pitch.
@export_range(0.0, 1.0) var stand_keep_look := 0.0
@export var stand_roll := 0.0  ## degrees the view tilts when killed standing / crouched
@export var stand_offset := Vector2.ZERO  ## death frame shift, screen heights
@export var stand_scale := 1.0  ## at full tilt
@export var stand_pivot := Vector2(0.5, 0.5)  ## tilt and scale centre, 0-1 of the screen
@export var prone_pitch := -10.0
@export var prone_yaw := 0.0
@export_range(0.0, 1.0) var prone_keep_look := 0.0
@export var prone_roll := 14.0  ## degrees the view tilts when killed while prone
@export var prone_offset := Vector2.ZERO
@export var prone_scale := 1.37  ## at full tilt; overscale keeps the arms' cut-off ends off screen
@export var prone_pivot := Vector2(0.875, 0.667)  ## tilt and scale centre, 0-1 of the screen (near the right hand)
## Second standing death (picked at random with the first).
@export var stand2_pitch := -60.0
@export var stand2_yaw := 0.0
@export_range(0.0, 1.0) var stand2_keep_look := 0.0
@export var stand2_roll := 0.0
@export var stand2_offset := Vector2.ZERO
@export var stand2_scale := 1.0
@export var stand2_pivot := Vector2(0.5, 0.5)
## Killed by a blast: thrown up, the view flips over and lands (BodySprite launch frames: thrown, tumbling, landed).
@export var launch_time := 1.1  ## seconds in the air
@export var launch_height := 1.2  ## metres the camera rises at the top of the arc
@export var launch_spin := 360.0  ## degrees the view flips over in the air (+ = backwards)
@export var launch_pitch := -60.0  ## where the view settles once landed
@export var launch_yaw := 0.0
@export_range(0.0, 1.0) var launch_keep_look := 0.0
@export var launch_roll := 0.0
@export var launch_offset := Vector2.ZERO
@export var launch_scale := 1.0
@export var launch_pivot := Vector2(0.5, 0.5)
## Easter-egg death (Ingrid drags the body to the heap; EggDeath plays it). The view while it plays.
@export var egg_pitch := -45.0
@export var egg_yaw := 0.0
@export_range(0.0, 1.0) var egg_keep_look := 0.0
@export var egg_roll := 0.0
@export var egg_offset := Vector2.ZERO
@export var egg_scale := 1.0
@export var egg_pivot := Vector2(0.5, 0.5)
