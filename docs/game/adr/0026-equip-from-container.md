# ADR-0026: Equip-from-Container

Date: 2026-06-24
Status: Accepted
Phase: 7 (Integration & Polish)

## Context

ADR-0023's Amendment shipped equipment as player-inventory-scoped: container
(ship-hold / cart) rows did not offer *Equip*, and equipment slots rejected
container-pane drops, so equipping a salvaged item meant a manual
transfer-then-equip. The Amendment recorded equip-from-container as the
accepted, deferred end-state.

## Decision

A single `InventoryPanel.equip_from_container(item_id)` performs a
Project-Zomboid-style atomic transfer-then-equip: `CargoTransfer.move_item`
moves one unit from the container into the player inventory, then the item is
equipped via the shared `_equip_in_inventory(item_id)` core (extracted from
`equip_selected()`); if the equip fails, the transfer is rolled back so BOTH
inventories end byte-identical to entry. The displaced worn item goes to the
player's carry inventory (reusing the existing equip semantics).

Two triggers reach it: the right-click *Equip* on a container row
(`context_actions` now offers `equip` for container equippables;
`_on_context_id` routes the container pane through `equip_from_container`), and
a drag of a container row onto an equipment slot (`zone_can_accept` /
`zone_drop` accept a `from_pane == "container"` payload). This supersedes the
ADR-0023 Amendment's interim "container rows don't offer Equip."

## Consequences

- No coordinator or persistence change; `_after_mutation()` already fires the
  coordinator's `transfer_completed` encumbrance + suit→oxygen recompute.
- Failure paths (transfer rejected, can't equip, displaced occupant has no
  carry room) all leave both inventories unchanged.
- Covered by `inventory_selection_model_smoke` (container row now offers equip)
  and `inventory_widget_smoke` Section C (right-click, drag, and the
  displaced-no-room rollback); regression bundle stays commands=119.

## Deferred

- Equipping more than one unit / auto-selecting the "best" item.
- A cart-both-hands gate on the panel equip path (it has none today).
