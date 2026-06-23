# Ship Cargo Holds (System 6 slice 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every cargo-room-bearing ship a persistent cargo hold the player physically loads/unloads (deposit-all / withdraw-by-category) by walking up to it.

**Architecture:** A pure-model `ShipInventory` (`RefCounted`) lives lazily on `ShipInstance` (mirroring `get_hangar()`); shared item-definition lookups are extracted to a static `ItemDefs`; pure-static `CargoTransfer` moves items between the player `InventoryState` and a ship hold with a conservation invariant; a walk-up `CargoHoldControl` (`Area3D`, mirrors `HangarBayControl`) emits deposit/withdraw intents the coordinator services. Persistence is additive (no save-version bump): derelict holds ride `ShipInstance.get_summary()`, the home hold rides a new `WorldSnapshot.home_ship_inventory` field.

**Tech Stack:** Godot 4.6.2, typed GDScript, headless `--script` validation smokes.

## Global Constraints

- **Godot binary:** `C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe`. **Project root:** `C:/Users/dasbl/Documents/The Synaptic Sea`. Run smokes headless: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/<name>.gd 2>&1`.
- **Markers route to stderr** under headless Godot — always capture with `2>&1`. **Trust the PASS marker, never the exit code** (`--script` can exit 0 on parse errors). Confirm the marker line is present AND no unexpected `ERROR:`/`WARNING:` appears.
- **Allowlisted baseline noise (ignore):** `ERROR: Capture not registered: 'gdaimcp'.` and `WARNING: ObjectDB instances leaked at exit`. **`resources still in use at exit` is a real leak (hard fail).**
- **Local `project.godot` drift:** single-smoke runs emit environmental `Unrecognized UID` / `Resource file not found: res://` / `Failed to instantiate an autoload 'MCPRuntime'` errors — these are local drift, NOT failures. For the **full regression bundle and Gate-1**, `git stash push -- project.godot` first, pop after. Do NOT revert or commit the drift.
- **Never stage/commit** `project.godot`, `.godot/`, `*.uid`, or `addons/`. Use selective `git add <explicit paths>` only.
- **Conventional Commits**, every commit message ends with the trailer:
  `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`
- **Typed GDScript** for new systems. **Headless class-cache portability:** new `RefCounted`/`Resource` classes that get reconstructed from data use a `static func create(...)` / `load()` self-reference factory, never `ClassName.new()` from another class under `--script` (mirrors `ShipInstance.create` / `WorldSnapshot.from_dict`). A `RefCounted` nil check is `== null` (not `is_instance_valid`).
- **No ship↔ship transfer.** Deposit-all moves only `part` + `supply`; **tools are never auto-deposited.**
- **No save-version bump** (`WORLD_SLICE_VERSION` stays `"world-4"`): the hold is additive/tolerant.
- **Validation is the definition of done.** Final state: `SARGASSO REGRESSION PASS commands=104 clean_output=true` and Gate-1 `GO 2.00`.

---

## File Structure

New files:
- `scripts/systems/item_defs.gd` — shared static item-definition lookups (DRY extract).
- `scripts/systems/ship_inventory.gd` — per-ship cargo hold (pure model).
- `scripts/systems/cargo_transfer.gd` — pure-static deposit/withdraw logic.
- `scripts/tools/cargo_hold_control.gd` — walk-up `Area3D` sensor.
- `scripts/validation/ship_inventory_smoke.gd` — `ShipInventory` model smoke.
- `scripts/validation/cargo_transfer_smoke.gd` — transfer + conservation smoke.
- `scripts/validation/cargo_hold_smoke.gd` — main-scene control gate + deposit/withdraw + persist smoke.
- `docs/game/adr/0020-ship-cargo-holds.md` — ADR.

Modified files:
- `scripts/systems/inventory_state.gd` — internal `ItemDefs` use (public API unchanged).
- `scripts/systems/ship_instance.gd` — lazy `inventory` + persistence.
- `scripts/systems/world_snapshot.gd` — `home_ship_inventory` field.
- `scripts/procgen/playable_generated_ship.gd` — spawn / handlers / teardown / seams.
- `scripts/validation/ship_instance_smoke.gd` — inventory round-trip assertion.
- `scripts/validation/world_snapshot_smoke.gd` — `home_ship_inventory` round-trip assertion.
- `docs/game/06_validation_plan.md` — register 3 smokes (101 → 104).
- `docs/game/09_system_roadmap.md` — System 6 status.

---

## Task 1: `ItemDefs` extract + `InventoryState` refactor

**Files:**
- Create: `scripts/systems/item_defs.gd`
- Modify: `scripts/systems/inventory_state.gd`
- Regression test: `scripts/validation/inventory_state_smoke.gd`, `scripts/validation/item_inventory_smoke.gd` (existing — must pass unchanged)

**Interfaces:**
- Produces: `ItemDefs.load_definitions() -> Dictionary`, `ItemDefs.weight_each(defs: Dictionary, item_id: String) -> float`, `ItemDefs.max_stack(defs: Dictionary, item_id: String) -> int`, `ItemDefs.category(defs: Dictionary, item_id: String) -> String`, `ItemDefs.display_name(defs: Dictionary, item_id: String) -> String`, `ItemDefs.get_definition(defs: Dictionary, item_id: String) -> Dictionary`. Constants `ItemDefs.DEFAULT_TOOL_WEIGHT := 2.0`, `ItemDefs.DEFAULT_MAX_STACK := 99`.

- [ ] **Step 1: Create the `ItemDefs` static.** This is a pure extract of `InventoryState`'s definition-loading + per-item lookups, verbatim in behavior.

Create `scripts/systems/item_defs.gd`:

```gdscript
extends RefCounted
class_name ItemDefs

## Shared, all-static item-definition lookups. Extracted from InventoryState so
## both the player inventory and the per-ship ShipInventory read one source of
## truth for weights, stack limits, categories, and display names. Tool defs are
## merged first with a synthetic 'tool' category + default weight (preserving the
## original InventoryState merge order and semantics).

const ITEM_DEFINITIONS_PATH: String = "res://data/items/item_definitions.json"
const TOOL_DEFINITIONS_PATH: String = "res://data/tools/tool_definitions.json"
const DEFAULT_TOOL_WEIGHT: float = 2.0
const DEFAULT_MAX_STACK: int = 99

## Merged tool+item definitions. Tools first (so item_definitions can override),
## tool defs get a synthetic 'tool' category + default weight while preserving
## their 'effect' field.
static func load_definitions() -> Dictionary:
	var defs: Dictionary = {}
	var tool_defs: Dictionary = _read_json_dict(TOOL_DEFINITIONS_PATH)
	for tool_id in tool_defs:
		var def: Dictionary = (tool_defs[tool_id] as Dictionary).duplicate(true)
		def["category"] = "tool"
		if not def.has("weight"):
			def["weight"] = DEFAULT_TOOL_WEIGHT
		defs[tool_id] = def
	var item_defs: Dictionary = _read_json_dict(ITEM_DEFINITIONS_PATH)
	for item_id in item_defs:
		defs[item_id] = item_defs[item_id]
	return defs

static func _read_json_dict(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}

static func get_definition(defs: Dictionary, item_id: String) -> Dictionary:
	var def: Variant = defs.get(item_id, {})
	return def if def is Dictionary else {}

static func category(defs: Dictionary, item_id: String) -> String:
	return str(get_definition(defs, item_id).get("category", ""))

static func weight_each(defs: Dictionary, item_id: String) -> float:
	# Unknown items weigh 0 so a foreign save round-trips without corrupting the cap.
	return float(get_definition(defs, item_id).get("weight", 0.0))

static func max_stack(defs: Dictionary, item_id: String) -> int:
	return int(get_definition(defs, item_id).get("max_stack", DEFAULT_MAX_STACK))

static func display_name(defs: Dictionary, item_id: String) -> String:
	var name: String = str(get_definition(defs, item_id).get("display_name", ""))
	return name if not name.is_empty() else item_id.replace("_", " ").capitalize()
```

- [ ] **Step 2: Refactor `InventoryState` to delegate to `ItemDefs`.** Public API, constants, tool shims, save shape, and `get_status_lines()` markers MUST stay identical. Replace only the internals.

In `scripts/systems/inventory_state.gd`:

Add the preload near the top (after `class_name InventoryState`, before the consts):
```gdscript
const ItemDefsScript := preload("res://scripts/systems/item_defs.gd")
```

Replace `_load_definitions()` (lines ~21-34) and `_read_json_dict()` (lines ~36-45) with a single delegating loader (delete `_read_json_dict` entirely):
```gdscript
func _load_definitions() -> void:
	_definitions = ItemDefsScript.load_definitions()
```

Replace the bodies of the definition helpers to delegate (keep the same signatures so all callers are untouched):
```gdscript
func get_definition(item_id: String) -> Dictionary:
	return ItemDefsScript.get_definition(_definitions, item_id)

func get_category(item_id: String) -> String:
	return ItemDefsScript.category(_definitions, item_id)

func get_weight_each(item_id: String) -> float:
	return ItemDefsScript.weight_each(_definitions, item_id)

func _max_stack(item_id: String) -> int:
	return ItemDefsScript.max_stack(_definitions, item_id)

func get_display_name(item_id: String) -> String:
	return ItemDefsScript.display_name(_definitions, item_id)
```

Leave `DEFAULT_TOOL_WEIGHT` / `DEFAULT_MAX_STACK` / `ITEM_DEFINITIONS_PATH` / `TOOL_DEFINITIONS_PATH` consts in `InventoryState` as-is (other code/tests may reference them; removing them is out of scope). They are now duplicated with `ItemDefs` but harmless; do not delete.

- [ ] **Step 3: Run the existing inventory regression smokes — they must still pass (this is the extract's regression guard).**

Run:
```bash
GODOT="C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe"
ROOT="C:/Users/dasbl/Documents/The Synaptic Sea"
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/inventory_state_smoke.gd 2>&1
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/item_inventory_smoke.gd 2>&1
```
Expected: both print their existing PASS markers (e.g. `INVENTORY STATE SMOKE PASS ...` / `ITEM INVENTORY SMOKE PASS ...`). No new `ERROR:`/`WARNING:` beyond the allowlisted baseline + local drift lines. If a marker is absent, the extract changed behavior — fix `ItemDefs` to match the original merge/lookup exactly.

- [ ] **Step 4: Commit.**

```bash
git add scripts/systems/item_defs.gd scripts/systems/inventory_state.gd
git commit -m "refactor(inventory): extract shared ItemDefs lookups from InventoryState

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: `ShipInventory` model + smoke

**Files:**
- Create: `scripts/systems/ship_inventory.gd`
- Create: `scripts/validation/ship_inventory_smoke.gd`

**Interfaces:**
- Consumes: `ItemDefs` (Task 1).
- Produces: `ShipInventory.create(p_max_weight := 500.0) -> ShipInventory`; instance API `add_item(item_id: String, qty: int) -> int`, `remove_item(item_id: String, qty: int) -> int`, `get_quantity(item_id: String) -> int`, `get_total_weight() -> float`, `get_max_weight() -> float`, `get_items_by_category(category: String) -> Array`, `reset() -> void`, `get_summary() -> Dictionary`, `apply_summary(summary) -> bool`; field `var items: Dictionary`; const `MAX_WEIGHT_DEFAULT := 500.0`.

- [ ] **Step 1: Write the failing smoke.**

Create `scripts/validation/ship_inventory_smoke.gd`:
```gdscript
extends SceneTree

## ShipInventory pure-model smoke: add/remove, weight-cap + stack-limit gating,
## get_summary/apply_summary round-trip. ShipInventory is a plain per-ship cargo
## container (no player tool shims), weight-capped (default 500), sharing ItemDefs
## weights with the player InventoryState.

const ShipInventoryScript := preload("res://scripts/systems/ship_inventory.gd")

func _init() -> void:
	var hold = ShipInventoryScript.create(500.0)
	assert(hold.get_max_weight() == 500.0, "configured cap")
	assert(hold.get_total_weight() == 0.0, "starts empty")

	# add_item returns qty actually added; honors stack room.
	var added: int = hold.add_item("scrap_metal", 5)
	assert(added == 5, "added 5 scrap_metal (got %d)" % added)
	assert(hold.get_quantity("scrap_metal") == 5, "quantity tracks")

	# remove_item returns qty actually removed.
	var removed: int = hold.remove_item("scrap_metal", 2)
	assert(removed == 2, "removed 2 (got %d)" % removed)
	assert(hold.get_quantity("scrap_metal") == 3, "quantity after remove")

	# Weight cap gating: a 12.0-cap hold fits exactly 2 scrap_metal (weight 5.0 each).
	var tiny = ShipInventoryScript.create(12.0)
	var fit: int = tiny.add_item("scrap_metal", 999)
	assert(fit == 2, "weight cap limited the add to 2 (fit=%d)" % fit)
	assert(tiny.get_total_weight() <= 12.0 + 0.0001, "never exceeds cap")

	# Round-trip.
	var summary: Dictionary = hold.get_summary()
	assert(summary.has("items") and summary.has("max_weight"), "summary shape")
	var restored = ShipInventoryScript.create(1.0)
	assert(restored.apply_summary(summary) == true, "apply_summary accepts")
	assert(restored.get_quantity("scrap_metal") == 3, "items round-tripped")
	assert(restored.get_max_weight() == 500.0, "max_weight round-tripped")

	# Tolerant: empty summary rejected.
	assert(ShipInventoryScript.create().apply_summary({}) == false, "empty summary rejected")

	print("SHIP INVENTORY SMOKE PASS items=%d weight=%s" % [restored.get_quantity("scrap_metal"), str(restored.get_total_weight())])
	quit()
```

Note: `scrap_metal` is a **real** id in `data/items/item_definitions.json` (`category: part`, `weight: 5.0`, `max_stack: 20`) — no substitution needed.

- [ ] **Step 2: Run the smoke to verify it fails.**

Run:
```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ship_inventory_smoke.gd 2>&1
```
Expected: FAIL — `ship_inventory.gd` does not exist yet (parse/load error, no `SHIP INVENTORY SMOKE PASS` marker).

- [ ] **Step 3: Implement `ShipInventory`.**

Create `scripts/systems/ship_inventory.gd`:
```gdscript
extends RefCounted
class_name ShipInventory

## Per-ship cargo hold. A focused, weight-capped item container — no player-tool
## shims. Shares item weights/stack-limits with the player InventoryState via
## ItemDefs. Pure model; never touches the scene tree. Round-trips via
## get_summary/apply_summary. Constructed through the load()-self-reference factory
## so it resolves under --headless --script (class_name globals are unreliable
## there; mirrors ShipInstance.create).

const ItemDefsScript := preload("res://scripts/systems/item_defs.gd")

const MAX_WEIGHT_DEFAULT: float = 500.0

var items: Dictionary = {}          # item_id: String -> quantity: int
var max_weight: float = MAX_WEIGHT_DEFAULT
var _defs: Dictionary = {}

func _init() -> void:
	_defs = ItemDefsScript.load_definitions()

static func create(p_max_weight: float = MAX_WEIGHT_DEFAULT) -> ShipInventory:
	var script: GDScript = load("res://scripts/systems/ship_inventory.gd")
	var inst = script.new()
	inst.max_weight = p_max_weight
	return inst

func get_max_weight() -> float:
	return max_weight

func get_total_weight() -> float:
	var total: float = 0.0
	for item_id in items:
		total += ItemDefsScript.weight_each(_defs, item_id) * float(items[item_id])
	return total

func get_quantity(item_id: String) -> int:
	return int(items.get(item_id, 0))

## Adds up to qty, honoring max_stack and the weight cap. Returns the quantity
## actually added (0 if none fit). Weight-0 items ignore the cap. Mirrors
## InventoryState.add_item semantics exactly.
func add_item(item_id: String, qty: int) -> int:
	if item_id.is_empty() or qty <= 0:
		return 0
	var current: int = get_quantity(item_id)
	var stack_room: int = max(0, ItemDefsScript.max_stack(_defs, item_id) - current)
	var want: int = min(qty, stack_room)
	if want <= 0:
		return 0
	var w: float = ItemDefsScript.weight_each(_defs, item_id)
	if w > 0.0:
		var remaining: float = max_weight - get_total_weight()
		var weight_room: int = int(floor(remaining / w + 0.0001))
		want = min(want, max(0, weight_room))
	if want <= 0:
		return 0
	items[item_id] = current + want
	return want

func remove_item(item_id: String, qty: int) -> int:
	if qty <= 0:
		return 0
	var current: int = get_quantity(item_id)
	var removed: int = min(qty, current)
	if removed <= 0:
		return 0
	if removed >= current:
		items.erase(item_id)
	else:
		items[item_id] = current - removed
	return removed

func get_items_by_category(category: String) -> Array:
	var out: Array = []
	var ids: Array = items.keys()
	ids.sort()
	for item_id in ids:
		if ItemDefsScript.category(_defs, item_id) == category:
			out.append({
				"id": item_id,
				"quantity": get_quantity(item_id),
				"weight_each": ItemDefsScript.weight_each(_defs, item_id),
			})
	return out

func reset() -> void:
	items.clear()

func get_summary() -> Dictionary:
	return {
		"items": items.duplicate(true),
		"max_weight": max_weight,
	}

func apply_summary(summary) -> bool:
	if typeof(summary) != TYPE_DICTIONARY or (summary as Dictionary).is_empty():
		return false
	items.clear()
	var items_variant: Variant = (summary as Dictionary).get("items", null)
	if typeof(items_variant) == TYPE_DICTIONARY:
		for item_id in (items_variant as Dictionary):
			items[String(item_id)] = int((items_variant as Dictionary)[item_id])
	if (summary as Dictionary).has("max_weight"):
		max_weight = float((summary as Dictionary)["max_weight"])
	return true
```

- [ ] **Step 4: Run the smoke to verify it passes.**

Run:
```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ship_inventory_smoke.gd 2>&1
```
Expected: PASS — `SHIP INVENTORY SMOKE PASS items=3 weight=...` printed, no unexpected errors.

- [ ] **Step 5: Commit.**

```bash
git add scripts/systems/ship_inventory.gd scripts/validation/ship_inventory_smoke.gd
git commit -m "feat(cargo): ShipInventory per-ship hold model + smoke

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: `CargoTransfer` static + smoke

**Files:**
- Create: `scripts/systems/cargo_transfer.gd`
- Create: `scripts/validation/cargo_transfer_smoke.gd`

**Interfaces:**
- Consumes: `InventoryState` (existing player model), `ShipInventory` (Task 2).
- Produces: `CargoTransfer.deposit_all(player, hold) -> Dictionary` (`{moved: Dictionary, total_moved: int}`), `CargoTransfer.withdraw_category(hold, player, category: String) -> Dictionary` (same shape), const `CargoTransfer.HAULABLE_CATEGORIES := ["part", "supply"]`.

- [ ] **Step 1: Write the failing smoke.**

Create `scripts/validation/cargo_transfer_smoke.gd`:
```gdscript
extends SceneTree

## CargoTransfer pure-logic smoke. Asserts:
##   - deposit_all moves part+supply, LEAVES tools on the player
##   - withdraw_category respects the player carry-weight cap (partial fill)
##   - the conservation invariant: summed per-id quantity across player+hold is
##     invariant under any transfer (no duplication, no loss)

const InventoryStateScript := preload("res://scripts/systems/inventory_state.gd")
const ShipInventoryScript := preload("res://scripts/systems/ship_inventory.gd")
const CargoTransferScript := preload("res://scripts/systems/cargo_transfer.gd")

# All three are real ids (item_definitions.json / tool_definitions.json).
const PART_ITEM := "scrap_metal"          # part, weight 5.0, max_stack 20
const SUPPLY_ITEM := "ration_pack"        # supply, weight 0.5, max_stack 20
const TOOL_ITEM := "portable_oxygen_pump" # tool (tool_definitions.json; used by OxygenState)

func _total(a: Dictionary, b: Dictionary, id: String) -> int:
	return int(a.get(id, 0)) + int(b.get(id, 0))

func _init() -> void:
	var player = InventoryStateScript.new()
	player.add_item(PART_ITEM, 4)
	player.add_item(SUPPLY_ITEM, 3)
	player.add_tool(TOOL_ITEM)   # a tool on the player
	var hold = ShipInventoryScript.create(500.0)

	# --- conservation baseline ---
	var before_part: int = _total(player.items, hold.items, PART_ITEM)
	var before_supply: int = _total(player.items, hold.items, SUPPLY_ITEM)
	var before_tool: int = _total(player.items, hold.items, TOOL_ITEM)

	# --- deposit_all ---
	var dep: Dictionary = CargoTransferScript.deposit_all(player, hold)
	assert(int(dep.get("total_moved", -1)) == 7, "deposited 4 part + 3 supply (got %d)" % int(dep.get("total_moved", -1)))
	assert(player.get_quantity(PART_ITEM) == 0, "part left the player")
	assert(player.get_quantity(SUPPLY_ITEM) == 0, "supply left the player")
	assert(player.has_tool(TOOL_ITEM), "TOOL STAYS on the player")
	assert(hold.get_quantity(PART_ITEM) == 4 and hold.get_quantity(SUPPLY_ITEM) == 3, "hold received salvage")
	assert(hold.get_quantity(TOOL_ITEM) == 0, "tool NOT in the hold")
	# conservation holds across the deposit
	assert(_total(player.items, hold.items, PART_ITEM) == before_part, "part conserved")
	assert(_total(player.items, hold.items, SUPPLY_ITEM) == before_supply, "supply conserved")
	assert(_total(player.items, hold.items, TOOL_ITEM) == before_tool, "tool conserved")

	# --- withdraw_category honors the player carry cap (partial fill) ---
	# Fill the hold heavily, then withdraw 'part' into a near-full player bag.
	hold.add_item(PART_ITEM, 90)
	var pre_player: int = player.get_quantity(PART_ITEM)
	var pre_hold: int = hold.get_quantity(PART_ITEM)
	var wd: Dictionary = CargoTransferScript.withdraw_category(hold, player, "part")
	var moved: int = int(wd.get("total_moved", -1))
	assert(moved >= 0, "withdraw returned a count")
	# conservation across the withdraw
	assert(player.get_quantity(PART_ITEM) + hold.get_quantity(PART_ITEM) == pre_player + pre_hold, "part conserved across withdraw")
	# player never exceeds its weight cap
	assert(player.get_total_weight() <= player.get_max_weight() + 0.0001, "player cap respected")

	print("CARGO TRANSFER SMOKE PASS conserved=true deposited=%d withdrew=%d" % [int(dep.get("total_moved", 0)), moved])
	quit()
```

**Note:** all three ids are real and need no substitution. Worked weights: after `deposit_all`, the hold holds 4 `scrap_metal` (20.0) + 3 `ration_pack` (1.5); the player keeps the oxygen-pump tool. The withdraw step then adds 90 `scrap_metal` to the hold — `scrap_metal` has `max_stack: 20`, so the hold caps at 20, and the withdraw is partial-filled by the player's 50 kg carry cap (≈9 fit), which is exactly the partial-fill + conservation path under test.

- [ ] **Step 2: Run the smoke to verify it fails.**

Run:
```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/cargo_transfer_smoke.gd 2>&1
```
Expected: FAIL — `cargo_transfer.gd` does not exist (no `CARGO TRANSFER SMOKE PASS`).

- [ ] **Step 3: Implement `CargoTransfer`.**

Create `scripts/systems/cargo_transfer.gd`:
```gdscript
extends RefCounted
class_name CargoTransfer

## Pure-static cargo transfer between the player InventoryState and a ship
## ShipInventory. Conservation is the contract: every move removes from the source
## EXACTLY what the destination's add_item reported accepting, so partial fills
## (hold full mid-deposit, player weight-capped mid-withdraw) never duplicate or
## lose items. Iterates over a snapshot of source ids so removals during iteration
## are safe.

# Salvage categories moved by deposit-all. Tools are intentionally excluded —
# survival gear stays on the player and is never auto-dumped into a hold.
const HAULABLE_CATEGORIES: Array = ["part", "supply"]

## Moves all part+supply stacks from player -> hold, capped by the hold's weight
## room. Returns { "moved": {id:qty}, "total_moved": int }.
static func deposit_all(player, hold) -> Dictionary:
	var moved: Dictionary = {}
	var total: int = 0
	if player == null or hold == null:
		return {"moved": moved, "total_moved": 0}
	var ids: Array = (player.items as Dictionary).keys()
	ids.sort()
	for id_v in ids:
		var item_id: String = String(id_v)
		if not (player.get_category(item_id) in HAULABLE_CATEGORIES):
			continue
		var have: int = player.get_quantity(item_id)
		if have <= 0:
			continue
		var accepted: int = hold.add_item(item_id, have)
		if accepted <= 0:
			continue
		var pulled: int = player.remove_item(item_id, accepted)
		# pulled == accepted by construction; guard anyway.
		if pulled > 0:
			moved[item_id] = int(moved.get(item_id, 0)) + pulled
			total += pulled
	return {"moved": moved, "total_moved": total}

## Moves as much of `category` from hold -> player as the player's carry room
## accepts. Returns { "moved": {id:qty}, "total_moved": int }.
static func withdraw_category(hold, player, category: String) -> Dictionary:
	var moved: Dictionary = {}
	var total: int = 0
	if player == null or hold == null or category.is_empty():
		return {"moved": moved, "total_moved": 0}
	var entries: Array = hold.get_items_by_category(category)   # [{id, quantity, weight_each}]
	for entry_v in entries:
		var entry: Dictionary = entry_v
		var item_id: String = String(entry.get("id", ""))
		var have: int = int(entry.get("quantity", 0))
		if item_id.is_empty() or have <= 0:
			continue
		var accepted: int = player.add_item(item_id, have)
		if accepted <= 0:
			continue
		var pulled: int = hold.remove_item(item_id, accepted)
		if pulled > 0:
			moved[item_id] = int(moved.get(item_id, 0)) + pulled
			total += pulled
	return {"moved": moved, "total_moved": total}
```

- [ ] **Step 4: Run the smoke to verify it passes.**

Run:
```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/cargo_transfer_smoke.gd 2>&1
```
Expected: PASS — `CARGO TRANSFER SMOKE PASS conserved=true deposited=7 withdrew=...`.

- [ ] **Step 5: Commit.**

```bash
git add scripts/systems/cargo_transfer.gd scripts/validation/cargo_transfer_smoke.gd
git commit -m "feat(cargo): CargoTransfer deposit-all/withdraw-by-category + conservation smoke

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: `ShipInstance` lazy inventory + persistence

**Files:**
- Modify: `scripts/systems/ship_instance.gd`
- Modify: `scripts/validation/ship_instance_smoke.gd`

**Interfaces:**
- Consumes: `ShipInventory` (Task 2).
- Produces: `ShipInstance.get_inventory() -> ShipInventory` (lazy), `ShipInstance.has_cargo() -> bool`, field `var inventory`; `get_summary()` includes `"inventory"` only when the hold is non-empty; `apply_summary()` reads `"inventory"` when present.

- [ ] **Step 1: Add the lazy field + accessors + persistence to `ShipInstance`.**

In `scripts/systems/ship_instance.gd`:

Add the preload alongside the existing const block (after `const HangarBayScript := preload(...)`):
```gdscript
const ShipInventoryScript := preload("res://scripts/systems/ship_inventory.gd")
```

Add the field next to the `hangar` field (after the `var hangar = null` block):
```gdscript
# Sub-project #6 (cargo): per-ship cargo hold (stores items). Lazily created;
# persisted under "inventory" only when it actually holds something.
var inventory = null                     # ShipInventory | null
```

In `get_summary()`, add — immediately after the `if hangar != null and hangar.slot_count > 0:` block, before `return result`:
```gdscript
	if inventory != null and not inventory.items.is_empty():
		result["inventory"] = inventory.get_summary()
```

In `apply_summary()`, add — immediately after the existing `hangar_summary` block, before `return true`:
```gdscript
	var inventory_summary: Variant = summary.get("inventory", null)
	if typeof(inventory_summary) == TYPE_DICTIONARY and not (inventory_summary as Dictionary).is_empty():
		get_inventory().apply_summary(inventory_summary as Dictionary)
```

Add the accessors next to `get_hangar()` / `has_hangar()`:
```gdscript
## Returns this ship's ShipInventory cargo hold, creating an empty one on first access.
func get_inventory():
	if inventory == null:
		inventory = ShipInventoryScript.create()
	return inventory

## True iff this ship's hold exists and holds at least one item.
func has_cargo() -> bool:
	return inventory != null and not inventory.items.is_empty()
```

- [ ] **Step 2: Add a round-trip assertion to the existing `ship_instance_smoke.gd`.** First read the file to find its existing structure and PASS marker; append the inventory assertions before the final `print(... PASS ...)`/`quit()`.

Add this block (adapt the local variable name for the ShipInstance under test to whatever the smoke already uses — call it `inst` below):
```gdscript
	# --- cargo hold round-trip (sub-project #6) ---
	# Empty hold: summary omits the "inventory" key.
	assert(not inst.get_summary().has("inventory"), "empty hold omitted from summary")
	# Non-empty hold round-trips.
	inst.get_inventory().add_item("scrap_metal", 2)   # use a real weighted part id
	assert(inst.has_cargo(), "has_cargo true after add")
	var s2: Dictionary = inst.get_summary()
	assert(s2.has("inventory"), "non-empty hold present in summary")
	var clone = ShipInstanceScript.create(inst.ship_id, inst.marker_id, null, null, null)
	assert(clone.apply_summary(s2) == true, "apply_summary accepts")
	assert(clone.get_inventory().get_quantity("scrap_metal") == 2, "hold round-tripped")
```
Use the smoke's existing `ShipInstance` preload constant name in place of `ShipInstanceScript`. `scrap_metal` is a real id — no substitution.

- [ ] **Step 3: Run the smoke — verify it still produces its PASS marker.**

Run:
```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ship_instance_smoke.gd 2>&1
```
Expected: PASS — the smoke's existing marker prints, now with the cargo assertions passing. No unexpected errors.

- [ ] **Step 4: Commit.**

```bash
git add scripts/systems/ship_instance.gd scripts/validation/ship_instance_smoke.gd
git commit -m "feat(cargo): ShipInstance lazy cargo hold + persistence round-trip

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 5: `WorldSnapshot.home_ship_inventory` field

**Files:**
- Modify: `scripts/systems/world_snapshot.gd`
- Modify: `scripts/validation/world_snapshot_smoke.gd`

**Interfaces:**
- Produces: `WorldSnapshot.home_ship_inventory: Dictionary` (default `{}`), round-tripped through `to_dict()` / `from_dict()`.

- [ ] **Step 1: Add the field + serialization to `WorldSnapshot`.**

In `scripts/systems/world_snapshot.gd`:

Add the field next to `home_looted_containers` (after line ~16):
```gdscript
var home_ship_inventory: Dictionary = {}        # home ship's ShipInventory.get_summary()
```

In `to_dict()`, add after the `"home_looted_containers": ...` line:
```gdscript
		"home_ship_inventory": home_ship_inventory.duplicate(true),
```

In `from_dict()`, add after the `home_looted_containers` reconstruction block (after the `for cid in (looted_variant as Array): ...` loop):
```gdscript
	ws.home_ship_inventory = _deep_copy_dict(dict.get("home_ship_inventory", {}))
```
(`_deep_copy_dict` already exists and returns `{}` for non-dicts — tolerant of old saves lacking the key.)

**Do NOT change `WORLD_SLICE_VERSION`** — it stays `"world-4"` (additive/tolerant field).

- [ ] **Step 2: Add a round-trip assertion to `world_snapshot_smoke.gd`.** Read the file first for its structure + marker; append before its final `print(... PASS ...)`/`quit()` (use the smoke's existing WorldSnapshot preload constant name in place of `WorldSnapshotScript`, and its existing expected-version locals):
```gdscript
	# --- home_ship_inventory round-trip (sub-project #6, additive, no version bump) ---
	var ws_cargo = WorldSnapshotScript.new()
	ws_cargo.slice_version = expected_world_version    # reuse the smoke's existing version locals
	ws_cargo.godot_version = expected_godot_version
	ws_cargo.home_ship_inventory = {"items": {"scrap_metal": 5}, "max_weight": 500.0}
	var rt = WorldSnapshotScript.from_dict(ws_cargo.to_dict(), expected_world_version, expected_godot_version)
	assert(rt != null, "home-cargo snapshot round-trips")
	assert(int(rt.home_ship_inventory.get("items", {}).get("scrap_metal", 0)) == 5, "home_ship_inventory survived round-trip")
```
If the smoke's version locals are named differently (e.g. `world_v` / `godot_v`), use those names. If it has none, derive them: `var expected_world_version := WorldSnapshotScript.WORLD_SLICE_VERSION` and `var expected_godot_version := Engine.get_version_info()["string"]`.

- [ ] **Step 3: Run the smoke — verify its PASS marker.**

Run:
```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/world_snapshot_smoke.gd 2>&1
```
Expected: PASS — existing marker prints with the new assertion passing.

- [ ] **Step 4: Commit.**

```bash
git add scripts/systems/world_snapshot.gd scripts/validation/world_snapshot_smoke.gd
git commit -m "feat(cargo): WorldSnapshot.home_ship_inventory field (additive, no version bump)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 6: `CargoHoldControl` walk-up sensor

**Files:**
- Create: `scripts/tools/cargo_hold_control.gd`
- Create: `scripts/validation/cargo_hold_smoke.gd` (control-gate section only; Task 7 extends it)

**Interfaces:**
- Produces: `CargoHoldControl` (`extends Area3D`): `configure(p_carrier_id: String, world_position: Vector3, radius := 1.8) -> void`, `try_deposit(player_body: Node) -> bool`, `try_withdraw(player_body: Node, category: String) -> bool`, signals `cargo_deposit_requested(carrier_id: String)`, `cargo_withdraw_requested(carrier_id: String, category: String)`, field `var carrier_id: String`.

- [ ] **Step 1: Write the failing control-gate smoke.**

Create `scripts/validation/cargo_hold_smoke.gd`:
```gdscript
extends SceneTree

## Cargo hold smoke. Section A (this task): CargoHoldControl strict in-range gate —
## off-tree / out-of-range refuses, in-range emits. Section B (Task 7) extends this
## file with the coordinator deposit/withdraw + save/load persistence flow.

const CargoHoldControlScript := preload("res://scripts/tools/cargo_hold_control.gd")

var _deposit_emits: int = 0
var _withdraw_cat: String = ""

func _init() -> void:
	_run_section_a()
	# Section B is appended in Task 7; for now Section A alone prints the marker.
	print("CARGO HOLD SMOKE PASS section_a=true deposited=0 withdrew=0 persisted=false")
	quit()

func _run_section_a() -> void:
	var control = CargoHoldControlScript.new()
	control.cargo_deposit_requested.connect(func(_cid): _deposit_emits += 1)
	control.cargo_withdraw_requested.connect(func(_cid, cat): _withdraw_cat = cat)
	# Off-tree: strict gate refuses (no crash, returns false, no emit).
	assert(control.try_deposit(null) == false, "off-tree/no-player deposit refused")
	assert(_deposit_emits == 0, "no emit while refused")

	root.add_child(control)
	control.configure("test_carrier", Vector3.ZERO, 1.8)
	# A player body in range.
	var player := CharacterBody3D.new()
	root.add_child(player)
	player.global_position = Vector3(0.5, 0.0, 0.0)   # within radius 1.8
	assert(control.try_deposit(player) == true, "in-range deposit emits")
	assert(_deposit_emits == 1, "deposit emitted once")
	assert(control.try_withdraw(player, "part") == true, "in-range withdraw emits")
	assert(_withdraw_cat == "part", "withdraw carried the category")
	# Out of range.
	player.global_position = Vector3(100.0, 0.0, 0.0)
	assert(control.try_deposit(player) == false, "out-of-range deposit refused")
	assert(_deposit_emits == 1, "no extra emit out of range")
```

- [ ] **Step 2: Run to verify it fails.**

Run:
```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/cargo_hold_smoke.gd 2>&1
```
Expected: FAIL — `cargo_hold_control.gd` does not exist.

- [ ] **Step 3: Implement `CargoHoldControl` (mirror of `HangarBayControl`).**

Create `scripts/tools/cargo_hold_control.gd`:
```gdscript
extends Area3D
class_name CargoHoldControl

## The cargo-hold control of a ship. Walk up and interact to deposit all haulable
## salvage into this ship's hold, or withdraw a category back out. Sensor + signal
## only: it does NOT move items (the coordinator owns the inventory models and
## single-ownership). Mirrors the strict in-range gate + marker of HangarBayControl.

signal cargo_deposit_requested(carrier_id: String)
signal cargo_withdraw_requested(carrier_id: String, category: String)

var carrier_id: String = ""
var interaction_radius: float = 1.8
var candidate_player: Node
var collision_shape: CollisionShape3D
var marker: MeshInstance3D

func _ready() -> void:
	monitoring = true
	monitorable = true
	collision_layer = 1
	collision_mask = 1
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)

func configure(p_carrier_id: String, world_position: Vector3, radius := 1.8) -> void:
	assert(radius >= 0.0, "CargoHoldControl.configure: radius must be non-negative")
	carrier_id = p_carrier_id
	interaction_radius = radius
	position = world_position
	name = "CargoHoldControl_%s" % p_carrier_id
	set_meta("cargo_hold_control", true)
	_ensure_collision(radius)
	_ensure_marker(radius)

## Emits cargo_deposit_requested(carrier_id) and returns true iff in range.
func try_deposit(player_body: Node) -> bool:
	if not _is_player_in_direct_range(player_body):
		return false
	emit_signal("cargo_deposit_requested", carrier_id)
	return true

## Emits cargo_withdraw_requested(carrier_id, category) and returns true iff in range.
func try_withdraw(player_body: Node, category: String) -> bool:
	if not _is_player_in_direct_range(player_body):
		return false
	emit_signal("cargo_withdraw_requested", carrier_id, category)
	return true

func _interaction_radius() -> float:
	if is_instance_valid(collision_shape) and collision_shape.shape is SphereShape3D:
		return (collision_shape.shape as SphereShape3D).radius
	return interaction_radius

func _is_player_in_direct_range(player_body: Node) -> bool:
	if not is_instance_valid(player_body) or not (player_body is Node3D):
		return false
	var pn: Node3D = player_body as Node3D
	if not is_inside_tree() or not pn.is_inside_tree():
		return false
	return global_position.distance_to(pn.global_position) <= _interaction_radius()

func _ensure_collision(radius: float) -> void:
	if not is_instance_valid(collision_shape):
		collision_shape = CollisionShape3D.new()
		collision_shape.name = "CargoHoldControlCollisionShape3D"
		add_child(collision_shape)
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	collision_shape.shape = sphere

func _ensure_marker(radius: float) -> void:
	if not is_instance_valid(marker):
		marker = MeshInstance3D.new()
		marker.name = "CargoHoldControlMarker"
		add_child(marker)
	var box := BoxMesh.new()
	box.size = Vector3(radius * 0.5, radius * 0.5, radius * 0.5)
	marker.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.7, 0.85, 0.7)   # cyan-class, distinct from the hangar control's orange
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	marker.material_override = mat
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.set_meta("debug_cargo_hold_control_marker", true)

func _on_body_entered(body: Node3D) -> void:
	if body is PlayerController:
		candidate_player = body

func _on_body_exited(body: Node3D) -> void:
	if body == candidate_player:
		candidate_player = null
```

- [ ] **Step 4: Run to verify it passes.**

Run:
```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/cargo_hold_smoke.gd 2>&1
```
Expected: PASS — `CARGO HOLD SMOKE PASS section_a=true deposited=0 withdrew=0 persisted=false`.

- [ ] **Step 5: Commit.**

```bash
git add scripts/tools/cargo_hold_control.gd scripts/validation/cargo_hold_smoke.gd
git commit -m "feat(cargo): CargoHoldControl walk-up sensor + in-range gate smoke

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 7: Coordinator wiring + main-scene cargo flow

**Files:**
- Modify: `scripts/procgen/playable_generated_ship.gd`
- Modify: `scripts/validation/cargo_hold_smoke.gd` (extend with Section B)

**Interfaces:**
- Consumes: `CargoHoldControl` (Task 6), `CargoTransfer` (Task 3), `ShipInstance.get_inventory()` (Task 4), `WorldSnapshot.home_ship_inventory` (Task 5).
- Produces (validation seams): `cargo_deposit_for_validation(ship_id: String) -> int`, `cargo_withdraw_for_validation(ship_id: String, category: String) -> int`, `ship_hold_quantity_for_validation(ship_id: String, item_id: String) -> int`, `ship_has_cargo_hold_for_validation(ship_id: String) -> bool`, `home_ship_id_for_validation()` (already exists, line ~4624).

**Context:** `playable_generated_ship.gd` is the ~4400-line runtime coordinator. The player inventory model is the field `inventory_state` (created ~line 918). Mirror the hangar-control wiring: `_spawn_hangar_control(inst)` (def ~1451), its call sites, `_clear_hangar_controls()` (def ~1484, called ~4367), `var hangar_controls` (~155). Ship lookup by id: `_find_ship_by_id(id)` (~4215). Save assembly: ~3949-3953 (`ws.home_looted_containers`, `ws.visited_ships`). Load: ~4104-4117. Cargo room location: `DockPorts._room_floor_center(layout, "cargo", "cargo")` returns `Vector3.INF` when absent.

- [ ] **Step 1: Add the preload, the controls array, spawn/clear/handlers, and seams.**

Add the preload near the other tool preloads (next to `HangarBayControlScript`):
```gdscript
const CargoHoldControlScript := preload("res://scripts/tools/cargo_hold_control.gd")
const CargoTransferScript := preload("res://scripts/systems/cargo_transfer.gd")
```

Add the controls array next to `var hangar_controls` (~155):
```gdscript
var cargo_hold_controls: Array = []         # Array[CargoHoldControl]
```

Add the spawn/clear/handler functions next to `_spawn_hangar_control` / `_clear_hangar_controls`:
```gdscript
func _spawn_cargo_hold_control(inst) -> void:
	if inst == null or not is_instance_valid(inst.scene_root):
		return
	var center: Vector3 = DockPortsScript._room_floor_center(inst.built_layout, "cargo", "cargo")
	if center == Vector3.INF:
		return   # no cargo room -> no hold, no lazy ShipInventory
	# Prune dead entries + any existing control for this same carrier (idempotent).
	var kept: Array = []
	for c in cargo_hold_controls:
		if not is_instance_valid(c):
			continue
		if String(c.carrier_id) == String(inst.ship_id):
			if c.get_parent() != null:
				c.get_parent().remove_child(c)
			c.queue_free()
			continue
		kept.append(c)
	cargo_hold_controls = kept
	var control = CargoHoldControlScript.new()
	(inst.scene_root as Node3D).add_child(control)
	control.configure(String(inst.ship_id), center, 1.8)
	control.cargo_deposit_requested.connect(_on_cargo_deposit_requested)
	control.cargo_withdraw_requested.connect(_on_cargo_withdraw_requested)
	cargo_hold_controls.append(control)

func _clear_cargo_hold_controls() -> void:
	for c in cargo_hold_controls:
		if is_instance_valid(c):
			if c.get_parent() != null:
				c.get_parent().remove_child(c)
			c.queue_free()
	cargo_hold_controls.clear()

func _on_cargo_deposit_requested(ship_id: String) -> void:
	if inventory_state == null:
		return
	var inst = _find_ship_by_id(ship_id)
	if inst == null:
		return
	CargoTransferScript.deposit_all(inventory_state, inst.get_inventory())

func _on_cargo_withdraw_requested(ship_id: String, category: String) -> void:
	if inventory_state == null:
		return
	var inst = _find_ship_by_id(ship_id)
	if inst == null:
		return
	CargoTransferScript.withdraw_category(inst.get_inventory(), inventory_state, category)
```

**Confirm the `DockPorts` preload constant name** already used in this file (grep for `DockPorts` / `preload(.*dock_ports`); it is referenced for port derivation. Use that exact constant in place of `DockPortsScript` above. If `_room_floor_center` is `static`, calling it via the preloaded script constant is correct.)

Add the validation seams near the other `*_for_validation` functions:
```gdscript
func cargo_deposit_for_validation(ship_id: String) -> int:
	var inst = _find_ship_by_id(ship_id)
	if inst == null or inventory_state == null:
		return 0
	return int(CargoTransferScript.deposit_all(inventory_state, inst.get_inventory()).get("total_moved", 0))

func cargo_withdraw_for_validation(ship_id: String, category: String) -> int:
	var inst = _find_ship_by_id(ship_id)
	if inst == null or inventory_state == null:
		return 0
	return int(CargoTransferScript.withdraw_category(inst.get_inventory(), inventory_state, category).get("total_moved", 0))

func ship_hold_quantity_for_validation(ship_id: String, item_id: String) -> int:
	var inst = _find_ship_by_id(ship_id)
	if inst == null:
		return 0
	return inst.get_inventory().get_quantity(item_id)

func ship_has_cargo_hold_for_validation(ship_id: String) -> bool:
	for c in cargo_hold_controls:
		if is_instance_valid(c) and String(c.carrier_id) == ship_id:
			return true
	return false
```

- [ ] **Step 2: Wire spawn at every hangar-control spawn site, and clear at the teardown site.**

For EACH call to `_spawn_hangar_control(<x>)` in the file (grep `_spawn_hangar_control(` — there are several: home setup ~2197, lifeboat ~2304, generic ~1276/~4077/~4605), add immediately after it a matching line:
```gdscript
	_spawn_cargo_hold_control(<x>)
```
(same `<x>` argument as the hangar call on that line).

For the call to `_clear_hangar_controls()` (~4367), add immediately after it:
```gdscript
	_clear_cargo_hold_controls()
```

- [ ] **Step 3: Persist the home hold in the save/load assembly.**

In the save assembly (after `ws.home_looted_containers = home_ship.looted_container_ids.duplicate()`, ~3950), add inside the same `if home_ship != null:` block:
```gdscript
		ws.home_ship_inventory = home_ship.get_inventory().get_summary()
```

In the load path (after `home_ship.looted_container_ids = ws.home_looted_containers.duplicate()`, ~4105), add inside the same `if home_ship != null:` block:
```gdscript
		if not ws.home_ship_inventory.is_empty():
			home_ship.get_inventory().apply_summary(ws.home_ship_inventory)
```

- [ ] **Step 4: Extend `cargo_hold_smoke.gd` with Section B (main-scene flow + persistence).**

Replace the `_init()` in `scripts/validation/cargo_hold_smoke.gd` with a version that runs Section A then Section B, and update the marker. Add the playable-ship preload at the top:
```gdscript
const PlayableGeneratedShipScript := preload("res://scripts/procgen/playable_generated_ship.gd")
const InventoryStateScript := preload("res://scripts/systems/inventory_state.gd")
```
New `_init()`:
```gdscript
func _init() -> void:
	_run_section_a()
	_run_section_b()

func _run_section_b() -> void:
	var ship = PlayableGeneratedShipScript.new()
	root.add_child(ship)
	for _i in range(3):
		await process_frame

	var home_id: String = ship.home_ship_id_for_validation()
	assert(ship.ship_has_cargo_hold_for_validation(home_id), "home cargo hold control spawned")

	# Seed the player inventory with a haulable part, then deposit-all into the home hold.
	ship.inventory_state.add_item("scrap_metal", 6)   # scrap_metal: part, weight 5.0, max_stack 20
	var deposited: int = ship.cargo_deposit_for_validation(home_id)
	assert(deposited == 6, "deposited 6 into home hold (got %d)" % deposited)
	assert(ship.ship_hold_quantity_for_validation(home_id, "scrap_metal") == 6, "hold holds 6")
	assert(ship.inventory_state.get_quantity("scrap_metal") == 0, "player emptied of part")

	# Withdraw the category back out.
	var withdrew: int = ship.cargo_withdraw_for_validation(home_id, "part")
	assert(withdrew >= 1, "withdrew at least 1 (got %d)" % withdrew)

	# Re-deposit so the hold is non-empty, then assert the home hold persists via
	# WorldSnapshot.home_ship_inventory across an in-process save->load round-trip.
	# Uses the SAME seams as hangar_persistence_smoke.gd: save_world_for_validation()
	# writes to disk, load_world_for_validation() reloads into the same instance.
	ship.cargo_deposit_for_validation(home_id)
	var qty_before: int = ship.ship_hold_quantity_for_validation(home_id, "scrap_metal")
	assert(ship.save_world_for_validation() == true, "world saved")
	assert(ship.load_world_for_validation() == true, "world loaded")
	for _j in range(3):
		await process_frame
	var home2: String = ship.home_ship_id_for_validation()
	var qty_after: int = ship.ship_hold_quantity_for_validation(home2, "scrap_metal")
	var persisted: bool = qty_after == qty_before and qty_after > 0
	assert(persisted, "home hold persisted across save/load (before=%d after=%d)" % [qty_before, qty_after])
	ship.queue_free()

	print("CARGO HOLD SMOKE PASS section_a=true deposited=%d withdrew=%d persisted=%s" % [deposited, withdrew, str(persisted)])
	quit()
```
And **remove** the `print(...)`/`quit()` that Section A's `_init()` had (the new `_init` ends in `_run_section_b`, which prints/quits).

**Persistence-seam note (confirmed):** `save_world_for_validation() -> bool` and
`load_world_for_validation() -> bool` are the real in-process round-trip seams
(`hangar_persistence_smoke.gd` lines 33-34 use exactly these on a single ship
instance). The load reads the home hold back via `WorldSnapshot.home_ship_inventory`
(Task 5 + Task 7 Step 3). No second ship instance needed.

- [ ] **Step 5: Run the full cargo hold smoke.**

Run:
```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/cargo_hold_smoke.gd 2>&1
```
Expected: PASS — `CARGO HOLD SMOKE PASS section_a=true deposited=6 withdrew=... persisted=true`. (Note: single-smoke runs emit the local-drift `Unrecognized UID` / `MCPRuntime` lines — ignore them; only the absence of the PASS marker or a `resources still in use at exit` line is a failure.)

- [ ] **Step 6: Commit.**

```bash
git add scripts/procgen/playable_generated_ship.gd scripts/validation/cargo_hold_smoke.gd
git commit -m "feat(cargo): coordinator cargo-hold spawn/handlers/persistence + main-scene smoke

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 8: ADR, roadmap, register smokes, full regression + Gate-1

**Files:**
- Create: `docs/game/adr/0020-ship-cargo-holds.md`
- Modify: `docs/game/06_validation_plan.md`
- Modify: `docs/game/09_system_roadmap.md`

**Interfaces:** none (docs + validation registration).

- [ ] **Step 1: Write ADR-0020.**

Create `docs/game/adr/0020-ship-cargo-holds.md`:
```markdown
# ADR-0020: Ship Cargo Holds (player↔ship transfer)

Date: 2026-06-23
Status: Accepted
Relates to: System 6 (Inventory & Equipment); ADR-0012 (world persistence); ADR-0007 (run-snapshot field freeze).

## Context

System 6's player inventory + loot are shipped. The remainder adds per-ship
storage and item transfer. We build the first slice: per-ship cargo holds plus a
physical player↔ship load/unload mechanism.

## Decision

1. **Per-ship hold as a pure model.** `ShipInventory` (`RefCounted`) is a focused,
   weight-capped (default 500) item container sharing `ItemDefs` weights with the
   player `InventoryState`. It lives lazily on `ShipInstance` (`get_inventory()`,
   mirroring `get_hangar()`/`get_access()`).

2. **No ship↔ship transfer.** There is no magic transfer between ships. Moving
   cargo from ship A to ship B is emergent and physical: withdraw into personal
   carry capacity, walk through the airlock to the docked/bayed ship, deposit. This
   matches System 5's physical-everything ethos and removes a subsystem. Carry
   containers (bags/trolleys/carts) that raise per-trip haul capacity are a future
   slice.

3. **Deposit-all / withdraw-by-category; tools excluded.** `CargoTransfer`
   (pure-static) moves only `part`+`supply` on deposit-all; tools (survival gear)
   are never auto-deposited. Withdraw pulls one chosen category. The rich
   item-picker UI is Phase 7. Transfer conserves item counts exactly (removes from
   the source only what the destination accepted).

4. **Physical access point.** `CargoHoldControl` (`Area3D`, mirrors
   `HangarBayControl`) spawns at the cargo-room floor center on any ship with a
   cargo room; it emits deposit/withdraw intents the coordinator services. Ships
   without a cargo room get no hold (clean no-op, like bay-less ships).

5. **Additive persistence, no version bump.** The hold is an additive, tolerant
   field — old saves load with empty holds; no existing structure changes. Unlike
   `world-4` (which restructured `dock_edges`), this does NOT bump
   `WORLD_SLICE_VERSION`. Routing: derelict/visited holds ride
   `ShipInstance.get_summary()["inventory"]`; the home hold rides a new
   `WorldSnapshot.home_ship_inventory` field (mirroring `home_looted_containers`).
   `RunSnapshot` is untouched — it carries an ADR-0007 field freeze, and its
   existing `inventory_summary` is the *player's* bag, not a ship hold.

## Consequences

- Salvage now has a home: dump a run's loot into your ship's hold.
- Cross-ship logistics are a physical hauling activity, not a menu action.
- Save compatibility: additive; pre-cargo saves load fine (empty holds).
- Follow-on slices: carry containers, EquipmentSlots, rich transfer UI (Phase 7),
  tool storage, footprint-scaled hold capacity.
```

- [ ] **Step 2: Register the three smokes in `06_validation_plan.md`.** Read the file to find the marker registry + the `commands=NNN` bundle count (currently 101). Add the three new smokes with their exact markers in the same format the file uses, and bump the count 101 → 104:
  - `ship_inventory_smoke.gd` → `SHIP INVENTORY SMOKE PASS`
  - `cargo_transfer_smoke.gd` → `CARGO TRANSFER SMOKE PASS`
  - `cargo_hold_smoke.gd` → `CARGO HOLD SMOKE PASS`

  Update every place the count appears (the bundle loop list, the count header, and the final `SARGASSO REGRESSION PASS commands=104` expectation). The `ship_instance_smoke` and `world_snapshot_smoke` markers are unchanged (already registered) — do not double-register.

- [ ] **Step 3: Update the System 6 roadmap row.**

In `docs/game/09_system_roadmap.md`, update the System 6 row (line ~39) and the "What remains" section to reflect: player inventory + loot + **ship cargo holds (player↔ship physical transfer)** done; **remaining:** carry containers, EquipmentSlots, item transfer UI. Keep it factual and consistent with the table's existing style. Reference ADR-0020.

- [ ] **Step 4: Run the FULL regression bundle (stash the drift first).**

```bash
cd "C:/Users/dasbl/Documents/The Synaptic Sea"
git stash push -- project.godot
# Run the bundle exactly as 06_validation_plan.md specifies (GODOT/ROOT env set to the
# Windows values in CLAUDE.md). It greps each PASS marker and fails on any unexpected
# ERROR:/WARNING: line.
# <run the bundle block from docs/game/06_validation_plan.md>
git stash pop
```
Expected final line: `SARGASSO REGRESSION PASS commands=104 clean_output=true`. If any smoke's marker is missing or an unexpected `ERROR:`/`WARNING:` appears, fix it before proceeding. (Remember to `git stash pop` even if the bundle fails.)

- [ ] **Step 5: Run the automated Gate-1 playtest (drift still stashed or re-stash).**

```bash
git stash push -- project.godot
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/gate1_automated_playtest.gd 2>&1
git stash pop
```
Expected: `GATE 1 AUTOMATED PLAYTEST PASS` / `pass_decision=GO` / `overall_average=2.00`.

- [ ] **Step 6: Commit.**

```bash
git add docs/game/adr/0020-ship-cargo-holds.md docs/game/06_validation_plan.md docs/game/09_system_roadmap.md
git commit -m "docs(cargo): ADR-0020 + roadmap + register cargo smokes (101->104)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Self-Review notes (for the executor)

- **Real item ids (confirmed, no substitution):** `scrap_metal` (part, weight 5.0, max_stack 20) and `ration_pack` (supply, weight 0.5, max_stack 20) are real ids in `data/items/item_definitions.json`; `portable_oxygen_pump` is a real tool. Mind `scrap_metal`'s `max_stack: 20` when reasoning about hold quantities (Task 3's "add 90" caps at 20).
- **Preload constant names (confirmed):** `DockPortsScript` is the real constant in `playable_generated_ship.gd` (line 35) and `_room_floor_center` is static — Task 7's usage is correct as written. The persistence round-trip seams are `save_world_for_validation()` / `load_world_for_validation()` (confirmed against `hangar_persistence_smoke.gd`).
- **`InventoryState` extract is behavior-preserving:** the regression guard is the unchanged inventory smokes (Task 1 Step 3). If a marker disappears, the extract diverged from the original merge/lookup — fix `ItemDefs`, do not edit the smoke.
- **No version bump:** `WORLD_SLICE_VERSION` stays `"world-4"` throughout.
