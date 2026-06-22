# Loot & Player Inventory (sub-project #3) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make searching a derelict's containers grant quantitied, weighted, categorized items into a player-global inventory that persists ship-to-ship and across save/load.

**Architecture:** Evolve the existing tool-set `InventoryState` into a quantitied/categorized/weight-capped bag, preserving its tool-surface shims so `ToolPickup`/`OxygenState`/the junction gate are untouched. A deterministic `LootRoller` rolls data-driven loot tables seeded by `marker_id + container_id`. A `LootContainer` node (mirroring `ToolPickup`) grants loot on interact. Salvage objectives gain a loot table; a new scattered-container procgen pass spawns crates/lockers. Per-ship looted state rides the `ShipInstance` summary; the bag rides the existing `inventory_summary`.

**Tech Stack:** Godot 4.6.2, typed GDScript, headless `--script` validation smokes.

## Global Constraints

- **Godot binary (headless):** `C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe`
- **Project root:** `C:/Users/dasbl/Documents/The Synaptic Sea`
- **Validation is the definition of done.** A task is done only when its smoke prints its exact PASS marker AND no unexpected `ERROR:`/`WARNING:` lines appear. `--script` can exit 0 on parse errors — trust the marker, not the exit code.
- **Allowlisted teardown noise (ignore):** `ERROR: Capture not registered: 'gdaimcp'.` and `WARNING: ObjectDB instances leaked at exit ...`.
- **Class-cache portability:** new `class_name` scripts (`LootContainer`, `LootRoller`) are NOT in the committed `global_script_class_cache.cfg` and `--headless --script` does not rebuild it. Construct them via a `load("res://...").new()` static factory or a `preload(...)` const — NEVER a bare `ClassName.new()` or `: ClassName` annotation in another script. `InventoryState` and `ShipInstance` are already in the cache and may keep bare/`class_name` refs.
- **Home loop must stay behaviorally identical** (singletons, tool pickups, OxygenState drain, junction gate, HUD) after travelling out and back. Loot containers are **derelicts only** this slice.
- **Do not break the three tool consumers:** `ToolPickup.add_tool`, `OxygenState` drain multiplier (`portable_oxygen_pump` → 0.5), junction gate (`has_tool("junction_calibrator")`).
- **Typed GDScript** for all new code. **Conventional Commits.** Commit trailer: `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.
- **Do not commit** `.godot/`, `*.uid`, or `addons/`. Use selective `git add` of named files only — never `git add -A`.
- **Items are inert this slice:** no consumption (repair = #4), no drop/ship-storage UI, no home containers, `max_weight` is a fixed constant.

Helper to run a smoke (used throughout):

```bash
GODOT="C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe"
ROOT="C:/Users/dasbl/Documents/The Synaptic Sea"
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/<smoke_name>.gd
```

---

### Task 1: Evolve `InventoryState` into a quantitied, weighted, categorized bag

**Files:**
- Create: `data/items/item_definitions.json`
- Modify: `scripts/systems/inventory_state.gd`
- Create (test): `scripts/validation/item_inventory_smoke.gd`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces (relied on by later tasks):
  - `add_item(id: String, qty: int) -> int` — adds up to `qty` honoring `max_stack` and `max_weight`; returns the quantity actually added (0 if none fit).
  - `get_quantity(id: String) -> int`
  - `remove_item(id: String, qty: int) -> int` — removes up to `qty`; returns quantity actually removed.
  - `get_total_weight() -> float`, `get_max_weight() -> float`
  - `get_items_by_category(category: String) -> Array` — `[{ "id": String, "quantity": int, "weight_each": float }]`, ordered by id.
  - `get_category(id: String) -> String` — `"part"`/`"supply"`/`"tool"`/`""`.
  - Preserved shims (unchanged behavior): `add_tool`, `has_tool`, `remove_tool`, `get_drain_multiplier`, `get_summary`, `apply_summary`, `get_status_lines`, `reset`, `get_definition`, `get_display_name`.
  - `tool_ids` remains readable as a **derived** property (ids whose category is `tool`).

- [ ] **Step 1: Before touching anything, find every reader of the old surface**

Run:
```bash
cd "C:/Users/dasbl/Documents/The Synaptic Sea"
grep -rn "\.tool_ids\|inventory_state\.\|InventoryState" scripts --include=*.gd | grep -v "scripts/systems/inventory_state.gd"
```
Confirm the only external uses are: `tool_pickup.gd` (`add_tool`), `playable_generated_ship.gd` (`has_tool`, `get_summary`, `get_status_lines`, `.new()`), and `oxygen_state.gd` (reads the summary's `drain_multiplier`). Anything reading `.tool_ids` as a property must keep working via the derived property in Step 3.

- [ ] **Step 2: Write the failing test** `scripts/validation/item_inventory_smoke.gd`

```gdscript
extends SceneTree

## Pure-model smoke: quantitied/weighted/categorized inventory + tool-shim
## backward compatibility. No scene tree.

const InventoryStateScript := preload("res://scripts/systems/inventory_state.gd")

func _initialize() -> void:
	var ok_add: bool = _test_add_and_categories()
	var ok_weight: bool = _test_weight_cap()
	var ok_round: bool = _test_round_trip()
	var ok_legacy: bool = _test_legacy_compat()
	if ok_add and ok_weight and ok_round and ok_legacy:
		print("ITEM INVENTORY PASS add=true weight_cap=true round_trip=true legacy_compat=true")
	else:
		push_error("ITEM INVENTORY FAIL add=%s weight_cap=%s round_trip=%s legacy_compat=%s" % [
			str(ok_add), str(ok_weight), str(ok_round), str(ok_legacy)])
	quit(0 if (ok_add and ok_weight and ok_round and ok_legacy) else 1)

func _test_add_and_categories() -> bool:
	var inv = InventoryStateScript.new()
	# power_cell is a 'part' defined in item_definitions.json (weight 1.0, max_stack 10).
	var added: int = inv.add_item("power_cell", 3)
	if added != 3 or inv.get_quantity("power_cell") != 3:
		return false
	var parts: Array = inv.get_items_by_category("part")
	if parts.size() != 1 or int(parts[0]["quantity"]) != 3:
		return false
	# Tools still resolve through the shims and are category 'tool'.
	if not inv.add_tool("portable_oxygen_pump"):
		return false
	if not inv.has_tool("portable_oxygen_pump"):
		return false
	if inv.get_category("portable_oxygen_pump") != "tool":
		return false
	if inv.get_drain_multiplier() != 0.5:
		return false
	# Derived tool_ids excludes parts.
	if inv.tool_ids != ["portable_oxygen_pump"]:
		return false
	return true

func _test_weight_cap() -> bool:
	var inv = InventoryStateScript.new()
	# Fill near max with a heavy part, then assert a further add is rejected/partial.
	var max_w: float = inv.get_max_weight()
	# scrap_metal weight 5.0; how many fit fully:
	var fit: int = int(floor(max_w / 5.0))
	var added: int = inv.add_item("scrap_metal", fit + 5)  # request more than fits
	if added != fit:
		return false
	if inv.get_total_weight() > max_w + 0.0001:
		return false
	# A further add of any weighted item returns 0 (full).
	if inv.add_item("scrap_metal", 1) != 0:
		return false
	return true

func _test_round_trip() -> bool:
	var inv = InventoryStateScript.new()
	inv.add_item("power_cell", 2)
	inv.add_item("ration_pack", 4)   # supply
	inv.add_tool("junction_calibrator")
	var summary: Dictionary = inv.get_summary()
	var restored = InventoryStateScript.new()
	if not restored.apply_summary(summary):
		return false
	if restored.get_quantity("power_cell") != 2: return false
	if restored.get_quantity("ration_pack") != 4: return false
	if not restored.has_tool("junction_calibrator"): return false
	if abs(restored.get_total_weight() - inv.get_total_weight()) > 0.0001: return false
	return true

func _test_legacy_compat() -> bool:
	# A pre-#3 save carried only {"tool_ids": [...], "drain_multiplier": ...}.
	var legacy: Dictionary = {"tool_ids": ["portable_oxygen_pump"], "drain_multiplier": 0.5}
	var inv = InventoryStateScript.new()
	if not inv.apply_summary(legacy):
		return false
	if not inv.has_tool("portable_oxygen_pump"): return false
	if inv.get_drain_multiplier() != 0.5: return false
	if inv.tool_ids != ["portable_oxygen_pump"]: return false
	return true
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/item_inventory_smoke.gd`
Expected: FAIL — `add_item`/`get_quantity`/`get_items_by_category`/`get_category`/`get_total_weight`/`get_max_weight` do not exist yet, and `item_definitions.json` is missing.

- [ ] **Step 4: Create `data/items/item_definitions.json`**

```json
{
  "power_cell":   { "display_name": "Power Cell",   "category": "part",   "weight": 1.0, "max_stack": 10 },
  "scrap_metal":  { "display_name": "Scrap Metal",  "category": "part",   "weight": 5.0, "max_stack": 20 },
  "wiring_spool": { "display_name": "Wiring Spool",  "category": "part",   "weight": 2.0, "max_stack": 10 },
  "ration_pack":  { "display_name": "Ration Pack",  "category": "supply", "weight": 0.5, "max_stack": 20 },
  "medkit":       { "display_name": "Medkit",       "category": "supply", "weight": 1.5, "max_stack": 5  }
}
```

- [ ] **Step 5: Rewrite `inventory_state.gd` to the item model with tool shims**

Replace the whole file with the following. Key points: items stored as `id -> qty`; tools live in the same store; definitions merge `item_definitions.json` + `tool_definitions.json`; `tool_ids` is a derived property; `get_summary`/`apply_summary` accept both new and legacy shapes; `get_drain_multiplier`/`get_status_lines` keep their existing REQ-007 markers.

```gdscript
extends RefCounted
class_name InventoryState

## Player-global inventory: quantitied, categorized (part/supply/tool), weight-capped.
## Pure model; never touches the scene tree. Tools are category 'tool' items, exposed
## through legacy shims (add_tool/has_tool/tool_ids/get_drain_multiplier) so OxygenState,
## ToolPickup, and the junction gate are untouched. Round-trips via get/apply_summary.

const ITEM_DEFINITIONS_PATH: String = "res://data/items/item_definitions.json"
const TOOL_DEFINITIONS_PATH: String = "res://data/tools/tool_definitions.json"
const MAX_WEIGHT: float = 50.0
const DEFAULT_TOOL_WEIGHT: float = 2.0
const DEFAULT_MAX_STACK: int = 99

var items: Dictionary = {}          # item_id: String -> quantity: int
var _definitions: Dictionary = {}   # item_id -> def Dictionary (merged)

func _init() -> void:
	_load_definitions()

func _load_definitions() -> void:
	_definitions.clear()
	# Tools first (so item_definitions can override if ever needed); tool defs get a
	# synthetic 'tool' category + default weight while preserving their 'effect' field.
	var tool_defs: Dictionary = _read_json_dict(TOOL_DEFINITIONS_PATH)
	for tool_id in tool_defs:
		var def: Dictionary = (tool_defs[tool_id] as Dictionary).duplicate(true)
		def["category"] = "tool"
		if not def.has("weight"):
			def["weight"] = DEFAULT_TOOL_WEIGHT
		_definitions[tool_id] = def
	var item_defs: Dictionary = _read_json_dict(ITEM_DEFINITIONS_PATH)
	for item_id in item_defs:
		_definitions[item_id] = item_defs[item_id]

func _read_json_dict(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}

# --- definition helpers ---

func get_definition(item_id: String) -> Dictionary:
	var def: Variant = _definitions.get(item_id, {})
	return def if def is Dictionary else {}

func get_category(item_id: String) -> String:
	return str(get_definition(item_id).get("category", ""))

func get_weight_each(item_id: String) -> float:
	# Unknown items weigh 0 so a foreign save round-trips without corrupting the cap.
	return float(get_definition(item_id).get("weight", 0.0))

func _max_stack(item_id: String) -> int:
	return int(get_definition(item_id).get("max_stack", DEFAULT_MAX_STACK))

func get_display_name(item_id: String) -> String:
	var name: String = str(get_definition(item_id).get("display_name", ""))
	return name if not name.is_empty() else item_id.replace("_", " ").capitalize()

# --- item API ---

func get_max_weight() -> float:
	return MAX_WEIGHT

func get_total_weight() -> float:
	var total: float = 0.0
	for item_id in items:
		total += get_weight_each(item_id) * float(items[item_id])
	return total

func get_quantity(item_id: String) -> int:
	return int(items.get(item_id, 0))

## Adds up to qty, honoring max_stack and the carry-weight cap. Returns the
## quantity actually added (0 if none fit). Items with weight 0 ignore the cap.
func add_item(item_id: String, qty: int) -> int:
	if item_id.is_empty() or qty <= 0:
		return 0
	var current: int = get_quantity(item_id)
	var stack_room: int = max(0, _max_stack(item_id) - current)
	var want: int = min(qty, stack_room)
	if want <= 0:
		return 0
	var w: float = get_weight_each(item_id)
	if w > 0.0:
		var remaining: float = get_max_weight() - get_total_weight()
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
		if get_category(item_id) == category:
			out.append({
				"id": item_id,
				"quantity": get_quantity(item_id),
				"weight_each": get_weight_each(item_id),
			})
	return out

func reset() -> void:
	items.clear()
	_load_definitions()

# --- legacy tool shims (REQ-007 consumers depend on these) ---

var tool_ids: Array[String]:
	get:
		var out: Array[String] = []
		var ids: Array = items.keys()
		ids.sort()
		for item_id in ids:
			if get_category(item_id) == "tool":
				out.append(String(item_id))
		return out

func add_tool(tool_id: String) -> bool:
	if tool_id.is_empty() or get_quantity(tool_id) > 0:
		return false
	return add_item(tool_id, 1) == 1

func has_tool(tool_id: String) -> bool:
	return get_quantity(tool_id) > 0 and get_category(tool_id) == "tool"

func remove_tool(tool_id: String) -> bool:
	return remove_item(tool_id, 1) == 1

func get_drain_multiplier() -> float:
	return 0.5 if has_tool("portable_oxygen_pump") else 1.0

# --- save/load ---

func get_summary() -> Dictionary:
	var effects: Array[Dictionary] = []
	for tool_id in tool_ids:
		var effect: Variant = get_definition(tool_id).get("effect", {})
		if effect is Dictionary:
			effects.append({
				"tool_id": tool_id,
				"type": str(effect.get("type", "")),
				"value": effect.get("value", 1.0),
			})
	return {
		"items": items.duplicate(true),
		"tool_ids": tool_ids.duplicate(),          # derived; kept for backward compat
		"active_effects": effects,
		"drain_multiplier": get_drain_multiplier(), # OxygenState consumes this
		"total_weight": get_total_weight(),
		"max_weight": get_max_weight(),
	}

## Accepts the new ("items") shape AND the legacy ("tool_ids"-only) shape.
func apply_summary(summary: Dictionary) -> bool:
	if summary == null or summary.is_empty():
		return false
	items.clear()
	var items_variant: Variant = summary.get("items", null)
	if typeof(items_variant) == TYPE_DICTIONARY:
		for item_id in (items_variant as Dictionary):
			items[String(item_id)] = int((items_variant as Dictionary)[item_id])
	else:
		# Legacy save: reconstruct tool items from tool_ids.
		var legacy_ids: Variant = summary.get("tool_ids", [])
		if typeof(legacy_ids) == TYPE_ARRAY:
			for tool_id in (legacy_ids as Array):
				items[String(tool_id)] = 1
	return true

func get_status_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	# Tools first, preserving the REQ-007 markers the inventory HUD smoke greps.
	for tool_id in tool_ids:
		lines.append("Tool: %s" % get_display_name(tool_id))
		lines.append("tool=%s" % tool_id)
		if tool_id == "portable_oxygen_pump" and get_drain_multiplier() != 1.0:
			lines.append("drain_multiplier=%s" % str(get_drain_multiplier()))
	# Then non-tool items + a weight readout for the loot HUD.
	for cat in ["part", "supply"]:
		for entry in get_items_by_category(cat):
			lines.append("item=%s x%d" % [String(entry["id"]), int(entry["quantity"])])
	lines.append("weight=%s/%s" % [str(snappedf(get_total_weight(), 0.1)), str(get_max_weight())])
	return lines
```

- [ ] **Step 6: Run the new model smoke to verify it passes**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/item_inventory_smoke.gd`
Expected: `ITEM INVENTORY PASS add=true weight_cap=true round_trip=true legacy_compat=true` and no unexpected ERROR/WARNING.

- [ ] **Step 7: Regression-check the existing inventory/tool smokes**

Run each and confirm its PASS marker is unchanged:
```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_inventory_smoke.gd
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_junction_calibrator_smoke.gd
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_junction_calibrator_save_load_smoke.gd
```
Expected: each prints its existing PASS marker (REQ-007/REQ-014 tool path intact). If any fails, the shim is wrong — fix before committing.

- [ ] **Step 8: Commit**

```bash
git add scripts/systems/inventory_state.gd data/items/item_definitions.json scripts/validation/item_inventory_smoke.gd
git commit -m "feat(loot): evolve InventoryState into quantitied/weighted/categorized bag

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: `LootRoller` — deterministic seeded loot tables

**Files:**
- Create: `data/items/loot_tables.json`
- Create: `scripts/systems/loot_roller.gd`
- Create (test): `scripts/validation/loot_table_smoke.gd`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `LootRoller.roll(table_key: String, seed_source: String, tables: Dictionary) -> Array` — returns `[{ "item_id": String, "quantity": int }]`, deterministic for a given `(table_key, seed_source, tables)`. Empty array for an unknown key.
  - `LootRoller.load_tables() -> Dictionary` — parses `loot_tables.json`.
  - Constructed via `preload(...)`/`load(...)`; methods are `static`.

- [ ] **Step 1: Write the failing test** `scripts/validation/loot_table_smoke.gd`

```gdscript
extends SceneTree

## Pure smoke: loot rolls are deterministic per (table_key, seed_source) and vary by seed.

const LootRollerScript := preload("res://scripts/systems/loot_roller.gd")

func _initialize() -> void:
	var tables: Dictionary = LootRollerScript.load_tables()
	var det: bool = _test_deterministic(tables)
	var varies: bool = _test_varies(tables)
	if det and varies:
		print("LOOT TABLE PASS deterministic=true varies_by_seed=true")
	else:
		push_error("LOOT TABLE FAIL deterministic=%s varies_by_seed=%s" % [str(det), str(varies)])
	quit(0 if (det and varies) else 1)

func _test_deterministic(tables: Dictionary) -> bool:
	var a: Array = LootRollerScript.roll("generic_crate", "marker7:crate_3", tables)
	var b: Array = LootRollerScript.roll("generic_crate", "marker7:crate_3", tables)
	if a.is_empty():
		return false
	return JSON.stringify(a) == JSON.stringify(b)

func _test_varies(tables: Dictionary) -> bool:
	var a: Array = LootRollerScript.roll("generic_crate", "marker7:crate_3", tables)
	var b: Array = LootRollerScript.roll("generic_crate", "marker9:crate_8", tables)
	# Different seed sources should (with this table) produce a different result.
	return JSON.stringify(a) != JSON.stringify(b)
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/loot_table_smoke.gd`
Expected: FAIL — `loot_roller.gd` and `loot_tables.json` do not exist.

- [ ] **Step 3: Create `data/items/loot_tables.json`**

Each table has a `rolls` count and weighted `entries`. Item ids must exist in `item_definitions.json`.

```json
{
  "generic_crate": {
    "rolls": 2,
    "entries": [
      { "item_id": "scrap_metal",  "qty_min": 1, "qty_max": 3, "weight": 5 },
      { "item_id": "wiring_spool", "qty_min": 1, "qty_max": 2, "weight": 3 },
      { "item_id": "power_cell",   "qty_min": 1, "qty_max": 1, "weight": 2 }
    ]
  },
  "generic_locker": {
    "rolls": 2,
    "entries": [
      { "item_id": "ration_pack", "qty_min": 1, "qty_max": 3, "weight": 5 },
      { "item_id": "medkit",      "qty_min": 1, "qty_max": 1, "weight": 2 }
    ]
  },
  "salvage_engineering": {
    "rolls": 2,
    "entries": [
      { "item_id": "power_cell",   "qty_min": 1, "qty_max": 2, "weight": 4 },
      { "item_id": "wiring_spool", "qty_min": 1, "qty_max": 2, "weight": 4 },
      { "item_id": "scrap_metal",  "qty_min": 1, "qty_max": 2, "weight": 2 }
    ]
  },
  "salvage_cargo": {
    "rolls": 3,
    "entries": [
      { "item_id": "scrap_metal",  "qty_min": 1, "qty_max": 4, "weight": 5 },
      { "item_id": "ration_pack",  "qty_min": 1, "qty_max": 3, "weight": 4 },
      { "item_id": "power_cell",   "qty_min": 1, "qty_max": 1, "weight": 1 }
    ]
  }
}
```

- [ ] **Step 4: Create `scripts/systems/loot_roller.gd`**

```gdscript
extends RefCounted
class_name LootRoller

## Pure, deterministic loot-table roller. Same (table_key, seed_source, tables)
## always yields the same result. Never touches the scene tree.

const LOOT_TABLES_PATH: String = "res://data/items/loot_tables.json"

static func load_tables() -> Dictionary:
	if not FileAccess.file_exists(LOOT_TABLES_PATH):
		return {}
	var file := FileAccess.open(LOOT_TABLES_PATH, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}

## Returns [{item_id, quantity}], merged by item_id, ordered by item_id.
static func roll(table_key: String, seed_source: String, tables: Dictionary) -> Array:
	var table_variant: Variant = tables.get(table_key, null)
	if typeof(table_variant) != TYPE_DICTIONARY:
		return []
	var table: Dictionary = table_variant
	var entries_variant: Variant = table.get("entries", [])
	if typeof(entries_variant) != TYPE_ARRAY or (entries_variant as Array).is_empty():
		return []
	var entries: Array = entries_variant
	var rolls: int = max(1, int(table.get("rolls", 1)))

	var rng := RandomNumberGenerator.new()
	rng.seed = _stable_seed(seed_source)

	var total_weight: float = 0.0
	for entry in entries:
		total_weight += float((entry as Dictionary).get("weight", 1.0))
	if total_weight <= 0.0:
		return []

	var accum: Dictionary = {}  # item_id -> qty
	for _i in range(rolls):
		var pick: float = rng.randf() * total_weight
		var chosen: Dictionary = entries[0]
		for entry in entries:
			pick -= float((entry as Dictionary).get("weight", 1.0))
			if pick <= 0.0:
				chosen = entry
				break
		var item_id: String = str(chosen.get("item_id", ""))
		if item_id.is_empty():
			continue
		var qty: int = rng.randi_range(int(chosen.get("qty_min", 1)), int(chosen.get("qty_max", 1)))
		if qty <= 0:
			continue
		accum[item_id] = int(accum.get(item_id, 0)) + qty

	var out: Array = []
	var ids: Array = accum.keys()
	ids.sort()
	for item_id in ids:
		out.append({ "item_id": item_id, "quantity": int(accum[item_id]) })
	return out

## Deterministic non-negative seed from a string, stable within a Godot version.
static func _stable_seed(seed_source: String) -> int:
	return abs(seed_source.hash())
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/loot_table_smoke.gd`
Expected: `LOOT TABLE PASS deterministic=true varies_by_seed=true`. (If `varies` flips false, the two seed sources collided — change `marker9:crate_8` to another value and re-run; the assertion only needs one differing pair.)

- [ ] **Step 6: Commit**

```bash
git add scripts/systems/loot_roller.gd data/items/loot_tables.json scripts/validation/loot_table_smoke.gd
git commit -m "feat(loot): add deterministic seeded LootRoller + loot tables

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: Persist looted-container ids on `ShipInstance`

**Files:**
- Modify: `scripts/systems/ship_instance.gd`
- Modify (test): `scripts/validation/ship_instance_smoke.gd`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `ShipInstance.looted_container_ids: Array` — list of scattered-container ids already searched on this ship.
  - `get_summary()` includes `"looted_containers"` only when the array is non-empty (home summary unchanged).
  - `apply_summary()` restores `looted_container_ids` from `"looted_containers"`.

- [ ] **Step 1: Read the current smoke marker**

Open `scripts/validation/ship_instance_smoke.gd`. The current marker is:
`SHIP INSTANCE PASS round_trip=true stubs_present=true objective_round_trip=true`.
You will extend it to add `looted_round_trip=true`.

- [ ] **Step 2: Add the failing assertion to `ship_instance_smoke.gd`**

In the round-trip section (after the existing objective round-trip checks), add a block that sets `looted_container_ids`, round-trips through `get_summary()`/`apply_summary()`, and asserts restoration. Update the printed marker to include `looted_round_trip=%s`. Concretely, locate the success `print(...)` line and replace it, and add the check before it. Example check to insert (adapt variable names to the smoke's existing instance var, here assumed `inst`):

```gdscript
	# Sub-project #3: looted-container ids round-trip on the per-ship slice.
	inst.looted_container_ids = ["crate_3", "locker_1"]
	var s3: Dictionary = inst.get_summary()
	var restored3 = ShipInstanceScript.create("x", "marker:1", null, null, null)
	restored3.apply_summary(s3)
	var looted_round_trip: bool = restored3.looted_container_ids == ["crate_3", "locker_1"]
```

And change the final marker print to:

```gdscript
	print("SHIP INSTANCE PASS round_trip=true stubs_present=true objective_round_trip=true looted_round_trip=%s" % str(looted_round_trip).to_lower())
```

If the smoke gates `quit()` on a boolean, AND `looted_round_trip` into that gate.

- [ ] **Step 3: Run the test to verify it fails**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ship_instance_smoke.gd`
Expected: FAIL — `looted_container_ids` does not exist (or restores empty), so `looted_round_trip=false`.

- [ ] **Step 4: Implement on `ship_instance.gd`**

Add the field near the `objective_controller` declaration:

```gdscript
# Sub-project #3: ids of scattered loot containers already searched on this ship.
# Salvage-point loot reuses the objective `completed` flag, so it is not listed here.
var looted_container_ids: Array = []
```

In `get_summary()`, before `return result`, add:

```gdscript
	if not looted_container_ids.is_empty():
		result["looted_containers"] = looted_container_ids.duplicate()
```

In `apply_summary()`, before `return true`, add:

```gdscript
	var looted_variant: Variant = summary.get("looted_containers", null)
	if typeof(looted_variant) == TYPE_ARRAY:
		looted_container_ids = []
		for cid in (looted_variant as Array):
			looted_container_ids.append(String(cid))
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ship_instance_smoke.gd`
Expected: `SHIP INSTANCE PASS round_trip=true stubs_present=true objective_round_trip=true looted_round_trip=true`.

- [ ] **Step 6: Commit**

```bash
git add scripts/systems/ship_instance.gd scripts/validation/ship_instance_smoke.gd
git commit -m "feat(loot): persist looted-container ids on ShipInstance summary

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: Procgen — salvage loot tables + scattered loot-container specs

**Files:**
- Modify: `scripts/procgen/gameplay_slice_builder.gd`
- Modify: `scripts/procgen/generated_ship_loader.gd`
- Modify (test): `scripts/validation/gameplay_slice_builder_smoke.gd`

**Interfaces:**
- Consumes: nothing from Tasks 1–3 (data-shape only).
- Produces:
  - Gameplay slice gains a top-level `"loot_containers"` array; each entry is `{ "id": String, "kind": String, "room_id": String, "approach_cell": Array, "loot_table": String }`.
  - Each `salvage` objective spec gains a `"loot_table": String` field.
  - `GeneratedShipLoader.get_loot_container_specs_copy() -> Array` — `[{ "id", "kind", "room_id", "loot_table", "position": Vector3 }]`, positions resolved like objective specs (`_room_cell_world`). Empty array when the slice has no `loot_containers`.

- [ ] **Step 1: Read the existing builder smoke to learn its style**

Open `scripts/validation/gameplay_slice_builder_smoke.gd`. Note how it builds a layout dict and asserts on `objectives`. You will add assertions for `loot_containers` and the salvage `loot_table` field using the same setup.

- [ ] **Step 2: Add failing assertions to `gameplay_slice_builder_smoke.gd`**

After the existing objective assertions, add (adapt the built-slice variable name, here `slice`):

```gdscript
	# Sub-project #3: a loot_containers array is emitted and salvage objectives carry a loot_table.
	var loot_containers: Array = slice.get("loot_containers", [])
	var has_containers: bool = loot_containers.size() > 0
	var first := loot_containers[0] if has_containers else {}
	var container_well_formed: bool = has_containers \
		and first.has("id") and first.has("kind") \
		and first.has("room_id") and first.has("approach_cell") and first.has("loot_table")
	var salvage_has_table: bool = true
	for obj in slice.get("objectives", []):
		if str(obj.get("type", "")) == "salvage" and str(obj.get("loot_table", "")).is_empty():
			salvage_has_table = false
```

Then AND `container_well_formed` and `salvage_has_table` into the smoke's pass condition / marker. If the smoke prints a fixed marker, extend it to include `loot_containers=%s salvage_tables=%s`.

- [ ] **Step 3: Run the test to verify it fails**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/gameplay_slice_builder_smoke.gd`
Expected: FAIL — no `loot_containers` key, salvage objectives lack `loot_table`.

- [ ] **Step 4: Add the `loot_table` field to salvage objectives in `gameplay_slice_builder.gd`**

In the salvage-objective loop (the block that appends `{"id": "obj_salvage_%s" % rid, ...}`), add a `loot_table` keyed by room role. Replace the appended dict with:

```gdscript
			objectives.append({
				"id": "obj_salvage_%s" % rid,
				"sequence": sequence,
				"type": "salvage",
				"kind": "single",
				"room_id": rid,
				"approach_cell": approach_cell,
				"loot_table": _salvage_loot_table_for_role(role),
			})
```

Add this helper at the bottom of the class:

```gdscript
## Maps a room role to a salvage loot table key (defined in loot_tables.json).
func _salvage_loot_table_for_role(role: String) -> String:
	match role:
		"engineering", "engine", "reactor", "machine_shop":
			return "salvage_engineering"
		"cargo", "storage", "hold":
			return "salvage_cargo"
		_:
			return "salvage_cargo"
```

- [ ] **Step 5: Emit scattered `loot_containers` in `gameplay_slice_builder.gd`**

After the objectives loop but before returning the slice dict, build a containers array. Place one container in each non-connective room that ISN'T already the start/goal, alternating crate/locker for variety, with a stable id. Find where the slice dict is assembled (the `return { ... }` near the end of `build`) and add a `loot_containers` key. Insert this before that return:

```gdscript
	var loot_containers: Array = []
	var container_index: int = 0
	for room in rooms:
		var rid2: String = str(room.get("id", ""))
		var role2: String = str(room.get("room_role", ""))
		if rid2 == start_room or rid2 == goal_room:
			continue
		if role2 in CONNECTIVE_ROLES:
			continue
		var cell2: Array = _get_first_floor_cell(room)
		if cell2.is_empty():
			continue
		var kind2: String = "generic_locker" if container_index % 2 == 1 else "generic_crate"
		loot_containers.append({
			"id": "loot_%s" % rid2,
			"kind": kind2,
			"room_id": rid2,
			"approach_cell": cell2,
			"loot_table": kind2,
		})
		container_index += 1
```

Then add `"loot_containers": loot_containers,` to the returned slice dictionary. (If `build()` returns a pre-named local like `var slice := { ... }`, add the key to that literal instead.)

- [ ] **Step 6: Add `get_loot_container_specs_copy()` to `generated_ship_loader.gd`**

Add a member array `var loot_container_specs: Array = []` near `objective_specs`. In `load_from_paths`, after `objective_specs = _build_objective_specs(...)`, add:

```gdscript
	loot_container_specs = _build_loot_container_specs(layout_doc, gameplay_doc)
```

Add the public copy method next to `get_objective_specs_copy`:

```gdscript
func get_loot_container_specs_copy() -> Array:
	return loot_container_specs.duplicate(true)
```

Add the builder (resolves positions exactly like objectives via `_room_cell_world`):

```gdscript
func _build_loot_container_specs(layout_doc: Dictionary, gameplay_doc: Dictionary) -> Array:
	var rooms_variant: Variant = layout_doc.get("rooms", [])
	if typeof(rooms_variant) != TYPE_ARRAY:
		return []
	var rooms: Array = rooms_variant
	var containers_variant: Variant = gameplay_doc.get("loot_containers", [])
	if typeof(containers_variant) != TYPE_ARRAY:
		return []
	var out: Array = []
	for c_variant in (containers_variant as Array):
		if typeof(c_variant) != TYPE_DICTIONARY:
			continue
		var c: Dictionary = c_variant
		var cid: String = str(c.get("id", ""))
		var room_id: String = str(c.get("room_id", ""))
		if cid.is_empty() or room_id.is_empty():
			continue
		var room: Dictionary = _find_room(rooms, room_id)
		if room.is_empty():
			continue
		var approach_variant: Variant = c.get("approach_cell", [])
		if typeof(approach_variant) != TYPE_ARRAY or (approach_variant as Array).size() < 3:
			continue
		var pos: Vector3 = _room_cell_world(room, approach_variant as Array)
		if pos == Vector3.INF:
			continue
		out.append({
			"id": cid,
			"kind": str(c.get("kind", "generic_crate")),
			"room_id": room_id,
			"loot_table": str(c.get("loot_table", "generic_crate")),
			"position": pos,
		})
	return out
```

- [ ] **Step 7: Run the builder smoke to verify it passes**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/gameplay_slice_builder_smoke.gd`
Expected: the smoke's PASS marker with `loot_containers=true salvage_tables=true` (or whatever exact marker you extended).

- [ ] **Step 8: Regression-check the loader + golden slice path**

Procgen and golden ships share one slice schema; confirm the added key doesn't break loaders:
```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/coherent_runtime_loader_smoke.gd
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/procgen_ship_gameplay_smoke.gd
```
Expected: each prints its existing PASS marker. The new `loot_containers` key is additive (golden slices simply omit it → empty array).

- [ ] **Step 9: Commit**

```bash
git add scripts/procgen/gameplay_slice_builder.gd scripts/procgen/generated_ship_loader.gd scripts/validation/gameplay_slice_builder_smoke.gd
git commit -m "feat(loot): emit salvage loot tables + scattered loot-container specs

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: `LootContainer` node + coordinator integration

**Files:**
- Create: `scripts/tools/loot_container.gd`
- Modify: `scripts/procgen/playable_generated_ship.gd`
- Create (test): `scripts/validation/derelict_loot_smoke.gd`

**Interfaces:**
- Consumes: `InventoryState.add_item` (Task 1), `LootRoller.roll` (Task 2), `ShipInstance.looted_container_ids` (Task 3), `GeneratedShipLoader.get_loot_container_specs_copy` + salvage `loot_table` (Task 4).
- Produces:
  - `LootContainer` node: `configure(container_id, loot_table, seed_source, inventory_state, tables, world_position, radius)`, `signal container_searched(container_id: String, granted: Array)`, `try_interact(player_body) -> bool`, `set_validation_player_in_range(player)`, `var searched: bool`, `var container_id: String`.
  - Coordinator: `var loot_container_root: Node3D`, `var loot_containers: Array`, `search_loot_container_for_validation(container_id: String) -> bool`.

- [ ] **Step 1: Write the failing integration smoke** `scripts/validation/derelict_loot_smoke.gd`

```gdscript
extends SceneTree

## Main-scene smoke: board a derelict, search a loot container, items enter the bag
## and weight rises; leave + revisit keeps it looted and the bag intact; a disk
## save/load aboard preserves the bag; returning home leaves the home loop + tools intact.

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 300

var main_node: Node
var frame_count: int = 0
var finished: bool = false
var _exit_code: int = 0

func _initialize() -> void:
	main_node = MAIN_SCENE.instantiate()
	if main_node == null:
		_fail("could not instantiate main scene"); return
	get_root().add_child(main_node)
	process_frame.connect(_on_process_frame)

func _on_process_frame() -> void:
	if finished:
		return
	frame_count += 1
	var playable: PlayableGeneratedShip = _find_playable(main_node)
	if playable == null:
		if frame_count > TIMEOUT_FRAMES: _fail("no PlayableGeneratedShip")
		return
	if playable.loader == null or not playable.loader.has_loaded_ship():
		if frame_count > TIMEOUT_FRAMES: _fail("loader did not finish")
		return
	_validate(playable)

func _validate(playable: PlayableGeneratedShip) -> void:
	# Make this ship travel-capable, then board a derelict.
	for sid in ["power", "navigation", "scanners", "propulsion"]:
		var sys = playable.get_ship_systems_manager().get_system(sid)
		if sys != null:
			for sub in sys.subcomponents:
				playable.get_ship_systems_manager().force_repair(sid, sub.subcomponent_id)
	var world = playable.get_sargasso_world()
	var in_range: Array = world.markers_in_range(playable.scanner_state.range_radius)
	if in_range.is_empty():
		_fail("no markers in range"); return
	var marker_id: String = String(in_range[0].marker_id)
	if not bool(playable.travel_to_marker_id(marker_id).get("success", false)):
		_fail("travel to derelict failed"); return

	if playable.loot_containers.is_empty():
		_fail("no loot containers built on board"); return
	var weight_before: float = playable.inventory_state.get_total_weight()
	var cid: String = String(playable.loot_containers[0].container_id)
	if not playable.search_loot_container_for_validation(cid):
		_fail("search of loot container failed"); return
	if playable.inventory_state.get_total_weight() <= weight_before:
		_fail("searching granted no weight"); return
	if not playable.loot_containers[0].searched:
		_fail("container not marked searched"); return
	var carried_weight: float = playable.inventory_state.get_total_weight()
	var items_snapshot: Dictionary = playable.inventory_state.items.duplicate(true)

	# Leave to home and revisit: container stays looted, bag unchanged.
	if not playable.travel_home(): _fail("travel_home failed"); return
	if not bool(playable.travel_to_marker_id(marker_id).get("success", false)):
		_fail("revisit travel failed"); return
	var still_looted: bool = false
	for lc in playable.loot_containers:
		if String(lc.container_id) == cid and lc.searched:
			still_looted = true
	if not still_looted:
		_fail("container respawned on revisit"); return
	if playable.inventory_state.items != items_snapshot:
		_fail("bag changed across revisit"); return

	# Disk save/load while aboard preserves the bag.
	if not playable.request_save(): _fail("save failed"); return
	if not playable.request_load(): _fail("load failed"); return
	if abs(playable.inventory_state.get_total_weight() - carried_weight) > 0.0001:
		_fail("bag weight not preserved across disk save/load"); return

	# Home loop + tool effect intact.
	if not playable.travel_home(): _fail("second travel_home failed"); return
	if playable.away_from_start:
		_fail("away_from_start still true at home"); return

	finished = true
	print("DERELICT LOOT PASS searched=true carried=true persists=true home_intact=true")
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
	if finished: return
	finished = true
	push_error("DERELICT LOOT FAIL reason=%s" % reason)
	_teardown_and_quit(1)

func _teardown_and_quit(code: int) -> void:
	_exit_code = code
	if main_node != null and is_instance_valid(main_node):
		main_node.free(); main_node = null
	call_deferred("_do_quit")

func _do_quit() -> void:
	quit(_exit_code)
```

> Before implementing, confirm the coordinator's save/load method names. Grep `func request_save\|func request_load\|func travel_to_marker_id\|func travel_home` in `playable_generated_ship.gd`; if the save/load seam differs (e.g. `_auto_save_current_run`/`request_world_save`), adjust the two calls in the smoke to the real names. The behavior asserted (bag survives a disk round-trip aboard) is what matters.

- [ ] **Step 2: Run the smoke to verify it fails**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/derelict_loot_smoke.gd`
Expected: FAIL — `loot_containers`, `search_loot_container_for_validation`, and the `LootContainer` class do not exist.

- [ ] **Step 3: Create `scripts/tools/loot_container.gd`**

Mirror `ToolPickup` (Area3D, sphere collision, range check, validation seam). On first search it rolls via `LootRoller`, grants via `add_item` (partial allowed under the weight cap), marks searched, and emits.

```gdscript
extends Area3D
class_name LootContainer

## Searchable loot container. On first interaction it rolls its table deterministically
## (seed = container's seed_source) and grants the result to the player InventoryState,
## then marks itself searched. Mirrors ToolPickup's interaction/range contract.

const LootRollerScript := preload("res://scripts/systems/loot_roller.gd")

signal container_searched(container_id: String, granted: Array)

var container_id: String = ""
var loot_table: String = ""
var seed_source: String = ""
var inventory_state                       # InventoryState
var tables: Dictionary = {}
var interaction_radius: float = 1.8
var searched: bool = false
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

func configure(p_container_id: String, p_loot_table: String, p_seed_source: String, p_inventory_state, p_tables: Dictionary, world_position: Vector3, radius := 1.8) -> void:
	container_id = p_container_id
	loot_table = p_loot_table
	seed_source = p_seed_source
	inventory_state = p_inventory_state
	tables = p_tables
	interaction_radius = radius
	searched = false
	candidate_player = null
	position = world_position
	name = "LootContainer_%s" % p_container_id
	set_meta("loot_container", true)
	set_meta("container_id", container_id)
	_ensure_collision(radius)
	_ensure_marker(radius)

func set_validation_player_in_range(player_body: Node) -> void:
	candidate_player = player_body

func set_searched(value: bool) -> void:
	searched = value
	set_marker_visible(marker_visible)
	if collision_shape != null:
		collision_shape.disabled = searched

func set_marker_visible(is_visible: bool) -> void:
	marker_visible = is_visible
	if marker != null:
		marker.visible = marker_visible and not searched

func try_interact(player_body: Node) -> bool:
	if searched or player_body == null or inventory_state == null:
		return false
	if not _is_player_in_direct_range(player_body):
		return false
	var rolled: Array = LootRollerScript.roll(loot_table, seed_source, tables)
	var granted: Array = []
	for entry in rolled:
		var item_id: String = str((entry as Dictionary).get("item_id", ""))
		var qty: int = int((entry as Dictionary).get("quantity", 0))
		if item_id.is_empty() or qty <= 0:
			continue
		var added: int = inventory_state.add_item(item_id, qty)
		if added > 0:
			granted.append({ "item_id": item_id, "quantity": added })
	# Searching consumes the container even if the bag was full (no re-roll on revisit).
	set_searched(true)
	emit_signal("container_searched", container_id, granted)
	return true

func _interaction_radius() -> float:
	if collision_shape != null and collision_shape.shape is SphereShape3D:
		return (collision_shape.shape as SphereShape3D).radius
	return interaction_radius

func _is_player_in_direct_range(player_body: Node) -> bool:
	if not (player_body is Node3D):
		return false
	var player_node: Node3D = player_body as Node3D
	var here: Vector3 = global_position if is_inside_tree() else position
	var there: Vector3 = player_node.global_position if player_node.is_inside_tree() else player_node.position
	return here.distance_to(there) <= _interaction_radius()

func _ensure_collision(radius: float) -> void:
	if collision_shape == null:
		collision_shape = CollisionShape3D.new()
		collision_shape.name = "LootContainerCollisionShape3D"
		add_child(collision_shape)
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	collision_shape.shape = sphere
	collision_shape.disabled = searched

func _ensure_marker(radius: float) -> void:
	if marker == null:
		marker = MeshInstance3D.new()
		marker.name = "LootContainerMarker"
		add_child(marker)
	var box := BoxMesh.new()
	box.size = Vector3(radius * 0.6, radius * 0.6, radius * 0.6)
	marker.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.7, 0.2, 0.65)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	marker.material_override = mat
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.visible = marker_visible and not searched
	marker.set_meta("debug_loot_container_marker", true)

func _on_body_entered(body: Node3D) -> void:
	if body is PlayerController:
		candidate_player = body

func _on_body_exited(body: Node3D) -> void:
	if body == candidate_player:
		candidate_player = null
```

- [ ] **Step 4: Wire the coordinator — declarations + root**

In `playable_generated_ship.gd`, near the `derelict_objective_root`/`derelict_interactables` declarations (around line 131), add:

```gdscript
const LootContainerScript := preload("res://scripts/tools/loot_container.gd")
const LootRollerScript := preload("res://scripts/systems/loot_roller.gd")
var loot_container_root: Node3D = null
var loot_containers: Array = []
var _loot_tables: Dictionary = {}
var _salvage_loot_tables: Dictionary = {}   # objective_id -> loot_table key
```

In `_build_runtime_nodes()`, right after the `derelict_objective_root` is created (around line 901), add:

```gdscript
	loot_container_root = Node3D.new()
	loot_container_root.name = "LootContainerRoot"
	add_child(loot_container_root)
	_loot_tables = LootRollerScript.load_tables()
```

- [ ] **Step 5: Wire the coordinator — build/clear loot containers**

Add these methods next to `_build_derelict_objectives`/`_clear_derelict_objectives`:

```gdscript
## Builds the active derelict's scattered loot containers (skipped on the home ship).
## Containers already in the ship's looted_container_ids read as searched (no respawn).
func _build_loot_containers() -> void:
	_clear_loot_containers()
	if current_ship == null or String(current_ship.marker_id) == "":
		return
	var active_loader = current_ship.scene_root
	if not is_instance_valid(active_loader) or not active_loader.has_method("get_loot_container_specs_copy"):
		return
	var looted: Array = current_ship.looted_container_ids
	for spec_variant in active_loader.get_loot_container_specs_copy():
		if typeof(spec_variant) != TYPE_DICTIONARY:
			continue
		var spec: Dictionary = spec_variant
		var cid: String = str(spec.get("id", ""))
		var pos_variant: Variant = spec.get("position", Vector3.INF)
		if cid.is_empty() or typeof(pos_variant) != TYPE_VECTOR3:
			continue
		var lc = LootContainerScript.new()
		var seed_source: String = "%s:%s" % [String(current_ship.marker_id), cid]
		lc.configure(cid, str(spec.get("loot_table", "generic_crate")), seed_source,
			inventory_state, _loot_tables, pos_variant, 1.8)
		if looted.has(cid):
			lc.set_searched(true)
		if not lc.container_searched.is_connected(_on_loot_container_searched):
			lc.container_searched.connect(_on_loot_container_searched)
		loot_container_root.add_child(lc)
		loot_containers.append(lc)

func _clear_loot_containers() -> void:
	if is_instance_valid(loot_container_root):
		for child in loot_container_root.get_children():
			loot_container_root.remove_child(child)
			child.queue_free()
	loot_containers.clear()

## Records a searched scattered container on the per-ship slice + refreshes the HUD.
func _on_loot_container_searched(container_id: String, granted: Array) -> void:
	if current_ship != null and not current_ship.looted_container_ids.has(container_id):
		current_ship.looted_container_ids.append(container_id)
	_refresh_inventory_hud()
	print("LOOT CONTAINER SEARCHED marker=%s container=%s granted=%d" % [
		String(current_ship.marker_id) if current_ship != null else "", container_id, granted.size()])

## Validation seam: search a loot container by id through the real interaction path.
func search_loot_container_for_validation(container_id: String) -> bool:
	for lc in loot_containers:
		if is_instance_valid(lc) and String(lc.container_id) == container_id and not lc.searched:
			lc.set_validation_player_in_range(player)
			return lc.try_interact(player)
	return false
```

For `_refresh_inventory_hud()`: if the coordinator already has a method that pushes `inventory_state.get_status_lines()` to the HUD (search around line 1612), call that instead — reuse it; do NOT duplicate HUD code. If it is inline, extract the inline block into `_refresh_inventory_hud()` and call it from both places.

- [ ] **Step 6: Wire the coordinator — build containers on board, clear on leave/reload, salvage loot grant**

1. In `_attach_derelict_active(...)`, on the line after `_build_derelict_objectives()` (around line 1033), add:
```gdscript
	_build_loot_containers()
```

2. In `travel_home()` where `_clear_derelict_objectives()` is called (around line 1202), add right after it:
```gdscript
	_clear_loot_containers()
```

3. In `_reset_runtime_for_reload()`'s `away_from_start` block where `_clear_derelict_objectives()` is called (around line 3033), add right after it:
```gdscript
	_clear_loot_containers()
```

4. Salvage-point loot: in `_build_derelict_objectives()`, while iterating specs, record salvage tables. Right after `var sequence: int = int(spec.get("sequence", 0))` block where the interactable is built, add (inside the loop, for salvage specs):
```gdscript
		if str(spec.get("type", "")) == "salvage":
			_salvage_loot_tables[str(spec.get("id", ""))] = str(spec.get("loot_table", "salvage_cargo"))
```
Clear it at the top of `_build_derelict_objectives()` (after `_clear_derelict_objectives()`):
```gdscript
	_salvage_loot_tables.clear()
```
Then in `_on_derelict_interactable_completed(...)`, after `controller.complete(sequence)`, grant salvage loot once (the interactable can't re-fire on revisit, so this never double-grants):
```gdscript
	if objective_type == "salvage" and _salvage_loot_tables.has(objective_id):
		var seed_source: String = "%s:%s" % [String(current_ship.marker_id), objective_id]
		var rolled: Array = LootRollerScript.roll(_salvage_loot_tables[objective_id], seed_source, _loot_tables)
		for entry in rolled:
			inventory_state.add_item(str(entry.get("item_id", "")), int(entry.get("quantity", 0)))
		_refresh_inventory_hud()
```

- [ ] **Step 7: Run the integration smoke to verify it passes**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/derelict_loot_smoke.gd`
Expected: `DERELICT LOOT PASS searched=true carried=true persists=true home_intact=true` and no unexpected ERROR/WARNING. Debugging hooks: the `LOOT CONTAINER SEARCHED ...` line should appear once.

- [ ] **Step 8: Regression-check the derelict + save/load smokes**

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/derelict_gameplay_smoke.gd
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/world_save_anywhere_smoke.gd
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_save_load_smoke.gd
```
Expected: each prints its existing PASS marker (derelict objective loop + world persistence undisturbed). Run these one at a time, NOT concurrently — smokes share the single save slot `user://saves/current_run.json` and MCP port 3572; concurrent runs cause spurious save/load failures.

- [ ] **Step 9: Commit**

```bash
git add scripts/tools/loot_container.gd scripts/procgen/playable_generated_ship.gd scripts/validation/derelict_loot_smoke.gd
git commit -m "feat(loot): LootContainer node + coordinator integration (search, grant, persist)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 6: Register smokes, ADR-0014, docs

**Files:**
- Modify: `docs/game/06_validation_plan.md`
- Create: `docs/game/adr/0014-loot-player-inventory.md`
- Modify: `docs/game/00_vision.md`

**Interfaces:**
- Consumes: the three new PASS markers from Tasks 1, 2, 5.
- Produces: regression bundle count 67 → 70; ADR-0014.

- [ ] **Step 1: Register the three new smokes in the regression bundle**

In `docs/game/06_validation_plan.md`, add the three smokes to the bundle script with their expected markers, following the existing entry format:
- `item_inventory_smoke.gd` → `ITEM INVENTORY PASS add=true weight_cap=true round_trip=true legacy_compat=true`
- `loot_table_smoke.gd` → `LOOT TABLE PASS deterministic=true varies_by_seed=true`
- `derelict_loot_smoke.gd` → `DERELICT LOOT PASS searched=true carried=true persists=true home_intact=true`

Also update the two extended markers in the doc if they are listed there:
- `ship_instance_smoke.gd` now ends `... looted_round_trip=true`
- `gameplay_slice_builder_smoke.gd` marker extended in Task 4.

Bump the final success line count: `SARGASSO REGRESSION PASS commands=67` → `commands=70`. Grep the doc for `commands=67` to find every occurrence (header counts + the final assertion) and update all.

- [ ] **Step 2: Run the FULL regression bundle**

Run the bash block in `docs/game/06_validation_plan.md` with `GODOT`/`ROOT` set to the Windows values. Run it to completion (it runs smokes sequentially — never concurrently with any other smoke).
Expected final line: `SARGASSO REGRESSION PASS commands=70 clean_output=true`. If any smoke is missing its marker or emits an un-allowlisted ERROR/WARNING, fix before proceeding.

- [ ] **Step 3: Write ADR-0014** `docs/game/adr/0014-loot-player-inventory.md`

```markdown
# ADR-0014: Loot & player inventory (quantitied bag + deterministic containers)

Date: 2026-06-21
Status: Accepted
Related: ADR-0011 (ShipInstance & travel), ADR-0012 (world persistence),
ADR-0013 (derelict gameplay parity), docs/game/00_vision.md (North Star),
docs/superpowers/specs/2026-06-21-loot-player-inventory-design.md

## Context

ADR-0013 gave derelicts an objective loop but deliberately deferred the tangible
reward: completing a salvage objective yielded only a `cleared` flag. The North Star
makes loot the real "why board a derelict." The existing `InventoryState` was a
tool-set (unique ids, no quantities), insufficient to accumulate parts/supplies.

## Decision

Evolve `InventoryState` in place into a quantitied, categorized (part/supply/tool),
weight-capped bag, preserving its tool-surface shims (`add_tool`/`has_tool`/`tool_ids`/
`get_drain_multiplier`) so OxygenState, ToolPickup, and the junction gate are untouched.
A pure `LootRoller` rolls data-driven loot tables deterministically, seeded by
`marker_id + container_id`, so a given ship always yields the same loot and persistence
records only THAT a container was emptied. A `LootContainer` node (mirroring ToolPickup)
grants loot on interact. One container mechanism serves two spawn contexts: salvage
objectives gain a `loot_table`, and a new procgen pass scatters crates/lockers. Per-ship
looted state rides `ShipInstance.looted_container_ids`; the player bag rides the existing
`inventory_summary`.

## Consequences

- Loot is **derelicts only** this slice; the home ship keeps its tool pickups + singleton
  loop untouched (the ADR-0013 home-loop constraint). Unifying home onto the same mechanism
  follows the home/derelict convergence (ADR-0011 Approach B).
- Items are **inert**: #3 delivers acquire → carry (weight-gated) → persist. Consumption
  (repair spends parts) is #4; survival consumables are #2b. No drop/ship-storage UI yet.
- Loot is deterministic per seed, not random per visit, matching "ships persist once
  accessed." Re-rolling would let players farm one container — explicitly avoided.
- `max_weight` is a fixed constant; capacity upgrades are future scope.

## Note: transitional

Per ADR-0013's note and the North Star, the home/derelict split is transitional. Loot is
built as an any-ship system (the bag is player-global, the container mechanism is
ship-agnostic) precisely so the home ship can adopt it when the convergence lands.
```

- [ ] **Step 4: Cross-reference loot in the vision doc**

In `docs/game/00_vision.md`, under the North Star section, the "Loot" bullet (item 1) and the transitional-scaffolding paragraph reference loot as future work. Add a short parenthetical noting it is now partially realized: locate the line `1. **Loot** — scavenge parts, tools, and supplies into your inventory.` and append `(realized for derelicts in sub-project #3 — see ADR-0014).` Do not restructure the section.

- [ ] **Step 5: Commit**

```bash
git add docs/game/06_validation_plan.md docs/game/adr/0014-loot-player-inventory.md docs/game/00_vision.md
git commit -m "docs(loot): register loot smokes (67->70) + ADR-0014 + vision cross-ref

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Self-Review (completed by plan author)

**Spec coverage:**
- §1 item model (quantities/categories/weight, tool shims) → Task 1. ✓
- §2 unified LootContainer, two spawn contexts, derelicts-only → Tasks 4 (specs) + 5 (node/wiring). ✓
- §3 item_definitions.json, loot_tables.json, deterministic seed → Tasks 1, 2. ✓
- §4 persistence (bag via inventory_summary, looted ids via ShipInstance) → Tasks 1 (summary) + 3 (ship) + 5 (wiring). ✓
- §5 scope boundary (inert, no drop UI, no home containers, fixed max_weight) → constraints + Task 5 (derelicts-only guard). ✓
- §6 three smokes + bundle 67→70 + ADR-0014 → Tasks 1/2/5 (smokes) + 6 (registration/ADR). ✓
- HUD weight readout → Task 1 (`get_status_lines`) + Task 5 (`_refresh_inventory_hud`). ✓

**Type consistency:** `add_item(id, qty) -> int`, `LootRoller.roll(table_key, seed_source, tables) -> Array` of `{item_id, quantity}`, `LootContainer.configure(container_id, loot_table, seed_source, inventory_state, tables, position, radius)`, `ShipInstance.looted_container_ids: Array`, coordinator `loot_containers`/`search_loot_container_for_validation` — names used identically across Tasks 1–6. ✓

**Placeholder scan:** no TBD/TODO; every code step shows full code. Two steps intentionally instruct a grep-and-adapt (Task 1 Step 1 reader audit; Task 5 Step 1 save/load method-name confirmation) because the exact existing names must be verified against the live coordinator — each gives the concrete fallback. ✓
