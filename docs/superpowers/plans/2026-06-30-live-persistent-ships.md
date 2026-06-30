# Live Persistent Ships — unified per-ship simulation tick + catch-up on revisit

> **Controlling spec for this effort.** Approved via plan mode 2026-06-30 (supersedes the remainder of Domain 4 and the deferred web-spread follow-on). Execute phase-by-phase via subagent-driven-development; each phase ends with a fully green regression bundle.

## Context

The project's core fiction is that **a derelict is a live, persistent environment from the moment procgen generates it on dock — time does not stand still inside it when the player leaves** (Barotrauma station / Project Zomboid house model). The current build only half-honors this:

- Domain 4 made the **hub** live on both `_process` branches — its systems advance and the web infestation devours its hull whether the player is home or away (a correct application of the principle *to the hub*).
- But **derelicts are not live**: the boarded derelict (`current_ship`) only gets its *fire* ticked — its own `systems_manager` is never time-advanced and it has no web/hull of its own. And **derelicts the player has left are frozen in time** — their state is retained in `visited_ships` but no time passes for them.
- The roadmap's "wire both `_process` branches" constraint is itself a *workaround* for the absence of a real multi-ship sim. The home/away split is the root cause of the PR #42–44 + recharge-port regression class.

**Decision (owner):** re-architect to a **unified "tick every live ship" model**, with **catch-up on revisit** for ships the player is not currently aboard.

**Outcome:** every generated ship (hub + each derelict) owns its full sim state and advances through one code path; present ships tick continuously, absent ships fast-forward by elapsed game-time when re-entered; the `ship_systems` loop closes on this foundation.

## What already exists (reuse, do not rebuild)

- `visited_ships: Dictionary` (marker_id → `ShipInstance`), persisted in the world snapshot (`_build_world_snapshot` ~6534, restored ~6730) — left derelicts already retain state. `_all_known_ships()` (~6583) iterates hub + lifeboat + visited.
- `ShipInstance` (`scripts/systems/ship_instance.gd`) already carries a per-ship `systems_manager` and a lazily-created per-ship `fire` (FireSuppressionState), each with `get_summary`/`apply_summary`. `web_attached: bool` was added in Domain 4.
- The **active-ship model accessor pattern**: `_active_systems_manager()` (~3135) and `_active_fire_state()` (~3122) return the boarded ship's model. Extend this pattern to hull/web.
- `WebInfestationState` (`scripts/systems/web_infestation_state.gd`) + `data/ship_systems/web_infestation.json` + `web_infestation_state_smoke.gd` (Domain 4) — reuse as the per-ship web model.
- Revisit transition: `travel_to` → `_attach_derelict_active(inst, root)` (~1835), where `inst = visited_ships[mid]` on revisit vs. a freshly created instance on first visit (~3623–3634).
- **Missing primitive:** there is no game-time clock anywhere in the coordinator. One must be added.

## Architecture

Introduce a single **`_advance_ship(ship, delta)`** (the unified tick) plus a **game-time clock** so absent ships can catch up:

- **Core per-ship sim (all ships):** `ship.systems_manager.advance(delta)` → ship fire tick + fire→system damage → `ship.web.tick(...) → ship.hull` damage. (Exactly the per-ship work currently scattered across the two `_process` branches.)
- **Present ships tick continuously:** each `_process` frame, `_advance_ship(home_ship, delta)` (hub always co-present) and, while `away_from_start`, `_advance_ship(current_ship, delta)`.
- **Absent ships catch up on revisit:** on re-entering a retained `visited_ships[mid]`, advance by `world_time − inst.last_sim_time` in capped sub-steps, then stamp `last_sim_time = world_time`.
- **Hub-specific layer stays separate:** `_recompute_expanded_ship_systems` (power_grid / propulsion / life_support / crafting station power / sustenance) + player-centric ticks (vitals, sanity, threat, oxygen, food, audio, consumables) remain in `_process`, reading the active ship via `_active_*()` accessors. NOT part of `_advance_ship`.

## Phases

### Phase 0 — Branch disposition (DONE)
Branch `feat/live-persistent-ships` off Domain 4 HEAD (`1f9b2cf`). Domain 4 inventory cross-entry contradictions (hull `content_note`, `ship_systems_manager`/`power_grid`/`sustenance`/`water_recycler`/`life_support`/`crafting_state` "home-only/away-returns-at-4808" claims, food/crafting loop break_points) are **deferred to Phase 5's single inventory pass**.

### Phase 1 — Game-time clock + per-ship sim timestamp
- `var world_time: float = 0.0` on the coordinator; `world_time += delta` once per `_process` frame (before branching). Persist in the world snapshot + `RunSnapshot` if run-scoped — **additive, no `CURRENT_SLICE_VERSION` bump** (read via `.get(..., 0.0)`).
- `var last_sim_time: float = 0.0` on `ShipInstance`, persisted additively.
- No behavior change. New smoke: `world_time` advances across `_process` frames and round-trips through save/load.

### Phase 2 — Per-ship hull + web on `ShipInstance` (highest-churn)
- Lazily-created `hull` (HullIntegrityState) + `web` (WebInfestationState) on `ShipInstance` (mirror `fire` field + `get_fire()`/`has_fire()` + summary gating). Persist additively.
- Move the hub's coordinator singletons onto `home_ship.hull` / `home_ship.web`. Add `_active_hull()` / `_active_web()` accessors.
- Route every hull reference through `_active_hull()`: BreachSealPoint configure (~2580), life_support `breach_count` (~1366), propulsion `hull_penalty` (~1358), `force_hull_breach_for_validation`/`seal_hull_breach_for_validation`, expanded-systems save/load (~1433/~6353). ~15 sites — grep `hull_integrity_state` / `hull_web_state`.
- Derelict hull seeded on generation (config or layout-derived); derelict web seeded attached.
- Verify: existing hull/ship-systems/breach smokes byte-identical; new per-ship hull/web persistence smoke.

### Phase 3 — Unified `_advance_ship(ship, delta)`
- Implement: `ship.systems_manager.advance` + fire tick (`ship.get_fire()`) + fire→system damage + `ship.web.tick(delta, contact) → ship.hull.damage_compartment(...)`.
- Route the active context: home → `_advance_ship(home_ship, delta)`; away → `_advance_ship(home_ship, delta)` + `_advance_ship(current_ship, delta)`. Remove Domain 4's bespoke hub `advance`/`_apply_web_hull_damage` + the away inline fire block (subsumed). Keep `_recompute_expanded_ship_systems` + player-centric ticks.
- Preserve the Domain 4 recharge-port fix + the no-double-fire-tick invariant.
- Verify: `ship_systems_closure_smoke` + full bundle green; fire/field-crafting tick exactly once per branch.

### Phase 4 — Catch-up on revisit
- `_catch_up_ship(inst)`: `dt = world_time - inst.last_sim_time`; advance via `_advance_ship` in capped sub-steps (≤5s/step loop) for stability; then `inst.last_sim_time = world_time`. Call in `_attach_derelict_active` on activating a retained instance; stamp `last_sim_time = world_time` on first generation. Hub never catches up.
- Verify: new smoke — generate/visit a derelict, advance `world_time`, revisit, assert web grew / hull degraded / systems advanced by the gap; sub-step stability (large dt no NaN/over-damage).

### Phase 5 — Close `ship_systems` loop + holistic inventory + docs
- `ship_systems.closes → "closed"`; `hull_integrity_state.input.live → true` (per-ship web source).
- **Fix ALL cross-entry contradictions in one sweep** (the 9 from the Domain 4 Task 4 review + any new ones): every "home-only / away returns at 4808 / no live damage source / powered crafts pause away" claim now false. Distinguish *model tick* (both branches) from *player-facing output* (active-ship only).
- Inventory entries for new tracked models; `tools/build_system_inventory.py` → `--check` + `--coverage` clean.
- Update stale comments (`:4948`, `:4999`) + ADR-0038 supersession; carry the recharge-port fix under `fix:`.
- Full bundle green (`SYNAPTIC_SEA REGRESSION PASS`).

## Critical files
- `scripts/procgen/playable_generated_ship.gd` — `world_time`, `_advance_ship`, `_active_hull()`/`_active_web()`, `_catch_up_ship`, `_process` rewrite, hull-ref routing, save/load.
- `scripts/systems/ship_instance.gd` — `last_sim_time`, `hull`, `web` (lazily-created + persisted, mirroring `fire`).
- `scripts/systems/web_infestation_state.gd`, `scripts/systems/hull_integrity_state.gd` — reused per-ship (likely unchanged).
- `data/ship_systems/web_infestation.json` (+ derelict-hull seed config if not layout-derived).
- New smokes (world_time, per-ship hull/web persistence, catch-up); reuse `ship_systems_closure_smoke.gd`, `web_infestation_state_smoke.gd`.
- `docs/game/inventory/system_inventory.json` (+ regenerated MD/HTML), `docs/game/06_validation_plan.md`, `docs/game/adr/0038-crafting-materials-stations-architecture.md`.

## Verification
- Per phase: targeted smokes RED→GREEN, then the **full regression bundle** from `06_validation_plan.md` (Windows `GODOT`/`ROOT`) — gate on `EXIT=0` + zero unexpected `ERROR:`/`WARNING:` + all PASS markers + `SYNAPTIC_SEA REGRESSION PASS`.
- `--check` + `--coverage` clean.
- Phase 4 catch-up smoke is the load-bearing proof of the principle.

## Risks
- **Phase 2 churn:** ~15 hull reference sites + save/load route through `_active_hull()`/`_active_web()`. Mitigate via the proven `_active_fire_state()` pattern + existing hull smokes as regression fences.
- **Catch-up large-`dt` stability:** sub-step the catch-up; assert bounded results.
- **Scope:** multi-phase; SDD one phase at a time, each gated on its own green bundle.
- **Catch-up semantics:** pure lazy catch-up means absent ships don't interact in real time; cross-ship web spread computed at catch-up from neighbor state — flagged for the follow-on.
