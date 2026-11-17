class_name BodyView
extends Resource
## First-person body (legs) settings, edited live with F4 -> Legs and saved to body_view.tres.

@export var cycle_length := 5.0  ## metres walked per loop of the walk frames; raise it if the feet slide (slower legs)
@export var run_cycle_length := 4.5  ## the same for the sprint (run) frames
@export var run_scale := 1.0  ## run frames' size relative to the walk frames (the run render is framed closer)
@export var run_offset := Vector2.ZERO  ## run frames' shift, screen heights
