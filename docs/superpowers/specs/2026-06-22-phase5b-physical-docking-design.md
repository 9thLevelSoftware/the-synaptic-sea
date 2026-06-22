# Phase 5b — Physical Docking & Port Types Design

Date: 2026-06-22
Status: Approved for implementation
System: 5 (Ship Docking & Ship-in-Ship) — physical-travel + port-types slice
Roadmap: `docs/game/09_system_roadmap.md` → "What remains" → B
Builds on: Phase 5a foundation (`docs/superpowers/specs/2026-06-22-phase5a-ship-docking-foundation-design.md`)

## Goal

Make ship docking physical and real in the running game. Replace the
menu-teleport travel abstraction with an undock → generate → port-aligned-dock
loop in which the player's piloted ship is a genuine ride that moves with them,
and add typed dock ports with a condition-gated, welding-speeded forced-entry
breach for boarding derelicts.

## Why this exists (the 5a gap)

Phase 5a's spec described "travel re-expression" (undock the lifeboat, take it
with you, re-dock) and a port-aligned walkable join, but the merged
implementation did **not** deliver them:

- `travel_to` still **teleports the player into** a derelict generated at a
  fixed `DERELICT_DOCK_OFFSET`; the lifeboat never undocks, moves, or re-docks.
- `_build_lifeboat_at_home` parks the lifeboat at a fixed `LIFEBOAT_DOCK_OFFSET`
  and hand-wires `parent_ship`/`docked_ships`. It does **not** call
  `DockingManager.dock()`.
- `DockingManager.dock()` with real port alignment runs **only in the pure
  smokes** — never in the live game.

5a delivered the *foundation* (the pure `DockingManager`/`ShipOccupancy` math,
the `ShipInstance` hierarchy fields, co-present subtrees, the canonical-opening
boot). 5b makes that foundation load-bearing in the runtime.

## Forward constraint (binding — carried from 5a)

Ships are first-class, independently-positioned, independently-simulatable
world entities. No "single active ship" assumption may be baked into the
docking, travel, occupancy, or persistence **interfaces**. The architecture must
generalize cleanly to N co-present ships (later goals the project has stated:
piloting more than one ship, Barotrauma-style ship-vs-ship / PvP,
Project-Zomboid-style multiple owned strongholds).

The lifeboat is **not** privileged in the architecture. It is merely the ship
the player is *currently piloting* this cycle. Travel is expressed as "the
player's piloted ship undocks from its host and docks to a target," parameterized
by a `piloted_ship` pointer — never as "the lifeboat travels." The
at-most-two-ships-loaded count is a **content/perf bound for this cycle**, not an
architectural cap; the co-present-ship registry and dock relationships are stored
as a general graph so adding live ships later is content, not a rewrite.

## Scope

### In scope (5b)

- **Physical travel-docking:** `travel_to`/`travel_home` rewritten to undock the
  piloted ship → free the old host (persists by identity) → generate the target
  derelict → `DockingManager.dock(target, piloted, …)` repositions the piloted
  ship flush. Player rides the piloted ship; **no teleport into the derelict.**
- **Runtime `DockingManager` use** at both boot and travel, including the
  local→world host-port lift the 5a docstring specifies. Retires the
  `LIFEBOAT_DOCK_OFFSET` fixed-anchor hack.
- **Typed dock ports:** `type` (airlock / hangar / cargo_clamp), `size_class`,
  `condition` (intact / broken from seed), and a pure `ports_compatible(a, b)`
  predicate. Airlock is the only type *exercised*; the others are valid typed
  values with working compat logic, not yet spawned by content.
- **Dock-port barrier + breach interactable:** the derelict's dock seam spawns a
  closed barrier; an interactable opens it — intact in one interact, broken via a
  timed welding-speeded channel (reuses the ADR-0015 repair-channel pattern, no
  parts). Opening removes the barrier and marks the derelict boardable.
- **Real occupancy:** populate `ShipInstance.interior_aabb()` from built room
  node positions (not `global_transform`); `recompute_occupancy()` becomes the
  authoritative driver of active systems-manager / HUD / objective set. Split the
  host axis (which derelict the piloted ship is docked to) from occupancy (which
  hull the player's body is in).
- **General-graph persistence:** the dock-edge set, the piloted-ship pointer,
  occupancy, and per-derelict port-opened/breached flags.
- Validation smokes + regression registration; ADR-0017.

### Out of scope (later cycles)

- **Claim a 2nd functional ship / pilot switching** (repair a derelict's
  propulsion to claim it) — its own cycle.
- **Ship-in-ship hangar nesting** (nested ships travel together) — its own cycle;
  the hangar port *type* exists here but is not behaviorally wired.
- **Cargo-clamp transfer** — depends on System 6 ship inventory; the cargo_clamp
  port *type* exists here but is not behaviorally wired.
- **Flight/approach animation** for travel (Phase 7 polish; travel repositions
  instantaneously).
- Concurrent multi-ship hazard balancing (structure for N; do not tune here).

## Architecture

Chosen approach: **uniform ship entities + a `piloted_ship` pointer + a general
dock graph.** Every `ShipInstance` remains a uniform world-space entity (the 5a
model); the piloted-ship pointer parameterizes travel; dock relationships persist
as an edge set over N ships. Rejected: re-anchoring both ships to a neutral dock
frame each travel (transform churn, fights the per-ship-world-transform model);
keeping teleport with a cosmetic docked lifeboat (does not deliver physical
docking — the thing being replaced).

### Components

**1. Typed `DockPort` descriptor** — `scripts/systems/dock_ports.gd` (extend).
`for_lifeboat()`/`for_derelict()` gain `type`, `size_class`, `condition`. Add a
pure static `ports_compatible(a: Dictionary, b: Dictionary) -> bool` (compatible
type + size fits). Pure/unit-testable; no scene tree.

**2. `DockingManager` runtime integration** — `docking_manager.gd` + coordinator.
Call `dock()` from the live game at boot (`_build_lifeboat_at_home`) and travel.
Add the local→world host-port lift (`host.scene_root.global_transform *
local_port`) so a non-origin host docks correctly per the existing port-space
contract. The pure `dock()`/`undock()`/`compute_mobile_transform()` are unchanged.

**3. Real occupancy** — `ship_instance.gd` + `ship_occupancy.gd` + coordinator.
`interior_aabb()` is computed from built room node positions (robust off-tree /
headless, where `global_transform` is identity — the bug 5a worked around).
`recompute_occupancy()` is authoritative for active systems-manager / HUD /
objective set. The **host axis** (piloted ship's current host derelict) stays as
the load/travel pointer; **occupancy** (player's hull) drives context.
Consequence: a target derelict's objectives activate when the player *boards* it,
not on arrival.

**4. Dock-port barrier + breach interactable** — new, mirrors `repair_point.gd`.
The derelict dock seam spawns a **closed barrier** (collider) with the port's
`condition`. An interactable on it: intact → one interact opens; broken → a timed
welding-speeded channel (reuse the repair-channel timing/skill pattern, no parts)
then opens. Opening frees the barrier, sets the derelict's port-opened flag, and
makes the seam walkable.

**5. Travel re-expression** — `playable_generated_ship.gd`. `travel_to` /
`travel_home` rewritten to the undock → free → generate → `dock()` →
spawn-closed-barrier sequence, parameterized by `piloted_ship`. The player is
**not** teleported into the derelict — they stay aboard and cross the port
themselves.

## Data flow

### Travel (`travel_to`; piloted ship = lifeboat this cycle)

1. Preconditions: occupancy == piloted ship (aboard the ride) and propulsion
   operational. Else `not_aboard_ship` / the existing `travel_controller` reason
   strings (preserved verbatim).
2. `DockingManager.undock(piloted)` from its current host.
3. Free the current host derelict subtree (persists by identity); generate the
   target derelict subtree at a world anchor via the existing procgen path.
4. Lift the target's local dock port to world; `DockingManager.dock(target,
   piloted, …)` repositions the piloted ship so its airlock aligns flush.
5. Spawn the target's dock barrier **closed**, condition from seed.
6. `recompute_occupancy()` — player is still inside the piloted ship; the HUD
   shows the piloted ship's context until the player breaches/opens and crosses.
   No teleport into the derelict.

### Boarding (breach/open)

Interact on the barrier → intact: open immediately; broken: welding-speeded timed
channel → open. Barrier removed, derelict marked boarded, port-opened flag set.
Crossing the now-open seam flips occupancy → target derelict; its
objectives/loot/HUD activate (component 3).

`travel_home` is the same sequence with the home (starting) derelict as the
target; symmetric.

## Persistence

Relationships, not transforms (geometry and dock transforms are deterministic):

- The **dock-edge set** — general `[{host, mobile, port}]` over N ships (today
  one edge, stored as a set so N is structural).
- The **piloted-ship pointer** and **occupancy** (`aboard: <ship_id>`).
- Per-derelict **port-opened/breached** flag (a breached derelict spawns
  already-open on revisit).
- Existing per-ship `get_summary`/`apply_summary` (systems / repair / loot /
  objective state) reused unchanged.

On load: rebuild ships → re-apply dock edges → `DockingManager` recomputes
transforms → restore occupancy + piloted pointer → restore opened barriers →
place the player. `WorldSnapshot` version bumps per ADR-0007/0012; an
incompatible save is rejected and falls back to a fresh run (existing behavior).

## Edge cases

| Case | Handling |
|------|----------|
| Travel while not aboard the piloted ship | Blocked, reason `not_aboard_ship` (falls out of occupancy). |
| Target generated with no compatible dock port | Generation contract guarantees a piloted-compatible airlock on every travel target, so it cannot occur for content. If `ports_compatible` ever fails, abort with `dock_incompatible` **before** freeing the current host (no half-undocked state). |
| `dock()` fails mid-travel after old host freed | Preserve `generation_failed` / `dock_failed`; the piloted ship keeps its own root and the player stays aboard — never stranded. Re-dock to home as the fallback. |
| Player exactly on a dock seam | Deterministic tiebreak: host ship wins (5a rule, kept). |
| Breach interrupted (player walks away mid-channel) | Channel resets; barrier stays closed; re-interact restarts (repair-channel semantics). |
| Revisit a breached derelict | Port-opened flag persists → barrier spawns already-open. |
| Occupancy AABB degenerate / zero | Fall back to the host-axis pointer so active context is never null (defensive, not the primary path). |

## Testing (definition of done)

- **Pure-model `DockPort` smoke** — `ports_compatible` over a type+size matrix
  including at least one incompatible pair; airlock↔airlock compatible.
- **Pure-model occupancy smoke** — real AABBs: player inside ship A resolves to A;
  crossing into B flips; the seam tiebreak resolves to the host.
- **Main-scene physical-docking smoke** — boot uses `DockingManager` port-aligned
  docking (not the fixed offset); travel performs undock → generate → dock with
  the piloted ship repositioned flush and the player **still aboard the lifeboat**
  (not teleported into the derelict).
- **Main-scene breach smoke** — an intact port opens in one interact; a broken
  port requires the welding-speeded channel; crossing the opened seam flips
  occupancy and activates the derelict's objectives.
- **Main-scene travel/persistence smoke** — `travel_home` re-docks to the starting
  derelict; save/load round-trips the dock-edge set + piloted pointer + occupancy
  + breached flags.
- **Regression bundle** — register the new smokes in
  `docs/game/06_validation_plan.md` (commands count rises from 81); full bundle
  and Gate-1 stay green. Only allowlisted baseline noise permitted.

## ADR

This changes architecture (runtime port-aligned docking, real occupancy,
piloted-ship + dock-graph model, teleport-travel retired, typed ports). It gets
`docs/game/adr/0017-physical-docking-and-ports.md`, recording the decisions and
the rejected alternatives, authored as the final implementation task.

## Files (anticipated)

- Modify: `scripts/systems/dock_ports.gd` (typed ports + `ports_compatible`).
- Modify: `scripts/systems/docking_manager.gd` (world-lift helper if not folded
  into the coordinator), `scripts/systems/ship_instance.gd` (real
  `interior_aabb`), `scripts/systems/ship_occupancy.gd` (authoritative resolve).
- Modify: `scripts/procgen/playable_generated_ship.gd` (runtime docking at
  boot+travel, travel re-expression, occupancy-driven context, barrier spawn),
  procgen dock-port generation (port condition from seed), `scripts/systems/
  world_snapshot.gd` (dock-edge set + piloted pointer + occupancy + breached
  flags).
- Create: dock-port barrier + breach interactable script (mirrors
  `repair_point.gd`).
- Create: `scripts/validation/*` new smokes; register in
  `docs/game/06_validation_plan.md`.
- Create: `docs/game/adr/0017-physical-docking-and-ports.md`.
- Update: `docs/game/09_system_roadmap.md` (correct the stale System 5 "Not
  started" status — the 5a foundation is merged and 5b makes docking physical).
