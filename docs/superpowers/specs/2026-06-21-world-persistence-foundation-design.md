# World Persistence Foundation — Design

Date: 2026-06-21
Status: Approved (pre-implementation)
Phase: Sub-project #1 of the "target session loop" decomposition (precedes Phase 5 docking)
Related: ADR-0007 (save/load scope), ADR-0011 (ShipInstance & travel integration), `docs/superpowers/specs/2026-06-20-synaptic-sea-core-systems-design.md` (System 5/8)

## Why this sub-project exists

The intended session loop (`docs/game/02_core_loop.md`, lines 21–28) is multi-ship and
persistent: choose a derelict, explore it, secure gains, return progress, and revisit
later. Fixing any single derelict is a multi-visit effort — the player loots parts from
many ships to repair one. None of that is possible today:

- Traveled derelicts are **stateless**: generated from seed on arrival, freed on leave,
  regenerated fresh on return (ADR-0011). Repairs and loot cannot survive a single leave.
- The save model is a **single-ship slice**: `RunSnapshot` holds exactly one ship's state
  (ADR-0007). There is no world object wrapping it; ADR-0011 names this gap explicitly.
- Saving is **rejected while away** from the home ship (Phase 4.5), so there is no
  save-anywhere.

This sub-project builds the foundation every later sub-project depends on: a persistent,
fully serializable world. It does **not** add derelict objectives/hazards, inventory/loot,
or the repair loop — those are sequenced after this and drop into the per-ship slice
structure defined here.

## Requirements (from the player-facing intent)

- **All ships persist once accessed.** A visited derelict's state (its ship systems, and
  later its objectives/loot/repairs) survives leaving and is restored on return.
- **Save anywhere** (Project-Zomboid style). The entire world serializes at any instant,
  including mid-derelict, and resumes exactly.
- **No stranding.** The home ship is always preserved and always a valid return target;
  the player always arrives at a derelict via their own working ship.
- **Scales to many ships.** Visiting dozens of derelicts must not keep dozens of scene
  trees in memory or serialize raw scenes.

## Starting point (current code)

- `scripts/systems/synaptic_sea_world.gd` — `Synaptic SeaWorld`: `world_seed`, map-space
  `player_position`, `generated_marker_ids` (set of materialized markers), with
  `get_summary()`/`apply_summary()`. Holds no per-ship state. Markers are regenerated
  deterministically from `world_seed`.
- `scripts/systems/run_snapshot.gd` — `RunSnapshot`: a single active-ship slice (layout/kit/
  gameplay paths + 8 model summaries + player position + version markers).
- `scripts/systems/save_load_service.gd` — `SaveLoadService`: single slot
  `user://saves/current_run.json`, serializes one `RunSnapshot`, version-gated
  (`gate2-current-run-1` + Godot version); incompatible saves are rejected → fresh run.
- `scripts/systems/ship_instance.gd` — `ShipInstance` (Phase 4.5): per-ship handle bundling
  `ship_id`, `marker_id`, `blueprint`, `systems_manager`, `scene_root`, with
  `get_summary()`/`apply_summary()`. The home ship is wrapped as `current_ship`.
- `scripts/procgen/ship_generator.gd` — `ShipGenerator.generate_from_seed(seed, size,
  condition)` deterministically builds a derelict scene (geometry + objectives via
  `GameplaySliceBuilder`).
- `scripts/procgen/playable_generated_ship.gd` — the coordinator. Travel currently
  generates a derelict, swaps `current_ship`, sets `away_from_start`, freezes `_process`,
  and frees the derelict on leave; `request_save` returns false while `away_from_start`.

## Keystone principle: regenerate geometry, persist state

Geometry is deterministic from seed and is **never serialized**. Only mutable state is
persisted, as summaries, and re-applied onto freshly rebuilt nodes.

A visited derelict's persistent slice:

```
{
  marker_id, seed, size, condition,   # identity → regenerate the hull deterministically
  systems_summary,                    # ShipInstance.systems_manager state
  # objective_progress_summary, hazard summaries, loot_summary, repair_summary
  # are added by later sub-projects; the slice is a summary-bag and extends without reshape
}
```

On revisit: rebuild the hull from `seed/size/condition`, then re-apply the slice summaries.
State survives; memory does not bloat.

## Architecture

### New top-level save object: `WorldSnapshot`

`scripts/systems/world_snapshot.gd` (`RefCounted`, pure data, `to_dict()`/`from_dict()`):

```
WorldSnapshot
├── world_summary             # Synaptic SeaWorld.get_summary()
├── home_ship                 # a RunSnapshot dict (home-ship slice — RunSnapshot unchanged)
├── visited_ships             # { marker_id -> per-ship slice dict }   (NEW)
├── current_location          # "" = home, else marker_id
├── player_position_in_ship   # scene-space [x,y,z] in the active ship
├── slice_version             # NEW version marker, distinct from RunSnapshot's
├── godot_version
└── saved_at
```

`RunSnapshot` keeps its exact current shape and remains the per-ship slice for the home
ship — no new fields, so ADR-0007's "adding a RunSnapshot field requires an ADR" is not
triggered. `WorldSnapshot` is the wrapping world object ADR-0011 anticipated. Per-derelict
slices use the same extensible summary-bag pattern but are a distinct, lighter structure
keyed by `marker_id` (they regenerate geometry, so they do not carry layout/kit paths).

`from_dict()` rejects version-mismatched data (returns null → fresh run), mirroring
`RunSnapshot`'s contract.

### Visited-ships registry on the coordinator

`visited_ships: Dictionary` mapping `marker_id -> ShipInstance`. Each `ShipInstance` keeps
its pure-data state (`blueprint`, `systems_manager`, summaries) alive across visits; only
the **active** ship holds a live `scene_root` in the tree.

### Travel becomes persist-and-restore

- **First visit to a marker:** generate from seed, build a `ShipInstance`, register it in
  `visited_ships`, make it the active ship. (`Synaptic SeaWorld.mark_generated` still records the
  marker.)
- **Leaving a derelict:** capture any live-node state back into the `ShipInstance` summaries,
  free its `scene_root` (geometry is regenerable), keep the `ShipInstance` (state) in the
  registry. In this sub-project a derelict's persistent state *is* its `ShipInstance`
  data (`systems_manager`), which is mutated in place and needs no capture step; the
  capture hook is structural — it becomes load-bearing when sub-project #2 adds live
  objective/hazard nodes whose runtime state must be summarized before the scene is freed.
- **Revisiting a registered marker:** rebuild the hull from its stored `seed/size/condition`,
  re-apply the `ShipInstance` summaries — not a fresh generate. The result is identical
  geometry with preserved state.
- **Home ship:** keeps today's detach-not-free behavior (lowest risk to its rich live sim);
  it already round-trips through `RunSnapshot`. Only derelicts take the new free-and-rebuild
  path in this sub-project.

### Save anywhere

`request_save` no longer rejects while `away_from_start`. It builds a `WorldSnapshot`
capturing: `world_summary`, the home-ship `RunSnapshot`, every entry in `visited_ships`
(the active ship's live state summarized first — trivial for a derelict in this
sub-project, the full `RunSnapshot` capture for the home ship), `current_location`, and the
player's scene-space position. `SaveLoadService` serializes the `WorldSnapshot` to the
single slot.

Load rebuilds: apply `world_summary` to `Synaptic SeaWorld`, restore the `visited_ships`
registry from the slices, rebuild the home ship from its `RunSnapshot`, then — based on
`current_location` — make the home ship or the named derelict active (rebuilding that
derelict's scene from its slice) and re-home the player at `player_position_in_ship`.

Single continuous slot (overwrite), manual trigger as today. Autosave and multiple/named
slots remain out of scope.

### Coordinate spaces (unchanged separation, both persisted)

Map space (`Synaptic SeaWorld.player_position`, in `world_summary`) and scene space
(`player_position_in_ship`) are separate and both serialized. Each ship is instantiated at
the coordinator's local origin; `player_position_in_ship` is relative to the active ship.

## ADR-0012 (to be written with the implementation)

Records the world-persistence model: `WorldSnapshot` wraps `RunSnapshot`;
regenerate-geometry / persist-state; save-anywhere **supersedes** the Phase 4.5 away-save
rejection and extends ADR-0007's single-ship stance. Old single-ship `current_run.json`
saves become version-incompatible under the new `WorldSnapshot` slice version → rejected →
fresh run (pre-release; no migration).

## Validation

Per project convention each new system gets a pure-model smoke and a main-scene smoke, both
registered in `docs/game/06_validation_plan.md` (commands 61 → ~64; regression bundle and
Gate-1 automated playtest must stay clean):

- **`world_snapshot_smoke.gd`** (pure): round-trips a `WorldSnapshot` with `world_summary`,
  a home `RunSnapshot`, and N visited-ship slices + `current_location` +
  `player_position_in_ship`; asserts version-mismatched data is rejected (returns null).
- **`world_persist_restore_smoke.gd`** (main scene): travel to a derelict → mutate its
  `systems_manager` state → leave → return → assert the state is preserved (not regenerated)
  and the geometry is identical to the first visit.
- **`world_save_anywhere_smoke.gd`** (main scene): save **while aboard a derelict** → reload
  → assert `current_location`, the derelict's persisted state, and the player's scene
  position are all restored; save on the home ship → reload → assert unchanged home
  behavior.

## Explicitly out of scope (later sub-projects)

- Derelict objectives / hazards / extraction (sub-project #2).
- Player inventory + lootable items on ships, manual transfer (sub-project #3).
- Parts-gated, multi-visit derelict repair loop (sub-project #4).
- Autosave; multiple or named save slots; save-file migration.
- Phase 5 docking / ship-in-ship.

The per-ship slice is a summary-bag specifically so these add fields without reshaping the
world model.
