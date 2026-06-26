# Ship Repair Loop (sub-project #4) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Spend looted parts on a Project-Zomboid-style timed repair of ship subcomponents, and make repairing the lifeboat's propulsion gate travel — closing the loot → repair → fly loop.

**Architecture:** Wire the existing deterministic `ShipSubcomponent.repair` model to real `InventoryState` (consume parts) via a new `ShipSystemsManager.repair_with_inventory`. A new `RepairPoint` Area3D node drives a timed channel (its own `_process`, independent of the coordinator's frozen per-frame loop) and calls that on completion. The coordinator builds repair points from the live systems manager for the lifeboat + derelicts, re-points the travel gate to the lifeboat's real systems, curates the lifeboat to boot with propulsion offline, and lifts loot to the starting ship.

**Tech Stack:** Godot 4.6.2, typed GDScript, headless `--script` validation smokes.

## Global Constraints

- **Godot binary (headless):** `C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe`
- **Project root:** `C:/Users/dasbl/Documents/The Synaptic Sea`
- **Validation is the definition of done.** A task is done only when its smoke prints its exact PASS marker AND no unexpected `ERROR:`/`WARNING:` lines appear. `--script` can exit 0 on parse errors — trust the marker, not the exit code.
- **Allowlisted teardown noise (ignore):** `ERROR: Capture not registered: 'gdaimcp'.` and `WARNING: ObjectDB instances leaked at exit ...`. The save/load service smoke additionally emits one expected `WARNING: SaveLoadService: save file rejected by from_dict ...`. Any other `ERROR:`/`WARNING:` line blocks completion.
- **Class-cache portability:** the new `class_name` script `RepairPoint` is NOT in the committed `global_script_class_cache.cfg` and `--headless --script` does not rebuild it. Construct it via a `preload(...)` const + `.new()` in the coordinator — NEVER a bare `RepairPoint.new()` or a `: RepairPoint` annotation in another script. `ShipSystemsManager`/`InventoryState` are already in the cache and may keep bare/`class_name` refs.
- **Home loop must stay green:** the existing objective→`force_repair` bridge (`OBJECTIVE_REPAIR_MAP`), the reactor/extraction flow, the derelict `_process` freeze, and gate-1 must be unchanged in behavior. Repair points are an ADDITIONAL path.
- **No stranding:** `travel_home()` is always available regardless of systems state.
- **Timed repair only:** repair is a channel (consume + restore on completion), never instant; cancels with no part loss if the player leaves range; mid-channel progress is not persisted.
- **Typed GDScript.** **Conventional Commits.** Commit trailer: `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.
- **Do not commit** `.godot/`, `*.uid`, or `addons/`. Selective `git add` of named files only — never `git add -A`.
- **Scope (non-goals):** no multi-ship docking entity / cannibalizing; no crafting (generic salvage inert); no new repair-skill curve (`min_skill` gates the existing progression); no `supply`-item consumption.

Run a smoke:
```bash
GODOT="C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe"
ROOT="C:/Users/dasbl/Documents/The Synaptic Sea"
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/<smoke_name>.gd
```

---

### Task 1: Expand the parts/tools vocabulary (data) so repairs can be fed by loot

**Files:**
- Modify: `data/items/item_definitions.json`
- Modify: `data/items/loot_tables.json`
- Modify (test): `scripts/validation/item_inventory_smoke.gd`

**Interfaces:**
- Consumes: nothing.
- Produces: every part id used by `data/ship_systems/systems.json` (`reactor_core`, `power_cell`, `oxygen_filter`, `sealant`, `plating`, `circuit_board`, `data_core`, `thruster_nozzle`, `fuel_line`, `sensor_module`) resolves in `InventoryState` as category `part`; the two repair tools (`welder`, `plasma_cutter`) resolve as category `tool`. Loot tables can drop them.

- [ ] **Step 1: Add a failing assertion to `item_inventory_smoke.gd`**

Add a new check function and call it from `_initialize()`, AND it into the pass gate + marker. Insert this function:

```gdscript
func _test_repair_vocabulary() -> bool:
	var inv = InventoryStateScript.new()
	# Every part required by systems.json must resolve as a 'part'.
	for part_id in ["reactor_core", "power_cell", "oxygen_filter", "sealant", "plating",
			"circuit_board", "data_core", "thruster_nozzle", "fuel_line", "sensor_module"]:
		if inv.get_category(part_id) != "part":
			return false
		if inv.get_weight_each(part_id) <= 0.0:
			return false
	# The two repair tools must resolve as 'tool'.
	for tool_id in ["welder", "plasma_cutter"]:
		if inv.get_category(tool_id) != "tool":
			return false
	return true
```

In `_initialize()`, add `var ok_repair: bool = _test_repair_vocabulary()`, AND it into the success condition, and extend the marker to end with ` repair_vocab=%s` (`str(ok_repair).to_lower()`). The new marker on pass becomes:
`ITEM INVENTORY PASS add=true weight_cap=true round_trip=true legacy_compat=true repair_vocab=true`.

- [ ] **Step 2: Run the test to verify it fails**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/item_inventory_smoke.gd`
Expected: FAIL — the repair part ids are not in `item_definitions.json` yet (`get_category` returns "").

- [ ] **Step 3: Add the repair parts + tools to `data/items/item_definitions.json`**

Add these entries (merge into the existing object, keep the existing `power_cell`/`scrap_metal`/`wiring_spool`/`ration_pack`/`medkit`):

```json
  "reactor_core":    { "display_name": "Reactor Core",    "category": "part", "weight": 12.0, "max_stack": 2 },
  "oxygen_filter":   { "display_name": "Oxygen Filter",   "category": "part", "weight": 1.5, "max_stack": 10 },
  "sealant":         { "display_name": "Sealant",         "category": "part", "weight": 1.0, "max_stack": 20 },
  "plating":         { "display_name": "Hull Plating",    "category": "part", "weight": 8.0, "max_stack": 10 },
  "circuit_board":   { "display_name": "Circuit Board",   "category": "part", "weight": 1.0, "max_stack": 15 },
  "data_core":       { "display_name": "Data Core",       "category": "part", "weight": 2.0, "max_stack": 10 },
  "thruster_nozzle": { "display_name": "Thruster Nozzle", "category": "part", "weight": 9.0, "max_stack": 5 },
  "fuel_line":       { "display_name": "Fuel Line",       "category": "part", "weight": 3.0, "max_stack": 10 },
  "sensor_module":   { "display_name": "Sensor Module",   "category": "part", "weight": 2.5, "max_stack": 10 },
  "welder":          { "display_name": "Welder",          "category": "tool", "weight": 3.0, "max_stack": 1 },
  "plasma_cutter":   { "display_name": "Plasma Cutter",   "category": "tool", "weight": 5.0, "max_stack": 1 }
```

(`power_cell` is already defined from #3; do not duplicate it.)

- [ ] **Step 4: Add these to `data/items/loot_tables.json` so they drop**

Extend the existing tables' `entries` arrays so repair parts appear. Replace the `salvage_engineering` and `salvage_cargo` tables with these (they keep their `rolls` and add repair parts), and add the two new tables `repair_parts_common` and `repair_tools`:

```json
  "salvage_engineering": {
    "rolls": 2,
    "entries": [
      { "item_id": "circuit_board",   "qty_min": 1, "qty_max": 2, "weight": 4 },
      { "item_id": "fuel_line",       "qty_min": 1, "qty_max": 2, "weight": 3 },
      { "item_id": "power_cell",      "qty_min": 1, "qty_max": 2, "weight": 3 },
      { "item_id": "thruster_nozzle", "qty_min": 1, "qty_max": 1, "weight": 1 }
    ]
  },
  "salvage_cargo": {
    "rolls": 3,
    "entries": [
      { "item_id": "scrap_metal",   "qty_min": 1, "qty_max": 4, "weight": 5 },
      { "item_id": "sealant",       "qty_min": 1, "qty_max": 3, "weight": 4 },
      { "item_id": "plating",       "qty_min": 1, "qty_max": 2, "weight": 2 },
      { "item_id": "oxygen_filter", "qty_min": 1, "qty_max": 2, "weight": 2 }
    ]
  },
  "repair_parts_common": {
    "rolls": 2,
    "entries": [
      { "item_id": "circuit_board", "qty_min": 1, "qty_max": 2, "weight": 5 },
      { "item_id": "sensor_module", "qty_min": 1, "qty_max": 1, "weight": 3 },
      { "item_id": "data_core",     "qty_min": 1, "qty_max": 1, "weight": 3 }
    ]
  },
  "repair_tools": {
    "rolls": 1,
    "entries": [
      { "item_id": "welder",        "qty_min": 1, "qty_max": 1, "weight": 5 },
      { "item_id": "plasma_cutter", "qty_min": 1, "qty_max": 1, "weight": 2 }
    ]
  }
```

(Keep the existing `generic_crate` and `generic_locker` tables unchanged.)

- [ ] **Step 5: Run the test to verify it passes**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/item_inventory_smoke.gd`
Expected: `ITEM INVENTORY PASS add=true weight_cap=true round_trip=true legacy_compat=true repair_vocab=true`.

- [ ] **Step 6: Regression-check the loot determinism smoke (tables changed)**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/loot_table_smoke.gd`
Expected: `LOOT TABLE PASS deterministic=true varies_by_seed=true` (still green — the smoke rolls `generic_crate`, which is unchanged; new tables are additive).

- [ ] **Step 7: Commit**

```bash
git add data/items/item_definitions.json data/items/loot_tables.json scripts/validation/item_inventory_smoke.gd
git commit -m "feat(repair): add repair parts + tools to loot vocabulary

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: `ShipSystemsManager.repair_with_inventory` (gated repair + consume)

**Files:**
- Modify: `scripts/systems/ship_systems_manager.gd`
- Create (test): `scripts/validation/repair_consume_smoke.gd`

**Interfaces:**
- Consumes: `InventoryState` (`get_items_by_category("part")`, `get_quantity`, `has_tool`, `remove_item`) from #3; the existing `repair(system_id, subcomponent_id, available_parts, available_tools, skill_level) -> Dictionary`.
- Produces:
  - `repair_with_inventory(system_id: String, subcomponent_id: String, inventory_state, skill_level: int) -> Dictionary` — gathers the player's part ids (category `part`, qty>0) and tool ids (category `tool`, qty>0) from `inventory_state`, calls `repair(...)`, and on `success` removes ONE of each `required_part` of that subcomponent from `inventory_state` (`remove_item(part, 1)`). Returns the underlying `repair` result dict (`{success, reason, seconds}`); on failure consumes nothing. Returns `{"success": false, "reason": "unknown_system"/"unknown_subcomponent", "seconds": 0.0}` for bad ids.

- [ ] **Step 1: Write the failing test** `scripts/validation/repair_consume_smoke.gd`

```gdscript
extends SceneTree

## Pure-model smoke: gated repair consumes the right parts, respects a dependency
## cascade, and rejects on missing parts/tools/skill. No scene tree.

const ShipSystemsManagerScript := preload("res://scripts/systems/ship_systems_manager.gd")
const InventoryStateScript := preload("res://scripts/systems/inventory_state.gd")

func _initialize() -> void:
	var repaired: bool = _test_repair_and_consume()
	var cascade: bool = _test_cascade()
	var rejects: bool = _test_rejects()
	if repaired and cascade and rejects:
		print("REPAIR CONSUME PASS repaired=true consumed=true cascade=true rejects=true")
	else:
		push_error("REPAIR CONSUME FAIL repaired=%s cascade=%s rejects=%s" % [
			str(repaired), str(cascade), str(rejects)])
	quit(0 if (repaired and cascade and rejects) else 1)

func _fresh_manager() -> Variant:
	var mgr = ShipSystemsManagerScript.new()
	# condition WRECKED (2), fixed seed → deterministic damage incl. broken subs.
	mgr.configure(mgr.load_definitions(), 2, 99)
	return mgr

func _test_repair_and_consume() -> bool:
	var mgr = _fresh_manager()
	# Force a clean scenario: break exactly battery_cells (power), everything else healthy,
	# so the repair target is deterministic and its deps are satisfied.
	for sid in ["power", "navigation", "propulsion", "life_support", "gravity", "scanners"]:
		var sys = mgr.get_system(sid)
		if sys != null:
			for sub in sys.subcomponents:
				sub.health = 1.0
	mgr.get_system("power").get_subcomponent("battery_cells").health = 0.1  # needs power_cell, skill 1, no tool
	var inv = InventoryStateScript.new()
	inv.add_item("power_cell", 2)
	var result: Dictionary = mgr.repair_with_inventory("power", "battery_cells", inv, 3)
	if not bool(result.get("success", false)):
		return false
	if not mgr.get_system("power").get_subcomponent("battery_cells").is_functional():
		return false
	# Exactly one power_cell consumed.
	if inv.get_quantity("power_cell") != 1:
		return false
	return true

func _test_cascade() -> bool:
	# propulsion depends on power+navigation. With those operational and propulsion's
	# subcomponents healthy except nav_linkage, repairing nav_linkage flips propulsion operational.
	var mgr = _fresh_manager()
	for sid in ["power", "navigation", "propulsion", "life_support", "gravity", "scanners"]:
		var sys = mgr.get_system(sid)
		if sys != null:
			for sub in sys.subcomponents:
				sub.health = 1.0
	mgr.get_system("propulsion").get_subcomponent("nav_linkage").health = 0.1  # circuit_board, skill 2, no tool
	if mgr.is_operational("propulsion"):
		return false  # broken before repair
	var inv = InventoryStateScript.new()
	inv.add_item("circuit_board", 1)
	var result: Dictionary = mgr.repair_with_inventory("propulsion", "nav_linkage", inv, 2)
	if not bool(result.get("success", false)):
		return false
	return mgr.is_operational("propulsion")  # operational after, via cascade resolve

func _test_rejects() -> bool:
	var mgr = _fresh_manager()
	for sid in ["power", "navigation", "propulsion", "life_support", "gravity", "scanners"]:
		var sys = mgr.get_system(sid)
		if sys != null:
			for sub in sys.subcomponents:
				sub.health = 1.0
	# thruster_array: needs thruster_nozzle + plasma_cutter + skill 4.
	mgr.get_system("propulsion").get_subcomponent("thruster_array").health = 0.1
	var empty = InventoryStateScript.new()
	# Missing parts:
	if bool(mgr.repair_with_inventory("propulsion", "thruster_array", empty, 5).get("success", true)):
		return false
	# Has part but missing tool:
	var inv = InventoryStateScript.new()
	inv.add_item("thruster_nozzle", 1)
	if bool(mgr.repair_with_inventory("propulsion", "thruster_array", inv, 5).get("success", true)):
		return false
	# Has part + tool but insufficient skill (min_skill 4, skill 1):
	inv.add_item("plasma_cutter", 1)
	if bool(mgr.repair_with_inventory("propulsion", "thruster_array", inv, 1).get("success", true)):
		return false
	# Nothing consumed on failure:
	if inv.get_quantity("thruster_nozzle") != 1:
		return false
	# Unknown ids:
	if str(mgr.repair_with_inventory("nope", "nope", inv, 9).get("reason", "")) != "unknown_system":
		return false
	return true
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/repair_consume_smoke.gd`
Expected: FAIL — `repair_with_inventory` does not exist.

- [ ] **Step 3: Implement `repair_with_inventory` in `ship_systems_manager.gd`**

Add this method (after the existing `repair(...)` method):

```gdscript
## Gated repair fed by a player InventoryState. Gathers the carried part/tool ids,
## runs the deterministic repair(), and on success consumes ONE of each required part.
## Consumes nothing on failure. Returns the repair() result dict.
func repair_with_inventory(system_id: String, subcomponent_id: String, inventory_state, skill_level: int) -> Dictionary:
	if not systems.has(system_id):
		return {"success": false, "reason": "unknown_system", "seconds": 0.0}
	var sub = systems[system_id].get_subcomponent(subcomponent_id)
	if sub == null:
		return {"success": false, "reason": "unknown_subcomponent", "seconds": 0.0}
	var available_parts: Array = []
	var available_tools: Array = []
	if inventory_state != null:
		for entry in inventory_state.get_items_by_category("part"):
			available_parts.append(String(entry["id"]))
		for entry in inventory_state.get_items_by_category("tool"):
			available_tools.append(String(entry["id"]))
	var result: Dictionary = sub.repair(available_parts, available_tools, skill_level)
	if bool(result.get("success", false)) and inventory_state != null:
		for part in sub.required_parts:
			inventory_state.remove_item(String(part), 1)
	return result
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/repair_consume_smoke.gd`
Expected: `REPAIR CONSUME PASS repaired=true consumed=true cascade=true rejects=true`.

- [ ] **Step 5: Regression-check the systems manager smoke**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ship_systems_manager_smoke.gd`
Expected: its existing PASS marker (the new method is additive; nothing else changed).

- [ ] **Step 6: Commit**

```bash
git add scripts/systems/ship_systems_manager.gd scripts/validation/repair_consume_smoke.gd
git commit -m "feat(repair): ShipSystemsManager.repair_with_inventory (gated repair + consume)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: Re-point the travel gate to the lifeboat (retire the placeholder)

**Files:**
- Modify: `scripts/procgen/playable_generated_ship.gd` (`_current_systems_ops`, ~lines 976-984)
- Create (test): `scripts/validation/lifeboat_travel_gate_smoke.gd`

**Interfaces:**
- Consumes: `ship_systems_manager` (the lifeboat's manager, coordinator-owned), `travel_to_marker_id`, `travel_home`, `get_ship_systems_manager`, `get_synaptic_sea_world`, `scanner_state`.
- Produces: `_current_systems_ops()` returns the starting ship's (lifeboat's) real operational status in BOTH home and away states; `travel_home()` remains always-available.

- [ ] **Step 1: Read the current `_current_systems_ops` and `travel_home`**

Open `scripts/procgen/playable_generated_ship.gd`. Confirm `_current_systems_ops()` (~line 976) currently returns `{"navigation": true, "scanners": true, "propulsion": true}` when `away_from_start`, and reflects `ship_systems_manager` when home. Confirm `travel_home()` (~line 1268) is not gated by propulsion (it returns to the starting ship). If `travel_home()` already gates on systems, note it — Step 4 must keep it always-available.

- [ ] **Step 2: Write the failing test** `scripts/validation/lifeboat_travel_gate_smoke.gd`

```gdscript
extends SceneTree

## Main-scene smoke: travel is gated by the LIFEBOAT's propulsion (home AND away);
## blocked while offline, succeeds after repair; travel_home always available.

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 300

var main_node: Node
var frame_count: int = 0
var finished: bool = false
var _exit_code: int = 0

func _initialize() -> void:
	main_node = MAIN_SCENE.instantiate()
	if main_node == null:
		_fail("could not instantiate main scene"); return
	get_root().add_child(main_node)
	process_frame.connect(_on_process_frame)

func _on_process_frame() -> void:
	if finished: return
	frame_count += 1
	var playable: PlayableGeneratedShip = _find_playable(main_node)
	if playable == null:
		if frame_count > TIMEOUT_FRAMES: _fail("no PlayableGeneratedShip")
		return
	if playable.loader == null or not playable.loader.has_loaded_ship():
		if frame_count > TIMEOUT_FRAMES: _fail("loader did not finish")
		return
	_validate(playable)

func _validate(playable: PlayableGeneratedShip) -> void:
	var mgr = playable.get_ship_systems_manager()
	# Make power + navigation operational so propulsion's deps are satisfied.
	for sid in ["power", "navigation"]:
		var sys = mgr.get_system(sid)
		if sys != null:
			for sub in sys.subcomponents:
				mgr.force_repair(sid, sub.subcomponent_id)
	# Break propulsion so it is offline.
	mgr.get_system("propulsion").get_subcomponent("nav_linkage").health = 0.1
	if mgr.is_operational("propulsion"):
		_fail("propulsion should be offline after breaking nav_linkage"); return

	# A marker must be in range to attempt travel.
	var world = playable.get_synaptic_sea_world()
	var in_range: Array = world.markers_in_range(playable.scanner_state.range_radius)
	if in_range.is_empty():
		_fail("no markers in range"); return
	var marker_id: String = String(in_range[0].marker_id)

	# Offline propulsion blocks travel_to.
	var blocked: Dictionary = playable.travel_to_marker_id(marker_id)
	if bool(blocked.get("success", false)):
		_fail("travel_to should be blocked while lifeboat propulsion offline"); return
	var blocked_offline: bool = String(blocked.get("reason", "")) == "propulsion_offline"

	# travel_home is always available even while offline.
	var home_always: bool = playable.travel_home()

	# Repair propulsion, then travel_to succeeds.
	mgr.force_repair("propulsion", "nav_linkage")
	if not mgr.is_operational("propulsion"):
		_fail("propulsion should be operational after repair"); return
	var after: Dictionary = playable.travel_to_marker_id(marker_id)
	var travels_after: bool = bool(after.get("success", false))

	if not (blocked_offline and home_always and travels_after):
		_fail("blocked_offline=%s home_always=%s travels_after=%s" % [
			str(blocked_offline), str(home_always), str(travels_after)]); return

	finished = true
	print("LIFEBOAT TRAVEL GATE PASS blocked_offline=true travels_after_repair=true home_always=true")
	_teardown_and_quit(0)

func _find_playable(node: Node) -> PlayableGeneratedShip:
	if node is PlayableGeneratedShip:
		return node as PlayableGeneratedShip
	for child in node.get_children():
		var found: PlayableGeneratedShip = _find_playable(child)
		if found != null: return found
	return null

func _fail(reason: String) -> void:
	if finished: return
	finished = true
	push_error("LIFEBOAT TRAVEL GATE FAIL reason=%s" % reason)
	_teardown_and_quit(1)

func _teardown_and_quit(code: int) -> void:
	_exit_code = code
	if main_node != null and is_instance_valid(main_node):
		main_node.free(); main_node = null
	call_deferred("_do_quit")

func _do_quit() -> void:
	quit(_exit_code)
```

> If `travel_home()` returns to home but the smoke is already home (not away), it should still return `true`. If the real `travel_home()` returns `false` when already home, adjust the smoke to first confirm `away_from_start` handling — but the spec requires `travel_home` to be a safe no-fail when home. If it currently returns `false` when already home, that is a pre-existing quirk; in that case assert `home_always` by confirming `travel_home()` does not throw and the player remains on the lifeboat, and note it in the report.

- [ ] **Step 3: Run the test to verify it fails**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/lifeboat_travel_gate_smoke.gd`
Expected: FAIL — currently propulsion-offline still allows travel only via the away-fake; when home the gate already reads real systems, but confirm the FAIL reason matches a real gap (e.g. the smoke breaks propulsion and expects a block). If it unexpectedly passes, the gate already behaves correctly when home; proceed to Step 4 for the away-branch change and re-verify.

- [ ] **Step 4: Re-point `_current_systems_ops()`**

Replace the body (the `away_from_start` early-return that fakes capability) so BOTH states read the lifeboat's manager. Replace lines ~976-984 with:

```gdscript
func _current_systems_ops() -> Dictionary:
	# Travel capability always comes from the player's functional ship — the lifeboat
	# (the coordinator-owned starting systems manager) — whether the player is on the
	# lifeboat or boarded on a docked derelict. The lifeboat is the guaranteed ride, so
	# a boarded derelict's broken systems never strand the player; an unrepaired lifeboat
	# simply cannot jump until its propulsion is restored. (Retires ADR-0011 placeholder.)
	var mgr = ship_systems_manager
	return {
		"navigation": mgr != null and mgr.is_operational("navigation"),
		"scanners": mgr != null and mgr.is_operational("scanners"),
		"propulsion": mgr != null and mgr.is_operational("propulsion"),
	}
```

Also update the doc-comment above the function to reflect the lifeboat model (remove the "report FULL capability" placeholder wording).

- [ ] **Step 5: Ensure `travel_home()` stays always-available**

Inspect `travel_home()` (~line 1268). It must return the player to the lifeboat regardless of systems state (no `propulsion`/ops gate). If it is already ungated, no change. If it gates on `_current_systems_ops()`/propulsion, remove that gate (home travel is the no-strand guarantee) and keep the rest. Do not change any other travel behavior.

- [ ] **Step 6: Run the test to verify it passes**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/lifeboat_travel_gate_smoke.gd`
Expected: `LIFEBOAT TRAVEL GATE PASS blocked_offline=true travels_after_repair=true home_always=true`.

- [ ] **Step 7: Regression-check every travel/derelict smoke (the away-branch changed)**

Run each ONE AT A TIME (shared save slot + MCP port 3572 — never concurrent):
```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/travel_integration_smoke.gd
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/world_persist_restore_smoke.gd
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/world_save_anywhere_smoke.gd
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/derelict_gameplay_smoke.gd
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/derelict_loot_smoke.gd
```
Expected: each prints its existing PASS marker. These smokes `force_repair`/make the home ship fully operational before travelling, so reading the lifeboat's (now-operational) systems when away keeps them green. If any FAILS with a travel block, that smoke travelled while the lifeboat's propulsion was not operational — fix the SMOKE to make the lifeboat propulsion operational before travelling (do NOT re-introduce the away-fake).

- [ ] **Step 8: Commit**

```bash
git add scripts/procgen/playable_generated_ship.gd scripts/validation/lifeboat_travel_gate_smoke.gd
git commit -m "feat(repair): travel capability reads the lifeboat in all states (no stranding)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: `RepairPoint` node + coordinator integration

**Files:**
- Create: `scripts/tools/repair_point.gd`
- Modify: `scripts/procgen/playable_generated_ship.gd`
- Modify: `data/procgen/golden/coherent_ship_001/gameplay_slice.json` (add guaranteed starting loot)

**Interfaces:**
- Consumes: `ShipSystemsManager.repair_with_inventory` (Task 2), `InventoryState` (#3), `LootContainer`/`_build_loot_containers` pattern (#3), `player_progression` (`get_skill_level`, `grant_xp`), the player seam (`teleport_to`, `request_interact`).
- Produces:
  - `RepairPoint` node: `configure(system_id, subcomponent_id, target_manager, inventory_state, player_progression, world_position, repair_seconds, min_skill, radius)`, `signal repair_completed(system_id, subcomponent_id)`, `try_start(player_body) -> bool` (precheck + begin channel), `advance_channel(delta) -> void`, `var channeling: bool`, `var progress: float` (0..1), `var repaired: bool`, `set_validation_player_in_range(player)`.
  - Coordinator: `var repair_point_root: Node3D`, `var repair_points: Array`, `repair_subcomponent_for_validation(system_id, subcomponent_id) -> bool` (start the channel through the real path), `advance_repair_channels_for_validation(delta)` (pump channels deterministically), `_apply_lifeboat_opening_damage()` (propulsion `nav_linkage` broken, others healthy).

- [ ] **Step 1: Create `scripts/tools/repair_point.gd`**

Mirror `LootContainer` (Area3D, sphere collision, marker, range check, validation seam) but with a timed channel that runs in the node's own `_process`. On completion it calls the manager's gated repair and consumes parts.

```gdscript
extends Area3D
class_name RepairPoint

## A spatial, parts-gated, timed repair node bound to one (system_id, subcomponent_id)
## of a specific ship's ShipSystemsManager. Interacting starts a Project-Zomboid-style
## channel that ticks in this node's OWN _process (independent of the coordinator's frozen
## per-frame loop). Leaving range cancels with no part loss; completing consumes the parts
## and restores the subcomponent.

signal repair_completed(system_id: String, subcomponent_id: String)
signal repair_blocked(system_id: String, subcomponent_id: String, reason: String)

var system_id: String = ""
var subcomponent_id: String = ""
var target_manager                       # ShipSystemsManager
var inventory_state                      # InventoryState
var player_progression                   # PlayerProgressionState | null
var interaction_radius: float = 1.8
var repair_seconds: float = 8.0
var min_skill: int = 0

var channeling: bool = false
var progress: float = 0.0                # 0..1
var repaired: bool = false
var _channel_player: Node = null
var _scaled_seconds: float = 1.0
var candidate_player: Node
var collision_shape: CollisionShape3D
var marker: MeshInstance3D
var marker_visible: bool = true

func _ready() -> void:
	monitoring = true
	monitorable = true
	collision_layer = 1
	collision_mask = 1
	set_process(true)
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)

func configure(p_system_id: String, p_subcomponent_id: String, p_target_manager, p_inventory_state, p_player_progression, world_position: Vector3, p_repair_seconds: float, p_min_skill: int, radius := 1.8) -> void:
	system_id = p_system_id
	subcomponent_id = p_subcomponent_id
	target_manager = p_target_manager
	inventory_state = p_inventory_state
	player_progression = p_player_progression
	repair_seconds = p_repair_seconds
	min_skill = p_min_skill
	interaction_radius = radius
	channeling = false
	progress = 0.0
	repaired = false
	candidate_player = null
	position = world_position
	name = "RepairPoint_%s_%s" % [p_system_id, p_subcomponent_id]
	set_meta("repair_point", true)
	_ensure_collision(radius)
	_ensure_marker(radius)

func set_validation_player_in_range(player_body: Node) -> void:
	candidate_player = player_body

func set_repaired(value: bool) -> void:
	repaired = value
	channeling = false
	progress = 1.0 if value else 0.0
	set_marker_visible(marker_visible)
	if collision_shape != null:
		collision_shape.disabled = repaired

func set_marker_visible(is_visible: bool) -> void:
	marker_visible = is_visible
	if marker != null:
		marker.visible = marker_visible and not repaired

func _player_skill() -> int:
	if player_progression != null and player_progression.has_method("get_skill_level"):
		return int(player_progression.get_skill_level("repair"))
	return 0

## Begins the channel if the player is in range and a dry-run of the gated repair
## would succeed (carries parts/tools, meets skill). Returns true if the channel started.
func try_start(player_body: Node) -> bool:
	if repaired or channeling or player_body == null or target_manager == null:
		return false
	# Mirrors Interactable's candidate bypass: a validation seam sets candidate_player.
	if candidate_player != player_body and not _is_player_in_direct_range(player_body):
		return false
	# Dry-run precheck WITHOUT consuming (repair() only mutates on success; we check parts/tools/skill).
	var sub = target_manager.get_system(system_id).get_subcomponent(subcomponent_id) if target_manager.get_system(system_id) != null else null
	if sub == null:
		return false
	if sub.is_functional():
		emit_signal("repair_blocked", system_id, subcomponent_id, "already_functional")
		return false
	var skill: int = _player_skill()
	var reason: String = _precheck_reason(sub, skill)
	if reason != "ok":
		emit_signal("repair_blocked", system_id, subcomponent_id, reason)
		return false
	_channel_player = player_body
	channeling = true
	progress = 0.0
	var factor: float = 1.0 + 0.1 * float(maxi(0, skill - min_skill))
	_scaled_seconds = maxf(0.01, repair_seconds / factor)
	return true

## Returns "ok" or a rejection reason, without mutating anything.
func _precheck_reason(sub, skill: int) -> String:
	var parts: Array = []
	var tools: Array = []
	if inventory_state != null:
		for entry in inventory_state.get_items_by_category("part"):
			parts.append(String(entry["id"]))
		for entry in inventory_state.get_items_by_category("tool"):
			tools.append(String(entry["id"]))
	for part in sub.required_parts:
		if not parts.has(String(part)):
			return "missing_parts"
	for tool in sub.required_tools:
		if not tools.has(String(tool)):
			return "missing_tools"
	if skill < min_skill:
		return "insufficient_skill"
	return "ok"

func _process(delta: float) -> void:
	if not channeling:
		return
	# Cancel if the player left range (unless a validation seam pinned candidate_player).
	if _channel_player != null and candidate_player != _channel_player and not _is_player_in_direct_range(_channel_player):
		_cancel()
		return
	advance_channel(delta)

## Pumps the channel by delta; completes the repair when progress reaches 1.0.
## Exposed so a validation smoke can drive the channel deterministically.
func advance_channel(delta: float) -> void:
	if not channeling:
		return
	progress = clampf(progress + delta / _scaled_seconds, 0.0, 1.0)
	if progress >= 1.0:
		_complete()

func _complete() -> void:
	channeling = false
	var skill: int = _player_skill()
	var result: Dictionary = target_manager.repair_with_inventory(system_id, subcomponent_id, inventory_state, skill)
	if bool(result.get("success", false)):
		set_repaired(true)
		if player_progression != null and player_progression.has_method("grant_xp"):
			player_progression.grant_xp("repair", 25)
		emit_signal("repair_completed", system_id, subcomponent_id)
	else:
		# Lost the parts/tools mid-channel (shouldn't normally happen); reset to idle.
		progress = 0.0
		emit_signal("repair_blocked", system_id, subcomponent_id, String(result.get("reason", "failed")))

func _cancel() -> void:
	channeling = false
	progress = 0.0
	_channel_player = null

func _interaction_radius() -> float:
	if collision_shape != null and collision_shape.shape is SphereShape3D:
		return (collision_shape.shape as SphereShape3D).radius
	return interaction_radius

func _is_player_in_direct_range(player_body: Node) -> bool:
	if not is_instance_valid(player_body) or not (player_body is Node3D):
		return false
	var player_node: Node3D = player_body as Node3D
	var here: Vector3 = global_position if is_inside_tree() else position
	var there: Vector3 = player_node.global_position if player_node.is_inside_tree() else player_node.position
	return here.distance_to(there) <= _interaction_radius()

func _ensure_collision(radius: float) -> void:
	if collision_shape == null:
		collision_shape = CollisionShape3D.new()
		collision_shape.name = "RepairPointCollisionShape3D"
		add_child(collision_shape)
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	collision_shape.shape = sphere
	collision_shape.disabled = repaired

func _ensure_marker(radius: float) -> void:
	if marker == null:
		marker = MeshInstance3D.new()
		marker.name = "RepairPointMarker"
		add_child(marker)
	var box := BoxMesh.new()
	box.size = Vector3(radius * 0.5, radius * 0.5, radius * 0.5)
	marker.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.45, 0.15, 0.7)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	marker.material_override = mat
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.visible = marker_visible and not repaired
	marker.set_meta("debug_repair_point_marker", true)

func _on_body_entered(body: Node3D) -> void:
	if body is PlayerController:
		candidate_player = body

func _on_body_exited(body: Node3D) -> void:
	if body == candidate_player:
		candidate_player = null
```

- [ ] **Step 2: Wire the coordinator — declarations + root + opening curation**

In `playable_generated_ship.gd`, near the `loot_container_root`/`loot_containers` declarations, add:

```gdscript
const RepairPointScript := preload("res://scripts/tools/repair_point.gd")
var repair_point_root: Node3D = null
var repair_points: Array = []
```

In `_build_runtime_nodes()`, right after `loot_container_root` is created, add:

```gdscript
	repair_point_root = Node3D.new()
	repair_point_root.name = "RepairPointRoot"
	add_child(repair_point_root)
```

Then, after `ship_systems_manager.configure(...)` in `_build_runtime_nodes()` (~line 861), curate the lifeboat opening so propulsion is offline via one low-skill blocker:

```gdscript
	_apply_lifeboat_opening_damage()
```

And add the method:

```gdscript
## Curates the lifeboat's propulsion so the opening blocker is a single low-skill repair:
## nav_linkage broken (circuit_board, skill 2, no tool), the other propulsion subs healthy.
## Propulsion is offline at boot (and stays so until repaired), making "repair the lifeboat to
## travel" the opening. Other systems keep their deterministic condition damage (the existing
## objective loop repairs power/navigation; nothing else depends on propulsion's start health).
func _apply_lifeboat_opening_damage() -> void:
	if ship_systems_manager == null:
		return
	var prop = ship_systems_manager.get_system("propulsion")
	if prop == null:
		return
	for sub in prop.subcomponents:
		sub.health = 1.0
	var blocker = prop.get_subcomponent("nav_linkage")
	if blocker != null:
		blocker.health = ShipSystemsManagerScript.DAMAGED_HEALTH
```

- [ ] **Step 3: Wire the coordinator — build/clear repair points**

Repair points are built from the LIVE systems manager (damaged subcomponents), placed at distributed room cells. Add a helper to resolve distributed positions from the active loader's rooms, then build/clear methods modeled on `_build_loot_containers`/`_clear_loot_containers`:

```gdscript
## Builds repair points for every currently-damaged subcomponent of the active ship,
## distributing them across the ship's rooms. Works for the lifeboat (home) and derelicts.
func _build_repair_points() -> void:
	_clear_repair_points()
	var mgr = _active_systems_manager()
	if mgr == null:
		return
	var positions: Array = _distributed_room_positions()
	if positions.is_empty():
		return
	var idx: int = 0
	for sid in mgr.system_order:
		var system = mgr.get_system(sid)
		if system == null:
			continue
		for sub in system.subcomponents:
			if sub.is_functional():
				continue
			var pos: Vector3 = positions[idx % positions.size()]
			idx += 1
			var rp = RepairPointScript.new()
			rp.configure(sid, sub.subcomponent_id, mgr, inventory_state, player_progression,
				pos, sub.repair_seconds, sub.min_skill, 1.8)
			if not rp.repair_completed.is_connected(_on_repair_completed):
				rp.repair_completed.connect(_on_repair_completed)
			repair_point_root.add_child(rp)
			repair_points.append(rp)

func _clear_repair_points() -> void:
	if is_instance_valid(repair_point_root):
		for child in repair_point_root.get_children():
			repair_point_root.remove_child(child)
			child.queue_free()
	repair_points.clear()

## The systems manager of the ship the player is currently aboard: the derelict's when away,
## the lifeboat's when home. (Repair points act on the ship under the player's feet; the
## travel gate separately reads the lifeboat — see _current_systems_ops.)
func _active_systems_manager():
	if away_from_start and current_ship != null and current_ship.systems_manager != null:
		return current_ship.systems_manager
	return ship_systems_manager

## Floor-cell world positions distributed across the active ship's rooms, for repair-point
## placement. Reuses the active loader's room/cell resolution where available.
func _distributed_room_positions() -> Array:
	var out: Array = []
	var active_loader = current_ship.scene_root if (away_from_start and current_ship != null) else loader
	if is_instance_valid(active_loader) and active_loader.has_method("get_objective_specs_copy"):
		for spec in active_loader.get_objective_specs_copy():
			if typeof(spec) == TYPE_DICTIONARY and typeof(spec.get("position", null)) == TYPE_VECTOR3:
				out.append(spec["position"])
	# Fallback: derive from loot container specs if no objective positions exist.
	if out.is_empty() and is_instance_valid(active_loader) and active_loader.has_method("get_loot_container_specs_copy"):
		for spec in active_loader.get_loot_container_specs_copy():
			if typeof(spec) == TYPE_DICTIONARY and typeof(spec.get("position", null)) == TYPE_VECTOR3:
				out.append(spec["position"])
	return out

func _on_repair_completed(system_id: String, subcomponent_id: String) -> void:
	_refresh_inventory_hud()
	print("REPAIR COMPLETED system=%s sub=%s operational=%s" % [
		system_id, subcomponent_id, str(_active_systems_manager().is_operational(system_id)).to_lower()])

## Validation seam: start a repair-point channel via the real path, by subcomponent.
func repair_subcomponent_for_validation(system_id: String, subcomponent_id: String) -> bool:
	for rp in repair_points:
		if is_instance_valid(rp) and rp.system_id == system_id and rp.subcomponent_id == subcomponent_id and not rp.repaired:
			rp.set_validation_player_in_range(player)
			return rp.try_start(player)
	return false

## Validation seam: pump all channeling repair points by delta (deterministic timed advance).
func advance_repair_channels_for_validation(delta: float) -> void:
	for rp in repair_points:
		if is_instance_valid(rp) and rp.channeling:
			rp.advance_channel(delta)
```

- [ ] **Step 4: Wire build/clear into the lifecycle + interact path + loot lift**

1. Build repair points whenever the active ship is (re)built. In `_build_runtime_nodes()`, after the initial loot/objective build for the home ship, add `_build_repair_points()`. In `_attach_derelict_active(...)`, after `_build_loot_containers()`, add `_build_repair_points()`.
   > Find the exact spot in `_build_runtime_nodes` where the home ship's loot/objectives are first built (after `_on_ship_loaded` resolves). If repair points must be built after the loader finishes, call `_build_repair_points()` from the same place `_build_loot_containers()` is first invoked for the home ship. Grep for `_build_loot_containers(` to find both call sites and add `_build_repair_points()` immediately after each.

2. Clear on leave/reload: wherever `_clear_loot_containers()` is called (`travel_home()` and `_reset_runtime_for_reload()`'s away-branch), add `_clear_repair_points()` immediately after.

3. Interact path: in `_on_player_interact_requested(...)`, in BOTH the away-branch and the home path, try repair points. Add this loop BEFORE the loot-container loop (repairs and loot don't overlap positions, but keep a deterministic order):
```gdscript
	for rp in repair_points:
		if is_instance_valid(rp) and rp.try_start(player_body):
			return
```
   Place it in the away-branch (next to the existing `loot_containers` loop the PR-feedback added) AND in the home interaction path (so the lifeboat's repair points are usable at home). If the home path currently has no pickup/loot loop, add this repair loop there before the objective/interactable handling.

4. Lift loot to the starting ship: in `_build_loot_containers()`, remove the `String(current_ship.marker_id) == ""` early-return so the home ship also builds loot containers. For the home ship, source specs from the home `loader` (not a derelict scene_root). Change the spec source line to:
```gdscript
	var active_loader = current_ship.scene_root if (away_from_start and current_ship != null) else loader
```
   and use a stable per-ship key for the seed source: keep `"%s:%s" % [String(current_ship.marker_id), cid]` (home `marker_id` is `""`, which is a stable, fixed seed source for the starting ship's guaranteed loot).
   > Verify the home `loader` exposes `get_loot_container_specs_copy()` (it does — same GeneratedShipLoader class). The guaranteed starting loot comes from the golden slice edited in Step 5.

- [ ] **Step 5: Add guaranteed starting loot to the golden slice**

Edit `data/procgen/golden/coherent_ship_001/gameplay_slice.json` to add a top-level `loot_containers` array guaranteeing the opening part (`circuit_board` for `nav_linkage`) plus a small starter kit. Pick two real room ids from that slice's `objectives`/rooms (open the file, copy two existing `room_id`s and their first floor `approach_cell` from the objectives). Add:

```json
  "loot_containers": [
    { "id": "start_supply_a", "kind": "generic_crate",  "room_id": "<ROOM_ID_1>", "approach_cell": [<CELL_1>], "loot_table": "repair_parts_common" },
    { "id": "start_supply_b", "kind": "generic_locker", "room_id": "<ROOM_ID_2>", "approach_cell": [<CELL_2>], "loot_table": "salvage_engineering" }
  ]
```

Both `repair_parts_common` and `salvage_engineering` contain `circuit_board` (the opening part). Because loot is deterministic per `"<marker_id>:<container_id>"` = `":start_supply_a"`, confirm the roll actually yields at least one `circuit_board`; if the deterministic roll of the chosen container does not include `circuit_board`, change the container's `loot_table` to `repair_parts_common` (high `circuit_board` weight, 2 rolls) and re-verify in Task 5's smoke. The opening must be guaranteed solvable.

- [ ] **Step 6: Parse-check the new node + coordinator compile**

Run a quick smoke that loads the main scene (this forces both files to parse):
```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/derelict_loot_smoke.gd
```
Expected: `DERELICT LOOT PASS ...` still green (proves the coordinator + RepairPoint parse and the loot/derelict path is intact with the new wiring). If it fails on a parse error in `repair_point.gd` or the coordinator, fix before proceeding. (Functional repair verification is Task 5.)

- [ ] **Step 7: Commit**

```bash
git add scripts/tools/repair_point.gd scripts/procgen/playable_generated_ship.gd data/procgen/golden/coherent_ship_001/gameplay_slice.json
git commit -m "feat(repair): RepairPoint timed node + coordinator wiring + lifeboat opening

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: Main-scene integration smoke (the opening, end to end)

**Files:**
- Create (test): `scripts/validation/repair_loop_smoke.gd`

**Interfaces:**
- Consumes: everything from Tasks 1-4 — `repair_subcomponent_for_validation`, `advance_repair_channels_for_validation`, `repair_points`, `search_loot_container_for_validation`/`loot_containers`, `_current_systems_ops` via `travel_to_marker_id`, `request_save`/`request_load`, `get_ship_systems_manager`.
- Produces: marker `REPAIR LOOP PASS opening=true channeled=true persists=true home_intact=true`.

- [ ] **Step 1: Write the failing test** `scripts/validation/repair_loop_smoke.gd`

```gdscript
extends SceneTree

## Main-scene integration: the opening loop. The lifeboat boots with propulsion offline
## (nav_linkage broken); loot the guaranteed starting parts; channel a timed repair of
## nav_linkage; propulsion comes online; a previously-blocked jump now succeeds; the repair
## survives a disk save/load; the home objective loop is intact.

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 300

var main_node: Node
var frame_count: int = 0
var finished: bool = false
var _exit_code: int = 0

func _initialize() -> void:
	main_node = MAIN_SCENE.instantiate()
	if main_node == null:
		_fail("could not instantiate main scene"); return
	get_root().add_child(main_node)
	process_frame.connect(_on_process_frame)

func _on_process_frame() -> void:
	if finished: return
	frame_count += 1
	var playable: PlayableGeneratedShip = _find_playable(main_node)
	if playable == null:
		if frame_count > TIMEOUT_FRAMES: _fail("no PlayableGeneratedShip")
		return
	if playable.loader == null or not playable.loader.has_loaded_ship():
		if frame_count > TIMEOUT_FRAMES: _fail("loader did not finish")
		return
	_validate(playable)

func _validate(playable: PlayableGeneratedShip) -> void:
	var mgr = playable.get_ship_systems_manager()
	# Opening: propulsion offline because nav_linkage was curated broken.
	if mgr.is_operational("propulsion"):
		_fail("lifeboat propulsion should be offline at boot"); return
	# Make power+navigation operational (the existing objective loop does this for the player).
	for sid in ["power", "navigation"]:
		for sub in mgr.get_system(sid).subcomponents:
			mgr.force_repair(sid, sub.subcomponent_id)
	var opening: bool = not mgr.is_operational("propulsion")  # still offline (nav_linkage broken)

	# A repair point for nav_linkage must exist on the lifeboat.
	var has_point: bool = false
	for rp in playable.repair_points:
		if rp.system_id == "propulsion" and rp.subcomponent_id == "nav_linkage":
			has_point = true
	if not has_point:
		_fail("no repair point for propulsion/nav_linkage on the lifeboat"); return

	# Loot the guaranteed starting parts (circuit_board needed for nav_linkage).
	if playable.loot_containers.is_empty():
		_fail("no starting loot containers (loot not lifted to lifeboat)"); return
	for lc in playable.loot_containers:
		playable.search_loot_container_for_validation(String(lc.container_id))
	if playable.inventory_state.get_quantity("circuit_board") < 1:
		_fail("starting loot did not guarantee a circuit_board"); return

	# Start the timed channel and prove it is NOT instant.
	if not playable.repair_subcomponent_for_validation("propulsion", "nav_linkage"):
		_fail("could not start nav_linkage repair channel"); return
	playable.advance_repair_channels_for_validation(0.01)  # tiny tick
	var mid_not_done: bool = not mgr.get_system("propulsion").get_subcomponent("nav_linkage").is_functional()
	# Drive the channel to completion deterministically.
	playable.advance_repair_channels_for_validation(999.0)
	var channeled: bool = mid_not_done and mgr.get_system("propulsion").get_subcomponent("nav_linkage").is_functional()
	if not channeled:
		_fail("timed channel did not complete the repair (mid_not_done=%s)" % str(mid_not_done)); return
	# One circuit_board consumed.
	if playable.inventory_state.get_quantity("circuit_board") != 0:
		_fail("repair did not consume the circuit_board"); return
	# Propulsion now operational; a jump that was blocked now succeeds.
	if not mgr.is_operational("propulsion"):
		_fail("propulsion not operational after repair"); return
	var world = playable.get_synaptic_sea_world()
	var in_range: Array = world.markers_in_range(playable.scanner_state.range_radius)
	if in_range.is_empty():
		_fail("no markers in range"); return
	var marker_id: String = String(in_range[0].marker_id)
	if not bool(playable.travel_to_marker_id(marker_id).get("success", false)):
		_fail("travel still blocked after repairing propulsion"); return

	# Persistence: the repaired nav_linkage survives a disk save/load.
	if not playable.travel_home():
		_fail("travel_home failed"); return
	if not playable.request_save():
		_fail("save failed"); return
	if not playable.request_load():
		_fail("load failed"); return
	var mgr2 = playable.get_ship_systems_manager()
	var persists: bool = mgr2.get_system("propulsion").get_subcomponent("nav_linkage").is_functional()
	if not persists:
		_fail("repaired nav_linkage did not persist across save/load"); return

	# Home loop intact: still on the lifeboat, away_from_start false.
	var home_intact: bool = not playable.away_from_start

	if not (opening and channeled and persists and home_intact):
		_fail("opening=%s channeled=%s persists=%s home_intact=%s" % [
			str(opening), str(channeled), str(persists), str(home_intact)]); return

	finished = true
	print("REPAIR LOOP PASS opening=true channeled=true persists=true home_intact=true")
	_teardown_and_quit(0)

func _find_playable(node: Node) -> PlayableGeneratedShip:
	if node is PlayableGeneratedShip:
		return node as PlayableGeneratedShip
	for child in node.get_children():
		var found: PlayableGeneratedShip = _find_playable(child)
		if found != null: return found
	return null

func _fail(reason: String) -> void:
	if finished: return
	finished = true
	push_error("REPAIR LOOP FAIL reason=%s" % reason)
	_teardown_and_quit(1)

func _teardown_and_quit(code: int) -> void:
	_exit_code = code
	if main_node != null and is_instance_valid(main_node):
		main_node.free(); main_node = null
	call_deferred("_do_quit")

func _do_quit() -> void:
	quit(_exit_code)
```

- [ ] **Step 2: Run the test**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/repair_loop_smoke.gd`
Expected: `REPAIR LOOP PASS opening=true channeled=true persists=true home_intact=true`.
If it fails on `starting loot did not guarantee a circuit_board`, fix the golden slice container's `loot_table` (Task 4 Step 5) until the deterministic roll yields a `circuit_board`. If it fails on `no repair point for propulsion/nav_linkage`, confirm `_build_repair_points()` runs for the home ship and `_apply_lifeboat_opening_damage()` broke `nav_linkage`. If save/load names differ, align them with the real coordinator method names (grep `func request_save`/`func request_load`).

- [ ] **Step 3: Commit**

```bash
git add scripts/validation/repair_loop_smoke.gd
git commit -m "test(repair): main-scene integration smoke for the opening repair loop

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 6: Register smokes, ADR-0015, full regression + Gate-1

**Files:**
- Modify: `docs/game/06_validation_plan.md`
- Create: `docs/game/adr/0015-ship-repair-loop.md`

**Interfaces:**
- Consumes: the three new PASS markers (Tasks 2, 3, 5).
- Produces: regression bundle count 70 → 73; ADR-0015.

- [ ] **Step 1: Register the three new smokes in the bundle**

In `docs/game/06_validation_plan.md`, add the three smokes to the bundle script with their exact markers, following the existing entry format:
- `repair_consume_smoke.gd` → `REPAIR CONSUME PASS repaired=true consumed=true cascade=true rejects=true`
- `lifeboat_travel_gate_smoke.gd` → `LIFEBOAT TRAVEL GATE PASS blocked_offline=true travels_after_repair=true home_always=true`
- `repair_loop_smoke.gd` → `REPAIR LOOP PASS opening=true channeled=true persists=true home_intact=true`
Also update the extended marker for `item_inventory_smoke.gd` (now ends `... repair_vocab=true`) if the doc lists it.
Bump the bundle count 70 → 73: grep the doc for `commands=70` and update every occurrence (count the registered commands to confirm 73).

- [ ] **Step 2: Run the FULL regression bundle**

Run the bash block in `docs/game/06_validation_plan.md` with `GODOT`/`ROOT` set to the Windows values, to completion (sequential — never concurrent with any other smoke; do not launch a background Godot process during this task).
Expected final line: `SYNAPTIC_SEA REGRESSION PASS commands=73 clean_output=true`. If any smoke is missing its marker or emits an un-allowlisted ERROR/WARNING, fix it. Do NOT add broad allowlist patterns to hide output.

- [ ] **Step 3: Run the Gate-1 automated playtest**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/gate1_automated_playtest.gd`
Expected: `GATE 1 AUTOMATED PLAYTEST PASS`. The lifeboat opening curation (propulsion `nav_linkage` broken) must not break Gate-1 — propulsion is not part of the single-ship objective/extraction flow. If Gate-1 fails, diagnose: if it expected propulsion operational at start, make the playtest restore it explicitly (do not revert the opening curation).

- [ ] **Step 4: Write ADR-0015** `docs/game/adr/0015-ship-repair-loop.md`

```markdown
# ADR-0015: Ship repair loop (parts-gated timed repair; lifeboat travel gate)

Date: 2026-06-21
Status: Accepted
Related: ADR-0011 (ShipInstance & travel — retires its "derelicts always travel-capable"
placeholder), ADR-0012 (world persistence), ADR-0013 (derelict gameplay parity),
ADR-0014 (loot & player inventory), docs/game/00_vision.md (North Star),
docs/superpowers/specs/2026-06-21-ship-repair-loop-design.md

## Context

ADR-0014 let the player accumulate parts but nothing consumed them. The existing
`ShipSubcomponent.repair` model was gated on parts/tools/skill but only ever driven by
`force_repair` (no inventory). Travel from a boarded derelict faked full capability
(ADR-0011 placeholder). The North Star makes repair the spine: loot → repair → fly.

## Decision

`ShipSystemsManager.repair_with_inventory` runs the existing deterministic gated repair using
the player's `InventoryState` and consumes the required parts on success. A `RepairPoint`
Area3D node drives a Project-Zomboid-style timed channel in its OWN `_process` (independent of
the coordinator's frozen per-frame loop, so no `_process` freeze lift), cancels with no part
loss if the player leaves range, and calls the gated repair on completion. The coordinator
builds repair points from the live systems manager (one per damaged subcomponent, distributed
across rooms) for the lifeboat AND derelicts. `_current_systems_ops()` now reads the lifeboat's
real systems in all states — travel capability lives in the player's functional ship, so a
boarded derelict's broken systems never strand the player, and an unrepaired lifeboat cannot
jump until its propulsion is restored. The lifeboat boots with propulsion offline (one
low-skill blocker, `nav_linkage`); the starting area's guaranteed loot supplies the part.

## Consequences

- The opening loop is "loot the starting area → repair the lifeboat's propulsion → first jump."
- Loot is lifted to an any-ship system (the starting ship now has loot containers).
- The existing home objective→`force_repair` bridge is untouched; repair points are an additional
  parts-gated path. Gate-1 and the completion loop stay green.
- Repaired state persists for free (existing `ship_systems_summary` / per-ship slice).
- `travel_home()` is always available — the no-strand guarantee.

## Non-goals (deferred)

- Multi-ship docking entity, cannibalizing, owning two ships — Phase-5 docking follow-on.
- Crafting (generic salvage is inert feedstock); a repair-skill progression curve; timed-channel
  persistence (a repair in progress is transient).

## Note: transitional

Per the North Star, the lifeboat/derelict split is transitional toward a uniform `ShipInstance`.
Repair is built as an any-ship system precisely so a fully repaired derelict can later become a
second functional vessel without re-architecture.
```

- [ ] **Step 5: Commit**

```bash
git add docs/game/06_validation_plan.md docs/game/adr/0015-ship-repair-loop.md
git commit -m "docs(repair): register repair smokes (70->73) + ADR-0015

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Self-Review (completed by plan author)

**Spec coverage:**
- §1 travel gate → lifeboat → Task 3. ✓
- §2 repair mechanic (distributed, parts-gated, timed, any-ship, dependency-aware) → Task 2 (consume) + Task 4 (RepairPoint timed node + build-from-live-manager + interact path). ✓
- §3 parts/tools vocabulary + guaranteed starting loot → Task 1 (data) + Task 4 Step 5 (golden slice). ✓
- §4 opening (lifeboat propulsion offline) + lift loot-derelicts-only → Task 4 Steps 2/4. ✓
- §5 persistence (free) → asserted in Task 5 (save/load survives). ✓
- §6 scope/non-goals → Global Constraints + no docking/crafting/skill-curve code anywhere. ✓
- §7 three smokes + bundle 70→73 + gate-1 + ADR-0015 → Tasks 2/3/5 (smokes) + Task 6. ✓
- HUD progress → RepairPoint exposes `progress`; `_on_repair_completed`/`_refresh_inventory_hud` reuse existing HUD plumbing (Task 4). (Minimal: progress surfaced via the existing status path; no new menu UI, per spec.)

**Type consistency:** `repair_with_inventory(system_id, subcomponent_id, inventory_state, skill_level) -> Dictionary`; `RepairPoint.configure(system_id, subcomponent_id, target_manager, inventory_state, player_progression, world_position, repair_seconds, min_skill, radius)`, `try_start`, `advance_channel`, `repair_completed(system_id, subcomponent_id)`; coordinator `repair_points`, `repair_subcomponent_for_validation(system_id, subcomponent_id)`, `advance_repair_channels_for_validation(delta)`, `_apply_lifeboat_opening_damage`, `_build_repair_points`/`_clear_repair_points` — used identically across Tasks 2-6. ✓

**Placeholder scan:** no TBD/TODO; full code in every code step. Three steps intentionally instruct grep-and-adapt against the live ~3000-line coordinator (Task 3 `travel_home` gating check; Task 4 Step 4 `_build_loot_containers` call-site location; Task 5 save/load method names) — each gives the concrete fallback, because the exact call sites must be verified against the real file rather than guessed. The golden-slice room ids in Task 4 Step 5 are placeholders the implementer fills from the actual slice file (the step says so and Task 5 verifies the guaranteed `circuit_board`). ✓
