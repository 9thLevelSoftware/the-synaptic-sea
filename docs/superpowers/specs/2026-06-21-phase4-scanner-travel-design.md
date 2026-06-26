# Phase 4 — Scanner & Travel Design

Date: 2026-06-21
Status: Approved for implementation
Parent spec: `docs/superpowers/specs/2026-06-20-synapse-sea-core-systems-design.md` (System 4 + System 8)
Integrates: Phase 2 ship systems (`ShipSystemsManager`), Phase 3 progression (`scanner_operation` skill), procgen (`ShipGenerator.generate_from_seed`)

---

## Goal

Build the deterministic logic for ship discovery and menu travel: a procedurally generated,
infinite Synapse Sea of ship markers; a scanner whose reach/detail is gated by the ship's
navigation/scanners systems and the player's `scanner_operation` skill; and a travel/docking action
that materializes a real ship from a marker's seed via the existing procgen pipeline.

## Scope & boundary

- **Pure deterministic `RefCounted` models** in `scripts/systems/*` + headless smokes. No live UI
  (scanner screen / travel menu / docking animation are deferred to a later visual pass).
- **End-to-end proof:** a headless smoke drives scan → select marker → `generate_from_seed` → a real
  ship `Node3D`.
- **No `RunSnapshot` integration this phase.** Each model exposes `get_summary`/`apply_summary`
  (round-trip validated by smokes), but wiring the Synapse Sea world into a save belongs to a later
  world↔slice integration: the current `RunSnapshot` is the *single-ship-slice* save, and the
  meta-world that wraps it does not exist yet. No `RunSnapshot`/ADR/`summaries` churn here.
- **No coordinator (`PlayableGeneratedShip`) changes.** Phase 4 sits above the single-ship slice; it
  is validated standalone.

### Out of scope (deferred)

Live scanner/travel UI + docking animation; fuel/time/risk travel economy (Phase 6 resources);
`RunSnapshot`/meta-save integration; rich loot/tech scanner fields (need richer ship data);
ship-in-ship docking (Phase 5).

---

## Architecture

```
ShipMarker (RefCounted, pure data)        scripts/systems/ship_marker.gd
MarkerGenerator (RefCounted, deterministic) scripts/systems/marker_generator.gd
Synapse SeaWorld (RefCounted)                scripts/systems/synapse_sea_world.gd
ScannerState (RefCounted)                 scripts/systems/scanner_state.gd
TravelController (RefCounted)             scripts/systems/travel_controller.gd
```

All deterministic; no RNG except seeded `RandomNumberGenerator`. No `Time`/`Math.random` (headless
determinism). Enums mirror `ShipBlueprint` (`Size`: LIFE_BOAT=0/SMALL=1/MEDIUM=2;
`Condition`: PRISTINE=0/DAMAGED=1/WRECKED=2).

### `ShipMarker`

```gdscript
var marker_id: String      # stable: "%d:%d:%d" % [cell.x, cell.y, index]
var position: Vector3      # in Synapse Sea space
var size_class: int        # ShipBlueprint.Size
var condition: int         # ShipBlueprint.Condition
var ship_type: String      # flavor: "shuttle"/"freighter"/"science_vessel"/"derelict_hauler"
var seed_value: int        # deterministic ship-generation seed
func to_dict() -> Dictionary
static func from_dict(d: Dictionary) -> ShipMarker
```

`distance` is derived against the player position by `Synapse SeaWorld`, never stored.

### `MarkerGenerator` (deterministic, infinite)

```gdscript
const CELL_SIZE := 100.0          # Synapse Sea-space units per grid cell
const MARKERS_PER_CELL := 3       # markers placed per cell

## Markers for one integer grid cell. Same (world_seed, cell) -> identical markers.
func markers_for_cell(world_seed: int, cell: Vector2i) -> Array   # Array[ShipMarker]

static func cell_seed(world_seed: int, cell: Vector2i) -> int     # stable spatial hash
```

`cell_seed` uses a fixed spatial hash (not `hash()`): `world_seed ^ (cell.x * 73856093) ^
(cell.y * 19349663)`. A `RandomNumberGenerator` seeded with `cell_seed` then places each marker:
position within the cell (x,z in world units; y=0 — Synapse Sea travel is planar), `seed_value` from
`rng.randi()`, and `size_class`/`condition`/`ship_type` from weighted picks. Marker grid is the X–Z
plane (locked-iso convention); `position.y` is always 0.

### `Synapse SeaWorld`

```gdscript
var world_seed: int
var player_position: Vector3
var generated_marker_ids: Dictionary   # marker_id -> true (locked-in ships)

func _init(p_world_seed: int, p_player_position := Vector3.ZERO)

## Distinct markers whose distance from player_position <= radius, sorted ascending by distance.
## Queries every cell overlapping the radius bounding box, dedupes by marker_id.
func markers_in_range(radius: float) -> Array            # Array[ShipMarker]

func mark_generated(marker_id: String) -> void
func is_generated(marker_id: String) -> bool
func set_player_position(pos: Vector3) -> void
func get_summary() -> Dictionary                         # {world_seed, player_position:[x,y,z], generated_marker_ids:[...]}
func apply_summary(summary: Dictionary) -> bool
```

`markers_in_range` is deterministic: it regenerates the cells in range each call (markers are not
stored), so the world is stateless apart from `world_seed`/position/generated set.

### `ScannerState`

```gdscript
const MAX_DETAIL := 6
var range_radius: float = 250.0    # spatial reach (covers ~3-5 markers at default density)
var hardware_detail: int = 1       # base detail from scanner hardware (upgradeable later)

## Resolves the visible markers at the gated detail level.
## systems_ops: { "navigation": bool, "scanners": bool } — operational status (caller derives
## from ShipSystemsManager.is_operational). scanner_skill: scanner_operation level 0..10.
func scan(world, systems_ops: Dictionary, scanner_skill: int) -> Dictionary
```

`scan` returns `{ "detail_level": int, "markers": Array }`:
- **Navigation offline** (`not systems_ops.navigation`) → `{detail_level: 0, markers: []}` (scanner
  shows nothing — master spec).
- **Scanners offline** (`navigation` ok, `not systems_ops.scanners`) → `detail_level = 1` (location/
  size only), markers visible.
- **Both operational** → `detail_level = min(MAX_DETAIL, hardware_detail + _skill_bonus(scanner_skill))`,
  where `_skill_bonus(skill) = skill / 2` (integer; skill 10 → +5).

Each `markers` entry is a **detail-gated view dict** (reveals progressively; lower-level fields
always present):

| Detail | Fields added |
|--------|--------------|
| 1 | `marker_id`, `position`, `distance`, `size_class` |
| 2 | + `ship_type` |
| 3 | + `condition` |
| 4 | + `predicted_status` (string derived from `condition`: pristine→"systems nominal", damaged→"systems degraded", wrecked→"systems critical") |
| 5 | + `predicted_offline` (Array[String] derived from `condition`/`size_class` — a deterministic guess of likely-offline systems) |
| 6 | + `loot_hint` (string derived from `size_class`/`condition`) |

Levels 4–6 are **deterministic predictions** from marker data (the ship is not generated yet), not
live system state. `get_summary`/`apply_summary` persist `range_radius`/`hardware_detail`.

### `TravelController`

```gdscript
## Validates and executes a jump to a marker, materializing the ship via procgen.
## generator: a ShipGenerator instance (injected). systems_ops: { "propulsion": bool }.
## radius: the current scanner reach used for the in-range check.
## Returns { success: bool, reason: String, ship: Node3D }.
func attempt_travel(marker, systems_ops: Dictionary, world, generator, radius: float) -> Dictionary
```

Rejections (each `{success:false, reason, ship:null}`): `null_marker` (marker null); `out_of_range`
(`marker.marker_id` not among `world.markers_in_range(radius)` ids); `propulsion_offline` (not
`systems_ops.propulsion`). Order: null → range → propulsion. On success: calls
`generator.generate_from_seed(marker.seed_value, marker.size_class, marker.condition)`; if non-null,
`world.set_player_position(marker.position)`, `world.mark_generated(marker.marker_id)`, returns
`{success:true, reason:"ok", ship:<Node3D>}`. If the generator returns null, returns
`{success:false, reason:"generation_failed", ship:null}` and the world is NOT mutated.

---

## System integrations (decoupled via plain dicts)

The models never import `ShipSystemsManager`/`PlayerProgressionState`; callers pass plain values:
- `systems_ops` dict from `ShipSystemsManager.is_operational("navigation"/"scanners"/"propulsion")`.
- `scanner_skill` int from `PlayerProgressionState.get_skill_level("scanner_operation")`.
- `generator` is a `ShipGenerator` instance.

This keeps each model independently testable and avoids cross-system coupling; the future live
wiring assembles these from the real systems.

---

## Testing

1. **`marker_generator_smoke.gd`** — `markers_for_cell(seed, cell)` is deterministic (two calls
   equal); different cells yield different marker sets; `MARKERS_PER_CELL` markers per cell with
   in-cell positions and distinct `seed_value`s; `cell_seed` stable.
2. **`synapse_sea_world_smoke.gd`** — `markers_in_range(radius)` returns markers within radius sorted by
   ascending distance, deduped; a marker beyond radius is excluded; `mark_generated`/`is_generated`;
   `get_summary`/`apply_summary` round-trip (`world_seed`, position, generated ids).
3. **`scanner_state_smoke.gd`** — navigation offline → empty, detail 0; scanners offline → detail 1,
   markers present with only L1 fields; both operational with `scanner_skill=10` → detail 6 and a
   marker view exposing L1–L6 fields; field-reveal matches the table; round-trip.
4. **`travel_controller_smoke.gd`** (SceneTree — generates real nodes) — propulsion offline →
   `propulsion_offline`; out-of-range marker → `out_of_range`; valid in-range marker with propulsion
   ok → `success`, `ship` is a non-null `Node3D`, and the world records the new position + generated
   id. Frees the generated ship to avoid leak warnings.
5. Register all four in `docs/game/06_validation_plan.md` (`commands=54` → `58`); full bundle must
   end `SYNAPSE_SEA REGRESSION PASS ... clean_output=true`; Gate-1 playtest still passes.

## File structure

- Create: `scripts/systems/ship_marker.gd`, `scripts/systems/marker_generator.gd`,
  `scripts/systems/synapse_sea_world.gd`, `scripts/systems/scanner_state.gd`,
  `scripts/systems/travel_controller.gd`
- Create: the 4 validation smokes above
- Modify: `docs/game/06_validation_plan.md` (register 4 smokes, bump count)
- No ADR (no `RunSnapshot`/architecture-of-record change — models are additive and self-contained).

## Risk

Low–moderate. The models are pure and standalone (no coordinator/RunSnapshot touch). The only
non-trivial pieces are the deterministic spatial hashing (fixed constants, no reliance on `hash()`)
and the `markers_in_range` cell-overlap query (bounding-box of cells intersecting the radius, then
distance filter). The travel smoke exercises the real procgen pipeline, already proven by
`ship_generator_smoke`/`load_from_blueprint_smoke`, so generation itself is low-risk.
