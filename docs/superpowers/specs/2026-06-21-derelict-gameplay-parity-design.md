# Derelict Gameplay Parity — Design

Date: 2026-06-21
Status: Approved (pre-implementation)
Phase: Sub-project #2 of the "target session loop" decomposition (follows #1 world persistence; precedes #3 inventory/loot)
Related: ADR-0011 (ShipInstance & travel integration), ADR-0012 (world persistence model), `docs/superpowers/specs/2026-06-20-synaptic-sea-core-systems-design.md` (System 4/8), `docs/game/02_core_loop.md`

## Why this sub-project exists

Sub-project #1 made every visited ship persist, but a boarded derelict is still a bare
hull: `_process` early-returns when `away_from_start`, so no gameplay runs aboard it. The
rich loop (objectives, route gates, extraction) lives only on the home ship. This
sub-project gives a boarded derelict its own generated objective loop — explore, complete
salvage objectives, reach extraction — running on the **active** ship and persisting
per-derelict via the slice the foundation established. It is the second half of "make
boarding meaningful": #1 made derelicts *remembered*, #2 makes them *playable*.

Hazards on derelicts are split to a fast-follow (#2b); the tangible reward (loot/parts) is
sub-project #3 (player inventory). #2 delivers a playable, persistent objective + extraction
loop and nothing more.

## Starting point (current code)

- `scripts/procgen/playable_generated_ship.gd` — the coordinator. `_process` (line ~1586)
  early-returns when `away_from_start`. `_on_ship_loaded` → `_build_interactables` (~1230)
  builds the HOME ship's objective loop from `loader.get_objective_specs_copy()` into
  coordinator singleton state (`objective_progress_state`, `current_objective_sequence`,
  `interactables`, the gameplay roots). `_on_player_interact_requested` early-returns when
  `away_from_start` (~1295, the Phase 4.5 interaction gate). Home extraction is tied to
  `OBJECTIVE_REPAIR_MAP` + `ship_systems_manager` (reactor stabilization).
- `scripts/systems/objective_progress_state.gd` — `ObjectiveProgressState` (pure model):
  `register_objective`, step/sequence completion, `is_sequence_complete`, `get_summary` /
  `apply_summary`. Currently one instance, on the coordinator, for the home ship.
- `scripts/procgen/gameplay_slice_builder.gd` — `GameplaySliceBuilder.build(layout)`
  generates derelict objectives: one `salvage` per non-connective room + a final
  `reach_goal` (`type: "interact"`). Hazard zones are stubbed empty (out of scope here).
- `scripts/procgen/ship_generator.gd` — the travel path materializes a derelict through the
  same `GeneratedShipLoader`, so a boarded derelict's loader already carries an `ObjectiveRoot`
  and its objective specs.
- `scripts/systems/ship_instance.gd` — `ShipInstance` per-ship handle. `get_summary` /
  `apply_summary` currently serialize `blueprint` + `systems_manager`. The slice is an
  extensible summary-bag (ADR-0012); #2 extends it.
- `scripts/interaction/interactable.gd` (the objective interactable node) configures from an
  objective spec (`configure_from_objective` / `configure_from_step`);
  `scripts/ui/objective_tracker.gd` `set_objectives(specs)` renders an objective list. Both
  are already parameterized by specs, so they serve any ship's loader.

## Requirements

- Boarding a derelict spawns its generated objective loop (salvage per-room + `reach_goal`)
  and its objectives are interactable on the boarded ship. Because #2 is objectives-only and
  the loop is purely input-driven, only the Phase 4.5 interaction-gate is lifted for the
  active derelict; the `_process` per-frame freeze stays (there is no derelict per-frame sim
  until hazards land in #2b).
- Completing a `salvage` objective marks it done; reaching `reach_goal` marks the derelict
  `cleared`. Both persist per-derelict.
- Progress (objective state + `cleared`) survives leave/return and save/load via the
  `ShipInstance` slice; completed salvage does not respawn on revisit; a cleared derelict
  reads as cleared.
- The home ship's loop is unchanged — its objectives, route gates, and reactor extraction
  behave exactly as before, including after travelling out and back.
- No softlock: travel-away keeps full capability, so an unfinished derelict is never a trap.

## Architecture: parallel derelict objective loop (Approach B, maximal reuse)

The home loop stays singleton-driven and untouched. Derelicts get a **parallel** objective
loop that reuses existing units rather than swapping the home singletons (swapping risks
destabilizing the reactor/extraction-entangled home loop; derelict objective semantics
genuinely differ).

### Reused as-is
- `ObjectiveProgressState` — a **fresh instance per derelict**, owned by its `ShipInstance`
  (mirroring how each `ShipInstance` already owns its `systems_manager`).
- The objective interactable node (`scripts/interaction/interactable.gd`) — spawned from the
  derelict loader's objective specs (`configure_from_objective`), under a dedicated derelict
  objective root.
- `ObjectiveTracker` — shows the **active** ship's objectives: the derelict's while aboard,
  the home ship's at home.

### New, small and focused
- A derelict objective controller (pure logic): given the derelict's objective specs and its
  `ObjectiveProgressState`, it registers objectives, records completion, exposes
  `is_cleared()` (true once `reach_goal` is complete), and round-trips through
  `get_summary` / `apply_summary`. One responsibility, no scene-tree access — unit-testable
  in isolation. (Exact file boundary decided in the plan; it may be a thin RefCounted
  alongside `ObjectiveProgressState`, not a duplicate of it.)
- Coordinator wiring: build/free the derelict's interactables on board/leave; lift the
  `_on_player_interact_requested` gate for the active derelict (the `_process` freeze stays —
  no per-frame derelict sim in #2); route the derelict's interactable-completion to the
  controller; capture/restore the controller summary into the `ShipInstance` slice.

### Lifecycle
- **Board a derelict** (travel/world-load activation): build the derelict's objective loop
  from its loader specs into the derelict objective root; restore any persisted
  `ObjectiveProgressState` + `cleared` from the `ShipInstance` slice (so completed objectives
  read as done and spent salvage is not respawned); the objectives are immediately
  interactable (interaction gate lifted).
- **Interact** on a derelict objective: the controller records completion; `reach_goal`
  completion sets `cleared`.
- **Leave** (travel away / travel home / world-load to another ship): the derelict's
  objective state already lives in its `ShipInstance` (the controller mutated it in place),
  so nothing is lost; free the derelict's interactable nodes with the scene.
- **Revisit / quit→resume**: geometry regenerates from seed (foundation); the slice restores
  objective progress + `cleared`; the loop rebuilds reflecting completed/cleared state.

## Per-ship persistence (slice extension)

`ShipInstance.get_summary` / `apply_summary` gain `objective_progress` (the derelict's
`ObjectiveProgressState` summary) and `cleared: bool`. The foundation already serializes each
`ShipInstance` into the `WorldSnapshot` and restores it, so derelict objective progress
persists across leave/return and save/load with no new save-layer work. The home ship's
gameplay state continues to ride the `RunSnapshot` (unchanged); only derelicts use the slice
for objective state.

## Completion / extraction

- `salvage` objective complete → marked done (persisted); its interactable is consumed and
  not respawned on revisit.
- `reach_goal` complete → derelict `cleared = true` (persisted). `reach_goal` *is* the
  extraction; there is no reactor/`stabilize_reactor` path on a derelict (home-only).
- Reward is deferred to #3: clearing yields the persisted `cleared` state now; loot/parts
  arrive with player inventory.

## HUD & interaction

- `ObjectiveTracker` renders the active ship's objective list. Boarding points it at the
  derelict's specs; returning home restores the home list.
- The Phase 4.5 interaction gate (`_on_player_interact_requested` early-return when
  `away_from_start`) is lifted for the active derelict so its objectives are interactable.
  The home ship's interactables remain detached while away, so there is no cross-ship
  interaction.

## Validation

Per project convention each new system gets a pure-model smoke and a main-scene smoke,
registered in `docs/game/06_validation_plan.md` (commands 65 → ~67; regression bundle and
Gate-1 must stay clean):

- **Pure-model smoke**: the derelict objective controller — register the generated objective
  set, complete salvage objectives (marked done), complete `reach_goal` (`is_cleared()`
  true), and assert `get_summary` / `apply_summary` round-trips progress + `cleared`.
- **Main-scene smoke**: board a generated derelict → its objectives are present and
  interactable while aboard (the interaction gate is lifted) → complete a salvage objective →
  reach goal → `cleared` set →
  leave → revisit → completed/cleared state restored and spent salvage not respawned →
  return home and assert the home objective loop is intact.

## Explicitly out of scope (later sub-projects)

- Hazards on derelicts — fire/breach generation + hazard-sim-on-derelict (**#2b**).
- Player inventory + lootable items / tangible clear reward (**#3**).
- Parts-gated, multi-visit derelict repair loop (**#4**).
- Phase 5 docking / ship-in-ship.

The `ShipInstance` slice remains an extensible summary-bag so these add fields without
reshaping the model.
