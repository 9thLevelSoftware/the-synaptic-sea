# Ship Systems, Power Grid, Hull, Life Support & Sustenance Infrastructure

Status: Implemented for Task 07 package baseline
Source: `docs/game/build-plans/07-ship-systems-sustenance-e2e.md`, ADR-0008, ADR-0034

## Objective
Add a pure-model ship infrastructure layer that turns the existing ship-system repair framework into a persistent runtime package with manual power routing, compartmentalized hull integrity, life-support telemetry, fire suppression, propulsion/shield readouts, and sustenance aggregation across hydroponics, synthesizer, and water recycler facilities.

## Player-facing behavior
- Manual power routing can blackout propulsion, life support, shields, stations, lights, or sustenance when allocations fall below threshold.
- Hull integrity is tracked per compartment and breaches can be opened/sealed independently.
- Life support reports oxygen/CO2/temperature/water telemetry and degrades when underpowered or breached.
- Fire suppression tracks active fires and clears them when powered suppressant is available.
- Propulsion and shields expose live state summaries driven by manager health plus routed power.
- Sustenance facilities aggregate real hydroponics/synthesizer/water-recycler output into a single ship-level summary.
- Expanded subsystem summaries persist through `RunSnapshot.ship_systems_summary` round-trips.

## Data contracts
- `data/ship_systems/power_budget_tables.json`
- `data/ship_systems/hull_compartments.json`
- `data/ship_systems/facility_upgrades.json`
- `data/ship_systems/subsystem_tuning.json`

## Acceptance criteria
1. Pure state objects exist for power grid, life support, hull integrity, fire suppression, propulsion, shields, and sustenance aggregation.
2. `PlayableGeneratedShip` owns and ticks the expanded models without moving gameplay state into scene nodes.
3. `get_ship_systems_summary()` and `_build_run_snapshot()` carry the expanded summaries.
4. Focused smokes pass for power grid, life support, sustenance aggregation, and playable-slice persistence.
5. Regression bundle registration is updated so Task 07 coverage stays in the standard validation path.

## Non-goals
- No authored panel scene/UI redesign beyond status-line integration in this package.
- No new damage-type combat pipeline.
- No ship-upgrade economy or crafting-tree expansion beyond facility summary aggregation.
