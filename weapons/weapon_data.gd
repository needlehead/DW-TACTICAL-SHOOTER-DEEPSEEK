class_name WeaponData
extends Resource
## All tunables for one weapon. Edit the .tres in the inspector, or live via the F1 panel.

enum BallisticMode { HITSCAN, PROJECTILE }

const SEMI := 1
const BURST := 2
const AUTO := 4

@export var display_name := "Weapon"
@export_flags("Semi", "Burst", "Auto") var fire_modes := SEMI
@export var rpm := 600.0
@export var burst_count := 3

@export_group("Damage")
@export var damage := 35.0  ## torso damage before falloff; Health applies zone multipliers
@export var falloff_start := 30.0  ## metres
@export var falloff_end := 120.0
@export var min_damage_mult := 0.6
@export var max_range := 600.0
@export var penetration_power := 0.5  ## damage kept after each thin surface
@export var max_penetrations := 2
@export var ballistic_mode := BallisticMode.HITSCAN
@export var muzzle_velocity := 800.0  ## m/s, for PROJECTILE mode (not implemented yet)

@export_group("Ammo")
@export var mag_size := 30
@export var spare_mags := 4
@export var reload_time := 2.4  ## tactical: round still chambered
@export var empty_reload_time := 3.1

@export_group("Handling")
@export var ads_time := 0.3
@export var ads_zoom := 1.35  ## FOV divisor while aiming
@export var equip_time := 0.55
@export var holster_time := 0.4
@export var sprint_to_fire_time := 0.25

@export_group("Spread")  # degrees, cone half-angle
@export var hip_spread := 3.0
@export var ads_spread := 0.15
@export var move_spread := 2.0  ## added at walk speed
@export var spread_per_shot := 0.25
@export var spread_max := 3.5
@export var spread_recover := 6.0  ## degrees per second

@export_group("Recoil")
## Per-shot kick in degrees (x = right, y = up). Shots past the end reuse the last entry.
@export var recoil_pattern := PackedVector2Array([Vector2(0, 1)])
@export var recoil_random := Vector2(0.2, 0.1)  ## +/- degrees added per shot
@export var camera_recoil := 1.0  ## scales the pattern applied to the view (aim)
@export var recoil_recovery := 7.0  ## degrees per second back toward the original aim
@export var vm_kick_back := 0.05  ## viewmodel only, metres
@export var vm_kick_rot := 3.0  ## viewmodel only, degrees

@export_group("Sprites")
## Doom-style 2D viewmodel. Full-screen frames (any 16:9 size). Leave idle_sprite empty to use the greybox 3D gun.
@export var idle_sprite: Texture2D
@export var shoot_sprite: Texture2D  ## shown for shoot_frame_time after each shot, with motion blur
@export var ads_sprite: Texture2D  ## optional; without it the hip sprite zooms toward centre
## Optional hip-to-ADS transition, picked by aim progress; the last frame is the held ADS frame.
## Overrides ads_sprite. Aiming out plays the same frames backwards.
@export var aim_sprites: Array[Texture2D] = []
## Sight glass on the last aim frame (0-1 UV). Aiming lines its centre up with the aim point. Empty = no alignment.
@export var sight_window := Rect2()
@export var reticle_size := 0.0  ## holographic ring diameter, fraction of screen height; 0 = no reticle
@export var reticle_color := Color(1.0, 0.2, 0.12)
## > 0: a magnified optic. The lens (sight_window) shows a picture-in-picture view at this zoom, with an ACOG-style reticle.
@export var scope_magnification := 0.0
@export var reload_sprites: Array[Texture2D] = []  ## played over the reload (see reload_fps)
@export var empty_reload_sprites: Array[Texture2D] = []  ## reloads from empty; falls back to reload_sprites
## Frames per second for reload_sprites; the last frame holds if the reload outlasts them.
## 0 = stretch the frames evenly over the whole reload time.
@export var reload_fps := 0.0
## One shot, played per round with overlapping voices; routed through the "World" bus (room reverb).
@export var fire_sound: AudioStream
@export var fire_volume_db := 0.0
@export var fire_pitch_jitter := 0.03  ## random +/- pitch per shot so full auto doesn't sound copy-pasted
@export var mode_switch_time := 0.35  ## selector-flick animation length
@export var sprite_offset := Vector2(0.0, 0.08)  ## fraction of screen height; +y moves the gun down
@export var shoot_frame_time := 0.07
@export var shoot_blur := 0.0223  ## streak length as a fraction of the frame width (57 px on 2560)
@export var shoot_blur_angle := -34.0  ## degrees, Paint.NET convention: 0 = horizontal, negative = down-right
@export var muzzle_uv := Vector2(0.5, 0.5)  ## muzzle position on the idle/shoot frame (0-1); smoke spawns here
@export var suppressed := false  ## muzzle smoke instead of flash light

@export_group("Viewmodel")
@export var vm_size := Vector3(0.06, 0.09, 0.7)
@export var color := Color(0.25, 0.28, 0.24)
@export var hip_offset := Vector3(0.17, -0.15, -0.28)
@export var ads_distance := 0.22  ## sight distance from the eye when aiming


func damage_at(distance: float) -> float:
	var t := clampf(inverse_lerp(falloff_start, falloff_end, distance), 0.0, 1.0)
	return damage * lerpf(1.0, min_damage_mult, t)


func modes() -> Array[int]:
	var out: Array[int] = []
	for m in [SEMI, BURST, AUTO]:
		if fire_modes & m:
			out.append(m)
	return out


static func mode_name(m: int) -> String:
	return {SEMI: "SEMI", BURST: "BURST", AUTO: "AUTO"}.get(m, "?")
