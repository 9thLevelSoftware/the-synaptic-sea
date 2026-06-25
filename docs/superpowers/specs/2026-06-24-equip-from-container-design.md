# Equip-from-Container (Design Spec)

Date: 2026-06-24
Status: Approved (brainstorm)

## Goal

Let the player equip an equippable item that lives in a ship cargo hold or cart **directly**,
Project-Zomboid style: a single right-click *Equip* (or a drag onto an equipment slot) on a
container row auto-transfers one unit into the player's own inventory and equips it atomically.
Today equipment is player-inventory-scoped (ADR-0023 Amendment): container rows do **not** offer
*Equip*, and equipment slots reject container-pane drops, so the player must transfer-then-equip
in two manual steps. This slice closes that gap as the accepted enhancement the Amendment tracked.

## Context (what already exists — verified)

- **`InventorySelectionModel`** (`scripts/systems/inventory_selection_model.gd`): pure per-list
  selection + the static `context_actions(item_id, defs, in_transfer_mode, row_is_container,
  is_equipped_slot) -> PackedStringArray`. Today it suppresses `equip` for container rows via
  `if equippable and not row_is_container`.
- **`InventoryPanel`** (`scripts/ui/inventory_panel.gd`) owns `_player_inv` (`InventoryState`),
  `_container` (`ShipInventory`/cart), and `_equip` (`EquipmentState`):
  - `equip_selected() -> bool` (lines ~146–167): reads the single SELF selection, prechecks
    `_player_inv.get_quantity(item_id) > 0 and _equip.can_equip(item_id)`, calls `_equip.equip()`
    (`{ok, displaced}`), returns the displaced occupant to the carry list with a no-carry-room
    rollback (`_equip.equip(displaced)` to restore the slot), then `_player_inv.remove_item(id, 1)`,
    then `_after_mutation()`.
  - `_after_mutation()` (lines ~201–207): `_rebuild_models()` (rebuilds BOTH `_sel_self` and
    `_sel_container`), `transfer_completed.emit()` (the coordinator recomputes encumbrance +
    suit→oxygen in its handler), then `_render()`.
  - `_on_context_id(id, pane, index)` (lines ~324–337): dispatches `_ACT_EQUIP` by selecting the
    row in `_model_for_pane(pane)` and calling `equip_selected()` (works only because equip is
    currently offered for SELF rows only).
  - `zone_can_accept(target, data)` / `zone_drop(target, data)` (lines ~242–273): for a
    `"slot:<id>"` target they **reject** any payload whose `from_pane != "self"`, else equip the
    first id whose `equip_slot == <id>` via `equip_selected()`.
- **`CargoTransfer.move_item(src, dst, item_id, qty) -> int`** (`scripts/systems/cargo_transfer.gd`):
  moves up to `qty` of one id; the destination's `add_item` enforces its own cap (player
  `InventoryState` = PZ soft-cap / full-accept gated only by `max_stack`; `ShipInventory` = hard
  weight-cap / partial fill); `src` loses **exactly** what `dst` accepted, so the per-id total
  across src+dst is invariant. Returns the count actually moved (0 on failure).
- **`EquipmentState`** (`scripts/systems/equipment_state.gd`): `can_equip(item_id)` is true iff the
  item's `equip_slot` is one of `SLOTS`; `equip(item_id)` only returns `{ok: false}` when
  `not can_equip` — for a valid equippable it always succeeds, returning the displaced occupant.
- **Equipment defs** (`data/items/equipment_definitions.json`): all `max_stack: 1`. Back-slot
  items `eva_backpack` and `field_pack`, waist `tool_belt`, suit `hardsuit`.

## Decisions

1. **One logic path, two triggers.** A single new `equip_from_container(item_id)` is reached from
   both the right-click *Equip* on a container row and a drag of a container row onto an equipment
   slot. No behavior forks between the triggers.
2. **Atomic transfer-then-equip with rollback.** `move_item(hold → player, 1)`, then equip the
   now-in-inventory unit reusing the existing atomic equip core; on equip failure, move the unit
   back to the hold. Both steps are synchronous (no `await`), so there is no observable
   intermediate state, and any failure leaves both inventories byte-identical to the start.
3. **Reuse the slice-1 equip core via extraction.** Factor the selection-independent body of
   `equip_selected()` into `_equip_in_inventory(item_id) -> bool` so both `equip_selected()` and
   `equip_from_container()` share the same precheck / displaced / no-carry-room rollback. Pure
   refactor; the existing self-equip behavior and smokes are unchanged.
4. **Displaced occupant goes to the player's carry inventory**, not back into the hold — identical
   to the existing equip semantics (the Amendment's sketch said to reuse slice-1 rollback).
5. **Player-inventory-scoped equip is retired.** `context_actions` re-enables `equip` for container
   equippable rows; the equipment slot drop-zones accept container-pane payloads. This supersedes
   the ADR-0023 Amendment's interim "container rows don't offer Equip."
6. **No coordinator change, no persistence change.** Everything happens inside `InventoryPanel`,
   which already holds all three references; `_after_mutation()` already fires the coordinator's
   `transfer_completed` recompute. World-4 save format is untouched.
7. **No cart-both-hands check is added.** The panel's equip path (`equip_selected`) predates and
   does not consult the coordinator's cart-both-hands block; `equip_from_container` matches it
   exactly rather than introducing a new, inconsistent gate. (Noted, not changed.)

## Architecture & Data Flow

```
right-click "Equip" on a container row ─┐
                                        ├─► InventoryPanel.equip_from_container(item_id):
drag a container row onto slot:<id> ────┘        moved = CargoTransfer.move_item(_container, _player_inv, item_id, 1)
                                                 if moved < 1: return false                       # transfer failed → no change
                                                 if _equip_in_inventory(item_id):                 # equip + displaced/no-room rollback
                                                     _after_mutation(); return true               # → transfer_completed → coordinator recompute
                                                 CargoTransfer.move_item(_player_inv, _container, item_id, 1)   # roll the unit back
                                                 return false

_equip_in_inventory(item_id):   # extracted core, shared with equip_selected()
    if _player_inv.get_quantity(item_id) <= 0 or not _equip.can_equip(item_id): return false
    res = _equip.equip(item_id)                              # {ok, displaced}; ok always true for a valid equippable
    if not res.ok: return false
    displaced = res.displaced
    if displaced != "" and _player_inv.add_item(displaced, 1) < 1:
        _equip.equip(displaced); return false               # no carry room → restore slot, leave item_id in carry
    _player_inv.remove_item(item_id, 1)
    return true
```

`equip_selected()` becomes: read the single SELF selection → `if _equip_in_inventory(id):
_after_mutation(); return true` → else `return false`.

## Components / Files

### Modify `scripts/systems/inventory_selection_model.gd`
- `context_actions`: change `if equippable and not row_is_container:` to `if equippable:` (the
  transfer-mode branch now offers `equip` for container equippables too). Update the method
  docstring to describe equip-from-container instead of the player-only scoping.

### Modify `scripts/ui/inventory_panel.gd`
- Add `_equip_in_inventory(item_id: String) -> bool` (the extracted core above).
- Refactor `equip_selected()` to read the single SELF selection and delegate to
  `_equip_in_inventory`, calling `_after_mutation()` on success (behavior unchanged).
- Add `equip_from_container(item_id: String) -> bool` (guards: `_container`/`_player_inv`/`_equip`
  non-null; `not ItemDefsScript.equip_slot(_defs, item_id).is_empty()`; `_container.get_quantity(item_id) > 0`;
  then move → `_equip_in_inventory` → `_after_mutation` on success, else roll the unit back).
- `_on_context_id`: in the `_ACT_EQUIP` branch, if `pane == "container"` call
  `equip_from_container(String(_ids_for_pane("container")[index]))`; else keep the SELF path
  (`_model_for_pane(pane).select_single(index); equip_selected()`). Remove the stale "SELF rows
  only" comment.
- `zone_can_accept(target, data)`: for a `"slot:<id>"` target, accept `from_pane == "self"` **or**
  `from_pane == "container"` when an id's `equip_slot == <id>` (replace the `from_pane != "self"`
  early-false with `from_pane != "self" and from_pane != "container"`).
- `zone_drop(target, data)`: for a `"slot:<id>"` target with a matching id, branch on `from_pane`:
  `"self"` → existing `select_single` + `equip_selected()`; `"container"` →
  `equip_from_container(matching_id)`.

### Modify `scripts/validation/inventory_selection_model_smoke.gd`
- Flip the locked assertion: a container equippable row in transfer mode **now offers** `"equip"`
  (the SELF row still offers it; a non-equippable container/SELF row still does not).

### Modify `scripts/validation/inventory_widget_smoke.gd`
Add an equip-from-container section exercising the panel directly (build `InventoryState` +
`ShipInventory` + `EquipmentState` + `InventoryPanel`, `open_transfer`):
- **Right-click from container:** hold has `eva_backpack` (1), player carry + back slot empty →
  `panel._on_context_id(panel._ACT_EQUIP, "container", <eva_backpack index>)` →
  `equip.get_equipped("back") == "eva_backpack"`, `hold.get_quantity("eva_backpack") == 0`,
  `inv.get_quantity("eva_backpack") == 0` (consumed into the slot, not left in carry).
- **Drag-to-slot from container:** `panel.zone_can_accept("slot:back", {"from_pane": "container",
  "ids": ["eva_backpack"]}) == true`; `panel.zone_drop("slot:back", {"from_pane": "container",
  "ids": ["eva_backpack"]})` → `equip.get_equipped("back") == "eva_backpack"` and hold count −1.
- **Rollback (transfer succeeds, equip fails):** `equip` wears `eva_backpack`; player carry holds
  `eva_backpack` ×1 (max_stack 1 → full); hold holds `field_pack` ×1. `panel.equip_from_container("field_pack")`
  returns `false`; assert `equip.get_equipped("back") == "eva_backpack"` (unchanged),
  `hold.get_quantity("field_pack") == 1` (restored), `inv.get_quantity("field_pack") == 0`
  (rolled back), `inv.get_quantity("eva_backpack") == 1` (untouched).

### Docs
- New `docs/game/adr/0026-equip-from-container.md` — records the two entry points, the
  transfer-then-equip atomicity + rollback, displaced→carry, and that it supersedes the ADR-0023
  Amendment's interim "container rows don't offer Equip."
- `docs/game/09_system_roadmap.md` — System 6 *Remaining:* drop the equip-from-container clause
  (now done; cite ADR-0026).
- `docs/game/adr/0023-inventory-widget-layer.md` — add a one-line pointer in the Amendment noting
  the deferred enhancement shipped as ADR-0026.

## Testing & Validation

- `inventory_selection_model_smoke` and `inventory_widget_smoke` print their existing PASS markers
  (unchanged marker strings); the new assertions run clean. Both smokes are already registered in
  the regression bundle, so the count stays **commands=119** (no new smoke).
- Full regression bundle green at **commands=119 clean_output=true** (stash `project.godot` drift
  before the run, pop after; never commit it / `.godot/` / `*.uid` / `addons/`).
- Gate-1 automated playtest still `GO`.

## Out of Scope (explicit)

- A cart-both-hands gate on the panel equip path (it does not exist today; not added here).
- Equipping more than one unit, or auto-equipping the "best" container item — one explicit unit
  per action only.
- Item icons, drag-out-to-unequip, gamepad/keyboard grid navigation, drop-target highlight
  animation — unrelated System 6 *Remaining:* polish items.
- Any change to `EquipmentState`, `CargoTransfer`, the coordinator, or the world-4 save format.
