# Phase 7 — Slice 2: InventoryPanel Interactive Widget Layer — Design

Date: 2026-06-23
Status: Approved design. Implementation pending (writing-plans → subagent-driven-development).
Branch: `phase7-interactive-widgets`, stacked on `phase7-inventory-transfer-ui` (slice 1, PR #20).
Rebases onto `main` once #20 merges.

## 1. Context & goal

Slice 1 (PR #20) delivered the inventory/transfer **logic**: the pure `InventorySelectionModel`,
`CargoTransfer.move_item`/`move_items`, the `InventoryPanel` logical API, the Godot drag-and-drop
entry points, and a single text-label render. A PR review (Codex P1) confirmed the gap: the panel
has **no per-row interactive widgets**, so in real mouse play nothing calls `select_row()` and a
drag produces an empty payload — the panel is not actually mouse-operable yet.

**Goal:** make the panel genuinely mouse-driven by replacing the text-mirror render with a real
widget tree of custom row Controls — click/shift/ctrl select, drag-and-drop between panes and onto
equipment slots, and right-click context menus (including a precise Split amount picker).

**This slice is purely additive.** The slice-1 model/logic layer and its validation smokes are
**unchanged**; only the render and the mouse-event wiring are added. No new persisted state;
`WORLD_SLICE_VERSION` stays `"world-4"`.

## 2. Resolved decisions

1. **Custom row Controls** back the rows (not `ItemList`/`Tree`) — full control over the hand-built
   theme, drag-drop, and right-click; rows stay thin and call the slice-1 logical API.
2. **Split = precise amount picker** — right-click → Split… opens a `SpinBox` (1..stack) + OK, then
   moves that quantity via `transfer_quantity`.
3. **Two new small Control scripts + panel as coordinator** (vs cramming everything into the panel).
4. **On-screen Deposit All + Close buttons**, keeping `A`/`Esc`/`I` as keyboard equivalents.
5. **Unequip via right-click** on an equipment slot (drag-out-to-unequip deferred).
6. The text-mirror render is **replaced** by the widget tree (no smoke reads the label — verified).

## 3. Architecture & components

### New files
- **`scripts/ui/inventory_row.gd`** — `InventoryRow extends PanelContainer`. One selectable /
  draggable / right-clickable row: an icon-or-swatch + name + qty + weight. Holds `pane: String`,
  `index: int`, `item_id: String`, and a `panel` ref. Behavior:
  - `_gui_input(event)`: left mouse press → `panel.row_clicked(pane, index, ctrl_held, shift_held)`;
    right mouse press → `panel.row_context(pane, index, event_global_position)`.
  - `_get_drag_data(at_position)` → `panel.row_drag_payload(pane, index)` (returns the drag dict or
    `null`); sets a drag preview.
  - Reflects selection via a highlight stylebox toggled by `set_selected(bool)`.
- **`scripts/ui/inventory_drop_zone.gd`** — `InventoryDropZone extends Control`. A drop target
  tagged `target: String` (`"self"` / `"container"` / `"slot:<slot_id>"`) with a `panel` ref:
  - `_can_drop_data(at_position, data)` → `panel.zone_can_accept(target, data)`.
  - `_drop_data(at_position, data)` → `panel.zone_drop(target, data)`.

### Modified file
- **`scripts/ui/inventory_panel.gd`** — `_render()` switches from setting `_root_label.text` to
  **rebuilding the widget tree**: a header (title + weight/Heavy-Load line), the panes
  (`InventoryDropZone` containing a `VBoxContainer` of `InventoryRow`s), the 5 equipment-slot
  `InventoryDropZone`s (SELF mode), and the Deposit All / Close buttons. The logical API is
  unchanged. New thin coordinator callbacks the widgets call:
  - `row_clicked(pane, index, additive, range_sel) -> void` — delegates to `select_row`.
  - `row_drag_payload(pane, index) -> Variant` — if the row's index is not already selected,
    select it single first; then return `{from_pane, ids}` (or `null` if the selection is empty).
  - `row_context(pane, index, global_pos) -> void` — if the row is not already in the selection,
    select it single; then build + pop the context `PopupMenu` at `global_pos`.
  - `zone_can_accept(target, data) -> bool` / `zone_drop(target, data) -> void` — accept/perform a
    cross-pane transfer or a slot equip.
  - `transfer_all_from(pane) -> int` — move EVERY id in `pane` to the other pane (loops
    `CargoTransfer.move_items` over the pane's full id list; manual, so includes tools). Distinct
    from the **Deposit All** button, which uses `deposit_all` (parts/supplies only, tools excluded).
  - `_build_context_menu(pane, index) -> PopupMenu` — builds (does NOT pop) the menu from
    `InventorySelectionModel.context_actions(...)`; the action ids map per §4.

### Unchanged (slice 1)
`InventorySelectionModel`, `CargoTransfer`, `EquipmentState`/`InventoryState`/`ShipInventory`, and
the panel's logical API + `transfer_completed`/`panel_closed` signals. The coordinator wiring in
`playable_generated_ship.gd` is unchanged (it already owns the panel and connects the signals).

## 4. Interaction

- **Select:** left-click = single; `Shift`+click = contiguous range from the anchor; `Ctrl`+click =
  toggle — all through `select_row(pane, i, additive, range_sel)`. Selected rows show a highlight.
- **Drag-and-drop:** dragging a row auto-selects it (if not already selected), then `_get_drag_data`
  returns `{from_pane, ids}` with a "N item(s)" drag preview. Dropping on the **other pane** →
  `transfer_selected(from_pane)`. Dropping on an **equipment slot** whose type matches an equippable
  in the payload → equip that item.
- **Right-click → `PopupMenu`** built from `context_actions(item_id, defs, in_transfer_mode,
  dest_is_container, is_equipped_slot=false)`. Exact action mapping (the slice-1 resolver returns
  `["transfer","transfer_all","split"]` for a normal stack in TRANSFER mode, `["equip"]` for an
  equippable in SELF mode):
  - **Transfer** → `transfer_selected(pane)` — move the selected row(s)' whole stacks to the other
    pane.
  - **Transfer all** → `transfer_all_from(pane)` — move every id in this pane to the other pane
    (manual; includes tools). Distinct from the Deposit All button (`deposit_all`, tools excluded).
  - **Split…** → opens a `SpinBox` popup (range 1..current stack) + OK → `transfer_quantity(pane,
    item_id, qty)`.
  - **Equip** → `equip_selected()` (selects the right-clicked item first).
  Right-click an **occupied equipment slot** → a menu with **Unequip** → `unequip_slot(slot_id)`.
- **Buttons:** **Deposit All** → `deposit_all_to_container()` (TRANSFER mode); **Close** → `close()`.
  `A` / `Esc` / `I` remain keyboard equivalents (handled by the coordinator `_input`, unchanged).

## 5. Rendering & refresh

`_render()` rebuilds the pane `VBoxContainer`s (free existing rows, re-add `InventoryRow`s for the
current `get_pane_ids`) on `open_self`/`open_transfer`/`_after_mutation`, and updates row highlights
on selection changes. Building Controls is headless-safe; `set_drag_preview`, `PopupMenu.popup()`,
and the Split `SpinBox` popup are only invoked during real interaction (`_gui_input`/`_get_drag_data`),
never during `_render`. Icons use `ItemDefs.icon(id)` → a `TextureRect` if the texture loads, else a
code-drawn category-swatch `ColorRect` (icons remain deferred; swatch fallback ships).

## 6. Testing & validation

- **Slice-1 logic smokes unchanged and still green** (`inventory_panel_smoke`,
  `inventory_selection_model_smoke`, `cargo_move_item_smoke`, `main_playable_slice_inventory_ui_smoke`)
  — they assert the logical API and model behavior, not the widget tree.
- **New `scripts/validation/inventory_widget_smoke.gd`** (scene): build the panel, seed + open
  TRANSFER, then drive the **widget→logic wiring directly** (no OS drag gesture, which isn't
  headless-drivable):
  - `panel.row_clicked("self", i, false, false)` → assert `get_selected_ids("self")` reflects it;
    shift/ctrl variants → range/toggle.
  - `panel.row_drag_payload("self", i)` returns a non-empty `{from_pane, ids}`; feed it to
    `panel.zone_drop("container", payload)` → assert the stack moved into the hold (quantities).
  - an equippable payload to `panel.zone_drop("slot:back", payload)` → assert `get_equipped("back")`.
  - `panel._build_context_menu("self", i)` returns a `PopupMenu` whose item labels equal the expected
    `context_actions` set (built, not popped — popups aren't headless-safe), and Split present.
  Marker: `INVENTORY WIDGET SMOKE PASS`.
- Register in the `06_validation_plan.md` bundle (114 → 115; recall the count = `grep -c '^run_clean'`
  minus the one `run_clean() {` definition line). **ADR-0023** records the widget-layer decisions.

## 7. Out of scope (deferred)

Drag-out-to-unequip (right-click Unequip ships) · gamepad / keyboard grid navigation · item-icon
generation (swatch fallback stays; `ItemDefs.icon` reader already wired) · drop-target highlight
animation · the slice-1-deferred B/C/D Phase-7 sub-slices.
