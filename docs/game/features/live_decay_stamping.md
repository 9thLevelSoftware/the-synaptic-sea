# Feature: Live decay overlays and wreck module stamps

## Status

Validated

## Design pillar alignment

- Pillar: boarded derelicts look and play as wrecks, not pristine kits.
- Why this feature supports it: `Condition.DAMAGED` / `WRECKED` generation now overlays locked doors and pre-damaged wrappers on the live compile path, not only in a mutator unit smoke.

## Player fantasy

A damaged ship has welded-shut doors and torn plating. You walk the standing route around a lock. Breached frames are holes, not extra rooms.

## Gameplay problem

Serializer always wrote `portals[].state = DOOR` and `blocked_links = []`. The loader hard-set `integrity_state = intact`. `LayoutMutator` only ran in `templates_wreck_mutator_smoke`. Live wrecks looked pristine. Deleting `room_links` false-failed `_layout_is_connected` on DAMAGED quality-gate seeds.

## Core behavior

Live mutators are overlays:

- Keep every hop in `room_links`.
- Copy blocked hops into `blocked_links` (`module_id = doorway_frame_blocked_1x1`, `reason = branch_mutator`).
- Matching `portals[].state = LOCKED` (and one non-critical existing `DOOR` → `BREACH` on WRECKED).
- Cap remains `links.size()/4`. Overlay protects every `critical_path` hop so standing start→goal survives.
- `_layout_is_connected` stays room-link BFS.

Compile order inside `ShipLayoutGenerator._generate_once`:

1. Serialize + occupancy/portals.
2. Overlay branch locks / optional BREACH.
3. Compile + validate (`structural_plan_validated`).
4. Immediately `_apply_wreck_to_compiled_plan` keyed by `floor/<cell_key>`, `edge/<edge_key>`, `ceiling/<cell_key>` plus `placement_id`.

`ShipGenerator._load_layout_as_scene` skips recompile when a validated plan exists and does not stamp wreck again. Loader sets `integrity_state` from `module_damage` and calls only `IntegrityVisualResolver.apply_visual_state`. Coordinator seeds `ModuleIntegrityMap` from those keys and finds wrappers by meta `module_key`.

## Inputs

- `ShipBlueprint.condition` (`PRISTINE` skips mutators)
- Compiled `structural_plan` occupancy / placements
- Wrapper Intact/Damaged/Breached children

## Outputs

- `blocked_links`, `portals[].state`, `module_damage`, `wreck_applied`
- LOCKED compiler edges (`doorway_frame_blocked_1x1`)
- Non-intact wrapper children visible on wrecked ships

## Rules

1. Do not delete `room_links`.
2. Never insert a portal or occupancy for BREACH. Convert an existing non-critical DOOR only.
3. Stamp wreck after the last compile. Do not restamp on load.
4. Variant wrappers: `IntegrityVisualResolver` only — no albedo tint fight.
5. Damaged/breached `ext_resource` fallbacks point at intact GLBs when imports fail. Do not allowlist those ERRORs.

## Non-goals

- Wrapper collision retune (PR 2b)
- Hive meshes / kit remap
- Slot fill
- Hub boot (`scripts/main.gd`)
- `unlock_edge`

## Technical design

- `scripts/procgen/layout_mutator.gd` — `apply_branch_overlays`, `apply_portal_overlays`, `apply_wreck_to_compiled_plan`
- `scripts/procgen/ship_layout_generator.gd` — overlay then compile then wreck
- `scripts/procgen/ship_generator.gd` — skip duplicate compile
- `scripts/procgen/generated_ship_loader.gd` — integrity visuals from `module_damage`
- `scripts/procgen/playable_generated_ship.gd` — meta finder; seed map from `module_damage`
- `scripts/systems/module_integrity_consequences.gd` — skip albedo on variant wrappers
- Wrapper `.tscn` Intact/Damaged/Breached children (blocked frame reuses intact GLB)

## Acceptance criteria

- Given a DAMAGED generated layout, when quality-gate runs, then room-links stay connected, standing start→goal exists, `wreck_applied` is true, and blocked hops remain in `room_links`.
- Given a WRECKED generated layout, when the live loader instantiates, then at least one wrapper `integrity_state != intact` with Damaged or Breached child visible.
- Given overlay locks, when `_layout_is_connected` runs, then every room id is still reachable via `room_links`.
- Given a variant wrapper, when wreck visuals apply, then `IntegrityVisualResolver` toggles children and albedo tint is not applied.

## Validation

```
GODOT="C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe"
ROOT="<project root>"
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/live_decay_stamp_smoke.gd
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/structural_variant_wrapper_smoke.gd
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/templates_wreck_mutator_smoke.gd
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/procgen_quality_gate_smoke.gd
```

Expected:

- `LIVE DECAY STAMP PASS locked=true wreck=true integrity=true links_kept=true quiet_import=true`
- `STRUCTURAL VARIANT WRAPPER PASS wrappers=8 intact=true damaged=true breached=true`
- `TEMPLATES WRECK MUTATOR PASS catalog=true load=true zone=true branch=true wreck=true`
- `PROCGEN QUALITY GATE PASS` (wreck stamps on DAMAGED)

## Risks

- Deleting `room_links` false-fails DAMAGED quality-gate connectivity — overlays only.
- Stamping wreck only on the loader path makes quality-gate `wreck_applied` dead — stamp in `_generate_once` after compile.
- Damaged GLB import ERRORs — retarget `ext_resource` to intact; do not allowlist.

## ADRs

- ADR-0051 module integrity not voxels
- ADR-0052 asset metadata and visual binding
- ADR-0054 compiler-edge nav (LOCKED/BREACH at `BLOCKED_COST`)
