# Inventory / Tool Loop Implementation Plan (REQ-007)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Gate 2 inventory/tool loop for the single `portable_oxygen_pump` tool so that acquiring it from a runtime pickup changes the oxygen hazard outcome, updates the HUD/status line, and is validated by a direct model smoke and a main-scene smoke.

**Architecture:** Add a pure `InventoryState` model (parallel to `ShipSystemState`, `RouteControlState`, and `OxygenState`) that owns the current slice's `tool_ids`. Add one tool definition resource/JSON for `portable_oxygen_pump`. Add a `ToolPickup` interactable node spawned in a fixed side room (`tool_storage_01` with a fallback near the entry room). `OxygenState` gains an `apply_inventory_summary(summary: Dictionary)` seam that computes a drain multiplier before `tick(...)`. `PlayableGeneratedShip` owns the `InventoryState` instance, passes its summary into `OxygenState` each frame before ticking, routes tool status lines into the existing HUD, and handles the pickup interaction. Save/load (REQ-012) will later serialize `InventoryState.tool_ids` as part of the current-run snapshot; this plan only adds the inventory model so the save/load feature can consume it.

**Tech Stack:** Godot 4.6.2 GDScript, `SceneTree` validation smokes, existing `res://scenes/main.tscn`, existing `PlayableGeneratedShip`, existing `OxygenState`, existing `ObjectiveTracker`, no external runtime dependencies.

**Source requirements:**
- `docs/game/features/inventory_tools.md`
- `docs/game/05_requirements.md#req-007-inventorytool-loop`
- `docs/gate2/gate2-scope-note.md`
- Preserve REQ-001, REQ-002, REQ-003, REQ-006; obey REQ-004 and REQ-005.

## Global Constraints

- Project root: `/Users/christopherwilloughby/the-synapse-sea-of-stars`.
- Godot binary: `/Users/christopherwilloughby/.local/bin/godot-4.6.2`.
- Workspace state checked on 2026-06-19: `GIT_INSIDE=false`.
- Do not create HTML, PNG, contact sheets, screenshot galleries, or proof documents for this milestone.
- Use TDD: write failing smoke(s), run them red, then implement runtime code.
- The tool must be a real acquired runtime state that changes oxygen drain, not just a HUD decoration or a proof prop.
- Tool behavior must preserve the existing objective sequence: `restore_systems` (objective 2) still seals the breach; `stabilize_reactor` (objective 4) still unlocks extraction; route gates, extraction, and fire hazards are unchanged by inventory state.
- The inventory/tool milestone has no proof artifacts as deliverables; validation is command-output smokes only.
- Preserve existing validation seams and smokes: `complete_objective_sequence_for_validation()`, `complete_all_objectives_for_validation()`, `main_playable_slice_hazard_smoke.gd`, `main_playable_slice_route_control_smoke.gd`, ship_systems/completion/input/readability smokes must keep passing.
- Output from validation commands must be clean of unexpected lines beginning with `ERROR:` or `WARNING:`.
- Because this is not a git repository, every task uses the no-git ledger fallback at `/tmp/synapse_sea_inventory_tool_no_git_changes.log` instead of assuming `git commit` works.
- Do not collapse `InventoryState` into `ShipSystemState` or `OxygenState`; keep separate responsibility.
- Do not delete the pickup node on acquisition — hide it and mark it acquired so state remains inspectable.
- Do not introduce equipment UI/grid, crafting, durability, charges, dropping, trading, hub-stored tools, route-gate keys, audio cues, particle VFX, or animation polish in this slice (non-goals in `features/inventory_tools.md`).
- Gate 2 ships exactly one tool. If implementation wants to generalize the data model beyond one hard-coded multiplier, block and raise ADR-0004 first.

---

## File Structure

Create:

- `scripts/systems/inventory_state.gd`
  - Pure runtime model for the current slice's tool inventory.
  - Extends `RefCounted`, class_name `InventoryState`.
  - No scene-tree access.
  - Methods: `add_tool(tool_id: String) -> bool`, `has_tool(tool_id: String) -> bool`, `remove_tool(tool_id: String) -> bool`, `reset()`, `get_summary() -> Dictionary`, `get_status_lines() -> PackedStringArray`.
  - Summary shape: `{ "tool_ids": Array[String], "active_effects": Array[Dictionary] }`.
  - Status lines: one line per carried tool formatted `Tool: <Display Name>` (e.g., `Tool: Portable Oxygen Pump`).

- `data/tools/tool_definitions.json`
  - Single Gate 2 definition:
    ```json
    {
      "portable_oxygen_pump": {
        "display_name": "Portable Oxygen Pump",
        "effect": {
          "type": "oxygen_drain_multiplier",
          "value": 0.5
        }
      }
    }
    ```
  - Loaded by a small helper in `scripts/tools/tool_database.gd` or directly by `InventoryState` (implementation choice documented below).

- `scripts/tools/tool_database.gd` (optional but recommended)
  - Pure helper extending `RefCounted` or static utility.
  - Loads `data/tools/tool_definitions.json` once.
  - Provides `get_definition(tool_id: String) -> Dictionary` and `get_display_name(tool_id: String) -> String`.
  - Returns an empty Dictionary for unknown ids so `OxygenState` treats missing effects as multiplier `1.0`.

- `scripts/tools/tool_pickup.gd`
  - Extends `Area3D`, class_name `ToolPickup`.
  - Configured with `tool_id: String` and a reference to the owning `InventoryState`.
  - Emits `tool_acquired(tool_id: String)` once on first successful interaction.
  - `try_interact(player_body: Node) -> bool` mirrors `Interactable.try_interact` shape and uses a validation seam `set_validation_player_in_range(player_body: Node)` for headless tests.
  - On successful acquisition: calls `inventory_state.add_tool(tool_id)`, hides `marker` and `collision_shape`, sets `acquired = true`.
  - On repeat interaction: returns `false` because `acquired` is already true.
  - Spawns a small `MeshInstance3D` marker (e.g., a box or cylinder) so the main-scene smoke can assert visibility before and after acquisition.

- `scenes/tools/portable_oxygen_pump_pickup.tscn` (optional)
  - A prefab scene containing a `ToolPickup` root with a `CollisionShape3D` and a `MeshInstance3D` marker.
  - If the implementation prefers pure code construction, this scene may be omitted and the pickup built in `_build_tool_pickup()`; the plan allows either approach.

- `scripts/validation/inventory_state_smoke.gd`
  - Direct model smoke for `InventoryState` + `OxygenState` drain multiplier integration.
  - Verifies:
    - Fresh inventory has empty `tool_ids`.
    - `add_tool("portable_oxygen_pump")` returns true and `has_tool(...)` is true.
    - Double add returns false.
    - `OxygenState.tick(1.0, true)` with the pump drains at `drain_rate * 0.5`.
    - `OxygenState.tick(1.0, true)` after removing the pump drains at full `drain_rate`.
    - `get_summary()` includes `tool_ids`, `active_effects`, and `drain_multiplier`.
    - `get_status_lines()` includes `Tool: Portable Oxygen Pump`.
  - Pass marker: `INVENTORY STATE PASS tools=1 pump=true drain_multiplier=0.5`.

- `scripts/validation/main_playable_slice_inventory_smoke.gd`
  - Main-scene runtime smoke.
  - Verifies:
    - `PlayableGeneratedShip` exposes `inventory_state` and `get_inventory_summary()`.
    - A `ToolPickup` node exists and is visible before acquisition.
    - The smoke teleports the player to the pickup, acquires it, and asserts `has_tool("portable_oxygen_pump")`.
    - The pickup node is hidden after acquisition.
    - The HUD status line includes `Tool: Portable Oxygen Pump`.
    - The player is teleported into the breach zone and oxygen drains at the reduced rate.
    - Route-control and extraction state are unchanged by carrying the tool.
  - Pass marker: `MAIN PLAYABLE INVENTORY PASS tool=portable_oxygen_pump acquired=true drain_multiplier=0.5`.

Modify:

- `scripts/systems/oxygen_state.gd`
  - Add `_inventory_summary: Dictionary = {}`.
  - Add `apply_inventory_summary(summary: Dictionary) -> void`.
  - Add `_compute_drain_multiplier() -> float`:
    - Returns `0.5` if `_inventory_summary.tool_ids` contains `"portable_oxygen_pump"` and the breach is unsealed (`breach_open and not breach_sealed`); otherwise returns `1.0`.
    - Ignores unknown tool effects and ids (defensive against future/loaded ids).
  - Modify `tick(...)` so the drain branch uses `drain_rate * _compute_drain_multiplier() * delta_seconds`.
  - Expose `effective_drain_rate: float` in `get_summary()` computed as `drain_rate * _compute_drain_multiplier()`.
  - Ensure `apply_inventory_summary` is called before `tick(...)` in the same frame by `PlayableGeneratedShip`.

- `scripts/procgen/playable_generated_ship.gd`
  - Preload `InventoryState` and `ToolPickup`.
  - Add `inventory_state: InventoryState`.
  - Add `tool_pickup: ToolPickup` and `tool_pickup_root: Node3D`.
  - In `_build_runtime_nodes()`: instantiate `inventory_state = InventoryState.new()`.
  - In `_on_ship_loaded(...)` after `_build_breach_zone()`: call `_build_tool_pickup()`.
  - In `_process(delta)` before `oxygen_state.tick(...)`: call `oxygen_state.apply_inventory_summary(inventory_state.get_summary())`.
  - In `_on_tool_pickup_acquired(tool_id: String)`: hide pickup marker, refresh HUD via `_refresh_tracker_system_status_lines()`.
  - Extend `_combined_system_status_lines()` to append `inventory_state.get_status_lines()` after oxygen lines.
  - Add helpers:
    - `get_inventory_summary() -> Dictionary`
    - `get_tool_pickup_node() -> Node`
    - `acquire_tool_for_validation(tool_id: String) -> bool` — headless seam that teleports the player to the pickup and triggers interaction.
    - `teleport_player_to_tool_pickup_for_validation() -> bool`
  - Add `_build_tool_pickup() -> void`:
    - Determine world position: prefer a room named `tool_storage_01` via `loader.get_room_center("tool_storage_01")` if the loader supports it; otherwise fall back to a fixed offset near the player start (e.g., start position + `Vector3(4.0, 0.0, 0.0)`).
    - Instantiate `ToolPickup`, configure with `tool_id = "portable_oxygen_pump"` and `inventory_state`, add to `tool_pickup_root`.
  - Ensure `_refresh_oxygen_state(force_initial, delta)` is called with the inventory summary applied. The existing `_refresh_oxygen_state` path becomes:
    1. `oxygen_state.apply_inventory_summary(inventory_state.get_summary())`.
    2. `oxygen_state.tick(delta_seconds, player_in_zone)` (or recompute passability on force_initial).
    3. `_apply_breach_zone_scene_state()`.
    4. `_refresh_tracker_system_status_lines()`.

- `scripts/ui/objective_tracker.gd`
  - No changes required if `set_system_status_lines()` is used; inventory status lines are appended by `PlayableGeneratedShip._combined_system_status_lines()`.

- `docs/game/06_validation_plan.md`
  - Add both new smokes to the regression bundle and update the "Future validation additions" section to mark REQ-007 smokes as now included.

Generated by Godot if import/class registration runs:

- `scripts/systems/inventory_state.gd.uid`
- `scripts/tools/tool_pickup.gd.uid`
- `scripts/tools/tool_database.gd.uid` (if created)
- `scripts/validation/inventory_state_smoke.gd.uid`
- `scripts/validation/main_playable_slice_inventory_smoke.gd.uid`
  - Accept these sidecars if Godot creates them.
  - Record them in the no-git ledger.

---

## Data Model Additions

- `InventoryState.tool_ids: Array[String]`
- `InventoryState.active_effects: Array[Dictionary]` (computed from definitions)
- `OxygenState._inventory_summary: Dictionary`
- `OxygenState.effective_drain_rate: float` (computed per tick; exposed in summary)
- `data/tools/tool_definitions.json`
- Save/load (REQ-012) will later serialize `InventoryState.tool_ids` as part of the current-run snapshot.

---

## Task 1: Inventory Model Smoke, RED Phase

**Files:**
- Create: `scripts/validation/inventory_state_smoke.gd`
- Read: `scripts/validation/oxygen_state_smoke.gd` (template)
- Read: `scripts/systems/oxygen_state.gd` (for multiplier contract)

**Interfaces:**
- Consumes intended future class: `InventoryState.new()`.
- Consumes intended future methods:
  - `add_tool(tool_id: String) -> bool`
  - `has_tool(tool_id: String) -> bool`
  - `remove_tool(tool_id: String) -> bool`
  - `reset()`
  - `get_summary() -> Dictionary`
  - `get_status_lines() -> PackedStringArray`
- Consumes intended future `OxygenState` methods:
  - `apply_inventory_summary(summary: Dictionary) -> void`
  - `get_summary()` returns `drain_multiplier` and `effective_drain_rate` keys.
- Produces a failing model smoke with pass marker:
  - `INVENTORY STATE PASS tools=1 pump=true drain_multiplier=0.5`

- [ ] **Step 1: Create the failing model smoke**

Write `scripts/validation/inventory_state_smoke.gd` with this complete content:

```gdscript
extends SceneTree

func _initialize() -> void:
	var inventory := InventoryState.new()
	var initial: Dictionary = inventory.get_summary()
	if not initial.has("tool_ids"):
		_fail("initial summary missing tool_ids")
		return
	if (initial.get("tool_ids") as Array).size() != 0:
		_fail("initial tool_ids should be empty")
		return

	if not inventory.add_tool("portable_oxygen_pump"):
		_fail("add_tool(portable_oxygen_pump) should return true on first add")
		return
	if not inventory.has_tool("portable_oxygen_pump"):
		_fail("has_tool(portable_oxygen_pump) should be true after add")
		return
	if inventory.add_tool("portable_oxygen_pump"):
		_fail("duplicate add_tool should return false")
		return

	var after_add: Dictionary = inventory.get_summary()
	var tool_ids: Array = after_add.get("tool_ids", []) as Array
	if tool_ids.size() != 1:
		_fail("tool_ids should contain exactly one tool")
		return
	if str(tool_ids[0]) != "portable_oxygen_pump":
		_fail("tool_ids[0] should be portable_oxygen_pump, got %s" % str(tool_ids[0]))
		return

	var status_lines: PackedStringArray = inventory.get_status_lines()
	var found_tool_line: bool = false
	for line in status_lines:
		if String(line) == "Tool: Portable Oxygen Pump":
			found_tool_line = true
			break
	if not found_tool_line:
		_fail("status lines missing 'Tool: Portable Oxygen Pump', got %s" % str(status_lines))
		return

	# Verify OxygenState honors the inventory summary.
	var oxygen := OxygenState.new()
	oxygen.configure(
		["corridor_to_reactor"],
		100.0,
		6.0,
		3.5,
		30.0,
		35.0
	)
	oxygen.apply_inventory_summary(inventory.get_summary())
	oxygen.tick(1.0, true)
	var after_pump: Dictionary = oxygen.get_summary()
	var effective_drain_rate: float = float(after_pump.get("effective_drain_rate", -1.0))
	if absf(effective_drain_rate - 3.0) > 0.001:
		_fail("effective_drain_rate with pump should be 3.0, got %s" % str(effective_drain_rate))
		return
	var oxygen_after_pump: float = float(after_pump.get("oxygen", -1.0))
	if absf(oxygen_after_pump - 97.0) > 0.001:
		_fail("oxygen after one pumped tick should be 97.0, got %s" % str(oxygen_after_pump))
		return

	# Remove the pump and confirm full drain returns.
	if not inventory.remove_tool("portable_oxygen_pump"):
		_fail("remove_tool(portable_oxygen_pump) should return true")
		return
	oxygen.apply_inventory_summary(inventory.get_summary())
	oxygen.tick(1.0, true)
	var after_remove: Dictionary = oxygen.get_summary()
	effective_drain_rate = float(after_remove.get("effective_drain_rate", -1.0))
	if absf(effective_drain_rate - 6.0) > 0.001:
		_fail("effective_drain_rate without pump should be 6.0, got %s" % str(effective_drain_rate))
		return

	# Final summary must include the keys called out in the spec.
	var final_inventory: Dictionary = inventory.get_summary()
	for key in ["tool_ids", "active_effects"]:
		if not final_inventory.has(key):
			_fail("inventory summary missing key: %s" % key)
			return

	print("INVENTORY STATE PASS tools=%d pump=%s drain_multiplier=%s" % [
		tool_ids.size(),
		str(inventory.has_tool("portable_oxygen_pump")).to_lower(),
		str(float(after_pump.get("drain_multiplier", -1.0))),
	])
	quit(0)

func _fail(reason: String) -> void:
	push_error("INVENTORY STATE FAIL reason=%s" % reason)
	quit(1)
```

- [ ] **Step 2: Run the model smoke red**

Run:
```bash
OUT=$(/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-synapse-sea-of-stars --script res://scripts/validation/inventory_state_smoke.gd 2>&1)
printf '%s\n' "$OUT"
printf '%s\n' "$OUT" | grep -q 'INVENTORY STATE PASS' || true
```

Expected (RED) result:
- Output contains `INVENTORY STATE FAIL reason=...` (likely `InventoryState` is undefined or `add_tool(...)` is missing).
- The pass marker `INVENTORY STATE PASS` does NOT appear.
- This is the RED phase — the failure is the desired outcome.

- [ ] **Step 3: Record Task 1 RED**

Run:
```bash
if git -C /Users/christopherwilloughby/the-synapse-sea-of-stars rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C /Users/christopherwilloughby/the-synapse-sea-of-stars add scripts/validation/inventory_state_smoke.gd
  git -C /Users/christopherwilloughby/the-synapse-sea-of-stars commit -m 'test(inventory): RED inventory/tool model smoke (REQ-007)'
else
  printf '%s\n' 'NO_GIT Task 1 RED: scripts/validation/inventory_state_smoke.gd added and failed for missing InventoryState implementation' >> /tmp/synapse_sea_inventory_tool_no_git_changes.log
fi
```

---

## Task 2: Implement `InventoryState` + Tool Definition + Green Model Smoke

**Files:**
- Create: `scripts/systems/inventory_state.gd`
- Create: `data/tools/tool_definitions.json`
- Create: `scripts/tools/tool_database.gd` (optional helper)
- Read: `scripts/systems/route_control_state.gd` (template for pure model shape)

**Interfaces:**
- Produces the classes referenced by the smoke.
- Sidecar `.uid` files may be created by Godot.

- [ ] **Step 1: Create `InventoryState`**

Write `scripts/systems/inventory_state.gd` with this complete content:

```gdscript
extends RefCounted
class_name InventoryState

## Runtime model for the Gate 2 inventory/tool loop.
## This model never reaches into the scene tree. PlayableGeneratedShip owns
## the tool pickup scene node and applies scene consequences from this summary.

const DEFAULT_TOOL_DEFINITIONS_PATH: String = "res://data/tools/tool_definitions.json"

var tool_ids: Array[String] = []
var _definitions: Dictionary = {}

func _init() -> void:
	_load_definitions(DEFAULT_TOOL_DEFINITIONS_PATH)

func _load_definitions(path: String) -> void:
	_definitions.clear()
	if not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		_definitions = parsed

func add_tool(tool_id: String) -> bool:
	if tool_id.is_empty():
		return false
	if tool_ids.has(tool_id):
		return false
	tool_ids.append(tool_id)
	return true

func has_tool(tool_id: String) -> bool:
	return tool_ids.has(tool_id)

func remove_tool(tool_id: String) -> bool:
	var index := tool_ids.find(tool_id)
	if index < 0:
		return false
	tool_ids.remove_at(index)
	return true

func reset() -> void:
	tool_ids.clear()

func get_definition(tool_id: String) -> Dictionary:
	var def: Variant = _definitions.get(tool_id, {})
	if def is Dictionary:
		return def
	return {}

func get_display_name(tool_id: String) -> String:
	var def := get_definition(tool_id)
	var name: String = str(def.get("display_name", ""))
	if name.is_empty():
		return tool_id.replace("_", " ").capitalize()
	return name

func get_summary() -> Dictionary:
	var effects: Array[Dictionary] = []
	for tool_id in tool_ids:
		var def := get_definition(tool_id)
		var effect: Variant = def.get("effect", {})
		if effect is Dictionary:
			effects.append({
				"tool_id": tool_id,
				"type": str(effect.get("type", "")),
				"value": effect.get("value", 1.0),
			})
	return {
		"tool_ids": tool_ids.duplicate(),
		"active_effects": effects,
	}

func get_status_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	for tool_id in tool_ids:
		lines.append("Tool: %s" % get_display_name(tool_id))
	return lines
```

- [ ] **Step 2: Create tool definition data**

Write `data/tools/tool_definitions.json`:

```json
{
  "portable_oxygen_pump": {
    "display_name": "Portable Oxygen Pump",
    "effect": {
      "type": "oxygen_drain_multiplier",
      "value": 0.5
    }
  }
}
```

- [ ] **Step 3: Modify `OxygenState` for inventory multiplier**

In `scripts/systems/oxygen_state.gd`:

1. Add member:
   ```gdscript
   var _inventory_summary: Dictionary = {}
   var effective_drain_rate: float = DEFAULT_DRAIN_RATE
   ```

2. Add method:
   ```gdscript
   func apply_inventory_summary(summary: Dictionary) -> void:
       _inventory_summary = summary.duplicate(true)
   ```

3. Add method:
   ```gdscript
   func _compute_drain_multiplier() -> float:
       if breach_sealed or not breach_open:
           return 1.0
       var ids: Variant = _inventory_summary.get("tool_ids", [])
       if ids is Array and ids.has("portable_oxygen_pump"):
           return 0.5
       return 1.0
   ```

4. Modify `tick(...)` drain branch:
   ```gdscript
   if breach_open and not breach_sealed and player_in_breach_zone:
       var multiplier: float = _compute_drain_multiplier()
       effective_drain_rate = drain_rate * multiplier
       var drained: float = effective_drain_rate * delta_seconds
       if drained > 0.0:
           oxygen = maxf(0.0, oxygen - drained)
           changed = true
   else:
       effective_drain_rate = drain_rate * _compute_drain_multiplier()
   ```

5. Modify `get_summary()` to include:
   ```gdscript
   "effective_drain_rate": effective_drain_rate,
   "drain_multiplier": _compute_drain_multiplier(),
   ```

6. Modify `configure(...)` to reset `_inventory_summary = {}` and `effective_drain_rate = p_drain_rate`.

- [ ] **Step 4: Run the model smoke green**

Run:
```bash
OUT=$(/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-synapse-sea-of-stars --script res://scripts/validation/inventory_state_smoke.gd 2>&1)
printf '%s\n' "$OUT"
printf '%s\n' "$OUT" | grep -q 'INVENTORY STATE PASS'
if printf '%s\n' "$OUT" | grep -E '^(ERROR|WARNING):' >/dev/null; then
  echo 'unexpected ERROR/WARNING in inventory_state_smoke'
  exit 1
fi
```

Expected (GREEN) result:
- Output contains `INVENTORY STATE PASS tools=1 pump=true drain_multiplier=0.5`.
- No unexpected `ERROR:` or `WARNING:` lines.

- [ ] **Step 5: Record Task 2 GREEN**

Run:
```bash
if git -C /Users/christopherwilloughby/the-synapse-sea-of-stars rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C /Users/christopherwilloughby/the-synapse-sea-of-stars add scripts/systems/inventory_state.gd data/tools/tool_definitions.json scripts/systems/oxygen_state.gd
  git -C /Users/christopherwilloughby/the-synapse-sea-of-stars commit -m 'feat(inventory): InventoryState model, tool definition, OxygenState drain multiplier (REQ-007)'
else
  printf '%s\n' 'NO_GIT Task 2 GREEN: scripts/systems/inventory_state.gd, data/tools/tool_definitions.json, scripts/systems/oxygen_state.gd added' >> /tmp/synapse_sea_inventory_tool_no_git_changes.log
fi
```

---

## Task 3: Implement Tool Pickup Scene Node

**Files:**
- Create: `scripts/tools/tool_pickup.gd`
- Create (optional): `scenes/tools/portable_oxygen_pump_pickup.tscn`
- Modify: `scripts/procgen/playable_generated_ship.gd`
- Read: `scripts/interaction/interactable.gd` (for `try_interact` / validation seam pattern)

**Interfaces:**
- `ToolPickup` must emit `tool_acquired(tool_id: String)`.
- `ToolPickup.try_interact(player_body: Node) -> bool` mirrors `Interactable` shape.
- `ToolPickup.set_validation_player_in_range(player_body: Node)` validation seam.

- [ ] **Step 1: Create `ToolPickup`**

Write `scripts/tools/tool_pickup.gd`:

```gdscript
extends Area3D
class_name ToolPickup

signal tool_acquired(tool_id: String)

var tool_id: String = ""
var inventory_state: InventoryState
var interaction_radius: float = 1.8
var acquired: bool = false
var candidate_player: Node
var collision_shape: CollisionShape3D
var marker: MeshInstance3D
var marker_visible: bool = true

func _ready() -> void:
	monitoring = true
	monitorable = true
	collision_layer = 1
	collision_mask = 1
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)

func configure(p_tool_id: String, p_inventory_state: InventoryState, world_position: Vector3, radius := 1.8) -> void:
	tool_id = p_tool_id
	inventory_state = p_inventory_state
	interaction_radius = radius
	acquired = false
	candidate_player = null
	position = world_position
	name = "ToolPickup_%s" % p_tool_id
	set_meta("tool_id", tool_id)
	set_meta("tool_pickup", true)
	_ensure_collision(radius)
	_ensure_marker(radius)

func set_validation_player_in_range(player_body: Node) -> void:
	candidate_player = player_body

func set_marker_visible(is_visible: bool) -> void:
	marker_visible = is_visible
	if marker != null:
		marker.visible = marker_visible and not acquired

func try_interact(player_body: Node) -> bool:
	if acquired:
		return false
	if player_body == null:
		return false
	if candidate_player != player_body and not _is_player_in_direct_range(player_body):
		return false
	if inventory_state == null:
		return false
	if not inventory_state.add_tool(tool_id):
		return false
	acquired = true
	set_marker_visible(false)
	if collision_shape != null:
		collision_shape.disabled = true
	emit_signal("tool_acquired", tool_id)
	return true

func _interaction_radius() -> float:
	if collision_shape != null and collision_shape.shape is SphereShape3D:
		var sphere_shape: SphereShape3D = collision_shape.shape as SphereShape3D
		return sphere_shape.radius
	return interaction_radius

func _is_player_in_direct_range(player_body: Node) -> bool:
	if not (player_body is Node3D):
		return false
	var player_node: Node3D = player_body as Node3D
	var pickup_position: Vector3 = global_position if is_inside_tree() else position
	var player_position: Vector3 = player_node.global_position if player_node.is_inside_tree() else player_node.position
	return pickup_position.distance_to(player_position) <= _interaction_radius()

func _ensure_collision(radius: float) -> void:
	if collision_shape == null:
		collision_shape = CollisionShape3D.new()
		collision_shape.name = "ToolPickupCollisionShape3D"
		add_child(collision_shape)
	var sphere_shape: SphereShape3D = SphereShape3D.new()
	sphere_shape.radius = radius
	collision_shape.shape = sphere_shape

func _ensure_marker(radius: float) -> void:
	if marker == null:
		marker = MeshInstance3D.new()
		marker.name = "ToolPickupMarker"
		add_child(marker)
	var box_mesh: BoxMesh = BoxMesh.new()
	box_mesh.size = Vector3(radius * 0.6, radius * 0.6, radius * 0.6)
	marker.mesh = box_mesh
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.25, 0.75, 0.95, 0.65)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	marker.material_override = material
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.visible = marker_visible and not acquired
	marker.set_meta("debug_tool_pickup_marker", true)

func _on_body_entered(body: Node3D) -> void:
	if body is PlayerController:
		candidate_player = body

func _on_body_exited(body: Node3D) -> void:
	if body == candidate_player:
		candidate_player = null
```

- [ ] **Step 2: Wire `ToolPickup` into `PlayableGeneratedShip`**

In `scripts/procgen/playable_generated_ship.gd`:

1. Add preload at the top:
   ```gdscript
   const InventoryStateScript := preload("res://scripts/systems/inventory_state.gd")
   const ToolPickupScript := preload("res://scripts/tools/tool_pickup.gd")
   ```

2. Add members after `oxygen_root`:
   ```gdscript
   var inventory_state: InventoryState
   var tool_pickup: ToolPickup
   var tool_pickup_root: Node3D
   const TOOL_PICKUP_INTERACTION_RADIUS: float = 1.8
   const TOOL_PICKUP_FALLBACK_OFFSET: Vector3 = Vector3(4.0, 0.0, 0.0)
   ```

3. In `_build_runtime_nodes()` after `oxygen_root` setup:
   ```gdscript
   inventory_state = InventoryStateScript.new()
   tool_pickup_root = Node3D.new()
   tool_pickup_root.name = "ToolPickupRoot"
   add_child(tool_pickup_root)
   ```

4. Add `_build_tool_pickup()`:
   ```gdscript
   func _build_tool_pickup() -> void:
       if tool_pickup_root == null:
           return
       for child in tool_pickup_root.get_children():
           tool_pickup_root.remove_child(child)
           child.queue_free()
       tool_pickup = null
       var world_position: Vector3 = _resolve_tool_pickup_world_position()
       tool_pickup = ToolPickupScript.new()
       tool_pickup.configure("portable_oxygen_pump", inventory_state, world_position, TOOL_PICKUP_INTERACTION_RADIUS)
       tool_pickup.tool_acquired.connect(_on_tool_pickup_acquired)
       tool_pickup_root.add_child(tool_pickup)
   ```

5. Add `_resolve_tool_pickup_world_position() -> Vector3`:
   ```gdscript
   func _resolve_tool_pickup_world_position() -> Vector3:
       if loader != null and loader.has_method("get_room_center"):
           var room_center: Vector3 = loader.get_room_center("tool_storage_01")
           if room_center != Vector3.INF:
               return room_center + Vector3(0.0, PLAYER_SPAWN_HEIGHT_ABOVE_NAV_FLOOR, 0.0)
       # Fallback: near player start.
       if player != null:
           return player.global_position + TOOL_PICKUP_FALLBACK_OFFSET
       if loader != null:
           return loader.get_start_transform().origin + TOOL_PICKUP_FALLBACK_OFFSET + Vector3(0.0, PLAYER_SPAWN_HEIGHT_ABOVE_NAV_FLOOR, 0.0)
       return TOOL_PICKUP_FALLBACK_OFFSET
   ```

6. Add `_on_tool_pickup_acquired(tool_id: String)`:
   ```gdscript
   func _on_tool_pickup_acquired(_tool_id: String) -> void:
       _refresh_tracker_system_status_lines()
       print("PLAYABLE TOOL ACQUIRED tool_id=%s" % _tool_id)
   ```

7. In `_on_ship_loaded(...)` after `_build_breach_zone()`:
   ```gdscript
   _build_tool_pickup()
   ```

8. Modify `_refresh_oxygen_state(...)` to apply the inventory summary before ticking:
   ```gdscript
   func _refresh_oxygen_state(force_initial: bool, delta_seconds: float) -> void:
       if oxygen_state == null:
           _refresh_tracker_system_status_lines()
           return
       if inventory_state != null:
           oxygen_state.apply_inventory_summary(inventory_state.get_summary())
       if force_initial:
           oxygen_state.apply_ship_systems_summary({})
           _apply_breach_zone_scene_state()
           _refresh_tracker_system_status_lines()
           return
       var player_in_zone: bool = is_player_in_breach_zone()
       oxygen_state.tick(delta_seconds, player_in_zone)
       _apply_breach_zone_scene_state()
       _refresh_tracker_system_status_lines()
   ```

9. Modify `_on_player_interact_requested(...)` to also try tool pickup interaction:
   ```gdscript
   func _on_player_interact_requested(player_body: PlayerController) -> void:
       if tool_pickup != null and tool_pickup.try_interact(player_body):
           return
       for interactable_variant in interactables:
           var interactable = interactable_variant
           if interactable.try_interact(player_body):
               return
   ```

10. Extend `_combined_system_status_lines()` to append inventory status lines:
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
        if inventory_state != null:
            for line in inventory_state.get_status_lines():
                lines.append(String(line))
        return lines
    ```

11. Add public helpers:
    ```gdscript
    func get_inventory_summary() -> Dictionary:
        if inventory_state == null:
            return { "tool_ids": [], "active_effects": [] }
        return inventory_state.get_summary()

    func get_tool_pickup_node() -> Node:
        return tool_pickup

    func teleport_player_to_tool_pickup_for_validation() -> bool:
        if player == null or tool_pickup == null:
            return false
        player.teleport_to(tool_pickup.global_position)
        return true

    func acquire_tool_for_validation(tool_id: String) -> bool:
        if tool_pickup == null or inventory_state == null:
            return false
        if tool_pickup.tool_id != tool_id:
            return false
        if not teleport_player_to_tool_pickup_for_validation():
            return false
        tool_pickup.set_validation_player_in_range(player)
        player.request_interact()
        return inventory_state.has_tool(tool_id)
    ```

- [ ] **Step 3: Run the model smoke again**

Run:
```bash
OUT=$(/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-synapse-sea-of-stars --script res://scripts/validation/inventory_state_smoke.gd 2>&1)
printf '%s\n' "$OUT"
printf '%s\n' "$OUT" | grep -q 'INVENTORY STATE PASS'
```

Expected: still green.

- [ ] **Step 4: Record Task 3 progress**

Run:
```bash
if git -C /Users/christopherwilloughby/the-synapse-sea-of-stars rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C /Users/christopherwilloughby/the-synapse-sea-of-stars add scripts/tools/tool_pickup.gd scripts/procgen/playable_generated_ship.gd
  git -C /Users/christopherwilloughby/the-synapse-sea-of-stars commit -m 'feat(inventory): ToolPickup node and PlayableGeneratedShip integration (REQ-007)'
else
  printf '%s\n' 'NO_GIT Task 3: scripts/tools/tool_pickup.gd, scripts/procgen/playable_generated_ship.gd modified' >> /tmp/synapse_sea_inventory_tool_no_git_changes.log
fi
```

---

## Task 4: Main-Scene Inventory Smoke, RED Phase

**Files:**
- Create: `scripts/validation/main_playable_slice_inventory_smoke.gd`
- Read: `scripts/validation/main_playable_slice_hazard_smoke.gd` (template)

**Interfaces:**
- Consumes intended future `PlayableGeneratedShip` helpers:
  - `get_inventory_summary() -> Dictionary`
  - `get_tool_pickup_node() -> Node`
  - `teleport_player_to_tool_pickup_for_validation() -> bool`
  - `acquire_tool_for_validation(tool_id: String) -> bool`
  - `teleport_player_to_breach_zone_for_validation() -> bool`
  - `is_player_in_breach_zone_for_validation() -> bool`
  - `get_oxygen_summary() -> Dictionary`
  - `get_combined_system_status_lines() -> PackedStringArray`
  - `get_route_control_summary() -> Dictionary`

- [ ] **Step 1: Create the failing main-scene smoke**

Write `scripts/validation/main_playable_slice_inventory_smoke.gd`:

```gdscript
extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const READY_TIMEOUT_FRAMES: int = 300
const DRAIN_WAIT_FRAMES: int = 120

var main_node: Node
var playable: PlayableGeneratedShip
var frame_count: int = 0
var phase: String = "waiting_ready"
var phase_frames: int = 0
var finished: bool = false

var oxygen_before_drain: float = 0.0
var oxygen_after_drain: float = 0.0

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
		"acquire_tool":
			_acquire_tool()
		"teleport_to_breach":
			_teleport_to_breach()
		"draining":
			_wait_for_drain()
		"check_drain":
			_check_drain_consequence()
		"verify_route_unchanged":
			_verify_route_unchanged()

func _validate_initial_state() -> void:
	if not playable.has_method("get_inventory_summary"):
		_fail("get_inventory_summary missing")
		return
	if not playable.has_method("acquire_tool_for_validation"):
		_fail("acquire_tool_for_validation missing")
		return
	var initial_inventory: Dictionary = playable.get_inventory_summary()
	if (initial_inventory.get("tool_ids") as Array).size() != 0:
		_fail("initial inventory should be empty")
		return
	var pickup: Node = playable.get_tool_pickup_node()
	if pickup == null:
		_fail("tool pickup node missing")
		return
	var marker: Variant = pickup.get("marker")
	if marker == null or not (marker is Node3D) or not (marker as Node3D).visible:
		_fail("tool pickup marker should be visible before acquisition")
		return
	phase = "acquire_tool"

func _acquire_tool() -> void:
	if not playable.acquire_tool_for_validation("portable_oxygen_pump"):
		_fail("acquire_tool_for_validation failed")
		return
	var inventory: Dictionary = playable.get_inventory_summary()
	var tool_ids: Array = inventory.get("tool_ids", []) as Array
	if tool_ids.size() != 1 or str(tool_ids[0]) != "portable_oxygen_pump":
		_fail("inventory should contain portable_oxygen_pump after acquisition")
		return
	var pickup: Node = playable.get_tool_pickup_node()
	var marker: Variant = pickup.get("marker")
	if marker != null and (marker is Node3D) and (marker as Node3D).visible:
		_fail("tool pickup marker should be hidden after acquisition")
		return
	var lines: PackedStringArray = playable.get_combined_system_status_lines()
	var found_tool_line: bool = false
	for line in lines:
		if String(line) == "Tool: Portable Oxygen Pump":
			found_tool_line = true
			break
	if not found_tool_line:
		_fail("HUD missing 'Tool: Portable Oxygen Pump' line")
		return
	phase = "teleport_to_breach"

func _teleport_to_breach() -> void:
	oxygen_before_drain = float(playable.get_oxygen_summary().get("oxygen", -1.0))
	if not playable.teleport_player_to_breach_zone_for_validation():
		_fail("could not teleport player into breach zone")
		return
	if not playable.is_player_in_breach_zone_for_validation():
		_fail("runtime proximity check did not see player inside breach zone")
		return
	phase = "draining"
	phase_frames = 0

func _wait_for_drain() -> void:
	phase_frames += 1
	if phase_frames >= DRAIN_WAIT_FRAMES:
		phase = "check_drain"

func _check_drain_consequence() -> void:
	oxygen_after_drain = float(playable.get_oxygen_summary().get("oxygen", -1.0))
	if oxygen_after_drain >= oxygen_before_drain:
		_fail("oxygen did not drain after teleport into breach")
		return
	var oxygen_summary: Dictionary = playable.get_oxygen_summary()
	var drain_multiplier: float = float(oxygen_summary.get("drain_multiplier", -1.0))
	if absf(drain_multiplier - 0.5) > 0.001:
		_fail("drain_multiplier should be 0.5 with pump, got %s" % str(drain_multiplier))
		return
	var effective_drain_rate: float = float(oxygen_summary.get("effective_drain_rate", -1.0))
	if absf(effective_drain_rate - 3.0) > 0.001:
		_fail("effective_drain_rate should be 3.0 with pump, got %s" % str(effective_drain_rate))
		return
	# Verify the tool does not alter route/extraction state.
	var route_summary: Dictionary = playable.get_route_control_summary()
	if bool(route_summary.get("extraction_unlocked", true)):
		_fail("tool must not unlock extraction")
		return
	phase = "verify_route_unchanged"

func _verify_route_unchanged() -> void:
	var route_summary: Dictionary = playable.get_route_control_summary()
	if bool(route_summary.get("extraction_unlocked", true)):
		_fail("tool must not unlock extraction")
		return
	finished = true
	var inventory: Dictionary = playable.get_inventory_summary()
	var tool_ids: Array = inventory.get("tool_ids", []) as Array
	print("MAIN PLAYABLE INVENTORY PASS tool=portable_oxygen_pump acquired=%s drain_multiplier=%s" % [
		str(tool_ids.size() == 1 and str(tool_ids[0]) == "portable_oxygen_pump").to_lower(),
		str(float(playable.get_oxygen_summary().get("drain_multiplier", -1.0))),
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
	push_error("MAIN PLAYABLE INVENTORY FAIL reason=%s" % reason)
	_cleanup_and_quit(1)

func _cleanup_and_quit(code: int) -> void:
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	quit(code)
```

- [ ] **Step 2: Run the main-scene smoke red**

Run:
```bash
OUT=$(/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-synapse-sea-of-stars --script res://scripts/validation/main_playable_slice_inventory_smoke.gd 2>&1)
printf '%s\n' "$OUT"
printf '%s\n' "$OUT" | grep -q 'MAIN PLAYABLE INVENTORY PASS' || true
```

Expected (RED) result:
- Output contains `MAIN PLAYABLE INVENTORY FAIL reason=...`.
- The pass marker does NOT appear.

- [ ] **Step 3: Record Task 4 RED**

Run:
```bash
if git -C /Users/christopherwilloughby/the-synapse-sea-of-stars rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C /Users/christopherwilloughby/the-synapse-sea-of-stars add scripts/validation/main_playable_slice_inventory_smoke.gd
  git -C /Users/christopherwilloughby/the-synapse-sea-of-stars commit -m 'test(inventory): RED main-scene inventory smoke (REQ-007)'
else
  printf '%s\n' 'NO_GIT Task 4 RED: scripts/validation/main_playable_slice_inventory_smoke.gd added and failed for missing scene integration' >> /tmp/synapse_sea_inventory_tool_no_git_changes.log
fi
```

---

## Task 5: Main-Scene Inventory Smoke, GREEN Phase

**Files:**
- Modify: `scripts/procgen/playable_generated_ship.gd` (ensure all helpers exist and work correctly)
- Read: `scripts/validation/main_playable_slice_inventory_smoke.gd` (assertions above)

- [ ] **Step 1: Verify all helpers are implemented**

Confirm `PlayableGeneratedShip` exposes:
- `get_inventory_summary() -> Dictionary`
- `get_tool_pickup_node() -> Node`
- `teleport_player_to_tool_pickup_for_validation() -> bool`
- `acquire_tool_for_validation(tool_id: String) -> bool`
- `teleport_player_to_breach_zone_for_validation() -> bool`
- `is_player_in_breach_zone_for_validation() -> bool`
- `get_oxygen_summary() -> Dictionary`
- `get_combined_system_status_lines() -> PackedStringArray`
- `get_route_control_summary() -> Dictionary`

- [ ] **Step 2: Run the main-scene smoke green**

Run:
```bash
OUT=$(/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-synapse-sea-of-stars --script res://scripts/validation/main_playable_slice_inventory_smoke.gd 2>&1)
printf '%s\n' "$OUT"
printf '%s\n' "$OUT" | grep -q 'MAIN PLAYABLE INVENTORY PASS'
if printf '%s\n' "$OUT" | grep -E '^(ERROR|WARNING):' >/dev/null; then
  echo 'unexpected ERROR/WARNING in main_playable_slice_inventory_smoke'
  exit 1
fi
```

Expected (GREEN) result:
- Output contains `MAIN PLAYABLE INVENTORY PASS tool=portable_oxygen_pump acquired=true drain_multiplier=0.5`.
- No unexpected `ERROR:` or `WARNING:` lines.

- [ ] **Step 3: Record Task 5 GREEN**

Run:
```bash
if git -C /Users/christopherwilloughby/the-synapse-sea-of-stars rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C /Users/christopherwilloughby/the-synapse-sea-of-stars add scripts/procgen/playable_generated_ship.gd
  git -C /Users/christopherwilloughby/the-synapse-sea-of-stars commit -m 'feat(inventory): green main-scene inventory smoke (REQ-007)'
else
  printf '%s\n' 'NO_GIT Task 5 GREEN: PlayableGeneratedShip helpers verified' >> /tmp/synapse_sea_inventory_tool_no_git_changes.log
fi
```

---

## Task 6: Update Validation Plan Regression Bundle

**Files:**
- Modify: `docs/game/06_validation_plan.md`

- [ ] **Step 1: Add inventory smokes to the regression bundle**

Insert two `run_clean` calls into the bundle in `docs/game/06_validation_plan.md` before the final `echo 'SYNAPSE_SEA REGRESSION PASS ...'` line:

```bash
run_clean 'inventory model smoke' 'INVENTORY STATE PASS tools=1 pump=true drain_multiplier=0.5' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/inventory_state_smoke.gd
run_clean 'main inventory smoke' 'MAIN PLAYABLE INVENTORY PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_inventory_smoke.gd
```

Update the final echo line to report `commands=10` (was `commands=8`).

- [ ] **Step 2: Update the "Future validation additions" section**

Change the REQ-007 bullet from:
```markdown
- Inventory/tool model smoke: `scripts/validation/inventory_state_smoke.gd` and main-scene smoke `scripts/validation/main_playable_slice_inventory_smoke.gd` (REQ-007).
```
to:
```markdown
- [x] Inventory/tool model smoke: `scripts/validation/inventory_state_smoke.gd` and main-scene smoke `scripts/validation/main_playable_slice_inventory_smoke.gd` (REQ-007).
```

- [ ] **Step 3: Record Task 6**

Run:
```bash
if git -C /Users/christopherwilloughby/the-synapse-sea-of-stars rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C /Users/christopherwilloughby/the-synapse-sea-of-stars add docs/game/06_validation_plan.md
  git -C /Users/christopherwilloughby/the-synapse-sea-of-stars commit -m 'docs(validation): add REQ-007 inventory smokes to regression bundle'
else
  printf '%s\n' 'NO_GIT Task 6: docs/game/06_validation_plan.md updated with REQ-007 smokes' >> /tmp/synapse_sea_inventory_tool_no_git_changes.log
fi
```

---

## Task 7: Regression Bundle Run

**Files:**
- Read: `docs/game/06_validation_plan.md`

- [ ] **Step 1: Run the updated regression bundle**

Run the bundle script from `docs/game/06_validation_plan.md` (lines 29-66, after the Task 6 edits):

```bash
ROOT=/Users/christopherwilloughby/the-synapse-sea-of-stars
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
run_clean 'inventory model smoke' 'INVENTORY STATE PASS tools=1 pump=true drain_multiplier=0.5' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/inventory_state_smoke.gd
run_clean 'main inventory smoke' 'MAIN PLAYABLE INVENTORY PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_inventory_smoke.gd
run_clean 'ship systems smoke' 'MAIN PLAYABLE SHIP SYSTEMS PASS supplies=true power=true logs=true reactor=true extraction=true blocked_visible=0 completed_systems=4' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_ship_systems_smoke.gd
run_clean 'completion smoke' 'MAIN PLAYABLE SLICE COMPLETE PASS completed=4 current_sequence=5 run_complete=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_completion_smoke.gd
run_clean 'input smoke' 'MAIN PLAYABLE INPUT LOOP PASS moved=true camera_followed=true interaction_input_path=true current_sequence=2' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_input_smoke.gd
run_clean 'readability smoke' 'MAIN PLAYABLE SLICE READABILITY PASS objective_props=4 blocked=1 ramp=1' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_readability_smoke.gd
echo 'SYNAPSE_SEA REGRESSION PASS commands=10 clean_output=true'
```

Expected:
- All 10 smokes pass with their markers.
- Final line: `SYNAPSE_SEA REGRESSION PASS commands=10 clean_output=true`.
- No unexpected `ERROR:` or `WARNING:` lines.

- [ ] **Step 2: If any existing smoke regresses**

If an existing smoke (route control, oxygen, hazard, ship systems, completion, input, readability) fails or emits a new `ERROR:`/`WARNING:`:
1. Stop the bundle.
2. Inspect the failure output.
3. Fix the regression in the inventory/tool code; do not alter the existing feature semantics.
4. Re-run the failing smoke plus the full bundle.
5. If the regression is caused by an intentional design conflict, block and escalate to `synapse_seareview` for ADR-level decision before proceeding.

- [ ] **Step 3: Record Task 7**

Run:
```bash
if git -C /Users/christopherwilloughby/the-synapse-sea-of-stars rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C /Users/christopherwilloughby/the-synapse-sea-of-stars commit -m 'test(regression): REQ-007 bundle passes with 10 smokes' --allow-empty
else
  printf '%s\n' 'NO_GIT Task 7: regression bundle passed with 10 smokes' >> /tmp/synapse_sea_inventory_tool_no_git_changes.log
fi
```

---

## Verification Commands

Direct model smoke:
```bash
/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-synapse-sea-of-stars --script res://scripts/validation/inventory_state_smoke.gd
```
Expected marker: `INVENTORY STATE PASS tools=1 pump=true drain_multiplier=0.5`

Main-scene smoke:
```bash
/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-synapse-sea-of-stars --script res://scripts/validation/main_playable_slice_inventory_smoke.gd
```
Expected marker: `MAIN PLAYABLE INVENTORY PASS tool=portable_oxygen_pump acquired=true drain_multiplier=0.5`

Regression bundle:
```bash
# Run the script from docs/game/06_validation_plan.md after Task 6 edits.
```
Expected marker: `SYNAPSE_SEA REGRESSION PASS commands=10 clean_output=true`

---

## Allowed Files

- `scripts/systems/inventory_state.gd`
- `scripts/systems/oxygen_state.gd`
- `scripts/tools/tool_pickup.gd`
- `scripts/tools/tool_database.gd` (optional)
- `data/tools/tool_definitions.json`
- `scenes/tools/portable_oxygen_pump_pickup.tscn` (optional)
- `scripts/procgen/playable_generated_ship.gd`
- `scripts/validation/inventory_state_smoke.gd`
- `scripts/validation/main_playable_slice_inventory_smoke.gd`
- `docs/game/06_validation_plan.md`
- Generated `.uid` sidecars for the new `.gd` files.

## Non-Goals (do not implement)

- No equipment UI, inventory grid, or drag-and-drop.
- No tool durability, charges, or crafting.
- No dropping, trading, or hub-stored tools across runs.
- No tools that alter route gates, extraction, objective sequence, or fire hazards in Gate 2.
- No audio, particle, or animation polish for the pickup.
- No generalization beyond the single `portable_oxygen_pump` tool without ADR-0004.
- No save/load serialization in this card (REQ-012 will consume `InventoryState.tool_ids` later).

## Risks

| Risk | Mitigation |
|---|---|
| Pickup placement is not readable and players miss it. | Place it on the critical-path side room with a visible `MeshInstance3D` marker; main-scene smoke asserts marker visibility before acquisition. |
| Oxygen pump makes the breach trivial. | Keep multiplier at 0.5 (still drains, still blocks at zero); smoke prints effective drain rate so tuning is visible. |
| Inventory model and oxygen model form a tight coupling. | `OxygenState` only reads a summary Dictionary; it does not own `InventoryState`. |
| Tool data model decisions become ad-hoc. | Ship with a single JSON definition and one conditional branch; defer ADR-0004 until a second tool is added. |
| Existing hazard smoke regresses because `OxygenState` summary shape changes. | The new `effective_drain_rate` and `drain_multiplier` keys are additive; existing keys and behavior remain unchanged when inventory is empty. |

## Stop / Block Conditions

Block the implementation and escalate to `synapse_seareview` if:
- The plan would add hub/meta state, broaden into a generic equipment system, alter route/extraction semantics, or require an unapproved architecture decision beyond the one-tool scope.
- Implementing the tool pickup requires changes to `GeneratedShipLoader` that affect layout/gameplay_slice parsing for other features.
- The `OxygenState` multiplier change causes any existing Gate 1 smoke to fail and the failure cannot be fixed without changing existing feature semantics.
- The implementation worker wants to generalize the tool/effect system beyond one hard-coded multiplier before ADR-0004 is accepted.

## Handoff to Implementer

The implementer card is `t_03fe5d4b` (Implement inventory/tool loop, REQ-007). This plan document is the handoff artifact. Before starting implementation, confirm:
1. This plan file is present at `docs/superpowers/plans/2026-06-19-inventory-tool-loop.md`.
2. The acceptance criteria in `t_03fe5d4b` still match this plan.
3. No ADR-0004 work has been started; if it has, re-read the current ADR and adjust the data-model steps accordingly.
