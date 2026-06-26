# World Persistence Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every visited ship persist and the whole world serializable at any instant (save anywhere), by wrapping the single-ship `RunSnapshot` in a new `WorldSnapshot` and replacing regenerate-on-revisit derelicts with persist-and-restore.

**Architecture:** A new pure-data `WorldSnapshot` holds the `Synaptic SeaWorld` summary, the home ship's existing `RunSnapshot` (unchanged), a `visited_ships` registry of per-derelict slices keyed by `marker_id`, the current location, and the in-ship player position. The coordinator keeps a live `visited_ships: Dictionary` of `ShipInstance`s — only the active ship has a live `scene_root`; derelict geometry is regenerated deterministically from seed on revisit while mutable state rides the `ShipInstance` summaries. Save/load operate on the whole `WorldSnapshot`, removing the Phase 4.5 away-save rejection.

**Tech Stack:** Godot 4.6.2, typed GDScript, headless `--script` validation smokes (each prints a single PASS marker line that is the contract).

## Global Constraints

- Godot binary (headless): `C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe` (use the `_console` build). Project root: `C:/Users/dasbl/Documents/The Synaptic Sea`.
- A smoke's **PASS marker line is the contract** — `--script` can exit 0 on parse errors, so always confirm the marker is printed and no parse error / unexpected `ERROR:`/`WARNING:` appears. Allowlisted teardown noise: `ERROR: Capture not registered: 'gdaimcp'.` and `WARNING: ObjectDB instances leaked at exit`.
- **Model/Node separation:** `WorldSnapshot` is a pure `RefCounted` data class that never touches the scene tree, with `to_dict()`/`from_dict()` like `RunSnapshot`. Scene-tree lifecycle stays in the coordinator.
- **Determinism:** ship geometry is regenerated from seed via the existing `ShipGenerator`; never serialize scenes. No `Time`/`randf`/`hash()` in persisted-state logic. (`saved_at` may use `Time` — it already does in `_build_run_snapshot`.)
- **`class_name` globals are unreliable under `--headless --script`:** in scripts that are loaded as instances, reference other scripts via `const XScript := preload("res://...")` and construct via the script's own `load(...).new()` factory where a self-reference is needed. Coordinator cross-script instance fields stay **untyped** (matches `ship_systems_manager`, `current_ship`).
- **`RunSnapshot` gets no new fields** (ADR-0007: adding a field requires an ADR). It is embedded whole inside `WorldSnapshot`.
- **Single save slot**, `user://saves/current_run.json` (existing `SaveLoadService.SAVE_PATH`). The world save reuses this slot; old single-ship saves become version-incompatible → rejected → fresh run. No autosave, no multi-slot.
- **Selective `git add`** only (never `git add -A`); never stage `.godot/`, `*.uid`, or `addons/`. Conventional Commits; commit trailer `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.

---

## File Structure

- **Create** `scripts/systems/world_snapshot.gd` — `WorldSnapshot` pure-data class (Task 1).
- **Create** `scripts/validation/world_snapshot_smoke.gd` — pure model smoke (Task 1).
- **Modify** `scripts/systems/save_load_service.gd` — add `save_world()` / `load_world()` (Task 2).
- **Create** `scripts/validation/world_save_service_smoke.gd` — disk round-trip smoke (Task 2).
- **Modify** `scripts/procgen/playable_generated_ship.gd` — `visited_ships` registry, persist-and-restore `travel_to`, `travel_home`, `home_ship`/`_home_player_position` fields (Task 3); world save/load (`_build_world_snapshot`, `_apply_world_snapshot`, `_activate_derelict_from_instance`) + `request_save`/`request_load` rewire (Task 4).
- **Create** `scripts/validation/world_persist_restore_smoke.gd` — in-session persist-and-restore smoke (Task 3).
- **Create** `scripts/validation/world_save_anywhere_smoke.gd` — save-anywhere smoke (Task 4).
- **Modify** `scripts/validation/travel_integration_smoke.gd` — update superseded assertions (away-save now succeeds) (Task 4).
- **Create** `docs/game/adr/0012-world-persistence-model.md` (Task 5).
- **Modify** `docs/game/06_validation_plan.md` — register 3 new smokes; remove obsolete `REQ012_AWAY_SAVE_WARNING` allowlist entry (Task 5).

---

### Task 1: `WorldSnapshot` pure-data class

**Files:**
- Create: `scripts/systems/world_snapshot.gd`
- Test: `scripts/validation/world_snapshot_smoke.gd`

**Interfaces:**
- Consumes: `RunSnapshot` (`scripts/systems/run_snapshot.gd`) `to_dict()` / `from_dict(data, expected_slice_version, expected_godot_version)`.
- Produces:
  - `WorldSnapshot` fields: `world_summary: Dictionary`, `home_ship: Dictionary` (a `RunSnapshot.to_dict()`), `visited_ships: Dictionary` (`marker_id String -> ShipInstance.get_summary() Dictionary`), `current_location: String` (`""` = home), `player_position_in_ship: Array` (`[x,y,z]`), `slice_version: String`, `godot_version: String`, `saved_at: String`.
  - `const WORLD_SLICE_VERSION: String = "world-1"`.
  - `to_dict() -> Dictionary`.
  - `static from_dict(data, expected_world_version: String, expected_godot_version: String) -> WorldSnapshot` (returns `null` on type/empty/version mismatch).

- [ ] **Step 1: Write the failing smoke**

Create `scripts/validation/world_snapshot_smoke.gd`:

```gdscript
extends SceneTree

## Unit smoke for WorldSnapshot: round-trip + version-mismatch rejection.

const WorldSnapshotScript := preload("res://scripts/systems/world_snapshot.gd")

func _initialize() -> void:
	var godot_version: String = Engine.get_version_info()["string"]

	var ws = WorldSnapshotScript.new()
	ws.world_summary = {"world_seed": 99, "player_position": [1.0, 0.0, 2.0], "generated_marker_ids": ["3:1:0"]}
	ws.home_ship = {"slice_version": "gate2-current-run-1", "player_position": [5.0, 1.0, 5.0]}
	ws.visited_ships = {
		"3:1:0": {"ship_id": "ship_3:1:0", "marker_id": "3:1:0", "blueprint": {"size": 1, "condition": 2, "seed": 7}, "systems": {"k": "v"}},
	}
	ws.current_location = "3:1:0"
	ws.player_position_in_ship = [10.0, 2.0, 3.0]
	ws.slice_version = WorldSnapshotScript.WORLD_SLICE_VERSION
	ws.godot_version = godot_version
	ws.saved_at = "2026-06-21T00:00:00"

	var dict: Dictionary = ws.to_dict()
	var rebuilt = WorldSnapshotScript.from_dict(dict, WorldSnapshotScript.WORLD_SLICE_VERSION, godot_version)
	if rebuilt == null:
		_fail("from_dict returned null on a valid dict")
		return
	if int(rebuilt.world_summary.get("world_seed", -1)) != 99:
		_fail("world_summary not restored")
		return
	if String(rebuilt.current_location) != "3:1:0":
		_fail("current_location not restored")
		return
	if not rebuilt.visited_ships.has("3:1:0"):
		_fail("visited_ships key not restored")
		return
	if String(rebuilt.home_ship.get("slice_version", "")) != "gate2-current-run-1":
		_fail("home_ship dict not restored")
		return
	if rebuilt.player_position_in_ship.size() != 3 or float(rebuilt.player_position_in_ship[0]) != 10.0:
		_fail("player_position_in_ship not restored")
		return

	# Version mismatch → null.
	if WorldSnapshotScript.from_dict(dict, "world-999", godot_version) != null:
		_fail("from_dict should reject mismatched world version")
		return
	if WorldSnapshotScript.from_dict(dict, WorldSnapshotScript.WORLD_SLICE_VERSION, "0.0.0") != null:
		_fail("from_dict should reject mismatched godot version")
		return
	# Non-dict / empty → null.
	if WorldSnapshotScript.from_dict(null, WorldSnapshotScript.WORLD_SLICE_VERSION, godot_version) != null:
		_fail("from_dict should reject null")
		return
	if WorldSnapshotScript.from_dict({}, WorldSnapshotScript.WORLD_SLICE_VERSION, godot_version) != null:
		_fail("from_dict should reject empty dict")
		return

	print("WORLD SNAPSHOT PASS round_trip=true version_gated=true")
	quit(0)

func _fail(reason: String) -> void:
	push_error("WORLD SNAPSHOT FAIL reason=%s" % reason)
	quit(1)
```

- [ ] **Step 2: Run the smoke to verify it fails**

Run:
```bash
GODOT="C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe"
ROOT="C:/Users/dasbl/Documents/The Synaptic Sea"
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/world_snapshot_smoke.gd
```
Expected: parse/load error (`world_snapshot.gd` does not exist yet) — NOT the `WORLD SNAPSHOT PASS` marker.

- [ ] **Step 3: Implement `WorldSnapshot`**

Create `scripts/systems/world_snapshot.gd`:

```gdscript
extends RefCounted
class_name WorldSnapshot

## Top-level world save. Wraps the Synaptic SeaWorld summary, the home ship's
## RunSnapshot (unchanged), a per-derelict slice registry keyed by marker_id,
## the player's current location, and the in-ship player position. Pure data;
## serialization-agnostic (SaveLoadService owns file I/O). Geometry is never
## stored — derelict hulls regenerate deterministically from seed; only mutable
## state rides the per-ship slices.

const WORLD_SLICE_VERSION: String = "world-1"

var world_summary: Dictionary = {}
var home_ship: Dictionary = {}                  # a RunSnapshot.to_dict()
var visited_ships: Dictionary = {}              # marker_id -> ShipInstance.get_summary()
var current_location: String = ""               # "" = home ship, else marker_id
var player_position_in_ship: Array = [0.0, 0.0, 0.0]
var slice_version: String = ""
var godot_version: String = ""
var saved_at: String = ""

func to_dict() -> Dictionary:
	return {
		"world_summary": world_summary.duplicate(true),
		"home_ship": home_ship.duplicate(true),
		"visited_ships": visited_ships.duplicate(true),
		"current_location": current_location,
		"player_position_in_ship": player_position_in_ship.duplicate(),
		"slice_version": slice_version,
		"godot_version": godot_version,
		"saved_at": saved_at,
	}

## Reconstructs a WorldSnapshot. Returns null when data is missing/not a dict,
## or when either version marker does not match (per ADR-0007/0012: incompatible
## saves are rejected so load always falls back to a fresh run).
static func from_dict(data, expected_world_version: String, expected_godot_version: String) -> WorldSnapshot:
	if typeof(data) != TYPE_DICTIONARY:
		return null
	var dict: Dictionary = data as Dictionary
	if dict.is_empty():
		return null
	if str(dict.get("slice_version", "")) != expected_world_version:
		return null
	if str(dict.get("godot_version", "")) != expected_godot_version:
		return null
	var ws := WorldSnapshot.new()
	ws.world_summary = _deep_copy_dict(dict.get("world_summary", {}))
	ws.home_ship = _deep_copy_dict(dict.get("home_ship", {}))
	ws.visited_ships = _deep_copy_dict(dict.get("visited_ships", {}))
	ws.current_location = str(dict.get("current_location", ""))
	var pos = dict.get("player_position_in_ship", [0.0, 0.0, 0.0])
	if typeof(pos) == TYPE_ARRAY and (pos as Array).size() >= 3:
		var pa: Array = pos as Array
		ws.player_position_in_ship = [float(pa[0]), float(pa[1]), float(pa[2])]
	ws.slice_version = str(dict.get("slice_version", ""))
	ws.godot_version = str(dict.get("godot_version", ""))
	ws.saved_at = str(dict.get("saved_at", ""))
	return ws

static func _deep_copy_dict(src) -> Dictionary:
	if typeof(src) != TYPE_DICTIONARY:
		return {}
	return (src as Dictionary).duplicate(true)
```

- [ ] **Step 4: Run the smoke to verify it passes**

Run the same command as Step 2.
Expected: stdout contains `WORLD SNAPSHOT PASS round_trip=true version_gated=true`, no parse error, exit 0.

- [ ] **Step 5: Commit**

```bash
git add scripts/systems/world_snapshot.gd scripts/validation/world_snapshot_smoke.gd
git commit -m "feat(persistence): add WorldSnapshot pure-data class + model smoke"
```

---

### Task 2: `SaveLoadService.save_world` / `load_world`

**Files:**
- Modify: `scripts/systems/save_load_service.gd`
- Test: `scripts/validation/world_save_service_smoke.gd`

**Interfaces:**
- Consumes: `WorldSnapshot` (Task 1) `to_dict()` / `WorldSnapshot.from_dict(...)` / `WorldSnapshot.WORLD_SLICE_VERSION`.
- Produces on `SaveLoadService`:
  - `save_world(world_snapshot: WorldSnapshot) -> bool` — writes `world_snapshot.to_dict()` JSON to `SAVE_PATH`.
  - `load_world() -> WorldSnapshot` — reads `SAVE_PATH`, returns a `WorldSnapshot` or `null` (missing/empty/invalid/version-mismatch).
  - Existing `save_current_run` / `load_current_run` / `has_save` / `delete_current_run` unchanged.

- [ ] **Step 1: Write the failing smoke**

Create `scripts/validation/world_save_service_smoke.gd`:

```gdscript
extends SceneTree

## Disk round-trip smoke for SaveLoadService world save/load.

const SaveLoadServiceScript := preload("res://scripts/systems/save_load_service.gd")
const WorldSnapshotScript := preload("res://scripts/systems/world_snapshot.gd")

func _initialize() -> void:
	var svc = SaveLoadServiceScript.new()
	svc.delete_current_run()  # start clean

	var ws = WorldSnapshotScript.new()
	ws.world_summary = {"world_seed": 5, "player_position": [0.0, 0.0, 0.0], "generated_marker_ids": ["2:0:1"]}
	ws.home_ship = {"slice_version": "gate2-current-run-1"}
	ws.visited_ships = {"2:0:1": {"marker_id": "2:0:1", "blueprint": {"size": 0, "condition": 1, "seed": 11}, "systems": {}}}
	ws.current_location = "2:0:1"
	ws.player_position_in_ship = [4.0, 1.0, 6.0]
	ws.slice_version = WorldSnapshotScript.WORLD_SLICE_VERSION
	ws.godot_version = Engine.get_version_info()["string"]
	ws.saved_at = "2026-06-21T00:00:00"

	if not svc.save_world(ws):
		_fail("save_world returned false")
		return
	if not svc.has_save():
		_fail("has_save false after save_world")
		return

	var loaded = svc.load_world()
	if loaded == null:
		_fail("load_world returned null after a valid save")
		return
	if String(loaded.current_location) != "2:0:1":
		_fail("current_location not round-tripped through disk")
		return
	if not loaded.visited_ships.has("2:0:1"):
		_fail("visited_ships not round-tripped through disk")
		return
	if int(loaded.world_summary.get("world_seed", -1)) != 5:
		_fail("world_summary not round-tripped through disk")
		return

	# Reject null snapshot.
	if svc.save_world(null):
		_fail("save_world(null) should return false")
		return

	svc.delete_current_run()
	if svc.load_world() != null:
		_fail("load_world should return null when no save exists")
		return

	print("WORLD SAVE SERVICE PASS disk_round_trip=true rejects_null=true")
	quit(0)

func _fail(reason: String) -> void:
	push_error("WORLD SAVE SERVICE FAIL reason=%s" % reason)
	quit(1)
```

- [ ] **Step 2: Run the smoke to verify it fails**

Run:
```bash
GODOT="C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe"
ROOT="C:/Users/dasbl/Documents/The Synaptic Sea"
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/world_save_service_smoke.gd
```
Expected: FAIL — `save_world`/`load_world` do not exist (`Invalid call. Nonexistent function 'save_world'`), no PASS marker.

- [ ] **Step 3: Implement `save_world` / `load_world`**

In `scripts/systems/save_load_service.gd`, add these two methods after `load_current_run()` (before `delete_current_run()`):

```gdscript
## REQ-0012 world save: serializes a whole WorldSnapshot to the single slot.
## Reuses SAVE_PATH; an old single-ship save at that path is rejected by
## WorldSnapshot.from_dict on the next load_world (version mismatch → fresh run).
func save_world(world_snapshot: WorldSnapshot) -> bool:
	if world_snapshot == null:
		push_warning("SaveLoadService: cannot save null world snapshot")
		return false
	var json: String = JSON.stringify(world_snapshot.to_dict(), "\t")
	var dir_path: String = SAVE_PATH.get_base_dir()
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir_path)):
		var make_err: int = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir_path))
		if make_err != OK and make_err != ERR_ALREADY_EXISTS:
			push_warning("SaveLoadService: failed to create save dir, error=%d" % make_err)
			return false
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("SaveLoadService: cannot open save file for writing, error=%d" % FileAccess.get_open_error())
		return false
	file.store_string(json)
	file.close()
	return true

## Reads the world save. Returns null when no save exists, the file is empty/
## not a JSON object, or the WorldSnapshot version markers do not match.
func load_world() -> WorldSnapshot:
	if not has_save():
		return null
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_warning("SaveLoadService: cannot open save file for reading, error=%d" % FileAccess.get_open_error())
		return null
	var json: String = file.get_as_text()
	file.close()
	if json.is_empty():
		push_warning("SaveLoadService: save file is empty")
		return null
	var parsed = JSON.parse_string(json)
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		push_warning("SaveLoadService: save file is not valid JSON object")
		return null
	var expected_godot: String = Engine.get_version_info()["string"]
	var ws: WorldSnapshot = WorldSnapshot.from_dict(parsed as Dictionary, WorldSnapshot.WORLD_SLICE_VERSION, expected_godot)
	if ws == null:
		push_warning("SaveLoadService: world save rejected by from_dict (missing fields or version mismatch)")
		return null
	return ws
```

- [ ] **Step 4: Run the smoke to verify it passes**

Run the same command as Step 2.
Expected: stdout contains `WORLD SAVE SERVICE PASS disk_round_trip=true rejects_null=true`, no parse error, exit 0.

Note: the deliberate `save_world(null)` path prints one allowlisted `WARNING: SaveLoadService: cannot save null world snapshot` — register it in the validation plan (Task 5). It does not block this smoke (the smoke asserts the `false` return, not absence of the warning).

- [ ] **Step 5: Commit**

```bash
git add scripts/systems/save_load_service.gd scripts/validation/world_save_service_smoke.gd
git commit -m "feat(persistence): SaveLoadService world save/load + disk smoke"
```

---

### Task 3: Visited-ships registry + persist-and-restore travel

**Files:**
- Modify: `scripts/procgen/playable_generated_ship.gd`
- Test: `scripts/validation/world_persist_restore_smoke.gd`

**Interfaces:**
- Consumes: existing `ShipInstanceScript.create(ship_id, marker_id, blueprint, systems_manager, scene_root)`; `ShipBlueprintScript.new(size, condition, seed)`; `ship_generator` (`ShipGenerator`) `generate(blueprint) -> Node3D`; `travel_controller.attempt_travel(...)`; `player.teleport_to(Vector3)`; `current_ship`, `away_from_start`, `_detach_starting_gameplay_roots()`, `_reattach_starting_gameplay_roots()`, `PLAYER_SPAWN_HEIGHT_ABOVE_NAV_FLOOR`.
- Produces on the coordinator (used by Task 4):
  - `var visited_ships: Dictionary = {}` — `marker_id String -> ShipInstance`.
  - `var home_ship = null` — the home `ShipInstance` (untyped; set in `_on_ship_loaded`).
  - `var _home_player_position: Vector3 = Vector3.ZERO` — player's last home scene position.
  - `func _attach_derelict_active(inst, new_root: Node3D) -> void` — detaches home roots, adds `new_root`, sets `current_ship = inst`, `inst.scene_root = new_root`, `away_from_start = true`.
  - `func travel_home() -> bool` — returns to the home ship instance.
  - `func get_visited_ship_ids() -> Array` (validation seam).

This task changes the **meaning** of leaving a derelict: the `ShipInstance` is retained in `visited_ships` (state preserved); only its `scene_root` is freed. Revisiting reuses the retained instance (keeping its mutated `systems_manager`) and rebuilds geometry from seed.

- [ ] **Step 1: Write the failing smoke**

Create `scripts/validation/world_persist_restore_smoke.gd`:

```gdscript
extends SceneTree

## In-session persist-and-restore smoke. Proves: travel to derelict A registers
## a ShipInstance; mutating A's systems then leaving (travel to B) keeps A's
## instance with its mutated state; revisiting A restores that state (NOT a fresh
## regenerate) with identical geometry signature; travel_home returns to the home
## ship instance.

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 300

var main_node: Node
var frame_count: int = 0
var finished: bool = false
var _exit_code: int = 0

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

func _all_operational(mgr) -> void:
	# Repair the four travel-relevant systems so jumps succeed from any ship.
	for sid in ["power", "navigation", "scanners", "propulsion"]:
		var sys = mgr.get_system(sid)
		if sys == null:
			continue
		for sub in sys.get_subcomponents():
			mgr.force_repair(sid, sub.id)

func _validate(playable: PlayableGeneratedShip) -> void:
	# Home ship wrapped and registered as home_ship.
	var home = playable.get_current_ship()
	if home == null or String(home.marker_id) != "":
		_fail("home ship not wrapped (marker_id must be empty)")
		return
	if playable.home_ship != home:
		_fail("home_ship reference not set to the starting ship")
		return
	_all_operational(playable.get_ship_systems_manager())

	# Travel to derelict A.
	var world = playable.get_synaptic_sea_world()
	var in_range: Array = world.markers_in_range(playable.scanner_state.range_radius)
	if in_range.size() < 1:
		_fail("no markers in range of the home position")
		return
	var id_a: String = String(in_range[0].marker_id)
	var ra: Dictionary = playable.travel_to_marker_id(id_a)
	if not bool(ra.get("success", false)):
		_fail("travel to A failed: %s" % String(ra.get("reason", "")))
		return
	if not playable.visited_ships.has(id_a):
		_fail("derelict A not registered in visited_ships")
		return
	var inst_a = playable.visited_ships[id_a]

	# Mutate A's own systems manager to a recognisable state and snapshot it.
	inst_a.systems_manager.force_repair("power", inst_a.systems_manager.get_system("power").get_subcomponents()[0].id)
	var a_summary_after_mutation: Dictionary = inst_a.systems_manager.get_summary()

	# Leave A by traveling to derelict B (from A's map position).
	var in_range2: Array = world.markers_in_range(playable.scanner_state.range_radius)
	var id_b: String = ""
	for m in in_range2:
		if String(m.marker_id) != id_a:
			id_b = String(m.marker_id)
			break
	if id_b == "":
		_fail("could not find a second distinct marker B in range of A")
		return
	var rb: Dictionary = playable.travel_to_marker_id(id_b)
	if not bool(rb.get("success", false)):
		_fail("travel to B failed: %s" % String(rb.get("reason", "")))
		return
	# A's instance is RETAINED with its mutated state; only its scene was freed.
	if not playable.visited_ships.has(id_a):
		_fail("derelict A dropped from visited_ships after leaving (state lost)")
		return
	if playable.visited_ships[id_a] != inst_a:
		_fail("derelict A instance replaced after leaving (must be the same retained object)")
		return

	# Revisit A: same retained instance, state preserved (NOT regenerated fresh).
	var ra2: Dictionary = playable.travel_to_marker_id(id_a)
	if not bool(ra2.get("success", false)):
		_fail("revisit A failed: %s" % String(ra2.get("reason", "")))
		return
	if playable.get_current_ship() != inst_a:
		_fail("revisit A did not restore the retained instance")
		return
	if inst_a.systems_manager.get_summary() != a_summary_after_mutation:
		_fail("derelict A systems state was regenerated, not preserved across revisit")
		return
	if inst_a.scene_root == null or not is_instance_valid(inst_a.scene_root):
		_fail("revisited A has no live scene_root")
		return

	# travel_home returns to the home instance with gameplay roots reattached.
	var home_ok: bool = playable.travel_home()
	if not home_ok:
		_fail("travel_home returned false")
		return
	if playable.get_current_ship() != home:
		_fail("travel_home did not restore the home ship instance")
		return
	if playable.away_from_start:
		_fail("away_from_start still true after travel_home")
		return
	if playable.oxygen_root == null or playable.oxygen_root.get_parent() != playable:
		_fail("gameplay roots not reattached after travel_home")
		return

	finished = true
	print("WORLD PERSIST RESTORE PASS registered=true state_preserved=true revisit_restores=true travel_home=true")
	_teardown_and_quit(0)

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
	push_error("WORLD PERSIST RESTORE FAIL reason=%s" % reason)
	_teardown_and_quit(1)

func _teardown_and_quit(code: int) -> void:
	_exit_code = code
	if main_node != null and is_instance_valid(main_node):
		main_node.free()
		main_node = null
	call_deferred("_do_quit")

func _do_quit() -> void:
	quit(_exit_code)
```

- [ ] **Step 2: Run the smoke to verify it fails**

Run:
```bash
GODOT="C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe"
ROOT="C:/Users/dasbl/Documents/The Synaptic Sea"
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/world_persist_restore_smoke.gd
```
Expected: FAIL — `visited_ships` / `home_ship` / `travel_home` do not exist yet (e.g. `Invalid get index 'visited_ships'`). No PASS marker.

- [ ] **Step 3: Add the registry fields**

In `scripts/procgen/playable_generated_ship.gd`, near the Phase 4.5 travel fields (find `var away_from_start: bool = false`, around line 119), add:

```gdscript
# Sub-project #1 (world persistence): every visited derelict is retained by
# marker_id so its mutable state survives leaving. Only the ACTIVE ship has a
# live scene_root; a derelict's geometry is regenerated from seed on revisit
# while its systems_manager (and later objective/hazard/loot summaries) ride the
# retained ShipInstance.
var visited_ships: Dictionary = {}          # marker_id -> ShipInstance
var home_ship = null                        # the home ShipInstance (marker_id "")
var _home_player_position: Vector3 = Vector3.ZERO
```

- [ ] **Step 4: Record `home_ship` when the starting ship is wrapped**

In `_on_ship_loaded`, find the Phase 4.5 starting-ship wrap (the `if current_ship == null:` block around line 1074 that calls `ShipInstanceScript.create("ship_start", "", ...)`). Immediately after `current_ship` is assigned there, add:

```gdscript
		# Sub-project #1: keep a stable reference to the home ship so travel_home
		# and world-load can restore it.
		home_ship = current_ship
```

(Place it inside the same `if current_ship == null:` block, after the `current_ship = ...` assignment.)

- [ ] **Step 5: Add `_attach_derelict_active` and rewrite the leave/arrive logic in `travel_to`**

Add this helper just above `func travel_to(marker)` (after `_reattach_starting_gameplay_roots`):

```gdscript
## Makes `inst` the active boarded derelict: detaches the home gameplay roots
## (so they do not overlay the derelict at the shared local origin), attaches the
## freshly built `new_root`, and flips away_from_start. Shared by travel_to
## (revisit/first-visit) and world-load (_apply_world_snapshot). Does NOT re-home
## the player — callers position the player afterwards.
func _attach_derelict_active(inst, new_root: Node3D) -> void:
	_detach_starting_gameplay_roots()
	inst.scene_root = new_root
	add_child(new_root)
	current_ship = inst
	away_from_start = true
```

Replace the body of `travel_to` from the "Detach/free the ship we are leaving" block through the end of the function (lines ~1010–1038) with:

```gdscript
	# Leaving the current ship. The HOME ship is detached-not-freed (retains its
	# live sim); a DERELICT keeps its retained ShipInstance in visited_ships but
	# frees its scene_root (geometry regenerates from seed on revisit).
	var leaving = current_ship
	if String(leaving.marker_id) == "":
		_home_player_position = (player as Node3D).global_position if player != null and player is Node3D else _home_player_position
		if leaving.scene_root != null and is_instance_valid(leaving.scene_root) and leaving.scene_root.get_parent() == self:
			remove_child(leaving.scene_root)
		_detach_starting_gameplay_roots()
	else:
		if leaving.scene_root != null and is_instance_valid(leaving.scene_root):
			if leaving.scene_root.get_parent() == self:
				remove_child(leaving.scene_root)
			leaving.scene_root.queue_free()
		leaving.scene_root = null  # retained instance, scene dropped

	var mid: String = String(marker.marker_id)
	var inst
	if visited_ships.has(mid):
		# Revisit: reuse the retained instance (its systems state is preserved);
		# the freshly generated geometry replaces the freed scene.
		inst = visited_ships[mid]
	else:
		# First visit: build the per-ship systems manager seeded by condition so a
		# wrecked ship boards with mostly-offline systems, and register it.
		var new_bp = ShipBlueprintScript.new(int(marker.size_class), int(marker.condition), int(marker.seed_value))
		var new_mgr = ShipSystemsManagerScript.new()
		new_mgr.configure(new_mgr.load_definitions(), new_bp.condition, new_bp.seed_value)
		inst = ShipInstanceScript.create("ship_%s" % mid, mid, new_bp, new_mgr, null)
		visited_ships[mid] = inst

	_attach_derelict_active(inst, new_root)

	# Re-home the existing player + camera into the new ship's spawn. The player
	# node, camera, HUD, progression and inventory are NEVER freed (player-owned).
	if player != null and new_root.has_method("get_start_transform"):
		player.teleport_to(new_root.get_start_transform().origin + Vector3(0.0, PLAYER_SPAWN_HEIGHT_ABOVE_NAV_FLOOR, 0.0))
	return result
```

- [ ] **Step 6: Add `travel_home` and the validation seam**

Add after `travel_to`:

```gdscript
## Returns the player to the home ship instance: frees the active derelict's
## scene (its retained instance stays in visited_ships), re-attaches the home
## scene_root and gameplay roots, restores current_ship = home_ship, and re-homes
## the player at the position they left from. Returns false if not currently away
## or the home ship is unavailable.
func travel_home() -> bool:
	if not away_from_start or home_ship == null:
		return false
	var leaving = current_ship
	if leaving != null and String(leaving.marker_id) != "":
		if leaving.scene_root != null and is_instance_valid(leaving.scene_root):
			if leaving.scene_root.get_parent() == self:
				remove_child(leaving.scene_root)
			leaving.scene_root.queue_free()
		leaving.scene_root = null
	if home_ship.scene_root != null and is_instance_valid(home_ship.scene_root) and home_ship.scene_root.get_parent() == null:
		add_child(home_ship.scene_root)
	_reattach_starting_gameplay_roots()
	current_ship = home_ship
	away_from_start = false
	if player != null and player is Node3D:
		(player as Node3D).global_position = _home_player_position
	return true

## Validation seam: the marker_ids of every retained visited derelict.
func get_visited_ship_ids() -> Array:
	return visited_ships.keys()
```

- [ ] **Step 7: Run the persist-restore smoke to verify it passes**

Run the command from Step 2.
Expected: stdout contains `WORLD PERSIST RESTORE PASS registered=true state_preserved=true revisit_restores=true travel_home=true`, no parse error, exit 0.

- [ ] **Step 8: Run the existing travel smoke (regression guard)**

Run:
```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/travel_integration_smoke.gd
```
Expected: it may now FAIL at step 10 (it asserts `request_save` while away returns **false**, which is still true at this task — `request_save` is rewired in Task 4). If it still prints `TRAVEL INTEGRATION PASS`, good. If it fails ONLY at the away-save step, that is expected and is fixed in Task 4; note it and proceed. Any OTHER failure (e.g. derelict→derelict travel, reload-while-away) is a real regression in this task — fix before committing.

- [ ] **Step 9: Commit**

```bash
git add scripts/procgen/playable_generated_ship.gd scripts/validation/world_persist_restore_smoke.gd
git commit -m "feat(persistence): retain visited ships + persist-and-restore travel"
```

---

### Task 4: World save/load on the coordinator (save-anywhere)

**Files:**
- Modify: `scripts/procgen/playable_generated_ship.gd`
- Modify: `scripts/validation/travel_integration_smoke.gd`
- Test: `scripts/validation/world_save_anywhere_smoke.gd`

**Interfaces:**
- Consumes: Task 1 `WorldSnapshotScript`; Task 2 `save_load_service.save_world()/load_world()`; Task 3 `visited_ships`, `home_ship`, `_home_player_position`, `_attach_derelict_active`; existing `_build_run_snapshot()`, `_apply_run_snapshot(snapshot)`, `RunSnapshotScript.from_dict(...)`, `synaptic_sea_world.get_summary()/apply_summary()`, `ship_generator.generate(blueprint)`.
- Produces on the coordinator:
  - `const WorldSnapshotScript := preload("res://scripts/systems/world_snapshot.gd")` (top-of-file, with the other preloads).
  - `func _build_world_snapshot() -> WorldSnapshot`.
  - `func _apply_world_snapshot(ws: WorldSnapshot) -> bool`.
  - `func _activate_derelict_from_instance(inst, pos_in_ship: Array) -> bool`.
  - `request_save()` builds+saves a `WorldSnapshot` (no away-block). `request_load()` loads+applies a `WorldSnapshot`.

- [ ] **Step 1: Write the failing smoke**

Create `scripts/validation/world_save_anywhere_smoke.gd`:

```gdscript
extends SceneTree

## Save-anywhere smoke. Proves: saving WHILE aboard a derelict succeeds; reloading
## restores current_location, the derelict's persisted systems state, and the
## player's in-ship position; saving on the home ship restores home cleanly.

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 300

var main_node: Node
var frame_count: int = 0
var finished: bool = false
var _exit_code: int = 0

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

func _all_operational(mgr) -> void:
	for sid in ["power", "navigation", "scanners", "propulsion"]:
		var sys = mgr.get_system(sid)
		if sys == null:
			continue
		for sub in sys.get_subcomponents():
			mgr.force_repair(sid, sub.id)

func _validate(playable: PlayableGeneratedShip) -> void:
	playable.get_save_load_service().delete_current_run()  # clean slot
	_all_operational(playable.get_ship_systems_manager())

	# Travel to a derelict and mutate its systems to a recognisable state.
	var world = playable.get_synaptic_sea_world()
	var in_range: Array = world.markers_in_range(playable.scanner_state.range_radius)
	if in_range.is_empty():
		_fail("no markers in range")
		return
	var id_a: String = String(in_range[0].marker_id)
	if not bool(playable.travel_to_marker_id(id_a).get("success", false)):
		_fail("travel to derelict failed")
		return
	var inst_a = playable.visited_ships[id_a]
	inst_a.systems_manager.force_repair("power", inst_a.systems_manager.get_system("power").get_subcomponents()[0].id)
	var expected_summary: Dictionary = inst_a.systems_manager.get_summary()

	# Move the player to a recognisable in-ship position.
	if playable.player != null and playable.player is Node3D:
		(playable.player as Node3D).global_position = Vector3(12.0, 1.5, 7.0)

	# SAVE WHILE ABOARD A DERELICT — must succeed now (was blocked pre-Task 4).
	if not playable.request_save():
		_fail("request_save while aboard a derelict should succeed (save-anywhere)")
		return

	# RELOAD — must restore the derelict location, state, and position.
	if not playable.request_load():
		_fail("request_load of a world save should succeed")
		return
	if not playable.away_from_start:
		_fail("away_from_start false after loading a saved-aboard-derelict world")
		return
	var cur = playable.get_current_ship()
	if cur == null or String(cur.marker_id) != id_a:
		_fail("current_location not restored to the saved derelict")
		return
	if cur.systems_manager.get_summary() != expected_summary:
		_fail("derelict systems state not restored from world save")
		return
	if playable.player == null or not is_instance_valid(playable.player):
		_fail("player invalid after world load")
		return
	var p: Vector3 = (playable.player as Node3D).global_position
	if p.distance_to(Vector3(12.0, 1.5, 7.0)) > 0.5:
		_fail("player in-ship position not restored from world save (got %s)" % str(p))
		return

	# Return home, save on home, reload — home restored, not away.
	if not playable.travel_home():
		_fail("travel_home failed before home-save check")
		return
	if not playable.request_save():
		_fail("request_save on the home ship should succeed")
		return
	if not playable.request_load():
		_fail("request_load of a home-saved world should succeed")
		return
	if playable.away_from_start:
		_fail("away_from_start true after loading a home-saved world")
		return
	if String(playable.get_current_ship().marker_id) != "":
		_fail("current ship after home-saved load is not the home ship")
		return

	finished = true
	print("WORLD SAVE ANYWHERE PASS away_save=true location_restored=true state_restored=true home_save=true")
	_teardown_and_quit(0)

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
	push_error("WORLD SAVE ANYWHERE FAIL reason=%s" % reason)
	_teardown_and_quit(1)

func _teardown_and_quit(code: int) -> void:
	_exit_code = code
	if main_node != null and is_instance_valid(main_node):
		main_node.free()
		main_node = null
	call_deferred("_do_quit")

func _do_quit() -> void:
	quit(_exit_code)
```

- [ ] **Step 2: Run the smoke to verify it fails**

Run:
```bash
GODOT="C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe"
ROOT="C:/Users/dasbl/Documents/The Synaptic Sea"
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/world_save_anywhere_smoke.gd
```
Expected: FAIL at the away-save assertion (`request_save` still blocks while away until this task rewires it). No PASS marker.

- [ ] **Step 3: Add the `WorldSnapshot` preload**

Near the top of `scripts/procgen/playable_generated_ship.gd`, beside `const RunSnapshotScript := preload(...)` (line 21), add:

```gdscript
const WorldSnapshotScript := preload("res://scripts/systems/world_snapshot.gd")
```

- [ ] **Step 4: Add `_build_world_snapshot`, `_activate_derelict_from_instance`, `_apply_world_snapshot`**

Add these near `_build_run_snapshot` / `_apply_run_snapshot` (e.g. after `_apply_run_snapshot`, before `_reset_runtime_for_reload`):

```gdscript
## Builds a full WorldSnapshot from live state. The home-ship slice is the
## existing RunSnapshot; when the player is aboard a derelict the home slice's
## player_position is overridden with the position they left home from (the live
## player position belongs to the derelict and is stored separately). Each
## retained ShipInstance contributes its own slice; current_location names the
## active ship.
func _build_world_snapshot() -> WorldSnapshot:
	var ws := WorldSnapshotScript.new()
	if synaptic_sea_world != null:
		ws.world_summary = synaptic_sea_world.get_summary()
	var home_snap = _build_run_snapshot()
	if home_snap != null:
		if away_from_start:
			home_snap.player_position = [_home_player_position.x, _home_player_position.y, _home_player_position.z]
		ws.home_ship = home_snap.to_dict()
	ws.visited_ships = {}
	for mid in visited_ships:
		ws.visited_ships[String(mid)] = visited_ships[mid].get_summary()
	ws.current_location = String(current_ship.marker_id) if current_ship != null else ""
	if player != null and player is Node3D:
		var p: Vector3 = (player as Node3D).global_position
		ws.player_position_in_ship = [p.x, p.y, p.z]
	ws.slice_version = WorldSnapshotScript.WORLD_SLICE_VERSION
	ws.godot_version = Engine.get_version_info()["string"]
	ws.saved_at = Time.get_datetime_string_from_system(true)
	return ws

## Regenerates a derelict's geometry from its retained blueprint, makes it the
## active ship (re-applying its persisted systems state is implicit — the
## ShipInstance already holds it), and re-homes the player at pos_in_ship.
func _activate_derelict_from_instance(inst, pos_in_ship: Array) -> bool:
	if inst == null or ship_generator == null:
		return false
	var new_root: Node3D = ship_generator.generate(inst.blueprint)
	if new_root == null:
		return false
	_attach_derelict_active(inst, new_root)
	if player != null and player is Node3D and pos_in_ship.size() >= 3:
		(player as Node3D).global_position = Vector3(float(pos_in_ship[0]), float(pos_in_ship[1]), float(pos_in_ship[2]))
	return true

## Applies a WorldSnapshot: rebuilds the home ship first (this resets the runtime
## and returns to home if currently away), restores the Synaptic SeaWorld and the
## visited-ships registry, then re-activates the saved derelict if the snapshot
## was taken aboard one. Returns false on any hard failure.
func _apply_world_snapshot(ws: WorldSnapshot) -> bool:
	if ws == null:
		return false
	# 1. Home ship via the existing single-ship reload path. Reconstruct a
	#    RunSnapshot object from the embedded dict (version-gated like a disk load).
	var home_snap = RunSnapshotScript.from_dict(ws.home_ship, SaveLoadServiceScript.CURRENT_SLICE_VERSION, Engine.get_version_info()["string"])
	if home_snap == null:
		push_warning("PlayableGeneratedShip: world load rejected — embedded home slice incompatible")
		return false
	if not _apply_run_snapshot(home_snap):
		return false
	# 2. World model. _apply_run_snapshot reset us to the home ship; home_ship is
	#    re-wrapped by _on_ship_loaded during that reload.
	if synaptic_sea_world != null and not ws.world_summary.is_empty():
		synaptic_sea_world.apply_summary(ws.world_summary)
	# 3. Rebuild the retained-derelict registry from the slices.
	visited_ships.clear()
	for mid in ws.visited_ships:
		var inst = ShipInstanceScript.create("", "", ShipBlueprintScript.new(), null, null)
		if inst.apply_summary(ws.visited_ships[mid]):
			visited_ships[String(mid)] = inst
	# 4. If saved aboard a derelict, re-activate it.
	if String(ws.current_location) != "":
		var active = visited_ships.get(String(ws.current_location), null)
		if active == null:
			push_warning("PlayableGeneratedShip: world load — current_location '%s' missing from visited_ships" % String(ws.current_location))
			return true  # home is already correctly restored; treat as on-home
		if not _activate_derelict_from_instance(active, ws.player_position_in_ship):
			push_warning("PlayableGeneratedShip: world load — failed to re-activate derelict '%s'" % String(ws.current_location))
			return true
	return true
```

Note for the implementer: `ShipInstance.apply_summary` reconstructs `blueprint` (size/condition/seed) and `systems_manager` from the slice — that is why `_activate_derelict_from_instance` does not separately re-apply systems state. Confirm by reading `scripts/systems/ship_instance.gd` `apply_summary`.

- [ ] **Step 5: Rewire `request_save` and `request_load`**

Replace `request_save` (lines ~2563–2579) with:

```gdscript
## Manual save trigger (F5 / save_run input). Saves the whole world, so saving is
## allowed anywhere — including aboard a traveled derelict (save-anywhere; ADR-0012
## supersedes the Phase 4.5 away-save rejection). Refuses only before the slice has
## started or after it has completed.
func request_save() -> bool:
	if not playable_started or slice_complete:
		return false
	if save_load_service == null:
		return false
	var ws: WorldSnapshot = _build_world_snapshot()
	if ws == null:
		return false
	var result: bool = save_load_service.save_world(ws)
	if result:
		print("PLAYABLE SHIP SAVED location=%s sequence=%d" % [ws.current_location, current_objective_sequence])
	return result
```

Replace `request_load` (lines ~2601–2608) with:

```gdscript
## Manual load trigger (F9 / load_run input). Loads the whole world and applies it
## (home ship + visited-ship registry + active location + in-ship position).
func request_load() -> bool:
	if save_load_service == null:
		return false
	var ws: WorldSnapshot = save_load_service.load_world()
	if ws == null:
		push_warning("PlayableGeneratedShip: no compatible world save to load")
		return false
	return _apply_world_snapshot(ws)
```

- [ ] **Step 6: Update the superseded assertions in `travel_integration_smoke.gd`**

In `scripts/validation/travel_integration_smoke.gd`, the away-save block (step 10, lines ~205–209) asserts away-save is **blocked** — now superseded. Replace:

```gdscript
	# 10. save() is blocked while aboard a traveled derelict.
	var away_save: bool = playable.request_save()
	if away_save:
		_fail("request_save while away should return false (away-state save blocked)")
		return
```

with:

```gdscript
	# 10. save() while aboard a traveled derelict now SUCCEEDS (save-anywhere,
	# ADR-0012 supersedes the Phase 4.5 away-save rejection).
	var away_save: bool = playable.request_save()
	if not away_save:
		_fail("request_save while away should succeed (save-anywhere)")
		return
```

The reload-while-away block (steps 11–13) still holds: `request_load` now applies a world snapshot, but step 1's save (on the home ship) plus this step's away-save mean a compatible world save exists; the reload returns to the home ship and detaches the derelict. If step 12/13 fail after this change, the regression is real — fix it. (Do not weaken steps 11–13.)

- [ ] **Step 7: Run all three affected smokes to verify they pass**

Run each:
```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/world_save_anywhere_smoke.gd
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/travel_integration_smoke.gd
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/world_persist_restore_smoke.gd
```
Expected markers, no parse errors, exit 0:
- `WORLD SAVE ANYWHERE PASS away_save=true location_restored=true state_restored=true home_save=true`
- `TRAVEL INTEGRATION PASS start_wrapped=true scan_gated=true propulsion_gate=true swapped=true progression_persists=true world_recorded=true`
- `WORLD PERSIST RESTORE PASS registered=true state_preserved=true revisit_restores=true travel_home=true`

- [ ] **Step 8: Commit**

```bash
git add scripts/procgen/playable_generated_ship.gd scripts/validation/world_save_anywhere_smoke.gd scripts/validation/travel_integration_smoke.gd
git commit -m "feat(persistence): world save/load on coordinator (save-anywhere)"
```

---

### Task 5: ADR-0012 + register smokes in the validation plan

**Files:**
- Create: `docs/game/adr/0012-world-persistence-model.md`
- Modify: `docs/game/06_validation_plan.md`

**Interfaces:**
- Consumes: nothing in code; documents Tasks 1–4 and registers the three new smokes in the regression bundle.

- [ ] **Step 1: Write ADR-0012**

Create `docs/game/adr/0012-world-persistence-model.md`:

```markdown
# ADR-0012: World persistence model & save-anywhere

Date: 2026-06-21
Status: Accepted
Supersedes: the Phase 4.5 away-save rejection (ADR-0011 consequence) — saving is
now allowed aboard a traveled derelict.
Extends: ADR-0007 (single-ship RunSnapshot scope).
Related: docs/superpowers/specs/2026-06-21-world-persistence-foundation-design.md

## Context

Travel materialized derelicts statelessly (regenerated from seed, freed on leave;
ADR-0011) and the save model held exactly one ship (RunSnapshot; ADR-0007). The
target session loop needs every visited ship to persist (multi-visit, parts-gated
repair) and saving to work anywhere (Project-Zomboid style).

## Decision

Introduce `WorldSnapshot` (RefCounted, pure data): wraps the `Synaptic SeaWorld`
summary, the home ship's unchanged `RunSnapshot`, a `visited_ships` registry of
per-derelict slices keyed by `marker_id`, the `current_location`, and the in-ship
player position. The coordinator keeps a live `visited_ships: Dictionary` of
`ShipInstance`s; only the active ship has a live `scene_root`. Derelict geometry is
regenerated deterministically from seed on revisit; mutable state rides the
`ShipInstance` summaries (regenerate-geometry / persist-state).

`request_save`/`request_load` operate on the whole `WorldSnapshot` through
`SaveLoadService.save_world`/`load_world` (single slot, `current_run.json`).
`RunSnapshot` gains no fields (ADR-0007 honored); it is embedded whole.

## Consequences

- Saving is allowed anywhere, including aboard a derelict; the Phase 4.5 away-save
  rejection is removed.
- Old single-ship saves are version-incompatible under the new `WorldSnapshot`
  slice version and are rejected on load → fresh run (pre-release; no migration).
- The home ship keeps detach-not-free travel behavior; only derelicts take the
  free-and-rebuild path. Full unification (home as just another registry entry) is
  deferred.
- The per-ship slice is an extensible summary-bag: sub-project #2 (objectives/
  hazards), #3 (inventory/loot), and #4 (repair loop) add fields without reshaping
  the world model.
- Out of scope: autosave, multiple/named save slots, save-file migration.
```

- [ ] **Step 2: Register the three smokes in the validation bundle**

In `docs/game/06_validation_plan.md`, add the three new commands to the regression bundle (the bundle currently ends at `commands=61`; this makes it `commands=64`). Find the last registered `run_clean ... res://scripts/validation/scanner_panel_smoke.gd ...` entry and add after it (match the existing `run_clean` invocation style and expected-marker grep used by the surrounding entries):

```bash
run_clean "world_snapshot" "res://scripts/validation/world_snapshot_smoke.gd" "WORLD SNAPSHOT PASS round_trip=true version_gated=true"
run_clean "world_save_service" "res://scripts/validation/world_save_service_smoke.gd" "WORLD SAVE SERVICE PASS disk_round_trip=true rejects_null=true"
run_clean "world_persist_restore" "res://scripts/validation/world_persist_restore_smoke.gd" "WORLD PERSIST RESTORE PASS registered=true state_preserved=true revisit_restores=true travel_home=true"
run_clean "world_save_anywhere" "res://scripts/validation/world_save_anywhere_smoke.gd" "WORLD SAVE ANYWHERE PASS away_save=true location_restored=true state_restored=true home_save=true"
```

(That is four `run_clean` lines — `world_snapshot`, `world_save_service`, `world_persist_restore`, `world_save_anywhere` — taking the count from 61 to 65. Update the final success line's expected count accordingly: `SYNAPTIC_SEA REGRESSION PASS commands=65 clean_output=true`. Read the bundle's actual count line and increment by 4 from whatever it currently reads.)

- [ ] **Step 3: Update the allowlist for the new expected warning**

In `docs/game/06_validation_plan.md`, the `world_save_service` smoke deliberately exercises `save_world(null)`, which prints `WARNING: SaveLoadService: cannot save null world snapshot`. Add an allowlist entry beside the existing per-smoke allowlist notes (mirror the format of the `REQ012` save-rejection allowlist entry) so the clean-output gate ignores it. Also remove the now-obsolete `REQ012_AWAY_SAVE_WARNING` allowlist entry (away-save no longer warns — it succeeds); confirm by grepping the doc for `AWAY_SAVE`.

- [ ] **Step 4: Run the FULL regression bundle**

Run the bundle block from `docs/game/06_validation_plan.md` with the Windows `GODOT`/`ROOT` env values set (per CLAUDE.md). 
Expected final line: `SYNAPTIC_SEA REGRESSION PASS commands=65 clean_output=true` (or the correct incremented count), with no unexpected `ERROR:`/`WARNING:` lines.

- [ ] **Step 5: Run the automated Gate-1 playtest**

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/gate1_automated_playtest.gd
```
Expected: the Gate-1 PASS marker, no parse errors. (Persistence must not regress the single-ship slice.)

- [ ] **Step 6: Commit**

```bash
git add docs/game/adr/0012-world-persistence-model.md docs/game/06_validation_plan.md
git commit -m "docs(persistence): ADR-0012 + register world-persistence smokes (61->65)"
```

---

## Self-Review notes (for the executor)

- **Spec coverage:** WorldSnapshot (Task 1) ↔ spec "New top-level save object"; SaveLoadService world I/O (Task 2) ↔ spec "Save anywhere" file layer; visited-ships registry + persist-and-restore + travel_home (Task 3) ↔ spec "Travel becomes persist-and-restore" + "regenerate geometry, persist state"; world save/load + save-anywhere + superseded-smoke update (Task 4) ↔ spec "Save anywhere"; ADR-0012 + validation (Task 5) ↔ spec "ADR-0012" + "Validation". The three spec smokes map to `world_snapshot_smoke`/`world_save_service_smoke` (model), `world_persist_restore_smoke`, and `world_save_anywhere_smoke`.
- **Type consistency:** `WorldSnapshot` field names (`world_summary`, `home_ship`, `visited_ships`, `current_location`, `player_position_in_ship`) are identical across Tasks 1, 2, and 4. `WORLD_SLICE_VERSION` is referenced consistently. `_attach_derelict_active(inst, new_root)` is defined in Task 3 and reused in Task 4's `_activate_derelict_from_instance`.
- **Known coupling to verify during execution:** `_build_run_snapshot()` reads live `player.global_position`; Task 4 overrides the home slice position with `_home_player_position` when away — confirm `_home_player_position` is set on every home→derelict departure (Task 3, Step 5). `ShipInstance.apply_summary` must reconstruct both blueprint and systems_manager for `_activate_derelict_from_instance` to work without an explicit systems re-apply — verify against `scripts/systems/ship_instance.gd`.
```
