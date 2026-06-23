# Phase 5d — Hangar Nesting (Design)

Date: 2026-06-23
Status: Approved (brainstorm). Final sub-cycle of **System 5 — Ship Docking &
Ship-in-Ship**. Extends merged 5a (DockingManager, ShipOccupancy, ShipInstance
parent/child hierarchy), 5b (physical docking, typed DockPorts, DockPortBarrier,
piloted_ship pointer, dock-edge persistence), and 5c (ShipAccessState
login-ownership, BridgeTerminal, set_piloted_ship pilot-switch, one-level
rigid-pair travel, world-3 persistence).

## Goal

Let a ship physically store other ships inside a **hangar bay** and carry them as
a nested fleet. Generalize 5c's *one-level* rigid-pair travel to **arbitrary
depth**: a chain of docked/bayed ships rides rigidly with whichever ship the
player pilots, at any nesting depth. Bays are a new asymmetric **hangar port
type** with fixed slots; docking and launching are **physical** walk-up
interactions, consistent with every docking-era interaction so far. There is no
HUD/menu — the screen-space layer stays deferred to Phase 7.

## Forward constraints (design seams, unchanged from 5a–5c)

- **N ships / N players.** The ownership/access model (5c) and the dock-edge
  forest are already general; 5d adds nothing player-specific. Multiplayer access
  UI remains a post-Phase-7 seam.
- **Resources are data, Nodes are behavior.** `HangarBay` is pure `RefCounted`;
  `HangarBayControl` is a behavior-only `Area3D` sensor.
- **Physical interaction, not HUD.** Dock/launch is a walk-up control, mirroring
  `BridgeTerminal` / `RepairPoint` / `DockPortBarrier`. No screen-space panel.

## Architecture

Chosen approach: **unify hangar nesting under the existing dock graph; a hangar
is a richer port type** (not a parallel subsystem). Rationale: each
`ShipInstance` already carries one `parent_ship` + a `docked_ships` array — the
dock relationship is already a *forest*, and `_current_dock_edges()` already
emits one persisted edge per parented ship, so the data model and persistence are
**already arbitrary-depth**. The genuine new surface is therefore bounded to: the
hangar port type, slot bookkeeping, the physical control, and generalizing the
*travel reposition* (the only genuinely one-level piece) from a single hop to a
DFS over the subtree.

### What a hangar bay is

- A **hangar** is a *weighted* (not guaranteed) procgen derelict room role,
  exactly how `bridge` gates claimability in 5c. A derelict that rolled a hangar
  exposes a bay; one that did not is loot/explore-only. The **home ship** also
  has a bay (your base can hold your fleet) — see the home-layout prerequisite
  below.
- A bay has **fixed slots**. Slot count is derived deterministically from the
  hangar room's floor footprint (number of floor cells, integer-divided by a
  per-slot cell budget) so a bigger hangar holds more ships — no magic constant.
  Each slot holds at most one ship and is gated by **size class**: a slot accepts
  a ship whose docking-port `size_class` is `<= slot_size_class`.
- Hangar docking is **asymmetric**: unlike airlock-to-airlock (symmetric, equal
  type + size_class), a hangar bay *contains* a smaller ship. `ports_compatible`
  gains a hangar branch: bay accepts ship iff `ship.size_class <=
  bay.slot_size_class` **and** a slot is free.

### Components

**New:**

- `scripts/systems/hangar_bay.gd` — `HangarBay extends RefCounted`. Pure data,
  independently unit-testable.
  - Fields: `slot_count: int`, `slot_size_class: int`, `slots: Array[String]`
    (each `""` for empty or a bayed `ship_id`).
  - `free_slot_for(size_class: int) -> int` — first empty slot index if
    `size_class <= slot_size_class`, else `-1`.
  - `dock(ship_id: String, size_class: int) -> int` — fills the first free
    compatible slot; returns its index or `-1` on no fit / already bayed.
  - `launch(slot_index: int) -> String` — empties the slot; returns the
    `ship_id` it held (or `""`).
  - `slot_of(ship_id) -> int`, `is_full() -> bool`.
  - `get_summary()` / `apply_summary(dict) -> bool` round-trip
    (`slot_count`, `slot_size_class`, `slots`).
- `scripts/tools/hangar_bay_control.gd` — `HangarBayControl extends Area3D`.
  Sensor + signal only; the coordinator owns all consequences (mirrors
  `BridgeTerminal`).
  - `configure(carrier_ship_id: String, slot_anchors: Array, radius := 1.8)`.
  - `try_dock(player_body, slot_index) -> bool` / `try_launch(player_body,
    slot_index) -> bool` — strict in-range gate (same pattern as
    `DockPortBarrier._is_player_in_direct_range`).
  - signals `bay_dock_requested(carrier_id: String, slot_index: int)` /
    `bay_launch_requested(carrier_id: String, slot_index: int)`.

**Modified:**

- `scripts/systems/dock_ports.gd`
  - `for_hangar(layout: Dictionary, seed_value := 0) -> Dictionary` →
    `{type:"hangar", slot_count:int, slot_size_class:int,
    slot_anchors:Array[Vector3]}` derived from the `hangar` room footprint
    (floor-cell centers give the per-slot anchors; `slot_count` =
    `floor(floor_cells / CELLS_PER_SLOT)`, min 1; `slot_size_class` from the
    room's size). Returns `{}` when no hangar room exists.
  - `ports_compatible(a, b)` gains the asymmetric hangar branch described above,
    while the existing symmetric airlock path is unchanged.
- `scripts/systems/ship_instance.gd` — lazy `hangar` (`HangarBay`) field +
  `get_hangar()`; `has_hangar() -> bool`; round-trip under `"hangar"` in
  `get_summary` / `apply_summary` (only when a bay exists).
- `data/procgen/archetypes/derelict.json` — add `"hangar"` to `role_weights`
  (weighted, not guaranteed — same shape as the 5c `bridge` addition).
- `scripts/validation/derelict_generator_smoke.gd` — authorize `hangar` in the
  "no system roles on derelicts" invariant (the same precedent that admitted
  `bridge` in 5c); all other system roles stay forbidden.
- `data/procgen/golden/coherent_ship_001/` (home-layout prerequisite) — add a
  `hangar` room to the home ship's golden layout so the home bay has real volume
  for slot anchors. **Risk to manage in the plan:** any standalone smoke that
  asserts on `coherent_ship_001`'s exact room set / count must be updated in the
  same task; the plan's first task adds the room and re-greens those smokes
  before any 5d behavior is built.
- `scripts/procgen/playable_generated_ship.gd` (coordinator)
  - `_spawn_hangar_controls(inst)` / `_clear_hangar_controls()` — spawn a
    `HangarBayControl` in each bay-bearing ship, wired to
    `_on_bay_dock_requested` / `_on_bay_launch_requested`. Reset-only clear
    (mirrors `_clear_bridge_terminals`), pruned per ship id.
  - `_on_bay_dock_requested(carrier_id, slot_index)` /
    `_on_bay_launch_requested(carrier_id, slot_index)` — gate + apply, silent
    refusal on failure (5c convention).
  - Generalize the one-level rigid-pair functions to a DFS:
    `_capture_subtree(root)` / `_reposition_subtree(root, captured)` walk the
    entire `docked_ships` subtree (airlock children **and** bayed children, any
    depth), recording/re-applying each node's transform relative to the piloted
    root. The 5c one-level case becomes depth-1 of the same walk. Replaces
    `_capture_docked_children` / `_reposition_docked_children` at their two call
    sites (travel_to and world-load).
  - Generalize load-path geometry reconstruction (`_ensure_derelict_geometry`)
    from "current-location endpoints" to **every parented ship in the forest**,
    placing bayed ships at their slot anchors before re-docking.
- `scripts/systems/world_snapshot.gd` — dock edges gain `port_type`
  (`"airlock"`|`"hangar"`) and `slot_index` (`-1` for airlock); bump
  `WORLD_SLICE_VERSION` `"world-3"` → `"world-4"`.

## Data flow

1. **Dock a ship into a bay (physical).** The player walks to the carrier's
   `HangarBayControl` while a candidate ship is co-present and airlock-docked to
   the carrier (the 5c rigid-pair state). The control fires
   `bay_dock_requested(carrier_id, slot_index)`. The coordinator resolves carrier
   + candidate, gates on `ports_compatible(bay, candidate_airlock)` and
   `bay.free_slot_for(size_class) != -1`. On pass: `DockingManager.undock` the
   candidate from its airlock edge, `bay.dock(ship_id, size_class)`, set
   `candidate.parent_ship = carrier` and append to `carrier.docked_ships`,
   reposition `candidate.scene_root` to the slot anchor (carrier-local). On fail:
   silent refusal, reason `no_free_slot` / `incompatible_size` / `not_co_present`.
2. **Recursive rigid-pair travel.** When the piloted ship travels,
   `_capture_subtree(piloted)` DFS-records every descendant's transform relative
   to the piloted root; after the dock move, `_reposition_subtree` re-applies them
   top-down so the whole nested group rides rigidly, at any depth.
3. **Launch a bayed ship.** At the control, `bay_launch_requested(carrier_id,
   slot_index)` → `bay.launch(slot)`, clear `parent_ship` / remove from
   `docked_ships`, reposition the launched ship to a computed free co-present
   anchor near the carrier. It is then an ordinary co-present ship (claim/pilot
   via its bridge per 5c, unchanged).
4. **Occupancy / boarding.** A bayed ship gets **no** airlock breach barrier — it
   sits inside the carrier's volume and is reached by walking into the bay
   (occupancy by `interior_aabb`, unchanged). Piloting still requires being aboard
   + bridge login (5c, untouched).

## Persistence (world-4)

The edge forest is already general, so saving adds only the two new fields per
edge (`port_type`, `slot_index`). Load:

- reconstructs the **full** parented forest geometry (every parented ship, not
  just current-location endpoints);
- re-pegs each `HangarBay`'s slot occupancy from the hangar edges;
- places bayed ships at their slot anchors, then re-establishes
  `parent_ship` / `docked_ships`.

**Forward compatibility:** world-3 saves load under world-4 — a missing
`port_type` defaults to `"airlock"` and a missing `slot_index` to `-1`, so a
pre-5d save (airlock edges only) restores exactly as before.

## Error handling & edge cases

| Case | Behavior |
|---|---|
| Dock when no free slot | Refused, `no_free_slot`; nothing moves. |
| Candidate too large for slot size-class | Refused, `incompatible_size`. |
| Dock requested but candidate not co-present / airlock-docked to carrier | Refused, `not_co_present`. |
| Bay-dock a ship that itself has bayed children | Allowed; the DFS travel walk carries the whole subtree. |
| Launch | Launched ship goes to a computed free co-present anchor; never overlaps the carrier. |
| Reload-to-home / reset | Sever the full forest cycles (`parent_ship` / `docked_ships`, already done in 5c) **and** clear `HangarBay` slots — no leaked RefCounted at exit. |
| Home ship bay | Same machinery; home is never pilotable but can *store* ships. |
| Derelict with no hangar room | No bay, no control — loot/explore only (mirrors no-bridge in 5c). |
| Travel while piloting a ship whose propulsion broke | Existing 5c propulsion travel-gate still applies; unchanged. |

## Testing (validation smokes)

Six new smokes, registered in `06_validation_plan.md` (commands 94 → 100):

- `hangar_bay_smoke` — pure model: dock / launch / `free_slot_for`, size-class
  gate, slot-full refusal, `slot_of`, summary round-trip.
- `hangar_port_smoke` — `DockPorts.for_hangar()` derives `slot_count` /
  `slot_size_class` / anchors from a hangar layout; `ports_compatible` asymmetric
  accept (small ship into big bay) and reject (oversize / no slot).
- `hangar_control_smoke` — node-level: in-range fires `bay_dock_requested` /
  `bay_launch_requested`; out-of-range no-op.
- `bay_dock_launch_smoke` — coordinator: dock a co-present ship into a slot, then
  launch it back to a co-present anchor; refusals gated
  (`no_free_slot` / `incompatible_size` / `not_co_present`).
- `recursive_travel_smoke` — a depth-≥2 nested group (a ship bayed in a ship that
  is airlock-docked to the piloted ship) all moves rigidly on travel; port
  positions track within tolerance.
- `hangar_persistence_smoke` — bay a ship, travel, save → load: `port_type` /
  `slot_index`, slot occupancy, bayed-ship geometry, and the forest all survive
  the round-trip (extends the 5c claim-persistence pattern).

Plus a full regression bundle + Gate-1 run with the `project.godot` drift
stashed (`git stash push -- project.godot` before the bundle/Gate-1, pop after).

## Scope boundaries (what this cycle is deliberately NOT)

- **Deferred to Phase 7 (UI/HUD):** any screen-space hangar panel, capacity
  readouts, fleet list. 5d ships the *physical* control only.
- **Deferred to System 6 (Inventory):** cross-ship cargo/inventory transfer
  between a carrier and its bayed ships.
- **Out of scope:** launch-in-flight / combat, hangar repair mechanics, and
  hangar doors as a separate breachable barrier (a bayed ship has no airlock
  seam this cycle).

## ADR

Record the hangar port type + fixed-slot bay + arbitrary-depth (DFS) rigid-pair
travel as **ADR-0019**, cross-referencing ADR-0016 (docking foundation),
ADR-0017 (physical docking + ports), and ADR-0018 (claim + pilot-switch).
