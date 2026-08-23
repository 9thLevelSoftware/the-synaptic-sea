# Feature: Enclosed slot fill

## Status

In implementation — REQ-FILL-001.

## Requirement cross-reference

- REQ-FILL-001 in `docs/game/05_requirements.md`
- Design: `docs/game/features/remaining_procgen_play_stack.md` work package 3
- Related: `docs/game/features/component_slots.md`, ADR-0053

## Design pillar alignment

- Pillar: salvage / derelict interiors that read as enclosed rooms, not floor plates.
- Why: WallDoorResolver already emits `wall_slots` / `center_slots`; live fill still dumped loot on the first `floor_cell_*`.

## Player fantasy

Crates sit against bulkheads. Salvage is in the room, not stacked in the doorway. Clutter is dressing, not a unique named affordance.

## Gameplay problem

`GameplaySliceBuilder._get_first_floor_cell` parked salvage and loot on the first floor placement. `ComponentPlacementState._extract_slots` never read `room.interior_zones`. Serializer wall-slot cells collapsed to `"(x, y)"` strings after JSON. Component markers jittered from room centers. Dressing was fog/light only.

## Core behavior

- Serializer emits every interior-zone slot cell as `[x, z]`.
- Slot consumers read `room.interior_zones.{wall_slots,center_slots,reserved_cells}` first; parse both `[x, z]` and `"(x, y)"`.
- Loot prefers unused `center_slots` then unused `wall_slots`.
- Salvage approach prefers center slots adjacent to reserved cells, else reserved portal cells.
- One occupant per slot. No reserved-cell loot. No start-room boarding cell.
- Fallback remains first floor cell and logs `slot_fallback` (goldens / empty zones).
- Dressing props (`DressingProp_<room>_<index>`) occupy unused wall slots scaled by `prop_density`. Lights/fog stay at room center. `collision_policy=none_visual_only`.
- Component markers use slot cells, not center+jitter.
- Slots are compile-time SOLID-wall cells. Do not re-resolve after BREACH overlay.

## Inputs

- Layout rooms with `interior_zones` from WallDoorResolver
- Gameplay slice builder seed from `program_id` / `seed_value`
- Room variant `prop_density` presets

## Outputs

- `gameplay_slice` loot/objectives with `approach_cell` on a slot plus optional `slot_kind` / `slot_index`
- Dressing props parented under `DressingVisuals`
- Component markers at slot world positions

## Rules

1. Iterate slots in serialized order. RNG is `seed_value XOR room_index`.
2. One occupant per slot.
3. Do not place loot/components/dressing in `reserved_cells`.
4. Do not place on the start-room boarding cell.
5. No `layout.json` version bump. Optional keys stay inside existing gameplay_slice objects.
6. Do not use `ReadabilityPropFactory` unique affordance names for clutter.

## Non-goals

- New machine art
- Loot table redesign
- Ship-mod UI
- Re-resolving slots after BREACH overlay

## Technical design

- `scripts/procgen/layout_serializer.gd`
- `scripts/procgen/gameplay_slice_builder.gd`
- `scripts/procgen/generated_ship_loader.gd`
- `scripts/procgen/playable_generated_ship.gd`
- `scripts/systems/component_placement_state.gd`

## Acceptance criteria

- Given a generated room with `interior_zones`, when the slice builds, then loot `approach_cell` equals a center or wall slot and is not the first `floor_cell_*` unless that cell is the chosen slot.
- Given `interior_zones` present, when components populate, then placements store parsed slot cells and markers sit on those cells.
- Given a dressed room, when the loader applies visuals, then `DressingProp_<room>_<index>` instances exist and lights/fog remain at room center.

## Validation

```
GODOT="C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe"
ROOT="<project root>"
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/enclosed_slot_fill_smoke.gd
```

Expected: `ENCLOSED SLOT FILL PASS loot_on_slot=true no_floor_dump=true components_on_cell=true dressing=true`

Existing component slot smokes remain green.

## Risks

- Goldens without `interior_zones` must keep synthesis. Mitigation: synthesize only when `interior_zones` is missing or empty.
- JSON round-trip of Vector2i wall cells. Mitigation: serializer always writes `[x, z]`.

## ADRs

- `docs/game/adr/0053-socketed-enclosed-interiors.md` (slots exist)
- `docs/game/adr/0052-asset-metadata-and-visual-binding-architecture.md` (`none_visual_only`)
