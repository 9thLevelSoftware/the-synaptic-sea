# Feature: Objective Variation — Multi-Step Repair Junction

## Status

Approved for Gate 2 implementation

## Requirement cross-reference

- REQ-011 Objective variation (new Gate 2 requirement)
- Preserves REQ-001 (route gates remain runtime blockers), REQ-002 (objective 2 still restores power and opens gates), REQ-003 (objective 4 still unlocks extraction), REQ-004 (model + scene validation), and REQ-006/REQ-007 (hazard/tool loops unchanged).

## Design pillar alignment

- Runtime systems over proof artifacts: the multi-step objective changes how the player completes a sequence slot, not just HUD text.
- Every action has visible consequence: each junction interaction updates local markers and the objective tracker; completing the set advances ship-system state.
- Small vertical slices before broad systems: exactly one new objective type and one multi-step slot for Gate 2; no full procedural objective generator.

## Player fantasy

A junction box has two damaged couplings. The player must repair both before the system comes back online, turning a single "press button" objective into a short spatial task inside one room.

## Gameplay problem

All current objectives are single interactions with identical verb usage. Gate 2 needs at least one different objective shape to prove the objective pipeline supports variation without breaking sequence-dependent systems like route control and extraction.

## Core behavior

- One new objective type is added for Gate 2: `repair_junction`.
- A `repair_junction` objective occupies a single sequence slot but requires exactly two interactions in the same room to complete.
- The two interactions are represented by two `Interactable` nodes: `junction_primary` and `junction_secondary`.
- Both interactions must be completed before `ShipSystemState.apply_objective()` is called for that sequence.
- The objective tracker shows progress as `Repair junction (1/2)` then `Repair junction (2/2)`.
- Only after the second interaction does the ship-system state advance and route/extraction behavior update per existing rules.
- Gate 2 places exactly one `repair_junction` slot, replacing the objective at sequence 2 (`restore_systems`) or sequence 3 (`download_logs`) in the default slice. The chosen sequence remains a power/logs milestone so REQ-002/REQ-003 are preserved.

## Inputs

- Generated ship objective data with `type == "repair_junction"`.
- A list of `steps` in the objective data (Gate 2 requires exactly 2).
- Player interaction events on each step interactable.
- Existing ship-system summary to avoid double-applying the sequence.

## Outputs

- Objective tracker text updates per step.
- Local interaction markers turn completed/disabled per step.
- `ShipSystemState.apply_objective()` fires once after the last step.
- Route gates open / extraction unlocks exactly as they do today.

## Rules

- A `repair_junction` slot must define at least 2 and at most 4 steps; Gate 2 uses 2.
- Steps within a slot are unordered; completing either first counts as step 1.
- Steps are independent interactables in the same room.
- The sequence number does not advance until all steps are completed.
- `ShipSystemState.apply_objective()` receives the same `objective_type` string used by the existing single-step type that the junction replaces (e.g., `"restore_systems"` if replacing sequence 2), so route-control and extraction logic need no changes.
- If a saved run (REQ-012) is loaded mid-junction, completed steps stay completed and incomplete steps remain available.

## Non-goals

- No fully procedural objective generation in Gate 2.
- No new ship-system flags or effects beyond the existing power/logs/reactor flags.
- No failure state for the repair (e.g., no timer, no wrong-order penalty).
- No audio, animation, or VFX for the junction couplings.
- No branching objective trees or optional alternate sequences.

## Technical design

- New pure model: `scripts/systems/objective_progress_state.gd` (`ObjectiveProgressState` extending `RefCounted`).
  - Tracks per-sequence step completion.
  - Inputs: `register_objective(sequence: int, objective_type: String, required_steps: int)`, `complete_step(sequence: int) -> bool`, `is_sequence_complete(sequence: int) -> bool`, `get_step_progress(sequence: int) -> Dictionary`.
  - Outputs: `get_summary() -> Dictionary`.
- Loader contract: `generated_ship_loader.gd` objective parsing accepts an optional `steps` array on an objective. Missing or empty means 1 step (backward compatible). Each step has an `approach_cell` and optional `step_id`.
- Coordinator changes in `scripts/procgen/playable_generated_ship.gd`:
  - After building interactables, group them by sequence.
  - For a sequence with `required_steps > 1`, wire all step interactables to a shared completion handler that increments `ObjectiveProgressState` and only advances `current_objective_sequence` after the last step.
  - The objective tracker receives per-step progress text from `ObjectiveProgressState`.
- `ShipSystemState.apply_objective()` continues to be called once per sequence, preserving the existing route-control integration.
- Direct model smoke: `scripts/validation/objective_progress_state_smoke.gd` registers a 2-step junction, completes steps out of order, and asserts the sequence completes only after both.
- Main-scene smoke: `scripts/validation/main_playable_slice_objective_variation_smoke.gd` loads the slice, completes both junction steps, and asserts the sequence advances and route control / extraction behave as expected.

## Data model additions

- `ObjectiveProgressState` instance owned by `PlayableGeneratedShip`.
- Objective spec format extension:
  ```json
  {
    "id": "junction_alpha",
    "sequence": 2,
    "type": "restore_systems",
    "kind": "repair_junction",
    "room_id": "reactor_prep",
    "steps": [
      { "step_id": "primary_coupling", "approach_cell": [4, 2, 0] },
      { "step_id": "secondary_coupling", "approach_cell": [5, 2, 0] }
    ]
  }
  ```
  - `type` maps to the ship-system effect; `kind` distinguishes multi-step handling.
- Save/load (REQ-012) serializes completed step ids per sequence.

## Trigger / preconditions / postconditions

- **Trigger:** Player interacts with a `repair_junction` step interactable.
- **Preconditions:**
  - The sequence is the current objective.
  - The step interactable is active and not already completed.
- **Postconditions:**
  - `ObjectiveProgressState.complete_step(sequence)` records the step.
  - If this was the last uncompleted step, `current_objective_sequence` increments and `ShipSystemState.apply_objective()` runs with the objective type.
  - If more steps remain, the objective tracker shows the updated progress text.

## Edge cases and failure modes

- **Single-step objective:** Objectives without `steps` remain single interactions; no behavior change for existing sequences.
- **All steps already completed:** Interacting with a completed step is a no-op.
- **Steps completed out of order:** Allowed; progress text updates to `x / total` regardless of order.
- **Save/load mid-junction:** On load, completed steps are restored and the current sequence remains pinned until remaining steps finish.
- **Duplicate step ids within a sequence:** `ObjectiveProgressState` treats them as the same step; loader validation should reject duplicates, but the model is idempotent.
- **Missing step approach_cell:** The loader falls back to the objective's main `approach_cell` for any missing step position.

## Acceptance criteria

- Given a fresh slice load, when `ObjectiveProgressState.get_summary()` is queried for a 2-step junction, then `required_steps == 2` and `completed_steps == 0`.
- Given the player completes one step of a 2-step junction, when the summary is queried, then `completed_steps == 1` and `current_objective_sequence` has not advanced.
- Given the player completes the second step, when the completion handler runs, then `current_objective_sequence` increments and `ShipSystemState.apply_objective()` has been called exactly once.
- Given the main playable slice loads with a `repair_junction` at sequence 2, when the objective-variation smoke runs, then it prints `MAIN PLAYABLE OBJECTIVE VARIATION PASS sequence=2 steps=2 complete=true power_restored=true gates_opened=true`.
- Given the model smoke runs in isolation, when it completes steps out of order, then it prints `OBJECTIVE PROGRESS STATE PASS sequence=2 required=2 completed=2 applied_once=true`.

## Validation

- Direct model smoke:
  ```bash
  /Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-synapse-sea-of-stars --script res://scripts/validation/objective_progress_state_smoke.gd
  ```
  Expected marker: `OBJECTIVE PROGRESS STATE PASS sequence=2 required=2 completed=2 applied_once=true`

- Main-scene smoke:
  ```bash
  /Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-synapse-sea-of-stars --script res://scripts/validation/main_playable_slice_objective_variation_smoke.gd
  ```
  Expected marker: `MAIN PLAYABLE OBJECTIVE VARIATION PASS sequence=2 steps=2 complete=true power_restored=true gates_opened=true`

- Regression inclusion: add both smokes to the bundle in `docs/game/06_validation_plan.md` before the feature is marked done.

## Risks

- Risk: multi-step objectives confuse the player if the HUD does not clearly show progress. Mitigation: tracker shows `Repair junction (1/2)` and both step markers remain visible until completion.
- Risk: out-of-order step completion breaks narrative framing. Mitigation: steps are identical couplings; no order dependency in Gate 2.
- Risk: changes to the coordinator accidentally break single-step objectives. Mitigation: model smoke covers single-step backward compatibility; existing completion smoke must continue to pass.
- Risk: the `kind`/`type` split is confusing. Mitigation: `type` stays the ship-system effect name (existing contract); `kind` is only added for multi-step layout.

## ADRs

- `docs/game/adr/0001-adopt-stage-gate-kanban-godot-validation.md`
- No new ADR required for one multi-step type; if Gate 3 expands to a generalized objective graph, author ADR-0006 (Objective Graph Architecture) then.
