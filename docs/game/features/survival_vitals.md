# Feature: Survival Vitals

## Source
- Package plan: `docs/game/build-plans/01-survival-vitals-e2e.md`
- Requirement range: REQ-SV-001..008

## Concept
A Project-Zomboid-style moodle/vitals stack adapted to space horror: oxygen, health, stamina, hunger, thirst, temperature, radiation, sanity, and their cascade rules.

## Scope
- VitalsState: health, stamina, hunger, thirst with deterministic drain/recovery.
- SanityState: sanity drain/recovery with perception/hallucination pressure.
- RadiationState: radiation accumulation, decay, and health damage.
- BodyTemperatureState: temperature tracking with thirst impact.
- StatusEffectsState: active status effects registry.
- HUD: bottom-left panel expanded for all vitals with severity colors/icons.
- Persistence: save/load preserves non-default vitals and active status effects.
- Difficulty scaling: drain rates scale per difficulty preset.

## Out of scope
- Final art assets (placeholder icons/colors are sufficient).
- Full audio feedback for every vital (event seams only).
- Save migration for vitals fields (additive-only; missing fields default safely).

## Cascade rules
1. Hunger below 30% reduces stamina recovery by 50%.
2. Thirst below 20% reduces vision/readability (communicated to HUD as a warning).
3. Sanity below 40% applies perception/hallucination pressure (communicated to HUD).
4. Radiation above 50% causes passive health drain.
5. Body temperature outside safe range [18, 32] increases thirst drain.

## Acceptance criteria
- All vitals drain/recover under deterministic tuning.
- At least three cascade interactions are live: hunger->stamina, thirst->vision, sanity->perception.
- Save/load preserves non-default vitals and active status effects.
- HUD communicates every critical state without opening a menu.

## Verification
- `scripts/validation/vitals_state_smoke.gd` -> `VITALS STATE PASS`
- `scripts/validation/sanity_state_smoke.gd` -> `SANITY STATE PASS`
- `scripts/validation/radiation_state_smoke.gd` -> `RADIATION STATE PASS`
- `scripts/validation/main_playable_slice_vitals_full_smoke.gd` -> `MAIN PLAYABLE VITALS FULL PASS`
- `scripts/validation/vitals_state_save_load_smoke.gd` -> validates round-trip persistence.
