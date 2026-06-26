# ADR-0034: Food, Cooking, Spoilage & Sustenance Architecture

## Status
Approved

## Context
Task 02 requires a complete food economy: rations, scavenged food, alien flora, cooked meals, spoilage, cooking stations, synthesizer, hydroponics, and water handling. The existing codebase has `VitalsState` (hunger/thirst), `SanityState`, and `InventoryState`, but no food-specific models. We need to add pure-model state that integrates with inventory, vitals, and save/load.

## Decision

1. **Pure-model-first**: All new state lives in `RefCounted` classes that never touch the scene tree.
2. **Six new models**:
   - `FoodState` — per-item freshness (Fresh/Stale/Rotten) with consumable effects.
   - `SpoilageState` — aggregates `FoodState` instances, ticks spoilage, reports transitions.
   - `CookingState` — station state machine (IDLE/COOKING/COMPLETE) with ingredient/power consumption.
   - `HydroponicsState` — timed growth cycle (IDLE/PLANTED/HARVESTABLE) with water/power costs.
   - `SynthesizerState` — thin wrapper over `CookingState` with synthesizer-specific UI/status.
   - `WaterRecyclerState` — converts contaminated water to purified water over time.
3. **Data sources**:
   - `data/items/food_definitions.json` — food item stats (restores, spoilage times, multipliers).
   - `data/recipes/cooking_recipes.json` — recipe ingredients, power costs, cook times.
   - `data/crops/hydroponics_crops.json` — crop growth times, yields, costs.
4. **Save/load integration**:
   - `RunSnapshot` gains four new summary fields: `spoilage_summary`, `cooking_summary`, `hydroponics_summary`, `synthesizer_summary`.
   - `PlayableGeneratedShip` owns the instances, ticks them per-frame, and captures/restores them in `_build_run_snapshot` / `_load_run_snapshot`.
5. **Vitals integration**:
   - `SpoilageState` is queried when food is consumed; `VitalsState.apply_food_effect(hunger, thirst, sanity)` updates the live vitals.
   - Rotten food sickness risk is rolled against `VitalsState` (future sickness model; for now, logged in status lines).
6. **Skill integration**:
   - `CookingState` checks `player_progression.get_skill_level("cooking")` against `required_skill_level`.
   - `HydroponicsState` and `SynthesizerState` also gate on cooking skill.

## Consequences

- **Positive**: Food economy is deterministic, testable, and persists across save/load.
- **Positive**: Spoilage stages directly affect hunger/thirst/sanity restoration values.
- **Positive**: Cooking produces real inventory items that can be consumed or spoiled.
- **Negative**: `RunSnapshot.SUMMARY_FIELDS` grows from 9 to 13, requiring updates to save/load smokes.
- **Negative**: `PlayableGeneratedShip` gains four new model references, increasing its state surface.

## Validation

- `food_state_smoke.gd` — `FOOD STATE PASS`
- `spoilage_state_smoke.gd` — `SPOILAGE STATE PASS`
- `cooking_state_smoke.gd` — `COOKING STATE PASS`
- `hydroponics_state_smoke.gd` — `HYDROPONICS STATE PASS`
- `main_playable_slice_cooking_smoke.gd` — `MAIN PLAYABLE COOKING PASS`
- `food_save_load_smoke.gd` — `FOOD SAVE LOAD PASS`
