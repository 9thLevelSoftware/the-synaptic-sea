# Derelict Gameplay Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give a boarded derelict its own generated objective loop (salvage per-room + `reach_goal` extraction) that is interactable while aboard and whose progress persists per-derelict via the `ShipInstance` slice.

**Architecture:** A parallel derelict objective loop, separate from the entangled home-ship loop. A pure-logic `DerelictObjectiveController` composes the existing `ObjectiveProgressState` and adds `reach_goal`/`cleared` semantics. Each derelict `ShipInstance` owns a controller; its summary rides the slice the world-persistence foundation already serializes. The coordinator spawns the derelict's interactables from the active loader's specs, lifts the Phase 4.5 interaction-gate for the active derelict (NOT `_process` — #2 is input-driven), routes completion to the controller, and restores completed/cleared state on revisit.

**Tech Stack:** Godot 4.6.2, typed GDScript, headless `--script` validation smokes (each prints a single PASS marker line that is the contract).

## Global Constraints

- Godot binary (headless): `C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe`. Project root: `C:/Users/dasbl/Documents/The Synaptic Sea`.
- A smoke's **PASS marker line is the contract** — `--script` can exit 0 on parse errors, so confirm the marker is printed and no parse error / unexpected `ERROR:`/`WARNING:` appears. Allowlisted teardown noise: `ERROR: Capture not registered: 'gdaimcp'.` and `WARNING: ObjectDB instances leaked at exit`.
- **Model/Node separation:** `DerelictObjectiveController` is a pure `RefCounted` that never touches the scene tree (it composes `ObjectiveProgressState`). Scene-tree wiring stays in the coordinator.
- **Portability (class cache):** `DerelictObjectiveController` is a NEW `class_name` not in the committed `.godot` global class cache, and `--headless --script` does not rebuild it. Construct it via a `load()` self-reference factory (like `ShipInstance.create`), and reference it from other scripts via a `preload(...)` const (like `ShipInstanceScript`/`ObjectiveProgressStateScript`) — NEVER bare `DerelictObjectiveController.x` and NEVER a `: DerelictObjectiveController` annotation in another script. (`ObjectiveProgressState`, `ShipInstance`, `Interactable` are already referenced via preload consts in the code that uses them; keep that.)
- **Typed GDScript** for new code. Cross-script instance fields stay untyped where they hold another script's instance (matches `current_ship`, `systems_manager`).
- **Reuse, don't duplicate:** reuse `ObjectiveProgressState` (`scripts/systems/objective_progress_state.gd`), the `Interactable` node (`scripts/interaction/interactable.gd`), and `ObjectiveTracker.set_objectives`. Do not reimplement objective progress.
- **Derelict objective specs:** `current_ship.scene_root` is the active ship's `GeneratedShipLoader`. `get_objective_specs_copy()` returns each objective with a world-space `position: Vector3` already converted from `approach_cell` (loader line ~357), plus `id`, `sequence`, `type`, `room_id`, `kind: "single"`. The final objective has `id == "obj_reach_goal"`, `type == "interact"`; salvage objectives have `type == "salvage"`.
- **The home ship's loop must stay byte-for-byte behaviorally unchanged** — do not modify `_build_interactables`, `_on_interactable_completed`, `_process`, or the home tracker setup except where this plan explicitly says.
- **Selective `git add`** only (never `git add -A`); never stage `.godot/`, `*.uid`, or `addons/`. If a headless run rewrites `.godot/global_script_class_cache.cfg`, revert it before committing. Conventional Commits; trailer `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.

---

## File Structure

- **Create** `scripts/systems/derelict_objective_controller.gd` — pure-logic controller (Task 1).
- **Create** `scripts/validation/derelict_objective_controller_smoke.gd` — pure-model smoke (Task 1).
- **Modify** `scripts/systems/ship_instance.gd` — own a `DerelictObjectiveController`; round-trip it in `get_summary`/`apply_summary` (Task 2).
- **Modify** `scripts/validation/ship_instance_smoke.gd` — assert the objective round-trip (Task 2).
- **Modify** `scripts/procgen/playable_generated_ship.gd` — build/restore/free the derelict objective loop; lift the interaction gate; completion handler; tracker switch (Task 3).
- **Create** `scripts/validation/derelict_gameplay_smoke.gd` — main-scene smoke (Task 3).
- **Create** `docs/game/adr/0013-derelict-gameplay-parity.md` (Task 4).
- **Modify** `docs/game/06_validation_plan.md` — register 2 smokes (65 → 67) (Task 4).

---

### Task 1: `DerelictObjectiveController` (pure logic)

**Files:**
- Create: `scripts/systems/derelict_objective_controller.gd`
- Test: `scripts/validation/derelict_objective_controller_smoke.gd`

**Interfaces:**
- Consumes: `ObjectiveProgressState` (`register_objective(seq, type, required_steps)`, `complete_step(seq, step_id) -> bool`, `is_sequence_complete(seq) -> bool`, `get_summary()`, `apply_summary(dict) -> bool`).
- Produces:
  - `static create() -> DerelictObjectiveController` (via `load()` factory).
  - `configure(objective_specs: Array) -> void` — first-visit registration; idempotent (preserves progress if already configured).
  - `complete(sequence: int) -> bool` — completes a single-step objective; sets `cleared` when the `reach_goal` sequence completes.
  - `is_objective_complete(sequence: int) -> bool`, `is_cleared() -> bool`.
  - `get_summary() -> Dictionary` / `apply_summary(summary) -> bool`.

- [ ] **Step 1: Write the failing smoke**

Create `scripts/validation/derelict_objective_controller_smoke.gd`:

```gdscript
extends SceneTree

## Unit smoke for DerelictObjectiveController: configure from generated specs,
## complete salvage + reach_goal, cleared semantics, summary round-trip.

const ControllerScript := preload("res://scripts/systems/derelict_objective_controller.gd")

func _initialize() -> void:
	var specs: Array = [
		{"id": "obj_salvage_cargo_01", "sequence": 1, "type": "salvage", "kind": "single", "room_id": "cargo_01"},
		{"id": "obj_salvage_eng_01", "sequence": 2, "type": "salvage", "kind": "single", "room_id": "eng_01"},
		{"id": "obj_reach_goal", "sequence": 3, "type": "interact", "kind": "single", "room_id": "bridge_01"},
	]
	var c = ControllerScript.create()
	if c == null:
		_fail("create returned null")
		return
	c.configure(specs)
	if c.is_cleared():
		_fail("cleared should be false before reach_goal")
		return

	# Complete a salvage objective.
	if not c.complete(1):
		_fail("complete(1) should return true")
		return
	if not c.is_objective_complete(1):
		_fail("objective 1 should be complete")
		return
	if c.is_cleared():
		_fail("cleared should still be false after a salvage completion")
		return
	# Duplicate completion is idempotent (no double-credit).
	if c.complete(1):
		_fail("complete(1) again should return false (already complete)")
		return

	# Complete reach_goal -> cleared.
	if not c.complete(3):
		_fail("complete(3) reach_goal should return true")
		return
	if not c.is_cleared():
		_fail("cleared should be true after reach_goal completion")
		return

	# configure() is idempotent: a second call must NOT reset progress.
	c.configure(specs)
	if not c.is_objective_complete(1) or not c.is_cleared():
		_fail("configure() wiped progress (must be idempotent once configured)")
		return

	# Summary round-trip onto a fresh controller.
	var summary: Dictionary = c.get_summary()
	var restored = ControllerScript.create()
	if not restored.apply_summary(summary):
		_fail("apply_summary returned false")
		return
	if not restored.is_objective_complete(1):
		_fail("restored: objective 1 not complete")
		return
	if not restored.is_cleared():
		_fail("restored: cleared not preserved")
		return
	# A restored controller can still complete a remaining objective.
	if not restored.complete(2):
		_fail("restored: complete(2) should succeed")
		return
	if not restored.is_objective_complete(2):
		_fail("restored: objective 2 not complete after completion")
		return

	# apply_summary rejects null/empty.
	if restored.apply_summary(null) or restored.apply_summary({}):
		_fail("apply_summary should reject null/empty")
		return

	print("DERELICT OBJECTIVE CONTROLLER PASS configure=true cleared_on_goal=true round_trip=true")
	quit(0)

func _fail(reason: String) -> void:
	push_error("DERELICT OBJECTIVE CONTROLLER FAIL reason=%s" % reason)
	quit(1)
```

- [ ] **Step 2: Run the smoke to verify it fails**

Run:
```bash
GODOT="C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe"
ROOT="C:/Users/dasbl/Documents/The Synaptic Sea"
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/derelict_objective_controller_smoke.gd
```
Expected: parse/load error (`derelict_objective_controller.gd` does not exist) — no PASS marker.

- [ ] **Step 3: Implement the controller**

Create `scripts/systems/derelict_objective_controller.gd`:

```gdscript
extends RefCounted
class_name DerelictObjectiveController

## Pure-logic objective loop for a generated derelict. Composes ObjectiveProgressState
## (single-step objectives) and adds reach_goal / cleared semantics. Never touches the
## scene tree. Owned by a ShipInstance; its summary rides the per-ship slice.

const ObjectiveProgressStateScript := preload("res://scripts/systems/objective_progress_state.gd")
const REACH_GOAL_ID: String = "obj_reach_goal"
const STEP_ID: String = "done"  # single synthetic step per single-objective

var progress                       # ObjectiveProgressState
var reach_goal_sequence: int = 0
var cleared: bool = false

# Static factory via load() self-reference (class_name globals unreliable under
# --headless --script; matches ShipInstance.create).
static func create() -> DerelictObjectiveController:
	var script: GDScript = load("res://scripts/systems/derelict_objective_controller.gd")
	var c: DerelictObjectiveController = script.new()
	c.progress = ObjectiveProgressStateScript.new()
	return c

## True once the objective set has been registered (or restored).
func is_configured() -> bool:
	return reach_goal_sequence != 0 or not progress.get_summary().is_empty()

## Registers the generated objective set. First-visit only: idempotent once configured
## so re-boarding a derelict (or building interactables after a restore) preserves progress.
func configure(objective_specs: Array) -> void:
	if is_configured():
		return
	for spec_variant in objective_specs:
		if typeof(spec_variant) != TYPE_DICTIONARY:
			continue
		var spec: Dictionary = spec_variant
		var sequence: int = int(spec.get("sequence", 0))
		if sequence <= 0:
			continue
		progress.register_objective(sequence, str(spec.get("type", "objective")), 1)
		if str(spec.get("id", "")) == REACH_GOAL_ID:
			reach_goal_sequence = sequence

## Completes a single-step objective by sequence. Returns true if newly completed.
## Sets `cleared` when the reach_goal sequence becomes complete.
func complete(sequence: int) -> bool:
	if progress == null:
		return false
	var changed: bool = progress.complete_step(sequence, STEP_ID)
	if reach_goal_sequence != 0 and progress.is_sequence_complete(reach_goal_sequence):
		cleared = true
	return changed

func is_objective_complete(sequence: int) -> bool:
	return progress != null and progress.is_sequence_complete(sequence)

func is_cleared() -> bool:
	return cleared

func get_summary() -> Dictionary:
	return {
		"progress": progress.get_summary() if progress != null else {},
		"reach_goal_sequence": reach_goal_sequence,
		"cleared": cleared,
	}

func apply_summary(summary) -> bool:
	if typeof(summary) != TYPE_DICTIONARY or (summary as Dictionary).is_empty():
		return false
	if progress == null:
		progress = ObjectiveProgressStateScript.new()
	var prog: Variant = summary.get("progress", {})
	if typeof(prog) == TYPE_DICTIONARY and not (prog as Dictionary).is_empty():
		progress.apply_summary(prog as Dictionary)
	reach_goal_sequence = int(summary.get("reach_goal_sequence", 0))
	cleared = bool(summary.get("cleared", false))
	return true
```

- [ ] **Step 4: Run the smoke to verify it passes**

Run the Step 2 command.
Expected: `DERELICT OBJECTIVE CONTROLLER PASS configure=true cleared_on_goal=true round_trip=true`, no parse error, exit 0.

- [ ] **Step 5: Commit**

```bash
git add scripts/systems/derelict_objective_controller.gd scripts/validation/derelict_objective_controller_smoke.gd
git commit -m "feat(derelict): add DerelictObjectiveController + model smoke"
```

---

### Task 2: `ShipInstance` owns the objective controller

**Files:**
- Modify: `scripts/systems/ship_instance.gd`
- Test: `scripts/validation/ship_instance_smoke.gd`

**Interfaces:**
- Consumes: Task 1 `DerelictObjectiveController` (`create()`, `get_summary()`, `apply_summary()`).
- Produces on `ShipInstance`:
  - `var objective_controller = null` (untyped; lazily created).
  - `get_objective_controller()` — returns the controller, creating it on first call.
  - `get_summary()` gains `"objective"` = controller summary (only when a controller exists); `apply_summary()` restores it.

- [ ] **Step 1: Write the failing test (extend the existing smoke)**

In `scripts/validation/ship_instance_smoke.gd`, add — immediately before the final `print("SHIP INSTANCE PASS ...")` line — an objective round-trip block:

```gdscript
	# Sub-project #2: ShipInstance carries a DerelictObjectiveController whose
	# state round-trips through get_summary / apply_summary.
	var controller = inst.get_objective_controller()
	if controller == null:
		_fail("get_objective_controller returned null")
		return
	controller.configure([
		{"id": "obj_salvage_a", "sequence": 1, "type": "salvage", "kind": "single", "room_id": "a"},
		{"id": "obj_reach_goal", "sequence": 2, "type": "interact", "kind": "single", "room_id": "b"},
	])
	controller.complete(1)
	controller.complete(2)
	if not controller.is_cleared():
		_fail("controller should be cleared after reach_goal")
		return
	var full_summary: Dictionary = inst.get_summary()
	if not full_summary.has("objective"):
		_fail("get_summary missing 'objective' key when a controller exists")
		return
	var rebuilt2 = ShipInstanceScript.create("", "", ShipBlueprintScript.new(), ShipSystemsManagerScript.new(), null)
	if not rebuilt2.apply_summary(full_summary):
		_fail("apply_summary returned false for objective-bearing summary")
		return
	var rebuilt_controller = rebuilt2.get_objective_controller()
	if not rebuilt_controller.is_objective_complete(1) or not rebuilt_controller.is_cleared():
		_fail("apply_summary did not restore derelict objective progress / cleared")
		return
```

Then change the existing PASS marker line to:
```gdscript
	print("SHIP INSTANCE PASS round_trip=true stubs_present=true objective_round_trip=true")
```

- [ ] **Step 2: Run the smoke to verify it fails**

Run:
```bash
GODOT="C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe"
ROOT="C:/Users/dasbl/Documents/The Synaptic Sea"
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ship_instance_smoke.gd
```
Expected: FAIL — `get_objective_controller` does not exist / `get_summary` has no `"objective"` key. No PASS marker.

- [ ] **Step 3: Implement the ShipInstance extension**

In `scripts/systems/ship_instance.gd`:

(a) Add a preload const beside the existing ones (after `const ShipSystemsManagerScript := ...`):
```gdscript
const DerelictObjectiveControllerScript := preload("res://scripts/systems/derelict_objective_controller.gd")
```

(b) Add the field beside the Phase 5 stubs (after `var docking_ports: Array = []`):
```gdscript
# Sub-project #2: per-derelict objective loop state. Lazily created; null for the
# home ship (which uses the coordinator's singleton loop, not this controller).
var objective_controller = null          # DerelictObjectiveController | null
```

(c) Add the lazy getter (anywhere after `apply_summary`):
```gdscript
## Returns this ship's DerelictObjectiveController, creating it on first access.
func get_objective_controller():
	if objective_controller == null:
		objective_controller = DerelictObjectiveControllerScript.create()
	return objective_controller
```

(d) In `get_summary()`, before the final `return {...}`, build the objective entry and include it ONLY when a controller exists (so the home ship's summary is unchanged):
```gdscript
	var result: Dictionary = {
		"ship_id": ship_id,
		"marker_id": marker_id,
		"blueprint": bp_dict,
		"systems": sys_dict,
	}
	if objective_controller != null:
		result["objective"] = objective_controller.get_summary()
	return result
```
(Replace the existing `return { ... }` dictionary literal with the `var result` form above.)

(e) In `apply_summary()`, before `return true`, restore the controller when present:
```gdscript
	var obj_summary: Variant = summary.get("objective", null)
	if typeof(obj_summary) == TYPE_DICTIONARY and not (obj_summary as Dictionary).is_empty():
		if objective_controller == null:
			objective_controller = DerelictObjectiveControllerScript.create()
		objective_controller.apply_summary(obj_summary as Dictionary)
```

- [ ] **Step 4: Run the smoke to verify it passes**

Run the Step 2 command.
Expected: `SHIP INSTANCE PASS round_trip=true stubs_present=true objective_round_trip=true`, no parse error, exit 0.

- [ ] **Step 5: Commit**

```bash
git add scripts/systems/ship_instance.gd scripts/validation/ship_instance_smoke.gd
git commit -m "feat(derelict): ShipInstance owns the derelict objective controller"
```

---

### Task 3: Coordinator — build, run, persist, restore the derelict objective loop

**Files:**
- Modify: `scripts/procgen/playable_generated_ship.gd`
- Test: `scripts/validation/derelict_gameplay_smoke.gd`

**Interfaces:**
- Consumes: `current_ship.get_objective_controller()` (Task 2); `current_ship.scene_root.get_objective_specs_copy()`; `InteractableScript` (already preloaded) with `configure_from_objective(spec, position, radius)`, `interaction_completed` signal, `try_interact(player) -> bool`, `set_active(bool)`, `set_validation_player_in_range(player)`, fields `sequence`/`completed`; `_attach_derelict_active`, `travel_home`, `away_from_start`, `tracker.set_objectives(...)`, `loader.get_objective_specs_copy()`, `player`.
- Produces on the coordinator: `var derelict_objective_root: Node3D`, `var derelict_interactables: Array = []`; `_build_derelict_objectives()`, `_clear_derelict_objectives()`, `_on_derelict_interactable_completed(...)`, `complete_derelict_objective_for_validation(sequence) -> bool`.

- [ ] **Step 1: Write the failing main-scene smoke**

Create `scripts/validation/derelict_gameplay_smoke.gd`:

```gdscript
extends SceneTree

## Main-scene smoke: a boarded derelict runs its own objective loop, completion
## clears it, progress persists across leave/revisit, and the home loop is intact.

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
		for sub in sys.subcomponents:
			mgr.force_repair(sid, sub.subcomponent_id)

func _validate(playable: PlayableGeneratedShip) -> void:
	var home_sequence_before: int = playable.get_current_objective_sequence()
	_all_operational(playable.get_ship_systems_manager())

	# Board a derelict.
	var world = playable.get_synapse_sea_world()
	var in_range: Array = world.markers_in_range(playable.scanner_state.range_radius)
	if in_range.is_empty():
		_fail("no markers in range")
		return
	var marker_id: String = String(in_range[0].marker_id)
	if not bool(playable.travel_to_marker_id(marker_id).get("success", false)):
		_fail("travel to derelict failed")
		return

	# Derelict objectives were built and are interactable while aboard.
	if playable.derelict_interactables.is_empty():
		_fail("no derelict objective interactables built on board")
		return
	var controller = playable.get_current_ship().get_objective_controller()
	if controller == null or controller.is_cleared():
		_fail("fresh derelict controller missing or already cleared")
		return

	# Complete every derelict objective through the real interaction path.
	var sequences: Array = []
	for it in playable.derelict_interactables:
		if not sequences.has(int(it.sequence)):
			sequences.append(int(it.sequence))
	sequences.sort()
	for seq in sequences:
		if not playable.complete_derelict_objective_for_validation(seq):
			_fail("could not complete derelict objective sequence %d" % seq)
			return
	if not controller.is_cleared():
		_fail("derelict not cleared after completing all objectives (incl. reach_goal)")
		return

	# Leave to home, then revisit: progress + cleared must be restored, and the
	# rebuilt interactables for completed objectives must read as completed.
	if not playable.travel_home():
		_fail("travel_home failed")
		return
	if not bool(playable.travel_to_marker_id(marker_id).get("success", false)):
		_fail("revisit travel failed")
		return
	var controller2 = playable.get_current_ship().get_objective_controller()
	if not controller2.is_cleared():
		_fail("cleared state not preserved across revisit")
		return
	if playable.derelict_interactables.is_empty():
		_fail("revisit rebuilt no derelict interactables")
		return
	for it in playable.derelict_interactables:
		if not it.completed:
			_fail("revisit: a previously-completed derelict interactable is not marked completed (respawned)")
			return

	# Home loop intact: return home and confirm the home objective sequence is unchanged.
	if not playable.travel_home():
		_fail("second travel_home failed")
		return
	if playable.away_from_start:
		_fail("away_from_start still true after returning home")
		return
	if playable.get_current_objective_sequence() != home_sequence_before:
		_fail("home objective sequence changed (home loop disturbed)")
		return

	finished = true
	print("DERELICT GAMEPLAY PASS built=true cleared=true persists=true home_intact=true")
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
	push_error("DERELICT GAMEPLAY FAIL reason=%s" % reason)
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
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/derelict_gameplay_smoke.gd
```
Expected: FAIL — `derelict_interactables` / `complete_derelict_objective_for_validation` do not exist. No PASS marker.

- [ ] **Step 3: Add the derelict objective fields + root**

In `scripts/procgen/playable_generated_ship.gd`, near the `visited_ships`/`home_ship` fields (added in sub-project #1, around line 126), add:
```gdscript
# Sub-project #2: the active derelict's objective interactables live under a
# dedicated root (empty while on the home ship). Separate from the home gameplay
# roots so it stays attached when away_from_start.
var derelict_objective_root: Node3D = null
var derelict_interactables: Array = []
```

In `_build_runtime_nodes()`, after the other `*_root` nodes are created and added (e.g. after `arc_root` is added), create the derelict root:
```gdscript
	derelict_objective_root = Node3D.new()
	derelict_objective_root.name = "DerelictObjectiveRoot"
	add_child(derelict_objective_root)
```

- [ ] **Step 4: Add the build / clear / completion methods**

Add these methods to the coordinator (e.g. just after `_attach_derelict_active`):

```gdscript
## Builds the active derelict's objective interactables from its loader specs and
## restores completed/cleared state from its (retained or loaded) controller. Called
## whenever a derelict becomes active. No-op on the home ship.
func _build_derelict_objectives() -> void:
	_clear_derelict_objectives()
	if current_ship == null or String(current_ship.marker_id) == "":
		return
	var active_loader = current_ship.scene_root
	if active_loader == null or not active_loader.has_method("get_objective_specs_copy"):
		return
	var specs: Array = active_loader.get_objective_specs_copy()
	var controller = current_ship.get_objective_controller()
	# First visit registers the set; a retained/restored controller is already
	# configured, so this is a no-op that preserves progress.
	controller.configure(specs)
	for spec_variant in specs:
		if typeof(spec_variant) != TYPE_DICTIONARY:
			continue
		var spec: Dictionary = spec_variant
		var sequence: int = int(spec.get("sequence", 0))
		if sequence <= 0:
			continue
		var position_variant: Variant = spec.get("position", Vector3.INF)
		if typeof(position_variant) != TYPE_VECTOR3:
			continue
		var interactable = InteractableScript.new()
		interactable.configure_from_objective(spec, position_variant, 1.8)
		interactable.interaction_completed.connect(_on_derelict_interactable_completed)
		# Restore: a persisted-complete objective reads as done and cannot be re-fired
		# (try_interact returns false when completed).
		if controller.is_objective_complete(sequence):
			interactable.completed = true
			interactable.set_active(false)
		derelict_objective_root.add_child(interactable)
		derelict_interactables.append(interactable)
	# Show the derelict's objectives in the HUD while aboard.
	if tracker != null:
		tracker.set_objectives(specs)

## Frees the active derelict's interactables. The controller (state) lives on the
## ShipInstance and is untouched.
func _clear_derelict_objectives() -> void:
	if derelict_objective_root != null:
		for child in derelict_objective_root.get_children():
			derelict_objective_root.remove_child(child)
			child.queue_free()
	derelict_interactables.clear()

## Routes a derelict interactable completion to the active ship's controller.
func _on_derelict_interactable_completed(interaction_id: String, objective_id: String, sequence: int, objective_type: String, room_id: String, step_id: String) -> void:
	if current_ship == null:
		return
	var controller = current_ship.get_objective_controller()
	controller.complete(sequence)
	print("DERELICT OBJECTIVE COMPLETE marker=%s sequence=%d type=%s cleared=%s" % [
		String(current_ship.marker_id), sequence, objective_type, str(controller.is_cleared()).to_lower()])

## Validation seam: complete a derelict objective by sequence through the real
## interaction path (bypassing proximity via set_validation_player_in_range).
func complete_derelict_objective_for_validation(sequence: int) -> bool:
	for it in derelict_interactables:
		if int(it.sequence) == sequence and not it.completed:
			it.set_validation_player_in_range(player)
			return it.try_interact(player)
	return false
```

- [ ] **Step 5: Build derelict objectives when a derelict becomes active**

In `_attach_derelict_active(inst, new_root)`, add a call to build the derelict loop as the LAST line of the function (after `away_from_start = true`):
```gdscript
	_build_derelict_objectives()
```
This covers both the `travel_to` path and the world-load `_activate_derelict_from_instance` path (both route through `_attach_derelict_active`), so the loop is built and restored consistently.

- [ ] **Step 6: Lift the interaction gate for the active derelict**

In `_on_player_interact_requested`, replace the existing away-gate:
```gdscript
	if away_from_start:
		return
```
with:
```gdscript
	if away_from_start:
		# Sub-project #2: the boarded derelict has its own objective interactables.
		for it in derelict_interactables:
			if it.try_interact(player_body):
				return
		return
```

- [ ] **Step 7: Clear the derelict loop and restore the home HUD on travel_home**

In `travel_home()`, after the derelict scene is freed and before/with the gameplay-root reattachment (i.e. once `current_ship = home_ship` and `away_from_start = false` are set), add:
```gdscript
	_clear_derelict_objectives()
	if tracker != null and loader != null and loader.has_method("get_objective_specs_copy"):
		tracker.set_objectives(loader.get_objective_specs_copy())
```

- [ ] **Step 8: Run the main-scene smoke to verify it passes**

Run the Step 2 command.
Expected: `DERELICT GAMEPLAY PASS built=true cleared=true persists=true home_intact=true`, plus `DERELICT OBJECTIVE COMPLETE ...` lines, no parse error, exit 0.

- [ ] **Step 9: Regression-guard the persistence + travel smokes**

Run each and confirm the existing markers still print (the derelict loop must not disturb world-persistence or travel):
```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/world_persist_restore_smoke.gd
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/world_save_anywhere_smoke.gd
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/travel_integration_smoke.gd
```
Expected: `WORLD PERSIST RESTORE PASS ...`, `WORLD SAVE ANYWHERE PASS ...`, `TRAVEL INTEGRATION PASS ...`, all with zero unexpected `ERROR:`/`WARNING:` (especially zero `RID allocations`/`Leaked instance` leak lines — the derelict interactables must be freed on leave by `_clear_derelict_objectives` and by the travel smoke teardown). If a leak appears, the derelict interactables are not being freed on a leave path — fix `_clear_derelict_objectives` coverage before committing.

- [ ] **Step 10: Commit**

```bash
git add scripts/procgen/playable_generated_ship.gd scripts/validation/derelict_gameplay_smoke.gd
git commit -m "feat(derelict): build/run/persist the boarded-derelict objective loop"
```

---

### Task 4: ADR-0013 + register smokes in the validation bundle

**Files:**
- Create: `docs/game/adr/0013-derelict-gameplay-parity.md`
- Modify: `docs/game/06_validation_plan.md`

**Interfaces:** docs + bundle registration only.

- [ ] **Step 1: Write ADR-0013**

Create `docs/game/adr/0013-derelict-gameplay-parity.md`:

```markdown
# ADR-0013: Derelict gameplay parity (parallel objective loop)

Date: 2026-06-21
Status: Accepted
Related: ADR-0011 (ShipInstance & travel), ADR-0012 (world persistence),
docs/superpowers/specs/2026-06-21-derelict-gameplay-parity-design.md

## Context

Sub-project #1 made visited ships persist, but a boarded derelict was a bare hull
(`_process` early-returns when `away_from_start`). The rich objective loop lived only on
the home ship and is entangled with reactor/extraction and junction_calibrator specifics.

## Decision

Give a boarded derelict a PARALLEL objective loop rather than swapping the home singletons.
A pure-logic `DerelictObjectiveController` composes `ObjectiveProgressState` and adds
`reach_goal`/`cleared` semantics. Each derelict `ShipInstance` owns a controller; its summary
rides the per-ship slice (ADR-0012), so objective progress + `cleared` persist across
leave/return and save/load for free. The coordinator spawns the derelict's interactables
(from the active loader's generated specs) under a dedicated `DerelictObjectiveRoot`, lifts
the Phase 4.5 interaction-gate for the active derelict, and routes completion to the
controller.

`reach_goal` IS the derelict's extraction (there is no reactor path on a derelict).

## Consequences

- Because #2 is objectives-only and input-driven (`Interactable` is an `Area3D`, no per-frame
  work), only the `_on_player_interact_requested` away-gate is lifted; the `_process`
  per-frame freeze stays. The `_process` freeze-lift moves to #2b, when derelict hazards
  add per-frame ticking.
- The home loop is untouched (its singletons, reactor extraction, and HUD behave exactly as
  before, including after travelling out and back).
- Completing a derelict yields the persisted `cleared` state only; the tangible reward
  (loot/parts) is deferred to sub-project #3 (player inventory).
- Completed salvage objectives do not respawn on revisit; a cleared derelict reads as cleared
  across revisit and quit→resume.
```

- [ ] **Step 2: Register the two smokes in the bundle**

In `docs/game/06_validation_plan.md`, add two `run_clean` lines immediately after the last
`run_clean` entry (the world-persistence block ends with `world save anywhere smoke`), using
the live bundle's exact `run_clean '<label>' '<MARKER>' "$GODOT" --headless --path "$ROOT" --script res://...` signature:
```bash
run_clean 'derelict objective controller smoke' 'DERELICT OBJECTIVE CONTROLLER PASS configure=true cleared_on_goal=true round_trip=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/derelict_objective_controller_smoke.gd
run_clean 'derelict gameplay smoke' 'DERELICT GAMEPLAY PASS built=true cleared=true persists=true home_intact=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/derelict_gameplay_smoke.gd
```
Then change the success line `echo 'SYNAPSE_SEA REGRESSION PASS commands=65 clean_output=true'` from `commands=65` to `commands=67`. (Read the actual current count line and increment by 2.)

- [ ] **Step 3: Run the FULL regression bundle**

Set env and run the bundle block from `docs/game/06_validation_plan.md`:
```bash
export GODOT="C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe"
export ROOT="C:/Users/dasbl/Documents/The Synaptic Sea"
```
Expected final line: `SYNAPSE_SEA REGRESSION PASS commands=67 clean_output=true`, with no unexpected `ERROR:`/`WARNING:` lines. If any smoke fails or unexpected noise appears, STOP and report the exact line — do not paper over it (no new allowlist entries without a root-cause justification).

- [ ] **Step 4: Run the Gate-1 automated playtest**

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/gate1_automated_playtest.gd
```
Expected: `GATE 1 AUTOMATED PLAYTEST PASS`, no parse error. (The home single-ship slice must be unaffected.)

- [ ] **Step 5: Commit**

```bash
git add docs/game/adr/0013-derelict-gameplay-parity.md docs/game/06_validation_plan.md
git commit -m "docs(derelict): ADR-0013 + register derelict-gameplay smokes (65->67)"
```

---

## Self-Review notes (for the executor)

- **Spec coverage:** DerelictObjectiveController (Task 1) ↔ spec "derelict objective controller (pure logic)"; ShipInstance ownership (Task 2) ↔ spec "per-ship persistence (slice extension)"; coordinator build/gate/complete/restore/HUD (Task 3) ↔ spec "Architecture" + "Lifecycle" + "HUD & interaction"; ADR + validation (Task 4) ↔ spec "Validation". The two spec smokes map to `derelict_objective_controller_smoke` (pure) and `derelict_gameplay_smoke` (main-scene).
- **Type consistency:** `DerelictObjectiveController` API names (`create`, `configure`, `complete`, `is_objective_complete`, `is_cleared`, `get_summary`, `apply_summary`) are identical across Tasks 1, 2, 3. `get_objective_controller()` defined in Task 2, consumed in Task 3. `derelict_interactables`/`derelict_objective_root` defined and used consistently in Task 3.
- **Couplings to verify during execution:** (1) `_attach_derelict_active` exists and is the single choke point both travel and world-load route through — confirm before relying on Step 5. (2) `current_ship.scene_root` is the active `GeneratedShipLoader` with `get_objective_specs_copy()` returning specs that include a `Vector3 position`. (3) `configure()` idempotence is what preserves restored progress when `_build_derelict_objectives` runs after a load — the Task 1 smoke asserts this; if a restored controller were re-`configure()`d destructively, revisit would wipe progress. (4) `_clear_derelict_objectives` must run on every leave path (it runs inside `_build_derelict_objectives` for derelict→derelict, and is added to `travel_home` for derelict→home) — Step 9 leak-guards this.
```
