# ADR-0046: Real slot metadata on RunSnapshot (play time, location, world seed)

- **Status:** Accepted
- **Date:** 2026-07-06
- **Supersedes / amends:** extends ADR-0007 (save scope), ADR-0031 (multi-slot), ADR-0032 (migration)

## Context

The 2026-07-06 foundation audit found `SaveLoadService._index_run_slot` filling
`SaveSlotState` rows with placeholders because `RunSnapshot` carried no real
source data:

- `synaptic_sea_seed = int(player_position.x * 1000)` — a coordinate, not the seed
- `current_location = str(player_position.x)` — an X coordinate rendered as a location
- `play_time_seconds = float(saved_at_epoch)` — a Unix timestamp, not play time

The slot browser therefore displayed fabricated metadata for every save.

## Decision

Add three fields to `RunSnapshot` (per ADR-0007, a new field requires an ADR;
all three are current-run state, so no hub/meta scope creep):

1. **`play_time_seconds: float`** — accumulated in-run play time. Owned by the
   coordinator (`PlayableGeneratedShip.run_play_time_seconds`), ticked every
   `_process` frame **before the home/away branch split** so both branches
   count, and only while `playable_started and not slice_complete` (menu and
   post-death time excluded). Restored by `_apply_run_snapshot` so the clock
   resumes across load.
2. **`current_location: String`** — the active ship's `marker_id`, or `"home"`
   when aboard the hub. Stamped at snapshot build; re-derived live at every
   save (not restored — the load path re-derives from `current_ship`).
3. **`world_seed: int`** — the Synaptic Sea `world_seed` the run's marker field
   was generated from (`SynapticSeaWorld.world_seed`). Stamped at snapshot
   build; authoritative restore remains the world-save path
   (`SynapticSeaWorld.apply_summary`).

Schema bumps `gate2-current-run-3 → gate2-current-run-4` following the
ADR-0032 chain: `KNOWN_VERSIONS` gains the new entry, `TARGET_VERSION` and
`SaveLoadService.CURRENT_SLICE_VERSION` advance, and a new `_migrate_v3_to_v4`
step defaults the three fields for older saves (honest zeros/empties instead
of the old placeholders).

`_index_run_slot` reads the three real fields.

## Consequences

- Slot rows show true location, true play time, and the real world seed.
- Legacy saves migrate additively; the migration smokes reference
  `TARGET_VERSION` symbolically and required no changes.
- Validation: `slot_metadata_smoke.gd` (bundle) drives the production path —
  main scene boot → frames tick → `force_autosave_for_validation()` →
  `_index_run_slot` — and asserts row values plus snapshot round-trip.
