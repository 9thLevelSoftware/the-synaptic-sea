# Feature: ShipRuntime (per-ship simulation context)

## Status

In implementation (PKG-A1a landed; A1b–A1c follow)

## Design pillar alignment

- Pre-polish architecture prerequisite (Part 1.1)
- Why: coordinator strangler so multi-ship sim and pillar systems do not grow `playable_generated_ship.gd`

## Player fantasy

N/A directly — infrastructure for persistent ships, salvage, and fleet meaning.

## Gameplay problem

Per-ship advance/catch-up logic lived only on the coordinator, blocking clean multi-runtime simulation and snapshot composition.

## Core behavior (A1a)

- `ShipRuntime` RefCounted owns `advance(delta, world_time)` and `catch_up(world_time)` for one ship handle.
- Advance stamps `last_sim_time`, advances `systems_manager`, ticks web → hull damage.
- Catch-up fast-forwards absent derelicts in capped sub-steps; home ships skip catch-up.
- Hub injects coordinator-owned hull/web; derelicts use `ShipInstance` models.
- Coordinator keeps thin wrappers (`_advance_ship` / `_catch_up_ship`) for existing smokes.

## Non-goals (A1a)

- Full coordinator shrink to <3k lines
- Tick bands (A3)
- Module integrity / components (pillar)
- Moving hub expanded recompute into ShipRuntime

## Acceptance criteria

- Given a derelict ShipInstance with attached web, when `advance` runs, then `last_sim_time` stamps and web/hull models move.
- Given elapsed absence, when `catch_up` runs, then sub-stepped advance applies and is idempotent at fixed world_time.
- Given home runtime, when `catch_up` is called, then it is a no-op.
- Existing `ship_catchup_smoke` remains green via coordinator wrappers.

## Validation

- `scripts/validation/ship_runtime_smoke.gd` — `SHIP RUNTIME PASS`
- `scripts/validation/ship_catchup_smoke.gd` — `SHIP CATCHUP PASS`

## Requirements

- REQ-ARCH-003
