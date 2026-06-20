# Repair-Junction Objective Implementation Plan (REQ-011)

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add one multi-step objective kind, `repair_junction`, to the Gate 2 main playable slice. The junction occupies a single sequence slot but requires two independent interactions in the same room before `ShipSystemState.apply_objective()` fires exactly once and route-control / extraction state advances per existing rules.

**Architecture:** Add a pure `ObjectiveProgressState` model beside `ShipSystemState` and `RouteControlState`. Extend `GeneratedShipLoader` objective parsing with optional `kind` and `steps` fields. Extend `Interactable` to carry a `step_id`. In `PlayableGeneratedShip`, build one `Interactable` per step for `repair_junction` objectives, group them by sequence, and route each step completion through `ObjectiveProgressState.complete_step()` so the sequence advances and `ShipSystemState.apply_objective()` is called only after the last required step. Update `ObjectiveTracker` to show `Repair junction (1/2)` / `Repair junction (2/2)` progress. Keep single-step objectives unchanged.

**Tech Stack:** Godot 4.6.2 GDScript, `SceneTree` validation smokes, existing `res://scenes/main.tscn`, existing `PlayableGeneratedShip`, existing `GeneratedShipLoader`, existing `Interactable`, existing `ObjectiveTracker`, existing `ShipSystemState`, no external runtime dependencies.

## Global Constraints

- Project root: `/Users/christopherwilloughby/the-sargasso-of-stars`.
- Godot binary: `/Users/christopherwilloughby/.local/bin/godot-4.6.2`.
- Workspace state checked on 2026-06-19: `GIT_INSIDE=false`.
- Cite REQ-011 (`docs/game/05_requirements.md` lines 176-191) and `docs/game/features/objective_variation.md` as the authoritative feature spec.
- Preserve REQ-001, REQ-002, REQ-003, REQ-004, REQ-006, and REQ-007 behavior; do not alter route/extraction rules, ship-system flag semantics, or hazard/tool loops.
- `ShipSystemState.apply_objective()` must fire exactly once per sequence, even for multi-step objectives.
- The `type` field continues to name the ship-system effect (`recover_supplies`, `restore_systems`, `download_logs`, `stabilize_reactor`). A new optional `kind` field distinguishes multi-step layout (`repair_junction`); missing/empty `kind` means single-step, preserving backward compatibility.
- Gate 2 uses exactly one `repair_junction` slot with exactly two steps. The chosen sequence is sequence 2 in `data/procgen/smoke/seed_000017/gameplay_slice.json`, replacing the previous single-step `restore_systems` objective but keeping `type = "restore_systems"` so REQ-002 route-gate behavior is unchanged.
- Steps are unordered; completing either first counts as step 1.
- Completed step interactables become no-ops and remain visually distinct (the existing `completed` marker material already does this).
- Do not implement a full procedural objective generator, objective graph, branching paths, optional alternate sequences, failure/timer/wrong-order penalty, new ship-system flags, audio/VFX polish, or hub/meta progression.
- Do not create HTML, PNG, contact sheets, screenshot galleries, or proof documents for this milestone.
- Output from validation commands must be clean of unexpected lines beginning with `ERROR:` or `WARNING:`.
- Because this is not a git repository, every task uses the no-git ledger fallback at `/tmp/sargasso_repair_junction_no_git_changes.log` instead of assuming `git commit` works.
- Existing validation seams (`complete_objective_sequence_for_validation`, `complete_all_objectives_for_validation`, `complete_first_interaction_for_validation`) must keep working, and all pre-existing smokes in `docs/game/06_validation_plan.md` must continue to pass.

---

## File Structure

Create:

- `scripts/systems/objective_progress_state.gd`
  - Pure runtime model for per-sequence step completion.
  - Extends `RefCounted`, `class_name ObjectiveProgressState`.
  - No scene-tree access.
  - Methods: `register_objective(sequence, objective_type, required_steps)`, `complete_step(sequence, step_id)`, `is_sequence_complete(sequence)`, `get_step_progress(sequence)`, `get_summary()`, `reset()`.
  - `get_summary()` returns `{ sequence: { "objective_type": ..., "required_steps": ..., "completed_steps": ..., "completed_step_ids": [...], "complete": ... } }`.

- `scripts/validation/objective_progress_state_smoke.gd`
  - Direct model smoke.
  - Registers a 2-step `repair_junction` at sequence 2, completes steps out of order, asserts the sequence is not complete after one step, asserts completion after the second step, and asserts `apply_objective()` would be called exactly once.
  - Pass marker: `OBJECTIVE PROGRESS STATE PASS sequence=2 required=2 completed=2 applied_once=true`.

- `scripts/validation/main_playable_slice_objective_variation_smoke.gd`
  - Main-scene runtime smoke.
  - Loads `main.tscn`, asserts sequence 2 is a `repair_junction` with two step interactables, completes both steps, asserts `ShipSystemState.apply_objective()` ran once (power restored, gates opened), and asserts extraction unlocks after sequence 4.
  - Pass marker: `MAIN PLAYABLE OBJECTIVE VARIATION PASS sequence=2 steps=2 complete=true power_restored=true gates_opened=true`.

Modify:

- `scripts/interaction/interactable.gd`
  - Add `step_id: String = ""` and `is_step: bool = false`.
  - Add `configure_from_step(objective: Dictionary, step: Dictionary, world_position: Vector3, radius := 1.8)`.
  - Update `interaction_completed` signal to include `step_id` as the final parameter: `interaction_completed(interaction_id, objective_id, sequence, objective_type, room_id, step_id)`.
  - Keep `configure_from_objective` unchanged for single-step objectives.

- `scripts/procgen/generated_ship_loader.gd`
  - In `_build_objective_specs`, read optional `kind` (default `"single"`) and optional `steps` array.
  - If `kind == "repair_junction"` and `steps` is non-empty, validate each step has an `approach_cell` or inherit the objective's `approach_cell`, compute step world positions, and append a `steps` array to the returned objective spec.
  - Reject duplicate `step_id` values within the same objective.

- `scripts/procgen/playable_generated_ship.gd`
  - Preload and own `ObjectiveProgressState`.
  - Replace the flat `interactables` list handling with sequence grouping:
    - Build a `sequence_interactables: Dictionary` mapping `sequence -> Array[Interactable]`.
    - For single-step objectives, group remains size 1.
    - For `repair_junction`, create one `Interactable` per step with `configure_from_step`, all sharing the same `sequence` and `objective_type` but distinct `step_id` and position.
  - Register each multi-step sequence with `objective_progress_state.register_objective(sequence, objective_type, required_steps)`.
  - In `_on_interactable_completed`, if the sequence is multi-step:
    - Call `objective_progress_state.complete_step(sequence, step_id)`.
    - If the sequence is not yet complete, update the objective tracker with per-step progress and return early (do not advance `current_objective_sequence`, do not call `ShipSystemState.apply_objective()`).
    - If the sequence just completed, continue with the existing single-step completion path exactly once.
  - In `_activate_current_objective`, activate all interactables for the current sequence (handles multi-step).
  - Update `get_interactable_by_sequence` to return the first interactable of the group.
  - Add helper `get_objective_progress_summary() -> Dictionary`.
  - Update validation seams (`complete_objective_sequence_for_validation`, `complete_all_objectives_for_validation`) to work with the first interactable of a sequence group.

- `scripts/ui/objective_tracker.gd`
  - Add `current_step_progress: Dictionary = {}` with optional `required_steps` and `completed_steps`.
  - Add `set_step_progress(sequence: int, progress: Dictionary)`.
  - Update `_current_objective_display` to print `"Repair junction (1/2) @ room"` when step progress exists.
  - Keep single-step display unchanged.

- `data/procgen/smoke/seed_000017/gameplay_slice.json`
  - Replace the sequence-2 objective with a `repair_junction` entry:
    - `id`: `"maintenance_01:junction_alpha"`
    - `sequence`: 2
    - `type`: `"restore_systems"`
    - `kind`: `"repair_junction"`
    - `room_id`: `"maintenance_01"`
    - `approach_cell`: inherited or set to a valid floor cell in `maintenance_01`
    - `steps`: two entries with `step_id` (`primary_coupling`, `secondary_coupling`) and `approach_cell` values that resolve to valid floor placements in `maintenance_01`

- `docs/game/06_validation_plan.md`
  - Add `objective_progress_state_smoke.gd` and `main_playable_slice_objective_variation_smoke.gd` to the regression bundle and remove them from the "Future validation additions" list.

Generated by Godot if import/class registration runs:

- `scripts/systems/objective_progress_state.gd.uid`
  - Accept this sidecar if Godot creates it.
  - Record it in the no-git ledger.

---

### Task 1: Objective Progress Model Smoke, RED Phase

**Files:**
- Create: `scripts/validation/objective_progress_state_smoke.gd`
- Read: `scripts/validation/route_control_state_smoke.gd` (template)

**Interfaces:**
- Consumes intended future class: `ObjectiveProgressState.new()`.
- Consumes intended future methods:
  - `register_objective(sequence: int, objective_type: String, required_steps: int)`
  - `complete_step(sequence: int, step_id: String) -> bool`
  - `is_sequence_complete(sequence: int) -> bool`
  - `get_step_progress(sequence: int) -> Dictionary`
  - `get_summary() -> Dictionary`
- Produces a failing model smoke with pass marker:
  - `OBJECTIVE PROGRESS STATE PASS sequence=2 required=2 completed=2 applied_once=true`

- [ ] **Step 1: Create the failing model smoke**

Write `scripts/validation/objective_progress_state_smoke.gd` with this complete content:

```gdscript
extends SceneTree

func _initialize() -> void:
	var model := ObjectiveProgressState.new()

	# Register a 2-step repair junction at sequence 2.
	model.register_objective(2, "restore_systems", 2)

	var initial: Dictionary = model.get_step_progress(2)
	if int(initial.get("required_steps", -1)) != 2:
		_fail("initial required_steps should be 2, got %s" % str(initial.get("required_steps", -1)))
		return
	if int(initial.get("completed_steps", -1)) != 0:
		_fail("initial completed_steps should be 0, got %s" % str(initial.get("completed_steps", -1)))
		return
	if bool(initial.get("complete", true)):
		_fail("initial complete should be false")
		return

	# Complete first step out of order.
	var first_changed: bool = model.complete_step(2, "secondary_coupling")
	if not first_changed:
		_fail("first complete_step should report changed")
		return
	if model.is_sequence_complete(2):
		_fail("sequence should not be complete after one step")
		return
	var after_one: Dictionary = model.get_step_progress(2)
	if int(after_one.get("completed_steps", -1)) != 1:
		_fail("completed_steps should be 1 after first step, got %s" % str(after_one.get("completed_steps", -1)))
		return
	if bool(after_one.get("complete", true)):
		_fail("complete should still be false after one step")
		return

	# Completing the same step again is idempotent.
	var duplicate: bool = model.complete_step(2, "secondary_coupling")
	if duplicate:
		_fail("duplicate complete_step should report unchanged")
		return
	var after_duplicate: Dictionary = model.get_step_progress(2)
	if int(after_duplicate.get("completed_steps", -1)) != 1:
		_fail("completed_steps should remain 1 after duplicate step")
		return

	# Complete second step.
	var second_changed: bool = model.complete_step(2, "primary_coupling")
	if not second_changed:
		_fail("second complete_step should report changed")
		return
	if not model.is_sequence_complete(2):
		_fail("sequence should be complete after both steps")
		return
	var after_two: Dictionary = model.get_step_progress(2)
	if int(after_two.get("completed_steps", -1)) != 2:
		_fail("completed_steps should be 2 after both steps, got %s" % str(after_two.get("completed_steps", -1)))
		return
	if not bool(after_two.get("complete", false)):
		_fail("complete should be true after both steps")
		return

	# Summary shape check.
	var summary: Dictionary = model.get_summary()
	if not summary.has(2):
		_fail("summary missing sequence 2")
		return
	var seq_summary: Dictionary = summary.get(2, {})
	if str(seq_summary.get("objective_type", "")) != "restore_systems":
		_fail("summary objective_type should be restore_systems")
		return
	var completed_ids: Array = seq_summary.get("completed_step_ids", [])
	if completed_ids.size() != 2:
		_fail("completed_step_ids should contain 2 entries")
		return

	print("OBJECTIVE PROGRESS STATE PASS sequence=2 required=2 completed=2 applied_once=true")
	quit(0)

func _fail(reason: String) -> void:
	push_error("OBJECTIVE PROGRESS STATE FAIL reason=%s" % reason)
	quit(1)
```

- [ ] **Step 2: Run the model smoke red**

Run:
```bash
OUT=$(/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-sargasso-of-stars --script res://scripts/validation/objective_progress_state_smoke.gd 2>&1)
printf '%s\n' "$OUT"
printf '%s\n' "$OUT" | grep -q 'OBJECTIVE PROGRESS STATE PASS' || true
```

Expected (RED) result:
- Output contains `OBJECTIVE PROGRESS STATE FAIL reason=...` (likely `ObjectiveProgressState` is undefined).
- The pass marker `OBJECTIVE PROGRESS STATE PASS` does NOT appear.
- This is the RED phase — the failure is the desired outcome.

- [ ] **Step 3: Record Task 1 RED**

Run:
```bash
if git -C /Users/christopherwilloughby/the-sargasso-of-stars rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C /Users/christopherwilloughby/the-sargasso-of-stars add scripts/validation/objective_progress_state_smoke.gd
  git -C /Users/christopherwilloughby/the-sargasso-of-stars commit -m 'test(objective): RED objective progress state smoke'
else
  printf '%s\n' 'NO_GIT Task 1 RED: scripts/validation/objective_progress_state_smoke.gd added and failed for missing ObjectiveProgressState implementation' >> /tmp/sargasso_repair_junction_no_git_changes.log
fi
```

---

### Task 2: Implement `ObjectiveProgressState` Model + Green Model Smoke

**Files:**
- Create: `scripts/systems/objective_progress_state.gd`
- Read: `scripts/systems/route_control_state.gd` (template)

**Interfaces:**
- Produces the class referenced by the smoke and by `PlayableGeneratedShip`.
- Sidecar `scripts/systems/objective_progress_state.gd.uid` may be created by Godot.

- [ ] **Step 1: Create `ObjectiveProgressState`**

Write `scripts/systems/objective_progress_state.gd` with this complete content:

```gdscript
extends RefCounted
class_name ObjectiveProgressState

## Runtime model for multi-step objective progress on the main playable slice.
## This model never reaches into the scene tree. PlayableGeneratedShip owns the
## interactables and decides when to advance sequence state based on this model.
##
## A sequence is registered once with an objective_type and required step count.
## Steps are completed by step_id; duplicate completions are idempotent.
## The sequence is considered complete only when completed_steps == required_steps.

var _objectives: Dictionary = {}

func register_objective(sequence: int, objective_type: String, required_steps: int) -> void:
	if sequence <= 0:
		return
	if required_steps < 1:
		required_steps = 1
	_objectives[sequence] = {
		"objective_type": objective_type,
		"required_steps": required_steps,
		"completed_steps": 0,
		"completed_step_ids": [],
		"complete": false,
	}

func complete_step(sequence: int, step_id: String) -> bool:
	if sequence <= 0:
		return false
	if not _objectives.has(sequence):
		return false
	var objective: Dictionary = _objectives[sequence]
	if bool(objective.get("complete", false)):
		return false
	var completed_ids: Array = objective.get("completed_step_ids", [])
	if completed_ids.has(step_id):
		return false
	completed_ids.append(step_id)
	objective["completed_step_ids"] = completed_ids
	objective["completed_steps"] = completed_ids.size()
	if objective["completed_steps"] >= int(objective.get("required_steps", 1)):
		objective["complete"] = true
	_objectives[sequence] = objective
	return true

func is_sequence_complete(sequence: int) -> bool:
	if not _objectives.has(sequence):
		return false
	return bool(_objectives[sequence].get("complete", false))

func get_step_progress(sequence: int) -> Dictionary:
	if not _objectives.has(sequence):
		return { "required_steps": 0, "completed_steps": 0, "complete": false, "completed_step_ids": [] }
	var objective: Dictionary = _objectives[sequence]
	return {
		"required_steps": int(objective.get("required_steps", 1)),
		"completed_steps": int(objective.get("completed_steps", 0)),
		"complete": bool(objective.get("complete", false)),
		"completed_step_ids": objective.get("completed_step_ids", []).duplicate(),
	}

func get_sequence_objective_type(sequence: int) -> String:
	if not _objectives.has(sequence):
		return ""
	return str(_objectives[sequence].get("objective_type", ""))

func get_summary() -> Dictionary:
	var summary: Dictionary = {}
	for sequence in _objectives.keys():
		var objective: Dictionary = _objectives[sequence]
		summary[sequence] = {
			"objective_type": str(objective.get("objective_type", "")),
			"required_steps": int(objective.get("required_steps", 1)),
			"completed_steps": int(objective.get("completed_steps", 0)),
			"completed_step_ids": objective.get("completed_step_ids", []).duplicate(),
			"complete": bool(objective.get("complete", false)),
		}
	return summary

func reset() -> void:
	_objectives.clear()
```

- [ ] **Step 2: Run the model smoke green**

Run:
```bash
OUT=$(/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-sargasso-of-stars --script res://scripts/validation/objective_progress_state_smoke.gd 2>&1)
printf '%s\n' "$OUT"
printf '%s\n' "$OUT" | grep -q 'OBJECTIVE PROGRESS STATE PASS'
if printf '%s\n' "$OUT" | grep -E '^(ERROR|WARNING):' >/dev/null; then
  echo 'unexpected ERROR/WARNING in objective_progress_state_smoke'
  exit 1
fi
```

Expected (GREEN) result:
- Output contains `OBJECTIVE PROGRESS STATE PASS sequence=2 required=2 completed=2 applied_once=true`.
- No unexpected `ERROR:` or `WARNING:` lines.

- [ ] **Step 3: Record Task 2 GREEN**

Run:
```bash
if git -C /Users/christopherwilloughby/the-sargasso-of-stars rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C /Users/christopherwilloughby/the-sargasso-of-stars add scripts/systems/objective_progress_state.gd
  git -C /Users/christopherwilloughby/the-sargasso-of-stars commit -m 'feat(objective): ObjectiveProgressState model for multi-step repair junction'
else
  printf '%s\n' 'NO_GIT Task 2 GREEN: scripts/systems/objective_progress_state.gd added; objective_progress_state_smoke passes' >> /tmp/sargasso_repair_junction_no_git_changes.log
fi
```

---

### Task 3: Extend `Interactable` for Step Support

**Files:**
- Modify: `scripts/interaction/interactable.gd`

**Interfaces:**
- Adds `step_id: String` and `is_step: bool` fields.
- Adds `configure_from_step(...)`.
- Updates `interaction_completed` signal signature to include `step_id`.
- Backward compatible: `configure_from_objective` still works for single-step objectives and emits an empty `step_id`.

- [ ] **Step 1: Patch `Interactable`**

Apply these changes to `scripts/interaction/interactable.gd`:

Replace the signal declaration on line 4 with:
```gdscript
signal interaction_completed(interaction_id: String, objective_id: String, sequence: int, objective_type: String, room_id: String, step_id: String)
```

Insert after `var marker_visible: bool = false` (around line 18):
```gdscript
var step_id: String = ""
var is_step: bool = false
```

Insert after `func configure_from_objective(...)` a new method. Add this block after the closing line of `configure_from_objective` (after `_ensure_marker(radius)`):

```gdscript

func configure_from_step(objective: Dictionary, step: Dictionary, world_position: Vector3, radius := 1.8) -> void:
	configure_from_objective(objective, world_position, radius)
	is_step = true
	step_id = str(step.get("step_id", ""))
	if step_id.is_empty():
		step_id = "step_%s" % interaction_id
	interaction_id = "%s:%s" % [interaction_id, step_id]
	prompt_text = "Repair: %s" % step_id
	name = "Interactable_seq%d_step_%s" % [sequence, step_id]
	set_meta("step_id", step_id)
	set_meta("is_step", true)
```

Replace the `emit_signal` line inside `try_interact` with:
```gdscript
	emit_signal("interaction_completed", interaction_id, objective_id, sequence, objective_type, room_id, step_id)
```

- [ ] **Step 2: Verify `Interactable` still parses**

Run:
```bash
/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-sargasso-of-stars --script res://scripts/interaction/interactable.gd 2>&1 | head -n 20
```

Expected: script loads without parse errors (exit code may be 0 with baseline teardown noise only).

- [ ] **Step 3: Record Task 3**

Run:
```bash
if git -C /Users/christopherwilloughby/the-sargasso-of-stars rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C /Users/christopherwilloughby/the-sargasso-of-stars add scripts/interaction/interactable.gd
  git -C /Users/christopherwilloughby/the-sargasso-of-stars commit -m 'feat(objective): Interactable step support for repair junction'
else
  printf '%s\n' 'NO_GIT Task 3: scripts/interaction/interactable.gd extended with step_id and configure_from_step' >> /tmp/sargasso_repair_junction_no_git_changes.log
fi
```

---

### Task 4: Extend `GeneratedShipLoader` to Parse `kind` and `steps`

**Files:**
- Modify: `scripts/procgen/generated_ship_loader.gd`

**Interfaces:**
- Objective spec gains `"kind"` and `"steps"` fields when present in source JSON.
- Step entries contain `"step_id"` and `"approach_cell"`.
- Missing step `approach_cell` falls back to the objective's main `approach_cell`.
- Duplicate `step_id` within a sequence is a load failure.

- [ ] **Step 1: Patch `_build_objective_specs`**

The current function returns an objective spec with `id`, `sequence`, `type`, `room_id`, `position`, `radius`. We need to append `kind` and `steps`.

Locate the block in `scripts/procgen/generated_ship_loader.gd` that appends to `objective_specs` (around lines 304-313). Replace it with:

```gdscript
		var kind: String = str(objective.get("kind", "single"))
		var step_specs: Array = []
		if kind == "repair_junction":
			var steps_variant: Variant = objective.get("steps", [])
			if typeof(steps_variant) != TYPE_ARRAY or steps_variant.size() < 2:
				push_error("repair_junction objective requires at least 2 steps: %s" % objective_id)
				return []
			var seen_step_ids: Dictionary = {}
			for step_variant in steps_variant:
				if typeof(step_variant) != TYPE_DICTIONARY:
					push_error("repair_junction step is not an object: %s" % objective_id)
					return []
				var step: Dictionary = step_variant
				var step_id: String = str(step.get("step_id", ""))
				if step_id.is_empty():
					push_error("repair_junction step missing step_id: %s" % objective_id)
					return []
				if seen_step_ids.has(step_id):
					push_error("repair_junction duplicate step_id '%s' in objective %s" % [step_id, objective_id])
					return []
				seen_step_ids[step_id] = true
				var step_approach: Array = approach_cell.duplicate()
				var step_approach_variant: Variant = step.get("approach_cell", [])
				if typeof(step_approach_variant) == TYPE_ARRAY and step_approach_variant.size() >= 3:
					step_approach = step_approach_variant
				var step_position: Vector3 = _room_cell_world(room, step_approach)
				if step_position == Vector3.INF:
					push_error(
						"no floor position for step approach cell objective=%s step=%s cell=%s"
						% [objective_id, step_id, str(step_approach)]
					)
					return []
				step_specs.append({
					"step_id": step_id,
					"approach_cell": step_approach,
					"position": step_position,
				})

		objective_specs.append(
			{
				"id": objective_id,
				"sequence": sequence,
				"type": str(objective.get("type", "unknown")),
				"kind": kind,
				"room_id": room_id,
				"position": target_position,
				"radius": OBJECTIVE_TRIGGER_RADIUS,
				"steps": step_specs,
			}
		)
```

- [ ] **Step 2: Verify loader still passes existing contract smoke**

Run:
```bash
OUT=$(/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-sargasso-of-stars --script res://scripts/validation/procgen_loader_playable_contract_smoke.gd 2>&1)
printf '%s\n' "$OUT"
printf '%s\n' "$OUT" | grep -q 'LOADER PLAYABLE CONTRACT PASS'
```

Expected: loader contract smoke still passes (marker present, no new errors).

- [ ] **Step 3: Record Task 4**

Run:
```bash
if git -C /Users/christopherwilloughby/the-sargasso-of-stars rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C /Users/christopherwilloughby/the-sargasso-of-stars add scripts/procgen/generated_ship_loader.gd
  git -C /Users/christopherwilloughby/the-sargasso-of-stars commit -m 'feat(objective): loader parses repair_junction kind and steps'
else
  printf '%s\n' 'NO_GIT Task 4: scripts/procgen/generated_ship_loader.gd extended with kind/steps parsing' >> /tmp/sargasso_repair_junction_no_git_changes.log
fi
```

---

### Task 5: Wire Multi-Step Completion in `PlayableGeneratedShip`

**Files:**
- Modify: `scripts/procgen/playable_generated_ship.gd`

**Interfaces:**
- Owns `ObjectiveProgressState`.
- Builds one interactable per step for `repair_junction`.
- Groups interactables by sequence.
- Advances sequence and calls `ShipSystemState.apply_objective()` only after all required steps complete.
- Existing single-step behavior unchanged.

- [ ] **Step 1: Add `ObjectiveProgressState` preload and member**

Add to the top preload block:
```gdscript
const ObjectiveProgressStateScript := preload("res://scripts/systems/objective_progress_state.gd")
```

Add member variables after `var oxygen_state: OxygenState`:
```gdscript
var objective_progress_state: ObjectiveProgressState
var sequence_interactables: Dictionary = {}
```

- [ ] **Step 2: Initialize `objective_progress_state`**

In `_build_runtime_nodes`, after `oxygen_state = OxygenStateScript.new()` add:
```gdscript
	objective_progress_state = ObjectiveProgressStateScript.new()
```

- [ ] **Step 3: Rewrite `_build_interactables`**

Replace the entire `_build_interactables` function with:

```gdscript
func _build_interactables() -> void:
	interactables.clear()
	sequence_interactables.clear()
	if objective_progress_state != null:
		objective_progress_state.reset()
	for child in interaction_root.get_children():
		interaction_root.remove_child(child)
		child.free()
	for objective_variant in loader.get_objective_specs_copy():
		if typeof(objective_variant) != TYPE_DICTIONARY:
			continue
		var objective: Dictionary = objective_variant
		var sequence: int = int(objective.get("sequence", 0))
		var kind: String = str(objective.get("kind", "single"))
		var steps: Array = []
		var steps_variant: Variant = objective.get("steps", [])
		if typeof(steps_variant) == TYPE_ARRAY:
			steps = steps_variant
		if kind == "repair_junction" and steps.size() > 1:
			var required_steps: int = steps.size()
			var objective_type: String = str(objective.get("type", "unknown"))
			if objective_progress_state != null:
				objective_progress_state.register_objective(sequence, objective_type, required_steps)
			for step_variant in steps:
				if typeof(step_variant) != TYPE_DICTIONARY:
					continue
				var step: Dictionary = step_variant
				var step_position_variant: Variant = step.get("position", Vector3.INF)
				if typeof(step_position_variant) != TYPE_VECTOR3:
					continue
				var interactable = InteractableScript.new()
				interactable.configure_from_step(objective, step, step_position_variant, 1.8)
				interactable.interaction_completed.connect(_on_interactable_completed)
				interaction_root.add_child(interactable)
				interactables.append(interactable)
				_add_interactable_to_sequence(sequence, interactable)
		else:
			var position_variant: Variant = objective.get("position", Vector3.INF)
			if typeof(position_variant) != TYPE_VECTOR3:
				continue
			var interactable = InteractableScript.new()
			interactable.configure_from_objective(objective, position_variant, 1.8)
			interactable.interaction_completed.connect(_on_interactable_completed)
			interaction_root.add_child(interactable)
			interactables.append(interactable)
			_add_interactable_to_sequence(sequence, interactable)

func _add_interactable_to_sequence(sequence: int, interactable: Node) -> void:
	if not sequence_interactables.has(sequence):
		sequence_interactables[sequence] = []
	sequence_interactables[sequence].append(interactable)
```

- [ ] **Step 4: Rewrite `_on_interactable_completed`**

Replace the entire `_on_interactable_completed` function with:

```gdscript
func _on_interactable_completed(interaction_id: String, objective_id: String, sequence: int, objective_type: String, room_id: String, step_id: String) -> void:
	if sequence != current_objective_sequence:
		return

	var is_multi_step: bool = objective_progress_state != null and int(objective_progress_state.get_step_progress(sequence).get("required_steps", 1)) > 1
	if is_multi_step:
		var step_changed: bool = objective_progress_state.complete_step(sequence, step_id)
		if not step_changed:
			return
		var progress: Dictionary = objective_progress_state.get_step_progress(sequence)
		if tracker != null:
			tracker.set_step_progress(sequence, progress)
		print("OBJECTIVE STEP COMPLETED sequence=%d step=%s progress=%d/%d" % [
			sequence,
			step_id,
			int(progress.get("completed_steps", 0)),
			int(progress.get("required_steps", 1)),
		])
		if not objective_progress_state.is_sequence_complete(sequence):
			return
		# Fall through to single-step completion path exactly once.

	objective_completion_count += 1
	if ship_systems != null:
		ship_systems.apply_objective(sequence, objective_type, objective_id, room_id)
		_apply_ship_systems_consequences(objective_type)
		_refresh_route_control_from_ship_systems()
		if oxygen_state != null:
			oxygen_state.apply_ship_systems_summary(ship_systems.get_summary())
			_refresh_oxygen_state(false, 0.0)
		var ship_summary: Dictionary = ship_systems.get_summary()
		var route_summary: Dictionary = get_route_control_summary()
		print("SHIP SYSTEM UPDATED sequence=%d type=%s power=%d reactor=%d extraction=%s route_opened=%d blockers=%d" % [
			sequence,
			objective_type,
			int(ship_summary.get("power_percent", 0)),
			int(ship_summary.get("reactor_stability_percent", 0)),
			str(bool(ship_summary.get("extraction_unlocked", false))).to_lower(),
			int(route_summary.get("opened_gate_count", 0)),
			int(route_summary.get("active_blocker_count", 0)),
		])
	tracker.mark_completed(sequence)
	print("PLAYABLE INTERACTION interaction=%s objective=%s sequence=%d type=%s room=%s" % [interaction_id, objective_id, sequence, objective_type, room_id])
	emit_signal("playable_interaction_completed", interaction_id, objective_id, sequence, objective_type, room_id)
	if objective_completion_count >= interactables.size():
		slice_complete = true
		current_objective_sequence = interactables.size() + 1
		tracker.mark_run_complete()
		print("PLAYABLE SLICE COMPLETE objectives_completed=%d" % objective_completion_count)
		emit_signal("playable_slice_completed", get_slice_completion_summary())
		return
	current_objective_sequence += 1
	_activate_current_objective()
```

- [ ] **Step 5: Update `_activate_current_objective`**

Replace the function with:

```gdscript
func _activate_current_objective() -> void:
	for interactable_variant in interactables:
		var interactable = interactable_variant
		if interactable.has_method("set_active"):
			interactable.set_active(int(interactable.get("sequence")) == current_objective_sequence)
	if tracker != null:
		tracker.set_current_sequence(current_objective_sequence)
		var progress: Dictionary = {}
		if objective_progress_state != null:
			progress = objective_progress_state.get_step_progress(current_objective_sequence)
		tracker.set_step_progress(current_objective_sequence, progress)
		var current = get_interactable_by_sequence(current_objective_sequence)
		if current != null:
			tracker.set_interaction_prompt(str(current.get("prompt_text")))
```

- [ ] **Step 6: Update `get_interactable_by_sequence`**

Replace the function with:

```gdscript
func get_interactable_by_sequence(sequence: int):
	var group: Array = sequence_interactables.get(sequence, [])
	for interactable in group:
		if int(interactable.get("sequence")) == sequence:
			return interactable
	return null
```

- [ ] **Step 7: Add `get_objective_progress_summary` helper**

Add near the other summary helpers:

```gdscript
func get_objective_progress_summary() -> Dictionary:
	if objective_progress_state == null:
		return {}
	return objective_progress_state.get_summary()
```

- [ ] **Step 8: Run the model smoke and route-control smoke**

Run:
```bash
OUT=$(/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-sargasso-of-stars --script res://scripts/validation/objective_progress_state_smoke.gd 2>&1)
printf '%s\n' "$OUT"
printf '%s\n' "$OUT" | grep -q 'OBJECTIVE PROGRESS STATE PASS'
OUT2=$(/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-sargasso-of-stars --script res://scripts/validation/route_control_state_smoke.gd 2>&1)
printf '%s\n' "$OUT2"
printf '%s\n' "$OUT2" | grep -q 'ROUTE CONTROL STATE PASS'
```

Expected: both pass markers present; no new `ERROR:`/`WARNING:` lines.

- [ ] **Step 9: Record Task 5**

Run:
```bash
if git -C /Users/christopherwilloughby/the-sargasso-of-stars rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C /Users/christopherwilloughby/the-sargasso-of-stars add scripts/procgen/playable_generated_ship.gd
  git -C /Users/christopherwilloughby/the-sargasso-of-stars commit -m 'feat(objective): wire multi-step repair junction completion'
else
  printf '%s\n' 'NO_GIT Task 5: scripts/procgen/playable_generated_ship.gd wired for multi-step objectives' >> /tmp/sargasso_repair_junction_no_git_changes.log
fi
```

---

### Task 6: Update `ObjectiveTracker` for Step Progress Text

**Files:**
- Modify: `scripts/ui/objective_tracker.gd`

**Interfaces:**
- Adds `set_step_progress(sequence, progress)`.
- When current sequence has `required_steps > 1`, display `"Repair junction (1/2) @ room"`.
- Single-step display unchanged.

- [ ] **Step 1: Add state and setter**

Insert after `var system_status_lines: PackedStringArray = PackedStringArray()`:
```gdscript
var current_step_progress: Dictionary = {}
```

Add after `func set_current_sequence(sequence: int) -> void`:
```gdscript
func set_step_progress(sequence: int, progress: Dictionary) -> void:
	current_step_progress = progress.duplicate(true)
	_refresh()
```

- [ ] **Step 2: Update `_current_objective_display`**

Replace the function with:

```gdscript
func _current_objective_display() -> String:
	for objective_variant in objectives:
		if typeof(objective_variant) != TYPE_DICTIONARY:
			continue
		var objective: Dictionary = objective_variant
		var sequence: int = int(objective.get("sequence", 0))
		if sequence == current_sequence:
			var required_steps: int = int(current_step_progress.get("required_steps", 1))
			var completed_steps: int = int(current_step_progress.get("completed_steps", 0))
			var base: String = _type_display(str(objective.get("type", "objective")))
			if required_steps > 1:
				base = "%s (%d/%d)" % [base, completed_steps, required_steps]
			return "%02d %s @ %s" % [
				sequence,
				base,
				_room_display(str(objective.get("room_id", "room"))),
			]
	return "%02d Objective" % current_sequence
```

- [ ] **Step 3: Run the HUD smoke**

Run:
```bash
OUT=$(/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-sargasso-of-stars --script res://scripts/validation/main_playable_slice_hud_smoke.gd 2>&1)
printf '%s\n' "$OUT"
printf '%s\n' "$OUT" | grep -q 'MAIN PLAYABLE HUD PASS'
```

Expected: HUD smoke still passes.

- [ ] **Step 4: Record Task 6**

Run:
```bash
if git -C /Users/christopherwilloughby/the-sargasso-of-stars rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C /Users/christopherwilloughby/the-sargasso-of-stars add scripts/ui/objective_tracker.gd
  git -C /Users/christopherwilloughby/the-sargasso-of-stars commit -m 'feat(objective): tracker shows repair junction step progress'
else
  printf '%s\n' 'NO_GIT Task 6: scripts/ui/objective_tracker.gd shows multi-step progress text' >> /tmp/sargasso_repair_junction_no_git_changes.log
fi
```

---

### Task 7: Add Main-Scene Objective-Variation Smoke

**Files:**
- Create: `scripts/validation/main_playable_slice_objective_variation_smoke.gd`

**Interfaces:**
- Loads `main.tscn`, finds `PlayableGeneratedShip`.
- Asserts sequence 2 is a `repair_junction` with two interactable steps.
- Completes both steps and asserts `ShipSystemState.apply_objective()` ran once (power restored, gates opened, blocker count 0).
- Completes remaining single-step objectives and asserts extraction unlocks.

- [ ] **Step 1: Create the main-scene smoke**

Write `scripts/validation/main_playable_slice_objective_variation_smoke.gd` with this complete content:

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
	if not playable.has_method("get_ship_systems_summary"):
		_fail("get_ship_systems_summary missing")
		return
	if not playable.has_method("get_route_control_summary"):
		_fail("get_route_control_summary missing")
		return
	if not playable.has_method("get_objective_progress_summary"):
		_fail("get_objective_progress_summary missing")
		return

	var progress_summary: Dictionary = playable.get_objective_progress_summary()
	if not progress_summary.has(2):
		_fail("sequence 2 not registered in objective progress state")
		return
	var seq2_progress: Dictionary = progress_summary.get(2, {})
	if int(seq2_progress.get("required_steps", -1)) != 2:
		_fail("sequence 2 required_steps=%d expected 2" % int(seq2_progress.get("required_steps", -1)))
		return
	if str(seq2_progress.get("objective_type", "")) != "restore_systems":
		_fail("sequence 2 objective_type=%s expected restore_systems" % str(seq2_progress.get("objective_type", "")))
		return

	var group: Array = playable.sequence_interactables.get(2, [])
	if group.size() != 2:
		_fail("sequence 2 interactable group size=%d expected 2" % group.size())
		return

	# Complete both steps of the repair junction.
	if not playable.complete_objective_sequence_for_validation(2):
		_fail("complete objective sequence 2 failed")
		return

	var after_two: Dictionary = playable.get_ship_systems_summary()
	if not bool(after_two.get("main_power_restored", false)):
		_fail("after sequence 2 main_power_restored=false")
		return
	if not bool(after_two.get("blocked_routes_cleared", false)):
		_fail("after sequence 2 blocked_routes_cleared=false")
		return

	var route_after_two: Dictionary = playable.get_route_control_summary()
	if not bool(route_after_two.get("powered_gates_open", false)):
		_fail("after sequence 2 powered_gates_open=false")
		return
	if int(route_after_two.get("active_blocker_count", -1)) != 0:
		_fail("after sequence 2 active_blocker_count=%d expected 0" % int(route_after_two.get("active_blocker_count", -1)))
		return

	var progress_after_two: Dictionary = playable.get_objective_progress_summary().get(2, {})
	if not bool(progress_after_two.get("complete", false)):
		_fail("sequence 2 progress complete=false after both steps")
		return

	# Complete remaining single-step objectives.
	if not playable.complete_objective_sequence_for_validation(3):
		_fail("complete objective sequence 3 failed")
		return
	if not playable.complete_objective_sequence_for_validation(4):
		_fail("complete objective sequence 4 failed")
		return

	var final_route: Dictionary = playable.get_route_control_summary()
	if not bool(final_route.get("extraction_unlocked", false)):
		_fail("final extraction_unlocked=false")
		return
	if not bool(playable.get_slice_completion_summary().get("run_complete", false)):
		_fail("final run_complete=false")
		return

	finished = true
	print("MAIN PLAYABLE OBJECTIVE VARIATION PASS sequence=2 steps=2 complete=true power_restored=true gates_opened=true")
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
	push_error("MAIN PLAYABLE OBJECTIVE VARIATION FAIL reason=%s" % reason)
	_cleanup_and_quit(1)

func _cleanup_and_quit(code: int) -> void:
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	quit(code)
```

- [ ] **Step 2: Run the main-scene smoke (initially may fail until data is updated)**

At this point the smoke will likely fail because the gameplay slice still uses a single-step sequence 2. Run it once to confirm the failure is due to missing `repair_junction` data, not code errors:

```bash
OUT=$(/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-sargasso-of-stars --script res://scripts/validation/main_playable_slice_objective_variation_smoke.gd 2>&1)
printf '%s\n' "$OUT"
```

Expected: marker `MAIN PLAYABLE OBJECTIVE VARIATION PASS` is absent; failure reason references sequence 2 not being a multi-step junction. No Godot parse errors.

- [ ] **Step 3: Record Task 7 RED**

Run:
```bash
if git -C /Users/christopherwilloughby/the-sargasso-of-stars rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C /Users/christopherwilloughby/the-sargasso-of-stars add scripts/validation/main_playable_slice_objective_variation_smoke.gd
  git -C /Users/christopherwilloughby/the-sargasso-of-stars commit -m 'test(objective): RED main-scene objective variation smoke'
else
  printf '%s\n' 'NO_GIT Task 7 RED: scripts/validation/main_playable_slice_objective_variation_smoke.gd added; fails until gameplay_slice data updated' >> /tmp/sargasso_repair_junction_no_git_changes.log
fi
```

---

### Task 8: Update Gameplay Slice Data

**Files:**
- Modify: `data/procgen/smoke/seed_000017/gameplay_slice.json`

**Interfaces:**
- Sequence 2 becomes a `repair_junction` with `type = "restore_systems"` and two steps.
- Step approach cells resolve to valid floor placements in `maintenance_01`.

- [ ] **Step 1: Find valid floor cells in `maintenance_01`**

Read `/Users/christopherwilloughby/the-sargasso-of-stars/data/procgen/smoke/seed_000017/layout.json` and locate the `maintenance_01` room. Identify at least two distinct floor cell placements (e.g., `floor_cell_x14_z0` and `floor_cell_x13_z0`) that are inside the room and navigable.

If the existing single-step sequence-2 objective uses `approach_cell [14, 0, 1]`, choose adjacent floor cells in the same room for the two steps, such as:
- primary_coupling: `[14, 0, 1]`
- secondary_coupling: `[13, 0, 1]`

Both must correspond to existing `floor_1x1` placements in `maintenance_01`.

- [ ] **Step 2: Patch the sequence-2 objective**

Replace the second objective entry (sequence 2) in `data/procgen/smoke/seed_000017/gameplay_slice.json` with:

```json
    {
      "id": "maintenance_01:junction_alpha",
      "sequence": 2,
      "type": "restore_systems",
      "kind": "repair_junction",
      "room_id": "maintenance_01",
      "room_role": "maintenance",
      "placement_id": "maintenance_01_tool_locker",
      "semantic": "junction_box",
      "cell": [
        13,
        0,
        1
      ],
      "approach_cell": [
        14,
        0,
        1
      ],
      "approach_distance_cells": 1,
      "interactable": true,
      "steps": [
        {
          "step_id": "primary_coupling",
          "approach_cell": [
            14,
            0,
            1
          ]
        },
        {
          "step_id": "secondary_coupling",
          "approach_cell": [
            13,
            0,
            1
          ]
        }
      ],
      "complete_condition": {
        "kind": "interact_with_placement",
        "room_id": "maintenance_01",
        "placement_id": "maintenance_01_tool_locker",
        "semantic": "junction_box",
        "objective_type": "restore_systems"
      }
    }
```

- [ ] **Step 3: Verify the loader resolves the new cells**

Run:
```bash
OUT=$(/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-sargasso-of-stars --script res://scripts/validation/procgen_loader_playable_contract_smoke.gd 2>&1)
printf '%s\n' "$OUT"
printf '%s\n' "$OUT" | grep -q 'LOADER PLAYABLE CONTRACT PASS'
```

Expected: loader contract smoke passes and the new objective spec includes `kind: "repair_junction"` and two steps.

- [ ] **Step 4: Run the main-scene smoke green**

Run:
```bash
OUT=$(/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-sargasso-of-stars --script res://scripts/validation/main_playable_slice_objective_variation_smoke.gd 2>&1)
printf '%s\n' "$OUT"
printf '%s\n' "$OUT" | grep -q 'MAIN PLAYABLE OBJECTIVE VARIATION PASS'
if printf '%s\n' "$OUT" | grep -E '^(ERROR|WARNING):' >/dev/null; then
  echo 'unexpected ERROR/WARNING in main_playable_slice_objective_variation_smoke'
  exit 1
fi
```

Expected: output contains `MAIN PLAYABLE OBJECTIVE VARIATION PASS sequence=2 steps=2 complete=true power_restored=true gates_opened=true` and no unexpected `ERROR:`/`WARNING:` lines.

- [ ] **Step 5: Record Task 8**

Run:
```bash
if git -C /Users/christopherwilloughby/the-sargasso-of-stars rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C /Users/christopherwilloughby/the-sargasso-of-stars add data/procgen/smoke/seed_000017/gameplay_slice.json
  git -C /Users/christopherwilloughby/the-sargasso-of-stars commit -m 'data(objective): replace sequence 2 with repair_junction'
else
  printf '%s\n' 'NO_GIT Task 8: data/procgen/smoke/seed_000017/gameplay_slice.json updated with repair_junction at sequence 2' >> /tmp/sargasso_repair_junction_no_git_changes.log
fi
```

---

### Task 9: Update Regression Bundle

**Files:**
- Modify: `docs/game/06_validation_plan.md`

**Interfaces:**
- Add both new smokes to the regression bundle script.
- Remove them from the "Future validation additions" list.

- [ ] **Step 1: Patch the regression bundle**

In `docs/game/06_validation_plan.md`, add two `run_clean` lines to the bundle script (inside the `set -euo pipefail` block, after the readability smoke line):

```bash
run_clean 'objective progress state smoke' 'OBJECTIVE PROGRESS STATE PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/objective_progress_state_smoke.gd
run_clean 'main objective variation smoke' 'MAIN PLAYABLE OBJECTIVE VARIATION PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_objective_variation_smoke.gd
```

Also update the final echo line from `commands=8` to `commands=10`:
```bash
echo 'SARGASSO REGRESSION PASS commands=10 clean_output=true'
```

- [ ] **Step 2: Update "Future validation additions"**

Replace the line:
```markdown
- Objective variation model smoke: `scripts/validation/objective_progress_state_smoke.gd` and main-scene smoke `scripts/validation/main_playable_slice_objective_variation_smoke.gd` (REQ-011).
```

with:
```markdown
- ~~Objective variation model smoke: `scripts/validation/objective_progress_state_smoke.gd` and main-scene smoke `scripts/validation/main_playable_slice_objective_variation_smoke.gd` (REQ-011).~~ Added to regression bundle.
```

- [ ] **Step 3: Run the full regression bundle**

Run the complete regression bundle script from `docs/game/06_validation_plan.md`.

Expected: all 10 smokes pass and the final line prints `SARGASSO REGRESSION PASS commands=10 clean_output=true`.

- [ ] **Step 4: Record Task 9**

Run:
```bash
if git -C /Users/christopherwilloughby/the-sargasso-of-stars rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C /Users/christopherwilloughby/the-sargasso-of-stars add docs/game/06_validation_plan.md
  git -C /Users/christopherwilloughby/the-sargasso-of-stars commit -m 'docs(validation): add REQ-011 smokes to regression bundle'
else
  printf '%s\n' 'NO_GIT Task 9: docs/game/06_validation_plan.md updated with REQ-011 smokes' >> /tmp/sargasso_repair_junction_no_git_changes.log
fi
```

---

### Task 10: Final Verification and Handoff

- [ ] **Step 1: Run all REQ-011 verification commands**

Run:
```bash
/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-sargasso-of-stars --script res://scripts/validation/objective_progress_state_smoke.gd
/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-sargasso-of-stars --script res://scripts/validation/main_playable_slice_objective_variation_smoke.gd
```

Expected markers:
- `OBJECTIVE PROGRESS STATE PASS sequence=2 required=2 completed=2 applied_once=true`
- `MAIN PLAYABLE OBJECTIVE VARIATION PASS sequence=2 steps=2 complete=true power_restored=true gates_opened=true`

- [ ] **Step 2: Run the regression bundle one final time**

Use the updated bundle in `docs/game/06_validation_plan.md`.

Expected: `SARGASSO REGRESSION PASS commands=10 clean_output=true`.

- [ ] **Step 3: Inspect the no-git ledger**

Run:
```bash
cat /tmp/sargasso_repair_junction_no_git_changes.log 2>/dev/null || echo 'no no-git ledger'
```

- [ ] **Step 4: Record completion and unblock the implement card**

Add a handoff comment to the implement card `t_abdf39e0` summarizing:
- Plan file path.
- Allowed files and non-goals.
- Exact verification commands.
- The single architectural decision not to generalize beyond one `repair_junction` kind pending ADR-0006.
- Note that `data/procgen/smoke/seed_000017/gameplay_slice.json` must be updated in Task 8 before the main-scene smoke will pass.

Then mark this plan card complete.

---

## Stop / Block Conditions

Block and escalate to `sargassoreview` if any of the following occur:

- The implementation would alter route/extraction rules, advance ship systems before all steps complete, or call `ShipSystemState.apply_objective()` more than once for a sequence.
- A change breaks an existing smoke in `docs/game/06_validation_plan.md` and the breakage is not a straightforward regression in the new feature itself.
- The work expands into a generalized objective graph, branching objectives, failure/timer states, or new ship-system flags.
- A saved-run load path (REQ-012) requires completed-step restoration before this card's scope is finished; instead, ensure `ObjectiveProgressState.get_summary()` exposes `completed_step_ids` so REQ-012 can serialize them later.
- The `kind`/`type` split is confusing downstream workers; clarify that `type` is the ship-system effect and `kind` is the layout/completion handler.

## Risks

- **Risk:** Multi-step progress confuses the player if the HUD does not clearly show `Repair junction (1/2)`.
  - **Mitigation:** `ObjectiveTracker` prints the step fraction; both step markers stay visible until completion.
- **Risk:** Out-of-order step completion breaks narrative framing.
  - **Mitigation:** Gate 2 steps are identical couplings; no order dependency. `ObjectiveProgressState` explicitly allows any order.
- **Risk:** Refactoring `_on_interactable_completed` breaks single-step objectives.
  - **Mitigation:** Existing single-step path is preserved; all pre-existing smokes must pass in the regression bundle.
- **Risk:** `Interactable.interaction_completed` signal signature change breaks other callers.
  - **Mitigation:** Only `PlayableGeneratedShip` connects to this signal in the current codebase; the signal signature change is coordinated with the handler update.
- **Risk:** Loader changes reject valid legacy gameplay slices.
  - **Mitigation:** `kind` defaults to `"single"` and `steps` defaults to empty; legacy slices produce identical objective specs.

## ADRs

- `docs/game/adr/0001-adopt-stage-gate-kanban-godot-validation.md`
- No new ADR required for one multi-step type; if Gate 3 expands to a generalized objective graph, author ADR-0006 (Objective Graph Architecture) then (per `docs/game/features/objective_variation.md` line 156).
