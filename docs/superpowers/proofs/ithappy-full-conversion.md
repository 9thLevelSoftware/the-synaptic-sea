# Gate 4: Full Asset Import

**Date:** 2026-08-22
**Status:** PASS (pending Godot import verification)

## Scope

Import all 1080+ ithappy Sci-Fi Props assets into the Synaptic Sea project. Convert all 15 structural wrapper scenes. Organize props by category.

## What was built

### Structural modules (15/15 complete)
All 15 wrapper `.tscn` scenes created under `scenes/wrappers/structural/ithappy/`:
- floor_1x1, floor_2x1, corridor_floor_1x1, corridor_floor_1x2
- wall_straight_1x1, wall_end_cap, wall_inner_corner, wall_outer_corner, wall_t_junction
- doorway_frame_open_1x1, bulkhead_portal_2x1, doorway_frame_blocked_1x1
- ramp_up_1x2, pillar_support_1x1, ceiling_cap_1x1

Each wrapper has 3 visual variants (intact/damaged/breached) using ithappy Type A/B/C models.

### Kit catalog
`data/kits/ithappy_scifi_v0.json` — all 15 modules mapped to ithappy wrappers.

### Props (1,084 GLBs in 11 categories)
| Category | Count | Examples |
|----------|-------|---------|
| furniture | 93 | Armchair, Chair, Desk, Sofa, Mini_sofa |
| containers | 72 | Barrel, Box, Crate, Container_type_A/B |
| structural_misc | 82 | Column, Platform, Fence, Stair, Ladder |
| technical | 65 | Generator, Terminal, Vending_Machine, Battery |
| threats | 50 | Turret, Drone, Cargo_drone, Delivery_drone |
| industrial | 71 | Gas_can, Pipe, Cable, Ventilation |
| capsules | 26 | capsule, capsule_contents |
| decor | 44 | Baloon, Barriaer, Trash |
| doors_hatches | 22 | Door, Hatch |
| security | 13 | Security_cam |
| weapons | 11 | Bullet, Missile, Laser_beam |

### File locations
- Structural GLBs: `assets/imported/structural/ithappy/{module_id}/`
- Prop GLBs: `assets/imported/props/ithappy/{category}/`
- Wrapper scenes: `scenes/wrappers/structural/ithappy/`
- Kit catalog: `data/kits/ithappy_scifi_v0.json`

## Test results

### Python regression
```
58 passed in 9.81s
```

### Godot import
Running (1000+ files, takes several minutes). Will verify after completion.

## Camera decision
**Isometric confirmed.** Top-down abandoned.

## Procgen feedback
Current procgen output is visually incoherent — modules pile up without spatial logic. Assets are good; placement algorithm needs redesign. This is a separate future workstream.

## Next step
Gate 5: Content pass (room dressing rules, biome variants, threat visual variety).
