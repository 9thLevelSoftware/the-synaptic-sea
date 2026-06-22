# ADR-0014: Loot & player inventory (quantitied bag + deterministic containers)

Date: 2026-06-21
Status: Accepted
Related: ADR-0011 (ShipInstance & travel), ADR-0012 (world persistence),
ADR-0013 (derelict gameplay parity), docs/game/00_vision.md (North Star),
docs/superpowers/specs/2026-06-21-loot-player-inventory-design.md

## Context

ADR-0013 gave derelicts an objective loop but deliberately deferred the tangible
reward: completing a salvage objective yielded only a `cleared` flag. The North Star
makes loot the real "why board a derelict." The existing `InventoryState` was a
tool-set (unique ids, no quantities), insufficient to accumulate parts/supplies.

## Decision

Evolve `InventoryState` in place into a quantitied, categorized (part/supply/tool),
weight-capped bag, preserving its tool-surface shims (`add_tool`/`has_tool`/`tool_ids`/
`get_drain_multiplier`) so OxygenState, ToolPickup, and the junction gate are untouched.
A pure `LootRoller` rolls data-driven loot tables deterministically, seeded by
`marker_id + container_id`, so a given ship always yields the same loot and persistence
records only THAT a container was emptied. A `LootContainer` node (mirroring ToolPickup)
grants loot on interact. One container mechanism serves two spawn contexts: salvage
objectives gain a `loot_table`, and a new procgen pass scatters crates/lockers. Per-ship
looted state rides `ShipInstance.looted_container_ids`; the player bag rides the existing
`inventory_summary`.

## Consequences

- Loot is **derelicts only** this slice; the home ship keeps its tool pickups + singleton
  loop untouched (the ADR-0013 home-loop constraint). Unifying home onto the same mechanism
  follows the home/derelict convergence (ADR-0011 Approach B).
- Items are **inert**: #3 delivers acquire → carry (weight-gated) → persist. Consumption
  (repair spends parts) is #4; survival consumables are #2b. No drop/ship-storage UI yet.
- Loot is deterministic per seed, not random per visit, matching "ships persist once
  accessed." Re-rolling would let players farm one container — explicitly avoided.
- `max_weight` is a fixed constant; capacity upgrades are future scope.

## Note: transitional

Per ADR-0013's note and the North Star, the home/derelict split is transitional. Loot is
built as an any-ship system (the bag is player-global, the container mechanism is
ship-agnostic) precisely so the home ship can adopt it when the convergence lands.
