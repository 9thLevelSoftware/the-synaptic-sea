# Current-Run Save/Load Implementation Plan (REQ-012)

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement a current-run-only save/load service for the active ship slice, scoped by ADR-0007 and `docs/game/features/save_load.md`.

**Architecture:** Add a pure `RunSnapshot` data class and a `SaveLoadService` owned by `PlayableGeneratedShip`. Runtime models expose `apply_summary()` to restore from a summary dictionary. Save triggers on objective completion (auto) and via input action (manual). Load reconstructs the slice through the normal `_ready` path, applies summaries before the first tick, and teleports the player. The save slot is deleted on run completion.

**Tech Stack:** Godot 4.6.2 GDScript, `FileAccess` + `JSON`, `SceneTree` validation smokes, existing `res://scenes/main.tscn`, existing `PlayableGeneratedShip`, no external runtime dependencies.

## Global Constraints

- Project root: `/Users/christopherwilloughby/the-synaptic-sea-of-stars`.
- Godot binary: `/Users/christopherwilloughby/.local/bin/godot-4.6.2`.
- Workspace state checked on 2026-06-19: `GIT_INSIDE=false`.
- Do not create HTML, PNG, contact sheets, screenshot galleries, or proof documents for this milestone.
- Use TDD: write failing smokes, run them red, then implement runtime code.
- Save/load must change actual file state and restore actual runtime model state; stubbed file I/O alone is not enough.
- Current-run-only boundary is enforced by ADR-0007. `RunSnapshot` must not contain hub/meta fields.
- This card depends on the **review completion** of REQ-007, REQ-010, and REQ-011 (`t_c98c338d`, `t_d357d336`, `t_d2ebf6cf`) because save/load serializes their model state. Do not start implementation until those review cards are done.
- The dependent models (`InventoryState`, `FireState`, `ObjectiveProgressState`) may not exist when this plan is written. The plan defines their `apply_summary()` contract; if a model is missing, implement a minimal stub version only for the save/load round-trip to compile, and leave full model behavior to the REQ-007/010/011 implement cards.
- Preserve existing objective sequence and validation seams: `complete_objective_sequence_for_validation()`, `complete_all_objectives_for_validation()`, and existing smokes must keep working.
- Output from validation commands must be clean of unexpected lines beginning with `ERROR:` or `WARNING:`.
- Because this is not a git repository, every task uses the no-git ledger fallback at `/tmp/synaptic_sea_save_load_no_git_changes.log` instead of assuming `git commit` works.

---

## File Structure

Create:

- `scripts/systems/run_snapshot.gd`
  - Pure data class extending `RefCounted`.
  - Fields: `layout_path`, `kit_path`, `gameplay_slice_path`, `player_position` (`Array[float]` of size 3), `current_objective_sequence` (`int`), `ship_systems_summary` (`Dictionary`), `route_control_summary` (`Dictionary`), `oxygen_summary` (`Dictionary`), `inventory_summary` (`Dictionary`), `fire_summary` (`Dictionary`), `objective_progress_summary` (`Dictionary`), `slice_version` (`String`), `godot_version` (`String`), `saved_at` (`String`, ISO-8601 UTC).
  - Static factory `from_dict(data: Dictionary) -> RunSnapshot` that validates required keys and version compatibility, returning `null` on mismatch.
  - Method `to_dict() -> Dictionary`.
  - Method `get_summary_count() -> int` returns `6` for the smoke marker.

- `scripts/systems/save_load_service.gd`
  - `SaveLoadService extends RefCounted`.
  - Constant `SAVE_PATH := "user://saves/current_run.json"`.
  - Constant `CURRENT_SLICE_VERSION := "gate2-current-run-1"`.
  - Method `save_current_run(snapshot: RunSnapshot) -> bool` writes JSON to `SAVE_PATH`.
  - Method `load_current_run() -> RunSnapshot` reads JSON, validates version, returns snapshot or `null`.
  - Method `delete_current_run() -> bool` removes `SAVE_PATH`.
  - Method `has_save() -> bool`.
  - All file operations use `FileAccess` and `JSON.stringify` / `JSON.parse_string`.
  - Logs clear warnings on parse failure, version mismatch, or missing file.

- `scripts/validation/save_load_service_smoke.gd`
  - Direct service smoke.
  - Creates a snapshot, saves, loads, asserts round-trip and version match.
  - Prints `SAVE LOAD SERVICE PASS round_trip=true version_match=true summaries=6`.

- `scripts/validation/main_playable_slice_save_load_smoke.gd`
  - Main-scene smoke.
  - Loads the slice, completes objective 1, saves, reloads, asserts player position, sequence, and `emergency_supplies_recovered`.
  - Prints `MAIN PLAYABLE SAVE LOAD PASS saved_sequence=2 loaded_sequence=2 position_match=true supplies=true`.

Modify:

- `scripts/procgen/playable_generated_ship.gd`
  - Preload and own `SaveLoadService` and `RunSnapshot`.
  - Add input actions `save_run` (default `F5`) and `load_run` (default `F9`) in `ensure_default_input_actions()`.
  - Add `save_load_service` member.
  - Add methods:
    - `request_save() -> bool` (manual save trigger).
    - `request_load() -> bool` (manual load trigger).
    - `_build_run_snapshot() -> RunSnapshot`.
    - `_apply_run_snapshot(snapshot: RunSnapshot) -> bool`.
    - `get_save_load_service() -> SaveLoadService` (validation seam).
  - In `_on_ship_loaded`, after `_activate_current_objective()`, call `_auto_save_current_run()`.
  - In `_on_interactable_completed`, after advancing `current_objective_sequence` (but before returning on slice completion), call `_auto_save_current_run()`.
  - On `playable_slice_completed`, call `save_load_service.delete_current_run()`.
  - Implement `_input(event)` to handle `save_run` and `load_run` actions when the slice is active.
  - Expose validation helpers:
    - `get_last_saved_snapshot() -> RunSnapshot` (returns the snapshot from the last successful save).
    - `is_load_available() -> bool`.

- `scripts/systems/ship_system_state.gd`
  - Add `apply_summary(summary: Dictionary) -> bool` that restores all flags, percentages, and `completed_sequences` from a dictionary matching `get_summary()` shape.
  - Return `true` if any field changed.

- `scripts/systems/route_control_state.gd`
  - Add `apply_summary(summary: Dictionary) -> bool` that restores `gate_records` and `extraction_unlocked`.
  - Return `true` if any field changed.

- `scripts/systems/oxygen_state.gd`
  - Add `apply_summary(summary: Dictionary) -> bool` that restores all tunables and runtime state from a dictionary matching `get_summary()` shape.
  - Return `true` if any field changed.

Create or stub (only if missing; full behavior belongs to REQ-007/010/011):

- `scripts/systems/inventory_state.gd`
  - Minimal `InventoryState extends RefCounted`.
  - `get_summary() -> Dictionary` and `apply_summary(summary: Dictionary) -> bool`.
  - If REQ-007 has already created this file, patch in `apply_summary()` instead.

- `scripts/systems/fire_state.gd`
  - Minimal `FireState extends RefCounted`.
  - `get_summary() -> Dictionary` and `apply_summary(summary: Dictionary) -> bool`.
  - If REQ-010 has already created this file, patch in `apply_summary()` instead.

- `scripts/systems/objective_progress_state.gd`
  - Minimal `ObjectiveProgressState extends RefCounted`.
  - `get_summary() -> Dictionary` and `apply_summary(summary: Dictionary) -> bool`.
  - If REQ-011 has already created this file, patch in `apply_summary()` instead.

No planned change:

- `scripts/ui/objective_tracker.gd`
  - Modify only if load path proves a real regression that cannot be solved in `PlayableGeneratedShip`.

Generated by Godot if import/class registration runs:

- `*.gd.uid` sidecars for new scripts.
  - Accept these sidecars if Godot creates them.
  - Record them in the no-git ledger.

---

## Model Summary Contract

All persisted runtime models must implement:

```gdscript
func get_summary() -> Dictionary
func apply_summary(summary: Dictionary) -> bool
```

`apply_summary()` must:

- Restore every key emitted by `get_summary()` that affects runtime behavior.
- Ignore unknown keys gracefully (forward compatibility).
- Return `true` if any field changed, `false` otherwise.
- Not emit signals or reach into the scene tree; `PlayableGeneratedShip` applies scene consequences after summaries are loaded.

The snapshot dictionary shape produced by `RunSnapshot.to_dict()` is:

```gdscript
{
  "layout_path": String,
  "kit_path": String,
  "gameplay_slice_path": String,
  "player_position": [float, float, float],
  "current_objective_sequence": int,
  "ship_systems_summary": Dictionary,
  "route_control_summary": Dictionary,
  "oxygen_summary": Dictionary,
  "inventory_summary": Dictionary,
  "fire_summary": Dictionary,
  "objective_progress_summary": Dictionary,
  "slice_version": "gate2-current-run-1",
  "godot_version": Engine.get_version_info()["string"],
  "saved_at": Time.get_datetime_string_from_system(true)
}
```

`RunSnapshot.from_dict()` rejects any save whose `slice_version` is not `"gate2-current-run-1"` or whose `godot_version` differs from the running engine version string.

---

### Task 1: SaveLoadService Model Smoke, RED Phase

**Files:**
- Create: `scripts/validation/save_load_service_smoke.gd`
- Read: `docs/game/features/save_load.md`

**Interfaces:**
- Consumes intended future classes:
  - `RunSnapshot`
  - `SaveLoadService`
- Produces a failing direct validation smoke with pass marker:
  - `SAVE LOAD SERVICE PASS round_trip=true version_match=true summaries=6`

- [ ] **Step 1: Create the failing save/load service smoke**

Write `scripts/validation/save_load_service_smoke.gd` with this complete content:

```gdscript
extends SceneTree

const RunSnapshotScript := preload("res://scripts/systems/run_snapshot.gd")
const SaveLoadServiceScript := preload("res://scripts/systems/save_load_service.gd")

func _initialize() -> void:
	var service := SaveLoadServiceScript.new()
	service.delete_current_run()

	var original := RunSnapshotScript.new()
	original.layout_path = "res://data/procgen/smoke/seed_000017/layout.json"
	original.kit_path = "res://data/kits/ship_structural_v0.json"
	original.gameplay_slice_path = "res://data/procgen/smoke/seed_000017/gameplay_slice.json"
	original.player_position = [1.0, 2.0, 3.0]
	original.current_objective_sequence = 2
	original.ship_systems_summary = {
		"emergency_supplies_recovered": true,
		"main_power_restored": false,
		"navigation_logs_downloaded": false,
		"reactor_stabilized": false,
		"blocked_routes_cleared": false,
		"extraction_unlocked": false,
		"power_percent": 18,
		"reactor_stability_percent": 22,
		"completed_sequences": [1],
		"completed_system_count": 1,
	}
	original.route_control_summary = {
		"route_gate_count": 1,
		"active_blocker_count": 1,
		"opened_gate_count": 0,
		"powered_gates_open": false,
		"extraction_unlocked": false,
		"gate_ids": ["gate_alpha"],
	}
	original.oxygen_summary = {
		"oxygen": 77.5,
		"max_oxygen": 100.0,
		"drain_rate": 6.0,
		"regen_rate": 3.5,
		"recovery_threshold": 30.0,
		"safe_threshold": 35.0,
		"breach_open": true,
		"breach_sealed": false,
		"passability_blocked": false,
		"player_in_breach_zone": false,
		"breach_zone_ids": ["corridor_to_reactor"],
	}
	original.inventory_summary = {"items": ["portable_oxygen_pump"]}
	original.fire_summary = {"active_zones": ["fire_side_corridor"], "sealed": false}
	original.objective_progress_summary = {"junction_steps": [true, false]}
	original.slice_version = service.CURRENT_SLICE_VERSION
	original.godot_version = Engine.get_version_info()["string"]
	original.saved_at = Time.get_datetime_string_from_system(true)

	if not service.save_current_run(original):
		_fail("save_current_run returned false")
		return
	if not service.has_save():
		_fail("has_save false after save")
		return

	var loaded: RunSnapshot = service.load_current_run()
	if loaded == null:
		_fail("load_current_run returned null")
		return

	if loaded.layout_path != original.layout_path:
		_fail("layout_path mismatch")
		return
	if loaded.kit_path != original.kit_path:
		_fail("kit_path mismatch")
		return
	if loaded.gameplay_slice_path != original.gameplay_slice_path:
		_fail("gameplay_slice_path mismatch")
		return
	if loaded.player_position != original.player_position:
		_fail("player_position mismatch")
		return
	if loaded.current_objective_sequence != original.current_objective_sequence:
		_fail("current_objective_sequence mismatch")
		return
	if loaded.get_summary_count() != 6:
		_fail("summary_count=%d expected 6" % loaded.get_summary_count())
		return
	if loaded.slice_version != original.slice_version:
		_fail("slice_version mismatch")
		return
	if loaded.godot_version != original.godot_version:
		_fail("godot_version mismatch")
		return
	if not _dicts_equal(loaded.ship_systems_summary, original.ship_systems_summary):
		_fail("ship_systems_summary mismatch")
		return
	if not _dicts_equal(loaded.route_control_summary, original.route_control_summary):
		_fail("route_control_summary mismatch")
		return
	if not _dicts_equal(loaded.oxygen_summary, original.oxygen_summary):
		_fail("oxygen_summary mismatch")
		return
	if not _dicts_equal(loaded.inventory_summary, original.inventory_summary):
		_fail("inventory_summary mismatch")
		return
	if not _dicts_equal(loaded.fire_summary, original.fire_summary):
		_fail("fire_summary mismatch")
		return
	if not _dicts_equal(loaded.objective_progress_summary, original.objective_progress_summary):
		_fail("objective_progress_summary mismatch")
		return

	# Version mismatch rejection
	var bad := RunSnapshotScript.new()
	bad.slice_version = "incompatible"
	bad.godot_version = Engine.get_version_info()["string"]
	bad.layout_path = original.layout_path
	bad.current_objective_sequence = 1
	if service.save_current_run(bad):
		var rejected: RunSnapshot = service.load_current_run()
		if rejected != null:
			_fail("incompatible version was accepted")
			return
	else:
		_fail("saving incompatible version failed unexpectedly")
		return

	# Cleanup
	service.delete_current_run()

	print("SAVE LOAD SERVICE PASS round_trip=true version_match=true summaries=6")
	quit(0)

func _dicts_equal(a: Dictionary, b: Dictionary) -> bool:
	return JSON.stringify(a) == JSON.stringify(b)

func _fail(reason: String) -> void:
	push_error("SAVE LOAD SERVICE FAIL reason=%s" % reason)
	quit(1)
```

- [ ] **Step 2: Run the smoke to verify it fails before implementation**

Run:

```bash
/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-synaptic-sea-of-stars --script res://scripts/validation/save_load_service_smoke.gd
```

Expected red result:

- The command exits non-zero.
- The failure is caused by missing `RunSnapshot` or `SaveLoadService`, such as `Identifier "RunSnapshot" not declared in the current scope` or `Cannot find member "save_current_run" in base "".`
- If the command fails for any other reason, stop and investigate.

- [ ] **Step 3: Record the red phase**

Run:

```bash
printf '%s\n' 'NO_GIT Task 1 RED save_load_service_smoke added and failed for missing service: scripts/validation/save_load_service_smoke.gd' >> /tmp/synaptic_sea_save_load_no_git_changes.log
```

---

### Task 2: RunSnapshot and SaveLoadService

**Files:**
- Create: `scripts/systems/run_snapshot.gd`
- Create: `scripts/systems/save_load_service.gd`
- Accept if generated: `scripts/systems/run_snapshot.gd.uid`, `scripts/systems/save_load_service.gd.uid`

**Interfaces:**
- `RunSnapshot` data class with fields and methods listed in File Structure.
- `SaveLoadService` with constants and methods listed in File Structure.

- [ ] **Step 1: Implement `RunSnapshot`**

Create `scripts/systems/run_snapshot.gd` with this complete content:

```gdscript
extends RefCounted
class_name RunSnapshot

var layout_path: String = ""
var kit_path: String = ""
var gameplay_slice_path: String = ""
var player_position: Array = [0.0, 0.0, 0.0]
var current_objective_sequence: int = 1
var ship_systems_summary: Dictionary = {}
var route_control_summary: Dictionary = {}
var oxygen_summary: Dictionary = {}
var inventory_summary: Dictionary = {}
var fire_summary: Dictionary = {}
var objective_progress_summary: Dictionary = {}
var slice_version: String = ""
var godot_version: String = ""
var saved_at: String = ""

const SUMMARY_FIELDS: Array = [
	"ship_systems_summary",
	"route_control_summary",
	"oxygen_summary",
	"inventory_summary",
	"fire_summary",
	"objective_progress_summary",
]

func get_summary_count() -> int:
	return SUMMARY_FIELDS.size()

func to_dict() -> Dictionary:
	return {
		"layout_path": layout_path,
		"kit_path": kit_path,
		"gameplay_slice_path": gameplay_slice_path,
		"player_position": player_position.duplicate(),
		"current_objective_sequence": current_objective_sequence,
		"ship_systems_summary": ship_systems_summary.duplicate(true),
		"route_control_summary": route_control_summary.duplicate(true),
		"oxygen_summary": oxygen_summary.duplicate(true),
		"inventory_summary": inventory_summary.duplicate(true),
		"fire_summary": fire_summary.duplicate(true),
		"objective_progress_summary": objective_progress_summary.duplicate(true),
		"slice_version": slice_version,
		"godot_version": godot_version,
		"saved_at": saved_at,
	}

static func from_dict(data: Dictionary, expected_slice_version: String, expected_godot_version: String) -> RunSnapshot:
	if data == null or data.is_empty():
		return null
	if str(data.get("slice_version", "")) != expected_slice_version:
		return null
	if str(data.get("godot_version", "")) != expected_godot_version:
		return null
	var snapshot := RunSnapshot.new()
	snapshot.layout_path = str(data.get("layout_path", ""))
	snapshot.kit_path = str(data.get("kit_path", ""))
	snapshot.gameplay_slice_path = str(data.get("gameplay_slice_path", ""))
	var pos = data.get("player_position", [0.0, 0.0, 0.0])
	if typeof(pos) == TYPE_ARRAY and pos.size() >= 3:
		snapshot.player_position = [float(pos[0]), float(pos[1]), float(pos[2])]
	snapshot.current_objective_sequence = int(data.get("current_objective_sequence", 1))
	snapshot.ship_systems_summary = _deep_copy_dict(data.get("ship_systems_summary", {}))
	snapshot.route_control_summary = _deep_copy_dict(data.get("route_control_summary", {}))
	snapshot.oxygen_summary = _deep_copy_dict(data.get("oxygen_summary", {}))
	snapshot.inventory_summary = _deep_copy_dict(data.get("inventory_summary", {}))
	snapshot.fire_summary = _deep_copy_dict(data.get("fire_summary", {}))
	snapshot.objective_progress_summary = _deep_copy_dict(data.get("objective_progress_summary", {}))
	snapshot.slice_version = str(data.get("slice_version", ""))
	snapshot.godot_version = str(data.get("godot_version", ""))
	snapshot.saved_at = str(data.get("saved_at", ""))
	return snapshot

static func _deep_copy_dict(src: Variant) -> Dictionary:
	if typeof(src) != TYPE_DICTIONARY:
		return {}
	return (src as Dictionary).duplicate(true)
```

- [ ] **Step 2: Implement `SaveLoadService`**

Create `scripts/systems/save_load_service.gd` with this complete content:

```gdscript
extends RefCounted
class_name SaveLoadService

const SAVE_PATH: String = "user://saves/current_run.json"
const CURRENT_SLICE_VERSION: String = "gate2-current-run-1"

func save_current_run(snapshot: RunSnapshot) -> bool:
	if snapshot == null:
		push_warning("SaveLoadService: cannot save null snapshot")
		return false
	var data: Dictionary = snapshot.to_dict()
	var json: String = JSON.stringify(data, "\t")
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("SaveLoadService: cannot open save file for writing, error=%d" % FileAccess.get_open_error())
		return false
	file.store_string(json)
	file.close()
	return true

func load_current_run() -> RunSnapshot:
	if not has_save():
		return null
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_warning("SaveLoadService: cannot open save file for reading, error=%d" % FileAccess.get_open_error())
		return null
	var json: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(json)
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		push_warning("SaveLoadService: save file is not valid JSON object")
		return null
	var expected_godot: String = Engine.get_version_info()["string"]
	var snapshot: RunSnapshot = RunSnapshot.from_dict(parsed as Dictionary, CURRENT_SLICE_VERSION, expected_godot)
	if snapshot == null:
		push_warning("SaveLoadService: save file version mismatch or missing required fields")
		return null
	return snapshot

func delete_current_run() -> bool:
	if not has_save():
		return true
	var err := DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	if err != OK:
		push_warning("SaveLoadService: failed to delete save file, error=%d" % err)
		return false
	return true

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)
```

- [ ] **Step 3: Re-run the model smoke**

Run:

```bash
/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-synaptic-sea-of-stars --script res://scripts/validation/save_load_service_smoke.gd
```

Expected green result:

- The command exits zero.
- Output contains `SAVE LOAD SERVICE PASS round_trip=true version_match=true summaries=6`.
- No unexpected `ERROR:` or `WARNING:` lines.

- [ ] **Step 4: Record the green phase**

Run:

```bash
printf '%s\n' 'NO_GIT Task 2 GREEN RunSnapshot and SaveLoadService implemented; save_load_service_smoke passes' >> /tmp/synaptic_sea_save_load_no_git_changes.log
```

---

### Task 3: Main-Scene Save/Load Smoke, RED Phase

**Files:**
- Create: `scripts/validation/main_playable_slice_save_load_smoke.gd`
- Read: `scripts/validation/main_playable_slice_ship_systems_smoke.gd`
- Read: `scripts/procgen/playable_generated_ship.gd`

**Interfaces:**
- Consumes intended future methods from `PlayableGeneratedShip`:
  - `get_save_load_service() -> SaveLoadService`
  - `get_last_saved_snapshot() -> RunSnapshot`
  - `request_save() -> bool`
  - `request_load() -> bool`
- Produces a failing main-scene validation smoke with pass marker:
  - `MAIN PLAYABLE SAVE LOAD PASS saved_sequence=2 loaded_sequence=2 position_match=true supplies=true`

- [ ] **Step 1: Create the failing main-scene save/load smoke**

Write `scripts/validation/main_playable_slice_save_load_smoke.gd` with this complete content:

```gdscript
extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 300
const POSITION_TOLERANCE: float = 0.01

var main_node: Node
var frame_count: int = 0
var finished: bool = false

func _initialize() -> void:
	var service := SaveLoadService.new()
	service.delete_current_run()
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
	if not playable.has_method("get_save_load_service"):
		_fail("get_save_load_service missing")
		return
	if not playable.has_method("get_last_saved_snapshot"):
		_fail("get_last_saved_snapshot missing")
		return
	if not playable.has_method("request_save"):
		_fail("request_save missing")
		return
	if not playable.has_method("request_load"):
		_fail("request_load missing")
		return

	var service: SaveLoadService = playable.get_save_load_service()
	if service == null:
		_fail("save_load_service null")
		return

	# Complete objective 1 and force a manual save.
	if not playable.complete_objective_sequence_for_validation(1):
		_fail("complete objective 1 failed")
		return
	if playable.get_current_objective_sequence() != 2:
		_fail("expected sequence 2 after objective 1")
		return
	var saved_pos: Vector3 = playable.player.global_position
	if not playable.request_save():
		_fail("request_save returned false")
		return
	var last_snapshot: RunSnapshot = playable.get_last_saved_snapshot()
	if last_snapshot == null:
		_fail("last saved snapshot null")
		return
	if last_snapshot.current_objective_sequence != 2:
		_fail("saved snapshot sequence=%d expected 2" % last_snapshot.current_objective_sequence)
		return

	# Load and assert restored state.
	if not playable.request_load():
		_fail("request_load returned false")
		return
	if playable.get_current_objective_sequence() != 2:
		_fail("loaded sequence=%d expected 2" % playable.get_current_objective_sequence())
		return
	var loaded_pos: Vector3 = playable.player.global_position
	if loaded_pos.distance_to(saved_pos) > POSITION_TOLERANCE:
		_fail("loaded position distance=%f > tolerance" % loaded_pos.distance_to(saved_pos))
		return
	var ship_summary: Dictionary = playable.get_ship_systems_summary()
	if not bool(ship_summary.get("emergency_supplies_recovered", false)):
		_fail("emergency_supplies_recovered not restored")
		return

	# Run completion must delete the save.
	if not playable.complete_all_objectives_for_validation():
		_fail("complete_all_objectives_for_validation failed")
		return
	if service.has_save():
		_fail("save file still exists after run completion")
		return

	finished = true
	print("MAIN PLAYABLE SAVE LOAD PASS saved_sequence=2 loaded_sequence=2 position_match=true supplies=true")
	_cleanup_and_quit(0)

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
	push_error("MAIN PLAYABLE SAVE LOAD FAIL reason=%s" % reason)
	_cleanup_and_quit(1)

func _cleanup_and_quit(code: int) -> void:
	var service := SaveLoadService.new()
	service.delete_current_run()
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	quit(code)
```

- [ ] **Step 2: Run the new smoke to verify it fails before implementation**

Run:

```bash
/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-synaptic-sea-of-stars --script res://scripts/validation/main_playable_slice_save_load_smoke.gd
```

Expected red result:

- The command exits non-zero.
- Failure is caused by missing `get_save_load_service`, `request_save`, `request_load`, or similar.

- [ ] **Step 3: Record the red phase**

Run:

```bash
printf '%s\n' 'NO_GIT Task 3 RED main_playable_slice_save_load_smoke added and failed for missing PlayableGeneratedShip hooks: scripts/validation/main_playable_slice_save_load_smoke.gd' >> /tmp/synaptic_sea_save_load_no_git_changes.log
```

---

### Task 4: apply_summary() on Existing Models

**Files:**
- Modify: `scripts/systems/ship_system_state.gd`
- Modify: `scripts/systems/route_control_state.gd`
- Modify: `scripts/systems/oxygen_state.gd`

**Interfaces:**
- Each model gains `apply_summary(summary: Dictionary) -> bool`.

- [ ] **Step 1: Add `apply_summary()` to `ShipSystemState`**

Patch `scripts/systems/ship_system_state.gd` by inserting after `get_status_lines()`:

```gdscript
func apply_summary(summary: Dictionary) -> bool:
	var changed: bool = false
	if bool(summary.get("emergency_supplies_recovered", false)) != emergency_supplies_recovered:
		emergency_supplies_recovered = bool(summary.get("emergency_supplies_recovered", false))
		changed = true
	if bool(summary.get("main_power_restored", false)) != main_power_restored:
		main_power_restored = bool(summary.get("main_power_restored", false))
		changed = true
	if bool(summary.get("navigation_logs_downloaded", false)) != navigation_logs_downloaded:
		navigation_logs_downloaded = bool(summary.get("navigation_logs_downloaded", false))
		changed = true
	if bool(summary.get("reactor_stabilized", false)) != reactor_stabilized:
		reactor_stabilized = bool(summary.get("reactor_stabilized", false))
		changed = true
	if bool(summary.get("blocked_routes_cleared", false)) != blocked_routes_cleared:
		blocked_routes_cleared = bool(summary.get("blocked_routes_cleared", false))
		changed = true
	if bool(summary.get("extraction_unlocked", false)) != extraction_unlocked:
		extraction_unlocked = bool(summary.get("extraction_unlocked", false))
		changed = true
	var new_power: int = int(summary.get("power_percent", INITIAL_POWER_PERCENT))
	if new_power != power_percent:
		power_percent = new_power
		changed = true
	var new_reactor: int = int(summary.get("reactor_stability_percent", INITIAL_REACTOR_STABILITY_PERCENT))
	if new_reactor != reactor_stability_percent:
		reactor_stability_percent = new_reactor
		changed = true
	var new_sequences: Array = summary.get("completed_sequences", []) as Array
	if new_sequences != completed_sequences:
		completed_sequences = new_sequences.duplicate()
		changed = true
	return changed
```

- [ ] **Step 2: Add `apply_summary()` to `RouteControlState`**

Patch `scripts/systems/route_control_state.gd` by inserting after `is_extraction_unlocked()`:

```gdscript
func apply_summary(summary: Dictionary) -> bool:
	var changed: bool = false
	var new_extraction: bool = bool(summary.get("extraction_unlocked", false))
	if new_extraction != extraction_unlocked:
		extraction_unlocked = new_extraction
		changed = true
	var incoming_ids: Array = summary.get("gate_ids", [])
	if incoming_ids.is_empty():
		return changed
	for gate_id_variant in incoming_ids:
		var gate_id: String = str(gate_id_variant)
		if not gate_records.has(gate_id):
			continue
		var record: Dictionary = gate_records[gate_id]
		var new_open: bool = bool(summary.get("gate_%s_open" % gate_id, false))
		# Also accept the legacy shape used by get_summary:
		if summary.has("gate_records"):
			var records: Dictionary = summary.get("gate_records", {})
			if records.has(gate_id):
				new_open = bool(records[gate_id].get("open", false))
		if bool(record.get("open", false)) != new_open:
			record["open"] = new_open
			gate_records[gate_id] = record
			changed = true
	return changed
```

- [ ] **Step 3: Add `apply_summary()` to `OxygenState`**

Patch `scripts/systems/oxygen_state.gd` by inserting after `get_status_lines()`:

```gdscript
func apply_summary(summary: Dictionary) -> bool:
	var changed: bool = false
	var new_oxygen: float = float(summary.get("oxygen", DEFAULT_MAX_OXYGEN))
	if abs(new_oxygen - oxygen) > 0.001:
		oxygen = clampf(new_oxygen, 0.0, max_oxygen)
		changed = true
	var new_max: float = float(summary.get("max_oxygen", DEFAULT_MAX_OXYGEN))
	if abs(new_max - max_oxygen) > 0.001:
		max_oxygen = maxf(0.0, new_max)
		changed = true
	var new_drain: float = float(summary.get("drain_rate", DEFAULT_DRAIN_RATE))
	if abs(new_drain - drain_rate) > 0.001:
		drain_rate = maxf(0.0, new_drain)
		changed = true
	var new_regen: float = float(summary.get("regen_rate", DEFAULT_REGEN_RATE))
	if abs(new_regen - regen_rate) > 0.001:
		regen_rate = maxf(0.0, new_regen)
		changed = true
	var new_recovery: float = float(summary.get("recovery_threshold", DEFAULT_RECOVERY_THRESHOLD))
	if abs(new_recovery - recovery_threshold) > 0.001:
		recovery_threshold = clampf(new_recovery, 0.0, max_oxygen)
		changed = true
	var new_safe: float = float(summary.get("safe_threshold", DEFAULT_SAFE_THRESHOLD))
	if abs(new_safe - safe_threshold) > 0.001:
		safe_threshold = clampf(new_safe, recovery_threshold, max_oxygen)
		changed = true
	var new_breach_open: bool = bool(summary.get("breach_open", true))
	if new_breach_open != breach_open:
		breach_open = new_breach_open
		changed = true
	var new_breach_sealed: bool = bool(summary.get("breach_sealed", false))
	if new_breach_sealed != breach_sealed:
		breach_sealed = new_breach_sealed
		changed = true
	var new_player_in: bool = bool(summary.get("player_in_breach_zone", false))
	if new_player_in != last_player_in_breach_zone:
		last_player_in_breach_zone = new_player_in
		changed = true
	var new_zone_ids: Array = summary.get("breach_zone_ids", []) as Array
	if new_zone_ids != breach_zone_ids:
		breach_zone_ids = new_zone_ids.duplicate()
		changed = true
	_recompute_passability_blocked()
	return changed
```

- [ ] **Step 4: Re-run the model smoke**

Run:

```bash
/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-synaptic-sea-of-stars --script res://scripts/validation/save_load_service_smoke.gd
```

Expected green result:

- Still passes with `SAVE LOAD SERVICE PASS round_trip=true version_match=true summaries=6`.

- [ ] **Step 5: Record the model-summary contract green phase**

Run:

```bash
printf '%s\n' 'NO_GIT Task 4 GREEN apply_summary() added to ShipSystemState, RouteControlState, OxygenState' >> /tmp/synaptic_sea_save_load_no_git_changes.log
```

---

### Task 5: Gate 2 Model Stubs and Contracts

**Files:**
- Create or modify: `scripts/systems/inventory_state.gd`
- Create or modify: `scripts/systems/fire_state.gd`
- Create or modify: `scripts/systems/objective_progress_state.gd`

**Block condition:** If REQ-007/010/011 implementation cards have not yet landed, create minimal stubs with `get_summary()` and `apply_summary()` so the save/load service compiles and its smoke passes. Do **not** implement full tool, fire, or objective-progression behavior; that belongs to the REQ-007/010/011 cards.

- [ ] **Step 1: Create or patch `InventoryState`**

If the file does not exist, create `scripts/systems/inventory_state.gd`:

```gdscript
extends RefCounted
class_name InventoryState

var items: Array = []

func get_summary() -> Dictionary:
	return {
		"items": items.duplicate(),
	}

func apply_summary(summary: Dictionary) -> bool:
	var new_items: Array = summary.get("items", []) as Array
	if new_items != items:
		items = new_items.duplicate()
		return true
	return false
```

If the file exists, add `apply_summary()` matching the existing `get_summary()` shape.

- [ ] **Step 2: Create or patch `FireState`**

If the file does not exist, create `scripts/systems/fire_state.gd`:

```gdscript
extends RefCounted
class_name FireState

var active_zones: Array = []
var sealed: bool = false

func get_summary() -> Dictionary:
	return {
		"active_zones": active_zones.duplicate(),
		"sealed": sealed,
	}

func apply_summary(summary: Dictionary) -> bool:
	var changed: bool = false
	var new_zones: Array = summary.get("active_zones", []) as Array
	if new_zones != active_zones:
		active_zones = new_zones.duplicate()
		changed = true
	var new_sealed: bool = bool(summary.get("sealed", false))
	if new_sealed != sealed:
		sealed = new_sealed
		changed = true
	return changed
```

- [ ] **Step 3: Create or patch `ObjectiveProgressState`**

If the file does not exist, create `scripts/systems/objective_progress_state.gd`:

```gdscript
extends RefCounted
class_name ObjectiveProgressState

var junction_steps: Array = []

func get_summary() -> Dictionary:
	return {
		"junction_steps": junction_steps.duplicate(),
	}

func apply_summary(summary: Dictionary) -> bool:
	var new_steps: Array = summary.get("junction_steps", []) as Array
	if new_steps != junction_steps:
		junction_steps = new_steps.duplicate()
		return true
	return false
```

- [ ] **Step 4: Re-run the model smoke**

Run:

```bash
/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-synaptic-sea-of-stars --script res://scripts/validation/save_load_service_smoke.gd
```

Expected green result.

- [ ] **Step 5: Record the stub/model contract phase**

Run:

```bash
printf '%s\n' 'NO_GIT Task 5 GREEN Gate 2 model stubs/contracts added for InventoryState, FireState, ObjectiveProgressState' >> /tmp/synaptic_sea_save_load_no_git_changes.log
```

---

### Task 6: PlayableGeneratedShip Save/Load Hooks

**Files:**
- Modify: `scripts/procgen/playable_generated_ship.gd`

**Interfaces:**
- New members:
  - `var save_load_service: SaveLoadService`
  - `var last_saved_snapshot: RunSnapshot`
  - `var inventory_state: InventoryState` (or stub)
  - `var fire_state: FireState` (or stub)
  - `var objective_progress_state: ObjectiveProgressState` (or stub)
- New methods:
  - `request_save() -> bool`
  - `request_load() -> bool`
  - `get_save_load_service() -> SaveLoadService`
  - `get_last_saved_snapshot() -> RunSnapshot`
  - `is_load_available() -> bool`
  - `_build_run_snapshot() -> RunSnapshot`
  - `_apply_run_snapshot(snapshot: RunSnapshot) -> bool`
  - `_auto_save_current_run() -> bool`

- [ ] **Step 1: Wire service and input actions**

At the top of `scripts/procgen/playable_generated_ship.gd`, add preloads:

```gdscript
const SaveLoadServiceScript := preload("res://scripts/systems/save_load_service.gd")
const RunSnapshotScript := preload("res://scripts/systems/run_snapshot.gd")
const InventoryStateScript := preload("res://scripts/systems/inventory_state.gd")
const FireStateScript := preload("res://scripts/systems/fire_state.gd")
const ObjectiveProgressStateScript := preload("res://scripts/systems/objective_progress_state.gd")
```

Add members after `oxygen_root`:

```gdscript
var save_load_service: SaveLoadService
var last_saved_snapshot: RunSnapshot
var inventory_state: InventoryState
var fire_state: FireState
var objective_progress_state: ObjectiveProgressState
```

In `ensure_default_input_actions()`, add:

```gdscript
_ensure_key_action("save_run", KEY_F5)
_ensure_key_action("load_run", KEY_F9)
```

In `_build_runtime_nodes()`, after `oxygen_state = OxygenStateScript.new()` add:

```gdscript
inventory_state = InventoryStateScript.new()
fire_state = FireStateScript.new()
objective_progress_state = ObjectiveProgressStateScript.new()
save_load_service = SaveLoadServiceScript.new()
```

- [ ] **Step 2: Implement snapshot builder**

Add to `PlayableGeneratedShip`:

```gdscript
func _build_run_snapshot() -> RunSnapshot:
	var snapshot := RunSnapshotScript.new()
	snapshot.layout_path = layout_path
	snapshot.kit_path = kit_path
	snapshot.gameplay_slice_path = gameplay_slice_path
	if player != null:
		var pos: Vector3 = player.global_position
		snapshot.player_position = [pos.x, pos.y, pos.z]
	else:
		snapshot.player_position = [0.0, 0.0, 0.0]
	snapshot.current_objective_sequence = current_objective_sequence
	snapshot.ship_systems_summary = ship_systems.get_summary() if ship_systems != null else {}
	snapshot.route_control_summary = get_route_control_summary()
	snapshot.oxygen_summary = get_oxygen_summary()
	snapshot.inventory_summary = inventory_state.get_summary() if inventory_state != null else {}
	snapshot.fire_summary = fire_state.get_summary() if fire_state != null else {}
	snapshot.objective_progress_summary = objective_progress_state.get_summary() if objective_progress_state != null else {}
	snapshot.slice_version = SaveLoadServiceScript.CURRENT_SLICE_VERSION
	snapshot.godot_version = Engine.get_version_info()["string"]
	snapshot.saved_at = Time.get_datetime_string_from_system(true)
	return snapshot

func _auto_save_current_run() -> bool:
	if save_load_service == null or slice_complete:
		return false
	var snapshot := _build_run_snapshot()
	if save_load_service.save_current_run(snapshot):
		last_saved_snapshot = snapshot
		return true
	return false
```

- [ ] **Step 3: Implement load path**

Add to `PlayableGeneratedShip`:

```gdscript
func request_load() -> bool:
	if save_load_service == null:
		return false
	var snapshot: RunSnapshot = save_load_service.load_current_run()
	if snapshot == null:
		push_warning("PlayableGeneratedShip: no compatible save to load")
		return false
	return _apply_run_snapshot(snapshot)

func _apply_run_snapshot(snapshot: RunSnapshot) -> bool:
	if snapshot == null:
		return false
	# Reconstruct the slice through the normal ready path.
	layout_path = snapshot.layout_path
	kit_path = snapshot.kit_path
	gameplay_slice_path = snapshot.gameplay_slice_path
	# Reset runtime state so _ready rebuilds cleanly.
	playable_started = false
	objective_completion_count = 0
	current_objective_sequence = 1
	slice_complete = false
	_ready()
	# Wait one frame for ship_loaded to fire, then apply summaries.
	await get_tree().process_frame
	if not playable_started:
		push_error("PlayableGeneratedShip: load failed because slice did not start")
		return false
	if ship_systems != null:
		ship_systems.apply_summary(snapshot.ship_systems_summary)
		_apply_ship_systems_consequences("")
	if route_control_state != null:
		route_control_state.apply_summary(snapshot.route_control_summary)
		_refresh_route_control_from_ship_systems()
	if oxygen_state != null:
		oxygen_state.apply_summary(snapshot.oxygen_summary)
		_refresh_oxygen_state(false, 0.0)
	if inventory_state != null:
		inventory_state.apply_summary(snapshot.inventory_summary)
	if fire_state != null:
		fire_state.apply_summary(snapshot.fire_summary)
	if objective_progress_state != null:
		objective_progress_state.apply_summary(snapshot.objective_progress_summary)
	current_objective_sequence = snapshot.current_objective_sequence
	_activate_current_objective()
	if player != null and snapshot.player_position.size() >= 3:
		player.teleport_to(Vector3(snapshot.player_position[0], snapshot.player_position[1], snapshot.player_position[2]))
	last_saved_snapshot = snapshot
	print("PLAYABLE SHIP LOADED sequence=%d position=(%.2f,%.2f,%.2f)" % [
		current_objective_sequence,
		snapshot.player_position[0],
		snapshot.player_position[1],
		snapshot.player_position[2],
	])
	return true
```

- [ ] **Step 4: Implement manual save trigger and input handling**

Add to `PlayableGeneratedShip`:

```gdscript
func request_save() -> bool:
	if not playable_started or slice_complete:
		return false
	return _auto_save_current_run()

func get_save_load_service() -> SaveLoadService:
	return save_load_service

func get_last_saved_snapshot() -> RunSnapshot:
	return last_saved_snapshot

func is_load_available() -> bool:
	if save_load_service == null:
		return false
	return save_load_service.has_save()

func _input(event: InputEvent) -> void:
	if not playable_started or slice_complete:
		return
	if event.is_action_pressed("save_run"):
		request_save()
	elif event.is_action_pressed("load_run"):
		request_load()
```

- [ ] **Step 5: Wire auto-save and deletion**

In `_on_interactable_completed`, after `current_objective_sequence += 1` and before `_activate_current_objective()`, add:

```gdscript
_auto_save_current_run()
```

On `playable_slice_completed` emission (after `emit_signal("playable_slice_completed", ...)`), add:

```gdscript
if save_load_service != null:
	save_load_service.delete_current_run()
```

- [ ] **Step 6: Re-run both smokes**

Run:

```bash
/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-synaptic-sea-of-stars --script res://scripts/validation/save_load_service_smoke.gd
/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-synaptic-sea-of-stars --script res://scripts/validation/main_playable_slice_save_load_smoke.gd
```

Expected green result:

- `SAVE LOAD SERVICE PASS round_trip=true version_match=true summaries=6`
- `MAIN PLAYABLE SAVE LOAD PASS saved_sequence=2 loaded_sequence=2 position_match=true supplies=true`
- No unexpected `ERROR:` or `WARNING:` lines.

- [ ] **Step 7: Record the green phase**

Run:

```bash
printf '%s\n' 'NO_GIT Task 6 GREEN PlayableGeneratedShip save/load hooks implemented; both smokes pass' >> /tmp/synaptic_sea_save_load_no_git_changes.log
```

---

### Task 7: Regression Bundle and Validation Plan Update

**Files:**
- Modify: `docs/game/06_validation_plan.md`

- [ ] **Step 1: Add save/load smokes to the regression bundle**

Patch `docs/game/06_validation_plan.md`:

1. Add two `run_clean` lines to the bundle script after the readability smoke:
   - `run_clean 'save/load service smoke' 'SAVE LOAD SERVICE PASS round_trip=true version_match=true summaries=6' ...`
   - `run_clean 'main save/load smoke' 'MAIN PLAYABLE SAVE LOAD PASS saved_sequence=2 loaded_sequence=2 position_match=true supplies=true' ...`
2. Update the final `SYNAPTIC_SEA REGRESSION PASS commands=N` line to count the new smokes.
3. Update the evidence-collection loop to include the two new smokes.
4. Move the four lines under "Future validation additions" for REQ-007/010/011/012 into the active regression bundle as they are implemented; for REQ-012, remove or strike the bullet now that it is in the bundle.

- [ ] **Step 2: Run the full regression bundle**

Run:

```bash
cd /Users/christopherwilloughby/the-synaptic-sea-of-stars
bash docs/game/06_validation_plan.md
```

(Extract and execute the regression bundle block; if the markdown file is not executable, copy the bundle script into a temp file and run it.)

Expected green result:

- `SYNAPTIC_SEA REGRESSION PASS commands=N clean_output=true` where N reflects the new count.

- [ ] **Step 3: Record the regression update**

Run:

```bash
printf '%s\n' 'NO_GIT Task 7 GREEN docs/game/06_validation_plan.md updated with save/load smokes; full regression bundle passes' >> /tmp/synaptic_sea_save_load_no_git_changes.log
```

---

## Non-Goals

- No hub ship state, derelict selection, meta-currency, persistent unlocks, faction/narrative state, cross-run progress, multiple save slots, cloud/Steam sync, encryption/compression, or mid-animation/physics preservation.
- No save/load during real-time hazard transitions; auto-save fires only at stable objective-completion boundaries.
- No migration path for old save formats beyond version rejection.
- No UI pause menu or save/load widget; only input actions and validation seams in this card.

## Risks

| Risk | Mitigation |
|------|------------|
| Save/load becomes a vector for hub/meta persistence by accident. | `RunSnapshot` explicitly excludes hub fields; code-review checklist checks for any hub/meta data in the snapshot. ADR-0007 governs additions. |
| Model summaries drift out of sync with `apply_summary()` methods. | Each model smoke asserts round-trip; if a new field is added to `get_summary()` without a matching loader, the smoke fails. |
| `user://` path differs between editor and exported builds. | Always use `user://saves/current_run.json` via `ProjectSettings`; never hard-code an absolute path. |
| Loading from a snapshot skips initialization side effects (route gates, breach zone). | Load path re-uses the normal `_ready` flow and applies model summaries after scene nodes are built. |
| `await get_tree().process_frame` in `_apply_run_snapshot` breaks headless smoke determinism. | If the headless smoke fails because of await timing, replace it with a single deferred `call_deferred` chain or poll `playable_started` for a bounded number of frames. |
| REQ-007/010/011 models change their summary shape after this card lands. | Their review cards must verify that `apply_summary()` matches `get_summary()`; save/load smoke will fail if shapes drift. |

## Stop / Block Conditions

Block and escalate to `synaptic_sea_review` if:

- ADR-0007 scope boundary is challenged by implementation needs.
- Current-run persistence would need to expand into hub/cross-run/meta persistence to satisfy a downstream feature.
- The plan cannot capture REQ-007/010/011 state because those implementations do not expose `get_summary()` / `apply_summary()` by their review deadline.
- Any validation smoke emits an unexpected `ERROR:` or `WARNING:` line that cannot be classified as baseline engine noise.
- The main-scene load path cannot restore the player position within `0.01` units or the objective sequence exactly.

## Verification Commands (downstream implementation)

Direct model smoke:

```bash
/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-synaptic-sea-of-stars --script res://scripts/validation/save_load_service_smoke.gd
```

Main-scene smoke:

```bash
/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-synaptic-sea-of-stars --script res://scripts/validation/main_playable_slice_save_load_smoke.gd
```

Regression bundle (after update):

```bash
cd /Users/christopherwilloughby/the-synaptic-sea-of-stars
# Copy the regression bundle block from docs/game/06_validation_plan.md into a temp script and run it.
```

Expected markers:

- `SAVE LOAD SERVICE PASS round_trip=true version_match=true summaries=6`
- `MAIN PLAYABLE SAVE LOAD PASS saved_sequence=2 loaded_sequence=2 position_match=true supplies=true`
- `SYNAPTIC_SEA REGRESSION PASS commands=N clean_output=true`

## Allowed Files

- `scripts/systems/run_snapshot.gd`
- `scripts/systems/save_load_service.gd`
- `scripts/systems/ship_system_state.gd`
- `scripts/systems/route_control_state.gd`
- `scripts/systems/oxygen_state.gd`
- `scripts/systems/inventory_state.gd` (create or patch)
- `scripts/systems/fire_state.gd` (create or patch)
- `scripts/systems/objective_progress_state.gd` (create or patch)
- `scripts/procgen/playable_generated_ship.gd`
- `scripts/validation/save_load_service_smoke.gd`
- `scripts/validation/main_playable_slice_save_load_smoke.gd`
- `docs/game/06_validation_plan.md`
- `docs/game/adr/0007-save-load-service-scope.md` (already authored by this plan card)

## Handoff Notes for Implementer

- Read ADR-0007 before touching any runtime code.
- Do not start until REQ-007, REQ-010, and REQ-011 review cards are done.
- If a Gate 2 model file already exists with a different shape, preserve its behavior and add `apply_summary()` to match its existing `get_summary()`; do not rewrite it.
- Keep `RunSnapshot` fields current-run-only. Any proposed new field must pass the ADR-0007 scope checklist.
- The headless smoke deletes `user://saves/current_run.json` before and after to avoid polluting the user's slot.
