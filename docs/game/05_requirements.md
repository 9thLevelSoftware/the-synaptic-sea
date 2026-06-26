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
