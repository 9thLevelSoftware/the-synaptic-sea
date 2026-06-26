# Combat / Threat AI Contract Review

Date: 2026-06-25
Task: `t_cbe56420`
Source package: `docs/game/build-plans/06-combat-threat-ai-e2e.md`

## Contract check
- Damage pipeline exists as a pure model (`scripts/systems/damage_pipeline.gd`) and passes its focused smoke.
- Armor, status effects, detection, and threat AI each have dedicated pure-model coverage.
- `PlayableGeneratedShip` exposes a save/load-capable combat encounter seam through `scripts/validation/main_playable_slice_combat_encounter_smoke.gd`.
- `ThreatManager` summary round-trip persists per-threat memory, world position, and last attack result.
- Weapon/ammo mapping mismatch on the shock-probe path was corrected in `PlayableGeneratedShip` so equipped item ids resolve to the correct combat weapon id and ammo id during runtime.

## Focused evidence
- `DAMAGE PIPELINE PASS vitals=65.0 threat=19.0 absorbed=10.0 status=true`
- `ARMOR RESOLVER PASS final=6.0 durability=18.0 fire=11.0`
- `STATUS EFFECTS PASS count=2 expired=true modifier=1.00`
- `DETECTION STATE PASS score=0.00 memory=0.0 reason=memory`
- `THREAT AI STATE PASS final_state=dead previous=hunt awareness=0.00`
- `MAIN PLAYABLE COMBAT ENCOUNTER PASS archetypes=5 awareness=1.07 ammo_spent=1 memory_restored=true`

## Caveats
- This package still uses placeholder threat visuals and HUD-only weapon feedback; final juice/audio polish is intentionally out of scope for Task 06.
- Death/respawn and hub/meta consequences remain outside the Task 06 contract.
