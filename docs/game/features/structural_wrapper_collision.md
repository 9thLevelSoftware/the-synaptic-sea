# Feature: Structural wrapper collision matches walkability contract

## Status

Validated

## Design pillar alignment

- Pillar: derelict exploration in enclosed, walkable ship volumes.
- Why this feature supports it: compiler-true walkability is not play until live wall and doorway proxies have the same 0.20 m slabs and 1.20 m standing opening the capsule sweep already assumes.

## Player fantasy

A suited body stops at a bulkhead plate. An open frame lets you through at standing height. You do not clip a 1 m cube that used to stand in for a wall.

## Gameplay problem

`ship_structural_v0` wall and doorway wrappers still used `BoxShape3D(1, 1, 1)`. Contract Z thickness is 0, so “match the contract AABB” is not a single box, and Godot cannot cut a hole in one box. Corner/T modules occupy a 4×4 footprint with two or three SOLID wings. Walkability Stage A extrudes per-edge 0.20 m slabs; live collision did not.

## Core behavior

Per-wrapper collision proxies, numbers from `walkability_contract.gd`:

| Wrapper | Collision |
|---|---|
| `wall_straight_1x1`, `wall_end_cap` | one `BoxShape3D(4.0, 3.0, 0.2)` at edge-center |
| `wall_inner_corner`, `wall_outer_corner` | two `BoxShape3D(4.0, 3.0, 0.2)` slabs, north and east SOLID wings |
| `wall_t_junction` | three `BoxShape3D(4.0, 3.0, 0.2)` slabs, north/east/west SOLID wings |
| `doorway_frame_blocked_1x1` | one `BoxShape3D(4.0, 3.2, 0.2)` full slab |
| `doorway_frame_open_1x1` | two posts `BoxShape3D(1.4, 3.2, 0.2)` at local X ±1.3 m, plus header `BoxShape3D(4.0, 1.0, 0.2)` with bottom at Y=2.2 m |

Open-doorway aperture is ~1.2 × 2.2 m. Standing capsule 0.80 × 1.70 must pass. `bulkhead_portal_2x1` is unchanged.

## Inputs

- `WalkabilityContract.SLAB_THICKNESS_M` / `DOOR_OPENING_WIDTH_M` / doorway proxy constants
- Wrapper scenes under `scenes/wrappers/structural/ship_structural_v0/`

## Outputs

- Live `StaticBody3D` proxies that block SOLID plates and thread open frames
- Smoke marker `STRUCTURAL WRAPPER COLLISION FOOTPRINT PASS walls=true corners=true doors=true aperture=true thickness=0.2 hatch_skipped=true`

## Rules

1. Per wrapper, not “every SOLID.” Compiler still emits `wall_straight_1x1` per edge; corner/T proxies exist for those modules.
2. Prefer compound wing slabs over a 4×3×4 AABB so each SOLID wing is a 0.20 m plate.
3. Doorway opening is posts + header; do not fake an opening with one box.
4. Hatch 2×1 stays out of this card.

## Non-goals

- Layout mutators / live LOCKED stamping
- GLB authoring or unique meshes
- `bulkhead_portal_2x1.tscn` / HATCH collision retune
- ithappy wrapper kit
- Crouch as a smaller live capsule

## Technical design

- Wrapper `.tscn` collision under `CollisionRoot`
- Shared numbers in `scripts/procgen/walkability_contract.gd`
- Smoke: `scripts/validation/structural_wrapper_collision_footprint_smoke.gd`
- REQ-DECAY-002

## Acceptance criteria

- Given `wall_straight_1x1` / `wall_end_cap`, when the wrapper instantiates, then it has one `BoxShape3D(4, 3, 0.2)` at edge-center.
- Given inner/outer corner wrappers, when they instantiate, then each has two wing slabs of `(4, 3, 0.2)` on north and east socket axes.
- Given `wall_t_junction`, when it instantiates, then it has three wing slabs on north/east/west socket axes.
- Given `doorway_frame_open_1x1`, when it instantiates, then posts sit at X ±1.3 m, header bottom is Y=2.2 m, and a 0.80×1.70 standing opening is clear.
- Given `doorway_frame_blocked_1x1`, when it instantiates, then it is a full `BoxShape3D(4, 3.2, 0.2)` slab.
- Given `bulkhead_portal_2x1`, when the smoke runs, then its proxy is unchanged.

## Validation

```
GODOT="C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe"
ROOT="<project root>"
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/structural_wrapper_collision_footprint_smoke.gd
```

Expected: `STRUCTURAL WRAPPER COLLISION FOOTPRINT PASS walls=true corners=true doors=true aperture=true thickness=0.2 hatch_skipped=true`

## Risks

- A 4×3×4 corner AABB would fill an occupied cell; compound wings avoid that.
- Adding CollisionShape3D nodes changes loader `collision_shapes=` pins; update those pins from fresh output.
- Stage A still extrudes compiler edge bounds, not these meshes. Live physics and Stage A can diverge if a later card places corner modules on a different origin.

## ADRs

- ADR-0054 compiler-edge nav and walkability (consumed numbers)
- ADR-0053 socketed enclosed interiors (consumed)
