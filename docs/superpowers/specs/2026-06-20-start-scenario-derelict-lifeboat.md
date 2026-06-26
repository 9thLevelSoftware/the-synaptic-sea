# Start Scenario: Derelict + Life Boat

> Status: DRAFT — needs review before implementation
> Date: 2026-06-20
> Supersedes: the "life boat as procgen archetype" approach in Phase 1

## Problem

Phase 1 treats the life boat as a procgen archetype — a 2-4 room ship
generated from a ShipBlueprint. This produces rooms like "maintenance"
and "corridor" on a vessel that should be a bare-bones escape pod.
More importantly, spawning the player directly onto a 3-room ship
with nothing to explore is dull.

The actual game start should put the player on a derelict — a dead
ship with salvageable components — and give them a broken life boat
to repair. The derelict provides the exploration and resource loop;
the life boat is the goal.

## Design

### Derelict (procgen, randomized)

The derelict is a structural shell generated from a ShipBlueprint.
It does NOT need functional rooms, working systems, or gameplay
objectives. It needs:

- **Structural variety**: different layout each seed (rooms, corridors,
  dead ends) so exploration feels fresh.
- **A dock connector**: one room (or wall) where the life boat
  attaches. This is the fixed anchor point.
- **Salvage points**: locations where the player can scavenge
  components. These are prop placements, not room roles.
- **No functional systems**: no engineering, no life support, no
  bridge. The derelict is dead. Rooms are just structural space
  (compartments, corridors, storage bays, crew areas).
- **Single deck**: no vertical layout for now. Multi-deck derelicts
  are a future expansion.

Room roles for the derelict should be generic: "compartment",
"corridor", "bay", "quarters". The generator doesn't need to think
about ship systems for the derelict — just spatial variety.

### Life Boat (hand-authored, fixed)

The life boat is a fixed layout that never changes. It's small:

- **Airlock**: entry from the derelict dock
- **Cockpit**: combined bridge + flight controls + scanner
- **Engine bay**: combined engineering + maintenance + life support

That's 3 rooms. Fixed. No procgen. The life boat is always the same
so the player learns it and the repair mechanics are deterministic.

The life boat starts broken. The player must scavenge components from
the derelict to repair it. Repair progress is tracked per-system
(engines, life support, navigation) but the physical layout doesn't
change.

### Dock Connector

The derelict and life boat are joined at a dock point:

- The derelict's dock room has a door/wall that connects to the
  life boat's airlock.
- The dock is always present on the derelict (guaranteed room).
- The life boat's airlock is always the connection point.

In the procgen pipeline, the dock is a special room role on the
derelict ("dock") that the generator always includes exactly one of.
The StructuralPlacer knows to position it so the life boat can attach.

### Generation Pipeline (revised)

```
Start Scene = Derelict(ShipBlueprint, seed) + LifeBoat(fixed)
```

1. Generate derelict structural shell from blueprint (procgen).
2. Place the fixed life boat scene adjacent to the derelict dock.
3. Add salvage points as prop placements inside the derelict rooms.
4. Add the player spawn inside the derelict (not the life boat).

The life boat is a PackedScene loaded from a fixed path, not
generated.

### Room Role Consolidation

Current roles: airlock, corridor, engineering, life_support, bridge,
cargo, crew_quarters, medical, maintenance.

For the derelict, most of these don't apply. The derelict needs:
- compartment (generic interior space)
- corridor (connecting passage)
- bay (large open space — cargo bay, hangar, storage)
- quarters (crew living space)
- dock (the life boat connection point)

For the life boat (hand-authored, not generated):
- airlock
- cockpit
- engine_bay

The existing roles (engineering, bridge, etc.) remain available for
future ship types that ARE generated with functional systems (Phase 2+).

### Archetype Changes

| Archetype | Purpose | Generated? | Rooms |
|-----------|---------|-----------|-------|
| derelict  | Dead shell, randomized | Yes (procgen) | 5-12 compartments/corridors |
| life_boat | Escape pod, fixed | No (hand-authored) | 3 (airlock, cockpit, engine_bay) |

The small_freighter and medium_cruiser archetypes remain for future
procgen of functional ships (salvage targets, other derelicts, etc.).

## Implementation Steps

1. Define derelict room roles (compartment, corridor, bay, quarters, dock).
2. Create derelict archetype JSON with derelict-appropriate weights.
3. Update RoomGraphGenerator to support the derelict role set.
4. Hand-author the life boat scene (3 rooms, fixed layout).
5. Create the dock connector system (derelict dock + life boat airlock).
6. Build the start scene combiner (loads derelict + life boat, joins at dock).
7. Place salvage points inside derelict rooms.
8. Spawn the player inside the derelict.

## Open Questions

- Should the derelict have multiple decks? (Adds vertical exploration)
  → Single deck for now. Multi-deck is a future expansion.
- How many salvage points per derelict? (Balancing concern)
- Should the life boat's cockpit be interactive from the start, or
  only after engines are repaired?
- Should there be multiple derelict archetypes (small/medium/large
  dead ships) or one size with varying room counts?
