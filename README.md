# Derelict WorldGen v2

Deterministic procedural derelict ships for an isometric Godot game. Version 2
makes authored topology and its compiled structural plan the source of truth;
the raster deck view is a projection of that plan, not the input to it.

The generator is pure Rust (derelict_core) with a headless CLI and an optional
Godot 4 GDExtension bridge. The exported documents are the contract consumed
by The Synaptic Sea's GeneratedShipLoader.

## Repository layout

| Path | Purpose |
|---|---|
| crates/derelict_core | Deterministic v2 generator, topology, structural compiler, validator, and exporters. |
| crates/derelict_cli | Headless ASCII/PNG renderer, export command, benchmark, and stress gate. |
| crates/derelict_godot | Thin gdext bridge exposing DerelictGenerator. |
| godot/ | Standalone Godot project with the Derelict addon and smoke tests. |
| scripts/build_windows.ps1 | Builds and installs the native GDExtension for the local Godot addon. |
| [MIGRATION.md](MIGRATION.md) | v1 → v2 cutover notes and schema changes. |

## Requirements

- Rust stable (the repository is developed on Rust 1.97).
- Godot 4.3 or newer (godot/project.godot declares compatibility_minimum = 4.3).

## Quick start

~~~powershell
# Core and contract tests; no Godot installation is required.
cargo test

# Inspect a generated ship in the headless renderer.
cargo run -p derelict_cli -- --seed 12 --archetype frigate --intactness 0.3 --all-decks

# Export The Synaptic Sea documents.
cargo run -p derelict_cli -- --seed 17 --archetype corvette --export-dir target/export --kit-id ship_structural_v0

# Run the full deterministic acceptance sweep (1,800 ships).
cargo run -p derelict_cli --release -- --stress

# Build the Rust GDExtension, then open godot/project.godot.
powershell -File scripts\build_windows.ps1
~~~

The CLI also supports --out <path> for a top-down PNG, --deck <n> or
--all-decks, --sweep <count>, and --bench. --archetype accepts the embedded
shuttle, corvette, freighter, and frigate definitions.

Headless Godot verification:

~~~powershell
godot --headless --path godot -s tests/smoke.gd
~~~

## The v2 pipeline

Every stage uses a named deterministic RNG stream. Ordered maps and integer
decision math keep output stable for a fixed seed, parameters, and
GENERATOR_VERSION.

### 1. Authored topology

Archetype RON files select a topology template and role policy. The topology
stage places explicit RoomSpec occupancy cells, authored PortalIntent edges,
and VerticalConnection openings on the rolled hull. Templates live in
crates/derelict_core/assets/topology_templates; archetypes live in
crates/derelict_core/assets/archetypes.

Topology is authoritative: a room owns its integer cells, a portal names both
endpoint cells and its state (Door, Locked, Hatch, or Breach), and a vertical
connection names the cells that remain open between decks. The compiler never
reconstructs rooms from a raster image after the fact.

### 2. Structural plan compilation

structural::compile turns the authored topology into the canonical
StructuralPlan:

- occupancy records and one floor placement per occupied cell;
- ceilings everywhere except authored vertical openings;
- one canonical record per geometric shared edge (edge_key), so shared
  boundaries cannot be emitted twice;
- materialized wall, door, locked-door, hatch, and vertex placements;
- socket bindings derived from placement adjacency.

The compiler selects module ids through a ModulePicker. The default picker
uses the stable ids expected by the game kits (floor_1x1, corridor_floor_1x1,
ceiling_cap_1x1, wall/door/portal variants, and the corner/T-junction
variants). Socket-catalog helpers in structural::sockets can check those
choices against real kit contracts.

### 3. Fail-closed validation

structural::validate has no warning tier: any compiler diagnostic or invariant
violation rejects the candidate. Checks include occupancy/floor round-trips,
ceiling openings, socket bindings, edge placement bijection and poses, portal
reciprocity, enclosure, flood-fill reachability, and the critical path.

Validation runs twice:

1. **Pre-damage** — the complete ship and critical path must be connected.
2. **Post-damage** — each surviving fragment must be internally connected;
   critical-path severing is accepted only when the selected story permits a
   fragment split.

Topology and damage have bounded deterministic retries. If no candidate passes,
generation returns a GenError instead of exporting a partial plan.

### 4. Damage, projection, and gameplay data

Damage mutates topology, recompiles, and validates again. Cosmetic decals and
DamageVariant values are overlays on the validated plan. The final plan is
projected to the Godot-friendly per-deck raster (DeckLayer) and assembled with
room graph, entities, damage events, fragments, and seeded loot.

## Export contract

The CLI writes two files when --export-dir <directory> is supplied:

- layout.json — schema 1.2.0, including generator metadata, kit_id, rooms,
  portals, vertical connections, critical path, and the embedded structural_plan
  (occupancy, edges, placements, floor/ceiling placements, and socket_bindings).
- gameplay_slice.json — schema 1.1.0, including start/goal rooms, critical path,
  reach-goal objective, and seeded loot-container descriptors.

Both documents are serialized from the same generated Ship. --kit-id stamps the
consuming kit id into layout.json; wrapper scenes are resolved by the consumer
from that kit's JSON catalog. The Rust exporter does not copy game assets into
this repository.

Example:

~~~powershell
cargo run -p derelict_cli -- --seed 23 --archetype frigate --intactness 0.1 --kit-id ithappy_scifi_v0 --export-dir target/ithappy_frigate
~~~

The ithappy_scifi_v0 catalog currently contains all 15 structural module
records used by The Synaptic Sea. The v2 compiler's emitted module ids are a
subset of that catalog; the loader still preflights every module id before
instancing a ship.

## GDExtension API

crates/derelict_godot exposes a RefCounted class named DerelictGenerator
through godot/addons/derelict/derelict.gdextension:

~~~gdscript
var generator := ClassDB.instantiate("DerelictGenerator")
var site_seed: int = generator.derive_site_seed(world_seed, world_x, world_y)

var ship: Dictionary = generator.generate(site_seed, {
    "archetype_id": "frigate",
    "intactness_override": 600,
})

var request_id: int = generator.generate_async(site_seed, {"archetype_id": "corvette"})
# In _process: null while running, then a ship Dictionary or {"error": ...}.
var result: Variant = generator.poll_async(request_id)
~~~

Methods:

- generate(seed, params) — synchronous ship generation. Supported parameter
  keys are archetype_id, optional intactness_override (0..=10000 bp),
  cause_override, and loot_richness.
- generate_async(seed, params) / poll_async(request_id) — background generation
  with the same result shape.
- derive_site_seed(world_seed, world_x, world_y) — discovery-order-independent
  site seed for co-op derivation.
- archetypes() — embedded archetype ids.
- item_catalog() — embedded item id/name catalog.
- generator_version() — the current GENERATOR_VERSION.
- export_layout_json(seed, params, kit_id) — pretty layout.json text (empty on
  failure; details are sent to the Godot error log).
- export_gameplay_slice_json(seed, params) — matching gameplay-slice text.

Ship dictionaries include per-deck PackedInt32Array layers plus room graph,
entities, damage events, and fragments for the Godot addon.

## The Synaptic Sea integration

The exported files are designed for the game's
GeneratedShipLoader.load_from_paths(layout_path, kit_path,
gameplay_slice_path, is_away):

~~~gdscript
var loader := GeneratedShipLoader.new()
var ok := loader.load_from_paths(
    "D:/world_gen/target/export/layout.json",
    "res://data/kits/ithappy_scifi_v0.json",
    "D:/world_gen/target/export/gameplay_slice.json",
    true,
)
~~~

The loader validates the exported plan again, maps every module_id to a
wrapper scene from the kit catalog, preflights wrapper resources, then builds
the structural scene, navigation, vertical links, objectives, and loot
descriptors. A missing file, malformed document, invalid plan, or missing
wrapper fails the load instead of producing a partial ship.

For the standard kit use res://data/kits/ship_structural_v0.json; for the
representative art probe use res://data/kits/ithappy_scifi_v0.json and stamp
--kit-id ithappy_scifi_v0 in the export. The worldgen-owned
scripts/worldgen_v2_visual_probe.gd accepts WORLDGEN_KIT_PATH for this choice
while retaining the standard-kit default.

## Determinism and migration

generate_ship(seed, params, data) is byte-identical for a fixed
GENERATOR_VERSION. If a deliberate output change is made, bump the version in
model.rs and update the golden hashes in the same commit:

~~~powershell
UPDATE_GOLDEN=1 cargo test -p derelict_core --test golden
~~~

v2 is a full cutover: the same seed does not reproduce a v1 ship. Read
[MIGRATION.md](MIGRATION.md) before loading existing saves or consuming old role/archetype
names. Mutation diffs remain forward-tolerant because unknown entity ids are
skipped during re-application.

## Persistence and co-op

The base ship is regenerated from (seed, params, generator_version); only the
mutation diff is persisted. ShipPersistence stores changed doors, inventories,
and removed entities under user://derelicts/<site_id>.json. The same diff can
be sent through a host-authoritative RPC path and applied on each peer after
deterministic regeneration.
