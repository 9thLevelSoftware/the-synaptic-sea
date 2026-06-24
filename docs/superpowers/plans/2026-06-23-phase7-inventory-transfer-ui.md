# Phase 7 Slice 1 — Inventory & Transfer UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a mouse-driven, Project-Zomboid-style inventory/equipment/transfer screen (drag-and-drop, shift/ctrl multi-select, right-click context menus) over the existing System 6 models, rendered with the hand-built HUD look.

**Architecture:** A pure `RefCounted` selection model (`inventory_selection_model.gd`, fully smoke-tested) plus a thin `Control` view (`inventory_panel.gd`) that delegates every decision to the model and every move to `CargoTransfer`. The view exposes a headless-queryable logical API that both its Godot mouse/DnD overrides and the validation smokes call, so the only lightly-covered code is literal pixel-drag plumbing. The coordinator (`playable_generated_ship.gd`) owns the panel like it owns `scanner_panel`, registers `toggle_inventory` at runtime, opens TRANSFER mode from the hold/cart controls, and recomputes encumbrance + refreshes oxygen on every transfer.

**Tech Stack:** Godot 4.6.2, typed GDScript, Forward+. Headless `--script` SceneTree validation smokes with single PASS-marker contracts.

## Global Constraints

- **Engine/binary:** `GODOT="C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe"`; `ROOT="C:/Users/dasbl/Documents/The Synaptic Sea"`. Run smokes headless: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/<name>.gd 2>&1`. **Markers print to stderr — always append `2>&1`.** Never trust exit code alone; confirm the PASS marker line is present.
- **Definition of done = fresh PASS-marker output.** Each new system gets a pure-model smoke and (if it has scene consequences) a scene smoke, both registered in `docs/game/06_validation_plan.md`.
- **Typed GDScript** for all new code.
- **No new persisted state, no save-format change.** `WORLD_SLICE_VERSION` stays `"world-4"`.
- **Do NOT stage/commit:** `project.godot`, `.godot/`, `*.uid`, `addons/`. Use selective `git add <explicit paths>` only. The `toggle_inventory` action is registered at runtime via `_ensure_key_action_set` — `project.godot` is never touched.
- **Allowlisted headless noise (ignore):** `ERROR: Capture not registered: 'gdaimcp'.` and `WARNING: ObjectDB instances leaked at exit`. Any other `ERROR:`/`WARNING:` line blocks completion.
- **Commit style:** Conventional Commits; every commit message ends with the trailer `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.
- **`context_actions` signature is fixed by the spec:** `static func context_actions(item_id: String, defs: Dictionary, in_transfer_mode: bool, dest_is_container: bool, is_equipped_slot: bool) -> PackedStringArray`. `dest_is_container` is accepted but not branched on in this slice (forward-compat); keep the parameter so the signature matches the spec verbatim.
- **Tools are transferable** via manual move; bulk `deposit_all` still excludes tools (`CargoTransfer.HAULABLE_CATEGORIES`). Depositing `portable_oxygen_pump` must revert the oxygen drain multiplier to 1.0 (live), withdrawing restores 0.5.
- **Branch:** `phase7-inventory-transfer-ui` (already created; the spec is committed on it).
- **Spec:** `docs/superpowers/specs/2026-06-23-phase7-inventory-transfer-ui-design.md`.

---

## File Structure

| File | Responsibility | Task |
|------|----------------|------|
| `scripts/systems/cargo_transfer.gd` (modify) | `move_item`/`move_items` per-item primitives | 1 |
| `scripts/systems/item_defs.gd` (modify) | `icon(defs, id)` reader (swatch fallback) | 1 |
| `scripts/validation/cargo_move_item_smoke.gd` (create) | proves move semantics + `icon` default | 1 |
| `scripts/systems/inventory_selection_model.gd` (create) | pure selection math + `context_actions` | 2 |
| `scripts/validation/inventory_selection_model_smoke.gd` (create) | proves selection + action resolution | 2 |
| `scripts/ui/inventory_panel.gd` (create, then extend) | thin Control view, SELF mode (T3) + TRANSFER mode & DnD (T4) | 3, 4 |
| `scripts/validation/inventory_panel_smoke.gd` (create, then extend) | panel logical-API coverage, Section A (T3) + B (T4) | 3, 4 |
| `scripts/procgen/playable_generated_ship.gd` (modify) | own panel, register action, open-from-container, freeze/restore, recompute-on-transfer, validation seams | 5 |
| `scripts/validation/cargo_hold_smoke.gd` (modify) | keep green after interact repoint (Section B) | 5 |
| `scripts/validation/main_playable_slice_inventory_ui_smoke.gd` (create) | open-freeze, per-item transfer, O2 tool-storage effect, close-restore | 6 |
| `docs/game/adr/0022-inventory-transfer-ui.md` (create) | record UI-integration decisions | 7 |
| `docs/game/06_validation_plan.md` (modify) | register 4 smokes (110 → 114) | 7 |
| `docs/game/09_system_roadmap.md` (modify) | System 6 ~80% → ~85%; Phase 7 slice A in progress | 7 |

---

### Task 1: Transfer primitives + icon reader

**Files:**
- Modify: `scripts/systems/cargo_transfer.gd` (add `move_item`, `move_items`)
- Modify: `scripts/systems/item_defs.gd` (add `icon`)
- Create: `scripts/validation/cargo_move_item_smoke.gd`

**Interfaces:**
- Consumes: `InventoryState`/`ShipInventory` duck-typed API — `get_quantity(id)->int`, `add_item(id,qty)->int` (returns accepted, enforces own cap), `remove_item(id,qty)->int`, `items: Dictionary`. `ItemDefs.get_definition(defs, id)->Dictionary`.
- Produces: `CargoTransfer.move_item(src, dst, item_id: String, qty: int) -> int`; `CargoTransfer.move_items(src, dst, id_to_qty: Dictionary) -> int`; `ItemDefs.icon(defs: Dictionary, item_id: String) -> String`.

- [ ] **Step 1: Write the failing test** — create `scripts/validation/cargo_move_item_smoke.gd`:

```gdscript
extends SceneTree

## CargoTransfer per-item move + ItemDefs.icon smoke. Asserts move_item honors each
## destination's own cap (player soft-cap = full accept; hold hard-cap = partial fill),
## conservation (no dup/loss), multi-item move, split (partial qty), tool transfer
## (tools ARE manually transferable), and the icon reader's empty default.

const InventoryStateScript := preload("res://scripts/systems/inventory_state.gd")
const ShipInventoryScript := preload("res://scripts/systems/ship_inventory.gd")
const CargoTransferScript := preload("res://scripts/systems/cargo_transfer.gd")
const ItemDefsScript := preload("res://scripts/systems/item_defs.gd")

const PART := "scrap_metal"          # part, weight 5.0, max_stack 20
const SUPPLY := "ration_pack"        # supply, weight 0.5, max_stack 20
const TOOL := "portable_oxygen_pump" # tool

func _init() -> void:
	var defs: Dictionary = ItemDefsScript.load_definitions()

	# icon reader: absent field -> "" (swatch fallback)
	assert(ItemDefsScript.icon(defs, PART) == "", "icon default is empty")

	# --- player soft-cap destination: full accept ---
	var hold = ShipInventoryScript.create(1000.0)
	hold.add_item(PART, 10)
	var player = InventoryStateScript.new()
	var moved_in: int = CargoTransferScript.move_item(hold, player, PART, 4)
	assert(moved_in == 4, "moved 4 to player (got %d)" % moved_in)
	assert(player.get_quantity(PART) == 4 and hold.get_quantity(PART) == 6, "split left 6 in hold")

	# --- hold hard-cap destination: partial fill ---
	# scrap_metal weighs 5.0; a 12-weight hold accepts only floor(12/5)=2.
	var tiny = ShipInventoryScript.create(12.0)
	var src = InventoryStateScript.new()
	src.add_item(PART, 5)
	var moved_cap: int = CargoTransferScript.move_item(src, tiny, PART, 5)
	assert(moved_cap == 2, "hold weight cap took only 2 (got %d)" % moved_cap)
	assert(src.get_quantity(PART) == 3, "exactly the accepted 2 left the source")
	assert(src.get_quantity(PART) + tiny.get_quantity(PART) == 5, "conservation across capped move")

	# --- tools transferable + multi-item move ---
	var p2 = InventoryStateScript.new()
	p2.add_tool(TOOL)
	p2.add_item(SUPPLY, 3)
	var hold2 = ShipInventoryScript.create(1000.0)
	var moved_multi: int = CargoTransferScript.move_items(p2, hold2, {TOOL: 1, SUPPLY: 3})
	assert(moved_multi == 4, "moved tool + 3 supply (got %d)" % moved_multi)
	assert(hold2.get_quantity(TOOL) == 1, "tool is now in the hold (tools transferable)")
	assert(p2.get_quantity(TOOL) == 0, "tool left the player")

	# --- no-ops ---
	assert(CargoTransferScript.move_item(p2, hold2, PART, 0) == 0, "qty 0 moves nothing")
	assert(CargoTransferScript.move_item(p2, hold2, "nonexistent_id", 5) == 0, "unknown id moves nothing")

	print("CARGO MOVE ITEM SMOKE PASS soft=%d capped=%d multi=%d" % [moved_in, moved_cap, moved_multi])
	quit()
```

- [ ] **Step 2: Run it — expect FAIL** (methods not defined):

```bash
GODOT="C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe"; ROOT="C:/Users/dasbl/Documents/The Synaptic Sea"
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/cargo_move_item_smoke.gd 2>&1
```
Expected: a parse/runtime error referencing `move_item`/`icon` (no `CARGO MOVE ITEM SMOKE PASS` line).

- [ ] **Step 3: Add `icon` to `scripts/systems/item_defs.gd`** — after the `effects` static (end of file), append:

```gdscript
static func icon(defs: Dictionary, item_id: String) -> String:
	return str(get_definition(defs, item_id).get("icon", ""))
```

- [ ] **Step 4: Add the move primitives to `scripts/systems/cargo_transfer.gd`** — append after `withdraw_category`:

```gdscript
## Moves up to `qty` of one item_id from src -> dst. The destination enforces its own
## cap inside add_item (player InventoryState = soft-cap/full accept; ShipInventory =
## hard weight-cap/partial fill), and src loses EXACTLY what dst accepted, so the
## per-id total across src+dst is invariant. Returns the count actually moved.
static func move_item(src, dst, item_id: String, qty: int) -> int:
	if src == null or dst == null or item_id.is_empty() or qty <= 0:
		return 0
	var have: int = int(src.get_quantity(item_id))
	var want: int = min(qty, have)
	if want <= 0:
		return 0
	var accepted: int = int(dst.add_item(item_id, want))
	if accepted <= 0:
		return 0
	return int(src.remove_item(item_id, accepted))

## Applies move_item per entry (ids sorted for determinism). Returns total moved.
## Used by multi-selection drags and "transfer all".
static func move_items(src, dst, id_to_qty: Dictionary) -> int:
	var total: int = 0
	var ids: Array = id_to_qty.keys()
	ids.sort()
	for id_v in ids:
		total += move_item(src, dst, String(id_v), int(id_to_qty[id_v]))
	return total
```

- [ ] **Step 5: Run it — expect PASS:**

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/cargo_move_item_smoke.gd 2>&1
```
Expected: `CARGO MOVE ITEM SMOKE PASS soft=4 capped=2 multi=4` and no non-allowlisted `ERROR:`/`WARNING:`.

- [ ] **Step 6: Commit:**

```bash
git add scripts/systems/cargo_transfer.gd scripts/systems/item_defs.gd scripts/validation/cargo_move_item_smoke.gd
git commit  # feat(inventory): per-item CargoTransfer.move_item/move_items + ItemDefs.icon reader  (+ Co-Authored-By trailer)
```

---

### Task 2: Pure selection model + context-action resolver

**Files:**
- Create: `scripts/systems/inventory_selection_model.gd`
- Create: `scripts/validation/inventory_selection_model_smoke.gd`

**Interfaces:**
- Consumes: `ItemDefs.equip_slot(defs, id) -> String` (non-empty ⇒ equippable).
- Produces: `InventorySelectionModel` with `set_ids(Array)`, `clear()`, `select_single(int)`, `toggle(int)`, `select_range_to(int)`, `is_selected(int)->bool`, `get_selected_indices()->Array`, `get_selected_ids()->Array`, and `static context_actions(item_id, defs, in_transfer_mode, dest_is_container, is_equipped_slot) -> PackedStringArray`.

- [ ] **Step 1: Write the failing test** — create `scripts/validation/inventory_selection_model_smoke.gd`:

```gdscript
extends SceneTree

## Pure selection-math + context-action smoke for the inventory UI's model layer.

const ModelScript := preload("res://scripts/systems/inventory_selection_model.gd")
const ItemDefsScript := preload("res://scripts/systems/item_defs.gd")

func _init() -> void:
	var m = ModelScript.new()
	m.set_ids(["a", "b", "c", "d", "e"])

	# single replaces + sets anchor
	m.select_single(1)
	assert(m.get_selected_ids() == ["b"], "single selects b")

	# shift range from anchor (1) to 3 -> b,c,d
	m.select_range_to(3)
	assert(m.get_selected_ids() == ["b", "c", "d"], "range b..d")

	# ctrl toggle removes one
	m.toggle(2)
	assert(m.get_selected_ids() == ["b", "d"], "toggle off c")

	# new single clears the rest
	m.select_single(4)
	assert(m.get_selected_ids() == ["e"], "single clears prior")

	# set_ids drops out-of-range selection
	m.select_single(4)
	m.set_ids(["x", "y"])
	assert(m.get_selected_ids().is_empty(), "shrunk id list cleared stale selection")

	# --- context_actions ---
	var defs: Dictionary = ItemDefsScript.load_definitions()
	# a normal part in transfer mode: transfer / transfer_all / split
	var part_actions: PackedStringArray = ModelScript.context_actions("scrap_metal", defs, true, true, false)
	assert(Array(part_actions) == ["transfer", "transfer_all", "split"], "part transfer actions")
	# an equippable suit in SELF mode: equip
	var suit_actions: PackedStringArray = ModelScript.context_actions("hardsuit", defs, false, false, false)
	assert(Array(suit_actions) == ["equip"], "suit equip action in self mode")
	# an occupied equipment slot: unequip
	var slot_actions: PackedStringArray = ModelScript.context_actions("hardsuit", defs, false, false, true)
	assert(Array(slot_actions) == ["unequip"], "occupied slot unequips")
	# a tool in transfer mode: transferable (transfer present)
	var tool_actions: PackedStringArray = ModelScript.context_actions("portable_oxygen_pump", defs, true, true, false)
	assert("transfer" in Array(tool_actions), "tools are transferable")

	print("INVENTORY SELECTION MODEL SMOKE PASS ids=%d" % m.ids.size())
	quit()
```

> Note: `hardsuit` must declare `equip_slot: "suit"` in `data/items/equipment_definitions.json` (it does — System 6). If the id differs, use the actual suit id; do not invent one.

- [ ] **Step 2: Run it — expect FAIL** (script not found):

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/inventory_selection_model_smoke.gd 2>&1
```

- [ ] **Step 3: Create `scripts/systems/inventory_selection_model.gd`:**

```gdscript
extends RefCounted
class_name InventorySelectionModel

## Pure per-list selection state for the inventory UI + a static context-action
## resolver. No scene-tree access. The view (inventory_panel.gd) owns one of these per
## visible list and asks it what is selected and which menu actions apply.

const ItemDefsScript := preload("res://scripts/systems/item_defs.gd")

var ids: Array = []                # ordered item ids currently shown in this list
var _selected: Dictionary = {}     # index:int -> true
var _anchor: int = -1

## Replace the ordered id list; drop any selection/anchor now out of range.
func set_ids(p_ids: Array) -> void:
	ids = []
	for v in p_ids:
		ids.append(String(v))
	var keep: Dictionary = {}
	for idx in _selected:
		if int(idx) >= 0 and int(idx) < ids.size():
			keep[int(idx)] = true
	_selected = keep
	if _anchor >= ids.size():
		_anchor = -1

func clear() -> void:
	_selected.clear()
	_anchor = -1

## Plain click: select exactly one and set the range anchor.
func select_single(index: int) -> void:
	_selected.clear()
	if index >= 0 and index < ids.size():
		_selected[index] = true
		_anchor = index

## Ctrl-click: add/remove one; the anchor follows the click.
func toggle(index: int) -> void:
	if index < 0 or index >= ids.size():
		return
	if _selected.has(index):
		_selected.erase(index)
	else:
		_selected[index] = true
	_anchor = index

## Shift-click: select the contiguous block from the anchor to index.
func select_range_to(index: int) -> void:
	if index < 0 or index >= ids.size():
		return
	if _anchor < 0:
		select_single(index)
		return
	_selected.clear()
	var lo: int = min(_anchor, index)
	var hi: int = max(_anchor, index)
	for i in range(lo, hi + 1):
		_selected[i] = true

func is_selected(index: int) -> bool:
	return _selected.has(index)

func get_selected_indices() -> Array:
	var out: Array = _selected.keys()
	out.sort()
	return out

func get_selected_ids() -> Array:
	var out: Array = []
	for i in get_selected_indices():
		out.append(ids[int(i)])
	return out

## Resolve the right-click menu action set for one row. `dest_is_container` is accepted
## for forward-compat (deposit vs withdraw labelling) but does not branch behaviour yet.
static func context_actions(item_id: String, defs: Dictionary, in_transfer_mode: bool, dest_is_container: bool, is_equipped_slot: bool) -> PackedStringArray:
	var actions: PackedStringArray = PackedStringArray()
	if is_equipped_slot:
		actions.append("unequip")
		return actions
	var equippable: bool = not ItemDefsScript.equip_slot(defs, item_id).is_empty()
	if in_transfer_mode:
		actions.append("transfer")
		actions.append("transfer_all")
		actions.append("split")
		if equippable:
			actions.append("equip")
	elif equippable:
		actions.append("equip")
	return actions
```

- [ ] **Step 4: Run it — expect PASS:**

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/inventory_selection_model_smoke.gd 2>&1
```
Expected: `INVENTORY SELECTION MODEL SMOKE PASS ids=2`.

- [ ] **Step 5: Commit:**

```bash
git add scripts/systems/inventory_selection_model.gd scripts/validation/inventory_selection_model_smoke.gd
git commit  # feat(inventory): pure InventorySelectionModel + context_actions resolver
```

---

### Task 3: InventoryPanel — scaffold + SELF mode

**Files:**
- Create: `scripts/ui/inventory_panel.gd`
- Create: `scripts/validation/inventory_panel_smoke.gd`

**Interfaces:**
- Consumes: `InventoryState` (`items`, `get_quantity`, `add_item`, `remove_item`, `get_category`, `get_display_name`, `get_load_ratio`, `get_capacity`, `get_total_weight`), `EquipmentState` (`SLOTS`, `equip`, `unequip`, `get_equipped`, `is_slot_occupied`, `can_equip`), `InventorySelectionModel`, `Encumbrance.move_speed_multiplier`, `ItemDefs`.
- Produces: `InventoryPanel` (extends Control). Public: `open_self(inv, equip)`, `close()`, `is_open()->bool`, `get_mode()->String`, `select_row(pane: String, index: int, additive: bool, range_sel: bool)`, `get_pane_ids(pane: String)->Array`, `get_selected_ids(pane: String)->Array`, `equip_selected()->bool`, `unequip_slot(slot_id: String)->bool`, `get_load_badge()->String`. Signals: `panel_closed`, `transfer_completed`. (TRANSFER methods land in Task 4.)

- [ ] **Step 1: Write the failing test** — create `scripts/validation/inventory_panel_smoke.gd`:

```gdscript
extends SceneTree

## InventoryPanel logical-API smoke. Section A (this task): SELF mode — render lists,
## select a row, equip/unequip round-trip, Heavy-Load badge. Section B (Task 4) extends
## this file with TRANSFER mode + drag-data plumbing. Drives the same logical API the
## mouse overrides call, so no synthetic pixel input is needed.

const InventoryPanelScript := preload("res://scripts/ui/inventory_panel.gd")
const InventoryStateScript := preload("res://scripts/systems/inventory_state.gd")
const EquipmentStateScript := preload("res://scripts/systems/equipment_state.gd")

func _init() -> void:
	await _run_section_a()
	print("INVENTORY PANEL SMOKE PASS section_a=true")
	quit()

func _run_section_a() -> void:
	var inv = InventoryStateScript.new()
	inv.add_item("scrap_metal", 6)        # part
	inv.add_item("eva_backpack", 1)       # equippable: back, +40 capacity
	var equip = EquipmentStateScript.create()

	var panel = InventoryPanelScript.new()
	root.add_child(panel)
	await process_frame
	panel.open_self(inv, equip)
	assert(panel.is_open() and panel.get_mode() == "self", "panel open in self mode")

	# carrying list contains both ids
	var ids: Array = panel.get_pane_ids("self")
	assert("scrap_metal" in ids and "eva_backpack" in ids, "self list shows carried items")

	# select the backpack row and equip it
	var bp_index: int = ids.find("eva_backpack")
	panel.select_row("self", bp_index, false, false)
	assert(panel.equip_selected() == true, "equipped the backpack")
	assert(equip.get_equipped("back") == "eva_backpack", "backpack now worn")
	assert(inv.get_quantity("eva_backpack") == 0, "worn item left the carry list")

	# unequip puts it back in the carry list
	assert(panel.unequip_slot("back") == true, "unequipped back")
	assert(inv.get_quantity("eva_backpack") == 1, "item returned to inventory")
	assert(equip.get_equipped("back") == "", "back slot empty")

	# Heavy-Load badge: stuff the player far over capacity (no bag bonus now)
	inv.add_item("plating", 10)   # 8.0 each -> 80; base cap 50 -> overloaded
	assert(panel.get_load_badge() == "OVERLOADED", "badge flips overloaded (got %s)" % panel.get_load_badge())

	# close emits panel_closed
	var closed := [false]
	panel.panel_closed.connect(func(): closed[0] = true)
	panel.close()
	assert(panel.is_open() == false and closed[0], "close emits panel_closed")
	panel.queue_free()
```

- [ ] **Step 2: Run it — expect FAIL** (script not found):

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/inventory_panel_smoke.gd 2>&1
```

- [ ] **Step 3: Create `scripts/ui/inventory_panel.gd`** (SELF mode + scaffold; TRANSFER methods added in Task 4):

```gdscript
extends Control
class_name InventoryPanel

## Thin view over the System 6 models. Hand-built dark-teal panel matching the HUD.
## Mouse interaction (drag-drop, multi-select, context menus) is layered on top in
## Task 4; every decision delegates to InventorySelectionModel + CargoTransfer, and a
## headless-queryable logical API lets smokes drive the same code paths without input.

signal panel_closed         # emitted on every close() so the coordinator restores control
signal transfer_completed   # emitted after any state mutation so the coordinator recomputes

const InventorySelectionModelScript := preload("res://scripts/systems/inventory_selection_model.gd")
const CargoTransferScript := preload("res://scripts/systems/cargo_transfer.gd")
const EncumbranceScript := preload("res://scripts/systems/encumbrance.gd")
const ItemDefsScript := preload("res://scripts/systems/item_defs.gd")

const PANEL_COLOR: Color = Color(0.03, 0.05, 0.07, 0.92)
const PANEL_BORDER_COLOR: Color = Color(0.22, 0.72, 1.0, 0.65)

var _mode: String = "closed"        # "closed" | "self" | "transfer"
var _player_inv = null              # InventoryState
var _equip = null                   # EquipmentState
var _container = null               # ShipInventory (TRANSFER mode), else null
var _container_label: String = ""

# Selection models, one per visible list. "self"/"you" share the player list model.
var _sel_self := InventorySelectionModelScript.new()
var _sel_container := InventorySelectionModelScript.new()

var _defs: Dictionary = {}
var _root_label: Label              # single text mirror of the panel for headless query + display

func _ready() -> void:
	set_anchors_preset(Control.PRESET_CENTER)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_defs = ItemDefsScript.load_definitions()
	if _root_label == null:
		var bg := PanelContainer.new()
		bg.position = Vector2(200, 120)
		bg.custom_minimum_size = Vector2(680, 420)
		var style := StyleBoxFlat.new()
		style.bg_color = PANEL_COLOR
		style.border_color = PANEL_BORDER_COLOR
		style.set_border_width_all(2)
		style.set_corner_radius_all(8)
		bg.add_theme_stylebox_override("panel", style)
		add_child(bg)
		var margin := MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 16)
		margin.add_theme_constant_override("margin_top", 14)
		margin.add_theme_constant_override("margin_right", 16)
		margin.add_theme_constant_override("margin_bottom", 14)
		bg.add_child(margin)
		_root_label = Label.new()
		_root_label.add_theme_color_override("font_color", Color.WHITE)
		margin.add_child(_root_label)
	visible = false

# --- lifecycle ---

func open_self(inv, equip) -> void:
	_player_inv = inv
	_equip = equip
	_container = null
	_container_label = ""
	_mode = "self"
	visible = true
	_rebuild_models()
	_render()

func close() -> void:
	_mode = "closed"
	visible = false
	panel_closed.emit()

func is_open() -> bool:
	return _mode != "closed"

func get_mode() -> String:
	return _mode

# --- list/pane access ---

## Ordered item ids in a pane. pane: "self"/"you" = player carry list; "container" = hold.
func _ids_for_pane(pane: String) -> Array:
	if pane == "container":
		return _sorted_ids(_container)
	return _sorted_ids(_player_inv)

func _sorted_ids(inv) -> Array:
	if inv == null:
		return []
	var ids: Array = (inv.items as Dictionary).keys()
	ids.sort()
	var out: Array = []
	for v in ids:
		out.append(String(v))
	return out

func get_pane_ids(pane: String) -> Array:
	return _ids_for_pane(pane)

func _model_for_pane(pane: String) -> InventorySelectionModel:
	return _sel_container if pane == "container" else _sel_self

func _rebuild_models() -> void:
	_sel_self.set_ids(_ids_for_pane("self"))
	_sel_container.set_ids(_ids_for_pane("container"))

func select_row(pane: String, index: int, additive: bool, range_sel: bool) -> void:
	var m := _model_for_pane(pane)
	if range_sel:
		m.select_range_to(index)
	elif additive:
		m.toggle(index)
	else:
		m.select_single(index)
	_render()

func get_selected_ids(pane: String) -> Array:
	return _model_for_pane(pane).get_selected_ids()

# --- equip / unequip (SELF) ---

## Equips the single selected carry-list item into its slot. The item leaves the carry
## list (worn != carried); any displaced occupant returns to the carry list.
func equip_selected() -> bool:
	if _player_inv == null or _equip == null:
		return false
	var sel: Array = _sel_self.get_selected_ids()
	if sel.size() != 1:
		return false
	var item_id: String = String(sel[0])
	if _player_inv.get_quantity(item_id) <= 0 or not _equip.can_equip(item_id):
		return false
	var res: Dictionary = _equip.equip(item_id)
	if not bool(res.get("ok", false)):
		return false
	_player_inv.remove_item(item_id, 1)
	var displaced: String = str(res.get("displaced", ""))
	if displaced != "":
		_player_inv.add_item(displaced, 1)
	_after_mutation()
	return true

func unequip_slot(slot_id: String) -> bool:
	if _player_inv == null or _equip == null:
		return false
	var item_id: String = _equip.unequip(slot_id)
	if item_id == "":
		return false
	_player_inv.add_item(item_id, 1)
	_after_mutation()
	return true

# --- encumbrance badge ---

func get_load_badge() -> String:
	if _player_inv == null:
		return "OK"
	var r: float = _player_inv.get_load_ratio()
	if r <= 1.0:
		return "OK"
	if r <= 1.25:
		return "HEAVY"
	return "OVERLOADED"

func _move_speed_mult() -> float:
	if _player_inv == null:
		return 1.0
	return EncumbranceScript.move_speed_multiplier(_player_inv.get_load_ratio())

# --- shared post-mutation hook ---

func _after_mutation() -> void:
	_rebuild_models()
	_render()
	transfer_completed.emit()

# --- rendering (text mirror; the visual pass is the hand-built panel above) ---

func _render() -> void:
	if _root_label == null:
		return
	var lines: PackedStringArray = PackedStringArray()
	if _mode == "self":
		lines.append("INVENTORY + GEAR")
		lines.append(_weight_line())
		lines.append("-- Equipment --")
		for slot in _equip.SLOTS if _equip != null else []:
			var worn: String = _equip.get_equipped(slot) if _equip != null else ""
			lines.append("  %s: %s" % [slot, ("(empty)" if worn == "" else _name(worn))])
		lines.append("-- Carrying --")
		for id in _ids_for_pane("self"):
			lines.append("  %s" % _row_text(_player_inv, id))
	elif _mode == "transfer":
		lines.append("TRANSFER  |  %s" % _container_label)
		lines.append("YOU  %s" % _weight_line())
		for id in _ids_for_pane("self"):
			lines.append("  Y %s" % _row_text(_player_inv, id))
		for id in _ids_for_pane("container"):
			lines.append("  C %s" % _row_text(_container, id))
	_root_label.text = "\n".join(lines)

func _weight_line() -> String:
	if _player_inv == null:
		return ""
	return "Wt %.1f/%.1f [%s] x%.2f" % [
		_player_inv.get_total_weight(), _player_inv.get_capacity(),
		get_load_badge(), _move_speed_mult(),
	]

func _row_text(inv, id: String) -> String:
	return "%s x%d" % [_name(id), int(inv.get_quantity(id))]

func _name(id: String) -> String:
	return ItemDefsScript.display_name(_defs, id)
```

- [ ] **Step 4: Run it — expect PASS:**

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/inventory_panel_smoke.gd 2>&1
```
Expected: `INVENTORY PANEL SMOKE PASS section_a=true`.

- [ ] **Step 5: Commit:**

```bash
git add scripts/ui/inventory_panel.gd scripts/validation/inventory_panel_smoke.gd
git commit  # feat(inventory): InventoryPanel SELF mode (inventory + equip/unequip + Heavy-Load badge)
```

---

### Task 4: InventoryPanel — TRANSFER mode + drag-and-drop

**Files:**
- Modify: `scripts/ui/inventory_panel.gd` (add TRANSFER methods + Godot DnD overrides)
- Modify: `scripts/validation/inventory_panel_smoke.gd` (add Section B)

**Interfaces:**
- Consumes: `CargoTransfer.move_item`/`move_items` (Task 1); the SELF scaffold (Task 3).
- Produces: `open_transfer(player_inv, container_hold, container_label, equip)`; `transfer_selected(from_pane: String) -> int`; `transfer_quantity(from_pane: String, item_id: String, qty: int) -> int`; `deposit_all_to_container() -> int`; Godot overrides `_get_drag_data`, `_can_drop_data`, `_drop_data` delegating to the logical API.

- [ ] **Step 1: Add Section B to `scripts/validation/inventory_panel_smoke.gd`** — change `_init` and append `_run_section_b`:

```gdscript
func _init() -> void:
	await _run_section_a()
	await _run_section_b()
	print("INVENTORY PANEL SMOKE PASS section_a=true section_b=true")
	quit()
```

```gdscript
func _run_section_b() -> void:
	const ShipInventoryScript := preload("res://scripts/systems/ship_inventory.gd")
	var inv = InventoryStateScript.new()
	inv.add_item("scrap_metal", 6)        # part
	inv.add_tool("portable_oxygen_pump")  # tool (transferable manually)
	var hold = ShipInventoryScript.create(1000.0)
	hold.add_item("plating", 4)
	var equip = EquipmentStateScript.create()

	var panel = InventoryPanelScript.new()
	root.add_child(panel)
	await process_frame
	panel.open_transfer(inv, hold, "HOLD", equip)
	assert(panel.get_mode() == "transfer", "transfer mode")

	# select the scrap row on YOU and transfer the whole stack into the hold
	var you_ids: Array = panel.get_pane_ids("self")
	panel.select_row("self", you_ids.find("scrap_metal"), false, false)
	var moved: int = panel.transfer_selected("self")
	assert(moved == 6, "moved the whole scrap stack (got %d)" % moved)
	assert(hold.get_quantity("scrap_metal") == 6 and inv.get_quantity("scrap_metal") == 0, "scrap now in hold")

	# split: move 1 plating back to the player
	var one: int = panel.transfer_quantity("container", "plating", 1)
	assert(one == 1 and inv.get_quantity("plating") == 1 and hold.get_quantity("plating") == 3, "split moved exactly 1")

	# tool is transferable into the hold
	panel.select_row("self", panel.get_pane_ids("self").find("portable_oxygen_pump"), false, false)
	assert(panel.transfer_selected("self") == 1, "tool transferred to hold")
	assert(hold.get_quantity("portable_oxygen_pump") == 1, "tool stored in hold")

	# deposit-all convenience excludes tools and remaining items move
	inv.add_item("ration_pack", 3)
	var bulk: int = panel.deposit_all_to_container()
	assert(bulk >= 3, "deposit-all moved the supplies (got %d)" % bulk)

	# drag-data round-trips through the logical API
	panel.select_row("self", 0, false, false)
	var drag = panel._build_drag_payload("self")
	assert(drag.get("from_pane") == "self" and (drag.get("ids") as Array).size() >= 1, "drag payload carries selection")

	panel.queue_free()
```

- [ ] **Step 2: Run it — expect FAIL** (`open_transfer`/`transfer_selected` not defined):

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/inventory_panel_smoke.gd 2>&1
```

- [ ] **Step 3: Add TRANSFER methods + DnD overrides to `scripts/ui/inventory_panel.gd`** — insert after `close()` add the opener, and append the rest before `_render` (order within the file is not significant):

```gdscript
func open_transfer(player_inv, container_hold, container_label: String, equip) -> void:
	_player_inv = player_inv
	_container = container_hold
	_container_label = container_label
	_equip = equip
	_mode = "transfer"
	visible = true
	_rebuild_models()
	_render()
```

```gdscript
# --- transfer (TRANSFER mode) ---

func _other_pane(pane: String) -> String:
	return "container" if pane == "self" or pane == "you" else "self"

func _inv_for_pane(pane: String):
	return _container if pane == "container" else _player_inv

## Move every selected whole stack from from_pane to the other pane. Returns total moved.
func transfer_selected(from_pane: String) -> int:
	if _mode != "transfer":
		return 0
	var src = _inv_for_pane(from_pane)
	var dst = _inv_for_pane(_other_pane(from_pane))
	if src == null or dst == null:
		return 0
	var id_to_qty: Dictionary = {}
	for id in _model_for_pane(from_pane).get_selected_ids():
		id_to_qty[String(id)] = int(src.get_quantity(String(id)))
	var moved: int = CargoTransferScript.move_items(src, dst, id_to_qty)
	if moved > 0:
		_after_mutation()
	return moved

## Split: move exactly qty of one id from from_pane to the other pane.
func transfer_quantity(from_pane: String, item_id: String, qty: int) -> int:
	if _mode != "transfer":
		return 0
	var src = _inv_for_pane(from_pane)
	var dst = _inv_for_pane(_other_pane(from_pane))
	var moved: int = CargoTransferScript.move_item(src, dst, item_id, qty)
	if moved > 0:
		_after_mutation()
	return moved

## "A" convenience: bulk deposit part+supply (tools excluded) into the container.
func deposit_all_to_container() -> int:
	if _mode != "transfer" or _player_inv == null or _container == null:
		return 0
	var moved: int = int(CargoTransferScript.deposit_all(_player_inv, _container).get("total_moved", 0))
	if moved > 0:
		_after_mutation()
	return moved

# --- Godot drag-and-drop overrides (thin; the smokes call the logical API above) ---

## The drag payload the mouse path and the smokes both use.
func _build_drag_payload(pane: String) -> Dictionary:
	return {"from_pane": pane, "ids": _model_for_pane(pane).get_selected_ids()}

func _get_drag_data(_at_position: Vector2) -> Variant:
	# In the full visual build the dragged pane is resolved from the row under the
	# cursor; the logical move is identical to _build_drag_payload + _drop_*.
	var pane: String = "self"
	if _mode == "transfer" and _sel_container.get_selected_ids().size() > 0:
		pane = "container"
	var data: Dictionary = _build_drag_payload(pane)
	var preview := Label.new()
	preview.text = "%d item(s)" % (data["ids"] as Array).size()
	set_drag_preview(preview)
	return data

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and (data as Dictionary).has("from_pane")

## drop_target: "self"/"container" pane, or "slot:<slot_id>" for an equipment slot.
func _drop_to(drop_target: String, data: Dictionary) -> void:
	var from_pane: String = String(data.get("from_pane", ""))
	if drop_target.begins_with("slot:"):
		# equip the first dragged equippable
		for id in (data.get("ids", []) as Array):
			if _equip != null and _equip.can_equip(String(id)):
				_model_for_pane(from_pane).select_single(_ids_for_pane(from_pane).find(String(id)))
				equip_selected()
				return
		return
	if _mode == "transfer" and drop_target != from_pane:
		transfer_selected(from_pane)

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if not (data is Dictionary):
		return
	# Default visual drop target is the opposite pane; the full build resolves the
	# control under the cursor. Smokes exercise transfer_selected/_drop_to directly.
	var from_pane: String = String((data as Dictionary).get("from_pane", "self"))
	_drop_to(_other_pane(from_pane), data as Dictionary)
```

- [ ] **Step 4: Run it — expect PASS:**

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/inventory_panel_smoke.gd 2>&1
```
Expected: `INVENTORY PANEL SMOKE PASS section_a=true section_b=true`.

- [ ] **Step 5: Commit:**

```bash
git add scripts/ui/inventory_panel.gd scripts/validation/inventory_panel_smoke.gd
git commit  # feat(inventory): InventoryPanel TRANSFER mode + per-item move + drag-data plumbing
```

---

### Task 5: Coordinator wiring

**Files:**
- Modify: `scripts/procgen/playable_generated_ship.gd`
- Modify: `scripts/validation/cargo_hold_smoke.gd` (keep green after the interact repoint)

**Interfaces:**
- Consumes: `InventoryPanel` (Task 3/4); `_build_hud_layer` (line ~2347), `_ensure_key_action_set` (line ~3228), `_on_scanner_panel_closed` (line ~2376), the cargo/cart handlers (lines ~1586–1627), `_recompute_player_encumbrance` (line ~1632), `_refresh_oxygen_state(false, 0.0)` (line ~3119), `cargo_interact_deposit_for_validation` (line ~4942), `_find_ship_by_id`, `_find_cart_by_id`.
- Produces: an owned `inventory_panel` field; runtime `toggle_inventory` (KEY_I); panel opens from the four container handlers + the toggle; player freeze/restore on open/close; encumbrance + oxygen refresh on `transfer_completed`; validation seams (below).

- [ ] **Step 1 (test first): Update `scripts/validation/cargo_hold_smoke.gd` Section B** so it asserts the NEW interact behaviour (interact opens the transfer panel; deposit-all happens through the panel). Replace lines 53–61 (the deposit block) with:

```gdscript
	# Seed the player, walk up + interact. Interact now OPENS the transfer panel for the
	# hold (it no longer auto-bulk-deposits). cargo_interact_deposit_for_validation drives
	# the real interact dispatch and then triggers the panel's deposit-all, returning the
	# moved count — a return of 0 means the control is not wired into the interact path.
	ship.inventory_state.add_item("scrap_metal", 6)
	var deposited: int = ship.cargo_interact_deposit_for_validation(home_id)
	assert(ship.inventory_panel_is_open_for_validation(), "interact at hold opened the transfer panel")
	assert(deposited == 6, "panel deposit-all moved 6 (got %d)" % deposited)
	assert(ship.ship_hold_quantity_for_validation(home_id, "scrap_metal") == 6, "hold holds 6")
	assert(ship.inventory_state.get_quantity("scrap_metal") == 0, "player emptied of part")
	ship.inventory_close_for_validation()
```

- [ ] **Step 2: Run cargo_hold_smoke — expect FAIL** (`inventory_panel_is_open_for_validation` not defined yet):

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/cargo_hold_smoke.gd 2>&1
```

- [ ] **Step 3: Register the action** — in `scripts/procgen/playable_generated_ship.gd`, immediately after the existing `_ensure_key_action_set("toggle_scanner", [KEY_TAB])` (line ~290), add:

```gdscript
	_ensure_key_action_set("toggle_inventory", [KEY_I])
```

- [ ] **Step 4: Own the panel** — add the field near `var hud_layer: CanvasLayer` (line ~113):

```gdscript
var inventory_panel
```

and the preload near the other UI preloads (top of file, by `ObjectiveTrackerScript`):

```gdscript
const InventoryPanelScript := preload("res://scripts/ui/inventory_panel.gd")
```

In `_build_hud_layer()` (after the `scanner_panel` block, line ~2374), add:

```gdscript
	inventory_panel = InventoryPanelScript.new()
	inventory_panel.name = "InventoryPanel"
	inventory_panel.visible = false
	hud_layer.add_child(inventory_panel)
	inventory_panel.panel_closed.connect(_on_inventory_panel_closed)
	inventory_panel.transfer_completed.connect(_on_inventory_transfer_completed)
```

In `_reset_runtime_for_reload` teardown (where `scanner_panel = null`, line ~4660), add:

```gdscript
	inventory_panel = null
```

- [ ] **Step 5: Add the open/close/transfer handlers** — add near `_on_scanner_panel_closed` (line ~2376):

```gdscript
func _freeze_player_for_panel() -> void:
	if player != null:
		player.set_physics_process(false)
		player.set_process_input(false)
		player.set_process_unhandled_input(false)

func _on_inventory_panel_closed() -> void:
	if player != null:
		player.set_physics_process(true)
		player.set_process_input(true)
		player.set_process_unhandled_input(true)

## A transfer/equip mutated player state: refresh carry budget (Heavy Load) and oxygen
## (the O2-pump drain benefit follows the pump in/out of the player inventory).
func _on_inventory_transfer_completed() -> void:
	_recompute_player_encumbrance()
	_refresh_oxygen_state(false, 0.0)

func _open_inventory_self() -> void:
	if inventory_panel == null or inventory_state == null:
		return
	inventory_panel.open_self(inventory_state, equipment_state)
	_freeze_player_for_panel()

func _open_transfer_panel_for_ship(ship_id: String) -> void:
	if inventory_panel == null or inventory_state == null:
		return
	var inst = _find_ship_by_id(ship_id)
	if inst == null:
		return
	inventory_panel.open_transfer(inventory_state, inst.get_inventory(), "HOLD", equipment_state)
	_freeze_player_for_panel()

func _open_transfer_panel_for_cart(cart_id: String) -> void:
	if inventory_panel == null or inventory_state == null:
		return
	var hit: Dictionary = _find_cart_by_id(cart_id)
	if hit.is_empty():
		return
	inventory_panel.open_transfer(inventory_state, hit["cart"].get_hold(), "CART", equipment_state)
	_freeze_player_for_panel()
```

- [ ] **Step 6: Repoint the four container handlers** — replace the bodies of `_on_cargo_deposit_requested`, `_on_cargo_withdraw_requested`, `_on_cart_load_requested`, `_on_cart_unload_requested` (lines ~1593–1627) with panel-open calls (the `_on_cart_grab_requested` grab handler is unchanged):

```gdscript
func _on_cart_load_requested(cart_id: String) -> void:
	_open_transfer_panel_for_cart(cart_id)

func _on_cart_unload_requested(cart_id: String, _category: String) -> void:
	_open_transfer_panel_for_cart(cart_id)

func _on_cargo_deposit_requested(ship_id: String) -> void:
	_open_transfer_panel_for_ship(ship_id)

func _on_cargo_withdraw_requested(ship_id: String, _category: String) -> void:
	_open_transfer_panel_for_ship(ship_id)
```

- [ ] **Step 7: Handle `toggle_inventory` + panel input in `_input`** — in `func _input` (line ~4729), insert this block right after the `scanner_panel` exclusivity block (after line ~4755, before the `save_load_service` block):

```gdscript
	if inventory_panel != null:
		if inventory_panel.is_open():
			if event.is_action_pressed("toggle_inventory") or event.is_action_pressed("ui_cancel"):
				inventory_panel.close()
				get_viewport().set_input_as_handled()
			return  # swallow other keys while the inventory panel is open (mouse drives it)
		if event.is_action_pressed("toggle_inventory"):
			_open_inventory_self()
			get_viewport().set_input_as_handled()
			return
```

- [ ] **Step 8: Add validation seams** — add near the other `*_for_validation` seams (after `cargo_withdraw_for_validation`, line ~4924):

```gdscript
func inventory_panel_is_open_for_validation() -> bool:
	return inventory_panel != null and inventory_panel.is_open()

func inventory_open_self_for_validation() -> bool:
	_open_inventory_self()
	return inventory_panel_is_open_for_validation()

func inventory_close_for_validation() -> void:
	if inventory_panel != null and inventory_panel.is_open():
		inventory_panel.close()

func inventory_panel_deposit_all_for_validation() -> int:
	if inventory_panel == null or not inventory_panel.is_open():
		return 0
	return int(inventory_panel.deposit_all_to_container())

func inventory_transfer_first_to_container_for_validation(item_id: String) -> int:
	# Open-transfer must already be active. Selects item_id on the YOU pane and moves the
	# whole stack into the container; returns moved.
	if inventory_panel == null or not inventory_panel.is_open():
		return 0
	var ids: Array = inventory_panel.get_pane_ids("self")
	var idx: int = ids.find(item_id)
	if idx < 0:
		return 0
	inventory_panel.select_row("self", idx, false, false)
	return int(inventory_panel.transfer_selected("self"))

func inventory_transfer_first_from_container_for_validation(item_id: String) -> int:
	if inventory_panel == null or not inventory_panel.is_open():
		return 0
	var ids: Array = inventory_panel.get_pane_ids("container")
	var idx: int = ids.find(item_id)
	if idx < 0:
		return 0
	inventory_panel.select_row("container", idx, false, false)
	return int(inventory_panel.transfer_selected("container"))

func player_frozen_for_validation() -> bool:
	return player != null and not player.is_physics_processing()
```

- [ ] **Step 9: Update `cargo_interact_deposit_for_validation`** (line ~4942) so it triggers the panel deposit-all after interact (the interact now opens the panel). Replace the body from `var before:` to the `return`:

```gdscript
	(player as Node3D).global_position = control.global_position
	var before: int = _hold_item_total(inst)
	_on_player_interact_requested(player)   # opens the transfer panel for this hold
	inventory_panel_deposit_all_for_validation()
	return _hold_item_total(inst) - before
```

- [ ] **Step 10: Run the affected smokes — expect PASS:**

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/cargo_hold_smoke.gd 2>&1
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/cart_state_smoke.gd 2>&1
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/cart_control_smoke.gd 2>&1
```
Expected: `CARGO HOLD SMOKE PASS ...`, `CART STATE SMOKE PASS ...`, `CART CONTROL SMOKE PASS ...`, each with no non-allowlisted `ERROR:`/`WARNING:`. (cart_state/cart_control call `CargoTransfer` directly and must still pass; if either regresses, the repoint touched a path it should not have — fix before continuing.)

- [ ] **Step 11: Commit:**

```bash
git add scripts/procgen/playable_generated_ship.gd scripts/validation/cargo_hold_smoke.gd
git commit  # feat(inventory): wire InventoryPanel into the coordinator (open from container, freeze/restore, recompute on transfer)
```

---

### Task 6: Main-scene slice smoke

**Files:**
- Create: `scripts/validation/main_playable_slice_inventory_ui_smoke.gd`

**Interfaces:**
- Consumes: the Task 5 seams — `inventory_open_self_for_validation`, `player_frozen_for_validation`, `inventory_close_for_validation`, `_open_transfer_panel_for_ship`, `inventory_transfer_first_to_container_for_validation`, `inventory_transfer_first_from_container_for_validation`, `inventory_panel_is_open_for_validation`, `home_ship_id_for_validation`, `ship_hold_quantity_for_validation`. `oxygen_state.get_summary()` exposes `drain_multiplier`.
- Produces: marker `INVENTORY UI SLICE SMOKE PASS`.

- [ ] **Step 1: Write the test** — create `scripts/validation/main_playable_slice_inventory_ui_smoke.gd`:

```gdscript
extends SceneTree

## Phase 7 slice smoke: the inventory/transfer panel inside the live playable ship.
## Proves: toggle opens SELF and freezes the player; close restores control; per-item
## transfer at a hold moves a stack both ways; and storing the O2 pump in a hold reverts
## the oxygen drain multiplier to 1.0 (withdraw restores 0.5) — the tool-storage wiring.

const PlayableGeneratedShipScript := preload("res://scripts/procgen/playable_generated_ship.gd")

func _init() -> void:
	await _run()
	quit()

func _run() -> void:
	var ship = PlayableGeneratedShipScript.new()
	root.add_child(ship)
	for _i in range(3):
		await process_frame

	# SELF open freezes the player; close restores.
	assert(ship.inventory_open_self_for_validation(), "toggle opened the inventory")
	assert(ship.player_frozen_for_validation(), "player frozen while panel open")
	ship.inventory_close_for_validation()
	for _j in range(2):
		await process_frame
	assert(not ship.player_frozen_for_validation(), "player control restored on close")

	# Per-item transfer at the home hold.
	var home_id: String = ship.home_ship_id_for_validation()
	ship.inventory_state.add_item("scrap_metal", 6)
	ship._open_transfer_panel_for_ship(home_id)
	assert(ship.inventory_panel_is_open_for_validation(), "transfer panel open at hold")
	var moved: int = ship.inventory_transfer_first_to_container_for_validation("scrap_metal")
	assert(moved == 6, "transferred 6 scrap into the hold (got %d)" % moved)
	assert(ship.ship_hold_quantity_for_validation(home_id, "scrap_metal") == 6, "hold has 6")
	var back: int = ship.inventory_transfer_first_from_container_for_validation("scrap_metal")
	assert(back == 6, "withdrew 6 back to the player (got %d)" % back)
	ship.inventory_close_for_validation()

	# Tool storage drives the oxygen drain multiplier live.
	ship.inventory_state.add_tool("portable_oxygen_pump")
	ship._open_transfer_panel_for_ship(home_id)
	ship._refresh_oxygen_state(false, 0.0)
	var with_pump: float = float(ship.oxygen_state.get_summary().get("drain_multiplier", 1.0))
	assert(abs(with_pump - 0.5) < 0.001, "pump on player -> drain 0.5 (got %s)" % str(with_pump))
	var dep: int = ship.inventory_transfer_first_to_container_for_validation("portable_oxygen_pump")
	assert(dep == 1, "deposited the pump into the hold")
	var stored: float = float(ship.oxygen_state.get_summary().get("drain_multiplier", 1.0))
	assert(abs(stored - 1.0) < 0.001, "pump stored -> drain 1.0 (got %s)" % str(stored))
	var wd: int = ship.inventory_transfer_first_from_container_for_validation("portable_oxygen_pump")
	assert(wd == 1, "withdrew the pump")
	var restored: float = float(ship.oxygen_state.get_summary().get("drain_multiplier", 1.0))
	assert(abs(restored - 0.5) < 0.001, "pump back -> drain 0.5 (got %s)" % str(restored))
	ship.inventory_close_for_validation()
	ship.queue_free()

	print("INVENTORY UI SLICE SMOKE PASS moved=%d stored_mult=%s" % [moved, str(stored)])
```

- [ ] **Step 2: Run it — expect FAIL first** (if any seam name/behaviour is off), then iterate to PASS:

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_inventory_ui_smoke.gd 2>&1
```
Expected on success: `INVENTORY UI SLICE SMOKE PASS moved=6 stored_mult=1` with no non-allowlisted `ERROR:`/`WARNING:`.

> If `oxygen_state.get_summary()` does not expose `drain_multiplier` under this key, read `scripts/systems/oxygen_state.gd` and assert the actual key it round-trips the inventory drain through — do not invent a key.

- [ ] **Step 3: Commit:**

```bash
git add scripts/validation/main_playable_slice_inventory_ui_smoke.gd
git commit  # test(inventory): main-scene inventory-UI slice smoke (freeze, transfer, tool-storage oxygen)
```

---

### Task 7: Docs — ADR, bundle registration, roadmap

**Files:**
- Create: `docs/game/adr/0022-inventory-transfer-ui.md`
- Modify: `docs/game/06_validation_plan.md`
- Modify: `docs/game/09_system_roadmap.md`

- [ ] **Step 1: Create the ADR** — `docs/game/adr/0022-inventory-transfer-ui.md`:

```markdown
# ADR-0022: Inventory & Transfer UI (Phase 7 slice 1)

Date: 2026-06-23
Status: Accepted

## Context
System 6 built the inventory/equipment/cargo/cart models but deferred the player-facing
UI to Phase 7. This slice delivers the interactive screen.

## Decisions
1. **Hand-built theme, no external asset kit.** The Godot Asset Library has no usable
   game-UI skins; itch kits were surveyed and declined. The panel uses `StyleBoxFlat`
   matching `ObjectiveTracker`/`ScannerPanel`.
2. **Physical open model.** Interact (`E`) at a hold/cart opens TRANSFER mode;
   `toggle_inventory` (`I`, registered at runtime) opens SELF mode. Supersedes the bulk
   deposit/withdraw prompts; bulk deposit-all survives as the panel's convenience action.
3. **Mouse-driven** drag-and-drop, shift/ctrl multi-select, right-click context menus —
   list-with-icons layout (not a slot grid), matching our weight/quantity model.
4. **Item icons deferred** behind an `ItemDefs.icon` reader with a category-swatch
   fallback; no icon art in this slice.
5. **Tools transferable** via manual move; bulk `deposit_all` still excludes them.
   Depositing the O2 pump reverts the oxygen drain multiplier live (×1.0), withdrawing
   restores ×0.5, via `_on_inventory_transfer_completed` → `_refresh_oxygen_state`.
6. **Model/Node split.** Pure `InventorySelectionModel` (selection math + action
   resolver, fully smoke-tested) + thin `InventoryPanel` Control whose mouse/DnD
   overrides delegate to a headless-queryable logical API. Only literal pixel-drag
   plumbing is lightly covered.
7. **No new persisted state**; `world-4` unchanged. The panel is a pure view.

## Consequences
The player can now view inventory + worn gear and move salvage per-item to/from holds
and carts. Deferred: item-icon generation, partial-stack split UX polish, slot/volume
model, floor-drop, gamepad nav, the B/C/D Phase-7 sub-slices.
```

- [ ] **Step 2: Register the four smokes in `docs/game/06_validation_plan.md`** — add four `run_clean` lines in the bundle (matching the existing flat format) and bump the final echo from `commands=110` to `commands=114`. The four lines (use the exact marker substrings):

```bash
run_clean 'cargo move-item primitive' 'CARGO MOVE ITEM SMOKE PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/cargo_move_item_smoke.gd
run_clean 'inventory selection model' 'INVENTORY SELECTION MODEL SMOKE PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/inventory_selection_model_smoke.gd
run_clean 'inventory panel' 'INVENTORY PANEL SMOKE PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/inventory_panel_smoke.gd
run_clean 'inventory UI slice' 'INVENTORY UI SLICE SMOKE PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_inventory_ui_smoke.gd
```

Update the final line to:

```bash
echo 'SARGASSO REGRESSION PASS commands=114 clean_output=true'
```

> Sanity: `grep -c '^run_clean' docs/game/06_validation_plan.md` will report **115** — that counts the `run_clean() {` definition line plus 114 invocations. The echo says `commands=114`.

- [ ] **Step 3: Update `docs/game/09_system_roadmap.md`** — in the System 6 row, change `~80%` to `~85%` and append to the *Remaining* list that the inventory/transfer UI (Phase 7 slice A) is **built**, leaving icon generation, split-UX polish, and the B/C/D sub-slices. In the build-phase crosswalk, mark Phase 7 as `🟡 in progress (slice A: inventory/transfer UI built)`.

- [ ] **Step 4: Run the FULL regression bundle to confirm 114 green.** The local `project.godot` carries an `MCPRuntime` autoload that breaks headless; stash it for the bundle only, then restore:

```bash
git stash push -- project.godot
bash docs/game/06_validation_plan.md   # or the documented bundle runner with GODOT/ROOT set
git stash pop
```
Expected tail: `SARGASSO REGRESSION PASS commands=114 clean_output=true`. Do not commit or revert the `project.godot` drift.

- [ ] **Step 5: Commit:**

```bash
git add docs/game/adr/0022-inventory-transfer-ui.md docs/game/06_validation_plan.md docs/game/09_system_roadmap.md
git commit  # docs(inventory): ADR-0022 + register inventory-UI smokes (110->114) + roadmap
```

---

## Self-Review (performed during planning)

**1. Spec coverage:**
- §2 decision 1 (hand-built theme) → Task 3 `StyleBoxFlat` panel. ✓
- §2 decision 2 (physical open: E→transfer, I→self) → Task 5 steps 3,6,7. ✓
- §2 decision 3 (mouse DnD + shift/ctrl multi-select + right-click) → Task 2 selection math + Task 4 DnD overrides/context payload. ✓
- §2 decision 4 (list-with-icons) → Task 3 render. ✓
- §2 decision 5 (icons deferred, swatch fallback, `icon` reader) → Task 1 `ItemDefs.icon`. ✓
- §2 decision 6 (tools transferable, bulk excludes, oxygen live) → Task 1 (move allows tools), Task 5 step 5 `_on_inventory_transfer_completed`, Task 6 oxygen assertions. ✓
- §2 decision 7 / §3 (Model/Node split) → Task 2 model + Task 3/4 thin Control. ✓
- §5 (`move_item`/`move_items` cap semantics) → Task 1. ✓
- §6 (coordinator wiring, runtime action, recompute+oxygen on transfer) → Task 5. ✓
- §10 (no persistence change) → no save code touched; `world-4` untouched. ✓
- §11 (four smokes + markers + bundle + ADR-0022) → Tasks 1,2,3/4,6,7. ✓

**2. Placeholder scan:** no "TBD"/"handle edge cases"/"similar to Task N" — every code step shows full code. The single forward-looking note (Task 6 step 2 oxygen-key check) names the exact file to read and forbids inventing a key. ✓

**3. Type consistency:** `move_item(src,dst,item_id,qty)`, `move_items(src,dst,id_to_qty)`, `context_actions(item_id,defs,in_transfer_mode,dest_is_container,is_equipped_slot)`, `open_self(inv,equip)`, `open_transfer(player_inv,container_hold,container_label,equip)`, `transfer_selected(from_pane)`, `transfer_quantity(from_pane,item_id,qty)`, `deposit_all_to_container()`, pane keys `"self"`/`"container"` — all consistent across tasks and matched to the verified model signatures (`InventoryState.add_item` soft-cap, `ShipInventory.add_item` hard-cap, `EquipmentState.equip` returns `{ok,displaced}`, `CartState.get_hold()`). ✓
