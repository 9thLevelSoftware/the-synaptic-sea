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
   Equip (**SELF-pane rows only** — see the Amendment below); right-click an occupied slot ->
   Unequip.
4. **On-screen Deposit All + Close buttons**, keeping A/Esc/I as keyboard equivalents.
5. **Purely additive** — the slice-1 model/logic layer and its smokes are unchanged; the
   text-mirror render is replaced by the widget tree. No persistence change (world-4).
6. Menus are **built, not popped** in tests (popups aren't headless-safe); the widget smoke
   drives row/zone methods with synthetic input and asserts the logical effect.

## Consequences
The panel is now genuinely mouse-driven (click/shift/ctrl select, drag across panes + onto
equipment slots, right-click menus). Deferred: equip-from-container (see Amendment),
drag-out-to-unequip, gamepad/keyboard grid navigation, item-icon generation (swatch fallback
stays), drop-target highlight animation.

## Amendment (2026-06-24): equip is player-inventory-scoped; equip-from-container is a planned enhancement

PR #21 review (Codex P2) found that in TRANSFER mode the right-click menu offered **Equip** on
*container*-pane rows, but the equip path is wired SELF-only: `equip_selected()` reads the SELF
selection model and mutates `_player_inv`/`_equip`, and equipment slots are SELF-only drop
targets. Equipping a container item therefore no-oped or equipped the wrong (already-selected)
player item.

**Decision (as shipped, commit 32a7de0):** equipment is **player-inventory-scoped**.
`context_actions(..., row_is_container, ...)` suppresses `equip` for container rows — to equip a
container item today the player transfers it into their own inventory first, then equips. The
resolver param was renamed `dest_is_container` → `row_is_container` to match how the panel wires
it (`pane == "container"`), since it is now load-bearing. Both directions are locked in
`inventory_selection_model_smoke` (SELF row offers equip; container row does not).

**Decision (accepted, deferred to a future enhancement):** the target end-state is
**equip-from-container** — right-clicking *Equip* (or dragging) an equippable that lives in a
container auto-transfers one unit into the player's inventory and equips it in a single action,
Project-Zomboid style. This is intentionally out of slice 2 (it changes the equip flow's
inputs); it is tracked in `09_system_roadmap.md` (System 6 *Remaining:*).

**Implementation sketch (for the future slice):** add an equip-from-container path that, given a
container row's `item_id`, runs `CargoTransfer.move_item(container_hold, _player_inv, item_id, 1)`
and, only on a non-zero accepted move, calls the existing atomic `equip_selected()` against the
now-in-inventory item — reusing slice-1's displaced-item / no-carry-room rollback so a failed
equip (or a failed transfer) leaves both inventories unchanged. Re-enable the `equip` action for
container rows in `context_actions` and route `_ACT_EQUIP` for container panes through that new
path. Cover with a smoke: container-only equippable → right-click Equip → item is worn and the
hold count dropped by one; and a no-carry-room case asserting nothing moved.

**Shipped (2026-06-24):** the deferred equip-from-container enhancement is now implemented per
this sketch — see ADR-0026. Container equippable rows offer *Equip* again, and equipment slots
accept container-pane drags.
