# Feature: Compiler-true walkability and standing nav

## Status

In implementation

## Design pillar alignment

- Pillar: derelict exploration in enclosed, walkable ship volumes.
- Why this feature supports it: enclosure geometry is not play until the player capsule cannot walk through compiler walls, off the deck, or through a locked door, and threats path the same standing graph.

## Player fantasy

The boarded wreck is a set of rooms the standing player can actually walk. Locked bulkheads stop you. Open doorways let a suited body through. You do not clip a wall or step into the void.

## Gameplay problem

Walkability smoked occupancy BFS over non-`SOLID` edges and a floor-polygon `NavigationAgent3D`. `ShipNavGraph` 4-connected floor modules and never read compiler kinds. `LOCKED` flooded as walkable. Quality-gate start→goal tunneled walls.

## Core behavior

Two occupancy floods share compiler occupancy:

- Enclosure: kind != `SOLID` (includes `LOCKED`, `BREACH`); all occupied cells. Validator portal-endpoint and `critical_path` stay here.
- Standing-play: `OPEN` / `DOOR` / `HATCH` plus `layout.vertical_connections`; start→goal only.

`ShipNavGraph.build_from_layout` uses `structural_plan` occupancy and edges when present. Standing costs: `OPEN`/`DOOR` 1.0, `HATCH` 1.15, `LOCKED`/`BREACH` `BLOCKED_COST` (edge kept). `SOLID` omitted. `blocked_links` overlay `BLOCKED_COST` even if the stored kind is `DOOR`. Vertical edges only from `vertical_connections`.

Walkability Stage A (pure): enclosure flood, standing start→goal, SOLID capsule sweep must hit 0.20 m extruded slab, DOOR must pass 0.80×1.70 opening, LOCKED must not, standing-path cells have floors.

## Inputs

- Validated `structural_plan` occupancy and edges (`SOLID|OPEN|DOOR|LOCKED|HATCH|BREACH`)
- `layout.vertical_connections`, `layout.blocked_links`
- Player capsule numbers in `walkability_contract.gd`

## Outputs

- Standing `ShipNavGraph` used by threats and quality-gate
- Walkability PASS flags: `compiler_walls`, `doorway`, `no_void`, `no_wall_through`, `nav_kinds`

## Rules

1. Enclosure flood and standing-play flood are different predicates.
2. `LOCKED` / `BREACH` stay in `_base_edges` at `BLOCKED_COST`. No `unlock_edge`.
3. Never infer vertical edges by `dy == deck_height`.
4. Do not regenerate goldens; overlay `blocked_links` at graph build.
5. NavigationAgent is not the PASS contract.

## Non-goals

- Wrapper collision retune (later card)
- Layout mutators / live `LOCKED` stamping
- Hive template
- `scripts/main.gd` hub boot
- Unlock / door-hack API
- Crouch as a smaller live capsule

## Technical design

- `scripts/procgen/walkability_contract.gd`
- `scripts/systems/ship_nav_graph.gd`
- `scripts/procgen/structural_plan_validator.gd` (enclosure flood stays non-SOLID)
- `scripts/procgen/structural_edge_compiler.gd` (live blocked_link → LOCKED kind)
- Smokes: `procgen_walkability_smoke.gd`, `ship_nav_graph_smoke.gd`, `procgen_quality_gate_smoke.gd`
- ADR-0054, REQ-WALK-001

## Acceptance criteria

- Given spine seed 42, when Stage A runs, then enclosure reaches all occupied cells and standing-play reaches start→goal without 100% occupancy.
- Given a SOLID compiler edge, when a standing capsule sweeps cell-center to neighbor-center, then it hits the 0.20 m extruded slab.
- Given a DOOR edge, when the same sweep runs, then it threads a 0.80×1.70 opening; LOCKED does not.
- Given `coherent_ship_001` shortcut `spine_01`→`reactor_01` cells `[8,1,1]`→`[9,1,1]`, when the standing graph builds, then that hop is blocked or has no neighbor, and airlock→corridor still paths.
- Given a stacked-template layout, when the graph builds, then at least one vertical `_base_edges` hop exists and start→goal still paths.
- Given a quality-gate seed whose standing start→goal needs 4-connect around SOLID/LOCKED, when the gate runs, then the seed fails.

## Validation

```
GODOT="C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe"
ROOT="<project root>"
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/procgen_walkability_smoke.gd
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ship_nav_graph_smoke.gd
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/procgen_quality_gate_smoke.gd
```

Expected: `WALKABILITY PASS spine_seed_42 compiler_walls=true doorway=true no_void=true no_wall_through=true nav_kinds=true`

## Risks

- Using one flood for both predicates fails wrecks with locked rooms.
- Zero-thickness contract AABB makes `no_wall_through` vacuously true — extrusion is mandatory.
- Dropping proximity verticals drops stacked nav unless `vertical_connections` are added.

## ADRs

- ADR-0054 compiler-edge nav and walkability
- ADR-0049 threat pathfinding (amended)
- ADR-0053 socketed enclosed interiors (consumed)
