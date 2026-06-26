# Feature: Second Tool — Junction Calibrator

## Status

Approved for Alpha implementation

## Requirement cross-reference

- REQ-014 Alpha tool variety
- Extends REQ-007 Inventory/tool loop with a second distinct tool.
- Preserves REQ-011 Objective variation; the calibrator only modifies `repair_junction` step count and does not alter sequence advancement rules.
- Preserves REQ-012 Save/load run persistence; the calibrator is captured as an inventory tool id.

## Design pillar alignment

- Runtime systems over proof artifacts: the calibrator is a real pickup, a real inventory entry, and a real modifier to the objective-progress model.
- Every action has visible consequence: acquiring the calibrator updates the HUD; using it reduces the interaction count required for a repair-junction objective.
- Small vertical slices before broad systems: exactly one second tool and one effect for Alpha; no general tool-crafting, charges, or reusable consumables.

## Player fantasy

The player finds a compact diagnostic calibrator in a side compartment. When used on a damaged junction box, it shortcuts one step of the repair sequence, turning a tedious multi-step repair into a faster fix.

## Gameplay problem

REQ-007 added the first tool that modifies an environmental pressure. REQ-014 requires a second tool that proves the inventory loop can support meaningful player choice beyond hazard mitigation. The junction calibrator targets a different system — objective traversal — so the two tools do not overlap in function.

## Core behavior

- One additional tool exists for Alpha: `junction_calibrator`.
- The tool is acquired by interacting with a pickup placed in a valid tool-pickup room per template (fallback placement near a side corridor if the template does not define one).
- Once acquired, the calibrator stays in the player's inventory until it is consumed.
- When the player interacts with a `repair_junction` objective node and the calibrator is in inventory, the calibrator is consumed and the objective's required step count is reduced by one, with a minimum of one step remaining.
- The calibrator is consumed only if the reduction actually changes the required step count (a one-step junction does not consume it).
- The calibrator does not affect oxygen drain, fire state, route gates, extraction unlock, or non-`repair_junction` objectives.
- The calibrator is optional; the slice must remain completable without it.

## Inputs

- Player interaction event from the calibrator pickup interactable.
- Player interaction event from a `repair_junction` objective node.
- Current inventory state queried by the objective-progress model before completing a step.

## Outputs

- Inventory summary (`tool_ids`, `active_effects`).
- HUD status line `Tool: Junction Calibrator` when carried.
- Reduced `required_steps` on the affected `repair_junction` sequence.
- Calibrator pickup node is hidden/removed after acquisition.
- Calibrator removed from inventory after consumption.

## Rules

- A calibrator can be acquired at most once per slice run.
- The calibrator is single-use; it is removed from inventory when it modifies a `repair_junction` sequence.
- The reduction is applied before the first step of the affected junction is completed.
- The reduced step count is `max(1, original_required_steps - 1)`.
- The calibrator cannot be applied to an already-completed junction.
- The calibrator has no effect on `repair_junction` sequences that already have `required_steps == 1` and is not consumed in that case.
- If multiple `repair_junction` sequences exist, the player chooses which one receives the calibrator by interacting with it first.

## Non-goals

- No equipment UI, inventory grid, or drag-and-drop.
- No manual "use" input; the calibrator applies automatically on the first eligible `repair_junction` interaction.
- No tool durability, charges, or crafting.
- No dropping, trading, or hub-stored tools across runs.
- No tools that alter oxygen drain, fire state, route gates, extraction, or non-junction objectives.
- No audio, particle, or animation polish for the pickup.

## Technical design

- Reuse `InventoryState` from REQ-007. Add `junction_calibrator` to `data/tools/tool_definitions.json`:
  - `{ "junction_calibrator": { "display_name": "Junction Calibrator", "effect": { "type": "junction_step_reduction", "value": 1 } } }`.
- Extend `ObjectiveProgressState` (`scripts/systems/objective_progress_state.gd`):
  - Add `apply_junction_calibrator(sequence: int) -> bool`.
  - Returns `true` and reduces `required_steps` by one (min 1) if:
    - the sequence is registered with `objective_type == "repair_junction"`,
    - the sequence is not already complete,
    - `required_steps > 1`,
    - a calibrator has not already been applied to this sequence.
  - Stores an `calibrator_applied` flag in the sequence record so save/load restores the reduced step count.
  - Returns `false` without modifying state otherwise.
- Scene integration:
  - `PlayableGeneratedShip` owns the `InventoryState` instance and the calibrator pickup node.
  - When the player interacts with a `repair_junction` node, the coordinator calls `objective_progress_state.apply_junction_calibrator(sequence)` if `inventory_state.has_tool("junction_calibrator")`.
  - If the calibrator is applied, the coordinator calls `inventory_state.remove_tool("junction_calibrator")`, hides the pickup node if still visible, and refreshes the HUD.
  - The normal `complete_step()` flow then proceeds with the reduced `required_steps`.
- HUD: `objective_tracker.gd` appends the active tool status line when `inventory_state.get_status_lines()` is non-empty (already supported by REQ-007).
- Save/load (REQ-012): serializes `InventoryState.tool_ids` and the new `calibrator_applied` flag per `repair_junction` sequence as part of the current-run snapshot.
- Direct model smoke: `scripts/validation/junction_calibrator_state_smoke.gd`.
- Main-scene smoke: `scripts/validation/main_playable_slice_junction_calibrator_smoke.gd` loads the slice, acquires the calibrator, interacts with a `repair_junction` node, and asserts the reduced step count and consumed inventory state.

## Data model additions

- `InventoryState.tool_ids` may contain `"junction_calibrator"`.
- `ObjectiveProgressState` sequence record gains `calibrator_applied: bool`.
- `data/tools/tool_definitions.json` gains the `junction_calibrator` entry.
- Save/load snapshot includes the above fields through existing `apply_summary` / `get_summary` contracts.

## Trigger / preconditions / postconditions

- **Trigger:** Player interacts with the junction calibrator pickup.
- **Preconditions:**
  - Slice is loaded and `playable_ready` has fired.
  - Player is within interaction range of the pickup.
  - The calibrator is not already in inventory.
- **Postconditions:**
  - `InventoryState.has_tool("junction_calibrator")` is true.
  - Pickup node is hidden/queued for deletion.
  - HUD shows the active tool.

- **Trigger:** Player interacts with a `repair_junction` objective node while carrying the calibrator.
- **Preconditions:**
  - The sequence is registered as `repair_junction`.
  - The sequence is not complete.
  - `required_steps > 1`.
  - `InventoryState.has_tool("junction_calibrator")` is true.
- **Postconditions:**
  - `required_steps` is reduced by one.
  - `calibrator_applied` is true for the sequence.
  - The calibrator is removed from inventory.
  - HUD no longer shows the calibrator.

## Edge cases and failure modes

- **Double pickup:** Interacting again after acquisition is a no-op; the pickup node is already hidden.
- **Load with saved calibrator:** If REQ-012 load restores `"junction_calibrator"` in `tool_ids`, it behaves normally.
- **Load with saved `calibrator_applied`:** The reduced `required_steps` is restored; the player cannot re-apply a calibrator to that sequence.
- **No repair_junction in slice:** The calibrator has no effect but still appears in inventory and HUD until the run ends.
- **All junctions already one-step:** The calibrator cannot be consumed; it remains in inventory as a dead weight.
- **Calibrator applied to already-started junction:** If one step was already completed before the player acquires the calibrator, applying it still reduces `required_steps` by one (min 1), so the remaining interactions decrease. This is valid and does not require the reduction to happen before any steps.
- **Model tick order:** The calibrator check must run before `complete_step()` in the same interaction frame so the step count is current.

## Acceptance criteria

- Given a fresh slice load, when `inventory_state.get_summary()` is queried, then `tool_ids` does not contain `"junction_calibrator"`.
- Given the player is within range of the calibrator pickup, when the player interacts, then `has_tool("junction_calibrator")` returns true and the pickup node is no longer visible.
- Given the player carries the calibrator and interacts with a `repair_junction` sequence registered with `required_steps == 3`, when the interaction is processed, then `required_steps == 2`, the calibrator is removed from inventory, and the sequence completes after two total step completions.
- Given the player carries the calibrator and interacts with a `repair_junction` sequence registered with `required_steps == 1`, when the interaction is processed, then `required_steps` remains 1 and the calibrator remains in inventory.
- Given the player does not carry the calibrator and interacts with a `repair_junction` sequence registered with `required_steps == 3`, when the interaction is processed, then `required_steps` remains 3 and the sequence completes after three total step completions.
- Given the main playable slice loads, when the junction-calibrator main-scene smoke runs, then it prints `MAIN PLAYABLE JUNCTION CALIBRATOR PASS acquired=true required_steps=2 consumed=true`.
- Given the model smoke runs in isolation, when it adds the calibrator and applies it to a three-step repair junction, then it prints `JUNCTION CALIBRATOR STATE PASS required_steps=2 consumed=true`.
- Given the player carries the calibrator and the run is saved and reloaded, when the smoke waits one process_frame after load and then drives the actual seed template sequence 2 repair_junction through `_on_interactable_completed`, then the post-load interaction completes without crashing, `current_objective_sequence` advances to 3, sequence 2 is recorded `complete=true` with `required_steps=1` and `calibrator_applied=true`, the calibrator is no longer in inventory, and the pickup marker stays hidden — prints `MAIN PLAYABLE JUNCTION CALIBRATOR SAVE LOAD PASS carried_load=true consumed_load=true next_frame_interaction=true`.
- Given the player has consumed the calibrator on sequence 2 and the run is saved and reloaded, when the smoke waits one process_frame after load, then the carried / consumed-applied state is fully restored (inventory empty, sequence 2 `complete=true` / `calibrator_applied=true` / `required_steps=1`, pickup marker hidden, and a post-load interaction on the rebuilt HUD/tracker path does not crash on the previously-freed `tracker` reference).

## Validation

- Direct model smoke:
  ```bash
  /Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-synaptic-sea-of-stars --script res://scripts/validation/junction_calibrator_state_smoke.gd
  ```
  Expected marker: `JUNCTION CALIBRATOR STATE PASS required_steps=2 consumed=true`

- Main-scene smoke:
  ```bash
  /Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-synaptic-sea-of-stars --script res://scripts/validation/main_playable_slice_junction_calibrator_smoke.gd
  ```
  Expected marker: `MAIN PLAYABLE JUNCTION CALIBRATOR PASS acquired=true required_steps=2 consumed=true`

- Save/load smoke (REQ-014 review-t_80dcea4b follow-up):
  ```bash
  /Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-synaptic-sea-of-stars --script res://scripts/validation/main_playable_slice_junction_calibrator_save_load_smoke.gd
  ```
  Expected marker: `MAIN PLAYABLE JUNCTION CALIBRATOR SAVE LOAD PASS carried_load=true consumed_load=true next_frame_interaction=true`

- Regression inclusion: add both smokes to the bundle in `docs/game/06_validation_plan.md` before the feature is marked done.

## Risks

- Risk: the pickup placement is not readable and players miss it. Mitigation: place it in a side room on the critical path and add a Label3D marker `TOOL PICKUP`; assert visibility in the main-scene smoke.
- Risk: calibrator makes every repair_junction trivial. Mitigation: single-use consumption and a minimum of one remaining step preserve the core interaction; place only one calibrator per run.
- Risk: inventory model and objective-progress model form a tight coupling. Mitigation: `ObjectiveProgressState` only checks an inventory boolean passed by the coordinator; it does not own `InventoryState`.
- Risk: tool data model decisions become ad-hoc. Mitigation: author ADR-0004 (Inventory/Tool Data Model) before implementation if the implementation worker wants to generalize beyond the existing `tool_definitions.json` plus conditional branches.

## ADRs

- `docs/game/adr/0001-adopt-stage-gate-kanban-godot-validation.md`
- ADR-0004 recommended if the implementation generalizes the tool/effect system beyond the current `tool_definitions.json` plus per-tool conditional branches.
