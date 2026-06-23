# Phase 5c — Claim & Pilot-Switch (Design)

Date: 2026-06-22
Status: Approved (brainstorm). Supersedes nothing; extends the merged 5a/5b
docking foundation. Sibling cycle to the deferred **5d — full hangar nesting**.

## Goal

Generalize the 5b `piloted_ship` pointer from "the lifeboat is the player's
ride" to "any working vessel the player has access to can be the ride." A player
repairs a derelict's propulsion, logs in at its bridge terminal to take command,
and can switch which ship they pilot by walking to that ship's bridge and logging
in. The lifeboat docked to a claimed ship travels with it as a rigid pair.

## Forward constraints (design seams, not built this cycle)

These mirror the 5b "N-ship" discipline: the *interfaces* generalize; only the
single-player / one-level slice is wired.

1. **N players (multiplayer is out of scope, post-Phase-7).** Ownership is a
   login-based access model — `owner_id` + an `access_ids` set per ship — so that
   "multiple players each flying different ships they have access to" is the
   natural extension. We build it for one local player id (`"player_local"`).
   The grant/revoke-other-players methods exist and persist (the seam) but there
   is **no multiplayer UI and no netcode** this cycle.
2. **N-level nesting (full hangar system is the deferred 5d cycle).** Travel moves
   the piloted ship's **direct** dock children with it (one level). Recursive /
   arbitrary-depth nesting, hangar-port-type gating, and hangar-bay UI are 5d.

## Architecture

### The ownership / access model (conceptual core)

- Every `ShipInstance` owns a `ShipAccessState` (pure `RefCounted`): `owner_id`,
  `access_ids` (set-semantics), and `claim/grant/revoke/has_access`. Persisted as
  an `"access"` sub-dict of the ship summary. This follows the project's strict
  "Resources are data, Nodes are behavior" rule (cf. `oxygen_state`,
  `inventory_state`) and keeps the access rules independently unit-testable.
- A **working vessel** is a ship whose own
  `systems_manager.is_operational("propulsion")` is true. The lifeboat is working
  from the start; a derelict becomes working once the player repairs its
  propulsion through the existing `RepairPoint` loop.
- A **bridge terminal** (`BridgeTerminal extends Area3D`, mirroring
  `DockPortBarrier`/`RepairPoint`) is spawned in each pilotable ship's `bridge`
  room. Interacting = **log in**. The terminal is a sensor + signal only; the
  coordinator owns the consequence.
- **Pilot-switching** is physical and uniform across N ships: walk into the ship
  you want to fly and log in at its bridge terminal. No menu/HUD picker. The
  lifeboat's terminal is always working + owned, so the player can always switch
  back.
- The **home ship is never pilotable** (web-trapped — the game's premise): no
  bridge terminal is spawned for it; it remains the base.

### Components

**New:**

- `scripts/systems/ship_access_state.gd` — `ShipAccessState extends RefCounted`.
  - Fields: `owner_id: String = ""`, `access_ids: Array[String] = []` (set).
  - `claim(player_id)`: if `owner_id == ""`, set `owner_id = player_id` and add to
    `access_ids`; if already owned by someone else, no-op returns false; if already
    owner, idempotent true. Returns whether the caller now owns it.
  - `grant(player_id)` / `revoke(player_id)`: add/remove from `access_ids`.
    `revoke` refuses to remove `owner_id` (owner always retains access).
  - `has_access(player_id) -> bool`.
  - `get_summary()` / `apply_summary(dict) -> bool` round-trip.
- `scripts/tools/bridge_terminal.gd` — `BridgeTerminal extends Area3D`.
  - `configure(ship_id: String, world_position: Vector3, radius := 1.8)`.
  - `try_login(player_body) -> bool` — strict in-range gate (identical pattern to
    `DockPortBarrier._is_player_in_direct_range`); emits `login_requested(ship_id)`
    when consumed.
  - signal `login_requested(ship_id: String)`. No game logic inside.

**Modified:**

- `scripts/systems/ship_instance.gd` — lazily-created `access` (`ShipAccessState`);
  `get_summary`/`apply_summary` round-trip it under `"access"`; add
  `is_working_vessel() -> bool` (`systems_manager != null and
  systems_manager.is_operational("propulsion")`).
- `scripts/procgen/playable_generated_ship.gd` (coordinator):
  - `const PLAYER_LOCAL_ID := "player_local"`.
  - Spawn a `BridgeTerminal` in each pilotable ship's `bridge` room
    (`_spawn_bridge_terminal(inst)` / `_clear_bridge_terminals()`), wired to
    `_on_login_requested(ship_id)`.
  - `_on_login_requested(ship_id)`: resolve ship; if `is_working_vessel()`,
    `inst.access.claim(PLAYER_LOCAL_ID)` + `set_piloted_ship(inst)`; else refuse
    (`vessel_not_operational`).
  - `set_piloted_ship(inst) -> Dictionary`: gate on `has_access`; reassign
    `piloted_ship`; recompute occupancy.
  - Generalize travel: after `DockingManager.dock(target, piloted, …)` repositions
    the piloted ship, re-place every ship in `piloted.docked_ships` flush against
    the moved piloted ship using `DockingManager` port-alignment math
    (`_reposition_docked_children(piloted)`), one level deep.
  - Persist owner/access (via ship summaries) and `piloted_ship` (already 5b).
- `scripts/systems/world_snapshot.gd` — ship summaries now include `"access"`;
  bump `WORLD_SLICE_VERSION` `"world-2"` → `"world-3"`.

## Data flow

1. **Repair → working:** existing `RepairPoint` loop repairs the derelict's
   propulsion → `derelict.is_working_vessel()` flips true.
2. **Login / take command:** at the bridge, `BridgeTerminal` fires
   `login_requested(ship_id)`. Coordinator gates on `is_working_vessel()`; on pass,
   `access.claim("player_local")` + `set_piloted_ship(inst)`. On fail, refused
   (`vessel_not_operational`); `piloted_ship` unchanged.
3. **Pilot-switch:** logging in at a different ship the player is aboard calls
   `set_piloted_ship` to that ship. The previously-piloted ship keeps its dock
   relationship (e.g. the lifeboat stays docked to the derelict just claimed).
4. **Rigid-pair travel:** travel runs as in 5b (piloted ship undocks from its host,
   target generated, `DockingManager.dock` repositions the piloted ship flush),
   then `_reposition_docked_children(piloted)` re-places each direct dock child
   flush against the moved piloted ship. The lifeboat docked to the claimed ship
   moves with it. One level deep.
5. **Occupancy** recomputes after a switch and after travel; the player stays
   bodily aboard whichever ship they are standing in.

## Error handling & edge cases

| Case | Behavior |
|---|---|
| Login on non-working vessel (propulsion offline) | Refused, reason `vessel_not_operational`; `piloted_ship` unchanged. |
| Login when not in range of the terminal | No-op (strict in-range gate, like `DockPortBarrier`). |
| Travel while piloting a ship whose propulsion broke after login | Blocked by the existing travel propulsion gate; no change needed. |
| Travel while not aboard the piloted ship | Existing `not_aboard_ship` block still applies. |
| `dock()` of a docked child fails during rigid-pair reposition | Child keeps its prior transform and stays a logical dock child; never freed — no stranding (mirrors the 5b half-dock guard). Logged, non-fatal. |
| Home ship | No bridge terminal spawned; never pilotable. |
| Re-login to a ship already owned by the player | Idempotent — just re-takes command (sets piloted). |
| `set_piloted_ship` to a ship the player lacks access to | Refused, reason `no_access`; `piloted_ship` unchanged. |

## Testing (validation smokes)

Five new smokes, registered in `06_validation_plan.md` (commands 88 → 93):

- `ship_access_smoke` — pure model: claim/grant/revoke/has_access, owner cannot be
  revoked, summary round-trip.
- `bridge_terminal_login_smoke` — login gated on working vessel; sets owner +
  piloted; refused (`vessel_not_operational`) when propulsion offline.
- `pilot_switch_smoke` — two ships aboard/owned; logging in at each flips
  `piloted_ship`; switching to a no-access ship refused.
- `rigid_pair_travel_smoke` — piloted ship travels; a ship docked to it ends flush
  against it (port positions track within tolerance).
- `claim_persistence_smoke` — owner/access/piloted/dock-edge round-trip through
  save → load.

Plus a full regression bundle + Gate-1 run with the `project.godot` drift stashed.

## Scope boundaries (what this cycle is deliberately NOT)

- **Deferred to 5d (full hangar nesting):** recursive / arbitrary-depth nesting,
  hangar-port-type gating, hangar-bay UI, and ships docked to a ship that is itself
  docked (multi-level travel groups). This cycle does exactly one level.
- **Deferred to post-Phase-7 (multiplayer):** netcode, a second live player, and
  grant/revoke-to-other-players UI. The access model is built and persisted as the
  seam; only single-`player_local` behavior is wired.

## ADR

Record the ownership/access model + rigid-pair (one-level) composite travel as
**ADR-0018** during implementation, cross-referencing ADR-0016 (docking
foundation) and ADR-0017 (physical docking + ports).
