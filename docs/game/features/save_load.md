# Feature: Save / Load Run Persistence

## Status

Approved for Gate 2 implementation

## Requirement cross-reference

- REQ-012 Save/load run persistence (new Gate 2 requirement)
- Current-run only; explicitly excludes REQ-008/REQ-009 hub/meta persistence.
- Preserves REQ-001..003 (route gate, system, and extraction state restore correctly), REQ-006/REQ-007/REQ-010/REQ-011 (hazard, tool, fire, and objective-progress state restore correctly).

## Design pillar alignment

- Runtime systems over proof artifacts: save/load is a real service that writes and reads runtime state, not a proof-of-concept file dump.
- Small vertical slices before broad systems: one save slot per run, auto-save on objective completion, manual save/load input optional; no hub meta-currency, no cross-run unlocks, no cloud saves.

## Player fantasy

The player can suspend and resume an expedition. The ship state, tool inventory, and current objective are restored exactly as left.

## Gameplay problem

Gate 1 ends when the slice completes or the process exits; there is no way to preserve progress mid-run. Gate 2 needs current-run persistence so a 5-minute derelict run can be interrupted and resumed.

## Core behavior

- One save slot per run: `user://saves/current_run.json`.
- Auto-save triggers after every objective completion.
- Manual save is available via an input action (`save_run`, bound to `F5` by default) when the slice is active.
- Manual load is available from the title/main menu or via an input action (`load_run`, bound to `F9`) when no slice is active.
- Loading reconstructs the same ship slice, restores pure model state, teleports the player to the saved position, and resumes at the saved objective sequence.
- The save file is deleted when the run completes (reactor stabilized / extraction unlocked) to prevent stale resumes.
- Cross-run persistence is out of scope: starting a new run overwrites the slot; no hub ship state, no meta-currency, no unlocks are saved.

## Inputs

- Save trigger (auto on objective completion, manual on input).
- Load trigger (menu selection or manual input).
- Runtime state from `PlayableGeneratedShip` and its owned models.

## Outputs

- `user://saves/current_run.json` written or read.
- Load result event: success or failure reason.
- Restored player position, objective sequence, and all model summaries.

## Rules

- Save captures only current-run state: ship layout identifiers, player transform, objective sequence, and model summaries.
- Save does not capture scene nodes, props, VFX, audio state, or camera zoom.
- Load must reject a save file whose `slice_version` or `godot_version` does not match; failure prints a clear reason and starts a fresh run.
- Load restores model state before the first `_process` tick so the resumed run is deterministic from the saved frame.
- If a save file is missing or corrupt, the load action starts a fresh run and logs a warning.
- Auto-save on objective completion runs only if the completion succeeded (i.e., not during validation-only forced completions unless explicitly requested).

## Non-goals

- No hub ship state, derelict selection state, meta-currency, unlocks, or faction progress.
- No multiple named save slots, quicksaves, or save-scumming support.
- No cloud, Steam, or cross-device sync.
- No save-file encryption or compression in Gate 2.
- No mid-animation or mid-physics state preservation.
- No save/load during real-time hazard transitions; auto-save fires at stable objective-completion boundaries.

## Technical design

- New service: `scripts/systems/save_load_service.gd` (`SaveLoadService` extending `RefCounted`).
  - Owned by `PlayableGeneratedShip`, not an autoload.
  - Inputs:
    - `save_current_run(ctx: RunSnapshot) -> bool`
    - `load_current_run() -> RunSnapshot` (returns null/empty on failure)
    - `delete_current_run() -> bool`
  - File path: `user://saves/current_run.json`.
  - Uses `FileAccess` and `JSON.stringify` / `JSON.parse_string`.
- New pure data class: `scripts/systems/run_snapshot.gd` (`RunSnapshot` extending `RefCounted` or `Resource`).
  - Fields: `layout_path`, `kit_path`, `gameplay_slice_path`, `player_position` (Vector3 array), `current_objective_sequence`, `ship_systems_summary`, `route_control_summary`, `oxygen_summary`, `inventory_summary`, `fire_summary`, `objective_progress_summary`, `slice_version`, `godot_version`, `saved_at`.
- Coordinator changes in `scripts/procgen/playable_generated_ship.gd`:
  - After each objective completion, build a `RunSnapshot` and call `save_load_service.save_current_run()`.
  - Expose `request_save()` and `request_load()` methods for manual triggers.
  - On load, re-run `_ready` with saved paths, then apply the snapshot to each model before spawning the player.
- Model support:
  - `ShipSystemState` adds `apply_summary(summary: Dictionary) -> void` (or constructor from summary).
  - `RouteControlState` adds `apply_summary(summary: Dictionary) -> void`.
  - `OxygenState` adds `apply_summary(summary: Dictionary) -> void`.
  - `InventoryState` adds `apply_summary(summary: Dictionary) -> void`.
  - `FireState` adds `apply_summary(summary: Dictionary) -> void`.
  - `ObjectiveProgressState` adds `apply_summary(summary: Dictionary) -> void`.
- Direct model smoke: `scripts/validation/save_load_service_smoke.gd` creates a snapshot, writes it, reads it back, and asserts all summaries round-trip.
- Main-scene smoke: `scripts/validation/main_playable_slice_save_load_smoke.gd` loads the slice, completes objective 1, saves, reloads, and asserts the player position, sequence, and ship-system flags match the saved frame.

## Data model additions

- `RunSnapshot` data class.
- `SaveLoadService` service class.
- `apply_summary()` methods on all Gate 2 runtime models.
- New input actions `save_run` and `load_run` registered in `PlayableGeneratedShip.ensure_default_input_actions()`.

## Trigger / preconditions / postconditions

- **Trigger (auto-save):** `PlayableGeneratedShip` emits `playable_interaction_completed` for an objective that advances `current_objective_sequence`.
- **Trigger (manual save):** Player presses the `save_run` input while a slice is active.
- **Trigger (load):** Player selects "Resume Run" from the main menu or presses `load_run` from a no-slice state.
- **Preconditions for save:**
  - `PlayableGeneratedShip` has fired `playable_ready`.
  - The run is not already complete (`slice_complete == false`).
- **Postconditions for save:**
  - `user://saves/current_run.json` exists and contains a valid `RunSnapshot`.
  - All model summaries and player position are captured.
- **Preconditions for load:**
  - A compatible save file exists.
- **Postconditions for load:**
  - The same slice is reconstructed.
  - All model summaries are applied before the first tick.
  - Player is teleported to the saved position.
  - `current_objective_sequence` matches the save.

## Edge cases and failure modes

- **Missing save file:** `load_current_run()` returns an empty snapshot; the caller starts a fresh run.
  - Smoke asserts this path does not crash.
- **Corrupt JSON:** Caught by `JSON.parse_string` returning null; service logs and returns empty snapshot.
- **Version mismatch:** `slice_version` or `godot_version` differs; service rejects load and returns empty snapshot.
- **Saved model state references unknown zone/tool:** Gracefully ignored by `apply_summary()` (e.g., unknown tool id is added but has no effect; unknown fire zone id is dropped).
- **Load while a slice is already running:** Unload the current slice first, then load; if unload fails, load is rejected.
- **Headless smoke cleanup:** Smokes delete `user://saves/current_run.json` before and after running so they do not pollute the user's real save slot.
- **Save during zero-oxygen passability block:** Captures oxygen value and passability state; on load the player is still blocked until oxygen recovers.

## Acceptance criteria

- Given a fresh slice, when objective 1 completes, then `user://saves/current_run.json` exists and contains `current_objective_sequence == 2`.
- Given a saved run, when `SaveLoadService.load_current_run()` is called, then the returned `RunSnapshot` matches the saved values for player position, sequence, and all model summaries.
- Given a saved run, when the main-scene load smoke reloads the slice, then the player position matches within `0.01` units, `current_objective_sequence` matches, and `ship_systems.emergency_supplies_recovered == true`.
- Given a run where the reactor is stabilized, when extraction unlocks, then the save file is deleted.
- Given a corrupt save file, when load is requested, then the service returns an empty snapshot and logs a clear reason.
- Given the model smoke runs in isolation, when it writes and reads a snapshot, then it prints `SAVE LOAD SERVICE PASS round_trip=true version_match=true summaries=6`.
- Given the main playable slice load, when the save/load smoke runs, then it prints `MAIN PLAYABLE SAVE LOAD PASS saved_sequence=2 loaded_sequence=2 position_match=true supplies=true`.

## Validation

- Direct model smoke:
  ```bash
  /Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-synapse-sea-of-stars --script res://scripts/validation/save_load_service_smoke.gd
  ```
  Expected marker: `SAVE LOAD SERVICE PASS round_trip=true version_match=true summaries=6`

- Main-scene smoke:
  ```bash
  /Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-synapse-sea-of-stars --script res://scripts/validation/main_playable_slice_save_load_smoke.gd
  ```
  Expected marker: `MAIN PLAYABLE SAVE LOAD PASS saved_sequence=2 loaded_sequence=2 position_match=true supplies=true`

- Regression inclusion: add both smokes to the bundle in `docs/game/06_validation_plan.md` before the feature is marked done.

## Risks

- Risk: save/load becomes a vector for hub/meta persistence by accident. Mitigation: `RunSnapshot` explicitly excludes hub fields; code review checklist checks for any hub/meta data in the snapshot.
- Risk: model summaries drift out of sync with `apply_summary()` methods. Mitigation: each model smoke asserts round-trip; if a new field is added to `get_summary()` without a matching loader, the smoke fails.
- Risk: `user://` path differs between editor and exported builds. Mitigation: always use `user://saves/current_run.json` via `ProjectSettings`; never hard-code an absolute path.
- Risk: loading from a snapshot skips initialization side effects (e.g., route gate scene nodes). Mitigation: load path re-uses the normal `_ready` flow and only applies model summaries after scene nodes are built.

## ADRs

- `docs/game/adr/0001-adopt-stage-gate-kanban-godot-validation.md`
- ADR-0007 required before implementation: `docs/game/adr/0007-save-load-service-scope.md` records the current-run-only boundary, the single-slot design, the model-summary contract, and the explicit exclusion of hub/meta state. **Status: Accepted.**
