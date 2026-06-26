# Task 07: Ship Systems, Power Grid, Hull, Life Support & Sustenance Infrastructure

Status: Implemented package baseline on 2026-06-25
Task id: `t_290ec958`

## Objective
Deliver the Task 07 end-to-end ship infrastructure package with real pure-model state, playable-slice integration, persistence round-trip coverage, and registered focused smokes.

## Delivered scope
- Added pure models for power grid, life support, hull integrity, fire suppression, propulsion, shields, and sustenance aggregation.
- Added ship-system tuning/config JSONs under `data/ship_systems/`.
- Extended `PlayableGeneratedShip` to instantiate, tick, summarize, and persist the expanded subsystem package.
- Added focused smokes for power-grid, life-support, sustenance, and playable-slice persistence coverage.

## Acceptance markers
- `POWER GRID STATE PASS`
- `LIFE SUPPORT STATE PASS`
- `SUSTENANCE STATE PASS`
- `MAIN PLAYABLE SHIP SYSTEMS EXPANDED PASS`

## Evidence
- `docs/game/build-plans/evidence/ship-systems-sustenance-contract-review.md`
- `docs/game/features/ship_systems_sustenance_infrastructure.md`
- `docs/game/adr/0035-ship-systems-sustenance-expansion-architecture.md`
- `docs/game/balance/ship-systems-sustenance-tuning.md`

## Follow-up
- Full dedicated ship-status/power-routing/facility-upgrade panels remain later UI work.
- Station/light blackout scene-side consequences should be expanded once Task 09 HUD/UI work is active.
