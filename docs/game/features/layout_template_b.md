# Layout Template B: Bifurcated Ship

## Overview

Template B (`coherent_ship_002`) is the second hand-authored ship layout for Sargasso Alpha. It is a single-deck, Y-shaped derelict in which the player spawns in an airlock, reaches a central hub, and must explore two major side branches before the route to the reactor unlocks.

This template is intentionally distinct from Template A (`coherent_ship_001`), which is a two-deck horizontal spine with side rooms reached by a ramp. Template B has no vertical deck transitions and no long central spine; instead, the critical path forks, loops through side rooms, and converges.

## Source

- `data/procgen/golden/coherent_ship_002/layout.json`
- `data/procgen/golden/coherent_ship_002/gameplay_slice.json`
- Content-complete target: `docs/game/content_complete_target.md`

## Topology

```
                        [reactor_01]
                             |
                    [convergence_01]
                             |
                         [hub_01]
                        /        \
              [left_arm_01]    [right_arm_01]
                  /    \            /    \
      [cargo_bay_01] [maintenance_bay_01] [medbay_01] [bridge_01]

[start] [tool_storage_01]
   |
[airlock_01] -- [corridor_01] -- [hub_01]
```

### Room roles

| Room | Role | Purpose |
|---|---|---|
| `airlock_01` | airlock | Player spawn and extraction anchor |
| `tool_storage_01` | storage | Optional portable oxygen pump pickup |
| `corridor_01` | corridor | Entry corridor from airlock to hub |
| `hub_01` | main_spine | Central fork where the ship splits |
| `left_arm_01` | corridor | Left branch access corridor |
| `cargo_bay_01` | cargo | Objective 1: recover emergency supplies |
| `maintenance_bay_01` | maintenance | Objective 2: repair junction (multi-step) |
| `right_arm_01` | corridor | Right branch access corridor |
| `medbay_01` | medbay | Objective 3: download logs |
| `bridge_01` | bridge | Objective 4: restore power distribution |
| `convergence_01` | main_spine | Meet point before the reactor |
| `reactor_01` | reactor | Objective 5: stabilize reactor |

### Critical path

The canonical completion order defined in the layout is:

`airlock_01 -> corridor_01 -> hub_01 -> left_arm_01 -> cargo_bay_01 -> maintenance_bay_01 -> right_arm_01 -> medbay_01 -> bridge_01 -> convergence_01 -> reactor_01`

The player may choose to clear the left or right branch first, but both branches must be completed before the reactor objective becomes available.

## Objective sequence

| Sequence | Type | Kind | Room | Notes |
|---|---|---|---|---|
| 1 | `recover_supplies` | single | `cargo_bay_01` | Emergency supply cache |
| 2 | `restore_systems` | `repair_junction` | `maintenance_bay_01` | Two-step breaker repair |
| 3 | `download_logs` | single | `medbay_01` | Medical terminal |
| 4 | `restore_systems` | single | `bridge_01` | Power distribution panel |
| 5 | `stabilize_reactor` | single | `reactor_01` | Reactor control panel |

Template B uses five objectives, one per sequence slot, satisfying the Alpha content-complete target of at least one objective per sequence and enough room volume for alternate placements per seed.

## Hazards and blocked routes

- **Blocked links:** two shortcut doorways from the branch ends (`maintenance_bay_01`, `bridge_01`) directly to `convergence_01`. These are sealed until a `restore_systems` objective is completed, so the player cannot bypass the hub without first restoring power. The two independent blocked-link candidates give the procedural generator a choice of seed-driven configurations.
- **Fire zone:** one timed-fire zone on the optional `airlock_01 <-> tool_storage_01` link. It can briefly block access to the portable oxygen pump but never blocks a main objective or the critical path.

## Tool placement

The portable oxygen pump spawns in `tool_storage_01`, a small side room attached to the airlock. Acquisition is optional and halves oxygen drain inside the breach zone.

## Procedural variation support

Template B provides seed-driven variation candidates for:

- **Blocked-link configuration:** two distinct blocked shortcuts allow the generator to activate one, both, or none per seed.
- **Objective placements:** each objective room has multiple floor cells, supporting at least two valid placements per sequence slot.
- **Hazard placement:** the fire zone can be moved to the alternate optional link or duplicated on other non-critical side links if future kits add them.

## Verification

- Loads end-to-end via `main_playable_slice_template_b_completion_smoke.gd`.
- All five objectives complete and mark the run complete.
- Regression bundle includes the template-B smoke.

## Distinctness from Template A

| Property | Template A | Template B |
|---|---|---|
| Decks | 2 (ramp transition) | 1 (flat) |
| Main shape | Long horizontal spine | Y-shaped fork |
| Branching | Side rooms off spine | Two parallel major branches |
| Objectives | 4 | 5 |
| Blocked links | 1 | 2 |
| Tool room | Fallback spawn | Dedicated `tool_storage_01` |
