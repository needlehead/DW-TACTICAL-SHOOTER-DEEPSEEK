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
| Assault rifle / pistol / DMR / SMG | 1 / 2 / 3 / 4 |
| Frag grenade | G |
| Reset dummies, health, ammo, doors | F5 |
| Debug panel and live tuning | F1 (frees the mouse) |
| Exact ammo counter | F2 |
| Release / capture mouse | Esc |

The white dot is where the gun points. In hip fire it drifts inside the aim deadzone before the view turns; when you aim down sights, the view snaps to it.

## Weapon sprites (Doom-style)

Weapons can be drawn as full-screen 2D frames instead of the greybox 3D gun. Render each frame in Koikatsu at 16:9 (the test set is 2560�1440) with a transparent background and the arms reaching the bottom edge. Then fill the **Sprites** group on the weapon's `.tres`:

| Field | Use |
|---|---|
| `idle_sprite` | Default frame. Setting it switches that weapon to sprite mode. |
| `shoot_sprite` | Shown for `shoot_frame_time` after each shot, with motion blur. |
| `reload_sprites` | Any number of frames, spread evenly over the reload time (tactical and empty). |
| `ads_sprite` | Optional. Without it, the hip frame zooms toward the centre while aiming. |
| `sprite_offset` | Per-weapon placement in screen heights (+y = lower). Default 0.08 down. |
| `shoot_frame_time`, `shoot_blur` | How long the shoot frame shows, and the blur streak length (fraction of screen height). |

The motion blur is a shader (`player/motion_blur.gdshader`) applied in-engine, so the source PNGs stay untouched. Sway, bob, kick, sprint and lowering move the sprite using the same values as the 3D viewmodel. The scale factors are exported on `Player/ViewmodelLayer/SpriteViewmodel`.

The test frames in `koikatsu sprites/testing/` are assigned to the assault rifle. The other weapons still use the greybox 3D gun.

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

- **Damage:** everything goes through `Health.take_damage(amount, zone, source)`. Zone multipliers live on Health: head ×4, torso ×1, arms ×0.6, legs ×0.7. Assault rifle up close: 3 torso hits or 1 headshot.
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
| WeaponData | damage, rpm, falloff, spreads, recoil pattern, reload and ADS times | see `weapons/data/*.tres` |
| Health | `zone_multipliers` | head 4, torso 1, arms 0.6, legs 0.7 |
| Grenade | `fuse`, `radius`, `max_damage`, `falloff_exponent` | 3.5 s, 9 m, 250, 1.5 |
| Dummy | `aim_error_deg`, `fire_interval`, `damage_scale`, `reaction_time` | 4°, 0.7 s, 0.4, 0.6 s |

## Known shortcuts

- Projectile ballistics is not implemented; that mode falls back to hitscan.
- Prone uses a short upright capsule, so there is no proper prone body yet.
- The player has only head and torso hitboxes.
- Burst mode has no extra delay between bursts.
- No magazine check yet. It is optional and planned.
