# Feature: Hazard Variety — Timed Fire Zone

> **Superseded (M7-B).** The cyclic, timer-driven `FireState` fire hazard described
> below was retired and replaced by the persistent compartment-fire model introduced
> in M7-B. See **ADR-0041 (Fire as a persistent compartment hazard)** and **REQ-010**
> for the current design (ignite/spread on accumulated damage, manual extinguishing
> via fire-suppression points, recharge ports, no automatic SAFE/BURNING cycle). The
> Gate-2 content below is retained as history only and no longer reflects runtime behavior.

## Status

Approved for Gate 2 implementation (superseded by M7-B persistent fire — see ADR-0041)

## Requirement cross-reference

- REQ-010 Hazard variety (new Gate 2 requirement)
- Extends REQ-006 Hazard pressure loop without changing oxygen semantics.
- Preserves REQ-001..003 and REQ-007 (the new fire zone does not depend on tools; tools do not affect it in Gate 2).

## Design pillar alignment

- Spatial coherence first: the fire zone occupies a readable room/corridor and changes its read state between SAFE and BURNING.
- Runtime systems over proof artifacts: the fire cycle is driven by a pure state model and toggles real collision/passability.
- Every action has visible consequence: the zone displays a different Label3D/color when burning; passability changes on the same tick.
- Small vertical slices before broad systems: exactly one new hazard type in one new zone for Gate 2; no health-depletion, no damage-over-time, no fire propagation.

## Player fantasy

A damaged plasma conduit cycles between venting and dormancy. The player must time movement through the corridor: wait for the flare to subside, then cross before it reignites.

## Gameplay problem

REQ-006 solved "one depleting resource" pressure. Gate 2 needs a second hazard pattern to prove the ship can support multiple environmental pressures without every hazard being a variation of oxygen drain.

## Core behavior

- One fire zone exists in the Gate 2 slice, placed on a side corridor that is not the objective 3 → objective 4 breach corridor.
- The fire zone has two states: `CLEARED` and `BURNING`.
- State cycles on a fixed timer: `burn_duration = 4.0s`, `clear_duration = 3.0s`.
- While `BURNING`, the zone's collision segment is enabled, blocking traversal.
- While `CLEARED`, the zone's collision segment is disabled, allowing traversal.
- The fire zone does not deplete oxygen, health, or other resources.
- The fire zone cannot be sealed or disabled by objectives in Gate 2.
- The cycle starts in `CLEARED` on slice load so the player is never spawn-trapped.

## Inputs

- Slice elapsed time (same `_process` delta source used by `OxygenState`).
- Fire zone marker from generated ship data (new optional field `fire_zones`).

## Outputs

- Fire zone summary (`state`, `time_in_state`, `cycle_duration`, `burning`, `passability_blocked`).
- Label3D text toggles between `FIRE CLEARED` and `FIRE BURNING — WAIT`.
- Collision segment enabled/disabled.

## Rules

- Fire cycle is independent of oxygen, route gates, objectives, and inventory.
- Timer accumulates `delta` until it reaches the current phase duration, then flips phase and resets.
- Passability is blocked only while `BURNING`.
- The cycle never stops or skips phases in Gate 2.
- If the player is inside the zone when it transitions to `BURNING`, the player is not teleported; the collision simply blocks further movement out of that segment (the existing physics/collision handles containment).

## Non-goals

- No player health or damage-over-time.
- No fire spread, propagation, or random ignition.
- No interaction to disable/override the fire cycle in Gate 2.
- No audio, particle, heat distortion, or lighting changes.
- No procedural fire placement per run; Gate 2 uses one fixed side corridor.
- No fire-oxygen interaction (fire does not drain oxygen faster and oxygen does not affect fire).

## Technical design

- New pure model: `scripts/systems/fire_state.gd` (`FireState` extending `RefCounted`).
  - Inputs: `configure(zone_ids: Array, burn_duration: float, clear_duration: float)`, `tick(delta_seconds: float)`.
  - Outputs: `get_summary() -> Dictionary`, `get_status_lines() -> PackedStringArray`, `is_passability_blocked() -> bool`.
  - State machine: `enum Phase { CLEARED, BURNING }`; `time_in_phase`; toggles on threshold.
- Scene integration:
  - `scripts/procgen/playable_generated_ship.gd` owns one `FireState` instance.
  - A single fire-zone collision segment is built from a marker in the loader output or a fixed fallback position in the side corridor.
  - `_process` calls `fire_state.tick(delta)` then `_refresh_fire_state()` which toggles collision and Label3D.
  - The fire zone uses a `StaticBody3D` + `CollisionShape3D` + `MeshInstance3D` + `Label3D`, mirroring the breach-zone construction.
- Loader contract: `scripts/procgen/generated_ship_loader.gd` gains an optional `fire_zones` array. Missing/null means no fire zone; the coordinator injects the Gate 2 fallback if needed for validation.
- Direct model smoke: `scripts/validation/fire_state_smoke.gd` runs the cycle through several phase transitions and asserts timing and passability.
- Main-scene smoke: `scripts/validation/main_playable_slice_fire_smoke.gd` loads the slice, advances time, and asserts the fire zone cycles and blocks passability in `BURNING`.

## Data model additions

- `FireState` instance owned by `PlayableGeneratedShip`.
- Optional `fire_zones` array in generated ship data (room id + cell + zone id).
- Save/load (REQ-012) serializes `FireState.phase`, `time_in_phase`, and cycle durations as part of the current-run snapshot.

## Trigger / preconditions / postconditions

- **Trigger:** Slice load initializes the fire zone.
- **Preconditions:**
  - Generated ship data provides a fire zone marker or the coordinator chooses the fallback.
  - `PlayableGeneratedShip` has finished `_ready` and spawned the fire zone nodes.
- **Postconditions:**
  - `FireState` is in `CLEARED` phase with `time_in_phase = 0.0`.
  - Collision on the fire-zone segment is disabled.
  - On each `_process`, the phase advances when its duration elapses and collision/label update accordingly.

## Edge cases and failure modes

- **Zero or negative duration:** `configure()` clamps both durations to a minimum of `0.1s` to prevent infinite rapid toggling.
- **Missing fire zone data:** The loader returns an empty array; the coordinator injects the fallback side-corridor zone id so the main-scene smoke can still assert a fire zone exists.
- **Large delta:** A single `tick(delta)` longer than one phase duration flips once and carries the remainder into the next phase (do not loop multiple times in one tick to keep determinism simple; document this clamp if needed).
- **Save/load mid-phase:** Loading restores the exact phase and `time_in_phase`; the cycle continues from there.
- **Overlap with oxygen breach:** If the fire zone and breach zone share geometry (they must not in Gate 2), both block independently; the spec forbids overlapping zones.

## Acceptance criteria

- Given a fresh slice load, when `fire_state.get_summary()` is queried, then `state == "CLEARED"`, `time_in_state == 0.0`, and `passability_blocked == false`.
- Given the fire zone is in `CLEARED`, when accumulated time reaches `clear_duration`, then state flips to `BURNING`, `time_in_state` resets to `0.0`, and `passability_blocked == true`.
- Given the fire zone is in `BURNING`, when accumulated time reaches `burn_duration`, then state flips to `CLEARED`, `passability_blocked == false`, and the cycle can repeat.
- Given the main playable slice loads, when the fire main-scene smoke runs, then it prints `MAIN PLAYABLE FIRE PASS state=CLEARED cycles=2 blocked_burning=true blocked_cleared=false`.
- Given the model smoke runs in isolation, when it advances through two full cycles, then it prints `FIRE STATE PASS cycles=2 phases=4 passability_switches=4`.

## Validation

- Direct model smoke:
  ```bash
  /Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-synaptic-sea-of-stars --script res://scripts/validation/fire_state_smoke.gd
  ```
  Expected marker: `FIRE STATE PASS cycles=2 phases=4 passability_switches=4`

- Main-scene smoke:
  ```bash
  /Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-synaptic-sea-of-stars --script res://scripts/validation/main_playable_slice_fire_smoke.gd
  ```
  Expected marker: `MAIN PLAYABLE FIRE PASS state=CLEARED cycles=2 blocked_burning=true blocked_cleared=false`

- Regression inclusion: add both smokes to the bundle in `docs/game/06_validation_plan.md` before the feature is marked done.

## Risks

- Risk: fire timer makes the slice feel like a waiting simulator. Mitigation: keep durations short (3s cleared / 4s burning) and place the zone on an optional side corridor, not the main critical path.
- Risk: two hazard models become copy-paste code. Mitigation: keep them independent for Gate 2; author ADR-0005 (Multi-Hazard Architecture) if a third hazard type is planned, extracting a common hazard interface then.
- Risk: fire collision and oxygen breach collision overlap or conflict. Mitigation: fire zone is on a separate side corridor; the main-scene smoke asserts the zone ids are distinct and non-overlapping.
- Risk: HUD becomes noisy with two hazard status lines. Mitigation: fire zone shows only a localized Label3D; the global HUD line is reserved for oxygen.

## ADRs

- `docs/game/adr/0001-adopt-stage-gate-kanban-godot-validation.md`
- ADR-0005 recommended before a third hazard type is added; Gate 2 can ship `FireState` as a second independent model without a generalized architecture ADR.
