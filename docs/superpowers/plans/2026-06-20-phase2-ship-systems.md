# Phase 2: Ship Systems Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the six core ship systems as pure data models with subcomponents, a derived dependency cascade, and a parameterized repair flow — alongside the existing `ShipSystemState`, with no changes to the live playable slice.

**Architecture:** A `ShipSystemsManager` (`RefCounted`) owns six `ShipSystem` instances built from `data/ship_systems/systems.json`. Operational status is computed on demand by walking subcomponent health + dependency ids (cycle-safe, no cached cascade). `advance(delta)` ticks each system with its operational status; only `LifeSupportSystem` (the one subclass) has a model-level time effect — it drains a wrapped `OxygenState` when offline. Repair is parameterized: `repair(system_id, subcomponent_id, parts, tools, skill)` resolves deterministically against each subcomponent's declared requirements.

**Tech Stack:** Godot 4.6.2, typed GDScript, `RefCounted` models (no scene tree). Validation via headless `extends SceneTree` smokes.

**Spec:** `docs/superpowers/specs/2026-06-20-phase2-ship-systems-design.md`
**ADR:** `docs/game/adr/0008-ship-systems-architecture.md`

## Global Constraints

- Godot 4.6.2, typed GDScript, `RefCounted` only — no scene tree access in any new file.
- New scripts in `scripts/systems/`; new data in `data/ship_systems/`; new smokes in `scripts/validation/`.
- Deterministic: same (condition, seed) → identical initial damage and identical round-trip.
- Every model implements `get_summary()` / `apply_summary()`.
- Build alongside: do NOT modify `scripts/systems/ship_system_state.gd`, the playable slice, `run_snapshot.gd`, or `save_load_service.gd` in this phase.
- The regression bundle must stay green; new smokes are added to it.
- Cross-file type references in smokes go through `preload(...)` `*Script` constants (Godot `class_name` globals are not reliably registered in `--headless --script` mode).
- Smoke idiom: `extends SceneTree`, `func _initialize()`, on failure `push_error("PREFIX FAIL ...")` then `quit(1)` then `return`; on success `print("PREFIX PASS ...")` then `quit(0)`. NOTE: in a `SceneTree`, `quit()` only sets a flag — it does NOT halt `_initialize()`, so every failure path MUST `return` immediately after `quit(1)` and the PASS print must be reachable only when all checks passed.
- Run a smoke:
  ```bash
  GODOT="C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe"
  ROOT="C:/Users/dasbl/Documents/The Synaptic Sea"
  "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/<smoke>.gd
  ```
- Allowlisted baseline teardown noise (ignore): `ERROR: Capture not registered: 'gdaimcp'.` and `WARNING: ObjectDB instances leaked at exit ...`. Any OTHER `ERROR:`/`WARNING:` line is a failure.

---

## File Structure

| File | Responsibility |
|------|----------------|
| `scripts/systems/ship_subcomponent.gd` | One repairable part: health, operational threshold, repair requirements, `repair()`, summary round-trip. |
| `scripts/systems/ship_system.gd` | One system: id, subcomponents, dependency ids; derived health; no-op `advance()`; summary round-trip. |
| `scripts/systems/life_support_system.gd` | `extends ship_system.gd`; owns an `OxygenState`, drains it when offline. |
| `scripts/systems/ship_systems_manager.gd` | Owns 6 systems, derived cascade, `advance`, `repair`, status + summary round-trip. |
| `data/ship_systems/systems.json` | Data definitions for the 6 systems, their subcomponents, requirements, and dependencies. |
| `scripts/validation/ship_subcomponent_smoke.gd` | Pure-model smoke for `ShipSubcomponent`. |
| `scripts/validation/ship_system_smoke.gd` | Pure-model smoke for `ShipSystem`. |
| `scripts/validation/life_support_system_smoke.gd` | Pure-model smoke for `LifeSupportSystem`. |
| `scripts/validation/ship_systems_definitions_smoke.gd` | Validates `systems.json` shape. |
| `scripts/validation/ship_systems_manager_smoke.gd` | Phase 2 gate smoke: cascade, repair, advance, determinism, round-trip. |

---

## Task 1: ShipSubcomponent

**Files:**
- Create: `scripts/systems/ship_subcomponent.gd`
- Test: `scripts/validation/ship_subcomponent_smoke.gd`

**Interfaces:**
- Produces:
  - `ShipSubcomponent.new(id: String, required_parts: Array[String], required_tools: Array[String], min_skill: int, repair_seconds: float, operational_threshold: float)`
  - `var health: float`, `var subcomponent_id: String`
  - `is_functional() -> bool`
  - `repair(available_parts: Array, available_tools: Array, skill_level: int) -> Dictionary` returning `{"success": bool, "reason": String, "seconds": float}` with reason in `ok | already_functional | missing_parts | missing_tools | insufficient_skill`
  - `get_summary() -> Dictionary`, `apply_summary(summary: Dictionary) -> bool`

- [ ] **Step 1: Write the failing test**

Create `scripts/validation/ship_subcomponent_smoke.gd`:

```gdscript
extends SceneTree

const SubScript := preload("res://scripts/systems/ship_subcomponent.gd")

func _initialize() -> void:
	# Damaged part with one required part, one tool, min skill 2.
	var sub = SubScript.new("reactor_core", ["power_cell"], ["welder"], 2, 10.0, 0.5)
	sub.health = 0.2

	if sub.is_functional():
		push_error("SHIP SUBCOMPONENT FAIL damaged part reports functional")
		quit(1)
		return

	# Missing the required part.
	var r1: Dictionary = sub.repair([], ["welder"], 5)
	if r1.get("success", true) or str(r1.get("reason", "")) != "missing_parts":
		push_error("SHIP SUBCOMPONENT FAIL expected missing_parts, got %s" % str(r1))
		quit(1)
		return

	# Missing the required tool.
	var r2: Dictionary = sub.repair(["power_cell"], [], 5)
	if r2.get("success", true) or str(r2.get("reason", "")) != "missing_tools":
		push_error("SHIP SUBCOMPONENT FAIL expected missing_tools, got %s" % str(r2))
		quit(1)
		return

	# Under-skill.
	var r3: Dictionary = sub.repair(["power_cell"], ["welder"], 1)
	if r3.get("success", true) or str(r3.get("reason", "")) != "insufficient_skill":
		push_error("SHIP SUBCOMPONENT FAIL expected insufficient_skill, got %s" % str(r3))
		quit(1)
		return

	# Full requirements met -> success, health restored, faster with higher skill.
	var r4: Dictionary = sub.repair(["power_cell"], ["welder"], 4)
	if not r4.get("success", false) or str(r4.get("reason", "")) != "ok":
		push_error("SHIP SUBCOMPONENT FAIL expected ok success, got %s" % str(r4))
		quit(1)
		return
	if absf(sub.health - 1.0) > 0.0001:
		push_error("SHIP SUBCOMPONENT FAIL health not restored: %f" % sub.health)
		quit(1)
		return
	if float(r4.get("seconds", 99.0)) >= 10.0:
		push_error("SHIP SUBCOMPONENT FAIL skill 4 should be faster than base 10s, got %f" % float(r4.get("seconds", 99.0)))
		quit(1)
		return

	# Repairing an already-functional part is a no-op rejection.
	var r5: Dictionary = sub.repair(["power_cell"], ["welder"], 4)
	if r5.get("success", true) or str(r5.get("reason", "")) != "already_functional":
		push_error("SHIP SUBCOMPONENT FAIL expected already_functional, got %s" % str(r5))
		quit(1)
		return

	# Summary round-trip.
	var damaged = SubScript.new("co2_scrubber", [], [], 0, 5.0, 0.5)
	damaged.health = 0.3
	var summary: Dictionary = damaged.get_summary()
	var restored = SubScript.new("co2_scrubber", [], [], 0, 5.0, 0.5)
	if not restored.apply_summary(summary):
		push_error("SHIP SUBCOMPONENT FAIL apply_summary reported no change")
		quit(1)
		return
	if absf(restored.health - 0.3) > 0.0001:
		push_error("SHIP SUBCOMPONENT FAIL round-trip health mismatch: %f" % restored.health)
		quit(1)
		return
	if restored.apply_summary({}):
		push_error("SHIP SUBCOMPONENT FAIL empty summary should be rejected")
		quit(1)
		return

	print("SHIP SUBCOMPONENT PASS repair_reasons=ok skill_scaling=ok round_trip=ok")
	quit(0)
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ship_subcomponent_smoke.gd
```
Expected: FAIL — `ship_subcomponent.gd` does not exist, preload error (no PASS marker).

- [ ] **Step 3: Write the implementation**

Create `scripts/systems/ship_subcomponent.gd`:

```gdscript
extends RefCounted
class_name ShipSubcomponent

## One repairable part of a ship system. Pure data model: never touches the
## scene tree. health is 0.0 (destroyed) .. 1.0 (perfect); at/above
## operational_threshold the part counts as functional.

var subcomponent_id: String = ""
var health: float = 1.0
var operational_threshold: float = 0.5
var required_parts: Array[String] = []
var required_tools: Array[String] = []
var min_skill: int = 0
var repair_seconds: float = 5.0

func _init(
		p_id: String = "",
		p_required_parts: Array[String] = [],
		p_required_tools: Array[String] = [],
		p_min_skill: int = 0,
		p_repair_seconds: float = 5.0,
		p_operational_threshold: float = 0.5) -> void:
	subcomponent_id = p_id
	required_parts = p_required_parts.duplicate()
	required_tools = p_required_tools.duplicate()
	min_skill = p_min_skill
	repair_seconds = p_repair_seconds
	operational_threshold = p_operational_threshold

func is_functional() -> bool:
	return health >= operational_threshold

## Parameterized repair. Deterministic: success is fully determined by the
## requirements being met. Returns {success, reason, seconds}.
func repair(available_parts: Array, available_tools: Array, skill_level: int) -> Dictionary:
	if is_functional():
		return {"success": false, "reason": "already_functional", "seconds": 0.0}
	for part in required_parts:
		if not available_parts.has(part):
			return {"success": false, "reason": "missing_parts", "seconds": 0.0}
	for tool in required_tools:
		if not available_tools.has(tool):
			return {"success": false, "reason": "missing_tools", "seconds": 0.0}
	if skill_level < min_skill:
		return {"success": false, "reason": "insufficient_skill", "seconds": 0.0}
	health = 1.0
	var factor: float = 1.0 + 0.1 * float(maxi(0, skill_level - min_skill))
	return {"success": true, "reason": "ok", "seconds": repair_seconds / factor}

func get_summary() -> Dictionary:
	return {
		"subcomponent_id": subcomponent_id,
		"health": health,
		"operational_threshold": operational_threshold,
		"required_parts": required_parts.duplicate(),
		"required_tools": required_tools.duplicate(),
		"min_skill": min_skill,
		"repair_seconds": repair_seconds,
	}

## Restores mutable runtime state (health) from a summary. Static config
## (requirements/threshold) is not re-applied. Returns false on empty input.
func apply_summary(summary: Dictionary) -> bool:
	if summary == null or summary.is_empty():
		return false
	var changed: bool = false
	var new_health: float = clampf(float(summary.get("health", health)), 0.0, 1.0)
	if absf(new_health - health) > 0.0001:
		health = new_health
		changed = true
	return changed
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ship_subcomponent_smoke.gd
```
Expected: `SHIP SUBCOMPONENT PASS repair_reasons=ok skill_scaling=ok round_trip=ok` and no non-allowlisted ERROR/WARNING.

- [ ] **Step 5: Commit**

```bash
git add scripts/systems/ship_subcomponent.gd scripts/validation/ship_subcomponent_smoke.gd
git commit -m "feat(systems): add ShipSubcomponent with parameterized repair"
```

---

## Task 2: ShipSystem (base)

**Files:**
- Create: `scripts/systems/ship_system.gd`
- Test: `scripts/validation/ship_system_smoke.gd`

**Interfaces:**
- Consumes: `ShipSubcomponent` (Task 1).
- Produces:
  - `ShipSystem.new(system_id: String, dependency_ids: Array[String])`
  - `var system_id: String`, `var subcomponents: Array`, `var dependency_ids: Array[String]`
  - `add_subcomponent(sub) -> void`, `get_subcomponent(sub_id: String) -> ShipSubcomponent` (null if absent)
  - `health() -> float` (min of subcomponent healths; 1.0 if none)
  - `is_self_functional() -> bool` (all subcomponents functional)
  - `advance(delta: float, operational: bool) -> void` (base: no-op)
  - `get_summary() -> Dictionary`, `apply_summary(summary: Dictionary) -> bool`

- [ ] **Step 1: Write the failing test**

Create `scripts/validation/ship_system_smoke.gd`:

```gdscript
extends SceneTree

const SystemScript := preload("res://scripts/systems/ship_system.gd")
const SubScript := preload("res://scripts/systems/ship_subcomponent.gd")

func _initialize() -> void:
	var deps: Array[String] = ["power"]
	var system = SystemScript.new("life_support", deps)
	system.add_subcomponent(SubScript.new("air_recycler", [], [], 0, 5.0, 0.5))
	system.add_subcomponent(SubScript.new("co2_scrubber", [], [], 0, 5.0, 0.5))

	# All healthy -> self functional, health 1.0.
	if not system.is_self_functional():
		push_error("SHIP SYSTEM FAIL healthy system not self_functional")
		quit(1)
		return
	if absf(system.health() - 1.0) > 0.0001:
		push_error("SHIP SYSTEM FAIL healthy health != 1.0: %f" % system.health())
		quit(1)
		return

	# Break one subcomponent -> not self functional, health is the weakest link.
	system.get_subcomponent("co2_scrubber").health = 0.1
	if system.is_self_functional():
		push_error("SHIP SYSTEM FAIL broken subcomponent still self_functional")
		quit(1)
		return
	if absf(system.health() - 0.1) > 0.0001:
		push_error("SHIP SYSTEM FAIL health not weakest link: %f" % system.health())
		quit(1)
		return

	# get_subcomponent returns null for unknown id.
	if system.get_subcomponent("nope") != null:
		push_error("SHIP SYSTEM FAIL unknown subcomponent should be null")
		quit(1)
		return

	# dependency ids preserved.
	if system.dependency_ids != ["power"]:
		push_error("SHIP SYSTEM FAIL dependency_ids mismatch: %s" % str(system.dependency_ids))
		quit(1)
		return

	# base advance is a no-op (does not raise, does not change health).
	system.advance(1.0, false)
	if absf(system.health() - 0.1) > 0.0001:
		push_error("SHIP SYSTEM FAIL base advance changed health")
		quit(1)
		return

	# Round-trip: damaged healths survive get_summary -> apply_summary.
	var summary: Dictionary = system.get_summary()
	var restored = SystemScript.new("life_support", deps)
	restored.add_subcomponent(SubScript.new("air_recycler", [], [], 0, 5.0, 0.5))
	restored.add_subcomponent(SubScript.new("co2_scrubber", [], [], 0, 5.0, 0.5))
	if not restored.apply_summary(summary):
		push_error("SHIP SYSTEM FAIL apply_summary reported no change")
		quit(1)
		return
	if absf(restored.get_subcomponent("co2_scrubber").health - 0.1) > 0.0001:
		push_error("SHIP SYSTEM FAIL round-trip subcomponent health mismatch")
		quit(1)
		return

	print("SHIP SYSTEM PASS health=weakest_link self_functional=ok advance_noop=ok round_trip=ok")
	quit(0)
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ship_system_smoke.gd
```
Expected: FAIL — `ship_system.gd` does not exist.

- [ ] **Step 3: Write the implementation**

Create `scripts/systems/ship_system.gd`:

```gdscript
extends RefCounted
class_name ShipSystem

## One ship system: a set of subcomponents plus the ids of other systems it
## depends on. Pure data model. Operational status is NOT stored here — the
## manager computes it (it owns the dependency graph). This class answers the
## health half of that decision via is_self_functional().

var system_id: String = ""
var subcomponents: Array = []  # Array of ShipSubcomponent
var dependency_ids: Array[String] = []

func _init(p_system_id: String = "", p_dependency_ids: Array[String] = []) -> void:
	system_id = p_system_id
	dependency_ids = p_dependency_ids.duplicate()
	subcomponents = []

func add_subcomponent(sub) -> void:
	subcomponents.append(sub)

func get_subcomponent(sub_id: String):
	for sub in subcomponents:
		if sub.subcomponent_id == sub_id:
			return sub
	return null

## Health of the weakest subcomponent (a system is only as good as its worst
## part). Returns 1.0 when there are no subcomponents.
func health() -> float:
	if subcomponents.is_empty():
		return 1.0
	var lowest: float = 1.0
	for sub in subcomponents:
		lowest = minf(lowest, sub.health)
	return lowest

func is_self_functional() -> bool:
	for sub in subcomponents:
		if not sub.is_functional():
			return false
	return true

## Base systems have no model-level time effect. Subclasses (LifeSupportSystem)
## override this. `operational` is the manager-resolved status for this system.
func advance(_delta: float, _operational: bool) -> void:
	pass

func get_summary() -> Dictionary:
	var subs: Array = []
	for sub in subcomponents:
		subs.append(sub.get_summary())
	return {
		"system_id": system_id,
		"dependency_ids": dependency_ids.duplicate(),
		"subcomponents": subs,
	}

func apply_summary(summary: Dictionary) -> bool:
	if summary == null or summary.is_empty():
		return false
	var changed: bool = false
	var subs_variant: Variant = summary.get("subcomponents", [])
	if typeof(subs_variant) == TYPE_ARRAY:
		for sub_summary in (subs_variant as Array):
			if typeof(sub_summary) != TYPE_DICTIONARY:
				continue
			var sub = get_subcomponent(str((sub_summary as Dictionary).get("subcomponent_id", "")))
			if sub != null and sub.apply_summary(sub_summary):
				changed = true
	return changed
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ship_system_smoke.gd
```
Expected: `SHIP SYSTEM PASS health=weakest_link self_functional=ok advance_noop=ok round_trip=ok`.

- [ ] **Step 5: Commit**

```bash
git add scripts/systems/ship_system.gd scripts/validation/ship_system_smoke.gd
git commit -m "feat(systems): add ShipSystem base with derived health"
```

---

## Task 3: LifeSupportSystem

**Files:**
- Create: `scripts/systems/life_support_system.gd`
- Test: `scripts/validation/life_support_system_smoke.gd`

**Interfaces:**
- Consumes: `ShipSystem` (Task 2), `OxygenState` (`scripts/systems/oxygen_state.gd`, existing — drains via `tick(delta, {"player_in_breach_zone": bool})`, exposes `var oxygen: float`).
- Produces:
  - `LifeSupportSystem.new(system_id: String, dependency_ids: Array[String])`
  - `get_oxygen_state()` returning the owned `OxygenState`
  - overrides `advance(delta, operational)`: drains oxygen when `operational == false`, regenerates when `true`
  - overrides `get_summary()` / `apply_summary()` to nest the oxygen summary under key `"oxygen"`

- [ ] **Step 1: Write the failing test**

Create `scripts/validation/life_support_system_smoke.gd`:

```gdscript
extends SceneTree

const LifeSupportScript := preload("res://scripts/systems/life_support_system.gd")
const SubScript := preload("res://scripts/systems/ship_subcomponent.gd")

func _initialize() -> void:
	var deps: Array[String] = ["power"]
	var ls = LifeSupportScript.new("life_support", deps)
	ls.add_subcomponent(SubScript.new("air_recycler", [], [], 0, 5.0, 0.5))

	var oxy = ls.get_oxygen_state()
	if oxy == null:
		push_error("LIFE SUPPORT SYSTEM FAIL no oxygen state")
		quit(1)
		return
	var start_oxygen: float = oxy.oxygen

	# Offline -> oxygen drains.
	ls.advance(1.0, false)
	if ls.get_oxygen_state().oxygen >= start_oxygen:
		push_error("LIFE SUPPORT SYSTEM FAIL offline did not drain oxygen (%f -> %f)" % [start_oxygen, ls.get_oxygen_state().oxygen])
		quit(1)
		return
	var drained_oxygen: float = ls.get_oxygen_state().oxygen

	# Operational -> oxygen recovers (does not drain further).
	ls.advance(1.0, true)
	if ls.get_oxygen_state().oxygen < drained_oxygen:
		push_error("LIFE SUPPORT SYSTEM FAIL operational drained oxygen further")
		quit(1)
		return

	# Summary nests oxygen and round-trips.
	var summary: Dictionary = ls.get_summary()
	if typeof(summary.get("oxygen", null)) != TYPE_DICTIONARY:
		push_error("LIFE SUPPORT SYSTEM FAIL summary missing nested oxygen dict")
		quit(1)
		return
	# Drive a fresh instance to a different oxygen level, then restore.
	var fresh = LifeSupportScript.new("life_support", deps)
	fresh.add_subcomponent(SubScript.new("air_recycler", [], [], 0, 5.0, 0.5))
	fresh.advance(2.0, false)  # drain it to a different value
	if not fresh.apply_summary(summary):
		push_error("LIFE SUPPORT SYSTEM FAIL apply_summary reported no change")
		quit(1)
		return
	if absf(fresh.get_oxygen_state().oxygen - ls.get_oxygen_state().oxygen) > 0.0001:
		push_error("LIFE SUPPORT SYSTEM FAIL round-trip oxygen mismatch (%f vs %f)" % [fresh.get_oxygen_state().oxygen, ls.get_oxygen_state().oxygen])
		quit(1)
		return

	print("LIFE SUPPORT SYSTEM PASS offline_drains=ok online_holds=ok oxygen_round_trip=ok")
	quit(0)
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/life_support_system_smoke.gd
```
Expected: FAIL — `life_support_system.gd` does not exist.

- [ ] **Step 3: Write the implementation**

Create `scripts/systems/life_support_system.gd`:

```gdscript
extends "res://scripts/systems/ship_system.gd"
class_name LifeSupportSystem

## The one system with a model-level time effect: it owns an OxygenState and
## drains it while Life Support is not operational. Reuses the existing
## OxygenState drain semantics by mapping "life support offline" onto the
## oxygen model's "player_in_breach_zone" gate.

const OxygenStateScript := preload("res://scripts/systems/oxygen_state.gd")

var oxygen_state

func _init(p_system_id: String = "life_support", p_dependency_ids: Array[String] = []) -> void:
	super(p_system_id, p_dependency_ids)
	oxygen_state = OxygenStateScript.new()
	# Configure with a single zone so breach_open == true and the model is in
	# its drainable state; we never seal it. Drain/regen is then gated purely
	# by the operational flag we pass into tick().
	oxygen_state.configure({"zone_ids": ["life_support"]})

func get_oxygen_state():
	return oxygen_state

## Offline -> oxygen drains (player_in_breach_zone == true). Operational ->
## oxygen regenerates per the OxygenState model.
func advance(delta: float, operational: bool) -> void:
	oxygen_state.tick(delta, {"player_in_breach_zone": not operational})

func get_summary() -> Dictionary:
	var base: Dictionary = super.get_summary()
	base["oxygen"] = oxygen_state.get_summary()
	return base

func apply_summary(summary: Dictionary) -> bool:
	var changed: bool = super.apply_summary(summary)
	var oxy_variant: Variant = summary.get("oxygen", null)
	if typeof(oxy_variant) == TYPE_DICTIONARY:
		if oxygen_state.apply_summary(oxy_variant):
			changed = true
	return changed
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/life_support_system_smoke.gd
```
Expected: `LIFE SUPPORT SYSTEM PASS offline_drains=ok online_holds=ok oxygen_round_trip=ok`.

- [ ] **Step 5: Commit**

```bash
git add scripts/systems/life_support_system.gd scripts/validation/life_support_system_smoke.gd
git commit -m "feat(systems): add LifeSupportSystem wrapping OxygenState"
```

---

## Task 4: systems.json definitions

**Files:**
- Create: `data/ship_systems/systems.json`
- Test: `scripts/validation/ship_systems_definitions_smoke.gd`

**Interfaces:**
- Produces: a JSON object `{"systems": [ {system_id, dependency_ids[], subcomponents:[{subcomponent_id, required_parts[], required_tools[], min_skill, repair_seconds, operational_threshold}]} ]}` with exactly the 6 systems and 3 subcomponents each, and dependency ids that reference only defined systems.

- [ ] **Step 1: Write the failing test**

Create `scripts/validation/ship_systems_definitions_smoke.gd`:

```gdscript
extends SceneTree

const DEFINITIONS_PATH := "res://data/ship_systems/systems.json"

const EXPECTED := {
	"power": [],
	"life_support": ["power"],
	"gravity": ["power"],
	"navigation": ["power"],
	"propulsion": ["power", "navigation"],
	"scanners": ["power", "navigation"],
}

func _initialize() -> void:
	var text: String = FileAccess.get_file_as_string(DEFINITIONS_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("SHIP SYSTEMS DEFINITIONS FAIL not a JSON object")
		quit(1)
		return
	var systems_variant: Variant = (parsed as Dictionary).get("systems", null)
	if typeof(systems_variant) != TYPE_ARRAY:
		push_error("SHIP SYSTEMS DEFINITIONS FAIL missing systems array")
		quit(1)
		return
	var systems: Array = systems_variant
	if systems.size() != 6:
		push_error("SHIP SYSTEMS DEFINITIONS FAIL expected 6 systems, got %d" % systems.size())
		quit(1)
		return

	var seen_ids: Array[String] = []
	for sys_variant in systems:
		if typeof(sys_variant) != TYPE_DICTIONARY:
			push_error("SHIP SYSTEMS DEFINITIONS FAIL system is not an object")
			quit(1)
			return
		var sys: Dictionary = sys_variant
		var sid: String = str(sys.get("system_id", ""))
		if not EXPECTED.has(sid):
			push_error("SHIP SYSTEMS DEFINITIONS FAIL unexpected system_id '%s'" % sid)
			quit(1)
			return
		seen_ids.append(sid)
		# Dependencies match the expected graph.
		var deps: Array = sys.get("dependency_ids", [])
		var dep_strs: Array[String] = []
		for d in deps:
			dep_strs.append(str(d))
		if dep_strs != EXPECTED[sid]:
			push_error("SHIP SYSTEMS DEFINITIONS FAIL %s deps=%s expected=%s" % [sid, str(dep_strs), str(EXPECTED[sid])])
			quit(1)
			return
		# Exactly 3 subcomponents, each with the required keys.
		var subs: Array = sys.get("subcomponents", [])
		if subs.size() != 3:
			push_error("SHIP SYSTEMS DEFINITIONS FAIL %s expected 3 subcomponents, got %d" % [sid, subs.size()])
			quit(1)
			return
		for sub_variant in subs:
			if typeof(sub_variant) != TYPE_DICTIONARY:
				push_error("SHIP SYSTEMS DEFINITIONS FAIL %s subcomponent not an object" % sid)
				quit(1)
				return
			var sub: Dictionary = sub_variant
			for key in ["subcomponent_id", "required_parts", "required_tools", "min_skill", "repair_seconds"]:
				if not sub.has(key):
					push_error("SHIP SYSTEMS DEFINITIONS FAIL %s subcomponent missing key '%s'" % [sid, key])
					quit(1)
					return

	for expected_id in EXPECTED.keys():
		if expected_id not in seen_ids:
			push_error("SHIP SYSTEMS DEFINITIONS FAIL missing system '%s'" % expected_id)
			quit(1)
			return

	print("SHIP SYSTEMS DEFINITIONS PASS systems=6 subcomponents=18 deps=ok")
	quit(0)
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ship_systems_definitions_smoke.gd
```
Expected: FAIL — `systems.json` does not exist (empty file string → not a JSON object).

- [ ] **Step 3: Write the data file**

Create `data/ship_systems/systems.json`:

```json
{
  "schema_version": "1.0.0",
  "systems": [
    {
      "system_id": "power",
      "dependency_ids": [],
      "subcomponents": [
        {"subcomponent_id": "reactor_core", "required_parts": ["reactor_core"], "required_tools": ["plasma_cutter"], "min_skill": 4, "repair_seconds": 20.0, "operational_threshold": 0.5},
        {"subcomponent_id": "power_distribution", "required_parts": ["power_cell"], "required_tools": ["welder"], "min_skill": 2, "repair_seconds": 10.0, "operational_threshold": 0.5},
        {"subcomponent_id": "battery_cells", "required_parts": ["power_cell"], "required_tools": [], "min_skill": 1, "repair_seconds": 6.0, "operational_threshold": 0.5}
      ]
    },
    {
      "system_id": "life_support",
      "dependency_ids": ["power"],
      "subcomponents": [
        {"subcomponent_id": "air_recycler", "required_parts": ["oxygen_filter"], "required_tools": ["welder"], "min_skill": 2, "repair_seconds": 12.0, "operational_threshold": 0.5},
        {"subcomponent_id": "co2_scrubber", "required_parts": ["oxygen_filter"], "required_tools": [], "min_skill": 1, "repair_seconds": 8.0, "operational_threshold": 0.5},
        {"subcomponent_id": "oxygen_tanks", "required_parts": ["sealant"], "required_tools": ["welder"], "min_skill": 2, "repair_seconds": 10.0, "operational_threshold": 0.5}
      ]
    },
    {
      "system_id": "gravity",
      "dependency_ids": ["power"],
      "subcomponents": [
        {"subcomponent_id": "gravity_plating", "required_parts": ["plating"], "required_tools": ["welder"], "min_skill": 3, "repair_seconds": 14.0, "operational_threshold": 0.5},
        {"subcomponent_id": "field_emitter", "required_parts": ["circuit_board"], "required_tools": ["welder"], "min_skill": 3, "repair_seconds": 12.0, "operational_threshold": 0.5},
        {"subcomponent_id": "inertial_dampeners", "required_parts": ["circuit_board"], "required_tools": [], "min_skill": 2, "repair_seconds": 9.0, "operational_threshold": 0.5}
      ]
    },
    {
      "system_id": "navigation",
      "dependency_ids": ["power"],
      "subcomponents": [
        {"subcomponent_id": "star_charts", "required_parts": ["data_core"], "required_tools": [], "min_skill": 1, "repair_seconds": 6.0, "operational_threshold": 0.5},
        {"subcomponent_id": "nav_computer", "required_parts": ["circuit_board"], "required_tools": ["welder"], "min_skill": 3, "repair_seconds": 12.0, "operational_threshold": 0.5},
        {"subcomponent_id": "sensor_array", "required_parts": ["sensor_module"], "required_tools": ["welder"], "min_skill": 2, "repair_seconds": 10.0, "operational_threshold": 0.5}
      ]
    },
    {
      "system_id": "propulsion",
      "dependency_ids": ["power", "navigation"],
      "subcomponents": [
        {"subcomponent_id": "thruster_array", "required_parts": ["thruster_nozzle"], "required_tools": ["plasma_cutter"], "min_skill": 4, "repair_seconds": 18.0, "operational_threshold": 0.5},
        {"subcomponent_id": "fuel_injection", "required_parts": ["fuel_line"], "required_tools": ["welder"], "min_skill": 3, "repair_seconds": 12.0, "operational_threshold": 0.5},
        {"subcomponent_id": "nav_linkage", "required_parts": ["circuit_board"], "required_tools": [], "min_skill": 2, "repair_seconds": 8.0, "operational_threshold": 0.5}
      ]
    },
    {
      "system_id": "scanners",
      "dependency_ids": ["power", "navigation"],
      "subcomponents": [
        {"subcomponent_id": "scanner_dish", "required_parts": ["sensor_module"], "required_tools": ["welder"], "min_skill": 3, "repair_seconds": 12.0, "operational_threshold": 0.5},
        {"subcomponent_id": "signal_processor", "required_parts": ["circuit_board"], "required_tools": ["welder"], "min_skill": 3, "repair_seconds": 11.0, "operational_threshold": 0.5},
        {"subcomponent_id": "power_coupling", "required_parts": ["power_cell"], "required_tools": [], "min_skill": 2, "repair_seconds": 7.0, "operational_threshold": 0.5}
      ]
    }
  ]
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ship_systems_definitions_smoke.gd
```
Expected: `SHIP SYSTEMS DEFINITIONS PASS systems=6 subcomponents=18 deps=ok`.

- [ ] **Step 5: Commit**

```bash
git add data/ship_systems/systems.json scripts/validation/ship_systems_definitions_smoke.gd
git commit -m "feat(systems): add ship systems data definitions"
```

---

## Task 5: ShipSystemsManager — configure + derived cascade

**Files:**
- Create: `scripts/systems/ship_systems_manager.gd`
- Test: `scripts/validation/ship_systems_manager_smoke.gd`

**Interfaces:**
- Consumes: `ShipSystem`, `LifeSupportSystem`, `ShipSubcomponent`, `systems.json`.
- Produces:
  - `ShipSystemsManager.new()`
  - `configure(definitions: Dictionary, condition: int, seed_value: int) -> void` — builds systems and applies deterministic condition damage. Condition ints: `0` pristine, `1` damaged, `2` wrecked (mirror `ShipBlueprint.Condition`).
  - `load_definitions() -> Dictionary` — reads/parses `res://data/ship_systems/systems.json`.
  - `get_system(system_id: String) -> ShipSystem`
  - `is_operational(system_id: String) -> bool` — derived, dependency-aware, cycle-safe.
  - `var system_order: Array[String]`, `var systems: Dictionary`
  - (Repair/advance/summary are added in Task 6.)

- [ ] **Step 1: Write the failing test**

Create `scripts/validation/ship_systems_manager_smoke.gd` (Task 6 extends this same file):

```gdscript
extends SceneTree

const ManagerScript := preload("res://scripts/systems/ship_systems_manager.gd")

func _count_damaged(mgr) -> int:
	var n: int = 0
	for sid in mgr.system_order:
		for sub in mgr.get_system(sid).subcomponents:
			if sub.health < sub.operational_threshold:
				n += 1
	return n

func _initialize() -> void:
	var defs: Dictionary = ManagerScript.new().load_definitions()
	if defs.is_empty():
		push_error("SHIP SYSTEMS MANAGER FAIL could not load definitions")
		quit(1)
		return

	# --- Determinism + condition severity ---
	var pristine = ManagerScript.new()
	pristine.configure(defs, 0, 4242)
	if _count_damaged(pristine) != 0:
		push_error("SHIP SYSTEMS MANAGER FAIL pristine has damage: %d" % _count_damaged(pristine))
		quit(1)
		return

	var damaged_a = ManagerScript.new()
	damaged_a.configure(defs, 1, 4242)
	var damaged_b = ManagerScript.new()
	damaged_b.configure(defs, 1, 4242)
	if damaged_a.get_summary_health_list() != damaged_b.get_summary_health_list():
		push_error("SHIP SYSTEMS MANAGER FAIL same seed/condition not deterministic")
		quit(1)
		return
	var damaged_count: int = _count_damaged(damaged_a)
	if damaged_count < 1:
		push_error("SHIP SYSTEMS MANAGER FAIL damaged condition produced no damage")
		quit(1)
		return

	var wrecked = ManagerScript.new()
	wrecked.configure(defs, 2, 4242)
	if _count_damaged(wrecked) < damaged_count:
		push_error("SHIP SYSTEMS MANAGER FAIL wrecked(%d) not >= damaged(%d)" % [_count_damaged(wrecked), damaged_count])
		quit(1)
		return

	# --- Dependency cascade ---
	var mgr = ManagerScript.new()
	mgr.configure(defs, 0, 1)  # pristine: everything operational
	for sid in ["power", "life_support", "gravity", "navigation", "propulsion", "scanners"]:
		if not mgr.is_operational(sid):
			push_error("SHIP SYSTEMS MANAGER FAIL pristine %s not operational" % sid)
			quit(1)
			return

	# Break Power -> all dependents cascade offline.
	mgr.get_system("power").get_subcomponent("reactor_core").health = 0.0
	if mgr.is_operational("power"):
		push_error("SHIP SYSTEMS MANAGER FAIL power still operational after break")
		quit(1)
		return
	for sid in ["life_support", "gravity", "navigation", "propulsion", "scanners"]:
		if mgr.is_operational(sid):
			push_error("SHIP SYSTEMS MANAGER FAIL %s operational while power down" % sid)
			quit(1)
			return

	# Repair Power back -> dependents that are themselves healthy come back.
	mgr.get_system("power").get_subcomponent("reactor_core").health = 1.0
	if not mgr.is_operational("life_support"):
		push_error("SHIP SYSTEMS MANAGER FAIL life_support did not recover after power restored")
		quit(1)
		return

	# Break navigation -> scanners + propulsion go offline (need navigation), but gravity stays up.
	mgr.get_system("navigation").get_subcomponent("nav_computer").health = 0.0
	if mgr.is_operational("scanners") or mgr.is_operational("propulsion"):
		push_error("SHIP SYSTEMS MANAGER FAIL scanners/propulsion up while navigation down")
		quit(1)
		return
	if not mgr.is_operational("gravity"):
		push_error("SHIP SYSTEMS MANAGER FAIL gravity wrongly offline (only deps on power)")
		quit(1)
		return

	print("SHIP SYSTEMS MANAGER PASS determinism=ok cascade=ok")
	quit(0)
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ship_systems_manager_smoke.gd
```
Expected: FAIL — `ship_systems_manager.gd` does not exist.

- [ ] **Step 3: Write the implementation**

Create `scripts/systems/ship_systems_manager.gd`:

```gdscript
extends RefCounted
class_name ShipSystemsManager

## Owns the six ship systems, resolves dependency cascades on demand, and
## (Task 6) drives time effects and repair. Pure data model — no scene tree.

const ShipSystemScript := preload("res://scripts/systems/ship_system.gd")
const LifeSupportSystemScript := preload("res://scripts/systems/life_support_system.gd")
const ShipSubcomponentScript := preload("res://scripts/systems/ship_subcomponent.gd")

const DEFINITIONS_PATH := "res://data/ship_systems/systems.json"

# Mirrors ShipBlueprint.Condition (PRISTINE=0, DAMAGED=1, WRECKED=2).
const CONDITION_PRISTINE := 0
const CONDITION_DAMAGED := 1
const CONDITION_WRECKED := 2

const DAMAGED_HEALTH := 0.2  # health a "broken" subcomponent is set to

var systems: Dictionary = {}            # system_id -> ShipSystem
var system_order: Array[String] = []

func load_definitions() -> Dictionary:
	var text: String = FileAccess.get_file_as_string(DEFINITIONS_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed

func configure(definitions: Dictionary, condition: int, seed_value: int) -> void:
	systems.clear()
	system_order.clear()
	var systems_variant: Variant = definitions.get("systems", [])
	if typeof(systems_variant) != TYPE_ARRAY:
		return
	for sys_variant in (systems_variant as Array):
		if typeof(sys_variant) != TYPE_DICTIONARY:
			continue
		var sys_def: Dictionary = sys_variant
		var sid: String = str(sys_def.get("system_id", ""))
		if sid.is_empty():
			continue
		var deps: Array[String] = []
		for d in sys_def.get("dependency_ids", []):
			deps.append(str(d))
		var system
		if sid == "life_support":
			system = LifeSupportSystemScript.new(sid, deps)
		else:
			system = ShipSystemScript.new(sid, deps)
		for sub_variant in sys_def.get("subcomponents", []):
			if typeof(sub_variant) != TYPE_DICTIONARY:
				continue
			var sub_def: Dictionary = sub_variant
			var parts: Array[String] = []
			for p in sub_def.get("required_parts", []):
				parts.append(str(p))
			var tools: Array[String] = []
			for t in sub_def.get("required_tools", []):
				tools.append(str(t))
			var sub = ShipSubcomponentScript.new(
				str(sub_def.get("subcomponent_id", "")),
				parts,
				tools,
				int(sub_def.get("min_skill", 0)),
				float(sub_def.get("repair_seconds", 5.0)),
				float(sub_def.get("operational_threshold", 0.5)))
			system.add_subcomponent(sub)
		systems[sid] = system
		system_order.append(sid)
	_apply_condition_damage(condition, seed_value)

## Deterministically damages subcomponents based on condition. A seeded RNG
## walks subcomponents in declaration order so the same (condition, seed)
## always produces the same damage set.
func _apply_condition_damage(condition: int, seed_value: int) -> void:
	var break_chance: float = 0.0
	match condition:
		CONDITION_PRISTINE:
			break_chance = 0.0
		CONDITION_DAMAGED:
			break_chance = 0.4
		CONDITION_WRECKED:
			break_chance = 0.8
		_:
			break_chance = 0.0
	if break_chance <= 0.0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for sid in system_order:
		for sub in systems[sid].subcomponents:
			if rng.randf() < break_chance:
				sub.health = DAMAGED_HEALTH

func get_system(system_id: String):
	return systems.get(system_id, null)

## Derived operational status: self-functional AND every dependency operational.
## Cycle-safe via the visiting set (no cycles are expected in the data).
func is_operational(system_id: String) -> bool:
	return _resolve_operational(system_id, {})

func _resolve_operational(system_id: String, visiting: Dictionary) -> bool:
	if not systems.has(system_id):
		return false
	if visiting.has(system_id):
		return false
	var system = systems[system_id]
	if not system.is_self_functional():
		return false
	visiting[system_id] = true
	for dep in system.dependency_ids:
		if not _resolve_operational(dep, visiting):
			visiting.erase(system_id)
			return false
	visiting.erase(system_id)
	return true

## Flat, ordered list of every subcomponent health — used by smokes to assert
## deterministic builds without depending on dictionary ordering.
func get_summary_health_list() -> Array:
	var out: Array = []
	for sid in system_order:
		for sub in systems[sid].subcomponents:
			out.append(sub.health)
	return out
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ship_systems_manager_smoke.gd
```
Expected: `SHIP SYSTEMS MANAGER PASS determinism=ok cascade=ok`.

- [ ] **Step 5: Commit**

```bash
git add scripts/systems/ship_systems_manager.gd scripts/validation/ship_systems_manager_smoke.gd
git commit -m "feat(systems): add ShipSystemsManager with derived dependency cascade"
```

---

## Task 6: ShipSystemsManager — advance, repair, round-trip + bundle registration

**Files:**
- Modify: `scripts/systems/ship_systems_manager.gd` (add `advance`, `repair`, `get_status_summary`, `get_summary`, `apply_summary`)
- Modify: `scripts/validation/ship_systems_manager_smoke.gd` (extend assertions; change final PASS line)
- Modify: `docs/game/06_validation_plan.md` (register the 5 new smokes; bump `commands` count)

**Interfaces:**
- Consumes: everything from Task 5.
- Produces:
  - `advance(delta: float) -> void` — ticks each system with its resolved operational status.
  - `repair(system_id, subcomponent_id, available_parts: Array, available_tools: Array, skill_level: int) -> Dictionary` — `{success, reason, seconds}`; reasons add `unknown_system`, `unknown_subcomponent`.
  - `get_status_summary() -> Dictionary` — `system_id -> {operational: bool, health: float}`.
  - `get_summary() -> Dictionary`, `apply_summary(summary: Dictionary) -> bool`.

- [ ] **Step 1: Extend the test (add the new behavior, update PASS line)**

In `scripts/validation/ship_systems_manager_smoke.gd`, replace the final two lines:

```gdscript
	print("SHIP SYSTEMS MANAGER PASS determinism=ok cascade=ok")
	quit(0)
```

with this block (keeps all earlier checks; `mgr` is still in scope):

```gdscript
	# --- advance(): life support drains oxygen only when offline ---
	var ship = ManagerScript.new()
	ship.configure(defs, 0, 1)  # pristine, all operational
	var ls = ship.get_system("life_support")
	var oxy_start: float = ls.get_oxygen_state().oxygen
	ship.advance(1.0)  # all operational -> no drain
	if ls.get_oxygen_state().oxygen < oxy_start:
		push_error("SHIP SYSTEMS MANAGER FAIL operational life support drained oxygen")
		quit(1)
		return
	# Knock out power so life support cascades offline, then advance.
	ship.get_system("power").get_subcomponent("reactor_core").health = 0.0
	var oxy_before: float = ls.get_oxygen_state().oxygen
	ship.advance(1.0)
	if ls.get_oxygen_state().oxygen >= oxy_before:
		push_error("SHIP SYSTEMS MANAGER FAIL offline life support did not drain oxygen")
		quit(1)
		return

	# --- repair() routes to the subcomponent and reports reasons ---
	var unknown_sys: Dictionary = ship.repair("warp", "x", [], [], 9)
	if str(unknown_sys.get("reason", "")) != "unknown_system":
		push_error("SHIP SYSTEMS MANAGER FAIL expected unknown_system, got %s" % str(unknown_sys))
		quit(1)
		return
	var unknown_sub: Dictionary = ship.repair("power", "nope", [], [], 9)
	if str(unknown_sub.get("reason", "")) != "unknown_subcomponent":
		push_error("SHIP SYSTEMS MANAGER FAIL expected unknown_subcomponent, got %s" % str(unknown_sub))
		quit(1)
		return
	# reactor_core needs reactor_core part + plasma_cutter tool + skill 4.
	var bad: Dictionary = ship.repair("power", "reactor_core", [], [], 9)
	if bad.get("success", true):
		push_error("SHIP SYSTEMS MANAGER FAIL repair succeeded without parts/tools")
		quit(1)
		return
	var ok: Dictionary = ship.repair("power", "reactor_core", ["reactor_core"], ["plasma_cutter"], 4)
	if not ok.get("success", false):
		push_error("SHIP SYSTEMS MANAGER FAIL valid repair failed: %s" % str(ok))
		quit(1)
		return
	if not ship.is_operational("power"):
		push_error("SHIP SYSTEMS MANAGER FAIL power not operational after repair")
		quit(1)
		return

	# --- status summary shape ---
	var status: Dictionary = ship.get_status_summary()
	if typeof(status.get("power", null)) != TYPE_DICTIONARY or not status["power"].has("operational"):
		push_error("SHIP SYSTEMS MANAGER FAIL status summary malformed")
		quit(1)
		return

	# --- full manager round-trip ---
	var src = ManagerScript.new()
	src.configure(defs, 1, 777)  # some damage
	var snap: Dictionary = src.get_summary()
	var dst = ManagerScript.new()
	dst.configure(defs, 0, 777)  # pristine, different state
	if not dst.apply_summary(snap):
		push_error("SHIP SYSTEMS MANAGER FAIL apply_summary reported no change")
		quit(1)
		return
	if dst.get_summary_health_list() != src.get_summary_health_list():
		push_error("SHIP SYSTEMS MANAGER FAIL round-trip health list mismatch")
		quit(1)
		return
	if dst.apply_summary({}):
		push_error("SHIP SYSTEMS MANAGER FAIL empty summary should be rejected")
		quit(1)
		return

	print("SHIP SYSTEMS MANAGER PASS determinism=ok cascade=ok advance=ok repair=ok round_trip=ok")
	quit(0)
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ship_systems_manager_smoke.gd
```
Expected: FAIL — `advance` / `repair` / `get_status_summary` / `get_summary` / `apply_summary` are not defined yet (runtime error, no PASS marker).

- [ ] **Step 3: Implement the new methods**

Append to `scripts/systems/ship_systems_manager.gd` (after `get_summary_health_list`):

```gdscript
## Ticks every system with its resolved operational status. Only LifeSupport
## acts on the time delta (oxygen drain when offline).
func advance(delta: float) -> void:
	for sid in system_order:
		systems[sid].advance(delta, is_operational(sid))

## Parameterized repair routed to the named subcomponent. Returns the
## subcomponent's RepairResult, or an unknown_system / unknown_subcomponent
## rejection.
func repair(system_id: String, subcomponent_id: String, available_parts: Array, available_tools: Array, skill_level: int) -> Dictionary:
	if not systems.has(system_id):
		return {"success": false, "reason": "unknown_system", "seconds": 0.0}
	var sub = systems[system_id].get_subcomponent(subcomponent_id)
	if sub == null:
		return {"success": false, "reason": "unknown_subcomponent", "seconds": 0.0}
	return sub.repair(available_parts, available_tools, skill_level)

func get_status_summary() -> Dictionary:
	var out: Dictionary = {}
	for sid in system_order:
		out[sid] = {"operational": is_operational(sid), "health": systems[sid].health()}
	return out

func get_summary() -> Dictionary:
	var sys_summaries: Dictionary = {}
	for sid in system_order:
		sys_summaries[sid] = systems[sid].get_summary()
	return {"systems": sys_summaries, "system_order": system_order.duplicate()}

func apply_summary(summary: Dictionary) -> bool:
	if summary == null or summary.is_empty():
		return false
	var sys_summaries_variant: Variant = summary.get("systems", {})
	if typeof(sys_summaries_variant) != TYPE_DICTIONARY:
		return false
	var changed: bool = false
	for sid in (sys_summaries_variant as Dictionary):
		if systems.has(sid):
			if systems[sid].apply_summary((sys_summaries_variant as Dictionary)[sid]):
				changed = true
	return changed
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ship_systems_manager_smoke.gd
```
Expected: `SHIP SYSTEMS MANAGER PASS determinism=ok cascade=ok advance=ok repair=ok round_trip=ok`.

- [ ] **Step 5: Register all five new smokes in the regression bundle**

In `docs/game/06_validation_plan.md`, inside the `## Regression bundle` script, add these five lines immediately before the final `echo 'SYNAPSE_SEA REGRESSION PASS ...'` line:

```bash
run_clean 'ship subcomponent smoke' 'SHIP SUBCOMPONENT PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ship_subcomponent_smoke.gd
run_clean 'ship system smoke' 'SHIP SYSTEM PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ship_system_smoke.gd
run_clean 'life support system smoke' 'LIFE SUPPORT SYSTEM PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/life_support_system_smoke.gd
run_clean 'ship systems definitions smoke' 'SHIP SYSTEMS DEFINITIONS PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ship_systems_definitions_smoke.gd
run_clean 'ship systems manager smoke' 'SHIP SYSTEMS MANAGER PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ship_systems_manager_smoke.gd
```

Then change the final line from `commands=42` to `commands=47`:

```bash
echo 'SYNAPSE_SEA REGRESSION PASS commands=47 clean_output=true'
```

Add a documentation bullet under `## Future validation additions`:

```markdown
- [x] Phase 2 ship-systems model smokes (System 2 / ADR-0008): `ship_subcomponent_smoke.gd` (`SHIP SUBCOMPONENT PASS`), `ship_system_smoke.gd` (`SHIP SYSTEM PASS`), `life_support_system_smoke.gd` (`LIFE SUPPORT SYSTEM PASS`), `ship_systems_definitions_smoke.gd` (`SHIP SYSTEMS DEFINITIONS PASS`), and `ship_systems_manager_smoke.gd` (`SHIP SYSTEMS MANAGER PASS` — the Phase 2 gate: deterministic build, dependency cascade, advance/oxygen-drain, parameterized repair, and full round-trip). All five added to the regression bundle. The manager is intentionally NOT yet wired into the live SaveLoadService snapshot (build-alongside; `summaries=7` unchanged).
```

- [ ] **Step 6: Run the full regression bundle to confirm 47/47 green**

Run (extract the bundle with Windows paths and execute, same method used in this repo):
```bash
awk '/^## Regression bundle/{f=1} f&&/^```bash/{c=1;next} f&&/^```/{if(c)exit} c{print}' docs/game/06_validation_plan.md \
  | sed "s#^ROOT=.*#ROOT=\"$ROOT\"#; s#^GODOT=.*#GODOT=\"$GODOT\"#" > /tmp/regression_bundle.sh
bash /tmp/regression_bundle.sh 2>&1 | tail -3
```
Expected final line: `SYNAPSE_SEA REGRESSION PASS commands=47 clean_output=true`.

- [ ] **Step 7: Commit**

```bash
git add scripts/systems/ship_systems_manager.gd scripts/validation/ship_systems_manager_smoke.gd docs/game/06_validation_plan.md
git commit -m "feat(systems): complete ShipSystemsManager (advance, repair, round-trip) and register Phase 2 smokes"
```

---

## Self-Review Notes

- **Spec coverage:** base class + manager (Tasks 2,5,6); subcomponents (Task 1); 6 systems data-driven (Task 4); dependency cascade derived/cycle-safe (Task 5); parameterized repair (Tasks 1,6); `advance` time effect via Life Support/OxygenState (Tasks 3,6); deterministic build from condition+seed (Task 5); `get_summary`/`apply_summary` round-trip at every level (Tasks 1,2,3,6); pure-model smoke + bundle registration (Task 6); no main-scene smoke and no SaveLoadService wiring (respected — Global Constraints + Task 6 doc note).
- **Deliberate spec deviation:** the spec said register only the manager smoke (`commands 42 → 43`); this plan registers all five new smokes (`42 → 47`) so the lower-level models are guarded too — leaving good smokes unregistered is precisely what let the Phase 1 regressions rot. Documented in Task 6.
- **Type consistency:** `repair(...)` returns `{success, reason, seconds}` everywhere; reasons are a fixed set (`ok`, `already_functional`, `missing_parts`, `missing_tools`, `insufficient_skill`, `unknown_system`, `unknown_subcomponent`). `health()` (method) vs `health` (subcomponent var) used consistently. `get_subcomponent`/`get_system` return `null` when absent and callers guard. Condition ints 0/1/2 match `ShipBlueprint.Condition`.
