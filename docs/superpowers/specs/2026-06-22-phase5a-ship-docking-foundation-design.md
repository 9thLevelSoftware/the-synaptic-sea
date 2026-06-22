# Phase 5a — Ship Docking Foundation Design

Date: 2026-06-22
Status: Approved for implementation
System: 5 (Ship Docking & Ship-in-Ship) — foundational slice
Roadmap: `docs/game/09_system_roadmap.md` → "What remains" → B

## Goal

Replace the single-ship-at-shared-origin swap with co-present, world-space ship
entities physically joined at a walkable dock, and wire the canonical opening
(start aboard an unfixable starting derelict with the damaged lifeboat docked).
Establish the foundation that the rest of System 5 — port types, forced entry,
ship-in-ship hierarchy — and the long-term multi-ship future build on.

## Forward constraint (binding on this spec)

The foundation MUST treat ships as first-class, independently-positioned,
independently-simulatable world entities. No "single active ship at origin"
assumption may be baked in. The architecture must generalize cleanly to N
co-present ships to leave room for later goals the project has stated:

- Piloting more than one ship at a time (later game).
- Barotrauma-style ship-vs-ship interaction / eventual PvP.
- Project-Zomboid-style multiple owned "strongholds" (ships) persisting.

5a itself loads at most two ships (lifeboat + one docked derelict) — this is a
load bound, not an architectural one. Nothing in 5a may assume two is the max.

## Scope

### In scope (5a)

- Per-ship world-space subtrees (`ship_root` per `ShipInstance`); relocate
  gameplay roots from coordinator-origin to per-ship ownership.
- `DockingManager`: port-aligned dock/undock between two ships; writes the
  `parent_ship`/`docked_ships`/`docking_ports` stubs already on `ShipInstance`.
- A walkable dock connector (port alignment + guaranteed portal + optional
  bridge segment).
- Occupancy: spatial-containment source of truth for "which ship the player is
  aboard," driving active systems manager / HUD / objective tracker and save's
  current location. Replaces the `away_from_start` / `current_ship` global
  toggles.
- Canonical opening: start aboard an unfixable starting derelict with the
  damaged lifeboat docked; starting loot/repair relocate onto the derelict.
- Travel re-expressed as undock-here / dock-there, gated on being aboard the
  lifeboat.
- Relationship-based persistence (docking edge + occupancy; transforms
  recomputed on load).
- Validation smokes + regression registration.

### Out of scope (later sub-phases)

- **5b:** docking-port *types* (airlock / hangar bay / cargo clamp), size
  compatibility, broken-airlock forced-entry skill check.
- **5c:** ship-in-ship parent/child hierarchy (claim a repaired derelict and
  keep it nested in a hangar; nested ships travel together; pilot a second
  ship). Claiming/piloting a repaired derelict is NOT in 5a.
- Concurrent multi-ship hazard balancing beyond what the lifeboat + one
  (dead) starting derelict requires. Structure for it; do not tune it here.
- Flight/approach animation for travel (polish, Phase 7).

## Architecture

Chosen approach: **per-ship positioned subtrees + occupancy-driven active
context.** Rejected alternatives: a minimal two-ship special-case (bakes in the
single-active assumption the forward constraint forbids), and full
ship-as-autonomous-scene (over-built for a foundation; can grow out of this
later).

### Ship as a world-space entity

- Every `ShipInstance` owns a `ship_root: Node3D` placed at a distinct world
  transform under the coordinator. The ship's hull AND its gameplay roots
  (interactables, hazards, loot containers, repair points, objective volumes)
  reparent under its own `ship_root` — not the coordinator's local origin.
- The coordinator stops being where ships live; it becomes the registry /
  orchestrator of co-present ships. The current pattern of detaching the home
  gameplay roots when "away" (`_detach_starting_gameplay_roots`) is removed —
  roots no longer collide because each ship occupies its own transform, not a
  shared origin.

### DockingManager (new — pure coordinator)

- `dock(host, mobile, connector) -> Dictionary` — computes the transform that
  aligns `mobile`'s dock port to `host`'s dock port (coincident position,
  opposing facing) so floors are flush and the seam is a walkable portal.
  Applies it to `mobile.ship_root`, sets `mobile.parent_ship = host`, appends to
  `host.docked_ships`, records the connector in `docking_ports`. Returns
  `{success, reason}`.
- `undock(mobile) -> Dictionary` — clears the relationship; the mobile ship
  keeps its own `ship_root` (it is about to be repositioned or freed by the
  caller).
- Pure logic where possible: transform computation is a static helper testable
  without the scene tree; node application is the only tree-touching part.

### Dock port (alignment contract)

A dock port is a marked opening at a known local position + outward facing on a
ship. Two contracts make the join walkable:

- **Generation contract:** the derelict's guaranteed `dock` room gets a
  guaranteed wall *portal* (non-colliding doorway) on its dock-facing side.
  `WallDoorResolver` must not wall off the dock port. The lifeboat's `airlock`
  already carries its doorway.
- **Continuity:** if aligned ports leave a gap, `DockingManager` drops a
  lightweight connector floor segment to bridge it; if flush, none is added.
  The seam is always an open portal, never a wall.

This promotes `StartSceneBuilder._find_dock_position` from a smoke-only
"position with a 6-unit gap" to a runtime, port-aligned, walkable join.

### Occupancy

- A single source of truth: `current_occupancy` = the `ShipInstance` whose
  interior spatially contains the player, recomputed on movement across a dock
  seam (not a global boolean).
- Drives: which `systems_manager` is active for the player (life-support /
  oxygen consequences apply from the ship the player is breathing in), which
  objective set the HUD shows, and the saved current location.
- Seam tiebreak: when the player is exactly on a dock seam, the host ship wins
  (deterministic).
- Replaces `away_from_start` and the implicit "current_ship is the only live
  ship" coupling.

### Per-ship simulation

Each ship simulates its own systems; `ShipInstance.systems_manager` is already
per-ship. The starting derelict is dead/unfixable (no functional systems), so
5a's concurrent-simulation surface is intentionally small — but the structure
is correct for N live ships later. 5a does not tune concurrent hazards.

## Canonical opening wiring

The live boot changes from "lifeboat at origin" to a docked pair:

- **Starting derelict** — a dead, unfixable procgen structural shell (no
  functional systems), a guaranteed `dock` room with its dock port, and
  guaranteed starting-loot containers (the `repair_parts_starter` loot table)
  placed in its rooms. This is where #3 loot and #4 repair's *starting*
  placement relocates (off the lifeboat, onto the derelict).
- **Lifeboat** — fixed layout, docked at the derelict's dock port, propulsion
  offline (the #4 nav_linkage opening-damage is retained), repair point aboard
  the lifeboat.
- **Player spawns inside the starting derelict.**
- **Loop:** loot the derelict for parts → walk across the dock into the
  lifeboat → repair propulsion → undock → travel (lifeboat docks to the selected
  derelict; the starting derelict unloads, persisting by its home identity).
- **Home redefined:** "home" is the starting derelict, with the lifeboat as the
  mobile ship. `travel_home` = undock from the current derelict, return, re-dock
  the lifeboat to the starting derelict. Existing travel-home semantics hold;
  home is now a docked pair, and is effectively the player's first base.

## Travel re-expression

`travel_to_marker` / `travel_home` become docking operations:

1. Precondition: occupancy is the lifeboat. Otherwise return
   `{success:false, reason:"not_aboard_ship"}`.
2. Existing preconditions hold (in scanner range; propulsion operational —
   `travel_controller.gd`'s reason strings are preserved).
3. `DockingManager.undock(lifeboat)` from the current host.
4. Free the previous derelict's subtree (it persists by marker); instantiate the
   target derelict's subtree at a world transform via the existing procgen path.
5. `DockingManager.dock(targetDerelict, lifeboat, connector)`.
6. Recompute occupancy; the player is aboard the lifeboat throughout.

Because travel takes the lifeboat *with the player in it*, the player is never
separated from their ride — **stranding remains impossible**, by construction.

## Persistence

Relationships, not transforms (geometry regenerates from seed; dock transforms
are deterministic from port contracts):

- `WorldSnapshot` records:
  - the **lifeboat** `ShipInstance` summary (mobile player-owned ship: systems,
    repair, opening-damage state),
  - the **starting-derelict** `ShipInstance` summary (loot/objective state; its
    looted-container persistence already exists via the `home_looted_containers`
    field added in #4, which maps directly now that home is the derelict),
  - the **docking edge** (`lifeboat docked to: "home" | marker_id`),
  - **occupancy** (`aboard: "lifeboat" | "derelict:<id>"`).
- On load: rebuild both home ships → `DockingManager` recomputes the dock
  transform from port contracts → restore occupancy → place the player. Reuses
  the existing `get_summary`/`apply_summary` round-trip; no raw transforms are
  stored.
- `WorldSnapshot` version bumps per ADR-0007/0012; an incompatible save is
  rejected and falls back to a fresh run (existing behavior).

## Edge cases

| Case | Handling |
|------|----------|
| Dock attempted with no valid port | `push_error`; abort with reason `dock_failed`. |
| Travel while not aboard the lifeboat | Blocked, reason `not_aboard_ship` (falls out of occupancy). |
| Player exactly on a dock seam | Deterministic tiebreak: host ship wins. |
| Generation/load of a ship subtree fails mid-travel | Preserve existing `generation_failed` reason; do not leave a half-docked state — abort before freeing the previous derelict where possible. |

## Testing (definition of done)

- **Pure-model `DockingManager` smoke** — `dock()` aligns ports (coincident
  position, opposing facing, floor continuity); `undock()` restores; the
  transform is deterministic and computed without a scene tree.
- **Pure-model occupancy smoke** — player position inside ship A resolves to A;
  crossing into B flips occupancy; the seam tiebreak resolves to the host.
- **Main-scene canonical-opening smoke** — boot shows two `ship_root`s
  co-present at distinct transforms joined at the dock; the player traverses
  derelict → lifeboat across the seam (occupancy flips, using the existing
  `teleport_to` validation seam); looting the derelict yields the starting
  parts; repair lifeboat propulsion; undock; travel to a marker (lifeboat now
  docked to the new derelict, starting derelict unloaded); `travel_home`
  re-docks to the starting derelict; save/load preserves docking edge +
  occupancy + loot/repair state.
- **Regression bundle** — register the new smokes in
  `docs/game/06_validation_plan.md` (commands count rises from 73); full bundle
  and Gate-1 stay green. Only the allowlisted baseline noise is permitted.

## ADR

This is an architecture change (kills the shared-origin model, introduces
world-space ship entities + occupancy + DockingManager). It gets an ADR
(`docs/game/adr/0016-ship-docking-foundation.md`) recording the per-ship
subtree + occupancy decision and the rejected alternatives, authored as the
final implementation task.

## Files (anticipated)

- Create: `scripts/systems/docking_manager.gd` (+ smoke).
- Create: occupancy resolver (either `scripts/systems/ship_occupancy.gd` or a
  focused method set on the coordinator; decided in the plan) (+ smoke).
- Modify: `scripts/systems/ship_instance.gd` (activate `ship_root` + docking
  fields), `scripts/procgen/playable_generated_ship.gd` (per-ship subtrees,
  occupancy, travel re-expression, canonical opening), `scripts/systems/
  world_snapshot.gd` (docking edge + occupancy + starting-derelict state),
  procgen dock-port generation (`wall_door_resolver.gd` / derelict archetype),
  starting-loot relocation onto the derelict.
- Create: `scripts/validation/*` new smokes; register in
  `docs/game/06_validation_plan.md`.
- Create: `docs/game/adr/0016-ship-docking-foundation.md`.
