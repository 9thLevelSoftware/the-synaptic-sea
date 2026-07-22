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
  - Documentation review by `synaptic_sea_review` checks that no Gate 1 card introduces hub/meta state, derelict selection, or persistent meta-currency.
  - Reviewer confirms `features/hub_progression.md` is not authored during Gate 1.

## REQ-009: Gate 2 hub/meta re-decision trigger

- Source: ADR-0002, ADR-0003, `08_milestone_gates.md`
- Type: process
- Priority: must
- Status: Resolved by ADR-0003 (Option A: deferred through Gate 2)
- Rationale: Hub/meta is the largest undecided design surface in the vision. Gate 2 entry review is the formal checkpoint where the deferral is re-affirmed or the scope is escalated into an early Gate 2 implementation card.
- Resolution: ADR-0003 re-affirms deferral through Gate 2 and anchors the next hub/meta decision to Gate 3 entry planning. Gate 2 focuses on derelict exploration depth: inventory/tools, expanded hazards, objective/procedural variation, and current-run persistence.
- Acceptance criteria:
  - Before Gate 2 begins, a hub/meta re-decision card exists on board `synaptic-sea-stage-gate`.
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
- Status: Approved (Gate 2 form **superseded by ADR-0041**; see note below)
- Rationale: Gate 2 needs a second hazard pattern to prove the ship can host multiple environmental pressures without every hazard being an oxygen-drain variant.
- Acceptance criteria (Gate 2 — historical):
  - At least one additional hazard type exists in the generated ship scene (the timed fire zone in a side corridor for Gate 2).
  - ~~The new hazard toggles real passability via its own pure state model (`FireState`).~~ **Superseded by ADR-0041** (see note).
  - The new hazard does not alter oxygen, route-gate, or extraction semantics.
  - Both a direct model smoke and a main-scene smoke pass.
- **Superseded note (M7-B / ADR-0041, 2026-06-27):** Fire was reworked from the cyclic
  phase-timer zone into the authoritative persistent compartment hazard owned by
  `FireSuppressionState`; `FireState` is deleted. **Fire no longer blocks passability**
  (burning fire zones are deliberately passable so the player can walk in to fight the
  fire), so the "timed fire zone in a non-critical side corridor / toggles real
  passability" placement constraint above is obsolete — it applied only to the old
  impassable timed zone. Fire now ignites as a symptom of unrepaired system damage and
  has vitals + ship-system teeth (REQ-010's "second hazard pattern" intent is satisfied,
  more strongly, by the new model). The Gate 2 criteria are kept for history.
- Verification (current — REQ-010 / ADR-0041):
  - `scripts/validation/fire_suppression_state_smoke.gd` (pure model)
  - `scripts/validation/main_playable_slice_fire_smoke.gd` (passable zones + teeth)
  - `scripts/validation/main_playable_fire_loop_smoke.gd` (full end-to-end loop)
  - Supporting: `extinguisher_state_smoke.gd`, `ship_systems_damage_smoke.gd`,
    `fire_suppression_point_smoke.gd`, `extinguisher_recharge_port_smoke.gd`

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

---

# E2E Systems Wave requirements (Tasks 01-15)

These entries trace the requirements referenced by the cross-system
integration matrix (`data/integration/cross_system_integration_matrix.json`)
and the Task 15 documentation-currency deliverable. They are validated by
`scripts/validation/doc_currency_validators.py requirement-trace`.

## REQ-DOC-001: Systems map cites every completed package task id and evidence

- Source: `features/systems_map_task_graph_currency.md`
- Type: documentation / process
- Priority: must
- Status: Validated
- Rationale: The complete systems map records each validated package's task id, code/data/smoke files, and smoke markers so 'what is built' is traceable to source.
- Acceptance criteria:
  - The currency claim above holds when the validators run with `ROOT` set.
- Verification:
  - `doc_currency_validators.py requirement-trace` (`REQUIREMENT TRACE PASS`)

## REQ-DOC-002: ADR currency index lists every package architecture decision

- Source: `features/systems_map_task_graph_currency.md`
- Type: documentation / process
- Priority: must
- Status: Validated
- Rationale: `docs/game/adr/README.md` and the systems map ADR index reference every package ADR, so each system's architecture decision is discoverable.
- Acceptance criteria:
  - The currency claim above holds when the validators run with `ROOT` set.
- Verification:
  - `doc_currency_validators.py requirement-trace` (`REQUIREMENT TRACE PASS`)

## REQ-DOC-003: Requirements doc traces every matrix-cited requirement

- Source: `features/systems_map_task_graph_currency.md`
- Type: documentation / process
- Priority: must
- Status: Validated
- Rationale: Every requirement id referenced by the integration matrix has a heading in this requirements document.
- Acceptance criteria:
  - The currency claim above holds when the validators run with `ROOT` set.
- Verification:
  - `doc_currency_validators.py requirement-trace` (`REQUIREMENT TRACE PASS`)

## REQ-DOC-004: Kanban manifest matches the live board

- Source: `features/systems_map_task_graph_currency.md`
- Type: documentation / process
- Priority: must
- Status: Validated
- Rationale: The task-graph manifest's task_count, link_count, and status_counts reconcile against the live Hermes board (when the board DB is available).
- Acceptance criteria:
  - The currency claim above holds when the validators run with `ROOT` set.
- Verification:
  - `doc_currency_validators.py requirement-trace` (`REQUIREMENT TRACE PASS`)

## REQ-DOC-005: Validation plan registers the doc-currency markers

- Source: `features/systems_map_task_graph_currency.md`
- Type: documentation / process
- Priority: must
- Status: Validated
- Rationale: `docs/game/06_validation_plan.md` registers the SYSTEMS MAP CURRENCY PASS, REQUIREMENT TRACE PASS, and KANBAN MANIFEST PASS markers.
- Acceptance criteria:
  - The currency claim above holds when the validators run with `ROOT` set.
- Verification:
  - `doc_currency_validators.py requirement-trace` (`REQUIREMENT TRACE PASS`)

## REQ-DOC-006: No stale in-scope phrases remain in the systems map

- Source: `features/systems_map_task_graph_currency.md`
- Type: documentation / process
- Priority: must
- Status: Validated
- Rationale: Superseded 'MISSING' / 'SPEC'D' in-scope phrases are removed from the systems map once their package is validated.
- Acceptance criteria:
  - The currency claim above holds when the validators run with `ROOT` set.
- Verification:
  - `doc_currency_validators.py requirement-trace` (`REQUIREMENT TRACE PASS`)

## REQ-DOC-007: Integration matrix is the source of truth for system traceability

- Source: `features/systems_map_task_graph_currency.md`
- Type: documentation / process
- Priority: must
- Status: Validated
- Rationale: The cross-system integration matrix links each package to its requirements, code, and smoke evidence and is the input to the currency validators.
- Acceptance criteria:
  - The currency claim above holds when the validators run with `ROOT` set.
- Verification:
  - `doc_currency_validators.py requirement-trace` (`REQUIREMENT TRACE PASS`)

## REQ-DOC-008: Doc-currency validators are host-side and reproducible

- Source: `features/systems_map_task_graph_currency.md`
- Type: documentation / process
- Priority: must
- Status: Validated
- Rationale: The currency validators run without booting Godot, auto-detect the repo root (overridable via ROOT), and exit non-zero on failure.
- Acceptance criteria:
  - The currency claim above holds when the validators run with `ROOT` set.
- Verification:
  - `doc_currency_validators.py requirement-trace` (`REQUIREMENT TRACE PASS`)

## REQ-DOC-009: Current architecture visualizations are source-backed and individually renderable

- Source: `features/architecture_visualizations.md`
- Type: documentation / process
- Priority: must
- Status: Validated
- Rationale: Developers need a small current architecture reading path that remains traceable to source and does not confuse historical intent with live runtime behavior.
- Acceptance criteria:
  - Five individual Mermaid diagrams cover system context, containers/data stores, gameplay interaction, threat-AI state, and curated runtime dependencies.
  - Every diagram includes a text equivalent, current evidence paths and symbols, inference/omission notes, current gaps, and export instructions.
  - Five committed SVGs carry the current Mermaid-source SHA-256 and exact renderer version.
  - Planned or deferred behavior is absent from diagram semantics.
- Verification:
  - `python3 tools/validate_architecture_diagrams.py --check` (`ARCHITECTURE DIAGRAMS PASS`)
  - Complete regression bundle (`SYNAPTIC_SEA REGRESSION PASS commands=208 clean_output=true`)

## REQ-SV-001: Survival vitals (REQ-SV-001)

- Source: `docs/game/features/survival_vitals.md`
- Type: gameplay / technical
- Priority: must
- Status: Validated
- Rationale: Part of the validated "Survival vitals" E2E package (task t_34d0483b); see the cross-system integration matrix.
- Acceptance criteria:
  - The "Survival vitals" package is implemented and smoke-validated.
- Verification:
  - `vitals_state_smoke.gd`
  - `VITALS STATE PASS`

## REQ-SV-002: Sanity hallucinations (REQ-SV-002)

- Source: `docs/game/features/survival_vitals.md`, ADR-0042
- Type: gameplay / technical
- Priority: must
- Status: Validated
- Rationale: Sanity below 40% was previously cosmetic (HUD text only). ADR-0042 replaces the
  cosmetic output with a tiered hallucination system: tier-1 ambient cues, tier-2 phantom threats
  and false HUD readouts, tier-3 direct health drain and stamina recovery penalty plus wasted-ammo
  counterplay. This closes the M1 simulation loop gap identified in the system-completion audit.
- Acceptance criteria:
  - Sanity below 40 activates tier-1 ambient hallucination cues (no HUD or phantom events).
  - Sanity below 25 activates tier-2 phantom threats and false HUD contact blips.
  - Sanity below 15 activates tier-3 direct vitals teeth: health drain per second and reduced
    stamina recovery multiplier fed into the vitals tick via `sanity_health_drain` and
    `sanity_stamina_recovery_mult` context keys.
  - Phantoms are rendered by `HallucinationManager`, never registered in `ThreatManager`; real
    combat math is untouched.
  - Swinging at a phantom in melee range dissipates it and spends the attack action (wasted ammo
    if an ammo weapon is equipped); the attack result carries `phantom_dissipated: true`.
  - Entering a safe zone or returning sanity to tier 0 clears all active hallucination events.
  - The hallucination schedule is deterministic from seed and sanity history (no `randi()`/`randf()`).
  - Hallucination events are not persisted; they re-derive from the already-saved sanity value on load.
  - A pure-model smoke and a main-scene live-loop smoke both pass.
- Verification:
  - `scripts/validation/hallucination_director_smoke.gd`
  - `HALLUCINATION DIRECTOR PASS tiers=true gated=true deterministic=true ttl=true teeth=true fx=true round_trip=true`
  - `scripts/validation/main_playable_hallucination_smoke.gd`
  - `MAIN PLAYABLE HALLUCINATION PASS manifest=true phantom_no_damage=true attack_dissipates=true teeth=true clears=true hud=true fx=true reachable=true`

## REQ-SV-007: Survival vitals (REQ-SV-007)

- Source: `docs/game/features/survival_vitals.md`
- Type: gameplay / technical
- Priority: must
- Status: Validated
- Rationale: Part of the validated "Survival vitals" E2E package (task t_34d0483b); see the cross-system integration matrix.
- Acceptance criteria:
  - The "Survival vitals" package is implemented and smoke-validated.
- Verification:
  - `main_playable_slice_vitals_full_smoke.gd`
  - `MAIN PLAYABLE VITALS FULL PASS`

## REQ-SV-008: Survival vitals (REQ-SV-008)

- Source: `docs/game/features/survival_vitals.md`
- Type: gameplay / technical
- Priority: must
- Status: Validated
- Rationale: Part of the validated "Survival vitals" E2E package (task t_34d0483b); see the cross-system integration matrix.
- Acceptance criteria:
  - The "Survival vitals" package is implemented and smoke-validated.
- Verification:
  - `vitals_state_save_load_smoke.gd`
  - `VITALS SAVE LOAD PASS`

## REQ-FC-001: Food, cooking, spoilage, and sustenance inputs (REQ-FC-001)

- Source: `docs/game/features/food_cooking_spoilage.md`
- Type: gameplay / technical
- Priority: must
- Status: Validated
- Rationale: Part of the validated "Food, cooking, spoilage, and sustenance inputs" E2E package (task t_d569eba2); see the cross-system integration matrix.
- Acceptance criteria:
  - The "Food, cooking, spoilage, and sustenance inputs" package is implemented and smoke-validated.
- Verification:
  - `food_state_smoke.gd`
  - `FOOD STATE PASS`

## REQ-FC-004: Food, cooking, spoilage, and sustenance inputs (REQ-FC-004)

- Source: `docs/game/features/food_cooking_spoilage.md`
- Type: gameplay / technical
- Priority: must
- Status: Validated
- Rationale: Part of the validated "Food, cooking, spoilage, and sustenance inputs" E2E package (task t_d569eba2); see the cross-system integration matrix.
- Acceptance criteria:
  - The "Food, cooking, spoilage, and sustenance inputs" package is implemented and smoke-validated.
- Verification:
  - `cooking_state_smoke.gd`
  - `COOKING STATE PASS`

## REQ-FC-008: Food, cooking, spoilage, and sustenance inputs (REQ-FC-008)

- Source: `docs/game/features/food_cooking_spoilage.md`
- Type: gameplay / technical
- Priority: must
- Status: Validated
- Rationale: Part of the validated "Food, cooking, spoilage, and sustenance inputs" E2E package (task t_d569eba2); see the cross-system integration matrix.
- Acceptance criteria:
  - The "Food, cooking, spoilage, and sustenance inputs" package is implemented and smoke-validated.
- Verification:
  - `main_playable_slice_cooking_smoke.gd`
  - `MAIN PLAYABLE COOKING PASS`

## REQ-CS-001: Crafting, materials, recipes, and stations (REQ-CS-001)

- Source: `docs/game/features/crafting_materials_recipes.md`
- Type: gameplay / technical
- Priority: must
- Status: Validated
- Rationale: Part of the validated "Crafting, materials, recipes, and stations" E2E package (task t_be88f847); see the cross-system integration matrix.
- Acceptance criteria:
  - The "Crafting, materials, recipes, and stations" package is implemented and smoke-validated.
- Verification:
  - `material_state_smoke.gd`
  - `MATERIAL STATE PASS`

## REQ-CS-005: Crafting, materials, recipes, and stations (REQ-CS-005)

- Source: `docs/game/features/crafting_materials_recipes.md`
- Type: gameplay / technical
- Priority: must
- Status: Validated
- Rationale: Part of the validated "Crafting, materials, recipes, and stations" E2E package (task t_be88f847); see the cross-system integration matrix.
- Acceptance criteria:
  - The "Crafting, materials, recipes, and stations" package is implemented and smoke-validated.
- Verification:
  - `crafting_state_smoke.gd`
  - `CRAFTING STATE PASS`

## REQ-CS-014: Crafting, materials, recipes, and stations (REQ-CS-014)

- Source: `docs/game/features/crafting_materials_recipes.md`
- Type: gameplay / technical
- Priority: must
- Status: Validated
- Rationale: Part of the validated "Crafting, materials, recipes, and stations" E2E package (task t_be88f847); see the cross-system integration matrix.
- Acceptance criteria:
  - The "Crafting, materials, recipes, and stations" package is implemented and smoke-validated.
- Verification:
  - `main_playable_slice_crafting_smoke.gd`
  - `MAIN PLAYABLE CRAFTING PASS`

## REQ-CS-018: Hydroponics crop picker (REQ-CS-018)

- Source: `docs/game/features/crafting_recipe_picker.md` (production extension)
- Type: gameplay / technical
- Priority: must
- Status: Validated
- Rationale: Hydroponics still auto-planted the first affordable crop; players need to choose cultivar when multiple crops are affordable.
- Acceptance criteria:
  - Hydroponics IDLE interact opens a crop list (not auto-plant).
  - Player can select and plant a non-first ready crop when skill/water/power allow.
  - Harvest / in-progress interact paths unchanged.
  - Food production smoke still PASSes via first-ready plant validation seam.
- Verification:
  - `hydroponics_crop_list_smoke.gd` — `HYDROPONICS CROP LIST PASS`
  - `main_playable_slice_hydro_crop_picker_smoke.gd` — `MAIN PLAYABLE HYDRO CROP PICKER PASS`
  - `main_playable_food_production_smoke.gd` — existing loop still green

## REQ-CS-017: Salvage station target picker (REQ-CS-017)

- Source: `docs/game/features/crafting_recipe_picker.md` (salvage extension)
- Type: gameplay / technical
- Priority: must
- Status: Validated
- Rationale: After REQ-CS-016, salvage still auto-selected the first deconstructable/junk item; players need to choose what to break down.
- Acceptance criteria:
  - Salvage station interact opens a target list (deconstruction recipes + catalog junk in inventory).
  - Player can select and execute a non-first ready target; only that item is consumed.
  - Headless smokes prove pure listing and main-scene chosen salvage.
  - Station craft reachability smoke still PASSes (first-ready validation seam).
- Verification:
  - `salvage_list_smoke.gd` — `SALVAGE LIST PASS`
  - `main_playable_slice_salvage_picker_smoke.gd` — `MAIN PLAYABLE SALVAGE PICKER PASS`
  - `main_playable_slice_station_craft_smoke.gd` — existing reachability still green

## REQ-CS-016: Crafting station recipe picker (REQ-CS-016)

- Source: `docs/game/features/crafting_recipe_picker.md`
- Type: gameplay / technical
- Priority: must
- Status: Validated
- Rationale: ADR-0038 residual MVP left stations auto-selecting the first craftable recipe; players need explicit choice when multiple recipes are ready.
- Acceptance criteria:
  - Non-salvage station interact opens a recipe list for that station_kind; craft does not start until confirm.
  - Player can select and craft a non-first ready recipe; ingredients consume for the chosen recipe only.
  - Blocked recipes (ingredients/skill/output) do not start a craft on confirm.
  - Salvage station remains auto-select (out of scope).
  - KEY_C opens the same picker for portable field_crafting recipes.
  - Headless smokes prove pure listing, panel selection, and main-scene chosen-recipe craft (station + field).
- Verification:
  - `crafting_recipe_list_smoke.gd` — `CRAFTING RECIPE LIST PASS`
  - `recipe_picker_panel_smoke.gd` — `RECIPE PICKER PANEL PASS`
  - `main_playable_slice_recipe_picker_smoke.gd` — `MAIN PLAYABLE RECIPE PICKER PASS`
  - `main_playable_slice_station_craft_smoke.gd` — existing reachability still green

## REQ-LE-001: Loot ecosystem (REQ-LE-001)

- Source: `docs/game/features/loot_ecosystem.md`
- Type: gameplay / technical
- Priority: must
- Status: Validated
- Rationale: Part of the validated "Loot ecosystem" E2E package (task t_af66b721); see the cross-system integration matrix.
- Acceptance criteria:
  - The "Loot ecosystem" package is implemented and smoke-validated.
- Verification:
  - `loot_distribution_smoke.gd`
  - `LOOT DISTRIBUTION PASS`

## REQ-LE-002: Loot ecosystem (REQ-LE-002)

- Source: `docs/game/features/loot_ecosystem.md`
- Type: gameplay / technical
- Priority: must
- Status: Validated
- Rationale: Part of the validated "Loot ecosystem" E2E package (task t_af66b721); see the cross-system integration matrix.
- Acceptance criteria:
  - The "Loot ecosystem" package is implemented and smoke-validated.
- Verification:
  - `unique_item_state_smoke.gd`
  - `UNIQUE ITEM STATE PASS`

## REQ-LE-005: Loot ecosystem (REQ-LE-005)

- Source: `docs/game/features/loot_ecosystem.md`
- Type: gameplay / technical
- Priority: must
- Status: Validated
- Rationale: Part of the validated "Loot ecosystem" E2E package (task t_af66b721); see the cross-system integration matrix.
- Acceptance criteria:
  - The "Loot ecosystem" package is implemented and smoke-validated.
- Verification:
  - `main_playable_slice_loot_ecosystem_smoke.gd`
  - `MAIN PLAYABLE LOOT ECOSYSTEM PASS`

## REQ-CN-001: Consumables, medicine, stimulants, ammo, utility (REQ-CN-001)

- Source: `docs/game/features/consumables_medicine_stimulants.md`
- Type: gameplay / technical
- Priority: must
- Status: Validated
- Rationale: Part of the validated "Consumables, medicine, stimulants, ammo, utility" E2E package (task t_67389b76); see the cross-system integration matrix.
- Acceptance criteria:
  - The "Consumables, medicine, stimulants, ammo, utility" package is implemented and smoke-validated.
- Verification:
  - `consumable_state_smoke.gd`
  - `CONSUMABLE STATE PASS`

## REQ-CN-004: Consumables, medicine, stimulants, ammo, utility (REQ-CN-004)

- Source: `docs/game/features/consumables_medicine_stimulants.md`
- Type: gameplay / technical
- Priority: must
- Status: Validated
- Rationale: Part of the validated "Consumables, medicine, stimulants, ammo, utility" E2E package (task t_67389b76); see the cross-system integration matrix.
- Acceptance criteria:
  - The "Consumables, medicine, stimulants, ammo, utility" package is implemented and smoke-validated.
- Verification:
  - `medicine_state_smoke.gd`
  - `MEDICINE STATE PASS`

## REQ-CN-009: Consumables, medicine, stimulants, ammo, utility (REQ-CN-009)

- Source: `docs/game/features/consumables_medicine_stimulants.md`
- Type: gameplay / technical
- Priority: must
- Status: Validated
- Rationale: Part of the validated "Consumables, medicine, stimulants, ammo, utility" E2E package (task t_67389b76); see the cross-system integration matrix.
- Acceptance criteria:
  - The "Consumables, medicine, stimulants, ammo, utility" package is implemented and smoke-validated.
- Verification:
  - `main_playable_consumables_smoke.gd`
  - `MAIN PLAYABLE CONSUMABLES PASS`

## REQ-D-001: Combat, threat AI, damage, armor, status (REQ-D-001)

- Source: `docs/game/features/combat_threat_ai.md`
- Type: gameplay / technical
- Priority: must
- Status: Validated
- Rationale: Part of the validated "Combat, threat AI, damage, armor, status" E2E package (task t_cbe56420); see the cross-system integration matrix.
- Acceptance criteria:
  - The "Combat, threat AI, damage, armor, status" package is implemented and smoke-validated.
- Verification:
  - `damage_pipeline_smoke.gd`
  - `DAMAGE PIPELINE PASS`

## REQ-D-006: Combat, threat AI, damage, armor, status (REQ-D-006)

- Source: `docs/game/features/combat_threat_ai.md`
- Type: gameplay / technical
- Priority: must
- Status: Validated
- Rationale: Part of the validated "Combat, threat AI, damage, armor, status" E2E package (task t_cbe56420); see the cross-system integration matrix.
- Acceptance criteria:
  - The "Combat, threat AI, damage, armor, status" package is implemented and smoke-validated.
- Verification:
  - `threat_ai_state_smoke.gd`
  - `THREAT AI STATE PASS`

## REQ-D-010: Combat, threat AI, damage, armor, status (REQ-D-010)

- Source: `docs/game/features/combat_threat_ai.md`
- Type: gameplay / technical
- Priority: must
- Status: Validated
- Rationale: Part of the validated "Combat, threat AI, damage, armor, status" E2E package (task t_cbe56420); see the cross-system integration matrix.
- Acceptance criteria:
  - The "Combat, threat AI, damage, armor, status" package is implemented and smoke-validated.
- Verification:
  - `main_playable_slice_combat_encounter_smoke.gd`
  - `MAIN PLAYABLE COMBAT ENCOUNTER PASS`

## REQ-D-019: Threat pathfollowing on layout nav graph

- Source: `docs/game/features/combat_threat_ai.md`, ADR-0049
- Type: gameplay / technical
- Priority: must
- Status: Validated
- Rationale: Replace lerp-through-walls threat motion with pure A* pathfollowing on floor cells.
- Acceptance criteria:
  - Threats in HUNT/ATTACK advance along `ShipNavGraph` waypoints without leaving the graph corridor.
  - INVESTIGATE targets last-known position; FLEE targets farthest reachable node.
  - Pure unit smokes + main-scene smoke pass headless.
- Verification:
  - `ship_nav_graph_smoke.gd` / `SHIP NAV GRAPH PASS`
  - `threat_pathfinder_smoke.gd` / `THREAT PATHFINDER PASS`
  - `threat_path_follow_smoke.gd` / `THREAT PATH FOLLOW PASS`
  - `main_playable_threat_pathfinding_smoke.gd` / `MAIN PLAYABLE THREAT PATHFINDING PASS`

## REQ-D-020: Dynamic path blockers (fire, sealed hatches)

- Source: `docs/game/features/combat_threat_ai.md`, ADR-0049
- Type: gameplay / technical
- Priority: should
- Status: Validated
- Rationale: Path costs must react to live fire intensity and sealed-hatch bulkheads.
- Acceptance criteria:
  - Coordinator pushes fire rooms + unbypassed hatch bulkheads into `ThreatManager.update_nav_dynamic_costs`.
  - Blocked/costed edges affect A* routes.
- Verification:
  - Covered by pathfinder unit tests + live `_refresh_threat_nav_costs` wiring.

## REQ-SS-001: Expanded ship systems and sustenance infrastructure (REQ-SS-001)

- Source: `docs/game/features/ship_systems_sustenance_infrastructure.md`
- Type: gameplay / technical
- Priority: must
- Status: Validated
- Rationale: Part of the validated "Expanded ship systems and sustenance infrastructure" E2E package (task t_290ec958); see the cross-system integration matrix.
- Acceptance criteria:
  - The "Expanded ship systems and sustenance infrastructure" package is implemented and smoke-validated.
- Verification:
  - `power_grid_state_smoke.gd`
  - `POWER GRID STATE PASS`

## REQ-SS-002: Expanded ship systems and sustenance infrastructure (REQ-SS-002)

- Source: `docs/game/features/ship_systems_sustenance_infrastructure.md`
- Type: gameplay / technical
- Priority: must
- Status: Validated
- Rationale: Part of the validated "Expanded ship systems and sustenance infrastructure" E2E package (task t_290ec958); see the cross-system integration matrix.
- Acceptance criteria:
  - The "Expanded ship systems and sustenance infrastructure" package is implemented and smoke-validated.
- Verification:
  - `sustenance_state_smoke.gd`
  - `SUSTENANCE STATE PASS`

## REQ-SS-006: Expanded ship systems and sustenance infrastructure (REQ-SS-006)

- Source: `docs/game/features/ship_systems_sustenance_infrastructure.md`
- Type: gameplay / technical
- Priority: must
- Status: Validated
- Rationale: Part of the validated "Expanded ship systems and sustenance infrastructure" E2E package (task t_290ec958); see the cross-system integration matrix.
- Acceptance criteria:
  - The "Expanded ship systems and sustenance infrastructure" package is implemented and smoke-validated.
- Verification:
  - `main_playable_slice_ship_systems_expanded_smoke.gd`
  - `MAIN PLAYABLE SHIP SYSTEMS EXPANDED PASS`

## REQ-PM-001: Player progression and meta progression (REQ-PM-001)

- Source: `docs/game/features/player_progression.md`
- Type: gameplay / technical
- Priority: must
- Status: Validated
- Rationale: Part of the validated "Player progression and meta progression" E2E package (task t_02146c59); see the cross-system integration matrix.
- Acceptance criteria:
  - The "Player progression and meta progression" package is implemented and smoke-validated.
- Verification:
  - `player_progression_state_smoke.gd`
  - `PLAYER PROGRESSION PASS`

## REQ-PM-006: Player progression and meta progression (REQ-PM-006)

- Source: `docs/game/features/player_progression.md`
- Type: gameplay / technical
- Priority: must
- Status: Validated
- Rationale: Part of the validated "Player progression and meta progression" E2E package (task t_02146c59); see the cross-system integration matrix.
- Acceptance criteria:
  - The "Player progression and meta progression" package is implemented and smoke-validated.
- Verification:
  - `meta_progression_state_smoke.gd`
  - `META PROGRESSION STATE PASS`

## REQ-PM-007: Player progression and meta progression (REQ-PM-007)

- Source: `docs/game/features/player_progression.md`
- Type: gameplay / technical
- Priority: must
- Status: Validated
- Rationale: Part of the validated "Player progression and meta progression" E2E package (task t_02146c59); see the cross-system integration matrix.
- Acceptance criteria:
  - The "Player progression and meta progression" package is implemented and smoke-validated.
- Verification:
  - `player_progression_full_smoke.gd`
  - `PLAYER PROGRESSION FULL PASS`

## REQ-UI-001: UI, HUD, tutorial, controller, accessibility (REQ-UI-001)

- Source: `docs/game/features/ui_ux_accessibility.md`
- Type: gameplay / technical
- Priority: must
- Status: Validated
- Rationale: Part of the validated "UI, HUD, tutorial, controller, accessibility" E2E package (task t_7a6849cb); see the cross-system integration matrix.
- Acceptance criteria:
  - The "UI, HUD, tutorial, controller, accessibility" package is implemented and smoke-validated.
- Verification:
  - `menu_state_smoke.gd`
  - `MENU STATE PASS`

## REQ-UI-003: UI, HUD, tutorial, controller, accessibility (REQ-UI-003)

- Source: `docs/game/features/ui_ux_accessibility.md`
- Type: gameplay / technical
- Priority: must
- Status: Validated
- Rationale: Part of the validated "UI, HUD, tutorial, controller, accessibility" E2E package (task t_7a6849cb); see the cross-system integration matrix.
- Acceptance criteria:
  - The "UI, HUD, tutorial, controller, accessibility" package is implemented and smoke-validated.
- Verification:
  - `settings_state_smoke.gd`
  - `SETTINGS STATE PASS`

## REQ-UI-006: UI, HUD, tutorial, controller, accessibility (REQ-UI-006)

- Source: `docs/game/features/ui_ux_accessibility.md`
- Type: gameplay / technical
- Priority: must
- Status: Validated
- Rationale: Part of the validated "UI, HUD, tutorial, controller, accessibility" E2E package (task t_7a6849cb); see the cross-system integration matrix.
- Acceptance criteria:
  - The "UI, HUD, tutorial, controller, accessibility" package is implemented and smoke-validated.
- Verification:
  - `main_playable_slice_ui_shell_smoke.gd`
  - `MAIN PLAYABLE UI SHELL PASS`

## REQ-AU-001: Audio, music, spatial audio, voice, meta events (REQ-AU-001)

- Source: `docs/game/features/audio-music-spatial.md`
- Type: gameplay / technical
- Priority: must
- Status: Validated
- Rationale: Part of the validated "Audio, music, spatial audio, voice, meta events" E2E package (task t_9e328a9f); see the cross-system integration matrix.
- Acceptance criteria:
  - The "Audio, music, spatial audio, voice, meta events" package is implemented and smoke-validated.
- Verification:
  - `audio_bus_config_smoke.gd`
  - `AUDIO BUS CONFIG PASS`

## REQ-AU-004: Audio, music, spatial audio, voice, meta events (REQ-AU-004)

- Source: `docs/game/features/audio-music-spatial.md`
- Type: gameplay / technical
- Priority: must
- Status: Validated
- Rationale: Part of the validated "Audio, music, spatial audio, voice, meta events" E2E package (task t_9e328a9f); see the cross-system integration matrix.
- Acceptance criteria:
  - The "Audio, music, spatial audio, voice, meta events" package is implemented and smoke-validated.
- Verification:
  - `dynamic_music_state_smoke.gd`
  - `DYNAMIC MUSIC STATE PASS`

## REQ-AU-010: Audio, music, spatial audio, voice, meta events (REQ-AU-010)

- Source: `docs/game/features/audio-music-spatial.md`
- Type: gameplay / technical
- Priority: must
- Status: Validated
- Rationale: Part of the validated "Audio, music, spatial audio, voice, meta events" E2E package (task t_9e328a9f); see the cross-system integration matrix.
- Acceptance criteria:
  - The "Audio, music, spatial audio, voice, meta events" package is implemented and smoke-validated.
- Verification:
  - `main_playable_slice_audio_smoke.gd`
  - `MAIN PLAYABLE AUDIO PASS`

## REQ-SL-001: Multi-slot save, autosave, migration, corruption, cloud manifest (REQ-SL-001)

- Source: `docs/game/features/save_load.md`
- Type: gameplay / technical
- Priority: must
- Status: Validated
- Rationale: Part of the validated "Multi-slot save, autosave, migration, corruption, cloud manifest" E2E package (task t_2d267b26); see the cross-system integration matrix.
- Acceptance criteria:
  - The "Multi-slot save, autosave, migration, corruption, cloud manifest" package is implemented and smoke-validated.
- Verification:
  - `save_slot_state_smoke.gd`
  - `SAVE SLOT STATE PASS`

## REQ-SL-007: Multi-slot save, autosave, migration, corruption, cloud manifest (REQ-SL-007)

- Source: `docs/game/features/save_load.md`
- Type: gameplay / technical
- Priority: must
- Status: Validated
- Rationale: Part of the validated "Multi-slot save, autosave, migration, corruption, cloud manifest" E2E package (task t_2d267b26); see the cross-system integration matrix.
- Acceptance criteria:
  - The "Multi-slot save, autosave, migration, corruption, cloud manifest" package is implemented and smoke-validated.
- Verification:
  - `save_migration_service_smoke.gd`
  - `SAVE MIGRATION SERVICE PASS`

## REQ-SL-012: Multi-slot save, autosave, migration, corruption, cloud manifest (REQ-SL-012)

- Source: `docs/game/features/save_load.md`
- Type: gameplay / technical
- Priority: must
- Status: Validated
- Rationale: Part of the validated "Multi-slot save, autosave, migration, corruption, cloud manifest" E2E package (task t_2d267b26); see the cross-system integration matrix.
- Acceptance criteria:
  - The "Multi-slot save, autosave, migration, corruption, cloud manifest" package is implemented and smoke-validated.
- Verification:
  - `main_playable_slice_multislot_save_smoke.gd`
  - `MAIN PLAYABLE MULTISLOT SAVE PASS`

## REQ-PG-001: Procedural generation expansion (REQ-PG-001)

- Source: `docs/game/features/procedural_generation_expansion.md`
- Type: gameplay / technical
- Priority: must
- Status: Validated
- Rationale: Part of the validated "Procedural generation expansion" E2E package (task t_4faf58cf); see the cross-system integration matrix.
- Acceptance criteria:
  - The "Procedural generation expansion" package is implemented and smoke-validated.
- Verification:
  - `room_variant_selector_smoke.gd`
  - `ROOM VARIANT SELECTOR PASS`

## REQ-PG-007: Procedural generation expansion (REQ-PG-007)

- Source: `docs/game/features/procedural_generation_expansion.md`
- Type: gameplay / technical
- Priority: must
- Status: Validated
- Rationale: Part of the validated "Procedural generation expansion" E2E package (task t_4faf58cf); see the cross-system integration matrix.
- Acceptance criteria:
  - The "Procedural generation expansion" package is implemented and smoke-validated.
- Verification:
  - `encounter_injector_smoke.gd`
  - `ENCOUNTER INJECTOR PASS`

## REQ-PG-012: Procedural generation expansion (REQ-PG-012)

- Source: `docs/game/features/procedural_generation_expansion.md`
- Type: gameplay / technical
- Priority: must
- Status: Validated
- Rationale: Part of the validated "Procedural generation expansion" E2E package (task t_4faf58cf); see the cross-system integration matrix.
- Acceptance criteria:
  - The "Procedural generation expansion" package is implemented and smoke-validated.
- Verification:
  - `seed_determinism_smoke.gd`
  - `SEED DETERMINISM PASS`

## REQ-RL-001: Distribution, store, achievements, demo, localization, post-launch ops (REQ-RL-001)

- Source: `docs/game/features/release_distribution.md`
- Type: gameplay / technical
- Priority: must
- Status: Validated
- Rationale: Part of the validated "Distribution, store, achievements, demo, localization, post-launch ops" E2E package (task t_3b217838); see the cross-system integration matrix.
- Acceptance criteria:
  - The "Distribution, store, achievements, demo, localization, post-launch ops" package is implemented and smoke-validated.
- Verification:
  - `export_presets_smoke.gd`
  - `EXPORT PRESETS PASS`

## REQ-RL-003: Distribution, store, achievements, demo, localization, post-launch ops (REQ-RL-003)

- Source: `docs/game/features/release_distribution.md`
- Type: gameplay / technical
- Priority: must
- Status: Validated
- Rationale: Part of the validated "Distribution, store, achievements, demo, localization, post-launch ops" E2E package (task t_3b217838); see the cross-system integration matrix.
- Acceptance criteria:
  - The "Distribution, store, achievements, demo, localization, post-launch ops" package is implemented and smoke-validated.
- Verification:
  - `achievement_state_smoke.gd`
  - `ACHIEVEMENT STATE PASS`

## REQ-RL-008: Distribution, store, achievements, demo, localization, post-launch ops (REQ-RL-008)

- Source: `docs/game/features/release_distribution.md`
- Type: gameplay / technical
- Priority: must
- Status: Validated
- Rationale: Part of the validated "Distribution, store, achievements, demo, localization, post-launch ops" E2E package (task t_3b217838); see the cross-system integration matrix.
- Acceptance criteria:
  - The "Distribution, store, achievements, demo, localization, post-launch ops" package is implemented and smoke-validated.
- Verification:
  - `release_readiness_ledger_smoke.gd`
  - `RELEASE READINESS LEDGER PASS`

## REQ-INT-001: Cross-system integration, balance, product audit, and gap closure (REQ-INT-001)

- Source: `docs/game/features/cross_system_integration_review.md`
- Type: gameplay / technical
- Priority: must
- Status: Validated
- Rationale: Part of the validated "Cross-system integration, balance, product audit, and gap closure" E2E package (task t_12bf9f4a); see the cross-system integration matrix.
- Acceptance criteria:
  - The "Cross-system integration, balance, product audit, and gap closure" package is implemented and smoke-validated.
- Verification:
  - `cross_system_dependency_smoke.gd`
  - `CROSS SYSTEM DEPENDENCY PASS`

## REQ-INT-002: Cross-system integration, balance, product audit, and gap closure (REQ-INT-002)

- Source: `docs/game/features/cross_system_integration_review.md`
- Type: gameplay / technical
- Priority: must
- Status: Validated
- Rationale: Part of the validated "Cross-system integration, balance, product audit, and gap closure" E2E package (task t_12bf9f4a); see the cross-system integration matrix.
- Acceptance criteria:
  - The "Cross-system integration, balance, product audit, and gap closure" package is implemented and smoke-validated.
- Verification:
  - `e2e_survival_loop_smoke.gd`
  - `E2E SURVIVAL LOOP PASS`

## REQ-INT-003: Cross-system integration, balance, product audit, and gap closure (REQ-INT-003)

- Source: `docs/game/features/cross_system_integration_review.md`
- Type: gameplay / technical
- Priority: must
- Status: Validated
- Rationale: Part of the validated "Cross-system integration, balance, product audit, and gap closure" E2E package (task t_12bf9f4a); see the cross-system integration matrix.
- Acceptance criteria:
  - The "Cross-system integration, balance, product audit, and gap closure" package is implemented and smoke-validated.
- Verification:
  - `e2e_combat_loot_craft_smoke.gd`
  - `E2E COMBAT LOOT CRAFT PASS`

## REQ-INT-004: Cross-system integration, balance, product audit, and gap closure (REQ-INT-004)

- Source: `docs/game/features/cross_system_integration_review.md`
- Type: gameplay / technical
- Priority: must
- Status: Validated
- Rationale: Part of the validated "Cross-system integration, balance, product audit, and gap closure" E2E package (task t_12bf9f4a); see the cross-system integration matrix.
- Acceptance criteria:
  - The "Cross-system integration, balance, product audit, and gap closure" package is implemented and smoke-validated.
- Verification:
  - `e2e_ship_meta_loop_smoke.gd`
  - `E2E SHIP META LOOP PASS`

## REQ-INT-005: Cross-system integration, balance, product audit, and gap closure (REQ-INT-005)

- Source: `docs/game/features/cross_system_integration_review.md`
- Type: gameplay / technical
- Priority: must
- Status: Validated
- Rationale: Part of the validated "Cross-system integration, balance, product audit, and gap closure" E2E package (task t_12bf9f4a); see the cross-system integration matrix.
- Acceptance criteria:
  - The "Cross-system integration, balance, product audit, and gap closure" package is implemented and smoke-validated.
- Verification:
  - `product_audit_smoke.gd`
  - `PRODUCT AUDIT PASS`

## REQ-INT-006: Cross-system integration, balance, product audit, and gap closure (REQ-INT-006)

- Source: `docs/game/features/cross_system_integration_review.md`
- Type: gameplay / technical
- Priority: must
- Status: Validated
- Rationale: Part of the validated "Cross-system integration, balance, product audit, and gap closure" E2E package (task t_12bf9f4a); see the cross-system integration matrix.
- Acceptance criteria:
  - The "Cross-system integration, balance, product audit, and gap closure" package is implemented and smoke-validated.
- Verification:
  - `cross_system_dependency_smoke.gd`
  - `CROSS SYSTEM DEPENDENCY PASS`

## REQ-INT-007: Cross-system integration, balance, product audit, and gap closure (REQ-INT-007)

- Source: `docs/game/features/cross_system_integration_review.md`
- Type: gameplay / technical
- Priority: must
- Status: Validated
- Rationale: Part of the validated "Cross-system integration, balance, product audit, and gap closure" E2E package (task t_12bf9f4a); see the cross-system integration matrix.
- Acceptance criteria:
  - The "Cross-system integration, balance, product audit, and gap closure" package is implemented and smoke-validated.
- Verification:
  - `cross_system_dependency_smoke.gd`
  - `CROSS SYSTEM DEPENDENCY PASS`

## REQ-INT-008: Cross-system integration, balance, product audit, and gap closure (REQ-INT-008)

- Source: `docs/game/features/cross_system_integration_review.md`
- Type: gameplay / technical
- Priority: must
- Status: Validated
- Rationale: Part of the validated "Cross-system integration, balance, product audit, and gap closure" E2E package (task t_12bf9f4a); see the cross-system integration matrix.
- Acceptance criteria:
  - The "Cross-system integration, balance, product audit, and gap closure" package is implemented and smoke-validated.
- Verification:
  - `cross_system_dependency_smoke.gd`
  - `CROSS SYSTEM DEPENDENCY PASS`

## REQ-INT-009: Cross-system integration, balance, product audit, and gap closure (REQ-INT-009)

- Source: `docs/game/features/cross_system_integration_review.md`
- Type: gameplay / technical
- Priority: must
- Status: Validated
- Rationale: Part of the validated "Cross-system integration, balance, product audit, and gap closure" E2E package (task t_12bf9f4a); see the cross-system integration matrix.
- Acceptance criteria:
  - The "Cross-system integration, balance, product audit, and gap closure" package is implemented and smoke-validated.
- Verification:
  - `cross_system_dependency_smoke.gd`
  - `CROSS SYSTEM DEPENDENCY PASS`

## REQ-INT-010: Cross-system integration, balance, product audit, and gap closure (REQ-INT-010)

- Source: `docs/game/features/cross_system_integration_review.md`
- Type: gameplay / technical
- Priority: must
- Status: Validated
- Rationale: Part of the validated "Cross-system integration, balance, product audit, and gap closure" E2E package (task t_12bf9f4a); see the cross-system integration matrix.
- Acceptance criteria:
  - The "Cross-system integration, balance, product audit, and gap closure" package is implemented and smoke-validated.
- Verification:
  - `cross_system_dependency_smoke.gd`
  - `CROSS SYSTEM DEPENDENCY PASS`

## Pre-polish foundations (2026-07-22 wave)

## REQ-MI-001: Module integrity FSM and sparse persistence

- Source: `features/module_integrity.md`, ADR-0051
- Type: gameplay / technical
- Priority: must
- Status: Implemented
- Acceptance criteria:
  - Structural modules own integrity state `intact|damaged|breached|destroyed`.
  - Only touched modules serialize as sparse deltas from pristine.
  - Deterministic under fixed seed + event order.
- Verification:
  - `module_integrity_state_smoke.gd` (when implemented)
  - `MODULE INTEGRITY PASS` marker

## REQ-WA-001: WorkAction catalog and pure progress model

- Source: `features/work_actions.md`, ADR-0051
- Type: gameplay / technical
- Priority: must
- Status: Approved
- Acceptance criteria:
  - Verbs cut/unbolt/weld/patch/pry/splice are data-defined.
  - Progress, interrupt, tool/skill/material gates are pure-tested.
- Verification:
  - `work_action_state_smoke.gd` (when implemented)

## REQ-CMP-001: Component slot population is deterministic

- Source: `features/component_slots.md`
- Type: gameplay / technical
- Priority: must
- Status: Approved
- Acceptance criteria:
  - Wall/center slots fill from a seeded placement stage without overlap.
  - Ship-system subcomponents link to placed components where authored.
- Verification:
  - `component_slot_population_smoke.gd` (when implemented)

## REQ-SMOD-001: Ship modification is mechanical fleet payoff

- Source: `features/ship_modification.md`
- Type: gameplay / technical
- Priority: must
- Status: Approved
- Acceptance criteria:
  - Salvaged components install into ship slots under power budget constraints.
  - Hub growth is physical (components/modules), not a separate hub scene.
- Verification:
  - `ship_modification_smoke.gd` (when implemented)

## REQ-ARCH-001: SimKeys contract for tick context

- Source: pre-polish plan PKG-A2
- Type: technical
- Priority: must
- Status: Implemented
- Acceptance criteria:
  - Vitals hot-path context keys are defined once in `SimKeys`.
  - Pure vitals consumers use `SimKeys` constants; wire strings remain stable.
- Verification:
  - `sim_keys_smoke.gd`
  - `SIM KEYS PASS`

## REQ-ARCH-002: TuningCatalog shell

- Source: pre-polish plan PKG-A4
- Type: technical
- Priority: must
- Status: Implemented
- Acceptance criteria:
  - `TuningCatalog` loads `data/balance/*.json` with const fallbacks for missing keys.
  - Shell fixture proves load/override without mass-migrating coordinator literals.
- Verification:
  - `tuning_catalog_smoke.gd`
  - `TUNING CATALOG PASS`

## REQ-MI-002: Module integrity has physical scene consequences

- Source: \eatures/module_integrity.md\, ADR-0051
- Type: gameplay / technical
- Priority: must
- Status: Approved
- Acceptance criteria:
  - Damaged/breached/destroyed states update mesh, collision, and nav as authored.
  - Breached walls couple to atmosphere/hull breach accounting.
- Verification:
  - Scene integrity smoke (when implemented)

## REQ-MI-003: Module integrity persists as sparse deltas

- Source: \eatures/module_integrity.md\, ADR-0051
- Type: technical
- Priority: must
- Status: Approved
- Acceptance criteria:
  - Save/load and revisit restore only touched modules over regenerate-from-seed geometry.
- Verification:
  - Integrity snapshot round-trip smoke (when implemented)

## REQ-MI-004: Structure damage sources route through module integrity

- Source: \eatures/module_integrity.md- Type: gameplay
- Priority: must
- Status: Approved
- Acceptance criteria:
  - Fire, decompression, threat structure attacks, and player tools can damage modules.
- Verification:
  - Multi-source damage smoke (when implemented)

## REQ-WA-002: WorkActions emit noise, XP, and inventory yields

- Source: \eatures/work_actions.md- Type: gameplay
- Priority: must
- Status: Approved
- Acceptance criteria:
  - Completed work emits noise into threat detection, XP via TrainingEventBus, and yields into inventory/encumbrance.
- Verification:
  - WorkAction scene smoke (when implemented)

## REQ-WA-003: WorkActions interrupt on damage without double-consume

- Source: \eatures/work_actions.md- Type: gameplay
- Priority: must
- Status: Approved
- Acceptance criteria:
  - Mid-work damage interrupts progress; materials are not double-consumed.
- Verification:
  - WorkAction interrupt pure smoke (when implemented)

## REQ-WA-004: Repair/seal/suppress unify onto WorkActions

- Source: \eatures/work_actions.md- Type: gameplay / technical
- Priority: must
- Status: Approved
- Acceptance criteria:
  - One progress/interrupt/UI path covers patch/weld/seal/suppress; authored repair_point remains objective wrapper.
- Verification:
  - Repair unification smoke (when implemented)

## REQ-CMP-002: Components link to ship-system subcomponents

- Source: \eatures/component_slots.md- Type: gameplay / technical
- Priority: must
- Status: Approved
- Acceptance criteria:
  - Where authored, systems.json subcomponents map onto placed physical components.
- Verification:
  - Component link smoke (when implemented)

## REQ-CMP-003: Components mount and dismount as WorkActions

- Source: \eatures/component_slots.md- Type: gameplay
- Priority: must
- Status: Approved
- Acceptance criteria:
  - Dismount yields a heavy inventory item; remount restores placed component.
- Verification:
  - Mount/dismount smoke (when implemented)

## REQ-SMOD-002: Installs respect power budget constraints

- Source: \eatures/ship_modification.md- Type: gameplay
- Priority: must
- Status: Approved
- Acceptance criteria:
  - Over-budget installs are rejected or force authored degradation; better components draw more power.
- Verification:
  - Power budget install smoke (when implemented)

## REQ-SMOD-003: Hub growth is the walkable home ship

- Source: \eatures/ship_modification.md- Type: gameplay / design
- Priority: should
- Status: Approved
- Acceptance criteria:
  - Home ship stations/components/hydro support the explorable-hub fantasy without a separate hub scene.
- Verification:
  - Home-ship interaction verification smoke/playtest (when implemented)

## REQ-ARCH-003: ShipRuntime owns per-ship advance and catch-up

- Source: \eatures/ship_runtime.md\, pre-polish PKG-A1a
- Type: technical
- Priority: must
- Status: Implemented
- Acceptance criteria:
  - Per-ship systems manager advance and web→hull damage run through \ShipRuntime\.
  - Absent derelicts catch up in capped sub-steps; home ships skip catch-up.
  - Coordinator wrappers preserve existing catch-up smoke contracts.
- Verification:
  - \ship_runtime_smoke.gd  - \SHIP RUNTIME PASS  - \ship_catchup_smoke.gd  - \SHIP CATCHUP PASS

## REQ-ARCH-004: ShipRuntime snapshots compose multi-ship state

- Source: \eatures/ship_runtime.md\, pre-polish PKG-A1b
- Type: technical
- Priority: must
- Status: Implemented
- Acceptance criteria:
  - ShipRuntime to_snapshot/from_snapshot round-trips last_sim_time and ship summary.
  - Two independent ShipRuntimes advance without cross-mutation.
  - compose_runtime_snapshots bundles multiple runtimes under a stable schema.
- Verification:
  - \ship_runtime_smoke.gd  - \SHIP RUNTIME PASS\ with \snapshot=true multi=true

## REQ-ARCH-005: Shared home/away sim helpers (ShipRuntime A1c)

- Source: eatures/ship_runtime.md, pre-polish PKG-A1c
- Type: technical
- Priority: must
- Status: Implemented
- Acceptance criteria:
  - Present ships advance through _tick_present_ships (ShipRuntime) on both branches.
  - Sanity, arc, ammo/consumable decay, audio, and food helpers are shared — no home-only reimplementation for those systems.
  - Away survival smoke still PASSes with away_ticks.
- Verification:
  - main_playable_survival_away_smoke.gd
  - ship_runtime_smoke.gd / ship_catchup_smoke.gd

## REQ-ARCH-006: Tick stratification FRAME/SLOW/LAZY

- Source: eatures/ship_runtime.md, pre-polish PKG-A3
- Type: technical
- Priority: must
- Status: Implemented
- Acceptance criteria:
  - ShipRuntime exposes FRAME/SLOW/LAZY band polling with fixed intervals.
  - Present-ship systems advance every frame; hub expanded recompute is SLOW-banded.
  - Catch-up uses LAZY-aligned quanta and is still bounded.
- Verification:
  - 	ick_bands_smoke.gd — TICK BANDS PASS
  - ship_catchup_smoke.gd remains green

## REQ-PG-DRESS-001: Room variant dressing drives visual presets

- Source: pre-polish PKG-B5.1 / oom_variant_selector.gd- Type: gameplay / technical
- Priority: should
- Status: Implemented
- Acceptance criteria:
  - Each dressing id has fog/tint/light/prop_density preset data.
  - GeneratedShipLoader expands room_variant_descriptors with preset fields.
  - Loader instantiates deterministic DressingVisuals lights (and fog markers when density > 0).
- Verification:
  - \dressing_consumption_smoke.gd  - \DRESSING CONSUMPTION PASS