# Phase 7 — Slice 1: Inventory & Transfer UI — Design

Date: 2026-06-23
Status: Approved design. Implementation pending (writing-plans → subagent-driven-development).
Branch: `phase7-inventory-transfer-ui`.

## 1. Context & scope

Phase 7 ("Integration & Polish") in `docs/game/09_system_roadmap.md` is not one project — it is
four independent sub-projects:

- **A. Inventory & transfer UI** — the interactive screen that makes System 6's machinery
  (player inventory, worn equipment/encumbrance, ship cargo holds, carts) actually usable by a
  human player. **This spec.**
- **B. Live suit→oxygen wiring** — connect `EquipmentState.get_oxygen_drain_multiplier()` into
  `OxygenState`. Tiny; deferred to its own slice.
- **C. Live repair-progress HUD line** — `RepairPoint.progress`/`repair_blocked` → HUD. Tiny;
  deferred.
- **D. Balance pass** — repair difficulty, loot distribution, scanner upgrades. Deferred; needs
  its own spec + playtest data.

This slice delivers **A only**. It is a UI/integration layer over already-built, already-validated
System 6 models; it adds **no new persisted state and no save-format change** (the `icon` field in
§4 is static definition data, not run state).

**Goal:** a mouse-driven inventory/equipment/transfer screen — Project-Zomboid-style interaction
(drag-and-drop, shift/ctrl multi-select, right-click context menus) rendered with the existing
hand-built HUD look — that lets the player view their inventory + worn gear and move items
per-item to/from a nearby cargo hold or cart.

## 2. Resolved decisions (the design forks, settled)

1. **Hand-built theme, no external asset kit.** The Godot Asset Library was surveyed (zero usable
   game-UI skins) and itch.io free Godot UI assets were browsed in a real browser; the user chose
   to hand-build with `StyleBoxFlat` matching `ObjectiveTracker`/`ScannerPanel`. Zero
   dependency/license exposure; fully headless-testable.
2. **Open model is physical, matching the rest of the game.** Press the interact key (`E`) at a
   hold/cart → TRANSFER mode (dual-pane). Press `toggle_inventory` (default `I`) anywhere → SELF
   mode (inventory + equipment). This supersedes the current bulk "deposit-all / withdraw-category"
   prompts (kept as an in-panel convenience action).
3. **Mouse-driven**, PZ-style: drag-and-drop, `Shift`+click range select, `Ctrl`+click toggle,
   right-click context menu. The cursor is already free (nothing captures the mouse).
4. **List-with-icons layout, not a slot/grid.** Our inventory is weight/quantity-based, not
   spatial; a Tetris grid would misrepresent the model. PZ's real layout is a list-with-icons —
   this is that, done prettier.
5. **Item icons deferred.** Ship with a code-drawn **category swatch** fallback now; wire an
   `icon` reader so generated icons drop in later with no code change. No icon-generation task in
   this slice.
6. **Tools are transferable** (manual per-item move). Bulk `deposit_all` still excludes tools.
   Consequence (intended): depositing the O2 pump removes its oxygen-drain benefit; the effect is
   wired to update immediately (§6).
7. **Model/Node split for testability.** A pure `RefCounted` selection/action model (fully
   smoke-tested) + a thin `Control` view (mouse plumbing, lightly covered). Honors the codebase's
   Resources-are-data / Nodes-are-behavior rule.

## 3. Architecture & components

### New files
- **`scripts/systems/inventory_selection_model.gd`** — `RefCounted`, pure. Owns per-list selection
  state and resolves context-menu action sets. No scene-tree access. Fully smoke-tested.
- **`scripts/ui/inventory_panel.gd`** — `Control`, thin view. Hand-built `StyleBoxFlat` chrome in
  the HUD palette. Houses Godot drag-and-drop (`_get_drag_data`/`_can_drop_data`/`_drop_data`), the
  right-click `PopupMenu`, row rendering with icon-or-swatch, and the two modes (SELF/TRANSFER).
  Delegates every selection/action decision to the model and every move to `CargoTransfer`.

### Modified files
- **`scripts/systems/cargo_transfer.gd`** — add per-item move primitives (§5).
- **`scripts/systems/item_defs.gd`** — add `icon(defs, id) -> String` reader (§4).
- **`data/items/item_definitions.json`**, **`data/items/equipment_definitions.json`** — optional
  `icon` field may be added later; readers default to `""` (swatch) when absent. No values added in
  this slice.
- **`scripts/procgen/playable_generated_ship.gd`** — coordinator wiring (§6): own the panel,
  register `toggle_inventory` at runtime, open TRANSFER from the hold/cart controls, freeze/restore
  the player around the panel, recompute encumbrance + refresh oxygen on transfer completion.

### Interfaces (so the plan can be written against exact names)

`InventorySelectionModel` (pure, per-list):
- `var ids: Array[String]` — the ordered item ids currently shown in this list (set by the view).
- `func set_ids(p_ids: Array) -> void` — replace the ordered id list; clears selection out of range.
- `func select_single(index: int) -> void` — single select; sets the anchor.
- `func toggle(index: int) -> void` — Ctrl-click: add/remove one; updates the anchor.
- `func select_range_to(index: int) -> void` — Shift-click: select contiguous [anchor..index].
- `func clear() -> void`
- `func is_selected(index: int) -> bool`
- `func get_selected_ids() -> Array` — selected ids in `ids` order.
- `static func context_actions(item_id: String, defs: Dictionary, in_transfer_mode: bool, dest_is_container: bool, is_equipped_slot: bool) -> PackedStringArray`
  — pure action resolver. Returns an ordered subset of:
  `"transfer"`, `"transfer_all"`, `"split"`, `"equip"`, `"unequip"`.
  Rules: SELF mode on an equippable item → `["equip"]`; SELF mode on an occupied equipment slot →
  `["unequip"]`; TRANSFER mode on a normal stack → `["transfer", "transfer_all", "split"]`; an
  equippable in TRANSFER mode also appends `"equip"`. Tools yield the same transfer actions as any
  other item (tools are transferable).

`CargoTransfer` (pure additions):
- `static func move_item(src, dst, item_id: String, qty: int) -> int`
- `static func move_items(src, dst, id_to_qty: Dictionary) -> int`
  Semantics in §5.

`InventoryPanel` (Control) public surface the coordinator uses:
- `func open_self(inv, equip) -> void`
- `func open_transfer(player_inv, container_hold, container_label: String) -> void`
- `func close() -> void`
- `func is_open() -> bool`
- `signal panel_closed` — emitted on every close path; coordinator restores player control here.
- `signal transfer_completed` — emitted after a move mutates state; coordinator recomputes
  encumbrance + refreshes oxygen.

## 4. Icons (deferred, but wired)

`ItemDefs.icon(defs, id) -> String` reads an optional `"icon"` field (a `res://` path), defaulting
to `""`. The panel: if `icon` is non-empty and the texture loads, draw it; otherwise draw a
**category swatch** — a small code-drawn colored square keyed by category
(`part`/`supply`/`tool`/equipment). The panel is fully functional and tested with swatches only;
generated icons are a future fast-follow that needs no panel code change.

## 5. Transfer primitives (model logic, smoke-tested)

`move_item(src, dst, item_id, qty)`:
- Moves up to `qty` of `item_id` from `src` to `dst`; returns the count actually moved.
- **Destination cap is honored by destination type:** a hold/cart (`ShipInventory`) hard-caps by
  weight → partial fill, returns what fit; the player (`InventoryState`) is soft-capped → accepts
  the full amount (may go over capacity / Heavy-Load), limited only by `max_stack`.
- Removes exactly the moved count from `src` (conservation: summed per-id quantity across src+dst is
  invariant).
- `qty <= 0`, unknown id, or `src` lacking the id → moves 0, no mutation.

`move_items(src, dst, id_to_qty)`: applies `move_item` per entry; returns total moved. Used for
multi-selection drags and "transfer all".

`deposit_all`/`withdraw_category` are unchanged; `deposit_all` continues to exclude tools.

## 6. Coordinator wiring (`playable_generated_ship.gd`)

- **Own the panel** as a field alongside `tracker`/`scanner_panel`, added to the HUD `CanvasLayer`.
- **Register `toggle_inventory` at runtime** (default key `I`) via the same InputMap-registration
  helper used for `toggle_scanner` — **`project.godot` is not modified.**
- **Open paths:**
  - `_input`: on `toggle_inventory`, open SELF mode; freeze the player
    (`set_physics_process(false)` + input off) exactly as the scanner block does.
  - The hold/cart walk-up controls (`CargoHoldControl`/`CartControl`) open TRANSFER mode for that
    container instead of firing the old bulk deposit/withdraw signals. The bulk "deposit all"
    remains available as the panel's `A` convenience action.
- **Close path:** `panel_closed` handler restores player control (mirrors the scanner's
  `panel_closed` restore — covers every close path, not just toggle/confirm).
- **Transfer completion:** on `transfer_completed`, the coordinator calls
  `_recompute_player_encumbrance()` **and** `_refresh_oxygen_state(false, 0.0)`. Encumbrance keeps
  Heavy-Load/move-speed correct after a soft-cap change; the oxygen refresh re-syncs the drain
  multiplier (`oxygen_state.apply_inventory_summary(inventory_state.get_summary())`) so storing or
  retrieving the O2 pump updates oxygen immediately and deterministically.
- **Input exclusivity:** while the panel is open, non-panel input (save/load, scanner toggle,
  interaction) is swallowed, mirroring the scanner's exclusivity.

## 7. Interaction detail

- **Selection:** click = single; `Shift`+click = range from anchor; `Ctrl`+click = toggle one.
- **Drag-and-drop (Godot Control DnD):** `_get_drag_data` packages the current selection (the
  dragged row plus any multi-selection) and a `set_drag_preview`; `_can_drop_data` accepts the
  other pane (TRANSFER) or a matching equipment slot (SELF); `_drop_data` runs the move/equip and
  emits `transfer_completed`. Dragging an equippable onto its slot equips it; dragging out of a slot
  unequips to inventory.
- **Right-click context menu:** a `PopupMenu` built from
  `InventorySelectionModel.context_actions(...)`. Actions: Transfer · Transfer all · Split… (a
  small amount stepper) · Equip / Unequip.
- **Equip displaces** the current slot occupant back to inventory
  (`EquipmentState.equip` returns the displaced item).

## 8. Layout (hand-built, HUD palette)

```
TRANSFER (E at hold/cart):                       SELF (I):
+== YOU ==============+== HOLD ===========+      +== INVENTORY + GEAR =========+
|[#] Scrap Metal  x6  |[#] Hull Plating x12|      | Wt 42.0/90.0  [OK] x1.00   |
|[#] Ration Pack  x3  |[#] Wiring Spool  x4|      | Suit  [#] Salvage Hardsuit |  <- drop
|[#] O2 Pump (tool)   |                    |      | Back  [#] EVA Backpack +40 |     targets
+ Wt 42/90 [OK] ------+- 180/500 ----------+      | Waist [ ] (empty)          |
 [#] = generated icon, swatch fallback            | Hands [ ] / [ ]            |
 drag row -> pane | Shift range | Ctrl toggle     | -- Carrying --             |
 right-click -> Transfer/Transfer all/Split/Equip | [#] Scrap Metal  x6 ...    |
                                                  + [OK]/[HEAVY]/[OVERLOADED]  +
```

Heavy-Load badge: `[OK]` / `[HEAVY]` / `[OVERLOADED]`, color-coded, with the live move-speed
multiplier (from `Encumbrance.move_speed_multiplier(load_ratio)`).

## 9. Edge cases & rules

- Soft-cap into the player is never refused; into a hold/cart it partial-fills to the hard cap.
- **Tools are transferable** via manual move/drag; `deposit_all` (bulk) still excludes them.
  Depositing the O2 pump reverts the drain multiplier to ×1.0; withdrawing it restores ×0.5 — live,
  via §6.
- Equip displaces the prior occupant to inventory; no item is lost.
- Empty list / empty container → `(empty)`; drop/move/equip is a no-op.
- Panel open ⇒ player frozen + non-panel input swallowed.
- Two-handed carts already block hand equips in the cart model; the panel only reflects state.

## 10. Persistence

None new. The panel is a pure view over `InventoryState`, `EquipmentState`, `ShipInventory`, and
`CartState`. `WORLD_SLICE_VERSION` stays `"world-4"`. The `icon` field is static definition data.

## 11. Testing & validation

All four register in the `docs/game/06_validation_plan.md` bundle (110 → 114; remember the bundle's
command count = `grep -c '^run_clean'` minus the one `run_clean() {` definition line).

1. `scripts/validation/inventory_selection_model_smoke.gd` — pure. Asserts: single replaces; Shift
   range from anchor selects contiguous; Ctrl toggle; `set_ids` clears out-of-range selection;
   `context_actions` returns the expected ordered sets for a part (transfer/transfer_all/split), an
   equippable suit (equip), an occupied slot (unequip), and a tool (transfer actions present —
   tools transferable). Marker: `INVENTORY SELECTION MODEL SMOKE PASS`.
2. `scripts/validation/cargo_move_item_smoke.gd` — pure. Asserts `move_item`/`move_items`: hold
   hard-cap partial fill; player soft-cap full accept; conservation invariant; multi-item move;
   split (partial qty) correctness. Marker: `CARGO MOVE ITEM SMOKE PASS`.
3. `scripts/validation/inventory_panel_smoke.gd` — scene/headless. Instantiates the panel, populates
   it, and drives logic by calling `_get_drag_data`/`_can_drop_data`/`_drop_data` and the
   context-menu handler **directly** (no synthetic pixel drags): a drag from YOU dropped on HOLD
   moves the stack; a drag of a suit onto the Suit slot equips it (inventory loses it, slot gains
   it) and unequip reverses; the Heavy-Load badge flips when pushed over capacity. Marker:
   `INVENTORY PANEL SMOKE PASS`.
4. `scripts/validation/main_playable_slice_inventory_ui_smoke.gd` — full scene. Opens the panel via
   a coordinator seam at a hold; asserts open freezes the player and close restores control; a
   per-item transfer at the hold moves an item and updates Heavy-Load; **depositing
   `portable_oxygen_pump` sets the oxygen drain multiplier to 1.0 and withdrawing it restores 0.5**
   (proves the §6 tool-storage wiring). Marker: `INVENTORY UI SLICE SMOKE PASS`.

Plus **ADR-0022** recording the UI-integration decisions (hand-built theme, physical open model,
mouse DnD + Model/Node split, tools-transferable, icons-deferred).

## 12. Out of scope (deferred)

Slot/volume (Tetris) inventory model · floor-drop of items (no world-item entity exists) ·
controller/gamepad navigation · item-icon generation (fast-follow) · **B** suit→oxygen wiring ·
**C** repair-progress HUD line · **D** balance pass.
