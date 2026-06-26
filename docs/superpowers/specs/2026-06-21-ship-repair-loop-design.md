# Ship Repair Loop (sub-project #4) — design

Date: 2026-06-21
Status: Accepted
Related: ADR-0011 (ShipInstance & travel — the "derelicts always travel-capable" placeholder
this retires), ADR-0012 (world persistence), ADR-0013 (derelict gameplay parity),
ADR-0014 (loot & player inventory), docs/game/00_vision.md (open-world survival North Star)

## Purpose

Make the looted parts from #3 *mean something*: spend them to **repair ship systems**, and make
repair restore **travel capability**. This is the spine of the North Star loop
(loot → repair → fly) and the first real consumer of the inventory's `part` category.

The travel model the player actually has (clarified during brainstorming):

- The player never "becomes" the derelict they loot. They travel in a **functional ship they
  own** — at game start, a **damaged lifeboat**. That ship docks to the target derelict; the
  player boards the derelict to loot/repair; the docked ship is their guaranteed ride, so
  **stranding is impossible**.
- **Opening loop:** the lifeboat boots with **propulsion offline**. The starting area is
  guaranteed to contain the parts/tools to repair it. Repairing the lifeboat's propulsion is
  what unlocks the first jump.
- Thereafter the lifeboat is the travel ship, derelict to derelict, until the player fully
  repairs some *other* derelict (a follow-on; see Non-goals). Travel capability lives in the
  **player's functional ship**, not the derelict under their feet.

Ships are the focus of the game; the long-term target is Barotrauma-style interdependent ship
needs (wiring, coolant, distributed failures) layered with Project-Zomboid looting/crafting.
#4 builds the spatial, parts-gated, **timed** repair mechanic on the existing system/
subcomponent/dependency model that makes that depth reachable.

## Existing foundation (build on)

- **Repair model already exists.** `ShipSubcomponent.repair(available_parts, available_tools,
  skill_level)` (`scripts/systems/ship_subcomponent.gd`) is deterministic: it checks
  `required_parts`/`required_tools`/`min_skill` and sets `health = 1.0` on success, returning
  `{success, reason, seconds}` where `seconds` is `repair_seconds` scaled down by skill over
  `min_skill`. `ShipSystemsManager.repair(system_id, subcomponent_id, ...)` routes to it.
  **Nothing calls this gated path with real inventory yet** — the home loop uses
  `force_repair` (deterministic, no parts) via an objective→`OBJECTIVE_REPAIR_MAP` bridge.
- **`systems.json`** already specifies rich requirements: 6 systems × 3 subcomponents, each with
  `required_parts` / `required_tools` (`welder`, `plasma_cutter`) / `min_skill` / `repair_seconds`
  / `operational_threshold`, and `dependency_ids` (e.g. `propulsion` depends on `power` +
  `navigation`). `ShipSystemsManager.is_operational` resolves the dependency cascade — fixing a
  dependency brings its dependents back online automatically.
- **`InventoryState`** (#3) carries quantitied, weight-capped `part`/`supply`/`tool` items with
  `add_item`/`remove_item`/`get_quantity`/`get_items_by_category` and `has_tool`.
- **`LootContainer`** (#3) is the search-on-interact node; loot tables roll deterministically per
  `marker_id + container_id`. Loot is currently **derelicts-only** (`_build_loot_containers`
  early-returns on the starting ship).
- **Travel gate.** `_current_systems_ops()` (`playable_generated_ship.gd`) reflects the starting
  ship's real systems when home, but **fakes full capability when aboard a derelict** — its own
  comment says condition-gating activates "once the derelict repair loop exists (see ADR-0011)."
  `TravelController.attempt_travel` blocks on `propulsion_offline`.
- **Persistence is free.** Subcomponent `health` rides `ship_systems_summary` (lifeboat) and the
  per-ship `ShipInstance.systems` slice (derelicts) — a repaired ship stays repaired across
  leave/return/save-load with no new persistence code.

## Design

### 1. Travel gate → the lifeboat (retire the placeholder)

Change `_current_systems_ops()` to **always reflect the starting ship's (lifeboat's) real
systems**, home *and* away — the lifeboat is the player's docked ride everywhere. The
`away_from_start` faked-`true` branch is removed; both branches read the coordinator's
`ship_systems_manager` (the lifeboat). Consequences:

- Before the opening repair: lifeboat propulsion offline ⇒ `travel_to` returns
  `propulsion_offline`. This *is* the opening gate.
- After: the lifeboat is detached-not-freed while away, so its propulsion stays operational ⇒
  travel always works and **the looted derelict's broken systems never strand the player**.
- `travel_home()` remains **always available** regardless of systems, as a no-strand guarantee.

This is additive to existing travel smokes, which already `force_repair` / make the home ship
fully operational before travelling (so they keep passing once the away-branch reads the
lifeboat that they already repaired).

### 2. Repair mechanic — distributed, parts-gated, timed repair points

`RepairPoint` (`scripts/tools/repair_point.gd`, new) is an Area3D interactable (same pattern as
`LootContainer`/`Interactable`) bound to one `(system_id, subcomponent_id)` of a specific ship,
placed at a distributed world location (propulsion in the engine room, a coolant line elsewhere,
wiring in another room). It drives a **Project-Zomboid-style timed channel**:

- **Start:** interacting begins the repair only if a dry-run validation passes — the player
  carries the `required_parts` + `required_tools` and meets `min_skill`. A failed precheck
  surfaces the reason (`missing_parts` / `missing_tools` / `insufficient_skill` /
  `already_functional`) and does nothing.
- **Channel:** the node accumulates elapsed time toward the **skill-scaled** duration
  (`repair_seconds / (1 + 0.1·max(0, skill − min_skill))`, mirroring the model) in its **own**
  `_process(delta)`. This ticks independently of the coordinator's per-frame loop — so timed
  repair does **not** require lifting the derelict `_process` freeze (that stays #2b). Progress
  `0.0..1.0` is exposed for the HUD.
- **Cancel:** if the player leaves interaction range during the channel, the repair cancels —
  **no parts consumed, no health change.** Progress is transient (not persisted mid-channel).
- **Complete:** on reaching full progress, call the gated `ShipSystemsManager.repair(...)` with
  the player's part/tool ids and skill; on `success`, **consume each `required_part`** from
  `InventoryState` (`remove_item(id, 1)`), mark the point repaired/inactive, and emit
  `repair_completed`. Dependents re-resolve automatically via `is_operational`. Award repair XP
  via the existing `player_progression` (reuse the path the objective bridge uses).

The coordinator owns a `repair_point_root: Node3D` and a `repair_points: Array`, builds/clears
them by the same pattern as `loot_containers` (built in `_attach_derelict_active` and for the
lifeboat at startup; cleared in `travel_home` and `_reset_runtime_for_reload`). One repair point
per **currently-damaged** subcomponent; a subcomponent already functional spawns none, and a
restored one is marked inactive (no respawn on revisit — the per-ship systems summary persists
the health, so a rebuilt point reads as done).

**Any-ship:** repair points are built for the **lifeboat and derelicts** alike. The existing
home objective→`force_repair` bridge is **untouched** (a separate, deterministic path that keeps
gate-1 and the completion loop green); repair points are an additional, parts-gated way to
restore the same subcomponents.

### 3. Parts/tools vocabulary reconciliation

`systems.json` needs parts (`thruster_nozzle`, `circuit_board`, `oxygen_filter`, `sealant`,
`plating`, `data_core`, `fuel_line`, `sensor_module`, `reactor_core`) and tools (`welder`,
`plasma_cutter`) that #3's loot does not yet produce. #4 reconciles them:

- Expand `data/items/item_definitions.json` with every repair part (category `part`, weights)
  and the two repair tools (`welder`, `plasma_cutter`, category `tool`). Existing generic salvage
  (`scrap_metal`, `wiring_spool`) stays as inert future crafting feedstock.
- Expand `data/items/loot_tables.json` so those parts/tools actually drop from containers.
- **Guaranteed starting loot:** the starting area's loot containers are seeded to *guarantee* the
  exact parts + tools the lifeboat's opening repair needs, at the player's starting skill — the
  opening can never soft-block. (Determinism is per `marker_id + container_id`; the starting ship
  uses a fixed container id so its guaranteed contents are stable.)

### 4. The opening loop (lifeboat boots with propulsion offline)

- The starting ship (lifeboat) is curated so **propulsion is offline at boot** — its blocking
  subcomponent(s) are damaged — using **low `min_skill`** and tools/parts that the starting area
  guarantees. The opening: explore start → loot the guaranteed parts/tools → repair propulsion at
  its repair point → first jump unlocks.
- This requires lifting #3's **loot-derelicts-only** restriction so the starting ship gets loot
  containers (`_build_loot_containers` no longer early-returns on the lifeboat). Loot thus becomes
  a true **any-ship** system (North Star convergence).
- The existing home objective loop (reactor/extraction via `force_repair`) stays alongside — it is
  a *different* objective set and does not touch propulsion-for-travel, so gate-1 and the
  completion smoke are unaffected. Curating which subcomponent boots offline is chosen to avoid
  colliding with the objective bridge's repaired set.

### 5. Persistence (free)

No new persistence code. Repaired subcomponent `health` already rides `ship_systems_summary`
(lifeboat) and the per-ship `ShipInstance.systems` slice (derelicts). A repaired ship stays
repaired across leave/return and save/load. A repair **in progress** is transient and not saved
(saving mid-channel loses the channel, PZ-style).

## Components

| Unit | Type | Responsibility | Depends on |
| --- | --- | --- | --- |
| `RepairPoint` | `Node3D` (Area3D) | timed channel; precheck; on complete call gated repair + consume parts; cancel on out-of-range | `InventoryState`, `ShipSystemsManager`, `player_progression` |
| `ShipSubcomponent.repair` | model (existing) | deterministic gated repair; unchanged | — |
| procgen repair-point specs | builder | emit one repair-point spec per damaged subcomponent with a distributed room/cell + `(system_id, subcomponent_id)` | systems manager state + layout rooms |
| `playable_generated_ship` | `Node3D` | build/clear `repair_point_root`; lifeboat + derelict points; travel-gate change; HUD repair progress; opening curation; lift loot-derelicts-only | all above |
| item/loot data | JSON | repair parts + tools; loot tables; guaranteed starting loot | — |

## HUD

Extend the existing ship-systems HUD/status path to show, while a repair channels, the target
subcomponent and progress (`repairing=<sub> <pct>%`); and to surface a repair point's precheck
reason when a start is rejected (`repair_blocked=<reason>`). Reuse the existing inventory/systems
status-line plumbing — no new menu UI.

## Portability constraints (from prior sub-projects)

- `RepairPoint` is a new `class_name` script not in the committed class cache; construct it via a
  `preload(...)` const + `.new()` in the coordinator — never a bare `RepairPoint.new()` or a
  `: RepairPoint` annotation in another script. (Same rule that governed `LootContainer`.)
- The home objective loop and home `_process` behavior must stay byte-for-byte unchanged where not
  explicitly modified; gate-1 and the main completion smoke must stay green.

## Scope boundary — what #4 does NOT do

- **No multi-ship docking entity** — no visible docked lifeboat object, no cannibalizing, no
  owning-two-ships bookkeeping. That is the Phase-5 docking follow-on. #4 models "the lifeboat is
  your ride" purely as *the travel gate reads the lifeboat's systems*.
- **No crafting** — generic salvage (`scrap_metal`, `wiring_spool`) is inert feedstock for a
  later crafting sub-project.
- **No repair-skill progression curve** — `min_skill` gates against the *existing*
  `player_progression`; #4 does not add a new skill or rebalance progression. Opening repairs use
  low `min_skill` so a fresh player can clear them.
- **No change to the home objective→`force_repair` loop**, the reactor/extraction flow, or the
  derelict `_process` freeze (timed repair is driven by the repair node itself).
- **No survival consumption** of `supply` items (that is #2b).

## Validation (3 new smokes → bundle 70 → 73)

1. **Pure-model** (`repair_consume_smoke.gd`): driving `ShipSystemsManager.repair` with an
   `InventoryState`-backed part/tool set restores the subcomponent and the caller consumes the
   required parts; a **dependency cascade** (repair a dependency → a dependent system becomes
   operational) holds; rejects on missing parts / missing tools / insufficient skill /
   already-functional. Marker:
   `REPAIR CONSUME PASS repaired=true consumed=true cascade=true rejects=true`.
2. **Travel-gate** (`lifeboat_travel_gate_smoke.gd`): with lifeboat propulsion offline,
   `travel_to` a marker returns `propulsion_offline`; after restoring propulsion, the same travel
   succeeds; `travel_home` succeeds in both states. Marker:
   `LIFEBOAT TRAVEL GATE PASS blocked_offline=true travels_after_repair=true home_always=true`.
3. **Main-scene** (`repair_loop_smoke.gd`): the opening — the starting area has the guaranteed
   parts/tools in loot containers; loot them; a `RepairPoint` for the lifeboat's offline
   propulsion subcomponent **channels over time** (advance frames) and on completion consumes the
   parts, the subcomponent is operational, and a previously-blocked `travel_to` now succeeds;
   the repaired state survives a disk save/load; the existing home loop is intact. Marker:
   `REPAIR LOOP PASS opening=true channeled=true persists=true home_intact=true`.

The timed channel is exercised by advancing `process_frame`s (a validation seam may fast-forward
the channel deterministically). All three smokes register in `docs/game/06_validation_plan.md`
and the bundle count goes 70 → 73; gate-1 must stay green.

## ADR

Recorded as **ADR-0015** during implementation: parts-gated timed repair on the existing systems
model; travel capability re-pointed to the lifeboat (retiring the ADR-0011 "derelicts always
travel-capable" placeholder, no stranding); loot lifted to any-ship; multi-ship docking deferred.
