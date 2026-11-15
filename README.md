# Tactical FPS prototype: gunplay and killhouse

Greybox testbed for movement and shooting (Godot 4.7, GDScript, Forward+ renderer, Jolt physics).

## Run

Open the folder in Godot 4.7 and press F5. The main scene is `res://maps/killhouse.tscn`; you spawn at the firing line, facing down the range. The shoot house is behind you.

Headless check (loads every script and scene, asserts ammo/TTK logic, plays the level for a few seconds):

```
godot --headless --path . res://tests/smoke_test.tscn
```

Rebuild the level from its layout script (this overwrites manual edits to `killhouse.tscn`):

```
godot --headless --path . res://maps/tools/build_killhouse.tscn
```

If you edit `killhouse.tscn` by hand instead, select `NavigationRegion3D` and click **Bake NavigationMesh** so the patrols follow the new layout.

## Controls

| Action | Key |
|---|---|
| Move | W A S D |
| Sprint (forward only, no ADS/fire) | Shift |
| Crouch toggle | C / Ctrl |
| Prone toggle | Z |
| Jump / vault (low obstacle ahead) | Space |
| Lean left / right (hold) | Q / E |
| Fire / ADS (hold) | LMB / RMB |
| Reload | R |
| Fire mode | B |
| Interact (doors) | F |
| Frag grenade | G |
| Reset dummies, health, ammo, doors | F5 |
| Debug panel and live tuning | F1 (frees the mouse) |
| Phone (status: vitals, outfit, weapon, mags) | Hold Tab |
| Canted sight (weapons that have one, e.g. the rifle's offset red dot) | V |
| Debug HUD (weapon/HP text, exact ammo, portrait) | F2 |
| Viewmodel editor: drag the gun (hip), the sight box (aimed frame), the muzzle point or the tablet; Save writes the .tres | F4 |
| Bodycam effect on/off | F3 |
| Release / capture mouse | Esc |

The white dot is where the gun points. In hip fire it drifts inside the aim deadzone before the view turns; when you aim down sights, the view snaps to it.

## Weapon sprites (Doom-style)

Weapons can be drawn as full-screen 2D frames instead of the greybox 3D gun. Render each frame in Koikatsu at 16:9 (the test set is 2560×1440) with a transparent background and the arms reaching the bottom edge. Then fill the **Sprites** group on the weapon's `.tres`:

| Field | Use |
|---|---|
| `idle_sprite` | Default frame. Setting it switches that weapon to sprite mode. |
| `shoot_sprite` | Shown for `shoot_frame_time` after each shot, with a directional motion blur. |
| `reload_sprites` | Any number of frames, played over the reload (tactical, and empty if no empty set). |
| `empty_reload_sprites` | Optional frames for reloads from empty (slide/bolt locked). |
| `reload_fps` | Playback rate for the reload frames; the last frame holds until the reload ends. 0 = stretch them evenly over the reload time. |
| `ads_sprite` | Optional. Without it, the hip frame zooms toward the centre while aiming. |
| `canted_aim_sprites` / `canted_sight_window` / `canted_dot_size` | Optional offset sight toggled with V: its own aim-in frames, glass window (editable in F4 with Canted) and red dot. |
| `sprint_sprite` | Optional sprint pose: the gun dips out (`sprint_dip` on SpriteViewmodel), swaps at the bottom and rises in. |
| `scope_magnification` | Magnified optic: the lens (`sight_window` on the last aim frame) shows a picture-in-picture view at this zoom, with an ACOG reticle in `reticle_color`. |
| `fire_sound` | One shot, played per round (overlapping) with `fire_pitch_jitter`; goes through the gun reverb. |
| `mode_switch_time` | Length of the selector-flick animation (B); twist and dip amounts are on the SpriteViewmodel node. |
| `aim_sprites` | Optional hip-to-ADS transition, driven by aim progress; last frame is held while aimed. Overrides `ads_sprite`. Must have transparent backgrounds. |
| `sight_window` | Sight glass on the last aim frame (UV rect); aiming slides the frame so its centre lands on the aim point. |
| `reticle_size` / `reticle_color` | Holographic reticle drawn inside `sight_window` at the true aim point (0 = none). |
| `sprite_offset` | Per-weapon placement in screen heights (+y = lower). Default 0.08 down. |
| `shoot_frame_time`, `shoot_blur`, `shoot_blur_angle` | How long the shoot frame shows; blur streak length (fraction of frame width) and angle in degrees, same convention as Paint.NET's Motion Blur (−34° = down-right). |
| `muzzle_uv` | Muzzle position on the idle/shoot frame (0–1). Suppressor smoke spawns here. |
| `suppressed` | Smoke wisps from the muzzle instead of a muzzle-flash light. |

The motion blur is a shader (`player/motion_blur.gdshader`) applied in-engine, so the source PNGs stay untouched. Sway, bob, kick, sprint and lowering move the sprite using the same values as the 3D viewmodel. The scale factors are exported on `Player/ViewmodelLayer/SpriteViewmodel`.

The loadout is a single suppressed SMG (`weapons/data/smg.tres`) using the frames in `koikatsu sprites/testing/`. Smoke look (size, opacity, rise, lifetime) is exported on `Player/ViewmodelLayer/MuzzleSmoke`.

Bullet impacts leave a decal, a dust burst tinted to the surface colour, and debris chunks. Hitboxes get a blood puff instead.

## First-person body

`BodySprite` (in `player.tscn` → ViewmodelLayer, behind the gun) shows full-screen frames of your own body, rendered looking down:
`idle_sprite`, `walk_sprites` (looped by distance walked, `cycle_length` m per loop, reversed when backing up) and `dead_sprite`.
It slides into view as you look down; `frame_pitch` is the look pitch the frames were rendered at, `body_scale` the frame size. Hidden while prone.
Killed while prone: `dead_prone_sprite`, and the view tilts by `dead_prone_roll` (on Player). Footstep clips are in `Footsteps.steps`.
`crouch_idle_sprite` / `crouch_walk_sprites` replace the standing frames while crouched.

`Portrait` (HUDLayer, bottom-left) shows `full` / `hurt` / `low` / `dead` by health; thresholds `hurt_below` (0.66) and
`low_below` (0.33) are fractions of max health. Frames can be full-screen renders: each is cropped to its visible pixels.

## Reverb

Gun sounds (player and dummies) play on the `World` bus (`default_bus_layout.tres`), which has a reverb; footsteps,
jumps and landings use the `Footsteps` bus, which gets the same reverb at `footstep_wet_scale` (40%) of the wetness. `ReverbProbe`
(on the Player) casts rays around the listener a few times a second and steers it from the space you're in: tight rooms
get a short, wet ring; open ground gets a drier sound with a delayed echo off distant walls. No zones to place, so it works
in any map. Tuning (wet range, ray length, what counts as a near wall, update rate) is on the `ReverbProbe` node.

## Ambience

The `Ambience` autoload plays every track in `my sounds/ambience/tracks/` in a shuffled order, crossfading between them
(`volume_db`, `crossfade`), on the `Ambience` bus. The tracks were cut from the 2-hour mix with
`python tools/split_ambience.py <mix.mp3> "my sounds/ambience/tracks"` (cuts land in quiet moments every 4-7 min).
The source mix lives in `my sounds/ambience/source/`, which Godot ignores (`.gdignore`) and git ignores (288 MB).

## Hip fire follows the gun

With a sprite gun, shots go where the gun is pointing: `SpriteViewmodel` tracks the screen point that sits on the
centre when the gun is at rest, carried by sway, bob, inertia, kick, the freeaim drift and stance pull-in, and
`Player.aim_basis()` fires through it (the HUD aim dot shows it). Aiming blends it back onto the sights. The wall
check and grenade throws still use the view (`freeaim_basis()`).

## Sprite shading

The viewmodel sprites (gun, body, phone) darken when your hands are out of the sun: `SpriteShadow` (a CanvasModulate in
ViewmodelLayer) casts a few rays from around the hands toward the level's DirectionalLight3D and fades between
`lit_color` and `shadow_color`. Sample points and fade speed are on the node.

## Handling sounds

`WeaponManager` plays `equip_sound` when a gun comes up (switch, after a grenade, phone put away) and `aim_sound` when
you start aiming. Jump and landing clips are on `Footsteps` (`jump_sounds`, `land_sounds`). Crouching and going prone
pull the gun closer (`low_stance_zoom`, `low_stance_shift` on SpriteViewmodel).

## Phone (diegetic UI)

There's no status HUD by default: hold **Tab** and Kei lowers the gun and pulls out her phone, showing her health face and
vitals, outfit, weapon and fire mode, a rough mag estimate (Full / Nearly full / Half / Nearly empty), spare mags and frags.
No firing, aiming or reloading while it's out; pressing fire or aim puts it away. Settings live on the `Phone` node in
`player.tscn` (`heroine_name`, `outfit_name`, `outfit_sprite`, `screen_quad` for the screen corners on the frame) and
`phone_time` on the WeaponManager. Decisions: `docs/decisions/2026-11-15-diegetic-phone.md`.

## Bodycam look

`ui/bodycam.gdshader` runs over the 3D world and the weapon sprite. The HUD and debug panel sit on a higher layer and stay undistorted, and the HUD aim dot and hit marker are moved through the same lens maths so they stay on target. It has a wide-lens barrel distortion, chromatic aberration at the edges, over-sharpening, a washed-out grade, vignette, grain, and a REC/timestamp overlay. While it's on, the FOV goes to `bodycam_fov` (95°), because the lens magnifies the centre. Every value is a shader parameter on `Player/PostFXLayer/Bodycam`'s material and can be changed live.

## Layout

```
core/     game.gd (autoload: reset, TTK, toasts), health.gd, hitbox.gd
player/   player.tscn/.gd (movement, stance, lean, look, recoil), viewmodel.gd, footsteps.gd
weapons/  weapon_data.gd (Resource), data/*.tres, weapon.gd, weapon_manager.gd,
          ballistics.gd (hitscan + penetration), impact.gd (decals/puffs), grenade.tscn/.gd
ai/       dummy.tscn/.gd (hit zones, patrol, turn and return fire)
maps/     killhouse.tscn, door.tscn/.gd, tools/build_killhouse.gd
ui/       hud.gd, debug_panel.gd
tests/    smoke_test.tscn/.gd
```

Physics layers: 1 world, 2 actors (movement capsules), 3 hitbox (bullets hit these), 4 penetrable (thin walls and doors; bullets pass through with reduced damage).
Render layer 2 holds the viewmodel, which is drawn by its own camera in a transparent SubViewport so it never clips into walls.

## Systems in short

- **Damage:** everything goes through `Health.take_damage(amount, zone, source)`. Zone multipliers live on Health: head ×4, torso ×1, arms ×0.6, legs ×0.7. SMG up close: 4 torso hits or 1 headshot.
- **Ammo:** magazine round count plus a chamber flag. A tactical reload keeps the chambered round (30+1). An empty reload takes longer and chambers from the new magazine. Spare magazines keep their own counts; a partial magazine goes back in the pouch, and reloads take the fullest one.
- **Recoil:** each weapon has a per-shot pattern (`recoil_pattern`, degrees) plus `recoil_random`. The camera kick (aim) and the viewmodel kick are tuned separately. Pulling the mouse against recoil cancels it, so a countered spray doesn't drift down when recoil recovers.
- **Bullets:** `Ballistics.trace_segment()` is the unit of travel. Hitscan calls it once over the full range. A projectile mode would call it once per tick (`ballistic_mode` and `muzzle_velocity` are already on WeaponData).
- **Live tuning:** use the F1 sliders, or while the game runs open the Remote tree in the editor's Scene dock and edit the WeaponData on `Player/.../Weapons`. **Save weapon .tres** in the panel writes the current values back to disk.

## Guessed values (all exported)

| Where | Value | Default |
|---|---|---|
| Player | `walk_speed` / `sprint_speed` / `crouch_speed` / `prone_speed` | 3.2 / 5.6 / 1.9 / 0.8 m/s |
| Player | `ground_accel` / `ground_decel` | 9 / 11 m/s² |
| Player | `deadzone_deg` (hip freeaim) | 3° |
| Player | `mouse_sensitivity` | 0.08°/px |
| Player | `stance_spread_mult` / `stance_recoil_mult` | 1 / 0.75 / 0.5 and 1 / 0.8 / 0.6 |
| Player | `lean_angle` / `lean_shift` | 12° / 0.3 m |
| Player | `ads_speed_mult`, `jump_velocity`, `vault_max_height` | 0.6, 3.6, 1.3 m |
| Viewmodel | `sway_amount`, `inertia`, `bob_amount`, `kick_return` | 0.25, 0.012, 0.012, 14 |
| WeaponData | damage, rpm, falloff, spreads, recoil pattern, reload and ADS times | see `weapons/data/smg.tres` |
| Health | `zone_multipliers` | head 4, torso 1, arms 0.6, legs 0.7 |
| Grenade | `fuse`, `radius`, `max_damage`, `falloff_exponent` | 3.5 s, 9 m, 250, 1.5 |
| Dummy | `aim_error_deg`, `fire_interval`, `damage_scale`, `reaction_time` | 4°, 0.7 s, 0.4, 0.6 s |

## Known shortcuts

- Projectile ballistics is not implemented; that mode falls back to hitscan.
- Prone uses a short upright capsule, so there is no proper prone body yet.
- The player has only head and torso hitboxes.
- Burst mode has no extra delay between bursts.
- No magazine check yet. It is optional and planned.
