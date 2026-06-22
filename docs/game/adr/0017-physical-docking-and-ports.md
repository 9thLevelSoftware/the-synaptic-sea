# ADR-0017: Physical docking, typed ports & occupancy-gated boarding (Phase 5b)

Date: 2026-06-22
Status: Accepted
Related: ADR-0016 (ship docking foundation), ADR-0011 (ShipInstance & travel), ADR-0012 (world
persistence), ADR-0015 (ship repair loop), docs/game/09_system_roadmap.md (System 5),
docs/superpowers/specs/2026-06-22-phase5b-physical-docking-design.md

## Context

Phase 5a built the docking *foundation* (pure `DockingManager`/`ShipOccupancy`/`DockPorts` math,
per-ship world-space subtrees, the canonical docked opening) but did NOT make docking physical in
the running game. As merged, 5a still:

- **teleported the player into** a derelict generated at a fixed `DERELICT_DOCK_OFFSET` on travel —
  the lifeboat never undocked, moved, or re-docked;
- positioned the boot lifeboat at a fixed `LIFEBOAT_DOCK_OFFSET` and hand-wired the dock
  relationship — `DockingManager.dock()` (with real port alignment) ran ONLY in unit smokes,
  never in the live game;
- left occupancy non-functional in headless validation (`interior_aabb()` returned a zero-size
  AABB), so "which hull is the player in" was driven by a coarse `away_from_start` toggle.

5b makes the foundation load-bearing: real port-aligned docking at boot and on travel, a piloted
ship that is a genuine ride, typed ports with a condition-gated forced-entry breach, real
spatial occupancy, and a general dock-edge persistence model.

## Decision

Seven parts:

1. **Runtime port-aligned docking.** `DockingManager.dock()` is now called from the live game at
   boot (`_build_lifeboat_at_home`) and on travel, via a new `DockingManager.host_port_to_world`
   that lifts a ship-local port to world space through the host's `global_transform` (per the 5a
   port-space contract). The fixed `LIFEBOAT_DOCK_OFFSET` anchor is retired.

2. **`piloted_ship` + general dock-edge graph (binding forward constraint).** Travel is expressed
   as "the player's **piloted ship** undocks from its host and docks to a target," parameterized
   by a `piloted_ship` pointer (the lifeboat this cycle). Nothing says "the lifeboat travels."
   Persistence stores a **dock-edge set** (`[{host, mobile, port_type}]`), the piloted pointer,
   and occupancy — all consumed on load by `_apply_docking_snapshot` — so adding more live ships
   later is content, not a re-architecture. The at-most-two-loaded count is a content bound.

3. **Real occupancy from room geometry.** `ShipInstance.interior_aabb()` now derives a world AABB
   from the built `ShipStructure` room-node positions (robust off-tree / headless), so
   `recompute_occupancy()` is authoritative for active systems-manager / HUD / objective context.

4. **Physical travel; objectives activate on boarding.** `travel_to`/`travel_home` undock the
   piloted ship → free the old host → generate the target → re-dock port-aligned → spawn a closed
   dock barrier. The player STAYS aboard the piloted ship (a `_capture_player_carry`/`_apply_player_carry`
   affine round-trip carries them across the dock reposition); they are no longer teleported into
   the derelict. A target's objectives/loot activate when the player BOARDS it, not on arrival.
   `travel_to` is gated on occupancy == piloted ship (`not_aboard_ship`), and a port-compatibility
   precheck runs BEFORE the old host is freed (no half-undocked stranding).

5. **Typed ports + welding-speeded breach.** `DockPorts` carries `type`/`size_class`/`condition`
   and a pure `ports_compatible`; `condition_from_seed` makes a derelict's dock port intact or
   broken (middle tiers seed-split). The **airlock** is the only type exercised; hangar/cargo_clamp
   are valid typed values reserved for later cycles. A `DockPortBarrier` (Area3D, mirrors
   `RepairPoint`'s channel) gates the seam: intact opens in one interact; broken needs a timed
   **Welding**-speeded breach channel (no parts). `for_derelict` falls back to the **airlock** room
   when a ship has no `dock` room (the golden home ship has an airlock, no dock room).

6. **Boarding gated on the open barrier (the user's explicit "must open the port" choice).** Because
   the barrier is an Area3D sensor (it does not physically block a CharacterBody) and occupancy is
   spatial, the open/closed state would otherwise be cosmetic. So `_ship_boardable(inst)` excludes a
   host from the occupancy entries until its dock barrier is opened — a ship cannot be "boarded"
   (resolved as occupied) until the player breaches/opens its port. The piloted ship and lifeboat
   are never gated. An intact home barrier is spawned at boot so boarding home is consistent.

7. **Seam tiebreak superseded.** 5a's "host wins the dock seam" rule is replaced by "**the piloted
   ship wins containment**" (it is first in the occupancy entries): in the ride-aboard model the
   player is bodily in their ship until they breach the barrier and cross fully into the host. The
   spec edge-case table was updated to record this.

## Rejected alternatives

- **Keep menu-teleport travel with a cosmetic docked lifeboat**: does not deliver physical
  docking — the thing being replaced.
- **Re-anchor both ships to a neutral dock frame each travel**: transform churn with no gameplay
  benefit; fights the per-ship-world-transform model 5a established.
- **Make the lifeboat a privileged singleton mobile root**: bakes in the single-active assumption
  the vision forbids; the `piloted_ship` pointer + dock-edge set keep N-ship generalization.
- **Document the cosmetic barrier as "intent-only"**: rejected — it would silently defeat the
  user's explicit design choice that crossing REQUIRES opening the port. Boarding is gated instead.

## Consequences

- Travel is physically real: the lifeboat is a guaranteed ride that undocks, moves with the player,
  and re-docks; stranding is impossible by construction.
- Occupancy is real in headless. Known limitation (tracked): the generous `interior_aabb`
  (`ROOM_HALF_EXTENT=4.0`) makes the piloted ship's AABB overlap the host's near rooms, so the
  occupancy flip to the host happens only in host-only space past the overlap; the barrier is the
  boarding gate. Tightening `interior_aabb` (per-room footprint-aware) is a follow-up for crisper
  resolution.
- Persistence generalizes to N ships (dock-edge set), all four new `WorldSnapshot` fields are
  consumed on load, and a breached derelict stays boardable across save/load (`opened_ports`).
  `WORLD_SLICE_VERSION` bumped `world-1` → `world-2` (incompatible saves fall back to fresh).
- Deferred to later System 5 cycles: behavioral hangar-bay nesting (claim/pilot a repaired derelict,
  ship-in-ship) and cargo-clamp transfer (System 6). Pre-existing & unrelated: `main_coherent_boot_smoke`
  fails on baseline (`expected 4 objectives got 5`) independent of 5b — flagged for a separate fix.
- Validation: 7 new smokes added to the regression bundle (`commands` 81 → 88); full bundle and
  Gate-1 green.
