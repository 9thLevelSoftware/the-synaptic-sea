# Feature: Hazard Type 3 — Electrical Arc Doorway

## Status

Approved for Alpha implementation

## Requirement cross-reference

- REQ-013 Alpha hazard variety
- Extends REQ-006 Hazard pressure loop and REQ-010 Hazard variety without changing oxygen or fire semantics.
- Preserves REQ-001..003 and REQ-007 (the arc zone does not depend on tools in Alpha; tools do not affect it).

## Design pillar alignment

- Spatial coherence first: the arc occupies a single readable doorway or short corridor and changes its read state between `DISCHARGED` (safe) and `ARCING` (blocked).
- Runtime systems over proof artifacts: the arc cycle is driven by a pure state model and toggles real collision/passability.
- Every action has visible consequence: the zone displays a different Label3D/color when arcing; passability changes on the same tick.
- Small vertical slices before broad systems: exactly one new hazard type for Alpha; no damage-over-time, no chain arcing, no player-electrocution animation.

## Player fantasy

A damaged power conduit cycles through unstable discharge. The doorway flickers live for a few seconds, then briefly grounds itself. The player must wait for the ground window and dash through before the arc re-ignites.

## Gameplay problem

REQ-006 solved "depleting resource" pressure and REQ-010 solved "periodic passability" pressure with a long-safe / short-danger cadence. Alpha needs a third hazard pattern to prove the ship can host multiple environmental pressures without every hazard being an oxygen-drain or fire-wait variant.

## Core behavior

- One or more electrical arc zones exist in each new Alpha template, placed on non-critical links (side corridors or optional doorways) where topology supports it.
- The arc zone has two states: `DISCHARGED` (safe/passable) and `ARCING` (blocked).
- State cycles on a fixed timer: `arcing_duration = 2.5s`, `discharged_duration = 1.5s`.
- While `ARCING`, the zone's collision segment is enabled, blocking traversal.
- While `DISCHARGED`, the zone's collision segment is disabled, allowing traversal.
- The arc zone does not deplete oxygen, health, or other resources.
- The arc zone cannot be disabled by objectives or tools in Alpha.
- The cycle starts in `DISCHARGED` on slice load so the player is never spawn-trapped.

The shorter safe window and shorter overall cycle make the arc feel complementary to fire: fire asks the player to wait for a longer clear window, while the arc asks the player to commit to a brief window. The two hazards de-synchronize naturally because their cycle durations differ.

## Inputs

- Slice elapsed time (same `_process` delta source used by `OxygenState` and `FireState`).
- Electrical arc zone markers from generated ship data (new optional field `arc_zones`).

## Outputs

- Arc zone summary (`state`, `time_in_state`, `cycle_duration`, `arcing`, `passability_blocked`).
- Label3D text toggles between `ARC GROUNDED — CROSS` and `ARC LIVE — WAIT`.
- Collision segment enabled/disabled.

## Rules

- Arc cycle is independent of oxygen, route gates, objectives, fire, and inventory.
- Timer accumulates `delta` until it reaches the current phase duration, then flips phase and resets.
- Passability is blocked only while `ARCING`.
- The cycle never stops or skips phases in Alpha.
- If the player is inside the zone when it transitions to `ARCING`, the player is not teleported; the collision simply blocks further movement out of that segment (the existing physics/collision handles containment).
- Arc zones must not overlap fire zones, breach zones, or other hazard zones in any template.

## Non-goals

- No player health or damage-over-time.
- No chain arcing, propagation, or random ignition.
- No interaction to disable/override the arc cycle in Alpha.
- No audio, particle, lighting changes, or screen-shake.
- No procedural arc placement per run; Alpha placement is hand-authored per template.
- No arc-oxygen or arc-fire interaction.

## Technical design

- New pure model: `scripts/systems/electrical_arc_state.gd` (`ElectricalArcState` extending `RefCounted`).
  - Inputs: `configure(zone_ids: Array, arcing_duration: float, discharged_duration: float)`, `tick(delta_seconds: float)`.
  - Outputs: `get_summary() -> Dictionary`, `get_status_lines() -> PackedStringArray`, `is_passability_blocked() -> bool`.
  - State machine: `enum Phase { DISCHARGED, ARCING }`; `time_in_phase`; toggles on threshold.
- Scene integration:
  - `scripts/procgen/playable_generated_ship.gd` owns one `ElectricalArcState` instance.
  - Arc-zone collision segments are built from markers in the loader output.
  - `_process` calls `electrical_arc_state.tick(delta)` then `_refresh_arc_state()` which toggles collision and Label3D.
  - The arc zone uses a `StaticBody3D` + `CollisionShape3D` + `MeshInstance3D` + `Label3D`, mirroring the breach-zone and fire-zone construction.
- Loader contract: `scripts/procgen/generated_ship_loader.gd` gains an optional `arc_zones` array. Missing/null means no arc zones; the coordinator skips arc setup rather than injecting a fallback, because placement is template-specific.
- Direct model smoke: `scripts/validation/electrical_arc_state_smoke.gd` runs the cycle through several phase transitions and asserts timing and passability.
- Main-scene smoke: `scripts/validation/main_playable_slice_arc_smoke.gd` loads a template that includes an arc zone, advances time, and asserts the zone cycles and blocks passability in `ARCING`.

## Data model additions

- `ElectricalArcState` instance owned by `PlayableGeneratedShip`.
- Optional `arc_zones` array in generated ship data (room id + cell + zone id).
- Save/load (REQ-012) serializes `ElectricalArcState.phase`, `time_in_phase`, and cycle durations as part of the current-run snapshot.

## Trigger / preconditions / postconditions

- **Trigger:** Slice load initializes the arc zones.
- **Preconditions:**
  - Generated ship data provides at least one arc zone marker for templates that support it.
  - `PlayableGeneratedShip` has finished `_ready` and spawned the arc zone nodes.
- **Postconditions:**
  - `ElectricalArcState` is in `DISCHARGED` phase with `time_in_phase = 0.0`.
  - Collision on the arc-zone segments is disabled.
  - On each `_process`, the phase advances when its duration elapses and collision/label update accordingly.

## Edge cases and failure modes

- **Zero or negative duration:** `configure()` clamps both durations to a minimum of `0.1s` to prevent infinite rapid toggling.
- **Missing arc zone data:** The loader returns an empty array; the coordinator skips arc setup. Templates that require arc validation must include at least one marker.
- **Large delta:** A single `tick(delta)` longer than one phase duration flips once and carries the remainder into the next phase (do not loop multiple times in one tick to keep determinism simple).
- **Save/load mid-phase:** Loading restores the exact phase and `time_in_phase`; the cycle continues from there.
- **Overlap with fire or breach:** Forbidden by placement rules; the main-scene smoke asserts zone ids are distinct and non-overlapping.

## Acceptance criteria

- Given a fresh slice load, when `electrical_arc_state.get_summary()` is queried, then `state == "DISCHARGED"`, `time_in_state == 0.0`, and `passability_blocked == false`.
- Given the arc zone is in `DISCHARGED`, when accumulated time reaches `discharged_duration`, then state flips to `ARCING`, `time_in_state` resets to `0.0`, and `passability_blocked == true`.
- Given the arc zone is in `ARCING`, when accumulated time reaches `arcing_duration`, then state flips to `DISCHARGED`, `passability_blocked == false`, and the cycle can repeat.
- Given a template that supports arc zones loads, when the arc main-scene smoke runs, then it prints `MAIN PLAYABLE ARC PASS state=DISCHARGED cycles=2 blocked_arcing=true blocked_discharged=false`.
- Given the model smoke runs in isolation, when it advances through two full cycles, then it prints `ARC STATE PASS cycles=2 phases=4 passability_switches=4`.
- Given each new Alpha template, when its layout is reviewed, then at least one non-critical link hosts an arc zone where the topology supports it.

## Validation

- Direct model smoke:
  ```bash
  /Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-synaptic-sea-of-stars --script res://scripts/validation/electrical_arc_state_smoke.gd
  ```
  Expected marker: `ARC STATE PASS cycles=2 phases=4 passability_switches=4`

- Main-scene smoke:
  ```bash
  /Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-synaptic-sea-of-stars --script res://scripts/validation/main_playable_slice_arc_smoke.gd
  ```
  Expected marker: `MAIN PLAYABLE ARC PASS state=DISCHARGED cycles=2 blocked_arcing=true blocked_discharged=false`

- Regression inclusion: add both smokes to the bundle in `docs/game/06_validation_plan.md` before the feature is marked done.

## Risks

- Risk: the short safe window makes the arc feel punitive. Mitigation: place it on non-critical links only; keep durations short enough that a missed window is only a 2.5s wait.
- Risk: arc and fire timers become copy-paste code. Mitigation: per ADR-0005, `FireState` and `ElectricalArcState` share a reusable `PhaseTimer` helper but remain independent `RefCounted` models; `OxygenState` implements the same `HazardStateContract` without timer inheritance.
- Risk: arc collision overlaps fire or breach zones. Mitigation: enforce distinct zone ids and non-overlapping geometry in template authoring; the main-scene smoke asserts this.
- Risk: HUD becomes noisy with a third hazard status line. Mitigation: arc zone shows only a localized Label3D; the global HUD line is reserved for oxygen.

## ADRs

- `docs/game/adr/0001-adopt-stage-gate-kanban-godot-validation.md`
- `docs/game/adr/0005-multi-hazard-architecture.md` — defines the `HazardStateContract`, the `PhaseTimer` helper shared by `FireState` and `ElectricalArcState`, the loader contract for `breach_zones` / `fire_zones` / `arc_zones`, and the save/load serialization shape for hazard state.
