# Feature: Combat, Threat AI, Damage, Stealth & Encounters

## Source
- Package plan: `docs/game/build-plans/06-combat-threat-ai-e2e.md`
- Requirement range: REQ-D-001..018
- ADR-0037

## Concept
A hostile-derelict combat layer that keeps damage, armor, status effects, detection, threat AI, encounter spawning, and weapon feedback in pure models while `PlayableGeneratedShip` applies the runtime consequences in the main playable slice.

## Scope
- `DamagePipeline`, `ArmorResolver`, `StatusEffectsState`, `DetectionState`, `ThreatAIState`, and `ThreatManager` implement deterministic combat/threat logic.
- `data/combat/*.json` defines threat archetypes, weapon stats, ammo links, and status-effect tuning.
- `PlayableGeneratedShip` owns the live `ThreatManager`, weapon hotbar text, ammo spend, save/load persistence, and cross-ship combat-summary restoration.
- The playable slice exposes at least five threat archetypes through one shared AI contract and saves/restores their positions, phases, detection memory, and last combat result.

## Out of scope
- Death/respawn UI, permadeath decisions, or hub/meta consequences.
- Final art/audio juice beyond placeholder threat silhouettes and HUD text.
- Networked combat, squad allies, or boss-only bespoke AI trees.

## Acceptance criteria
- At least five threat archetypes spawn through one shared `ThreatAIState` contract.
- Noise, light, and sight all change detection state and threat awareness.
- Player weapon use consumes ammo/resources, raises threat awareness, and updates HUD feedback.
- Threat positions, phases, memory, and last attack state survive save/load and ship travel.

## Verification
- `scripts/validation/damage_pipeline_smoke.gd` -> `DAMAGE PIPELINE PASS`
- `scripts/validation/armor_resolver_smoke.gd` -> `ARMOR RESOLVER PASS`
- `scripts/validation/status_effects_smoke.gd` -> `STATUS EFFECTS PASS`
- `scripts/validation/detection_state_smoke.gd` -> `DETECTION STATE PASS`
- `scripts/validation/threat_ai_state_smoke.gd` -> `THREAT AI STATE PASS`
- `scripts/validation/main_playable_slice_combat_encounter_smoke.gd` -> `MAIN PLAYABLE COMBAT ENCOUNTER PASS`
