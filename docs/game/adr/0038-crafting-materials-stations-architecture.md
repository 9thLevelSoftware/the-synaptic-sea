# ADR-0038: Crafting, Materials & Station Architecture

Status: Accepted
Date: 2026-06-26

## Context

Task 03 needs a complete crafting economy, but the repository already has strong constraints: pure gameplay state should stay out of the scene tree, save/load changes must remain additive, and shipboard stations must respect power availability and upgrade levels. The package also needs field crafting and deconstruction without collapsing everything into `PlayableGeneratedShip`.

## Decision

1. Keep the crafting package pure-model first:
   - `MaterialState` owns catalog + quality tracking.
   - `CraftingState` owns recipes, ingredient transactions, active craft summaries, and station lookup.
   - `StationState` owns queue/progress/power/level state.
   - `FieldCraftingState` wraps `CraftingState` for the limited emergency recipe subset.
   - `DeconstructionResolver` is a recipe-backed material-yield seam.
2. Store recipe/material tuning in additive JSON catalogs (`data/materials/material_definitions.json`, `data/recipes/recipe_definitions.json`) so content and balance move without scene rewrites.
3. Resolve quality deterministically from four inputs: ingredient quality, player skill level, station level, and station power. Field crafting deliberately omits the powered-station bonus.
4. Persist current-run crafting additively by extending `RunSnapshot` with `crafting_summary` and `material_summary`. Older saves that lack the fields load with empty defaults.
5. Let station queue progression live on `StationState` so pause/resume and save/load semantics are shared between shipboard crafting and field-craft restoration.

## Consequences

- The crafting package is headless-testable through pure-model smokes.
- Designers can ship 50+ recipes and 30+ materials without touching runtime code.
- Mid-craft save/load is a first-class contract rather than a smoke-local side channel.
- `PlayableGeneratedShip` stays an orchestrator instead of a recipe engine.

## Rejected alternatives

- Put per-recipe behavior directly on interactable station nodes. Rejected: too scene-bound, hard to test headlessly, and poor for save/load.
- Keep crafting persistence outside `RunSnapshot` as ad-hoc smoke data. Rejected: not production-grade and does not satisfy the package acceptance criteria.
- Split field crafting into a wholly separate recipe catalog. Rejected: same schema with a `station_kind == field_crafting` subset is simpler and deterministic.

## Superseded in part (Domain 4, 2026-06-30)

The "powered-station crafts pause while the player is away on a derelict" behavior
was an emergent side-effect of `_recompute_expanded_ship_systems` running only on the
home `_process` branch — not a deliberate architectural rule. Domain 4 makes the ship
sim live on both branches (`docs/superpowers/specs/2026-06-30-domain4-ship-systems-design.md`),
so powered stations now advance while away as well. Field crafting remains the
unpowered/portable path and is unchanged.
