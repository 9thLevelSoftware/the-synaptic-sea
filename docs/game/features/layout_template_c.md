# Feature: Ship Layout Template C (Stacked)

## Status

In progress for Alpha content-complete target.

## Requirement cross-reference

- Content-complete target: `docs/game/content_complete_target.md` (3 unique ship layout templates)
- Schema contract: `data/procgen/golden/coherent_ship_001/layout.json` and `gameplay_slice.json`
- Runtime loader: `scripts/procgen/generated_ship_loader.gd`
- Main-scene smoke: `scripts/validation/template_c_main_scenario_smoke.gd`

## Design intent

Template C is the third hand-authored ship layout for Synapse Sea Alpha. It is visually and topologically distinct from Template A (horizontal spine with side rooms, single ramp) and Template B (bifurcated branch-and-merge). Template C is a **stacked two-deck ship**:

- Lower deck contains the airlock, entry corridor, a central hub, optional side rooms, and the reactor.
- Upper deck contains a second hub and the maintenance / medbay side rooms.
- The player must climb a ramp to reach deck 1, complete upper-deck objectives, then ride an elevator shaft back down to deck 0 to reach the reactor.

This creates two meaningful vertical transitions on the critical path and forces the player to traverse both decks, making the ship shape immediately recognizable on repeated runs.

## Topology

### Rooms

| Room | Deck | Role | Notes |
|---|---|---|---|
| `airlock_03` | 0 | airlock | Spawn point |
| `corridor_03` | 0 | corridor | Entry corridor |
| `lower_hub_03` | 0 | main_hub | Central hub on lower deck |
| `storage_03` | 0 | storage | Objective 1: recover_supplies |
| `tool_storage_03` | 0 | tool_storage | Portable oxygen pump pickup |
| `ramp_03` | 0 | ramp | Ramp up to upper deck |
| `elevator_03` | 0 | elevator_shaft | Elevator down from upper deck |
| `reactor_access_03` | 0 | corridor | Corridor before reactor |
| `reactor_03` | 0 | reactor | Objective 5: stabilize_reactor, extraction point |
| `upper_hub_03` | 1 | main_hub | Central hub on upper deck |
| `medbay_03` | 1 | medbay | Objective 3: download_logs |
| `maintenance_03` | 1 | maintenance | Objective 2: repair_junction |

### Critical path

```
airlock_03 → corridor_03 → lower_hub_03 → ramp_03 → upper_hub_03 → elevator_03 → reactor_access_03 → reactor_03
```

### Vertical transitions

1. `ramp_03_to_upper_hub_03`: ramp from lower deck cell `[6, 0, 0]` to upper deck cell `[6, 0, 1]`.
2. `elevator_03_to_upper_hub_03`: elevator shaft from lower deck cell `[8, 0, 0]` to upper deck cell `[8, 0, 1]`.

### Objectives

| Sequence | Type | Room | Notes |
|---|---|---|---|
| 1 | `recover_supplies` | `storage_03` | Optional side room off lower hub |
| 2 | `restore_systems` / `repair_junction` | `maintenance_03` | Two-step junction; restores main power and clears blocked route |
| 3 | `download_logs` | `medbay_03` | Upper deck side room |
| 4 | `restore_systems` | `upper_hub_03` | Single-step life-support console |
| 5 | `stabilize_reactor` | `reactor_03` | Final objective, unlocks extraction |

### Hazards

- **Timed fire** on the side link `lower_hub_to_storage_fire` (non-critical; only blocks access to optional objective 1 loot).
- **Oxygen breach** on the `upper_hub_to_elevator_breach` vertical corridor (obj4 → obj5 path). Sealed when main power is restored at sequence 2.

### Blocked route

- `reactor_access_to_reactor_blocked`: biomatter blockage on the critical path just before the reactor. Cleared when main power is restored at sequence 2.

### Tool pickup

- Portable oxygen pump in `tool_storage_03`.

## Procedural variation

Template C supports the variation targets from `docs/game/content_complete_target.md`:

- **Objective placements:** each sequence slot has at least two valid approach cells documented in the data files.
- **Hazard placements:** the fire zone can be moved to other non-critical side links (`lower_hub_to_tool_storage`, `upper_hub_to_medbay`, `upper_hub_to_maintenance`). The breach zone can be placed on any obj4 → obj5 corridor segment.
- **Tool pickup:** the pump can be placed in `tool_storage_03` or moved to another side room.
- **Blocked-link configs:** the biomatter blockage can be placed on `reactor_access_to_reactor` (current) or on `elevator_to_reactor_access`.

The exact randomization rules are owned by the procedural generator and validated by seed-diversity smokes.

## Files

- `data/procgen/golden/coherent_ship_003/layout.json`
- `data/procgen/golden/coherent_ship_003/gameplay_slice.json`
- `scripts/validation/template_c_main_scenario_smoke.gd`

## Verification

Run the main-scene smoke:

```bash
/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-synapse-sea-of-stars --script res://scripts/validation/template_c_main_scenario_smoke.gd
```

Expected marker:

```
TEMPLATE C MAIN SCENARIO PASS objectives=5 current_sequence=6 run_complete=true
```

The smoke is included in the regression bundle in `docs/game/06_validation_plan.md`.

## Non-goals

- No new art assets or modules beyond the existing `ship_structural_v0` kit.
- No new objective, hazard, or tool archetypes (uses existing Gate 2 systems).
- No runtime generator changes in this card; those are deferred to the procedural-variation implementation plan.
