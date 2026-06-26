# Feature: Hazards — Depleting Oxygen Pressure Loop

## Status

Validated for the Gate 1 runtime slice

## Design pillar alignment

- Spatial coherence first: the hazard occupies a room the player can already read; its state changes how that room reads (safe vs unsafe marker on the locked-isometric view).
- Runtime systems over proof artifacts: oxygen is a live resource value, breach zones affect passability and HUD, repair toggles actual state — not a cosmetic overlay.
- Every action has visible consequence: HUD oxygen line, room unsafe marker, and a fail state (player blocked from objective 4 area) all reflect model state.
- Small vertical slices before broad systems: one hazard type (oxygen pressure) on the existing main playable slice before adding fire, vacuum, radiation, or enemy pressure.

## Player fantasy

The player is aboard a derelict whose hull integrity is failing. Air is leaking. The player has to keep moving, reach objectives, and complete repairs before the atmosphere drains — every minute spent in a breached room costs air, and a fully drained suit locks the player out of the extraction corridor.

## Gameplay problem

Before this feature, `docs/game/02_core_loop.md` listed "Hazard/survival pressure is not yet a real runtime loop" as a Gate 1 exit gap. The slice only had restoration progression; there was no time or resource that forced a moment-to-moment decision. Without pressure, the route/system loop could be cleared at the player's leisure and the slice could not demonstrate the 60–120 second "fun to navigate" target.

## Core behavior

A single ship-scale hazard: a depleting oxygen reserve that drains while the player is inside any breach zone and recovers slowly outside them. One breach zone exists in the main playable slice (the corridor between objective 3 and objective 4, the path the player must cross to reach reactor stabilization). The hazard interacts with the existing route-control and ship-system systems:

- The breach is "open" on slice load. While open, oxygen drains whenever the player occupies the breach zone.
- Completing objective 2 (main power restored, per `features/route_control.md`) seals the breach and stops the drain in that zone.
- Completing objective 4 (reactor stabilization) does not affect the breach; oxygen is a survival pressure, not a route-control gate.
- If oxygen reaches zero, the player is moved out of passability through the breach zone: the segment is treated as collision-blocked until oxygen recovers above a recovery threshold (player returns to a sealed/safe room and waits).
- Oxygen regenerates at a fixed rate while the player is not in any breach zone; passability re-opens once oxygen recovers above the recovery threshold.

The hazard is intentionally narrow: one resource, one breach zone, one seal action tied to existing objective 2. It is a pressure loop, not a content suite.

## Inputs

- Generated ship data with at least one breach-zone marker (new data field on the loader output; falls back to a hard-coded zone id if the data is missing so existing slices still validate).
- Player position updates from `scripts/player/player_controller.gd`.
- Ship-system summary from `scripts/systems/ship_system_state.gd` (specifically `main_power_restored`, set true by objective 2).
- Slice time elapsed (from the main scene tree tick).

## Outputs

- Oxygen resource value visible in HUD as a numeric line (`Oxygen: 87` / `Oxygen: 12 LOW`).
- Room unsafe marker visible on the locked-isometric view when the player is inside an unsealed breach zone.
- Passability toggle on the breach zone's collision segment (enabled when oxygen is at or below recovery threshold, disabled when oxygen is above the safe threshold).
- Hazard summary exposed for the validation smoke (`oxygen`, `breach_open`, `breach_sealed`, `passability_blocked`, `recovery_threshold`).
- Failure state when oxygen is at zero: HUD line reads `Oxygen: 0 BREACH BLOCKED` and the slice cannot complete objectives 3 or 4 until oxygen recovers.

## Rules

- One oxygen resource, one breach zone, one seal action per slice run.
- Oxygen drains at a fixed rate when the player is inside an unsealed breach zone; never drains when sealed or outside any breach zone.
- Oxygen regenerates only when the player is outside any breach zone; passability re-opens once oxygen recovers above the recovery threshold.
- Sealing the breach (objective 2) is permanent for the current slice run.
- A zero-oxygen state blocks forward traversal through the breach zone by collision, not by deleting the node.
- The hazard does not affect route-gate state, extraction unlock, or objective sequence numbering. It runs in parallel.

## Non-goals

- No oxygen tanks, pickups, or inventory items (out of scope until REQ-007 ships).
- No multiple hazard types (fire, radiation, vacuum) in this slice.
- No hazard UI beyond a single HUD numeric line plus the existing locked-isometric room marker.
- No procedural breach placement per run; the breach zone is fixed to the objective 3 → objective 4 corridor for Gate 1.
- No damage-over-time on the player avatar in this slice; the fail state is passability-block, not health depletion.
- No audio cues, no particle VFX, no animation polish.
- No enemy/NPC pressure; hazards remain environmental only.
- No save/load of hazard state within a slice.

## Technical design

- Pure model: `scripts/systems/oxygen_state.gd` (`OxygenState` extending `RefCounted`), following the `RouteControlState` pattern.
  - Inputs: `configure(breach_zone_ids: Array, drain_rate: float, regen_rate: float, recovery_threshold: float, max_oxygen: float)`, `tick(delta_seconds: float, player_in_breach_zone: bool)`, `seal_breach(zone_id: String)`, `is_passability_blocked()`.
  - Outputs: `get_summary() -> Dictionary`, `get_status_lines() -> PackedStringArray`.
- Scene integration: `scripts/procgen/playable_generated_ship.gd` adds an `OxygenState` instance, calls `tick()` from `_process`, feeds player position from the existing player controller, and toggles collision on the breach-zone segment using the same pattern as `RouteControlState` gate open/close.
- Loader contract: `scripts/procgen/generated_ship_loader.gd` gains an optional `breach_zones` array on its output. Missing/null is treated as an empty array; the spec's required breach zone is then injected by the scene coordinator from a fixed list so existing procedural data still validates.
- Direct model smoke: `scripts/validation/oxygen_state_smoke.gd` exercises the model in isolation.
- Main-scene smoke: `scripts/validation/main_playable_slice_hazard_smoke.gd` loads the main playable slice, simulates player crossing the breach zone, and asserts the hazard summary, HUD line source, and passability toggle.
- Documentation updates: `docs/game/02_core_loop.md` "Current implemented loop evidence" gains a hazard-pressure row; "Loop gaps to resolve before Gate 1 exit" loses the hazard/survival pressure line.
- No ADR required for this slice: the model mirrors `RouteControlState` and the scene integration reuses the existing route-control collision-toggle pattern. An ADR for hazard architecture generally is listed in `docs/game/04_tdd.md` and will be authored when the second hazard type lands.

## Acceptance criteria

- Given a fresh slice load, when the player spawns in the entry room, then oxygen starts at `max_oxygen` and the breach zone reports `breach_open=true`.
- Given the player enters the unsealed breach zone, when a tick advances, then oxygen decreases by `drain_rate * delta` and the HUD line reflects the new value.
- Given the player exits the breach zone, when subsequent ticks advance, then oxygen regenerates by `regen_rate * delta` until `max_oxygen`.
- Given objective 2 completes (`main_power_restored`), when the model receives the ship-system summary, then the breach zone is sealed and oxygen no longer drains when the player is inside it.
- Given oxygen drops to zero, when the player tries to traverse the breach zone, then passability is blocked (collision enabled on the segment) and HUD reads `Oxygen: 0 BREACH BLOCKED`.
- Given the player returns to a sealed/safe room with oxygen at zero, when ticks advance, then oxygen recovers above `recovery_threshold` and passability re-opens.
- Given the model is queried directly, when `get_summary()` is called, then the result includes `oxygen`, `breach_open`, `breach_sealed`, `passability_blocked`, and `recovery_threshold` keys.
- Given the main playable slice loads, when the hazard main-scene smoke runs, then it prints a `MAIN PLAYABLE HAZARD PASS oxygen=... breach_open=false breach_sealed=true passability_blocked=false` marker.

## Validation

- `scripts/validation/oxygen_state_smoke.gd` — model-only smoke.
- `scripts/validation/main_playable_slice_hazard_smoke.gd` — scene consequence smoke.
- Both are part of the regression bundle in `docs/game/06_validation_plan.md`.
- Verification commands:
  ```
  /Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-synapse-sea-of-stars --script res://scripts/validation/oxygen_state_smoke.gd
  /Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-synapse-sea-of-stars --script res://scripts/validation/main_playable_slice_hazard_smoke.gd
  ```
- Expected model-smoke marker: `OXYGEN STATE PASS oxygen=... breach_open=false breach_sealed=true passability_blocked=false recovery_threshold=...`
- Expected main-smoke marker: `MAIN PLAYABLE HAZARD PASS oxygen=... breach_open=false breach_sealed=true passability_blocked=false`

## Risks

- Risk: oxygen drain rate is tuned too aggressively and turns the slice into a frustrated run instead of a pressure run. Mitigation: keep drain/regen/recovery values on a single `OxygenTuning` Resource so they can be adjusted without code changes; record chosen values in the hazard smoke output.
- Risk: hazard model and ship-system model race on the same tick and report inconsistent state. Mitigation: the scene coordinator applies ship-system summary first, then ticks oxygen, matching the existing route-control integration order.
- Risk: the breach zone's collision toggle is misinterpreted as a route-gate state change. Mitigation: `OxygenState` lives in its own model and emits its own summary; route-control summary is unchanged by hazard state.
- Risk: hazard pressure turns out to be too thin to satisfy the Gate 1 exit criterion "at least one risk/pressure loop". Mitigation: keep this slice as the minimum, and track a follow-up card for the second hazard type before Gate 1 exit; Gate 1 does not require multiple hazard types.

## ADRs

- `docs/game/adr/0001-adopt-stage-gate-kanban-godot-validation.md` (governs how this spec is implemented and validated).
- No new ADR for this slice; the hazard architecture decision is deferred until a second hazard type is specified (per `docs/game/04_tdd.md`).