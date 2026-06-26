# Save/Load Persistence Package — Contract and Gap Review

Package: `docs/game/build-plans/11-save-load-persistence-e2e.md`
Author: synapse_seaworker (Task 11, board `synaptic-sea-e2e-systems`)
Date: 2026-06-25

## Existing seams to extend (not replace)

| File | Role | Action |
|---|---|---|
| `scripts/systems/save_load_service.gd` | Single-slot current-run save/load (REQ-012). Owns `user://saves/current_run.json`. Provides `save_current_run`, `load_current_run`, `save_world`, `load_world`, `delete_current_run`, `has_save`, `_ensure_save_dir`. | **Extend, do not replace.** Add `save_to_slot(slot_id)`, `load_from_slot(slot_id)`, `delete_slot(slot_id)`, `list_slots()`, `backup_corrupt_slot(slot_id)`, `has_slot(slot_id)`, `quicksave()`, `quickload()`, `autosave_tick(...)`. The single-slot API stays as the world-save alias (`slot_id == WORLD_SLOT_ALIAS`) so ADR-0012 and existing smokes stay green. |
| `scripts/systems/run_snapshot.gd` | Pure data, 8 summaries, version markers. | **Keep.** Add `slot_kind`, `slot_id`, `is_autosave`, `is_quicksave`, `death_recorded_at`, `parent_world_slot` fields. New fields are pure additive data; `from_dict` ignores unknown keys so old saves load. |
| `scripts/systems/world_snapshot.gd` | Pure data, multi-ship world persistence (ADR-0012). | **Keep.** Embeds a single `home_ship` `RunSnapshot` (per ADR-0007). The world slot is itself an alias-slot in the new `SaveIndexState`, so the existing `save_world/load_world` path becomes `slot_id == "__world__"`. |
| `scripts/procgen/playable_generated_ship.gd` | Scene coordinator that owns the service and the per-model `apply_summary` calls. | **Extend.** Add `request_save_to_slot`, `request_load_from_slot`, `request_quicksave`, `request_quickload`, `request_autosave_tick`, `record_player_death(cause)`. Existing `request_save` / `request_load` route to the active autosave slot so all prior REQ-012 smokes keep passing. |
| `scripts/validation/save_load_service_smoke.gd` | REQ-012 single-slot round-trip (marker `SAVE LOAD SERVICE PASS round_trip=true version_match=true summaries=8`). | **Keep unchanged.** Contract: `from_dict` ignores unknown fields so the existing marker stays valid after we add new slot metadata to `RunSnapshot`. |
| `scripts/validation/main_playable_slice_save_load_smoke.gd` | REQ-012 main-scene round-trip. | **Keep unchanged.** Same reasoning. |
| `scripts/validation/req012_autosave_sequence_smoke.gd` | Auto-save ordering assertion. | **Keep unchanged.** New `AutosavePolicy` records its triggers into the same `current_run.json` path (autosave overwrites manual in the active autosave slot), preserving the legacy `has_save=true` invariant after objective-1 completion. |
| `docs/game/adr/0007-save-load-service-scope.md` | Current-run-only boundary. | **Patch (small).** Add a clause acknowledging slot identity (`slot_id`), autosave/quicksave as physical slot aliases, and explicit permadeath flow. ADR-0007's "single slot per run" is reinterpreted as "single active logical run, expressed through the autosave slot, with sibling slots for manual + quicksave + world." |
| `docs/game/adr/0012-world-persistence-model.md` | World save any-where. | **Patch (small).** Note the new `__world__` slot alias and that the world save participates in the slot index alongside manual/autosave slots. |

## Missing files (to be added by this package)

| Path | Role |
|---|---|
| `scripts/systems/save_slot_state.gd` | Pure data class representing one row in the save index. `slot_id`, `slot_kind` ("manual"/"auto"/"quick"/"world"), `display_name`, `synapse_sea_seed`, `player_class`, `current_location`, `objective_sequence`, `play_time_seconds`, `saved_at`, `world_slot_id` (for embedded ship slots inside a world), `corrupt` (bool). |
| `scripts/systems/save_index_state.gd` | Pure data class representing the on-disk index file (`user://saves/index.json`). `version`, `godot_version`, `updated_at`, `slots: Array[Dictionary]`. |
| `scripts/systems/save_migration_service.gd` | Pure model. Owns the migration table. Each entry maps `from_version -> to_version` and applies a transform on a parsed Dictionary. `migrate(parsed, from_version) -> {dict, to_version}` is deterministic. |
| `scripts/systems/autosave_policy.gd` | Pure model. Tracks last autosave wall-clock + game-time + scene-tick + event-count. `tick(seconds, event_count) -> bool` returns true when a save should fire. Owns the autosave-slot rotation (current/previous/older) and a 5-second minimum-interval budget. |
| `scripts/systems/permadeath_resolver.gd` | Pure model. Records death events, freezes the run as an epitaph (`death_epitaph.json`), and refuses reloads from a death-frozen slot until a new run is started. |
| `scripts/systems/cloud_manifest_state.gd` | Pure data class. Cloud-ready metadata (device id, build id, schema version, sync eligibility). NOT a cloud SDK; the manifest is what a future Steam/Cloud-Save adapter would upload. |
| `scripts/ui/save_load_menu.gd` | Node-based menu seam. Reads `SaveLoadService.list_slots()`, presents manual/quick/autosave rows, exposes `select_slot_for_load`, `confirm_save_to_slot`, `confirm_quicksave`, `confirm_delete`. SceneTree-free APIs so it can be tested headlessly. |
| `scripts/validation/save_slot_state_smoke.gd` | PASS marker: `SAVE SLOT STATE PASS` |
| `scripts/validation/save_migration_service_smoke.gd` | PASS marker: `SAVE MIGRATION SERVICE PASS` |
| `scripts/validation/autosave_policy_smoke.gd` | PASS marker: `AUTOSAVE POLICY PASS` |
| `scripts/validation/main_playable_slice_multislot_save_smoke.gd` | PASS marker: `MAIN PLAYABLE MULTISLOT SAVE PASS` |
| `docs/game/balance/save-load-persistence.md` | Tuning notes: autosave interval (90 s of in-game time), 3 autosave slots, quicksave cooldown (10 s), corruption backup retention (1 per slot). |

## ADR updates to issue

| ADR | Topic |
|---|---|
| ADR-0031 | Multi-slot save architecture (manual/autosave/quicksave/world slot families, index file, slot identity, per-slot corruption backup). |
| ADR-0032 | Migration service, permadeath/epitaph flow, cloud-manifest schema. Adds a death flow that preserves the death record but refuses reload, and a manifest class that's cloud-SDK-agnostic. |

## Non-conflicting decisions

- Existing REQ-012 single-slot path stays green. The autosave slot alias = the legacy `current_run.json` path so existing smokes (REQ-012, autosave sequence, world save anywhere, docking persistence) do not need to change.
- `RunSnapshot.from_dict` ignores unknown keys (existing behaviour); we add new optional fields (`slot_id`, `slot_kind`, `is_autosave`, `is_quicksave`, `death_recorded_at`, `parent_world_slot`) without breaking old saves.
- `WorldSnapshot.WORLD_SLICE_VERSION` stays at `"world-4"`; we add a sibling alias-slot `"__world__"` in the slot index rather than bumping versions.

## Stop/block reasoning

No blocking conditions named in the package plan apply. Existing ADRs (`0007`, `0012`) extend rather than conflict. We are not introducing a cloud SDK, encryption, compression, or cross-device sync — those are explicitly out of scope.