# Procedural Ship Layout Pipeline Design

**Date:** 2026-06-20
**Status:** Approved
**Scope:** Layout generation only (structural layout.json output). Gameplay slice generation (objectives, hazards, blocked routes) is future scope.

## Problem

The existing procedural generation system (`RoomGraphGenerator` + `StructuralPlacer`) produces poor ship layouts:

1. **Topology is random** — rooms are placed in a linear chain with random branch links. No concept of spines, hubs, branches, or intentional ship shapes.
2. **Rooms lack geometry** — each room is 2-3 floor tiles in a line. No walls, no doors, no enclosed spaces.
3. **Output format mismatch** — the procgen output is a raw Node3D tree, not the rich `layout.json` format that the hand-authored golden layouts use. The `GeneratedShipLoader` cannot load procgen ships the same way it loads golden ships.

The hand-authored golden layouts (`coherent_ship_001/002/003`) prove that intentional topology, proper walls/doors, and the `layout.json` format produce good, playable ships. The procgen system needs to produce the same quality of output.

## Design Decisions

1. **Template-based composition** — topology patterns are defined as templates, not generated from scratch. Three templates match the three golden layouts. Seed-driven variation within each template provides per-run freshness.
2. **Output format = golden layout.json** — the procgen system outputs the exact same JSON schema as the hand-authored golden layouts. `GeneratedShipLoader` loads both identically.
3. **Proper room geometry** — walls on exposed cell edges, portal doors where rooms connect, interior zones for prop placement.
4. **Keep existing data classes** — `ShipBlueprint` and `RoomGraph` are preserved. Everything between "blueprint input" and "loader consumption" is replaced.
5. **Layout-only scope** — `blocked_links`, `fire_zones`, `arc_zones`, `breach_zones` arrays are output as empty. A future gameplay slice generator populates them.
6. **Deterministic per seed** — same seed + archetype = identical layout.

## Pipeline Architecture

```
ShipBlueprint + Archetype
        |
        v
+---------------------+
|  TemplateSelector    |  Picks a topology template based on archetype/size/seed
+----------+----------+
           | TopologyTemplate
           v
+---------------------+
|  RoomAssigner        |  Fills template zones with room roles, sizes, deck assignments
+----------+----------+
           | RoomPlan (rooms with roles, zone assignments, target cell counts)
           v
+---------------------+
|  CellLayoutEngine    |  Places rooms on a 2D grid, assigns cell footprints,
|                      |  resolves adjacencies and connections
+----------+----------+
           | CellGrid (rooms as rectangular cell blocks on the grid)
           v
+---------------------+
|  WallDoorResolver    |  For each room: walls on exposed edges, portals where
|                      |  rooms connect, interior zones, wall slots
+----------+----------+
           | RoomGeometry (structural placements, wall segments, portals)
           v
+---------------------+
|  LayoutSerializer    |  Assembles the full layout.json document
+----------+----------+
           | Dictionary (layout.json schema)
           v
    GeneratedShipLoader (existing, unchanged)
```

Each stage is a pure-data `RefCounted` class. No scene nodes until `GeneratedShipLoader` instantiates them. Every stage is deterministic given the same seed.

## Topology Templates

Each template defines the macro shape of a ship as a set of named zones connected by a topology graph.

### Template Data Structure

```gdscript
var template := {
    "id": String,                  # "spine", "bifurcated", "stacked"
    "description": String,
    "zones": [{
        "id": String,              # "entry", "spine", "side_branch"
        "role_pool": [String],     # Roles that can fill this zone
        "count": int or [min,max], # How many rooms in this zone
        "position_hint": String,   # "bow", "stern", "center", "lateral", "upper", "lower"
        "deck": int,               # Which deck (0 default)
        "layout": String,          # "linear", "clustered", "single"
        "attach_to": String,       # Which zone this branches off of
    }],
    "connections": [{
        "from": String,            # Zone reference (supports [0], [-1], [*] indexing)
        "to": String,
        "distribution": String,    # "spread", "random", "adjacent"
    }],
    "deck_config": {
        "max_decks": int,
        "vertical_transition_probability": float,
    }
}
```

### Template Pattern: Spine

Based on golden layout `coherent_ship_001`. Linear backbone with side rooms branching off.

```
                    [side_room]   [side_room]
                         |             |
[entry] -- [corridor] -- [spine] ---- [spine] -- [destination]
                         |             |
                    [side_room]   [side_room]
```

Zones:
- `entry` (1 room: airlock/dock, bow position)
- `entry_corridor` (1 corridor, bow)
- `spine` (3-5 corridor/spine rooms, center, linear layout)
- `side_branch` (2-4 functional rooms, lateral, attached to spine)
- `destination` (1 room: reactor/bridge, stern)

Deck config: max 2 decks, 40% chance of vertical transition.

### Template Pattern: Bifurcated

Based on golden layout `coherent_ship_002`. Y-shaped fork with two parallel branches converging.

```
                [branch_room]  [branch_room]
                      |              |
[entry] -- [hub] -- [left_arm] -- [convergence] -- [destination]
                  \                    /
                   [right_arm] ------
                      |              |
                [branch_room]  [branch_room]
```

Zones:
- `entry` (1 room: airlock, bow)
- `entry_corridor` (1 corridor, bow)
- `hub` (1 hub, center)
- `left_arm` (1 corridor, lateral-left)
- `right_arm` (1 corridor, lateral-right)
- `left_branch` (1-2 functional rooms, lateral-left, attached to left_arm)
- `right_branch` (1-2 functional rooms, lateral-right, attached to right_arm)
- `convergence` (1 spine, center)
- `destination` (1 reactor, stern)

Deck config: 1 deck only (flat layout).

### Template Pattern: Stacked

Based on golden layout `coherent_ship_003`. Two decks connected by ramp and elevator.

```
Deck 0: [entry] -- [corridor] -- [lower_hub] -- [ramp]  ...[elevator] -- [access] -- [destination]
                                       |                       |
                                  [lower_side]                 |
Deck 1:                              [upper_hub] -------------+
                                    /           \
                              [upper_side]   [upper_side]
```

Zones:
- `entry` (1 airlock, deck 0, bow)
- `entry_corridor` (1 corridor, deck 0, bow)
- `lower_hub` (1 hub, deck 0, center)
- `lower_side` (1-2 side rooms, deck 0, lateral)
- `ramp` (1 ramp cell, deck 0, center)
- `upper_hub` (1 hub, deck 1, center)
- `upper_side` (1-2 side rooms, deck 1, lateral)
- `elevator` (1 elevator cell, deck 0, center)
- `access_corridor` (1 corridor, deck 0, center)
- `destination` (1 reactor, deck 0, stern)

Deck config: exactly 2 decks, 2 vertical transitions required (ramp up, elevator down).

### Seed-Driven Variation Within Templates

Same template + different seed produces different ships through:
- Room count variation: count ranges like `[3, 5]` are resolved per seed
- Role assignment: which roles fill side branches varies per seed
- Lateral placement: side rooms go port or starboard randomly
- Corridor length: corridors get 1-3 cell-lengths per seed
- Room footprint: rooms get varied rectangular sizes based on role and seed
- Branch distribution: where side rooms attach to the spine shifts per seed

## Room Footprints

Each room gets a rectangular footprint in grid cells based on its role:

| Role | Footprint Options | Notes |
|---|---|---|
| airlock, dock | 2x2, 3x2 | Entry points, medium-sized |
| corridor | 1xN (N=2-5) | Long and narrow |
| engineering | 2x2, 3x2 | Large functional rooms |
| bridge | 2x2, 3x2 | Forward command |
| cargo, bay | 2x2, 3x3, 2x3 | Largest rooms |
| medical | 2x1, 2x2 | Medium rooms |
| crew_quarters | 2x1, 2x2 | Medium rooms |
| maintenance | 1x2, 2x2 | Small to medium |
| life_support | 2x2 | Medium |
| reactor | 3x3, 2x3, 3x2 | Large destination rooms |
| main_spine, hub | 3x3, 2x2 | Hub junctions |
| ramp | 1x1 | Vertical transition cell |
| elevator | 1x1 | Vertical transition cell |
| storage | 1x2, 2x2 | Small utility rooms |

The seed picks from available options. Larger blueprints (MEDIUM) tend toward bigger footprints; SMALL blueprints tend toward smaller.

## Cell Layout Engine

### Placement Algorithm

1. Place the entry zone room at grid origin `(0, 0)`.
2. Placement is `attach_to`-driven: zones are ordered by a BFS over `attach_to` parents and each room is placed adjacent to its zone anchor (falling back to any placed room). The template `connections` array is consumed AFTER placement (Tranche 5, 2026-07-07): declared cross-deck edges whose zone pair placement did not connect are emitted as logical adjacencies (this is what makes stacked_v2's `elevator -> upper_hub` vertical path real); same-deck declared edges act as placement hints and are not force-materialized.
3. Position hints guide placement direction:
   - `bow` = negative Z (forward)
   - `stern` = positive Z (aft)
   - `lateral` = positive/negative X (port/starboard)
   - `center` = along the main axis
4. Collision detection: no two rooms' cell rectangles may overlap. If a placement collides, try alternate positions (rotated footprint, shifted by one cell, opposite lateral side).
5. After all rooms are placed, verify connectivity via BFS. All rooms must be reachable from the entry room.

### Grid Coordinates to World Position

Cell `(x, z)` on deck `d` maps to:
- `world_x = x * CELL_SIZE` where `CELL_SIZE = 4.0`
- `world_y = d * DECK_HEIGHT` where `DECK_HEIGHT = 4.0`
- `world_z = z * CELL_SIZE`

## Wall and Door Resolution

For each room, after its cell footprint is placed on the grid:

### Wall Placement

1. For every cell in the room, check each of its 4 edges (north, south, east, west).
2. If the edge faces empty grid space or the grid boundary: place a `wall_straight_1x1` module at the appropriate position and yaw.
3. If the edge faces another cell of the same room: no wall (open interior).
4. If the edge faces a cell of an adjacent connected room: place a `bulkhead_portal_2x1` portal instead of a wall.

### Wall Module Positioning

| Edge Direction | Module | Yaw | Position Offset from Cell Center |
|---|---|---|---|
| South | wall_straight_1x1 | 0 degrees | `(0, 0, -CELL_SIZE/2 - 1.0)` |
| West | wall_straight_1x1 | 90 degrees | `(-CELL_SIZE/2 - 1.0, 0, 0)` |
| North | wall_straight_1x1 | 180 degrees | `(0, 0, CELL_SIZE/2 + 1.0)` |
| East | wall_straight_1x1 | 270 degrees | `(CELL_SIZE/2 + 1.0, 0, 0)` |

Wall offset values (the `1.0`) are derived from the golden layout wall placement patterns. The exact value is validated against the existing wrapper scene dimensions.

### Portal Placement

Portals replace wall segments where two connected rooms share an edge. A portal entry includes:
- `id`: descriptive name like `"east_to_corridor_01"`
- `wall`: which wall of the room the portal is on
- `module_id`: `"bulkhead_portal_2x1"`
- `position`: world-space position matching the wall slot
- `yaw_degrees`: matching the wall direction
- `replaced_wall_name`: the wall segment this portal replaces
- `span_cells`: 2 (portal covers 2 cells of wall space)

### Interior Zones

For each room, compute:
- `reserved_cells`: cells adjacent to portals (kept clear for navigation)
- `door_approach_cells`: cells the player walks through to reach doors
- `route_cells`: the union of door approach cells (the walkable path through the room)
- `wall_slots`: cells against walls available for prop/motif placement (cell + wall direction + yaw)
- `center_slots`: cells not against walls and not reserved (available for center-room props)

## Output Format

The `LayoutSerializer` assembles a Dictionary matching the golden `layout.json` schema (version 1.2.0 — the serializer's emitted version is canonical; `layout_schema_coherence_smoke` keeps the goldens in lockstep):

```json
{
  "schema_version": "1.2.0",
  "document_kind": "ship_layout",
  "program_id": "procgen-<archetype>-seed-<seed>",
  "kit_id": "ship_structural_v0",
  "design_intent": "procedurally generated <template_id> ship",
  "cell_size": 4.0,
  "rooms": [/* full room objects with structural_placements, wall_segments, portals, interior_zones */],
  "room_links": [/* open doorway connections between rooms */],
  "blocked_links": [],
  "vertical_connections": [/* ramps and elevators between decks */],
  "landmarks": [/* orientation beacons at hubs and destination */],
  "critical_path": [/* BFS shortest path from entry to destination */],
  "fire_zones": [],
  "arc_zones": [],
  "breach_zones": [],
  "prototype": {
    "start_room": "<entry_room_id>",
    "goal_room": "<destination_room_id>"
  }
}
```

### Empty Gameplay Arrays

Since this spec covers layout-only generation:
- `blocked_links`: empty array (future gameplay slice generator populates)
- `fire_zones`: empty array
- `arc_zones`: empty array
- `breach_zones`: empty array

### Populated Structural Arrays

- `room_links`: all open doorway connections (portal-based, structural)
- `vertical_connections`: ramp and elevator transitions between decks
- `critical_path`: BFS shortest path from entry to destination room
- `landmarks`: auto-placed orientation beacons (orange at first hub, green at destination)

### Motif Requests

Each room gets a default `motif_requests` array based on its role:
- airlock/dock: `["mot-airlock-entry-locker"]`
- corridor: `["mot-maintenance-workbench-corner"]`
- engineering: `["mot-engineering-console"]`
- Other roles: empty (future content)

## Vertical Connections

For the Stacked template (and optionally for Spine ships with deck transitions):

1. A `ramp` room (1x1 cell) is placed at the deck boundary. Its structural placement includes a `ramp_up_1x2` module.
2. An `elevator` room (1x1 cell) provides a second vertical transition. Its structural placement uses `floor_1x1` as the base module. If `elevator_shaft_1x1` is added to the structural kit in the future, the module ID can be updated without pipeline changes.
3. Each vertical connection gets an entry in `vertical_connections[]` with `from_cell`, `to_cell`, `from_room`, `to_room`, and `module_id`, matching the golden format.

## File Structure

### New Files

```
scripts/procgen/
  topology_template.gd       # TopologyTemplate data class
  template_selector.gd       # Picks template based on archetype/size/seed
  room_assigner.gd           # Fills template zones with rooms
  cell_layout_engine.gd      # Places rooms on 2D grid
  wall_door_resolver.gd      # Generates walls, portals, interior zones
  layout_serializer.gd       # Assembles layout.json Dictionary
  ship_layout_generator.gd   # Top-level orchestrator

data/procgen/templates/
  spine.json                  # Spine topology template
  bifurcated.json             # Bifurcated topology template
  stacked.json                # Stacked topology template
```

### Modified Files

- `ship_generator.gd` — Updated to use `ShipLayoutGenerator` pipeline. Its `generate()` method runs the new pipeline, produces a `layout.json` Dictionary, writes it to a temp file, and calls `GeneratedShipLoader.load_from_paths()`.

### Preserved Files (unchanged)

- `ship_blueprint.gd` — input data class
- `room_graph.gd` — used internally by `CellLayoutEngine`
- `generated_ship_loader.gd` — downstream consumer
- All golden layout files — reference implementations
- All existing validation smokes — should pass unchanged

## Testing Strategy

### Unit Smokes (one per pipeline stage)

- `template_selector_smoke.gd` — template selection is deterministic per seed
- `room_assigner_smoke.gd` — role distribution matches archetype weights, room counts within range
- `cell_layout_smoke.gd` — no overlapping cells, all rooms placed, grid connectivity
- `wall_door_resolver_smoke.gd` — complete wall coverage (no exposed edges without walls), portal placement at connections
- `layout_serializer_smoke.gd` — output schema matches golden layout structure
- `ship_layout_generator_smoke.gd` — end-to-end: seed produces layout.json that `GeneratedShipLoader` loads successfully

### Integration Tests

- Multi-seed stress test: generate 20 ships across all 3 templates, verify all load via `GeneratedShipLoader` and produce connected navigation meshes.
- Golden comparison: for a fixed seed, the generated layout should be stable across runs (determinism check).

### Regression

Existing golden layout smokes should continue to pass unchanged since the `GeneratedShipLoader` and golden data files are not modified.

## Non-Goals

- No gameplay slice generation (objectives, hazard placement, blocked routes)
- No new structural art assets or modules beyond the existing `ship_structural_v0` kit
- No changes to `GeneratedShipLoader`
- No changes to the player controller, camera, or interaction systems
- No runtime generation during gameplay (layouts are pre-generated and loaded from JSON)
