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
