# ADR-0009: Retire ShipSystemState; ShipSystemsManager is the live ship-systems model

Date: 2026-06-20
Status: Accepted
Supersedes parts of: ADR-0008 (ship-systems architecture)
Relates to: ADR-0007 (save/load scope)

## Context
Phase 2 introduced `ShipSystemsManager` (6 systems, subcomponents, dependency
cascade, repair). The vertical slice still drove ship-systems consequences from
`ShipSystemState`, a coarse objective-flag model. The master core-systems design
mandates the manager replaces the flag model.

## Decision
The coordinator (`playable_generated_ship.gd`) builds `ShipSystemsManager` from a
golden blueprint sidecar and derives all consequences from it via a flag-compat
adapter. `ShipSystemState` is deleted. Two pure-narrative flags (supplies
recovered, logs downloaded) move to a coordinator `completed_objective_types`
record. The RunSnapshot `ship_systems_summary` field now carries the manager
snapshot (a content change, not a new field — SUMMARY_FIELDS count stays 7),
which ADR-0007 gates; this ADR records that change.

## Consequences
- HUD Power/Reactor percentages are now real health-derived values, not the old
  hardcoded 18/72/22/100.
- `main_power_restored` derives from `power_distribution` + `battery_cells`
  functional; extraction/`reactor_stabilized` derives from `reactor_core` full.
- Breach-oxygen ownership and the loader are unchanged (later phases).
