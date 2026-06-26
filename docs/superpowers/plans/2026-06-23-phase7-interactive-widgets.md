# Phase 7 Slice 2 — InventoryPanel Interactive Widget Layer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the inventory/transfer panel genuinely mouse-driven — replace the text-mirror render with a real widget tree of custom row Controls supporting click/shift/ctrl select, drag-and-drop across panes and onto equipment slots, and right-click context menus (with a precise Split amount picker).

**Architecture:** Two new thin Control scripts (`inventory_row.gd`, `inventory_drop_zone.gd`) that forward all mouse events to coordinator callbacks on `InventoryPanel`. The panel's `_render()` rebuilds a widget tree (header + panes of rows + equipment slots + buttons) instead of setting a label's text. The slice-1 model/logic layer (`InventorySelectionModel`, `CargoTransfer`, the panel's logical API) is **unchanged**; the new code is render + mouse wiring only.

**Tech Stack:** Godot 4.6.2, typed GDScript, Forward+. Headless `--script` SceneTree validation smokes with single PASS-marker contracts.

## Global Constraints

- **Engine/binary:** `GODOT="C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe"`; `ROOT="C:/Users/dasbl/Documents/The Synaptic Sea"`. Run smokes headless: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/<name>.gd 2>&1`. **Markers print to stderr — always append `2>&1`.** Never trust exit code alone; confirm the PASS-marker line is present.
- **Definition of done = fresh PASS-marker output.** Register new smokes in `docs/game/06_validation_plan.md`.
- **Typed GDScript** for new code.
- **Purely additive — no new persisted state, no save-format change.** `WORLD_SLICE_VERSION` stays `"world-4"`. The slice-1 logic smokes (`inventory_panel_smoke`, `inventory_selection_model_smoke`, `cargo_move_item_smoke`, `main_playable_slice_inventory_ui_smoke`) MUST stay green — they assert the logical API, not the render.
- **Do NOT stage/commit:** `project.godot`, `.godot/`, `*.uid`, `addons/`. Use selective `git add <explicit paths>` only.
- **Headless class-cache:** newly-added `class_name` globals are unreliable under `--headless --script`. New Controls are constructed via a `load()`-self-reference `create(...)` factory (mirrors `ShipInventory.create`/`CartState.create`); smokes type via preloaded `const`, never the `class_name` global.
- **GDScript `match` pitfall:** `match x: SOME_CONST:` *binds* `SOME_CONST` to `x` (always matches) instead of comparing. The context-action dispatch MUST use `if/elif` against the integer id consts, not `match`. (String-literal `match` cases like `"transfer"` are fine — literals compare.)
- **Popups are not headless-safe to `.popup()`** — separate menu BUILDING from popping: `_build_context_menu(...)` returns a populated `PopupMenu` without popping; smokes assert on the built menu, never call `.popup()`.
- **Allowlisted headless noise (ignore):** `ERROR: Capture not registered: 'gdaimcp'.`, `WARNING: ObjectDB instances leaked at exit`; for full-scene runs with the local `project.godot` drift also `Unrecognized UID` / `Resource file not found: res://` / `Failed to instantiate an autoload 'MCPRuntime'`. Any other `ERROR:`/`WARNING:` blocks completion.
- **Commit style:** Conventional Commits; every commit message ends with `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.
- **Branch:** `phase7-interactive-widgets` (created off merged `main`; spec committed at `544c475`).
- **Spec:** `docs/superpowers/specs/2026-06-23-phase7-interactive-widgets-design.md`.

---

## File Structure

| File | Responsibility | Task |
|------|----------------|------|
| `scripts/ui/inventory_panel.gd` (modify) | Coordinator callbacks (`row_*`/`zone_*`/`transfer_all_from`/`slot_context`/`_build_context_menu`/`_on_context_id`/`_open_split_picker`/`pane_quantity`); then `_ready`/`_render` widget-tree rebuild + `_rows`/`_zones`/`row_at`/`zone_for`; remove panel-level DnD overrides | 1, 2 |
| `scripts/ui/inventory_row.gd` (create) | Selectable / draggable / right-clickable row Control; forwards to panel | 2 |
| `scripts/ui/inventory_drop_zone.gd` (create) | Pane + equipment-slot drop target; right-click on a slot; forwards to panel | 2 |
| `scripts/validation/inventory_widget_smoke.gd` (create, then extend) | Section A: callbacks driven directly (T1). Section B: real widgets driven with synthetic input (T2) | 1, 2 |
| `docs/game/adr/0023-inventory-widget-layer.md` (create) | Record widget-layer decisions | 3 |
| `docs/game/06_validation_plan.md` (modify) | Register the widget smoke (114 → 115) | 3 |
| `docs/game/09_system_roadmap.md` (modify) | Note slice-2 built | 3 |

---

### Task 1: Panel coordinator callbacks (logic)

Add the coordinator callbacks the widgets will call, plus the context-menu builder/dispatch, `transfer_all_from`, the split picker, and `pane_quantity`. The render stays text for this task (the widget tree lands in Task 2). All callbacks operate on the existing models, so they are testable by calling them directly.

**Files:**
- Modify: `scripts/ui/inventory_panel.gd` (add callbacks; render unchanged this task)
- Create: `scripts/validation/inventory_widget_smoke.gd`

**Interfaces:**
- Consumes (slice 1, unchanged): `select_row(pane, index, additive, range_sel)`, `_model_for_pane(pane)`, `_ids_for_pane(pane)`, `_inv_for_pane(pane)`, `_other_pane(pane)`, `_build_drag_payload(pane)`, `transfer_selected(pane)`, `transfer_quantity(pane, id, qty)`, `equip_selected()`, `unequip_slot(slot)`, `_after_mutation()`, `_name(id)`; `InventorySelectionModel.context_actions(item_id, defs, in_transfer_mode, dest_is_container, is_equipped_slot)`; `CargoTransfer.move_items(src, dst, id_to_qty)`; `ItemDefs.equip_slot(defs, id)`; `EquipmentState.is_slot_occupied(slot)`.
- Produces: `row_clicked`, `row_drag_payload`, `row_context`, `zone_can_accept`, `zone_drop`, `transfer_all_from`, `slot_context`, `pane_quantity`, `_build_context_menu`, `_on_context_id`, `_open_split_picker`, and the `_ACT_*` id consts.

- [ ] **Step 1: Write the failing test** — create `scripts/validation/inventory_widget_smoke.gd`:

```gdscript
extends SceneTree

## InventoryPanel interactive-widget smoke. Section A (this task): the coordinator
## callbacks the row/zone widgets call, driven DIRECTLY (no widgets needed yet).
## Section B (Task 2) extends this with real widgets driven by synthetic input.

const InventoryPanelScript := preload("res://scripts/ui/inventory_panel.gd")
const InventoryStateScript := preload("res://scripts/systems/inventory_state.gd")
const EquipmentStateScript := preload("res://scripts/systems/equipment_state.gd")
const ShipInventoryScript := preload("res://scripts/systems/ship_inventory.gd")

func _init() -> void:
	await _run_section_a()
	print("INVENTORY WIDGET SMOKE PASS section_a=true")
	quit()

func _run_section_a() -> void:
	var inv = InventoryStateScript.new()
	inv.add_item("scrap_metal", 6)
	inv.add_item("ration_pack", 3)
	inv.add_item("eva_backpack", 1)        # equippable: back
	var hold = ShipInventoryScript.create(1000.0)
	hold.add_item("plating", 4)
	var equip = EquipmentStateScript.create()

	var panel = InventoryPanelScript.new()
	root.add_child(panel)
	await process_frame
	panel.open_transfer(inv, hold, "HOLD", equip)

	# row_clicked -> selection
	var you := panel.get_pane_ids("self")
	panel.row_clicked("self", you.find("scrap_metal"), false, false)
	assert(panel.get_selected_ids("self") == ["scrap_metal"], "row_clicked selected scrap")

	# row_drag_payload selects if needed + returns payload
	var drag = panel.row_drag_payload("self", you.find("ration_pack"))
	assert(drag != null and drag["from_pane"] == "self", "drag payload built")
	assert("ration_pack" in (drag["ids"] as Array), "payload carries the row id")

	# zone_can_accept / zone_drop across panes (transfer)
	panel.row_clicked("self", panel.get_pane_ids("self").find("scrap_metal"), false, false)
	var pay := {"from_pane": "self", "ids": ["scrap_metal"]}
	assert(panel.zone_can_accept("container", pay) == true, "container accepts a YOU drop")
	assert(panel.zone_can_accept("self", pay) == false, "same-pane drop refused")
	panel.zone_drop("container", pay)
	assert(hold.get_quantity("scrap_metal") == 6, "zone_drop moved the stack into the hold")

	# transfer_all_from moves every id (incl tools) from a pane
	inv.add_tool("portable_oxygen_pump")
	var moved_all := panel.transfer_all_from("self")
	assert(moved_all >= 1 and hold.get_quantity("portable_oxygen_pump") == 1, "transfer_all moved tool too")
	assert(panel.get_pane_ids("self").is_empty(), "YOU emptied by transfer_all")

	# equipment-slot drop equips (from the self pane only)
	inv.add_item("eva_backpack", 1)  # back in the player inventory again
	var slot_pay := {"from_pane": "self", "ids": ["eva_backpack"]}
	assert(panel.zone_can_accept("slot:back", slot_pay) == true, "back slot accepts the backpack")
	assert(panel.zone_can_accept("slot:suit", slot_pay) == false, "suit slot rejects a back item")
	panel.zone_drop("slot:back", slot_pay)
	assert(equip.get_equipped("back") == "eva_backpack", "slot drop equipped the backpack")

	# context menu: built (not popped) with the expected action set; dispatch works
	hold.add_item("plating", 4)  # ensure container has a row
	var cmenu = panel._build_context_menu("container", panel.get_pane_ids("container").find("plating"))
	var labels: Array = []
	for i in range(cmenu.item_count):
		labels.append(cmenu.get_item_text(i))
	assert("Transfer" in labels and "Transfer all" in labels and "Split…" in labels, "menu has transfer/all/split")
	cmenu.free()
	# dispatch Transfer all from the container -> everything back to the player
	panel._on_context_id(panel._ACT_TRANSFER_ALL, "container", 0, null)
	assert(inv.get_quantity("plating") >= 4, "context Transfer all pulled plating to player")

	panel.queue_free()
```

> Note: the smoke uses real ids (`scrap_metal`, `ration_pack`, `eva_backpack`, `plating`, `portable_oxygen_pump`) and `eva_backpack`'s `equip_slot=="back"` (System 6 data). `panel._ACT_TRANSFER_ALL` is a const read via the instance (legal in GDScript).

- [ ] **Step 2: Run it — expect FAIL** (callbacks not defined):

```bash
GODOT="C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe"; ROOT="C:/Users/dasbl/Documents/The Synaptic Sea"
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/inventory_widget_smoke.gd 2>&1
```
Expected: error referencing `row_clicked`/`zone_drop`/etc.

- [ ] **Step 3: Add the callbacks to `scripts/ui/inventory_panel.gd`** — insert this block after `_after_mutation()` (the existing function near the transfer methods). Use `if/elif` (NOT `match`) for the id dispatch:

```gdscript
# --- interactive-widget coordinator callbacks (rows/zones forward here) ---

const _ACT_TRANSFER := 0
const _ACT_TRANSFER_ALL := 1
const _ACT_SPLIT := 2
const _ACT_EQUIP := 3
const _ACT_UNEQUIP := 4

func row_clicked(pane: String, index: int, additive: bool, range_sel: bool) -> void:
	select_row(pane, index, additive, range_sel)

func row_drag_payload(pane: String, index: int) -> Variant:
	var m = _model_for_pane(pane)
	if not m.is_selected(index):
		m.select_single(index)
	var data: Dictionary = _build_drag_payload(pane)
	return null if (data["ids"] as Array).is_empty() else data

func row_context(pane: String, index: int, global_pos: Vector2) -> void:
	var m = _model_for_pane(pane)
	if not m.is_selected(index):
		m.select_single(index)
		_render()
	var menu: PopupMenu = _build_context_menu(pane, index)
	add_child(menu)
	menu.position = global_pos
	menu.id_pressed.connect(_on_context_id.bind(pane, index, menu))
	menu.popup()

## True iff `data` can drop on `target` ("self"/"container" pane, or "slot:<id>").
func zone_can_accept(target: String, data) -> bool:
	if not (data is Dictionary):
		return false
	var from_pane: String = String((data as Dictionary).get("from_pane", ""))
	if target.begins_with("slot:"):
		if from_pane != "self":
			return false   # equip only from your own inventory
		var slot: String = target.substr(5)
		for id in ((data as Dictionary).get("ids", []) as Array):
			if _equip != null and ItemDefsScript.equip_slot(_defs, String(id)) == slot:
				return true
		return false
	return _mode == "transfer" and target != from_pane

func zone_drop(target: String, data) -> void:
	if not (data is Dictionary):
		return
	var from_pane: String = String((data as Dictionary).get("from_pane", ""))
	if target.begins_with("slot:"):
		if from_pane != "self":
			return
		var slot: String = target.substr(5)
		for id in ((data as Dictionary).get("ids", []) as Array):
			if _equip != null and ItemDefsScript.equip_slot(_defs, String(id)) == slot:
				_sel_self.select_single(_ids_for_pane("self").find(String(id)))
				equip_selected()
				return
		return
	if _mode == "transfer" and target != from_pane:
		transfer_selected(from_pane)

## Move every id in `pane` to the other pane (manual — includes tools). Distinct from the
## Deposit All button, which uses deposit_all (parts/supplies only). Returns total moved.
func transfer_all_from(pane: String) -> int:
	var src = _inv_for_pane(pane)
	var dst = _inv_for_pane(_other_pane(pane))
	if src == null or dst == null:
		return 0
	var id_to_qty: Dictionary = {}
	for id in _ids_for_pane(pane):
		id_to_qty[String(id)] = int(src.get_quantity(String(id)))
	var moved: int = CargoTransferScript.move_items(src, dst, id_to_qty)
	if moved > 0:
		_after_mutation()
	return moved

func slot_context(slot_id: String, global_pos: Vector2) -> void:
	if _equip == null or not _equip.is_slot_occupied(slot_id):
		return
	var menu := PopupMenu.new()
	menu.add_item("Unequip", _ACT_UNEQUIP)
	add_child(menu)
	menu.position = global_pos
	menu.id_pressed.connect(func(_id): unequip_slot(slot_id); menu.queue_free())
	menu.popup()

func pane_quantity(pane: String, id: String) -> int:
	var inv = _inv_for_pane(pane)
	return int(inv.get_quantity(id)) if inv != null else 0

## Builds (does NOT pop) the right-click menu for a row, from context_actions.
func _build_context_menu(pane: String, index: int) -> PopupMenu:
	var menu := PopupMenu.new()
	var ids: Array = _ids_for_pane(pane)
	if index < 0 or index >= ids.size():
		return menu
	var item_id: String = String(ids[index])
	var actions: PackedStringArray = InventorySelectionModelScript.context_actions(
		item_id, _defs, _mode == "transfer", pane == "container", false)
	for a in actions:
		match String(a):
			"transfer": menu.add_item("Transfer", _ACT_TRANSFER)
			"transfer_all": menu.add_item("Transfer all", _ACT_TRANSFER_ALL)
			"split": menu.add_item("Split…", _ACT_SPLIT)
			"equip": menu.add_item("Equip", _ACT_EQUIP)
			"unequip": menu.add_item("Unequip", _ACT_UNEQUIP)
	return menu

func _on_context_id(id: int, pane: String, index: int, menu) -> void:
	if id == _ACT_TRANSFER:
		transfer_selected(pane)
	elif id == _ACT_TRANSFER_ALL:
		transfer_all_from(pane)
	elif id == _ACT_SPLIT:
		var ids: Array = _ids_for_pane(pane)
		var item_id: String = String(ids[index]) if index >= 0 and index < ids.size() else ""
		_open_split_picker(pane, item_id)
	elif id == _ACT_EQUIP:
		_model_for_pane(pane).select_single(index)
		equip_selected()
	if is_instance_valid(menu):
		menu.queue_free()

## Interaction-only (popup); split amount picker -> transfer_quantity.
func _open_split_picker(pane: String, item_id: String) -> void:
	var src = _inv_for_pane(pane)
	if src == null or item_id == "":
		return
	var maxq: int = int(src.get_quantity(item_id))
	if maxq <= 0:
		return
	var dlg := AcceptDialog.new()
	dlg.title = "Split %s" % _name(item_id)
	var spin := SpinBox.new()
	spin.min_value = 1
	spin.max_value = maxq
	spin.value = max(1, int(maxq / 2.0))
	dlg.add_child(spin)
	add_child(dlg)
	dlg.confirmed.connect(func(): transfer_quantity(pane, item_id, int(spin.value)); dlg.queue_free())
	dlg.canceled.connect(func(): dlg.queue_free())
	dlg.popup_centered()
```

- [ ] **Step 4: Run it — expect PASS:**

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/inventory_widget_smoke.gd 2>&1
```
Expected: `INVENTORY WIDGET SMOKE PASS section_a=true` and no non-allowlisted `ERROR:`/`WARNING:`.

- [ ] **Step 5: Confirm slice-1 panel smoke still passes** (the callbacks added nothing that changes the logical API):

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/inventory_panel_smoke.gd 2>&1
```
Expected: `INVENTORY PANEL SMOKE PASS section_a=true section_b=true`.

- [ ] **Step 6: Commit:**

```bash
git add scripts/ui/inventory_panel.gd scripts/validation/inventory_widget_smoke.gd
git commit  # feat(inventory): panel coordinator callbacks for the interactive widget layer
```

---

### Task 2: Row + drop-zone widgets and the widget-tree render

Create the two interactive Control scripts and switch `_render()` from setting label text to rebuilding the widget tree (header + panes of rows + equipment slots + buttons). Remove the now-superseded panel-level DnD overrides. Track rows/zones so the smoke can fetch them and drive synthetic input.

**Files:**
- Create: `scripts/ui/inventory_row.gd`
- Create: `scripts/ui/inventory_drop_zone.gd`
- Modify: `scripts/ui/inventory_panel.gd` (`_ready`/`_render` widget tree, `_rows`/`_zones`/`row_at`/`zone_for`, remove panel-level `_get_drag_data`/`_can_drop_data`/`_drop_data`/`_drop_to`)
- Modify: `scripts/validation/inventory_widget_smoke.gd` (add Section B)

**Interfaces:**
- Consumes: the Task-1 callbacks; slice-1 `_ids_for_pane`, `_weight_line`, `_name`, `pane_quantity`, `_container_label`, `_equip.SLOTS`/`get_equipped`, `deposit_all_to_container`, `close`.
- Produces: `InventoryRow.create(panel, pane, index, item_id, defs)`, `InventoryDropZone.create(panel, target)`; panel `row_at(pane, index)`, `zone_for(target)`, `_rows`, `_zones`, `_content`.

- [ ] **Step 1: Create `scripts/ui/inventory_row.gd`:**

```gdscript
extends PanelContainer
class_name InventoryRow

## One selectable / draggable / right-clickable inventory row. Thin: every mouse event
## forwards to the owning InventoryPanel's coordinator callbacks. Constructed via the
## load()-self-reference factory so it resolves under --headless --script.

const ItemDefsScript := preload("res://scripts/systems/item_defs.gd")
const SWATCH := {
	"part": Color(0.55, 0.70, 0.95),
	"supply": Color(0.60, 0.90, 0.60),
	"tool": Color(0.95, 0.80, 0.40),
}
const SEL_BG := Color(0.18, 0.40, 0.55, 0.85)

var panel                       # InventoryPanel
var pane: String = ""
var index: int = -1
var item_id: String = ""
var _defs: Dictionary = {}
var _selected: bool = false

static func create(p_panel, p_pane: String, p_index: int, p_item_id: String, p_defs: Dictionary):
	var script: GDScript = load("res://scripts/ui/inventory_row.gd")
	var r = script.new()
	r.panel = p_panel
	r.pane = p_pane
	r.index = p_index
	r.item_id = p_item_id
	r._defs = p_defs
	return r

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var h := HBoxContainer.new()
	var sw := ColorRect.new()
	sw.custom_minimum_size = Vector2(14, 14)
	sw.color = SWATCH.get(ItemDefsScript.category(_defs, item_id), Color(0.5, 0.5, 0.5))
	h.add_child(sw)
	var lbl := Label.new()
	var qty: int = int(panel.pane_quantity(pane, item_id)) if panel != null else 0
	lbl.text = "%s  x%d" % [ItemDefsScript.display_name(_defs, item_id), qty]
	h.add_child(lbl)
	add_child(h)
	_apply_style()

func set_selected(v: bool) -> void:
	_selected = v
	_apply_style()

func _apply_style() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = SEL_BG if _selected else Color(0, 0, 0, 0)
	sb.set_corner_radius_all(4)
	add_theme_stylebox_override("panel", sb)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			panel.row_clicked(pane, index, mb.ctrl_pressed, mb.shift_pressed)
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			panel.row_context(pane, index, mb.global_position)

func _get_drag_data(_at_position: Vector2) -> Variant:
	var data = panel.row_drag_payload(pane, index)
	if data == null:
		return null
	var preview := Label.new()
	preview.text = "%d item(s)" % ((data as Dictionary)["ids"] as Array).size()
	set_drag_preview(preview)
	return data

# A row is also a drop target for its own pane (drop on a row == drop on the pane).
func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return panel.zone_can_accept(pane, data)

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	panel.zone_drop(pane, data)
```

- [ ] **Step 2: Create `scripts/ui/inventory_drop_zone.gd`:**

```gdscript
extends PanelContainer
class_name InventoryDropZone

## A drop target tagged with a `target` ("self"/"container" pane, or "slot:<slot_id>").
## Forwards drops to the owning InventoryPanel; on an equipment slot, right-click forwards
## to slot_context (Unequip). Constructed via the load()-self-reference factory.

var panel                       # InventoryPanel
var target: String = ""

static func create(p_panel, p_target: String):
	var script: GDScript = load("res://scripts/ui/inventory_drop_zone.gd")
	var z = script.new()
	z.panel = p_panel
	z.target = p_target
	return z

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return panel.zone_can_accept(target, data)

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	panel.zone_drop(target, data)

func _gui_input(event: InputEvent) -> void:
	if not target.begins_with("slot:"):
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			panel.slot_context(target.substr(5), mb.global_position)
```

- [ ] **Step 3: Rewrite `_ready` and `_render` in `scripts/ui/inventory_panel.gd` + add tracking/seams.** First add the preloads + fields near the top (after the existing consts/vars):

```gdscript
const InventoryRowScript := preload("res://scripts/ui/inventory_row.gd")
const InventoryDropZoneScript := preload("res://scripts/ui/inventory_drop_zone.gd")

var _content: VBoxContainer
var _rows: Dictionary = {"self": [], "container": []}   # pane -> Array[InventoryRow]
var _zones: Dictionary = {}                             # target -> InventoryDropZone
```

Replace the existing `_ready()` body's node-building (the `if not is_instance_valid(_root_label):` block) so it builds `_content` instead of `_root_label`. The new `_ready()`:

```gdscript
func _ready() -> void:
	set_anchors_preset(Control.PRESET_CENTER)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_defs = ItemDefsScript.load_definitions()
	if not is_instance_valid(_content):
		var bg := PanelContainer.new()
		bg.position = Vector2(200, 120)
		bg.custom_minimum_size = Vector2(700, 440)
		var style := StyleBoxFlat.new()
		style.bg_color = PANEL_COLOR
		style.border_color = PANEL_BORDER_COLOR
		style.set_border_width_all(2)
		style.set_corner_radius_all(8)
		bg.add_theme_stylebox_override("panel", style)
		add_child(bg)
		var margin := MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 14)
		margin.add_theme_constant_override("margin_top", 12)
		margin.add_theme_constant_override("margin_right", 14)
		margin.add_theme_constant_override("margin_bottom", 12)
		bg.add_child(margin)
		_content = VBoxContainer.new()
		margin.add_child(_content)
	visible = false
```

Delete the `var _root_label: Label` field and the panel-level DnD overrides (`_get_drag_data`, `_can_drop_data`, `_drop_data`, `_drop_to`) — rows/zones own DnD now. Replace `_render()` and add the builders + seams:

```gdscript
func _render() -> void:
	if not is_instance_valid(_content):
		return
	for c in _content.get_children():
		_content.remove_child(c)
		c.queue_free()
	_rows = {"self": [], "container": []}
	_zones = {}
	if _mode == "self":
		_content.add_child(_make_header())
		_content.add_child(_make_equipment_section())
		_content.add_child(_make_pane_section("self", "-- Carrying --"))
	elif _mode == "transfer":
		_content.add_child(_make_header())
		var body := HBoxContainer.new()
		body.add_child(_make_pane_section("self", "YOU"))
		body.add_child(_make_pane_section("container", _container_label))
		_content.add_child(body)
		_content.add_child(_make_footer())

func _make_header() -> Control:
	var l := Label.new()
	var title: String = "INVENTORY + GEAR" if _mode == "self" else "TRANSFER  |  %s" % _container_label
	l.text = "%s\n%s" % [title, _weight_line()]
	return l

func _make_equipment_section() -> Control:
	var box := VBoxContainer.new()
	var hdr := Label.new()
	hdr.text = "-- Equipment --"
	box.add_child(hdr)
	for slot in (_equip.SLOTS if _equip != null else []):
		var zone = InventoryDropZoneScript.create(self, "slot:%s" % String(slot))
		zone.custom_minimum_size = Vector2(300, 0)
		var worn: String = _equip.get_equipped(String(slot)) if _equip != null else ""
		var lbl := Label.new()
		lbl.text = "%s  [%s]" % [String(slot), ("(empty)" if worn == "" else _name(worn))]
		zone.add_child(lbl)
		_zones["slot:%s" % String(slot)] = zone
		box.add_child(zone)
	return box

func _make_pane_section(pane: String, title: String) -> Control:
	var box := VBoxContainer.new()
	var t := Label.new()
	var cap: String = ""
	if pane == "container" and _container != null:
		cap = "  %d/%d" % [int(_container.get_total_weight()), int(_container.get_max_weight())]
	t.text = "%s%s" % [title, cap]
	box.add_child(t)
	var zone = InventoryDropZoneScript.create(self, pane)
	zone.custom_minimum_size = Vector2(320, 200)
	var rows_vbox := VBoxContainer.new()
	zone.add_child(rows_vbox)
	var ids: Array = _ids_for_pane(pane)
	for i in range(ids.size()):
		var row = InventoryRowScript.create(self, pane, i, String(ids[i]), _defs)
		rows_vbox.add_child(row)
		(_rows[pane] as Array).append(row)
		row.set_selected(_model_for_pane(pane).is_selected(i))
	_zones[pane] = zone
	box.add_child(zone)
	return box

func _make_footer() -> Control:
	var h := HBoxContainer.new()
	var dep := Button.new()
	dep.text = "Deposit All"
	dep.pressed.connect(deposit_all_to_container)
	h.add_child(dep)
	var cl := Button.new()
	cl.text = "Close"
	cl.pressed.connect(close)
	h.add_child(cl)
	return h

## Test/inspection seams: fetch a built row / drop zone after a render.
func row_at(pane: String, index: int) -> Control:
	var arr: Array = _rows.get(pane, []) as Array
	return arr[index] if index >= 0 and index < arr.size() else null

func zone_for(target: String) -> Control:
	return _zones.get(target, null)
```

> Note on row `set_selected` after `add_child`: a row's `_ready` runs when it enters the tree (on `add_child`), so calling `row.set_selected(...)` right after `add_child` is safe (the style nodes exist).

- [ ] **Step 4: Add Section B to `scripts/validation/inventory_widget_smoke.gd`** — change `_init` and append `_run_section_b`:

```gdscript
func _init() -> void:
	await _run_section_a()
	await _run_section_b()
	print("INVENTORY WIDGET SMOKE PASS section_a=true section_b=true")
	quit()
```

```gdscript
func _run_section_b() -> void:
	var inv = InventoryStateScript.new()
	inv.add_item("scrap_metal", 6)
	inv.add_item("eva_backpack", 1)
	var hold = ShipInventoryScript.create(1000.0)
	hold.add_item("plating", 4)
	var equip = EquipmentStateScript.create()

	var panel = InventoryPanelScript.new()
	root.add_child(panel)
	await process_frame
	panel.open_transfer(inv, hold, "HOLD", equip)
	await process_frame   # let the row Controls' _ready run

	# a real row exists and a synthetic left-click selects it
	var ids := panel.get_pane_ids("self")
	var ri := ids.find("scrap_metal")
	var row := panel.row_at("self", ri)
	assert(row != null, "row Control was built for scrap_metal")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	row._gui_input(click)
	assert(panel.get_selected_ids("self") == ["scrap_metal"], "synthetic click selected the row")

	# the row yields a non-empty drag payload; dropping on the container zone transfers
	var payload = row._get_drag_data(Vector2.ZERO)
	assert(payload != null and (payload as Dictionary)["from_pane"] == "self", "row drag payload built")
	var czone := panel.zone_for("container")
	assert(czone != null, "container drop zone exists")
	assert(czone._can_drop_data(Vector2.ZERO, payload) == true, "container zone accepts the drop")
	czone._drop_data(Vector2.ZERO, payload)
	assert(hold.get_quantity("scrap_metal") == 6, "drag->drop moved the stack into the hold")

	# dropping the backpack on the back equipment slot equips it
	var bp_row := panel.row_at("self", panel.get_pane_ids("self").find("eva_backpack"))
	var bp_payload = bp_row._get_drag_data(Vector2.ZERO)
	var back_zone := panel.zone_for("slot:back")
	assert(back_zone != null and back_zone._can_drop_data(Vector2.ZERO, bp_payload) == true, "back slot accepts the backpack")
	back_zone._drop_data(Vector2.ZERO, bp_payload)
	assert(equip.get_equipped("back") == "eva_backpack", "slot drop equipped via the widget")

	panel.queue_free()
```

- [ ] **Step 5: Run it — expect PASS:**

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/inventory_widget_smoke.gd 2>&1
```
Expected: `INVENTORY WIDGET SMOKE PASS section_a=true section_b=true`.

- [ ] **Step 6: Confirm the slice-1 smokes still pass** (render replaced, logical API intact):

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/inventory_panel_smoke.gd 2>&1
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_inventory_ui_smoke.gd 2>&1
```
Expected: `INVENTORY PANEL SMOKE PASS section_a=true section_b=true` and `INVENTORY UI SLICE SMOKE PASS ...`, both with no non-allowlisted `ERROR:`/`WARNING:`.

- [ ] **Step 7: Commit:**

```bash
git add scripts/ui/inventory_panel.gd scripts/ui/inventory_row.gd scripts/ui/inventory_drop_zone.gd scripts/validation/inventory_widget_smoke.gd
git commit  # feat(inventory): interactive row + drop-zone widgets, widget-tree render
```

---

### Task 3: Docs — ADR, bundle registration, roadmap

**Files:**
- Create: `docs/game/adr/0023-inventory-widget-layer.md`
- Modify: `docs/game/06_validation_plan.md`
- Modify: `docs/game/09_system_roadmap.md`

- [ ] **Step 1: Create the ADR** — `docs/game/adr/0023-inventory-widget-layer.md`:

```markdown
# ADR-0023: Inventory Interactive Widget Layer (Phase 7 slice 2)

Date: 2026-06-23
Status: Accepted

## Context
Slice 1 (ADR-0022) delivered the inventory/transfer logic + Godot DnD entry points but rendered
a single text label with no per-row widgets, so the panel was not actually mouse-operable
(Codex PR review confirmed empty drag payloads in real play).

## Decisions
1. **Custom row Controls** back the rows (`inventory_row.gd`) — not ItemList/Tree — for full
   control over the hand-built theme, drag-drop, and right-click; rows stay thin and forward
   every mouse event to coordinator callbacks on InventoryPanel.
2. **Drop targets** are `inventory_drop_zone.gd` (panes + the 5 equipment slots); rows are also
   drop targets for their own pane (drop-on-row == drop-on-pane).
3. **Right-click `PopupMenu`** built from `context_actions`: Transfer / Transfer all
   (`transfer_all_from`, includes tools) / Split… (SpinBox amount picker -> transfer_quantity) /
   Equip; right-click an occupied slot -> Unequip.
4. **On-screen Deposit All + Close buttons**, keeping A/Esc/I as keyboard equivalents.
5. **Purely additive** — the slice-1 model/logic layer and its smokes are unchanged; the
   text-mirror render is replaced by the widget tree. No persistence change (world-4).
6. Menus are **built, not popped** in tests (popups aren't headless-safe); the widget smoke
   drives row/zone methods with synthetic input and asserts the logical effect.

## Consequences
The panel is now genuinely mouse-driven (click/shift/ctrl select, drag across panes + onto
equipment slots, right-click menus). Deferred: drag-out-to-unequip, gamepad/keyboard grid
navigation, item-icon generation (swatch fallback stays), drop-target highlight animation.
```

- [ ] **Step 2: Register the widget smoke in `docs/game/06_validation_plan.md`** — add one `run_clean` line beside the other inventory smokes and bump the final echo from `commands=114` to `commands=115`:

```bash
run_clean 'inventory widget layer' 'INVENTORY WIDGET SMOKE PASS' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/inventory_widget_smoke.gd
```

```bash
echo 'SYNAPTIC_SEA REGRESSION PASS commands=115 clean_output=true'
```

> Sanity: `grep -c '^run_clean' docs/game/06_validation_plan.md` will report **116** (the `run_clean() {` definition line + 115 invocations). The echo says `commands=115`.

- [ ] **Step 3: Update `docs/game/09_system_roadmap.md`** — in the System 6 row, note the inventory/transfer UI is now interactive (mouse-driven widgets, ADR-0023); keep the deferred list (icon generation, drag-out unequip, gamepad nav, B/C/D sub-slices). Bump the percentage modestly (e.g. ~85% → ~88%).

- [ ] **Step 4: Run the FULL regression bundle to confirm 115 green.** Stash the local `project.godot` drift for the run only:

```bash
git stash push -- project.godot
bash <(awk '/^## Regression bundle/{f=1} f && /^```bash$/ {c=1; next} f && c && /^```$/ {exit} f && c {print}' docs/game/06_validation_plan.md)   # GODOT/ROOT exported
git stash pop
```
Expected tail: `SYNAPTIC_SEA REGRESSION PASS commands=115 clean_output=true`. Do not commit or revert the `project.godot` drift.

- [ ] **Step 5: Commit:**

```bash
git add docs/game/adr/0023-inventory-widget-layer.md docs/game/06_validation_plan.md docs/game/09_system_roadmap.md
git commit  # docs(inventory): ADR-0023 + register inventory-widget smoke (114->115) + roadmap
```

---

## Self-Review (performed during planning)

**1. Spec coverage:**
- §2.1 custom row Controls → `inventory_row.gd` (Task 2). ✓
- §2.2 precise Split amount picker → `_open_split_picker` SpinBox (Task 1). ✓
- §2.3 two new Controls + panel coordinator → Tasks 1–2. ✓
- §2.4 Deposit All + Close buttons → `_make_footer` (Task 2). ✓
- §2.5 unequip via right-click on a slot → `slot_context` + `InventoryDropZone._gui_input` (Tasks 1–2). ✓
- §2.6 text-mirror replaced → `_render` rewrite + `_root_label`/panel-DnD removal (Task 2). ✓
- §3 callbacks (`row_*`/`zone_*`/`transfer_all_from`/`_build_context_menu`) → Task 1. ✓
- §4 Transfer / Transfer all (incl tools) / Split / Equip / Unequip mapping → `_build_context_menu` + `_on_context_id` (Task 1). ✓
- §5 rebuild render headless-safe; popups only on interaction → Task 2 `_render`. ✓
- §6 widget smoke + build-not-pop menu testing + bundle 114→115 + ADR-0023 → Tasks 1–3. ✓
- §1 additive / world-4 unchanged → no model/persistence code touched. ✓

**2. Placeholder scan:** no "TBD"/"handle edge cases". The one deliberate leftover (the dead `if false` guard line in the Task-1 smoke) is explicitly removed in Task 1 Step 4 and called out in the note — it must not ship.

**3. Type consistency:** `row_clicked(pane, index, additive, range_sel)`, `row_drag_payload(pane, index)`, `zone_can_accept(target, data)`, `zone_drop(target, data)`, `transfer_all_from(pane)`, `slot_context(slot_id, global_pos)`, `_build_context_menu(pane, index)`, `_on_context_id(id, pane, index, menu)`, `pane_quantity(pane, id)`, `InventoryRow.create(panel, pane, index, item_id, defs)`, `InventoryDropZone.create(panel, target)`, `row_at(pane, index)`, `zone_for(target)`, the `_ACT_*` consts, and the `_rows`/`_zones`/`_content` fields are consistent across Tasks 1–2 and matched to the verified slice-1 API (`select_row`, `_build_drag_payload`, `transfer_selected`/`transfer_quantity`, `equip_selected`/`unequip_slot`, `_ids_for_pane`/`_inv_for_pane`/`_model_for_pane`, `_equip.SLOTS`). The dispatch uses `if/elif` (not `match`) per the Global Constraint. ✓
