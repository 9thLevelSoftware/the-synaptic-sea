# Feature: Socketed Enclosed Interiors

## Status

Approved for implementation. RED enclosure smoke exists; live topology
construction and boundary compilation still fail it.

## Requirement cross-reference

- REQ-ENC-001..004 in `docs/game/05_requirements.md`
- ADR: `docs/game/adr/0053-socketed-enclosed-interiors.md`
- Related: ADR-0029 (extend the pipeline, do not replace loader/goldens),
  ADR-0051 (module grain), ADR-0052 (wrappers own sockets)
- Pipeline design this repairs:
  `docs/superpowers/specs/2026-06-20-procgen-layout-pipeline-design.md`

## Design pillar alignment

- Pillar: derelict exploration and salvage in enclosed, readable ship volumes.
- Why this feature supports it: a boarded wreck or hive cluster has to be a
  set of rooms the player can walk, seal, and strip. Floor plates in a line
  with nonsense walls are not that fantasy.

## Player fantasy

The player steps off the lifeboat into a real interior: bulkheads, doorways,
corners, and ceilings. Derelict wrecks feel like dead ships. Hive clusters
feel like the same ships overgrown — not a different generator, a different
kit on the same enclosed rooms.

## Gameplay problem

The live pipeline already has the right three-layer split (`layout.json`
schema 1.2.0 as the shared model, discrete topology and wall stages,
`GeneratedShipLoader` as geometry instantiation). It still produces
unenclosed decks because the **middle stages** do not consume kit sockets
and one live path still uses the legacy linear placer:

1. `CellLayoutEngine` emits occupancy footprints and adjacencies only.
2. `StructuralEdgeCompiler` (via `WallDoorResolver`) places
   `wall_straight_1x1` from occupancy-edge math and hardcoded `module_id`
   values. It never reads `ModularAssetSpec` sockets, never picks corner
   or junction modules, and never emits ceilings.
3. Kit contracts already declare `floor_edge`, `wall_end`, `portal_edge`,
   and corner vertices, but no GDScript reads `compatible_kinds`.
4. `LifeBoatBuilder.build()` still calls `StructuralPlacer`, which spaces
   rooms by `CELL_SIZE + ROOM_GAP` (6 m) so they never share edges.
5. `LifeBoatBuilder.build_layout()` writes one `floor_1x1` per room, empty
   `portals`, schema `1.1.0`, and no `structural_plan`.
6. `ShipLayoutGenerator._kit_id_for_biome` returns `ship_structural_v0`
   for every biome, so derelict / hive flavour cannot even remap stems.

Named themes "derelict wreck" and "hive cluster" are not kit ids. Closest
bindings: archetype `derelict` and biomes `abyssal_synaptic_sea`,
`breach_field`, `dead_fleet`. Hive / biomatter is encounter and dressing
flavour today (`biomatter_crusted`, `biomatter_lurker`), not a structural
kit. This feature makes enclosed rooms those kits can skin. It does not
invent unique hive meshes.

## Core behavior

Replace **only** topology construction and boundary compilation.

### Stage A — topology construction (replaces `CellLayoutEngine` algorithm)

Keep `TemplateSelector` and `RoomAssigner` as the mission / role graph
(the analog of a cyclic-graph first pass). Replace the greedy occupancy
placer so rooms grow from connector-compatible footprints:

- Every room is a 4-connected integer cell set on a 4 m grid.
- Declared template connections become shared cardinal edges (or
  vertical connections), never `ROOM_GAP` spacing.
- Output shape stays the current cell-grid contract: `rooms` with
  `cells` / `footprint` / `deck` / `role`, plus `adjacencies` with
  real shared-edge endpoints.
- Same seed still produces the same occupancy.

Do not adopt a ground-up 3D WFC generator. Research for enclosed
modular interiors is socketed assembly and connector-grown authored
rooms on top of a separate topology model. This repo already has that
split. A method that cannot emit integer occupancy cells and canonical
shared edges cannot feed `layout.json` or `GeneratedShipLoader`.

### Stage B — socketed boundary compilation (replaces `StructuralEdgeCompiler` algorithm)

Keep the `structural_plan` keys the loader already consumes
(`occupancy`, `edges`, `placements`, `floor_placements`). Change how
`module_id` is chosen:

- Load wrapper contracts from
  `data/placement/contracts/structural/<kit_id>/`.
- Place one floor per occupied cell by matching `floor_edge` sockets.
- Place one ceiling per occupied cell (`ceiling_cap_1x1` or kit remap)
  unless the cell is an authored vertical opening.
- Place wall, portal, or OPEN on each canonical shared edge by matching
  `wall_end` / `portal_edge` / `wall_base` sockets — not a hardcoded
  `WALL_MODULE`.
- Place inner/outer corner (and T-junction) modules at vertices where
  those contracts match.
- Record `socket_bindings` on every placement: local socket id, neighbor
  placement id, neighbor socket id, `kind`.
- `WallDoorResolver` stays a compatibility adapter to the legacy
  per-room geometry shape. It must not become a second compiler.

### Hub / lifeboat

`LifeBoatBuilder.build_layout()` emits schema 1.2.0 with stamped cells,
portals on the two real shared edges, and a compiler-produced
`structural_plan`. `LifeBoatBuilder.build()` instances that plan (same
loader path as derelicts) and stops calling `StructuralPlacer`.
`StructuralPlacer` remains debug-only; its smoke stays an allowlisted
legacy diagnostic until deleted.

### Loader, goldens, schema

`GeneratedShipLoader` may gain an additive loop over
`structural_plan.ceiling_placements` using the existing
`module_id → wrapper` instantiation. It must not solve topology or
sockets. `layout.json` schema_version stays `1.2.0`. New fields live
**inside** `structural_plan` so `layout_schema_coherence_smoke` does not
force a top-level key bump. Goldens are upgraded by hand in the same
change that tightens `StructuralPlanValidator` — never pipeline-regenerated.

## Socket contract the compiler must consume

Canonical kinds (kit contracts already use most of these names; this
feature makes them runtime-authoritative):

| Kind | Who owns it | Compatible with | Use |
|---|---|---|---|
| `floor_edge` | floor / corridor floor | `floor_edge`, `corridor_edge`, `wall_base` | Cardinal cell-edge in XZ at floor height |
| `corridor_edge` | corridor floor | `floor_edge`, `corridor_edge`, `wall_base` | Same as `floor_edge` for corridor stems |
| `wall_base` | wall / portal | `floor_edge`, `corridor_edge` | Wall sits on a floor edge |
| `wall_end` | wall / end cap | `wall_end`, `wall_edge`, `portal_edge` | Continue a wall run or meet a portal |
| `wall_edge` | wall run | `wall_end`, `portal_edge` | Alias accepted on wall-end compatibility |
| `portal_edge` | doorway / bulkhead / pressure door | `portal_edge`, `wall_end`, `wall_edge` | Stitch a portal into a wall run |
| `portal_center` | doorway leaf | `portal_center` | Door slab / blockage, not a room closer |
| `inner_corner_vertex` | inner corner | `inner_corner_vertex` | Concave room corner |
| `outer_corner_vertex` | outer corner | `outer_corner_vertex` | Convex hull corner |
| `ceiling_edge` | ceiling cap | `ceiling_edge` | Cardinal ceiling rim |
| `floor_top` | floor | `ceiling_bottom` | Vertical close of the cell volume |
| `ceiling_bottom` | ceiling cap | `floor_top` | Vertical close of the cell volume |

Contract amendments required before the compiler can be honest (current
JSON is unused and, for floors, mis-authored):

1. Floor cardinal sockets live in XZ at cell-edge, Y = 0. With
   cell-center origin and north = −Z (matching `StructuralEdgePlan`
   `DIRECTIONS.north = (0, -1)`): north `[0, 0, -2]`, south `[0, 0, 2]`,
   east `[2, 0, 0]`, west `[-2, 0, 0]`. Today's `floor_edge_north_01` at
   `[0, 2, 0]` is +Y and is not a north edge.
2. `floor_edge.compatible_kinds` must include `wall_base`.
3. `wall_straight_1x1` (and portal frames) must declare `wall_base`.
4. `ceiling_cap_1x1` must declare `ceiling_edge` on four cardinals plus
   `ceiling_bottom`. Today's sole `prop_anchor` is not an enclosure socket.
5. Wrapper visual swaps must not change socket transforms (ADR-0052).

A pair matches when each socket's `kind` is in the other's
`compatible_kinds` (or kinds are equal) and their world positions agree
within the 4 m grid snap after yaw.

## Inputs

- `ShipBlueprint` + archetype + biome/difficulty ids (existing).
- Topology templates under `data/procgen/templates/`.
- Kit JSON under `data/kits/` and wrapper contracts under
  `data/placement/contracts/structural/`.
- Hand-authored goldens for schema lock.

## Outputs

- `layout.json` 1.2.0 with occupancy-stamped rooms, portals on real
  shared edges, and a `structural_plan` that includes floors, walls,
  portals, ceilings, corners, and `socket_bindings`.
- Scene: watertight wrapper instances from `GeneratedShipLoader`.
- Hub craft: same enclosure contract as derelicts.

## Rules

1. Resources are data; the two replaced stages stay pure `RefCounted`.
   Scene instantiation stays in `GeneratedShipLoader`.
2. Occupancy cells remain the unit of floors and nav. Destruction stays
   module-grained (ADR-0051). No voxel hull.
3. Adjacent rooms share a cardinal cell edge. `ROOM_GAP` is forbidden on
   every live path.
4. A room is enclosed when every occupied cell has a floor and a ceiling
   (unless an authored vertical opening) and every exterior edge is a
   wall or portal chosen by socket match.
5. Same `(seed, archetype, biome, difficulty)` remains byte-stable under
   `SeedDeterminismContract`.
6. Biome kit selection may remap stems (`ship_structural_hazard`,
   `ship_structural_industrial`) but must not invent geometry the
   sockets do not describe.
7. Unexpected Godot `ERROR:` / `WARNING:` lines still block completion.

## Non-goals

- New art beyond existing `ship_structural_v0` stems and the already
  authored hazard / industrial kit remaps.
- A new `layout.json` schema, a new loader, or regenerating goldens from
  the pipeline.
- Full 3D Wave Function Collapse as the topology solver.
- Voxel or CSG interiors.
- Hive-specific meshes, biomatter growth simulation, or encounter
  runtime (encounter markers stay `EncounterInjector`).
- Rewriting `TemplateSelector`, `RoomAssigner`, `GameplaySliceBuilder`,
  or `ShipNavGraph`.
- Deleting `StructuralPlacer` in this feature (retire live callers only).

## Technical design

Allowed implementation files:

- `scripts/procgen/cell_layout_engine.gd` — connector-growth algorithm
  behind the existing `layout()` contract.
- `scripts/procgen/structural_edge_compiler.gd` — socketed module choice;
  keep occupancy / edge identity helpers.
- `scripts/procgen/structural_plan_validator.gd` — require ceilings,
  socket bindings, and no floor-only rooms.
- `scripts/procgen/wall_door_resolver.gd` — adapter only.
- `scripts/procgen/life_boat.gd` — compiler-backed layout; stop calling
  `StructuralPlacer`.
- `scripts/procgen/ship_layout_generator.gd` — stamp / kit_id only as
  needed for the compiler.
- `scripts/procgen/modular_socket_catalog.gd` (new) — load contracts,
  answer compatible pairs.
- `scripts/placement/modular_asset_spec.gd` — no gameplay expansion;
  catalog reads the existing Resource / JSON.
- `data/placement/contracts/structural/ship_structural_v0/*.json` —
  socket axis and compatibility amendments.
- `scripts/procgen/generated_ship_loader.gd` — additive
  `ceiling_placements` instance loop only.
- `data/procgen/golden/*/layout.json` — hand-upgrade `structural_plan`
  additive fields when the validator tightens.
- `scripts/validation/socketed_enclosure_smoke.gd` — RED now, GREEN on
  completion.
- `docs/game/06_validation_plan.md` — register the smoke in the
  regression bundle only after GREEN.

## Acceptance criteria

- Given a derelict seed, when the pipeline runs, then every occupied
  cell has a floor and a ceiling, every exterior edge is a wall or
  portal, and adjacent rooms share a cardinal cell edge.
- Given two rooms that the template connects, when topology construction
  finishes, then their footprints touch on a shared edge (no 6 m gap).
- Given a placed wall, floor, or portal, when the compiler emits it,
  then `socket_bindings` names a compatible pair from the kit contracts.
- Given a convex or concave vertex, when the boundary compiles, then a
  corner module is used instead of two overlapping `wall_straight_1x1`
  plates.
- Given `LifeBoatBuilder.build_layout()`, when it is loaded, then it has
  schema 1.2.0, a validated `structural_plan`, and the same enclosure
  rules as a derelict.
- Given `LifeBoatBuilder.build()`, when it returns a Node3D, then it did
  not call `StructuralPlacer.place_structure`.
- Given goldens `coherent_ship_001/002/003`, when the loader runs, then
  they still load; any additive `structural_plan` fields were upgraded
  by hand.
- Given the enclosure smoke, when implementation is done, then it prints
  `SOCKETED ENCLOSURE PASS` and is added to the regression bundle.

## Validation

RED command (expected to fail until the two stages are replaced):

```bash
GODOT="C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe"
ROOT="D:/the-synaptic-sea"
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/socketed_enclosure_smoke.gd
```

Expected while RED: `SOCKETED ENCLOSURE FAIL` with at least one of
`floor_only`, `room_gap`, `sockets_unused`, `no_ceilings`,
`no_corners`, `floor_socket_axes`, `hub_plan_missing`. Exit code is not
the contract; the FAIL marker and the absence of PASS are.

Expected when GREEN:

`SOCKETED ENCLOSURE PASS no_floor_only=true no_room_gap=true sockets_consumed=true watertight=true corners_used=true floor_socket_axes=true hub_plan=true`

Regression bundle (after GREEN only): the same command plus the existing
procgen cluster (`wall_door_resolver_smoke`, `cell_layout_engine_smoke`,
`layout_serializer_smoke`, `ship_layout_generator_smoke`,
`seed_determinism_smoke`, `layout_schema_coherence_smoke`,
`structural_live_loader_smoke`, `procgen_quality_gate_smoke`).

## Risks

- Tightening `StructuralPlanValidator` without hand-upgrading goldens
  breaks `GeneratedShipLoader` on curated ships. Mitigation: additive
  fields inside `structural_plan`; goldens upgraded in the same change.
- Socket axis correction can shift wrapper pivots. Mitigation: contracts
  change metadata; wrapper collision proxies stay authoritative;
  `floor_wrapper_collision_footprint_smoke` stays green.
- Connector-growth can break seed hashes. Mitigation: `seed_determinism_smoke`
  is part of the completion bundle; hash pin updates only with a recorded
  algorithm change.
- Theme kits still all resolve to `ship_structural_v0`. Mitigation:
  enclosure is the blocker; biome `kit_id` selection is REQ-ENC-004
  should-priority, not a geometry blocker.

## ADRs

- `docs/game/adr/0053-socketed-enclosed-interiors.md` (this feature)
- `docs/game/adr/0029-procedural-generation-expansion-architecture.md`
- `docs/game/adr/0051-module-integrity-not-voxels.md`
- `docs/game/adr/0052-asset-metadata-and-visual-binding-architecture.md`
