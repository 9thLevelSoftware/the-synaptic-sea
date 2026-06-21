# Phase 4 Scanner & Travel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the deterministic scanner/travel logic — an infinite procgen Sargasso of ship markers, a system/skill-gated scanner, and a propulsion-gated travel action that materializes a real ship via `generate_from_seed`.

**Architecture:** Five pure `RefCounted` models in `scripts/systems/*` (Resources are data, Nodes are behavior). Deterministic via seeded `RandomNumberGenerator` and a fixed spatial hash; no `Time`/`Math.random`. Models are decoupled from `ShipSystemsManager`/`PlayerProgressionState` — callers pass plain dicts/ints. No `RunSnapshot`/coordinator changes.

**Tech Stack:** Godot 4.6.2, typed GDScript, headless validation smokes (each "test" is a `SceneTree`/`--script` smoke printing a `PASS` marker — the marker is the contract).

## Global Constraints

- Godot binary (headless console): `C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe`
- Project root: `C:/Users/dasbl/Documents/The Synaptic Sea`
- Smoke run pattern (Git Bash):
  ```bash
  GODOT="C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe"
  ROOT="C:/Users/dasbl/Documents/The Synaptic Sea"
  "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/<name>.gd
  ```
- **`--script` exits 0 on parse/load errors** — proof is the literal `PASS` marker line AND no `Parse Error`/`SCRIPT ERROR`/unexpected `ERROR:`/`WARNING:`. Allowlisted noise: `ERROR: Capture not registered: 'gdaimcp'.`, `WARNING: ObjectDB instances leaked at exit ...`.
- In a `SceneTree` smoke, `quit()` does NOT halt `_initialize()` — every failure path must `return` after `quit(1)`.
- `class_name` globals are unreliable under `--headless --script`; reference cross-file scripts via `preload(...)` const Script vars; use the `load(...).new()` self-reference idiom in static factory methods (as `ship_blueprint.gd` does); avoid `class_name` return-type annotations on cross-file calls.
- Typed GDScript for new code. Conventional Commits. Branch: `phase4-scanner-travel`.
- Determinism: no `Time.*`, no `Math.random`, no argless `Date`. Use `RandomNumberGenerator` with an explicit `.seed`. Spatial hash uses fixed constants, NOT `hash()`.
- Enums mirror `ShipBlueprint`: `Size` LIFE_BOAT=0 / SMALL=1 / MEDIUM=2; `Condition` PRISTINE=0 / DAMAGED=1 / WRECKED=2.
- The Sargasso grid is the X–Z plane; `position.y` is always `0.0`. Grid cell = `Vector2i(cell_x, cell_y)` where `cell_y` indexes the Z axis.
- `ShipGenerator` API (existing, do not change): `ShipGenerator.new()`; `generate_from_seed(seed_value: int, size := 0, condition := 1) -> Node3D` (returns null on failure).

---

## File Structure

- **Create** `scripts/systems/ship_marker.gd` — `ShipMarker` pure data + `to_dict`/`from_dict`.
- **Create** `scripts/systems/marker_generator.gd` — `MarkerGenerator` deterministic per-cell markers.
- **Create** `scripts/systems/sargasso_world.gd` — `SargassoWorld` range query + generated set + summary.
- **Create** `scripts/systems/scanner_state.gd` — `ScannerState` gated scan + detail-reveal views.
- **Create** `scripts/systems/travel_controller.gd` — `TravelController` validated jump → generation.
- **Create** 4 smokes: `marker_generator_smoke.gd`, `sargasso_world_smoke.gd`, `scanner_state_smoke.gd`, `travel_controller_smoke.gd`.
- **Modify** `docs/game/06_validation_plan.md` — register 4 smokes, `commands=54` → `58`.

---

## Task 1: ShipMarker + MarkerGenerator

`ShipMarker` is tiny data consumed only by the generator, so they ship together and are proven by one determinism smoke.

**Files:**
- Create: `scripts/systems/ship_marker.gd`, `scripts/systems/marker_generator.gd`
- Test: `scripts/validation/marker_generator_smoke.gd`

**Interfaces:**
- Produces: `ShipMarker` fields `marker_id:String`, `position:Vector3`, `size_class:int`, `condition:int`, `ship_type:String`, `seed_value:int`; `to_dict()->Dictionary`, `static from_dict(d)->ShipMarker`.
- Produces: `MarkerGenerator` `const CELL_SIZE := 100.0`, `const MARKERS_PER_CELL := 3`; `static cell_seed(world_seed:int, cell:Vector2i)->int`; `markers_for_cell(world_seed:int, cell:Vector2i)->Array` (Array[ShipMarker]).

- [ ] **Step 1: Write the failing smoke**

Create `scripts/validation/marker_generator_smoke.gd`:

```gdscript
extends SceneTree

const GenScript := preload("res://scripts/systems/marker_generator.gd")
const MarkerScript := preload("res://scripts/systems/ship_marker.gd")

func _initialize() -> void:
	var gen = GenScript.new()

	# Determinism: same (world_seed, cell) -> identical markers.
	var a: Array = gen.markers_for_cell(42, Vector2i(3, -1))
	var b: Array = gen.markers_for_cell(42, Vector2i(3, -1))
	if a.size() != GenScript.MARKERS_PER_CELL:
		_fail("expected %d markers per cell, got %d" % [GenScript.MARKERS_PER_CELL, a.size()])
		return
	for i in range(a.size()):
		if a[i].to_dict() != b[i].to_dict():
			_fail("non-deterministic marker at index %d" % i)
			return

	# Different cell -> different marker set (ids differ at least).
	var c: Array = gen.markers_for_cell(42, Vector2i(4, -1))
	if c[0].marker_id == a[0].marker_id and c[0].seed_value == a[0].seed_value:
		_fail("different cell produced identical first marker")
		return

	# Marker positions fall inside the cell's world span; seeds are distinct.
	var seeds: Dictionary = {}
	for m in a:
		var base_x: float = float(3) * GenScript.CELL_SIZE
		var base_z: float = float(-1) * GenScript.CELL_SIZE
		if m.position.x < base_x or m.position.x > base_x + GenScript.CELL_SIZE:
			_fail("marker x outside cell span")
			return
		if m.position.z < base_z or m.position.z > base_z + GenScript.CELL_SIZE:
			_fail("marker z outside cell span")
			return
		if absf(m.position.y) > 0.0001:
			_fail("marker y should be 0")
			return
		seeds[m.seed_value] = true
	if seeds.size() != a.size():
		_fail("marker seed_values not distinct")
		return

	# ShipMarker round-trip.
	var rt = MarkerScript.from_dict(a[0].to_dict())
	if rt.to_dict() != a[0].to_dict():
		_fail("ShipMarker round-trip mismatch")
		return

	print("MARKER GENERATOR PASS deterministic=true per_cell=%d round_trip=true" % GenScript.MARKERS_PER_CELL)
	quit(0)

func _fail(reason: String) -> void:
	push_error("MARKER GENERATOR FAIL reason=%s" % reason)
	quit(1)
```

- [ ] **Step 2: Run it to verify it fails**

```bash
GODOT="C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe"
ROOT="C:/Users/dasbl/Documents/The Synaptic Sea"
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/marker_generator_smoke.gd
```
Expected: FAIL — the scripts do not exist yet (load error, no PASS marker).

- [ ] **Step 3: Implement ShipMarker**

Create `scripts/systems/ship_marker.gd`:

```gdscript
extends RefCounted
class_name ShipMarker

## Lightweight pre-generation descriptor of a ship in Sargasso space. Pure data;
## the actual ship is materialized on demand from seed_value via ShipGenerator.

var marker_id: String = ""
var position: Vector3 = Vector3.ZERO   # y is always 0 (planar Sargasso grid)
var size_class: int = 0                # ShipBlueprint.Size
var condition: int = 1                 # ShipBlueprint.Condition
var ship_type: String = ""
var seed_value: int = 0

func to_dict() -> Dictionary:
	return {
		"marker_id": marker_id,
		"position": [position.x, position.y, position.z],
		"size_class": size_class,
		"condition": condition,
		"ship_type": ship_type,
		"seed_value": seed_value,
	}

static func from_dict(d: Dictionary):
	var m = load("res://scripts/systems/ship_marker.gd").new()
	m.marker_id = str(d.get("marker_id", ""))
	var p: Variant = d.get("position", [0.0, 0.0, 0.0])
	if typeof(p) == TYPE_ARRAY and (p as Array).size() >= 3:
		m.position = Vector3(float(p[0]), float(p[1]), float(p[2]))
	m.size_class = int(d.get("size_class", 0))
	m.condition = int(d.get("condition", 1))
	m.ship_type = str(d.get("ship_type", ""))
	m.seed_value = int(d.get("seed_value", 0))
	return m
```

- [ ] **Step 4: Implement MarkerGenerator**

Create `scripts/systems/marker_generator.gd`:

```gdscript
extends RefCounted
class_name MarkerGenerator

## Deterministic, infinite marker field. (world_seed, grid cell) -> a fixed set
## of ShipMarkers. Same inputs always yield identical markers.

const ShipMarkerScript := preload("res://scripts/systems/ship_marker.gd")

const CELL_SIZE := 100.0
const MARKERS_PER_CELL := 3
const SHIP_TYPES := ["shuttle", "freighter", "science_vessel", "derelict_hauler"]

## Stable spatial hash (NOT Godot's hash(), which we do not rely on for save
## reproducibility). The large primes decorrelate adjacent cells.
static func cell_seed(world_seed: int, cell: Vector2i) -> int:
	return world_seed ^ (cell.x * 73856093) ^ (cell.y * 19349663)

func markers_for_cell(world_seed: int, cell: Vector2i) -> Array:
	var out: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = cell_seed(world_seed, cell)
	var base_x: float = float(cell.x) * CELL_SIZE
	var base_z: float = float(cell.y) * CELL_SIZE
	for i in range(MARKERS_PER_CELL):
		var m = ShipMarkerScript.new()
		m.marker_id = "%d:%d:%d" % [cell.x, cell.y, i]
		# Consume rng in a FIXED order so determinism holds.
		var lx: float = rng.randf() * CELL_SIZE
		var lz: float = rng.randf() * CELL_SIZE
		m.position = Vector3(base_x + lx, 0.0, base_z + lz)
		m.seed_value = rng.randi()
		m.size_class = _weighted_size(rng)
		m.condition = _weighted_condition(rng)
		m.ship_type = SHIP_TYPES[rng.randi() % SHIP_TYPES.size()]
		out.append(m)
	return out

func _weighted_size(rng: RandomNumberGenerator) -> int:
	var r: float = rng.randf()
	if r < 0.4:
		return 0  # LIFE_BOAT
	elif r < 0.8:
		return 1  # SMALL
	return 2      # MEDIUM

func _weighted_condition(rng: RandomNumberGenerator) -> int:
	var r: float = rng.randf()
	if r < 0.15:
		return 0  # PRISTINE
	elif r < 0.6:
		return 1  # DAMAGED
	return 2      # WRECKED
```

- [ ] **Step 5: Run it to verify it passes**

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/marker_generator_smoke.gd
```
Expected: PASS — `MARKER GENERATOR PASS deterministic=true per_cell=3 round_trip=true`.

- [ ] **Step 6: Commit**

```bash
git add scripts/systems/ship_marker.gd scripts/systems/marker_generator.gd scripts/validation/marker_generator_smoke.gd
git commit -m "feat(scanner): add ShipMarker + deterministic MarkerGenerator"
```

---

## Task 2: SargassoWorld

**Files:**
- Create: `scripts/systems/sargasso_world.gd`
- Test: `scripts/validation/sargasso_world_smoke.gd`

**Interfaces:**
- Consumes: `MarkerGenerator` (`CELL_SIZE`, `markers_for_cell`); `ShipMarker`.
- Produces: `SargassoWorld` `_init(world_seed:int=0, player_position:Vector3=Vector3.ZERO)`; `world_seed:int`, `player_position:Vector3`, `generated_marker_ids:Dictionary`; `markers_in_range(radius:float)->Array`; `mark_generated(id:String)->void`; `is_generated(id:String)->bool`; `set_player_position(pos:Vector3)->void`; `get_summary()->Dictionary`; `apply_summary(summary)->bool`.

- [ ] **Step 1: Write the failing smoke**

Create `scripts/validation/sargasso_world_smoke.gd`:

```gdscript
extends SceneTree

const WorldScript := preload("res://scripts/systems/sargasso_world.gd")

func _initialize() -> void:
	var world = WorldScript.new(42, Vector3.ZERO)

	var near: Array = world.markers_in_range(250.0)
	if near.is_empty():
		_fail("expected markers within radius 250")
		return

	# Every returned marker is within the radius.
	for m in near:
		if m.position.distance_to(world.player_position) > 250.0 + 0.001:
			_fail("marker beyond radius returned")
			return

	# Sorted ascending by distance.
	for i in range(1, near.size()):
		var d_prev: float = near[i - 1].position.distance_to(world.player_position)
		var d_cur: float = near[i].position.distance_to(world.player_position)
		if d_cur + 0.001 < d_prev:
			_fail("markers not sorted ascending by distance")
			return

	# Monotonic: a larger radius returns at least as many markers.
	var far: Array = world.markers_in_range(500.0)
	if far.size() < near.size():
		_fail("larger radius returned fewer markers")
		return

	# No duplicate marker_ids.
	var ids: Dictionary = {}
	for m in near:
		if ids.has(m.marker_id):
			_fail("duplicate marker_id in range result")
			return
		ids[m.marker_id] = true

	# generated set.
	var first_id: String = near[0].marker_id
	if world.is_generated(first_id):
		_fail("marker should not be pre-generated")
		return
	world.mark_generated(first_id)
	if not world.is_generated(first_id):
		_fail("mark_generated did not stick")
		return

	# Round-trip.
	world.set_player_position(Vector3(123.0, 0.0, -45.0))
	var summary: Dictionary = world.get_summary()
	var world2 = WorldScript.new(0, Vector3.ZERO)
	if not world2.apply_summary(summary):
		_fail("apply_summary returned false")
		return
	if world2.world_seed != 42:
		_fail("world_seed not restored")
		return
	if world2.player_position.distance_to(Vector3(123.0, 0.0, -45.0)) > 0.001:
		_fail("player_position not restored")
		return
	if not world2.is_generated(first_id):
		_fail("generated set not restored")
		return

	print("SARGASSO WORLD PASS in_range_sorted=true generated=true round_trip=true")
	quit(0)

func _fail(reason: String) -> void:
	push_error("SARGASSO WORLD FAIL reason=%s" % reason)
	quit(1)
```

- [ ] **Step 2: Run it to verify it fails**

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/sargasso_world_smoke.gd
```
Expected: FAIL — `sargasso_world.gd` does not exist.

- [ ] **Step 3: Implement SargassoWorld**

Create `scripts/systems/sargasso_world.gd`:

```gdscript
extends RefCounted
class_name SargassoWorld

## The infinite Sargasso: a world_seed, the player's position, and the set of
## markers already materialized into ships. Markers themselves are not stored —
## they are regenerated deterministically from world_seed on each query.

const MarkerGeneratorScript := preload("res://scripts/systems/marker_generator.gd")

var world_seed: int = 0
var player_position: Vector3 = Vector3.ZERO
var generated_marker_ids: Dictionary = {}   # marker_id -> true
var _generator

func _init(p_world_seed: int = 0, p_player_position: Vector3 = Vector3.ZERO) -> void:
	world_seed = p_world_seed
	player_position = p_player_position
	_generator = MarkerGeneratorScript.new()

## Distinct markers within `radius` of player_position, sorted ascending by
## distance. Regenerates every cell overlapping the radius bounding box.
func markers_in_range(radius: float) -> Array:
	var out: Array = []
	var seen: Dictionary = {}
	var cs: float = MarkerGeneratorScript.CELL_SIZE
	var min_x: int = int(floor((player_position.x - radius) / cs))
	var max_x: int = int(floor((player_position.x + radius) / cs))
	var min_y: int = int(floor((player_position.z - radius) / cs))
	var max_y: int = int(floor((player_position.z + radius) / cs))
	for cx in range(min_x, max_x + 1):
		for cy in range(min_y, max_y + 1):
			for m in _generator.markers_for_cell(world_seed, Vector2i(cx, cy)):
				if seen.has(m.marker_id):
					continue
				if m.position.distance_to(player_position) <= radius:
					seen[m.marker_id] = true
					out.append(m)
	out.sort_custom(_closer_to_player)
	return out

func _closer_to_player(a, b) -> bool:
	return a.position.distance_to(player_position) < b.position.distance_to(player_position)

func mark_generated(marker_id: String) -> void:
	generated_marker_ids[marker_id] = true

func is_generated(marker_id: String) -> bool:
	return generated_marker_ids.has(marker_id)

func set_player_position(pos: Vector3) -> void:
	player_position = pos

func get_summary() -> Dictionary:
	return {
		"world_seed": world_seed,
		"player_position": [player_position.x, player_position.y, player_position.z],
		"generated_marker_ids": generated_marker_ids.keys(),
	}

func apply_summary(summary) -> bool:
	if typeof(summary) != TYPE_DICTIONARY or (summary as Dictionary).is_empty():
		return false
	world_seed = int(summary.get("world_seed", world_seed))
	var p: Variant = summary.get("player_position", null)
	if typeof(p) == TYPE_ARRAY and (p as Array).size() >= 3:
		player_position = Vector3(float(p[0]), float(p[1]), float(p[2]))
	generated_marker_ids.clear()
	var ids: Variant = summary.get("generated_marker_ids", [])
	if typeof(ids) == TYPE_ARRAY:
		for mid in (ids as Array):
			generated_marker_ids[str(mid)] = true
	return true
```

- [ ] **Step 4: Run it to verify it passes**

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/sargasso_world_smoke.gd
```
Expected: PASS — `SARGASSO WORLD PASS in_range_sorted=true generated=true round_trip=true`.

- [ ] **Step 5: Commit**

```bash
git add scripts/systems/sargasso_world.gd scripts/validation/sargasso_world_smoke.gd
git commit -m "feat(scanner): add SargassoWorld range query + generated set + summary"
```

---

## Task 3: ScannerState

**Files:**
- Create: `scripts/systems/scanner_state.gd`
- Test: `scripts/validation/scanner_state_smoke.gd`

**Interfaces:**
- Consumes: `SargassoWorld` (`markers_in_range`, `player_position`).
- Produces: `ScannerState` `const MAX_DETAIL := 6`; `range_radius:float=250.0`, `hardware_detail:int=1`; `scan(world, systems_ops:Dictionary, scanner_skill:int)->Dictionary` returning `{detail_level:int, markers:Array}`; `get_summary()->Dictionary`; `apply_summary(summary)->bool`.

- [ ] **Step 1: Write the failing smoke**

Create `scripts/validation/scanner_state_smoke.gd`:

```gdscript
extends SceneTree

const WorldScript := preload("res://scripts/systems/sargasso_world.gd")
const ScannerScript := preload("res://scripts/systems/scanner_state.gd")

func _initialize() -> void:
	var world = WorldScript.new(42, Vector3.ZERO)
	var scanner = ScannerScript.new()

	# Navigation offline -> nothing.
	var r0: Dictionary = scanner.scan(world, {"navigation": false, "scanners": true}, 10)
	if int(r0.get("detail_level", -1)) != 0 or not (r0.get("markers", [1]) as Array).is_empty():
		_fail("navigation offline should yield detail 0 + empty markers")
		return

	# Scanners offline -> detail 1, markers present, only L1 fields.
	var r1: Dictionary = scanner.scan(world, {"navigation": true, "scanners": false}, 10)
	if int(r1.get("detail_level", -1)) != 1:
		_fail("scanners offline should cap detail at 1, got %d" % int(r1.get("detail_level", -1)))
		return
	var m1: Array = r1.get("markers", [])
	if m1.is_empty():
		_fail("expected markers at detail 1")
		return
	if (m1[0] as Dictionary).has("ship_type"):
		_fail("detail 1 view should not expose ship_type")
		return
	for key in ["marker_id", "position", "distance", "size_class"]:
		if not (m1[0] as Dictionary).has(key):
			_fail("detail 1 view missing %s" % key)
			return

	# Both operational, skill 10 -> detail min(6, 1 + 10/2) = 6; full field set.
	var r6: Dictionary = scanner.scan(world, {"navigation": true, "scanners": true}, 10)
	if int(r6.get("detail_level", -1)) != 6:
		_fail("full scan should be detail 6, got %d" % int(r6.get("detail_level", -1)))
		return
	var v: Dictionary = (r6.get("markers", []) as Array)[0]
	for key in ["ship_type", "condition", "predicted_status", "predicted_offline", "loot_hint"]:
		if not v.has(key):
			_fail("detail 6 view missing %s" % key)
			return

	# Round-trip.
	scanner.range_radius = 333.0
	scanner.hardware_detail = 2
	var summary: Dictionary = scanner.get_summary()
	var scanner2 = ScannerScript.new()
	if not scanner2.apply_summary(summary):
		_fail("apply_summary returned false")
		return
	if absf(scanner2.range_radius - 333.0) > 0.001 or scanner2.hardware_detail != 2:
		_fail("scanner config not restored")
		return

	print("SCANNER STATE PASS nav_off_empty=true scanners_off_detail1=true full_detail=6 round_trip=true")
	quit(0)

func _fail(reason: String) -> void:
	push_error("SCANNER STATE FAIL reason=%s" % reason)
	quit(1)
```

- [ ] **Step 2: Run it to verify it fails**

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/scanner_state_smoke.gd
```
Expected: FAIL — `scanner_state.gd` does not exist.

- [ ] **Step 3: Implement ScannerState**

Create `scripts/systems/scanner_state.gd`:

```gdscript
extends RefCounted
class_name ScannerState

## Resolves which markers are visible and at what detail, gated by the ship's
## navigation/scanners systems and the player's scanner_operation skill. Pure
## logic — callers pass operational status as a plain dict.

const MAX_DETAIL := 6

var range_radius: float = 250.0   # spatial reach
var hardware_detail: int = 1      # base detail from scanner hardware (upgradeable)

## systems_ops: { "navigation": bool, "scanners": bool }. scanner_skill: 0..10.
## Returns { "detail_level": int, "markers": Array[Dictionary] }.
func scan(world, systems_ops: Dictionary, scanner_skill: int) -> Dictionary:
	if not bool(systems_ops.get("navigation", false)):
		return {"detail_level": 0, "markers": []}
	var detail: int = 1
	if bool(systems_ops.get("scanners", false)):
		detail = mini(MAX_DETAIL, hardware_detail + _skill_bonus(scanner_skill))
	var views: Array = []
	for m in world.markers_in_range(range_radius):
		views.append(_marker_view(m, world.player_position, detail))
	return {"detail_level": detail, "markers": views}

func _skill_bonus(skill: int) -> int:
	return int(skill / 2)   # every 2 skill points -> +1 detail

func _marker_view(m, player_pos: Vector3, detail: int) -> Dictionary:
	var view: Dictionary = {
		"marker_id": m.marker_id,
		"position": [m.position.x, m.position.y, m.position.z],
		"distance": m.position.distance_to(player_pos),
		"size_class": m.size_class,
	}
	if detail >= 2:
		view["ship_type"] = m.ship_type
	if detail >= 3:
		view["condition"] = m.condition
	if detail >= 4:
		view["predicted_status"] = _predicted_status(m.condition)
	if detail >= 5:
		view["predicted_offline"] = _predicted_offline(m.condition, m.size_class)
	if detail >= 6:
		view["loot_hint"] = _loot_hint(m.size_class, m.condition)
	return view

func _predicted_status(condition: int) -> String:
	match condition:
		0: return "systems nominal"
		1: return "systems degraded"
		_: return "systems critical"

func _predicted_offline(condition: int, _size_class: int) -> Array:
	# Deterministic guess of likely-offline systems from condition.
	match condition:
		0: return []
		1: return ["scanners"]
		_: return ["scanners", "navigation", "propulsion"]

func _loot_hint(size_class: int, condition: int) -> String:
	var scale: String = ["meagre", "modest", "rich"][clampi(size_class, 0, 2)]
	var salvage: String = "intact" if condition == 0 else "salvageable"
	return "%s cache, %s" % [scale, salvage]

func get_summary() -> Dictionary:
	return {"range_radius": range_radius, "hardware_detail": hardware_detail}

func apply_summary(summary) -> bool:
	if typeof(summary) != TYPE_DICTIONARY or (summary as Dictionary).is_empty():
		return false
	range_radius = float(summary.get("range_radius", range_radius))
	hardware_detail = int(summary.get("hardware_detail", hardware_detail))
	return true
```

- [ ] **Step 4: Run it to verify it passes**

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/scanner_state_smoke.gd
```
Expected: PASS — `SCANNER STATE PASS nav_off_empty=true scanners_off_detail1=true full_detail=6 round_trip=true`.

- [ ] **Step 5: Commit**

```bash
git add scripts/systems/scanner_state.gd scripts/validation/scanner_state_smoke.gd
git commit -m "feat(scanner): add ScannerState gated scan with detail-reveal views"
```

---

## Task 4: TravelController (docking → generation proof)

**Files:**
- Create: `scripts/systems/travel_controller.gd`
- Test: `scripts/validation/travel_controller_smoke.gd`

**Interfaces:**
- Consumes: `SargassoWorld` (`markers_in_range`, `set_player_position`, `mark_generated`, `is_generated`, `player_position`); `ShipMarker`; `ShipGenerator` (`new()`, `generate_from_seed`).
- Produces: `TravelController` `attempt_travel(marker, systems_ops:Dictionary, world, generator, radius:float)->Dictionary` returning `{success:bool, reason:String, ship}`. Rejection order: `null_marker` → `out_of_range` → `propulsion_offline`; then `generation_failed` if generator returns null; else success with the ship `Node3D`. Mutates the world ONLY on success.

- [ ] **Step 1: Write the failing smoke**

Create `scripts/validation/travel_controller_smoke.gd`:

```gdscript
extends SceneTree

const WorldScript := preload("res://scripts/systems/sargasso_world.gd")
const TravelScript := preload("res://scripts/systems/travel_controller.gd")
const GeneratorScript := preload("res://scripts/procgen/ship_generator.gd")
const MarkerScript := preload("res://scripts/systems/ship_marker.gd")

func _initialize() -> void:
	var world = WorldScript.new(42, Vector3.ZERO)
	var travel = TravelScript.new()
	var generator = GeneratorScript.new()

	var in_range: Array = world.markers_in_range(250.0)
	if in_range.is_empty():
		_fail("no markers in range to travel to")
		return
	var target = in_range[0]

	# Propulsion offline -> rejected, world unchanged.
	var r_prop: Dictionary = travel.attempt_travel(target, {"propulsion": false}, world, generator, 250.0)
	if bool(r_prop.get("success", true)) or str(r_prop.get("reason", "")) != "propulsion_offline":
		_fail("propulsion offline should reject, got %s" % str(r_prop))
		return
	if world.is_generated(target.marker_id):
		_fail("world mutated on rejected travel")
		return

	# Out of range -> rejected (a marker id that is not in range).
	var bogus = MarkerScript.new()
	bogus.marker_id = "9999:9999:0"
	bogus.position = Vector3(1000000.0, 0.0, 0.0)
	bogus.seed_value = 7
	var r_range: Dictionary = travel.attempt_travel(bogus, {"propulsion": true}, world, generator, 250.0)
	if bool(r_range.get("success", true)) or str(r_range.get("reason", "")) != "out_of_range":
		_fail("out-of-range marker should reject, got %s" % str(r_range))
		return

	# Valid jump -> success, real ship Node3D, world updated.
	var r_ok: Dictionary = travel.attempt_travel(target, {"propulsion": true}, world, generator, 250.0)
	if not bool(r_ok.get("success", false)):
		_fail("valid travel should succeed, got %s" % str(r_ok))
		return
	var ship = r_ok.get("ship", null)
	if ship == null or not (ship is Node3D):
		_fail("travel did not return a Node3D ship")
		return
	if not world.is_generated(target.marker_id):
		_fail("world did not record generated marker")
		return
	if world.player_position.distance_to(target.position) > 0.001:
		_fail("player_position not updated to target")
		return

	# Free the generated ship to avoid leak noise beyond the allowlisted baseline.
	ship.queue_free()

	print("TRAVEL CONTROLLER PASS propulsion_gate=true range_gate=true generated_node=true")
	quit(0)

func _fail(reason: String) -> void:
	push_error("TRAVEL CONTROLLER FAIL reason=%s" % reason)
	quit(1)
```

- [ ] **Step 2: Run it to verify it fails**

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/travel_controller_smoke.gd
```
Expected: FAIL — `travel_controller.gd` does not exist.

- [ ] **Step 3: Implement TravelController**

Create `scripts/systems/travel_controller.gd`:

```gdscript
extends RefCounted
class_name TravelController

## Validates and executes a jump to a marker, materializing the ship via the
## procgen pipeline. Pure coordinator — takes the world, a ShipGenerator, and
## operational status as inputs; mutates the world only on success.

## systems_ops: { "propulsion": bool }. radius: current scanner reach.
## Returns { success: bool, reason: String, ship: Node3D|null }.
func attempt_travel(marker, systems_ops: Dictionary, world, generator, radius: float) -> Dictionary:
	if marker == null:
		return {"success": false, "reason": "null_marker", "ship": null}
	var in_range: bool = false
	for m in world.markers_in_range(radius):
		if m.marker_id == marker.marker_id:
			in_range = true
			break
	if not in_range:
		return {"success": false, "reason": "out_of_range", "ship": null}
	if not bool(systems_ops.get("propulsion", false)):
		return {"success": false, "reason": "propulsion_offline", "ship": null}
	var ship = generator.generate_from_seed(marker.seed_value, marker.size_class, marker.condition)
	if ship == null:
		return {"success": false, "reason": "generation_failed", "ship": null}
	world.set_player_position(marker.position)
	world.mark_generated(marker.marker_id)
	return {"success": true, "reason": "ok", "ship": ship}
```

- [ ] **Step 4: Run it to verify it passes**

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/travel_controller_smoke.gd
```
Expected: PASS — `TRAVEL CONTROLLER PASS propulsion_gate=true range_gate=true generated_node=true` (the `gdaimcp` ERROR and ObjectDB leak WARNING are the only allowlisted lines).

- [ ] **Step 5: Commit**

```bash
git add scripts/systems/travel_controller.gd scripts/validation/travel_controller_smoke.gd
git commit -m "feat(scanner): add TravelController — propulsion/range-gated jump to generated ship"
```

---

## Task 5: Register smokes + full regression

**Files:**
- Modify: `docs/game/06_validation_plan.md`

- [ ] **Step 1: Register the four smokes in the regression bundle**

In `docs/game/06_validation_plan.md`, inside the `run_clean` block (the bash fence that ends with the `SARGASSO REGRESSION PASS` echo at line ~118), add these four lines just before that echo:

```bash
run_clean 'marker generator smoke' 'MARKER GENERATOR PASS deterministic=true per_cell=3 round_trip=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/marker_generator_smoke.gd
run_clean 'sargasso world smoke' 'SARGASSO WORLD PASS in_range_sorted=true generated=true round_trip=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/sargasso_world_smoke.gd
run_clean 'scanner state smoke' 'SCANNER STATE PASS nav_off_empty=true scanners_off_detail1=true full_detail=6 round_trip=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/scanner_state_smoke.gd
run_clean 'travel controller smoke' 'TRAVEL CONTROLLER PASS propulsion_gate=true range_gate=true generated_node=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/travel_controller_smoke.gd
```

Then change the final echo `commands=54` → `commands=58`.

- [ ] **Step 2: Run the full regression bundle + Gate-1 playtest**

Extract the bundle bash fence and run with the Windows paths substituted (do NOT edit the doc's hardcoded macOS paths). The fence content currently spans lines ~30–118; after adding 4 lines it ends ~122 — capture through the `SARGASSO REGRESSION PASS` echo:
```bash
GODOT="C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe"
ROOT="C:/Users/dasbl/Documents/The Synaptic Sea"
START=$(grep -n '^```bash$' docs/game/06_validation_plan.md | sed -n '2p' | cut -d: -f1)
END=$(grep -n "SARGASSO REGRESSION PASS commands=" docs/game/06_validation_plan.md | head -1 | cut -d: -f1)
sed -n "$((START+1)),${END}p" docs/game/06_validation_plan.md \
  | sed "s#^ROOT=.*#ROOT=\"$ROOT\"#; s#^GODOT=.*#GODOT=\"$GODOT\"#" > /tmp/reg.sh
bash /tmp/reg.sh 2>&1 | tail -2
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/gate1_automated_playtest.gd 2>&1 | grep -E "GATE 1 AUTOMATED PLAYTEST PASS|FAIL"
```
Expected: bundle ends `SARGASSO REGRESSION PASS commands=58 clean_output=true`; Gate-1 prints `GATE 1 AUTOMATED PLAYTEST PASS`. If the count mismatches or an unexpected ERROR/WARNING appears, fix the registration/marker (or the real regression) and re-run — do not adjust the count to mask a missing smoke.

- [ ] **Step 3: Commit**

```bash
git add docs/game/06_validation_plan.md
git commit -m "docs(validation): register Phase 4 scanner/travel smokes (commands 54->58)"
```

---

## Self-Review

**Spec coverage:**
- `ShipMarker` data + round-trip → Task 1 ✓
- `MarkerGenerator` deterministic cell markers + spatial hash → Task 1 ✓
- `SargassoWorld` range query + generated set + summary → Task 2 ✓
- `ScannerState` gating (nav off → empty; scanners off → detail 1; operational + skill → detail 1..6) + detail-reveal field table + round-trip → Task 3 ✓
- `TravelController` null/range/propulsion rejections + generate_from_seed proof + world mutation on success only → Task 4 ✓
- 4 smokes registered, commands 54→58, regression + Gate-1 → Task 5 ✓
- Decoupling via plain dicts (systems_ops, scanner_skill, generator injected) → Tasks 3–4 ✓
- Out-of-scope (UI, fuel economy, RunSnapshot, ship-in-ship) → not built; no coordinator/RunSnapshot touch ✓

**Placeholder scan:** No TBD/TODO. All code blocks complete. `commands=58` is concrete (54 + 4); Step 2 says fix-and-re-run rather than fudge on mismatch.

**Type consistency:** `markers_for_cell(world_seed, cell)`, `cell_seed`, `CELL_SIZE`, `MARKERS_PER_CELL`, `markers_in_range(radius)`, `scan(world, systems_ops, scanner_skill)` returning `{detail_level, markers}`, `attempt_travel(marker, systems_ops, world, generator, radius)` returning `{success, reason, ship}` are used identically across tasks and smokes. `ShipMarker` field names (`marker_id`, `position`, `size_class`, `condition`, `ship_type`, `seed_value`) match between producer (Task 1) and all consumers (Tasks 2–4). `generate_from_seed(seed_value, size_class, condition)` matches the existing `ShipGenerator` signature verified in source.
