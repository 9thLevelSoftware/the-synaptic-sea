# ADR-0021: Equipment Slots, Carry Containers & Carts (PZ-faithful)

Date: 2026-06-23
Status: Accepted
Relates to: System 6 (Inventory & Equipment); ADR-0020 (ship cargo holds); ADR-0012 (world persistence); ADR-0007 (run-snapshot field freeze); PR #10 (PZ-style North Star).

## Context

System 6's player inventory + loot (#3) and ship cargo holds (ADR-0020) are
shipped. The next slice adds the worn-equipment and carry-container layer, modeled
on Project Zomboid: body-location equipment slots, worn containers that expand
carry capacity, soft-cap encumbrance with a Heavy Load penalty, and pushable carts
whose contents are off the player's personal encumbrance.

## Decision

1. **PZ soft-cap, player-only.** The player `InventoryState` no longer refuses
   `add_item` on weight — it accepts up to `max_stack` regardless of weight; the
   player may carry *over* capacity. `get_capacity()` = base (50) + worn-container
   bonus (+ a strength seam, default 0); `get_load_ratio()` / `is_over_capacity()`
   report the overage. Ship/cart holds (`ShipInventory`) stay **hard-capped** — only
   the player goes soft-cap. The `CargoTransfer` conservation invariant
   (remove == accepted) is unchanged; only cap-limited smoke expectations were
   re-validated.

2. **Heavy Load = movement only (this slice).** `Encumbrance` (pure-static) maps
   `load_ratio` to a PZ-tiered move-speed multiplier (1.0 at/under capacity; ~0.63
   at 125%; ~0.25 floor at/above 175%), wired to `PlayerController.move_speed`. PZ's
   endurance drain + over-encumbrance health damage are **deferred** — no
   player-condition (stamina/health) model exists yet.

3. **Worn equipment as a pure model.** `EquipmentState` (`RefCounted`) holds one
   item per body-location slot — `suit`, `back`, `waist`, `primary_hand`,
   `secondary_hand` (PZ body locations trimmed to what this game uses). Items declare
   their `equip_slot` in `ItemDefs`. Equipping moves an item OUT of the inventory pool
   into a slot (its own weight stops counting); unequip returns it. A worn container
   adds its `container_capacity` to the carry budget — PZ's per-bag contents-weight
   reduction **collapsed onto our single inventory pool** as a capacity bonus (no
   nested per-container item assignment; that is a deferred enhancement).

4. **Carts = separate zero-encumbrance containers.** A `CartState` (`RefCounted`,
   wrapping a `ShipInventory`) is a mobile container whose contents are **never**
   counted against the player's encumbrance — a cart *removes* weight, where a worn
   bag only *raises the cap* (matching PZ Build 42 carts). A `CartControl` (`Area3D`,
   mirrors `CargoHoldControl`) is grabbed to push: grabbing occupies **both hands**
   (blocks hand-slot equips) and applies a push speed multiplier (0.7); load/unload
   reuse `CargoTransfer`.

5. **Equipment effects are generic; suit→oxygen modeled, wired in Phase 7.** A worn
   item carries an `effects` block; `EquipmentState.get_oxygen_drain_multiplier()`
   aggregates suit effects. The multiplier is modeled + unit-tested now; composing it
   into the live oxygen hazard is a Phase-7 integration step (cross-system wiring is
   deferred per the isolate-then-integrate roadmap), so this slice does not touch
   `OxygenState`.

6. **Equip UX = auto-equip-on-pickup + seams; rich UI Phase 7.** Looting a container
   into an empty slot auto-equips it (raising capacity immediately); manual
   equip/unequip and the transfer/equipment screen are Phase-7 (same deferral as the
   cargo-holds withdraw picker). Validation seams drive the real equip/encumbrance/
   cart code paths now.

7. **Additive persistence, no version bump.** `WORLD_SLICE_VERSION` stays `"world-4"`.
   Player equipment rides a new `WorldSnapshot.player_equipment` field; derelict carts
   ride `ShipInstance.get_summary()["carts"]`; home-ship carts ride a new
   `WorldSnapshot.home_ship_carts` field (the home ship is saved through `WorldSnapshot`,
   not `visited_ships`). All are tolerant new keys — pre-slice saves load fine.
   `RunSnapshot` is untouched (ADR-0007 freeze).

## Consequences

- Carry capacity is now gear-driven: equip a backpack/tool-belt to haul more; over-pack
  and the Heavy Load penalty slows you.
- Carts enable bulk physical logistics between ships without touching personal carry
  weight — at the cost of both hands and reduced push speed.
- Save compatibility: additive; pre-slice saves load fine (no equipment, no carts).
- The `CargoHoldControl`/`HangarBayControl`/`CartControl` trio now share ~80% of an
  `Area3D` walk-up-gate pattern — a candidate to extract a shared base class in a
  follow-up (out of this slice's scope; tracked).

## Delivery

Shipped as two PRs off one design: **PR-A** = worn equipment + encumbrance (ItemDefs
metadata, `EquipmentState`, soft-cap `InventoryState`, `Encumbrance`,
`WorldSnapshot.player_equipment`, coordinator wiring); **PR-B** = carts (`CartState`,
`CartControl`, `ShipInstance.carts` + `WorldSnapshot.home_ship_carts`, coordinator cart
wiring). Each is an independently validated slice.

## Deferred (future slices)

- Player endurance/health + over-encumbrance damage → then full PZ Heavy Load.
- Nested per-container item assignment + per-bag weight-reduction %.
- Full clothing layering: protection (bite/scratch), insulation/temperature.
- Strength-skill capacity scaling (System 3 roster work).
- Live suit→oxygen-hazard composition (Phase 7 integration).
- Screen-space equipment/inventory/transfer UI (Phase 7).
- Cart edge cases: auto-drop on climb/board, multi-cart trains; shared walk-up-control base class.
