# ADR-0032: Migration, Permadeath/Epitaph, and Cloud-Ready Manifest

Date: 2026-06-25
Status: Accepted
Extends: ADR-0007 (current-run only), ADR-0029 (slot identity).

## Context

The Task 11 E2E package needs three persistence-side capabilities that
current ADRs do not define:

1. **Save migration forward-compatibility.** Today's `RunSnapshot.from_dict`
   rejects any save whose `slice_version` does not match (good for
   corruption, bad for legitimate evolution: e.g. Phase 3 player progression
   added `player_progression_summary` to v2 saves, but no v1 save can ever
   load again).
2. **Permadeath / death flow.** Project-Zomboid-style persistence expects
   death to be preserved (epitaph, cause, timestamp) and the slot to refuse
   reloads until a new run is started. ADR-0007 only specifies "delete save
   on run completion"; it does not specify what happens at the player's
   death in a permadeath world.
3. **Cloud-ready manifest.** A future Steam Cloud / iCloud / GOG Galaxy
   adapter will need a structured sidecar per slot carrying the device id,
   build id, schema version, payload sha, and sync eligibility. We do not
   ship the cloud SDK, but we ship the manifest so a future adapter only
   needs to walk `user://saves/.cloud/<slot_id>.manifest.json`.

## Decision

### 1. SaveMigrationService

`scripts/systems/save_migration_service.gd` is a pure `RefCounted`. It owns
a `MIGRATIONS` table:

```
{
  "gate2-current-run-1": _migrate_v1_to_v2,
  "gate2-current-run-2": _migrate_v2_to_v3,
  ...
}
```

Each entry takes the parsed Dictionary and returns a new Dictionary with
the target version's keys. The migration is deterministic: given the same
input, it always produces the same output. Migrations are pure (no scene
tree, no engine time). New migration steps are appended; old steps are never
removed.

The service is invoked from `SaveLoadService.load_from_slot` BEFORE
`RunSnapshot.from_dict`. If the slot's `slice_version` is older than the
current `CURRENT_SLICE_VERSION`, the migration chain is applied; the
migrated form is written to `<slot_id>.migrated.json` (so the player can
inspect the upgrade). If the slot is newer than the current version, the
service returns null (a forward-only save cannot be downgraded).

### 2. PermadeathResolver

`scripts/systems/permadeath_resolver.gd` is a pure `RefCounted`. When the
coordinator detects player death:

1. Build an epitaph Dictionary: `{slot_id, cause, epitaph, died_at, run_time_seconds, final_objective_sequence}`.
2. Write `<slot_id>.death.json`.
3. Mark the slot in the index as `frozen=true`.
4. Subsequent `load_from_slot(slot_id)` returns null while the death file exists.

Starting a new run with a different `slot_id` is allowed while the
death-frozen slot persists; the player can return to view the epitaph in
the menu. The death file is preserved (not auto-deleted) until the player
explicitly chooses "Forget this death" from the menu (out of scope for this
package, but the seam is in place).

The resolver does NOT touch hub/meta state (ADR-0007 still in force). The
epitaph is purely a per-slot record.

### 3. CloudManifestState

`scripts/systems/cloud_manifest_state.gd` is a pure `RefCounted` data class:

```
{
  device_id: String,         # sha256 of OS.user_data_dir or similar stable token
  build_id: String,           # ProjectSettings.get_setting("application/config/version")
  schema_version: String,     # mirrors CURRENT_SLICE_VERSION
  payload_sha256: String,     # sha256 of the slot file bytes
  payload_size_bytes: int,
  created_at: String,         # ISO 8601
  sync_eligible: bool,        # false when the save is migration-temp or corrupt
  cloud_provider: String,     # "stub" in this package; future Steam / iCloud values live here
}
```

The manifest is written to `user://saves/.cloud/<slot_id>.manifest.json`
on every successful save. On load, the service recomputes
`payload_sha256` and refuses to load if the manifest's sha does not match
the slot file (defense against silent FS tampering). Sync eligibility
defaults to true; migration-temp files and corrupt files set it false so a
future cloud adapter skips them.

## Consequences

Positive:

- Future save schema changes can be deployed without orphaning older saves.
- Death flow is data-driven, not a hard-coded branch in the coordinator.
- Cloud adapter work is decoupled: a future PR only needs to read the
  manifest, not the slot file's internal schema.

Negative / tradeoffs:

- Migration adds a "two files for one logical save" situation
  (`slot.json` + `slot.migrated.json`). Mitigated: the original is the
  source of truth; the migrated form is only written when the player
  actually loads an old save.
- Manifest writes add a third disk operation per save. Mitigated: the
  manifest is a small (≤ 1 KB) JSON file; failure to write the manifest
  logs a warning but does not fail the save.
- Death file retention is open-ended. Future ADR will define the
  "forget this death" UX; until then the death file accumulates.

## Affected documents

- `docs/game/features/save_load.md` — REQ-SL-007 / REQ-SL-009 / REQ-SL-010
  rows.
- `docs/game/06_validation_plan.md` — smoke registration.
- `docs/game/07_risk_register.md` — RISK-010 (death data accumulation).

## Verification

- `scripts/validation/save_migration_service_smoke.gd` exercises:
  - v1 → v2 migration of a save without `player_progression_summary`.
  - Forward-only rejection of a newer-version save.
  - Death-record write/load round-trip (frozen slot rejects).
- The `SAVE MIGRATION SERVICE PASS` marker is the spec contract.
- All four package markers (`SAVE SLOT STATE PASS`,
  `SAVE MIGRATION SERVICE PASS`, `AUTOSAVE POLICY PASS`,
  `MAIN PLAYABLE MULTISLOT SAVE PASS`) pass under the regression bundle.