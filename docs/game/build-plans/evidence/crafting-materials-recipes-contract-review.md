# Crafting / Materials / Recipes Contract Review

Source plan: `docs/game/build-plans/03-crafting-materials-recipes-e2e.md`
Reviewed against: `AGENTS.md`, `docs/game/05_requirements.md`, `docs/game/06_validation_plan.md`, `docs/SYNAPTIC_SEA_COMPLETE_SYSTEMS_MAP.md`

## Existing extension seams

- Pure crafting models already present: `scripts/systems/material_state.gd`, `crafting_state.gd`, `station_state.gd`, `field_crafting_state.gd`, `deconstruction_resolver.gd`, `quality_tier_resolver.gd`
- Data catalogs already present: `data/materials/material_definitions.json`, `data/recipes/recipe_definitions.json`
- Validation harness already present: focused smokes under `scripts/validation/`
- Persistence seam already present: `RunSnapshot` / `SaveLoadService`

## Gaps closed by this package pass

- `CraftingState` had headless compile/type issues around station typing.
- `FieldCraftingState` configured its synthetic station as unpowered, which paused the craft instead of progressing it.
- `StationState` queue-advance semantics were out of sync with the station smoke's pause/resume contract.
- `RunSnapshot` did not carry `crafting_summary` / `material_summary`, so the original crafting smoke used an out-of-band local variable instead of a real save/load round-trip.
- Task-03 paperwork (feature spec, ADR, balance note, requirements, validation registration, risk/system-map closeout) was missing.

## Chosen seams

- Keep crafting persistence additive on `RunSnapshot`; do not add a separate crafting save file.
- Keep all station progression pure-model-side; do not push queue/progress logic into scene nodes.
- Reuse the main-scene smoke harness pattern from other packages instead of bespoke direct `SceneTree.add_child` misuse.
