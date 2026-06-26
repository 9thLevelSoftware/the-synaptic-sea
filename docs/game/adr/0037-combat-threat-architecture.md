# ADR-0037: Combat / Threat / Encounter Runtime Architecture

Status: Accepted
Date: 2026-06-25

## Context
Task 06 needs a saveable combat layer without pushing gameplay authority into scene nodes. The project already has inventory, save/load, progression, and generated-ship systems, but combat/threat behavior needed an explicit architecture boundary so damage resolution, armor, status effects, detection, and threat AI could be validated headlessly and restored from snapshots.

## Decision
1. Keep combat logic in pure `RefCounted` models: `DamagePipeline`, `ArmorResolver`, `StatusEffectsState`, `DetectionState`, `ThreatAIState`, and `ThreatManager`.
2. Treat `PlayableGeneratedShip` as the scene coordinator only: it owns the live threat manager, supplies player signals, applies threat placeholder/encounter consequences, routes weapon use, and persists combat summaries through `RunSnapshot` / `WorldSnapshot`.
3. Store combat tuning in `data/combat/weapon_definitions.json`, `ammo_definitions.json`, `status_effect_definitions.json`, and `threat_archetypes.json` so new weapons/threats stay data-driven.
4. Persist the package additively by saving threat summaries, current-ship combat summaries, ammo spend results, and per-threat memory/state instead of rebuilding encounters from scratch on load.
5. Lock the contract with model smokes (`damage_pipeline`, `armor_resolver`, `status_effects`, `detection_state`, `threat_ai_state`) plus a main-scene end-to-end smoke that proves ammo spend, awareness spikes, and threat-memory restoration after save/load.

## Consequences
- Combat behavior can be regression-tested without the editor because the core systems are deterministic pure models.
- Save/load preserves live encounter state instead of silently resetting threat phase or target memory.
- `PlayableGeneratedShip` still coordinates many systems, but the package avoids growing a scene-tree-driven combat god-object.
- Data/catalog drift between equipped item ids, weapon ids, and ammo ids must be caught by smokes because the runtime intentionally composes them across multiple JSON catalogs.

## Rejected alternatives
- Put threat AI directly on Node3D enemy scenes and reconstruct from visuals on load. Rejected because it would make save/load brittle and headless validation weak.
- Collapse damage, armor, status, and detection into one monolithic combat manager. Rejected because it would hide persistence boundaries and make targeted regression harder.
