# The Synaptic Sea — Complete Systems Map & Final Board Currency

**Currency date:** 2026-06-26
**Task:** Task 15 / `t_c7ac4d08`
**Board:** `synaptic-sea-e2e-systems`
**Validation markers:** `SYSTEMS MAP CURRENCY PASS`, `REQUIREMENT TRACE PASS`, `KANBAN MANIFEST PASS`
**Scope:** Final source-of-truth update for the E2E systems wave: systems map, roadmap, requirements, ADR index, validation plan, build plan, and Kanban manifest.

This document intentionally supersedes earlier stale status text in this file. It is the current source-backed systems ledger for the Synaptic Sea E2E implementation wave.

---

## 1. Current architecture snapshot

The project now has a production-grade headless-validation spine across the major gameplay packages:

- Pure `RefCounted` / `Resource` models remain the default home for gameplay state.
- `PlayableGeneratedShip` applies scene consequences and validation seams; models do not reach into the scene tree.
- Save/load is additive through `RunSnapshot`, world/meta-specific files, and multi-slot index state.
- Each package carries a feature spec, requirement rows, ADR/balance/evidence docs where applicable, and focused validation markers.
- Task 14 proved cross-system composition and the documented 163-command regression bundle before Task 15 performed this final currency pass.

---

## 2. Current system status matrix

| System | Current status | Source-backed evidence |
| --- | --- | --- |
| Survival vitals | Validated runtime package | REQ-SV-001..008; Task 01 smokes; vitals/sanity/radiation/temperature/status models; HUD + save/load |
| Food, cooking, spoilage, sustenance inputs | Validated runtime package | REQ-FC-001..010; Task 02 smokes; food/spoilage/cooking/hydroponics/synthesizer/water-recycler models |
| Crafting/materials/recipes/stations | Validated runtime package | REQ-CS-001..015; Task 03 smokes; material/recipe/station/quality/field-crafting path |
| Loot ecosystem | Validated runtime package | REQ-LE-001..009; Task 04 smokes; rarity, biome/depth loot, unique, junk, containers, feedback |
| Consumables | Validated runtime package | REQ-CN-001..010; Task 05 smokes; medicine, stimulants/addiction, ammo, utility, hotbar |
| Combat/threat/encounter | Validated runtime package | REQ-D-001..018; Task 06 smokes; five archetypes, detection, armor, status, ammo spend, save/load memory |
| Ship systems/sustenance | Validated runtime package | REQ-SS-001..007; Task 07 smokes; power, life support, hull, fire, propulsion, shields, sustenance |
| Progression/meta | Validated runtime package / explorable hub scene remains future content | REQ-PM-001..010; Task 08 smokes; classes, training, skill tree, meta currency, hub upgrades, panels |
| UI/UX/accessibility | Validated runtime package | REQ-UI-001..016; Task 09 smokes; menu, settings, tutorials, minimap, glyphs, tooltips, UI save/load |
| Audio/music/spatial/voice | Validated infrastructure/runtime package | REQ-AU-001..010; Task 10 smokes; buses, ambient zones, SFX captions, music states, spatial resolver, meta events |
| Save/load/persistence | Validated runtime package | REQ-SL-001..012; Task 11 smokes; manual/auto/quick/world slots, migration, corruption backup, permadeath, cloud manifest |
| Procgen expansion | Validated runtime package | REQ-PG-001..012; Task 12 smokes; templates, variants, kits, biomes, difficulty, encounters, determinism |
| Release/distribution local scaffold | Validated local scaffold; external platform evidence pending release ops | REQ-RL-001..010; Task 13 smokes; export preset validation, achievements, localization, demo, crash, readiness ledger |
| Integration/product audit | Validated | REQ-INT-001..010; Task 14 smokes; strict 163-command regression pass |
| Doc/manifest currency | Validated by Task 15 focused validators | REQ-DOC-001..008; SYSTEMS MAP CURRENCY PASS; REQUIREMENT TRACE PASS; KANBAN MANIFEST PASS |

---

## 3. Completed package evidence ledger

Every completed implementation/review package below is tied to real Kanban ids, requirement ranges, ADR/docs, code/data files, and stable validation markers.

| Task | Package | Status | Requirement / ADR | Primary evidence |
| --- | --- | --- | --- | --- |
| 00 / `t_0228a857` | Kickoff / graph release | Done | board governance<br>- | Docs: docs/game/build-plan.md; .omh/kanban/synaptic-sea-e2e-systems-task-graph.json<br>Code/data: -<br>Validation: - |
| 01 / `t_34d0483b` | Survival Vitals | Validated | REQ-SV-001..008<br>ADR-0034 survival vitals | Docs: docs/game/features/survival_vitals.md<br>Code/data: scripts/systems/vitals_state.gd; sanity_state.gd; radiation_state.gd; body_temperature_state.gd; status_effects_state.gd<br>Validation: VITALS STATE PASS; SANITY STATE PASS; RADIATION STATE PASS; BODY TEMPERATURE STATE PASS; MAIN PLAYABLE VITALS FULL PASS; VITALS SAVE LOAD PASS |
| 02 / `t_d569eba2` | Food, Cooking, Spoilage & Sustenance Inputs | Validated | REQ-FC-001..010<br>ADR-0034 food/cooking/spoilage | Docs: docs/game/features/food_cooking_spoilage.md; docs/game/balance/food_cooking_spoilage_tuning.md<br>Code/data: scripts/systems/food_state.gd; spoilage_state.gd; cooking_state.gd; hydroponics_state.gd; synthesizer_state.gd; water_recycler_state.gd<br>Validation: FOOD STATE PASS; SPOILAGE STATE PASS; COOKING STATE PASS; HYDROPONICS STATE PASS; SYNTHESIZER STATE PASS; FOOD SAVE LOAD PASS; MAIN PLAYABLE COOKING PASS |
| 03 / `t_be88f847` | Crafting, Materials, Recipes & Stations | Validated | REQ-CS-001..015<br>ADR-0038 | Docs: docs/game/features/crafting_materials_recipes.md; docs/game/balance/crafting_materials_tuning.md<br>Code/data: scripts/systems/material_state.gd; crafting_state.gd; station_state.gd; field_crafting_state.gd; quality_tier_resolver.gd; deconstruction_resolver.gd<br>Validation: MATERIAL STATE PASS; CRAFTING STATE PASS; STATION STATE PASS; RECIPE RESOURCE PASS; QUALITY TIER PASS; FIELD CRAFTING STATE PASS; MAIN PLAYABLE CRAFTING PASS |
| 04 / `t_af66b721` | Loot Ecosystem, Rarity, Containers & Unique Finds | Validated | REQ-LE-001..009<br>ADR-0037 loot ecosystem | Docs: docs/game/features/loot_ecosystem.md; docs/game/balance/loot_ecosystem_tuning.md<br>Code/data: scripts/systems/rarity_tier.gd; loot_distribution.gd; unique_item_state.gd; junk_yield_resolver.gd; scripts/tools/loot_container.gd<br>Validation: RARITY TIER PASS; LOOT DISTRIBUTION PASS; LOOT TABLE BIOME PASS; UNIQUE ITEM STATE PASS; JUNK ITEMS PASS; CONTAINER VARIETY PASS; DERELICT LOOT PASS; MAIN PLAYABLE LOOT ECOSYSTEM PASS |
| 05 / `t_67389b76` | Consumables, Medicine, Stimulants, Ammo & Utility Items | Validated | REQ-CN-001..010<br>ADR-0036 | Docs: docs/game/features/consumables_medicine_stimulants.md; docs/game/build-plans/evidence/consumables-medicine-stimulants-contract-review.md<br>Code/data: scripts/systems/effect_dispatcher.gd; consumable_state.gd; medicine_state.gd; stimulant_state.gd; addiction_state.gd; ammo_state.gd; utility_item_resolver.gd<br>Validation: EFFECT DISPATCHER PASS; CONSUMABLE STATE PASS; MEDICINE STATE PASS; STIMULANT STATE PASS; ADDICTION STATE PASS; CONSUMABLE SAVE LOAD PASS; MAIN PLAYABLE CONSUMABLES PASS |
| 06 / `t_cbe56420` | Combat, Threat AI, Damage, Stealth & Encounters | Validated | REQ-D-001..018<br>ADR-0037 combat/threat | Docs: docs/game/features/combat_threat_ai.md; docs/game/balance/combat_threat_ai.md<br>Code/data: scripts/systems/damage_pipeline.gd; armor_resolver.gd; status_effects_state.gd; detection_state.gd; threat_ai_state.gd; threat_manager.gd; scripts/procgen/playable_generated_ship.gd<br>Validation: DAMAGE PIPELINE PASS; ARMOR RESOLVER PASS; STATUS EFFECTS PASS; DETECTION STATE PASS; THREAT AI STATE PASS; MAIN PLAYABLE COMBAT ENCOUNTER PASS |
| 07 / `t_290ec958` | Ship Systems, Power Grid, Hull, Life Support & Sustenance Infrastructure | Validated | REQ-SS-001..007<br>ADR-0035 | Docs: docs/game/features/ship_systems_sustenance_infrastructure.md; docs/game/balance/ship-systems-sustenance-tuning.md<br>Code/data: scripts/systems/power_grid_state.gd; life_support_state.gd; hull_integrity_state.gd; fire_suppression_state.gd; propulsion_state.gd; shield_state.gd; sustenance_state.gd<br>Validation: POWER GRID STATE PASS; LIFE SUPPORT STATE PASS; SUSTENANCE STATE PASS; MAIN PLAYABLE SHIP SYSTEMS EXPANDED PASS; SHIP SYSTEMS MANAGER PASS; FOOD SAVE LOAD PASS |
| 08 / `t_02146c59` | Player Progression, Skills, Classes, Hub & Meta-Progression | Validated | REQ-PM-001..010<br>ADR-0033 progression/meta | Docs: docs/game/features/player_progression.md; docs/game/balance/progression_meta_tuning.md<br>Code/data: scripts/systems/player_progression_state.gd; meta_progression_state.gd; hub_upgrade_state.gd; skill_tree_state.gd; unlock_registry.gd; training_event_bus.gd<br>Validation: PLAYER PROGRESSION PASS; CROSS TRAINING PASS; TRAINING BY ITEM PASS; META PROGRESSION STATE PASS; META SNAPSHOT PASS; SKILL TREE PANEL PASS; PLAYER PROGRESSION FULL PASS |
| 09 / `t_7a6849cb` | UI/UX, HUD, Menus, Tutorials, Controller & Accessibility | Validated | REQ-UI-001..016<br>ADR-0033 UI/UX/accessibility | Docs: docs/game/features/ui_ux_accessibility.md; docs/game/balance/ui_ux_accessibility_tuning.md<br>Code/data: scripts/systems/menu_state.gd; settings_state.gd; tutorial_state.gd; map_fog_state.gd; controller_glyph_state.gd; tooltip_presenter.gd; scripts/ui/*panel.gd<br>Validation: MENU STATE PASS; SETTINGS STATE PASS; TUTORIAL STATE PASS; MAP FOG STATE PASS; CONTROLLER GLYPH STATE PASS; TOOLTIP PRESENTER PASS; MAIN PLAYABLE UI SHELL PASS; UI SHELL SAVE LOAD PASS |
| 10 / `t_9e328a9f` | Audio, Music, Spatial Sound, Voice & Meta Events | Validated | REQ-AU-001..010<br>ADR-0029 audio/music/spatial | Docs: docs/game/features/audio-music-spatial.md; docs/game/balance/audio-music-spatial.md<br>Code/data: scripts/systems/audio_bus_config.gd; ambient_zone_state.gd; sfx_event_router.gd; dynamic_music_state.gd; spatial_audio_resolver.gd; meta_event_state.gd; scripts/audio/audio_manager.gd<br>Validation: AUDIO BUS CONFIG PASS; AMBIENT ZONE STATE PASS; SFX EVENT ROUTER PASS; DYNAMIC MUSIC STATE PASS; SPATIAL AUDIO RESOLVER PASS; META EVENT STATE PASS; MAIN PLAYABLE AUDIO PASS; AUDIO SAVE LOAD PASS |
| 11 / `t_2d267b26` | Save/Load, Persistence, Multi-Slot, Auto-Save & Cloud Readiness | Validated | REQ-SL-001..012<br>ADR-0007; ADR-0031; ADR-0032 | Docs: docs/game/features/save_load.md; docs/game/balance/save-load-persistence.md<br>Code/data: scripts/systems/save_slot_state.gd; save_index_state.gd; autosave_policy.gd; save_migration_service.gd; permadeath_resolver.gd; cloud_manifest_state.gd; save_load_service.gd; scripts/ui/save_load_menu.gd<br>Validation: SAVE SLOT STATE PASS; SAVE MIGRATION SERVICE PASS; AUTOSAVE POLICY PASS; MAIN PLAYABLE MULTISLOT SAVE PASS |
| 12 / `t_4faf58cf` | Procedural Generation Expansion, Templates, Biomes & Encounter Injection | Validated | REQ-PG-001..012<br>ADR-0029 procgen expansion | Docs: docs/game/features/procedural_generation_expansion.md; docs/game/balance/procgen_expansion_tuning.md<br>Code/data: scripts/procgen/room_variant_selector.gd; kit_catalog.gd; template_c_traversal.gd; biome_profile.gd; difficulty_profile.gd; encounter_injector.gd; seed_determinism_contract.gd<br>Validation: TEMPLATE C TRAVERSAL PASS; ROOM VARIANT SELECTOR PASS; KIT CATALOG PASS; BIOME PROFILE PASS; DIFFICULTY PROFILE PASS; ENCOUNTER INJECTOR PASS; SEED DETERMINISM PASS |
| 13 / `t_3b217838` | Distribution, Store, Achievements, Demo, Localization & Post-Launch Ops | Validated local scaffold | REQ-RL-001..010<br>ADR-0029 release; ADR-0030 achievements; ADR-0031 localization | Docs: docs/game/features/release_distribution.md; docs/game/balance/release_distribution_tuning.md<br>Code/data: scripts/systems/build_metadata_state.gd; achievement_state.gd; localization_catalog.gd; demo_scope_gate.gd; crash_report_bundle.gd; release_readiness_ledger.gd; scripts/release/export_presets_validator.gd<br>Validation: EXPORT PRESETS PASS; ACHIEVEMENT STATE PASS; LOCALIZATION CATALOG PASS; DEMO SCOPE GATE PASS; RELEASE READINESS LEDGER PASS |
| 14 / `t_12bf9f4a` | Cross-System Integration, Balance, Product Audit & Gap Closure | Validated | REQ-INT-001..010<br>ADR-0039 | Docs: docs/game/features/cross_system_integration_review.md; docs/game/balance/cross_system_balance_ledger.md; data/integration/product_audit_report.json<br>Code/data: scripts/systems/integration_matrix.gd; dependency_validator.gd; balance_ledger.gd; automated_playtest_rubric.gd; product_audit_report.gd<br>Validation: CROSS SYSTEM DEPENDENCY PASS; E2E SURVIVAL LOOP PASS; E2E COMBAT LOOT CRAFT PASS; E2E SHIP META LOOP PASS; PRODUCT AUDIT PASS; SYNAPTIC_SEA REGRESSION PASS commands=163 clean_output=true |
| 15 / `t_c7ac4d08` | Systems Map, Roadmap, Requirements, Manifest & Final Board Currency | Validated by focused doc validators | REQ-DOC-001..008<br>ADR-0040 | Docs: docs/game/features/systems_map_task_graph_currency.md; docs/game/adr/0040-systems-map-task-graph-currency.md; docs/game/adr/README.md; docs/game/build-plans/evidence/systems-map-task-graph-update-contract-review.md<br>Code/data: scripts/validation/doc_currency_validators.py<br>Validation: SYSTEMS MAP CURRENCY PASS; REQUIREMENT TRACE PASS; KANBAN MANIFEST PASS |

---

## 4. ADR Currency Index

| ADR | Path | Artifact reference |
| --- | --- | --- |
| 0001 | docs/game/adr/0001-adopt-stage-gate-kanban-godot-validation.md | Stage-gate/Kanban/Godot validation operating model |
| 0005 | docs/game/adr/0005-multi-hazard-architecture.md | hazard contract smokes; oxygen/fire/electrical arc models |
| 0007 | docs/game/adr/0007-save-load-service-scope.md | RunSnapshot boundary, multi-slot additions, save/load smokes |
| 0029 | docs/game/adr/0029-audio-music-spatial-architecture.md | audio/music/spatial pure models and smokes |
| 0029 | docs/game/adr/0029-procedural-generation-expansion-architecture.md | procgen expansion models/templates/biomes/encounters |
| 0029 | docs/game/adr/0029-release-distribution-architecture.md | release metadata/demo/crash/readiness scaffold |
| 0030 | docs/game/adr/0030-achievement-catalog-and-triggers.md | achievement catalog/state smoke |
| 0031 | docs/game/adr/0031-localization-catalog-and-routing.md | localization catalog and language selector |
| 0031 | docs/game/adr/0031-multi-slot-save-architecture.md | save slot/index/autosave/manual/quicksave/world slot architecture |
| 0032 | docs/game/adr/0032-migration-permadeath-cloud-manifest.md | save migration, permadeath, cloud manifest |
| 0033 | docs/game/adr/0033-player-progression-meta-architecture.md | progression/meta/hub upgrade models and panels |
| 0033 | docs/game/adr/0033-ui-ux-accessibility-architecture.md | menu/settings/tutorial/minimap/glyph/tooltip UI shell |
| 0034 | docs/game/adr/0034-survival-vitals-architecture.md | survival vitals state and HUD persistence |
| 0034 | docs/game/adr/0034-food-cooking-spoilage-architecture.md | food/spoilage/cooking/hydroponics/synthesizer/water recycler |
| 0035 | docs/game/adr/0035-ship-systems-sustenance-expansion-architecture.md | power/life-support/hull/fire/propulsion/shield/sustenance models |
| 0036 | docs/game/adr/0036-consumable-effect-pipeline-architecture.md | effect dispatcher, medicine/stimulants/ammo/utility |
| 0037 | docs/game/adr/0037-combat-threat-architecture.md | damage, armor, status, detection, threats |
| 0037 | docs/game/adr/0037-loot-ecosystem-rarity-container-architecture.md | loot rarity/distribution/containers/unique/junk |
| 0038 | docs/game/adr/0038-crafting-materials-stations-architecture.md | materials/crafting/stations/quality/field crafting |
| 0039 | docs/game/adr/0039-cross-system-integration-audit-architecture.md | Task 14 integration audit models and e2e smokes |
| 0040 | docs/game/adr/0040-systems-map-task-graph-currency.md | Task 15 doc-currency validators and board manifest checks |

---

## 5. Board and manifest currency

- Active execution board: `synaptic-sea-e2e-systems`.
- Active manifest: `.omh/kanban/synaptic-sea-e2e-systems-task-graph.json`.
- Board database captured by Task 15: `/Users/christopherwilloughby/.hermes/kanban/boards/synaptic-sea-e2e-systems/kanban.db`.
- Live board counts at Task 15 pre-completion capture: tasks=18, links=44, status_counts={"done": 17, "running": 1}. Expected after this card completes: status_counts={"done": 18}.
- The package graph contains the kickoff, Tasks 01-15, the resolved Task 14 live-controller follow-up (`t_4e47145d`, marker `LIVE MAIN PREPARE UPGRADE PROBE PASS stages=7`), and the resolved rigid-pair follow-up (`t_cc483347`).
- Task 15's manifest validation checks that all manifest task ids exist in the live board, that declared parent edges exist in `task_links`, and that recorded task/link/status counts match the live board database.

---

## 6. Remaining work that is intentionally not claimed complete

These are explicit future/release-ops surfaces, not stale contradictions about systems already shipped in Tasks 01-14. The Task 14 live controller-path probe is now completed by `t_4e47145d` and registered in the validation plan.

1. External release evidence: signed exports, itch/Steam page evidence, platform achievement/cloud integration, and hardware/Steam Deck checks.
2. Final art/audio/content polish: bespoke enemy art/audio, final SFX/music assets, store capsule/trailer/screenshot production, juice/FX passes.
3. Larger content expansion: more handcrafted set pieces, boss encounters, vendor/faction economy, explorable hub scene, and long-form narrative/content beyond the E2E wave.
4. Performance/QA hardening beyond the current headless smoke/regression baseline.

---

## 7. Task 15 validation contract

The focused Task 15 validators are source-backed and deterministic:

- `scripts/validation/systems_map_currency_smoke.py` prints `SYSTEMS MAP CURRENCY PASS` after checking every package row is represented here and stale in-scope deferral language is absent.
- `scripts/validation/requirement_trace_smoke.py` prints `REQUIREMENT TRACE PASS` after checking `REQ-DOC-001..008`, matrix requirements, and ADR index references.
- `scripts/validation/kanban_manifest_smoke.py` prints `KANBAN MANIFEST PASS` after checking the live Kanban board against the manifest counts, ids, statuses, and dependency links.
