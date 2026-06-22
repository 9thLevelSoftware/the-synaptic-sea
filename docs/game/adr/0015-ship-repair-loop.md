# ADR-0015: Ship repair loop (parts-gated timed repair; lifeboat travel gate)

Date: 2026-06-21
Status: Accepted
Related: ADR-0011 (ShipInstance & travel — retires its "derelicts always travel-capable"
placeholder), ADR-0012 (world persistence), ADR-0013 (derelict gameplay parity),
ADR-0014 (loot & player inventory), docs/game/00_vision.md (North Star),
docs/superpowers/specs/2026-06-21-ship-repair-loop-design.md

## Context

ADR-0014 let the player accumulate parts but nothing consumed them. The existing
`ShipSubcomponent.repair` model was gated on parts/tools/skill but only ever driven by
`force_repair` (no inventory). Travel from a boarded derelict faked full capability
(ADR-0011 placeholder). The North Star makes repair the spine: loot → repair → fly.

## Decision

`ShipSystemsManager.repair_with_inventory` runs the existing deterministic gated repair using
the player's `InventoryState` and consumes the required parts on success. A `RepairPoint`
Area3D node drives a Project-Zomboid-style timed channel in its OWN `_process` (independent of
the coordinator's frozen per-frame loop, so no `_process` freeze lift), cancels with no part
loss if the player leaves range, and calls the gated repair on completion. The coordinator
builds repair points from the live systems manager (one per damaged subcomponent, distributed
across rooms) for the lifeboat AND derelicts. `_current_systems_ops()` now reads the lifeboat's
real systems in all states — travel capability lives in the player's functional ship, so a
boarded derelict's broken systems never strand the player, and an unrepaired lifeboat cannot
jump until its propulsion is restored. The lifeboat boots with propulsion offline (one
low-skill blocker, `nav_linkage`); the starting area's guaranteed loot supplies the part.

## Consequences

- The opening loop is "loot the starting area → repair the lifeboat's propulsion → first jump."
- Loot is lifted to an any-ship system (the starting ship now has loot containers).
- The existing home objective→`force_repair` bridge is untouched; repair points are an additional
  parts-gated path. Gate-1 and the completion loop stay green.
- Repaired state persists for free (existing `ship_systems_summary` / per-ship slice).
- `travel_home()` is always available — the no-strand guarantee.

## Non-goals (deferred)

- Multi-ship docking entity, cannibalizing, owning two ships — Phase-5 docking follow-on.
- Crafting (generic salvage is inert feedstock); a repair-skill progression curve; timed-channel
  persistence (a repair in progress is transient).

## Note: transitional

Per the North Star, the lifeboat/derelict split is transitional toward a uniform `ShipInstance`.
Repair is built as an any-ship system precisely so a fully repaired derelict can later become a
second functional vessel without re-architecture.
