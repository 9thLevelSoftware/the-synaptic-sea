# ADR-0035: Ship Systems Sustenance Expansion Architecture

Status: Accepted
Date: 2026-06-25

## Context
Task 07 requires the existing `ShipSystemsManager` package to grow into a broader ship-infrastructure layer: manual power routing, compartmentalized hull state, richer life-support telemetry, fire suppression, propulsion/shield summaries, and sustained integration with hydroponics, synthesizer, and water recycler systems. The current codebase already contains a manager-level repair model and separate sustenance-adjacent pure models, but no aggregate infrastructure layer or persistence contract for those states.

## Decision
1. Keep `ShipSystemsManager` as the authoritative repair/damage system for canonical ship-system health.
2. Add new pure `RefCounted` state models for Task 07 concerns:
   - `PowerGridState`
   - `LifeSupportState`
   - `HullIntegrityState`
   - `FireSuppressionState`
   - `PropulsionState`
   - `ShieldState`
   - `SustenanceState`
3. Let `PlayableGeneratedShip` remain the coordinator that instantiates, ticks, and persists the new models.
4. Persist expanded subsystem summaries by nesting them inside `RunSnapshot.ship_systems_summary` instead of adding another top-level snapshot field.
5. Feed sustenance aggregation from the existing hydroponics/synthesizer/water-recycler summaries rather than duplicating those models.

## Consequences
- Save/load stays additive: older snapshots that lack expanded keys continue to load because the new summaries default to empty dictionaries.
- Manual power routing can affect real downstream behavior without rewriting the older manager contract.
- The coordinator grows wider, but the actual gameplay state remains in pure models instead of scene nodes.
- UI work can read the expanded summaries from one place later without changing the persistence contract again.

## Rejected alternatives
- Extending `ShipSystemsManager` to own every new concern directly. Rejected because it would turn the manager into a god-object and mix repair state with telemetry/resource models.
- Adding a new top-level `RunSnapshot.ship_infrastructure_summary`. Rejected because the existing ship-system summary already owns ship-level persistence and additive nesting is migration-safe.
