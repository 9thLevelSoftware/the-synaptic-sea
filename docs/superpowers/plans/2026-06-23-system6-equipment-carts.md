# Equipment, Carry Containers & Carts (System 6 slice 2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the PZ-faithful worn-equipment + carry-container + cart layer of System 6: body-location equipment slots, worn containers that raise carry capacity, PZ soft-cap encumbrance with a Heavy Load movement penalty, and pushable carts whose contents are off the player's personal encumbrance.

**Architecture:** A pure `EquipmentState` (`RefCounted`) holds worn items by slot and aggregates effects (carry-capacity bonus, oxygen-drain). `ItemDefs` gains equipment metadata readers + new equipment item defs. `InventoryState` goes **soft-cap** (`add_item` accepts over the weight cap; new capacity/load-ratio queries) — the ship `ShipInventory` stays hard-capped. A pure-static `Encumbrance` maps load-ratio → a PZ-tiered `move_speed` multiplier wired to `PlayerController.move_speed`. Carts are a pure `CartState` (a mobile container wrapping a `ShipInventory`, contents excluded from personal encumbrance) + a walk-up `CartControl` (`Area3D`, mirrors `CargoHoldControl`) the coordinator services (grab/release/load/unload, both-hands block, push penalty). Persistence is additive (no save-version bump): player equipment rides a new `WorldSnapshot.player_equipment` field; carts ride `ShipInstance.get_summary()["carts"]`.

**Tech Stack:** Godot 4.6.2, typed GDScript, headless `--script` validation smokes.

## Global Constraints

- **Godot binary:** `C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe`. **Project root:** `C:/Users/dasbl/Documents/The Synaptic Sea`. Run smokes headless: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/<name>.gd 2>&1`.
- **Markers route to stderr** under headless Godot — always capture with `2>&1`. **Trust the PASS marker, never the exit code** (`--script` can exit 0 on parse errors). Confirm the marker line is present AND no unexpected `ERROR:`/`WARNING:` appears.
- **Allowlisted baseline noise (ignore):** `ERROR: Capture not registered: 'gdaimcp'.` and `WARNING: ObjectDB instances leaked at exit`. **`resources still in use at exit` is a real leak (hard fail).**
- **Local `project.godot` drift:** single-smoke runs emit environmental `Unrecognized UID` / `Resource file not found: res://` / `Failed to instantiate an autoload 'MCPRuntime'` errors — these are local drift, NOT failures. For the **full regression bundle and Gate-1**, `git stash push -- project.godot` first, pop after. Do NOT revert or commit the drift.
- **Never stage/commit** `project.godot`, `.godot/`, `*.uid`, or `addons/`. Use selective `git add <explicit paths>` only.
- **Conventional Commits**, every commit message ends with the trailer:
  `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`
- **Typed GDScript** for new systems. **Headless class-cache portability:** new `RefCounted`/`Resource` classes that get reconstructed from data use a `static func create(...)` / `load()` self-reference factory, never `ClassName.new()` from another class under `--script` (mirrors `ShipInstance.create`). A `RefCounted` nil check is `== null` (not `is_instance_valid`).
- **Soft cap is PLAYER-only.** Only the player `InventoryState` goes soft-cap (accept over weight). `ShipInventory` (ship holds and cart holds) stays **hard-capped** — a hold/cart can refuse on its own weight cap.
- **Worn ≠ carried.** Equipping moves an item OUT of `InventoryState` into an `EquipmentState` slot (so its own weight stops counting); unequip returns it to `InventoryState`. A worn container adds its `container_capacity` to the player's effective carry budget.
- **Heavy Load = movement only** this slice (no player endurance/health model exists). Endurance/damage are deferred.
- **No save-version bump** (`WORLD_SLICE_VERSION` stays `"world-4"`): equipment + carts are additive/tolerant.
- **Validation is the definition of done.** Each new system: pure-model smoke (+ main-scene smoke where scene consequences exist), registered in `docs/game/06_validation_plan.md`. Final state: full regression bundle green + Gate-1 `GO 2.00`.

---

## File Structure

New files:
- `data/items/equipment_definitions.json` — worn-equipment item defs (merged like tools).
- `scripts/systems/equipment_state.gd` — worn-equipment model (pure).
- `scripts/systems/encumbrance.gd` — pure-static load-ratio → move-speed multiplier.
- `scripts/systems/cart_state.gd` — mobile-container model (pure).
- `scripts/tools/cart_control.gd` — walk-up `Area3D` cart sensor.
- `scripts/validation/equipment_defs_smoke.gd` — equipment-def readers smoke.
- `scripts/validation/equipment_state_smoke.gd` — `EquipmentState` model smoke.
- `scripts/validation/encumbrance_smoke.gd` — `Encumbrance` curve smoke.
- `scripts/validation/cart_state_smoke.gd` — `CartState` model smoke.
- `scripts/validation/equipment_carts_smoke.gd` — main-scene equip + encumbrance + cart + persistence smoke.
- `docs/game/adr/0021-equipment-carts.md` — ADR.

Modified files:
- `scripts/systems/item_defs.gd` — equipment metadata readers + merge equipment defs.
- `scripts/systems/inventory_state.gd` — soft-cap rework + capacity/load queries.
- `scripts/systems/world_snapshot.gd` — `player_equipment` field.
- `scripts/systems/ship_instance.gd` — lazy `carts` array + persistence.
- `scripts/procgen/playable_generated_ship.gd` — equipment ownership, auto-equip, encumbrance recompute, cart spawn/handlers/teardown, persistence, seams.
- `scripts/validation/inventory_state_smoke.gd`, `scripts/validation/item_inventory_smoke.gd` — soft-cap assertions.
- `scripts/validation/cargo_transfer_smoke.gd`, `scripts/validation/cargo_hold_smoke.gd` — re-validate under player soft-cap.
- `scripts/validation/world_snapshot_smoke.gd` — `player_equipment` round-trip.
- `scripts/validation/ship_instance_smoke.gd` — carts round-trip.
- `docs/game/06_validation_plan.md` — register new smokes (104 → 109).
- `docs/game/09_system_roadmap.md` — System 6 status (~60% → ~80%).

**Delivery note:** Tasks 1–7 are the *equipment + encumbrance* group; Tasks 8–11 are the *carts* group; Task 12 is docs. The two groups are independently testable and MAY ship as two PRs (decided at finishing). Build in order regardless.

---

## Task 1: `ItemDefs` equipment metadata + equipment defs JSON

**Files:**
- Create: `data/items/equipment_definitions.json`
- Create: `scripts/validation/equipment_defs_smoke.gd`
- Modify: `scripts/systems/item_defs.gd`

**Interfaces:**
- Consumes: existing `ItemDefs.load_definitions()`.
- Produces: `ItemDefs.equip_slot(defs: Dictionary, item_id: String) -> String` (`""` if not equippable), `ItemDefs.container_capacity(defs: Dictionary, item_id: String) -> float` (`0.0` if none), `ItemDefs.effects(defs: Dictionary, item_id: String) -> Array` (`[]` if none). New equipment ids: `eva_backpack`, `field_pack`, `tool_belt`, `hardsuit`.

- [ ] **Step 1: Create the equipment defs JSON.**

Create `data/items/equipment_definitions.json`:
```json
{
  "eva_backpack": {
    "display_name": "EVA Backpack",
    "category": "equipment",
    "weight": 3.0,
    "max_stack": 1,
    "equip_slot": "back",
    "container_capacity": 40.0
  },
  "field_pack": {
    "display_name": "Field Pack",
    "category": "equipment",
    "weight": 1.5,
    "max_stack": 1,
    "equip_slot": "back",
    "container_capacity": 15.0
  },
  "tool_belt": {
    "display_name": "Tool Belt",
    "category": "equipment",
    "weight": 1.0,
    "max_stack": 1,
    "equip_slot": "waist",
    "container_capacity": 12.0
  },
  "hardsuit": {
    "display_name": "Salvage Hardsuit",
    "category": "equipment",
    "weight": 6.0,
    "max_stack": 1,
    "equip_slot": "suit",
    "effects": [{ "type": "oxygen_drain", "value": 0.75 }]
  }
}
```

- [ ] **Step 2: Merge equipment defs + add the readers in `ItemDefs`.**

In `scripts/systems/item_defs.gd`:

Add the path const next to the others (after `TOOL_DEFINITIONS_PATH`):
```gdscript
const EQUIPMENT_DEFINITIONS_PATH: String = "res://data/items/equipment_definitions.json"
```

In `load_definitions()`, add — immediately after the `item_defs` merge loop, before `return defs`:
```gdscript
	var equip_defs: Dictionary = _read_json_dict(EQUIPMENT_DEFINITIONS_PATH)
	for equip_id in equip_defs:
		var raw_equip: Variant = equip_defs[equip_id]
		if not (raw_equip is Dictionary):
			continue   # skip malformed entries rather than crash
		defs[equip_id] = raw_equip
```

Add the three readers after `display_name(...)`:
```gdscript
static func equip_slot(defs: Dictionary, item_id: String) -> String:
	return str(get_definition(defs, item_id).get("equip_slot", ""))

static func container_capacity(defs: Dictionary, item_id: String) -> float:
	return float(get_definition(defs, item_id).get("container_capacity", 0.0))

static func effects(defs: Dictionary, item_id: String) -> Array:
	var e: Variant = get_definition(defs, item_id).get("effects", [])
	return e if e is Array else []
```

- [ ] **Step 3: Write the failing readers smoke.**

Create `scripts/validation/equipment_defs_smoke.gd`:
```gdscript
extends SceneTree

## ItemDefs equipment-metadata smoke: the new equipment defs load and the
## equip_slot / container_capacity / effects readers return the declared values;
## non-equippable items report empty/zero (the readers never crash on plain items).

const ItemDefsScript := preload("res://scripts/systems/item_defs.gd")

func _init() -> void:
	var defs: Dictionary = ItemDefsScript.load_definitions()
	assert(defs.has("eva_backpack"), "equipment defs merged into the catalog")

	assert(ItemDefsScript.equip_slot(defs, "eva_backpack") == "back", "backpack -> back slot")
	assert(ItemDefsScript.equip_slot(defs, "tool_belt") == "waist", "tool_belt -> waist slot")
	assert(ItemDefsScript.equip_slot(defs, "hardsuit") == "suit", "hardsuit -> suit slot")
	assert(ItemDefsScript.container_capacity(defs, "eva_backpack") == 40.0, "backpack capacity 40")
	assert(ItemDefsScript.container_capacity(defs, "tool_belt") == 12.0, "tool_belt capacity 12")
	assert(ItemDefsScript.container_capacity(defs, "hardsuit") == 0.0, "suit is not a container")

	var fx: Array = ItemDefsScript.effects(defs, "hardsuit")
	assert(fx.size() == 1 and str(fx[0].get("type", "")) == "oxygen_drain", "suit carries an oxygen_drain effect")
	assert(float(fx[0].get("value", 1.0)) == 0.75, "suit oxygen_drain value 0.75")

	# Non-equippable real item (scrap_metal: part) -> empty/zero, no crash.
	assert(ItemDefsScript.equip_slot(defs, "scrap_metal") == "", "plain item has no slot")
	assert(ItemDefsScript.container_capacity(defs, "scrap_metal") == 0.0, "plain item not a container")
	assert(ItemDefsScript.effects(defs, "scrap_metal").is_empty(), "plain item has no effects")

	print("EQUIPMENT DEFS SMOKE PASS slots=3 effects=1")
	quit()
```

- [ ] **Step 4: Run the smoke — verify it passes.**

Run:
```bash
GODOT="C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe"
ROOT="C:/Users/dasbl/Documents/The Synaptic Sea"
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/equipment_defs_smoke.gd 2>&1
```
Expected: PASS — `EQUIPMENT DEFS SMOKE PASS slots=3 effects=1`. Also re-run `inventory_state_smoke.gd` once to confirm the extra merge did not disturb existing lookups (its marker still prints).

- [ ] **Step 5: Commit.**

```bash
git add data/items/equipment_definitions.json scripts/systems/item_defs.gd scripts/validation/equipment_defs_smoke.gd
git commit -m "feat(equipment): ItemDefs equipment metadata readers + equipment defs

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: `EquipmentState` model + smoke

**Files:**
- Create: `scripts/systems/equipment_state.gd`
- Create: `scripts/validation/equipment_state_smoke.gd`

**Interfaces:**
- Consumes: `ItemDefs` (Task 1).
- Produces: `EquipmentState.create() -> EquipmentState`; const `EquipmentState.SLOTS := ["suit","back","waist","primary_hand","secondary_hand"]`; `can_equip(item_id: String) -> bool`, `equip(item_id: String) -> Dictionary` (`{ok: bool, displaced: String}`), `unequip(slot: String) -> String`, `get_equipped(slot: String) -> String`, `is_slot_occupied(slot: String) -> bool`, `get_carry_capacity_bonus() -> float`, `get_oxygen_drain_multiplier() -> float`, `get_summary() -> Dictionary`, `apply_summary(summary) -> bool`; field `var slots: Dictionary`.

- [ ] **Step 1: Write the failing smoke.**

Create `scripts/validation/equipment_state_smoke.gd`:
```gdscript
extends SceneTree

## EquipmentState pure-model smoke: equip/unequip, slot validation, displacement,
## capacity-bonus + oxygen-multiplier aggregation, summary round-trip.

const EquipmentStateScript := preload("res://scripts/systems/equipment_state.gd")

func _init() -> void:
	var eq = EquipmentStateScript.create()
	assert(eq.get_carry_capacity_bonus() == 0.0, "empty -> no capacity bonus")
	assert(eq.get_oxygen_drain_multiplier() == 1.0, "empty -> neutral oxygen multiplier")

	# Non-equippable item refused.
	assert(eq.can_equip("scrap_metal") == false, "plain item cannot equip")
	assert(eq.equip("scrap_metal").get("ok") == false, "equip of plain item fails")

	# Equip a backpack on the back slot.
	var r1: Dictionary = eq.equip("eva_backpack")
	assert(r1.get("ok") == true and str(r1.get("displaced")) == "", "backpack equipped, nothing displaced")
	assert(eq.get_equipped("back") == "eva_backpack", "back slot holds the backpack")
	assert(eq.is_slot_occupied("back"), "back slot occupied")
	assert(eq.get_carry_capacity_bonus() == 40.0, "backpack adds 40 capacity")

	# Equip a waist pack -> stacks the bonus.
	eq.equip("tool_belt")
	assert(eq.get_carry_capacity_bonus() == 52.0, "backpack + tool_belt = 52 (got %s)" % str(eq.get_carry_capacity_bonus()))

	# Equip a suit -> oxygen multiplier.
	eq.equip("hardsuit")
	assert(eq.get_oxygen_drain_multiplier() == 0.75, "hardsuit drain multiplier 0.75")

	# Displacement: a second back item displaces the backpack.
	var r2: Dictionary = eq.equip("field_pack")
	assert(r2.get("ok") == true and str(r2.get("displaced")) == "eva_backpack", "field_pack displaced the backpack")
	assert(eq.get_equipped("back") == "field_pack", "back slot now holds field_pack")
	assert(eq.get_carry_capacity_bonus() == 27.0, "field_pack(15) + tool_belt(12) = 27 (got %s)" % str(eq.get_carry_capacity_bonus()))

	# Unequip returns the worn id and clears the slot.
	var removed: String = eq.unequip("waist")
	assert(removed == "tool_belt", "unequip waist returns tool_belt")
	assert(not eq.is_slot_occupied("waist"), "waist now empty")
	assert(eq.unequip("waist") == "", "unequip empty slot returns empty")

	# Round-trip.
	var summary: Dictionary = eq.get_summary()
	var clone = EquipmentStateScript.create()
	assert(clone.apply_summary(summary) == true, "apply_summary accepts")
	assert(clone.get_equipped("back") == "field_pack", "worn items round-tripped")
	assert(clone.get_oxygen_drain_multiplier() == 0.75, "suit effect round-tripped")
	assert(EquipmentStateScript.create().apply_summary({}) == false, "empty summary rejected")

	print("EQUIPMENT STATE SMOKE PASS bonus=%s oxy=%s" % [str(clone.get_carry_capacity_bonus()), str(clone.get_oxygen_drain_multiplier())])
	quit()
```

- [ ] **Step 2: Run the smoke to verify it fails.**

Run:
```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/equipment_state_smoke.gd 2>&1
```
Expected: FAIL — `equipment_state.gd` does not exist (no `EQUIPMENT STATE SMOKE PASS`).

- [ ] **Step 3: Implement `EquipmentState`.**

Create `scripts/systems/equipment_state.gd`:
```gdscript
extends RefCounted
class_name EquipmentState

## The player's worn equipment, keyed by body-location slot (one item per slot).
## Pure model; never touches the scene tree. Worn containers raise carry capacity;
## a suit modifies the oxygen drain. Constructed via the load()-self-reference
## factory so it resolves under --headless --script (class_name globals unreliable
## there; mirrors ShipInstance.create). Round-trips via get_summary/apply_summary.

const ItemDefsScript := preload("res://scripts/systems/item_defs.gd")

const SLOTS: Array = ["suit", "back", "waist", "primary_hand", "secondary_hand"]

var slots: Dictionary = {}          # slot_id: String -> item_id: String (absent = empty)
var _defs: Dictionary = {}

func _init() -> void:
	_defs = ItemDefsScript.load_definitions()

static func create() -> EquipmentState:
	var script: GDScript = load("res://scripts/systems/equipment_state.gd")
	return script.new()

## True iff the item declares a slot in SLOTS.
func can_equip(item_id: String) -> bool:
	var slot: String = ItemDefsScript.equip_slot(_defs, item_id)
	return slot in SLOTS

## Equips item_id into its declared slot, displacing whatever was there.
## Returns { "ok": bool, "displaced": String } (displaced "" if the slot was empty
## or on failure).
func equip(item_id: String) -> Dictionary:
	if not can_equip(item_id):
		return {"ok": false, "displaced": ""}
	var slot: String = ItemDefsScript.equip_slot(_defs, item_id)
	var displaced: String = str(slots.get(slot, ""))
	slots[slot] = item_id
	return {"ok": true, "displaced": displaced}

## Removes and returns the item in `slot` ("" if empty).
func unequip(slot: String) -> String:
	var item_id: String = str(slots.get(slot, ""))
	if item_id != "":
		slots.erase(slot)
	return item_id

func get_equipped(slot: String) -> String:
	return str(slots.get(slot, ""))

func is_slot_occupied(slot: String) -> bool:
	return slots.has(slot) and str(slots[slot]) != ""

## Sum of container_capacity across all worn containers.
func get_carry_capacity_bonus() -> float:
	var bonus: float = 0.0
	for slot in slots:
		bonus += ItemDefsScript.container_capacity(_defs, str(slots[slot]))
	return bonus

## Product of all worn 'oxygen_drain' effect values (default 1.0 = neutral).
func get_oxygen_drain_multiplier() -> float:
	var mult: float = 1.0
	for slot in slots:
		for fx in ItemDefsScript.effects(_defs, str(slots[slot])):
			if fx is Dictionary and str(fx.get("type", "")) == "oxygen_drain":
				mult *= float(fx.get("value", 1.0))
	return mult

func get_summary() -> Dictionary:
	return {"slots": slots.duplicate(true)}

func apply_summary(summary) -> bool:
	if typeof(summary) != TYPE_DICTIONARY or (summary as Dictionary).is_empty():
		return false
	slots.clear()
	var slots_variant: Variant = (summary as Dictionary).get("slots", null)
	if typeof(slots_variant) == TYPE_DICTIONARY:
		for slot in (slots_variant as Dictionary):
			var item_id: String = str((slots_variant as Dictionary)[slot])
			if String(slot) in SLOTS and item_id != "":
				slots[String(slot)] = item_id
	return true
```

- [ ] **Step 4: Run the smoke to verify it passes.**

Run:
```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/equipment_state_smoke.gd 2>&1
```
Expected: PASS — `EQUIPMENT STATE SMOKE PASS bonus=27 oxy=0.75`.

- [ ] **Step 5: Commit.**

```bash
git add scripts/systems/equipment_state.gd scripts/validation/equipment_state_smoke.gd
git commit -m "feat(equipment): EquipmentState worn-slot model + smoke

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: `InventoryState` soft-cap rework + existing-smoke updates

**Files:**
- Modify: `scripts/systems/inventory_state.gd`
- Modify: `scripts/validation/inventory_state_smoke.gd`, `scripts/validation/item_inventory_smoke.gd`

**Interfaces:**
- Produces: `InventoryState.bonus_capacity: float` (default 0.0), `get_capacity() -> float`, `get_load_ratio() -> float`, `is_over_capacity() -> bool`. `add_item` no longer refuses on weight (still honors `max_stack`). `get_max_weight()` still returns the **base** const (50.0).

- [ ] **Step 1: Rework `add_item` to soft-cap + add capacity/load queries.**

In `scripts/systems/inventory_state.gd`:

Add the field next to `var items: Dictionary = {}`:
```gdscript
var bonus_capacity: float = 0.0     # added by worn containers (set by the coordinator)
```

Replace the `add_item` body (the weight-gating block) so weight no longer limits — accept up to `max_stack` only:
```gdscript
## Adds up to qty, honoring max_stack ONLY. Weight does NOT gate (PZ soft-cap):
## the player may carry over capacity and suffer a Heavy Load movement penalty.
## Returns the quantity actually added (0 if the stack is full).
func add_item(item_id: String, qty: int) -> int:
	if item_id.is_empty() or qty <= 0:
		return 0
	var current: int = get_quantity(item_id)
	var stack_room: int = max(0, _max_stack(item_id) - current)
	var want: int = min(qty, stack_room)
	if want <= 0:
		return 0
	items[item_id] = current + want
	return want
```

Add the capacity/load queries after `get_max_weight()`:
```gdscript
## Effective carry budget = base cap + worn-container bonus (+ future strength).
func get_capacity() -> float:
	return MAX_WEIGHT + bonus_capacity

## total_weight / capacity. >1.0 means over-encumbered (Heavy Load).
func get_load_ratio() -> float:
	return get_total_weight() / max(0.0001, get_capacity())

func is_over_capacity() -> bool:
	return get_total_weight() > get_capacity()
```

In `get_status_lines()`, change the weight readout line to report the effective capacity (not the bare base const):
```gdscript
	lines.append("weight=%s/%s" % [str(snappedf(get_total_weight(), 0.1)), str(snappedf(get_capacity(), 0.1))])
```

- [ ] **Step 2: Update the existing inventory smokes for soft-cap.**

Read `scripts/validation/inventory_state_smoke.gd` and `scripts/validation/item_inventory_smoke.gd` first. Any assertion that `add_item` REFUSES (returns a partial count or 0) once over the **weight** cap must be replaced — `add_item` now only caps on `max_stack`. Specifically:
- If a smoke asserts "weight cap limited the add" for the **player** inventory, change it to assert the full stack-limited amount is accepted and that `is_over_capacity()` is then true and `get_load_ratio() > 1.0`.
- Keep markers identical (the marker contract is unchanged); only the intermediate assertions change.

Append to `inventory_state_smoke.gd` (before its final `print(... PASS ...)`/`quit()`), a positive soft-cap assertion:
```gdscript
	# --- PZ soft-cap (slice 2): weight never refuses; capacity/load queries ---
	var sc = InventoryStateScript.new()   # use the smoke's existing preload const name
	sc.add_item("scrap_metal", 20)        # 20 * 5.0 = 100.0 weight, base cap 50.0
	assert(sc.get_quantity("scrap_metal") == 20, "soft-cap accepted a full stack over weight")
	assert(sc.is_over_capacity(), "over capacity after overload")
	assert(sc.get_load_ratio() > 1.0, "load ratio > 1 when overloaded")
	sc.bonus_capacity = 60.0              # a worn container raises the budget
	assert(not sc.is_over_capacity(), "container bonus lifts player back under capacity")
```
Use the smoke's existing `InventoryState` preload constant name in place of `InventoryStateScript`. If `item_inventory_smoke.gd` has no weight-refusal assertion, leave it unchanged (just confirm its marker still prints in Step 3).

- [ ] **Step 3: Run both smokes — verify their markers still print.**

Run:
```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/inventory_state_smoke.gd 2>&1
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/item_inventory_smoke.gd 2>&1
```
Expected: both PASS markers print; the new soft-cap assertions pass. No unexpected errors.

- [ ] **Step 4: Commit.**

```bash
git add scripts/systems/inventory_state.gd scripts/validation/inventory_state_smoke.gd scripts/validation/item_inventory_smoke.gd
git commit -m "feat(equipment): InventoryState PZ soft-cap + capacity/load queries

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: Re-validate `CargoTransfer` cargo smokes under player soft-cap

**Files:**
- Modify: `scripts/validation/cargo_transfer_smoke.gd`, `scripts/validation/cargo_hold_smoke.gd`

**Interfaces:** none changed. `CargoTransfer` logic is conservation-based and needs **no code change** — only the smokes' cap-limited expectations change, because the player now accepts over its weight cap.

- [ ] **Step 1: Update `cargo_transfer_smoke.gd` withdraw expectations.**

Read `scripts/validation/cargo_transfer_smoke.gd`. The withdraw section previously asserted the player carry cap **partial-filled** the withdraw (player `get_total_weight() <= get_max_weight()`). Under soft-cap the player accepts the whole category. Replace the withdraw assertions so they assert:
- conservation still holds (`player.get_quantity(id) + hold.get_quantity(id) == pre_player + pre_hold`),
- the withdraw moved the **entire** available hold quantity for the category (no cap-limited partial),
- the player may now be over capacity (`player.is_over_capacity()` may be true — assert `get_load_ratio()` is defined, not the old `<= max_weight`).

Concretely, replace the old `assert(player.get_total_weight() <= player.get_max_weight() + 0.0001, ...)` line with:
```gdscript
	# Player soft-cap: withdraw is NOT limited by the player's weight cap; it pulls
	# the whole category and the player may end over capacity (Heavy Load).
	assert(hold.get_quantity(PART_ITEM) == 0, "withdraw pulled the whole part stock from the hold")
	assert(moved == pre_hold, "withdrew the full hold quantity (got %d of %d)" % [moved, pre_hold])
```
Keep the existing conservation assertion and the `CARGO TRANSFER SMOKE PASS ...` marker unchanged.

- [ ] **Step 2: Update `cargo_hold_smoke.gd` Section B withdraw expectation.**

Read `scripts/validation/cargo_hold_smoke.gd`. In Section B, the withdraw step asserts `withdrew >= 1`. That still holds, but make it precise for soft-cap: after depositing 6 `scrap_metal`, `withdraw_category(home_id, "part")` now returns all 6 (player accepts over cap). Change:
```gdscript
	var withdrew: int = ship.cargo_withdraw_for_validation(home_id, "part")
	assert(withdrew == 6, "withdrew all 6 under player soft-cap (got %d)" % withdrew)
```
The marker `CARGO HOLD SMOKE PASS section_a=true deposited=6 withdrew=6 persisted=...` is unchanged (still `withdrew=6`).

- [ ] **Step 3: Run both cargo smokes — verify markers.**

Run:
```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/cargo_transfer_smoke.gd 2>&1
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/cargo_hold_smoke.gd 2>&1
```
Expected: both PASS markers print with the new soft-cap assertions. `CARGO HOLD SMOKE PASS section_a=true deposited=6 withdrew=6 persisted=true`.

- [ ] **Step 4: Commit.**

```bash
git add scripts/validation/cargo_transfer_smoke.gd scripts/validation/cargo_hold_smoke.gd
git commit -m "test(cargo): re-validate cargo transfer/hold smokes under player soft-cap

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 5: `Encumbrance` curve + smoke

**Files:**
- Create: `scripts/systems/encumbrance.gd`
- Create: `scripts/validation/encumbrance_smoke.gd`

**Interfaces:**
- Produces: `Encumbrance.move_speed_multiplier(load_ratio: float) -> float` (all-static). Monotonic non-increasing; `1.0` at/below `load_ratio == 1.0`; floor `0.25`.

- [ ] **Step 1: Write the failing smoke.**

Create `scripts/validation/encumbrance_smoke.gd`:
```gdscript
extends SceneTree

## Encumbrance curve smoke: PZ-tiered move-speed multiplier. 1.0 at/under capacity,
## monotonic non-increasing above it, clamped floor 0.25.

const EncumbranceScript := preload("res://scripts/systems/encumbrance.gd")

func _approx(a: float, b: float) -> bool:
	return absf(a - b) <= 0.01

func _init() -> void:
	assert(EncumbranceScript.move_speed_multiplier(0.0) == 1.0, "empty -> full speed")
	assert(EncumbranceScript.move_speed_multiplier(0.5) == 1.0, "half load -> full speed")
	assert(EncumbranceScript.move_speed_multiplier(1.0) == 1.0, "at capacity -> full speed")
	assert(_approx(EncumbranceScript.move_speed_multiplier(1.25), 0.63), "125% -> ~0.63 (PZ)")
	assert(_approx(EncumbranceScript.move_speed_multiplier(1.75), 0.25), "175% -> ~0.25 (PZ)")
	assert(EncumbranceScript.move_speed_multiplier(3.0) == 0.25, "far over -> floor 0.25")
	assert(EncumbranceScript.move_speed_multiplier(-1.0) == 1.0, "negative ratio clamps to full")

	# Monotonic non-increasing across a sweep.
	var prev: float = 2.0
	for i in range(0, 31):
		var r: float = float(i) * 0.1   # 0.0 .. 3.0
		var m: float = EncumbranceScript.move_speed_multiplier(r)
		assert(m <= prev + 0.0001, "monotonic non-increasing at r=%s" % str(r))
		prev = m

	print("EQUIPMENT ENCUMBRANCE SMOKE PASS floor=0.25")
	quit()
```

- [ ] **Step 2: Run to verify it fails.**

Run:
```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/encumbrance_smoke.gd 2>&1
```
Expected: FAIL — `encumbrance.gd` does not exist.

- [ ] **Step 3: Implement `Encumbrance`.**

Create `scripts/systems/encumbrance.gd`:
```gdscript
extends RefCounted
class_name Encumbrance

## Pure-static Heavy Load curve. Maps an inventory load-ratio (total_weight /
## capacity) to a movement-speed multiplier, modeled on Project Zomboid's Heavy
## Load tiers: no penalty at/under capacity; ~37% slower at 125%; ~75% slower at
## 175%; clamped to a 0.25 floor beyond. (PZ's endurance/health effects are
## deferred — no player-condition model yet.)

const FLOOR_MULTIPLIER: float = 0.25
const MULT_AT_125: float = 0.63

static func move_speed_multiplier(load_ratio: float) -> float:
	if load_ratio <= 1.0:
		return 1.0
	if load_ratio <= 1.25:
		return lerpf(1.0, MULT_AT_125, (load_ratio - 1.0) / 0.25)
	if load_ratio <= 1.75:
		return lerpf(MULT_AT_125, FLOOR_MULTIPLIER, (load_ratio - 1.25) / 0.50)
	return FLOOR_MULTIPLIER
```

- [ ] **Step 4: Run to verify it passes.**

Run:
```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/encumbrance_smoke.gd 2>&1
```
Expected: PASS — `EQUIPMENT ENCUMBRANCE SMOKE PASS floor=0.25`.

- [ ] **Step 5: Commit.**

```bash
git add scripts/systems/encumbrance.gd scripts/validation/encumbrance_smoke.gd
git commit -m "feat(equipment): Encumbrance Heavy Load curve + smoke

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 6: `WorldSnapshot.player_equipment` field

**Files:**
- Modify: `scripts/systems/world_snapshot.gd`
- Modify: `scripts/validation/world_snapshot_smoke.gd`

**Interfaces:**
- Produces: `WorldSnapshot.player_equipment: Dictionary` (default `{}`), round-tripped through `to_dict()`/`from_dict()`. `WORLD_SLICE_VERSION` stays `"world-4"`.

- [ ] **Step 1: Add the field + serialization.**

In `scripts/systems/world_snapshot.gd`:

Add the field next to `home_ship_inventory`:
```gdscript
var player_equipment: Dictionary = {}           # EquipmentState.get_summary()
```

In `to_dict()`, add after the `"home_ship_inventory": ...` line:
```gdscript
		"player_equipment": player_equipment.duplicate(true),
```

In `from_dict()`, add after the `ws.home_ship_inventory = ...` reconstruction line:
```gdscript
	ws.player_equipment = _deep_copy_dict(dict.get("player_equipment", {}))
```
(`_deep_copy_dict` returns `{}` for non-dicts — tolerant of old saves.)

**Do NOT change `WORLD_SLICE_VERSION`.**

- [ ] **Step 2: Add a round-trip assertion to `world_snapshot_smoke.gd`.**

Read the file for its WorldSnapshot preload const + version locals. Append before its final `print(... PASS ...)`/`quit()`:
```gdscript
	# --- player_equipment round-trip (slice 2, additive, no version bump) ---
	var ws_eq = WorldSnapshotScript.new()
	ws_eq.slice_version = expected_world_version       # reuse the smoke's version locals
	ws_eq.godot_version = expected_godot_version
	ws_eq.player_equipment = {"slots": {"back": "eva_backpack", "suit": "hardsuit"}}
	var rt_eq = WorldSnapshotScript.from_dict(ws_eq.to_dict(), expected_world_version, expected_godot_version)
	assert(rt_eq != null, "equipment snapshot round-trips")
	assert(str(rt_eq.player_equipment.get("slots", {}).get("back", "")) == "eva_backpack", "player_equipment survived round-trip")
```
Use the smoke's actual preload const + version local names. If absent, derive: `var expected_world_version := WorldSnapshotScript.WORLD_SLICE_VERSION` and `var expected_godot_version := Engine.get_version_info()["string"]`.

- [ ] **Step 3: Run the smoke — verify its marker.**

Run:
```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/world_snapshot_smoke.gd 2>&1
```
Expected: PASS — existing marker prints, new assertion passes.

- [ ] **Step 4: Commit.**

```bash
git add scripts/systems/world_snapshot.gd scripts/validation/world_snapshot_smoke.gd
git commit -m "feat(equipment): WorldSnapshot.player_equipment field (additive, no version bump)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 7: Coordinator equipment wiring + encumbrance + persistence + main-scene Section A

**Files:**
- Modify: `scripts/procgen/playable_generated_ship.gd`
- Create: `scripts/validation/equipment_carts_smoke.gd` (Section A here; Task 11 appends Section B)

**Interfaces:**
- Consumes: `EquipmentState` (T2), `Encumbrance` (T5), `ItemDefs` (T1), `WorldSnapshot.player_equipment` (T6). Existing: `inventory_state` (field ~200, created ~921), `player` (~106), `_on_loot_container_searched` (~1969, grants via `inventory_state.add_item` ~1998), save assembly (~4023), load (~4180).
- Produces (seams): `equip_for_validation(item_id: String) -> bool`, `unequip_for_validation(slot: String) -> String`, `player_capacity_for_validation() -> float`, `player_equipped_for_validation(slot: String) -> String`, `player_move_speed_for_validation() -> float`, `overload_player_for_validation(item_id: String, qty: int) -> void`.

**Context:** `playable_generated_ship.gd` is the ~4400-line coordinator. `player` is a `PlayerController` with a `move_speed` var and a `DEFAULT_MOVE_SPEED` const (default 6.0; access via `player.DEFAULT_MOVE_SPEED`). The player inventory model is `inventory_state`. Equipment is owned here (single ownership), created beside `inventory_state`.

- [ ] **Step 1: Add the equipment field, preloads, ownership, helpers, and seams.**

Add preloads near the other system preloads:
```gdscript
const EquipmentStateScript := preload("res://scripts/systems/equipment_state.gd")
const EncumbranceScript := preload("res://scripts/systems/encumbrance.gd")
const ItemDefsScript := preload("res://scripts/systems/item_defs.gd")
```
(If `ItemDefs` is already preloaded under another const in this file, reuse that const name instead of adding a duplicate.)

Add the field next to `var inventory_state: InventoryState` (~200):
```gdscript
var equipment_state                  # EquipmentState (untyped: class_name unreliable headless)
```

Where `inventory_state` is created (~921), add immediately after:
```gdscript
	equipment_state = EquipmentStateScript.create()
```

Add the equipment + encumbrance helpers (place near the cargo handlers ~1530):
```gdscript
## Recompute the player's effective carry budget from worn equipment and apply the
## Heavy Load movement penalty (× any active cart push penalty). Called on every
## inventory/equipment/cart change.
func _recompute_player_encumbrance() -> void:
	if inventory_state == null:
		return
	var bonus: float = 0.0
	if equipment_state != null:
		bonus = equipment_state.get_carry_capacity_bonus()   # + future strength bonus
	inventory_state.bonus_capacity = bonus
	if player != null:
		var mult: float = EncumbranceScript.move_speed_multiplier(inventory_state.get_load_ratio())
		player.move_speed = float(player.DEFAULT_MOVE_SPEED) * mult * _cart_push_multiplier()

## Equip item_id from the player inventory into its slot. Honors the both-hands
## cart block. `auto` (pickup path) only fills EMPTY slots; manual equip displaces
## the worn item back into inventory. Returns true on success.
func _equip_from_inventory(item_id: String, auto: bool) -> bool:
	if equipment_state == null or inventory_state == null:
		return false
	if not equipment_state.can_equip(item_id):
		return false
	var slot: String = ItemDefsScript.equip_slot(_definitions_for_equip(), item_id)
	if (slot == "primary_hand" or slot == "secondary_hand") and _is_cart_grabbed():
		return false   # both hands occupied by a grabbed cart
	if auto and equipment_state.is_slot_occupied(slot):
		return false   # auto-equip never swaps a filled slot
	if inventory_state.get_quantity(item_id) <= 0:
		return false
	inventory_state.remove_item(item_id, 1)
	var res: Dictionary = equipment_state.equip(item_id)
	if not bool(res.get("ok", false)):
		inventory_state.add_item(item_id, 1)   # equip failed -> put it back
		return false
	var displaced: String = str(res.get("displaced", ""))
	if displaced != "":
		inventory_state.add_item(displaced, 1)
	_recompute_player_encumbrance()
	return true

## Unequip a slot back into the player inventory. Returns the unequipped id ("" if empty).
func _unequip_to_inventory(slot: String) -> String:
	if equipment_state == null or inventory_state == null:
		return ""
	var item_id: String = equipment_state.unequip(slot)
	if item_id != "":
		inventory_state.add_item(item_id, 1)
		_recompute_player_encumbrance()
	return item_id

func _definitions_for_equip() -> Dictionary:
	# The merged item-def catalog. inventory_state already loaded it; reuse a fresh
	# static load (cheap, identical) to avoid reaching into inventory internals.
	return ItemDefsScript.load_definitions()
```

**Note on `_is_cart_grabbed()` / `_cart_push_multiplier()`:** these are introduced in Task 11 (carts). For Tasks 7–10, add **temporary stubs** so the equipment code compiles and runs standalone; Task 11 replaces them with the real cart-backed bodies:
```gdscript
func _is_cart_grabbed() -> bool:
	return false

func _cart_push_multiplier() -> float:
	return 1.0
```

Add the validation seams near the other `*_for_validation` functions (~4701):
```gdscript
func equip_for_validation(item_id: String) -> bool:
	# Seed one into inventory if absent so the seam can drive equip deterministically.
	if inventory_state != null and inventory_state.get_quantity(item_id) <= 0:
		inventory_state.add_item(item_id, 1)
	return _equip_from_inventory(item_id, false)

func unequip_for_validation(slot: String) -> String:
	return _unequip_to_inventory(slot)

func player_capacity_for_validation() -> float:
	return inventory_state.get_capacity() if inventory_state != null else 0.0

func player_equipped_for_validation(slot: String) -> String:
	return equipment_state.get_equipped(slot) if equipment_state != null else ""

func player_move_speed_for_validation() -> float:
	return float(player.move_speed) if player != null else 0.0

func overload_player_for_validation(item_id: String, qty: int) -> void:
	if inventory_state != null:
		inventory_state.add_item(item_id, qty)
	_recompute_player_encumbrance()
```

- [ ] **Step 2: Auto-equip containers on loot pickup, and recompute encumbrance after grants.**

At `_on_loot_container_searched` (~1969), after the grant loop that calls `inventory_state.add_item(...)` (~1998), add auto-equip of any granted equippable container into an empty slot, then recompute:
```gdscript
	# Auto-equip granted containers into empty slots (Phase-7 deferral: no equip UI yet).
	for entry in granted:
		var gid: String = str(entry.get("item_id", ""))
		if gid != "" and equipment_state != null and equipment_state.can_equip(gid):
			_equip_from_inventory(gid, true)
	_recompute_player_encumbrance()
```
(Keep the existing grant loop intact; this block runs after it.)

- [ ] **Step 3: Persist player equipment in the save/load assembly.**

In the save assembly (next to `ws.home_ship_inventory = ...`, ~4023), add:
```gdscript
	if equipment_state != null:
		ws.player_equipment = equipment_state.get_summary()
```
In the load path (next to the `home_ship.get_inventory().apply_summary(...)` block, ~4180), add (NOT inside the `if home_ship != null:` block — equipment is player-global):
```gdscript
	if equipment_state != null and not ws.player_equipment.is_empty():
		equipment_state.apply_summary(ws.player_equipment)
	_recompute_player_encumbrance()
```

- [ ] **Step 4: Create `equipment_carts_smoke.gd` with Section A (equip + encumbrance + persistence).**

Create `scripts/validation/equipment_carts_smoke.gd`:
```gdscript
extends SceneTree

## Equipment & carts main-scene smoke.
## Section A (Task 7): auto-equip raises capacity; overload drops move_speed via the
##   Heavy Load curve; equip/unequip move items between inventory and slots; player
##   equipment persists across an in-process save->load.
## Section B (Task 11): cart grab occupies both hands + push penalty; load/unload;
##   parked cart persists on its ship.

const PlayableGeneratedShipScript := preload("res://scripts/procgen/playable_generated_ship.gd")

func _init() -> void:
	await _run_section_a()
	# Section B is appended in Task 11; for now Section A alone prints the marker.
	print("EQUIPMENT CARTS SMOKE PASS section_a=true cap_bonus=40 slowed=true cart_loaded=0 persisted=true")
	quit()

func _run_section_a() -> void:
	var ship = PlayableGeneratedShipScript.new()
	root.add_child(ship)
	for _i in range(3):
		await process_frame

	# Auto-equip path via the manual seam (equips a backpack from inventory).
	var base_cap: float = ship.player_capacity_for_validation()
	assert(ship.equip_for_validation("eva_backpack") == true, "backpack equipped")
	assert(ship.player_equipped_for_validation("back") == "eva_backpack", "back slot holds backpack")
	assert(ship.player_capacity_for_validation() == base_cap + 40.0, "capacity rose by 40 (base=%s now=%s)" % [str(base_cap), str(ship.player_capacity_for_validation())])

	# Overload -> Heavy Load -> move_speed drops below the default.
	var default_speed: float = ship.player_move_speed_for_validation()
	ship.overload_player_for_validation("scrap_metal", 20)   # 100 weight vs ~90 cap -> over 100%
	var slowed_speed: float = ship.player_move_speed_for_validation()
	assert(slowed_speed < default_speed, "move_speed dropped under Heavy Load (%s -> %s)" % [str(default_speed), str(slowed_speed)])

	# Unequip returns the item to inventory and drops the capacity bonus.
	assert(ship.unequip_for_validation("back") == "eva_backpack", "unequip returns backpack")
	assert(ship.player_capacity_for_validation() == base_cap, "capacity back to base after unequip")

	# Re-equip, then persist equipment across save->load.
	ship.equip_for_validation("hardsuit")
	assert(ship.save_world_for_validation() == true, "world saved")
	assert(ship.load_world_for_validation() == true, "world loaded")
	for _j in range(3):
		await process_frame
	assert(ship.player_equipped_for_validation("suit") == "hardsuit", "suit persisted across save/load")
	ship.queue_free()
```
**Both sections MUST be awaited** in `_init` (each contains `await process_frame`; calling without `await` detaches the coroutine so its assertions never run before `quit()` — a real bug pattern caught in the cargo slice). Confirm `save_world_for_validation()` / `load_world_for_validation()` are the existing seam names (grep — they are used by `cargo_hold_smoke.gd` Section B); if named differently use the actual names.

- [ ] **Step 5: Run the smoke — verify Section A.**

Run:
```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/equipment_carts_smoke.gd 2>&1
```
Expected: PASS — `EQUIPMENT CARTS SMOKE PASS section_a=true ...`. Investigate any assertion failure before proceeding.

- [ ] **Step 6: Commit.**

```bash
git add scripts/procgen/playable_generated_ship.gd scripts/validation/equipment_carts_smoke.gd
git commit -m "feat(equipment): coordinator equipment ownership, auto-equip, encumbrance + Section A smoke

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 8: `CartState` model + smoke

**Files:**
- Create: `scripts/systems/cart_state.gd`
- Create: `scripts/validation/cart_state_smoke.gd`

**Interfaces:**
- Consumes: `ShipInventory` (cargo slice), `CargoTransfer` (cargo slice), `InventoryState`.
- Produces: `CartState.create(p_cart_id: String, p_max_weight := 200.0) -> CartState`; fields `cart_id: String`, `parked_ship_id: String`, `parked_position: Vector3`, `push_speed_multiplier: float` (default 0.7); `get_hold() -> ShipInventory`, `get_summary() -> Dictionary`, `apply_summary(summary) -> bool`.

- [ ] **Step 1: Write the failing smoke.**

Create `scripts/validation/cart_state_smoke.gd`:
```gdscript
extends SceneTree

## CartState pure-model smoke: a mobile container whose contents are moved via the
## same CargoTransfer flow as a ship hold, and which round-trips through
## get_summary/apply_summary. Contents live in the cart's own hold — never in the
## player inventory — so they are off personal encumbrance by construction.

const CartStateScript := preload("res://scripts/systems/cart_state.gd")
const InventoryStateScript := preload("res://scripts/systems/inventory_state.gd")
const CargoTransferScript := preload("res://scripts/systems/cargo_transfer.gd")

func _init() -> void:
	var cart = CartStateScript.create("cart_1", 200.0)
	assert(cart.cart_id == "cart_1", "cart id set")
	assert(cart.push_speed_multiplier == 0.7, "default push multiplier 0.7")
	assert(cart.get_hold().get_max_weight() == 200.0, "cart hold cap set")

	# Load from a player inventory via CargoTransfer (deposit into the cart hold).
	var player = InventoryStateScript.new()
	player.add_item("scrap_metal", 6)       # part
	var dep: Dictionary = CargoTransferScript.deposit_all(player, cart.get_hold())
	assert(int(dep.get("total_moved", 0)) == 6, "loaded 6 into the cart")
	assert(player.get_quantity("scrap_metal") == 0, "items left the player (off personal encumbrance)")
	assert(cart.get_hold().get_quantity("scrap_metal") == 6, "cart holds the salvage")

	# Unload back to the player.
	var wd: Dictionary = CargoTransferScript.withdraw_category(cart.get_hold(), player, "part")
	assert(int(wd.get("total_moved", 0)) == 6, "unloaded 6 back to the player")

	# Park metadata + round-trip.
	cart.parked_ship_id = "home"
	cart.parked_position = Vector3(2, 0, 3)
	cart.get_hold().add_item("scrap_metal", 4)
	var summary: Dictionary = cart.get_summary()
	var clone = CartStateScript.create("x", 1.0)
	assert(clone.apply_summary(summary) == true, "apply_summary accepts")
	assert(clone.cart_id == "cart_1", "cart_id round-tripped")
	assert(clone.parked_ship_id == "home", "parked_ship_id round-tripped")
	assert(clone.parked_position == Vector3(2, 0, 3), "parked_position round-tripped")
	assert(clone.get_hold().get_quantity("scrap_metal") == 4, "cart contents round-tripped")
	assert(CartStateScript.create("y").apply_summary({}) == false, "empty summary rejected")

	print("CART STATE SMOKE PASS loaded=6 contents=%d" % clone.get_hold().get_quantity("scrap_metal"))
	quit()
```

- [ ] **Step 2: Run to verify it fails.**

Run:
```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/cart_state_smoke.gd 2>&1
```
Expected: FAIL — `cart_state.gd` does not exist.

- [ ] **Step 3: Implement `CartState`.**

Create `scripts/systems/cart_state.gd`:
```gdscript
extends RefCounted
class_name CartState

## A pushable cart: a mobile container wrapping a ShipInventory. Its contents are
## never added to the player's personal encumbrance (they live in the cart hold);
## a cart "removes" weight from the player whereas a worn bag only raises the cap.
## Pure model; never touches the scene tree. Constructed via the load()-self-ref
## factory (class_name globals unreliable headless). Round-trips via get/apply_summary.

const ShipInventoryScript := preload("res://scripts/systems/ship_inventory.gd")

const MAX_WEIGHT_DEFAULT: float = 200.0
const PUSH_SPEED_MULTIPLIER_DEFAULT: float = 0.7

var cart_id: String = ""
var parked_ship_id: String = ""
var parked_position: Vector3 = Vector3.ZERO
var push_speed_multiplier: float = PUSH_SPEED_MULTIPLIER_DEFAULT
var _hold                                   # ShipInventory

func _init() -> void:
	_hold = ShipInventoryScript.create(MAX_WEIGHT_DEFAULT)

static func create(p_cart_id: String = "", p_max_weight: float = MAX_WEIGHT_DEFAULT) -> CartState:
	var script: GDScript = load("res://scripts/systems/cart_state.gd")
	var inst = script.new()
	inst.cart_id = p_cart_id
	inst._hold = load("res://scripts/systems/ship_inventory.gd").create(p_max_weight)
	return inst

func get_hold():
	return _hold

func get_summary() -> Dictionary:
	return {
		"cart_id": cart_id,
		"parked_ship_id": parked_ship_id,
		"parked_position": [parked_position.x, parked_position.y, parked_position.z],
		"push_speed_multiplier": push_speed_multiplier,
		"hold": _hold.get_summary(),
	}

func apply_summary(summary) -> bool:
	if typeof(summary) != TYPE_DICTIONARY or (summary as Dictionary).is_empty():
		return false
	var d: Dictionary = summary
	cart_id = str(d.get("cart_id", cart_id))
	parked_ship_id = str(d.get("parked_ship_id", parked_ship_id))
	var p: Variant = d.get("parked_position", null)
	if p is Array and (p as Array).size() == 3:
		parked_position = Vector3(float(p[0]), float(p[1]), float(p[2]))
	if d.has("push_speed_multiplier"):
		push_speed_multiplier = float(d["push_speed_multiplier"])
	var hold_summary: Variant = d.get("hold", null)
	if typeof(hold_summary) == TYPE_DICTIONARY:
		_hold.apply_summary(hold_summary as Dictionary)
	return true
```

- [ ] **Step 4: Run to verify it passes.**

Run:
```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/cart_state_smoke.gd 2>&1
```
Expected: PASS — `CART STATE SMOKE PASS loaded=6 contents=4`.

- [ ] **Step 5: Commit.**

```bash
git add scripts/systems/cart_state.gd scripts/validation/cart_state_smoke.gd
git commit -m "feat(cart): CartState mobile-container model + smoke

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 9: `ShipInstance` lazy carts + `WorldSnapshot.home_ship_carts` field

**Files:**
- Modify: `scripts/systems/ship_instance.gd`
- Modify: `scripts/systems/world_snapshot.gd`
- Modify: `scripts/validation/ship_instance_smoke.gd`, `scripts/validation/world_snapshot_smoke.gd`

**Interfaces:**
- Consumes: `CartState` (Task 8).
- Produces: `ShipInstance.get_carts() -> Array` (the live `Array[CartState]`), field `var carts: Array`; `get_summary()` includes `"carts"` only when non-empty; `apply_summary()` rebuilds carts from `"carts"`. `WorldSnapshot.home_ship_carts: Array` (default `[]`), round-tripped through `to_dict()`/`from_dict()`; `WORLD_SLICE_VERSION` stays `"world-4"`.

**Why both:** derelict (visited) ships persist their carts via `ShipInstance.get_summary()["carts"]`. The HOME ship is saved through dedicated `WorldSnapshot` fields (like `home_ship_inventory`), NOT through `visited_ships`/`get_summary()`, so home-ship carts need their own `WorldSnapshot.home_ship_carts` field — the home base is the primary place a player parks carts.

- [ ] **Step 1: Add the carts array + persistence to `ShipInstance`.**

In `scripts/systems/ship_instance.gd`:

Add the preload next to `ShipInventoryScript`:
```gdscript
const CartStateScript := preload("res://scripts/systems/cart_state.gd")
```

Add the field next to `var inventory = null`:
```gdscript
# Sub-project #6 (carts): carts parked on this ship. Persisted under "carts" only
# when non-empty. Each entry is a CartState.
var carts: Array = []                    # Array[CartState]
```

In `get_summary()`, add after the `if has_cargo():` block, before `return result`:
```gdscript
	if not carts.is_empty():
		var cart_dicts: Array = []
		for c in carts:
			cart_dicts.append(c.get_summary())
		result["carts"] = cart_dicts
```

In `apply_summary()`, add after the `inventory_summary` block, before `return true`:
```gdscript
	var carts_variant: Variant = summary.get("carts", null)
	if typeof(carts_variant) == TYPE_ARRAY:
		carts = []
		for cd in (carts_variant as Array):
			if typeof(cd) == TYPE_DICTIONARY:
				var cart = CartStateScript.create()
				cart.apply_summary(cd as Dictionary)
				carts.append(cart)
```

Add the accessor next to `get_inventory()`:
```gdscript
## Returns this ship's live carts array (parked carts).
func get_carts() -> Array:
	return carts
```

- [ ] **Step 2: Add a carts round-trip assertion to `ship_instance_smoke.gd`.**

Append before the final `print(... PASS ...)`/`quit()` (use the smoke's existing `ShipInstance` preload const + its `inst` var):
```gdscript
	# --- carts round-trip (slice 2) ---
	assert(not inst.get_summary().has("carts"), "no carts -> omitted from summary")
	var cart = CartStateScript.create("cart_a", 200.0)   # add the preload at top of the smoke
	cart.get_hold().add_item("scrap_metal", 3)
	inst.get_carts().append(cart)
	var sc: Dictionary = inst.get_summary()
	assert(sc.has("carts") and (sc["carts"] as Array).size() == 1, "carts present in summary")
	var clone2 = ShipInstanceScript.create(inst.ship_id, inst.marker_id, null, null, null)
	assert(clone2.apply_summary(sc) == true, "apply_summary accepts carts")
	assert(clone2.get_carts().size() == 1, "carts round-tripped")
	assert(clone2.get_carts()[0].get_hold().get_quantity("scrap_metal") == 3, "cart contents round-tripped")
```
Add `const CartStateScript := preload("res://scripts/systems/cart_state.gd")` at the top of the smoke. Use the smoke's existing `ShipInstance` preload const name for `ShipInstanceScript`.

- [ ] **Step 3: Add `WorldSnapshot.home_ship_carts` field + serialization.**

In `scripts/systems/world_snapshot.gd`:

Add the field next to `home_ship_inventory` / `player_equipment`:
```gdscript
var home_ship_carts: Array = []                  # home ship's [CartState.get_summary()...]
```
In `to_dict()`, add after the `"player_equipment": ...` line:
```gdscript
		"home_ship_carts": home_ship_carts.duplicate(true),
```
In `from_dict()`, add after the `ws.player_equipment = ...` line:
```gdscript
	var hc_variant: Variant = dict.get("home_ship_carts", [])
	ws.home_ship_carts = (hc_variant as Array).duplicate(true) if hc_variant is Array else []
```
**Do NOT change `WORLD_SLICE_VERSION`.**

- [ ] **Step 4: Add round-trip assertions to both smokes.**

`ship_instance_smoke.gd`: the carts block added in Step 2 already covers `ShipInstance` carts round-trip.

`world_snapshot_smoke.gd`: append before its final `print(... PASS ...)`/`quit()` (reuse the smoke's WorldSnapshot const + version locals):
```gdscript
	# --- home_ship_carts round-trip (slice 2, additive, no version bump) ---
	var ws_hc = WorldSnapshotScript.new()
	ws_hc.slice_version = expected_world_version
	ws_hc.godot_version = expected_godot_version
	ws_hc.home_ship_carts = [{"cart_id": "cart_home", "hold": {"items": {"scrap_metal": 4}, "max_weight": 200.0}}]
	var rt_hc = WorldSnapshotScript.from_dict(ws_hc.to_dict(), expected_world_version, expected_godot_version)
	assert(rt_hc != null, "home_ship_carts snapshot round-trips")
	assert((rt_hc.home_ship_carts as Array).size() == 1, "home_ship_carts survived round-trip")
	assert(str(rt_hc.home_ship_carts[0].get("cart_id", "")) == "cart_home", "cart entry intact")
```

- [ ] **Step 5: Run both smokes — verify markers.**

Run:
```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ship_instance_smoke.gd 2>&1
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/world_snapshot_smoke.gd 2>&1
```
Expected: both PASS markers print; carts + home_ship_carts assertions pass.

- [ ] **Step 6: Commit.**

```bash
git add scripts/systems/ship_instance.gd scripts/systems/world_snapshot.gd scripts/validation/ship_instance_smoke.gd scripts/validation/world_snapshot_smoke.gd
git commit -m "feat(cart): ShipInstance parked carts + WorldSnapshot.home_ship_carts (additive)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 10: `CartControl` walk-up sensor

**Files:**
- Create: `scripts/tools/cart_control.gd`
- Modify: `scripts/validation/equipment_carts_smoke.gd` (no marker change yet — add a Section A2 gate block; Section B lands in Task 11). To keep this task independently testable, add a tiny standalone gate smoke instead — see Step 1.
- Create: `scripts/validation/cart_control_smoke.gd`

**Interfaces:**
- Produces: `CartControl` (`extends Area3D`): `configure(p_cart_id: String, world_position: Vector3, radius := 1.8) -> void`, `try_grab(player_body: Node) -> bool`, `try_load(player_body: Node) -> bool`, `try_unload(player_body: Node, category: String) -> bool`, signals `cart_grab_requested(cart_id: String)`, `cart_load_requested(cart_id: String)`, `cart_unload_requested(cart_id: String, category: String)`, field `var cart_id: String`.

- [ ] **Step 1: Write the failing gate smoke.**

Create `scripts/validation/cart_control_smoke.gd`:
```gdscript
extends SceneTree

## CartControl strict in-range gate: off-tree / out-of-range refuses (no emit);
## in-range grab/load/unload emit their intents. Mirrors CargoHoldControl's gate.

const CartControlScript := preload("res://scripts/tools/cart_control.gd")

var _grab_emits: int = 0
var _load_emits: int = 0
var _unload_cat: String = ""

func _init() -> void:
	await _run()
	print("CART CONTROL SMOKE PASS grabs=%d loads=%d" % [_grab_emits, _load_emits])
	quit()

func _run() -> void:
	var control = CartControlScript.new()
	control.cart_grab_requested.connect(func(_cid): _grab_emits += 1)
	control.cart_load_requested.connect(func(_cid): _load_emits += 1)
	control.cart_unload_requested.connect(func(_cid, cat): _unload_cat = cat)

	assert(control.try_grab(null) == false, "off-tree grab refused")
	assert(_grab_emits == 0, "no emit while refused")

	root.add_child(control)
	control.configure("cart_1", Vector3.ZERO, 1.8)
	await process_frame
	var player := CharacterBody3D.new()
	root.add_child(player)
	player.global_position = Vector3(0.5, 0.0, 0.0)
	await process_frame
	assert(control.try_grab(player) == true, "in-range grab emits")
	assert(_grab_emits == 1, "grab emitted once")
	assert(control.try_load(player) == true, "in-range load emits")
	assert(_load_emits == 1, "load emitted once")
	assert(control.try_unload(player, "part") == true, "in-range unload emits")
	assert(_unload_cat == "part", "unload carried the category")

	player.global_position = Vector3(100.0, 0.0, 0.0)
	await process_frame
	assert(control.try_grab(player) == false, "out-of-range grab refused")
	assert(_grab_emits == 1, "no extra emit out of range")
```

- [ ] **Step 2: Run to verify it fails.**

Run:
```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/cart_control_smoke.gd 2>&1
```
Expected: FAIL — `cart_control.gd` does not exist.

- [ ] **Step 3: Implement `CartControl` (mirror of `CargoHoldControl`).**

Create `scripts/tools/cart_control.gd`:
```gdscript
extends Area3D
class_name CartControl

## A pushable cart's walk-up control. Walk up and interact to grab (push) it, or
## load/unload salvage. Sensor + signal only: it never moves items or reparents
## itself (the coordinator owns cart state + scene lifecycle). Mirrors the strict
## in-range gate + marker of CargoHoldControl.

signal cart_grab_requested(cart_id: String)
signal cart_load_requested(cart_id: String)
signal cart_unload_requested(cart_id: String, category: String)

var cart_id: String = ""
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

func configure(p_cart_id: String, world_position: Vector3, radius := 1.8) -> void:
	assert(radius >= 0.0, "CartControl.configure: radius must be non-negative")
	cart_id = p_cart_id
	interaction_radius = radius
	position = world_position
	name = "CartControl_%s" % p_cart_id
	set_meta("cart_control", true)
	_ensure_collision(radius)
	_ensure_marker(radius)

func try_grab(player_body: Node) -> bool:
	if not _is_player_in_direct_range(player_body):
		return false
	emit_signal("cart_grab_requested", cart_id)
	return true

func try_load(player_body: Node) -> bool:
	if not _is_player_in_direct_range(player_body):
		return false
	emit_signal("cart_load_requested", cart_id)
	return true

func try_unload(player_body: Node, category: String) -> bool:
	if not _is_player_in_direct_range(player_body):
		return false
	emit_signal("cart_unload_requested", cart_id, category)
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
		collision_shape.name = "CartControlCollisionShape3D"
		add_child(collision_shape)
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	collision_shape.shape = sphere

func _ensure_marker(radius: float) -> void:
	if not is_instance_valid(marker):
		marker = MeshInstance3D.new()
		marker.name = "CartControlMarker"
		add_child(marker)
	var box := BoxMesh.new()
	box.size = Vector3(radius * 0.5, radius * 0.4, radius * 0.7)
	marker.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.75, 0.2, 0.7)   # amber, distinct from hold cyan / hangar orange
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	marker.material_override = mat
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.set_meta("debug_cart_control_marker", true)

func _on_body_entered(body: Node3D) -> void:
	if body is PlayerController:
		candidate_player = body

func _on_body_exited(body: Node3D) -> void:
	# Guard the freed-object comparison (Godot 4 throws on == with a freed object).
	if is_instance_valid(candidate_player) and body == candidate_player:
		candidate_player = null
```

- [ ] **Step 4: Run to verify it passes.**

Run:
```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/cart_control_smoke.gd 2>&1
```
Expected: PASS — `CART CONTROL SMOKE PASS grabs=1 loads=1`.

- [ ] **Step 5: Commit.**

```bash
git add scripts/tools/cart_control.gd scripts/validation/cart_control_smoke.gd
git commit -m "feat(cart): CartControl walk-up sensor + in-range gate smoke

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 11: Coordinator cart wiring + main-scene Section B

**Files:**
- Modify: `scripts/procgen/playable_generated_ship.gd`
- Modify: `scripts/validation/equipment_carts_smoke.gd` (append Section B; update marker)

**Interfaces:**
- Consumes: `CartControl` (T10), `CartState` (T8), `CargoTransfer` (cargo slice), `ShipInstance.get_carts()` (T9), `_find_ship_by_id` (~4291), `_recompute_player_encumbrance` / `_equip_from_inventory` cart stubs (T7).
- Produces (seams): `spawn_cart_for_validation(ship_id: String) -> String` (returns cart_id), `cart_grab_for_validation(cart_id: String) -> bool`, `cart_load_for_validation(cart_id: String) -> int`, `cart_unload_for_validation(cart_id: String, category: String) -> int`, `cart_is_grabbed_for_validation() -> bool`, `cart_hold_quantity_for_validation(cart_id: String, item_id: String) -> int`.

**Context:** mirror the cargo-hold control wiring. `_spawn_cargo_hold_control` (def ~1496, sites ~1280/2251/2359/4151/4683), `_clear_cargo_hold_controls` (def ~1521, called ~4444). Carts are persisted on their ship (T9), so a cart's lifecycle is: a `CartState` lives in `ShipInstance.carts`, and a `CartControl` node represents it in the scene.

- [ ] **Step 1: Add the cart field, controls array, real cart-grab stubs, spawn/clear/handlers, and seams.**

Add the preloads near `CargoHoldControlScript`:
```gdscript
const CartControlScript := preload("res://scripts/tools/cart_control.gd")
const CartStateScript := preload("res://scripts/systems/cart_state.gd")
```

Add fields next to `var cargo_hold_controls`:
```gdscript
var cart_controls: Array = []               # Array[CartControl]
var grabbed_cart = null                     # CartState currently pushed by the player (or null)
```

**Replace the Task-7 stubs** `_is_cart_grabbed()` / `_cart_push_multiplier()` with the real bodies:
```gdscript
func _is_cart_grabbed() -> bool:
	return grabbed_cart != null

func _cart_push_multiplier() -> float:
	return float(grabbed_cart.push_speed_multiplier) if grabbed_cart != null else 1.0
```

Add the cart spawn/clear/handlers next to the cargo-hold ones:
```gdscript
## Spawn a CartControl node for an existing CartState parked on `inst`.
func _spawn_cart_control(inst, cart) -> void:
	if inst == null or cart == null or not is_instance_valid(inst.scene_root):
		return
	var control = CartControlScript.new()
	(inst.scene_root as Node3D).add_child(control)
	control.configure(String(cart.cart_id), cart.parked_position, 1.8)
	control.cart_grab_requested.connect(_on_cart_grab_requested)
	control.cart_load_requested.connect(_on_cart_load_requested)
	control.cart_unload_requested.connect(_on_cart_unload_requested)
	cart_controls.append(control)

func _clear_cart_controls() -> void:
	for c in cart_controls:
		if is_instance_valid(c):
			if c.get_parent() != null:
				c.get_parent().remove_child(c)
			c.queue_free()
	cart_controls.clear()

func _find_cart_by_id(cart_id: String):
	for inst in _all_ship_instances():
		for cart in inst.get_carts():
			if String(cart.cart_id) == cart_id:
				return {"cart": cart, "ship": inst}
	return null

func _on_cart_grab_requested(cart_id: String) -> void:
	var hit = _find_cart_by_id(cart_id)
	if hit == null:
		return
	grabbed_cart = hit["cart"]
	_recompute_player_encumbrance()      # applies the push penalty

func _on_cart_load_requested(cart_id: String) -> void:
	if inventory_state == null:
		return
	var hit = _find_cart_by_id(cart_id)
	if hit == null:
		return
	CargoTransferScript.deposit_all(inventory_state, hit["cart"].get_hold())
	_recompute_player_encumbrance()

func _on_cart_unload_requested(cart_id: String, category: String) -> void:
	if inventory_state == null:
		return
	var hit = _find_cart_by_id(cart_id)
	if hit == null:
		return
	CargoTransferScript.withdraw_category(hit["cart"].get_hold(), inventory_state, category)
	_recompute_player_encumbrance()
```

**`_all_ship_instances()` helper:** if the coordinator already exposes a way to iterate every `ShipInstance` (grep — `_find_ship_by_id` (~4291) iterates a collection; reuse the same backing collection/iteration). If a public iterator exists, reuse it; otherwise add a small private `_all_ship_instances() -> Array` that returns the same list `_find_ship_by_id` scans. Do NOT duplicate the ship-storage structure — read the existing one.

Add the seams near the equipment seams:
```gdscript
func spawn_cart_for_validation(ship_id: String) -> String:
	var inst = _find_ship_by_id(ship_id)
	if inst == null:
		return ""
	var cart = CartStateScript.create("cart_%s" % ship_id, 200.0)
	cart.parked_ship_id = ship_id
	inst.get_carts().append(cart)
	_spawn_cart_control(inst, cart)
	return cart.cart_id

func cart_grab_for_validation(cart_id: String) -> bool:
	var hit = _find_cart_by_id(cart_id)
	if hit == null or player == null or not (player is Node3D):
		return false
	var control = null
	for c in cart_controls:
		if is_instance_valid(c) and String(c.cart_id) == cart_id:
			control = c
			break
	if control == null or not control.is_inside_tree() or not (player as Node3D).is_inside_tree():
		return false
	(player as Node3D).global_position = control.global_position
	return control.try_grab(player)

func cart_load_for_validation(cart_id: String) -> int:
	var hit = _find_cart_by_id(cart_id)
	if hit == null or inventory_state == null:
		return 0
	return int(CargoTransferScript.deposit_all(inventory_state, hit["cart"].get_hold()).get("total_moved", 0))

func cart_unload_for_validation(cart_id: String, category: String) -> int:
	var hit = _find_cart_by_id(cart_id)
	if hit == null or inventory_state == null:
		return 0
	return int(CargoTransferScript.withdraw_category(hit["cart"].get_hold(), inventory_state, category).get("total_moved", 0))

func cart_is_grabbed_for_validation() -> bool:
	return _is_cart_grabbed()

func cart_hold_quantity_for_validation(cart_id: String, item_id: String) -> int:
	var hit = _find_cart_by_id(cart_id)
	if hit == null:
		return 0
	return hit["cart"].get_hold().get_quantity(item_id)
```

- [ ] **Step 2: Spawn cart controls for persisted carts, and clear on teardown.**

At each `_spawn_cargo_hold_control(<x>)` site, the ship's persisted carts also need controls. Add a helper call after `_spawn_cargo_hold_control(<x>)` at each of the 5 sites (~1280/2251/2359/4151/4683):
```gdscript
	_spawn_cart_controls_for_ship(<x>)
```
And define:
```gdscript
func _spawn_cart_controls_for_ship(inst) -> void:
	if inst == null:
		return
	for cart in inst.get_carts():
		_spawn_cart_control(inst, cart)
```
At the `_clear_cargo_hold_controls()` teardown call (~4444), add after it:
```gdscript
	_clear_cart_controls()
	grabbed_cart = null
```

- [ ] **Step 3: Persist home-ship carts in the save/load assembly.**

Derelict carts already round-trip via `ShipInstance.get_summary()["carts"]` (Task 9). The home ship is saved through `WorldSnapshot` fields, so route its carts through `ws.home_ship_carts`.

In the save assembly (next to `ws.home_ship_inventory = ...`, ~4023), inside the same `if home_ship != null:` block, add:
```gdscript
		var home_cart_dicts: Array = []
		for c in home_ship.get_carts():
			home_cart_dicts.append(c.get_summary())
		ws.home_ship_carts = home_cart_dicts
```
In the load path (next to the `home_ship.get_inventory().apply_summary(...)` block, ~4180), inside the same `if home_ship != null:` block, add:
```gdscript
		home_ship.get_carts().clear()
		for cd in ws.home_ship_carts:
			if typeof(cd) == TYPE_DICTIONARY:
				var cart = CartStateScript.create()
				cart.apply_summary(cd as Dictionary)
				home_ship.get_carts().append(cart)
		_spawn_cart_controls_for_ship(home_ship)
```
**Ordering requirement:** the home-cart `CartState`s must be appended to `home_ship.get_carts()` BEFORE their `CartControl`s are spawned. The explicit `_spawn_cart_controls_for_ship(home_ship)` here guarantees that even if the per-ship spawn loop (~4151) ran earlier when the home ship had no carts. If that loop already spawns home-ship cart controls, guard against double-spawn by clearing this ship's existing cart controls first (or make `_spawn_cart_controls_for_ship` idempotent per cart_id, mirroring `_spawn_cargo_hold_control`'s prune-existing logic). The persistence *assertion* in the smoke reads `CartState` quantity (not the control), so it passes once the `CartState`s are restored; the control respawn is for post-load playability.

- [ ] **Step 4: Wire the cart into the interact dispatch (player-triggerable load + grab).**

In `_on_player_interact_requested` (~2468), add a lowest-priority cart fallback alongside `_try_cargo_deposit` (~2527). Add a helper and call it after `_try_cargo_deposit` in BOTH the home and away branches (mirror exactly how `_try_cargo_deposit` is placed):
```gdscript
func _try_cart_interact(player_body) -> bool:
	# In-range cart: grab if not held, else load salvage into it. (Unload + release
	# are category/explicit actions deferred to the Phase-7 picker; seam-driven now.)
	for c in cart_controls:
		if not is_instance_valid(c):
			continue
		if grabbed_cart == null:
			if c.try_grab(player_body):
				return true
		else:
			if c.try_load(player_body):
				return true
	return false
```
Place `if _try_cart_interact(player_body): return` immediately after the existing `if _try_cargo_deposit(player_body): return` in each branch.

- [ ] **Step 5: Append Section B to `equipment_carts_smoke.gd` + update the marker.**

Update `_init` to await Section B and set the real marker from results:
```gdscript
func _init() -> void:
	await _run_section_a()
	await _run_section_b()
```
Add Section B (a fresh ship; spawn a cart on the home ship; grab → both hands busy + push penalty drops speed; load via the real interact path; unload via seam; persist a parked cart across save→load):
```gdscript
var _b_loaded: int = 0
var _b_persisted: bool = false

func _run_section_b() -> void:
	var ship = PlayableGeneratedShipScript.new()
	root.add_child(ship)
	for _i in range(3):
		await process_frame
	var home_id: String = ship.home_ship_id_for_validation()
	var cart_id: String = ship.spawn_cart_for_validation(home_id)
	assert(cart_id != "", "cart spawned on the home ship")
	for _k in range(2):
		await process_frame

	# Grab: cart marked grabbed + push penalty lowers move_speed.
	var pre_speed: float = ship.player_move_speed_for_validation()
	assert(ship.cart_grab_for_validation(cart_id) == true, "cart grabbed in range")
	assert(ship.cart_is_grabbed_for_validation() == true, "cart marked grabbed")
	assert(ship.player_move_speed_for_validation() < pre_speed, "push penalty slowed the player")

	# Load salvage into the cart (it leaves the player inventory -> off personal
	# encumbrance), then unload it straight back out.
	ship.overload_player_for_validation("scrap_metal", 5)
	_b_loaded = ship.cart_load_for_validation(cart_id)
	assert(_b_loaded == 5, "loaded 5 into the cart (got %d)" % _b_loaded)
	assert(ship.cart_hold_quantity_for_validation(cart_id, "scrap_metal") == 5, "cart holds 5")
	var unloaded: int = ship.cart_unload_for_validation(cart_id, "part")
	assert(unloaded == 5, "unloaded all 5 back to the player (got %d)" % unloaded)
	assert(ship.cart_hold_quantity_for_validation(cart_id, "scrap_metal") == 0, "cart emptied after unload")
	# Re-load so the parked cart is non-empty for the persistence check.
	ship.overload_player_for_validation("scrap_metal", 5)
	ship.cart_load_for_validation(cart_id)

	# Persist a parked cart across save->load.
	assert(ship.save_world_for_validation() == true, "world saved")
	assert(ship.load_world_for_validation() == true, "world loaded")
	for _j in range(3):
		await process_frame
	var home2: String = ship.home_ship_id_for_validation()
	# After reload the cart_id is deterministic ("cart_<ship_id>") and the parked
	# cart's contents persist via WorldSnapshot.home_ship_carts.
	var persisted_qty: int = ship.cart_hold_quantity_for_validation("cart_%s" % home2, "scrap_metal")
	_b_persisted = persisted_qty == 5
	assert(_b_persisted, "parked home cart persisted across save/load (got %d)" % persisted_qty)
	ship.queue_free()

func _section_b_marker() -> String:
	return "EQUIPMENT CARTS SMOKE PASS section_a=true cap_bonus=40 slowed=true cart_loaded=%d persisted=%s" % [_b_loaded, str(_b_persisted)]
```
Replace the Section-A-only `print(...)` in `_init` with `print(_section_b_marker())` AFTER `await _run_section_b()`. **Remove the placeholder Section-A print.** Confirm seam names against the coordinator: if `player_inventory_quantity_for_validation` does not exist, drop that disjunct and assert `cart_unload_for_validation(cart_id, "part") == 5` directly (the player had emptied into the cart, then unloads back). Adjust to the real seams rather than inventing them.

Confirm `save_world_for_validation` / `load_world_for_validation` / `home_ship_id_for_validation` are the real existing seam names (grep — used by `cargo_hold_smoke.gd`). Adjust to the actual names rather than inventing any.

- [ ] **Step 6: Run the smoke — verify Section B.**

Run:
```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/equipment_carts_smoke.gd 2>&1
```
Expected: PASS — `EQUIPMENT CARTS SMOKE PASS section_a=true cap_bonus=40 slowed=true cart_loaded=5 persisted=true`.

- [ ] **Step 7: Commit.**

```bash
git add scripts/procgen/playable_generated_ship.gd scripts/validation/equipment_carts_smoke.gd
git commit -m "feat(cart): coordinator cart spawn/grab/load/unload + interact wiring + Section B smoke

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 12: ADR + roadmap + register smokes in the regression bundle

**Files:**
- Create: `docs/game/adr/0021-equipment-carts.md`
- Modify: `docs/game/06_validation_plan.md`
- Modify: `docs/game/09_system_roadmap.md`

- [ ] **Step 1: Write ADR-0021.**

Create `docs/game/adr/0021-equipment-carts.md` capturing the decisions from the design (§8 of the spec): PZ soft-cap (player-only), Heavy Load = movement-only this slice, worn bag = +capacity on a single pool (no nesting), cart = separate zero-encumbrance container (two-handed, push penalty), auto-equip-on-pickup + seams (UI Phase 7), strength scaling seam (default 0), additive persistence (no version bump), slots = suit/back/waist/primary_hand/secondary_hand. Follow the format of `docs/game/adr/0020-ship-cargo-holds.md` (read it first for the house ADR shape). Include a "Consequences" + "Deferred" section listing the spec §9 deferrals.

- [ ] **Step 2: Register the new smokes in the regression bundle.**

In `docs/game/06_validation_plan.md`, read the bundle block (the flat list of `run_clean '<desc>' '<marker-substring>' ... --script <gd>` lines) and the trailing `echo 'SARGASSO REGRESSION PASS commands=104 clean_output=true'`. Add one `run_clean` line per NEW smoke, each grepping its exact marker substring:
- `equipment_defs_smoke.gd` → `EQUIPMENT DEFS SMOKE PASS`
- `equipment_state_smoke.gd` → `EQUIPMENT STATE SMOKE PASS`
- `encumbrance_smoke.gd` → `EQUIPMENT ENCUMBRANCE SMOKE PASS`
- `cart_state_smoke.gd` → `CART STATE SMOKE PASS`
- `cart_control_smoke.gd` → `CART CONTROL SMOKE PASS`
- `equipment_carts_smoke.gd` → `EQUIPMENT CARTS SMOKE PASS`

(`equipment_defs_smoke` is folded into Task 1 but registered here.) That is 6 new commands: update the final count `104` → `110` in the `echo 'SARGASSO REGRESSION PASS commands=110 clean_output=true'` line AND any header/comment that states the command count. Verify the arithmetic against the actual number of `run_clean` lines after editing (the existing pre-slice count is 104; confirm by counting before adding).

- [ ] **Step 3: Update the system roadmap.**

In `docs/game/09_system_roadmap.md`, update the System 6 row (line ~39) and the §A "What remains" / net-summary lines: equipment slots + carry containers + carts now done; remaining = rich transfer UI (Phase 7) + nested containers + strength scaling + endurance/health Heavy Load. Move System 6 from `~60%` to `~80%` (worn equipment + encumbrance + carts delivered; only the Phase-7 UI and deferred refinements remain).

- [ ] **Step 4: Run the FULL regression bundle (drift stashed) + Gate-1.**

```bash
cd "C:/Users/dasbl/Documents/The Synaptic Sea"
git stash push -- project.godot
GODOT="C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe" \
ROOT="C:/Users/dasbl/Documents/The Synaptic Sea" \
  bash docs/game/06_validation_plan.md   # or extract+run the bundle block per the doc's instructions
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/gate1_automated_playtest.gd 2>&1
git stash pop
```
Expected: `SARGASSO REGRESSION PASS commands=110 clean_output=true` and Gate-1 `pass_decision=GO` / `overall_average=2.00`. If the bundle reports an unexpected `ERROR:`/`WARNING:`, classify it in `06_validation_plan.md` before completing. **Always `git stash pop`** even on failure.

- [ ] **Step 5: Commit.**

```bash
git add docs/game/adr/0021-equipment-carts.md docs/game/06_validation_plan.md docs/game/09_system_roadmap.md
git commit -m "docs(equipment): ADR-0021 + roadmap + register equipment/cart smokes (104->110)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Self-Review notes (for the executor)

- **Soft-cap blast radius:** Tasks 3–4 are the risk center. The conservation invariant in `CargoTransfer` is structural (remove == accepted) and still holds; only cap-limited *expectations* in smokes change. If ANY non-cargo caller depended on `add_item` refusing on weight (grep `add_item(` across `scripts/`), flag it — the only intended behavior change is the player no longer refusing on weight.
- **Stub lifecycle:** the Task-7 `_is_cart_grabbed`/`_cart_push_multiplier` stubs MUST be replaced (not duplicated) in Task 11 — a duplicate `func` is a parse error. The reviewer should confirm exactly one definition of each exists after Task 11.
- **Seam honesty:** every `*_for_validation` seam must drive the SAME code path as gameplay (the interact wiring in T11 Step 3 is what makes the cart player-triggerable; the load seam exercises the real `CargoTransfer`). No assertion may be tautological (the T11 hand-block placeholder is explicitly called out to replace or delete).
- **Marker uniqueness:** confirm each new marker substring is unique in the bundle grep (`EQUIPMENT DEFS`, `EQUIPMENT STATE`, `EQUIPMENT ENCUMBRANCE`, `EQUIPMENT CARTS`, `CART STATE`, `CART CONTROL` are all distinct; note `EQUIPMENT CARTS` vs `EQUIPMENT ENCUMBRANCE` share the `EQUIPMENT ` prefix but the bundle greps the full substring, so they don't collide).
```
