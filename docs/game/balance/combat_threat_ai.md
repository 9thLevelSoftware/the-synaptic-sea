# Combat / Threat AI Balance Baseline

Date: 2026-06-25
Source package: Task 06 (`docs/game/build-plans/06-combat-threat-ai-e2e.md`)

## Current baseline
- Threat roster: 5 archetypes (`biomatter_swarm`, `puppet_corpse`, `stalker`, `mimic`, `hull_tendril`)
- Weapon roster: `crowbar`, `flare_pistol`, `shock_probe`, `welding_lance`
- Ammo/resource links:
  - `flare_pistol` -> `flare_round`
  - `shock_probe` -> `capacitor_cell`
  - `welding_lance` -> `fuel_canister`
- Main playable combat smoke baseline: `awareness=1.07`, `ammo_spent=1`, `archetypes=5`
- Damage smoke baseline: `vitals=65.0`, `threat=19.0`, `absorbed=10.0`, `status=true`

## Tuning intent
- Melee (`crowbar`) is the always-available fallback and should never require ammo.
- Ranged/tool weapons trade inventory pressure for faster awareness spikes and control effects.
- Threat memory should last long enough to preserve pressure through save/load, but not so long that every missed shot hard-locks the run into permanent combat.
- Archetypes should remain distinct by pressure profile: swarm = numbers, puppet = bruiser, stalker = stealth, mimic = ambush, hull_tendril = anchored area denial.

## Guardrails
- Do not ship a tuning change without re-running the six Task 06 smokes.
- If a tuning change alters the main playable smoke marker materially, update this baseline and the evidence note in the same change.
- Keep encounter persistence additive; never reset live threat state on load just to make balance easier.
