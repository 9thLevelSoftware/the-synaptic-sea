# ADR-0034: Survival Vitals Architecture

## Status
Accepted

## Context
Task 01 requires a complete Project-Zomboid-style moodle/vitals stack adapted to space horror. The existing codebase has `OxygenState`, `FireState`, `ElectricalArcState`, `PlayerVitalsModel`, and `PlayerVitalsPanel`, but no health, stamina, hunger, thirst, sanity, radiation, temperature, or status-effects system.

## Decision
Add five new pure `RefCounted` models and wire them into `PlayableGeneratedShip`, `PlayerVitalsModel`, `PlayerVitalsPanel`, `RunSnapshot`, and save/load.

### Models
1. `VitalsState` — health, stamina, hunger, thirst with cascade rules (hunger->stamina, thirst->vision).
2. `SanityState` — sanity drain/recovery with perception/hallucination pressure below 40%.
3. `RadiationState` — radiation accumulation/decay with passive health drain above 50%.
4. `BodyTemperatureState` — temperature tracking with thirst-drain multiplier when outside safe range.
5. `StatusEffectsState` — active effect registry with duration/stacks and stat modifiers.

### Integration rules
- `PlayableGeneratedShip._process()` ticks all five models each frame.
- Cascades are computed in `_process` and passed via `context` dictionaries.
- `PlayerVitalsModel` receives summaries from all five models and composes HUD lines.
- `RunSnapshot` carries five new summary fields; save/load applies them on restore.
- `_reset_runtime_for_reload()` resets all five models to defaults before snapshot re-application.

## Consequences
- HUD now displays 7+ vital categories without opening a menu.
- Three cascade interactions are live: hunger->stamina, thirst->vision, sanity->perception.
- Save/load preserves non-default vitals and active status effects.
- No scene-tree access in any pure model.

## Risks
- Performance: five extra `tick()` calls per frame; negligible for `RefCounted` math.
- Save compatibility: older snapshots missing the five new fields load with empty defaults; the models start at their configured defaults.
