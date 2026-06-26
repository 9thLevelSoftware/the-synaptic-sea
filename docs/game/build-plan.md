# Synaptic Sea E2E Systems Build Plan

Generated: 2026-06-25T19:59:51-04:00

## Board name and purpose
- Board: `synaptic-sea-e2e-systems`
- Purpose: Execute the 15 expanded Synaptic Sea system packages as full end-to-end, production-grade implementations. Each package has a standalone plan under `docs/game/build-plans/` and a real Kanban task ID in `.omh/kanban/synaptic-sea-e2e-systems-task-graph.json`.

## Inputs consumed
- `docs/SYNAPTIC_SEA_COMPLETE_SYSTEMS_MAP.md`
- `docs/PLANNING_SYNTHESIS.md`
- `docs/game/00_vision.md`
- `docs/game/02_core_loop.md`
- `docs/game/06_validation_plan.md`
- `docs/game/09_system_roadmap.md`
- `AGENTS.md`
- Subagent coverage reviews for Tasks 1-5, 6-8/12, and 9-15.

## Assignee/profile map
- `synapse_seaworker`: production implementation packages (MiniMax-M3).
- `synapse_seareview`: GPT-5.5 reviewer, integration gate, final systems-map/currency gate.
- `synapse_seadocs`: available for documentation support, not assigned by default in this graph.

## Board strategy
The graph is staged behind a blocked kickoff card `t_0228a857` so implementation does not auto-start while the expanded E2E package plan is reviewed.

When the user says to start implementation, complete the kickoff card. Tasks 1-13 will become dependency-free implementation packages. Task 14 remains gated on Tasks 1-13. Task 15 remains gated on Tasks 1-14.

## Milestones

### M1: M1 Survival Foundation
- `t_34d0483b` — Task 01: Survival Vitals (`docs/game/build-plans/01-survival-vitals-e2e.md`)
- `t_d569eba2` — Task 02: Food, Cooking, Spoilage & Sustenance Inputs (`docs/game/build-plans/02-food-cooking-spoilage-e2e.md`)

### M2: M2 Production Economy
- `t_be88f847` — Task 03: Crafting, Materials, Recipes & Stations (`docs/game/build-plans/03-crafting-materials-recipes-e2e.md`)
- `t_af66b721` — Task 04: Loot Ecosystem, Rarity, Containers & Unique Finds (`docs/game/build-plans/04-loot-ecosystem-e2e.md`)
- `t_67389b76` — Task 05: Consumables, Medicine, Stimulants, Ammo & Utility Items (`docs/game/build-plans/05-consumables-medicine-stimulants-e2e.md`)

### M3: M3 Hostile Derelicts
- `t_cbe56420` — Task 06: Combat, Threat AI, Damage, Stealth & Encounters (`docs/game/build-plans/06-combat-threat-ai-e2e.md`)

### M4: M4 Ship Survival Infrastructure
- `t_290ec958` — Task 07: Ship Systems, Power Grid, Hull, Life Support & Sustenance Infrastructure (`docs/game/build-plans/07-ship-systems-sustenance-e2e.md`)

### M5: M5 Long-Arc Progression
- `t_02146c59` — Task 08: Player Progression, Skills, Classes, Hub & Meta-Progression (`docs/game/build-plans/08-progression-skills-meta-e2e.md`)

### M6: M6 Presentation & Operability
- `t_7a6849cb` — Task 09: UI/UX, HUD, Menus, Tutorials, Controller & Accessibility (`docs/game/build-plans/09-ui-ux-accessibility-e2e.md`)
- `t_9e328a9f` — Task 10: Audio, Music, Spatial Sound, Voice & Meta Events (`docs/game/build-plans/10-audio-music-spatial-e2e.md`)

### M7: M7 Persistence & Platform Reliability
- `t_2d267b26` — Task 11: Save/Load, Persistence, Multi-Slot, Auto-Save & Cloud Readiness (`docs/game/build-plans/11-save-load-persistence-e2e.md`)

### M8: M8 World Variety
- `t_4faf58cf` — Task 12: Procedural Generation Expansion, Templates, Biomes & Encounter Injection (`docs/game/build-plans/12-procedural-generation-expansion-e2e.md`)

### M9: M9 Release Readiness
- `t_3b217838` — Task 13: Distribution, Store, Achievements, Demo, Localization & Post-Launch Ops (`docs/game/build-plans/13-distribution-store-postlaunch-e2e.md`)

### M10: M10 Integration Gate
- `t_12bf9f4a` — Task 14: Cross-System Integration, Balance, Product Audit & Gap Closure (`docs/game/build-plans/14-cross-system-integration-review-e2e.md`)

### M11: M11 Documentation Currency
- `t_c7ac4d08` — Task 15: Systems Map, Roadmap, Requirements, Manifest & Final Board Currency (`docs/game/build-plans/15-systems-map-task-graph-update-e2e.md`)

## Parallel lanes
- Tasks 1-5: survival/economy foundation.
- Tasks 6-8: combat, ship infrastructure, progression/meta.
- Tasks 9-13: presentation, audio, persistence, procgen, release operations.
- Task 14: fan-in cross-system integration and product audit.
- Task 15: final systems-map/manifest/currency gate.

## Gates and acceptance criteria
Every package must satisfy its standalone `docs/game/build-plans/<task>-e2e.md` acceptance criteria. The common gate is:
1. Feature spec + requirements + ADR + risk row exist.
2. Data schemas/resources exist and are validated.
3. Pure model smokes pass.
4. Main-scene/integration smokes pass.
5. Persistence and migration smokes pass where applicable.
6. UI/audio/assets/player feedback exist at placeholder-or-better quality.
7. `docs/game/06_validation_plan.md` contains registered smoke commands and the focused/regression evidence is fresh.
8. Systems map/roadmap/build-plan are updated with real evidence.

## Verification strategy
Use explicit Synaptic Sea root for Godot runs because some historical docs still default to `/Users/christopherwilloughby/the-synapse-sea-of-stars`:

```bash
ROOT=/Users/christopherwilloughby/the-synaptic-sea \
GODOT=/Users/christopherwilloughby/.local/bin/godot-4.6.2 \
/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-synaptic-sea --script res://scripts/validation/<smoke>.gd
```

## Risks/blockers
- The graph is intentionally broad; use package boundaries and ADRs to avoid god-object rewrites.
- Shared workspace edits can collide if too many cards run at once. Keep worker concurrency conservative or switch high-risk packages to worktrees before releasing kickoff.
- Older validation docs mention the Synapse Sea path; all cards explicitly override `ROOT`.
- Workers must not convert package scope into documentation-only deliverables unless the package itself is documentation/currency only (Task 15).

## Manifest
- `.omh/kanban/synaptic-sea-e2e-systems-task-graph.json`

## Package index
- Task 01: `t_34d0483b` — [Survival Vitals](build-plans/01-survival-vitals-e2e.md)
- Task 02: `t_d569eba2` — [Food, Cooking, Spoilage & Sustenance Inputs](build-plans/02-food-cooking-spoilage-e2e.md)
- Task 03: `t_be88f847` — [Crafting, Materials, Recipes & Stations](build-plans/03-crafting-materials-recipes-e2e.md)
- Task 04: `t_af66b721` — [Loot Ecosystem, Rarity, Containers & Unique Finds](build-plans/04-loot-ecosystem-e2e.md)
- Task 05: `t_67389b76` — [Consumables, Medicine, Stimulants, Ammo & Utility Items](build-plans/05-consumables-medicine-stimulants-e2e.md)
- Task 06: `t_cbe56420` — [Combat, Threat AI, Damage, Stealth & Encounters](build-plans/06-combat-threat-ai-e2e.md)
  - Status (2026-06-25, synapse_seaworker): implementation complete. Added Task 06 feature/requirements/ADR/balance/evidence docs, corrected the playable shock-probe weapon→ammo mapping in `scripts/procgen/playable_generated_ship.gd`, and registered six focused combat/threat smokes (`damage_pipeline`, `armor_resolver`, `status_effects`, `detection_state`, `threat_ai_state`, `main_playable_slice_combat_encounter`). Main-scene validation now proves `archetypes=5`, `ammo_spent=1`, and `memory_restored=true` after a live save/load encounter. See `docs/game/build-plans/evidence/combat-threat-ai-contract-review.md`.
- Task 07: `t_290ec958` — [Ship Systems, Power Grid, Hull, Life Support & Sustenance Infrastructure](build-plans/07-ship-systems-sustenance-e2e.md)
  - Status (2026-06-25, synapse_seaworker): implementation baseline complete. Added seven pure models (`PowerGridState`, `LifeSupportState`, `HullIntegrityState`, `FireSuppressionState`, `PropulsionState`, `ShieldState`, `SustenanceState`), four ship-system tuning/config JSONs under `data/ship_systems/`, playable-slice integration in `scripts/procgen/playable_generated_ship.gd`, and four focused smokes (`power_grid_state_smoke`, `life_support_state_smoke`, `sustenance_state_smoke`, `main_playable_slice_ship_systems_expanded_smoke`). REQ-SS-001..007 added to `docs/game/05_requirements.md`; ADR-0035 and feature/balance/evidence docs added; regression bundle extended to `commands=146`. See `docs/game/build-plans/evidence/ship-systems-sustenance-contract-review.md`.
- Task 08: `t_02146c59` — [Player Progression, Skills, Classes, Hub & Meta-Progression](build-plans/08-progression-skills-meta-e2e.md)
- Task 09: `t_7a6849cb` — [UI/UX, HUD, Menus, Tutorials, Controller & Accessibility](build-plans/09-ui-ux-accessibility-e2e.md)
- Task 10: `t_9e328a9f` — [Audio, Music, Spatial Sound, Voice & Meta Events](build-plans/10-audio-music-spatial-e2e.md)
- Task 11: `t_2d267b26` — [Save/Load, Persistence, Multi-Slot, Auto-Save & Cloud Readiness](build-plans/11-save-load-persistence-e2e.md)
- Task 12: `t_4faf58cf` — [Procedural Generation Expansion, Templates, Biomes & Encounter Injection](build-plans/12-procedural-generation-expansion-e2e.md)
- Task 13: `t_3b217838` — [Distribution, Store, Achievements, Demo, Localization & Post-Launch Ops](build-plans/13-distribution-store-postlaunch-e2e.md)
  - Status (2026-06-25, synapse_seaworker): implementation complete. Six pure models (`BuildMetadataState`, `AchievementState`, `LocalizationCatalog`, `DemoScopeGate`, `CrashReportBundle`, `ReleaseReadinessLedger`) under `scripts/systems/`, six JSON catalogs under `data/release/`, four UI seams under `scripts/ui/`, export preset validator at `scripts/release/export_presets_validator.gd`, and five regression smokes under `scripts/validation/`. REQ-RL-001..010 added to `docs/game/05_requirements.md`; ADRs 0029/0030/0031 added under `docs/game/adr/`; risk-register rows RISK-009/010 added. Regression bundle extended to `commands=125`. See `docs/game/build-plans/evidence/distribution-store-postlaunch-contract-review.md` for the package contract review. Achievement trigger wired into `_on_tool_pickup_acquired` (silent no-op when no service is injected — existing inventory/junction-calibrator smokes continue to pass).
- Task 14: `t_12bf9f4a` — [Cross-System Integration, Balance, Product Audit & Gap Closure](build-plans/14-cross-system-integration-review-e2e.md)
- Task 15: `t_c7ac4d08` — [Systems Map, Roadmap, Requirements, Manifest & Final Board Currency](build-plans/15-systems-map-task-graph-update-e2e.md)

## Task 15 final currency closeout

Task 15 (`t_c7ac4d08`) updates the final source-of-truth package after Tasks 01-14:

- Systems map: `docs/SYNAPTIC_SEA_COMPLETE_SYSTEMS_MAP.md`
- Roadmap: `docs/game/09_system_roadmap.md`
- Requirements: `REQ-DOC-001..008` in `docs/game/05_requirements.md`
- Feature spec: `docs/game/features/systems_map_task_graph_currency.md`
- ADR: `docs/game/adr/0040-systems-map-task-graph-currency.md`
- ADR index: `docs/game/adr/README.md`
- Validation: `scripts/validation/systems_map_currency_smoke.py`, `scripts/validation/requirement_trace_smoke.py`, `scripts/validation/kanban_manifest_smoke.py`
- Manifest: `.omh/kanban/synaptic-sea-e2e-systems-task-graph.json`, captured with task_count=18, link_count=44, status_counts pre-completion=`{"done": 17, "running": 1}` and expected post-completion=`{"done": 18}`.

`t_4e47145d` completed the live controller-path follow-up with marker `LIVE MAIN PREPARE UPGRADE PROBE PASS stages=7`; external store/platform evidence remains release-ops work and is not claimed by this documentation-currency package.
