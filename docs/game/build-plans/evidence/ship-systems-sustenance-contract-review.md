# Task 07 contract review — ship systems sustenance expansion

Date: 2026-06-25
Task: `t_290ec958`

## Implemented artifacts
- Pure models:
  - `scripts/systems/power_grid_state.gd`
  - `scripts/systems/life_support_state.gd`
  - `scripts/systems/hull_integrity_state.gd`
  - `scripts/systems/fire_suppression_state.gd`
  - `scripts/systems/propulsion_state.gd`
  - `scripts/systems/shield_state.gd`
  - `scripts/systems/sustenance_state.gd`
- Data:
  - `data/ship_systems/power_budget_tables.json`
  - `data/ship_systems/hull_compartments.json`
  - `data/ship_systems/facility_upgrades.json`
  - `data/ship_systems/subsystem_tuning.json`
- Integration:
  - `scripts/procgen/playable_generated_ship.gd`
- Validation:
  - `scripts/validation/power_grid_state_smoke.gd`
  - `scripts/validation/life_support_state_smoke.gd`
  - `scripts/validation/sustenance_state_smoke.gd`
  - `scripts/validation/main_playable_slice_ship_systems_expanded_smoke.gd`

## Contract notes
- Expanded subsystem summaries persist as nested dictionaries inside `ship_systems_summary`.
- Propulsion gating now reflects routed power through `PropulsionState.can_propel()` in addition to manager repairs.
- Sustenance aggregation reads the real hydroponics/synthesizer/water-recycler summaries instead of introducing duplicate facility models.
- Status-line output is the delivery surface for this package; full bespoke panels remain future UI work.

## Validation markers
- `POWER GRID STATE PASS`
- `LIFE SUPPORT STATE PASS`
- `SUSTENANCE STATE PASS`
- `MAIN PLAYABLE SHIP SYSTEMS EXPANDED PASS`
