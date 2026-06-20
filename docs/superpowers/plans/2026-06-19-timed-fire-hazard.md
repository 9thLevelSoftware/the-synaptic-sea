# Timed Fire Hazard Implementation Plan (REQ-010)

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Gate 2 timed fire-zone hazard on the main playable slice so that a single side-corridor fire zone cycles between `CLEARED` and `BURNING`, toggles real collision/passability, displays a localized Label3D state change, and proves the ship can host a second hazard pattern without coupling to oxygen, route gates, objectives, inventory, or extraction.

**Architecture:** Add a pure `FireState` model beside `OxygenState`, `ShipSystemState`, and `RouteControlState`. `PlayableGeneratedShip` owns a `FireRoot` (fire-zone collision segment + visual + Label3D) and applies scene consequences from the model's summary. The model decides phase and passability-block state from elapsed time only; the scene enables/disables collision on the fire-zone `StaticBody3D` and toggles the Label3D text between `FIRE CLEARED` and `FIRE BURNING — WAIT`. Mirror the breach-zone pattern so existing validation seams keep working and the new hazard is independent.

**Tech Stack:** Godot 4.6.2 GDScript, `SceneTree` validation smokes, existing `res://scenes/main.tscn`, existing `PlayableGeneratedShip`, existing `GeneratedShipLoader`, no external runtime dependencies.

## Global Constraints

- Project root: `/Users/christopherwilloughby/the-sargasso-of-stars`.
- Godot binary: `/Users/christopherwilloughby/.local/bin/godot-4.6.2`.
- Workspace state checked on 2026-06-19: `GIT_INSIDE=false`.
- Do not create HTML, PNG, contact sheets, screenshot galleries, or proof documents for this milestone.
- Use TDD: write failing smoke(s), run them red, then implement runtime code.
- The fire zone must change actual scene passability through collision state; updating the Label3D alone is not enough.
- Fire behavior must preserve the existing objective sequence and must not alter oxygen, route-control, inventory/tool, or extraction semantics.
- Fire must not drain oxygen, health, or any other resource; must not spread; must not be disabled by objectives, tools, or player interaction in Gate 2.
- The fire milestone has no proof artifacts as deliverables; validation is command-output smokes only.
- Preserve existing objective sequence and validation seams: `complete_objective_sequence_for_validation()`, `complete_all_objectives_for_validation()`, `complete_first_interaction_for_validation()`, and all existing Gate 1/2 smokes must keep passing unchanged.
- Output from validation commands must be clean of unexpected lines beginning with `ERROR:` or `WARNING:` (baseline Godot teardown noise already classified in `docs/game/06_validation_plan.md` may be filtered).
- Because this is not a git repository, every task uses the no-git ledger fallback at `/tmp/sargasso_timed_fire_no_git_changes.log` instead of assuming `git commit` works.
- Do not collapse `FireState` into `OxygenState`, `ShipSystemState`, or `RouteControlState`; keep separate responsibility, parallel to the oxygen architecture.
- Do not delete the fire-zone node when toggling phases — enable/disable collision, update metadata, and toggle the Label3D so the state remains inspectable.
- Do not introduce health/damage-over-time, fire spread, audio cues, particle VFX, lighting changes, random ignition, procedural placement, or fire-oxygen interaction.
- Fire cycle durations are tunables — they live on the model as constants and are printed by the smokes so they are visible from validation output.
- Add both new smokes to the regression bundle in `docs/game/06_validation_plan.md` before marking the downstream implementation card done.

---

## File Structure

Create:

- `scripts/systems/fire_state.gd`
  - Pure runtime model for the timed fire-zone cycle.
  - Extends `RefCounted`, class_name `FireState`.
  - No scene-tree access.
  - Mirrors the `OxygenState` shape: `configure(...)`, `tick(...)`, `get_summary()`, `get_status_lines()`, plus `is_passability_blocked()`.
  - Carries tunables as class constants: `DEFAULT_BURN_DURATION: float = 4.0`, `DEFAULT_CLEAR_DURATION: float = 3.0`.
  - State machine: `enum Phase { CLEARED = 0, BURNING = 1 }`; starts in `CLEARED` with `time_in_phase = 0.0`.
  - `configure(zone_ids: Array, burn_duration: float, clear_duration: float)` clamps durations to a minimum of `0.1s`.
  - `tick(delta_seconds: float) -> bool` advances `time_in_phase`, flips phase when duration elapses, carries remainder into next phase, and returns `true` if phase or passability changed.
  - `get_summary()` returns `state` (String `"CLEARED"` / `"BURNING"`), `phase` (int), `time_in_state`, `cycle_duration`, `burning`, `passability_blocked`, `burn_duration`, `clear_duration`, `zone_ids`.
  - `get_status_lines()` returns a single localized line, e.g. `"Fire: CLEARED"` / `"Fire: BURNING — WAIT"`.

- `scripts/validation/fire_state_smoke.gd`
  - Direct model smoke for `FireState`.
  - Verifies initial `CLEARED`, phase transitions after `clear_duration` and `burn_duration`, passability toggles, two full cycles, and summary keys.
  - Pass marker: `FIRE STATE PASS cycles=2 phases=4 passability_switches=4`.

- `scripts/validation/main_playable_slice_fire_smoke.gd`
  - Main-scene runtime smoke for the fire zone.
  - Verifies `FireState` exists on `PlayableGeneratedShip`, the fire-zone scene node exists, initial state is `CLEARED`, collision is disabled while cleared, enabled while burning, and the zone completes two cycles in the live scene.
  - Pass marker: `MAIN PLAYABLE FIRE PASS state=CLEARED cycles=2 blocked_burning=true blocked_cleared=false`.

Modify:

- `scripts/procgen/generated_ship_loader.gd`
  - Add optional `fire_zones` to the loader output.
  - Read `layout_doc.get("fire_zones", [])` and expose a new accessor `get_fire_zone_markers() -> Array[Vector3]`.
  - Missing/null is treated as an empty array; the scene coordinator injects a fixed Gate 2 fallback fire zone in a side corridor so existing fixtures still validate.

- `scripts/procgen/playable_generated_ship.gd`
  - Preload and own `FireState`.
  - Add `fire_state`, `fire_root: Node3D`, `fire_zone_node: StaticBody3D`, `fire_zone_label: Label3D`.
  - Add constants:
    - `FIRE_ZONE_FALLBACK_ID: String = "side_corridor_fire"`
    - `FIRE_ZONE_FALLBACK_ROOM_ID: String = "corridor_01"` (side corridor, not the objective 3 → 4 breach corridor)
    - `FIRE_ZONE_COLLISION_SIZE: Vector3 = Vector3(2.6, 2.2, 1.6)`
    - `FIRE_ZONE_VISUAL_COLOR_CLEARED: Color = Color(0.18, 0.75, 1.0, 0.35)`
    - `FIRE_ZONE_VISUAL_COLOR_BURNING: Color = Color(1.0, 0.22, 0.18, 0.82)`
    - `FIRE_ZONE_LABEL_TEXT_CLEARED: String = "FIRE CLEARED"`
    - `FIRE_ZONE_LABEL_TEXT_BURNING: String = "FIRE BURNING — WAIT"`
  - In `_build_runtime_nodes()`: create `fire_root = Node3D.new()` named `"FireRoot"`, add it as a child; instantiate `fire_state = FireStateScript.new()`.
  - In `_on_ship_loaded(...)` after `_build_breach_zone()`: call `_build_fire_zone()` then `_refresh_fire_state(true)` so the initial `CLEARED` state is applied.
  - In `_process(delta)` after the existing oxygen refresh: if `fire_state != null`, call `fire_state.tick(delta)` then `_refresh_fire_state(false)`.
  - Add helpers `get_fire_summary() -> Dictionary`, `get_fire_zone_node() -> Node`, `get_fire_zone_collision_enabled_count() -> int`, `teleport_player_to_fire_zone_for_validation() -> bool`.
  - Keep fire status lines out of the global HUD by default (localized Label3D only). Do not append fire lines to `_combined_system_status_lines()` unless the downstream reviewer explicitly asks; the spec deliberately reserves the global HUD line for oxygen.
  - Ensure fire zone id does not overlap with breach zone id (`corridor_to_reactor`).

- `docs/game/06_validation_plan.md`
  - Add `fire_state_smoke` and `main_playable_slice_fire_smoke` to the regression bundle.
  - Update the "Future validation additions" section to mark fire hazard smokes as in-progress/done.

Generated by Godot if import/class registration runs:

- `scripts/systems/fire_state.gd.uid`
  - Accept this sidecar if Godot creates it.
  - Record it in the no-git ledger.

---

### Task 1: Fire Model Smoke, RED Phase

**Files:**
- Create: `scripts/validation/fire_state_smoke.gd`
- Read: `scripts/validation/oxygen_state_smoke.gd` (template)
- Read: `scripts/systems/route_control_state.gd` (mirror shape)

**Interfaces:**
- Consumes intended future class: `FireState.new()`.
- Consumes intended future methods:
  - `configure(zone_ids: Array, burn_duration: float, clear_duration: float)`
  - `tick(delta_seconds: float) -> bool`
  - `get_summary() -> Dictionary`
  - `get_status_lines() -> PackedStringArray`
  - `is_passability_blocked() -> bool`
- Produces a failing model smoke with pass marker:
  - `FIRE STATE PASS cycles=2 phases=4 passability_switches=4`

- [ ] **Step 1: Create the failing model smoke**

Write `scripts/validation/fire_state_smoke.gd` with this complete content:

```gdscript
extends SceneTree

func _initialize() -> void:
	var model := FireState.new()
	model.configure(
		["side_corridor_fire"],
		4.0,
		3.0
	)

	var initial: Dictionary = model.get_summary()
	if str(initial.get("state", "")) != "CLEARED":
		_fail("initial state should be CLEARED, got %s" % str(initial.get("state", "")))
		return
	if float(initial.get("time_in_state", -1.0)) != 0.0:
		_fail("initial time_in_state should be 0.0, got %s" % str(initial.get("time_in_state", -1.0)))
		return
	if bool(initial.get("passability_blocked", true)):
		_fail("initial passability_blocked should be false")
		return
	if bool(initial.get("burning", true)):
		_fail("initial burning should be false")
		return
	if not model.has_method("is_passability_blocked") or model.is_passability_blocked():
		_fail("initial is_passability_blocked should be false")
		return

	var cycles: int = 0
	var phases: int = 0
	var passability_switches: int = 0
	var last_blocked: bool = model.is_passability_blocked()
	var last_phase: int = int(initial.get("phase", 0))

	# Advance through two full cycles: CLEARED -> BURNING -> CLEARED -> BURNING -> CLEARED.
	while cycles < 2:
		var before: Dictionary = model.get_summary()
		var before_phase: int = int(before.get("phase", 0))
		var remaining: float = float(before.get("remaining_in_state", 0.0))
		if remaining <= 0.0:
			remaining = float(before.get("burn_duration" if before_phase == 1 else "clear_duration", 0.0))
		# Tick exactly the remaining time to force a phase transition.
		model.tick(remaining)
		var after: Dictionary = model.get_summary()
		var after_phase: int = int(after.get("phase", 0))
		if after_phase != before_phase:
			phases += 1
			last_phase = after_phase
		var after_blocked: bool = bool(after.get("passability_blocked", false))
		if after_blocked != last_blocked:
			passability_switches += 1
			last_blocked = after_blocked
		# Count a completed cycle when we return to CLEARED from BURNING.
		if before_phase == 1 and after_phase == 0:
			cycles += 1

	var final: Dictionary = model.get_summary()
	if str(final.get("state", "")) != "CLEARED":
		_fail("after two cycles state should be CLEARED, got %s" % str(final.get("state", "")))
		return
	if cycles != 2:
		_fail("expected 2 cycles, got %d" % cycles)
		return
	if phases != 4:
		_fail("expected 4 phase transitions, got %d" % phases)
		return
	if passability_switches != 4:
		_fail("expected 4 passability switches, got %d" % passability_switches)
		return
	if bool(final.get("passability_blocked", true)):
		_fail("final passability_blocked should be false in CLEARED")
		return

	# Status lines must include a Fire line.
	var lines: PackedStringArray = model.get_status_lines()
	var found_fire: bool = false
	for line in lines:
		var text := String(line)
		if text.begins_with("Fire:"):
			found_fire = true
			break
	if not found_fire:
		_fail("status lines missing Fire: line")
		return

	# Final summary must include the keys called out in the spec.
	for key in ["state", "phase", "time_in_state", "cycle_duration", "burning", "passability_blocked", "burn_duration", "clear_duration", "zone_ids"]:
		if not final.has(key):
			_fail("final summary missing key: %s" % key)
			return

	print("FIRE STATE PASS cycles=%d phases=%d passability_switches=%d" % [cycles, phases, passability_switches])
	quit(0)

func _fail(reason: String) -> void:
	push_error("FIRE STATE FAIL reason=%s" % reason)
	quit(1)
```

- [ ] **Step 2: Run the model smoke red**

Run:
```bash
OUT=$(/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-sargasso-of-stars --script res://scripts/validation/fire_state_smoke.gd 2>&1)
printf '%s\n' "$OUT"
printf '%s\n' "$OUT" | grep -q 'FIRE STATE PASS' || true
```

Expected (RED) result:
- Output contains `FIRE STATE FAIL reason=...` (likely `FireState` is undefined or `configure(...)` is missing).
- The pass marker `FIRE STATE PASS` does NOT appear.
- This is the RED phase — the failure is the desired outcome.

- [ ] **Step 3: Record Task 1 RED**

Run:
```bash
if git -C /Users/christopherwilloughby/the-sargasso-of-stars rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C /Users/christopherwilloughby/the-sargasso-of-stars add scripts/validation/fire_state_smoke.gd
  git -C /Users/christopherwilloughby/the-sargasso-of-stars commit -m 'test(fire): RED fire model smoke'
else
  printf '%s\n' 'NO_GIT Task 1 RED: scripts/validation/fire_state_smoke.gd added and failed for missing FireState implementation' >> /tmp/sargasso_timed_fire_no_git_changes.log
fi
```

---

### Task 2: Implement `FireState` Model + Green Model Smoke

**Files:**
- Create: `scripts/systems/fire_state.gd`
- Read: `scripts/systems/oxygen_state.gd` (template)
- Read: `scripts/systems/route_control_state.gd` (template)

**Interfaces:**
- Produces the class referenced by the smoke.
- Sidecar `scripts/systems/fire_state.gd.uid` may be created by Godot.

- [ ] **Step 1: Create `FireState`**

Write `scripts/systems/fire_state.gd` with this complete content:

```gdscript
extends RefCounted
class_name FireState

## Runtime model for the Gate 2 timed fire-zone hazard.
## This model never reaches into the scene tree. PlayableGeneratedShip owns
## the fire-zone scene node and applies scene consequences from this summary.

const DEFAULT_BURN_DURATION: float = 4.0
const DEFAULT_CLEAR_DURATION: float = 3.0
const MINIMUM_PHASE_DURATION: float = 0.1

enum Phase { CLEARED, BURNING }

var zone_ids: Array = []
var burn_duration: float = DEFAULT_BURN_DURATION
var clear_duration: float = DEFAULT_CLEAR_DURATION

var phase: int = Phase.CLEARED
var time_in_phase: float = 0.0
var passability_blocked: bool = false

func configure(p_zone_ids: Array, p_burn_duration: float, p_clear_duration: float) -> void:
	zone_ids.clear()
	for zone_id_variant in p_zone_ids:
		var zone_id: String = str(zone_id_variant)
		if zone_id.is_empty():
			continue
		zone_ids.append(zone_id)
	burn_duration = maxf(MINIMUM_PHASE_DURATION, p_burn_duration)
	clear_duration = maxf(MINIMUM_PHASE_DURATION, p_clear_duration)
	phase = Phase.CLEARED
	time_in_phase = 0.0
	_recompute_passability_blocked()

func tick(delta_seconds: float) -> bool:
	if delta_seconds <= 0.0:
		return false
	var changed: bool = false
	time_in_phase += delta_seconds
	var duration: float = burn_duration if phase == Phase.BURNING else clear_duration
	if time_in_phase >= duration:
		time_in_phase -= duration
		phase = Phase.BURNING if phase == Phase.CLEARED else Phase.CLEARED
		changed = true
	var passability_before: bool = passability_blocked
	_recompute_passability_blocked()
	if passability_blocked != passability_before:
		changed = true
	return changed

func is_passability_blocked() -> bool:
	return passability_blocked

func get_summary() -> Dictionary:
	var current_duration: float = burn_duration if phase == Phase.BURNING else clear_duration
	return {
		"state": "BURNING" if phase == Phase.BURNING else "CLEARED",
		"phase": phase,
		"time_in_state": time_in_phase,
		"cycle_duration": burn_duration + clear_duration,
		"burning": phase == Phase.BURNING,
		"passability_blocked": passability_blocked,
		"burn_duration": burn_duration,
		"clear_duration": clear_duration,
		"remaining_in_state": maxf(0.0, current_duration - time_in_phase),
		"zone_ids": zone_ids.duplicate(),
	}

func get_status_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	if phase == Phase.BURNING:
		lines.append("Fire: BURNING — WAIT")
	else:
		lines.append("Fire: CLEARED")
	return lines

func _recompute_passability_blocked() -> void:
	passability_blocked = (phase == Phase.BURNING)
```

- [ ] **Step 2: Run the model smoke green**

Run:
```bash
OUT=$(/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-sargasso-of-stars --script res://scripts/validation/fire_state_smoke.gd 2>&1)
printf '%s\n' "$OUT"
printf '%s\n' "$OUT" | grep -q 'FIRE STATE PASS cycles=2 phases=4 passability_switches=4'
if printf '%s\n' "$OUT" | grep -E '^(ERROR|WARNING):' >/dev/null; then
  echo 'unexpected ERROR/WARNING in fire_state_smoke'
  exit 1
fi
```

Expected (GREEN) result:
- Output contains `FIRE STATE PASS cycles=2 phases=4 passability_switches=4`.
- No unexpected `ERROR:` or `WARNING:` lines.

- [ ] **Step 3: Record Task 2 GREEN**

Run:
```bash
if git -C /Users/christopherwilloughby/the-sargasso-of-stars rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C /Users/christopherwilloughby/the-sargasso-of-stars add scripts/systems/fire_state.gd scripts/validation/fire_state_smoke.gd
  git -C /Users/christopherwilloughby/the-sargasso-of-stars commit -m 'feat(fire): FireState model and model smoke'
else
  printf '%s\n' 'NO_GIT Task 2 GREEN: scripts/systems/fire_state.gd and scripts/validation/fire_state_smoke.gd added and passing' >> /tmp/sargasso_timed_fire_no_git_changes.log
fi
```

---

### Task 3: Loader Contract for Optional Fire Zones

**Files:**
- Modify: `scripts/procgen/generated_ship_loader.gd`

**Interfaces:**
- Adds `get_fire_zone_markers() -> Array[Vector3]`.
- Reads `layout_doc.get("fire_zones", [])` with the same shape as `breach_zones`.

- [ ] **Step 1: Add fire zone marker parsing**

In `scripts/procgen/generated_ship_loader.gd`:

1. Near `var breach_zone_markers: Array[Vector3] = []`, add:
```gdscript
var fire_zone_markers: Array[Vector3] = []
```

2. In `clear_loaded_ship()`, add:
```gdscript
fire_zone_markers = []
```

3. In `_add_coherence_runtime_nodes(...)`, after `_add_breach_zone_markers(...)`, add:
```gdscript
_add_fire_zone_markers(layout_doc, ship_root)
```

4. Add the following public accessor and helper near `get_breach_zone_markers()`:
```gdscript
func get_fire_zone_markers() -> Array[Vector3]:
	return fire_zone_markers.duplicate()

func _add_fire_zone_markers(layout_doc: Dictionary, ship_root: Node3D) -> void:
	var raw_zones: Variant = layout_doc.get("fire_zones", [])
	if typeof(raw_zones) != TYPE_ARRAY:
		return
	for zone_variant in raw_zones:
		if typeof(zone_variant) != TYPE_DICTIONARY:
			continue
		var zone: Dictionary = zone_variant
		var from_pos: Vector3 = _cell_world_from_link_endpoint(zone, "from_cell", "from_room", layout_doc)
		var to_pos: Vector3 = _cell_world_from_link_endpoint(zone, "to_cell", "to_room", layout_doc)
		if from_pos == Vector3.INF:
			from_pos = _room_center_for_blocked_link(zone, "from_room", layout_doc)
		if to_pos == Vector3.INF:
			to_pos = _room_center_for_blocked_link(zone, "to_room", layout_doc)
		if from_pos == Vector3.INF or to_pos == Vector3.INF:
			continue
		fire_zone_markers.append((from_pos + to_pos) * 0.5)
```

- [ ] **Step 2: Verify the loader still passes existing smokes**

Run:
```bash
OUT=$(/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-sargasso-of-stars --script res://scripts/validation/main_playable_slice_hazard_smoke.gd 2>&1)
printf '%s\n' "$OUT"
printf '%s\n' "$OUT" | grep -q 'MAIN PLAYABLE HAZARD PASS'
```

Expected:
- Output still contains `MAIN PLAYABLE HAZARD PASS`.
- No unexpected errors from the loader change.

---

### Task 4: Scene Integration in `PlayableGeneratedShip`

**Files:**
- Modify: `scripts/procgen/playable_generated_ship.gd`

**Interfaces:**
- Adds fire-zone construction, per-frame tick, and scene-state refresh.
- Adds validation seams: `get_fire_summary()`, `get_fire_zone_node()`, `get_fire_zone_collision_enabled_count()`, `teleport_player_to_fire_zone_for_validation()`.

- [ ] **Step 1: Preload `FireState` and add scene fields**

At the top of `scripts/procgen/playable_generated_ship.gd`, after the `OxygenStateScript` preload, add:
```gdscript
const FireStateScript := preload("res://scripts/systems/fire_state.gd")
```

After the breach-zone constants, add:
```gdscript
const FIRE_ZONE_FALLBACK_ID: String = "side_corridor_fire"
const FIRE_ZONE_FALLBACK_ROOM_ID: String = "corridor_01"
const FIRE_ZONE_COLLISION_SIZE: Vector3 = Vector3(2.6, 2.2, 1.6)
const FIRE_ZONE_VISUAL_COLOR_CLEARED: Color = Color(0.18, 0.75, 1.0, 0.35)
const FIRE_ZONE_VISUAL_COLOR_BURNING: Color = Color(1.0, 0.22, 0.18, 0.82)
const FIRE_ZONE_LABEL_TEXT_CLEARED: String = "FIRE CLEARED"
const FIRE_ZONE_LABEL_TEXT_BURNING: String = "FIRE BURNING — WAIT"
```

After `var breach_zone_node: StaticBody3D` and `var unsafe_room_marker: Label3D`, add:
```gdscript
var fire_state: FireState
var fire_root: Node3D
var fire_zone_node: StaticBody3D
var fire_zone_label: Label3D
```

- [ ] **Step 2: Build runtime nodes for fire**

In `_build_runtime_nodes()`, after the oxygen root setup, add:
```gdscript
fire_state = FireStateScript.new()
fire_root = Node3D.new()
fire_root.name = "FireRoot"
add_child(fire_root)
```

- [ ] **Step 3: Build the fire zone after breach zone**

In `_on_ship_loaded(...)`, after `_refresh_oxygen_state(true, 0.0)`, add:
```gdscript
_build_fire_zone()
_refresh_fire_state(true)
```

- [ ] **Step 4: Add the fire-zone build helpers**

Add these methods near the breach-zone helpers:

```gdscript
func _build_fire_zone() -> void:
	if fire_root == null:
		return
	for child in fire_root.get_children():
		fire_root.remove_child(child)
		child.queue_free()
	fire_zone_node = null
	fire_zone_label = null
	var world_position: Vector3 = _resolve_fire_zone_world_position()
	if fire_state == null:
		fire_state = FireStateScript.new()
	fire_state.configure(
		[FIRE_ZONE_FALLBACK_ID],
		FireStateScript.DEFAULT_BURN_DURATION,
		FireStateScript.DEFAULT_CLEAR_DURATION,
	)
	fire_zone_node = _create_fire_zone_node(world_position)
	fire_root.add_child(fire_zone_node)
	fire_zone_label = _create_fire_zone_label(world_position)
	fire_root.add_child(fire_zone_label)

func _resolve_fire_zone_world_position() -> Vector3:
	if loader != null and loader.has_method("get_fire_zone_markers"):
		var markers: Array = loader.get_fire_zone_markers()
		if markers.size() > 0 and markers[0] is Vector3:
			var candidate: Vector3 = markers[0]
			if candidate != Vector3.INF:
				return candidate
	# Fallback: side corridor room center (must not be the objective 3 -> 4 corridor).
	if loader != null and loader.has_method("get_room_center"):
		var room_center: Vector3 = loader.get_room_center(FIRE_ZONE_FALLBACK_ROOM_ID)
		if room_center != Vector3.INF:
			return room_center
	# Last-ditch: player spawn + offset.
	if player != null:
		return player.global_position + Vector3(6.0, 0.0, 0.0)
	return Vector3.ZERO

func _create_fire_zone_node(world_position: Vector3) -> StaticBody3D:
	var zone: StaticBody3D = StaticBody3D.new()
	zone.name = "FireZone_SideCorridor"
	zone.position = world_position
	zone.collision_layer = 1
	zone.collision_mask = 1
	zone.set_meta("fire_zone_id", FIRE_ZONE_FALLBACK_ID)
	zone.set_meta("fire_zone_kind", "timed_fire")
	zone.set_meta("fire_zone_phase", "CLEARED")
	zone.set_meta("fire_zone_passability_blocked", false)

	var collision_shape: CollisionShape3D = CollisionShape3D.new()
	collision_shape.name = "FireZoneCollisionShape3D"
	var box_shape: BoxShape3D = BoxShape3D.new()
	box_shape.size = FIRE_ZONE_COLLISION_SIZE
	collision_shape.shape = box_shape
	collision_shape.position = Vector3(0.0, FIRE_ZONE_COLLISION_SIZE.y * 0.5, 0.0)
	zone.add_child(collision_shape)

	var visual: MeshInstance3D = MeshInstance3D.new()
	visual.name = "FireZoneVisual"
	var box_mesh: BoxMesh = BoxMesh.new()
	box_mesh.size = FIRE_ZONE_COLLISION_SIZE
	visual.mesh = box_mesh
	visual.position = collision_shape.position
	visual.material_override = _make_fire_zone_material(false)
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	zone.add_child(visual)
	return zone

func _make_fire_zone_material(is_burning: bool) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = FIRE_ZONE_VISUAL_COLOR_BURNING if is_burning else FIRE_ZONE_VISUAL_COLOR_CLEARED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material

func _create_fire_zone_label(world_position: Vector3) -> Label3D:
	var label: Label3D = Label3D.new()
	label.name = "FireZoneLabel"
	label.text = FIRE_ZONE_LABEL_TEXT_CLEARED
	label.position = world_position + Vector3(0.0, FIRE_ZONE_COLLISION_SIZE.y + 0.4, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	label.pixel_size = 0.0035
	label.modulate = FIRE_ZONE_VISUAL_COLOR_CLEARED
	label.outline_size = 3
	label.outline_modulate = Color.BLACK
	return label

func _refresh_fire_state(force_initial: bool) -> void:
	if fire_state == null or fire_zone_node == null:
		return
	if force_initial:
		_apply_fire_zone_scene_state()
		return
	_apply_fire_zone_scene_state()

func _apply_fire_zone_scene_state() -> void:
	if fire_state == null or fire_zone_node == null:
		return
	var summary: Dictionary = fire_state.get_summary()
	var burning: bool = bool(summary.get("burning", false))
	var state_text: String = str(summary.get("state", "CLEARED"))
	fire_zone_node.set_meta("fire_zone_phase", state_text)
	fire_zone_node.set_meta("fire_zone_passability_blocked", burning)
	_set_fire_zone_collision_enabled(fire_zone_node, burning)
	_update_fire_zone_visual(fire_zone_node, burning)
	if fire_zone_label != null:
		fire_zone_label.text = FIRE_ZONE_LABEL_TEXT_BURNING if burning else FIRE_ZONE_LABEL_TEXT_CLEARED
		fire_zone_label.modulate = FIRE_ZONE_VISUAL_COLOR_BURNING if burning else FIRE_ZONE_VISUAL_COLOR_CLEARED

func _set_fire_zone_collision_enabled(zone: Node, enabled: bool) -> void:
	for child in zone.get_children():
		if child is CollisionShape3D:
			(child as CollisionShape3D).disabled = not enabled

func _update_fire_zone_visual(zone: Node, is_burning: bool) -> void:
	for child in zone.get_children():
		if child is MeshInstance3D and child.name == "FireZoneVisual":
			var visual: MeshInstance3D = child as MeshInstance3D
			visual.material_override = _make_fire_zone_material(is_burning)
```

- [ ] **Step 5: Add per-frame fire tick**

In `_process(delta)`, after the existing oxygen refresh block, add:
```gdscript
if fire_state != null:
	fire_state.tick(delta)
	_refresh_fire_state(false)
```

- [ ] **Step 6: Add validation seams**

Add these public helpers near `get_oxygen_summary()`:

```gdscript
func get_fire_summary() -> Dictionary:
	var summary: Dictionary = {}
	if fire_state == null:
		summary["state"] = "CLEARED"
		summary["phase"] = 0
		summary["time_in_state"] = 0.0
		summary["cycle_duration"] = 0.0
		summary["burning"] = false
		summary["passability_blocked"] = false
		summary["burn_duration"] = 0.0
		summary["clear_duration"] = 0.0
		summary["zone_ids"] = []
		return summary
	return fire_state.get_summary()

func get_fire_zone_node() -> Node:
	return fire_zone_node

func get_fire_zone_collision_enabled_count() -> int:
	if fire_zone_node == null:
		return 0
	for child in fire_zone_node.get_children():
		if child is CollisionShape3D and not (child as CollisionShape3D).disabled:
			return 1
	return 0

func teleport_player_to_fire_zone_for_validation() -> bool:
	if player == null or fire_zone_node == null:
		return false
	player.teleport_to(fire_zone_node.global_position)
	return true
```

- [ ] **Step 7: Verify the scene builds without errors**

Run:
```bash
OUT=$(/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-sargasso-of-stars --script res://scripts/validation/main_playable_slice_hazard_smoke.gd 2>&1)
printf '%s\n' "$OUT"
printf '%s\n' "$OUT" | grep -q 'MAIN PLAYABLE HAZARD PASS'
```

Expected:
- Existing hazard smoke still passes.
- No new `ERROR:` / `WARNING:` lines beyond the documented baseline.

---

### Task 5: Main-Scene Fire Smoke

**Files:**
- Create: `scripts/validation/main_playable_slice_fire_smoke.gd`
- Read: `scripts/validation/main_playable_slice_hazard_smoke.gd` (template)

**Interfaces:**
- Loads `res://scenes/main.tscn`, finds `PlayableGeneratedShip`, drives real `_process` frames, asserts fire-zone cycle and collision behavior.
- Pass marker: `MAIN PLAYABLE FIRE PASS state=CLEARED cycles=2 blocked_burning=true blocked_cleared=false`

- [ ] **Step 1: Create the main-scene smoke**

Write `scripts/validation/main_playable_slice_fire_smoke.gd` with this complete content:

```gdscript
extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const READY_TIMEOUT_FRAMES: int = 300

var main_node: Node
var playable: PlayableGeneratedShip
var frame_count: int = 0
var phase: String = "waiting_ready"
var phase_frames: int = 0
var finished: bool = false

var cycles: int = 0
var last_phase_text: String = ""
var saw_blocked_burning: bool = false
var saw_blocked_cleared: bool = false
var last_blocked: bool = false

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
	if playable == null:
		playable = _find_playable(main_node)
	if playable == null or playable.loader == null or not playable.loader.has_loaded_ship():
		if frame_count > READY_TIMEOUT_FRAMES:
			_fail("playable did not become ready")
		return
	match phase:
		"waiting_ready":
			_validate_initial_state()
		"cycling":
			_wait_for_cycles()
		"done":
			_finish()

func _validate_initial_state() -> void:
	if not playable.has_method("get_fire_summary"):
		_fail("get_fire_summary missing")
		return
	if not playable.has_method("get_fire_zone_node"):
		_fail("get_fire_zone_node missing")
		return
	if not playable.has_method("get_fire_zone_collision_enabled_count"):
		_fail("get_fire_zone_collision_enabled_count missing")
		return
	if playable.get("fire_state") == null:
		_fail("fire_state null")
		return
	var initial: Dictionary = playable.get_fire_summary()
	if str(initial.get("state", "")) != "CLEARED":
		_fail("initial state should be CLEARED, got %s" % str(initial.get("state", "")))
		return
	if bool(initial.get("burning", true)):
		_fail("initial burning should be false")
		return
	if bool(initial.get("passability_blocked", true)):
		_fail("initial passability_blocked should be false")
		return
	var fire_node: Node = playable.get_fire_zone_node()
	if fire_node == null:
		_fail("get_fire_zone_node returned null")
		return
	if str(fire_node.get_meta("fire_zone_id", "")) != "side_corridor_fire":
		_fail("fire_zone_id meta should be side_corridor_fire, got %s" % str(fire_node.get_meta("fire_zone_id", "")))
		return
	if str(fire_node.get_meta("fire_zone_kind", "")) != "timed_fire":
		_fail("fire_zone_kind meta should be timed_fire")
		return
	if playable.get_fire_zone_collision_enabled_count() != 0:
		_fail("initial fire zone collision should be disabled, got %d" % playable.get_fire_zone_collision_enabled_count())
		return
	last_phase_text = "CLEARED"
	last_blocked = false
	phase = "cycling"
	phase_frames = 0

func _wait_for_cycles() -> void:
	phase_frames += 1
	var summary: Dictionary = playable.get_fire_summary()
	var state_text: String = str(summary.get("state", "CLEARED"))
	var blocked: bool = bool(summary.get("passability_blocked", false))
	if state_text == "BURNING" and blocked:
		saw_blocked_burning = true
	if state_text == "CLEARED" and not blocked:
		saw_blocked_cleared = true
	if blocked != last_blocked:
		last_blocked = blocked
	if state_text != last_phase_text:
		if last_phase_text == "BURNING" and state_text == "CLEARED":
			cycles += 1
		last_phase_text = state_text
	# Two cycles need at least 2 * (burn + clear) seconds plus margin.
	# At 60 FPS, 7 seconds is 420 frames; allow a generous budget.
	if cycles >= 2 and state_text == "CLEARED":
		phase = "done"
		return
	if phase_frames > 1200:
		_fail("timed out waiting for two fire cycles")

func _finish() -> void:
	var final: Dictionary = playable.get_fire_summary()
	if str(final.get("state", "")) != "CLEARED":
		_fail("final state should be CLEARED, got %s" % str(final.get("state", "")))
		return
	if not saw_blocked_burning:
		_fail("never saw collision enabled while BURNING")
		return
	if saw_blocked_cleared:
		_fail("saw collision enabled while CLEARED")
		return
	if playable.get_fire_zone_collision_enabled_count() != 0:
		_fail("final fire zone collision should be disabled")
		return
	finished = true
	print("MAIN PLAYABLE FIRE PASS state=CLEARED cycles=%d blocked_burning=%s blocked_cleared=%s" % [
		cycles,
		str(saw_blocked_burning).to_lower(),
		str(saw_blocked_cleared).to_lower(),
	])
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
	push_error("MAIN PLAYABLE FIRE FAIL reason=%s" % reason)
	_cleanup_and_quit(1)

func _cleanup_and_quit(code: int) -> void:
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	quit(code)
```

- [ ] **Step 2: Run the main-scene smoke green**

Run:
```bash
OUT=$(/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-sargasso-of-stars --script res://scripts/validation/main_playable_slice_fire_smoke.gd 2>&1)
printf '%s\n' "$OUT"
printf '%s\n' "$OUT" | grep -q 'MAIN PLAYABLE FIRE PASS state=CLEARED cycles=2 blocked_burning=true blocked_cleared=false'
if printf '%s\n' "$OUT" | grep -E '^(ERROR|WARNING):' >/dev/null; then
  echo 'unexpected ERROR/WARNING in main_playable_slice_fire_smoke'
  exit 1
fi
```

Expected (GREEN) result:
- Output contains `MAIN PLAYABLE FIRE PASS state=CLEARED cycles=2 blocked_burning=true blocked_cleared=false`.
- No unexpected `ERROR:` or `WARNING:` lines.

---

### Task 6: Regression Bundle + Validation Plan Update

**Files:**
- Modify: `docs/game/06_validation_plan.md`

- [ ] **Step 1: Add fire smokes to the regression bundle**

In `docs/game/06_validation_plan.md`, inside the `run_clean` calls under `## Regression bundle`, add these two lines after the existing oxygen/hazard smokes:

```bash
run_clean 'fire model smoke' 'FIRE STATE PASS cycles=2 phases=4 passability_switches=4' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/fire_state_smoke.gd
run_clean 'main fire smoke' 'MAIN PLAYABLE FIRE PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_fire_smoke.gd
```

Update the final echo to reflect the new command count (from 8 to 10):
```bash
echo 'SARGASSO REGRESSION PASS commands=10 clean_output=true'
```

- [ ] **Step 2: Update future-validation list**

In `docs/game/06_validation_plan.md`, under `## Future validation additions`, change:
```markdown
- Fire hazard model smoke: `scripts/validation/fire_state_smoke.gd` and main-scene smoke `scripts/validation/main_playable_slice_fire_smoke.gd` (REQ-010).
```
to:
```markdown
- [x] Fire hazard model smoke: `scripts/validation/fire_state_smoke.gd` and main-scene smoke `scripts/validation/main_playable_slice_fire_smoke.gd` (REQ-010).
```

- [ ] **Step 3: Run the full regression bundle**

Run:
```bash
ROOT=/Users/christopherwilloughby/the-sargasso-of-stars
GODOT=/Users/christopherwilloughby/.local/bin/godot-4.6.2
BASELINE_ERROR="^ERROR: Capture not registered: 'gdaimcp'\\.$"
BASELINE_WARNING="^WARNING: ObjectDB instances leaked at exit \\(run with --verbose for details\\)\\.$"
run_clean() {
  label="$1"
  marker="$2"
  shift 2
  echo "=== $label ==="
  OUT=$("$@" 2>&1)
  printf '%s\n' "$OUT"
  printf '%s\n' "$OUT" | grep -q "$marker"
  FILTERED=$(printf '%s\n' "$OUT" | grep -E '^(ERROR|WARNING):' | grep -Ev "$BASELINE_ERROR|$BASELINE_WARNING" || true)
  if [ -n "$FILTERED" ]; then
    printf '%s\n' "$FILTERED"
    echo "UNEXPECTED_ERROR_OR_WARNING in $label"
    exit 1
  fi
}
run_clean 'route control model smoke' 'ROUTE CONTROL STATE PASS gates=2 opened=2 blockers=0 extraction=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/route_control_state_smoke.gd
run_clean 'main route control smoke' 'MAIN PLAYABLE ROUTE CONTROL PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_route_control_smoke.gd
run_clean 'oxygen model smoke' 'OXYGEN STATE PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/oxygen_state_smoke.gd
run_clean 'main hazard smoke' 'MAIN PLAYABLE HAZARD PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_hazard_smoke.gd
run_clean 'fire model smoke' 'FIRE STATE PASS cycles=2 phases=4 passability_switches=4' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/fire_state_smoke.gd
run_clean 'main fire smoke' 'MAIN PLAYABLE FIRE PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_fire_smoke.gd
run_clean 'ship systems smoke' 'MAIN PLAYABLE SHIP SYSTEMS PASS supplies=true power=true logs=true reactor=true extraction=true blocked_visible=0 completed_systems=4' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_ship_systems_smoke.gd
run_clean 'completion smoke' 'MAIN PLAYABLE SLICE COMPLETE PASS completed=4 current_sequence=5 run_complete=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_completion_smoke.gd
run_clean 'input smoke' 'MAIN PLAYABLE INPUT LOOP PASS moved=true camera_followed=true interaction_input_path=true current_sequence=2' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_input_smoke.gd
run_clean 'readability smoke' 'MAIN PLAYABLE SLICE READABILITY PASS objective_props=4 blocked=1 ramp=1' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_readability_smoke.gd
echo 'SARGASSO REGRESSION PASS commands=10 clean_output=true'
```

Expected:
- All smokes print their pass markers.
- `SARGASSO REGRESSION PASS commands=10 clean_output=true` is printed.
- No unexpected `ERROR:` / `WARNING:` lines.

---

## Save/Load Serialization Note (REQ-012)

The downstream REQ-012 implementation will need to serialize `FireState.phase` and `FireState.time_in_phase` (and the cycle durations) as part of the current-run snapshot. This plan deliberately does not implement serialization here; it only exposes the necessary state in `get_fire_summary()` so the save/load service can read it. Do not add save/load code in this card.

---

## Verification Commands

Direct model smoke:
```bash
/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-sargasso-of-stars --script res://scripts/validation/fire_state_smoke.gd
```
Expected marker: `FIRE STATE PASS cycles=2 phases=4 passability_switches=4`

Main-scene smoke:
```bash
/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-sargasso-of-stars --script res://scripts/validation/main_playable_slice_fire_smoke.gd
```
Expected marker: `MAIN PLAYABLE FIRE PASS state=CLEARED cycles=2 blocked_burning=true blocked_cleared=false`

Regression bundle:
```bash
# Run the updated bundle in docs/game/06_validation_plan.md
```
Expected marker: `SARGASSO REGRESSION PASS commands=10 clean_output=true`

---

## Allowed Files

- `scripts/systems/fire_state.gd`
- `scripts/systems/fire_state.gd.uid` (Godot-generated sidecar)
- `scripts/validation/fire_state_smoke.gd`
- `scripts/validation/main_playable_slice_fire_smoke.gd`
- `scripts/procgen/generated_ship_loader.gd`
- `scripts/procgen/playable_generated_ship.gd`
- `docs/game/06_validation_plan.md`
- `/tmp/sargasso_timed_fire_no_git_changes.log` (no-git ledger)

---

## Non-Goals

- No player health or damage-over-time.
- No fire spread, propagation, or random ignition.
- No interaction to disable/override the fire cycle in Gate 2.
- No audio, particle, heat distortion, or lighting changes.
- No procedural fire placement per run; Gate 2 uses one fixed side corridor.
- No fire-oxygen interaction (fire does not drain oxygen faster and oxygen does not affect fire).
- No coupling to route gates, objectives, inventory/tools, or extraction.
- No save/load serialization in this card (REQ-012 will consume `get_fire_summary()`).

---

## Risks and Mitigations

- **Risk:** fire timer makes the slice feel like a waiting simulator.
  - **Mitigation:** keep durations short (3s cleared / 4s burning) and place the zone on an optional side corridor, not the main critical path.
- **Risk:** two hazard models become copy-paste code.
  - **Mitigation:** keep them independent for Gate 2; author ADR-0005 (Multi-Hazard Architecture) if a third hazard type is planned, extracting a common hazard interface then.
- **Risk:** fire collision and oxygen breach collision overlap or conflict.
  - **Mitigation:** fire zone is on a separate side corridor (`corridor_01` fallback, not the objective 3 → 4 corridor); the main-scene smoke asserts the zone ids are distinct and non-overlapping.
- **Risk:** HUD becomes noisy with two hazard status lines.
  - **Mitigation:** fire zone shows only a localized Label3D; the global HUD line is reserved for oxygen.
- **Risk:** main-scene smoke is flaky due to frame timing.
  - **Mitigation:** the smoke observes real `_process` frames with a generous timeout (1200 frames ≈ 20s) and asserts cycle count + collision state rather than exact frame counts.

---

## Stop / Block Conditions

Block and escalate if any of the following occur during implementation:

- The plan is changed to couple fire state to oxygen, route gates, objectives, inventory/tools, or extraction.
- Health, damage-over-time, fire spread, random ignition, or fire-oxygen interaction is introduced.
- A generalized multi-hazard architecture is required beyond the second independent model without ADR-0005.
- Route/extraction semantics are altered by the fire zone.
- The regression bundle cannot be updated because existing smokes fail.
- Any new `ERROR:` or `WARNING:` line appears in the regression bundle that cannot be classified and accepted in `docs/game/06_validation_plan.md`.
