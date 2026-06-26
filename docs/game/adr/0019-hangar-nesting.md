# ADR-0019: Hangar nesting — hangar port type, fixed-slot bays & arbitrary-depth travel (Phase 5d)

Date: 2026-06-23
Status: Accepted
Related: ADR-0016 (ship docking foundation), ADR-0017 (physical docking & ports),
ADR-0018 (claim & pilot-switch), ADR-0011 (ShipInstance & travel),
ADR-0012 (world persistence), docs/game/09_system_roadmap.md (System 5),
docs/superpowers/specs/2026-06-23-phase5d-hangar-nesting-design.md

## Context

Phase 5c generalized `piloted_ship` to any claimed working vessel and added **one-level**
rigid-pair travel: the lifeboat docked to a claimed derelict travels with it. ADR-0018 explicitly
deferred to 5d the remaining docking work: storing ships inside other ships (a hangar bay),
recursive / arbitrary-depth nesting, and the hangar-bay interaction. This is the final sub-cycle
of System 5 — after it, a ship can physically carry a nested fleet.

The dock relationship was already a forest at the data level: every `ShipInstance` has one
`parent_ship` and a `docked_ships` array, and `_current_dock_edges()` already persisted one edge
per parented ship. So the data model and persistence were already arbitrary-depth; the genuinely
one-level piece was the *travel reposition*. 5d therefore unifies hangar nesting under the
existing dock graph rather than building a parallel subsystem.

## Decision

Five parts:

### 1. Hangar as an asymmetric port type (`DockPorts.for_hangar` + `ports_compatible`)

A hangar is a richer **port type**, not a new subsystem. `DockPorts.for_hangar(layout, seed)`
derives a bay descriptor `{type:"hangar", slot_count, slot_size_class, slot_anchors}` from the
ship's `hangar` room floor cells (`slot_count = floor(floor_cells / CELLS_PER_SLOT)`, min 1;
`slot_size_class = 2` when the room has `>= HANGAR_BIG_CELL_THRESHOLD` cells, else 1; anchors are
ship-local floor-cell centers). It **falls back to the `cargo` room** when no `hangar` room
exists — this is how the **home ship** gets a bay without re-authoring the curated
`coherent_ship_001` golden fixture (and its 31 validators).

`ports_compatible(a, b)` keeps the existing **symmetric** airlock path (equal type + equal
size_class, missing fields fail closed) and adds an **asymmetric hangar branch**: a hangar bay
accepts a ship iff `ship.size_class <= bay.slot_size_class`; two hangars are incompatible; missing
size fields fail closed. Free-slot availability is gated separately by the `HangarBay` model — a
port descriptor has no occupancy.

### 2. Fixed-slot bay model (`HangarBay`)

`HangarBay extends RefCounted` (pure data, "Resources are data, Nodes are behavior"):
`slot_count`, `slot_size_class`, `slots: Array[String]` (each `""` or a bayed `ship_id`).
`dock(ship_id, size_class) -> int`, `launch(slot_index) -> String`, `free_slot_for(size_class)`,
`slot_of(ship_id)`, `is_full()`, and `get_summary()` / `apply_summary()` round-trip under the
`"hangar"` key of a ship's summary (only when the bay has slots). `ShipInstance` lazily creates it
via `get_hangar()`; `has_hangar()` is true only when `slot_count > 0`.

### 3. Weighted `hangar` derelict role

`hangar` is a **weighted** (not guaranteed) procgen derelict role, mirroring how `bridge` gates
claimability in 5c. A derelict that rolled a hangar can store ships; one that did not is
loot/explore only. Wiring the weight required registering `hangar` in three places (the archetype
`role_weights`, `DERELICT_OPTIONAL_ROLES` in `room_graph_generator`, and `ROOM_FOOTPRINT_OPTIONS`
in `room_assigner` — the latter two are the actual selection pool + footprint map; the weight
alone is inert without them), each mirroring the existing `bay` entry. The footprint matches
`bay`/`cargo` (2×2 / 3×3 / 2×3 ≥ 4 cells), so derelict hangars yield size-class-2 bays.

### 4. Physical dock/launch control (`HangarBayControl`)

A `HangarBayControl extends Area3D` is spawned in each bay-bearing ship — **including the home
ship** (which, unlike the bridge terminal, does get a bay). It mirrors `BridgeTerminal`: a
sensor + signal only, strict in-range gate identical to `DockPortBarrier`, no game logic inside.
`try_dock` / `try_launch(player_body, slot_index)` emit `bay_dock_requested` /
`bay_launch_requested(carrier_id, slot_index)`; `slot_index == -1` means "coordinator chooses".
There is **no HUD/menu** — the screen-space hangar UI stays deferred to Phase 7, consistent with
every docking-era interaction.

The coordinator owns the consequence. `_on_bay_dock_requested` takes a ship currently
airlock-docked to the carrier, `bay.dock`s it, drops its airlock alignment via
`DockingManager.undock`, keeps it a dock child (`parent_ship`/`docked_ships`), and re-pegs it to
the carrier-local slot anchor. `_on_bay_launch_requested` reverses it: `bay.launch`, clear
`parent_ship`, remove from `docked_ships`, park it at a co-present anchor near the carrier. All
failures (no candidate / no free slot / incompatible size / not co-present) are **silent
refusals**, per the 5c convention. The lifeboat has no hangar/cargo room, so it gets no control —
it remains the thing that gets stored.

### 5. Arbitrary-depth (DFS) rigid-pair travel (`_capture_subtree` / `_reposition_subtree`)

The one-level `_capture_docked_children` / `_reposition_docked_children` are **replaced** by a DFS:
`_capture_subtree()` walks the entire `piloted_ship.docked_ships` descendant tree (airlock children
*and* bayed children, any depth; stack + `seen` set, cycle-safe), recording each descendant's
transform relative to the piloted root *before* the dock move; `_reposition_subtree()` re-applies
them after. This is **provably depth-agnostic by construction**: every descendant is an independent
root pegged by absolute `global_transform`, so reposition applies a single flat rigid delta
`P' · P⁻¹` to each — the world-relative pose of a node at any depth is preserved regardless of walk
order. The 5c one-level case is just depth-1 of the same walk. A deterministic synthetic-chain test
(`captured.size() == 2` over an A→B→C chain) guards against a dropped recursion.

### 6. `world-4` hangar-edge persistence

Each dock edge gains `port_type` (`"airlock"`|`"hangar"`) and `slot_index` (`-1` for airlock).
`_current_dock_edges` tags an edge as hangar iff `parent.hangar.slot_of(child) != -1`. On load,
`_apply_docking_snapshot` routes a hangar edge to `_redock_bayed` (configure the bay,
re-peg the slot, set `parent_ship` + `docked_ships`, place at the slot anchor) and an airlock edge
to the existing `_dock_piloted_to` — never cross-routed. `_reset_runtime_for_reload` additionally
clears surviving ships' `hangar.slots` so a stale occupant cannot desync the reload re-peg.
`WORLD_SLICE_VERSION` is bumped `"world-3"` → `"world-4"`; older saves fall back to a fresh run.
A world-3-shaped edge lacking `port_type` defaults to airlock / `-1` (forward-compatible shape).

## Rejected alternatives

- **Separate hangar subsystem** (a `HangarBay` state parallel to the dock graph): duplicates the
  edge/persistence/travel machinery and creates two ways a ship can be "attached" — two invariants
  to keep in sync. Unifying under the existing forest is the smaller, safer delta.
- **Visual-only parking** (reposition bayed ships, no graph change): breaks the parent/child forest
  and the persistence model, and fights the recursive-depth goal. Fragile.
- **Adding a `hangar` room to the golden home layout**: high-risk — 31 fixture validators assert the
  curated `coherent_ship_001` room/link graph and critical path. The `cargo`-room fallback gives the
  home a bay with zero golden-fixture churn.
- **Screen-space hangar panel / fleet UI**: deferred to Phase 7 with the rest of the HUD layer; 5d
  ships the physical control only.
- **Cross-ship inventory transfer between carrier and bayed ships**: belongs to System 6
  (Inventory) — out of scope here.

## Consequences

- A ship with a bay (a hangar-rolled derelict, or the home ship via cargo fallback) can store other
  ships in fixed slots and carry them as a nested fleet; a piloted ship's entire dock subtree
  travels with it at arbitrary depth.
- Hangar occupancy, slot indices, and the full dock forest persist through save / load; the player
  cannot lose a bayed fleet by reloading.
- System 5 (Ship Docking & Ship-in-Ship) is **complete**: 5a foundation + 5b physical docking &
  ports + 5c claim/pilot-switch + 5d hangar nesting.
- The N-player access seam (ADR-0018) is untouched and still a post-Phase-7 concern; 5d adds nothing
  player-specific.
- Deferred beyond 5d: the screen-space hangar UI (Phase 7), cross-ship inventory transfer (System 6),
  launch-in-flight / combat, and a bay stored inside another bay (the forest supports nesting, but a
  hangar port cannot itself be a bayed payload this cycle).
- Validation: 6 new smokes registered in the regression bundle (`commands` 94 → 100); full bundle
  and Gate-1 green.
