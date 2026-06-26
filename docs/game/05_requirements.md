# 05 Requirements

Requirements must be granular, testable, and linked to feature specs or ADRs.

## Status legend

- Proposed
- Approved
- Implemented
- Validated
- Deferred
- Cut

## Gate 2 feature-to-requirement traceability

| Existing REQ | Gate 2 feature spec | Relationship |
|---|---|---|
| REQ-001 | `features/inventory_tools.md`, `features/hazard_variety.md`, `features/objective_variation.md`, `features/save_load.md` | Preserved / restored by each Gate 2 feature |
| REQ-002 | `features/objective_variation.md`, `features/save_load.md` | Restore-systems rule preserved; gate state restored |
| REQ-003 | `features/objective_variation.md`, `features/save_load.md` | Extraction unlock preserved; state restored |
| REQ-004 | `features/inventory_tools.md`, `features/hazard_variety.md`, `features/objective_variation.md`, `features/save_load.md` | Each feature adds model + scene validation |
| REQ-006 | `features/inventory_tools.md`, `features/hazard_variety.md`, `features/save_load.md` | Extended by tool/fire; preserved by save/load |
| REQ-008 | `features/save_load.md` | Save/load explicitly excludes hub/meta persistence |
| REQ-009 | `features/save_load.md` | Gate 2 feature set scoped by ADR-0003 Option A |

## REQ-001: Route gates are real runtime blockers

- Source: `features/route_control.md`
- Type: gameplay / technical
- Priority: must
- Status: Validated
- Rationale: Blocked routes must affect traversal/passability, not just HUD or props.
- Acceptance criteria:
  - A route gate exists as a runtime `StaticBody3D` node.
  - It has a `CollisionShape3D` while closed.
  - It starts with collision enabled.
  - It exposes inspectable metadata including route id and open state.
- Verification:
  - `main_playable_slice_route_control_smoke.gd`

## REQ-002: Restoring systems opens powered route gates

- Source: `features/route_control.md`
- Type: gameplay / technical
- Priority: must
- Status: Validated
- Acceptance criteria:
  - Completing objective 1 does not open the route gate.
  - Completing objective 2 restores main power and opens powered gates.
  - Active blocker count becomes zero.
  - Gate collision is disabled rather than the node being deleted.
- Verification:
  - `main_playable_slice_route_control_smoke.gd`

## REQ-003: Reactor stabilization unlocks extraction

- Source: `features/route_control.md`
- Type: gameplay
- Priority: must
- Status: Validated
- Acceptance criteria:
  - Completing objective 4 unlocks extraction in route-control summary.
  - Slice completion remains intact.
- Verification:
  - `main_playable_slice_route_control_smoke.gd`
  - `main_playable_slice_completion_smoke.gd`

## REQ-004: New gameplay systems require model and scene validation

- Source: `08_milestone_gates.md`
- Type: process / technical
- Priority: must
- Status: Approved
- Acceptance criteria:
  - Pure state logic has a direct model smoke when practical.
  - Scene consequences have a main-scene smoke.
  - Regression bundle includes the new smoke before a feature is marked done.
- Verification:
  - Review card checklist.

## REQ-005: No proof-only milestone substitution

- Source: design pillars
- Type: process
- Priority: must
- Status: Approved
- Acceptance criteria:
  - A milestone cannot be completed solely by HTML, PNG, screenshot, contact sheet, or proof doc artifacts.
  - If visual evidence is required, it is secondary to in-engine runtime behavior.
- Verification:
  - Artifact scope guard in validation plan.

## REQ-006: Hazard pressure loop

- Source: `features/hazards.md`, core loop gaps
- Type: gameplay
- Priority: should
- Status: Validated
- Acceptance criteria:
  - At least one hazard exists in the generated ship scene (one oxygen breach zone on the objective 3 → objective 4 corridor for Gate 1).
  - The hazard affects traversal, resources, timing, and objective risk: drain rate consumes oxygen while inside the unsealed breach zone, regeneration is gated by leaving any breach zone, objective 2 seals the breach, and a zero-oxygen state blocks passability through the breach zone until oxygen recovers above the recovery threshold.
  - Player can observe and respond to the hazard: HUD oxygen line, room unsafe marker on the locked-isometric view, and collision-blocked traversal when oxygen is zero.
  - The hazard has both a direct state model smoke (`oxygen_state_smoke.gd`) and a main-scene smoke (`main_playable_slice_hazard_smoke.gd`).
  - Hazard state is parallel to route-control and ship-system state; sealing the breach does not alter route-gate or extraction state.
- Verification:
  - `scripts/validation/oxygen_state_smoke.gd`
  - `scripts/validation/main_playable_slice_hazard_smoke.gd`
  - Both added to the regression bundle in `docs/game/06_validation_plan.md`.

## REQ-007: Inventory/tool loop

- Source: `features/inventory_tools.md`
- Type: gameplay
- Priority: should
- Status: Approved
- Rationale: Gate 2 must add the first player-owned resource that modifies an environmental system; the portable oxygen pump extends the hazard pressure loop without changing route-control or extraction semantics.
- Acceptance criteria:
  - At least one tool (`portable_oxygen_pump`) can be acquired by interacting with a pickup.
  - Carrying the tool changes the oxygen hazard outcome (reduces drain rate while inside an unsealed breach zone).
  - Tool state persists for the current ship slice and is captured by REQ-012 save/load.
  - A direct model smoke and a main-scene smoke both pass.
- Verification:
  - `scripts/validation/inventory_state_smoke.gd`
  - `scripts/validation/main_playable_slice_inventory_smoke.gd`

## REQ-008: Hub/meta progression stance for Gate 1

- Source: ADR-0002, `02_core_loop.md`, `08_milestone_gates.md`
- Type: process / scope
- Priority: must
- Status: Approved (deferred with cut line)
- Rationale: Gate 1 exit is a single-ship slice; implementing hub/meta now would broaden scope past the vertical-slice discipline called out in Pillar 4 and would require content/economy/save architecture decisions before validation. Deferral with a documented cut line and a Gate 2 entry-review trigger prevents future workers from guessing at scope.
- Acceptance criteria:
  - Gate 1 MUST NOT require a hub ship scene, hub UI, derelict selection, persistent meta-currency, persistent unlocks, faction progression, or hub save state.
  - The reactor-stabilization completion state is the Gate 1 stand-in for "return progress to hub" (see `02_core_loop.md` Gate 1 hub/meta stance).
  - Any hub/meta work in Gate 1 is a scope violation unless the Gate 1 stance is explicitly re-decided via a new ADR.
  - Hub/meta re-decision is required before Gate 2 entry (see `08_milestone_gates.md` Gate 2 entry criteria).
- Verification:
  - Documentation review by `sargassoreview` checks that no Gate 1 card introduces hub/meta state, derelict selection, or persistent meta-currency.
  - Reviewer confirms `features/hub_progression.md` is not authored during Gate 1.

## REQ-009: Gate 2 hub/meta re-decision trigger

- Source: ADR-0002, ADR-0003, `08_milestone_gates.md`
- Type: process
- Priority: must
- Status: Resolved by ADR-0003 (Option A: deferred through Gate 2)
- Rationale: Hub/meta is the largest undecided design surface in the vision. Gate 2 entry review is the formal checkpoint where the deferral is re-affirmed or the scope is escalated into an early Gate 2 implementation card.
- Resolution: ADR-0003 re-affirms deferral through Gate 2 and anchors the next hub/meta decision to Gate 3 entry planning. Gate 2 focuses on derelict exploration depth: inventory/tools, expanded hazards, objective/procedural variation, and current-run persistence.
- Acceptance criteria:
  - Before Gate 2 begins, a hub/meta re-decision card exists on board `sargasso-stage-gate`.
  - The card selects exactly one of: (a) re-affirm deferral with a Gate 3/4 anchor, or (b) escalate into an early Gate 2 implementation card with a `features/hub_progression.md` spec.
  - The chosen path is recorded as a new or patched ADR.
- Chosen path:
  - Option A selected by ADR-0003: hub/meta remains deferred through Gate 2 with a Gate 3 entry planning anchor.
  - `features/hub_progression.md` is not authored for Gate 2.
- Verification:
  - Kanban board audit at Gate 2 entry review.

## REQ-010: Hazard variety

- Source: `features/hazard_variety.md`
- Type: gameplay
- Priority: should
- Status: Approved
- Rationale: Gate 2 needs a second hazard pattern to prove the ship can host multiple environmental pressures without every hazard being an oxygen-drain variant.
- Acceptance criteria:
  - At least one additional hazard type exists in the generated ship scene (the timed fire zone in a side corridor for Gate 2).
  - The new hazard toggles real passability via its own pure state model (`FireState`).
  - The new hazard does not alter oxygen, route-gate, or extraction semantics.
  - Both a direct model smoke and a main-scene smoke pass.
- Verification:
  - `scripts/validation/fire_state_smoke.gd`
  - `scripts/validation/main_playable_slice_fire_smoke.gd`

## REQ-011: Objective variation

- Source: `features/objective_variation.md`
- Type: gameplay
- Priority: should
- Status: Approved
- Rationale: Gate 2 needs at least one non-single-interaction objective shape to validate that the objective pipeline supports variation without breaking sequence-dependent systems.
- Acceptance criteria:
  - At least one new objective kind (`repair_junction`) requires multiple interactions in the same room before the sequence advances.
  - Multi-step completion advances ship-system and route-control state exactly once.
  - Single-step objectives remain backward compatible.
  - Both a direct model smoke and a main-scene smoke pass.
- Verification:
  - `scripts/validation/objective_progress_state_smoke.gd`
  - `scripts/validation/main_playable_slice_objective_variation_smoke.gd`

## REQ-012: Save/load run persistence

- Source: `features/save_load.md`, ADR-0007
- Type: technical
- Priority: should
- Status: Approved
- Rationale: A 5-minute derelict run needs current-run persistence; Gate 2 implements a single-slot save/load service scoped to the active ship slice.
- Acceptance criteria:
  - Runtime state (player position, objective sequence, ship systems, route control, oxygen, inventory, fire, objective progress) can be serialized to `user://saves/current_run.json`.
  - Loading the snapshot reconstructs the same slice and restores all captured state before the next tick.
  - Save/load is current-run only: no hub state, meta-currency, unlocks, or cross-run progress is persisted (enforced by ADR-0007).
  - The save slot is deleted when the run completes.
  - Both a direct model smoke and a main-scene smoke pass.
- Verification:
  - `scripts/validation/save_load_service_smoke.gd`
  - `scripts/validation/main_playable_slice_save_load_smoke.gd`

## REQ-013: Alpha hazard variety

- Source: `features/hazard_type_3.md`, `content_complete_target.md`
- Type: gameplay
- Priority: should
- Status: Approved
- Rationale: Alpha content-complete requires three distinct hazard patterns to prove the ship can host multiple environmental pressures without every hazard being a variant of oxygen drain or timed fire.
- Acceptance criteria:
  - A third hazard type exists in the generated ship scene on at least one non-critical link per new template where topology supports it.
  - The new hazard has its own pure state model and main-scene smoke.
  - The new hazard toggles real passability, resource pressure, or traversal timing.
  - The new hazard does not duplicate oxygen-breach or timed-fire semantics.
  - ADR-0005 is authored and accepted before implementation; it defines the `HazardStateContract`, the `PhaseTimer` helper for timer-based hazards, the loader contract for `breach_zones` / `fire_zones` / `arc_zones`, and the save/load serialization shape for hazard state.
- Verification:
  - `scripts/validation/electrical_arc_state_smoke.gd` — direct model smoke.
  - `scripts/validation/main_playable_slice_arc_smoke.gd` — main-scene placement smoke.

## REQ-014: Alpha tool variety

- Source: `docs/game/content_complete_target.md`, `docs/game/features/tool_type_2.md`
- Type: gameplay
- Priority: should
- Status: Approved
- Rationale: Alpha content-complete requires two distinct tools to validate that the inventory loop supports meaningful player choice beyond the portable oxygen pump.
- Acceptance criteria:
  - A second tool (`junction_calibrator`) can be acquired by interacting with a pickup.
  - The second tool modifies a `repair_junction` objective by reducing its required step count by one (min 1).
  - Tool state persists for the current ship slice and is captured by REQ-012 save/load.
  - The carried / consumed / applied state survives save/load round-trips with a real next-frame interaction after load (no "previously freed" crash in the post-load HUD/tracker path; no silent loss of the per-sequence `calibrator_applied` flag through the JSON string-key round-trip; the pickup marker stays hidden after reload in both carried and spent save states).
  - The live coordinator path records a completed `objective_progress_state` step when the carried calibrator reduces a real 2-step repair_junction to 1 required step (pre-calibration `required_steps` snapshot, not post-calibration).
  - Direct model smoke (`scripts/validation/junction_calibrator_state_smoke.gd`), main-scene smoke (`scripts/validation/main_playable_slice_junction_calibrator_smoke.gd`), and save/load smoke (`scripts/validation/main_playable_slice_junction_calibrator_save_load_smoke.gd`) all pass.
  - ADR-0004 is authored before implementation if the tool/effect system is generalized beyond hard-coded multipliers.
- Verification:
  - `scripts/validation/junction_calibrator_state_smoke.gd`
  - `scripts/validation/main_playable_slice_junction_calibrator_smoke.gd`
  - `scripts/validation/main_playable_slice_junction_calibrator_save_load_smoke.gd`

## REQ-CS-001: Material catalog ships at production scale

- Source: `docs/game/features/crafting_materials_recipes.md`, ADR-0038
- Type: gameplay / data
- Priority: must
- Status: Validated
- Acceptance criteria:
  - `data/materials/material_definitions.json` contains at least 30 material entries.
  - Each material exposes `display_name`, `category`, `weight`, `max_stack`, and `base_quality`.
  - The material smoke prints `MATERIAL STATE PASS`.
- Verification:
  - `scripts/validation/material_state_smoke.gd`

## REQ-CS-002: Material quality is tracked independently from quantity

- Source: `docs/game/features/crafting_materials_recipes.md`, ADR-0038
- Type: gameplay / technical
- Priority: must
- Status: Validated
- Acceptance criteria:
  - `MaterialState` stores per-material quality and falls back to the material definition's base quality when unset.
  - Weighted ingredient averages remain deterministic.
  - The material smoke prints `MATERIAL STATE PASS`.
- Verification:
  - `scripts/validation/material_state_smoke.gd`

## REQ-CS-003: Recipe catalog ships at production scale

- Source: `docs/game/features/crafting_materials_recipes.md`, ADR-0038
- Type: gameplay / data
- Priority: must
- Status: Validated
- Acceptance criteria:
  - `data/recipes/recipe_definitions.json` contains at least 50 recipes.
  - Recipes cover the shipped station kinds `fabricator`, `workbench`, `medbay`, `kitchen`, `synthesizer`, and `field_crafting`.
  - The recipe-resource smoke prints `RECIPE RESOURCE PASS`.
- Verification:
  - `scripts/validation/recipe_resource_smoke.gd`

## REQ-CS-004: Recipe schema is validated headlessly

- Source: `docs/game/features/crafting_materials_recipes.md`, ADR-0038
- Type: technical
- Priority: must
- Status: Validated
- Acceptance criteria:
  - Every recipe exposes `recipe_id`, `display_name`, `category`, `ingredients`, `produces`, `craft_time_seconds`, `required_skill_level`, `station_kind`, `power_cost`, and `batch_size`.
  - Unknown station kinds or malformed ingredient/produce payloads fail validation.
  - The recipe-resource smoke prints `RECIPE RESOURCE PASS`.
- Verification:
  - `scripts/validation/recipe_resource_smoke.gd`

## REQ-CS-005: Crafting consumes real inventory ingredients

- Source: `docs/game/features/crafting_materials_recipes.md`, ADR-0038
- Type: gameplay
- Priority: must
- Status: Validated
- Acceptance criteria:
  - Starting a valid recipe removes the required input quantities from inventory exactly once.
  - Insufficient ingredients reject the craft.
  - The crafting-state smoke prints `CRAFTING STATE PASS`.
- Verification:
  - `scripts/validation/crafting_state_smoke.gd`

## REQ-CS-006: Craft completion produces real items and quantities

- Source: `docs/game/features/crafting_materials_recipes.md`, ADR-0038
- Type: gameplay
- Priority: must
- Status: Validated
- Acceptance criteria:
  - Completing a craft yields the recipe's `produces.item_id` and `produces.quantity`.
  - Batch recipes can yield more than one output.
  - The crafting-state smoke prints `CRAFTING STATE PASS`.
- Verification:
  - `scripts/validation/crafting_state_smoke.gd`

## REQ-CS-007: Station state is power-aware and queue-aware

- Source: `docs/game/features/crafting_materials_recipes.md`, ADR-0038
- Type: gameplay / technical
- Priority: must
- Status: Validated
- Acceptance criteria:
  - `StationState` round-trips station kind, level, power, active recipe, progress, and queue state.
  - Losing power pauses a queued/active craft and restoring power resumes it.
  - The station smoke prints `STATION STATE PASS`.
- Verification:
  - `scripts/validation/station_state_smoke.gd`

## REQ-CS-008: Quality tiers are deterministic and tunable

- Source: `docs/game/features/crafting_materials_recipes.md`, ADR-0038
- Type: gameplay / balance
- Priority: must
- Status: Validated
- Acceptance criteria:
  - Quality tier resolution is deterministic for the same inputs.
  - The shipped thresholds/multipliers cover `poor`, `standard`, `good`, `excellent`, and `masterwork`.
  - The quality-tier smoke prints `QUALITY TIER PASS`.
- Verification:
  - `scripts/validation/quality_tier_smoke.gd`

## REQ-CS-009: Skill, station level, material quality, and power affect output quality

- Source: `docs/game/features/crafting_materials_recipes.md`, ADR-0038
- Type: gameplay / balance
- Priority: must
- Status: Validated
- Acceptance criteria:
  - Craft results carry `quality_tier`, `quality_multiplier`, and `quality_score`.
  - The resolved quality responds to ingredient quality, player skill, station level, and power state.
  - The crafting-state smoke prints `CRAFTING STATE PASS` and the quality-tier smoke prints `QUALITY TIER PASS`.
- Verification:
  - `scripts/validation/crafting_state_smoke.gd`
  - `scripts/validation/quality_tier_smoke.gd`

## REQ-CS-010: Field crafting is a constrained emergency subset

- Source: `docs/game/features/crafting_materials_recipes.md`, ADR-0038
- Type: gameplay
- Priority: should
- Status: Validated
- Acceptance criteria:
  - Only `station_kind == field_crafting` recipes are available through `FieldCraftingState`.
  - Non-field recipes are rejected.
  - The field-crafting smoke prints `FIELD CRAFTING STATE PASS`.
- Verification:
  - `scripts/validation/field_crafting_state_smoke.gd`

## REQ-CS-011: Deconstruction returns deterministic material yields

- Source: `docs/game/features/crafting_materials_recipes.md`, ADR-0038
- Type: gameplay
- Priority: should
- Status: Validated
- Acceptance criteria:
  - Deconstruction recipes are represented in the shared recipe catalog under `category == deconstruction`.
  - Resolving a valid deconstruction recipe consumes the source item and returns the configured output payload.
  - Recipe-resource validation continues to pass for the deconstruction entries.
- Verification:
  - `scripts/validation/recipe_resource_smoke.gd`

## REQ-CS-012: Batch crafting survives queue advancement

- Source: `docs/game/features/crafting_materials_recipes.md`, ADR-0038
- Type: gameplay / technical
- Priority: should
- Status: Validated
- Acceptance criteria:
  - Queued recipes advance to the next active recipe when the previous one finishes.
  - Pause/resume semantics remain intact across the queue handoff.
  - The station smoke prints `STATION STATE PASS`.
- Verification:
  - `scripts/validation/station_state_smoke.gd`

## REQ-CS-013: Crafting state round-trips through save/load

- Source: `docs/game/features/crafting_materials_recipes.md`, ADR-0038
- Type: persistence
- Priority: must
- Status: Validated
- Acceptance criteria:
  - `RunSnapshot` carries additive `crafting_summary` and `material_summary` fields.
  - `SaveLoadService` preserves those summaries field-for-field.
  - The save/load service smoke prints `SAVE LOAD SERVICE PASS round_trip=true version_match=true summaries=27`.
- Verification:
  - `scripts/validation/save_load_service_smoke.gd`

## REQ-CS-014: Mid-craft save/load resumes without duplication or loss

- Source: `docs/game/features/crafting_materials_recipes.md`, ADR-0038
- Type: gameplay / persistence
- Priority: must
- Status: Validated
- Acceptance criteria:
  - A partially progressed craft can be serialized, reloaded, resumed, and completed.
  - Consumed ingredients remain consumed after reload; no duplicate payout occurs.
  - The main playable crafting smoke prints `MAIN PLAYABLE CRAFTING PASS`.
- Verification:
  - `scripts/validation/main_playable_slice_crafting_smoke.gd`

## REQ-CS-015: Crafting package ships with focused and regression validation coverage

- Source: `docs/game/features/crafting_materials_recipes.md`, ADR-0038
- Type: process / technical
- Priority: must
- Status: Validated
- Acceptance criteria:
  - The package registers focused smokes for materials, crafting, station state, quality tiers, field crafting, recipe resources, and the main playable save/load path.
  - The validation plan includes the crafting package in the regression bundle.
- Verification:
  - `docs/game/06_validation_plan.md`

## REQ-LE-001: Rarity tiers normalize and render consistently

- Source: `docs/game/features/loot_ecosystem.md`, ADR-0037
- Type: gameplay / UI
- Priority: must
- Status: Validated
- Acceptance criteria:
  - `RarityTier` recognizes the shipped rarity set and falls back safely for unknown input.
  - Every rarity tier exposes a label and color used by the inventory UI.
  - The rarity smoke prints `RARITY TIER PASS`.
- Verification:
  - `scripts/validation/rarity_tier_smoke.gd`

## REQ-LE-002: Loot distribution is deterministic for identical inputs

- Source: `docs/game/features/loot_ecosystem.md`, ADR-0037
- Type: gameplay / technical
- Priority: must
- Status: Validated
- Acceptance criteria:
  - Given the same `(table_key, seed_source, biome, depth, condition, container_kind)` inputs, `LootDistribution.roll(...)` returns byte-identical results.
  - Claimed unique items are filtered from later rolls.
  - The distribution smoke prints `LOOT DISTRIBUTION PASS`.
- Verification:
  - `scripts/validation/loot_distribution_smoke.gd`

## REQ-LE-003: Biome / depth / condition / container modifiers change outcomes

- Source: `docs/game/features/loot_ecosystem.md`, ADR-0037
- Type: gameplay / balance
- Priority: must
- Status: Validated
- Acceptance criteria:
  - Changing biome/depth/condition/container context can change the rolled result for the same seed/table.
  - The biome smoke prints `LOOT TABLE BIOME PASS`.
- Verification:
  - `scripts/validation/loot_table_biome_smoke.gd`

## REQ-LE-004: Container variety is data-backed and gameplay-visible

- Source: `docs/game/features/loot_ecosystem.md`, ADR-0037
- Type: gameplay / content
- Priority: should
- Status: Validated
- Acceptance criteria:
  - The rarity palette defines labels/colors for `industrial_crate`, `survivor_locker`, `maintenance_cache`, and `hidden_cache`.
  - GameplaySliceBuilder emits both crate and locker container kinds in a representative slice.
  - The container smoke prints `CONTAINER VARIETY PASS`.
- Verification:
  - `scripts/validation/container_variety_smoke.gd`

## REQ-LE-005: Unique finds drop once per world state and persist

- Source: `docs/game/features/loot_ecosystem.md`, ADR-0037
- Type: gameplay / persistence
- Priority: must
- Status: Validated
- Acceptance criteria:
  - `UniqueItemState.claim(...)` rejects duplicate claims for the same unique id / seed key.
  - Claimed unique ids and codex unlocks round-trip through summary persistence.
  - The unique-item smoke prints `UNIQUE ITEM STATE PASS`.
- Verification:
  - `scripts/validation/unique_item_state_smoke.gd`

## REQ-LE-006: Junk items expose deterministic material yields

- Source: `docs/game/features/loot_ecosystem.md`, ADR-0037
- Type: gameplay / data
- Priority: should
- Status: Validated
- Acceptance criteria:
  - Every shipped junk item exposes at least one salvage-yield entry.
  - `JunkYieldResolver` and merged `ItemDefs` agree on the yield payload.
  - The junk smoke prints `JUNK ITEMS PASS`.
- Verification:
  - `scripts/validation/junk_items_smoke.gd`

## REQ-LE-007: Loot feedback is visible, audible, and caption-backed

- Source: `docs/game/features/loot_ecosystem.md`, ADR-0037
- Type: gameplay / accessibility
- Priority: must
- Status: Validated
- Acceptance criteria:
  - Searching a loot container updates the HUD with a `Loot: ...` feedback line.
  - The pickup event routes through the audio/caption seam so a caption fallback exists.
  - Inventory rows render the looted item's rarity through their border color.
  - The main playable smoke prints `MAIN PLAYABLE LOOT ECOSYSTEM PASS`.
- Verification:
  - `scripts/validation/main_playable_slice_loot_ecosystem_smoke.gd`

## REQ-LE-008: Searched-container state persists across revisits and save/load

- Source: `docs/game/features/loot_ecosystem.md`, ADR-0037
- Type: gameplay / persistence
- Priority: must
- Status: Validated
- Acceptance criteria:
  - A searched container stays searched on revisit.
  - Home/world loot state restores after save/load.
  - The legacy derelict-loot smoke continues to print `DERELICT LOOT PASS`.
- Verification:
  - `scripts/validation/derelict_loot_smoke.gd`
  - `scripts/validation/main_playable_slice_loot_ecosystem_smoke.gd`

## REQ-LE-009: Loot package validation is registered in the regression bundle

- Source: `docs/game/build-plans/04-loot-ecosystem-e2e.md`
- Type: process / technical
- Priority: must
- Status: Validated
- Acceptance criteria:
  - Focused package validation uses `ROOT=/Users/christopherwilloughby/the-synaptic-sea`.
  - The regression bundle includes rarity, distribution, biome, unique, junk, container-variety, and main-playable loot smokes.
  - No unexpected Godot `ERROR:`/`WARNING:` lines appear in the focused package run.
- Verification:
  - `docs/game/06_validation_plan.md`

## REQ-SL-001: Save slot identity and manual/autosave/quicksave distinction

- Source: `docs/game/build-plans/11-save-load-persistence-e2e.md`, ADR-0031
- Type: technical / process
- Priority: must
- Status: Approved
- Rationale: A multi-slot persistence package must give every persisted snapshot a stable `slot_id` and a `slot_kind` (`manual` / `auto` / `quick` / `world`) so the menu UI, autosave policy, and cloud adapter can disambiguate them without parsing display names.
- Acceptance criteria:
  - Every persisted slot carries `slot_id` (non-empty String) and `slot_kind` (one of `manual`/`auto`/`quick`/`world`).
  - The autosave policy rotates between at most 3 autosave slots per save family.
  - Manual saves can write to any of the 6 manual slots (`slot_01`..`slot_06`).
  - Quicksaves overwrite the single `quicksave` slot for the active family.
  - Given two manual saves written back-to-back, when the index is listed, then both rows are present and the most recent `saved_at` sorts first.
- Verification: `scripts/validation/save_slot_state_smoke.gd` (expected marker `SAVE SLOT STATE PASS`).

## REQ-SL-002: Save index lists and resolves slots

- Source: ADR-0031
- Type: technical
- Priority: must
- Status: Approved
- Acceptance criteria:
  - A `SaveIndexState` exists at `user://saves/index.json` and contains a `version`, `godot_version`, `updated_at`, and a `slots` Array.
  - `SaveLoadService.list_slots()` returns slot rows sorted by `saved_at` descending.
  - `has_slot(slot_id)` is `true` when the slot file exists on disk.
  - When a slot file is deleted from disk but still in the index, the next list call flags it `corrupt=true`.
- Verification: `scripts/validation/save_slot_state_smoke.gd` (covers index round-trip alongside the slot row).

## REQ-SL-003: Corruption detection backs up rather than loads

- Source: ADR-0031, ADR-0032
- Type: technical
- Priority: must
- Status: Approved
- Acceptance criteria:
  - When a slot file fails JSON parse, version match, or summary load, the service moves the bad file to `user://saves/.corrupt/<slot_id>.<saved_at_epoch>.bak` and returns `null` from `load_*`.
  - The corrupted slot does NOT appear in the index as loadable, but its row in the index is marked `corrupt=true` for review.
  - The original file is never deleted silently; an explicit backup path always exists.
  - Given a corrupted slot file, when `load_from_slot` is called, then it returns null AND a backup file exists under `.corrupt/`.
- Verification: `scripts/validation/save_slot_state_smoke.gd` (corruption path).

## REQ-SL-004: Manual saves are listed, loadable, and versioned

- Source: ADR-0031
- Type: technical
- Priority: must
- Status: Approved
- Acceptance criteria:
  - Writing to `slot_01` through `slot_06` produces a distinct file `user://saves/<slot_id>.json` plus an index row.
  - Loading any of the 6 manual slots returns a `RunSnapshot` whose `slot_id` matches the requested slot.
  - Given a manual save in slot_03, when it is loaded, then `loaded.slot_id == "slot_03"` and `loaded.slot_kind == "manual"`.
- Verification: `scripts/validation/main_playable_slice_multislot_save_smoke.gd` (manual slot writes).

## REQ-SL-005: Quicksave overwrites a single dedicated slot

- Source: ADR-0031
- Type: technical / gameplay
- Priority: must
- Status: Approved
- Acceptance criteria:
  - `request_quicksave` writes to slot_id `quicksave` (or `quicksave_<family>` when family > 1) and increments a `quicksave_cooldown` of 10 s.
  - `request_quickload` reads from the matching quicksave slot and rejects while the cooldown is active.
  - Given a cooldown of 10 s, when two quicksaves fire within 1 s, then only the first writes; the second is rejected with a warning.
- Verification: `scripts/validation/autosave_policy_smoke.gd` (quicksave cooldown) and `scripts/validation/main_playable_slice_multislot_save_smoke.gd` (quicksave end-to-end).

## REQ-SL-006: Autosave policy fires on cadence + event triggers

- Source: ADR-0031, ADR-0032
- Type: technical
- Priority: must
- Status: Approved
- Acceptance criteria:
  - `AutosavePolicy.tick(seconds, event_count)` returns true when (a) ≥ 90 in-game seconds since the last autosave OR (b) ≥ 8 events since the last autosave OR (c) a manual force flag is set.
  - Minimum interval of 5 s real-time between autosaves (budget guard).
  - Rotation: at most 3 autosave slots per family; oldest is overwritten when the budget is exhausted.
  - Given 0 s elapsed + 0 events, `tick(0,0)` returns false; after 91 s + 1 tick, the next tick returns true.
- Verification: `scripts/validation/autosave_policy_smoke.gd` (expected marker `AUTOSAVE POLICY PASS`).

## REQ-SL-007: Save migration service moves old saves forward

- Source: ADR-0032
- Type: technical
- Priority: must
- Status: Approved
- Acceptance criteria:
  - `SaveMigrationService` exposes a migration table mapping `from_version -> to_version`.
  - When an old-version slot is loaded, the service transparently migrates it forward, writes the migrated form to a sibling `<slot_id>.migrated.json`, and returns the migrated snapshot.
  - Migration is deterministic and pure (no scene tree access).
  - Given a v1 save with no `player_progression_summary` field, when migrated to v2, the loaded snapshot has a default `player_progression_summary` and the migrated file exists.
- Verification: `scripts/validation/save_migration_service_smoke.gd` (expected marker `SAVE MIGRATION SERVICE PASS`).

## REQ-SL-008: Meta / world / run scopes do not leak

- Source: ADR-0031, ADR-0007
- Type: process / scope
- Priority: must
- Status: Approved
- Acceptance criteria:
  - `SaveIndexState.slots` rows expose `slot_kind` and the kind drives what summary fields are valid; a `manual` slot never carries `world_summary`, and a `world` slot always carries it.
  - Loading a `manual` slot into a coordinator that has visited-ships state does not silently overwrite the world record.
  - Given an existing world slot and a manual save for the same player, when the manual save is loaded, then `current_location` is read from the manual slot but `visited_ships` is preserved from the world slot (load-time merge).
- Verification: `scripts/validation/save_slot_state_smoke.gd` (manual vs world distinction) + main-scene smoke end-to-end.

## REQ-SL-009: Permadeath resolver freezes the run and blocks invalid reloads

- Source: ADR-0032
- Type: gameplay / technical
- Priority: must
- Status: Approved
- Acceptance criteria:
  - `PermadeathResolver.record_death(cause, epitaph)` writes `user://saves/<slot_id>.death.json` containing the cause, an epitaph string, and a `died_at` timestamp.
  - The death-frozen slot returns `null` from `load_*` and reports `frozen=true` from `has_slot`.
  - Starting a new run to a different slot_id is allowed while the death-frozen slot persists.
  - Given a death-frozen slot, when `load_from_slot(dead_slot)` is called, then it returns null and the death record is preserved.
- Verification: `scripts/validation/save_migration_service_smoke.gd` (uses death-record fixture; marker still `SAVE MIGRATION SERVICE PASS`).

## REQ-SL-010: Cloud-ready manifest captures build + device + sync eligibility

- Source: ADR-0032
- Type: technical
- Priority: should
- Status: Approved
- Acceptance criteria:
  - `CloudManifestState` captures `device_id`, `build_id`, `schema_version`, `payload_sha256`, `created_at`, `sync_eligible` (bool), and `cloud_provider` placeholder.
  - The manifest is written alongside every successful save under `user://saves/.cloud/<slot_id>.manifest.json`.
  - The manifest's `payload_sha256` matches the SHA-256 of the slot file content.
- Verification: `scripts/validation/save_slot_state_smoke.gd` (manifest sha matches).

## REQ-SL-011: Save/load menu UI seam reads the slot index

- Source: ADR-0031
- Type: UX / technical
- Priority: should
- Status: Approved
- Acceptance criteria:
  - `SaveLoadMenu.refresh()` reads `SaveLoadService.list_slots()` and exposes rows `{slot_id, slot_kind, display_name, saved_at, current_location, objective_sequence, corrupt}`.
  - The menu seam is testable headlessly through its public methods.
  - Given 3 manual slots written to slot_01..03, when the menu is refreshed, then 3 rows are returned in `saved_at` desc order with no scene tree access required.
- Verification: pure-method test in `scripts/validation/save_slot_state_smoke.gd` (menu seam section).

## REQ-SL-012: Main-scene multi-slot save flow is end-to-end

- Source: ADR-0031, ADR-0032
- Type: technical / integration
- Priority: must
- Status: Approved
- Acceptance criteria:
  - Driving `PlayableGeneratedShip` through objective 1, writing to manual slot_01, writing a quicksave, then loading from slot_01, restores the same `objective_sequence`, `player_position`, and `current_objective_types` summary.
  - The autosave policy fires during a long simulated tick, the autosave slot is written, and the slot index gains an autosave row.
  - Corruption backup: a manual save corrupted in-place is backed up under `.corrupt/` and the index marks it `corrupt=true`.
- Verification: `scripts/validation/main_playable_slice_multislot_save_smoke.gd` (expected marker `MAIN PLAYABLE MULTISLOT SAVE PASS`).

## REQ-AU-001: All major gameplay events route through named audio events/buses

- Source: `features/audio-music-spatial.md`, ADR-0029
- Type: gameplay / technical
- Priority: must
- Status: Approved
- Rationale: Production audio must be driven by event ids, not by callers poking at buses or stream players directly. A named-event router centralizes volume mapping, dedup, captions, and bus routing.
- Acceptance criteria:
  - SfxEventRouter routes every documented event id (`sfx.tool.pickup`, `sfx.suit.breath`, `sfx.door.open`, `sfx.fire.crackle`, `sfx.arc.zap`, `ui.inventory.open`, `meta.beacon.distress`, …) to the correct bus (master / sfx / ui / voice / meta / ambient) using the per-event volume and dedup cooldown.
  - Unknown event ids are logged and dropped, never silently routed to master.
  - Each event has an optional closed-caption mapping that fires alongside the SFX.
- Verification:
  - `scripts/validation/sfx_event_router_smoke.gd`
  - `scripts/validation/main_playable_slice_audio_smoke.gd`

## REQ-AU-002: AudioBusConfig declares the full bus layout

- Source: `features/audio-music-spatial.md`, ADR-0029
- Type: technical
- Priority: must
- Status: Approved
- Acceptance criteria:
  - The canonical config `res://data/audio/audio_bus_config.tres` declares seven buses (master, sfx, music, voice, ui, ambient, meta) with default dB values clamped to [-60, 0].
  - Static schema validation rejects buses with empty ids, duplicate ids, unknown bus names, or out-of-range volumes.
  - Default values match the spec table in ADR-0029.
- Verification:
  - `scripts/validation/audio_bus_config_smoke.gd`

## REQ-AU-003: Ambient zones change by room role and threat

- Source: `features/audio-music-spatial.md`, ADR-0029
- Type: gameplay
- Priority: must
- Status: Approved
- Acceptance criteria:
  - Each room role (cargo, engine, med_bay, crew_quarters, docking) maps to a deterministic ambient track id and base intensity.
  - Entering a new zone fades the previous ambient layer out (default 1.5s) and the new layer in (default 1.5s).
  - A threat-driven intensity layer adds gain when any hazard state moves to non-safe (any of oxygen/fire/arc hazards triggers a threat meter rise).
- Verification:
  - `scripts/validation/ambient_zone_state_smoke.gd`
  - `scripts/validation/main_playable_slice_audio_smoke.gd`

## REQ-AU-004: Dynamic music layers respond to exploration/tension/combat/critical vitals

- Source: `features/audio-music-spatial.md`, ADR-0029
- Type: gameplay
- Priority: must
- Status: Approved
- Acceptance criteria:
  - DynamicMusicState owns four named states (EXPLORATION, TENSION, COMBAT, CRITICAL) with per-state layer set and per-layer target gain.
  - State transitions are deterministic: COMBAT engages when the engagement flag is true, TENSION when any hazard is non-safe, CRITICAL when vitals model reports unsafe vitals (oxygen <= 0.0 OR hp below critical threshold), EXPLORATION otherwise.
  - Layer gain changes use a configurable crossfade duration (default 2.0s) with at most one fade in flight per layer.
- Verification:
  - `scripts/validation/dynamic_music_state_smoke.gd`

## REQ-AU-005: Spatial attenuation and occlusion is deterministic and testable

- Source: `features/audio-music-spatial.md`, ADR-0029
- Type: technical
- Priority: must
- Status: Approved
- Acceptance criteria:
  - `SpatialAudioResolver.resolve_volume_db(emitter_pos, listener_pos, occluded, base_db)` returns `(base_db) - attenuation_distance - occlusion_penalty`.
  - Attenuation distance uses the configured max-distance and rolloff curve; identical inputs always produce identical outputs (no RNG).
  - Occlusion penalty is a constant (default -6 dB) when `occluded=true` and 0 dB when `false`.
  - Empty / zero-distance inputs return the configured base_db without NaN / -inf.
- Verification:
  - `scripts/validation/spatial_audio_resolver_smoke.gd`

## REQ-AU-006: Voice / audio log entries replay through the `voice` bus

- Source: `features/audio-music-spatial.md`, ADR-0029
- Type: gameplay
- Priority: should
- Status: Approved
- Acceptance criteria:
  - AudioLog is a data-only registry of entries (id, label, transcript, clip_path, duration).
  - Triggered playback (manual or meta-event-driven) routes through the `voice` bus with the configured per-entry volume.
  - The audio_log_panel exposes play / pause / stop / jump-to-entry.
- Verification:
  - `scripts/validation/main_playable_slice_audio_smoke.gd`

## REQ-AU-007: Meta-events are deterministic scripted dispatches

- Source: `features/audio-music-spatial.md`, ADR-0029
- Type: gameplay
- Priority: must
- Status: Approved
- Acceptance criteria:
  - MetaEventState holds a deterministic schedule (seed-derived) of meta-events with id, trigger_time, voice_log_entry_id.
  - `tick(delta)` advances time and fires any events whose trigger_time has elapsed; firing is recorded in the summary and never re-fires for the same id within a run.
  - Firing routes through the `meta` bus and optionally queues a voice-log entry.
- Verification:
  - `scripts/validation/meta_event_state_smoke.gd`

## REQ-AU-008: Audio settings panel exposes per-bus volume and toggles

- Source: `features/audio-music-spatial.md`, ADR-0029
- Type: gameplay / accessibility
- Priority: should
- Status: Approved
- Acceptance criteria:
  - AudioSettingsPanel exposes per-bus volume sliders, mute toggles, closed-caption toggle, voice-log toggle.
  - The panel cascades through `accessibility_settings.scaled_hud_font_size` for A11Y-P1-001 compatibility.
  - Adjusting a slider persists into `audio_summary` and survives a save/load round-trip.
- Verification:
  - `scripts/validation/main_playable_slice_audio_smoke.gd`
  - `scripts/validation/audio_save_load_smoke.gd`

## REQ-AU-009: Closed captions appear for SFX events

- Source: `features/audio-music-spatial.md`, ADR-0029
- Type: gameplay / accessibility
- Priority: should
- Status: Approved
- Acceptance criteria:
  - SfxEventRouter has a caption map keyed by event id; firing an event with a caption appends the caption to the HUD caption queue for the configured display duration.
  - The closed-caption toggle in the audio settings panel disables the caption queue without suppressing the SFX itself.
- Verification:
  - `scripts/validation/sfx_event_router_smoke.gd`
  - `scripts/validation/main_playable_slice_audio_smoke.gd`

## REQ-AU-010: Audio summary round-trips through save/load

- Source: `features/audio-music-spatial.md`, ADR-0029
- Type: technical
- Priority: must
- Status: Approved
- Acceptance criteria:
  - `RunSnapshot.audio_summary` carries bus_config, ambient, sfx_router, music, spatial, meta_event sub-summaries.
  - Saving then loading restores all six sub-summaries and re-applies them to the live models in the playable scene.
  - The SaveLoadService smoke `summaries` count rises to 9 (was 8).
- Verification:
  - `scripts/validation/audio_save_load_smoke.gd`
  - existing `scripts/validation/save_load_service_smoke.gd` updated assertion (summaries=9)

## REQ-PG-001: At least six seed-deterministic template variants

- Source: `features/procedural_generation_expansion.md`, `build-plans/12-procedural-generation-expansion-e2e.md`
- Type: technical
- Priority: must
- Status: Proposed
- Rationale: Phase 1 procgen shipped three templates; the content-complete target requires at least six template/variant seeds to prove the pipeline generalises. Six or more variants also keep seed-diversity meaningful.
- Acceptance criteria:
  - At least six topology templates (the three existing `spine` / `bifurcated` / `stacked` + three or more new) are loaded by `TemplateSelector` and assigned by seed.
  - Every new template JSON loads successfully via `TopologyTemplate.from_dict()` and produces a non-empty `zones` / `connections` pair.
  - The selector picks a valid template id (one of the registered set) for any seed in `[0, 1_000_000)`.
  - Same seed always picks the same template id.
- Verification:
  - `scripts/validation/room_variant_selector_smoke.gd` (asserts template variant enumeration and seeded selection).
  - `scripts/validation/seed_determinism_smoke.gd` (asserts same seed picks same template id).

## REQ-PG-002: Per-room variant selection

- Source: `features/procedural_generation_expansion.md`
- Type: gameplay
- Priority: must
- Status: Proposed
- Rationale: Every room role (airlock, corridor, bridge, cargo, medical, etc.) should produce a deterministic variant string (`standard` / `bio_seal` / `refrigerated` / etc.) so per-room dressing, lighting, and HUD detail can vary without changing room roles.
- Acceptance criteria:
  - `RoomVariantSelector.pick(role, room_index, seed)` returns a non-empty variant string for every known role.
  - Same `(role, room_index, seed)` always returns the same variant (determinism).
  - Unknown roles fall back to `standard` without raising.
  - At least four distinct variants exist per common role (airlock, corridor, cargo, medical).
- Verification:
  - `scripts/validation/room_variant_selector_smoke.gd`

## REQ-PG-003: Kit catalog with role-aligned kits

- Source: `features/procedural_generation_expansion.md`
- Type: technical
- Priority: must
- Status: Proposed
- Rationale: The structural placer currently uses one hardcoded module list per role. The kit catalog decouples role → module-list mapping so hazard-biased or industrial-biased kits can dress the same room role differently.
- Acceptance criteria:
  - `KitCatalog.configure()` loads every JSON file under `res://data/kits/` and registers it under its `kit_id`.
  - `kit_catalog.kits_for_role(role, biome)` returns a non-empty Array[String] for every known role in every loaded kit.
  - Missing kits fall back to `ship_structural_v0` without raising.
  - The structural placer reads from `KitCatalog` when a `kit_id` is supplied, and falls back to its built-in list otherwise (backward compatible).
- Verification:
  - `scripts/validation/kit_catalog_smoke.gd`

## REQ-PG-004: Template C vertical traversal integrity

- Source: `features/procedural_generation_expansion.md`, `features/layout_template_c.md`
- Type: technical
- Priority: must
- Status: Proposed
- Rationale: Template C is the third hand-authored ship layout. Its two-deck design is the first topology that exercises vertical traversal; the procgen pipeline must validate every ramp and elevator transition has both endpoints, both decks, and stays inside deck bounds.
- Acceptance criteria:
  - `TemplateCTraversal.validate(layout)` returns `valid=true` for every `stacked` template generation.
  - Every `vertical_connections` entry has `from_room` and `to_room` in `layout.rooms`, `from_deck != to_deck`, and both endpoint cells are present in their deck's `rooms[deck].cells`.
  - A fabricated layout with a missing vertical endpoint returns `valid=false` and a stable `error_code` (`missing_room` / `deck_mismatch` / `cell_missing`).
- Verification:
  - `scripts/validation/template_c_traversal_smoke.gd`

## REQ-PG-005: Biome profile

- Source: `features/procedural_generation_expansion.md`
- Type: gameplay
- Priority: must
- Status: Proposed
- Rationale: Biomes (`abyssal_sargasso` / `breach_field` / `dead_fleet`) add flavour without changing layout. A biome must scale hazard density, loot quality, and encounter density by deterministic multipliers.
- Acceptance criteria:
  - `BiomeProfile.from_dict(json)` round-trips a JSON file under `res://data/procgen/biomes/`.
  - `BiomeProfile.modifier()` for `hazard_modifier` / `loot_quality_modifier` / `encounter_density_modifier` returns the value from JSON (default 1.0).
  - Unknown biome id raises a typed error but never crashes the loader.
  - The selector picks a valid biome id for any seed; same seed always picks the same biome.
- Verification:
  - `scripts/validation/biome_profile_smoke.gd`

## REQ-PG-006: Difficulty profile

- Source: `features/procedural_generation_expansion.md`
- Type: gameplay
- Priority: must
- Status: Proposed
- Rationale: Difficulty presets (`standard` / `hardened` / `deep_dive`) scale the same dials the biome touches. Difficulty and biome compose multiplicatively so a `breach_field` biome on `deep_dive` is meaningfully harder than either alone.
- Acceptance criteria:
  - `DifficultyProfile.from_dict(json)` round-trips a JSON file under `res://data/procgen/difficulty/`.
  - `combined_modifier(biome, difficulty, dial)` returns `biome.modifier * difficulty.modifier`, clamped to `[0.0, 3.0]`.
  - Unknown difficulty id raises a typed error.
  - The selector picks a valid difficulty id for any seed; same seed always picks the same difficulty.
- Verification:
  - `scripts/validation/difficulty_profile_smoke.gd`

## REQ-PG-007: Encounter injection produces valid spawn markers

- Source: `features/procedural_generation_expansion.md`
- Type: gameplay
- Priority: must
- Status: Proposed
- Rationale: Combat needs deterministic encounter spawn markers derived from biome + difficulty + room layout. The injector must skip critical-path rooms and emit markers combat can consume.
- Acceptance criteria:
  - `EncounterInjector.inject(layout, biome, difficulty, seed)` returns a Dictionary with key `encounters` (Array) embedded in the layout.
  - Every spawn marker has `id` (unique within layout), `room_id` (in `layout.rooms`), `deck` (matches room deck), `cell` (in `room.cells`), `encounter_kind` (non-empty), `count` (>= 1), `difficulty_tier` (matches the supplied difficulty), `seed_offset` (>= 0).
  - No critical-path room carries an encounter marker.
  - Same `(layout, biome, difficulty, seed)` always produces the same marker set (determinism).
- Verification:
  - `scripts/validation/encounter_injector_smoke.gd`

## REQ-PG-008: Seed determinism contract

- Source: `features/procedural_generation_expansion.md`
- Type: technical
- Priority: must
- Status: Proposed
- Rationale: All procgen outputs must be deterministic by seed so QA can reproduce any ship and so save/load can be replayed. The contract hash provides a stable byte-equal fingerprint for any `(seed, archetype, biome, difficulty)` tuple.
- Acceptance criteria:
  - `SeedDeterminismContract.fnv1a_64(text)` returns the same 64-bit integer on every run.
  - `SeedDeterminismContract.assert_layout_match(blueprint, archetype, biome, difficulty)` returns `match=true` when run twice and the layouts are byte-equal under `JSON.stringify(layout, "  ")`.
  - The contract hash for a recorded golden seed matches the recorded hash across runs.
- Verification:
  - `scripts/validation/seed_determinism_smoke.gd`

## REQ-PG-009: Hazard density scales with biome+difficulty

- Source: `features/procedural_generation_expansion.md`, ADR-0005
- Type: gameplay
- Priority: must
- Status: Proposed
- Rationale: Higher hazard density must not break connectivity — biome+difficulty modify hazard / loot / encounter counts while the underlying critical path stays intact.
- Acceptance criteria:
  - A `breach_field` biome at `deep_dive` difficulty places at least one oxygen-breach hazard zone on a non-critical link.
  - Hazard density (zones per non-critical link) follows the combined biome*difficulty multiplier within the `[0.0, 3.0]` clamped range.
  - The critical path BFS in `LayoutSerializer._build_critical_path()` still reaches the destination from the entry room after hazard placement.
- Verification:
  - `scripts/validation/biome_profile_smoke.gd` (multiplier check)
  - `scripts/validation/difficulty_profile_smoke.gd` (composition check)
  - `scripts/validation/encounter_injector_smoke.gd` (non-critical placement)

## REQ-PG-010: Layout JSON schema bump with additive `encounters` field

- Source: `features/procedural_generation_expansion.md`
- Type: technical
- Priority: must
- Status: Proposed
- Rationale: Encounter markers must be embedded in the layout JSON so the loader spawns combat threats from the layout, not a separate runtime feed. The schema bumps `1.1.0` → `1.2.0` and adds a single new top-level key.
- Acceptance criteria:
  - `LayoutSerializer.serialize(...)` writes `schema_version: "1.2.0"` and a non-null `encounters` array (possibly empty).
  - Each encounter marker matches the schema in REQ-PG-007.
  - The `GeneratedShipLoader` reads `layout.encounters` if present and silently ignores the field when it is absent (older 1.1.0 layouts).
- Verification:
  - `scripts/validation/encounter_injector_smoke.gd` (schema field assertion)

## REQ-PG-011: At least six templates selectable by seed

- Source: `features/procedural_generation_expansion.md`, `build-plans/12-procedural-generation-expansion-e2e.md`
- Type: technical
- Priority: must
- Status: Proposed
- Rationale: The acceptance criterion "at least six templates/variants are deterministic by seed" is the package's headline number. The smoke must enumerate every selectable template id and prove seeded selection returns a valid id.
- Acceptance criteria:
  - `TemplateSelector` exposes at least six template ids across the existing and new template set.
  - For every seed in `[0, 1_000)`, the selector returns a non-empty id and the id is in the registered set.
  - Same seed always returns the same id.
- Verification:
  - `scripts/validation/room_variant_selector_smoke.gd`
  - `scripts/validation/seed_determinism_smoke.gd`

## REQ-PG-012: Layout-time state does not leak into RunSnapshot

- Source: `features/procedural_generation_expansion.md`, ADR-0007 / ADR-0010
- Type: technical
- Priority: must
- Status: Proposed
- Rationale: Biome / difficulty / variants are layout-time state, not gameplay state. Save/load must not store them in `RunSnapshot`; if needed, they are recovered by re-running the seed through the pipeline.
- Acceptance criteria:
  - `RunSnapshot` schema is unchanged; no new top-level fields are added by this package.
  - The SaveLoadService smoke `summaries` count stays at the value it had before this package (8 today, 9 after REQ-AU-010 — but never 10+ because of REQ-PG-012).
  - Re-running the seed through the procgen pipeline produces the same biome / difficulty / variants as the original layout.
- Verification:
  - `scripts/validation/save_load_service_smoke.gd` (summaries count unchanged after package)
  - `scripts/validation/seed_determinism_smoke.gd` (round-trip match)

## REQ-RL-001: Export preset validation

- Source: `docs/game/features/release_distribution.md`, ADR-0029
- Type: technical / process
- Priority: must
- Status: Approved
- Rationale: A bad preset path or a missing preset key would only surface at release time when fixing it costs a day. The export pipeline runs once; we need a smoke that proves the config is well-formed before invoking `godot --export-release`.
- Acceptance criteria:
  - `export_presets.cfg` parses cleanly.
  - Every preset has the required keys (`name`, `platform`, `export_path`, `runnable`, `include_filter`, `exclude_filter`).
  - Every preset's `export_path` starts with `build/exports/<preset_name>/`.
  - The smoke reports the preset count and passes a known-good four-preset config.
- Verification:
  - `scripts/validation/export_presets_smoke.gd` (marker `EXPORT PRESETS PASS presets=N all_runnable=true paths_under_build=true`)

## REQ-RL-002: Build metadata state

- Source: `docs/game/features/release_distribution.md`, ADR-0029
- Type: technical
- Priority: must
- Status: Approved
- Rationale: The demo gate, the release badge overlay, and the release readiness ledger all need a single source of truth for "what kind of build is running." Without it, three independent switches could disagree.
- Acceptance criteria:
  - `BuildMetadataState.configure(manifest)` accepts a dictionary carrying `version`, `build_kind`, `store`, `language_defaults`, `achievements_supported`.
  - `get_build_kind()` returns one of `dev`, `demo`, `release`.
  - `is_achievements_supported()` returns the boolean from the manifest.
  - `get_summary()` carries every input key plus a `build_kind_validated` boolean that asserts the kind is one of the three known values.
- Verification:
  - `scripts/validation/export_presets_smoke.gd` (load_metadata=true asserts the catalog loads with a known `build_kind`).
  - Implicit coverage by `demo_scope_gate_smoke.gd` and `release_readiness_ledger_smoke.gd`.

## REQ-RL-003: Achievement catalog (data-driven)

- Source: `docs/game/features/release_distribution.md`, ADR-0030
- Type: gameplay / process
- Priority: must
- Status: Approved
- Rationale: Steam / itch achievements require a storefront-ingestible catalog AND runtime events triggered by real gameplay, not by debug flags. Hard-coded `if (event) { unlock(...) }` calls are a recipe for missed unlocks and double-unlocks.
- Acceptance criteria:
  - `data/release/achievement_catalog.json` parses and lists ≥ 5 achievements at launch.
  - Every entry has `id`, `display_name`, `description`, `icon_placeholder`, `trigger_event`, `trigger_target`.
  - `AchievementState.unlock(id)` returns `false` for unknown ids (catalog is the only source of truth).
  - Duplicate unlock returns `false` (idempotent; no double-unlock).
- Verification:
  - `scripts/validation/achievement_state_smoke.gd` (marker `ACHIEVEMENT STATE PASS unlocked=N catalog=N unknown_rejected=true`).

## REQ-RL-004: Achievement state persistence

- Source: `docs/game/features/release_distribution.md`, ADR-0030, ADR-0007
- Type: technical
- Priority: must
- Status: Approved
- Rationale: Player unlocks must survive crashes and game exits but MUST stay per-run (ADR-0007 boundary). A separate file from the run snapshot keeps the two lifecycles independent.
- Acceptance criteria:
  - Achievement state persists at `user://achievements.json` with schema `release-achievements-1`.
  - Save / load round-trip preserves the unlock set.
  - A new run wipes the unlock set; cross-run state is preserved by an external service (Steamworks, deferred).
- Verification:
  - `scripts/validation/achievement_state_smoke.gd` (round-trip + new-run wipe asserted).

## REQ-RL-005: Localization catalog

- Source: `docs/game/features/release_distribution.md`, ADR-0031
- Type: technical
- Priority: must
- Status: Approved
- Rationale: Hard-coded English in every HUD line blocks non-English releases. A pure-data catalog with fallback rules lets translators ship a language pack as a JSON file.
- Acceptance criteria:
  - `data/release/localization_catalog.json` parses with at least one language (`en`) and at least 5 string ids.
  - `LocalizationCatalog.translate(id, lang)` returns the translation when present.
  - Unknown id → empty string (or supplied fallback text via `translate_fallback`).
  - Unknown language → default language's text.
  - Missing translation key inside a known language → default language's text (HUD never goes blank).
- Verification:
  - `scripts/validation/localization_catalog_smoke.gd` (marker `LOCALIZATION CATALOG PASS languages=N translations=N fallback=true unknown_returns_default=true`).

## REQ-RL-006: Demo scope gate

- Source: `docs/game/features/release_distribution.md`, ADR-0029
- Type: technical / process
- Priority: must
- Status: Approved
- Rationale: A Steam demo build must restrict content without crashing the rest of the engine. A data-driven manifest lets the demo team add a restriction in JSON instead of writing a code branch.
- Acceptance criteria:
  - `data/release/demo_scope_manifest.json` parses and lists demo-restricted features.
  - `DemoScopeGate.is_allowed(id)` returns `true` when `build_kind == "full"` or `"dev"`.
  - `is_allowed(id)` returns `false` when the id is in the manifest AND `build_kind == "demo"`.
  - Unknown ids return `false` (no silent allow; the gate must be explicit).
- Verification:
  - `scripts/validation/demo_scope_gate_smoke.gd` (marker `DEMO SCOPE GATE PASS build_kind=<full|demo> blocked=<n> allowed=<n> unknown_rejected=true`).

## REQ-RL-007: Crash report bundle

- Source: `docs/game/features/release_distribution.md`, ADR-0029
- Type: technical
- Priority: should
- Status: Approved
- Rationale: Players report "the game closed" without data. A disk-side crash bundle captures the last 256 log entries so a support ticket has something to work with. The bundle is disk-only in this package; upload is a deferred telemetry concern.
- Acceptance criteria:
  - `CrashReportBundle.capture(message, context, stack)` appends an entry.
  - `flush(path)` writes a JSON bundle of `{entries: [...], captured_at: ...}`.
  - Cap at 256 entries FIFO; older entries are dropped.
  - `clear()` empties the in-memory list.
- Verification:
  - Coverage by `release_readiness_ledger_smoke.gd` (it captures a crash entry and asserts the bundle round-trips).

## REQ-RL-008: Release readiness ledger

- Source: `docs/game/features/release_distribution.md`, ADR-0029
- Type: technical / process
- Priority: must
- Status: Approved
- Rationale: A gate reviewer needs a machine-checkable manifest that distinguishes local smoke output from external (Steam / itch / human) evidence. Without the tag, "looks good to me" cannot be audited.
- Acceptance criteria:
  - `data/release/release_checklist.json` parses with ≥ 1 check per category (`pre_launch`, `launch_day`, `post_launch`).
  - `record_local_evidence(check_id, status, evidence_path)` adds a row with `source=local`.
  - `record_external_evidence(check_id, status, evidence_path, captured_at)` adds a row with `source=external`.
  - Empty `evidence_path` for a `source=external` row is REJECTED (no silent acceptance).
  - `get_summary()` returns the row count split by `local` and `external`.
- Verification:
  - `scripts/validation/release_readiness_ledger_smoke.gd` (marker `RELEASE READINESS LEDGER PASS rows=N local=N external=N external_evidence_required=true`).

## REQ-RL-009: Credits and attribution

- Source: `docs/game/features/release_distribution.md`, ADR-0029
- Type: process
- Priority: must
- Status: Approved
- Rationale: A shipped game must carry credits (Project Zomboid ships dozens of community attributions). The credits screen reads a JSON file so a future contributor addition is a JSON edit.
- Acceptance criteria:
  - `data/release/credits.json` parses with ≥ 5 entries.
  - Every entry has `role` and `name`.
  - `CreditsScreen` script loads and renders the catalog (smoke proves the script parses as Godot loadable).
- Verification:
  - Coverage by `release_readiness_ledger_smoke.gd` (asserts the credits catalog loads) and `export_presets_smoke.gd` (catalog integrity check).

## REQ-RL-010: Post-launch playbook

- Source: `docs/game/features/release_distribution.md`, ADR-0029
- Type: process
- Priority: should
- Status: Approved
- Rationale: "Ship it" is not a release plan. A post-launch playbook surfaces the cadence (patch schedule, telemetry review, mod-policy posture, community engagement) as machine-checkable rows in the release readiness ledger.
- Acceptance criteria:
  - `data/release/release_checklist.json` carries at least one check per category (`pre_launch`, `launch_day`, `post_launch`).
  - The release ledger smoke asserts the per-category split.
  - No new gameplay state is added by this package (process-only).
- Verification:
  - `scripts/validation/release_readiness_ledger_smoke.gd` (category split asserted).

## REQ-UI-001: Top-level menu stack is navigable by keyboard, mouse, and controller

- Source: `docs/game/features/ui_ux_accessibility.md`, ADR-0033
- Type: gameplay
- Priority: must
- Status: Approved
- Rationale: Players must reach every menu surface without a keyboard (controller) and without a controller (keyboard / mouse). The menu state machine, focus index, and the dedicated input actions `ui_up / ui_down / ui_left / ui_right / ui_accept / ui_cancel` must work uniformly on every device.
- Acceptance criteria:
  - `MenuState` exposes `current_menu`, `menu_history`, and `focus_index`; headless transitions (`open_menu`, `close_top`, `navigate(dx, dy)`, `confirm`, `cancel`) work without scene-tree access.
  - The main menu lists Start / Continue / Settings / Quit and Continue is disabled when no save exists.
  - The pause menu lists Resume / Settings / Codex / Save / Quit to Main and is reachable via the `ui_pause` action (default `KEY_ESCAPE` + gamepad start).
  - Every menu's items render with the AccessibilitySettings text-scale seam.
- Verification:
  - `scripts/validation/menu_state_smoke.gd`
  - `scripts/validation/main_playable_slice_ui_shell_smoke.gd`

## REQ-UI-002: HUD exposes survival / combat / ship information without overlap

- Source: `docs/game/features/ui_ux_accessibility.md`, ADR-0033
- Type: gameplay
- Priority: must
- Status: Approved
- Rationale: Locked-isometric readability requires that every critical signal has a fixed, non-overlapping screen anchor. The HUD layout manager owns the anchors and rejects overlapping rectangles via `HUDLayoutManager.assert_no_overlap(panels)`.
- Acceptance criteria:
  - ObjectiveTracker anchors top-left, PlayerVitalsPanel anchors bottom-left, MinimapPanel anchors top-right, HotbarPanel anchors bottom-center, TutorialOverlayPanel anchors top-center, CodexHintPanel anchors bottom-right.
  - At text-scale 2.0x none of the panels overflow the viewport.
  - The status lines fed into PlayerVitalsPanel come from the live vitals model (not a cached string).
- Verification:
  - `scripts/validation/main_playable_slice_ui_shell_smoke.gd`
  - existing `scripts/validation/main_playable_slice_vitals_hud_smoke.gd`

## REQ-UI-003: SettingsState persists across save/load and applies at runtime

- Source: `docs/game/features/ui_ux_accessibility.md`, ADR-0033
- Type: technical
- Priority: must
- Status: Approved
- Rationale: Settings are the player's expression of accessibility / difficulty preference. Changes must apply immediately and survive the next session. `SettingsState.apply_to_accessibility(a11y)` writes back to the existing `AccessibilitySettings` so the rest of the HUD keeps its single source of truth.
- Acceptance criteria:
  - `SettingsState` owns text_scale, colorblind_mode, motion_reduce, captions, hold_to_tap, difficulty, glyph_scheme.
  - `apply_to_accessibility(a11y)` sets every field on the existing AccessibilitySettings and never creates a duplicate seam.
  - `RunSnapshot.settings_summary` carries the settings dict and survives a save / load round-trip field-for-field.
  - Older saves (schema < 1.1.0) load with `settings_summary = null` and the in-memory state re-bootstraps from defaults.
- Verification:
  - `scripts/validation/settings_state_smoke.gd`
  - `scripts/validation/ui_shell_save_load_smoke.gd`

## REQ-UI-004: TooltipPresenter resolves queries to payloads via a registered catalog

- Source: `docs/game/features/ui_ux_accessibility.md`, ADR-0033
- Type: technical
- Priority: must
- Status: Approved
- Rationale: Multiple UI surfaces (interactable prompts, inventory rows, codex entries) all need a uniform "what is this?" tooltip. A single presenter keeps the catalog, formatting, and unknown-id fallback in one place.
- Acceptance criteria:
  - `TooltipPresenter.configure(catalog)` loads `data/ui/tooltip_catalog.json` and rejects malformed entries (missing id, empty title, mismatched subject_kind).
  - `resolve(query)` returns a `TooltipPayload` (title, body, footer) for known `(subject_kind, subject_id)` pairs and `null` for unknown ids.
  - The catalog carries at least 12 entries covering the major interactable / item / hazard kinds.
- Verification:
  - `scripts/validation/tooltip_presenter_smoke.gd`

## REQ-UI-005: Tutorials trigger once per `(event, target)` pair per run, can be skipped, and unlock codex help

- Source: `docs/game/features/ui_ux_accessibility.md`, ADR-0033
- Type: gameplay
- Priority: must
- Status: Approved
- Rationale: First-time players need guided affordances; experienced players need the ability to skip. Tutorials that the player has seen must remain reachable in the codex so they are never blocked by dismissal.
- Acceptance criteria:
  - `TutorialState.trigger(event, target)` is idempotent for the same pair (returns the tutorial id the first time, empty string on re-fire).
  - `TutorialState.dismiss(tutorial_id)` removes the banner and unlocks the matching codex entry; the entry remains available in `codex_panel`.
  - The trigger catalog (`data/ui/tutorial_triggers.json`) carries at least 6 entries covering: first move, first interact, first inventory open, first save, first travel, first objective complete.
  - A tutorial cannot fire on an unknown `(event, target)` pair.
- Verification:
  - `scripts/validation/tutorial_state_smoke.gd`

## REQ-UI-006: Minimap / map-of-the-ship with deterministic fog-of-war

- Source: `docs/game/features/ui_ux_accessibility.md`, ADR-0033
- Type: gameplay
- Priority: must
- Status: Approved
- Rationale: Locked-isometric visibility is limited; the player needs a top-down map to plan traversal. A deterministic fog-of-war state derived from the room graph keeps the system headless-testable.
- Acceptance criteria:
  - `MapFogState.configure_for_rooms(room_ids)` initialises every room as `discovered=false`, `revealed=false`.
  - `reveal(room_id)` and `discover(room_id)` mark the room and propagate discovery to its neighbours (so adjacent rooms become `discovered` even if not yet visited).
  - `track(room_id)` updates the player's current location; tracking an unknown room id is rejected.
  - The fog state summary round-trips through `apply_summary`.
- Verification:
  - `scripts/validation/map_fog_state_smoke.gd`

## REQ-UI-007: ControllerGlyphState resolves action names to glyphs per scheme

- Source: `docs/game/features/ui_ux_accessibility.md`, ADR-0033
- Type: technical
- Priority: must
- Status: Approved
- Rationale: HUD prompts must reflect the input device the player is using. Reading the actually-bound keycode (rather than a hard-coded label) means swapping input bindings keeps the glyph correct.
- Acceptance criteria:
  - `ControllerGlyphState.configure(bindings_table, glyph_table)` populates the per-scheme glyph map and rejects unknown action names.
  - `glyph_for(action_name, scheme)` returns the glyph text for the requested scheme and falls back to `keyboard` when the scheme key is missing.
  - The glyph table (`data/ui/input_glyphs.json`) carries entries for at least 6 actions across all three schemes (`keyboard`, `gamepad_xbox`, `gamepad_ps`).
- Verification:
  - `scripts/validation/controller_glyph_state_smoke.gd`

## REQ-UI-008: AccessibilitySettings is the single runtime seam for HUD text + accessibility

- Source: `docs/game/features/ui_ux_accessibility.md`, ADR-0033
- Type: accessibility
- Priority: must
- Status: Approved
- Rationale: One seam means one source of truth for every accessibility / HUD-text concern. Adding a new accessibility field (colorblind mode, motion reduce, captions, hold-to-tap) MUST live on `AccessibilitySettings`, never on a duplicate seam.
- Acceptance criteria:
  - `AccessibilitySettings` exposes text_scale, colorblind_mode, motion_reduce, captions, hold_to_tap, preset_id, difficulty, glyph_scheme with typed getters / setters and clamp helpers.
  - Default values reproduce the pre-package behaviour exactly so the existing A11Y-P1-001 smoke stays green.
  - `apply_preset(preset_id)` writes the preset's full field set onto the same instance (never creates a duplicate).
- Verification:
  - `scripts/validation/settings_state_smoke.gd`
  - existing `scripts/validation/main_playable_slice_text_scale_smoke.gd` (must still pass)

## REQ-UI-009: Pause menu opens via `ui_pause` and freezes player input

- Source: `docs/game/features/ui_ux_accessibility.md`, ADR-0033
- Type: gameplay
- Priority: must
- Status: Approved
- Rationale: While the pause menu is open, the player must not move, interact, or trigger accidental save/load. Closing the pause menu restores control via the panel-closed signal (mirrors the ScannerPanel / InventoryPanel contract).
- Acceptance criteria:
  - The `ui_pause` action is bound to KEY_ESCAPE + gamepad start by default.
  - Pressing `ui_pause` while in-play opens the pause menu and disables the player's physics / input / unhandled-input.
  - Pressing `ui_pause` again (or selecting Resume) closes the menu and restores control.
  - The pause menu cannot open during slice_complete or during another modal panel (scanner / inventory).
- Verification:
  - `scripts/validation/main_playable_slice_ui_shell_smoke.gd`

## REQ-UI-010: Codex is reachable from pause menu and lists every unlocked entry

- Source: `docs/game/features/ui_ux_accessibility.md`, ADR-0033
- Type: gameplay
- Priority: must
- Status: Approved
- Rationale: Players need a stable reference for mechanics they encountered briefly during a tutorial. The codex must list every entry `TutorialState.unlock_codex(id)` has emitted.
- Acceptance criteria:
  - The codex panel subscribes to `TutorialState.unlock_events` and rebuilds the entry list on every change.
  - Each codex entry shows topic, title, and body sourced from `data/ui/codex_entries.json`.
  - The codex panel closes via `ui_cancel` (Escape / gamepad B).
- Verification:
  - `scripts/validation/tutorial_state_smoke.gd`
  - `scripts/validation/main_playable_slice_ui_shell_smoke.gd`

## REQ-UI-011: Hotbar shows the selected tool / item from the inventory

- Source: `docs/game/features/ui_ux_accessibility.md`, ADR-0033
- Type: gameplay
- Priority: should
- Status: Approved
- Rationale: A bottom-center hotbar gives the player a quick visual of the currently-held item. The hotbar is a passive viewer; selecting a slot updates the inventory's selection model (REQ-007 surface).
- Acceptance criteria:
  - `HotbarPanel.set_selection(inventory, slot_index)` renders the slot's icon label and the matching glyph for the use action.
  - The hotbar renders 5 slots by default; an empty slot shows a placeholder glyph.
  - The hotbar is hidden while the main menu / pause menu is open.
- Verification:
  - `scripts/validation/main_playable_slice_ui_shell_smoke.gd`

## REQ-UI-012: Tutorial banner shows the current tutorial title and body

- Source: `docs/game/features/ui_ux_accessibility.md`, ADR-0033
- Type: gameplay
- Priority: must
- Status: Approved
- Rationale: The first time a mechanic is available, the player needs a transient banner. The banner must not stack (only the latest tutorial is visible) and must disappear after 5s, on dismiss, or on a new trigger.
- Acceptance criteria:
  - `TutorialOverlayPanel.bind(tutorial_state)` subscribes to the latest-fired tutorial.
  - The banner shows the tutorial's title and body; the dismiss action removes it.
  - A reduced-motion setting disables the slide-in animation.
- Verification:
  - `scripts/validation/tutorial_state_smoke.gd`
  - `scripts/validation/main_playable_slice_ui_shell_smoke.gd`

## REQ-UI-013: Tooltip panel renders the current TooltipPresenter payload

- Source: `docs/game/features/ui_ux_accessibility.md`, ADR-0033
- Type: gameplay
- Priority: should
- Status: Approved
- Rationale: Context prompts surface contextual info ("press E to interact") on demand. The tooltip panel is the visible face of `TooltipPresenter`.
- Acceptance criteria:
  - `TooltipPanel.bind(presenter, input_source)` subscribes to query changes from the input source (e.g. an interactable Area3D).
  - The panel renders title, body, and footer for the current payload and hides itself when `presenter.resolve()` returns null.
- Verification:
  - `scripts/validation/tooltip_presenter_smoke.gd`
  - `scripts/validation/main_playable_slice_ui_shell_smoke.gd`

## REQ-UI-014: Difficulty preset applies gameplay-side multipliers

- Source: `docs/game/features/ui_ux_accessibility.md`, ADR-0033
- Type: gameplay
- Priority: should
- Status: Approved
- Rationale: A difficulty toggle gives the player control over the gameplay challenge without changing the HUD. The preset writes a `difficulty_multiplier` into `AccessibilitySettings` so downstream systems (hazard spawn rates, loot quality) can read it.
- Acceptance criteria:
  - The difficulty preset loads from `data/ui/accessibility_presets.json` and writes the per-preset multipliers onto the same AccessibilitySettings instance.
  - The multipliers surface in the pause-menu / codex / tooltip text and in the settings_state summary.
  - The multipliers do not retroactively change live hazard state (a reload is required to apply mid-run).
- Verification:
  - `scripts/validation/settings_state_smoke.gd`

## REQ-UI-015: UI input map adds `ui_up / ui_down / ui_left / ui_right / ui_accept / ui_cancel / ui_pause / ui_open_codex / ui_open_map` actions

- Source: `docs/game/features/ui_ux_accessibility.md`, ADR-0033
- Type: technical
- Priority: must
- Status: Approved
- Rationale: Menu navigation needs a uniform action surface that works on keyboard, mouse, and gamepad. The existing `ensure_default_input_actions` already covers movement + interact; this requirement extends it with the menu navigation surface.
- Acceptance criteria:
  - Every new UI action is registered in `ensure_default_input_actions` with both keyboard and gamepad bindings.
  - The `ui_pause` action is bound to KEY_ESCAPE + gamepad start by default.
  - Re-running `ensure_default_input_actions` is idempotent (no duplicate events).
- Verification:
  - `scripts/validation/main_playable_slice_ui_shell_smoke.gd`
  - existing `scripts/validation/a11y_p1_002_idempotency_smoke.gd` (must still pass)

## REQ-UI-016: SaveLoadService smoke `summaries` count rises to 10 (audio + settings)

- Source: `docs/game/features/ui_ux_accessibility.md`, ADR-0033
- Type: technical
- Priority: must
- Status: Approved
- Rationale: `RunSnapshot` now carries a `settings_summary` field on top of the existing 9 (8 from Phase 3 progression + audio_summary added by REQ-AU-010). The save/load service smoke must update its assertion so the new field is locked down.
- Acceptance criteria:
  - `RunSnapshot.settings_summary` carries the settings dict.
  - `save_load_service_smoke.gd` updated to assert `summaries=10`.
  - The save/load round-trip preserves the settings field-for-field.
- Verification:
  - `scripts/validation/save_load_service_smoke.gd` (existing, updated assertion)
  - `scripts/validation/ui_shell_save_load_smoke.gd` (new, end-to-end)

## REQ-PM-001: PlayerProgressionState is data-driven for all 8 classes

- Source: `docs/game/features/player_progression.md`, ADR-0033
- Type: gameplay
- Priority: must
- Status: Approved
- Rationale: Class roster is the entry point for progression; every class in `data/player/classes.json` must produce a usable PlayerProgressionState with class-specific XP multipliers and starting skills.
- Acceptance criteria:
  - All 8 classes (engineer, mechanic, medic, pilot, scientist, cook, security, communications) load via `ClassDefinition.load_all()` and configure a fresh `PlayerProgressionState`.
  - The default class on a new run is engineer (existing default preserved).
  - `player_progression_state_smoke.gd` still passes with marker `PLAYER PROGRESSION PASS` (existing).
- Verification:
  - `scripts/validation/class_definitions_smoke.gd` (existing)
  - `scripts/validation/player_progression_state_smoke.gd` (existing)

## REQ-PM-002: TrainingEventBus resolves every gameplay loop into typed XP events

- Source: `docs/game/features/player_progression.md`, ADR-0033
- Type: gameplay
- Priority: must
- Status: Approved
- Rationale: Every major gameplay loop (repair, combat, crafting, discovery) must emit a deterministic training event that resolves into an XP grant via the actions catalog. The bus is pure and ordered so a replay reproduces the same XP awards.
- Acceptance criteria:
  - `TrainingEventBus.emit(event_id, target_id)` records the event and resolves `(skill_id, base_xp)` from `data/player/training_actions.json`.
  - The bus forwards resolved XP to `PlayerProgressionState.grant_xp`.
  - Unknown event_id is rejected without crashing (returns false).
  - The bus log is replayable: emitting the same event sequence reproduces the same XP.
- Verification:
  - `scripts/validation/training_event_bus_smoke.gd` (new)
  - `scripts/validation/player_progression_full_smoke.gd` (new)

## REQ-PM-003: SkillTreeState exposes prerequisites, book requirements, and unlock chain

- Source: `docs/game/features/player_progression.md`, ADR-0033
- Type: gameplay
- Priority: must
- Status: Approved
- Rationale: The skill tree is the player's mental model for what unlocks what. Books/schematics are first-class unlocks, not arbitrary XP bonuses.
- Acceptance criteria:
  - `SkillTreeState.can_unlock(skill_id)` returns true only when every prereq skill has level >= min_level AND every required book has been read.
  - The tree is loaded from `data/player/skills.json` + `data/player/skill_books.json`.
  - `SkillTreeState.unlock(skill_id)` records the unlock and is idempotent.
- Verification:
  - `scripts/validation/skill_tree_state_smoke.gd` (new)
  - `scripts/validation/skill_tree_panel_smoke.gd` (new)

## REQ-PM-004: Skill books / schematics grant XP and unlock prerequisites

- Source: `docs/game/features/player_progression.md`, ADR-0033
- Type: gameplay
- Priority: must
- Status: Approved
- Rationale: Project Zomboid's learn-by-doing uses books as primary skill catalysts. Books that are also schematics should unlock skill-tree branches (REQ-PM-003), not just grant XP.
- Acceptance criteria:
  - `PlayerProgressionState.grant_xp_from_book(book_id, books_state)` adds the book's XP to its target skill AND records the book in `books_read`.
  - The book catalog lists each book's `target_skill`, `book_xp`, and optional `unlocks_skill`.
  - Reading the same book twice is idempotent (second call is a no-op).
- Verification:
  - `scripts/validation/skill_books_smoke.gd` (new, embedded in `training_by_item_smoke.gd`)

## REQ-PM-005: Cross-training applies a 0.5x penalty to off-category XP

- Source: `docs/game/features/player_progression.md`, ADR-0033
- Type: gameplay
- Priority: must
- Status: Approved
- Rationale: PZ-style cross-training has diminishing returns. Engineering repair should still award engineering XP normally; a medic doing welding should earn half.
- Acceptance criteria:
  - `PlayerProgressionState.cross_training[skill_id]` accumulates the raw XP granted to that skill from off-category events.
  - The cross-training counter is separate from the in-category XP and is preserved through `apply_summary`.
  - `PlayerProgressionState.get_cross_training_total()` returns the sum of all cross-training XP across skills.
- Verification:
  - `scripts/validation/cross_training_smoke.gd` (new)

## REQ-PM-006: MetaProgressionState persists across runs in a separate file

- Source: `docs/game/features/player_progression.md`, ADR-0033
- Type: technical
- Priority: must
- Status: Approved
- Rationale: Per ADR-0007, RunSnapshot is current-run only. Meta state (currency, hub unlocks, class unlocks) must persist across runs in its own file. Mixing the two would let a deleted run wipe meta progress.
- Acceptance criteria:
  - `MetaProgressionState.save_to_disk()` writes `user://meta_progression.json` with schema `meta-progression-1`.
  - `load_from_disk()` round-trips `meta_currency`, `unlocked_class_ids`, `unlocked_hub_upgrade_ids`, `unlocked_codex_entry_ids`, and the run counter.
  - A missing or corrupted file defaults to zeroed state (no crash, no migration needed).
- Verification:
  - `scripts/validation/meta_progression_state_smoke.gd` (new)
  - `scripts/validation/meta_snapshot_smoke.gd` (new)

## REQ-PM-007: HubUpgradeState purchases gate on currency, prerequisites, and catalog

- Source: `docs/game/features/player_progression.md`, ADR-0033
- Type: gameplay
- Priority: must
- Status: Approved
- Rationale: Hub upgrades are the player's persistent power curve. They must be data-driven, gated, and round-trip through the meta state.
- Acceptance criteria:
  - `HubUpgradeState.purchase(upgrade_id, meta_state)` deducts cost on success and adds the id to `meta_state.unlocked_hub_upgrade_ids`.
  - Purchase is rejected when: unknown id, insufficient currency, missing prerequisite upgrade.
  - Every catalog upgrade's `effects` dict is exposed via `get_effect(upgrade_id, effect_key)`.
- Verification:
  - `scripts/validation/hub_upgrade_state_smoke.gd` (new, embedded in `player_progression_full_smoke.gd`)

## REQ-PM-008: Run-end meta payout converts run summary to meta currency

- Source: `docs/game/features/player_progression.md`, ADR-0033
- Type: gameplay
- Priority: must
- Status: Approved
- Rationale: Closing the loop requires that completed objectives + high-skill performance yield meta currency. Without it, meta progression is invisible to the player.
- Acceptance criteria:
  - `apply_meta_payout(run_summary, meta_state)` adds: `10` per completed objective, `+5` per skill >= level 5, `+15` per skill >= level 8.
  - The payout is deterministic for a fixed run summary.
  - Death triggers the same payout then wipes the run snapshot.
- Verification:
  - `scripts/validation/meta_snapshot_smoke.gd` (new, includes the payout step)

## REQ-PM-009: UnlockRegistry wraps AchievementState for codex + hub unlocks

- Source: `docs/game/features/player_progression.md`, ADR-0033
- Type: technical
- Priority: should
- Status: Approved
- Rationale: The achievement service is per-run (REQ-RL-003/004); codex and hub unlocks are cross-run. Wrapping it with `UnlockRegistry` keeps the per-run / cross-run boundary clean.
- Acceptance criteria:
  - `UnlockRegistry.unlock(id)` is idempotent and rejects unknown ids.
  - The registry exposes `is_unlocked`, `get_unlocked_ids`, `save_to_disk`, `load_from_disk`.
  - Unknown id returns false (catalog is the source of truth).
- Verification:
  - `scripts/validation/unlock_registry_smoke.gd` (new, embedded in `meta_progression_state_smoke.gd`)

## REQ-PM-010: Skill tree, class, and hub upgrade panels expose the new state

- Source: `docs/game/features/player_progression.md`, ADR-0033
- Type: UX
- Priority: should
- Status: Approved
- Rationale: The new progression surface is invisible without UI. The three panels must read from the pure models, render accessibility-friendly text, and update on model change.
- Acceptance criteria:
  - `skill_tree_panel.gd` lists every skill with category, level, XP-to-next, and a status line per prerequisite.
  - `class_panel.gd` lists every class with display name, description, starting skills.
  - `hub_upgrade_panel.gd` lists every upgrade with cost, prerequisites, and current affordability.
  - Each panel has a `get_status_lines() -> PackedStringArray` method for accessibility.
- Verification:
  - `scripts/validation/skill_tree_panel_smoke.gd` (new, marker `SKILL TREE PANEL PASS`)
  - `scripts/validation/class_panel_smoke.gd` (new, embedded in `player_progression_full_smoke.gd`)
  - `scripts/validation/hub_upgrade_panel_smoke.gd` (new, embedded in `player_progression_full_smoke.gd`)

## REQ-SV-001: VitalsState tracks health, stamina, hunger, thirst deterministically

- Source: `docs/game/features/survival_vitals.md`, `docs/game/build-plans/01-survival-vitals-e2e.md`
- Type: gameplay
- Priority: must
- Status: Approved
- Acceptance criteria:
  - `VitalsState` is a pure `RefCounted` model with configurable max values and drain/recovery rates for health, stamina, hunger, thirst.
  - `tick(delta, context)` updates all four vitals deterministically; negative delta is a no-op.
  - Hunger below 30% reduces stamina recovery by 50% (cascade).
  - Thirst below 20% emits a vision/readability warning (cascade).
  - `get_summary()` returns all current values, max values, and rates.
  - `apply_summary()` restores state and returns whether anything changed.
- Verification: `scripts/validation/vitals_state_smoke.gd` (marker `VITALS STATE PASS`).

## REQ-SV-002: SanityState tracks sanity with perception/hallucination pressure

- Source: `docs/game/features/survival_vitals.md`
- Type: gameplay
- Priority: must
- Status: Approved
- Acceptance criteria:
  - `SanityState` is a pure `RefCounted` model with max sanity, drain rate, and recovery rate.
  - Sanity drains while in the Sargasso field and recovers in safe zones.
  - Sanity below 40% applies perception/hallucination pressure (cascade).
  - `get_summary()` and `apply_summary()` follow the same contract as VitalsState.
- Verification: `scripts/validation/sanity_state_smoke.gd` (marker `SANITY STATE PASS`).

## REQ-SV-003: RadiationState tracks radiation accumulation and health damage

- Source: `docs/game/features/survival_vitals.md`
- Type: gameplay
- Priority: must
- Status: Approved
- Acceptance criteria:
  - `RadiationState` is a pure `RefCounted` model with max radiation, accumulation rate, and decay rate.
  - Radiation above 50% causes passive health drain via `VitalsState` (cascade).
  - `get_summary()` and `apply_summary()` follow the same contract.
- Verification: `scripts/validation/radiation_state_smoke.gd` (marker `RADIATION STATE PASS`).

## REQ-SV-004: BodyTemperatureState tracks temperature and thirst impact

- Source: `docs/game/features/survival_vitals.md`
- Type: gameplay
- Priority: must
- Status: Approved
- Acceptance criteria:
  - `BodyTemperatureState` is a pure `RefCounted` model with safe range [18, 32], default 22.
  - Temperature outside the safe range increases thirst drain rate (cascade).
  - `get_summary()` and `apply_summary()` follow the same contract.
- Verification: embedded in `vitals_state_smoke.gd` and `main_playable_slice_vitals_full_smoke.gd`.

## REQ-SV-005: StatusEffectsState registers and ticks active status effects

- Source: `docs/game/features/survival_vitals.md`
- Type: gameplay
- Priority: must
- Status: Approved
- Acceptance criteria:
  - `StatusEffectsState` is a pure `RefCounted` registry of active effects with duration and stacks.
  - Effects can add/remove stacks; expired effects are pruned automatically.
  - Effects can modify vital drain/recovery rates (e.g., "radiation_sickness" reduces stamina recovery).
  - `get_summary()` and `apply_summary()` preserve active effects across save/load.
- Verification: embedded in `vitals_state_save_load_smoke.gd`.

## REQ-SV-006: Difficulty preset scales vitals drain rates

- Source: `docs/game/features/survival_vitals.md`
- Type: gameplay
- Priority: should
- Status: Approved
- Acceptance criteria:
  - `DifficultyProfile` exposes a `vitals_drain_modifier` float (default 1.0).
  - `PlayableGeneratedShip` passes the modifier into `VitalsState.configure()`.
  - Standard difficulty uses 1.0; deep_dive uses 1.3; hardened uses 0.85.
- Verification: embedded in `vitals_state_smoke.gd`.

## REQ-SV-007: HUD communicates every critical vital without opening a menu

- Source: `docs/game/features/survival_vitals.md`
- Type: UX
- Priority: must
- Status: Approved
- Acceptance criteria:
  - `PlayerVitalsPanel` displays all vitals with severity colors/icons in the bottom-left HUD.
  - Critical states (health < 25%, stamina < 20%, hunger < 15%, thirst < 15%, sanity < 30%, radiation > 60%, temperature outside safe range) trigger a visible warning flash or color change.
  - Status effects are shown in a dedicated row.
- Verification: `scripts/validation/main_playable_slice_vitals_full_smoke.gd` (marker `MAIN PLAYABLE VITALS FULL PASS`).

## REQ-SV-008: Save/load preserves non-default vitals and active status effects

- Source: `docs/game/features/survival_vitals.md`, ADR-0007
- Type: technical
- Priority: must
- Status: Approved
- Acceptance criteria:
  - `RunSnapshot` carries `vitals_summary`, `sanity_summary`, `radiation_summary`, `temperature_summary`, and `status_effects_summary`.
  - Loading a snapshot restores all five models to their saved state.
  - Mid-action state (e.g., active status effect with partial duration) survives round-trips.
- Verification: `scripts/validation/vitals_state_save_load_smoke.gd` (embedded in main-scene smoke suite).

## REQ-FC-001: Food items carry spoilage, hunger, thirst, and sanity stats

- Source: `docs/game/features/food_cooking_spoilage.md`, ADR-0034
- Type: gameplay / data
- Priority: must
- Status: Validated
- Acceptance criteria:
  - Every food item in `data/items/item_definitions.json` has `spoilage_seconds`, `hunger_restore`, `thirst_restore`, `sanity_restore`, `fresh_multiplier`, `stale_multiplier`, `rotten_multiplier`, and `rotten_sickness_risk`.
  - Unknown or missing fields default to safe values (0.0 restore, 1.0 multiplier, 0.0 risk) so corrupted saves do not crash.
- Verification: `scripts/validation/food_state_smoke.gd` (marker `FOOD STATE PASS`).

## REQ-FC-002: Food freshness progresses FRESH → STALE → ROTTEN deterministically

- Source: `docs/game/features/food_cooking_spoilage.md`, ADR-0034
- Type: gameplay
- Priority: must
- Status: Validated
- Acceptance criteria:
  - `FoodState.tick(delta)` advances `accumulated_seconds` and transitions stage at 50% (STALE) and 100% (ROTTEN) of `spoilage_seconds`.
  - `get_effective_value()` applies the per-item multiplier for the current stage.
  - `is_rotten()` returns true only at ROTTEN; `get_sickness_risk()` returns the per-item config at ROTTEN and 0.0 otherwise.
- Verification: `scripts/validation/food_state_smoke.gd` (marker `FOOD STATE PASS`).

## REQ-FC-003: Spoilage aggregates all food in inventory or cargo

- Source: `docs/game/features/food_cooking_spoilage.md`, ADR-0034
- Type: gameplay
- Priority: must
- Status: Validated
- Acceptance criteria:
  - `SpoilageState` owns a Dictionary of `item_id → FoodState`.
  - `tick(delta)` advances every food and reports how many items changed stage.
  - `get_summary()` / `apply_summary()` round-trip the full aggregated state.
- Verification: `scripts/validation/spoilage_state_smoke.gd` (marker `SPOILAGE STATE PASS`).

## REQ-FC-004: Cooking consumes ingredients and power, then produces a consumable item

- Source: `docs/game/features/food_cooking_spoilage.md`, ADR-0034
- Type: gameplay
- Priority: must
- Status: Validated
- Acceptance criteria:
  - `CookingState.start_cooking(inventory_summary, skill_level, available_power)` returns `"ok": false` if ingredients are missing, insufficient, or power is below the recipe cost.
  - `tick(delta)` advances `progress_seconds` and transitions to COMPLETE when `progress_seconds >= cook_time_seconds`.
  - `collect_result()` returns the produced `item_id` and `quantity` only once; a second call returns `"ok": false`.
- Verification: `scripts/validation/cooking_state_smoke.gd` (marker `COOKING STATE PASS`), `scripts/validation/main_playable_slice_cooking_smoke.gd` (marker `MAIN PLAYABLE COOKING PASS`).

## REQ-FC-005: Hydroponics grows crops through a timed cycle with water and power costs

- Source: `docs/game/features/food_cooking_spoilage.md`, ADR-0034
- Type: gameplay
- Priority: must
- Status: Validated
- Acceptance criteria:
  - `HydroponicsState.plant(crop_config, skill_level, available_water, available_power)` rejects planting if water or power is below the crop cost.
  - `tick(delta)` advances `progress_seconds` and transitions from PLANTING → GROWING → HARVESTABLE.
  - `harvest()` returns produce only when stage is HARVESTABLE and returns `"ok": false` otherwise.
- Verification: `scripts/validation/hydroponics_state_smoke.gd` (marker `HYDROPONICS STATE PASS`).

## REQ-FC-006: Nutrient synthesizer produces food via skill-gated recipes with power tracking

- Source: `docs/game/features/food_cooking_spoilage.md`, ADR-0034
- Type: gameplay
- Priority: should
- Status: Validated
- Acceptance criteria:
  - `SynthesizerState` wraps `CookingState` with synthesizer-specific recipe filtering.
  - `start_synthesis()` checks `required_skill_level` against the supplied skill value.
  - `get_summary()` reports `total_power_consumed` and `station_type = "synthesizer"`.
- Verification: `scripts/validation/synthesizer_state_smoke.gd` (marker `SYNTHESIZER STATE PASS`).

## REQ-FC-007: Water recycler converts contaminated water to purified water over time

- Source: `docs/game/features/food_cooking_spoilage.md`, ADR-0034
- Type: gameplay
- Priority: should
- Status: Validated
- Acceptance criteria:
  - `WaterRecyclerState.start_recycling(input_quantity)` transitions from IDLE → RECYCLING.
  - `tick(delta)` advances `progress_seconds`; completion produces `purified_water` at the configured conversion rate.
  - `collect_output()` returns the purified quantity only once per cycle.
- Verification: `scripts/validation/water_recycler_state_smoke.gd` (deferred to future smoke; model tested via cooking/hydroponics dependency on purified_water).

## REQ-FC-008: Food state persists across save/load and ship travel

- Source: `docs/game/features/food_cooking_spoilage.md`, ADR-0034, ADR-0007
- Type: technical
- Priority: must
- Status: Validated
- Acceptance criteria:
  - `RunSnapshot` carries `spoilage_summary`, `cooking_summary`, `hydroponics_summary`, and `synthesizer_summary`.
  - Loading a snapshot restores all four food models to their saved state.
  - Mid-action state (e.g., cooking at 4s of 10s) survives round-trips.
- Verification: `scripts/validation/food_save_load_smoke.gd` (marker `FOOD SAVE LOAD PASS`), `scripts/validation/save_load_service_smoke.gd` (marker `SAVE LOAD SERVICE PASS summaries=18`).

## REQ-FC-009: Cooking UI panel seams exist in the playable coordinator

- Source: `docs/game/features/food_cooking_spoilage.md`, ADR-0034
- Type: UX / technical
- Priority: should
- Status: Approved
- Acceptance criteria:
  - `PlayableGeneratedShip` exposes `cooking_state`, `spoilage_state`, `hydroponics_state`, and `synthesizer_state` as public fields.
  - The coordinator's `_process(delta)` ticks spoilage, cooking, hydroponics, and synthesizer when configured.
  - `_build_run_snapshot()` captures all four summaries into the snapshot.
- Verification: `scripts/validation/main_playable_slice_cooking_smoke.gd` (marker `MAIN PLAYABLE COOKING PASS`).

## REQ-FC-010: Rotten food carries sickness risk that affects vitals

- Source: `docs/game/features/food_cooking_spoilage.md`, ADR-0034
- Type: gameplay
- Priority: should
- Status: Approved
- Acceptance criteria:
  - `FoodState.get_sickness_risk()` returns the per-item `rotten_sickness_risk` only when stage is ROTTEN.
  - `StatusEffectsState` (Task 01) can register a `food_poisoning` status effect triggered by consuming ROTTEN food.
  - The sickness effect drains health and stamina over time until it expires.
- Verification: `scripts/validation/food_state_smoke.gd` (rotten sickness risk assertion), `scripts/validation/status_effects_state_smoke.gd` (deferred to Task 01 integration).

## REQ-SS-001: Expanded ship infrastructure uses pure state models

- Source: `docs/game/features/ship_systems_sustenance_infrastructure.md`, ADR-0035
- Type: architecture
- Priority: must
- Status: Approved
- Acceptance criteria:
  - `PowerGridState`, `LifeSupportState`, `HullIntegrityState`, `FireSuppressionState`, `PropulsionState`, `ShieldState`, and `SustenanceState` exist as pure `RefCounted` models.
  - `PlayableGeneratedShip` owns the models and ticks them without moving gameplay state into scene nodes.
- Verification: code inspection + `scripts/validation/main_playable_slice_ship_systems_expanded_smoke.gd`.

## REQ-SS-002: Manual power routing produces subsystem blackouts

- Source: `docs/game/features/ship_systems_sustenance_infrastructure.md`, ADR-0035
- Type: gameplay
- Priority: must
- Status: Approved
- Acceptance criteria:
  - `PowerGridState` tracks baseline demand, manual routes, effective routes, and blackout subsystems.
  - A subsystem blackouts when routed power falls below its minimum operational ratio.
  - Propulsion availability reflects both manager repair state and routed power.
- Verification: `scripts/validation/power_grid_state_smoke.gd`, `scripts/validation/main_playable_slice_ship_systems_expanded_smoke.gd`.

## REQ-SS-003: Life-support telemetry degrades under power loss and breach pressure

- Source: `docs/game/features/ship_systems_sustenance_infrastructure.md`, ADR-0035
- Type: gameplay
- Priority: must
- Status: Approved
- Acceptance criteria:
  - `LifeSupportState` tracks oxygen, CO2, temperature, and water reserves.
  - Offline life support drains oxygen and raises CO2 faster when hull breaches are open.
  - Online life support recovers oxygen and scrubs CO2 when sufficient power is available.
- Verification: `scripts/validation/life_support_state_smoke.gd`.

## REQ-SS-004: Hull integrity is compartmentalized and repairable

- Source: `docs/game/features/ship_systems_sustenance_infrastructure.md`, ADR-0035
- Type: gameplay
- Priority: must
- Status: Approved
- Acceptance criteria:
  - `HullIntegrityState` stores per-compartment health and breach-open state.
  - Compartments can be damaged into a breach and later sealed by repair.
  - Average integrity and breach counts are queryable for downstream systems.
- Verification: `scripts/validation/main_playable_slice_ship_systems_expanded_smoke.gd`.

## REQ-SS-005: Fire suppression is explicit and power-gated

- Source: `docs/game/features/ship_systems_sustenance_infrastructure.md`, ADR-0035
- Type: gameplay
- Priority: should
- Status: Approved
- Acceptance criteria:
  - `FireSuppressionState` tracks active fires by compartment plus remaining suppressant.
  - Powered suppression ticks reduce or clear active fires.
  - Suppression summary round-trips through persistence.
- Verification: `scripts/validation/main_playable_slice_ship_systems_expanded_smoke.gd`.

## REQ-SS-006: Sustenance aggregation reflects real facility outputs

- Source: `docs/game/features/ship_systems_sustenance_infrastructure.md`, ADR-0035
- Type: gameplay
- Priority: must
- Status: Approved
- Acceptance criteria:
  - `SustenanceState` consumes hydroponics, synthesizer, and water-recycler summaries.
  - Aggregated summary reports harvest-ready crops, meal output, purified-water readiness, and facility consumption totals.
  - Aggregation does not duplicate the underlying facility models.
- Verification: `scripts/validation/sustenance_state_smoke.gd`, `scripts/validation/main_playable_slice_ship_systems_expanded_smoke.gd`.

## REQ-SS-007: Expanded ship-system summaries persist through run snapshots

- Source: `docs/game/features/ship_systems_sustenance_infrastructure.md`, ADR-0035
- Type: persistence
- Priority: must
- Status: Approved
- Acceptance criteria:
  - `PlayableGeneratedShip.get_ship_systems_summary()` includes nested summaries for power grid, life support, hull integrity, fire suppression, propulsion, shields, and sustenance.
  - `_build_run_snapshot()` stores those nested summaries inside `ship_systems_summary`.
  - `_apply_run_snapshot()` restores the nested summaries without requiring a schema-breaking top-level snapshot field.
- Verification: `scripts/validation/main_playable_slice_ship_systems_expanded_smoke.gd`.

## REQ-CN-001: EffectDispatcher resolves shared consumable effects deterministically

- Source: `docs/game/features/consumables_medicine_stimulants.md`, `docs/game/build-plans/05-consumables-medicine-stimulants-e2e.md`, ADR-0036
- Type: gameplay
- Priority: must
- Status: Validated
- Acceptance criteria:
  - `EffectDispatcher` routes effect ids into vitals, sanity, radiation, status-effect, and ammo state mutations without scene-tree access.
  - Unknown effect ids fail explicitly instead of mutating partial state.
  - The same dispatcher path is reused by medicine, stimulants, ammo packs, and utility items.
- Verification: `scripts/validation/effect_dispatcher_smoke.gd`.

## REQ-CN-002: ConsumableState owns use actions and hotbar slot summaries

- Source: `docs/game/features/consumables_medicine_stimulants.md`, ADR-0036
- Type: gameplay
- Priority: must
- Status: Validated
- Acceptance criteria:
  - `ConsumableState` recognizes supported item categories and rejects non-usable items safely.
  - Three hotbar slots can be assigned, serialized, restored, and invoked through the same use pipeline.
  - Successful item use increments total-use telemetry and records the last used item id.
- Verification: `scripts/validation/consumable_state_smoke.gd`, `scripts/validation/main_playable_consumables_smoke.gd`.

## REQ-CN-003: Medicine items heal or cure status effects through shared effects

- Source: `docs/game/features/consumables_medicine_stimulants.md`, ADR-0036
- Type: gameplay
- Priority: must
- Status: Validated
- Acceptance criteria:
  - Medicine definitions under `data/items/medicine_definitions.json` can restore health/stamina and cure status ids through `EffectDispatcher`.
  - Inventory quantity decreases exactly once per successful use.
  - `MedicineState` preserves the last used medicine id and cured-status summary for UI/save-load.
- Verification: `scripts/validation/consumable_state_smoke.gd`.

## REQ-CN-004: Stimulants apply timed buffs and withdrawal risk

- Source: `docs/game/features/consumables_medicine_stimulants.md`, ADR-0036
- Type: gameplay
- Priority: must
- Status: Validated
- Acceptance criteria:
  - Stimulant use applies status effects for a duration scaled by tolerance.
  - Expired stimulants can trigger withdrawal effects when dependence exceeds threshold.
  - `StimulantState` and `AddictionState` preserve active timers and dependence/tolerance summaries through save/load.
- Verification: `scripts/validation/stimulant_state_smoke.gd`, `scripts/validation/main_playable_consumables_smoke.gd`.

## REQ-CN-005: Ammo packs feed reserve ammo through the same consumable pipeline

- Source: `docs/game/features/consumables_medicine_stimulants.md`, ADR-0036
- Type: gameplay
- Priority: must
- Status: Validated
- Acceptance criteria:
  - Ammo items use effect definitions instead of bespoke reserve math in the coordinator.
  - Successful use increments the correct reserve bucket and consumes exactly one inventory stack unit.
  - `AmmoState` summary round-trips through `RunSnapshot`.
- Verification: `scripts/validation/consumable_state_smoke.gd`, `scripts/validation/main_playable_consumables_smoke.gd`.

## REQ-CN-006: Utility items set durable utility flags and notes

- Source: `docs/game/features/consumables_medicine_stimulants.md`, ADR-0036
- Type: gameplay
- Priority: must
- Status: Validated
- Acceptance criteria:
  - Utility items run through `EffectDispatcher` and `UtilityItemResolver`.
  - Utility flags record the last used item, note text, and count summary.
  - Utility summaries survive save/load and can be surfaced to UI later without recomputing from inventory.
- Verification: `scripts/validation/consumable_state_smoke.gd`, `scripts/validation/main_playable_consumables_smoke.gd`.

## REQ-CN-007: PlayableGeneratedShip wires inventory-panel use into the consumable pipeline

- Source: `docs/game/features/consumables_medicine_stimulants.md`, ADR-0036
- Type: gameplay
- Priority: must
- Status: Validated
- Acceptance criteria:
  - `InventoryPanel.use_requested` is connected in the playable scene and routes into `ConsumableState.use_item(...)`.
  - Successful item use refreshes encumbrance, oxygen, vitals, and hotbar UI state without reopening the scene.
  - Consumed/missing items are removed or re-assigned from hotbar slots safely.
- Verification: `scripts/validation/main_playable_consumables_smoke.gd`, `scripts/validation/inventory_panel_smoke.gd`.

## REQ-CN-008: The playable hotbar exposes at least three consumable slots

- Source: `docs/game/features/consumables_medicine_stimulants.md`, ADR-0036
- Type: gameplay
- Priority: must
- Status: Validated
- Acceptance criteria:
  - The HUD hotbar shows three consumable slot labels with quantities.
  - Keys `1`, `2`, and `3` trigger the corresponding hotbar slot when gameplay is active and no modal panel is open.
  - Save/load restores the hotbar summary after a reload.
- Verification: `scripts/validation/main_playable_consumables_smoke.gd`.

## REQ-CN-009: Consumable package summaries persist additively in RunSnapshot

- Source: `docs/game/features/consumables_medicine_stimulants.md`, ADR-0036
- Type: gameplay
- Priority: must
- Status: Validated
- Acceptance criteria:
  - `RunSnapshot` carries additive summaries for consumable, medicine, stimulant, addiction, ammo, and utility state.
  - Save/load round-trips these summaries without breaking older snapshot fields.
  - The save/load service smoke locks the new summary-count baseline.
- Verification: `scripts/validation/save_load_service_smoke.gd`, `scripts/validation/main_playable_consumables_smoke.gd`.

## REQ-CN-010: Task 05 validation markers are part of the regression bundle

- Source: `docs/game/build-plans/05-consumables-medicine-stimulants-e2e.md`, `docs/game/06_validation_plan.md`
- Type: validation
- Priority: must
- Status: Validated
- Acceptance criteria:
  - The validation plan includes focused commands for effect dispatcher, consumable state, medicine state, stimulant state, addiction state, consumable save/load, and main playable consumables smokes.
  - Marker strings are stable: `EFFECT DISPATCHER PASS`, `CONSUMABLE STATE PASS`, `MEDICINE STATE PASS`, `STIMULANT STATE PASS`, `ADDICTION STATE PASS`, `CONSUMABLE SAVE LOAD PASS`, and `MAIN PLAYABLE CONSUMABLES PASS`.
  - The package ships with both pure-model and main-scene coverage.
- Verification: `docs/game/06_validation_plan.md`, `scripts/validation/effect_dispatcher_smoke.gd`, `scripts/validation/consumable_state_smoke.gd`, `scripts/validation/stimulant_state_smoke.gd`, `scripts/validation/main_playable_consumables_smoke.gd`.

## REQ-D-001: Damage resolution is a pure-model pipeline

- Source: `docs/game/features/combat_threat_ai.md`, ADR-0037
- Type: gameplay / architecture
- Priority: must
- Status: Validated
- Acceptance criteria:
  - `DamagePipeline` resolves incoming damage by damage type, armor absorption, and threat/vitals routing without scene-tree access.
  - The pipeline can apply an optional status effect as part of the same resolution event.
- Verification: `scripts/validation/damage_pipeline_smoke.gd` (marker `DAMAGE PIPELINE PASS`).

## REQ-D-002: Armor uses flat reduction, resistance, and durability loss

- Source: `docs/game/features/combat_threat_ai.md`, ADR-0037
- Type: gameplay
- Priority: must
- Status: Validated
- Acceptance criteria:
  - `ArmorResolver` applies flat reduction before resistance/weakness math.
  - Resolved hits reduce armor durability using the configured wear factor.
- Verification: `scripts/validation/armor_resolver_smoke.gd` (marker `ARMOR RESOLVER PASS`).

## REQ-D-003: Status effects stack, tick, and expire deterministically

- Source: `docs/game/features/combat_threat_ai.md`, ADR-0037
- Type: gameplay
- Priority: must
- Status: Validated
- Acceptance criteria:
  - `StatusEffectsState` can add, remove, stack, summarize, and expire effects without scene-tree access.
  - Effect timers survive tick advancement and cleanup consistently.
- Verification: `scripts/validation/status_effects_smoke.gd` (marker `STATUS EFFECTS PASS`).

## REQ-D-004: Detection fuses sound, sight, light, and memory

- Source: `docs/game/features/combat_threat_ai.md`, ADR-0037
- Type: gameplay
- Priority: must
- Status: Validated
- Acceptance criteria:
  - `DetectionState` accepts sound, vision, light, and stealth inputs.
  - Detection can persist via short-term memory after direct stimuli stop.
- Verification: `scripts/validation/detection_state_smoke.gd` (marker `DETECTION STATE PASS`).

## REQ-D-005: Threat AI advances through shared combat states

- Source: `docs/game/features/combat_threat_ai.md`, ADR-0037
- Type: gameplay
- Priority: must
- Status: Validated
- Acceptance criteria:
  - `ThreatAIState` supports investigate/hunt/attack/dead style transitions from one common contract.
  - Threat awareness drops back down only through the model's own tick logic.
- Verification: `scripts/validation/threat_ai_state_smoke.gd` (marker `THREAT AI STATE PASS`).

## REQ-D-006: The main playable slice spawns at least five threat archetypes

- Source: `docs/game/features/combat_threat_ai.md`, ADR-0037
- Type: gameplay
- Priority: must
- Status: Validated
- Acceptance criteria:
  - `ThreatManager` loads at least five archetypes from `data/combat/threat_archetypes.json`.
  - The main playable combat smoke sees all five archetypes in one live encounter summary.
- Verification: `scripts/validation/main_playable_slice_combat_encounter_smoke.gd` (marker `MAIN PLAYABLE COMBAT ENCOUNTER PASS archetypes=5`).

## REQ-D-007: Player melee and ranged/tool weapons share one runtime contract

- Source: `docs/game/features/combat_threat_ai.md`, ADR-0037
- Type: gameplay
- Priority: must
- Status: Validated
- Acceptance criteria:
  - `crowbar`, `flare_pistol`, `shock_probe`, and `welding_lance` resolve through the same attack pipeline.
  - Equipped item ids map to the correct combat weapon ids before attack resolution.
- Verification: code inspection + `scripts/validation/main_playable_slice_combat_encounter_smoke.gd`.

## REQ-D-008: Ammo/resource-backed weapons spend inventory resources on attack

- Source: `docs/game/features/combat_threat_ai.md`, ADR-0037
- Type: gameplay
- Priority: must
- Status: Validated
- Acceptance criteria:
  - `flare_pistol`, `shock_probe`, and `welding_lance` each consume one linked ammo/resource item per successful attack.
  - Failed attacks do not silently consume ammo.
- Verification: `scripts/validation/main_playable_slice_combat_encounter_smoke.gd` (marker includes `ammo_spent=1`).

## REQ-D-009: Weapon use raises threat awareness and detection pressure

- Source: `docs/game/features/combat_threat_ai.md`, ADR-0037
- Type: gameplay
- Priority: must
- Status: Validated
- Acceptance criteria:
  - Attacks raise `ThreatManager.awareness_indicator` above the idle baseline.
  - At least one threat becomes detected / alerted after a live attack.
- Verification: `scripts/validation/main_playable_slice_combat_encounter_smoke.gd`.

## REQ-D-010: Threat summaries persist world position and live memory state

- Source: `docs/game/features/combat_threat_ai.md`, ADR-0037
- Type: technical
- Priority: must
- Status: Validated
- Acceptance criteria:
  - A saved threat summary carries `world_position`, `memory_remaining`, health, and phase/state fields.
  - Reloading restores the attacked target without rebuilding it from scratch.
- Verification: `scripts/validation/main_playable_slice_combat_encounter_smoke.gd` (marker includes `memory_restored=true`).

## REQ-D-011: Current-ship combat summaries persist the last attack result

- Source: `docs/game/features/combat_threat_ai.md`, ADR-0037
- Type: technical
- Priority: must
- Status: Validated
- Acceptance criteria:
  - Save/load preserves `last_attack_result.weapon_id` and `last_attack_result.target_id`.
  - Reloading a live encounter does not clear the ship combat summary just because a scene rebuilt.
- Verification: `scripts/validation/main_playable_slice_combat_encounter_smoke.gd`.

## REQ-D-012: Encounter state remains additive within the save/load model

- Source: `docs/game/features/combat_threat_ai.md`, ADR-0037, ADR-0007
- Type: technical
- Priority: must
- Status: Validated
- Acceptance criteria:
  - Combat/threat summaries are additive snapshot fields rather than bespoke side files.
  - Reloading a save restores live encounter pressure without resetting the run.
- Verification: `scripts/validation/main_playable_slice_combat_encounter_smoke.gd`, `scripts/validation/save_load_service_smoke.gd`.

## REQ-D-013: Combat tuning is data-driven

- Source: `docs/game/features/combat_threat_ai.md`, ADR-0037
- Type: architecture
- Priority: must
- Status: Validated
- Acceptance criteria:
  - Threat archetypes, weapon definitions, ammo links, and status-effect definitions live under `data/combat/`.
  - Runtime systems read those catalogs without hardcoding per-archetype logic in scene nodes.
- Verification: code/data inspection + Task 06 smoke suite.

## REQ-D-014: Main playable HUD exposes combat feedback text

- Source: `docs/game/features/combat_threat_ai.md`, ADR-0037
- Type: UX
- Priority: should
- Status: Validated
- Acceptance criteria:
  - The hotbar/combat HUD updates to reflect the active weapon and its ammo mode.
  - Combat summary text is synchronized from live runtime state instead of static placeholder text.
- Verification: `scripts/validation/main_playable_slice_combat_encounter_smoke.gd`.

## REQ-D-015: Threat placeholders are sufficient for headless/main-scene validation

- Source: `docs/game/features/combat_threat_ai.md`, ADR-0037
- Type: technical
- Priority: should
- Status: Validated
- Acceptance criteria:
  - `ThreatManager` can spawn placeholder nodes for threats without requiring final art assets.
  - Placeholder behavior still reflects threat position and aggressive state changes.
- Verification: `scripts/validation/main_playable_slice_combat_encounter_smoke.gd`.

## REQ-D-016: Combat status effects integrate with damage events

- Source: `docs/game/features/combat_threat_ai.md`, ADR-0037
- Type: gameplay
- Priority: must
- Status: Validated
- Acceptance criteria:
  - Damage events can attach status ids such as bleed/burn/stun.
  - The damage pipeline can apply the status within the same resolution step.
- Verification: `scripts/validation/damage_pipeline_smoke.gd`, `scripts/validation/status_effects_smoke.gd`.

## REQ-D-017: Stealth remains a player-side modifier, not a separate AI tree

- Source: `docs/game/features/combat_threat_ai.md`, ADR-0037
- Type: gameplay / architecture
- Priority: should
- Status: Validated
- Acceptance criteria:
  - Player stealth influences detection inputs rather than branching the threat AI into a separate implementation.
  - Threat response still routes through the same shared detection + threat-state pipeline.
- Verification: `scripts/validation/detection_state_smoke.gd`, `scripts/validation/threat_ai_state_smoke.gd`.

## REQ-D-018: Task 06 keeps death/respawn and meta consequences out of scope

- Source: `docs/game/features/combat_threat_ai.md`, `docs/game/build-plans/06-combat-threat-ai-e2e.md`
- Type: scope
- Priority: must
- Status: Validated
- Acceptance criteria:
  - Task 06 changes are limited to combat/threat/runtime persistence and do not introduce hub/meta or death-screen workflow decisions.
  - Save/load covers live encounter state only.
- Verification: scope review + `docs/game/build-plans/evidence/combat-threat-ai-contract-review.md`.

## REQ-INT-001: Cross-system integration matrix is source-backed

- Source: `docs/game/features/cross_system_integration_review.md`, ADR-0039
- Type: process / technical
- Priority: must
- Status: Validated
- Acceptance criteria:
  - `data/integration/cross_system_integration_matrix.json` records the kickoff and Task 01-14 package rows.
  - Each implementation row cites task id, loop stages, requirement ids, code files, docs files, smoke files, and smoke markers.
  - The matrix covers prepare, derelict, survive, loot, craft, return, and upgrade loop stages.
- Verification: `scripts/validation/cross_system_dependency_smoke.gd` (marker `CROSS SYSTEM DEPENDENCY PASS`).

## REQ-INT-002: Dependency validation checks code, docs, requirements, and markers

- Source: `docs/game/features/cross_system_integration_review.md`, ADR-0039
- Type: validation
- Priority: must
- Status: Validated
- Acceptance criteria:
  - `DependencyValidator` verifies every cited file exists in the checkout.
  - Every cited requirement id appears as a heading in this document.
  - Every cited smoke marker is registered in `docs/game/06_validation_plan.md`.
- Verification: `scripts/validation/cross_system_dependency_smoke.gd`.

## REQ-INT-003: Integration audit models remain pure

- Source: `docs/game/features/cross_system_integration_review.md`, ADR-0039
- Type: architecture
- Priority: must
- Status: Validated
- Acceptance criteria:
  - `IntegrationMatrix`, `DependencyValidator`, `BalanceLedger`, `AutomatedPlaytestRubric`, and `ProductAuditReport` are `RefCounted` pure models.
  - The models do not reach into the scene tree or mutate gameplay runtime state.
  - Validation scripts instantiate the models directly.
- Verification: code inspection + Task 14 focused smokes.

## REQ-INT-004: Balance ledger defines deterministic safe ranges

- Source: `docs/game/balance/cross_system_balance_ledger.md`, ADR-0039
- Type: gameplay / balance
- Priority: must
- Status: Validated
- Acceptance criteria:
  - `data/integration/balance_ledger.json` defines metric thresholds for the seven-stage survival loop.
  - The survival-loop smoke fails when a required metric is missing or outside the accepted range.
  - The ledger clearly states that these are sanity thresholds, not final tuning claims.
- Verification: `scripts/validation/e2e_survival_loop_smoke.gd` (marker `E2E SURVIVAL LOOP PASS`).

## REQ-INT-005: Automated e2e rubric covers the full player loop

- Source: `docs/game/features/cross_system_integration_review.md`, ADR-0039
- Type: validation / product
- Priority: must
- Status: Validated
- Acceptance criteria:
  - The rubric requires prepare -> derelict -> survive -> loot -> craft -> return -> upgrade coverage.
  - Each stage must provide at least one visible-consequence step.
  - Stuck-state counts above the configured threshold fail the rubric.
- Verification: `scripts/validation/e2e_survival_loop_smoke.gd`.

## REQ-INT-006: Combat, loot, and crafting compose in one deterministic scenario

- Source: `docs/game/features/cross_system_integration_review.md`, ADR-0039
- Type: gameplay / integration
- Priority: must
- Status: Validated
- Acceptance criteria:
  - A live `DamagePipeline` hit reduces a `ThreatAIState` target.
  - `LootDistribution` rolls a deterministic derelict reward.
  - `CraftingState`, `MaterialState`, and `InventoryState` convert salvage into a `power_cell` without separate fixture-only code.
- Verification: `scripts/validation/e2e_combat_loot_craft_smoke.gd` (marker `E2E COMBAT LOOT CRAFT PASS`).

## REQ-INT-007: Ship repair, return, meta payout, and upgrade compose

- Source: `docs/game/features/cross_system_integration_review.md`, ADR-0039
- Type: gameplay / integration
- Priority: must
- Status: Validated
- Acceptance criteria:
  - Power routing gates propulsion before repair/allocation and restores it afterward.
  - `MetaProgressionState` converts a completed run summary into enough currency for the first upgrade tier.
  - `HubUpgradeState` can purchase and unlock `hub_storage_basic` from that payout.
- Verification: `scripts/validation/e2e_ship_meta_loop_smoke.gd` (marker `E2E SHIP META LOOP PASS`).

## REQ-INT-008: Product audit findings require evidence and fix-card links

- Source: `docs/game/features/cross_system_integration_review.md`, ADR-0039
- Type: process / product
- Priority: must
- Status: Validated
- Acceptance criteria:
  - Every product audit finding has at least one evidence path or source reference.
  - Every contradiction or follow-up finding has a `fix_key` linked to `data/integration/known_issue_fix_manifest.json`.
  - Product audit validation fails if untracked blocking findings remain.
- Verification: `scripts/validation/product_audit_smoke.gd` (marker `PRODUCT AUDIT PASS`).

## REQ-INT-009: Contradictions become explicit Kanban work

- Source: `docs/game/features/cross_system_integration_review.md`, ADR-0039
- Type: process
- Priority: must
- Status: Validated
- Acceptance criteria:
  - Source-map/roadmap currency contradictions link to existing Task 15 (`t_c7ac4d08`).
  - The stronger live main-scene/controller e2e probe is tracked as `t_4e47145d` and completed with `LIVE MAIN PREPARE UPGRADE PROBE PASS stages=7`.
  - The issue manifest records assignee and reason for every tracked item.
- Verification: `data/integration/known_issue_fix_manifest.json`, `scripts/validation/product_audit_smoke.gd`.

## REQ-INT-010: Task 14 focused smokes are registered in the regression bundle

- Source: `docs/game/build-plans/14-cross-system-integration-review-e2e.md`, `docs/game/06_validation_plan.md`
- Type: validation
- Priority: must
- Status: Validated
- Acceptance criteria:
  - The validation plan includes the five Task 14 focused smoke commands.
  - Required markers are stable: `CROSS SYSTEM DEPENDENCY PASS`, `E2E SURVIVAL LOOP PASS`, `E2E COMBAT LOOT CRAFT PASS`, `E2E SHIP META LOOP PASS`, and `PRODUCT AUDIT PASS`.
  - No unexpected Godot `ERROR:` or `WARNING:` lines are introduced by Task 14 smokes.
- Verification: `docs/game/06_validation_plan.md`, Task 14 focused smoke bundle.
## REQ-DOC-001: Systems map has source-backed package evidence

- Source: `docs/game/features/systems_map_task_graph_currency.md`, ADR-0040
- Type: process / documentation
- Priority: must
- Status: Validated
- Acceptance criteria:
  - The systems map lists Task 00-15 with real Kanban ids.
  - Every completed package row cites docs, code/data, and validation evidence.
  - The systems map validator prints `SYSTEMS MAP CURRENCY PASS`.
- Verification: `scripts/validation/systems_map_currency_smoke.py`.

## REQ-DOC-002: Stale in-scope missing-system language is rejected

- Source: `docs/game/features/systems_map_task_graph_currency.md`, ADR-0040
- Type: process / documentation
- Priority: must
- Status: Validated
- Acceptance criteria:
  - The final systems map no longer says in-scope Task 01-14 systems such as survival vitals, crafting, combat, UI shell, audio infrastructure, multi-slot saves, or procgen Template C are missing.
  - Future missing-work language is scoped to explicit follow-up/release-ops surfaces.
- Verification: `scripts/validation/systems_map_currency_smoke.py`.

## REQ-DOC-003: Requirements trace includes Task 15 rows and all matrix-cited rows

- Source: `docs/game/features/systems_map_task_graph_currency.md`, ADR-0040
- Type: process / requirements
- Priority: must
- Status: Validated
- Acceptance criteria:
  - `REQ-DOC-001..008` exist and are `Validated`.
  - Every requirement id cited by `data/integration/cross_system_integration_matrix.json` appears as a heading in this document.
  - The requirement trace smoke prints `REQUIREMENT TRACE PASS`.
- Verification: `scripts/validation/requirement_trace_smoke.py`.

## REQ-DOC-004: ADR index references shipped artifacts

- Source: `docs/game/features/systems_map_task_graph_currency.md`, ADR-0040
- Type: process / architecture
- Priority: must
- Status: Validated
- Acceptance criteria:
  - `docs/game/adr/README.md` lists the current package ADRs and their shipped artifact references.
  - The systems map includes an ADR Currency Index with the same artifact-reference paths.
  - ADR-0040 is present and accepted for the Task 15 validator architecture.
- Verification: `scripts/validation/requirement_trace_smoke.py`.

## REQ-DOC-005: Kanban manifest uses real live board ids

- Source: `docs/game/features/systems_map_task_graph_currency.md`, ADR-0040
- Type: process / kanban
- Priority: must
- Status: Validated
- Acceptance criteria:
  - `.omh/kanban/synaptic-sea-e2e-systems-task-graph.json` names board `synaptic-sea-e2e-systems`.
  - Every manifest task id exists in the live board database.
  - Every declared manifest parent edge exists in `task_links`.
- Verification: `scripts/validation/kanban_manifest_smoke.py`.

## REQ-DOC-006: Kanban manifest captures current board counts

- Source: `docs/game/features/systems_map_task_graph_currency.md`, ADR-0040
- Type: process / kanban
- Priority: must
- Status: Validated
- Acceptance criteria:
  - The manifest `board_currency.task_count` equals the live board task count.
  - The manifest `board_currency.link_count` equals the live board dependency-link count.
  - The manifest `board_currency.status_counts` captures the pre-completion live grouped task statuses, and `allowed_status_counts` also permits the expected post-completion `{done: 18}` state.
- Verification: `scripts/validation/kanban_manifest_smoke.py`.

## REQ-DOC-007: Validation plan registers the Task 15 focused smokes

- Source: `docs/game/features/systems_map_task_graph_currency.md`, ADR-0040
- Type: validation
- Priority: must
- Status: Validated
- Acceptance criteria:
  - `docs/game/06_validation_plan.md` contains `SYSTEMS MAP CURRENCY PASS`, `REQUIREMENT TRACE PASS`, and `KANBAN MANIFEST PASS`.
  - The strict regression bundle invokes the three host-side Task 15 smoke wrappers.
- Verification: `scripts/validation/requirement_trace_smoke.py`.

## REQ-DOC-008: Final board currency preserves explicit caveats instead of hidden blockers

- Source: `docs/game/features/systems_map_task_graph_currency.md`, ADR-0040
- Type: process / release readiness
- Priority: must
- Status: Validated
- Acceptance criteria:
  - `t_4e47145d` is listed as a completed live main-scene/controller-path follow-up rather than treated as an untracked contradiction.
  - External store/platform/signing evidence is listed as release-ops follow-up rather than claimed by Task 15.
  - Task 15 completion metadata cites the three focused PASS markers.
- Verification: `scripts/validation/systems_map_currency_smoke.py`, `scripts/validation/kanban_manifest_smoke.py`.
