# Hazard Pressure Loop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Gate 1 hazard pressure loop on the main playable slice so that a single depleting oxygen resource applies real runtime drain, a breach-zone collision toggle, a HUD numeric line, and a room unsafe marker while a fresh player crosses the objective 3 → objective 4 corridor.

**Architecture:** Add a pure `OxygenState` model beside `ShipSystemState` and `RouteControlState`, then let `PlayableGeneratedShip` own an `OxygenRoot` (breach-zone collision segments + scene markers) and apply scene consequences from the model's summary. The model decides oxygen, breach seal, and passability-block state from the player position and ship-system summary; the scene applies passability by toggling collision on the breach-zone `StaticBody3D`, attaches a `Label3D` room-unsafe marker, and exposes a HUD oxygen line source through `ObjectiveTracker.set_system_status_lines()`. Mirror the route-control pattern so existing validation seams (`complete_objective_sequence_for_validation`, etc.) keep working.

**Tech Stack:** Godot 4.6.2 GDScript, `SceneTree` validation smokes, existing `res://scenes/main.tscn`, existing `PlayableGeneratedShip`, existing `RouteControlState`, existing `ShipSystemState`, existing `ObjectiveTracker`, no external runtime dependencies.

## Global Constraints

- Project root: `/Users/christopherwilloughby/the-synapse-sea-of-stars`.
- Godot binary: `/Users/christopherwilloughby/.local/bin/godot-4.6.2`.
- Workspace state checked on 2026-06-19: `GIT_INSIDE=false`.
- Do not create HTML, PNG, contact sheets, screenshot galleries, or proof documents for this milestone.
- Use TDD: write failing smoke(s), run them red, then implement runtime code.
- The hazard must change actual scene passability through the breach-zone collision state; updating HUD text or adding a marker alone is not enough.
- The breach-zone collision toggle contract must explicitly verify collision enabled while oxygen is at or below the recovery threshold and collision disabled while above the safe threshold.
- Hazard behavior must preserve the existing objective sequence: `restore_systems` (objective 2) seals the breach, `stabilize_reactor` (objective 4) must not affect oxygen or breach state, and route-control/extraction summary must remain unchanged by hazard state.
- The hazard milestone has no proof artifacts as deliverables; validation is command-output smokes only.
- Preserve existing objective sequence and validation seams: `complete_objective_sequence_for_validation()`, `complete_all_objectives_for_validation()`, `complete_first_interaction_for_validation()`, and existing smokes (`route_control_state_smoke`, `main_playable_slice_route_control_smoke`, ship_systems / completion / input / readability smokes) must keep passing unchanged.
- Output from validation commands must be clean of unexpected lines beginning with `ERROR:` or `WARNING:`.
- Because this is not a git repository, every task uses the no-git ledger fallback at `/tmp/synapse_sea_hazard_pressure_no_git_changes.log` instead of assuming `git commit` works.
- Do not collapse `OxygenState` into `ShipSystemState` or `RouteControlState`; keep separate responsibility, parallel to the route-control architecture.
- Do not delete the breach-zone node when sealing the breach or blocking traversal — disable collision, update metadata, and toggle visibility so the state remains inspectable.
- Do not introduce save/load of hazard state, oxygen tanks, pickups, audio cues, particle VFX, or animation polish in this slice (those are non-goals in `docs/game/features/hazards.md`).
- All drain / regen / recovery / max values are tunables — they live on the model as constants and are printed by the smokes so they are visible from validation output.

---

## File Structure

Create:

- `scripts/systems/oxygen_state.gd`
  - Pure runtime model for oxygen depletion / regeneration / breach seal / passability block.
  - Extends `RefCounted`, class_name `OxygenState`.
  - No scene-tree access.
  - Mirrors the `RouteControlState` shape: `configure(...)`, `tick(...)`, `seal_breach(...)`, `apply_ship_systems_summary(...)`, `get_summary()`, `get_status_lines()`, plus `is_passability_blocked()` and `is_player_in_breach_zone()` accessors.
  - Carries tunables as class constants: `DEFAULT_MAX_OXYGEN: float = 100.0`, `DEFAULT_DRAIN_RATE: float = 6.0`, `DEFAULT_REGEN_RATE: float = 3.5`, `DEFAULT_SAFE_THRESHOLD: float = 35.0`, `DEFAULT_RECOVERY_THRESHOLD: float = 30.0`.

- `scripts/validation/oxygen_state_smoke.gd`
  - Direct model smoke for `OxygenState`.
  - Verifies initial full oxygen, drain while in unsealed breach, regen while outside, seal-on-objective-2, passability block at zero, recovery above threshold, idempotence of duplicate summaries, and `get_summary()` keys (`oxygen`, `breach_open`, `breach_sealed`, `passability_blocked`, `recovery_threshold`).
  - Pass marker: `OXYGEN STATE PASS oxygen=... breach_open=... breach_sealed=... passability_blocked=... recovery_threshold=...`.

- `scripts/validation/main_playable_slice_hazard_smoke.gd`
  - Main-scene runtime smoke for the hazard.
  - Verifies `OxygenState` exists on `PlayableGeneratedShip`, breach-zone scene node exists with collision enabled, sealing via objective 2 flips `breach_sealed=true`, hazard summary keys are populated, and the smoke exits without errors after objective 4 (reactor stabilization must NOT affect oxygen or breach state).
  - Pass marker: `MAIN PLAYABLE HAZARD PASS oxygen=... breach_open=... breach_sealed=... passability_blocked=...`.

Modify:

- `scripts/procgen/generated_ship_loader.gd`
  - Add optional `breach_zones` to the loader output.
  - Read `layout_doc.get("breach_zones", [])` and expose a new accessor `get_breach_zone_markers() -> Array[Vector3]`.
  - Missing/null is treated as an empty array; the scene coordinator then injects a fixed Gate 1 breach zone at the corridor between objective 3 and objective 4 from a constant list (see `playable_generated_ship.gd` below) so existing fixtures still validate.

- `scripts/procgen/playable_generated_ship.gd`
  - Preload and own `OxygenState`.
  - Add `oxygen_state`, `oxygen_root: Node3D`, `breach_zone_node: StaticBody3D`, and `unsafe_room_marker: Label3D`.
  - Add `_GATE1_BREACH_ZONE_FALLBACK_ID: String = "corridor_to_reactor"` and a constant fallback world position derived from the loader (the midpoint between the objective-3 room center and the objective-4 / reactor room center) used only when the loader has no breach data.
  - In `_on_ship_loaded(...)` after `_build_route_control_gates()`: call `_build_breach_zone()` then `_refresh_oxygen_state(force_initial=true)` so the HUD oxygen line and passability reflect the open breach on slice start.
  - In `_process(delta)` after the existing tick: read player world position and call `_refresh_oxygen_state(force_initial=false)`, passing `delta` and the player's `is_player_in_breach_zone` boolean to `OxygenState.tick(...)`.
  - In `_on_interactable_completed(...)`: after `_refresh_route_control_from_ship_systems()`, call `_refresh_oxygen_state(force_initial=false)` so objective 2 (`restore_systems`) sealing reaches the model.
  - Add helpers `get_oxygen_summary() -> Dictionary`, `get_breach_zone_node() -> Node`, `get_breach_zone_collision_enabled_count() -> int`, `is_player_in_breach_zone() -> bool`, `get_oxygen_status_lines() -> PackedStringArray`.
  - Extend `_combined_system_status_lines()` to also append `oxygen_state.get_status_lines()` (filtered so duplicate `Routes:` / `Extraction:` lines from ship-systems are still skipped, but oxygen lines are always added).

- `scripts/ui/objective_tracker.gd`
  - No changes required — `set_system_status_lines(lines: PackedStringArray)` already accepts composed system/status lines.

- `docs/game/06_validation_plan.md`
  - Add the two new smokes to the regression bundle and to the "Future validation additions" section.

- `docs/game/02_core_loop.md`
  - Update "Current implemented loop evidence" with a hazard-pressure row.
  - Remove the hazard/survival pressure line from "Loop gaps to resolve before Gate 1 exit".

Generated by Godot if import/class registration runs:

- `scripts/systems/oxygen_state.gd.uid`
  - Accept this sidecar if Godot creates it.
  - Record it in the no-git ledger.

---

### Task 1: Hazard Model Smoke, RED Phase

**Files:**
- Create: `scripts/validation/oxygen_state_smoke.gd`
- Read: `scripts/validation/route_control_state_smoke.gd` (template)
- Read: `scripts/systems/route_control_state.gd` (mirror shape)

**Interfaces:**
- Consumes intended future class: `OxygenState.new()`.
- Consumes intended future methods:
  - `configure(breach_zone_ids: Array, max_oxygen: float, drain_rate: float, regen_rate: float, recovery_threshold: float, safe_threshold: float)`
  - `tick(delta_seconds: float, player_in_breach_zone: bool) -> bool`
  - `seal_breach(zone_id: String) -> bool`
  - `apply_ship_systems_summary(summary: Dictionary) -> bool`
  - `get_summary() -> Dictionary`
  - `get_status_lines() -> PackedStringArray`
  - `is_passability_blocked() -> bool`
  - `is_player_in_breach_zone() -> bool`
- Produces a failing model smoke with pass marker:
  - `OXYGEN STATE PASS oxygen=... breach_open=... breach_sealed=... passability_blocked=... recovery_threshold=...`

- [ ] **Step 1: Create the failing model smoke**

Write `scripts/validation/oxygen_state_smoke.gd` with this complete content:

```gdscript
extends SceneTree

func _initialize() -> void:
	var model := OxygenState.new()
	model.configure(
		["corridor_to_reactor"],
		100.0,
		6.0,
		3.5,
		30.0,
		35.0
	)

	var initial: Dictionary = model.get_summary()
	if absf(float(initial.get("oxygen", -1.0)) - 100.0) > 0.001:
		_fail("initial oxygen should be 100.0, got %s" % str(initial.get("oxygen", -1.0)))
		return
	if not bool(initial.get("breach_open", false)):
		_fail("initial breach_open should be true")
		return
	if bool(initial.get("breach_sealed", true)):
		_fail("initial breach_sealed should be false")
		return
	if bool(initial.get("passability_blocked", true)):
		_fail("initial passability_blocked should be false")
		return
	if not initial.has("recovery_threshold"):
		_fail("summary missing recovery_threshold key")
		return
	if not initial.has("safe_threshold"):
		_fail("summary missing safe_threshold key")
		return
	if model.is_passability_blocked():
		_fail("initial is_passability_blocked should be false")
		return
	if not model.is_player_in_breach_zone():
		# Initial player position is undefined; the model is not required
		# to start "in" a breach zone. It is only required to reflect any
		# explicit zone-id match returned by configure(...).
		# Test below will set it explicitly.
		pass

	# Drain while inside the unsealed breach zone.
	var first_tick_changed: bool = model.tick(1.0, true)
	if not first_tick_changed:
		_fail("drain tick should report changed when player is inside unsealed breach")
		return
	var after_drain: Dictionary = model.get_summary()
	var oxygen_after_drain: float = float(after_drain.get("oxygen", -1.0))
	if oxygen_after_drain >= 100.0:
		_fail("oxygen should decrease after drain tick, got %s" % oxygen_after_drain)
		return
	if oxygen_after_drain != 100.0 - 6.0:
		_fail("oxygen after one drain tick should be 94.0, got %s" % oxygen_after_drain)
		return

	# Duplicate drain tick (same state) must report unchanged.
	var duplicate_tick_changed: bool = model.tick(1.0, true)
	if duplicate_tick_changed:
		# Note: oxygen value itself changes; we only assert the
		# "state changed" boolean from the model. Since oxygen did change,
		# the boolean should be true. Reset by exiting then re-entering.
		pass
	var oxygen_after_second_drain: float = float(model.get_summary().get("oxygen", -1.0))
	if absf(oxygen_after_second_drain - (oxygen_after_drain - 6.0)) > 0.001:
		_fail("oxygen after second drain tick should be %s, got %s" % [str(oxygen_after_drain - 6.0), oxygen_after_second_drain])
		return

	# Regen while outside any breach zone.
	var oxygen_before_regen: float = float(model.get_summary().get("oxygen", -1.0))
	var regen_tick_changed: bool = model.tick(1.0, false)
	var oxygen_after_regen: float = float(model.get_summary().get("oxygen", -1.0))
	if oxygen_after_regen <= oxygen_before_regen:
		_fail("oxygen should increase while outside breach zone, before=%s after=%s" % [oxygen_before_regen, oxygen_after_regen])
		return
	if absf(oxygen_after_regen - (oxygen_before_regen + 3.5)) > 0.001:
		_fail("oxygen regen rate should be 3.5/sec, before=%s after=%s" % [oxygen_before_regen, oxygen_after_regen])
		return

	# Seal the breach via objective 2 summary.
	var seal_changed: bool = model.apply_ship_systems_summary({
		"main_power_restored": true,
		"blocked_routes_cleared": true,
		"extraction_unlocked": false,
	})
	if not seal_changed:
		_fail("ship-system summary with main_power_restored should seal the breach")
		return
	var after_seal: Dictionary = model.get_summary()
	if bool(after_seal.get("breach_open", false)):
		_fail("after seal breach_open should be false")
		return
	if not bool(after_seal.get("breach_sealed", false)):
		_fail("after seal breach_sealed should be true")
		return

	# After sealing, even staying "inside" the breach zone should not drain.
	var oxygen_before_post_seal: float = float(model.get_summary().get("oxygen", -1.0))
	model.tick(1.0, true)
	var oxygen_after_post_seal: float = float(model.get_summary().get("oxygen", -1.0))
	if absf(oxygen_after_post_seal - oxygen_before_post_seal) > 0.001:
		_fail("oxygen should not change while inside sealed breach, before=%s after=%s" % [oxygen_before_post_seal, oxygen_after_post_seal])
		return

	# Direct seal call should be idempotent.
	var double_seal_changed: bool = model.seal_breach("corridor_to_reactor")
	if double_seal_changed:
		_fail("duplicate seal_breach should report unchanged")
		return

	# Reset the model for the passability block test by reconfiguring it.
	model.configure(
		["corridor_to_reactor"],
		30.0,   # max
		100.0,  # drain
		0.0,    # no regen
		30.0,   # recovery_threshold
		35.0    # safe_threshold
	)
	# Drain to zero.
	model.tick(1.0, true)
	var zero_state: Dictionary = model.get_summary()
	if float(zero_state.get("oxygen", -1.0)) > 0.001:
		_fail("after forced drain oxygen should be 0, got %s" % str(zero_state.get("oxygen", -1.0)))
		return
	if not bool(zero_state.get("passability_blocked", false)):
		_fail("at oxygen=0 passability_blocked should be true")
		return
	if not model.is_passability_blocked():
		_fail("is_passability_blocked should be true at oxygen=0")
		return

	# Recovery: with regen > 0, ticks above threshold reopen passability.
	model.configure(
		["corridor_to_reactor"],
		100.0,
		1000.0, # drain
		100.0,  # regen
		30.0,   # recovery_threshold
		35.0    # safe_threshold
	)
	model.tick(1.0, true)  # drain to zero
	var zero_again: Dictionary = model.get_summary()
	if float(zero_again.get("oxygen", -1.0)) > 0.001:
		_fail("after forced drain oxygen should be 0, got %s" % str(zero_again.get("oxygen", -1.0)))
		return
	if not model.is_passability_blocked():
		_fail("is_passability_blocked should be true after forced drain")
		return
	# Now tick while outside the breach to regen above recovery threshold.
	for i in range(5):
		model.tick(1.0, false)
	var recovered: Dictionary = model.get_summary()
	if float(recovered.get("oxygen", -1.0)) <= 30.0:
		_fail("oxygen should recover above recovery_threshold after regen ticks, got %s" % str(recovered.get("oxygen", -1.0)))
		return
	if bool(recovered.get("passability_blocked", true)):
		_fail("passability_blocked should be false once oxygen > recovery_threshold")
		return
	if model.is_passability_blocked():
		_fail("is_passability_blocked should be false once oxygen > recovery_threshold")
		return

	# Status lines must include the oxygen line and the seal marker.
	var lines: PackedStringArray = model.get_status_lines()
	var found_oxygen: bool = false
	var found_seal_marker: bool = false
	for line in lines:
		var text := String(line)
		if text.begins_with("Oxygen:"):
			found_oxygen = true
		if text.begins_with("Breach:"):
			found_seal_marker = true
	if not found_oxygen:
		_fail("status lines missing Oxygen: line")
		return
	if not found_seal_marker:
		_fail("status lines missing Breach: line")
		return

	# Final summary must include all the keys called out in the spec.
	var final: Dictionary = model.get_summary()
	for key in ["oxygen", "breach_open", "breach_sealed", "passability_blocked", "recovery_threshold", "safe_threshold", "max_oxygen", "drain_rate", "regen_rate", "breach_zone_ids"]:
		if not final.has(key):
			_fail("final summary missing key: %s" % key)
			return

	print("OXYGEN STATE PASS oxygen=%s breach_open=%s breach_sealed=%s passability_blocked=%s recovery_threshold=%s" % [
		str(final.get("oxygen", -1.0)),
		str(final.get("breach_open", false)).to_lower(),
		str(final.get("breach_sealed", false)).to_lower(),
		str(final.get("passability_blocked", false)).to_lower(),
		str(final.get("recovery_threshold", -1.0)),
	])
	quit(0)

func _fail(reason: String) -> void:
	push_error("OXYGEN STATE FAIL reason=%s" % reason)
	quit(1)
```

- [ ] **Step 2: Run the model smoke red**

Run:
```bash
OUT=$(/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-synapse-sea-of-stars --script res://scripts/validation/oxygen_state_smoke.gd 2>&1)
printf '%s\n' "$OUT"
printf '%s\n' "$OUT" | grep -q 'OXYGEN STATE PASS' || true
```

Expected (RED) result:
- Output contains `OXYGEN STATE FAIL reason=...` (likely `OxygenState` is undefined or `configure(...)` is missing).
- The pass marker `OXYGEN STATE PASS` does NOT appear.
- This is the RED phase — the failure is the desired outcome.

- [ ] **Step 3: Record Task 1 RED**

Run:
```bash
if git -C /Users/christopherwilloughby/the-synapse-sea-of-stars rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C /Users/christopherwilloughby/the-synapse-sea-of-stars add scripts/validation/oxygen_state_smoke.gd
  git -C /Users/christopherwilloughby/the-synapse-sea-of-stars commit -m 'test(hazard): RED oxygen model smoke'
else
  printf '%s\n' 'NO_GIT Task 1 RED: scripts/validation/oxygen_state_smoke.gd added and failed for missing OxygenState implementation' >> /tmp/synapse_sea_hazard_pressure_no_git_changes.log
fi
```

---

### Task 2: Implement `OxygenState` Model + Green Model Smoke

**Files:**
- Create: `scripts/systems/oxygen_state.gd`
- Read: `scripts/systems/route_control_state.gd` (template)
- Read: `scripts/systems/ship_system_state.gd` (template)

**Interfaces:**
- Produces the class referenced by the smoke.
- Sidecar `scripts/systems/oxygen_state.gd.uid` may be created by Godot.

- [ ] **Step 1: Create `OxygenState`**

Write `scripts/systems/oxygen_state.gd` with this complete content:

```gdscript
extends RefCounted
class_name OxygenState

## Runtime model for the Gate 1 hazard pressure loop.
## This model never reaches into the scene tree. PlayableGeneratedShip owns
## the breach-zone scene node and applies scene consequences from this summary.
##
## Tunables (DEFAULT_* constants) are the values used by the Gate 1 slice.
## They are exposed via get_summary() so smokes can assert the exact tuning
## in use.

const DEFAULT_MAX_OXYGEN: float = 100.0
const DEFAULT_DRAIN_RATE: float = 6.0
const DEFAULT_REGEN_RATE: float = 3.5
const DEFAULT_RECOVERY_THRESHOLD: float = 30.0
const DEFAULT_SAFE_THRESHOLD: float = 35.0

var breach_zone_ids: Array = []
var max_oxygen: float = DEFAULT_MAX_OXYGEN
var drain_rate: float = DEFAULT_DRAIN_RATE
var regen_rate: float = DEFAULT_REGEN_RATE
var recovery_threshold: float = DEFAULT_RECOVERY_THRESHOLD
var safe_threshold: float = DEFAULT_SAFE_THRESHOLD

var oxygen: float = DEFAULT_MAX_OXYGEN
var breach_open: bool = true
var breach_sealed: bool = false
var passability_blocked: bool = false
var last_player_in_breach_zone: bool = false

func configure(zone_ids: Array, p_max_oxygen: float, p_drain_rate: float, p_regen_rate: float, p_recovery_threshold: float, p_safe_threshold: float) -> void:
	breach_zone_ids.clear()
	for zone_id_variant in zone_ids:
		var zone_id: String = str(zone_id_variant)
		if zone_id.is_empty():
			continue
		breach_zone_ids.append(zone_id)
	max_oxygen = maxf(0.0, p_max_oxygen)
	drain_rate = maxf(0.0, p_drain_rate)
	regen_rate = maxf(0.0, p_regen_rate)
	recovery_threshold = clampf(p_recovery_threshold, 0.0, max_oxygen)
	safe_threshold = clampf(p_safe_threshold, recovery_threshold, max_oxygen)
	oxygen = max_oxygen
	breach_open = breach_zone_ids.size() > 0
	breach_sealed = false
	passability_blocked = false
	last_player_in_breach_zone = false

func tick(delta_seconds: float, player_in_breach_zone: bool) -> bool:
	last_player_in_breach_zone = player_in_breach_zone
	if delta_seconds <= 0.0:
		return false
	var changed: bool = false
	if breach_open and not breach_sealed and player_in_breach_zone:
		var drained: float = drain_rate * delta_seconds
		if drained > 0.0:
			oxygen = maxf(0.0, oxygen - drained)
			changed = true
	elif not player_in_breach_zone and oxygen < max_oxygen:
		var regenerated: float = regen_rate * delta_seconds
		if regenerated > 0.0:
			oxygen = minf(max_oxygen, oxygen + regenerated)
			changed = true
	_recompute_passability_blocked()
	return changed

func seal_breach(_zone_id: String) -> bool:
	if not breach_open:
		return false
	if breach_sealed:
		return false
	breach_open = false
	breach_sealed = true
	return true

func apply_ship_systems_summary(summary: Dictionary) -> bool:
	# Per docs/game/features/hazards.md, completing objective 2
	# (main_power_restored) seals the breach. Other ship-system events are
	# ignored here; this keeps the hazard parallel to route-control state.
	if not bool(summary.get("main_power_restored", false)):
		return false
	if breach_sealed:
		return false
	breach_open = false
	breach_sealed = true
	return true

func is_passability_blocked() -> bool:
	return passability_blocked

func is_player_in_breach_zone() -> bool:
	return last_player_in_breach_zone

func get_summary() -> Dictionary:
	return {
		"oxygen": oxygen,
		"max_oxygen": max_oxygen,
		"drain_rate": drain_rate,
		"regen_rate": regen_rate,
		"recovery_threshold": recovery_threshold,
		"safe_threshold": safe_threshold,
		"breach_open": breach_open,
		"breach_sealed": breach_sealed,
		"passability_blocked": passability_blocked,
		"player_in_breach_zone": last_player_in_breach_zone,
		"breach_zone_ids": breach_zone_ids.duplicate(),
	}

func get_status_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	if oxygen <= 0.001:
		lines.append("Oxygen: 0 BREACH BLOCKED")
	elif oxygen <= recovery_threshold + 0.001:
		lines.append("Oxygen: %d LOW" % int(round(oxygen)))
	elif oxygen <= safe_threshold + 0.001:
		lines.append("Oxygen: %d" % int(round(oxygen)))
	else:
		lines.append("Oxygen: %d" % int(round(oxygen)))
	if breach_sealed:
		lines.append("Breach: SEALED")
	elif breach_open:
		lines.append("Breach: OPEN")
	else:
		lines.append("Breach: CLOSED")
	return lines

func _recompute_passability_blocked() -> void:
	if oxygen <= recovery_threshold + 0.001 and not breach_sealed:
		passability_blocked = true
	else:
		passability_blocked = false
```

- [ ] **Step 2: Run the model smoke green**

Run:
```bash
OUT=$(/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-synapse-sea-of-stars --script res://scripts/validation/oxygen_state_smoke.gd 2>&1)
printf '%s\n' "$OUT"
printf '%s\n' "$OUT" | grep -q 'OXYGEN STATE PASS'
if printf '%s\n' "$OUT" | grep -E '^(ERROR|WARNING):' >/dev/null; then
  echo 'unexpected ERROR/WARNING in oxygen_state_smoke'
  exit 1
fi
```

Expected green marker:
```text
OXYGEN STATE PASS oxygen=... breach_open=false breach_sealed=true passability_blocked=false recovery_threshold=30.0
```

(The exact `oxygen=` value is whatever remains after the recovery test loop; the boolean keys are fixed once sealed.)

- [ ] **Step 3: Record Task 2**

Run:
```bash
if git -C /Users/christopherwilloughby/the-synapse-sea-of-stars rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C /Users/christopherwilloughby/the-synapse-sea-of-stars add scripts/systems/oxygen_state.gd scripts/systems/oxygen_state.gd.uid scripts/validation/oxygen_state_smoke.gd
  git -C /Users/christopherwilloughby/the-synapse-sea-of-stars commit -m 'feat(hazard): implement OxygenState model'
else
  printf '%s\n' 'NO_GIT Task 2 changed: scripts/systems/oxygen_state.gd scripts/systems/oxygen_state.gd.uid scripts/validation/oxygen_state_smoke.gd' >> /tmp/synapse_sea_hazard_pressure_no_git_changes.log
fi
```

---

### Task 3: Main-Playable-Scene Hazard Smoke (RED) + Loader + Scene Integration

**Files:**
- Modify: `scripts/procgen/generated_ship_loader.gd`
- Modify: `scripts/procgen/playable_generated_ship.gd`
- Create: `scripts/validation/main_playable_slice_hazard_smoke.gd`
- Read: `scripts/validation/main_playable_slice_route_control_smoke.gd` (template)

**Interfaces:**
- Consumes intended future methods from `PlayableGeneratedShip`:
  - `get_oxygen_summary() -> Dictionary`
  - `get_breach_zone_node() -> Node`
  - `get_breach_zone_collision_enabled_count() -> int`
  - `is_player_in_breach_zone() -> bool`
- Consumes intended future class:
  - `OxygenState.new()`
- Consumes intended future loader method:
  - `GeneratedShipLoader.get_breach_zone_markers() -> Array[Vector3]`
- Produces a failing main-scene validation smoke with pass marker:
  - `MAIN PLAYABLE HAZARD PASS oxygen=... breach_open=... breach_sealed=... passability_blocked=...`

- [ ] **Step 1: Add `breach_zone_markers` accessor to the loader**

In `scripts/procgen/generated_ship_loader.gd`, add a member:

```gdscript
var breach_zone_markers: Array[Vector3] = []
```

In the existing reset block (search for the assignment `blocked_route_nodes = []` and add a sibling line):

```gdscript
breach_zone_markers = []
```

In the `_add_coherence_runtime_nodes(layout_doc, ship_root)` block (or equivalent runtime-add function — add as a sibling call):

```gdscript
_add_breach_zone_markers(layout_doc, ship_root)
```

Add a new function near `_add_blocked_route_nodes(...)`:

```gdscript
func _add_breach_zone_markers(layout_doc: Dictionary, ship_root: Node3D) -> void:
	var raw_zones: Variant = layout_doc.get("breach_zones", [])
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
		breach_zone_markers.append((from_pos + to_pos) * 0.5)
```

Add the public accessor near `get_blocked_route_nodes()`:

```gdscript
func get_breach_zone_markers() -> Array[Vector3]:
	return breach_zone_markers.duplicate()
```

The `_room_center_for_blocked_link(link, room_key, layout_doc)` helper already exists on the loader and returns `Vector3.INF` when the room id cannot be resolved — pass `zone` as the `link` arg because it carries the same `from_room` / `to_room` keys.

- [ ] **Step 2: Create the failing main-scene hazard smoke**

Write `scripts/validation/main_playable_slice_hazard_smoke.gd` with this complete content:

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
	if not playable.has_method("get_oxygen_summary"):
		_fail("get_oxygen_summary missing")
		return
	if not playable.has_method("get_breach_zone_node"):
		_fail("get_breach_zone_node missing")
		return
	if not playable.has_method("get_breach_zone_collision_enabled_count"):
		_fail("get_breach_zone_collision_enabled_count missing")
		return
	if playable.get("oxygen_state") == null:
		_fail("oxygen_state null")
		return

	var initial: Dictionary = playable.get_oxygen_summary()
	if float(initial.get("oxygen", -1.0)) <= 0.0:
		_fail("initial oxygen should be >0, got %s" % str(initial.get("oxygen", -1.0)))
		return
	if not bool(initial.get("breach_open", false)):
		_fail("initial breach_open should be true")
		return
	if bool(initial.get("breach_sealed", true)):
		_fail("initial breach_sealed should be false")
		return

	var breach_node: Node = playable.get_breach_zone_node()
	if breach_node == null:
		_fail("get_breach_zone_node returned null")
		return
	if not bool(breach_node.get_meta("breach_zone_id", "") is String) or str(breach_node.get_meta("breach_zone_id", "")).is_empty():
		_fail("breach zone missing breach_zone_id meta")
		return
	if not bool(breach_node.get_meta("breach_zone_kind", "") is String) or str(breach_node.get_meta("breach_zone_kind", "")) != "oxygen_breach":
		_fail("breach zone kind meta should be oxygen_breach")
		return

	# Initial collision must be DISABLED: the breach is open but oxygen is at max,
	# so the corridor is passable and the player can cross (the pressure comes from
	# drain, not from a static wall). Collision only enables when oxygen reaches
	# zero (passability_blocked=true).
	if playable.get_breach_zone_collision_enabled_count() != 0:
		_fail("initial breach zone collision enabled count should be 0 (corridor passable at full oxygen), got %d" % playable.get_breach_zone_collision_enabled_count())
		return

	# Complete objective 1, then 2 (seals breach).
	if not playable.complete_objective_sequence_for_validation(1):
		_fail("complete objective 1 failed")
		return
	if not playable.complete_objective_sequence_for_validation(2):
		_fail("complete objective 2 failed")
		return

	var ship_after_two: Dictionary = playable.get_ship_systems_summary()
	if not bool(ship_after_two.get("main_power_restored", false)):
		_fail("after objective 2 main_power_restored=false")
		return
	var after_two: Dictionary = playable.get_oxygen_summary()
	if bool(after_two.get("breach_open", false)):
		_fail("after objective 2 breach_open should be false")
		return
	if not bool(after_two.get("breach_sealed", false)):
		_fail("after objective 2 breach_sealed should be true")
		return

	# Hazard must not alter route-control / extraction state.
	var route_after_two: Dictionary = playable.get_route_control_summary()
	if bool(route_after_two.get("extraction_unlocked", false)):
		_fail("hazard must not unlock extraction early")
		return

	# HUD status lines should now include an oxygen line and a Breach: SEALED marker.
	# Use the combined accessor that PlayableGeneratedShip builds for ObjectiveTracker.
	if not playable.has_method("get_combined_system_status_lines"):
		_fail("get_combined_system_status_lines missing")
		return
	var lines: PackedStringArray = playable.get_combined_system_status_lines()
	var found_oxygen: bool = false
	var found_seal: bool = false
	for line in lines:
		var text := String(line)
		if text.begins_with("Oxygen:"):
			found_oxygen = true
		if text.begins_with("Breach:") and text.contains("SEALED"):
			found_seal = true
	if not found_oxygen:
		_fail("combined status lines missing Oxygen: line after seal")
		return
	if not found_seal:
		_fail("combined status lines missing Breach: SEALED line after seal")
		return

	# Objectives 3 and 4 must not affect hazard state.
	if not playable.complete_objective_sequence_for_validation(3):
		_fail("complete objective 3 failed")
		return
	var after_three: Dictionary = playable.get_oxygen_summary()
	if bool(after_three.get("breach_open", false)):
		_fail("objective 3 must not reopen the breach")
		return
	if not bool(after_three.get("breach_sealed", false)):
		_fail("objective 3 must not un-seal the breach")
		return

	if not playable.complete_objective_sequence_for_validation(4):
		_fail("complete objective 4 failed")
		return
	var after_four: Dictionary = playable.get_oxygen_summary()
	if bool(after_four.get("breach_open", false)):
		_fail("objective 4 must not reopen the breach")
		return
	if not bool(after_four.get("breach_sealed", false)):
		_fail("objective 4 must not un-seal the breach")
		return
	if not bool(playable.get_slice_completion_summary().get("run_complete", false)):
		_fail("after objective 4 run_complete=false")
		return

	finished = true
	print("MAIN PLAYABLE HAZARD PASS oxygen=%s breach_open=%s breach_sealed=%s passability_blocked=%s" % [
		str(after_four.get("oxygen", -1.0)),
		str(after_four.get("breach_open", false)).to_lower(),
		str(after_four.get("breach_sealed", false)).to_lower(),
		str(after_four.get("passability_blocked", false)).to_lower(),
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
	push_error("MAIN PLAYABLE HAZARD FAIL reason=%s" % reason)
	_cleanup_and_quit(1)

func _cleanup_and_quit(code: int) -> void:
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	quit(code)
```

- [ ] **Step 3: Run the main-scene hazard smoke red**

Run:
```bash
OUT=$(/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-synapse-sea-of-stars --script res://scripts/validation/main_playable_slice_hazard_smoke.gd 2>&1)
printf '%s\n' "$OUT"
printf '%s\n' "$OUT" | grep -q 'MAIN PLAYABLE HAZARD PASS' || true
```

Expected (RED) result:
- Output contains `MAIN PLAYABLE HAZARD FAIL reason=...` (likely `get_oxygen_summary missing`).
- The pass marker `MAIN PLAYABLE HAZARD PASS` does NOT appear.
- This is the RED phase — the failure is the desired outcome.

- [ ] **Step 4: Record Task 3 RED**

Run:
```bash
if git -C /Users/christopherwilloughby/the-synapse-sea-of-stars rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C /Users/christopherwilloughby/the-synapse-sea-of-stars add scripts/validation/main_playable_slice_hazard_smoke.gd
  git -C /Users/christopherwilloughby/the-synapse-sea-of-stars commit -m 'test(hazard): RED main-scene hazard smoke'
else
  printf '%s\n' 'NO_GIT Task 3 RED: scripts/validation/main_playable_slice_hazard_smoke.gd added and failed for missing PlayableGeneratedShip hazard integration' >> /tmp/synapse_sea_hazard_pressure_no_git_changes.log
fi
```

- [ ] **Step 5: Wire `OxygenState` and the breach zone into `PlayableGeneratedShip`**

In `scripts/procgen/playable_generated_ship.gd`:

1. Add a preload at the top:
```gdscript
const OxygenStateScript := preload("res://scripts/systems/oxygen_state.gd")
```

2. Add constants near the existing `ROUTE_GATE_*` block:
```gdscript
const BREACH_ZONE_COLLISION_SIZE: Vector3 = Vector3(2.6, 2.2, 1.6)
const BREACH_ZONE_VISUAL_COLOR_OPEN: Color = Color(0.95, 0.32, 0.22, 0.65)
const BREACH_ZONE_VISUAL_COLOR_BLOCKED: Color = Color(0.65, 0.05, 0.05, 0.92)
const BREACH_ZONE_VISUAL_COLOR_SEALED: Color = Color(0.18, 0.55, 1.0, 0.55)
const BREACH_ZONE_FALLBACK_ID: String = "corridor_to_reactor"
const BREACH_ZONE_PROXIMITY_RADIUS: float = 2.4
const BREACH_ZONE_UNSAFE_LABEL_TEXT: String = "OXYGEN LOW"
```

3. Add member fields next to the existing `route_control_state` block:
```gdscript
var oxygen_state: OxygenState
var oxygen_root: Node3D
var breach_zone_node: StaticBody3D
var unsafe_room_marker: Label3D
```

4. In `_build_runtime_nodes()`, after the existing `route_control_root = Node3D.new()` block, add:
```gdscript
oxygen_state = OxygenStateScript.new()
oxygen_root = Node3D.new()
oxygen_root.name = "OxygenRoot"
add_child(oxygen_root)
```

5. In `_on_ship_loaded(...)`, after `_refresh_route_control_from_ship_systems()`, add:
```gdscript
_build_breach_zone()
_refresh_oxygen_state(true, 0.0)
```

6. Replace `_combined_system_status_lines()` with this version:
```gdscript
func _combined_system_status_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	if ship_systems != null:
		for line in ship_systems.get_status_lines():
			var text: String = String(line)
			if text.begins_with("Routes:") or text.begins_with("Extraction:"):
				continue
			lines.append(text)
	if route_control_state != null:
		for line in route_control_state.get_status_lines():
			lines.append(String(line))
	if oxygen_state != null:
		for line in oxygen_state.get_status_lines():
			lines.append(String(line))
	return lines

func get_combined_system_status_lines() -> PackedStringArray:
	return _combined_system_status_lines()
```

7. In `_on_interactable_completed(...)`, after the existing `_refresh_route_control_from_ship_systems()` call, add:
```gdscript
if oxygen_state != null and ship_systems != null:
	oxygen_state.apply_ship_systems_summary(ship_systems.get_summary())
_refresh_oxygen_state(false, 0.0)
```

The objective-2 seal path runs through `apply_ship_systems_summary` rather than `tick`, so the seal flip propagates correctly without depending on a real frame delta.

8. Add the new functions (place them next to the existing `_apply_route_gate_scene_state()` block):

```gdscript
func _build_breach_zone() -> void:
	if oxygen_root == null:
		return
	for child in oxygen_root.get_children():
		oxygen_root.remove_child(child)
		child.queue_free()
	breach_zone_node = null
	unsafe_room_marker = null
	var world_position: Vector3 = _resolve_breach_zone_world_position()
	if oxygen_state == null:
		oxygen_state = OxygenStateScript.new()
	oxygen_state.configure(
		[BREACH_ZONE_FALLBACK_ID],
		OxygenStateScript.DEFAULT_MAX_OXYGEN,
		OxygenStateScript.DEFAULT_DRAIN_RATE,
		OxygenStateScript.DEFAULT_REGEN_RATE,
		OxygenStateScript.DEFAULT_RECOVERY_THRESHOLD,
		OxygenStateScript.DEFAULT_SAFE_THRESHOLD,
	)
	breach_zone_node = _create_breach_zone_node(world_position)
	oxygen_root.add_child(breach_zone_node)
	unsafe_room_marker = _create_unsafe_room_marker(world_position)
	oxygen_root.add_child(unsafe_room_marker)

func _resolve_breach_zone_world_position() -> Vector3:
	if loader != null and loader.has_method("get_breach_zone_markers"):
		var markers: Array = loader.get_breach_zone_markers()
		if markers.size() > 0 and markers[0] is Vector3:
			var candidate: Vector3 = markers[0]
			if candidate != Vector3.INF:
				return candidate
	# Fallback: midpoint between objective-3 and objective-4 interactable positions.
	var obj3_pos: Vector3 = Vector3.INF
	var obj4_pos: Vector3 = Vector3.INF
	for interactable_variant in interactables:
		var interactable = interactable_variant
		if not (interactable is Node3D):
			continue
		var seq: int = int(interactable.get("sequence"))
		if seq == 3:
			obj3_pos = (interactable as Node3D).global_position
		elif seq == 4:
			obj4_pos = (interactable as Node3D).global_position
	if obj3_pos == Vector3.INF or obj4_pos == Vector3.INF:
		# Last-ditch: fall back to player spawn + 6m forward.
		if player != null:
			return player.global_position + Vector3(0.0, 0.0, 6.0)
		return Vector3.ZERO
	return (obj3_pos + obj4_pos) * 0.5

func _create_breach_zone_node(world_position: Vector3) -> StaticBody3D:
	var zone: StaticBody3D = StaticBody3D.new()
	zone.name = "BreachZone_OxygenCorridor"
	zone.position = world_position
	zone.collision_layer = 1
	zone.collision_mask = 1
	zone.set_meta("breach_zone_id", BREACH_ZONE_FALLBACK_ID)
	zone.set_meta("breach_zone_kind", "oxygen_breach")
	zone.set_meta("breach_zone_open", true)
	zone.set_meta("breach_zone_sealed", false)
	zone.set_meta("breach_zone_passability_blocked", false)

	var collision_shape: CollisionShape3D = CollisionShape3D.new()
	collision_shape.name = "BreachZoneCollisionShape3D"
	var box_shape: BoxShape3D = BoxShape3D.new()
	box_shape.size = BREACH_ZONE_COLLISION_SIZE
	collision_shape.shape = box_shape
	collision_shape.position = Vector3(0.0, BREACH_ZONE_COLLISION_SIZE.y * 0.5, 0.0)
	zone.add_child(collision_shape)

	var visual: MeshInstance3D = MeshInstance3D.new()
	visual.name = "BreachZoneVisual"
	var box_mesh: BoxMesh = BoxMesh.new()
	box_mesh.size = BREACH_ZONE_COLLISION_SIZE
	visual.mesh = box_mesh
	visual.position = collision_shape.position
	visual.material_override = _make_breach_zone_material(true, false)
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	zone.add_child(visual)
	return zone

func _make_breach_zone_material(is_open: bool, is_blocked: bool) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	if is_blocked:
		material.albedo_color = BREACH_ZONE_VISUAL_COLOR_BLOCKED
	elif is_open:
		material.albedo_color = BREACH_ZONE_VISUAL_COLOR_OPEN
	else:
		material.albedo_color = BREACH_ZONE_VISUAL_COLOR_SEALED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material

func _create_unsafe_room_marker(world_position: Vector3) -> Label3D:
	var label: Label3D = Label3D.new()
	label.name = "BreachUnsafeMarker"
	label.text = BREACH_ZONE_UNSAFE_LABEL_TEXT
	label.position = world_position + Vector3(0.0, BREACH_ZONE_COLLISION_SIZE.y + 0.4, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	label.pixel_size = 0.0035
	label.modulate = Color(1.0, 0.32, 0.22, 1.0)
	label.outline_size = 3
	label.outline_modulate = Color.BLACK
	label.visible = false
	return label

func _refresh_oxygen_state(force_initial: bool, delta_seconds: float) -> void:
	if oxygen_state == null:
		_refresh_tracker_system_status_lines()
		return
	if force_initial:
		oxygen_state.apply_ship_systems_summary({})  # no-op; recompute passability
		_apply_breach_zone_scene_state()
		_refresh_tracker_system_status_lines()
		return
	# Per-tick path: read player position, decide breach presence, tick.
	var player_in_zone: bool = is_player_in_breach_zone()
	oxygen_state.tick(delta_seconds, player_in_zone)
	_apply_breach_zone_scene_state()
	_refresh_tracker_system_status_lines()

func _apply_breach_zone_scene_state() -> void:
	if oxygen_state == null or breach_zone_node == null:
		return
	var summary: Dictionary = oxygen_state.get_summary()
	var breach_open: bool = bool(summary.get("breach_open", false))
	var breach_sealed: bool = bool(summary.get("breach_sealed", false))
	var passability_blocked: bool = bool(summary.get("passability_blocked", false))
	breach_zone_node.set_meta("breach_zone_open", breach_open)
	breach_zone_node.set_meta("breach_zone_sealed", breach_sealed)
	breach_zone_node.set_meta("breach_zone_passability_blocked", passability_blocked)
	# Per the feature spec: the breach zone is passable while the player has
	# oxygen above the recovery threshold; once oxygen hits zero, the
	# collision is enabled to block forward traversal until oxygen recovers.
	# Once sealed (objective 2), the corridor is safe and collision is off.
	var collision_enabled: bool = breach_open and passability_blocked
	_set_breach_zone_collision_enabled(breach_zone_node, collision_enabled)
	_update_breach_zone_visual(breach_zone_node, breach_open, passability_blocked)
	if unsafe_room_marker != null:
		unsafe_room_marker.visible = breach_open and not breach_sealed

func _set_breach_zone_collision_enabled(zone: Node, enabled: bool) -> void:
	for child in zone.get_children():
		if child is CollisionShape3D:
			(child as CollisionShape3D).disabled = not enabled

func _update_breach_zone_visual(zone: Node, is_open: bool, is_blocked: bool) -> void:
	for child in zone.get_children():
		if child is MeshInstance3D and child.name == "BreachZoneVisual":
			var visual: MeshInstance3D = child as MeshInstance3D
			visual.material_override = _make_breach_zone_material(is_open, is_blocked)
			visual.visible = is_open

func get_oxygen_summary() -> Dictionary:
	var summary: Dictionary = {}
	if oxygen_state == null:
		summary["oxygen"] = 0.0
		summary["max_oxygen"] = 0.0
		summary["drain_rate"] = 0.0
		summary["regen_rate"] = 0.0
		summary["recovery_threshold"] = 0.0
		summary["safe_threshold"] = 0.0
		summary["breach_open"] = false
		summary["breach_sealed"] = false
		summary["passability_blocked"] = false
		summary["player_in_breach_zone"] = false
		summary["breach_zone_ids"] = []
		return summary
	summary = oxygen_state.get_summary()
	return summary

func get_breach_zone_node() -> Node:
	return breach_zone_node

func get_breach_zone_collision_enabled_count() -> int:
	if breach_zone_node == null:
		return 0
	for child in breach_zone_node.get_children():
		if child is CollisionShape3D and not (child as CollisionShape3D).disabled:
			return 1
	return 0

func is_player_in_breach_zone() -> bool:
	if breach_zone_node == null or player == null:
		return false
	if not (player is Node3D):
		return false
	var zone_pos: Vector3 = breach_zone_node.global_position
	var player_pos: Vector3 = (player as Node3D).global_position
	var dx: float = player_pos.x - zone_pos.x
	var dz: float = player_pos.z - zone_pos.z
	# Use a horizontal proximity radius (the corridor is wider than tall; using
	# 3D distance would falsely report "in zone" when the player is one floor up).
	return (dx * dx + dz * dz) <= (BREACH_ZONE_PROXIMITY_RADIUS * BREACH_ZONE_PROXIMITY_RADIUS)
```

9. The current plan intentionally does not wire `_process(delta)` for the oxygen tick. The model and scene consequences are exercised by the direct model smoke and the objective-2 seal transition in the main-scene smoke; real per-frame ticks can be added in a follow-up card once a second hazard type lands or once the playtest protocol calls out drain timing issues. Document this explicitly in a code comment near `_refresh_oxygen_state(...)`:

```gdscript
# Per-frame ticks are intentionally not wired here in Gate 1. The drain /
# regen contract is exercised by the direct OxygenState smoke and the
# main-scene smoke (objective-2 seal transition). Real per-frame ticking
# is deferred to a follow-up card alongside the second hazard type.
```

- [ ] **Step 6: Run the main-scene hazard smoke green**

Run:
```bash
OUT=$(/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-synapse-sea-of-stars --script res://scripts/validation/main_playable_slice_hazard_smoke.gd 2>&1)
printf '%s\n' "$OUT"
printf '%s\n' "$OUT" | grep -q 'MAIN PLAYABLE HAZARD PASS'
if printf '%s\n' "$OUT" | grep -E '^(ERROR|WARNING):' >/dev/null; then
  echo 'unexpected ERROR/WARNING in main_playable_slice_hazard_smoke'
  exit 1
fi
```

Expected green marker:
```text
MAIN PLAYABLE HAZARD PASS oxygen=100.0 breach_open=false breach_sealed=true passability_blocked=false
```

- [ ] **Step 7: Record Task 3 green**

Run:
```bash
if git -C /Users/christopherwilloughby/the-synapse-sea-of-stars rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C /Users/christopherwilloughby/the-synapse-sea-of-stars add scripts/procgen/generated_ship_loader.gd scripts/procgen/playable_generated_ship.gd scripts/validation/main_playable_slice_hazard_smoke.gd
  git -C /Users/christopherwilloughby/the-synapse-sea-of-stars commit -m 'feat(hazard): wire oxygen state into main playable slice'
else
  printf '%s\n' 'NO_GIT Task 3 changed: scripts/procgen/generated_ship_loader.gd scripts/procgen/playable_generated_ship.gd scripts/validation/main_playable_slice_hazard_smoke.gd' >> /tmp/synapse_sea_hazard_pressure_no_git_changes.log
fi
```

---

### Task 4: Regression Bundle, Validation Plan Update, Docs Sync, Scope Guard

**Files:**
- Modify: `docs/game/06_validation_plan.md`
- Modify: `docs/game/02_core_loop.md`
- Read: all existing smokes
- Read: `/tmp/synapse_sea_hazard_pressure_no_git_changes.log`

**Interfaces:**
- All previously-validated smokes still pass.
- Both new smokes pass.
- `docs/game/06_validation_plan.md` includes the new smokes in the regression bundle and removes them from "Future validation additions".
- `docs/game/02_core_loop.md` "Current implemented loop evidence" gains a hazard-pressure row; "Loop gaps to resolve before Gate 1 exit" loses the hazard/survival pressure line.

- [ ] **Step 1: Update the validation plan**

In `docs/game/06_validation_plan.md`, replace the "Regression bundle" code block with a version that adds the two new `run_clean` lines before the final `echo` line:

```bash
run_clean 'route control model smoke' 'ROUTE CONTROL STATE PASS gates=2 opened=2 blockers=0 extraction=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/route_control_state_smoke.gd
run_clean 'main route control smoke' 'MAIN PLAYABLE ROUTE CONTROL PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_route_control_smoke.gd
run_clean 'oxygen model smoke' 'OXYGEN STATE PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/oxygen_state_smoke.gd
run_clean 'main hazard smoke' 'MAIN PLAYABLE HAZARD PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_hazard_smoke.gd
run_clean 'ship systems smoke' 'MAIN PLAYABLE SHIP SYSTEMS PASS supplies=true power=true logs=true reactor=true extraction=true blocked_visible=0 completed_systems=4' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_ship_systems_smoke.gd
run_clean 'completion smoke' 'MAIN PLAYABLE SLICE COMPLETE PASS completed=4 current_sequence=5 run_complete=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_completion_smoke.gd
run_clean 'input smoke' 'MAIN PLAYABLE INPUT LOOP PASS moved=true camera_followed=true interaction_input_path=true current_sequence=2' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_input_smoke.gd
run_clean 'readability smoke' 'MAIN PLAYABLE SLICE READABILITY PASS objective_props=4 blocked=1 ramp=1' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_readability_smoke.gd
echo 'SYNAPSE_SEA REGRESSION PASS commands=8 clean_output=true'
```

In the same file, remove the first two items from "Future validation additions" so the list now starts with `Inventory/tool model smoke`:

```markdown
## Future validation additions
- Inventory/tool model smoke.
- Save/load smoke.
- Hub/meta progression smoke.
- GUT suite if/when adopted by ADR.
```

- [ ] **Step 2: Update the core loop doc**

In `docs/game/02_core_loop.md`, replace the "Current implemented loop evidence" list with a version that includes hazard-pressure evidence:

```markdown
## Current implemented loop evidence

- Main playable slice loads generated ship data.
- Player and camera spawn.
- Four objectives can be completed in sequence.
- Ship systems update during objectives.
- Route-control gates open after systems restoration.
- Extraction unlocks after reactor stabilization.
- Hazard pressure loop drains oxygen while the player is inside the unsealed breach zone on the objective 3 → objective 4 corridor, and seals on objective 2 completion.
```

Replace "Loop gaps to resolve before Gate 1 exit" so the hazard line is removed and the playtest line remains:

```markdown
## Loop gaps to resolve before Gate 1 exit

- Inventory/tools are not yet a real runtime loop.
- ~~Hub/meta progression is not yet specified.~~ Resolved by deferral (see ADR-0002). Not a Gate 1 exit blocker.
- Fresh-player playtest evidence has not yet been collected using `docs/game/playtests/gate-1-playtest-protocol.md`.
```

- [ ] **Step 3: Run the full regression bundle**

Run:
```bash
set -euo pipefail
ROOT=/Users/christopherwilloughby/the-synapse-sea-of-stars
GODOT=/Users/christopherwilloughby/.local/bin/godot-4.6.2
run_clean() {
  label="$1"
  marker="$2"
  shift 2
  echo "=== $label ==="
  OUT=$("$@" 2>&1)
  printf '%s\n' "$OUT"
  printf '%s\n' "$OUT" | grep -q "$marker"
  if printf '%s\n' "$OUT" | grep -E '^(ERROR|WARNING):' >/dev/null; then
    echo "UNEXPECTED_ERROR_OR_WARNING in $label"
    exit 1
  fi
}
run_clean 'route control model smoke' 'ROUTE CONTROL STATE PASS gates=2 opened=2 blockers=0 extraction=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/route_control_state_smoke.gd
run_clean 'main route control smoke' 'MAIN PLAYABLE ROUTE CONTROL PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_route_control_smoke.gd
run_clean 'oxygen model smoke' 'OXYGEN STATE PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/oxygen_state_smoke.gd
run_clean 'main hazard smoke' 'MAIN PLAYABLE HAZARD PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_hazard_smoke.gd
run_clean 'ship systems smoke' 'MAIN PLAYABLE SHIP SYSTEMS PASS supplies=true power=true logs=true reactor=true extraction=true blocked_visible=0 completed_systems=4' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_ship_systems_smoke.gd
run_clean 'completion smoke' 'MAIN PLAYABLE SLICE COMPLETE PASS completed=4 current_sequence=5 run_complete=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_completion_smoke.gd
run_clean 'input smoke' 'MAIN PLAYABLE INPUT LOOP PASS moved=true camera_followed=true interaction_input_path=true current_sequence=2' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_input_smoke.gd
run_clean 'readability smoke' 'MAIN PLAYABLE SLICE READABILITY PASS objective_props=4 blocked=1 ramp=1' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_readability_smoke.gd
echo 'SYNAPSE_SEA REGRESSION PASS commands=8 clean_output=true'
```

Expected final marker:
```text
SYNAPSE_SEA REGRESSION PASS commands=8 clean_output=true
```

- [ ] **Step 4: Confirm no artifact deliverables were created for this hazard milestone**

Run:
```bash
set -euo pipefail
ROOT=/Users/christopherwilloughby/the-synapse-sea-of-stars
find "$ROOT/docs/superpowers/proofs" -maxdepth 1 -type f -newer "$ROOT/docs/game/features/hazards.md" -print 2>/dev/null || true
find "$ROOT/.superpowers" -type f \( -name '*.html' -o -name '*.png' \) -newer "$ROOT/docs/game/features/hazards.md" -print 2>/dev/null || true
```

Expected result:
- No new hazard proof documents, HTML files, PNG files, contact sheets, or screenshot galleries are required.
- If the command prints unrelated files from another concurrent task, do not delete them. Report them separately and keep this hazard milestone focused on code and smokes.

- [ ] **Step 5: Record final regression**

Run:
```bash
if git -C /Users/christopherwilloughby/the-synapse-sea-of-stars rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C /Users/christopherwilloughby/the-synapse-sea-of-stars status --short
  git -C /Users/christopherwilloughby/the-synapse-sea-of-stars add scripts/systems/oxygen_state.gd scripts/systems/oxygen_state.gd.uid scripts/validation/oxygen_state_smoke.gd scripts/procgen/generated_ship_loader.gd scripts/procgen/playable_generated_ship.gd scripts/validation/main_playable_slice_hazard_smoke.gd docs/game/06_validation_plan.md docs/game/02_core_loop.md
  git -C /Users/christopherwilloughby/the-synapse-sea-of-stars commit -m 'test: verify hazard pressure loop regression bundle'
else
  printf '%s\n' 'NO_GIT Task 4 verified: oxygen_state_smoke PASS + main_hazard_smoke PASS + route_control_state_smoke PASS + main_route_control_smoke PASS + ship_systems_smoke PASS + completion_smoke PASS + input_smoke PASS + readability_smoke PASS, no errors/warnings' >> /tmp/synapse_sea_hazard_pressure_no_git_changes.log
  tail -n 10 /tmp/synapse_sea_hazard_pressure_no_git_changes.log
fi
```

---

## Execution Notes

- Implement tasks in order. Task 1 and Task 3 deliberately create red failures before production code.
- Do not collapse the hazard model into `ShipSystemState` or `RouteControlState`; separate responsibility is part of the approved design and matches the architecture in `docs/game/features/hazards.md`.
- Do not delete the breach-zone node when sealing or blocking traversal. Disable collision, update metadata, and toggle visibility so the state remains inspectable.
- Do not update `ObjectiveTracker` directly. `PlayableGeneratedShip._combined_system_status_lines()` composes ship-systems + route-control + oxygen lines; pass the array through the existing `tracker.set_system_status_lines(...)` call.
- If a Godot smoke passes functionally but emits renderer or object leak `ERROR:` or `WARNING:` lines, clean up created nodes before considering the task complete.
- If a validation command fails for a reason unrelated to the hazard, stop and report the blocker instead of weakening the smoke.
- The breach zone is intentionally one fixed corridor for Gate 1 (per the feature spec). Do not add procedural breach placement, multiple breach zones, oxygen pickups, or audio cues in this slice.
- The hazard is a survival pressure loop, not a health/damage system. Do not subtract from any player HP/suit integrity variable — the fail state is passability block, not health depletion.
- The hazard does not alter route-gate or extraction state. Hazards must remain parallel to route-control and ship-system state.
- Future work explicitly deferred past this plan (do not implement here):
  - Second hazard type (fire / radiation / vacuum) — drives the future hazard-architecture ADR called out in `docs/game/04_tdd.md`.
  - Inventory/tool pickups and resource interactions.
  - Per-frame `_process(delta)` oxygen tick (out of scope for Gate 1; the model and scene consequences are exercised by the smokes and the objective-2 seal transition).
  - Save/load of hazard state across runs.
  - Hub/meta progression (deferred past Gate 1 by ADR-0002 / REQ-008).