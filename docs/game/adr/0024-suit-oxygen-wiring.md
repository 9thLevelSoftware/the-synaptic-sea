# ADR-0024: Live Suit→Oxygen Wiring (Phase 7 sub-project B)

Date: 2026-06-24
Status: Accepted

## Context
The `hardsuit` declared an `oxygen_drain` effect (0.75) and
`EquipmentState.get_oxygen_drain_multiplier()` already computed the product of
worn `oxygen_drain` effects, but that value never reached `OxygenState`, so
wearing the suit had no effect on live breach drain. The only gap was the
coordinator seam.

## Decisions
1. **Separate model seam** `OxygenState.apply_equipment_summary({"drain_multiplier": …})`
   mirrors `apply_inventory_summary`; the combination rule lives in the pure
   model, not the coordinator. `_inventory_summary` keeps meaning exactly what
   `InventoryState` reported.
2. **Multiplicative stacking** — effective breach multiplier =
   `inventory_mult × equipment_mult`, hard-gated to 1.0 when the breach is
   sealed/closed (drain is suppressed there anyway).
3. **No new persistence** — the equipment multiplier is recomputed live each
   frame from `equipment_state` (which already persists via `player_equipment`);
   `apply_summary` does not restore it (symmetric with the inventory summary).
4. The coordinator `_refresh_oxygen_state` applies the equipment summary before
   `tick` on every frame.

## Consequences
Equipping the hardsuit reduces live breach drain (×0.75; ×0.375 with the
portable oxygen pump). `OxygenState.get_summary()` exposes both the combined
`drain_multiplier` and the `equipment_drain_multiplier` component. Deferred:
HUD surfacing of the suit contribution (sub-project C); re-tuning the 0.75
value (sub-project D); suit air-supply depletion (future system).
