# ADR-0016: Ship docking foundation (per-ship world-space subtrees; occupancy; canonical docked opening)

Date: 2026-06-22
Status: Accepted
Related: ADR-0011 (ShipInstance & travel), ADR-0012 (world persistence), ADR-0013 (derelict
gameplay parity), ADR-0015 (ship repair loop), docs/game/00_vision.md (North Star),
docs/game/09_system_roadmap.md (System 5), docs/superpowers/specs/2026-06-22-phase5a-ship-docking-foundation-design.md

## Context

Before this change the coordinator (`playable_generated_ship.gd`) placed the home ship and
every traveled derelict at its OWN local origin and, on travel, DETACHED the home gameplay
roots and ATTACHED the derelict at the same origin — only one ship was ever live in the tree.
That single-active-at-origin swap is a dead end for everything the vision needs next:
multiple ships piloted at once, Barotrauma-style ship-vs-ship, and Project-Zomboid-style
multiple owned "strongholds". The canonical opening (start aboard an unfixable derelict with a
damaged lifeboat docked; loot the derelict → repair the lifeboat → travel) also could not be
expressed: there was no way for two ships to be physically co-present and walkable.

## Decision

This is the foundational slice of System 5 (Phase 5a). Five parts:

1. **Per-ship world-space subtrees.** Each `ShipInstance` owns a `ship_root: Node3D` (a property
   alias of `scene_root`) placed at a distinct world transform. A traveled derelict is now
   co-present with the home ship at `DERELICT_DOCK_OFFSET` rather than overwriting it at the
   origin; the derelict's own gameplay roots (objectives, loot, repair points) parent under its
   positioned `scene_root` so they move and free with it. The detach/reattach-home coupling and
   its helpers are deleted.

2. **Pure helpers.** `DockingManager` (yaw-only transform that aligns two ships at coincident,
   opposing dock ports + writes the `parent_ship`/`docked_ships`/`docking_ports` relationship),
   `ShipOccupancy` (first-entry-priority AABB containment resolver), `DockPorts` (derives a
   dock-port descriptor from a layout), and `ShipInstance.interior_aabb()`. All are
   `RefCounted`, scene-tree-free, and independently smoke-tested.

3. **Occupancy-driven active context.** "Which ship the player is aboard" derives from spatial
   containment (`current_occupancy`), kept in lockstep with the existing `away_from_start` flag.
   (Note: `interior_aabb()` is effectively zero in headless validation — occupancy is exercised
   in-game and weakly in smokes; 5a's gates do not depend on it.)

4. **Canonical opening — LEAN Option A (user-approved).** The home ship STAYS the rich, fully
   validated golden `coherent_ship_001` slice — conceptually "the derelict" the player explores
   and loots (its objectives, hazards, route-control, and the guaranteed `repair_parts_starter`
   loot are unchanged). A physical 3-room `LifeBoatBuilder` ship is docked to it and SHARES the
   home `ship_systems_manager` (ADR-0015 already treats those systems as "the lifeboat's"). Only
   the repair point's parent node moves into the lifeboat, so the player physically repairs in
   the docked lifeboat. The alternative — replacing the golden slice with a bare structural shell
   to match the spec's literal "dead shell" wording — was rejected: it would discard the
   most-validated artifact in the repo and break a swath of the home-slice validation suite for
   no gameplay gain.

5. **Deterministic lifeboat persistence.** The lifeboat carries no independent state (it shares
   the persisted systems manager and is rebuilt from `LifeBoatBuilder` at home), so it needs no
   new `WorldSnapshot` fields — it is rebuilt and re-docked on every reload.

## Rejected alternatives

- **Minimal two-ship special-case** (keep coordinator-origin roots, bolt the derelict on at an
  offset, hard-code the pair): bakes in the single-active assumption the vision forbids; does not
  generalize to N ships.
- **Full ship-as-autonomous-scene now**: over-built for a foundation; relocating coordinator
  responsibilities into ship scenes is deferred.
- **A `not_aboard_ship` travel gate** (require the player be inside the lifeboat to travel):
  unimplementable under lean Option A (shared systems + zero headless AABB) and unnecessary —
  ADR-0015's propulsion gate already enforces no-stranding. Aboard-ship gating is deferred to the
  multi-ship-ownership phase (5c).

## Consequences

- 5a loads at most two ships (home derelict + lifeboat at home; + one traveled derelict when
  away) — a load bound, not an architectural one. The structure generalizes to N co-present,
  independently-positioned, independently-simulatable ships.
- The canonical opening is live: explore + loot the derelict, walk to the docked lifeboat, repair
  its propulsion, travel. All #4 repair/travel/opening-damage semantics are preserved.
- Deferred to later sub-phases: port-aligned docking of traveled derelicts and the lifeboat to
  the golden ship (5a uses a fixed offset/anchor; `coherent_ship_001` has no dock room) — System
  5b (port types, forced entry); full per-ship systems separation, ship-in-ship hierarchy, and
  owning/piloting a repaired derelict — System 5c.
- Validation: 8 new smokes added to the regression bundle (`commands` 73 → 81).
