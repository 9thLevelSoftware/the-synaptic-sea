# Domain 3: Close the Food Loop — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the `food` loop by making hydroponics + water-recycler player-operated production stations, retiring the orphan `synthesizer_state`, and ticking spoilage + production on the away (derelict) branch.

**Architecture:** A new `ProductionStation` Area3D node mirrors the existing `CraftingStation` range/interact contract but drives a *stateful, persistent* production model (start on first interact, harvest on a later interact). The coordinator builds two such stations on the home ship, wires their signals to the existing food/spoilage/HUD plumbing, and hoists the per-frame food tick into a shared `_tick_food_runtime(delta)` helper called from **both** `_process` branches. The orphan `synthesizer_state` (duplicated by the live crafting `"synthesizer"` station) is removed, including its `RunSnapshot` save field (backward-compatible, no schema-version bump).

**Tech Stack:** Godot 4.6.2, typed GDScript, Forward+. Headless `--script` validation smokes (`extends SceneTree`, print a single `… PASS …` marker; trust the marker, not the exit code).

## Global Constraints

- **Godot binary:** `C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe` (use the `_console` build for headless runs).
- **Project root:** `C:/Users/dasbl/Documents/The Synaptic Sea`.
- **Run a smoke:** `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/<smoke>.gd` where `GODOT`/`ROOT` are the two values above. **Godot `--script` can exit 0 on parse/load errors — trust only the printed `… PASS …` marker and the absence of unexpected `ERROR:`/`WARNING:` lines.**
- **Baseline output noise (allowlisted, ignore):** `ERROR: Capture not registered: 'gdaimcp'.` and `WARNING: ObjectDB instances leaked at exit (run with --verbose for details).` Any *other* `ERROR:`/`WARNING:` line blocks completion.
- **Model/Node separation (strict):** pure gameplay state → `RefCounted`/`Resource` (never touches the scene tree, has `get_summary()`/`apply_summary()`); scene consequences → Nodes. `ProductionStation` is a Node; it drives the existing pure models, it is not one.
- **Wire BOTH `_process` branches:** `playable_generated_ship.gd::_process` has an `if away_from_start:` branch that `return`s before the home branch. Any per-frame system must run in both or it is dead on a derelict (the primary gameplay context).
- **Typed GDScript** for all new code.
- **Conventional Commits** (`feat:`, `fix:`, `refactor:`, `test:`, `docs:`).
- **git staging:** stage only the exact paths each task names. NEVER `git add -A`. Never stage `project.godot`, `.godot/`, `*.uid`, or `addons/`.
- **Commit trailers (every commit):**
  ```
  Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01KPbqcGeunTAQouMUN1HWWx
  ```
- **Spec:** `docs/superpowers/specs/2026-06-30-domain3-food-design.md`.
- **Branch:** `feat/domain3-food` (already created off `docs/completion-roadmap`).

## Existing interfaces this plan relies on (verified, exact)

- `InventoryState` (`scripts/systems/inventory_state.gd`): `add_item(item_id: String, qty: int) -> int` (returns qty actually added), `remove_item(item_id: String, qty: int) -> int` (returns qty actually removed), `can_accept(item_id: String, qty: int) -> bool`, `get_quantity(item_id: String) -> int`.
- `HydroponicsState` (`scripts/systems/hydroponics_state.gd`): `enum State { IDLE, PLANTED, HARVESTABLE }`; `plant(crop_config: Dictionary, skill_level: int, available_water: float, available_power: float) -> Dictionary` (`{"ok", "reason", "water_consumed", "power_consumed"}`); `tick(delta: float) -> bool`; `harvest() -> Dictionary` (`{"ok", "item_id", "quantity"}`); fields `state`, `water_cost`, `power_cost`, `required_skill_level`, `produce_item_id`.
- `WaterRecyclerState` (`scripts/systems/water_recycler_state.gd`): `enum State { IDLE, RECYCLING }`; `load_input(item_id: String, qty: int, available_power: float) -> Dictionary` (`{"ok", "reason"}`); `tick(delta: float) -> bool`; `collect_output() -> Dictionary` (`{"ok", "item_id", "quantity"}`); fields `state`, `power_cost`, `output_ready`, `output_item_id`.
- Crop config file `data/crops/hydroponics_crops.json`: `{"crops": [ {crop_id, display_name, produce_item_id, produce_quantity, growth_seconds, water_cost, power_cost, required_skill_level}, ... ]}`. Existing crops: `hydroponic_greens` (water_cost 2.0, power_cost 3.0, skill 0), `alien_flora_cultivar` (water_cost 3.0, power_cost 5.0, skill 2).
- `CraftingStation` (`scripts/tools/crafting_station.gd`) is the node pattern to mirror: `extends Area3D`, range-gated `try_interact(player_body) -> bool` via `_is_player_in_direct_range` (`global_position.distance_to(player) <= radius`), `_ensure_collision`/`_ensure_marker`, `set_powered`, `set_meta`.
- Coordinator (`scripts/procgen/playable_generated_ship.gd`): `_build_crafting_stations()` and `_clear_crafting_stations()`; `_home_local_station_positions() -> Array`; the unified interact sweep `for st in crafting_stations:` (the one inside the player-interact handler, currently near line 4380 — locate by the loop body `if is_instance_valid(st) and st.try_interact(player_body): return true`); `craft_at_station_for_validation(station_kind: String) -> bool`; `_register_food_for_spoilage(item_id: String)`; `_refresh_inventory_hud()`; `_recompute_player_encumbrance()`; `_load_json_dict(path: String) -> Dictionary`; `power_grid_state.get_allocation_ratio("sustenance") -> float`. Model fields `hydroponics_state`, `synthesizer_state`, `water_recycler_state`, `sustenance_state`, `spoilage_state`, `inventory_state`, `player_progression`, `home_ship`.
- `RunSnapshot` (`scripts/systems/run_snapshot.gd`): `SUMMARY_FIELDS: Array` (const), `get_summary_count() -> int`, `to_dict()`, `from_dict(data, expected_slice_version, expected_godot_version)` — reads each field via `.get(key, {})`, tolerates unknown/missing keys.

---

### Task 1: Add `contaminated_water` input item + acquisition

**Files:**
- Modify: `data/items/item_definitions.json` (add one item)
- Modify: one derelict/home loot table under `data/items/loot_tables.json` (seed acquisition)
- Test: `scripts/validation/contaminated_water_item_smoke.gd` (create)

**Interfaces:**
- Produces: item id `contaminated_water` (category `"supply"`), loadable by `WaterRecyclerState.load_input` and lootable so the player can acquire it.

- [ ] **Step 1: Write the failing smoke**

Create `scripts/validation/contaminated_water_item_smoke.gd`:

```gdscript
extends SceneTree

## Domain 3 Task 1: contaminated_water exists as a supply item (recycler input) and
## is reachable as loot. It is NOT a food/drink (never eaten), so it has no nutrition.
## Marker: CONTAMINATED WATER ITEM PASS defined=true supply=true lootable=true

const ItemDefsScript := preload("res://scripts/systems/item_definitions.gd")
const LOOT_TABLES_PATH := "res://data/items/loot_tables.json"

func _initialize() -> void:
	var defs: Dictionary = ItemDefsScript.load_definitions()
	if not defs.has("contaminated_water"):
		_fail("contaminated_water not defined in item definitions"); return
	var d: Dictionary = defs["contaminated_water"]
	if str(d.get("category", "")) != "supply":
		_fail("contaminated_water category=%s expected supply" % str(d.get("category", ""))); return
	# Reachable as loot: appears in at least one loot table's entries.
	var f := FileAccess.open(LOOT_TABLES_PATH, FileAccess.READ)
	if f == null:
		_fail("could not open loot_tables.json"); return
	var raw: String = f.get_as_text()
	f.close()
	if not raw.contains("contaminated_water"):
		_fail("contaminated_water not seeded into any loot table"); return
	print("CONTAMINATED WATER ITEM PASS defined=true supply=true lootable=true")
	quit(0)

func _fail(reason: String) -> void:
	push_error("CONTAMINATED WATER ITEM FAIL reason=%s" % reason)
	quit(1)
```

> Note: confirm the item-definitions loader path. If `scripts/systems/item_definitions.gd` is not the correct loader, locate it with `grep -rn "load_definitions" scripts/systems` and use that script. The grep in research showed `ItemDefsScript.load_definitions()` is already used by `playable_generated_ship.gd`.

- [ ] **Step 2: Run smoke to verify it fails**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/contaminated_water_item_smoke.gd`
Expected: no `CONTAMINATED WATER ITEM PASS` line; a `CONTAMINATED WATER ITEM FAIL reason=contaminated_water not defined…` error.

- [ ] **Step 3: Add the item definition**

In `data/items/item_definitions.json`, add this entry next to `purified_water` (match the surrounding formatting; `contaminated_water` gets NO `hunger_restore`/`thirst_restore`/spoilage fields — it is never consumed):

```json
  "contaminated_water": { "display_name": "Contaminated Water", "category": "supply", "weight": 0.25, "max_stack": 20, "rarity": "common" },
```

- [ ] **Step 4: Seed it into a loot table**

Open `data/items/loot_tables.json`. Find an existing derelict/general supply loot table (e.g. the same table family that yields `scrap_metal`/`power_cell` supplies). Add a `contaminated_water` entry to that table's `entries` array, mirroring the existing entry shape exactly. Example shape (adapt keys to the file's real schema):

```json
{ "item_id": "contaminated_water", "qty_min": 1, "qty_max": 3, "weight": 8, "rarity": "common" }
```

> Read the file first; copy a sibling entry and change only `item_id`/quantities/weight so the schema matches byte-for-byte.

- [ ] **Step 5: Run smoke to verify it passes**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/contaminated_water_item_smoke.gd`
Expected: prints `CONTAMINATED WATER ITEM PASS defined=true supply=true lootable=true`, no unexpected ERROR/WARNING.

- [ ] **Step 6: Commit**

```bash
git add data/items/item_definitions.json data/items/loot_tables.json scripts/validation/contaminated_water_item_smoke.gd
git commit -m "feat: add contaminated_water recycler input item + loot acquisition

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01KPbqcGeunTAQouMUN1HWWx"
```

---

### Task 2: `ProductionStation` node + unit smoke

**Files:**
- Create: `scripts/tools/production_station.gd`
- Test: `scripts/validation/production_station_smoke.gd` (create)

**Interfaces:**
- Consumes: `HydroponicsState`, `WaterRecyclerState`, `InventoryState` (Task-0 existing); item `contaminated_water` (Task 1).
- Produces: `class_name ProductionStation` with:
  - `configure(station_kind: String, model, inventory_state, power_available: Callable, player_skill: Callable, config: Dictionary, world_position: Vector3, radius := 1.8) -> void`
  - `try_interact(player_body) -> bool`
  - `set_validation_player_in_range(player_body: Node) -> void` (bypasses the range gate for headless tests, mirrors CraftingStation)
  - signals `production_started(station_kind: String, input_id: String)`, `production_harvested(station_kind: String, item_id: String, qty: int)`, `production_blocked(station_kind: String, reason: String)`.

- [ ] **Step 1: Write the failing smoke**

Create `scripts/validation/production_station_smoke.gd`:

```gdscript
extends SceneTree

## Domain 3 Task 2: ProductionStation drives a stateful production model via interact.
## - IDLE interact starts production (consumes input from inventory).
## - interact while RUNNING is a no-op (production_blocked "in_progress").
## - interact while READY harvests/collects into inventory.
## Validated against BOTH a HydroponicsState and a WaterRecyclerState with a fake inventory.
## Marker: PRODUCTION STATION PASS hydro_harvest=true recycler_collect=true blocked_in_progress=true

const ProductionStationScript := preload("res://scripts/tools/production_station.gd")
const HydroStateScript := preload("res://scripts/systems/hydroponics_state.gd")
const RecyclerStateScript := preload("res://scripts/systems/water_recycler_state.gd")
const InventoryStateScript := preload("res://scripts/systems/inventory_state.gd")

var blocked_in_progress: bool = false

func _initialize() -> void:
	var ok_hydro: bool = _test_hydro()
	var ok_recycler: bool = _test_recycler()
	if ok_hydro and ok_recycler and blocked_in_progress:
		print("PRODUCTION STATION PASS hydro_harvest=true recycler_collect=true blocked_in_progress=true")
		quit(0)
	else:
		push_error("PRODUCTION STATION FAIL hydro=%s recycler=%s blocked=%s" % [str(ok_hydro), str(ok_recycler), str(blocked_in_progress)])
		quit(1)

func _test_hydro() -> bool:
	var inv = InventoryStateScript.new()
	inv.add_item("purified_water", 5)
	var model = HydroStateScript.new()
	var crops := {"crops": [{
		"crop_id": "hydroponic_greens", "display_name": "Hydroponic Greens",
		"produce_item_id": "hydroponic_greens", "produce_quantity": 3,
		"growth_seconds": 1.0, "water_cost": 2.0, "power_cost": 3.0, "required_skill_level": 0,
	}]}
	var st = ProductionStationScript.new()
	st.configure("hydroponics", model, inv, func(): return 999.0, func(): return 5, crops, Vector3.ZERO, 1.8)
	st.set_validation_player_in_range(self)  # bypass spatial gate in headless
	# IDLE -> start
	if not st.try_interact(self):
		return false
	if model.state != HydroStateScript.State.PLANTED:
		return false
	if inv.get_quantity("purified_water") != 3:  # 5 - water_cost(2)
		return false
	# RUNNING -> no-op
	if st.try_interact(self):
		return false  # should return false while growing
	# tick to HARVESTABLE
	model.tick(2.0)
	if model.state != HydroStateScript.State.HARVESTABLE:
		return false
	# READY -> harvest
	if not st.try_interact(self):
		return false
	if inv.get_quantity("hydroponic_greens") != 3:
		return false
	if model.state != HydroStateScript.State.IDLE:
		return false
	return true

func _test_recycler() -> bool:
	var inv = InventoryStateScript.new()
	inv.add_item("contaminated_water", 4)
	var model = RecyclerStateScript.new()
	model.configure({"input_item_id": "contaminated_water", "output_item_id": "purified_water",
		"conversion_ratio": 1.0, "recycle_time_seconds": 1.0, "power_cost": 5.0})
	var st = ProductionStationScript.new()
	st.configure("water_recycler", model, inv, func(): return 999.0, func(): return 0, {}, Vector3.ZERO, 1.8)
	st.st_blocked_seen = false
	st.production_blocked.connect(func(_k, reason):
		if reason == "in_progress":
			blocked_in_progress = true)
	st.set_validation_player_in_range(self)
	if not st.try_interact(self):  # IDLE -> load contaminated_water
		return false
	if model.state != RecyclerStateScript.State.RECYCLING:
		return false
	if inv.get_quantity("contaminated_water") != 0:
		return false
	st.try_interact(self)  # RUNNING -> blocked in_progress (sets blocked_in_progress via signal)
	model.tick(2.0)        # -> output_ready
	if not st.try_interact(self):  # READY -> collect
		return false
	if inv.get_quantity("purified_water") != 4:
		return false
	return true
```

> The `st.st_blocked_seen = false` line is harmless scratch; remove it if your node has no such field. The important assertion is the `production_blocked("in_progress")` signal firing.

- [ ] **Step 2: Run smoke to verify it fails**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/production_station_smoke.gd`
Expected: parse/load error or FAIL (script `production_station.gd` does not exist yet).

- [ ] **Step 3: Implement `ProductionStation`**

Create `scripts/tools/production_station.gd`:

```gdscript
extends Area3D
class_name ProductionStation

## A spatial, range-gated production station bound to one stateful production model
## (HydroponicsState or WaterRecyclerState) on the home ship. Unlike CraftingStation
## (single-active, stateless, auto-deposit), this drives a persistent model: the first
## interact STARTS production (consuming inputs), and a later interact HARVESTS the produce
## once the model reports ready. The coordinator ticks the model per-frame; this node only
## starts and collects. Mirrors the range/interact/marker contract of crafting_station.gd.

signal production_started(station_kind: String, input_id: String)
signal production_harvested(station_kind: String, item_id: String, qty: int)
signal production_blocked(station_kind: String, reason: String)

var station_kind: String = ""
var model                                  # HydroponicsState | WaterRecyclerState
var inventory_state                        # InventoryState
var power_available: Callable = Callable()  # () -> float
var player_skill: Callable = Callable()     # () -> int
var config: Dictionary = {}                 # hydroponics: {"crops": [...]}
var interaction_radius: float = 1.8

var candidate_player: Node
var collision_shape: CollisionShape3D
var marker: MeshInstance3D

func _ready() -> void:
	monitoring = true
	monitorable = true
	collision_layer = 1
	collision_mask = 1
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)

func configure(p_station_kind: String, p_model, p_inventory_state, p_power_available: Callable, p_player_skill: Callable, p_config: Dictionary, world_position: Vector3, radius := 1.8) -> void:
	assert(p_model != null, "p_model must not be null")
	assert(p_inventory_state != null, "p_inventory_state must not be null")
	assert(radius >= 0.0, "radius must be non-negative")
	station_kind = p_station_kind
	model = p_model
	inventory_state = p_inventory_state
	power_available = p_power_available
	player_skill = p_player_skill
	config = p_config
	interaction_radius = radius
	candidate_player = null
	position = world_position
	name = "ProductionStation_%s" % p_station_kind
	set_meta("production_station", true)
	set_meta("station_kind", station_kind)
	_ensure_collision(radius)
	_ensure_marker(radius)

func set_validation_player_in_range(player_body: Node) -> void:
	candidate_player = player_body

func _avail_power() -> float:
	return float(power_available.call()) if power_available.is_valid() else 0.0

func _skill() -> int:
	return int(player_skill.call()) if player_skill.is_valid() else 0

## Range-gated interact. Returns true when it started or harvested production.
func try_interact(player_body: Node) -> bool:
	if not is_instance_valid(player_body) or model == null or inventory_state == null:
		return false
	if not _is_player_in_direct_range(player_body):
		return false
	if station_kind == "hydroponics":
		return _interact_hydro()
	if station_kind == "water_recycler":
		return _interact_recycler()
	emit_signal("production_blocked", station_kind, "unknown_kind")
	return false

func _interact_hydro() -> bool:
	var HydroState = load("res://scripts/systems/hydroponics_state.gd")
	if model.state == HydroState.State.HARVESTABLE:
		var out: Dictionary = model.harvest()
		return _deposit(str(out.get("item_id", "")), int(out.get("quantity", 0)))
	if model.state == HydroState.State.PLANTED:
		emit_signal("production_blocked", station_kind, "in_progress")
		return false
	# IDLE -> plant the first affordable crop.
	var crops: Array = config.get("crops", []) as Array
	var skill: int = _skill()
	var power: float = _avail_power()
	for crop in crops:
		var c: Dictionary = crop as Dictionary
		var water_cost: float = float(c.get("water_cost", 0.0))
		if int(c.get("required_skill_level", 0)) > skill:
			continue
		if float(inventory_state.get_quantity("purified_water")) < water_cost:
			continue
		if power < float(c.get("power_cost", 0.0)):
			continue
		var res: Dictionary = model.plant(c, skill, float(inventory_state.get_quantity("purified_water")), power)
		if res.get("ok", false):
			inventory_state.remove_item("purified_water", int(ceil(water_cost)))
			emit_signal("production_started", station_kind, str(c.get("crop_id", "")))
			return true
	emit_signal("production_blocked", station_kind, "no_affordable_crop")
	return false

func _interact_recycler() -> bool:
	var RecyclerState = load("res://scripts/systems/water_recycler_state.gd")
	if model.output_ready > 0:
		var out: Dictionary = model.collect_output()
		return _deposit(str(out.get("item_id", "")), int(out.get("quantity", 0)))
	if model.state == RecyclerState.State.RECYCLING:
		emit_signal("production_blocked", station_kind, "in_progress")
		return false
	# IDLE -> load contaminated_water.
	var qty: int = inventory_state.get_quantity("contaminated_water")
	if qty <= 0:
		emit_signal("production_blocked", station_kind, "no_input")
		return false
	if _avail_power() < model.power_cost:
		emit_signal("production_blocked", station_kind, "insufficient_power")
		return false
	var res: Dictionary = model.load_input("contaminated_water", qty, _avail_power())
	if res.get("ok", false):
		inventory_state.remove_item("contaminated_water", qty)
		emit_signal("production_started", station_kind, "contaminated_water")
		return true
	emit_signal("production_blocked", station_kind, str(res.get("reason", "load_failed")))
	return false

func _deposit(item_id: String, qty: int) -> bool:
	if item_id.is_empty() or qty <= 0:
		return false
	var added: int = inventory_state.add_item(item_id, qty)
	if added < qty:
		print("PRODUCTION OVERFLOW item=%s lost=%d reason=stack_full" % [item_id, qty - added])
	emit_signal("production_harvested", station_kind, item_id, qty)
	return true

func _interaction_radius() -> float:
	if is_instance_valid(collision_shape) and collision_shape.shape is SphereShape3D:
		return (collision_shape.shape as SphereShape3D).radius
	return interaction_radius

func _is_player_in_direct_range(player_body: Node) -> bool:
	# Headless validation injects candidate_player via set_validation_player_in_range to
	# bypass the spatial gate (mirrors CraftingStation's validation seam path).
	if candidate_player == player_body:
		return true
	if not is_instance_valid(player_body) or not (player_body is Node3D):
		return false
	var pn: Node3D = player_body as Node3D
	if not is_inside_tree() or not pn.is_inside_tree():
		return false
	return global_position.distance_to(pn.global_position) <= _interaction_radius()

func _ensure_collision(radius: float) -> void:
	if not is_instance_valid(collision_shape):
		collision_shape = CollisionShape3D.new()
		collision_shape.name = "ProductionStationCollisionShape3D"
		add_child(collision_shape)
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	collision_shape.shape = sphere

func _ensure_marker(radius: float) -> void:
	if not is_instance_valid(marker):
		marker = MeshInstance3D.new()
		marker.name = "ProductionStationMarker"
		add_child(marker)
	var box := BoxMesh.new()
	box.size = Vector3(radius * 0.5, radius * 0.5, radius * 0.5)
	marker.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.85, 0.45, 0.7)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	marker.material_override = mat
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.set_meta("debug_production_station_marker", true)

func _on_body_entered(body: Node3D) -> void:
	if body is PlayerController:
		candidate_player = body

func _on_body_exited(body: Node3D) -> void:
	if body == candidate_player:
		candidate_player = null
```

- [ ] **Step 4: Remove the scratch line from the smoke if needed**

If `production_station.gd` has no `st_blocked_seen` field, delete the `st.st_blocked_seen = false` line from `production_station_smoke.gd::_test_recycler` (it is inert but tidy to drop).

- [ ] **Step 5: Run smoke to verify it passes**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/production_station_smoke.gd`
Expected: prints `PRODUCTION STATION PASS hydro_harvest=true recycler_collect=true blocked_in_progress=true`, no unexpected ERROR/WARNING.

- [ ] **Step 6: Commit**

```bash
git add scripts/tools/production_station.gd scripts/validation/production_station_smoke.gd
git commit -m "feat: add ProductionStation node for player-operated food/water production

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01KPbqcGeunTAQouMUN1HWWx"
```

---

### Task 3: Retire orphan `synthesizer_state`

**Files:**
- Modify: `scripts/procgen/playable_generated_ship.gd` (remove field, preload, instantiation, tick line, save read/write, sustenance context key)
- Modify: `scripts/systems/run_snapshot.gd` (remove `synthesizer_summary` from declaration, `SUMMARY_FIELDS`, `to_dict`, `from_dict`)
- Modify: `scripts/systems/sustenance_state.gd` (drop `synthesizer_summary` read; re-source `meals_ready`)
- Modify: `scripts/validation/save_load_service_smoke.gd` (summary count 27 → 26)
- Delete: `scripts/systems/synthesizer_state.gd` and `scripts/validation/synthesizer_state_smoke.gd` if it exists
- Test: `scripts/validation/food_synthesizer_retirement_smoke.gd` (create)

**Interfaces:**
- Consumes: existing crafting `"synthesizer"` station + `craft_at_station_for_validation` (unchanged, canonical synthesizer).
- Produces: `playable.synthesizer_state` no longer exists; `RunSnapshot` carries 26 summary fields; `sustenance_state` rolls up hydroponics + water_recycler only.

- [ ] **Step 1: Write the failing retirement smoke**

Create `scripts/validation/food_synthesizer_retirement_smoke.gd`:

```gdscript
extends SceneTree

## Domain 3 Task 3: synthesizer_state is retired (orphan duplicate of the live crafting
## "synthesizer" station). Asserts:
##  - the coordinator no longer exposes a synthesizer_state model,
##  - the crafting synthesizer still produces synthesized_paste,
##  - a legacy RunSnapshot dict carrying synthesizer_summary still loads clean (key ignored).
## Marker: FOOD SYNTHESIZER RETIREMENT PASS orphan_removed=true crafting_synth_ok=true legacy_load_ok=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const RunSnapshotScript := preload("res://scripts/systems/run_snapshot.gd")
const SaveLoadServiceScript := preload("res://scripts/systems/save_load_service.gd")
const TIMEOUT_FRAMES: int = 300

var main_node: Node
var playable
var frame_count: int = 0
var finished: bool = false

func _initialize() -> void:
	# Legacy-load check is pure and can run immediately.
	if not _legacy_load_ok():
		_fail("legacy snapshot with synthesizer_summary failed to load"); return
	main_node = MAIN_SCENE.instantiate()
	get_root().add_child(main_node)
	process_frame.connect(_on_frame)

func _legacy_load_ok() -> bool:
	var snap = RunSnapshotScript.new()
	var d: Dictionary = snap.to_dict()
	d["synthesizer_summary"] = {"station_type": "synthesizer", "total_power_consumed": 9.0}  # legacy key
	d["slice_version"] = SaveLoadServiceScript.CURRENT_SLICE_VERSION
	var loaded = RunSnapshotScript.from_dict(d, SaveLoadServiceScript.CURRENT_SLICE_VERSION, Engine.get_version_info()["string"])
	return loaded != null

func _on_frame() -> void:
	if finished:
		return
	frame_count += 1
	if playable == null:
		playable = _find_playable(main_node)
	if playable == null or playable.loader == null or not playable.loader.has_loaded_ship() or not playable.playable_started:
		if frame_count > TIMEOUT_FRAMES:
			_fail("playable did not become ready")
		return
	# orphan removed: no synthesizer_state member (get() returns null for a missing var).
	if playable.get("synthesizer_state") != null:
		_fail("synthesizer_state still present on coordinator"); return
	# crafting synthesizer still works.
	if not playable.craft_at_station_for_validation("synthesizer"):
		_fail("crafting synthesizer produced nothing"); return
	playable.advance_crafting_for_validation(60.0)
	finished = true
	print("FOOD SYNTHESIZER RETIREMENT PASS orphan_removed=true crafting_synth_ok=true legacy_load_ok=true")
	_cleanup_and_quit(0)

func _find_playable(node: Node):
	if node.get_class() == "Node" and node.get("playable_started") != null:
		pass
	for child in node.get_children():
		if child.get("playable_started") != null and child.has_method("craft_at_station_for_validation"):
			return child
		var f = _find_playable(child)
		if f != null:
			return f
	return null

func _fail(reason: String) -> void:
	if finished: return
	finished = true
	push_error("FOOD SYNTHESIZER RETIREMENT FAIL reason=%s" % reason)
	_cleanup_and_quit(1)

func _cleanup_and_quit(code: int) -> void:
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	quit(code)
```

> If `_find_playable` here is awkward, copy the exact `_find_playable(node) -> PlayableGeneratedShip` recursion from `scripts/validation/combat_corpse_position_smoke.gd` (it returns the typed node by `node is PlayableGeneratedShip`). Prefer that proven version.

- [ ] **Step 2: Run smoke to verify it fails**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/food_synthesizer_retirement_smoke.gd`
Expected: FAIL `synthesizer_state still present on coordinator` (the model is currently instantiated).

- [ ] **Step 3: Remove `synthesizer_state` from the coordinator**

In `scripts/procgen/playable_generated_ship.gd`:
- Delete the preload line: `const SynthesizerStateScript := preload("res://scripts/systems/synthesizer_state.gd")`.
- Delete the field declaration `var synthesizer_state  # SynthesizerState`.
- Delete the instantiation line `synthesizer_state = SynthesizerStateScript.new()`.
- Delete the home-branch tick lines:
  ```gdscript
  	if synthesizer_state != null and synthesizer_state._cooking.state == CookingStateScript.State.COOKING:
  		synthesizer_state.tick(delta)
  ```
- In the `sustenance_state.tick(delta, { … })` call, delete the line `"synthesizer_summary": synthesizer_state.get_summary() if synthesizer_state != null else {},`.
- Delete the save write `snapshot.synthesizer_summary = synthesizer_state.get_summary()`.
- Delete the save read block:
  ```gdscript
  	if synthesizer_state != null and not snapshot.synthesizer_summary.is_empty():
  		synthesizer_state.apply_summary(snapshot.synthesizer_summary)
  ```

- [ ] **Step 4: Remove the field from `RunSnapshot`**

In `scripts/systems/run_snapshot.gd`:
- Delete `var synthesizer_summary: Dictionary = {}`.
- Remove the `"synthesizer_summary",` entry from the `SUMMARY_FIELDS` const array.
- Remove the `"synthesizer_summary": synthesizer_summary.duplicate(true),` line from `to_dict()`.
- Remove the `snapshot.synthesizer_summary = _deep_copy_dict(dict.get("synthesizer_summary", {}))` line from `from_dict()`.

- [ ] **Step 5: Re-source `sustenance_state`**

In `scripts/systems/sustenance_state.gd::tick`, replace the synthesizer-derived lines. Change:

```gdscript
	var synth: Dictionary = (context.get("synthesizer_summary", {}) as Dictionary).duplicate(true)
	total_power_consumed = float(hydro.get("power_cost", 0.0)) + float(synth.get("power_cost", 0.0)) + float(water.get("power_cost", 0.0))
	if powered_ratio < 0.5:
		total_power_consumed = 0.0
	total_materials_consumed = float(hydro.get("water_cost", 0.0)) + float(water.get("input_quantity", 0)) + maxf(0.0, float((synth.get("ingredients", {}) as Dictionary).size()))
	harvest_ready = 1 if int(hydro.get("state", 0)) == 2 else 0
	meals_ready = 1 if int(synth.get("state", 0)) == 2 else 0
	purified_water_ready = int(water.get("output_ready", 0))
```

to (drop `synth`; `meals_ready` reads an explicit `meals_active` context flag the coordinator passes from the live crafting kitchen/synthesizer, defaulting to 0):

```gdscript
	total_power_consumed = float(hydro.get("power_cost", 0.0)) + float(water.get("power_cost", 0.0))
	if powered_ratio < 0.5:
		total_power_consumed = 0.0
	total_materials_consumed = float(hydro.get("water_cost", 0.0)) + float(water.get("input_quantity", 0))
	harvest_ready = 1 if int(hydro.get("state", 0)) == 2 else 0  # 2 == HydroponicsState.State.HARVESTABLE
	meals_ready = 1 if bool(context.get("meals_active", false)) else 0
	purified_water_ready = int(water.get("output_ready", 0))
```

In the coordinator's `sustenance_state.tick(delta, { … })` context dict (same call site as Step 3), the `synthesizer_summary` key is already removed; add `"meals_active": crafting_state != null and crafting_state.is_crafting(),` so `meals_ready` reflects a live craft. (Confirm `crafting_state.is_crafting()` exists — it is used in `crafting_station.gd`. If it does not, pass `false`.)

- [ ] **Step 6: Update the save-load summary-count smoke**

In `scripts/validation/save_load_service_smoke.gd`:
- Line `if loaded.get_summary_count() != 27:` → `!= 26`.
- Its `_fail("summary_count=%d expected 27" …)` → `expected 26`.
- The marker `print("SAVE LOAD SERVICE PASS round_trip=true version_match=true summaries=27")` → `summaries=26`.
- Update any comment in that file that says "seven SUMMARY_FIELDS" / "27 entries" to "26".

- [ ] **Step 7: Delete the orphan files**

```bash
git rm scripts/systems/synthesizer_state.gd
# Only if it exists:
git rm scripts/validation/synthesizer_state_smoke.gd 2>/dev/null || true
```

Then grep to confirm no remaining references:
```bash
grep -rn "synthesizer_state\|synthesizer_summary\|SynthesizerStateScript" scripts/ docs/game/06_validation_plan.md
```
Expected: only the crafting-recipe `"station_kind": "synthesizer"` data (in `data/`) and any *design-doc* prose remain. No `.gd` code references.

- [ ] **Step 8: Run the retirement smoke + the save-load smoke + the sustenance smoke**

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/food_synthesizer_retirement_smoke.gd
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/save_load_service_smoke.gd
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/sustenance_state_smoke.gd
```
Expected markers: `FOOD SYNTHESIZER RETIREMENT PASS orphan_removed=true crafting_synth_ok=true legacy_load_ok=true`; `SAVE LOAD SERVICE PASS … summaries=26`; the existing sustenance smoke PASS marker (update that smoke if it injects/asserts a `synthesizer_summary` — re-source it to the new contract; if it asserts `meals_ready` from synth state, change it to set `meals_active` in the context).

- [ ] **Step 9: Commit**

```bash
git add scripts/procgen/playable_generated_ship.gd scripts/systems/run_snapshot.gd scripts/systems/sustenance_state.gd scripts/validation/save_load_service_smoke.gd scripts/validation/food_synthesizer_retirement_smoke.gd
git add -u scripts/systems/synthesizer_state.gd
# include the sustenance smoke if you edited it:
# git add scripts/validation/sustenance_state_smoke.gd
git commit -m "refactor: retire orphan synthesizer_state; crafting synthesizer is canonical

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01KPbqcGeunTAQouMUN1HWWx"
```

---

### Task 4: Coordinator wiring — build production stations, signals, interact sweep, validation seam

**Files:**
- Modify: `scripts/procgen/playable_generated_ship.gd`
- Test: `scripts/validation/production_station_wiring_smoke.gd` (create)

**Interfaces:**
- Consumes: `ProductionStation` (Task 2), `_home_local_station_positions()`, `_build_crafting_stations()` call sites, the unified `for st in crafting_stations:` interact sweep, `_register_food_for_spoilage`, `_load_json_dict`, `power_grid_state.get_allocation_ratio("sustenance")`.
- Produces: `production_stations: Array`; `_build_production_stations()`; `_clear_production_stations()`; `_on_production_started/harvested/blocked`; `produce_at_station_for_validation(station_kind: String, harvest: bool) -> bool`.

- [ ] **Step 1: Write the failing wiring smoke**

Create `scripts/validation/production_station_wiring_smoke.gd`:

```gdscript
extends SceneTree

## Domain 3 Task 4: the coordinator builds real hydroponics + water_recycler production
## stations on the home ship and drives them through the REAL interact seam, depositing
## produce into the player inventory and registering it for spoilage.
## Marker: PRODUCTION WIRING PASS hydro=true recycler=true spoilage_registered=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 300

var main_node: Node
var playable
var frame_count: int = 0
var finished: bool = false

func _initialize() -> void:
	main_node = MAIN_SCENE.instantiate()
	get_root().add_child(main_node)
	process_frame.connect(_on_frame)

func _on_frame() -> void:
	if finished: return
	frame_count += 1
	if playable == null:
		playable = _find_playable(main_node)
	if playable == null or playable.loader == null or not playable.loader.has_loaded_ship() or not playable.playable_started:
		if frame_count > TIMEOUT_FRAMES:
			_fail("playable not ready")
		return
	_validate()

func _validate() -> void:
	# Give the player the inputs and ensure the sustenance power band is up.
	var home_mgr = playable.get_ship_systems_manager()
	for sub in ["reactor_core", "power_distribution", "battery_cells"]:
		home_mgr.force_repair("power", sub)
	playable.inventory_state.add_item("contaminated_water", 4)
	playable.inventory_state.add_item("purified_water", 5)

	# --- Recycler: load -> advance -> collect ---
	if not playable.produce_at_station_for_validation("water_recycler", false):
		_fail("recycler load failed"); return
	for i in range(120):
		playable._process(1.0)
	if not playable.produce_at_station_for_validation("water_recycler", true):
		_fail("recycler collect failed"); return
	var recycler_ok: bool = playable.inventory_state.get_quantity("purified_water") >= 5

	# --- Hydroponics: plant -> advance -> harvest ---
	if not playable.produce_at_station_for_validation("hydroponics", false):
		_fail("hydroponics plant failed"); return
	for i in range(200):
		playable._process(1.0)
	if not playable.produce_at_station_for_validation("hydroponics", true):
		_fail("hydroponics harvest failed"); return
	var hydro_ok: bool = playable.inventory_state.get_quantity("hydroponic_greens") >= 1
	var spoilage_ok: bool = playable.spoilage_state != null and playable.spoilage_state.has_food("hydroponic_greens")

	if recycler_ok and hydro_ok and spoilage_ok:
		finished = true
		print("PRODUCTION WIRING PASS hydro=true recycler=true spoilage_registered=true")
		_cleanup_and_quit(0)
	else:
		_fail("recycler_ok=%s hydro_ok=%s spoilage_ok=%s" % [str(recycler_ok), str(hydro_ok), str(spoilage_ok)])

func _find_playable(node):
	for child in node.get_children():
		if child.get("playable_started") != null and child.has_method("produce_at_station_for_validation"):
			return child
		var f = _find_playable(child)
		if f != null:
			return f
	return null

func _fail(reason: String) -> void:
	if finished: return
	finished = true
	push_error("PRODUCTION WIRING FAIL reason=%s" % reason)
	_cleanup_and_quit(1)

func _cleanup_and_quit(code: int) -> void:
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	quit(code)
```

> Use the proven typed `_find_playable` from `combat_corpse_position_smoke.gd` if the duck-typed one above misbehaves. Confirm `spoilage_state.has_food(item_id)` exists (it is used by `_register_food_for_spoilage`).

- [ ] **Step 2: Run smoke to verify it fails**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/production_station_wiring_smoke.gd`
Expected: FAIL `playable not ready` → no, it will FAIL at `produce_at_station_for_validation` not existing (parse/missing-method). Either way, no PASS marker.

- [ ] **Step 3: Add the production-station field + builder + clearer**

In `scripts/procgen/playable_generated_ship.gd`:

Add a preload near the other tool preloads:
```gdscript
const ProductionStationScript := preload("res://scripts/tools/production_station.gd")
```
Add a field near `var crafting_stations: Array = []`:
```gdscript
var production_stations: Array = []
```
Add the crops-config path near the other config path constants (e.g. next to `FACILITY_UPGRADES_CONFIG_PATH`):
```gdscript
const HYDROPONICS_CROPS_CONFIG_PATH := "res://data/crops/hydroponics_crops.json"
```
Add the builder + clearer, modeled on `_build_crafting_stations()` / `_clear_crafting_stations()`:
```gdscript
func _build_production_stations() -> void:
	_clear_production_stations()
	if away_from_start or home_ship == null or not is_instance_valid(home_ship.scene_root):
		return
	if hydroponics_state == null or water_recycler_state == null or inventory_state == null:
		return
	var crops_cfg: Dictionary = _load_json_dict(HYDROPONICS_CROPS_CONFIG_PATH)
	var positions: Array = _home_local_station_positions()
	var y: float = PLAYER_SPAWN_HEIGHT_ABOVE_NAV_FLOOR
	var specs: Array = [
		{"kind": "hydroponics", "model": hydroponics_state, "config": crops_cfg},
		{"kind": "water_recycler", "model": water_recycler_state, "config": {}},
	]
	var power_cb: Callable = func() -> float:
		# Boolean power gate as a large float: the sustenance band either powers the
		# station (>= half allocation) or it does not. Mirrors how crafting stations
		# treat power as an on/off gate via set_power(ratio >= threshold).
		var ratio: float = power_grid_state.get_allocation_ratio("sustenance") if power_grid_state != null else 0.0
		return 999.0 if ratio >= 0.5 else 0.0
	var skill_cb: Callable = func() -> int:
		return int(player_progression.get_skill_level("fabrication")) if player_progression != null and player_progression.has_method("get_skill_level") else 0
	var idx: int = 0
	for spec in specs:
		var pos: Vector3 = positions[idx % positions.size()] if not positions.is_empty() else Vector3(float(idx) * 2.0, y, 0.0)
		idx += 1
		var st = ProductionStationScript.new()
		st.configure(str(spec["kind"]), spec["model"], inventory_state, power_cb, skill_cb, spec["config"] as Dictionary, pos, 1.8)
		if not st.production_started.is_connected(_on_production_started):
			st.production_started.connect(_on_production_started)
		if not st.production_harvested.is_connected(_on_production_harvested):
			st.production_harvested.connect(_on_production_harvested)
		if not st.production_blocked.is_connected(_on_production_blocked):
			st.production_blocked.connect(_on_production_blocked)
		home_ship.scene_root.add_child(st)
		production_stations.append(st)

func _clear_production_stations() -> void:
	for st in production_stations:
		if is_instance_valid(st):
			var p = st.get_parent()
			if is_instance_valid(p):
				p.remove_child(st)
			st.queue_free()
	production_stations.clear()
```

- [ ] **Step 4: Add the signal handlers + validation seam**

Add near `_on_craft_started` / `_on_craft_completed`:
```gdscript
func _on_production_started(station_kind: String, input_id: String) -> void:
	_refresh_inventory_hud()
	_recompute_player_encumbrance()
	print("PRODUCTION STARTED station=%s input=%s" % [station_kind, input_id])

func _on_production_harvested(station_kind: String, item_id: String, qty: int) -> void:
	# The station already deposited into inventory; register the produce for spoilage
	# (mirrors _on_craft_completed) and refresh HUD/encumbrance.
	_register_food_for_spoilage(item_id)
	_refresh_inventory_hud()
	_recompute_player_encumbrance()
	print("PRODUCTION HARVESTED station=%s item=%s qty=%d" % [station_kind, item_id, qty])

func _on_production_blocked(station_kind: String, reason: String) -> void:
	print("PRODUCTION BLOCKED station=%s reason=%s" % [station_kind, reason])

## Validation seam (mirrors craft_at_station_for_validation): teleport the player onto a
## production station and interact. harvest=false starts production; harvest=true collects.
func produce_at_station_for_validation(station_kind: String, harvest: bool) -> bool:
	if not is_instance_valid(player):
		return false
	for st in production_stations:
		if is_instance_valid(st) and st.station_kind == station_kind:
			if player.has_method("teleport_to"):
				player.teleport_to(st.global_position)
			st.set_validation_player_in_range(player)
			return st.try_interact(player)
	return false
```

> `harvest` is accepted for call-site clarity; the node infers start-vs-harvest from model state, so the seam need not branch on it. Keep the param (the smokes pass it) but you may leave it unused or `var _ = harvest`.

- [ ] **Step 5: Call the builder at the three crafting-station build sites + add to the interact sweep**

- Find every call to `_build_crafting_stations()` (research showed 3 sites — boot, rebuild, restore). Immediately after each, add `_build_production_stations()`.
- In the unified player-interact sweep, right after the `crafting_stations` loop:
  ```gdscript
  	for st in crafting_stations:
  		if is_instance_valid(st) and st.try_interact(player_body):
  			return true
  ```
  add:
  ```gdscript
  	for st in production_stations:
  		if is_instance_valid(st) and st.try_interact(player_body):
  			return true
  ```

- [ ] **Step 6: Run the wiring smoke to verify it passes**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/production_station_wiring_smoke.gd`
Expected: `PRODUCTION WIRING PASS hydro=true recycler=true spoilage_registered=true`, no unexpected ERROR/WARNING. (If a `PRODUCTION OVERFLOW`/`PRODUCTION BLOCKED` line appears, diagnose: ensure power band is up via `force_repair` and inputs are seeded.)

- [ ] **Step 7: Commit**

```bash
git add scripts/procgen/playable_generated_ship.gd scripts/validation/production_station_wiring_smoke.gd
git commit -m "feat: wire hydroponics + water_recycler production stations into coordinator

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01KPbqcGeunTAQouMUN1HWWx"
```

---

### Task 5: Away-branch food tick (`_tick_food_runtime`) on BOTH `_process` branches

**Files:**
- Modify: `scripts/procgen/playable_generated_ship.gd`
- Test: `scripts/validation/food_away_tick_smoke.gd` (create)

**Interfaces:**
- Consumes: `spoilage_state`, `hydroponics_state`, `water_recycler_state`, the home-branch food tick block (synthesizer line already removed in Task 3).
- Produces: `_tick_food_runtime(delta: float)` called from both `_process` branches.

- [ ] **Step 1: Write the failing away-tick smoke**

Create `scripts/validation/food_away_tick_smoke.gd`:

```gdscript
extends SceneTree

## Domain 3 Task 5: spoilage AND in-progress production advance on the AWAY (derelict)
## branch. Drives away_from_start = true and asserts a planted crop's growth advances and
## a tracked food's spoilage age advances while boarded.
## Marker: FOOD AWAY TICK PASS away_ticks=<n> crop_grew=true spoiled_away=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const HydroStateScript := preload("res://scripts/systems/hydroponics_state.gd")
const TIMEOUT_FRAMES: int = 300

var main_node: Node
var playable
var frame_count: int = 0
var finished: bool = false

func _initialize() -> void:
	main_node = MAIN_SCENE.instantiate()
	get_root().add_child(main_node)
	process_frame.connect(_on_frame)

func _on_frame() -> void:
	if finished: return
	frame_count += 1
	if playable == null:
		playable = _find_playable(main_node)
	if playable == null or playable.loader == null or not playable.loader.has_loaded_ship() or not playable.playable_started:
		if frame_count > TIMEOUT_FRAMES:
			_fail("playable not ready")
		return
	_validate()

func _validate() -> void:
	# Plant a crop directly on the model (state under test is the TICK, not the station).
	var crop := {"crop_id": "hydroponic_greens", "produce_item_id": "hydroponic_greens",
		"produce_quantity": 3, "growth_seconds": 600.0, "water_cost": 0.0, "power_cost": 0.0,
		"required_skill_level": 0}
	playable.hydroponics_state.plant(crop, 0, 99.0, 99.0)
	# Track a food for spoilage.
	playable._register_food_for_spoilage("cooked_meal")
	playable.inventory_state.add_item("cooked_meal", 1)
	playable._register_food_for_spoilage("cooked_meal")

	var growth_before: float = playable.hydroponics_state.progress_seconds
	var spoil_before: float = _spoil_age("cooked_meal")

	# Force the AWAY branch.
	playable.away_from_start = true
	var n: int = 0
	for i in range(30):
		playable._process(1.0)
		n += 1

	var crop_grew: bool = playable.hydroponics_state.progress_seconds > growth_before + 1.0
	var spoiled_away: bool = _spoil_age("cooked_meal") > spoil_before + 1.0

	if crop_grew and spoiled_away:
		finished = true
		print("FOOD AWAY TICK PASS away_ticks=%d crop_grew=true spoiled_away=true" % n)
		_cleanup_and_quit(0)
	else:
		_fail("crop_grew=%s spoiled_away=%s" % [str(crop_grew), str(spoiled_away)])

func _spoil_age(item_id: String) -> float:
	var s = playable.spoilage_state
	if s == null:
		return 0.0
	# spoilage summary carries per-item age; read defensively.
	var summary: Dictionary = s.get_summary()
	var foods: Variant = summary.get("foods", summary)
	if typeof(foods) == TYPE_DICTIONARY and (foods as Dictionary).has(item_id):
		var entry = (foods as Dictionary)[item_id]
		if typeof(entry) == TYPE_DICTIONARY:
			return float((entry as Dictionary).get("age_seconds", (entry as Dictionary).get("elapsed_seconds", 0.0)))
	return 0.0

func _find_playable(node):
	for child in node.get_children():
		if child.get("playable_started") != null and child.get("hydroponics_state") != null:
			return child
		var f = _find_playable(child)
		if f != null:
			return f
	return null

func _fail(reason: String) -> void:
	if finished: return
	finished = true
	push_error("FOOD AWAY TICK FAIL reason=%s" % reason)
	_cleanup_and_quit(1)

func _cleanup_and_quit(code: int) -> void:
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	quit(code)
```

> Before relying on `_spoil_age`, open `scripts/systems/spoilage_state.gd` and read the real `get_summary()` shape; adjust the key path (`foods`/`age_seconds`) to match exactly. The assertion only needs *some* monotonically increasing age field for a tracked food.

- [ ] **Step 2: Run smoke to verify it fails**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/food_away_tick_smoke.gd`
Expected: FAIL `crop_grew=false spoiled_away=false` — the away branch currently returns before any food tick.

- [ ] **Step 3: Extract `_tick_food_runtime` and call it from the home branch**

In `scripts/procgen/playable_generated_ship.gd`, replace the home-branch food tick block (the `# ADR-0034: tick food / cooking / spoilage / sustenance models.` block — now without the synthesizer lines removed in Task 3) with a single call, and add the helper:

Replace:
```gdscript
	# ADR-0034: tick food / cooking / spoilage / sustenance models.
	if spoilage_state != null:
		spoilage_state.tick(delta)
	if hydroponics_state != null and hydroponics_state.state == HydroponicsStateScript.State.PLANTED:
		hydroponics_state.tick(delta)
	if water_recycler_state != null and water_recycler_state.state == WaterRecyclerStateScript.State.RECYCLING:
		water_recycler_state.tick(delta)
```
with:
```gdscript
	# ADR-0034 / Domain 3: tick food spoilage + production (shared by BOTH _process branches).
	_tick_food_runtime(delta)
```

Add the helper (place it near the other `_tick_*` helpers):
```gdscript
## Domain 3: advance food spoilage and in-progress production. Called from BOTH _process
## branches. DELIBERATE divergence from crafting (powered crafting stations PAUSE while away):
## growth/recycling are time-based biological/chemical processes that do not require the
## player aboard, so a crop planted before boarding keeps growing on the derelict run and is
## HARVESTABLE on return. Spoilage is likewise time-based and must not freeze on a derelict.
func _tick_food_runtime(delta: float) -> void:
	if spoilage_state != null:
		spoilage_state.tick(delta)
	if hydroponics_state != null and hydroponics_state.state == HydroponicsStateScript.State.PLANTED:
		hydroponics_state.tick(delta)
	if water_recycler_state != null and water_recycler_state.state == WaterRecyclerStateScript.State.RECYCLING:
		water_recycler_state.tick(delta)
```

- [ ] **Step 4: Call the helper from the AWAY branch**

In the `if away_from_start:` branch of `_process`, add the call just before the `return` (after the audio tick block, alongside the other away-branch ticks):
```gdscript
		# Domain 3: food spoilage + production advance on the derelict branch too (see
		# _tick_food_runtime — deliberate divergence from crafting, which pauses away).
		_tick_food_runtime(delta)
```

- [ ] **Step 5: Run the away-tick smoke to verify it passes**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/food_away_tick_smoke.gd`
Expected: `FOOD AWAY TICK PASS away_ticks=30 crop_grew=true spoiled_away=true`, no unexpected ERROR/WARNING.

- [ ] **Step 6: Commit**

```bash
git add scripts/procgen/playable_generated_ship.gd scripts/validation/food_away_tick_smoke.gd
git commit -m "fix: tick food spoilage + production on the away branch via _tick_food_runtime

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01KPbqcGeunTAQouMUN1HWWx"
```

---

### Task 6: End-to-end scene smoke (production + away) and bundle registration

**Files:**
- Create: `scripts/validation/main_playable_food_production_smoke.gd`
- Modify: `docs/game/06_validation_plan.md` (register 6 new markers, bump `commands=68` → `commands=74`)

**Interfaces:**
- Consumes: everything from Tasks 1–5 (`produce_at_station_for_validation`, `_tick_food_runtime`, `production_stations`).
- Produces: one flagship scene smoke proving the full home→away food production path; all 6 Domain-3 markers registered in the regression bundle.

> The 6 new smokes registered by the end of this task: `contaminated_water_item_smoke` (Task 1), `production_station_smoke` (Task 2), `food_synthesizer_retirement_smoke` (Task 3), `production_station_wiring_smoke` (Task 4), `food_away_tick_smoke` (Task 5), and `main_playable_food_production_smoke` (this task). Final bundle count: 68 + 6 = **74**. Reconcile the echo number against `grep -c "run_clean '"` in Step 3.

- [ ] **Step 1: Write the flagship end-to-end smoke**

Create `scripts/validation/main_playable_food_production_smoke.gd` combining home production + an away-spoilage assertion in one run:

```gdscript
extends SceneTree

## Domain 3 flagship: full food production loop on the home ship (recycle -> plant -> harvest
## into inventory + spoilage-registered) AND spoilage continuing on the away branch.
## Marker: MAIN PLAYABLE FOOD PRODUCTION PASS harvested=true recycled=true away_ticks=<n> spoiled_away=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 300

var main_node: Node
var playable
var frame_count: int = 0
var finished: bool = false

func _initialize() -> void:
	main_node = MAIN_SCENE.instantiate()
	get_root().add_child(main_node)
	process_frame.connect(_on_frame)

func _on_frame() -> void:
	if finished: return
	frame_count += 1
	if playable == null:
		playable = _find_playable(main_node)
	if playable == null or playable.loader == null or not playable.loader.has_loaded_ship() or not playable.playable_started:
		if frame_count > TIMEOUT_FRAMES:
			_fail("playable not ready")
		return
	_validate()

func _validate() -> void:
	var home_mgr = playable.get_ship_systems_manager()
	for sub in ["reactor_core", "power_distribution", "battery_cells"]:
		home_mgr.force_repair("power", sub)
	playable.inventory_state.add_item("contaminated_water", 4)
	playable.inventory_state.add_item("purified_water", 5)

	if not playable.produce_at_station_for_validation("water_recycler", false):
		_fail("recycler load failed"); return
	for i in range(120): playable._process(1.0)
	playable.produce_at_station_for_validation("water_recycler", true)
	var recycled: bool = playable.inventory_state.get_quantity("purified_water") >= 5

	if not playable.produce_at_station_for_validation("hydroponics", false):
		_fail("hydroponics plant failed"); return
	for i in range(200): playable._process(1.0)
	playable.produce_at_station_for_validation("hydroponics", true)
	var harvested: bool = playable.inventory_state.get_quantity("hydroponic_greens") >= 1 \
		and playable.spoilage_state.has_food("hydroponic_greens")

	# Away-branch spoilage.
	var spoil_before: float = _spoil_age("hydroponic_greens")
	playable.away_from_start = true
	var n: int = 0
	for i in range(30):
		playable._process(1.0); n += 1
	var spoiled_away: bool = _spoil_age("hydroponic_greens") > spoil_before + 1.0

	if recycled and harvested and spoiled_away:
		finished = true
		print("MAIN PLAYABLE FOOD PRODUCTION PASS harvested=true recycled=true away_ticks=%d spoiled_away=true" % n)
		_cleanup_and_quit(0)
	else:
		_fail("recycled=%s harvested=%s spoiled_away=%s" % [str(recycled), str(harvested), str(spoiled_away)])

func _spoil_age(item_id: String) -> float:
	var s = playable.spoilage_state
	if s == null: return 0.0
	var summary: Dictionary = s.get_summary()
	var foods: Variant = summary.get("foods", summary)
	if typeof(foods) == TYPE_DICTIONARY and (foods as Dictionary).has(item_id):
		var entry = (foods as Dictionary)[item_id]
		if typeof(entry) == TYPE_DICTIONARY:
			return float((entry as Dictionary).get("age_seconds", (entry as Dictionary).get("elapsed_seconds", 0.0)))
	return 0.0

func _find_playable(node):
	for child in node.get_children():
		if child.get("playable_started") != null and child.has_method("produce_at_station_for_validation"):
			return child
		var f = _find_playable(child)
		if f != null: return f
	return null

func _fail(reason: String) -> void:
	if finished: return
	finished = true
	push_error("MAIN PLAYABLE FOOD PRODUCTION FAIL reason=%s" % reason)
	_cleanup_and_quit(1)

func _cleanup_and_quit(code: int) -> void:
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	quit(code)
```

> Match `_spoil_age` to the real `spoilage_state.get_summary()` shape (read the file). Reuse the exact key path you settled on in Task 5.

- [ ] **Step 2: Run the flagship smoke**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_food_production_smoke.gd`
Expected: `MAIN PLAYABLE FOOD PRODUCTION PASS harvested=true recycled=true away_ticks=30 spoiled_away=true`.

- [ ] **Step 3: Register every new marker in the bundle**

In `docs/game/06_validation_plan.md`, in the `run_clean` block (near the other food smokes around line 105–108), add one `run_clean` line per new smoke, copying the exact marker substring each smoke prints:

```bash
run_clean 'Domain3 contaminated_water item smoke' 'CONTAMINATED WATER ITEM PASS defined=true supply=true lootable=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/contaminated_water_item_smoke.gd
run_clean 'Domain3 production station unit smoke' 'PRODUCTION STATION PASS hydro_harvest=true recycler_collect=true blocked_in_progress=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/production_station_smoke.gd
run_clean 'Domain3 synthesizer retirement smoke' 'FOOD SYNTHESIZER RETIREMENT PASS orphan_removed=true crafting_synth_ok=true legacy_load_ok=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/food_synthesizer_retirement_smoke.gd
run_clean 'Domain3 production wiring smoke' 'PRODUCTION WIRING PASS hydro=true recycler=true spoilage_registered=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/production_station_wiring_smoke.gd
run_clean 'Domain3 food away tick smoke' 'FOOD AWAY TICK PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/food_away_tick_smoke.gd
run_clean 'Domain3 main playable food production smoke' 'MAIN PLAYABLE FOOD PRODUCTION PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_food_production_smoke.gd
```

That is **6** new `run_clean` lines. Update the final echo: `commands=68` → `commands=74`. (68 + 6 = 74. Verify with `grep -c "run_clean '" docs/game/06_validation_plan.md` — it must equal the new echo number.)

> Note: `save_load_service_smoke`'s marker text changed (`summaries=27` → `summaries=26`) in Task 3. If its `run_clean` line in the bundle greps the `summaries=27` substring, update that substring to `summaries=26`. Grep for it: `grep -n "summaries=27" docs/game/06_validation_plan.md`.

- [ ] **Step 4: Run the FULL regression bundle**

Extract and run the bundle with Windows paths (the doc hardcodes macOS `ROOT`/`GODOT`):

```bash
GODOT="C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe"
ROOT="C:/Users/dasbl/Documents/The Synaptic Sea"
awk '/^ROOT=/{f=1} f{print} /clean_output=true/{exit}' "$ROOT/docs/game/06_validation_plan.md" \
  | sed "s|^ROOT=.*|ROOT=\"$ROOT\"|; s|^GODOT=.*|GODOT=\"$GODOT\"|" > /tmp/domain3_bundle.sh
bash /tmp/domain3_bundle.sh; echo "EXIT=$?"
```
Expected final line: `SYNAPTIC_SEA REGRESSION PASS commands=74 clean_output=true`, `EXIT=0`.
**Verify rigorously (the bundle's marker grep is unchecked — only ERROR/WARNING triggers exit 1):** confirm `EXIT=0`, the printed `=== ` section count equals 74 (`grep -c '^=== ' <output>`), zero `FAIL`, zero `UNEXPECTED`. If any smoke's marker is missing despite a green echo, that smoke regressed — fix before continuing.

- [ ] **Step 5: Commit**

```bash
git add scripts/validation/main_playable_food_production_smoke.gd docs/game/06_validation_plan.md
git commit -m "test: add flagship food production smoke; register Domain 3 markers (bundle 74)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01KPbqcGeunTAQouMUN1HWWx"
```

---

### Task 7: Inventory deltas + regeneration

**Files:**
- Modify: `docs/game/inventory/system_inventory.json` (the canonical source)
- Regenerate: `docs/game/inventory/SYSTEM_INVENTORY.md` + `docs/game/inventory/system_map.html` (via the tool)

**Interfaces:**
- Consumes: the closed `food` loop from Tasks 1–6.
- Produces: an inventory that reflects the closed loop, passes `--check`/`--coverage`/self-test, and contains **no cross-entry semantic contradiction**.

- [ ] **Step 1: Read the inventory tool + current food entries**

```bash
grep -n "food\|hydroponics_state\|water_recycler_state\|synthesizer_state\|sustenance_state" docs/game/inventory/system_inventory.json | head -40
python tools/build_system_inventory.py --help 2>/dev/null | head -20
```
Note the exact JSON shape of a loop entry (`closes`, `steps`, break-points) and a system entry (`output.live`, `gaps`, `desc`, `confidence`).

- [ ] **Step 2: Apply the deltas in `system_inventory.json`**

- `food` loop: set `closes` (or the equivalent status field) to `"closed"`; rewrite its break-points to describe the now-live production (hydroponics + water_recycler player-operated; spoilage + production tick on the away branch). Remove the stale "production half is fully dead" language.
- `hydroponics_state`: set `output.live → true`; record `ProductionStation` (player-operated) as the live caller; clear the "no runtime callers" gap.
- `water_recycler_state`: set `output.live → true`; record `ProductionStation` caller + `contaminated_water` input; clear the dead-output gap.
- `synthesizer_state`: mark **retired/removed**; note the synthesizer loop closes via `CraftingState` (crafting `"synthesizer"` station). If the inventory tracks a fixed system count, decrement it by 1 for this removal (and add 1 if you add a `production_station` entry — net zero).
- `sustenance_state`: record the HUD (`get_status_lines`) as its live consumer; note it now rolls up hydroponics + water_recycler (+ `meals_active`) and no longer reads the retired synthesizer.
- Optionally add a `production_station` node entry if the inventory tracks nodes of this kind (mirror the `crafting_station` entry shape).
- **Cross-entry consistency:** grep the JSON for any remaining text claiming food production is dead / hydroponics has no caller / spoilage is home-only, and fix every occurrence (this contradiction class slipped past `--check` in Domains 1 and 2 and was caught only by review).

- [ ] **Step 3: Regenerate the views**

```bash
python tools/build_system_inventory.py
```
Expected: regenerates `SYSTEM_INVENTORY.md` + `system_map.html` from the JSON.

- [ ] **Step 4: Run the inventory gates**

```bash
python tools/build_system_inventory.py --check
python tools/build_system_inventory.py --coverage
python tools/test_build_system_inventory.py
```
Expected markers: `SYSTEM INVENTORY CHECK PASS systems=<N> verified=<N>` (N reflects the net count), the coverage PASS line, and `BUILD INVENTORY SELFTEST PASS`. If `--check` reports a count mismatch, reconcile the `systems=` total with your add/remove.

- [ ] **Step 5: Commit**

```bash
git add docs/game/inventory/system_inventory.json docs/game/inventory/SYSTEM_INVENTORY.md docs/game/inventory/system_map.html
git commit -m "docs: close the food loop in the system inventory (Domain 3)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01KPbqcGeunTAQouMUN1HWWx"
```

---

## Self-Review (completed)

**1. Spec coverage:**
- Player-initiated + manual harvest production → Tasks 2 (node), 4 (wiring). ✅
- Spoilage + production tick on away branch → Task 5. ✅
- `sustenance_state` kept + re-sourced → Task 3 (Steps 5). ✅
- `synthesizer_state` retired (no version bump, per the post-spec decision) → Task 3. ✅
- `contaminated_water` input + renewable water chain → Task 1. ✅
- Three+ smokes + bundle registration → Tasks 1,2,3,4,5,6. ✅
- Inventory deltas + regeneration + cross-entry consistency → Task 7. ✅

**2. Placeholder scan:** No "TBD"/"handle edge cases"/"similar to Task N". Each code step shows complete code. The few "read the real shape and match it" notes (spoilage summary key path, loot-table entry schema, item-defs loader path) are explicit verification instructions, not placeholders — they name the file and the exact field to confirm.

**3. Type consistency:** `ProductionStation.configure(station_kind, model, inventory_state, power_available, player_skill, config, world_position, radius)` and signals `production_started/harvested/blocked` are used identically in Tasks 2, 4, and the smokes. `produce_at_station_for_validation(station_kind, harvest)` matches across Tasks 4 and 6. `_tick_food_runtime(delta)` defined and called consistently in Task 5. `RunSnapshot` summary count 27→26 is consistent across Task 3 (Steps 4, 6).

## Notes for the executor

- **Bundle math:** baseline `commands=68` on this branch; Task 6 adds 6 `run_clean` lines → `commands=74`. Always reconcile the echo number against `grep -c "run_clean '"`.
- **Away-branch divergence** (food production continues away while crafting pauses) is intentional and documented at the `_tick_food_runtime` call site; do not "fix" it to match crafting.
- **Power gate** is modeled as a boolean-as-large-float (999.0 when the sustenance band is ≥ 50% allocated, else 0.0), matching how crafting treats station power as on/off. The validation seams seed power via `force_repair`.
- **RID/leak hygiene:** scene smokes must `queue_free()` the instantiated `main_node` on every exit path (the templates above do). Pure-model smokes that `.new()` a bare ThreatManager-style node must free it — the production smokes here use either pure RefCounted models or the full scene, so no bare-node leak, but keep this in mind if you add nodes.
- **TRUST THE PASS MARKER, not the exit code**, on every smoke run.
