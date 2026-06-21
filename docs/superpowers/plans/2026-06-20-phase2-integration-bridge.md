# Phase 2 Integration Bridge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `ShipSystemsManager` the live source of truth for ship-systems state in the playable coordinator and delete `ShipSystemState`, with every consequence (route gates, breach seal, blocked-affordance clear, extraction, HUD) re-derived from the manager.

**Architecture:** The coordinator builds a `ShipSystemsManager` from a golden blueprint sidecar and advances it each frame. Objective completions call `manager.force_repair(...)` per a declarative map. A coordinator-side flag-compat adapter synthesizes the old flag-shaped summary from manager subcomponent state and feeds the unchanged `route_control_state` / breach `oxygen_state` models. Two pure-narrative flags (supplies recovered, logs downloaded) move to a small coordinator objective record. Save/load swaps the snapshot's `ship_systems_summary` content from the flag dict to the manager snapshot.

**Tech Stack:** Godot 4.6.2, typed GDScript, headless validation smokes (no unit-test framework — each "test" is a `SceneTree`/`--script` smoke that prints a `PASS` marker; the marker is the contract).

## Global Constraints

- Godot binary (headless, console build): `C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe`
- Project root: `C:/Users/dasbl/Documents/The Synaptic Sea`
- Smoke run pattern (Git Bash):
  ```bash
  GODOT="C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe"
  ROOT="C:/Users/dasbl/Documents/The Synaptic Sea"
  "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/<name>.gd
  ```
- **`--script` can exit 0 on parse/load errors** — never trust exit code alone; confirm the `PASS` marker is present and no parse error / unexpected `ERROR:`/`WARNING:` appears.
- Allowlisted teardown noise (ignore): `ERROR: Capture not registered: 'gdaimcp'.` and `WARNING: ObjectDB instances leaked at exit ...`.
- In a `SceneTree` smoke, `quit()` does NOT halt `_initialize()`/the frame loop — every failure path must `return` after `quit(1)`.
- `class_name` globals are unreliable under `--headless --script`; reference cross-file scripts via `preload(...)` const Script vars; avoid `class_name` return-type annotations on cross-file calls.
- Typed GDScript for new code. Conventional Commits (`feat:`, `fix:`, `refactor:`, `test:`, `docs:`).
- Branch: `phase2-integration-bridge`.
- Manager rules (from code, do not violate): `ShipSystem.is_operational()` via the manager requires **all** subcomponents functional (`health >= operational_threshold`, default 0.5) **and** all dependencies operational. `ShipSubcomponent.is_functional()` is `health >= operational_threshold`. `ShipSystem.health()` is the **minimum** subcomponent health.

---

## File Structure

- **Create** `data/procgen/golden/coherent_ship_001/blueprint.json` — blueprint sidecar (size/condition/seed) for the live golden ship.
- **Modify** `scripts/systems/ship_systems_manager.gd` — add `force_repair(system_id, subcomponent_id)`.
- **Modify** `scripts/procgen/playable_generated_ship.gd` — the integration hub: build manager from sidecar, advance it, objective→repair map, flag-compat adapter, narrative record, save/load swap, remove `ShipSystemState`.
- **Delete** `scripts/systems/ship_system_state.gd`.
- **Modify** `scripts/ui/objective_tracker.gd` — update a stale comment referencing `ShipSystemState.apply_objective()`.
- **Modify** `scripts/validation/save_load_service_smoke.gd` — build `ship_systems_summary` from a `ShipSystemsManager` instead of `ShipSystemState` (count stays 7).
- **Rewrite** `scripts/validation/main_playable_slice_ship_systems_smoke.gd` — assert manager-derived runtime consequences.
- **Create** `docs/game/adr/0009-retire-ship-system-state-for-manager.md` — ADR for the content swap + retirement.
- **Modify** `docs/game/06_validation_plan.md` — update the expected marker for the rewritten smoke; re-run the bundle.
- **Verified no change needed:** `scripts/validation/req012_autosave_sequence_smoke.gd` (asserts no ship-systems content — grep-confirmed).

---

## Task 1: Add `force_repair` to ShipSystemsManager

**Files:**
- Modify: `scripts/systems/ship_systems_manager.gd`
- Test: `scripts/validation/ship_systems_manager_force_repair_smoke.gd` (create)

**Interfaces:**
- Produces: `ShipSystemsManager.force_repair(system_id: String, subcomponent_id: String) -> bool` — sets the named subcomponent `health = 1.0`; returns `false` for unknown system or subcomponent, `true` on success.

- [ ] **Step 1: Write the failing smoke**

Create `scripts/validation/ship_systems_manager_force_repair_smoke.gd`:

```gdscript
extends SceneTree

const ManagerScript := preload("res://scripts/systems/ship_systems_manager.gd")

func _initialize() -> void:
	var mgr = ManagerScript.new()
	mgr.configure(mgr.load_definitions(), 2, 17)  # WRECKED, seed 17 -> guarantees breakage

	# Break a known subcomponent, then force_repair it.
	var sub = mgr.get_system("power").get_subcomponent("battery_cells")
	sub.health = 0.0
	if sub.is_functional():
		_fail("setup: battery_cells should be non-functional at health 0.0")
		return

	if not mgr.force_repair("power", "battery_cells"):
		_fail("force_repair(power, battery_cells) returned false")
		return
	if not mgr.get_system("power").get_subcomponent("battery_cells").is_functional():
		_fail("battery_cells not functional after force_repair")
		return
	if absf(mgr.get_system("power").get_subcomponent("battery_cells").health - 1.0) > 0.0001:
		_fail("battery_cells health != 1.0 after force_repair")
		return

	# Unknown ids must return false, not crash.
	if mgr.force_repair("nope", "battery_cells"):
		_fail("force_repair(unknown system) should return false")
		return
	if mgr.force_repair("power", "nope"):
		_fail("force_repair(unknown subcomponent) should return false")
		return

	print("SHIP SYSTEMS MANAGER FORCE REPAIR PASS health=1.0 unknown_rejected=true")
	quit(0)

func _fail(reason: String) -> void:
	push_error("SHIP SYSTEMS MANAGER FORCE REPAIR FAIL reason=%s" % reason)
	quit(1)
```

- [ ] **Step 2: Run it to verify it fails**

```bash
GODOT="C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe"
ROOT="C:/Users/dasbl/Documents/The Synaptic Sea"
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ship_systems_manager_force_repair_smoke.gd
```
Expected: FAIL — no `FORCE REPAIR PASS` marker; error like `Invalid call. Nonexistent function 'force_repair'`.

- [ ] **Step 3: Implement `force_repair`**

In `scripts/systems/ship_systems_manager.gd`, add after `repair(...)` (after line ~146):

```gdscript
## Deterministically brings a subcomponent to full health (operational).
## Used by the objective bridge, which has no parts/tools/skill inventory
## feeding the gated repair() path yet (that arrives with Phase 6 inventory).
## Returns false for an unknown system or subcomponent.
func force_repair(system_id: String, subcomponent_id: String) -> bool:
	if not systems.has(system_id):
		return false
	var sub = systems[system_id].get_subcomponent(subcomponent_id)
	if sub == null:
		return false
	sub.health = 1.0
	return true
```

- [ ] **Step 4: Run it to verify it passes**

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ship_systems_manager_force_repair_smoke.gd
```
Expected: PASS — line `SHIP SYSTEMS MANAGER FORCE REPAIR PASS health=1.0 unknown_rejected=true`, no error.

- [ ] **Step 5: Commit**

```bash
git add scripts/systems/ship_systems_manager.gd scripts/validation/ship_systems_manager_force_repair_smoke.gd
git commit -m "feat(systems): add ShipSystemsManager.force_repair for the objective bridge"
```

---

## Task 2: Blueprint sidecar + manager built in the coordinator (alongside ShipSystemState)

This task is purely **additive**: the manager is built and advanced, but `ShipSystemState` still drives every consequence. The codebase stays green; nothing switches yet.

**Files:**
- Create: `data/procgen/golden/coherent_ship_001/blueprint.json`
- Modify: `scripts/procgen/playable_generated_ship.gd`
- Test: `scripts/validation/playable_manager_built_smoke.gd` (create)

**Interfaces:**
- Produces (on `PlayableGeneratedShip`):
  - `var ship_systems_manager` (the configured manager; null before build)
  - `@export var blueprint_path: String`
  - `func get_ship_systems_manager()` — returns the manager (validation seam)

- [ ] **Step 1: Create the blueprint sidecar**

Create `data/procgen/golden/coherent_ship_001/blueprint.json` (shape matches `ShipBlueprint.to_dict()`; `condition` 1 = DAMAGED, `size` 2 = MEDIUM):

```json
{
  "size": 2,
  "condition": 1,
  "seed_value": 17,
  "room_count_range": { "min": 8, "max": 12 }
}
```

- [ ] **Step 2: Write the failing smoke**

Create `scripts/validation/playable_manager_built_smoke.gd`:

```gdscript
extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 300

var main_node: Node
var frame_count: int = 0
var finished: bool = false

func _initialize() -> void:
	main_node = MAIN_SCENE.instantiate()
	if main_node == null:
		_fail("could not instantiate main scene")
		return
	get_root().add_child(main_node)
	process_frame.connect(_on_process_frame)

func _on_process_frame() -> void:
	if finished:
		return
	frame_count += 1
	var playable: PlayableGeneratedShip = _find_playable(main_node)
	if playable == null:
		if frame_count > TIMEOUT_FRAMES:
			_fail("no PlayableGeneratedShip found")
		return
	if playable.loader == null or not playable.loader.has_loaded_ship():
		if frame_count > TIMEOUT_FRAMES:
			_fail("loader did not finish")
		return
	_validate(playable)

func _validate(playable: PlayableGeneratedShip) -> void:
	if not playable.has_method("get_ship_systems_manager"):
		_fail("get_ship_systems_manager missing")
		return
	var mgr = playable.get_ship_systems_manager()
	if mgr == null:
		_fail("ship_systems_manager null")
		return
	if mgr.system_order.size() != 6:
		_fail("expected 6 systems, got %d" % mgr.system_order.size())
		return
	if mgr.get_system("power") == null or mgr.get_system("life_support") == null:
		_fail("power/life_support missing from manager")
		return
	finished = true
	print("PLAYABLE MANAGER BUILT PASS systems=%d" % mgr.system_order.size())
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	quit(0)

func _find_playable(node: Node) -> PlayableGeneratedShip:
	if node is PlayableGeneratedShip:
		return node as PlayableGeneratedShip
	for child in node.get_children():
		var found: PlayableGeneratedShip = _find_playable(child)
		if found != null:
			return found
	return null

func _fail(reason: String) -> void:
	if finished:
		return
	finished = true
	push_error("PLAYABLE MANAGER BUILT FAIL reason=%s" % reason)
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	quit(1)
```

- [ ] **Step 3: Run it to verify it fails**

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/playable_manager_built_smoke.gd
```
Expected: FAIL — `get_ship_systems_manager missing` (method/field not added yet).

- [ ] **Step 4: Add the preload, fields, blueprint load, build, advance, and accessor**

In `scripts/procgen/playable_generated_ship.gd`:

(a) Add the preloads near the other `const ...Script :=` lines (after line 21):
```gdscript
const ShipSystemsManagerScript := preload("res://scripts/systems/ship_systems_manager.gd")
const ShipBlueprintScript := preload("res://scripts/procgen/ship_blueprint.gd")
```

(b) Add the export near the other `@export` paths (after line 64):
```gdscript
@export var blueprint_path: String = "res://data/procgen/golden/coherent_ship_001/blueprint.json"
```

(c) Add the field near `var ship_systems: ShipSystemState` (line 88):
```gdscript
var ship_systems_manager   # ShipSystemsManager (untyped: class_name globals unreliable under --headless --script)
```

(d) In `_build_runtime_nodes()` (after `ship_systems = ShipSystemStateScript.new()` at line 791), build the manager:
```gdscript
	ship_systems_manager = ShipSystemsManagerScript.new()
	var bp = _load_blueprint_for_systems()
	ship_systems_manager.configure(ship_systems_manager.load_definitions(), bp.condition, bp.seed_value)
```

(e) Add the loader helper and accessor (place near `_build_runtime_nodes`):
```gdscript
## Loads the blueprint sidecar that seeds the ShipSystemsManager's condition
## damage. Falls back to a DAMAGED/seed=17 default (never crashes the slice)
## when the sidecar is absent or malformed.
func _load_blueprint_for_systems():
	var fallback = ShipBlueprintScript.new(ShipBlueprintScript.Size.MEDIUM, ShipBlueprintScript.Condition.DAMAGED, 17)
	if blueprint_path.is_empty() or not FileAccess.file_exists(blueprint_path):
		push_warning("PlayableGeneratedShip: blueprint sidecar missing at %s; using DAMAGED/seed=17 default" % blueprint_path)
		return fallback
	var text: String = FileAccess.get_file_as_string(blueprint_path)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("PlayableGeneratedShip: blueprint sidecar malformed at %s; using default" % blueprint_path)
		return fallback
	return ShipBlueprintScript.from_dict(parsed as Dictionary)

## Validation seam: the live ShipSystemsManager (null before _build_runtime_nodes()).
func get_ship_systems_manager():
	return ship_systems_manager
```

(f) In `_process(delta)` (after the `oxygen_state == null` guard, around line 1248), advance the manager:
```gdscript
	if ship_systems_manager != null:
		ship_systems_manager.advance(delta)
```

(g) In `_reset_runtime_for_reload()` reset block (near the `ship_systems.reset()` at line 2465), rebuild the manager fresh:
```gdscript
	if ship_systems_manager != null:
		var bp_reset = _load_blueprint_for_systems()
		ship_systems_manager.configure(ship_systems_manager.load_definitions(), bp_reset.condition, bp_reset.seed_value)
```

- [ ] **Step 5: Run the new smoke to verify it passes**

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/playable_manager_built_smoke.gd
```
Expected: PASS — `PLAYABLE MANAGER BUILT PASS systems=6`.

- [ ] **Step 6: Verify nothing regressed (ShipSystemState still drives everything)**

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_ship_systems_smoke.gd
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/save_load_service_smoke.gd
```
Expected: both still print their existing PASS markers (`MAIN PLAYABLE SHIP SYSTEMS PASS ...`, `SAVE LOAD SERVICE PASS ... summaries=7`).

- [ ] **Step 7: Commit**

```bash
git add data/procgen/golden/coherent_ship_001/blueprint.json scripts/procgen/playable_generated_ship.gd scripts/validation/playable_manager_built_smoke.gd
git commit -m "feat(systems): build and advance ShipSystemsManager from golden blueprint sidecar"
```

---

## Task 3: Switch consequences to manager-derived (the behavior swap)

This is the core task. After it, the manager drives gates/breach/HUD/extraction; `ShipSystemState` still exists in the file but no longer influences consequences. The rewritten integration smoke goes RED→GREEN within this task.

**Files:**
- Modify: `scripts/procgen/playable_generated_ship.gd`
- Test (rewrite): `scripts/validation/main_playable_slice_ship_systems_smoke.gd`

**Interfaces:**
- Consumes: `ShipSystemsManager.force_repair`, `.get_system`, `.is_operational` (Task 1 + existing).
- Produces (on `PlayableGeneratedShip`):
  - `const OBJECTIVE_REPAIR_MAP: Dictionary`
  - `var completed_objective_types: Dictionary`
  - `func _manager_compat_summary() -> Dictionary` — flag-shaped dict derived from manager + narrative record.
  - `get_ship_systems_summary()` now returns `_manager_compat_summary()` + `blocked_affordance_visible_count`.

- [ ] **Step 1: Rewrite the integration smoke to the target contract (RED)**

Replace the entire contents of `scripts/validation/main_playable_slice_ship_systems_smoke.gd` with:

```gdscript
extends SceneTree

## Manager-driven runtime-consequence smoke. Proves the live coordinator
## derives gates/breach/extraction/HUD from ShipSystemsManager (not the
## retired ShipSystemState). Deterministic: the smoke damages the relevant
## power subcomponents at setup, then drives objectives and asserts the
## derived consequences (independent of the blueprint's seeded damage set).

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 300

var main_node: Node
var frame_count: int = 0
var finished: bool = false

func _initialize() -> void:
	main_node = MAIN_SCENE.instantiate()
	if main_node == null:
		_fail("could not instantiate main scene")
		return
	get_root().add_child(main_node)
	process_frame.connect(_on_process_frame)

func _on_process_frame() -> void:
	if finished:
		return
	frame_count += 1
	var playable: PlayableGeneratedShip = _find_playable(main_node)
	if playable == null:
		if frame_count > TIMEOUT_FRAMES:
			_fail("no PlayableGeneratedShip found")
		return
	if playable.loader == null or not playable.loader.has_loaded_ship():
		if frame_count > TIMEOUT_FRAMES:
			_fail("loader did not finish")
		return
	_validate(playable)

func _validate(playable: PlayableGeneratedShip) -> void:
	var mgr = playable.get_ship_systems_manager()
	if mgr == null:
		_fail("ship_systems_manager null")
		return

	# Deterministic setup: break the power subcomponents the objectives repair.
	mgr.get_system("power").get_subcomponent("power_distribution").health = 0.0
	mgr.get_system("power").get_subcomponent("battery_cells").health = 0.0
	mgr.get_system("power").get_subcomponent("reactor_core").health = 0.0

	var initial: Dictionary = playable.get_ship_systems_summary()
	if bool(initial.get("main_power_restored", true)):
		_fail("initial main_power_restored should be false after breaking power subs")
		return
	if bool(initial.get("extraction_unlocked", true)):
		_fail("initial extraction_unlocked should be false")
		return

	# Objective 1: recover_supplies (narrative flag, no system) -------------------
	if not playable.complete_objective_sequence_for_validation(1):
		_fail("complete obj1 returned false")
		return
	if not bool(playable.get_ship_systems_summary().get("emergency_supplies_recovered", false)):
		_fail("after obj1 emergency_supplies_recovered=false")
		return

	# Objective 2: restore_systems -> power_distribution + battery_cells repaired -
	if not playable.complete_objective_sequence_for_validation(2):
		_fail("complete obj2 returned false")
		return
	var s2: Dictionary = playable.get_ship_systems_summary()
	if not bool(s2.get("main_power_restored", false)):
		_fail("after obj2 main_power_restored=false")
		return
	if not bool(s2.get("blocked_routes_cleared", false)):
		_fail("after obj2 blocked_routes_cleared=false")
		return
	if int(s2.get("blocked_affordance_visible_count", -1)) != 0:
		_fail("after obj2 blocked_affordance_visible_count!=0")
		return
	# Breach must have sealed (oxygen model fed the compat summary).
	if not bool(playable.get_oxygen_summary().get("breach_sealed", false)):
		_fail("after obj2 breach_sealed=false")
		return
	# Route gates opened (route-control fed the compat summary).
	if int(playable.get_route_control_summary().get("opened_gate_count", 0)) < 1:
		_fail("after obj2 no route gates opened")
		return
	# Extraction must still be locked (reactor not yet stabilized).
	if bool(s2.get("extraction_unlocked", true)):
		_fail("after obj2 extraction_unlocked should still be false")
		return

	# Objective 3: download_logs (narrative flag) --------------------------------
	if not playable.complete_objective_sequence_for_validation(3):
		_fail("complete obj3 returned false")
		return
	if not bool(playable.get_ship_systems_summary().get("navigation_logs_downloaded", false)):
		_fail("after obj3 navigation_logs_downloaded=false")
		return

	# Objective 4: stabilize_reactor -> reactor_core full, extraction unlocks -----
	if not playable.complete_objective_sequence_for_validation(4):
		_fail("complete obj4 returned false")
		return
	var s4: Dictionary = playable.get_ship_systems_summary()
	if not bool(s4.get("reactor_stabilized", false)):
		_fail("after obj4 reactor_stabilized=false")
		return
	if not bool(s4.get("extraction_unlocked", false)):
		_fail("after obj4 extraction_unlocked=false")
		return
	if int(s4.get("power_percent", 0)) != 100:
		_fail("after obj4 power_percent=%d expected 100" % int(s4.get("power_percent", 0)))
		return
	if int(s4.get("reactor_stability_percent", 0)) != 100:
		_fail("after obj4 reactor_stability_percent=%d expected 100" % int(s4.get("reactor_stability_percent", 0)))
		return
	if not bool(playable.get_slice_completion_summary().get("run_complete", false)):
		_fail("after obj4 run_complete=false")
		return
	# Now the whole power system is operational (all subs functional).
	if not mgr.is_operational("power"):
		_fail("after obj4 is_operational(power)=false")
		return

	# HUD includes the systems section.
	if not playable.tracker.get_hud_text().contains("Systems:"):
		_fail("HUD missing 'Systems:' section")
		return

	finished = true
	print("MAIN PLAYABLE SHIP SYSTEMS PASS power=true breach_sealed=true gates_open=true logs=true reactor=true extraction=true power_pct=100")
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	quit(0)

func _find_playable(node: Node) -> PlayableGeneratedShip:
	if node is PlayableGeneratedShip:
		return node as PlayableGeneratedShip
	for child in node.get_children():
		var found: PlayableGeneratedShip = _find_playable(child)
		if found != null:
			return found
	return null

func _fail(reason: String) -> void:
	if finished:
		return
	finished = true
	push_error("MAIN PLAYABLE SHIP SYSTEMS FAIL reason=%s" % reason)
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	quit(1)
```

- [ ] **Step 2: Run it to verify it fails**

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_ship_systems_smoke.gd
```
Expected: FAIL — `main_power_restored` still flips via `ShipSystemState`, so `power_percent`/`is_operational(power)` assertions and the manager-derived expectations fail (the manager isn't yet wired into consequences).

- [ ] **Step 3: Add the repair map, narrative record, and compat adapter**

In `scripts/procgen/playable_generated_ship.gd`:

(a) Add the constant near the top-level consts (after line ~60):
```gdscript
# Objective bridge: which manager subcomponents each objective brings operational.
# restore_systems delivers main power (distribution + battery); stabilize_reactor
# brings the reactor core to full health (extraction). download_logs/recover_supplies
# are narrative beats with no system backing.
const OBJECTIVE_REPAIR_MAP: Dictionary = {
	"restore_systems": [["power", "power_distribution"], ["power", "battery_cells"]],
	"download_logs": [["navigation", "nav_computer"]],
	"stabilize_reactor": [["power", "reactor_core"]],
}
```

(b) Add the narrative record field near `var ship_systems_manager` (line ~88):
```gdscript
# Narrative objective flags with no manager backing (supplies/logs). Set on
# completion; persisted in the snapshot; read by _manager_compat_summary().
var completed_objective_types: Dictionary = {}
```

(c) Add the adapter + helpers (place near `get_ship_systems_summary`, line ~1187):
```gdscript
func _sub_health(system_id: String, sub_id: String) -> float:
	if ship_systems_manager == null:
		return 0.0
	var system = ship_systems_manager.get_system(system_id)
	if system == null:
		return 0.0
	var sub = system.get_subcomponent(sub_id)
	return sub.health if sub != null else 0.0

func _sub_functional(system_id: String, sub_id: String) -> bool:
	if ship_systems_manager == null:
		return false
	var system = ship_systems_manager.get_system(system_id)
	if system == null:
		return false
	var sub = system.get_subcomponent(sub_id)
	return sub != null and sub.is_functional()

## Flag-shaped summary derived from manager subcomponent state + the narrative
## record. Feeds the unchanged route_control_state / breach oxygen_state models
## and the HUD, replacing ShipSystemState.get_summary().
func _manager_compat_summary() -> Dictionary:
	var power_restored: bool = _sub_functional("power", "power_distribution") and _sub_functional("power", "battery_cells")
	var reactor_full: bool = _sub_health("power", "reactor_core") >= 1.0
	var power_health: float = 0.0
	if ship_systems_manager != null and ship_systems_manager.get_system("power") != null:
		power_health = ship_systems_manager.get_system("power").health()
	return {
		"emergency_supplies_recovered": completed_objective_types.has("recover_supplies"),
		"main_power_restored": power_restored,
		"navigation_logs_downloaded": completed_objective_types.has("download_logs"),
		"reactor_stabilized": reactor_full,
		"blocked_routes_cleared": power_restored,
		"extraction_unlocked": reactor_full,
		"power_percent": int(round(power_health * 100.0)),
		"reactor_stability_percent": int(round(_sub_health("power", "reactor_core") * 100.0)),
	}
```

- [ ] **Step 4: Route the objective-completion handler through the manager**

In `_on_interactable_completed()` replace the `ship_systems` block (lines 1051–1068) with a manager-driven block:

```gdscript
	if ship_systems_manager != null:
		completed_objective_types[objective_type] = true
		for pair in OBJECTIVE_REPAIR_MAP.get(objective_type, []):
			ship_systems_manager.force_repair(str(pair[0]), str(pair[1]))
		var compat: Dictionary = _manager_compat_summary()
		_apply_ship_systems_consequences(objective_type)
		_refresh_route_control_from_ship_systems()
		if oxygen_state != null:
			oxygen_state.apply_ship_systems_summary(compat)
			_refresh_oxygen_state(false, 0.0)
		var route_summary: Dictionary = get_route_control_summary()
		print("SHIP SYSTEM UPDATED sequence=%d type=%s power=%d reactor=%d extraction=%s route_opened=%d blockers=%d" % [
			sequence,
			objective_type,
			int(compat.get("power_percent", 0)),
			int(compat.get("reactor_stability_percent", 0)),
			str(bool(compat.get("extraction_unlocked", false))),
			int(route_summary.get("opened_gate_count", 0)),
			int(route_summary.get("active_blocker_count", 0)),
		])
```

- [ ] **Step 5: Point the remaining ShipSystemState readers at the compat summary**

Replace the three remaining `ship_systems.get_summary()` / status-line reads so consequences derive from the manager:

(i) In `_refresh_route_control_from_ship_systems()` (lines 1124–1130), change the guard and feed:
```gdscript
func _refresh_route_control_from_ship_systems() -> void:
	if route_control_state == null or ship_systems_manager == null:
		_refresh_tracker_system_status_lines()
		return
	route_control_state.apply_ship_systems_summary(_manager_compat_summary())
	_apply_route_gate_scene_state()
	_refresh_tracker_system_status_lines()
```

(ii) In `get_ship_systems_summary()` (lines 1187–1204), return the compat adapter:
```gdscript
func get_ship_systems_summary() -> Dictionary:
	var summary: Dictionary = {}
	if ship_systems_manager == null:
		summary["main_power_restored"] = false
		summary["extraction_unlocked"] = false
		summary["power_percent"] = 0
		summary["reactor_stability_percent"] = 0
		summary["blocked_affordance_visible_count"] = 0
		return summary
	summary = _manager_compat_summary()
	summary["blocked_affordance_visible_count"] = get_blocked_affordance_visible_count()
	return summary
```

(iii) In `_combined_system_status_lines()` (lines 1164–1182), replace the `ship_systems.get_status_lines()` block with manager-derived HUD lines:
```gdscript
	if ship_systems_manager != null:
		var compat: Dictionary = _manager_compat_summary()
		lines.append("Power: %d%%" % int(compat.get("power_percent", 0)))
		lines.append("Reactor: %d%%" % int(compat.get("reactor_stability_percent", 0)))
		lines.append("Supplies: %s" % ("OK" if bool(compat.get("emergency_supplies_recovered", false)) else "LOW"))
		lines.append("Main Power: %s" % ("ON" if bool(compat.get("main_power_restored", false)) else "OFF"))
		lines.append("Logs: %s" % ("DOWNLOADED" if bool(compat.get("navigation_logs_downloaded", false)) else "PENDING"))
		lines.append("Reactor: %s" % ("STABLE" if bool(compat.get("reactor_stabilized", false)) else "UNSTABLE"))
```

> Note: `ship_systems` (the old model) is still allocated in `_build_runtime_nodes` and reset on reload, but no longer drives any consequence. Task 5 deletes it. Leaving it for now keeps this task's diff focused on the behavior swap and the file parseable.

- [ ] **Step 6: Run the integration smoke to verify it passes**

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_ship_systems_smoke.gd
```
Expected: PASS — `MAIN PLAYABLE SHIP SYSTEMS PASS power=true breach_sealed=true gates_open=true ... power_pct=100`.

- [ ] **Step 7: Commit**

```bash
git add scripts/procgen/playable_generated_ship.gd scripts/validation/main_playable_slice_ship_systems_smoke.gd
git commit -m "feat(systems): derive route/breach/HUD consequences from ShipSystemsManager"
```

---

## Task 4: Save/load swap to the manager snapshot

**Files:**
- Modify: `scripts/procgen/playable_generated_ship.gd`
- Modify: `scripts/validation/save_load_service_smoke.gd`

**Interfaces:**
- Consumes: `ShipSystemsManager.get_summary()` / `.apply_summary()` (existing); `completed_objective_types` (Task 3).
- Produces: snapshot `ship_systems_summary` now carries the manager snapshot; load restores manager + narrative record.

- [ ] **Step 1: Update the save smoke to build `ship_systems_summary` from a manager (RED)**

In `scripts/validation/save_load_service_smoke.gd`, find where `var ship` (a `ShipSystemState`) is constructed (just above line 78) and the line `original.ship_systems_summary = ship.get_summary()`. Replace the construction with a manager and drive a non-default state:

```gdscript
	var ship = preload("res://scripts/systems/ship_systems_manager.gd").new()
	ship.configure(ship.load_definitions(), 1, 17)  # DAMAGED, seed 17
	ship.force_repair("power", "battery_cells")       # force a known non-default health
```

Leave `original.ship_systems_summary = ship.get_summary()` (line 78) unchanged — `ship` is now the manager. Add a shape assertion after the existing `get_summary_count() != 7` check (after line 118):

```gdscript
	if not loaded.ship_systems_summary.has("systems") or not loaded.ship_systems_summary.has("system_order"):
		_fail("ship_systems_summary missing manager keys after round-trip")
		return
```

- [ ] **Step 2: Run the save smoke to verify it fails**

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/save_load_service_smoke.gd
```
Expected: FAIL — until the coordinator save path writes the manager summary, OR (if `ShipSystemState` still referenced) a parse/shape error. (If it happens to pass here because the smoke builds its own summary, that is acceptable — the contract is exercised in Step 5's integration round-trip; proceed.)

- [ ] **Step 3: Swap the snapshot build to the manager**

In `_build_run_snapshot()` replace lines 2246–2247:
```gdscript
	if ship_systems_manager != null:
		snapshot.ship_systems_summary = ship_systems_manager.get_summary()
		snapshot.ship_systems_summary["completed_objective_types"] = completed_objective_types.keys()
```

- [ ] **Step 4: Swap the load-apply path to the manager**

In `_apply_run_snapshot()` replace the `ship_systems` apply block (lines 2345–2355) with:
```gdscript
	if ship_systems_manager != null and not snapshot.ship_systems_summary.is_empty():
		ship_systems_manager.apply_summary(snapshot.ship_systems_summary)
		completed_objective_types.clear()
		for t in snapshot.ship_systems_summary.get("completed_objective_types", []):
			completed_objective_types[str(t)] = true
		objective_completion_count = max(0, snapshot.current_objective_sequence - 1)
		_apply_ship_systems_consequences("")
		_refresh_route_control_from_ship_systems()
		if oxygen_state != null:
			oxygen_state.apply_ship_systems_summary(_manager_compat_summary())
```

Also, in `_reset_runtime_for_reload()`, clear the narrative record next to the manager reconfigure (Task 2 step 4g):
```gdscript
	completed_objective_types.clear()
```

- [ ] **Step 5: Run save + autosave + integration smokes**

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/save_load_service_smoke.gd
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/req012_autosave_sequence_smoke.gd
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_ship_systems_smoke.gd
```
Expected: all PASS. Save smoke: `SAVE LOAD SERVICE PASS ... summaries=7`. Autosave and integration smokes keep their markers.

- [ ] **Step 6: Commit**

```bash
git add scripts/procgen/playable_generated_ship.gd scripts/validation/save_load_service_smoke.gd
git commit -m "feat(systems): persist ShipSystemsManager snapshot in run save/load"
```

---

## Task 5: Delete `ShipSystemState`

**Files:**
- Delete: `scripts/systems/ship_system_state.gd`
- Modify: `scripts/procgen/playable_generated_ship.gd`
- Modify: `scripts/ui/objective_tracker.gd`

**Interfaces:**
- Removes: all `ShipSystemState` / `ship_systems` references from the coordinator.

- [ ] **Step 1: Remove coordinator references**

In `scripts/procgen/playable_generated_ship.gd`:
- Delete the preload `const ShipSystemStateScript := preload("res://scripts/systems/ship_system_state.gd")` (line 12).
- Delete the field `var ship_systems: ShipSystemState` (line 88).
- Delete `ship_systems = ShipSystemStateScript.new()` in `_build_runtime_nodes()` (line 791).
- Delete the `if ship_systems != null: ship_systems.reset()` block in `_reset_runtime_for_reload()` (lines 2465–2466).

- [ ] **Step 2: Update the stale tracker comment**

In `scripts/ui/objective_tracker.gd` lines 230–232, replace the comment text:
```gdscript
# "repair_junction" to show as "Repair junction" even though the ship-system
# `type` stays "restore_systems" (the objective bridge maps it to manager
# repairs + route-control integration).
```

- [ ] **Step 3: Confirm no dangling references**

```bash
GODOT="C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe"
ROOT="C:/Users/dasbl/Documents/The Synaptic Sea"
grep -rn "ship_system_state\|ShipSystemState\|\bship_systems\b\.apply_objective" "$ROOT/scripts" || echo "NO DANGLING REFERENCES"
```
Expected: `NO DANGLING REFERENCES` (the only remaining `ship_systems_manager` is the new field — the `\b` word boundary excludes it).

- [ ] **Step 4: Delete the file**

```bash
git rm scripts/systems/ship_system_state.gd
```

- [ ] **Step 5: Run the affected smokes**

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_ship_systems_smoke.gd
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/save_load_service_smoke.gd
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/playable_manager_built_smoke.gd
```
Expected: all PASS, no `Parse Error` / `Could not resolve class "ShipSystemState"`.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "refactor(systems): retire ShipSystemState; ShipSystemsManager is the source of truth"
```

---

## Task 6: ADR, validation-plan doc, and full regression

**Files:**
- Create: `docs/game/adr/0009-retire-ship-system-state-for-manager.md`
- Modify: `docs/game/06_validation_plan.md`

- [ ] **Step 1: Write the ADR**

Create `docs/game/adr/0009-retire-ship-system-state-for-manager.md`:

```markdown
# ADR-0009: Retire ShipSystemState; ShipSystemsManager is the live ship-systems model

Date: 2026-06-20
Status: Accepted
Supersedes parts of: ADR-0008 (ship-systems architecture)
Relates to: ADR-0007 (save/load scope)

## Context
Phase 2 introduced `ShipSystemsManager` (6 systems, subcomponents, dependency
cascade, repair). The vertical slice still drove ship-systems consequences from
`ShipSystemState`, a coarse objective-flag model. The master core-systems design
mandates the manager replaces the flag model.

## Decision
The coordinator (`playable_generated_ship.gd`) builds `ShipSystemsManager` from a
golden blueprint sidecar and derives all consequences from it via a flag-compat
adapter. `ShipSystemState` is deleted. Two pure-narrative flags (supplies
recovered, logs downloaded) move to a coordinator `completed_objective_types`
record. The RunSnapshot `ship_systems_summary` field now carries the manager
snapshot (a content change, not a new field — SUMMARY_FIELDS count stays 7),
which ADR-0007 gates; this ADR records that change.

## Consequences
- HUD Power/Reactor percentages are now real health-derived values, not the old
  hardcoded 18/72/22/100.
- `main_power_restored` derives from `power_distribution` + `battery_cells`
  functional; extraction/`reactor_stabilized` derives from `reactor_core` full.
- Breach-oxygen ownership and the loader are unchanged (later phases).
```

- [ ] **Step 2: Update the validation plan marker**

In `docs/game/06_validation_plan.md`, find the expected marker line for `main_playable_slice_ship_systems_smoke.gd` and replace the old `MAIN PLAYABLE SHIP SYSTEMS PASS supplies=true power=true logs=true reactor=true extraction=true blocked_visible=0 completed_systems=4` with the new marker:
```
MAIN PLAYABLE SHIP SYSTEMS PASS power=true breach_sealed=true gates_open=true logs=true reactor=true extraction=true power_pct=100
```
Add the two new smokes to the bundle (grep list + command count): `ship_systems_manager_force_repair_smoke.gd` (marker `SHIP SYSTEMS MANAGER FORCE REPAIR PASS health=1.0 unknown_rejected=true`) and `playable_manager_built_smoke.gd` (marker `PLAYABLE MANAGER BUILT PASS systems=6`). Increment the `commands=` count in the final `SARGASSO REGRESSION PASS` line accordingly (was 47; +2 new = 49 — confirm against the actual bundle when you run it).

- [ ] **Step 3: Run the full regression bundle**

Extract the bundle block from `docs/game/06_validation_plan.md` and run it with `GODOT`/`ROOT` set to the Windows values (the doc hardcodes macOS paths — override them, do not edit the doc's paths). Then:
```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/gate1_automated_playtest.gd
```
Expected: bundle ends `SARGASSO REGRESSION PASS commands=<n> clean_output=true`; Gate-1 playtest passes. Resolve any unexpected `ERROR:`/`WARNING:` before proceeding (only the allowlisted teardown/REQ-012 lines are permitted).

- [ ] **Step 4: Commit**

```bash
git add docs/game/adr/0009-retire-ship-system-state-for-manager.md docs/game/06_validation_plan.md
git commit -m "docs(systems): ADR-0009 + validation-plan update for manager bridge"
```

- [ ] **Step 5: Open the PR**

```bash
git push -u origin phase2-integration-bridge
gh pr create --base main --title "feat(systems): Phase 2 integration bridge — ShipSystemsManager into live runtime" \
  --body "Wires ShipSystemsManager into the live coordinator and retires ShipSystemState (Path B, bridge-scoped). Consequences derived via a flag-compat adapter; breach-oxygen and loader untouched. Full regression + Gate-1 playtest green."
```

---

## Self-Review

**Spec coverage:**
- Build manager from blueprint sidecar → Task 2 ✓
- Objective completions drive manager repairs (force_repair + map) → Tasks 1, 3 ✓
- Consequences derive from manager via flag-compat adapter (route/breach unchanged) → Task 3 ✓
- Subcomponent-level gating (distribution+battery / reactor_core full) → Task 3 (map + adapter) ✓
- Narrative flags in coordinator record → Tasks 3, 4 ✓
- HUD power/reactor derived from manager → Task 3 step 5(iii) ✓
- Manager life-support oxygen stays internal (not surfaced) → no HUD line added for it ✓
- Save/load swaps ship_systems_summary content (count stays 7) → Task 4 ✓
- Retire ShipSystemState → Task 5 ✓
- ADR + validation plan + regression → Task 6 ✓
- Out-of-scope (oxygen→LifeSupport, loader→RoomGraph, runtime generation) → not touched ✓

**Placeholder scan:** No TBD/TODO. `commands=<n>` in Task 6 is explicitly "confirm against the actual bundle when you run it" (the count is environment-derived, not inventable). All code steps show full code.

**Type consistency:** `force_repair(system_id, subcomponent_id) -> bool` defined Task 1, used Tasks 3–4. `_manager_compat_summary()` defined Task 3, used Tasks 3–4. `completed_objective_types` (Dictionary) defined Task 3, read/written Tasks 3–4, cleared Tasks 2g/4/5. `ship_systems_manager` field + `get_ship_systems_manager()` defined Task 2, used everywhere after. Compat dict keys (`main_power_restored`, `blocked_routes_cleared`, `extraction_unlocked`) match the exact keys `route_control_state.apply_ship_systems_summary` and `oxygen_state.apply_ship_systems_summary` read (verified in source).
