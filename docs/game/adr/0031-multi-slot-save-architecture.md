# ADR-0031: Multi-Slot Save Architecture

Date: 2026-06-25
Status: Accepted
Extends: ADR-0007 (single-ship RunSnapshot scope), ADR-0012 (world persistence)
Supersedes: the "single slot per run" phrasing in ADR-0007 for slot identity
(per-slot payload size, corruption backup, autosave rotation); the current-run
boundary itself is preserved.

## Context

REQ-012 (current-run save/load) and ADR-0012 (world save any-where) ship a
single-slot, current-run-only persistence layer. The Task 11 E2E package
requires manual/autosave/quicksave distinction, corruption backup, slot
listing, migration forward-compatibility, and a cloud-ready manifest. The
current single-slot design cannot satisfy any of those without becoming a god
service.

We must extend the persistence layer without breaking:

- REQ-012 current-run autosave sequence (autosave writes to the active slot,
  then load_current_run restores it).
- ADR-0012 world save any-where (`save_world` / `load_world`).
- ADR-0007 "no hub/meta/cross-run state" cut line.

## Decision

Adopt a slot-based persistence model where every persisted snapshot carries a
`slot_id` and a `slot_kind` (`manual` / `auto` / `quick` / `world`).

### Slot families

| Family | slot_id form | Path | Owner |
|---|---|---|---|
| World | `__world__` | `user://saves/world.json` | `SaveLoadService.save_world/load_world` (existing path aliased) |
| Manual | `slot_01`..`slot_06` | `user://saves/<slot_id>.json` | New `save_to_slot` / `load_from_slot` |
| Autosave | `autosave_a`..`autosave_c` | `user://saves/<slot_id>.json` | `AutosavePolicy.tick` routes through `save_to_slot` |
| Quicksave | `quicksave` | `user://saves/quicksave.json` | `quicksave` / `quickload` with 10 s cooldown |
| Death | `<slot_id>.death.json` | `user://saves/<slot_id>.death.json` | `PermadeathResolver` |

### Slot identity

`RunSnapshot` gains four new optional fields: `slot_id`, `slot_kind`,
`is_autosave`, `is_quicksave`, `parent_world_slot`. They are additive: the
existing `RunSnapshot.from_dict` ignores unknown keys (verified at
`scripts/systems/run_snapshot.gd:71-101`), so old single-slot saves load and
read back as `slot_id == ""`, `slot_kind == ""` — the smoke `save_load_service_smoke.gd`
round-trip stays green.

### Index file

`SaveIndexState` is the on-disk index at `user://saves/index.json`. It carries
`version`, `godot_version`, `updated_at`, and `slots: Array`. Each row is a
`SaveSlotState` summary (`slot_id`, `slot_kind`, `display_name`, `synapse_sea_seed`,
`player_class`, `current_location`, `objective_sequence`, `play_time_seconds`,
`saved_at`, `world_slot_id`, `corrupt`). `SaveLoadService.list_slots()` reads
this file and returns rows sorted by `saved_at` desc. The index is rewritten
on every save/delete; corruption is detected when a listed slot file is
missing on disk (flagged `corrupt=true`).

### Corruption backup

When `load_from_slot` finds a slot file that fails JSON parse, version match,
or summary apply, the service moves the bad file to
`user://saves/.corrupt/<slot_id>.<saved_at_epoch>.bak` and returns null. The
original is never silently deleted; the backup is the audit trail. The slot
remains in the index with `corrupt=true` so the menu can show it as
unloadable.

### Autosave policy

`AutosavePolicy` is a pure model. `tick(seconds, event_count)` returns true
when:

- (a) ≥ 90 in-game seconds since last autosave (cadence), OR
- (b) ≥ 8 events since last autosave (event pressure), OR
- (c) `force` is set (objective completion, manual autosave key).

A minimum 5 s real-time budget is enforced between autosaves. Rotation: the
3 autosave slots are written in `autosave_a` → `autosave_b` → `autosave_c` →
wrap order; oldest is overwritten when the 3rd save fires.

### Quicksave

`request_quicksave` writes to the active family's `quicksave` slot and sets a
`quicksave_cooldown` of 10 s. A second quicksave inside the cooldown is
rejected with a warning. `request_quickload` is always allowed (cooldown only
guards quicksave writes).

### Manual vs world

A manual slot embeds the same RunSnapshot shape (current-run-only per
ADR-0007). A world slot embeds the WorldSnapshot (multi-ship per ADR-0012).
Loading a manual slot into a coordinator that has world state does NOT
overwrite `visited_ships`; it only restores the active ship's RunSnapshot. The
slot index's `slot_kind` drives which schema is loaded.

### File I/O contract

- All paths use `user://` (resolves per-platform) — never absolute.
- Every save writes the slot file, then the index, then the cloud manifest.
  A failure to write the index still leaves the slot usable; the next save
  rebuilds the index from `list_slots`-friendly disk scan.
- No encryption, no compression, no network calls (out of scope per package
  plan; cloud adapter is a future ADR).

### Migration

`SaveMigrationService` (ADR-0030) owns a migration table. Old-version slots
are migrated forward transparently on load, the migrated form is written to
`<slot_id>.migrated.json`, and the in-memory snapshot is returned. The original
slot file is preserved until the user explicitly overwrites it.

## Consequences

Positive:

- Multi-slot UX, autosave rotation, and corruption backup land without
  breaking the existing single-slot API.
- Slot identity is data, not configuration: future HUD/menu/HUD work can
  read it without parsing file names.
- Cloud manifest is co-located with every save, so a future cloud adapter
  only needs to read `user://saves/.cloud/<slot_id>.manifest.json`.

Negative / tradeoffs:

- Index file adds a second write per save (mitigated: index write is async
  best-effort; slot file is the source of truth).
- Migration adds a "two files for one logical save" situation
  (`slot.json` + `slot.migrated.json`). We mitigate by only writing the
  migrated form when the user actually loads an old save.
- Autosave rotation can overwrite an autosave slot the user might want to
  keep. We mitigate by saving the previous autosave as `autosave_b`
  (preserved until the next autosave) so the player always has at least
  the two most recent autosaves available.

## Affected documents

- `docs/game/features/save_load.md` — REQ-SL-001..012 rows added.
- `docs/game/adr/0007-save-load-service-scope.md` — patched to acknowledge
  slot identity (the "current-run only" boundary stays intact).
- `docs/game/06_validation_plan.md` — `SAVE SLOT STATE PASS`,
  `SAVE MIGRATION SERVICE PASS`, `AUTOSAVE POLICY PASS`,
  `MAIN PLAYABLE MULTISLOT SAVE PASS` registered.
- `docs/game/07_risk_register.md` — RISK-009 (corruption data loss)
  added.
- `docs/game/balance/save-load-persistence.md` — tuning notes for autosave
  cadence and slot retention.

## Verification

- All four smoke markers in this package's verification section pass.
- Existing REQ-012 / autosave-sequence / world-save-anywhere / docking-persistence
  smokes stay green (autosave slot alias preserves their `current_run.json`
  invariant).
- `scripts/systems/run_snapshot.gd:from_dict` still ignores unknown keys,
  so old saves round-trip without migration.
- No new `ERROR:`/`WARNING:` lines from any of the new scripts under the
  focused smoke runs (filtered allowlist in `docs/game/06_validation_plan.md`).