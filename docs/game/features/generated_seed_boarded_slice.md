# Feature: Boarded generated-seed vertical slice

## Status

Validated — REQ-SLICE-001.

## Requirement cross-reference

- REQ-SLICE-001 in `docs/game/05_requirements.md`
- Design: `docs/game/features/remaining_procgen_play_stack.md` work package 5
- Related: `docs/game/features/vertical_slice_v1.md` (hub remains golden `coherent_ship_001`)

## Design pillar alignment

- Pillar: raid a hostile generated derelict, not a hand-authored golden.
- Why this feature supports it: walkability, live decay, wrapper collision, and slot fill are only play once a production `travel_to` boarding attaches `current_ship` and enters the away `_process` branch.

## Player fantasy

You leave the hub, dock a wreck the generator built, and the interior is a standing route with loot in the rooms.

## Gameplay problem

`generate_from_seed` returns a loader `Node3D` and does not attach `current_ship` or enter the away `_process` branch. Flag-flipping `away_from_start` hides that. `main_playable_derelict_pipeline_contract_smoke.gd` generates a layout without boarding.

## Core behavior

Headless `travel_to_marker_id` boarding copied from `away_branch_integrity_smoke.gd`:

1. Instantiate `res://scenes/main.tscn`. Wait until `playable_started` and hub loader `has_loaded_ship()`.
2. Repair `power`, `navigation`, `scanners`, `propulsion`.
3. `travel_to_marker_id` on the first in-range marker. Do not overwrite `seed_value` / `condition`. First away jump keeps `first_run_contract`.
4. `away_from_start` is true as a result of `_attach_derelict_active`. `current_ship.scene_root` is a loaded `GeneratedShipLoader` whose layout is not `coherent_ship_001`.
5. Layout `schema_version == 1.2.0`, enclosure validator ok, `ShipNavGraph` standing path start→goal, at least one objective spec, at least one loot spec on an `interior_zones` center or wall slot, wreck overlay when the boarded condition is DAMAGED/WRECKED.
6. Thirty away `_process` ticks. HUD/objective surface still alive. No extract assertion.

## Inputs

- Production travel path (`travel_to` → `_attach_derelict_active`)
- First-run contract preferred seeds `[42, 777]`
- Boarded `built_layout` / loader layout copy

## Outputs

- Away boarded generated wreck (`away_from_start=true`)
- Standing nav, slot loot, wreck overlay, objectives, `away_ticks=30`

## Rules

1. Do not change `scripts/main.gd`. Hub stays `coherent_ship_001`.
2. Do not assign `away_from_start = true` in the test.
3. Do not skip or null `first_run_contract`.
4. Do not pin `seed=42` in the PASS / `run_clean` prefix. Print `seed=` as informational.
5. Timeout 300 frames.

## Non-goals

- Replacing New Game hub / changing `scripts/main.gd`
- Extract/return-home assertion
- Skipping `first_run_contract`
- Title-flow rewrite
- 20-minute content script
- Occupancy-out, second loader, schema rewrite, WFC, unique hive meshes

## Technical design

- `scripts/validation/generated_seed_boarded_slice_smoke.gd`
- Production attach path already in `scripts/procgen/playable_generated_ship.gd`

## Acceptance criteria

- Given the main scene hub, when the smoke boards via `travel_to_marker_id`, then `away_from_start` is true from `_attach_derelict_active` and the boarded layout is a generated wreck, not `coherent_ship_001`.
- Given that boarded layout, when nav/slots/wreck/objectives are read, then standing start→goal exists, at least one loot spec sits on an interior slot, wreck overlay is present for DAMAGED/WRECKED, and at least one objective spec exists.
- Given 30 away `_process` ticks, when HUD/objective surface is queried, then `get_combined_system_status_lines()` is non-empty or `complete_objective_sequence_for_validation(1)` succeeds.

## Validation

```
GODOT="C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe"
ROOT="<project root>"
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/generated_seed_boarded_slice_smoke.gd
```

Expected: `GENERATED SEED BOARDED SLICE PASS away=true nav=true slots=true wreck=true objectives=true away_ticks=30`

`seed=` may appear on the same line as informational.

## Risks

- First-run contract may pick 777 when 42 fails validate. Mitigation: do not pin `seed=42`.
- Away-branch `_process` early-return. Mitigation: assert `away_from_start` from the travel attach path and tick 30 away frames.

## ADRs

- ADR-0054 compiler-edge nav
- ADR-0053 socketed enclosed interiors (slots)
- No new ADR: this is a validation proof, not an architecture change.
