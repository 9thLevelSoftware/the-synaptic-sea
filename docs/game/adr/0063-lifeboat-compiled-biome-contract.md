# ADR-0063: Lifeboat biome selection follows the compiled structural contract

- Status: Accepted; implementation pending.
- Date: 2026-09-05
- Requirements: REQ-ENC-004 (documentation-stale); preserves REQ-ENC-001..003.
- Source: `docs/game/features/remaining_procgen_play_stack.md`, Work Package 4,
  especially lines 418-461.

## Context

`main_playable_lifeboat_biome_skin_smoke.gd` currently treats wrapper node names
as module stems and compares them to `KitCatalog.role_modules`. That is not the
live compiled contract. `LifeBoatBuilder` is off the deprecated
`StructuralPlacer`: `StructuralEdgeCompiler` emits canonical floor, edge, and
ceiling records and `LifeBoatBuilder._instance_plan_records` names wrapper roots
from each record's `placement_id`. Names such as `floor_0_0` and `edge_0_h_-1`
are placement identities, not module identities.

The resolved biome is already passed to `LifeBoatBuilder.build(biome)`, which
selects a layout `kit_id`. Hazard and industrial kits currently contain catalog
`role_modules` but no wrapper map and no modular-contract directory.
`ModularSocketCatalog` and the wrapper map therefore deliberately fall back to
`ship_structural_v0`. This preserves compiled occupancy, enclosure, socket
positions, and valid wrapper instancing. It does not yet provide a visual
biome remap. REQ-ENC-004's claim that stems already remap is stale; its remaining
loader/theme work is tracked as P23 evidence.

## Decision

The lifeboat validation will test the current compiled truth without reviving
`StructuralPlacer` or projecting role-module lists into geometry:

1. The live lifeboat is built with the same resolved biome passed to both
   `LifeBoatBuilder.build` and its retained `built_layout`.
2. For each of abyssal, breach-field, and dead-fleet inputs, `build_layout`
   selects the documented `kit_id` (`v0`, `hazard`, `industrial`) and compiles
   an unchanged valid three-room enclosure.
3. Every live wrapper exposes metadata for the compiled record's `module_id`
   and source wrapper path. The test compares that metadata to the associated
   compiled-plan record, never to a placement name.
4. The live wrapper map is the resolved map used by the builder. When a selected
   kit has no wrapper map, the test asserts the deliberate v0 fallback and
   reports it as fallback; it does not claim a distinct visual skin.
5. Existing marker text remains compatible:
   `MAIN PLAYABLE LIFEBOAT BIOME SKIN PASS biomes=3 live_match=true reachable=true`.
   `live_match` means compiled record-to-wrapper agreement, not unique themed
   meshes.

No role-module list is used to alter compiled geometry. No kit data, meshes,
material tints, occupancy, or socket contracts are added by this decision.

## Consequences

The smoke continues to prove live lifeboat reachability and biome-to-kit-id
selection while accurately describing the v0 wrapper fallback. It no longer
creates a false failure by comparing placement IDs to catalog role-module IDs.
A future P23/REQ-ENC-004 implementation may add kit wrapper maps and contracts;
then the same assertions will automatically require a non-fallback resolved map
without changing topology.

## Acceptance for the pending implementation

- `life_boat.gd` attaches compiled `module_id` and resolved wrapper-path metadata
  to every instantiated structural wrapper.
- `playable_generated_ship.gd` retains `LifeBoatBuilder.build_layout` using the
  exact biome used for the live build.
- The smoke checks all three selected kit ids, valid compiled enclosure/room
  occupancy, live wrapper metadata against the active compiled plan, and the
  declared v0 fallback for hazard/industrial.
- The smoke preserves its existing PASS marker and remains headless leak-free.