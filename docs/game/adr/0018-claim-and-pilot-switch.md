# ADR-0018: Login-based ownership, BridgeTerminal, pilot-switch & rigid-pair travel (Phase 5c)

Date: 2026-06-22
Status: Accepted
Related: ADR-0016 (ship docking foundation), ADR-0017 (physical docking & ports),
ADR-0011 (ShipInstance & travel), ADR-0012 (world persistence),
docs/game/09_system_roadmap.md (System 5),
docs/superpowers/specs/2026-06-22-phase5c-claim-and-pilot-switch-design.md

## Context

Phase 5b delivered a physically real docking loop — the lifeboat is the player's guaranteed ride
and travel is an undock → generate → dock cycle. However, `piloted_ship` was hard-fixed to the
lifeboat: there was no way for the player to claim a derelict they had repaired and fly it back to
a new location. Every derelict was loot-and-leave. The vision calls for the player to be able to
repair a wreck, take the helm, and pilot it as their new vessel while the lifeboat stays docked
as a tender.

This cycle generalizes `piloted_ship` from "always the lifeboat" to "any working vessel the
player has logged in to" while preserving all N-ship forward constraints established in 5b (the
dock-edge set, the `piloted_ship` pointer, occupancy) and adding three new things:
ownership/access model, pilot-switch, and one-level rigid-pair travel.

## Decision

Six parts:

### 1. Login-based ownership model (`ShipAccessState`)

Every `ShipInstance` owns a lazily-created `ShipAccessState extends RefCounted`: `owner_id`,
`access_ids` (set-semantics), and `claim / grant / revoke / has_access`. This follows the
project's strict "Resources are data, Nodes are behavior" rule (mirrors `oxygen_state`,
`inventory_state`, etc.) and keeps the access rules independently unit-testable.

- `claim(player_id)` — if unclaimed, sets `owner_id` and adds to `access_ids`; if already
  owned by the same player, idempotent; if owned by another player, no-op false.
- `grant(player_id)` / `revoke(player_id)` — add/remove from `access_ids`; `revoke` refuses
  to remove the current `owner_id` (owner always keeps access).
- `has_access(player_id) -> bool` — checks `access_ids`.
- `get_summary()` / `apply_summary(dict) -> bool` — round-trip under the `"access"` key of
  each ship's summary dict.

For the single-player slice, the only player id used is `PLAYER_LOCAL_ID = "player_local"`.
The grant/revoke-other-players path exists and persists as the **multiplayer seam** (post-Phase-7).

### 2. Working-vessel gate & BridgeTerminal

A **working vessel** is a ship whose `systems_manager.is_operational("propulsion")` is true.
The lifeboat is working from boot; a derelict becomes working once the player repairs its
propulsion through the existing `RepairPoint` loop.

A `BridgeTerminal extends Area3D` is spawned in each pilotable ship's `bridge` room by the
coordinator (`_spawn_bridge_terminal(inst)`). It mirrors `DockPortBarrier` / `RepairPoint`:
it is a sensor + signal only, no game logic inside. The coordinator owns the consequence.

- `configure(ship_id, world_position, radius)` — positions and names the sensor.
- `try_login(player_body) -> bool` — strict in-range gate identical to
  `DockPortBarrier._is_player_in_direct_range`; emits `login_requested(ship_id)` when consumed.
- signal `login_requested(ship_id: String)`.

`_on_login_requested(ship_id)` in the coordinator: resolve ship; if `is_working_vessel()`,
`inst.access.claim(PLAYER_LOCAL_ID)` + `set_piloted_ship(inst)`; else refuse with reason
`vessel_not_operational`.

### 3. Claimability rule and the bridge-room gate

`bridge` is a **weighted** (not guaranteed) role in the procgen derelict generator — a derelict
that rolled a bridge room is claimable at that helm; a derelict without one gets no terminal and
is a loot/explore space only. There is deliberately **no fallback** (no "use the entry room
instead"). This was a design decision: a derelict with a missing or inaccessible bridge is not a
fly-by-wire ship, it is a wreck.

The lifeboat (`cockpit_01`, role `bridge`) and the golden ships always have a bridge. No change
was needed there.

This rule required an authorized change to `derelict_generator_smoke`'s deny-list to permit the
`bridge` role on derelicts (previously considered a system role and forbidden). The other system
roles (`reactor`, `life_support`, `oxygen`, etc.) remain forbidden for derelicts. That smoke's
pre-existing check-5 (`no_system_roles`) was corrected in this same cycle.

### 4. Pilot-switch via physical login

Pilot-switching is physical and uniform: walk into the ship you want to fly and interact with its
bridge terminal. No menu / HUD picker. `set_piloted_ship(inst) -> Dictionary`:

- Gates on `has_access(PLAYER_LOCAL_ID)` — refused with reason `no_access` if not met.
- Reassigns `_piloted_ship_local` to `inst`.
- Recomputes occupancy (the new piloted ship wins the dock-seam tiebreak, as in 5b).
- Returns a result dict (`ok`, `reason`, `ship_id`).

The lifeboat's terminal is always working and owned by `player_local`, so the player can always
switch back by walking to the lifeboat's cockpit. The **home ship is never pilotable** — no
terminal is spawned for it (`_spawn_bridge_terminal` early-returns on `home_ship`).

### 5. One-level rigid-pair travel (`_capture_docked_children` / `_reposition_docked_children`)

When the player travels while piloting a claimed derelict (or any ship with dock children), the
coordinator moves the piloted ship's **direct** dock children with it — one level deep. The
lifeboat docked to the claimed derelict travels with it as a rigid pair.

Mechanics:
- `_capture_docked_children(piloted)` — before undock, records each direct child's port names
  and transform relative to the piloted ship.
- After `DockingManager.dock(target, piloted, …)` repositions the piloted ship,
  `_reposition_docked_children(piloted)` re-places each captured child flush against the now-
  moved piloted ship using `DockingManager.host_port_to_world` port-alignment math (the same
  utility `_build_lifeboat_at_home` uses).
- The **never-free-piloted-ship** rule (5b): if a dock child is the current `piloted_ship` the
  repositioning loop must not `queue_free` it. A guard skips `queue_free` for that node.
- If `DockingManager.dock()` fails for a child, the child keeps its prior transform and its
  logical dock relationship; it is never stranded. Logged, non-fatal (mirrors 5b's half-dock
  guard).

Recursive / arbitrary-depth nesting, hangar-port-type gating, and hangar-bay UI are **deferred
to 5d**.

### 6. General dock-edge persistence (`world-3`)

Ship summaries now include an `"access"` sub-dict. `WORLD_SLICE_VERSION` is bumped from
`"world-2"` → `"world-3"`. Saves from `world-2` and earlier fall back to a fresh run
(consistent with every prior version bump). The dock-edge set, piloted pointer, access state,
and occupancy all round-trip through save → load — verified by `claim_persistence_smoke`.

## Rejected alternatives

- **Menu-based ownership** (select which ship to pilot from a HUD list): deferred to post-Phase-7
  multiplayer UI; the physical login model is simpler to implement and more immersive.
- **Guaranteed bridge on every derelict**: guaranteed roles bloat procgen and give every wreck the
  same strategic value; weighted keeps scarcity and makes bridge derelicts meaningful finds.
- **Entry-room fallback terminal**: creates a loophole where non-bridge ships become claimable;
  the bridge-room gate is the design's strategic layer.
- **Recursive nesting this cycle**: deferred to 5d — one-level covers the lifeboat-aboard-
  claimed-derelict use case; recursive nesting needs its own spec (hangar ports, N-level AABB
  composition, multi-generation travel groups).

## Consequences

- Any working derelict with a bridge room can be claimed and piloted; derelicts without one are
  loot/explore spaces. Scarcity is a gameplay lever.
- Travel with a dock child (lifeboat aboard a claimed derelict) is physically correct: the child
  moves flush against the moved piloted ship.
- Ownership and access persist through save / load; the player cannot lose command of a ship by
  saving and reloading.
- The multiplayer seam exists: `owner_id` / `access_ids` / `grant` / `revoke` generalize to N
  players; only `player_local` is wired. **Multiplayer netcode and UI remain post-Phase-7.**
- Full hangar nesting (ships docked to ships that are themselves docked, multi-generation travel
  groups) remains **deferred to 5d**.
- Validation: 5 new smokes registered in the regression bundle (`commands` 89 → 94); full
  bundle and Gate-1 green.
