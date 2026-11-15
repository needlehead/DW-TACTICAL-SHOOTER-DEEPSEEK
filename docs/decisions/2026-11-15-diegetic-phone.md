# Diegetic phone UI — decisions

| Decision | Choice | Why | Revisit when |
|---|---|---|---|
| Interactivity | Read-only status screen | No outfit/inventory system to act on yet | outfits or gear become switchable |
| Gun while phone is up | Gun lowers first, then phone rises; no firing/ADS/reload/switching; fire or ADS cancels | Checking status is a real risk, Insurgency-style commitment | it feels too punishing in playtests |
| Regular HUD | Diegetic by default: weapon/HP/frags text and portrait hidden; F2 shows them (debug) | Immersion, but keep a testing escape hatch | shipping (decide whether F2 stays) |
| Input | Hold Tab | Short, deliberate checks | gamepad support is added |
| Mag info | Estimate for the loaded mag (Full / Nearly full / Half / Nearly empty / Empty) + spare mag count | Fits "check your mags" | mag-check-by-feel is added |
| Outfit | Heroine name (Kei Fujiwara), outfit name ("Heavy Metal") and the outfit render | Provided by the artist | multiple heroines/outfits exist |
| Phone art | `diegeticuitest.png` frame; screen contents rendered to a SubViewport mapped onto the screen quad | Screen gets the bodycam lens like the world | the phone is re-rendered at another angle (update `screen_quad`) |

## Open / deferred
- Wrist device alternative — not built; the phone frame is the only device.
- Mag check by feel (no phone) — deferred.
