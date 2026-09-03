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
- Status: Implemented
- Acceptance criteria:
  - Salvaged components install into ship slots under power budget constraints.
  - Hub growth is physical (components/modules), not a separate hub scene.
  - Catalog-linked installs restore hub ship-system sub floor; uninstall damages the sub.
- Verification:
  - `scripts/validation/ship_modification_smoke.gd`
  - `scripts/validation/ship_mod_install_key_smoke.gd` marker `SHIP MOD INSTALL KEY PASS`
  - `scripts/validation/ship_mod_system_effect_smoke.gd` marker `SHIP MOD SYSTEM EFFECT PASS restore=true power=true uninstall_damage=true`

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
- Status: Implemented
- Acceptance criteria:
  - Damaged/breached/destroyed states update mesh, collision, and nav as authored.
  - Breached walls couple to atmosphere/hull breach accounting.
- Verification:
  - \module_integrity_consequences_smoke.gd\ (implemented)

## REQ-MI-003: Module integrity persists as sparse deltas

- Source: \features/module_integrity.md\, ADR-0051
- Type: technical
- Priority: must
- Status: Implemented (PKG-D6.1)
- Acceptance criteria:
  - Save/load and revisit restore only touched modules over regenerate-from-seed geometry.
- Verification:
  - `scripts/validation/pillar_revisit_persistence_smoke.gd` marker `PILLAR REVISIT PERSISTENCE PASS integrity=true components=true ship=true runtime=true`
  - ShipInstance `module_integrity` / `component_placement` sparse packs; coordinator leave/revisit flush via `_sync_current_ship_pillar_summaries`

## REQ-MI-004: Structure damage sources route through module integrity

- Source: features/module_integrity.md
- Type: gameplay
- Priority: must
- Status: Implemented
- Acceptance criteria:
  - Fire, decompression, threat structure attacks, and player tools can damage modules.
- Verification:
  - `scripts/validation/multi_source_module_damage_smoke.gd` marker `MULTI SOURCE MODULE DAMAGE PASS fire=true decomp=true threat=true tool=true interrupt=true`
  - `ModuleDamageRouter`; vent path + threat validation seam on playable

## REQ-WA-002: WorkActions emit noise, XP, and inventory yields

- Source: features/work_actions.md
- Type: gameplay
- Priority: must
- Status: Implemented
- Acceptance criteria:
  - Completed work emits noise into threat detection, XP via TrainingEventBus, and yields into inventory/encumbrance.
- Verification:
  - WorkAction driver/integration/interact smokes; `emit_training_event` on complete

## REQ-WA-003: WorkActions interrupt on damage without double-consume

- Source: features/work_actions.md
- Type: gameplay
- Priority: must
- Status: Implemented
- Acceptance criteria:
  - Mid-work damage interrupts progress; materials are not double-consumed.
- Verification:
  - Multi-source smoke interrupt case; vitals health drop calls `_interrupt_work_on_damage`

## REQ-WA-004: Repair/seal/suppress unify onto WorkActions

- Source: \eatures/work_actions.md- Type: gameplay / technical
- Priority: must
- Status: Implemented (PKG-B2.5)
- Acceptance criteria:
  - One progress/interrupt/UI path covers patch/weld/seal/suppress; authored repair_point remains objective wrapper.
- Verification:
  - `scripts/validation/repair_unification_smoke.gd` marker `REPAIR UNIFICATION PASS repair=true seal=true suppress=true interrupt=true catalog=true`

## REQ-CMP-002: Components link to ship-system subcomponents

- Source: features/component_slots.md
- Type: gameplay / technical
- Priority: must
- Status: Implemented
- Acceptance criteria:
  - Where authored, systems.json subcomponents map onto placed physical components.
- Verification:
  - `scripts/validation/component_system_link_smoke.gd` marker `COMPONENT SYSTEM LINK PASS catalog_links=true soft_fill=true coverage=true`
  - Coordinator calls `link_ship_systems` after component populate

## REQ-CMP-003: Components mount and dismount as WorkActions

- Source: \eatures/component_slots.md- Type: gameplay
- Priority: must
- Status: Implemented (PKG-B2.3b)
- Acceptance criteria:
  - Dismount yields a heavy inventory item; remount restores placed component.
- Verification:
  - `scripts/validation/component_mount_dismount_smoke.gd` marker `COMPONENT MOUNT DISMOUNT PASS dismount=true mount=true work=true mass=true round_trip=true`

## REQ-SMOD-002: Installs respect power budget constraints

- Source: eatures/ship_modification.md
- Type: gameplay
- Priority: must
- Status: Implemented
- Acceptance criteria:
  - Over-budget installs are rejected or force authored degradation; better components draw more power.
  - Component catalog authors per-component power_draw consumed on install.
- Verification:
  - scripts/validation/ship_modification_smoke.gd power_budget path
  - scripts/validation/ship_mod_system_effect_smoke.gd power=true

## REQ-SMOD-003: Hub growth is the walkable home ship

- Source: \eatures/ship_modification.md- Type: gameplay / design
- Priority: should
- Status: Approved
- Acceptance criteria:
  - Home ship stations/components/hydro support the explorable-hub fantasy without a separate hub scene.
- Verification:
  - \hub_explorable_verify_smoke.gd\ (implemented)

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

## REQ-PG-PACING-001: Encounter tension budget pacing

- Source: pre-polish PKG-C5.3 / \ncounter_injector.gd- Type: gameplay / technical
- Priority: must
- Status: Implemented
- Acceptance criteria:
  - Critical-path rooms remain non-spawn camps (REQ-PG-007).
  - Entry rooms are quieter; probability escalates with graph progress toward the objective.
  - Branch depth scales encounter chance (risk/reward).
  - Density-high runs may force one authored spike near the objective.
  - Markers adjacent to critical path flag \patrol_crosses_critical\.
- Verification:
  - \ncounter_injector_smoke.gd  - \ENCOUNTER INJECTOR PASS

---

# Asset metadata and visual binding requirements (Task 1)

## REQ-AVB-001: Every governed prop has an adjacent `.sidecar.json`

- Source: `features/asset_metadata_pipeline.md`, ADR-0052
- Type: technical / content pipeline
- Priority: must
- Status: Approved (Task 1 contract)
- Acceptance criteria:
  - The 26 governed component, dressing, and supplied objective props each have exactly one
    adjacent same-basename `.sidecar.json` file paired with its GLB.
  - Missing, duplicate, or mismatched sidecars fail validation rather than being silently
    omitted from the runtime view.
- Verification:
  - Future prop validator with `--check-index`, as listed in `docs/game/06_validation_plan.md`.

## REQ-AVB-002: Sidecars validate schema, path, hash, and bounds

- Source: `features/asset_metadata_pipeline.md`, ADR-0052
- Type: technical / content pipeline
- Priority: must
- Status: Approved (Task 1 contract)
- Acceptance criteria:
  - Each sidecar document has `schema_version: "1.0.0"` and
    `document_kind: "prop_visual_binding"` and is the same-basename `.sidecar.json`
    adjacent to its named source GLB.
  - `source.sha256` is the SHA-256 digest represented by exactly 64 lowercase hexadecimal
    characters.
  - `bounds.local_min_m` and `bounds.local_max_m` are meter-space `[x, y, z]` local min/max
    arrays, with every coordinate rounded to six decimal places.
  - Canonical sidecar JSON is lexicographically key-sorted, compact, newline-terminated,
    and timestamp-free; the recorded hash and bounds match the explicit GLB-derived refresh
    contract.
  - Direct prop records declare `collision_policy=none_visual_only`.
- Verification:
  - Future prop validator with `--check-index`.
  - Future structural audit for structural contracts.

## REQ-AVB-003: Visual metadata does not duplicate gameplay state

- Source: `features/asset_metadata_pipeline.md`, ADR-0052
- Type: gameplay / technical boundary
- Priority: must
- Status: Approved (Task 1 contract)
- Acceptance criteria:
  - Sidecars and the derived index may contain visual/content metadata only: source hash,
    bounds, category, visual policy, provenance, bindings, placement, and extensions.
  - Gameplay state is forbidden, including component lifecycle/state, ship-system state,
    objective progression/volumes, collision, navigation, and structural integrity state.
  - Component lifecycle, ship-system state, objective progression, objective volumes,
    collision, navigation, and structural integrity remain owned by their existing
    gameplay/runtime systems.
- Verification:
  - Future prop and objective visual-binding smokes plus structural audit.

## REQ-AVB-004: Component bindings preserve lifecycle and system linkage

- Source: `features/asset_metadata_pipeline.md`, `features/component_slots.md`, ADR-0052
- Type: gameplay / technical
- Priority: must
- Status: Approved (Task 1 contract)
- Acceptance criteria:
  - Every supplied component binding resolves by its authored component ID.
  - Mount, dismount, rebuild, and component-marker placement remain owned by the component
    runtime; component save/load ownership and restoration remain there as well, with
    lifecycle ownership and ship-system subcomponent linkage intact after visual resolution.
- Verification:
  - Future prop visual binding smoke.
  - Existing component marker and component-system-link smokes remain regression evidence.

## REQ-AVB-005: Objective bindings use gameplay placement IDs

- Source: `features/asset_metadata_pipeline.md`, `features/objective_variation.md`, ADR-0052
- Type: gameplay / technical
- Priority: must
- Status: Approved (Task 1 contract)
- Acceptance criteria:
  - Every supported supplied objective visual binding resolves by gameplay-authored
    `placement_id`.
  - Objective type is never used as the identity key, and objective volume and progression
    ownership remain in gameplay systems.
- Verification:
  - Future objective visual binding smoke.
  - Existing objective variation and objective-progress smokes remain regression evidence.

## REQ-AVB-006: Invalid bindings use explicit fallback

- Source: `features/asset_metadata_pipeline.md`, ADR-0052
- Type: gameplay / technical boundary
- Priority: must
- Status: Approved (Task 1 contract)
- Acceptance criteria:
  - A missing, malformed, stale, or unsupported component binding retains the existing
    primitive fallback; the same failure in an objective binding retains the existing
    readability fallback.
  - Both resolved records report `visual_source="fallback"`.
  - No unrelated component, objective, or prop visual is selected as a substitute by either
    fallback.
- Verification:
  - Future prop visual binding smoke.
  - Future objective visual binding smoke.

## REQ-AVB-007: Structural variants preserve wrapper contracts

- Source: `features/asset_metadata_pipeline.md`, ADR-0052
- Type: technical / structural runtime
- Priority: must
- Status: Approved (Task 1 contract)
- Acceptance criteria:
  - Structural wrappers validate and switch intact, damaged, and breached visual variants.
  - Connector/socket ownership, collision proxies, passability, and integrity ownership do
    not drift when the visual state changes.
- Verification:
  - `scripts/placement/validate_wrapper_scenes.gd` against
    `scenes/wrappers/structural/ship_structural_v0`.
  - Future structural audit and structural variant smoke.

## REQ-AVB-008: Derived index freshness is deterministic

- Source: `features/asset_metadata_pipeline.md`, ADR-0052
- Type: technical / content pipeline
- Priority: must
- Status: Approved (Task 1 contract)
- Acceptance criteria:
  - The only canonical derived index path is `data/props/visual_bindings.generated.json`.
  - The index document has `schema_version: "1.0.0"` and
    `document_kind: "prop_visual_binding_index"` and is generated only from valid
    same-basename `.sidecar.json` files and source GLBs.
  - Repeated generation from unchanged inputs produces byte-identical canonical JSON:
    lexicographically key-sorted, compact, newline-terminated, and timestamp-free.
  - A stale, hand-edited, or source-mismatched index fails the freshness gate, including
    when any source hash or six-decimal local bounds value differs.
- Verification:
  - Future prop validator with `--check-index`.
  - Future structural audit where structural records participate in the derived view.

## REQ-WALK-001: Compiler-edge walkability and nav

- Source: `features/compiler_walkability.md`, ADR-0054
- Type: gameplay / technical
- Priority: must
- Status: Validated
- Rationale: Enclosure flood must stay watertight including `LOCKED`/`BREACH`; standing play and production `ShipNavGraph` must not tunnel `SOLID`, `LOCKED`, or `BREACH`.
- Acceptance criteria:
  - Two floods: enclosure = non-SOLID all occupied cells; standing-play = OPEN/DOOR/HATCH + `vertical_connections`, start→goal only.
  - `ShipNavGraph` standing path cannot cross `SOLID`, `LOCKED`, or `BREACH`.
  - `LOCKED`/`BREACH` exist in `_base_edges` at `BLOCKED_COST` for the life of this stack (no `unlock_edge`).
  - Walkability Stage A capsule-sweeps SOLID (must hit 0.20 m slab) and DOOR (must pass 0.80×1.70 opening).
  - `coherent_ship_001` biomatter shortcut is standing-blocked.
  - Stacked `vertical_connections` path.
- Verification:
  - `procgen_walkability_smoke.gd`
  - `ship_nav_graph_smoke.gd`
  - `procgen_quality_gate_smoke.gd`

## REQ-DECAY-001: Live wreck stamps

- Source: `features/live_decay_stamping.md`
- Type: gameplay / technical
- Priority: must
- Status: Validated
- Rationale: DAMAGED/WRECKED generation must overlay locked doors and pre-damaged modules on the live compile path without deleting `room_links`.
- Acceptance criteria:
  - `Condition.DAMAGED` / `WRECKED` layouts overlay `blocked_links` without removing `room_links`.
  - Matching portals are `LOCKED` (optional existing-DOOR `BREACH` on WRECKED). Never insert a portal.
  - `wreck_applied=true` and `module_damage` keyed by loader `module_key` after the last compile.
  - At least one wrapper is not `intact`, with the Damaged or Breached child visible.
  - Imports emit no unclassified ERROR/WARNING. `_layout_is_connected` remains true. Standing start→goal remains.
- Verification:
  - `live_decay_stamp_smoke.gd`
  - `structural_variant_wrapper_smoke.gd`
  - `procgen_quality_gate_smoke.gd`

## REQ-DECAY-002: Structural wrapper collision matches walkability contract

- Source: `features/structural_wrapper_collision.md`
- Type: gameplay / technical
- Priority: must
- Status: Validated
- Rationale: Live wall/door proxies must be 0.20 m slabs and a posts+header opening, not 1×1×1 cubes, so the player capsule matches Stage A walkability numbers.
- Acceptance criteria:
  - `wall_straight_1x1` / `wall_end_cap` one `BoxShape3D(4, 3, 0.2)`.
  - Inner/outer corner two wing slabs (not a 4×3×4 AABB); T-junction three wing slabs.
  - `doorway_frame_open_1x1` posts at X ±1.3 m plus header bottom at Y=2.2 m; standing 0.80×1.70 opening is clear.
  - `doorway_frame_blocked_1x1` full `BoxShape3D(4, 3.2, 0.2)` slab.
  - `bulkhead_portal_2x1` unchanged.
  - Numbers match `walkability_contract.gd`.
- Verification:
  - `structural_wrapper_collision_footprint_smoke.gd`

## REQ-AVB-009: Explicit derived refresh preserves authored extensions

- Source: `features/asset_metadata_pipeline.md`, ADR-0052
- Type: technical / content pipeline
- Priority: must
- Status: Approved (Task 1 contract)
- Acceptance criteria:
  - An explicit GLB-derived refresh replaces the full GLB-derived source evidence:
    `source.sha256` (SHA-256), `source.byte_size`, `source.mesh_count`,
    `source.gltf_version`, and six-decimal meter-space local min/max bounds.
  - The refresh preserves only hand-authored extensions, binding fields, placement fields,
    and provenance; those authored fields survive without semantic loss.
  - The refreshed sidecar and regenerated index use lexicographically key-sorted, compact,
    newline-terminated, timestamp-free canonical JSON.
  - A refresh is explicit and reproducible; importing or re-reading a GLB does not perform
    a blind destructive rewrite or add a timestamp.
- Verification:
  - Future prop validator refresh-preservation check.
  - Future prop visual binding smoke with an extension/provenance fixture.

---

# Meshy-to-Blender candidate asset pipeline (ADR-0058)

These requirements govern the implemented candidate-only AI asset workflow described in
`features/ai_candidate_asset_pipeline.md`. The toolchain is implemented and host-verified at
commit `4dc9e7d7f7aee2c5884bb72118949583737e8994`; that implementation evidence is separate from
real provider candidates, which remain a post-PR live-pilot limitation. Meshy output is never a
runtime source, and promotion is always a separate reviewed task.

## REQ-AIAP-001: Contract-first candidate generation

- Source: `features/ai_candidate_asset_pipeline.md`, ADR-0058
- Type: process / content pipeline
- Priority: must
- Status: Implemented
- Acceptance criteria:
  - A validated repository asset contract exists before reference packaging, candidate
    selection, Blender cleanup, or any Meshy API call.
  - The contract defines category, gameplay role, dimensions and tolerance, pivot, `+Z`
    forward, required states, budgets, generation policy, reference requirements, and runtime
    review matrix.
  - Threat and kit triangle budgets use an explicit range plus scope (such as per organism,
    per module, or final kit), not one ambiguous scalar.
  - `hull_tendril_kit_v1` and `biomatter_swarm_kit_v1` include explicit `deliverables`/`kit_parts`
    arrays that enumerate their required modules, parts, and state coverage.
  - Structural floors, walls, doors, ramps, sockets, collision, and damage topology are not
    valid Meshy generation targets.
- Verification:
  - `/usr/bin/python3 tools/meshy_asset_contract.py validate data/asset_generation/contracts/*.json`
  - Focused Meshy suite: 340 passed at the implementation snapshot.

## REQ-AIAP-002: Reference consistency and rights

- Source: `features/ai_candidate_asset_pipeline.md`, ADR-0058
- Type: content pipeline / legal
- Priority: must
- Status: Implemented
- Acceptance criteria:
  - Required reference views are separate image files, consistent in subject, proportions, and
    design language; a collage cannot substitute for separate views.
  - Every input records a hash and an explicit rights/license state before upload.
  - Missing, inconsistent, unlicensed, or ambiguous references fail closed before provider
    submission.
- Verification:
  - Focused Meshy contract/staging/provenance tests pass; real rights-cleared pilot files are
    intentionally absent until the post-PR live pilot.

## REQ-AIAP-003: Standing subscription authorization and request integrity

- Source: `features/ai_candidate_asset_pipeline.md`, ADR-0058
- Type: process / request integrity
- Priority: must
- Status: Implemented
- Acceptance criteria:
  - Standing project subscription authorization permits post-PR testing; spend, cap, and
    account bookkeeping are not a human blocker.
  - `--approved-credits` remains required and equals the plan's `maximum_credits` as a
    request-envelope/integrity field, not renewed human spend approval.
  - No API call occurs without the validated contract, validated reference rights, the required
    approved-credits field, and an immutable request record.
  - Within one governed batch, each planned candidate record permits exactly one paid creation
    POST attempt. A transport failure, timeout, `429`, `5xx`, or other ambiguous outcome is
    reconciled from the immutable journal and is never automatically retried.
- Verification:
  - Focused staging and request-integrity tests pass; the plan command is read-only and makes no
    provider call.

## REQ-AIAP-004: Immutable staged provenance

- Source: `features/ai_candidate_asset_pipeline.md`, ADR-0058
- Type: technical / provenance
- Priority: must
- Status: Implemented
- Acceptance criteria:
  - Candidate output is isolated below `assets/_staging/meshy/<asset_id>/<task_id>/`.
  - The immutable generation record captures the exact request, contract/reference/prompt
    hashes, provider/model/task identifiers, output hashes and sizes, license state, and
    consumed credits.
  - Records contain no API key, authorization header, signed download URL, or local secret.
  - Later review and validation decisions do not rewrite immutable generation facts.
- Verification:
  - Focused staging/provenance tests and protected-path tests pass.

## REQ-AIAP-005: Blender canonical master

- Source: `features/ai_candidate_asset_pipeline.md`, ADR-0058
- Type: technical / content pipeline
- Priority: must
- Status: Implemented
- Acceptance criteria:
  - A selected candidate becomes eligible for runtime review only after a canonical external
    Blender master exists.
  - Blender owns the editable master, topology, UVs, exact meter scale, pivot, `+Z` forward,
    alternate-state derivation, rig, cleanup, and normalized GLB export.
  - All alternate states derive from one Blender master; independently generated states are
    rejected.
  - Blender does not become the owner of runtime collision, navigation, sockets, integrity,
    or damage topology.
- Verification:
  - `/usr/bin/python3 tools/meshy_blender_master.py ...`
  - `/usr/bin/python3 tools/meshy_blender_validate.py ...`
  - Host Blender focused tests pass for valid re-import/publication and non-affine rejection.

## REQ-AIAP-006: Geometry, material, and scale gate

- Source: `features/ai_candidate_asset_pipeline.md`, ADR-0058
- Type: technical / visual quality
- Priority: must
- Status: Implemented
- Acceptance criteria:
  - The normalized GLB is independently re-imported and checked against the contract for
    readable geometry, dimensions/tolerance, exact scale, pivot, `+Z` forward, applied
    transforms, triangle/material budgets, UVs, and permitted state/rig policy.
  - Texturing is downstream of candidate selection and geometry/UV approval; baked lighting,
    floating helpers, collision nodes, and forbidden structural gameplay geometry fail the
    visual export gate.
  - The validator reports failures rather than silently decimating, retopologizing, or
    otherwise changing the Blender master.
- Verification:
  - Host Blender re-import/publication tests pass; a real external pilot GLB is not available
    until the post-PR live pilot.

## REQ-AIAP-007: Wrapper-owned gameplay concerns

- Source: `features/ai_candidate_asset_pipeline.md`, ADR-0058, ADR-0052
- Type: gameplay / technical boundary
- Priority: must
- Status: Implemented
- Acceptance criteria:
  - Godot wrappers and repository runtime data remain authoritative for collision, navigation,
    sockets/connectors, integrity/damage state, VFX/animation integration, and gameplay
    bindings.
  - Meshy candidates and Blender visual exports do not author or replace structural floors,
    walls, doors, ramps, sockets, collision, or damage topology.
  - Existing ADR-0052 prop GLB+sidecar records, generated visual-binding index, placement IDs,
    fallbacks, and wrapper contracts remain intact; visual refresh cannot duplicate gameplay
    state.
- Verification:
  - Existing Godot visual/catalog, structural-loader, and generated-seed smokes remain the
    regression path; candidate runtime evidence is supplied by the post-PR live pilot.

## REQ-AIAP-008: Locked-isometric seed review

- Source: `features/ai_candidate_asset_pipeline.md`, ADR-0058
- Type: runtime validation
- Priority: must
- Status: Implemented
- Acceptance criteria:
  - A temporary overlay reviews the staged normalized GLB in the real `breach_field` derelict
    environment with the production locked-isometric camera.
  - The review runs seeds `42` and `777` under `normal`, `emergency`, and `dark` lighting,
    for exactly six cases, and publishes captures only after all six pass.
  - Unexpected `ERROR:`, `WARNING:`, or `SCRIPT ERROR:` output blocks runtime acceptance
    unless that exact output is explicitly classified by the validation plan.
- Verification:
  - `/usr/bin/python3 tools/meshy_runtime_review.py ...` and the existing Godot smoke commands
    in `docs/game/06_validation_plan.md`; six real candidate captures remain post-PR pilot
    evidence.

## REQ-AIAP-009: No automatic promotion

- Source: `features/ai_candidate_asset_pipeline.md`, ADR-0058
- Type: process / release safety
- Priority: must
- Status: Implemented
- Acceptance criteria:
  - Generation, candidate review, Blender cleanup, validation, and runtime review cannot write
    to `assets/imported`, `data/combat/threat_visual_catalog.json`,
    `data/props/visual_bindings.generated.json`, or `scenes/wrappers`.
  - Any sidecar, generated-index, catalog, or wrapper change is a reviewable proposal only.
  - Promotion occurs only through a separate reviewed task with an explicit diff and complete
    provenance.
- Verification:
  - Protected-path and no-promotion tests pass; no live catalog, index, wrapper, or imported
    asset is produced by this documentation phase.

## REQ-AIAP-010: Skill pressure-test compliance

- Source: `features/ai_candidate_asset_pipeline.md`, ADR-0058, implementation plan Task 12
- Type: process / operator workflow
- Priority: must
- Status: Implemented
- Acceptance criteria:
  - The umbrella asset skill refuses structural Meshy routes, independently generated states,
    premature texturing, non-humanoid auto-rigging, collage substitution, contract bypass,
    duplicate or ambiguous paid submission, and self-authored relabeling of AI provenance.
  - The skill routes operators to the repository contract, staging, Blender, runtime-review,
    and separate-promotion gates rather than improvising direct Godot import.
  - RED/GREEN pressure scenarios demonstrate behavior change and are recorded as proof.
- Verification:
  - `docs/superpowers/proofs/meshy-skill-pressure-tests.md` and its focused scenarios.

---

# Socketed enclosed interiors (ADR-0053)

## REQ-ENC-001: Topology construction emits connector-grown occupancy with shared edges

- Source: `features/socketed_enclosed_interiors.md`
- Type: technical / procgen
- Priority: must
- Status: Approved
- Rationale: Occupancy-only greedy placement and `ROOM_GAP` spacing are why rooms do not exist as shared-edge volumes. The cell-grid contract stays; the placer algorithm does not.
- Acceptance criteria:
  - Every generated room is a non-empty 4-connected integer cell set on the 4 m grid.
  - Template-declared connections become shared cardinal edges or vertical connections.
  - No live path spaces rooms by `CELL_SIZE + ROOM_GAP`.
  - `CellLayoutEngine.layout()` output shape (`rooms`, `adjacencies`, footprints) remains the input to serialization.
- Verification:
  - `socketed_enclosure_smoke.gd` (`no_room_gap=true` when GREEN)
  - Existing `cell_layout_engine_smoke.gd` remains green

## REQ-ENC-002: Boundary compilation consumes kit sockets and emits watertight rooms

- Source: `features/socketed_enclosed_interiors.md`
- Type: technical / procgen
- Priority: must
- Status: Approved
- Rationale: Hardcoded `wall_straight_1x1` on occupancy edges ignores wrapper sockets, skips corners and ceilings, and produces walls that do not close rooms.
- Acceptance criteria:
  - The compiler loads `ModularAssetSpec` contracts for the layout `kit_id` and chooses `module_id` by socket match.
  - Every occupied cell has a floor and a ceiling unless it is an authored vertical opening.
  - Every exterior non-OPEN edge is a wall or portal with `socket_bindings`.
  - Vertices use corner / junction modules when those contracts match.
  - Floor cardinal sockets are XZ cell-edge positions (north = −Z), and `floor_edge` is compatible with `wall_base`.
  - New plan fields live inside `structural_plan`; `layout.json` schema_version stays `1.2.0`.
- Verification:
  - `socketed_enclosure_smoke.gd` (`sockets_consumed`, `watertight`, `corners_used`, `floor_socket_axes` when GREEN)
  - `structural_plan_validator` fail-closed on floor-only plans
  - `wall_door_resolver_smoke.gd` and `structural_live_loader_smoke.gd` remain green

## REQ-ENC-003: Hub and lifeboat use the same compiler; StructuralPlacer is not a live path

- Source: `features/socketed_enclosed_interiors.md`
- Type: technical / procgen
- Priority: must
- Status: Approved
- Rationale: `LifeBoatBuilder.build()` still instances the deprecated gapped placer, and `build_layout()` writes floor-only rooms with empty portals.
- Acceptance criteria:
  - `LifeBoatBuilder.build_layout()` emits schema `1.2.0` with a validated `structural_plan` and portals on the two real shared edges.
  - `LifeBoatBuilder.build()` instances that plan and does not call `StructuralPlacer.place_structure`.
  - Enclosure rules in REQ-ENC-002 apply to the hub craft.
- Verification:
  - `socketed_enclosure_smoke.gd` (`hub_plan=true`, `no_floor_only=true` when GREEN)
  - Existing `life_boat_layout_smoke.gd` remains green for the 3-room role contract

## REQ-ENC-004: Biome kit selection remaps stems on the enclosed kit, and the enclosure smoke is the gate

- Source: `features/socketed_enclosed_interiors.md`
- Type: technical / procgen
- Priority: should
- Status: Approved
- Rationale: `_kit_id_for_biome` currently returns `ship_structural_v0` for every biome, so derelict / hive flavour cannot skin enclosed rooms even after sockets work. Enclosure itself is REQ-ENC-001..003; this row is the theme binding.
- Acceptance criteria:
  - `kit_id` follows `KitCatalog` biome preference (`breach_field` → hazard kit, `dead_fleet` → industrial kit, default → `ship_structural_v0`) without changing occupancy.
  - No new hive / wreck meshes are required; kits remap existing stems.
  - `socketed_enclosure_smoke.gd` is RED (`SOCKETED ENCLOSURE FAIL`) until REQ-ENC-001..003 pass, then prints `SOCKETED ENCLOSURE PASS` and is added to the regression bundle. It is not in the bundle while RED.
- Verification:
  - `socketed_enclosure_smoke.gd`
  - `kit_catalog_smoke.gd` remains green

---

# Enclosed slot fill (remaining procgen play stack WP3)

## REQ-FILL-001: Slot-native interior fill

- Source: `features/enclosed_slot_fill.md`, `features/remaining_procgen_play_stack.md` WP3
- Type: gameplay / technical
- Priority: must
- Status: Implemented
- Rationale: Enclosed rooms already expose `wall_slots` / `center_slots`; dumping loot on the first `floor_cell_*` is the remaining empty-box tell.
- Acceptance criteria:
  - Consumers read `room.interior_zones.{wall_slots,center_slots,reserved_cells}` with `[x, z]` cells (one-release parse of `"(x, y)"` strings).
  - Generated loot / salvage / components / dressing use those slots; no live dump on the first `floor_cell_*` unless that cell is the chosen slot.
  - Dressing clutter is not `ReadabilityPropFactory` unique affordance names; props are `DressingProp_<room>_<index>` with `collision_policy=none_visual_only`.
  - Slots stay compile-time SOLID-wall cells; do not re-resolve after BREACH overlay.
- Verification:
  - `scripts/validation/enclosed_slot_fill_smoke.gd` marker `ENCLOSED SLOT FILL PASS loot_on_slot=true no_floor_dump=true components_on_cell=true dressing=true`
  - Existing component slot smokes remain green

---

# Hive topology + biomatter kit remap

## REQ-HIVE-001: Hive template + biomatter kit remap

- Source: `features/hive_biomatter_kit.md`
- Type: technical / procgen
- Priority: should
- Status: Approved
- Rationale: Hive flavour is occupancy topology plus a kit-id stamp on the same sockets. Unique meshes and a fourth biome are later content.
- Acceptance criteria:
  - `hive.json` loads through `CellLayoutEngine` (shared cardinal edges, integer occupancy).
  - Generator stamps `template_id` after serialize (not in `LayoutSerializer`).
  - When `template_id == "hive"`, `kit_id = ship_structural_biomatter`, independent of biome.
  - That kit’s `modules[].godot_wrapper_scene` may be v0 paths (intentional first milestone, not a visual remap).
  - Compiler sockets fall back to v0 contracts. `ShipGenerator` passes a kit file that contains wrapper scenes.
  - `"hive"` is in `EXTENDED_TEMPLATES` only — not a derelict guaranteed template, not forced into the 16-seed quality-gate pool.
- Verification:
  - `hive_biomatter_kit_smoke.gd` (`HIVE BIOMATTER KIT PASS template=true kit=true sockets_fallback=true occupancy=true v0_paths=true`)
  - `kit_catalog_smoke.gd` remains green
  - `template_selector_smoke.gd` legacy three unchanged

---

# Boarded generated-seed slice

## REQ-SLICE-001: Boarded generated-seed play proof

- Source: `features/generated_seed_boarded_slice.md`, `features/vertical_slice_v1.md`
- Type: gameplay / technical
- Priority: must
- Status: Validated
- Rationale: Walkability, live decay, wrapper collision, and slot fill are only play once a production `travel_to` boarding attaches `current_ship` and enters the away `_process` branch. `generate_from_seed` alone does not board.
- Acceptance criteria:
  - Headless `travel_to_marker_id` boarding of a generated wreck (not `coherent_ship_001`), copied from `away_branch_integrity_smoke.gd`.
  - `away_from_start` is true as a result of `_attach_derelict_active`.
  - Standing nav start→goal, slot-placed loot, wreck overlay when the boarded condition is DAMAGED/WRECKED, at least one objective, `away_ticks=30`.
  - No extract requirement. Bundle pin does not include `seed=42`.
- Verification:
  - `scripts/validation/generated_seed_boarded_slice_smoke.gd` — registered in the bundle in the same PR after GREEN

---

# Derelict builder runtime preview

## REQ-PCG-BUILDER-001: Builder bundles must pass the real local runtime preview

- Source: `features/derelict_builder_runtime_preview.md`, ADR-0057
- Type: technical / gameplay
- Priority: must
- Status: Approved
- Rationale: A builder export is not working until the Synaptic Sea loads the authored area through `GeneratedShipLoader` and observes its runtime behavior.
- Acceptance criteria:
  - A validated `derelict_builder_bundle` manifest resolves layout, gameplay-slice, and kit paths relative to the manifest, while preserving an absolute kit path.
  - Actual structural wrappers provide collision and navigation; vertical links, objectives, authored props, loot, fire, arc, breach, radiation, and authored atmosphere have observable consumers.
  - Missing or unsupported runtime semantics fail readiness and produce machine-readable result JSON plus a non-zero exit code.
- Verification:
  - Dedicated local preview smoke emits `DERELICT BUILDER PREVIEW PASS collision=true navigation=true verticals=true objectives=true props=true loot=true fire=true arc=true breach=true radiation=true atmosphere=true`.

---

# Procedural biomass assembly

## REQ-BIO-001: Canonical part catalog and schema

- Source: `features/procedural_biomass_assembly.md`, ADR-0059
- Type: technical / asset
- Priority: must
- Status: Validated (Task 1 contract)
- Rationale: Every assembled threat must draw from one strict, deterministic eight-part catalog.
- Acceptance criteria:
  - `data/combat/biomass_part_catalog.json` validates against `data/combat/schemas/biomass_part_catalog_v1.schema.json`.
  - The document contains exactly the eight canonical `biomass_*` IDs, exact categories, roles, budgets, sockets, collision descriptors, fallbacks, and limits.
  - Empty wrapper paths are valid fallback authority; non-empty paths are existing project-relative `res://` paths.
- Verification:
  - `PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 PYTHONPATH=. /opt/homebrew/bin/python3.11 -m pytest -q tests/test_biomass_catalog_validate.py`
  - `tools/biomass_catalog_validate.py --project-root . --parts data/combat/biomass_part_catalog.json --recipes data/combat/biomass_recipe_catalog.json`

## REQ-BIO-002: Repository-owned socket contract

- Source: `features/procedural_biomass_assembly.md`, ADR-0058, ADR-0059
- Type: technical / asset boundary
- Priority: must
- Status: Validated (Task 1 contract)
- Rationale: Socket and connector behavior must remain in repository data and Godot wrappers, not in exported visual assets.
- Acceptance criteria:
  - Socket names, kinds, accepted categories, local positions, rotations, and `root_0` (`socket_root_0` in the part catalog) child alignment are data-defined.
  - Local `+Y` is up and `+Z` is forward/outward; alignment uses `parent_socket.global_transform * child_socket.transform.affine_inverse()`.
  - Exported Meshy/Blender GLBs are visual-only and contain no socket markers, marker empties, collision shapes, or helper nodes.
- Verification:
  - Part-catalog validator and schema tests.
  - ADR-0058 authority review.

## REQ-BIO-003: Canonical BiomassRecipe resource

- Source: `features/procedural_biomass_assembly.md`, ADR-0059
- Type: technical / gameplay
- Priority: must
- Status: Validated (Task 1 contract)
- Rationale: An explicit attachment graph is the stable boundary between recipe generation, runtime assembly, and save/load.
- Acceptance criteria:
  - `data/combat/biomass_recipe_catalog.json` validates against `data/combat/schemas/biomass_recipe_catalog_v1.schema.json`.
  - Recipe records have exactly `recipe_id`, `locomotion_hint`, `core`, and `attachments`; edges have exactly the six canonical fields.
  - Unknown/missing fields, duplicate keys, non-finite numbers, unknown IDs, incompatible categories, missing child roots, duplicate IDs/occupancy, forward references, cycles, and limit violations fail closed with sorted diagnostics.
- Verification:
  - `tools/biomass_catalog_validate.py --project-root . --parts data/combat/biomass_part_catalog.json --recipes data/combat/biomass_recipe_catalog.json`
  - Focused biomass catalog test suite.

## REQ-BIO-004: Runtime assembly ownership

- Source: `features/procedural_biomass_assembly.md`, ADR-0058, ADR-0059
- Type: technical / gameplay
- Priority: must
- Status: Proposed
- Rationale: The runtime assembler must apply repository socket-space graphs without moving gameplay authority into visual assets, and gait setup must fail closed before an invalid visual becomes live.
- Acceptance criteria:
  - A per-manager `RefCounted` assembler creates wrapper-owned runtime nodes under the calling threat manager; no assembler or gait controller autoload, shared service, or scene-tree controller is introduced.
  - Each assembled `BiomassThreatVisual` owns exactly one private `RefCounted` gait controller and records immutable assembly-rest transforms without adding Nodes or changing node/triangle/collision counts: each part rest is immediate-parent-local (visual-local core or mount-local child), while each direct-child mount rest is visual-root-local.
  - The visual exposes `part_rest_transform(instance_id: String) -> Variant` and `attachment_rest_transform(instance_id: String) -> Variant`, returning the corresponding local `Transform3D` for a known ID and `null` otherwise; reset restores mounts then parts directly and never assigns visual-root-local `part_to_visual` to a mount-parented child.
  - `configure_gait(parts, recipe, biomass_seed)` is called only after `assembler.build(recipe, parts)` succeeds and before scene-tree registration or gait stepping; false frees the visual synchronously and selects the existing whole-threat primitive fallback.
  - Configuration rejects wrong scripts, unloaded catalogs, invalid recipes, recipe-document mismatches, and missing core/attachment part, mount, or rest data without retaining partial controller state; the visual remains at assembly rest and stepping is a no-op.
  - Godot wrappers own collision, navigation, connectors, and gameplay bindings; the core, visual/root transform, world position, recipe, AI state, meshes, and bones remain under their existing authorities.
  - A core may be a skull; a torso is not mandatory.
- Verification:
  - `scripts/validation/biomass_assembly_smoke.gd` for rest APIs, fail-closed setup, exact assembly preservation, and the Task 6 gait marker.
  - `scripts/validation/biomass_threat_manager_smoke.gd` for six configured archetype visuals, no controller Node child, and exactly one whole-threat fallback for the invalid fixture.

## REQ-BIO-005: Deterministic random recipes

- Source: `features/procedural_biomass_assembly.md`, ADR-0059
- Type: technical / gameplay
- Priority: should
- Status: Approved
- Rationale: Seeded random assembly creates emergent forms while preserving reproducibility and graph safety.
- Acceptance criteria:
  - Random recipes draw only from the canonical catalog, pass the same graph and locomotion checks as curated recipes, and are byte-deterministic for a fixed seed.
  - The six archetype pools remain deterministic and contain only the five curated recipe IDs.
  - New records may select/generate; restored biomass records never regenerate. Missing/invalid recipe or seed yields a stable diagnostic and whole-threat fallback, while dead restored records remain dead and create no visual/fallback.
- Verification:
  - Seeded recipe-generation smoke, repeated canonical serialization comparison, and Task 7 restore-matrix smoke with defensive sorted/deduplicated `ThreatManager.get_restore_diagnostics()`.

## REQ-BIO-006: Five locomotion gait profiles

- Source: `features/procedural_biomass_assembly.md`, ADR-0059
- Type: gameplay / technical
- Priority: must
- Status: Approved
- Rationale: Five explicit hints cover the intended assembled-threat movement families without requiring a skeleton or IK contract, while deterministic rest-based stepping prevents pose drift.
- Acceptance criteria:
  - `biped` has exactly two locomotor parts and a head.
  - `quadruped` has exactly four locomotor parts and a head.
  - `crawl` has at least one locomotor part; `drag` has at least one puller; `slither` has at least one slither part.
  - `BiomassThreatVisual.configure_gait(parts: Variant, recipe: Variant, seed_value: int) -> bool` owns one private `RefCounted` controller per visual and rejects invalid dependencies before retaining references.
  - Role-driven mounts are selected from attachment part roles, sorted by instance ID, assigned deterministic profile phases, rebuilt from immutable root-local rest each step, and leave non-driven mounts exactly at rest.
  - Active gait changes only driven mount orientations within the total angular bound; rest/near-zero states use bounded pose-weight decay, and invalid deltas are no-ops.
  - Reconfiguration restores assembly rest, resets elapsed/weight/phase deterministically, replaces the controller, and does not alter the core, visual/root transform, world position, recipe, AI state, meshes, or bones. Core bob/yaw is a v1 no-op.
  - Gaits are rigid socket-space profiles, not skeleton/IK behavior.
- Verification:
  - `scripts/validation/biomass_assembly_smoke.gd`, run twice with byte-identical complete output, including `BIOMASS GAIT PASS recipes=5 profiles=5 deterministic=true bounded=true rest=true drift=false` and no `WARNING:`, `ERROR:`, or `SCRIPT ERROR:` lines.
  - `scripts/validation/biomass_threat_manager_smoke.gd` proves all six valid archetype visuals have active configured gaits and the invalid fixture uses exactly one whole-threat fallback.

## REQ-BIO-007: Exact assembly save/load persistence

- Source: `features/procedural_biomass_assembly.md`, ADR-0059
- Type: technical / persistence
- Priority: must
- Status: Approved
- Rationale: Reloading an assembled threat must restore its authored graph rather than silently generating a different threat.
- Acceptance criteria:
  - Save/load preserves recipe ID, locomotion hint, core instance/part, every attachment instance/part, parent instance, parent socket, child root socket, and connector part ID exactly.
  - The restored graph revalidates without regeneration or catalog mutation; malformed records are deterministically omitted/rejected.
  - `_build_run_snapshot(use_home_ship_summary=false)` serializes home-ship combat when away; `_build_world_snapshot()` syncs active derelict combat once. Load restores home and active combat once each, proven by distinct fingerprints.
  - After successful `save_load_service.save_world(ws)`, legacy `last_saved_snapshot` is populated from `_build_run_snapshot(away_from_start)`; failed saves never set it and the saved `WorldSnapshot` remains authoritative.
- Verification:
  - `biomass_revisit_persistence_smoke.gd` with home-vs-active fingerprints, failed-save/non-null-after-success assertions, and canonical recipe bytes.

## REQ-BIO-008: Exact eight-part candidate set

- Source: `features/procedural_biomass_assembly.md`, ADR-0058, ADR-0059
- Type: technical / asset governance
- Priority: must
- Status: Approved
- Rationale: The pilot set establishes a bounded contract before any candidate asset scale-up.
- Acceptance criteria:
  - The exact IDs are `biomass_human_arm_v1`, `biomass_insect_leg_v1`, `biomass_cephalopod_tentacle_v1`,
    `biomass_animal_skull_v1`, `biomass_humanoid_torso_v1`, `biomass_gunk_connector_v1`,
    `biomass_claw_v1`, and `biomass_maw_v1`.
  - Meshy remains candidate-only; no provider call, asset mutation, or automatic promotion occurs in this contract task.
- Verification:
  - Part catalog validator and ADR-0058 candidate-only gate review.

## REQ-BIO-009: Thirty composite runtime review captures

- Source: `features/procedural_biomass_assembly.md`, ADR-0059
- Type: technical / gameplay / visual review
- Priority: must
- Status: Approved
- Rationale: Composite low-poly cohesion and readability need coverage across all five movement families and all production lighting modes.
- Acceptance criteria:
  - Five recipes are reviewed at seeds `42` and `777` under `normal`, `emergency`, and `dark` lighting: exactly 30 composite captures.
  - All six 3D archetype pools remain covered during the singular-threat migration.
  - `biomass_visual_review.gd` uses production `scenes/main.tscn`, `IsoCameraRig`, `breach_field`, `SliceAtmosphereApplier`, and the exact validation seam; it does not create a neutral standalone camera/floor/environment.
  - `--visual-stage` is exactly `placeholder|final`, with separate fixed evidence roots; Task 8 runs placeholder only and Task 15 runs final. Each case records exact recipe node/triangle oracles, nodes `<=160`, triangles `<=24000`, finite AABB extents `0.05–20m`, collision/ray metrics, and frozen paired-camera readability values (RGB delta `>=8/255`, changed pixels `>=64`, changed bbox width/height `>=8px`).
  - Unexpected Godot `ERROR:`, `WARNING:`, or `SCRIPT ERROR:` output blocks acceptance.
- Verification:
  - Canonical `biomass_composite_review.py` manifest `run`/`verify`, protected-surface path+SHA snapshot, and manual inspection of all 30 captures.

## REQ-BIO-010: No auto-promotion or gameplay duplication

- Source: `features/procedural_biomass_assembly.md`, ADR-0058, ADR-0059
- Type: technical / governance
- Priority: must
- Status: Validated (Task 1 contract)
- Rationale: Visual candidates and catalog contracts must not bypass review or take ownership from Godot/runtime data.
- Acceptance criteria:
  - No provider calls or writes to `assets/imported`, exported GLBs, `scenes/wrappers`, or unrelated threat catalogs occur during catalog validation.
  - Promotion remains a separate human-reviewed action.
  - Collision, navigation, sockets/connectors, integrity, and gameplay bindings remain repository/Godot-owned.
  - `meshy_blender_validate.py` rejects recursively any GLB node extras key or string value containing case-insensitive `socket`, `marker`, `anchor`, `helper`, or `collision`; benign extras such as `{source:"meshy"}` and visual-only no-helper GLBs remain valid.
  - `BiomassAssembler` validates every instantiated placeholder/wrapper before accepting it and rejects/frees the whole assembly with stable diagnostics on failure.
- Verification:
  - Exact biomass validator CLI and focused tests.
  - `git diff -- assets/imported scenes/wrappers data/combat/threat_visual_catalog.json` remains empty during this task.

