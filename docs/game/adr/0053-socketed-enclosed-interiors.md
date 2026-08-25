# ADR-0053: Stage-only replacement of topology construction and boundary compilation

- **Status:** Accepted
- **Date:** 2026-08-22
- **Supersedes / amends:** none. Extends ADR-0029 ("extend, do not replace")
  to the two middle stages. Does not reopen ADR-0051 (module grain) or
  ADR-0052 (wrappers own sockets).
- **Related:** feature `docs/game/features/socketed_enclosed_interiors.md`;
  REQ-ENC-001..004; pipeline design
  `docs/superpowers/specs/2026-06-20-procgen-layout-pipeline-design.md`

## Context

Enclosed interiors from prebuilt modular kits are solved in current
literature as a geometry pass on top of a separate topology model:
socketed 3D WFC, six-direction example-based model synthesis, and
connector-grown authored rooms. A typical constructive method has a
representational model, a method that constructs that model, and a
separate method that instantiates geometry.

This game already has that split:

- `layout.json` schema 1.2.0 is the shared model. Procgen and hand-authored
  goldens use it. `GeneratedShipLoader` loads both identically.
- The loader is only instantiation. It requires a validated
  `structural_plan` and instances wrappers by `module_id`.
- Topology construction (`CellLayoutEngine`) and boundary compilation
  (`StructuralEdgeCompiler`, with `WallDoorResolver` as a compatibility
  adapter) are already discrete stages.

Floor-only decks and nonsense walls are not evidence that this architecture
is missing. They come from still-live middle-stage algorithms:

- Occupancy-only layout that does not grow rooms from connectors.
- Occupancy-edge compilation that hardcodes `wall_straight_1x1` /
  `doorway_frame_open_1x1` and never reads kit sockets.
- Unused socket contracts, including mis-authored floor cardinals
  (`floor_edge_north_01` at `[0, 2, 0]` is +Y, not north).
- `LifeBoatBuilder` still calling `StructuralPlacer` (`CELL_SIZE + ROOM_GAP`
  = 6 m) and writing floor-only `build_layout()` JSON.

A ground-up generator would discard the schema lock, the goldens, the
loader, module integrity, and regenerate-from-seed persistence at once.
When the prior generator was replaced, loader and goldens were preserved.
That remains the viable path.

No 2024–2026 source inspected for this decision showed locked-isometric,
cell-scale WFC assembling fully enclosed multi-room interiors from a
prebuilt kit. Infinigen Indoors encloses rooms with fully procedural
meshes, not this tileset. CEIG 2025 wall sockets are demonstrated on
outdoor isometric terrain. Those methods are not a drop-in replacement
for an occupancy-cell / `structural_plan` contract.

## Decision

**Replace the algorithms of topology construction and boundary compilation
only.** Do not replace `layout.json`, `LayoutSerializer` top-level keys,
`GeneratedShipLoader` (beyond an additive ceiling instance loop), or the
hand-authored goldens' curated content.

### 1. Topology construction

`CellLayoutEngine.layout()` keeps its output contract (integer occupancy
cells, 4-connected room footprints, adjacencies on real shared cardinal
edges). The greedy linear placer is replaced by connector-growth from the
existing template graph (`TemplateSelector` + `RoomAssigner` remain the
mission / role pass).

Forbidden on every live path: `ROOM_GAP`, placing rooms as disconnected
floor lists, inventing portals between non-touching rooms.

### 2. Boundary compilation

`StructuralEdgeCompiler.compile()` keeps occupancy keys, canonical
`edge_key` identity, and the plan keys the loader already reads
(`occupancy`, `edges`, `placements`, `floor_placements`). Module choice
changes:

- Load `ModularAssetSpec` JSON for the layout `kit_id`.
- Match sockets from the table in
  `docs/game/features/socketed_enclosed_interiors.md`.
- Emit ceilings, corner / junction modules, and `socket_bindings`.
- Stop using hardcoded `WALL_MODULE` / `DOOR_MODULE` as the only stems.

`WallDoorResolver` remains an adapter. `StructuralPlanValidator` gains
fail-closed checks for ceilings, socket bindings, and floor-only rooms.

New plan fields stay **inside** `structural_plan` so schema_version stays
`1.2.0` and `layout_schema_coherence_smoke` does not require a top-level
key bump. Goldens are upgraded by hand when the validator tightens.

### 3. Hub path

`LifeBoatBuilder` uses the same compiler and loader contract.
`StructuralPlacer` is not a valid structural compiler. Live callers of
`place_structure()` are removed. The class may remain for the existing
debug smoke until a later deletion card.

### 4. What is not chosen

| Option | Why rejected |
|---|---|
| Ground-up WFC / new generator | Breaks schema, goldens, loader, integrity, save model; no published locked-iso enclosed-kit result to copy |
| Voxel or CSG interiors | ADR-0051 |
| Keep occupancy-edge hardcoded modules and "add walls later" | Walls without socket match are the current failure |
| Theme-specific hive geometry generator | Kits remap stems; hive art is out of scope |
| Regenerating goldens from the pipeline | Goldens are curated schema locks (fire-zone markers, authored routes) |

## Consequences

- Implementation is two stage replacements plus hub rewiring, not a new
  procgen stack.
- Socket JSON must be amended (axes and `compatible_kinds`) before the
  compiler can consume it honestly.
- `GeneratedShipLoader` instances `ceiling_placements` the same way it
  instances floors and edges.
- Seed hashes in `seed_determinism_smoke` will change when the placer
  algorithm changes; the pin updates in the same implementation card.
- Biome `kit_id` still collapsing to `ship_structural_v0` is a follow-up
  (REQ-ENC-004), not a reason to keep floor-only rooms.

## What agents must not do

- Introduce a second layout schema or a second loader path for derelicts
  vs hub.
- Solve sockets inside `GeneratedShipLoader`.
- Treat `StructuralPlacer` as production geometry.
- Re-litigate voxel interiors or a wholesale WFC rewrite without a new
  ADR that supersedes this one.

## Validation

- RED: `scripts/validation/socketed_enclosure_smoke.gd` prints
  `SOCKETED ENCLOSURE FAIL` until the two stages and hub path comply.
- GREEN: same smoke prints `SOCKETED ENCLOSURE PASS` with the flags in
  the feature spec, then joins the regression bundle in
  `docs/game/06_validation_plan.md`.
- Existing procgen smokes stay green, including
  `layout_schema_coherence_smoke`, `structural_live_loader_smoke`, and
  `wall_door_resolver_smoke`.
