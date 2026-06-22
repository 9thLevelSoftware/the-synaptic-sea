# ADR-0013: Derelict gameplay parity (parallel objective loop)

Date: 2026-06-21
Status: Accepted
Related: ADR-0011 (ShipInstance & travel), ADR-0012 (world persistence),
docs/superpowers/specs/2026-06-21-derelict-gameplay-parity-design.md

## Context

Sub-project #1 made visited ships persist, but a boarded derelict was a bare hull
(`_process` early-returns when `away_from_start`). The rich objective loop lived only on
the home ship and is entangled with reactor/extraction and junction_calibrator specifics.

## Decision

Give a boarded derelict a PARALLEL objective loop rather than swapping the home singletons.
A pure-logic `DerelictObjectiveController` composes `ObjectiveProgressState` and adds
`reach_goal`/`cleared` semantics. Each derelict `ShipInstance` owns a controller; its summary
rides the per-ship slice (ADR-0012), so objective progress + `cleared` persist across
leave/return and save/load for free. The coordinator spawns the derelict's interactables
(from the active loader's generated specs) under a dedicated `DerelictObjectiveRoot`, lifts
the Phase 4.5 interaction-gate for the active derelict, and routes completion to the
controller.

`reach_goal` IS the derelict's extraction (there is no reactor path on a derelict).

## Consequences

- Because #2 is objectives-only and input-driven (`Interactable` is an `Area3D`, no per-frame
  work), only the `_on_player_interact_requested` away-gate is lifted; the `_process`
  per-frame freeze stays. The `_process` freeze-lift moves to #2b, when derelict hazards
  add per-frame ticking.
- The home loop is untouched (its singletons, reactor extraction, and HUD behave exactly as
  before, including after travelling out and back).
- Completing a derelict yields the persisted `cleared` state only; the tangible reward
  (loot/parts) is deferred to sub-project #3 (player inventory).
- Completed salvage objectives do not respawn on revisit; a cleared derelict reads as cleared
  across revisit and quit→resume.
