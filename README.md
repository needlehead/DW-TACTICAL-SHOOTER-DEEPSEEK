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
| Viewmodel editor: drag the gun (hip), the sight box (aimed frame), the muzzle point, the tablet, the death view or the legs' step speed; Save writes the .tres | F4 |
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
Killed while prone: `dead_prone_sprite`. Each death (standing / prone) has its own view roll, and its frame tilts with it. The death view (camera height, tilt, both death frames' position and size, tilt centres, the dead camera's pitch / yaw / roll, how much of her last look it keeps and how fast it settles) lives in `player/death_view.tres`; edit it live with **F4 → Dead** (the Showing button cycles standing / prone / standing 2 / launched and replays it). Standing deaths pick `dead_sprite` or `dead_sprite_2` at random. A grenade (blast) kill launches her: the view is thrown up (`launch_height`) and flips over (`launch_spin`) for `launch_time` while `launch_sprites` 1 and 2 play, then lands on frame 3. The **EASTER EGG** test pad plays the easter-egg death (`EggDeath`): Ingrid walks up, grabs an ankle and drags the body the way the pad faces in tugs (`egg_sprites` 1-3), throws it (4) onto the heap of other Keis (5 over `egg_heap`), talking in game subtitles; lines and timings are exports on `EggDeath`. How fast the legs step (`cycle_length`, metres per walk loop; raise it if the feet slide) is in `player/body_view.tres`; edit it live with **F4 → Legs**, which walks the legs in place at walk or sprint speed. Sprinting uses `run_sprites` (its own `run_cycle_length`, and `run_scale` / `run_offset` to line the closer-framed run render up with the walk: drag / wheel in the Legs sprint preview). Footstep clips are in `Footsteps.steps`.
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

## Damage feedback

`DamageFeedback` (HUDLayer): each hit flashes the screen edges red (scaled by damage), punches the view and spikes
the bodycam's colour fringing; below `low_health` the edges pulse with a heartbeat. The direction arcs and voice
grunts still play. Unsuppressed shots also light the gun sprite (`flash_light` on SpriteViewmodel).

## Laser, flashlight and low light
- WeaponData "Attachments": `laser` (dot + beam, toggle **L**), `laser_color`, `laser_uv` (emitter on the hip frame), `flashlight` (toggle **T**). MP7: red laser. Radian: green laser + light.
- The dot sits where the shots go (same ray as hip fire). The 2D beam only draws on hip frames and only in the dark: its strength follows how much SpriteShadow is darkening the hands.
- Low-light test room: `maps/dark_area.tscn`, east of the spawn (sign "LOW LIGHT"). A light-lock entrance keeps the sun out; its `DarkZone` fades the sky ambient down while you are inside and darkens the 2D hands. The flashlight lifts the hands back up a bit. The phone screen is backlit and never darkens.

## Voice and breathing

`PlayerVoice` (on the Player) plays a random `damage_sounds` clip when hit (with `damage_cooldown`), a `death_sounds`
clip on death, and a breathing loop that only plays while sprinting (swells in, fades out over ~2 s after). The loop is generic, shared by all heroines: rebuild it with
`python tools/make_breath_loop.py "my sounds/generic/source/<breath>.mp3" "my sounds/generic/breath_loop.ogg"`.

## Handling sounds

`WeaponManager` plays `equip_sound` when a gun comes up (switch, after a grenade, phone put away) and `aim_sound` when
you start aiming. Jump and landing clips are on `Footsteps` (`jump_sounds`, `land_sounds`). Crouching and going prone
pull the gun closer (`low_stance_zoom`, `low_stance_shift` on SpriteViewmodel).

## Phone (diegetic UI)

There's no status HUD by default: press **Tab** and Kei lowers the gun and pulls out her device; Tab again puts it away.
It always opens on **Status**; **Q/E** or the **mouse wheel** flip pages while it's out (Q/E lean again once it's away):
- **Status:** health face and vitals, outfit, weapon and fire mode, a rough mag estimate, spare mags and frags.
- **Objective:** heading-up map of the targets (red = up, grey X = down), targets-down progress.
- **Run:** elapsed time (restarts on reset).
- **Gear:** both guns with fire modes and spare mags (the one in hand highlighted), frags, and the outfit: front view,
  **R** turns it to show the back.

The screen's colours all come from one `heroine_color` on the Phone node (Kei: `#529364`); fonts are Barlow
(`fonts/`, OFL). The layout follows the design mockup in `docs/ui_mockup/`.
Fields for systems the game doesn't have yet (capture, caches, checkpoint, credits, threat, carried items, ammo type)
show a dim dash. No firing, aiming or reloading while it's out; taking damage, sprinting, firing or aiming puts it away. Settings live on the `Phone` node in
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

## Night vision

A pair of PVS-15-style goggles sits on a stand next to the spawn ("NIGHT VISION [F]"): look at it and press **F** to
pick them up. **N** then flips them down: the gun lowers, Kei brings the goggles to her eyes, and the tubes come on
(N again flips them up, in reverse). Through the tubes:
- two round fields of view with dark housing around them, instead of a full-screen filter;
- light is amplified (the camera's exposure is raised), so the low-light room reads; in daylight everything washes out;
- green-white phosphor with a faint honeycomb (the tube's fibre plate) and a slow shimmer, a little softness, and bloom around bright lights (flashlight, muzzle
  flash, lit doorways);
- the gun up close goes soft, and a magnified scope shows an amplified but blurry picture: use a laser or the red dot.

**L** cycles the laser **visible → IR → off**; **I** toggles the IR illuminator (a wide flood that only shows through the goggles). The IR laser is invisible to the naked eye and shows (dot and beam,
in any light) only through the goggles. The tablet's Gear page lists the goggles once picked up. F5 puts them back on
the stand. Settings: `NightVision` (in the player: frame timing, `exposure`, `hand_fill`) and `ui/night_vision.gdshader`
(`gain`, `phosphor`, `bloom`, `honeycomb`, `shimmer`, tube size and spacing); `gun_defocus` and `scope_blur` on `NightVision`.

## Stamina

Sprinting drains stamina (about 9 s from full); run it dry and you can't sprint again until it is back to 30%. It starts
recovering 0.8 s after you stop (slower while walking). While it's low:
- the aim wobbles with your breathing: a slow figure-8 of the view (so it moves the sights and where shots go), wider
  and quicker the more tired you are; crouching and going prone steady it; there is a tiny breathing sway even rested;
- the gun lags further behind your mouse movement;
- the breathing stays loud until you've recovered;
- the screen edges drain of colour and darken (tunnel vision), pulsing with each breath (`FatigueFX`, under the bodycam so its REC overlay stays bright; it backs off its darkening when health is low so the red warning reads first).
Settings: the "Stamina" group on the Player.

Crawling (moving while prone) with a gun that has a sprint pose (the Radian) carries it in that pose with a slower,
deeper bob, and eases back to the prone idle when you stop. You can't fire or aim while crawling.

## Story dialogue

Talk to Ingrid (next to the spawn, **F**) to test it. A conversation is a `Dialogue` resource (`dialogue/*.tres`) written as plain text: `Speaker: line` for a line, `> option text -> label` for Kei's choices (consecutive ones make one menu; she says the picked one), `# label` to mark a branch, `-> label` to jump and `-> end` to finish (see `dialogue/ingrid_range_day.tres`). An `Npc` plays its `dialogues` in order, one per talk, repeating the last. `Npc` (`maps/npc.gd`) opens it in the `DialogueBox`: the game pauses and blurs behind the portraits and the lines stack as speech boxes (Ingrid right / orange, Kei left / green; other speakers centred grey). **F** / Space / click for the next line, click or **1-9** to pick a choice, **Esc** skips. New speakers get a side and colours in `DialogueBox.SPEAKERS`. Character portraits are `Portrait` resources (`dialogue/portraits/*.tres`: full-screen art plus an offset and scale); place them with **F4** while a conversation is open (VN sprite editor: click a character, drag to move, wheel to scale, arrows nudge, Save writes the .tres).
