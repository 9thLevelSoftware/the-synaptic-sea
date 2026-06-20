# ADR-0007: Save/Load Service Scope — Current Run Only

## Status

Accepted

## Context

REQ-012 (`docs/game/features/save_load.md`) calls for current-run persistence so a Gate 2 derelict expedition can be suspended and resumed. Gate 2 is scoped under ADR-0003 Option A, which defers hub/meta progression through Gate 2 and limits Gate 2 save/load to run/ship-slice persistence unless a Gate 3 hub/meta decision explicitly expands it.

Without a scope boundary, the first save/load implementation could accidentally persist hub-level state (derelict selection, persistent unlocks, meta-currency, faction/narrative progress, or cross-run bookkeeping). That would violate ADR-0003 and re-open scope before Gate 3 planning. A dedicated ADR is required to fix the boundary before implementation.

## Decision

Adopt a **current-run-only, single-slot save/load service** scoped to the active ship slice.

### In scope

- Serialize and deserialize runtime state that exists only for the active ship slice:
  - Player position (`Vector3`) inside the current slice.
  - Current objective sequence (`current_objective_sequence`).
  - Ship-system state summary (`ShipSystemState`).
  - Route-control state summary (`RouteControlState`).
  - Oxygen state summary (`OxygenState`).
  - Inventory/tool state summary (`InventoryState`) produced by REQ-007.
  - Fire hazard state summary (`FireState`) produced by REQ-010.
  - Objective-progress state summary (`ObjectiveProgressState`) produced by REQ-011.
- One save slot per run at `user://saves/current_run.json`.
- Auto-save on objective completion.
- Manual save/load input actions (`save_run`, `load_run`).
- Version markers (`slice_version`, `godot_version`) that reject incompatible saves.
- Save deletion when the run completes (reactor stabilized / extraction unlocked).

### Explicitly out of scope

- Hub ship scene/UI state.
- Derelict selection, queueing, or seed history.
- Persistent meta-currency, unlocks, faction/narrative progress, or cross-run achievements.
- Multiple named save slots, quicksaves, or save-scumming.
- Cloud, Steam, or cross-device sync.
- Save-file encryption or compression in Gate 2.
- Mid-animation or mid-physics state preservation.
- Scene nodes, props, VFX, audio state, or camera zoom.

### Architecture contract

- `SaveLoadService` is a `RefCounted` service owned by `PlayableGeneratedShip`, not an autoload.
- `RunSnapshot` is a pure data class that holds only the in-scope fields listed above.
- Every persisted runtime model exposes:
  - `get_summary() -> Dictionary` (already required by existing models).
  - `apply_summary(summary: Dictionary) -> bool` (new contract for Gate 2 models).
- `PlayableGeneratedShip` coordinates snapshot capture and application; it does not allow models to read the file directly.
- Load reconstructs the slice via the normal `_ready` path, then applies model summaries before the first `_process` tick.

## Consequences

Positive:

- Prevents accidental hub/meta persistence by documenting the cut line in an ADR.
- Gives REQ-012 implementation a bounded, single-slot design that can later be wrapped by a hub-level save manager without migration of the core service.
- Keeps save/load testing focused on round-trip state fidelity rather than cross-run economy.

Negative / tradeoffs:

- Starting a new run overwrites the previous slot; players cannot keep multiple expediments in progress.
- Save data is local and unencrypted; expanding to cloud/encrypted saves will require a future ADR.
- Hub-level persistence will need its own snapshot and service later; some naming conventions may need to change when that layer is added.

Mitigations:

- Code-review checklist for any PR touching `RunSnapshot` or `SaveLoadService` must confirm no hub/meta fields are added.
- `RunSnapshot` fields are enumerated explicitly in the feature spec and this ADR; adding a field requires ADR review.
- Save-file deletion on run completion prevents stale slice data from leaking into the next run.

## Affected documents

- `docs/game/features/save_load.md` — ADR-0007 is cited as the scope authority.
- `docs/game/05_requirements.md` — REQ-012 acceptance criteria reference the current-run-only boundary.
- `docs/game/adr/0003-reaffirm-hub-meta-deferral-through-gate-2.md` — ADR-0007 operationalizes the save/load limit in ADR-0003 line 31.
- `docs/game/06_validation_plan.md` — regression bundle includes save/load smokes before completion.

## Verification

- `docs/game/adr/0007-save-load-service-scope.md` exists and is Accepted.
- `RunSnapshot` source contains no hub/meta fields (manual review + grep for `hub_`, `meta_`, `unlock_`, `faction_`, `currency_`).
- Save/load smokes pass and the regression bundle includes them.
- `PlayableGeneratedShip` deletes `user://saves/current_run.json` on `playable_slice_completed`.
